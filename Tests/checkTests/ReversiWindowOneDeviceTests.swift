import Foundation
import Testing
@testable import check
@testable import CheckCore

// 한 계정 여러 맥 — 아잉 뒤집기 창은 **판을 연 기기에서만** 저절로 열린다(오목·체스와 같은 규칙, 가지 `fix/game-window-one-device`
// 62ecdf73 의 `GameWindowOneDeviceTests` 를 리버시로 옮긴 꼴).
//
// 그 가지의 제보 원문: "아니 이거 오목이나 미니게임 화면이 맥미니에도 동시에 열리는데 맥미니 꺼는 안 꺼져요".
// 1:1 판의 초인종(`reversi` 이벤트)은 그 사람의 **모든 기기**로 간다. 받은 기기마다 로비 → 판 상태를 읽고 `noteMatchProgress` 가
// "진행 중 판으로 처음 넘어갔다"로 보아 창 · 주의 · 말풍선을 부르면, 맥북에서 신청한 판이 놀던 맥미니에서도 열리고 그 창은 사람이
// 맥미니로 가서 닫기 전까지 남는다. 내 차례 말풍선도 두 기기에서 같이 뜬다.
//
// 이 파일은 **같은 사람의 두 기기**(각자 `WorkTimerStore` · 각자 defaults = 다른 맥)를 한 흉내 서버 위에 세우고 창 띄우기 · 주의 ·
// 말풍선 횟수를 잰다. 스토어는 소유자(`WorkTimerStore.reversi`)의 것을 그대로 쓴다 — 장부를 앱 defaults 에 두는 배선(T 몫)도 같이 잰다.
// 기준선이 짝으로 붙는다 — 판을 연 기기 A 는 예전처럼 창이 뜬다(가드 앞에서 통째로 멈춘 가짜 초록과 구별하려고).
// 응답 본문은 서버 픽스처 **원문**이고(`Fixtures/reversi-rpc` — 하네스는 `V03xxReversiStoreTests.swift` 것), 원문으로 못 만드는
// 장면(진행 중 판을 가리키는 로비)만 한 칸을 바꿨다 — 바꾼 칸은 `rodLobbyActive` 에 적었다.

/// 같은 사람의 기기들이 같이 보는 흉내 서버(rpc 이름 → 지금 응답 원문). 서버가 나아가면 `set` 으로 원문을 갈아 끼운다.
/// 스텁 응답기는 URL 로딩 스레드에서 부르므로 잠금으로 지킨다(오목 `ODGomokuServer` 와 같은 꼴). 표에 없는 rpc 는 `[]`.
private final class RODServer: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String: String] = [:]

    func set(_ rpc: String, _ body: String) {
        lock.lock()
        bodies[rpc] = body
        lock.unlock()
    }

    func handler() -> GomokuStubProtocol.Handler {
        { [self] rpc, _, _ in
            lock.lock()
            defer { lock.unlock() }
            return bodies[rpc].map { GomokuStubProtocol.Reply(body: $0) }
        }
    }
}

@MainActor
private enum RODRetention { static var stores: [WorkTimerStore] = [] }

@MainActor
private final class RODTally {
    var presents = 0
    var attentionRequests = 0
    var attentions: [ReversiAttention] = []
    var invites: [String] = []
}

