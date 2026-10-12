import { LINKS } from "@/data/fixtures";

// 다운로드 CTA — server 컴포넌트(상태·이벤트 없음, SPEC §6.2 · DECISIONS D9).
// 플랫폼별 마크업을 SSR 하고 <html data-platform>(PLATFORM_SCRIPT 가 첫 페인트 전에 단다)으로 하나만 보인다 — 깜빡임 0.
//   .cta-mac  : data-platform 없음(스크립트 전·JS 끔) 또는 mac → 보임
//   .cta-ios  : data-platform=ios 일 때만
//   .cta-other: data-platform=other 일 때만
// 보임/숨김은 이 파일의 Tailwind 임의 변형([html[data-platform=…]_&])으로 스스로 해결한다. 래퍼는 display: contents 라
// 부모 flex 줄에서는 안쪽 알약이 바로 항목이 된다.
//
// 자리(Placement)별 규칙
//   nav     : mac·other = <a href="/api/download">(모든 폭 — DECISIONS D19-3) · ios = App Store 알약
//   hero    : mac·other = 다운로드 링크 · ios = 아무것도 그리지 않는다(옆의 App Store 배지가 버튼 줄 맨 앞이 된다)
//   outro   : hero 와 같다
//   install : 플랫폼과 무관하게 같은 다운로드 링크 하나(설치 절은 iOS 에서도 Mac 안내를 보인다)
// 'Mac 링크 보내기'(공유 시트)는 v2 에서 없다(허용 목록 밖 — DECISIONS D9).

type Placement = "nav" | "hero" | "install" | "outro";

export interface DownloadCTAProps {
  placement: Placement;
  size: "l" | "s";
  tone?: "fill" | "outline";
  /** 기본 "Mac용 다운로드" */
  label?: string;
  file?: "dmg" | "zip";
  /** 접근 이름에 형식·크기 포함(예: "Mac용 다운로드, aing-check.dmg 30.1MB" — 크기는 부르는 쪽이 getRelease() 로) */
  ariaLabel?: string;
  /** 알약에 붙일 클래스 */
  className?: string;
  /** (쓰지 않음 — DECISIONS D19-3 로 nav 의 phone '설치' 알약이 없어졌다. PLAN §3.4 서명 호환을 위해 받기만 한다) */
  installHref?: string;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

const VIS = {
  mac: "cta-mac contents [html[data-platform=ios]_&]:hidden [html[data-platform=other]_&]:hidden",
  ios: "cta-ios hidden [html[data-platform=ios]_&]:contents",
  other: "cta-other hidden [html[data-platform=other]_&]:contents",
} as const;

// display 는 PILL 에 넣지 않는다: Tailwind 출력에서 .inline-flex 가 .hidden 뒤에 와서 'hidden' 을 이기기 때문(실측).
// 보이는 방식은 부르는 자리에서 inline-flex / "hidden phone:inline-flex" / "inline-flex phone:hidden" 중 하나로 준다.
const PILL =
  "shrink-0 select-none items-center justify-center whitespace-nowrap rounded-[var(--r-pill)] border " +
  "[transition:background-color_var(--t-resize)_linear,color_var(--t-resize)_linear,border-color_var(--t-resize)_linear,scale_100ms_var(--ease-out)] " +
  "active:scale-[.98] motion-reduce:transition-none motion-reduce:active:scale-100";

const SIZE = {
  l: "t-button h-12 px-6",
  // SPEC §2.4 버튼 s = 36 · §4 터치 대상 ≥ 44 — 보이는 알약 36 + 투명 ::before 로 위아래 4px 씩(review-perf-a11y P1-1)
  s: "t-button-s relative h-9 px-4 before:absolute before:inset-x-0 before:-inset-y-1 before:content-['']",
} as const;

const TONE = {
  fill: "btn-primary border-aing bg-aing text-on-aing hover:border-aing-hover hover:bg-aing-hover",
  // SPEC §S0 · DECISIONS D19-3: 히어로 CTA 가 보이는 동안 내비는 --line-strong 테두리 + ink-1 글자
  outline: "border-line-strong bg-transparent text-ink-1 hover:bg-surface",
} as const;

export function DownloadCTA({
  placement,
  size,
  tone = "fill",
  label,
  file = "dmg",
  ariaLabel,
  className,
}: DownloadCTAProps) {
  const href = file === "zip" ? LINKS.downloadZip : LINKS.download;
  const text = label ?? "Mac용 다운로드";
  const pill = cx(PILL, SIZE[size], TONE[tone], className);

  const download = (extra: string) => (
    <a href={href} aria-label={ariaLabel} data-cta={placement} className={cx(pill, extra)}>
      {text}
    </a>
  );

  // 설치 절: 플랫폼 분기 없음(iOS 에서도 같은 DMG 링크).
  if (placement === "install") return download("inline-flex");

  // nav 도 모든 폭에서 같은 '다운로드' 알약(SPEC §S0 390 와이어 · DECISIONS D19-3 — v1 의 phone '설치' 알약은 쓰지 않는다).
  const desktop = download("inline-flex");

  return (
    <>
      <span className={VIS.mac}>{desktop}</span>
      {placement === "nav" && (
        <span className={VIS.ios}>
          <a
            href={LINKS.appStore}
            target="_blank"
            rel="noopener noreferrer"
            data-cta={placement}
            className={cx(pill, "inline-flex")}
          >
            App Store
          </a>
        </span>
      )}
      <span className={VIS.other}>{desktop}</span>
    </>
  );
}

export default DownloadCTA;
