"use client";

// 아잉 한 마리(SPEC §S1 · §S8 · §5.5 · PLAN §3.4) — 히어로(도착)와 아웃트로(북엔드) 두 곳에서만 쓴다.
// 포스터 → (once 1회) → idle × maxLoops → 그 프레임에서 정지(포스터로 바꾸지 않는다 — 자세 튐 0).
// 클릭 없음(pointer-events:none), 전부 aria-hidden(같은 사실이 리드에 있다). 영상 움직임은 앱 렌더 30fps 그대로(CSS 변형 0).
//
// 루트 data 속성(수용 테스트·globals CSS 가 본다)
//   data-aing     늘
//   data-arrived  근무 라벨 켬 — once 시작 순간 · once 건너뜀(마감·오류) · once 없는 idle 시작 · posterOnly 즉시(이후 유지)
//   data-bubble   말풍선 보임 — once 시작 순간 붙고 BUBBLE_TEXT ms(5,000) 뒤 떨어진다 · posterOnly 면 즉시 붙고 떨어지지 않는다
//   data-stopped  idle 이 maxLoops 를 다 돌고 멈춤(또는 posterOnly 정지 상태 · idle 영상 실패)
//   data-instant  posterOnly(감속 모션·Save-Data — 영상 요청 0, 도착 뒤 상태로 정지)
//   ※ globals: `.js [data-aing]:not([data-arrived]) .aing-timer{opacity:0}` · `…:not([data-bubble]) .aing-bubble{opacity:0}`
//     — @media no-preference 안이라 감속 모션·JS 없음은 처음부터 말풍선·근무 라벨이 보인다(SSR 첫 페인트 = 최종 상태).
//
// 흐름
//   · 영상은 load + idle(afterLoadIdle) 뒤에만 만든다(로드 전 영상 요청 0 — SPEC §5.5). posterOnly 면 끝까지 만들지 않는다.
//   · once 층은 그때 바로 만들어 받아 둔다(preload auto). start 가 true 이고 once 가 재생 가능(canplay)이면 재생 → 도착.
//     start 는 '이제' 신호 — 한 번 true 가 되면 래치한다(false 로 되돌려도 되감기지 않는다).
//   · deadlineAt(performance.now() 기준)까지 once 가 재생 가능하지 않으면 once·말풍선을 건너뛰고 data-arrived 만 붙인 뒤
//     곧바로 idle(start 를 기다리지 않는다 — 히어로는 onArrive 로 빛 한 줄을 접는다). once 오류도 같은 길.
//   · idle 층은 once 가 시작될 때 만들어(받기 시작) idleResumeFrame(once 칸 수, …) 칸으로 미리 시크해 둔다 →
//     once 가 끝나면(ended, 감시 타이머) 층만 바꿔 이어 재생(이음매 0, TD §3). once 가 없으면 start 때 0번 칸부터.
//   · idle 은 loop=false 로 두고 ended 마다 loopsDone++ → shouldStop 이면 그 프레임에서 멈춤, 아니면 0번 칸으로 돌아가 다시.
//   · inView=false(보이는 비율 < .35)·탭 숨김(visibilitychange)이면 idle 일시정지, 돌아오면 남은 횟수만 이어서.
//   · 캐시된 <video> 는 React 커밋 전에 canplay 를 쏘고 지나간다 — 층을 만든 직후·마감 때 handle.ready(readyState)로 다시 본다.
//   · once 가 재생 가능해지면 onOnceReady 를 한 번 부른다 — 히어로는 그때부터 빛 한 줄을 출발시킨다(DECISIONS D28-1).
// 층 상자: 포스터·영상 = 아잉 상자(폭 width, 높이 = 폭 × 790/654) · 말풍선·근무 라벨 = heroLayer() 를 상자 비율(%)로
//   (CSS 길이 width 에 따라 함께 늘고 준다 — SSR 첫 페인트부터 제자리, 불투명만 바뀐다 → CLS 0).

