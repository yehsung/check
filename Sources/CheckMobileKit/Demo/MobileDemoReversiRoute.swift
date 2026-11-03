#if DEBUG
import CheckCore
import Foundation

/// 데모 스크린샷 라우트 `games/reversi/…`(아잉 뒤집기 · 폰 1.0.17)를 **값으로 푼 것**(DEBUG 전용).
/// 왜 `Demo/` 안이고 파일 통째가 `#if DEBUG` 인가 · 왜 `#if os(iOS)` 를 더하면 안 되는가는 `MobileDemoTetrisRoute` 머리말과 같다
/// (출시 게이트의 금지 문자열 `MobileDemo` · 맥 스위트가 이 값을 재야 라우트마다 다른 장면이 서는지 안다).
///
/// | 라우트                          | 장면 폴더                         | 열 판(…e?)   | 관전(…e?) | 그 밖                          |
/// | ------------------------------- | --------------------------------- | ------------ | --------- | ------------------------------ |
/// | `games/reversi/lobby`           | (없음 — 바깥 층)                   | nil          | nil       | 로비 머리                      |
/// | `games/reversi/lobby/invites`   | `_games-reversi-lobby-invites`    | nil          | nil       | 받은 신청 둘 · 보낸 신청 하나  |
/// | `games/reversi/ranking`         | (없음 — 바깥 층)                   | nil          | nil       | 로비 맨 아래(순위)부터         |
/// | `games/reversi/rules`           | (없음 — 바깥 층)                   | nil          | nil       | 규칙 시트를 연다               |
/// | `games/reversi/match/playing`   | `_games-reversi-match-playing`    | e1           | nil       | 진행 중 · 내 차례(흑)          |
/// | `games/reversi/match/warned`    | `_games-reversi-match-warned`     | e2           | nil       | 자동 착수 두 번 뒤 내 차례(백) |
/// | `games/reversi/match/won`       | `_games-reversi-match-won`        | e3           | nil       | 끝남 · 이김(판 가득)           |
/// | `games/reversi/match/draw`      | `_games-reversi-match-draw`       | e4           | nil       | 끝남 · 32:32 무승부(환불)      |
/// | `games/reversi/match/lost`      | `_games-reversi-match-lost`       | e5           | nil       | 끝남 · 자동 착수 세 번 → 짐    |
/// | `games/reversi/watch`           | (없음 — 바깥 층)                   | nil          | e6        | 남의 판 관전(진행 중)          |
/// | `games/reversi/watch/over`      | (없음 — 바깥 층)                   | nil          | e7        | 남의 판 관전(끝남 · 기권)      |
/// | `games/reversi/ai`              | (없음 — 바깥 층)                   | nil          | nil       | 로봇 연습(나 = 흑)             |
/// | `games/reversi/ai/white`        | (없음 — 바깥 층)                   | nil          | nil       | 로봇 연습(나 = 백 · 로봇이 먼저) |
/// | `games/reversi/ai/invite`       | `_games-reversi-ai-invite`        | nil          | nil       | 로봇 연습 + 판 위 받은 신청 띠 |
///
/// 판 id 는 실서버처럼 **uuid** 다(`d0000000-0000-4000-8000-0000000000e1` …). 상태 픽스처의 바늘이 곧 그 id 다(`rpc.reversi_state@<id>.json`).
///
/// ## 판 장면이 판을 여는 두 길
/// 진행 중 장면(playing · warned)은 테트리스·큐브처럼 **두 길**로 같은 판을 연다: 장면 폴더 로비의 `me.active_match_id`(코어만으로 선다) +
/// `focusMatchID`(`openWindow(focusMatchID:)`). 같은 id 라 겹쳐도 멱등이다. **끝난 판**(won · draw · lost)은 서버가 active 로 가리키지 않으므로
/// `focusMatchID` 한 길이다 — 장면 폴더 로비는 정산 **뒤** 서버 사실(잔액 · 전적)을 싣는 몫이다.
///
/// ## 관전 · 로봇 연습 · 규칙은 픽스처가 아니라 라우트가 건다
/// 데모에는 합성 탭이 없다(작업 규칙 — 손가락 없는 스크린샷). 그래서 [관전] 칩 · [로봇과 연습하기] · 책 버튼을 누른 것과 **같은 코어 문**을 라우트가 부른다:
/// 관전은 `startWatching(matchID:)`(배선 `GamesStore.startDemoReversiWatchIfNeeded` — 로비가 온 뒤), 로봇 연습은 `startAIMatch(humanColor:)`,
/// 규칙은 `isRulesVisible`. 코어 게이트(주 스위치 · 세션 · `canStartAIMatch` …)는 하나도 우회하지 않는다.
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute games/reversi/match/playing
/// ```
package struct MobileDemoReversiRoute: Hashable, Sendable {
    /// 데모 장면 열넷. `rawValue` 가 **정규 라우트 글자**다 — 장면 폴더 이름은 거기서 `/` 를 `-` 로 바꾼 것이다(`MobileDemo.environment` 와 같은 식).
    package enum Scene: String, Hashable, Sendable, CaseIterable {
        case lobby = "games/reversi/lobby"
        case lobbyInvites = "games/reversi/lobby/invites"
        case ranking = "games/reversi/ranking"
        case rules = "games/reversi/rules"
        case matchPlaying = "games/reversi/match/playing"
        case matchWarned = "games/reversi/match/warned"
        case matchWon = "games/reversi/match/won"
        case matchDraw = "games/reversi/match/draw"
        case matchLost = "games/reversi/match/lost"
        case watch = "games/reversi/watch"
        case watchOver = "games/reversi/watch/over"
        case ai = "games/reversi/ai"
        case aiWhite = "games/reversi/ai/white"
        case aiInvite = "games/reversi/ai/invite"

        /// 스텁이 고르는 장면 이름(`_` 를 뺀 폴더 이름). 폴더가 **없는** 장면도 값은 있다 — 그때는 바깥 층이 답한다.
        package var scenario: String { rawValue.replacingOccurrences(of: "/", with: "-") }

        /// 이 장면이 여는 **내 판**(`ReversiStore.openWindow(focusMatchID:)` 로 간다).
        package var focusMatchID: String? {
            switch self {
            case .matchPlaying: return Self.playingID
            case .matchWarned: return Self.warnedID
            case .matchWon: return Self.wonID
            case .matchDraw: return Self.drawID
            case .matchLost: return Self.lostID
            case .lobby, .lobbyInvites, .ranking, .rules, .watch, .watchOver, .ai, .aiWhite, .aiInvite: return nil
            }
        }

        /// 이 장면이 거는 **남의 판 관전**(`ReversiStore.startWatching(matchID:)` 로 간다).
        package var watchMatchID: String? {
            switch self {
            case .watch: return Self.watchLiveID
            case .watchOver: return Self.watchOverID
            default: return nil
            }
        }

        /// 로봇 연습을 세울 때 **내** 돌 색(nil = 로봇 연습 장면이 아니다).
        package var aiHumanColor: ReversiColor? {
            switch self {
            case .ai, .aiInvite: return .black
            case .aiWhite: return .white
            default: return nil
            }
        }

        /// 규칙 시트를 열어 둔다.
        package var opensRules: Bool { self == .rules }

        /// 로비 스크롤을 **맨 아래 절(순위)** 에서 시작한다. 순위는 별도 화면이 아니라 로비 안 절이다(push 하면 폴링이 죽는다).
        package var startsAtBottom: Bool { self == .ranking }

        package static let playingID = "d0000000-0000-4000-8000-0000000000e1"
        package static let warnedID = "d0000000-0000-4000-8000-0000000000e2"
        package static let wonID = "d0000000-0000-4000-8000-0000000000e3"
        package static let drawID = "d0000000-0000-4000-8000-0000000000e4"
        package static let lostID = "d0000000-0000-4000-8000-0000000000e5"
        package static let watchLiveID = "d0000000-0000-4000-8000-0000000000e6"
        package static let watchOverID = "d0000000-0000-4000-8000-0000000000e7"
        /// 로비 "지금 대결 중" 둘째 판(솜사탕 · 꿀떡) — 관전 장면은 없다(로비 줄만).
        package static let liveQuickID = "d0000000-0000-4000-8000-0000000000e8"
        /// 받은 신청 둘(구름빵 · 호두과자)과 보낸 신청 하나(초코칩).
        package static let inviteInID = "d0000000-0000-4000-8000-0000000000e9"
        package static let inviteInSecondID = "d0000000-0000-4000-8000-0000000000ea"
        package static let inviteOutID = "d0000000-0000-4000-8000-0000000000eb"
    }

    package var scene: Scene

    package init(scene: Scene) {
        self.scene = scene
    }

    package var focusMatchID: String? { scene.focusMatchID }
    package var watchMatchID: String? { scene.watchMatchID }
    package var scenario: String { scene.scenario }
    /// 게임 탭이 쌓을 경로 — 열넷이 **한 화면**으로 간다(로비 · 판 · 결과 · 관전 · 순위 · 로봇 연습이 모두 `GamesReversiScreen` 안이다).
    package var destination: GamesDestination { .reversi }

    /// 데모 라우트 글자 → 값. 아잉 뒤집기 라우트가 아니면 nil. `games/reversi` 한 토막은 로비 머리다(`AingRoute` 에 주인이 없다 — 미니게임 이름이 아니다).
    /// 모르는 꼬리는 **로비 머리로 접는다**(조용히 버리면 데모가 기본 탭에 머물러 라우트 오타를 사람이 못 가린다 — 테트리스와 같은 규약).
    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard path == "games/reversi" || path.hasPrefix("games/reversi/") else { return nil }
        self.init(scene: Scene(rawValue: path) ?? .lobby)
    }

    /// 이 데모 라우트가 아잉 뒤집기 화면을 띄우라는 뜻인가. 꼬리까지 푸는 자리는 `init?(demoRoute:)` 하나다(두 판정이 갈리지 않게).
    package static func isReversiRoute(_ raw: String) -> Bool {
        MobileDemoReversiRoute(demoRoute: raw) != nil
    }

    /// 화면이 설 때(판을 읽기 전) 스토어에 적을 것 — 규칙 시트 · 로봇 연습. 다시 불러도 해롭지 않다:
    /// 로봇 판은 `canStartAIMatch` 일 때만 연다(들고 있는 판이 있으면 돌아선다 — `startAIMatch` 의 '바쁨' 안내도 안 남긴다).
    @MainActor
    package func prepare(_ store: ReversiStore) {
        if scene.opensRules, !store.isRulesVisible { store.isRulesVisible = true }
        if let color = scene.aiHumanColor, store.canStartAIMatch { store.startAIMatch(humanColor: color) }
    }
}
#endif
