'use client';

// 스프라이트 시트 백엔드(PLAN §3.5). 지금은 틱 띠(`tick`) 하나만 쓴다.
// <div> 하나에 background-image · background-size · background-position 으로 칸을 고른다.
// 칸 교체는 숫자 교체라 움직임이 아니다 — 감속 모션에서도 그대로 동작한다(SPEC §2.7 `--t-instant`).

import { forwardRef, useEffect, useImperativeHandle, useState, type CSSProperties } from 'react';

export interface SheetPlayerHandle {
  play(): Promise<void>;
  pause(): void;
  seekToFrame(n: number): Promise<void>;
  readonly ready: boolean;
}

export interface SheetPlayerProps {
  src: string;
  cols: number;
  rows: number;
  frames: number;
  fps: number;
  /** 원본 한 칸 크기(px). 표시 높이 = displayWidth × h / w */
  frameSize: readonly [number, number];
  displayWidth: number;
  /** 외부 제어 칸. 주어지면 내부 재생은 쓰지 않는다 */
  frame?: number;
  /** frame 이 없을 때만: true 면 fps 로 칸을 넘긴다 */
  play: boolean;
  loop: boolean;
  onReady?: () => void;
  onEnded?: () => void;
  className?: string;
  style?: CSSProperties;
}

/** 칸 번호 → background-position(px). 순수 함수(검증 스크립트가 그대로 실행한다). */
export function sheetPosition(
  frame: number,
  cols: number,
  rows: number,
  displayWidth: number,
  displayHeight: number,
): { x: number; y: number } {
  const total = Math.max(1, cols * rows);
  const f = Math.min(Math.max(0, Math.floor(frame)), total - 1);
  const col = f % cols;
  const row = Math.floor(f / cols);
  return { x: -col * displayWidth, y: -row * displayHeight };
}

export const SheetPlayer = forwardRef<SheetPlayerHandle, SheetPlayerProps>(function SheetPlayer(props, ref) {
  const { src, cols, rows, frames, fps, frameSize, displayWidth, frame, play, loop, onReady, onEnded, className, style } = props;
  const [internal, setInternal] = useState(0);
  const [loadedSrc, setLoadedSrc] = useState<string | null>(null);

  const displayHeight = (displayWidth * frameSize[1]) / frameSize[0];
  const controlled = typeof frame === 'number';
  const shown = controlled ? frame : internal;
  const pos = sheetPosition(shown, cols, rows, displayWidth, displayHeight);

  // 시트 이미지를 미리 디코드해 칸 교체 때 빈 칸이 생기지 않게 한다.
  useEffect(() => {
    let cancelled = false;
    const img = new Image();
    img.src = src;
    const done = () => {
      if (cancelled) return;
      setLoadedSrc(src);
      onReady?.();
    };
    if (typeof img.decode === 'function') img.decode().then(done, done);
    else img.onload = done;
    return () => {
      cancelled = true;
    };
    // onReady 는 src 가 바뀔 때 한 번만 알린다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [src]);

  // 내부 재생(외부 frame 이 없을 때만).
  useEffect(() => {
    if (controlled || !play) return;
    const last = Math.max(0, frames - 1);
    const id = setInterval(() => {
      setInternal((f) => {
        if (f >= last) return loop ? 0 : f;
        return f + 1;
      });
    }, 1000 / Math.max(1, fps));
    return () => clearInterval(id);
  }, [controlled, play, frames, fps, loop]);

  // 내부 재생이 마지막 칸에 닿으면 onEnded.
  useEffect(() => {
    if (controlled || loop) return;
    if (internal >= frames - 1 && frames > 0 && play) onEnded?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [internal]);

  useImperativeHandle(
    ref,
    () => ({
      play: () => Promise.resolve(),
      pause: () => {},
      seekToFrame: (n: number) => {
        setInternal(Math.max(0, Math.min(frames - 1, Math.floor(n))));
        return Promise.resolve();
      },
      ready: true,
    }),
    [frames],
  );

  return (
    <div
      aria-hidden="true"
      data-sheet-ready={loadedSrc === src ? '' : undefined}
      className={className}
      style={{
        width: displayWidth,
        height: displayHeight,
        backgroundImage: `url("${src}")`,
        backgroundRepeat: 'no-repeat',
        backgroundSize: `${cols * displayWidth}px ${rows * displayHeight}px`,
        backgroundPosition: `${pos.x}px ${pos.y}px`,
        ...style,
      }}
    />
  );
});
