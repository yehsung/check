# 리뷰 ⑥ — 성능·접근성(perf-a11y)

작성 2026-10-12 KST · review-perf-a11y · 읽기 전용(코드 0글자 수정). 근거: DECISIONS D1–D25 · PLAN §7 T3/T5/T13/T14/T17 · SPEC §1.5·§2.1·§4·§5·§6.5·§8.
측정: `npm run build`(exit 0) → `npx next start -p 3100`(이 리뷰에서 한 번 띄우고 kill, `lsof -i :3100` 비어 있음 확인) / 접근성·콘솔은 데브 3000(재시작 0).
스크립트·원자료: `landing/.scratch/review-perf-a11y/`(`perf.mjs` · `a11y.mjs` · `contrast.mjs` · `console.mjs` · `layers.mjs` · `*.json` · `shots/`).

**결과: P0 0 · P1 3 · P2 9.** 통합 보고서 T13 수치는 그대로 재현됐다(바이트 차이 +36B = 응답 헤더 날짜). 다만 390 LCP 816ms 를 "aing-idle-15 영상"이라 적은 것은 **opacity 0 인 숨은 idle 층**이 잡힌 것이고, 눈에 보이는 LCP 는 포스터 288ms 다(아래 §1 참고 1).

---

## 0. 잘 된 점(3줄)
- 스크롤 리스너 0 → 맨 아래까지 휠 스크롤 중 50ms 초과 작업 **0건**(CPU 1× · 4× 둘 다, 프레임 50ms 초과 0) · CLS **0** · 로드 전 영상 요청 **0**(모든 실행) · 히어로·아웃트로 idle 은 **같은 URL 1회 요청**(아웃트로 추가 바이트 0) · 글꼴은 300·500·600·JBM 4개뿐, 800 요청 0.
- 감속 모션·Save-Data: 영상 요청 0 · 빛 한 줄 없음 · 무대 목록 모드 · 남는 전이는 바닥 빛 불투명뿐 · `scroll-behavior:auto`. 콘솔·pageerror·실패 요청·404 **0**(데브·prod × 크롬·웹킷 × 7 컨텍스트) · 가로 넘침 **0**(320/390/768/1024/1440 × 두 엔진, 스크롤 내내).
- 랜드마크(header·nav "주요"·main·footer 각 1) · h1 1 · 절마다 h2(트립틱 카드마다) · img 44장 alt 가 SPEC §6.5 와 전부 일치 · aria-hidden 안 포커스 0 · 건너뛰기 링크(첫 Tab, 보임, 동작) · 포커스 링 2px #C9B8FF 전부 보임 · 고정 내비에 가린 포커스 0 · 글자 대비 최저 **5.77**(실측, 1440·390).

---

## 1. 예산 재측정(prod 3100, `perf-*.json`)

