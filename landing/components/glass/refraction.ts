// components/glass/refraction.ts — 유리 가장자리 렌즈(굴절)의 순수 함수 + 기능 감지(docs/v3/brief.md §3 '굴절').
// import 0 — node --experimental-strip-types 로 바로 테스트한다(refraction.test.ts).
//
// 방식: 요소 크기에 맞춘 변위 맵(R = x 변위, G = y 변위, 128 = 0)을 그려 SVG <feImage> 로 넣고,
//   backdrop-filter: url(#필터) saturate() 로 건다. 필터 안에서
//     · 서리(frost) = 뒤 그림을 단계 blur(18/28/36)로 흐린 것 — 가운데
//     · 렌즈(lens)  = 살짝만 흐린 뒤 그림을 맵대로 안쪽에서 끌어온 것, RGB 채널마다 scale 을 조금씩 달리해 미세 색수차
//     · 테두리 무게(B 채널)로 렌즈를 가장자리에만 얹는다(렌즈 in rim → over 서리).
//   그래서 가장자리 띠(band px)에서만 뒤 글자·빛이 휘고 색이 갈리며, 가운데는 평범한 서리 유리다.
// 데스크톱 Chromium 에서만 쓴다(canRefract). WebKit 은 CSS.supports('backdrop-filter','url(#a)') 가 true 인데
//   그리지는 못한다(실측 — 판 전체가 투명해진다). 그래서 navigator.userAgentData(Chromium 계열에만 있다)로 가른다.

export type GlassLevel = 'thin' | 'regular' | 'thick';

export interface RefractOptions {
  /** 렌즈 띠 폭(px, 가장자리에서 안쪽으로) */
  band?: number;
  /** 변위 세기(px) — 가장자리에서 띠 안쪽 내용을 이만큼까지 끌어온다 */
  scale?: number;
  /** 색수차(0–.2): G·B 채널 scale 을 (1 − a)·(1 − 2a) 배로 */
  aberration?: number;
  /** 렌즈 쪽에만 거는 약한 blur(px) */
  rimBlur?: number;
}

export const REFRACT_DEFAULTS: Record<GlassLevel, Required<RefractOptions>> = {
  thin: { band: 12, scale: 30, aberration: 0.08, rimBlur: 0.6 },
  regular: { band: 18, scale: 46, aberration: 0.08, rimBlur: 0.9 },
  thick: { band: 26, scale: 64, aberration: 0.09, rimBlur: 1.1 },
};

/** 단계별 서리 blur(px) — globals.css 의 --g-blur 와 같은 값(요소에서 못 읽을 때 쓴다). */
export const FROST_BLUR: Record<GlassLevel, number> = { thin: 18, regular: 28, thick: 36 };

export interface EdgeMap {
  /** 맵 픽셀 크기(요소 크기 / k, 반올림) */
  w: number;
  h: number;
  /** RGBA, 길이 w·h·4 */
  data: Uint8ClampedArray;
}

/**
 * 둥근 사각형(W×H CSS px, 모서리 radius)의 가장자리 변위 맵. k = 축소 배율(2 → 절반 해상도 — 맵이 매끄러워 늘려도 티가 안 난다).
 * 픽셀마다: d = 안쪽 거리(px), t = clamp(d/band), m = (1 − t)² (가장자리 1 → 띠 안쪽 0),
 *   n = 안쪽 법선(단위 벡터) → R = 128 + 127·m·nx, G = 128 + 127·m·ny, B = 255·(1 − t)^1.15(렌즈 무게), A = 255.
 * 띠 안쪽(가운데)은 정확히 (128, 128, 0) — 변위 0, 렌즈 무게 0. 순수 함수.
 */
export function edgeMap(W: number, H: number, radius: number, band: number, k = 2): EdgeMap {
  const w = Math.max(2, Math.round(W / k));
  const h = Math.max(2, Math.round(H / k));
  const data = new Uint8ClampedArray(w * h * 4);
  const hw = W / 2;
  const hh = H / 2;
  const r = Math.max(0, Math.min(radius, hw, hh));
  const b = Math.max(1, band);
  for (let j = 0; j < h; j++) {
    const py = ((j + 0.5) * H) / h - hh;
    for (let i = 0; i < w; i++) {
      const px = ((i + 0.5) * W) / w - hw;
      const qx = Math.abs(px) - (hw - r);
      const qy = Math.abs(py) - (hh - r);
      const ox = Math.max(qx, 0);
      const oy = Math.max(qy, 0);
      const lo = Math.hypot(ox, oy);
      const dist = lo + Math.min(Math.max(qx, qy), 0) - r; // 안쪽 음수
      let nx: number;
      let ny: number;
      if (qx > 0 && qy > 0 && lo > 0) {
        nx = ox / lo;
        ny = oy / lo;
      } else if (qx > qy) {
        nx = 1;
        ny = 0;
      } else {
        nx = 0;
        ny = 1;
      }
      // 바깥 법선 → 안쪽 법선(사분면 부호를 뒤집는다)
      nx *= px > 0 ? -1 : px < 0 ? 1 : 0;
      ny *= py > 0 ? -1 : py < 0 ? 1 : 0;
      const t = Math.min(1, Math.max(0, -dist / b));
      const m = (1 - t) * (1 - t);
      const o = (j * w + i) * 4;
      data[o] = Math.round(128 + 127 * m * nx);
      data[o + 1] = Math.round(128 + 127 * m * ny);
      data[o + 2] = Math.round(255 * Math.pow(1 - t, 1.15));
      data[o + 3] = 255;
    }
  }
  return { w, h, data };
}

