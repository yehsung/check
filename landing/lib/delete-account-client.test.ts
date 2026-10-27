// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift @ 1b8260d (deleteAccount 순서 — 290–345)
// 원본: Sources/CheckCore/SupabaseWorkService.swift @ 1b8260d (요청 경로·본문 — 92–104, 429–498, 1320–1370)
//
// node --experimental-strip-types --test lib/delete-account-client.test.ts
// 웹 계정 삭제의 왕복 순서·머리·본문을 **가짜 fetch** 로 잰다(실서버 0). 순서가 계약이다:
//   본인 확인 → (실패면 여기서 끝) → 사진 DELETE(결과 무시) → rpc/delete_my_account `{}` → (실패면) logout?scope=local.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { DeleteAccountConfig } from './delete-account.ts';
import { runDeletion, sendRecoveryCode, type FetchLike } from './delete-account-client.ts';

const CONFIG: DeleteAccountConfig = { url: 'https://proj.example.test', anonKey: 'anon-key-x' };
const TOKEN = 'access-token-y';
const UID = '0b5f6a1e-1111-4222-8333-944445555666';

interface Call {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
}

type Reply = { status: number; body?: unknown } | 'throw';

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

test('사용자 id 는 경로 조각으로 인코딩한다(이상한 id 가 다른 경로로 새지 않는다)', async () => {
  const odd = { ...SESSION_BODY, user: { id: '../x?y' } };
  const f = fakeFetch({ [SIGN_IN]: { status: 200, body: odd }, ['DELETE /storage/v1/object/avatars/..%2Fx%3Fy.jpg']: { status: 404 }, [RPC]: { status: 204 } });
  const out = await runDeletion(f.fn, CONFIG, { mode: 'password', email: 'me@example.com', password: 'pw' });
  assert.deepEqual(out, { ok: true });
  // 사진 요청의 결과는 버려지므로(계약) 결과가 아니라 **나간 주소**를 잰다.
  assert.deepEqual(f.keys(), [SIGN_IN, 'DELETE /storage/v1/object/avatars/..%2Fx%3Fy.jpg', RPC]);
});
