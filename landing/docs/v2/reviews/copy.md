# 리뷰 ⑥ — 카피·사실 렌즈(review-copy)

작성 2026-10-12 KST · review-copy(읽기 전용 — 코드는 고치지 않았다). 대상 = 데브 http://localhost:3000(재시작 0) + 소스(`app/ components/ data/ lib/`).
읽은 것: DECISIONS D1–D25 → PLAN §0·§2·§4·§6·§9·§10 → SPEC §1·§2.3–2.4·§S0–§S9·§6·§8 → `docs/content-brief.md`(CB) 전문 → `integration-report.md` · `.scratch/integration/shots/*`(24장).
측정 도구(저장소 밖 아님, gitignore 된 `.scratch/review-copy/`): `dom.mjs`(크롬 4컨텍스트 — desk 1440 · 감속 1440 · phone 390 · iOS UA 390, 맨 아래까지 스크롤 뒤 텍스트 노드·alt·aria-label·title·meta·JSON-LD 수집) · `cbmap.mjs`(DOM 문장 ↔ CB 줄 글자 대조) · `faqcmp.mjs`(FAQ v2 ↔ v1 스냅숏 `.scratch/landing-v1-2026-10-12.tgz` ↔ CB:254–273) · `forbid.mjs`(금지어·표기·인물) · `lines.mjs`/`lines-webkit.mjs`(헤드라인 실제 줄 수 — 크롬 390/768/1024/1280/1440 · 웹킷 390/1440) · `leadwrap.mjs` · `iosshot.mjs`(증거 `out/ios-390-{hero,install,outro}.png`).

**결과: P0 0 · P1 1 · P2 6.** 카피·사실 렌즈의 수용 항목 12개는 전부 초록이다(§1). 결함은 SPEC 이 정하지 않은 iOS 문맥과 SPEC 안의 중복·모순에서 나왔다(§2).

---

## 0. 잘 된 점(3줄)
- 화면의 모든 문장이 CB 글자 그대로다 — 표본 82개(본문·버튼·라벨 62 + FAQ 20) 불일치 0, 헤드라인 `<br>` 9곳과 실제 줄 수가 SPEC `lines` 와 크롬 5폭·웹킷 2폭에서 모두 같다.
- 금지어 21개 0건(4컨텍스트 + `/licenses`) · 제품명·근무 중·팀 코드·울트라 표기 위반 0 · "아잉체크(aing-check)" 정확히 1회 · 인물은 v4 가상 세트만.
- 숫자 격자 30.1 은 서버 값이다(`/api/release` → `source:"github"`, `installChoice(getRelease(), RELEASE_FALLBACK).mb`), 하드코딩은 D16 이 허용한 `RELEASE_FALLBACK` 한 곳뿐. D18 업데이트 문장은 글자 그대로이고 옛 문장 잔재는 의미상 0.

---

## 1. 수용 항목별 판정

