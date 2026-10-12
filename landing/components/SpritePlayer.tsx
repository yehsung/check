'use client';

// 시퀀스 플레이어(PLAN §3.5). 캐릭터 알파 영상(video)과 틱 띠(sheet)를 같은 메타 형식으로 재생한다.
// 메타는 data/generated/sequences.json(assets 에이전트가 쓴다)을 느슨한 타입으로 읽는다(DECISIONS §4).
// 메타가 없거나 모양이 틀리면 개발 모드 console.warn + 아무것도 그리지 않는다(빌드가 깨지지 않게).

import { forwardRef, type CSSProperties } from 'react';
import sequencesJson from '@/data/generated/sequences.json';
import type { SequenceName } from '@/data/fixtures';
import { pickVideoFormat, preloadImage, wantsLowFps } from '@/lib/media';
import { AlphaVideo, type AlphaVideoSources } from './sprite/AlphaVideo';
import { SheetPlayer } from './sprite/SheetPlayer';

// 이름 목록은 fixtures(core)가 정본이다 — 여기서는 PLAN §3.5 서명대로 다시 내보낸다.
export type { SequenceName };

export interface SpritePlayerHandle {
  play(): Promise<void>;
  pause(): void;
  seekToFrame(n: number): Promise<void>;
  readonly ready: boolean;
}

export interface SpritePlayerProps {
  name: SequenceName;
  /** true 면 재생(loop 이면 계속), false 면 현재 프레임 정지 */
  play: boolean;
  /** sheet 백엔드: 보여 줄 칸(외부 제어). video: 무시 */
  frame?: number;
  /** CSS px. 높이는 메타 비율 */
  displayWidth: number;
  /** 메타 기본값 덮어쓰기 */
  loop?: boolean;
  /** 메타에 15fps 판(low)이 있으면 그것 */
  lowFps?: boolean;
  /** 감속 모션·Save-Data·오류 → 포스터 <img> 만, 영상 요청 0건 */
  posterOnly?: boolean;
  preload?: 'none' | 'metadata' | 'auto';
  /** 포스터 fetchpriority="high" */
  priority?: boolean;
  onReady?: () => void;
  onEnded?: () => void;
  onError?: () => void;
  className?: string;
  style?: CSSProperties;
}

export interface VideoVariant {
  fps: number;
  frames: number;
  src: AlphaVideoSources;
}

export interface VideoSequenceMeta {
  kind: 'video';
  fps: number;
  frames: number;
  loop: boolean;
  canvas?: string;
  box?: readonly [number, number, number, number];
  scale?: number;
  /** 출력 px(HERO 박스 기준 654×790 등) */
  size: readonly [number, number];
  /** 이 시퀀스 박스 원점 − HERO 박스 원점(출력 px). HERO 박스와 같으면 [0,0], 울트라는 null */
  offsetOut: readonly [number, number] | null;
  gop?: number;
  src: AlphaVideoSources;
  low: VideoVariant | null;
  poster: string | null;
  posterFrame?: number;
}

export interface SheetSequenceMeta {
  kind: 'sheet';
  fps: number;
  frames: number;
  loop: boolean;
  hold?: string;
  src: string;
  frameSize: readonly [number, number];
  cols: number;
  rows: number;
  displayPt?: readonly [number, number];
}

export type SequenceMeta = VideoSequenceMeta | SheetSequenceMeta;

// ---------------------------------------------------------------------------
// 메타 읽기(느슨한 JSON → 검사한 타입)

type Loose = Record<string, unknown>;
const isObj = (v: unknown): v is Loose => typeof v === 'object' && v !== null && !Array.isArray(v);
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isPair = (v: unknown): v is [number, number] => Array.isArray(v) && v.length >= 2 && isNum(v[0]) && isNum(v[1]);
const isQuad = (v: unknown): v is [number, number, number, number] =>
  Array.isArray(v) && v.length >= 4 && v.slice(0, 4).every(isNum);

function readSources(v: unknown): AlphaVideoSources | null {
  if (!isObj(v)) return null;
  const out: AlphaVideoSources = {};
  if (typeof v.webm === 'string' && v.webm) out.webm = v.webm;
  if (typeof v.mov === 'string' && v.mov) out.mov = v.mov;
  return out.webm || out.mov ? out : null;
}

