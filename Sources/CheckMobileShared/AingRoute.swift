import Foundation

/// 폰 앱의 딥링크(`aingcheck://…`) ↔ 화면. 푸시·위젯·데모 실행 인자가 모두 이 값 하나로 화면을 연다.
///
/// URL 모양(SPEC-ios §3 의 다섯 개 + 탭·하위 화면):
///
///     aingcheck://now
///     aingcheck://messages                 aingcheck://message/<peer>
///     aingcheck://rankings/league|tokens|minigame
///     aingcheck://games                    aingcheck://games/timing|flappy
///     aingcheck://gomoku/lobby             aingcheck://gomoku/invite/<match>    aingcheck://gomoku/match[/<match>]
///     aingcheck://me                       aingcheck://me/shop    aingcheck://me/settings
///     aingcheck://feedback[/<report>]
///
/// 모르는 모양은 nil 이다(조용히 "지금" 탭으로 접지 않는다 — 푸시 페이로드가 틀렸다는 사실을 호출부가 알아야 한다).
public enum AingRoute: Hashable, Sendable {
    case now
    case messages
    case message(peerID: String)
    case rankings(RankingsBoard)
    case games
    case miniGame(MiniGame)
    case gomokuLobby
    case gomokuInvite(matchID: String)
    /// nil = 지금 진행 중인 판(데모·"대국으로 돌아가기").
    case gomokuMatch(matchID: String?)
    case me
    case shop
    /// nil = 제보 목록.
    case feedback(reportID: String?)
    case settings

    public enum RankingsBoard: String, CaseIterable, Sendable {
        case league, tokens, minigame
    }

    /// 딥링크가 여는 미니게임(`aingcheck://games/<rawValue>`).
    ///
    /// ⚠️ **이 열거와 `MiniGameKind.phoneCases` 는 언제나 같이 넓힌다.** 한쪽만 넓히면 `GamesStore.routeStep` 이
    /// 모르는 값을 **조용히 다른 게임으로 오배달**한다 — 값이 없으니 컴파일 경고도 안 난다.
    /// 예전에 그 접는 식이 `game == .timing ? .timingBar : .flappy` 였고, `tetris` 를 여기만 더했다면
    /// 테트리스 딥링크가 전부 플래피를 열었을 것이다. 지금은 `routeStep` 이 **빠짐없는 switch** 라
    /// 여기에 값을 더하면 거기가 컴파일 에러로 막는다 — 그 구조를 되돌리지 마라.
    public enum MiniGame: String, CaseIterable, Sendable {
        case timing, flappy
        /// v0.3.38(2026-09-23 폰 노출과 같은 커밋).
        case tetris
    }

    public static let scheme = "aingcheck"

    /// 이 화면이 속한 탭.
    public var tab: AingTab {
        switch self {
        case .now: return .now
        case .messages, .message: return .messages
        case .rankings: return .rankings
        case .games, .miniGame, .gomokuLobby, .gomokuInvite, .gomokuMatch: return .games
        case .me, .shop, .feedback, .settings: return .me
        }
    }

