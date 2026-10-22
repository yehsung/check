// node --experimental-strip-types --test components/outro/outro.test.ts
// 아웃트로 문장 계약(docs/v3/brief.md §8 '아웃트로' · §4.6): 글자 그대로 · H2 두 줄(쉼표 끊기 없음) · 금지어 0 · '근무 종료' 없음 ·
// 버튼 줄(Mac용 다운로드 · brew 알약 · App Store 배지)과 플랫폼 규칙(iOS 는 배지만)이 Outro.tsx 에 남아 있다.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { OUTRO } from "./copy.ts";

const BRIEF = readFileSync(new URL("../../docs/v3/brief.md", import.meta.url), "utf8");
const S8 = BRIEF.slice(BRIEF.indexOf("## 8."));
const outro = S8.slice(S8.indexOf("\n아웃트로"), S8.indexOf("\n푸터"));

/** 소스 계약용 — 주석을 걷어낸 본문. */
function code(path: string): string {
  return readFileSync(new URL(path, import.meta.url), "utf8")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'])\/\/.*$/gm, "$1")
    .replace(/\{\s*\}/g, "");
}

const FORBIDDEN = [
  "오픈소스", "판돈", "베팅", "내기", "걸고", "체험", "눌러 보세요", "Learn more", "더보기", "Mac 링크 보내기",
  "작은 팀", "작은 Mac", "AI 토큰 리밋", "서울", "부산", "소마", "마에스트로", "울찌", "열품타",
  "확인 메일", "이메일 인증", "일곱", "별점",
];

test("H2 = §8 두 줄 그대로(줄마다 <br>), 쉼표로 억지로 끊지 않는다", () => {
  assert.equal(OUTRO.title.length, 2);
  assert.ok(outro.includes(`H2: \`${OUTRO.title[0]}\` / \`${OUTRO.title[1]}\``), "§8 아웃트로 H2");
  for (const line of OUTRO.title) assert.ok(!/[,.]$/.test(line), `쉼표·마침표 끝 '${line}'`);
});

test("한 줄 = §8 글자 그대로(문장 하나)", () => {
  assert.ok(outro.includes(`한 줄: \`${OUTRO.lead}\``));
  assert.equal(OUTRO.lead.split(/[.!?]\s/).length, 1, "문장 하나");
});

test("버튼 글자 = §8 'Mac용 다운로드'", () => {
  assert.ok(outro.includes(`\`${OUTRO.cta}\``));
});

test("금지어 0 · '근무 종료' 0(아웃트로는 근무 상태가 아니다) · '누르다' 0", () => {
  const text = [...OUTRO.title, OUTRO.lead, OUTRO.cta].join("\n");
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
  assert.ok(!text.includes("근무 종료"));
  assert.ok(!/누르|눌러|누른/.test(text));
});

test("Outro.tsx: #outro · 넓은 벌(≥768·iOS 아님) = 다운로드 → brew 알약 → App Store 배지 · 폰·iOS 벌 = 배지 먼저 → Mac용 다운로드(설치 절) · 돔 없음", () => {
  const src = code("./Outro.tsx");
  assert.match(src, /id="outro"/);
  const narrowAt = src.indexOf('placement="outro-phone"');
  assert.ok(narrowAt > 0, "폰·iOS 벌");
  const wide = src.slice(0, src.lastIndexOf("<div", narrowAt));
  const narrow = src.slice(src.lastIndexOf("<div", narrowAt));
  const dl = wide.indexOf("<DownloadCTA");
  const brew = wide.indexOf("<BrewPill");
  const badge = wide.indexOf("<AppStoreBadge");
  assert.ok(dl > 0 && brew > dl && badge > brew, "§8 순서(넓은 벌): Mac용 다운로드 · brew 알약 · App Store 배지");
  assert.match(wide, /<DownloadCTA[^>]*placement="outro"/);
  assert.match(wide, /<div className="[^"]*hidden[^"]*tab:flex[^"]*desk:flex[^"]*\[html\[data-platform=ios\]_&\]:hidden/, "넓은 벌은 ≥768 · iOS 아님");
  assert.ok(narrow.indexOf("<AppStoreBadge") < narrow.indexOf("LINKS.install"), "§9.4.4: 폰은 배지가 먼저(히어로와 같은 순서)");
  assert.ok(!/<BrewPill/.test(narrow), "폰엔 brew 알약 없음(한 줄에 안 들어간다 — §9.4.3)");
  assert.match(narrow, /tab:hidden[^"]*desk:hidden[^"]*\[html\[data-platform=ios\]_&\]:flex/, "폰 폭 · iOS 기기");
  assert.ok(!/\bDome\b/.test(src), "돔(큰 원) 금지");
});

test("OutroStage.tsx: 아잉 idle(포스터 aing-idle-poster) · 등장 페이드 없음", () => {
  const src = code("./OutroStage.tsx");
  assert.match(src, /<AingClip[\s\S]*?poster="char\/aing-idle-poster"/);
  assert.ok(!/data-shown|opacity/.test(src), "절 등장 연출(페이드)을 걸지 않는다 — 첫 페인트에 글이 다 보인다");
});

test("푸터 한 줄 = §8 글자 그대로 · '작은 팀' 류 0 · OG alt 도 새 히어로를 말한다", () => {
  const footer = code("../site/SiteFooter.tsx");
  const m = /FOOTER_LINE = "([^"]+)"/.exec(footer);
  assert.ok(m, "SiteFooter 의 FOOTER_LINE");
  assert.ok(S8.includes(`푸터: \`${m[1]}\``), "§8 푸터 한 줄");
  assert.match(footer, /\{FOOTER_LINE\}/, "화면에 그 한 줄");
  const alt = readFileSync(new URL("../../app/opengraph-image.alt.txt", import.meta.url), "utf8");
  for (const s of [footer, alt]) assert.ok(!/작은 (Mac )?팀/.test(s), "'작은 팀' 표현 금지(§8)");
  assert.ok(!/돔/.test(alt), "OG alt 가 v2 돔 그림을 말하지 않는다");
  assert.ok(alt.includes("메뉴바에서 바로 켜는 근무 타이머"), "OG alt = 새 히어로 H1");
});
