import { FeatureStage } from './FeatureStage';

// 핵심 기능 6장면(docs/v3/brief.md §4.4) — app/page.tsx 가 부르는 이름. 본체는 FeatureStage(client: 고정 무대·세그먼트·흐름 배치).
// 문구 = copy.ts(§8 글자 그대로) · 렌더 구성 = scenes.data.ts · 배치 = features.css(전역 — 이름은 전부 fx-).
export function Scenes() {
  return <FeatureStage />;
}

export default Scenes;
