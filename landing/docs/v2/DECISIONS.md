# DECISIONS v2 — 결정 기록(SPEC v2·PLAN v2 와 어긋나면 이 문서가 이긴다)

작성 2026-10-12 KST · 종합자(설계 워크플로 마지막 단계). 모든 에이전트는 작업 전에 이 문서 → `docs/v2/PLAN.md` → `docs/v2/SPEC.md`(자기 절) 순서로 읽는다.
v1 결정(`docs/DECISIONS.md`, 2026-10-12 08:50)은 아래 §1 에 적은 것만 살아 있고, 나머지는 거부된 v1 과 함께 기록으로만 남는다.

---

## 1. v1 에서 승계하는 결정

| v1 § | 내용 | v2 에서 |
|---|---|---|
| §1 프레임워크 | Next **16.4.0** · React **19.3** · Tailwind **4.3**(`@tailwindcss/turbopack`, postcss 설정 없음) · eslint-config-next 16.4 · TypeScript ^5 · sharp(dev). `cacheComponents` 꺼짐(고전 ISR, `export const revalidate = 3600`, 라우트 핸들러 `fetch(…, { next: { revalidate } })`). `themeColor` 는 `export const viewport`. 이미지 최적화 끔 + `<img>` 직접(`RenderImage`). **이 Next 는 학습 데이터와 다르다** — 코드 전에 `node_modules/next/dist/docs/` 해당 문서를 읽는다 | 그대로. `motion` 은 v2 에서 **제거**(D6) |
| §2 포트 | dev·start 모두 3000 | dev = **3000 그대로**(사용자가 본다). 측정용 prod 서버만 임시 **3100**(D14) |
| §3 Playwright | `@playwright/test` 를 넣지 않는다. `createRequire('/Users/yesung/Aingo/node_modules/')` 의 playwright 1.60(chromium·webkit·firefox), 하네스는 `landing/` 밖 세션 scratchpad. 기존 `…/scratchpad/tools/shoot.mjs` | 그대로. v2 하네스 = `…/scratchpad/v2accept/`(PLAN §7) |
| §4 AssetKey | `data/fixtures.ts` 에 손으로 적은 문자열 리터럴 유니언. generated JSON 은 느슨하게 받고 키가 없으면 개발 경고 + 빈 `<img alt>` | 그대로 + 새 키 11개(SPEC §6.3) |
| §6 공통 금지 | 서브에이전트·스킬 금지, git 상태 변경 금지, 워크트리 금지, `landing/` 밖 읽기만, 임시는 `.scratch/<agent>/`, 프로세스 정리, exit code 판정 | 그대로(PLAN §6·§10) |
| §8 기타 | 센터(서울/부산) FAQ 미게재 · `/api/download` 302 + `no-store`, DMG 기본·`?file=zip` · `AGENTS.md` 그대로 | 그대로 |
| §9 WebKit | WebKit 설치됨 — 통합이 웹킷 캡처·콘솔·HEVC 알파 투명 확인 | 그대로(T3·T7·T13·T17 + ⑧ 사파리 실기) |
| (brief) | 모든 서브에이전트 Opus xhigh · 커밋·배포 금지(사용자 몫) · 결과는 `http://localhost:3000` | 그대로 |

---

## 2. v2 결정(2026-10-12)

### D1. 트립틱은 **세로 스크롤 + 가운데 오브젝트 고정**(brief §5.1 의 "가로 스크럽"과 다름)
- **근거**: ① 사용자 원문은 "스크롤에 따라 어떻게 바뀌는지 다 드러나는 영상이니까 영상 전체를 읽고 참고해"이고, 영상의 트립틱은 **세로**다 — RA §0.2-2·§5.1 이 30fps 전 프레임으로 실증(숫자·캡션·단락은 위로 스크롤, 오브젝트만 고정 교체, 가로 이동 증거 0). brief §2.1 의 "가로 이동"은 그 실증 전의 읽기였고, brief §7-1 이 RA 에게 §2 를 검증·보강하라고 맡겼다. ② 심사 1 의 A mustFix 3(세로 + sticky, 가로 마스크 삭제). ③ 후보 A 자신의 위험 R3 대안·축소판 1순위가 세로판이다. ④ 스크롤 하이재킹 느낌·sticky 조상·svh 변동·되감기 교체의 구현 위험이 가장 큰 항목(J3 난이도 1위)을 없앤다 — 스크럽은 히어로 패럴랙스 한 곳만 남는다.
- **심사 2·3 과의 관계**: 두 심사는 A 가 brief 확정 사항을 지킨 점을 높이 샀지만, 가로를 고집하는 mustFix 는 없었다(J2-A5 는 히스테리시스·길이만, J3 는 "브리프를 따르거나 리드가 세로를 승인한 기록을 남긴다"). 이 항목이 그 기록이다.
- **되돌리는 길**: 리드가 가로를 원하면 A §S2 가로판(트랙 300vw + 가운데 38–62% 마스크)을 `MomentsStage` 의 카드 래퍼에만 얹는다. 무대 DOM·교체·점등 코드는 같다.

