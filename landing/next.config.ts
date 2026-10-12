import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // cacheComponents(옛 PPR/dynamicIO)는 끈다 — 고전 ISR(`export const revalidate`)과 라우트 핸들러 fetch 를 그대로 쓰기 위해.
  images: { unoptimized: true },
  poweredByHeader: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
