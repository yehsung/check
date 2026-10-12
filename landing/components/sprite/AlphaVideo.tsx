'use client';

// 알파 영상 백엔드(PLAN §3.5, SPEC §3.4·§8.3).
// - 형식은 <source> 순서가 아니라 JS(pickVideoFormat)로 고르고 src 하나만 붙인다.
//   서버·하이드레이션 동안에는 형식을 모르므로(null) 포스터만 그린다 → 하이드레이션 어긋남 0.
// - posterOnly 면 <video> 를 만들지 않는다 → 영상 요청 0건.
// - error(또는 iOS 저전력의 autoplay 거절) → onError + 포스터에 머문다. 재생 버튼 UI 없음.

import {
  forwardRef,
  useCallback,
  useEffect,
  useEffectEvent,
  useImperativeHandle,
  useRef,
  useState,
  useSyncExternalStore,
  type CSSProperties,
} from 'react';
import { pickVideoFormat } from '@/lib/media';

export type VideoFormat = 'mov' | 'webm';
export interface AlphaVideoSources {
  webm?: string;
  mov?: string;
}

export interface AlphaVideoHandle {
  play(): Promise<void>;
  pause(): void;
  seekToFrame(n: number): Promise<void>;
  readonly ready: boolean;
}

export interface AlphaVideoProps {
  sources: AlphaVideoSources;
  poster: string | null;
  fps: number;
  frames: number;
  width: number;
  height: number;
  play: boolean;
  loop: boolean;
  posterOnly: boolean;
  preload: 'none' | 'metadata' | 'auto';
  priority?: boolean;
  onReady?: () => void;
  onEnded?: () => void;
  onError?: () => void;
  className?: string;
  style?: CSSProperties;
}

/** seeked 를 기다리는 최대 시간(SPEC §3.4). */
export const SEEK_WAIT_MS = 300;

/** 프레임 n 의 한가운데 시각(초). 칸 경계에 걸려 이전 프레임이 나오는 것을 피한다. 순수 함수. */
export function frameTime(n: number, fps: number, frames: number): number {
  const last = Math.max(0, frames - 1);
  const f = Math.min(Math.max(0, Math.floor(n)), last);
  return (f + 0.5) / fps;
}

function seekVideo(v: HTMLVideoElement, t: number): Promise<void> {
  return new Promise((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      v.removeEventListener('seeked', finish);
      resolve();
    };
    const timer = setTimeout(finish, SEEK_WAIT_MS);
    v.addEventListener('seeked', finish);
    try {
      const d = v.duration;
      v.currentTime = Number.isFinite(d) && d > 0 ? Math.min(t, Math.max(0, d - 0.001)) : t;
    } catch {
      finish();
    }
  });
}

function makeHandle(get: () => HTMLVideoElement | null, fps: number, frames: number): AlphaVideoHandle {
  return {
    play() {
      const v = get();
      if (!v) return Promise.resolve();
      return v.play().then(
        () => undefined,
        () => undefined,
      );
    },
    pause() {
      get()?.pause();
    },
    seekToFrame(n: number) {
      const v = get();
      if (!v) return Promise.resolve();
      return seekVideo(v, frameTime(n, fps, frames));
    },
    get ready() {
      const v = get();
      return !!v && v.readyState >= 2;
    },
  };
}

const noopSubscribe = () => () => {};
const serverFormat = () => null;

function useVideoFormat(): VideoFormat | null {
  return useSyncExternalStore<VideoFormat | null>(noopSubscribe, pickVideoFormat, serverFormat);
}

const FILL: CSSProperties = { position: 'absolute', inset: 0, width: '100%', height: '100%', display: 'block' };

