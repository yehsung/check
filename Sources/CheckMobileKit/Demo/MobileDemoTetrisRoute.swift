#if DEBUG
import Foundation

/// 데모 스크린샷 라우트 `games/tetris/…`(1:1 테트리스 · 1.0.11)를 **값으로 푼 것**(DEBUG 전용).
///
/// ── 왜 `Demo/` 안이고 파일 통째가 `#if DEBUG` 인가 ──
/// Release 바이너리에서 **이름이 사라져야** 한다. 출시 게이트 `ios/scripts/check-release-app.sh` 의 금지 문자열
/// `MobileDemo` 가 리플렉션 메타데이터의 타입 이름을 물면 아카이브가 막힌다(1.0.6 build 16 실측 —
/// `MobileDemoMissionsRoute` 머리말에 그 사고가 적혀 있다). 그래서 데모 기계는 전부 이 폴더 안 `#if DEBUG` 이다.
///
/// ── **`#if os(iOS)` 를 더하면 안 된다** ──
/// 플랫폼 분기와 구성 분기는 다른 것이다. 테트리스 화면(`GamesTetrisDuel*`)은 전부 `#if os(iOS)` 안이라 맥 스위트가
/// 한 줄도 못 보므로(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'), 라우트 → 장면 판정은 **플랫폼 분기 없는 값**인 여기
/// 있어야 `swift test` 가 라우트마다 다른 결과를 잴 수 있다. `#if DEBUG` 는 그 그물을 깨지 않는다(테스트는 Debug 다).
///
/// ## 1. 꼬리가 정하는 것 셋 — 장면 폴더 · 열 판 · 로비 탭
///
/// | 라우트                          | 장면 폴더                        | focusMatchID            | 로비 탭 |
/// | ------------------------------- | -------------------------------- | ----------------------- | ------- |
/// | `games/tetris/lobby`            | (없음 — 바깥 층)                  | nil                     | 상대 고르기 |
/// | `games/tetris/lobby/invites`    | `_games-tetris-lobby-invites`    | nil                     | 상대 고르기 |
/// | `games/tetris/ranking`          | (없음 — 바깥 층)                  | nil                     | 순위    |
/// | `games/tetris/match/ready`      | `_games-tetris-match-ready`      | `demo-tetris-ready`     | 상대 고르기 |
/// | `games/tetris/match/countdown`  | `_games-tetris-match-countdown`  | `demo-tetris-countdown` | 상대 고르기 |
/// | `games/tetris/match/playing`    | `_games-tetris-match-playing`    | `demo-tetris-playing`   | 상대 고르기 |
/// | `games/tetris/match/speedup`    | `_games-tetris-match-speedup`    | `demo-tetris-speedup`   | 상대 고르기 |
/// | `games/tetris/match/won`        | `_games-tetris-match-won`        | `demo-tetris-won`       | 상대 고르기 |
/// | `games/tetris/match/lost`       | `_games-tetris-match-lost`       | `demo-tetris-lost`      | 상대 고르기 |
///
/// 판 장면의 로비 탭이 '상대 고르기' 인 것이 맞다: 판이 흐르면 `store.phase != .lobby` 라 로비가 **화면에 없고**,
/// [로비로] 로 돌아온 뒤에 설 자리가 머리다.
///
/// ## 2. 왜 **두 길**로 같은 판을 여는가 (장면 폴더 + focusMatchID)
/// 판 장면의 장면 폴더에는 `rpc.tetris_lobby.json` 변형이 있고 그 `me.active_match_id` 가 그 판을 가리킨다 —
/// 코어가 로비 응답만으로 `refreshMatch` 를 돌려 그 단계를 세운다(`TetrisDuelStore.applyLobby` 끝줄). 즉 **배선이
/// 하나도 없어도** 스틸이 옳다. `focusMatchID` 는 그 위에 겹치는 둘째 길이고(`openWindow(focusMatchID:)`), 체스가
/// 쓰는 길이다. 같은 판 id 라 두 길이 겹쳐도 멱등이다(`refreshMatch` 가 도는 중이면 뒤따르는 한 번으로 합친다).
///
/// 체스는 **한 길**(꼬리)만 썼다. 그 길만 두면 앱 모델 갈래(`MobileAppModel.openDemoRouteIfNeeded`)가 물릴 때까지
/// 여섯 라우트가 전부 같은 로비를 그린다 — 체스에서 그 꼴로 라우트 일곱 중 넷이 **스크린샷 md5 동일**이었다(결함 D6).
/// 그 함수는 배선 레인·통합의 소유라(설계서 §3 레인 A) 이 레인이 손대지 않는다. 그래서 데이터 쪽 길을 먼저 깔았다.
///
/// ## 3. ⚠️ `games/tetris` **한 토막은 이 값이 가로채지 않는다**(설계서 §5 표와 갈리는 유일한 자리)
/// 설계서 §5 는 `games/tetris` 를 로비 머리의 별칭으로 적었지만 그 글자는 **이미 주인이 있다**:
/// `AingRoute.MiniGame.tetris`(v0.3.38) — 혼자 하는 미니게임 테트리스다. 즉 `AingRoute(path: "games/tetris")` 는
/// `.miniGame(.tetris)` 로 **지금도 풀린다**(체스에는 그런 충돌이 없어서 `games/chess` 를 가로챌 수 있었다).
/// 앱 모델은 데모 갈래를 `AingRoute` **앞에** 두므로, 여기서 그 한 토막을 받으면 솔로 테트리스 데모 라우트가
/// 통째로 사라진다 — 설계서 P1 의 "솔로 테트리스와 그 소스 계약은 한 글자도 건드리지 않는다" 를 글자가 아니라
/// **동작으로** 어기는 일이다. 그래서 1:1 테트리스의 로비 머리는 `games/tetris/lobby` 하나다.
/// (`GamesTetrisDemoRouteTests` 가 이 충돌을 못 박는다 — 되돌리면 그 테스트가 빨개진다.)
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck \
///   -AingCheckDemo YES -AingCheckDemoRoute games/tetris/match/speedup
/// ```
package struct MobileDemoTetrisRoute: Hashable, Sendable {

    /// 데모 장면 아홉. `rawValue` 가 **정규 라우트 글자**다 — 장면 폴더 이름은 거기서 `/` 를 `-` 로 바꾼 것이고
    /// (`MobileDemo.environment` 가 같은 식으로 고른다) 그래서 표가 한 벌이다(두 벌이면 갈린다).
    package enum Scene: String, Hashable, Sendable, CaseIterable {
        case lobby = "games/tetris/lobby"
        case lobbyInvites = "games/tetris/lobby/invites"
        case ranking = "games/tetris/ranking"
        case matchReady = "games/tetris/match/ready"
        case matchCountdown = "games/tetris/match/countdown"
        case matchPlaying = "games/tetris/match/playing"
        case matchSpeedup = "games/tetris/match/speedup"
        case matchWon = "games/tetris/match/won"
        case matchLost = "games/tetris/match/lost"

        /// 스텁이 고르는 장면 이름(`_` 를 뺀 폴더 이름). 폴더가 **없는** 장면도 값은 있다 — 그때는 바깥 층이 답한다.
        package var scenario: String { rawValue.replacingOccurrences(of: "/", with: "-") }

        /// 이 장면이 세우는 판(없으면 nil). 판 id 는 장면 이름의 꼬리를 그대로 쓴다(`rpc.tetris_state@<id>.json` 의 바늘).
        package var focusMatchID: String? {
            switch self {
            case .lobby, .lobbyInvites, .ranking:
                return nil
            case .matchReady, .matchCountdown, .matchPlaying, .matchSpeedup, .matchWon, .matchLost:
                return "demo-tetris-" + rawValue.split(separator: "/").map(String.init)[3]
            }
        }

        /// 로비에서 열어 둘 탭. 판 장면은 로비가 화면에 없으므로 머리다(머리말 1).
        package var lobbyTab: LobbyTab { self == .ranking ? .ranking : .opponents }
    }

    /// 로비 안 탭 둘(`TetrisPhoneText.usersTab` · `.rankTab`). 순위는 **별도 화면이 아니라 로비 안 탭**이다 —
    /// 자식 화면을 push 하면 `onDisappear` 로 폴링이 죽는다(오목·체스에서 실증된 자리).
    package enum LobbyTab: String, Hashable, Sendable { case opponents, ranking }

    package var scene: Scene

    package init(scene: Scene) {
        self.scene = scene
    }

    /// 열 판(`TetrisDuelStore.openWindow(focusMatchID:)` 로 가는 값). 로비·순위 장면은 nil.
    package var focusMatchID: String? { scene.focusMatchID }
    /// 로비에서 열어 둘 탭.
    package var lobbyTab: LobbyTab { scene.lobbyTab }
    /// 스텁이 고르는 장면 이름.
    package var scenario: String { scene.scenario }

    /// 게임 탭이 쌓을 경로. 테트리스는 **화면 하나가 단계를 갈아 끼우므로**(설계서 P6) 아홉 장면이 한 값으로 간다 —
    /// 로비·준비·카운트다운·판·결과·순위가 모두 `GamesTetrisDuelScreen` 안이다.
    package var destination: GamesDestination { .tetrisDuel }

    /// 데모 라우트 글자 → 값. 1:1 테트리스 라우트가 아니면 nil.
    ///
    /// - `games/tetris` **한 토막은 nil 이다** — 솔로 미니게임의 글자다(머리말 3).
    /// - `games/tetris/` 아래 모르는 꼬리(`match` 혼자 · `match/<모르는 id>` · 오타)는 **로비 머리로 접는다.**
    ///   조용히 버리면(nil) 앱 모델이 `AingRoute` 로 내려가 거기서도 nil 이라 데모가 기본 탭(지금)에 머문다 —
    ///   "테트리스를 열라고 했는데 지금 탭이 떴다" 는 라우트 오타를 사람이 못 가린다. 머리로 접으면 틀린 꼬리가
    ///   **보인다**(열린 화면은 테트리스 로비이고, 찍힌 스틸이 기대와 다르다).
    ///   모르는 id 를 `focusMatchID` 로 흘리지 않는 까닭도 하나다: 그 id 에는 상태 픽스처가 없어 404(PGRST202)가
    ///   `noteServerMissing()` 을 때리고 화면이 통째로 '서버가 모른다' 로 바뀐다(체스는 꼬리가 곧 판 id 라 달랐다).
    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard path.hasPrefix("games/tetris/") else { return nil }
        self.init(scene: Scene(rawValue: path) ?? .lobby)
    }

    /// 이 데모 라우트가 1:1 테트리스 화면을 띄우라는 뜻인가.
    /// **꼬리까지 푸는 자리는 `init?(demoRoute:)` 다** — 이 되묻기는 그 값이 섰는가만 본다(두 판정이 갈리지 않게).
    package static func isTetrisDuelRoute(_ raw: String) -> Bool {
        MobileDemoTetrisRoute(demoRoute: raw) != nil
    }
}
#endif
