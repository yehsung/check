#!/usr/bin/env node
/**
 * 안드로이드 베타 · 설치 선택 창 브라우저 스모크(docs/v3/brief.md §12) — 빌드한 사이트를 헤드리스 Chromium 으로 열어 '보이는 결과'를 잰다.
 * components/install/android.test.ts · chooser.test.ts 의 '소스 계약 —' 시험은 글자 꼴만 본다(CSS 우선순위로 hidden 이 지는 일 등은 못 잡는다).
 * 빌드·배포에는 걸지 않는다. 서버는 부르는 쪽이 띄우고 끈다. playwright 는 이 패키지 의존성이 아니다 — 든 node_modules 를 알려 준다.
 *
 *   npx next start -p 3101 &   # 그다음
 *   PLAYWRIGHT_DIR=<playwright 가 든 node_modules> npm run android:smoke -- --base http://localhost:3101
 *
 * 재는 것
 *   폰 390 안드로이드 UA: <html data-android> · 히어로/아웃트로 [안드로이드 베타 받기] 보임(높이 48) · App Store 배지 display:none ·
 *     두 버튼 화면 안 · 설치 절 안드로이드 카드가 맨 앞 · 카드 뒤 폰 안드로이드 전용 빛 · 카드 문단 text-wrap pretty · 카드에 금지된 aria 이름 없음
 *   폰 390 기본 UA · 아이폰 UA · 안드로이드 UA + JS 끔: 배지 보임 · 안드로이드 버튼 숨김 · 전용 빛 숨김(판별 전 = 예전과 같다)
 *   다음 단계 안내 · 문제 해결(§12.6): 390 안드로이드 UA(/#android — 카드가 화면 안이라 layout-shift 가 잡힌다) 처음 = 1단계 주 버튼 · 1단계 li aria-current ·
 *     단계 버튼 높이 ≥ 48 · 폭 = 카드 안 폭 · 버튼 사이 넉넉히 → 1단계 클릭(새 탭은 가로채 닫는다 — 구글 주소는 가짜 응답) → 1 체크 · 2단계 주 버튼 · aria-current ·
 *     저장 '1' · 버튼 상자 그대로 · 카드 안 layout-shift 0 → 새로고침 뒤 유지(layout-shift 0 · 하이드레이션 오류 0) → 3단계 → 셋 다 체크 · 주 버튼 없음 →
 *     1단계 다시(순서를 막지 않는다) · 문제 해결 <details> 기본 닫힘 · 요약 줄 ≥ 44 · Tab 으로 3단계 버튼 다음 · Enter 열고 Space 닫기 ·
 *     저장소 접근자가 던지는 컨텍스트 = 처음 상태 · 클릭은 메모리로 · 새로고침이면 처음 · 페이지 오류 0 / 이상한 저장 값('7') = 처음 상태 /
 *     JS 끔 = 서버 HTML 그대로(1단계 주 버튼 · aria-current) / 1440 = 버튼 32 그대로 · 클릭 뒤 상자 그대로
 *   선택 창: 1440×900 · 1024×768 히어로 — 창이 화면 안 · 휴대폰 줄(이름 + 칩 둘) 세로 중심 하나(한 줄) · 창 안쪽 폭 안
 *            페이지 끝 아웃트로(1440×900 · 1440×700 · 1366×657 · 1280×680) — 열고 나면 창 전체(맨 아래 '설치 방법 자세히 보기'까지)가 화면 안
 * 출력: 검사마다 ok/FAIL 한 줄. 하나라도 FAIL 이면 exit 1.
 */
import { createRequire } from "node:module";

const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : fallback;
};
const BASE = arg("--base", "http://localhost:3101").replace(/\/+$/, "");
const PW_DIR = arg("--playwright", process.env.PLAYWRIGHT_DIR);

let chromium;
try {
  const req = createRequire(PW_DIR ? `${PW_DIR.replace(/\/+$/, "")}/` : import.meta.url);
  ({ chromium } = req("playwright"));
} catch {
  console.error("playwright 를 찾지 못했다 — PLAYWRIGHT_DIR=<playwright 가 든 node_modules> 또는 --playwright <경로>");
  process.exit(2);
}

const UA = {
  android: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36",
  iphone: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
};

let failed = 0;
function check(name, cond, detail = "") {
  if (cond) console.log(`ok    ${name}`);
  else {
    failed++;
    console.log(`FAIL  ${name}${detail ? ` — ${detail}` : ""}`);
  }
}

