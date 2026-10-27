// 원본: 없음
@testable import CheckCore
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckMobileKit

// W1-d G6 디코드 덤프(C§5.2 · G §2-3 W1-d ②): 응답 픽스처(시험 픽스처 + 데모 픽스처) → 서비스와 **같은 디코더**로 읽은 값의
// 정규 덤프(GoldenMirror) + 변형마다(키 빼기 · null · 타입 바꾸기 · 정수 칸에 3.0/3.5 · 2^31 넘는 정수 · 모르는 열거값) 결과
// (실패면 "error", 성공이면 원본 덤프와 **다른 점만**). Kotlin 은 같은 픽스처에 같은 변형을 가해 kotlin-reflect 덤프와 대조한다.
//
// 타입 고르기 = 서비스 메서드가 그 경로에서 디코드하는 타입(SupabaseWorkService*.swift). W1-c 몫 타입(AchievementStatus ·
// WeeklyWorkStatus · Megaphone*)은 이 골든의 case 가 아니다 — spec.otherLanes 에 경로와 함께 적는다(그 골든은 W1-c missions·weekly).
// 디코드가 없는 경로(로그아웃 등)는 spec.noDecode. 어느 쪽에도 없는 픽스처가 생기면 이 시험이 빨갛다(빠짐 금지).

