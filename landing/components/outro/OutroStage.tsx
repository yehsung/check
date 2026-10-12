"use client";

// components/outro/OutroStage.tsx — 아웃트로의 움직이는 부분(SPEC v2 §S8 · DECISIONS D3). 스크롤 리스너 없음(IO 뿐, D7).
// - 이 상자 = 절의 내용 상자 전체(#outro 의 유일한 흐름 자식, flex-1). 그래서 '절 45% 진입' = 이 상자가 45% 보임.
//   한 번 45% 보이면 data-shown 을 붙이고 떼지 않는다 → 내용(제목·리드·버튼 줄·아잉) 불투명 0 → 1, --t-fade 600ms 선형.
//   '시작 전' 숨김은 .js · 감속 아님 · data-shown 없음 · 안에 포커스 없음 일 때만(JS 없음·감속 = 처음부터 보임, 하이드레이션 어긋남 0).
//   숨김·페이드 규칙은 globals([data-outro-stage] — 통합이 requests/faq-outro.md §2 를 흡수, 시간은 --t-fade).
// - 아잉 = 브랜드 마크(앱 아이콘의 링 + 라벨 없는 아잉): 포스터 char/aing-idle-poster(idle 0번 칸) → data-shown 순간 idle 시작 → 2회 뒤
//   그 프레임에서 정지(AingClip maxLoops 2). once·말풍선·근무 라벨 없음, 꾸벅(commute-end) 없음. 아잉 상자가 35% 미만으로 보이거나
//   탭이 숨으면 일시정지, 돌아오면 남은 횟수만. 감속·Save-Data 는 포스터 정지(영상 요청 0).
// - 아잉 폭 = 절이 정한 --aing-w(Outro.tsx), 아래 여백 16 — 발밑 웅덩이(Dome pool)와 같은 기준.
import { useRef, useState, type ReactNode } from "react";
import { AingClip } from "@/components/ui/AingClip";
import { useInViewRatio, usePosterOnly } from "@/lib/hooks";

/** 절 진입 문턱(SPEC §S8 '절이 45% 보이면 1회'). */
const ENTER_RATIO = 0.45;
/** 아잉 일시정지 문턱(SPEC §5.5 '보이는 비율 < .35'). */
const AING_VISIBLE_RATIO = 0.35;
/** 아잉 idle 반복 상한(SPEC §S8 '14.4s × 2회'). */
const IDLE_LOOPS = 2;

const STAGE =
  "relative flex flex-1 flex-col items-center px-[var(--gutter)] text-center " +
  // 제목 윗변 = 작은 돔 꼭대기(.dome--small top 14svh · phone 10svh) + 70 / 56 (SPEC §S8 와이어: 126 → 196)
  "pt-[calc(14svh_+_70px)] phone:pt-[calc(10svh_+_56px)]";

export function OutroStage({ children }: { children: ReactNode }) {
  const stageRef = useRef<HTMLDivElement>(null);
  const aingRef = useRef<HTMLDivElement>(null);
  const entered = useInViewRatio(stageRef, ENTER_RATIO);
  const aingVisible = useInViewRatio(aingRef, AING_VISIBLE_RATIO);
  const posterOnly = usePosterOnly();

  // 1회 래치 — 렌더 중 조건부 setState(React 의 '이전 값에 맞춰 상태 고치기' 패턴). 되감기 없음.
  const [shown, setShown] = useState(false);
  if (entered && !shown) setShown(true);

  return (
    <div ref={stageRef} data-outro-stage="" data-shown={shown ? "" : undefined} className={STAGE}>
      {children}
      <div ref={aingRef} className="mt-auto pb-4">
        <AingClip
          width="var(--aing-w)"
          poster="char/aing-idle-poster"
          start={shown}
          maxLoops={IDLE_LOOPS}
          inView={aingVisible}
          posterOnly={posterOnly}
        />
      </div>
    </div>
  );
}

export default OutroStage;
