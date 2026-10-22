'use client';
// components/features/FeatureStage.tsx — 핵심 기능 6장면: 고정 무대 + 유리 세그먼트(docs/v3/brief.md §4.4). 배치는 features.css.
//
// 고정 무대(≥1024 × ≥760 · 감속 아님 · JS): 스크롤 진행으로 활성 장면이 바뀐다. .root 의 고정 구간(R = 절 높이 − 무대 높이)을
//   6등분 — 장면 i = [i, i+1)·R/6. 세그먼트는 tablist 가 아니라 목차 링크 목록(#f-…, 활성 칸 aria-current): 칸을 누르면
//   그 장면 앵커(구간 한가운데)로 부드럽게 스크롤하고(scrollIntoView · 주소 #id), 그동안은 중간 장면을 건너뛴다(잠금 — 도착·스크롤 끝·
//   사용자 입력·시한에서 풀림). 장면이 바뀌면 물방울이 칸 사이를 미끄러지며 가로로 늘었다 줄고(WAAPI scale), 무대 유리의 서리가 한 번
//   출렁인다(--g-blur). 메시지 장면은 구간 60% 를 지나면 읽음 판으로(내 말 옆 '1'이 사라진다 — 스크롤로만, 자동 연출 아님).
// 흐름(그 밖·JS 없음): 장면을 세로로 쌓는다 — 스크롤 리스너 없음.
// 렌더는 window load 뒤에만 받는다(첫 화면 예산 — §6): 흐름 = 화면 한 장 앞으로 다가온 장면, 고정 = 지금·다음 장면 → 2초 뒤 전부.
import { useEffect, useRef, useState, type CSSProperties, type MouseEvent } from 'react';
import { glassClass } from '@/components/glass/Glass';
import { LocalLight } from '@/components/glass/LocalLight';
import { useRefraction } from '@/components/glass/useRefraction';
import { useMediaQuery } from '@/lib/hooks';
import { KeepDots } from '@/components/ui/KeepDots';
import { FEATURE_NAV_LABEL, FEATURE_SECTION_LABEL } from './copy';
import { Composition } from './Composition';
import { SCENES } from './scenes.data';
import './features.css';

/** 고정 무대 조건(JS 쪽 — CSS 는 같은 미디어 + html.js). */
export const MQ_PIN = '(min-width: 1024px) and (min-height: 760px) and (prefers-reduced-motion: no-preference)';

const N = SCENES.length;
/** 메시지 장면(안 읽음 → 읽음 교체가 있는 장면) */
const MSG = SCENES.findIndex((sc) => sc.comp.items.some((it) => it.kind === 'img' && it.swap));
/** 장면 구간 안에서 읽음 판으로 바뀌는 지점(앵커가 0.5 에 떨어지므로 그보다 조금 뒤) */
const READ_AT = 0.6;
/** 세그먼트 이동 잠금 시한(ms) — scrollend 를 못 받는 브라우저의 보험 */
const LOCK_MS = 1800;
/** load 뒤 나머지 장면 렌더를 받기 시작하는 시각(ms, 고정 무대) */
const ALL_AFTER_MS = 2000;

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

