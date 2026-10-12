> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# core — 계약 메모 · PLAN/SPEC 과 다른 점

작성: core 에이전트, 2026-10-12. 계약 파일은 09:04 에 `docs/.contracts-done` 과 함께 나갔고, 그 뒤 **export 서명은 바꾸지 않았다**(아래는 처음부터 PLAN 과 달랐던 점과, 쓰는 쪽이 알아야 할 동작이다). 고칠 사람이 없으면 그대로 두면 된다.

## 1. 타입 위치
- 공유 타입의 **정의는 `lib/demo/reducer.ts`** 에 있다(리듀서 import 0 규칙 — node strip-types 테스트). `lib/demo/types.ts` 는 전부 다시 내보내는 정문이다. 쓰는 쪽은 지금처럼 `@/lib/demo/types` 에서 가져가면 된다.
- 셀렉터(`labelKey`·`capsuleText`·`panelFor`·`isSpineSection`·`spineOpen`·`labelPanel`·`gamesValue`·`sceneOf`)의 본체도 reducer.ts 에 있고 `lib/demo/selectors.ts` 가 다시 내보낸다(테스트가 `./reducer.ts` 하나에서 표 전부를 검사하도록). 추가 export: `SPINE_SECTIONS`, `SECTION_ORDER`, `REACTION_MIN_GAP`.

## 2. SPEC §3.1 · PLAN §3.1 에 더한 것(상위 집합 — 기존 쓰임은 안 깨진다)
- `DemoState.seq: number` — nonce 발급 카운터(반응·말풍선·알림 공용, 단조 증가). 늦게 도착한 `reactionDone(옛 nonce)` 가 새 반응을 지우지 않게.
- `DemoState.ultraPoster: boolean` — `ultraWaitMax`(2500ms) 안에 영상이 준비되지 않아 스토어가 **포스터로 강제 재생**했을 때 true. 울트라 오버레이(stage-corner)는 `ultra === 'playing' && ultraPoster` 면 포스터 + 말풍선을 `reducedUltraMs` 동안 보여 주고 `demo.ultraDone()`.
- `DemoEvent`: `{ type:'HYDRATE'; hidden; installHint }`(sessionStorage 반영), `REACTION_DONE` 에 `now?`, `ULTRA_PLAY` 에 `poster?`.
- 타입 별칭 추가: `BubbleArtId`(= BubbleId | 'ultra-mint' | 'update'), `SpineRect`, `StartedBy`, `TeamView`, `GamesView`, `GrassView`, `TokensView`, `PhoneTab`, `PokeStep`, `FocusLevel`, `MessageStep`, `UltraStep`, `InstallPlacement`, `ReactionPlay`, `BubblePlay`, `DemoOnce`.

## 3. fixtures(SPEC §6)와 다른 점
- **`BubbleId` 는 한 뜻(상태 말풍선 6개)** 으로만 쓴다. SPEC §6 은 fixtures 안에서 같은 이름을 8개짜리로 다시 정의했는데, 그러면 `@/lib/demo/types` 의 BubbleId 와 이름이 같고 값이 달라진다. 그래서 8개짜리는 `BubbleArtId` 로 두고 `BUBBLE_TEXT: Record<BubbleArtId, …>`. 문구·지속 시간은 SPEC 그대로.
- `AssetKey` 는 손으로 적은 유니언(DECISIONS §4) — SPEC §9 출력 전부(영상 기본 이름 `char/aing-*` 포함, 메타는 sequences.json 에만).
- `asset(k)` 는 **`AssetMeta | undefined`** 를 돌려준다(assets.json 이 `{}` 이거나 키가 없을 수 있다 — DECISIONS §4). `AssetMeta = { src; w; h; bytes }` 도 export.
- `SequenceName`(PLAN §3.5)도 fixtures 에서 export. `HotspotKey = keyof typeof HOTSPOTS`, `HotspotSpec` 추가.
- `RELEASE_FALLBACK`·`ReleaseInfo`·`ReleaseAsset` 의 **정의는 fixtures**(클라 번들이 서버 fetch 코드를 끌어오지 않게), `lib/release.ts` 가 다시 내보낸다. PLAN §3.7 의 `ReleaseInfo` 모양에 맞추려고 폴백에 `url`(latest/download 주소)·`publishedAt: null` 을 채웠다.

## 4. 리듀서 동작 메모(SPEC 표에 없던 결정)
- `SET_AUTO_PASSED` 의 반응·자동 시작은 **activeSection === 'auto' 일 때만**. `/#team` 처럼 해시로 건너뛰어 표지가 처음부터 중앙선 위에 있으면 값(라벨)만 바뀌고 반응은 없다.
- `SET_SECTION` 은 같은 id 면 아무것도 안 한다(activeBeat 를 지우지 않는다).
- `HIDE_CORNER`: `hidden=true` 를 **바로** 세우고 commute_end 반응을 건다(말풍선·할 일 보드 닫힘). 코너는 `!hidden || reaction?.id ∈ {commute_end, poked}` 동안 그리면 "꾸벅 후 사라짐"과 "숨김 중 poked 만 잠깐 보임"이 둘 다 맞는다.
- `TOGGLE_TODO` 로 열 때 숨김이면 `hidden=false` 로 되돌린다(S7 버튼 규칙). `force` 는 열기/닫기 지정.
- `MSG_OPEN` 은 떠 있는 `message-gureum` 말풍선을 걷는다.
- 반응 큐: commute_end 는 간격이 지나도 끊기지 않는다 → 그동안 온 반응(예: 빠른 RESTART 의 commute_start)은 pending 이었다가 commute_end 가 끝나면 재생.
- 알림 문장은 리듀서가 아니라 스토어가 이벤트 종류로 고른다(`ANNOUNCE` 상수 한 곳): PRESS_START·AUTO_START(+표지1 자동 시작)·POKE_IN·ULTRA_PLAY·CYCLE_FOCUS·MSG_ARRIVE·MSG_SEND·MSG_READ·PRESS_END·RESTART.

