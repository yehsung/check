// components/hero/Hero.tsx — 히어로 #top(docs/v3/brief.md §4.3 · §8 · §9.4). server 컴포넌트 — 움직이는 부분은 HeroStage(아잉)·GlassFx(굴절).
// 왼쪽 글(H1 두 줄 · 리드 · 버튼 줄 · 메타 · 설치 방법 보기) / 오른쪽 thick 유리 베젤 안 근무 중 팝오버 렌더 통째.
// 팝오버의 오른쪽 끝 = 메뉴바 오른쪽 끝(--bar-pad), 위 = 메뉴바 아래 10px(실제 macOS 팝오버 자리).
// 렌더 높이 --pop-h(1440×900 → 653 = .5 배율), 둘레 베젤 16px. 크롭·마스크 없음(모서리 14px 둥글림은 렌더 바깥 여백만 닿는다).
// 들어오는 순간(유일한 자동 연출 — globals.css): 글 줄 200–700 차례로 · 팝오버 응결 300–1100(.hero-pop) · 아잉 1200~(HeroStage).
// 버튼 줄은 두 벌을 SSR 하고 폭·플랫폼으로 하나만 보인다(깜빡임 0):
//   ≥768 · iOS 아님 : [Mac용 다운로드](보라 유리) [brew 알약] · 메타 '무료 · macOS 14 이상 · Apple 공증'
//   폰(< 768) · iOS 기기(§9.4.1) : [App Store 배지] [Mac용 다운로드](투명 유리 → 설치 절 — 폰에 DMG 는 쓸모없다) · 메타 '무료 · iOS 18 이상 · macOS 14 이상'.
//                                 brew 알약은 숨긴다(폰에선 쓸 수 없다 — 설치 절이 보여 준다).
// 폰·태블릿 팝오버(§9.4.2): 폭을 줄이고 아잉을 데스크톱처럼 베젤 왼아래 모서리에 겹쳐 붙인다(혼자 떨어진 줄 없음) — globals.css.
import type { CSSProperties } from 'react';
import { Glass } from '@/components/glass/Glass';
import { LocalLight } from '@/components/glass/LocalLight';
import { BrewPill } from '@/components/glass/CommandPill';
import { RenderImage } from '@/components/ui/RenderImage';
import { DownloadCTA } from '@/components/ui/DownloadCTA';
import { AppStoreBadge } from '@/components/ui/AppStoreBadge';
import { KeepDots } from '@/components/ui/KeepDots';
import { glassButtonClass } from '@/components/glass/GlassButton';
import { GlassFx } from '@/components/glass/GlassFx';
import { ALT, LINKS, RELEASE_FALLBACK } from '@/data/fixtures';
import type { ReleaseInfo } from '@/lib/release';
import { HERO_COPY, heroCtaAriaLabel } from './copy';
import { HeroStage } from './HeroStage';

const line = (i: number) => ({ '--i': i }) as CSSProperties;
/** 두 벌 보이기: WIDE = ≥768 이고 iOS 아님 · NARROW = 폰(< 768) 또는 iOS 기기(§9.4.1 — 같은 규칙) */
const WIDE = 'contents phone:hidden [html[data-platform=ios]_&]:hidden';
const NARROW = 'hidden phone:contents [html[data-platform=ios]_&]:contents';
const WIDE_INLINE = 'phone:hidden [html[data-platform=ios]_&]:hidden';
const NARROW_INLINE = 'hidden phone:inline [html[data-platform=ios]_&]:inline';
const orb = (c: string, left: string, top: string, size: string) => ({ '--c': c, '--s': size, left, top }) as CSSProperties;

