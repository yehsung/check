# 3D 아잉이 굽기 (`bake-aing`)

맥이 SceneKit 으로 그리는 3D 아잉이(아잉 · 황금 · 무지개)를 Windows·Android 판이 쓸 2D 칸으로 미리 굽는다.
엔진은 `Tests/checkTests/AingBakeSuite.swift`(앱 장면을 `@testable import check` 로 그대로 돌린다), 인코딩·잠금은 `bake.py`,
진입점은 `bake.sh` 다. 산출물은 `multiplatform/assets/aing-bake/`(+ `lock.json`)에 커밋한다.

## 다시 굽기

```sh
multiplatform/scripts/bake-aing/bake.sh            # 봉인 빌드 + 굽기 → multiplatform/assets/aing-bake/ 를 다시 쓴다
multiplatform/scripts/bake-aing/bake.sh --check    # 임시 폴더에 다시 구워 커밋된 lock.json 과 raw · outputs · inputs 대조
```

- 빌드와 렌더 모두 `sandbox-exec` 로 바깥 네트워크를 막는다. 빌드에는 `--disable-sandbox` 가 필요하다
  (SwiftPM 의 매니페스트 샌드박스를 sandbox-exec 안에서 또 걸 수 없다 — 없으면 `sandbox_apply: Operation not permitted`).
- 창을 띄우지 않는다(`SCNRenderer` 오프스크린만).
- 굽기가 소유 경로 밖을 바꾸면 종료 코드 4 다. 굽기 전후로 소유 밖 더러운 파일의 (상태, 경로, sha256) 을 비교한다
  (`bake.py outside-snapshot`) — 이미 수정돼 있던 파일을 또 바꿔도 잡힌다.
- 종료 코드: 0 성공 · 1 빌드/굽기/`--check` 대조 실패 · 2 도구·인자 · 3 크기 예산 초과 · 4 소유 밖 변경.
- 같은 입력이면 같은 바이트가 나온다(이 맥, M4 Pro · Xcode 27.1 · cwebp 1.6.0 에서 세 번 실측). 다른 맥은 F-10 미검증이다(아래).

## 알파 형식 (마스터 계획 G §8-12 — 설계 F §3.4 를 대체)

| 파일 | 알파 | 인코딩 | 읽는 쪽 |
|---|---|---|---|
| 칸 · 감은 눈 패치 페이지(`bake.pages`) | **프리멀티 그대로** | WebP 손실 q90, 알파 평면 무손실(`-alpha_q 100 -exact`) | 재생기(W5-a): 곱하지 않고 디코드 → 프리멀티 표면에 그대로 |
| 💤 글리프(`bake.glyph`) | **프리멀티 그대로** | WebP 무손실 | 재생기 |
| 골든(`golden/*.webp`) | 프리멀티 그대로 | WebP 무손실 | 렌더 대조 시험 |
| `legacy.webp`(2칸 스프라이트) | 직선(표준 WebP) | WebP 손실 q90, 알파 무손실 | 기존 스프라이트 디코더 |

- 이유: SceneKit 은 반투명을 "선형 프리멀티 후 sRGB 부호화"로 적어서 가장자리 픽셀의 색이 알파를 넘는다. 직선으로 바꾸면 C 가 255 로
  잘려 가장자리가 최대 73단계 어두워진다(실측: 반투명 픽셀 1,187,907개 중 1,157,220개 = 97.4%).
- 매니페스트 `bake.alpha`(역할별 알파 + 디코드 클램프) · `bake.encoding`(역할별 손실/무손실) · `bake.cwebpArgs`(실제 cwebp 인자)가 이 표를 적는다.
- **재생기는 칸 페이지를 디코드한 뒤 채널마다 `min(c, table[A])` 를 해야 한다**(`bake.alpha.decodeClamp.table`, 256칸).
  손실 RGB 의 코덱 잡음이 알파 0 자리에도 색을 남겨, 프리멀티 표면에선 몸 둘레에 빛으로 더해진다. SceneKit 값은 이 표를
  넘을 수 없으므로(굽기가 칸마다 재고, 넘으면 실패한다) 클램프는 진짜 픽셀을 바꾸지 않는다.
