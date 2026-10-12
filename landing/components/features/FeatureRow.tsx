"use client";

import { useEffect, useRef, type CSSProperties } from "react";
import { ROW_TIMING } from "@/data/fixtures";
import { MQ_REDUCED, useBand, useNearViewport, useRevealOnce } from "@/lib/hooks";
import { Gridlines } from "@/components/ui/Gridlines";
import { Headline } from "@/components/ui/Headline";
import { Rail } from "./Rail";
import { RowCanvas, type RowCanvasSpec } from "./RowCanvas";

// 기능 엔진(SPEC §S4 4.0–4.1 · PLAN §3.5 · brief-v21 §3·§4) — 데이터(FeatureRowProps)만 받는다. 부르는 쪽은 server 섹션.
//
// 두 모드(mode):
//   row(v2 기능 행, 기본) : <article> + H3 · 576 캔버스(조각 렌더) · 바닥 빛 GlowGate · 행마다 스파인 토막 + 노드.
//   scene(v2.1 장면)      : <section class="scene-wash"> + H2(t-h3 크기) · '통째 렌더' 690 캔버스(크롭·페이드·노치 0) ·
//                           렌더 영역 = 장면 폭 46–94%(1440 에서 662–1352) 세로 가운데 · 글 열 12.5–42% 세로 가운데 ·
//                           무대 빛 .scene-glow 를 렌더 영역 가운데 늘 켠다(GlowGate 없음) · 스파인은 선만(늘 켜짐, 장면끼리 맞닿아
//                           이어진다) · 노드는 라벨 옆(조립 때 점등). 장면 높이 = max(760, 캔버스 높이 × k + 160).
// 공통:
//   · 문턱 1회: useRevealOnce(노드, ROW_TIMING.threshold = .68) — 노드가 화면 위에서 68svh 를 지나면 data-on(이후 고정).
//     마운트 때 이미 지나 있으면(해시·뒤로 가기) data-on + data-instant(전이 없이 완성). data-reveal-count 는 0 → 1 로 한 번만.
//   · 조립 모양은 전부 CSS(globals `.js [data-row]…` + 각 요소 --at): 노드 점등 → 트렁크 선 → 빈 창 → 내용 → 보조(1.3s).
//     JS 는 data 속성만 바꾼다(스크롤 리스너 0). 감속 모션·JS 없음은 CSS 가 처음부터 최종 상태.
//   · 렌더 <img> 는 화면 1,200px 안에 들어올 때 마운트(useNearViewport + <noscript> — DECISIONS D25-1).
//   · R3 의 ringFlash 만 Web Animations 로 한 번(감속·instant 면 생략).
// 배율 --k(캔버스 → 화면). 웹킷은 vw 가 든 tan(atan2()) 를 라디안으로 읽어 뒤집힌다 → 등록된 길이 --kw(globals @property)에 담아
//   px 로 굳힌 뒤 넣는다(DECISIONS D20-1).
//   row  : desk k = min(1, 46vw / 576)(1024 → .82) · tab 1
//   scene: desk k = min(1, .48·shell / 690)(1440 → 1 · 1024 → .71) · tab k = min(1, (100vw − 96) / 690)
// 클릭 대상 없음(포커스 대상 0). 선·점·노드·빛 aria-hidden, 렌더마다 alt.

export type { Box, CanvasItem, RowCanvasSpec, Stack } from "./RowCanvas";

export interface FeatureRowProps {
  id: `f-${string}`;
  /** 한글 라벨(t-kicker — 앱 레일·탭 이름) */
  kicker: string;
  /** 제목 lines(CB 의 ' / ' 위치) — row = H3, scene = H2(t-h3 크기) */
  title: readonly string[];
  body: string;
  /** 두 번째 박자: H4 + 본문(row 만) */
  sub?: { title: readonly string[]; body: string };
  /** t-small ink-3 한 줄 */
  note?: string;
  canvas: RowCanvasSpec;
  /** 기본 row. scene = v2.1 장면(통째 렌더) */
  mode?: "row" | "scene";
  /** scene: 첫 장면이면 스파인이 투명에서 시작한다 */
  railStart?: boolean;
}

/** 렌더 마운트 거리(DECISIONS D25-1). */
const NEAR_MARGIN = "1200px";

/** R3 빈 창 테두리 반짝임: 120ms 에 시작해 600ms 에 가장 밝고 1000ms 에 꺼진다(SPEC §S4 R3). */
const RING_FLASH = { delay: 120, duration: 880, peak: 480 / 880 } as const;

