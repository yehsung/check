// 원본: 없음
//
// node --experimental-strip-types --test lib/delete-account-page.test.ts
// /delete-account 화면의 사실 계약(Play answer/13327111 · E§9.6) — 페이지 소스를 읽어(주석은 걷고) 잰다.
//   ① 앱·개발자 이름이 등록정보 상수(STORE_LISTING)에서 온다 ② 지워지는 것·남는 것·웹에서 지우기·메일함도 못 쓸 때(지원 경로)가 있다
//   ②-1 고지 문장(지워지는 것·같이 처리되는 것·남는 것·되돌릴 수 없음)이 앱·처리방침과 같은 사실을 싣는다
//   ②-2 서버 백업은 처리방침·페이지 어디에도 싣지 않는다(2026-10-28 사용자 결정)
//   ③ 설정은 NEXT_PUBLIC_* 두 이름을 글자 그대로 읽는다(빌드 때 박힘) ④ 운영 주소·서비스 롤 키·브라우저 저장소·콘솔 0
//   ⑤ 랜딩 금지어 0(히어로·FAQ 시험과 같은 목록) ⑥ 흐름 섬 배선(체크박스·삭제 버튼·lib 손잡이 — 행동은 delete-account-client.test 가 잰다).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { STORE_LISTING, TEXT } from './delete-account.ts';

