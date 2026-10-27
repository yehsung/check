// node --experimental-strip-types --test components/install/install-copy.test.ts
// 설치 절 계약(docs/v3/brief.md §4.5 · §8 '설치'): 문장 = §8 글자 그대로 · brew 터미널 출력 = §8(Homebrew 7 형식) · 버전은 릴리스 값 ·
// 타이핑 시간표(명령 ≈1.2초 · 줄당 120–250ms) · 줄바꿈 조각(하이픈에서 안 끊김) · installChoice(버튼·크기) · 금지어 0.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import {
  asMbFigure,
  brewTranscript,
  caskZipUrl,
  installChoice,
  INSTALL_COPY,
  metaParts,
  OHAI_ARROW,
  parseBrewInstall,
  TYPING,
  typingSchedule,
  wrapTokens,
} from '../../data/install-copy.ts';
import type { ReleaseInfo } from '../../data/fixtures.ts';

const BRIEF = readFileSync(new URL('../../docs/v3/brief.md', import.meta.url), 'utf8');
const S8 = BRIEF.slice(BRIEF.indexOf('## 8.'));
const SEC = S8.slice(S8.indexOf('\n설치(#install)'), S8.indexOf('\n자주 묻는 질문(#faq)'));
const HERO = S8.slice(S8.indexOf('\n히어로'), S8.indexOf('\n핵심 기능'));
const FIXTURES = readFileSync(new URL('../../data/fixtures.ts', import.meta.url), 'utf8');
const INSTALL_SRC = readFileSync(new URL('./Install.tsx', import.meta.url), 'utf8');

/** 주석(블록·줄·JSX)을 걷어 낸 소스 — 설명 글이 계약을 흔들지 않게 */
const stripComments = (src: string) =>
  src.replace(/\{\/\*[\s\S]*?\*\/\}/g, '').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/.*$/gm, '$1');

/** fixtures.ts 의 BREW 상수(정본 — JSON import 가 있어 node 로 못 불러와 소스에서 읽는다) */
function brewFromFixtures(): { install: string; upgrade: string } {
  const m = /export const BREW = \{\s*install:\s*'([^']+)',\s*upgrade:\s*'([^']+)'\s*\}/.exec(FIXTURES);
  assert.ok(m, 'fixtures.ts 에 BREW 상수가 없다');
  return { install: m[1], upgrade: m[2] };
}
const BREW = brewFromFixtures();

const FORBIDDEN = [
  '오픈소스', '판돈', '베팅', '내기', '걸고', '체험', '눌러 보세요', '누르', 'Learn more', '더보기', 'Mac 링크 보내기',
  '작은 팀', 'AI 토큰 리밋',
];

// ─── 문장 ───────────────────────────────────────────────────────────────────────────────────────

test('H2 = §8 두 줄 그대로(줄마다 <br>), 쉼표로 억지로 끊지 않는다', () => {
  assert.equal(INSTALL_COPY.h2.length, 2);
  assert.ok(SEC.includes(`\`${INSTALL_COPY.h2[0]}\` / \`${INSTALL_COPY.h2[1]}\``), '§8 설치 H2');
  for (const line of INSTALL_COPY.h2) assert.ok(!/,$/.test(line), `쉼표 끝 '${line}'`);
});

test('부제 · 터미널 제목 · DMG 카드 · iPhone 카드 문장 = §8 글자 그대로', () => {
  for (const s of [
    INSTALL_COPY.sub,
    INSTALL_COPY.terminalTitle,
    INSTALL_COPY.dmgTitle,
    INSTALL_COPY.dmgLine,
    INSTALL_COPY.iphoneTitle,
    INSTALL_COPY.iphoneMeta,
    INSTALL_COPY.qrCaption,
  ]) {
    assert.ok(SEC.includes(`\`${s}\``), `§8 설치에 없음: ${s}`);
  }
  // 터미널 [복사] 접근 이름 = 히어로 알약과 같은 'brew 설치 명령 복사'(§8) · 보이는 '복사' 를 포함(WCAG 2.5.3)
  assert.ok(HERO.includes(`\`${INSTALL_COPY.copyAria}\``));
  assert.ok(INSTALL_COPY.copyAria.includes('복사'));
});

test("DMG 메타 줄 = §8 'v{ver} · {mb}MB · macOS 14 이상 · Apple Silicon·Intel · Apple 공증' — 버전·크기는 릴리스 값", () => {
  assert.ok(SEC.includes(`\`${metaParts({ version: '{ver}', mb: '{mb}' as never }).join(' · ')}\``), '§8 메타 꼴');
  assert.deepEqual(metaParts({ version: '0.3.70', mb: '31.4' }), [
    'v0.3.70',
    '31.4MB',
    'macOS 14 이상',
    'Apple Silicon·Intel',
    'Apple 공증',
  ]);
});

