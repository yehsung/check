import { Fragment } from "react";

// 헤드라인: level → h1–h4, size → .t-* 타입 클래스(app/globals.css), lines 사이 <br>(SPEC §2.4 · J2-A7).
// 글꼴·굵기·자간·행간은 .t-* 가 정한다(500 = display·closing·facts-title, 600 = h2·h3·h4·caption) — 여기서 고정하지 않는다.
// 줄바꿈은 lines 가 정본이다(CB 의 ' / ' 위치). text-wrap: balance 는 한 줄 안의 균형에만 쓰인다. 낱말 강조·이탤릭 없음.

export type HeadlineSize = "display" | "closing" | "h2" | "h2-solo" | "h3" | "h4" | "caption" | "facts-title";

export interface HeadlineProps {
  level: 1 | 2 | 3 | 4;
  size: HeadlineSize;
  lines: readonly string[];
  id?: string;
  className?: string;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

const SIZE_CLASS: Record<HeadlineSize, string> = {
  display: "t-display",
  closing: "t-closing",
  h2: "t-h2",
  "h2-solo": "t-h2-solo",
  h3: "t-h3",
  h4: "t-h4",
  caption: "t-caption",
  "facts-title": "t-facts-title",
};

const TAG = { 1: "h1", 2: "h2", 3: "h3", 4: "h4" } as const;

export function Headline({ level, size, lines, id, className }: HeadlineProps) {
  const Tag = TAG[level];
  return (
    <Tag id={id} className={cx(SIZE_CLASS[size], "text-ink-1", className)}>
      {lines.map((line, i) => (
        <Fragment key={i}>
          {i > 0 && <br />}
          {line}
        </Fragment>
      ))}
    </Tag>
  );
}

export default Headline;
