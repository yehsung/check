import type { CSSProperties, ReactElement } from "react";
import type { AssetKey } from "@/data/fixtures";
import { Bubble, bubbleSize, type BubbleKey } from "@/components/ui/Bubble";
import { FloorLight } from "@/components/ui/FloorLight";
import { PhoneShell, PHONE_SCREEN_RATIO } from "@/components/ui/PhoneShell";
import { RenderImage, fadeMask, type Fade } from "@/components/ui/RenderImage";
import { Tile } from "@/components/ui/Tile";
import { Wire } from "@/components/ui/Wire";

// 기능 캔버스(SPEC §S4 4.1–4.2 · brief-v21 §3·§4) — 'use client' 없음·훅 없음(데이터만 받아 그리는 순수 렌더).
// FeatureRow(client)가 그리고, 켜짐(data-on·data-instant)과 바닥 빛(glow)은 FeatureRow 가 정한다.
//
// 두 모드:
//   row(v2 기능 행)   : 576 폭 캔버스 · 조각 렌더(가장자리 페이드·노치) · 바닥 빛(GlowGate) · 점 격자 · 타일.
//   scene(v2.1 장면)  : '통째 렌더' — 690 폭 캔버스(1440 에서 렌더 영역 46–94% = 691px) · 크롭·페이드·노치 0 · 창은 --r-window +
//                       --shadow-window 그대로 · 바닥 빛·점 격자·타일 없음(무대 빛 .scene-glow 는 FeatureRow 가 렌더 영역에 늘 켜 둔다).
//                       선은 트렁크 1 + 가지 1. 렌더 안을 가리는 마스크는 어디에도 없다.
// 좌표 = 캔버스 px (x, y, w, h). 배치:
//   폭 ≥ 768: 캔버스 폭(--cw) × height 판에 절대 배치 → transform: scale(--k)(왼쪽 위 기준) + 바깥 상자 크기 보정.
//             --k 는 FeatureRow 가 준다(row: 1440 = 1 · 1024 = .82 / scene: 1440 = 1 · 1024 = .71 · tab = 폭에 맞춤).
//   phone(< 768): 캔버스 대신 세로 묶음 — 주 렌더(row ≤ 322 · scene min(100%, 340)) → 세로 선 24 → 보조들.
//             scene 의 보조는 stack 힌트로 폭(w)과 자리(before = 주 렌더 위)를 정한다. 선·접합점·타일·점 격자는 숨긴다.
//             같은 DOM 을 CSS 만으로 다시 배치(하이드레이션 어긋남 0).
// 조립 타임라인은 각 요소의 --at(ms) + globals 의 `.js [data-row]…` 규칙이 그린다(문턱 t=0):
//   선 = --at 에 200ms 그리기 · 주 렌더 = 빈 창(--surface + --shadow-window) --at 에 들고 440ms 에 내용 페이드
//   · 타일 = 360ms 팝 · 보조·말풍선 = --at 에 불투명 + 8px 올라옴 · 점 격자 = 900ms · 교체(.swap-to) = --swap-at.
// 렌더 <img> 는 mount(FeatureRow 의 useNearViewport — 화면 1,200px 안) 뒤에만 그린다(DECISIONS D25-1 — 첫 화면 예산).
//   그 전에는 <noscript> 안에 같은 그림(JS 없음 = 최종 상태). 상자(.row-item 의 --bw·--bh·aspect)는 처음부터 제자리 → CLS 0.
// 말풍선은 페이지 크롬이라 aria-hidden(같은 사실이 패널 alt·본문에 있다 — DECISIONS D26-3).

export type Box = readonly [x: number, y: number, w: number, h: number];

/** phone 세로 묶음 힌트(scene 모드): w = 표시 폭 상한(px, 기본 150) · before = 주 렌더 위에 둔다(예: 팝오버 위 메뉴바 라벨). */
export type Stack = { w?: number; before?: boolean };

