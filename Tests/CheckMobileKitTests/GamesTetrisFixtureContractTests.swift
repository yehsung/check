// 코어 `package` 타입(TetrisWire 의 응답 행 · TetrisDuelBoard · TetrisDuelSession · TetrisDuelStore.resumePoint)을
// 쓰므로 `@testable` 로 받는다 — 옆 `GamesChessFixtureContractTests` 와 같은 길이다.
@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1:1 테트리스 **데모 픽스처**(`Demo/Fixtures/games/rpc.tetris_*.json` · 장면 폴더 일곱)의 계약.
//
// ── 무엇을 재는가: 글자가 아니라 **코어가 그 글자로 세우는 것** ──
// JSON 을 문자열로 훑지 않는다. 모든 픽스처를 **서비스와 같은 디코더로** 와이어 타입에 넣고(그래서 키 이름이
// 하나라도 틀리면 값이 nil 이 되어 아래 단언이 빨개진다 — 특히 사람 행의 `id`: 체스는 `user_id` 라 베껴 쓰면
// 목록이 조용히 빈다), 판 글자는 **엔진에 올려** 왕복을 잰다.
//   ① 파일 집합이 정확히 스물셋이다(늘리거나 줄이는 것은 결정이다).
//   ② 모든 `board` 가 정확히 200글자이고 글자가 `.IJLOSTZG` 뿐이다(서버 CHECK 와 같은 술어).
//   ③ 장면마다 **재개(`resumePoint`)가 서는지/안 서는지**를 기대값과 함께 잰다 — 판 장면에서 재개가 안 서면
//      스틸에 **빈 판**이 선다(이 레인이 막아야 하는 바로 그 결함).
//   ④ 재개가 서는 장면은 엔진 왕복(`encode(resumingFrom(board)) == board`)과 **따라잡기 초**를 잰다.
//      `last_seen_ms` 를 `server_now_ms` 에서 떼면 그만큼 엔진이 혼자 흘러(상한 30초) 스틸의 판이 글자판과 달라진다.
//   ⑤ 가속 장면은 서버 경과초가 120 을 **넘는다**(D7). 안 넘으면 '속도 올라가는 중 · 레벨 N' 이 아예 안 뜬다.
//   ⑥ 결과 장면의 승패·사유 쌍이 서버 CHECK 를 지키고(topout 은 승패가 있다 · time_cap·no_show 는 무승부),
//      `result` 글자가 **내 기준이 아니다**(won 은 `opponent_win`, lost 는 `challenger_win` — 두 장면이 갈린다).
//   ⑦ 루비가 수수료 식(`DuelFee`)과 맞고, 장면 로비의 잔액과 같은 숫자다(한 화면에 함께 뜬다).
//   ⑧ 공격 누계가 서로 맞물리고 서버 상한(`8 + 3×경과초`) 아래다.
//   ⑨ 마지막으로 **갈림 자체**를 단언한다 — 여섯 판 장면의 state 가 서로 달라야 한다(기준선이 같은 입력이면
//      그 테스트는 영원히 초록이다).
//
// ── 닿는 길(데모 라우트) ──
//   games/tetris/lobby                 로비 머리(상대 고르기)
//   games/tetris/lobby/invites         받은 신청 둘 · 보낸 신청 하나
//   games/tetris/ranking               순위 탭
//   games/tetris/match/{ready,countdown,playing,speedup,won,lost}
// 라우트 → 장면·판 id 표는 `MobileDemoTetrisRoute` 머리말이고, 그 파서는 `GamesTetrisDemoRouteTests` 가 잰다.
@Suite struct GamesTetrisFixtureContractTests {

    // MARK: - 재료

    static let index = MobileDemoFixtures.load()
    /// 서비스와 **같은 설정**이어야 한다 — 디코더가 다르면 이 스위트가 통과해도 앱에서 nil 이 된다.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let serverNowMs: Double = 1_789_621_500_000      // MobileClock.demoInstant
    static let baseRuby = 42                                 // 기본 로비 me.ruby_balance

    static let me = MobileDemo.userID
    static let cloud = "d0000000-0000-4000-8000-0000000000b1"    // 구름빵
    static let choco = "d0000000-0000-4000-8000-0000000000b2"    // 초코칩
    static let walnut = "d0000000-0000-4000-8000-0000000000b4"   // 호두과자

    /// 판 장면 여섯 + 신청 하나. `matchID` 가 그대로 `rpc.tetris_state@<id>.json` 의 바늘이고 라우트 꼬리다.
    struct MatchScene {
        let route: String
        let matchID: String
        let stake: Int
        /// 서버 행에서 판을 **재개할 수 있는가**(`TetrisDuelStore.resumePoint` 네 조건).
        let resumes: Bool
        /// 서버 경과초(`server_now_ms − start_at_ms`). 시작 전이면 음수, 아직 안 정했으면 nil.
        let elapsed: Double?
        /// 그 경과초의 가속 바닥(D7). 시작 시각이 없으면 nil.
        let levelFloor: Int?
        let finished: Bool
        /// 정산 뒤 내 잔액.
        let ruby: Int
        let opponent: String
    }

