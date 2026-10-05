import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 — 체스 **저장소**가 말 이동 애니메이션을 언제 세우고 언제 안 세우는가(`ChessStore.flight`).
//
// 모델이 내는 숫자(길이·이징·밀림 방향·흐려짐 순서)는 `V0346ChessFlightModelTests` 가 잰다. 여기서 재는 것은
// **배선** 하나다: 판을 갈아 치우는 깔때기가 셋이고(1:1 `applyState` · 로봇 `commitAIGame` · 관전 `applyWatch`)
// 하나라도 빠지면 그 길로 온 수만 순간이동한다 — 사용자에게는 "어떤 때는 되고 어떤 때는 안 된다" 로 보여
// 재현 조건을 찾는 데만 한참 걸린다.
//
// ★ 이 저장소에서 가장 자주 나온 결함이 **"모양을 재고 결과를 안 재는 테스트"** 다(메모리
//   `tests-measure-shape-not-result`). 그래서 여기 단언은 전부 **부르는 자리에서 `store.flight` 가
//   생겼는가/안 생겼는가 · 무슨 수인가**를 잰다. 함수가 있는지, 소스에 글자가 있는지는 한 줄도 세지 않는다.
//
// 서버는 쓰지 않는다 — `applyState`·`applyWatch` 를 **손으로 밟고** 로봇 판은 가짜 선택기로 돌린다. 그래서
// 응답 본문은 픽스처 원문이 아니라 손으로 만든 봉투인데, 키 이름이 어긋나 아무것도 안 재는 사고를 막기 위해
// **서비스와 같은 디코더**(`.convertFromSnakeCase`)로 읽고 FEN·SAN 은 손으로 적지 않고 `ChessRules` 로 만든다.
//
// ★ 기준선이 갈리는지 확인했다(두 분기가 동시에 참인 입력이 없으면 그 단언은 영원히 초록이다):
//   · 길 — 1:1 · 로봇(사람 수 **와** 로봇 수) · 관전 셋이 각자 애니메이션을 낸다 → ①②③
//   · 수 번호 — +1(생긴다) · 그대로(안 생긴다) · +2(안 생긴다) · 첫 적재(안 생긴다) → ②③④⑤
//   · 창 — 보임(생긴다) · 안 보임(안 생긴다) · 가려짐(안 생긴다) → ⑥
//   · 잡기 — 있는 수(`knockout` 이 선다) · 없는 수(nil) → ① vs ③
//   · 애니메이션 유무 — `flight` 만 다르고 `match`·`legalMoves`·`isMyTurn`·시계는 같다 → ⑩⑪

// MARK: - 하네스

/// 두 시험이 쓰는 수순. 잡기가 **두 번** 들어 있다(exd5 · Qxd5) — 잡힘 없는 수(e4 · d5)와 갈리는 기준선이다.
/// 네 수까지 두는 까닭: "수 번호가 2 늘면 안 만든다" 를 재고 **그 뒤에 한 수만 더 오면 만든다** 까지 보려면
/// ply 1·3·4 가 다 필요하다(그 기준선이 없으면 그 시험은 영원히 nil 을 보고 초록이다).
private let fdOpening = ["e2e4", "d7d5", "e4d5", "d8d5"]

/// 시각 기준점. `timeIntervalSinceReferenceDate` 가 0 인 순간을 쓴다 — `startedAt` 동치 단언이 한 비트도
/// 안 틀리게 떨어지고, 서버 epoch 과의 오프셋도 아래 `fdServerNowMs` 로 정확히 0 이 된다.
private let fdT0 = Date(timeIntervalSinceReferenceDate: 0)
/// 응답의 서버 '지금'. `fdT0` 와 같은 순간이라 `serverClockOffset` 이 0 이 되고, 그래서 두 스토어의 시계가
/// 바이트까지 같아진다(⑪ 이 그 동치를 잰다).
private let fdServerNowMs = fdT0.timeIntervalSince1970 * 1000

private let fdPvPMatch = "cf460000-0000-4000-8000-0000000000c1"
private let fdWatchMatch = "cf460000-0000-4000-8000-0000000000c2"
private let fdOtherMatch = "cf460000-0000-4000-8000-0000000000c3"
private let fdWhiteID = "aa460000-0000-4000-8000-0000000000a1"
private let fdBlackID = "bb460000-0000-4000-8000-0000000000b1"

private struct FDError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 테스트가 쥔 '지금'. 박스로 넣어 시나리오가 시간을 앞으로 민다(`AwayCloseTests.AFKClock` 과 같은 관용구).
@MainActor
private final class FDClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// 로봇의 수를 **테스트가 풀어 준다**. 사람 수와 로봇 수는 같은 깔때기(`commitAIGame`)를 지나므로, 풀어 주지
/// 않으면 로봇이 같은 틱에 두어 사람 수의 애니메이션을 덮는다 — 그러면 ② 는 로봇 것만 재고 "사람 수도
/// 미끄러지는가" 는 한 번도 안 재게 된다(둘 다 붙었는지 확인할 유일한 자리를 잃는다).
private actor FDRobotGate {
    private var isOpen = false
    func open() { isOpen = true }
    func waitUntilOpen() async {
        while !isOpen { try? await Task.sleep(for: .milliseconds(2)) }
    }
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥔다 — 오목 실측).
@MainActor
private func fdWait(_ resumes: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

/// 서비스와 **같은 규약**으로 읽는다(`SupabaseWorkService` 의 `.convertFromSnakeCase`). 구조체를 손으로
/// 채우면 `ply_count`·`turn_started_ms` 같은 키가 어긋난 자리를 영원히 못 잡는다.
private let fdDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

private func fdDecode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try fdDecoder.decode(type, from: JSONSerialization.data(withJSONObject: object))
}