| # | 항목 | 판정 | 근거(실측) |
|---|---|---|---|
| 1 | 모든 문장 = CB 줄(표본 ≥ 30) | 초록 | 표본 82 — 아래 §1.1 표 62건 + FAQ 10문항 × (질문·답) 20건. `cbmap.mjs` 62/62(1건은 스크립트의 ` / ` 정규화 오탐 — DOM 에 "콕 / 메시지" 그대로 있음), `faqcmp.mjs` 10/10 |
| 2 | 신규 문구는 SPEC §1.4.3 뿐 | 초록(조건부) | 격자 라벨 8 · 단위 6 · 열 라벨 Mac/iPhone · D18 한 줄 · alt(§6.5 15키 글자 그대로) · OG alt = 승인 목록. 그 밖에 화면에 있는 것은 SPEC 다른 절이 정한 것(내비 기능/설치/자주 묻는 것·건너뛰기·`aria-label="주요"` §S0 · 푸터 §S9 · 접근 이름 §S1·§S6 · title/description §8 · 카운터 §S2). **v2 SPEC 어디에도 없고 v1 SPEC(docs/SPEC.md:872·958)에서만 승계된 3건**: 배지 alt "App Store에서 다운로드" · QR alt "App Store 아잉체크 페이지로 가는 QR 코드" · 복사 실패 힌트 "⌘C로 복사하세요" → P2-3·P2-4 |
| 3 | 금지어(SPEC §1.4.1 — 목록은 21개) 0건 | 초록 | `document.body` 텍스트 노드(숨은 것 포함) + innerText + alt·aria-label·title + meta(description·og·twitter) + JSON-LD + noscript, desk·감속·390·iOS 4컨텍스트 각각 0. `/licenses` HTML 0. 소스의 사용자 문자열(주석 제외) 0 — '판돈'은 `rows-a.data.ts:93` 주석에만 |
| 4 | 제품명 표기 | 초록 | '아잉 체크'·AingCheck·Aing-check·AING CHECK 0 · aing-check 는 파일명·명령·CB:229 단계 문장에만 · "아잉체크(aing-check)" 1회(푸터, 4컨텍스트 모두) · 산문 '근무 중'(트립틱 02·FAQ 4·5), '근무중'은 앱 칩을 옮긴 alt 2개뿐(SPEC §6.5 문장 그대로: header-on-lg · poke-slice) · '팀 코드'만(참여코드·초대코드 0) · '울트라'만 |
| 5 | 가상 인물 세트만 | 초록 | DOM: 새벽·구름빵·달토끼·민트별·보리차 + 팀 파도 커피단·아잉 데모팀·종이 공방(CB §11 리그 표). 렌더 속: 호두과자·초코칩·솜사탕(세트 안). 실사용자 0 |
| 6 | 숫자마다 출처 · 30.1 이 서버 값 | 초록 | 격자 8칸 출처 주석 = SPEC §S5 표(`Facts.tsx:26–33`): 0원 CB:21·17 / 14 이상 CB:19 / 18 이상 CB:17·192 / 30.1MB 서버 / 12주 CB:149 / 3종 CB:170·173 / 1:1 CB:116·170·174–175 / 0개 CB:20. 트립틱 00:00·콕.·12주 = 렌더 속 글자. alt 속 숫자(19시간 38분·49%·41점·23점·36시간 40분·3:45:00·23시간 23분·남은 4개·울트라 3)는 렌더를 직접 읽어 대조(webp → png 13장) — 전부 일치. `grep 30\.1` → 실행 코드는 `data/fixtures.ts:160`(RELEASE_FALLBACK, D16 허용)뿐, 나머지는 주석·테스트. `/api/release` = `{"version":"0.3.49","dmg":{"bytes":30054068,"mb":"30.1"},…,"source":"github"}` |
| 7 | 헤드라인 줄바꿈 = SPEC `lines` | 초록 | `<br>` 수: H1 1 · 기능 H2 1 · R1–R5 H3 각 1 · 격자 제목 1 · 아웃트로 1 · 나머지(캡션 3·H4 2·설치·FAQ) 0 = SPEC. 실제 줄 수(Range rect)도 `lines` 수와 같음 — 크롬 390/768/1024/1280/1440, 웹킷 390/1440, 넘치는 꺾임 0 |
| 8 | 설치 업데이트 문장 = D18 · "덮어쓰"·"brew 설치에서만" 잔재 0 | 초록 | DOM `[data-install="update"]` = 「새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. 지금 업데이트 한 번이면 설치하고 다시 켜져요.」 글자 그대로(`data/install-copy.ts:32`). 잔재: 의미상 0. 글자상 5건 — `components/SpritePlayer.tsx:32`·`components/ui/Bubble.tsx:8`·`scripts/subset-fonts.mjs:22` 의 '덮어쓰기'(설정·스타일 덮어쓰기 뜻, 업데이트 문장과 무관) · `components/install/install-copy.test.ts:70·76`(옛 문장이 없음을 단언하는 부정 가드). 'brew로 설치했다면'·'DMG로 받았다면' 0. 옛 문장은 v1 문서(`docs/SPEC.md:917`)·후보 문서(`docs/v2/candidates/C.md:550`)에만 |
| 9 | FAQ 10문항 = v1 문장 | 초록 | `data/faq-items.ts` 10문항이 v1 `components/sections/install-faq/faq-items.ts`(스냅숏)와 CB:254–273 둘 다와 질문·답 글자까지 같음. JSON-LD `FAQPage` 10문항도 같은 문장(파싱 대조 10/10), `SoftwareApplication` 0 |
| 10 | 영문 소문자 라벨 · 대문자 눈썹 0 | 초록 | 계산 스타일 `text-transform: uppercase` 요소 0. 라틴 소문자만으로 된 텍스트 노드는 brew 명령 상자·업데이트 명령 안(`brew`·`update`·`upgrade`·`aing-check`)뿐. 눈썹 칩 1개 = "Mac 메뉴바 앱 · iPhone 앱"(CB:62) |
| 11 | alt 문구 = SPEC §6.5 | 초록 | `data/fixtures.ts` ALT 15키 + 장식 6키가 §6.5 표와 글자 그대로. 말풍선 alt 4개("오늘도 화이팅!"·"민트별님이 콕 찔렀어요!"·"구름빵님: 커피 한잔 해요 ☕️"·"루비 +3!")가 구운 그림 글자와 같음(합성 시트로 확인) |
| 12 | 메타 · OG · title | 초록 | title「아잉체크: 작은 Mac 팀을 위한 메뉴바 근무 타이머」· description = SPEC §8(v1 그대로, `layout.tsx:42–43`) · og/twitter 같은 값 · `og:image:alt` = `twitter:image:alt` = `app/opengraph-image.alt.txt` = `lib/site.ts:13` = SPEC §8 문장. OG 그림을 열어 alt 서술(돔·라벨 00:00·말풍선·H1)과 맞는지 확인 |

