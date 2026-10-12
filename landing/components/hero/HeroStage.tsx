'use client';

// components/hero/HeroStage.tsx — 히어로의 움직이는 부분(SPEC v2 §S1 모션 ① · PLAN §4.1). client 섬.
// 빛 한 줄(SVG .comet) + 아잉(AingClip) 오케스트레이션. 스크롤 리스너 0(IO 와 afterLoadIdle 뿐 — DECISIONS D7).
//
// 도착(1회)
//   조건: load + idle 뒤 · 히어로가 50% 이상 보임 · scrollY < 40(맨 위 39px 센티널이 화면 안) · 감속 아님 · Save-Data 아님.
//   · desk 무대 모드(MQ_STAGE): commute-start 가 재생 가능해진 뒤에만(AingClip onOnceReady — DECISIONS D28-1) .comet 를 그리고
//     다음 프레임에 data-run → 빛 한 줄 1000ms(두 구간: 림 등속 → 착지 ease-out, Web Animations — D28-3) → start=true(도착)
//     + data-done(빛 전체 불투명 1 → 0, 1200ms 선형 — globals). 그 뒤 다시 달리지 않는다(스크롤 왕복 후에도).
//     빛은 언제나 진짜 렌더에서 끝난다(SPEC §1.2) — 반응이 준비되지 않은 채 빛만 달리고 아무것도 도착하지 않는 일이 없다.
//   · phone·tab(무대 아님): 빛 없이 곧바로 start=true(AingClip 이 once 가 재생 가능해지면 재생).
//   · 감속 모션·Save-Data: AingClip posterOnly — 영상 0, 포스터 + 말풍선 + 근무 라벨 정지(= 도착 뒤 상태), 빛 없음.
// 마감(내비게이션 시작 + 2.5s = HERO.arrivalDeadlineMs, performance.now() 기준)
//   · 그때까지 도착이 시작되지 않았거나(조건 미충족·늦은 load·반응 준비 안 됨), 그 전에 히어로를 벗어났으면(보이는 비율 .35 미만),
//     load 때 히어로가 아예 화면 밖이면(해시로 들어옴) 도착을 건너뛴다: 빛·once·말풍선 없이, 히어로가 .35 이상 보일 때 start →
//     AingClip 이 근무 라벨만 켜고 idle 로(돌아와도 다시 하지 않는다 · 화면 밖에서는 idle 영상도 받지 않는다).
//   · 빛 한 줄이 달리는 중(도착 전)에 히어로를 벗어나도 같은 길(DECISIONS D28-4): 빛을 접고, 돌아오면 근무 라벨 + idle.
//   · AingClip 은 마감까지 commute-start 가 재생 가능하지 않으면 스스로 건너뛰고 onArrive 를 먼저 부른다 → 빛 한 줄을 접는다.
// idle: 보이는 비율 .35 미만·탭 숨김이면 일시정지, 돌아오면 남은 횟수만(AingClip 이 inView·visibilitychange 로).
// 아잉·말풍선·근무 라벨·빛 한 줄은 aria-hidden, 클릭 없음(pointer-events:none).

import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AingClip } from '@/components/ui/AingClip';
import { HERO } from '@/data/fixtures';
import { MQ_STAGE, useInViewRatio, useMediaQuery, usePosterOnly } from '@/lib/hooks';
import { afterLoadIdle } from '@/lib/media';
import { RIM_CORE_INSET, cometGeometry, cometPath, cometRimFraction, cometRimTime } from './comet-path';

type CometDraw = { d: string; x1: number; y1: number; x2: number; y2: number; rim: number };

/** 끝점 = 말풍선 왼쪽 가운데 − 8px(SPEC §S1). */
const END_GAP = 8;
/** 착지 구간 커브 = --ease-out(SPEC §2.7). 림 구간은 등속(linear). */
const EASE_OUT = 'cubic-bezier(.2,.8,.2,1)';

/**
 * 돔·말풍선을 재서 빛 한 줄 경로를 만든다(#top 왼쪽 위 기준 CSS px). 위치는 레이아웃 값(offset*)으로 — 돔 패럴랙스 translate·
 * 말풍선 숨김 scale(.96) 의 영향을 받지 않는다. 못 재면 null.
 */
function measureComet(probe: HTMLElement | null, stage: HTMLElement | null): CometDraw | null {
  const section = probe?.parentElement;
  if (!probe || !section || !stage) return null;
  const dome = section.querySelector<HTMLElement>('[data-dome="hero"]');
  const aing = stage.querySelector<HTMLElement>('[data-aing]');
  if (!dome || !aing || dome.offsetParent !== section) return null;
  const origin = probe.getBoundingClientRect();
  const width = dome.getBoundingClientRect().width;
  if (!(width > 0)) return null;
  const r = width / 2;
  const cx = dome.offsetLeft + r;
  const cy = dome.offsetTop + r;
  const a = aing.getBoundingClientRect();
  const bubble = aing.querySelector<HTMLElement>('.aing-bubble');
  const end =
    bubble && bubble.offsetParent === aing
      ? {
          x: a.left - origin.left + bubble.offsetLeft - END_GAP,
          y: a.top - origin.top + bubble.offsetTop + bubble.offsetHeight / 2,
        }
      : { x: a.left - origin.left - END_GAP, y: a.top - origin.top + a.height * 0.4 };
  const dome2 = { cx, cy, r: r - RIM_CORE_INSET };
  const g = cometGeometry(dome2, end);
  return {
    d: cometPath(dome2, end),
    x1: g.start.x,
    y1: g.start.y,
    x2: g.leave.x,
    y2: g.leave.y,
    rim: cometRimFraction(g),
  };
}

