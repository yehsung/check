'use client';
// components/glass/CopyButton.tsx — 진짜 클립보드 복사 버튼(docs/v3/brief.md §4.5 · §8). 체험이 아니라 사이트 기능.
// 누르면 navigator.clipboard.writeText(text) → 글자 '복사' → '복사했어요'(2초 뒤 되돌림) + 페이지 라이브 영역(LiveAnnouncer)에 알림.
// 클립보드가 막히면 document.execCommand('copy') 로 한 번 더, 그것도 안 되면 onFail(보통 명령 글자를 선택해 둔다).
// 두 글자를 한 칸에 겹쳐 두어 바뀌어도 폭이 흔들리지 않는다(숨은 쪽 visibility:hidden — 접근 이름은 ariaLabel 그대로).
// variant: chip(알약 안 작은 유리 칩, 기본) | glass(큰 보조 버튼 l) | primary
import { useEffect, useRef, useState } from 'react';
import { ANNOUNCE, TIMING } from '@/data/fixtures';
import { announce } from '@/lib/announce';
import { usePointerSpecular } from './usePointerSpecular';

export interface CopyButtonProps {
  text: string;
  /** 보이는 글자(기본 '복사') */
  label?: string;
  /** 복사 뒤 글자·알림(기본 '복사했어요') */
  done?: string;
  /** 접근 이름(예: 'brew 설치 명령 복사') — 보이는 글자를 포함해야 한다(WCAG 2.5.3) */
  ariaLabel: string;
  variant?: 'chip' | 'glass' | 'primary';
  /** 복사 아이콘(겹친 네모 → 체크) */
  icon?: boolean;
  onFail?: () => void;
  className?: string;
  /** 데이터 표식(측정용 data-cta — 예: 설치 선택 창의 'chooser-brew') */
  dataCta?: string;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

const VARIANT: Record<NonNullable<CopyButtonProps['variant']>, string> = {
  chip: 'gbtn gbtn--chip',
  glass: 'gbtn gbtn--glass gbtn--l',
  primary: 'gbtn gbtn--primary gbtn--l',
};

function legacyCopy(text: string): boolean {
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0;pointer-events:none';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  } catch {
    return false;
  }
}

function CopyIcon({ done }: { done: boolean }) {
  return (
    <svg aria-hidden="true" width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      {done ? (
        <path d="M3.5 8.5l3 3 6-7" />
      ) : (
        <>
          <rect x="5.5" y="5.5" width="8" height="8" rx="2" />
          <path d="M10.5 3.5v-.5a1.5 1.5 0 0 0-1.5-1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5" />
        </>
      )}
    </svg>
  );
}

export function CopyButton({
  text,
  label = '복사',
  done = ANNOUNCE.copied,
  ariaLabel,
  variant = 'chip',
  icon = variant === 'chip',
  onFail,
  className,
  dataCta,
}: CopyButtonProps) {
  // 0 = 평상시, n > 0 = n 번째 복사 직후(다시 누르면 2초가 다시 시작된다)
  const [copiedAt, setCopiedAt] = useState(0);
  const btnRef = useRef<HTMLButtonElement>(null);
  usePointerSpecular(btnRef);

  useEffect(() => {
    if (copiedAt === 0) return;
    const t = window.setTimeout(() => setCopiedAt(0), TIMING.copyResetMs);
    return () => window.clearTimeout(t);
  }, [copiedAt]);

  const onClick = async () => {
    let ok = false;
    try {
      if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        ok = true;
      }
    } catch {
      ok = false;
    }
    if (!ok) ok = legacyCopy(text);
    if (!ok) {
      onFail?.();
      return;
    }
    setCopiedAt((n) => n + 1);
    announce(done);
  };

  const copied = copiedAt > 0;
  return (
    <button
      ref={btnRef}
      type="button"
      aria-label={ariaLabel}
      onClick={onClick}
      data-copied={copied ? '' : undefined}
      data-cta={dataCta}
      className={cx(VARIANT[variant], className)}
    >
      {icon && <CopyIcon done={copied} />}
      <span className="grid justify-items-center">
        <span className={cx('col-start-1 row-start-1', copied && 'invisible')}>{label}</span>
        <span className={cx('col-start-1 row-start-1', !copied && 'invisible')}>{done}</span>
      </span>
    </button>
  );
}

export default CopyButton;
