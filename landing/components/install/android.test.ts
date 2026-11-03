// node --experimental-strip-types --test components/install/android.test.ts
// 안드로이드 — Play 스토어 출시 준비 중 계약(docs/v3/brief.md §12.7 — 대표 결재 11-03 "검토 통과 때 안내 내리고 '출시 준비 중'으로").
// 10-30 의 베타 세 단계(구글 그룹 가입 → 웹에서 테스터 되기 → Play 스토어 설치)를 내렸다. 테스터가 구글 그룹에서 이메일 목록으로 바뀌어
// 그룹으로 가입한 사람은 앱을 받을 수 없게 되기 때문이다.
// 값으로 확인: ANDROID_COPY 글자 · brief §12.7 에 같은 글자 · 내린 안내(그룹·테스터 주소, 베타 글자)가 화면 소스 어디에도 없다 · 금지어 0 ·
//   선택 창 글자는 ANDROID_COPY 를 가리킨다 · [ANDROID-LAUNCH] 표식이 출시 때 바꿀 자리마다 있다.
// 소스 계약(이름이 '소스 계약 —' 로 시작 — 서버 컴포넌트는 렌더 없이 볼 길이 없다): 설치 절 카드(#android · 누를 것 0) · 빛 · 폰 첫 화면 · 선택 창.
//   보이는 결과(배지 display:none · 카드 맨 앞 · 선택 창 한 줄)는 브라우저 스모크 scripts/android-smoke.mjs(npm run android:smoke)가 잰다.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { ANDROID_COPY, CHOOSER_COPY } from '../../data/install-copy.ts';
import { HERO_COPY } from '../hero/copy.ts';

const read = (p: string) => readFileSync(new URL(p, import.meta.url), 'utf8');
/** 주석(블록·줄·JSX)을 걷어 낸 소스 */
const strip = (s: string) =>
  s
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
const code = (p: string) => strip(read(p));

const BRIEF = read('../../docs/v3/brief.md');
const S127 = BRIEF.slice(BRIEF.indexOf('### 12.7 '));
const FIXTURES = read('../../data/fixtures.ts');
const INSTALL = code('./Install.tsx');
const CHOOSER = code('./InstallChooser.tsx');
const HERO = code('../hero/Hero.tsx');
const OUTRO = code('../outro/Outro.tsx');

/** 화면을 만드는 소스 전부(시험 · 문서 제외) — 주석을 걷어 낸 글자 */
function screenSources(): { path: string; src: string }[] {
  const out: { path: string; src: string }[] = [];
  for (const dir of ['app', 'components', 'data', 'lib']) {
    const base = new URL(`../../${dir}/`, import.meta.url);
    for (const rel of readdirSync(base, { recursive: true }) as string[]) {
      if (!/\.(tsx?|css|json)$/.test(rel) || /\.test\.ts$/.test(rel)) continue;
      out.push({ path: `${dir}/${rel}`, src: strip(readFileSync(new URL(rel, base), 'utf8')) });
    }
  }
  return out;
}

const FORBIDDEN = ['격자', '작은 팀', '작은 Mac', '눌러', '누르', '누른', 'AI 토큰 리밋', '판돈', '베팅', '내기', '체험', 'Learn more', '더보기'];
/** 내린 베타 안내의 흔적 — 화면 소스 어디에도 없어야 한다 */
const RETIRED = [
  'groups.google.com',
  'aingcheck-android-beta',
  'play.google.com/apps/testing',
  'androidGroup',
  'androidTesting',
  '안드로이드 베타',
  '안드로이드는 베타로',
  '테스터 되기',
  '구글 그룹',
  'data-android-help',
  'AndroidSteps',
  'aing-android-beta-step',
  'data-cta="hero-android"',
  'data-cta="outro-android"',
  'data-cta="chooser-android"',
  'data-cta="android-',
];

const allText = () => Object.values(ANDROID_COPY) as string[];

// ─── 문구 ───────────────────────────────────────────────────────────────────────────────────────

test('ANDROID_COPY = §12.7 글자 그대로(출시 준비 중 — 누를 것 없는 글자뿐)', () => {
  assert.deepEqual(ANDROID_COPY, {
    title: '안드로이드',
    line: '안드로이드 앱은 Play 스토어 출시를 준비하고 있어요.',
    chooserRow: '휴대폰 앱',
    chooserIphone: '아이폰',
    chooserAndroid: '안드로이드 출시 준비 중',
    phoneMeta: '무료 · 안드로이드 출시 준비 중 · macOS 14 이상',
  });
});

