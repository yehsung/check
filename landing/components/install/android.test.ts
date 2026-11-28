// node --experimental-strip-types --test components/install/android.test.ts
// 안드로이드 — Play 스토어 정식 출시 계약(docs/v3/brief.md §12.8 — 대표 결재 #d_MpzLv9qhvDuP "판 8로 대한민국에 전체 출시", 11-20 공개).
// 10-30 베타 세 단계(구글 그룹 가입 → 웹에서 테스터 되기 → Play 스토어 설치)는 11-03 에 내렸고(§12.7 '출시 준비 중'), 이제 스토어 버튼으로 바꿨다.
// 값으로 확인: ANDROID_COPY 글자 · brief §12.8 에 같은 글자 · 내린 베타 안내(그룹·테스터 주소, 베타 글자)가 화면 소스 어디에도 없다 · 금지어 0 ·
//   선택 창 글자는 ANDROID_COPY 를 가리킨다 · 스토어 주소는 LINKS.androidStore 하나 · '출시 준비 중' 글자 0 · [ANDROID-LAUNCH] 표식 0.
// 기기마다 자기 스토어(대표 결재 #d_88MQEAwesX78): 안드로이드는 아이폰과 같은 자리·같은 모양 — App Store 배지 자리에 Google Play 배지, 메뉴바 'Play 스토어',
//   컴퓨터 아웃트로 줄은 두 배지 다.
// 소스 계약(이름이 '소스 계약 —' 로 시작 — 서버 컴포넌트는 렌더 없이 볼 길이 없다): 설치 절 카드(#android · 배지 하나) · 빛 · 폰 첫 화면 · 아웃트로 · 메뉴바 · 선택 창.
//   보이는 결과(배지 보임/숨김 · 카드 맨 앞 · 선택 창 한 줄)는 브라우저 스모크 scripts/android-smoke.mjs(npm run android:smoke)가 잰다.
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
const S128 = BRIEF.slice(BRIEF.indexOf('### 12.8 '));
const FIXTURES = read('../../data/fixtures.ts');
const INSTALL = code('./Install.tsx');
const CHOOSER = code('./InstallChooser.tsx');
const HERO = code('../hero/Hero.tsx');
const OUTRO = code('../outro/Outro.tsx');
const CTA = code('../ui/DownloadCTA.tsx');
const BADGE = code('../ui/PlayStoreBadge.tsx');

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
  'data-cta="android-',
];
/** '출시 준비 중' 시절(§12.7)의 글자 — 출시 뒤 화면 소스에 없어야 한다 */
const SOON = ['출시 준비 중', '출시를 준비하고', 'ic-soon', 'data-chooser-android', '[ANDROID-LAUNCH]'];
const STORE = 'https://play.google.com/store/apps/details?id=com.yehsung.aingcheck';

const allText = () => Object.values(ANDROID_COPY) as string[];

// ─── 문구 ───────────────────────────────────────────────────────────────────────────────────────

test('ANDROID_COPY = §12.8 글자 그대로(정식 출시 — 스토어 버튼 · 칩)', () => {
  assert.deepEqual(ANDROID_COPY, {
    title: '안드로이드',
    line: '안드로이드 앱은 Play 스토어에서 받을 수 있어요.',
    badgeAlt: 'Google Play에서 다운로드',
    nav: 'Play 스토어',
    chooserRow: '휴대폰 앱',
    chooserIphone: '아이폰',
    chooserAndroid: '안드로이드',
    phoneMeta: '무료 · 안드로이드 · macOS 14 이상',
  });
});

test('§12.8 에 문구가 글자 그대로 있다 · 대표 결재 원문 · 스토어 주소', () => {
  assert.ok(S128.length > 0, 'brief §12.8');
  assert.ok(S128.includes('"판 8로 대한민국에 전체 출시"'), '대표 결재 원문');
  for (const s of allText()) assert.ok(S128.includes(`\`${s}\``), `§12.8 에 없음: ${s}`);
  assert.ok(S128.includes(STORE), '스토어 주소');
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
  // '출시 준비 중' 시절 글자 · 표식도 남지 않는다(주석 포함 — 표식은 주석에 있었다)
  for (const dir of ['app', 'components', 'data', 'lib']) {
    const base = new URL(`../../${dir}/`, import.meta.url);
    for (const rel of readdirSync(base, { recursive: true }) as string[]) {
      if (!/\.(tsx?|css|json)$/.test(rel) || /\.test\.ts$/.test(rel)) continue;
      const raw = readFileSync(new URL(rel, base), 'utf8');
      for (const gone of SOON) assert.ok(!raw.includes(gone), `${dir}/${rel} 에 '${gone}'`);
    }
  }
  // 세 단계 섬 파일은 지웠다
  for (const f of ['./AndroidSteps.tsx', './android-steps-logic.ts', './android-parts.tsx']) assert.ok(!existsSync(new URL(f, import.meta.url)), f);
});