| 항목 | 실측 | 예산 | 판정 |
|---|---|---|---|
| 1440 크롬 첫 화면(`load` 까지 전송 — D24-1) | **397,511B**(388.2KiB) · 47요청 중 load 전 25 | ≤ 400KB · **D25 목표 ≤ 360KB** | 400 통과(여유 2.5KB) / **D25 미달 → P1-3** |
| └ 같은 측정, 네트워크 에뮬레이션(지연 20ms·50Mbps → 지연 로딩 거리 1,250px) | **323,717B**(316.1KiB) — R1 렌더 3장이 load 뒤로 빠짐 | 참고 | 실사용 근사 |
| └ load + 1s(정보) | 568,228B | — | commute-start 영상(151KB)이 load 뒤 들어옴(설계) |
| 1440 크롬 전체(맨 아래 + 아웃트로 idle 재생 확인 + 3s) | **1,649,227B**(1.65MB) — Script 162,465 · Font 69,721 · Image 414,618 · Media 959,980 · HTML 27,956 · CSS 14,487 | ≤ 4.5MB | 초록 |
| 1440 웹킷 전체(sizes 합) | **2,464,500B**(2.46MB) — `aing-idle.mov` 818,300B **×2** | ≤ 4.5MB | 초록(×2 는 P2-9) |
| 390 크롬 전체(모바일·DSF 3) | **1,368,960B**(1.37MB) · load 까지 303,843B | ≤ 2.2MB | 초록 |
| 스로틀 390(지연 60·다운 9Mbps·업 1.5Mbps·CPU 4×) ×3 | FCP 288/288/296ms · **LCP(보이는 것) = 포스터 288/288/296ms** · 마지막 LCP 항목 = 숨은 idle-15 영상 824/836/832ms · **CLS 0/0/0** · load ≈ 505ms | LCP ≤ 2.5s · CLS ≤ .05 | 초록 |
| 참고: 느린 4G(지연 150·1.6Mbps·CPU 4×) | LCP 764ms(포스터) · load 2,061ms · 도착 마감(2.5s) 지나 once 건너뜀 → 영상은 load 뒤 | — | 초록 |
| load 이전 영상 요청 | 0(크롬 1440 ×2 · 390 · 스로틀 ×4 · 웹킷) | 0 | 초록 |
| 영상 요청 규율 | 크롬: commute-start.webm 151,382 ×1 · idle.webm 808,598 ×1(아웃트로 재요청 0) · 390: idle-15.webm 536,413 ×1 · 감속·Save-Data 0 | 같은 URL 재사용 | 초록(웹킷 로컬 ×2 — P2-9) |
| 스크롤 중 긴 작업(CDP 트레이스, CrRendererMain RunTask > 50ms) | CPU 1×: 0 / 4,345 작업 · CPU 4×: 0 / 4,154 · `longtask` 관찰자 0 · 프레임 50ms 초과 0 | 0 | 초록 |
| 글꼴 | 300-num 2,318 · 500 31,360 · 600 31,304 · JBM 4,739(4요청) · 800 0 · `public/fonts` 에 800 파일 없음 | 3+1, 800 0 | 초록 |
| 1440×900 문서 높이 | 9,849px | 9,300–9,900 | 초록 |

참고 1(결함 아님): 스로틀 390 에서 LCP 항목이 288ms 포스터 → ≈830ms `video`(idle-15)로 바뀐다. `layers.mjs` 타임라인상 그 순간 idle 층은 `opacity:0`(once 재생 중, 1.50s 칸으로 미리 시크)이고 크롬이 그 첫 프레임을 LCP 로 센다(박스 58,520 > 포스터 58,300). 필드 데이터에서 LCP 요소가 `<video>` 로 보고될 것이라는 점만 알아 둔다 — `visibility:hidden` 으로 바꾸면 D22-1 의 requestVideoFrameCallback 교체가 깨질 수 있어 고치지 않는 쪽을 권한다.
참고 2: 첫 화면 구성(헤드리스, 10진 KB) = JS 162.3 · 글꼴 69.7 · HTML 28.0(원문 138.7, 그중 RSC 페이로드 63.8) · CSS 14.4 · 이미지 123.0(R1 렌더 3장 + R1 타일 아이콘 72.0 포함). SPEC §5.1 추정(합 309.4KB)과의 차이는 거의 R1 렌더(지연 로딩 거리 3,000px) + JS·HTML 초과다(P2-10).

---

## 2. 접근성 점검표(데브 3000, `a11y.json`)

