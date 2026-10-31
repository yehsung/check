// node --experimental-strip-types --test components/install/chooser.test.ts
// 설치 선택 창 계약(docs/v3/brief.md §11 — 2026-10-30 "브루나 dmg 파일 직접 다운 같은거중 선택할 수 있게끔"):
// 값으로 확인: 문구 = §11 글자 그대로(CHOOSER_COPY 하나) · 금지어 0 · DMG 줄 메타(github · fallback — DMG 카드와 같은 값) ·
//   자리 계산 computePlacement(오른쪽 끝 맞춤 · 16px 클램프 · 줄바꿈된 CTA 줄 아래 · 위로 뒤집기 · 천장 · 스크롤) · Tab 순환 · /api/release 읽기.
// 소스 계약(꼭 필요한 것만 — 서버 컴포넌트 분기는 렌더 없이 볼 길이 없다): DownloadCTA 자리별 분기(폰 '/#install' · iOS App Store ·
//   설치 절 = 바로 /api/download) · 창이 위 순수 함수를 실제로 부른다 · 점진적 향상 · 대화상자 · CSS(z · 전이 · 감속 모션 · CSS anchor 없음).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CHOOSER_COPY, INSTALL_COPY, chooserMetaParts, installChoice, metaParts } from '../../data/install-copy.ts';
import type { ReleaseInfo } from '../../data/fixtures.ts';
import { EDGE, GAP, asRelease, computePlacement, nextFocusIndex } from './chooser-logic.ts';
import type { Box, PlaceInput } from './chooser-logic.ts';

const read = (p: string) => readFileSync(new URL(p, import.meta.url), 'utf8');
/** 주석(블록·줄·JSX)을 걷어 낸 소스 — 설명 글이 계약을 흔들지 않게 */
const code = (p: string) =>
  read(p)
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:'"`])\/\/.*$/gm, '$1');