enum WireDecodeRegistry {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// 타입 이름 → 디코드(서비스와 같은 설정). 이름은 Kotlin 레지스트리 열쇠와 같다.
    nonisolated(unsafe) static let decoders: [String: (Data) throws -> Any] = {
        func one<T: Decodable>(_ t: T.Type) -> (Data) throws -> Any { { try decoder.decode(T.self, from: $0) } }
        func list<T: Decodable>(_ t: T.Type) -> (Data) throws -> Any { { try decoder.decode([T].self, from: $0) } }
        return [
            "ChessActionResponse": one(ChessActionResponse.self),
            "ChessLobbyResponse": one(ChessLobbyResponse.self),
            "ChessStateResponse": one(ChessStateResponse.self),
            "ChessRankingResponse": one(ChessRankingResponse.self),
            "ChessWatchResponse": one(ChessWatchResponse.self),
            "GomokuActionResponse": one(GomokuActionResponse.self),
            "GomokuLobbyResponse": one(GomokuLobbyResponse.self),
            "GomokuStateResponse": one(GomokuStateResponse.self),
            "GomokuInboxResponse": one(GomokuInboxResponse.self),
            "GomokuChatResponse": one(GomokuChatResponse.self),
            "GomokuLeaveResponse": one(GomokuLeaveResponse.self),
            "GomokuRankingResponse": one(GomokuRankingResponse.self),
            "GomokuWatchResponse": one(GomokuWatchResponse.self),
            "TetrisActionResponse": one(TetrisActionResponse.self),
            "TetrisLobbyResponse": one(TetrisLobbyResponse.self),
            "TetrisRankingResponse": one(TetrisRankingResponse.self),
            "TetrisWatchResponse": one(TetrisWatchResponse.self),
            "[MessageHistoryRow]": list(MessageHistoryRow.self),
            "[MessageHistoryReadsRow]": list(MessageHistoryReadsRow.self),
            "MessageUnreadSummaryResponse": one(MessageUnreadSummaryResponse.self),
            "MessageReadMarkResponse": one(MessageReadMarkResponse.self),
            "PokeSendResponse": one(PokeSendResponse.self),
            "[TakenPokeRow]": list(TakenPokeRow.self),
            "TodoSyncResponse": { try TodoSyncResponse.decode($0) },
            "ClientReleaseResponse": one(ClientReleaseResponse.self),
            "SignInResponse": one(SignInResponse.self),
            "SignUpResponse": one(SignUpResponse.self),
            "[MembershipRow]": list(MembershipRow.self),
            "[AppUserCharacterRow]": list(AppUserCharacterRow.self),
            "RegisterDeviceResponse": one(RegisterDeviceResponse.self),
            "SetPushPrefsResponse": one(SetPushPrefsResponse.self),
            "UnregisterDeviceResponse": one(UnregisterDeviceResponse.self),
            "[ProfilePrivacyRow]": list(ProfilePrivacyRow.self),
            "[MiniGameBoardRow]": list(MiniGameBoardRow.self),
            "[MiniGameWinnerRow]": list(MiniGameWinnerRow.self),
            "[MiniGameAllTimeBoardRow]": list(MiniGameAllTimeBoardRow.self),
            "MiniGameStartRoundResponse": one(MiniGameStartRoundResponse.self),
            "MiniGameSubmitScoreResponse": one(MiniGameSubmitScoreResponse.self),
            "[AILimitServerRow]": list(AILimitServerRow.self),
            "[CharacterSyncProfileRow]": list(CharacterSyncProfileRow.self),
            "[TokenUsageDailyRow]": list(TokenUsageDailyRow.self),
            "[WorkSessionRow]": list(WorkSessionRow.self),
            "[WorkStatusRow]": list(WorkStatusRow.self),
            "ShopStateResponse": one(ShopStateResponse.self),
            "[DisplayNameChangedAtRow]": list(DisplayNameChangedAtRow.self),
            "[MeProfileCardRow]": list(MeProfileCardRow.self),
            "[ProfileCenterRow]": list(ProfileCenterRow.self),
            "[ProfileStatusMessageRow]": list(ProfileStatusMessageRow.self),
            "BuyCharacterResponse": one(BuyCharacterResponse.self),
            "CharacterGiftPendingResponse": one(CharacterGiftPendingResponse.self),
            "CharacterGiftClaimResponse": one(CharacterGiftClaimResponse.self),
            "[FeedbackReportRow]": list(FeedbackReportRow.self),
            "String": one(String.self),
            "GachaExchangeResponse": one(GachaExchangeResponse.self),
            "GachaPullResponse": one(GachaPullResponse.self),
            "[InviteCodeRow]": list(InviteCodeRow.self),
            "SetCharacterResponse": one(SetCharacterResponse.self),
            "DisplayNameChangeResponse": one(DisplayNameChangeResponse.self),
            "SetStatusMessageResponse": one(SetStatusMessageResponse.self),
            "[PokeDirectoryRow]": list(PokeDirectoryRow.self),
            "[MessagePokeLossyRow]": list(MessagePokeLossyRow.self),
            "PhoneWorkResponse": one(PhoneWorkResponse.self),
            "[SetTeamGoalRow]": list(SetTeamGoalRow.self),
            "[TeamLeaderboardRow]": list(TeamLeaderboardRow.self),
            "[TokenBoardRow]": list(TokenBoardRow.self),
            "[CreateTeamRow]": list(CreateTeamRow.self),
            "[JoinTeamRow]": list(JoinTeamRow.self),
            "[TeamJoinPreviewRow]": list(TeamJoinPreviewRow.self),
            "[WorkStatusDeviceRow]": list(WorkStatusDeviceRow.self),
            "AppNotice": one(AppNotice.self),
            "AppLatestRelease": one(AppLatestRelease.self),
            "[BlockedUserRow]": list(BlockedUserRow.self),
            "MessageConversationReadMarkResponse": one(MessageConversationReadMarkResponse.self),
            "SupabaseErrorResponse": one(SupabaseErrorResponse.self),
        ]
    }()

    /// 정규 덤프. 디코드가 던지면 nil.
    static func dump(_ type: String, _ data: Data) throws -> GoldenJSON? {
        guard let decode = decoders[type] else { throw GoldenJSONError("레지스트리에 없는 타입 \(type)") }
        guard let value = try? decode(data) else { return nil }
        return try GoldenMirror.dump(value)
    }

    // ---- 픽스처 → 타입 ----

