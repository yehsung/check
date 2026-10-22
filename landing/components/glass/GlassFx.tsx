'use client';
// components/glass/GlassFx.tsx — 서버 컴포넌트 안의 유리 판에 움직임을 붙이는 보이지 않는 조각(client 섬).
// 부모 요소(= 유리 판)에 포인터 스페큘러·굴절을 건다. <Glass specular refract> 가 자동으로 넣는다 — 직접 쓸 일은 드물다.
// 클라이언트 컴포넌트에서는 이 조각 대신 usePointerSpecular(ref) · useRefraction(ref) 훅을 쓴다.
import { useEffect, useRef } from 'react';
import { attachPointerSpecular } from './usePointerSpecular';
import { attachRefraction } from './useRefraction';
import type { GlassLevel, RefractOptions } from './refraction';

export interface GlassFxProps {
  specular?: boolean;
  refract?: boolean | RefractOptions;
  /** 첫 등장 응결(굴절 세기 강 → 보통) */
  entrance?: boolean;
  level?: GlassLevel;
}

export function GlassFx({ specular = false, refract = false, entrance = false, level }: GlassFxProps) {
  const ref = useRef<HTMLSpanElement>(null);
  const r = typeof refract === 'object' ? refract : null;
  const on = !!refract;
  const band = r?.band;
  const scale = r?.scale;
  const aberration = r?.aberration;
  const rimBlur = r?.rimBlur;

  useEffect(() => {
    const host = ref.current?.parentElement;
    if (!host || !specular) return;
    return attachPointerSpecular(host);
  }, [specular]);

  useEffect(() => {
    const host = ref.current?.parentElement;
    if (!host || !on) return;
    return attachRefraction(host, { level, band, scale, aberration, rimBlur, entrance });
  }, [on, level, band, scale, aberration, rimBlur, entrance]);

  return <span ref={ref} hidden data-glass-fx="" />;
}

export default GlassFx;
