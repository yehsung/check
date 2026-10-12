import type { CSSProperties } from "react";
import type { AssetKey } from "@/data/fixtures";
import { RenderImage } from "./RenderImage";

// 48px 타일(SPEC §2.2 .tile · §S4) — server, aria-hidden(아이콘은 장식 alt=""). 위치는 부모가 정한다.
// 기본: 보라 그라디언트 면(--lilac → --violet → --violet-deep) + 안쪽 하이라이트, 가운데 앱 메뉴바 아이콘 32px(R1·R3).
// bare: 앱 아이콘 렌더 그대로 48px(R5 — 레퍼런스의 '보라 앱 아이콘 타일'을 진짜 아이콘으로). 면·하이라이트 없이 그림자만,
//   그림자는 아이콘의 둥근 사각(256 판 실측: 알파 상자 25–230 · 모서리 ≈50px → 48px 에서 안쪽 4.7 · 반경 9.4)에 맞춘다.
// 조립: .js [data-row]:not([data-on]) 에서 불투명 0 · scale .6 → 켜지면 360ms 뒤 팝(globals, --ease-pop). at 은 --at 으로만 남긴다.

export interface TileProps {
  icon: AssetKey;
  /** 앱 아이콘 그대로(그림자만) */
  bare?: boolean;
  /** 조립 시작부터의 지연 ms(--at) */
  at?: number;
}

const BARE_INSET = 4.7;
const BARE_RADIUS = 9.4;

export function Tile({ icon, bare = false, at }: TileProps) {
  const vars = (at !== undefined ? { "--at": `${at}ms` } : {}) as CSSProperties;
  if (!bare) {
    return (
      <div aria-hidden="true" className="tile" data-tile="" style={vars}>
        <RenderImage asset={icon} widthPt={32} heightPt={32} alt="" className="block size-8" />
      </div>
    );
  }
  return (
    <div
      aria-hidden="true"
      className="tile relative"
      data-tile="bare"
      style={{ ...vars, background: "none", boxShadow: "none" }}
    >
      <span
        className="absolute"
        style={{
          inset: BARE_INSET,
          borderRadius: BARE_RADIUS,
          boxShadow: "0 0 0 1px rgba(126,94,250,.35), 0 10px 28px -8px rgba(126,94,250,.6)",
        }}
      />
      <RenderImage asset={icon} widthPt={48} heightPt={48} alt="" className="relative block size-12" />
    </div>
  );
}

export default Tile;