export function Hero({ release }: { release: ReleaseInfo }) {
  return (
    <section id="top" aria-labelledby="hero-h1" data-hero-cta-scope="" className="hero relative isolate overflow-clip">
      {/* scrollY < 40 센티널(HeroStage 가 읽는다) */}
      <div data-hero-top="" aria-hidden="true" className="pointer-events-none absolute left-0 top-0 h-[39px] w-px" />
      {/* 국소 빛: 팝오버 뒤 보라(가장 넓게) · 상태 항목 쪽 오키드 · 왼아래 인디고 — 부드러운 바탕 빛.
          절이 overflow-clip 이라 타원이 아랫변(= 기능 절 윗변)을 넘으면 거기서 빛이 가로로 뚝 끊긴다(3단계 실측: 인디고가 α .24 에서 잘림).
          → 아래쪽 빛은 타원 아래 끝이 절 안에서 0 이 되게: 중심 y ≤ 100% − 반높이(size × aspect / 2) − 12px */}
      <LocalLight tone="violet" x="72%" y="min(48%, calc(100% - min(434px, 40.3vw) - 12px))" size="min(1400px, 130vw)" aspect={0.62} strength={0.28} />
      <LocalLight tone="orchid" x="90%" y="10%" size="min(760px, 90vw)" strength={0.2} />
      <LocalLight tone="indigo" x="16%" y="calc(100% - min(280px, 33.6vw) - 12px)" size="min(1000px, 120vw)" aspect={0.56} strength={0.3} />

      <div className="hero-grid">
        <div className="hero-copy">
          <h1 id="hero-h1" className="t-display text-ink-1">
            <span className="hero-line inline-block whitespace-nowrap" style={line(0)}>
              {HERO_COPY.h1[0]}
            </span>
            <br />
            <span className="hero-line inline-block whitespace-nowrap" style={line(1)}>
              {HERO_COPY.h1[1]}
            </span>
          </h1>
          <p className="t-lead hero-line mt-5 desk:mt-6" style={line(2)}>
            {HERO_COPY.lead}
          </p>
          <div data-hero-cta="" className="hero-line mt-7 flex flex-wrap items-center gap-3 desk:mt-9" style={line(3)}>
            {/* ≥768 · iOS 아님: 주 버튼 + brew 알약 */}
            <span className={WIDE}>
              <DownloadCTA placement="hero" size="l" label={HERO_COPY.cta} ariaLabel={heroCtaAriaLabel(release, RELEASE_FALLBACK)} />
              <BrewPill />
            </span>
            {/* 폰 · iOS: App Store 배지가 첫 행동(애플 규칙 여백 = 높이/4 — 줄 높이에서는 빼 준다) + Mac용 다운로드(투명 유리, 배지와 같은 높이 48).
                배지는 lazy(placement 'hero-phone') — 데스크톱에서는 display:none 이라 받지 않는다(첫 화면 −9KB) */}
            <span className={NARROW}>
              <AppStoreBadge height={48} placement="hero-phone" className="-m-3" />
              <a href={LINKS.install} data-cta="hero-install" className={glassButtonClass('glass', 'l', 'ml-3 [--b-h:48px] [--b-px:22px]')}>
                {HERO_COPY.cta}
                <GlassFx specular />
              </a>
            </span>
          </div>
          <p className="hero-line t-small mt-5 flex flex-wrap items-center gap-x-4 gap-y-1 text-ink-2" style={line(4)}>
            <span className={WIDE_INLINE}>{HERO_COPY.meta}</span>
            <span className={NARROW_INLINE}>
              <KeepDots text={HERO_COPY.metaPhone} items />
            </span>
            {/* 글자는 14px 줄이지만 누를 자리는 44px — 위아래 여백을 음수 바깥 여백으로 상쇄 */}
            <a href="#install" className="hero-install -my-3 inline-block py-3">
              {HERO_COPY.install}
            </a>
          </p>
        </div>

        <div className="hero-pop-col">
          <div className="relative">
            {/* 베젤 가장자리 뒤에 걸친 빛 덩어리(가장자리가 비교적 선명) — 유리 밖은 또렷, 베젤 띠 안은 흐리고 휜다.
                왼쪽 가장자리 오키드 · 위 오른쪽 모서리 인디고 · 오른아래 모서리 로즈(작게). 위치는 베젤 상자 기준 % */}
            <span aria-hidden="true" className="hero-orb" style={orb('var(--orchid-rgb)', '0%', '36%', 'clamp(150px, 15vw, 230px)')} />
            <span aria-hidden="true" className="hero-orb hero-orb--top" style={orb('var(--indigo-rgb)', '84%', '1%', 'clamp(120px, 11vw, 170px)')} />
            <span aria-hidden="true" className="hero-orb" style={orb('var(--rose-rgb)', '97%', '95%', 'clamp(84px, 7vw, 112px)')} />
            {/* 굴절: 베젤 띠(20px)에 맞춘 렌즈 — 가장자리는 휘고(색수차) 안쪽으로 갈수록 서리 */}
            <Glass level="thick" specular refract={{ band: 22, scale: 56, rimBlur: 2.4 }} entrance className="hero-pop">
              <RenderImage
                asset="ui/popover-working"
                widthPt={414}
                heightPt={653}
                alt={ALT['ui/popover-working'] ?? ''}
                eager
                fetchPriority="high"
                className="hero-pop__img"
              />
            </Glass>
          </div>
          <HeroStage className="hero-aing" />
        </div>
      </div>
    </section>
  );
}

export default Hero;