export type CanvasItem =
  | {
      kind: "main";
      asset: AssetKey;
      alt: string;
      box: Box;
      at: number;
      fade?: Fade;
      swapTo?: { asset: AssetKey; alt: string; at: number };
      ringFlash?: boolean;
    }
  | { kind: "child"; asset: AssetKey; alt: string; box: Box; at: number; fade?: Fade; stack?: Stack }
  | { kind: "bubble"; bubble: BubbleKey; box: Box; at: number; stack?: Stack }
  | { kind: "phone"; screen: AssetKey; alt: string; box: Box; screenWidth: number; at: number }
  | { kind: "junction"; point: readonly [number, number]; at: number };

export interface RowCanvasSpec {
  /** 캔버스 높이(px) — row ≤ 480, scene ≤ 680 */
  height: number;
  items: readonly CanvasItem[];
  wires: readonly { d: string; at: number }[];
  tile?: { box: readonly [number, number]; icon: AssetKey; bare?: boolean };
  /** row 모드 바닥 빛: 폭 = 캔버스 안 렌더들의 합집합 폭(타원은 × 1.3 — DECISIONS D19-1·D20-2), top = 캔버스 위에서의 거리.
   *  왼쪽 끝은 첫 주 렌더의 왼쪽 끝에 맞춘다. scene 모드는 쓰지 않는다(무대 빛 .scene-glow 가 늘 켜져 있다) */
  floor?: { width: number; top: number };
}

export type CanvasMode = "row" | "scene";

export interface RowCanvasProps {
  spec: RowCanvasSpec;
  /** row 모드 바닥 빛 GlowGate(FeatureRow 의 useBand). scene 모드는 무시 */
  glow: boolean;
  /** 렌더 <img> 를 그려도 되는가(FeatureRow 의 useNearViewport 1,200px — DECISIONS D25-1). false 면 <noscript> 폴백만. 기본 true */
  mount?: boolean;
  /** 기본 row */
  mode?: CanvasMode;
}

/** row 캔버스 기준 폭(px). 1440 에서 50–90% 열 = 576. */
export const CANVAS_W = 576;
/** scene 캔버스 기준 폭(px). 1440 에서 렌더 영역 46–94% = 691.2 → 690(배율이 1 아래로 떨어지지 않게). */
export const SCENE_CANVAS_W = 690;
/** 타일 팝 시작(SPEC §S4 4.1 — 360ms, globals 의 .tile 전이 지연과 같다). */
const TILE_AT = 360;

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

/** 알파(투명 모서리)가 구워진 렌더 — 창 상자(배경·그림자·반경)를 두르지 않는다. */
const ALPHA_PREFIX = ["ios/widget-", "brand/", "ui/menubar-", "ui/bubble-", "char/", "ui/timer-"] as const;
const hasAlpha = (a: AssetKey) => ALPHA_PREFIX.some((p) => a.startsWith(p));

/** 렌더 창 상자: --r-window + --surface(빈 창) + --shadow-window.
 *  row 모드에서 페이드가 있으면 마스크(바깥 그림자는 마스크에 잘리므로 안쪽 1px 테두리만). 왼쪽 페이드 = 크롭이 자른 쪽 → 그 변은 직각
 *  (DECISIONS D27-3). scene 모드는 페이드를 받지 않는다 — 창은 언제나 통째(둥근 모서리 넷 + 그림자). */
function windowStyle(asset: AssetKey, fade: Fade | undefined, mode: CanvasMode): CSSProperties {
  if (hasAlpha(asset)) return {};
  const mask = mode === "row" ? fadeMask(fade) : undefined;
  if (mask) {
    return {
      borderRadius: fade?.left ? "0 var(--r-window) var(--r-window) 0" : "var(--r-window)",
      background: "var(--surface)",
      boxShadow: "inset 0 0 0 1px rgba(255,255,255,.07)",
      ...mask,
    };
  }
  return { borderRadius: "var(--r-window)", background: "var(--surface)", boxShadow: "var(--shadow-window)" };
}