test('LINKS: 그룹·테스터 주소 0 · 스토어 주소(지역 코드 없음)는 LINKS.androidStore 하나 · /#android 그대로', () => {
  assert.ok(!/androidGroup|androidTesting/.test(FIXTURES));
  assert.ok(FIXTURES.includes(`androidStore: '${STORE}',`), 'LINKS.androidStore');
  assert.match(FIXTURES, /\bandroid: '\/#android',/);
  // 주소 글자는 fixtures 에만 — 화면은 LINKS.androidStore 로 가리킨다(정본 하나)
  const users: string[] = [];
  for (const { path, src } of screenSources()) {
    if (path === 'data/fixtures.ts') continue;
    assert.ok(!src.includes('play.google.com'), `${path} 가 스토어 주소 글자를 쓴다`);
    if (src.includes('LINKS.androidStore')) users.push(path);
  }
  assert.deepEqual(users.sort(), ['app/g/[code]/InviteActions.tsx', 'components/install/InstallChooser.tsx', 'components/ui/DownloadCTA.tsx', 'components/ui/PlayStoreBadge.tsx']);
});

test('선택 창 휴대폰 줄 글자 = ANDROID_COPY 를 가리킨다(정본 하나)', () => {
  assert.equal(CHOOSER_COPY.phoneTitle, '휴대폰 앱');
  assert.equal(CHOOSER_COPY.phoneIphone, '아이폰');
  assert.equal(CHOOSER_COPY.phoneAndroid, '안드로이드');
  const src = read('../../data/install-copy.ts');
  assert.match(src, /phoneTitle:\s*ANDROID_COPY\.chooserRow/);
  assert.match(src, /phoneIphone:\s*ANDROID_COPY\.chooserIphone/);
  assert.match(src, /phoneAndroid:\s*ANDROID_COPY\.chooserAndroid/);
});

test('QR 자산 brand/qr-android-beta(/#android)는 파이프라인에 남는다(화면에서 안 쓴다) · assets.json 해시가 파일과 맞다 · App Store QR 그대로', () => {
  const py = read('../../scripts/make-qr.py');
  assert.match(py, /\("https:\/\/aing-check\.vercel\.app\/#android", "qr-android-beta\.svg"\)/, 'make-qr TARGETS');
  assert.match(py, /\("https:\/\/apps\.apple\.com\/app\/id6812768622", "qr-appstore\.svg"\)/, 'App Store 대상 그대로');
  const assets = JSON.parse(read('../../data/generated/assets.json')) as Record<string, { src: string; w: number; h: number; bytes: number }>;
  for (const key of ['brand/qr-android-beta', 'brand/qr-appstore', 'brand/googleplay-badge-ko']) {
    const meta = assets[key];
    assert.ok(meta, `assets.json ${key}`);
    const ext = key === 'brand/googleplay-badge-ko' ? 'png' : 'svg';
    const file = new URL(`../../public/assets/${key}.${ext}`, import.meta.url);
    assert.ok(existsSync(file), `${key}.${ext}`);
    const buf = readFileSync(file);
    assert.equal(meta.src, `/assets/${key}.${ext}?v=${createHash('sha1').update(buf).digest('hex').slice(0, 8)}`, `${key} ?v= 해시`);
    assert.equal(meta.bytes, buf.length);
  }
  assert.ok(!INSTALL.includes('qr-android-beta'), '설치 절은 안드로이드 QR 을 쓰지 않는다');
  // Google Play 배지 = 646×192(공식 PNG 의 위아래 투명 여백만 잘라 낸 것) · 컴포넌트 비율과 같다
  assert.equal(assets['brand/googleplay-badge-ko'].w, 646);
  assert.equal(assets['brand/googleplay-badge-ko'].h, 192);
  assert.match(BADGE, /const RATIO = 646 \/ 192;/);
});

