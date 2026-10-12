import type { ElementType, JSX, ReactNode } from "react";

// 시각적으로 숨김(스크린 리더에는 읽힘). 섹션 제목 스텁·숨긴 <h3> 에 쓴다.

export interface VisuallyHiddenProps {
  as?: keyof JSX.IntrinsicElements;
  children: ReactNode;
  // 선택: aria-labelledby 대상이 되도록
  id?: string;
  className?: string;
}

export function VisuallyHidden({ as = "span", children, id, className }: VisuallyHiddenProps) {
  const Tag = as as ElementType;
  return (
    <Tag id={id} className={className ? `sr-only ${className}` : "sr-only"}>
      {children}
    </Tag>
  );
}

export default VisuallyHidden;
