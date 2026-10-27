// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift @ 1b8260d (deleteAccount 순서 — 290–345)
// 원본: Sources/CheckCore/SupabaseWorkService.swift @ 1b8260d (요청 경로·본문 — 92–104, 429–498, 1320–1370)
//
// node --experimental-strip-types --test lib/delete-account-client.test.ts
// 웹 계정 삭제의 왕복 순서·머리·본문을 **가짜 fetch** 로 잰다(실서버 0). 순서가 계약이다:
//   본인 확인 → (실패면 여기서 끝) → 사진 DELETE(결과 무시) → rpc/delete_my_account `{}` → (실패면) logout?scope=local.
// 아래쪽은 흐름 섬 손잡이(requestCodeFlow · submitFlow · browserFetchFrom) — 진짜 상태기계(reduce) + 가짜 fetch · 가짜 시계로
// 화면이 받는 이벤트(완료/실패)와 나가는 요청을 잰다.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TEXT, initialState, reduce, type DeleteAccountConfig, type DeleteAccountEvent, type DeleteAccountState } from './delete-account.ts';
import {
  browserFetchFrom,
  requestCodeFlow,
  runDeletion,
  sendRecoveryCode,
  submitFlow,
  type BrowserRequestInit,
  type FetchLike,
  type FlowContext,
} from './delete-account-client.ts';

const CONFIG: DeleteAccountConfig = { url: 'https://proj.example.test', anonKey: 'anon-key-x' };
const TOKEN = 'access-token-y';
const UID = '0b5f6a1e-1111-4222-8333-944445555666';

interface Call {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
}

/** 'throw' = 연결 실패(fetch 가 거절) · textThrows = 응답은 왔는데 본문 읽기가 실패(스트림 끊김). */
type Reply = { status: number; body?: unknown; textThrows?: boolean } | 'throw';

/** 경로(쿼리 포함, 주소 앞부분 뺀 것) → 응답. 없는 경로를 부르면 시험이 실패한다(예상 밖 왕복 = 결함). */
function fakeFetch(routes: Record<string, Reply>) {
  const calls: Call[] = [];
  const fn: FetchLike = async (url, init) => {
    calls.push({ url, method: init.method, headers: { ...init.headers }, body: init.body === undefined ? undefined : JSON.parse(init.body) });
    const key = `${init.method} ${url.slice(CONFIG.url.length)}`;
    const reply = routes[key];
    if (reply === undefined) throw new Error(`예상 밖 요청: ${key}`);
    if (reply === 'throw') throw new TypeError('Failed to fetch');
    const text = reply.body === undefined ? '' : typeof reply.body === 'string' ? reply.body : JSON.stringify(reply.body);
    if (reply.textThrows) {
      return {
        status: reply.status,
        text: async () => {
          throw new TypeError('body stream interrupted');
        },
      };
    }
    return { status: reply.status, text: async () => text };
  };
  return { fn, calls, keys: () => calls.map((c) => `${c.method} ${c.url.slice(CONFIG.url.length)}`) };
}

const SIGN_IN = 'POST /auth/v1/token?grant_type=password';
const VERIFY = 'POST /auth/v1/verify';
const AVATAR = `DELETE /storage/v1/object/avatars/${UID}.jpg`;
const RPC = 'POST /rest/v1/rpc/delete_my_account';
const LOGOUT = 'POST /auth/v1/logout?scope=local';
const SESSION_BODY = { access_token: TOKEN, token_type: 'bearer', refresh_token: 'r', user: { id: UID, email: 'me@example.com' } };

test('흐름 A 성공: 로그인 → 사진 → 삭제 RPC, 성공 뒤엔 logout 을 부르지 않는다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 200, body: [] }, [RPC]: { status: 204 } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw 1' });
  assert.deepEqual(out, { ok: true });
  assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC]);
});

test('흐름 A 머리·본문: apikey 는 늘 anon, Authorization 은 로그인 전 anon · 뒤엔 새 토큰, RPC 본문은 {}', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 404 }, [RPC]: { status: 200, body: '' } });
  await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw 1' });
  const [signIn, avatar, rpc] = f.calls;
  assert.equal(signIn.url, 'https://proj.example.test/auth/v1/token?grant_type=password');
  assert.deepEqual(signIn.body, { email: 'me@example.com', password: 'pw 1' });
  assert.equal(signIn.headers.apikey, CONFIG.anonKey);
  assert.equal(signIn.headers.Authorization, `Bearer ${CONFIG.anonKey}`);
  assert.equal(signIn.headers['Content-Type'], 'application/json');
  for (const c of [signIn, avatar, rpc]) {
    // 앱 SupabaseWorkHTTP.send 와 같은 머리 — Accept 가 없으면 PostgREST 오류 본문이 JSON 이 아닐 수 있다.
    assert.equal(c.headers.Accept, 'application/json');
  }
  for (const c of [avatar, rpc]) {
    assert.equal(c.headers.apikey, CONFIG.anonKey);
    assert.equal(c.headers.Authorization, `Bearer ${TOKEN}`);
  }
  assert.equal(avatar.body, undefined);
  assert.equal(avatar.headers['Content-Type'], undefined);
  assert.deepEqual(rpc.body, {});
});

