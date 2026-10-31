// node --experimental-strip-types --test components/faq/faq.test.ts
// FAQ 의 사실 계약(docs/v3/brief.md §8 '자주 묻는 질문' · §4.6): 5문항이 §8 의 1–5번과 글자·순서까지 같다 · 제목 = §8 H2(= 내비 이름) ·
// 화면 데이터 = JSON-LD(같은 문장 5개) · #faq-1…#faq-5 · JS 없이 열리는 <details>/<summary> · 금지어 0.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { FAQ_ITEMS, faqId, faqJsonLd } from "../../data/faq-items.ts";
import { ANDROID_COPY } from "../../data/install-copy.ts";
import { FAQ_TITLE } from "./copy.ts";
import { jsonLdHtml } from "./jsonld.ts";

const BRIEF = readFileSync(new URL("../../docs/v3/brief.md", import.meta.url), "utf8");
const S8 = BRIEF.slice(BRIEF.indexOf("## 8."));
const faqBlock = S8.slice(S8.indexOf("\n자주 묻는 질문(#faq)"), S8.indexOf("\n아웃트로"));
const navLine = S8.split("\n").find((l) => l.startsWith("내비")) ?? "";

/** §8 의 번호 목록 `n. \`질문\` — \`답\`` → { q, a }. */
function briefFaq(): { q: string; a: string }[] {
  const out: { q: string; a: string }[] = [];
  for (const line of faqBlock.split("\n")) {
    const m = /^\d+\.\s+`(.+?)`\s+—\s+`(.+)`\s*$/.exec(line);
    if (m) out.push({ q: m[1], a: m[2] });
  }
  return out;
}

/** 소스 계약용 — 주석을 걷어낸 본문(설명을 지워야만 초록이 되는 일이 없게). */
function code(path: string): string {
  return readFileSync(new URL(path, import.meta.url), "utf8")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'])\/\/.*$/gm, "$1")
    .replace(/\{\s*\}/g, "");
}

// 금지어(히어로 copy.test 와 같은 결 + v2 수용 테스트 목록에서 지금도 유효한 것). '클릭' 규칙·'잔디' 규칙도 여기서 본다.
const FORBIDDEN = [
  "오픈소스", "판돈", "베팅", "내기", "걸고", "체험", "눌러 보세요", "Learn more", "더보기", "Mac 링크 보내기",
  "작은 팀", "작은 Mac", "AI 토큰 리밋", "서울", "부산", "소마", "마에스트로", "울찌", "열품타",
  "확인 메일", "이메일 인증", "일곱", "별점", "격자", "센터",
];

test("FAQ 5문항이 §8 의 1–5번과 글자까지 같다(순서 포함)", () => {
  const brief = briefFaq();
  assert.equal(brief.length, 5, "§8 FAQ 는 5문항");
  assert.equal(FAQ_ITEMS.length, 5);
  FAQ_ITEMS.forEach((it, i) => {
    assert.equal(it.q, brief[i].q, `${i + 1}번 질문`);
    assert.equal(it.a, brief[i].a, `${i + 1}번 답`);
  });
});

test("2번 답 맨 끝 = 안드로이드 베타 한 문장(§12 · ANDROID_COPY.faqTail) — 앞 문장은 그대로 · JSON-LD 도 따라간다", () => {
  const a = FAQ_ITEMS[1].a;
  assert.equal(FAQ_ITEMS[1].q, "어떤 기기와 OS에서 쓸 수 있나요?");
  assert.equal(ANDROID_COPY.faqTail, "안드로이드에서도 베타로 쓸 수 있어요.");
  assert.ok(a.endsWith(` ${ANDROID_COPY.faqTail}`), "맨 끝에 공백 하나 + 문장");
  assert.equal(
    a,
    "macOS 14 이상 맥이면 Apple Silicon·Intel 모두 돼요. 아이폰은 iOS 18 이상이에요. 근무 시작·종료는 맥에서 하고, 아이폰에선 현황·메시지·할 일·게임을 써요. 안드로이드에서도 베타로 쓸 수 있어요.",
  );
  assert.equal(a.split(ANDROID_COPY.faqTail).length, 2, "한 번만");
  // 다른 문항에는 안드로이드 문장이 없다 · 최소 OS 버전을 지어내지 않는다
  FAQ_ITEMS.forEach((it, i) => i !== 1 && assert.ok(!it.a.includes("안드로이드"), `${i + 1}번`));
  assert.ok(!/안드로이드 ?\d|Android ?\d/.test(a), "안드로이드 버전 숫자 0");
  assert.equal(faqJsonLd().mainEntity[1].acceptedAnswer.text, a);
});