/** 상자 → CSS 변수(폭 ≥ 768 절대 배치 · phone 비율 · scene 보조 폭). */
function boxVars(box: Box, at: number, stack?: Stack): CSSProperties {
  const [x, y, w, h] = box;
  return {
    "--bx": `${x}px`,
    "--by": `${y}px`,
    "--bw": `${w}px`,
    "--bh": `${h}px`,
    "--ar": `${w} / ${h}`,
    "--at": `${at}ms`,
    ...(stack?.w ? { "--sw": `${stack.w}px` } : null),
  } as CSSProperties;
}

// 폭 ≥ 768: 캔버스 px 그대로 절대 배치 / phone: 흐름 배치.
//   row  : primary = 주 렌더 자리 폭 ≤ 322 · child = 아래 줄 폭 ≤ 150(SPEC §S4 390 — 322 = 390 − 좌우 여백 48·20)
//   scene: primary = min(100%, 340) · child = min(100%, stack.w ?? 150) · before = 주 렌더 위(order −1, 아래 여백 12)
const PLACE = "min-[768px]:absolute min-[768px]:left-(--bx) min-[768px]:top-(--by) min-[768px]:w-(--bw) min-[768px]:h-(--bh)";
const PHONE_PRIMARY: Record<CanvasMode, string> = {
  row: "phone:relative phone:order-0 phone:w-[min(100%,322px)] phone:aspect-(--ar)",
  scene: "phone:relative phone:order-0 phone:w-[min(100%,340px)] phone:aspect-(--ar)",
};
const PHONE_CHILD: Record<CanvasMode, string> = {
  row: "phone:relative phone:order-3 phone:w-[min(150px,var(--bw))] phone:aspect-(--ar)",
  scene: "phone:relative phone:order-3 phone:w-[min(100%,var(--sw,150px))] phone:aspect-(--ar)",
};
const PHONE_BEFORE = "phone:relative phone:order-[-1] phone:mb-3 phone:basis-full phone:max-w-(--sw,150px) phone:aspect-(--ar)";

type Placed = Exclude<CanvasItem, { kind: "junction" }>;

/** 렌더 <img> 를 mount 뒤에만(그 전엔 <noscript> — JS 없음은 처음부터 그림). */
const lazy = (mount: boolean, el: ReactElement): ReactElement => (mount ? el : <noscript>{el}</noscript>);

const stackOf = (item: Placed): Stack | undefined =>
  item.kind === "child" || item.kind === "bubble" ? item.stack : undefined;

function childPlace(item: Placed, mode: CanvasMode): string {
  const stack = stackOf(item);
  if (mode === "scene" && stack?.before) return PHONE_BEFORE;
  return PHONE_CHILD[mode];
}

