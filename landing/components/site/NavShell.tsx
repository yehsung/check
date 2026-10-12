'use client';
// components/site/NavShell.tsx — 내비 띠의 움직이는 부분(SPEC v2 §S0). 스크롤 리스너 없음(DECISIONS D7).
// - data-scrolled: 문서 맨 위 8px 센티널(IO)이 화면에서 벗어나면(scrollY > 8) 붙는다 → bg-0/78% + blur 14px + 아랫변 --line(200ms 선형).
// - data-fill: 히어로 버튼 줄([data-hero-cta])이 내비 뒤로 사라지면 붙는다(useHeroCtaVisible) → 내비 CTA 를 라벤더 채움으로.
// SSR·첫 렌더는 둘 다 없음(scrollY 0 · 히어로 CTA 보임 가정) — 서버와 같은 마크업으로 하이드레이션하고, IO 첫 콜백이 실제 값으로 고친다.
// 감속 모션: 배경 전이 0ms(motion-reduce:transition-none).
import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { DownloadCTA } from '@/components/ui/DownloadCTA';
import { useHeroCtaVisible } from '@/components/site/useHeroCtaVisible';

export interface NavShellProps {
  /** 왼쪽 워드마크(서버에서 그린 아이콘 + '아잉체크'). 링크가 아니다 — 허용 인터랙션 목록(SPEC §1.5) 밖이라. */
  brand: ReactNode;
  /** 가운데 링크 목록(서버에서 그린 NAV_LINKS). phone 에서 숨는다. */
  links: ReactNode;
}

export function NavShell({ brand, links }: NavShellProps) {
  const sentinelRef = useRef<HTMLDivElement>(null);
  const [scrolled, setScrolled] = useState(false);
  const fill = !useHeroCtaVisible();

  useEffect(() => {
    const el = sentinelRef.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver(
      (entries) => {
        const en = entries[entries.length - 1];
        if (en) setScrolled(!en.isIntersecting);
      },
      { threshold: 0 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <>
      {/* 문서 맨 위(초기 포함 블록 기준) 1×8px — html·body 는 위치 지정이 없어 문서 y 0 에 붙는다 */}
      <div ref={sentinelRef} aria-hidden="true" data-nav-sentinel="" className="pointer-events-none absolute left-0 top-0 h-2 w-px" />
      <header
        data-nav=""
        data-scrolled={scrolled ? '' : undefined}
        data-fill={fill ? '' : undefined}
        className={
          'fixed inset-x-0 top-0 z-[var(--z-nav)] h-[var(--nav-h)] border-b border-transparent bg-transparent ' +
          'transition-[background-color,border-color,backdrop-filter] duration-[var(--t-resize)] ease-linear motion-reduce:transition-none ' +
          'data-[scrolled]:border-line data-[scrolled]:bg-bg-0/78 data-[scrolled]:backdrop-blur-[14px]'
        }
      >
        <a
          href="#main"
          className={
            't-button-s sr-only rounded-[var(--r-pill)] bg-surface-2 px-4 py-2 text-ink-1 ' +
            // not-sr-only 는 padding 을 0 으로 되돌리고, globals 의 .sr-only(clip:rect(0,0,0,0))는 풀지 않는다(v4 는 clip-path 만 푼다) —
            // 같은 focus: 묶음 안에서 둘 다 다시 준다(실측: 안 주면 높이 14px · 잘려서 안 보임)
            'focus:not-sr-only focus:fixed focus:left-4 focus:top-2 focus:z-[var(--z-ultra)] focus:px-4 focus:py-2 focus:[clip:auto]'
          }
        >
          본문으로 건너뛰기
        </a>
        <nav aria-label="주요" className="grid h-full grid-cols-[1fr_auto_1fr] items-center px-[var(--gutter)]">
          {brand}
          {links}
          <div className="col-start-3 flex items-center justify-self-end">
            <DownloadCTA placement="nav" size="s" tone={fill ? 'fill' : 'outline'} />
          </div>
        </nav>
      </header>
    </>
  );
}

export default NavShell;
