#!/usr/bin/env node
/**
 * SEO 스모크(docs/v3/seo.md §5) — 빌드한 사이트에 실제로 요청을 보내 응답을 잰다(lib/seo.test.ts 는 순수 함수·소스 꼴만 잰다).
 * 빌드·배포에는 걸지 않는다. 서버는 부르는 쪽이 띄우고 끈다.
 *
 *   npx next start -p 3101 &   # 그다음
 *   npm run seo:smoke -- --base http://localhost:3101
 *   npm run seo:smoke -- --base https://aing-check.vercel.app
 *
 * 소유 확인 메타: GOOGLE_/NAVER_/BING_SITE_VERIFICATION 이 이 명령의 환경에 있으면 그 값이 meta 로 찍혔는지,
 * 없으면 meta 가 하나도 없는지 본다(빌드할 때와 같은 환경으로 돌린다).
 * 출력: 검사마다 ok/FAIL 한 줄. 하나라도 FAIL 이면 exit 1.
 */
import {
  DESCRIPTION,
  INDEXNOW_KEY,
  LLMS_SUMMARY,
  ROBOTS_AGENTS,
  TITLE,
  verificationFromEnv,
} from "../lib/seo.ts";

const argBase = process.argv.indexOf("--base");
const BASE = (argBase > 0 ? process.argv[argBase + 1] : "http://localhost:3101").replace(/\/+$/, "");

let failed = 0;
function check(name, cond, detail = "") {
  if (cond) console.log(`ok    ${name}`);
  else {
    failed++;
    console.log(`FAIL  ${name}${detail ? ` — ${detail}` : ""}`);
  }
}

async function get(path) {
  const res = await fetch(BASE + path, { redirect: "manual", signal: AbortSignal.timeout(15_000) });
  return { status: res.status, type: res.headers.get("content-type") ?? "", cache: res.headers.get("cache-control") ?? "", body: await res.text() };
}

const decode = (s) =>
  s.replace(/&quot;/g, '"').replace(/&#x27;/g, "'").replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
const metas = (html, name) =>
  [...html.matchAll(/<meta\b[^>]*>/g)]
    .map((m) => m[0])
    .filter((t) => new RegExp(`\\bname="${name.replace(/\./g, "\\.")}"`).test(t))
    .map((t) => decode((/\bcontent="([^"]*)"/.exec(t) ?? [])[1] ?? ""));

// ─── 첫 페이지 ──────────────────────────────────────────────────────────────────────────────
const home = await get("/");
check("/ → 200", home.status === 200, String(home.status));
const titles = [...home.body.matchAll(/<title\b[^>]*>([\s\S]*?)<\/title>/g)].map((m) => decode(m[1]));
check("<title> 하나 = TITLE", titles.length === 1 && titles[0] === TITLE, JSON.stringify(titles));
check("meta description = DESCRIPTION", metas(home.body, "description")[0] === DESCRIPTION);
const og = /<meta\b[^>]*property="og:title"[^>]*content="([^"]*)"/.exec(home.body);
check("og:title = TITLE", og && decode(og[1]) === TITLE);
// 사이트 주소(빌드 환경의 SITE_URL)는 canonical 에서 — robots·sitemap·LD 의 절대 주소가 모두 같은 곳을 가리키는지 본다
const homeCanon = /<link rel="canonical" href="([^"]+)"/.exec(home.body)?.[1];
check("첫 페이지 canonical", Boolean(homeCanon), String(homeCanon));
const ORIGIN = homeCanon ? new URL(homeCanon).origin : "";
console.log(`      (사이트 주소 = ${ORIGIN})`);

const lds = [...home.body.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => m[1]);
check("JSON-LD 둘(@graph · FAQPage)", lds.length === 2, String(lds.length));
let graph = null;
let faq = null;
for (const raw of lds) {
  try {
    const j = JSON.parse(raw);
    if (Array.isArray(j["@graph"])) graph = j;
    if (j["@type"] === "FAQPage") faq = j;
  } catch (e) {
    check("JSON-LD 가 JSON 으로 읽힌다", false, String(e));
  }
}
check(
  "@graph = WebSite · Organization · SoftwareApplication · MobileApplication",
  graph && graph["@graph"].map((n) => n["@type"]).join(",") === "WebSite,Organization,SoftwareApplication,MobileApplication",
);
check("FAQPage 질문 5", faq && Array.isArray(faq.mainEntity) && faq.mainEntity.length === 5);
const ldText = lds.join("\n");
check("LD 에 별점·리뷰 0", !/aggregateRating|"review"|ratingValue/.test(ldText));
check("LD WebSite url = canonical", graph && new URL(graph["@graph"][0].url).href === new URL(homeCanon ?? "x:").href);
const mac = graph?.["@graph"].find((n) => n["@type"] === "SoftwareApplication");
if (mac?.screenshot) {
  const shotPath = new URL(mac.screenshot).pathname + new URL(mac.screenshot).search;
  check("LD screenshot = 화면의 <img src>", home.body.includes(`src="${shotPath.replace(/&/g, "&amp;")}"`), shotPath);
}
// 버전이 실렸다면 /api/release 가 GitHub 출처여야 한다(폴백 상수를 '사실'로 내지 않는다)
const rel = await get("/api/release");
let relJson = null;
try {
  relJson = JSON.parse(rel.body);
} catch {}
if (relJson) {
  const live = relJson.source === "github";
  check(
    `LD 버전·크기 ${live ? "있음(github)" : "없음(fallback)"}`,
    live ? mac?.softwareVersion === relJson.version : !("softwareVersion" in (mac ?? {})) && !("fileSize" in (mac ?? {})),
    `source=${relJson.source} softwareVersion=${mac?.softwareVersion}`,
  );
}

