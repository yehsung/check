// node --experimental-strip-types --test components/install/android.test.ts
// 안드로이드 베타 받는 길 계약(docs/v3/brief.md §12 — 2026-10-30 "베타로 사용할 수 있는 경로를 랜딩페이지에 추가하자. 간편하게 접근할 수 있게끔."):
// 값으로 확인: ANDROID_COPY = §12 글자 그대로 · 단계 순서(그룹 → 테스터 → 스토어) · LINKS 세 주소 글자 그대로 · 금지어 0 · 넣지 말 것 0 ·
//   QR(/#android) 파일·해시 · 선택 창 휴대폰 줄 글자는 ANDROID_COPY 를 가리킨다.
// 소스 계약(이름이 '소스 계약 —' 로 시작 — 서버 컴포넌트는 렌더 없이 볼 길이 없다, 꼭 필요한 것만): 설치 절 카드(#android · 칸 자리 · 안드로이드 기기 맨 앞) ·
//   단계 버튼(새 탭 · data-cta · 접근 이름 — AndroidSteps.tsx) · 접는 문제 해결(<details> §12.6) · QR 넘김 · 빛 · 폰 첫 화면(히어로·아웃트로) 안드로이드 벌.
//   다음 단계 안내(클릭 → 주 버튼)의 계산은 android-steps.test.ts 가 값으로 본다.
//   글자 꼴만 보므로 CSS 우선순위로 hidden 이 지는 일 같은 '보이는 결과'는 못 잡는다 → 브라우저 스모크 scripts/android-smoke.mjs(npm run android:smoke)가 잰다.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { ANDROID_COPY, CHOOSER_COPY } from '../../data/install-copy.ts';
import { HERO_COPY } from '../hero/copy.ts';

const read = (p: string) => readFileSync(new URL(p, import.meta.url), 'utf8');
/** 주석(블록·줄·JSX)을 걷어 낸 소스 */
const code = (p: string) =>
  read(p)
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:'"`])\/\/.*$/gm, '$1');

const BRIEF = read('../../docs/v3/brief.md');
const S12 = BRIEF.slice(BRIEF.indexOf('## 12. 안드로이드 베타 받는 길'));
const FIXTURES = read('../../data/fixtures.ts');
const INSTALL = code('./Install.tsx');
const STEPS = code('./AndroidSteps.tsx');
const PARTS = code('./android-parts.tsx');
const GLOBALS = read('../../app/globals.css');
const HERO = code('../hero/Hero.tsx');
const OUTRO = code('../outro/Outro.tsx');

/** fixtures.ts LINKS 값(JSON import 가 있어 node 로 못 불러와 소스에서 읽는다 — seo.test 와 같은 방식) */
function fixtureLink(key: string): string {
  const m = new RegExp(`\\b${key}: '([^']+)'`).exec(FIXTURES);
  assert.ok(m, `fixtures.ts LINKS.${key} 없음`);
  return m[1];
}

const URLS = {
  group: 'https://groups.google.com/g/aingcheck-android-beta',
  testing: 'https://play.google.com/apps/testing/com.yehsung.aingcheck',
  store: 'https://play.google.com/store/apps/details?id=com.yehsung.aingcheck',
};

const FORBIDDEN = ['격자', '작은 팀', '작은 Mac', '눌러', '누르', '누른', 'AI 토큰 리밋', '판돈', '베팅', '내기', '체험', 'Learn more', '더보기'];

const allText = () => {
  const out: string[] = [];
  const walk = (v: unknown) => {
    if (typeof v === 'string') out.push(v);
    else if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === 'object') Object.values(v).forEach(walk);
  };
  walk(ANDROID_COPY);
  return out;
};

// ─── 문구 ───────────────────────────────────────────────────────────────────────────────────────

