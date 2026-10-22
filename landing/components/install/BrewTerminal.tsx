'use client';
// components/install/BrewTerminal.tsx — 설치 절의 유리 터미널 창(docs/v3/brief.md §4.5 · §8). regular 유리 + 옅은 어두운 틴트.
// 신호등 점 셋 · 제목 'zsh' · 첫 줄 '$ brew install yehsung/check/aing-check' + [복사](진짜 클립보드 · '복사했어요' · 라이브 영역) ·
// brew 출력 다섯 줄(Tapping · Downloading · Installing Cask · Moving App · 🍺 성공) · 새 프롬프트.
//
// 점진적 향상: 서버 HTML 은 처음부터 완성된 출력이다(JS 없음 · 감속 모션 · 검색 엔진 = 그대로).
// JS 가 돌고 감속 모션이 아니고 터미널이 아직 화면 아래에 있으면 '준비'(출력 숨김 — 자리는 그대로)로 두었다가,
// 처음 화면에 들어올 때 한 번만 명령을 치고(≈1.2초) 출력 줄을 차례로(줄당 120–250ms) 띄운다. 다시 보여도 재생하지 않는다.
// 마운트 때 이미 화면에 걸쳐 있으면(해시 이동·새로고침 복원) 보이는 글자를 지웠다 다시 쓰지 않고 완성 그대로 둔다.
// 숨김은 visibility 라 높이·줄바꿈이 처음부터 고정된다(CLS 0 — 예약 높이 = 완성 높이).
// v3.1(§9.4.3): 명령은 어느 폭에서도 한 줄(중간 줄바꿈 0). 폰(< 768)은 모노 글자를 폭에 맞춰 줄이고 [복사] 를 제목 줄(zsh 오른쪽)로
// 옮긴다 — 출력 긴 줄(Downloading URL · Moving App)만 '==> ' 너비로 들여 쓴 채 줄을 바꾼다. 폰에서는 명령 줄이 보이면(110px) 바로 친다
// (빈 터미널이 오래 비어 보이지 않게). ≥768 은 그대로(40% 보이면).
import { Fragment, useEffect, useRef, useState } from 'react';
import { Glass } from '@/components/glass/Glass';
import { CopyButton } from '@/components/glass/CopyButton';
import { INSTALL_COPY, OHAI_ARROW, typingSchedule, wrapTokens, type TerminalLine } from '@/data/install-copy';
import { MQ_PHONE, MQ_REDUCED } from '@/lib/hooks';

/** null = 완성(서버·JS 없음·감속 모션·재생 끝) */
type Play = { typed: number; lines: number; prompt: boolean } | null;

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