const browser = await chromium.launch({ headless: true });

async function open({ w, h, ua, js = true }) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1, javaScriptEnabled: js, ...(ua ? { userAgent: UA[ua] } : {}) });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/`, { waitUntil: "networkidle" });
  if (js) await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(js ? 1500 : 300); // 히어로 등장(rise-in)이 끝나게
  return { ctx, page };
}

/** 폰 첫 화면 · 설치 절 상태(보이는 결과만) */
const phoneState = () => {
  const shown = (el) => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== "hidden";
  const box = (el) => {
    if (!shown(el)) return null;
    const r = el.getBoundingClientRect();
    return { top: r.top + scrollY, left: r.left, right: r.right, height: r.height };
  };
  const q = (s) => document.querySelector(s);
  const card = q("#android");
  const lights = [...document.querySelectorAll("#install > .local-light")];
  return {
    android: document.documentElement.hasAttribute("data-android"),
    vw: document.documentElement.clientWidth,
    heroAndroid: box(q('[data-cta="hero-android"]')),
    heroInstall: box(q('[data-cta="hero-install"]')),
    heroBadge: box(q('[data-placement="hero-phone"]')),
    outroAndroid: box(q('[data-cta="outro-android"]')),
    outroInstall: box(q('[data-cta="outro-install"]')),
    outroBadge: box(q('[data-placement="outro-phone"]')),
    cards: ["brew", "dmg", "iphone", "android"].map((k) => [k, box(q(`[data-install="${k}"]`))?.top ?? null]),
    lightsShown: lights.filter((l) => getComputedStyle(l).display !== "none").length,
    lightsTotal: lights.length,
    cardBox: box(card),
    androidLight: (() => {
      const l = lights.find((x) => x.className.includes("data-android"));
      if (!l || getComputedStyle(l).display === "none") return null;
      const r = l.getBoundingClientRect();
      return { top: r.top + scrollY, bottom: r.bottom + scrollY };
    })(),
    prettyMissing: [...card.querySelectorAll("p")].filter((p) => shown(p) && !/pretty/.test(getComputedStyle(p).textWrapStyle || getComputedStyle(p).textWrap || "")).length,
    cardNamed: card.hasAttribute("aria-labelledby") || card.hasAttribute("aria-label"),
    cardRole: card.getAttribute("role"),
  };
};

// ─── 폰 390 ────────────────────────────────────────────────────────────────────────────────────
{
  const { ctx, page } = await open({ w: 390, h: 844, ua: "android" });
  const s = await page.evaluate(phoneState);
  const tag = "390 안드로이드";
  check(`${tag}: <html data-android>`, s.android);
  check(`${tag}: 히어로 [안드로이드 베타 받기] 보임 · 높이 48`, s.heroAndroid && Math.abs(s.heroAndroid.height - 48) < 0.5, JSON.stringify(s.heroAndroid));
  check(`${tag}: 히어로 App Store 배지 display:none`, s.heroBadge === null, JSON.stringify(s.heroBadge));
  check(`${tag}: 아웃트로 [안드로이드 베타 받기] 보임 · 높이 48`, s.outroAndroid && Math.abs(s.outroAndroid.height - 48) < 0.5, JSON.stringify(s.outroAndroid));
  check(`${tag}: 아웃트로 App Store 배지 display:none`, s.outroBadge === null);
  for (const [k, b] of [["히어로", s.heroAndroid], ["히어로 Mac용", s.heroInstall], ["아웃트로", s.outroAndroid], ["아웃트로 Mac용", s.outroInstall]]) {
    check(`${tag}: ${k} 버튼 화면 폭 안`, b && b.left >= 0 && b.right <= s.vw, JSON.stringify(b));
  }
  const tops = Object.fromEntries(s.cards);
  check(`${tag}: 설치 절 안드로이드 카드가 맨 앞`, tops.android !== null && Object.values(tops).every((t) => t === null || tops.android <= t), JSON.stringify(tops));
  check(`${tag}: 폰 안드로이드 전용 빛이 보이고 카드에 걸친다`, s.androidLight && s.androidLight.top < s.cardBox.top + s.cardBox.height && s.androidLight.bottom > s.cardBox.top, JSON.stringify([s.androidLight, s.cardBox]));
  check(`${tag}: 카드 문단 전부 text-wrap pretty`, s.prettyMissing === 0, `${s.prettyMissing}개 빠짐`);
  check(`${tag}: 카드(generic)에 aria 이름 없음`, !s.cardNamed || !!s.cardRole);
  await ctx.close();
}
for (const [tag, cfg] of [["390 기본 UA", { w: 390, h: 844 }], ["390 아이폰", { w: 390, h: 844, ua: "iphone" }], ["390 안드로이드 JS 끔", { w: 390, h: 844, ua: "android", js: false }]]) {
  const { ctx, page } = await open(cfg);
  const s = await page.evaluate(phoneState);
  check(`${tag}: data-android 없음`, !s.android);
  check(`${tag}: 히어로 배지 보임`, s.heroBadge !== null && s.heroBadge.height > 0);
  check(`${tag}: 히어로·아웃트로 안드로이드 버튼 숨김`, s.heroAndroid === null && s.outroAndroid === null);
  check(`${tag}: 폰 안드로이드 전용 빛 숨김(빛 ${s.lightsTotal - 1}개만)`, s.androidLight === null && s.lightsShown === s.lightsTotal - 1, `${s.lightsShown}/${s.lightsTotal}`);
  await ctx.close();
}

// ─── 다음 단계 안내 · 문제 해결(§12.6) ──────────────────────────────────────────────────────────
/** 구글 주소는 열지 않는다(새 탭은 가짜 응답) */
const GOOGLE = /^https:\/\/(groups|play)\.google\.com\//;

/** layout-shift 를 처음부터 모은다 — 카드(#android) 안 요소가 원인인 것만 합한다(입력 직후 것도 포함) */
function recordShifts() {
  window.__shifts = [];
  try {
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        const inCard = (e.sources || []).some((src) => {
          const n = src.node && (src.node.nodeType === 1 ? src.node : src.node.parentElement);
          return !!(n && n.closest && n.closest("#android"));
        });
        if (inCard) window.__shifts.push(e.value);
      }
    }).observe({ type: "layout-shift", buffered: true });
  } catch {}
}

async function openSteps({ w, h, ua, js = true, init = [] }) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1, javaScriptEnabled: js, ...(ua ? { userAgent: UA[ua] } : {}) });
  await ctx.route(GOOGLE, (r) => r.fulfill({ status: 200, contentType: "text/html", body: "<!doctype html><title>stub</title>" }));
  for (const [fn, argv] of init) await ctx.addInitScript(fn, argv);
  if (js) await ctx.addInitScript(recordShifts);
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
  page.on("console", (m) => {
    if (m.type() === "error" && /#41[89]|#42[35]|hydrat/i.test(m.text())) errors.push(`console: ${m.text().slice(0, 160)}`);
  });
  const settle = async () => {
    if (js) await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(js ? 1200 : 300);
  };
  await page.goto(`${BASE}/#android`, { waitUntil: "networkidle" });
  await settle();
  return { ctx, page, errors, settle };
}