### D2. 히어로 = **아이콘 링 돔 + 돔 꼭대기 메뉴바 라벨 + 아잉 도착 1회**
- A 의 팝오버·혜성 3슬롯 루프·펄스·점 격자 삭제(J1-A1·J2-A2·A3·J3-A5). B 의 "돔 아래 진짜 아잉"을 들이되 A 의 서명 "빛의 선 끝에서 렌더가 핀다"를 **1회 도착**으로 합쳤다 — 이것이 v2 의 '기억에 남을 하나'(SPEC §0.1·§1.2).
- 말풍선은 앱 배치 그대로(아잉 머리 위, `CORNER.bubbleAtOut`), 앱 짝(commute-start + "오늘도 화이팅!" + 근무 라벨 00:00)으로만. 근무 라벨은 앱이 근무 중 늘 띄운다(`Sources/check/CheckCharacter3DView.swift:1553` `showsTimer` — 종합자 확인).
- 제품 신호(J1-B4·J2-B2): 실제 메뉴바 라벨 `menubar-0000-lg` 를 돔 꼭대기에(아이콘 링 끝점 자리) + 근무 라벨.
- idle 은 2회 뒤 그 프레임에서 일시정지(WCAG 2.2.2 는 횟수 상한으로 갈음, 멈춤 버튼은 허용 목록 밖 — J3 판정).

### D3. 아웃트로 = **작은 돔(북엔드) + 아잉 idle 2회**, 말풍선·근무 라벨·꾸벅 없음
- 꾸벅 → idle 은 앱에 없는 상태(J1-B5·J2-B6). commute-start 는 히어로가 이미 썼다. 아웃트로 아잉은 앱 아이콘(링 + 라벨 없는 아잉) 구성의 브랜드 마크로 둔다. H2 「메뉴바에, 아잉 하나.」(CB:280)와 맞는다.

### D4. 철거 범위
- TD §1.1 의 **70개** + `components/ui/TimerCapsule.tsx`(근무 라벨은 렌더로) + `motion` 의존성 + `public/fonts/pretendard-800-sub.*` + v1 표식 `docs/.*-done` 5개 + `package.json` `test:store`.
- 유지·이동 9개(TD §1.2) 그대로. 신규 `lib/announce.ts`(TD §2.4) · **`lib/aing.ts`**(v1 `CharacterStage.tsx:121–146` 의 순수 함수 2개를 삭제 전에 복사).
- `data/fixtures.ts`: TD §2.9 + `PANELS`·`LABELS`·`PHONE`·v1 `ALT`·`ANNOUNCE.linkCopied` 삭제(소비처 0 — 종합자 grep), v2 `ALT`·`HERO`·`MOMENTS_TIMING`·`ROW_TIMING` 추가(SPEC §6.3).
- 철거만 따로 반영하지 않는다 — ① 과 ② 를 한 묶음으로(TD §0.1-10).

### D5. 글꼴: Pretendard **500 · 600 · 300 숫자 전용** + JetBrains Mono ASCII, 800 삭제
- 500 = H1·클로징·격자 제목(크고 가볍게, RA §7), 600 = H2·H3·H4·캡션·FAQ(작은 제목이 오히려 무겁게), 300 = 트립틱·격자 숫자(C 접목, ≈2.8KB).
- 500·600 은 같은 글자 집합(소스 스캔 — `check-glyphs.mjs` 수집기 그대로). 300 은 같은 수집기를 `data/figures.ts` 에만 + `0–9 : .`. `.t-number`·`.t-facts` 의 문자열은 `FigureString` 타입으로 강제.
- `check-glyphs.mjs` 는 txt 3벌을 검사(SPEC §9.5). 스캐폴드 때는 `--from-spec`(= `docs/v2/SPEC.md` §3 ∪ 소스), 통합 때 소스 모드로 다시.

