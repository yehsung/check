// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift @ 1b8260d (deleteAccount 순서 — 290–345)
// 원본: Sources/CheckMobileKit/Session/MobilePasswordResetStore.swift @ 1b8260d (입력 정규화·쿨다운·문구 — 40–60, 108–137, 166–200, 355–389)
// 원본: Sources/CheckCore/SupabaseWorkHTTP.swift @ 1b8260d (serviceError 실패 분류 — 90–188)
// 원본: Sources/CheckCore/SupabaseWorkService.swift @ 1b8260d (passwordRecoveryError·retryAfterSeconds — 1383–1432)
// 원본: Sources/CheckMobileKit/Me/MeText.swift @ 1b8260d (계정 삭제 문구 — 885–925)
// 원본: Sources/CheckMobileKit/Session/MobileDeviceService.swift @ 1b8260d (isMissingFunction — 91–99: 삭제 RPC 의 404 를 '아직 준비 안 됨'으로)
//
// 웹 계정 삭제(/delete-account)의 **순수** 부분 — 설정 읽기 · 입력 정규화 · HTTP 실패 분류 · 화면 상태기계 · 문구.
// 네트워크는 여기서 하지 않는다(lib/delete-account-client.ts 가 fetch 를 주입받아 한다). 그래서 `node --test` 로 실서버 없이 잰다.
//
// 설계(G §2-3 W2-i · E§9.6): 요청 폼이 아니라 **본인 확인 뒤 즉시 삭제**다.
//   흐름 A(비밀번호 앎): 이메일·비밀번호 → 그 자리에서 영구 삭제.
//   흐름 B(비밀번호 모름): 이메일 → 6자리 코드 메일(앱의 비밀번호 재설정과 같은 메일) → 코드 → 영구 삭제.
//   흐름 C(메일함도 잃음): 지울 수 없다고 밝히고 문의 경로만 준다(운영자가 손으로 지우는 길은 사칭 위험 때문에 두지 않는다).
// 자유 입력 요청 폼이 없으니 남의 계정 삭제 요청·운영자 메일함 스팸이 원천적으로 없다.

/**
 * Play 등록정보에 보이는 이름 그대로(Play 요구: "app or developer name as it appears on your store listing").
 * ⚠️ 개발자 이름은 Play Console 계정 이름 기록(2026-10-28, "team: watermelon")에서 왔다 — 등록정보 공개 화면에서 사용자가 확인할 값.
 */
export const STORE_LISTING = { appName: '아잉체크', developerName: 'team: watermelon' } as const;

/** 메일 코드 자릿수(MobilePasswordResetStore.codeLength). */
export const CODE_LENGTH = 6;
/** 첫 발송 뒤 다시 받기까지(초) — 첫 메일이 안 오는 일이 실제로 있어 1분을 붙잡지 않는다(앱과 같은 값). */
export const FIRST_RESEND_DELAY_SECONDS = 5;
/** 두 번째 발송부터의 쿨다운(초). 서버가 남은 초를 안 주는 429 도 이 값으로 잠근다(0 으로 지어내면 버튼이 바로 열려 429 를 또 맞는다). */
export const RESEND_COOLDOWN_SECONDS = 60;
/** 쿨다운 상한(초) — 서버가 터무니없는 값을 줘도 화면이 영영 잠기지 않게(앱 startCooldown 의 600). */
export const MAX_COOLDOWN_SECONDS = 600;

// ---------------------------------------------------------------------------------------------------------------
// 설정 — 프로젝트 주소와 anon 키(앱에도 실려 나가는 공개 값). 서비스 롤(관리자) 키는 여기 올 일이 없다.

export interface DeleteAccountConfig {
  /** 끝 '/' 를 뗀 Supabase 프로젝트 주소. */
  readonly url: string;
  readonly anonKey: string;
}