test('흐름 A: 틀린 비밀번호면 삭제 RPC 를 부르지 않는다(왕복은 로그인 하나)', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 400, body: { code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials' } } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'nope' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'wrongCredentials' }, stage: 'signIn' });
  assert.deepEqual(f.keys(), [SIGN_IN]);
});

test('흐름 A: 로그인 응답에 토큰·사용자가 없으면 거절로 보고 더 부르지 않는다(빈 토큰으로 지우지 않는다)', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: { user: { id: UID } } } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'rejected', status: 200 }, stage: 'signIn' });
  assert.deepEqual(f.keys(), [SIGN_IN]);
});

test('흐름 A: 로그인 응답에 토큰은 있는데 사용자 id 가 없으면 거절 — 사진 경로를 avatars/.jpg 로 만들지 않는다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: { access_token: TOKEN, user: {} } } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'rejected', status: 200 }, stage: 'signIn' });
  assert.deepEqual(f.keys(), [SIGN_IN]);
  // 기준선: 같은 응답에 id 만 더하면 끝까지 간다.
  const g = fakeFetch({ [SIGN_IN]: { status: 200, body: { access_token: TOKEN, user: { id: UID } } }, [AVATAR]: { status: 200 }, [RPC]: { status: 204 } });
  assert.deepEqual(await runDeletion(g.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' }), { ok: true });
});

test('응답 본문 읽기가 실패해도 상태코드로 판정한다 — 204 RPC 는 성공(logout 없음), 400 로그인은 거절(연결 실패로 접지 않는다)', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 200 }, [RPC]: { status: 204, textThrows: true } });
  assert.deepEqual(await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' }), { ok: true });
  assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC]);
  const g = fakeFetch({ [SIGN_IN]: { status: 400, textThrows: true } });
  assert.deepEqual(await runDeletion(g.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' }), {
    ok: false,
    failure: { kind: 'rejected', status: 400 },
    stage: 'signIn',
  });
});

test('사진 지우기가 실패해도(5xx·연결 끊김) 계정 삭제는 계속한다', async () => {
  for (const avatarReply of [{ status: 500, body: { message: 'boom' } }, 'throw'] as Reply[]) {
    const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: avatarReply, [RPC]: { status: 204 } });
    const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
    assert.deepEqual(out, { ok: true });
    assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC]);
  }
});

test('삭제 RPC 가 실패하면 그 세션을 logout?scope=local 로 닫고 실패를 돌려준다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 200 }, [RPC]: { status: 503, body: { message: 'paused' } }, [LOGOUT]: { status: 204 } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'server', status: 503 }, stage: 'delete' });
  assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC, LOGOUT]);
  assert.equal(f.calls[3].headers.Authorization, `Bearer ${TOKEN}`);
});

test('함수가 없는 서버(PGRST202) → schemaMissing, 세션은 닫는다', async () => {
  const missing = { code: 'PGRST202', message: 'Could not find the function public.delete_my_account without parameters in the schema cache' };
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 404 }, [RPC]: { status: 404, body: missing }, [LOGOUT]: { status: 204 } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'schemaMissing' }, stage: 'delete' });
  assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC, LOGOUT]);
});

test('함수를 모르는 서버가 문구 없는 404 를 주면(게이트웨이 404) schemaMissing, 세션은 닫는다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 404 }, [RPC]: { status: 404, body: '<html>Not Found</html>' }, [LOGOUT]: { status: 204 } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'schemaMissing' }, stage: 'delete' });
  assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC, LOGOUT]);
});

test('첫 왕복부터 연결이 안 되면(CORS 거절 포함) network, 더 부르지 않는다', async () => {
  const f = fakeFetch({ [SIGN_IN]: 'throw' });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'network' }, stage: 'signIn' });
  assert.deepEqual(f.keys(), [SIGN_IN]);
});

