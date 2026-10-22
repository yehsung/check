import Link from "next/link";
import { RenderImage } from "@/components/ui/RenderImage";
import { FOOTER_LINKS, type FooterLinkId } from "@/data/site-links";

// 푸터(docs/v3/brief.md §4.6 · §8, 서버 컴포넌트). 바탕 bg-deep(페이지에서 가장 깊은 곳) · 위 1px 선 · 작은 글.
// 좌우 시작 = --bar-pad(유리 메뉴바와 같은 선, 1440 → 40). desk: 왼쪽 앱 아이콘 + 한 줄 · 오른쪽 링크 줄 / 그 아래 저작권.
// tab: 한 줄 → 링크 3열 → 저작권 · phone: 한 줄 → 링크 가로 묶음(줄바꿈 — §9.4.8 · 누를 자리 44) → 저작권.
// "아잉체크(aing-check)" 는 페이지에서 여기 한 번만 쓴다. 이메일 주소는 넣지 않는다. 링크(이름·주소·순서)는 data/site-links 그대로.

export interface SiteFooterProps {
  /** 지금 보고 있는 페이지의 링크에 aria-current="page"(/licenses 에서 '글꼴 라이선스'). */
  current?: FooterLinkId;
}

/** §8 푸터 한 줄. */
const FOOTER_LINE = "아잉체크(aing-check)는 Mac 메뉴바 근무 타이머예요.";

// 누를 자리: tab 44×44 · phone 높이 44(가로 묶음이라 폭은 글자 + 사이 20px — 짧은 '지원' 뒤만 휑하지 않게). desk 는 한 줄 링크라 글자 높이 그대로
const LINK =
  "inline-flex min-h-11 items-center rounded-md text-ink-2 transition-colors duration-[var(--t-quick)] ease-linear tab:min-w-11 " +
  "hover:text-ink-1 motion-reduce:transition-none desk:min-h-6 desk:min-w-0";

export function SiteFooter({ current }: SiteFooterProps = {}) {
  return (
    <footer className="border-t border-white/[.07] bg-bg-deep">
      <div className="px-[var(--bar-pad)] pb-14 pt-10 desk:pb-12 desk:pt-10">
        <div className="desk:flex desk:items-center desk:justify-between desk:gap-10">
          <p className="t-small flex items-start gap-3 text-ink-2 desk:items-center">
            {/* 장식(바로 옆 글이 제품 이름을 말한다) — 빈 alt */}
            <RenderImage asset="brand/icon-64" widthPt={24} heightPt={24} alt="" className="-mt-px block size-6 shrink-0 desk:mt-0" />
            <span>{FOOTER_LINE}</span>
          </p>
          <ul
            role="list"
            className={
              "t-small mt-3 flex flex-wrap gap-x-5 tab:mt-4 " +
              "tab:grid tab:grid-cols-[repeat(3,max-content)] tab:gap-x-6 " +
              "desk:mt-0 desk:flex desk:flex-row desk:flex-wrap desk:justify-end desk:gap-x-6 desk:gap-y-2"
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
        </div>
        <p className="t-micro mt-5 text-ink-3 desk:mt-6">© 2026 아잉체크</p>
      </div>
    </footer>
  );
}

export default SiteFooter;
