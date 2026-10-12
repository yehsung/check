// lib/aing.ts — 아잉 영상 층의 순수 함수(PLAN §3.3). import 0 — node --experimental-strip-types 로 바로 돈다.
// idleResumeFrame·reactionBox 는 v1 components/ui/CharacterStage.tsx:121–146 에서 JSDoc 째 그대로 옮겼다(teardown).
// heroLayer·shouldStop 은 primitives(components/ui/AingClip.tsx 가 쓴다).

/**
 * 반응이 끝난 뒤 idle 이 이어질 칸: (N mod idleFrames)/idleFps 초를 재생 판(30fps 또는 15fps)의 칸으로 바꾼다.
 * 순수 함수(검증 스크립트가 실행한다).
 */
export function idleResumeFrame(
  n: number,
  idleFrames: number,
  idleFps: number,
  variantFps: number,
  variantFrames: number,
): number {
  const k = ((n % idleFrames) + idleFrames) % idleFrames;
  const t = k / idleFps;
  return Math.min(Math.max(0, variantFrames - 1), Math.floor(t * variantFps + 1e-6));
}

/** 반응 층의 상자(CSS px): offsetOut × d 만큼 평행이동, 크기 = size × d. 순수 함수. */
export function reactionBox(
  offsetOut: readonly [number, number] | null,
  sizeOut: readonly [number, number],
  d: number,
): { left: number; top: number; width: number; height: number } {
  const ox = offsetOut ? offsetOut[0] : 0;
  const oy = offsetOut ? offsetOut[1] : 0;
  return { left: ox * d, top: oy * d, width: sizeOut[0] * d, height: sizeOut[1] * d };
}

export type Rect = { left: number; top: number; width: number; height: number };

/**
 * HERO 박스(출력 654×790) 기준 앱 배치 — data/fixtures.ts `CORNER` 의 같은 이름 값과 **같아야 한다**
 * (이 파일은 import 0 이라 복사해 둔다. AingClip 이 개발 모드에서 둘을 맞춰 보고 다르면 경고한다).
 * bubbleAtOut = 말풍선 왼쪽 위, capsuleAtOut = 근무 라벨 왼쪽 위(앱 CheckCharacter3DView 배치 그대로 — v1 CharacterStage 와 같다).
 */
export const HERO_BOX = {
  out: [654, 790],
  bubbleAtOut: [-50.5, 218.5],
  capsuleAtOut: [181.5, 571],
  capsuleSizeOut: [263.5, 119.5],
} as const;

/**
 * 히어로 아잉 상자 폭 w(CSS px) → 말풍선·근무 라벨 상자(아잉 상자 왼쪽 위 기준, CSS px). 순수 함수.
 * d = w/654. 말풍선 = 왼쪽 위 bubbleAtOut × d, 크기 = canvasPx × 0.5 × d(= Bubble 의 bubbleSize(id, d)).
 * 근무 라벨 = 왼쪽 위 capsuleAtOut × d, 크기 capsuleSizeOut × d. 1440×900(w 228): 말풍선 148×54 · 근무 라벨 92×42(SPEC §S1).
 */
export function heroLayer(w: number, bubbleCanvasPx: readonly [number, number]): { bubble: Rect; timer: Rect } {
  const d = w / HERO_BOX.out[0];
  return {
    bubble: {
      left: HERO_BOX.bubbleAtOut[0] * d,
      top: HERO_BOX.bubbleAtOut[1] * d,
      width: bubbleCanvasPx[0] * 0.5 * d,
      height: bubbleCanvasPx[1] * 0.5 * d,
    },
    timer: {
      left: HERO_BOX.capsuleAtOut[0] * d,
      top: HERO_BOX.capsuleAtOut[1] * d,
      width: HERO_BOX.capsuleSizeOut[0] * d,
      height: HERO_BOX.capsuleSizeOut[1] * d,
    },
  };
}

/** idle 반복 상한: 끝난 횟수가 maxLoops 에 닿으면 그 프레임에서 멈춘다(SPEC §S1 · §5.5 — 무한 루프 0). 순수 함수. */
export function shouldStop(loopsDone: number, maxLoops: number): boolean {
  return loopsDone >= maxLoops;
}