| 항목 | 결과 |
|---|---|
| `html lang` | `ko` ✓ |
| h1 | 1개(`#hero-h1`) ✓ |
| 절마다 h2 | top(h1) · moments 카드 3장 각 h2 · features h2 · facts h2 · install h2(+ h3 Mac/iPhone) · faq h2 · outro h2 ✓ · 행 5개는 article + h3(+ h4 둘) ✓ — 헤딩 건너뜀 0 |
| 랜드마크 | `header`(body 직속 → banner) 1 · `nav aria-label="주요"` 1 · `main#main` 1 · `footer`(body 직속) 1 · `role=status` 1 ✓ |
| img alt | 44장 모두 `alt` 있음, SPEC §6.5 표와 일치(장식 `""` = 포스터·근무 라벨·메뉴바 아이콘(-dot)·타일 `brand/icon-256`·워드마크 옆 `brand/icon-64`·빈 잔디 판) · 말풍선: 행 = `bubbleText` alt, 히어로·트립틱 = aria-hidden ✓ |
| Tab 순서 = 시각 순서 | 1440: 건너뛰기 → 내비 3 → 내비 CTA → 히어로(CTA → 배지 → brew로 설치) → 설치(Mac 열 → iPhone 열) → summary 10 → 아웃트로 3 → 푸터 6(32개) ✓ · 390: 같은 흐름 28개 ✓ · 트립틱·행 포커스 대상 0 ✓ · iOS 390 설치 절만 시각(iPhone 먼저)≠Tab(Mac 먼저) — D21-4 로 수용(개수에 안 셈) |
| 건너뛰기 링크 | 첫 Tab · fixed (16,8) 132×30 · z 90 · ink-1/surface-2 14.6:1 · Enter → `#main`, 다음 Tab = 히어로 CTA ✓ |
| 포커스 링 캡처 | `shots/1440-focus-nav-cta.png` · `1440-focus-copy.png` · `1440-focus-summary.png` (+ `1440-focus-skip.png` · `390-focus-skip.png` · `1440-focus-outro-cta.png`) — 채움 버튼은 offset 3px 로 링이 떨어져 보임 ✓ · 고정 내비에 가린 포커스 0(`scroll-padding-top` 작동) ✓ |
| 대비 | 글자를 투명하게 한 캡처에서 글자 상자 밑 바탕을 표본으로 잰 최악값: 1440 최저 5.77(명령 `$`, surface) · ink-3 13–14px 6.31–6.47 · 트립틱 단락이 무대 빛 위에서 5.27(390) — 4.5 미만 0(390 에서 잡힌 4건은 글자 밖 틱·스파인 점 표본 → 캡처로 확인, 오탐) ✓ · wire-rest 비글자 3.39(bg-0)·3.10(surface) ✓, 선은 바닥 빛 위를 지나지 않음(빛 α .2 위였다면 2.77) |
| 터치 대상 ≥ 44 | **✗ 내비 CTA 126×32(iOS "App Store" 101×32) · zip 링크 206×17** · brew로 설치 72×43.7 · 푸터 "지원" 23×44 · "GitHub" 42×44 — 나머지(히어로·설치·아웃트로 버튼 48, 배지 72, 인라인 복사 32+::before=44, summary 64) ✓ |
| prefers-reduced-motion | 크롬·웹킷: `.comet` 없음 · 말풍선·근무 라벨 불투명 1 · 무대 `display:none` · 돔 애니메이션 none · 스크롤 중 진행 전이 = 바닥 빛 opacity 뿐 · 행 dashoffset 0 · 아웃트로 불투명 1 · 영상 요청 0 ✓ |
| aria-hidden 안 포커스 | 0 ✓ · aria-hidden 없는 svg 0 ✓ |
| details/summary 키보드 | `#faq-2 > summary` Enter → 열림(1번 닫힘, name 그룹) · Space → 닫힘 ✓ · 포커스 링 ✓ |
| 가로 넘침 | 크롬·웹킷 320/390/768/1024/1440 스크롤 내내 `scrollWidth === innerWidth` ✓ |
| sticky 조상 T17 | 크롬·웹킷: `#moments`·`main`·`body`·`html` overflow visible(body x = clip) · transform/translate/scale/filter/perspective none · contain none · will-change auto · content-visibility visible · 무대 `top 0`(scrollY 1,548) ✓ |
| 콘솔 0 | 데브·prod × 크롬·웹킷 × {1440, 768, 390, 1440 감속, 390 감속, Save-Data, iOS} — error·warning·pageerror·실패 요청·4xx 0, 깨진 img 0 ✓ |
| robots/sitemap/OG/theme-color | robots `Allow: /` + Sitemap · sitemap 2 URL · OG 1200×630, `og:image:alt` = `.alt.txt` = SPEC §8 문장 · `theme-color #0C0A14` · `color-scheme dark` · title SPEC §8 ✓(로컬 빌드는 주소가 localhost — P2-12) |

