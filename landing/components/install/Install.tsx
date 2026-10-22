// components/install/Install.tsx — 설치 #install(docs/v3/brief.md §4.5 · 문구 §8 '설치' · §9.3). server 컴포넌트 — 움직이는 건 BrewTerminal 하나.
// brew 가 주인공: 가운데 H2 두 줄 + 부제 → 왼쪽(넓게 ≈60%) regular 유리 터미널 / 오른쪽 regular 유리 카드 둘
// (Homebrew를 안 쓴다면 — DMG · 아이폰에서도 — App Store·QR). v3.1(§9.3): 터미널 아래 업데이트 줄은 지웠다(upgrade 명령을 보이지 않는다).
//
// 배치
//   desk(≥1024·≥640) : 2열 [1.6fr | 1fr]. 왼쪽 열 = 터미널(카드 둘 높이를 채운다), 오른쪽 = DMG 카드 위 · iPhone 카드 아래
//   768–1023         : 터미널 전폭 → 아래 DMG · iPhone 카드 두 칸
//   390              : 터미널(명령 한 줄 · [복사] 는 제목 줄 · 출력 긴 줄만 줄바꿈) → DMG 카드 → iPhone 카드.
//                      <html data-platform=ios> 면 iPhone 카드가 맨 앞(768 이상은 칸 자리를 못박아 순서가 그대로)
// 빛: 절 뒤 LocalLight 셋(터미널 뒤 보라 넓게 · 카드 뒤 인디고 · 위 오키드) — 어느 스크롤 위치에서도 유리 뒤에 색이 있다.
// 버전·크기는 릴리스 API 값(getRelease → installChoice) — 하드코딩 금지. 명령 문자열은 BREW(data/fixtures) 정본.
import { Fragment } from 'react';
import type { ReleaseInfo } from '@/lib/release';
import { RELEASE_FALLBACK } from '@/lib/release';
import { BREW } from '@/data/fixtures';
import { INSTALL_COPY, brewTranscript, installChoice, metaParts } from '@/data/install-copy';
import { Glass } from '@/components/glass/Glass';
import { LocalLight } from '@/components/glass/LocalLight';
import { Headline } from '@/components/ui/Headline';
import { DownloadCTA } from '@/components/ui/DownloadCTA';
import { AppStoreBadge } from '@/components/ui/AppStoreBadge';
import { QrCode } from '@/components/ui/QrCode';
import { BrewTerminal } from './BrewTerminal';

const C = INSTALL_COPY;

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
        </div>
      </div>
    </section>
  );
}

export default Install;
