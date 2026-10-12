# 독립 재검증(⑧) — 아잉체크 랜딩 v2 · verify-final

작성 2026-10-12 22:40 KST · reverify(①–⑦ 에 참여하지 않음). 코드는 한 줄도 고치지 않았다. 앞 단계 보고(integration-report·reviews)는 믿지 않고 같은 명령·하네스를 처음부터 다시 돌렸고, 하네스가 거짓 초록을 낼 수 있는 핵심 단언 5개는 하네스를 import 하지 않는 자기 스크립트로 한 번 더 쟀다.
데브 3000(pid 14129/14130)은 재시작하지 않았다. 측정용 3100 은 두 번 띄우고 두 번 다 껐다(`lsof -i :3100` 비어 있음).

## 0. 결론

- **PLAN §7 T1–T17: 17/17 초록**(데브 3000 + prod 3100, 하네스 `v2accept` 와 독립 스크립트가 같은 값).
- **눈 검사에서 빨강 1건(P2, WebKit 에서만)**: 조용한 절의 빛나는 선(`.seam`·`.tick`·`.horizon`·`.faq-open-line`·`.spine-ext`)에 붙은 `filter: drop-shadow(…)` 때문에 WebKit 이 **문서 왼쪽 위 (0,0)에 28×28 CSS px 사각**을 그린다(대개 검정, 데브에서 한 번은 흰색). Playwright WebKit 26.4 에서 재현했고 원인 CSS 까지 좁혔다. 실제 사파리에서는 확인하지 못했다 → §4.
- 그 밖의 발견은 전부 정보·리드 판단 몫(§7).

---

## 1. T1–T17 결과표

하네스 실행: 데브 = `v2accept/out/reverify-dev/report.json`(15/15 PASS, T1·T13 SKIP) · T1 = `out/reverify-t1/report.json` · prod = `out/reverify-prod/report.json`(T13·T3@prod·T4@prod·T9@prod 4/4 PASS). 하네스 루트 `/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/v2accept/`.

