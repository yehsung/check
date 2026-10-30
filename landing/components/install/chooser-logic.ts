// components/install/chooser-logic.ts — 설치 선택 창(docs/v3/brief.md §11)의 순수 계산. DOM·React 없음 — chooser.test.ts 가 값으로 확인한다.
// InstallChooser.tsx 가 쓴다: 자리(computePlacement) · Tab 순환(nextFocusIndex) · /api/release JSON 읽기(asRelease).
import type { ReleaseAsset, ReleaseInfo } from '@/data/fixtures';

/** 화면 가장자리 여백 · 방아쇠(또는 CTA 줄)와의 간격(px) */
export const EDGE = 16;
export const GAP = 10;

/** 뷰포트 기준 사각형(DOMRect 를 그대로 넘겨도 된다) */
export interface Box {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface PlaceInput {
  /** 방아쇠 */
  trigger: Box;
  /** 방아쇠가 든 CTA 줄([data-chooser-row]). 폭이 좁아 brew 알약이 아래 줄로 내려가면 그 줄까지 — 창이 알약을 반쯤 덮지 않게 줄 아래(위)에 연다. 없으면 방아쇠만 */
  row?: Box | null;
  /** 창 크기 */
  pop: { width: number; height: number };
  /** 뷰포트(documentElement.clientWidth · innerHeight) */
  viewport: { width: number; height: number };
  /** 메뉴바 높이(--nav-h). 위로 열 때 천장 = 메뉴바 아래 8px */
  navH: number;
  /** true = position: fixed(메뉴바 창) · false = 문서 기준 absolute(scroll 을 더한다) */
  fixed: boolean;
  scroll: { x: number; y: number };
  /** 문서 높이(documentElement.scrollHeight — 창이 문서를 늘리기 전). 주면 문서 기준 창이 위아래 어디에도 다 안 들어갈 때
   *  페이지를 굴려 다 보이게 한다(scrollBy). 없으면(메뉴바 · 값 시험의 옛 규칙) 굴리지 않는다 */
  docHeight?: number;
}

export interface Placement {
  top: number;
  left: number;
  side: 'above' | 'below';
  align: 'left' | 'right';
  /** 창을 다 보이게 페이지를 굴릴 양(px · + 아래로 · − 위로 · 0 = 그대로). top 은 굴리기 전 문서 기준 — 창이 문서와 함께 움직이니 굴린 뒤에도 맞다 */
  scrollBy: number;
}

/**
 * 창 자리.
 * 가로: 방아쇠 왼쪽 맞춤 → 오른쪽 화면 끝(16px)을 넘으면 방아쇠 오른쪽 끝 맞춤(메뉴바) → 화면 안 16px 클램프.
 * 세로: 줄(또는 방아쇠) 아래 10px. 아래에 다 안 들어가고 위(천장 = 메뉴바 아래 8px)에는 다 들어가면 위로 뒤집는다.
 *       어느 쪽에도 다 안 들어가면(낮은 노트북 창 657–713 에서 페이지 끝 아웃트로 — 창 313px) 문서 기준 창은 덜 굴리는 쪽으로 열고
 *       모자란 만큼 페이지를 굴린다(scrollBy): 위 = 끝까지 굴릴 수 있을 때만(덜 굴리면 메뉴바 밑으로 들어간다) · 아래 = 굴릴 수 있는 만큼
 *       (페이지 끝이면 창이 늘린 문서만큼 — 화면 아래끝에 닿는다). 굴린 뒤 창은 천장 아래 · 바닥 위 · 줄과 겹치지 않는다.
 *       굴려도 안 되면(창 + 간격 + 줄 > 천장~바닥 — 가로로 눕힌 폰 412) · 메뉴바(fixed) · docHeight 없음 = 아래 그대로(스크롤로 마저 본다).
 *       위로 열어 메뉴바·화면 위끝을 넘는 일은 없다.
 */
export function computePlacement(i: PlaceInput): Placement {
  const t = i.trigger;
  const row = i.row ?? t;
  const { width: pw, height: ph } = i.pop;
  const { width: vw, height: vh } = i.viewport;

  let left = t.left;
  let align: Placement['align'] = 'left';
  if (left + pw > vw - EDGE) {
    left = t.right - pw;
    align = 'right';
  }
  left = Math.max(EDGE, Math.min(left, vw - EDGE - pw));

  const ceiling = Math.max(EDGE, i.navH + 8);
  const floor = vh - EDGE;
  const rowTop = Math.min(t.top, row.top);
  const rowBottom = Math.max(t.bottom, row.bottom);
  const belowTop = rowBottom + GAP;
  const aboveTop = rowTop - GAP - ph;
  /** > 0 = 그쪽으로 열면 모자란 양(px) */
  const needDown = belowTop + ph - floor;
  const needUp = ceiling - aboveTop;

  let side: Placement['side'] = 'below';
  let scrollBy = 0;
  if (needDown <= 0) side = 'below';
  else if (needUp <= 0) side = 'above';
  else if (!i.fixed && i.docHeight !== undefined && ph + GAP + (rowBottom - rowTop) <= floor - ceiling) {
    const roomUp = Math.max(0, i.scroll.y);
    // 아래로 열면 창이 문서를 늘린다(문서 기준 absolute) — 페이지 끝에서도 그만큼은 굴릴 수 있다
    const roomDown = Math.max(0, Math.max(i.docHeight, i.scroll.y + belowTop + ph) - vh - i.scroll.y);
    const up = Math.ceil(needUp);
    const down = Math.ceil(needDown);
    if (up <= roomUp && (up <= down || down > roomDown)) {
      side = 'above';
      scrollBy = -up;
    } else {
      scrollBy = Math.min(down, Math.floor(roomDown));
    }
  }
  let top = side === 'above' ? aboveTop : belowTop;

  if (!i.fixed) {
    top += i.scroll.y;
    left += i.scroll.x;
  }
  return { top: Math.round(top), left: Math.round(left), side, align, scrollBy };
}

/** 창 안 Tab 순환: 지금 포커스 위치(current, 창 밖이면 −1)에서 다음(back = Shift+Tab) 항목. 항목이 없으면 −1 */
export function nextFocusIndex(count: number, current: number, back: boolean): number {
  if (count <= 0) return -1;
  if (current < 0 || current >= count) return back ? count - 1 : 0;
  return (current + (back ? count - 1 : 1)) % count;
}

function asAsset(x: unknown): ReleaseAsset | null {
  if (!x || typeof x !== 'object') return null;
  const a = x as Record<string, unknown>;
  if ((a.name !== 'aing-check.dmg' && a.name !== 'aing-check.zip') || typeof a.bytes !== 'number' || typeof a.mb !== 'string') return null;
  return { name: a.name, url: typeof a.url === 'string' ? a.url : '', bytes: a.bytes, mb: a.mb };
}

/** /api/release JSON → ReleaseInfo(모양이 이상하면 null — 부르는 쪽이 RELEASE_FALLBACK 으로) */
export function asRelease(x: unknown): ReleaseInfo | null {
  if (!x || typeof x !== 'object') return null;
  const r = x as Record<string, unknown>;
  if (typeof r.version !== 'string' || !r.version) return null;
  return {
    version: r.version,
    publishedAt: typeof r.publishedAt === 'string' ? r.publishedAt : null,
    dmg: asAsset(r.dmg),
    zip: asAsset(r.zip),
    source: r.source === 'github' ? 'github' : 'fallback',
  };
}
