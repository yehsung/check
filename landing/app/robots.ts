import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/site";

// robots.txt — 모두 허용 + sitemap 주소(SITE_URL 기준, lib/site.ts).
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