### D6. 패키지: **새 패키지 0**, `motion` 제거
- 움직임은 CSS 전이 + CSS scroll-driven + IntersectionObserver 로 충분하다. Playwright 는 저장소 밖(§1 v1 §3).

### D7. 스크럽 · 리빌 구현 방식
- **스크롤 리스너 0개.** 히어로 돔 패럴랙스 = CSS `view-timeline` + `animation-timeline`(desk·감속 아님, `@supports` 미지원(파이어폭스)은 정적). 트립틱 활성·engaged · 행 문턱 · GlowGate · 내비 배경 = IntersectionObserver.
- 트립틱 교체 문턱은 앞 .55 / 뒤 .62 의 두 줄(히스테리시스), 순수 함수 `nextActive()` + `isEngaged()` 를 `node --test` 로 고정.
- 행 리빌은 **1회**(`useRevealOnce`, 문턱 68svh). 바닥 빛(GlowGate)만 양방향.
- 감속 모션·JS 없음은 **CSS 로 최종 상태**(`.js` 클래스 아래에만 '시작 전' 상태) — 하이드레이션 어긋남 0.

### D8. OG 재촬영 장면
- 1440×900 · **감속 모션 컨텍스트**(도착 뒤 상태가 결정적: 포스터 + 말풍선 + 근무 라벨) · 내비 제외 · 자르기 (0, 라벨 위 − 40, 1440, 756) → 1200×630. alt 는 SPEC §8. `app/opengraph-image.png`·`.alt.txt`·`lib/site.ts` `OG_IMAGE.alt` 를 통합이 함께 바꾼다.

### D9. iOS 공유 시트('Mac 링크 보내기') 삭제, `DownloadCTA` 를 server 컴포넌트로
- 허용 목록 밖 도구(J1-A5·C). iOS: 내비 = App Store 알약, 히어로·아웃트로 = 아무것도 안 그림(옆 배지가 맨 앞), 설치 = DMG 링크 그대로(설치 절은 Mac 안내를 보인다).

### D10. App Store 공식 배지는 히어로 · 설치 · 아웃트로 3곳
- CB:69·CB:241·CB:282 가 세 자리에 배지를 둔다. `docs/asset-manifest.md` 의 "페이지당 하나"는 원본 규칙 `A/v3/brand/manifest.json` 의 **"영상당 하나"**를 옮긴 것이라 웹 페이지에는 적용하지 않는다(종합자 확인). 수정·기울이기·애니메이션 금지, 높이 ≥ 40, 여백 = 높이/4 는 그대로.

### D11. v2 미사용 에셋과 `AssetKey` 는 남긴다
- SPEC §9.7 의 출력들은 페이지가 요청하지 않아 무게에 들어가지 않는다. 레시피·검증 목록·`AssetKey` 를 함께 지워야 하는 일(TD §6)이라 v2 범위 밖 — 후속 정리.

### D12. 이름 맞춤
- FAQ 제목 「자주 묻는 것.」(CB:252) = 내비 링크 "자주 묻는 것". 내비 링크 셋 = 기능(`/#features`)·설치(`/#install`)·자주 묻는 것(`/#faq`). 트립틱에는 sr-only 절 제목을 두지 않고 카드 캡션을 `<h2>` 로(J3-A3 — 신규 문구 0).

### D13. 보라 면적 예산(C 접목)과 조정 손잡이
- 측정 = HSV `H 245–295° · S ≥ .35 · V ≥ .30` 픽셀 비율(1440×900 캡처). 하한: 히어로 3% · 트립틱 2% · **행 1%**(J1) · 아웃트로 2% · 조용한 절 0.02%. 상한 12%. 표는 SPEC §2.9.
- 행이 1% 를 못 넘으면 `.floor-light` 중심 α 만 .34 → .40 → .46 으로 올린다(다른 곳에 보라를 더하지 않는다).
- 글로우는 화면당 하나 — GlowGate 조건은 SPEC §2.9 표.