const BRIEF = read('../../docs/v3/brief.md');
const S11 = BRIEF.slice(BRIEF.indexOf('## 11. 설치 선택 창'));
const FIXTURES = read('../../data/fixtures.ts');
const CTA = code('../ui/DownloadCTA.tsx');
const CHOOSER = code('./InstallChooser.tsx');
const LOGIC = code('./chooser-logic.ts');
const CSS = read('./install-chooser.css').replace(/\/\*[\s\S]*?\*\//g, '');

const FORBIDDEN = [
  '격자', '작은 팀', '작은 Mac', '눌러', '누르', '누른', 'AI 토큰 리밋',
  '오픈소스', '판돈', '베팅', '내기', '걸고', '체험', 'Learn more', '더보기', 'Mac 링크 보내기',
];

// ─── 문구 ───────────────────────────────────────────────────────────────────────────────────────

test('CHOOSER_COPY = 승인된 글자 그대로', () => {
  assert.deepEqual(CHOOSER_COPY, {
    ariaLabel: '아잉체크 설치 방법 선택',
    brewTitle: 'Homebrew로 설치하기',
    brewLine: '터미널에 복사해 붙여 넣으면 내려받기부터 설치까지 끝나요.',
    dmgTitle: 'DMG 파일 직접 내려받기',
    phoneTitle: '휴대폰 앱',
    phoneIphone: '아이폰',
    phoneAndroid: '안드로이드 베타',
    more: '설치 방법 자세히 보기',
  });
  // 한 줄은 설치 절 부제와 같은 상수(따로 적지 않는다)
  assert.equal(CHOOSER_COPY.brewLine, INSTALL_COPY.sub);
  const src = read('../../data/install-copy.ts');
  assert.match(src, /brewLine:\s*INSTALL_COPY\.sub/, '한 줄은 INSTALL_COPY.sub 를 가리킨다');
});

test('§11 에 문구가 글자 그대로 있다 · 사용자 원문이 남아 있다', () => {
  assert.ok(S11.length > 0, 'brief §11');
  assert.ok(S11.includes('브루나 dmg 파일 직접 다운 같은거중 선택할 수 있게끔 하자'), '§11 사용자 원문');
  for (const s of Object.values(CHOOSER_COPY)) assert.ok(S11.includes(`\`${s}\``), `§11 에 없음: ${s}`);
  assert.ok(S11.includes('`v{ver} · {mb}MB · Apple 공증`'), '§11 메타 꼴');
});

test('금지어 0 · 맥 동작은 클릭', () => {
  const text = Object.values(CHOOSER_COPY).join('\n');
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
  for (const w of FORBIDDEN) assert.ok(!S11.includes(w), `§11 에 금지어 '${w}'`);
});

test('창 소스는 CHOOSER_COPY · INSTALL_COPY · BREW 만 읽는다(한글 리터럴 0 — 정본 하나)', () => {
  assert.equal(/[가-힣]/.test(CHOOSER), false, 'InstallChooser.tsx 에 한글 리터럴');
  for (const k of ['ariaLabel', 'brewTitle', 'brewLine', 'dmgTitle', 'phoneTitle', 'phoneIphone', 'phoneAndroid', 'more']) assert.ok(CHOOSER.includes(`CHOOSER_COPY.${k}`), `CHOOSER_COPY.${k}`);
  assert.match(CHOOSER, /ariaLabel=\{INSTALL_COPY\.copyAria\}/, "[복사] 접근 이름 = 'brew 설치 명령 복사'");
  assert.equal(INSTALL_COPY.copyAria, 'brew 설치 명령 복사');
});

// ─── DMG 줄 메타 ────────────────────────────────────────────────────────────────────────────────

const dmg = (bytes: number, mb: string) => ({ name: 'aing-check.dmg' as const, url: 'https://x/aing-check.dmg', bytes, mb });
const zip = (bytes: number, mb: string) => ({ name: 'aing-check.zip' as const, url: 'https://x/aing-check.zip', bytes, mb });
const FALLBACK: ReleaseInfo = { version: '0.3.49', publishedAt: null, dmg: dmg(30054068, '30.1'), zip: zip(28343288, '28.3'), source: 'fallback' };
const GITHUB: ReleaseInfo = { version: '0.3.68', publishedAt: '2026-10-30T00:00:00Z', dmg: dmg(31_412_000, '31.4'), zip: zip(29e6, '29.0'), source: 'github' };

test("메타(github): 'v{ver} · {mb}MB · Apple 공증' — 릴리스 값", () => {
  const parts = chooserMetaParts(installChoice(GITHUB, FALLBACK));
  assert.deepEqual(parts, ['v0.3.68', '31.4MB', 'Apple 공증']);
  assert.equal(parts.join(' · '), 'v0.3.68 · 31.4MB · Apple 공증');
});

test('메타(fallback): DMG 카드와 같은 값(RELEASE_FALLBACK) — 카드 메타에서 버전·크기·공증만', () => {
  const c = installChoice(FALLBACK, FALLBACK);
  const parts = chooserMetaParts(c);
  assert.deepEqual(parts, ['v0.3.49', '30.1MB', 'Apple 공증']);
  const card = metaParts(c);
  assert.deepEqual(parts, card.filter((p) => parts.includes(p)), '카드 메타의 부분열(순서 그대로)');
  assert.deepEqual(parts, [card[0], card[1], card.at(-1)]);
  // 자산 없는 github 응답 → installChoice 가 폴백을 고른다(카드와 같다)
  const empty: ReleaseInfo = { ...GITHUB, dmg: null, zip: null };
  assert.deepEqual(chooserMetaParts(installChoice(empty, FALLBACK)), ['v0.3.49', '30.1MB', 'Apple 공증']);
});

test('메타: 모르는 항목만 뺀다(크기 0 · 빈 버전) · 공증은 늘 끝', () => {
  assert.deepEqual(chooserMetaParts({ version: '0.3.70', mb: '0.0' }), ['v0.3.70', 'Apple 공증']);
  assert.deepEqual(chooserMetaParts({ version: '', mb: '30.1' }), ['30.1MB', 'Apple 공증']);
  assert.deepEqual(chooserMetaParts({ version: ' ', mb: '0.0' }), ['Apple 공증']);
  assert.equal(INSTALL_COPY.metaTail.at(-1), 'Apple 공증');
});

// ─── 자리 계산(값) ──────────────────────────────────────────────────────────────────────────────

const box = (left: number, top: number, w: number, h: number): Box => ({ left, top, right: left + w, bottom: top + h });
const POP = { width: 380, height: 300 };
const NAV_H = 46;
const CEILING = NAV_H + 8;
const base = (over: Partial<PlaceInput>): PlaceInput => ({
  trigger: box(120, 400, 200, 48),
  row: null,
  pop: POP,
  viewport: { width: 1440, height: 900 },
  navH: NAV_H,
  fixed: false,
  scroll: { x: 0, y: 0 },
  ...over,
});

test('자리: 히어로(1440) = 방아쇠 아래 10px · 왼쪽 맞춤', () => {
  const p = computePlacement(base({ row: box(120, 399, 700, 50) }));
  assert.deepEqual(p, { top: 449 + GAP, left: 120, side: 'below', align: 'left', scrollBy: 0 }, '한 줄이면 줄 아래끝(알약이 1px 더 길면 그만큼) + 10 · 굴리지 않는다');
  assert.equal(computePlacement(base({})).top, 448 + GAP, '줄이 없으면 방아쇠 아래');
});

test('자리: 메뉴바(오른쪽 끝) = 방아쇠 오른쪽 끝 맞춤 · fixed 는 스크롤을 더하지 않는다', () => {
  for (const vw of [1024, 1280, 1440, 1920]) {
    const trigger = box(vw - 24 - 96, 7, 96, 32);
    const p = computePlacement(base({ trigger, viewport: { width: vw, height: 768 }, fixed: true, scroll: { x: 0, y: 3000 } }));
    assert.equal(p.align, 'right', `${vw} 오른쪽 맞춤`);
    assert.equal(p.left, trigger.right - POP.width, `${vw} 창 오른쪽 끝 = 방아쇠 오른쪽 끝`);
    assert.ok(p.left >= EDGE && p.left + POP.width <= vw - EDGE, `${vw} 화면 안`);
    assert.equal(p.top, trigger.bottom + GAP, `${vw} 스크롤과 무관`);
    assert.equal(p.side, 'below');
  }
});

test('자리: 화면 안 16px 클램프(왼쪽 · 오른쪽)', () => {
  assert.equal(computePlacement(base({ trigger: box(4, 400, 120, 48) })).left, EDGE, '왼쪽 끝');
  const narrow = computePlacement(base({ trigger: box(100, 400, 100, 48), pop: { width: 360, height: 300 }, viewport: { width: 400, height: 900 } }));
  assert.equal(narrow.left, EDGE, '오른쪽 맞춤이 왼쪽 밖으로 나가면 16');
  assert.equal(narrow.align, 'right');
});

test('자리: 폭이 좁아 brew 알약이 아래 줄로 내려가면(768–1180) 줄 아래에 연다 — 알약을 반쯤 덮지 않는다', () => {
  for (const vw of [768, 1024, 1180]) {
    const trigger = box(64, 384, 196, 48);
    const row = box(64, 384, 478, 48 + 12 + 48); // 알약(478)이 둘째 줄
    const p = computePlacement(base({ trigger, row, viewport: { width: vw, height: 900 } }));
    assert.equal(p.side, 'below', `${vw}`);
    assert.equal(p.top, row.bottom + GAP, `${vw} 줄 아래끝 + 10`);
    assert.ok(p.top >= row.bottom, `${vw} 알약과 겹치지 않음`);
  }
});

test('자리: 아래가 모자라고 위(메뉴바 아래 8px)에 다 들어가면 위로 — 위로 열면 줄 위끝 − 10', () => {
  const trigger = box(120, 500, 200, 48);
  const p = computePlacement(base({ trigger, viewport: { width: 1280, height: 700 } }));
  assert.equal(p.side, 'above');
  assert.equal(p.top, 500 - GAP - POP.height);
  assert.equal(p.align, 'left');
});

test('자리: 위아래 어디에도 다 안 들어가고 굴릴 수 없으면(docHeight 없음) 아래(문서 기준 — 스크롤로 마저 본다) · 위로 열어 메뉴바/화면 위끝을 넘지 않는다', () => {
  // 1024×560 · 1280×600 같은 낮은 창
  for (const [vw, vh, y] of [[1024, 560, 300], [1280, 600, 330]]) {
    const trigger = box(64, y, 196, 48);
    const p = computePlacement(base({ trigger, viewport: { width: vw, height: vh } }));
    assert.equal(p.side, 'below', `${vw}×${vh}`);
    assert.equal(p.top, y + 48 + GAP, `${vw}×${vh}`);
    assert.equal(p.scrollBy, 0, `${vw}×${vh} 굴리지 않는다`);
  }
  // 성질: 위로 열면 언제나 천장 아래, 아래로 열면 언제나 기준 아래
  for (let vh = 400; vh <= 1200; vh += 50) {
    for (let y = 60; y < vh; y += 37) {
      const trigger = box(120, y, 200, 48);
      const row = box(120, y, 478, (y % 2 ? 48 : 108));
      const p = computePlacement(base({ trigger, row, viewport: { width: 1280, height: vh } }));
      if (p.side === 'above') {
        assert.ok(p.top >= CEILING, `천장 ${vh}/${y}: ${p.top}`);
        assert.ok(p.top + POP.height <= y - GAP, `방아쇠 위 ${vh}/${y}`);
      } else {
        assert.ok(p.top >= row.bottom + GAP, `아래 ${vh}/${y}`);
      }
    }
  }
});

// 검증 지적(2026-10-30): 휴대폰 줄로 창이 273 → 313px. 낮은 노트북 창(657–713)에서 페이지 끝 아웃트로 [Mac용 다운로드](방아쇠 위끝 ≈ vh − 337)는
// 위(천장 54)에도 아래에도 다 안 들어가 아래로 열리고 '설치 방법 자세히 보기'가 화면 밖으로 잘렸다(1440×700 실측 창 425–738).
// 이제 덜 굴리는 쪽으로 열고 모자란 만큼 페이지를 굴린다 — 아래 값은 실측 방아쇠 자리 그대로.
const OUTRO_POP = { width: 380, height: 313 };
const DOC_H = 6200;
/** 굴린 뒤(브라우저처럼 0 ~ 최대 스크롤로 자른다) 창의 화면 자리 */
function afterScroll(i: PlaceInput, p: ReturnType<typeof computePlacement>) {
  const popDocBottom = p.top + i.pop.height;
  const maxScroll = Math.max(i.docHeight ?? 0, popDocBottom) - i.viewport.height;
  const y = Math.max(0, Math.min(maxScroll, i.scroll.y + p.scrollBy));
  const shift = y - i.scroll.y;
  return { top: p.top - y, bottom: popDocBottom - y, rowTop: (i.row ?? i.trigger).top - shift, rowBottom: (i.row ?? i.trigger).bottom - shift };
}

test('자리: 낮은 노트북 창의 페이지 끝 아웃트로(1440×700 · 1366×657 · 1280×680) — 위로 열고 모자란 만큼 위로 굴려 창이 다 보인다', () => {
  for (const [vw, vh, y] of [[1440, 700, 363], [1366, 657, 321], [1280, 680, 344]]) {
    const scrollY = DOC_H - vh; // 페이지 끝
    const trigger = box(vw / 2 - 98, y, 196, 52);
    const row = box(vw / 2 - 250, y, 500, 52);
    const i = base({ trigger, row, pop: OUTRO_POP, viewport: { width: vw, height: vh }, scroll: { x: 0, y: scrollY }, docHeight: DOC_H });
    const p = computePlacement(i);
    assert.equal(p.side, 'above', `${vw}×${vh}`);
    assert.equal(p.scrollBy, -Math.ceil(CEILING - (y - GAP - OUTRO_POP.height)), `${vw}×${vh} 모자란 만큼만 위로`);
    const a = afterScroll(i, p);
    assert.ok(a.top >= CEILING, `${vw}×${vh} 천장 아래: ${a.top}`);
    assert.ok(a.bottom <= a.rowTop - GAP, `${vw}×${vh} 줄 위 10px: ${a.bottom} / ${a.rowTop}`);
    assert.ok(a.rowBottom <= vh - EDGE, `${vw}×${vh} 방아쇠도 화면 안`);
  }
  // 1440×700 = 지적의 바로 그 값(방아쇠 위끝 363 · 창 313): 14px 만 굴린다
  const p = computePlacement(base({ trigger: box(622, 363, 196, 52), pop: OUTRO_POP, viewport: { width: 1440, height: 700 }, scroll: { x: 0, y: 5500 }, docHeight: DOC_H }));
  assert.deepEqual([p.side, p.scrollBy, p.top], ['above', -14, 5500 + 363 - GAP - 313]);
});

test('자리: 페이지 맨 위 낮은 창(히어로 1024×560 — 위로 굴릴 자리 없음) = 아래로 열고 아래로 굴린다 · 메뉴바(fixed) · 너무 낮은 창은 굴리지 않는다', () => {
  const i = base({ trigger: box(64, 300, 196, 48), viewport: { width: 1024, height: 560 }, docHeight: DOC_H });
  const p = computePlacement(i);
  assert.equal(p.side, 'below');
  assert.equal(p.scrollBy, 300 + 48 + GAP + POP.height - (560 - EDGE));
  const a = afterScroll(i, p);
  assert.equal(a.bottom, 560 - EDGE, '창 아래끝 = 바닥');
  assert.ok(a.rowTop >= CEILING, '방아쇠는 메뉴바 아래에 남는다');
  // 메뉴바 창(fixed — 굴려도 따라오지 않는다)
  const f = computePlacement(base({ trigger: box(900, 7, 96, 32), viewport: { width: 1024, height: 300 }, fixed: true, scroll: { x: 0, y: 2000 }, docHeight: DOC_H }));
  assert.equal(f.scrollBy, 0);
  // 가로로 눕힌 폰(915×412): 창 + 간격 + 줄이 천장~바닥보다 길다 → 옛 규칙(아래 · 굴리지 않음)
  const low = computePlacement(base({ trigger: box(64, 200, 196, 52), pop: OUTRO_POP, viewport: { width: 915, height: 412 }, scroll: { x: 0, y: 3000 }, docHeight: DOC_H }));
  assert.deepEqual([low.side, low.scrollBy], ['below', 0]);
});

test('자리: 성질 — 굴릴 수 있으면 굴린 뒤 창은 늘 천장 아래 · 화면 안 · 줄과 겹치지 않는다(높이 600–1200 · 방아쇠 자리 · 스크롤 위치 전부)', () => {
  for (let vh = 600; vh <= 1200; vh += 25) {
    for (let y = 60; y < vh - 60; y += 23) {
      for (const scrollY of [0, 120, 2000, DOC_H - vh]) {
        const trigger = box(120, y, 196, 52);
        const row = box(120, y, 478, y % 2 ? 52 : 112);
        const i = base({ trigger, row, pop: OUTRO_POP, viewport: { width: 1280, height: vh }, scroll: { x: 0, y: scrollY }, docHeight: DOC_H });
        const p = computePlacement(i);
        const a = afterScroll(i, p);
        const tag = `${vh}/${y}/${scrollY}`;
        assert.ok(a.top >= CEILING, `천장 ${tag}: ${a.top}`);
        assert.ok(a.bottom <= vh, `화면 안 ${tag}: ${a.bottom}`);
        if (p.side === 'above') assert.ok(a.bottom <= a.rowTop - GAP, `줄 위 ${tag}`);
        else assert.ok(a.top >= a.rowBottom + GAP, `줄 아래 ${tag}`);
        if (p.scrollBy === 0) assert.ok(a.bottom <= vh - EDGE, `안 굴리면 바닥 위 ${tag}`);
      }
    }
  }
});

test('자리: 문서 기준(absolute)은 스크롤을 더한다', () => {
  const p = computePlacement(base({ scroll: { x: 0, y: 1200 } }));
  assert.equal(p.top, 448 + GAP + 1200);
  assert.equal(p.left, 120);
});

test('Tab 순환: 창 안이면 다음·이전(끝에서 처음으로) · 창 밖(−1)이면 처음/끝 · 항목 없으면 −1', () => {
  assert.equal(nextFocusIndex(3, 0, false), 1);
  assert.equal(nextFocusIndex(3, 2, false), 0);
  assert.equal(nextFocusIndex(3, 0, true), 2);
  assert.equal(nextFocusIndex(3, 1, true), 0);
  assert.equal(nextFocusIndex(3, -1, false), 0);
  assert.equal(nextFocusIndex(3, -1, true), 2);
  assert.equal(nextFocusIndex(0, -1, false), -1);
});

// /api/release 실제 응답(0.3.67 프로덕션 빌드의 프리렌더 본문 그대로)
const RELEASE_JSON = `{"version":"0.3.67","publishedAt":"2026-10-26T22:32:43Z","dmg":{"name":"aing-check.dmg","url":"https://github.com/yehsung/check/releases/download/v0.3.67/aing-check.dmg","bytes":39010106,"mb":"39.0"},"zip":{"name":"aing-check.zip","url":"https://github.com/yehsung/check/releases/download/v0.3.67/aing-check.zip","bytes":37323958,"mb":"37.3"},"source":"github"}`;

test('/api/release 읽기(asRelease): 실제 응답 → 같은 ReleaseInfo → 메타 v0.3.67 · 39.0MB · Apple 공증', () => {
  const r = asRelease(JSON.parse(RELEASE_JSON));
  assert.deepEqual(r, JSON.parse(RELEASE_JSON));
  assert.deepEqual(chooserMetaParts(installChoice(r!, FALLBACK)), ['v0.3.67', '39.0MB', 'Apple 공증']);
});

test('/api/release 읽기: 이상한 모양은 null(→ 폴백) · 모르는 자산은 null · 모르는 source 는 fallback', () => {
  for (const bad of [null, 'x', 42, {}, { version: '' }, { version: 3 }]) assert.equal(asRelease(bad), null, JSON.stringify(bad));
  const odd = asRelease({ version: '0.3.70', dmg: { name: 'evil.dmg', bytes: 1, mb: '1.0' }, zip: { name: 'aing-check.zip', bytes: '1', mb: '1.0' }, source: 'cdn' });
  assert.deepEqual(odd, { version: '0.3.70', publishedAt: null, dmg: null, zip: null, source: 'fallback' });
  // 자산 없는 응답 → DMG 카드처럼 폴백 값
  assert.deepEqual(chooserMetaParts(installChoice(odd!, FALLBACK)), ['v0.3.49', '30.1MB', 'Apple 공증']);
});

// ─── DownloadCTA 자리별 분기(소스 계약) ─────────────────────────────────────────────────────────

test("LINKS: download = '/api/download' · install = '/#install' · appStore 그대로", () => {
  assert.match(FIXTURES, /download: '\/api\/download'/);
  assert.match(FIXTURES, /install: '\/#install'/);
  assert.match(FIXTURES, /appStore: 'https:\/\/apps\.apple\.com\/app\/id\d+'/);
});

test('설치 절(placement install)은 그대로 바로 내려받는 /api/download 링크(선택 창 없음)', () => {
  assert.match(CTA, /const href = file === "zip" \? LINKS\.downloadZip : LINKS\.download;/);
  const at = CTA.indexOf('if (placement === "install")');
  assert.ok(at > 0, 'install 분기');
  const block = CTA.slice(at, CTA.indexOf('}', CTA.indexOf('</a>', at)));
  assert.match(block, /<a href=\{href\}[^>]*data-cta=\{placement\}/, '설치 절 = <a href={href}>');
  assert.ok(!/InstallChooser/.test(block), '설치 절엔 선택 창 없음');
  assert.ok(at < CTA.indexOf('<InstallChooser'), '설치 절은 선택 창보다 먼저 돌아간다');
  assert.match(code('./Install.tsx'), /<DownloadCTA[\s\S]*?placement="install"/, 'Install.tsx 의 DMG 카드');
});

test('메뉴바 폰(< 768) = 같은 글자로 설치 절(/#install) 링크 · ≥768 = 선택 창', () => {
  assert.match(CTA, /chooser\("phone:hidden"\)/, '≥768 선택 창');
  const phone = /<a href=\{LINKS\.install\}[^>]*className=\{cx\(btn, "hidden phone:inline-flex"\)\}>\s*\{text\}/.exec(CTA);
  assert.ok(phone, '폰 = /#install 링크(같은 글자)');
  assert.match(phone[0], /data-cta=\{`\$\{placement\}-install`\}/, "폰 짝 표식 'nav-install'(창이 폭 줄어 닫힐 때 포커스를 넘기는 곳)");
  assert.match(CTA, /placement === "nav" \? navPair : chooser\(\)/, 'hero·outro = 선택 창');
});

test('iOS: 메뉴바 = App Store 버튼 · hero/outro 는 아무것도 그리지 않는다(배지가 맨 앞) · mac·other 벌만 선택 창', () => {
  assert.match(CTA, /ios: "cta-ios hidden \[html\[data-platform=ios\]_&\]:contents"/);
  assert.match(CTA, /mac: "cta-mac contents \[html\[data-platform=ios\]_&\]:hidden/);
  const iosAt = CTA.indexOf('<span className={VIS.ios}>');
  assert.ok(CTA.lastIndexOf('placement === "nav" &&', iosAt) > 0, 'iOS 벌은 메뉴바만');
  const ios = CTA.slice(iosAt, CTA.indexOf('</span>', iosAt));
  assert.match(ios, /<a href=\{LINKS\.appStore\} target="_blank" rel="noopener noreferrer"/);
  assert.ok(!/InstallChooser|chooser\(/.test(ios), 'iOS 벌엔 선택 창 없음');
  assert.match(CTA, /<span className=\{VIS\.mac\}>\{main\}<\/span>/);
  assert.match(CTA, /<span className=\{VIS\.other\}>\{main\}<\/span>/);
});

test('히어로·아웃트로: 폰/iOS 벌(App Store 배지 먼저 → /#install)은 그대로 · 넓은 벌 = 릴리스 넘김 · CTA 줄 표식 · 방아쇠 이름 = 보이는 글자', () => {
  const hero = code('../hero/Hero.tsx');
  const narrow = hero.slice(hero.indexOf('<span className={NARROW}>'));
  assert.ok(narrow.indexOf('<AppStoreBadge') >= 0 && narrow.indexOf('<AppStoreBadge') < narrow.indexOf('href={LINKS.install}'), '히어로 폰: 배지 → /#install');
  assert.match(narrow, /href=\{LINKS\.install\} data-cta="hero-install"/, "히어로 폰 짝 표식 'hero-install'");
  const heroCta = /<DownloadCTA placement="hero"[^>]*\/>/.exec(hero)?.[0] ?? '';
  assert.match(heroCta, /release=\{release\}/);
  assert.ok(!/ariaLabel=/.test(heroCta), '히어로 방아쇠는 파일 이름·크기를 읽지 않는다(바로 받지 않으니까)');
  assert.match(hero, /<div data-hero-cta="" data-chooser-row=""/, '히어로 CTA 줄 = 자리 기준');
  const outro = code('../outro/Outro.tsx');
  const oNarrow = outro.slice(outro.indexOf('placement="outro-phone"'));
  assert.match(oNarrow, /href=\{LINKS\.install\} data-cta="outro-install"/, '아웃트로 폰: /#install');
  const outroCta = /<DownloadCTA\s+placement="outro"[\s\S]*?\/>/.exec(outro)?.[0] ?? '';
  assert.match(outroCta, /release=\{release\}/);
  assert.ok(!/ariaLabel=/.test(outroCta), '아웃트로 방아쇠도 보이는 글자가 이름');
  assert.ok(outro.lastIndexOf('data-chooser-row=""', outro.indexOf('placement="outro"')) > 0, '아웃트로 CTA 줄 = 자리 기준');
  assert.match(code('../site/NavShell.tsx'), /<DownloadCTA placement="nav"[^>]*release=\{release\}/);
  assert.match(code('../../app/page.tsx'), /<SiteNav release=\{release\} \/>/);
});

// ─── 창(소스 계약 — 부르는 자리) ───────────────────────────────────────────────────────────────

test('창은 순수 함수를 실제로 부른다: 자리 = computePlacement(+ CTA 줄) · Tab = nextFocusIndex · 메타 = asRelease', () => {
  assert.match(CHOOSER, /from '\.\/chooser-logic'/);
  assert.match(CHOOSER, /computePlacement\(\{[\s\S]*?row:[\s\S]*?\}\)/);
  assert.match(CHOOSER, /closest\('\[data-chooser-row\]'\)/);
  assert.match(CHOOSER, /nextFocusIndex\(/);
  assert.match(CHOOSER, /asRelease\(await res\.json\(\)\)/);
  assert.ok(!/function (computePlacement|asRelease|nextFocusIndex)/.test(CHOOSER), '복사본이 아니라 chooser-logic 의 것을 쓴다');
  assert.equal(/[가-힣]/.test(LOGIC), false, 'chooser-logic 에 한글 리터럴 없음');
});

test('점진적 향상: 서버 HTML 방아쇠 = /#install 링크 · 하이드레이션 뒤에만 메뉴 버튼 속성(+ tabIndex 0)', () => {
  assert.match(CHOOSER, /<a\s+ref=\{triggerRef\}\s+href=\{LINKS\.install\}/, '방아쇠 href = /#install');
  const a11y = /const a11y = hydrated\s*\?\s*\{([^}]*)\}\s*:\s*\{\}/.exec(CHOOSER)?.[1] ?? '';
  for (const k of ["role: 'button'", 'tabIndex: 0', "'aria-haspopup': 'dialog'", "'aria-expanded': open", "'aria-controls': popId"]) assert.ok(a11y.includes(k), `하이드레이션 뒤 ${k}`);
  assert.match(CHOOSER, /data-cta=\{`\$\{placement\}-chooser`\}/, "방아쇠 표식 'hero-chooser' 꼴");
  assert.ok(!CHOOSER.slice(0, CHOOSER.indexOf('createPortal(')).includes('href={LINKS.download}'), '방아쇠는 다운로드 링크가 아니다');
});

test('창: role=dialog · 접근 이름 · body 포털 · 순서(Homebrew → 구분선 → DMG 줄 → 자세히 보기) · 링크 · 표식', () => {
  const portal = CHOOSER.slice(CHOOSER.indexOf('createPortal('));
  assert.match(portal, /role="dialog"/);
  assert.match(portal, /aria-label=\{CHOOSER_COPY\.ariaLabel\}/);
  assert.match(portal, /hidden=\{!open\}/);
  assert.match(portal, /document\.body/, 'document.body 로 포털(절 쌓임 맥락 밖)');
  const order = ['CHOOSER_COPY.brewTitle', '<CopyButton', 'CHOOSER_COPY.brewLine', '{BREW.install}', '<hr', 'href={LINKS.download}', 'CHOOSER_COPY.dmgTitle', 'href={LINKS.install}', 'CHOOSER_COPY.more'];
  let at = -1;
  for (const s of order) {
    const i = portal.indexOf(s, at + 1);
    assert.ok(i > at, `순서: ${s}`);
    at = i;
  }
  assert.match(portal, /<CopyButton\s+text=\{BREW\.install\}[\s\S]*?dataCta="chooser-brew"/, '[복사] = BREW.install · chooser-brew');
  const dmgLink = /<a href=\{LINKS\.download\}[\s\S]*?(?<!=)>/.exec(portal)?.[0] ?? '';
  assert.match(dmgLink, /data-cta="chooser-dmg"/);
  assert.match(dmgLink, /onClick=\{\(\) => close\(true\)\}/, 'DMG 줄 = 닫고 방아쇠로');
  const moreLink = /<a href=\{LINKS\.install\}[\s\S]*?(?<!=)>/.exec(portal)?.[0] ?? '';
  assert.match(moreLink, /data-cta="chooser-install"/);
  assert.match(moreLink, /onClick=\{\(\) => close\(false\)\}/, '자세히 보기 = 닫고 설치 절로');
  assert.match(portal, /<DownloadGlyph \/>/, '내려받기 아이콘');
});

test('소스 계약 — 창: 휴대폰 앱 줄(§12) — DMG 줄 아래 · 자세히 보기 위 · 칩 [아이폰](App Store 새 탭 · 닫고 방아쇠로) · [안드로이드 베타](/#android · 닫고 그 자리로)', () => {
  const portal = CHOOSER.slice(CHOOSER.indexOf('createPortal('));
  const order = ['CHOOSER_COPY.dmgTitle', 'className="ic-phone"', 'CHOOSER_COPY.phoneTitle', 'href={LINKS.appStore}', 'CHOOSER_COPY.phoneIphone', 'href={LINKS.android}', 'CHOOSER_COPY.phoneAndroid', 'data-cta="chooser-install"'];
  let at = -1;
  for (const s of order) {
    const i = portal.indexOf(s, at + 1);
    assert.ok(i > at, `순서: ${s}`);
    at = i;
  }
  const iphone = /<a\s+href=\{LINKS\.appStore\}[\s\S]*?(?<!=)>/.exec(portal)?.[0] ?? '';
  assert.match(iphone, /target="_blank"/);
  assert.match(iphone, /rel="noopener noreferrer"/);
  assert.match(iphone, /data-cta="chooser-iphone"/);
  assert.match(iphone, /onClick=\{\(\) => close\(true\)\}/, '새 탭 = 닫고 방아쇠로(DMG 줄과 같다)');
  assert.match(iphone, /tabIndex=\{0\}/, 'Safari 에서도 Tab 이 선다');
  const android = /<a href=\{LINKS\.android\}[\s\S]*?(?<!=)>/.exec(portal)?.[0] ?? '';
  assert.match(android, /data-cta="chooser-android"/);
  assert.match(android, /onClick=\{\(\) => close\(false\)\}/, "'설치 방법 자세히 보기' 와 같이 닫고 그 자리로");
  assert.ok(!/target=/.test(android), '같은 탭');
  assert.match(android, /tabIndex=\{0\}/);
  for (const chip of [iphone, android]) assert.match(chip, /className="gbtn gbtn--chip ic-chip"/, '유리 칩');
  // 포커스 고리: 창 안의 보이는 a[href] 전부(칩 포함)를 nextFocusIndex 로 돈다 — 칩만 따로 빼는 선택자 없음
  assert.match(CHOOSER, /querySelectorAll<HTMLElement>\('a\[href\], button:not\(\[disabled\]\)'\)/);
  // CSS: 이름 + 칩 둘 한 줄(이름 nowrap · 칩 묶음 flex none)
  const row = /\.ic-phone \{([^}]*)\}/.exec(CSS)?.[1] ?? '';
  assert.match(row, /display:\s*flex/);
  assert.match(row, /justify-content:\s*space-between/);
  assert.match(/\.ic-phone__title \{([^}]*)\}/.exec(CSS)?.[1] ?? '', /white-space:\s*nowrap/);
  assert.match(/\.ic-phone__chips \{([^}]*)\}/.exec(CSS)?.[1] ?? '', /flex:\s*none/);
});

