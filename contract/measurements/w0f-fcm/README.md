<!-- 원본: 없음 (W0-f ⑤ FCM 토큰 실측 기록 — Swift 짝 없음) -->
# W0-f ⑤ FCM 토큰 실측(스냅숏 원문 — 빌드에 들지 않는다)

`contract/README.md` §6-2 의 수치를 낸 측정기다. 2026-10-28 에 쟀고 게이트는 다시 재지 않는다(바깥망·실제 제공자가 필요하다 — G §8-8).
**개발 Firebase 프로젝트 `aingcheck-dev` 에서만** 잰다. 운영 프로젝트 설정으로는 빌드되지 않는다(`app.build.gradle.kts` 가 project_id 를 확인한다).
이 폴더의 파일은 어느 Gradle 소스 세트에도 들지 않는다 — 다시 잴 때만 저장소 **밖** 스크래치에 탐침 프로젝트를 꾸려 돌린다.

## 지킨 것

- **토큰 원문은 기기 밖으로 나오지 않는다.** 탐침(`FcmProbe`, 앱 프로세스 안의 Instrumentation)이 기기 메모리에서 길이·글자 집합·서버 꼴 일치만 계산해
  `am instrument` 결과로 낸다. 서로 다름은 운전 스크립트가 실행마다 새로 만든 소금을 붙인 SHA-256 앞 16자(`h`)로 그 프로세스 메모리에서만 센다(출력·파일에 안 적는다).
- logcat 은 파일로 받지 않는다. 메모리에서 "토큰 꼴" 줄의 태그 수와, 그 줄에 이번 토큰(같은 `h`)이 있는지만 센다.
- Google 계정 로그인 없음 — `dumpsys account` 의 `Accounts: 0` 을 실행 앞뒤로, 앱이 본 `com.google` 계정 수 0 을 회차마다 단언한다.
- 에뮬레이터는 `emu.sh start --no-seal`(바깥망 필요 — 봉인 게이트와 따로) · `-read-only`(끄면 손님 /data, 곧 토큰을 든 앱·GMS 자료가 버려진다) · 창 없음.
- Firebase 는 앱 설계(A§6-1 · E§6.6)와 같은 길: google-services 플러그인 없이 `FirebaseOptions` 를 손으로 초기화, `firebase_messaging_auto_init_enabled=false`.
  Firebase BoM 35.0.2(firebase-messaging 26.0.0 · firebase-installations 20.0.0 · play-services-cloud-messaging 17.4.0) — 앱(`androidApp`)과 같은 판.

## 결과(2026-10-28)

| 판 | 이미지 | GMS | 받은 토큰 | 길이 | 모양 | 글자 |
|---|---|---|---|---|---|---|
| API 35 · Android 15 `AE3A.240806.036` | `system-images/android-35/google_apis_playstore/arm64-v8a` Pkg.Revision 9 | 24.23.35 | 20 | 전부 **142** | `<FID 22자>:APA91b<113자>` — 콜론 1개(22번째 자리), 앞 22자 = Firebase Installations ID, 뒤 119자는 `APA91b` 로 시작 | `[A-Za-z0-9_:-]` 만(가장 작은 글자 `-` 0x2D, 가장 큰 `z` 0x7A). 대·소문자는 모든 토큰에 섞임(소문자로 바꾸면 다른 글자열), 숫자는 칸을 기록한 45개 모두에 있음 |
| API 36 · Android 16 `BE2A.250530.026.D1` | `system-images/android-36/google_apis_playstore/arm64-v8a` Pkg.Revision 7(공용 `aingcheck-api36`) | 25.08.34 → 같은 부팅 안에서 **저절로 26.41.31** 로 올라감(계정 없이) | 35 | 전부 **142** | 같음 | 같음 |

- 받은 토큰 55개 = 판정 실행 세 번(API 36 두 번 — GMS 25.08.34 · 26.41.31, API 35 한 번 · 각 10개 · 모두 `VERDICT ok`) + 그 앞 측정 실행 21개(같은 탐침, 판정 줄을 넣기 전) + 결함 심기 실행 4개(아래). 55개 모두 위 모양이다.
- **계정 로그인 없이 Play 이미지에서 토큰이 나온다**(E-U6 · B§9-1 둘째 물음): 첫 `getToken` 2.6~9.7초(새 FID 0.04~0.7초).
- 재설치·`pm clear` 마다 새 FID·새 토큰(판정 실행마다 10/10 서로 다름). 같은 설치에서 `getToken` 두 번은 같은 값, 지우지 않고 다시 실행해도 같은 값(결함 심기 D2 가 보인 1/2).
- logcat 에 이번 토큰이 든 줄 0. Play 스토어(`Finsky`)가 자기 것인 토큰 꼴 문자열을 정보 로그에 0~5줄 남긴다(우리 토큰 아님).
- 설정 자원이 없으니 `FirebaseInitProvider` 는 기본 앱을 만들지 않았고(`defaultAppBeforeInit=false`), 손 초기화 + 자동 초기화 끔에서도 `getToken` 이 바로 된다(E§6.6 길 성립).

