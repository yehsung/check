'use client';
// components/site/NavShell.tsx — 첫 페이지 유리 메뉴바(docs/v3/brief.md §4.2)의 움직이는 부분. 스크롤 리스너 없음.
// - 늘 유리(thin) · 화면 맨 위 전폭 · fixed(스크롤해도 붙어 있고 숨지 않는다).
// - 가장자리 굴절(데스크톱 Chromium 만 — useRefraction) + 포인터 스페큘러(usePointerSpecular).
// - data-fill: 히어로 버튼 줄([data-hero-cta])이 메뉴바 뒤로 사라지면 → 다운로드 버튼을 투명 유리에서 보라 빛 유리로.
// - 오른쪽은 [다운로드] 하나(§9.2 — 상태 항목 03:45 은 지웠다). ≥768 은 설치 선택 창(§11 — Homebrew · DMG)을 열고,
//   폰(< 768)에선 그 버튼이 설치 절(#install)로 간다(DownloadCTA nav).
// SSR·첫 렌더 = 히어로 CTA 보임 가정(투명 유리) — 하이드레이션 뒤 IO 첫 콜백이 실제 값으로 고친다.
import { useRef } from 'react';
import type { ReactNode } from 'react';
import { DownloadCTA } from '@/components/ui/DownloadCTA';
import { useHeroCtaVisible } from '@/components/site/useHeroCtaVisible';
import { usePointerSpecular } from '@/components/glass/usePointerSpecular';
import { useRefraction } from '@/components/glass/useRefraction';
import { MENUBAR_ROW, MENUBAR_SHELL, SkipLink } from '@/components/site/MenuBar';
import type { ReleaseInfo } from '@/data/fixtures';

export interface NavShellProps {
  /** 왼쪽 앱 이름(서버에서 그린 MenuBrand) */
  brand: ReactNode;
  /** 메뉴 항목(서버에서 그린 MenuLinks) — phone 에서 숨는다 */
  links: ReactNode;
  /** 다운로드 선택 창의 DMG 메타(버전·크기) 출처 — 서버의 getRelease() */
  release?: ReleaseInfo;
}

export function NavShell({ brand, links, release }: NavShellProps) {
  const headerRef = useRef<HTMLElement>(null);
  const heroVisible = useHeroCtaVisible();
  usePointerSpecular(headerRef);
  useRefraction(headerRef, { level: 'thin' });

  return (
    <header
      ref={headerRef}
      data-nav=""
      data-fill={heroVisible ? undefined : ''}
      className={`${MENUBAR_SHELL} fixed inset-x-0 top-0 z-[var(--z-nav)]`}
    >
      <SkipLink />
      <nav aria-label="주요" className={MENUBAR_ROW}>
        {brand}
        {links}
        <div className="ml-auto flex items-center">
          <DownloadCTA placement="nav" size="s" tone={heroVisible ? 'outline' : 'fill'} label="다운로드" ariaLabel="Mac용 다운로드" release={release} />
        </div>
      </nav>
    </header>
  );
}

export default NavShell;