// 스타일은 Tailwind(이 절 전용 — globals.css 는 건드리지 않는다). CSS 모듈은 못 쓴다: next.config 의 turbopack '*.css' 규칙이
// *.module.css 를 전역 CSS 로 바꿔 클래스 이름 해시가 사라진다(s.x = undefined · '.hidden' 같은 이름이 전역으로 샌다).
// 판 자체는 <Glass level="regular" tint>(채움·테두리·그림자·광택은 globals 의 .glass 몫) — 여기는 창 안쪽만. 판에 의사 요소를 달지 않는다.
const S = {
  term: 'flex min-w-0 flex-col overflow-hidden',
  // 제목 띠: 신호등 점 셋 + 가운데 'zsh' (+ 폰: 오른쪽 [복사])
  bar:
    'relative flex h-11 flex-none items-center justify-between border-b border-white/[.07] bg-linear-to-b from-white/[.035] to-white/0 pl-3.5 pr-1.5 ' +
    'min-[768px]:h-[46px] min-[768px]:px-[18px]',
  // 폰: 제목 줄 오른쪽 [복사](작은 칩 32px) · ≥768: 숨김(명령 줄 오른쪽에 있다)
  barCopy: 'min-[768px]:hidden [--b-h:32px]',
  lights: 'flex gap-2',
  light: 'block size-[11px] rounded-full shadow-[inset_0_0_0_.5px_rgb(0_0_0/.28),inset_0_1px_0_rgb(255_255_255/.22)] min-[768px]:size-3',
  title: 'absolute left-1/2 -translate-x-1/2 select-none font-heading text-[13px] font-semibold leading-none tracking-[.01em] text-ink-2',
  // 본문(모노): 🍺 뒤 공백 둘을 지키는 pre-wrap · 줄은 공백과 '/' 뒤(<wbr>)에서 바뀌고 anywhere 는 마지막 보험 · '==>' 합자 끔
  // 폰 글자 = 명령 한 줄('$ ' + 37자 = 23.4em)이 안쪽 폭(100vw − 절 여백 40 − 판 여백 28)에 들어가는 크기, 최대 13.5px
  body:
    'min-w-0 flex-1 px-3.5 pt-3.5 pb-4 font-code text-[length:min(13.5px,calc((100vw_-_70px)_/_23.6))] leading-[1.7] text-ink-2 whitespace-pre-wrap ' +
    '[word-break:normal] [overflow-wrap:anywhere] [font-variant-ligatures:none] ' +
    'min-[768px]:px-7 min-[768px]:pt-[22px] min-[768px]:pb-[26px] min-[768px]:text-[15.5px] min-[768px]:leading-[1.8] min-[1280px]:text-[16px]',
  // 첫 줄: '$ 명령' + [복사](≥768) — 명령은 늘 가장 밝고 한 줄(nowrap — 줄바꿈 기회 <wbr> 도 쓰지 않는다)
  cmdRow: 'mb-1.5 flex items-center gap-2.5 min-[768px]:-mt-[5px] min-[768px]:mb-2 min-[768px]:gap-3.5',
  cmd: 'min-w-0 flex-1 [font:inherit] whitespace-nowrap text-ink-1',
  rowCopy: 'self-start phone:hidden',
  ps: 'select-none text-focus',
  // 명령 글자는 한 글자씩 제자리에 그려 두고 칠 차례가 아닌 글자만 숨긴다 — 움직이는 요소가 없어 layout-shift 0.
  // 아직 안 친 글자: 자리는 그대로(줄바꿈·높이 고정)
  ghost: 'invisible',
  // 타이핑 커서 = 다음에 칠 글자 칸(글자는 투명, 칸만 밝게)
  caretChar: 'rounded-[1.5px] bg-ink-1/80 text-transparent',
  // 새 프롬프트 뒤 정지 커서(폭 0 인라인 닻 + 절대 위치 막대 — 줄바꿈 기회를 만들지 않는다)
  caret: 'relative',
  caretBar: 'absolute left-px top-[.08em] bottom-[.02em] w-[.56em] rounded-[1.5px] bg-ink-1/80',
  out: 'min-w-0',
  // 출력 줄 — 줄이 바뀌면 '==> ' 너비(4ch)만큼 들여 쓴다. 뜨는 순간 140ms 떠오름(글자 요소 자신만 — 유리 조상엔 opacity 없음)
  line:
    'block [font:inherit] pl-[4ch] -indent-[4ch] transition-[opacity,translate] duration-150 ease-out motion-reduce:transition-none',
  arrow: 'text-[#8ea4ff]', // brew 의 ohai 화살표(파랑 — 보랏빛 쪽으로 기울임)
  done: 'text-ink-1',
  prompt: 'mt-0.5 block transition-opacity duration-150 ease-out motion-reduce:transition-none',
  // 재생 중 아직 안 뜬 줄: 자리만 차지하고 숨는다
  hidden: 'invisible opacity-0 translate-y-[3px]',
} as const;

const LIGHTS = ['bg-[#ff5f57]', 'bg-[#febc2e]', 'bg-[#28c840]'] as const;

/** 화면에 이만큼 보이면 재생을 시작한다(≥768) */
const START_RATIO = 0.4;
/** 폰: 터미널이 이만큼(px — 제목 줄 + 명령 줄) 보이면 시작한다 */
const START_PX_PHONE = 110;

function Caret() {
  return (
    <span aria-hidden="true" className={S.caret}>
      <span className={S.caretBar} />
    </span>
  );
}

/** 줄바꿈 조각(wrapTokens) — 하이픈 낱말은 통째(nowrap), '/' 뒤에 <wbr>. 출력 줄(정적)용. */
function Wrapped({ text }: { text: string }) {
  return (
    <>
      {wrapTokens(text).map((t, i) => (
        <Fragment key={i}>
          {t.nowrap ? <span className="whitespace-nowrap">{t.text}</span> : t.text}
          {t.wbrAfter ? <wbr /> : null}
        </Fragment>
      ))}
    </>
  );
}

/**
 * 명령 줄: 글자마다 제자리 칸(span) — typed 앞은 보이고, typed 칸은 커서(caret 일 때), 나머지는 자리만 차지한다.
 * 줄바꿈 자리는 Wrapped 와 같다(하이픈 낱말 통째 · '/' 뒤 <wbr>). 화면 읽기는 옆의 sr-only 원문이 맡는다(글자 칸은 aria-hidden).
 */
function TypedChars({ text, typed, caret }: { text: string; typed: number; caret: boolean }) {
  const tokens = wrapTokens(text);
  const starts = tokens.map((_, i) => tokens.slice(0, i).reduce((n, q) => n + q.text.length, 0));
  return (
    <>
      {tokens.map((t, i) => {
        const chars = Array.from(t.text, (ch, k) => {
          const at = starts[i] + k;
          const cls = at < typed ? undefined : caret && at === typed ? S.caretChar : S.ghost;
          return (
            <span key={k} className={cls}>
              {ch}
            </span>
          );
        });
        return (
          <Fragment key={i}>
            {t.nowrap ? <span className="whitespace-nowrap">{chars}</span> : chars}
            {t.wbrAfter ? <wbr /> : null}
          </Fragment>
        );
      })}
    </>
  );
}

export interface BrewTerminalProps {
  /** BREW.install */
  command: string;
  /** brewTranscript(BREW.install, 릴리스 버전) */
  lines: readonly TerminalLine[];
  className?: string;
}