/** sequences.json 의 항목 하나를 검사해 타입으로 바꾼다. 틀리면 null. 순수 함수. */
export function parseSequenceMeta(raw: unknown): SequenceMeta | null {
  if (!isObj(raw)) return null;
  const fps = raw.fps;
  const frames = raw.frames;
  if (!isNum(fps) || fps <= 0 || !isNum(frames) || frames <= 0) return null;
  const loop = raw.loop === true;

  if (raw.kind === 'sheet') {
    if (typeof raw.src !== 'string' || !raw.src || !isPair(raw.frameSize)) return null;
    const cols = isNum(raw.cols) && raw.cols > 0 ? raw.cols : frames;
    const rows = isNum(raw.rows) && raw.rows > 0 ? raw.rows : 1;
    return {
      kind: 'sheet',
      fps,
      frames,
      loop,
      hold: typeof raw.hold === 'string' ? raw.hold : undefined,
      src: raw.src,
      frameSize: [raw.frameSize[0], raw.frameSize[1]],
      cols,
      rows,
      displayPt: isPair(raw.displayPt) ? [raw.displayPt[0], raw.displayPt[1]] : undefined,
    };
  }

  if (raw.kind !== 'video') return null;
  const src = readSources(raw.src);
  if (!src || !isPair(raw.size) || raw.size[0] <= 0 || raw.size[1] <= 0) return null;
  let low: VideoVariant | null = null;
  if (isObj(raw.low) && isNum(raw.low.fps) && raw.low.fps > 0 && isNum(raw.low.frames) && raw.low.frames > 0) {
    const lowSrc = readSources(raw.low.src);
    if (lowSrc) low = { fps: raw.low.fps, frames: raw.low.frames, src: lowSrc };
  }
  return {
    kind: 'video',
    fps,
    frames,
    loop,
    canvas: typeof raw.canvas === 'string' ? raw.canvas : undefined,
    box: isQuad(raw.box) ? [raw.box[0], raw.box[1], raw.box[2], raw.box[3]] : undefined,
    scale: isNum(raw.scale) ? raw.scale : undefined,
    size: [raw.size[0], raw.size[1]],
    offsetOut: isPair(raw.offsetOut) ? [raw.offsetOut[0], raw.offsetOut[1]] : null,
    gop: isNum(raw.gop) ? raw.gop : undefined,
    src,
    low,
    poster: typeof raw.poster === 'string' && raw.poster ? raw.poster : null,
    posterFrame: isNum(raw.posterFrame) ? raw.posterFrame : undefined,
  };
}

const FILE: unknown = sequencesJson;
const RAW_SEQUENCES: Loose = isObj(FILE) && isObj(FILE.sequences) ? FILE.sequences : {};
const parsed = new Map<string, SequenceMeta | null>();
const warned = new Set<string>();

function devWarn(key: string, msg: string): void {
  if (process.env.NODE_ENV === 'production' || warned.has(key)) return;
  warned.add(key);
  console.warn(msg);
}

/** 시퀀스 메타. 없거나 모양이 틀리면 null(개발 모드 경고 1회). */
export function sequenceMeta(name: SequenceName): SequenceMeta | null {
  if (parsed.has(name)) return parsed.get(name) ?? null;
  const raw = RAW_SEQUENCES[name];
  const meta = raw === undefined ? null : parseSequenceMeta(raw);
  if (!meta) {
    devWarn(
      `seq:${name}`,
      raw === undefined
        ? `[SpritePlayer] data/generated/sequences.json 에 '${name}' 메타가 없다 — 아무것도 그리지 않는다.`
        : `[SpritePlayer] '${name}' 메타 모양이 PLAN §3.5 와 다르다 — 아무것도 그리지 않는다.`,
    );
  }
  parsed.set(name, meta);
  return meta;
}

/** lowFps 이고 15fps 판이 있으면 그 판, 아니면 기본 판. 순수 함수. */
export function videoVariant(meta: VideoSequenceMeta, lowFps: boolean): VideoVariant {
  if (lowFps && meta.low) return meta.low;
  return { fps: meta.fps, frames: meta.frames, src: meta.src };
}

/** 표시 높이(CSS px). 순수 함수. */
export function sequenceDisplayHeight(meta: SequenceMeta, displayWidth: number): number {
  const [w, h] = meta.kind === 'video' ? meta.size : meta.frameSize;
  return (displayWidth * h) / w;
}

