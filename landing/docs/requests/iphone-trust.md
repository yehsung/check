> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# iphone-trust — 요청과 메모

작성: iphone-trust, 2026-10-12. 대상은 `components/sections/IphoneTrust.tsx` 와 `components/sections/iphone-trust/{copy,geometry,layout}.ts` · `PhoneTabs.tsx` · `TodoWidget.tsx` 이다.
공용 파일은 고치지 않았다. 아래 1·2 는 공용 파일을 바꿔 달라는 요청이다. 둘 다 지금 값으로도 동작한다. 3 은 SPEC 안에서 어긋난 곳에 내가 고른 해석, 4 는 통합 단계에서 확인해 달라는 목록이다.

## 1. `data/fixtures.ts` 의 `HOTSPOTS.phoneTabs` 세로 보정 (core 소유)
- **무엇**: `y: 790, h: 60` 을 `y: 791, h: 62` 로.
- **왜**: 원본 `/Users/yesung/aing-check-promo/public/assets/v4/ios/screens/now_dark@3x.png` 를 열 단위로 스캔하면 탭바 캡슐이 y 2373–2559px, 곧 **791–853pt** 이다. 실제로 내보내는 `public/assets/ios/now.webp`(600폭)에서도 ≈790–852pt 다. `me-records`·`games` 판도 같다.
  - 가로는 맞는다. fixture cx(63·132·201·269·338)와 실측 아이콘 가운데(63.3·131.7·200·269.3·338.3)가 ±1pt 안이다.
  - 지금 값으로도 세로 가운데가 820 대 822, 윗변이 790 대 791 이라 수용 기준(±2pt) 안이다. 어긋나는 것은 아랫변 하나다(850 대 853, 3pt).
- **diff**:
```diff
-  phoneTabs: { size: [402, 874], y: 790, h: 60, w: 66, tabs: [
+  phoneTabs: { size: [402, 874], y: 791, h: 62, w: 66, tabs: [
```
- **쓰는 쪽**: `PhoneTabs` 는 fixture 를 그대로 읽으므로 고치면 바로 반영된다. 히트 크기는 바뀌지 않는다(minHit 50.77px 가 이미 더 크다). 통합 단계에서 `?hotspots=1` 로 한 번 눈으로 확인해 주면 좋다.

## 2. `components/ui/PhoneShell.tsx` 의 반응형 폭 (primitives-b 소유, 선택)
- **무엇**: `screenWidth` 가 숫자(px)만 받는다. 그래서 모드별 화면 폭(300·280·260)을 첫 페인트부터 CSS 로 줄 수 없다.
- **지금 우회**: W=300 셸을 그리고 바깥 래퍼에 CSS `zoom` 을 건다(`PhoneTabs.tsx` 의 `ZOOM`: 기본 0.866667, `desk:max-[1280px]` 0.933333, `desk:min-[1280px]` 1). 셸 치수(베젤·반경·아일랜드)와 핫스팟 좌표가 전부 W 에 비례하므로, W=300 셸을 0.866667 로 줄인 것과 W=260 셸은 같다. JS 판정이 없어 하이드레이션 어긋남도 없다. zoom 지원 범위는 Chrome 128+(표준 zoom), Safari 전부, Firefox 126+ 이다.
- **제안(바꾼다면)**: `screenWidth: number | string`(CSS 길이 또는 `var(--w)`)를 받게 하고, 안쪽 치수를 `calc(var(--w) * k)` 로 쓴다. 그러면 zoom 래퍼를 걷어낼 수 있다. 급하지 않다.

