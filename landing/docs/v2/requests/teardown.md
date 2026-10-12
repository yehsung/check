# teardown — 인계 메모(공용 파일 변경 요청 없음)

작성: teardown, 2026-10-12. ① 철거(TD §5 P0–P5 + PLAN §0.1 ① 1–6) 완료. 아래는 **② 가 원래 맡은 일**인데 철거 뒤 남아 있는 v1 흔적이다. 고칠 사람과 근거만 적는다.

| 남은 것 | 어디 | 누가(근거) |
|---|---|---|
| `NAV_LINKS` 가 v1 앵커·모양(`{label, href}` 4개: `/#team`·`/#iphone`·`/#install`·`/#faq`) | `data/site-links.ts` (TD §5 대로 cp 만 함) | core ②(b) — PLAN §3.6 의 3개 `/#features`·`/#install`·`/#faq` |
| `SendMacLink`(Mac 링크 보내기·`navigator.share`)·`"use client"`·`Placement` 의 `closing` | `components/ui/DownloadCTA.tsx` | primitives — SPEC §6.2 · DECISIONS D9. 지우면 `data/fixtures.ts` 의 `ANNOUNCE.linkCopied` 소비처가 0 이 된다(core 가 SPEC §6.3 대로 삭제) |
| `onClick`·`ariaLabel`·버튼 분기 | `components/ui/Bubble.tsx` | primitives — SPEC §6.2 |
| `LABELS`·`PANELS`·`PHONE`·v1 `ALT`·`RELEASE_FALLBACK`(0.3.48) | `data/fixtures.ts`(TD §2.9 까지만 정리함) | core ②(a) — SPEC §6.3 · DECISIONS D4·D18 |
| `useCenterLine`(사용처 0) | `lib/hooks.ts` | core — PLAN §3.1 '통합이 확인 후' |
| 주석의 `PanelSlot`·"조상 transform 금지" | `components/ui/MacWindowShell.tsx:5` 등 | primitives — SPEC §6.2 |
| v1 토큰·스파인/핫스팟 키프레임, `themeColor #12131C`, 800 글꼴 | `app/globals.css` · `app/layout.tsx` | core ②(b)(c) |

참고(확인한 사실):
- `tsconfig.json` 의 `**/*.ts` 는 점으로 시작하는 폴더를 건너뛴다 — `.scratch/**/*.ts` 는 tsc 대상이 아니다(`tsc --listFilesOnly` 실측 0건). eslint 는 `.scratch/**` 를 globalIgnores 로 뺀다.
- `lib/aing.ts` 는 import 0, 테스트는 `node --experimental-strip-types --test lib/aing.test.ts`(4건 초록). PLAN §8 의 `test:unit` 글롭(`lib/**/*.test.ts`)에 그대로 잡힌다.
- 되돌릴 길은 `.scratch/landing-v1-2026-10-12.tgz`(269항목) 하나. 삭제 직전 트리와 `diff -rq` 차이 0 을 확인했다(app·components·lib·data).
