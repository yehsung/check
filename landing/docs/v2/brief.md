# 아잉체크 랜딩 v2 — 재설계 브리프 (디자인 리드 → 설계 워크플로)

작성 2026-10-12 16:05 KST · 작성자: 메인 오케스트레이터(디자인 리드)
상태: **v1(`docs/SPEC.md`, 2026-10-12 오전 완성)은 사용자가 거부했다.** 이 문서가 v2 의 출발점이고, 설계 워크플로가 이 문서에서 `docs/v2/SPEC.md`·`docs/v2/PLAN.md` 를 만든다.
v1 전체 스냅숏: `landing/.scratch/landing-v1-2026-10-12.tgz`(node_modules·.next 제외). 되돌릴 일이 있으면 여기서.

---

## 0. 사용자의 말(원문, 2026-10-12 15:50)

> 지금 랜딩페이지 마음에 안들어.
> 일단 웹에서 체험해볼 수 있는기능은 빼버려. 지저분해. 그리고 너무 다크하게만이 아니라 다크와 보라색 색감의 조화가 있길 원해
> https://pin.it/35v5m4ly9 여기를 참고해봐.
> 스크롤에 따라 어떻게 바뀌는지 다 드러나는 영상 이니까 영상 전체를 읽고 참고해

세 가지 요구로 읽는다. **이 셋은 협상 대상이 아니다.**
1. **체험(인터랙티브 데모) 전면 제거.** 라벨에 매달린 팝오버 스파인, 렌더 위 핫스팟, 세그먼트로 패널 바꾸기, 플레이 가능한 게임 창, 할 일 보드, 코너 아잉 상태 기계, 근무 시작/종료 버튼 흉내 — 전부 뺀다. 페이지는 **보여 주는** 페이지다. 방문자가 하는 일은 읽기·스크롤·다운로드뿐이다.
2. **다크 + 보라의 조화.** v1 은 네이비 무채색 바탕에 라벤더 버튼 하나였다("너무 다크하게만"). v2 는 검정에 가까운 보랏빛 밤을 바탕으로, **보라를 빛으로** 쓴다(테두리 발광·그라디언트·연결선·아이콘 타일). 아잉의 라벤더(#C9B8FF)는 이 가족의 색이라 자연스럽다.
3. **레퍼런스 영상의 스크롤 안무를 참고.** §2 에 35초 전체를 프레임 단위로 읽어 적었다. 복제가 아니라 안무·분위기의 참고다(§3 에 "가져오지 않는 것"도 적었다).

이전 세션의 지시도 그대로 산다: 모든 서브에이전트 Opus xhigh, 커밋·배포 금지(둘 다 사용자 몫), `Sources/`·`Tests/` 등 저장소의 다른 변경은 절대 건드리지 않음, 데브 서버 `http://localhost:3000` 에서 결과 확인.

---

## 1. 제품 사실(변하지 않은 것 — v1 정본에서 승계)

- 제품: **아잉체크(aing-check)** — 작은 Mac 팀을 위한 메뉴바 근무 타이머 + 아이폰 앱. 근무 시작을 누르면 팀 전체에 바로 보인다. 근무 중엔 고른 캐릭터(아잉)가 화면 구석에 산다. 콕 찌르기·울트라·1:1 메시지·미니게임·오목·체스·캐릭터·루비·할 일·12주 잔디·AI 토큰·아이폰 앱·위젯.
- 다운로드: 1차 CTA = DMG(`/api/download` → GitHub 최신 릴리스 302, 현재 **v0.3.49**(2026-10-12 18:06 KST 배포) `aing-check.dmg` **30,054,068B = 30.1MB** · `aing-check.zip` 28,343,288B — 화면 값은 `getRelease()` 서버 렌더, `RELEASE_FALLBACK` 도 이 값으로). 보조 = App Store(id6812768622), brew(`brew install yehsung/check/aing-check`).
- **업데이트 사실(0.3.49 · 커밋 3545607, 2026-10-12 17:59)**: DMG 로 설치한 앱도 앱 안 [지금 업데이트] 한 번으로 새 DMG 를 받아 공증·서명 신원·버전을 검증한 뒤 자기 번들을 교체하고 다시 켜진다(brew 가 관리하는 번들만 brew 경로). 따라서 랜딩의 업데이트 문장은 설치 경로를 가르지 않는다: **「새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. 지금 업데이트 한 번이면 설치하고 다시 켜져요.」** v1 S11 의 "DMG 로 받았다면 새 DMG 를 받아 덮어쓰면 돼요" 는 **폐기**(0.3.48 이하 DMG 설치자의 과도기 안내는 docs/team-install.md 몫). brew 업데이트 명령은 `brew update && brew upgrade --cask aing-check`.
- **사실 규칙은 v1 `docs/SPEC.md` §1.4 를 그대로 승계한다**(금지어·가상 인물 세트·렌더 덧그리기 금지·쓰지 않는 소재). 카피 정본은 `docs/content-brief.md`(헤드라인 후보·본문·출처·금지 목록 §9·용어 §10). 소재 실측은 `docs/asset-manifest.md`. 현재 내보낸 에셋은 `public/assets/{ui,char,ios,brand}`(74개, 목록은 §6).
- 숫자 규칙 추가: 레퍼런스의 "In Numbers" 를 들여올 때 **사용자 수·별점·거래량 같은 지표는 쓰지 않는다**(사실 규칙). 쓸 수 있는 숫자는 **제품 사실**뿐이고 각 숫자에 출처(content-brief 줄 번호 또는 README)를 단다. 후보: 무료(0원) · macOS 14 이상 · DMG 30.1MB(v0.3.49, 화면 값은 서버 렌더) · 12주 잔디 · 미니게임 3종 + 오목·체스 · 1:1 메시지 · 위젯 2종(오늘·할 일) · 근무 시작 1번. 검증 안 되는 숫자는 뺀다.

---

## 2. 레퍼런스 영상 읽기 (pin.it/35v5m4ly9 → Sellix 랜딩, Framer 제작, 35.1초, 720×540 30fps)

프레임 72장(0.5초 간격)과 접촉 시트가 `/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/pin/{frames,sheets}/` 에 있다(세션 한정, 저장소에 넣지 말 것 — 남의 디자인이다). 아래는 리드가 전부 읽고 적은 것.

### 2.1 장면 순서(타임코드)

| 시간 | 장면 | 레이아웃 · 움직임 |
|---|---|---|
| 0.0–8.5s | **히어로** | 가운데 정렬. 흰 큰 헤드라인 "Cross-border finance"(기하학적 산세리프, 2줄) · 작은 리드 3줄 · 알약 버튼 둘(흰 채움 "Get Started →" + 테두리 "Contact Sales →"). 뒤에는 화면 아래에서 솟은 **거대한 돔(행성)**: 어두운 구체에 **보라 발광 테두리**(대기권 글로우), 구체 표면은 보라 점으로 찍은 세계지도, 위쪽은 별밭. 돔 표면 위로 **빛줄기가 호를 그리며 이동**하고 그 끝에 작은 알림 카드("0.1 BTC sent to Janet", "Product Bought 1.2 SOL")가 떠오른다. 지도 위 도시들이 보라로 번쩍인다. 내비: 로고 왼쪽, 링크 가운데, 오른쪽 "Login" + 흰 알약 "Get Started". |
| 8.5–9.5s | 로고 띠 | 결제 수단 로고 한 줄(PayPal·Cash App·bitcoin…), 회백색. |
| 9.5–15.5s | **큰 숫자 트립틱(가로 스크럽)** | 섹션이 고정되고 스크롤이 **가로 이동**으로 바뀐다. 각 장: 왼쪽 위 거대한 숫자 + 두 줄 설명("100x / cheaper than traditional payments" → "5x / faster than credit cards" → "100% / global cross-border availability"), 가운데 **3D 오브젝트**(저울 위 동전·발광 보라 셰브론과 VISA 카드·보라 지구본), 오른쪽 아래 작은 단락, 왼쪽 아래 `[ 01 / 03 ]` 카운터(진짜 순서). 배경에 세로 헤어라인 격자가 희미하게. 다음 장의 숫자가 아래/오른쪽에서 미리 보인다. |
| 15.5–17.5s | 기능 절 제목 | 가운데 정렬 h2 "End-to-end universal payment solution for cryptocurrencies and fiat", 그 위 작은 알약 눈썹 "BRIDGING WEB2 AND WEB3", 아래 한 줄 서브. |
| 17.5–28.0s | **기능 행 ×4 (왼쪽 스파인)** | 왼쪽 가장자리에 **세로 선(타임라인)**이 흐르고 행마다 작은 사각 아이콘 노드. 각 행: 카테고리 라벨(소문자 "Wallet"·"Payments"·"Commerce"·"Subscriptions") → h3("Secure Crypto Management"·"Fast, Secure, Global"·"Empower Your Store"·"Automate Revenue") → 단락 → 테두리 알약 "Learn more ›". 오른쪽은 **목업이 조립되며 등장**: 지갑 대시보드(차트 + 거래 목록이 차례로 나타남), 주문 영수증 카드에서 **보라 연결선이 그려져** 결제 수단 카드 셋으로 갈라짐, 스토어 대시보드 창이 **보라 그라디언트 앱 아이콘 타일**과 가는 보라 선으로 이어짐, 구독 카드 둘. 목업 뒤에는 점 격자(dot grid). 목업 안에서 커서가 클릭하고 창이 열리는 연출도 있다. |
| 28.0–30.0s | **숫자 격자 "In Numbers"** | 왼쪽에 제목, 오른쪽 4×2 격자. 칸마다 작은 아이콘 + 라벨 위, 큰 숫자 아래("35+ · 60M+ · 25+ · 100M+ / 8.2M+ · 3.2M+ · 350K+ · 3.5K+"). 칸 사이는 헤어라인. |
| 30.0–35.0s | **아웃트로** | 검정 바탕에 브랜드 마크 "S" 애니메이션: 보라 반투명 S 주위로 흰 화살표 둘이 돌고 코인 아이콘이 궤도를 돈다. 루프 두 번 뒤 검정. |

### 2.2 색(프레임 픽셀 실측, sharp)

- 바탕: `#111111`(가장 많음) ~ `#111122`(히어로에서 보라 기운). 순검정이 아니라 **아주 어두운 회색/보라 밤**.
- 보라: 발광 중앙값 `#8434E6`, 밝은 꼬리(p90) `#DA84FF`, 가장 밝은 심 `#FDD6FF`(거의 흰 라일락), 어두운 끝 `#4C17B7`. 즉 **채도 높은 바이올렛이 검정 위에서 빛으로** 쓰인다. 평평한 보라 면은 없다.
- 글자: 순백에 가까운 흰색. 보조 글자는 회색(`#999`~`#AAA`).
- 보라가 쓰이는 자리: 돔 테두리 글로우 · 지도 점 · 이동하는 빛줄기 · 3D 오브젝트의 발광부 · 연결선 · 앱 아이콘 타일(보라 그라디언트 사각) · 차트 채움 · 아웃트로 마크. **버튼은 보라가 아니라 흰 알약**이다(보라는 장식과 빛에만).

### 2.3 타이포·구조

- 글꼴: 기하학적 산세리프(Space Grotesk 계열 느낌). 히어로·절 제목은 **가운데 정렬**, 기능 행은 왼쪽 정렬. 큰 숫자는 가볍고 크다(Regular~Medium). 대문자 눈썹 칩은 한 번(기능 절 제목 위).
- 구조 장치: 세로 헤어라인 격자(트립틱), 왼쪽 세로 스파인 + 노드(기능 행), 점 격자(목업 뒤), 헤어라인 칸(숫자 격자). 모두 **정보가 있는 구조**(순서·소속)다.
- 여백: 검정 공간이 넓다. 한 화면에 큰 것 하나(돔·3D 오브젝트·목업).
- 움직임: 히어로 빛줄기(자동 루프), 트립틱 가로 스크럽, 행마다 **한 번의 조립 리빌**(선 그리기 → 창 스케일 인 → 목록 차례로), 아웃트로 루프. 호버 효과는 거의 안 보인다.

### 2.4 v1 과의 거리(왜 v1 이 "지저분"했나 — 리드의 판단)

- v1 은 한 화면에 **움직이는 것이 여럿**이었다: 스티키 라벨 + 매달린 팝오버 + 코너 아잉 + 세그먼트 + 핫스팟 링 + 말풍선. 레퍼런스는 한 화면에 큰 것 하나.
- v1 의 바탕은 평평한 네이비(#12131C) 한 장이었고 빛이 없었다. 레퍼런스는 검정 위 보라 빛이 깊이를 만든다.
- v1 의 섹션은 글 왼쪽 + 작은 렌더 오른쪽이 반복됐다. 레퍼런스는 가운데 정렬 큰 장면 ↔ 왼쪽 정렬 기능 행 ↔ 격자가 리듬을 만든다.

---

## 3. 레퍼런스에서 가져오는 것 / 가져오지 않는 것 (리드 확정)

**가져온다(안무·분위기)**
- 히어로: 가운데 정렬 큰 헤드라인 + 리드 + 알약 버튼 둘 + **보라 빛의 돔(지평선)** 하나.
- 큰 숫자 트립틱(가로 스크럽, `[ 01 / 03 ]` 같은 진짜 순서 카운터 허용).
- 기능 행: 왼쪽 세로 스파인 + 노드, 카테고리 라벨(한글, 소문자 영문 아님) → h3 → 단락, 오른쪽 목업이 **보라 연결선·아이콘 타일**과 함께 한 번 조립되는 리빌.
- 숫자 격자(제품 사실 숫자만, §1).
- 아웃트로: 검정 위 브랜드 요소 하나(우리는 아잉).
- 보라 = 빛. 바탕은 보라 기운의 밤. 버튼은 보라 면이 아니라 **라벤더 채움 1개 + 테두리 1개**(라벤더는 우리 가족색이므로 흰 알약 대신 써도 좋다 — 디자이너 판단).

**가져오지 않는다**
- 암호화폐·결제 3D 오브젝트, 지구본·세계지도(우리 제품과 무관). 우리 "오브젝트"는 **앱 렌더와 아잉 영상**이다.
- 태블릿 기기 프레임(영상 연출일 뿐). 가짜 데스크톱·가짜 노트북 금지(v1 규칙 유지).
- 파트너 로고 띠(파트너 없음). 사용자 수 지표.
- 목업 안에 **커서를 합성**하거나 렌더 위에 덧그리는 것(렌더는 크롭만). 페이지 크롬(연결선·타일·글로우·그림자)은 자유.
- 영문 소문자 카테고리 라벨·대문자 눈썹 남발. 눈썹 칩은 **최대 1개**(히어로 위 "Mac 메뉴바 앱 · iPhone 앱" 정도), 카테고리 라벨은 한글 작은 글자.

---

## 4. 철거 목록(확정) — "체험" 코드

아래는 **삭제**한다(스캐폴드 단계에서). 남길 가치가 있는 조각은 `teardown.md` 에서 가려내되 기본은 삭제.
- `lib/demo/**`(reducer·store·selectors·테스트), `package.json` 의 `test:store`.
- `components/sections/MenubarStage.tsx` + `menubar-stage/**`(StatusItem·Spine·spineDisplay·useSpineBoot·fixedAncestors·useHeroCtaVisible).
- `components/sections/AingCorner.tsx` + `aing-corner/**`(Corner·TodoBoard·UltraOverlay·placement·HideButton·AingCornerClient).
- `components/ui/Hotspot.tsx`, `components/ui/PanelSlot.tsx`, `components/ui/Segmented.tsx`(패널 교체용), `components/ui/LiveAnnouncer.tsx`, `components/ui/TickStrip.tsx`(틱 띠 데모), `components/ui/CharacterStage.tsx`(상태 기계 결합 — 영상 플레이어만 남길지 teardown 이 판단).
- 섹션 전부(`HeroAuto`·`TeamPoke`·`MessageGames`·`CharacterRecords`·`IphoneTrust`·`InstallFaq`·`ClosingFooter` 와 하위 폴더) — v2 섹션은 새로 쓴다. 단 `install-faq/{faq-items,install-copy}.ts`·`closing-footer/{SiteFooter,LicensesNav}.tsx` 같은 **데이터·정적 조각은 재사용 후보**.

**남긴다(인프라·소재)**: `public/assets/**`, `public/fonts/**`, `scripts/**`(build-assets·subset-fonts·check-glyphs·make-qr), `data/fixtures.ts`(인물 세트·RELEASE_FALLBACK·AssetKey — 상태 기계 상수는 정리), `data/generated/*.json`, `lib/{release,site,platform,media,hooks}.ts`(hooks 는 필요한 것만), `app/api/{download,release}/route.ts`, `app/{robots,sitemap}.ts`, `app/licenses/page.tsx`, `app/layout.tsx`(메타·글꼴), `vercel.json`, `next.config.ts`, `components/ui/{Button,DownloadCTA,CommandBox,CopyButton,AppStoreBadge,QrCode,RenderImage,MacWindowShell,PhoneShell,Headline,Bubble}.tsx`(API 는 손봐도 됨), `components/sprite/{AlphaVideo,SheetPlayer}.tsx`·`components/SpritePlayer.tsx`(캐릭터 영상 재생 — 비인터랙티브로만), `components/ui/RenderStack.tsx`(지연 마운트 — 필요하면).
- 복사 버튼(brew 명령 복사)과 FAQ `<details>` 는 "체험"이 아니라 **도구**다. 남긴다.

---

## 5. 디자인 방향(리드 확정 사항과 디자이너의 자유)

### 5.1 확정(모든 안이 지킨다)
- **색 토큰 방향**(최종값은 디자이너가 대비를 실측해 확정, 여기 값은 출발점):
  - 바탕 `--bg-0` ≈ `#0C0A14`(보라 기운 밤; 레퍼런스 #111111/#111122 와 aingo.app #0B0818 사이), 띠 `--bg-1` ≈ `#120F1F`, 면 `--surface` ≈ `#181428`, `--surface-2` ≈ `#221C38`.
  - 빛 `--violet` ≈ `#7C4DFF`(레퍼런스 중앙값 #8434E6 와 라벤더 사이), 깊은 끝 `--violet-deep` ≈ `#3B1E8F`, 밝은 심 `--violet-bright` ≈ `#DA84FF`.
  - 손 `--aing` `#C9B8FF`(유지: 주 버튼 채움·링크·포커스 링), `--on-aing` `#14102A`.
  - 글자 `--ink-1` ≈ `#F4F1FF`, `--ink-2` ≈ `#B8B1D4`, `--ink-3` ≈ `#8A82A8`(모두 bg-0 위 대비 실측 ≥ 4.5, ink-3 는 ≥ 4.5 되는 값으로).
  - 앱 색(민트 #59E0A1·코랄·앱 파랑)은 **렌더 안에서만**.
  - 보라는 **빛으로만**: 돔 테두리, 라디얼 글로우, 연결선, 아이콘 타일 그라디언트, 스파인 노드 점등, `::selection`. 평평한 보라 면(카드 바탕·섹션 바탕)은 없다. 글로우는 **한 화면에 하나**.
- **뼈대(순서 고정, 내용은 자유)**: 내비 → ① 히어로(돔) → ② 큰 숫자 트립틱(가로 스크럽, 3장) → ③ 기능 절 제목 → ④ 기능 행 ×5~6(왼쪽 스파인, 목업 조립 리빌) → ⑤ 숫자 격자(제품 사실) → ⑥ 설치(DMG 주·App Store·brew) → ⑦ FAQ → ⑧ 아웃트로(아잉) → 푸터. 1440×900 기준 **9~11 뷰포트**(트립틱 스크럽 포함).
- **글꼴**: Pretendard 유지. 가중치는 자유 — 소스 `/Users/yesung/aing-check-promo/public/fonts/Pretendard-{Regular,Medium,SemiBold,Bold,ExtraBold}.woff2` 가 있고 `scripts/subset-fonts.mjs` 로 서브셋을 만든다(가중치 하나당 ≈35KB). 레퍼런스처럼 큰 숫자는 가벼운 가중치가 어울릴 수 있다. 본문은 시스템 SF(0바이트) 유지. 명령은 JetBrains Mono.
- **정렬**: 히어로·절 제목·숫자 격자 제목은 가운데(또는 디자이너가 근거를 대고 바꾼다), 기능 행은 왼쪽.
- **모션 체계**: (a) 스크롤 스크럽 2곳까지 — 히어로 돔/빛줄기의 패럴랙스, 트립틱 가로 이동. (b) 문턱 리빌 — 기능 행마다 **한 번**(연결선 그리기 → 렌더 등장 → 보조 요소), 되감기 없음. (c) 자동 루프는 히어로 1곳 + 아웃트로 1곳. (d) 캐릭터 영상은 보일 때만 재생, `prefers-reduced-motion` 이면 **전부 정지 한 장**(스크럽은 세로 나열로 폴백, 트립틱은 3장을 세로로). (e) 호버 효과는 버튼·링크에만. 카드 호버 들림 없음.
- **인터랙션 허용 목록**(이 밖에는 전부 금지): 내비 링크, 다운로드·App Store·brew 복사 버튼, FAQ `<details>`, 푸터 링크, 트립틱의 키보드 접근(섹션 안 요소에 포커스 가능 + 가로 스크럽은 스크롤로만). **클릭하면 렌더가 바뀌는 것 없음.**
- **사실·절제**: v1 SPEC §1.3 의 1(색 규칙 → 이 문서 §5.1 로 대체)·3(캐릭터에 CSS 변형 금지)·4(불투명도는 선형, 이동은 ease-out/in)·6(규칙·수치 캡션 금지 — 단 숫자 격자의 라벨은 허용)·8(한 화면에 어긋나는 가상 수치 금지)은 유지. §1.3-2(움직임은 응답)·5(장식 없음)·7(키커 금지)은 **이 문서 §5.1 모션 체계·§3 으로 대체**(돔·글로우·연결선·격자·눈썹 1개·카테고리 라벨 허용).
- **성능 예산**: 첫 화면 전송 ≤ 400KB(크롬, Fast 4G), 전체 ≤ 4.5MB, 모바일 LCP ≤ 2.5s, CLS ≤ 0.05. 글로우는 CSS(라디얼 그라디언트·blur 된 도형·SVG) 또는 **1장의 webp** 로. 캔버스 셰이더 금지(v1 결정 유지), 3D 라이브러리 추가 금지.

### 5.2 디자이너가 경쟁하는 축
- 돔 안/위에 무엇을 둘 것인가(진짜 팝오버 렌더 / 확대한 메뉴바 라벨 / 아잉 영상 / 조합), 돔의 형태(지평선 호 vs 구체 vs 창 모양 빛), 빛줄기 끝의 "알림 카드"를 우리 앱의 진짜 말풍선 렌더(콕!·메시지·루비)로 쓸지.
- 트립틱 3장의 내용(숫자는 **렌더에 있는 사실**에서만: 예 "5명 근무중"·"콕."·"1"(안 읽은 메시지)·"00:00"·"12주") 과 각 장의 오브젝트.
- 기능 행 순서·묶음(자동 시작 / 캐릭터·루비·할 일 / 쉬는 시간 / 내 기록·AI 토큰 / 아이폰·위젯 / 안심 등), 각 행의 목업과 조립 안무, 카테고리 라벨 문구.
- 숫자 격자 항목(§1 후보 중 검증되는 것).
- 아웃트로 연출(아잉 commute-end 꾸벅 1회 → idle / 라벨 확대 / 아이콘).
- 폰(390)·태블릿(768) 레이아웃, 트립틱의 모바일 폴백.
- 타입 스케일·가중치, 내비 CTA 처리, 설치 절의 Mac/iPhone 배치, FAQ 모양.

---

## 6. 소재(현재 `public/assets/`, 파일명 = 내용)

- `ui/`: `popover-{off,on,working,newmsg,off-1702,tick-strip}.webp`(팝오버 전체 렌더 414pt 폭), `poke-{list,focus-1,focus-2,cooldown}.webp`, `message-{unread,read,composing}.webp`, `league.webp`, `minigame.webp`(플래피 + 오늘 순위 창), `gomoku-board{,-sm}.webp`, `todo-board.webp`, `character-pick.webp`, `insights-popover.webp`, `grass-{work,token}-{empty,final}.webp`, `token-{month,last}.webp`, `header-off-1702.webp`, `menubar-{off,0000,0100,0345,0345-newmsg,0642}.webp` + `menubar-{off,0642}-lg.webp`(확대 라벨), `menubar-icon-dot.webp`, `bubble-{autostart,commute-start,commute-end,poked-mint,message-gureum,ruby,ultra-mint,update}.webp`(앱 말풍선 원문 렌더).
- `char/`: `aing-idle{,-15}.{webm,mov}`(알파 영상, 14.4초 루프/15초), `aing-commute-start`(폴짝 등장), `aing-commute-end`(꾸벅), `aing-poked`, `aing-milestone`(색종이), `aing-ultra`, `aing-ultra-charged`, 포스터 `aing-idle-poster.webp`·`aing-ultra-poster.webp`. 재생은 `components/sprite/AlphaVideo.tsx`(webm/mov 판별 + 포스터 폴백).
- `ios/`: `now.webp`·`messages.webp`·`games.webp`·`rankings-league.webp`·`me-records.webp`(아이폰 화면), `widget-today-small.webp`, `widget-todos-large{,-checked}.webp`.
- `brand/`: `icon-{64,256}.webp`, `appstore-badge-ko-black.svg`(수정 금지), `qr-appstore.svg`.
- 원본(@3x 등)은 `/Users/yesung/aing-check-promo/public/assets/`, 재생성은 `scripts/build-assets.mjs`. 새 크롭·새 크기가 필요하면 이 스크립트에 레시피를 추가한다(렌더 덧그리기 금지, 크롭·리사이즈만).
- **없는 것(그리지 않는다)**: 로봇, AI 리밋 화면, 테트리스·체스 화면, 설정 창 대부분. 글로만.

---

## 7. 설계 워크플로 산출물(이 브리프의 소비자)

1. `docs/v2/reference-analysis.md` — 프레임을 직접 다시 읽고 §2 를 보강: 장면별 레이아웃 비율(헤드라인 폭·여백·목업 크기), 색 표본(sharp 로 영역별), 모션 타이밍(몇 프레임에 걸쳐 조립되는지), 트립틱 스크럽의 길이(스크롤 몇 화면이 가로 3장에 해당하는지 추정). 저장소에 프레임을 복사하지 말 것.
2. `docs/v2/teardown.md` — 현재 `landing/` 파일 전수(§4 를 검증·보강): 삭제/유지/수정 + 이유, 유지하는 컴포넌트의 현재 props, 삭제로 줄어드는 바이트, `package.json`·`eslint`·`tsconfig` 에서 같이 지울 것, 삭제 순서(한 번에 지워도 `tsc` 가 통과하도록).
3. `docs/v2/candidates/{A,B,C}.md` — 세 디자이너의 완전한 SPEC 후보(토큰 실측값·타입 스케일·섹션별 카피(content-brief 문장 그대로)·1440/390 와이어·모션 타이밍·에셋 매핑·컴포넌트 목록·성능 추정·자기 비평). 서로 다른 강조: **A = 레퍼런스 충실(빛의 돔 + 트립틱 + 스파인 행)**, **B = 아잉이 주인공(캐릭터 영상이 돔·트립틱·아웃트로의 오브젝트)**, **C = 에디토리얼(큰 숫자·타이포·보라 선, 렌더는 작게 정확하게)**.
4. `docs/v2/judging/{1,2,3}.md` — 심사 3명. 100점: 사용자 요구 적합(체험 제거·다크+보라 조화·레퍼런스 안무) 40 · 템플릿 아님/기억에 남는 하나 15 · 사실 규칙·소재 실현성 20 · 성능·접근성·반응형 15 · 길이·리듬 10. 각 안에 mustFix 목록.
5. `docs/v2/SPEC.md` + `docs/v2/PLAN.md` + `docs/v2/DECISIONS.md` — 종합자가 1위 안을 뼈대로 접목·mustFix 반영. PLAN 은 v1 `docs/PLAN.md` 와 같은 밀도(디렉터리·파일 소유권·공용 API 서명·섹션 계약·수용 테스트·통합 규칙). 수용 테스트는 "클릭하면 바뀌는 것"이 아니라 **스크롤 위치별 상태·리빌 1회성·감속 모션 정지·금지어 0·콘솔 0·예산** 을 단언한다.
