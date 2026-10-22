'use client';
// components/glass/usePointerSpecular.ts — 포인터를 따르는 유리 스페큘러(docs/v3/brief.md §3 · §5).
// 요소에 --mx · --my(요소 왼쪽 위 기준 px)와 --spec(0 | 1)을 인라인으로 단다 → globals.css 의 .glass::before(테두리 캐치라이트)·
// ::after(면 스페큘러)가 읽는다. pointer:fine 에서만, 마우스·펜만, rAF 로 한 프레임에 한 번. 감속 모션이면 아무것도 하지 않는다.
// .glass 가 아닌 요소에도 쓸 수 있다(값만 단다 — 그리는 쪽은 그 요소의 CSS).
import { useEffect } from 'react';
import type { RefObject } from 'react';

/** ref 대신 요소를 직접 받는 판(GlassFx 가 부모 요소에 건다). 해제 함수를 돌려준다. */
export function attachPointerSpecular(el: HTMLElement): () => void {
  if (typeof window === 'undefined' || !window.matchMedia) return () => {};
  if (!window.matchMedia('(pointer: fine)').matches) return () => {};
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return () => {};
  let raf = 0;
  let cx = 0;
  let cy = 0;
  const flush = () => {
    raf = 0;
    const r = el.getBoundingClientRect();
    el.style.setProperty('--mx', `${Math.round(cx - r.left)}px`);
    el.style.setProperty('--my', `${Math.round(cy - r.top)}px`);
  };
  const ok = (e: PointerEvent) => e.pointerType === 'mouse' || e.pointerType === 'pen';
  const move = (e: PointerEvent) => {
    if (!ok(e)) return;
    cx = e.clientX;
    cy = e.clientY;
    if (!raf) raf = requestAnimationFrame(flush);
  };
  const enter = (e: PointerEvent) => {
    if (!ok(e)) return;
    move(e);
    el.style.setProperty('--spec', '1');
  };
  const leave = () => el.style.setProperty('--spec', '0');
  el.addEventListener('pointerenter', enter);
  el.addEventListener('pointermove', move, { passive: true });
  el.addEventListener('pointerleave', leave);
  return () => {
    cancelAnimationFrame(raf);
    el.removeEventListener('pointerenter', enter);
    el.removeEventListener('pointermove', move);
    el.removeEventListener('pointerleave', leave);
    el.style.removeProperty('--mx');
    el.style.removeProperty('--my');
    el.style.removeProperty('--spec');
  };
}

/** 클라이언트 컴포넌트용 훅: usePointerSpecular(ref). enabled=false 면 걸지 않는다. */
export function usePointerSpecular(ref: RefObject<HTMLElement | null>, enabled = true): void {
  useEffect(() => {
    const el = ref.current;
    if (!el || !enabled) return;
    return attachPointerSpecular(el);
  }, [ref, enabled]);
}

export default usePointerSpecular;
