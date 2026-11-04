@testable import CheckCore
import Foundation
import Testing

// 한 계정 여러 맥 — 아잉 마작 창·주의·말풍선·깨우기·방 확인·보조 자동은 **이 기기가 연 판**(장부)에서만(SPEC §4.7 · CC-20 보류).
// 62ecdf73 `GameWindowOneDeviceTests` 꼴: 같은 사람의 두 기기(각자 장부 defaults = 다른 맥)를 한 흉내 서버 위에 세운다.
// 기준선이 짝으로 붙는다 — 방을 연 기기 A 는 창이 뜬다(가드 앞에서 통째로 멈춘 가짜 초록과 구별하려고).
// B 에서 판 시작 말풍선 0 은 장부 규약 그대로다 — 총괄이 '옮겨 앉음' 예외를 두면 이 기대값 하나가 바뀐다(§4.7 CC-20).

@MainActor
@Suite("아잉 마작 — 한 계정 여러 맥, 창·말풍선·깨우기는 판을 연 기기에서만", .serialized)
struct V03xxMahjongOneDeviceTests {
    @Test("방을 만든 A 만 방 확인·창·판 시작 말풍선·내 차례·자리 비움·닫기 안내 — 같은 계정의 맥미니 B 는 판을 알되 0",
          .gomokuDefaultsCleanup)
    func onlyTheOpeningDeviceSpeaks() async throws {
        // 없으면: 초인종이 그 사람의 모든 맥으로 가 놀던 맥미니에서도 창이 뜨고 안 꺼진다(11-03 제보와 같은 결함).
        let server = MJServer()
        server.set("mahjong_create", try MJFixture.text("mahjong_create__ok"))
        server.set("mahjong_lobby", try MJFixture.mutated("mahjong_lobby__ok") { top in
            mjEditNested(&top, "me") { me in
                me["room"] = ["id": mjRoom, "host": ["id": mjA, "display_name": "아잉", "avatar_url": NSNull(), "character": "aing"],
                              "stake": 5, "format": "tonpuu", "is_public": false, "expires_at_ms": mjT0Ms + 480_000, "max_seats": 4,
                              "seats": [["user": ["id": mjA, "display_name": "아잉", "avatar_url": NSNull(), "character": "aing"],
                                         "state": "joined"]]]
            }
        })
        server.set("mahjong_state", try MJFixture.text("mahjong_state__room_four"))
        let a = mjDevice("od-a", server: server)
        let b = mjDevice("od-b", server: server)
        a.store.windowDidHide()
        b.store.windowDidHide()
        await a.store.createRoom()
        await mjRing(b.store)          // B 는 로비가 말하는 내 방을 읽어 세운다(같은 계정)
        await mjWait { b.store.match?.match?.id == mjRoom && b.store.stateInFlightID == nil }
        #expect(b.store.phase == .room && !b.store.ownsMatch(mjRoom), "전제: B 도 방을 알되 장부는 없다")
        #expect(a.store.ownsMatch(mjRoom))

        // 방 확인 30초 — A 만.
        let later = a.clock.now.addingTimeInterval(31)
        let aStates = a.count("state"), bStates = b.count("state")
        a.store.checkWake(at: later)
        b.store.checkWake(at: later)
        await mjWait { a.count("state") > aStates }
        try await Task.sleep(for: .milliseconds(20))
        #expect(a.count("state") == aStates + 1 && b.count("state") == bStates)

        // 판 시작 — 둘 다 판을 읽지만 창·말풍선은 A 만.
        server.set("mahjong_state", try MJFixture.text("mahjong_state__their_turn"))
        await mjRing(a.store)
        await mjRing(b.store)
        #expect(a.store.phase == .playing && b.store.phase == .playing)
        #expect(a.tally.presents == 1 && a.tally.kinds(.matchStarted) == 1 && a.tally.attentionRequests == 1)
        #expect(b.tally.presents == 0 && b.tally.attentions.isEmpty && b.tally.attentionRequests == 0)
        #expect(a.store.defersMegaphoneBanner && !b.store.defersMegaphoneBanner)

        // 내 차례 — A 만.
        server.set("mahjong_state", try MJFixture.text("mahjong_state__my_turn_hand2"))
        await mjRing(a.store)
        await mjRing(b.store)
        #expect(a.tally.kinds(.myTurn) == 1 && b.tally.attentions.isEmpty)
        #expect(a.store.wakeTarget(now: a.clock.now) != nil && b.store.wakeTarget(now: b.clock.now) == nil, "깨우기도 A 만")

        // 닫기 안내 — A 만.
        a.store.windowDidClose(byUser: true)
        b.store.windowDidClose(byUser: true)
        #expect(a.tally.kinds(.closedWhilePlaying) == 1 && b.tally.attentions.isEmpty)

        // 자리 비움 — A 만(점·배너·말풍선 모두 hasAwaySeatHere 하나).
        server.set("mahjong_state", try MJFixture.mutated("mahjong_leave__ok_away") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "match") { $0["seq"] = 30; $0["hand_index"] = 1 }
                st["events"] = [Any]()
            }
        })
        await mjRing(a.store)
        await mjRing(b.store)
        #expect(a.store.hasAwaySeatHere && a.tally.kinds(.away) == 1)
        #expect(!b.store.hasAwaySeatHere && b.tally.attentions.isEmpty)
    }

    @Test("B 에서 직접 보내면 B 도 연 기기 — 그 뒤 B 에서도 말풍선 · 보조 자동은 연 판에서만", .gomokuDefaultsCleanup)
    func sendingFromTheOtherMacMakesItOwn() async throws {
        // 없으면: 사람이 맥미니로 옮겨 앉아 거기서 두어도 맥미니가 끝까지 말풍선·깨우기 없이 남는다.
        let server = MJServer()
        server.set("mahjong_act", try MJFixture.text("mahjong_act__ok"))
        let b = mjDevice("od-b2", server: server)
        b.store.windowDidHide()
        b.store.aids.tsumogiri = true
        b.store.aidJitter = { 0.5 }
        b.store.applyState(try MJFixture.state("mahjong_start__ok"))
        b.clock.now = mjDate(ms: mjT0Ms + 900)
        try await Task.sleep(for: .milliseconds(30))
        #expect(b.count("act") == 0 && b.tally.attentions.isEmpty, "안 연 기기는 보조도 말풍선도 0")
        await b.store.discard(mjTile(129))
        #expect(b.store.ownsMatch(mjRoom) && b.count("act") == 1)
        b.store.applyState(try MJFixture.state("mahjong_state__my_turn_hand2"))
        #expect(b.tally.kinds(.myTurn) == 1)
    }
}
