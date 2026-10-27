// components/outro/copy.ts — 아웃트로 문장(docs/v3/brief.md §8 '아웃트로' 글자 그대로). import 0 — node --test 가 그대로 읽는다(outro.test.ts).
//   H2   두 줄(줄마다 <br>) — 쉼표로 억지로 끊지 않는다
//   lead 한 줄(문장 하나)
//   버튼 줄은 Mac용 다운로드(DownloadCTA 기본 글자) · brew 알약(BrewPill — 복사 → 복사했어요, 접근 이름 'brew 설치 명령 복사') · App Store 배지

export const OUTRO = {
  title: ["가볍게 설치하고", "팀원들과 바로 시작해요"],
  lead: "가입할 때 새 팀을 만들거나 전달받은 팀 코드를 넣으면 곧바로 함께 쓸 수 있어요.",
  cta: "Mac용 다운로드",
} as const;