    /// 시험 픽스처(Tests/checkTests/Fixtures/*-rpc): 파일 이름의 RPC 이름 → 타입.
    static func fixtureType(dir: String, file: String) -> String? {
        let name = file.replacingOccurrences(of: ".json", with: "")
        let rpc = name.components(separatedBy: "__").first ?? name
        switch dir {
        case "chess-rpc", "chess-rpc-clock10":
            switch rpc {
            case "chess_lobby": return "ChessLobbyResponse"
            case "chess_state": return "ChessStateResponse"
            case "chess_ranking": return "ChessRankingResponse"
            case "chess_watch": return "ChessWatchResponse"
            case "chess_cancel", "chess_challenge", "chess_respond", "chess_move", "chess_resign", "chess_offer_draw", "chess_respond_draw":
                return "ChessActionResponse"
            default: return nil
            }
        case "gomoku-rpc":
            if name.hasPrefix("flow_m1_") { return name.hasSuffix("_move") ? "GomokuActionResponse" : (name.contains("_state_since") ? "GomokuStateResponse" : nil) }
            switch rpc {
            case "gomoku_lobby": return "GomokuLobbyResponse"
            case "gomoku_state": return "GomokuStateResponse"
            case "gomoku_inbox": return "GomokuInboxResponse"
            case "gomoku_chat_send", "gomoku_chat_mute": return "GomokuChatResponse"
            case "gomoku_leave": return "GomokuLeaveResponse"
            case "gomoku_ranking": return "GomokuRankingResponse"
            case "gomoku_watch": return "GomokuWatchResponse"
            case "gomoku_challenge", "gomoku_cancel", "gomoku_respond", "gomoku_move", "gomoku_resign": return "GomokuActionResponse"
            default: return nil
            }
        case "message-rpc":
            if name.hasPrefix("flow_") {
                if name.hasSuffix("__mark") { return "MessageReadMarkResponse" }
                if name.hasSuffix("__summary") { return "MessageUnreadSummaryResponse" }
                if name.contains("__with_reads_") { return "[MessageHistoryReadsRow]" }
                return nil
            }
            switch rpc {
            case "message_history": return "[MessageHistoryRow]"
            case "message_history_with_reads": return "[MessageHistoryReadsRow]"
            case "message_unread_summary": return "MessageUnreadSummaryResponse"
            case "mark_messages_read": return "MessageReadMarkResponse"
            case "send_message": return "PokeSendResponse"
            case "take_pokes": return "[TakenPokeRow]"
            default: return nil
            }
        case "todo-rpc":
            return rpc == "todo_sync" ? "TodoSyncResponse" : nil
        default:
            return nil
        }
    }

    /// 시험 픽스처 중 서비스 디코드가 아닌 것(실시간 방송 행 — 실시간 골든이 다룬다).
    static let fixtureNotDecoded: Set<String> = ["Tests/checkTests/Fixtures/message-rpc/realtime__message_read_rows.json"]

