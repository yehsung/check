// components/hero/copy.ts — 히어로 문장(SPEC v2 §S1 · CB 그대로). 줄바꿈은 lines 가 정본(§1.4.2 · J2-A7).
// import 는 타입뿐이라 node --experimental-strip-types 로 바로 읽힌다.
import type { ReleaseInfo } from '@/data/fixtures';

export const HERO_COPY = {
  /** CB:64 ✓v4 — H1 두 줄(` / ` 위치에 <br>) */
  h1: ['출퇴근 기록을,', '메뉴바 하나로.'],
  /** CB:67 첫 문장 한 줄(brief-v21 §2 — 둘째 문장 삭제) */
  lead: '근무 시작을 누르면 팀 전체에 바로 보여요.',
  /** CB:68 */
  cta: 'Mac용 다운로드',
  /** CB:68 */
  meta: 'macOS 14 이상 · 무료',
  /** CB:243 — iOS(data-platform=ios)에서 배지 아래(설치 절 iPhone 열과 같은 문장, DECISIONS D26-2) */
  metaIos: 'iOS 18 이상 · 무료',
  /** CB:69 — 설치 절로 */
  brew: 'brew로 설치',
} as const;

/**
 * 주 버튼 접근 이름(SPEC §S1 접근성): "Mac용 다운로드, aing-check.dmg 30.1MB".
 * 크기는 getRelease() 의 10진 MB 문자열 그대로(DECISIONS D16 — 하드코딩 금지). 릴리스에 DMG 가 없으면 zip(/api/download 와 같은 순서).
 * 둘 다 없으면 fallback(RELEASE_FALLBACK)으로. 순수 함수.
 */
export function heroCtaAriaLabel(release: ReleaseInfo, fallback: ReleaseInfo): string {
  const rel = release.dmg || release.zip ? release : fallback;
  const file = rel.dmg ?? rel.zip;
  return file ? `${HERO_COPY.cta}, ${file.name} ${file.mb}MB` : HERO_COPY.cta;
}
