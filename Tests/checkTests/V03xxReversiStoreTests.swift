import Foundation
import Observation
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기(reversi) 스토어(`ReversiStore`) 계약 — 갈래 C2. 출시 버전이 정해지면 `git mv` + `@Suite` 이름을 함께 바꾼다.
// **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁이고 **응답 본문은 서버 갈래 픽스처 원문**이다(`Fixtures/reversi-rpc/*.json` — 하네스 Postgres 에 마이그레이션을 올려
// RPC 를 실제로 부른 jsonb, `FLIP/server/fixtures` 복사). 원문으로 못 만드는 장면(같은 판의 다른 수 번호 · 진부분집합 합법 수 ·
// 늦은 응답)은 원문을 읽어 **한 칸만** 바꿔 쓴다 — 바꾼 칸은 시험마다 적었다.
//
// 하네스는 오목 것을 **그대로 쓴다**(`GomokuStubProtocol` · `GomokuTestDefaults`). 스토어는 아직 `WorkTimerStore` 가 소유하지 않으므로
// (배선은 갈래 T) 시험이 `attach(host:)` 로 물린다. host 는 약참조라 소유자를 붙잡아 둔다(`RVRetention`).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다. 결과가 갈리는 기준선을 같은 시험 안에 둔다.

// MARK: - 하네스 (같은 모듈의 리버시 시험 파일들이 같이 쓴다)

let rvFixtureDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/reversi-rpc", isDirectory: true)

/// 픽스처의 두 사람(매니페스트 `viewers.A`·`B` — 고정 uuid). A 가 신청자다. 흑백은 수락 때 서버가 무작위로 정하므로
/// **다시 뽑으면 바뀔 수 있다** — 흑을 전제하는 시험은 `rvViewer` 로 전제를 먼저 `#require` 한다(지금 사본은 B 흑).
let rvA = "b0000000-0000-4000-8000-000000000001"
let rvB = "b0000000-0000-4000-8000-000000000002"
/// 픽스처 b_flow 의 주 판 id. **실행마다 바뀌는 값**이라 원문에서 읽는다(매니페스트 notes).
let rvMainMatch: String = {
    guard let data = try? Data(contentsOf: rvFixtureDirectory.appendingPathComponent("reversi_state__my_turn.json")),
          let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let state = top["state"] as? [String: Any], let match = state["match"] as? [String: Any],
          let id = match["id"] as? String else { return "(픽스처 없음)" }
    return id
}()

struct RVError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 픽스처 **원문**(서버가 낸 글자 그대로).
func rvText(_ name: String) throws -> String {
    try String(contentsOf: rvFixtureDirectory.appendingPathComponent("\(name).json"), encoding: .utf8)
}

func rvJSON(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: rvFixtureDirectory.appendingPathComponent("\(name).json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RVError("\(name) 는 JSON 객체가 아니다")
    }
    return object
}

/// 그 픽스처를 **누가 불렀는가**(매니페스트 `files[].viewer`). 시험 세션의 user id 가 이 사람이어야 내 색·신청 방향이 맞는다.
func rvViewer(_ name: String) throws -> String {
    let manifest = try rvJSON("_manifest")
    guard let files = manifest["files"] as? [[String: Any]],
          let entry = files.first(where: { ($0["file"] as? String) == "\(name).json" }),
          let viewer = entry["viewer"] as? String else {
        throw RVError("\(name): 매니페스트에 viewer 가 없다")
    }
    return viewer
}

func rvSerialize(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

/// 원문을 읽어 한 곳만 바꾼 본문(`state` 봉투 안을 고친다).
func rvMutatedState(_ name: String, _ edit: (inout [String: Any]) -> Void) throws -> String {
    var top = try rvJSON(name)
    var state = try #require(top["state"] as? [String: Any], "\(name): state 없음")
    edit(&state)
    top["state"] = state
    return rvSerialize(top)
}

/// 원문을 읽어 최상위만 바꾼 본문.
func rvMutated(_ name: String, _ edit: (inout [String: Any]) -> Void) throws -> String {
    var top = try rvJSON(name)
    edit(&top)
    return rvSerialize(top)
}

/// 앱 디코더와 같은 설정(`.convertFromSnakeCase`).
func rvDecode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(text.utf8))
}

func rvState(_ name: String) throws -> ReversiStatePayload {
    try #require(try rvDecode(ReversiActionResponse.self, try rvText(name)).state, "\(name): state 없음")
}

func rvStateText(_ text: String) throws -> ReversiStatePayload {
    try #require(try rvDecode(ReversiActionResponse.self, text).state, "state 없음")
}

/// 서버에 그 함수가 아직 없을 때 PostgREST 가 내는 **실제 404 본문 모양**("schema cache" 가 `.databaseSchemaMissing` 으로 접힌다).
func rvPGRST202(_ function: String) -> String {
    #"{"code":"PGRST202","details":"Searched for the function public."# + function
        + #" with parameters, but no matches were found in the schema cache.","hint":null,"#
        + #""message":"Could not find the function public."# + function
        + #" in the schema cache"}"#
}

/// rpc 이름 → 응답 본문 목록(같은 rpc 의 n 번째 호출이 n 번째 본문, 모자라면 마지막이 반복). 표에 없는 rpc 는 PGRST202.
func rvHandler(_ map: [String: [String]], delays: [String: TimeInterval] = [:]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(status: 404, body: rvPGRST202(rpc))
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)], delay: delays[rpc] ?? 0)
    }
}

@MainActor
enum RVRetention {
    /// 스토어는 host 를 **약참조**로 든다 — 시험이 버리면 곧바로 해제되어 요청이 한 건도 안 나간다(오목에서 실제로 데였다).
    static var owners: [WorkTimerStore] = []
}

/// 움직일 수 있는 시험 시계.
final class RVClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ date: Date) {
        lock.lock()
        value = date
        lock.unlock()
    }
    func advance(_ seconds: TimeInterval) { set(now.addingTimeInterval(seconds)) }
}

