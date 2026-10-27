// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift @ 1b8260d (deleteAccount 순서 — 290–345)
// 원본: Sources/CheckCore/SupabaseWorkService.swift @ 1b8260d (signIn 92–104 · deleteAvatarFile 429–457 · signOut 459–470 · deleteMyAccount 472–498 · 재설정 OTP 1320–1370)
// 원본: Sources/CheckCore/SupabaseWorkHTTP.swift @ 1b8260d (요청 머리 apikey·Authorization — 55–80)
//
// 웹 계정 삭제의 **왕복** — 브라우저가 Supabase 를 직접 부른다(E§9.6). Vercel 서버를 거치지 않는 이유: 모든 요청이 Vercel IP 하나로
// 보이면 GoTrue 의 IP 기준 제한이 전원을 한꺼번에 막는다. fetch 는 주입받는다(시험은 가짜 fetch 로 순서·머리·본문을 잰다).
//
// 순서가 계약이다(앱 MobileSessionStore.deleteAccount 그대로):
//   1. 본인 확인 — 비밀번호(`/auth/v1/token?grant_type=password`) 또는 메일 코드(`/auth/v1/verify`, type recovery).
//      실패하면 **삭제 RPC 를 부르지 않는다**.
//   2. 프로필 사진 지우기(`DELETE /storage/v1/object/avatars/<uid>.jpg`) — 결과를 보지 않는다. 서버 함수는 Storage 표에 직접
//      못 써서 사진만 남긴다(2026-09-18 실측). 사진 한 장 때문에 계정 삭제가 막히면 안 된다.
//   3. `POST /rest/v1/rpc/delete_my_account` 본문 `{}` — 1 에서 받은 **새 토큰**으로.
//   4. 3 이 실패했을 때만 그 세션을 `logout?scope=local` 로 닫는다(성공했으면 cascade 로 세션이 이미 없다).
// 토큰은 이 함수들의 지역 변수로만 산다 — 화면 상태·저장소·로그 어디에도 남기지 않는다.

import { classifyHttpFailure, type CallKind, type DeleteAccountConfig, type DeletionRequest, type Failure, type Stage } from './delete-account.ts';

/** 브라우저 fetch 중 이 파일이 쓰는 모양만. */
export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body?: string }) => Promise<{
  readonly status: number;
  text(): Promise<string>;
}>;

export interface AuthSession {
  readonly accessToken: string;
  readonly userId: string;
}

export type Result<T> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly failure: Failure };

type Raw = { readonly status: number; readonly text: string } | null;

/**
 * 요청 하나. 머리는 앱(SupabaseWorkHTTP.send)과 같다 — `apikey` 는 늘 anon 키, `Authorization` 은 로그인 토큰이 있으면 그것,
 * 없으면 anon 키. 연결 자체가 실패하면(CORS 거절 포함) null.
 */
async function send(fetchFn: FetchLike, config: DeleteAccountConfig, path: string, method: string, accessToken: string | null, body: unknown): Promise<Raw> {
  const headers: Record<string, string> = {
    apikey: config.anonKey,
    Authorization: `Bearer ${accessToken ?? config.anonKey}`,
    Accept: 'application/json',
  };
  const init: { method: string; headers: Record<string, string>; body?: string } = { method, headers };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body);
  }
  try {
    const res = await fetchFn(`${config.url}${path}`, init);
    let text = '';
    try {
      text = await res.text();
    } catch {
      text = '';
    }
    return { status: res.status, text };
  } catch {
    return null;
  }
}

function failed<T>(raw: Raw, call: CallKind): Result<T> {
  if (raw === null) return { ok: false, failure: { kind: 'network' } };
  return { ok: false, failure: classifyHttpFailure(raw.status, raw.text, call) };
}

const ok2xx = (raw: Raw): raw is { status: number; text: string } => raw !== null && raw.status >= 200 && raw.status < 300;

/** 로그인·코드 검증 응답(같은 봉투 `{access_token, user:{id}}`) → 세션. 모양이 다르면 거절로 본다(빈 토큰으로 삭제를 부르지 않는다). */
function sessionFrom(raw: { status: number; text: string }): Result<AuthSession> {
  try {
    const parsed = JSON.parse(raw.text) as { access_token?: unknown; user?: { id?: unknown } };
    const accessToken = typeof parsed.access_token === 'string' ? parsed.access_token : '';
    const userId = parsed.user && typeof parsed.user.id === 'string' ? parsed.user.id : '';
    if (accessToken && userId) return { ok: true, value: { accessToken, userId } };
  } catch {
    // 아래로
  }
  return { ok: false, failure: { kind: 'rejected', status: raw.status } };
}

