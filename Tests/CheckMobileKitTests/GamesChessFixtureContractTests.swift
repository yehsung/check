// `package` 타입(ChessPosition·ChessRules·MobileDemoFixtures·MobileStubRequest)의 멤버와이즈·내부 멤버를
// 쓰므로 `@testable` 로 받는다 — 같은 폴더 `GamesGomokuRankingContractTests` 와 같은 길이다.
@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 체스 **데모 픽스처**(`Demo/Fixtures/games/rpc.chess_*.json`)의 계약.
//
// ── 왜 화면보다 이 파일이 먼저인가 ──
// 직전 오목 작업에서 관전 화면 416줄이 **한 번도 떠본 적 없는 상태로** 완성됐다. 폰 뷰는 `#if os(iOS)` 라 맥 스위트가
// 컴파일조차 못 하고(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'), 데모 데이터도 없어서 띄울 길이 아예 없었다. 그래서
// "관전자에게 이기면 +10이라고 말한다" 같은 결함을 전부 소스를 읽어서 잡았다 — 한 번 띄울 수 있었으면 10초에 보일
// 것들이었다. 이번엔 **데이터를 먼저** 두고, 그 데이터가 거짓을 그리지 못하게 여기서 못을 박는다.
//
// ── 무엇을 재는가: 모양이 아니라 **결과** ──
// "키가 있다"는 재지 않는다. 재는 것은 "그 값이 체스 규칙상 맞는가" 다:
//   ③ `match.fen` 하나에서 차례·체크·합법 수를 **엔진으로 다시 계산해** 서버 값과 맞춘다.
//      ★ 합법 수는 서버가 주는 값이고 PvP 화면은 그것만 쓴다 — 픽스처가 틀리면 화면이 못 두는 수를 보여 준다.
//   ④ 기보(SAN)를 표준 시작 국면부터 재생해 **최종 FEN 이 픽스처의 FEN 과 같은지**. 두 칸(fen · moves[])은
//      서로 독립한 자료라 이 대조는 자기 확인이 아니다.
//   ⑤ 시계가 **행마다** 실리는지 + `deadline = 차례 시작 + 차례쪽 남은 시간` 인지.
//   ⑥ 끝난 판의 사유·결과·승자를 엔진으로 **다시 판정**한다. ★ `timeout_insufficient`(FIDE 6.9)는 같은 깃발로
//      끝난 `timeout` 과 **쌍으로** 두어 둘이 갈리는 것을 잰다 — 합치면 사용자는 무승부를 패배로 읽는다.
//   ⑧ 로비의 관전 입구 id 가 관전 픽스처에 **닿는지**(오목에서 이게 어긋나 관전이 안 열렸다).
//   ⑪ 마지막으로 **갈림 자체**를 단언한다 — 기준선이 같은 입력이면 그 테스트는 영원히 초록이다.
//
// ── 닿는 길(데모 라우트) ──
//   games/chess/lobby                       기본 로비
//   games/chess/lobby/invites               신청 두 건(들어온 1 · 보낸 1)
//   games/chess/match                       내 판이 진행 중인 로비 → 바로 대국
//   games/chess/match/<match-id>            대국 변형 열셋(아래 `stateIDs`)
//   games/chess/watch/demo-chess-live|over  관전(진행 중 · 끝난 판)
//   games/chess/ranking                     순위(내가 목록 안)
//   games/chess/ranking/unlisted            순위(내가 목록 밖인데 내 순위는 보인다)
// 라우트 글자는 `-AingCheckDemoRoute` 값이고 `/` 를 `-` 로 바꾼 것이 장면 이름이다(`MobileDemo.environment`).
// 라우트 해석(`AingRoute`)과 화면은 이 파일의 소유가 아니다 — 체스 화면 작업자가 위 글자를 받아 가면 된다.
@Suite struct GamesChessFixtureContractTests {

    // MARK: - 재료

