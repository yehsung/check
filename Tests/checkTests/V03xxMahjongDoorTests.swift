import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 — 문(X1). 서버 `mahjong_create` · `mahjong_join`(공개 방 · 받은 초대) · `mahjong_start` 는 부른 사람의 앱이 문 밖이면
// (`mahjong_capable` 거짓 — 출시 전 문, 되돌리기 '문 닫기') `outdated` 를 내고 방·판을 만들지 않는다. [시작]은 앉은 사람 가운데 문 밖을
// `seats_dropped{reasons: outdated}` 로 거른다. 실응답은 판 초안 시험 `tests/o_door.sql`(S2 하네스 55492)이 뜬 넷(`Fixtures/mahjong-rpc`).
// 진행 중 판(state · act · call · back · leave)은 문을 보지 않는다 — 그 쪽은 서버 시험(o_door ③)이 잰다.
// 각 시험 첫 줄 주석은 "없으면 어떤 결함이 초록인가".

@MainActor
@Suite("아잉 마작 문 — outdated(만들기 · 들어가기 · 시작) · seats_dropped{outdated} → 업데이트 안내 · 방/판 안 생김", .serialized)
struct V03xxMahjongDoorTests {
    /// 판 초안 실응답 seats_dropped{outdated} 의 방장(o_door ① R3).
    static let realHost = "3a07d996-a5eb-44b4-b1b6-2d7e02c8a9a5"

    @Test("실응답 넷 — outdated 셋은 .outdated(.unknown 아님) · state · match_id 없음 · seats_dropped 의 까닭은 outdated 하나")
    func realResponsesDecode() throws {
        // 없으면: 클라가 'outdated' 를 몰라 .unknown('잠시 후 다시 시도해 주세요')으로 접어, 문이 닫힌 동안 같은 단추를 계속 누르게 한다.
        for name in ["mahjong_create__outdated", "mahjong_join__outdated", "mahjong_start__outdated"] {
            let response = try MJFixture.real(name)
            #expect(response.status == .outdated, "\(name)")
            #expect(response.state == nil && response.matchId == nil, "\(name): 방·판이 실려 오지 않는다")
        }
        let dropped = try MJFixture.real("mahjong_start__seats_dropped_outdated")
        #expect(dropped.status == .seatsDropped && dropped.dropped?.count == 1)
        #expect(dropped.reasons.map { Set($0.values) } == ["outdated"])
        #expect(dropped.state?.match?.id != nil, "방 state 는 실려 온다(빠진 뒤 셋)")
        // 기준선: 모르는 글자는 여전히 .unknown.
        #expect(MahjongRPCStatus(rawValue: "outdated") == .outdated && MahjongRPCStatus(rawValue: "outdated2") == nil)
    }

    @Test("문구 — outdated 는 만들기 · 들어가기 · 시작 모두 '앱을 업데이트해 주세요' · 빠진 까닭 outdated 는 제 줄 · 섞이면 까닭 없는 줄")
    func noticeLines() {
        // 없으면: 문 밖 거절이 '다시 시도'로 보이거나, 옛 맥이 빠졌는데 '자리를 비웠거나 루비가 모자란 사람'으로 잘못 말한다.
        for action in [MahjongNoticeText.Action.create, .join, .start] {
            #expect(MahjongNoticeText.status(.outdated, for: action) == MahjongNoticeText.updateRequired, "\(action)")
        }
        #expect(MahjongNoticeText.status(.outdated, for: .join) == MahjongNoticeText.status(.unsupportedClient, for: .join))
        #expect(MahjongNoticeText.droppedOthers(reasons: ["outdated"]) == "앱 업데이트가 필요한 사람이 빠졌어요")
        #expect(MahjongNoticeText.droppedOthers(reasons: ["outdated", "outdated"]) == "앱 업데이트가 필요한 사람이 빠졌어요")
        #expect(MahjongNoticeText.droppedOthers(reasons: ["unseen", "outdated"]) == "방에서 빠진 사람이 있어요")
        // 기준선: 옛 까닭 줄은 그대로.
        #expect(MahjongNoticeText.droppedOthers(reasons: ["insufficient"]) == "루비가 모자란 사람이 빠졌어요")
        #expect(MahjongNoticeText.droppedOthers(reasons: ["unseen"]) == "자리를 비운 사람이 빠졌어요")
        #expect(MahjongNoticeText.droppedOthers(reasons: ["unseen", "insufficient"]) == "자리를 비웠거나 루비가 모자란 사람이 빠졌어요")
    }

