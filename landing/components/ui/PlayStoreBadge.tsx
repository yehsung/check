import { asset, LINKS } from "@/data/fixtures";
import { ANDROID_COPY } from "@/data/install-copy";

// Google Play 공식 배지(한국어 'Google Play에서 다운로드', 검정 — play.google.com 배지 생성기의 ko_badge_web_generic.png 에서
// 위아래 투명 여백 29px 씩만 잘라 낸 것. 그림은 손대지 않는다). 수정·기울이기·애니메이션 금지.
// App Store 배지(AppStoreBadge)와 짝 — 같은 높이 · 같은 여백 규칙(사방 = 높이/4, <a> 의 padding · 구글 규칙도 높이의 1/4 이상).
// 기기마다 자기 스토어(대표 결재 #d_88MQEAwesX78): 안드로이드 기기면 App Store 배지 자리에 이 배지가 선다 · 컴퓨터 아웃트로는 둘 다.

export interface PlayStoreBadgeProps {
  height?: 40 | 44 | 48;
  placement: string;
  className?: string;
}

const KEY = "brand/googleplay-badge-ko" as const;
const FALLBACK_SRC = "/assets/brand/googleplay-badge-ko.png";
const RATIO = 646 / 192; // 잘라 낸 PNG 픽셀

export function PlayStoreBadge({ height = 48, placement, className }: PlayStoreBadgeProps) {
  const src = asset(KEY)?.src ?? FALLBACK_SRC;
  const width = Math.round(height * RATIO * 100) / 100;
  return (
    <a
      href={LINKS.androidStore}
      target="_blank"
      rel="noopener noreferrer"
      data-placement={placement}
      className={className ? `inline-flex shrink-0 ${className}` : "inline-flex shrink-0"}
      style={{ padding: height / 4 }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- next/image 금지(SPEC §8.2) */}
      <img
        src={src}
        alt={ANDROID_COPY.badgeAlt} // 배지 글자 그대로(WCAG 2.5.3 이름 안의 라벨 — App Store 배지와 같은 원칙)
        width={Math.round(width)}
        height={height}
        decoding="async"
        loading="lazy"
        className="block max-w-none"
        style={{ width, height }}
      />
    </a>
  );
}

export default PlayStoreBadge;
