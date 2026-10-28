// 원본: Sources/CheckMobileKit/Me/MeText.swift @ 1b8260d (계정 삭제 문구 — 885–925)
// 원본: docs/privacy.md @ 1b8260d (계정 삭제 절 — 149–164: 지워지는 것 · 같이 처리되는 것)
//
// /delete-account — Play Data safety 가 요구하는 **웹 계정 삭제 경로**(G §2-3 W2-i · E§9.6). 서버 컴포넌트: 정적 안내 + 흐름 섬(client).
// Play 요구(answer/13327111): 앱·개발자 이름을 등록정보 그대로 · 삭제 경로가 눈에 띄게 · 앱으로 되돌려 보내지 않고 이 페이지에서 끝 ·
// 추가 단계가 있으면 밝히고 지원 경로를 둔다 · 남는 데이터와 보관 기간을 밝힌다(기간은 처리방침에).
// 글꼴: 제목(t-h2·t-h4)만 Pretendard 600, 나머지는 시스템 글꼴(t-body·t-small) — /licenses 와 같은 결(docs/v3/brief.md §3).
// 문구 규칙: 랜딩 금지어(판돈·센터·이메일 인증 …)를 쓰지 않는다 — lib/delete-account-page.test.ts 가 이 파일을 읽어 잰다.

import type { Metadata } from "next";
import { LINKS } from "@/data/fixtures";
import { OG_IMAGE, SITE_NAME } from "@/lib/site";
import { STORE_LISTING } from "@/lib/delete-account";
import { Headline } from "@/components/ui/Headline";
import { LicensesNav } from "@/components/site/LicensesNav";
import { SiteFooter } from "@/components/site/SiteFooter";
import { DeleteAccountFlow } from "./DeleteAccountFlow";

const TITLE = "아잉체크: 계정 삭제";
const DESCRIPTION = "아잉체크 계정과 그 계정의 기록을 웹에서 영구히 지워요. 앱이 없어도 본인 확인만 하면 바로 끝나요.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/delete-account" },
  // openGraph·twitter 는 얕게 덮어써지므로(Next 메타 병합 규칙) 그림·사이트 이름까지 함께 준다(/licenses 와 같다)
  openGraph: { title: TITLE, description: DESCRIPTION, url: "/delete-account", siteName: SITE_NAME, type: "website", locale: "ko_KR", images: [OG_IMAGE] },
  twitter: { card: "summary_large_image", title: TITLE, description: DESCRIPTION, images: [OG_IMAGE] },
};

/** 지워지는 것 — 서버 delete_my_account 가 지우는 범위(계정 행 + FK cascade). 순서는 사람이 아까워할 것부터(MeText.deleteAccountItems). */
const DELETED = [
  "계정(로그인 자체)과 프로필(별명·사진·상태메시지)",
  "근무 기록",
  "메시지와 읽음 위치, 콕 찌르기 기록",
  "할 일",
  "캐릭터와 루비, 상점·뽑기 기록",
  "순위 기록",
  "미니게임 기록과 오목·체스·테트리스 대국 기록·대국 채팅",
  "미션 진행 기록",
  "AI 토큰 기록과 사용량 리밋 기록",
  "기기 등록과 알림 설정",
] as const;

/** 같이 처리되는 것(docs/privacy.md 계정 삭제 절 + delete_my_account 의 대국 정리). */
const ALSO = [
  "진행 중이던 오목·체스·테트리스 대국은 지우기 전에 내가 진 것으로 끝내요. 상대가 걸었던 루비가 사라지지 않게 하려는 거예요.",
  "나 혼자 남아 있던 팀은 함께 지워져요. 다른 사람이 남은 팀은 그대로예요.",
  "차단 기록은 내가 한 것도, 남이 나를 차단한 것도 함께 지워져요.",
  "다른 사람이 받은 메시지 중 내가 보낸 것도 함께 지워져요.",
] as const;

