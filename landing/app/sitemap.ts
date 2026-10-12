import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/site";

// sitemap.xml — 공개 페이지 둘(첫 페이지 · 글꼴 라이선스).
export default function sitemap(): MetadataRoute.Sitemap {
  return [
    { url: `${SITE_URL}/`, changeFrequency: "weekly", priority: 1 },
    { url: `${SITE_URL}/licenses`, changeFrequency: "yearly", priority: 0.2 },
  ];
}
