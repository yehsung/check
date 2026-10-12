> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# hero — 요청·공지 (S1 `#top` · S2 `#auto`)

작성: hero, 2026-10-12. 공용 파일을 꼭 고쳐야 하는 요청은 없다. 아래는 통합 단계가 알아야 할 결정과 선택 제안이다.

## 1. S2 의 desk 위 여백을 0 으로 뒀다(SPEC §2.4 의 plain 112 와 다르다)
- **무엇**: `#auto` 는 SectionShell 에 `py-0!` 를 주고, 안쪽 래퍼가 여백을 갖는다. 값은 phone 72/72, tab 96/96, desk **0**/112.
- **왜**: SPEC S1 레이아웃과 PLAN §4.3-1 은 "S1 아래 64px 에 S2 헤드라인 윗부분이 걸쳐 보인다"를 요구하고, S1 desk 높이는 `max(560px, 100svh − 48 − 64)` 로 정해져 있다. 위 여백이 112 면 1440×900 에서 S2 헤드라인이 접힘선보다 48px 아래로 가서 안 보인다. S1 높이를 112 더 줄이면 H1 윗변이 SPEC 의 y≈236 에서 벗어난다.
- **확인할 것(통합)**: 1440×900 첫 화면 아래 64px 에 "깜빡해도, 알아서." 윗부분이 보이는지. 문서 높이 예산(9,000–9,900px)에는 112px 줄어드는 쪽이라 유리하다.

## 2. S2 미리 받기는 "load + idle ∧ 600px 안 ∧ 스크롤 한 번"일 때 시작한다
- **무엇**: idle 영상 · milestone · ultra-charged · 루비 말풍선(`hero-auto/AutoProbe.tsx`).
- **왜**: desk 에서는 첫 화면에 이미 S2 머리가 보여서 "600px 안" 조건만으로는 load 직후 ≈1.3MB 를 받게 된다. SPEC S2 성능은 "S1 이 화면을 반쯤 벗어날 때" 받는다고 적고 있다. 그래서 스크롤을 S2 로 가려는 의도로 본다. idle 영상은 [근무 시작] 의도(pointerenter·touchstart·포커스)에서도 받는다(SPEC §8.2-3).
- 감속 모션·Save-Data 이면 영상 요청은 `preloadSequence` 가 스스로 막는다(포스터·말풍선 그림만).

## 3. 히어로 인라인 창의 `popover-on` 은 load + idle 뒤에 `panels` 에 넣는다
- **무엇**: `PanelSlot panels` 의 처음 값은 `['popover-off']`, load + idle 뒤에는 `['popover-off','popover-on']` 이다. 그 전에 누르면 RenderStack 이 active 판을 늘 마운트하므로 그대로 동작한다.
- **왜**: RenderStack 은 `panels` 를 전부 lazy `<img>` 로 마운트한다. 화면 안에 있으면 불투명 0 이어도 받는다. 그러면 phone 첫 화면 전송에 popover-on 40KB 가 더해진다(예산 350KB, SPEC §8.2-2 는 load + idle 에 받으라고 한다).
- **선택 제안(primitives-a 소유 RenderStack)**: 다른 섹션도 같은 문제가 있을 수 있다. RenderStack 이 active·top·under 가 아닌 판은 `idle()` 뒤에 마운트하게 하면 섹션마다 따로 우회하지 않아도 된다.
  ```diff
  - const list = uniq([...panels, active, top, under]);
  + const [warm, setWarm] = useState(false);
  + useEffect(() => idle(() => setWarm(true)), []);
  + const list = uniq([...(warm ? panels : []), active, top, under]);
  ```

## 4. [근무 시작]을 키보드로 누르면 포커스가 body 로 떨어진다(관찰, 우선순위 낮음)
- popover-on 판에는 startButton 핫스팟이 없어서, 누른 핫스팟이 사라진다. 알림("근무를 시작했어요. 오늘도 화이팅!")은 나오고, 요즘 브라우저는 다음 Tab 을 사라진 자리 다음부터 이어 간다. SPEC 이 포커스 이동을 정하지 않아서 그대로 뒀다.

## 5. 맥동 1회 보장
- Hotspot 의 `pulse` 는 마운트될 때마다 1.2초 뒤에 맥동한다. 히어로를 벗어났다 돌아오면 핫스팟이 다시 마운트되므로, `HeroPopover` 가 첫 맥동이 끝날 즈음(1200 + 700 + 1100ms) `pulse` 를 내린다. 핫스팟이 하이드레이션·스파인 사각형 게시보다 1.1초 넘게 늦게 마운트되면 맥동이 중간에 잘릴 수 있다.

## 6. 그 밖의 배치 메모
- `@container`(container-type) 는 **글 열에만** 있다. container-type 은 fixed 자식의 기준을 바꾸므로 PanelSlot(desk fixed 핫스팟)을 그 안에 넣지 않았다.
- 짧은 phone(폭 < 768 ∧ 높이 ≤ 700)에서만 H1 = `min(40px, 10.3cqi)` 이다. 390×844 는 SPEC 와이어대로 40px 다.
- iOS 순서(배지 → Mac 링크 보내기)는 CSS `order` 를 쓰지 않고 배지를 두 번 SSR 해서 맞췄다(플랫폼별로 하나만 보인다). DOM 순서가 보이는 순서와 같아서 Tab 순서도 같다.
- phone S1 인라인 무대: 창 왼쪽 기준 `left = max(-20px, 8px − gutter)` → 390 에서 화면 x 8, 아래로 20px 걸침. phone S2 무대 자리(180×217.4)는 근무 전에도 비워 둔다(CLS 0).
