# requests — hero(④ 섹션)

작성 2026-10-12 · hero. 공용 파일은 고치지 않았다. 내 파일: `components/hero/{Hero.tsx,HeroStage.tsx,comet-path.ts,comet-path.test.ts,copy.ts}`.
증거 캡처·스크립트: `landing/.scratch/hero/`(gitignore).

---

## 1. primitives → 통합 — `components/ui/AingClip.tsx` 층 교체 순간 아잉이 2–4프레임 사라진다(P1)

**무엇**: 두 번의 층 교체에서 들어오는 `<video>` 가 첫 프레임을 화면에 내기 **전에** 나가는 층을 `opacity:0` 으로 내린다.
- 도착 순간(포스터 → `aing-commute-start`): 포스터 숨김 → once 첫 프레임 표시(`requestVideoFrameCallback`)까지 **35 · 58 · 44ms**(크로뮴, 데브 3000, 3회). 연사 `.scratch/hero/burst/sheet.png` 둘째 칸 — 근무 라벨만 있고 아잉이 없다.
- 도착 +1.5s(once → idle): 같은 빈 칸. 연사 `.scratch/hero/burst2/sheet.png` 셋째 칸.
- 재현: `node .scratch/hero/gap.mjs`(포스터 숨김 ↔ 첫 프레임 ms) · `node .scratch/hero/burst.mjs` · `node .scratch/hero/burst2.mjs`.

**왜**: SPEC §0.3 "`aing-rest-poster` … 포스터 → 폴짝 이음매 0", §5.5 "층 교체(TD §3) … 자세 튐 0". 이 순간이 페이지의 '기억에 남을 하나'(§1.2)의 정점이다. 아웃트로(포스터 → idle)도 같은 길이라 같은 깜빡임이 날 수 있다.

**제안**(AingClip 안에서만 — 서명 그대로): 들어오는 층이 실제로 프레임을 낸 뒤에 나가는 층을 내린다.
```diff
+  // 실제로 프레임이 화면에 나온 층(들어오는 층이 첫 프레임을 낼 때까지 나가는 층을 덮어 둔다)
+  const [shown, setShown] = useState<"poster" | "once" | "idle">("poster");
+  useEffect(() => {
+    if (layer === shown) return;
+    const root = rootRef.current;
+    // once 층은 DOM 에서 idle 층보다 앞 — 이름으로 고르는 편이 안전하면 SpritePlayer 래퍼에 data-layer 를 단다
+    const v = [...(root?.querySelectorAll("video") ?? [])].find((x) => (layer === "idle" ? /idle/ : /commute/).test(x.currentSrc));
+    let done = false;
+    const finish = () => { if (!done) { done = true; setShown(layer); } };
+    const safety = window.setTimeout(finish, 300);
+    if (v && "requestVideoFrameCallback" in v) v.requestVideoFrameCallback(() => finish());
+    else if (v) v.addEventListener("playing", () => requestAnimationFrame(() => requestAnimationFrame(finish)), { once: true });
+    else finish();
+    return () => { done = true; window.clearTimeout(safety); };
+  }, [layer, shown]);
 …
-  opacity: layer === "poster" ? 1 : 0,                       // 포스터
+  opacity: layer === "poster" || shown === "poster" ? 1 : 0,
 …
-  style={layerStyle(layer === "once")}                         // once
+  style={layerStyle(layer === "once" || (layer === "idle" && shown === "once"))}
 …
-  const onceMounted = videosOK && onceWanted && !(idleWanted && seekDone);
+  const onceMounted = videosOK && onceWanted && !(idleWanted && seekDone && shown === "idle");
```
한 프레임 겹쳐도 보이지 않는다: once 0번 칸 = 포스터(바이트 동일, SPEC §9.2), idle 이어지는 칸 = once 끝 자세(`idleResumeFrame`). 층 순서는 이미 포스터 < once < idle(나중 층이 위).

**히어로는 우회하지 않았다**: 바깥에서 포스터를 한 장 덧대면 poster → once 만 가리고 once → idle 은 못 가린다. AingClip 을 `components/hero/` 로 포크하면 아웃트로와 갈라지고 클라 JS 가 두 벌이 된다.

---

## 2. 오케스트레이터 · 리드 — 빛 한 줄 문턱: 작업 지시 24px ↔ SPEC §S1 · PLAN §4.1 12px

