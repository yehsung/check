import { asset, LINKS } from "@/data/fixtures";

// QR 흰 타일(--r-window). desk 에서만 보인다.
// 기본 = App Store QR(지역 코드 없는 주소로 새로 만든 SVG) — 누르면 App Store 새 탭(SPEC S11). 기존 호출부(<QrCode size={96} />)는 그대로.
// href·src·alt 를 넘기면 다른 QR(설치 절 안드로이드 카드 — /#android 안내, docs/v3/brief.md §12). 바깥 주소(http…)만 새 탭, 같은 사이트 경로는 같은 탭.

export interface QrCodeProps {
  size?: number;
  className?: string;
  /** 링크 주소. 기본 LINKS.appStore */
  href?: string;
  /** QR 그림(asset(key).src). 기본 brand/qr-appstore */
  src?: string;
  /** 그림 alt(= 링크 이름). 기본 App Store 문장 */
  alt?: string;
}

const KEY = "brand/qr-appstore" as const;
const FALLBACK_SRC = "/assets/brand/qr-appstore.svg";
const DEFAULT_ALT = "App Store 아잉체크 페이지로 가는 QR 코드";
const PAD = 8;

export function QrCode({ size = 112, className, href = LINKS.appStore, src, alt = DEFAULT_ALT }: QrCodeProps) {
  const img = src ?? asset(KEY)?.src ?? FALLBACK_SRC;
  const inner = size - PAD * 2;
  const external = /^https?:/.test(href); // 바깥 주소(https:) = 새 탭 · '/#android' 같은 사이트 경로 = 같은 탭
  return (
    <a
      href={href}
      target={external ? "_blank" : undefined}
      rel={external ? "noopener noreferrer" : undefined}
      className={
        "hidden shrink-0 rounded-[var(--r-window)] bg-white desk:block" + (className ? ` ${className}` : "")
      }
      style={{ width: size, height: size, padding: PAD }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- next/image 금지(SPEC §8.2) */}
      <img
        src={img}
        alt={alt}
        width={inner}
        height={inner}
        decoding="async"
        loading="lazy"
        className="block"
        style={{ width: inner, height: inner }}
      />
    </a>
  );
}

export default QrCode;