## 3. SPEC 안의 어긋남과 내가 고른 해석 (확인용, 문서 변경 요청 아님)
- **(a) 폰 화면 폭**: PLAN §4.7 은 "desk 300" 이고 SPEC §7 은 "1024 → 280" 이다. SPEC 을 따랐다. desk ≥1280 은 300, desk 1024–1279 는 280, tab·phone 은 260 이다.
- **(b) desk 12열 배치**(글 1–5 · 폰 7–9 · 위젯 10–12)는 1024–1279 에서 물리적으로 들어가지 않는다. 1024 의 본문 폭은 928px 다. 여기에 글 5열 373 + 셸 300 + 위젯 L 300 이 들어가야 하는데 12열의 3칸은 214px 다. 1280 에서도 셸이 3칸(262)을 넘쳐 위젯 칸과 겹친다. 그래서 이렇게 나눴다.
  - desk 1024–1279: tab 과 같은 2열(글 | 폰). 위젯은 글 열 안 글 아래에 두고, 1024 에서 L·S 가 나란히 들어간다.
  - desk ≥1280: 3열(글 | 폰 | 위젯). 위젯 묶음은 폰 아랫변에 맞춰 내려앉는다('위젯은 폰 중간 높이부터').
  - 1440 에서는 글 열 0–579 · 폰 619–940 · 위젯 980–1280 이다. SPEC 12열 위치(폰 642–963 · 위젯 978–1278)보다 폰이 23px 왼쪽에 있다.
- **(c) S10 큰 문장 크기**: `.t-statement` 의 clamp(24px, 2.6vw, 36px) 는 1024 → 26.6 · 768 → 24 라 SPEC §7 S10 행(36 · 32 · 30 · 24)과 다르다. 내 파일에서만 §7 대로 덮었다(`tab:text-[30px]`, desk `clamp(32px, 22.15px + 0.9615vw, 36px)` = 1024 → 32 · 1440 → 36, phone 은 토큰 하한 24 그대로). 전역 토큰을 바꿀지는 통합에서 판단해 달라.
- **(d) 감속 모션**: SPEC §2.7 은 "패널 교체는 불투명 120ms 만" 이다. 섹션 지시("전이 시간 0")를 따라 폰 화면과 위젯 교체는 `motion-reduce:transition-none`(0ms)로 했다. 상태 변화는 같다. 이 절에는 영상 요청이 처음부터 0건이다.
- **(e) 탭 핫스팟 모양**: fixture 에 모양이 없어 `capsule` 로 했다. 렌더의 선택 탭 하이라이트가 캡슐이다.

## 4. 통합 단계에서 확인해 줄 것 (dev·build 를 못 띄워 실행 확인을 못 했다)
- 빌드 CSS 에 이 변형들이 실제로 나오는지: `desk:max-[1280px]:` · `desk:min-[1280px]:` · `[zoom:0.866667]` · `min-[768px]:row-[1/-1]` · `grid-rows-[repeat(4,auto)_1fr]` · `desk:text-[length:clamp(32px,calc(22.15px_+_0.9615vw),36px)]` · `transition-[opacity,visibility]`.
- 화면 폭(`#iphone [data-phone-shell] > div` 의 getBoundingClientRect().width): 390 → 260, 768 → 260, 1024×768 → 280, 1440×900 → 300.
- 탭 핫스팟 히트: phone 모드에서 44×44 이상(셸 좌표 50.77 × zoom 0.866667 = 44.0). 이웃 탭과는 0.02px 만 닿는다.
- 3열(1440)에서 위젯 L 이 300×315 인지. 위젯 열이 auto 라 `desk:min-[1280px]:w-[300px]` 로 고정해 두었다.
- 390 에서 가로 넘침 0. 계산으로는 셸 278.2 ≤ 본문 350 이고, 위젯 L 은 `min(100%, 300px)` 이다.
- `#iphone` 탭 '나' → 보이는 화면이 `ios/me-records`. 지난 화면은 200ms 뒤 `visibility:hidden` 이 되므로 `img[src*="me-records"]` 를 `toBeVisible()` 로 단언해도 된다. 위젯 체크 → `[role=checkbox][aria-checked=true]`.
- 글자 서브셋: 탭 목록 접근 이름 '아이폰 앱 탭' 은 SPEC 밖의 문자열이다(화면에 그리지 않음). check-glyphs 가 소스를 스캔하므로 `npm run subset`(기본 모드)에 맡긴다.