// ── row(v2) ────────────────────────────────────────────────────────────────────────────────────────────
const ROW_ROOT =
  // overflow-x:clip — 바닥 빛(렌더 합집합 × 1.3)·점 격자가 좁은 폭(1024)에서 화면 오른쪽 밖으로 나가 가로 넘침을 만들지 않게.
  "relative overflow-x-clip pt-10 phone:pb-12 tab:pb-14 desk:min-h-[560px] desk:pb-10 " +
  "[--k:1] desk:[--kw:46vw] desk:[--k:min(1,tan(atan2(var(--kw),576px)))] " +
  "desk:[--text-l:calc(50%_-_var(--shell)_*_.375)] desk:[--canvas-l:min(50%,calc(94%_-_576px_*_var(--k)))]";
const ROW_TEXT =
  "relative desk:ml-(--text-l) desk:w-[min(425px,calc(var(--canvas-l)_-_var(--text-l)_-_40px))] " +
  "tab:ml-16 tab:w-[min(576px,calc(100%_-_96px))] phone:ml-12 phone:mr-5";
const ROW_CANVAS = "relative desk:absolute desk:top-10 desk:left-(--canvas-l) tab:ml-16 tab:mt-10 phone:ml-12 phone:mr-5 phone:mt-8";

// ── scene(v2.1) ────────────────────────────────────────────────────────────────────────────────────────
const SCENE_ROOT =
  // overflow-x:clip — 무대 빛(지름 1,520)이 화면 오른쪽 밖으로 나가 가로 넘침을 만들지 않게(세로는 visible: 인접 장면으로 번져도 된다 — §4).
  "scene-wash relative overflow-x-clip phone:py-14 phone:[&:not(:first-of-type)]:border-t phone:border-line tab:py-20 " +
  "desk:flex desk:min-h-[max(760px,calc(var(--ch)_*_var(--k)_+_160px))] desk:flex-col desk:justify-center desk:py-20 " +
  "[--k:1] desk:[--kw:calc(var(--shell)_*_.48)] desk:[--k:min(1,tan(atan2(var(--kw),690px)))] " +
  "tab:[--kw:calc(100vw_-_96px)] tab:[--k:min(1,tan(atan2(var(--kw),690px)))] " +
  "desk:[--text-l:calc(50%_-_var(--shell)_*_.375)] desk:[--area-l:calc(50%_-_var(--shell)_*_.04)] desk:[--area-w:calc(var(--shell)_*_.48)]";
// 글 열: desk 12.5% ~ 렌더 영역 − 48(≤ 425 — 1440 에서 180–605) · tab 64 ~ · phone 48–(폭 − 20)
const SCENE_TEXT =
  "relative desk:ml-(--text-l) desk:w-[min(425px,calc(var(--area-l)_-_var(--text-l)_-_48px))] " +
  "tab:ml-16 tab:mr-8 phone:ml-12 phone:mr-5";
// 노드: 중심 x = 스파인(desk 50% − .40·shell · tab 32 · phone 20) — 글 열 왼쪽 기준으로 되짚는다. 중심 y = 라벨 가운데(7).
const SCENE_NODE =
  "node absolute top-[-5px] desk:left-[calc(var(--shell)_*_-.025_-_11.5px)] tab:left-[-43.5px] " +
  "phone:top-[-3px] phone:left-[-37.5px] phone:size-5";
// 렌더 영역: desk = 장면 폭 46–94% 세로 가운데(absolute) · tab = 글 아래 가운데 · phone = 글 아래 세로 묶음.
// isolate — .scene-glow(z-index −1)가 이 상자 안에서 렌더 뒤·장면 워시 위에 깔린다.
const SCENE_AREA =
  "relative isolate flex justify-center desk:absolute desk:top-1/2 desk:left-(--area-l) desk:w-(--area-w) desk:-translate-y-1/2 " +
  "tab:mt-12 tab:ml-16 tab:mr-8 phone:mt-8 phone:ml-12 phone:mr-5 phone:block";

