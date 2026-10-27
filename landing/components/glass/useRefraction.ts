'use client';
// components/glass/useRefraction.ts — 유리 가장자리 렌즈를 요소에 건다(데스크톱 Chromium 만 — refraction.ts canRefract).
// 하는 일: <svg id="glass-defs">(app/layout.tsx 의 GlassDefs) 안에 그 요소 전용 <filter> 를 만들고, 요소 크기(ResizeObserver)에 맞춘
// 변위 맵(canvas → PNG data URL)을 넣은 뒤 요소에 data-refract="on" + --g-refract:url(#id) 를 단다(globals.css 가 backdrop-filter 로 쓴다).
// 화면 밖이면(IntersectionObserver) data-refract="off" — 블러 폴백으로 돌아가 GPU 를 쉰다(동시에 보이는 굴절 요소 ≤ 3 — §3).
// entrance: 처음 한 번 '응결' — 변위·서리 세기를 2.2배 → 1배로(300ms 뒤 800ms, 감속 모션이면 생략). CSS .hero-pop 응결과 같은 박자.
// 굴절을 못 켜는 환경에서는 아무것도 하지 않는다(요소는 .glass 의 blur 그대로).
import { useEffect } from 'react';
import type { RefObject } from 'react';
import {
  FROST_BLUR,
  REFRACT_DEFAULTS,
  canRefract,
  easeOutBack,
  edgeMap,
  filterMarkup,
  type GlassLevel,
  type RefractOptions,
} from './refraction';

const NS = 'http://www.w3.org/2000/svg';
let seq = 0;

function defsRoot(): SVGElement {
  const found = document.querySelector<SVGElement>('#glass-defs defs');
  if (found) return found;
  // GlassDefs 가 없는 페이지 — 스스로 만든다(보이지 않는 0×0 svg)
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('id', 'glass-defs');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('width', '0');
  svg.setAttribute('height', '0');
  svg.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden;pointer-events:none';
  const defs = document.createElementNS(NS, 'defs');
  svg.appendChild(defs);
  document.body.appendChild(svg);
  return defs;
}

function mapDataUrl(w: number, h: number, radius: number, band: number): string | null {
  const m = edgeMap(w, h, radius, band, 2);
  const c = document.createElement('canvas');
  c.width = m.w;
  c.height = m.h;
  const ctx = c.getContext('2d');
  if (!ctx) return null;
  const img = ctx.createImageData(m.w, m.h);
  img.data.set(m.data);
  ctx.putImageData(img, 0, 0);
  return c.toDataURL('image/png');
}

function levelOf(el: HTMLElement): GlassLevel {
  if (el.classList.contains('glass--thin')) return 'thin';
  if (el.classList.contains('glass--thick')) return 'thick';
  return 'regular';
}

export interface UseRefractionOptions extends RefractOptions {
  /** 단계(기본: 요소의 .glass--* 클래스에서 읽는다) */
  level?: GlassLevel;
  /** 첫 등장 때 한 번 응결(세기 강 → 보통) */
  entrance?: boolean;
}

/** 요소를 직접 받는 판(GlassFx 가 부모 요소에 건다). 해제 함수를 돌려준다. */
export function attachRefraction(el: HTMLElement, opts: UseRefractionOptions = {}): () => void {
  if (!canRefract() || typeof ResizeObserver === 'undefined') return () => {};
  const level = opts.level ?? levelOf(el);
  const d = REFRACT_DEFAULTS[level];
  const band = opts.band ?? d.band;
  const scale = opts.scale ?? d.scale;
  const aberration = opts.aberration ?? d.aberration;
  const rimBlur = opts.rimBlur ?? d.rimBlur;
  const id = `g-refract-${++seq}`;
  const filter = document.createElementNS(NS, 'filter');
  filter.setAttribute('id', id);
  filter.setAttribute('filterUnits', 'userSpaceOnUse');
  filter.setAttribute('color-interpolation-filters', 'sRGB');
  filter.setAttribute('x', '0');
  filter.setAttribute('y', '0');
  defsRoot().appendChild(filter);

  let k = 1; // 응결 배율(1 = 보통)
  let size = { w: 0, h: 0, frost: FROST_BLUR[level], href: '' };
  let built = false;

  const paint = () => {
    filter.setAttribute('width', String(size.w));
    filter.setAttribute('height', String(size.h));
    filter.innerHTML = filterMarkup({
      mapHref: size.href,
      width: size.w,
      height: size.h,
      frost: size.frost * k,
      scale: scale * k,
      aberration,
      rimBlur,
    });
  };

  const build = () => {
    // 레이아웃 크기(offset*) — 응결 scale 변형의 영향을 받지 않는다
    const w = el.offsetWidth;
    const h = el.offsetHeight;
    if (!(w > 0 && h > 0)) return;
    const cs = getComputedStyle(el);
    const radius = parseFloat(cs.borderTopLeftRadius) || 0;
    const frost = parseFloat(cs.getPropertyValue('--g-blur')) || FROST_BLUR[level];
    const href = mapDataUrl(w, h, Math.min(radius, w / 2, h / 2), band);
    if (!href) return;
    size = { w, h, frost: frost > 0 && frost < 64 ? frost : FROST_BLUR[level], href };
    paint();
    if (!built) {
      built = true;
      el.style.setProperty('--g-refract', `url(#${id})`);
      el.dataset.refract = 'on';
    }
  };

  let raf = 0;
  const ro = new ResizeObserver(() => {
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(build);
  });
  ro.observe(el);

  const io =
    typeof IntersectionObserver === 'undefined'
      ? null
      : new IntersectionObserver((entries) => {
          const en = entries[entries.length - 1];
          if (!en || !built) return;
          el.dataset.refract = en.isIntersecting ? 'on' : 'off';
        });
  io?.observe(el);

  // 응결(1회)
  let tween = 0;
  if (opts.entrance && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    k = 2.2;
    const t0 = performance.now() + 300;
    const step = (now: number) => {
      const t = (now - t0) / 800;
      if (t >= 0) {
        k = 2.2 - 1.2 * easeOutBack(t);
        if (size.href) paint();
      }
      if (t < 1) tween = requestAnimationFrame(step);
      else {
        k = 1;
        if (size.href) paint();
      }
    };
    tween = requestAnimationFrame(step);
  }

  return () => {
    cancelAnimationFrame(raf);
    cancelAnimationFrame(tween);
    ro.disconnect();
    io?.disconnect();
    filter.remove();
    el.style.removeProperty('--g-refract');
    delete el.dataset.refract;
  };
}

/** 클라이언트 컴포넌트용 훅. opts 는 처음 값만 쓴다(바꾸려면 key 를 바꿔 다시 마운트). */
export function useRefraction(ref: RefObject<HTMLElement | null>, opts: UseRefractionOptions & { enabled?: boolean } = {}): void {
  const { enabled = true, level, band, scale, aberration, rimBlur, entrance } = opts;
  useEffect(() => {
    const el = ref.current;
    if (!el || !enabled) return;
    return attachRefraction(el, { level, band, scale, aberration, rimBlur, entrance });
  }, [ref, enabled, level, band, scale, aberration, rimBlur, entrance]);
}

export default useRefraction;
