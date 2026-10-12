import Link from "next/link";
import { RenderImage } from "@/components/ui/RenderImage";
import { FOOTER_LINKS, type FooterLinkId } from "@/data/site-links";

// 푸터(SPEC v2 §S9, 서버 컴포넌트 — v1 S14 구조 그대로, v2 토큰으로).
// 바탕 --bg-outro(아웃트로와 이어진다) · 위 --line 1px · 패딩 위 48(phone 40)·아래 64 · 왼쪽 시작 = --gutter(내비·FAQ 와 같은 선, 1440 → 176).
// 왼쪽 앱 아이콘 24px + 한 줄 → 링크 줄(desk 한 줄 · tab 3열 · phone 세로 목록) → 저작권.
// "아잉체크(aing-check)" 는 페이지에서 여기 한 번만 쓴다(SPEC §1.4). 이메일 주소는 넣지 않는다.

export interface SiteFooterProps {
  /** 지금 보고 있는 페이지의 링크에 aria-current="page"(/licenses 에서 '글꼴 라이선스'). */
  current?: FooterLinkId;
}

// 누를 자리 44×44(SPEC §4 — '지원' 23px·'GitHub' 42px 폭도 44 로, review-perf-a11y P2-5). desk 는 한 줄 링크라 글자 크기 그대로
const LINK =
  "inline-flex min-h-11 min-w-11 items-center text-ink-2 transition-colors duration-[var(--t-quick)] ease-linear " +
  "hover:text-ink-1 motion-reduce:transition-none desk:min-h-6 desk:min-w-0";

export function SiteFooter({ current }: SiteFooterProps = {}) {
  return (
    <footer className="border-t border-line bg-bg-outro">
      <div className="px-[var(--gutter)] pb-16 pt-12 phone:pt-10">
        <p className="t-small flex items-start gap-3 text-ink-2">
          {/* 장식(바로 옆 글이 제품 이름을 말한다) — 빈 alt */}
          <RenderImage asset="brand/icon-64" widthPt={24} heightPt={24} alt="" className="-mt-px block size-6 shrink-0" />
          <span>아잉체크(aing-check)는 작은 Mac 팀을 위한 메뉴바 근무 타이머예요.</span>
        </p>
        <ul
          role="list"
          className={
            "t-micro mt-4 flex flex-col " +
            "tab:grid tab:grid-cols-[repeat(3,max-content)] tab:gap-x-6 " +
            "desk:mt-5 desk:flex desk:flex-row desk:flex-wrap desk:gap-x-6 desk:gap-y-2"
          }
        >
          {FOOTER_LINKS.map((l) => (
            <li key={l.id}>
              {l.href.startsWith("/") ? (
                // 안쪽 페이지(/licenses)는 Link — 미리 받기는 끈다(첫 페이지 전송 예산)
                <Link href={l.href} prefetch={false} className={LINK} aria-current={current === l.id ? "page" : undefined}>
                  {l.label}
                </Link>
              ) : (
                // 바깥 주소(지원·처리방침·약관·GitHub·이슈)는 새 탭
                <a href={l.href} target="_blank" rel="noopener noreferrer" className={LINK}>
                  {l.label}
                </a>
              )}
            </li>
          ))}
        </ul>
        <p className="t-micro mt-5 text-ink-3 desk:mt-6">© 2026 아잉체크</p>
      </div>
    </footer>
  );
}

export default SiteFooter;
