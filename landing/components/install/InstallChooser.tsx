'use client';
// components/install/InstallChooser.tsx — 설치 선택 창(docs/v3/brief.md §11). 히어로·아웃트로·메뉴바의 다운로드 버튼(DownloadCTA, ≥768 · mac·other)이 쓴다.
// 사용자(2026-10-30): "설치하기 눌렀을때 바로 dmg 파일 다운되는게 아니라 브루나 dmg 파일 직접 다운 같은거중 선택할 수 있게끔 하자."
//
// 점진적 향상
//   서버 HTML(·JS 없음): 방아쇠 = 평범한 <a href="/#install"> — 클릭하면 두 선택이 다 있는 설치 절로 간다(다운로드 없음).
//   하이드레이션 뒤: 같은 <a> 에 role="button" · tabIndex 0(Safari 기본값은 Tab 이 링크에 서지 않는다 — 버튼처럼 서게) · aria-haspopup="dialog" ·
//     aria-expanded · aria-controls 를 단다. 클릭 · Enter · Space(놓을 때) = 창 열고 닫기(이동·다운로드 없음). ⌘·Ctrl·Shift·Alt·가운데 클릭은 링크 그대로.
// 창(role="dialog", 비모달, 접근 이름 CHOOSER_COPY.ariaLabel): thick 유리 판 하나를 document.body 로 포털한다(절의 isolate·overflow 밖).
//   z: 메뉴바 창(fixed) = 메뉴바(--z-nav 50) 위 60 · 히어로·아웃트로 창(absolute) = 메뉴바 바로 아래 49 — 열어 둔 채 스크롤해도 메뉴바를 덮지 않는다.
//   내용 순서: Homebrew 제목 + [복사](진짜 복사 — BREW.install) · 한 줄 · 명령(한 줄) / 구분선 / DMG 줄 전체 = /api/download 링크 /
//   휴대폰 앱 줄(§12 — 칩 [아이폰] = App Store 새 탭 · [안드로이드 베타] = /#android) / 설치 방법 자세히 보기(/#install).
// 자리: computePlacement(chooser-logic.ts — 순수 함수, 값 시험). 열 때 · 창 크기가 바뀔 때 · 메뉴바 창은 스크롤할 때 · 방아쇠(조상)의 등장 애니메이션이
//   도는 동안 매 프레임 JS 로 잰다(CSS anchor 없음 — Safari 도 같다). 기준은 방아쇠 + CTA 줄([data-chooser-row]) — 폭이 좁아 brew 알약이 아래 줄로
//   내려가면 창이 알약을 반쯤 덮지 않게 줄 아래에 연다. 메뉴바 방아쇠는 fixed, 나머지는 문서 기준 absolute(스크롤하면 방아쇠와 함께 간다).
//   위아래 어디에도 다 안 들어가면(낮은 노트북 창의 페이지 끝 아웃트로) 덜 굴리는 쪽으로 열고 모자란 만큼 페이지를 바로 굴린다.
// 포커스: 열면 첫 행동(복사 버튼)으로 · Tab/Shift+Tab 은 늘 직접 옮겨 창 안에서 돈다(Safari 처럼 링크를 건너뛰는 브라우저도 같다) · 창이 열린 채
//   포커스가 창 밖(창 안 글자를 클릭해 body 로 빠진 때 등)이면 Tab 이 창 안으로 돌아온다 · Esc = 닫고 방아쇠로 · 바깥 클릭 = 닫기 ·
//   DMG 줄 · [아이폰](새 탭) = 내려받기/열기 + 닫고 방아쇠로 · '설치 방법 자세히 보기' · [안드로이드 베타] = 닫고 설치 절(그 카드)로
//   (방아쇠로 되돌리면 스크롤이 히어로로 돌아간다) ·
//   폭을 폰으로 줄여 방아쇠가 숨으면 닫고, 포커스가 창에 있었으면 같은 자리의 폰 짝 링크(*-install)로 넘긴다. 한 번에 하나만 열린다.
// 움직임: 열 때 opacity·scale 140–160ms(@starting-style — 미지원 브라우저는 그냥 나타난다), 감속 모션이면 전이 없음. 위치가 고정이라 레이아웃 이동 0.
// 스타일은 install-chooser.css(전역 — 이름은 전부 ic-. 이 프로젝트는 *.module.css 도 전역 CSS 로 컴파일된다).
import { useCallback, useId, useLayoutEffect, useRef, useState, useSyncExternalStore } from 'react';
import type { FocusEvent, KeyboardEvent as ReactKeyboardEvent, MouseEvent as ReactMouseEvent } from 'react';
import { createPortal } from 'react-dom';
import { BREW, LINKS, RELEASE_FALLBACK } from '@/data/fixtures';
import type { ReleaseInfo } from '@/data/fixtures';
import { CHOOSER_COPY, INSTALL_COPY, chooserMetaParts, installChoice } from '@/data/install-copy';
import { Glass, glassClass } from '@/components/glass/Glass';
import { GlassFx } from '@/components/glass/GlassFx';
import { CopyButton } from '@/components/glass/CopyButton';
import { asRelease, computePlacement, nextFocusIndex } from './chooser-logic';
import './install-chooser.css';