## 5. 스토어(`lib/demo/store.ts`)
- 추가 export: `subscribeDemo(listener)`(컴포넌트 밖 구독), `type Demo`.
- `useDemo(selector)` 는 상태 단위로 결과를 기억한다 — selector 가 새 객체를 돌려줘도 무한 렌더가 나지 않는다. 서버·하이드레이션 중에는 `initialState(false,false)`.
- sessionStorage 는 첫 구독 뒤 마이크로태스크에서 읽는다(OR 병합 — 하이드레이션 전에 누른 것도 산다).
- 보험 타이머: 반응 6초·말풍선 `BUBBLE_TEXT.ms + 1.5초`·울트라 재생 9초가 지나도 끝 알림이 없으면 스토어가 스스로 비운다(그리는 쪽이 없는 폭에서 대기열이 막히지 않게). 그리는 쪽은 지금처럼 `reactionDone/bubbleDone/ultraDone` 을 부르면 된다.
- 알림 큐: 문장 사이 최소 1000ms.
- `ultraIn()` 은 내부 단계(pokeBack 이 1000ms 뒤 부른다)라 `demo` 에 없다.

## 6. 훅·유틸
- `lib/hooks.ts` 는 **클라이언트 전용**(React 훅을 import 한다). 서버 컴포넌트에서 import 하면 Next 가 빌드를 막는다 — 서버 쪽 분기는 CSS 변형(`desk:`·`tab:`·`phone:`)으로. 추가 export: `MQ_REDUCED`, `useSaveData`, `viewportModeNow()`, `saveDataNow()`.
- `useCenterLine` 은 루트 = "화면 위 아주 먼 곳 ~ 중앙선"이라 빠르게 표지를 건너뛰어도 바뀐다. dwell 은 앞으로(true) 지날 때만, 거꾸로(false)는 바로.
- `useInViewRatio` 는 요소가 뷰포트보다 크면 "뷰포트의 ratio 를 채움"도 보임으로 친다.
- `lib/media.ts` 는 hooks.ts 를 import 하지 않는다(MQ_PHONE 같은 문자열을 자체로 둠) — 서버에서 import 해도 안전.

## 7. 전역 CSS(`app/globals.css`)
- SPEC §2.8 그대로 + `.t-*` 16개(§2.3 표 전부 — 본문엔 "14개"라 적혀 있지만 표에는 16행) `@layer components` + `.sr-only`.
- **플랫폼 CTA**: `.cta-mac` / `.cta-ios` / `.cta-other` 를 `<html data-platform>` 으로 하나만 보이게 하는 규칙을 층 밖에 넣었다(data-platform 이 없으면 Mac 판). DownloadCTA 는 클래스만 달면 된다.
- 움직임 도우미(모두 `prefers-reduced-motion: no-preference` 안): `.anim-spine-drop`(150ms 지연, 불투명 120 선형 + 이동 180 ease-out), `.anim-hotspot-pulse`(700ms 1회 — **지연 없음**, 1200ms 시점에 클래스를 붙이거나 `animation-delay` 를 주라), `.anim-label-glow`(600ms 1회), `summary.disclosure`(▸ 삼각형 `::after`, `details[open]` 에서 90°, 전이 180ms ease-out).
- Tailwind 기본 테마의 `--ease-out` 은 층 안이라 우리 `:root` 값(cubic-bezier(.2,.8,.2,1))이 이긴다(빌드 CSS 로 확인).

## 8. 레이아웃·라우트
- `components/ui/PlatformScript` 가 이미 있어서 그걸 `<head>` 에 넣었다. `<html suppressHydrationWarning>`(스크립트가 data-platform 을 먼저 단다).
- 스마트 배너는 `metadata.itunes.appId` 로 낸다 → `<meta name="apple-itunes-app" content="app-id=6812768622"/>`(빌드 HTML 확인).
- `metadataBase` 폴백은 `http://localhost:3000`(DECISIONS §2 — SPEC 의 3210 대신). `NEXT_PUBLIC_SITE_URL` 이 빈 문자열이어도 폴백.
- `viewport`: `themeColor '#12131C'`, `colorScheme 'dark'`.
- `/api/release` 는 빌드에서 ○(1h ISR)로 나온다. `/api/download` 는 ƒ.

## 9. tsconfig · eslint
- `allowImportingTsExtensions: true` 추가(테스트가 `./reducer.ts` 를 import).
- `eslint.config.mjs` 의 globalIgnores 에 `.scratch/**` 추가 — `eslint .` 가 다른 에이전트의 임시 번들(`.scratch/primitives-a/out/*.js`, `.scratch/primitives-b/verify.cjs`)까지 읽어 30 errors 로 빨갛게 나왔다(flat config 는 .gitignore 를 따르지 않는다).
