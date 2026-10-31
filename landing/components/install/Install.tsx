// components/install/Install.tsx — 설치 #install(docs/v3/brief.md §4.5 · 문구 §8 '설치' · §9.3 · 안드로이드 §12). server 컴포넌트 — 움직이는 건 BrewTerminal 과
// 안드로이드 세 단계 목록(AndroidSteps — 다음 단계 안내 §12.6) 둘.
// brew 가 주인공: 가운데 H2 두 줄 + 부제 → 왼쪽(넓게 ≈60%) regular 유리 터미널 / 오른쪽 regular 유리 카드 둘
// (Homebrew를 안 쓴다면 — DMG · 아이폰에서도 — App Store·QR) → 아래 전폭 안드로이드 베타 카드(#android — 세 단계).
// v3.1(§9.3): 터미널 아래 업데이트 줄은 지웠다(upgrade 명령을 보이지 않는다).
//
// 배치
//   desk(≥1024·≥640) : 2열 [1.6fr | 1fr]. 왼쪽 열 = 터미널(카드 둘 높이를 채운다), 오른쪽 = DMG 카드 위 · iPhone 카드 아래.
//                      3번째 줄 = 안드로이드 카드 두 칸 전폭 — 안은 2열(왼쪽 제목·한 줄 · 베타 안내 · 아래 끝 QR / 오른쪽 같은 계정 경고 ·
//                      세 단계 가로 3칸, 번호 원을 선으로 잇는다 · 그 아래 접는 문제 해결)
//   768–1023         : 터미널 전폭 → DMG · iPhone 카드 두 칸 → 안드로이드 카드 전폭(글 묶음 위 · 세 단계 가로 3칸 — 768 실측에서도
//                      단계 이름이 한 줄, 보조 줄이 두 줄이라 세로보다 낮고 덜 눌린다. QR 은 없다 — 데스크톱 전용)
//   390              : 터미널(명령 한 줄 · [복사] 는 제목 줄 · 출력 긴 줄만 줄바꿈) → DMG 카드 → iPhone 카드 → 안드로이드 카드(단계 세로 — 단계마다
//                      번호 원 + 이름 · 카드 폭 버튼(48) · 보조, 단계 사이 선).
//                      <html data-platform=ios> 면 iPhone 카드가, <html data-android> 면 안드로이드 카드가 맨 앞
//                      (768 이상은 칸 자리를 못박아 순서가 그대로)
// 빛: 절 뒤 LocalLight 넷(터미널 뒤 보라 넓게 · 카드 뒤 인디고 · 위 오키드 · 아래 안드로이드 카드 뒤 보라) — 어느 스크롤 위치에서도 유리 뒤에 색이 있다.
//     + 폰 · 안드로이드 기기 전용 하나(카드가 맨 앞 — 절 위쪽으로 올라와 넷이 닿지 않는다. 다른 기기·≥768 은 display:none).
// 버전·크기는 릴리스 API 값(getRelease → installChoice) — 하드코딩 금지. 명령 문자열은 BREW(data/fixtures) 정본.
import { Fragment } from 'react';
import type { ReleaseInfo } from '@/lib/release';
import { RELEASE_FALLBACK } from '@/lib/release';
import { BREW, LINKS, asset } from '@/data/fixtures';
import { ANDROID_COPY, INSTALL_COPY, brewTranscript, installChoice, metaParts } from '@/data/install-copy';
import { Glass } from '@/components/glass/Glass';
import { LocalLight } from '@/components/glass/LocalLight';
import { Headline } from '@/components/ui/Headline';
import { DownloadCTA } from '@/components/ui/DownloadCTA';
import { AppStoreBadge } from '@/components/ui/AppStoreBadge';
import { QrCode } from '@/components/ui/QrCode';
import { KeepDots } from '@/components/ui/KeepDots';
import { BrewTerminal } from './BrewTerminal';
import { AndroidSteps } from './AndroidSteps';
import { KeepQuotes } from './android-parts';

const C = INSTALL_COPY;
const A = ANDROID_COPY;

/** 메타 줄: "v0.3.63 · 30.1MB · macOS 14 이상 · Apple Silicon·Intel · Apple 공증" — 항목은 끊지 않고, '·' 는 앞 항목 끝에 붙여
 *  줄머리에 '·' 가 오지 않게 한다(줄바꿈은 항목 사이 공백에서만). */