---

## 3. 결함

### P1-1 내비 CTA 가 32px — SPEC 버튼 s(36)·터치 대상(44) 둘 다 미달
- **파일**: `components/ui/DownloadCTA.tsx:52` (`s: "t-button-s h-8 px-4"`) — `NavShell.tsx:67`·`LicensesNav.tsx:50` 이 씀.
- **재현**: 390×844 모바일 컨텍스트, scrollY 0 → `header a[data-cta="nav"]` 126×32(iOS UA 면 "App Store" 101×32). 1440 도 126×32. (`a11y.json` `touch390`·`touch390ios`)
- **기대 vs 실제**: SPEC §2.4 `t-button-s` = 버튼 높이 **36** · SPEC §4 "터치 대상 ≥ 44×44" — phone 에서 이것이 내비의 유일한 행동이다. 실제 32×(126|101).
- **고칠 방법**(보이는 알약 36 + 투명 히트 영역 44, 내비 높이 56/64 안에 들어감):
```diff
 const SIZE = {
   l: "t-button h-12 px-6",
-  s: "t-button-s h-8 px-4",
+  // SPEC §2.4 버튼 s = 36 · §4 터치 44 — 보이는 알약 36 + 투명 ::before 로 위아래 4px 씩
+  s: "t-button-s relative h-9 px-4 before:absolute before:inset-x-0 before:-inset-y-1 before:content-['']",
 } as const;
```

### P1-2 설치 절 "GitHub Releases에서 zip으로 받기" 링크의 누를 자리 17px
- **파일**: `components/install/Install.tsx:115-117`
- **재현**: 390×844 모바일, `#install` 의 zip 링크 → 206×17(1440 도 206×17). 자기 줄에 홀로 있는 링크라 WCAG 2.5.8 의 '문장 속 링크' 예외도 아니다.
- **기대 vs 실제**: SPEC §4 터치 ≥ 44. 실제 17.
- **고칠 방법**(히어로 brew 링크와 같은 수법, 레이아웃 불변):
```diff
               <p className="t-small mt-1.5">
-                <TextLink href={LINKS.downloadZip}>{C.zipLink}</TextLink>
+                {/* 글자 줄 21.7 → 누를 자리 45.7(SPEC §4). 음수 바깥 여백으로 줄 높이는 그대로 */}
+                <TextLink href={LINKS.downloadZip} className="-my-3 inline-block py-3">{C.zipLink}</TextLink>
               </p>
```