/**
 * 남는 것 — 숨기지 않고 밝힌다. 서버 백업은 처리방침과 같이 다루지 않는다(사용자 결정 2026-10-28, 무료 요금제) —
 * lib/delete-account-page.test.ts ②-2 가 두 파일 어디에도 백업 문장이 없는지 잰다.
 */
const KEPT = [
  "보낸 제보와 신고는 작성자 없이 내용만 남아요. 버그를 고치고 신고를 처리한 기록이라서예요.",
] as const;

const H2 = "t-h4 text-ink-1";
const LIST = "t-small mt-4 max-w-[44em] list-disc space-y-2 pl-5 text-ink-2 marker:text-ink-3";
const LINK = "underline decoration-white/30 underline-offset-4 hover:text-ink-1 hover:decoration-white/60";

export default function DeleteAccountPage() {
  return (
    <>
      <LicensesNav />
      <main id="main">
        <div className="px-[var(--gutter)] phone:py-18 tab:py-24 desk:py-30">
          <p className="t-small text-ink-3">
            {STORE_LISTING.appName} · 개발자 {STORE_LISTING.developerName}
          </p>
          <Headline level={1} size="h2" lines={[`${STORE_LISTING.appName} 계정 삭제`]} className="mt-3" />
          <p className="t-body mt-5">
            {STORE_LISTING.appName} 계정과 그 계정에 쌓인 기록을 서버에서 영구히 지워요. 앱이 없어도 이 페이지에서 본인 확인만 하면 바로 끝나요.
            지운 계정은 되돌릴 수 없고, 맥·아이폰 앱도 곧 로그아웃돼요.
          </p>

          <section aria-labelledby="deleted-title" className="mt-14">
            <h2 id="deleted-title" className={H2}>
              지워지는 것
            </h2>
            <ul role="list" className={LIST}>
              {DELETED.map((t) => (
                <li key={t}>{t}</li>
              ))}
            </ul>
          </section>

          <section aria-labelledby="also-title" className="mt-12">
            <h2 id="also-title" className={H2}>
              같이 처리되는 것
            </h2>
            <ul role="list" className={LIST}>
              {ALSO.map((t) => (
                <li key={t}>{t}</li>
              ))}
            </ul>
          </section>

          <section aria-labelledby="kept-title" className="mt-12">
            <h2 id="kept-title" className={H2}>
              남는 것
            </h2>
            <ul role="list" className={LIST}>
              {KEPT.map((t) => (
                <li key={t}>{t}</li>
              ))}
            </ul>
            <p className="t-small mt-4 text-ink-2">
              자세한 내용은{" "}
              <a href={LINKS.privacy} target="_blank" rel="noopener noreferrer" className={LINK}>
                개인정보 처리방침
              </a>
              에 있어요.
            </p>
          </section>

          <DeleteAccountFlow />

          <section aria-labelledby="app-title" className="mt-14">
            <h2 id="app-title" className={H2}>
              앱에서 지우기
            </h2>
            <ul role="list" className={LIST}>
              <li>아이폰: 나 → 설정 → 계정 삭제</li>
              <li>맥: 설정 → 내 정보 → 계정 삭제</li>
            </ul>
          </section>

          <section aria-labelledby="help-title" className="mt-12">
            <h2 id="help-title" className={H2}>
              메일함도 쓸 수 없다면
            </h2>
            <p className="t-small mt-4 max-w-[44em] text-ink-2">
              비밀번호도, 가입한 메일함도 쓸 수 없으면 본인인지 확인할 방법이 없어 계정을 지울 수 없어요. 남의 계정이 지워지는 일을 막으려고
              운영자가 대신 지워 주지도 않아요.{" "}
              <a href={LINKS.issues} target="_blank" rel="noopener noreferrer" className={LINK}>
                GitHub Issues
              </a>
              로 문의해 주세요. 공개 게시판이라 이메일 주소는 적지 마세요.
            </p>
          </section>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
