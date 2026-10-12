import type { ReactNode, Ref } from "react";

// 공용 버튼. 'use client' 를 붙이지 않는다 — 서버 섹션은 href 로, 클라 파일은 onClick 으로 쓴다.
// 끝 화살표 없음(SPEC §1.3-7). 색은 토큰 변수만.

export type ButtonVariant = "primary" | "secondary" | "ghost";
export type ButtonSize = "l" | "m" | "s";

export interface ButtonProps {
  variant: ButtonVariant;
  size?: ButtonSize;
  href?: string;
  onClick?: () => void;
  external?: boolean;
  disabled?: boolean;
  ariaLabel?: string;
  className?: string;
  children: ReactNode;
  // ↓ PLAN §3.3 표 밖의 선택 props(상위 집합 — 섹션의 aria 연결·포커스 이동용)
  id?: string;
  type?: "button" | "submit";
  ariaExpanded?: boolean;
  ariaControls?: string;
  ariaDescribedBy?: string;
  ariaPressed?: boolean;
  ref?: Ref<HTMLElement>;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

const BASE =
  "inline-flex shrink-0 select-none items-center justify-center gap-2 whitespace-nowrap rounded-[var(--r-pill)] " +
  "[transition:background-color_var(--t-quick)_linear,color_var(--t-quick)_linear,border-color_var(--t-quick)_linear,scale_100ms_var(--ease-out)] " +
  "active:scale-[.98] motion-reduce:transition-none motion-reduce:active:scale-100";

const SIZE: Record<ButtonSize, string> = {
  l: "h-12 px-6",
  m: "h-10 px-5",
  s: "h-8 px-4",
};

const VARIANT: Record<ButtonVariant, string> = {
  primary: "btn-primary bg-aing text-on-aing hover:bg-aing-hover",
  secondary: "border border-line-strong bg-transparent text-ink-1 hover:bg-surface",
  ghost: "bg-transparent text-ink-2 hover:bg-surface hover:text-ink-1",
};

const DISABLED = "pointer-events-none cursor-default opacity-40";

/** 주 버튼 l 만 t-button(16px), 나머지(보조·고스트·작은 크기)는 t-button-s(14px) — SPEC §2.3 */
function typeClass(variant: ButtonVariant, size: ButtonSize): string {
  return variant === "primary" && size === "l" ? "t-button" : "t-button-s";
}

export function Button({
  variant,
  size = "l",
  href,
  onClick,
  external,
  disabled,
  ariaLabel,
  className,
  children,
  id,
  type = "button",
  ariaExpanded,
  ariaControls,
  ariaDescribedBy,
  ariaPressed,
  ref,
}: ButtonProps) {
  const cls = cx(BASE, SIZE[size], typeClass(variant, size), VARIANT[variant], disabled && DISABLED, className);

  if (href !== undefined) {
    if (disabled) {
      return (
        <span
          ref={ref as unknown as Ref<HTMLSpanElement>}
          id={id}
          role="link"
          aria-disabled="true"
          aria-label={ariaLabel}
          aria-describedby={ariaDescribedBy}
          className={cls}
        >
          {children}
        </span>
      );
    }
    return (
      <a
        ref={ref as unknown as Ref<HTMLAnchorElement>}
        id={id}
        href={href}
        onClick={onClick}
        target={external ? "_blank" : undefined}
        rel={external ? "noopener noreferrer" : undefined}
        aria-label={ariaLabel}
        aria-expanded={ariaExpanded}
        aria-controls={ariaControls}
        aria-describedby={ariaDescribedBy}
        className={cls}
      >
        {children}
      </a>
    );
  }

  return (
    <button
      ref={ref as unknown as Ref<HTMLButtonElement>}
      id={id}
      type={type}
      onClick={onClick}
      disabled={disabled}
      aria-label={ariaLabel}
      aria-expanded={ariaExpanded}
      aria-controls={ariaControls}
      aria-describedby={ariaDescribedBy}
      aria-pressed={ariaPressed}
      className={cls}
    >
      {children}
    </button>
  );
}

export default Button;