/**
 * 환경 변수 두 값 → 설정. 하나라도 없거나 이상하면 null(화면은 "지금은 웹에서 지울 수 없어요" + 앱·문의 경로).
 * **운영 주소·키를 코드에 적지 않는다** — 값은 배포 환경(Vercel NEXT_PUBLIC_*)이 준다.
 * https 만 받는다. 예외는 내 컴퓨터(localhost·127.0.0.1)의 http — 로컬 `supabase start` 시험 경로다.
 */
export function readConfig(rawUrl: string | undefined, rawKey: string | undefined): DeleteAccountConfig | null {
  const urlText = (rawUrl ?? '').trim();
  const anonKey = (rawKey ?? '').trim();
  if (!urlText || !anonKey || /\s/.test(anonKey)) return null;
  let parsed: URL;
  try {
    parsed = new URL(urlText);
  } catch {
    return null;
  }
  const local = parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
  if (parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && local)) return null;
  if (parsed.search || parsed.hash || parsed.username || parsed.password) return null;
  const url = `${parsed.origin}${parsed.pathname}`.replace(/\/+$/, '');
  return { url, anonKey };
}

// ---------------------------------------------------------------------------------------------------------------
// 입력 정규화(MobilePasswordResetStore 의 nonisolated static 그대로)

/** 앞뒤 공백·줄바꿈을 걷고 소문자로. */
export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

/** 이메일 형식의 **최소** 검증 — "@ 도 없는 입력"으로 왕복(과 메일 쿨다운)을 태우지 않기 위한 사전 필터. RFC 를 흉내 내지 않는다. */
export function isPlausibleEmail(email: string): boolean {
  if (/\s/.test(email)) return false;
  const parts = email.split('@');
  if (parts.length !== 2 || parts[0].length === 0) return false;
  const domain = parts[1];
  return domain.includes('.') && !domain.startsWith('.') && !domain.endsWith('.');
}

/** 메일에서 복사하면 공백·하이픈이 섞여 오므로 ASCII 숫자만 남긴다. */
export function normalizeCode(raw: string): string {
  return raw.replace(/[^0-9]/g, '');
}

// ---------------------------------------------------------------------------------------------------------------
// HTTP 실패 분류 — SupabaseWorkHTTP.serviceError + passwordRecoveryError + AuthErrorRules.classify 를 웹 흐름에 필요한 만큼.

export type Failure =
  /** fetch 자체가 실패했다(연결 끊김 · CORS 거절 · 주소 오류). 응답이 없으니 서버가 무엇을 했는지 모른다. */
  | { readonly kind: 'network' }
  /** 5xx — 무료 플랜 일시정지·배포 중 같은 일시 장애. */
  | { readonly kind: 'server'; readonly status: number }
  | { readonly kind: 'rateLimited'; readonly retryAfterSeconds: number | null }
  /** anon 키가 틀렸다 — 사용자가 아니라 배포 설정이 잘못됐다. */
  | { readonly kind: 'config' }
  /** 서버가 함수·표를 모른다(PGRST202 "… in the schema cache"). 웹이 서버 배포보다 먼저 나간 창. */
  | { readonly kind: 'schemaMissing' }
  | { readonly kind: 'sessionExpired' }
  /** GoTrue "Invalid login credentials" — 이메일이 없는지 비밀번호가 틀렸는지 **가르지 않는다**(계정 유무를 흘리지 않는다). */
  | { readonly kind: 'wrongCredentials' }
  | { readonly kind: 'emailNotConfirmed' }
  /** 재설정 코드가 틀렸거나 만료됐다(GoTrue 는 둘 다 같은 403 otp_expired 를 준다). */
  | { readonly kind: 'codeRejected' }
  | { readonly kind: 'rejected'; readonly status: number };

/** 실패를 낸 왕복의 종류. 재설정(recover·verify)만 GoTrue 문구를 한 번 더 좁힌다(SupabaseWorkService.passwordRecoveryError). */
export type CallKind = 'password' | 'recovery' | 'rpc' | 'storage' | 'logout';

