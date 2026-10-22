import Link from "next/link";
import { RenderImage } from "@/components/ui/RenderImage";
import { NAV_LINKS } from "@/data/site-links";
import { BrandLink } from "@/components/site/BrandLink";

// components/site/MenuBar.tsx — 유리 메뉴바(docs/v3/brief.md §4.2 · §9.2)의 조각들(서버·클라 어디서나, 훅 없음).
// 첫 페이지(SiteNav → NavShell)와 /licenses(LicensesNav)가 같은 조각을 쓴다.
// macOS 메뉴바처럼: 왼쪽 [앱 아이콘 + 아잉체크(굵게)] 기능 · 설치 · 자주 묻는 질문(13.5px 메뉴 항목) · 오른쪽 [다운로드] 하나.
// v3.1(§9.2): 오른쪽 상태 항목(아잉 아이콘 + 03:45)은 지웠다. 앱 이름은 어디서나 '처음으로' 링크(BrandLink). 애플 로고 없음.
// 390: 아이콘 + 이름 · [다운로드] 만(링크 숨김).

/** 메뉴바 안쪽 줄(좌우 --bar-pad = 히어로 팝오버 오른쪽 끝과 같은 선). */
export const MENUBAR_ROW = "flex h-full items-center gap-1 px-[var(--bar-pad)]";

/** 유리 메뉴바 껍데기 클래스(thin 유리 + 메뉴바 보정). position 은 부르는 쪽이 준다. */
export const MENUBAR_SHELL = "glass glass--thin menubar h-[var(--nav-h)]";

export function SkipLink() {
  return (
    <a
      href="#main"
      className={
        "gbtn gbtn--glass gbtn--s sr-only " +
        // .sr-only(clip) 를 focus 때 같은 묶음 안에서 푼다(not-sr-only 는 clip 을 풀지 않는다 — v2 실측)
        "focus:not-sr-only focus:fixed focus:left-4 focus:top-2 focus:z-[var(--z-ultra)] focus:h-8 focus:px-4 focus:[clip:auto]"
      }
    >
      본문으로 건너뛰기
    </a>
  );
}

/**
 * 왼쪽 앱 이름 = '처음으로' 링크(§9.2). 첫 페이지에서는 맨 위로 스크롤 · 주소의 # 지우기 · 포커스를 문서 맨 앞으로(BrandLink 가 직접),
 * 다른 경로(/licenses)에서는 '/' 로 간다.
 */
export function MenuBrand() {
  return (
    <BrandLink className="mr-2 inline-flex h-11 shrink-0 items-center gap-2 pl-0.5 pr-1 text-ink-1">
      {/* 장식(바로 옆 글이 제품 이름을 말한다) — 빈 alt */}
      <RenderImage asset="brand/icon-64" widthPt={20} heightPt={20} alt="" eager className="block size-5" />
      <span className="t-wordmark">아잉체크</span>
    </BrandLink>
  );
}

/** 메뉴 항목 셋(NAV_LINKS). next=true 면 next/link(/licenses 에서 첫 페이지 앵커로). phone 에서 숨는다. */
export function MenuLinks({ next = false }: { next?: boolean }) {
  return (
    <ul role="list" className="flex items-center gap-0.5 phone:hidden">
      {NAV_LINKS.map((l) => (
        <li key={l.href}>
          {next ? (
            <Link href={l.href} prefetch={false} className="menu-item t-nav">
              {l.label}
            </Link>
          ) : (
            <a href={l.href} className="menu-item t-nav">
              {l.label}
            </a>
          )}
        </li>
      ))}
    </ul>
  );
}
