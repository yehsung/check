// components/glass/LocalLight.tsx — 절마다 유리 판 뒤에 까는 국소 빛(docs/v3/brief.md §4.1). 서버·클라 어디서나.
// <section className="relative isolate overflow-clip"> <LocalLight tone="violet" x="70%" y="45%" size={1000} /> … </section>
//   tone     violet(기본) | orchid | indigo | rose(아주 작게, 한두 곳만) | ice
//   x, y     중심(부모 기준 CSS 길이, 기본 50% 50%)
//   size     지름(px 숫자 또는 CSS 길이, 기본 900) · aspect 세로/가로(기본 .7)
//   strength 중심 불투명(기본 .32 — rose 는 .2 이하 권장)
// 부모는 position:relative + isolation:isolate 여야 한다(z -1 이 절 밖 오로라 뒤로 빠지지 않게). 가장자리 밖으로 크면 overflow-clip.
import type { CSSProperties } from 'react';

export type LightTone = 'violet' | 'orchid' | 'indigo' | 'rose' | 'ice';

const RGB: Record<LightTone, string> = {
  violet: 'var(--violet-rgb)',
  orchid: 'var(--orchid-rgb)',
  indigo: 'var(--indigo-rgb)',
  rose: 'var(--rose-rgb)',
  ice: 'var(--ice-rgb)',
};

export interface LocalLightProps {
  tone?: LightTone;
  x?: string;
  y?: string;
  size?: number | string;
  aspect?: number;
  strength?: number;
  className?: string;
}

export function LocalLight({ tone = 'violet', x = '50%', y = '50%', size = 900, aspect = 0.7, strength = 0.32, className }: LocalLightProps) {
  const style = {
    '--c': RGB[tone],
    '--a': strength,
    '--x': x,
    '--y': y,
    '--s': typeof size === 'number' ? `${size}px` : size,
    '--ar': aspect,
  } as CSSProperties;
  return <span aria-hidden="true" className={className ? `local-light ${className}` : 'local-light'} style={style} />;
}

export default LocalLight;