### 서버 판정(B§9-1 첫째 물음 — 바꿀 것 없음)

| 서버 자리(M1 = 서버 ① `20261101100000_client_platforms_android_windows.sql` · M4 = 서버 ③ 초안 · push-send `fcm.ts`) | 꼴 | 55개 실측 |
|---|---|---|
| M1 `client_devices_fcm_token_format` | `fcm_token ~ '^[!-~]+$' and char_length(fcm_token) between 32 and 4096`(Postgres 반복 상한 255 때문에 `{32,4096}` 대신 이 꼴) | 모두 통과 — 142자, 0x2D..0x7A 는 `[!-~]`(0x21..0x7E) 안 |
| M1 `register_device_fcm` | `btrim(p_fcm_token, E' \t\r\n')` 뒤 같은 꼴 | `btrim` 이 걷는 글자 0 → 그대로 통과 |
| push-send `buildFcmMessage` | `/^[!-~]{32,4096}$/` | 모두 통과 |
| M4 `push_outbox_complete` FCM 비우기 | `btrim` 만, `lower(` 없음(대소문자 보존) | 모든 토큰이 소문자로 바꾸면 다른 글자열이 된다 → **`lower()` 금지가 맞다**(APNs 쪽 `lower(btrim())` 를 FCM 에 옮기면 안 된다) |
| M1 부분 unique `client_devices_fcm_token_key` | 토큰 하나 = 행 하나 | 설치·데이터 지우기마다 새 토큰이라 겹침은 "같은 설치를 다른 계정이 쓴 경우"뿐(토큰 이동 절이 다룬다) |

결론: **서버 CHECK·RPC 검사·push-send 정규식은 그대로 맞다.** 길이 142 는 하한 32·상한 4096 안에 넉넉하다. Firebase 는 토큰 길이·모양을 문서로 약속하지 않으므로
CHECK 를 실측 모양(142자 · `:APA91b`)으로 좁히지 않는다 — 넓은 지금 꼴이 옳다.

### 채널 없는 알림(B§9-4)

| 길 | 실험 | API 35 | API 36 |
|---|---|---|---|
| 앱이 직접 게시(data-only, K7) — 채널을 만든 뒤 | `probe_baseline` 채널 만들고 id 101 | 보임 | 보임 |
| 앱이 직접 게시 — **아직 안 만든 채널** `message` | id 102 | **안 보임** — 시스템이 조용히 버린다(`E/NotificationService: No Channel found for pkg=…, channelId=message`), 채널도 저절로 안 생긴다 | 같음 |
| 같은 채널을 만든 뒤 다시 | id 103 | 보임(②의 차이가 채널 부재 탓임을 가르는 대조) | 보임 |
| SDK notification 메시지가 없는 `android_channel_id` 를 가리킴 | `FcmBroadcastProcessor.process`(GMS 가 넘긴 뒤와 같은 처리기)에 합성 RECEIVE 인텐트 | `fcm_fallback_notification_channel`("Miscellaneous", 중요도 3)로 보임, 요청한 채널은 안 생김 | 같음 |

설계에 주는 것: data-only(K7)에서는 **게시 전에 채널이 있어야 한다.** FCM 이 프로세스를 깨워 Activity 없이 `onMessageReceived` 가 먼저 돌 수 있으므로
채널 다섯(E§6.5)은 `Application.onCreate` 또는 게시 직전 멱등 생성으로 만든다. 없으면 오류 없이 알림이 사라진다.
`notification` 메시지(쓰지 않는 길)였다면 SDK 가 'Miscellaneous' 채널로 대신 보였을 것이다.

### 재지 않은 것

- 실제 FCM 발송 왕복(data high 도착 · Doze · 강제 중지 · 배달 시간) — 개발 프로젝트 서비스 계정 키가 없다(운영 키는 쓰지 않는다 — §8-8). 개발 키를 받거나 서버 ② 뒤에.
- 실기기 · API 26~34 · 계정에 로그인한 기기. 토큰 모양은 FCM 서버가 정하므로 기기 판에 따라 달라질 까닭은 작다(판단).
- SDK notification 길은 GMS 가 실제로 넘긴 인텐트가 아니라 같은 처리기에 넣은 합성 인텐트다.

## 판정(`VERDICT`)과 결함 심기

`fcm_rounds.py` 는 끝에 `VERDICT ok` 또는 `VERDICT fail [까닭…]` 을 찍고 종료 코드 0/1 로 끝난다. `ok` 의 뜻:
회차 수 = 요청 · 회차마다 탐침 성공 · `jsForm`·`pgForm`·`btrimNoop`·`stableWithinInstall`·`headEqualsFid` 참 · 글자 0x21..0x7E · 앱이 본 Google 계정 0 ·
토큰 수 = 서로 다른 토큰 수 = 회차 수 · logcat 에 이번 토큰 든 줄 0 · 기기 계정 수(앞뒤) 0 ·
채널 실험 = 위 표(기준선 보임 · 없는 채널 안 보임·안 생김 · 만든 뒤 보임 · SDK 는 대체 채널 · 요청 채널 안 생김).