import {
  useEffect,
  useEffectEvent,
  useRef,
  useState,
  useSyncExternalStore,
  type CSSProperties,
} from "react";
import { CORNER, HERO, asset } from "@/data/fixtures";
import { HERO_BOX, heroLayer, idleResumeFrame, shouldStop, type Rect } from "@/lib/aing";
import { afterLoadIdle, wantsLowFps } from "@/lib/media";
import { SpritePlayer, sequenceMeta, videoVariant, type SpritePlayerHandle } from "@/components/SpritePlayer";
import { Bubble, bubbleMs, bubbleSize, bubbleSrc } from "./Bubble";

export interface AingClipProps {
  /** CSS 길이, 예: 'var(--aing-w)'. 높이 = 폭 × 790/654 */
  width: string;
  poster: "char/aing-rest-poster" | "char/aing-idle-poster";
  /** start 때 한 번 재생할 반응(없으면 곧바로 idle) */
  once?: "aing-commute-start";
  /** 부모의 '이제' 신호(히어로: 빛 한 줄 끝 / 아웃트로: 45% 진입). false→true 한 번만 의미 */
  start: boolean;
  /** 기본 HERO.idleLoops = 2 → 끝나면 그 프레임에서 pause(포스터로 바꾸지 않음) */
  maxLoops?: number;
  /** 보이는 비율 ≥ .35 — false 면 idle pause, true 면 남은 횟수만 이어서 */
  inView: boolean;
  /** usePosterOnly() — true 면 영상 요청 0, data-arrived·data-bubble 즉시(해제하지 않음 = 감속 판 정지 상태) */
  posterOnly: boolean;
  /** once 시작과 같은 순간 data-bubble, BUBBLE_TEXT ms(5,000) 뒤 해제 */
  bubble?: "commute-start";
  /** 근무 라벨(ui/timer-00-00) — once 시작 순간 data-arrived(이후 유지) */
  timer?: boolean;
  /** performance.now() 기준 마감. 그때까지 once 가 canplay 가 아니면 once·bubble 건너뛰고 data-arrived 만 */
  deadlineAt?: number;
  onArrive?(): void;
  /** once 가 재생 가능(canplay · readyState)해진 순간 한 번 — 히어로는 이때부터 빛 한 줄을 출발시킨다(DECISIONS D28-1) */
  onOnceReady?(): void;
  onStop?(): void;
  className?: string;
}

// ─── 상자 비율(HERO 박스 654×790 기준 %) ─────────────────────────────────────────────────────────

const [OUT_W, OUT_H] = HERO_BOX.out;

/** heroLayer(654, …) 의 px 상자(d = 1)를 아잉 상자 기준 % 로. 순수 함수. */
function pct(r: Rect): CSSProperties {
  return {
    left: `${(r.left / OUT_W) * 100}%`,
    top: `${(r.top / OUT_H) * 100}%`,
    width: `${(r.width / OUT_W) * 100}%`,
    height: `${(r.height / OUT_H) * 100}%`,
  };
}

function layerBoxes(bubble: AingClipProps["bubble"]): { bubble: CSSProperties | null; timer: CSSProperties } {
  const unit = bubble ? bubbleSize(bubble, 1) : null; // = canvasPx × 0.5
  const canvas: readonly [number, number] = unit ? [unit.w * 2, unit.h * 2] : [0, 0];
  const L = heroLayer(OUT_W, canvas);
  return { bubble: unit ? pct(L.bubble) : null, timer: pct(L.timer) };
}

// lib/aing.ts 는 import 0 이라 CORNER 를 복사해 둔다 — 개발 모드에서 둘이 같은지 한 번 본다.
if (process.env.NODE_ENV !== "production") {
  const same = (a: readonly number[], b: readonly number[]) => a.length === b.length && a.every((v, i) => v === b[i]);
  if (
    !same(HERO_BOX.out, CORNER.heroOut) ||
    !same(HERO_BOX.bubbleAtOut, CORNER.bubbleAtOut) ||
    !same(HERO_BOX.capsuleAtOut, CORNER.capsuleAtOut) ||
    !same(HERO_BOX.capsuleSizeOut, CORNER.capsuleSizeOut)
  ) {
    console.warn("[AingClip] lib/aing.ts HERO_BOX 와 data/fixtures.ts CORNER 가 다르다 — 말풍선·근무 라벨 자리가 어긋난다.");
  }
}

