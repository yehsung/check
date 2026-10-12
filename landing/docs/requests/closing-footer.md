> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# closing-footer — 요청·공지

작성: closing-footer, 2026-10-12. 대상: `components/sections/ClosingFooter.tsx`(+ `SiteFooter` 이름 붙은 내보내기) · `components/sections/closing-footer/**` · `app/licenses/page.tsx`.
공용 파일을 고쳐야만 동작하는 것은 **없다**(전부 내 폴더 안에서 끝냈다). 아래 1·2 는 선택 개선, 3·4 는 통합 단계 확인 요청이다.

## 1. (선택) `/licenses` 의 내비를 MenubarStage 의 띠로 바꾸기 — stage-menubar · integration
- **무엇**: `/licenses` 는 지금 로컬 판 `closing-footer/LicensesNav.tsx`(48px sticky 띠, 워드마크 → `/`, 링크 4개 → `/#team` `/#iphone` `/#install` `/#faq`, phone 은 '설치' 캡슐)를 쓴다.
- **왜**: SPEC S14 는 "같은 내비·푸터"인데, `MenubarStage` 는 다른 섹션 소유(import 금지)이고 띠 + 메뉴바 라벨 + 스파인(데모 상태)을 함께 그려서 라이선스 페이지에 그대로 두면 popover-off 가 매달린다. 또 `DownloadCTA placement="nav"` 의 phone 링크가 `#install`(상대)이라 `/licenses#install` 로 간다.
- **제안**: MenubarStage 가 라벨·스파인 없는 띠만 `export function NavBar({ standalone }: { standalone?: boolean })` 로 내보내면(standalone 이면 링크·phone 설치 링크를 `/#…` 로), `app/licenses/page.tsx` 에서
  ```diff
  - import { LicensesNav } from "@/components/sections/closing-footer/LicensesNav";
  + import { NavBar } from "@/components/sections/menubar-stage/NavBar";
  …
  - <LicensesNav />
  + <NavBar standalone />
  ```
  로 바꾸고 `LicensesNav.tsx` 를 지운다. 안 바꿔도 동작·접근성(건너뛰기 링크·`nav aria-label="주요"`)은 맞다.

## 2. (선택) `RenderImage` 에 `id` 통과 — primitives-a 영역(통합이 처리)
- **무엇**: SPEC S13 "근무 종료 버튼 `aria-describedby` 로 라벨 상태 연결" 을 위해 확대 라벨 `<img>` 를 `<span id="closing-label-state">` 로 감쌌다(설명 계산이 자식 img 의 alt 를 읽는다 — 동작은 같다).
- **제안 diff**(`components/ui/RenderImage.tsx`): props 에 `id?: string` 추가, `<img id={id} …>`. 들어오면 span 을 걷어도 되지만 필수는 아니다.

## 3. 통합 확인 — CLS 측정 범위
- SPEC S13 순서대로 헤더 카드는 **꾸벅(commute_end)이 끝난 뒤**(≈1.35s, 대기열이 있으면 더 늦게 — 상한 3s 폴백) 높이 0→131px 로 열린다. 사용자 입력 500ms 밖이라 `layout-shift` 의 `hadRecentInput` 이 false 다. §7.4 CLS ≤ 0.05 를 **로드 구간**에서만 재면 무관하고, 근무 종료 흐름까지 합쳐 잰다면 이 한 번(아래 CTA 줄·푸터가 밀림)이 잡힐 수 있다. 그때는 SPEC 과 상의해 "누르는 즉시 자리만 열고 카드는 꾸벅 뒤 불투명으로" 로 바꿀 수 있다(내 파일 안에서 10줄).

## 4. 통합 확인 — 동작 메모(테스트 작성용)
- 확대 라벨은 `work === 'ended'` 일 때만 `menubar-off-lg`, 그 밖(진입 전·SSR 포함)은 `menubar-0642-lg`. 이 절에서 `labelKey` 는 evening='0642'·ended='off' 둘뿐이라 같은 뜻이고, 진입 전에 'off'(출근 전)를 따르지 않는 것은 SSR 첫 페인트에서 '오프' 라벨 옆에 [근무 종료]가 서는 모순을 피하려는 것.
- [근무 종료] 는 `activeSection !== 'closing'` 이면 먼저 `setActiveSection('closing')` 을 부른 뒤 `pressEnd()`(빠른 스크롤·사파리 클릭 무포커스 대비). 꾸벅 중 재클릭은 무시.
- 카드가 열리는 순간 [근무 종료] 자리가 같은 200ms 로 접히고(inert) 포커스는 카드의 `[근무 시작]`(Hotspot, `aria-label="근무 시작"`)으로, 재시작하면 카드가 접히고 포커스는 [근무 종료] 로 돌아온다.
- PLAN §7.2-12 의 셀렉터: 띠 라벨은 MenubarStage 의 것을 보라 — 확대 라벨도 `img[src*="menubar-off-lg"]` / `img[src*="menubar-0642-lg"]` 로 같이 잡힌다(`menubar-off` 부분 문자열이 겹치니 띠 라벨 단언은 `header` 안으로 좁힐 것).
- 닫힌 카드는 SSR 부터 DOM 에 있다(`inert`·`aria-hidden`·`visibility:hidden`, 높이 0). `role=button[name="근무 시작"]` 단언은 `:visible` 로.
- CTA 줄 래퍼에 `data-companion-avoid`(DownloadCTA closing · 배지 · brew 복사, 복사 실패 시 명령 줄 + "⌘C로 복사하세요" 까지 포함).
- 푸터 링크 6개 중 `/licenses` 만 `next/link`(`prefetch={false}` — 첫 페이지 전송 예산), 나머지는 같은 탭 `<a>`. 푸터 패딩은 SPEC "48(phone 40)/64" 을 위 48(phone 40)·아래 64 로 읽었다.