    static let index = MobileDemoFixtures.load()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase   // 서비스 디코더와 같은 설정
        return decoder
    }()

    static let me = MobileDemo.userID
    static let cloud = "d0000000-0000-4000-8000-0000000000b1"       // 구름빵
    static let choco = "d0000000-0000-4000-8000-0000000000b2"       // 초코칩
    static let mint = "d0000000-0000-4000-8000-0000000000b3"        // 민트별
    static let walnut = "d0000000-0000-4000-8000-0000000000b4"      // 호두과자
    static let barley = "d0000000-0000-4000-8000-0000000000b5"      // 보리차 — 0판 · 옛 버전
    static let moon = "d0000000-0000-4000-8000-0000000000b6"        // 달토끼
    static let candy = "d0000000-0000-4000-8000-0000000000b7"       // 솜사탕 — 근무 중인데 옛 버전

    static let stakes = [3, 5, 10]
    static let initialMs = 600_000
    static let incrementMs = 3_000
    static let graceMs = 2_000
    static let inviteTTL = 60
    /// `chess_watch_tail_seconds()` — 끝난 판은 이 꼬리 안에서만 보인다.
    static let watchTailMs = 180_000

    /// `chess_state` 변형의 match id — 이것이 그대로 바늘(`@…`)이고 데모 라우트의 꼬리다.
    static let stateIDs = [
        "demo-chess-my-turn", "demo-chess-their-turn", "demo-chess-incheck",
        "demo-chess-promo", "demo-chess-promoted",
        "demo-chess-mate-win", "demo-chess-mate-loss", "demo-chess-flagdraw", "demo-chess-flagloss",
        "demo-chess-drawoffer", "demo-chess-invite-in", "demo-chess-invite-out",
    ]
    static let watchIDs = ["demo-chess-live", "demo-chess-over"]

    /// 체스 데모 픽스처는 **정확히 이 열아홉 장**이다(대국 12 · 관전 2 · 로비 3 · 순위 2).
    /// 늘리거나 줄이는 것은 결정이므로 여기를 고쳐야 한다.
    static var requiredPaths: Set<String> {
        var paths: Set<String> = [
            "games/rpc.chess_lobby.json",
            "games/_games-chess-lobby-invites/rpc.chess_lobby.json",
            "games/_games-chess-match/rpc.chess_lobby.json",
            "games/rpc.chess_ranking.json",
            "games/_games-chess-ranking-unlisted/rpc.chess_ranking.json",
        ]
        for id in stateIDs { paths.insert("games/rpc.chess_state@\(id).json") }
        for id in watchIDs { paths.insert("games/rpc.chess_watch@\(id).json") }
        return paths
    }

    static var chessEntries: [MobileDemoFixtures.Entry] {
        index.entries.filter { $0.key.hasPrefix("rpc.chess_") }
    }

    static func entry(_ path: String) throws -> MobileDemoFixtures.Entry {
        try #require(chessEntries.first { $0.relativePath == path }, "픽스처 없음: \(path)")
    }

    static func raw(_ path: String) throws -> [String: Any] {
        let data = try entry(path).data
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], "\(path): JSON 객체가 아니다")
    }

    /// 설명용 `__` 키는 계약이 아니다(걷어낸다 — 안 걷으면 주석을 지워야 초록이 되는 거꾸로 된 테스트가 된다).
    static func keys(_ object: Any?) -> Set<String> {
        guard let dictionary = object as? [String: Any] else { return [] }
        return Set(dictionary.keys.filter { !$0.hasPrefix("__") })
    }

    static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

    static func request(rpc: String, matchID: String?) -> MobileStubRequest {
        let body = matchID.map { #"{"p_protocol":1,"p_match_id":"\#($0)","p_since_seq":0}"# } ?? #"{"p_protocol":1}"#
        return MobileStubRequest(
            method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)",
            query: "", headers: [:], bodyText: body)
    }

    /// 판을 싣는 픽스처 한 장(상태 열하나 + 관전 둘).
    struct Board {
        let path: String
        let raw: [String: Any]
        let match: [String: Any]
        let moves: [[String: Any]]
        let isWatch: Bool
        let position: ChessPosition
        var status: String { match["status"] as? String ?? "?" }
        var isActive: Bool { status == "active" }
    }

    static func boards() throws -> [Board] {
        var out: [Board] = []
        for path in requiredPaths.sorted() where path.contains("chess_state@") || path.contains("chess_watch@") {
            let object = try raw(path)
            let match = try #require(object["match"] as? [String: Any], "\(path): match 없음")
            let moves = try #require(object["moves"] as? [[String: Any]], "\(path): moves 없음")
            let fen = try #require(match["fen"] as? String, "\(path): fen 없음")
            let position = try #require(ChessPosition(fen: fen), "\(path): FEN 을 못 읽는다 — \(fen)")
            out.append(Board(path: path, raw: object, match: match, moves: moves,
                             isWatch: path.contains("chess_watch@"), position: position))
        }
        #expect(out.count == stateIDs.count + watchIDs.count)
        return out
    }

    // MARK: - ① 픽스처 집합과 데모 라우팅(요청 → **그 장**)

    @Test("픽스처가 번들에 다 있고, 데모 응답기가 요청마다 그 장을 고른다(접두사가 겹치는 짝도 갈린다)")
    func theSetIsBundledAndTheDemoResponderPicksTheRightFile() throws {
        // 없으면: 파일을 만들어도 리소스에 안 들어가거나(`.copy("Demo/Fixtures")` 밖에 두면 그렇다) 바늘이 서로를
        // 가려도 모른다. 특히 `demo-chess-mate-win` 은 `demo-chess-mate-loss` 의 **접두사가 아니지만**
        // 길이 우선 규칙이 깨지면 한쪽이 다른 쪽을 삼킨다 — 그 순간 '이겼다' 화면에서 패배 문구가 난다.
        #expect(Set(Self.chessEntries.map(\.relativePath)) == Self.requiredPaths)
        #expect(Self.index.duplicateKeys.isEmpty, "같은 장면·키·바늘이 둘: \(Self.index.duplicateKeys)")

        for id in Self.stateIDs {
            let picked = Self.index.entry(for: Self.request(rpc: "chess_state", matchID: id),
                                          scenario: "games-chess-lobby")
            #expect(picked?.relativePath == "games/rpc.chess_state@\(id).json", "\(id) 가 엉뚱한 장에 걸렸다")
        }
        for id in Self.watchIDs {
            let picked = Self.index.entry(for: Self.request(rpc: "chess_watch", matchID: id),
                                          scenario: "games-chess-watch-\(id)")
            #expect(picked?.relativePath == "games/rpc.chess_watch@\(id).json", "\(id) 관전이 엉뚱한 장에 걸렸다")
        }
        // ★ 접두사가 겹치는 짝(promo ⊂ promoted)은 **긴 바늘이 먼저** 걸려야 한다.
        // 이 규칙이 깨지면 `games/chess/match/demo-chess-promoted` 가 승격 직전 판을 열고, 기보에 승격 수가
        // 든 유일한 판이 데모에서 통째로 사라진다(그러고도 화면은 그럴듯하게 돈다 — 그게 가장 안 잡히는 꼴이다).
        #expect(Self.index.entry(for: Self.request(rpc: "chess_state", matchID: "demo-chess-promo"),
                                 scenario: "games-chess-lobby")?.needle == "demo-chess-promo")
        #expect(Self.index.entry(for: Self.request(rpc: "chess_state", matchID: "demo-chess-promoted"),
                                 scenario: "games-chess-lobby")?.needle == "demo-chess-promoted")

        // 장면 파일은 바깥 파일을 **덮는다**. 장면이 안 걸리면 기본 로비가 나와 신청·내 판이 화면에서 통째로 사라진다.
        let lobbyRequest = Self.request(rpc: "chess_lobby", matchID: nil)
        let rankingRequest = Self.request(rpc: "chess_ranking", matchID: nil)
        #expect(Self.index.entry(for: lobbyRequest, scenario: "games-chess-lobby")?.relativePath
                == "games/rpc.chess_lobby.json")
        #expect(Self.index.entry(for: lobbyRequest, scenario: "now")?.relativePath
                == "games/rpc.chess_lobby.json")
        #expect(Self.index.entry(for: lobbyRequest, scenario: "games-chess-lobby-invites")?.relativePath
                == "games/_games-chess-lobby-invites/rpc.chess_lobby.json")
        #expect(Self.index.entry(for: lobbyRequest, scenario: "games-chess-match")?.relativePath
                == "games/_games-chess-match/rpc.chess_lobby.json")
        #expect(Self.index.entry(for: rankingRequest, scenario: "games-chess-ranking")?.relativePath
                == "games/rpc.chess_ranking.json")
        #expect(Self.index.entry(for: rankingRequest, scenario: "games-chess-ranking-unlisted")?.relativePath
                == "games/_games-chess-ranking-unlisted/rpc.chess_ranking.json")

        // 그리고 실제 응답이 200 이어야 한다(금지 호출로 403 이 되거나 `__status` 로 오류를 흘리면 안 된다).
        let response = Self.index.response(for: lobbyRequest, scenario: "games-chess-lobby")
        #expect(response.status == 200)
        #expect(response.failure == nil)
        #expect(MobileForbiddenCalls.violation(lobbyRequest) == nil)
    }

    // MARK: - ② 봉투 키 집합 + 와이어 타입 디코드

    @Test("봉투가 서버 계약의 정확한 키 집합이고 ChessWire 타입으로 디코드되며, state 중복 봉투가 최상위와 같다")
    func envelopesMatchTheServerKeySetAndDecodeAsWireTypes() throws {
        // 없으면: 키가 하나 빠져도(= 그 자리에서 화면이 빈다) 아무도 모른다. 늘기만 하면 디코더는 무사하지만
        // 줄면 조용히 빈다 — 그래서 **정확 집합**으로 잰다. 집합은 맥 캡처 79장이 박아 둔 것과 같은 표다.
        let stateKeys: Set<String> = ["in_check", "legal_moves", "match", "moves", "my_color",
                                      "opponent", "ruby_balance", "server_now_ms", "state", "status"]
        let matchKeys: Set<String> = ["black", "black_grace_ms", "black_ms_left", "challenger",
                                      "deadline_ms", "draw_offer_by", "end_reason", "fen", "finished_ms",
                                      "id", "increment_ms", "invite_expires_ms", "opponent", "ply_count",
                                      "result", "stake", "started_ms", "status", "turn", "turn_started_ms",
                                      "white", "white_grace_ms", "white_ms_left", "winner"]
        let moveKeys: Set<String> = ["color", "fen", "from", "ms_left", "ms_spent", "promo", "san", "seq", "to"]
        let peerKeys: Set<String> = ["avatar_url", "center", "character", "display_name", "user_id"]
        let watchKeys: Set<String> = ["black_user", "in_check", "match", "moves", "server_now_ms",
                                      "status", "white_user"]

        for board in try Self.boards() {
            if board.isWatch {
                #expect(Self.keys(board.raw) == watchKeys, "\(board.path): 관전 최상위 키")
                // 관전은 **판만**이다 — my_color·legal_moves·ruby_balance·opponent·state 가 없는 것이 계약이다.
                // (있으면 참가자 적용 경로로 흘러들어 대국 화면이 설 수 있다 — ChessWatchResponse 머리말.)
                #expect(Self.keys(board.match) == matchKeys.subtracting(["invite_expires_ms"]),
                        "\(board.path): 관전 match 키")
                let decoded = try Self.decoder.decode(ChessWatchResponse.self, from: Self.entry(board.path).data)
                #expect(decoded.status == .ok)
                #expect(decoded.match?.id == board.match["id"] as? String)
                #expect(decoded.whiteUser?.userId == board.match["white"] as? String)
                #expect(decoded.blackUser?.userId == board.match["black"] as? String)
            } else {
                #expect(Self.keys(board.raw) == stateKeys, "\(board.path): 상태 최상위 키")
                #expect(Self.keys(board.match) == matchKeys, "\(board.path): match 키")
                #expect(Self.keys(board.raw["opponent"]) == peerKeys, "\(board.path): opponent 키")
                // state 중복 봉투 = 최상위에서 status·state 를 뺀 것과 **같은 내용**이어야 한다
                // (두 디코더가 갈리면 한쪽만 고친 날 화면이 서로 다른 판을 그린다).
                let nested = try #require(board.raw["state"] as? [String: Any], "\(board.path): state 없음")
                #expect(Self.keys(nested) == stateKeys.subtracting(["status", "state"]), "\(board.path): state 키")
                for key in Self.keys(nested) {
                    let lhs = (board.raw[key] as? NSObject) ?? NSNull()
                    let rhs = (nested[key] as? NSObject) ?? NSNull()
                    #expect(lhs == rhs, "\(board.path): state.\(key) 가 최상위와 다르다")
                }
                let decoded = try Self.decoder.decode(ChessStateResponse.self, from: Self.entry(board.path).data)
                #expect(decoded.status == .ok)
                #expect(decoded.state.match?.id == board.match["id"] as? String)
                #expect(decoded.state.myColor == board.raw["my_color"] as? String)
                // 쓰기 RPC 공용 디코더로도 같은 판이 읽혀야 한다(최상위에 match 가 있으므로 payload 가 선다).
                let asAction = try Self.decoder.decode(ChessActionResponse.self, from: Self.entry(board.path).data)
                #expect(asAction.state?.match?.fen == board.match["fen"] as? String)
            }
            for row in board.moves {
                #expect(Self.keys(row) == moveKeys, "\(board.path): moves[] 키")
            }
        }
    }

    // MARK: - ③ ★ 판: FEN 하나에서 엔진으로 다시 계산해 서버 값과 맞춘다

    @Test("★ match.fen 을 엔진으로 읽으면 turn·in_check·legal_moves·ply_count 가 서버 값과 같다")
    func boardsAgreeWithTheSwiftEngine() throws {
        // ★ 체스에서 가장 값진 계약이다. 서버 값(turn·in_check·legal_moves)을 **쓰지 않고** FEN 하나에서 전부
        // 다시 계산해 맞춘다. 없으면: 합법 수 목록을 다른 국면에서 만들어도 아무도 모르고, 화면에는
        // "둘 수 있다고 보여 준 수가 거절되는" 모양으로 나온다 — PvP 화면은 이 배열만 쓴다(판정 주인은 서버다).
        for board in try Self.boards() {
            let path = board.path
            let position = board.position

            // (a) 차례는 FEN 에서 파생한다(따로 저장하면 갈린다).
            #expect(board.match["turn"] as? String == position.sideToMove.rawValue, "\(path): turn")

            // (b) 체크는 **진행 중일 때만** 싣는다.
            if board.isActive {
                #expect(board.raw["in_check"] as? Bool == ChessRules.isInCheck(position), "\(path): in_check")
            } else {
                #expect(board.raw["in_check"] is NSNull, "\(path): 끝난/대기 판인데 in_check 가 있다")
            }

            // (c) ★ 합법 수 — 내 차례일 때만, 그리고 **엔진 목록과 정확히 같아야** 한다.
            if board.isWatch {
                #expect(board.raw["legal_moves"] == nil, "\(path): 관전에 legal_moves 가 있다")
            } else {
                let myColor = try #require(board.raw["my_color"] as? String, "\(path): my_color")
                let myTurn = board.isActive && myColor == position.sideToMove.rawValue
                if myTurn {
                    let served = try #require(board.raw["legal_moves"] as? [String], "\(path): 내 차례인데 legal_moves 가 없다")
                    let engine = ChessRules.legalMoves(in: position).map(\.uci).sorted()
                    #expect(served == engine, "\(path): 합법 수가 엔진과 다르다")
                    #expect(!served.isEmpty, "\(path): 내 차례인데 둘 수가 없다")
                    // UCI 사전순이라는 계약도 결과로 잰다(화면이 순서를 믿고 묶는 자리가 있다).
                    #expect(served == served.sorted(), "\(path): legal_moves 가 사전순이 아니다")
                } else {
                    #expect(board.raw["legal_moves"] is NSNull,
                            "\(path): 내 차례가 아닌데 legal_moves 가 있다(화면이 못 두는 수를 보여 준다)")
                }

                // (d) 내 색·상대가 판의 두 사람과 맞물린다.
                let white = try #require(board.match["white"] as? String)
                let black = try #require(board.match["black"] as? String)
                #expect(myColor == (white == Self.me ? "white" : "black"), "\(path): my_color")
                #expect([white, black].contains(Self.me), "\(path): 내가 참가자가 아니다")
                let peer = white == Self.me ? black : white
                #expect((board.raw["opponent"] as? [String: Any])?["user_id"] as? String == peer, "\(path): opponent")
            }

            // (e) 수 번호 = 기보 길이. 데모는 `p_since_seq = 0` 으로 부르므로 **처음부터 전부** 온다.
            #expect(Self.int(board.match["ply_count"]) == board.moves.count, "\(path): ply_count ↔ moves 길이")
            #expect(board.moves.map { Self.int($0["seq"]) } == (1...max(board.moves.count, 1)).prefix(board.moves.count).map { $0 },
                    "\(path): seq 가 1부터 연속이 아니다")

            // (f) 두 사람·판돈·가산.
            let pair = Set([board.match["white"] as? String, board.match["black"] as? String].compactMap { $0 })
            let invite = Set([board.match["challenger"] as? String, board.match["opponent"] as? String].compactMap { $0 })
            #expect(pair.count == 2, "\(path): 흑백이 같은 사람")
            #expect(pair == invite, "\(path): challenger/opponent 가 흑백과 다른 사람")
            #expect(Self.stakes.contains(Self.int(board.match["stake"]) ?? -1), "\(path): 판돈이 집합 밖")
            #expect(Self.int(board.match["increment_ms"]) == Self.incrementMs, "\(path): 가산")
            #expect(Self.int(board.raw["server_now_ms"])
                    == Int(MobileClock.demoInstant.timeIntervalSince1970 * 1000), "\(path): 데모 시계")
        }
    }

    // MARK: - ④ 기보: 표준 시작 국면부터 재생해 FEN 과 맞춘다

    @Test("★ 기보(SAN)를 처음부터 재생하면 행마다의 fen 과 최종 match.fen 이 그대로 나온다")
    func moveLinesReplayIntoTheDeclaredFEN() throws {
        // 없으면: `fen` 과 `moves[]` 가 각각 그럴듯해도 **다른 판**일 수 있다. 화면 기보를 누르면 판이 튀고,
        // 되감기(수 넘기기)가 통째로 어긋난다. 두 칸은 독립한 자료이므로 이 대조는 자기 확인이 아니다.
        // SAN 은 **양방향**으로 잰다: 엔진이 같은 글자를 만들어 내는가 + 그 글자가 같은 수로 되읽히는가.
        var replayed = 0
        for board in try Self.boards() {
            var position = ChessPosition.standard
            for row in board.moves {
                let seq = Self.int(row["seq"]) ?? -1
                let label = "\(board.path) seq \(seq)"
                let san = try #require(row["san"] as? String, "\(label): san")
                let move = try #require(ChessRules.move(san: san, in: position), "\(label): \(san) 이 불법/모호하다")
                // 칸 번호는 rank*8+file 이고 `ChessSquare.index` 와 같은 눈금이다.
                #expect(move.from.index == Self.int(row["from"]), "\(label): from")
                #expect(move.to.index == Self.int(row["to"]), "\(label): to")
                let promo = move.promotion.map { String($0.fenLetter).lowercased() }
                #expect(promo == row["promo"] as? String, "\(label): promo")
                #expect(ChessRules.san(for: move, in: position) == san, "\(label): 엔진이 만든 SAN 이 다르다")
                // 차례 색도 기보가 말하는 색과 같아야 한다(한 수 밀리면 전부 뒤집힌다).
                #expect(position.sideToMove.rawValue == row["color"] as? String, "\(label): color")
                position = try #require(ChessRules.apply(move, to: position), "\(label): 적용 실패")
                #expect(position.fen == row["fen"] as? String, "\(label): 그 수 뒤의 fen")
                replayed += 1
            }
            if board.moves.isEmpty {
                // 신청 대기 판은 표준 시작 국면 그대로여야 한다(수가 없는데 판이 움직여 있으면 거짓이다).
                #expect(board.match["fen"] as? String == ChessPosition.standard.fen, "\(board.path): 수 0인데 판이 다르다")
            }
            #expect(position.fen == board.match["fen"] as? String, "\(board.path): 재생한 최종 FEN 이 match.fen 과 다르다")
        }
        #expect(replayed >= 100, "재생한 수가 \(replayed)개뿐 — 긴 판이 사라졌으면 재생 대조가 공짜다")
    }

    // MARK: - ⑤ 시계: 행마다 · 쪽마다

    @Test("시계가 행마다·쪽마다 실리고, deadline = 차례 시작 + 차례쪽 남은 시간이다")
    func clocksAreCarriedPerRowAndPerSide() throws {
        // 없으면: 전역 `grace_ms` 만 쓰는 화면이 최대 2초를 거짓으로 그리고(쪽마다 다를 수 있다),
        // 마감을 내 시계로 재면 상대 차례에 **내 시간이 깎이는** 꼴이 된다.
        for board in try Self.boards() {
            let path = board.path
            #expect(Self.int(board.match["white_grace_ms"]) == Self.graceMs, "\(path): white_grace_ms")
            #expect(Self.int(board.match["black_grace_ms"]) == Self.graceMs, "\(path): black_grace_ms")

            // (a) 행의 ms_left 는 "직전 그 쪽의 남은 시간 − 쓴 시간 + 가산" 이다.
            var left: [String: Int] = ["white": Self.initialMs, "black": Self.initialMs]
            for row in board.moves {
                let color = try #require(row["color"] as? String)
                let spent = try #require(Self.int(row["ms_spent"]), "\(path): ms_spent")
                let shown = try #require(Self.int(row["ms_left"]), "\(path): ms_left")
                #expect(spent > 0, "\(path) seq \(Self.int(row["seq"]) ?? -1): 쓴 시간이 0 이하")
                left[color] = left[color]! - spent + Self.incrementMs
                #expect(shown == left[color]!, "\(path) seq \(Self.int(row["seq"]) ?? -1): ms_left 산식")
                #expect(shown > 0, "\(path): 아직 도는 판인데 행의 시계가 0 이하")
            }
            // (b) match 의 쪽별 시계 = 그 쪽 **마지막 수 뒤**의 값(수가 없으면 시작값).
            #expect(Self.int(board.match["white_ms_left"]) == left["white"], "\(path): white_ms_left")
            #expect(Self.int(board.match["black_ms_left"]) == left["black"], "\(path): black_ms_left")

            // (c) 마감은 차례쪽으로 잰다. 진행 중이 아니면 null 이다.
            let turn = try #require(board.match["turn"] as? String)
            if board.isActive {
                let started = try #require(Self.int(board.match["turn_started_ms"]), "\(path): turn_started_ms")
                #expect(Self.int(board.match["deadline_ms"]) == started + left[turn]!, "\(path): deadline_ms")
                #expect(board.match["finished_ms"] is NSNull, "\(path): 도는 판에 finished_ms")
                #expect(board.match["result"] is NSNull && board.match["end_reason"] is NSNull
                        && board.match["winner"] is NSNull, "\(path): 도는 판에 결과")
            } else {
                #expect(board.match["deadline_ms"] is NSNull, "\(path): 안 도는 판에 deadline_ms")
            }
            if board.status == "pending" {
                #expect(board.match["started_ms"] is NSNull && board.match["turn_started_ms"] is NSNull,
                        "\(path): 대기 판에 시작 시각")
                #expect(Self.int(board.match["invite_expires_ms"])
                        .map { $0 > Self.int(board.raw["server_now_ms"])! } == true,
                        "\(path): 신청이 이미 만료됐다(카운트다운이 음수로 돈다)")
                #expect(Self.int(board.match["invite_expires_ms"])!
                        <= Self.int(board.raw["server_now_ms"])! + Self.inviteTTL * 1_000,
                        "\(path): 만료가 TTL 보다 멀다")
            }
        }
    }

    // MARK: - ⑥ ★ 끝난 판: 엔진으로 다시 판정한다 (FIDE 6.9 포함)

    @Test("★ 끝난 판의 사유·결과·승자가 서로 맞물리고, 외통과 FIDE 6.9 를 엔진으로 다시 판정해도 같다")
    func finishedMatchesRejudgeToTheSameResult() throws {
        // ★ 돈이 갈리는 자리다. 없으면: '외통 무승부' 나 '무승부인데 승자 있음' 같은 모양이 통과하고,
        // 무엇보다 `timeout` 과 `timeout_insufficient` 를 한 문구로 합친 화면이 초록으로 남는다 —
        // 그 순간 **무승부로 끝난 사용자가 자기가 졌다고 읽는다.**
        var seenReasons: Set<String> = []
        for board in try Self.boards() where board.status == "finished" {
            let path = board.path
            let reasonText = try #require(board.match["end_reason"] as? String, "\(path): end_reason")
            let reason = try #require(ChessEndReason(rawValue: reasonText), "\(path): 모르는 사유 \(reasonText)")
            let result = try #require(board.match["result"] as? String, "\(path): result")
            seenReasons.insert(reasonText)

            // (a) "무승부 ⟺ 무승부 사유" 는 iff 다(한쪽만 보면 '외통 무승부' 가 통과한다).
            #expect(reason.isDraw == (result == "draw"), "\(path): \(reasonText) ↔ \(result)")
            if reason.isDraw {
                #expect(board.match["winner"] is NSNull, "\(path): 무승부에 승자가 있다")
            } else {
                let expected = result == "white_win" ? board.match["white"] : board.match["black"]
                #expect(board.match["winner"] as? String == expected as? String, "\(path): 승자 ↔ result")
            }
            #expect(["white_win", "black_win", "draw"].contains(result), "\(path): 모르는 result")
            #expect(Self.int(board.match["finished_ms"])! > Self.int(board.match["turn_started_ms"])!,
                    "\(path): 끝난 시각이 차례 시작보다 앞이다")

            switch reason {
            case .checkmate:
                // 외통은 **판에서 다시 판정한다** — 서버 글자를 믿지 않는다.
                let winner: ChessColor = result == "white_win" ? .white : .black
                #expect(ChessRules.outcome(position: board.position) == .checkmate(winner: winner),
                        "\(path): 판이 외통이 아니거나 승자가 다르다")
            case .timeout, .timeoutInsufficient:
                // 깃발은 **차례인 쪽**에서 떨어진다. 지는지 무승부인지는 "시간이 남은 쪽에게 메이트 재료가 있는가" 다.
                let flagged = try #require(ChessColor(rawValue: board.match["turn"] as! String))
                let left = Self.int(board.match[flagged == .white ? "white_ms_left" : "black_ms_left"])!
                let grace = Self.int(board.match[flagged == .white ? "white_grace_ms" : "black_grace_ms"])!
                let turnStarted = Self.int(board.match["turn_started_ms"])!
                #expect(turnStarted + left + grace < Self.int(board.match["finished_ms"])!,
                        "\(path): 유예까지 더해도 깃발이 안 떨어졌는데 시간패다")
                // 판 규칙으로는 **안 끝난** 판이어야 한다 — 그래야 끝낸 것이 시계라는 말이 선다.
                #expect(ChessRules.outcome(position: board.position) == nil, "\(path): 시계가 아니라 판이 끝냈다")
                let opponentHasMate = !ChessRules.hasNoMatingMaterial(board.position, color: flagged.opponent)
                if reason == .timeoutInsufficient {
                    // ★ FIDE 6.9 — 깃발은 떨어졌는데 상대에게 메이트 재료가 없어 **무승부**.
                    #expect(!opponentHasMate, "\(path): 상대에게 메이트 재료가 있는데 6.9 무승부다")
                    #expect(result == "draw" && board.match["winner"] is NSNull)
                    // 사국(FIDE 5.2.2)이 아니어야 한다 — 사국이면 깃발과 무관하게 무승부라 6.9 를 증명하지 못한다.
                    #expect(!ChessRules.hasInsufficientMaterial(board.position),
                            "\(path): 사국이라 6.9 가 유일한 사유가 아니다")
                } else {
                    #expect(opponentHasMate, "\(path): 상대에게 메이트 재료가 없는데 시간패(패배)다 — 6.9 로 무승부여야 한다")
                    #expect(result != "draw")
                }
            default:
                break
            }
        }
        // ★ 기준선이 갈려야 한다: **같은 깃발**로 끝난 판이 둘 있고 하나는 무승부, 하나는 패배다.
        // (쌍이 없으면 "둘이 갈린다" 를 재는 단언이 전부 공짜다 — 저장소 메모 '비교 기준선이 달라야 한다'.)
        #expect(seenReasons.isSuperset(of: ["checkmate", "timeout", "timeout_insufficient"]),
                "끝난 사유가 \(seenReasons.sorted()) — 깃발 두 갈래와 외통이 다 있어야 한다")
        let draw = try Self.raw("games/rpc.chess_state@demo-chess-flagdraw.json")
        let loss = try Self.raw("games/rpc.chess_state@demo-chess-flagloss.json")
        let drawMatch = draw["match"] as! [String: Any]
        let lossMatch = loss["match"] as! [String: Any]
        #expect(drawMatch["turn"] as? String == lossMatch["turn"] as? String, "두 깃발이 다른 쪽에서 떨어졌다")
        #expect(Self.int(drawMatch["white_ms_left"]) == Self.int(lossMatch["white_ms_left"]),
                "두 깃발의 남은 시간이 달라 '재료만 다르다' 가 아니다")
        #expect(drawMatch["result"] as? String != lossMatch["result"] as? String, "두 깃발의 결과가 같다")
        #expect(drawMatch["fen"] as? String != lossMatch["fen"] as? String)
    }

    // MARK: - ⑦ 승격: 도착 칸마다 합법 수 넷

    @Test("승격 픽스처는 도착 칸마다 합법 수가 정확히 넷(q·r·b·n)이다 — 폰이 승격 2단을 그릴 수 있다")
    func promotionOffersExactlyFourMovesPerTargetSquare() throws {
        // 없으면: 화면이 '칸 고르기 → 말 고르기' 2단을 그릴 재료가 없고, 넷 중 하나만 실린 목록으로
        // 만들면 "퀸 말고는 못 고른다" 가 데모에서 정상으로 보인다.
        let object = try Self.raw("games/rpc.chess_state@demo-chess-promo.json")
        let match = try #require(object["match"] as? [String: Any])
        let position = try #require(ChessPosition(fen: match["fen"] as! String))
        let served = try #require(object["legal_moves"] as? [String])
        let moves = try #require(served.map { ChessMove(uci: $0) } as? [ChessMove], "UCI 를 못 읽는다")

        let byTarget = Dictionary(grouping: moves, by: \.to)
        let promotionTargets = byTarget.filter { $0.value.contains { $0.promotion != nil } }
        #expect(!promotionTargets.isEmpty, "승격 수가 없다")
        for (square, group) in promotionTargets {
            #expect(group.count == 4, "\(square.notation): 승격 도착 칸의 합법 수가 \(group.count)개")
            #expect(group.allSatisfy { $0.promotion != nil }, "\(square.notation): 승격 아닌 수가 섞였다")
            #expect(Set(group.compactMap(\.promotion)) == Set(ChessPieceKind.promotionChoices),
                    "\(square.notation): 고를 수 있는 말이 네 가지가 아니다")
        }
        // 엔진이 같은 목록을 내는지도 되묻는다(서버 목록이 권위지만 둘이 갈리면 그 자리가 결함이다).
        #expect(served == ChessRules.legalMoves(in: position).map(\.uci).sorted())
        // 그리고 승격이 **없는** 판과 대조한다 — 없으면 "넷" 이 어느 판에서나 참인 말이 된다.
        let plain = try Self.raw("games/rpc.chess_state@demo-chess-my-turn.json")
        let plainMoves = try #require(plain["legal_moves"] as? [String]).compactMap { ChessMove(uci: $0) }
        #expect(plainMoves.allSatisfy { $0.promotion == nil }, "대조군에 승격 수가 있다")
    }

    // MARK: - ⑧ 로비: 상대 상태 네 갈래 + 관전 입구가 **닿는가**

    @Test("★ 로비가 상대 상태 네 갈래를 덮고, 관전 입구 id 가 관전 픽스처에 닿고, 신청 id 가 대기 판에 닿는다")
    func lobbyCoversEveryOpponentStateAndItsEntriesResolve() throws {
        // ★ 오목에서 이게 어긋나 관전이 안 열렸다: 로비 카드가 가리키는 id 에 픽스처가 없어 3회 실패 뒤 로비로
        // 튕겼고, 그 상태가 0.3.41 의 기준선이었다(관전 화면에 검증 수단이 0이었다). 같은 사고를 여기서 막는다.
        let lobby = try Self.raw("games/rpc.chess_lobby.json")
        let decoded = try Self.decoder.decode(ChessLobbyResponse.self, from: Self.entry("games/rpc.chess_lobby.json").data)
        #expect(decoded.status == .ok)

        // (a) 서버 상수는 앱이 베끼지 않는다 — 로비가 알려 준다.
        #expect(decoded.stakes == Self.stakes)
        #expect(decoded.initialMs == Self.initialMs)
        #expect(decoded.incrementMs == Self.incrementMs)
        #expect(decoded.graceMs == Self.graceMs)
        #expect(decoded.inviteTtlSeconds == Self.inviteTTL)

        // (b) 내 전적·루비. 지갑은 me 와 최상위 두 곳에 같은 값으로 온다.
        let mine = try #require(decoded.me)
        #expect(mine.wins == 5 && mine.losses == 3 && mine.draws == 2)
        #expect(mine.rubyBalance == 42 && decoded.rubyBalance == 42)

        // (c) 상대 목록이 네 갈래를 덮는다. **값으로** 잰다 — 사람마다 어느 상태인지 여기에 적어 둔다.
        let users = try #require(decoded.users)
        func user(_ id: String) throws -> ChessUserRow { try #require(users.first { $0.userId == id }, "로비에 없다: \(id)") }
        #expect(try user(Self.cloud).isWorking == true)                                   // ① 근무 중
        #expect(try user(Self.cloud).capable == true && user(Self.cloud).inMatch == false)
        #expect(try user(Self.choco).isWorking == false)                                  // ② 근무 안 함
        #expect(try user(Self.choco).capable == true && user(Self.choco).inMatch == false)
        #expect(try user(Self.mint).inMatch == true && user(Self.moon).inMatch == true)    // ③ 대국 중 둘
        #expect(try user(Self.barley).capable == false)                                   // ④ 옛 버전
        #expect(try user(Self.candy).capable == false && user(Self.candy).isWorking == true)  // 근무 중 + 옛 버전
        // capable 과 is_working 이 **다른 축**이라는 것이 네 조합으로 서야 한다.
        #expect(Set(users.map { [$0.capable, $0.inMatch] }).count >= 3, "capable/in_match 조합이 한 가지뿐")
        #expect(!users.contains { $0.userId == Self.me }, "users[] 에 내가 있다(서버는 호출자를 뺀다)")
        #expect(users.allSatisfy { $0.displayName?.isEmpty == false }, "이름이 빈 줄이 있다")

        // (d) ★ 관전 입구: 카드의 id·판돈·시작 시각·두 사람이 관전 픽스처와 **같아야** 한다.
        let cards = try #require(lobby["matches"] as? [[String: Any]])
        #expect(!cards.isEmpty, "관전 입구가 없으면 관전 화면에 닿는 길이 없다")
        for card in cards {
            #expect(Self.keys(card) == ["a", "b", "match_id", "stake", "started_ms"], "로비 카드 키")
            // 판 내용(fen·ply_count)이 없는 것이 계약이다 — 있으면 제3자가 판을 들여다본다.
            #expect(card["fen"] == nil && card["ply_count"] == nil, "로비 카드에 판이 실렸다")
            let id = try #require(card["match_id"] as? String)
            let watch = try Self.raw("games/rpc.chess_watch@\(id).json")
            let watchMatch = try #require(watch["match"] as? [String: Any], "\(id): 관전 픽스처에 못 닿는다")
            #expect(watchMatch["status"] as? String == "active", "\(id): 로비 카드가 도는 판이 아니다")
            #expect(Self.int(watchMatch["stake"]) == Self.int(card["stake"]), "\(id): 판돈")
            #expect(Self.int(watchMatch["started_ms"]) == Self.int(card["started_ms"]), "\(id): 시작 시각")
            // a/b 는 **uuid 오름차순**이고 색이 아니다 — 색은 관전 응답의 white_user/black_user 로만 안다.
            let a = try #require((card["a"] as? [String: Any])?["user_id"] as? String)
            let b = try #require((card["b"] as? [String: Any])?["user_id"] as? String)
            #expect(a < b, "\(id): a/b 가 uuid 오름차순이 아니다")
            let sides = Set([watchMatch["white"] as? String, watchMatch["black"] as? String].compactMap { $0 })
            #expect(sides == Set([a, b]), "\(id): 카드의 두 사람이 판의 두 사람과 다르다")
            #expect(Self.keys(card["a"]) == ["avatar_url", "center", "character", "display_name", "user_id"])
        }

        // (e) 기본 로비는 신청·내 판이 **없는** 상태다(변형과 갈려야 한다).
        #expect(mine.activeMatchId == nil && mine.incomingMatchId == nil && mine.outgoingMatchId == nil)

        // (f) ★ 신청 변형: 두 id 가 **대기 판**에 닿고 그 판의 보낸 쪽/받은 쪽이 뒤집혀 있다.
        let invites = try Self.decoder.decode(
            ChessLobbyResponse.self,
            from: Self.entry("games/_games-chess-lobby-invites/rpc.chess_lobby.json").data)
        let inviteMe = try #require(invites.me)
        let incoming = try #require(inviteMe.incomingMatchId, "들어온 신청이 없다")
        let outgoing = try #require(inviteMe.outgoingMatchId, "보낸 신청이 없다")
        #expect(inviteMe.activeMatchId == nil, "신청과 진행 중 판이 함께 있다")
        for (id, challengerIsMe) in [(incoming, false), (outgoing, true)] {
            let state = try Self.raw("games/rpc.chess_state@\(id).json")
            let match = try #require(state["match"] as? [String: Any], "\(id): 신청 상태 픽스처에 못 닿는다")
            #expect(match["status"] as? String == "pending", "\(id): pending 이 아니다")
            #expect(Self.int(match["ply_count"]) == 0 && (state["moves"] as? [Any])?.isEmpty == true)
            #expect((match["challenger"] as? String == Self.me) == challengerIsMe,
                    "\(id): 신청을 보낸 쪽이 뒤집혔다(취소 버튼과 수락 버튼이 바뀐다)")
        }

        // (g) ★ 내 판 변형: active_match_id 가 가리키는 판이 **내가 참가자인 도는 판**이고, 상대가 in_match 다.
        let resume = try Self.decoder.decode(
            ChessLobbyResponse.self, from: Self.entry("games/_games-chess-match/rpc.chess_lobby.json").data)
        let resumeID = try #require(resume.me?.activeMatchId, "진행 중 판을 가리키지 않는다")
        let resumeState = try Self.raw("games/rpc.chess_state@\(resumeID).json")
        let resumeMatch = try #require(resumeState["match"] as? [String: Any], "\(resumeID): 못 닿는다")
        #expect(resumeMatch["status"] as? String == "active")
        let peerID = try #require([resumeMatch["white"] as? String, resumeMatch["black"] as? String]
            .compactMap { $0 }.first { $0 != Self.me })
        #expect(resume.users?.first { $0.userId == peerID }?.inMatch == true,
                "내 상대가 로비에서 in_match 가 아니다")
        // 기본 로비에서는 그 사람이 한가하다 — 두 장면이 갈리는 칸이 바로 거기다.
        #expect(decoded.users?.first { $0.userId == peerID }?.inMatch == false)
    }

    // MARK: - ⑨ 순위: 행이 전적을 다 싣고, rank 산식·0판 제외

    @Test("★ 순위 행이 승점과 승·패·무를 다 싣고, rank·정렬을 거꾸로 세도 맞고, 0판은 빠진다")
    func rankingRowsCarryTheWholeRecordAndTheRankFormula() throws {
        // ★ 사용자 지시: "정렬은 승점(승 − 패)이지만 **행에 승·패·무를 같이 띄워야** 한다. 승점만 보여주면 안 된다."
        // 화면이 승점만 그리면 데이터가 없는 것과 구별되지 않으므로, 먼저 **데이터가 다 차 있는지**를 못 박는다.
        // 없으면: rank 를 행 번호로 적어도(동점자 순위가 전부 틀린다) 모르고, 0판이 섞여 "0승 0패" 줄이 선다.
        struct Row { let rank: Int; let id: String; let wins: Int; let losses: Int; let draws: Int; let points: Int }
        let rowKeys: Set<String> = ["avatar_url", "center", "character", "display_name", "draws",
                                    "losses", "points", "rank", "user_id", "wins"]
        var sawTie = false
        var sawUnlistedMe = false

        for path in ["games/rpc.chess_ranking.json",
                     "games/_games-chess-ranking-unlisted/rpc.chess_ranking.json"] {
            let object = try Self.raw(path)
            #expect(Self.keys(object) == ["me", "record_since_ms", "rows", "server_now_ms", "status"], "\(path): 키")
            let decoded = try Self.decoder.decode(ChessRankingResponse.self, from: Self.entry(path).data)
            #expect(decoded.status == .ok)
            #expect(decoded.recordSinceMs != nil, "\(path): 전적 컷이 없으면 화면이 '언제부터' 를 못 말한다")

            let rawRows = try #require(object["rows"] as? [[String: Any]])
            #expect(!rawRows.isEmpty, "\(path): 행이 없으면 '0판 제외' 와 '전부 제외' 가 구별되지 않는다")
            var parsed: [Row] = []
            for row in rawRows {
                #expect(Self.keys(row) == rowKeys, "\(path): rows[] 키")
                // 한 칸이라도 null 이면 그 자리가 화면에서 빈다 — 그래서 **값이 있는지**부터 잰다.
                let entry = Row(
                    rank: try #require(Self.int(row["rank"]), "\(path): rank"),
                    id: try #require(row["user_id"] as? String, "\(path): user_id"),
                    wins: try #require(Self.int(row["wins"]), "\(path): wins"),
                    losses: try #require(Self.int(row["losses"]), "\(path): losses"),
                    draws: try #require(Self.int(row["draws"]), "\(path): draws"),
                    points: try #require(Self.int(row["points"]), "\(path): points"))
                #expect((row["display_name"] as? String)?.isEmpty == false, "\(path): 이름이 빈 줄")
                // 아바타는 사진이 없으면 캐릭터로 그린다 — 둘 다 없는 줄이 하나는 있어야(머리글자 대체) 하지만
                // **그 줄도 그릴 수 있어야** 하므로 이름이 있는지로 가른다(위 단언).
                parsed.append(entry)
            }
            for row in parsed {
                #expect(row.points == row.wins - row.losses, "\(path): 승점 = 승 − 패 (\(row.id))")
                #expect(row.wins + row.losses + row.draws > 0, "\(path): 0판이 순위표에 있다 (\(row.id))")
                // rank 는 "나보다 엄격히 나은 행 수 + 1" 이다 — 부호를 뒤집은 다른 식으로 센다.
                // (앞토막만 온 변형에서도 성립한다: 나보다 나은 사람은 전부 앞토막 안에 있다.)
                let better = parsed.filter {
                    ($0.points, $0.wins, $0.draws) > (row.points, row.wins, row.draws)
                }.count
                #expect(row.rank == better + 1, "\(path): \(row.id) 의 rank \(row.rank) ↔ 더 나은 행 \(better)")
            }
            // 정렬 축(승점 desc · 승 desc · 무 desc · user_id asc)을 거꾸로 정렬해 맞춘다. 재정렬 금지가 계약이다.
            let sorted = parsed.sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                if $0.wins != $1.wins { return $0.wins > $1.wins }
                if $0.draws != $1.draws { return $0.draws > $1.draws }
                return $0.id < $1.id
            }
            #expect(parsed.map(\.id) == sorted.map(\.id), "\(path): 정렬 축")
            if Set(parsed.map(\.rank)).count < parsed.count { sawTie = true }

            // 0판인 보리차는 순위에 없다 — **로비에는 있다**(그래서 '0판 제외' 가 '그 사람이 없다' 와 다르다).
            #expect(!parsed.contains { $0.id == Self.barley }, "\(path): 0판인 보리차가 순위표에 있다")

            // 내 순위: 목록 안이면 그 행과 숫자가 같아야 하고, 밖이어도 rank 가 보여야 한다.
            let myRank = try #require(decoded.me)
            let rank = try #require(myRank.rank, "\(path): 내 순위가 null 이다(전적이 있는데 순위 밖으로 보인다)")
            #expect(myRank.points == (myRank.wins ?? 0) - (myRank.losses ?? 0), "\(path): 내 승점")
            if let row = parsed.first(where: { $0.id == Self.me }) {
                #expect(row.rank == rank && row.wins == myRank.wins
                        && row.losses == myRank.losses && row.draws == myRank.draws, "\(path): 내 행 ↔ me 가 다르다")
            } else {
                sawUnlistedMe = true
                #expect(rank > parsed.count, "\(path): 목록 밖인데 순위가 목록 안쪽 숫자다")
                #expect(parsed.allSatisfy { $0.points >= myRank.points! },
                        "\(path): 목록 밖인데 목록 안보다 승점이 높다")
            }
            // 로비 me 와 순위 me 가 같은 전적을 말해야 한다(두 화면이 다른 숫자를 띄우면 어느 쪽이 참인지 모른다).
            let lobbyMe = try #require(try Self.decoder.decode(
                ChessLobbyResponse.self, from: Self.entry("games/rpc.chess_lobby.json").data).me)
            #expect([lobbyMe.wins, lobbyMe.losses, lobbyMe.draws] == [myRank.wins, myRank.losses, myRank.draws],
                    "\(path): 로비 전적 ↔ 순위 전적")
        }
        // ★ 기준선: 두 변형이 **갈려야** 한다 — 동률 한 쌍과 '목록 밖인 나' 가 각각 한 번은 있어야
        // rank 산식과 내 순위 줄을 재는 단언이 공짜가 아니다.
        #expect(sawTie, "동률이 한 번도 없으면 rank 산식이 행 번호와 구별되지 않는다")
        #expect(sawUnlistedMe, "내가 목록 밖인 변형이 없으면 '내 순위 줄' 을 재지 못한다")
    }

    // MARK: - ⑩ 관전: 판만 · 끝난 판은 꼬리 안

    @Test("관전은 판만 싣고(채팅·관전자 수 없음), 끝난 관전 판은 180초 꼬리 안이다")
    func watchIsBoardOnlyAndTheFinishedOneSitsInsideTheTail() throws {
        // 없으면: 관전 응답을 참가자 적용 경로로 흘려보내 대국 화면이 서거나(my_color 가 없다),
        // 오목에서 그랬듯 관전 화면이 있는 줄 알면서 꼬리 밖 판만 가리켜 **열어 볼 수 없는** 상태가 된다.
        var sawActive = false
        var sawFinished = false
        for id in Self.watchIDs {
            let path = "games/rpc.chess_watch@\(id).json"
            let object = try Self.raw(path)
            let match = try #require(object["match"] as? [String: Any])
            // 관전에 **없어야** 하는 것들(서버가 안 싣는 것이 1차 방어, 앱이 안 읽는 것이 2차).
            for forbidden in ["my_color", "legal_moves", "ruby_balance", "opponent", "state",
                              "chat", "chat_seq", "watchers", "watcher_count"] {
                #expect(object[forbidden] == nil, "\(path): 관전에 \(forbidden) 가 있다")
            }
            let decoded = try Self.decoder.decode(ChessWatchResponse.self, from: Self.entry(path).data)
            // 흑백은 black_user/white_user 로만 확정한다.
            #expect(decoded.whiteUser?.userId == match["white"] as? String, "\(path): white_user")
            #expect(decoded.blackUser?.userId == match["black"] as? String, "\(path): black_user")
            #expect(decoded.whiteUser?.userId != decoded.blackUser?.userId)
            // 관전자는 참가자가 아니다 — 내가 끼어 있으면 이 판은 관전 입구가 아니라 내 판이다.
            #expect(![match["white"] as? String, match["black"] as? String].contains(Self.me),
                    "\(path): 관전 판에 내가 참가자로 있다")

            let now = Self.int(object["server_now_ms"])!
            switch match["status"] as? String {
            case "active":
                sawActive = true
                #expect(match["finished_ms"] is NSNull)
                #expect(Self.int(match["turn_started_ms"])! <= now, "\(path): 차례가 미래에 시작됐다")
            case "finished":
                sawFinished = true
                let finished = try #require(Self.int(match["finished_ms"]), "\(path): finished_ms")
                #expect(finished <= now, "\(path): 미래에 끝났다")
                #expect(now - finished < Self.watchTailMs,
                        "\(path): 끝난 지 \(now - finished)ms — 180초 꼬리 밖이라 서버는 not_found 다")
            default:
                Issue.record("\(path): 관전할 수 없는 상태 \(match["status"] ?? "nil")")
            }
        }
        #expect(sawActive && sawFinished, "관전은 진행 중 한 판과 끝난 한 판이 다 있어야 한다")
    }

    // MARK: - ⑪ ★ 갈림: 기준선이 같은 입력이면 위 단언들이 전부 공짜다

    @Test("★ 픽스처 집합이 실제로 갈린다(상태·차례·내 색·체크·결과·승격·제안)")
    func theFixtureSetActuallyVaries() throws {
        // ★ 저장소 메모 '비교 기준선이 달라야 한다': 기준선이 같은 입력이면 그 테스트는 영원히 초록이다.
        // 위 ①~⑩ 은 "갈래마다 다르게 다뤄야 한다" 를 재는데, 갈래가 하나뿐이면 전부 공짜로 통과한다.
        // 그래서 **갈림 자체**를 단언으로 못 박는다 — 누가 변형을 지우면 여기가 빨개진다.
        var statuses: Set<String> = []
        var turns: Set<String> = []
        var myColors: Set<String> = []
        var inChecks: Set<String> = []
        var results: Set<String> = []
        var legalPresence: Set<Bool> = []
        var sawPromoRow = false
        var sawDrawOffer = false
        var sawCastling = false
        var longestLine = 0

        for board in try Self.boards() {
            statuses.insert(board.status)
            turns.insert(board.match["turn"] as? String ?? "nil")
            results.insert(board.match["result"] as? String ?? "nil")
            inChecks.insert(board.raw["in_check"] is NSNull ? "nil" : "\(board.raw["in_check"] as? Bool ?? false)")
            if !board.isWatch {
                myColors.insert(board.raw["my_color"] as? String ?? "nil")
                legalPresence.insert(board.raw["legal_moves"] is [String])
            }
            if board.match["draw_offer_by"] is String { sawDrawOffer = true }
            if board.moves.contains(where: { $0["promo"] is String }) { sawPromoRow = true }
            if board.moves.contains(where: { ($0["san"] as? String)?.hasPrefix("O-O") == true }) { sawCastling = true }
            longestLine = max(longestLine, board.moves.count)
        }

        #expect(statuses == ["active", "finished", "pending"], "판 상태 갈래: \(statuses.sorted())")
        #expect(turns == ["black", "white"], "차례 갈래: \(turns.sorted())")
        #expect(myColors == ["black", "white"], "내 색 갈래: \(myColors.sorted())")
        #expect(inChecks == ["false", "nil", "true"], "체크 갈래: \(inChecks.sorted())")
        #expect(results == ["black_win", "draw", "nil", "white_win"], "결과 갈래: \(results.sorted())")
        #expect(legalPresence == [false, true], "합법 수가 있는 판과 없는 판이 다 있어야 한다")
        #expect(sawDrawOffer, "무승부 제안이 와 있는 판이 없다")
        #expect(sawPromoRow, "기보에 승격 수(promo)가 든 판이 없으면 기보 목록의 '=Q' 표기를 못 본다")
        #expect(sawCastling, "캐슬링이 든 기보가 없으면 '룩도 함께 움직인다' 를 데모에서 볼 수 없다")
        #expect(longestLine >= 40, "가장 긴 기보가 \(longestLine)수 — 기보 목록의 스크롤을 못 본다")

        // '내 차례 + 도는 판' 과 '상대 차례 + 도는 판' 이 **둘 다** 있어야 집기 금지를 잴 수 있다.
        var myTurnActive = 0
        var theirTurnActive = 0
        for board in try Self.boards() where board.isActive && !board.isWatch {
            if board.raw["my_color"] as? String == board.match["turn"] as? String { myTurnActive += 1 }
            else { theirTurnActive += 1 }
        }
        #expect(myTurnActive >= 2 && theirTurnActive >= 1,
                "내 차례 \(myTurnActive) · 상대 차례 \(theirTurnActive) — 둘 다 있어야 한다")
    }
}