/**
 * "…after 51 seconds." 에서 51. **정규식 대신 'second' 앞을 뒤에서 훑는다**(문구가 GoTrue 버전마다 조금씩 달라져 왔다 —
 * "this after N seconds" / "N seconds"). 'second' 바로 앞의 숫자 뭉치만 취하고, 없으면 null(0 이면 재시도가 바로 열린다).
 */
export function retryAfterSeconds(lowercasedMessage: string): number | null {
  const at = lowercasedMessage.indexOf('second');
  if (at < 0) return null;
  const digits: string[] = [];
  for (let i = at - 1; i >= 0; i--) {
    const ch = lowercasedMessage[i];
    if (ch >= '0' && ch <= '9') digits.push(ch);
    else if (digits.length > 0) break;
  }
  if (digits.length === 0) return null;
  return Number(digits.reverse().join(''));
}

interface ErrorBody {
  message?: unknown;
  msg?: unknown;
  error_description?: unknown;
  error?: unknown;
  error_code?: unknown;
  code?: unknown;
}

const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v.trim() : null);

/** 2xx 가 아닌 응답 → 실패 갈래. 본문은 글자 그대로 받는다(JSON 이 아니어도 된다). */
export function classifyHttpFailure(status: number, bodyText: string, call: CallKind): Failure {
  const rawBody = bodyText.toLowerCase();
  // INV-SupabaseWorkHTTP-d4703379 이식: 상태코드 게이트를 본문 메시지 폴딩보다 **먼저** 건다. GoTrue 는 5xx·429 에도
  //   {"msg":…} 본문을 싣는데, 그 문구로 접으면 일시 장애(일시정지·레이트리밋)가 "비밀번호가 틀렸다" 같은 확정 실패로 둔갑한다.
  if (status >= 500) return { kind: 'server', status };
  if (status === 429) return { kind: 'rateLimited', retryAfterSeconds: retryAfterSeconds(rawBody) };

  let body: ErrorBody | null = null;
  try {
    const parsed: unknown = JSON.parse(bodyText);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) body = parsed as ErrorBody;
  } catch {
    body = null;
  }
  if (!body) {
    if (status === 401) return { kind: 'sessionExpired' };
    return call === 'rpc' && status === 404 ? { kind: 'schemaMissing' } : { kind: 'rejected', status };
  }

  const message = [body.message, body.msg, body.error_description, body.error].map(str).find((m) => m !== null) ?? null;
  const errorCode = str(body.error_code) ?? (typeof body.code === 'string' ? str(body.code) : null);
  const lowered = [message, errorCode].filter((x): x is string => x !== null).join(' ').toLowerCase();

  if (lowered.includes('schema cache') || lowered.includes('could not find the table')) return { kind: 'schemaMissing' };
  if (lowered.includes('invalid api key')) return { kind: 'config' };
  if (lowered.includes('jwt expired') || lowered.includes('pgrst301') || (status === 401 && (lowered.includes('jwt') || lowered.includes('expired')))) {
    return { kind: 'sessionExpired' };
  }
  if (lowered.includes('refresh token') || lowered.includes('refresh_token') || lowered.includes('invalid_grant')) return { kind: 'sessionExpired' };
  if (lowered.includes('invalid login credentials') || lowered.includes('invalid_credentials')) return { kind: 'wrongCredentials' };
  if (lowered.includes('email not confirmed') || lowered.includes('email_not_confirmed')) return { kind: 'emailNotConfirmed' };

  if (call === 'recovery') {
    // 재설정 흐름 전용 재분류(passwordRecoveryError) — 공용 분류가 모르는 GoTrue 문구 셋.
    if (lowered.includes('rate limit') || lowered.includes('security purposes')) {
      return { kind: 'rateLimited', retryAfterSeconds: retryAfterSeconds(lowered) };
    }
    if (lowered.includes('token has expired or is invalid') || lowered.includes('otp_expired') || lowered.includes('verify requires')) {
      return { kind: 'codeRejected' };
    }
    if (lowered.includes('invalid jwt') || lowered.includes('bad_jwt') || lowered.includes('missing sub claim')) return { kind: 'sessionExpired' };
  }
  if (status === 401) return { kind: 'sessionExpired' };
  // 앱 MobileDeviceRPC.isMissingFunction 의 `.invalidResponse(404)` 갈래 — 함수를 모르는 서버가 PGRST202 문구 없이(본문이 JSON 이
  //   아니거나 메시지가 없게) 404 만 줄 때도 "아직 준비 안 됨"이다. 삭제 RPC 에서만 이렇게 읽는다(앱도 그 호출에만 건다 — 로그인·코드의
  //   404 는 그냥 거절). 메시지가 있는 404 는 앱처럼 거절로 둔다(.authMessage → fatal → rejected). JSON 이 아닌 404 는 위에서 같은 판정.
  if (call === 'rpc' && status === 404 && message === null) return { kind: 'schemaMissing' };
  return { kind: 'rejected', status };
}