const stepsState = () => {
  const card = document.getElementById("android");
  const cs = getComputedStyle(card);
  const cr = card.getBoundingClientRect();
  const lis = [...card.querySelectorAll("[data-android-step]")];
  const n = (li) => Number(li.dataset.androidStep);
  const btn = (li) => li.querySelector("a.gbtn");
  let stored;
  try {
    stored = localStorage.getItem("aing-android-beta-step");
  } catch {
    stored = "THROWS";
  }
  const det = card.querySelector("[data-android-help]");
  const sum = det.querySelector("summary").getBoundingClientRect();
  return {
    primary: lis.filter((li) => btn(li).classList.contains("gbtn--primary")).map(n),
    outline: lis.filter((li) => btn(li).classList.contains("gbtn--glass")).map(n),
    current: lis.filter((li) => li.getAttribute("aria-current") === "step").map(n),
    // 체크 = data-done + 번호 원 안 장식 svg(aria-hidden) · 번호는 sr-only 로 남는다
    done: lis.filter((li) => li.hasAttribute("data-done") && li.querySelector(':scope > div > span > svg[aria-hidden="true"]') && li.querySelector(":scope > div > span > .sr-only")).map(n),
    btns: lis.map((li) => {
      const r = btn(li).getBoundingClientRect();
      return { left: +r.left.toFixed(2), top: +(r.top + scrollY).toFixed(2), width: +r.width.toFixed(2), height: +r.height.toFixed(2) };
    }),
    inner: { left: cr.left + card.clientLeft + parseFloat(cs.paddingLeft), width: card.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) },
    stored,
    helpOpen: det.open,
    summaryH: sum.height,
    // 닫힌 <details> 안은 content-visibility:hidden 이라 상자를 재면 높이가 있다 → checkVisibility 로 본다
    helpItemsShown: [...det.querySelectorAll("li")].filter((li) => li.checkVisibility({ contentVisibilityAuto: true, visibilityProperty: true })).length,
    shifts: (window.__shifts || []).reduce((a, b) => a + b, 0),
  };
};

