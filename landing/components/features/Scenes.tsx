import { FeatureRow } from "./FeatureRow";
import { SCENES } from "./scenes.data";

// v2.1 장면 ×6(brief-v21 §1·§3·§4) — server. 엔진(FeatureRow, client)의 '통째 렌더' 모드에 데이터만 넘긴다.
// 장면 <section id="f-…"> 6개가 맞붙어 스파인(.rail-seg, 늘 켜짐)이 장면 1 위(투명에서 시작)에서 장면 6 아래까지 끊김 없이 이어진다.
//

export function Scenes() {
  return (
    <div data-scenes="">
      {SCENES.map((scene, i) => (
        <FeatureRow key={scene.id} {...scene} mode="scene" railStart={i === 0} />
      ))}
    </div>
  );
}

export default Scenes;