function MetaLine({ parts }: { parts: readonly string[] }) {
  return (
    <p data-install-meta="" className="t-small mt-3.5 text-ink-2">
      {parts.map((part, i) => {
        const last = i === parts.length - 1;
        return (
          <Fragment key={i}>
            <span className="whitespace-nowrap">{last ? part : `${part} ·`}</span>
            {last ? null : ' '}
          </Fragment>
        );
      })}
    </p>
  );
}

// 카드 = regular 유리 + 옅은 대비 보험(.glass-tint-soft — 터미널 tint .38 보다 옅게). 카드 뒤 보라 빛이 가장 밝은 지점에서
// 14px ink-2 가 4.22:1 이었다(3단계 실측) → ≥ 5:1. 클래스라서 투명도 줄이기·backdrop 미지원 폴백(globals)이 그대로 이긴다
const CARD = 'glass-tint-soft flex min-w-0 flex-col p-6 min-[768px]:p-7';
const CARD_H = 't-h4 text-ink-1';

/** 안드로이드 QR(/#android — 이 안내를 폰에서 연다). assets.json 에 없으면 원본 경로 */
const ANDROID_QR_SRC = asset('brand/qr-android-beta')?.src ?? '/assets/brand/qr-android-beta.svg';

function InfoGlyph() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="mt-px size-[18px] flex-none text-[color:var(--focus)]">
      <circle cx="10" cy="10" r="7.6" stroke="currentColor" strokeWidth="1.5" />
      <path d="M10 9v4.6" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <circle cx="10" cy="6.3" r="1" fill="currentColor" />
    </svg>
  );
}

/** 접는 문제 해결(§12.6) — FAQ 의 <details> 와 같은 모양(펼침 칩 꺾쇠 · 열리면 180° + 보라 칩) · 요약 줄 48 */
const HELP =
  'group/help mt-7 rounded-[14px] bg-white/[.03] shadow-[inset_0_0_0_1px_rgb(255_255_255/.09)] desk:col-start-2 desk:row-start-4 desk:mt-0';
const HELP_SUMMARY =
  'group/hs flex min-h-12 cursor-pointer list-none items-center justify-between gap-4 rounded-[14px] py-2 pl-3.5 pr-2.5 ' +
  'font-heading text-[15px] font-semibold leading-[1.35] tracking-[-.01em] text-ink-1 [&::-webkit-details-marker]:hidden';
const HELP_ICON =
  'grid size-7 shrink-0 place-items-center rounded-full bg-white/[.06] text-ink-2 ' +
  'shadow-[inset_0_1px_0_rgb(255_255_255/.16),inset_0_0_0_1px_rgb(255_255_255/.07)] ' +
  'transition-[rotate,background-color,color] duration-200 ease-[var(--ease-out)] motion-reduce:transition-none ' +
  'group-hover/hs:bg-white/[.12] group-hover/hs:text-ink-1 ' +
  'group-open/help:rotate-180 group-open/help:bg-[rgb(var(--violet-rgb)/.34)] group-open/help:text-ink-1';
/** 항목 = 작은 점 + t-small ink-2(점 중심 = 첫 줄 가운데 10.5px) */
const HELP_ITEM =
  't-small relative pl-4 text-pretty text-ink-2 before:absolute before:left-[3px] before:top-[8px] before:size-[5px] before:rounded-full before:bg-current before:opacity-70';

/**
 * 안드로이드 베타 카드(#android — §12). 단계 = <ol> 1·2·3(실제 순서 — AndroidSteps, client 섬: 클릭한 다음 단계가 주 버튼 §12.6).
 * 소스 순서 = 읽는 순서(제목·한 줄 → 같은 계정 경고 → 세 단계 → 접는 문제 해결 → 베타 안내 → QR). 폰·768–1023 은 이 순서로 쌓고,
 * desk 는 2열 그리드로 자리만 옮긴다 — 왼쪽(제목·한 줄 / 베타 안내 / 아래 끝 QR) · 오른쪽(경고 / 세 단계 / 문제 해결).
 * 경고를 오른쪽 맨 위(단계 바로 위)에 둔 까닭: 왼쪽에 경고·QR 을 다 쌓으면 왼쪽이 단계 열보다 ≈140px 길어 단계 아래가 비었다(1440 실측) ·
 * 단계 버튼을 클릭하기 직전에 읽힌다.
 * 문제 해결 = <details> 기본 닫힘(JS 없이 열고 닫힘 · 키보드 Enter/Space) — 3단계에서 '찾을 수 없음'이 뜬 사람이 단계 바로 아래에서 찾는다.
 */
