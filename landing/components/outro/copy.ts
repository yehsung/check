// components/outro/copy.ts — 아웃트로 문장(SPEC v2 §S8, CB 글자 그대로). import 0 — node --test 가 그대로 읽는다(outro.test.ts).
//   H2(t-closing)  CB:280 「메뉴바에, 아잉 하나.」 — 줄바꿈은 쉼표 뒤(SPEC §1.4.2)
//   리드            CB:281
//   복사 버튼       CB:282 "brew 명령 복사"(누르면 ANNOUNCE.copied "복사했어요")

export const OUTRO = {
  title: ["메뉴바에,", "아잉 하나."],
  lead: "맥에 설치하고, 팀 코드를 나눠 주세요.",
  copyLabel: "brew 명령 복사",
} as const;
