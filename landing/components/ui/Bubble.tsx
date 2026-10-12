'use client';

// 말풍선(SPEC §2.7 · §6.2). 글자는 이미지에 구워져 있다(앱 원문). alt 는 fixtures BUBBLE_TEXT 의 문구.
// 크기: bubbles.json 의 canvasPx × 0.5 × scale(CSS px) — 4x 파일로 다시 구워도 canvasPx 가 같아 크기 공식 불변(SPEC §9.3).
// 등장: 불투명 0→1 120ms 선형 + scale .96→1 200ms ease-out(origin 왼쪽 아래) / 퇴장: 1→0 160ms 선형.
// 감속 모션이면 scale 없이 불투명만. static 이면 전이 없음(부모가 CSS 로 보임을 정할 때 — AingClip 의 .aing-bubble).
// 클릭 대상이 아니다(v2 허용 목록 밖 — onClick·버튼 분기 삭제). 위치는 부모가 정한다(이 컴포넌트는 자기 상자만 그린다).
// 이미지는 자기 상자를 채운다 — style 로 상자 크기를 덮어쓰면(예: width/height 100%) 그 크기로 그린다.

import { useLayoutEffect, useRef, type CSSProperties } from 'react';
import bubblesJson from '@/data/generated/bubbles.json';
import { BUBBLE_TEXT, asset, type AssetKey, type BubbleArtId } from '@/data/fixtures';

/** 상태 BubbleId + 'ultra-mint' + 'update'. */
export type BubbleKey = BubbleArtId;

export interface BubbleProps {
  id: BubbleKey;
  scale: number;
  visible: boolean;
  /** 전이 없이 그대로 */
  static?: boolean;
  className?: string;
  style?: CSSProperties;
}

type Loose = Record<string, unknown>;
const isObj = (v: unknown): v is Loose => typeof v === 'object' && v !== null && !Array.isArray(v);
const isPair = (v: unknown): v is [number, number] =>
  Array.isArray(v) && v.length >= 2 && typeof v[0] === 'number' && typeof v[1] === 'number';

const BUBBLES: unknown = bubblesJson;
const TEXT = BUBBLE_TEXT as Record<string, { text: string; ms: number } | undefined>;

const EASE_OUT = 'cubic-bezier(.2,.8,.2,1)';
const warned = new Set<string>();

function devWarn(key: string, msg: string): void {
  if (process.env.NODE_ENV === 'production' || warned.has(key)) return;
  warned.add(key);
  console.warn(msg);
}

/** 말풍선 문구(앱 원문). */
export function bubbleText(id: BubbleKey): string {
  return TEXT[id]?.text ?? '';
}

/** 말풍선 표시 시간(ms, 앱 값). 0 = 따로 정한다(울트라·정지 그림). */
export function bubbleMs(id: BubbleKey): number {
  return TEXT[id]?.ms ?? 0;
}

/** 말풍선 이미지 경로(미리 받기용). 없으면 null. */
export function bubbleSrc(id: BubbleKey): string | null {
  if (!isObj(BUBBLES) || !isObj(BUBBLES.bubbles)) return null;
  const b = BUBBLES.bubbles[id];
  if (!isObj(b) || typeof b.asset !== 'string') return null;
  const a = asset(b.asset as AssetKey);
  return a && typeof a.src === 'string' ? a.src : null;
}

/**
 * 말풍선 표시 크기(CSS px) = canvasPx × 0.5 × scale. canvasPx 가 없으면 px3x × canvasPerPx3x(3.5) 로 만든다.
 * 메타가 없으면 null. 순수 함수(검증 스크립트가 실행한다).
 */
export function bubbleSizeFrom(file: unknown, id: string, scale: number): { w: number; h: number } | null {
  if (!isObj(file) || !isObj(file.bubbles)) return null;
  const b = file.bubbles[id];
  if (!isObj(b)) return null;
  let canvas: [number, number] | null = isPair(b.canvasPx) ? [b.canvasPx[0], b.canvasPx[1]] : null;
  if (!canvas && isPair(b.px3x)) {
    const k = typeof file.canvasPerPx3x === 'number' ? file.canvasPerPx3x : 3.5;
    canvas = [b.px3x[0] * k, b.px3x[1] * k];
  }
  if (!canvas) return null;
  return { w: canvas[0] * 0.5 * scale, h: canvas[1] * 0.5 * scale };
}

export function bubbleSize(id: BubbleKey, scale: number): { w: number; h: number } | null {
  return bubbleSizeFrom(BUBBLES, id, scale);
}

const visuallyHidden: CSSProperties = {
  position: 'absolute',
  width: 1,
  height: 1,
  padding: 0,
  margin: -1,
  overflow: 'hidden',
  clip: 'rect(0, 0, 0, 0)',
  whiteSpace: 'nowrap',
  border: 0,
};

export function Bubble({ id, scale, visible, static: isStatic = false, className, style }: BubbleProps) {
  const rootRef = useRef<HTMLDivElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);
  const prevVisible = useRef<boolean | null>(null);

  const size = bubbleSize(id, scale);
  const src = bubbleSrc(id);
  const text = bubbleText(id);

  // 등장·퇴장 전이(Web Animations). 레이아웃 효과라 첫 페인트 전에 시작 값(불투명 0)이 걸린다.
  useLayoutEffect(() => {
    const el = rootRef.current;
    const was = prevVisible.current;
    prevVisible.current = visible;
    if (!el || isStatic || typeof el.animate !== 'function') return;
    if (visible) {
      const reduce =
        typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      const anims: Animation[] = [
        el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120, easing: 'linear', fill: 'backwards' }),
      ];
      if (!reduce) {
        anims.push(
          el.animate([{ transform: 'scale(.96)' }, { transform: 'scale(1)' }], {
            duration: 200,
            easing: EASE_OUT,
            fill: 'backwards',
          }),
        );
      }
      // 이미지가 아직 안 왔으면 디코드될 때까지 시작 값(불투명 0)에 멈춰 둔다.
      const img = imgRef.current;
      if (img && !img.complete) {
        anims.forEach((a) => a.pause());
        const go = () => anims.forEach((a) => a.play());
        if (typeof img.decode === 'function') img.decode().then(go, go);
        else img.addEventListener('load', go, { once: true });
      }
      return () => anims.forEach((a) => a.cancel());
    }
    if (was === true) {
      const a = el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 160, easing: 'linear', fill: 'backwards' });
      return () => a.cancel();
    }
  }, [visible, isStatic]);

  if (!size || !src) {
    devWarn(`bubble:${id}`, `[Bubble] bubbles.json/assets.json 에 '${id}' 말풍선이 없다 — 문구만 숨긴 글자로 둔다.`);
    return visible ? <span style={visuallyHidden}>{text}</span> : null;
  }

  return (
    <div
      ref={rootRef}
      className={className}
      aria-hidden={visible ? undefined : true}
      data-bubble={id}
      style={{
        width: size.w,
        height: size.h,
        opacity: visible ? 1 : 0,
        transformOrigin: 'left bottom',
        pointerEvents: 'none',
        ...style,
      }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- next/image 를 쓰지 않는다(이미지 최적화 끔) */}
      <img
        ref={imgRef}
        src={src}
        alt={text}
        width={Math.round(size.w)}
        height={Math.round(size.h)}
        decoding="async"
        loading={isStatic ? 'lazy' : undefined}
        draggable={false}
        style={{ display: 'block', width: '100%', height: '100%', maxWidth: 'none' }}
      />
    </div>
  );
}

export default Bubble;