    /// 데모 픽스처 경로의 이름(`rpc.<name>` · `rest.<표>.<메서드>` · `auth.<경로>.<메서드>`, `@` 뒤 변형은 버린다) → 타입.
    static let demoRouteTypes: [String: String] = [
        "rpc.client_release": "ClientReleaseResponse",
        "auth.token.post": "SignInResponse",
        "auth.verify.post": "SignInResponse",
        "auth.signup.post": "SignUpResponse",
        "rest.memberships.get": "[MembershipRow]",
        "rpc.app_user_characters": "[AppUserCharacterRow]",
        "rpc.register_device": "RegisterDeviceResponse",
        "rpc.set_push_prefs": "SetPushPrefsResponse",
        "rpc.unregister_device": "UnregisterDeviceResponse",
        "rpc.chess_lobby": "ChessLobbyResponse",
        "rpc.chess_ranking": "ChessRankingResponse",
        "rpc.chess_state": "ChessStateResponse",
        "rpc.chess_watch": "ChessWatchResponse",
        "rpc.gomoku_inbox": "GomokuInboxResponse",
        "rpc.gomoku_state": "GomokuStateResponse",
        "rpc.gomoku_lobby": "GomokuLobbyResponse",
        "rpc.gomoku_watch": "GomokuWatchResponse",
        "rpc.gomoku_chat_send": "GomokuChatResponse",
        "rpc.gomoku_leave": "GomokuLeaveResponse",
        "rpc.gomoku_ranking": "GomokuRankingResponse",
        "rpc.tetris_lobby": "TetrisLobbyResponse",
        "rpc.tetris_ranking": "TetrisRankingResponse",
        "rpc.tetris_cancel": "TetrisActionResponse",
        "rpc.tetris_challenge": "TetrisActionResponse",
        "rpc.tetris_report": "TetrisActionResponse",
        "rpc.tetris_resign": "TetrisActionResponse",
        "rpc.tetris_respond": "TetrisActionResponse",
        "rpc.tetris_state": "TetrisActionResponse",
        "rpc.minigame_board": "[MiniGameBoardRow]",
        "rpc.minigame_yesterday_winner": "[MiniGameWinnerRow]",
        "rpc.minigame_start_round": "MiniGameStartRoundResponse",
        "rpc.minigame_submit_score": "MiniGameSubmitScoreResponse",
        "rest.ai_limits.get": "[AILimitServerRow]",
        "rest.token_usage_device_daily.get": "[TokenUsageDailyRow]",
        "rest.work_sessions.get": "[WorkSessionRow]",
        "rest.work_statuses.get": "[WorkStatusRow]",
        "rpc.shop_state": "ShopStateResponse",
        "rpc.buy_character": "BuyCharacterResponse",
        "rpc.character_gift_pending": "CharacterGiftPendingResponse",
        "rpc.claim_character_gift": "CharacterGiftClaimResponse",
        "rpc.feedback_list": "[FeedbackReportRow]",
        "rpc.feedback_reply_latest": "String",
        "rpc.submit_feedback": "String",
        "rpc.gacha_exchange": "GachaExchangeResponse",
        "rpc.gacha_pull": "GachaPullResponse",
        "rpc.my_team_invite_code": "[InviteCodeRow]",
        "rpc.set_character": "SetCharacterResponse",
        "rpc.set_display_name": "DisplayNameChangeResponse",
        "rpc.set_status_message": "SetStatusMessageResponse",
        "rpc.app_user_directory": "[PokeDirectoryRow]",
        "rpc.send_message": "PokeSendResponse",
        "rpc.message_history_with_pokes": "[MessagePokeLossyRow]",
        "rpc.message_history_with_reads": "[MessageHistoryReadsRow]",
        "rpc.mark_messages_read": "MessageReadMarkResponse",
        "rpc.message_unread_summary": "MessageUnreadSummaryResponse",
        "rpc.todo_sync": "TodoSyncResponse",
        "rpc.work_phone_touch": "PhoneWorkResponse",
        "rpc.work_phone_start": "PhoneWorkResponse",
        "rpc.work_phone_stop": "PhoneWorkResponse",
        "rpc.set_team_weekly_goal": "[SetTeamGoalRow]",
        "rpc.team_weekly_leaderboard": "[TeamLeaderboardRow]",
        "rpc.token_usage_board": "[TokenBoardRow]",
        "rpc.create_team": "[CreateTeamRow]",
        "rpc.join_team": "[JoinTeamRow]",
        "rpc.lookup_team_by_code": "[TeamJoinPreviewRow]",
    ]

    /// `rest.profiles.get@…` 는 select 칸으로 타입이 갈린다(같은 표, 다른 GET).
    static func profilesType(variant: String) -> String? {
        if variant.contains("minigame_public") || variant.contains("token_usage_collect") { return "[ProfilePrivacyRow]" }
        if variant.contains("character") { return "[CharacterSyncProfileRow]" }
        if variant.contains("display_name_changed_at") { return "[DisplayNameChangedAtRow]" }
        if variant.contains("display_name,avatar_url") { return "[MeProfileCardRow]" }
        if variant.contains("center") { return "[ProfileCenterRow]" }
        if variant.contains("status_message") { return "[ProfileStatusMessageRow]" }
        return nil
    }

    /// W1-c 몫 응답 타입(rules 의 lossy 디코드 — 골든은 W1-c 가 낸다).
    static let otherLaneRoutes: [String: String] = [
        "rpc.achievements_status": "W1-c AchievementStatus(missions)",
        "rpc.achievement_claim": "W1-c AchievementStatus(missions)",
        "rpc.daily_mission_claim": "W1-c AchievementStatus(missions)",
        "rpc.weekly_work_status": "W1-c WeeklyWorkStatus(weekly)",
        "rpc.weekly_work_claim": "W1-c WeeklyWorkStatus(weekly)",
        "rpc.megaphone_info": "W1-c MegaphoneInfoResponse(text)",
        "rpc.send_megaphone": "W1-c MegaphoneSendResponse(text)",
    ]

