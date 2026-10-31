// node --experimental-strip-types --test lib/platform.test.ts
// 첫 페인트 전 플랫폼 판별(lib/platform.ts PLATFORM_SCRIPT — docs/v3/brief.md §12 안드로이드 덧붙임) 계약.
// 모양을 재지 않고 **스크립트 문자열을 실제로 실행**한다(node:vm 새 맥락 — document · navigator · location 만 흉내).
// 실행 뒤 <html> 의 속성(class · data-platform · data-android)을 본다. UA 표 = 실제 브라우저 UA 문자열.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { PLATFORM_SCRIPT, getPlatform, isAndroid } from './platform.ts';

type Html = {
  attrs: Map<string, string>;
  classes: Set<string>;
  style: Record<string, string>;
  hasAttribute(name: string): boolean;
  getAttribute(name: string): string | null;
};

/** dataset 은 DOM 처럼 data-* 속성으로 비친다(camelCase → kebab). */
function fakeHtml(): Html & { classList: { add(c: string): void }; dataset: Record<string, string | undefined> } {
  const attrs = new Map<string, string>();
  const classes = new Set<string>();
  const toAttr = (k: string) => `data-${k.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`;
  const dataset = new Proxy({} as Record<string, string | undefined>, {
    set(_, k: string, v) {
      attrs.set(toAttr(k), String(v));
      return true;
    },
    get(_, k: string) {
      return attrs.get(toAttr(k));
    },
  });
  return {
    attrs,
    classes,
    style: {},
    classList: { add: (c: string) => void classes.add(c) },
    dataset,
    hasAttribute: (n: string) => attrs.has(n),
    getAttribute: (n: string) => attrs.get(n) ?? null,
  };
}

/** PLATFORM_SCRIPT 를 새 맥락에서 실행하고 <html> 을 돌려준다. */
function run(ua: string, { maxTouchPoints = 0, hash = '' }: { maxTouchPoints?: number; hash?: string } = {}) {
  const html = fakeHtml();
  const loads: unknown[] = [];
  const ctx = {
    document: { documentElement: html },
    navigator: { userAgent: ua, maxTouchPoints },
    location: { hash },
    addEventListener: (type: string, fn: unknown) => void loads.push([type, fn]),
    requestAnimationFrame: (fn: () => void) => fn(),
  };
  vm.runInNewContext(PLATFORM_SCRIPT, ctx);
  return { html, loads };
}

const UA = {
  androidPhoneChrome:
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.102 Mobile Safari/537.36',
  androidPhoneSamsung:
    'Mozilla/5.0 (Linux; Android 14; SAMSUNG SM-S921N) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0.0.0 Mobile Safari/537.36',
  androidTablet: 'Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  iphone:
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  /** iPad 데스크톱 모드 = 맥 사파리와 같은 UA + 터치 */
  macintosh: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
  windowsChrome: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  /** 안드로이드 크롬 '데스크톱 사이트' — UA 에 Android 가 없다(판별 못 함 = 그냥 other) */
  androidDesktopMode: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
} as const;

const TABLE: { name: string; ua: string; touch: number; platform: 'mac' | 'ios' | 'other'; android: boolean }[] = [
  { name: '안드로이드 폰 크롬', ua: UA.androidPhoneChrome, touch: 5, platform: 'other', android: true },
  { name: '안드로이드 폰 삼성 인터넷', ua: UA.androidPhoneSamsung, touch: 5, platform: 'other', android: true },
  { name: '안드로이드 태블릿', ua: UA.androidTablet, touch: 10, platform: 'other', android: true },
  { name: '아이폰 사파리', ua: UA.iphone, touch: 5, platform: 'ios', android: false },
  { name: 'iPad 데스크톱 모드(Macintosh + 터치)', ua: UA.macintosh, touch: 5, platform: 'ios', android: false },
  { name: '맥 사파리', ua: UA.macintosh, touch: 0, platform: 'mac', android: false },
  { name: '윈도 크롬', ua: UA.windowsChrome, touch: 0, platform: 'other', android: false },
  { name: '안드로이드 크롬 데스크톱 사이트(UA 에 Android 없음)', ua: UA.androidDesktopMode, touch: 5, platform: 'other', android: false },
];

for (const row of TABLE) {
  test(`UA 표: ${row.name} → data-platform=${row.platform}${row.android ? ' + data-android=""' : ' · data-android 없음'}`, () => {
    const { html } = run(row.ua, { maxTouchPoints: row.touch });
    assert.ok(html.classes.has('js'), "class 'js'");
    assert.equal(html.getAttribute('data-platform'), row.platform);
    assert.equal(html.hasAttribute('data-android'), row.android);
    if (row.android) assert.equal(html.getAttribute('data-android'), '', '값 없는 속성 — CSS [html[data-android]_&] 가 본다');
    // 안드로이드여도 data-platform 은 other 그대로(기존 [html[data-platform=other]_&] 규칙이 깨지지 않게)
    if (row.android) assert.equal(html.getAttribute('data-platform'), 'other');
  });
}

test('안드로이드 판별은 try 안: navigator 가 터지면 class js 만 달고 속성은 없다(페이지는 기본 벌 그대로)', () => {
  const html = fakeHtml();
  const ctx = {
    document: { documentElement: html },
    get navigator(): never {
      throw new Error('no navigator');
    },
    location: { hash: '' },
  };
  assert.doesNotThrow(() => vm.runInNewContext(PLATFORM_SCRIPT, ctx));
  assert.ok(html.classes.has('js'));
  assert.equal(html.hasAttribute('data-platform'), false);
  assert.equal(html.hasAttribute('data-android'), false);
});

test('해시로 들어온 첫 로드는 그대로: 안드로이드여도 scroll-behavior auto → load 뒤 두 프레임에 걷는다', () => {
  const { html, loads } = run(UA.androidPhoneChrome, { maxTouchPoints: 5, hash: '#android' });
  assert.equal(html.style.scrollBehavior, 'auto');
  assert.equal(loads.length, 1);
  const [type, fn] = loads[0] as [string, () => void];
  assert.equal(type, 'load');
  fn();
  assert.equal(html.style.scrollBehavior, '', 'load 뒤 원래대로');
  assert.ok(html.hasAttribute('data-android'));
  // 해시 없으면 load 를 걸지 않는다
  assert.equal(run(UA.androidPhoneChrome).loads.length, 0);
});

test('스크립트는 짧다(첫 페인트 전 인라인) · 안드로이드 판별은 한 군데', () => {
  assert.ok(Buffer.byteLength(PLATFORM_SCRIPT) <= 520, `${Buffer.byteLength(PLATFORM_SCRIPT)}B`);
  assert.equal(PLATFORM_SCRIPT.match(/Android/g)?.length, 1);
});

test('isAndroid() · getPlatform(): 서버(document 없음) = false · other, 스크립트 뒤엔 <html> 을 읽는다', () => {
  assert.equal(isAndroid(), false);
  assert.equal(getPlatform(), 'other');
  const g = globalThis as { document?: unknown };
  for (const row of TABLE) {
    const { html } = run(row.ua, { maxTouchPoints: row.touch });
    g.document = { documentElement: html };
    try {
      assert.equal(isAndroid(), row.android, row.name);
      assert.equal(getPlatform(), row.platform, row.name);
    } finally {
      delete g.document;
    }
  }
});
