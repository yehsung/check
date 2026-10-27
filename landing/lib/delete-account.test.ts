// 원본: Sources/CheckMobileKit/Session/MobilePasswordResetStore.swift @ 1b8260d (입력 정규화·쿨다운 — 시험 기대값의 출처)
// 원본: Sources/CheckCore/SupabaseWorkHTTP.swift @ 1b8260d (실패 분류 순서 — 90–188)
// 원본: Sources/CheckCore/SupabaseWorkService.swift @ 1b8260d (passwordRecoveryError·retryAfterSeconds — 1383–1432)
// 원본: Sources/CheckMobileKit/Session/MobilePasswordResetStore.swift @ 1b8260d (sendFailureMessage·verifyFailureMessage — 336–349: 문장 표의 출처)
// 원본: Sources/CheckMobileKit/Me/MeText.swift @ 1b8260d (deleteAccountFailure — 907–922: 삭제 단계 문장의 출처)
//
// node --experimental-strip-types --test lib/delete-account.test.ts
// 웹 계정 삭제의 순수 부분: 설정 읽기 · 입력 정규화 · HTTP 실패 분류 · 상태기계(입력 → 확인 → 삭제 → 완료/오류). 실서버 0.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CODE_LENGTH,
  MAX_COOLDOWN_SECONDS,
  TEXT,
  canRequestCode,
  canSubmit,
  classifyHttpFailure,
  deletionRequest,
  failureMessage,
  initialState,
  isPlausibleEmail,
  normalizeCode,
  normalizeEmail,
  readConfig,
  reduce,
  resendSecondsLeft,
  retryAfterSeconds,
  type DeleteAccountEvent,
  type DeleteAccountState,
  type Failure,
  type Stage,
} from './delete-account.ts';

const run = (events: DeleteAccountEvent[], from: DeleteAccountState = initialState) => events.reduce(reduce, from);
const T0 = 1_000_000;

// ---------------------------------------------------------------------------------------------------------------
// 설정

test('readConfig: https 주소 + 키 → 설정(끝 / 를 뗀다)', () => {
  assert.deepEqual(readConfig('https://abc.example.co/', ' k1 '), { url: 'https://abc.example.co', anonKey: 'k1' });
  assert.deepEqual(readConfig('https://abc.example.co/base//', 'k1'), { url: 'https://abc.example.co/base', anonKey: 'k1' });
});

test('readConfig: 내 컴퓨터만 http 를 받는다(로컬 supabase start 경로)', () => {
  assert.deepEqual(readConfig('http://127.0.0.1:54431', 'k'), { url: 'http://127.0.0.1:54431', anonKey: 'k' });
  assert.deepEqual(readConfig('http://localhost:54431', 'k'), { url: 'http://localhost:54431', anonKey: 'k' });
  assert.equal(readConfig('http://abc.example.co', 'k'), null);
  assert.equal(readConfig('ftp://abc.example.co', 'k'), null);
});

test('readConfig: 값이 없거나 이상하면 null(화면은 "지금은 웹에서 지울 수 없어요")', () => {
  assert.equal(readConfig(undefined, 'k'), null);
  assert.equal(readConfig('https://a.example.co', undefined), null);
  assert.equal(readConfig('https://a.example.co', '   '), null);
  assert.equal(readConfig('https://a.example.co', 'a b'), null);
  assert.equal(readConfig('not a url', 'k'), null);
  assert.equal(readConfig('https://a.example.co/?x=1', 'k'), null);
  assert.equal(readConfig('https://user:pw@a.example.co', 'k'), null);
});

// ---------------------------------------------------------------------------------------------------------------
// 입력 정규화(앱 MobilePasswordResetStore 와 같은 판정)

test('normalizeEmail: 앞뒤 공백·줄바꿈을 걷고 소문자', () => {
  assert.equal(normalizeEmail('  Me@Example.COM\n'), 'me@example.com');
});

test('isPlausibleEmail: 최소 형식만', () => {
  const yes = ['a@b.c', 'me.you+x@sub.example.co.kr'];
  const no = ['', 'a@b', '@b.c', 'a@.b', 'a@b.', 'a@@b.c', 'a b@c.d', 'a@b.c d', 'ab.c'];
  for (const e of yes) assert.equal(isPlausibleEmail(e), true, e);
  for (const e of no) assert.equal(isPlausibleEmail(e), false, e);
});