export type ChooserPlacement = 'nav' | 'hero' | 'outro';

export interface InstallChooserProps {
  placement: ChooserPlacement;
  /** 방아쇠 글자('다운로드' · 'Mac용 다운로드') — 그대로 */
  label: string;
  /** 방아쇠 접근 이름(보이는 글자를 포함 — 메뉴바 'Mac용 다운로드'). 없으면 보이는 글자 */
  ariaLabel?: string;
  /** 방아쇠 유리 버튼 클래스(glassButtonClass …) */
  className?: string;
  /** DMG 줄 메타(chooserMetaParts). null 이면(/licenses 처럼 릴리스를 받지 않은 페이지) 처음 열 때 /api/release 에서 만든다 */
  meta: readonly string[] | null;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

/** 한 번에 하나만: 열리는 창이 자기 id 를 알리면 나머지는 닫는다 */
const OPEN_EVENT = 'aing:install-chooser-open';
const RELEASE_API = '/api/release';

const noopSubscribe = () => () => {};
/** 서버·하이드레이션 첫 렌더 = false, 그 뒤 = true(어긋남 없이 한 번 더 그린다) */
const useHydrated = () => useSyncExternalStore(noopSubscribe, () => true, () => false);

function navHeight(): number {
  const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--nav-h'));
  return Number.isFinite(v) && v > 0 ? v : 46;
}

/** 창 자리를 단다. 방아쇠가 안 보이면(폭이 바뀌어 숨음) false.
 *  문서 기준 창이 위아래 어디에도 다 안 들어가면 computePlacement 가 준 만큼 페이지를 바로 굴린다(낮은 노트북 창의 페이지 끝 아웃트로).
 *  창이 문서와 함께 움직이니 굴린 뒤 다시 잴 필요가 없고, 다음에 잴 때는 0 이 나온다(되먹임 없음). */
function place(trigger: HTMLElement, pop: HTMLElement, fixed: boolean): boolean {
  const t = trigger.getBoundingClientRect();
  if (t.width === 0 && t.height === 0) return false;
  const row = trigger.closest('[data-chooser-row]');
  // 문서 높이는 창을 뺀 값으로 잰다 — 지난번 자리(문서 끝 아래)가 문서를 늘려 둔 채로 재지 않게 잠깐 맨 위로 옮긴다(그리기 전이라 보이지 않는다)
  let docHeight: number | undefined;
  if (!fixed) {
    pop.style.top = '0px';
    docHeight = document.documentElement.scrollHeight;
  }
  const p = computePlacement({
    trigger: t,
    row: row ? row.getBoundingClientRect() : null,
    pop: { width: pop.offsetWidth, height: pop.offsetHeight },
    viewport: { width: document.documentElement.clientWidth, height: window.innerHeight },
    navH: navHeight(),
    fixed,
    scroll: { x: window.scrollX, y: window.scrollY },
    docHeight,
  });
  pop.style.top = `${p.top}px`;
  pop.style.left = `${p.left}px`;
  pop.style.transformOrigin = `${p.align} ${p.side === 'above' ? 'bottom' : 'top'}`;
  pop.dataset.side = p.side;
  pop.dataset.align = p.align;
  if (p.scrollBy) window.scrollBy({ top: p.scrollBy, behavior: 'instant' });
  return true;
}

/** 창 안의 Tab 대상(보이는 링크·버튼) */
function focusables(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>('a[href], button:not([disabled])')).filter((el) => el.getClientRects().length > 0);
}