### D14. 수용 테스트의 위치와 서버
- 하네스 `…/scratchpad/v2accept/`(저장소 밖). 동작·모양 = 데브 3000. 예산(T13) = `npm run build && npx next start -p 3100` 임시 서버 — 측정이 끝나면 즉시 kill 하고 `lsof -i :3100` 비어 있음을 확인한다. 3100 은 한 번에 하나만(통합 · 리뷰 perf-a11y · 재검증 순서로만 쓴다).

### D15. 단계 표식 파일
- `docs/v2/.{teardown,contracts,fonts,core,assets,primitives,verify,hero,moments,rows-a,rows-b,facts-install,faq-outro,integration,repair}-done`. v1 의 `docs/.*-done` 은 ① 에서 지운다. v2 표식은 통합 마지막에 지운다.

### D16. 숫자는 렌더나 데이터에서만
- 근무 라벨 00:00 = 렌더(`ui/timer-00-00`), HTML 숫자 합성 금지(`TimerCapsule` 삭제). 숫자 격자 30.1MB(0.3.49) = `installChoice(getRelease(), RELEASE_FALLBACK).mb`(하드코딩 금지). `RELEASE_FALLBACK` 은 0.3.49 값(dmg 30,054,068B "30.1" · zip 28,343,288B "28.3")으로 core 가 ② 에서 갱신. 트립틱·격자 숫자 = `FIGURES`.

### D17. 크롭은 센터 배지가 확대되지 않게
- 콕·토큰·리그 패널은 아바타 열을 뺀 조각(`poke-slice`·`token-slice`·`league-slice`, 왼쪽 28px 페이드). 미니게임 창(.78pt 축소)의 작은 배지는 허용(CB:293 "크게 보이지 않는 크롭"). 감사는 assets(②)·통합(⑤) 두 번.

### D18. 0.3.49 반영(brief §1 갱신, 2026-10-12 18:11)
- 릴리스 기준값: **v0.3.49** `aing-check.dmg` 30,054,068B = **30.1MB** · `aing-check.zip` 28,343,288B. 화면 값은 `getRelease()` 서버 렌더, `RELEASE_FALLBACK` 도 이 값(core 가 ② 계약 때).
- 업데이트 문장은 설치 경로를 가르지 않는다: **「새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. 지금 업데이트 한 번이면 설치하고 다시 켜져요.」**(DMG 설치본도 앱 안에서 새 DMG 를 받아 공증·서명·버전을 검증한 뒤 스스로 교체 — 커밋 3545607). v1 S11 의 "DMG로 받았다면 새 DMG를 받아 덮어쓰면 돼요" 는 폐기(과도기 안내는 `docs/team-install.md` 몫). brew 명령은 `brew update && brew upgrade --cask aing-check`.

---

## 3. brief 와 다르게 정한 것(한눈에)

| brief | v2 | 근거 |
|---|---|---|
| §5.1 트립틱 "가로 스크럽" | 세로 + 고정 오브젝트 | D1 |
| §3 눈썹 칩 "히어로 위 정도" | 기능 절 제목 위(페이지에 하나) | 레퍼런스의 칩 자리(RA §0.2-6) + 히어로를 '큰 것 하나'로(J1-A1) |
| §5.1 "스크럽 2곳까지" | 1곳(히어로 패럴랙스) | D1·D7 |
| §5.2 "아웃트로 commute-end 꾸벅 → idle" | idle 만 | D3(앱에 없는 상태) |
| §1 숫자 후보 "위젯 2종" | 숫자 격자에서 제외 | CB:191 "넷"과 충돌 — 확인 전 |

---

## 4. 사용자 · 리드 결정 대기(기본값으로 진행)

1. 공개 범위(CB §13-2: 가입 폼의 센터 필수 칸, 앱 사용자 전체 한 판) — 랜딩은 그대로 진행, 센터 FAQ 미게재.
2. 저작권 표기 "© 2026 아잉체크"(판매자명으로 할지 — CB:284).
3. 위젯 수(2 ↔ 4) — 숫자 격자 밖.
4. DMG 서명·공증·스테이플 확인 전 "경고 없이 열려요" 금지(CB §13-1, 메모리 '공증 스크립트가 실패를 삼킨다').
5. 신규 문구 승인(SPEC §1.4.3).
6. 트립틱 방향(D1)·아웃트로(D3) — 기본값은 이 문서대로.

