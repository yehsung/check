'use client';
// components/glass/CommandPill.tsx — 명령 알약(docs/v3/brief.md §4.3 · §4.5 · §8): thin 유리 + 모노 글자 + [복사] 칩.
// <BrewPill />                                   → brew install yehsung/check/aing-check · 접근 이름 'brew 설치 명령 복사'
// <CommandPill command={명령} copyAriaLabel="… 복사" />
// '$ ' 프롬프트는 복사·선택에서 빠진다. 좁은 폭에서는 '/' 뒤 · '&& ' 뒤 · 공백에서만 줄을 바꾼다(하이픈 낱말은 한 덩어리) — 가로 넘침 0.
// 복사가 막히면 명령 글자를 선택해 둔다(직접 ⌘C 할 수 있게).
import { useRef } from 'react';
import { BREW } from '@/data/fixtures';
import { glassClass } from './Glass';
import { CopyButton } from './CopyButton';
import { commandParts } from './command-parts';

export interface CommandPillProps {
  command: string;
  /** 복사 버튼 접근 이름(보이는 '복사' 를 포함) */
  copyAriaLabel: string;
  /** 복사 버튼 글자(기본 '복사') */
  copyLabel?: string;
  /** l = 설치 절 같은 넓은 자리(글자 15.5px) */
  size?: 'm' | 'l';
  /** '$' 프롬프트(기본 보임) */
  prompt?: boolean;
  className?: string;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

// 줄바꿈 조각(하이픈 낱말 nowrap · '/'·'&& ' 뒤 <wbr>)은 순수 모듈 command-parts.ts — 여기서 다시 내보낸다(이름 그대로).
export { commandParts } from './command-parts';
export type { CommandPart } from './command-parts';

export function CommandPill({ command, copyAriaLabel, copyLabel, size = 'm', prompt = true, className }: CommandPillProps) {
  const codeRef = useRef<HTMLSpanElement>(null);

  const onFail = () => {
    const el = codeRef.current;
    const sel = typeof window !== 'undefined' ? window.getSelection() : null;
    if (el && sel) {
      const range = document.createRange();
      range.selectNodeContents(el);
      sel.removeAllRanges();
      sel.addRange(range);
    }
  };

  return (
    <div className={cx(glassClass('thin'), 'cmd-pill', size === 'l' && 'cmd-pill--l', className)} data-command="">
      <code className="cmd-pill__code">
        {prompt && (
          <span aria-hidden="true" className="cmd-pill__prompt">
            {'$ '}
          </span>
        )}
        <span ref={codeRef}>
          {commandParts(command).map((p, i) => (
            <span key={i}>
              {p.nowrap ? <span className="whitespace-nowrap">{p.text}</span> : p.text}
              {p.wbrAfter ? <wbr /> : null}
            </span>
          ))}
        </span>
      </code>
      <CopyButton text={command} label={copyLabel} ariaLabel={copyAriaLabel} variant="chip" onFail={onFail} />
    </div>
  );
}

/** 히어로·설치·아웃트로의 brew 설치 알약(문구 §8: 복사 → 복사했어요 · 접근 이름 'brew 설치 명령 복사'). */
export function BrewPill({ size = 'm', className }: { size?: 'm' | 'l'; className?: string }) {
  return <CommandPill command={BREW.install} copyAriaLabel="brew 설치 명령 복사" size={size} className={className} />;
}

export default CommandPill;