    // MARK: URL ↔ 값

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // aingcheck://message/<peer> 에서 host 가 "message", path 가 "/<peer>" 다.
        var segments: [String] = []
        if let host = url.host(percentEncoded: false), !host.isEmpty { segments.append(host) }
        segments.append(contentsOf: url.path(percentEncoded: false).split(separator: "/").map(String.init))
        guard let route = Self.parse(segments) else { return nil }
        self = route
    }

    /// 데모 실행 인자(`-AingCheckDemoRoute messages/<peer>`)와 URL 이 같은 해석을 지난다.
    /// 데모 전용 표기(`messages/<peer>` · `games/gomoku/lobby` · `games/gomoku/match` · `me/feedback`)도 받는다.
    public init?(path: String) {
        guard let route = Self.parse(path.split(separator: "/").map(String.init)) else { return nil }
        self = route
    }

    private static func parse(_ raw: [String]) -> AingRoute? {
        var s = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // 데모 표기 games/gomoku/… 는 gomoku/… 와 같다.
        if s.count >= 2, s[0].lowercased() == "games", s[1].lowercased() == "gomoku" {
            s.removeFirst()
        }
        guard let head = s.first?.lowercased() else { return nil }
        let rest = Array(s.dropFirst())
        switch (head, rest.count) {
        case ("now", 0): return .now
        case ("messages", 0): return .messages
        case ("messages", 1), ("message", 1):
            return safeID(rest[0]).map { .message(peerID: $0) }
        case ("rankings", 0): return .rankings(.league)
        case ("rankings", 1):
            return RankingsBoard(rawValue: rest[0].lowercased()).map { .rankings($0) }
        case ("games", 0): return .games
        case ("games", 1):
            return MiniGame(rawValue: rest[0].lowercased()).map { .miniGame($0) }
        case ("gomoku", 0): return .gomokuLobby
        case ("gomoku", 1):
            switch rest[0].lowercased() {
            case "lobby": return .gomokuLobby
            case "match": return .gomokuMatch(matchID: nil)
            default: return nil
            }
        case ("gomoku", 2):
            guard let id = safeID(rest[1]) else { return nil }
            switch rest[0].lowercased() {
            case "invite": return .gomokuInvite(matchID: id)
            case "match": return .gomokuMatch(matchID: id)
            default: return nil
            }
        case ("me", 0): return .me
        case ("me", 1):
            switch rest[0].lowercased() {
            case "shop": return .shop
            case "settings": return .settings
            case "feedback": return .feedback(reportID: nil)
            default: return nil
            }
        case ("feedback", 0): return .feedback(reportID: nil)
        case ("feedback", 1):
            return safeID(rest[0]).map { .feedback(reportID: $0) }
        default:
            return nil
        }
    }

    /// 정규 URL. `AingRoute(url: route.url) == route` 가 모든 값에서 성립한다(테스트가 못 박는다).
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        let segments: [String]
        switch self {
        case .now: segments = ["now"]
        case .messages: segments = ["messages"]
        case .message(let peer): segments = ["message", peer]
        case .rankings(let board): segments = ["rankings", board.rawValue]
        case .games: segments = ["games"]
        case .miniGame(let game): segments = ["games", game.rawValue]
        case .gomokuLobby: segments = ["gomoku", "lobby"]
        case .gomokuInvite(let id): segments = ["gomoku", "invite", id]
        case .gomokuMatch(let id): segments = ["gomoku", "match"] + (id.map { [$0] } ?? [])
        case .me: segments = ["me"]
        case .shop: segments = ["me", "shop"]
        case .feedback(let id): segments = ["feedback"] + (id.map { [$0] } ?? [])
        case .settings: segments = ["me", "settings"]
        }
        components.host = segments[0]
        components.path = segments.count > 1 ? "/" + segments.dropFirst().joined(separator: "/") : ""
        return components.url ?? URL(string: "\(Self.scheme)://now")!
    }

    /// 경로에 실리는 id 는 서버 uuid·정수 id 모양만 받는다(`..`·공백·퍼센트 인코딩된 제어 문자는 거절).
    static func safeID(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.count <= 64,
              raw.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return raw
    }
}

/// 탭 다섯 개(SPEC-ios §3). 순서가 곧 탭 막대 순서다.
public enum AingTab: String, CaseIterable, Hashable, Sendable {
    case now, messages, rankings, games, me

    /// 탭 이름(한국어).
    public var title: String {
        switch self {
        case .now: return "지금"
        case .messages: return "메시지"
        case .rankings: return "순위"
        case .games: return "게임"
        case .me: return "나"
        }
    }

    /// SF Symbol 이름.
    public var systemImage: String {
        switch self {
        case .now: return "clock.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .rankings: return "trophy.fill"
        case .games: return "gamecontroller.fill"
        case .me: return "person.crop.circle.fill"
        }
    }
}
