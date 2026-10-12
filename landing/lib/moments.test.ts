// node --experimental-strip-types --test lib/moments.test.ts
// 기댓값은 SPEC v2 §S2 의 1440×900 손계산: 섹션 문서 y 900, 카드 피치 72svh = 648, 숫자 윗변 = 카드 위 + 16svh(144),
// 무대 모드에서 카드 묶음은 margin-top:-100svh 라 카드 i 의 숫자 문서 y = 1,044 + 648·i. 섹션 높이 244svh = 2,196.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DEFAULT_THRESHOLDS, isEngaged, nextActive } from './moments.ts';

const VH = 900;
const tops = (scrollY: number) => [1044 - scrollY, 1692 - scrollY, 2340 - scrollY];
const sectionBox = (scrollY: number) => [900 - scrollY, 900 + 2196 - scrollY] as const;
/** 스크롤 위치를 차례로 지나며 활성 카드를 굴린다(실제 훅처럼 직전 값을 이어 받는다). */
function walk(start: number, ys: readonly number[]): number[] {
  const out: number[] = [];
  let a = start;
  for (const y of ys) {
    a = nextActive(a, tops(y), VH);
    out.push(a);
  }
  return out;
}

test('nextActive: scrollY 549 · 1,197 · 1,845 에서 0 · 1 · 2(앞 문턱 .55·vh, 경계 포함)', () => {
  assert.deepEqual(walk(-1, [549, 1197, 1845]), [0, 1, 2]);
});

test('nextActive: 문턱 1px 앞에서는 아직 바뀌지 않는다', () => {
  assert.equal(nextActive(-1, tops(548), VH), -1);
  assert.equal(nextActive(0, tops(1196), VH), 0);
  assert.equal(nextActive(1, tops(1844), VH), 1);
});

test('nextActive: 1,845 → 1,800(−45px) 되돌림에 2 유지(히스테리시스), 1,700 에서 1', () => {
  assert.deepEqual(walk(-1, [549, 1197, 1845, 1800, 1700]), [0, 1, 2, 2, 1]);
});

test('nextActive: 뒤 문턱 .62·vh — 1→0 은 scrollY < 1,134, 2→1 은 < 1,782', () => {
  assert.equal(nextActive(1, tops(1134), VH), 1);
  assert.equal(nextActive(1, tops(1133), VH), 0);
  assert.equal(nextActive(2, tops(1782), VH), 2);
  assert.equal(nextActive(2, tops(1781), VH), 1);
});

test('nextActive: scrollY 0 에서 -1(어느 활성에서 돌아와도)', () => {
  assert.equal(nextActive(-1, tops(0), VH), -1);
  assert.equal(nextActive(1, tops(0), VH), -1);
  assert.equal(nextActive(2, tops(0), VH), -1);
});

test('nextActive: 한 번에 건너뛰면 여러 칸을 한꺼번에(해시·빠른 스크롤)', () => {
  assert.equal(nextActive(-1, tops(1845), VH), 2);
  assert.equal(nextActive(2, tops(600), VH), 0);
});

test('nextActive: 문턱 인자를 따른다 · 빈 목록은 -1 · 이상한 prev 는 범위 안으로', () => {
  assert.equal(nextActive(-1, tops(549), VH, { forward: 0.5, back: 0.62 }), -1); // 495 > 450
  assert.equal(nextActive(-1, tops(594), VH, { forward: 0.5, back: 0.62 }), 0); // 450 ≤ 450
  assert.equal(nextActive(-1, [], VH), -1);
  assert.equal(nextActive(7, tops(1845), VH), 2);
  assert.equal(nextActive(-5, tops(0), VH), -1);
});

test('isEngaged: 섹션 위 ≤ .30·vh 그리고 아래 ≥ .70·vh — 1440×900 경계 scrollY 630 / 2,466', () => {
  assert.equal(isEngaged(...sectionBox(629), VH), false);
  assert.equal(isEngaged(...sectionBox(630), VH), true);
  assert.equal(isEngaged(...sectionBox(1548), VH), true);
  assert.equal(isEngaged(...sectionBox(2466), VH), true);
  assert.equal(isEngaged(...sectionBox(2467), VH), false);
});

test('DEFAULT_THRESHOLDS = data/fixtures.ts MOMENTS_TIMING 의 forward·back(값이 두 군데라 맞춰 본다)', () => {
  const src = readFileSync(new URL('../data/fixtures.ts', import.meta.url), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
  const body = /MOMENTS_TIMING\s*=\s*\{([\s\S]*?)\}/.exec(src)?.[1] ?? '';
  const num = (k: string) => Number(new RegExp(`\\b${k}\\s*:\\s*([0-9.]+)`).exec(body)?.[1]);
  assert.equal(num('forward'), DEFAULT_THRESHOLDS.forward);
  assert.equal(num('back'), DEFAULT_THRESHOLDS.back);
});
