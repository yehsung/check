// /g/<코드> 의 기기별 행동 섬. 어느 기기 벌을 보일지는 첫 페인트 전 <html data-platform|data-android>(PlatformScript)로
// CSS 가 고른다(첫 페이지 히어로와 같은 방식 — 깜빡임 없음). JS 가 하는 일은 코드 복사뿐이다.
//   아이폰: App Store 배지 + 코드(앱이 있으면 Safari 맨 위 스마트 배너의 '열기'가 이 링크를 앱에 넘긴다).
//   안드로이드: '앱에서 열기'(intent → 앱, 없으면 Play 스토어) + Play 배지 + 코드.
//   맥·그 밖: 코드 크게 + 복사 + 'Mac용 다운로드' + 폰 앱 두 스토어(아이폰·안드로이드 짝 노출).
"use client";

import { LINKS } from "@/data/fixtures";
import { INVITE_COPY, androidIntentUrl } from "@/lib/group-invite";
import { AppStoreBadge } from "@/components/ui/AppStoreBadge";
import { PlayStoreBadge } from "@/components/ui/PlayStoreBadge";
import { CopyButton } from "@/components/glass/CopyButton";
import { DownloadCTA } from "@/components/ui/DownloadCTA";
import { glassButtonClass } from "@/components/glass/GlassButton";

const IOS = "hidden [html[data-platform=ios]_&]:block";
const ANDROID = "hidden [html[data-android]_&]:block";
const DESK = "block [html[data-platform=ios]_&]:hidden [html[data-android]_&]:hidden";

export interface InviteActionsProps {
  code: string;
  showCode: boolean;
  siteHost: string;
}

function CodeBox({ code }: { code: string }) {
  return (
    <div className="mt-8" data-invite-code="">
      <p className="t-small font-semibold text-ink-1">{INVITE_COPY.codeLabel}</p>
      <div className="mt-3 flex flex-wrap items-center gap-3">
        <code className="t-code rounded-xl border border-white/15 bg-white/[.04] px-4 py-3 text-[22px] tracking-[.12em] text-ink-1">{code}</code>
        <CopyButton text={code} label={INVITE_COPY.copy} done={INVITE_COPY.copied} ariaLabel={`${INVITE_COPY.codeLabel} ${INVITE_COPY.copy}`} variant="glass" />
      </div>
    </div>
  );
}

export function InviteActions({ code, showCode, siteHost }: InviteActionsProps) {
  return (
    <div className="mt-10" data-invite-actions="">
      {/* 아이폰 */}
      <div className={IOS} data-invite-device="ios">
        <AppStoreBadge height={48} placement="invite-ios" className="-m-3" />
        {showCode ? (
          <>
            <p className="t-small mt-6 max-w-[36em] text-ink-2">{INVITE_COPY.phoneHow}</p>
            <CodeBox code={code} />
          </>
        ) : null}
      </div>

      {/* 안드로이드 */}
      <div className={ANDROID} data-invite-device="android">
        <div className="flex flex-wrap items-center gap-x-6 gap-y-4">
          {showCode ? (
            <a
              href={androidIntentUrl(siteHost, code, LINKS.androidStore)}
              data-cta="invite-open-android"
              className={glassButtonClass("primary", "l")}
            >
              {INVITE_COPY.openApp}
            </a>
          ) : null}
          <PlayStoreBadge height={48} placement="invite-android" className="-m-3" />
        </div>
        {showCode ? (
          <>
            <p className="t-small mt-6 max-w-[36em] text-ink-2">{INVITE_COPY.phoneHow}</p>
            <CodeBox code={code} />
          </>
        ) : null}
      </div>

      {/* 맥·그 밖 */}
      <div className={DESK} data-invite-device="desktop">
        {showCode ? (
          <>
            <CodeBox code={code} />
            <p className="t-small mt-4 max-w-[36em] text-ink-2">{INVITE_COPY.macHow}</p>
          </>
        ) : null}
        <p className="t-small mt-10 font-semibold text-ink-1">{INVITE_COPY.noApp}</p>
        <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-4">
          <DownloadCTA placement="install" size="l" label={INVITE_COPY.macDownload} ariaLabel={INVITE_COPY.macDownload} />
          <span className="inline-flex items-center">
            <AppStoreBadge height={44} placement="invite-desk" />
            <PlayStoreBadge height={44} placement="invite-desk-play" className="-ml-3" />
          </span>
        </div>
      </div>
    </div>
  );
}

export default InviteActions;
