// node --experimental-strip-types --test components/hero/comet-path.test.ts
// 빛 한 줄 경로(SPEC v2 §S1 · PLAN §4.1): 표본 200점이 글자 줄 상자(H1·리드·버튼 줄·메타)와 떨어져 있는가, 시작점 = 돔 꼭대기,
// 끝점 = 말풍선 왼쪽 가운데 − 8.
// 고정값 = 데브 3000 실측(2026-10-12, 크로뮴, 감속 컨텍스트로 정지 상태 — .scratch/hero/measure.mjs). #top 왼쪽 위 기준 CSS px.
//   글자 줄 상자 = Range.getClientRects()(텍스트 노드마다) — 통합 T6 이 실제 페이지에서 재는 것과 같은 상자. 버튼 줄 = [data-hero-cta].
//   돔 = .dome 의 레이아웃 원(offsetLeft/Top + 지름/2), 말풍선 = .aing-bubble 상자. HeroStage 와 같이 r = 지름/2 − RIM_CORE_INSET.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RIM_CORE_INSET, cometGeometry, cometLength, cometPath, sampleComet } from './comet-path.ts';

type Box = { left: number; top: number; right: number; bottom: number };
type Fixture = { dome: { cx: number; cy: number; d: number }; bubble: Box; heroH: number; text: Record<string, Box[]> };

/** SPEC §S1 · PLAN §4.1 의 문턱(경로 표본점 ↔ 글자 줄 상자). */
const MIN_GAP = 12;

const FIXTURES: Record<string, Fixture> = {
  '1440x900': {
    dome: { cx: 720, cy: 792, d: 1260 },
    bubble: { left: 583.8, top: 677.8, right: 736.6, bottom: 734 },
    heroH: 900,
    text: {
      h1: [
        { left: 479.9, top: 230.6, right: 960.1, bottom: 335.6 },
        { left: 480.1, top: 327.4, right: 959.9, bottom: 432.4 },
      ],
      lead: [
        { left: 556, top: 453.2, right: 884, bottom: 476.2 },
        { left: 541.1, top: 485.2, right: 898.8, bottom: 508.2 },
      ],
      buttons: [{ left: 553, top: 541.2, right: 887, bottom: 589.2 }],
      meta: [
        { left: 611.2, top: 605.2, right: 740.7, bottom: 622.2 },
        { left: 756.7, top: 605.2, right: 828.8, bottom: 622.2 },
      ],
    },
  },
  '1440x789': {
    dome: { cx: 720.296875, cy: 694.296875, d: 1104.59375 },
    bubble: { left: 601.7, top: 597, right: 734.4, bottom: 645.8 },
    heroH: 792.0625,
    text: {
      h1: [
        { left: 504.7, top: 206.7, right: 935.3, bottom: 300.7 },
        { left: 504.9, top: 293.5, right: 935.1, bottom: 387.5 },
      ],
      lead: [
        { left: 556, top: 408.3, right: 884, bottom: 431.3 },
        { left: 541.1, top: 440.3, right: 898.8, bottom: 463.3 },
      ],
      buttons: [{ left: 553, top: 496.3, right: 887, bottom: 544.3 }],
      meta: [
        { left: 611.2, top: 560.3, right: 740.7, bottom: 577.3 },
        { left: 756.7, top: 560.3, right: 828.8, bottom: 577.3 },
      ],
    },
  },
  '1024x768': {
    dome: { cx: 512, cy: 586, d: 896 },
    bubble: { left: 397.1, top: 578.1, right: 526, bottom: 625.5 },
    heroH: 768,
    text: {
      h1: [
        { left: 323.8, top: 202, right: 700.2, bottom: 285 },
        { left: 323.9, top: 277.9, right: 700, bottom: 360.9 },
      ],
      lead: [
        { left: 360.2, top: 380.8, right: 663.8, bottom: 402.8 },
        { left: 346.6, top: 410.2, right: 677.4, bottom: 432.2 },
      ],
      buttons: [{ left: 345, top: 464.6, right: 679, bottom: 512.6 }],
      meta: [
        { left: 403.2, top: 528.6, right: 532.7, bottom: 545.6 },
        { left: 548.7, top: 528.6, right: 620.8, bottom: 545.6 },
      ],
    },
  },
};

/** 점 ↔ 상자 거리(안이면 0). */
function distToBox(p: { x: number; y: number }, b: Box): number {
  const dx = Math.max(b.left - p.x, 0, p.x - b.right);
  const dy = Math.max(b.top - p.y, 0, p.y - b.bottom);
  return Math.hypot(dx, dy);
}

function setup(f: Fixture) {
  const dome = { cx: f.dome.cx, cy: f.dome.cy, r: f.dome.d / 2 - RIM_CORE_INSET };
  const end = { x: f.bubble.left - 8, y: (f.bubble.top + f.bubble.bottom) / 2 };
  return { dome, end, g: cometGeometry(dome, end), d: cometPath(dome, end) };
}

