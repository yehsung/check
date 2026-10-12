// lib/media.ts — 영상 형식 고르기·저프레임 판정·이미지 미리 받기·idle(PLAN §3.2 · SPEC §3.4).
// lib/hooks.ts(클라이언트 전용 — React 훅을 import 한다)를 끌어오지 않도록 같은 문자열을 여기 둔다(hooks.ts 의 MQ_PHONE 과 같다).
const MQ_PHONE = '(max-width: 767.98px)';

/** SPEC §3.4: WebKit(사파리·iOS 전부) → HEVC 알파 .mov, 그 밖 → VP9 알파 .webm. 서버에서는 'webm'. */
export function pickVideoFormat(): 'mov' | 'webm' {
  if (typeof navigator === 'undefined') return 'webm';
  const ua = navigator.userAgent;
  const isWebKit = (/AppleWebKit/.test(ua) && !/Chrome|Chromium|Edg|OPR|Android/.test(ua)) || /iP(hone|ad|od)/.test(ua);
  return isWebKit ? 'mov' : 'webm';
}

/** phone 모드 · Save-Data · deviceMemory ≤ 4 → idle 은 15fps 판. */
export function wantsLowFps(): boolean {
  if (typeof window === 'undefined') return false;
  const nav = navigator as Navigator & { connection?: { saveData?: boolean }; deviceMemory?: number };
  const phone = !!window.matchMedia && window.matchMedia(MQ_PHONE).matches;
  const saveData = !!nav.connection?.saveData;
  const lowMem = typeof nav.deviceMemory === 'number' && nav.deviceMemory <= 4;
  return phone || saveData || lowMem;
}

const imageCache = new Map<string, Promise<void>>();

/** new Image + decode. 실패해도 reject 하지 않는다(미리 받기는 최선 노력). 같은 src 는 한 번만. */
export function preloadImage(src: string): Promise<void> {
  if (typeof window === 'undefined' || !src) return Promise.resolve();
  const hit = imageCache.get(src);
  if (hit) return hit;
  const p = new Promise<void>((resolve) => {
    const img = new Image();
    img.decoding = 'async';
    img.src = src;
    const done = () => resolve();
    if (typeof img.decode === 'function') img.decode().then(done, done);
    else {
      img.onload = done;
      img.onerror = done;
    }
  });
  imageCache.set(src, p);
  return p;
}

/** requestIdleCallback, 없으면 setTimeout 200. */
export function idle(fn: () => void): void {
  if (typeof window === 'undefined') return;
  const w = window as Window & { requestIdleCallback?: (cb: () => void, opts?: { timeout: number }) => number };
  if (typeof w.requestIdleCallback === 'function') w.requestIdleCallback(() => fn(), { timeout: 2000 });
  else setTimeout(fn, 200);
}

/** load 이벤트 뒤 requestIdleCallback(SPEC §8.2 의 '2. load + requestIdleCallback'). 취소 함수를 돌려준다. */
export function afterLoadIdle(fn: () => void): () => void {
  if (typeof window === 'undefined') return () => {};
  let cancelled = false;
  const run = () => idle(() => {
    if (!cancelled) fn();
  });
  if (document.readyState === 'complete') {
    run();
    return () => {
      cancelled = true;
    };
  }
  window.addEventListener('load', run, { once: true });
  return () => {
    cancelled = true;
    window.removeEventListener('load', run);
  };
}