function renderItem(item: Placed, i: number, primary: boolean, mount: boolean, mode: CanvasMode) {
  const vars = boxVars(item.box, item.at, stackOf(item));
  const [, , w, h] = item.box;

  if (item.kind === "bubble") {
    const unit = bubbleSize(item.bubble, 1);
    return (
      <div key={i} className={cx("row-item", PLACE, childPlace(item, mode))} data-kind="bubble" aria-hidden="true" style={vars}>
        {lazy(
          mount,
          <Bubble
            id={item.bubble}
            scale={unit && unit.w > 0 ? w / unit.w : 1}
            visible
            static
            style={{ width: "100%", height: "100%" }}
          />,
        )}
      </div>
    );
  }

  if (item.kind === "phone") {
    return (
      <div
        key={i}
        className={cx("row-item", PLACE, primary ? "phone:relative phone:order-0" : "phone:relative phone:order-3")}
        data-kind="main"
        data-item="phone"
        style={vars}
      >
        <PhoneShell screenWidth={item.screenWidth}>
          {mode === "scene" ? (
            // 통째(brief-v21 요구 3): PhoneShell 의 직계 img 규칙(1% 확대 + object-fit cover — 가장자리 0.5% 가 잘린다)을 피해 한 겹 감싸고
            // 화면 상자에 꼭 맞춘다. 스틸 비율(600:1304 = .4601)이 화면 비율(402:874 = .4600)과 같아 늘어남 0
            <div className="absolute inset-0">
              {lazy(
                mount,
                <RenderImage
                  asset={item.screen}
                  widthPt={item.screenWidth}
                  heightPt={Math.round(item.screenWidth * PHONE_SCREEN_RATIO)}
                  alt={item.alt}
                  className="block size-full max-w-none"
                />,
              )}
            </div>
          ) : (
            lazy(
              mount,
              <RenderImage
                asset={item.screen}
                widthPt={item.screenWidth}
                heightPt={Math.round(item.screenWidth * PHONE_SCREEN_RATIO)}
                alt={item.alt}
              />,
            )
          )}
        </PhoneShell>
      </div>
    );
  }

  const place = primary ? PHONE_PRIMARY[mode] : childPlace(item, mode);
  const img = "block size-full max-w-none rounded-[inherit]";

  if (item.kind === "main") {
    return (
      <div
        key={i}
        className={cx("row-item", PLACE, place)}
        data-kind="main"
        style={{ ...vars, ...windowStyle(item.asset, item.fade, mode) }}
      >
        {lazy(mount, <RenderImage asset={item.asset} widthPt={w} heightPt={h} alt={item.alt} className={img} />)}
        {item.swapTo && (
          <div
            className="swap-to absolute inset-0 rounded-[inherit]"
            style={{ "--swap-at": `${item.swapTo.at}ms` } as CSSProperties}
          >
            {lazy(
              mount,
              <RenderImage asset={item.swapTo.asset} widthPt={w} heightPt={h} alt={item.swapTo.alt} className={img} />,
            )}
          </div>
        )}
        {item.ringFlash && (
          <span
            aria-hidden="true"
            data-ring-flash=""
            className="pointer-events-none absolute inset-0 rounded-[inherit] opacity-0"
            style={{ boxShadow: "var(--ring-lit)" }}
          />
        )}
      </div>
    );
  }

  // child
  return (
    <div
      key={i}
      className={cx("row-item", PLACE, place)}
      data-kind="child"
      style={{ ...vars, ...windowStyle(item.asset, item.fade, mode) }}
    >
      {lazy(mount, <RenderImage asset={item.asset} widthPt={w} heightPt={h} alt={item.alt} className={img} />)}
    </div>
  );
}

