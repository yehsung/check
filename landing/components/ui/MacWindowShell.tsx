import type { CSSProperties, ReactNode } from "react";

// '창' 셸(패널 조각·게임 창·헤더 카드): --r-window · --shadow-window · overflow hidden.
// 크기 = pt × scale(px). 높이가 바뀌면 --t-resize ease-out 으로 맞춘다(감속 모션은 즉시).
// fluid(또는 scale ≤ 0) 면 폭 100% + aspect-ratio — 폭을 아직 재지 못한 첫 페인트용.

export interface MacWindowShellProps {
  widthPt: number;
  heightPt: number;
  scale: number;
  className?: string;
  children?: ReactNode;
  // ↓ 선택(상위 집합)
  fluid?: boolean;
  style?: CSSProperties;
  id?: string;
  role?: string;
  ariaLabel?: string;
}

export function MacWindowShell({
  widthPt,
  heightPt,
  scale,
  className,
  children,
  fluid,
  style,
  id,
  role,
  ariaLabel,
}: MacWindowShellProps) {
  const isFluid = fluid || !(scale > 0);
  const dims: CSSProperties = isFluid
    ? { width: "100%", aspectRatio: `${widthPt} / ${heightPt}` }
    : { width: `${widthPt * scale}px`, height: `${heightPt * scale}px` };
  return (
    <div
      id={id}
      role={role}
      aria-label={ariaLabel}
      className={
        "relative overflow-hidden rounded-[var(--r-window)] " +
        "[transition:height_var(--t-resize)_var(--ease-out)] motion-reduce:transition-none" +
        (className ? ` ${className}` : "")
      }
      style={{ boxShadow: "var(--shadow-window)", ...dims, ...style }}
    >
      {children}
    </div>
  );
}

export default MacWindowShell;