export function BrewTerminal({ command, lines, className }: BrewTerminalProps) {
  const rootRef = useRef<HTMLElement>(null);
  const codeRef = useRef<HTMLSpanElement>(null);
  const [play, setPlay] = useState<Play>(null);
  const lineCount = lines.length;

  useEffect(() => {
    const el = rootRef.current;
    if (!el || typeof IntersectionObserver === 'undefined' || !window.matchMedia) return;
    if (window.matchMedia(MQ_REDUCED).matches) return;
    // 이미 화면에 걸쳐 있으면 재생하지 않는다(완성 그대로)
    if (el.getBoundingClientRect().top < window.innerHeight) return;
    const phone = window.matchMedia(MQ_PHONE).matches;

    const timers: number[] = [];
    let armed = false;
    let started = false;
    const arm = requestAnimationFrame(() => {
      armed = true;
      setPlay({ typed: 0, lines: 0, prompt: false });
    });

    const io = new IntersectionObserver(
      (entries) => {
        const en = entries[entries.length - 1];
        if (!en || !en.isIntersecting) return;
        const rootH = en.rootBounds?.height ?? window.innerHeight;
        const seen = en.intersectionRect.height;
        if (phone ? seen < Math.min(START_PX_PHONE, en.boundingClientRect.height) : en.intersectionRatio < START_RATIO && seen < rootH * START_RATIO) return;
        io.disconnect();
        started = true;
        const plan = typingSchedule(command.length, lineCount);
        plan.chars.forEach((t, i) => {
          timers.push(window.setTimeout(() => setPlay((p) => p && { ...p, typed: i + 1 }), t));
        });
        plan.lines.forEach((t, j) => {
          timers.push(window.setTimeout(() => setPlay((p) => p && { ...p, typed: command.length, lines: j + 1 }), t));
        });
        timers.push(window.setTimeout(() => setPlay((p) => p && { ...p, prompt: true }), plan.prompt));
        // 끝 = 완성 상태로 돌아간다(data-playing 이 빠진다 — 이후 다시 보여도 그대로)
        timers.push(window.setTimeout(() => setPlay(null), plan.prompt + 400));
      },
      { threshold: [0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, START_RATIO, 0.6, 0.8, 1] },
    );
    io.observe(el);

    return () => {
      cancelAnimationFrame(arm);
      io.disconnect();
      for (const t of timers) window.clearTimeout(t);
      // 재생 도중에 떨어지면 반쯤 친 상태로 남기지 않는다
      if (armed || started) setPlay(null);
    };
  }, [command, lineCount]);

  // 복사가 막히면 명령 글자를 선택해 둔다(직접 ⌘C 할 수 있게)
  const selectCommand = () => {
    const node = codeRef.current;
    const sel = window.getSelection();
    if (!node || !sel) return;
    const range = document.createRange();
    range.selectNodeContents(node);
    sel.removeAllRanges();
    sel.addRange(range);
  };

  const full = play === null;
  const typed = full ? command.length : play.typed;
  const shown = full ? lineCount : play.lines;
  const promptOn = full || play.prompt;
  const typingCaret = !full && typed < command.length;

  return (
    <Glass
      ref={rootRef}
      level="regular"
      tint
      data-terminal=""
      data-playing={full ? undefined : ''}
      className={cx(S.term, className)}
    >
      <div className={S.bar}>
        <span aria-hidden="true" className={S.lights}>
          {LIGHTS.map((bg) => (
            <i key={bg} className={cx(S.light, bg)} />
          ))}
        </span>
        <span className={S.title}>{INSTALL_COPY.terminalTitle}</span>
        <CopyButton
          text={command}
          ariaLabel={INSTALL_COPY.copyAria}
          variant="chip"
          onFail={selectCommand}
          className={S.barCopy}
        />
      </div>

      <div className={S.body}>
        <div className={S.cmdRow}>
          <code className={S.cmd} data-terminal-command="">
            <span aria-hidden="true" className={S.ps}>
              {'$ '}
            </span>
            <span className="sr-only">{command}</span>
            <span ref={codeRef} aria-hidden="true">
              <TypedChars text={command} typed={typed} caret={typingCaret} />
            </span>
          </code>
          <CopyButton
            text={command}
            ariaLabel={INSTALL_COPY.copyAria}
            variant="chip"
            onFail={selectCommand}
            className={S.rowCopy}
          />
        </div>

        <div className={S.out} data-terminal-output="">
          {lines.map((ln, j) => (
            <samp key={j} className={cx(S.line, ln.kind === 'done' && S.done, j >= shown && S.hidden)}>
              {ln.kind === 'ohai' ? (
                <>
                  <span className={S.arrow}>{OHAI_ARROW}</span> <Wrapped text={ln.text} />
                </>
              ) : (
                ln.text
              )}
            </samp>
          ))}
          <span aria-hidden="true" className={cx(S.prompt, !promptOn && S.hidden)}>
            <span className={S.ps}>$</span> <Caret />
          </span>
        </div>
      </div>
    </Glass>
  );
}

export default BrewTerminal;
