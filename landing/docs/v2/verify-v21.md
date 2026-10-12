# verify21 — 랜딩 v2.1 검증 2회차(읽기 전용)

작성 2026-10-12 23:47 KST · verify21. 코드는 한 줄도 고치지 않았다. 이 회차에 쓴 파일은 셋뿐이다: 이 문서(1회차 판을 덮어씀), `docs/v2/.verify2121-done`(touch), `.scratch/verify21/**`.

측정 대상 상태:
- 마지막 소스 변경은 23:31:56 `app/opengraph-image.png`(fix21 의 OG 재촬영)이다. 그다음은 23:08 `app/globals.css` 다.
- 1회차 이후 바뀐 저장소 파일은 OG 그림 하나다. 하네스(저장소 밖)에서는 fix21 이 `tests/T10·T14·T17.mjs` 를 갱신했다(23:32–23:33).
- 측정은 23:36–23:46 에 했다. 그동안 landing/ 소스 변경은 0건이다(`find -newermt 23:35`, `.next`·`node_modules`·`.scratch` 제외).

서버:
- 데브 3000(pid 14129/14130)은 재시작하지 않았다.
- 측정용 prod 는 **3101** 에 한 번 띄우고 kill 했다. 그 뒤 `lsof -i :3101` 은 exit 1(비어 있음)이다.
- 3100(Aingo-652 next dev, pid 42258/42268)은 건드리지 않았다.

## 0. 결론

- **수용 조건 빨강 0건.** T1–T17(T1 직접 실행 + 데브 15/15 + prod 4/4)과 자기 스크립트 12항목이 모두 초록이다.
- **1회차 빨강 4건이 전부 풀렸다.**
  - T16: fix21 이 OG 를 다시 찍었다. 그림 안 리드가 한 문장이다.
  - T10 · T14 · T17: fix21 이 하네스를 v2.1 에 맞게 고쳤다. 단언을 약하게 만든 것이 아니라 바꾼 것이다(§2 끝).
- **T16 을 리드 지시와 다르게 적었다.** 리드는 "T16 은 빨강으로 적는다(수정 단계가 D8 절차로 다시 찍는다)"고 했다. 그런데 그 재촬영이 이미 23:31 에 끝나 있었다. 실측이 초록이라 초록으로 적고 근거를 남긴다(§5).
- brief-v21 의 세 요구는 숫자로 다시 확인했다.
  - ① 글: main **721자** = v2 1,561자의 **46.2%**(목표 ≤ 780).
  - ② 보라: 장면 6.35–11.54% · 보라 기운 48.5–61.8%.
  - ③ 통째 렌더: 7개 폭/엔진 × 13장 = 104건 모두 마스크·clip-path·잘림 0, 부모 상자 안에 완전히 들어감.
- **눈 검사에서 리드 판단 1건**(수치 기준 밖, 빨강 아님): 장면 5 주 렌더 `ui/minigame` 은 **원본 소재 자체가 아래가 잘린 창**이다(§6-1). 사용자 요구 ③("창은 통째로")의 눈높이로는 잘린 창으로 읽힐 수 있다.

## 1. 빌드 건강(T1 — 명령마다 따로, exit code 로 판정)

| 명령 | exit | 실측 | 로그(`.scratch/verify21/r2/logs/`) |
|---|---|---|---|
| `npm run typecheck` | 0 | — | `typecheck.log` |
| `npm run lint` | 0 | — | `lint.log` |
| `npm run test:unit` | 0 | 50/50 pass | `test-unit.log` |
| `node scripts/check-glyphs.mjs` | 0 | 소스 58개 파일. 한글 267자 ⊂ 500·600 서브셋 370자. 300-num 10자 ⊂ 14자 | `check-glyphs.log` |
| `npm run build` | 0 | 라우트 10개. `/` 정적(revalidate 1h) | `build.log` |

prod 3101 이 내준 `/opengraph-image.png` 는 `app/opengraph-image.png` 와 같다(`cmp` exit 0). 빌드가 새 OG 를 담았다는 뜻이다.

## 2. 하네스 결과(`/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/v2accept/`)

- **데브**: `node run.mjs --base http://localhost:3000 --out out/v21`
  - 결과 **exit 0**: judged 15 · pass 15 · fail 0 · T1·T13 skip · 190.7s.
  - `out/v21/report.json` · 로그 `out/v21.log`. 1회차 report 사본은 `.scratch/verify21/r2/r1-harness/`.
