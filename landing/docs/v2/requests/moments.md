# requests — moments(④ 섹션)

작성 2026-10-12 · moments. 공용 파일은 고치지 않았다. 아래 1 은 수용 조건(T9 V1)이 빨간 원인이라 통합 판단이 필요하고, 2–5 는 알림이다.

## 1. core·integration — `app/globals.css` `.obj-glow` 로는 V1 보라 면적 하한 2.0% 를 못 넘는다(실측 0.02%)

**무엇**: SPEC §2.9 V1(트립틱 02 머묾, scrollY 1,548, 1440×900) 하한 **2.0%** · 상한 8%. 지금 `.obj-glow`(globals 글자 그대로)로 실측 **0.02%**(크로뮴, 점등 끝 + 2.5s 뒤 캡처, HSV H 245–295 · S ≥ .35 · V ≥ .30).
**왜 못 넘나**: 보라로 세려면 바탕 #0C0A14 위에서 α ≥ .246 이어야 V ≥ .30 이 된다(.246 × 250 + .754 × 20 = 76.5). `.obj-glow` 첫 층은 가운데 α .30 → 55% 에서 .12 라 α ≥ .246 인 곳이 반지름의 17% 안쪽뿐인데, 그 자리는 렌더(499×369)가 덮는다. 둘째 층(웅덩이)은 가운데 α .22 라 어디서도 문턱을 못 넘는다(웅덩이 한가운데 실측 rgb(37,28,70) → V .27). 오브젝트 2 렌더(콕 목록)에는 보라가 없다(파랑 단추). 오브젝트 3 은 잔디 자체가 보라라 2.78%.
**실측**(`.scratch/moments/purple.mjs` — 주입 CSS, 파일 변경 없음, 순서대로 내려가 각 위치 2.5s 대기):

| 후보 | V1(오브젝트 2) | 오브젝트 3 | 모양 |
|---|---|---|---|
| 지금 | 0.02% | 2.78% | 빛이 거의 안 보임(`.scratch/moments/stage-1440x900-y1548.png`) |
| A 웅덩이만 .22 → .46 | 1.58% | 3.90% | 여전히 하한 밑 |
| B 라디얼 .30/.12 → .46/.26 | 5.12% | 3.94% | 범위 안, 가장 진함 |
| **C(제안)** 라디얼 .40/.20(60%) + 웅덩이 .42 | **3.67%** | **4.38%** | 범위 안(`.scratch/moments/purple-mixC-V1.png`) |

**제안 diff**(같은 보라 `rgba(126,94,250,…)` 의 α·정지점만 — 새 색 없음. D13 의 행 손잡이처럼 이 절의 손잡이로 DECISIONS 에 적어 주면 된다):
```diff
   .obj-glow { position:absolute; inset:-140px -180px; pointer-events:none; background:
-    radial-gradient(closest-side, rgba(126,94,250,.30), rgba(59,30,143,.12) 55%, transparent),
-    radial-gradient(ellipse 46% 14% at 50% 92%, rgba(126,94,250,.22), transparent 70%); }
+    radial-gradient(closest-side, rgba(126,94,250,.40), rgba(126,94,250,.20) 60%, transparent),
+    radial-gradient(ellipse 52% 18% at 50% 88%, rgba(126,94,250,.42), transparent 70%); }
```
- 목록 모드(tab·phone·desk 감속)의 인라인 오브젝트도 같은 `.obj-glow` 를 쓰므로 함께 진해진다(카드당 하나).
- 통합이 받지 않으면 V1 은 빨강으로 남는다 — moments 쪽에서 새 색·새 빛을 더해 우회하지 않았다(SPEC §1.3 · 철칙).

## 2. integration(알림) — SPEC 과 다르게 한 것(이유 있음)

