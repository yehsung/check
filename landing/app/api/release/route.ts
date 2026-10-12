import { getRelease } from "@/lib/release";

// GET /api/release → 릴리스 JSON(SPEC §8.5). 고전 ISR(cacheComponents 꺼짐): 1시간마다 다시 만든다.
export const revalidate = 3600;

export async function GET() {
  const release = await getRelease();
  return Response.json(release, {
    headers: { "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400" },
  });
}