export function RowCanvas({ spec, glow, mount = true, mode = "row" }: RowCanvasProps) {
  const H = spec.height;
  const W = mode === "scene" ? SCENE_CANVAS_W : CANVAS_W;
  const placed = spec.items.filter((it): it is Placed => it.kind !== "junction");
  const junctions = spec.items.filter((it): it is Extract<CanvasItem, { kind: "junction" }> => it.kind === "junction");
  // phone 의 주 렌더 자리 = 첫 main/phone(그 밖은 아래 줄 보조). row 의 바닥 빛 왼쪽 끝도 이 렌더에 맞춘다.
  const primaryIndex = placed.findIndex((it) => it.kind === "main" || it.kind === "phone");
  const primary = primaryIndex >= 0 ? placed[primaryIndex] : undefined;
  // phone 세로 선 24 는 주 렌더 '아래' 보조가 있을 때만(scene 의 before 보조는 주 렌더 위라 선이 없다)
  const hasAfter = placed.some((it, i) => i !== primaryIndex && !(mode === "scene" && stackOf(it)?.before));
  const primaryBottom = primary ? primary.box[1] + primary.box[3] : 0;
  const floor = mode === "row" ? spec.floor : undefined;

  return (
    <div
      className="relative min-[768px]:w-[calc(var(--cw)*var(--k,1))] min-[768px]:h-[calc(var(--ch)*var(--k,1))]"
      data-row-canvas=""
      data-canvas-mode={mode}
      style={{ "--cw": `${W}px`, "--ch": `${H}px` } as CSSProperties}
    >
      <div
        className={cx(
          "min-[768px]:absolute min-[768px]:left-0 min-[768px]:top-0 min-[768px]:h-(--ch) min-[768px]:w-(--cw)",
          "min-[768px]:origin-top-left min-[768px]:[transform:scale(var(--k,1))]",
          "phone:relative phone:flex phone:flex-wrap phone:items-start phone:justify-center phone:gap-x-3",
        )}
      >
        {/* 점 격자(캔버스 뒤, inset −40 + 타원 마스크) — row 만, 조립 끝 900ms 에 페이드 */}
        {mode === "row" && <div aria-hidden="true" className="dots phone:hidden" />}

        {/* 바닥 빛(GlowGate, row 만) — desk·tab: 주 렌더 왼쪽 끝부터 floor.width 폭의 가운데 · phone: 주 렌더 바로 아래 */}
        {floor && (
          <div
            aria-hidden="true"
            className={cx(
              "pointer-events-none",
              "min-[768px]:absolute min-[768px]:top-0 min-[768px]:left-(--fx) min-[768px]:h-0 min-[768px]:w-(--fw)",
              "phone:relative phone:order-1 phone:h-0 phone:basis-full",
              // phone: 타원 폭 = 주 렌더 자리(≤ 322) × 1.1 — globals 의 × 1.3 을 .846 으로 되돌려 390 에서 화면 밖으로 나가지 않게
              "phone:[&>.floor-light]:top-(--fo)! phone:[&>.floor-light]:[--w:calc(min(100%,322px)*.846)]!",
            )}
            style={
              {
                "--fx": `${primary ? primary.box[0] : 0}px`,
                "--fw": `${floor.width}px`,
                "--fo": `${floor.top - primaryBottom}px`,
              } as CSSProperties
            }
          >
            <FloorLight width={floor.width} top={floor.top} on={glow} />
          </div>
        )}

        {/* 선(트렁크·가지) — viewBox = 캔버스 px */}
        {spec.wires.length > 0 && (
          <svg
            aria-hidden="true"
            className="pointer-events-none absolute left-0 top-0 overflow-visible phone:hidden"
            width={W}
            height={H}
            viewBox={`0 0 ${W} ${H}`}
            fill="none"
          >
            {spec.wires.map((wr, i) => (
              <Wire key={i} d={wr.d} at={wr.at} />
            ))}
          </svg>
        )}

        {placed.map((it, i) => renderItem(it, i, i === primaryIndex, mount, mode))}

        {/* phone: 주 렌더 → 아래 보조 사이 세로 선 24(트렁크 하나) */}
        {hasAfter && (
          <div aria-hidden="true" className="hidden phone:order-2 phone:flex phone:basis-full phone:justify-center">
            <svg width={2} height={24} viewBox="0 0 2 24" className="overflow-visible" fill="none">
              <Wire d="M 1 0 V 24" at={0} />
            </svg>
          </div>
        )}

        {/* 접합점(5px --violet-core) — 선이 시작하거나 갈라지는 곳 */}
        {junctions.map((j, i) => (
          <span
            key={`j${i}`}
            aria-hidden="true"
            className="row-item pointer-events-none absolute size-[5px] rounded-full phone:hidden"
            data-kind="junction"
            style={
              {
                left: j.point[0] - 2.5,
                top: j.point[1] - 2.5,
                background: "var(--violet-core)",
                boxShadow: "0 0 8px rgba(218,132,255,.8)",
                "--at": `${j.at}ms`,
              } as CSSProperties
            }
          />
        ))}

        {/* 타일(48px) — row 만, 360ms 팝 */}
        {mode === "row" && spec.tile && (
          <div className="absolute phone:hidden" style={{ left: spec.tile.box[0], top: spec.tile.box[1] }}>
            {lazy(mount, <Tile icon={spec.tile.icon} bare={spec.tile.bare} at={TILE_AT} />)}
          </div>
        )}
      </div>
    </div>
  );
}

export default RowCanvas;