test('업데이트 줄 삭제(§9.3): 페이지 어디에도 upgrade 명령을 보이지 않는다 · BREW.upgrade 는 README 정합용으로만 남는다', () => {
  // §8 '설치' 는 업데이트 줄을 지웠다고 적는다
  assert.ok(SEC.includes('(v3.1 삭제) 업데이트 줄'), '§8 업데이트 줄 삭제 기록');
  // 화면 소스(components · app)에 BREW.upgrade · upgrade 문자열 · 업데이트 칩이 없다
  const files = ['./Install.tsx', './BrewTerminal.tsx', '../hero/Hero.tsx', '../outro/Outro.tsx', '../glass/CommandPill.tsx', '../../app/page.tsx'];
  for (const f of files) {
    const code = stripComments(readFileSync(new URL(f, import.meta.url), 'utf8'));
    assert.ok(!/BREW\.upgrade|brew upgrade|CommandChip/.test(code), `${f} 에 업데이트 명령`);
  }
  assert.equal(existsSync(new URL('./CommandChip.tsx', import.meta.url)), false, '업데이트 칩 컴포넌트는 지웠다');
  assert.ok(!Object.keys(INSTALL_COPY).some((k) => /^update/.test(k)), 'INSTALL_COPY 에 업데이트 줄 문장이 없다');
  // README 업그레이드 문구와 BREW.upgrade 는 그대로 같다(정합)
  const readme = new URL('../../../README.md', import.meta.url);
  if (existsSync(readme)) assert.ok(readFileSync(readme, 'utf8').includes(`\`${BREW.upgrade}\``), 'README 업그레이드 문구');
});

test('금지어 0', () => {
  const text = Object.values(INSTALL_COPY).flat().join('\n');
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
});

test('터미널(§9.4.3): 명령은 어느 폭에서도 한 줄(nowrap) · 폰은 [복사] 를 제목 줄로 · 폰 글자는 폭에 맞춰 줄인다', () => {
  const code = stripComments(readFileSync(new URL('./BrewTerminal.tsx', import.meta.url), 'utf8'));
  assert.match(code, /cmd: '[^']*whitespace-nowrap/, '명령 줄 nowrap');
  assert.match(code, /barCopy: '[^']*min-\[768px\]:hidden/, '제목 줄 [복사] 는 폰에서만');
  assert.match(code, /rowCopy: '[^']*phone:hidden/, '명령 줄 [복사] 는 ≥768 에서만');
  assert.match(code, /text-\[length:min\(13\.5px,calc\(\(100vw_-_70px\)_\/_23\.6\)\)\]/, '폰 글자 = 명령 한 줄이 들어가는 크기');
  assert.equal((code.match(/<CopyButton/g) ?? []).length, 2, '[복사] 두 벌(폭으로 하나만 보인다)');
});

// ─── brew 터미널 ────────────────────────────────────────────────────────────────────────────────

const shown = (l: { kind: 'ohai' | 'done'; text: string }) => (l.kind === 'ohai' ? `${OHAI_ARROW} ${l.text}` : l.text);

test('터미널 출력 다섯 줄 = §8 그대로(Tapping · Downloading · Installing Cask · Moving App · 🍺 성공), {ver} 자리만 릴리스 값', () => {
  const lines = brewTranscript(BREW.install, '{ver}');
  assert.equal(lines.length, 5);
  assert.deepEqual(
    lines.map((l) => l.kind),
    ['ohai', 'ohai', 'ohai', 'ohai', 'done'],
  );
  for (const l of lines) assert.ok(SEC.includes(`\`${shown(l)}\``), `§8 설치 터미널에 없음: ${shown(l)}`);
  // 🍺 뒤 공백 둘(brew 원문)
  assert.ok(lines[4].text.startsWith('🍺  aing-check'));
});

test('버전은 릴리스 값으로 바뀐다(하드코딩 없음) · 다운로드 주소 = Cask url 꼴', () => {
  const a = brewTranscript(BREW.install, '0.3.70').map(shown).join('\n');
  const b = brewTranscript(BREW.install, '1.2.3').map(shown).join('\n');
  assert.ok(a.includes('/releases/download/v0.3.70/aing-check.zip'));
  assert.ok(b.includes('/releases/download/v1.2.3/aing-check.zip'));
  assert.equal(a.replaceAll('0.3.70', 'X'), b.replaceAll('1.2.3', 'X'), '버전 밖은 같다');

  const cask = new URL('../../../packaging/homebrew/aing-check.rb', import.meta.url);
  if (existsSync(cask)) {
    const m = /url "([^"]+)"/.exec(readFileSync(cask, 'utf8'));
    assert.ok(m, 'Cask 에 url 이 없다');
    assert.equal(caskZipUrl('0.3.70'), m[1].replace('__GH_OWNER__', 'yehsung').replace('#{version}', '0.3.70'));
  }
});