test('어림 — 휴대폰 줄 폭: 창 안쪽(380 − 좌우 패딩 40 = 340) 안에 이름 + 칩 둘이 한 줄로 든다(글자 폭 어림 — 한글 1em · 공백 .26em · 실측 한 줄은 scripts/android-smoke.mjs)', () => {
  const em = (s: string) => [...s].reduce((w, ch) => w + (/[가-힣]/.test(ch) ? 1 : ch === ' ' ? 0.26 : 0.6), 0);
  const chip = (s: string) => em(s) * 13.5 + 13 * 2; // .gbtn--chip 13.5px · 좌우 13px
  const width = em(CHOOSER_COPY.phoneTitle) * 13.5 + 12 + chip(CHOOSER_COPY.phoneIphone) + 6 + chip(CHOOSER_COPY.phoneAndroid);
  assert.ok(width < 340 - 2, `${Math.round(width)}px`);
});

// ─── CSS ────────────────────────────────────────────────────────────────────────────────────────

test('CSS: 전역 ic- 이름 · z(absolute 는 메뉴바 아래 · fixed 는 위) · 폭 ≤ 380 · 전이 ≤ 160ms · 감속 모션 · CSS anchor 없음', () => {
  assert.match(CHOOSER, /import '\.\/install-chooser\.css';/);
  assert.ok(!/\.module\.css/.test(CHOOSER), 'CSS 모듈 금지');
  const selectors = CSS.match(/(^|\})\s*([^{}@]+)\{/g) ?? [];
  for (const s of selectors) {
    const sel = s.replace(/^\}?\s*/, '').replace(/\{$/, '').trim();
    if (!sel) continue;
    for (const part of sel.split(',')) assert.match(part.trim(), /^\.ic-/, `ic- 로 시작하지 않는 선택자: ${part.trim()}`);
  }
  const pop = /\.ic-pop \{([^}]*)\}/.exec(CSS)?.[1] ?? '';
  assert.match(pop, /z-index:\s*calc\(var\(--z-nav, 50\) - 1\)/, '히어로·아웃트로 창은 메뉴바(50) 바로 아래 — 스크롤해도 메뉴바를 덮지 않는다');
  const fixedZ = Number(/\.ic-pop\[data-strategy="fixed"\] \{[^}]*z-index:\s*(\d+)/.exec(CSS)?.[1]);
  assert.ok(fixedZ > 50 && fixedZ < 90, `메뉴바 창 z ${fixedZ} — 메뉴바(50) 위 · 건너뛰기 링크(90) 아래`);
  assert.match(pop, /width:\s*min\(380px, calc\(100vw - 32px\)\)/);
  const transition = /transition:([^;]*);/.exec(pop)?.[1] ?? '';
  for (const prop of ['opacity', 'scale']) {
    const ms = Number(new RegExp(`${prop} (\\d+)ms`).exec(transition)?.[1]);
    assert.ok(ms > 0 && ms <= 160, `${prop} ${ms}ms`);
  }
  assert.match(CSS, /@starting-style\s*\{\s*\.ic-pop\s*\{[^}]*opacity:\s*0/);
  assert.match(CSS, /@media \(prefers-reduced-motion: reduce\)\s*\{[^}]*\.ic-pop[^{]*\{\s*transition:\s*none/);
  assert.ok(!/anchor-name|position-anchor|anchor\(/.test(CSS), 'CSS anchor 위치 지정에 기대지 않는다');
  assert.match(CSS, /\.ic-trigger\[aria-expanded="true"\] \.ic-chev \{[^}]*rotate:\s*180deg/, '열리면 꺾쇠가 뒤집힌다');
  assert.match(/\.ic-more \{([^}]*)\}/.exec(CSS)?.[1] ?? '', /border-radius:\s*\d+px/, '자세히 보기 포커스 링도 둥글게');
  assert.match(/\.ic-dmg \{([^}]*)\}/.exec(CSS)?.[1] ?? '', /background:\s*rgb\(255 255 255 \/ \.0\d\)/, 'DMG 줄은 쉬는 상태에도 옅은 판');
});
