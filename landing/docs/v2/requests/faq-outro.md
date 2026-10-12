# requests — faq-outro(④ 섹션)

작성 2026-10-12 · faq-outro. 공용 파일은 고치지 않았다. 아래 둘(1·2)은 **자기 파일 안 Tailwind 변형으로 우회해 지금 동작한다** — 통합이 globals 로 옮길지 판단하면 된다(옮기지 않아도 수용 조건은 초록).

## 1. `app/globals.css` — FAQ 높이 전이(SPEC §S7 "높이 전이는 `::details-content` + `interpolate-size` 지원 브라우저만")

**무엇**: globals 에 FAQ 높이 전이 규칙이 없다(디스클로저 회전만 있음). 지금은 `components/faq/Faq.tsx` 의 `HEIGHT_TRANSITION` 상수(Tailwind `motion-safe:supports-[interpolate-size:allow-keywords]:details-content:…`)로 건다. 시간·커브는 globals 변수(`--t-resize` · `--ease-out`). 크로뮴 실측: 2번을 열면 90ms 에 `::details-content` 71px / 내용 78px(전이 중), 감속 컨텍스트 `transition-duration: 0s`. 사파리(interpolate-size 없음)는 즉시 열고 닫음.
**왜 옮기나**: §2.8 "색·빛·움직임은 globals 변수·클래스로" — 움직임 규칙이 섹션 파일에 흩어지지 않게.
**제안 diff**(`@media (prefers-reduced-motion: no-preference)` 블록 안, `.disclosure::after` 전이 옆):
```css
  @supports (interpolate-size: allow-keywords) {
    details[name="faq"] { interpolate-size:allow-keywords; }
    details[name="faq"]::details-content { height:0; overflow:clip;
      transition:height var(--t-resize) var(--ease-out), content-visibility var(--t-resize) allow-discrete; }
    details[name="faq"][open]::details-content { height:auto; }
  }
```
옮긴 뒤 `Faq.tsx` 에서 `HEIGHT_TRANSITION` 상수와 그 사용 한 곳을 지운다. `FaqHash` 의 딥링크 순간 동결(`details[name="faq"]::details-content{transition:none!important}`)은 그대로 맞는다.

## 2. `app/globals.css` — 아웃트로 내용 페이드(SPEC §S8 "절이 45% 보이면 1회: 내용 불투명 0→1 `--t-fade` 600ms 선형")

**무엇**: globals 에 '시작 전' 숨김 규칙이 없다. 지금은 `components/outro/OutroStage.tsx` 의 상자 클래스
`transition-opacity duration-[var(--t-fade)] ease-linear motion-reduce:transition-none motion-safe:[.js_&:not([data-shown]):not(:focus-within)]:opacity-0` 로 건다.
(`.js` · 감속 아님 · `data-shown` 없음 · 안에 포커스 없음일 때만 0 — JS 없음·감속은 처음부터 보임, 키보드로 버튼에 먼저 닿아도 보임.)
**제안 diff**(같은 no-preference 블록, 히어로 규칙 아래):
```css
  /* 아웃트로: 절 45% 진입(data-shown) 전 내용 숨김 — OutroStage 가 1회 붙인다 */
  .js [data-outro-stage]:not([data-shown]):not(:focus-within) { opacity:0; }
  [data-outro-stage] { transition:opacity var(--t-fade) linear; }
```
옮긴 뒤 `OutroStage.tsx` 의 `STAGE` 상수에서 마지막 두 줄(transition·motion-safe 변형)을 지운다.

## 3. 알림 — 계약과 글자가 다른 곳(서명은 PLAN §3.10 그대로: `Faq()` · `Outro()` named export, server)

- `#outro` 가 `--aing-w` 를 **절 안에서만** 다시 정한다(desk·tab `clamp(184px, 24svh − 16px, 220px)` · phone `clamp(170px, 24svh, 220px)`, SPEC §S8). `AingClip width="var(--aing-w)"` 와 globals `.dome-pool`(폭 × 1.6)이 같은 값을 읽게 하려고. 히어로의 `--aing-w` 에는 영향 없음(상속 범위가 `#outro` 뿐).
- 아웃트로 아잉의 `inView` 는 **아잉 상자 자신이 35% 보이는지**(절 전체가 아니라) — 절이 45% 보여 `start` 가 와도 1440×900 에서는 아잉이 아직 화면 아래라, 보이기 시작할 때부터 idle 2회를 센다(SPEC §5.5 "화면 밖이면 일시정지").
- 아웃트로 `DownloadCTA` 에 `ariaLabel` 을 주지 않았다(접근 이름 = "Mac용 다운로드"). `Outro()` 는 props 가 없어 릴리스 크기를 모른다 — 히어로처럼 "…, aing-check.dmg 30.1MB" 를 원하면 `page.tsx` 에서 `Outro({ release })` 로 넘기는 서명 변경이 필요(PLAN §3.10 이 막아서 하지 않음).
- 아웃트로 복사 버튼 `aria-label` = 보이는 글자 "brew 명령 복사"(WCAG 2.5.3 이름 속 라벨 — 설치 절의 "brew 설치 명령 복사" 를 쓰면 보이는 글자가 이름에 연속으로 들어가지 않는다).
- 가로 줄의 App Store 배지에 `tab:-my-3 desk:-my-3`(배지 여백 12 를 줄 높이에서만 뺌 — 여백은 비어 있고 이웃이 들어오지 않음: 리드와 28). phone 세로 쌓기에서는 여백 그대로. 1440×900 실측: H2 196–339 · 리드 359–391 · 버튼 줄 419–467 · 아잉 467–709 · 절 725(와이어 720 — 아잉 상자 위 27.7% 빈 칸을 버튼 줄과 5px 겹치지 않게 둔 차이).
- `/licenses` 내비(`LicensesNav`)를 첫 페이지 내비와 같은 틀로 맞췄다: `--gutter` · 3열 그리드(워드마크 / 가운데 링크 / CTA) · `t-wordmark` · 아이콘 24(phone 22) · phone 의 '설치' 는 이제 `DownloadCTA placement="nav" installHref="/#install"` 의 phone 분기가 그린다(전용 캡슐 삭제). core 요청 §2(건너뛰기 링크 `focus:px-4 focus:py-2 focus:[clip:auto]`)·워드마크 `t-wordmark` 반영 — Tab 첫 대상 실측 높이 30 · `clip:auto`. core 요청 §1(b)대로 `DownloadCTA` nav 의 phone 분기가 바뀌면 `/licenses` 도 같이 따라간다.
- 푸터·`/licenses` 본문은 `max-w-[1440px] mx-auto` 를 걷고 `px-[var(--gutter)]` 만 둔다 — v2 `--gutter` 가 이미 셸(1600) 가운데 정렬을 품고 있어서(1440 에서 176, 내비·FAQ 와 같은 선).

## 4. 다른 소유자 파일의 tsc 오류(고치지 않음)

- 작업 중간 한 번 `components/hero/Hero.tsx(20,27): error TS2307: Cannot find module './HeroStage'` 가 났다(hero 가 작업 중이던 파일 — ④ 동시 진행). 마지막 `npx tsc --noEmit` 은 exit 0. 내 파일에서 나는 오류는 0.