| # | 결과 | 어디서 | 실측 |
|---|---|---|---|
| T1 빌드 건강 | 초록 | landing(직접 + 하네스) | 명령마다 따로 실행: `typecheck` 0 · `lint` 0 · `test:unit` 0(66/66) · `check-glyphs` 0(한글 341자 ⊂ 서브셋 447자 · 300-num 10자 ⊂ 14자) · `build` 0. 데워진 캐시 의심을 덜려고 세션 scratchpad 의 APFS 사본(`.next`·`.scratch` 뺌, `tsbuildinfo` 지움)에서 **콜드 빌드도 exit 0**(사본은 끝나고 지움). 로그 `.scratch/reverify/t1-*.log` |
| T2 서버 | 초록 | 데브 | `/api/download` 302 → `…/v0.3.49/aing-check.dmg`(no-store) · `?file=zip` → `aing-check.zip` · `/api/release` 200 `version 0.3.49` · `dmg.mb "30.1"` · `source github` |
| T3 깨끗함 | 초록 | 데브 + prod | 크롬 390·768·1440 + 웹킷 1440 맨 아래까지: 콘솔 error 0 · pageerror 0 · 실패 요청 0 · 404·4xx·5xx 0 · 보이는 img naturalWidth > 0. 데브 로그(`.scratch/dev.log`)에도 수리 이후 2xx·3xx 밖 응답 0 |
| T4 금지어 | 초록 | 데브 + prod | 21개 0건. 독립 확인 §2-B |
| T5 모양 | 초록 | 데브 | scrollWidth = innerWidth(크롬 390·768·1440, 웹킷 390·768·1024·1440) · 문서 높이 **9,849**(9,300–9,900) · id 순서 12개 일치 · `[data-eyebrow]` 1 · popover 0 · 말풍선−메타 **19.7px**(1440×789·1280×720) · H1 87.99 / 78.9 / 72px(≤ .1·vh) · `<br>` 16곳 = lines − 1 |
| T6 히어로·아웃트로 | 초록 | 데브 | 도착 **1,103ms**(≤ 3.5s) · 빛 한 줄 1회 · 말풍선 +5s 해제 · 빛 한 줄 ↔ 글자 줄 **14.5px**(1440) · **15.6px**(1024) · playbackRate 16 → `data-stopped` **2,897ms**(히어로·아웃트로 모두 실제 재생 뒤) · 감속 영상 요청 0(크롬·웹킷) · 390 `.comet` 없음, 도착 84ms · 아웃트로 말풍선·근무 라벨 0 · 웹킷 기본 = 포스터 폴백(HEVC 알파 디코드 불가 — 알려진 환경 한계) |
| T7 트립틱 | 초록 | 데브 | DOM 위치 SPEC ±24 · scrollY 0 에서 poke·grass 요청 0 → 700 에서 요청 · 활성 0(557)→1(1,205)→2(1,853) · 1,800 에 2 유지 · 1,700 에 1 · 무대 top 0(크롬·웹킷) · 1.5s 안 점등 · 보이는 글로우 1 · 감속 목록 모드 |
| T8 기능 행 | 초록 | 데브 | 5행: 문턱 전 data-on 없음 → 1.5s 안 data-on + dashoffset 0 · 렌더 상자 교차 0 · R1 swap 1 · 그 행만 바닥 빛 · 감속 최종 · todo-board 0 · 행 배율 크롬·웹킷 1440 = 1 · 1024 = .8178 · 800 = 1. 1회성은 하네스 단언이 동어반복이라 독립 확인 §2-D |
| T9 빛 | 초록 | 데브 + prod | V0 6.584 · V1 3.668 · V2 0.330 · V3 1.951 · V4 1.395 · V5 2.174 · V6 0.738 · V7 0.337 · V8 0.383 · V9 5.050%(prod 차이 ≤ .005) · 경계 6곳 글로우 ≤ 1. 독립 확인 §2-C |
| T10 체험 0 | 초록 | 데브 | Tab 33곳 전부 허용 목록 · 첫 Tab = 건너뛰기 · button = 복사 2개 · role tab/switch/slider 0 · cursor:pointer 밖 0 · navigator.share 0 · 감속 img 클릭 해시 불변. 독립 확인 §2-A |
| T11 복사 | 초록 | 데브 | 설치·아웃트로 → 클립보드 `brew install yehsung/check/aing-check` · "복사했어요" → 2.2s 뒤 복귀 · role=status |
| T12 FAQ | 초록 | 데브 | `/#faq-3` → faq-3 만 open · details 10 · JSON-LD 10문항 · 열린 행 빛 헤어라인 |
| T13 예산 | 초록 | prod 3100 | 첫 화면 `load` 까지 **319.2KiB**(독립 CDP 합 **326,846B** · 4G 에뮬 324,970B — 400KB·D25 목표 360KB 둘 다 안) · load + 1s 485.9KiB(정보, D24-1) · 전체 1440 크롬 **1,611.8KiB** · 웹킷 **2,408KiB** · 390 크롬 **1,338.1KiB** · 스로틀 390 LCP **800ms** · CLS **0** · load 전 영상 요청 0(4개 실행) |
| T14 접근성 | 초록 | 데브 | lang=ko · h1 1 · 절마다 h2 · 트립틱 카드 h2 · alt = ALT 표 · 건너뛰기 링크 보임 · 포커스 링 3장 · t-small 21개 대비 ≥ 4.5 |
| T15 iOS | 초록 | 데브 | 히어로·아웃트로 Mac 다운로드 0 · 배지가 버튼 줄 첫째 · 내비 = App Store · 설치 iPhone 열이 위. 추가 확인: 히어로 메타 "iOS 18 이상 · 무료", brew 링크·아웃트로 brew 복사 안 보임(D26-2·4) |
| T16 OG·메타 | 초록 | 파일 + 데브 | 1200×630 · alt.txt = `OG_IMAGE.alt` = SPEC §8 · theme-color #0C0A14 · title = SPEC §8 · og:image 200 |
| T17 sticky 조상 | 초록 | 데브 | html·body·main·#moments(크롬·웹킷): overflow visible/clip · transform 류 none · contain·will-change 없음 |

## 2. 핵심 단언 5개 — 독립 스크립트(`.scratch/reverify/core5.mjs`, 하네스 import 0)

결과 `.scratch/reverify/core5/core5.json`(데브) · `core5-prod/` · `core5-prod-ad/`(prod). 스크립트 자체의 '빨강' 3건은 내 판정 범위가 너무 좁았던 것이라 원인을 확인하고 초록으로 판정했다(아래 '판정 메모').