export function FeatureStage() {
  const pinned = useMediaQuery(MQ_PIN);

  const rootRef = useRef<HTMLElement>(null);
  const stickyRef = useRef<HTMLDivElement>(null);
  const dropRef = useRef<HTMLSpanElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const bezelRefs = useRef<(HTMLDivElement | null)[]>([]);
  const activeRef = useRef(0);
  const lockRef = useRef<{ i: number; at: number; until: number } | null>(null);

  const [active, setActive] = useState(0);
  const [read, setRead] = useState(false);
  const [live, setLive] = useState(false);
  const [maxSeen, setMaxSeen] = useState(0);
  const [near, setNear] = useState<readonly boolean[]>(() => SCENES.map(() => false));
  const [loaded, setLoaded] = useState(false);
  const [allowAll, setAllowAll] = useState(false);

  // 세그먼트 물방울 = 굴절(데스크톱 Chromium 만 — 그 밖은 blur 폴백). 고정 무대에서만 보이므로 그때만 건다.
  useRefraction(dropRef, { level: 'regular', band: 12, scale: 30, aberration: 0.1, rimBlur: 0.5, enabled: pinned });

  // window load(첫 화면 예산) → 렌더 받기 허용. 고정 무대는 2초 뒤 나머지 장면도.
  useEffect(() => {
    let raf = 0;
    const on = () => {
      raf = requestAnimationFrame(() => setLoaded(true));
    };
    if (document.readyState === 'complete') on();
    else window.addEventListener('load', on, { once: true });
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('load', on);
    };
  }, []);
  useEffect(() => {
    if (!loaded) return;
    const t = window.setTimeout(() => setAllowAll(true), ALL_AFTER_MS);
    return () => window.clearTimeout(t);
  }, [loaded]);

  // 장면 렌더 상자가 화면 한 장 앞으로 오면 near(한 번 true 면 유지). 고정 무대에선 여섯 상자가 같은 자리라 함께 켜진다.
  useEffect(() => {
    const els = bezelRefs.current;
    const io = new IntersectionObserver(
      (entries) => {
        const hit = entries.filter((en) => en.isIntersecting).map((en) => els.indexOf(en.target as HTMLDivElement));
        if (hit.length === 0) return;
        setNear((prev) => (hit.every((i) => prev[i]) ? prev : prev.map((v, i) => v || hit.includes(i))));
      },
      { rootMargin: '100% 0px' },
    );
    els.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, []);

  // 활성 장면 바꾸기(콜백 전용 — 스크롤 rAF·클릭). 바뀔 때 물방울을 늘였다 줄이고 무대 서리를 한 번 출렁인다.
  const applyRef = useRef<(idx: number, readNow: boolean) => void>(() => {});
  useEffect(() => {
    applyRef.current = (idx, readNow) => {
      const prev = activeRef.current;
      if (idx !== prev) {
        activeRef.current = idx;
        setActive(idx);
        setLive(true);
        setMaxSeen((m) => Math.max(m, idx));
        const drop = dropRef.current;
        if (drop && typeof drop.animate === 'function') {
          const sx = 1 + 0.16 * Math.min(Math.abs(idx - prev), 3);
          drop.animate([{ scale: '1 1' }, { scale: `${sx} 0.84`, offset: 0.36 }, { scale: '1.02 0.98', offset: 0.7 }, { scale: '1 1' }], {
            duration: 620,
            easing: 'cubic-bezier(.3,.7,.2,1)',
          });
        }
        const stage = stageRef.current;
        if (stage && typeof stage.animate === 'function') {
          stage.animate([{ '--g-blur': '36px' }, { '--g-blur': '52px', offset: 0.3 }, { '--g-blur': '36px' }], {
            duration: 700,
            easing: 'ease-out',
          });
        }
      }
      setRead(readNow);
    };
  });

  // 고정 무대: 스크롤 진행 → 활성 장면(rAF 로 한 프레임에 한 번). 흐름 배치에선 아무것도 하지 않는다.
  useEffect(() => {
    if (!pinned) return;
    const root = rootRef.current;
    const sticky = stickyRef.current;
    if (!root || !sticky) return;
    let raf = 0;
    let pinTop = 0;
    let padY = 0;
    const measure = () => {
      pinTop = parseFloat(getComputedStyle(sticky).top) || 0;
      // 고정 구간 = 절 내용 높이 − 무대 높이. 절 아래 여백(무대 유리 그림자가 절 경계에서 잘리지 않게 둔 자리 — features.css)은 빼고 잰다
      const rs = getComputedStyle(root);
      padY = (parseFloat(rs.paddingTop) || 0) + (parseFloat(rs.paddingBottom) || 0);
    };
    const update = () => {
      raf = 0;
      const R = root.offsetHeight - padY - sticky.offsetHeight;
      if (!(R > 0)) return;
      const step = R / N;
      const y = (pinTop - root.getBoundingClientRect().top) / step;
      const idx = Math.max(0, Math.min(N - 1, Math.floor(y)));
      const lock = lockRef.current;
      if (lock) {
        if (idx === lock.i || performance.now() > lock.until) lockRef.current = null;
        else return;
      }
      applyRef.current(idx, idx > MSG || (idx === MSG && y - idx >= READ_AT));
    };
    const schedule = () => {
      if (!raf) raf = requestAnimationFrame(update);
    };
    const onResize = () => {
      measure();
      schedule();
    };
    // 사용자가 직접 스크롤을 잡거나(휠·터치·키) 스크롤이 끝나면 세그먼트 이동 잠금을 푼다. 클릭보다 앞선 사건(늦게 배달된 앞
    // 스크롤의 scrollend 등)은 무시한다 — 실측: 클릭 직전 스크롤의 scrollend 가 클릭 뒤에 와서 잠금을 바로 풀었다.
    const release = (e: Event) => {
      const lock = lockRef.current;
      if (lock && e.timeStamp > lock.at) {
        lockRef.current = null;
        schedule();
      }
    };
    measure();
    schedule();
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', onResize);
    window.addEventListener('scrollend', release);
    window.addEventListener('wheel', release, { passive: true });
    window.addEventListener('touchstart', release, { passive: true });
    window.addEventListener('keydown', release);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', onResize);
      window.removeEventListener('scrollend', release);
      window.removeEventListener('wheel', release);
      window.removeEventListener('touchstart', release);
      window.removeEventListener('keydown', release);
    };
  }, [pinned]);

  // 세그먼트 칸(목차 링크): 기본 동작(앵커로 부드럽게 스크롤 + 주소의 #)은 그대로 두고, 고정 무대면 도착 전까지 중간 장면을 건너뛴다.
  //   스크롤은 직접 건다(scrollIntoView — 앵커의 scroll-margin·문서의 scroll-padding 을 그대로 따른다) + 주소에 #id(pushState):
  //   기본 조각 이동은 포커스를 body 로 떨어뜨려(실측 — 키보드로 칸을 고르면 포커스 링이 사라지고 다음 Tab 이 절 맨 앞에서 시작)
  //   막는다. 포커스는 누른 칸에 남는다. 새 탭 열기(⌘·Ctrl·Shift·Alt·가운데 버튼)는 건드리지 않는다.
  //   시각은 클릭 이벤트의 timeStamp(= performance.now() 와 같은 기준)로 잰다.
  const onJump = (e: MouseEvent<HTMLAnchorElement>, i: number) => {
    if (!pinned || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const id = SCENES[i].id;
    const target = document.getElementById(id);
    if (!target) return;
    e.preventDefault();
    lockRef.current = { i, at: e.timeStamp, until: e.timeStamp + LOCK_MS };
    applyRef.current(i, false);
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    if (location.hash !== `#${id}`) history.pushState(null, '', `#${id}`);
  };

  const mountAt = (i: number) => loaded && near[i] && (!pinned || allowAll || i <= maxSeen + 1);

  return (
    <section
      ref={rootRef}
      id="features"
      aria-label={FEATURE_SECTION_LABEL}
      className="fx-root"
      data-features=""
      data-live={live ? '' : undefined}
    >
      {SCENES.map((sc, i) => (
        <span key={sc.id} id={sc.id} className="fx-anchor" style={{ '--i': i, order: i * 2 } as CSSProperties} />
      ))}

      <div ref={stickyRef} className="fx-sticky">
        {/* 무대 뒤 국소 빛(고정 무대 — 유리 뒤에 늘 색이 있게) */}
        <LocalLight tone="violet" x="66%" y="54%" size="min(1180px, 86vw)" aspect={0.7} strength={0.36} className="fx-pin-light" />
        <LocalLight tone="orchid" x="86%" y="26%" size={560} strength={0.22} className="fx-pin-light" />
        <LocalLight tone="indigo" x="16%" y="76%" size={820} aspect={0.5} strength={0.24} className="fx-pin-light" />

        <nav
          aria-label={FEATURE_NAV_LABEL}
          className={cx(glassClass('regular'), 'fx-seg')}
          style={{ '--active': active } as CSSProperties}
        >
          <span ref={dropRef} aria-hidden="true" className={cx(glassClass('regular'), 'fx-drop')} />
          <ol className="fx-seg-list">
            {SCENES.map((sc, i) => (
              <li key={sc.id}>
                <a
                  href={`#${sc.id}`}
                  className="fx-seg-link"
                  aria-current={pinned && active === i ? 'true' : undefined}
                  onClick={(e) => onJump(e, i)}
                >
                  {sc.tab}
                </a>
              </li>
            ))}
          </ol>
        </nav>

        <div className="fx-row">
          <div ref={stageRef} aria-hidden="true" className={cx(glassClass('thick'), 'fx-stage-glass')} />
          {SCENES.map((sc, i) => (
            <article
              key={sc.id}
              aria-labelledby={`${sc.id}-h`}
              className="fx-scene"
              style={{ order: i * 2 + 1 }}
              data-scene={sc.id}
              data-on={active === i ? '' : undefined}
              data-read={i === MSG && read ? '' : undefined}
            >
              <div className="fx-copy">
                <h2 id={`${sc.id}-h`} className="t-h2-feature fx-title text-ink-1">
                  {sc.title[0]}
                  <br />
                  {sc.title[1]}
                </h2>
                <p className="t-lead fx-body">
                  <KeepDots text={sc.body} />
                </p>
              </div>
              <div
                ref={(el) => {
                  bezelRefs.current[i] = el;
                }}
                className="fx-bezel"
              >
                <LocalLight tone={i % 2 ? 'orchid' : 'violet'} x="50%" y="55%" size="min(820px, 160vw)" strength={0.3} className="fx-flow-light" />
                <div aria-hidden="true" className={cx(glassClass('thick'), 'fx-bezel-glass')} />
                <Composition comp={sc.comp} mount={mountAt(i)} />
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

export default FeatureStage;
