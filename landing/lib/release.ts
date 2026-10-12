// lib/release.ts — GitHub 최신 릴리스(SPEC §8.5 · PLAN §3.7). 서버(서버 컴포넌트·라우트 핸들러)에서만 부른다.
import { LINKS, RELEASE_FALLBACK } from '@/data/fixtures';
import type { ReleaseAsset, ReleaseInfo } from '@/data/fixtures';

export type { ReleaseAsset, ReleaseInfo } from '@/data/fixtures';
export { RELEASE_FALLBACK } from '@/data/fixtures';

const LATEST_URL = 'https://api.github.com/repos/yehsung/check/releases/latest';
const ASSET_NAMES = ['aing-check.dmg', 'aing-check.zip'] as const;

/** Finder 와 같은 10진 MB, 소수 한 자리(29,959,634B → "30.0"). */
export function formatMB(bytes: number): string {
  return (bytes / 1e6).toFixed(1);
}

type GitHubAsset = { name?: unknown; size?: unknown; browser_download_url?: unknown };
type GitHubRelease = { tag_name?: unknown; published_at?: unknown; assets?: unknown };

function pickAsset(list: GitHubAsset[], name: ReleaseAsset['name']): ReleaseAsset | null {
  const a = list.find((x) => x && x.name === name);
  if (!a || typeof a.size !== 'number' || !(a.size > 0)) return null;
  const url = typeof a.browser_download_url === 'string' && a.browser_download_url.startsWith('https://')
    ? a.browser_download_url
    : name === 'aing-check.dmg' ? LINKS.dmgLatest : LINKS.zipLatest;
  return { name, url, bytes: a.size, mb: formatMB(a.size) };
}

/** 실패·타임아웃(3초)·이상한 응답이면 RELEASE_FALLBACK. 결과는 Next 데이터 캐시에 1시간. */
export async function getRelease(): Promise<ReleaseInfo> {
  try {
    const headers: Record<string, string> = {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'aing-check-landing',
    };
    const token = process.env.GITHUB_TOKEN;
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(LATEST_URL, {
      next: { revalidate: 3600 },
      signal: AbortSignal.timeout(3000),
      headers,
    });
    if (!res.ok) return RELEASE_FALLBACK;
    const json = (await res.json()) as GitHubRelease;
    const tag = typeof json.tag_name === 'string' ? json.tag_name.trim().replace(/^v/i, '') : '';
    if (!/^\d+(\.\d+)*/.test(tag)) return RELEASE_FALLBACK;
    const list = Array.isArray(json.assets) ? (json.assets as GitHubAsset[]) : [];
    const dmg = pickAsset(list, ASSET_NAMES[0]);
    const zip = pickAsset(list, ASSET_NAMES[1]);
    if (!dmg && !zip) return RELEASE_FALLBACK;
    return {
      version: tag,
      publishedAt: typeof json.published_at === 'string' ? json.published_at : null,
      dmg,
      zip,
      source: 'github',
    };
  } catch {
    return RELEASE_FALLBACK;
  }
}

/**
 * 302 대상. ?file=zip 이면 zip, 아니면 DMG(릴리스에 DMG 가 없으면 zip).
 * 자산 URL 이 없으면 releases/latest/download/<파일명>.
 */
export function downloadTarget(r: ReleaseInfo, file: 'dmg' | 'zip'): string {
  if (file === 'zip') return r.zip?.url ?? LINKS.zipLatest;
  return r.dmg?.url ?? r.zip?.url ?? LINKS.dmgLatest;
}
