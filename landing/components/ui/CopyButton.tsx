"use client";

import { useEffect, useState } from "react";
import { ANNOUNCE, TIMING } from "@/data/fixtures";
import { announce } from "@/lib/announce";

// 복사 버튼: '복사' → '복사했어요'(TIMING.copyResetMs 뒤 되돌림) + 알림. 실패하면 onFail.
// 두 글자를 한 칸에 겹쳐 두어 바뀌어도 폭이 흔들리지 않는다(숨은 쪽은 visibility: hidden — 접근 이름에서 빠진다).

export interface CopyButtonProps {
  text: string;
  label?: string;
  done?: string;
  ariaLabel: string;
  variant?: "inline" | "secondary";
  onFail?: () => void;
  className?: string;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

const VARIANT: Record<NonNullable<CopyButtonProps["variant"]>, string> = {
  // inline 은 h-8(32px) — 투명 ::before 로 위아래 6px 씩 히트를 넓혀 터치 44px(SPEC §7)
  inline: "relative h-8 rounded-[var(--r-seg-in)] px-3 text-ink-1 hover:bg-surface-2 before:absolute before:inset-x-0 before:-inset-y-1.5 before:content-['']",
  secondary: "h-12 rounded-[var(--r-pill)] border border-line-strong px-6 text-ink-1 hover:bg-surface",
};

export function CopyButton({
  text,
  label = "복사",
  done = ANNOUNCE.copied,
  ariaLabel,
  variant = "inline",
  onFail,
  className,
}: CopyButtonProps) {
  // 0 = 평상시, n > 0 = n 번째 복사 직후(다시 누르면 2초가 다시 시작된다)
  const [copiedAt, setCopiedAt] = useState(0);

  useEffect(() => {
    if (copiedAt === 0) return;
    const t = window.setTimeout(() => setCopiedAt(0), TIMING.copyResetMs);
    return () => window.clearTimeout(t);
  }, [copiedAt]);

  const onClick = async () => {
    try {
      if (typeof navigator === "undefined" || !navigator.clipboard?.writeText) throw new Error("clipboard unavailable");
      await navigator.clipboard.writeText(text);
    } catch {
      onFail?.();
      return;
    }
    setCopiedAt((n) => n + 1);
    announce(done);
  };

  const copied = copiedAt > 0;
  return (
    <button
      type="button"
      aria-label={ariaLabel}
      onClick={onClick}
      className={cx(
        "t-button-s inline-flex shrink-0 select-none items-center justify-center whitespace-nowrap transition-colors duration-[var(--t-quick)] ease-linear",
        VARIANT[variant],
        className,
      )}
    >
      <span className="grid justify-items-center">
        <span className={cx("col-start-1 row-start-1", copied && "invisible")}>{label}</span>
        <span className={cx("col-start-1 row-start-1", !copied && "invisible")}>{done}</span>
      </span>
    </button>
  );
}

export default CopyButton;