/** 소스 계약용 — 주석을 걷어낸 본문(설명을 지워야만 초록이 되는 일이 없게, faq.test 와 같은 방식). */
function code(rel: string): string {
  return readFileSync(new URL(rel, import.meta.url), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:"'])\/\/.*$/gm, '$1');
}

const PAGE = code('../app/delete-account/page.tsx');
const FLOW = code('../app/delete-account/DeleteAccountFlow.tsx');
const LIB = code('./delete-account.ts');
const CLIENT = code('./delete-account-client.ts');
const ALL = [PAGE, FLOW, LIB, CLIENT].join('\n');

test('① 앱·개발자 이름은 등록정보 상수 하나에서 온다(페이지에 이름을 따로 적지 않는다)', () => {
  assert.equal(STORE_LISTING.appName, '아잉체크');
  assert.ok(STORE_LISTING.developerName.trim().length > 0);
  assert.match(PAGE, /\{STORE_LISTING\.developerName\}/);
  assert.match(PAGE, /\{STORE_LISTING\.appName\} · 개발자/);
  assert.match(PAGE, /`\$\{STORE_LISTING\.appName\} 계정 삭제`/);
});

test('② 지워지는 것 · 같이 처리되는 것 · 남는 것 · 앱에서 지우기 · 지원 경로가 페이지에 있다', () => {
  for (const h of ['지워지는 것', '같이 처리되는 것', '남는 것', '앱에서 지우기', '메일함도 쓸 수 없다면']) {
    assert.ok(PAGE.includes(h), `절 '${h}'`);
  }
  assert.ok(FLOW.includes('웹에서 지우기'), "흐름 섬의 절 '웹에서 지우기'");
  assert.match(PAGE, /href=\{LINKS\.issues\}/, '지원 경로(GitHub Issues)');
  assert.match(PAGE, /href=\{LINKS\.privacy\}/, '보관 기간은 처리방침으로');
  assert.match(PAGE, /<DeleteAccountFlow \/>/);
  // 두 흐름(비밀번호 · 메일 코드)이 다 있다.
  assert.match(FLOW, /id: "password"/);
  assert.match(FLOW, /id: "code"/);
});

/** 페이지의 `const NAME = [ … ] as const;` 목록 본문 — 고지 문장이 그 절(지워지는 것·같이 처리되는 것·남는 것)에 있는지 본다. */
function listBlock(name: string): string {
  const m = new RegExp(`const ${name} = \\[([\\s\\S]*?)\\] as const;`).exec(PAGE);
  assert.ok(m, `목록 ${name}`);
  // 그 목록이 실제로 그려진다(목록만 남고 화면에서 빠지는 일이 없게).
  assert.match(PAGE, new RegExp(`\\{${name}\\.map\\(`), `${name} 를 그린다`);
  return m[1];
}

test('②-1 고지 문장 — 지워지는 것(앱 MeText.deleteAccountItems · docs/index.md 계정 삭제 절) · 같이 처리되는 것 · 남는 것 · 되돌릴 수 없음', () => {
  // 지워지는 것: 앱 나 탭이 보여 주는 다섯(MeText.deleteAccountItems = 근무 기록 · 메시지 · 할 일 · 캐릭터와 루비 · 순위 기록)이 다 있다.
  const deleted = listBlock('DELETED');
  for (const item of ['근무 기록', '메시지', '할 일', '캐릭터와 루비', '순위 기록']) assert.ok(deleted.includes(item), `지워지는 것 '${item}'`);
  // 처리방침 계정 삭제 절의 '같이 처리되는 것'(진행 중 대국 기권 마감 · 혼자 남은 팀 · 차단 기록 · 내가 보낸 메시지).
  const also = listBlock('ALSO');
  assert.ok(also.includes('진행 중이던 오목·체스·테트리스 대국은 지우기 전에 내가 진 것으로 끝내요'), '대국 정산');
  assert.ok(also.includes('나 혼자 남아 있던 팀은 함께 지워져요'), '혼자 남은 팀');
  assert.ok(also.includes('차단 기록은 내가 한 것도, 남이 나를 차단한 것도 함께 지워져요'), '차단 기록');
  assert.ok(also.includes('다른 사람이 받은 메시지 중 내가 보낸 것도 함께 지워져요'), '보낸 메시지');
  // 남는 것(MeText.deleteAccountFeedbackNote 의 웹 판 — 신고도 같은 set null).
  assert.ok(listBlock('KEPT').includes('보낸 제보와 신고는 작성자 없이 내용만 남아요'), '제보·신고는 익명으로 남음');
  // 되돌릴 수 없음 — 체크박스 문구(흐름 섬)와 따로, 페이지 머리 문단에도(설정이 없어 폼이 안 뜰 때도 보이게).
  assert.match(PAGE, /<p className="t-body mt-5">[\s\S]*?지운 계정은 되돌릴 수 없고[\s\S]*?<\/p>/, '머리 문단의 되돌릴 수 없음');
});

/** 처리방침(docs/privacy.md)에 서버 백업 줄이 있나 — 사용자 결정(2026-10-28)으로 두 곳 모두 백업 이야기를 싣지 않는다. */
function privacyMentionsBackup(): boolean {
  const policy = readFileSync(new URL('../../docs/privacy.md', import.meta.url), 'utf8');
  return policy.split('\n').some((l) => l.startsWith('**서버 백업**') || l.includes('〈'));
}

test('②-2 서버 백업 — 처리방침도 페이지도 백업 문장을 싣지 않는다(자리표시 〈…〉 도 남기지 않는다)', () => {
  assert.equal(privacyMentionsBackup(), false, '처리방침에 서버 백업 줄·자리표시가 없어야 한다');
  assert.equal(listBlock('KEPT').includes('백업'), false, '페이지 남는 것에 백업 문장이 없어야 한다');
});

test('③ 설정은 NEXT_PUBLIC_SUPABASE_URL · NEXT_PUBLIC_SUPABASE_ANON_KEY 를 글자 그대로 읽는다', () => {
  assert.match(FLOW, /readConfig\(process\.env\.NEXT_PUBLIC_SUPABASE_URL, process\.env\.NEXT_PUBLIC_SUPABASE_ANON_KEY\)/);
  // 설정이 없으면 폼 대신 안내 문장(앱·문의 경로)을 그린다.
  assert.match(FLOW, /if \(!CONFIG\) \{[\s\S]*?TEXT\.unavailable/);
});

test('④ 운영 주소·비밀 키·브라우저 저장소·콘솔 출력이 없다', () => {
  assert.doesNotMatch(ALL, /\.supabase\.co/);
  // 서비스 롤 키 이름 — 저장소 비밀 검사(커밋 diff 에 그 낱말 0)에 걸리지 않게 조각으로 만든다.
  assert.doesNotMatch(ALL, new RegExp(['service', 'role'].join('_'), 'i'));
  assert.doesNotMatch(ALL, /eyJ[A-Za-z0-9_-]{20,}/);
  assert.doesNotMatch(ALL, /localStorage|sessionStorage|indexedDB|document\.cookie/);
  assert.doesNotMatch(ALL, /console\./);
});

// 히어로 copy.test · FAQ faq.test 의 금지어(같은 결). 화면 문구 전부(페이지·흐름·문구 표)에 적용한다.
const FORBIDDEN = [
  '오픈소스', '판돈', '베팅', '내기', '걸고', '체험', '눌러 보세요', 'Learn more', '더보기', 'Mac 링크 보내기', 'Gemini',
  '작은 팀', '작은 Mac', 'AI 토큰 리밋', '서울', '부산', '소마', '마에스트로', '울찌', '열품타',
  '확인 메일', '이메일 인증', '일곱', '별점', '격자', '센터',
];

test('⑤ 랜딩 금지어 0', () => {
  const text = [PAGE, FLOW, ...Object.values(TEXT)].join('\n');
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
});

test('⑥ 흐름 섬 배선: 체크박스가 삭제 버튼과 같은 자리에 그려지고, 왕복·fetch 옵션은 lib 손잡이에만 있다', () => {
  // 체크박스(되돌릴 수 없음 확인)는 삭제 버튼과 같은 조건 블록 안에, 숨김 속성 없이 바로 label 안에 있다.
  assert.match(
    FLOW,
    /\{\(state\.mode === "password" \|\| step2\) && \(\s*<>\s*<label className="[^"]*">\s*<input\s+type="checkbox"\s+checked=\{state\.acknowledged\}[\s\S]*?onChange=\{\(e\) => apply\(\{ type: "acknowledge", value: e\.target\.checked \}\)\}[\s\S]*?<button type="submit" disabled=\{!canSubmit\(state\)\}/,
  );
  assert.doesNotMatch(FLOW, /\shidden[\s>=]|aria-hidden/);
  // 제출·코드 받기는 lib 손잡이로만(행동 시험이 그 손잡이를 잰다).
  assert.match(FLOW, /void submitFlow\(ctx\)/);
  assert.match(FLOW, /void requestCodeFlow\(ctx\)/);
  assert.match(FLOW, /const browserFetch = browserFetchFrom\(\(url, init\) => fetch\(url, init\)\);/);
  assert.match(FLOW, /fetch: browserFetch/);
  // 화면이 왕복을 직접 하거나 fetch 옵션(credentials 등)을 덮어쓰지 않는다.
  assert.doesNotMatch(FLOW, /runDeletion|sendRecoveryCode|credentials|ctx\.apply\(\{ type: "deleted"/);
  assert.equal((FLOW.match(/\bfetch\(/g) ?? []).length, 1, '전역 fetch 호출은 browserFetchFrom 안 한 곳');
});
