// node --experimental-strip-types --test lib/group-invite.test.ts
// 그룹 초대 링크 페이지(/g/<코드>)의 순수 부분: 코드 정규화 · 응답 해석 · 서버 부르기(가짜 fetch) · 기기별 행동 · 문구 · 페이지 배선.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  INVITE_COPY,
  androidIntentUrl,
  fetchGroupPreview,
  isPlausibleInviteCode,
  normalizeInviteCode,
  parsePreview,
  showsCode,
  smartBannerAppId,
  type PreviewFetch,
} from './group-invite.ts';

const CONFIG = { url: 'https://example.supabase.co', anonKey: 'anon-key' };
const src = (rel: string) => readFileSync(new URL(rel, import.meta.url), 'utf8');

test('코드 정규화: 서버 lookup_team_by_code 와 같게 공백·하이픈을 지우고 대문자로, % 인코딩을 푼다', () => {
  assert.equal(normalizeInviteCode('ab-cd 12'), 'ABCD12');
  assert.equal(normalizeInviteCode('ab%20cd'), 'ABCD');
  assert.equal(normalizeInviteCode('%E0%A4%A'), '%E0%A4%A'); // 잘못된 인코딩은 그대로 → 모양 검사에서 걸림
  assert.equal(isPlausibleInviteCode('ABCD12'), true);
  assert.equal(isPlausibleInviteCode('ABC'), false);
  assert.equal(isPlausibleInviteCode('ABCD12%'), false);
  assert.equal(isPlausibleInviteCode('가나다라'), false);
  assert.equal(isPlausibleInviteCode('A'.repeat(33)), false);
});

test('응답 해석: ok 는 이름·인원·목표·승인제, 나머지 상태는 그대로, 모양이 틀리면 unavailable', () => {
  assert.deepEqual(parsePreview({ status: 'ok', team: { name: ' 파도 커피단 ', member_count: 7, weekly_goal_hours: 40, join_policy: 'approval', visibility: 'public' } }), {
    status: 'ok',
    group: { name: '파도 커피단', memberCount: 7, weeklyGoalHours: 40, needsApproval: true },
  });
  assert.deepEqual(parsePreview({ status: 'ok', team: { name: '종이 공방', member_count: 3, weekly_goal_hours: 0, join_policy: 'open' } }), {
    status: 'ok',
    group: { name: '종이 공방', memberCount: 3, weeklyGoalHours: null, needsApproval: false },
  });
  for (const s of ['not_found', 'expired', 'used_up', 'full', 'not_enabled'] as const) assert.deepEqual(parsePreview({ status: s }), { status: s });
  assert.deepEqual(parsePreview({ status: 'ok', team: { name: '', member_count: 2 } }), { status: 'unavailable' });
  assert.deepEqual(parsePreview({ status: 'ok' }), { status: 'unavailable' });
  assert.deepEqual(parsePreview({ status: 'weird' }), { status: 'unavailable' });
  assert.deepEqual(parsePreview(null), { status: 'unavailable' });
  assert.deepEqual(parsePreview([{ status: 'ok' }]), { status: 'unavailable' });
});

test('서버 부르기: team_preview 에 anon 머리·{p_code}·no-store, 쿠키·사용자 토큰 없음', async () => {
  const calls: { url: string; init: Parameters<PreviewFetch>[1] }[] = [];
  const fake: PreviewFetch = async (url, init) => {
    calls.push({ url, init });
    return { status: 200, json: async () => ({ status: 'ok', team: { name: '아잉 데모팀', member_count: 5, weekly_goal_hours: 40, join_policy: 'open' } }) };
  };
  const r = await fetchGroupPreview(fake, CONFIG, 'ABCD12');
  assert.equal(r.status, 'ok');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://example.supabase.co/rest/v1/rpc/team_preview');
  assert.equal(calls[0].init.method, 'POST');
  assert.equal(calls[0].init.cache, 'no-store');
  assert.deepEqual(JSON.parse(calls[0].init.body), { p_code: 'ABCD12' });
  assert.equal(calls[0].init.headers.apikey, 'anon-key');
  assert.equal(calls[0].init.headers.Authorization, 'Bearer anon-key');
  assert.equal(Object.keys(calls[0].init.headers).some((k) => k.toLowerCase() === 'cookie'), false);
});

test('서버 부르기: 모양이 틀린 코드는 부르지 않고 not_found, 설정이 없으면 unavailable, HTTP 실패·예외도 unavailable', async () => {
  let n = 0;
  const counting: PreviewFetch = async () => {
    n++;
    return { status: 200, json: async () => ({ status: 'ok' }) };
  };
  assert.deepEqual(await fetchGroupPreview(counting, CONFIG, 'AB'), { status: 'not_found' });
  assert.deepEqual(await fetchGroupPreview(counting, null, 'ABCD12'), { status: 'unavailable' });
  assert.equal(n, 0);
  assert.deepEqual(await fetchGroupPreview(async () => ({ status: 404, json: async () => ({}) }), CONFIG, 'ABCD12'), { status: 'unavailable' });
  assert.deepEqual(await fetchGroupPreview(async () => { throw new Error('net'); }, CONFIG, 'ABCD12'), { status: 'unavailable' });
  // 서버가 아직 team_preview 를 모르면(켜는 날 전 배포) 404 → unavailable(코드는 보여 줌)
  assert.equal(showsCode('unavailable'), true);
});

