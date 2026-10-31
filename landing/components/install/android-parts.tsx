// components/install/android-parts.tsx — 안드로이드 베타 카드(docs/v3/brief.md §12)의 작은 조각. 훅 없음 — 서버(Install.tsx)·클라(AndroidSteps.tsx) 어디서나.
import { KeepDots } from '@/components/ui/KeepDots';

/** 작은따옴표 묶음('테스터 되기'를 · '찾을 수 없음'이 · '테스터 되기'까지)은 통째로 — 인용이 두 줄로 갈라지지 않게(1024 실측). 나머지는 KeepDots. 글자는 그대로 */
export function KeepQuotes({ text }: { text: string }) {
  return text.split(/('[^']+'[가-힣]*)/).map((part, i) =>
    i % 2 === 1 ? (
      <span key={i} className="whitespace-nowrap">
        {part}
      </span>
    ) : (
      <KeepDots key={i} text={part} />
    ),
  );
}

/** 바깥 링크(새 탭) 표시 — 장식 */
export function ExternalGlyph() {
  return (
    <svg aria-hidden="true" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" className="-mr-0.5 size-[11px] flex-none opacity-80">
      <path d="M4.25 2.75h5v5" />
      <path d="M9.25 2.75 3 9" />
    </svg>
  );
}

/** 끝낸 단계 번호 원의 체크 — 장식(번호는 sr-only 로 남는다) */
export function CheckGlyph() {
  return (
    <svg aria-hidden="true" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-3.5">
      <path d="M3.6 8.4 6.6 11.3 12.4 5.2" />
    </svg>
  );
}