test('§12.7 에 문구가 글자 그대로 있다 · 대표 결재 원문 · [ANDROID-LAUNCH] 안내', () => {
  assert.ok(S127.length > 0, 'brief §12.7');
  assert.ok(S127.includes("\"검토 통과 때 안내 내리고 '출시 준비 중'으로\""), '대표 결재 원문');
  for (const s of allText()) assert.ok(S127.includes(`\`${s}\``), `§12.7 에 없음: ${s}`);
  assert.ok(S127.includes('[ANDROID-LAUNCH]'), '출시 때 바꿀 자리 표식');
});

test('금지어 0 · 넣지 말 것 0(이메일 주소 · APK · 안드로이드 최소 OS 버전)', () => {
  const text = allText().join('\n');
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
  assert.ok(!/@[\w.-]+\.\w+/.test(text), '이메일 주소');
  assert.ok(!/apk/i.test(text), 'APK');
  for (const s of allText()) assert.ok(!/안드로이드 \d+|Android \d+/.test(s), `안드로이드 버전 숫자: ${s}`);
  // 메타의 'macOS 14 이상' 은 맥 앱 이야기(히어로 폰 메타와 같은 끝)
  assert.ok(ANDROID_COPY.phoneMeta.endsWith(HERO_COPY.metaPhone.split(' · ').at(-1) ?? ''));
  for (const src of [INSTALL, HERO, OUTRO, CHOOSER]) assert.ok(!/\.apk|mailto:/i.test(src), 'APK · mailto');
});

test('내린 베타 안내가 화면 소스 어디에도 없다(그룹·테스터 주소 · 베타 글자 · 세 단계 섬 · 측정 표식)', () => {
  const sources = screenSources();
  assert.ok(sources.length > 30, `소스 ${sources.length}개`);
  for (const { path, src } of sources) for (const gone of RETIRED) assert.ok(!src.includes(gone), `${path} 에 '${gone}'`);
  // 세 단계 섬 파일은 지웠다
  for (const f of ['./AndroidSteps.tsx', './android-steps-logic.ts', './android-parts.tsx']) assert.ok(!existsSync(new URL(f, import.meta.url)), f);
});

test('LINKS: 그룹·테스터 주소 0 · 스토어 주소는 출시 때 쓸 자리로 남는다([ANDROID-LAUNCH]) · /#android 그대로', () => {
  assert.ok(!/androidGroup|androidTesting/.test(FIXTURES));
  assert.match(FIXTURES, /\[ANDROID-LAUNCH\][^\n]*\n\s*androidStore: 'https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.yehsung\.aingcheck',/);
  assert.match(FIXTURES, /\bandroid: '\/#android',/);
  // 스토어 주소는 화면 어디에서도 쓰지 않는다(비로그인 404 — 출시 전)
  for (const { path, src } of screenSources()) {
    if (path === 'data/fixtures.ts') continue;
    assert.ok(!src.includes('LINKS.androidStore') && !src.includes('play.google.com'), `${path} 가 스토어 주소를 쓴다`);
  }
});

test('선택 창 휴대폰 줄 글자 = ANDROID_COPY 를 가리킨다(정본 하나)', () => {
  assert.equal(CHOOSER_COPY.phoneTitle, '휴대폰 앱');
  assert.equal(CHOOSER_COPY.phoneIphone, '아이폰');
  assert.equal(CHOOSER_COPY.phoneAndroid, '안드로이드 출시 준비 중');
  const src = read('../../data/install-copy.ts');
  assert.match(src, /phoneTitle:\s*ANDROID_COPY\.chooserRow/);
  assert.match(src, /phoneIphone:\s*ANDROID_COPY\.chooserIphone/);
  assert.match(src, /phoneAndroid:\s*ANDROID_COPY\.chooserAndroid/);
});

test('[ANDROID-LAUNCH] 표식: 정식 출시 때 바꿀 자리마다 있다', () => {
  const raw = (p: string) => read(p);
  for (const p of [
    '../../data/install-copy.ts',
    '../../data/fixtures.ts',
    './Install.tsx',
    './InstallChooser.tsx',
    '../hero/Hero.tsx',
    '../outro/Outro.tsx',
    '../../lib/seo.ts',
  ]) {
    assert.ok(raw(p).includes('[ANDROID-LAUNCH]'), p);
  }
});

