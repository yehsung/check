'use client';

// components/hero/HeroStage.tsx — 히어로 아잉(docs/v3/brief.md §4.3 · §5). client 섬. 스크롤 리스너 0(IO 와 afterLoadIdle 뿐).
// 아잉은 첫 진입에 한 번 도착해 팝오버 왼쪽 아래 바닥 쪽에 선다(데스크톱) · 폰·태블릿은 팝오버 아래 오른쪽. 말풍선 "오늘도 화이팅!" 1회(5초).
//
// 도착(1회) — 진입 연출의 마지막 박자(오로라 0–600 → 글 200–700 → 팝오버 응결 300–1100 → 아잉 1200~)
//   조건: load + idle 뒤 · 히어로(#top)가 50% 이상 보임 · scrollY < 40(맨 위 39px 센티널) · 내비게이션 시작 + 1200ms 지남.
//   그때 AingClip 에 start → commute-start 가 재생 가능하면 그 반응 1회 + 말풍선, 이어서 idle 2회 뒤 그 프레임에서 정지.
// 건너뜀(HERO.arrivalDeadlineMs = 2.5s 까지 시작 못 함 · 보던 히어로를 벗어남 · 해시로 들어와 히어로가 화면 밖)
//   → 반응·말풍선 없이 히어로가 .35 이상 보일 때 idle 만(돌아와도 다시 하지 않는다 · 화면 밖에서는 영상을 받지 않는다).
// 감속 모션·Save-Data: AingClip posterOnly — 영상 0, 포스터 + 말풍선 정지(= 도착 뒤 상태).
// 근무 라벨(00:00 캡슐)은 쓰지 않는다 — 옆 팝오버가 03:45 근무 중이라 숫자가 서로 어긋난다.
// 아잉·말풍선은 aria-hidden, 클릭 없음(pointer-events:none).

import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AingClip } from '@/components/ui/AingClip';
import { HERO } from '@/data/fixtures';
import { useInViewRatio, usePosterOnly } from '@/lib/hooks';
import { afterLoadIdle } from '@/lib/media';

/** 아잉 도착 시각(내비게이션 시작 기준 ms) — §4.3 '아잉 도착 1200ms~'. */
const ARRIVE_AT_MS = 1200;

export function HeroStage({ className }: { className?: string }) {
  const heroRef = useRef<HTMLElement | null>(null);
  const topRef = useRef<HTMLElement | null>(null);

  // 보이는 비율은 히어로 절 전체로 잰다(이 섬은 팝오버 열 안에 있다). 맨 위 센티널은 Hero.tsx 가 절 왼쪽 위에 둔다.
  // IO 효과보다 먼저 ref 를 채운다(레이아웃 효과).
  useLayoutEffect(() => {
    heroRef.current = document.getElementById('top');
    topRef.current = document.querySelector<HTMLElement>('[data-hero-top]');
  }, []);

  const posterOnly = usePosterOnly();
  const in50 = useInViewRatio(heroRef, 0.5);
  const in35 = useInViewRatio(heroRef, 0.35);

  const [atTop, setAtTop] = useState(false);
  const [heroOff, setHeroOff] = useState(false);
  const [loadIdle, setLoadIdle] = useState(false);
  const [timeOk, setTimeOk] = useState(false);
  const [deadlinePassed, setDeadlinePassed] = useState(false);

  // 렌더 중 래치(이전 값에 맞춰 상태 고치기)
  const [seen35, setSeen35] = useState(false);
  const [begun, setBegun] = useState(false);
  const [skip, setSkip] = useState(false);

  if (in35 && !seen35) setSeen35(true);
  if (!begun && !skip && !posterOnly) {
    if (deadlinePassed || (seen35 && !in35) || heroOff) setSkip(true);
    else if (loadIdle && timeOk && in50 && atTop) setBegun(true);
  }

  useEffect(() => afterLoadIdle(() => setLoadIdle(true)), []);

  useEffect(() => {
    const now = performance.now();
    const t1 = window.setTimeout(() => setTimeOk(true), Math.max(0, ARRIVE_AT_MS - now));
    const t2 = window.setTimeout(() => setDeadlinePassed(true), Math.max(0, HERO.arrivalDeadlineMs - now));
    return () => {
      window.clearTimeout(t1);
      window.clearTimeout(t2);
    };
  }, []);

  // scrollY < 40 ⇔ 맨 위 센티널이 화면과 겹친다 · 히어로가 화면과 전혀 겹치지 않음(해시 진입)
  useEffect(() => {
    const top = topRef.current;
    const hero = heroRef.current;
    if (!top || !hero || typeof IntersectionObserver === 'undefined') return;
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
    io.observe(hero);
    return () => io.disconnect();
  }, []);

  return (
    <div className={className} data-hero-aing="">
        <AingClip
          width="var(--aing-w)"
          poster="char/aing-rest-poster"
          once={skip ? undefined : 'aing-commute-start'}
          bubble={skip ? undefined : 'commute-start'}
          start={(begun && !skip) || (skip && in35)}
          inView={in35}
          posterOnly={posterOnly}
          deadlineAt={HERO.arrivalDeadlineMs}
        />
    </div>
  );
}

export default HeroStage;