test('normalizeCode: ASCII 숫자만(메일에서 복사한 공백·하이픈·전각 숫자는 빠진다)', () => {
  assert.equal(normalizeCode(' 12 34-56 '), '123456');
  assert.equal(normalizeCode('１２３４５６'), '');
  assert.equal(normalizeCode('a1b2'), '12');
});

// ---------------------------------------------------------------------------------------------------------------
// 실패 분류

test('retryAfterSeconds: "second" 바로 앞의 숫자 뭉치, 없으면 null', () => {
  assert.equal(retryAfterSeconds('for security purposes, you can only request this after 51 seconds.'), 51);
  assert.equal(retryAfterSeconds('after 7 second'), 7);
  assert.equal(retryAfterSeconds('12 then 34 seconds'), 34);
  assert.equal(retryAfterSeconds('email rate limit exceeded'), null);
  assert.equal(retryAfterSeconds('wait some seconds'), null);
  assert.equal(retryAfterSeconds(''), null);
});

const j = (o: unknown) => JSON.stringify(o);

test('classify: 5xx·429 상태코드 게이트가 본문 문구보다 먼저다(INV-SupabaseWorkHTTP-d4703379)', () => {
  // 본문이 "비밀번호 틀림"이어도 503 이면 일시 장애다 — 틀린 비밀번호로 접으면 사용자는 맞는 비밀번호를 의심한다.
  assert.deepEqual(classifyHttpFailure(503, j({ msg: 'Invalid login credentials' }), 'password'), { kind: 'server', status: 503 });
  assert.deepEqual(classifyHttpFailure(429, j({ msg: 'Invalid login credentials after 9 seconds' }), 'password'), { kind: 'rateLimited', retryAfterSeconds: 9 });
  assert.deepEqual(classifyHttpFailure(429, 'nope', 'recovery'), { kind: 'rateLimited', retryAfterSeconds: null });
});

