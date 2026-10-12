// lib/site.ts — 배포 주소(메타·robots·sitemap 이 함께 쓴다).
// NEXT_PUBLIC_SITE_URL(배포 도메인)을 먼저, 없으면 Vercel 이 주는 프로덕션 도메인, 그것도 없으면 로컬.
// metadataBase 를 직접 주면 Next 가 VERCEL_PROJECT_PRODUCTION_URL 로 바꿔 주지 않으므로 여기서 같은 폴백을 건다
// (환경 변수 없이 배포해도 og:image·twitter:image 가 localhost 를 가리키지 않게).
const vercel = process.env.VERCEL_PROJECT_PRODUCTION_URL;

export const SITE_URL: string =
  process.env.NEXT_PUBLIC_SITE_URL || (vercel ? `https://${vercel}` : "http://localhost:3000");

export const SITE_NAME = "아잉체크";

/** 공유 카드 그림(app/opengraph-image.png 1200×630 과 같은 파일) — 하위 페이지가 openGraph 를 덮어써도 그림을 잃지 않게 함께 쓴다. */
export const OG_IMAGE = { url: "/opengraph-image.png", width: 1200, height: 630, alt: "보라 돔 아래 아잉이 '오늘도 화이팅!' 하고, 돔 꼭대기에 메뉴바 라벨 00:00. 출퇴근 기록을, 메뉴바 하나로." } as const; // SPEC §8 · DECISIONS D8(통합 재촬영 2026-10-12)