### D19. 리드 결정(2026-10-12 19:30, ④ 진행 중 — requests/rows-a.md §1·§2, requests/core.md §1·§3, requests/primitives.md 에 대한 답). 통합(⑤)이 반영한다
1. **행 바닥 빛 — 옵션 (b) 채택 + 하한 0.8%.** `.floor-light` 를 중심 α **.55**, 55% 지점 **.20**, 높이 **160px**, 폭 **렌더 폭 × 1.3** 으로 키운다(globals.css, 통합이 수정). rows-a·rows-b 데이터의 `floor.top` 은 **+40px** 까지 허용(±8px 공차 예외 — 이 항목으로 승인). SPEC §2.9 V3–V5 의 하한은 **1.0% → 0.8%** 로 고치고(T9 도 같이), 상한 6% 유지. 근거: 사용자 요구 "다크와 보라의 조화"를 지키려면 하한을 0.4% 로 내리는 (a) 보다 빛을 키우는 쪽이 맞다. 다른 곳에 보라를 더하지 않는 D13 원칙은 그대로.
2. **R1 아래 페이드 40 → 24px** 승인(rows-a.md §2) — "안 읽음 1" 이 또렷해야 R1 의 유일한 숫자 움직임이 읽힌다.
3. **390 폭 내비 CTA** = SPEC §S0 대로 **"Mac용 다운로드"**(→ /api/download). iOS 는 App Store 알약. v1 의 "설치" 알약은 쓰지 않는다(core.md §1 (b) 채택). 내비 outline 톤도 SPEC 대로 `--line-strong` 테두리 + ink-1 글자(core.md §1 (a) 채택).
4. **포스터 preload** 는 layout 이 아니라 **page.tsx 에서 react-dom `preload()`** 로(core.md §3) — /licenses 의 "preloaded but not used" 경고를 없앤다.
5. **tab(768) 폭의 세로 격자선** = **없음(스파인만)**. SPEC §4 의 "10% 만" 은 스파인 x 32 와 어긋나 지그재그가 생기므로 폐기. 1024 이상만 10/50/90.
6. **LicensesNav 건너뛰기 링크** 는 NavShell 과 같은 방식으로 고친다(core.md §2) — faq-outro 가 못 했으면 통합이.
7. **조립 규칙 @layer 밖 문제**(primitives.md §1-1): 행 말풍선은 앱 문법(120ms 선형 + .96→1 200ms)이어야 하므로 globals 의 `.row-item` 규칙에 말풍선 예외(`.row-item[data-kind="bubble"]`)를 두는 쪽으로 통합이 고친다. R5 폰 화면 페이드(§1-2)는 선택.
8. 기능 절 제목 높이 385px(SPEC 360) 은 허용(문서 높이 여유 안). 통합이 T5 의 9,300–9,900 안인지 확인.

### D20. 리드 결정(2026-10-12 19:30, requests/rows-b.md·faq-outro.md 에 대한 답). 통합(⑤)이 반영한다
1. **P0 — WebKit 에서 기능 행 캔버스가 뒤집히고 커지는 문제**(rows-b.md §0: FeatureRow.tsx 의 `--k: min(1, tan(atan2(46vw, 576px)))` 를 WebKit 이 라디안으로 읽음). 통합이 **가장 먼저** 고친다 — 제안대로 `@property --kw { syntax: "<length>"; inherits: true; initial-value: 0px }` 를 등록하고 `--kw: 46vw` 를 거쳐 `--k: min(1, tan(atan2(var(--kw), 576px)))` 로. 고친 뒤 Chromium·WebKit 모두 1440 → 1 · 1024 → .818 · 800 → 1 인지 T17 옆에 단언을 추가한다(하네스 T8 에 WebKit 1440 캡처 1장).
2. **행 바닥 빛의 폭 기준**은 주 렌더 폭이 아니라 **캔버스 안 렌더들의 합집합 폭**(R5 = 폰 + 위젯 + 타일 ≈ 540px). D19-1 의 α .55 · 높이 160 · ×1.3 과 함께 적용. 그래도 R5 가 0.8% 에 못 미치면 **그 행만** `--floor-alpha: .60` 같은 행별 변수로 올린다(다른 행·다른 곳에 보라를 더하지 않는다).
3. 슬라이스 왼쪽 28px 페이드가 첫 글자를 흐리는 문제(rows-b.md P2): 페이드를 **16px** 로 줄이고 크롭 왼쪽 여백은 그대로 둔다(글자가 3px 안쪽에서 시작하므로 16px 이면 첫 음절 중심부는 90% 이상 불투명). rows-a 의 poke-slice 도 같게.
4. 아웃트로 다운로드 버튼 접근 이름은 **"Mac용 다운로드"** 그대로(크기 없음, 서명 변경 안 함). 크기는 히어로·설치 절 버튼이 말한다.
5. FAQ 높이 전이·아웃트로 진입 페이드를 globals 로 옮기는 것(faq-outro.md §1–2)은 **선택** — 통합이 시간이 남을 때만.
6. 아웃트로 725px(와이어 720) 허용. 문서 높이 9,300–9,900 범위는 T5 가 판정.