test('classify: GoTrue 로그인 거절(새·옛 모양) → wrongCredentials', () => {
  assert.deepEqual(classifyHttpFailure(400, j({ code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials' }), 'password'), { kind: 'wrongCredentials' });
  assert.deepEqual(classifyHttpFailure(400, j({ error: 'invalid_grant', error_description: 'Invalid login credentials' }), 'password'), { kind: 'wrongCredentials' });
});

test('classify: GoTrue 기계 코드 error_code=invalid_credentials 만으로도 wrongCredentials(문구가 바뀌어도 영어가 새지 않게)', () => {
  // 사람이 읽는 msg 는 GoTrue 판마다 바뀌어 왔다 — 기계 코드는 고정이다(Supabase Auth error codes 표의 invalid_credentials).
  assert.deepEqual(classifyHttpFailure(400, j({ error_code: 'invalid_credentials', msg: 'Login failed' }), 'password'), { kind: 'wrongCredentials' });
  // 기준선: 같은 모양에 다른 기계 코드면 접지 않는다(위 단언이 아무 400 이나 wrongCredentials 로 보는 게 아님을 보인다).
  assert.deepEqual(classifyHttpFailure(400, j({ error_code: 'validation_failed', msg: 'Login failed' }), 'password'), { kind: 'rejected', status: 400 });
});

test('classify: 이메일 미인증 · 키 오류 · 세션 만료', () => {
  assert.deepEqual(classifyHttpFailure(400, j({ error_code: 'email_not_confirmed', msg: 'Email not confirmed' }), 'password'), { kind: 'emailNotConfirmed' });
  assert.deepEqual(classifyHttpFailure(401, j({ message: 'Invalid API key' }), 'password'), { kind: 'config' });
  assert.deepEqual(classifyHttpFailure(401, j({ code: 'PGRST301', message: 'JWT expired' }), 'rpc'), { kind: 'sessionExpired' });
  assert.deepEqual(classifyHttpFailure(401, '<html>', 'rpc'), { kind: 'sessionExpired' });
});

test('classify: 함수가 없는 서버(PGRST202 schema cache) → schemaMissing', () => {
  const body = j({ code: 'PGRST202', message: 'Could not find the function public.delete_my_account without parameters in the schema cache', hint: null, details: null });
  assert.deepEqual(classifyHttpFailure(404, body, 'rpc'), { kind: 'schemaMissing' });
});

test('classify: 삭제 RPC 의 메시지 없는 404 도 schemaMissing(앱 MobileDeviceRPC.isMissingFunction 의 invalidResponse(404))', () => {
  assert.deepEqual(classifyHttpFailure(404, '<html>Not Found</html>', 'rpc'), { kind: 'schemaMissing' });
  assert.deepEqual(classifyHttpFailure(404, '', 'rpc'), { kind: 'schemaMissing' });
  assert.deepEqual(classifyHttpFailure(404, j({ code: 'XX000', hint: null }), 'rpc'), { kind: 'schemaMissing' });
  // 메시지가 있는 404 는 앱처럼 거절(.authMessage → fatal → rejected).
  assert.deepEqual(classifyHttpFailure(404, j({ message: 'not here' }), 'rpc'), { kind: 'rejected', status: 404 });
  // 앱은 이 판정을 삭제 RPC 에만 건다 — 로그인·코드 왕복의 404 는 그냥 거절이다.
  assert.deepEqual(classifyHttpFailure(404, '<html>Not Found</html>', 'password'), { kind: 'rejected', status: 404 });
  assert.deepEqual(classifyHttpFailure(404, '', 'recovery'), { kind: 'rejected', status: 404 });
});

test('classify: 재설정 흐름만 GoTrue 코드 문구를 좁힌다(passwordRecoveryError)', () => {
  const expired = j({ code: 403, error_code: 'otp_expired', msg: 'Token has expired or is invalid' });
  assert.deepEqual(classifyHttpFailure(403, expired, 'recovery'), { kind: 'codeRejected' });
  // 다른 왕복에서는 같은 본문을 코드 거절로 읽지 않는다.
  assert.deepEqual(classifyHttpFailure(403, expired, 'password'), { kind: 'rejected', status: 403 });
  assert.deepEqual(classifyHttpFailure(400, j({ msg: 'Verify requires either a token or a token hash' }), 'recovery'), { kind: 'codeRejected' });
  assert.deepEqual(classifyHttpFailure(400, j({ msg: 'Email rate limit exceeded' }), 'recovery'), { kind: 'rateLimited', retryAfterSeconds: null });
  assert.deepEqual(classifyHttpFailure(403, j({ error_code: 'bad_jwt', msg: 'invalid JWT: unable to parse' }), 'recovery'), { kind: 'sessionExpired' });
});

test('classify: 그 밖의 4xx → rejected(상태 그대로), JSON 아닌 본문도 받는다', () => {
  assert.deepEqual(classifyHttpFailure(400, 'plain text', 'rpc'), { kind: 'rejected', status: 400 });
  assert.deepEqual(classifyHttpFailure(403, j({ code: '28000', message: 'authentication required' }), 'rpc'), { kind: 'rejected', status: 403 });
  assert.deepEqual(classifyHttpFailure(400, j([1, 2]), 'rpc'), { kind: 'rejected', status: 400 });
});

// ---------------------------------------------------------------------------------------------------------------
// 문구

const ALL_FAILURES: Failure[] = [
  { kind: 'network' },
  { kind: 'server', status: 502 },
  { kind: 'rateLimited', retryAfterSeconds: 3 },
  { kind: 'config' },
  { kind: 'schemaMissing' },
  { kind: 'sessionExpired' },
  { kind: 'wrongCredentials' },
  { kind: 'emailNotConfirmed' },
  { kind: 'codeRejected' },
  { kind: 'rejected', status: 418 },
];
const STAGES: Stage[] = ['signIn', 'sendCode', 'verify', 'delete'];

test('failureMessage: 모든 갈래 × 단계가 정해 둔 한국어 문장 중 하나다(서버 원문·영어가 새지 않는다)', () => {
  const allowed = new Set<string>(Object.values(TEXT));
  for (const f of ALL_FAILURES) {
    for (const s of STAGES) {
      const m = failureMessage(f, s);
      assert.ok(allowed.has(m), `${f.kind}/${s}: ${m}`);
      assert.doesNotMatch(m, /[A-Za-z]/, `${f.kind}/${s}: ${m}`);
    }
  }
});

// 갈래 × 단계 문장 표. 기대값의 출처는 구현이 아니라 앱 문장과 설계다(글자 그대로 적는다 — TEXT 를 거치지 않는다):
//   연결 실패·5xx → MobileLoadText.checkConnection(앱 deleteAccount·재설정 모두 transient → network).
//   429 → sendCode: MobilePasswordResetText.alreadySent(requestCode 의 429 갈래) · verify: .cooldown(verifyFailureMessage) ·
//         signIn·delete: AuthErrorRules.message(.rateLimited)(앱 deleteAccount 는 '연결 확인'으로 접지만 웹은 이 문장 — failureMessage 주석).
//   config → 웹 전용 안내(배포 설정이 틀렸다 — 사용자가 고칠 일이 아니다, E§9.6 '설정 없으면 안내').
//   schemaMissing → delete: MeText.deleteAccountFailure(.serverNotReady)의 웹 판 · 그 밖: 웹 전용 안내.
//   sessionExpired → verify: codeRejected(passwordRecoveryError 가 bad_jwt 를 sessionExpired 로 접고 verifyFailureMessage 나머지 갈래).
//   wrongCredentials → signIn: MeText .wrongPassword 에 이메일을 더한 문장(웹은 이메일도 친다 — 어느 쪽이 틀렸는지 가르지 않는다).
//   rejected → signIn: 본인 확인 실패 · sendCode: .sendFailed · verify: .codeRejected · delete: MeText .rejected 의 웹 판.
const CHECK = '연결을 확인하고 다시 시도해 주세요';
const LATER = '잠시 후 다시 시도해주세요';
const UNAVAILABLE = '지금은 웹에서 계정을 지울 수 없어요 · 앱에서 지우거나 아래 문의 경로로 알려 주세요';
const CODE_BAD = '코드가 맞지 않거나 만료됐어요 · 다시 받기를 눌러주세요';
const SIGNIN_FAILED = '본인 확인을 하지 못했어요 · 다시 시도해 주세요';
const EXPIRED = '본인 확인이 만료됐어요 · 처음부터 다시 시도해 주세요';
const NOT_CONFIRMED = '가입 코드 확인을 마치지 않은 계정이에요 · 메일 코드로 확인해 주세요';
const EXPECTED_MESSAGES: Record<Failure['kind'], Record<Stage, string>> = {
  network: { signIn: CHECK, sendCode: CHECK, verify: CHECK, delete: CHECK },
  server: { signIn: CHECK, sendCode: CHECK, verify: CHECK, delete: CHECK },
  rateLimited: { signIn: LATER, sendCode: '메일을 이미 보냈어요 · 메일함을 확인해주세요', verify: '조금 뒤에 다시 받을 수 있어요', delete: LATER },
  config: { signIn: UNAVAILABLE, sendCode: UNAVAILABLE, verify: UNAVAILABLE, delete: UNAVAILABLE },
  schemaMissing: {
    signIn: UNAVAILABLE,
    sendCode: UNAVAILABLE,
    verify: UNAVAILABLE,
    delete: '계정 삭제가 아직 서버에 준비되지 않았어요 · 잠시 뒤 다시 시도해 주세요',
  },
  sessionExpired: { signIn: EXPIRED, sendCode: EXPIRED, verify: CODE_BAD, delete: EXPIRED },
  wrongCredentials: { signIn: '이메일 또는 비밀번호가 맞지 않아요', sendCode: SIGNIN_FAILED, verify: SIGNIN_FAILED, delete: SIGNIN_FAILED },
  emailNotConfirmed: { signIn: NOT_CONFIRMED, sendCode: NOT_CONFIRMED, verify: NOT_CONFIRMED, delete: NOT_CONFIRMED },
  codeRejected: { signIn: CODE_BAD, sendCode: CODE_BAD, verify: CODE_BAD, delete: CODE_BAD },
  rejected: {
    signIn: SIGNIN_FAILED,
    sendCode: '메일을 보내지 못했어요 · 주소를 확인하고 다시 시도해주세요',
    verify: CODE_BAD,
    delete: '계정을 지우지 못했어요 · 잠시 뒤 다시 시도해 주세요',
  },
};

test('failureMessage: 갈래 × 단계 문장 표(10 × 4)가 앱 문장·설계에서 옮긴 기대값과 같다', () => {
  assert.equal(ALL_FAILURES.length, 10);
  let cells = 0;
  for (const f of ALL_FAILURES) {
    for (const s of STAGES) {
      assert.equal(failureMessage(f, s), EXPECTED_MESSAGES[f.kind][s], `${f.kind}/${s}`);
      cells++;
    }
  }
  assert.equal(cells, 40);
});

test('failureMessage: 단계마다 할 일이 다르다', () => {
  assert.equal(failureMessage({ kind: 'wrongCredentials' }, 'signIn'), TEXT.wrongCredentials);
  assert.equal(failureMessage({ kind: 'schemaMissing' }, 'delete'), TEXT.serverNotReady);
  assert.equal(failureMessage({ kind: 'schemaMissing' }, 'signIn'), TEXT.unavailable);
  assert.equal(failureMessage({ kind: 'rateLimited', retryAfterSeconds: 3 }, 'sendCode'), TEXT.alreadySent);
  assert.equal(failureMessage({ kind: 'rejected', status: 400 }, 'sendCode'), TEXT.sendFailed);
  assert.equal(failureMessage({ kind: 'rejected', status: 400 }, 'verify'), TEXT.codeRejected);
  assert.equal(failureMessage({ kind: 'rejected', status: 400 }, 'delete'), TEXT.deleteRejected);
  assert.equal(failureMessage({ kind: 'network' }, 'delete'), TEXT.checkConnection);
});

// ---------------------------------------------------------------------------------------------------------------
// 상태기계 — 흐름 A(비밀번호)

const filledA = run([
  { type: 'email', value: '  Me@Example.com ' },
  { type: 'password', value: 'pw-123' },
]);

test('흐름 A: 되돌릴 수 없다는 체크 없이는 버튼이 닫혀 있고, 눌러도 삭제로 넘어가지 않는다', () => {
  assert.equal(canSubmit(initialState), false);
  assert.equal(canSubmit(filledA), false);
  const s = reduce(filledA, { type: 'submit' });
  assert.equal(s.phase, 'editing');
  assert.deepEqual(s.notice, { text: TEXT.acknowledgeRequired, tone: 'error' });
  assert.equal(deletionRequest(s), null);
});

test('흐름 A: 이메일 형식·비밀번호가 먼저 걸린다(왕복 전에)', () => {
  const badEmail = run([{ type: 'email', value: 'me@example' }, { type: 'password', value: 'x' }, { type: 'acknowledge', value: true }, { type: 'submit' }]);
  assert.equal(badEmail.phase, 'editing');
  assert.equal(badEmail.notice?.text, TEXT.invalidEmail);
  const noPw = run([{ type: 'email', value: 'me@example.com' }, { type: 'acknowledge', value: true }, { type: 'submit' }]);
  assert.equal(noPw.phase, 'editing');
  assert.equal(noPw.notice?.text, TEXT.passwordRequired);
});

test('흐름 A: 다 갖추면 deleting — 보낼 값은 정규화한 이메일 + 친 비밀번호 그대로', () => {
  const ready = reduce(filledA, { type: 'acknowledge', value: true });
  assert.equal(canSubmit(ready), true);
  const s = reduce(ready, { type: 'submit' });
  assert.equal(s.phase, 'deleting');
  assert.deepEqual(deletionRequest(s), { mode: 'password', email: 'me@example.com', password: 'pw-123' });
  // 도는 동안 입력·갈래 바꾸기·재제출은 먹지 않는다.
  assert.equal(reduce(s, { type: 'password', value: 'other' }).password, 'pw-123');
  assert.equal(reduce(s, { type: 'mode', mode: 'code' }).mode, 'password');
  assert.equal(reduce(s, { type: 'submit' }), s);
});

test('흐름 A: 틀린 비밀번호면 비밀번호만 비우고 이메일은 남긴다 · 연결 실패면 둘 다 남긴다', () => {
  const deleting = run([{ type: 'acknowledge', value: true }, { type: 'submit' }], filledA);
  const wrong = reduce(deleting, { type: 'deleteFailed', failure: { kind: 'wrongCredentials' }, stage: 'signIn' });
  assert.equal(wrong.phase, 'editing');
  assert.equal(wrong.password, '');
  assert.equal(wrong.email, 'me@example.com');
  assert.deepEqual(wrong.notice, { text: TEXT.wrongCredentials, tone: 'error' });
  const offline = reduce(deleting, { type: 'deleteFailed', failure: { kind: 'network' }, stage: 'signIn' });
  assert.equal(offline.password, 'pw-123');
  assert.equal(offline.notice?.text, TEXT.checkConnection);
});

test('완료: deleted 뒤에는 비밀번호·코드가 비고 어떤 이벤트도 상태를 바꾸지 않는다', () => {
  const deleting = run([{ type: 'acknowledge', value: true }, { type: 'submit' }], filledA);
  const done = reduce(deleting, { type: 'deleted' });
  assert.equal(done.phase, 'deleted');
  assert.equal(done.password, '');
  for (const e of [{ type: 'submit' }, { type: 'mode', mode: 'code' }, { type: 'email', value: 'x@y.z' }, { type: 'deleteFailed', failure: { kind: 'network' }, stage: 'delete' }] as DeleteAccountEvent[]) {
    assert.equal(reduce(done, e), done);
  }
  // deleting 이 아닌데 온 완료·실패는 무시한다(늦은 응답).
  assert.equal(reduce(filledA, { type: 'deleted' }), filledA);
});

// ---------------------------------------------------------------------------------------------------------------
// 상태기계 — 흐름 B(메일 코드)

const codeMode = run([{ type: 'mode', mode: 'code' }, { type: 'email', value: 'Me@Example.com' }]);

test('흐름 B: 코드 받기 — 형식이 틀리면 왕복하지 않는다', () => {
  const bad = run([{ type: 'mode', mode: 'code' }, { type: 'email', value: 'nope' }, { type: 'requestCode', now: T0 }]);
  assert.equal(bad.phase, 'editing');
  assert.equal(bad.notice?.text, TEXT.invalidEmail);
  assert.equal(canRequestCode(codeMode, T0), true);
  const sending = reduce(codeMode, { type: 'requestCode', now: T0 });
  assert.equal(sending.phase, 'sendingCode');
  assert.equal(canRequestCode(sending, T0), false);
});

test('흐름 B: 첫 발송 뒤 5초, 두 번째부터 60초 동안 다시 받기가 잠긴다', () => {
  const sent = run([{ type: 'requestCode', now: T0 }, { type: 'codeSent', now: T0 }], codeMode);
  assert.equal(sent.codeSentTo, 'me@example.com');
  assert.deepEqual(sent.notice, { text: TEXT.sent, tone: 'info' });
  assert.equal(resendSecondsLeft(sent, T0), 5);
  assert.equal(resendSecondsLeft(sent, T0 + 1_001), 4);
  assert.equal(canRequestCode(sent, T0 + 4_999), false);
  assert.equal(canRequestCode(sent, T0 + 5_000), true);
  const early = reduce(sent, { type: 'requestCode', now: T0 + 1_000 });
  assert.equal(early.phase, 'editing');
  assert.deepEqual(early.notice, { text: TEXT.cooldown, tone: 'info' });
  const again = run([{ type: 'requestCode', now: T0 + 6_000 }, { type: 'codeSent', now: T0 + 6_000 }], sent);
  assert.equal(resendSecondsLeft(again, T0 + 6_000), 60);
});

test('흐름 B: 429 는 "이미 보냈다" — 코드 화면으로 넘기고 서버가 준 초(없으면 60, 상한 600)로 잠근다', () => {
  const r9 = run([{ type: 'requestCode', now: T0 }, { type: 'codeSendFailed', failure: { kind: 'rateLimited', retryAfterSeconds: 9 }, now: T0 }], codeMode);
  assert.equal(r9.codeSentTo, 'me@example.com');
  assert.deepEqual(r9.notice, { text: TEXT.alreadySent, tone: 'info' });
  assert.equal(resendSecondsLeft(r9, T0), 9);
  const rNull = run([{ type: 'requestCode', now: T0 }, { type: 'codeSendFailed', failure: { kind: 'rateLimited', retryAfterSeconds: null }, now: T0 }], codeMode);
  assert.equal(resendSecondsLeft(rNull, T0), 60);
  const rHuge = run([{ type: 'requestCode', now: T0 }, { type: 'codeSendFailed', failure: { kind: 'rateLimited', retryAfterSeconds: 99_999 }, now: T0 }], codeMode);
  assert.equal(resendSecondsLeft(rHuge, T0), MAX_COOLDOWN_SECONDS);
  // 하한 1초(앱 startCooldown 의 min(max(seconds, 1), 600)) — 서버가 '0초 뒤'라고 해도 같은 순간에 또 누르지 못한다.
  const rZero = run([{ type: 'requestCode', now: T0 }, { type: 'codeSendFailed', failure: { kind: 'rateLimited', retryAfterSeconds: 0 }, now: T0 }], codeMode);
  assert.equal(resendSecondsLeft(rZero, T0), 1);
  assert.equal(canRequestCode(rZero, T0), false);
  assert.equal(canRequestCode(rZero, T0 + 1_000), true);
});

test('흐름 B: 그 밖의 발송 실패는 첫 화면에 머문다', () => {
  const s = run([{ type: 'requestCode', now: T0 }, { type: 'codeSendFailed', failure: { kind: 'rejected', status: 400 }, now: T0 }], codeMode);
  assert.equal(s.phase, 'editing');
  assert.equal(s.codeSentTo, null);
  assert.deepEqual(s.notice, { text: TEXT.sendFailed, tone: 'error' });
});

const sentB = run([{ type: 'requestCode', now: T0 }, { type: 'codeSent', now: T0 }], codeMode);

test('흐름 B: 코드를 보낸 뒤엔 주소 칸이 잠기고, [주소 바꾸기]로만 첫 화면에 돌아간다', () => {
  assert.equal(reduce(sentB, { type: 'email', value: 'other@example.com' }).email, sentB.email);
  const back = reduce(sentB, { type: 'editEmail' });
  assert.equal(back.codeSentTo, null);
  assert.equal(reduce(back, { type: 'email', value: 'other@example.com' }).email, 'other@example.com');
});

test('흐름 B: 6자리 + 체크 → deleting, 보낼 이메일은 코드를 보낸 주소', () => {
  const short = run([{ type: 'code', value: '12345' }, { type: 'acknowledge', value: true }, { type: 'submit' }], sentB);
  assert.equal(short.phase, 'editing');
  assert.equal(short.notice?.text, TEXT.invalidCode);
  const ready = run([{ type: 'code', value: '12 34 56' }, { type: 'acknowledge', value: true }], sentB);
  assert.equal(canSubmit(ready), true);
  const s = reduce(ready, { type: 'submit' });
  assert.equal(s.phase, 'deleting');
  assert.deepEqual(deletionRequest(s), { mode: 'code', email: 'me@example.com', code: '123456' });
  assert.equal(CODE_LENGTH, 6);
});

test('흐름 B: 되돌릴 수 없다는 체크 없이는 버튼이 닫혀 있고, Enter(submit)로 눌러도 삭제로 넘어가지 않는다', () => {
  const coded = reduce(sentB, { type: 'code', value: '123456' });
  assert.equal(canSubmit(coded), false);
  const s = reduce(coded, { type: 'submit' });
  assert.equal(s.phase, 'editing');
  assert.deepEqual(s.notice, { text: TEXT.acknowledgeRequired, tone: 'error' });
  assert.equal(deletionRequest(s), null);
  // 체크했다가 풀어도 같다.
  const unchecked = run([{ type: 'acknowledge', value: true }, { type: 'acknowledge', value: false }, { type: 'submit' }], coded);
  assert.equal(canSubmit(unchecked), false);
  assert.equal(unchecked.phase, 'editing');
  assert.equal(deletionRequest(unchecked), null);
  // 기준선: 같은 상태에 체크만 더하면 deleting 이다(위 빨강이 코드·주소 탓이 아님을 보인다).
  assert.equal(run([{ type: 'acknowledge', value: true }, { type: 'submit' }], coded).phase, 'deleting');
});

test('흐름 B: 확인(verify) 단계 실패 — 서버가 코드를 보고 거절했으면 비우고, 코드를 보기 전에 멈췄으면 남긴다', () => {
  const deleting = run([{ type: 'code', value: '123456' }, { type: 'acknowledge', value: true }, { type: 'submit' }], sentB);
  // 코드를 보기 전: 연결 실패(닿았는지 모른다) · 5xx · 429 · 배포 설정.
  const kept = new Set<Failure['kind']>(['network', 'server', 'rateLimited', 'config', 'schemaMissing']);
  for (const f of ALL_FAILURES) {
    const s = reduce(deleting, { type: 'deleteFailed', failure: f, stage: 'verify' });
    assert.equal(s.phase, 'editing', f.kind);
    assert.equal(s.code, kept.has(f.kind) ? '123456' : '', `verify/${f.kind}: 코드 칸`);
    // 칸을 비웠으면 문장도 코드를 탓한다(남겼으면 탓하지 않는다) — 말과 칸이 어긋나지 않게.
    if (f.kind !== 'wrongCredentials' && f.kind !== 'emailNotConfirmed') {
      assert.equal(s.notice?.text === CODE_BAD, !kept.has(f.kind), `verify/${f.kind}: ${s.notice?.text}`);
    }
  }
});

test('흐름 B: 확인을 지난 뒤(delete) 실패는 모든 갈래에서 코드를 비우고 "새 코드" 를 말한다(함수 없음만 "아직 준비 안 됨")', () => {
  const deleting = run([{ type: 'code', value: '123456' }, { type: 'acknowledge', value: true }, { type: 'submit' }], sentB);
  for (const f of ALL_FAILURES) {
    const s = reduce(deleting, { type: 'deleteFailed', failure: f, stage: 'delete' });
    assert.equal(s.code, '', `delete/${f.kind}`);
    const expected =
      f.kind === 'schemaMissing'
        ? '계정 삭제가 아직 서버에 준비되지 않았어요 · 잠시 뒤 다시 시도해 주세요'
        : f.kind === 'network' || f.kind === 'server'
          ? '연결을 확인하고 새 코드를 받아 다시 시도해 주세요'
          : '계정을 지우지 못했어요 · 새 코드를 받아 다시 시도해 주세요';
    assert.equal(s.notice?.text, expected, `delete/${f.kind}`);
  }
});

test('흐름 B: 코드는 1회용 — 확인을 지난 뒤의 실패·코드 거절은 코드를 비우고, 확인 단계의 연결 실패만 남긴다', () => {
  const deleting = run([{ type: 'code', value: '123456' }, { type: 'acknowledge', value: true }, { type: 'submit' }], sentB);
  const rejected = reduce(deleting, { type: 'deleteFailed', failure: { kind: 'codeRejected' }, stage: 'verify' });
  assert.equal(rejected.code, '');
  assert.equal(rejected.notice?.text, TEXT.codeRejected);
  const offline = reduce(deleting, { type: 'deleteFailed', failure: { kind: 'network' }, stage: 'verify' });
  assert.equal(offline.code, '123456');
  const rpcFail = reduce(deleting, { type: 'deleteFailed', failure: { kind: 'rejected', status: 400 }, stage: 'delete' });
  assert.equal(rpcFail.code, '');
  assert.equal(rpcFail.notice?.text, TEXT.deleteRejectedNewCode);
  const rpcOffline = reduce(deleting, { type: 'deleteFailed', failure: { kind: 'server', status: 503 }, stage: 'delete' });
  assert.equal(rpcOffline.notice?.text, TEXT.checkConnectionNewCode);
  const notReady = reduce(deleting, { type: 'deleteFailed', failure: { kind: 'schemaMissing' }, stage: 'delete' });
  assert.equal(notReady.notice?.text, TEXT.serverNotReady);
  assert.equal(rpcFail.codeSentTo, 'me@example.com');
});

test('갈래 바꾸기: 비밀번호·코드는 비우고, 메일 쿨다운은 남긴다(왔다 갔다로 메일 제한을 우회하지 않게)', () => {
  const withPw = reduce(sentB, { type: 'password', value: 'secret' });
  assert.notEqual(withPw.notice, null); // 기준선: 바꾸기 전엔 '메일을 보냈어요' 가 떠 있다
  const toA = reduce(withPw, { type: 'mode', mode: 'password' });
  assert.equal(toA.password, '');
  assert.equal(toA.codeSentTo, null);
  // 다른 갈래의 안내('메일을 보냈어요' · 오류)는 데려가지 않는다.
  assert.equal(toA.notice, null);
  const errored = reduce(filledA, { type: 'submit' }); // 체크 안 함 → 오류 문장
  assert.notEqual(errored.notice, null);
  assert.equal(reduce(errored, { type: 'mode', mode: 'code' }).notice, null);
  const backToB = reduce(toA, { type: 'mode', mode: 'code' });
  assert.equal(resendSecondsLeft(backToB, T0 + 1_000), 4);
  assert.equal(canRequestCode(backToB, T0 + 1_000), false);
});