- 페이지를 WebP 무손실로 담으면 묶음이 예산을 크게 넘는다. 그래서 칸 페이지의 "무손실"은 **알파 평면 무손실 + 알파 변환 없음**이고
  RGB 평면은 손실 q90 이다. 실측(같은 원본 39페이지, 2026-10-21. 오차는 재생기 표면 값과 SceneKit 원본의 채널 차이, 0–255.
  커밋본은 매니페스트에 클램프 표가 더해져 클램프 없는 줄보다 12,972 B 크다):

  | 페이지 인코딩 | Android 기본 | Windows | 커밋 합계 | 표면 값 오차(전체 평균 · p99.9 · 반투명 평균) | 알파 0 빛 |
  |---|---|---|---|---|---|
  | 직선 · 손실 q90(첫 굽기) | 4,041,166 B | 16,647,923 B | 25,937,385 B | 0.90 · 59 · 31.6 | 0 |
  | 프리멀티 · 손실 q90(클램프 없음) | 3,964,344 B | 16,129,553 B | 25,339,625 B | 0.85 · 32 · — | 13,190,070 채널(최대 90) |
  | **프리멀티 · 손실 q90 + 디코드 클램프(채택, 커밋본)** | **3,977,316 B** | **16,142,525 B** | **25,352,597 B** | **0.73 · 24 · 3.8** | **0** |
  | 프리멀티 · near-lossless 60 | 10,263,444 B | 58,794,475 B | 74,303,647 B | 0.09 · — · — (알파도 ±2) | 0 |
  | 프리멀티 · 무손실 | 11,569,558 B | 62,776,867 B | 79,592,153 B | 0 | 0 |

## 크기 예산 (`config.json` → `bundles`, `bake.py sizes`)

| 묶음 | 정의 | 예산 |
|---|---|---|
| `windows` | S·U 칸 · 메타 · legacy · 글리프 · 트랙 + 후광 원본 PNG | 20,000,000 B |
| `androidDefault` | L 쉬는 행 · L 감은 눈 패치 · **S 스핀 행(페이지 셋 + cells-S — 공개 한 바퀴, G §8-19 #6②)** · 메타 · legacy · 트랙 2개(hit · commuteStart) + 후광 원본 PNG | 6,900,000 B (실측 ≈ 6.70MB + 여유, G §8-20 #5) |
| `goldenTestOnly` | 골든 240장 + golden.json — 앱에 싣지 않는다 | 없음 |

`bundles` 는 굽기가 읽지 않는 포장 정책이라 입력 다이제스트(lock.json `inputs`)에서 빠진다(`bake.py` `PACKAGING_KEYS`) — 묶음 · 예산만 바꾸면 다시 굽지 않는다.

## 잠금 (CI `mp-bake`)

- `aing-bake-lock`(ubuntu, 망 봉인): 굽기 입력(`config.json` 의 `inputs`, `.swift` 는 주석을 걷고 해시)과 복사 잠금(`copied`)을
  다시 재서 `lock.json` 과 대조하고, 자산 폴더의 모든 파일 sha256 을 `lock.json.outputs` 와 대조한다. 다르면 빨강 → Windows/Android 출시를 막는다.
- `aing-bake-verify`(macOS, **수동 실행만**): 아래 "설계와 다른 점".

## 설계 F §7 과 다른 점

| F §7 | 지금 | 이유 · 되돌릴 조건 |
|---|---|---|
| `aing-bake-verify` 가 굽기 입력이 바뀐 PR 마다 돈다 | `workflow_dispatch` 수동 실행만 | 러너 최신 Xcode 26.6(Swift 6.3.3)이 이 저장소 시험 타깃을 못 빌드한다(2026-10-21 실측, `#require` 매크로 전개 오류 11곳). Xcode 27 러너나 자체 러너가 생기면 push 로 되돌린다 |
| `bake.sh --check` 로 전부 다시 굽는다 | 늘 구워지는 7칸(`AingBakeSuite.probeCells`, 칸 6 + 패치 1)만 그린다 | 러너 시간 · 빌드 문제. 칸은 솎기와 무관하게 늘 구워지는 것만 고른다(늘 도는 시험 `probeCellsAreInCommittedLock` 이 ⊂ 잠금을 잰다) |
| 다이제스트가 다르면 허용오차(최대 Δ ≤ 2 · IoU ≥ 0.999) 비교 + diff 그림 | 다이제스트 대조만(`bake.py probe-compare`: 같음 · 다름 · 잠금에 없음을 따로 센다) | 허용오차 비교는 F-10 결과(다른 맥에서 실제로 다른가)를 보고 정한다 |
| Metal 이 없으면 건너뛰고 해시 잡이 지킨다 | 같다(F-5: macos-15 · macos-26 러너엔 Metal 이 있다) | — |

- 결론: **F-10(맥 사이 렌더 재현성)은 미검증이다. Windows/Android 출시 게이트는 `aing-bake-lock`(해시 잠금)만 지킨다.**
  다른 맥에서 굽기가 바이트로 같다는 보장은 없다 — 다시 굽는 맥이 바뀌면 `bake.sh --check` 를 먼저 돌려 본다.