### D21. 리드 결정(2026-10-12 19:32, requests/facts-install.md 에 대한 답). 통합(⑤)이 반영한다
1. **설치 절 높이(989 vs 760)**: 옵션 (b)+(c) — 팀 참여 3걸음을 **iPhone 열 아래**(오른쪽 열, 내용이 적은 쪽)에 세로로 붙여 두 열의 높이를 맞추고, 절 아래 패딩은 **96** 으로. 업데이트 한 줄은 두 열 아래 전폭 그대로. 그래도 T5 의 문서 높이 상한 9,900 을 넘으면 SPEC §3.0 의 줄이는 순서(행 560 → 520 …)를 그대로 적용한다.
2. **check-glyphs·subset-fonts 의 소스 스캔은 `*.test.ts`·`*.test.tsx`·`*.test.mjs` 를 제외**한다(테스트 문자열은 배포되지 않는다). 통합이 scripts 를 고치고 `npm run subset` → `check-glyphs` 0 을 확인한다.
3. 숫자 격자 "왼쪽 제목 + 4×2" 는 **1280 이상**에서만, 768–1279 는 제목 위 + 4×2 로(SPEC §4 의 1024 칸 156 은 실측상 넘침). SPEC §4 표를 통합이 이 값으로 고친다.
4. 390 iOS 에서 iPhone 묶음을 시각 순서로만 앞세우는 `.order-ios-first`(Tab 순서는 DOM) 는 SPEC 대로 유지.

### D22. 리드 결정(2026-10-12 19:40, requests/hero.md 에 대한 답). 통합(⑤)이 반영한다
1. **AingClip 층 교체 때 아잉이 2–4프레임 사라지는 문제(hero.md §1) = P1.** 통합이 primitives 의 AingClip 을 제안 diff 대로 고친다 — 나가는 층(포스터 또는 once 영상)은 **들어오는 영상이 첫 프레임을 실제로 그린 뒤**(requestVideoFrameCallback 또는 playing+timeupdate 첫 발생)에만 숨긴다. 포스터→commute-start, once→idle 두 교체 모두. 고친 뒤 hero 의 gap.mjs(.scratch/hero/) 로 공백 프레임 0 을 확인하고, 아웃트로(포스터→idle)에도 같은 효과가 있는지 본다.
2. **빛 한 줄과 글 상자 간격은 SPEC·PLAN 의 12px 가 정본**(오케스트레이터 프롬프트의 24px 는 오기). 실측 17.7–19px 이면 통과. 돔·라벨·H1 기하는 바꾸지 않는다. comet-path.test.ts 의 단언 12px 유지.
3. App Store 배지 높이는 모든 뷰포트에서 48(PLAN §4.1) — SPEC §9.1 의 "phone 44" 를 48 로 고친다(통합).

