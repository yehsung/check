# 이슬 아잉이 대체 그림 — 폰 1.0.17 심사 5.2.1 반려 대비 (저장소 안 사본)

대표 결정(2026-11-03 #d_dk4IjWRZvFYR 원문): **"그대로 + 대체 그림 미리 준비"**(맥과 같은 그림. 5.2.1로 반려되면 되묻지 않고
대체 그림으로 바꿔 그날 다시 제출(지연 1~2일)).

→ 1.0.17 은 맥과 같은 그림(라벨 큰 글자 = 실제 소주 상표)으로 낸다. **App Review 가 지침 5.2.1(지식재산 · 상표)로 반려하면 되묻지 않고**
아래 순서로 폰 사본만 바꿔 같은 날 다시 낸다. 맥 그림(`Sources/check/Resources/aing_isul-*.png`)은 **바꾸지 않는다**.

이 폴더는 처음에 저장소 밖 작업 폴더(`phone-1017/isul-alt/`)에만 있었다. 작업 폴더는 정리 때 통째로 지워진 이력이 있어(10-30 · 11-02)
반려 당일 다시 구워야 하는 일을 막으려고 **저장소 안(이 폴더, GitHub Pages 제외 `docs/plan`)** 으로 옮겼다(1.0.17 검토 지적).
`Tests/CheckMobileKitTests/IsulAltKitTests.swift` 가 이 폴더의 파일 · 모양 · 패치가 지금 저장소와 맞는지 늘 잰다.

## 무엇이 들어 있나

| 파일 | 뜻 |
| --- | --- |
| `aing_isul-neutral.png` · `aing_isul-negative.png` | 대체 초상 두 장(192², RGBA). 시안 R 모양 그대로, 라벨 큰 글자만 **'참아잉'**. 맥 그림과 **알파(모양)는 0px 다르고** 라벨 부분 색만 다르다 |
| `card-aing_isul.heic` (+ `.base64.txt`) | 나 탭 카드 그림(146×150, HEIC q0.8, 알파 있음) — 대체 초상 neutral 로 `MeCharacterCardTests` 규칙 그대로 구웠다 |
| `MeCharacterCardData-alt.patch` | 카드 표에서 **이슬 한 줄(heicBase64)만** 바꾸는 패치 |
| `BaseComponentTests-alt.patch` | 폰 초상 = 맥 원본 픽셀 대조에서 이슬만 "알파 같음 + 색 다름(대체 그림이 들어왔다)" 으로 바꾸는 패치 |
| `swap-card.py` | 카드 패치가 안 먹을 때(그사이 카드가 다시 구워짐) 이슬 base64 한 줄만 바꾸는 예비 스크립트 |

만든 방법(재현): 저장소 루트에서 `swift -O scripts/make-isul-aing.swift --label 참아잉 --out <저장소 밖 폴더>`(커밋 `bbe62e30` 의 `--label`).
macOS 내려받기 글꼴 'Nanum Brush Script' 가 있어야 같은 글씨가 나온다. 인자 없이 돌리면 맥 산출물 셋과 바이트까지 같다. `--label` 은 `--out` 없이 쓰면 멈춘다(맥 그림 보호).
패치를 만든 기준: ios-1017-int `bbe62e30` — `9e0e0fa8` 위에서도 `git apply --check` 깨끗(2026-11-04).
맥 3D 라벨 텍스처의 대체판(`label.png`)은 폰이 안 써서 여기 두지 않았다(맥 Storage 에 올리는 일은 대표 결정이 따로 있을 때만 — 결정 카드의 C안).

## 바꿔 끼우기 (반려 당일 — 정확한 명령)

출시 가지(1.0.17 을 낸 커밋 위)의 작업 복사본에서, 저장소 루트를 현재 폴더로 두고:

```sh
A=docs/plan/isul-alt
cp "$A/aing_isul-neutral.png"  Sources/CheckMobileShared/Resources/Portraits/aing_isul-neutral.png
cp "$A/aing_isul-negative.png" Sources/CheckMobileShared/Resources/Portraits/aing_isul-negative.png
git apply "$A/MeCharacterCardData-alt.patch"
git apply "$A/BaseComponentTests-alt.patch"
cmp "$A/aing_isul-neutral.png"  Sources/CheckMobileShared/Resources/Portraits/aing_isul-neutral.png
cmp "$A/aing_isul-negative.png" Sources/CheckMobileShared/Resources/Portraits/aing_isul-negative.png
git status --short     # 정확히 네 파일만 M 이어야 한다(위 둘 + MeCharacterCardData.swift + BaseComponentTests.swift)
```

카드 패치가 안 먹으면(`git apply` 실패 — 그사이 카드가 다시 구워졌다) 대신:

```sh
python3 -I "$A/swap-card.py" Sources/CheckMobileKit/Me/MeCharacterCardData.swift "$A/card-aing_isul.heic.base64.txt"
```

