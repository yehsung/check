import { LINKS, RELEASE_FALLBACK, type ReleaseInfo } from "@/data/fixtures";
import { chooserMetaParts, installChoice } from "@/data/install-copy";
import { glassButtonClass } from "@/components/glass/GlassButton";
import { GlassFx } from "@/components/glass/GlassFx";
import { InstallChooser } from "@/components/install/InstallChooser";

// 다운로드 CTA — server 컴포넌트(상태·이벤트 없음 — 선택 창은 InstallChooser client 섬). v3: 유리 버튼(.gbtn)으로 입힌다 — fill = 보라 틴트 유리, outline = 투명 유리.
// 포인터 스페큘러는 GlassFx(client 섬)가 붙인다.
// 플랫폼별 마크업을 SSR 하고 <html data-platform>(PLATFORM_SCRIPT 가 첫 페인트 전에 단다)으로 하나만 보인다 — 깜빡임 0.
//   .cta-mac  : data-platform 없음(스크립트 전·JS 끔) 또는 mac → 보임
//   .cta-ios  : data-platform=ios 일 때만
//   .cta-other: data-platform=other 일 때만
// 래퍼는 display: contents 라 부모 flex 줄에서는 안쪽 버튼이 바로 항목이 된다.
//
// 자리(Placement)별 규칙(docs/v3/brief.md §11 — 2026-10-30: 바로 DMG 를 받지 않고 Homebrew · DMG 중 고르게)
//   nav     : mac·other(≥768) = 설치 선택 창 방아쇠(InstallChooser — JS 없으면 '/#install' 링크) · 폰(< 768)은 같은 글자로 설치 절('/#install')로 간다
//             (§9.2 — 폰에 DMG 는 쓸모없다. 두 벌을 SSR 하고 폭으로 하나만 보인다) · ios = App Store 버튼
//   hero    : mac·other = 설치 선택 창 방아쇠 · ios = 아무것도 그리지 않는다(옆의 App Store 배지가 버튼 줄 맨 앞이 된다)
//             (폰 < 768 벌은 Hero.tsx 가 따로 그린다 — 배지 + 설치 절 링크)
//   outro   : hero 와 같다
//   install : 플랫폼과 무관하게 같은 다운로드 링크 하나(/api/download — 설치 절 DMG 카드가 곧 'DMG 직접' 선택이다. iOS 에서도 Mac 안내를 보인다)

type Placement = "nav" | "hero" | "install" | "outro";

export interface DownloadCTAProps {
  placement: Placement;
  size: "l" | "s";
  tone?: "fill" | "outline";
  /** 기본 "Mac용 다운로드" */
  label?: string;
  file?: "dmg" | "zip";
  /** 접근 이름(보이는 글자를 포함할 것). 설치 절은 형식·크기 포함 가능(바로 내려받으니까). 선택 창 방아쇠(hero·outro)는 넘기지 않는다 —
   *  파일을 바로 받지 않으니 보이는 글자 그대로가 이름(§11 — 크기는 창 안 DMG 줄에). 메뉴바는 'Mac용 다운로드' */
  ariaLabel?: string;
  /** 버튼에 붙일 클래스 */
  className?: string;
  /** 선택 창 DMG 줄 메타(v{ver} · {mb}MB · Apple 공증)의 출처 — getRelease(). 없으면 창이 처음 열릴 때 /api/release 에서 받는다 */
  release?: ReleaseInfo;
  /** (쓰지 않음 — v2 서명 호환) */
  installHref?: string;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

const VIS = {
  mac: "cta-mac contents [html[data-platform=ios]_&]:hidden [html[data-platform=other]_&]:hidden",
  ios: "cta-ios hidden [html[data-platform=ios]_&]:contents",
  other: "cta-other hidden [html[data-platform=other]_&]:contents",
} as const;

export function DownloadCTA({ placement, size, tone = "fill", label, file = "dmg", ariaLabel, className, release }: DownloadCTAProps) {
  const href = file === "zip" ? LINKS.downloadZip : LINKS.download;
  const text = label ?? "Mac용 다운로드";
  const btn = glassButtonClass(tone === "fill" ? "primary" : "glass", size, className);

  // 설치 절: 플랫폼 분기 없음(iOS 에서도 같은 DMG 링크) — 바로 내려받는다.
  if (placement === "install") {
    return (
      <a href={href} aria-label={ariaLabel} data-cta={placement} className={btn}>
        {text}
        <GlassFx specular />
      </a>
    );
  }

  // 히어로·아웃트로·메뉴바(≥768 · mac·other): 바로 내려받지 않고 설치 선택 창(Homebrew · DMG)을 연다.
  const meta = release ? chooserMetaParts(installChoice(release, RELEASE_FALLBACK)) : null;
  const chooser = (extra?: string) => (
    <InstallChooser placement={placement} label={text} ariaLabel={ariaLabel} className={cx(btn, extra)} meta={meta} />
  );
  // 메뉴바 폰(< 768): 선택 창 대신 설치 절로(같은 글자·같은 모양). ≥768 은 선택 창.
  const navPair = (
    <>
      {chooser("phone:hidden")}
      <a href={LINKS.install} aria-label={ariaLabel} data-cta={`${placement}-install`} className={cx(btn, "hidden phone:inline-flex")}>
        {text}
        <GlassFx specular />
      </a>
    </>
  );

  const main = placement === "nav" ? navPair : chooser();
  return (
    <>
      <span className={VIS.mac}>{main}</span>
      {placement === "nav" && (
        <span className={VIS.ios}>
          <a href={LINKS.appStore} target="_blank" rel="noopener noreferrer" data-cta={placement} className={cx(btn)}>
            App Store
            <GlassFx specular />
          </a>
        </span>
      )}
      <span className={VIS.other}>{main}</span>
    </>
  );
}

export default DownloadCTA;