// ---------------------------------------------------------------------------------------------------------------
// 문구 — 앱(MeText · MobilePasswordResetText · MobileLoadText)과 뜻이 같은 것은 같은 문장. 서버 원문(영어)은 절대 싣지 않는다.

export const TEXT = {
  checkConnection: '연결을 확인하고 다시 시도해 주세요',
  invalidEmail: '이메일 주소를 확인해주세요',
  passwordRequired: '비밀번호를 입력해 주세요',
  invalidCode: '메일로 받은 6자리 숫자를 입력해주세요',
  acknowledgeRequired: '되돌릴 수 없다는 안내를 확인하고 체크해 주세요',
  wrongCredentials: '이메일 또는 비밀번호가 맞지 않아요',
  emailNotConfirmed: '가입 코드 확인을 마치지 않은 계정이에요 · 메일 코드로 확인해 주세요',
  signInFailed: '본인 확인을 하지 못했어요 · 다시 시도해 주세요',
  sent: '메일을 보냈어요 · 오지 않으면 주소를 확인해주세요',
  alreadySent: '메일을 이미 보냈어요 · 메일함을 확인해주세요',
  cooldown: '조금 뒤에 다시 받을 수 있어요',
  sendFailed: '메일을 보내지 못했어요 · 주소를 확인하고 다시 시도해주세요',
  codeRejected: '코드가 맞지 않거나 만료됐어요 · 다시 받기를 눌러주세요',
  sessionExpired: '본인 확인이 만료됐어요 · 처음부터 다시 시도해 주세요',
  rateLimited: '잠시 후 다시 시도해주세요',
  serverNotReady: '계정 삭제가 아직 서버에 준비되지 않았어요 · 잠시 뒤 다시 시도해 주세요',
  deleteRejected: '계정을 지우지 못했어요 · 잠시 뒤 다시 시도해 주세요',
  deleteRejectedNewCode: '계정을 지우지 못했어요 · 새 코드를 받아 다시 시도해 주세요',
  checkConnectionNewCode: '연결을 확인하고 새 코드를 받아 다시 시도해 주세요',
  unavailable: '지금은 웹에서 계정을 지울 수 없어요 · 앱에서 지우거나 아래 문의 경로로 알려 주세요',
  sendingCode: '코드 보내는 중…',
  deleting: '확인하고 지우는 중…',
} as const;

/** 실패가 난 단계. 같은 갈래라도 단계마다 할 일이 달라 문장이 갈린다. */
export type Stage = 'signIn' | 'sendCode' | 'verify' | 'delete';