| 단언 | 결과 | 어떻게 쟀나 · 실측 |
|---|---|---|
| A 체험 0 | 초록 | 포커스 가능한 요소 36개 전부 SPEC §1.5 목록 · button = "복사"·"brew 명령 복사" 2개 · input 0 · 조작 role 0 · **DOM 의 React props 를 훑어 onClick/onPointer/onMouse/onKey… 핸들러를 가진 요소** = 복사 버튼 2 + 푸터 `/licenses` Next `<Link>`(허용 '푸터 링크') 뿐 · **addEventListener 감시(init script)** = Next 내부(`next-route-announcer`·데브 `nextjs-portal`)뿐 · 감속 컨텍스트에서 main 의 img·캔버스·무대·svg **42곳** 가운데 클릭 → 클릭마다 main 해시·URL 불변, 새 창 0. prod 도 같음 |
| B 금지어 0 | 초록 | 서버 HTML **원문 전체**(RSC 페이로드·iOS 변형·noscript 포함) `/`·`/licenses` 0건 + 렌더 DOM(1440 · iOS 390 · 감속 1440)의 모든 텍스트 노드·alt·aria-label·title·placeholder·meta content·JSON-LD 0건. prod 같음 |
| C 보라 예산 | 초록 | 자기 HSV 구현(sharp raw)으로 V0–V9: 6.568 · 3.668 · 0.330 · 1.951 · 1.395 · 2.173 · 0.738 · 0.337 · 0.383 · 5.049% — 하네스와 ±.02 안. **`data-glow≠on` 인데 불투명 > .05 인 빛 0**(속성만 세는 하네스 판정의 거짓 초록 가능성 배제). **1440 전 구간 300px 간격 31곳 훑기**: 12% 초과 0 · 글로우 ≤ 1 · 정착 상태 최저 0.078%(y 8,100). 목록 모드 글로우 훑기(`probe10`): 390 40곳 · 768 29곳 · 감속 1440 31곳 모두 ≤ 1, 숨은 빛 0 |
| D 리빌 1회성 | 초록 | 하네스의 `data-reveal-count` 는 `on ? 1 : 0` 로 계산돼(`FeatureRow.tsx:105`) 재생을 잡지 못한다 → `transitionrun`·`animationstart` 를 행별로 셌다. 1차 통과 조립 전이 18–21개/행 → **위로 되감아 두 번 왕복한 뒤 조립 전이·애니메이션 0**(바닥 빛 GlowGate 전이 8개/행만 — 설계상 양방향) · data-on 한 번 붙고 안 지워짐 · 빛 한 줄 data-run 1회. prod 같음 |
| E 감속 영상 0 | 초록 | 감속 컨텍스트 크롬 1440 · 크롬 390 · 웹킷 1440 · iOS UA 390 — 로드 → 맨 아래 → 아웃트로 4s → 맨 위까지 `.webm/.mov/.mp4`·media 요청 **0**, `<video>` 요소 0, 말풍선·근무 라벨 불투명 1(최종 상태). prod 같음 |

판정 메모(스크립트가 빨강으로 찍었지만 결함 아님): ① React 핸들러 1건 = 푸터 `/licenses` `<Link>`(클라 이동·프리패치) ② 요소 리스너 80건 = `next-route-announcer`·`nextjs-portal`(프레임워크 내부, 페이지 조작 아님) ③ '처음·끝 main 해시 다름' = 스크롤로 행 렌더가 마운트되고(D25-1 `useNearViewport`) data-on 이 붙은 것(클릭 전후 해시는 42곳 모두 같음, `probe2/probe2.json` 의 속성 차이 목록) ④ 훑기 y 1,200 의 0.016% = 트립틱 교체 직후 ≈1s(꺼진 채 들어와 450ms 뒤 점등 — SPEC §S2 설계). 1,293ms 1.79% → 1,692ms 3.66% 로 정착(`probe2`).

## 3. 하네스 거짓 초록 점검

- **T8 1회성**: `data-reveal-count={on ? 1 : 0}` — 값이 2 가 될 수 없는 동어반복. 전이 이벤트로 다시 재서 초록(§2-D).
- **T9 GlowGate**: `[data-glow="on"]` 속성만 센다. 속성과 실제 불투명이 어긋나는 빛은 0(§2-C).
- **T13 예산 단위**: `400 * 1024` B(KiB)로 판정해 SPEC 의 400KB 보다 2.4% 느슨하다. 독립 측정 326,846B 는 400,000·360,000 둘 다 안이라 결과는 같다.
- **하네스 수정 이력**: `T05`·`T08` 은 단언을 **더한** 것(웹킷 4폭 가로 넘침 · 행 배율), `T13` 은 D24-1(`load` 까지) 승인 변경, `expect.mjs` V6–V8 하한 0.003 은 D27-2. 단언을 약하게 만든 수정 없음(`*.orig` 와 diff).

