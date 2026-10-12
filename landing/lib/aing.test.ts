// node --experimental-strip-types --test lib/aing.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HERO_BOX, heroLayer, idleResumeFrame, reactionBox, shouldStop } from './aing.ts';

test('idleResumeFrame: commute-start 45칸 뒤 30fps idle 은 45칸에서 잇는다', () => {
  assert.equal(idleResumeFrame(45, 432, 30, 30, 432), 45);
});

test('idleResumeFrame: 15fps idle 판(216칸)은 1.5초 = 22칸', () => {
  assert.equal(idleResumeFrame(45, 432, 30, 15, 216), 22);
});

test('reactionBox: 오프셋 없음 → 원점, 크기 × d', () => {
  assert.deepEqual(reactionBox(null, [654, 790], 0.5), { left: 0, top: 0, width: 327, height: 395 });
});

test('reactionBox: 오프셋 × d 만큼 평행이동', () => {
  assert.deepEqual(reactionBox([-50.5, 218.5], [263.5, 119.5], 2), { left: -101, top: 437, width: 527, height: 239 });
});

const near = (a: number, b: number, eps = 0.01) => Math.abs(a - b) <= eps;

test('heroLayer: 출력 크기(w 654, d=1)면 CORNER 값 그대로 · 말풍선 크기 = canvasPx × 0.5', () => {
  const L = heroLayer(654, [847, 311.5]);
  assert.deepEqual(L.bubble, { left: -50.5, top: 218.5, width: 423.5, height: 155.75 });
  assert.deepEqual(L.timer, { left: 181.5, top: 571, width: 263.5, height: 119.5 });
});

test('heroLayer: 1440×900 의 아잉 228px → 말풍선 148×54 · 근무 라벨 92×42(SPEC §S1 표)', () => {
  const L = heroLayer(228, [847, 311.5]);
  assert.equal(Math.round(L.bubble.width), 148);
  assert.equal(Math.round(L.bubble.height), 54);
  assert.equal(Math.round(L.timer.width), 92);
  assert.equal(Math.round(L.timer.height), 42);
});

test('heroLayer: 1440×789 의 아잉 197px → 말풍선 윗변 = 상자 위 + 65.8(SPEC 와이어 601 = 535 + 66)', () => {
  const L = heroLayer(197, [847, 311.5]);
  assert.ok(near(L.bubble.top, 218.5 * (197 / 654)));
  assert.equal(Math.round(535 + L.bubble.top), 601);
});

test('heroLayer: 폭에 선형(2배 폭 → 모든 값 2배)', () => {
  const a = heroLayer(200, [800, 300]);
  const b = heroLayer(400, [800, 300]);
  for (const k of ['left', 'top', 'width', 'height'] as const) {
    assert.ok(near(b.bubble[k], a.bubble[k] * 2));
    assert.ok(near(b.timer[k], a.timer[k] * 2));
  }
});

test('HERO_BOX: 출력 상자 654×790', () => {
  assert.deepEqual([...HERO_BOX.out], [654, 790]);
});

test('shouldStop: 끝난 횟수가 상한에 닿으면 멈춘다', () => {
  assert.equal(shouldStop(0, 2), false);
  assert.equal(shouldStop(1, 2), false);
  assert.equal(shouldStop(2, 2), true);
  assert.equal(shouldStop(3, 2), true);
});

test('shouldStop: 상한 0 이면 처음부터 멈춤(재생하지 않는다)', () => {
  assert.equal(shouldStop(0, 0), true);
});
