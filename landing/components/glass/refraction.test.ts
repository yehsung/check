// node --experimental-strip-types --test components/glass/refraction.test.ts
// 유리 굴절 맵(docs/v3/brief.md §3): 가운데는 변위 0 · 가장자리는 안쪽을 가리킨다 · 렌즈 무게는 가장자리에만.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { REFRACT_DEFAULTS, easeOutBack, edgeMap, filterMarkup } from './refraction.ts';

const px = (m: ReturnType<typeof edgeMap>, i: number, j: number) => {
  const o = (j * m.w + i) * 4;
  return [m.data[o], m.data[o + 1], m.data[o + 2], m.data[o + 3]];
};

test('맵 크기 = 요소 크기 / k', () => {
  const m = edgeMap(400, 300, 30, 24, 2);
  assert.equal(m.w, 200);
  assert.equal(m.h, 150);
  assert.equal(m.data.length, 200 * 150 * 4);
});

test('가운데(띠 안쪽)는 정확히 (128, 128, 0, 255) — 변위·렌즈 0', () => {
  const m = edgeMap(400, 300, 30, 24, 2);
  assert.deepEqual(px(m, 100, 75), [128, 128, 0, 255]);
});

test('왼쪽 가장자리는 오른쪽(안)을, 위 가장자리는 아래(안)를 가리킨다 · 렌즈 무게 큼', () => {
  const m = edgeMap(400, 300, 30, 24, 2);
  const left = px(m, 0, 75);
  assert.ok(left[0] > 200, `R ${left[0]}`);
  assert.ok(Math.abs(left[1] - 128) <= 1, `G ${left[1]}`);
  assert.ok(left[2] > 200, `B ${left[2]}`);
  const top = px(m, 100, 0);
  assert.ok(top[1] > 200, `G ${top[1]}`);
  const right = px(m, m.w - 1, 75);
  assert.ok(right[0] < 56, `R ${right[0]}`);
  const bottom = px(m, 100, m.h - 1);
  assert.ok(bottom[1] < 56, `G ${bottom[1]}`);
});

test('모서리 0 · 납작한 메뉴바(1440×46)도 가운데 줄은 변위 0', () => {
  const m = edgeMap(1440, 46, 0, REFRACT_DEFAULTS.thin.band, 2);
  const mid = px(m, 360, 11);
  assert.ok(Math.abs(mid[0] - 128) <= 1 && Math.abs(mid[1] - 128) <= 12, `mid ${mid}`);
});

test('필터: 세 채널 scale 이 색수차만큼 다르고, 맵 크기를 요소 크기로 늘린다', () => {
  const s = filterMarkup({ mapHref: 'data:x', width: 446, height: 685, frost: 36, scale: 64, aberration: 0.1, rimBlur: 1 });
  assert.match(s, /width="446" height="685"/);
  assert.match(s, /scale="64"/);
  assert.match(s, /scale="57.6"/);
  assert.match(s, /scale="51.2"/);
  assert.match(s, /stdDeviation="36"/);
});

test('easeOutBack: 0 → 0, 1 → 1, 중간에 1 을 살짝 넘는다', () => {
  assert.equal(easeOutBack(0), 0);
  assert.equal(easeOutBack(1), 1);
  assert.ok(Math.max(...[0.6, 0.7, 0.8].map(easeOutBack)) > 1);
});
