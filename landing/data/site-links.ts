import { LINKS } from "@/data/fixtures";

// 푸터 링크 6개(SPEC S14). 순서·문구 그대로, 화면에는 가운뎃점 없이 간격으로만 잇는다.
// '버그·요청' 의 가운뎃점은 링크 이름 속 한국어 문장 부호다(구분자가 아니다).
export const FOOTER_LINKS = [
  { id: "support", label: "지원", href: LINKS.support },
  { id: "privacy", label: "개인정보 처리방침", href: LINKS.privacy },
  { id: "terms", label: "이용약관", href: LINKS.terms },
  { id: "github", label: "GitHub", href: LINKS.github },
  { id: "issues", label: "버그·요청", href: LINKS.issues },
  { id: "licenses", label: "글꼴 라이선스", href: LINKS.licenses },
] as const;

export type FooterLinkId = (typeof FOOTER_LINKS)[number]["id"];

// 내비 링크 셋(docs/v3/brief.md §8 — v2 SPEC §S0 · DECISIONS D12 에서). 첫 페이지 내비(SiteNav)와 /licenses 내비(LicensesNav)가 같이 쓴다.
// 경로를 '/#…' 로 둬서 /licenses 에서도 첫 페이지의 앵커로 돌아간다.
export const NAV_LINKS = [
  { href: "/#f-timer", label: "기능" },
  { href: "/#install", label: "설치" },
  { href: "/#faq", label: "자주 묻는 질문" },
] as const;
