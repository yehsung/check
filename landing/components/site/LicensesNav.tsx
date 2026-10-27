import { DownloadCTA } from "@/components/ui/DownloadCTA";
import { GlassFx } from "@/components/glass/GlassFx";
import { MENUBAR_ROW, MENUBAR_SHELL, MenuBrand, MenuLinks, SkipLink } from "@/components/site/MenuBar";

// /licenses 의 유리 메뉴바(서버 컴포넌트). 첫 페이지 내비(SiteNav/NavShell)와 같은 조각·같은 자리(docs/v3/brief.md §4.2).
// 다른 점: sticky(문서 흐름 안), 메뉴 항목은 첫 페이지 앵커('/#…')로 돌아간다, 히어로가 없으니 다운로드는 늘 투명 유리.
// 앱 이름(BrandLink)은 여기서 '/' 로 간다. 굴절·스페큘러는 GlassFx(client 섬)가 붙인다.

export function LicensesNav() {
  return (
    <header className={`${MENUBAR_SHELL} sticky top-0 z-[var(--z-nav)]`}>
      <SkipLink />
      <nav aria-label="주요" className={MENUBAR_ROW}>
        <MenuBrand />
        <MenuLinks next />
        <div className="ml-auto flex items-center">
          <DownloadCTA placement="nav" size="s" tone="outline" label="다운로드" ariaLabel="Mac용 다운로드" />
        </div>
      </nav>
      <GlassFx specular refract level="thin" />
    </header>
  );
}

export default LicensesNav;