    static let matchScenes: [MatchScene] = [
        // 준비 대기 — 시작 시각이 없으니 이어 받을 판이 없다(준비 보고는 빈 판이다).
        .init(route: "games/tetris/match/ready", matchID: "demo-tetris-ready", stake: 5,
              resumes: false, elapsed: nil, levelFloor: nil, finished: false, ruby: 37, opponent: cloud),
        // 카운트다운 — 마지막 보고가 시작 시각보다 **앞**이라 재개가 서지 않는다.
        .init(route: "games/tetris/match/countdown", matchID: "demo-tetris-countdown", stake: 5,
              resumes: false, elapsed: -1.8, levelFloor: 1, finished: false, ruby: 37, opponent: cloud),
        .init(route: "games/tetris/match/playing", matchID: "demo-tetris-playing", stake: 5,
              resumes: true, elapsed: 73, levelFloor: 1, finished: false, ruby: 37, opponent: cloud),
        // 가속 — 120 을 넘겨야 '속도 올라가는 중' 이 선다. 10 + (168−120)/10 = 14.
        .init(route: "games/tetris/match/speedup", matchID: "demo-tetris-speedup", stake: 10,
              resumes: true, elapsed: 168, levelFloor: 14, finished: false, ruby: 32, opponent: walnut),
        .init(route: "games/tetris/match/won", matchID: "demo-tetris-won", stake: 5,
              resumes: true, elapsed: 214, levelFloor: 19, finished: true, ruby: 46, opponent: cloud),
        .init(route: "games/tetris/match/lost", matchID: "demo-tetris-lost", stake: 10,
              resumes: true, elapsed: 151, levelFloor: 13, finished: true, ruby: 32, opponent: choco),
    ]

    /// 테트리스 데모 픽스처는 **정확히 이 스물셋**이다(로비 8 · 상태 7 · 쓰기 7 · 순위 1).
    static let requiredPaths: Set<String> = [
        "games/rpc.tetris_lobby.json",
        "games/_games-tetris-lobby-invites/rpc.tetris_lobby.json",
        "games/_games-tetris-match-ready/rpc.tetris_lobby.json",
        "games/_games-tetris-match-countdown/rpc.tetris_lobby.json",
        "games/_games-tetris-match-playing/rpc.tetris_lobby.json",
        "games/_games-tetris-match-speedup/rpc.tetris_lobby.json",
        "games/_games-tetris-match-won/rpc.tetris_lobby.json",
        "games/_games-tetris-match-lost/rpc.tetris_lobby.json",
        "games/rpc.tetris_state@demo-tetris-ready.json",
        "games/rpc.tetris_state@demo-tetris-countdown.json",
        "games/rpc.tetris_state@demo-tetris-playing.json",
        "games/rpc.tetris_state@demo-tetris-speedup.json",
        "games/rpc.tetris_state@demo-tetris-won.json",
        "games/rpc.tetris_state@demo-tetris-lost.json",
        "games/rpc.tetris_state@demo-tetris-invite-out.json",
        "games/rpc.tetris_report.json",
        "games/rpc.tetris_respond@true.json",
        "games/rpc.tetris_respond@false.json",
        "games/rpc.tetris_challenge.json",
        "games/rpc.tetris_cancel.json",
        "games/rpc.tetris_resign@demo-tetris-playing.json",
        "games/rpc.tetris_resign.json",
        "games/rpc.tetris_ranking.json",
    ]

    // MARK: - 도우미

