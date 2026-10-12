// node --experimental-strip-types --test components/outro/outro.test.ts
// 아웃트로 문장 계약(SPEC v2 §S8 · §1.4): CB:280–282 글자 그대로 · H2 두 줄(쉼표 뒤) · 금지어 0 · '근무 종료' 없음(D3).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { OUTRO } from "./copy.ts";

const CB = readFileSync(new URL("../../docs/content-brief.md", import.meta.url), "utf8");
const cbLine = (n: number) => CB.split("\n")[n - 1] ?? "";

const FORBIDDEN = [
  "오픈소스", "판돈", "베팅", "걸고", "서울", "부산", "소마", "마에스트로", "울찌", "열품타", "경고 없이",
  "확인 메일", "이메일 인증", "일곱", "별점", "Learn more", "더보기", "눌러 보세요", "체험", "Mac 링크 보내기", "Gemini",
];

test("H2 = CB:280 「메뉴바에, 아잉 하나.」, 줄바꿈은 쉼표 뒤 한 번", () => {
  assert.deepEqual([...OUTRO.title], ["메뉴바에,", "아잉 하나."]);
  assert.ok(cbLine(280).includes(`「${OUTRO.title.join(" ")}」`), "CB:280 에 같은 문장");
});

test("리드 = CB:281", () => {
  assert.ok(cbLine(281).includes(`"${OUTRO.lead}"`));
});

test("복사 버튼 이름 = CB:282 의 'brew 명령 복사'", () => {
  assert.ok(cbLine(282).includes(OUTRO.copyLabel));
});

test("금지어 0 · '근무 종료' 0(아웃트로는 근무 상태가 아니다)", () => {
  const text = [...OUTRO.title, OUTRO.lead, OUTRO.copyLabel].join("\n");
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
  assert.ok(!text.includes("근무 종료"));
});
