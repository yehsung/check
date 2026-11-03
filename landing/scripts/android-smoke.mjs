#!/usr/bin/env node
/**
 * 안드로이드(Play 스토어 출시 준비 중) · 설치 선택 창 브라우저 스모크(docs/v3/brief.md §12.7 · §11) — 빌드한 사이트를 헤드리스 Chromium 으로 열어 '보이는 결과'를 잰다.
 * components/install/android.test.ts · chooser.test.ts 의 '소스 계약 —' 시험은 글자 꼴만 본다(CSS 우선순위로 hidden 이 지는 일 등은 못 잡는다).
 * 빌드·배포에는 걸지 않는다. 서버는 부르는 쪽이 띄우고 끈다(미리보기·운영 주소도 된다). playwright 는 이 패키지 의존성이 아니다 — 든 node_modules 를 알려 준다.
 *
 *   npx next start -p 3101 &   # 그다음
 *   PLAYWRIGHT_DIR=<playwright 가 든 node_modules> npm run android:smoke -- --base http://localhost:3101
 *
 * 재는 것
 *   서버 HTML · llms.txt: 10-30 베타 안내(구글 그룹 · 웹 테스터 등록 주소, '안드로이드 베타' · '테스터 되기' 글자, 단계 측정 표식)가 없다 ·
 *     출시 준비 중 한 줄이 있다 · Play 스토어 주소 0(출시 전 — 비로그인 404)
 *   폰 390 안드로이드 UA: <html data-android> · 히어로/아웃트로 App Store 배지 display:none · Mac용 다운로드가 줄을 채운다(화면 폭 안) ·
 *     히어로 메타 = 안드로이드 메타 · 설치 절 안드로이드 카드가 맨 앞 · 카드에 누를 것 0 · 카드 문단 text-wrap pretty · 페이지 오류 0
 *   폰 390 기본 UA · 아이폰 UA · 안드로이드 UA + JS 끔: 배지 보임 · 안드로이드 메타 숨김(판별 전 = 예전과 같다)
 *   1440×900 · 768×1024: 안드로이드 카드 = 3번째 줄 두 칸 전폭 · 낮은 띠(제목·한 줄 한 줄)
 *   선택 창: 1440×900 · 1024×768 히어로 — 창이 화면 안 · 휴대폰 줄(이름 + [아이폰] 칩 + 안드로이드 글자) 세로 중심 하나(한 줄) · 창 안쪽 폭 안 ·
 *            안드로이드 글자는 링크 아님(Tab 고리 밖)
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
/** 출시 준비 중 한 줄(data/install-copy.ts ANDROID_COPY.line) · 폰 메타 */
const LINE = "안드로이드 앱은 Play 스토어 출시를 준비하고 있어요.";
const PHONE_META_PART = "안드로이드 출시 준비 중";
/** 내린 베타 안내의 흔적(HTML · llms.txt 어디에도 없어야 한다) */
const RETIRED = [
  "groups.google.com",
  "aingcheck-android-beta",
  "play.google.com/apps/testing",
  "안드로이드 베타",
  "안드로이드는 베타로",
  "테스터 되기",
  "구글 그룹",
  "data-android-help",
  'data-cta="hero-android"',
  'data-cta="outro-android"',
  'data-cta="chooser-android"',
  'data-cta="android-',
];

let failed = 0;
function check(name, cond, detail = "") {
  if (cond) console.log(`ok    ${name}`);
  else {
    failed++;
    console.log(`FAIL  ${name}${detail ? ` — ${detail}` : ""}`);
  }
}

// ─── 서버 HTML · llms.txt ─────────────────────────────────────────────────────────────────────
{
  const html = await (await fetch(`${BASE}/`)).text();
  const llms = await (await fetch(`${BASE}/llms.txt`)).text();
  for (const [tag, text] of [["HTML", html], ["llms.txt", llms]]) {
    const left = RETIRED.filter((r) => text.includes(r));
    check(`${tag}: 내린 베타 안내 0`, left.length === 0, left.join(" · "));
    check(`${tag}: Play 스토어 주소 0(출시 전)`, !text.includes("play.google.com"));
    check(`${tag}: 출시 준비 중 한 줄 있음`, text.includes(LINE));
  }
  check("HTML: 설치 절 안드로이드 카드(#android) 있음", /id="android"/.test(html));
  check("llms.txt: '- Android: {한 줄}' 한 줄", llms.split("\n").filter((l) => l === `- Android: ${LINE}`).length === 1);
}