## 4. 빨강 — 재현 방법

### R1 (P2 · WebKit 만) 문서 왼쪽 위 (0,0)–(28,28) 에 사각 하나가 그려진다
- **보이는 것**: 페이지 맨 위(scrollY 0–27, 내비가 투명한 동안) 히어로 왼쪽 위 모서리에 28×28 CSS px(레티나 56×56) 사각. prod·데브 대부분 **검정(0,0,0)** — 바탕 #0C0A14 와 거의 같아 눈에 잘 안 띄지만, 이번 데브 캡처 한 장에서는 **흰색**이었다(`.scratch/reverify/vis/webkit-1440-fold.png`, 확대 `vis/webkit-dev-topleft-zoom.png`). 색이 실행마다 다른 것은 초기화되지 않은 합성 타일의 증상이다. 크롬에는 없다. 390(iOS 에뮬)에서도 같은 자리에 검정.
- **원인(좁힌 것)**: 숫자 격자·설치·FAQ·아웃트로의 빛나는 선에 걸린 `filter: drop-shadow(…)`(`app/globals.css` 182행 `.spine-ext` 외 `.seam`·`.tick`·`.horizon`·`.faq-open-line` — 수리 1바퀴의 D27-2 '좁은 빛'). 모든 요소의 filter 를 끄면 사라지고, **`#facts .seam` 하나에만 filter 를 남겨도 다시 생긴다**. 해당 선들이 화면 밖(문서 아래 6,000px+)에 있을 때 WebKit 이 그 층의 타일을 문서 원점에 잘못 그리는 것으로 보인다. 통합(⑤) 때 웹킷 캡처에는 없었고 수리(⑦) 캡처(`.scratch/repair/shots/webkit-1440-fold.png`)부터 검정 사각이 있다.
- **재현**:
  1. `node /Users/yesung/check/landing/.scratch/reverify/webkit-corner-cause.mjs http://localhost:3000` → `as-is 0,0,0` · `all filter:none 12,10,20` · `only .seam keeps filter 0,0,0`(왼쪽 위 (10,10) 픽셀).
  2. `node /Users/yesung/check/landing/.scratch/reverify/webkit-corner-sweep.mjs http://localhost:3000` → 내비를 숨기고 scrollY 0 에서 784px(=28×28), 8 에서 560px(=28×20) — 문서에 붙어 함께 스크롤된다. 100 이상에서는 0.
  3. prod 에서도 같다(`wkprod.mjs` 캡처 `vis/webkit-prod-1440-fold.png`, 확대 `vis/webkit-prod-topleft-zoom.png`).
- **판정 근거와 한계**: Playwright WebKit 26.4(macOS 포트) 결과다. 실제 사파리에서 같은지는 확인하지 못했다(사파리 실기는 D25-4 로 사용자 몫). 크기·색 때문에 사용자가 알아챌 가능성은 낮지만, 랜딩 방문자의 주 브라우저가 사파리이고 흰색이 나오면 '지저분함'(brief 원문)에 해당하므로 빨강으로 올린다. 고칠 길(제안만): 1px 선의 '좁은 빛'을 `filter: drop-shadow` 대신 `box-shadow`(선 상자를 따르는 0 0 2px · 0 0 8px)로 바꾸고 V6–V8 ≥ 0.3% 를 다시 재거나, 사파리 실기에서 안 보이면 리드가 허용으로 닫는다.

## 5. 눈 검사

