// components/hero/Hero.tsx — 히어로 #top(SPEC v2 §S1 · PLAN §4.1). server 컴포넌트 — 움직이는 부분은 HeroStage(client 섬).
// 큰 것은 돔 하나, 그 안의 물체는 아잉 하나. 첫 페인트(SSR)에 돔·라벨·H1·리드·버튼·메타·포스터가 바로 보인다(불투명 0 시작 없음).
// 말풍선·근무 라벨은 .js 일 때만 도착 전 숨김(globals §2.8) — JS 가 없거나 감속 모션이면 도착 뒤 상태 그대로.
//
// 세로 흐름(SPEC §S1 '세로 흐름 규칙'): 라벨(위 = --dome-top + 14) → 20 → H1 → 20 → 리드 → 28 → 버튼 줄 → 14 → 메타
//   → 유연 여백(flex 1, 최소 0) → 아잉 무대(아래 여백 16). 불변식 '말풍선 윗변 − 메타 아랫변 ≥ 16' 은 HeroStage 의 무대
//   음수 윗여백(16 − 말풍선 오프셋)이 지킨다 — 화면이 짧으면 히어로가 길어진다(min-height 100svh, 고정 높이 아님).
// 돔 패럴랙스는 globals 의 `#top { view-timeline }` + `#top .dome` 규칙이 건다(여기서는 id·구조만). 절은 overflow:clip —
//   돔·웅덩이가 가로로 넘치지 않게(스크롤 컨테이너를 만들지 않는다 → sticky·view-timeline 무해, SPEC §5.4).
// 금지(SPEC §S1): 팝오버·근무 버튼 흉내·핫스팟·커서·아잉 클릭 반응·말풍선 둘 이상·펄스·점 격자·눈썹 칩·돔 안 워시.
import { Dome } from '@/components/ui/Dome';
import { RenderImage } from '@/components/ui/RenderImage';
import { Headline } from '@/components/ui/Headline';
import { DownloadCTA } from '@/components/ui/DownloadCTA';
import { AppStoreBadge } from '@/components/ui/AppStoreBadge';
import { TextLink } from '@/components/ui/TextLink';
import { ALT, RELEASE_FALLBACK } from '@/data/fixtures';
import type { ReleaseInfo } from '@/lib/release';
import { HERO_COPY, heroCtaAriaLabel } from './copy';
import { HeroStage } from './HeroStage';

export function Hero({ release }: { release: ReleaseInfo }) {
  return (
    <section
      id="top"
      aria-labelledby="hero-h1"
      data-hero-cta-scope=""
      // border-b: 돔 안(--dome-in)이 트립틱 바탕과 직각으로 맞닿지 않게 받침선 한 줄(DECISIONS D27-4 — 아웃트로 돔이 푸터 윗선에서 잘리는 것과 같게)
      className="relative flex min-h-svh flex-col items-center overflow-clip border-b border-line"
    >
      {/* 웅덩이 = 아잉 발밑(무대 아래 16px 선) 가운데 — 높이 --aing-w × .24 의 절반만큼 아래로 */}
      <Dome variant="hero" pool={{ bottom: 'calc(16px - var(--aing-w) * .12)' }} />

      <div className="relative z-[1] flex w-full flex-col items-center px-[var(--gutter)] pt-[calc(var(--dome-top)+14px)] text-center">
        {/* 돔 꼭대기 바로 아래(아이콘 링의 끝점 자리) — 앱이 메뉴바에 그리는 라벨 그대로 */}
        <RenderImage
          asset="ui/menubar-0000-lg"
          widthPt={463}
          heightPt={132}
          alt={ALT['ui/menubar-0000-lg'] ?? ''}
          eager
          className="block h-[clamp(30px,4.4svh,40px)] w-auto max-w-none phone:h-[clamp(28px,3.6svh,32px)]"
        />
        {/* w-full: 가운데 정렬 flex 열의 맞춤 폭(fit-content)에 맡기지 않는다 — 웹킷이 text-wrap 과 함께 폭을 좁게 재
            리드 둘째 문장을 한 번 더 꺾었다(실측). 줄은 lines·<br> 가 정하고 글자는 가운데 정렬 */}
        <Headline level={1} size="display" lines={HERO_COPY.h1} id="hero-h1" className="mt-5 w-full max-w-[640px]" />
        <p className="t-lead mt-5 w-full max-w-[576px] text-ink-2">{HERO_COPY.lead}</p>
        <div
          data-hero-cta=""
          className="mt-7 flex items-center justify-center gap-3 phone:w-full phone:flex-col"
        >
          <DownloadCTA
            placement="hero"
            size="l"
            label={HERO_COPY.cta}
            ariaLabel={heroCtaAriaLabel(release, RELEASE_FALLBACK)}
            className="phone:w-full phone:max-w-[320px]"
          />
          {/* 배지 여백(높이/4 = 12, 애플 규칙)은 그대로 두고 줄 높이는 48 로 — 위아래·오른쪽 여백만 바깥으로 */}
          <AppStoreBadge height={48} placement="hero" className="-my-3 -mr-3 phone:-mx-3" />
        </div>
        {/* iOS(data-platform=ios): 배지 아래 Mac 요구 사항·터미널 링크 대신 아이폰 요구 사항(CB:243) — DECISIONS D26-2.
            DownloadCTA 와 같은 방식(임의 변형 [html[data-platform=ios]_&] 의 특이도가 inline·inline-block 을 이긴다) */}
        <p className="t-small mt-3.5 flex flex-wrap items-baseline justify-center gap-x-4 text-ink-3">
          <span className="[html[data-platform=ios]_&]:hidden">{HERO_COPY.meta}</span>
          <span className="hidden [html[data-platform=ios]_&]:inline">{HERO_COPY.metaIos}</span>
          {/* 글자는 14px 줄이지만 누를 자리는 45.7px(SPEC §4 터치 대상 ≥ 44) — 위아래 여백을 음수 바깥 여백으로 상쇄 */}
          <TextLink href="#install" className="-my-3 inline-block py-3 [html[data-platform=ios]_&]:hidden">
            {HERO_COPY.brew}
          </TextLink>
        </p>
      </div>

      {/* 유연 여백(flex 1, 최소 0) */}
      <div aria-hidden="true" className="min-h-0 flex-1" />

      <HeroStage />
    </section>
  );
}

export default Hero;