    /// 스텁이 실제로 고르는 길로 픽스처 한 장을 집는다(키 + 바늘 + 장면) — 테스트가 파일 경로를 짚으면
    /// 스텁의 고르기 규칙이 바뀌어도 초록이다. 여기서는 **앱이 받는 바이트**를 잰다.
    static func body(rpc: String, matchID: String? = nil, accept: Bool? = nil,
                     route: String = "games/tetris/lobby") throws -> Data {
        var fields = [#""p_protocol":1"#]
        if let matchID { fields.append(#""p_match_id":"\#(matchID)""#) }
        if let accept { fields.append(#""p_accept":\#(accept)"#) }
        let request = MobileStubRequest(
            method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)",
            query: "", headers: [:], bodyText: "{" + fields.joined(separator: ",") + "}")
        let scenario = route.replacingOccurrences(of: "/", with: "-").lowercased()
        let entry = try #require(index.entry(for: request, scenario: scenario),
                                 "스텁이 \(rpc) 를 \(route) 장면에서 못 고른다(404 로 접힌다)")
        return entry.data
    }

    static func lobby(route: String) throws -> TetrisLobbyResponse {
        try decoder.decode(TetrisLobbyResponse.self, from: body(rpc: "tetris_lobby", route: route))
    }

    static func action(rpc: String, matchID: String? = nil, accept: Bool? = nil,
                       route: String = "games/tetris/lobby") throws -> TetrisActionResponse {
        try decoder.decode(TetrisActionResponse.self,
                           from: body(rpc: rpc, matchID: matchID, accept: accept, route: route))
    }

    static func state(_ scene: MatchScene) throws -> TetrisStatePayload {
        let response = try action(rpc: "tetris_state", matchID: scene.matchID, route: scene.route)
        #expect(response.status == .ok, "\(scene.matchID): 상태 봉투가 ok 가 아니다")
        return try #require(response.state, "\(scene.matchID): 봉투에 state 가 없다(§2.5 — 펼치지 않는다)")
    }

    /// 서버 `tetris_attack_cap(p_elapsed_ms)` = `8 + 3 × greatest(0, 경과초)`.
    static func attackCap(elapsed: Double) -> Int { 8 + 3 * Int(max(0, elapsed)) }

    // MARK: - ① 파일 집합

    @Test("테트리스 데모 픽스처는 정확히 스물셋이다 · 키가 겹치지 않는다")
    func fixtureSetIsPinned() {
        let found = Set(Self.index.entries.filter { $0.key.hasPrefix("rpc.tetris_") }.map(\.relativePath))
        #expect(found == Self.requiredPaths, """
            테트리스 픽스처 집합이 달라졌다(늘리거나 줄이는 것은 결정이다).
            더 생긴 것: \(found.subtracting(Self.requiredPaths).sorted())
            사라진 것: \(Self.requiredPaths.subtracting(found).sorted())
            """)
        #expect(Self.index.duplicateKeys.isEmpty, "\(Self.index.duplicateKeys)")
        // 모든 장면 폴더에는 로비 변형이 **하나만** 있다 — 두 벌이면 어느 쪽이 답하는지가 정렬에 달린다.
        for scene in Self.matchScenes {
            let scenario = scene.route.replacingOccurrences(of: "/", with: "-")
            let inScene = Self.index.entries.filter { $0.scenario == scenario }
            #expect(inScene.map(\.key) == ["rpc.tetris_lobby"], "\(scenario) 장면 폴더: \(inScene.map(\.relativePath))")
        }
    }

    // MARK: - ② 판 글자판 200글자

    @Test("모든 board 가 정확히 200글자이고 글자가 .IJLOSTZG 뿐이다(서버 CHECK 와 같은 술어) · 디코드가 선다")
    func everyBoardMatchesTheServerCheck() throws {
        var counted = 0
        var withGarbage = 0
        for scene in Self.matchScenes {
            let payload = try Self.state(scene)
            for (who, row) in [("me", payload.me), ("opponent", payload.opponent)] {
                let row = try #require(row, "\(scene.matchID).\(who) 행이 없다")
                // 사람 행의 id 키는 `id` 다(체스의 `user_id` 가 아니다) — 틀리면 여기서 nil 이다.
                #expect(row.id?.isEmpty == false, "\(scene.matchID).\(who): id 가 없다(키를 user_id 로 적었나)")
                guard let board = row.board else { continue }
                counted += 1
                // 글자 수는 **UTF-8 바이트가 아니라 칸 수**로 센다(알파벳이 ASCII 라 같지만 술어를 섞지 않는다).
                #expect(board.count == TetrisDuelBoard.cellCount,
                        "\(scene.matchID).\(who): 판이 \(board.count)글자다(200이어야 한다)")
                let alphabet = Set(TetrisDuelBoard.alphabet)
                let strays = Set(board).subtracting(alphabet)
                #expect(strays.isEmpty, "\(scene.matchID).\(who): 모르는 글자 \(strays.sorted())")
                #expect(TetrisDuelBoard.isValid(board), "\(scene.matchID).\(who): 서버 CHECK 를 못 지난다")
                #expect(TetrisDuelBoard.decode(board) != nil, "\(scene.matchID).\(who): 코어가 못 읽는다")
                if board.contains("G") { withGarbage += 1 }
            }
        }
        // 대조: 준비 대기의 상대 행만 board 가 null 이다(보고가 한 번도 없으면 서버 칸이 null 이다).
        #expect(counted == 11, "판 글자를 싣는 행 수가 달라졌다: \(counted)")
        #expect(withGarbage == 8, "방해 줄(G)이 든 판 수가 달라졌다 — 회색 줄 없는 판만 남으면 painter 의 회색이 안 보인다: \(withGarbage)")
        // 빈 판(준비·카운트다운)은 점 200개여야 한다.
        let ready = try Self.state(Self.matchScenes[0])
        #expect(ready.me?.board == String(repeating: ".", count: 200))
        #expect(ready.opponent?.board == nil, "첫 보고 전 상대 판은 null 이다(빈 문자열이 아니다)")
    }

    // MARK: - ③④ 재개 · 따라잡기 · 엔진 왕복

    @Test("장면마다 재개가 기대대로 서고/안 서고, 서는 장면은 엔진 왕복 · 살아 있는 판은 따라잡기 2초 이하다")
    func resumeMatchesThePerSceneExpectation() throws {
        for scene in Self.matchScenes {
            let payload = try Self.state(scene)
            let point = TetrisDuelStore.resumePoint(me: payload.me, startAtMs: payload.startAtMs)
            #expect((point != nil) == scene.resumes, """
                \(scene.matchID): 재개 기대 \(scene.resumes) 인데 \(point != nil) 다.
                재개 조건 넷 — seq>0(\(payload.me?.seq ?? -1)) · board 유효 · start_at_ms 있음(\(payload.startAtMs != nil)) \
                · last_seen_ms > start_at_ms. 판 장면에서 이것이 거짓이면 스틸에 **빈 판**이 선다.
                """)
            guard let point else { continue }
            let seed = try #require(payload.seed, "\(scene.matchID): seed 가 없으면 코어가 판을 아예 열지 않는다")
            var session = try #require(TetrisDuelSession(seed: seed, resumingFrom: point),
                                       "\(scene.matchID): 엔진이 이 판 글자를 못 받는다")
            // 왕복: 서버 행 → 엔진 → 다시 200글자. 방해 줄은 찬 칸 + 표시 비트라 `G` 로 되돌아와야 한다.
            #expect(TetrisDuelBoard.encode(session.game) == point.board,
                    "\(scene.matchID): 엔진에 올린 판이 서버 글자와 다르다(방해 줄 표시가 샜다)")
            #expect(session.game.lines == (payload.me?.lines ?? -1), "\(scene.matchID): 지운 줄이 안 이어졌다")
            #expect(session.game.attackSentTotal == (payload.me?.garbageSent ?? -1),
                    "\(scene.matchID): 보낸 공격 누계가 안 이어졌다(0 에서 다시 세면 서버 단조 최댓값에 막혀 새 공격이 안 간다)")
            #expect(session.game.pendingGarbageLines == (payload.me?.pending ?? -1),
                    "\(scene.matchID): 대기 방해 줄이 안 이어졌다")
            #expect(session.started && !session.game.isGameOver, "\(scene.matchID): 재개한 판이 이미 끝나 있다")

            let elapsed = try #require(scene.elapsed)
            let catchUp = elapsed - point.elapsedSeconds
            #expect(catchUp >= 0, "\(scene.matchID): 마지막 보고가 서버가 아는 경과보다 뒤다(시각이 어긋났다)")
            if scene.finished {
                // 끝난 판은 **따라잡지 않는다**(applyState 가 구동기를 버린다) — 그래서 마지막 보고가 몇 초 전이어도
                // 스틸의 판이 흐르지 않는다. 대신 그 보고가 판이 닫힌 시각보다 **앞**인지만 본다.
                let finishedAt = try #require(payload.finishedAtMs, "\(scene.matchID): finished_at_ms 가 없다")
                for (who, seen) in [("me", payload.me?.lastSeenMs), ("opponent", payload.opponent?.lastSeenMs)] {
                    #expect((seen ?? 0) <= finishedAt, "\(scene.matchID).\(who): 판이 닫힌 뒤에 보고가 닿았다")
                }
                continue
            }
            // 따라잡기: 서버가 아는 경과 − 내 마지막 보고의 경과. 이만큼 엔진이 혼자 흐른다(상한 30초).
            // **살아 있는 판에만 재는 규칙이다** — 화면이 열리는 순간 코어가 그만큼 판을 밀기 때문이다.
            #expect(catchUp <= 2, """
                \(scene.matchID): 따라잡기 \(catchUp)초. last_seen_ms 를 server_now_ms 에 붙여 둬라 —
                멀어지면 그만큼 엔진이 혼자 흘러 스틸의 판이 이 글자판과 달라진다.
                """)
            // 끝나지 않은 장면은 실제로 밀어 본다: 화면이 열리는 순간 코어가 하는 일 그대로.
            let localNow: TimeInterval = 10_000
            session.syncStart(startAtMs: try #require(payload.startAtMs),
                              serverNowMs: Self.serverNowMs, localNow: localNow)
            session.advance(to: localNow)
            #expect(!session.game.isGameOver, "\(scene.matchID): 따라잡기만으로 판이 끝났다 — 스틸이 결과 카드가 된다")
            #expect(session.game.lines >= (payload.me?.lines ?? 0), "\(scene.matchID): 지운 줄이 줄었다")
        }
    }

    // MARK: - ⑤ 가속

    @Test("가속 장면만 경과 120초를 넘고 레벨 바닥이 1 보다 크다(D7) · 장면마다 바닥이 갈린다")
    func speedupSceneCrossesTheRamp() throws {
        var floors: [String: Int] = [:]
        for scene in Self.matchScenes {
            let payload = try Self.state(scene)
            guard let startAtMs = payload.startAtMs else {
                #expect(scene.elapsed == nil, "\(scene.matchID): 시작 시각이 없는데 경과 기대값이 있다")
                #expect(scene.levelFloor == nil)
                continue
            }
            let elapsed = (Self.serverNowMs - startAtMs) / 1000
            #expect(elapsed == scene.elapsed, "\(scene.matchID): 서버 경과 \(elapsed)초(기대 \(scene.elapsed ?? -1))")
            let floor = TetrisDuelSession.rampLevelFloor(elapsedSeconds: elapsed)
            #expect(floor == scene.levelFloor, "\(scene.matchID): 레벨 바닥 \(floor)(기대 \(scene.levelFloor ?? -1))")
            floors[scene.matchID] = floor
        }
        // 이 장면의 전부가 이 한 줄이다: 120 을 안 넘기면 '속도 올라가는 중 · 레벨 N' 이 **아예 안 뜬다**.
        #expect(floors["demo-tetris-speedup"] == 14 && floors["demo-tetris-speedup"]! > 1)
        #expect(floors["demo-tetris-playing"] == 1, "판 진행 장면이 가속에 걸리면 두 장면이 같은 그림이 된다")
        // 갈림: 바닥 값이 네 가지여야 한다(1 · 14 · 19 · 13) — 전부 같으면 가속 표시가 거짓이어도 안 드러난다.
        #expect(Set(floors.values).count == 4, "레벨 바닥이 안 갈린다: \(floors)")
    }

    // MARK: - ⑥ 결과 장면의 쌍방 규칙

    @Test("결과 장면의 승패·사유 쌍이 서버 CHECK 를 지키고 result 글자가 내 기준이 아니다")
    func finishedScenesObeyTheServerPairRules() throws {
        var results: [String] = []
        for scene in Self.matchScenes where scene.finished {
            let payload = try Self.state(scene)
            #expect(payload.status == "finished", "\(scene.matchID): status 가 finished 가 아니다")
            let reasonRaw = try #require(payload.endReason, "\(scene.matchID): 끝난 판에 사유가 없다")
            let reason = try #require(TetrisDuelEndReason(rawValue: reasonRaw),
                                      "\(scene.matchID): 코어가 모르는 사유 \(reasonRaw)")
            let result = try #require(payload.result, "\(scene.matchID): 끝난 판에 result 가 없다")
            #expect(["challenger_win", "opponent_win", "draw"].contains(result), "\(scene.matchID): \(result)")
            #expect(payload.finishedAtMs != nil, "\(scene.matchID): finished_at_ms 가 없다(서버 쌍방 CHECK)")
            // 쌍방 iff: draw ⟺ winner null · time_cap·no_show 는 늘 draw · topout·resign 은 승패가 있다.
            let isDraw = result == "draw"
            #expect(isDraw == (payload.winner == nil), "\(scene.matchID): draw ⟺ winner null 이 깨졌다")
            if reason.isAlwaysDraw {
                #expect(isDraw, "\(scene.matchID): \(reasonRaw) 는 언제나 무승부다")
            } else {
                #expect(!isDraw, "\(scene.matchID): \(reasonRaw) 는 승패가 있어야 한다")
            }
            // 탑아웃은 **진 쪽만** 자기 신고를 한다(D9 — 서버는 자기에게 불리한 신고만 믿는다).
            if reason == .topout {
                let winner = try #require(payload.winner)
                let iWon = winner == Self.me
                #expect((payload.me?.toppedOut ?? false) == !iWon, "\(scene.matchID): 내 탑아웃 깃발이 승패와 어긋난다")
                #expect((payload.opponent?.toppedOut ?? false) == iWon, "\(scene.matchID): 상대 탑아웃 깃발이 어긋난다")
            }
            results.append(result)
        }
        // ★ `result` 는 판 표의 challenger/opponent 칸 기준이고 **내 기준이 아니다.** 두 결과 장면이 같은 글자면
        //   result 로 승패를 가르는 화면이 있어도 드러나지 않는다 — 그래서 일부러 갈라 뒀다.
        #expect(Set(results) == ["challenger_win", "opponent_win"], "결과 두 장면의 result 글자가 안 갈린다: \(results)")
        let won = try Self.state(Self.matchScenes[4])
        #expect(won.result == "opponent_win" && won.winner == Self.me,
                "이긴 장면의 result 가 'opponent_win' 이어야 한다(나는 신청받은 쪽이다) — 이 짝이 함정이다")
        let lost = try Self.state(Self.matchScenes[5])
        #expect(lost.result == "challenger_win" && lost.winner == Self.choco)
    }

    // MARK: - ⑦ 루비 · 수수료

    @Test("장면마다 루비가 DuelFee 식과 맞고, 같은 장면 로비의 잔액과 같은 숫자다")
    func rubyFollowsTheFeeFormula() throws {
        for scene in Self.matchScenes {
            let payload = try Self.state(scene)
            #expect(payload.stake == scene.stake, "\(scene.matchID): 판돈 \(payload.stake ?? -1)")
            #expect(TetrisDuelStake(rawValue: scene.stake) != nil, "\(scene.matchID): 판돈이 3·5·10 밖이다")
            // 수락 때 양쪽에서 판돈을 걷고, 이기면 2×판돈 − 수수료를 받는다(서버 duel_fee 와 같은 식).
            let iWon = payload.winner == Self.me
            let want = Self.baseRuby - scene.stake + (iWon ? DuelFee.winnerPayout(stake: scene.stake) : 0)
            #expect(payload.rubyBalance == want,
                    "\(scene.matchID): 잔액 \(payload.rubyBalance ?? -1)(기대 \(want) = 42 − 판돈\(iWon ? " + 승자 수령" : ""))")
            #expect(payload.rubyBalance == scene.ruby, "\(scene.matchID): 표의 기대 잔액과 다르다")
            // 같은 화면에 함께 뜨는 두 숫자 — 장면 로비의 잔액이 상태의 잔액과 달라선 안 된다.
            let sceneLobby = try Self.lobby(route: scene.route)
            #expect(sceneLobby.me?.rubyBalance == payload.rubyBalance,
                    "\(scene.route): 로비 잔액 \(sceneLobby.me?.rubyBalance ?? -1) ≠ 상태 잔액 \(payload.rubyBalance ?? -1)")
            #expect(sceneLobby.me?.activeMatchId == scene.matchID, """
                \(scene.route): 장면 로비의 active_match_id 가 \(sceneLobby.me?.activeMatchId ?? "nil") 다.
                이 칸이 그 판을 가리켜야 코어가 로비 응답만으로 그 단계를 세운다 — 아니면 여섯 라우트가 전부 로비를 그린다.
                """)
            // 결과 카드의 눈금은 **순이익**이다(수령액이 아니다).
            if payload.result != nil {
                let delta = iWon ? DuelFee.winnerNet(stake: scene.stake) : -scene.stake
                #expect(delta == (iWon ? scene.stake - DuelFee.fee(stake: scene.stake) : -scene.stake))
            }
        }
        // 판돈 세 값이 모두 쓰인다 — 한 값만 쓰면 수수료 계산이 틀려도 안 보인다(3→1 · 5→1 · 10→2).
        #expect(Set(Self.matchScenes.map(\.stake) + [3]) == [3, 5, 10])
        let invite = try Self.action(rpc: "tetris_state", matchID: "demo-tetris-invite-out",
                                     route: "games/tetris/lobby/invites")
        #expect(invite.state?.stake == 3, "보낸 신청 장면이 판돈 3 을 덮는다")
        // 신청은 아직 판돈을 걷지 않는다 — 잔액이 기본값 그대로여야 한다.
        #expect(invite.state?.rubyBalance == Self.baseRuby)
        #expect(invite.state?.seed == nil, "수락 전에는 시드가 없다(수락 순간 뽑는다)")
        #expect(invite.state?.status == "pending")
    }

    // MARK: - ⑧ 공격 누계

    @Test("공격 누계가 서로 맞물리고 서버 상한(8 + 3×경과초) 아래다")
    func attackTotalsInterlock() throws {
        for scene in Self.matchScenes {
            let payload = try Self.state(scene)
            let mine = try #require(payload.me)
            let theirs = try #require(payload.opponent)
            guard let elapsed = scene.elapsed, elapsed > 0 else { continue }
            #expect(mine.garbageApplied == theirs.garbageSent, """
                \(scene.matchID): 내가 받아들인 누계(\(mine.garbageApplied ?? -1))가 상대가 보낸 누계\
                (\(theirs.garbageSent ?? -1))와 다르다 — 코어는 그 차이만큼 receiveGarbage 를 더 부른다.
                """)
            #expect(theirs.garbageApplied == mine.garbageSent, "\(scene.matchID): 반대 방향 누계가 안 맞물린다")
            let cap = Self.attackCap(elapsed: elapsed)
            #expect((mine.garbageSent ?? 0) <= cap && (theirs.garbageSent ?? 0) <= cap,
                    "\(scene.matchID): 서버가 자를 값이다(상한 \(cap))")
            #expect((mine.pending ?? 0) <= (mine.garbageApplied ?? 0), "\(scene.matchID): 대기가 받아들인 누계보다 많다")
        }
    }

    // MARK: - ⑨ 갈림

    @Test("여섯 판 장면의 state 가 서로 다르다(기준선이 같은 입력이면 그 테스트는 영원히 초록이다)")
    func theSixMatchScenesDiffer() throws {
        var seen: [TetrisStatePayload] = []
        for scene in Self.matchScenes {
            let payload = try Self.state(scene)
            #expect(!seen.contains(payload), "\(scene.matchID) 가 앞 장면과 바이트 동일이다")
            seen.append(payload)
        }
        #expect(seen.count == 6)
        // 흐름 네 단계가 실제로 갈린다: 시작 시각 없음 → 미래 → 과거 → 끝남.
        #expect(seen[0].startAtMs == nil)
        #expect(seen[1].startAtMs.map { $0 > Self.serverNowMs } == true, "카운트다운 장면의 시작 시각이 과거다")
        #expect(seen[2].startAtMs.map { $0 < Self.serverNowMs } == true)
        #expect(seen.filter { $0.status == "finished" }.count == 2)
        #expect(Set(seen.compactMap(\.seed)).count == 6, "시드가 겹친다 — 장면마다 조각 순서가 같아 보인다")
    }

    // MARK: - 로비

    @Test("로비 머리: 내가 목록에 없고, 신청을 막는 축 네 개가 각각 적어도 하나씩 있다")
    func lobbyCoversEveryBlockingAxis() throws {
        let response = try Self.lobby(route: "games/tetris/lobby")
        #expect(response.status == .ok)
        #expect(response.serverNowMs == Self.serverNowMs)
        #expect(response.stakes == [3, 5, 10])
        let rows = try #require(response.users)
        #expect(rows.allSatisfy { $0.id?.isEmpty == false }, "사람 행 id 가 비었다(키를 user_id 로 적었나)")
        #expect(!rows.contains { $0.id == Self.me }, "서버는 호출자를 users[] 에서 뺀다")
        #expect(rows.count == 8)
        // 축 넷 + 신청 가능한 근무자. `capable == nil` 은 코어가 **불가**로 읽으므로 nil 을 두지 않는다.
        #expect(rows.allSatisfy { $0.capable != nil }, "capable 이 nil 인 행은 '불가'로 읽혀 조용히 신청이 막힌다")
        #expect(rows.contains { $0.capable == false }, "구버전(capable=false) 행이 없다")
        #expect(rows.contains { $0.inMatch == true }, "대결 중 행이 없다")
        #expect(rows.contains { $0.focusMode == true }, "집중 모드 행이 없다")
        #expect(rows.contains { $0.isWorking == true && $0.capable == true && $0.inMatch != true },
                "신청할 수 있는 근무자가 없다 — 그러면 로비에서 아무도 못 고른다")
        // 구버전과 근무 중이 **다른 축**임이 보여야 한다(근무 중인데 구버전 한 줄).
        #expect(rows.contains { $0.capable == false && $0.isWorking == true })
        // '지금 대결 중' 카드는 하나라도 모르면 안 선다 — 코어 매핑으로 실제로 세워 본다.
        let matches = try #require(response.matches)
        #expect(matches.count == 1)
        let live = try #require(matches.first)
        #expect(live.id?.isEmpty == false && live.a?.id != nil && live.b?.id != nil)
        #expect(live.startedAtMs != nil, "started_at_ms 가 없으면 liveMatch(from:) 이 카드를 안 만든다(체스는 started_ms 다)")
        #expect(TetrisDuelStake(rawValue: live.stake ?? 0) != nil)
        #expect(response.me?.activeMatchId == nil, "로비 머리에는 진행 중 판이 없다")
        #expect(response.me?.incoming?.isEmpty == true && response.me?.outgoing == nil)
        #expect(response.me?.rubyBalance == Self.baseRuby)
    }

    @Test("신청 장면: 받은 둘 · 보낸 하나 · 만료가 미래 · 판돈이 그 판의 state 와 같다")
    func invitesSceneIsCoherent() throws {
        let response = try Self.lobby(route: "games/tetris/lobby/invites")
        let mine = try #require(response.me)
        let incoming = try #require(mine.incoming)
        #expect(incoming.count == 2, "받은 신청이 둘이어야 '외 N건' 줄이 선다")
        for invite in incoming {
            #expect(invite.matchId?.isEmpty == false)
            #expect(invite.from?.id?.isEmpty == false, "받은 신청은 from 을 싣는다")
            #expect(invite.to == nil, "받은 신청에 to 를 싣지 않는다")
            let expires = try #require(invite.expiresAtMs, "만료가 없으면 코어가 그 신청을 아예 안 만든다")
            #expect(expires > Self.serverNowMs, "만료가 과거다 — 열자마자 카드가 사라진다")
            #expect(expires - Self.serverNowMs <= 60_000, "서버 TTL(60초)보다 멀다")
        }
        let outgoing = try #require(mine.outgoing)
        #expect(outgoing.to?.id == Self.walnut && outgoing.from == nil)
        #expect(outgoing.matchId == "demo-tetris-invite-out")
        // 판돈이 신청 카드와 그 판의 state 에서 **같은 숫자**여야 한다(수락하면 그 판이 열린다).
        let readyState = try Self.state(Self.matchScenes[0])
        #expect(incoming.first?.matchId == "demo-tetris-ready")
        #expect(incoming.first?.stake == readyState.stake, "받은 신청 판돈 ≠ 수락 뒤 판의 판돈")
        let outgoingState = try Self.action(rpc: "tetris_state", matchID: "demo-tetris-invite-out",
                                            route: "games/tetris/lobby/invites")
        #expect(outgoing.stake == outgoingState.state?.stake, "보낸 신청 판돈 ≠ 그 판의 판돈")
        #expect(mine.rubyBalance == Self.baseRuby, "신청만으로는 판돈을 걷지 않는다")
    }

    // MARK: - 쓰기 RPC

    @Test("판 보고는 성공이고 state 를 싣지 않는다(결정) · 없으면 1초 뒤 판 화면이 내려간다")
    func reportAnswersWithoutState() throws {
        let response = try Self.action(rpc: "tetris_report", matchID: "demo-tetris-playing",
                                       route: "games/tetris/match/playing")
        #expect(response.status == .ok, """
            판 보고가 실패로 오면 두 번 쌓여 '연결 확인 중' 이 판 위에 뜨고, 404(PGRST202) 면
            noteServerMissing() 이 1초 뒤 판 화면을 통째로 내린다.
            """)
        #expect(response.state == nil, """
            보고 응답에 state 를 실으면 고정 시계 데모에서 1초마다 같은 스냅숏이 돌아와 판이 그 순간에 묶인다.
            와이어는 state 를 Optional 로 뒀고(nil = 모른다) 코어는 nil 이면 아무것도 바꾸지 않는다 —
            그래서 화면은 열 때 받은 state 에서 출발해 제 단조 시계로 흐른다(D10). 운영 서버는 언제나 state 를 싣는다.
            """)
    }

    @Test("수락·거절이 바늘 하나(p_accept)로 갈린다 · 수락은 준비 대기 판을 돌려준다")
    func respondSplitsOnTheAcceptFlag() throws {
        let accepted = try Self.action(rpc: "tetris_respond", matchID: "demo-tetris-ready", accept: true,
                                       route: "games/tetris/lobby/invites")
        #expect(accepted.status == .ok && accepted.accepted == true)
        let state = try #require(accepted.state, "수락 ok 는 state 를 싣는다(§2.4)")
        #expect(state.matchId == "demo-tetris-ready")
        // 수락 직후는 판도 결과도 아니다 — 둘 다 첫 보고를 낸 뒤에 start_at 이 정해진다(D4).
        #expect(state.status == "active" && state.startAtMs == nil)
        #expect(state.seed != nil, "수락 순간 서버가 시드를 뽑는다")
        #expect(state.readyDeadlineMs != nil, "수락 + 30초가 없으면 '몇 초 안에' 를 말할 수 없다")

        let declined = try Self.action(rpc: "tetris_respond", matchID: "demo-tetris-ready", accept: false,
                                       route: "games/tetris/lobby/invites")
        #expect(declined.status == .ok && declined.accepted == false)
        #expect(declined.state == nil, "거절은 state 를 싣지 않는다(§2.4 — ok{accepted:false})")
    }

    @Test("신청·취소·기권 응답이 코어 어휘로 디코드된다 · 기권은 결과 카드를 세운다")
    func writeRPCsDecodeIntoCoreVocabulary() throws {
        let challenge = try Self.action(rpc: "tetris_challenge")
        #expect(challenge.status == .ok)
        #expect(challenge.matchId == "demo-tetris-invite-out", "돌려주는 id 가 보낸 신청 장면의 것과 같아야 뒤 폴링이 픽스처에 닿는다")
        #expect(challenge.expiresAtMs.map { $0 > Self.serverNowMs } == true)

        let cancel = try Self.action(rpc: "tetris_cancel", matchID: "demo-tetris-invite-out")
        #expect(cancel.status == .ok)

        let resign = try Self.action(rpc: "tetris_resign", matchID: "demo-tetris-playing",
                                     route: "games/tetris/match/playing")
        #expect(resign.status == .ok)
        let state = try #require(resign.state)
        #expect(state.matchId == "demo-tetris-playing", "기권 응답의 판 id 가 다르면 applyState 가 그 응답을 버린다")
        #expect(state.status == "finished" && state.endReason == TetrisDuelEndReason.resign.rawValue)
        #expect(state.winner == Self.cloud && state.result == "opponent_win")
        #expect(state.rubyBalance == Self.baseRuby - 5, "기권은 걸어 둔 판돈만 잃는다(더 떼지 않는다)")
        // 그 밖 장면의 기권은 **정직한 거절**로 온다 — 404 로 두면 화면이 통째로 내려간다.
        let elsewhere = try Self.action(rpc: "tetris_resign", matchID: "demo-tetris-speedup",
                                        route: "games/tetris/match/speedup")
        #expect(elsewhere.status == .notActive, "바늘 없는 안전망이 not_active 를 돌려줘야 한다")
    }

    // MARK: - 순위

    @Test("순위: 승점·순위를 행에서 다시 계산해 맞추고, 동률 두 줄이 같은 순위를 쓴다")
    func rankingRecomputesFromRows() throws {
        let response = try Self.decoder.decode(TetrisRankingResponse.self, from: Self.body(rpc: "tetris_ranking",
                                                                                           route: "games/tetris/ranking"))
        #expect(response.status == .ok)
        let rows = try #require(response.rows)
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { $0.id?.isEmpty == false }, "순위 행 id 가 비었다(키를 user_id 로 적었나)")
        for row in rows {
            let wins = try #require(row.wins), losses = try #require(row.losses)
            #expect(row.draws != nil, "무 칸이 비었다 — 사용자 지시로 승점만 띄우면 안 된다")
            #expect(row.displayName?.isEmpty == false)
            #expect(row.points == wins - losses, "승점 = 승 − 패(D11)")
            #expect(wins + losses + (row.draws ?? 0) > 0, "0판 행은 순위에서 빠진다")
        }
        // 순위 = '나보다 **엄격히** 나은 행 수 + 1'. 정렬은 (승점 desc, 승 desc, 무 desc, id asc).
        func better(_ a: TetrisRankRow, than b: TetrisRankRow) -> Bool {
            if (a.points ?? 0) != (b.points ?? 0) { return (a.points ?? 0) > (b.points ?? 0) }
            if (a.wins ?? 0) != (b.wins ?? 0) { return (a.wins ?? 0) > (b.wins ?? 0) }
            return (a.draws ?? 0) > (b.draws ?? 0)
        }
        for row in rows {
            let want = rows.filter { better($0, than: row) }.count + 1
            #expect(row.rank == want, "\(row.displayName ?? "?"): 순위 \(row.rank ?? -1)(기대 \(want))")
        }
        // 동률이 **있어야** rank 산식이 공짜로 통과하지 않는다.
        let ranks = rows.compactMap(\.rank)
        #expect(ranks.count != Set(ranks).count, "동률이 하나도 없다 — rank 산식이 검증되지 않는다")
        #expect(rows.first?.rank == 1 && rows == rows.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) },
                "배열 순서가 서버 순위 순서여야 한다(재정렬 금지)")
        // 전적 컷: tetris_record_epoch() 이 '-infinity' 라 컷이 없다 → 코어가 nil 로 접는다.
        #expect(response.recordSinceMs == nil, "record_since_ms 는 null 이다(체스는 컷이 있어 숫자가 실린다)")
        // 같은 화면에 함께 뜨는 전적 두 벌(순위 me ↔ 로비 me)이 같은 숫자여야 한다.
        let lobbyMe = try #require(try Self.lobby(route: "games/tetris/ranking").me)
        let rankingMe = try #require(response.me)
        #expect([rankingMe.wins, rankingMe.losses, rankingMe.draws] == [lobbyMe.wins, lobbyMe.losses, lobbyMe.draws],
                "순위의 내 전적과 로비의 내 전적이 다르다")
        let myRow = try #require(rows.first { $0.id == Self.me }, "내 행이 목록에 있어야 한다")
        #expect(rankingMe.rank == myRow.rank && rankingMe.points == myRow.points)
    }

    // MARK: - 설명 주석

    @Test("모든 테트리스 픽스처에 __note 가 있고, 그 키가 와이어 디코드를 막지 않는다")
    func everyFixtureCarriesItsNote() throws {
        for path in Self.requiredPaths.sorted() {
            let entry = try #require(Self.index.entries.first { $0.relativePath == path }, "픽스처가 없다: \(path)")
            let object = try #require(try JSONSerialization.jsonObject(with: entry.data) as? [String: Any],
                                      "JSON 객체가 아니다: \(path)")
            let note = try #require(object["__note"] as? [String], "\(path): __note 가 없다(픽스처 관례)")
            #expect(note.count >= 2, "\(path): 설명이 \(note.count)줄이다 — 닿는 길과 그 장면의 요점을 적는다")
            #expect(note.allSatisfy { !$0.isEmpty }, "\(path): 빈 설명 줄이 있다")
            // 봉투는 언제나 status 를 싣는다(와이어의 유일한 비옵셔널).
            #expect(object["status"] is String, "\(path): status 가 없다")
        }
    }
}
