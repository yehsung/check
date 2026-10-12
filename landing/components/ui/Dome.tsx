import type { CSSProperties } from "react";

// 빛의 돔(SPEC §2.2 · §2.8 .dome / .dome--small / .dome-pool) — server, aria-hidden, 클릭 없음.
// 돔 = 그라디언트 한 장(블렌드·의사 요소·점 격자 없음, J3-A6). 크기·위치는 globals 의 --dome-d·--dome-top 이 정한다.
// 부모(히어로 #top · 아웃트로 #outro)가 position:relative + overflow:clip 상자여야 한다(가로 넘침 0 — SPEC §4).
// 히어로 돔의 패럴랙스는 globals 의 `#top .dome`(CSS view-timeline)이 건다 — 여기서는 아무것도 하지 않는다.
// pool = 아잉 발밑 웅덩이(.dome-pool: 폭 --aing-w × 1.6, 가운데) — bottom 은 부모 기준(px 또는 CSS 길이).

export interface DomeProps {
  variant: "hero" | "small";
  pool?: { bottom: number | string };
  className?: string;
}

export function Dome({ variant, pool, className }: DomeProps) {
  const domeClass = variant === "small" ? "dome dome--small" : "dome";
  const poolStyle: CSSProperties | undefined = pool
    ? { bottom: typeof pool.bottom === "number" ? `${pool.bottom}px` : pool.bottom }
    : undefined;
  return (
    <>
      <div aria-hidden="true" data-dome={variant} className={className ? `${domeClass} ${className}` : domeClass} />
      {pool && <div aria-hidden="true" className="dome-pool" style={poolStyle} />}
    </>
  );
}

export default Dome;
