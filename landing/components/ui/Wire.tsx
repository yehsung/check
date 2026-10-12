import type { CSSProperties } from "react";

// 연결선 한 토막(SPEC §2.2 .wire · §S4 4.1) — server. 부모 <svg>(viewBox = 캔버스 px)는 RowCanvas 가 만든다.
// pathLength=100 이라 stroke-dasharray 100 하나로 길이와 무관하게 그려진다. 조립 전(.js [data-row]:not([data-on]))은
// dashoffset 100 · --wire-draw, 켜지면 --at 뒤 200ms 에 그려지고 --at + 700ms 부터 --wire-rest 로 탁해진다(globals).
// 감속 모션·JS 없음은 처음부터 그려진 rest 색.

export interface WireProps {
  d: string;
  /** 조립 시작(문턱 t=0)부터의 지연 ms */
  at?: number;
}

export function Wire({ d, at = 0 }: WireProps) {
  return <path className="wire" pathLength={100} d={d} style={{ "--at": `${at}ms` } as CSSProperties} />;
}

export default Wire;
