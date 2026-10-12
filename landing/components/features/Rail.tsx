import type { CSSProperties } from "react";

// 스파인 토막(SPEC §S4 4.0 — 이름은 Rail, 'Spine' 금지) — server, aria-hidden, 클릭 없음.
// 세로 격자 왼쪽 선(x = 50% − .40·shell, 1440 에서 144)과 같은 자리. tab x 32 · phone x 20. 부모(행 <article>·장면 <section>
// 또는 기능 절 <section>)가 position:relative 이고 화면 전폭이어야 한다(왼쪽 선 계산이 부모 폭 기준).
//
// 행(기본): 행 위 ~ 아래 1px --line 토막 + 같은 자리의 보라 토막(.rail-seg) + 노드(.node 24×24, phone 20 — 중심 y = 행 위 + 47).
//   노드 켜짐은 부모 [data-row][data-on] 이 CSS 로 정한다(globals) — 한 번 켜지면 꺼지지 않는다(행 리빌 1회).
// bare(v2.1 장면 — brief-v21 §4·§5): 선만 그린다. .rail-seg 는 globals 가 늘 켜 둔 보라 선(.55 + box-shadow 좁은 빛)이라
//   장면 6개가 맞붙어 장면 1 위에서 장면 6 아래까지 끊김 없이 이어진다(뒤는 설치·FAQ 의 .spine-ext 가 잇는다).
//   노드는 장면이 라벨 옆에 따로 그린다(라벨이 세로 가운데라 위치가 행마다 다르다). start = 첫 장면: 선이 투명에서 시작한다
//   (.spine-ext--start — 위 15% 동안 0 → .55, 끝에 타원 빛).
// head(v2 기능 절 제목): 머리 점(8px --violet-core) + 그 아래 첫 토막(늘 켜짐).

const LIT: CSSProperties = { background: "linear-gradient(transparent, rgba(126,94,250,.45))" };

/** 왼쪽 선 x(부모 기준). 세로 격자(.gridlines)의 calc(50% − shell × .40) 와 같은 식. */
const X = "desk:left-[calc(50%-var(--shell)*.40)] tab:left-8 phone:left-5";

export interface RailProps {
  head?: boolean;
  /** 선만(노드·회색 토막 없이) — v2.1 장면 */
  bare?: boolean;
  /** bare 와 함께: 첫 장면이라 선이 투명에서 시작 */
  start?: boolean;
}

export function Rail({ head = false, bare = false, start = false }: RailProps) {
  if (head) {
    return (
      <div aria-hidden="true" data-rail="head" className={`pointer-events-none absolute bottom-0 h-12 w-px ${X}`}>
        <span className="absolute inset-y-0 left-0 w-px" style={LIT} />
        <span
          className="absolute size-2 rounded-full"
          style={{
            left: -3.5,
            top: -4,
            background: "var(--violet-core)",
            boxShadow: "0 0 8px rgba(218,132,255,.8)",
          }}
        />
      </div>
    );
  }
  if (bare) {
    return (
      <div aria-hidden="true" data-rail="scene" className={`pointer-events-none absolute inset-y-0 w-px ${X}`}>
        <span className={`rail-seg absolute inset-y-0 left-0 w-px${start ? " spine-ext--start" : ""}`} />
      </div>
    );
  }
  return (
    <div aria-hidden="true" data-rail="" className={`pointer-events-none absolute inset-y-0 w-px ${X}`}>
      <span className="absolute inset-y-0 left-0 w-px bg-line" />
      <span className="rail-seg absolute inset-y-0 left-0 w-px" style={LIT} />
      <span className="node absolute top-[35px] left-[-11.5px] phone:top-[37px] phone:left-[-9.5px] phone:size-5" />
    </div>
  );
}

export default Rail;
