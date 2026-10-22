// components/hero/copy.ts — 히어로 문장(docs/v3/brief.md §8 · 폰 메타는 §9.4.1 글자 그대로). 줄바꿈은 h1 배열이 정본(줄마다 <br>).
// import 는 타입뿐이라 node --experimental-strip-types 로 바로 읽힌다(copy.test.ts).
import type { ReleaseInfo } from '@/data/fixtures';

export const HERO_COPY = {
  /** H1 두 줄 */
  h1: ['메뉴바에서 바로 켜는', '근무 타이머'],
  lead: '근무 시작을 클릭하면 타이머가 돌고, 팀원들도 곧바로 알 수 있어요.',
  /** 주 버튼 */
  cta: 'Mac용 다운로드',
  /** brew 알약의 복사 버튼 접근 이름(보이는 글자 '복사' 포함) */
  brewCopyAria: 'brew 설치 명령 복사',
  /** 버튼 줄 아래 메타(≥768 · iOS 아님) */
  meta: '무료 · macOS 14 이상 · Apple 공증',
  /** 폰(< 768)·iOS 기기(§9.4.1) — [App Store 배지] [Mac용 다운로드] 아래 메타 */
  metaPhone: '무료 · iOS 18 이상 · macOS 14 이상',
  /** 작은 링크(#install) */
  install: '설치 방법 보기',
} as const;

/**
 * 주 버튼 접근 이름: "Mac용 다운로드, aing-check.dmg 30.1MB".
 * 크기는 getRelease() 의 10진 MB 문자열 그대로(하드코딩 금지). 릴리스에 DMG 가 없으면 zip(/api/download 와 같은 순서).
 * 둘 다 없으면 fallback(RELEASE_FALLBACK)으로. 순수 함수.
 */
export function heroCtaAriaLabel(release: ReleaseInfo, fallback: ReleaseInfo): string {
  const rel = release.dmg || release.zip ? release : fallback;
  const file = rel.dmg ?? rel.zip;
  return file ? `${HERO_COPY.cta}, ${file.name} ${file.mb}MB` : HERO_COPY.cta;
}