function AndroidCard() {
  return (
    <Glass
      level="regular"
      id="android"
      data-install="android"
      className={
        `${CARD} [html[data-android]_&]:-order-1 min-[768px]:col-span-2 min-[768px]:col-start-1 min-[768px]:row-start-3 ` +
        'desk:grid desk:grid-cols-[clamp(264px,25vw,320px)_minmax(0,1fr)] desk:grid-rows-[auto_auto_1fr_auto] desk:gap-x-10 desk:gap-y-6'
      }
    >
      <div className="min-w-0 desk:col-start-1 desk:row-start-1">
        <h3 className={CARD_H}>{A.title}</h3>
        <p className="t-small mt-2 text-pretty text-ink-2">{A.line}</p>
      </div>
      <p
        data-android-warn=""
        className={
          't-small mt-4 flex gap-2.5 rounded-[14px] bg-white/[.06] px-3.5 py-3 text-pretty text-ink-1 shadow-[inset_0_0_0_1px_rgb(255_255_255/.1)] ' +
          'min-[768px]:max-w-[34em] desk:col-start-2 desk:row-start-1 desk:mt-0 desk:max-w-none desk:self-center'
        }
      >
        <InfoGlyph />
        <span className="min-w-0">
          <KeepQuotes text={A.warn} />
        </span>
      </p>

      <AndroidSteps className="mt-7 desk:col-start-2 desk:row-span-2 desk:row-start-2 desk:mt-0 desk:min-w-0" />

      <details data-android-help="" className={HELP}>
        <summary className={HELP_SUMMARY}>
          <span className="min-w-0">{A.helpTitle}</span>
          <span aria-hidden="true" className={HELP_ICON}>
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
              <path d="M3.25 5.25 7 9l3.75-3.75" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        </summary>
        <ul className="grid gap-1.5 px-3.5 pb-3.5 pt-0.5">
          {A.helpItems.map((item) => (
            <li key={item} className={HELP_ITEM}>
              <KeepQuotes text={item} />
            </li>
          ))}
        </ul>
      </details>

      <p className="t-micro mt-6 text-pretty text-ink-2 desk:col-start-1 desk:row-start-2 desk:mt-0">
        <KeepDots text={A.betaNote} />
      </p>
      {/* QR(데스크톱만) — 폰 카메라로 이 안내를 연다. 같은 탭 /#android. 왼쪽 열 아래 끝 = 단계 열 아래 끝 */}
      <div className="hidden items-center gap-4 desk:col-start-1 desk:row-start-3 desk:flex desk:self-end">
        <QrCode size={88} href={LINKS.android} src={ANDROID_QR_SRC} alt={A.qrAlt} />
        <p className="t-small text-pretty text-ink-2">{A.qrCaption}</p>
      </div>
    </Glass>
  );
}

