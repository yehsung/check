import { BREW, LINKS } from "@/data/fixtures";
import { installChoice } from "@/data/install-copy";
import { FOOTER_LINKS, NAV_LINKS } from "@/data/site-links";
import { getRelease, RELEASE_FALLBACK } from "@/lib/release";
import { llmsTxt } from "@/lib/seo";

// GET /llms.txt(llmstxt.org — docs/v3/brief.md §10): 사이트 문구와 같은 데이터(기능·FAQ·설치 카드 값·링크)로 만든 마크다운.
// 버전·크기·릴리스 날은 GitHub 에서 받았을 때만(live) — 폴백 상수를 '사실'로 1시간 굳히지 않는다.
// 고전 ISR(/api/release 와 같다): 1시간마다 다시 만든다. 본문 생성은 lib/seo.ts llmsTxt(순수 — lib/seo.test.ts).
export const revalidate = 3600;

export async function GET() {
  const release = await getRelease();
  const body = llmsTxt({
    links: LINKS,
    brewInstall: BREW.install,
    choice: installChoice(release, RELEASE_FALLBACK),
    live: release.source === "github",
    publishedAt: release.publishedAt,
    footerLinks: FOOTER_LINKS,
    navLinks: NAV_LINKS,
  });
  return new Response(body, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400",
    },
  });
}
