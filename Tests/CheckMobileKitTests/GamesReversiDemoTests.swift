@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **아잉 뒤집기 데모**(갈래 4/4 · 대표 답 #d_DdwzmxPClGqk) — 라우트 값 `MobileDemoReversiRoute` 와 픽스처 `Demo/Fixtures/games/rpc.reversi_*` 의 계약.
//
// 화면은 `#if os(iOS)` 안이라 맥 스위트가 못 본다. 그래서 여기서 재는 것은 **글자가 아니라 코어가 그 글자로 세우는 것**이다:
//   ① 라우트 열넷이 각각 **다른** 장면으로 간다(체스 D6 — 꼬리를 버리자 라우트 일곱 중 넷이 같은 그림이었다).
//   ② 장면 폴더 · 바늘이 스텁의 고르기 규칙과 한 식이다(바늘이 틀리면 404 가 `noteServerMissing()` 으로 화면을 '곧 열려요'로 내린다).
//   ③ 모든 픽스처가 **서버 RPC 반환 모양**이다 — 키 집합을 서버 SQL(20261108200000_reversi.sql 의 jsonb_build_object)·서버 하네스가 떨군 원문의
//      매니페스트와 대조한다. 사람 행 id 키가 로비는 `id`, state·순위는 `user_id` 인 것까지(바꿔 쓰면 디코더가 nil 을 내고 목록이 조용히 빈다).
//   ④ 판 글자 · 돌 수 · 둘 곳 · 점수 · 끝난 까닭이 **규칙 엔진으로 되짚어** 맞다(기록을 처음부터 다시 둔다 — 지어낸 판이면 빨개진다).
//   ⑤ 루비 · 전적이 정산 식과 맞고 한 화면에 같이 뜨는 두 응답(장면 로비 · 상태)이 같은 숫자다.
//   ⑥ 데모 환경으로 앱 모델을 띄워 **스텁만으로** 장면마다 코어가 다른 상태를 세운다(갈림 자체를 센다).
@MainActor
@Suite(.serialized) struct GamesReversiDemoTests {
    typealias S = MobileDemoReversiRoute.Scene

    static let index = MobileDemoFixtures.load()
    /// 서비스와 **같은 설정**이어야 한다(디코더가 다르면 이 스위트가 초록이어도 앱에서 nil 이 된다).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    static let nowMs = 1_789_621_500_000.0          // MobileClock.demoInstant
    static let baseRuby = 42
    static let baseRecord = (wins: 4, losses: 2, draws: 1)

    // MARK: - 라우트 표

    struct Row {
        let route: String
        let scene: S
        let focus: String?
        let watch: String?
        let ai: ReversiColor?
        let rules: Bool
        let bottom: Bool
    }

    static let table: [Row] = [
        .init(route: "games/reversi/lobby", scene: .lobby, focus: nil, watch: nil, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/lobby/invites", scene: .lobbyInvites, focus: nil, watch: nil, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/ranking", scene: .ranking, focus: nil, watch: nil, ai: nil, rules: false, bottom: true),
        .init(route: "games/reversi/rules", scene: .rules, focus: nil, watch: nil, ai: nil, rules: true, bottom: false),
        .init(route: "games/reversi/match/playing", scene: .matchPlaying, focus: S.playingID, watch: nil, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/match/warned", scene: .matchWarned, focus: S.warnedID, watch: nil, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/match/won", scene: .matchWon, focus: S.wonID, watch: nil, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/match/draw", scene: .matchDraw, focus: S.drawID, watch: nil, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/match/lost", scene: .matchLost, focus: S.lostID, watch: nil, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/watch", scene: .watch, focus: nil, watch: S.watchLiveID, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/watch/over", scene: .watchOver, focus: nil, watch: S.watchOverID, ai: nil, rules: false, bottom: false),
        .init(route: "games/reversi/ai", scene: .ai, focus: nil, watch: nil, ai: .black, rules: false, bottom: false),
        .init(route: "games/reversi/ai/white", scene: .aiWhite, focus: nil, watch: nil, ai: .white, rules: false, bottom: false),
        .init(route: "games/reversi/ai/invite", scene: .aiInvite, focus: nil, watch: nil, ai: .black, rules: false, bottom: false),
    ]

    /// 장면 폴더가 있어야 하는 장면 — 로비 변형이 필요한 일곱(로비 머리·순위·규칙·관전·로봇 연습 둘은 바깥 층이 답한다).
    static let sceneFolders: Set<String> = [
        "games-reversi-lobby-invites", "games-reversi-ai-invite",
        "games-reversi-match-playing", "games-reversi-match-warned",
        "games-reversi-match-won", "games-reversi-match-draw", "games-reversi-match-lost",
    ]

    /// 아잉 뒤집기 데모 픽스처는 **정확히 이 스물하나**다(로비 8 · 상태 6 · 관전 2 · 쓰기 4 · 순위 1). 늘리거나 줄이는 것은 결정이다.
    static let requiredPaths: Set<String> = {
        var paths: Set<String> = [
            "games/rpc.reversi_lobby.json",
            "games/rpc.reversi_ranking.json",
            "games/rpc.reversi_challenge.json",
            "games/rpc.reversi_cancel.json",
            "games/rpc.reversi_respond@true.json",
            "games/rpc.reversi_respond@false.json",
            "games/rpc.reversi_state@\(S.inviteOutID).json",
            "games/rpc.reversi_watch_live@\(S.watchLiveID).json",
            "games/rpc.reversi_watch_live@\(S.watchOverID).json",
        ]
        for id in [S.playingID, S.warnedID, S.wonID, S.drawID, S.lostID] { paths.insert("games/rpc.reversi_state@\(id).json") }
        for folder in sceneFolders { paths.insert("games/_\(folder)/rpc.reversi_lobby.json") }
        return paths
    }()

    // MARK: - 도우미

    /// 스텁이 **실제로 고르는 길**(키 + 바늘 + 장면)로 한 장을 집는다 — 파일 경로를 짚으면 고르기 규칙이 바뀌어도 초록이다.
    static func body(rpc: String, matchID: String? = nil, accept: Bool? = nil, route: String = "games/reversi/lobby") throws -> Data {
        var fields = [#""p_protocol":1"#]
        if let matchID { fields.append(#""p_match_id":"\#(matchID)""#) }
        if let accept { fields.append(#""p_accept":\#(accept)"#) }
        if rpc == "reversi_state" || rpc.hasPrefix("reversi_watch") { fields.append(#""p_since_seq":0"#) }
        let request = MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)",
                                        query: "", headers: [:], bodyText: "{" + fields.joined(separator: ",") + "}")
        let scenario = route.replacingOccurrences(of: "/", with: "-").lowercased()
        let entry = try #require(index.entry(for: request, scenario: scenario), "스텁이 \(rpc) 를 \(route) 장면에서 못 고른다(404 로 접힌다)")
        return entry.data
    }

    static func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func lobby(route: String) throws -> ReversiLobbyResponse {
        try decoder.decode(ReversiLobbyResponse.self, from: body(rpc: "reversi_lobby", route: route))
    }

    static func action(rpc: String, matchID: String? = nil, accept: Bool? = nil, route: String = "games/reversi/lobby") throws -> ReversiActionResponse {
        try decoder.decode(ReversiActionResponse.self, from: body(rpc: rpc, matchID: matchID, accept: accept, route: route))
    }

    static func rpcName(of entry: MobileDemoFixtures.Entry) -> String { String(entry.key.dropFirst("rpc.".count)) }

    static var reversiEntries: [MobileDemoFixtures.Entry] { index.entries.filter { $0.key.hasPrefix("rpc.reversi_") } }

    // MARK: - ① 라우트 표 그대로 풀린다 · 갈린다

    @Test("라우트 열넷이 표대로 풀린다 — 열 판 · 관전 · 로봇 색 · 규칙 시트 · 맨 아래 시작 · 한 화면(.reversi)")
    func theTableResolvesAsWritten() throws {
        for row in Self.table {
            let parsed = try #require(MobileDemoReversiRoute(demoRoute: row.route), "\(row.route): 값이 안 선다")
            #expect(parsed.scene == row.scene, "\(row.route): \(parsed.scene)")
            #expect(parsed.focusMatchID == row.focus, "\(row.route): 열 판")
            #expect(parsed.watchMatchID == row.watch, "\(row.route): 관전")
            #expect(parsed.scene.aiHumanColor == row.ai, "\(row.route): 로봇 연습 색")
            #expect(parsed.scene.opensRules == row.rules && parsed.scene.startsAtBottom == row.bottom, "\(row.route)")
            #expect(parsed.destination == .reversi)
            #expect(parsed.scenario == row.route.replacingOccurrences(of: "/", with: "-"), "\(row.route): 장면 이름이 스텁 식과 다르다")
        }
        #expect(Self.table.map(\.route) == S.allCases.map(\.rawValue), "표와 장면 열거가 다르다 — 한쪽만 넓히면 새 장면이 조용히 로비로 접힌다")
    }

    @Test("갈림: 열넷이 서로 다른 효과를 낸다(장면 폴더 · 판 · 관전 · 로봇 · 규칙 · 닻) — 같은 효과 둘이면 스크린샷이 같은 그림이다")
    func everyRouteHasADistinctEffect() {
        let folders = Set(Self.index.entries.compactMap(\.scenario))
        let effects = Self.table.map { row -> String in
            let folder = folders.contains(row.scene.scenario) ? row.scene.scenario : "-"
            return [folder, row.focus ?? "-", row.watch ?? "-", row.ai?.rawValue ?? "-", "\(row.rules)", "\(row.bottom)"].joined(separator: "|")
        }
        #expect(Set(effects).count == Self.table.count, "두 라우트가 같은 효과다: \(effects)")
        #expect(Set(Self.table.compactMap(\.focus) + Self.table.compactMap(\.watch)).count == 7, "판 장면 · 관전 장면이 같은 판을 연다")
    }

    @Test("모르는 꼬리는 로비 머리로 접힌다 · games/reversi 한 토막도 로비 · 남의 데모 라우트는 안 읽는다 · AingRoute 에 주인이 없다")
    func unknownTailsFoldIntoTheLobbyHead() {
        for raw in ["games/reversi", "games/reversi/", "games/reversi/match", "games/reversi/match/\(S.playingID)",
                    "games/reversi/watch/live", "games/reversi/nope", "games/reversi/ai/red"] {
            let parsed = MobileDemoReversiRoute(demoRoute: raw)
            #expect(parsed?.scene == .lobby, "\(raw): 로비 머리로 접혀야 한다(나온 값 \(String(describing: parsed)))")
            #expect(parsed?.focusMatchID == nil && parsed?.watchMatchID == nil, "\(raw): 모르는 id 를 코어에 흘리면 404 가 화면을 내린다")
        }
        #expect(MobileDemoReversiRoute(demoRoute: " /games/reversi/MATCH/Won/ ")?.scene == .matchWon, "글자 다듬기(빈 칸 · 슬래시 · 대문자)")
        for raw in ["games", "games/tetris", "games/tetris/lobby", "games/rummy/lobby", "games/chess/lobby", "games/gomoku/lobby",
                    "games/reversiduel", "reversi/lobby", "me/shop", "now"] {
            #expect(MobileDemoReversiRoute(demoRoute: raw) == nil, "남의 데모 라우트를 아잉 뒤집기로 읽었다: \(raw)")
            #expect(!MobileDemoReversiRoute.isReversiRoute(raw))
        }
        // `games/reversi` 를 가로채도 잃는 라우트가 없다 — 미니게임 이름이 아니다(테트리스 한 토막과 다른 자리).
        #expect(AingRoute(path: "games/reversi") == nil, "games/reversi 에 주인(AingRoute)이 생겼다 — 데모 갈래가 그 링크를 가로챈다")
        #expect(MobileAppModel.isDemoChessRoute("games/reversi/lobby") == false, "체스 데모 갈래가 아잉 뒤집기를 먹는다")
        #expect(MobileDemoRummyRoute(demoRoute: "games/reversi/lobby") == nil && MobileDemoTetrisRoute(demoRoute: "games/reversi/lobby") == nil)
    }

    // MARK: - ② 파일 집합 · 장면 폴더 · 바늘

    @Test("픽스처는 정확히 스물하나 · 장면 폴더는 일곱이고 각 폴더에는 로비 한 장뿐 · 키가 겹치지 않는다")
    func fixtureSetIsPinned() {
        let found = Set(Self.reversiEntries.map(\.relativePath))
        #expect(found == Self.requiredPaths, """
            아잉 뒤집기 픽스처 집합이 달라졌다.
            더 생긴 것: \(found.subtracting(Self.requiredPaths).sorted())
            사라진 것: \(Self.requiredPaths.subtracting(found).sorted())
            """)
        #expect(Self.index.duplicateKeys.isEmpty, "\(Self.index.duplicateKeys)")
        let folders = Set(Self.index.entries.compactMap(\.scenario).filter { $0.hasPrefix("games-reversi") })
        #expect(folders == Self.sceneFolders, "장면 폴더 집합: \(folders.sorted())")
        for folder in folders {
            #expect(Self.index.entries.filter { $0.scenario == folder }.map(\.key) == ["rpc.reversi_lobby"], "\(folder)")
        }
        // 폴더 이름이 표 밖이면 그 폴더는 조용히 안 쓰인다.
        #expect(folders.subtracting(Set(S.allCases.map(\.scenario))).isEmpty)
    }

    @Test("판 장면의 열 판마다 상태 픽스처가 있고 바늘이 그 id 다 · 진행 중 장면의 로비가 같은 판을 가리킨다 · 끝난 장면은 안 가리킨다")
    func everyFocusHasItsStateAndLobby() throws {
        for row in Self.table {
            if let focus = row.focus {
                let response = try Self.action(rpc: "reversi_state", matchID: focus, route: row.route)
                let match = try #require(response.state?.match, "\(row.route): 상태 봉투에 판이 없다")
                #expect(match.id == focus, "\(row.route): 바늘 \(focus) 로 고른 판이 \(match.id ?? "nil") 다")
                let lobby = try Self.lobby(route: row.route)
                let active = match.matchStatus == .active
                #expect(lobby.me?.activeMatchId == (active ? focus : nil),
                        "\(row.route): 로비 active_match_id 가 \(lobby.me?.activeMatchId ?? "nil") — 진행 중이면 그 판, 끝났으면 null(서버는 active 만 가리킨다)")
            }
            if let watch = row.watch {
                let response = try Self.action(rpc: "reversi_watch_live", matchID: watch, route: row.route)
                #expect(response.state?.match?.id == watch, "\(row.route): 관전 바늘")
                #expect(response.state?.myColor == nil && response.state?.opponent == nil && response.state?.rubyBalance == nil,
                        "\(row.route): 관전 응답이 참가자 칸을 싣는다 — 대국 화면으로 옮겨질 수 있다")
            }
        }
        // 진행 중 관전 판은 로비 '지금 대결 중' 줄에 있다(씨앗 얼굴) · 끝난 관전 판은 없다(서버는 active 만 싣는다).
        let base = try Self.lobby(route: "games/reversi/watch")
        #expect(base.matches?.contains { $0.id == S.watchLiveID } == true)
        #expect(base.matches?.contains { $0.id == S.watchOverID } == false)
        // 보낸 신청 장면은 코어가 그 신청의 상태를 한 번 읽는다(5초 폴링) — 그 답이 있어야 한다.
        let invites = try Self.lobby(route: "games/reversi/lobby/invites")
        let sent = try #require(invites.me?.outgoing?.matchId)
        #expect(try Self.action(rpc: "reversi_state", matchID: sent, route: "games/reversi/lobby/invites").state?.match?.matchStatus == .pending)
    }

    // MARK: - ③ 서버 모양

    /// 서버 SQL(20261108200000_reversi.sql)의 jsonb_build_object 키 — 서버 하네스가 떨군 원문 매니페스트(flip/server/fixtures/_manifest.json)와 같다.
    enum Shape {
        static let lobby: Set<String> = ["auto_abandon_streak", "invite_ttl_seconds", "matches", "me", "server_now_ms", "stakes", "status",
                                         "turn_grace_seconds", "turn_seconds", "users"]
        static let lobbyMe: Set<String> = ["active_match_id", "draws", "incoming", "losses", "outgoing", "ruby_balance", "wins"]
        static let lobbyUser: Set<String> = ["avatar_url", "capable", "center", "character", "display_name", "focus_mode", "id", "in_match", "is_working"]
        static let lobbyMatch: Set<String> = ["a", "b", "id", "stake", "started_at_ms", "watchers"]
        static let peer: Set<String> = ["avatar_url", "character", "display_name", "id"]
        static let incoming: Set<String> = ["expires_at_ms", "from", "match_id", "stake"]
        static let outgoing: Set<String> = ["expires_at_ms", "match_id", "stake", "to"]
        static let match: Set<String> = ["black", "board", "challenger", "deadline_ms", "discs", "end_reason", "finished_ms", "id", "invite_expires_ms",
                                         "move_count", "opponent", "result", "score", "stake", "started_ms", "status", "turn", "turn_started_ms",
                                         "white", "winner"]
        static let state: Set<String> = ["auto_abandon_streak", "black_auto_streak", "black_user", "grace_ms", "legal_moves", "match", "moves",
                                         "my_auto_streak", "my_color", "opponent", "opponent_auto_streak", "ruby_balance", "server_now_ms",
                                         "turn_seconds", "watchers", "white_auto_streak", "white_user"]
        static let move: Set<String> = ["at_ms", "auto", "color", "flipped", "idx", "kind", "seq"]
        static let user: Set<String> = ["avatar_url", "center", "character", "display_name", "user_id"]
        static let ranking: Set<String> = ["me", "record_since_ms", "rows", "server_now_ms", "status"]
        static let rankRow: Set<String> = ["avatar_url", "center", "character", "display_name", "draws", "losses", "points", "rank", "user_id", "wins"]
        static let rankMe: Set<String> = ["draws", "losses", "points", "rank", "wins"]
        static let challengeOK: Set<String> = ["invite_expires_ms", "match_id", "ruby_balance", "server_now_ms", "status"]
        static let cancelOK: Set<String> = ["server_now_ms", "status"]
    }

    static func keys(_ object: [String: Any]) -> Set<String> { Set(object.keys).subtracting(["__note"]) }

    static func expectUUID(_ value: Any?, _ label: String) {
        guard let text = value as? String else { return }
        #expect(UUID(uuidString: text) != nil && text == text.lowercased(), "\(label): 서버 id 는 소문자 uuid 다 — \(text)")
    }

    static func expectStateShape(_ state: [String: Any], _ label: String) throws {
        #expect(keys(state) == Shape.state, "\(label) state 키: \(keys(state).symmetricDifference(Shape.state).sorted())")
        let match = try #require(state["match"] as? [String: Any], "\(label): match 가 없다")
        #expect(keys(match) == Shape.match, "\(label) match 키: \(keys(match).symmetricDifference(Shape.match).sorted())")
        for key in ["id", "challenger", "opponent", "black", "white", "winner"] { expectUUID(match[key], "\(label) match.\(key)") }
        for move in state["moves"] as? [[String: Any]] ?? [] {
            #expect(keys(move) == Shape.move, "\(label) move 키: \(keys(move).sorted())")
        }
        for key in ["black_user", "white_user", "opponent"] {
            guard let row = state[key] as? [String: Any] else { continue }
            #expect(keys(row) == Shape.user, "\(label) \(key) 키: \(keys(row).sorted()) — state 의 사람 행 id 키는 user_id 다")
            expectUUID(row["user_id"], "\(label) \(key).user_id")
        }
    }

    @Test("모든 픽스처가 서버 RPC 반환 모양이다 — 키 집합 · 사람 행 id 키(로비 id / state·순위 user_id) · uuid · 서비스 디코더로 status ok")
    func everyFixtureHasTheServerShape() throws {
        var seen: Set<String> = []
        for entry in Self.reversiEntries {
            let label = entry.relativePath
            let top = try Self.object(entry.data)
            let rpc = Self.rpcName(of: entry)
            seen.insert(rpc)
            #expect(top["status"] as? String == "ok", "\(label): status")
            switch rpc {
            case "reversi_lobby":
                #expect(Self.keys(top) == Shape.lobby, "\(label): \(Self.keys(top).symmetricDifference(Shape.lobby).sorted())")
                let me = try #require(top["me"] as? [String: Any])
                #expect(Self.keys(me) == Shape.lobbyMe, "\(label) me")
                for row in me["incoming"] as? [[String: Any]] ?? [] {
                    #expect(Self.keys(row) == Shape.incoming, "\(label) incoming")
                    let from = try #require(row["from"] as? [String: Any], "\(label) incoming.from")
                    #expect(Self.keys(from) == Shape.peer, "\(label) incoming.from")
                    Self.expectUUID(row["match_id"], label)
                }
                if let row = me["outgoing"] as? [String: Any] {
                    #expect(Self.keys(row) == Shape.outgoing, "\(label) outgoing")
                    let to = try #require(row["to"] as? [String: Any], "\(label) outgoing.to")
                    #expect(Self.keys(to) == Shape.peer, "\(label) outgoing.to")
                }
                let users = try #require(top["users"] as? [[String: Any]])
                #expect(!users.isEmpty)
                for row in users {
                    #expect(Self.keys(row) == Shape.lobbyUser, "\(label) user \(Self.keys(row).sorted()) — 로비 사람 행 id 키는 id 다")
                    #expect(row["id"] as? String != MobileDemo.userID, "\(label): 로비 users 에 내가 있다(서버는 호출자를 뺀다)")
                    Self.expectUUID(row["id"], label)
                }
                for row in top["matches"] as? [[String: Any]] ?? [] {
                    #expect(Self.keys(row) == Shape.lobbyMatch, "\(label) match row")
                    let a = try #require(row["a"] as? [String: Any]), b = try #require(row["b"] as? [String: Any])
                    #expect(Self.keys(a) == Shape.peer && Self.keys(b) == Shape.peer)
                    #expect((a["id"] as? String ?? "") < (b["id"] as? String ?? ""), "\(label): a/b 는 uuid 오름차순이다(색이 아니다)")
                    Self.expectUUID(row["id"], label)
                }
                let started = (top["matches"] as? [[String: Any]] ?? []).compactMap { $0["started_at_ms"] as? Double }
                #expect(started == started.sorted(by: >), "\(label): 지금 대결 중은 최근 순이다(서버 순서)")
                _ = try Self.decoder.decode(ReversiLobbyResponse.self, from: entry.data)
            case "reversi_state", "reversi_watch_live", "reversi_respond":
                let want: Set<String> = rpc == "reversi_respond" ? ["accepted", "state", "status"] : ["state", "status"]
                #expect(Self.keys(top) == want, "\(label): 봉투 키 \(Self.keys(top).sorted())(state 를 펼치지 않는다)")
                try Self.expectStateShape(try #require(top["state"] as? [String: Any]), label)
                let decoded = try Self.decoder.decode(ReversiActionResponse.self, from: entry.data)
                #expect(decoded.status == .ok && decoded.state?.match?.board != nil, "\(label): 디코드한 판이 없다")
            case "reversi_ranking":
                #expect(Self.keys(top) == Shape.ranking, "\(label)")
                let rankMe = try #require(top["me"] as? [String: Any])
                #expect(Self.keys(rankMe) == Shape.rankMe)
                for row in try #require(top["rows"] as? [[String: Any]]) {
                    #expect(Self.keys(row) == Shape.rankRow, "\(label) row \(Self.keys(row).sorted()) — 순위 사람 행 id 키는 user_id 다")
                    Self.expectUUID(row["user_id"], label)
                }
                _ = try Self.decoder.decode(ReversiRankingResponse.self, from: entry.data)
            case "reversi_challenge":
                #expect(Self.keys(top) == Shape.challengeOK, "\(label)")
                Self.expectUUID(top["match_id"], label)
            case "reversi_cancel":
                #expect(Self.keys(top) == Shape.cancelOK, "\(label)")
            default:
                Issue.record("\(label): 계약 밖의 RPC 픽스처")
            }
        }
        #expect(seen == ["reversi_lobby", "reversi_state", "reversi_watch_live", "reversi_respond", "reversi_ranking",
                         "reversi_challenge", "reversi_cancel"])
        // 쓰기 응답 둘은 받은 신청 장면의 **첫 신청**을 말한다(다른 판 id 면 수락하는 순간 엉뚱한 판이 선다).
        let firstInvite = try #require(try Self.lobby(route: "games/reversi/lobby/invites").me?.incoming?.first?.matchId)
        let yes = try Self.action(rpc: "reversi_respond", matchID: firstInvite, accept: true, route: "games/reversi/lobby/invites")
        let no = try Self.action(rpc: "reversi_respond", matchID: firstInvite, accept: false, route: "games/reversi/lobby/invites")
        #expect(yes.accepted == true && yes.state?.match?.id == firstInvite && yes.state?.match?.matchStatus == .active)
        #expect(no.accepted == false && no.state?.match?.id == firstInvite && no.state?.match?.matchStatus == .declined)
        #expect(yes.state?.legalMoves == ReversiRules.legalMoves(.start, color: .black), "수락 판의 첫 둘 곳이 시작 판 규칙과 다르다")
        // 신청 응답의 판은 보낸 신청 장면의 pending 판이다 — 뒤따르는 상태 읽기도 픽스처가 답한다.
        #expect(try Self.action(rpc: "reversi_challenge").matchId == S.inviteOutID)
    }

    // MARK: - ④ 판이 규칙과 맞다

    /// 상태 · 관전 픽스처 전부(장면 · 바늘 · RPC).
    static var boards: [(label: String, rpc: String, id: String, route: String)] {
        Self.table.compactMap { row in row.focus.map { (row.route, "reversi_state", $0, row.route) } }
            + Self.table.compactMap { row in row.watch.map { (row.route, "reversi_watch_live", $0, row.route) } }
    }

    @Test("판이 규칙과 맞다 — 기록을 처음부터 다시 두면 판 글자 · 돌 수 · 패스 줄 · 다음 차례 · 둘 곳 · 점수 · 끝난 까닭 · 자동 착수 연속이 그대로 나온다")
    func boardsReplayUnderTheRules() throws {
        var finals: Set<String> = []
        for item in Self.boards {
            let label = item.label
            let payload = try #require(try Self.action(rpc: item.rpc, matchID: item.id, route: item.route).state)
            let match = try #require(payload.match)
            let plies = try #require(payload.moves)
            var board = ReversiBoard.start
            var next: ReversiColor? = .black
            var over = false
            var lastOutcome: ReversiMoveOutcome?
            var pendingPass: ReversiColor?
            for (offset, ply) in plies.enumerated() {
                #expect(ply.seq == offset + 1, "\(label): seq 가 1부터 이어지지 않는다(\(ply.seq))")
                switch ply.kind {
                case .pass:
                    #expect(pendingPass == ply.color, "\(label): seq \(ply.seq) 패스 줄이 규칙의 자동 패스와 다르다")
                    pendingPass = nil
                case .stone:
                    #expect(pendingPass == nil, "\(label): 자동 패스 줄이 빠졌다(seq \(ply.seq) 앞)")
                    #expect(!over, "\(label): 끝난 판에 돌을 더 뒀다")
                    #expect(ply.color == next, "\(label): seq \(ply.seq) 차례가 아니다")
                    let idx = try #require(ply.idx)
                    guard case .success(let outcome) = ReversiRules.play(board, color: ply.color, idx: idx) else {
                        Issue.record("\(label): seq \(ply.seq) 는 규칙 밖의 수다(\(idx))")
                        return
                    }
                    #expect(outcome.flipped == ply.flipped, "\(label): seq \(ply.seq) 뒤집힌 칸이 엔진과 다르다")
                    board = outcome.board
                    next = outcome.next
                    over = outcome.isOver
                    lastOutcome = outcome
                    if outcome.passed { pendingPass = ply.color.opponent }
                }
            }
            #expect(pendingPass == nil, "\(label): 마지막 자동 패스 줄이 없다")
            #expect(match.board == board, "\(label): 판 글자가 기록을 되짚은 판과 다르다")
            #expect(match.discs == board.counts, "\(label): 돌 수")
            #expect(match.moveCount == plies.count, "\(label): move_count")
            finals.insert(board.string)
            let auto = { (color: ReversiColor) -> Int in
                plies.filter { $0.kind == .stone && $0.color == color }.reversed().prefix(while: { $0.auto }).count
            }
            #expect(payload.blackAutoStreak == auto(.black) && payload.whiteAutoStreak == auto(.white), "\(label): 자동 착수 연속 수가 기록과 다르다")
            switch match.matchStatus {
            case .active:
                #expect(!over && match.turn == next, "\(label): 다음 차례")
                #expect(match.deadlineMs == match.turnStartedMs.map { $0 + 30_000 }, "\(label): 마감 = 차례 시작 + 30초")
                let mine = payload.myColor
                let want: [Int] = next.map { mine == $0 ? ReversiRules.legalMoves(board, color: $0) : [] } ?? []
                #expect(payload.legalMoves == want, "\(label): 둘 곳(서버는 내 차례에만 싣는다)")
                #expect(match.score == nil && match.result == nil && match.finishedMs == nil)
            case .finished:
                #expect(match.turn == nil && match.deadlineMs == nil && match.legalMovesAreEmpty(payload), "\(label): 끝난 판의 차례 · 마감 · 둘 곳")
                switch match.endReason {
                case .boardFull?, .wipeout?, .noMoves?:
                    let score = try #require(ReversiRules.score(board), "\(label): 자연 종료라는데 판이 안 끝났다")
                    #expect(over && lastOutcome?.end.map { ReversiEndReason($0) } == match.endReason, "\(label): 끝난 까닭")
                    #expect(match.score?.black == score.black && match.score?.white == score.white && match.result == score.result, "\(label): WOF 점수")
                case .abandoned?:
                    // 셋째 자동 착수가 판에 놓인 뒤 서버가 닫는다 — 진 쪽의 마지막 세 수가 자동이고 점수는 없다(서버 CHECK).
                    let loser: ReversiColor = match.result == .blackWin ? .white : .black
                    #expect(auto(loser) == payload.autoAbandonStreak, "\(label): 자리 비움 패인데 진 쪽 자동 착수가 \(auto(loser)) 번이다")
                    #expect(match.score == nil && !over, "\(label): 자리 비움 판에 점수가 있다")
                case .resign?:
                    #expect(match.score == nil && !over, "\(label): 기권 판에 점수가 있다")
                default:
                    Issue.record("\(label): 끝난 까닭 \(String(describing: match.endReason))")
                }
                let winnerColor: ReversiColor? = match.result?.winner
                let winnerID: String? = winnerColor.flatMap { $0 == .black ? match.black : match.white }
                #expect(match.winner == winnerID, "\(label): winner 가 결과의 색과 다른 사람이다")
            default:
                Issue.record("\(label): 판 상태 \(match.matchStatus)")
            }
        }
        #expect(finals.count == Self.boards.count, "두 장면이 같은 판을 그린다 — 기준선이 같은 입력이면 그 장면은 영원히 같은 그림이다")
    }

    // MARK: - ⑤ 루비 · 전적

    @Test("루비 · 전적이 정산 식과 맞고, 한 화면에 같이 뜨는 장면 로비와 상태가 같은 숫자다 · 순위 me 줄 = 기본 로비 전적")
    func rubyAndRecordAgree() throws {
        let base = try Self.lobby(route: "games/reversi/lobby")
        #expect(base.me?.rubyBalance == Self.baseRuby)
        #expect(base.me?.wins == Self.baseRecord.wins && base.me?.losses == Self.baseRecord.losses && base.me?.draws == Self.baseRecord.draws)
        for row in Self.table {
            guard let focus = row.focus else { continue }
            let state = try #require(try Self.action(rpc: "reversi_state", matchID: focus, route: row.route).state)
            let match = try #require(state.match)
            let stake = try #require(match.stake)
            #expect([3, 5, 10].contains(stake), "\(row.route): 판돈 \(stake) 는 서버 CHECK 밖이다")
            let mine = try #require(state.myColor)
            let outcome: ReversiMatchOutcome? = match.result.map { $0.winner == nil ? .draw : ($0.winner == mine ? .won : .lost) }
            let expected: Int
            switch outcome {
            case nil: expected = Self.baseRuby - stake
            case .won?: expected = Self.baseRuby - stake + DuelFee.winnerPayout(stake: stake)
            case .lost?: expected = Self.baseRuby - stake
            case .draw?: expected = Self.baseRuby
            }
            #expect(state.rubyBalance == expected, "\(row.route): 상태 잔액 \(state.rubyBalance ?? -1) ≠ 정산 \(expected)")
            let lobby = try Self.lobby(route: row.route)
            #expect(lobby.me?.rubyBalance == expected, "\(row.route): 장면 로비 잔액이 상태와 다르다")
            let record = (lobby.me?.wins ?? -1, lobby.me?.losses ?? -1, lobby.me?.draws ?? -1)
            let want = (Self.baseRecord.wins + (outcome == .won ? 1 : 0), Self.baseRecord.losses + (outcome == .lost ? 1 : 0),
                        Self.baseRecord.draws + (outcome == .draw ? 1 : 0))
            #expect(record == want, "\(row.route): 장면 로비 전적 \(record) ≠ \(want)")
        }
        let ranking = try Self.decoder.decode(ReversiRankingResponse.self, from: Self.body(rpc: "reversi_ranking"))
        let rows = try #require(ranking.rows)
        #expect(rows.count > 5, "순위가 다섯 줄 이하라 [전체 보기]가 안 선다")
        #expect(rows.map { $0.rank ?? 0 } == rows.map { $0.rank ?? 0 }.sorted(), "서버 순서(순위 오름차순)")
        for row in rows { #expect(row.points == (row.wins ?? 0) - (row.losses ?? 0), "승점 = 승 − 패: \(row.displayName ?? "")") }
        #expect(ranking.me?.wins == Self.baseRecord.wins && ranking.me?.losses == Self.baseRecord.losses && ranking.me?.draws == Self.baseRecord.draws)
        #expect(rows.contains { $0.userId == MobileDemo.userID && $0.rank == ranking.me?.rank })
    }

    // MARK: - ⑥ 스텁만으로 장면이 선다

    /// 데모 환경으로 앱 모델을 띄워 그 장면까지 간다(게임 탭이 쌓는 깃발을 꺼내고 화면 훅을 부른다 — 뷰가 하는 일 그대로).
    private func launch(_ route: String) async throws -> MobileAppModel {
        let environment = try #require(MobileDemo.environment(arguments: ["-AingCheckDemo", "YES", "-AingCheckDemoRoute", route]))
        let model = MobileAppModel(environment: environment)
        model.session.clientReleaseTimeoutSeconds = 0
        model.reversi.aiRuntime.minimumThinkSeconds = 0
        model.start()
        model.sceneDidBecomeActive()
        _ = await baseWaitUntil { model.session.isSignedIn }
        #expect(await baseWaitUntil { model.games.pendingDemoReversiScreen }, "\(route): 앱 모델이 아잉 뒤집기 깃발을 안 세운다")
        #expect(model.games.consumePendingDemoReversiScreen(), "\(route): 게임 탭이 아잉 뒤집기를 안 쌓는다")
        #expect(model.games.demoReversiRoute?.scene.rawValue == route)
        model.games.reversiScreenDidAppear()
        return model
    }

    @Test("장면: 라우트 열넷마다 코어가 다른 상태를 세운다 — 스텁만으로(서버 없음이 화면을 내리지 않는다)")
    func scenesStandOnStubsAlone() async throws {
        try await baseWithDemoHost {
            var signatures: [String: String] = [:]
            for row in Self.table {
                let model = try await launch(row.route)
                let reversi = model.reversi
                let games = model.games
                let ready: Bool
                switch row.scene {
                case .lobby, .ranking:
                    ready = await baseWaitUntil { reversi.record != nil && reversi.ranking != nil }
                case .lobbyInvites:
                    ready = await baseWaitUntil { reversi.visibleIncomingInvites.count == 2 && reversi.outgoing != nil }
                case .rules:
                    ready = await baseWaitUntil { reversi.isRulesVisible && reversi.record != nil }
                case .matchPlaying, .matchWarned:
                    ready = await baseWaitUntil { reversi.match?.id == row.focus && reversi.phase == .playing }
                case .matchWon, .matchDraw, .matchLost:
                    ready = await baseWaitUntil { reversi.match?.id == row.focus && reversi.phase == .result }
                case .watch, .watchOver:
                    ready = await baseWaitUntil { reversi.spectating?.id == row.watch && (reversi.spectating?.moveCount ?? 0) > 0 }
                case .ai, .aiWhite:
                    ready = await baseWaitUntil { reversi.isAIMatch && reversi.match?.isMyTurn == true && reversi.record != nil }
                case .aiInvite:
                    ready = await baseWaitUntil { reversi.isAIMatch && GamesReversiInviteBanner.invite(reversi) != nil }
                }
                #expect(ready, "\(row.route): 장면이 안 선다(phase \(reversi.phase) · match \(reversi.match?.id ?? "nil") · 관전 \(reversi.spectating?.id ?? "nil"))")
                // 바늘 · 폴링이 한 번씩 돈 뒤에도 서버 없음으로 접히지 않았다(빠진 픽스처가 있으면 404 → noteServerMissing).
                try? await Task.sleep(nanoseconds: 700_000_000)
                #expect(reversi.availability == .available, "\(row.route): 픽스처가 빠져 서버 없음으로 접혔다")
                #expect(reversi.notice == nil, "\(row.route): 데모 장면에 안내가 섰다 — \(reversi.notice ?? "")")
                let now = reversi.clock()
                switch row.scene {
                case .lobby:
                    #expect(games.reversiLobbyUsers.count == 9)
                    #expect(GamesReversiLobbyPlan.lockLegends(games).count == 3, "풀이 줄 셋(업데이트 · 대결 중 · 집중)이 다 안 선다")
                    #expect(reversi.liveMatches.count == 2 && reversi.liveMatches.contains { $0.id == S.watchLiveID && $0.watchers == 3 })
                    #expect(reversi.ranking?.entries.count == 8 && reversi.myRankConsistentWithRecord?.rank == 4, "내 순위 줄이 안 선다")
                case .lobbyInvites:
                    #expect(reversi.visibleIncomingInvites.map(\.id) == [S.inviteInID, S.inviteInSecondID], "받은 신청은 서버 순서(최근 순)")
                    #expect(reversi.visibleIncomingInvites.map { Int($0.expiresAt.timeIntervalSince(now).rounded()) } == [45, 31])
                    #expect(reversi.outgoing?.id == S.inviteOutID && reversi.outgoing?.stake == 3)
                case .matchPlaying:
                    #expect(reversi.match?.isMyTurn == true && reversi.match?.myColor == .black && reversi.legalTargets.count >= 5)
                    #expect(reversi.remainingSeconds(now: now).map { Int($0.rounded()) } == 18, "데모 시계로 남은 초가 고정이 아니다")
                case .matchWarned:
                    let match = try #require(reversi.match)
                    #expect(match.myAutoStreak == 2 && match.myColor == .white && match.isMyTurn)
                    let chrome = GamesReversiMatchChrome(match: match, notice: nil, isBusy: false, serverTurnSeconds: reversi.turnSeconds)
                    #expect(chrome.autoStreakWarning != nil, "한 번 더 놓치면 지는 빨강 줄이 안 선다")
                    #expect(reversi.remainingSeconds(now: now).map { Int($0.rounded()) } == 9)
                case .matchWon, .matchDraw, .matchLost:
                    let match = try #require(reversi.match)
                    let chrome = GamesReversiMatchChrome(match: match, notice: nil, isBusy: false, serverTurnSeconds: reversi.turnSeconds)
                    let result = try #require(chrome.result)
                    switch row.scene {
                    case .matchWon:
                        #expect(match.outcome == .won && result.rubyDelta == 5 && match.score != nil)
                    case .matchDraw:
                        #expect(match.outcome == .draw && result.isDraw && result.rubyNote == ReversiPhoneText.drawRefund(stake: 10),
                                "무승부 환불 줄: \(result.rubyNote ?? "nil")")
                    default:
                        #expect(match.outcome == .lost && match.endReason == .abandoned && result.rubyDelta == -3 && match.score == nil)
                    }
                case .watch:
                    #expect(reversi.spectating?.isFinished == false && reversi.spectatorCount == 3 && reversi.spectating?.faces.count == 2,
                            "관전 씨앗(로비 줄의 두 얼굴) · 관전자 수")
                case .watchOver:
                    #expect(reversi.spectating?.isFinished == true && reversi.spectating?.endReason == .resign && reversi.spectating?.winner == .black)
                case .ai:
                    #expect(reversi.match?.myColor == .black && reversi.match?.moveCount == 0)
                case .aiWhite:
                    #expect(reversi.match?.myColor == .white && (reversi.match?.moveCount ?? 0) >= 1, "로봇(흑)이 먼저 두지 않았다")
                case .aiInvite:
                    #expect(GamesReversiInviteBanner.invite(reversi)?.id == S.inviteInID && GamesReversiInviteBanner.moreCount(reversi) == 1)
                case .rules, .ranking:
                    break
                }
                signatures[row.route] = [
                    // 로봇 판 id 는 실행마다 새 uuid 다 — 그대로 넣으면 갈림이 저절로 서므로 '로봇'으로 접는다.
                    "\(reversi.phase)", reversi.isAIMatch ? "ai" : (reversi.match?.id ?? "-"), reversi.spectating?.id ?? "-",
                    "\(reversi.match?.myColor.rawValue ?? "-")", "\(reversi.isRulesVisible)", "\(reversi.visibleIncomingInvites.count)",
                    "\(reversi.outgoing != nil)", "\(row.scene.startsAtBottom)",
                ].joined(separator: "|")
                await model.session.signOut()
            }
            #expect(Set(signatures.values).count == Self.table.count, "두 라우트가 같은 상태를 세운다: \(signatures.sorted { $0.key < $1.key })")
        }
    }

    // MARK: - 소스 계약: 값과 그 이름이 나오는 줄이 전부 #if DEBUG 안이다

    @Test("라우트 값과 그 이름이 나오는 소스 줄이 전부 #if DEBUG 안이다 · 플랫폼 분기가 없다(맥 스위트가 이 값을 잰다)")
    func theRouteValueIsDebugOnlyAndPlatformFree() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let raw = try String(contentsOf: root.appendingPathComponent("Sources/CheckMobileKit/Demo/MobileDemoReversiRoute.swift"), encoding: .utf8)
        let typeFile = stripComments(raw)
        #expect(typeFile.contains("package struct MobileDemoReversiRoute"))
        #expect(raw.hasPrefix("#if DEBUG") && raw.hasSuffix("#endif\n"))
        #expect(!typeFile.contains("#if os("), "플랫폼 분기를 더하면 이 스위트가 통째로 사라진다")
        for forbidden in ["reversiScreenDidAppear", "reversiScreenDidDisappear", "openWindow(", "windowDidShow", "presentReversiScreen"]
            where typeFile.contains(forbidden) {
            Issue.record("데모 라우트 값이 화면 수명 문을 부른다(배선의 소유다): \(forbidden)")
        }
        let base = root.appendingPathComponent("Sources/CheckMobileKit")
        let enumerator = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        var sourcesSeen = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = stripComments(try String(contentsOf: url, encoding: .utf8))
            guard text.contains("MobileDemoReversiRoute") || text.contains("demoReversiRoute") else { continue }
            sourcesSeen += 1
            var depth = 0
            var debugDepth: Int?
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if") {
                    depth += 1
                    if trimmed.contains("DEBUG"), debugDepth == nil { debugDepth = depth }
                } else if trimmed.hasPrefix("#else") {
                    if debugDepth == depth { debugDepth = nil }
                } else if trimmed.hasPrefix("#endif") {
                    if debugDepth == depth { debugDepth = nil }
                    depth -= 1
                }
                guard line.contains("MobileDemoReversiRoute") || line.contains("demoReversiRoute") else { continue }
                #expect(debugDepth != nil, """
                    \(url.lastPathComponent): 이 줄이 #if DEBUG 밖이다 — Release 바이너리에 데모 타입 이름이 남아 출시 게이트(금지 문자열 MobileDemo)가 막는다.
                    \(trimmed)
                    """)
            }
        }
        #expect(sourcesSeen >= 4, "대조: 이름이 나오는 소스(라우트 · 앱 모델 · 게임 스토어 · 화면)를 다 못 찾았다(\(sourcesSeen))")
    }
}

private extension ReversiMatchRow {
    /// 끝난 판에 둘 곳이 실리지 않았는가(서버는 active 이고 내 차례일 때만 싣는다).
    func legalMovesAreEmpty(_ payload: ReversiStatePayload) -> Bool { (payload.legalMoves ?? []).isEmpty }
}
