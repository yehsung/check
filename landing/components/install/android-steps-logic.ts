// components/install/android-steps-logic.ts — 안드로이드 베타 카드 '다음 단계 안내'(docs/v3/brief.md §12.6)의 순수 계산. DOM·React 없음 —
// android-steps.test.ts 가 값으로 확인한다. AndroidSteps.tsx(client 섬)가 쓴다.
//
// 상태 = 마지막으로 클릭한 단계 번호 0–3(0 = 아직 없음 — 서버 HTML · JS 없음 · 저장소가 없거나 막힘 · 이상한 값).
//   단계 1..상태 = 체크(장식) · 상태 + 1 단계 = 주 버튼(보라 primary) + <li aria-current="step"> · 3 이면 셋 다 체크, 주 버튼 없음.
//   아무 단계나 다시 클릭할 수 있다(순서를 막지 않는다) — 클릭한 단계가 곧 새 상태(1단계를 다시 하면 2단계가 다시 주 버튼:
//   다른 계정으로 그룹에 다시 가입했다면 테스터 등록도 그 계정으로 다시 해야 한다).
// 저장: localStorage `aing-android-beta-step` = '0'…'3'. 읽기·쓰기는 전부 try/catch — 접근자가 던져도(사파리 사생활 · 막힌 사이트 데이터) 0 · 그대로.

export const ANDROID_STEP_KEY = 'aing-android-beta-step';
export const ANDROID_STEP_COUNT = 3;

/** 저장소에서 쓰는 두 메서드만(Storage 를 그대로 넘겨도 된다) */
export type StepStorage = Pick<Storage, 'getItem' | 'setItem'>;

/** 0–3 정수로 자른다(정수가 아니거나 범위 밖이면 0) */
export function clampStep(n: unknown): number {
  return typeof n === 'number' && Number.isInteger(n) && n >= 0 && n <= ANDROID_STEP_COUNT ? n : 0;
}

/** 저장된 글자 → 상태. 정확히 '0'…'3' 만 받는다(공백 · '1.0' · '04' · JSON · null → 0) */
export function parseStep(raw: unknown): number {
  return typeof raw === 'string' && /^[0-3]$/.test(raw) ? Number(raw) : 0;
}

/** 저장소 읽기. 저장소를 꺼내는 함수 자체가 던져도(window.localStorage 접근자가 SecurityError) 0 */
export function readStep(storage: () => StepStorage | null | undefined): number {
  try {
    const s = storage();
    return s ? parseStep(s.getItem(ANDROID_STEP_KEY)) : 0;
  } catch {
    return 0;
  }
}

/** 저장소 쓰기. 성공 여부만 돌려준다(실패해도 화면 상태는 메모리로 이어간다) */
export function writeStep(storage: () => StepStorage | null | undefined, step: number): boolean {
  try {
    const s = storage();
    if (!s) return false;
    s.setItem(ANDROID_STEP_KEY, String(clampStep(step)));
    return true;
  } catch {
    return false;
  }
}

/** 단계 n(1–3) 버튼을 클릭한 뒤의 상태 = n(순서를 막지 않는다). 범위 밖 n 은 상태를 바꾸지 않는다 */
export function clickStep(state: number, n: number): number {
  return Number.isInteger(n) && n >= 1 && n <= ANDROID_STEP_COUNT ? n : clampStep(state);
}

export interface StepView {
  /** 1–3 */
  n: number;
  /** 번호 원 → 체크(장식) */
  done: boolean;
  /** 주 버튼(보라 primary). 나머지는 유리 outline — 크기는 같다(레이아웃 이동 0) */
  primary: boolean;
  /** <li aria-current="step"> */
  current: boolean;
}

/** 상태 → 단계 셋의 모양. 상태 0(서버 HTML) = 1단계 주 버튼 · aria-current, 체크 없음 */
export function stepViews(state: number): StepView[] {
  const s = clampStep(state);
  return Array.from({ length: ANDROID_STEP_COUNT }, (_, i) => {
    const n = i + 1;
    return { n, done: n <= s, primary: n === s + 1, current: n === s + 1 };
  });
}