    @Test("만들기 outdated — 안내줄만 · 방 안 생김 · 장부 안 적힘 · 가용성 그대로(패널이 '업데이트' 화면으로 안 덮인다)",
          .gomokuDefaultsCleanup)
    func createOutdated() async throws {
        // 없으면: 문 닫힌 동안 [만들기]가 unsupported_client 처럼 패널 전체(연습판 포함)를 '업데이트' 화면으로 덮거나 방 화면으로 넘어간다.
        let server = MJServer()
        server.set("mahjong_create", try MJFixture.realText("mahjong_create__outdated"))
        let a = mjDevice("door-create", me: V03xxMahjongStoreRealResponseTests.host, server: server)
        await a.store.createRoom()
        #expect(a.count("create") == 1)
        #expect(a.store.notice == MahjongNoticeText.updateRequired)
        #expect(a.store.availability == .available && a.store.phase == .lobby && a.store.match == nil)
        #expect(!a.store.ownsMatch(V03xxMahjongStoreRealResponseTests.room) && !a.store.isWorking)
        // 기준선: 같은 기기에 ok 원문이면 방이 선다.
        server.set("mahjong_create", try MJFixture.realText("mahjong_create__ok"))
        await a.store.createRoom()
        #expect(a.store.phase == .room && a.store.notice == nil && a.store.ownsMatch(V03xxMahjongStoreRealResponseTests.room))
    }

    @Test("들어가기 outdated — 받은 초대 카드는 남고 방이 안 선다 · 가용성 그대로", .gomokuDefaultsCleanup)
    func joinOutdated() async throws {
        // 없으면: 문 닫힌 동안 초대 [참가]가 방을 세우거나(장부·방 화면) 카드를 걷어, 문이 다시 열려도 그 초대로 못 들어간다.
        let server = MJServer()
        server.set("mahjong_lobby", try MJFixture.text("mahjong_lobby__invited"))
        server.set("mahjong_join", try MJFixture.realText("mahjong_join__outdated"))
        let b = mjDevice("door-join", me: mjB, server: server)
        await mjRing(b.store)
        #expect(b.store.hasIncomingInvite, "기준선: 초대 카드가 있다")
        await b.store.join(roomID: UUID(uuidString: mjRoom)!)
        #expect(b.count("join") == 1 && b.store.notice == MahjongNoticeText.updateRequired)
        #expect(b.store.match == nil && b.store.phase == .lobby && !b.store.ownsMatch(mjRoom))
        #expect(b.store.availability == .available && b.store.hasIncomingInvite)
    }

    @Test("방장 [시작] outdated — 방 화면 그대로(넷 앉음) · 판 안 섬 · 창 안 띄움", .gomokuDefaultsCleanup)
    func startOutdated() async throws {
        // 없으면: 문 닫힌 동안 [시작]이 '다시 시도'만 말하거나, 응답을 판 시작으로 읽어 창을 띄운다.
        let server = MJServer()
        server.set("mahjong_start", try MJFixture.realText("mahjong_start__outdated"))
        let a = mjDevice("door-start", server: server)
        a.store.applyState(try MJFixture.state("mahjong_state__room_four"))
        #expect(a.store.canStart, "기준선: 넷이 모인 방의 방장")
        await a.store.start()
        #expect(a.count("start") == 1 && a.store.notice == MahjongNoticeText.updateRequired)
        #expect(a.store.phase == .room && MahjongStore.joinedCount(a.store.match) == 4 && a.store.canStart)
        #expect(a.tally.presents == 0 && a.store.availability == .available)
    }

    @Test("[시작] seats_dropped{outdated} — 방장: '앱 업데이트가 필요한 사람이 빠졌어요' · 실응답 원문도 같은 줄", .gomokuDefaultsCleanup)
    func startDropsOutdatedSeat() async throws {
        // 없으면: 앉은 뒤 앱이 문 밖이 된 사람이 빠졌는데 방장 화면이 '자리를 비웠거나 루비가 모자란 사람'으로 말한다.
        let server = MJServer()
        server.set("mahjong_start", try MJFixture.mutated("mahjong_start__seats_dropped") { top in
            top["reasons"] = [mjD: "outdated"]
        })
        let a = mjDevice("door-drop", server: server)
        a.store.applyState(try MJFixture.state("mahjong_state__room_four"))
        await a.store.start()
        #expect(a.store.notice == "앱 업데이트가 필요한 사람이 빠졌어요" && a.store.phase == .room)
        #expect(a.store.notice != MahjongNoticeText.droppedOthers(reasons: ["unseen"]), "기준선: 까닭이 다르면 다른 줄")
        // 실응답 원문(판 초안 o_door ①) — 방장 기기에 그대로 먹인다.
        server.set("mahjong_start", try MJFixture.realText("mahjong_start__seats_dropped_outdated"))
        let real = try MJFixture.real("mahjong_start__seats_dropped_outdated")
        let h = mjDevice("door-drop-real", me: Self.realHost, server: server)
        h.store.handleRoomResponse(real, action: .start, ticket: h.store.issueTicket())
        #expect(h.store.notice == "앱 업데이트가 필요한 사람이 빠졌어요")
        #expect(h.store.phase != .playing && h.tally.presents == 0)
    }
}