test("제목 = §8 H2 「자주 묻는 질문」 한 줄 · 내비 링크 이름과 같다", () => {
  assert.deepEqual([...FAQ_TITLE], ["자주 묻는 질문"]);
  assert.ok(faqBlock.includes(`H2 \`${FAQ_TITLE[0]}\``), "§8 FAQ H2");
  assert.ok(navLine.includes(`\`${FAQ_TITLE[0]}\``), "§8 내비 이름");
});

test("문항 앵커는 #faq-1 … #faq-5", () => {
  assert.deepEqual(
    FAQ_ITEMS.map((_, i) => faqId(i + 1)),
    ["faq-1", "faq-2", "faq-3", "faq-4", "faq-5"],
  );
});

test("JSON-LD: FAQPage · 질문 5개 · 화면 문장과 같다 · '<' 가 본문에 날것으로 없다", () => {
  const data = faqJsonLd();
  const html = jsonLdHtml(data);
  assert.ok(!html.includes("<"), "'<' 는 \\u003c 로 바뀐다");
  const parsed = JSON.parse(html);
  assert.deepEqual(parsed, data);
  assert.equal(parsed["@type"], "FAQPage");
  assert.equal(parsed.mainEntity.length, 5);
  parsed.mainEntity.forEach((q: { "@type": string; name: string; acceptedAnswer: { text: string } }, i: number) => {
    assert.equal(q["@type"], "Question");
    assert.equal(q.name, FAQ_ITEMS[i].q);
    assert.equal(q.acceptedAnswer.text, FAQ_ITEMS[i].a);
  });
});

test("jsonLdHtml 은 '</script>' 를 깨뜨리지 못하게 한다", () => {
  const html = jsonLdHtml({ x: "</script><b>" });
  assert.ok(!html.includes("</script>"));
  assert.deepEqual(JSON.parse(html), { x: "</script><b>" });
});

test("FAQ 문장에 금지어 0 · 맥 동작은 '클릭'(누르다 0)", () => {
  const text = [...FAQ_TITLE, ...FAQ_ITEMS.flatMap((it) => [it.q, it.a])].join("\n");
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
  assert.ok(!/누르|눌러|누른/.test(text), "'누르다' 대신 '클릭'");
});

test("Faq.tsx: #faq 절 · <details name=\"faq\"> + <summary>(JS 없이 열림) · 문항 id 는 faqId · JSON-LD 는 같은 데이터", () => {
  const src = code("./Faq.tsx");
  assert.match(src, /id="faq"/, "내비가 링크하는 #faq");
  assert.match(src, /<details[\s\S]*?name="faq"/, "네이티브 details 그룹(FaqHash 가 찾는 이름)");
  assert.match(src, /id=\{faqId\(i \+ 1\)\}/, "문항 앵커");
  assert.match(src, /<summary/, "summary");
  assert.match(src, /FAQ_ITEMS\.map/, "화면 = 데이터");
  assert.match(src, /jsonLdHtml\(faqJsonLd\(\)\)/, "JSON-LD = 같은 데이터");
  assert.match(src, /<FaqHash\s*\/>/, "딥링크 보험");
});