test('흐름 B 성공: verify(type recovery) → 사진 → 삭제 RPC', async () => {
  const f = fakeFetch({ [VERIFY]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 404 }, [RPC]: { status: 204 } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'code', email: 'me@example.com', code: '123456' });
  assert.deepEqual(out, { ok: true });
  assert.deepEqual(f.keys(), [VERIFY, AVATAR, RPC]);
  assert.deepEqual(f.calls[0].body, { email: 'me@example.com', token: '123456', type: 'recovery' });
  assert.equal(f.calls[0].headers.Authorization, `Bearer ${CONFIG.anonKey}`);
  assert.equal(f.calls[2].headers.Authorization, `Bearer ${TOKEN}`);
});

test('흐름 B: 코드 거절이면 삭제 RPC 를 부르지 않는다', async () => {
  const f = fakeFetch({ [VERIFY]: { status: 403, body: { code: 403, error_code: 'otp_expired', msg: 'Token has expired or is invalid' } } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'code', email: 'me@example.com', code: '000000' });
  assert.deepEqual(out, { ok: false, failure: { kind: 'codeRejected' }, stage: 'verify' });
  assert.deepEqual(f.keys(), [VERIFY]);
});

test('코드 메일: POST /auth/v1/recover {email} · 429 는 남은 초를 싣는다 · 연결 실패는 network', async () => {
  const ok = fakeFetch({ 'POST /auth/v1/recover': { status: 200, body: {} } });
  assert.deepEqual(await sendRecoveryCode(ok.fn, CONFIG, 'me@example.com'), { ok: true, value: null });
  assert.deepEqual(ok.calls[0].body, { email: 'me@example.com' });
  assert.equal(ok.calls[0].headers.apikey, CONFIG.anonKey);
  const limited = fakeFetch({ 'POST /auth/v1/recover': { status: 429, body: { msg: 'For security purposes, you can only request this after 30 seconds.' } } });
  assert.deepEqual(await sendRecoveryCode(limited.fn, CONFIG, 'me@example.com'), { ok: false, failure: { kind: 'rateLimited', retryAfterSeconds: 30 } });
  const down = fakeFetch({ 'POST /auth/v1/recover': 'throw' });
  assert.deepEqual(await sendRecoveryCode(down.fn, CONFIG, 'me@example.com'), { ok: false, failure: { kind: 'network' } });
});

test('코드 메일 실패는 재설정 갈래로 좁힌다 — 429 아닌 "Email rate limit exceeded" 도 rateLimited(passwordRecoveryError)', async () => {
  const f = fakeFetch({ 'POST /auth/v1/recover': { status: 400, body: { code: 400, error_code: 'over_email_send_rate_limit', msg: 'Email rate limit exceeded' } } });
  assert.deepEqual(await sendRecoveryCode(f.fn, CONFIG, 'me@example.com'), { ok: false, failure: { kind: 'rateLimited', retryAfterSeconds: null } });
  // 기준선: 같은 모양의 다른 문구는 그냥 거절이다.
  const g = fakeFetch({ 'POST /auth/v1/recover': { status: 400, body: { code: 400, error_code: 'validation_failed', msg: 'Unable to validate email address' } } });
  assert.deepEqual(await sendRecoveryCode(g.fn, CONFIG, 'me@example.com'), { ok: false, failure: { kind: 'rejected', status: 400 } });
});

test('사용자 id 는 경로 조각으로 인코딩한다(이상한 id 가 다른 경로로 새지 않는다)', async () => {
  const odd = { ...SESSION_BODY, user: { id: '../x?y' } };
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: odd }, ['DELETE /storage/v1/object/avatars/..%2Fx%3Fy.jpg']: { status: 404 }, [RPC]: { status: 204 } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: true });
  // 사진 요청의 결과는 버려지므로(계약) 결과가 아니라 **나간 주소**를 잰다.
  assert.deepEqual(f.keys(), [SIGN_IN, 'DELETE /storage/v1/object/avatars/..%2Fx%3Fy.jpg', RPC]);
});

// ---------------------------------------------------------------------------------------------------------------
// 흐름 섬 손잡이 — 진짜 상태기계 + 가짜 fetch + 가짜 시계