export function FeatureRow({ id, kicker, title, body, sub, note, canvas, mode = "row", railStart = false }: FeatureRowProps) {
  const rootRef = useRef<HTMLElement>(null);
  const nodeRef = useRef<HTMLSpanElement>(null);
  const markerRef = useRef<HTMLSpanElement>(null);

  const { on, instant } = useRevealOnce(nodeRef, ROW_TIMING.threshold);
  // 바닥 빛 GlowGate — row 만(scene 의 무대 빛은 늘 켜져 있다). 표식이 없으면 useBand 는 아무것도 하지 않는다.
  const glow = useBand(markerRef, ROW_TIMING.band);
  // 렌더 <img> 는 화면 1,200px 안으로 들어올 때 마운트(DECISIONS D25-1). 문턱(68svh)보다 1,200px 앞이라 조립이 시작될 때는
  // 이미 받아져 있다. 한 번 true 면 유지. 해시 진입은 첫 IO 콜백에서 true.
  const near = useNearViewport(rootRef, NEAR_MARGIN);

  // R3 ringFlash — 조립이 전이로 시작할 때 한 번(되감기 없음).
  useEffect(() => {
    if (!on || instant) return;
    const root = rootRef.current;
    if (!root || typeof window.matchMedia !== "function" || window.matchMedia(MQ_REDUCED).matches) return;
    const anims: Animation[] = [];
    root.querySelectorAll<HTMLElement>("[data-ring-flash]").forEach((el) => {
      if (typeof el.animate !== "function") return;
      anims.push(
        el.animate([{ opacity: 0 }, { opacity: 1, offset: RING_FLASH.peak }, { opacity: 0 }], {
          delay: RING_FLASH.delay,
          duration: RING_FLASH.duration,
          easing: "linear",
        }),
      );
    });
    return () => anims.forEach((a) => a.cancel());
  }, [on, instant]);

  const headingId = `${id}-h`;
  const state = {
    "data-row": "",
    "data-on": on ? "" : undefined,
    "data-instant": on && instant ? "" : undefined,
    "data-reveal-count": on ? 1 : 0,
  } as const;

  if (mode === "scene") {
    return (
      <section
        ref={rootRef}
        id={id}
        aria-labelledby={headingId}
        data-scene=""
        {...state}
        className={SCENE_ROOT}
        style={{ "--ch": `${canvas.height}px` } as CSSProperties}
      >
        <Rail bare start={railStart} />

        <div className={SCENE_TEXT}>
          {/* 노드 = 문턱 1회의 기준점(라벨 가운데 높이) */}
          <span ref={nodeRef} aria-hidden="true" className={SCENE_NODE} />
          <p className="t-kicker">{kicker}</p>
          <Headline level={2} size="h3" lines={title} id={headingId} className="mt-3" />
          <p className="t-body mt-5 text-ink-2">{body}</p>
          {note && <p className="t-small mt-3 text-ink-3">{note}</p>}
        </div>

        <div className={SCENE_AREA}>
          {/* 무대 빛(brief-v21 §4 — 반지름 760, 늘 켜짐). 모양은 globals .scene-glow(렌더 영역 가운데 · z-index −1) */}
          <div aria-hidden="true" className="scene-glow" />
          <RowCanvas mode="scene" spec={canvas} glow={false} mount={near} />
        </div>
      </section>
    );
  }

  return (
    <article ref={rootRef} id={id} aria-labelledby={headingId} {...state} className={ROW_ROOT}>
      {/* 세로 격자 10/50/90(SPEC §4 — 기능 행 1440 = 10/50/90, tab·phone 없음. requests/rows-b.md §2): 50% = 캔버스 왼쪽, 90% = 오른쪽 끝 */}
      <Gridlines />
      <Rail />
      {/* 노드 표식(노드 윗변 = 행 위 + 35) — 문턱 1회의 기준점 */}
      <span ref={nodeRef} aria-hidden="true" className="pointer-events-none absolute left-0 top-[35px] h-px w-px" />

      <div className={ROW_TEXT}>
        <p className="t-kicker">{kicker}</p>
        <Headline level={3} size="h3" lines={title} id={headingId} className="mt-3" />
        <p className="t-body mt-5 text-ink-2">{body}</p>
        {sub && (
          <>
            <Headline level={4} size="h4" lines={sub.title} className="mt-8" />
            <p className="t-body mt-3 text-ink-2">{sub.body}</p>
          </>
        )}
        {note && <p className="t-small mt-4 text-ink-3">{note}</p>}
      </div>

      <div className={ROW_CANVAS}>
        <RowCanvas spec={canvas} glow={glow} mount={near} />
        {/* 캔버스 가운데 표식 — 바닥 빛 GlowGate(화면 30–70% 띠) */}
        <span ref={markerRef} aria-hidden="true" className="pointer-events-none absolute left-0 top-1/2 h-px w-px" />
      </div>
    </article>
  );
}

export default FeatureRow;