### 5.1 캡처(전부 `/Users/yesung/check/landing/.scratch/reverify/vis/`, 데브 표시기 숨김)
1440×900: `1440-01-hero-t0.png` · `1440-02-hero-arrived.png` · `1440-03-moments-01.png` · `1440-04-moments-02.png` · `1440-05-moments-03.png` · `1440-06-features.png` · `1440-07-R1-message.png` · `1440-08-R2-character.png` · `1440-09-R3-break.png` · `1440-10-R4-ranking.png` · `1440-11-R5-iphone.png` · `1440-12-facts.png` · `1440-13-install.png` · `1440-14-faq.png` · `1440-15-outro.png` · `1440-16-bottom.png` · `1440-full.png`(9,849px)
390: `390-fold.png` · `390-full.png`(780×23,948 @2x, 나눠 본 것 `390-full-part1–7.png`)
감속 1440: `1440-reduced-fold.png` · `1440-reduced-full.png`(9,999px, 나눠 본 것 `1440-reduced-part1–5.png`)
웹킷: `webkit-1440-fold.png`(데브) · `webkit-prod-1440-fold.png` · `webkit-prod-1440-R4.png`(행 캔버스 정상 배율) · 확대 `webkit-dev-topleft-zoom.png` · `webkit-prod-topleft-zoom.png`
빛 한 줄 프레임 시트(110ms 간격 12장): `/Users/yesung/check/landing/.scratch/reverify/probe10/comet-sheet.png`
보라 측정 캡처: `/Users/yesung/check/landing/.scratch/reverify/core5/shots/C-V0…V9.png`

### 5.2 SPEC §1.3 절제 원칙 대조
| 원칙 | 판정 | 본 것 |
|---|---|---|
| 1 큰 것 하나·글로우 하나·움직임 하나 | 초록 | 화면마다 주인공 하나(돔 / 트립틱 오브젝트 / 행 캔버스 / 격자 / 두 열 / 질문 목록 / 작은 돔). 글로우 ≤ 1 은 1440 31곳 · 390 40곳 · 768 29곳 · 감속 31곳 훑기로 확인. 트립틱 01 진입 직후(scrollY ≈670)는 히어로 아잉 아랫부분과 오브젝트 1 이 한 화면 — 둘 다 00:00 이라 SPEC §S2 금지('다른 시각') 아님, 지나가는 위치 |
| 2 보랏빛 밤 바탕 | 초록 | 바탕 실측 (12,10,20) = #0C0A14 · 평평한 보라 면은 48px 타일뿐 |
| 3 렌더는 크롭·축소·페이드만 | 초록 | 덧그린 숫자·커서·필터 없음. 콕 조각 머리띠 노치·16px 페이드(D27-3) 확인 |
| 4 움직임 여섯 가지뿐 | 초록 | 도착 1회(프레임 시트: +184ms 림 위 흰 머리 → +406ms 림 이탈 → +1,058ms 도착·말풍선 → +1,286ms 폴짝) · idle 2회 정지 · 패럴랙스 · 트립틱 교체 · 행 조립 1회(§2-D) · GlowGate. 섹션 페이드업·호버 들림 못 봄 |
| 5 불투명도 선형 | 판정 안 함 | 정지 캡처로는 못 잰다(리뷰 motion 몫) |
| 6 클릭하면 바뀌는 렌더 0 | 초록 | §2-A |
| 7 숫자는 렌더·제품 사실만 | 초록 | 격자 0원 · 14이상 · 18이상 · 30.1MB(서버 값) · 12주 · 3종 · 1:1 · 0개 |
| 8 한글 주인공·칩 하나 | 초록 | 영문 대문자 라벨 없음, 칩 1개 |

### 5.3 SPEC §0.4 세 요구 대조
| 요구 | 판정 | 본 것 |
|---|---|---|
| ① 체험 제거 | 초록 | 누를 수 있는 것은 내비·CTA·배지·QR·brew 링크·복사 2·summary·푸터뿐(§2-A, T10) |
| ② 다크 + 보라 조화 | 초록 | 모든 화면에 보라 빛이 있다: 돔 6.6% → 무대 3.7% → 칩 0.33% → 행 1.4–2.2% → 조용한 절 0.34–0.74%(선·틱·스파인 연장) → 작은 돔 5.0%. 정착 상태 최저 0.078%, 최고 6.6%(상한 12%) |
| ③ 레퍼런스 안무 | 초록 | 돔 히어로 → 큰 숫자 3장(고정 오브젝트 교체·점등·[ 01 / 03 ]) → 눈썹 칩 + 가운데 H2 → 10% 스파인 + 노드 행 조립 → 4×2 숫자 격자 → 한 단 검은 엔드(작은 돔) |
| 지저분함 | 빨강 1(§4 R1, 웹킷) | 크롬 캡처에서는 겹침·잘림·잔상 없음 |