test('QR 자산 brand/qr-android-beta(/#android)는 파이프라인에 남는다(화면에서 안 쓴다) · assets.json 해시가 파일과 맞다 · App Store QR 그대로', () => {
  const py = read('../../scripts/make-qr.py');
  assert.match(py, /\("https:\/\/aing-check\.vercel\.app\/#android", "qr-android-beta\.svg"\)/, 'make-qr TARGETS');
  assert.match(py, /\("https:\/\/apps\.apple\.com\/app\/id6812768622", "qr-appstore\.svg"\)/, 'App Store 대상 그대로');
  const assets = JSON.parse(read('../../data/generated/assets.json')) as Record<string, { src: string; w: number; h: number; bytes: number }>;
  for (const key of ['brand/qr-android-beta', 'brand/qr-appstore']) {
    const meta = assets[key];
    assert.ok(meta, `assets.json ${key}`);
    const file = new URL(`../../public/assets/${key}.svg`, import.meta.url);
    assert.ok(existsSync(file), `${key}.svg`);
    const buf = readFileSync(file);
    assert.equal(meta.src, `/assets/${key}.svg?v=${createHash('sha1').update(buf).digest('hex').slice(0, 8)}`, `${key} ?v= 해시`);
    assert.equal(meta.bytes, buf.length);
  }
  assert.ok(!INSTALL.includes('qr-android-beta'), '설치 절은 안드로이드 QR 을 쓰지 않는다');
});

// ─── 설치 절 카드(소스 계약) ────────────────────────────────────────────────────────────────────

