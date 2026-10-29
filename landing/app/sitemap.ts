import type { MetadataRoute } from "next";
import { getRelease } from "@/lib/release";
import { sitemapEntries } from "@/lib/seo";

// sitemap.xml(docs/v3/brief.md §10) — 공개 페이지 셋(첫 페이지 · 글꼴 라이선스 · 계정 삭제), url = 각 페이지 canonical.
// lastmod 은 정직하게: 내용 갱신일(lib/seo.ts CONTENT_UPDATED) — 첫 페이지는 화면에 보이는 버전이 바뀐 날(최신 릴리스)과 비교해 늦은 날.
// 첫 페이지·/api/release 와 같은 1시간 ISR(getRelease 의 fetch 도 revalidate 3600).
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const release = await getRelease();
  return sitemapEntries(release.publishedAt);
}