    /// 서비스가 응답을 디코드하지 않는 경로.
    static let noDecodeRoutes: Set<String> = ["auth.logout.post", "auth.recover.post", "auth.resend.post", "auth.user.put"]

    static func demoRoute(_ relative: String) -> (route: String, variant: String) {
        let file = (relative as NSString).lastPathComponent.replacingOccurrences(of: ".json", with: "")
        let parts = file.components(separatedBy: "@")
        return (parts[0], parts.count > 1 ? parts[1...].joined(separator: "@") : "")
    }

    static func demoType(_ relative: String) -> String? {
        let (route, variant) = demoRoute(relative)
        if route == "rest.profiles.get" { return profilesType(variant: variant) }
        return demoRouteTypes[route]
    }

    // ---- case 만들기 ----

    static func listJSON(under dir: String) throws -> [String] {
        let root = WireRepo.url(dir)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [String] = []
        for case let url as URL in e where url.pathExtension == "json" {
            let rel = String(url.path.dropFirst(WireRepo.root.path.count + 1))
            out.append(rel)
        }
        return out.sorted()
    }

    static func cases(_ files: [(id: String, type: String)]) throws -> [GoldenJSON] {
        var seen = Set<String>()
        var out: [GoldenJSON] = []
        for (id, type) in files {
            let text = try String(contentsOf: WireRepo.url(id), encoding: .utf8)
            out.append(try oneCase(id: id, type: type, text: text, seen: &seen))
        }
        return out
    }

    static func oneCase(id: String, type: String, text: String, seen: inout Set<String>, extra: [String: GoldenJSON] = [:]) throws -> GoldenJSON {
        let tree = try WireJSON.parse(text)
        let base = try dump(type, Data(text.utf8))
        var variants: [GoldenJSON] = []
        for (path, op) in WireVariant.plan(tree) {
            guard seen.insert("\(type)|\(WireVariant.normalized(path))|\(op)").inserted else { continue }
            let changed = WireVariant.apply(tree, path: path, op: op)
            let result: GoldenJSON
            if let r = try dump(type, Data(changed.text.utf8)) {
                result = try base.map { try GoldenWireDiff.diff($0, r) } ?? r
            } else {
                result = .string("error")
            }
            variants.append(.object(["path": .string(path), "op": .string(op), "result": WireScrub.json(result)]))
        }
        var object: [String: GoldenJSON] = [
            "id": .string(id), "type": .string(type), "dump": WireScrub.json(base ?? .string("$error")), "variants": .array(variants),
        ]
        for (k, v) in extra { object[k] = v }
        return .object(object)
    }
}

@Suite("GoldenExport W1-d 와이어 — G6 디코드 덤프")
struct GoldenExportWireDecode {
    static let swiftSources = [
        "Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/ChessWire.swift", "Sources/CheckCore/TetrisWire.swift",
        "Sources/CheckCore/CharacterGift.swift", "Sources/CheckCore/MessagePokeLog.swift", "Sources/CheckCore/Gacha.swift",
        "Sources/CheckCore/TodoSync.swift", "Sources/CheckCore/AppUserCharacters.swift", "Sources/CheckCore/StatusMessage.swift",
        "Sources/CheckCore/SupabaseWorkServiceBlocks.swift", "Sources/CheckCore/SupabaseWorkServiceCharacter.swift",
        "Sources/CheckCore/SupabaseWorkServiceMessageReads.swift", "Sources/CheckMobileKit/Session/MobileDeviceService.swift",
        "Sources/CheckMobileKit/Session/MobilePhoneWorkService.swift", "Sources/CheckMobileKit/Me/MeProfileService.swift",
        "Sources/CheckMobileKit/Me/MeAILimitsService.swift",
    ]