for (const [name, f] of Object.entries(FIXTURES)) {
  test(`${name}: 표본 200점이 H1·리드·버튼 줄·메타 글자 줄 상자와 ${MIN_GAP}px 이상 떨어진다`, () => {
    const { g } = setup(f);
    const pts = sampleComet(g, 200);
    assert.equal(pts.length, 200);
    let min = Infinity;
    let where = '';
    for (const [kind, boxes] of Object.entries(f.text)) {
      for (const b of boxes) {
        for (const p of pts) {
          const dist = distToBox(p, b);
          if (dist < min) {
            min = dist;
            where = `${kind} (${p.x.toFixed(1)}, ${p.y.toFixed(1)})`;
          }
        }
      }
    }
    assert.ok(min >= MIN_GAP, `${name}: 가장 가까운 거리 ${min.toFixed(1)}px @ ${where} < ${MIN_GAP}`);
    // 림을 달리므로 가장 가까운 곳은 H1 첫 줄 왼쪽 위(SPEC §S1)
    assert.match(where, /^h1 /);
  });

  test(`${name}: 시작점 = 돔 꼭대기, 끝점 = 말풍선 왼쪽 가운데 − 8`, () => {
    const { dome, end, g, d } = setup(f);
    assert.deepEqual(g.start, { x: dome.cx, y: dome.cy - dome.r });
    const pts = sampleComet(g, 200);
    assert.ok(Math.abs(pts[0].x - dome.cx) < 1e-6 && Math.abs(pts[0].y - (dome.cy - dome.r)) < 1e-6);
    assert.ok(Math.hypot(pts[199].x - end.x, pts[199].y - end.y) < 1e-6);
    const m = /^M (\S+) (\S+) A /.exec(d);
    assert.ok(m, d);
    assert.ok(Math.abs(Number(m[1]) - dome.cx) <= 0.05 && Math.abs(Number(m[2]) - (dome.cy - dome.r)) <= 0.05, d);
    assert.ok(d.endsWith(` ${Math.round(end.x * 10) / 10} ${Math.round(end.y * 10) / 10}`), d);
  });

  test(`${name}: 원호 구간은 림 위 · 경로는 절 안(가로 0 ~ 폭, 세로 히어로 안)`, () => {
    const { dome, g } = setup(f);
    const pts = sampleComet(g, 200);
    for (const p of pts) {
      assert.ok(p.x >= 0 && p.y >= 0 && p.y <= f.heroH, `밖: (${p.x}, ${p.y})`);
      // 원호 구간(떠나는 점 위)은 원 위
      if (p.y <= g.leave.y - 1) assert.ok(Math.abs(Math.hypot(p.x - dome.cx, p.y - dome.cy) - dome.r) < 0.5);
    }
    // 떠나는 높이 = 끝점 − 80, 림 왼쪽
    assert.ok(Math.abs(g.leave.y - (g.end.y - 80)) < 1e-9);
    assert.ok(g.leave.x < dome.cx);
  });
}

test('SPEC §S1 예(1440×900 설계값): M 720 162 A 630 630 0 0 0 110.7 632 C … 580 712', () => {
  const d = cometPath({ cx: 720, cy: 792, r: 630 }, { x: 580, y: 712 });
  assert.match(d, /^M 720 162 A 630 630 0 0 0 110\.7 632 C \S+ \S+ \S+ \S+ 580 712$/);
  // 길이 ≈ 1,300px(SPEC) — 원호 ≈ 630 × 1.32 + 곡선 ≈ 490
  const len = cometLength(cometGeometry({ cx: 720, cy: 792, r: 630 }, { x: 580, y: 712 }));
  assert.ok(len > 1150 && len < 1450, `길이 ${len.toFixed(0)}`);
});

test('림에서 꺾이지 않는다: 떠나는 점의 첫 조절점이 원의 접선 위(시계 반대 방향)', () => {
  const g = cometGeometry({ cx: 720, cy: 792, r: 630 }, { x: 580, y: 712 });
  const rx = g.leave.x - g.center.x;
  const ry = g.leave.y - g.center.y;
  const tx = g.c1.x - g.leave.x;
  const ty = g.c1.y - g.leave.y;
  assert.ok(Math.abs(rx * tx + ry * ty) < 1e-6, '반지름과 수직');
  assert.ok(ty > 0, '아래로 이어진다');
  // 끝점에는 수평으로(오른쪽으로) 닿는다
  assert.equal(g.c2.y, g.end.y);
  assert.ok(g.c2.x < g.end.x);
});

test('끝점이 원의 세로 범위 밖이어도 깨지지 않는다(떠나는 높이를 원 안으로 자른다)', () => {
  const g = cometGeometry({ cx: 100, cy: 100, r: 50 }, { x: 120, y: 400 });
  assert.ok(Number.isFinite(g.leave.x) && Number.isFinite(g.leave.y));
  assert.equal(g.leave.y, 150);
  const d = cometPath({ cx: 100, cy: 100, r: 50 }, { x: 120, y: 400 });
  assert.ok(!/NaN|Infinity/.test(d), d);
});

test('두 구간 타이밍(DECISIONS D28-3): 림 비율 · 림 시간 T₁ = P/(4 − 3P) · 이음매 속도 일치', async () => {
  const { cometRimFraction, cometRimTime } = await import('./comet-path.ts');
  for (const f of Object.values(FIXTURES)) {
    const { g } = setup(f);
    const p = cometRimFraction(g);
    assert.ok(p > 0.4 && p < 0.8, `림 비율 ${p.toFixed(3)}`);
    const t1 = cometRimTime(p);
    assert.ok(t1 > 0.15 && t1 < 0.5, `림 시간 ${t1.toFixed(3)}`);
    // 림 구간 속도 P/T₁ = 착지 구간 처음 속도 4(1 − P)/(1 − T₁)(ease-out cubic-bezier(.2,.8,.2,1) 의 처음 기울기 4)
    assert.ok(Math.abs(p / t1 - (4 * (1 - p)) / (1 - t1)) < 1e-9);
  }
  assert.equal(cometRimTime(0), 0);
  assert.equal(cometRimTime(1), 1);
});
