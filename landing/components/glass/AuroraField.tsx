// components/glass/AuroraField.tsx — 바탕 오로라 장(docs/v3/brief.md §4.1). app/layout.tsx 가 한 번 마운트한다(페이지마다 두지 말 것).
// position:fixed 전체 화면 층(z -1): 큰 빛 덩어리 다섯(violet 가장 크게 · orchid · indigo 아래 · violet 왼쪽 · rose 작게) +
// 노이즈 결. 빛은 부드러운 방사 그라디언트(filter:blur 없음), transform 으로 40–70초 주기 표류. 탭 숨김·감속 모션이면 정지.
// 첫 진입에 0–600ms 차오름(.js · 감속 아님 — globals.css). 서버 마크업이라 JS 없이도 보인다.
import type { CSSProperties } from 'react';
import { AuroraPause } from './AuroraPause';

type Blob = { c: string; a: number; x: string; y: string; w: string; h: string; drift: 'aurora-a' | 'aurora-b' | 'aurora-c'; dur: number; delay: number };

/** 1440×900 기준 배치. 오른쪽 위(히어로 팝오버 뒤)가 가장 밝고, 왼쪽 글 열은 덜 밝다(글자 대비). */
const BLOBS: Blob[] = [
  { c: 'var(--violet-rgb)', a: 0.5, x: '66%', y: '34%', w: '92vmax', h: '68vmax', drift: 'aurora-a', dur: 58, delay: -12 },
  { c: 'var(--orchid-rgb)', a: 0.34, x: '92%', y: '8%', w: '54vmax', h: '42vmax', drift: 'aurora-b', dur: 47, delay: -20 },
  { c: 'var(--indigo-rgb)', a: 0.42, x: '20%', y: '96%', w: '86vmax', h: '56vmax', drift: 'aurora-c', dur: 66, delay: -8 },
  { c: 'var(--violet-rgb)', a: 0.24, x: '4%', y: '30%', w: '52vmax', h: '52vmax', drift: 'aurora-b', dur: 53, delay: -31 },
  { c: 'var(--rose-rgb)', a: 0.13, x: '80%', y: '84%', w: '32vmax', h: '24vmax', drift: 'aurora-a', dur: 41, delay: -5 },
];

export function AuroraField() {
  return (
    <div aria-hidden="true" className="aurora" data-aurora="">
      {BLOBS.map((b, i) => (
        <i
          key={i}
          className="aurora__blob"
          style={
            {
              '--c': b.c,
              '--a': b.a,
              '--x': b.x,
              '--y': b.y,
              '--w': b.w,
              '--h': b.h,
              '--drift': b.drift,
              '--dur': `${b.dur}s`,
              '--delay': `${b.delay}s`,
            } as CSSProperties
          }
        />
      ))}
      <AuroraPause />
    </div>
  );
}

export default AuroraField;
