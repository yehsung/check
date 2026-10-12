# requests — facts-install(④ 섹션)

작성 2026-10-12 · facts-install. 공용 파일은 고치지 않았다. 내 파일: `components/facts/Facts.tsx` · `components/install/Install.tsx` · `components/install/install-copy.test.ts` · `data/install-copy.ts`. 실측 하네스·캡처: `landing/.scratch/facts-install/{check.mjs,report.json,shots/}`(데브 3000, 크로뮴).

## 1. integration · 리드 — 설치 절 높이 989px(SPEC §3.0 의 760 보다 +229)

**무엇**: 1440×900 에서 `#install` = **989px**(숫자 격자 `#facts` = 640 그대로). SPEC §S6 와이어(가운데 H2 → Mac/iPhone 두 열 → `--line` → 팀 3열 → 업데이트 한 줄)와 §2.5 패딩(120/120)을 그대로 지켰다.
**왜 760 이 안 되나**: 패딩 240 + H2 70 + 간격 40 + **Mac 열 408**(Mac 라벨 · 버튼 48 · 메타 · 3단계 · 라벨 · 명령 상자 48 · 업데이트 2줄 · zip 링크 — CB 문장 9덩이) + 40 + 헤어라인 + 32 + 팀 94 + 32 + 업데이트 22. Mac 열만으로 SPEC 이 잡은 내용 높이(520)의 80% 다. 간격은 이미 줄였다(1차 1,059 → 989).
**지금 문서 높이**: 1440×900 `scrollHeight` 9,977(다른 절은 아직 자리표시자) — T5 상한 9,900 을 넘을 수 있다.
**고르는 길**(통합·리드 판단 — 내가 하지 않은 이유: 와이어와 다르다)
- (a) SPEC §3.0 의 줄이는 순서(행 560→520 −200 · 트립틱 피치 −72 · 숫자 격자 640→600 −40 · FAQ 패딩)로 흡수. 설치 절은 그대로.
- (b) 팀 3단계를 오른쪽(iPhone) 열 아래로 세로 쌓기 → 약 −160px(두 열 높이도 408 ↔ ≈410 으로 맞는다. 지금 오른쪽 열 아래가 ≈270px 비어 있다). DOM 순서 Mac · iPhone · 팀 을 두고 768 이상에서 팀을 `col-start-2 row-start-2` 로 두면 390(iOS 먼저 → Mac → 팀) 순서는 그대로다. 단점: 헤딩 없이 iPhone 아래에 놓여 "아이폰 단계"로 읽힐 수 있다(3번이 메뉴바).
- (c) 데스크톱 아래 패딩 120 → 96(−24, FAQ 위 패딩과 합쳐 절 사이가 240 → 216).

## 2. 알림 — 숫자 격자 1024–1279 는 '제목 위 + 4×2'(SPEC §4 의 1024 '같음(칸 156)' 과 다름)

실측(크로뮴, 실제 서브셋 글꼴): 제목 `t-facts-title` 40px 두 줄 폭 305px, 칸 안 '30.1MB' = 숫자 100(52px) + 단위 30 + 여백 24. 1024 에서 제목 왼쪽 + 36→90% 칸이면 제목 열 234px · 칸 138px 이라 둘 다 넘친다(칸 156 은 4×156 = 624 > 36→90% 의 553). 그래서 **1280 이상만 왼쪽 제목 + 4×2**(1440: 제목 x 176 · 칸 x 518 · 폭 194 · 행 피치 216 · 높이 640 — SPEC 값 그대로), 768–1279 는 제목 위 + 4×2(1024 칸 197), 390 은 2×4(칸 구분은 위선). 칸 넘침 0(320 · 390 · 768 · 1024 · 1200 · 1280 · 1440 · 1600 · 1920 실측).

## 3. integration — tab(768) 세로 격자(DECISIONS D19-5)

`Install` 은 `<Gridlines lines="all" />` 를 쓴다(수평선부터 팀 헤어라인까지 10/50/90). 지금 프리미티브는 tab 에서 왼쪽 선 하나를 보여 768 캡처에서 Mac 열 글자 뒤로 지나간다. D19-5 대로 `Gridlines` 가 tab 을 없음으로 바꾸면 설치 절은 그대로 맞는다(설치 절 쪽 수정 불필요).

## 4. integration · faq-outro — `node scripts/check-glyphs.mjs` exit 1(내 파일 아님)

빠진 음절 8개(깨 뀐 베 쉼 싣 앵 픈 험)가 전부 `components/faq/faq.test.ts`·`components/outro/outro.test.ts` 의 문자열(금지어 검사용)에서 나온다. 수집기가 `*.test.ts` 도 훑기 때문. 제안: `scripts/check-glyphs.mjs` 의 `listSourceFiles` 에서 `.test.ts` 를 건너뛰거나(테스트 문자열은 화면에 안 나온다), 통합 때 소스 모드 `npm run subset`. 내 파일의 글자는 500·600·300 서브셋에 모두 있다(같은 실행에서 미검출).

## 5. 알림 — `installChoice()` 반환 모양(PLAN §3.7 + 접근 이름)

`installChoice(release, RELEASE_FALLBACK)` → `{ file: 'dmg'|'zip'; label: 'aing-check.dmg 다운로드'; ariaLabel: 'aing-check.dmg 다운로드, 30.1MB'; mb: MbFigure('30.1' — FigureString 의 한 갈래); version: '0.3.49' }`. v1 의 `meta`(CB 밖 문장 "모두 돼요. Apple 공증을 받은 앱이에요.")는 지웠다. 히어로·아웃트로가 버튼 접근 이름에 크기를 넣을 때 `ariaLabel` 또는 `mb` 를 그대로 쓰면 된다. `mb` 문자열이 이상하면 바이트에서 같은 식으로 다시 만든다(테스트 7건 — `components/install/install-copy.test.ts`, `test:unit` 글롭에 들어간다).

## 6. 참고(결정 불필요)

- `CommandBox` 바탕은 `bg-surface`(#181428). SPEC §2.1 은 `--bg-1` 행에 "brew 명령 줄 바탕 하나", `--surface` 행에 "명령 상자" 를 같이 적어 둘 다 맞다 — 프리미티브 그대로 둔다.
- 390 iOS 에서 `.order-ios-first`(order:-1)로 iPhone 묶음이 먼저 **보이지만** Tab 순서는 DOM 순서(Mac 버튼 → 복사 → zip → 배지)다. SPEC 이 정한 방식이라 그대로 뒀다. 768 이상은 두 열 자리를 못박아(`col-start`) iPad(iOS 판정)에서도 Mac 이 왼쪽이다.
