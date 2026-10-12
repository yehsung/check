# requests — assets(② 스캐폴드)

작성 2026-10-12 · assets. 공용 파일은 고치지 않았다. 아래는 다른 소유자가 처리할 것.

## 1. core — `data/fixtures.ts` `AssetKey` 에 새 키 11개(SPEC §6.3)

**무엇**: `AssetKey` 유니언에 아래 11개 리터럴을 더한다. 파일과 `data/generated/assets.json` 항목은 이미 있다(`node scripts/build-assets.mjs --only=ui,data`, 2026-10-12 18:35).
**왜**: `asset('ui/poke-slice')` 등이 타입 오류 없이 컴파일되게(v1 DECISIONS §4 — 손으로 적은 유니언).

| 키 | w | h | bytes | src(현재 해시) |
|---|---|---|---|---|
| `ui/header-on-lg` | 1264 | 428 | 17,878 | `/assets/ui/header-on-lg.webp?v=d9a59d04` |
| `ui/menubar-0000-lg` | 463 | 132 | 7,148 | `/assets/ui/menubar-0000-lg.webp?v=565a634d` |
| `ui/menubar-icon` | 66 | 66 | 1,596 | `/assets/ui/menubar-icon.webp?v=ea2eecc5` |
| `ui/poke-slice` | 762 | 852 | 18,942 | `/assets/ui/poke-slice.webp?v=2a9100e6` |
| `ui/token-slice` | 472 | 670 | 17,718 | `/assets/ui/token-slice.webp?v=5c49e8bc` |
| `ui/league-slice` | 496 | 427 | 17,140 | `/assets/ui/league-slice.webp?v=a7311e4c` |
| `ui/message-unread-panel` | 954 | 900 | 28,576 | `/assets/ui/message-unread-panel.webp?v=4aef0f92` |
| `ui/message-read-panel` | 954 | 900 | 28,486 | `/assets/ui/message-read-panel.webp?v=8ff4e2b6` |
| `ui/character-panel` | 954 | 900 | 30,666 | `/assets/ui/character-panel.webp?v=c505987e` |
| `ui/timer-00-00` | 264 | 120 | 10,826 | `/assets/ui/timer-00-00.webp?v=ecf3ef48` |
| `char/aing-rest-poster` | 654 | 790 | 17,426 | `/assets/char/aing-rest-poster.webp?v=c279d5f4` |

제안 diff(유니언 끝에 추가 — 기존 키는 그대로, DECISIONS D11):
```diff
 export type AssetKey =
   | …기존 키…
+  | 'ui/header-on-lg'
+  | 'ui/menubar-0000-lg'
+  | 'ui/menubar-icon'
+  | 'ui/poke-slice'
+  | 'ui/token-slice'
+  | 'ui/league-slice'
+  | 'ui/message-unread-panel'
+  | 'ui/message-read-panel'
+  | 'ui/character-panel'
+  | 'ui/timer-00-00'
+  | 'char/aing-rest-poster';
```
참고: 위 w·h 는 파일 픽셀이다(표시 크기는 SPEC §9.2·§S4 표가 정본). 파일 배율 — `header-on-lg` = @4x 원본 그대로, `poke-slice`·`message-*-panel`·`character-panel` = @3x 원본 크롭 그대로, `token-slice`·`league-slice` = @3x 크롭 ×2/3(= @2x), `timer-00-00`·`aing-rest-poster` = 캔버스 ×.5(`aing-idle-poster` 와 같은 배율).

## 2. core — `app/layout.tsx` 글꼴 전환(이미 계획된 일, 알림만)

- `public/fonts/pretendard-500-sub.woff2`(47,076B) · `pretendard-600-sub.woff2`(47,172B) · `pretendard-300-num.woff2`(2,004B) 가 생겼다(`docs/v2/.fonts-done`).
- 지금 크기는 `--from-spec`(SPEC §3 본문 전체 ∪ 철거 전 소스, 한글 571자) 이라 SPEC §2.3 의 ≈36,000B 보다 크다. ⑤ 통합이 `npm run subset`(소스 모드)로 다시 만들면 줄어든다.
- `pretendard-300-num.txt` = `.0123456789:주콕`(SPEC §6.4 코드 블록에서). `data/figures.ts` 가 §6.4 와 다른 글자를 쓰면 `check-glyphs` 가 exit 1 — 그때는 `npm run subset -- --from-spec` 또는 소스 모드로 다시 만든다(assets/integration).
- `scripts/check-glyphs.mjs` 는 이제 `pretendard-500-sub.txt`·`pretendard-600-sub.txt`(소스 한글) + `pretendard-300-num.txt`(`data/figures.ts` 글자)를 본다. `pretendard-800-sub.*` 는 보지 않는다.

## 3. integration(⑤) — v1 800 서브셋 삭제

- `public/fonts/pretendard-800-sub.{woff2,txt}` 는 지우지 않았다(오케스트레이터 지시: `app/layout.tsx` 가 아직 가리킨다). PLAN §5.3-5 "public/fonts 에 800 없음" 은 이 때문에 **빨강으로 남김** — layout 전환을 확인한 뒤 ⑤ 가 `rm public/fonts/pretendard-800-sub.woff2 public/fonts/pretendard-800-sub.txt`. 빌드 검증 목록(`FONT_OUTPUTS`)에서는 이미 뺐다.
- `node scripts/build-assets.mjs` 끝의 경고 "④ 크롬 경로 에셋 4.40MB + JS·CSS ≈0.21MB 가 4.5MB 를 넘을 수 있다" 는 `public/assets` **디스크 전체 합**(v2 가 요청하지 않는 v1 출력 포함 — DECISIONS D11)이라 페이지 예산과 다르다. 예산은 T13 실측으로 판정.

## 4. 참고 — SPEC §9.4 와 다르게 한 것

- SPEC §9.4 는 `char/aing-rest-poster` 를 char 묶음 포스터 레시피로, 재생성을 `--only=ui,char,data` 로 적었지만 PLAN §5.1·§5.2(우선)를 따라 **ui 묶음의 `V2_CROPS`** 에서 굽고 `--only=ui,data` 로 돌렸다(영상 재인코딩 0). `sequences.json`·`grass.json`·`bubbles.json` 은 바이트 그대로(내용이 같으면 다시 쓰지 않음).