### 1.1 DOM ↔ CB 표본(줄 번호 — `cat -n docs/content-brief.md`)
| 자리 | CB | 자리 | CB | 자리 | CB |
|---|---|---|---|---|---|
| H1 출퇴근 기록을, / 메뉴바 하나로. | 64 | R1 라벨 콕 / 메시지 | 123 | 설치 H2 지금, 메뉴바에. | 224 |
| 히어로 리드 두 문장 | 67 | R1 H3 하고 싶은 말은, 메시지로. | 114 | 설치 버튼 aing-check.dmg 다운로드 | 227 |
| Mac용 다운로드(내비·히어로·아웃트로) | 68 | R1 본문 | 116 | 설치 메타 꼬리 | 228 |
| 메타 macOS 14 이상 · 무료 | 68 | R2 라벨 캐릭터 | 126 | 설치 단계 1·2·3 | 229 |
| brew로 설치 | 69 | R2 H3 일한 만큼, 루비. | 128 | 터미널이 편하다면 | 234 |
| 트립틱 01 근무 시작. / 버튼 하나, 메뉴바에서. | 81 | R2 본문 | 130 | brew 명령 · 복사 · 복사했어요 | 235 |
| 트립틱 01 단락 | 82 | R2 H4 + 본문 | 131 | 업데이트는 … 다시 켜져요(명령은 CB:394 정정) | 236 |
| 트립틱 02 콕. / 찔러 부르기. | 114 | R3 라벨 쉬는 시간 | 167 | GitHub Releases에서 zip으로 받기 | 238 |
| 트립틱 02 단락 | 115 | R3 H3 한 판, 쉬어 가기. | 169 | iOS 18 이상 · 무료 / 근무 시작·종료는 맥에서 해요. | 243 |
| 트립틱 03 나만 보는 기록. | 143 | R3 본문 | 170 | 팀 1 가입 | 246 |
| 트립틱 03 단락 앞·뒤 | 144·145 | R4 라벨 순위 | 187 | 팀 2 팀 코드 | 247 |
| 눈썹 칩 | 62 | R4 H3 이번 달 AI 토큰, / 전체 순위판. | 154 | 팀 3 메뉴바 | 248 |
| 기능 H2 같이 켜는 / 근무 타이머. | 66 | R4 본문 | 155 | FAQ 제목 자주 묻는 것. | 252 |
| 기능 서브 | 30 | R4 H4 팀끼리는, 리그로. + 본문 | 100·102 | FAQ 1–10 질문·답 | 254–273 |
| 격자 제목 작은 Mac 팀을 위한 / 메뉴바 근무 타이머. | 29 | R5 라벨 iPhone | 180 | 아웃트로 H2 메뉴바에, / 아잉 하나. | 280 |
| 격자 안심 한 줄 | 199 | R5 H3 이제, / 아이폰에서도. | 182 | 아웃트로 리드 | 281 |
| 푸터 한 줄(정의문 부분) | 29 | R5 본문 · 작은 줄 | 183·185 | brew 명령 복사 | 282 |
| 말풍선 alt 구름빵님: 커피 한잔 해요 ☕️ | 363 | | | | |