const browser = await chromium.launch({ headless: true });

async function open({ w, h, ua, js = true, path = "/" }) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1, javaScriptEnabled: js, ...(ua ? { userAgent: UA[ua] } : {}) });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e.message || e)));
  page.on("console", (m) => m.type() === "error" && /hydrat/i.test(m.text()) && errors.push(m.text()));
  await page.goto(`${BASE}${path}`, { waitUntil: "networkidle" });
  if (js) await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(js ? 1500 : 300); // 히어로 등장(rise-in)이 끝나게
  return { ctx, page, errors };
}

/** 폰 첫 화면 · 설치 절 상태(보이는 결과만) */
const phoneState = () => {
  const shown = (el) => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== "hidden";
  const box = (el) => {
    if (!shown(el)) return null;
    const r = el.getBoundingClientRect();
    return { top: r.top + scrollY, left: r.left, right: r.right, width: r.width, height: r.height };
  };
  const q = (s) => document.querySelector(s);
  const card = q("#android");
  const metas = [...document.querySelectorAll(".hero-copy p span")].filter(shown).map((s) => s.textContent);
  return {
    android: document.documentElement.hasAttribute("data-android"),
    vw: document.documentElement.clientWidth,
    heroInstall: box(q('[data-cta="hero-install"]')),
    heroBadge: box(q('[data-placement="hero-phone"]')),
    outroInstall: box(q('[data-cta="outro-install"]')),
    outroBadge: box(q('[data-placement="outro-phone"]')),
    metas,
    cards: ["brew", "dmg", "iphone", "android"].map((k) => [k, box(q(`[data-install="${k}"]`))?.top ?? null]),
    cardBox: box(card),
    cardText: card.innerText.replace(/\s+/g, " ").trim(),
    cardInteractive: card.querySelectorAll("a, button, details, [tabindex]").length,
    androidLight: [...document.querySelectorAll("#install > .local-light")].some((l) => l.className.includes("data-android") && getComputedStyle(l).display !== "none"),
    prettyMissing: [...card.querySelectorAll("p")].filter((p) => shown(p) && !/pretty/.test(getComputedStyle(p).textWrapStyle || getComputedStyle(p).textWrap || "")).length,
  };
};

// ─── 폰 390 ────────────────────────────────────────────────────────────────────────────────────
{
  const { ctx, page, errors } = await open({ w: 390, h: 844, ua: "android" });
  const s = await page.evaluate(phoneState);
  const tag = "390 안드로이드";
  check(`${tag}: <html data-android>`, s.android);
  check(`${tag}: 히어로 App Store 배지 display:none`, s.heroBadge === null, JSON.stringify(s.heroBadge));
  check(`${tag}: 아웃트로 App Store 배지 display:none`, s.outroBadge === null, JSON.stringify(s.outroBadge));
  for (const [k, b] of [["히어로", s.heroInstall], ["아웃트로", s.outroInstall]]) {
    check(`${tag}: ${k} Mac용 다운로드가 줄을 채운다(화면 폭 안 · 높이 48)`, b && b.left >= 0 && b.right <= s.vw && b.width > s.vw * 0.75 && Math.abs(b.height - 48) < 0.5, JSON.stringify(b));
  }
  check(`${tag}: 히어로 메타 = 안드로이드 메타`, s.metas.some((m) => m.includes(PHONE_META_PART)) && !s.metas.some((m) => m.includes("iOS 18")), JSON.stringify(s.metas));
  const tops = Object.fromEntries(s.cards);
  check(`${tag}: 설치 절 안드로이드 카드가 맨 앞`, tops.android !== null && Object.values(tops).every((t) => t === null || tops.android <= t), JSON.stringify(tops));
  check(`${tag}: 카드 = 제목 · 한 줄뿐(누를 것 0)`, s.cardInteractive === 0 && s.cardText === `안드로이드 ${LINE}`, JSON.stringify([s.cardText, s.cardInteractive]));
  check(`${tag}: 카드 문단 text-wrap pretty`, s.prettyMissing === 0, `${s.prettyMissing}개 빠짐`);
  check(`${tag}: 폰 안드로이드 전용 빛 없음`, !s.androidLight);
  check(`${tag}: 페이지 오류 · 하이드레이션 오류 0`, errors.length === 0, errors.join(" | "));
  await ctx.close();
}
for (const [tag, cfg] of [["390 기본 UA", { w: 390, h: 844 }], ["390 아이폰", { w: 390, h: 844, ua: "iphone" }], ["390 안드로이드 JS 끔", { w: 390, h: 844, ua: "android", js: false }]]) {
  const { ctx, page } = await open(cfg);
  const s = await page.evaluate(phoneState);
  check(`${tag}: data-android 없음`, !s.android);
  check(`${tag}: 히어로 배지 보임`, s.heroBadge !== null && s.heroBadge.height > 0);
  check(`${tag}: 안드로이드 메타 숨김`, !s.metas.some((m) => m.includes(PHONE_META_PART)), JSON.stringify(s.metas));
  await ctx.close();
}
for (const [w, h] of [[1440, 900], [768, 1024]]) {
  const { ctx, page } = await open({ w, h });
  const s = await page.evaluate(() => {
    const r = (sel) => document.querySelector(sel).getBoundingClientRect();
    const card = r("#android");
    const brew = r('[data-install="brew"]');
    const iphone = r('[data-install="iphone"]');
    const h3 = r("#android h3");
    const p = r("#android p");
    return { card: [card.left, card.right, card.top, card.height], left: brew.left, right: iphone.right, below: card.top >= iphone.bottom, sameLine: Math.abs(h3.bottom - p.bottom) < 6 };
  });
  const tag = `${w}×${h} 안드로이드 카드`;
  check(`${tag}: 3번째 줄 두 칸 전폭(아이폰 카드 아래)`, s.below && Math.abs(s.card[0] - s.left) < 1 && Math.abs(s.card[1] - s.right) < 1, JSON.stringify(s));
  check(`${tag}: 낮은 띠(제목 · 한 줄이 한 줄 · 높이 ${Math.round(s.card[3])})`, s.sameLine && s.card[3] < 120, JSON.stringify(s));
  await ctx.close();
}

