# requests — scenes(v2.1) · 2026-10-12

scenes 가 자기 경로 밖이라 고치지 않은 것. 무엇 · 왜 · 제안.

## 1. 내비 링크 '기능' → `/#f-timer`(core · `data/site-links.ts`)
- 왜: brief-v21 §1 이 `#features` 절을 지웠고, 하네스 T5(`expect.mjs` `GONE_IDS`)가 id `features` 0 을 단언한다. 지금 `NAV_LINKS[0].href` 는 `/#features`.
- 제안 diff: `{ href: "/#features", label: "기능" }` → `{ href: "/#f-timer", label: "기능" }`(SiteNav·LicensesNav 가 같이 쓴다).
- 그동안: `components/features/Scenes.tsx` 맨 앞에 이름 닻 `<a name="features" aria-hidden>`(id 아님 · href 없음 → 포커스 대상 아님 · 글자 0)를 뒀다.
  브라우저 조각 찾기가 id 다음에 `a[name]` 을 봐서 크롬·웹킷 모두 클릭·직접 진입(`/licenses` → `/#features`) 때 장면 1 윗변이 88px(내비 + 24)에 온다(실측).
  링크를 바꾸면 그 닻(`LEGACY_ANCHOR`)을 지운다.

## 2. 하네스 T8(verify) — 장면 id 로
- 옛 `ROWS = [f-message, f-character, f-break, f-ranking, f-iphone]` 중 셋이 사라졌다 → `SCENES`(expect.mjs) 로.
- 엔진 계약은 그대로 남겼다: 루트 `[data-row]`(+ `[data-scene]`) · `data-on` · `data-instant` · `data-reveal-count` · `.node`(라벨 옆, 문턱 = 노드가 68svh — `ROW_TIMING` 값 그대로) · `.wire`(dashoffset) · `[data-row-canvas]` · `.row-item[data-kind=main|child|bubble]` · `#f-message .swap-to`(조립 1.5s 뒤 읽음 판, 180ms).
- (5) '그 행만 `.floor-light[data-glow=on]`' 은 v2.1 에 해당 없음 — 장면 무대 빛 `.scene-glow` 는 늘 켜짐이고 `data-glow` 속성이 없다(brief-v21 §4).

## 3. 이제 쓰는 곳이 0 인 공용 코드(D11 처럼 후속 정리 — 지금은 남김)
- `lib/moments.ts`·`lib/moments.test.ts`·`data/fixtures.ts` `MOMENTS_TIMING`(트립틱 삭제) · `data/figures.ts`(300 숫자 서브셋의 출처로만 남음 — `install-copy.ts` 가 타입만 씀).
- `components/ui/{FloorLight,Tile}.tsx` · `Gridlines lines="left"` · `Rail head` · 엔진의 `mode="row"` 갈래(엔진에 '통째 렌더' 모드를 더한 것이라 row 는 그대로 둠).
- globals: `.moments-*` · `.obj-glow` · `.floor-light` · `[data-glow]` · `.dots` · `.tile` · `.seam` · `.tick` · `.t-number` · `.t-facts*`.

## 4. 글꼴 서브셋
- 새 장면 문장의 음절 6자(격·난·듬·성·얼·찼)가 서브셋 밖이라 `npm run subset` 을 돌렸다 → 500·600 = 370자(한글 267), 25,816 · 25,792B(이전 31,060 · 31,004 — 트립틱·격자 글자가 빠짐). check-glyphs 0.
- purple 이 설치·FAQ 문구에 새 음절을 더하면 한 번 더 돌려야 한다.

## 5. SPEC 갱신 거리(문서 소유자에게)
- §S4 를 v2.1 장면으로: 690 폭 캔버스(1440 렌더 영역 46–94% = 691px, k = min(1, .48·shell/690) — 1024 .71 · tab min(1,(100vw−96)/690)), 장면 높이 max(760, 캔버스 × k + 160), 글 열 세로 가운데, 노드 = 라벨 옆, 선 = 트렁크 1 + 가지 1, 좌표표는 `components/features/scenes.data.ts` 가 정본.
- §6.5 ALT 6줄 추가(`ui/popover-working` · `ui/token-month` · `ui/league` · `ui/message-unread` · `ui/message-read` · `ui/insights-popover`) — fixtures `ALT` 에 넣었다.
- 장면 4 제목은 「12주 잔디, / 지난주 리듬.」(CB:143 ✓v4) — brief-v21 §2 '제목 2박자' + 사용자 원문 '근무 리듬, 잔디'. 하네스 HEADINGS 의 alt 후보와 같다.