- **1024 배율**: SPEC §4 표 "1024×768 … 오브젝트 ×.85" 대신 `--moment-u = clamp(.6px, (36vw − 16px)/499, 1px)`(1440 → 1 · 1280 → .89 · 1024 → .71). ×.85 면 1024 에서 오브젝트 2(424px, 중심 50.8%)의 말풍선 오른쪽 끝 732 가 단락 왼쪽(69% = 707)을, 오브젝트 1 왼쪽 끝 319 가 "00:00" 숫자(134–≈350)를 덮는다. 지금 1024 실측: 숫자 오른쪽 ≈348 · 오브젝트 1 왼쪽 353 · 말풍선 오른쪽 ≈692 · 단락 707(`.scratch/moments/stage-1024x768-card{1,2,3}.png`). SPEC §S2 의 "가운데 무대와 겹치지 않는다" 를 우선했다.
- **인라인(목록 모드) 무대 빛은 `data-glow` 속성 없이 늘 켜짐**: 무대 모드에서 인라인은 `display:none` 이라 `getBoundingClientRect()` 가 0 상자다 — T9 의 '화면과 겹치는 `[data-glow="on"]`' 셈이 0 상자를 겹침으로 셀 위험을 없앴다. 목록 모드의 인라인 빛은 SPEC §S2 대로 '켜진 최종 상태, 카드당 하나'(돔처럼 구조물 취급).
- **무대 빛 켜짐 지연**(moments.css): 오브젝트 1 = 선 다음(200ms) · 2 = 말풍선 다음(120ms) · 3 = 13열이 다 켜진 뒤(910ms). `data-glow="on"` 은 점등 순간 붙고(GlowGate 셈은 속성 기준), 보이는 불투명만 지연된다. 꺼질 땐 지연 없이 800ms 선형.
- **처음 engaged 가 활성 1·2 와 함께 오면**(해시·새로고침·`scrollTo(0→1548)`) 서 있는 오브젝트를 곧바로 켠다(450ms 대기 없음) — 0 → 1,548 로 뛰어든 뒤 1s 에 점등·빛 불투명 1 실측(T9 의 '각 위치 1s 대기' 에서 빛이 덜 켜진 채 찍히지 않게).
- **오브젝트 2·3 마운트 조건**: 처음 engaged **또는** 활성 ≥ 1(섹션 끝에서 새로고침했을 때 무대가 비지 않게). 활성 ≥ 1 은 scrollY ≥ 1,197 이라 첫 화면 바이트와 무관.
- `lib/grass/**` 삭제(소비처 0 — grep 확인, PLAN §1 '쓰지 않으면 삭제'). 잔디 격자 상수는 `components/moments/stage.ts` `GRASS_GRID`(테스트가 `data/generated/grass.json` token 판과 맞춰 본다).
- 잔디 빈 판(`ui/grass-token-empty`)은 SPEC §6.5 표에 없어 `alt=""`(다 찬 판이 "최근 12주 AI 토큰 잔디" 를 진다).

## 3. integration·primitives(알림, 내 파일 아님) — WebKit 768·1024 가로 넘침은 기능 행에서

- WebKit 768×1024 `scrollWidth` 2,005 · 1024×768 7,598(크로뮴은 둘 다 정상). 원인 요소: `components/features` 의 `.dots`(폭 31,837px)·`.floor-light`(폭 ≈20,000–29,000px) — 행 루트 `--k: min(1, tan(atan2(…)))` 를 WebKit 이 이 쓰임에서 다르게 푸는 것으로 보인다(`getComputedStyle(row).getPropertyValue('--k')` 는 식 그대로).
- `main > :not(#moments)` 를 숨기면 WebKit 4폭(390·768·1024·1440) 모두 `scrollWidth === innerWidth` — #moments 는 넘침 0(`.scratch/moments/overflow2.mjs`).

## 4. integration(알림) — 수용 테스트 하네스

- `html { scroll-behavior:smooth }`(감속 아님) 이라 `window.scrollTo(0, y)` 는 부드럽게 굴러간다. 위치별 단언은 `window.scrollTo({ top: y, behavior: 'instant' })` 로(내 점검 `.scratch/moments/probe.mjs` 가 그렇게 해서 크로뮴·웹킷 22/22·21/22 — 웹킷 빨강 1 은 위 3).
- 무대 상태는 `.moments-stage .obj[data-idx][data-active|data-lit]` · `.moments-stage[data-engaged]`(디버그용 표식) · `.moments-stage[data-first]` 로 읽을 수 있다. 인라인 오브젝트에는 `data-idx`·`data-lit` 이 없다(`[data-idx="1"][data-lit]` 가 인라인 때문에 거짓 초록이 되지 않게).

## 5. 알림 — 데브 로그의 'Module not found: ./moments.css' 한 줄

`Moments.tsx` 를 먼저 저장하고 `moments.css` 를 몇 초 뒤 만든 탓에 그 사이 한 번 오버레이가 떴다(`.scratch/dev.log`). 곧바로 "Compiled" · `GET / 200` 으로 회복했고 재시작은 하지 않았다.
