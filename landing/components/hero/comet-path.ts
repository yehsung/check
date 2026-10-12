// components/hero/comet-path.ts — 히어로 빛 한 줄의 경로(SPEC v2 §S1 '빛 한 줄 경로'). 순수 함수, import 0
// (node --experimental-strip-types --test 로 바로 돈다 — comet-path.test.ts).
//
// 좌표는 #top(히어로 절) 왼쪽 위 기준 CSS px. 경로 = 돔 꼭대기 S 에서 림을 타고 시계 반대 방향(화면에서 왼쪽으로)
// 내려가다(원호), 끝점 E 보다 leaveDy 위인 림 위 점 L 에서 림을 떠나 E 로 휘어 들어간다(3차 베지어).
//   M cx,cy−r  A r,r 0 0 0 Lx,Ly  C c1 c2 E
// · L = 림 왼쪽에서 y = E.y − leaveDy 인 점. 원호는 꼭대기에서 왼쪽 반원 안만 돈다 → large-arc 0 · sweep 0.
// · c1 = L 에서 원의 접선 방향(돌던 방향 그대로)으로 leaveDy·¾ — 림에서 꺾이지 않고 이어진다(G1).
// · c2 = E 왼쪽 수평선 위(E.x − 0.45·(E.x − Lx), E.y) — E 에 수평으로(오른쪽으로) 닿는다.
// E(끝점)는 부르는 쪽이 정한다: 말풍선 왼쪽 가운데 − 8px(SPEC §S1).
// 1440×900 예(SPEC): 돔 (720, 792, 630) · E (580, 712) → M 720 162 A 630 630 0 0 0 110.7 632 C … 580 712.

export type CometDome = { cx: number; cy: number; r: number };
export type CometPoint = { x: number; y: number };

export interface CometGeometry {
  center: CometPoint;
  r: number;
  /** 돔 꼭대기 = 출발점 */
  start: CometPoint;
  /** 림을 떠나는 점 */
  leave: CometPoint;
  c1: CometPoint;
  c2: CometPoint;
  /** 끝점(= 말풍선 왼쪽 가운데 − 8) */
  end: CometPoint;
}

/** 빛 머리가 달리는 원은 돔 바깥 지름에서 5px 안쪽 — 림의 핵(1.5px, --violet-core)이 아니라 바로 안쪽 보라 띠(`--violet calc(100% − 5px)`)
 *  위다(DECISIONS D27-1: 핵 위를 달리면 같은 색이라 머리가 안 보인다). 부르는 쪽이 r = 돔 지름/2 − RIM_CORE_INSET 으로 넘긴다.
 *  글자 줄 상자와의 최소 이격은 1.5 일 때 실측 17.7px → 5 일 때 ≈14px(comet-path.test.ts 의 ≥ 12 단언 그대로). */
export const RIM_CORE_INSET = 5;

const C1_K = 0.75;
const C2_K = 0.45;

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
/** 경로 문자열은 0.1px 로 줄인다(-0 은 0 으로). */
const fmt = (v: number) => {
  const n = Math.round(v * 10) / 10;
  return Object.is(n, -0) ? '0' : String(n);
};

/** 경로의 뼈대(출발·떠남·조절점·끝). 순수 함수. */
export function cometGeometry(dome: CometDome, end: CometPoint, leaveDy = 80): CometGeometry {
  const { cx, cy } = dome;
  const r = Math.max(0, dome.r);
  // 떠나는 높이는 원의 세로 범위 안(꼭대기보다 아래 — 꼭대기에서 바로 떠나면 원호 길이 0)
  const ly = clamp(end.y - leaveDy, cy - r, cy + r);
  const lx = cx - Math.sqrt(Math.max(0, r * r - (ly - cy) * (ly - cy)));
  // 반지름 벡터 (rx, ry) = L − C. 화면에서 시계 반대 방향(꼭대기 → 왼쪽 → 아래)의 접선 = (ry, −rx)/r
  const rx = lx - cx;
  const ry = ly - cy;
  const tx = r > 0 ? ry / r : 0;
  const ty = r > 0 ? -rx / r : 1;
  const k1 = leaveDy * C1_K;
  const k2 = Math.max(0, end.x - lx) * C2_K;
  return {
    center: { x: cx, y: cy },
    r,
    start: { x: cx, y: cy - r },
    leave: { x: lx, y: ly },
    c1: { x: lx + tx * k1, y: ly + ty * k1 },
    c2: { x: end.x - k2, y: end.y },
    end: { x: end.x, y: end.y },
  };
}

