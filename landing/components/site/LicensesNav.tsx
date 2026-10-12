import Link from "next/link";
import { DownloadCTA } from "@/components/ui/DownloadCTA";
import { RenderImage } from "@/components/ui/RenderImage";
import { NAV_LINKS } from "@/data/site-links";

// /licenses 의 내비 띠(서버 컴포넌트). 첫 페이지 내비(SPEC v2 §S0 — SiteNav/NavShell)와 같은 자리·글꼴·토큰으로 그린다:
// 높이 --nav-h(64 · phone 56) · 좌우 --gutter · [아이콘 24(phone 22) + 워드마크 t-wordmark] / 가운데 링크 3 / 오른쪽 CTA.
// 다른 점: 히어로가 없으니 늘 불투명(--bg-0) + 아랫변 --line, sticky. 워드마크는 첫 페이지로 돌아가는 링크(이 페이지엔 다른 길이 없다).
// 링크·CTA 는 첫 페이지의 앵커로 돌아간다(NAV_LINKS 가 '/#…', phone 의 '설치' = '/#install').

const NAV_LINK =
  "t-nav inline-flex h-11 items-center rounded-[var(--r-nav)] px-3 text-ink-2 " +
  "transition-colors duration-[var(--t-quick)] ease-linear hover:text-ink-1 motion-reduce:transition-none";

export function LicensesNav() {
  return (
    <header className="sticky top-0 z-[var(--z-nav)] h-[var(--nav-h)] border-b border-line bg-bg-0">
      <a
        href="#main"
        className={
          "t-button-s sr-only rounded-[var(--r-pill)] bg-surface-2 px-4 py-2 text-ink-1 " +
          // not-sr-only 는 padding 을 0 으로 되돌리고 globals 의 .sr-only(clip:rect(0,0,0,0))는 풀지 않는다 — 같은 focus: 묶음에서 다시 준다
          // (NavShell 과 같은 고침 — docs/v2/requests/core.md §2)
          "focus:not-sr-only focus:fixed focus:left-4 focus:top-2 focus:z-[var(--z-ultra)] focus:px-4 focus:py-2 focus:[clip:auto]"
        }
      >
        본문으로 건너뛰기
      </a>
      <nav aria-label="주요" className="grid h-full grid-cols-[1fr_auto_1fr] items-center px-[var(--gutter)]">
        <Link
          href="/"
          prefetch={false}
          aria-label="아잉체크 처음으로"
          className="col-start-1 inline-flex h-11 items-center gap-2 justify-self-start text-ink-1"
        >
          <RenderImage asset="brand/icon-64" widthPt={24} heightPt={24} alt="" eager className="block size-6 phone:size-[22px]" />
          <span className="t-wordmark">아잉체크</span>
        </Link>
        <ul role="list" className="col-start-2 flex items-center gap-2 phone:hidden">
          {NAV_LINKS.map((l) => (
            <li key={l.href}>
              <Link href={l.href} prefetch={false} className={NAV_LINK}>
                {l.label}
              </Link>
            </li>
          ))}
        </ul>
        {/* 첫 페이지와 같은 플랫폼 CTA(Mac용 다운로드 / iOS 는 App Store / phone 폭은 '설치') — 히어로가 없으니 테두리 그대로 */}
        <div className="col-start-3 flex items-center justify-self-end">
          <DownloadCTA placement="nav" size="s" tone="outline" installHref="/#install" />
        </div>
      </nav>
    </header>
  );
}

export default LicensesNav;
