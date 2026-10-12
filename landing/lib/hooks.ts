// lib/hooks.ts — 뷰포트 모드·감속 모션·근접·문턱·띠(PLAN v2 §3.1). 클라이언트 컴포넌트에서만 부른다.
// MQ_* 는 app/globals.css 의 @custom-variant 와 같은 문자열이다(SPEC §2.8). 스크롤 리스너는 두지 않는다(DECISIONS D7).
import { useEffect, useState, useSyncExternalStore } from 'react';
import type { RefObject } from 'react';

export type ViewportMode = 'desk' | 'tab' | 'phone';

export const MQ_DESK = '(min-width: 1024px) and (min-height: 640px)';
export const MQ_TAB = '(min-width: 768px) and ((max-width: 1023.98px) or (max-height: 639.98px))';
export const MQ_PHONE = '(max-width: 767.98px)';
export const MQ_REDUCED = '(prefers-reduced-motion: reduce)';
/** 무대 모드 = desk + 감속 아님(트립틱 고정 무대·빛 한 줄·패럴랙스). globals.css 의 @custom-variant stage 와 같다. */
export const MQ_STAGE = '(min-width: 1024px) and (min-height: 640px) and (prefers-reduced-motion: no-preference)';

type ConnectionLike = EventTarget & { saveData?: boolean; effectiveType?: string };
function connection(): ConnectionLike | undefined {
  if (typeof navigator === 'undefined') return undefined;
  return (navigator as Navigator & { connection?: ConnectionLike }).connection;
}

/** 지금 뷰포트 모드(클라). 서버에서는 'desk'. */
export function viewportModeNow(): ViewportMode {
  if (typeof window === 'undefined' || !window.matchMedia) return 'desk';
  if (window.matchMedia(MQ_PHONE).matches) return 'phone';
  if (window.matchMedia(MQ_DESK).matches) return 'desk';
  return 'tab';
}

const SLOW_NET = new Set(['slow-2g', '2g', '3g']);
/** Save-Data 의사 또는 느린 망(effectiveType slow-2g·2g·3g — SPEC §5.2). 서버·미지원은 false. */
export function saveDataNow(): boolean {
  const c = connection();
  if (!c) return false;
  return !!c.saveData || (typeof c.effectiveType === 'string' && SLOW_NET.has(c.effectiveType));
}

function subscribeQueries(queries: string[]) {
  return (cb: () => void) => {
    if (typeof window === 'undefined' || !window.matchMedia) return () => {};
    const lists = queries.map((q) => window.matchMedia(q));
    for (const m of lists) m.addEventListener('change', cb);
    return () => {
      for (const m of lists) m.removeEventListener('change', cb);
    };
  };
}

const subscribeMode = subscribeQueries([MQ_DESK, MQ_TAB, MQ_PHONE]);
const subscribeReduced = subscribeQueries([MQ_REDUCED]);
const reducedNow = () => typeof window !== 'undefined' && !!window.matchMedia && window.matchMedia(MQ_REDUCED).matches;
const subscribeSaveData = (cb: () => void) => {
  const c = connection();
  if (!c || typeof c.addEventListener !== 'function') return () => {};
  c.addEventListener('change', cb);
  return () => c.removeEventListener('change', cb);
};

/** SSR 기본 'desk'(첫 페인트는 CSS 의 desk:/tab:/phone: 변형이 책임진다). */
export function useViewportMode(): ViewportMode {
  return useSyncExternalStore(subscribeMode, viewportModeNow, () => 'desk' as const);
}

/** SSR false. 전이 시간에만 쓴다(initial 값을 가르지 않는다 — 하이드레이션 어긋남 방지). */
export function useReducedMotion(): boolean {
  return useSyncExternalStore(subscribeReduced, reducedNow, () => false);
}

export function useSaveData(): boolean {
  return useSyncExternalStore(subscribeSaveData, saveDataNow, () => false);
}

/** 감속 모션 또는 Save-Data(느린 망 포함) → 포스터만(영상 요청 0건). */
export function usePosterOnly(): boolean {
  const reduced = useReducedMotion();
  const saveData = useSaveData();
  return reduced || saveData;
}

const mqSubscribers = new Map<string, (cb: () => void) => () => void>();
function subscribeQuery(query: string) {
  let s = mqSubscribers.get(query);
  if (!s) {
    s = subscribeQueries([query]);
    mqSubscribers.set(query, s);
  }
  return s;
}