/** 렌즈 필터 원시 요소(문자열). 맵 주소·크기·세기를 받는다. 순수 함수 — GlassFx 가 <filter> 안에 넣는다. */
export function filterMarkup(o: {
  mapHref: string;
  width: number;
  height: number;
  frost: number;
  scale: number;
  aberration: number;
  rimBlur: number;
}): string {
  const s = (v: number) => (Math.round(v * 100) / 100).toString();
  const sr = o.scale;
  const sg = o.scale * (1 - o.aberration);
  const sb = o.scale * (1 - 2 * o.aberration);
  const disp = (scale: number, res: string) =>
    `<feDisplacementMap in="soft" in2="map" scale="${s(scale)}" xChannelSelector="R" yChannelSelector="G" result="${res}"/>`;
  return [
    `<feImage href="${o.mapHref}" x="0" y="0" width="${s(o.width)}" height="${s(o.height)}" preserveAspectRatio="none" result="map"/>`,
    `<feGaussianBlur in="SourceGraphic" stdDeviation="${s(o.frost)}" edgeMode="duplicate" result="frost"/>`,
    `<feGaussianBlur in="SourceGraphic" stdDeviation="${s(o.rimBlur)}" edgeMode="duplicate" result="soft"/>`,
    disp(sr, 'dr'),
    `<feColorMatrix in="dr" type="matrix" values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0" result="cr"/>`,
    disp(sg, 'dg'),
    `<feColorMatrix in="dg" type="matrix" values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0" result="cg"/>`,
    disp(sb, 'db'),
    `<feColorMatrix in="db" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0" result="cb"/>`,
    `<feBlend in="cr" in2="cg" mode="screen" result="crg"/>`,
    `<feBlend in="crg" in2="cb" mode="screen" result="lens"/>`,
    `<feColorMatrix in="map" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 1 0 0" result="rim"/>`,
    `<feComposite in="lens" in2="rim" operator="in" result="lensrim"/>`,
    `<feComposite in="lensrim" in2="frost" operator="over"/>`,
  ].join('');
}

/** 감속 없는 스프링 비슷한 이징(응결 연출용): 0 → 1, 살짝 넘쳤다 돌아온다. 순수 함수. */
export function easeOutBack(t: number): number {
  const c1 = 1.4;
  const c3 = c1 + 1;
  const x = Math.min(1, Math.max(0, t)) - 1;
  return 1 + c3 * x * x * x + c1 * x * x;
}

type UADataLike = { mobile?: boolean; brands?: { brand: string }[] };

/**
 * 굴절을 켜도 되는가(브라우저에서만 의미). 조건: 데스크톱 Chromium(navigator.userAgentData 가 있고 mobile 아님)
 * · 정밀 포인터 · 폭 ≥ 1024 · 투명도 줄이기 아님 · CSS 가 backdrop-filter url() 을 받는다.
 * Safari·Firefox·모바일·서버는 false → blur 폴백.
 */
export function canRefract(): boolean {
  if (typeof window === 'undefined' || typeof navigator === 'undefined' || !window.matchMedia) return false;
  const uad = (navigator as Navigator & { userAgentData?: UADataLike }).userAgentData;
  if (!uad || uad.mobile) return false;
  if (Array.isArray(uad.brands) && uad.brands.length > 0 && !uad.brands.some((b) => /Chrom|Edge|Opera|Brave/i.test(b.brand))) {
    return false;
  }
  if (!window.matchMedia('(pointer: fine) and (min-width: 1024px)').matches) return false;
  if (window.matchMedia('(prefers-reduced-transparency: reduce)').matches) return false;
  return typeof CSS !== 'undefined' && typeof CSS.supports === 'function' && CSS.supports('backdrop-filter', 'url(#a) saturate(1)');
}