/** SVG path d. 순수 함수. */
export function cometPath(dome: CometDome, end: CometPoint, leaveDy = 80): string {
  const g = cometGeometry(dome, end, leaveDy);
  return (
    `M ${fmt(g.start.x)} ${fmt(g.start.y)} ` +
    `A ${fmt(g.r)} ${fmt(g.r)} 0 0 0 ${fmt(g.leave.x)} ${fmt(g.leave.y)} ` +
    `C ${fmt(g.c1.x)} ${fmt(g.c1.y)} ${fmt(g.c2.x)} ${fmt(g.c2.y)} ${fmt(g.end.x)} ${fmt(g.end.y)}`
  );
}

function bezier(g: CometGeometry, t: number): CometPoint {
  const u = 1 - t;
  const a = u * u * u;
  const b = 3 * u * u * t;
  const c = 3 * u * t * t;
  const d = t * t * t;
  return {
    x: a * g.leave.x + b * g.c1.x + c * g.c2.x + d * g.end.x,
    y: a * g.leave.y + b * g.c1.y + c * g.c2.y + d * g.end.y,
  };
}

/**
 * 경로 위 표본 n 점(길이 기준 등간격, 양 끝 포함). 브라우저의 getPointAtLength 와 같은 뜻을 DOM 없이 —
 * 단위 테스트가 글자 줄 상자와의 거리를 잰다. 순수 함수.
 */
export function sampleComet(g: CometGeometry, n = 200): CometPoint[] {
  // 촘촘한 꺾은선(원호 + 베지어)을 만든 뒤 길이로 다시 뽑는다
  const dense: CometPoint[] = [];
  const a0 = Math.atan2(g.start.y - g.center.y, g.start.x - g.center.x); // −π/2
  let a1 = Math.atan2(g.leave.y - g.center.y, g.leave.x - g.center.x);
  if (a1 > a0) a1 -= 2 * Math.PI; // 화면에서 시계 반대 = 각도가 줄어드는 쪽(y 아래 좌표계)
  const ARC = 400;
  for (let i = 0; i <= ARC; i++) {
    const a = a0 + ((a1 - a0) * i) / ARC;
    dense.push({ x: g.center.x + g.r * Math.cos(a), y: g.center.y + g.r * Math.sin(a) });
  }
  const BEZ = 400;
  for (let i = 1; i <= BEZ; i++) dense.push(bezier(g, i / BEZ));

  const cum = [0];
  for (let i = 1; i < dense.length; i++) {
    cum.push(cum[i - 1] + Math.hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y));
  }
  const total = cum[cum.length - 1];
  const out: CometPoint[] = [];
  let j = 1;
  for (let k = 0; k < n; k++) {
    const s = n === 1 ? 0 : (total * k) / (n - 1);
    while (j < cum.length - 1 && cum[j] < s) j++;
    const seg = cum[j] - cum[j - 1];
    const f = seg > 0 ? clamp((s - cum[j - 1]) / seg, 0, 1) : 0;
    out.push({
      x: dense[j - 1].x + (dense[j].x - dense[j - 1].x) * f,
      y: dense[j - 1].y + (dense[j].y - dense[j - 1].y) * f,
    });
  }
  return out;
}

/** 경로 길이(px, 꺾은선 근사). 순수 함수. */
export function cometLength(g: CometGeometry): number {
  const pts = sampleComet(g, 801);
  let len = 0;
  for (let i = 1; i < pts.length; i++) len += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
  return len;
}

/** 림 원호 길이 / 전체 길이(0–1). 빛 한 줄 타이밍을 두 구간으로 나누는 기준(DECISIONS D28-3). 순수 함수. */
export function cometRimFraction(g: CometGeometry): number {
  const a0 = Math.atan2(g.start.y - g.center.y, g.start.x - g.center.x);
  let a1 = Math.atan2(g.leave.y - g.center.y, g.leave.x - g.center.x);
  if (a1 > a0) a1 -= 2 * Math.PI;
  const arc = g.r * (a0 - a1);
  const total = cometLength(g);
  return total > 0 ? clamp(arc / total, 0, 1) : 0;
}

/**
 * 빛 한 줄의 두 구간 타이밍(DECISIONS D28-3): 림 구간(P = 림 비율)은 등속, 착지 구간은 ease-out(cubic-bezier(.2,.8,.2,1)).
 * 이음매 속도를 맞춘다 — ease-out 의 처음 기울기 = .8/.2 = 4 → P/T₁ = 4(1 − P)/(1 − T₁) → T₁ = P / (4 − 3P).
 * 1440×900(P ≈ .63) 에서 T₁ ≈ .30(1000ms 중 림 300ms). 순수 함수.
 */
export function cometRimTime(rimFraction: number): number {
  const p = clamp(rimFraction, 0, 1);
  return p / (4 - 3 * p);
}
