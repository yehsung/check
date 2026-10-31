'use client';
// components/install/AndroidSteps.tsx — 안드로이드 베타 카드의 세 단계 <ol>(docs/v3/brief.md §12 · 다음 단계 안내 §12.6). 카드(Install.tsx)는 서버 컴포넌트 —
// 움직이는 건 이 목록 하나(client 섬).
//
// 다음 단계 안내: 단계 N 버튼을 클릭하면(새 탭 — 랜딩 탭은 남는다) 1..N 번호 원이 체크(장식)가 되고 N+1 단계 버튼이 주 버튼(보라 primary),
//   그 <li> 에 aria-current="step". 3단계 뒤엔 셋 다 체크 · 주 버튼 없음. 아무 단계나 다시 클릭할 수 있다. 계산은 android-steps-logic.ts(순수 — 값 시험).
//   상태는 localStorage(aing-android-beta-step) — 읽기·쓰기 try/catch, 없거나 막혀도 서버 HTML 상태(1단계 주 버튼)로 정상, 클릭은 메모리로 이어간다.
//   useSyncExternalStore 서버 스냅숏 = 0 → 서버 HTML·하이드레이션 첫 렌더가 같다(어긋남 0). 저장된 값은 하이드레이션 직후 한 번 더 그려 적용.
//   primary·glass 버튼은 크기 클래스(s)가 같아 상자가 그대로다(레이아웃 이동 0 — scripts/android-smoke.mjs 가 잰다).
//   폰 보조 줄 위 여백 16: primary 의 보라 그림자(아래로 ≈ 34px 번짐)가 바로 밑 보조 줄 뒤를 밝혀 10px 일 때 ink-2 대비 4.54 였다(실측) → 16 에서 다시 잰다.
//
// 한 단계 = 번호 원 · 이름(h4) · 버튼(새 탭, 유리 s) · 보조 한 줄. 버튼 접근 이름 = 보이는 글자('가입하기') + 설명(aria-describedby) = 단계 이름.
// 배치
//   ≥768 : 가로 3칸 — 위 레일(번호 원 + 다음 번호 원 12px 앞에서 끝나는 가는 선, 끝낸 단계 뒤 선은 보라) · 아래 이름 · 버튼 · 보조.
//   < 768: 단계마다 한 덩어리 — 번호 원 + 이름 한 줄 → 버튼(카드 안 폭 전체 · 높이 48 · 15px) → 16 → 보조. 단계 사이 24 + 1px 선 + 24
//          (버튼 사이 ≈ 130px = 16 + 보조 21 + 24 + 1 + 24 + 번호 원 줄 28 + 16 · 360 폭에서 1단계 보조가 두 줄이면 151 — 옆 버튼을 잘못 클릭하지 않게).
//          버튼이 카드 폭을 가로질러 세로 레일은 두지 않는다.
//          내용 묶음은 display:contents — 이름·버튼·보조가 <li> 격자의 칸이 된다(버튼·보조는 두 칸 전폭).
import { useSyncExternalStore } from 'react';
import type { MouseEvent } from 'react';
import { LINKS } from '@/data/fixtures';
import { ANDROID_COPY } from '@/data/install-copy';
import { glassButtonClass } from '@/components/glass/GlassButton';
import { GlassFx } from '@/components/glass/GlassFx';
import { clickStep, readStep, stepViews, writeStep } from './android-steps-logic';
import { CheckGlyph, ExternalGlyph, KeepQuotes } from './android-parts';

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

// ─── 상태(모듈 하나 — 같은 페이지의 목록은 하나뿐) ──────────────────────────────────────────────
/** null = 아직 안 읽음. 저장소가 막혀도 클릭한 값은 여기 남는다(새로고침하면 0) */
let memory: number | null = null;
const listeners = new Set<() => void>();
const local = () => window.localStorage;
const subscribe = (cb: () => void) => {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
};
const snapshot = () => (memory ??= readStep(local));
const serverSnapshot = () => 0;