시험 패치가 안 먹으면 `Tests/CheckMobileKitTests/BaseComponentTests.swift` 의 `portraitsAreBundledCopiesOfMacArt` 에서
`#expect(try Self.pixels(url) == Self.pixels(mac), …)` 한 줄을 `BaseComponentTests-alt.patch` 안의 `if id == CharacterCatalog.isulAingID { … } else { … }`
모양으로 손으로 옮긴다(이슬만 알파 같음 + 색 다름, 나머지는 그대로).

★ **바꿔 끼운 판에서 카드를 다시 구워도 된다**(`AING_REGENERATE_CHARACTER_CARDS=1`). 1.0.17 검토 수리부터 내장 캐릭터 카드는 **폰 초상**에서 굽는다
(`MeCharacterCardTests.builtInPortraitURL`) — 그 전에는 맥 그림에서 구워 상표 그림이 카드로 돌아왔다. 다시 구운 뒤에도
`IsulAltKitTests` 가 "카드 = 대체 카드"를 잰다(같은 인코더라 바이트까지 같아야 한다).

## 그때 고칠 시험 · 확인 (2026-11-03 실제로 바꿔 끼워 돌려 봄)

- **고칠 시험은 하나다**: `BaseComponentTests.portraitsAreBundledCopiesOfMacArt`(폰 초상 = 맥 원본 픽셀 대조) — 위 패치. 패치 없이 바꿔 끼우면
  정확히 2건(neutral · negative) 빨강, 나머지는 초록.
- `IsulAltKitTests` 는 두 상태를 다 안다: 바꿔 끼우기 **전**에는 "패치가 지금 파일에 붙는다(빼는 줄이 그대로 있다) · 대체 그림 모양 = 폰 초상 모양",
  **뒤**에는 "초상 둘 · 카드 한 줄 · 시험 패치가 모두 들어왔다"(하나라도 빠지면 빨강 — 반쪽 교체를 막는다).
- 바꿔 끼운 상태 + 두 패치로 폰 시험 **전체 초록**(2026-11-03 1,823건). 그대로인 것들:
  카드 드리프트(`MeCharacterCardTests` — 조인 상자 146×150 · 출력 크기 같다, 알파가 같으므로) · 아바타 틀(`MeIsulGiftTests` — 몸 자리 18.0px) · 번호 5(`MeIsulProtocolPinTests`).
- 폰 시험(저장소 루트):
  `swift build --build-tests && caffeinate -di sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip "*:*"))' swift test --disable-sandbox --skip-build --no-parallel --filter CheckMobileKitTests`
- 그림만 바뀌어 코드는 그대로지만 번들이 바뀌므로 `ios/scripts/build-sim.sh <DerivedData> Debug` 한 번 → 빌드 번호 올려 아카이브 · 제출.
- 위젯도 같은 번들 초상을 읽으므로 따로 할 일이 없다.

## 다시 제출할 때

- 심사 답장(Resolution Center, 영어): 캐릭터 그림의 라벨에서 제3자 상표 글자를 빼고 지어낸 글자로 바꿨다고 쓴다.
  예: "We replaced the third-party brand text on the character artwork's label with an original made-up label. No other changes."
- 스토어 글 · 새 기능 · 심사 메모 · 스크린샷 글 · **스크린샷 이미지**에는 원래부터 상표를 쓰지 않는다(대표 결정 — 이슬 칸이 서는 `me/shop` 장면은 1.0.17 스크린샷에 쓰지 않는다, `docs/appstore.md` §6.2).
- 서버 · Storage 는 건드리지 않는다. 폰 1.0.17 은 이슬 그림을 **번들에서만** 읽는다(Storage 받기 없음) — 그래서 바꾸려면 새 빌드가 필요하다.
- 맥(0.3.74 이후)은 이 일과 무관하다 — 맥 그림을 바꿀지는 별도 대표 결정(맥은 `IsulArt` Storage 로 앱 업데이트 없이 바꿀 수 있다).
- ⚠️ 남는 위험(검토 지적, 확인 못 함): '참아잉'은 큰 글자만 바꿨고 붓글씨체 · 라벨 왼쪽 파란 물방울 표식 · 초록 병 몸은 그대로다. 재심사에서
  '혼동될 만큼 비슷한 겉모양'으로 다시 반려될 수 있다 — 그러면 하루가 더 늦어진다. 더 먼 안(첫 글자 · 표식까지 바꾼 그림)을 미리 구울지는 대표 판단이다.

## 되돌리기

바꿔 끼운 작업 복사본을 원래대로:

```sh
git checkout -- Sources/CheckMobileShared/Resources/Portraits/aing_isul-neutral.png \
  Sources/CheckMobileShared/Resources/Portraits/aing_isul-negative.png \
  Sources/CheckMobileKit/Me/MeCharacterCardData.swift Tests/CheckMobileKitTests/BaseComponentTests.swift
```