/// 같은 사람(`me`)의 **기기 하나**. 기기마다 자기 스텁 호스트 · 자기 defaults(= 다른 맥)를 갖는다. 같은 맥에서 다시 켠 앱이면
/// 같은 `defaults` 를 넘긴다.
@MainActor
private func rodDevice(_ label: String, me: String, server: RODServer, defaults: UserDefaults? = nil)
    -> (owner: WorkTimerStore, reversi: ReversiStore, tally: RODTally, host: String) {
    let host = "rod-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: server.handler())
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: defaults ?? GomokuTestDefaults.make("rod"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    RODRetention.stores.append(owner)
    let reversi = owner.reversi
    // 실루프를 재운다(초인종 · 동작만 재는 결정적 시험).
    reversi.pollStepSeconds = 3_600
    let tally = RODTally()
    reversi.presentWindow = { tally.presents += 1 }
    reversi.requestAttention = { tally.attentionRequests += 1 }
    reversi.onAttention = { tally.attentions.append($0) }
    reversi.onInviteArrived = { tally.invites.append($0.id) }
    return (owner, reversi, tally, host)
}

/// 초인종 한 번이 끝까지 돈다(진행 중 판이 없으면 로비 → 그 로비가 가리키는 판, 있으면 그 판).
@MainActor
private func rodRing(_ reversi: ReversiStore) async {
    reversi.handleSignal()
    await rvWait { reversi.syncTask == nil }
}

/// 진행 중 판을 가리키는 로비 — 원문에 없는 장면이라 한 칸을 바꿨다. **바꾼 칸**: `me.active_match_id` = 주 판 id
/// (`reversi_lobby__ok` 는 A 가, `reversi_lobby__incoming` 은 B 가 부른 원문이다 — B 쪽은 판이 섰으니 `me.incoming` 도 비웠다).
private func rodLobbyActive(viewer: String) throws -> String {
    let name = viewer == rvA ? "reversi_lobby__ok" : "reversi_lobby__incoming"
    try #require(try rvViewer(name) == viewer, "\(name): 시청자가 \(viewer) 가 아니다")
    return try rvMutated(name) { top in
        var me = top["me"] as? [String: Any] ?? [:]
        me["active_match_id"] = rvMainMatch
        me["incoming"] = [Any]()
        top["me"] = me
    }
}

@MainActor
@Suite("아잉 뒤집기 — 한 계정 여러 맥, 창은 판을 연 기기에서만 저절로 열린다", .serialized)
struct ReversiWindowOneDeviceTests {

    @Test("① 신청한 기기 A 만 창·주의를 받는다 — 같은 계정의 맥미니 A' 는 판을 알되 창을 안 띄운다", .gomokuDefaultsCleanup)
    func challengerOnlyOpensOnTheChallengingDevice() async throws {
        // 없으면: 수락 초인종을 받은 신청자의 **모든 맥**이 창을 띄우고 주의를 끈다(오목·체스 2026-11-03 제보와 같은 결함).
        for name in ["reversi_challenge__ok", "reversi_lobby__outgoing", "reversi_state__their_turn"] {
            try #require(try rvViewer(name) == rvA, "\(name): 시청자가 A 가 아니다")
        }
        let server = RODServer()
        server.set("reversi_challenge", try rvText("reversi_challenge__ok"))
        server.set("reversi_lobby", try rvText("reversi_lobby__outgoing"))
        let a = rodDevice("ch-a", me: rvA, server: server)
        let other = rodDevice("ch-a2", me: rvA, server: server)

        await a.reversi.challenge(userID: rvB)
        #expect(a.reversi.outgoing?.id == rvMainMatch, "전제: A 가 신청을 보냈다")
        await rodRing(other.reversi)                   // A' 도 로비에서 보낸 신청을 본다(계정 단위)
        #expect(other.reversi.outgoing?.id == rvMainMatch, "전제: A' 도 같은 계정의 보낸 신청을 안다")

        // 상대가 수락했다 — 신청자의 모든 기기에 초인종. 로비가 진행 중 판을 말하고, 그 판은 상대(흑) 차례다.
        server.set("reversi_lobby", try rodLobbyActive(viewer: rvA))
        server.set("reversi_state", try rvText("reversi_state__their_turn"))
        await rodRing(a.reversi)
        await rodRing(other.reversi)

        #expect(a.reversi.phase == .playing && a.reversi.match?.id == rvMainMatch)
        #expect(a.reversi.ownsMatch(rvMainMatch))
        #expect(a.tally.presents == 1, "신청한 A 가 창을 안 띄웠다(\(a.tally.presents)회) — 상대 수 뒤 30초를 흘린다")
        #expect(a.tally.attentionRequests == 1)

        #expect(other.reversi.match?.id == rvMainMatch && other.reversi.phase == .playing,
                "A' 는 판을 알아야 한다 — 사람이 A' 에서 창을 직접 열면 판이 보여야 한다")
        #expect(!other.reversi.ownsMatch(rvMainMatch))
        #expect(other.tally.presents == 0, "신청하지 않은 A' 가 창을 \(other.tally.presents)번 띄웠다")
        #expect(other.tally.attentionRequests == 0, "A' 가 주의를 끌었다")
        #expect(other.tally.attentions.isEmpty, "A' 에 말풍선이 떴다: \(other.tally.attentions)")
        a.reversi.reset()
        other.reversi.reset()
    }

    @Test("② 수락한 기기 B 만 창·주의·판 시작 말풍선을 받는다 — 받은 신청 알림은 두 기기 다 그대로다", .gomokuDefaultsCleanup)
    func acceptOnlyOpensOnTheAcceptingDevice() async throws {
        // 없으면: 수락으로 판이 선 순간 서버가 울린 초인종에 놀던 B' 도 창 · 주의 · '대결이 시작됐어요' 말풍선을 띄운다.
        for name in ["reversi_lobby__incoming", "reversi_respond__accepted", "reversi_state__my_turn"] {
            try #require(try rvViewer(name) == rvB, "\(name): 시청자가 B 가 아니다")
        }
        try #require(try rvState("reversi_respond__accepted").myColor == .black, "B 가 흑이 아닌 원문이다(판 시작 = 내 차례 전제)")
        let server = RODServer()
        server.set("reversi_lobby", try rvText("reversi_lobby__incoming"))
        server.set("reversi_respond", try rvText("reversi_respond__accepted"))
        let b = rodDevice("ac-b", me: rvB, server: server)
        let other = rodDevice("ac-b2", me: rvB, server: server)
        await rodRing(b.reversi)
        await rodRing(other.reversi)
        #expect(b.reversi.incoming.map(\.id) == [rvMainMatch] && other.reversi.incoming.map(\.id) == [rvMainMatch],
                "전제: 받은 신청은 두 기기 다 안다")
        // 받은 신청 알림(말풍선 큐 · 메뉴바 점 · 배너가 읽는 값)은 장부와 무관하게 **모든 기기**에 선다(그 가지도 막지 않았다).
        #expect(b.tally.invites == [rvMainMatch] && other.tally.invites == [rvMainMatch],
                "받은 신청 알림이 한 기기에만 섰다: \(b.tally.invites) · \(other.tally.invites)")
        #expect(b.reversi.visibleIncoming?.id == rvMainMatch && other.reversi.visibleIncoming?.id == rvMainMatch)

        await b.reversi.respond(inviteID: rvMainMatch, accept: true)
        server.set("reversi_lobby", try rodLobbyActive(viewer: rvB))
        server.set("reversi_state", try rvText("reversi_state__my_turn"))
        await rodRing(other.reversi)                   // 수락으로 판이 섰다 — 서버는 두 사람의 모든 기기를 울린다

        #expect(b.reversi.phase == .playing && b.reversi.ownsMatch(rvMainMatch))
        #expect(b.tally.presents == 1, "수락한 B 가 창을 안 띄웠다(\(b.tally.presents)회)")
        #expect(b.tally.attentionRequests == 1)
        #expect(b.tally.attentions.map(\.kind) == [.matchStarted], "판을 연 B 에 판 시작 말풍선이 안 떴다 — 기준선이 죽었다")
        #expect(other.reversi.match?.id == rvMainMatch && other.reversi.match?.isMyTurn == true)
        #expect(!other.reversi.ownsMatch(rvMainMatch))
        #expect(other.tally.presents == 0 && other.tally.attentionRequests == 0 && other.tally.attentions.isEmpty,
                "수락하지 않은 B' 가 창 \(other.tally.presents) · 주의 \(other.tally.attentionRequests) · 말풍선 \(other.tally.attentions.count)")
        b.reversi.reset()
        other.reversi.reset()
    }

    @Test("③ 판 중 '내 차례' 말풍선도 판을 연 기기에서만 — B' 는 상대가 둘 때마다 울려도 조용하다", .gomokuDefaultsCleanup)
    func turnBubblesStayOnTheOwningDevice() async throws {
        // 없으면: 상대가 둘 때마다 같은 계정의 모든 맥에 '내 차례예요' 말풍선이 뜬다.
        for name in ["reversi_move__ok", "reversi_move__ok_pass"] {
            try #require(try rvViewer(name) == rvB, "\(name): 시청자가 B 가 아니다")
        }
        let server = RODServer()
        server.set("reversi_lobby", try rvText("reversi_lobby__incoming"))
        server.set("reversi_respond", try rvText("reversi_respond__accepted"))
        let b = rodDevice("turn-b", me: rvB, server: server)
        let other = rodDevice("turn-b2", me: rvB, server: server)
        await rodRing(b.reversi)
        await b.reversi.respond(inviteID: rvMainMatch, accept: true)
        server.set("reversi_lobby", try rodLobbyActive(viewer: rvB))
        server.set("reversi_state", try rvText("reversi_state__my_turn"))
        await rodRing(other.reversi)

        // B 가 두었다(흑 1수) — 초인종이 B' 에도 간다.
        server.set("reversi_move", try rvText("reversi_move__ok"))
        await b.reversi.place(19)
        server.set("reversi_state", try rvText("reversi_move__ok"))
        await rodRing(other.reversi)
        let bBefore = b.tally.attentions.count

        // 상대(백)가 두고 B 가 패스 — 다시 내 차례(수 4). 두 기기 다 창이 안 보인다.
        server.set("reversi_state", try rvText("reversi_move__ok_pass"))
        await rodRing(b.reversi)
        await rodRing(other.reversi)

        #expect(b.reversi.match?.moveCount == 4 && other.reversi.match?.moveCount == 4, "전제: 두 기기 다 상대 수를 읽었다")
        #expect(b.reversi.match?.isMyTurn == true && other.reversi.match?.isMyTurn == true)
        #expect(b.tally.attentions.count == bBefore + 1 && b.tally.attentions.last?.kind == .myTurn,
                "판을 연 B 에 내 차례 말풍선이 안 떴다 — 기준선이 죽었다: \(b.tally.attentions)")
        #expect(b.tally.attentions.last?.moveCount == 4)
        #expect(other.tally.attentions.isEmpty, "B' 에 내 차례 말풍선이 떴다: \(other.tally.attentions)")
        #expect(other.tally.presents == 0 && other.tally.attentionRequests == 0)
        b.reversi.reset()
        other.reversi.reset()
    }

    @Test("④ 장부는 앱 defaults 에 산다(WorkTimerStore 배선) — 판 중에 다시 켠 A 는 자기 판의 창을 띄우고, 다른 맥은 여전히 조용하다",
          .gomokuDefaultsCleanup)
    func ledgerSurvivesARestartOnTheOwningDevice() async throws {
        // 없으면(`reversi.deviceLedger.defaults = defaults` 가 빠지면): 장부가 프로세스 안에만 살아 판 중에 앱을 다시 켠 A 가
        // 자기 판을 못 알아본다 — 창이 안 떠 30초씩 흘리고 세 번이면 판돈을 잃는다.
        let server = RODServer()
        server.set("reversi_challenge", try rvText("reversi_challenge__ok"))
        let defaultsA = GomokuTestDefaults.make("rod-restart-a")
        let a = rodDevice("rs-a", me: rvA, server: server, defaults: defaultsA)
        #expect(a.owner.reversi.deviceLedger.defaults === defaultsA, "소유자가 장부에 자기 defaults 를 안 넣었다")
        await a.reversi.challenge(userID: rvB)
        #expect(a.reversi.ownsMatch(rvMainMatch))
        #expect(defaultsA.dictionary(forKey: a.reversi.deviceLedger.key(userID: rvA))?.keys.contains(rvMainMatch) == true,
                "장부가 앱 defaults 에 안 떨어졌다(WorkTimerStore 배선)")
        a.reversi.reset()

        server.set("reversi_lobby", try rodLobbyActive(viewer: rvA))
        server.set("reversi_state", try rvText("reversi_state__their_turn"))
        // 같은 맥에서 앱을 다시 켰다 = 같은 defaults 의 새 소유자. 다른 맥 = 다른 defaults.
        let restarted = rodDevice("rs-a2", me: rvA, server: server, defaults: defaultsA)
        let other = rodDevice("rs-b", me: rvA, server: server)
        await rodRing(restarted.reversi)
        await rodRing(other.reversi)
        #expect(restarted.reversi.match?.id == rvMainMatch && other.reversi.match?.id == rvMainMatch, "전제: 둘 다 판을 읽었다")
        #expect(restarted.tally.presents == 1, "다시 켠 A 가 자기 판의 창을 안 띄웠다(\(restarted.tally.presents)회)")
        #expect(other.tally.presents == 0, "다른 맥이 창을 띄웠다 — 위 1 이 장부 덕인지 가리지 못한다")
        restarted.reversi.reset()
        other.reversi.reset()
    }

    @Test("⑤ B' 로 옮겨 와 직접 두면 B' 도 연 기기가 된다 — 그 뒤 내 차례 말풍선이 B' 에서도 뜬다 · 끝나면 장부에서 걷힌다",
          .gomokuDefaultsCleanup)
    func placingOnAnotherDeviceAdoptsTheMatch() async throws {
        // 막는 것은 **저절로** 열리는 것뿐이다 — 사람이 B' 에서 창을 열고 두면 B' 가 그 판을 알린다.
        // 없으면(착수가 장부에 안 적으면): 맥미니로 옮겨 와 두는 사람에게 다음 차례 말풍선이 영영 안 온다 — 30초 자동 착수.
        // 없으면(끝난 판을 안 걷으면): 끝난 판이 6시간 장부에 남는다(상한 8개를 남의 판이 채운다).
        try #require(try rvViewer("reversi_move__finished_board_full") == rvB)
        let server = RODServer()
        server.set("reversi_lobby", try rvText("reversi_lobby__incoming"))
        server.set("reversi_respond", try rvText("reversi_respond__accepted"))
        let b = rodDevice("mv-b", me: rvB, server: server)
        let other = rodDevice("mv-b2", me: rvB, server: server)
        await rodRing(b.reversi)
        await b.reversi.respond(inviteID: rvMainMatch, accept: true)
        server.set("reversi_lobby", try rodLobbyActive(viewer: rvB))
        server.set("reversi_state", try rvText("reversi_state__my_turn"))
        await rodRing(other.reversi)
        #expect(other.tally.presents == 0 && !other.reversi.ownsMatch(rvMainMatch))

        // 사람이 B' 에서 창을 연다 — 판은 이미 들고 있다(로비가 아니라 판이 보인다).
        other.reversi.isWindowVisible = true
        #expect(other.reversi.phase == .playing && other.reversi.legalTargets.contains(19),
                "놀던 B' 가 판 상태를 안 들고 있다 — 창을 직접 열어도 판이 안 보인다")
        server.set("reversi_move", try rvText("reversi_move__ok"))
        await other.reversi.place(19)
        #expect(GomokuStubProtocol.count(host: other.host, rpc: "reversi_move") == 1, "전제: B' 의 수가 서버로 갔다")
        #expect(other.reversi.ownsMatch(rvMainMatch), "B' 에서 둔 수가 장부에 안 올랐다")

        // 창을 닫았는데 상대가 두고 내 차례가 왔다 → 내 차례 말풍선이 B' 에서 뜬다.
        other.reversi.isWindowVisible = false
        server.set("reversi_state", try rvText("reversi_move__ok_pass"))
        await rodRing(other.reversi)
        #expect(other.tally.attentions.map(\.kind) == [.myTurn], "B' 로 옮겨 온 사람에게 내 차례가 안 왔다: \(other.tally.attentions)")
        #expect(other.tally.presents == 0, "판 시작은 지나갔다 — 창을 다시 띄우면 안 된다")

        // 판이 끝났다 → 두 기기 다 장부에서 걷힌다.
        server.set("reversi_state", try rvText("reversi_move__finished_board_full"))
        await rodRing(other.reversi)
        await rodRing(b.reversi)
        #expect(other.reversi.match?.isFinished == true && b.reversi.match?.isFinished == true, "전제: 두 기기 다 끝난 판을 읽었다")
        #expect(!other.reversi.ownsMatch(rvMainMatch), "끝난 판이 B' 장부에 남았다")
        #expect(!b.reversi.ownsMatch(rvMainMatch), "끝난 판이 B 장부에 남았다")
        #expect(other.owner.defaults.object(forKey: other.reversi.deviceLedger.key(userID: rvB)) == nil,
                "빈 장부의 키가 앱 defaults 에 남았다")
        b.reversi.reset()
        other.reversi.reset()
    }

    @Test("⑥ 장부는 사용자별 키 — 같은 맥에서 계정을 바꾼 상대는 앞 사람이 연 판(같은 판 id)을 자기 판으로 읽지 않는다 · 로그아웃은 장부를 안 지운다",
          .gomokuDefaultsCleanup)
    func ledgerIsKeyedPerUser() async throws {
        // 없으면(키에 사람이 없으면): B 가 쓰던 맥에 A(그 판의 상대)가 들어오면 A 의 초인종이 앞 사람의 장부를 읽어 창을 연다.
        let shared = GomokuTestDefaults.make("rod-per-user")
        let serverB = RODServer()
        serverB.set("reversi_lobby", try rvText("reversi_lobby__incoming"))
        serverB.set("reversi_respond", try rvText("reversi_respond__accepted"))
        let b = rodDevice("pu-b", me: rvB, server: serverB, defaults: shared)
        await rodRing(b.reversi)
        await b.reversi.respond(inviteID: rvMainMatch, accept: true)
        #expect(b.reversi.ownsMatch(rvMainMatch) && b.tally.presents == 1, "전제: 이 맥에서 B 가 판을 열었다")
        b.reversi.reset()                              // 로그아웃·계정 전환의 정리
        #expect(b.reversi.ownsMatch(rvMainMatch), "로그아웃이 장부를 지웠다 — 다시 들어온 B 가 자기 판의 창을 못 띄운다")

        let serverA = RODServer()
        serverA.set("reversi_lobby", try rodLobbyActive(viewer: rvA))
        serverA.set("reversi_state", try rvText("reversi_state__their_turn"))
        let a = rodDevice("pu-a", me: rvA, server: serverA, defaults: shared)
        #expect(!a.reversi.ownsMatch(rvMainMatch), "A 가 B 의 장부를 자기 것으로 읽었다")
        #expect(shared.dictionary(forKey: a.reversi.deviceLedger.key(userID: rvA)) == nil)
        #expect(shared.dictionary(forKey: a.reversi.deviceLedger.key(userID: rvB))?.keys.contains(rvMainMatch) == true,
                "전제: B 의 기록은 같은 defaults 에 그대로 있다")
        await rodRing(a.reversi)
        #expect(a.reversi.match?.id == rvMainMatch, "전제: A 도 그 판을 읽었다")
        #expect(a.tally.presents == 0 && a.tally.attentionRequests == 0, "앞 사람(B)이 연 판이라고 A 의 창이 떴다")
        a.reversi.reset()
    }
}