### P1-3 첫 화면 397.5KB — D25 목표(헤드리스 ≤ 360KB) 미달, 400KB 대비 여유 2.5KB
- **파일**: `components/features/RowCanvas.tsx:112`(Bubble)·`:133`(phone 화면)·`:155`·`:161`(swapTo)·`:184`(child) 의 `RenderImage` · 타일 아이콘 `components/ui/Tile.tsx:27,46` · `components/features/FeatureRow.tsx:62-127`.
- **재현**: prod 3100, 크롬 1440×900, 스크롤 없이 `load` 까지 CDP `encodedDataLength` 합 = 397,511B. load 전 목록에 R1 렌더 `message-unread-panel` 28.2K · `message-read-panel` 28.1K · `bubble-message-gureum` 11.9K · 타일 `menubar-icon-dot` 2.1K(헤드리스의 지연 로딩 거리 3,000px 안 — R1 은 문서 y ≈3,456). 네트워크 에뮬레이션(거리 1,250px)에선 323,717B.
- **기대 vs 실제**: DECISIONS D25-1 "행 캔버스 렌더 `<img>` 는 행이 1,200px 안으로 들어올 때 마운트 + `<noscript>` 폴백, 목표 ≤ 360KB". 실제 미적용 397.5KB.
- **고칠 방법**(히어로 말풍선·근무 라벨과 같은 패턴 — 상자 크기는 `.row-item` 의 `--bw/--bh`·`aspect-(--ar)` 가 이미 잡고 있어 CLS 0):
```diff
 // FeatureRow.tsx
-import { MQ_REDUCED, useBand, useRevealOnce } from "@/lib/hooks";
+import { MQ_REDUCED, useBand, useNearViewport, useRevealOnce } from "@/lib/hooks";
 ...
   const glow = useBand(markerRef, ROW_TIMING.band);
+  const near = useNearViewport(rootRef, "1200px"); // DECISIONS D25-1 — 한 번 true 면 유지
 ...
-        <RowCanvas spec={canvas} glow={glow} />
+        <RowCanvas spec={canvas} glow={glow} mount={near} />

 // RowCanvas.tsx — props 에 mount: boolean, renderItem(item, i, primary, mount)
+const lazy = (mount: boolean, el: JSX.Element) => (mount ? el : <noscript>{el}</noscript>);
 ...
-        <RenderImage asset={item.asset} widthPt={w} heightPt={h} alt={item.alt} className={img} />
+        {lazy(mount, <RenderImage asset={item.asset} widthPt={w} heightPt={h} alt={item.alt} className={img} />)}
 // swapTo · child · phone 화면 · Bubble · Tile 아이콘(RowCanvas 가 Tile 에 mount 를 넘기거나 tile 블록을 lazy 로 감싼다)도 같게
```
  기대 효과: 397,511 − 71,987(R1 렌더 3장 + 타일 아이콘) = **≈325,500B**(헤드리스, D25 목표 360KB 안). 행 문턱(.68svh)보다 1,200px 앞에서 마운트되므로 조립 시작 때 이미 받아져 있다. 해시 진입(`instant`)은 `useNearViewport` 첫 콜백에서 true.

### P2-4 히어로 "brew로 설치" 누를 자리 43.7px(0.3px 모자람)
- **파일**: `components/hero/Hero.tsx:68` — `-my-[11px] py-[11px]` → 14px × 1.55 = 21.7 + 22 = 43.7.
- **재현**: 390×844, `#top a[href="#install"]` 72×43.7.
- **고칠 방법**: `className="-my-3 inline-block py-3"`(45.7, 줄 높이 불변).

### P2-5 푸터 "지원"(23px)·"GitHub"(42px) 폭이 44 미만(phone)
- **파일**: `components/site/SiteFooter.tsx:15-17`
- **재현**: 390×844, 푸터 세로 목록 — 높이는 44 ✓, 폭 23·42. 위아래 이웃만 있어 WCAG 2.5.8 은 통과하지만 SPEC §4 "44×44" 엄격 기준 미달.
- **고칠 방법**: `"inline-flex min-h-11 min-w-11 items-center … desk:min-h-6 desk:min-w-0"`.