test('설치 절은 터미널에 릴리스 버전(installChoice)을 넘기고, 소스에 버전 숫자를 박지 않는다', () => {
  const code = stripComments(INSTALL_SRC);
  assert.match(code, /brewTranscript\(BREW\.install,\s*c\.version\)/);
  assert.match(code, /installChoice\(release,\s*RELEASE_FALLBACK\)/);
  assert.equal(/\d+\.\d+\.\d+/.test(code), false, 'Install.tsx 에 버전 숫자');
});

test('탭·토큰은 BREW.install 에서 읽는다(yehsung/check · aing-check)', () => {
  assert.equal(BREW.install, 'brew install yehsung/check/aing-check');
  assert.deepEqual(parseBrewInstall(BREW.install), { tap: 'yehsung/check', token: 'aing-check' });
  assert.equal(parseBrewInstall('brew install aing-check'), null);
  assert.equal(brewTranscript('brew install foo/bar/baz', '1.0.0')[0].text, 'Tapping foo/bar');
});

test('타이핑 시간표: 명령 ≈1.2초 · 출력 줄 간격 120–250ms · 차례대로 · 새 프롬프트는 마지막', () => {
  const plan = typingSchedule(BREW.install.length, 5);
  assert.equal(plan.chars.length, BREW.install.length);
  assert.ok(Math.abs(plan.chars.at(-1)! - 1200) <= 1, `마지막 글자 ${plan.chars.at(-1)}ms`);
  assert.equal(TYPING.typeMs, 1200);
  for (let i = 1; i < plan.chars.length; i++) assert.ok(plan.chars[i] >= plan.chars[i - 1]);
  assert.equal(plan.lines.length, 5);
  assert.ok(plan.lines[0] > plan.chars.at(-1)!, '출력은 Enter 뒤');
  for (let j = 1; j < plan.lines.length; j++) {
    const gap = plan.lines[j] - plan.lines[j - 1];
    assert.ok(gap >= 120 && gap <= 250, `줄 ${j} 간격 ${gap}ms`);
  }
  assert.ok(plan.prompt > plan.lines.at(-1)!);
  // 줄이 더 많아도 마지막 간격을 되풀이(범위 그대로)
  const more = typingSchedule(10, 8);
  for (let j = 1; j < more.lines.length; j++) {
    const gap = more.lines[j] - more.lines[j - 1];
    assert.ok(gap >= 120 && gap <= 250);
  }
  assert.deepEqual(typingSchedule(0, 0), { chars: [], lines: [], prompt: TYPING.enterMs + TYPING.promptMs });
});

test("줄바꿈 조각: 이으면 원문 · '/' 뒤에만 기회('//' 사이 제외) · 하이픈 낱말은 통째(하이픈에서 안 끊김)", () => {
  const all = [BREW.install, BREW.upgrade, ...brewTranscript(BREW.install, '0.3.70').map((l) => l.text)];
  for (const t of all) {
    const parts = wrapTokens(t);
    assert.equal(parts.map((p) => p.text).join(''), t, `원문 그대로: ${t}`);
    for (const p of parts) {
      if (p.text.includes('-') && !/\s/.test(p.text)) assert.ok(p.nowrap, `하이픈 낱말이 묶이지 않음: ${p.text}`);
      if (p.wbrAfter) assert.ok(/(\/|&& )$/.test(p.text), `줄바꿈 기회는 '/' 또는 '&& ' 뒤만: ${p.text}`);
    }
    assert.equal(parts.at(-1)!.wbrAfter, false, '맨 끝에는 기회 없음');
  }
  const url = wrapTokens(`Downloading ${caskZipUrl('0.3.70')}`);
  assert.ok(url.some((p) => p.text.endsWith('https://') && p.wbrAfter), "'https://' 뒤에서 끊을 수 있다");
  assert.ok(!url.some((p) => p.text.endsWith('https:/') && p.wbrAfter), "'//' 사이에서 끊지 않는다");
  assert.deepEqual(
    wrapTokens(BREW.install).map((p) => [p.text, p.nowrap, p.wbrAfter]),
    [
      ['brew install yehsung/', false, true],
      ['check/', false, true],
      ['aing-check', true, false],
    ],
  );
});