const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const sameBoxes = (a, b) => a.every((r, i) => ["left", "top", "width", "height"].every((k) => Math.abs(r[k] - b[i][k]) <= 0.5));

/** 단계 n 버튼 클릭 — 새 탭(구글 가짜 응답)을 받아 닫는다. 새 탭 주소를 돌려준다 */
async function clickStep(ctx, page, cta) {
  const [popup] = await Promise.all([ctx.waitForEvent("page"), page.locator(`[data-cta="${cta}"]`).click()]);
  const url = popup.url();
  await popup.close();
  await page.waitForTimeout(250);
  return url;
}

{
  const tag = "390 안드로이드 다음 단계";
  const { ctx, page, errors, settle } = await openSteps({ w: 390, h: 844, ua: "android" });
  const s0 = await page.evaluate(stepsState);
  check(`${tag}: 처음 = 1단계 주 버튼 · 2·3 outline · 1단계 li aria-current · 체크 없음 · 저장 없음`, same(s0.primary, [1]) && same(s0.outline, [2, 3]) && same(s0.current, [1]) && same(s0.done, []) && s0.stored === null, JSON.stringify(s0));
  check(`${tag}: 단계 버튼 높이 ≥ 48`, s0.btns.every((b) => b.height >= 48), JSON.stringify(s0.btns.map((b) => b.height)));
  check(
    `${tag}: 단계 버튼 폭 = 카드 안 폭(${s0.inner.width.toFixed(1)}px · 왼쪽 맞춤)`,
    s0.btns.every((b) => Math.abs(b.width - s0.inner.width) <= 0.5 && Math.abs(b.left - s0.inner.left) <= 0.5),
    JSON.stringify([s0.inner, s0.btns]),
  );
  const gaps = s0.btns.slice(1).map((b, i) => b.top - (s0.btns[i].top + s0.btns[i].height));
  check(`${tag}: 버튼 사이 넉넉히(위 버튼 아래끝 → 다음 버튼 위끝 ≥ 64px: ${gaps.map((g) => g.toFixed(0)).join(" · ")})`, gaps.every((g) => g >= 64));

  const url1 = await clickStep(ctx, page, "android-group");
  const s1 = await page.evaluate(stepsState);
  check(`${tag}: 1단계 클릭 = 새 탭(그룹 주소) · 랜딩 탭 그대로`, url1.startsWith("https://groups.google.com/g/aingcheck-android-beta") && page.url().startsWith(BASE), url1);
  check(`${tag}: 1단계 클릭 뒤 = 1 체크 · 2단계 주 버튼 · 2단계 li aria-current · 저장 '1'`, same(s1.primary, [2]) && same(s1.outline, [1, 3]) && same(s1.current, [2]) && same(s1.done, [1]) && s1.stored === "1", JSON.stringify(s1));
  check(`${tag}: 클릭 전후 버튼 상자 그대로 · 카드 안 layout-shift ${s1.shifts}`, sameBoxes(s0.btns, s1.btns) && s1.shifts === 0, JSON.stringify([s0.btns, s1.btns]));

  await page.reload({ waitUntil: "networkidle" });
  await settle();
  const s1r = await page.evaluate(stepsState);
  check(`${tag}: 새로고침 뒤 유지(2단계 주 버튼 · aria-current · 1 체크)`, same(s1r.primary, [2]) && same(s1r.current, [2]) && same(s1r.done, [1]), JSON.stringify(s1r));
  check(`${tag}: 새로고침 뒤 저장 값 적용에 카드 안 layout-shift 0 · 버튼 상자 그대로`, s1r.shifts === 0 && sameBoxes(s0.btns, s1r.btns), `${s1r.shifts}`);

  await clickStep(ctx, page, "android-store");
  const s3 = await page.evaluate(stepsState);
  check(`${tag}: 3단계 클릭 뒤 = 셋 다 체크 · 주 버튼 없음 · aria-current 없음 · 저장 '3'`, same(s3.primary, []) && same(s3.current, []) && same(s3.done, [1, 2, 3]) && s3.stored === "3", JSON.stringify(s3));
  await clickStep(ctx, page, "android-group");
  const sAgain = await page.evaluate(stepsState);
  check(`${tag}: 1단계 다시 클릭(순서를 막지 않는다) = 2단계 주 버튼 · 저장 '1'`, same(sAgain.primary, [2]) && same(sAgain.done, [1]) && sAgain.stored === "1", JSON.stringify(sAgain));

  // 문제 해결 <details>
  check(`${tag}: 문제 해결 기본 닫힘 · 요약 줄 ≥ 44(${s0.summaryH.toFixed(0)}px) · 항목 안 보임`, !s0.helpOpen && s0.summaryH >= 44 && s0.helpItemsShown === 0, JSON.stringify([s0.helpOpen, s0.summaryH, s0.helpItemsShown]));
  await page.locator('[data-cta="android-store"]').focus();
  await page.keyboard.press("Tab");
  const tabbed = await page.evaluate(() => document.activeElement?.matches("[data-android-help] > summary") ?? false);
  check(`${tag}: Tab 으로 3단계 버튼 다음이 문제 해결 요약 줄`, tabbed);
  await page.locator("[data-android-help] > summary").focus();
  await page.keyboard.press("Enter");
  await page.waitForTimeout(500);
  const opened = await page.evaluate(stepsState);
  await page.keyboard.press("Space");
  await page.waitForTimeout(500);
  const closed = await page.evaluate(stepsState);
  check(`${tag}: Enter = 열림(항목 ${opened.helpItemsShown}개 보임) · Space = 닫힘`, opened.helpOpen && opened.helpItemsShown === 3 && !closed.helpOpen && closed.helpItemsShown === 0, JSON.stringify([opened.helpOpen, opened.helpItemsShown, closed.helpOpen]));
  check(`${tag}: 하이드레이션 오류 · 페이지 오류 0`, errors.length === 0, errors.join(" | "));
  await ctx.close();
}
{
  // 저장소 접근자가 던진다(사파리 사생활 · 막힌 사이트 데이터) — 서버 HTML 상태로 정상 · 클릭은 메모리로 · 새로고침이면 처음
  const tag = "390 안드로이드 저장소 막힘";
  const block = () => {
    Object.defineProperty(window, "localStorage", {
      configurable: true,
      get() {
        throw new DOMException("blocked", "SecurityError");
      },
    });
  };
  const { ctx, page, errors, settle } = await openSteps({ w: 390, h: 844, ua: "android", init: [[block]] });
  const s0 = await page.evaluate(stepsState);
  check(`${tag}: 처음 = 1단계 주 버튼 · aria-current(저장소 읽기가 던져도)`, s0.stored === "THROWS" && same(s0.primary, [1]) && same(s0.current, [1]) && same(s0.done, []), JSON.stringify(s0));
  await clickStep(ctx, page, "android-group");
  const s1 = await page.evaluate(stepsState);
  check(`${tag}: 1단계 클릭 = 2단계 주 버튼(메모리로 이어간다)`, same(s1.primary, [2]) && same(s1.current, [2]) && same(s1.done, [1]), JSON.stringify(s1));
  await page.reload({ waitUntil: "networkidle" });
  await settle();
  const s2 = await page.evaluate(stepsState);
  check(`${tag}: 새로고침 뒤 = 처음 상태`, same(s2.primary, [1]) && same(s2.current, [1]) && same(s2.done, []), JSON.stringify(s2));
  check(`${tag}: 페이지 오류 · 하이드레이션 오류 0`, errors.length === 0, errors.join(" | "));
  await ctx.close();
}
{
  const tag = "390 안드로이드 이상한 저장 값";
  const seed = (v) => {
    try {
      localStorage.setItem("aing-android-beta-step", v);
    } catch {}
  };
  const { ctx, page, errors } = await openSteps({ w: 390, h: 844, ua: "android", init: [[seed, "7"]] });
  const s = await page.evaluate(stepsState);
  check(`${tag}('7'): 처음 상태(1단계 주 버튼 · 체크 없음) · 오류 0`, s.stored === "7" && same(s.primary, [1]) && same(s.current, [1]) && same(s.done, []) && errors.length === 0, JSON.stringify([s, errors]));
  await ctx.close();
}
{
  const tag = "390 안드로이드 JS 끔";
  const { ctx, page } = await openSteps({ w: 390, h: 844, ua: "android", js: false });
  const s = await page.evaluate(stepsState);
  check(`${tag}: 서버 HTML = 1단계 주 버튼 · 1단계 li aria-current · 문제 해결 닫힘 · 버튼 48 · 카드 안 폭`, same(s.primary, [1]) && same(s.current, [1]) && !s.helpOpen && s.btns.every((b) => b.height >= 48 && Math.abs(b.width - s.inner.width) <= 0.5), JSON.stringify(s));
  await ctx.close();
}
{
  const tag = "1440×900 다음 단계";
  const { ctx, page, errors } = await openSteps({ w: 1440, h: 900 });
  const s0 = await page.evaluate(stepsState);
  check(`${tag}: 처음 = 1단계 주 버튼 · 버튼 높이 32 그대로(유리 s)`, same(s0.primary, [1]) && s0.btns.every((b) => Math.abs(b.height - 32) < 0.5), JSON.stringify(s0.btns));
  await clickStep(ctx, page, "android-testing");
  const s2 = await page.evaluate(stepsState);
  check(`${tag}: 2단계 클릭 = 1·2 체크 · 3단계 주 버튼 · 버튼 상자 그대로 · layout-shift 0`, same(s2.primary, [3]) && same(s2.done, [1, 2]) && sameBoxes(s0.btns, s2.btns) && s2.shifts === 0, JSON.stringify([s2, s0.btns]));
  check(`${tag}: 요약 줄 ≥ 44 · 오류 0`, s0.summaryH >= 44 && errors.length === 0, `${s0.summaryH} ${errors.join(" | ")}`);
  await ctx.close();
}