/** stroke-dashoffset 두 구간(pathLength 100): 림(0 → T₁) 등속 · 착지(T₁ → 1) ease-out. 이음매 속도가 같다(comet-path.ts). */
function runComet(trail: SVGPathElement, head: SVGPathElement, rim: number): Animation[] {
  const p = Math.min(1, Math.max(0, rim));
  const t1 = cometRimTime(p);
  if (typeof trail.animate !== 'function' || typeof head.animate !== 'function') {
    trail.style.strokeDashoffset = '0';
    head.style.strokeDashoffset = '-98';
    return [];
  }
  const opts: KeyframeAnimationOptions = { duration: HERO.cometMs, fill: 'forwards', easing: 'linear' };
  // 키프레임 easing 은 그 키프레임에서 다음 키프레임까지 — 첫 구간은 기본(linear), 둘째 구간만 ease-out.
  const seg = (from: number, to: number): Keyframe[] => [
    { strokeDashoffset: String(from) },
    { strokeDashoffset: String(from - (from - to) * p), offset: t1, easing: EASE_OUT },
    { strokeDashoffset: String(to) },
  ];
  return [trail.animate(seg(100, 0), opts), head.animate(seg(2, -98), opts)];
}

export function HeroStage() {
  const probeRef = useRef<HTMLDivElement>(null);
  const topRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const trailRef = useRef<SVGPathElement>(null);
  const headRef = useRef<SVGPathElement>(null);

  const stageMode = useMediaQuery(MQ_STAGE);
  const posterOnly = usePosterOnly();
  const in50 = useInViewRatio(probeRef, 0.5);
  const in35 = useInViewRatio(probeRef, 0.35);

  // 콜백(IO·타이머·rAF·load·AingClip 알림)에서만 바꾸는 상태
  const [atTop, setAtTop] = useState(false);
  const [heroOff, setHeroOff] = useState(false); // 히어로가 화면과 전혀 겹치지 않음(해시로 들어옴 등)
  const [loadIdle, setLoadIdle] = useState(false);
  const [deadlinePassed, setDeadlinePassed] = useState(false);
  const [onceOk, setOnceOk] = useState(false); // commute-start 가 재생 가능(AingClip onOnceReady — D28-1)
  const [comet, setComet] = useState<CometDraw | null>(null);
  const [run, setRun] = useState(false);
  const [startSig, setStartSig] = useState(false);
  const [early, setEarly] = useState(false); // AingClip 이 start 전에 도착(마감 건너뜀·once 오류·posterOnly)

  // 렌더 중 래치(이전 값에 맞춰 상태 고치기 — 효과를 한 바퀴 돌리지 않는다)
  const [seen35, setSeen35] = useState(false);
  const [begun, setBegun] = useState<null | 'comet' | 'direct'>(null);
  const [skip, setSkip] = useState(false);
  const [done, setDone] = useState(false);

  if (in35 && !seen35) setSeen35(true);
  if (begun === null && !skip && !posterOnly && !early) {
    // 건너뜀: 마감 지남 · 보던 히어로를 벗어남 · 히어로가 아예 화면 밖(해시 진입 — load 전에 정해 once 영상을 받지 않는다)
    if (deadlinePassed || (seen35 && !in35) || heroOff) setSkip(true);
    // 무대 모드의 빛 한 줄은 반응이 재생 가능해진 뒤에만 출발한다(D28-1). phone·tab 은 AingClip 이 스스로 기다린다.
    else if (loadIdle && in50 && atTop && (!stageMode || onceOk)) setBegun(stageMode ? 'comet' : 'direct');
  }
  if (begun === 'direct' && !startSig) setStartSig(true);
  if (begun === 'comet' && early && !done) setDone(true); // 빛 한 줄을 접는다(이미 도착했거나 건너뜀)
  // 빛 한 줄이 달리는 중(도착 전)에 히어로를 벗어나면 도착을 건너뛴다(SPEC §S1 · D28-4) — 빛은 접고, 돌아오면 근무 라벨 + idle
  if (begun === 'comet' && !startSig && !skip && seen35 && !in35) {
    setSkip(true);
    setDone(true);
  }

  // load + idle
  useEffect(() => afterLoadIdle(() => setLoadIdle(true)), []);

  // 도착 마감(내비게이션 시작 기준)
  useEffect(() => {
    const t = window.setTimeout(() => setDeadlinePassed(true), Math.max(0, HERO.arrivalDeadlineMs - performance.now()));
    return () => window.clearTimeout(t);
  }, []);

  // scrollY < 40 ⇔ 맨 위 39px 센티널이 화면과 겹친다(스크롤 리스너 대신 IO) · 히어로 상자가 화면과 겹치는지(heroOff)
  useEffect(() => {
    const top = topRef.current;
    const probe = probeRef.current;
    if (!top || !probe || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver(
      (entries) => {
        for (const en of entries) {
          if (en.target === top) setAtTop(en.isIntersecting);
          else setHeroOff(!en.isIntersecting);
        }
      },
      { threshold: 0 },
    );
    io.observe(top);
    io.observe(probe);
    return () => io.disconnect();
  }, []);

  // 빛 한 줄: 재고 → 그리고 → 다음 프레임에 data-run → 1000ms 뒤 도착 신호 + data-done
  useEffect(() => {
    if (begun !== 'comet') return;
    const id = requestAnimationFrame(() => {
      const c = measureComet(probeRef.current, stageRef.current);
      if (c) setComet(c);
      else setStartSig(true); // 못 재면 빛 없이 도착
    });
    return () => cancelAnimationFrame(id);
  }, [begun]);

  useEffect(() => {
    if (!comet || run || skip) return;
    let id2 = 0;
    const id1 = requestAnimationFrame(() => {
      id2 = requestAnimationFrame(() => setRun(true));
    });
    return () => {
      cancelAnimationFrame(id1);
      cancelAnimationFrame(id2);
    };
  }, [comet, run, skip]);

  // 진행: data-run 이 붙는 커밋에서 페인트 전에 건다(시작 상태 = CSS 기본값 dashoffset 100 · 2 — 끝 상태가 먼저 보이는 프레임 없음).
  useLayoutEffect(() => {
    if (!run || !comet) return;
    const trail = trailRef.current;
    const head = headRef.current;
    if (!trail || !head) return;
    const anims = runComet(trail, head, comet.rim);
    return () => anims.forEach((a) => a.cancel());
  }, [run, comet]);

  useEffect(() => {
    if (!run || skip) return;
    const t = window.setTimeout(() => {
      setStartSig(true);
      setDone(true);
    }, HERO.cometMs);
    return () => window.clearTimeout(t);
  }, [run, skip]);

  const onArrive = () => {
    if (!startSig) setEarly(true);
  };

  return (
    <>
      {/* 보이는 비율 판정용(절 전체를 덮는 빈 상자) · scrollY < 40 센티널 */}
      <div ref={probeRef} aria-hidden="true" className="pointer-events-none absolute inset-0" />
      <div ref={topRef} aria-hidden="true" className="pointer-events-none absolute left-0 top-0 h-[39px] w-px" />

      {comet && (
        <svg
          className="comet"
          aria-hidden="true"
          focusable="false"
          data-run={run ? '' : undefined}
          data-done={done ? '' : undefined}
        >
          <defs>
            <linearGradient
              id="comet-grad"
              gradientUnits="userSpaceOnUse"
              x1={comet.x1}
              y1={comet.y1}
              x2={comet.x2}
              y2={comet.y2}
            >
              {/* 꼬리 시작 불투명 .35 — 림 구간(라벨 출발점)부터 꼬리가 보이게(D28-3) */}
              <stop offset="0" style={{ stopColor: 'var(--violet-deep)', stopOpacity: 0.35 }} />
              <stop offset="0.45" style={{ stopColor: 'var(--violet)' }} />
              <stop offset="1" style={{ stopColor: 'var(--violet-bright)' }} />
            </linearGradient>
          </defs>
          <path ref={trailRef} className="comet-trail" pathLength={100} d={comet.d} />
          <path ref={headRef} className="comet-head" pathLength={100} d={comet.d} />
        </svg>
      )}

      {/* 아잉 무대: 아래 여백 16 · 음수 윗여백 = 17 − 말풍선 오프셋(218.5/654 × 폭) → 말풍선 윗변 − 메타 아랫변 ≥ 16
          (1px 은 레이아웃 단위 반올림 여유 — 짧은 화면에서 15.98 로 떨어지지 않게) */}
      <div
        ref={stageRef}
        className="relative z-[1] mb-4 shrink-0"
        style={{ marginTop: 'calc(17px - var(--aing-w) * 218.5 / 654)' }}
      >
        <AingClip
          width="var(--aing-w)"
          poster="char/aing-rest-poster"
          once={skip ? undefined : 'aing-commute-start'}
          bubble={skip ? undefined : 'commute-start'}
          timer
          start={(startSig && !skip) || (skip && in35)}
          inView={in35}
          posterOnly={posterOnly}
          deadlineAt={HERO.arrivalDeadlineMs}
          onArrive={onArrive}
          onOnceReady={() => setOnceOk(true)}
        />
      </div>
    </>
  );
}

export default HeroStage;