/** 방아쇠와 그 조상에 걸린, 끝이 있는 애니메이션·전이(히어로 글 줄 rise-in 등) — 도는 동안 창이 따라간다 */
function runningAncestorAnimations(el: Element): Animation[] {
  const out: Animation[] = [];
  for (let n: Element | null = el; n; n = n.parentElement) {
    if (typeof n.getAnimations !== 'function') break;
    for (const a of n.getAnimations()) {
      if (a.playState !== 'running' && a.playState !== 'paused') continue;
      const end = a.effect?.getComputedTiming().endTime;
      if (typeof end === 'number' && Number.isFinite(end)) out.push(a);
    }
  }
  return out;
}

/** 릴리스를 받지 않은 페이지의 메타 — 실패하면 DMG 카드와 같은 폴백 값 */
async function loadMeta(): Promise<string[]> {
  let release: ReleaseInfo = RELEASE_FALLBACK;
  try {
    const res = await fetch(RELEASE_API, { headers: { Accept: 'application/json' } });
    if (res.ok) release = asRelease(await res.json()) ?? RELEASE_FALLBACK;
  } catch {
    // 폴백 그대로
  }
  return chooserMetaParts(installChoice(release, RELEASE_FALLBACK));
}

function Chevron() {
  return (
    <svg aria-hidden="true" className="ic-chev" viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2.25 3.75 5 6.5l2.75-2.75" />
    </svg>
  );
}

function DownloadGlyph() {
  return (
    <svg aria-hidden="true" width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 3.25v9.5" />
      <path d="m6 9 4 4 4-4" />
      <path d="M4 16.25h12" />
    </svg>
  );
}

