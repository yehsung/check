import { asset, LINKS } from "@/data/fixtures";

// App Store 공식 배지(한국어, 검정). 수정·기울이기·애니메이션 금지.
// 애플 규칙: 높이 ≥ 40, 사방 여백 = 높이/4 → <a> 의 padding 으로 둔다(여백이 배지의 일부).

export interface AppStoreBadgeProps {
  height?: 40 | 44 | 48;
  placement: string;
  className?: string;
}

const KEY = "brand/appstore-badge-ko-black" as const;
const FALLBACK_SRC = "/assets/brand/appstore-badge-ko-black.svg";
const RATIO = 129.70071 / 40; // 원본 SVG viewBox

export function AppStoreBadge({ height = 48, placement, className }: AppStoreBadgeProps) {
  const src = asset(KEY)?.src ?? FALLBACK_SRC;
  const width = Math.round(height * RATIO * 100) / 100;
  const firstView = placement === "hero" || placement === "nav";
  return (
    <a
      href={LINKS.appStore}
      target="_blank"
      rel="noopener noreferrer"
      data-placement={placement}
      className={className ? `inline-flex shrink-0 ${className}` : "inline-flex shrink-0"}
      style={{ padding: height / 4 }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- next/image 금지(SPEC §8.2) */}
      <img
        src={src}
        alt="App Store에서 다운로드 하기" // 배지 글자 그대로(DECISIONS D26-5 · WCAG 2.5.3 이름 안의 라벨)
        width={Math.round(width)}
        height={height}
        decoding="async"
        loading={firstView ? "eager" : "lazy"}
        className="block max-w-none"
        style={{ width, height }}
      />
    </a>
  );
}

export default AppStoreBadge;
