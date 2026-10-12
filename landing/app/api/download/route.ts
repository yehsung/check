import { NextResponse, type NextRequest } from "next/server";
import { downloadTarget, getRelease } from "@/lib/release";

// GET /api/download → 302 GitHub 릴리스 자산(SPEC §8.5). DMG 기본, ?file=zip 이면 zip.
// 릴리스에 DMG 가 없으면 zip, 자산 URL 이 없으면 releases/latest/download/<파일명>.
export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  const file = req.nextUrl.searchParams.get("file") === "zip" ? "zip" : "dmg";
  const target = downloadTarget(await getRelease(), file);
  return NextResponse.redirect(target, { status: 302, headers: { "Cache-Control": "no-store" } });
}
