"use client";

// components/outro/OutroStage.tsx — 아웃트로의 아잉 + 작은 유리 받침(docs/v3/brief.md §4.6). 스크롤 리스너 없음(IO 뿐).
// - 아잉 idle: 포스터 char/aing-idle-poster(idle 0번 칸)로 첫 페인트 → 이 상자가 절반 보이면 idle 시작 → 2회 뒤 그 프레임에서 정지.
//   35% 미만으로 보이거나 탭이 숨으면 일시정지, 돌아오면 남은 횟수만. 감속 모션·Save-Data 는 포스터 정지(영상 요청 0).
//   등장 연출(페이드·떠오름) 없음 — 포스터가 SSR 부터 제자리에 있다(CLS 0).
// - 받침 = thick 유리 원반(윗면 타원) + regular 유리 옆면(위아래가 타원인 기둥 모양 — 두께가 보인다). 돔(큰 원) 아님.
//   발밑 접지 그림자는 윗면 안쪽 방사 그라디언트, 받침 아래로 보라 빛이 번진다(받침이 빛을 모으는 모양).
// - 치수는 전부 아잉 상자 폭 --aing-w(Outro 가 폭마다 정한다)의 배수 — 아잉 상자 654×790 에서 발끝은 아래 97%(1.173W),
//   몸 가운데는 왼쪽 48.2% → 받침 윗면 가운데(1.173W)에 발을 맞추고, 몸 가운데를 상자 가운데에 맞춘다.
// - 전부 장식(aria-hidden, 클릭 없음). 같은 뜻이 제목·문장에 있다.
import { useRef, type CSSProperties } from "react";
import { Glass } from "@/components/glass/Glass";
import { LocalLight } from "@/components/glass/LocalLight";
import { AingClip } from "@/components/ui/AingClip";
import { useInViewRatio, usePosterOnly } from "@/lib/hooks";

/** idle 시작 문턱(상자의 절반이 보이면). */
const START_RATIO = 0.5;
/** 아잉 일시정지 문턱(보이는 비율 < .35 — AingClip 규칙). */
const AING_VISIBLE_RATIO = 0.35;
/** idle 반복 상한(14.4s × 2회 뒤 정지 — 무한 루프 0). */
const IDLE_LOOPS = 2;

/** 아잉 상자 폭의 배수(CSS 길이). */
const w = (k: number) => `calc(var(--aing-w) * ${k})`;

// 받침 기하(W = --aing-w): 윗면 타원 폭 1.22W · 높이 .26W, 가운데 = 발끝(1.173W) → 윗면 위 = 1.043W. 옆면 두께 .075W.
const FACE_TOP = 1.043;
const FACE_W = 1.22;
const FACE_H = 0.26;
const SIDE_T = 0.075;

const BOX: CSSProperties = { width: w(1.7), height: w(FACE_TOP + FACE_H + SIDE_T) };

// 받침 유리는 채도를 낮춘다(--g-sat) — 뒤의 오키드 빛을 190% 로 끌어올리면 유리가 아니라 보라 원반으로 읽힌다.
const SIDE = {
  top: w(FACE_TOP),
  width: w(FACE_W),
  height: w(FACE_H + SIDE_T),
  "--g-sat": "125%",
  // 옆면: 위는 거의 맑고 아래 테두리로 갈수록 빛을 머금는다(유리 두께의 가장자리 빛) + 받침 아래로 번지는 보라 빛
  background:
    "linear-gradient(180deg, rgb(255 255 255 / .02) 45%, rgb(255 255 255 / .09) 82%, rgb(var(--ice-rgb) / .20))",
  "--g-shadow":
    "inset 0 -1.5px 0 rgb(255 255 255 / .42), inset 0 -10px 16px -10px rgb(var(--ice-rgb) / .35), " +
    "0 24px 46px -18px rgb(var(--violet-rgb) / .8), 0 10px 24px -12px rgb(4 2 14 / .85)",
} as CSSProperties;

const FACE = {
  top: w(FACE_TOP),
  width: w(FACE_W),
  height: w(FACE_H),
  "--g-sat": "125%",
  // 윗면: 뒤 가장자리 1px 흰 빛 · 앞 가장자리 얼음빛 테 — 두께 있는 유리판의 두 모서리
  "--g-shadow":
    "inset 0 1px 0 rgb(255 255 255 / .5), inset 0 -1.5px 0 rgb(var(--ice-rgb) / .45), inset 0 -10px 18px -10px rgb(var(--ice-rgb) / .16)",
} as CSSProperties;

/** 윗면 광택(뒤쪽이 밝다 — 위에서 오는 빛). */
const SHEEN: CSSProperties = {
  background: "radial-gradient(62% 80% at 50% 12%, rgb(255 255 255 / .2), rgb(255 255 255 / 0) 72%)",
};

/** 발밑 접지 그림자(윗면 안). */
const CONTACT: CSSProperties = {
  background: "radial-gradient(closest-side, rgb(4 2 14 / .6), rgb(4 2 14 / .24) 55%, rgb(4 2 14 / 0))",
};

const AING: CSSProperties = { left: `calc(50% - ${w(0.482)})` };

export function OutroStage({ className }: { className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useInViewRatio(ref, START_RATIO);
  const inView = useInViewRatio(ref, AING_VISIBLE_RATIO);
  const posterOnly = usePosterOnly();

  return (
    <div
      ref={ref}
      aria-hidden="true"
      data-outro-stage=""
      className={className ? `relative isolate mx-auto ${className}` : "relative isolate mx-auto"}
      style={BOX}
    >
      {/* 아잉 뒤에 모이는 빛(오키드) + 받침 아래 바닥 빛(보라, 납작). 절이 overflow-clip 이라 빛 타원이 절 윗변에 닿지 않게
          (닿으면 FAQ 와의 경계에 네모난 빛 모서리가 생긴다) 크기·중심을 아잉 몸~받침 쪽으로 둔다 */}
      <LocalLight tone="orchid" x="50%" y="64%" size={w(2.8)} aspect={0.66} strength={0.38} />
      <LocalLight tone="violet" x="50%" y="100%" size={w(2.6)} aspect={0.22} strength={0.5} />

      <Glass level="regular" radius={`50% / ${w(FACE_H / 2)}`} className="absolute left-1/2 -translate-x-1/2" style={SIDE} />
      <Glass level="thick" radius="50%" className="absolute left-1/2 -translate-x-1/2" style={FACE}>
        <span className="absolute inset-0 rounded-[50%]" style={SHEEN} />
        <span className="absolute left-1/2 top-[46%] h-[40%] w-[52%] -translate-x-1/2 -translate-y-1/2 rounded-full" style={CONTACT} />
      </Glass>

      <div className="absolute top-0 z-[4]" style={AING}>
        <AingClip
          width="var(--aing-w)"
          poster="char/aing-idle-poster"
          start={seen}
          maxLoops={IDLE_LOOPS}
          inView={inView}
          posterOnly={posterOnly}
        />
      </div>
    </div>
  );
}

export default OutroStage;