export async function signInWithPassword(fetchFn: FetchLike, config: DeleteAccountConfig, email: string, password: string): Promise<Result<AuthSession>> {
  const raw = await send(fetchFn, config, '/auth/v1/token?grant_type=password', 'POST', null, { email, password });
  return ok2xx(raw) ? sessionFrom(raw) : failed(raw, 'password');
}

/** 재설정 코드 메일. **계정이 없어도 200** 이다(GoTrue 가 계정 유무를 흘리지 않는다) — 화면 문구도 성공/실패로 유무를 말하지 않는다. */
export async function sendRecoveryCode(fetchFn: FetchLike, config: DeleteAccountConfig, email: string): Promise<Result<null>> {
  const raw = await send(fetchFn, config, '/auth/v1/recover', 'POST', null, { email });
  return ok2xx(raw) ? { ok: true, value: null } : failed(raw, 'recovery');
}

/** 6자리 코드 → 세션. type 은 반드시 "recovery"(다른 값은 서버가 같은 403 으로 되돌려 "코드가 틀렸다"고 거짓말하게 된다). */
export async function verifyRecoveryCode(fetchFn: FetchLike, config: DeleteAccountConfig, email: string, code: string): Promise<Result<AuthSession>> {
  const raw = await send(fetchFn, config, '/auth/v1/verify', 'POST', null, { email, token: code, type: 'recovery' });
  return ok2xx(raw) ? sessionFrom(raw) : failed(raw, 'recovery');
}

/** 프로필 사진 파일 — 결과를 버리는 것이 이 경로의 계약이다(없던 사람의 404 도 정상). */
export async function deleteAvatarIfAny(fetchFn: FetchLike, config: DeleteAccountConfig, session: AuthSession): Promise<void> {
  await send(fetchFn, config, `/storage/v1/object/avatars/${encodeURIComponent(session.userId)}.jpg`, 'DELETE', session.accessToken, undefined);
}

// INV-SupabaseWorkService-d348f33f 이식: delete_my_account 는 본인 계정에만 작용한다(누구를 지울지는 **토큰이** 정한다 — 인자 없음).
//   그래서 맥·폰과 같은 서버 함수를 웹도 그대로 부른다. 인자 없는 RPC 라 본문은 `{}`(PostgREST 는 본문 키 집합으로 함수를 고른다).
export async function deleteMyAccount(fetchFn: FetchLike, config: DeleteAccountConfig, session: AuthSession): Promise<Result<null>> {
  const raw = await send(fetchFn, config, '/rest/v1/rpc/delete_my_account', 'POST', session.accessToken, {});
  return ok2xx(raw) ? { ok: true, value: null } : failed(raw, 'rpc');
}

/** 이 토큰의 세션 하나만 닫는다. **scope=local 이 요점** — 기본(global)이면 같은 계정의 맥·폰 세션까지 끊긴다. */
export async function signOutLocal(fetchFn: FetchLike, config: DeleteAccountConfig, session: AuthSession): Promise<void> {
  await send(fetchFn, config, '/auth/v1/logout?scope=local', 'POST', session.accessToken, undefined);
}

export type DeletionOutcome = { readonly ok: true } | { readonly ok: false; readonly failure: Failure; readonly stage: Stage };

/** 본인 확인을 마친 세션으로 2~4 단계. */
export async function deleteWithSession(fetchFn: FetchLike, config: DeleteAccountConfig, session: AuthSession): Promise<DeletionOutcome> {
  await deleteAvatarIfAny(fetchFn, config, session);
  const deleted = await deleteMyAccount(fetchFn, config, session);
  if (deleted.ok) return { ok: true };
  await signOutLocal(fetchFn, config, session);
  return { ok: false, failure: deleted.failure, stage: 'delete' };
}

/** 상태기계가 'deleting' 으로 넘긴 요청 하나를 끝까지. */
export async function runDeletion(fetchFn: FetchLike, config: DeleteAccountConfig, request: DeletionRequest): Promise<DeletionOutcome> {
  const auth =
    request.mode === 'password'
      ? await signInWithPassword(fetchFn, config, request.email, request.password)
      : await verifyRecoveryCode(fetchFn, config, request.email, request.code);
  if (!auth.ok) return { ok: false, failure: auth.failure, stage: request.mode === 'password' ? 'signIn' : 'verify' };
  return deleteWithSession(fetchFn, config, auth.value);
}
