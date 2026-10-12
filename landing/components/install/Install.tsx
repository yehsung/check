// components/install/Install.tsx — 설치 #install(SPEC v2 §S6 · brief-v21 §2·§5 · DECISIONS D9·D16·D18). server 컴포넌트.
// v2.1 압축: H2 + Mac 열(DMG 버튼 · 메타 1줄 · 3단계 · brew 명령+복사) + iPhone 열(배지 · QR · "iOS 18 이상 · 무료") + 업데이트 1줄.
// 팀 참여 3걸음(FAQ "팀 코드는 어디서 받나요?"가 맡는다)·"GitHub Releases에서 zip으로 받기" 링크(/api/download?file=zip 라우트는 유지)·
// "터미널이 편하다면" 라벨·iPhone "근무 시작·종료는 맥에서 해요."(장면 6 이 말한다)는 뺐다. 단계는 처음부터 정적(v1 installHint 없음).
//
// 배치
//   1440 : 윗변 .horizon(돔 림을 편 선, 10–90%) · 세로 격자 10/50/90 · 절 뒤 가로 오로라 띠(.aurora-band — 높이 420, α .14)
//          가운데 H2 → Mac 열(왼쪽) / iPhone 열(오른쪽) → 두 열 아래 전폭 업데이트 한 줄. 목표 높이 ≈ 620
//   768  : 같은 두 열 · QR 숨김(QrCode 가 desk 만)
//   390  : 한 열. data-platform=ios 면 iPhone 묶음이 먼저(.order-ios-first — 768 이상은 열 자리를 못박아 Mac 이 왼쪽 그대로)
//          명령은 '/' 뒤 <wbr>(CommandBox), 가로 스크롤 0
// 움직임: 버튼 호버·눌림뿐(프리미티브 몫). 감속 모션에서도 같다. 빛은 늘 켜진 오로라 띠 + 빛나는 수평선 + 스파인 연장(filter 없음 — R1).
// 주 버튼은 iOS 에서도 같은 DMG 링크(설치 절은 플랫폼과 무관하게 Mac 안내 — DownloadCTA placement="install").
import { Fragment } from 'react';
import type { ReleaseInfo } from '@/lib/release';
import { RELEASE_FALLBACK } from '@/lib/release';
import { ALT, BREW } from '@/data/fixtures';
import { INSTALL_COPY, installChoice } from '@/data/install-copy';
import { Headline } from '@/components/ui/Headline';
import { DownloadCTA } from '@/components/ui/DownloadCTA';
import { CommandBox } from '@/components/ui/CommandBox';
import { AppStoreBadge } from '@/components/ui/AppStoreBadge';
import { QrCode } from '@/components/ui/QrCode';
import { RenderImage } from '@/components/ui/RenderImage';
import { Gridlines } from '@/components/ui/Gridlines';

const C = INSTALL_COPY;

/** 메타 줄: "v0.3.49 · 30.1MB · macOS 14 Sonoma 이상 · Apple Silicon·Intel · Apple 공증" — 항목은 끊지 않고, '·' 는 앞 항목 끝에 붙여
 *  줄머리에 '·' 가 오지 않게 한다(줄바꿈은 항목 사이 공백에서만). */