- **prod**: `npm run build`(exit 0) → `npx next start -p 3101`(백그라운드) → `node run.mjs --base http://localhost:3000 --prod http://localhost:3101 --only T13,T3@prod,T4@prod,T9@prod --out out/v21-prod`
  - 결과 **exit 0**(4/4) · `out/v21-prod/report.json`.
  - 끝난 뒤 내가 띄운 3101(npm exec 64992 + next-server 65011)만 kill 했다.

| # | 결과 | 실측 |
|---|---|---|
| T2 서버 | 초록 | `/api/download` 302 → `…/v0.3.49/aing-check.dmg`(no-store) · `?file=zip` → `aing-check.zip` · `/api/release` 200 `0.3.49` · dmg.mb "30.1" · source github |
| T3 깨끗함 | 초록(데브 + prod) | 크롬 390·768·1440 + 웹킷 1440: 콘솔 error 0 · pageerror 0 · 실패 요청 0 · 4xx/5xx 0 · 깨진 img 0 |
| T4 금지어 | 초록(데브 + prod) | 21개 0건(크롬 1440 · iOS 390) |
| T5 모양 | 초록 | 가로 넘침 0(크롬 390·768·1440 · 웹킷 390·768·1024·1440) · 문서 높이 **7,938**(7,000–8,400) · id 순서 10개 일치 · 장면 6개 렌더 통째(2·2·3·2·2·2개) · `<br>` 수 일치 · 말풍선−메타 47.6(1440×789) · 27.2(1280×720) · H1 78.9 · 72px |
| T6 히어로·아웃트로 | 초록 | 도착 1,121ms · 빛 한 줄 run t=265 · 1회(왕복 뒤) · +2.5s 불투명 0 · 빛↔글자 14.5px(1440) · 15.6px(1024) · `data-stopped` 2,981ms · 감속 영상 0(크롬·웹킷) · 390 도착 79ms · 아웃트로 629ms 불투명 1 |
| T7 | 초록 | 트립틱 섹션 없음(v2.1) |
| T8 장면 6 | 초록 | 문턱 전 data-on 없음 → 1.5s 안 data-on · dashoffset 0 · 렌더 상자 교차 0 · f-message `.swap-to` 1 · 감속 최종 · 캔버스 배율: 크롬·웹킷 1440 = 1, 1024 = .7123, 800 = 1 |
| T9 빛 | 초록(데브 + prod, 값 같음) | §4 표 · 큰 빛 ≤ 2(경계 9곳 모두 2) · `.scene-glow` 계약 6장면 · **웹킷 (0..40)² 코너 maxDev 0**(내비 보임 · 숨김 · scrollY 8) |
| T10 체험 0 | **초록**(1회차 빨강 → 하네스 갱신) | Tab 27곳 전부 허용(데브 표시기 1 제외) · 첫 Tab = 건너뛰기 · button = 복사 2 · role 0 · pointer 밖 0 · navigator.share 0(로드 청크 · `.next/static` 12파일) · 감속 img 14곳 클릭 → main 불변 · 팝업 0 |
| T11 복사 | 초록 | 10 checks |
| T12 FAQ | 초록 | details 5 · 질문 순서 = CB §7 1–5 · JSON-LD 5 · 기본 faq-1 열림 · `/#faq-3` → 3만 |
| T13 예산(prod 3101) | 초록 | 아래 블록 |
| T14 접근성 | **초록**(1회차 빨강 → 하네스 갱신) | lang ko · h1 1(#top) · section 10개 h2 · **장면 6개 모두 h2**(새 단언) · alt = ALT 표 · 건너뛰기 보임 · 포커스 링 3(2px #C9B8FF) · t-small 대비 6개 ≥ 4.5 |
| T15 iOS | 초록 | 7 checks(내비 CTA = App Store, Mac 다운로드 0) |
| T16 OG·메타 | **초록**(1회차 빨강 → fix21 재촬영) | §5 |
| T17 sticky 조상 | **초록**(1회차 빨강 → 하네스 갱신) | 크롬·웹킷: sticky 요소 0 · html · body · main#main 금지 스타일 0 |

T13 예산(prod 3101) 실측:
- 첫 화면 `load` 까지 **283,624B(277KiB)** ≤ 400KB. D25 목표 360KB 안이다.
- load + 1s 는 596,423B 다(정보).
- 전체 크롬 1440 **1,673,867B(1.67MB)** · 웹킷 1440 2,489,142B · 390 1,400,419B ≤ 2.2MB.
- 스로틀 390 LCP 852ms(영상) · CLS 0 · load 전 영상 0(4개 실행).

하네스 갱신 점검(`T10/T14/T17.mjs` ↔ `*.v2.mjs` diff):
- T10: 허용 내비 정규식만 `features` → `f-timer` 로 바뀌었다. 사라진 `/#features` 링크는 목록 밖으로 센다.
- T14: 트립틱 카드 h2 단언은 `#moments` 가 있을 때만 판정한다. 대신 **#top h1 + 장면 6개 section 마다 h2** 단언이 새로 들어갔다.
- T17: `#moments` 전제를 뺐다. html · body · main 은 늘 판정하고, 페이지의 모든 sticky 요소의 조상 사슬과 `#moments`(되살아나면)도 판정한다.
- 셋 다 v2.1 구조에 맞춘 교체다. 판정을 느슨하게 만든 곳은 없다.

## 3. 자기 스크립트로 한 번 더(하네스 import 0)

스크립트:
- `.scratch/verify21/r2/probe2.mjs`: 1회차 `probe.mjs` 에 세 가지를 더했다 — 직접 부모 상자 포함 판정 · 서버 HTML 원문 금지어 · 웹킷 폭 통째 판정.
- `r2/summ.mjs`: 판정 요약.
- `r2/tab2.mjs`: 맨 위부터 Tab.
- 글자 수 도구: `…/scratchpad/tools/textlen.mjs`.

결과 파일: `r2/probe/probe.json` · `r2/summ.json` · `r2/tab.json` · `r2/after.txt`.

| 항목 | 결과 | 실측 |
|---|---|---|
| main 글자 수(textlen) | **초록** | **721** ← v2 1,561(`.scratch/verify21/before.txt`) = 46.2%, 기준 ≤ 780. 공백 포함 innerText 는 972 |
| 섹션 순서 | 초록 | `top, f-timer, f-tokens, f-message, f-rhythm, f-games, f-iphone, install, faq, outro`. main 자식 = top · [장면 묶음 `data-scenes`] · install · faq · outro |
| 문서 높이 | 초록 | 1440×900 **7,938**(brief ≈7,600, T5 범위 안) · 390×844 9,307(정보) |
| 보라(엄격 · 기운) | 초록 | §4 |
| 장면 렌더 통째 | **초록** | 크롬 1440(장면 조립 끝) · 크롬/웹킷 × 390·768·1440 · 모바일 390 dsf2, 7벌 × 13장 = **104건**. 아래 여섯 가지를 모두 만족 |
| 센터 배지 패널 배율 ≤ .5 | 초록 | 표시폭 ÷ naturalWidth(1440). popover-working · message-unread/read · insights-popover **.449** · token-month **.435** · league **.362** · minigame **.400**. 768 최대 .438 · 390 최대 .389(minigame .230). 모든 폭·엔진에서 828px 패널 최대 **.4493** |
| 금지어 0 | 초록 | DOM(본문 · alt · aria-label · title · placeholder · meta · JSON-LD · title) 0. 서버 HTML 원문 `/`(98,318자 — RSC · 닫힌 FAQ 답 포함)·`/licenses` 0 |
| 체험 0(Tab 순회) | **초록** | 맨 위부터 Tab **26곳**, 모두 허용 목록(아래) |
| 감속 모션 영상 요청 0 | 초록 | 감속 1440: 로드 → 맨 아래 → 4s → 맨 위까지 media · webm/mov/mp4 요청 **0** · `<video>` 0 · 말풍선 · 근무 라벨 불투명 1 · 장면 6개 data-on |
| WebKit 코너 | **초록** | 웹킷 1440 첫 화면 (0..40)² maxDev **0**(dsf 1) · (0..80)² maxDev **0**(dsf 2). 맨 아래까지 왕복한 뒤에도 0/0 |
| 가로 넘침 0 | 초록 | 크롬 · 웹킷 × 390/768/1440: 스크롤 내내 최대 넘침 0, 끝에서 scrollWidth = innerWidth |
| 콘솔 에러 0 | 초록 | 컨텍스트 10개(크롬 1440 · 넘침 6 · 감속 · 웹킷 ×2 · 모바일 390 — 넘침 6 은 크롬 · 웹킷 각 3폭): console error 0 · pageerror 0 · 실패 요청 0(미디어 자진 중단 제외) · 4xx/5xx 0 |
| 렌더 상자 교차(정보) | 0 | 장면별 쌍 교차(1px 초과, 메시지 교체 쌍 제외) 7벌 모두 0 |
| sticky · 조상(정보) | 초록 | `position: sticky` 요소 0 · html/body/main 금지 스타일 0(body `overflow-x: clip` 만) |

Tab 26곳의 내역: 건너뛰기 1 · 내비 링크 3(`/#f-timer` · `/#install` · `/#faq`) · 내비 CTA 1 · 다운로드 3 · App Store 배지 · QR 4 · brew로 설치 1 · 복사 2 · summary 5 · 푸터 6. 그 밖에 button = "복사" · "brew 명령 복사" · role 0 · input 0 · cursor:pointer 밖 0 이다. 하네스는 27곳으로 셌는데, 시작 포커스를 잡는 방식이 달라서다. 둘 다 위반 0 이다.

통째 렌더의 판정 여섯 가지(104건 전부):
- 원본/표시 종횡비 오차 최대 **.0026**(반올림 수준).
- `object-fit: fill`.
- img 에서 장면 `<section>` 까지 모든 조상의 `mask-image` · `-webkit-mask-image` · `clip-path` = none(마스크 0).
- overflow 가 visible 이 아닌 조상(장면 루트 `overflow-x: clip` 포함)이 잘라낸 px = 최대 **0**.
- **getBoundingClientRect 가 직접 부모 상자 안에 완전히 포함**(±1px). 실패 0건, 네 변 차이 모두 0.
- 창 모양: 주 패널 · 보조 패널 9종은 부모 상자에 radius 12px + `--shadow-window`(링 `rgba(255,255,255,.07)` + 그림자)가 있다. 메뉴바 라벨 · 말풍선 · 위젯 · 폰 화면은 창이 아니라 해당 없음.

예외(정보): 장면 6 의 `ios/now` 는 폰 셸 화면(`overflow: hidden`, radius 37.2px) 안에 있다. 잘린 px 는 0 이고, 모서리만 폰 화면처럼 둥글다.

## 4. 보라 면적(HSV, 1440×900, dsf 1 — 자기 측정 / 하네스 T9 데브 · prod)

판정 기준과 목표:
- 엄격 = H 245–295° · S ≥ .35 · V ≥ .30.
- 기운 = 같은 H 범위에서 S ≥ .15 · V ≥ .12.
- 목표는 brief-v21 §5 다. 히어로 · 아웃트로의 기운 ≥ 25% 는 리드 결정으로 면제다(돔 안 검정은 의도 — 정보로만 적는다).

| 위치 | 엄격 % (목표) | 기운 % (≥ 25) | 하네스 데브 / prod 엄격 |
|---|---|---|---|
| V0 히어로(도착 + 2.5s) | **6.855** (≥ 6, ≤ 12) | 18.0 — 면제 | 6.858 / 6.858 |
| V1 `#f-timer` 가운데 | **6.353** (4–15) | 56.1 | 6.353 / 6.353 |
| V2 `#f-tokens` | **9.097** | 48.5 | 9.097 / 9.097 |
| V3 `#f-message` | **11.544** | 55.2 | 11.544 / 11.544 |
| V4 `#f-rhythm` | **10.160** | 52.0 | 10.16 / 10.16 |
| V5 `#f-games` | **11.545** | 53.8 | 11.545 / 11.545 |
| V6 `#f-iphone` | **10.895** | 61.8 | 10.895 / 10.895 |
| V7 설치(내비 아래) | **4.187** (≥ 1.5, ≤ 8) | 59.2 | 4.187 / 4.187 |
| V8 FAQ(내비 아래) | **1.968** (≥ 1, ≤ 8) | 31.4 | 1.968 / 1.968 |
| V9 아웃트로(위 = 0) | **5.081** (≥ 5, ≤ 12) | 9.6 — 면제 | 5.094 / 5.094 |

- 15% 를 넘는 곳은 0 이다.
- 장면 빛 지름(리드 승인 값): f-timer · f-tokens · f-iphone 1520(반지름 760) · f-message 1400(700) · f-rhythm 1440(720) · f-games 1280(640). 모두 불투명 1 · 전이 0 · data-glow 없음이다.
- purple 이 더한 설치 · FAQ 타원 빛은 리드 승인 대상이고, 위 V7 · V8 값에 들어 있다.
- 정보: V9 는 5% 하한에 여유가 .08–.09%p 뿐이다. 아웃트로 돔은 '그대로'라 조정할 손잡이가 없다.

## 5. 빨강 — 없음(1회차 빨강의 해소 근거)

### 1회차 R1(제품) T16 — OG 그림의 옛 두 문장 리드 → **해소**
- `app/opengraph-image.png`(302,431B, 23:31:56)는 fix21 의 `.scratch/fix21/og/opengraph-image.png` 와 바이트가 같다(`cmp` exit 0). prod 3101 이 내준 그림도 같다.
- 그림을 직접 봤다: 1200×630 · 내비 없음 · 돔 꼭대기 · 메뉴바 라벨 00:00 · H1 두 줄 · **리드 한 줄 "근무 시작을 누르면 팀 전체에 바로 보여요."** · CTA · 메타 · 말풍선 "오늘도 화이팅!" · 근무 라벨이 붙은 아잉. 데브 표시기는 없다.
- 하네스 T16: 'OG 그림이 히어로 카피 뒤에 찍힘'이 초록이다(og 23:31:56 KST > hero copy 22:56:50 KST). 리드 한 문장 · alt.txt = `OG_IMAGE.alt` = SPEC §8 문장 · 1200×630 · theme-color · title 도 모두 초록이다.
- 촬영 절차(`.scratch/fix21/og.mjs`)는 D8 과 같다: 1440×900 dsf 2 · 감속 · 내비와 데브 표시기 숨김 · (0, 라벨 위 − 40, 1440, 756) → 1200×630 lanczos.
- 리드 지시("T16 은 빨강으로")는 재촬영 전 상태를 전제한 것이다. 실측이 초록이라 초록으로 적었다.

### 1회차 R2–R4(하네스) T10 · T14 · T17 → **해소**
- fix21 의 하네스 갱신으로 초록이 됐다(§2 끝의 diff 점검). 1회차에 자기 스크립트로 같은 의도를 확인한 값과 이번 하네스 값이 같다.

## 6. 정보 · 리드 판단(빨강 아님)

1. **장면 5 주 렌더 `ui/minigame` 의 아래 변이 잘린 창처럼 보인다** — 눈 검사, 리드 판단.
   - 무엇: 게임 캔버스는 위 모서리만 둥글고 아래 변은 테두리 · 여백 없이 파이프가 창 아래 끝에 닿는다. 순위 목록도 8번째 행 바로 아래에서 끊긴다.
   - 페이지 탓인가: 아니다. CSS 크롭은 0 이고(§3 통째 판정 초록), 창 상자(radius 12 + 그림자)도 통째다.
   - 원인: **소재 원본이 그렇게 찍혀 있다.**
     - `scripts/build-assets.mjs:82` 는 `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/minigame_window_flappy_playing_8rows@3x.png`(2100×1168)를 1400×779 로 **축소만** 한다.
     - 원본의 맨 아래 줄(y 1167)도 게임 캔버스 안쪽이다(x 300 = 파이프 녹색 46,93,67). 축소본도 같다(x 200, y 778 = 48,93,67).
   - brief-v21 §3 은 이 파일을 '통째 패널'로 지정했다. 사용자 요구 ③("절반만 보이는 창 금지 · 창은 통째로")의 눈높이로 보면 잘린 창으로 읽힐 수 있다.
   - 캡처: `.scratch/verify21/shots/1440-scene5-f-games.png`. 소재 비교: `.scratch/verify21/r2/minigame-asset.png` · `minigame-source.png`.
   - 고칠 길(제안만): 아래까지 있는 다른 미니게임 원본이 있으면 교체한다. 없으면 리드가 허용으로 닫는다.
2. **히어로 빛 한 줄 머리에 `filter: drop-shadow` 가 남아 있다**(`app/globals.css:226` `.comet-head`). 1회차 정보 그대로다.
   - 수용 기준(웹킷 코너 bg-0 ±6)은 초록이다(하네스 3상태 · 자기 측정 2배율 · 왕복 뒤 모두 0).
   - 다만 Playwright WebKit 은 HEVC 알파를 못 풀어 빛 한 줄을 출발시키지 않는다. 실제 사파리에서 빛이 달린 뒤의 코너는 재지 못했다.
3. **스파인 이음매**: FAQ → 아웃트로 경계(y ≈ 6,989)에서 스파인 밝기가 한 번 뛴 뒤 사라지는 짧은 따로 선이 보인다(`1440-faq.png` 왼쪽 아래 x 144, `1440-full.png`). 1회차와 같다.
4. **장면 높이**: f-timer 823 · f-tokens 793 · f-message 760 · f-rhythm 824 · f-games 760 · f-iphone 760(brief ≈760). 설치 644 · FAQ 725(1번 열림).
5. **brief §3 와 작은 차이**(1회차 그대로):
   - 장면 4 보조 잔디 표시폭 290(brief 300).
   - 장면 4 문장은 CB:144 의 둘째 문장이다(글자는 CB 그대로).
   - 장면 4 제목 「12주 잔디, / 지난주 리듬.」은 brief 가 허용한 2박자 후보다.
   - 위젯(`ios/widget-today-small`)의 표시 배율은 .5 다. 센터 배지 패널이 아니라 해당 없음.
6. **쓰는 곳이 0인 코드**(후속 정리, 1회차 그대로):
   - 모듈 `components/ui/{Button,MacWindowShell,VisuallyHidden}.tsx` · `lib/moments.ts`(+test).
   - 엔진 row 갈래만 쓰는 `FloorLight` · `Tile` · `Gridlines` 와 globals `.floor-light` · `[data-glow]`.
7. 390 문서 높이는 9,307px(11 화면)이다. brief 에 390 목표는 없다.
8. **표식**: `docs/v2/` 에 `.fix21-done` · `.fix2121-done` · `.purple21-done` · `.scenes21-done` · `.verify2121-done` 이 있고, 그 밖에 `.v21-css-done` 하나가 더 있다. 마지막 것은 brief §6 이 정한 purple 의 CSS 계약 표식이라 `*21-done` 꼴이 아니다. 리드가 지울지 정한다.
9. 하네스 T13 의 'KB' 는 KiB 다(400×1024). 첫 화면 283,624B 는 10진 400,000 · 360,000 둘 다 안이다.

## 7. 캡처 — `/Users/yesung/check/landing/.scratch/verify21/shots/`(데브, 개발 표시기 숨김, 이번 회차 23:42–23:43 에 새로 찍음)

- **1440×900**
  - 히어로 t=3s: `1440-hero-t3s.png`
  - 장면(조립 끝 + 1.5s, f-message 는 + 3s = 읽음 판): `1440-scene1-f-timer.png` · `1440-scene2-f-tokens.png` · `1440-scene3-f-message.png` · `1440-scene4-f-rhythm.png` · `1440-scene5-f-games.png` · `1440-scene6-f-iphone.png`
  - 설치 · FAQ · 아웃트로: `1440-install.png` · `1440-faq.png` · `1440-outro.png`
  - 전체: `1440-full.png`(1440×7,938). 나눠 본 것: `.scratch/verify21/r2/full-a.png` · `full-b.png`
- **390 전체**: `390-full.png`(780×18,614 @2x). 나눠 본 것: `r2/390-part1–3.png`
- **감속 1440 전체**: `1440-reduced-full.png`(1440×7,938)
- **WebKit 1440 첫 화면**: `webkit-1440-fold.png`(@2x) · 왕복 뒤 `webkit-1440-fold-after-scroll.png`
- 하네스 캡처: `…/v2accept/out/v21/shots/` · `out/v21-prod/shots/`

## 8. 위생

- 데브 3000: pid 14129/14130 살아 있음, `GET /` 200, 재시작 0회.
- 3101: 내가 띄운 `npm exec next start -p 3101`(64992) + next-server(65011)를 kill 했다. `lsof -i :3101` exit 1 · `pgrep -f "next start"` exit 1 이다. 3100 의 Aingo 서버(42268 LISTEN)는 그대로다.
- 남은 프로세스: `pgrep -f ms-playwright` exit 1(내 브라우저 0) · 내 node 스크립트(probe2 · tab2 · run · textlen) 0. Aingo 쪽 프로세스는 건드리지 않았다.
- `git -C /Users/yesung/check status --short` = `?? landing/` 한 줄.
- landing/ 안에서 이 회차에 내가 만든 · 고친 파일:
  - `.scratch/verify21/r2/**`(probe2.mjs · summ.mjs · tab2.mjs · probe/ · logs/ · r1-harness/ · after.txt · summ.json · tab.json · probe.log · 보기용 png).
  - `.scratch/verify21/shots/*`(덮어씀).
  - 이 문서, `.verify2121-done`.
- `npm run build` 는 `.next/` 에만 쓴다. 그 밖에 landing/ 에서 바뀐 파일은 0 이다.
