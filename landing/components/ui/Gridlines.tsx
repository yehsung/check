// 세로 격자 10 / 50 / 90%(SPEC §2.5 · §2.8 .gridlines) — server, aria-hidden. 부모가 position:relative 여야 한다.
// 반응형(SPEC §4 '세로 격자선' · DECISIONS D19-5): desk(1024 이상) = 10·50·90 · tab = 없음(스파인만) · phone = 없음.
//   tab 의 스파인은 x 32 라 10% 선(768 에서 76.8)과 지그재그가 생긴다 — 그래서 tab 은 선을 그리지 않는다.
//   lines="all"  → desk 셋
//   lines="left" → desk 왼쪽 하나
// 색은 --grid-line(.06) 한 가지. 선이 아니라 구조라 '선 → 렌더' 규칙의 예외다(SPEC §1.2).

export interface GridlinesProps {
  lines?: "all" | "left";
}

export function Gridlines({ lines = "all" }: GridlinesProps) {
  if (lines === "left") {
    return <div aria-hidden="true" data-gridlines="left" className="gridlines gridlines--left hidden desk:block" />;
  }
  return <div aria-hidden="true" data-gridlines="all" className="gridlines hidden desk:block" />;
}

export default Gridlines;