private func fdSquare(_ notation: String) throws -> ChessSquare {
    guard let square = ChessSquare(notation) else { throw FDError("칸 이름이 아니다: \(notation)") }
    return square
}

/// 시작 국면에서 UCI 수들을 **실제로 적용해** 국면 열과 서버 수 행을 만든다.
/// `positions[n]` 은 n 수를 둔 뒤의 국면이고 `rows[n]` 은 n+1 번째 수의 행이다.
///
/// FEN·SAN 을 손으로 적지 않는 까닭: 파생(`ChessMoveFlight.make`)이 `after[move.to]` 로 "수와 국면이 맞는가"를
/// 보는데, 손으로 적은 FEN 은 그 단언을 공허하게 만든다(엔진이 준 국면이어야 실물이다).
private func fdLine(_ ucis: [String]) throws -> (positions: [ChessPosition], rows: [[String: Any]]) {
    var positions: [ChessPosition] = [.standard]
    var rows: [[String: Any]] = []
    for (offset, uci) in ucis.enumerated() {
        let current = positions[offset]
        guard let move = ChessMove(uci: uci) else { throw FDError("UCI 가 아니다: \(uci)") }
        guard let san = ChessRules.san(for: move, in: current) else {
            throw FDError("합법 수가 아니다: \(uci) · \(current.fen)")
        }
        guard let after = ChessRules.apply(move, to: current) else {
            throw FDError("적용할 수 없는 수다: \(uci) · \(current.fen)")
        }
        rows.append([
            "seq": offset + 1,
            "color": current.sideToMove.rawValue,
            // `from`·`to` 는 **칸 번호**(rank*8+file)다 — 서버 `chess_state` 의 그 모양이다.
            "from": move.from.index,
            "to": move.to.index,
            "san": san,
            "fen": after.fen,
            "ms_left": 300_000,
            "ms_spent": 0,
        ])
        positions.append(after)
    }
    return (positions, rows)
}

/// 대국 한 판의 서버 행(두 응답이 함께 쓴다). 끝난 판은 `turn`·`turn_started_ms` 가 없다(서버 계약).
private func fdMatchRow(matchID: String, ply: Int, position: ChessPosition,
                        finished: Bool, myColor: ChessColor) -> [String: Any] {
    var row: [String: Any] = [
        "id": matchID, "status": finished ? "finished" : "active", "stake": 5,
        "white": fdWhiteID, "black": fdBlackID,
        "challenger": fdWhiteID, "opponent": fdBlackID,
        "ply_count": ply, "fen": position.fen,
        "white_ms_left": 300_000, "black_ms_left": 300_000, "increment_ms": 3_000,
        "white_grace_ms": 2_000, "black_grace_ms": 2_000,
        "started_ms": fdServerNowMs,
    ]
    if finished {
        row["result"] = myColor == .white ? "white_win" : "black_win"
        row["end_reason"] = "checkmate"
    } else {
        row["turn"] = position.sideToMove.rawValue
        row["turn_started_ms"] = fdServerNowMs
    }
    return row
}

/// `chess_state` 봉투(= 쓰기 RPC 응답과 같은 모양). `legal_moves` 는 **내 차례일 때만** 싣는다(서버 계약 ⑦).
private func fdStateJSON(matchID: String, ply: Int,
                         _ line: (positions: [ChessPosition], rows: [[String: Any]]),
                         myColor: ChessColor = .white, finished: Bool = false) -> [String: Any] {
    let position = line.positions[ply]
    let isMine = !finished && position.sideToMove == myColor
    return [
        "status": "ok",
        "server_now_ms": fdServerNowMs,
        "match": fdMatchRow(matchID: matchID, ply: ply, position: position,
                            finished: finished, myColor: myColor),
        "moves": Array(line.rows.prefix(ply)),
        "my_color": myColor.rawValue,
        "in_check": finished ? NSNull() : false,
        "legal_moves": isMine ? ChessRules.legalMoves(in: position).map(\.uci).sorted() : NSNull(),
    ]
}

/// `chess_watch` 봉투. **판만이다** — `my_color`·`legal_moves`·`state` 중복 봉투가 없다(서버가 안 싣는다).
private func fdWatchJSON(matchID: String, ply: Int,
                         _ line: (positions: [ChessPosition], rows: [[String: Any]])) -> [String: Any] {
    let position = line.positions[ply]
    return [
        "status": "ok",
        "server_now_ms": fdServerNowMs,
        "match": fdMatchRow(matchID: matchID, ply: ply, position: position,
                            finished: false, myColor: .white),
        "moves": Array(line.rows.prefix(ply)),
        "in_check": false,
    ]
}

