# purple → scenes (v2.1) — 클래스 계약

`app/globals.css` 에 정의됨(서빙 확인). `docs/v2/.v21-css-done` 표식.

1. **`.scene-wash`** — 장면 `<section>` 자체에 붙인다(배경 한 장: `radial-gradient(1400px 900px at 62% 50%, rgba(126,94,250,.10), transparent 70%)`). 위치·쌓임·overflow 는 건드리지 않는다. 장면에 불투명 배경(`bg-bg-0` 등)을 함께 깔지 말 것.
2. **`.scene-glow`** — 렌더 영역 상자(46–94% 열, `position:relative` 필요) 안에 빈 `<div className="scene-glow" aria-hidden="true" />` 하나. 그 상자의 가운데에 absolute(`left/top 50%` + `translate -50% -50%`), 지름 `2 × --glow-r`(desk 760 · tab 560 · phone 380), `z-index:-1` 이라 렌더·글자 뒤. 렌더 영역 상자에 `isolation`·`z-index`·불투명 배경을 주면 빛이 상자 안에 갇히거나 가려진다 — 주지 말 것. 전이·`data-glow` 없음(늘 켜짐). 크기를 바꾸고 싶으면 인라인 `--glow-r` 만.
3. **스파인** — `.rail-seg` 는 이제 CSS 가 `background:rgba(126,94,250,.55)` + box-shadow 빛으로 늘 켠다(조립 `scale:1 0` 규칙 삭제). **`components/features/Rail.tsx` 의 인라인 `style={LIT}`(linear-gradient(transparent, .45)) 가 CSS 를 이기므로 `.rail-seg` 에서는 빼 주세요.** 장면 1 위 끝이 흐려지게 하려면 장면 1 의 스파인 요소에 `spine-ext spine-ext--start`(첫 15% 투명 → .55) 를 쓰면 된다. 설치·FAQ 는 `.spine-ext`, 아웃트로는 `.spine-ext--end`(purple 이 유지).
4. **filter: drop-shadow 금지**(verify-final R1). 빛은 box-shadow 또는 의사 요소로.
5. 지울 규칙(.floor-light · `[data-glow]` GlowGate · `.moments-*` · `.seam` · `.tick`) 은 scenes 가 import 를 끊고 `docs/v2/.scenes21-done` 을 남기면 purple 이 지운다. 그 전엔 남겨 둔다.

---

## 완료 뒤 남은 것(purple, 2026-10-12 23:12) — 소유자에게

6. **OG 그림 재촬영(D8 — 통합/리드)**: 히어로 리드가 한 문장이 됐는데 `app/opengraph-image.png`(20:10)는 그 전에 찍혀 옛 리드(두 문장)가 그림에 남아 있다. 하네스 T16 이 `OG 그림이 히어로 카피 뒤에 찍힘` 으로 빨강을 낸다. D8 절차(1440×900 감속 · 내비 제외 · (0, 라벨 위 − 40, 1440, 756) → 1200×630)로 다시 찍으면 초록. alt 문구는 그대로(H1 만 말한다).
7. **`.floor-light`·`[data-glow]` GlowGate 규칙은 남겼다**: `components/features/RowCanvas.tsx` 가 아직 `FloorLight` 를 import 한다(엔진의 row 갈래 — 쓰는 장면 0). scenes(또는 후속 정리)가 import 를 끊으면 globals 의 두 블록을 지운다(주석에 적어 둠). `.moments-*`·`.obj-glow`·`.seam`·`.tick` 은 참조 0 이라 지웠다.
8. **장면별 빛 반지름(globals, purple 이 정함)**: `#f-message` 700 · `#f-rhythm` 720 · `#f-games` 640(desk) — 760 그대로면 V3 15.3 · V5 18.0% 로 상한 15% 를 넘었다. 장면 렌더 배치를 크게 바꾸면 T9 V1–V6 을 다시 재고 이 값만 고친다(SPEC §2.9 v2.1).
9. **보라 기운 ≥ 25% '모든 뷰포트'**: 히어로 18.0% · 아웃트로 9.6% 는 돔 안쪽이 의도된 검정이라 '돔 그대로'와 함께 못 넘는다 → SPEC §2.9 v2.1 · T9 에서 정보로만 기록. 리드 판단 몫.
