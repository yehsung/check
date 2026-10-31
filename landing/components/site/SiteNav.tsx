// components/site/SiteNav.tsx — 첫 페이지 내비 = 유리 메뉴바(docs/v3/brief.md §4.2 · §8, 서버 컴포넌트).
// 움직이는 부분(굴절·스페큘러·다운로드 채움)은 NavShell(client). 조각은 MenuBar.tsx.
// 1440: [아이콘 20 · 아잉체크] 기능 · 설치 · 자주 묻는 질문 ……… [다운로드] — 높이 46, 좌우 --bar-pad(40). (v3.1: 상태 항목 03:45 삭제)
// 390: [아이콘 · 아잉체크] ……… [다운로드 → #install] — 높이 44(링크 숨김, 햄버거 없음).
import { NavShell } from '@/components/site/NavShell';
import { MenuBrand, MenuLinks } from '@/components/site/MenuBar';
import type { ReleaseInfo } from '@/data/fixtures';

/** release = 첫 페이지의 getRelease() — [다운로드] 선택 창의 DMG 메타(버전·크기)가 설치 카드와 같은 값이 되게(docs/v3/brief.md §11). */
export function SiteNav({ release }: { release?: ReleaseInfo } = {}) {
  return <NavShell brand={<MenuBrand />} links={<MenuLinks />} release={release} />;
}

export default SiteNav;
