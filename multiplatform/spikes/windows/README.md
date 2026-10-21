# W0-e Windows 탐침 (출시 빌드 아님)

G §2-3 W0-e ①②, §8-3. 자기 완결 Gradle 빌드라 `multiplatform/settings.gradle.kts` 에 넣지 않는다(`SpikeExclusionTest` 가 잰다).
러너 실행은 `.github/workflows/mp-windows-spike.yml`.

| 명령 | 재는 것 |
|---|---|
| `smoke` | JNA `GetLastInputInfo` · `RegisterHotKey`(겹침 1409 짝) · DPAPI 왕복(틀린 엔트로피 거부 짝) · `Shell_NotifyIcon` v4(구조체 976바이트) · 세션(A-X14·D-E24) |
| `selfcheck` | 빌드 시각·SHA·JNA·TLS·리소스, (선택) 읽기·쓰기 탐침, MSIX 패키지 신원 — 창·망 없음 |
| `manifest` | exe 의 RT_MANIFEST 를 순수 Kotlin 으로 읽어 DPI 인식(D-E22) |

맥에서 시험(봉인 아래): `sandbox-exec`(바깥 연결 거부) + `AINGCHECK_NETWORK_SEALED=1` + `gradle --no-daemon --offline test`.
봉인 없이 돌리면 `NetworkCanaryTest` 가 빨갛다 — 정상이다.