- 작업 지시는 "표본 200점이 H1·리드·버튼·메타 상자와 **24px** 이상", SPEC §S1 수용 조건·PLAN §4.1 은 **12px**. `comet-path.test.ts` 는 문서 문턱 12px 로 단언한다(초록).
- 실측 최소 거리(경로 = 림 핵 위, 글자 줄 상자 = `Range.getClientRects()`):
  | 뷰포트 | 최소 | 위치 |
  |---|---|---|
  | 1440×900 | 18.1px | H1 첫 줄 왼쪽 위 |
  | 1440×789 | 17.7px | 같음 |
  | 1280×720 | 18.3px | 같음 |
  | 1024×768 | 19.0px | 같음 |
  리드 ≥ 153 · 버튼 줄 ≥ 74 · 메타 ≥ 42px. 실제 페이지 `getPointAtLength` 로도 같은 값(`.scratch/hero/t6path.mjs`).
- SPEC 의 "손계산 여유 23–27px" 은 H1 첫 줄 폭을 실제(1440×900 에서 480px — `출퇴근 기록을,` 88px)보다 좁게 잡은 값으로 보인다.
- 24px 를 넘기려면 SPEC 기하를 바꿔야 한다(히어로는 하지 않았다): (a) 라벨 → H1 간격 20 → 28(+≈7px, 세로 흐름 규칙 변경) 또는 (b) 빛을 림 바깥 6px 로(림에서 떨어져 보여 "림을 타고"와 어긋난다). 결정이 필요하면 (a) 가 덜 보인다.

---

## 3. 참고 — SPEC 과 글자가 다르거나 해석한 것(서명·카피는 그대로)

1. **App Store 배지 높이 48 고정**(PLAN §4.1 `AppStoreBadge 48`). SPEC §9.1 의 'phone 44' 는 따르지 않았다(PLAN 우선). 애플 여백(높이/4 = 12)은 padding 그대로 두고, 줄 높이가 48 이 되게 바깥 여백만 `-my-3 -mr-3`(phone `-mx-3`).
2. **빛 한 줄 반지름 = 돔 지름/2 − 1.5**(림 핵 위를 달린다 — `RIM_CORE_INSET`). 시작점 = 핵 꼭대기(돔 바깥 꼭대기 + 1.5px, 라벨 위 12.5px). 경로 길이 1440×900 = 1,305px(SPEC ≈1,300).
3. **베지어 조절점**(SPEC 은 `C Lx+…` 로 비워 둠): c1 = 떠나는 점에서 원의 접선 방향으로 60px(림에서 꺾이지 않게), c2 = (E.x − 0.45·(E.x − Lx), E.y)(말풍선에 수평으로 닿게).
4. **말풍선 불변식 여유 1px**: 무대 윗여백 = `17px − 폭 × 218.5/654`(레이아웃 단위 반올림으로 15.98 이 되지 않게). 실측 1440×789 = 17 · 1280×720 = 17. 그 때문에 1440×789 히어로 = 792px(globals `--aing-w` 205 > 와이어 197), 1280×720 = 742.5px(와이어 743) — "못 지키면 히어로가 길어진다" 그대로.
5. **도착 건너뜀 해석**(SPEC "처음 도착 전에 히어로를 벗어났으면 도착을 건너뛴다 … 근무 라벨은 켠다"): ① 마감(2.5s)까지 도착이 시작되지 않음 ② 본 히어로가 .35 미만으로 내려감 ③ 히어로가 화면과 아예 안 겹침(해시 진입 — load 전에 정해 commute-start 요청 0). 건너뛴 경우 `once`·`bubble` 을 빼고, `start` 는 히어로가 .35 이상 보일 때만 준다 → 화면 밖에서는 idle 영상도 받지 않는다(해시 진입 실측: 영상 요청 0 → 위로 오면 근무 라벨 + idle).
6. **Playwright WebKit**: HEVC 알파 디코드 실패 → AingClip 이 once 오류로 건너뜀 → `onArrive` 가 먼저 와서 빛 한 줄이 ~50ms 달리다 접힌다(1.2s 페이드). 포스터 + 근무 라벨, 콘솔 0. 실 사파리는 영향 없음(⑧ 실기에서 확인).
7. 웹킷에서 리드 둘째 문장이 한 번 더 꺾이던 것(가운데 정렬 flex 열의 맞춤 폭)을 H1·리드에 `w-full` 로 막았다 — 크로뮴 배치 불변(실측).
8. `app/layout.tsx` 의 포스터 preload 는 이제 `/` 에서 쓰인다(AingClip 포스터 `<img>` 와 같은 URL) — core requests §3 의 `/` 경고는 사라짐(크로뮴·웹킷 콘솔 warning 0). `/licenses` 경고는 그대로(통합 판단).