test('ANDROID_COPY = §12 글자 그대로(Gemini 정본 · 문제 해결 §12.6)', () => {
  assert.deepEqual(ANDROID_COPY, {
    title: '안드로이드는 베타로',
    line: '구글 계정만 있으면 세 단계로 설치까지 끝나요.',
    warn: "폰의 Play 스토어와 같은 구글 계정으로 가입해요. 다르면 3단계에서 '찾을 수 없음'이 떠요.",
    steps: [
      { name: '구글 그룹 가입', cta: '가입하기', note: '누구나 가입할 수 있고 목록·이메일은 관리자만 봐요.', link: 'androidGroup', dataCta: 'android-group' },
      { name: '웹에서 테스터 되기', cta: '등록하기', note: "열린 페이지에서 '테스터 되기'를 클릭해요.", link: 'androidTesting', dataCta: 'android-testing' },
      { name: 'Play 스토어에서 설치', cta: '설치하기', note: '설치 뒤 업데이트는 Play 스토어가 자동으로 해요.', link: 'androidStore', dataCta: 'android-store' },
    ],
    helpTitle: '3단계에서 앱이 안 보이나요?',
    helpItems: [
      'Play 스토어 앱 오른쪽 위 프로필 사진에서 그룹에 가입한 계정으로 바꿔요.',
      "2단계에서 '테스터 되기'까지 클릭했는지 확인해요.",
      '등록 반영까지 몇 분 걸릴 수 있어요. 잠시 뒤 다시 열어요.',
    ],
    betaNote: '베타라 길건너 아잉이·아잉 큐브 게임은 아직 없어요.',
    qrCaption: '카메라로 찍으면 이 안내가 폰에서 열려요.',
    qrAlt: '이 안내를 폰에서 여는 QR 코드',
    chooserRow: '휴대폰 앱',
    chooserIphone: '아이폰',
    chooserAndroid: '안드로이드 베타',
    phoneCta: '안드로이드 베타 받기',
    phoneMeta: '무료 · 안드로이드 베타 · macOS 14 이상',
    faqTail: '안드로이드에서도 베타로 쓸 수 있어요.',
  });
});

test('단계 순서 = 실제 순서(그룹 가입 → 웹에서 테스터 되기 → Play 스토어) · 주소 셋 = LINKS 글자 그대로', () => {
  assert.deepEqual(
    ANDROID_COPY.steps.map((s) => s.link),
    ['androidGroup', 'androidTesting', 'androidStore'],
  );
  assert.deepEqual(
    ANDROID_COPY.steps.map((s) => fixtureLink(s.link)),
    [URLS.group, URLS.testing, URLS.store],
  );
  // 패키지 이름이 테스트·스토어 두 주소에서 같다
  for (const u of [URLS.testing, URLS.store]) assert.ok(u.includes('com.yehsung.aingcheck'), u);
  assert.equal(fixtureLink('android'), '/#android', 'LINKS.android = 설치 절 카드');
  // 경고는 3단계를 말한다 — 단계가 정말 셋이다
  assert.equal(ANDROID_COPY.steps.length, 3);
  assert.ok(ANDROID_COPY.warn.includes('3단계'));
  assert.ok(ANDROID_COPY.line.includes('세 단계'));
});

test('§12 에 문구가 글자 그대로 있다 · 사용자 원문 · 세 주소', () => {
  assert.ok(S12.length > 0, 'brief §12');
  assert.ok(S12.includes('저거 베타로 사용할 수 있는 경로를 랜딩페이지에 추가하자. 간편하게 접근할 수 있게끔.'), '§12 사용자 원문');
  for (const s of allText().filter((x) => /[가-힣]/.test(x))) assert.ok(S12.includes(`\`${s}\``), `§12 에 없음: ${s}`);
  for (const u of Object.values(URLS)) assert.ok(S12.includes(u), `§12 주소 ${u}`);
});

test('금지어 0 · 넣지 말 것 0(이메일 주소 · APK · 안드로이드 최소 OS 버전 · 지원 이메일)', () => {
  const text = allText().join('\n');
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
  assert.ok(!/@[\w.-]+\.\w+/.test(text), '이메일 주소');
  assert.ok(!/apk/i.test(text), 'APK');
  for (const s of allText()) assert.ok(!/안드로이드 \d+|Android \d+/.test(s), `안드로이드 버전 숫자: ${s}`);
  // 메타의 'macOS 14 이상' 은 맥 앱 이야기(히어로 폰 메타와 같은 끝)
  assert.ok(ANDROID_COPY.phoneMeta.endsWith(HERO_COPY.metaPhone.split(' · ').at(-1) ?? ''));
  // 화면 소스에 APK·이메일 링크 0
  for (const src of [INSTALL, HERO, OUTRO]) {
    assert.ok(!/\.apk|mailto:/i.test(src), 'APK · mailto');
  }
});

