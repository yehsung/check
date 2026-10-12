> 거부된 v1(2026-10-12 15:50). v2 정본은 `docs/v2/`(SPEC·PLAN·DECISIONS). 이 문서의 SPEC §1.4 사실 규칙·§9 에셋 표, 그리고 `docs/v2/DECISIONS.md` §1 표에 적힌 v1 결정만 v2 가 승계한다.

# DECISIONS — 오케스트레이터 결정(SPEC.md·PLAN.md 와 어긋나면 이 문서가 이긴다)

작성 2026-10-12 08:50 KST. 모든 에이전트는 작업 전에 이 문서 → `docs/PLAN.md` → `docs/SPEC.md`(자기 절) 순서로 읽는다.

## 1. 프레임워크 버전 — PLAN 의 "Next 15 · motion 12" 는 아래로 읽는다
- `create-next-app@latest` 가 깐 그대로: **Next 16.4.0 · React 19.3 · Tailwind 4.3(`@tailwindcss/turbopack`, postcss 설정 없음) · eslint-config-next 16.4 · TypeScript ^5**. 추가로 `motion ^14.1`(dep), `sharp ^0.35`(dev).
- **이 Next 는 학습 데이터와 다르다.** 코드를 쓰기 전에 `node_modules/next/dist/docs/01-app/02-guides/upgrading/version-16.md` 와 자기 영역 문서(`01-app/01-getting-started/13-fonts.md`, `14-metadata-and-og-images.md`, `15-route-handlers.md`, `03-api-reference/03-file-conventions/02-route-segment-config/`)를 읽는다.
- `next.config.ts` 에서 **`cacheComponents` 는 껐다**(고전 ISR). 그래서 `export const revalidate = 3600` 과 라우트 핸들러의 `fetch(..., { next: { revalidate } })` 가 PLAN 대로 동작한다. `'use cache'`·`cacheLife` 는 쓰지 않는다.
- 레이아웃 props 타입은 전역 `LayoutProps<"/">`(템플릿 그대로 써도 되고 `{ children: React.ReactNode }` 도 된다). `themeColor` 는 `metadata` 가 아니라 `export const viewport: Viewport` 에 둔다.
- 이미지 최적화는 끔(`images.unoptimized`), `<img>` 직접 사용(RenderImage). `next/image` 금지는 SPEC §8.2 그대로.

## 2. 포트 — dev·start 모두 **3000**(PLAN 의 3210 → 3000)
사용자가 아침에 `http://localhost:3000` 에서 본다. 섹션 에이전트는 어차피 dev 금지.

## 3. 의존성 — `@playwright/test` 를 넣지 않는다
- 검수 스크립트는 `createRequire('/Users/yesung/Aingo/node_modules/')` 로 `require('playwright')`(1.60, chromium·webkit·firefox 설치됨)를 쓰고 **`landing/` 밖**(세션 scratchpad `/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/`)에 둔다. `tests/e2e/`·`playwright.config.ts` 는 만들지 않는다.
- 이미 있는 촬영 하네스: `…/scratchpad/tools/shoot.mjs <url> <outdir> [--widths 390,768,1440] [--reduced]` → `w{폭}-fold.png`·`w{폭}-full.png`·`report.json`(콘솔 에러·페이지 에러·실패 요청·깨진 이미지·가로 넘침·전송 KB).
- 의존성 추가는 금지(요청은 `docs/requests/`).

## 4. AssetKey 는 손으로 적은 유니언
- `data/fixtures.ts` 에 `AssetKey` 를 SPEC §9 출력 목록 전부(확장자 뺀 `ui/popover-off` 꼴)로 **문자열 리터럴 유니언**으로 적는다. 영상 시퀀스 이름은 `SequenceName`(PLAN §3.5).
- `data/generated/{assets,sequences,bubbles,grass}.json` 은 지금 `{}` 스텁이고 assets 에이전트가 덮어쓴다. 읽는 쪽은 `import assets from '@/data/generated/assets.json'` 뒤 `as Record<string, AssetMeta>` 로 느슨하게 받고, 키가 없으면 개발 모드 `console.warn` + props 크기의 빈 `<img alt>` 를 그린다(빌드가 깨지지 않게). `typeof assets` 로 타입을 뽑지 않는다.

