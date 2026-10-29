import type { MetadataRoute } from "next";
import { robotsConfig } from "@/lib/seo";

// robots.txt(docs/v3/brief.md §10) — 모두 허용 · /api/ 만 막음(DMG 302 · 릴리스 JSON) · 검색·AI 크롤러를 이름으로 적어 정책을 분명히 ·
// sitemap 주소(SITE_URL 기준). 규칙 정본과 시험은 lib/seo.ts · lib/seo.test.ts.
export default function robots(): MetadataRoute.Robots {
  return robotsConfig();
}