// ─── 선택 창 ───────────────────────────────────────────────────────────────────────────────────
const chooserState = (cta) => {
  const trig = [...document.querySelectorAll(`[data-cta="${cta}"]`)].find((x) => x.getClientRects().length);
  const pop = document.getElementById(trig.getAttribute("aria-controls"));
  const p = pop.getBoundingClientRect();
  const navH = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--nav-h")) || 46;
  const row = pop.querySelector(".ic-phone");
  const kids = [...row.querySelectorAll(".ic-phone__title, .ic-chip")].map((el) => el.getBoundingClientRect());
  const centers = kids.map((r) => (r.top + r.bottom) / 2);
  const cs = getComputedStyle(pop);
  const innerRight = p.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth);
  const more = pop.querySelector(".ic-more").getBoundingClientRect();
  return {
    open: !pop.hidden,
    side: pop.dataset.side,
    pop: [Math.round(p.top), Math.round(p.bottom)],
    vh: innerHeight,
    navH,
    inView: p.top >= navH && p.bottom <= innerHeight,
    moreBottom: Math.round(more.bottom),
    centerSpread: Math.max(...centers) - Math.min(...centers),
    rowRight: Math.max(...kids.map((r) => r.right)),
    innerRight,
    titleLines: Math.round(kids[0].height / 17.55), // 13.5px × 1.3
  };
};

