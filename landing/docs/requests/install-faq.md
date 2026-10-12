> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# install-faq — 요청 1건 · 통합 메모

작성: install-faq, 2026-10-12. 소유 파일: `components/sections/InstallFaq.tsx` · `components/sections/install-faq/**`.

## 1. (primitives-a 소유) `CopyButton` inline 변형의 터치 히트 32 → 44
- **무엇**: `components/ui/CopyButton.tsx` 의 `VARIANT.inline` 에 투명 `::before` 로 위아래 6px 히트를 더한다(보이는 모양은 그대로).
- **왜**: SPEC §7 "터치 히트 최소 44×44". inline 변형은 `h-8`(32px)이라 phone 에서 brew [복사] 버튼이 기준 미달이다. 명령 상자 안쪽 여백(py-2 = 8px)이 있어서 넓힌 영역은 상자 밖으로 나가지 않는다.
- **제안 diff**
  ```diff
  -  inline: "h-8 rounded-[var(--r-seg-in)] px-3 text-ink-1 hover:bg-surface-2",
  +  inline: "relative h-8 rounded-[var(--r-seg-in)] px-3 text-ink-1 hover:bg-surface-2 before:absolute before:inset-x-0 before:-inset-y-1.5",
  ```
- **지금의 우회**: `install-faq/InstallSection.tsx` 에서 CommandBox 를 감싼 div 에 `[&_button]:relative [&_button]:before:absolute [&_button]:before:inset-x-0 [&_button]:before:-inset-y-1.5` 를 걸어 두었다. 위 diff 가 들어가면 이 클래스 넷을 지운다(겹쳐도 결과는 같다).

## 2. 통합 메모(요청 아님)
- **주 버튼 선택**: `InstallFaq.tsx`(서버)가 `await getRelease()` → `installChoice(release, RELEASE_FALLBACK)`(`install-faq/install-copy.ts`, 순수 함수). DMG 가 있으면 "aing-check.dmg 다운로드"(`/api/download`), 없을 때만 "aing-check.zip 다운로드"(`file="zip"` → `/api/download?file=zip`). 접근 이름은 "aing-check.dmg 다운로드, 30.0MB", 메타는 "{version} 버전, {mb}MB. …". zip 이면 안내 1·2단계도 zip 문장으로 바뀐다.
- **설치 안내(installHint)**: `install-faq/InstallBlock.tsx`. 두 판(버튼+메타 / 세 단계+다시 받기)을 다 SSR 하고 하나만 흐름 안, 다른 하나는 `inert` + `invisible` 로 겹쳐 둔다. 래퍼에 `data-install-hint` 가 붙으면 안내 상태(수용 테스트 단언에 쓸 수 있다).
  - 이 블록의 다운로드를 눌렀을 때만 높이 200ms ease-out + 내용 120ms 선형 교차, 포커스는 안내 묶음(tabIndex −1)으로 옮긴다. 새로고침 뒤 sessionStorage 반영·다른 자리(히어로·내비·클로징) 클릭은 즉시 바뀐다. 감속 모션은 전이 0.
  - SSR 은 installHint=false 이므로, 새로고침 직후 #install 이 화면에 있으면 하이드레이션 뒤 한 번 즉시 바뀐다(스토어 설계상 불가피 — 전이 없이 바꿔 깜빡임을 줄였다).
- **플랫폼 순서**: 한 열(tab·phone)에서 `html[data-platform=ios]` 면 iPhone 묶음이 먼저(`order-first`). desk 는 명시 배치(1–7열 · 9–12열)라 영향 없다. Mac 묶음 머리의 [Mac 링크 보내기]는 DownloadCTA 의 ios 판이 그린다.
- **`data-companion-avoid`**: 주 버튼 줄 · brew 명령 상자 · iPhone 묶음(배지·QR·작은 줄) 세 곳.
- **FAQ**: `install-faq/faq-items.ts` 한 출처(SPEC S12 문장을 스크립트로 옮겨 원문 대조 통과) → `<details name="faq" id="faq-N">` 10개(1번만 `open`) + `FAQPage` JSON-LD(`<script type="application/ld+json">`, `<` 이스케이프). 삼각형은 globals.css 의 `.disclosure`(core 가 이미 넣어 둔 것)를 그대로 쓴다. 열린 행 바탕 띠는 summary·답 상자에 `-mx-4 px-4 group-open/faq:bg-surface`(선은 글 열 폭 그대로).
  - 열림 높이 전이는 `motion-safe` + `@supports (interpolate-size: allow-keywords)` 안의 `::details-content`(들어올 때 ease-out, 나갈 때 ease-in 180ms). 그 밖 브라우저·감속 모션은 즉시.
  - `install-faq/FaqHash.tsx`: 로드·hashchange 에서 `#faq-N` 을 열고(다른 문항은 닫힘) `scrollIntoView({block:'start'})` — html 의 `scroll-padding-top` 을 따른다. 1번이 닫히며 위 높이가 줄어드는 동안 자리가 어긋나지 않게, 그 순간만 `<style>` 하나를 head 에 넣어 `details[name="faq"]::details-content` 전이를 끄고 두 프레임 뒤 지운다. `name` 미지원 브라우저용으로 toggle(캡처) 보험이 있다.
- **확인 못 한 것**: dev·build·브라우저를 띄우지 않았으므로 화면·상호작용·하이드레이션은 실행으로 보지 못했다(통합 단계 몫). 확인한 것은 `tsc`·`eslint` 0, 카피 원문 대조·릴리스 선택·JSON-LD 를 node 로, Tailwind 4.3 컴파일러로 이 폴더의 임의 클래스(`group-data-[animate]/install:*`, `[html[data-platform=ios]_&]:order-first`, `group-open/faq:bg-surface`, `details-content:*`, `[&_button]:before:*`)가 기대한 선택자로 나오는지.