---

## 2. 결함(심각도순)

### P1-1. iOS 히어로: App Store 배지 바로 아래에 Mac 요구 사항 "macOS 14 이상 · 무료" + "brew로 설치"
- **파일:줄** `components/hero/Hero.tsx:65–71`(메타 줄) · `components/hero/copy.ts:13–15`
- **재현** 크롬 390×844, `isMobile`·`hasTouch`, UA = iPhone iOS 18 사파리(`data-platform="ios"`), scrollY 0. 증거 `.scratch/review-copy/out/ios-390-hero.png`. 버튼 줄에 보이는 것은 배지 하나(`["App Store에서 다운로드"]`), 바로 아래 메타 = "macOS 14 이상 · 무료\nbrew로 설치".
- **기대 vs 실제** D9·SPEC §6.2 는 iOS 에서 히어로 다운로드 버튼을 그리지 않아 배지가 맨 앞이 되게 했지만 메타 줄의 iOS 처리는 정하지 않았다. 그 결과 아이폰 방문자는 "App Store에서 다운로드 하기" 바로 밑에서 "macOS 14 이상"을 읽는다 — 아이폰 앱의 요구 사항(iOS 18 이상, CB:17·243)과 다른 사실처럼 읽히고(SPEC §1.4 사실 규칙의 취지), 터미널 명령 링크 "brew로 설치"는 아이폰에서 쓸 수 없다. 데스크톱에서는 Mac 버튼이 앞에 있어 같은 줄이 Mac 메타로 읽혀 문제가 없다.
- **고칠 방법**(신규 문구 0 — CB:243 의 승인 문장 재사용, DownloadCTA 와 같은 플랫폼 변형):
  ```diff
  // components/hero/copy.ts
     meta: 'macOS 14 이상 · 무료',
  +  /** CB:243 — iOS 에서 배지 아래(설치 절 iPhone 열과 같은 문장) */
  +  metaIos: 'iOS 18 이상 · 무료',
  // components/hero/Hero.tsx:66–70
  -  <span>{HERO_COPY.meta}</span>
  +  <span className="[html[data-platform=ios]_&]:hidden">{HERO_COPY.meta}</span>
  +  <span className="hidden [html[data-platform=ios]_&]:inline">{HERO_COPY.metaIos}</span>
  -  <TextLink href="#install" className="-my-[11px] inline-block py-[11px]">
  +  <TextLink href="#install" className="-my-[11px] inline-block py-[11px] [html[data-platform=ios]_&]:hidden">
  ```
  (`[html[data-platform=ios]_&]:hidden` 은 선택자 특이도가 높아 `inline-block` 을 이긴다 — DownloadCTA.tsx:38 과 같은 방식. 고친 뒤 T15 · T10(iOS Tab 대상에서 brew 링크가 빠지는 것 허용) 재확인. SPEC §S1 카피 절에 "iOS: 메타 = CB:243 「iOS 18 이상 · 무료」, brew 링크 없음" 한 줄 추가.)

