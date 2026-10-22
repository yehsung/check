'use client';
// components/site/BrandLink.tsx — 메뉴바 왼쪽 앱 이름 링크(docs/v3/brief.md §9.2). 첫 페이지와 /licenses 가 같이 쓴다.
// 다른 경로(/licenses)에서는 평범한 next/link 로 '/' 로 간다.
// 첫 페이지에서는 '/' 가 지금 주소와 같아 브라우저·라우터가 아무것도 안 할 수 있다 → 직접 처리한다:
//   맨 위(히어로)로 스크롤(감속 모션이면 즉시) · 주소의 '#…' 를 지운다(replaceState — 기록을 늘리지 않는다) ·
//   포커스를 문서 맨 앞으로(body 에 잠깐 tabindex=-1 → 다음 Tab 이 '본문으로 건너뛰기'부터). 새 탭 열기(⌘·Ctrl·Shift·Alt·가운데)는 건드리지 않는다.
import Link from 'next/link';
import type { MouseEvent, ReactNode } from 'react';
import { MQ_REDUCED } from '@/lib/hooks';

/** 문서 맨 앞으로 포커스(링 없이 — 페이지를 처음 연 것과 같은 자리). 포커스가 떠나면 tabindex 를 거둔다. */
function focusDocumentStart() {
  const body = document.body;
  const hadTabIndex = body.hasAttribute('tabindex');
  if (!hadTabIndex) body.setAttribute('tabindex', '-1');
  const prevOutline = body.style.outline;
  body.style.outline = 'none';
  body.focus({ preventScroll: true });
  if (!hadTabIndex) {
    body.addEventListener(
      'blur',
      () => {
        body.removeAttribute('tabindex');
        body.style.outline = prevOutline;
      },
      { once: true },
    );
  }
}

export function BrandLink({ className, children }: { className?: string; children: ReactNode }) {
  const onClick = (e: MouseEvent<HTMLAnchorElement>) => {
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (window.location.pathname !== '/') return; // 다른 경로 → next/link 가 '/' 로
    e.preventDefault();
    const reduced = window.matchMedia?.(MQ_REDUCED).matches ?? false;
    window.scrollTo({ top: 0, left: 0, behavior: reduced ? 'instant' : 'smooth' });
    if (window.location.hash) history.replaceState(history.state, '', window.location.pathname + window.location.search);
    focusDocumentStart();
  };
  return (
    <Link href="/" prefetch={false} aria-label="아잉체크 처음으로" onClick={onClick} className={className}>
      {children}
    </Link>
  );
}

export default BrandLink;
