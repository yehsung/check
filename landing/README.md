# 아잉체크 랜딩

아잉체크(aing-check) 공개 랜딩페이지. Next.js 16 App Router + TypeScript + Tailwind 4. 배포는 Vercel(루트 디렉터리 `landing/`) 예정.

## 실행

```bash
npm install
npm run dev        # http://localhost:3000
npm run build      # prebuild 로 글꼴 서브셋 누락 글자 검사(check-glyphs)
npm run typecheck && npm run lint
```

## 문서(정본)

- `docs/v2/SPEC.md` — 디자인·카피·토큰·에셋 목록. 카피는 이 문서가 고른 `docs/content-brief.md` 문장 그대로 쓴다.
- `docs/v2/PLAN.md` — 파일 소유권, 공용 API, 수용 테스트.
- `docs/v2/DECISIONS.md` — 결정 기록(셋이 어긋나면 DECISIONS > PLAN > SPEC).
- `docs/content-brief.md`, `docs/asset-manifest.md` — 사실 출처와 소재 실측.
- `docs/SPEC.md`, `docs/PLAN.md`, `docs/DECISIONS.md`, `docs/requests/` — 거부된 v1 기록(정본 아님).

## 에셋·글꼴

소재 원본은 `/Users/yesung/aing-check-promo/public/assets/`(저장소 밖). `public/assets/`·`public/fonts/`·`data/generated/` 는 스크립트 출력이며 커밋 대상이다.

```bash
npm run assets     # scripts/build-assets.mjs — 렌더 webp, 캐릭터 알파 영상(webm/mov), JSON 메타
npm run subset     # scripts/subset-fonts.mjs — 소스 글자로 Pretendard 500·600 서브셋 + 300 숫자 전용 서브셋
```

## 다운로드 경로

- `/api/download` → GitHub 최신 릴리스의 `aing-check.dmg` 로 302 (`?file=zip` 은 zip). 폴백 상수는 `data/fixtures.ts` 의 `RELEASE_FALLBACK`.
- `/api/release` → 최신 릴리스 JSON(1시간 ISR).

환경 변수(선택): `NEXT_PUBLIC_SITE_URL`(배포 도메인), `GITHUB_TOKEN`(API 한도).
