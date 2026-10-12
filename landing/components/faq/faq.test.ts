// node --experimental-strip-types --test components/faq/faq.test.ts
// FAQ 의 사실 계약(SPEC v2 §S7 · §1.4 · brief-v21 §2): 5문항이 CB §7 의 1–5번(CB:254–263)과 글자·순서까지 같다 · 제목 = CB:252 ·
// JSON-LD 가 같은 문장 5개 · 금지어 0.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { FAQ_ITEMS, faqId, faqJsonLd } from "../../data/faq-items.ts";
import { FAQ_TITLE } from "./copy.ts";
import { jsonLdHtml } from "./jsonld.ts";

const CB = readFileSync(new URL("../../docs/content-brief.md", import.meta.url), "utf8");

/** CB §7 의 번호 목록 → { q, a }. 답 줄 끝의 ' — 출처' 는 뗀다. '예비' 줄에서 멈춘다. */
function cbFaq(): { q: string; a: string }[] {
  const lines = CB.split("\n");
  const start = lines.findIndex((l) => l.startsWith("## 7. FAQ"));
  assert.ok(start >= 0, "content-brief.md 에 '## 7. FAQ' 절이 있다");
  const out: { q: string; a: string }[] = [];
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith("예비") || line.startsWith("## ")) break;
    const m = /^\s*\d+\.\s+\*\*(.+?)\*\*\s*$/.exec(line);
    if (!m) continue;
    const answer = (lines[i + 1] ?? "").trim().split(" — ")[0];
    out.push({ q: m[1], a: answer });
  }
  return out;
}

// SPEC v2 §1.4.1 금지어(수용 테스트 T4 와 같은 목록).
const FORBIDDEN = [
  "오픈소스", "판돈", "베팅", "걸고", "서울", "부산", "소마", "마에스트로", "울찌", "열품타", "경고 없이",
  "확인 메일", "이메일 인증", "일곱", "별점", "Learn more", "더보기", "눌러 보세요", "체험", "Mac 링크 보내기", "Gemini",
];

test("FAQ 5문항이 CB §7 의 1–5번(CB:254–263)과 글자까지 같다(순서 포함 — brief-v21 §2)", () => {
  const cb = cbFaq();
  assert.equal(cb.length, 10, "CB §7 원본은 10문항 그대로");
  assert.equal(FAQ_ITEMS.length, 5);
  assert.deepEqual(
    FAQ_ITEMS.map((it) => it.q),
    ["요금이 있나요?", "어떤 기기에서 쓰나요?", "팀 코드는 어디서 받나요?", "화면이나 키 입력을 보나요?", "누가 내 근무 시간을 보나요?"],
  );
  FAQ_ITEMS.forEach((it, i) => {
    assert.equal(it.q, cb[i].q, `${i + 1}번 질문`);
    assert.equal(it.a, cb[i].a, `${i + 1}번 답`);
  });
});

test("제목은 CB:252 의 「자주 묻는 것.」 한 줄", () => {
  assert.deepEqual([...FAQ_TITLE], ["자주 묻는 것."]);
  assert.ok(CB.includes("「자주 묻는 것.」"));
});

test("문항 앵커는 #faq-1 … #faq-5", () => {
  assert.equal(faqId(1), "faq-1");
  assert.equal(faqId(3), "faq-3");
  assert.equal(faqId(5), "faq-5");
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

test("FAQ 문장에 금지어 0(SPEC §1.4.1) · 센터 문항 없음", () => {
  const text = [...FAQ_TITLE, ...FAQ_ITEMS.flatMap((it) => [it.q, it.a])].join("\n");
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
  assert.ok(!text.includes("센터"), "센터 문항은 싣지 않는다(DECISIONS §1 v1 §8)");
});
