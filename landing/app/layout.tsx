import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { PlatformScript } from "@/components/ui/PlatformScript";
import { APP_STORE_ID } from "@/data/fixtures";
import { OG_IMAGE, SITE_NAME, SITE_URL } from "@/lib/site";
import "./globals.css";

// 글꼴(PLAN v2 §3.9 · DECISIONS D5): Pretendard 500(H1·클로징·격자 제목) · 600(H2·H3·H4·캡션·FAQ) · 300 숫자 전용 + JetBrains Mono ASCII.
// 파일은 assets 에이전트가 만든다(public/fonts/*, scripts/subset-fonts.mjs). 본문은 시스템 글꼴(0B).
// 글꼴 로더 인자는 리터럴이어야 한다(Next: "Font loader values must be explicitly written literals").
const ptd500 = localFont({
  src: "../public/fonts/pretendard-500-sub.woff2",
  weight: "500",
  display: "swap",
  preload: true,
  variable: "--font-ptd-500",
  fallback: ["-apple-system", "BlinkMacSystemFont", "Apple SD Gothic Neo", "system-ui"],
});
const ptd600 = localFont({
  src: "../public/fonts/pretendard-600-sub.woff2",
  weight: "600",
  display: "swap",
  preload: false,
  variable: "--font-ptd-600",
  fallback: ["-apple-system", "BlinkMacSystemFont", "Apple SD Gothic Neo", "system-ui"],
});
const ptd300n = localFont({
  src: "../public/fonts/pretendard-300-num.woff2",
  weight: "300",
  display: "swap",
  preload: true,
  variable: "--font-ptd-300n",
});
const jbm = localFont({
  src: "../public/fonts/jbm-400-ascii.woff2",
  weight: "400",
  display: "swap",
  preload: false,
  variable: "--font-jbm",
});

const TITLE = "아잉체크: 작은 Mac 팀을 위한 메뉴바 근무 타이머";
const DESCRIPTION = "근무 시작을 누르면 팀 전체에 바로 보여요. 맥 메뉴바에서 근무 시간을 재고, 아이폰에서도 팀 현황을 봐요.";

// OG·트위터 이미지: app/opengraph-image.png(1200×630, 통합 단계에서 재촬영 — DECISIONS D8) + 같은 alt.
// 파일 규약(opengraph-image.png · .alt.txt)이 config 보다 우선하므로 og:image 는 파일이, twitter:image 는 아래 config 가 낸다.
// 그림 정의(OG_IMAGE)는 lib/site.ts — /licenses 도 같은 그림을 쓴다.

// 메타(SPEC v2 §8 — v1 그대로).
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
  themeColor: "#0C0A14",
  colorScheme: "dark",
};

// 히어로 아잉 포스터(phone LCP — SPEC §5.4)의 preload 는 첫 페이지에서만(app/page.tsx 의 react-dom preload() — DECISIONS D19-4).
// 여기 두면 /licenses 가 "preloaded but not used" 경고를 낸다.

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    // data-platform·class "js" 는 첫 페인트 전에 PlatformScript 가 단다 → <html> 속성 차이 경고를 끈다.
    // data-scroll-behavior="smooth": globals.css 의 html { scroll-behavior:smooth } 를 라우트 이동(/licenses ↔ /) 동안
    // Next 가 잠시 auto 로 내린다(Next 16 은 이 속성이 있어야 그렇게 한다 — upgrading/version-16.md 'Scroll Behavior Override').
    <html
      lang="ko"
      className={`${ptd500.variable} ${ptd600.variable} ${ptd300n.variable} ${jbm.variable}`}
      data-scroll-behavior="smooth"
      suppressHydrationWarning
    >
      <head>
        <PlatformScript />
      </head>
      <body>{children}</body>
    </html>
  );
}