for (const [w, h] of [[1440, 900], [1024, 768]]) {
  const { ctx, page } = await open({ w, h });
  await page.locator('[data-cta="hero-chooser"]:visible').click();
  await page.waitForTimeout(400);
  const s = await page.evaluate(chooserState, "hero-chooser");
  const tag = `${w}×${h} 히어로 선택 창`;
  check(`${tag}: 열림 · 화면 안(${s.side} ${s.pop.join("–")})`, s.open && s.inView, JSON.stringify(s));
  check(`${tag}: 휴대폰 줄 한 줄(세로 중심 차 ${s.centerSpread.toFixed(1)}px)`, s.centerSpread <= 1 && s.titleLines === 1);
  check(`${tag}: 휴대폰 줄이 창 안쪽 폭 안`, s.rowRight <= s.innerRight + 0.5, `${s.rowRight} > ${s.innerRight}`);
  await ctx.close();
}
for (const [w, h] of [[1440, 900], [1440, 700], [1366, 657], [1280, 680]]) {
  const { ctx, page } = await open({ w, h });
  await page.evaluate(() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "instant" }));
  await page.waitForTimeout(600);
  await page.locator('[data-cta="outro-chooser"]:visible').click();
  await page.waitForTimeout(400);
  const s = await page.evaluate(chooserState, "outro-chooser");
  check(`${w}×${h} 페이지 끝 아웃트로 선택 창: 맨 아래 링크까지 화면 안(${s.side} ${s.pop.join("–")} · vh ${s.vh})`, s.open && s.inView && s.moreBottom <= s.vh, JSON.stringify(s));
  await ctx.close();
}

await browser.close();
console.log(failed ? `\n${failed}건 FAIL` : "\n전부 ok");
process.exit(failed ? 1 : 0);