/** 미디어쿼리 일치 여부. SSR·하이드레이션 첫 렌더는 false(서버 스냅숏) → 하이드레이션 직후 실제 값으로 다시 렌더한다. */
export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    subscribeQuery(query),
    () => typeof window !== 'undefined' && !!window.matchMedia && window.matchMedia(query).matches,
    () => false,
  );
}

/** rootMargin 안으로 한 번 들어오면 true 로 남는다(미리 받기용). */
export function useNearViewport(ref: RefObject<Element | null>, rootMargin = '600px'): boolean {
  const [near, setNear] = useState(false);
  useEffect(() => {
    if (near) return;
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((en) => en.isIntersecting)) {
          setNear(true);
          io.disconnect();
        }
      },
      { rootMargin },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [ref, rootMargin, near]);
  return near;
}

/** ratio 이상 보이면 true(요소가 뷰포트보다 크면 뷰포트의 ratio 를 채울 때 true). 양방향. */
export function useInViewRatio(ref: RefObject<Element | null>, ratio: number): boolean {
  const [inView, setInView] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const thresholds = Array.from(new Set([0, ratio, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1])).sort((a, b) => a - b);
    const io = new IntersectionObserver(
      (entries) => {
        const en = entries[entries.length - 1];
        if (!en) return;
        const rootH = en.rootBounds?.height ?? window.innerHeight;
        const ok = en.isIntersecting && (en.intersectionRatio >= ratio || en.intersectionRect.height >= rootH * ratio);
        setInView(ok);
      },
      { threshold: thresholds },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [ref, ratio]);
  return inView;
}

/** useRevealOnce 의 상태. instant = 마운트 때 이미 문턱을 지나 있었다(해시·뒤로 가기) → 전이 없이 완성. */
export type RevealState = { on: boolean; instant: boolean };

/**
 * 문턱 1회(SPEC §S4 4.0 · DECISIONS D7). 요소 윗변이 화면 위에서 line·innerHeight 를 지나면 on(이후 고정 — 되감기 없음).
 * 마운트 때 이미 지나 있으면 { on: true, instant: true }.
 * IO 루트 = 화면 위 멀리 ~ 화면 line 지점(rootMargin `100000px 0px -${(1-line)*100}% 0px`). PLAN §3.1 의 아래 여백
 * `-${(1-line)*100}%` 에 위 여백을 크게 더한 것 — 빠른 스크롤·해시 이동으로 요소가 문턱 띠를 한 프레임 안에 건너뛰어
 * 화면 위로 사라져도(교차 없음 → 콜백 없음) '지남'으로 잡힌다.
 */
export function useRevealOnce(ref: RefObject<Element | null>, line = 0.68): RevealState {
  const [state, setState] = useState<RevealState>({ on: false, instant: false });
  const on = state.on;
  useEffect(() => {
    if (on) return;
    const el = ref.current;
    if (!el) return;
    let first = true;
    const io = new IntersectionObserver(
      (entries) => {
        const en = entries[entries.length - 1];
        if (!en) return;
        const passed = en.isIntersecting;
        if (passed) {
          setState({ on: true, instant: first });
          io.disconnect();
        }
        first = false;
      },
      { rootMargin: `100000px 0px -${round((1 - line) * 100)}% 0px`, threshold: 0 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [ref, line, on]);
  return state;
}

/**
 * GlowGate(SPEC §2.9). 요소(보통 높이 0 표식)가 화면 [band[0], band[1]] 비율 띠 안이면 true(양방향).
 * IO rootMargin = `-${band[0]*100}% 0px -${(1-band[1])*100}% 0px`. 높이 0 표식도 띠 안이면 isIntersecting 이다(가장자리 맞닿음 포함).
 */
export function useBand(ref: RefObject<Element | null>, band: readonly [number, number] = [0.3, 0.7]): boolean {
  const [inside, setInside] = useState(false);
  const top = band[0];
  const bottom = band[1];
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => {
        const en = entries[entries.length - 1];
        if (!en) return;
        setInside(en.isIntersecting);
      },
      { rootMargin: `-${round(top * 100)}% 0px -${round((1 - bottom) * 100)}% 0px`, threshold: 0 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [ref, top, bottom]);
  return inside;
}

/** rootMargin 문자열용 — (1 - .68) * 100 = 31.999999999999996 같은 꼬리를 걷는다. */
function round(n: number): number {
  return Math.round(n * 1000) / 1000;
}
