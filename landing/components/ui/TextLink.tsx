import type { ReactNode } from "react";

// 텍스트 링크: --aing, 밑줄 1px · 오프셋 3px(SPEC §2.1·S1). 서버·클라 어디서나.

export interface TextLinkProps {
  href: string;
  external?: boolean;
  children: ReactNode;
  className?: string;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

export function TextLink({ href, external, children, className }: TextLinkProps) {
  return (
    <a
      href={href}
      target={external ? "_blank" : undefined}
      rel={external ? "noopener noreferrer" : undefined}
      className={cx(
        "text-aing underline decoration-1 underline-offset-[3px] transition-colors duration-[var(--t-quick)] ease-linear hover:text-aing-hover",
        className,
      )}
    >
      {children}
    </a>
  );
}

export default TextLink;