    static let spec: [String: GoldenJSON] = [
        "decoder": .string("JSONDecoder(keyDecodingStrategy: .convertFromSnakeCase) — 서비스와 같다. TodoSyncResponse 만 키 변환 없는 JSONDecoder(TodoSyncResponse.decode)"),
        "dump": .string("contract/README.md §2-3 GoldenMirror 정규 덤프. 실패하면 \"$error\""),
        "variants": .string("경로($.a[0].b) × op: remove · null · str(\"3\") · num(3) · enum(\"zz_unknown_value\") · bool(true) · float0(정수 글자+\".0\") · float5(+\".5\") · big(4294967296 — 2^31 넘는 정수) · int(3) · empty([]). 배열은 첫 원소 안만. 같은 (타입·정규 경로·op)는 처음 한 번만. result = \"error\" 또는 원본 덤프와 다른 점 [[경로, 새 값]…](\"$absent\" = 빠짐)"),
        "input": .string("case id = 저장소 상대 경로(픽스처 원문을 Kotlin 이 직접 읽는다 — 복사 0). 합성 입력은 case.json 에 싣는다"),
        "scrub": .string("덤프·결과의 JWT 모양 글자(eyJ + 20자 이상)는 <jwt:길이> 로 바꿔 싣는다(비밀 검사) — Kotlin 도 같은 규칙으로 바꿔 견준다"),
    ]

    func emit(_ name: String, _ cases: [GoldenJSON], extra: [String: GoldenJSON] = [:]) {
        var spec = Self.spec
        for (k, v) in extra { spec[k] = v }
        goldenEmit(GoldenFile(golden: name, equivalence: .bit, swiftSources: Self.swiftSources, spec: spec, cases: cases))
    }

    func fixtureFiles(_ dirs: [String]) throws -> [(id: String, type: String)] {
        var out: [(id: String, type: String)] = []
        for dir in dirs {
            for rel in try WireDecodeRegistry.listJSON(under: "Tests/checkTests/Fixtures/\(dir)") {
                let file = (rel as NSString).lastPathComponent
                if file.hasPrefix("_") || WireDecodeRegistry.fixtureNotDecoded.contains(rel) { continue }
                guard let type = WireDecodeRegistry.fixtureType(dir: dir, file: file) else {
                    throw GoldenJSONError("픽스처 \(rel) 의 타입을 모른다 — WireDecodeRegistry.fixtureType 에 더한다")
                }
                out.append((rel, type))
            }
        }
        return out
    }

    @Test func chessFixtures() throws {
        emit("wire/decode-fixtures-chess", try WireDecodeRegistry.cases(try fixtureFiles(["chess-rpc", "chess-rpc-clock10"])))
    }

    @Test func gomokuFixtures() throws {
        emit("wire/decode-fixtures-gomoku", try WireDecodeRegistry.cases(try fixtureFiles(["gomoku-rpc"])))
    }

    @Test func messageTodoFixtures() throws {
        emit("wire/decode-fixtures-message-todo", try WireDecodeRegistry.cases(try fixtureFiles(["message-rpc", "todo-rpc"])),
             extra: ["notDecoded": .array(WireDecodeRegistry.fixtureNotDecoded.sorted().map(GoldenJSON.string))])
    }

    /// 데모 픽스처(Sources/CheckMobileKit/Demo/Fixtures — 182개). 영역 하나 = 골든 하나(크기 예산).
    func demo(_ area: String) throws -> (cases: [GoldenJSON], other: [GoldenJSON], none: [GoldenJSON]) {
        var files: [(id: String, type: String)] = []
        var other: [GoldenJSON] = []
        var none: [GoldenJSON] = []
        for rel in try WireDecodeRegistry.listJSON(under: "Sources/CheckMobileKit/Demo/Fixtures/\(area)") {
            let (route, _) = WireDecodeRegistry.demoRoute(rel)
            if let owner = WireDecodeRegistry.otherLaneRoutes[route] {
                other.append(.array([.string(rel), .string(owner)]))
            } else if WireDecodeRegistry.noDecodeRoutes.contains(route) {
                none.append(.string(rel))
            } else if let type = WireDecodeRegistry.demoType(rel) {
                files.append((rel, type))
            } else {
                throw GoldenJSONError("데모 픽스처 \(rel) 의 타입을 모른다 — WireDecodeRegistry 에 더한다")
            }
        }
        return (try WireDecodeRegistry.cases(files), other, none)
    }

