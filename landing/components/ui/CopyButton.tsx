"use client";

import { CopyButton as GlassCopyButton } from "@/components/glass/CopyButton";

// 복사 버튼(v2 이름·props 유지 — v3 에서는 components/glass/CopyButton 을 입힌다. 새 코드는 그쪽을 직접 쓴다).
// variant: inline = 알약 안 유리 칩 · secondary = 큰 투명 유리 버튼. '복사' → '복사했어요' + 라이브 영역 알림.

export interface CopyButtonProps {
  text: string;
  label?: string;
  done?: string;
  ariaLabel: string;
  variant?: "inline" | "secondary";
  onFail?: () => void;
  className?: string;
}

export function CopyButton({ variant = "inline", ...rest }: CopyButtonProps) {
  return <GlassCopyButton variant={variant === "inline" ? "chip" : "glass"} icon={variant === "inline"} {...rest} />;
}

export default CopyButton;