test('browserFetchFrom: 쿠키·리퍼러·캐시 없이 CORS 로 — 요청 모양(메서드·머리·본문)은 그대로 넘긴다', async () => {
  const seen: { url: string; init: BrowserRequestInit }[] = [];
  const fetchLike = browserFetchFrom(async (url, init) => {
    seen.push({ url, init });
    return { status: 204, text: async () => '' };
  });
  const res = await fetchLike('https://proj.example.test/rest/v1/rpc/delete_my_account', { method: 'POST', headers: { apikey: 'k', Authorization: 'Bearer t' }, body: '{}' });
  assert.equal(res.status, 204);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].url, 'https://proj.example.test/rest/v1/rpc/delete_my_account');
  // credentials 는 'omit' 이어야 한다 — 'include' 면 Supabase 의 ACAO '*' 응답을 브라우저가 거절해 모든 왕복이 network 가 된다.
  assert.deepEqual(seen[0].init, {
    method: 'POST',
    headers: { apikey: 'k', Authorization: 'Bearer t' },
    body: '{}',
    mode: 'cors',
    credentials: 'omit',
    cache: 'no-store',
    referrerPolicy: 'no-referrer',
  });
});

const T0 = 1_700_000_000_000;

/** 화면의 ref·setState 대역 — 진짜 reduce 로 상태를 굴리고 받은 이벤트와 시계 알림을 적는다. */
function harness(fetchFn: FetchLike, from: DeleteAccountState = initialState, clock: number[] = [T0]) {
  let state = from;
  const events: DeleteAccountEvent[] = [];
  const ticks: number[] = [];
  let i = 0;
  const ctx: FlowContext = {
    config: CONFIG,
    fetch: fetchFn,
    now: () => clock[Math.min(i++, clock.length - 1)],
    current: () => state,
    apply: (e) => {
      events.push(e);
      state = reduce(state, e);
      return state;
    },
    tick: (t) => ticks.push(t),
  };
  return { ctx, events, ticks, state: () => state, types: () => events.map((e) => e.type) };
}

const RECOVER = 'POST /auth/v1/recover';
const ready = (events: DeleteAccountEvent[], from: DeleteAccountState = initialState) => events.reduce(reduce, from);
const readyA = ready([{ type: 'email', value: ' Me@Example.com ' }, { type: 'password', value: 'pw 1' }, { type: 'acknowledge', value: true }]);

test('submitFlow(흐름 A): 성공이면 deleted — 화면은 "지웠어요"로 가고 비밀번호가 비워진다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 200 }, [RPC]: { status: 204 } });
  const h = harness(f.fn, readyA);
  await submitFlow(h.ctx);
  assert.deepEqual(h.types(), ['submit', 'deleted']);
  assert.equal(h.state().phase, 'deleted');
  assert.equal(h.state().password, '');
  assert.deepEqual(f.calls[0].body, { email: 'me@example.com', password: 'pw 1' });
});

test('submitFlow(흐름 A): 삭제가 실패하면 deleted 가 아니라 deleteFailed — 화면에 "지웠어요"가 뜨지 않는다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 200 }, [RPC]: { status: 403, body: { code: '42501', message: 'permission denied' } }, [LOGOUT]: { status: 204 } });
  const h = harness(f.fn, readyA);
  await submitFlow(h.ctx);
  assert.deepEqual(h.types(), ['submit', 'deleteFailed']);
  assert.deepEqual(h.events[1], { type: 'deleteFailed', failure: { kind: 'rejected', status: 403 }, stage: 'delete' });
  assert.equal(h.state().phase, 'editing');
  assert.deepEqual(h.state().notice, { text: TEXT.deleteRejected, tone: 'error' });
  assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC, LOGOUT]);
});

test('submitFlow: 틀린 비밀번호는 signIn 단계 실패 — 삭제 RPC 0, 비밀번호 칸만 비운다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 400, body: { error_code: 'invalid_credentials', msg: 'Invalid login credentials' } } });
  const h = harness(f.fn, readyA);
  await submitFlow(h.ctx);
  assert.deepEqual(h.events[1], { type: 'deleteFailed', failure: { kind: 'wrongCredentials' }, stage: 'signIn' });
  assert.equal(h.state().password, '');
  assert.equal(h.state().email, 'me@example.com');
  assert.deepEqual(f.keys(), [SIGN_IN]);
});

test('submitFlow: 체크 없이 누르면 아무것도 보내지 않는다(흐름 A·B 둘 다)', async () => {
  const f = fakeFetch({});
  const a = harness(f.fn, ready([{ type: 'acknowledge', value: false }], readyA));
  await submitFlow(a.ctx);
  const sentB = ready([{ type: 'mode', mode: 'code' }, { type: 'email', value: 'me@example.com' }, { type: 'requestCode', now: T0 }, { type: 'codeSent', now: T0 }, { type: 'code', value: '123456' }]);
  const b = harness(f.fn, sentB);
  await submitFlow(b.ctx);
  assert.equal(f.calls.length, 0);
  assert.equal(a.state().notice?.text, TEXT.acknowledgeRequired);
  assert.equal(b.state().notice?.text, TEXT.acknowledgeRequired);
});

