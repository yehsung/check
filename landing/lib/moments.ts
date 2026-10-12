// lib/moments.ts — 트립틱 활성 카드·engaged 판정(PLAN v2 §3.2 · SPEC §S2 · DECISIONS D7).
// 순수 함수 둘(nextActive·isEngaged — node --test 로 고정)과 훅 하나(useActiveCard — 스크롤 리스너 없이 IO 만).
// 이 파일은 node --experimental-strip-types 로도 읽혀야 하므로 '@/…' 별칭·JSON import 를 끌어오지 않는다
// (그래서 문턱 기본값을 data/fixtures.ts MOMENTS_TIMING 에서 가져오지 않고 같은 값을 여기 둔다 — moments.test.ts 가 맞춰 본다).
import { useEffect, useState } from 'react';
import type { RefObject } from 'react';

export type MomentsThresholds = { forward: number; back: number };

/** = MOMENTS_TIMING.forward / .back(data/fixtures.ts). 앞 .55 / 뒤 .62 — 히스테리시스 7svh(SPEC §S2). */
export const DEFAULT_THRESHOLDS: MomentsThresholds = { forward: 0.55, back: 0.62 };
/** engaged 띠: 섹션 위가 화면 30% 위로, 섹션 아래가 70% 아래(SPEC §S2 · §2.9). */
export const ENGAGED_BAND = [0.3, 0.7] as const;

// 부동소수 경계(.55 × 900 = 495.00000000000006 같은 꼬리)를 판정에서 지운다 — 기댓값의 정확한 scrollY 가 늘 같은 쪽에 떨어지게.
const EPS = 1e-6;

/**
 * 순수. numberTops[i] = i번 카드 큰 숫자의 화면 기준 윗변(px). prev = -1 이면 아직 활성 없음.
 * 앞으로: numberTops[prev+1] ≤ forward·vh 인 동안 한 칸씩(경계 포함 — 1440×900 에서 scrollY 549 가 곧 0번 활성) /
 * 뒤로: numberTops[prev] > back·vh 인 동안 한 칸씩(최소 -1).
 */
export function nextActive(
  prev: number,
  numberTops: readonly number[],
  vh: number,
  t: MomentsThresholds = DEFAULT_THRESHOLDS,
): number {
  const n = numberTops.length;
  let i = Math.min(Math.max(Math.trunc(Number.isFinite(prev) ? prev : -1), -1), n - 1);
  const fwd = t.forward * vh + EPS;
  const back = t.back * vh + EPS;
  while (i + 1 < n && numberTops[i + 1] <= fwd) i += 1;
  while (i >= 0 && numberTops[i] > back) i -= 1;
  return i;
}

/** 순수. 섹션 상자로 engaged 판정: top ≤ .30·vh && bottom ≥ .70·vh(경계 포함). */
export function isEngaged(sectionTop: number, sectionBottom: number, vh: number): boolean {
  return sectionTop <= ENGAGED_BAND[0] * vh + EPS && sectionBottom >= ENGAGED_BAND[1] * vh - EPS;
}

export type ActiveCardState = { active: number; engaged: boolean };
const IDLE: ActiveCardState = { active: -1, engaged: false };
const THRESHOLDS = [0, 0.25, 0.5, 0.75, 1];

/** 화면 위에서 p(0–1) 지점에 가로줄을 긋는 rootMargin 두 가지. 'above' = 루트 (−∞, p·vh] — 요소 윗변이 줄을 지나면 교차가 바뀐다.
 *  'below' = 루트 [p·vh, +∞) — 요소 아랫변이 줄을 지나면 교차가 바뀐다. 바깥쪽을 100000px 로 넓혀 두면 한 프레임에 화면 밖까지
 *  건너뛰어도(해시·빠른 스크롤) 교차 상태가 바뀌어 콜백이 온다(크로뮴·웹킷 실측). */
function lineMargin(p: number, side: 'above' | 'below'): string {
  const pct = (x: number) => `${Math.round(x * 100000) / 1000}%`;
  return side === 'above' ? `100000px 0px -${pct(1 - p)} 0px` : `-${pct(p)} 0px 100000px 0px`;
}

/**
 * 훅. enabled=false(목록 모드)면 { active: -1, engaged: false } 고정. 스크롤 리스너 없이
 * IO(카드 숫자 3개 + 섹션, thresholds [0,.25,.5,.75,1]) 콜백에서 getBoundingClientRect 를 읽어 위 두 순수 함수로 갱신.
 * IO 는 문턱 줄마다 하나씩 건다(앞 .55·뒤 .62 = 숫자 윗변, .30 = 섹션 윗변, .70 = 섹션 아랫변) — 숫자는 화면 가운데에서
 * 줄을 지나도 화면과의 교차 비율이 1 그대로라, 화면 전체를 루트로 하면 콜백이 오지 않는다.
 * numberRefs 는 렌더마다 새 배열이 되지 않게(useMemo·useRef·모듈 상수) 넘긴다 — 바뀌면 IO 를 다시 건다.
 */
export function useActiveCard(
  sectionRef: RefObject<HTMLElement | null>,
  numberRefs: readonly RefObject<HTMLElement | null>[],
  enabled: boolean,
): ActiveCardState {
  const [state, setState] = useState<ActiveCardState>(IDLE);

  useEffect(() => {
    if (!enabled) return;
    const section = sectionRef.current;
    if (!section || typeof IntersectionObserver === 'undefined') return;

    const update = () => {
      const vh = window.innerHeight;
      if (!(vh > 0)) return;
      const tops = numberRefs.map((r) => r.current?.getBoundingClientRect().top ?? Number.POSITIVE_INFINITY);
      const box = section.getBoundingClientRect();
      const engaged = isEngaged(box.top, box.bottom, vh);
      setState((s) => {
        const active = nextActive(s.active, tops, vh, DEFAULT_THRESHOLDS);
        return active === s.active && engaged === s.engaged ? s : { active, engaged };
      });
    };

    const ios: IntersectionObserver[] = [];
    const watch = (targets: Element[], rootMargin: string) => {
      if (targets.length === 0) return;
      const io = new IntersectionObserver(update, { rootMargin, threshold: THRESHOLDS });
      for (const el of targets) io.observe(el);
      ios.push(io);
    };
    const numbers = numberRefs.map((r) => r.current).filter((el): el is HTMLElement => !!el);
    watch(numbers, lineMargin(DEFAULT_THRESHOLDS.forward, 'above'));
    watch(numbers, lineMargin(DEFAULT_THRESHOLDS.back, 'above'));
    watch([section], lineMargin(ENGAGED_BAND[0], 'above'));
    watch([section], lineMargin(ENGAGED_BAND[1], 'below'));

    return () => {
      for (const io of ios) io.disconnect();
    };
  }, [sectionRef, numberRefs, enabled]);

  return enabled ? state : IDLE;
}
