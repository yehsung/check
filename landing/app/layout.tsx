import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { PlatformScript } from "@/components/ui/PlatformScript";
import { AuroraField } from "@/components/glass/AuroraField";
import { GlassDefs } from "@/components/glass/GlassDefs";
import { APP_STORE_ID } from "@/data/fixtures";
import { OG_IMAGE, SITE_NAME, SITE_URL } from "@/lib/site";
import "./globals.css";

// 글꼴(docs/v3/brief.md §3): 제목·버튼 = Pretendard 600(첫 화면 H1 — preload) + JetBrains Mono ASCII(brew 알약·터미널). 본문은 시스템 글꼴(0B).
// 파일은 scripts/subset-fonts.mjs 가 만든다(public/fonts/*). v2 의 500·300 숫자 서브셋은 v3 에서 쓰는 곳이 없어 불러오지 않는다(파일·check-glyphs 검사는 남겨 둔다).
// 글꼴 로더 인자는 리터럴이어야 한다(Next: "Font loader values must be explicitly written literals").
const ptd600 = localFont({
  src: "../public/fonts/pretendard-600-sub.woff2",
  weight: "600",
  display: "swap",
  preload: true,
  variable: "--font-ptd-600",
  fallback: ["-apple-system", "BlinkMacSystemFont", "Apple SD Gothic Neo", "system-ui"],
});
const jbm = localFont({
  src: "../public/fonts/jbm-400-ascii.woff2",
  weight: "400",
  display: "swap",
  preload: false, // 루트 레이아웃 preload 는 /licenses 에도 붙는다(거기선 안 쓴다 — 'preloaded but not used' 경고). 4.4KB 라 CSS 에서 바로 찾는다
  variable: "--font-jbm",
});

// 문구 정본: docs/v3/brief.md §8 메타.
const TITLE = "아잉체크: Mac 메뉴바 근무 타이머";
const DESCRIPTION = "근무 타이머부터 AI 리밋·토큰 확인, 1:1 메시지, 미니게임까지 맥 메뉴바에서 무료로 써요.";

// OG·트위터 이미지: app/opengraph-image.png(1200×630, 통합 단계에서 재촬영 — DECISIONS D8) + 같은 alt.
// 파일 규약(opengraph-image.png · .alt.txt)이 config 보다 우선하므로 og:image 는 파일이, twitter:image 는 아래 config 가 낸다.
// 그림 정의(OG_IMAGE)는 lib/site.ts — /licenses 도 같은 그림을 쓴다.

// 메타(docs/v3/brief.md §8).
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/" },
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    url: "/",
    siteName: SITE_NAME,
    type: "website",
    locale: "ko_KR",
    images: [OG_IMAGE],
  },
  twitter: { card: "summary_large_image", title: TITLE, description: DESCRIPTION, images: [OG_IMAGE] },
  // <meta name="apple-itunes-app" content="app-id=6812768622"> — iOS 사파리 스마트 배너
  itunes: { appId: APP_STORE_ID },
};

export const viewport: Viewport = {
  themeColor: "#090713", // --bg(§3)
  colorScheme: "dark",
};

// 히어로 팝오버 렌더(LCP — docs/v3/brief.md §4.3)의 preload 는 첫 페이지에서만(app/page.tsx 의 react-dom preload()).
// 여기 두면 /licenses 가 "preloaded but not used" 경고를 낸다.

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    // data-platform·class "js" 는 첫 페인트 전에 PlatformScript 가 단다 → <html> 속성 차이 경고를 끈다.
    // data-scroll-behavior="smooth": globals.css 의 html { scroll-behavior:smooth } 를 라우트 이동(/licenses ↔ /) 동안
    // Next 가 잠시 auto 로 내린다(Next 16 은 이 속성이 있어야 그렇게 한다 — upgrading/version-16.md 'Scroll Behavior Override').
    <html
      lang="ko"
      className={`${ptd600.variable} ${jbm.variable}`}
      data-scroll-behavior="smooth"
      suppressHydrationWarning
    >
      <head>
        <PlatformScript />
      </head>
      {/* 오로라 장(fixed, z -1 — 모든 페이지 바탕) · 굴절 SVG 필터 자리(useRefraction 이 요소마다 <filter> 를 넣는다) */}
      <body>
        <AuroraField />
        {children}
        <GlassDefs />
      </body>
    </html>
  );
}
