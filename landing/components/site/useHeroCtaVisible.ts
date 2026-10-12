'use client';
// 히어로 CTA 줄([data-hero-cta])이 내비 띠 아래로 보이는지(SPEC S0: 보이면 내비 CTA 는 테두리, 벗어나면 채움).
// 여러 벌(플랫폼별)이 있으면 하나라도 보이면 보임. display:none 인 벌은 교차하지 않으므로 자연히 빠진다.
// SSR·첫 페인트 기본값 = 보임(테두리) — 첫 화면에서 주 버튼 둘이 경쟁하지 않는다.
// 하이드레이션 시점에 줄이 아직 없으면 생길 때까지 MutationObserver 로 기다린다.
import { useEffect, useState } from 'react';

const SELECTOR = '[data-hero-cta]';

function navHeightPx(): number {
  const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--nav-h'));
  return Number.isFinite(v) && v > 0 ? v : 48;
}

export function useHeroCtaVisible(): boolean {
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    if (typeof IntersectionObserver === 'undefined') return;
    const seen = new Map<Element, boolean>();
    const io = new IntersectionObserver(
      (entries) => {
        for (const en of entries) seen.set(en.target, en.isIntersecting);
        let any = false;
        for (const v of seen.values()) any = any || v;
        setVisible(any);
      },
      { rootMargin: `-${navHeightPx()}px 0px 0px 0px`, threshold: 0 },
    );
    const attach = (): boolean => {
      const els = document.querySelectorAll(SELECTOR);
      els.forEach((el) => io.observe(el));
      return els.length > 0;
    };
    let mo: MutationObserver | null = null;
    if (!attach()) {
      mo = new MutationObserver(() => {
        if (attach()) mo?.disconnect();
      });
      mo.observe(document.body, { childList: true, subtree: true });
    }
    return () => {
      io.disconnect();
      mo?.disconnect();
    };
  }, []);

  return visible;
}