## 6. 서버 · 위생

- **서버(데브 3000)**: `/api/download` 302 → `https://github.com/yehsung/check/releases/download/v0.3.49/aing-check.dmg`(no-store) · `?file=zip` 302 → `aing-check.zip` · `/api/release` 200(361B JSON) · `/licenses` 200 · `/robots.txt` 200 · `/sitemap.xml` 200 · `/` 200 · `/opengraph-image.png` 200(260,853B). `/licenses` 첫 Tab = 건너뛰기 링크(132×30, 화면 안), 콘솔 0.
- **데브 3000**: pid 14129(next dev)/14130(next-server) 그대로, `GET /` 200, 재시작 0회.
- **3100**: 두 번 띄움(예산 · 웹킷 prod 캡처), 두 번 다 종료, `lsof -i :3100` exit 1(비어 있음), `next start` 프로세스 0.
- **남은 프로세스**: ms-playwright 브라우저 0 · 웹킷 프로세스 0 · ffmpeg 0 · 내 node 스크립트 0(전부 `pgrep` exit 1 로 판정). 데브 밖 node 중 landing·하네스 관련 0(나머지는 사용자 앱·MCP).
- **landing/ 흘린 파일**: 작업 전·후 파일 목록(`.next`·`node_modules`·`.scratch` 제외) diff 0. 내 임시는 전부 `.scratch/reverify/`. 콜드 빌드 사본은 세션 scratchpad 에 만들고 지웠다.
- **git**: `git -C /Users/yesung/check status --short` = `?? landing/` 한 줄.
- **requests 처리**: `docs/v2/requests/` 10개 파일의 요청 항목(assets §1·§3, core §1–3, facts-install §1–4, faq-outro §1–2, hero §1–3, moments §1–3, primitives §1·§2, rows-a §1–3, rows-b §0–4)이 전부 integration-report §3 표에 처리로 있다. 나머지 절은 알림·참고(조치 불필요). 몇 개는 직접 확인: 새 AssetKey 11개(fixtures·assets.json) · 800 서브셋 없음 · `motion`·`test:store` 없음 · LicensesNav 건너뛰기 링크 보임 · check-glyphs 0 · tsc 0. 리뷰 P1 12건도 수리 표에 다 있고, 그중 iOS 메타 · 목록 모드 글로우 · 빛 한 줄 머리 · 히어로 받침선 · 조용한 절 보라 · zip 누를 자리를 다시 확인했다.

## 7. 남은 문제(빨강 아님 — 정보 · 리드 판단)

1. **트립틱 교체 직후 ≈1s 보라 0.016%**(y 1,200): 꺼진 채 들어와 점등되는 설계(SPEC §S2). 정착 뒤 3.66%.
2. **R4 리그 조각 첫 음절**: "각자 목표" 가 "ㄱ자" 로, 팀 이름 첫 글자가 흐리게 보인다. 수리가 D27-3 조건부 재굽기를 배지(서울/부산) 유입 때문에 하지 않은 것 그대로.
3. **390 히어로**: 메타와 아잉 사이 빈 띠 ≈150px(review-design P2-6, 리드 판단으로 남김).
4. **390 brew 명령 줄바꿈**: `brew install yehsung/` · `check/aing-check` 두 줄로 꺾인다(복사 값은 정확).
5. **내비 CTA 누를 자리**: 테두리 상태에서 `::before` 계산 높이 42px(수리 보고 44). WCAG 2.5.8(24px)은 넉넉히 넘는다.
6. **스로틀 390 LCP 요소 = 영상**(800ms): SPEC §5.4 는 포스터를 기대하지만 예산 안(perf 리뷰 참고 1).
7. **sitemap·robots 주소**: 데브는 `http://localhost:3000`. 배포 때 `VERCEL_PROJECT_PRODUCTION_URL`(또는 `NEXT_PUBLIC_SITE_URL`)로 바뀐다(`lib/site.ts`).
8. **사파리 실기 HEVC 알파**: Playwright WebKit 은 디코드하지 못한다(포스터 폴백·콘솔 0 확인). 실기 확인은 사용자 몫(D25-4). §4 R1 도 실기에서 함께 보면 된다.

## 8. 표식

DECISIONS D15 대로 `docs/v2/.*-done` 20개를 이 문서를 쓴 뒤 모두 지웠다.