// ─── installChoice(DMG 버튼 · 크기) ────────────────────────────────────────────────────────────

const dmg = (bytes: number, mb: string) => ({ name: 'aing-check.dmg' as const, url: 'https://x/aing-check.dmg', bytes, mb });
const zip = (bytes: number, mb: string) => ({ name: 'aing-check.zip' as const, url: 'https://x/aing-check.zip', bytes, mb });

// RELEASE_FALLBACK 과 같은 값(아래 소스 대조 테스트가 같은지 본다)
const FALLBACK: ReleaseInfo = {
  version: '0.3.49',
  publishedAt: null,
  dmg: dmg(30054068, '30.1'),
  zip: zip(28343288, '28.3'),
  source: 'fallback',
};

test("installChoice: DMG 가 있으면 dmg · 라벨 = §8 'aing-check.dmg 다운로드' · 접근 이름 · 크기 · 버전", () => {
  const r: ReleaseInfo = { version: '0.3.50', publishedAt: null, dmg: dmg(31_250_000, '31.3'), zip: zip(29e6, '29.0'), source: 'github' };
  const c = installChoice(r, FALLBACK);
  assert.deepEqual(c, {
    file: 'dmg',
    label: 'aing-check.dmg 다운로드',
    ariaLabel: 'aing-check.dmg 다운로드, 31.3MB',
    mb: '31.3',
    version: '0.3.50',
  });
  assert.ok(SEC.includes(`\`${c.label}\``), '§8 DMG 버튼');
});

test('installChoice: DMG 없으면 zip 크기', () => {
  const r: ReleaseInfo = { version: '0.3.40', publishedAt: null, dmg: null, zip: zip(28_100_000, '28.1'), source: 'github' };
  const c = installChoice(r, FALLBACK);
  assert.equal(c.file, 'zip');
  assert.equal(c.label, 'aing-check.zip 다운로드');
  assert.equal(c.mb, '28.1');
  assert.equal(c.version, '0.3.40');
});

test('installChoice: 자산이 둘 다 없으면 폴백(0.3.49 · 30.1)', () => {
  const r: ReleaseInfo = { version: '9.9.9', publishedAt: null, dmg: null, zip: null, source: 'github' };
  const c = installChoice(r, FALLBACK);
  assert.equal(c.mb, '30.1');
  assert.equal(c.version, '0.3.49');
  assert.equal(c.ariaLabel, 'aing-check.dmg 다운로드, 30.1MB');
});

test('installChoice: mb 문자열이 이상하면 바이트에서 같은 식(소수 한 자리)으로', () => {
  const r: ReleaseInfo = { version: '0.3.51', publishedAt: null, dmg: dmg(30_054_068, '30,1MB'), zip: null, source: 'github' };
  assert.equal(installChoice(r, FALLBACK).mb, '30.1');
  const r2: ReleaseInfo = { ...r, dmg: dmg(29_959_634, '') };
  assert.equal(installChoice(r2, FALLBACK).mb, '30.0');
});

test('asMbFigure: 숫자.숫자 만 통과', () => {
  assert.equal(asMbFigure('30.1'), '30.1');
  assert.equal(asMbFigure('130.25'), '130.25');
  for (const bad of ['30', '30.', '.1', '30.1MB', '', null, undefined, '3O.1']) assert.equal(asMbFigure(bad), null);
});

test('RELEASE_FALLBACK(fixtures.ts 소스)이 0.3.49 · dmg 30.1 · zip 28.3 이고 위 FALLBACK 과 같다', () => {
  const block = FIXTURES.slice(FIXTURES.indexOf('export const RELEASE_FALLBACK'));
  assert.match(block, /version:\s*'0\.3\.49'/);
  assert.match(block, /name:\s*'aing-check\.dmg',[^}]*bytes:\s*30054068,\s*mb:\s*'30\.1'/);
  assert.match(block, /name:\s*'aing-check\.zip',[^}]*bytes:\s*28343288,\s*mb:\s*'28\.3'/);
});

test('v2 문장(지금, 메뉴바에. · 세 걸음 · 메뉴바 점 안내) 0', () => {
  const src = readFileSync(new URL('../../data/install-copy.ts', import.meta.url), 'utf8');
  for (const gone of ['지금, 메뉴바에.', '받은 파일을 열어요', '작은 점이 떠요', 'macOS 14 Sonoma 이상', 'installHint', 'stepsDmg']) {
    assert.equal(src.includes(gone), false, `install-copy.ts 에 '${gone}' 이 남아 있다`);
  }
});