test('소스 계약 — PlayStoreBadge: AppStoreBadge 와 같은 꼴(LINKS.androidStore 새 탭 · 사방 여백 = 높이/4 · alt = 배지 글자 · lazy)', () => {
  assert.match(BADGE, /href=\{LINKS\.androidStore\}\s+target="_blank"\s+rel="noopener noreferrer"\s+data-placement=\{placement\}/);
  assert.match(BADGE, /style=\{\{ padding: height \/ 4 \}\}/);
  assert.match(BADGE, /alt=\{ANDROID_COPY\.badgeAlt\}/);
  assert.match(BADGE, /loading="lazy"/);
  assert.match(BADGE, /const KEY = "brand\/googleplay-badge-ko" as const;/);
  assert.equal(/[가-힣]/.test(BADGE.replace(/\/\/.*$/gm, '')), false, 'PlayStoreBadge 에 한글 리터럴');
});

// ─── 설치 절 카드(소스 계약) ────────────────────────────────────────────────────────────────────

test('소스 계약 — 설치 절: 안드로이드 카드 = <Glass regular id="android" data-install="android"> · CARD · 칸 자리(≥768 3번째 줄 두 칸) · 안드로이드 기기면 맨 앞 · 제목·한 줄·Google Play 배지 하나', () => {
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
  // Google Play 배지 하나(아이폰 카드의 App Store 배지와 같은 높이 · 같은 음수 여백) · 링크·버튼·QR·접는 목록 0 · 한글 리터럴 0
  assert.equal(card.match(/<PlayStoreBadge\b/g)?.length, 1, '배지 하나');
  assert.match(card, /<PlayStoreBadge height=\{48\} placement="install-play" className="-m-3" \/>/);
  assert.ok(!/<a\b|<button\b|<QrCode\b|<details\b/.test(card), '링크 · 버튼 · QR · 접는 목록 0');
  assert.match(card, /<div className="mt-5 flex min-\[768px\]:my-0 min-\[768px\]:ml-auto">/, '≥768 은 오른쪽 끝');
  assert.match(INSTALL, /<AppStoreBadge height=\{48\} placement="install" className="-m-3" \/>/, '아이폰 카드 배지와 같은 꼴');
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

test('소스 계약 — 히어로 폰 벌: 기기마다 자기 스토어 — App Store 배지(안드로이드면 숨김) · Google Play 배지(안드로이드만) · Mac용 다운로드 · 메타 교체 · 안드로이드 태블릿도 폰 벌', () => {
  const narrow = HERO.slice(HERO.indexOf('<span className={NARROW}>'), HERO.indexOf('<a href={LINKS.install}', HERO.indexOf('<span className={NARROW}>')) + 200);
  assert.match(narrow, /<AppStoreBadge height=\{48\} placement="hero-phone" className=\{`-m-3 \$\{NOT_ANDROID\}`\} \/>/, 'App Store 배지 = 안드로이드면 숨김');
  assert.match(narrow, /<span className=\{ANDROID_ONLY\}>\s*<PlayStoreBadge height=\{48\} placement="hero-phone-play" className="-m-3" \/>\s*<\/span>/, 'Google Play 배지 = 안드로이드만, 같은 높이·여백');
  assert.match(narrow, /data-cta="hero-install" className=\{glassButtonClass\('glass', 'l', 'ml-3 \[--b-h:48px\] \[--b-px:22px\]'\)\}/, 'Mac용 다운로드 = 아이폰과 같은 꼴');
  assert.ok(narrow.indexOf('hero-phone-play') < narrow.indexOf('hero-install'), '배지가 먼저');
  assert.ok(!HERO.includes('ANDROID_GROW') && !HERO.includes("'primary'"), '보라 주 버튼 · 늘이기 0(첫 안)');
  assert.match(HERO, /const NOT_ANDROID = '\[html\[data-android\]_&\]:hidden';/);
  assert.match(HERO, /const ANDROID_ONLY = 'hidden \[html\[data-android\]_&\]:contents';/);
  // 안드로이드 기기는 폭과 무관하게 폰 벌(아이패드와 같은 규칙)
  assert.match(HERO, /const WIDE = 'contents phone:hidden \[html\[data-platform=ios\]_&\]:hidden \[html\[data-android\]_&\]:hidden';/);
  assert.match(HERO, /const NARROW = 'hidden phone:contents \[html\[data-platform=ios\]_&\]:contents \[html\[data-android\]_&\]:contents';/);
  assert.match(HERO, /<span className=\{`\$\{NARROW_INLINE\} \$\{NOT_ANDROID\}`\}>\s*<KeepDots text=\{HERO_COPY\.metaPhone\} items \/>/);
  assert.match(HERO, /<span className="hidden \[html\[data-android\]_&\]:inline">\s*<KeepDots text=\{ANDROID_COPY\.phoneMeta\} items \/>/);
});

test('소스 계약 — 아웃트로: 컴퓨터 줄 = Mac · brew · App Store + Google Play 배지(한 묶음) · 폰 줄 = 히어로와 같은 규칙(기기마다 자기 스토어)', () => {
  const wideAt = OUTRO.indexOf('data-chooser-row=""');
  const wide = OUTRO.slice(OUTRO.lastIndexOf('<div', wideAt), OUTRO.indexOf('</div>', wideAt));
  assert.ok(wide.includes('[html[data-platform=ios]_&]:hidden [html[data-android]_&]:hidden'), '컴퓨터 줄은 iOS · 안드로이드 기기에서 숨김');
  assert.match(wide, /<span data-store-badges="" className="inline-flex shrink-0 items-center self-center -my-3">\s*<AppStoreBadge height=\{48\} placement="outro" \/>\s*<PlayStoreBadge height=\{48\} placement="outro-play" className="-ml-3" \/>\s*<\/span>/, '두 배지 한 묶음(App Store 먼저)');
  const at = OUTRO.indexOf('placement="outro-phone"');
  const narrow = OUTRO.slice(OUTRO.lastIndexOf('<div', at), OUTRO.indexOf('</div>', at));
  assert.ok(narrow.includes('[html[data-platform=ios]_&]:flex [html[data-android]_&]:flex'), '폰 줄은 iOS · 안드로이드 기기면 폭과 무관하게');
  assert.match(narrow, /<AppStoreBadge height=\{48\} placement="outro-phone" className="-m-3 \[html\[data-android\]_&\]:hidden" \/>/);
  assert.match(narrow, /<span className="hidden \[html\[data-android\]_&\]:contents">\s*<PlayStoreBadge height=\{48\} placement="outro-phone-play" className="-m-3" \/>\s*<\/span>/);
  assert.match(narrow, /data-cta="outro-install" className=\{glassButtonClass\("glass", "l", "ml-3 \[--b-h:48px\] \[--b-px:22px\]"\)\}/);
  assert.equal(narrow.match(/<a\b/g)?.length, 1, '폰 줄 링크(배지 밖) = Mac용 다운로드 하나');
});

test('소스 계약 — 메뉴바: 아이폰 App Store · 안드로이드 Play 스토어(새 탭) · 그 밖은 다운로드 그대로', () => {
  assert.match(CTA, /<a href=\{LINKS\.appStore\} target="_blank" rel="noopener noreferrer" data-cta=\{placement\}/);
  assert.match(CTA, /<span className="contents \[html\[data-android\]_&\]:hidden">\{main\}<\/span>/);
  assert.match(CTA, /<span className="hidden \[html\[data-android\]_&\]:contents">\s*<a href=\{LINKS\.androidStore\} target="_blank" rel="noopener noreferrer" data-cta="nav-android" className=\{cx\(btn\)\}>\s*\{ANDROID_COPY\.nav\}/);
  assert.ok(CTA.indexOf('nav-android') > CTA.indexOf('VIS.other'), '안드로이드 갈래는 other 안(data-android 는 other 의 한 갈래)');
});

test('소스 계약 — 선택 창: 휴대폰 줄 = [아이폰] 칩(App Store 새 탭) + [안드로이드] 칩(Play 스토어 새 탭) — 둘 다 같은 칩 · 누르면 닫고 방아쇠로', () => {
  const row = CHOOSER.slice(CHOOSER.indexOf('className="ic-phone"'), CHOOSER.indexOf('<a href={LINKS.install}'));
  assert.match(row, /<a\s+href=\{LINKS\.appStore\}[\s\S]*?data-cta="chooser-iphone"[\s\S]*?className="gbtn gbtn--chip ic-chip"/);
  assert.match(
    row,
    /<a\s+href=\{LINKS\.androidStore\}\s+target="_blank"\s+rel="noopener noreferrer"\s+tabIndex=\{0\}\s+data-cta="chooser-android"\s+className="gbtn gbtn--chip ic-chip"\s+onClick=\{\(\) => close\(true\)\}\s*>\s*\{CHOOSER_COPY\.phoneAndroid\}\s*<\/a>/,
  );
  assert.equal(row.match(/<a\b/g)?.length, 2, '휴대폰 줄 링크 = [아이폰] · [안드로이드]');
  assert.ok(row.indexOf('chooser-iphone') < row.indexOf('chooser-android'), '아이폰 먼저');
  assert.ok(!read('./install-chooser.css').includes('.ic-soon'), '.ic-soon 0');
});