@MainActor
private enum FDRetention {
    /// `WorkTimerStore` 는 체스 스토어를 **약참조**로 들린다(순환 참조 금지). 테스트가 버리면 곧바로 해제되어
    /// host 가 nil 이 되고 세션도 사라진다 — `applyState` 가 `my_color` 를 못 읽어 조용히 .ignored 가 된다.
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func fdStore(_ label: String, me: String = fdWhiteID,
                     handler: @escaping GomokuStubProtocol.Handler) -> (ChessStore, String) {
    let host = "v0346-cf-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0346-chess-flight"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    FDRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    // 실루프를 재우고 `pollTick(at:)` 을 직접 밟아 결정적으로 본다(오목·체스 관용구).
    chess.pollStepSeconds = 3_600
    chess.clock = { fdT0 }
    return (chess, host)
}

/// 표에 없는 rpc 는 PGRST202(서버가 그 함수를 아직 모르는 창)로 답한다. 이 스위트의 거의 모든 시험은
/// 요청을 한 건도 내지 않으므로 빈 표가 기본이다 — 요청이 새면 그 자리가 곧 결함이다.
private func fdHandler(_ map: [String: [String]] = [:]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"missing"}"#)
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)])
    }
}

private func fdSerialize(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

/// 애니메이션이 **도는 중인** 1:1 스토어(ply 2 → 3, 잡는 수). 거두는 자리 시험이 자리마다 새 스토어로 재도록
/// 공장으로 둔다 — 한 스토어를 여섯 번 쓰면 첫 자리가 거둔 뒤로는 나머지 다섯이 아무것도 안 잰다.
@MainActor
private func fdRunningPvP(_ label: String, finished: Bool = false) throws -> ChessStore {
    let line = try fdLine(fdOpening)
    let (store, _) = fdStore(label, handler: fdHandler())
    store.isWindowVisible = true
    store.applyState(try fdDecode(ChessStatePayload.self, fdStateJSON(matchID: fdPvPMatch, ply: 2, line)))
    store.applyState(try fdDecode(ChessStatePayload.self,
                                  fdStateJSON(matchID: fdPvPMatch, ply: 3, line, finished: finished)))
    return store
}

@Suite("체스 애니메이션 — 저장소 배선")
struct V0346ChessFlightStoreTests {

    // MARK: - ① 1:1 길(`applyState`) — 첫 적재는 안 미끄러지고, 다음 한 수는 미끄러진다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func pvpMoveStartsAFlightWhileTheFirstLoadDoesNot() async throws {
        // 없으면: 1:1 판의 수가 그대로 순간이동한다(배선이 통째로 빠져도 초록). 그리고 판을 처음 받는 순간
        //        밀린 두 수를 한 장으로 미끄러뜨려 말이 엉뚱한 칸에서 출발한다.
        let line = try fdLine(fdOpening)
        let (store, host) = fdStore("pvp", handler: fdHandler())
        store.isWindowVisible = true

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 2, line)))
        #expect(store.match?.plyCount == 2)
        #expect(store.flight == nil, "첫 적재가 밀린 두 수를 한 장으로 미끄러뜨렸다")

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 3, line)))
        let flight = try #require(store.flight, "1:1 길로 온 수가 여전히 순간이동한다")
        #expect(flight.matchID == fdPvPMatch)
        #expect(flight.ply == 3)
        #expect(flight.generation == 1)
        #expect(flight.startedAt == fdT0)
        #expect(flight.move.uci == "e4d5")
        #expect(flight.sliders.map(\.from.notation) == ["e4"])
        #expect(flight.sliders.map(\.to.notation) == ["d5"])
        #expect(flight.sliders.map(\.piece) == [ChessPiece(.white, .pawn)])

        // 잡힌 말은 **밀려나는 모션**을 받는다 — 사용자가 고쳐 달라고 한 바로 그 증상("말이 갑자기 사라진다").
        let knockout = try #require(flight.knockout, "잡힌 말이 그냥 사라진다 — 아웃시키는 모션이 없다")
        #expect(knockout.square.notation == "d5")
        #expect(knockout.piece == ChessPiece(.black, .pawn))
        // e4 → d5 는 왼쪽 위로 한 칸이다. 잡은 말이 **온 방향을 그대로 이어** 밀려난다.
        #expect(knockout.pushFile == -1)
        #expect(knockout.pushRank == 1)

        // 한 칸 잡기: 미끄러짐 0.175s · 밀림은 그 45% 뒤에 시작해 0.22s 간다 → 전체 0.29875s.
        #expect(abs(flight.slideDuration - 0.175) < 1e-9)
        #expect(abs(flight.duration - 0.29875) < 1e-9)

        // 애니메이션은 **그림 전용**이다 — 세우느라 서버에 뭘 묻지 않는다.
        #expect(GomokuStubProtocol.calls(host: host).isEmpty, "애니메이션 배선이 요청을 냈다")
    }

    // MARK: - ② 로봇 길(`commitAIGame`) — 사람 수와 로봇 수 **둘 다**

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func robotBoardSlidesBothMyMoveAndTheRobotsMove() async throws {
        // 없으면: 로봇 판에서 한쪽만 미끄러진다. 둘은 같은 깔때기(`commitAIGame`)를 지나므로 한 자리만
        //        붙이면 둘 다 되어야 하는데, 사람 수 쪽에만 붙인 배선(예: `moveInAIMatch` 안)도 통과한다.
        let gate = FDRobotGate()
        let (store, host) = fdStore("robot", handler: fdHandler())
        store.isWindowVisible = true
        store.aiRuntime.minimumThinkSeconds = 0
        // 결정적 가짜 엔진 — 언제나 **첫 합법 수**(`ChessRules.legalMoves` 의 순서는 결정적이다).
        // 다만 문이 열릴 때까지 기다린다(위 `FDRobotGate` 머리말).
        store.aiMoveChooser = { position, _ in
            await gate.waitUntilOpen()
            return ChessRules.legalMoves(in: position).first
        }

        store.startAIMatch(humanColor: .white)
        let opened = try #require(store.match)
        #expect(opened.id.hasPrefix(ChessAIGame.idPrefix))
        #expect(store.flight == nil, "판이 열린 것은 수가 아니다 — 첫 적재가 미끄러졌다")

        await store.tap(try fdSquare("e2"))
        await store.tap(try fdSquare("e4"))
        #expect(store.match?.plyCount == 1)
        let mine = try #require(store.flight, "로봇 판에서 **내** 수가 순간이동한다")
        #expect(mine.matchID == opened.id)
        #expect(mine.ply == 1)
        #expect(mine.generation == 1)
        #expect(mine.move.uci == "e2e4")
        #expect(mine.sliders.map(\.to.notation) == ["e4"])
        #expect(mine.knockout == nil, "잡기 없는 수인데 밀려나는 말이 섰다")
        // 두 칸 전진: 0.15 + 2 × 0.025 = 0.20s. 잡기가 없으면 전체 길이가 미끄러짐과 같다.
        #expect(abs(mine.slideDuration - 0.20) < 1e-9)
        #expect(mine.duration == mine.slideDuration)

        await gate.open()
        await fdWait { store.flight?.ply == 2 }
        let robots = try #require(store.flight, "로봇의 수가 순간이동한다 — 같은 깔때기인데 한쪽만 붙었다")
        #expect(robots.matchID == opened.id)
        #expect(robots.ply == 2)
        #expect(robots.generation == 2, "로봇 수가 새 꼬리표를 못 받았다")
        #expect(store.match?.plyCount == 2)
        #expect(store.match?.turn == .white)
        #expect(robots.sliders.map(\.piece.color) == [.black])

        #expect(GomokuStubProtocol.calls(host: host).isEmpty, "로봇 판이 서버로 나갔다")
    }

    // MARK: - ③ 관전 길(`applyWatch`) — 들어간 첫 응답은 안 미끄러진다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func spectatingSlidesTheNextMoveWhileTheEntryResponseDoesNot() async throws {
        // 없으면: 관전으로 보는 판의 수가 순간이동한다(대국 쪽만 붙인 배선이 통과한다). 그리고 관전에
        //        들어간 순간 받은 판을 '한 수 나아간 것' 으로 읽어 엉뚱한 칸에서 말이 출발한다.
        let line = try fdLine(fdOpening)
        let (store, host) = fdStore("watch", handler: fdHandler())
        store.spectatorFeaturesEnabled = true
        // ★ 창이 아직 안 보이는 동안 들어간다 — `canPollSpectatorFeatures` 가 거짓이라 진입이 조회를 쏘지
        //   않고, 그래서 `applyWatch` 만 손으로 밟아 결정적으로 잴 수 있다.
        store.startWatching(matchID: fdWatchMatch)
        #expect(store.spectating?.id == fdWatchMatch)
        #expect(store.spectating?.position == nil, "씨앗에 판 내용이 생겼다 — 아래 '첫 응답' 단언이 공허해진다")
        store.isWindowVisible = true

        store.applyWatch(try fdDecode(ChessWatchResponse.self, fdWatchJSON(matchID: fdWatchMatch,
                                                                           ply: 1, line)))
        #expect(store.spectating?.plyCount == 1)
        #expect(store.flight == nil, "관전 첫 응답이 미끄러졌다 — 그 수의 **이전 국면**을 앱은 본 적이 없다")

        store.applyWatch(try fdDecode(ChessWatchResponse.self, fdWatchJSON(matchID: fdWatchMatch,
                                                                           ply: 2, line)))
        let flight = try #require(store.flight, "관전 길로 온 수가 순간이동한다")
        #expect(flight.matchID == fdWatchMatch)
        #expect(flight.ply == 2)
        #expect(flight.move.uci == "d7d5")
        #expect(flight.sliders.map(\.from.notation) == ["d7"])
        #expect(flight.sliders.map(\.to.notation) == ["d5"])
        #expect(flight.knockout == nil, "잡기 없는 수인데 밀려나는 말이 섰다")
        #expect(GomokuStubProtocol.calls(host: host).isEmpty, "관전 배선이 요청을 냈다")
    }

    // MARK: - ④ 두 수를 한꺼번에 받으면 안 만든다(그리고 한 수만 더 오면 만든다)

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aTwoPlyCatchUpNeverSlidesButTheNextSinglePlyDoes() async throws {
        // 없으면: 기기가 잠들었다 깨어나 두 수를 한 번에 받을 때 **마지막 수만** 미끄러져, 말이 전혀 없던
        //        칸에서 출발한다(그 사이 수의 국면을 앱은 본 적이 없다).
        let line = try fdLine(fdOpening)
        let (store, _) = fdStore("jump", handler: fdHandler())
        store.isWindowVisible = true

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 1, line)))
        #expect(store.match?.plyCount == 1)
        #expect(store.flight == nil)

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 3, line)))
        #expect(store.match?.plyCount == 3, "판은 따라잡아야 한다 — 거절은 애니메이션만이다")
        #expect(store.flight == nil, "두 수를 한 장으로 미끄러뜨렸다")

        // ★ 기준선: **같은 스토어**에서 한 수만 더 오면 만든다(이게 없으면 위 단언은 영원히 nil 을 보고 초록이다).
        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 4, line)))
        let flight = try #require(store.flight, "따라잡은 뒤로는 애니메이션이 영영 안 산다")
        #expect(flight.ply == 4)
        #expect(flight.move.uci == "d8d5")
        #expect(flight.knockout?.square.notation == "d5")
    }

    // MARK: - ⑤ 수 번호가 그대로인 폴링 응답은 세우지도, 돌고 있는 것을 덮지도 않는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func repeatedPollResponsesNeitherStartNorRestartARunningFlight() async throws {
        // 없으면: 1.5초 주기 폴링이 같은 수를 **영원히** 다시 미끄러뜨린다(상대가 생각하는 동안 내 판의 말이
        //        계속 날아다닌다). 또는 되읽은 응답마다 시작 시각이 밀려 애니메이션이 끝나지 않는다.
        let line = try fdLine(fdOpening)
        let clock = FDClock(fdT0)
        let (store, _) = fdStore("poll", handler: fdHandler())
        store.clock = { clock.now }
        store.isWindowVisible = true

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 1, line)))
        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 2, line)))
        let first = try #require(store.flight)
        #expect(first.startedAt == fdT0)

        // 0.05초 지난 폴링 응답 셋 — 수 번호가 그대로다. 시계를 밀어야 '다시 세웠는가' 가 보인다.
        clock.now = fdT0.addingTimeInterval(0.05)
        let repeated = try fdDecode(ChessStatePayload.self, fdStateJSON(matchID: fdPvPMatch, ply: 2, line))
        for _ in 0..<3 { store.applyState(repeated) }

        let same = try #require(store.flight, "폴링 응답이 돌고 있는 애니메이션을 지웠다")
        #expect(same == first, "수 번호가 그대로인 폴링 응답이 애니메이션을 다시 세웠다")
        #expect(same.startedAt == fdT0)
        #expect(same.generation == 1)
    }

    // MARK: - ⑥ 창이 안 보이거나 가려지면 안 만든다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func anInvisibleOrOccludedWindowNeverStartsAFlight() async throws {
        // 없으면: 보이지도 않는 창 때문에 뷰의 `TimelineView` 가 60fps 로 깨어 배터리를 먹는다
        //        (`paused: flight == nil` 이 배터리 계약이고, 그 계약은 저장소가 지킨다).
        let line = try fdLine(fdOpening)
        func advanced(_ label: String, configure: (ChessStore) -> Void) throws -> ChessStore {
            let (store, _) = fdStore(label, handler: fdHandler())
            configure(store)
            store.applyState(try fdDecode(ChessStatePayload.self,
                                          fdStateJSON(matchID: fdPvPMatch, ply: 2, line)))
            store.applyState(try fdDecode(ChessStatePayload.self,
                                          fdStateJSON(matchID: fdPvPMatch, ply: 3, line)))
            return store
        }

        let hidden = try advanced("win-hidden") { $0.isWindowVisible = false }
        #expect(hidden.match?.plyCount == 3, "판은 갱신돼야 한다 — 창 규칙은 애니메이션만 막는다")
        #expect(hidden.flight == nil, "창이 안 보이는데 애니메이션이 섰다")

        let occluded = try advanced("win-occluded") {
            $0.isWindowVisible = true
            $0.windowOcclusionDidChange(visible: false)
        }
        #expect(occluded.isWindowVisible, "가림 통지는 보임 깃발을 건드리지 않는다")
        #expect(occluded.match?.plyCount == 3)
        #expect(occluded.flight == nil, "창이 가려졌는데 애니메이션이 섰다")

        // ★ 기준선: 셋째 갈래(보이고 안 가려짐)는 **만든다**.
        let shown = try advanced("win-shown") { $0.isWindowVisible = true }
        #expect(shown.flight?.ply == 3)
    }

    // MARK: - ⑦ 길이가 지나면 저절로 거둬진다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theFlightReapsItselfOnceItsDurationHasPassed() async throws {
        // 없으면: 애니메이션 값이 영영 남아 뷰가 60fps 로 계속 돈다(끝난 수는 그려지지도 않으면서).
        let store = try fdRunningPvP("reap")
        let running = try #require(store.flight)

        // 끝 판정의 경계는 **열려 있다**(`>`): `duration` 에 정확히 닿은 프레임은 아직 그려야 한다
        // (잡기 없는 수는 `duration == slideDuration` 이라 닫으면 t=1 프레임이 한 번도 안 그려진다).
        #expect(!running.isFinished(now: fdT0.addingTimeInterval(running.duration)))
        #expect(running.isFinished(now: fdT0.addingTimeInterval(running.duration + 0.001)))

        await fdWait { store.flight == nil }
        #expect(store.flight == nil, "길이가 지났는데 아무도 값을 안 거뒀다")
    }

    // MARK: - ⑧ 세대 — 늦게 깬 옛 Task 가 새 애니메이션을 지우지 않는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aSecondMoveReplacesTheFirstAndTheFirstsTaskDoesNotEraseIt() async throws {
        // 없으면: 빠르게 두는 판에서 **두 수째부터** 애니메이션이 한 프레임만 보이고 사라진다.
        //        `beginFlight` 가 앞 Task 를 취소하는데 `try? await Task.sleep` 은 취소를 삼키고 다음 줄로
        //        내려가므로(던지지 않는다), 취소된 Task 도 몸통을 한 번 실행한다 — 꼬리표 비교가 그 한 번을 막는다.
        let line = try fdLine(fdOpening)
        let (store, _) = fdStore("generation", handler: fdHandler())
        store.isWindowVisible = true

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 1, line)))
        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 2, line)))
        let a = try #require(store.flight)
        #expect(a.ply == 2)
        #expect(a.generation == 1)

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 3, line)))
        let b = try #require(store.flight)
        #expect(b.ply == 3)
        #expect(b.generation == 2, "새 수가 새 꼬리표를 못 받았다 — 그러면 옛 Task 가 자기 것으로 착각한다")

        // 취소된 A 의 Task 는 **곧바로** 깨어난다(잠을 다 자지 않는다). 그 한 번이 돌 틈을 준다 —
        // 20ms 는 B 의 길이(0.29875s)보다 한참 짧으므로 B 가 스스로 거둬질 틈은 없다.
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<20 { await Task.yield() }

        let alive = try #require(store.flight, "수 A 의 Task 가 깨어나 수 B 의 애니메이션을 지웠다")
        #expect(alive == b)
        #expect(alive.generation == 2)
    }

    // MARK: - ⑨ 거두는 자리 일곱 전부

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func allSevenClearSitesDropTheFlight() async throws {
        // 없으면: 로그아웃·판 내림·로비 접기·창 닫기·창 숨김·관전 종료 뒤에도 값이 남아, 뷰가 그만큼 더
        //        60fps 로 깨어 있고 창을 다시 연 사람에게는 끝나던 수의 토막이 다시 미끄러진다.
        //        로그아웃은 그 위에 한 겹 더다 — 다음 사람 화면에 앞 사람 판의 말이 날아가면 안 된다.
        let viaReset = try fdRunningPvP("clear-reset")
        #expect(viaReset.flight != nil)
        viaReset.reset()
        #expect(viaReset.flight == nil, "로그아웃했는데 앞 사람 판의 말이 날아간다")

        let viaClearMatch = try fdRunningPvP("clear-match")
        #expect(viaClearMatch.flight != nil)
        viaClearMatch.clearMatch()
        #expect(viaClearMatch.flight == nil, "판을 내렸는데 애니메이션이 남았다")

        // [로비로] 는 **끝난 판에서만** 동작한다 — 그래서 끝난 수가 미끄러지는 중인 스토어로 잰다.
        // (외통으로 끝난 판의 그 수가 안 보이면 왜 끝났는지 모르므로 결과 화면도 미끄러진다.)
        let viaLobby = try fdRunningPvP("clear-lobby", finished: true)
        #expect(viaLobby.match?.isFinished == true)
        #expect(viaLobby.flight != nil, "끝낸 그 수가 결과 화면에서 안 미끄러진다")
        viaLobby.backToLobby()
        #expect(viaLobby.flight == nil, "로비로 돌아왔는데 애니메이션이 남았다")

        let viaClose = try fdRunningPvP("clear-close")
        #expect(viaClose.flight != nil)
        viaClose.windowDidClose()
        #expect(viaClose.flight == nil, "창을 닫았는데 애니메이션이 남았다")

        let viaHide = try fdRunningPvP("clear-hide")
        #expect(viaHide.flight != nil)
        viaHide.windowDidHide()
        #expect(viaHide.flight == nil, "창을 숨겼다 다시 열면 끝나던 수의 토막이 다시 미끄러진다")

        // 관전 종료. 관전 길의 애니메이션을 세워 두고 [나가기] 의 몸통(`stopWatching`)으로 거둔다.
        let line = try fdLine(fdOpening)
        let (viaWatch, _) = fdStore("clear-watch", handler: fdHandler())
        viaWatch.spectatorFeaturesEnabled = true
        viaWatch.startWatching(matchID: fdWatchMatch)
        viaWatch.isWindowVisible = true
        viaWatch.applyWatch(try fdDecode(ChessWatchResponse.self,
                                         fdWatchJSON(matchID: fdWatchMatch, ply: 1, line)))
        viaWatch.applyWatch(try fdDecode(ChessWatchResponse.self,
                                         fdWatchJSON(matchID: fdWatchMatch, ply: 2, line)))
        #expect(viaWatch.flight != nil)
        viaWatch.stopWatching()
        #expect(viaWatch.spectating == nil)
        #expect(viaWatch.flight == nil, "관전을 나왔는데 남의 판 애니메이션이 남았다")

        // 일곱 번째 — 창이 **가려졌다**(다른 창이 덮었다). 숨김과 달리 창은 열려 있지만 그려지지는 않는다.
        // 없으면: 가림 뒤에서 꼬리만큼(최대 0.355초) 60~78Hz 그리기를 계속 요구한다. 아무도 안 보는 그림이다.
        let viaOcclude = try fdRunningPvP("clear-occlude")
        #expect(viaOcclude.flight != nil)
        viaOcclude.windowOcclusionDidChange(visible: false)
        #expect(viaOcclude.isWindowOccluded)
        #expect(viaOcclude.flight == nil, "가려진 창 뒤에서 애니메이션이 계속 돈다")

        // ★ 기준선이 갈린다: **다시 보이면** 거두지 않는다(그 길에는 `clearFlight()` 가 없다).
        //   둘 다 거두면 "언제나 nil" 로 굳은 것이고 그러면 위 단언이 아무것도 안 잰다.
        let viaReveal = try fdRunningPvP("clear-reveal")
        #expect(viaReveal.flight != nil)
        viaReveal.windowOcclusionDidChange(visible: true)
        #expect(viaReveal.isWindowOccluded == false)
        #expect(viaReveal.flight != nil, "창이 다시 보이는데 날던 수를 거뒀다")
    }

    // MARK: - ⑩ 입력이 안 막힌다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func inputIsNotBlockedWhileAFlightRuns() async throws {
        // 없으면: 애니메이션이 도는 0.2~0.35초 동안 탭이 씹힌다(입력 잠금을 몰래 끼워 넣어도 초록이다).
        //        5분 블리츠에서 빠르게 두는 사람의 수가 그대로 사라진다.
        let line = try fdLine(fdOpening)
        /// 상대 수(ply 2)까지 받은 스토어 — 내 차례이고, `flying` 이면 그 수가 미끄러지는 중이다.
        func ready(_ label: String, flying: Bool) throws -> (ChessStore, String) {
            let move = fdSerialize(fdStateJSON(matchID: fdPvPMatch, ply: 3, line))
            let (store, host) = fdStore(label, handler: fdHandler(["chess_move": [move]]))
            store.isWindowVisible = flying
            store.applyState(try fdDecode(ChessStatePayload.self,
                                          fdStateJSON(matchID: fdPvPMatch, ply: 1, line)))
            store.applyState(try fdDecode(ChessStatePayload.self,
                                          fdStateJSON(matchID: fdPvPMatch, ply: 2, line)))
            return (store, host)
        }

        let (flying, flyingHost) = try ready("input-flying", flying: true)
        let (still, stillHost) = try ready("input-still", flying: false)
        // ★ 기준선이 갈린다: 한쪽만 애니메이션이 돈다.
        #expect(flying.flight?.ply == 2)
        #expect(still.flight == nil)
        #expect(flying.match?.isMyTurn == true)

        // 1단 — 말 고르기.
        await flying.tap(try fdSquare("e4"))
        await still.tap(try fdSquare("e4"))
        let picked = try #require(flying.selection, "애니메이션이 도는 동안 말이 안 골라진다")
        #expect(picked == still.selection, "애니메이션이 있을 때와 없을 때 고르기가 다르다")
        #expect(picked.targets.contains(try fdSquare("d5")))
        #expect(flying.flight != nil, "탭이 애니메이션을 지웠다")

        // 2단 — 도착 칸. 수가 **실제로 서버로 나가는지**를 잰다(요청 수가 그 결과다).
        await flying.tap(try fdSquare("d5"))
        await still.tap(try fdSquare("d5"))
        #expect(GomokuStubProtocol.count(host: flyingHost, rpc: "chess_move") == 1,
                "애니메이션이 도는 동안 둔 수가 씹혔다")
        #expect(GomokuStubProtocol.count(host: stillHost, rpc: "chess_move") == 1)
        #expect(GomokuStubProtocol.calls(host: flyingHost, rpc: "chess_move").first?.json["p_uci"] as? String
                == "e4d5")
        #expect(flying.match?.plyCount == 3)
        #expect(flying.match == still.match, "애니메이션이 입력 결과를 갈랐다")
        #expect(flying.selection == nil)
        #expect(!flying.isBusy)
    }

    // MARK: - ⑪ 판정에 영향이 없다 — `flight` 만 다르다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aRunningFlightChangesNothingTheGameLogicReads() async throws {
        // 없으면: 애니메이션을 세우는 자리가 판·차례·합법 수·시계를 슬쩍 건드려도(예: 도착 칸의 말을 숨기려고
        //        `position` 을 고치거나 시계를 멈춰) 초록이다. `flight` 는 **그림 전용**이라는 계약이 그물 없이 남는다.
        let line = try fdLine(fdOpening)
        func advanced(_ label: String, visible: Bool) throws -> ChessStore {
            let (store, _) = fdStore(label, handler: fdHandler())
            store.isWindowVisible = visible
            store.applyState(try fdDecode(ChessStatePayload.self,
                                          fdStateJSON(matchID: fdPvPMatch, ply: 1, line)))
            store.applyState(try fdDecode(ChessStatePayload.self,
                                          fdStateJSON(matchID: fdPvPMatch, ply: 2, line)))
            return store
        }

        let flying = try advanced("logic-flying", visible: true)
        let still = try advanced("logic-still", visible: false)
        // ★ 기준선이 갈린다: 같은 응답인데 한쪽만 애니메이션이 섰다.
        #expect(flying.flight?.ply == 2)
        #expect(still.flight == nil)

        // 판 전체가 **값으로 같다**(`ChessMatchState` 는 Equatable — fen·국면·차례·시계·합법 수·기보가 다 들어 있다).
        #expect(flying.match == still.match)
        let mine = try #require(flying.match)
        #expect(mine.fen == still.match?.fen)
        #expect(mine.position == still.match?.position)
        #expect(mine.legalMoves.map(\.uci) == still.match?.legalMoves.map(\.uci))
        #expect(mine.isMyTurn == still.match?.isMyTurn)
        #expect(mine.isMyTurn)
        #expect(mine.clock == still.match?.clock)
        let flyingPair = try #require(flying.remainingSecondsPair(now: fdT0))
        let stillPair = try #require(still.remainingSecondsPair(now: fdT0))
        #expect(flyingPair.mine == stillPair.mine)
        #expect(flyingPair.opponent == stillPair.opponent)
        #expect(flying.targets(from: try fdSquare("e4")) == still.targets(from: try fdSquare("e4")))
        #expect(flying.phase == still.phase)
        #expect(flying.notice == still.notice)

        // 그리고 애니메이션이 도는 판의 도착 칸에는 **말이 이미 서 있다** — 뷰가 `hidden` 으로 가릴 뿐이다.
        // (판을 고쳐 말을 빼는 길로 갔으면 여기가 빨개진다.)
        #expect(mine.position?[try fdSquare("d5")] == ChessPiece(.black, .pawn))
    }

    // MARK: - ⑫ 판이 바뀐 것은 애니메이션이 아니다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func switchingToADifferentMatchNeverSlides() async throws {
        // 없으면: 다른 판으로 넘어가는 순간(신청 수락·관전에서 내 판으로)이 애니메이션이 되어, 앞 판의 말이
        //        새 판의 엉뚱한 칸으로 날아간다. 수 번호만 보는 배선은 ply 가 +1 이면 이걸 구분하지 못한다.
        let line = try fdLine(fdOpening)
        let (store, _) = fdStore("swap", handler: fdHandler())
        store.isWindowVisible = true

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 1, line)))
        #expect(store.match?.id == fdPvPMatch)

        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdOtherMatch, ply: 2, line)))
        #expect(store.match?.id == fdOtherMatch, "판은 바뀌어야 한다 — 거절은 애니메이션만이다")
        #expect(store.match?.plyCount == 2)
        #expect(store.flight == nil, "판이 바뀐 것을 애니메이션으로 읽었다")

        // ★ 기준선: 새 판에서 한 수 더 오면 만든다.
        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdOtherMatch, ply: 3, line)))
        #expect(store.flight?.matchID == fdOtherMatch)
        #expect(store.flight?.ply == 3)
    }

    // MARK: - ⑬ 파생이 nil 인 수 하나가 돌고 있는 애니메이션을 **버려두지 않는다**

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aMoveThatCannotBeDerivedNeitherReplacesNorStrandsTheRunningFlight() async throws {
        // 없으면: 꼬리표를 `make` **전에** 올려도 48건이 전부 초록이다(실측 2026-10-06). 그때 파생이 nil 인
        //        수 하나가 돌고 있는 애니메이션의 거두기 Task 를 꼬리표만으로 무력화한다(그 Task 는 옛 세대가
        //        되어 그냥 `return` 한다) → `flight` 가 **영영 안 거둬지고** 뷰의 `TimelineView` 가
        //        `paused: flight == nil` 이 거짓인 채로 주사율대로 계속 돈다(그리는 것은 아무것도 없이).
        //        그게 사양 ①이 막으려던 바로 그 배터리 사고다.
        let store = try fdRunningPvP("strand")
        let running = try #require(store.flight)
        #expect(running.ply == 3)
        #expect(running.generation == 1)

        // 가드 ①~④ 를 **전부 지나고** ⑤(파생 nil)에서만 떨어지는 수 하나. a1 에는 백 룩이 서 있고(출발 칸 있음)
        // a3 은 비어 있다(`after[move.to] == nil`) — 서버 FEN 과 수가 어긋난 응답의 꼴이다.
        let position = try #require(store.match?.position)
        #expect(position[try fdSquare("a1")] == ChessPiece(.white, .rook), "전제: a1 에 백 룩")
        #expect(position[try fdSquare("a3")] == nil, "전제: a3 은 비어 있다")
        // ★ 수를 **먼저 받아 둔다**. `move:` 가 옵셔널이라 인자 자리에 `#require` 를 바로 쓰면 매크로가
        //   한 겹만 벗기고 nil 을 통과시킨다 — 그러면 거절 ⑤(파생 nil) 가 아니라 ④(수 없음)에서 떨어져
        //   이 시험이 재려던 자리를 한 번도 안 밟는다.
        let undeliverable = try #require(ChessMove(uci: "a1a3"))
        store.beginFlight(matchID: fdPvPMatch, previousMatchID: fdPvPMatch, previousPly: 3,
                          previousPosition: position, nextPly: 4, nextPosition: position,
                          move: undeliverable)
        #expect(store.flight == running, "파생이 nil 인 수가 돌고 있는 애니메이션을 갈아 치웠다")

        // ★ 여기가 무는 자리다: 그래도 **스스로 거둬진다**(꼬리표가 안 밀렸으므로 옛 Task 가 제 것으로 알아본다).
        await fdWait { store.flight == nil }
        #expect(store.flight == nil,
                "파생이 nil 인 수가 꼬리표를 올려 돌고 있던 애니메이션이 영영 안 거둬진다 — 뷰가 계속 깨어 있다")

        // ★ 그리고 꼬리표를 **먹지 않았다**: 다음 진짜 수가 2 를 받는다(3 이면 nil 수가 하나 먹었다는 뜻이다).
        let line = try fdLine(fdOpening)
        store.applyState(try fdDecode(ChessStatePayload.self,
                                      fdStateJSON(matchID: fdPvPMatch, ply: 4, line)))
        let next = try #require(store.flight, "따라오는 진짜 수가 안 미끄러진다")
        #expect(next.ply == 4)
        #expect(next.generation == 2, "파생이 nil 인 수가 꼬리표를 먹었다(지금 \(next.generation))")
    }
}
