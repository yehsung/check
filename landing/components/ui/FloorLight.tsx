import type { CSSProperties } from "react";

// 행 바닥 빛(SPEC §2.2 .floor-light · §2.9 GlowGate) — client 아님. data-glow 값은 부모(FeatureRow 의 useBand)가 준다.
// 렌더 아래 타원: 폭 = width × 1.3(가운데 = 부모 상자의 50%), 높이 160, 중심 α .55(행별 --floor-alpha) — DECISIONS D19-1·D20-2. 위치 기준은 부모의 position 상자.
// GlowGate: data-glow="on" 일 때만 불투명 1(800ms 선형 — 감속 모션에서도 남는 불투명 페이드).

export interface FloorLightProps {
  /** 캔버스 안 렌더들의 합집합 폭(px) — 타원 폭은 이것의 1.3배 */
  width: number;
  /** 부모 상자 위에서의 거리(px) */
  top: number;
  on: boolean;
}

export function FloorLight({ width, top, on }: FloorLightProps) {
  return (
    <div
      aria-hidden="true"
      className="floor-light"
      data-glow={on ? "on" : "off"}
      style={{ "--w": `${width}px`, top } as CSSProperties}
    />
  );
}

export default FloorLight;