### P2-1. 390 히어로 리드가 둘째 문장 꾸밈말 가운데서 꺾인다("… 보여요. 일하는 / 동안엔 아잉이 …")
- **파일:줄** `components/hero/Hero.tsx:48`(`<br className="phone:hidden" />`) · SPEC §S1 `docs/v2/SPEC.md:622`("phone 은 자연 줄바꿈")
- **재현** 크롬 390×844 · 375×812 · 360×780(감속, scrollY 0). `leadwrap.mjs` 실측 줄: `["근무 시작을 누르면 팀 전체에 바로 보여요. 일하는 ", "동안엔 아잉이 화면 구석에서 함께해요."]`(세 폭 모두 같음). 웹킷 390 도 2줄 같은 자리. 통합 캡처 `390x844-fold.png` 에서도 보인다.
- **기대 vs 실제** SPEC 대로(자연 줄바꿈)라 위반은 아니지만, 두 박자 문장의 주어구 "일하는 동안엔"이 갈라져 첫 화면에서 눈에 걸린다. 둘째 문장(25자)은 지금 첫 줄(27자)보다 짧아 360 폭에서도 한 줄에 들어간다 → 문장 사이 `<br>` 를 phone 에도 두면 줄 수(2)·높이 그대로 문장 단위로 갈린다.
- **고칠 방법** `Hero.tsx:48` `<br className="phone:hidden" />` → `<br />`, SPEC §S1 리드 주석을 "(문장 사이 줄바꿈 — phone 포함, 360–390 실측 2줄)"로. 히어로 세로 흐름·말풍선 불변식(T5 ≥ 16px)은 줄 수가 같아 영향 없음 — T5 재확인.

### P2-2. 설치 절에 업데이트 문장이 둘 — 한 절 안에서 "다시 켜져요"가 두 번, 업데이트 길이 둘로 읽힌다
- **파일:줄** `components/install/Install.tsx:102–114`(brew 업데이트 줄, `data/install-copy.ts:18–19`) · `Install.tsx:158–169`(D18 한 줄, `install-copy.ts:32`) · SPEC §S6 `docs/v2/SPEC.md:941`(Mac 줄 안 '작은 줄 업데이트는 …') · `:944`(D18 줄)
- **재현** 1440×900, `#install` 머묾(통합 캡처 `1440-install.png`): Mac 열 "업데이트는 brew update && brew upgrade --cask aing-check 한 줄이고, 끝나면 앱이 다시 켜져요." → 약 150px 아래 전폭 "새 버전이 나오면 … 지금 업데이트 한 번이면 설치하고 다시 켜져요."
- **기대 vs 실제** 둘 다 SPEC 이 고른 문장이라 위반은 아니다. 다만 D18 의 취지("업데이트 문장은 설치 경로를 가르지 않는다")와 달리, 첫 문장이 "업데이트는 ~ 한 줄이고"로 단정해 DMG 로 설치한 사람이 brew 를 써야 하는지 헷갈릴 수 있다(brief §1: brew 설치본도 앱 안 [지금 업데이트]가 brew 경로로 처리 — D18 한 줄이 두 경로를 다 덮는다).
- **고칠 방법(리드 결정 — 기본값은 현행 유지)** (a) brew 줄 삭제: `Install.tsx:102–114` 문단과 `install-copy.ts:18–19` 를 지우고 SPEC §S6 에서 CB:236 문장을 뺀다(업데이트 문장 1개, 신규 문구 0). (b) 유지하되 순서만: D18 한 줄을 brew 줄 바로 위로 올리지 않는다(두 열 아래 전폭 자리는 D21-1 결정) — 바꾸지 않음. 권장 (a).