### D23. 리드 결정(2026-10-12 19:42, requests/moments.md 에 대한 답). 통합(⑤)이 반영한다
1. **트립틱 무대 빛 V1 0.02%(하한 2%)** — globals `.obj-glow` 의 α 를 moments.md §1 의 **후보 C 값**(같은 violet, α 만 올림; 실측 V1 3.67% · 오브젝트 3 4.38%)으로 바꾼다. 빛의 중심이 렌더 뒤에 가려지므로 바깥 고리와 발밑 웅덩이가 V ≥ .30 을 넘게 하는 값이어야 한다. 상한 8% 안인지 T9 로 확인.
2. WebKit 768·1024 의 가로 넘침(moments.md §3)은 **D20-1 의 atan2 수정으로 함께 풀린다** — 고친 뒤 WebKit 390/768/1024/1440 에서 scrollWidth === innerWidth 를 T5 에 추가.
3. 1024 폭 트립틱 오브젝트 배율 **.71**(SPEC ×.85 는 글과 겹침) 허용 — SPEC §4 표를 통합이 고친다.

### D24. 리드 결정(2026-10-12 19:52, 하네스가 올린 T13 정의 충돌에 대한 답). 통합(⑤)·재검증(⑧)이 따른다
1. **첫 화면 예산(≤ 400KB)은 SPEC §5.1 정의대로 `load` 이벤트까지의 전송 바이트**로 판정한다. PLAN §7.2 T13 의 "load + 1s" 는 정보로만 기록한다(AingClip 이 load 뒤 afterLoadIdle 에 commute-start 를 받는 것은 설계다). 대신 **`load` 이전 영상 요청 0** 은 그대로 단언.
2. 문서 높이 9,977px(상한 9,900)는 D21-1(설치 절 팀 3걸음 재배치)로 먼저 줄이고, 그래도 넘으면 SPEC §3.0 순서(행 560 → 520 …).
3. T16 의 OG alt 는 통합이 재촬영하면서 SPEC §8 문장으로 바꾼다(하네스 단언 유지).

### D25. 리드 결정(2026-10-12 20:30, 통합 보고의 열린 문제에 대한 답). 수리(⑦)가 반영한다
1. **첫 화면 예산 여유 2.5KB 는 부족하다.** 기능 행 캔버스의 렌더 `<img>` 는 **행이 뷰포트에서 1,200px 안으로 들어올 때 마운트**(useNearViewport, rootMargin 1200px)하고 `<noscript>` 폴백을 둔다 — 통합이 히어로 말풍선·근무 라벨에 쓴 것과 같은 패턴. 목표: 헤드리스 크롬 측정에서 첫 화면 **≤ 360KB**(여유 40KB). assets.json·sequences.json 을 클라이언트 번들에서 빼는 일은 하지 않는다(범위 밖).
2. `--kw` initial-value **576px**(스케일 폴백 1) 허용 — D20-1 의 0px 보다 안전하다. 행 바닥 빛 +40·행별 α 미적용도 V3–V5 가 이미 통과하므로 허용.
3. 통합의 추가 변경(행 `overflow-x: clip`, 390 바닥 빛 ×.846, 데스크톱 행의 10/50/90 격자) 승인. 단 sticky 조상 규칙(T17)은 `#moments` 와 그 조상에만 해당하므로 행 안의 clip 은 무해함을 재검증이 확인.
4. 사파리 실기 HEVC 확인은 사용자 몫으로 남긴다(⑧ 은 WebKit 포스터 폴백·콘솔 0 만 본다).

### D26. 리드 결정(2026-10-12 20:45, reviews/copy.md 의 리드 판단 요청에 대한 답). 수리(⑦)가 반영한다
1. **설치 절의 업데이트 문장은 하나만.** brew 블록의 CB:236 문장("업데이트는 brew update && … 한 줄이고, 끝나면 앱이 다시 켜져요.")을 **뺀다**. 맨 아래 D18 문장이 brew·DMG 모두를 말한다(앱 안 [지금 업데이트]가 brew 설치도 처리). "GitHub Releases에서 zip으로 받기" 링크는 유지.
2. **iOS 히어로 메타**(P1): data-platform=ios 면 "macOS 14 이상 · 무료" 대신 **"iOS 18 이상 · 무료"**(CB:243), "brew로 설치" 링크 숨김. DownloadCTA 와 같은 variant 로.
3. **말풍선 접근성은 전부 `aria-hidden`**(히어로·트립틱·행 동일 — 말풍선은 페이지 크롬이고 같은 사실이 본문에 있다). SPEC §S4 의 "bubbleText 를 alt 로" 는 폐기, §1.4 가 이긴다.
4. iOS 에서 아웃트로의 "brew 명령 복사" 버튼 숨김(D9 의 iOS 규칙과 일관).
5. App Store 배지 alt = 배지 글자 그대로 **"App Store에서 다운로드 하기"**, QR alt = "App Store 아잉체크 페이지로 가는 QR 코드" 유지, CommandBox 의 "⌘C로 복사하세요" 힌트는 **삭제**(버튼 "복사"가 충분).
6. 390 리드 줄바꿈은 자연 줄바꿈 유지(SPEC §S1). 변경 없음.