test('선택 창 휴대폰 줄 글자 = ANDROID_COPY 를 가리킨다(정본 하나)', () => {
  assert.equal(CHOOSER_COPY.phoneTitle, '휴대폰 앱');
  assert.equal(CHOOSER_COPY.phoneIphone, '아이폰');
  assert.equal(CHOOSER_COPY.phoneAndroid, '안드로이드 베타');
  const src = read('../../data/install-copy.ts');
  assert.match(src, /phoneTitle:\s*ANDROID_COPY\.chooserRow/);
  assert.match(src, /phoneIphone:\s*ANDROID_COPY\.chooserIphone/);
  assert.match(src, /phoneAndroid:\s*ANDROID_COPY\.chooserAndroid/);
});

// ─── QR ─────────────────────────────────────────────────────────────────────────────────────────

test('QR: public/assets/brand/qr-android-beta.svg = make-qr.py 의 /#android 대상 · assets.json 해시가 파일과 맞다 · App Store QR 그대로', () => {
  const py = read('../../scripts/make-qr.py');
  assert.match(py, /\("https:\/\/aing-check\.vercel\.app\/#android", "qr-android-beta\.svg"\)/, 'make-qr TARGETS');
  assert.match(py, /\("https:\/\/apps\.apple\.com\/app\/id6812768622", "qr-appstore\.svg"\)/, 'App Store 대상 그대로');
  assert.ok(BRIEF.includes('운영 주소는 그대로 https://aing-check.vercel.app'), 'QR 주소 = 운영 주소(brief §10)');
  const assets = JSON.parse(read('../../data/generated/assets.json')) as Record<string, { src: string; w: number; h: number; bytes: number }>;
  for (const key of ['brand/qr-android-beta', 'brand/qr-appstore']) {
    const meta = assets[key];
    assert.ok(meta, `assets.json ${key}`);
    const file = new URL(`../../public/assets/${key}.svg`, import.meta.url);
    assert.ok(existsSync(file), `${key}.svg`);
    const buf = readFileSync(file);
    assert.equal(meta.src, `/assets/${key}.svg?v=${createHash('sha1').update(buf).digest('hex').slice(0, 8)}`, `${key} ?v= 해시`);
    assert.equal(meta.bytes, buf.length);
    assert.deepEqual([meta.w, meta.h], [148, 148]);
    const svg = buf.toString('utf8');
    assert.match(svg, /viewBox="0 0 37 37"/);
    assert.ok(svg.includes('#12131C') && svg.includes('#F2F3F7'), '같은 색(모듈 · 타일)');
  }
  assert.match(read('../../scripts/build-assets.mjs'), /"brand\/qr-android-beta\.svg"/, 'build-assets 검증 목록');
});

// ─── 설치 절 카드(소스 계약) ────────────────────────────────────────────────────────────────────

