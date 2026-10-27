# W0-f ③ ART 대조 측정기(스냅숏 원문 — 빌드에 들지 않는다)

`contract/README.md` §6-1 의 수치를 낸 측정기다. 2026-10-28 에 한 번 쟀고 게이트는 다시 재지 않는다.
이 폴더의 파일은 어느 Gradle 소스 세트에도 들지 않는다 — 다시 잴 때만 저장소 **사본**(APFS 사본 등)에 넣어 돌린다.

| 파일 | 넣을 자리(사본 안) | 하는 일 |
|---|---|---|
| `W0fProbeCore.kt` | `multiplatform/androidApp/src/androidTest/kotlin/com/yehsung/aingcheck/w0fprobe/` **와** `multiplatform/testkit/src/desktopTest/kotlin/com/yehsung/aingcheck/w0fprobe/`(같은 바이트 두 벌) | W0-b 표를 읽어 pow·중력·글자 범주·그래핌·NFC·KST 를 재고 결과 JSON 을 낸다. `problems()` 가 측정기·표의 온전함을 판정한다 |
| `W0fArtProbeDeviceTest.kt` | androidTest 쪽 같은 폴더 | ART(기기)에서 `java.*` 와 `android.icu.*` 를 둘 다 잰다. 덤프를 쓴 **뒤** 단언한다 |
| `W0fJvmProbeDumpTest.kt` | desktopTest 쪽 같은 폴더 | 같은 측정기를 데스크톱 JVM 에서 돌린다(대조 기준). 덤프를 쓴 뒤 단언한다 |
| `compare.py` | 아무 데나 | Swift 표 · JVM 덤프 · ART 덤프를 칸별로 대조해 요약 JSON(§6-1 표의 수치)을 낸다 |
| `canon.py` | 아무 데나 | 덤프의 정규 지문(시간 칸·단언 칸을 빼고 키를 정렬한 JSON 의 sha256) |

계측 APK 의 assets 로는 `multiplatform/testkit/src/desktopTest/resources/golden/w0b-probe/{pow3,gravity,text-scalars,graphemes,nfc,kst}.json`
여섯 개를 `multiplatform/androidApp/src/androidTest/assets/w0b-probe/` 에 그대로 복사한다.

## 단언(‘OK (1 test)’ 가 뜻하는 것)

`OK` = 덤프를 썼고 **측정기·표가 온전하다**: 읽은 표 바이트의 sha256 이 W0-b 골든과 같다 · 칸마다 예외가 없다 · pow 표 지문(x·ref·pow) 실패 0 ·
중력 바탕 비트 일치 · 범위 표가 0..10FFFF 를 잇는다 · 표 크기(1,000,000 · 20 · 20 · 300 · 300 · 1,375) · 분할기·정규화기 예외 0.
런타임 차이 수치(Swift 와 다른 줄 수 등)는 측정값이라 단언하지 않는다 — 덤프와 `compare.py` 로 읽는다.
결함 심기: pow3 chunk-00 의 xDigest 와 graphemes g-000 의 cps 를 바꾼 표로 JVM·ART 26·ART 36 모두 빨강(문제 2~3건)을 확인했다.

## 다시 재는 법

```sh
# 사본의 multiplatform 에서(봉인 · 오프라인 · 데몬 없음)
/usr/bin/sandbox-exec -f scripts/seal.sb /usr/bin/env AINGCHECK_NETWORK_SEALED=1 ./gradlew --offline --no-daemon \
  :testkit:desktopTest --tests com.yehsung.aingcheck.w0fprobe.W0fJvmProbeDumpTest \
  :androidApp:assembleDebug :androidApp:assembleDebugAndroidTest          # JVM 덤프 → testkit/build/w0f/jvm.json

# 기기(갈래 포트 · 봉인 · 읽기 전용) — API 26 은 aingcheck-api26, API 36 은 aingcheck-api36(또는 aingcheck-api36-ko)
scripts/emu.sh start --avd aingcheck-api26 --port <포트>
adb -s emulator-<포트> install -r -t androidApp/build/outputs/apk/debug/androidApp-debug.apk
adb -s emulator-<포트> install -r -t androidApp/build/outputs/apk/androidTest/debug/androidApp-debug-androidTest.apk
adb -s emulator-<포트> shell am instrument -w -r -e class com.yehsung.aingcheck.w0fprobe.W0fArtProbeDeviceTest \
  com.yehsung.aingcheck.test/androidx.test.runner.AndroidJUnitRunner       # 'OK (1 test)'
adb -s emulator-<포트> exec-out run-as com.yehsung.aingcheck cat files/w0f-art.json > art-26.json
scripts/emu.sh stop --port <포트>

python3 -I canon.py jvm.json art-26.json art-36.json                      # §6-1 의 정규 sha256 과 맞춰 본다
python3 -I compare.py <w0b-probe 폴더> jvm.json api26=art-26.json api36=art-36.json > summary.json
```

같은 시스템 이미지(§6-1 의 Pkg.Revision)면 정규 sha256 이 같아야 한다. 다르면 이미지·JDK·표 가운데 무엇이 바뀌었는지부터 본다.