test('submitFlow: 두 번 연달아 눌러도(렌더 사이) 요청은 한 벌 — 첫 누름이 곧바로 deleting 으로 바꾼다', async () => {
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 200 }, [RPC]: { status: 204 } });
  const h = harness(f.fn, readyA);
  await Promise.all([submitFlow(h.ctx), submitFlow(h.ctx)]);
  assert.deepEqual(f.keys(), [SIGN_IN, AVATAR, RPC]);
  assert.equal(h.state().phase, 'deleted');
});

const codeA = ready([{ type: 'mode', mode: 'code' }, { type: 'email', value: '  Me@Example.COM \n' }]);

test('requestCodeFlow: 보낼 주소는 정규화한 값 · 끝난 시각으로 화면 시계를 깨우고 5초 잠근다', async () => {
  const f = fakeFetch({ [RECOVER]: { status: 200, body: {} } });
  const h = harness(f.fn, codeA, [T0, T0 + 700]);
  await requestCodeFlow(h.ctx);
  assert.deepEqual(f.calls[0].body, { email: 'me@example.com' });
  assert.deepEqual(h.types(), ['requestCode', 'codeSent']);
  assert.deepEqual(h.ticks, [T0 + 700]);
  assert.equal(h.state().codeSentTo, 'me@example.com');
  // 잠금은 왕복이 **끝난** 시각부터(앱 startCooldown 과 같다).
  assert.equal(h.state().resendAvailableAt, T0 + 700 + 5_000);
});

test('requestCodeFlow: 429 는 codeSendFailed(rateLimited) — 코드 화면으로 넘기고 서버 초로 잠근다 · 형식이 틀리면 왕복 0', async () => {
  const f = fakeFetch({ [RECOVER]: { status: 429, body: { msg: 'For security purposes, you can only request this after 42 seconds.' } } });
  const h = harness(f.fn, codeA);
  await requestCodeFlow(h.ctx);
  assert.deepEqual(h.events[1], { type: 'codeSendFailed', failure: { kind: 'rateLimited', retryAfterSeconds: 42 }, now: T0 });
  assert.equal(h.state().codeSentTo, 'me@example.com');
  assert.equal(h.state().resendAvailableAt, T0 + 42_000);
  const g = fakeFetch({});
  const bad = harness(g.fn, ready([{ type: 'mode', mode: 'code' }, { type: 'email', value: 'nope' }]));
  await requestCodeFlow(bad.ctx);
  assert.equal(g.calls.length, 0);
  assert.equal(bad.state().notice?.text, TEXT.invalidEmail);
});

test('submitFlow(흐름 B): 코드 받기 전 Enter 는 [코드 받기] · 받은 뒤엔 코드를 보낸 주소로 verify → 삭제', async () => {
  const f = fakeFetch({ [RECOVER]: { status: 200, body: {} }, [VERIFY]: { status: 200, body: SESSION_BODY }, [AVATAR]: { status: 404 }, [RPC]: { status: 204 } });
  const h = harness(f.fn, codeA);
  await submitFlow(h.ctx);
  assert.deepEqual(f.keys(), [RECOVER]);
  assert.equal(h.state().codeSentTo, 'me@example.com');
  h.ctx.apply({ type: 'code', value: '12 34 56' });
  h.ctx.apply({ type: 'acknowledge', value: true });
  await submitFlow(h.ctx);
  assert.deepEqual(f.keys(), [RECOVER, VERIFY, AVATAR, RPC]);
  assert.deepEqual(f.calls[1].body, { email: 'me@example.com', token: '123456', type: 'recovery' });
  assert.equal(h.state().phase, 'deleted');
  assert.equal(h.state().code, '');
});

test('submitFlow(흐름 B): 코드 거절이면 삭제 RPC 0 · 코드 칸을 비우고 "다시 받기" 를 말한다', async () => {
  const sentB = ready([{ type: 'requestCode', now: T0 }, { type: 'codeSent', now: T0 }, { type: 'code', value: '000000' }, { type: 'acknowledge', value: true }], codeA);
  const f = fakeFetch({ [VERIFY]: { status: 403, body: { code: 403, error_code: 'otp_expired', msg: 'Token has expired or is invalid' } } });
  const h = harness(f.fn, sentB);
  await submitFlow(h.ctx);
  assert.deepEqual(f.keys(), [VERIFY]);
  assert.deepEqual(h.events[1], { type: 'deleteFailed', failure: { kind: 'codeRejected' }, stage: 'verify' });
  assert.equal(h.state().code, '');
  assert.equal(h.state().notice?.text, TEXT.codeRejected);
});