export function Install({ release }: { release: ReleaseInfo }) {
  const c = installChoice(release, RELEASE_FALLBACK);
  const transcript = brewTranscript(BREW.install, c.version);
  return (
    <section
      id="install"
      aria-labelledby="install-h"
      data-release={c.version}
      className="relative isolate overflow-clip pb-14 pt-16 tab:pb-20 tab:pt-24 desk:py-32"
    >
      {/* 타원이 절 위아래 변을 넘지 않게(넘으면 overflow-clip 경계에서 빛이 가로로 끊긴다 — 3단계 실측 α .03–.07):
          아래 빛 중심 ≤ 100% − 반높이 − 12px · 위 빛 중심 ≥ 반높이 + 12px. 반높이 = size × aspect / 2.
          위 오키드는 부제(ink-2 19px) 대비 ≥ 4.5 를 지키게 오른쪽·약하게(1024 실측 4.50 → 여유) */}
      <LocalLight tone="violet" x="32%" y="min(60%, calc(100% - min(390px, 41.6vw) - 12px))" size="min(1500px, 160vw)" aspect={0.52} strength={0.34} />
      <LocalLight tone="indigo" x="84%" y="min(72%, calc(100% - min(294px, 39vw) - 12px))" size="min(980px, 130vw)" aspect={0.6} strength={0.28} />
      <LocalLight tone="orchid" x="76%" y="calc(min(252px, 35vw) + 12px)" size="min(720px, 100vw)" strength={0.16} />
      {/* 안드로이드 카드(맨 아래 줄) 뒤 — 왼쪽 글 묶음 쪽 보라. 아랫변을 넘지 않게 중심 ≤ 100% − 반높이 − 12px */}
      <LocalLight tone="violet" x="22%" y="calc(100% - min(230px, 32.2vw) - 12px)" size="min(1000px, 140vw)" aspect={0.46} strength={0.24} />
      {/* 폰 · 안드로이드 기기: 안드로이드 카드가 맨 앞(절 위에서 ≈ 260–1100px — §12.6 폰 버튼 48 · 단계 사이 선 · 문제 해결로 길어졌다)이라
          위 넷이 닿지 않는다 → 카드 뒤 보라 하나(세로로 긴 타원 — 카드 아래끝까지).
          윗변을 넘지 않게 중심 = 반높이 + 12px 이상(위끝이 늘 절 위 300px) · 다른 기기 · ≥768 은 display:none */}
      <LocalLight
        tone="violet"
        x="30%"
        y="calc(min(448px, 114.8vw) + 300px)"
        size="min(640px, 164vw)"
        aspect={1.4}
        strength={0.26}
        className="hidden phone:[html[data-android]_&]:block"
      />

      <div className="relative mx-auto w-full max-w-[1200px] px-5 min-[768px]:px-8 desk:px-10">
        <div className="text-center">
          <Headline level={2} size="h2" lines={C.h2} id="install-h" />
          <p className="t-lead mx-auto mt-5">{C.sub}</p>
        </div>

        <div className="mt-12 grid grid-cols-1 gap-5 min-[768px]:mt-14 min-[768px]:grid-cols-2 desk:mt-16 desk:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)] desk:gap-6">
          {/* brew — 터미널 */}
          <div
            data-install="brew"
            className="flex min-w-0 flex-col min-[768px]:col-span-2 min-[768px]:row-start-1 desk:col-span-1 desk:col-start-1 desk:row-span-2"
          >
            <BrewTerminal command={BREW.install} lines={transcript} className="flex-1" />
          </div>

          {/* DMG — Homebrew를 안 쓴다면 */}
          <Glass
            level="regular"
            data-install="dmg"
            className={`${CARD} min-[768px]:col-start-1 min-[768px]:row-start-2 desk:col-start-2 desk:row-start-1`}
          >
            <h3 className={CARD_H}>{C.dmgTitle}</h3>
            <div className="mt-5 flex">
              <DownloadCTA
                placement="install"
                size="l"
                tone="outline"
                file={c.file}
                label={c.label}
                ariaLabel={c.ariaLabel}
                className="phone:w-full"
              />
            </div>
            <MetaLine parts={metaParts(c)} />
            <p className="t-small mt-2 text-ink-2">{C.dmgLine}</p>
          </Glass>

          {/* iPhone — App Store 배지 · iOS 18 이상 · 무료 · (데스크톱) QR. 390 iOS 기기에서는 맨 앞 */}
          <Glass
            level="regular"
            data-install="iphone"
            className={`${CARD} [html[data-platform=ios]_&]:-order-1 min-[768px]:col-start-2 min-[768px]:row-start-2 desk:row-start-2`}
          >
            <h3 className={CARD_H}>{C.iphoneTitle}</h3>
            <div className="mt-5 flex items-center justify-between gap-5">
              <div className="min-w-0">
                {/* 배지 여백(높이/4 — 애플 규칙)은 그대로 두고, 바깥 음수 여백으로 보이는 배지 왼쪽 위를 글 열에 맞춘다 */}
                <AppStoreBadge height={48} placement="install" className="-m-3" />
                <p className="t-small mt-3.5 text-ink-2">{C.iphoneMeta}</p>
                {/* QR 옆 안내 — QR 과 함께 데스크톱에서만 */}
                <p className="t-small mt-1 hidden text-ink-2 desk:block">{C.qrCaption}</p>
              </div>
              <QrCode size={96} />
            </div>
          </Glass>

          {/* 안드로이드 — 베타 세 단계(§12). desk·768–1023 은 3번째 줄 두 칸 전폭 · 폰은 맨 아래(안드로이드 기기면 맨 앞) */}
          <AndroidCard />
        </div>
      </div>
    </section>
  );
}

export default Install;