// ---------------------------------------------------------------------------
// 미리 받기

const inflight = new Map<string, Promise<void>>();

function once(key: string, job: () => Promise<unknown>): Promise<void> {
  const hit = inflight.get(key);
  if (hit) return hit;
  const p = job().then(
    () => undefined,
    () => {
      inflight.delete(key); // 실패하면 다음에 다시 시도할 수 있게
    },
  );
  inflight.set(key, p);
  return p;
}

/** 지금 이 순간 감속 모션·Save-Data 인가(훅이 아닌 곳에서 영상 요청을 막는 데 쓴다). */
function posterOnlyNow(): boolean {
  if (typeof window === 'undefined') return true;
  const reduce = typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const conn = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection;
  return reduce || conn?.saveData === true;
}

/**
 * 시퀀스를 미리 받는다. 포스터는 decode 까지, 영상은 고른 형식 파일 하나를 HTTP 캐시에 받아 둔다.
 * 감속 모션·Save-Data 이면 영상은 받지 않는다(SPEC §2.7 "캐릭터 영상 요청 0건"). 실패해도 reject 하지 않는다.
 */
export function preloadSequence(name: SequenceName, lowFps?: boolean): Promise<void> {
  if (typeof window === 'undefined') return Promise.resolve();
  const meta = sequenceMeta(name);
  if (!meta) return Promise.resolve();
  const jobs: Promise<void>[] = [];
  if (meta.kind === 'sheet') {
    const src = meta.src;
    jobs.push(once(src, () => preloadImage(src)));
  } else {
    const poster = meta.poster;
    if (poster) jobs.push(once(poster, () => preloadImage(poster)));
    if (!posterOnlyNow()) {
      const variant = videoVariant(meta, lowFps ?? wantsLowFps());
      const fmt = pickVideoFormat();
      const src = variant.src[fmt];
      // .mov(사파리)는 미리 받지 않는다 — WebKit 네트워크 캐시는 미디어(Range) 요청을 캐시에서 내주지 않아, fetch 로 받아 둔 파일을
      // <video> 가 처음부터 다시 받는다(영상 바이트 ≈1.6배). 사파리는 반응 때 받고, 600ms 안에 준비되지 않으면 말풍선만(SPEC S1).
      if (src && fmt !== 'mov') {
        jobs.push(
          once(src, () =>
            fetch(src, { priority: 'low' }).then((r) => (r.ok ? r.blob() : Promise.reject(new Error(String(r.status))))),
          ),
        );
      }
    }
  }
  return Promise.all(jobs).then(
    () => undefined,
    () => undefined,
  );
}

// ---------------------------------------------------------------------------
// 컴포넌트

export const SpritePlayer = forwardRef<SpritePlayerHandle, SpritePlayerProps>(function SpritePlayer(props, ref) {
  const {
    name,
    play,
    frame,
    displayWidth,
    loop,
    lowFps = false,
    posterOnly = false,
    preload = 'metadata',
    priority,
    onReady,
    onEnded,
    onError,
    className,
    style,
  } = props;

  const meta = sequenceMeta(name);
  if (!meta) return null;

  if (meta.kind === 'sheet') {
    return (
      <SheetPlayer
        ref={ref}
        src={meta.src}
        cols={meta.cols}
        rows={meta.rows}
        frames={meta.frames}
        fps={meta.fps}
        frameSize={meta.frameSize}
        displayWidth={displayWidth}
        frame={frame}
        play={play}
        loop={loop ?? meta.loop}
        onReady={onReady}
        onEnded={onEnded}
        className={className}
        style={style}
      />
    );
  }

  const variant = videoVariant(meta, lowFps);
  return (
    <AlphaVideo
      ref={ref}
      sources={variant.src}
      poster={meta.poster}
      fps={variant.fps}
      frames={variant.frames}
      width={displayWidth}
      height={sequenceDisplayHeight(meta, displayWidth)}
      play={play}
      loop={loop ?? meta.loop}
      posterOnly={posterOnly}
      preload={preload}
      priority={priority}
      onReady={onReady}
      onEnded={onEnded}
      onError={onError}
      className={className}
      style={style}
    />
  );
});

export default SpritePlayer;