## 5. 스캐폴드는 4명이 동시에 쓴다 — 파일 소유권(PLAN §2 세분)
| 에이전트 | 소유 파일 |
|---|---|
| `assets` | `scripts/build-assets.mjs` · `scripts/subset-fonts.mjs` · `scripts/check-glyphs.mjs`(지금은 자리표시자) · `scripts/make-qr.py` · `public/assets/**` · `public/fonts/**` · `data/generated/*.json`(덮어쓰기) · `app/icon.png` · `app/apple-icon.png` · `vercel.json` |
| `core` | `app/globals.css` · `app/layout.tsx` · `app/page.tsx` · `app/api/download/route.ts` · `app/api/release/route.ts` · `lib/release.ts` · `lib/demo/{types,reducer,store,selectors,reducer.test}.ts` · `lib/{hooks,media,platform}.ts` · `data/fixtures.ts` · 섹션 스텁 9개 `components/sections/*.tsx` · `tsconfig.json`·`eslint.config.mjs`·`next.config.ts`·`package.json`(필요할 때만, 최소 수정) |
| `primitives-a` | `components/ui/{Button,DownloadCTA,AppStoreBadge,QrCode,TextLink,SectionShell,Headline,TimeMark,MacWindowShell,RenderImage,RenderStack,Hotspot,PanelSlot,Segmented,CopyButton,CommandBox,VisuallyHidden,PlatformScript,LiveAnnouncer}.tsx` |
| `primitives-b` | `components/SpritePlayer.tsx` · `components/sprite/{AlphaVideo,SheetPlayer}.tsx` · `components/ui/{Bubble,TimerCapsule,PhoneShell,TickStrip,CharacterStage,AingStageInline}.tsx` |
- 계약 순서: `core` 는 **먼저** `lib/demo/types.ts`(DemoState·DemoEvent·SectionId 등 SPEC §3.1 + PLAN §3.1 서명 전부) · `data/fixtures.ts`(SPEC §6 전문 + AssetKey) · `lib/{hooks,media,platform}.ts`·`lib/demo/{reducer,store,selectors}.ts` 의 **export 서명**(본문은 임시 구현이어도 됨)을 쓰고 `touch docs/.contracts-done` 한다(목표 15분 안). 그 뒤 본 구현.
- `primitives-a/b` 는 PLAN §3 서명대로 코드를 쓰되 `docs/.contracts-done` 이 생기기 전에는 `tsc` 를 돌리지 않는다(`while [ ! -f docs/.contracts-done ]; do sleep 20; done` 식으로 기다린다, 최대 40분). 서명이 PLAN 과 다르면 **자기 쪽을 맞추고** `docs/requests/<agent>.md` 에 적는다. core 파일은 고치지 않는다.
- `primitives-a` 의 `RenderStack`(overlay:'tick')은 `primitives-b` 의 `TickStrip` 을 PLAN 서명 `{ startedAt: number|null; scale: number }` 으로 import 한다. `PanelSlot`·`AingStageInline` 처럼 서로의 파일을 import 하는 곳은 상대 파일이 아직 없으면 그 에러만 남기고 끝낸다(검증 에이전트가 맞춘다).
- 각자 끝나면 `touch docs/.<agent>-done` 하고 결과를 보고한다. **`next build`·`next dev` 는 스캐폴드 단계에서 `assets`·`core` 만**(core 는 자기 파일 범위에서 `npm run build` 1회 허용, dev 는 띄우면 반드시 끈다), primitives 는 `tsc --noEmit`·`eslint <자기 파일>` 만.

## 6. 공통 금지
- 서브에이전트·스킬 호출 금지. git 상태를 바꾸는 명령 금지(add·commit·stash·checkout·reset·clean·push). 워크트리 금지.
- `landing/` 밖은 읽기만(소재 `/Users/yesung/aing-check-promo/public/assets/**`, 글꼴, 앱 아이콘 `/Users/yesung/check/packaging/appicon/icon-1024.png`). 저장소의 `Sources/`·`Tests/` 등은 열지도 않는다.
- 임시 파일은 `landing/.scratch/<agent>/`(gitignore 됨) 또는 OS 임시 폴더. 끝나면 `.scratch/<agent>` 를 비운다. 떠 있는 node·chromium·ffmpeg 프로세스를 남기지 않는다.
- 명령 출력은 exit code 로 판정하고, `| grep`·`| tail` 로 실패를 가리지 않는다. 백그라운드로 띄운 서버는 `kill` 까지가 작업이다.

## 7. 글꼴 서브셋(스캐폴드 시점)
섹션 카피가 아직 소스에 없으므로 `assets` 는 첫 서브셋을 **`docs/SPEC.md` §4·§6 본문 전체의 글자 + 숫자·ASCII·한글 문장부호(「」·…)** 로 만든다(`scripts/subset-fonts.mjs --from-spec`). 통합 단계에서 소스 스캔(기본 모드)으로 다시 만든다. `check-glyphs.mjs` 는 소스 글자 ⊄ 서브셋이면 exit 1 — 단 `pretendard-800-sub.txt` 가 없으면 경고만 하고 통과.

## 8. 기타 확정
- 센터(서울/부산) FAQ 미게재(SPEC 기본값). OG 이미지는 통합 단계(그 전 `openGraph.images` 생략).
- `/api/download` 는 302 + `Cache-Control: no-store`, DMG 기본, `?file=zip`. 폴백 상수는 SPEC §6 `RELEASE_FALLBACK`.
- `AGENTS.md`(Next 가 생성)는 그대로 둔다.

## 9. 추가(09:40) — Playwright WebKit 설치됨
`~/Library/Caches/ms-playwright/webkit-2287` 이 이제 있다(`createRequire('/Users/yesung/Aingo/node_modules/')` 의 playwright 1.60 이 쓴다). 통합 단계는 WebKit 으로 첫 화면·#poke 촬영 + 콘솔 error 0 + **`.mov`(HEVC 알파) 투명 확인**(`scratchpad/tools/alpha-probe.mjs` 를 webkit 으로)을 실제로 한다. 검증 단계의 "WebKit 미설치" 메모는 더 이상 유효하지 않다.
