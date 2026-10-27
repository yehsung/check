// components/glass/GlassDefs.tsx — 굴절 SVG 필터를 둘 자리(app/layout.tsx 가 <body> 끝에 한 번). 보이지 않는 0×0 svg.
// useRefraction 이 요소마다 <filter id="g-refract-N"> 를 이 <defs> 안에 만든다(없으면 스스로 만든다).
// display:none 금지 — 그러면 필터 참조가 끊기는 브라우저가 있다.
export function GlassDefs() {
  return (
    <svg
      id="glass-defs"
      aria-hidden="true"
      focusable="false"
      width="0"
      height="0"
      style={{ position: 'absolute', width: 0, height: 0, overflow: 'hidden', pointerEvents: 'none' }}
    >
      <defs />
    </svg>
  );
}

export default GlassDefs;
