import type { CSSProperties } from "react";
import { asset as assetMeta, type AssetKey } from "@/data/fixtures";

// 렌더 한 장: <img> + 명시 width/height + decoding async. next/image 를 타지 않는다(이미지 최적화 끔 — v1 DECISIONS §1).
// 경로·캐시 버전은 data/generated/assets.json(느슨한 Record — v1 DECISIONS §4).
// 키가 없으면 개발 모드 console.warn + props 크기의 빈 <img alt>(빌드는 깨지지 않는다).
// 렌더는 크롭·축소·가장자리 페이드 마스크만(SPEC §1.3-3) — fade 는 mask-image 로 가장자리 px 만큼 투명하게 녹인다(필터 아님).

export interface RenderImageProps {
  asset: AssetKey;
  widthPt: number;
  heightPt: number;
  alt: string;
  /** loading="eager"(첫 화면). 우선순위는 fetchPriority 로 따로 준다 */
  eager?: boolean;
  className?: string;
  /** 표시 배율(기본 1 — pt = CSS px) */
  scale?: number;
  style?: CSSProperties;
  id?: string;
  /** fetchpriority="high"(LCP 후보만) */
  fetchPriority?: "high";
  /** 가장자리 페이드(px, 표시 크기 기준). 왼쪽 = 크롭 경계가 행 카드를 자를 때(16), 아래 = 패널 꼬리(24) · notch = 아래 Fade */
  fade?: Fade;
}

/**
 * 가장자리 페이드(px, 표시 크기 기준).
 * notch(DECISIONS D27-3): 크롭 경계가 머리띠(헤더 줄)의 단추·글자 조각을 자를 때 — 위 height px 띠만 왼쪽 solid px 를 완전히 투명하게
 *   하고 그 뒤 left px 동안 페이드(본문 행과 같은 부드러움을 오른쪽으로 민 것). 그 아래는 보통 left 페이드. left 와 함께만 쓴다(bottom 무시).
 */
export type Fade = { left?: number; bottom?: number; notch?: { solid: number; height: number } };

/**
 * 가장자리 페이드 마스크(CSS). 둘 다 있으면 교집합(왼쪽 ∧ 아래). 없으면 undefined. 순수 함수.
 * 렌더 바깥 상자(빈 창 등)에도 같은 마스크를 걸 수 있게 내보낸다(components/features/RowCanvas).
 */
export function fadeMask(fade?: Fade): CSSProperties | undefined {
  if (!fade) return undefined;
  const notch = fade.notch;
  if (notch && notch.solid > 0 && notch.height > 0 && fade.left && fade.left > 0) {
    // 머리띠(위 height px) 층 + 그 아래 층 — 두 층은 겹치지 않고 합쳐 상자 전체를 덮는다(mask-composite 기본 add = 합집합).
    const head = `linear-gradient(to right, transparent ${notch.solid}px, #000 ${notch.solid + fade.left}px)`;
    const body = `linear-gradient(to right, transparent, #000 ${fade.left}px)`;
    const image = `${head}, ${body}`;
    const size = `100% ${notch.height}px, 100% calc(100% - ${notch.height}px)`;
    const position = "0 0, 0 100%";
    return {
      maskImage: image,
      WebkitMaskImage: image,
      maskSize: size,
      WebkitMaskSize: size,
      maskPosition: position,
      WebkitMaskPosition: position,
      maskRepeat: "no-repeat",
      WebkitMaskRepeat: "no-repeat",
    };
  }
  const layers: string[] = [];
  if (fade.left && fade.left > 0) layers.push(`linear-gradient(to right, transparent, #000 ${fade.left}px)`);
  if (fade.bottom && fade.bottom > 0) layers.push(`linear-gradient(to top, transparent, #000 ${fade.bottom}px)`);
  if (layers.length === 0) return undefined;
  const image = layers.join(", ");
  const style: CSSProperties = { maskImage: image, WebkitMaskImage: image };
  if (layers.length > 1) {
    style.maskComposite = "intersect";
    style.WebkitMaskComposite = "source-in";
  }
  return style;
}

export function RenderImage({
  asset,
  widthPt,
  heightPt,
  alt,
  eager,
  className,
  scale = 1,
  style,
  id,
  fetchPriority,
  fade,
}: RenderImageProps) {
  const meta = assetMeta(asset);
  if (!meta && process.env.NODE_ENV !== "production") {
    console.warn(`[RenderImage] assets.json 에 '${asset}' 키가 없어요 — 빈 이미지로 그립니다.`);
  }
  const mask = fadeMask(fade);
  return (
    // eslint-disable-next-line @next/next/no-img-element -- next/image 를 쓰지 않는다(이미지 최적화 끔)
    <img
      id={id}
      src={meta?.src}
      alt={alt}
      width={Math.round(widthPt * scale)}
      height={Math.round(heightPt * scale)}
      decoding="async"
      loading={eager ? "eager" : "lazy"}
      fetchPriority={fetchPriority}
      className={className}
      style={mask ? { ...mask, ...style } : style}
    />
  );
}

export default RenderImage;