// ─── 선택 창 ───────────────────────────────────────────────────────────────────────────────────
const chooserState = (cta) => {
  const trig = [...document.querySelectorAll(`[data-cta="${cta}"]`)].find((x) => x.getClientRects().length);
  const pop = document.getElementById(trig.getAttribute("aria-controls"));
  const p = pop.getBoundingClientRect();
  const navH = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--nav-h")) || 46;
  const row = pop.querySelector(".ic-phone");
  const kids = [...row.querySelectorAll(".ic-phone__title, .ic-chip, .ic-soon")].map((el) => el.getBoundingClientRect());
  const centers = kids.map((r) => (r.top + r.bottom) / 2);
  const cs = getComputedStyle(pop);
  const innerRight = p.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth);
  const more = pop.querySelector(".ic-more").getBoundingClientRect();
  const soon = row.querySelector(".ic-soon");
  return {
    open: !pop.hidden,
    side: pop.dataset.side,
    pop: [Math.round(p.top), Math.round(p.bottom)],
    vh: innerHeight,
    navH,
    inView: p.top >= navH && p.bottom <= innerHeight,
    moreBottom: Math.round(more.bottom),
    kids: kids.length,
    centerSpread: Math.max(...centers) - Math.min(...centers),
    rowRight: Math.max(...kids.map((r) => r.right)),
    innerRight,
    titleLines: Math.round(kids[0].height / 17.55), // 13.5px × 1.3
    soonText: soon?.textContent ?? null,
    soonFocusable: !!soon && (soon.matches("a, button, [tabindex]") || !!soon.querySelector("a, button, [tabindex]")),
  };
};

for (const [w, h] of [[1440, 900], [1024, 768]]) {
  const { ctx, page } = await open({ w, h });
  await page.locator('[data-cta="hero-chooser"]:visible').click();
  await page.waitForTimeout(400);
  const s = await page.evaluate(chooserState, "hero-chooser");
  const tag = `${w}×${h} 히어로 선택 창`;
  check(`${tag}: 열림 · 화면 안(${s.side} ${s.pop.join("–")})`, s.open && s.inView, JSON.stringify(s));
  check(`${tag}: 휴대폰 줄 = 이름 + 칩 + 안드로이드 글자 한 줄(세로 중심 차 ${s.centerSpread.toFixed(1)}px)`, s.kids === 3 && s.centerSpread <= 1.5 && s.titleLines === 1, JSON.stringify(s));
  check(`${tag}: 휴대폰 줄이 창 안쪽 폭 안`, s.rowRight <= s.innerRight + 0.5, `${s.rowRight} > ${s.innerRight}`);
  check(`${tag}: 안드로이드 글자 '${s.soonText}' · 링크 아님`, s.soonText === PHONE_META_PART && !s.soonFocusable, JSON.stringify(s));
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