const want = verificationFromEnv(process.env) ?? {};
const wantOther = want.other ?? {};
for (const [name, value] of [
  ["google-site-verification", want.google],
  ["naver-site-verification", wantOther["naver-site-verification"]],
  ["msvalidate.01", wantOther["msvalidate.01"]],
]) {
  const got = metas(home.body, name);
  check(
    value ? `meta ${name} = 환경 값` : `meta ${name} 없음(환경 비어 있음)`,
    value ? got.length === 1 && got[0] === value : got.length === 0,
    JSON.stringify(got),
  );
}
check("첫 페이지 robots 메타에 noindex 0", !metas(home.body, "robots").some((c) => /noindex/.test(c)));
const gb = metas(home.body, "googlebot");
check("googlebot 메타 = max-* 셋", gb.length === 1 && /max-image-preview:large/.test(gb[0]) && /max-snippet:-1/.test(gb[0]) && /max-video-preview:-1/.test(gb[0]), JSON.stringify(gb));

// ─── 404 ───────────────────────────────────────────────────────────────────────────────────
const nf = await get(`/seo-smoke-${Date.now().toString(36)}`);
check("없는 경로 → 404", nf.status === 404, String(nf.status));
const nfRobots = metas(nf.body, "robots");
check("404 robots 메타 = noindex 만(index 0)", nfRobots.length >= 1 && nfRobots.every((c) => !/(^|[\s,])index\b/.test(c)), JSON.stringify(nfRobots));
check("404 googlebot 메타에 index 0", metas(nf.body, "googlebot").every((c) => !/(^|[\s,])index\b/.test(c)));

// ─── robots.txt · sitemap.xml ─────────────────────────────────────────────────────────────
const robots = await get("/robots.txt");
check("/robots.txt → 200 text/plain", robots.status === 200 && robots.type.startsWith("text/plain"), `${robots.status} ${robots.type}`);
check("robots.txt Allow 줄 0", !/^Allow:/im.test(robots.body));
const groups = robots.body.split(/\n(?=User-Agent:)/i).filter((g) => /^User-Agent:/im.test(g));
check(`robots.txt 그룹 ${1 + ROBOTS_AGENTS.length}개`, groups.length === 1 + ROBOTS_AGENTS.length, String(groups.length));
check("그룹마다 Disallow: /api/", groups.every((g) => /^Disallow: \/api\/$/m.test(g)));
for (const ua of ["*", ...ROBOTS_AGENTS]) check(`User-Agent: ${ua}`, new RegExp(`^User-Agent: ${ua.replace("*", "\\*")}$`, "m").test(robots.body));
check("Sitemap 줄 = canonical 과 같은 주소", new RegExp(`^Sitemap: ${ORIGIN.replace(/[.:/]/g, "\\$&")}/sitemap\\.xml$`, "m").test(robots.body));

const sm = await get("/sitemap.xml");
check("/sitemap.xml → 200 xml", sm.status === 200 && /xml/.test(sm.type), `${sm.status} ${sm.type}`);
const locUrls = [...sm.body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]));
check("sitemap 주소 = canonical 과 같은 곳", locUrls.length > 0 && locUrls.every((u) => u.origin === ORIGIN));
const locs = locUrls.map((u) => u.pathname);
check("sitemap = / · /licenses · /delete-account", locs.join(",") === "/,/licenses,/delete-account", locs.join(","));
for (const p of locs.slice(1)) {
  const r = await get(p);
  const canon = /<link rel="canonical" href="([^"]+)"/.exec(r.body);
  check(`${p} → 200 · canonical ${p}`, r.status === 200 && canon && new URL(canon[1]).pathname === p, canon?.[1]);
}

// ─── llms.txt · IndexNow 키 ────────────────────────────────────────────────────────────────
const llms = await get("/llms.txt");
check("/llms.txt → 200", llms.status === 200, String(llms.status));
check("llms.txt Content-Type = text/plain; charset=utf-8", llms.type === "text/plain; charset=utf-8", llms.type);
check("llms.txt Cache-Control s-maxage=3600", /s-maxage=3600/.test(llms.cache), llms.cache);
check("llms.txt 머리 = # 이름 · > 요약(한글 그대로)", llms.body.startsWith(`# 아잉체크 (aing-check)\n\n> ${LLMS_SUMMARY}\n`));
check("llms.txt 제목 = H1 · '## 링크' 둘뿐", llms.body.split("\n").filter((l) => /^#{1,6} /.test(l)).length === 2);
if (relJson) {
  const live = relJson.source === "github";
  check(`llms.txt 버전 ${live ? "있음" : "없음"}`, live ? llms.body.includes(`v${relJson.version}`) : !llms.body.includes(`v${relJson.version}`));
}

const key = await get(`/${INDEXNOW_KEY}.txt`);
check(`/${INDEXNOW_KEY}.txt → 200 · 내용 = 키`, key.status === 200 && key.body.trim() === INDEXNOW_KEY, String(key.status));

console.log(failed ? `\nseo-smoke: ${failed}건 실패 (${BASE})` : `\nseo-smoke: 모두 통과 (${BASE})`);
process.exit(failed ? 1 : 0);
