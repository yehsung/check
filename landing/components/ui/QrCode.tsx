import { asset, LINKS } from "@/data/fixtures";

// App Store QR(지역 코드 없는 주소로 새로 만든 SVG). desk 에서만 보인다. 흰 타일 · --r-window.
// 누르면 App Store 새 탭(SPEC S11).

export interface QrCodeProps {
  size?: number;
  className?: string;
}

const KEY = "brand/qr-appstore" as const;
const FALLBACK_SRC = "/assets/brand/qr-appstore.svg";
const PAD = 8;

export function QrCode({ size = 112, className }: QrCodeProps) {
  const src = asset(KEY)?.src ?? FALLBACK_SRC;
  const inner = size - PAD * 2;
  return (
    <a
      href={LINKS.appStore}
      target="_blank"
      rel="noopener noreferrer"
      className={
        "hidden shrink-0 rounded-[var(--r-window)] bg-white desk:block" + (className ? ` ${className}` : "")
      }
      style={{ width: size, height: size, padding: PAD }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- next/image 금지(SPEC §8.2) */}
      <img
        src={src}
        alt="App Store 아잉체크 페이지로 가는 QR 코드"
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
