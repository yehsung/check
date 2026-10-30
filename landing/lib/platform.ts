// lib/platform.ts — 첫 페인트 전 플랫폼 판별(SPEC §8.4).
export type Platform = 'mac' | 'ios' | 'other';

/**
 * <head> 인라인 스크립트 원문(≈250B). 첫 페인트 전에 <html data-platform="mac|ios|other"> 를 단다.
 * 규칙: iPhone|iPad|iPod 또는 (Macintosh ∧ maxTouchPoints > 1) → ios, Macintosh|Mac OS X → mac, 그 외 other.
 * 맨 처음에 <html class="js"> 를 붙인다(SPEC v2 §2.7 'JS 없음' — 조립 전·도착 전 같은 '시작 전' 상태는 전부 .js 아래에서만
 * 걸어, JS 가 없으면 모든 절이 최종 상태로 보인다). <html> 의 className 은 React 도 쓰므로 layout 의 suppressHydrationWarning 이 받는다.
 * 덧붙임: 해시로 들어온 첫 로드(/#install)는 브라우저의 조각 스크롤이 html 의 scroll-behavior:smooth 를 타서 맨 위부터
 * 1.4초 동안 굴러 내려가며 모든 절을 차례로 켠다 — load 뒤 두 프레임까지만 auto 로 두고 걷는다(그 뒤 내비 이동은 그대로 부드럽게).
 * 안드로이드(docs/v3/brief.md §12): UA 에 'Android' 가 있으면 <html data-android=""> 를 **덧단다**. data-platform 은 그대로 other —
 * 기존 [html[data-platform=other]_&] 규칙이 깨지지 않게. 폰 첫 화면의 '안드로이드 베타 받기' · 설치 절 안드로이드 카드 맨 앞이 이걸 본다.
 * (데스크톱 모드 안드로이드 크롬은 UA 에 Android 가 없다 — 그때는 그냥 other.)
 */
export const PLATFORM_SCRIPT =
  "(function(){var d=document.documentElement;d.classList.add('js');try{var n=navigator,u=n.userAgent,p=/iPhone|iPad|iPod/.test(u)||(/Macintosh/.test(u)&&n.maxTouchPoints>1)?'ios':/Macintosh|Mac OS X/.test(u)?'mac':'other';d.dataset.platform=p;if(/Android/.test(u))d.dataset.android='';if(location.hash){d.style.scrollBehavior='auto';addEventListener('load',function(){requestAnimationFrame(function(){requestAnimationFrame(function(){d.style.scrollBehavior=''})})},{once:true})}}catch(e){}})();";

/** <html data-platform> 를 읽는다. 서버·스크립트 전에는 'other'. */
export function getPlatform(): Platform {
  if (typeof document === 'undefined') return 'other';
  const p = document.documentElement.dataset.platform;
  return p === 'mac' || p === 'ios' ? p : 'other';
}

/** <html data-android> 가 있으면 true(PLATFORM_SCRIPT 가 단다). 서버·스크립트 전에는 false. */
export function isAndroid(): boolean {
  if (typeof document === 'undefined') return false;
  return document.documentElement.hasAttribute('data-android');
}
