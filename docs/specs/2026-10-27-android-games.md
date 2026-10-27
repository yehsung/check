# Android 게임 클라이언트 0.1

기존 macOS·iOS 계정으로 두 미니게임을 즐기고 같은 일일 순위표에 참여한다.
첫 범위는 타이밍 바·플래피 아잉, 비로그인 연습, 로그인·세션 갱신·로그아웃, 순위 조회·점수 제출이다.
테트리스·보드게임 대전·근무 타이머·푸시는 후속 범위다.

## 계약과 수용 기준

- 원본: `Sources/CheckCore/TimingBarGame.swift`, `FlappyGame.swift`, `MiniGameEngine.swift`.
  논리 좌표 292×302, 난수 SplitMix64, 점수·속도·충돌·라운드 전이를 Kotlin으로 옮긴다.
- API: `SupabaseWorkService.swift:764-860`, `SupabaseWorkModels.swift:2955-3028`.
  순위 모드는 게임 시작 전 `minigame_start_round` 토큰을 받아야 한다. 자연 종료한 판만 동일 토큰으로 한 번 제출한다.
  시간 하한을 우회하거나 서버 테이블에 직접 점수를 쓰지 않는다.
- `profiles.minigame_public=false`이면 토큰 발급·점수 제출을 하지 않는다.
  공개 여부 조회 실패도 순위 시작 실패로 처리한다. 연습은 항상 가능하다.
- 앱이 배경으로 가거나 뒤로 나가면 진행 중 판과 발급 대기 응답을 버린다.
  완료된 판의 제출 응답은 해당 계정·판 세대에서만 화면에 반영한다.
- refresh token은 Android Keystore AES-GCM으로 암호화한다. 비밀번호·access token은 디스크에 보관하지 않는다.
  백업·평문 HTTP는 비활성화한다. 공개용 anon/publishable key만 사용한다.
- 게임 엔진은 Android SDK 없는 JVM에서 테스트 가능해야 한다. Swift 실행 결과와 고정 시드 궤적을 대조한다.
- API 테스트는 모의 서버만 사용한다. 운영 서버에 테스트 점수·계정을 생성하지 않는다.
- APK 빌드·단위 테스트·lint 통과 후 PR에 검증 결과와 아직 확인하지 못한 실기기 연동을 명시한다.

## 설계 검토

공용 Swift 코어를 Android에서 직접 링크하면 SwiftUI·Apple 모듈 결합을 먼저 분리해야 한다.
첫 단계는 순수 Kotlin 엔진 두 개와 독립 `android/` 프로젝트로 제한한다.
서버 토큰은 게임별 새 판 시작 시 기존 토큰을 바꿀 수 있으므로 시작 요청을 직렬화하고 늦은 응답은 세대로 무효화한다.
점수 전송 중에는 새 순위 판을 열지 않는다. 통신 실패는 기록 반영 여부가 불명확함을 표시하고 자동으로 새 토큰을 만들지 않는다.