/** 층 그림 주소를 CSS 변수 --art 로(감속 모션 첫 페인트용 배경 — globals). 순수 함수. */
function artVar(src: string | null | undefined): CSSProperties {
  return src ? ({ "--art": `url("${src}")` } as CSSProperties) : {};
}

// ─── 탭 숨김 ───────────────────────────────────────────────────────────────────────────────────

function subscribeVisibility(cb: () => void): () => void {
  document.addEventListener("visibilitychange", cb);
  return () => document.removeEventListener("visibilitychange", cb);
}
const docVisibleNow = () => document.visibilityState !== "hidden";
const docVisibleServer = () => true;

/** ended 가 오지 않을 때(재생 멈춤·디코드 정지) once 를 끝난 것으로 치는 여유. */
const WATCHDOG_EXTRA_MS = 1000;
/** 들어오는 영상이 첫 프레임을 알리지 않을 때(일시정지 상태로 층이 바뀜 등) 나가는 층을 내리는 상한. */
const SHOWN_SAFETY_MS = 300;
const IDLE = "aing-idle" as const;

export function AingClip({
  width,
  poster,
  once,
  start,
  maxLoops = HERO.idleLoops,
  inView,
  posterOnly,
  bubble,
  timer = false,
  deadlineAt,
  onArrive,
  onOnceReady,
  onStop,
  className,
}: AingClipProps) {
  const rootRef = useRef<HTMLDivElement>(null);
  const onceRef = useRef<SpritePlayerHandle>(null);
  const idleRef = useRef<SpritePlayerHandle>(null);
  const loopsRef = useRef(0);
  const playRef = useRef(false);
  const arriveCalled = useRef(false);
  const onceReadyCalled = useRef(false);
  const stopCalled = useRef(false);

  const docVisible = useSyncExternalStore(subscribeVisibility, docVisibleNow, docVisibleServer);

  // 클라에서만 바뀌는 상태 — 전부 콜백(RO·타이머·영상 이벤트·promise)에서만 바꾼다.
  const [w, setW] = useState(0); // 아잉 상자 실측 폭(px) — SpritePlayer 는 px 를 받는다
  const [loaded, setLoaded] = useState<{ lowFps: boolean } | null>(null); // afterLoadIdle 뒤
  const [layersOn, setLayersOn] = useState(false); // 말풍선·근무 라벨 렌더를 받아도 되는가(아래 효과)
  const [onceReady, setOnceReady] = useState(false);
  const [onceEnded, setOnceEnded] = useState(false);
  const [skipped, setSkipped] = useState(false);
  const [bubbleExpired, setBubbleExpired] = useState(false);
  const [idleReady, setIdleReady] = useState(false);
  const [seekDone, setSeekDone] = useState(false);
  const [idleFailed, setIdleFailed] = useState(false);
  const [stoppedState, setStoppedState] = useState(false);
  // 실제로 첫 프레임이 화면에 나온 층(아래 효과 — DECISIONS D22-1).
  const [shown, setShown] = useState<"poster" | "once" | "idle">("poster");
  // start 는 '이제' 신호 — 한 번 true 가 되면 래치한다(부모가 false 로 되돌려도 도착·idle 이 되감기지 않는다).
  // 렌더 중 조건부 setState(React 문서의 '이전 prop 에 맞춰 상태 고치기' 패턴) — 효과를 한 바퀴 돌리지 않는다.
  const [started, setStarted] = useState(false);
  if (start && !started) setStarted(true);
  const go = start || started;

  // ── 파생 ──
  const videosOK = !posterOnly && loaded !== null && w > 0;
  const onceWanted = !!once && !skipped;
  const onceActive = videosOK && onceWanted && go && onceReady && !onceEnded;
  const onceStarted = onceActive || onceEnded;
  const idleWanted = videosOK && !idleFailed && (onceEnded || ((!once || skipped) && (go || skipped)));
  // once 층은 idle 이 첫 프레임을 실제로 그린 뒤에 내린다(그 전에 지우면 틈이 생긴다 — D22-1).
  const onceMounted = videosOK && onceWanted && !(idleWanted && seekDone && shown === "idle");
  const idleMounted = videosOK && !idleFailed && (onceActive || idleWanted);
  const idleVisible = idleWanted && seekDone;
  const stopped = posterOnly || stoppedState || idleFailed || (idleVisible && shouldStop(0, maxLoops));
  const idlePlay = idleVisible && !stopped && inView && docVisible;
  const layer: "poster" | "once" | "idle" = idleVisible ? "idle" : onceStarted && videosOK ? "once" : "poster";
  const arrived = posterOnly || onceStarted || skipped || idleWanted;
  const bubbleOn = !!bubble && (posterOnly || (onceStarted && !bubbleExpired));

  // 실제로 프레임이 화면에 나온 층(DECISIONS D22-1 · requests/hero.md §1). 층이 바뀌어도 들어오는 영상이 첫 프레임을
  // 그리기 전까지(requestVideoFrameCallback, 없으면 playing + 2 rAF) 나가는 층을 덮어 둔다 — 포스터→once·once→idle·포스터→idle
  // 교체에서 아잉이 2–4프레임 사라지던 틈을 없앤다. 한 프레임 겹쳐도 같은 자세(once 0번 칸 = 포스터, idle 이어지는 칸 = once 끝 자세).
  useEffect(() => {
    if (layer === shown) return;
    if (layer === "poster") {
      // 영상 층이 사라졌다(오류) — 포스터는 늘 그려져 있으니 곧바로.
      const id = requestAnimationFrame(() => setShown("poster"));
      return () => cancelAnimationFrame(id);
    }
    const want = layer === "idle" ? /aing-idle/ : /commute/;
    const v = [...(rootRef.current?.querySelectorAll("video") ?? [])].find((x) => want.test(x.currentSrc || x.src));
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      setShown(layer);
    };
    const safety = window.setTimeout(finish, SHOWN_SAFETY_MS);
    let raf = 0;
    const onPlaying = () => {
      raf = requestAnimationFrame(() => {
        raf = requestAnimationFrame(finish);
      });
    };
    if (v && typeof v.requestVideoFrameCallback === "function") v.requestVideoFrameCallback(() => finish());
    else if (v) v.addEventListener("playing", onPlaying, { once: true });
    else raf = requestAnimationFrame(finish);
    return () => {
      done = true;
      window.clearTimeout(safety);
      cancelAnimationFrame(raf);
      v?.removeEventListener("playing", onPlaying);
    };
  }, [layer, shown]);
  const posterShown = layer === "poster" || shown === "poster";
  const onceShown = layer === "once" || (layer === "idle" && shown === "once");

  // 아잉 상자 폭 실측(첫 콜백은 observe 직후).
  useEffect(() => {
    const el = rootRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver((entries) => {
      const en = entries[entries.length - 1];
      if (en) setW(Math.round(en.contentRect.width * 100) / 100);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // 말풍선·근무 라벨 렌더 파일은 load + idle 뒤에 받는다(SPEC §5.1 첫 화면 목록 밖 · §5.2-2 'load + idle: 히어로 말풍선·근무 라벨').
  // 도착 전에는 어차피 불투명 0 이라 보이는 차이가 없다. posterOnly(감속·Save-Data)는 처음부터 최종 상태라 마운트 직후 받는다.
  const hasLayers = !!timer || !!bubble;
  useEffect(() => {
    if (!hasLayers) return;
    if (posterOnly) {
      const id = requestAnimationFrame(() => setLayersOn(true));
      return () => cancelAnimationFrame(id);
    }
    return afterLoadIdle(() => setLayersOn(true));
  }, [hasLayers, posterOnly]);

  // load + idle 뒤에만 영상 층을 만든다.
  useEffect(() => {
    if (posterOnly) return;
    return afterLoadIdle(() => setLoaded({ lowFps: wantsLowFps() }));
  }, [posterOnly]);

  // 캐시 함정: 층을 만든 직후 readyState 로 한 번 더 본다(React 가 커밋 전 canplay 를 버린다).
  const onceLayerUp = onceMounted && !!once;
  useEffect(() => {
    if (!onceLayerUp) return;
    const id = requestAnimationFrame(() => {
      if (onceRef.current?.ready) setOnceReady(true);
    });
    return () => cancelAnimationFrame(id);
  }, [onceLayerUp]);
  useEffect(() => {
    if (!idleMounted) return;
    const id = requestAnimationFrame(() => {
      if (idleRef.current?.ready) setIdleReady(true);
    });
    return () => cancelAnimationFrame(id);
  }, [idleMounted]);

  // 도착 마감.
  const onDeadline = useEffectEvent(() => {
    if (onceStarted || skipped) return;
    if (onceReady || onceRef.current?.ready) {
      setOnceReady(true);
      return;
    }
    setSkipped(true);
  });
  const hasOnce = !!once;
  useEffect(() => {
    if (!hasOnce || posterOnly || deadlineAt === undefined) return;
    const t = window.setTimeout(() => onDeadline(), Math.max(0, deadlineAt - performance.now()));
    return () => window.clearTimeout(t);
  }, [hasOnce, posterOnly, deadlineAt]);

  // once 감시 타이머 · 말풍선 해제 타이머.
  useEffect(() => {
    if (!onceActive || !once) return;
    const meta = sequenceMeta(once);
    const ms = meta ? (meta.frames / meta.fps) * 1000 : 1500;
    const t = window.setTimeout(() => setOnceEnded(true), ms + WATCHDOG_EXTRA_MS);
    return () => window.clearTimeout(t);
  }, [onceActive, once]);
  useEffect(() => {
    if (!onceStarted || !bubble || posterOnly) return;
    const t = window.setTimeout(() => setBubbleExpired(true), bubbleMs(bubble) || HERO.bubbleMs);
    return () => window.clearTimeout(t);
  }, [onceStarted, bubble, posterOnly]);

  // idle 을 이어질 칸으로 미리 시크(once 중) 또는 0번 칸(once 없음·건너뜀) → 끝나면 보일 수 있다.
  const seekTarget = (onceActive || onceEnded) && once ? "resume" : "zero";
  useEffect(() => {
    if (!idleMounted || !idleReady || seekDone || !loaded) return;
    const h = idleRef.current;
    if (!h) return;
    let target = 0;
    const idleMeta = sequenceMeta(IDLE);
    const onceMeta = once ? sequenceMeta(once) : null;
    if (seekTarget === "resume" && idleMeta && idleMeta.kind === "video" && onceMeta) {
      const v = videoVariant(idleMeta, loaded.lowFps);
      target = idleResumeFrame(onceMeta.frames, idleMeta.frames, idleMeta.fps, v.fps, v.frames);
    }
    let alive = true;
    void h.seekToFrame(target).then(() => {
      if (alive) setSeekDone(true);
    });
    return () => {
      alive = false;
    };
  }, [idleMounted, idleReady, seekDone, loaded, seekTarget, once]);

  // ended 콜백이 최신 재생 의사를 읽게.
  useEffect(() => {
    playRef.current = idlePlay;
  });

  // 알림(한 번씩).
  useEffect(() => {
    if (!arrived || arriveCalled.current) return;
    arriveCalled.current = true;
    onArrive?.();
  }, [arrived, onArrive]);
  useEffect(() => {
    if (!once || !onceReady || skipped || onceReadyCalled.current) return;
    onceReadyCalled.current = true;
    onOnceReady?.();
  }, [once, onceReady, skipped, onOnceReady]);
  useEffect(() => {
    if (!stopped || stopCalled.current) return;
    stopCalled.current = true;
    onStop?.();
  }, [stopped, onStop]);

  const onIdleEnded = () => {
    loopsRef.current += 1;
    if (shouldStop(loopsRef.current, maxLoops)) {
      setStoppedState(true);
      return;
    }
    const h = idleRef.current;
    if (!h) return;
    void h.seekToFrame(0).then(() => {
      if (playRef.current) void h.play();
    });
  };

  const onOnceError = () => {
    if (onceStarted) setOnceEnded(true);
    else setSkipped(true);
  };

  const boxes = layerBoxes(bubble);
  const posterMeta = asset(poster);
  if (!posterMeta && process.env.NODE_ENV !== "production") {
    console.warn(`[AingClip] assets.json 에 '${poster}' 키가 없어요 — 포스터 없이 그립니다.`);
  }
  const eagerPoster = poster === "char/aing-rest-poster"; // 히어로(phone LCP 후보) — layout 의 preload 와 같은 URL
  const timerMeta = timer ? asset("ui/timer-00-00") : undefined;
  const timerImg = (
    // eslint-disable-next-line @next/next/no-img-element -- next/image 를 쓰지 않는다(이미지 최적화 끔)
    <img
      src={timerMeta?.src}
      alt=""
      width={264}
      height={120}
      decoding="async"
      draggable={false}
      style={{ display: "block", width: "100%", height: "100%", maxWidth: "none" }}
    />
  );
  const bubbleEl = bubble ? <Bubble id={bubble} scale={1} visible static style={{ width: "100%", height: "100%" }} /> : null;
  const layerStyle = (on: boolean): CSSProperties => ({ position: "absolute", left: 0, top: 0, opacity: on ? 1 : 0 });

  return (
    <div
      ref={rootRef}
      aria-hidden="true"
      data-aing=""
      data-arrived={arrived ? "" : undefined}
      data-bubble={bubbleOn ? "" : undefined}
      data-stopped={stopped ? "" : undefined}
      data-instant={posterOnly ? "" : undefined}
      className={className}
      style={{ position: "relative", width, aspectRatio: `${OUT_W} / ${OUT_H}`, pointerEvents: "none" }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- next/image 를 쓰지 않는다(이미지 최적화 끔) */}
      <img
        src={posterMeta?.src}
        alt=""
        width={OUT_W}
        height={OUT_H}
        decoding="async"
        loading={eagerPoster ? "eager" : "lazy"}
        fetchPriority={eagerPoster ? "high" : undefined}
        draggable={false}
        className="aing-poster"
        style={{
          position: "absolute",
          inset: 0,
          display: "block",
          width: "100%",
          height: "100%",
          maxWidth: "none",
          opacity: posterShown ? 1 : 0,
        }}
      />

      {onceMounted && once && (
        <SpritePlayer
          ref={onceRef}
          name={once}
          play={onceActive}
          displayWidth={w}
          loop={false}
          preload="auto"
          onReady={() => setOnceReady(true)}
          onEnded={() => setOnceEnded(true)}
          onError={onOnceError}
          style={layerStyle(onceShown)}
        />
      )}

      {idleMounted && loaded && (
        <SpritePlayer
          ref={idleRef}
          name={IDLE}
          play={idlePlay}
          displayWidth={w}
          loop={false}
          lowFps={loaded.lowFps}
          preload="auto"
          onReady={() => setIdleReady(true)}
          onEnded={onIdleEnded}
          onError={() => setIdleFailed(true)}
          style={layerStyle(layer === "idle")}
        />
      )}

      {timer && (
        // 상자(.aing-timer)는 SSR 부터 제자리(CLS 0) — 렌더 파일은 layersOn 뒤에 받는다. JS 가 없으면 <noscript> 가 최종 상태를 낸다.
        // --art: 감속 모션에서만 globals 가 배경으로 그린다 — 하이드레이션 전 첫 페인트부터 최종 상태(review-motion P2-6). 기본 컨텍스트는 요청 0
        <span
          className="aing-timer"
          style={{ position: "absolute", display: "block", zIndex: 1, ...boxes.timer, ...artVar(timerMeta?.src) }}
        >
          {layersOn ? timerImg : <noscript>{timerImg}</noscript>}
        </span>
      )}

      {bubble && boxes.bubble && (
        <div className="aing-bubble" style={{ position: "absolute", zIndex: 2, ...boxes.bubble, ...artVar(bubbleSrc(bubble)) }}>
          {layersOn ? bubbleEl : <noscript>{bubbleEl}</noscript>}
        </div>
      )}
    </div>
  );
}

export default AingClip;