### D27. 리드 결정(2026-10-12 20:50, reviews/design.md 의 P1 네 건에 대한 답). 수리(⑦)가 반영한다
1. **빛 한 줄 머리가 안 보이는 문제** — 리뷰 제안대로 머리를 **흰색 5px + 이중 글로우**, 타이밍은 **선형**(ease-out 금지 — 처음 180ms 에 63% 를 달려 버린다), 림 핵에서 **5px 안쪽**(RIM_CORE_INSET 5)으로 띄운다. 꼬리는 그대로. 수리 뒤 40ms 프레임 시트로 머리가 라벨에서 아잉까지 내내 보이는지 확인.
2. **숫자 격자 → 설치 → FAQ 세 화면이 평평하다**(V6 0.19 · V7 0.12 · V8 0.06%) — 이것이 v1 거부 사유 "너무 다크하게만" 의 재발이므로 고친다. (a) `.seam`·`.tick`·`.faq-open-line` 에 `.horizon` 과 같은 헤일로(box-shadow 18px rgba(126,94,250,.45)) (b) 열린 FAQ 행의 삼각형은 `--violet-bright` (c) **10% 스파인 선을 조용한 절까지 이어 그린다**(1px, rgba(126,94,250,.35) 그라디언트 — 기능 행에서 끝난 선이 숫자 격자·설치·FAQ 왼쪽을 지나 아웃트로 돔에서 끝남; 선은 구조물이라 GlowGate 대상 아님) (d) 숫자 격자 제목 아래 안심 한 줄 앞에 2px 보라 틱 하나. **조용한 절의 하한을 0.02% → 0.3%** 로 올린다(V6·V7·V8, 상한 3% 유지). 글로우(라디얼)는 여전히 두지 않는다 — 화면당 글로우 ≤ 1 규칙 유지.
3. **슬라이스 잘린 가장자리** — 잘린 왼쪽 변은 **직각**(둥근 모서리 0), 머리띠(헤더 줄)만 더 긴 '노치' 마스크로 '◀' 조각을 가리고, 행 글자는 D20-3 의 16px 페이드로. 첫 글자가 잘리는 크롭(ㅊ르기·각자 목표)은 크롭 x 를 왼쪽으로 12px 넓혀 다시 굽는 쪽이 낫다면 assets 레시피를 고쳐 다시 굽는다(SPEC §9.2 표 갱신).
4. **히어로 → 트립틱 경계**에 `--line` 헤어라인 추가(돔 안 검정이 bg-0 와 직각으로 만나지 않게).
5. design.md 의 P2 는 수리가 P0·P1 뒤 시간이 남을 때만.

### D28. 리드 결정(2026-10-12 21:05, reviews/motion.md 의 P1 네 건 승인). 수리(⑦)가 반영한다
1. 빛 한 줄은 **commute-start 가 재생 가능해진 뒤에만 출발**(AingClip onOnceReady → HeroStage). 마감 2.5s 안에 준비되지 않으면 빛·폴짝·말풍선 전부 생략하고 근무 라벨만(SPEC §S1 그대로).
2. 목록 모드(tab·phone·감속)의 카드별 무대 빛은 **useBand([.3,.7]) 로 한 번에 하나만**(InlineMoment 클라 섬). JS 없음은 CSS 로 켜 둔다.
3. 빛 한 줄 타이밍 **두 구간**(림 구간 등속 ≈300ms → 착지 구간 ease-out) + 흰 머리 이중 글로우 + 꼬리 시작 불투명 .35 **승인**(D27-1 의 구체화). SPEC §S1 표의 "1000ms ease-out" 을 이 값으로 통합/수리가 고친다.
4. 빛 한 줄 도중 히어로를 벗어나면(보이는 비율 < .35) **도착을 생략**하고 done 처리(돌아와도 다시 하지 않음, 근무 라벨만).