export function InstallChooser({ placement, label, ariaLabel, className, meta }: InstallChooserProps) {
  const hydrated = useHydrated();
  const [open, setOpen] = useState(false);
  const [loadedMeta, setLoadedMeta] = useState<readonly string[] | null>(null);
  const loading = useRef(false);
  const triggerRef = useRef<HTMLAnchorElement>(null);
  const popRef = useRef<HTMLElement>(null);
  const codeRef = useRef<HTMLSpanElement>(null);
  const popId = useId();
  const fixed = placement === 'nav';
  const shownMeta = meta ?? loadedMeta;

  const close = useCallback((restoreFocus: boolean) => {
    setOpen(false);
    if (restoreFocus) triggerRef.current?.focus({ preventScroll: true });
  }, []);

  const openChooser = () => {
    const trigger = triggerRef.current;
    if (!trigger || trigger.getClientRects().length === 0) return;
    window.dispatchEvent(new CustomEvent(OPEN_EVENT, { detail: popId }));
    setOpen(true);
    if (!meta && !loading.current) {
      loading.current = true;
      void loadMeta().then(setLoadedMeta);
    }
  };
  const toggle = () => (open ? close(true) : openChooser());

  // 열려 있는 동안: 자리 · 첫 행동 포커스 · 창 크기/스크롤(메뉴바)/등장 애니메이션 · 바깥 클릭 · Esc · Tab · 다른 창 열림
  useLayoutEffect(() => {
    if (!open) return;
    const trigger = triggerRef.current;
    const pop = popRef.current;
    if (!trigger || !pop) return;
    let live = true;
    place(trigger, pop, fixed);
    focusables(pop)[0]?.focus({ preventScroll: true });

    // 폭이 폰으로 줄어 방아쇠가 숨으면 닫는다. 포커스가 창(·방아쇠)에 있었으면 같은 자리의 보이는 폰 짝 링크로 넘긴다(body 로 떨어지지 않게)
    const closeHidden = () => {
      const active = document.activeElement;
      if (active && (pop.contains(active) || trigger.contains(active))) {
        const twin = Array.from(document.querySelectorAll<HTMLElement>(`[data-cta="${placement}-install"]`)).find((el) => el.getClientRects().length > 0);
        twin?.focus({ preventScroll: true });
      }
      setOpen(false);
    };

    let raf = 0;
    const reflow = () => {
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        if (!place(trigger, pop, fixed)) closeHidden();
      });
    };

    // 방아쇠(조상)가 아직 움직이는 중이면(히어로 등장 rise-in — translate 14px) 끝날 때까지 매 프레임 따라가고, 끝나면 한 번 더 잰다
    let follow = 0;
    const anims = runningAncestorAnimations(trigger);
    if (anims.length > 0) {
      let settled = false;
      const tick = () => {
        follow = 0;
        if (!live) return;
        if (!place(trigger, pop, fixed)) return closeHidden();
        if (!settled) follow = requestAnimationFrame(tick);
      };
      follow = requestAnimationFrame(tick);
      void Promise.all(anims.map((a) => a.finished.catch(() => undefined))).then(() => {
        settled = true;
        if (live && !place(trigger, pop, fixed)) closeHidden();
      });
    }

    const onPointerDown = (e: PointerEvent) => {
      const target = e.target as Node | null;
      if (target && (pop.contains(target) || trigger.contains(target))) return;
      setOpen(false);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        setOpen(false);
        trigger.focus({ preventScroll: true });
        return;
      }
      if (e.key !== 'Tab' || e.altKey || e.ctrlKey || e.metaKey) return;
      const active = document.activeElement as HTMLElement | null;
      // 방아쇠에서 Shift+Tab = 창을 닫고 앞 요소로(기본 동작 그대로)
      if (active === trigger && e.shiftKey) {
        setOpen(false);
        return;
      }
      // 그 밖에는 늘 직접 옮긴다: 창 안이면 다음·이전, 창 밖(body · 방아쇠)이면 창의 처음·끝으로
      const items = focusables(pop);
      const next = nextFocusIndex(items.length, active ? items.indexOf(active) : -1, e.shiftKey);
      if (next < 0) return;
      e.preventDefault();
      items[next].focus();
    };
    const onOtherOpen = (e: Event) => {
      if ((e as CustomEvent<string>).detail !== popId) setOpen(false);
    };
    window.addEventListener('resize', reflow);
    if (fixed) window.addEventListener('scroll', reflow, { passive: true });
    document.addEventListener('pointerdown', onPointerDown, true);
    document.addEventListener('keydown', onKeyDown);
    window.addEventListener(OPEN_EVENT, onOtherOpen);
    return () => {
      live = false;
      if (raf) cancelAnimationFrame(raf);
      if (follow) cancelAnimationFrame(follow);
      window.removeEventListener('resize', reflow);
      window.removeEventListener('scroll', reflow);
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('keydown', onKeyDown);
      window.removeEventListener(OPEN_EVENT, onOtherOpen);
    };
  }, [open, fixed, popId, placement]);

  // ── 방아쇠 ──
  const onTriggerClick = (e: ReactMouseEvent<HTMLAnchorElement>) => {
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return; // 새 탭 = 링크 그대로(설치 절)
    e.preventDefault();
    toggle();
  };
  const onTriggerKeyDown = (e: ReactKeyboardEvent<HTMLAnchorElement>) => {
    // Enter 는 keydown 에서(기본 동작 = 링크 이동을 막는다 — 막으면 keypress 도 안 생겨 새로 포커스된 [복사] 가 눌리지 않는다)
    if (e.key === 'Enter') {
      e.preventDefault();
      if (!e.repeat) toggle();
    } else if (e.key === ' ') {
      e.preventDefault(); // 페이지 스크롤 막기 — 동작은 놓을 때(버튼과 같다)
    } else if (e.key === 'ArrowDown' && !open) {
      e.preventDefault();
      openChooser();
    }
  };
  const onTriggerKeyUp = (e: ReactKeyboardEvent<HTMLAnchorElement>) => {
    if (e.key !== ' ') return;
    e.preventDefault();
    toggle();
  };

  // ── 창 ──
  // 포커스가 창·방아쇠 밖의 다른 요소로 가면(스크린 리더 가상 커서 등) 닫는다. 한 프레임 뒤에 본다 — 복사 폴백(execCommand)이 잠깐 body 에
  // 붙였다 떼는 textarea 로 포커스가 지나가도 닫히지 않게. body(창 안 글자 클릭 등)면 그대로 — 다음 Tab 이 창 안으로 돌아온다.
  const onPopBlur = (e: FocusEvent<HTMLElement>) => {
    if (!e.relatedTarget) return;
    requestAnimationFrame(() => {
      const a = document.activeElement;
      if (!a || a === document.body || popRef.current?.contains(a) || triggerRef.current?.contains(a)) return;
      setOpen(false);
    });
  };
  // 복사가 막히면 명령 글자를 선택해 둔다(직접 ⌘C — CommandPill 과 같다)
  const selectCommand = () => {
    const el = codeRef.current;
    const sel = window.getSelection();
    if (!el || !sel) return;
    const range = document.createRange();
    range.selectNodeContents(el);
    sel.removeAllRanges();
    sel.addRange(range);
  };

  const a11y = hydrated
    ? { role: 'button' as const, tabIndex: 0, 'aria-haspopup': 'dialog' as const, 'aria-expanded': open, 'aria-controls': popId }
    : {};

  return (
    <>
      <a
        ref={triggerRef}
        href={LINKS.install}
        aria-label={ariaLabel}
        data-cta={`${placement}-chooser`}
        className={cx(className, 'ic-trigger')}
        onClick={onTriggerClick}
        onKeyDown={onTriggerKeyDown}
        onKeyUp={onTriggerKeyUp}
        {...a11y}
      >
        {label}
        <Chevron />
        <GlassFx specular />
      </a>
      {hydrated &&
        createPortal(
          <Glass
            ref={popRef}
            id={popId}
            level="thick"
            specular
            role="dialog"
            aria-label={CHOOSER_COPY.ariaLabel}
            hidden={!open}
            data-chooser={placement}
            data-strategy={fixed ? 'fixed' : 'absolute'}
            className="ic-pop"
            onBlur={onPopBlur}
          >
            <div className="ic-head">
              <p className="ic-title">{CHOOSER_COPY.brewTitle}</p>
              <CopyButton
                text={BREW.install}
                ariaLabel={INSTALL_COPY.copyAria}
                variant="chip"
                dataCta="chooser-brew"
                onFail={selectCommand}
                className="ic-copy"
              />
            </div>
            <p className="ic-line">{CHOOSER_COPY.brewLine}</p>
            <div className={cx(glassClass('thin'), 'ic-cmd')} data-command="">
              <code className="ic-cmd__code">
                <span aria-hidden="true" className="cmd-pill__prompt">
                  {'$ '}
                </span>
                <span ref={codeRef}>{BREW.install}</span>
              </code>
            </div>
            <hr className="ic-rule" />
            <a href={LINKS.download} tabIndex={0} data-cta="chooser-dmg" className="ic-dmg" onClick={() => close(true)}>
              <span className="ic-dmg__icon">
                <DownloadGlyph />
              </span>
              <span className="ic-dmg__text">
                <span className="ic-title">{CHOOSER_COPY.dmgTitle}</span>
                {/* 메타를 아직 받는 중이면(릴리스 없는 페이지) 같은 높이의 빈 줄 — 창 높이가 바뀌지 않게 */}
                <span className="ic-meta">{shownMeta && shownMeta.length > 0 ? shownMeta.join(' · ') : ' '}</span>
              </span>
            </a>
            <div className="ic-phone">
              <p className="ic-phone__title">{CHOOSER_COPY.phoneTitle}</p>
              <div className="ic-phone__chips">
                <a
                  href={LINKS.appStore}
                  target="_blank"
                  rel="noopener noreferrer"
                  tabIndex={0}
                  data-cta="chooser-iphone"
                  className="gbtn gbtn--chip ic-chip"
                  onClick={() => close(true)}
                >
                  {CHOOSER_COPY.phoneIphone}
                </a>
                <a href={LINKS.android} tabIndex={0} data-cta="chooser-android" className="gbtn gbtn--chip ic-chip" onClick={() => close(false)}>
                  {CHOOSER_COPY.phoneAndroid}
                </a>
              </div>
            </div>
            <a href={LINKS.install} tabIndex={0} data-cta="chooser-install" className="ic-more" onClick={() => close(false)}>
              {CHOOSER_COPY.more}
            </a>
          </Glass>,
          document.body,
        )}
    </>
  );
}

export default InstallChooser;