### P2-3. App Store 배지 alt 가 배지 그림 글자와 다르고, 배지·QR alt 가 v2 SPEC 승인 목록에 없다
- **파일:줄** `components/ui/AppStoreBadge.tsx:32` · `components/ui/QrCode.tsx:31` · SPEC §6.5 `docs/v2/SPEC.md:1155–1174` · §6.2 `:1126`
- **재현** 아무 뷰포트, 히어로·설치·아웃트로 배지(`img[src*="appstore-badge-ko-black"]`). 그림 글자 = "App Store에서 / 다운로드 하기", alt = "App Store에서 다운로드". QR alt = "App Store 아잉체크 페이지로 가는 QR 코드"(desk 설치 절).
- **기대 vs 실제** SPEC §1.4.3 은 "alt 문구 = §6.5 표"만 신규로 승인하는데 두 alt 는 §6.5 에 없다(v1 SPEC `docs/SPEC.md:872` 승계 — v2 §6.2 가 두 컴포넌트를 '바꿀 것 없음'으로 둬서 남았다). 배지 alt 는 글자 그림의 이름이 보이는 글자와 다르다(WCAG 2.5.3 '이름 안의 라벨' — "다운로드 하기"로 말하는 음성 사용자).
- **고칠 방법** `AppStoreBadge.tsx:32` `alt="App Store에서 다운로드"` → `alt="App Store에서 다운로드 하기"`(배지 글자 그대로). SPEC §6.5 표에 두 줄 추가: `brand/appstore-badge-ko-black` | App Store에서 다운로드 하기 · `brand/qr-appstore` | App Store 아잉체크 페이지로 가는 QR 코드(v1 승계). T4·T14 재확인.

### P2-4. 복사 실패 힌트 "⌘C로 복사하세요" — v2 승인 목록 밖이고, iPhone 에서도 보이는 설치 절에서 ⌘ 를 말한다
- **파일:줄** `components/ui/CommandBox.tsx:18`(문구) · `:34`(announce) · `:56`(작은 줄)
- **재현** iOS 컨텍스트 390, `navigator.clipboard.writeText` 를 거부(Promise.reject)로 바꾼 뒤 `#install` 의 [복사]를 `page.mouse.click` → 실측(`copyfail.mjs`): `{"platform":"ios","hint":["⌘C로 복사하세요"],"status":"⌘C로 복사하세요"}` — 작은 줄 + `[role=status]` 같은 문장. 설치 절은 D9 대로 iOS 에서도 Mac 안내를 보이므로 이 문장이 아이폰에 뜬다(아이폰엔 ⌘ 키가 없음).
- **기대 vs 실제** v1 SPEC S11(`docs/SPEC.md:958`)에서만 정한 문구로 v2 SPEC §1.4.3 목록에 없다. 정상 경로(복사 성공)에서는 보이지 않으므로 P2.
- **고칠 방법** (a) SPEC §1.4.3 에 "복사 실패 힌트 ⌘C로 복사하세요(v1 S11 승계)"를 등록하고, (b) iOS 에서는 힌트 줄만 숨긴다(선택 상태는 그대로 — 길게 눌러 복사 가능): `CommandBox.tsx:56` `className="t-small mt-2 text-ink-2"` → `"t-small mt-2 text-ink-2 [html[data-platform=ios]_&]:hidden"`, `:34` 는 `document.documentElement.dataset.platform !== 'ios'` 일 때만 announce.

### P2-5. 말풍선 접근성 규칙이 SPEC 안에서 갈리고, 구현도 둘로 갈렸다(행 = 읽힘, 트립틱 = 숨김)
- **파일:줄** `components/features/RowCanvas.tsx:108–120`(행 말풍선 — `aria-hidden` 없음, alt = bubbleText) · `components/moments/MomentObject.tsx:84–86`(트립틱 말풍선 — 감싼 div `aria-hidden="true"`) · SPEC §1.4 v2 `docs/v2/SPEC.md:144`("행·트립틱의 말풍선은 … `aria-hidden`") ↔ §S4 접근성 `:898`("말풍선은 `bubbleText()` 문장을 alt 로")
- **재현** 1440×900 감속, 맨 아래까지 스크롤 뒤 `img` 마다 `closest('[aria-hidden="true"]')`: `bubble-message-gureum`(R1)·`bubble-ruby`(R2) = 노출, `bubble-poked-mint`(트립틱 02) = 숨김(`axhidden.mjs`). 화면 낭독기는 R2 에서 "루비 +3!"을 맥락 없이 한 번 더 읽는다.
- **기대 vs 실제** SPEC 두 절이 서로 반대라 어느 쪽도 '정답'이 아니다. 같은 성격(아잉 없이 렌더 곁에 놓은 페이지 크롬)의 말풍선이 절마다 다르게 낭독된다.
- **고칠 방법(리드 결정)** 권장 = §1.4 쪽으로 통일: `RowCanvas.tsx:111` `<div key={i} … data-kind="bubble" style={vars}>` 에 `aria-hidden="true"` 추가(같은 사실이 패널 alt·본문에 있다 — 메시지 패널 alt 가 이미 대화를 서술) + SPEC §S4 접근성 문장을 "말풍선은 `aria-hidden`(문구는 bubbleText 원문 그대로 그림에)"로 고친다. 반대로 통일한다면 `MomentObject.tsx:84` 의 `aria-hidden` 을 지우고 §1.4 를 고친다. T14(모든 img 에 alt 속성)는 어느 쪽이든 그대로 초록.

