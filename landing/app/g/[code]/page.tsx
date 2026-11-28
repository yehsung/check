// /g/<코드> — 그룹 초대 링크 페이지(구조 개편 DV-14 · 서버 계약 판 1 §9 랜딩 칸).
// 서버 렌더: 요청마다 `team_preview`(anon·읽기만) 를 불러 그룹 이름·인원을 보여 주고, 기기별 행동은 섬(InviteActions)이 정한다.
//   아이폰: 앱이 있으면 링크가 앱으로 바로 열린다(연결 도메인). 이 페이지가 보이면 Safari 스마트 배너('열기')·App Store·코드.
//   안드로이드: '앱에서 열기'(intent — 앱이 없으면 Play 스토어로) · Play 스토어 · 코드.
//   맥·그 밖: 코드 크게 + 복사 · 'Mac용 다운로드' · 폰 앱 두 스토어(짝 노출 원칙 — memo feedback-ios-android-parity-on-landing).
// 사생활: 그룹 이름은 본문에만. 제목·미리보기(OG)·검색에는 싣지 않는다(noindex). 캐시하지 않는다(코드는 바뀌고 만료된다).
// 글꼴: 그룹 이름은 사람이 지은 글자라 웹 글꼴 서브셋에 없을 수 있다 → 시스템 글꼴로 그린다.

import type { Metadata } from "next";
import { LINKS } from "@/data/fixtures";
import { SITE_NAME, SITE_URL } from "@/lib/site";
import { readConfig } from "@/lib/delete-account";
import {
  INVITE_COPY,
  fetchGroupPreview,
  normalizeInviteCode,
  showsCode,
  smartBannerAppId,
  type PreviewFetch,
} from "@/lib/group-invite";
import { LicensesNav } from "@/components/site/LicensesNav";
import { SiteFooter } from "@/components/site/SiteFooter";
import { InviteActions } from "./InviteActions";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ code: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const code = normalizeInviteCode((await params).code);
  const pageUrl = `${SITE_URL}/g/${encodeURIComponent(code)}`;
  const appId = smartBannerAppId(LINKS.appStore);
  return {
    title: INVITE_COPY.title,
    description: INVITE_COPY.description,
    robots: { index: false, follow: false },
    openGraph: { title: INVITE_COPY.title, description: INVITE_COPY.description, siteName: SITE_NAME, type: "website", locale: "ko_KR" },
    // 루트 레이아웃의 스마트 배너(app-id 만)를 덮어써 이 주소를 앱에 넘긴다(앱이 있으면 배너가 '열기').
    ...(appId ? { itunes: { appId, appArgument: pageUrl } } : {}),
  };
}

const CONFIG = readConfig(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
const serverFetch: PreviewFetch = (url, init) => fetch(url, init);

export default async function GroupInvitePage({ params }: Params) {
  const code = normalizeInviteCode((await params).code);
  const result = await fetchGroupPreview(serverFetch, CONFIG, code);
  const siteHost = new URL(SITE_URL).host;

  return (
    <>
      <LicensesNav />
      <main id="main">
        <div className="px-[var(--gutter)] phone:py-18 tab:py-24 desk:py-30">
          <p className="t-small text-ink-3">{INVITE_COPY.eyebrow}</p>

          {result.status === "ok" ? (
            <>
              <h1 className="t-h2 mt-3 break-words text-ink-1 [font-family:var(--font-sans)]" data-group-name="">
                {result.group.name}
              </h1>
              <p className="t-body mt-4">
                {INVITE_COPY.members(result.group.memberCount)}
                {result.group.weeklyGoalHours ? ` · ${INVITE_COPY.goal(result.group.weeklyGoalHours)}` : ""}
              </p>
              {result.group.needsApproval ? <p className="t-small mt-2 text-ink-2">{INVITE_COPY.approval}</p> : null}
            </>
          ) : (
            <>
              <h1 className="t-h2 mt-3 text-ink-1">{INVITE_COPY.status[result.status].title}</h1>
              <p className="t-body mt-4">{INVITE_COPY.status[result.status].body}</p>
            </>
          )}

          <InviteActions code={code} showCode={showsCode(result.status)} siteHost={siteHost} />
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