export function failureMessage(f: Failure, stage: Stage): string {
  switch (f.kind) {
    case 'network':
    case 'server':
      return TEXT.checkConnection;
    case 'rateLimited':
      if (stage === 'sendCode') return TEXT.alreadySent;
      if (stage === 'verify') return TEXT.cooldown;
      // 로그인·삭제의 429 — 앱(MobileSessionStore.deleteAccount)은 일시 장애를 한데 접어 '연결을 확인'이라고 하지만, 웹은 앱 공용 문장
      //   AuthErrorRules.message(.rateLimited)를 쓴다(일부러 갈랐다): 연결은 멀쩡한데 '연결을 확인'이라 하면 곧바로 다시 눌러 제한만 늘린다.
      return TEXT.rateLimited;
    case 'config':
      return TEXT.unavailable;
    case 'schemaMissing':
      return stage === 'delete' ? TEXT.serverNotReady : TEXT.unavailable;
    case 'sessionExpired':
      return stage === 'verify' ? TEXT.codeRejected : TEXT.sessionExpired;
    case 'wrongCredentials':
      return stage === 'signIn' ? TEXT.wrongCredentials : TEXT.signInFailed;
    case 'emailNotConfirmed':
      return TEXT.emailNotConfirmed;
    case 'codeRejected':
      return TEXT.codeRejected;
    case 'rejected':
      if (stage === 'sendCode') return TEXT.sendFailed;
      if (stage === 'verify') return TEXT.codeRejected;
      if (stage === 'delete') return TEXT.deleteRejected;
      return TEXT.signInFailed;
  }
}

/**
 * 흐름 B 에서 본인 확인(코드)은 통과했는데 삭제가 실패했을 때. 그 코드는 이미 쓰였으니 **새 코드**가 필요하다고 말한다
 * (같은 코드를 다시 넣으면 반드시 "코드가 맞지 않거나 만료됐어요"를 보게 된다).
 */
export function codeModeDeleteMessage(f: Failure): string {
  if (f.kind === 'schemaMissing') return TEXT.serverNotReady;
  if (f.kind === 'network' || f.kind === 'server') return TEXT.checkConnectionNewCode;
  return TEXT.deleteRejectedNewCode;
}

// ---------------------------------------------------------------------------------------------------------------
// 화면 상태기계 — 입력 → (코드 받기) → 확인 → 삭제 → 완료/오류. 순수 함수라 시각은 이벤트가 들고 온다(now = epoch ms).

export type Mode = 'password' | 'code';
export type Phase = 'editing' | 'sendingCode' | 'deleting' | 'deleted';

export interface Notice {
  readonly text: string;
  readonly tone: 'info' | 'error';
}

export interface DeleteAccountState {
  readonly mode: Mode;
  readonly phase: Phase;
  /** 입력 칸 그대로(정규화는 보낼 때). */
  readonly email: string;
  readonly password: string;
  readonly code: string;
  /** "되돌릴 수 없다"를 확인했다는 체크. 삭제 버튼은 이것 없이 열리지 않는다. */
  readonly acknowledged: boolean;
  /** 코드를 보낸 주소(정규화). null 이면 흐름 B 의 첫 화면(코드 받기)이다. */
  readonly codeSentTo: string | null;
  readonly sendCount: number;
  /** 다시 받기가 열리는 시각(epoch ms). null = 잠금 없음. */
  readonly resendAvailableAt: number | null;
  readonly notice: Notice | null;
}

export const initialState: DeleteAccountState = {
  mode: 'password',
  phase: 'editing',
  email: '',
  password: '',
  code: '',
  acknowledged: false,
  codeSentTo: null,
  sendCount: 0,
  resendAvailableAt: null,
  notice: null,
};

export type DeleteAccountEvent =
  | { readonly type: 'mode'; readonly mode: Mode }
  | { readonly type: 'email'; readonly value: string }
  | { readonly type: 'password'; readonly value: string }
  | { readonly type: 'code'; readonly value: string }
  | { readonly type: 'acknowledge'; readonly value: boolean }
  /** 흐름 B 에서 보낸 주소를 고치러 첫 화면으로. */
  | { readonly type: 'editEmail' }
  | { readonly type: 'requestCode'; readonly now: number }
  | { readonly type: 'codeSent'; readonly now: number }
  | { readonly type: 'codeSendFailed'; readonly failure: Failure; readonly now: number }
  | { readonly type: 'submit' }
  | { readonly type: 'deleted' }
  | { readonly type: 'deleteFailed'; readonly failure: Failure; readonly stage: Stage };

export function isBusy(s: DeleteAccountState): boolean {
  return s.phase === 'sendingCode' || s.phase === 'deleting';
}