test('소스 계약 — 설치 절: 안드로이드 카드 = <Glass regular id="android" data-install="android"> · CARD · 칸 자리(≥768 3번째 줄 두 칸) · 안드로이드 기기면 맨 앞 · 제목·한 줄뿐(누를 것 0)', () => {
  const at = INSTALL.indexOf('function AndroidCard()');
  assert.ok(at > 0, 'AndroidCard');
  const card = INSTALL.slice(at, INSTALL.indexOf('export function Install'));
  const glass = /<Glass[\s\S]*?>/.exec(card)?.[0] ?? '';
  assert.match(glass, /level="regular"/);
  assert.match(glass, /id="android"/);
  assert.match(glass, /data-install="android"/);
  assert.ok(!/aria-label/.test(glass), 'generic 카드에 aria-label(ledby) 없음');
  assert.match(glass, /\$\{CARD\}/, '기존 카드 클래스(glass-tint-soft)');
  for (const c of ['[html[data-android]_&]:-order-1', 'min-[768px]:col-span-2', 'min-[768px]:col-start-1', 'min-[768px]:row-start-3']) {
    assert.ok(glass.includes(c), `카드 클래스 ${c}`);
  }
  // 누를 것 0 · 한글 리터럴 0(글자는 ANDROID_COPY 에서만) · 제목 h3 + 한 줄 p 둘뿐
  assert.ok(!/<a\b|<button\b|<QrCode\b|<details\b|href=/.test(card), '링크 · 버튼 · QR · 접는 목록 0');
  assert.equal(/[가-힣]/.test(card), false, 'AndroidCard 에 한글 리터럴');
  assert.match(card, /<h3 className=\{CARD_H\}>\{A\.title\}<\/h3>/);
  assert.match(card, /<p data-android-line="" className="t-small [^"]*\btext-pretty\b[^"]*">\s*\{A\.line\}\s*<\/p>/);
  assert.equal(card.match(/<p\b/g)?.length, 1, '문단 하나');
  // 그리드 안에 카드가 있다(iPhone 카드 다음) · 절 루트는 그대로
  const grid = INSTALL.slice(INSTALL.indexOf('data-install="iphone"'));
  assert.ok(grid.indexOf('<AndroidCard />') > 0, 'iPhone 카드 다음에 AndroidCard');
  assert.match(INSTALL, /id="install"[\s\S]*?className="relative isolate overflow-clip /);
});

test('소스 계약 — 설치 절: 빛 — 안드로이드 카드 뒤 국소 빛은 아랫변을 넘지 않는다(중심 ≤ 100% − 반높이 − 12px) · 폰 안드로이드 전용 빛은 지웠다(카드가 짧다)', () => {
  const lights = [...INSTALL.matchAll(/<LocalLight\s[^>]*\/>/g)].map((m) => m[0]);
  assert.equal(lights.length, 4, `빛 ${lights.length}개`);
  for (const l of lights) {
    const m = /y="calc\(100% - min\((\d+)px, ([\d.]+)vw\) - 12px\)" size="min\((\d+)px, (\d+)vw\)" aspect=\{([\d.]+)\}/.exec(l);
    if (!m) continue;
    const [, halfPx, halfVw, sizePx, sizeVw, aspect] = m.map(Number);
    assert.ok(Math.abs(halfPx - (sizePx * aspect) / 2) < 1, `반높이 px ${l}`);
    assert.ok(Math.abs(halfVw - (sizeVw * aspect) / 2) < 0.5, `반높이 vw ${l}`);
  }
  assert.ok(!INSTALL.includes('data-android]_&]:block'), '폰 안드로이드 전용 빛 0');
});

// ─── 폰 첫 화면(히어로 · 아웃트로) ──────────────────────────────────────────────────────────────

test('소스 계약 — 히어로 폰 벌: 안드로이드 기기면 배지를 숨기고 Mac용 다운로드가 줄을 채운다 · 메타 교체 · 안드로이드 버튼 0(보이는 결과는 scripts/android-smoke.mjs)', () => {
  const narrow = HERO.slice(HERO.indexOf('<span className={NARROW}>'), HERO.indexOf('</span>', HERO.indexOf('<span className={NARROW}>')));
  assert.match(narrow, /<AppStoreBadge [^>]*className=\{`-m-3 \$\{NOT_ANDROID\}`\} \/>/, '배지 = 안드로이드면 숨김');
  assert.match(narrow, /data-cta="hero-install" className=\{glassButtonClass\('glass', 'l', `ml-3 \[--b-h:48px\] \[--b-px:22px\] \$\{ANDROID_GROW\}`\)\}/);
  assert.equal(narrow.match(/<a\b/g)?.length, 1, '폰 벌 링크는 Mac용 다운로드 하나');
  assert.match(HERO, /const NOT_ANDROID = '\[html\[data-android\]_&\]:hidden';/);
  assert.match(HERO, /const ANDROID_GROW = '\[html\[data-android\]_&\]:ml-0 \[html\[data-android\]_&\]:grow';/);
  assert.match(HERO, /<span className=\{`\$\{NARROW_INLINE\} \$\{NOT_ANDROID\}`\}>\s*<KeepDots text=\{HERO_COPY\.metaPhone\} items \/>/);
  assert.match(HERO, /<span className="hidden phone:\[html\[data-android\]_&\]:inline">\s*<KeepDots text=\{ANDROID_COPY\.phoneMeta\} items \/>/);
});

test('소스 계약 — 아웃트로 폰 벌: 히어로와 같은 규칙(배지 숨김 → Mac용 다운로드가 줄을 채운다) · 안드로이드 버튼 0', () => {
  const at = OUTRO.indexOf('placement="outro-phone"');
  const narrow = OUTRO.slice(OUTRO.lastIndexOf('<div', at), OUTRO.indexOf('</div>', at));
  assert.match(narrow, /<AppStoreBadge height=\{48\} placement="outro-phone" className="-m-3 \[html\[data-android\]_&\]:hidden" \/>/);
  assert.match(narrow, /data-cta="outro-install" className=\{glassButtonClass\("glass", "l", `ml-3 \[--b-h:48px\] \[--b-px:22px\] \$\{ANDROID_GROW\}`\)\}/);
  assert.equal(narrow.match(/<a\b/g)?.length, 1, '폰 벌 링크는 Mac용 다운로드 하나');
});

test('소스 계약 — 선택 창: 휴대폰 줄 = [아이폰] 칩(App Store 새 탭) + 링크 아닌 안드로이드 글자(.ic-soon — 칩 모양 아님 · Tab 고리 밖)', () => {
  const row = CHOOSER.slice(CHOOSER.indexOf('className="ic-phone"'), CHOOSER.indexOf('<a href={LINKS.install}'));
  assert.match(row, /<a\s+href=\{LINKS\.appStore\}[\s\S]*?data-cta="chooser-iphone"[\s\S]*?className="gbtn gbtn--chip ic-chip"/);
  assert.match(row, /<span data-chooser-android="" className="ic-soon">\s*\{CHOOSER_COPY\.phoneAndroid\}\s*<\/span>/);
  assert.equal(row.match(/<a\b/g)?.length, 1, '휴대폰 줄 링크는 [아이폰] 하나');
  const css = read('./install-chooser.css');
  assert.match(css, /\.ic-soon \{[^}]*white-space: nowrap;[^}]*\}/);
  assert.ok(!/\.ic-soon \{[^}]*(background|box-shadow|border)/.test(css), '칩 모양(판·테) 0');
});
