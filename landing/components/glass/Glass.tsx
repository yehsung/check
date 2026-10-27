// components/glass/Glass.tsx — 유리 판(docs/v3/brief.md §3). 서버·클라 어디서나(훅 없음).
// <Glass level="regular" as="section" className="p-8">…</Glass>
//   level    thin(메뉴바·칩·알약) | regular(터미널·FAQ·세그먼트·설치 카드, 기본) | thick(히어로 팝오버·기능 무대 베젤)
//   radius   모서리(px 숫자 또는 CSS 길이) — 기본은 단계 값(thin 999 · regular 22 · thick 30)
//   tint     글 많은 판의 대비 보험(짙은 바닥색 .38)
//   specular 포인터 스페큘러(pointer:fine · 감속 아님일 때만 움직인다)
//   refract  가장자리 굴절(데스크톱 Chromium 만, 나머지는 blur 폴백). true 또는 { band, scale, aberration, rimBlur }.
//            한 화면에 동시에 보이는 굴절 판은 셋까지(내비 · 히어로 팝오버 · 세그먼트 물방울) — 다른 판에는 켜지 말 것.
//   entrance 굴절 판의 첫 등장 응결(히어로 전용)
// ::before/::after 는 유리가 쓴다(테두리 링·스페큘러). 안쪽 내용은 그 위에 그려지지 않는다(z 3) — 내용이 가장자리까지 차는 판이면
// padding 을 1px 이상 두거나 내용에 z-index 를 주지 말 것.
import type { CSSProperties, HTMLAttributes, ElementType, ReactNode, Ref } from 'react';
import { GlassFx } from './GlassFx';
import type { GlassLevel, RefractOptions } from './refraction';

export type { GlassLevel, RefractOptions } from './refraction';

type GlassTag =
  | 'div' | 'section' | 'article' | 'aside' | 'header' | 'footer' | 'nav' | 'figure' | 'ul' | 'ol' | 'li' | 'span' | 'details' | 'pre';

export interface GlassProps extends HTMLAttributes<HTMLElement> {
  as?: GlassTag;
  level?: GlassLevel;
  radius?: number | string;
  tint?: boolean;
  specular?: boolean;
  refract?: boolean | RefractOptions;
  entrance?: boolean;
  ref?: Ref<HTMLElement>;
  children?: ReactNode;
}

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

/** 유리 판 클래스만 필요할 때(이미 있는 요소에 입히기): className={glassClass('regular')} */
export function glassClass(level: GlassLevel = 'regular', opts: { tint?: boolean } = {}): string {
  return cx('glass', `glass--${level}`, opts.tint && 'glass-tint');
}

export function Glass({
  as = 'div',
  level = 'regular',
  radius,
  tint,
  specular,
  refract,
  entrance,
  className,
  style,
  children,
  ref,
  ...rest
}: GlassProps) {
  const Tag = as as ElementType;
  const st: CSSProperties | undefined =
    radius === undefined
      ? style
      : ({ ...style, '--g-r': typeof radius === 'number' ? `${radius}px` : radius } as CSSProperties);
  return (
    <Tag ref={ref} className={cx(glassClass(level, { tint }), className)} style={st} {...rest}>
      {children}
      {(specular || refract) && <GlassFx specular={!!specular} refract={refract} entrance={entrance} level={level} />}
    </Tag>
  );
}

export default Glass;