/** 다시 받기까지 남은 초(올림). 0 이면 열림. */
export function resendSecondsLeft(s: DeleteAccountState, now: number): number {
  if (s.resendAvailableAt === null) return 0;
  return Math.max(0, Math.ceil((s.resendAvailableAt - now) / 1000));
}

/** [코드 받기]·[다시 받기]를 누를 수 있는가 — 빈 요청으로 서버 메일 제한을 태우지 않는다. */
export function canRequestCode(s: DeleteAccountState, now: number): boolean {
  return s.mode === 'code' && s.phase === 'editing' && isPlausibleEmail(normalizeEmail(s.email)) && resendSecondsLeft(s, now) === 0;
}

/** [계정 영구 삭제]를 누를 수 있는가(버튼 활성 전용 — 막는 일은 submit 이 한 번 더 한다). */
export function canSubmit(s: DeleteAccountState): boolean {
  if (s.phase !== 'editing' || !s.acknowledged) return false;
  if (s.mode === 'password') return isPlausibleEmail(normalizeEmail(s.email)) && s.password.length > 0;
  return s.codeSentTo !== null && normalizeCode(s.code).length === CODE_LENGTH;
}

/** submit 이 'deleting' 으로 넘긴 뒤 클라이언트가 보낼 값. 'deleting' 이 아니면 null. */
export type DeletionRequest =
  | { readonly mode: 'password'; readonly email: string; readonly password: string }
  | { readonly mode: 'code'; readonly email: string; readonly code: string };

export function deletionRequest(s: DeleteAccountState): DeletionRequest | null {
  if (s.phase !== 'deleting') return null;
  if (s.mode === 'password') return { mode: 'password', email: normalizeEmail(s.email), password: s.password };
  if (s.codeSentTo === null) return null;
  return { mode: 'code', email: s.codeSentTo, code: normalizeCode(s.code) };
}

const err = (text: string): Notice => ({ text, tone: 'error' });
const info = (text: string): Notice => ({ text, tone: 'info' });

function cooldownAt(now: number, seconds: number): number {
  return now + Math.min(Math.max(seconds, 1), MAX_COOLDOWN_SECONDS) * 1000;
}

