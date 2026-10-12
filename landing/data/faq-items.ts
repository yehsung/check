// FAQ 5문항(brief-v21 §2 — CB §7 의 1–5번(CB:254–263) 문장 그대로, 순서대로. components/faq/faq.test.ts 가 CB 와 글자까지 맞춰 본다).
// v2 의 6–10번(데이터 저장·자동 근무 시작·근무 종료 깜빡·계정 삭제·AI 리밋 로그인)은 v2.1 에서 뺐다(글을 줄인다 — 사용자 원문).
// 화면(<details>)과 FAQPage JSON-LD 가 이 한 곳에서 읽는다. import 0(node --test 가 그대로 읽는다).
// 센터 문항은 싣지 않는다(DECISIONS §1 v1 §8). 문장을 바꾸려면 content-brief → SPEC 부터 고친다.

export type FaqItem = { readonly q: string; readonly a: string };

export const FAQ_ITEMS: readonly FaqItem[] = [
  {
    q: "요금이 있나요?",
    a: "무료예요. 앱 안에서 현금 결제를 받지 않고, 루비는 일하거나 게임해서 모으는 앱 안 재화라 현금으로 사거나 바꿀 수 없어요.",
  },
  {
    q: "어떤 기기에서 쓰나요?",
    a: "맥은 macOS 14 이상이면 Apple Silicon·Intel 모두 돼요. 아이폰은 iOS 18 이상이에요. 근무 시작·종료는 맥에서 하고, 아이폰에서는 현황·메시지·할 일·게임을 써요.",
  },
  {
    q: "팀 코드는 어디서 받나요?",
    a: "이미 쓰는 팀원에게 받아요. 팀원 누구나 팀 카드의 열쇠 버튼에서 코드를 보고 복사할 수 있어요. 팀이 없으면 가입할 때 '새 팀 만들기'를 누르면 코드가 바로 생겨요. 공개된 팀 목록은 없어요.",
  },
  {
    q: "화면이나 키 입력을 보나요?",
    a: "아니요. 스크린샷·키보드 입력·마우스 움직임·앱과 웹 사용 기록을 모으지 않고, 손쉬운 사용·화면 기록·카메라·마이크·위치 권한도 요청하지 않아요. 근무 중에만 '마지막으로 키·클릭·스크롤을 한 시각' 하나를 보내요.",
  },
  {
    q: "누가 내 근무 시간을 보나요?",
    a: "근무 시작·종료 시각과 근무 기록은 같은 팀 안에서만 보여요. 콕 찌르기 목록·AI 토큰 순위판·미니게임 순위표는 앱을 쓰는 모두가 보는 화면이라 별명·아바타·지금 근무 중인지가 보여요. 토큰과 미니게임은 설정에서 비공개로 바꿀 수 있어요.",
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