### P2-6 무대 모드에서 꺼진(opacity 0) 오브젝트가 접근성 트리에 남고 카드 글보다 먼저 읽힌다
- **파일**: `components/moments/MomentsStage.tsx:112-119`(`.obj` 래퍼)
- **재현**: 1440×900 · 감속 아님 · scrollY 1,548 → `.moments-stage .obj` 3개 중 활성 1 만 불투명 1, 0·2 번(라벨·헤더 카드·잔디 alt)은 opacity 0 인데 aria-hidden 이 없다(`a11y.json` `stageTop.objImgs`). DOM 이 `무대 → 카드` 순이라 화면 낭독기는 카드 1 의 h2 전에 오브젝트 1·2·3 alt 를 몰아 읽는다(WCAG 1.3.2 · 보이지 않는 내용 노출).
- **기대**: SPEC §S2 접근성 "접근성 트리에는 늘 한 벌" — 지금은 무대 안에서 최대 세 벌.
- **고칠 방법**: 활성 오브젝트만 노출(SSR·목록 모드는 `enabled=false` 라 영향 없음)
```diff
         <div
           key={n}
           className="obj"
+          aria-hidden={enabled && i !== shown ? true : undefined}
           data-idx={i}
```

### P2-7 트립틱 카운터의 대괄호가 그대로 읽힌다
- **파일**: `components/moments/Moments.tsx:25-27`
- **재현**: 접근성 이름 = "[ 01 / 03 ]"(구두점 낭독 설정에 따라 "왼쪽 대괄호 …").
- **고칠 방법**: `<span aria-hidden="true">[ </span><span className="text-ink-1">{m.counter}</span> / {MOMENTS_TOTAL}<span aria-hidden="true"> ]</span>`(보이는 모양 불변).

### P2-8 `/licenses` 가 쓰지 않는 Pretendard 500·300 을 preload 한다(≈33KB 낭비)
- **파일**: `app/layout.tsx:11-18, 27-33`(`preload: true` 가 루트 레이아웃 → 모든 라우트, `node_modules/next/dist/docs/01-app/03-api-reference/02-components/font.md:1059-1063`).
- **재현**: prod `/licenses` HTML 에 `pretendard_300_num`·`pretendard_500_sub` preload 링크, 실제 로드된 글꼴은 600 하나(`document.fonts`). 첫 페이지 예산과 무관(D19-4 가 포스터 preload 만 옮겼다).
- **고칠 방법**: `ptd500`·`ptd300n` 의 `localFont` 를 `app/page.tsx` 로 옮기고 `<main id="main" className={`${ptd500.variable} ${ptd300n.variable}`}>` 에 변수를 단다(500·300 을 쓰는 H1·클로징·격자 제목·숫자는 전부 main 안. 내비 워드마크·/licenses 는 600 이라 `ptd600`·`jbm` 은 레이아웃에 둔다).

### P2-9 웹킷(로컬 prod)에서 아웃트로가 `aing-idle.mov` 818KB 를 한 번 더 받는다
- **파일**: `vercel.json:4-7`(배포에서만 `/assets/*` immutable) · 로컬 `next start` 는 `Cache-Control: public, max-age=0`.
- **재현**: prod 3100 웹킷 1440, 맨 아래까지 → `aing-idle.mov` 요청 2회(각 body 817,960B). 이 환경 웹킷은 HEVC 알파를 못 풀어(MEDIA_ERR_DECODE ×3) 원인이 캐시 헤더인지 디코드 실패인지 여기선 가르지 못한다. 크롬은 같은 상황에서 재요청 0.
- **기대**: SPEC §5.5 "같은 idle URL — 캐시되면 0". 예산(4.5MB)은 ×2 여도 2.46MB 로 통과.
- **고칠 방법**: 코드 변경 없음 — ⑧ 사파리 실기(배포 또는 `vercel.json` 헤더가 적용된 환경)에서 Network 탭으로 아웃트로의 idle.mov 가 (disk cache)/(memory cache) 인지 확인. 재요청이면 아웃트로 AingClip 이 히어로의 `<video>` 를 재사용하는 길보다, `SpritePlayer` 의 형식 선택이 두 무대에서 같은 URL(쿼리 `?v=` 포함)을 내는지부터 본다.