function mark(n: number) {
  memory = clickStep(snapshot(), n);
  writeStep(local, memory);
  for (const l of listeners) l();
}

// ─── 모양 ───────────────────────────────────────────────────────────────────────────────────────
const OL = 'grid grid-cols-1 min-[768px]:grid-cols-3';
const LI =
  'grid grid-cols-[28px_minmax(0,1fr)] items-center gap-x-3 min-[768px]:flex min-[768px]:flex-col min-[768px]:items-stretch ' +
  'phone:not-first:mt-6 phone:not-first:border-t phone:not-first:border-white/[.09] phone:not-first:pt-6';
const CIRCLE =
  'grid size-7 flex-none place-items-center rounded-full font-heading text-[13.5px] font-semibold text-ink-1 ' +
  'transition-[background-color,box-shadow] duration-200 motion-reduce:transition-none';
const CIRCLE_TODO = 'bg-white/[.07] shadow-[inset_0_0_0_1px_rgb(255_255_255/.22)]';
const CIRCLE_DONE = 'bg-[rgb(var(--violet-rgb)/.46)] shadow-[inset_0_0_0_1px_rgb(255_255_255/.3)]';
const LINE = 'hidden min-[768px]:mx-3 min-[768px]:block min-[768px]:h-px min-[768px]:flex-1';
/** 버튼: ≥768 = 유리 s(32 · 누를 자리 44) · < 768 = 카드 안 폭 전체 · 48 · 15px */
const BTN = 'mt-3 gap-1.5 phone:col-span-2 phone:mt-4 phone:w-full phone:[--b-h:48px] phone:text-[15px]';

export function AndroidSteps({ className }: { className?: string }) {
  const state = useSyncExternalStore(subscribe, snapshot, serverSnapshot);
  const views = stepViews(state);
  const last = ANDROID_COPY.steps.length - 1;
  return (
    <ol data-android-steps="" className={cx(OL, className)}>
      {ANDROID_COPY.steps.map((step, i) => {
        const v = views[i];
        const nameId = `android-step-${v.n}`;
        const end = i === last;
        const onAux = (e: MouseEvent) => {
          if (e.button === 1) mark(v.n); // 가운데 클릭도 새 탭을 연다
        };
        return (
          <li
            key={step.link}
            data-android-step={v.n}
            data-done={v.done ? '' : undefined}
            aria-current={v.current ? 'step' : undefined}
            className={LI}
          >
            {/* 레일: 번호 원(끝내면 체크 — 장식, 번호는 sr-only 로 남는다) + ≥768 다음 단계로 잇는 선(장식) */}
            <div className="flex items-center">
              <span className={cx(CIRCLE, v.done ? CIRCLE_DONE : CIRCLE_TODO)}>
                <span className={v.done ? 'sr-only' : undefined}>{v.n}</span>
                {v.done && <CheckGlyph />}
              </span>
              {!end && <span aria-hidden="true" className={cx(LINE, v.done ? 'bg-[rgb(var(--violet-rgb)/.55)]' : 'bg-white/[.14]')} />}
            </div>
            <div className={cx('contents min-w-0 min-[768px]:mt-3.5 min-[768px]:block', !end && 'min-[768px]:pr-6')}>
              <h4 id={nameId} className="font-heading text-[17px] font-semibold leading-[1.35] tracking-[-.01em] text-ink-1">
                {step.name}
              </h4>
              <a
                href={LINKS[step.link]}
                target="_blank"
                rel="noopener noreferrer"
                data-cta={step.dataCta}
                aria-describedby={nameId}
                onClick={() => mark(v.n)}
                onAuxClick={onAux}
                className={glassButtonClass(v.primary ? 'primary' : 'glass', 's', BTN)}
              >
                {step.cta}
                <ExternalGlyph />
                <GlassFx specular />
              </a>
              <p className="t-small mt-2.5 text-pretty text-ink-2 phone:col-span-2 phone:mt-4">
                <KeepQuotes text={step.note} />
              </p>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

export default AndroidSteps;