export function reduce(s: DeleteAccountState, e: DeleteAccountEvent): DeleteAccountState {
  // 지운 뒤에는 아무것도 받지 않는다(같은 탭에서 다른 계정을 또 지우려면 새로 연다 — 완료 화면이 남아 있어야 한다).
  if (s.phase === 'deleted') return s;
  switch (e.type) {
    case 'mode':
      if (isBusy(s) || s.mode === e.mode) return s;
      // 쿨다운(sendCount·resendAvailableAt)은 갈래를 바꿔도 남긴다 — 왔다 갔다로 메일 제한을 우회하지 않게.
      return { ...s, mode: e.mode, password: '', code: '', codeSentTo: null, notice: null };
    case 'email':
      if (isBusy(s) || s.codeSentTo !== null) return s;
      return { ...s, email: e.value };
    case 'password':
      if (isBusy(s)) return s;
      return { ...s, password: e.value };
    case 'code':
      if (isBusy(s)) return s;
      return { ...s, code: e.value };
    case 'acknowledge':
      if (isBusy(s)) return s;
      return { ...s, acknowledged: e.value };
    case 'editEmail':
      if (isBusy(s)) return s;
      return { ...s, codeSentTo: null, code: '', notice: null };
    case 'requestCode': {
      if (s.mode !== 'code' || isBusy(s)) return s;
      const email = normalizeEmail(s.email);
      if (!isPlausibleEmail(email)) return { ...s, email, notice: err(TEXT.invalidEmail) };
      // 쿨다운 중이면 서버가 어차피 429 다 — 헛왕복은 서버 카운터만 밀어 대기를 늘린다.
      if (resendSecondsLeft(s, e.now) > 0) return { ...s, notice: info(TEXT.cooldown) };
      return { ...s, email, phase: 'sendingCode', notice: null };
    }
    case 'codeSent': {
      if (s.phase !== 'sendingCode') return s;
      const delay = s.sendCount === 0 ? FIRST_RESEND_DELAY_SECONDS : RESEND_COOLDOWN_SECONDS;
      return {
        ...s,
        phase: 'editing',
        codeSentTo: normalizeEmail(s.email),
        sendCount: s.sendCount + 1,
        resendAvailableAt: cooldownAt(e.now, delay),
        notice: info(TEXT.sent),
      };
    }
    case 'codeSendFailed': {
      if (s.phase !== 'sendingCode') return s;
      if (e.failure.kind === 'rateLimited') {
        // 429 = "방금 이미 보냈다". 코드는 메일함으로 가는 중이니 입력 화면으로 넘긴다 — 남은 초는 서버가 진실이다.
        return {
          ...s,
          phase: 'editing',
          codeSentTo: normalizeEmail(s.email),
          sendCount: s.sendCount + 1,
          resendAvailableAt: cooldownAt(e.now, e.failure.retryAfterSeconds ?? RESEND_COOLDOWN_SECONDS),
          notice: info(TEXT.alreadySent),
        };
      }
      return { ...s, phase: 'editing', notice: err(failureMessage(e.failure, 'sendCode')) };
    }
    case 'submit': {
      if (s.phase !== 'editing') return s;
      if (s.mode === 'password') {
        const email = normalizeEmail(s.email);
        if (!isPlausibleEmail(email)) return { ...s, email, notice: err(TEXT.invalidEmail) };
        if (s.password.length === 0) return { ...s, notice: err(TEXT.passwordRequired) };
        if (!s.acknowledged) return { ...s, notice: err(TEXT.acknowledgeRequired) };
        return { ...s, email, phase: 'deleting', notice: info(TEXT.deleting) };
      }
      if (s.codeSentTo === null) return s;
      if (normalizeCode(s.code).length !== CODE_LENGTH) return { ...s, notice: err(TEXT.invalidCode) };
      if (!s.acknowledged) return { ...s, notice: err(TEXT.acknowledgeRequired) };
      return { ...s, phase: 'deleting', notice: info(TEXT.deleting) };
    }
    case 'deleted':
      if (s.phase !== 'deleting') return s;
      // 비밀번호·코드는 화면 메모리에서도 지운다.
      return { ...s, phase: 'deleted', password: '', code: '', notice: null };
    case 'deleteFailed': {
      if (s.phase !== 'deleting') return s;
      const f = e.failure;
      const notice = err(failureMessage(f, e.stage));
      if (s.mode === 'password') {
        // 틀린 비밀번호는 비운다(같은 값으로 또 누르지 않게). 이메일은 남긴다.
        return { ...s, phase: 'editing', password: f.kind === 'wrongCredentials' ? '' : s.password, notice };
      }
      // 코드는 1회용이다 — 본인 확인(verify)을 지난 뒤의 실패는 이미 쓴 코드라 비운다. verify 단계에서도 서버가 코드를 보고 거절했으면
      // (codeRejected · 죽은 recovery 토큰 sessionExpired · 그 밖의 4xx rejected — 화면 문장은 셋 다 "코드가 맞지 않거나 만료됐어요") 비운다.
      // 서버가 코드를 **보기 전에** 멈춘 실패만 남긴다: 연결 실패(닿았는지 모른다 — 안 닿았으면 코드가 아직 산다) · 5xx · 429 ·
      // 배포 설정(config · schemaMissing). 그때 문장은 코드 탓을 하지 않는다(연결 확인 · 조금 뒤 · 지금은 웹에서 못 지움).
      const codeUnchecked = f.kind === 'network' || f.kind === 'server' || f.kind === 'rateLimited' || f.kind === 'config' || f.kind === 'schemaMissing';
      const codeSpent = e.stage !== 'verify' || !codeUnchecked;
      const text = e.stage === 'delete' ? codeModeDeleteMessage(f) : notice.text;
      return { ...s, phase: 'editing', code: codeSpent ? '' : s.code, notice: err(text) };
    }
  }
}