### P2-10 JS·HTML 이 SPEC §5.1 추정을 넘는다(기록)
- **파일**: 클라 섬 청크 `/_next/static/chunks/24qv3is7kpl0l.js` 20,483B gz(원문 60,966B — `data/generated/assets.json` 전체가 들어 있어 v2 가 안 쓰는 `ui/popover-*` 등 57개 `ui/` 키 포함) · HTML 27,956B gz(원문 138,737B 중 RSC 페이로드 63,776B).
- **기대 vs 실제**: SPEC §5.1 JS ≈150KB(클라 섬 ≈8KB) · HTML+CSS ≈26KB → 실제 JS 162.3KB(load 전, 8청크) · HTML+CSS 42.4KB.
- **고칠 방법**: D25-1 이 "assets.json·sequences.json 을 클라 번들에서 빼는 일은 범위 밖"이라 했으므로 지금은 기록만. 후속에서 `asset()` 조회를 서버 컴포넌트로 올리고 클라 섬엔 쓰는 키만 props 로 넘기면 클라 청크 ≈10KB gz 감소 예상.

### P2-11 새 탭으로 여는 링크에 예고가 없다
- **파일**: `components/ui/AppStoreBadge.tsx:21-28`(히어로·설치·아웃트로) · `components/ui/QrCode.tsx:19-27` · `components/ui/DownloadCTA.tsx:91-99`(iOS 내비) · `components/site/SiteFooter.tsx:45`(바깥 링크 5개).
- **재현**: 화면 낭독기로 배지·푸터 링크를 열면 예고 없이 새 탭(WCAG G201 권고, AA 실패는 아님).
- **고칠 방법**: 접근 이름 끝에 sr-only "(새 탭)" — 예) 배지 `<span className="sr-only"> (새 탭)</span>` 를 `<a>` 안에. 신규 문구라 SPEC §1.4.3 승인 필요 — 리드 판단.

### P2-12 로컬 빌드의 canonical·og:url·og:image·robots·sitemap 주소가 `http://localhost:3000`
- **파일**: `lib/site.ts:7-8`(`NEXT_PUBLIC_SITE_URL` → `VERCEL_PROJECT_PRODUCTION_URL` → localhost 폴백).
- **재현**: prod 3100 HTML `<link rel="canonical" href="http://localhost:3000">`, `/robots.txt` Sitemap · `/sitemap.xml` loc 모두 localhost.
- **기대**: 배포 도메인. Vercel 배포는 `VERCEL_PROJECT_PRODUCTION_URL` 로 맞지만 다른 곳에 내면 그대로 새 나간다.
- **고칠 방법**: 배포 체크리스트에 `NEXT_PUBLIC_SITE_URL` 확인 한 줄(코드 변경 불필요). 원하면 `next.config.ts` 에서 production 빌드인데 두 변수가 다 없으면 경고 한 줄.

---

## 4. 결정으로 수용된 것(개수에 안 셈)
- WCAG 2.2.2: 히어로·아웃트로 idle 이 각각 14.4s × 2회(≈29s) 움직이고 멈춤 단추가 없다 — DECISIONS D2 · SPEC §7.4-4 "횟수 상한으로 갈음". 감속 모션에선 정지 포스터라 대안은 있다.
- iOS 390 설치 절 시각 순서(iPhone 먼저) ≠ Tab 순서(Mac 먼저) — DECISIONS D21-4.

## 5. 남은 일 · 확인 요청
- 사파리 실기(⑧·사용자): P2-9 의 idle.mov 재요청 여부, HEVC 알파 도착·idle 정지.
- 수리(⑦) 뒤 재측정 명령: `node .scratch/review-perf-a11y/perf.mjs http://localhost:3100 desk desk4g phone webkit lcp longtask` · `node .scratch/review-perf-a11y/a11y.mjs http://localhost:3000` (3100 은 `npm run build && npx next start -p 3100` 을 백그라운드로 띄우고 끝나면 kill + `lsof -i :3100` 확인).
