import { PLATFORM_SCRIPT } from "@/lib/platform";

// <head> 인라인 스크립트: 첫 페인트 전에 <html data-platform="mac|ios|other"> (SPEC §8.4).
// 서버 컴포넌트로만 렌더한다(app/layout.tsx 의 <head>).

export function PlatformScript() {
  return <script dangerouslySetInnerHTML={{ __html: PLATFORM_SCRIPT }} />;
}

export default PlatformScript;