function MetaLine({ parts }: { parts: readonly string[] }) {
  return (
    <p data-install-meta className="t-small mt-2.5 text-ink-3">
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

// 세로 격자가 수평선(섹션 윗변)부터 업데이트 줄 위까지 내려오도록, 윗 패딩을 이 전폭 상자가 갖는다.
const TOP = 'relative pt-18 pb-10 min-[768px]:pt-20 desk:pt-24';
const COLS = 'mt-10 grid gap-12 min-[768px]:grid-cols-2 min-[768px]:gap-x-12 desk:gap-x-16';

export function Install({ release }: { release: ReleaseInfo }) {
  const c = installChoice(release, RELEASE_FALLBACK);
  return (
    <section
      id="install"
      aria-labelledby="install-h"
      data-release={c.version}
      className="relative pb-18 min-[768px]:pb-20"
    >
      {/* 절 뒤 가로 오로라 띠(brief-v21 §5 — 늘 켜짐, 글 뒤 z -1) */}
      <div aria-hidden="true" className="aurora-band" />
      <div aria-hidden="true" className="horizon" />
      {/* 10% 스파인의 연장(DECISIONS D27-2(c) — 구조물, desk 만) */}
      <div aria-hidden="true" className="spine-ext hidden desk:block" />

      <div className={TOP}>
        {/* 세로 격자는 업데이트 줄 위에서 뚝 끊기지 않게 아래 96px 동안 흐려진다(review-design P2-4) */}
        <div aria-hidden="true" className="absolute inset-0 [mask-image:linear-gradient(#000_calc(100%-96px),transparent)]">
          <Gridlines lines="all" />
        </div>
        <div className="relative px-(--gutter)">
          <Headline level={2} size="h2" lines={C.h2} id="install-h" className="text-center" />

          <div className={COLS}>
            {/* Mac — DMG 주 버튼 · 메타 · 세 단계 · brew 명령 */}
            <div data-install="mac" className="min-w-0 min-[768px]:col-start-1 min-[768px]:row-start-1">
              <h3 className="t-kicker">{C.macTitle}</h3>
              <div className="mt-3 flex">
                <DownloadCTA
                  placement="install"
                  size="l"
                  tone="fill"
                  file={c.file}
                  label={c.label}
                  ariaLabel={c.ariaLabel}
                />
              </div>
              <MetaLine parts={[`v${c.version}`, `${c.mb}MB`, ...C.metaTail]} />

              <ol className="t-body mt-5 list-decimal space-y-1 pl-5 text-ink-2 marker:text-ink-3">
                <li>{C.steps[0]}</li>
                <li>{C.steps[1]}</li>
                <li>
                  {C.steps[2]}
                  {/* 실제로 뜨는 라벨(오프) — 185×66 → 92.5×33 */}
                  <RenderImage
                    asset="ui/menubar-off"
                    widthPt={92.5}
                    heightPt={33}
                    alt={ALT['ui/menubar-off'] ?? ''}
                    className="ml-3 inline-block h-[33px] w-[92.5px] align-middle"
                  />
                </li>
              </ol>

              <CommandBox className="mt-6" command={BREW.install} copyAriaLabel={C.copyAria} />
            </div>

            {/* iPhone — App Store 배지 · QR(desk) · 요구 사항. 390 iOS 에서는 먼저 */}
            <div
              data-install="iphone"
              className="order-ios-first min-w-0 min-[768px]:col-start-2 min-[768px]:row-start-1"
            >
              <h3 className="t-kicker">{C.iphoneTitle}</h3>
              <div className="mt-3 flex items-start gap-8">
                <div className="min-w-0">
                  {/* 배지 여백(높이/4)은 그대로 두고, 바깥 음수 여백으로 보이는 배지 왼쪽 위를 글 열에 맞춘다 */}
                  <AppStoreBadge height={48} placement="install" className="-m-3" />
                  <p className="t-small mt-4 text-ink-2">{C.iphoneMeta}</p>
                </div>
                <QrCode size={112} />
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="relative px-(--gutter)">
        {/* 업데이트 한 줄(DECISIONS D18) — 두 열 아래 전폭. 앞에 작은 점이 뜬 메뉴바 아이콘(장식, alt="") */}
        <p data-install="update" className="t-small flex items-start gap-2.5 text-ink-2">
          <RenderImage
            asset="ui/menubar-icon-dot"
            widthPt={16}
            heightPt={16}
            alt={ALT['ui/menubar-icon-dot'] ?? ''}
            className="mt-[3px] block size-4 shrink-0"
          />
          <span>{C.updateLine}</span>
        </p>
      </div>
    </section>
  );
}

export default Install;