export const AlphaVideo = forwardRef<AlphaVideoHandle, AlphaVideoProps>(function AlphaVideo(props, ref) {
  const {
    sources,
    poster,
    fps,
    frames,
    width,
    height,
    play,
    loop,
    posterOnly,
    preload,
    priority,
    onReady,
    onEnded,
    onError,
    className,
    style,
  } = props;

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const readyFired = useRef(false);
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  const [frameSrc, setFrameSrc] = useState<string | null>(null);

  const format = useVideoFormat();
  const src = format ? (sources[format] ?? null) : null;
  const failed = src !== null && failedSrc === src;
  const showVideo = !posterOnly && src !== null && !failed;
  const posterVisible = poster !== null && (!showVideo || frameSrc !== src);

  useImperativeHandle(ref, () => makeHandle(() => videoRef.current, fps, frames), [fps, frames]);

  // <video> 가 새로 생길 때(key=src)만 불린다. iOS 자동 재생 조건(muted)을 속성으로도 확실히 건다.
  const setVideo = useCallback((el: HTMLVideoElement | null) => {
    videoRef.current = el;
    if (el) {
      el.muted = true;
      el.defaultMuted = true;
      readyFired.current = false;
    }
  }, []);

  const reportError = useEffectEvent(() => {
    onError?.();
  });
  const reportBlocked = useEffectEvent((s: string) => {
    setFailedSrc(s);
    onError?.();
  });

  // 캐시된 영상은 React 가 <video> 를 붙이기(커밋) 전에 canplay·loadeddata 가 이미 지나가 버린다 — React 는 커밋 전 노드의
  // 이벤트를 버리므로 onCanPlay 가 끝내 오지 않는다(울트라가 2.5초 포스터로 강제되던 원인). 붙은 직후 readyState 로 한 번 더 본다.
  const reportReady = useEffectEvent(() => {
    if (readyFired.current) return;
    readyFired.current = true;
    onReady?.();
  });
  useEffect(() => {
    const v = videoRef.current;
    if (!v || !showVideo || src === null) return;
    // 같은 원리로 커밋 전에 지나간 error(알파 HEVC 를 못 푸는 WebKit 은 83ms 안에 낸다)도 다시 잡는다 — 안 그러면
    // onError → 포스터 경로가 돌지 않아 울트라가 스토어의 2.5초 강제 포스터까지 숨어 있다.
    if (v.error) {
      reportBlocked(src);
      return;
    }
    if (v.readyState >= 2) {
      const s = src;
      requestAnimationFrame(() => setFrameSrc(s));
    }
    if (v.readyState >= 3) reportReady();
  }, [showVideo, src]);

  // 형식은 정했는데 메타에 그 형식 파일이 없으면 포스터에 머문다.
  useEffect(() => {
    if (format && !posterOnly && src === null) reportError();
  }, [format, posterOnly, src]);

  // play prop → 재생/정지. muted 자동 재생이 거절되면(iOS 저전력) 포스터로.
  useEffect(() => {
    const v = videoRef.current;
    if (!v || !showVideo || src === null) return;
    if (play) {
      const p = v.play();
      if (p) {
        p.catch((err: unknown) => {
          if (err && typeof err === 'object' && (err as { name?: string }).name === 'NotAllowedError') reportBlocked(src);
        });
      }
    } else {
      v.pause();
    }
  }, [play, showVideo, src]);

  return (
    <div className={className} style={{ position: 'relative', width, height, ...style }} aria-hidden="true">
      {poster !== null && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={poster}
          alt=""
          draggable={false}
          decoding="async"
          fetchPriority={priority ? 'high' : undefined}
          style={{ ...FILL, opacity: posterVisible ? 1 : 0 }}
        />
      )}
      {showVideo && (
        <video
          key={src}
          ref={setVideo}
          src={src}
          muted
          playsInline
          disablePictureInPicture
          disableRemotePlayback
          loop={loop}
          preload={preload}
          tabIndex={-1}
          style={FILL}
          onCanPlay={() => {
            if (readyFired.current) return;
            readyFired.current = true;
            onReady?.();
          }}
          onLoadedData={() => {
            const s = src;
            requestAnimationFrame(() => setFrameSrc(s));
          }}
          onEnded={() => onEnded?.()}
          onError={() => {
            setFailedSrc(src);
            onError?.();
          }}
        />
      )}
    </div>
  );
});