test('코드를 보여 줄지: 쓸 수 있는 코드만(없음·만료·횟수 끝·가득 참은 숨김)', () => {
  assert.equal(showsCode('ok'), true);
  assert.equal(showsCode('not_enabled'), true);
  for (const s of ['not_found', 'expired', 'used_up', 'full'] as const) assert.equal(showsCode(s), false, s);
});

test('안드로이드 intent: https 로 이 주소를 우리 패키지에 넘기고, 앱이 없으면 Play 스토어로', () => {
  const u = androidIntentUrl('aing-check.vercel.app', 'ABCD12', 'https://play.google.com/store/apps/details?id=com.yehsung.aingcheck');
  assert.equal(
    u,
    'intent://aing-check.vercel.app/g/ABCD12#Intent;scheme=https;package=com.yehsung.aingcheck;S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.yehsung.aingcheck;end',
  );
});

test('아이폰 스마트 배너: App Store id 와 이 페이지 주소', () => {
  assert.equal(smartBannerAppId('https://apps.apple.com/app/id6812768622'), '6812768622');
  assert.equal(smartBannerAppId('https://apps.apple.com/app/x'), null);
  // 루트 레이아웃의 itunes 를 덮어쓴다(other 로 따로 달면 meta 가 둘이 된다)
  assert.match(src('../app/g/[code]/page.tsx'), /itunes: \{ appId, appArgument: pageUrl \}/);
});

test('문구: 상태마다 제목·본문이 있고, 랜딩 금지어가 없다', () => {
  for (const s of ['not_found', 'expired', 'used_up', 'full', 'not_enabled', 'unavailable'] as const) {
    assert.ok(INVITE_COPY.status[s].title.length > 0 && INVITE_COPY.status[s].body.length > 0, s);
  }
  const all = JSON.stringify(INVITE_COPY) + src('../app/g/[code]/page.tsx') + src('../app/g/[code]/InviteActions.tsx');
  for (const w of ['판돈', '센터', '이메일 인증', '도박']) assert.equal(all.includes(w), false, w);
});

test('페이지 배선: 검색 제외(noindex) · 그룹 이름은 제목·미리보기에 싣지 않음 · 요청마다 렌더 · 그룹 이름은 시스템 글꼴', () => {
  const page = src('../app/g/[code]/page.tsx');
  assert.match(page, /robots:\s*\{\s*index:\s*false,\s*follow:\s*false\s*\}/);
  assert.match(page, /export const dynamic = "force-dynamic"/);
  const meta = page.slice(page.indexOf('generateMetadata'), page.indexOf('const CONFIG'));
  assert.equal(meta.includes('group.name'), false, '메타에 그룹 이름 없음');
  assert.match(page, /data-group-name=""/);
  assert.match(page, /\[font-family:var\(--font-sans\)\]/);
});

test('기기별 벌: 아이폰 App Store · 안드로이드 Play + 앱에서 열기 · 컴퓨터는 Mac 다운로드와 두 스토어(짝 노출)', () => {
  const ui = src('../app/g/[code]/InviteActions.tsx');
  const block = (dev: string) => ui.slice(ui.indexOf(`data-invite-device="${dev}"`), ui.indexOf('</div>\n\n', ui.indexOf(`data-invite-device="${dev}"`)));
  assert.match(block('ios'), /<AppStoreBadge/);
  assert.equal(block('ios').includes('PlayStoreBadge'), false);
  assert.match(block('android'), /<PlayStoreBadge/);
  assert.match(block('android'), /androidIntentUrl/);
  assert.equal(block('android').includes('AppStoreBadge'), false);
  assert.match(block('desktop'), /<DownloadCTA/);
  assert.match(block('desktop'), /<AppStoreBadge/);
  assert.match(block('desktop'), /<PlayStoreBadge/);
});

test('앱 열기 파일: 아이폰 연결 도메인 파일은 /g/* 를 우리 앱(팀 ID·번들 — ios/project.yml)에 넘기고, 안드로이드 파일은 있으면 서명 값이 채워져 있다', async () => {
  const { existsSync } = await import('node:fs');
  const aasa = JSON.parse(src('../public/.well-known/apple-app-site-association'));
  const yml = src('../../ios/project.yml');
  const team = /DEVELOPMENT_TEAM:\s*(\w+)/.exec(yml)?.[1];
  assert.ok(team, 'ios/project.yml 팀 ID');
  const detail = aasa.applinks.details[0];
  assert.deepEqual(detail.appIDs, [`${team}.com.yehsung.aingcheck`]);
  assert.deepEqual(detail.components.map((c: { '/': string }) => c['/']), ['/g/*']);
  const vercel = JSON.parse(src('../vercel.json'));
  const ct = vercel.headers.find((h: { source: string }) => h.source === '/.well-known/apple-app-site-association');
  assert.equal(ct?.headers?.[0]?.value, 'application/json');
  const al = new URL('../public/.well-known/assetlinks.json', import.meta.url);
  if (existsSync(al)) {
    const links = JSON.parse(readFileSync(al, 'utf8'));
    assert.equal(links[0].target.package_name, 'com.yehsung.aingcheck');
    for (const fp of links[0].target.sha256_cert_fingerprints) assert.match(fp, /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
  }
});
