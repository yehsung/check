// FAQ 5문항(docs/v3/brief.md §8 '자주 묻는 질문' — 글자 그대로, 순서대로. components/faq/faq.test.ts 가 §8 과 글자까지 맞춰 본다).
// 화면(<details>)과 FAQPage JSON-LD 가 이 한 곳에서 읽는다. import 0(node --test 가 그대로 읽는다).
// 센터 문항은 싣지 않는다. 문장을 바꾸려면 brief §8 부터 고친다.

export type FaqItem = { readonly q: string; readonly a: string };

export const FAQ_ITEMS: readonly FaqItem[] = [
  {
    q: "정말 무료로 쓸 수 있나요?",
    a: "네, 무료예요. 앱 안의 루비는 일하거나 게임하면서 모으는 재화라 돈으로 사거나 바꿀 수 없어요.",
  },
  {
    q: "어떤 기기와 OS에서 쓸 수 있나요?",
    a: "macOS 14 이상 맥이면 Apple Silicon·Intel 모두 돼요. 아이폰은 iOS 18 이상이에요. 근무 시작·종료는 맥에서 하고, 아이폰에선 현황·메시지·할 일·게임을 써요. 안드로이드에서도 베타로 쓸 수 있어요.",
  },
  {
    q: "우리 팀에는 어떻게 합류하나요?",
    a: "팀원에게 팀 코드를 받아 가입할 때 넣으면 돼요. 코드는 팀 카드의 열쇠 버튼에서 누구나 복사할 수 있어요. 팀이 없으면 가입할 때 '새 팀 만들기'를 선택하면 바로 생겨요.",
  },
  {
    q: "화면이나 키 입력도 기록하나요?",
    a: "아니요. 스크린샷·키 입력·마우스 움직임·앱 사용 기록을 모으지 않고, 화면 기록·손쉬운 사용 권한도 요청하지 않아요. 근무 중에만 마지막 입력(키·클릭·스크롤) 시각 하나만 보내요.",
  },
  {
    q: "내가 일한 시간은 누가 볼 수 있나요?",
    a: "근무 기록은 같은 팀 안에서만 보여요. 콕 찌르기 목록·AI 토큰 순위판·미니게임 순위표는 앱을 쓰는 모두에게 열려 별명·아바타·근무 여부가 표시되고, 토큰과 미니게임은 설정에서 비공개로 바꿀 수 있어요.",
  },
];

/** 문항 n(1부터)의 앵커 id — #faq-1 … #faq-5. */
export const faqId = (n: number): string => `faq-${n}`;

/** FAQPage 구조화 데이터(schema.org). 질문·답은 화면 문장과 같은 출처. */
export function faqJsonLd(items: readonly FaqItem[] = FAQ_ITEMS) {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: items.map((it) => ({
      "@type": "Question",
      name: it.q,
      acceptedAnswer: { "@type": "Answer", text: it.a },
    })),
  };
}