    @Test func demoGames() throws {
        let d = try demo("games")
        emit("wire/decode-demo-games", d.cases, extra: ["otherLanes": .array(d.other), "noDecode": .array(d.none)])
    }

    @Test func demoMe() throws {
        let d = try demo("me")
        emit("wire/decode-demo-me", d.cases, extra: ["otherLanes": .array(d.other), "noDecode": .array(d.none)])
    }

    @Test func demoOther() throws {
        var cases: [GoldenJSON] = []
        var other: [GoldenJSON] = []
        var none: [GoldenJSON] = []
        for area in ["base", "messages", "now", "rankings", "session"] {
            let d = try demo(area)
            cases += d.cases
            other += d.other
            none += d.none
        }
        emit("wire/decode-demo-other", cases, extra: ["otherLanes": .array(other), "noDecode": .array(none)])
    }

    /// 합성 입력(픽스처가 없는 새 전선 — 역대 순위 · 관전 live · 공지 · 차단 · 대화 읽음 · 오류 본문 · 경계 정수).
    @Test func synthetic() throws {
        let samples: [(String, String, String)] = [
            ("alltime-basic", "[MiniGameAllTimeBoardRow]",
             #"[{"user_id":" AA000000-0000-4000-8000-0000000000A1 ","display_name":" 아잉 ","avatar_url":"","best_score":4210,"best_at":"2026-10-20T03:04:05.123+00:00","day":"2026-10-20","center":"seoul"},{"user_id":null,"best_score":5},{"user_id":"bb","best_score":"7","day":"  "},7,{"user_id":"cc","best_score":3.0,"best_at":"x"}]"#),
            ("alltime-empty", "[MiniGameAllTimeBoardRow]", "[]"),
            ("watch-live-gomoku", "GomokuWatchResponse",
             #"{"status":"ok","server_now_ms":1790000000000,"watchers":3,"match":{"id":"m","status":"active","board":"b","deadline_ms":1790000030000.5},"moves":[{"seq":1,"color":"black","x":7,"y":7,"auto":false}],"black_user":{"user_id":"a","display_name":"가"},"white_user":{"user_id":"b"},"auto_abandon_streak":2}"#),
            ("watch-live-chess", "ChessWatchResponse",
             #"{"status":"ok","watchers":0,"in_check":true,"match":{"id":"m","fen":"8/8/8/8/8/8/8/8 w - - 0 1","white_ms_left":59000,"increment_ms":0},"moves":[{"seq":1,"from":12,"to":28,"san":"e4"}]}"#),
            ("watch-live-tetris", "TetrisWatchResponse",
             #"{"status":"ok","watchers":12,"match":{"id":"m","stake":5,"status":"finished","result":"a_win","winner":"aa","reason":"top_out","finished_ms":1790000000000},"a":{"user":{"id":"aa","display_name":"A","center":"busan"},"board":"..........","lines":3,"pending":1,"garbage_sent":2,"topped_out":false,"last_seen_ms":1790000000000},"b":{"user":{"id":"bb"},"topped_out":true}}"#),
            ("tetris-status-unknown", "TetrisWatchResponse", #"{"status":"brand_new_status"}"#),
            ("notice-ok", "AppNotice", #"{"id":" n1 ","title":" 제목 ","body":"본문\n","link_url":"  ","link_label":" 열기 "}"#),
            ("notice-empty-title", "AppNotice", #"{"id":"n1","title":"  ","body":"b"}"#),
            ("blocks", "[BlockedUserRow]",
             #"[{"blocked":"bb","display_name":"B","blocked_at":"2026-10-01T00:00:00Z","blocked_epoch":1790000000},{"id":"cc","created_epoch":1790000001.0}]"#),
            ("conversation-read", "MessageConversationReadMarkResponse", #"{"status":"ok","advanced":true,"unread":0,"poke_advanced":false,"poke_unread":2}"#),
            ("gift-pending-cake", "CharacterGiftPendingResponse",
             #"{"status":"ok","gift":{"id":" g1 ","options":["aing_cake_choco",3,"robot","aing_cake_strawberry","aing_cake_choco"],"note":"  ","created_at":"2026-10-25T00:00:00Z"}}"#),
            ("gift-pending-no-options", "CharacterGiftPendingResponse", #"{"status":"ok","gift":{"id":"g1","options":["robot"]}}"#),
            ("gift-pending-not-ok", "CharacterGiftPendingResponse", #"{"status":"unauthorized","gift":{"id":"g1","options":["aing_cake_choco"]}}"#),
            ("shop-gift-only", "ShopStateResponse",
             #"{"ruby_balance":2147483648,"characters":[{"id":"aing_cake_choco","price":100,"gacha_only":true,"gift_only":true},{"id":"aing_gold","owned":false},{"id":"robot","price":50}],"gacha":{"price":50,"shards":3,"odds":[{"character_id":"aing_gold","percent":3},{"character_id":7},null,{"character_id":"robot","percent":97.0}],"shard_costs":{"aing_gold":20,"robot":"x","rainbow_aing":null}}}"#),
            ("shop-gacha-not-object", "ShopStateResponse", #"{"gacha":[1,2]}"#),
            ("poke-log-epochs", "[MessagePokeLossyRow]",
             #"[{"id":"1","kind":"poke","created_epoch":1790000000.5,"peer_user_id":"p"},{"id":"2","kind":"message","created_epoch":"1790000001","body":"hi"},{"id":"3","kind":" ultra ","created_epoch":-2.5},"x",{"id":4}]"#),
            ("error-body-gotrue", "SupabaseErrorResponse", #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#),
            ("error-body-postgrest", "SupabaseErrorResponse", #"{"code":"PGRST202","message":"Could not find the function public.x","details":null,"hint":null}"#),
            ("token-board-legacy", "[TokenBoardRow]",
             #"[{"user_id":"u","display_name":"D","claude_input":3000000000,"claude_output":1,"claude_cache_read":2,"claude_cache_creation":3,"codex_input":4,"codex_output":5,"total":9007199254740993}]"#),
            ("phone-work-lossy", "PhoneWorkResponse", #"{"status":"ok","session":{"id":"S","started_at":5},"check_after_seconds":"10","wallet":{"ruby_balance":3}}"#),
            ("latest-release", "AppLatestRelease", #"{"v":1,"version":"0.3.67","build":120,"notes":["a","b"],"published_at":"2026-10-27T00:00:00Z"}"#),
            ("devices", "[WorkStatusDeviceRow]", #"[{"user_id":"u","device_id":"d","session_id":null,"opened_session":true}]"#),
        ]
        var seen = Set<String>()
        var cases: [GoldenJSON] = []
        for (id, type, json) in samples {
            cases.append(try WireDecodeRegistry.oneCase(id: id, type: type, text: json, seen: &seen, extra: ["json": .string(json)]))
        }
        emit("wire/decode-synthetic", cases)
    }

    /// 빠짐 금지: 데모 픽스처 전부가 case · 다른 갈래 · 디코드 없음 중 하나로 갈렸고, 시험 픽스처 전부가 타입을 가졌다.
    @Test func everyFixtureIsClassified() throws {
        var total = 0
        for area in ["base", "games", "me", "messages", "now", "rankings", "session"] {
            for rel in try WireDecodeRegistry.listJSON(under: "Sources/CheckMobileKit/Demo/Fixtures/\(area)") {
                total += 1
                let (route, _) = WireDecodeRegistry.demoRoute(rel)
                let known = WireDecodeRegistry.otherLaneRoutes[route] != nil || WireDecodeRegistry.noDecodeRoutes.contains(route)
                    || WireDecodeRegistry.demoType(rel) != nil
                #expect(known, "분류 안 된 데모 픽스처 \(rel)")
            }
        }
        #expect(total == 182, "데모 픽스처 수가 바뀌었다(\(total)) — 배정표(182)와 골든을 다시 본다")
        let fixtures = try fixtureFiles(["chess-rpc", "chess-rpc-clock10", "gomoku-rpc", "message-rpc", "todo-rpc"])
        #expect(fixtures.count == 224, "시험 픽스처 수가 바뀌었다(\(fixtures.count))")
    }
}