### P2-6. iOS 아웃트로: App Store 배지 다음에 "brew 명령 복사"(터미널 명령) 버튼
- **파일:줄** `components/outro/Outro.tsx:44–50`
- **재현** iOS 컨텍스트 390, `#outro` 머묾(증거 `.scratch/review-copy/out/ios-390-outro.png`): 버튼 줄 = 배지 → "brew 명령 복사"(폭 100% 알약). 리드는 "맥에 설치하고, 팀 코드를 나눠 주세요."
- **기대 vs 실제** D9·SPEC §6.2 는 iOS 에서 아웃트로 다운로드 버튼만 빼라고 했고 복사 버튼은 정하지 않았다. 아이폰에서 맥 터미널 명령을 복사하는 쓸모는 작다(유니버설 클립보드 정도) — 마지막 화면의 두 번째 큰 버튼이 아이폰 방문자에게 뜻이 없다. P1-1 과 같은 뿌리(iOS 문맥 미정).
- **고칠 방법(리드 결정)** 숨긴다면 `Outro.tsx:49` `className={FULL_ON_PHONE}` → `className={\`${FULL_ON_PHONE} [html[data-platform=ios]_&]:hidden\`}` — T10 의 'button 요소 = 복사 2개'는 DOM 개수라 그대로, T11 은 기본 컨텍스트라 영향 없음. 유지한다면 SPEC §S8 에 "iOS 에서도 brew 복사 유지" 한 줄.

---

## 3. 관찰(결함 아님 — 리드 참고, 수리 대상 아님)
1. 같은 정의문 「작은 Mac 팀을 위한 메뉴바 근무 타이머」가 격자 제목(CB:29) · 푸터 한 줄 · `<title>` 세 번 — SPEC §S5·§S9·§8 의 선택.
2. "근무 시작·종료는 맥에서 해요."가 R5 작은 줄(CB:185) · 설치 iPhone 열(CB:243) 두 번 + FAQ 2 — 같은 뷰포트에 함께 보이지는 않는다(1440·390 실측).
3. 설치 메타의 "Apple 공증"(CB:228)은 DMG 버튼 바로 아래다. "경고 없이 열려요"는 0건(DECISIONS §4-4 준수). DMG 자체 공증·스테이플 실측은 ⑧·사용자 몫.
4. D18 문장의 "지금 업데이트"는 앱 버튼 이름인데 괄호·따옴표가 없어 부사 "지금"으로도 읽힌다 — 리드 확정 문장이라 그대로 둔다.
5. 통합 보고 T4 의 "21개"가 맞다(SPEC §1.4.1 목록 21개 — 오케스트레이터 프롬프트의 "20개"는 오기).

## 4. 재현 메모
- 스크립트: `/Users/yesung/check/landing/.scratch/review-copy/{dom,cbmap,faqcmp,forbid,lines,lines-webkit,leadwrap,iosshot,axhidden,copyfail}.mjs` — 모두 `node <파일>`(데브 3000 필요, 3100 안 씀). Playwright = `createRequire('/Users/yesung/Aingo/node_modules/')('playwright')`.
- iOS 컨텍스트 = `{ viewport: 390×844, isMobile, hasTouch, userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) … Version/18.0 Mobile/15E148 Safari/604.1' }` → `PlatformScript` 가 `data-platform="ios"`.
- 띄운 브라우저는 모두 닫았다. 서버는 띄우지 않았다(3100 미사용).