| 결함(사본에 심음) | 결과 |
|---|---|
| D1 탐침의 JS 꼴 하한을 150 으로 | `1: jsForm=false` · `2: jsForm=false` → fail, 종료 1 |
| D3 탐침이 게시 전에 `message` 채널을 먼저 만듦 | `notify: missingPosted=true` · `messageChannelCreatedImplicitly=true` → fail(D1 과 같은 실행) |
| D2 운전 스크립트가 `pm clear` 를 건너뜀 | `서로 다른 토큰 1/2/2` → fail, 종료 1 |
| D4 logcat 훑기를 "줄 통째 비교"로 | `--self-test` 가 `이번 토큰이 든 줄 0 (기대 1)` → fail, 종료 1 |

`python3 -I fcm_rounds.py --self-test` 는 기기 없이(합성 토큰 꼴 문자열로) logcat 훑기를 잰다.

## 파일

| 파일 | 넣을 자리(스크래치 탐침 프로젝트 안) | 하는 일 |
|---|---|---|
| `settings.gradle.kts` · `root.build.gradle.kts`(→ `build.gradle.kts`) · `probe.gradle.properties`(→ `gradle.properties`) | 프로젝트 뿌리 | AGP 9.3.1 · KGP 2.4.21(저장소와 같은 판) |
| `app.build.gradle.kts`(→ `app/build.gradle.kts`) | `app/` | 앱 id `com.yehsung.aingcheck` · compileSdk 37 · minSdk 26 · targetSdk 36. 개발 프로젝트 클라 설정 JSON 을 `-Pw0f5.firebaseConfig=<경로>` 로 읽어 BuildConfig 에 넣는다(project_id 가 `aingcheck-dev` 가 아니면 멈춘다). 앱과 같은 의존 판으로 맞춘 줄들이 있어 `--offline` 으로 빌드된다 |
| `AndroidManifest.xml` | `app/src/main/` | 자동 초기화 끔 · 자기 자신을 겨누는 `<instrumentation>` |
| `FcmProbe.java` | `app/src/main/java/com/yehsung/aingcheck/w0f5/` | `mode=token`: 손 초기화 → FID → `getToken` 두 번 → 길이·글자·서버 세 꼴·구조. `mode=notify`: 위 채널 실험 |
| `fcm_rounds.py` | 아무 데나 | 회차(홀수 재설치 · 짝수 `pm clear`) → logcat 훑기 → 채널 실험 → 판정 |

## 다시 재는 법

```sh
S=<갈래 스크래치>; R=<저장소 사본>; M=$R/contract/measurements/w0f-fcm
mkdir -p $S/probe/app/src/main/java/com/yehsung/aingcheck/w0f5 $S/probe/gradle/wrapper
cp $M/settings.gradle.kts $S/probe/; cp $M/root.build.gradle.kts $S/probe/build.gradle.kts; cp $M/probe.gradle.properties $S/probe/gradle.properties
cp $M/app.build.gradle.kts $S/probe/app/build.gradle.kts; cp $M/AndroidManifest.xml $S/probe/app/src/main/
cp $M/FcmProbe.java $S/probe/app/src/main/java/com/yehsung/aingcheck/w0f5/
cp $R/multiplatform/gradlew $S/probe/; cp $R/multiplatform/gradle/wrapper/gradle-wrapper.{jar,properties} $S/probe/gradle/wrapper/
echo "sdk.dir=$HOME/Library/Android/sdk" > $S/probe/local.properties
(cd $S/probe && ./gradlew --no-daemon --offline -Pw0f5.firebaseConfig=<개발 프로젝트 클라 설정 JSON> :app:assembleDebug)

# 기기: 봉인 없음 · 읽기 전용 · 갈래 포트. API 35 Play 는 공용 AVD 가 없어 스크래치 AVD(ANDROID_AVD_HOME) — emu.sh 머리말 '바깥망 실험'
EMU_STATE_DIR=$S/emu-state $R/multiplatform/scripts/emu.sh start --avd aingcheck-api36 --port <포트> --no-seal
python3 -I $M/fcm_rounds.py ~/Library/Android/sdk/platform-tools/adb emulator-<포트> \
  $S/probe/app/build/outputs/apk/debug/app-debug.apk 10            # 마지막 줄 'VERDICT ok', 종료 코드 0
EMU_STATE_DIR=$S/emu-state $R/multiplatform/scripts/emu.sh stop --port <포트>
rm -rf $S/probe/app/build $S/probe/.gradle                          # 설정 값이 든 BuildConfig·APK 를 지운다
```

같은 이미지·GMS 판이면 위 표와 같은 모양(142자 · 22자 FID · `APA91b`)이 나와야 한다. 다르면 GMS·firebase-messaging 판부터 본다 —
모양이 바뀌어도 서버 꼴(`[!-~]`, 32..4096)에 들면 문제없고, 벗어나면 서버 CHECK 와 push-send 정규식을 함께 다시 정한다.
