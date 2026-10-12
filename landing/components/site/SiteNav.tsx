// components/site/SiteNav.tsx — 첫 페이지 내비(SPEC v2 §S0, 서버 컴포넌트). 움직이는 부분(배경·CTA 채움)은 NavShell(client).
// 1440: 176 [아이콘 24] 아잉체크 · 가운데 기능 / 설치 / 자주 묻는 것 · 오른쪽 Mac용 다운로드(1264) — 높이 64.
// 390: 20 [아이콘 22] 아잉체크 · 링크 숨김(햄버거 없음) · CTA — 높이 56. 메뉴바 라벨·활성 섹션 하이라이트는 두지 않는다.
import { NavShell } from '@/components/site/NavShell';
import { RenderImage } from '@/components/ui/RenderImage';
import { NAV_LINKS } from '@/data/site-links';

const LINK =
  't-nav inline-flex h-11 items-center rounded-[var(--r-nav)] px-3 text-ink-2 ' +
  'transition-colors duration-[var(--t-quick)] ease-linear hover:text-ink-1 motion-reduce:transition-none phone:hidden';

export function SiteNav() {
  return (
    <NavShell
      brand={
        <span className="col-start-1 inline-flex items-center gap-2 justify-self-start text-ink-1">
          {/* 장식(바로 옆 글이 제품 이름을 말한다) — 빈 alt */}
          <RenderImage asset="brand/icon-64" widthPt={24} heightPt={24} alt="" className="block size-6 phone:size-[22px]" />
          <span className="t-wordmark">아잉체크</span>
        </span>
      }
      links={
        <ul role="list" className="col-start-2 flex items-center gap-2 phone:hidden">
          {NAV_LINKS.map((l) => (
            <li key={l.href} className="phone:hidden">
              <a href={l.href} className={LINK}>
                {l.label}
              </a>
            </li>
          ))}
        </ul>
      }
    />
  );
}

export default SiteNav;
