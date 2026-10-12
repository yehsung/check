// 폰 셸(SPEC 공통 P · §2.6). 코드로 그린 정면 셸 — 측면 버튼 없음.
// 화면 402:874 · 화면 반경 0.155W · 베젤 0.035W · 셸 반경 = 화면 반경 + 베젤 · 셸 #0a0a0c
// 바깥 1px rgba(255,255,255,.10) + 안쪽 1px rgba(255,255,255,.06) + --shadow-window.
// 다이내믹 아일랜드는 CSS 로 덮는다(스틸에 아일랜드가 없다): 폭 0.315W · 높이 0.093W · 화면 위 0.028W.
// 구조: div.shell > div.screen(overflow hidden) > img(1% 확대, object-fit cover) + div.island
// children 의 직계 <img> 는 화면을 덮도록 맞춘다. 핫스팟 등 다른 children 은 화면(relative) 기준으로 스스로 자리 잡는다.

import type { CSSProperties, ReactNode } from 'react';

export interface PhoneShellProps {
  /** 화면 폭(CSS px) = W */
  screenWidth: number;
  children?: ReactNode;
  className?: string;
  style?: CSSProperties;
}

export const PHONE_SCREEN_RATIO = 874 / 402;

/** 셸 치수(CSS px). 순수 함수. */
export function phoneShellMetrics(W: number) {
  const bezel = 0.035 * W;
  const screenRadius = 0.155 * W;
  return {
    screenW: W,
    screenH: W * PHONE_SCREEN_RATIO,
    bezel,
    screenRadius,
    shellRadius: screenRadius + bezel,
    shellW: W + 2 * bezel,
    shellH: W * PHONE_SCREEN_RATIO + 2 * bezel,
    island: { w: 0.315 * W, h: 0.093 * W, top: 0.028 * W },
  };
}

export function PhoneShell({ screenWidth, children, className, style }: PhoneShellProps) {
  const m = phoneShellMetrics(screenWidth);
  return (
    <div
      className={className}
      data-phone-shell=""
      style={{
        position: 'relative',
        boxSizing: 'content-box',
        width: m.screenW,
        height: m.screenH,
        padding: m.bezel,
        borderRadius: m.shellRadius,
        background: '#0a0a0c',
        boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.06), 0 0 0 1px rgba(255,255,255,.10), var(--shadow-window)',
        flex: 'none',
        ...style,
      }}
    >
      <div
        className="[&>img]:absolute [&>img]:inset-0 [&>img]:block [&>img]:h-full [&>img]:w-full [&>img]:max-w-none [&>img]:scale-[1.01] [&>img]:object-cover"
        style={{
          position: 'relative',
          width: m.screenW,
          height: m.screenH,
          borderRadius: m.screenRadius,
          overflow: 'hidden',
          background: '#000',
          isolation: 'isolate',
        }}
      >
        {children}
        <div
          aria-hidden="true"
          style={{
            position: 'absolute',
            top: m.island.top,
            left: '50%',
            width: m.island.w,
            height: m.island.h,
            marginLeft: -m.island.w / 2,
            borderRadius: 999,
            background: '#000',
            pointerEvents: 'none',
            zIndex: 1,
          }}
        />
      </div>
    </div>
  );
}

export default PhoneShell;
