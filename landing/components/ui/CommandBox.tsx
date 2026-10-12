"use client";

import { useRef } from "react";
import { CopyButton } from "./CopyButton";

// brew 명령 상자: --surface · --r-code · t-code(JetBrains Mono). '$ ' 접두는 복사·선택에서 제외.
// phone 폭에서도 가로 스크롤 없이 줄바꿈(pre-wrap) — SPEC S11. 낱말 가운데('chec|k')서 끊지 않게 break-all 대신
// overflow-wrap:anywhere(정말 안 들어갈 때만) + 각 '/' 뒤 <wbr>(자연스러운 끊김 자리). 복사 문자열은 그대로.
// 복사가 거부되면 명령 글자를 선택 상태로 만든다(직접 복사할 수 있게). 안내 문구는 두지 않는다 — 버튼 '복사'로 충분(DECISIONS D26-5).

export interface CommandBoxProps {
  command: string;
  copyAriaLabel: string;
  className?: string;
}

export function CommandBox({ command, copyAriaLabel, className }: CommandBoxProps) {
  const codeRef = useRef<HTMLSpanElement>(null);

  const onFail = () => {
    const el = codeRef.current;
    const sel = typeof window !== "undefined" ? window.getSelection() : null;
    if (el && sel) {
      const range = document.createRange();
      range.selectNodeContents(el);
      sel.removeAllRanges();
      sel.addRange(range);
    }
  };

  return (
    <div className={className}>
      <div className="flex items-center gap-3 rounded-[var(--r-code)] bg-surface py-2 pl-4 pr-2">
        <code className="t-code min-w-0 flex-1 whitespace-pre-wrap [overflow-wrap:anywhere] font-[family-name:var(--font-code)] text-ink-1">
          <span aria-hidden="true" className="select-none text-ink-3">
            {"$ "}
          </span>
          <span ref={codeRef}>
            {command.split("/").map((part, i) => (
              <span key={i}>
                {i > 0 ? "/" : null}
                {i > 0 ? <wbr /> : null}
                {part}
              </span>
            ))}
          </span>
        </code>
        <CopyButton text={command} ariaLabel={copyAriaLabel} variant="inline" onFail={onFail} />
      </div>
    </div>
  );
}

export default CommandBox;
