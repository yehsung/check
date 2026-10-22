'use client';
// 탭이 숨으면 <html data-tab-hidden> → globals.css 가 오로라 표류(animation)를 멈춘다. 아무것도 그리지 않는다.
import { useEffect } from 'react';

export function AuroraPause() {
  useEffect(() => {
    const root = document.documentElement;
    const sync = () => {
      if (document.visibilityState === 'hidden') root.setAttribute('data-tab-hidden', '');
      else root.removeAttribute('data-tab-hidden');
    };
    sync();
    document.addEventListener('visibilitychange', sync);
    return () => {
      document.removeEventListener('visibilitychange', sync);
      root.removeAttribute('data-tab-hidden');
    };
  }, []);
  return null;
}

export default AuroraPause;