/// 리버시 스토어 한 벌 + 스텁 호스트 이름. `me` 는 픽스처를 부른 사람이어야 한다(`rvViewer`).
@MainActor
func makeReversiStore(
    _ label: String, me: String, clock: RVClock? = nil, handler: @escaping GomokuStubProtocol.Handler
) -> (ReversiStore, String) {
    let host = "v03xx-rv-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let defaults = GomokuTestDefaults.make("v03xx-reversi")
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults, workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    RVRetention.owners.append(owner)
    let store = clock.map { box in ReversiStore(clock: { box.now }) } ?? ReversiStore()
    store.attach(host: owner)
    // 실루프를 재우고 `pollTick(at:)` 을 직접 밟아 결정적으로 본다(오목·체스 관용구).
    store.pollStepSeconds = 3_600
    store.aiRuntime.minimumThinkSeconds = 0
    return (store, host)
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 시험이 메인 액터를 오래 쥔다).
@MainActor
func rvWait(_ resumes: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 서버 시각(ms) → 그 순간의 Date.
func rvDate(ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

// MARK: - 시험

@Suite("아잉 뒤집기 스토어 — 서버 픽스처 원문을 먹였을 때의 결과")
@MainActor
struct V03xxReversiStoreTests {

    // MARK: ① 받은 쪽 흐름

    @Test(.gomokuDefaultsCleanup)
    func 로비_신청_수락_착수_신호_패스_끝_결과_로비() async throws {
        // 없으면: 로비가 받은 신청을 안 세우거나 · 수락이 판을 안 열거나 · 착수가 응답 전에 판을 그리거나(낙관적) ·
        // 신호가 구멍 난 기록을 그대로 그리거나 · 패스를 말하지 않거나 · 끝난 판이 결과/미션 꼬리를 안 내도 초록이다.
        // 전제: 받은 쪽(B)이 흑으로 뽑힌 원문이다(흑이 바뀐 재생성이면 여기서 멈춘다 — 시험을 원문에 맞춰 다시 짤 것).
        for name in ["reversi_lobby__incoming", "reversi_respond__accepted", "reversi_move__ok",
                     "reversi_move__ok_pass", "reversi_move__finished_board_full"] {
            try #require(try rvViewer(name) == rvB, "\(name): 시청자가 B 가 아니다")
        }
        try #require(try rvState("reversi_respond__accepted").myColor == .black, "B 가 흑이 아닌 원문이다")
        let (store, host) = makeReversiStore("flow", me: rvB, handler: rvHandler(
            [
                "reversi_lobby": [try rvText("reversi_lobby__incoming"), try rvText("reversi_lobby__ok")],
                "reversi_respond": [try rvText("reversi_respond__accepted")],
                // ① 내 첫 수 · ② 패스 뒤 내 수(판을 끝낸다)
                "reversi_move": [try rvText("reversi_move__ok"), try rvText("reversi_move__finished_board_full")],
                // 신호 조회: since=1 로 물으면 seq 3·4 만 온다(구멍) → 처음부터 한 번 더
                "reversi_state": [try rvText("reversi_move__ok_pass")],
            ],
            delays: ["reversi_move": 0.3]))
        var arrived: [String] = []
        var finished = 0
        store.onInviteArrived = { arrived.append($0.id) }
        store.onMatchFinished = { finished += 1 }

        await store.refreshLobby()
        #expect(store.phase == .lobby)
        #expect(store.availability == .available)
        #expect(store.incoming.map(\.id) == [rvMainMatch])
        #expect(store.visibleIncoming?.peer.id == rvA)
        #expect(store.visibleIncoming?.stake == 5)
        #expect(arrived == [rvMainMatch])
        #expect(store.users.contains { $0.id == rvA && $0.isCapable })
        #expect(store.users.contains { !$0.isCapable })          // capable false 행도 그대로 실린다(화면이 잠근다)
        #expect(store.record == ReversiRecord(wins: 0, losses: 0, draws: 0))
        #expect(store.rubyBalance == 100)

        await store.respond(inviteID: rvMainMatch, accept: true)
        #expect(store.phase == .playing)
        let opened = try #require(store.match)
        #expect(opened.id == rvMainMatch)
        #expect(opened.myColor == .black)
        #expect(opened.isMyTurn)
        #expect(store.legalTargets == [19, 26, 37, 44])
        #expect(store.incoming.isEmpty)
        #expect(store.visibleIncoming == nil)
        #expect(store.rubyBalance == 95)                          // 수락 순간 판돈 차감(서버 값)
        #expect(store.notice == nil)                              // 수락 성공은 말하지 않는다(판이 답한다)
        #expect(store.defersMegaphoneBanner)

        // 착수 — 응답(0.3초 지연)이 오기 **전에는** 판이 그대로다(낙관적 그림 없음).
        let placing = Task { await store.place(19) }
        await rvWait { store.isBusy }
        #expect(store.isBusy)
        #expect(store.match?.board == .start)
        #expect(store.match?.moveCount == 0)
        await placing.value
        #expect(store.match?.moveCount == 1)
        #expect(store.match?.board[19] == .black)
        #expect(store.match?.board[27] == .black)                 // 뒤집힌 돌
        #expect(store.match?.lastStoneIdx == 19)
        #expect(store.match?.isMyTurn == false)
        #expect(store.legalTargets.isEmpty)
        #expect(store.isBusy == false)
        let moveBody = try #require(GomokuStubProtocol.calls(host: host, rpc: "reversi_move").first?.json)
        #expect(moveBody["p_expected_seq"] as? Int == 0)
        #expect(moveBody["p_idx"] as? Int == 19)
        #expect(moveBody["p_protocol"] as? Int == ReversiWire.protocolVersion)

        // 상대 차례에 또 누르면 요청 없이 문구만.
        await store.place(26)
        #expect(store.notice == ReversiNoticeText.notYourTurn)
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_move") == 1)

        // 신호 → 그 판 조회(since=1). 온 기록이 seq 3 부터라 구멍 — 처음부터(since=0) 한 번 더 받아 다시 짓는다.
        store.handleSignal()
        await rvWait { store.match?.moveCount == 4 }
        let stateCalls = GomokuStubProtocol.calls(host: host, rpc: "reversi_state")
        #expect(stateCalls.map { $0.json["p_since_seq"] as? Int } == [1, 0])
        #expect(store.match?.moveCount == 4)
        #expect(store.match?.isMyTurn == true)
        #expect(store.legalTargets == [58])
        #expect(store.match?.plies.map(\.seq) == [3, 4])
        // 상대(백)가 둘 곳이 없어 내 차례가 이어진다 — 상태줄이 말한다.
        #expect(store.notice == ReversiNoticeText.opponentPassed(name: "비시험01"))

        // 판을 끝내는 수 — 결과 화면 · 미션 꼬리 한 번 · 로비 다시 읽기.
        await store.place(58)
        #expect(store.phase == .result)
        let done = try #require(store.match)
        #expect(done.isFinished)
        #expect(done.outcome == .won)
        #expect(done.endReason == .boardFull)
        #expect(done.score == ReversiScore(black: 41, white: 23, result: .blackWin))
        #expect(done.counts == ReversiCounts(black: 41, white: 23, empty: 0))
        #expect(done.deadline == nil)
        #expect(store.remainingSeconds(now: Date()) == nil)
        #expect(store.rubyBalance == 105)
        #expect(finished == 1)
        #expect(store.notice == nil)                              // 지난 패스 안내는 다음 수가 오면 걷힌다
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") >= 2 }
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 2)

        store.backToLobby()
        #expect(store.phase == .lobby)
        #expect(store.match == nil)
        #expect(store.defersMegaphoneBanner == false)
        // 접은 판의 늦은 끝난 응답은 결과 화면을 되살리지 않는다.
        #expect(store.applyState(try rvState("reversi_move__finished_board_full")) == .ignored)
        #expect(store.match == nil)
        #expect(finished == 1)
    }

    // MARK: ② 보낸 신청 폴링(CCT I12)

    @Test(.gomokuDefaultsCleanup)
    func 보낸_신청은_초인종_없이도_5초_폴링으로_수락을_안다() async throws {
        // 없으면: 신청자가 초인종을 놓치면(재연결 중) 로비 30초 주기로만 수락을 알아 흑 첫 수가 자동 착수가 되는데도 초록이다.
        #expect(try rvViewer("reversi_challenge__ok") == rvA)
        #expect(try rvViewer("reversi_state__their_turn") == rvA)
        let clock = RVClock(Date())
        let (store, host) = makeReversiStore("outgoing", me: rvA, clock: clock, handler: rvHandler([
            "reversi_lobby": [try rvText("reversi_lobby__outgoing")],
            "reversi_challenge": [try rvText("reversi_challenge__ok")],
            "reversi_state": [try rvText("reversi_state__their_turn")],
        ]))
        store.applyLobby(try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__ok")))
        store.selectedStake = .five
        await store.challenge(userID: rvB)
        let sent = try #require(store.outgoing)
        #expect(sent.id == rvMainMatch)
        #expect(sent.peer.id == rvB)
        #expect(sent.stake == 5)
        #expect(store.notice == ReversiNoticeText.challenge(.ok))
        let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "reversi_challenge").first?.json)
        #expect(body["p_opponent"] as? String == rvB)
        #expect(body["p_stake"] as? Int == 5)
        #expect(store.canStartAIMatch == false)                   // 보낸 신청이 떠 있으면 AI 판을 못 연다

        store.isWindowVisible = true
        store.lastLobbyRequestAt = clock.now                      // 로비 30초 분기는 이 시험 밖
        let t0 = clock.now
        // 기준선: 5초 전에는 아무것도 안 묻는다.
        await store.pollTick(at: t0.addingTimeInterval(4.9))
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 0)
        #expect(store.phase == .lobby)
        await store.pollTick(at: t0.addingTimeInterval(5))
        let calls = GomokuStubProtocol.calls(host: host, rpc: "reversi_state")
        #expect(calls.count == 1)
        #expect(calls.first?.json["p_match_id"] as? String == rvMainMatch)
        #expect(store.phase == .playing)
        #expect(store.outgoing == nil)
        #expect(store.match?.myColor == .white)
        #expect(store.match?.isMyTurn == false)
        #expect(store.legalTargets.isEmpty)
    }

    // MARK: ③ 합법 수는 서버 목록만(DEC:26 · CCT I7)

    @Test(.gomokuDefaultsCleanup)
    func 어긋난_기준선_서버가_19만_주면_26은_요청_없이_문구만() async throws {
        // 없으면: 스토어가 `ReversiRules.legalMoves` 로 점을 그리고 입력을 받아도 진짜 판에선 늘 같아 전부 초록이다.
        // 이 시험만이 서버 목록을 규칙의 **진부분집합**으로 줘서 둘을 가른다.
        #expect(try rvViewer("reversi_state__my_turn") == rvB)
        let narrowed = try rvMutatedState("reversi_state__my_turn") { $0["legal_moves"] = [19] }   // 바꾼 칸: legal_moves
        let (store, host) = makeReversiStore("subset", me: rvB, handler: rvHandler([
            "reversi_move": [try rvText("reversi_move__ok")],
        ]))
        #expect(store.applyState(try rvStateText(narrowed)) == .applied)
        #expect(store.match?.board == .start)
        #expect(Set(ReversiRules.legalMoves(.start, color: .black)) == [19, 26, 37, 44])   // 규칙은 넷
        #expect(store.legalTargets == [19])                                                 // 화면은 서버 하나
        await store.place(26)
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_move") == 0)
        #expect(store.notice == ReversiNoticeText.outOfRange)
        #expect(store.match?.moveCount == 0)

        // 기준선: 원문(넷)이면 같은 칸이 서버로 나간다.
        let (wide, wideHost) = makeReversiStore("subset-base", me: rvB, handler: rvHandler([
            "reversi_move": [try rvText("reversi_move__ok")],
        ]))
        wide.applyState(try rvState("reversi_state__my_turn"))
        #expect(wide.legalTargets == [19, 26, 37, 44])
        await wide.place(26)
        #expect(GomokuStubProtocol.count(host: wideHost, rpc: "reversi_move") == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    func 합법_수는_내_차례일_때만_선다() async throws {
        // 없으면: 상대 차례 응답에 목록이 섞여 와도(서버 결함·관전 모양) 점이 그려지고 착수가 나가도 초록이다.
        #expect(try rvViewer("reversi_state__their_turn") == rvA)
        let leaked = try rvMutatedState("reversi_state__their_turn") { $0["legal_moves"] = [19, 26] }  // 바꾼 칸: legal_moves
        let (store, _) = makeReversiStore("their-turn", me: rvA, handler: rvHandler([:]))
        store.applyState(try rvStateText(leaked))
        #expect(store.match?.isMyTurn == false)
        #expect(store.match?.legalMoves == [])
        #expect(store.legalTargets.isEmpty)
        // 기준선: 내 차례 원문은 넷.
        let (mine, _) = makeReversiStore("my-turn", me: rvB, handler: rvHandler([:]))
        mine.applyState(try rvState("reversi_state__my_turn"))
        #expect(mine.legalTargets.count == 4)
        // 관전 모양(내 색 없음)은 대국으로 옮기지 않는다.
        #expect(mine.applyState(try rvState("reversi_watch_live__ok")) == .ignored)
    }

    // MARK: ④ 늦은 응답 가드

    @Test(.gomokuDefaultsCleanup)
    func 늦은_응답_같은_판_수_번호가_줄면_버린다() throws {
        // 없으면: 착수보다 먼저 읽힌 옛 스냅숏이 늦게 와서 방금 둔 돌이 사라지고 차례가 되돌아가도 초록이다.
        let (store, _) = makeReversiStore("shrink", me: rvB, handler: rvHandler([:]))
        #expect(store.applyState(try rvState("reversi_move__ok")) == .applied)
        #expect(store.match?.moveCount == 1)
        #expect(store.applyState(try rvState("reversi_state__my_turn"), requestedSince: 0) == .ignored)
        #expect(store.match?.moveCount == 1)
        #expect(store.match?.board[19] == .black)
        // 기준선: 같은 수 번호(1)는 받는다.
        #expect(store.applyState(try rvState("reversi_move__ok"), requestedSince: 1) == .applied)
    }

    @Test(.gomokuDefaultsCleanup)
    func 늦은_응답_끝난_판_뒤의_진행_응답은_버린다() throws {
        // 없으면: 끝나기 전에 나간 조회가 늦게 와서 결과 화면이 대국 화면으로 되돌아가도 초록이다.
        #expect(try rvViewer("reversi_state__finished") == rvA)
        let (store, _) = makeReversiStore("after-finish", me: rvA, handler: rvHandler([:]))
        store.applyState(try rvState("reversi_state__finished"))
        #expect(store.phase == .result)
        #expect(store.match?.outcome == .lost)                     // A 는 백, 흑 승
        #expect(store.applyState(try rvState("reversi_state__their_turn")) == .ignored)
        #expect(store.phase == .result)
        #expect(store.match?.isFinished == true)
    }

    @Test(.gomokuDefaultsCleanup)
    func 늦은_응답_다른_판을_두는_중이면_끝난_판은_버린다() throws {
        // 없으면: 지난 판의 늦은 끝남 응답이 두던 판을 지우고 결과 화면을 세워도 초록이다.
        #expect(try rvViewer("reversi_resign__ok") == rvA)
        let (store, _) = makeReversiStore("other-finished", me: rvA, handler: rvHandler([:]))
        store.applyState(try rvState("reversi_state__their_turn"))
        #expect(store.match?.id == rvMainMatch)
        let other = try rvState("reversi_resign__ok")
        #expect(other.match?.id != rvMainMatch)
        #expect(store.applyState(other) == .ignored)
        #expect(store.match?.id == rvMainMatch)
        #expect(store.phase == .playing)
        // 기준선: 두는 판이 없으면 같은 응답이 결과로 선다.
        let (idle, _) = makeReversiStore("other-finished-base", me: rvA, handler: rvHandler([:]))
        #expect(idle.applyState(other) == .applied)
        #expect(idle.phase == .result)
        #expect(idle.match?.endReason == .resign)
        #expect(idle.match?.score == nil)                          // 기권은 점수 없이 승패만(V-15)
    }

    @Test(.gomokuDefaultsCleanup)
    func 늦은_응답_세대가_밀리면_버린다() async throws {
        // 없으면: 로그아웃 직전에 나간 로비 응답이 다음 사람 화면에 앞 사람의 신청·전적·루비를 세워도 초록이다.
        let (store, host) = makeReversiStore("generation", me: rvB, handler: rvHandler(
            ["reversi_lobby": [try rvText("reversi_lobby__incoming")]], delays: ["reversi_lobby": 0.3]))
        let loading = Task { await store.refreshLobby() }
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 1 }
        store.reset()
        await loading.value
        #expect(store.incoming.isEmpty)
        #expect(store.users.isEmpty)
        #expect(store.rubyBalance == nil)
        // 기준선: 리셋 없이 같은 응답이면 선다.
        let (base, _) = makeReversiStore("generation-base", me: rvB, handler: rvHandler(
            ["reversi_lobby": [try rvText("reversi_lobby__incoming")]], delays: ["reversi_lobby": 0.3]))
        await base.refreshLobby()
        #expect(base.incoming.count == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    func 늦은_응답_방금_보낸_신청보다_먼저_나간_로비는_신청을_안_지운다() async throws {
        // 없으면: 신청 직전에 나간 로비 응답(보낸 신청 없음)이 늦게 와서 방금 보낸 신청을 "거절"로 지워도 초록이다.
        let (store, host) = makeReversiStore("revision", me: rvA, handler: rvHandler(
            [
                "reversi_lobby": [try rvText("reversi_lobby__ok")],
                "reversi_challenge": [try rvText("reversi_challenge__ok")],
            ],
            delays: ["reversi_lobby": 0.4]))
        let lobby = Task { await store.refreshLobby() }
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 1 }
        await store.challenge(userID: rvB)
        #expect(store.outgoing?.id == rvMainMatch)
        await lobby.value
        #expect(store.outgoing?.id == rvMainMatch)
        #expect(store.notice == ReversiNoticeText.challenge(.ok))
        // 기준선: 신청 **뒤에** 나간 같은 응답은 신청을 걷는다(서버에 이제 없다 = 거절·취소).
        await store.refreshLobby()
        #expect(store.outgoing == nil)
        #expect(store.notice == ReversiNoticeText.inviteDeclined)
    }

    // MARK: ⑤ 부활 방지(CCT M10)

    @Test(.gomokuDefaultsCleanup)
    func 부활_방지_수락_뒤_늦은_옛_로비가_신청을_되살리지_않는다() async throws {
        // 없으면: 수락 전에 나간 로비 응답이 수락 뒤에 와서 메뉴바 점·배너가 이미 시작된 판의 신청을 다시 띄워도 초록이다.
        let (store, _) = makeReversiStore("revive", me: rvB, handler: rvHandler([
            "reversi_respond": [try rvText("reversi_respond__accepted")],
        ]))
        let oldLobby = try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__incoming"))
        store.applyLobby(oldLobby)
        #expect(store.visibleIncoming?.id == rvMainMatch)
        await store.respond(inviteID: rvMainMatch, accept: true)
        #expect(store.match?.id == rvMainMatch)
        store.applyLobby(oldLobby)                                 // 늦게 온 옛 응답
        #expect(store.visibleIncomingInvites.isEmpty)
        #expect(store.visibleIncoming == nil)

        // 계산 칸 단독: `incoming` 에 내 판과 같은 id 가 남아 있어도 화면 값은 뺀다(시계 안 읽음).
        let stale = ReversiInvite(id: rvMainMatch, peer: ReversiUser(id: rvA, displayName: "비시험01"),
                                  stake: 5, expiresAt: .distantFuture)
        let other = ReversiInvite(id: "e0000000-0000-4000-8000-00000000000e",
                                  peer: ReversiUser(id: rvA, displayName: "비시험01"), stake: 3, expiresAt: .distantFuture)
        store.incoming = [stale, other]
        #expect(store.visibleIncomingInvites.map(\.id) == [other.id])
        store.hiddenPeerIDs = [rvA]
        #expect(store.visibleIncomingInvites.isEmpty)              // 차단 거울도 같이 거른다
    }

    @Test(.gomokuDefaultsCleanup)
    func 부활_방지_거절한_신청은_늦은_로비로_돌아오지_않는다() async throws {
        // 없으면: 거절 직전에 나간 로비 응답이 늦게 와서 방금 거절한 신청의 배너가 다시 떠도 초록이다(그 판이 없어 막을 id 가 없다).
        let (store, host) = makeReversiStore("revive-decline", me: rvB, handler: rvHandler([
            "reversi_respond": [try rvText("reversi_respond__declined")],
        ]))
        let oldLobby = try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__incoming"))
        store.applyLobby(oldLobby)
        await store.respond(inviteID: rvMainMatch, accept: false)
        #expect(GomokuStubProtocol.calls(host: host, rpc: "reversi_respond").first?.json["p_accept"] as? Bool == false)
        #expect(store.notice == "신청을 거절했어요")
        #expect(store.visibleIncoming == nil)
        store.applyLobby(oldLobby)
        #expect(store.visibleIncoming == nil)
        // 기준선: 답하지 않은 기기는 같은 응답으로 신청을 세운다.
        let (fresh, _) = makeReversiStore("revive-decline-base", me: rvB, handler: rvHandler([:]))
        fresh.applyLobby(oldLobby)
        #expect(fresh.visibleIncoming?.id == rvMainMatch)
    }

    // MARK: ⑥ 만료(CCT I8)

    @Test(.gomokuDefaultsCleanup)
    func 만료_시각이_지나면_스토어_타이머가_걷고_관찰이_깬다() async throws {
        // 없으면: 계산 칸이 시계를 읽는 구현(관찰이 안 깬다)이나 타이머가 없는 구현에서 만료된 메뉴바 점이 다음 무관한
        // 갱신까지 남아도 초록이다.
        let clock = RVClock(Date())
        let (store, _) = makeReversiStore("expiry", me: rvB, clock: clock, handler: rvHandler([:]))
        let nowMs = (clock.now.timeIntervalSince1970 * 1000).rounded()
        let lobby = try rvMutated("reversi_lobby__incoming") { top in       // 바꾼 칸: server_now_ms · expires_at_ms
            top["server_now_ms"] = nowMs
            var me = top["me"] as! [String: Any]
            var rows = me["incoming"] as! [[String: Any]]
            rows[0]["expires_at_ms"] = nowMs + 300
            me["incoming"] = rows
            top["me"] = me
        }
        store.applyLobby(try rvDecode(ReversiLobbyResponse.self, lobby))
        #expect(store.visibleIncoming?.id == rvMainMatch)
        let fired = RVFlag()
        withObservationTracking {
            _ = store.visibleIncoming
        } onChange: {
            fired.set()
        }
        // 기준선: 시계가 그대로면 타이머가 깨어나도 걷지 않는다(만료 판정은 스토어 시계 기준).
        try await Task.sleep(for: .milliseconds(700))
        #expect(store.visibleIncoming != nil)
        #expect(!fired.value)
        clock.advance(1)
        await rvWait { fired.value }
        #expect(fired.value)
        #expect(store.visibleIncoming == nil)
        #expect(store.incoming.isEmpty)
    }

    // MARK: ⑦ 두 기기 stale(CSM I-3)

    @Test(.gomokuDefaultsCleanup)
    func 두_기기_stale_은_문구_없이_실려_온_판으로_맞춘다() async throws {
        // 없으면: 같은 계정 다른 기기가 먼저 둔 뒤 이 기기의 착수가 stale 을 받아 "다시 시도" 같은 문구를 띄우거나
        // 낡은 판을 그대로 들고 있어도 초록이다.
        #expect(ReversiNoticeText.move(.stale) == nil)
        // 다른 기기가 둔 뒤의 판(move__ok 의 state) 을 stale 봉투에 싣는다 — 바꾼 칸: status.
        let staleBody = try rvMutated("reversi_move__ok") { $0["status"] = "stale" }
        let (store, host) = makeReversiStore("stale", me: rvB, handler: rvHandler([
            "reversi_move": [staleBody],
        ]))
        store.applyState(try rvState("reversi_state__my_turn"))
        await store.place(37)
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_move") == 1)
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 0)   // 실려 온 판으로 충분하다
        #expect(store.notice == nil)
        #expect(store.match?.moveCount == 1)
        #expect(store.match?.board[19] == .black)
        #expect(store.match?.isMyTurn == false)
        // 기준선: 같은 판에서 not_your_turn 은 문구를 낸다.
        let notYours = try rvMutated("reversi_move__ok") { $0["status"] = "not_your_turn" }
        let (other, _) = makeReversiStore("stale-base", me: rvB, handler: rvHandler(["reversi_move": [notYours]]))
        other.applyState(try rvState("reversi_state__my_turn"))
        await other.place(37)
        #expect(other.notice == ReversiNoticeText.notYourTurn)
    }

    // MARK: ⑧ auto_placed

    @Test(.gomokuDefaultsCleanup)
    func auto_placed_는_문구와_연속_횟수와_회색_점을_세운다() async throws {
        // 없으면: 착수 직전 서버가 내 색을 시간 초과로 대신 둔 사실을 화면이 모르고(문구·연속 횟수·회색 점 없음) 초록이다.
        try #require(try rvViewer("reversi_move__auto_placed") == rvB)
        // 서버가 대신 둔 칸은 무작위다 — 원문에서 읽는다.
        let autoMove = try #require(try rvState("reversi_move__auto_placed").moves?.last)
        #expect(autoMove.auto && autoMove.kind == .stone)
        let autoIdx = try #require(autoMove.idx)
        let (store, _) = makeReversiStore("auto", me: rvB, handler: rvHandler([
            "reversi_move": [try rvText("reversi_move__auto_placed")],
        ]))
        store.applyState(try rvState("reversi_state__my_turn"))
        #expect(store.match?.myAutoStreak == 0)
        await store.place(26)
        #expect(store.notice == ReversiNoticeText.autoPlaced)
        #expect(store.match?.myAutoStreak == 1)
        #expect(store.match?.autoStones == [autoIdx])
        #expect(store.match?.lastStoneIdx == autoIdx)
        #expect(store.match?.moveCount == 5)
        #expect(store.match?.isMyTurn == false)
        #expect(store.match?.autoAbandonStreak == 3)
    }

    // MARK: ⑨ Availability 세 갈래

    @Test(.gomokuDefaultsCleanup)
    func Availability_는_로비_ok_unsupported_PGRST202_세_갈래다() async throws {
        // 없으면: 옛 앱(unsupported_client)과 배포 전 서버(PGRST202)가 같은 화면이 되거나, 서버가 올라온 뒤에도 잠긴 채 남아도 초록이다.
        let (store, _) = makeReversiStore("availability", me: rvA, handler: rvHandler([
            "reversi_lobby": [try rvText("reversi_lobby__unsupported_client"), try rvText("reversi_lobby__ok")],
        ]))
        await store.refreshLobby()
        #expect(store.availability == .updateRequired)
        #expect(store.notice == ReversiNoticeText.updateRequired)
        await store.refreshLobby()
        #expect(store.availability == .available)

        let (missing, _) = makeReversiStore("availability-202", me: rvA, handler: rvHandler([:]))
        await missing.refreshLobby()
        #expect(missing.availability == .serverMissing)
        #expect(missing.notice == ReversiNoticeText.unavailable)

        let (unauthorized, _) = makeReversiStore("availability-401", me: rvA, handler: rvHandler([
            "reversi_lobby": [try rvText("reversi_lobby__unauthorized")],
        ]))
        await unauthorized.refreshLobby()
        #expect(unauthorized.availability == .available)           // 로그인 문제는 버전 문제가 아니다
        #expect(unauthorized.notice == ReversiNoticeText.signInAgain)
    }

    // MARK: ⑩ 알림 문

    @Test(.gomokuDefaultsCleanup)
    func 창이_안_보이면_판_시작과_내_차례를_한_번씩_알린다() throws {
        // 없으면: 창을 닫아 둔 사람이 수락·상대 수를 몰라 30초를 흘리거나(자동 착수), 같은 차례에 말풍선이 두 번 떠도 초록이다.
        let (store, _) = makeReversiStore("attention", me: rvB, handler: rvHandler([:]))
        var seen: [ReversiAttention] = []
        var presented = 0
        store.onAttention = { seen.append($0) }
        store.presentWindow = { presented += 1 }
        store.applyState(try rvState("reversi_respond__accepted"))
        store.applyState(try rvState("reversi_respond__accepted"))
        #expect(seen.map(\.kind) == [.matchStarted])
        #expect(seen.first?.opponentName == "비시험01")
        #expect(seen.first?.moveCount == 0)
        #expect(presented == 1)
        store.applyState(try rvState("reversi_move__ok_pass"), requestedSince: 0)
        #expect(seen.map(\.kind) == [.matchStarted, .myTurn])
        #expect(seen.last?.moveCount == 4)
        // 기준선: 창이 보이면 같은 진행에도 말풍선을 안 연다.
        let (visible, _) = makeReversiStore("attention-visible", me: rvB, handler: rvHandler([:]))
        var visibleSeen = 0
        visible.onAttention = { _ in visibleSeen += 1 }
        visible.isWindowVisible = true
        visible.applyState(try rvState("reversi_respond__accepted"))
        #expect(visibleSeen == 0)
    }

    // MARK: ⑪ 거절 갈래

    @Test(.gomokuDefaultsCleanup)
    func 신청_거절_문구와_받은_신청_잔액_부족은_신청을_남긴다() async throws {
        // 없으면: 잔액 부족 문구가 일반 실패로 접히거나, 수락이 잔액 부족으로 막혔는데 신청 카드가 사라져 다시 못 받아도 초록이다.
        let (store, _) = makeReversiStore("refusals", me: rvB, handler: rvHandler([
            "reversi_challenge": [try rvText("reversi_challenge__insufficient")],
            "reversi_respond": [try rvText("reversi_respond__insufficient_me")],
        ]))
        await store.challenge(userID: rvA)
        #expect(store.notice == "루비 1개 더 필요해요")
        #expect(store.outgoing == nil)
        store.applyLobby(try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__incoming")))
        await store.respond(inviteID: rvMainMatch, accept: true)
        #expect(store.match == nil)
        #expect(store.visibleIncoming?.id == rvMainMatch)
        // 기준선: 만료면 신청이 걷힌다.
        let (expired, _) = makeReversiStore("refusals-expired", me: rvB, handler: rvHandler([
            "reversi_respond": [try rvText("reversi_respond__expired")],
        ]))
        expired.applyLobby(try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__incoming")))
        await expired.respond(inviteID: rvMainMatch, accept: true)
        #expect(expired.visibleIncoming == nil)
        #expect(expired.notice == "신청 시간이 지났어요")
    }

    // MARK: ⑫ 적대 검증 1차(FLIP/verify/findings-round1.json V2-01·02·03·04·06 — 재현 시험 flip/v2 e04cfa54 를 옮겼다)

    @Test(.gomokuDefaultsCleanup)
    func 가려진_창에서도_초인종으로_온_내_차례를_알린다() throws {
        // 없으면(V2-01): 창을 연 채 다른 전체 화면 앱·다른 스페이스로 넘어간 사람은 폴링이 멈추고(가림) 말풍선 문도
        // `isWindowVisible` 에 막혀 내 차례를 알 길이 0 이다 — 30초 + 유예 뒤 자동 착수, 세 번이면 판돈을 잃는데도 초록이다.
        let (store, _) = makeReversiStore("attention-occluded", me: rvB, handler: rvHandler([:]))
        var seen: [ReversiAttention] = []
        store.onAttention = { seen.append($0) }
        store.isWindowVisible = true
        store.windowOcclusionDidChange(visible: false)
        #expect(store.pollTask == nil)                             // 가려진 동안 안전망 폴링은 없다 — 초인종만 남는다
        store.applyState(try rvState("reversi_move__ok"))          // B 흑 1수 뒤 상대 차례
        store.applyState(try rvState("reversi_move__ok_pass"), requestedSince: 0)
        #expect(store.match?.isMyTurn == true)
        #expect(seen.map(\.kind) == [.myTurn], "가려진 창인데 내 차례 알림이 없다")
        #expect(seen.last?.moveCount == 4)
        #expect(store.isWindowVisible)                             // 시계 잎 뷰가 읽는 값은 그대로다

        // 기준선: 보이고 안 가려진 창이면 같은 진행에도 말풍선을 안 연다(화면이 이미 말한다).
        let (shown, _) = makeReversiStore("attention-occluded-base", me: rvB, handler: rvHandler([:]))
        var shownSeen: [ReversiAttention] = []
        shown.onAttention = { shownSeen.append($0) }
        shown.isWindowVisible = true
        shown.applyState(try rvState("reversi_move__ok"))
        shown.applyState(try rvState("reversi_move__ok_pass"), requestedSince: 0)
        #expect(shown.match?.isMyTurn == true)
        #expect(shownSeen.isEmpty)
    }

    @Test(.gomokuDefaultsCleanup)
    func 도는_로비_조회_중에_온_초인종은_끝난_뒤_로비를_한_번_더_읽는다() async throws {
        // 없으면(V2-02): 신청이 생기기 **전에** 읽힌 로비(팝오버 열기·재접속 따라잡기·30초 폴링)가 날던 중 온 '새 신청' 초인종이
        // 그냥 버려져, 받는 쪽이 신청 카드·메뉴바 점·말풍선을 못 본 채 60초 TTL 이 지나가도 초록이다.
        // 기준선: 로비가 안 돌 때 온 초인종은 로비 한 번으로 받은 신청을 세운다.
        let (base, baseHost) = makeReversiStore("signal-lobby-base", me: rvB, handler: rvHandler(
            ["reversi_lobby": [try rvText("reversi_lobby__incoming")]]))
        base.handleSignal()
        await rvWait { !base.incoming.isEmpty }
        #expect(GomokuStubProtocol.count(host: baseHost, rpc: "reversi_lobby") == 1)
        #expect(base.incoming.map(\.id) == [rvMainMatch])

        // 바꾼 칸: 첫 로비의 me.incoming 을 비웠다(신청 전 스냅숏).
        let before = try rvMutated("reversi_lobby__incoming") { top in
            var me = top["me"] as? [String: Any] ?? [:]
            me["incoming"] = [Any]()
            top["me"] = me
        }
        let (store, host) = makeReversiStore("signal-lobby", me: rvB, handler: rvHandler(
            ["reversi_lobby": [before, try rvText("reversi_lobby__incoming")]],
            delays: ["reversi_lobby": 0.4]))
        var arrived: [String] = []
        store.onInviteArrived = { arrived.append($0.id) }
        let first = Task { await store.refreshLobby() }
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 1 }
        store.handleSignal()                                       // 상대가 막 신청했다는 초인종
        await first.value
        await rvWait(400) { !store.incoming.isEmpty }
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 2, "초인종이 로비 조회를 한 번도 못 냈다")
        #expect(store.incoming.map(\.id) == [rvMainMatch], "받은 신청이 화면·메뉴바 점에 안 섰다")
        #expect(arrived == [rvMainMatch], "말풍선(onInviteArrived)이 안 울렸다")
        // 합친 뒤 남은 깃발이 없다 — 다음 조회는 한 번만 나간다.
        await store.refreshLobby()
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 3)
    }

    @Test(.gomokuDefaultsCleanup)
    func 창을_닫는_순간에도_폴링에_합쳐진_초인종_조회는_끝까지_간다() async throws {
        // 없으면(V2-03): 상대 차례 안전망 폴링 조회에 초인종 조회가 합쳐진(stateAgain) 순간 창을 닫으면 `pollTask.cancel()` 이
        // 날던 조회와 합쳐진 조회를 함께 죽여, 창도 폴링도 없는 사람이 내 차례를 모른 채 30초 뒤 자동 착수돼도 초록이다.
        // B 흑 · 1수 뒤 상대(백) 차례(move__ok) → 상대가 두고 패스까지 해 내 차례(ok_pass, mc 4).
        func make(_ label: String) throws -> (ReversiStore, String) {
            let (store, host) = makeReversiStore(label, me: rvB, handler: rvHandler(
                ["reversi_state": [try rvText("reversi_move__ok"), try rvText("reversi_move__ok_pass")]],
                delays: ["reversi_state": 0.5]))
            store.applyState(try rvState("reversi_move__ok"))
            store.isWindowVisible = true
            store.pollStepSeconds = 0.02
            return (store, host)
        }

        // 기준선: 창을 그대로 두면 합쳐진 초인종 조회가 이어서 나가 내 차례가 선다.
        let (base, baseHost) = try make("pollcancel-base")
        base.startPolling()
        await rvWait { GomokuStubProtocol.count(host: baseHost, rpc: "reversi_state") == 1 }
        base.handleSignal()
        await rvWait(600) { base.match?.moveCount == 4 }
        #expect(base.match?.moveCount == 4)
        base.stopPolling()

        let (store, host) = try make("pollcancel")
        var attentions: [ReversiAttention] = []
        store.onAttention = { attentions.append($0) }
        store.startPolling()
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 1 }
        store.handleSignal()                                       // stateAgain 으로 합쳐진다
        store.windowDidHide()                                      // 최소화·빨간 점 — 폴링이 멈춘다
        #expect(store.pollTask == nil)
        await rvWait(600) { store.match?.moveCount == 4 }
        #expect(store.match?.moveCount == 4, "초인종이 알린 상대 수가 안 들어왔다(창이 닫혀 폴링도 없다)")
        #expect(attentions.contains { $0.kind == .myTurn }, "창이 닫혔는데 내 차례 말풍선이 안 떴다 — 30초 뒤 자동 착수")
    }

    @Test(.gomokuDefaultsCleanup)
    func 늦은_응답_수락_전에_읽힌_pending_은_진행_판과_잔액을_안_건드린다() async throws {
        // 없으면(V2-04): 배너 [보기] 가 신청을 읽는 동안 [수락] 했고 수락 응답이 먼저 왔을 때, 늦게 온 pending 이 진행 판을 지우고
        // (판 화면 → 로비) 잔액을 수락 전 값으로 되돌려도 초록이다 — 흑이면 첫 수 30초가 아무 화면 없이 흐른다.
        #expect(try rvViewer("reversi_respond__accepted") == rvB)
        // 바꾼 칸: pending 원문은 A 가 불렀다 — B 가 본 모양이 되게 opponent 만 A 로 바꾼다.
        let stalePending = try rvMutatedState("reversi_state__pending") { state in
            state["opponent"] = ["user_id": rvA, "display_name": "비시험01", "avatar_url": NSNull(),
                                 "character": NSNull(), "center": NSNull()] as [String: Any]
        }
        let pending = try rvStateText(stalePending)
        #expect(pending.match?.id == rvMainMatch)

        let (store, host) = makeReversiStore("stale-pending", me: rvB, handler: rvHandler(
            [
                "reversi_lobby": [try rvText("reversi_lobby__incoming")],
                "reversi_state": [stalePending],
                "reversi_respond": [try rvText("reversi_respond__accepted")],
            ],
            delays: ["reversi_state": 0.6]))
        store.openWindow(focusMatchID: rvMainMatch)
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 1 }
        #expect(store.incoming.map(\.id) == [rvMainMatch])
        await store.respond(inviteID: rvMainMatch, accept: true)
        #expect(store.match?.id == rvMainMatch)
        #expect(store.phase == .playing)
        #expect(store.rubyBalance == 95)
        #expect(store.match?.isMyTurn == true)                     // B 흑 — 첫 수 30초가 돈다
        await rvWait(400) { store.stateInFlightID == nil }
        #expect(store.stateInFlightID == nil)                      // 늦은 pending 이 도착해 처리됐다
        #expect(store.match?.id == rvMainMatch, "수락 전에 읽힌 pending 이 진행 중 판을 지웠다")
        #expect(store.phase == .playing)
        #expect(store.rubyBalance == 95, "판돈이 빠진 잔액(95)이 수락 전 값으로 되돌아갔다")
        #expect(store.incoming.isEmpty)
        // 진행 판을 든 동안 같은 id 의 신청 단계 응답은 어느 갈래(pending · declined)든 버린다 — 판은 신청으로 돌아가지 않는다.
        #expect(store.applyState(pending) == .ignored)
        let declined = try rvStateText(try rvMutatedState("reversi_state__pending") { state in   // 바꾼 칸: match.status
            var match = state["match"] as? [String: Any] ?? [:]
            match["status"] = "declined"
            state["match"] = match
        })
        #expect(store.applyState(declined) == .ignored)
        #expect(store.match?.id == rvMainMatch)
        #expect(store.rubyBalance == 95)

        // 기준선: 그 판을 안 든 기기에는 같은 pending 이 받은 신청으로 선다.
        let (fresh, _) = makeReversiStore("stale-pending-base", me: rvB, handler: rvHandler([:]))
        #expect(fresh.applyState(pending) == .applied)
        #expect(fresh.incoming.map(\.id) == [rvMainMatch])
        #expect(fresh.match == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    func 늦은_응답_쓰기보다_먼저_나간_로비는_잔액과_진행_판_id_를_안_덮는다() async throws {
        // 없으면(V2-06): 팝오버 열기 로비가 날던 중 [수락] 했고 로비(수락 전 스냅숏)가 늦게 왔을 때, 잔액 칩·앱 전체 루비 거울이
        // 판돈 빠지기 전 값으로 돌아가고 진행 판 id 가 지워져도 초록이다.
        let (store, host) = makeReversiStore("stale-lobby-ruby", me: rvB, handler: rvHandler(
            [
                "reversi_lobby": [try rvText("reversi_lobby__incoming")],
                "reversi_respond": [try rvText("reversi_respond__accepted")],
                "reversi_state": [try rvText("reversi_respond__accepted")],
            ],
            delays: ["reversi_lobby": 0.5]))
        let lobbyRuby = try #require(try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__incoming")).me?.rubyBalance)
        #expect(lobbyRuby != 95)                                   // 결과가 갈리는 입력이다
        let lobby = Task { await store.refreshLobby() }
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 1 }
        await store.respond(inviteID: rvMainMatch, accept: true)
        #expect(store.match?.id == rvMainMatch)
        #expect(store.rubyBalance == 95)                           // 서버가 판돈을 뺀 값
        #expect(store.activeMatchID == rvMainMatch)
        await lobby.value
        #expect(store.match?.id == rvMainMatch)
        #expect(store.incoming.isEmpty)                            // 답한 신청은 안 되살아난다(C2 ②)
        #expect(store.rubyBalance == 95, "수락 전 로비가 잔액 칩을 되돌렸다")
        #expect(store.host?.rubyBalance == 95, "수락 전 로비가 앱 전체 루비 거울을 되돌렸다")
        #expect(store.activeMatchID == rvMainMatch, "수락 전 로비가 진행 판 id 를 지웠다")

        // 기준선: 쓰기 **뒤에** 나간 로비는 잔액을 그대로 옮긴다(서버 값이 권위다).
        await store.refreshLobby()
        #expect(store.rubyBalance == lobbyRuby)
    }
}

/// 관찰 콜백이 다른 실행 맥락에서 불려도 안전한 깃발.
final class RVFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }
    func set() {
        lock.lock()
        raised = true
        lock.unlock()
    }
}