test('소스 계약 — 설치 절: 안드로이드 카드 = <Glass regular id="android" data-install="android"> · CARD · 칸 자리(≥768 3번째 줄 두 칸) · 안드로이드 기기면 맨 앞 · 문단은 text-pretty', () => {
  const at = INSTALL.indexOf('function AndroidCard()');
  assert.ok(at > 0, 'AndroidCard');
  const card = INSTALL.slice(at, INSTALL.indexOf('export function Install'));
  const glass = /<Glass[\s\S]*?>/.exec(card)?.[0] ?? '';
  assert.match(glass, /level="regular"/);
  assert.match(glass, /id="android"/);
  assert.match(glass, /data-install="android"/);
  // 역할 없는 div(generic)에는 이름을 붙일 수 없다(ARIA — 스크린 리더가 무시 · axe aria-prohibited-attr) → 이름 없이 h3 이 제목 구조를 준다
  assert.ok(!/aria-label/.test(glass), 'generic 카드에 aria-label(ledby) 없음');
  assert.match(glass, /\$\{CARD\}/, '기존 카드 클래스(glass-tint-soft)');
  for (const c of ['[html[data-android]_&]:-order-1', 'min-[768px]:col-span-2', 'min-[768px]:col-start-1', 'min-[768px]:row-start-3', 'desk:grid', 'desk:grid-cols-[clamp(264px,25vw,320px)_minmax(0,1fr)]']) {
    assert.ok(glass.includes(c), `카드 클래스 ${c}`);
  }
  assert.match(INSTALL, /const CARD = 'glass-tint-soft /);
  // 그리드 안에 카드가 있다(iPhone 카드 다음)
  const grid = INSTALL.slice(INSTALL.indexOf('data-install="iphone"'));
  assert.ok(grid.indexOf('<AndroidCard />') > 0, 'iPhone 카드 다음에 AndroidCard');
  // 절 루트는 그대로
  assert.match(INSTALL, /id="install"[\s\S]*?className="relative isolate overflow-clip /);
  // 한글 리터럴 0 — 글자는 ANDROID_COPY 에서만(카드 · 단계 목록 둘 다)
  assert.equal(/[가-힣]/.test(card), false, 'AndroidCard 에 한글 리터럴');
  assert.equal(/[가-힣]/.test(STEPS), false, 'AndroidSteps 에 한글 리터럴');
  for (const k of ['A.title', 'A.line', 'A.warn', 'A.betaNote', 'A.qrCaption', 'A.qrAlt', 'A.helpTitle', 'A.helpItems']) assert.ok(card.includes(k), k);
  for (const k of ['step.name', 'step.cta', 'step.note']) assert.ok(STEPS.includes(k), k);
  // 문단(+ 문제 해결 항목)은 전부 text-pretty — t-small·t-micro 에는 text-wrap 지정이 없어 390·412 에서 끝줄이 '떠요.'·'봐요.' 두 글자로 남았다(검증 실측)
  const paras = [...(card.match(/<p\b[\s\S]*?>/g) ?? []), ...(STEPS.match(/<p\b[\s\S]*?>/g) ?? [])];
  assert.ok(paras.length >= 5, `문단 ${paras.length}`);
  for (const para of paras) assert.match(para, /\btext-pretty\b/, `text-pretty 없음: ${para.slice(0, 60)}`);
  assert.match(INSTALL, /const HELP_ITEM =\s*'[^']*\btext-pretty\b/, '문제 해결 항목 text-pretty');
});

test('소스 계약 — 설치 절: 단계 = <ol> 셋(AndroidSteps — 번호 · h4 이름 · 새 탭 버튼 · 보조 줄) · 버튼 주소 LINKS[step.link] · data-cta · 접근 이름 = 보이는 글자 + 단계 이름 설명', () => {
  const card = INSTALL.slice(INSTALL.indexOf('function AndroidCard()'), INSTALL.indexOf('export function Install'));
  assert.match(INSTALL, /import \{ AndroidSteps \} from '\.\/AndroidSteps';/);
  assert.match(STEPS, /<ol data-android-steps="" className=\{cx\(OL, className\)\}>/);
  assert.match(STEPS, /ANDROID_COPY\.steps\.map\(\(step, i\)/);
  assert.match(STEPS, /\{v\.n\}/, '번호 원 1·2·3');
  assert.match(STEPS, /const v = views\[i\];/);
  assert.match(STEPS, /<h4 id=\{nameId\}/);
  const a = /<a\s+href=\{LINKS\[step\.link\]\}[\s\S]*?>\s*\{step\.cta\}/.exec(STEPS)?.[0] ?? '';
  assert.ok(a, '버튼 <a href={LINKS[step.link]}>');
  assert.match(a, /target="_blank"/);
  assert.match(a, /rel="noopener noreferrer"/);
  assert.match(a, /data-cta=\{step\.dataCta\}/);
  assert.match(a, /aria-describedby=\{nameId\}/, '설명 = 단계 이름');
  assert.ok(!/aria-label=/.test(a), '접근 이름은 보이는 글자 그대로');
  assert.match(a, /glassButtonClass\(v\.primary \? 'primary' : 'glass', 's'/, '유리 small — 다음 단계만 primary, 나머지 outline(§12.6)');
  assert.match(STEPS, /const nameId = `android-step-\$\{v\.n\}`/);
  // 경고는 ink-1(가장 중요) · 정보 아이콘 하나
  const warn = /<p\s+data-android-warn=""[\s\S]*?<\/p>/.exec(card)?.[0] ?? '';
  assert.match(warn, /text-ink-1/);
  assert.equal((warn.match(/<InfoGlyph \/>/g) ?? []).length, 1);
  // 보조 줄 t-small ink-2
  assert.match(STEPS, /<p className="t-small mt-2\.5 text-pretty text-ink-2[^"]*">\s*<KeepQuotes text=\{step\.note\} \/>/);
  // 읽는 순서(소스 순서) = 제목 → 경고 → 단계 → 문제 해결 → 베타 안내 → QR(desk 는 격자 자리만 옮긴다)
  const seq = ['A.title', 'data-android-warn', '<AndroidSteps', 'data-android-help', 'A.betaNote', '<QrCode'];
  let at = -1;
  for (const k of seq) {
    const i = card.indexOf(k, at + 1);
    assert.ok(i > at, `순서: ${k}`);
    at = i;
  }
  // desk 자리: 경고 = 오른쪽 맨 위 · 단계 = 오른쪽 둘째·셋째 줄 · 문제 해결 = 오른쪽 넷째 줄 · 베타 안내 = 왼쪽 둘째 줄 · QR = 왼쪽 셋째 줄 아래 끝
  assert.match(warn, /desk:col-start-2 desk:row-start-1/);
  assert.match(card, /<AndroidSteps className="[^"]*desk:col-start-2 desk:row-span-2 desk:row-start-2/);
  assert.match(card, /desk:grid-rows-\[auto_auto_1fr_auto\]/);
  assert.match(INSTALL, /const HELP =\s*'[^']*desk:col-start-2 desk:row-start-4/);
  assert.match(card, /desk:col-start-1 desk:row-start-3 desk:flex desk:self-end/);
});

test('KeepQuotes: 작은따옴표 묶음(+ 붙은 조사)만 통째 — 이으면 원문', () => {
  const src = PARTS.slice(PARTS.indexOf('function KeepQuotes'));
  const re = new RegExp(/text\.split\((\/.*\/)\)/.exec(src)?.[1].slice(1, -1) ?? '^$');
  const parts = (s: string) => s.split(re);
  for (const s of [ANDROID_COPY.warn, ...ANDROID_COPY.steps.map((x) => x.note), ...ANDROID_COPY.helpItems]) assert.equal(parts(s).join(''), s);
  assert.deepEqual(parts(ANDROID_COPY.helpItems[1]).filter((_, i) => i % 2 === 1), ["'테스터 되기'까지"]);
  assert.deepEqual(parts(ANDROID_COPY.steps[1].note).filter((_, i) => i % 2 === 1), ["'테스터 되기'를"]);
  assert.deepEqual(parts(ANDROID_COPY.warn).filter((_, i) => i % 2 === 1), ["'찾을 수 없음'이"]);
  assert.deepEqual(parts(ANDROID_COPY.steps[0].note).filter((_, i) => i % 2 === 1), []);
});

test('소스 계약 — 설치 절: 접는 문제 해결 = 단계 목록 아래 <details>(기본 닫힘 · FAQ 와 같은 모양) · 요약 줄 ≥ 44(min-h-12) · <ul> 항목 셋 = ANDROID_COPY · 높이 전이는 FAQ 와 같은 규칙', () => {
  const card = INSTALL.slice(INSTALL.indexOf('function AndroidCard()'), INSTALL.indexOf('export function Install'));
  const det = /<details data-android-help="" className=\{HELP\}>[\s\S]*?<\/details>/.exec(card)?.[0] ?? '';
  assert.ok(det, '<details data-android-help>');
  assert.ok(!/\bopen\b/.test(det.slice(0, det.indexOf('>'))), '기본 닫힘');
  assert.match(det, /<summary className=\{HELP_SUMMARY\}>\s*<span className="min-w-0">\{A\.helpTitle\}<\/span>/);
  assert.match(det, /<span aria-hidden="true" className=\{HELP_ICON\}>/, '꺾쇠 칩 = 장식');
  assert.match(det, /<ul [^>]*>\s*\{A\.helpItems\.map\(\(item\) => \(\s*<li key=\{item\} className=\{HELP_ITEM\}>\s*<KeepQuotes text=\{item\} \/>/);
  const summary = /const HELP_SUMMARY =\s*('[^']*'(?:\s*\+\s*'[^']*')*)/.exec(INSTALL)?.[1] ?? '';
  for (const c of ['min-h-12', 'list-none', '[&::-webkit-details-marker]:hidden', 'cursor-pointer']) assert.ok(summary.includes(c), `요약 줄 ${c}`);
  const icon = /const HELP_ICON =\s*('[^']*'(?:\s*\+\s*'[^']*')*)/.exec(INSTALL)?.[1] ?? '';
  for (const c of ['group-open/help:rotate-180', 'motion-reduce:transition-none']) assert.ok(icon.includes(c), `칩 ${c}`);
  // 높이 전이(globals — FAQ 와 같은 블록, 감속 아님 · interpolate-size 지원일 때만)
  assert.match(GLOBALS, /details\[name="faq"\]::details-content, details\[data-android-help\]::details-content \{ height:0;/);
  assert.match(GLOBALS, /details\[name="faq"\]\[open\]::details-content, details\[data-android-help\]\[open\]::details-content \{ height:auto; \}/);
});

test('소스 계약 — 설치 절: QR 은 데스크톱 전용 · /#android(같은 탭) · qr-android-beta 그림 · alt = ANDROID_COPY.qrAlt · QrCode 기본값은 App Store 그대로', () => {
  const card = INSTALL.slice(INSTALL.indexOf('function AndroidCard()'), INSTALL.indexOf('export function Install'));
  assert.match(card, /<QrCode size=\{\d+\} href=\{LINKS\.android\} src=\{ANDROID_QR_SRC\} alt=\{A\.qrAlt\} \/>/);
  assert.match(INSTALL, /const ANDROID_QR_SRC = asset\('brand\/qr-android-beta'\)\?\.src \?\? '\/assets\/brand\/qr-android-beta\.svg';/);
  const qrRow = card.slice(card.lastIndexOf('<div', card.indexOf('<QrCode')), card.indexOf('<QrCode'));
  assert.match(qrRow, /hidden[^"]*desk:flex/, 'QR 줄은 desk 에서만');
  // iPhone 카드 QR 은 무변경(기본값)
  assert.match(INSTALL, /<QrCode size=\{96\} \/>/);
  const qr = code('../ui/QrCode.tsx');
  assert.match(qr, /href = LINKS\.appStore/, '기본 href = App Store');
  assert.match(qr, /const external = \/\^https\?:\/\.test\(href\)/, '바깥 주소만 새 탭');
  assert.match(qr, /target=\{external \? "_blank" : undefined\}/);
});

test('소스 계약 — 설치 절: 빛 — 안드로이드 카드 뒤에도 국소 빛(아랫변을 넘지 않게 중심 ≤ 100% − 반높이 − 12px) · 폰 안드로이드 기기 전용 빛(윗변을 넘지 않게 중심 ≥ 반높이 + 12px)', () => {
  const lights = [...INSTALL.matchAll(/<LocalLight\s[^>]*\/>/g)].map((m) => m[0]);
  assert.ok(lights.length >= 4, `빛 ${lights.length}개`);
  for (const l of lights) {
    const m = /y="calc\(100% - min\((\d+)px, ([\d.]+)vw\) - 12px\)" size="min\((\d+)px, (\d+)vw\)" aspect=\{([\d.]+)\}/.exec(l);
    if (!m) continue;
    const [, halfPx, halfVw, sizePx, sizeVw, aspect] = m.map(Number);
    // 반높이 = size × aspect / 2 — px·vw 두 갈래 모두
    assert.ok(Math.abs(halfPx - (sizePx * aspect) / 2) < 1, `반높이 px ${l}`);
    assert.ok(Math.abs(halfVw - (sizeVw * aspect) / 2) < 0.5, `반높이 vw ${l}`);
  }
  // 폰 · 안드로이드 기기: 카드가 맨 앞(절 위쪽)이라 위 넷이 닿지 않는다(검증 실측 — 빛을 다 꺼도 카드 뒤 휘도 그대로) → 그 기기에서만 보이는 빛 하나
  const phone = lights.filter((l) => l.includes('phone:[html[data-android]_&]:block'));
  assert.equal(phone.length, 1, '폰 안드로이드 전용 빛 하나');
  assert.match(phone[0], /className="hidden phone:\[html\[data-android\]_&\]:block"/, '다른 기기 · ≥768 은 display:none');
  const m = /y="calc\(min\((\d+)px, ([\d.]+)vw\) \+ (\d+)px\)"\s+size="min\((\d+)px, (\d+)vw\)"\s+aspect=\{([\d.]+)\}/.exec(phone[0].replace(/\s+/g, ' '));
  assert.ok(m, `중심 = 반높이 + Npx 꼴: ${phone[0]}`);
  const [, halfPx, halfVw, top, sizePx, sizeVw, aspect] = m.map(Number);
  assert.ok(Math.abs(halfPx - (sizePx * aspect) / 2) < 1 && Math.abs(halfVw - (sizeVw * aspect) / 2) < 0.5, '반높이 = size × aspect / 2');
  assert.ok(top >= 12, `윗변 위 여백 ${top}px ≥ 12`);
});

// ─── 폰 첫 화면(히어로 · 아웃트로) ──────────────────────────────────────────────────────────────

test('소스 계약 — 히어로 폰 벌: 안드로이드 기기면 배지를 숨기고 그 자리에 보라 주 버튼(48) → #android · Mac용 다운로드는 그대로 · 메타 교체 · 판별 전 = 배지(보이는 결과는 scripts/android-smoke.mjs)', () => {
  const narrow = HERO.slice(HERO.indexOf('<span className={NARROW}>'));
  const badge = narrow.indexOf('<AppStoreBadge');
  const android = narrow.indexOf('href={LINKS.android}');
  const install = narrow.indexOf('href={LINKS.install}');
  assert.ok(badge >= 0 && badge < android && android < install, '배지 → 안드로이드 버튼 → Mac용 다운로드');
  assert.match(narrow.slice(badge, android), /className=\{`-m-3 \$\{NOT_ANDROID\}`\}/, '배지는 안드로이드 기기에서 숨김');
  assert.match(HERO, /const NOT_ANDROID = '\[html\[data-android\]_&\]:hidden';/);
  assert.match(HERO, /const ANDROID_ONLY = 'hidden \[html\[data-android\]_&\]:inline-flex';/, '판별 전·JS 없음 = 숨김');
  const btn = /<a href=\{LINKS\.android\} data-cta="hero-android" className=\{glassButtonClass\('primary', 'l', `\$\{ANDROID_ONLY\}[^`]*\[--b-h:48px\][^`]*`\)\}>\s*\{ANDROID_COPY\.phoneCta\}/.exec(narrow);
  assert.ok(btn, "주 버튼: primary · 48 · '안드로이드 베타 받기'");
  assert.match(narrow, /href=\{LINKS\.install\} data-cta="hero-install"/, 'Mac용 다운로드 → 설치 절 그대로');
  // 메타: 안드로이드면 ANDROID_COPY.phoneMeta(KeepDots items) · 아니면 그대로
  assert.match(HERO, /<span className=\{`\$\{NARROW_INLINE\} \$\{NOT_ANDROID\}`\}>\s*<KeepDots text=\{HERO_COPY\.metaPhone\} items \/>/);
  assert.match(HERO, /<span className="hidden phone:\[html\[data-android\]_&\]:inline">\s*<KeepDots text=\{ANDROID_COPY\.phoneMeta\} items \/>/);
  // 넓은 벌은 무변경
  const wide = HERO.slice(HERO.indexOf('<span className={WIDE}>'), HERO.indexOf('<span className={NARROW}>'));
  assert.ok(!/android/i.test(wide), '넓은 벌엔 안드로이드 없음');
});

test('소스 계약 — 아웃트로 폰 벌: 히어로와 같은 규칙(배지 → 안드로이드 주 버튼 → Mac용 다운로드) · outro-android(보이는 결과는 scripts/android-smoke.mjs)', () => {
  const narrow = OUTRO.slice(OUTRO.lastIndexOf('<div', OUTRO.indexOf('placement="outro-phone"')));
  const badge = narrow.indexOf('<AppStoreBadge');
  const android = narrow.indexOf('href={LINKS.android}');
  const install = narrow.indexOf('href={LINKS.install}');
  assert.ok(badge >= 0 && badge < android && android < install);
  assert.match(narrow, /placement="outro-phone" className="-m-3 \[html\[data-android\]_&\]:hidden"/);
  const btn = /<a\s+href=\{LINKS\.android\}\s+data-cta="outro-android"\s+className=\{glassButtonClass\("primary", "l", "hidden [^"]*\[--b-h:48px\][^"]*\[html\[data-android\]_&\]:inline-flex"\)\}\s*>\s*\{ANDROID_COPY\.phoneCta\}/.exec(narrow);
  assert.ok(btn, '아웃트로 주 버튼');
  assert.match(narrow, /href=\{LINKS\.install\} data-cta="outro-install"/);
});
