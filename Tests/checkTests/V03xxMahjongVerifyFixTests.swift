import Foundation
import Testing
@testable import check
@testable import CheckCore

// 갈래 F(11-04) — 적대 검증 V2 · V3 가 재현한 클라 결함을 고친 뒤의 동작을 단언한다(고치기 전 빨강 · 고친 뒤 초록을 봤다).
// 각 시험 첫 줄 '없으면:' 이 그 결함이다. 서버 쪽 짝은 MJ/server/table/tests/n_fix.sql · g_concurrent.sh ⑦.

@MainActor
@Suite("아잉 마작 — 검증 V2 · V3 고침(가림 기록 · 실패한 울기 답 · 접은 판 · 나가기 경합 · 깨우기 실패 · 리치 링 · 빠진 사람)", .serialized)
struct V03xxMahjongVerifyFixTests {
    @Test("V3-01 판 시작 창 띄우기가 열린 채 가려진 창의 가림 기록을 지우지 않는다 · 기준선: 숨긴 창은 말풍선 0", .gomokuDefaultsCleanup)
    func presentWindowKeepsOcclusion() throws {
        // 없으면: 다른 전체 화면 앱에 가려진 채 판이 시작되면 창 띄우기(→ windowDidShow)가 가림 기록을 지워, 창이 실제로 못
        //   올라와도 스토어는 보인다고 믿는다 — 시작 말풍선은 오버레이가 버리고 그 판 '내 차례' 말풍선이 하나도 안 뜬다.
        let a = mjDevice("f-v301", server: MJServer())
        a.store.presentWindow = { [store = a.store, tally = a.tally] in
            tally.presents += 1
            store.windowDidShow()       // 앱 배선 그대로(창 컨트롤러 show → notifyVisibility(true) → 동기)
        }
        a.store.noteOwnsMatch(mjRoom)
        a.store.windowDidShow()
        a.store.windowOcclusionDidChange(visible: false)
        a.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        let started = try #require(a.tally.attentions.first { $0.kind == .matchStarted })
        #expect(a.store.isWindowOccluded, "판 시작 창 띄우기 뒤에도 가림 기록이 남는다")
        #expect(CheckOverlayController.mahjongAttentionIsCurrent(started, in: a.store), "시작 말풍선이 산다")
        a.store.applyState(try MJFixture.state("mahjong_state__my_turn_hand2"))
        #expect(a.tally.kinds(.myTurn) == 1, "가려진 창 — 내 차례 말풍선")
        a.store.windowOcclusionDidChange(visible: true)
        #expect(!a.store.isWindowOccluded && a.store.isWindowShowingTable, "창이 정말 앞으로 오면 가림 통지가 푼다")
        a.store.windowDidHide()

        let b = mjDevice("f-v301b", server: MJServer())
        b.store.presentWindow = { [store = b.store, tally = b.tally] in
            tally.presents += 1
            store.windowDidShow()
        }
        b.store.noteOwnsMatch(mjRoom)
        b.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        #expect(b.tally.presents == 1 && b.store.isWindowShowingTable, "기준선: 숨긴 창을 띄우면 보인다")
        b.store.applyState(try MJFixture.state("mahjong_state__my_turn_hand2"))
        #expect(b.tally.kinds(.myTurn) == 0, "기준선: 탁자가 보이면 말풍선 0")
        b.store.windowDidHide()
    }

    @Test("V3-02 울기 답이 서버에 못 닿으면(503) '답함' 기록을 걷는다 — 같은 창 [론]을 다시 보낼 수 있고 조회가 프롬프트를 되살린다",
          .gomokuDefaultsCleanup)
    func failedCallAnswerCanBeRetried() async throws {
        // 없으면: 보내기 전에 적은 '답함'이 실패 뒤에도 남아, 503 뒤 [론]을 다시 눌러도 요청이 0건이고 다음 조회도 answered 로 덮여
        //   단추가 사라진다 — 서버는 답을 못 받았으니 론을 잃는다(시간 초과 자동 화료가 있어도 그 전에 넘기기로 닫히는 창이 있다).
        let ron = try MJFixture.mutated("mahjong_state__call_prompt") { top in
            mjEditState(&top) { st in mjEditNested(&st, "my_decision") { $0["ron"] = true } }
        }
        let server = MJServer()
        server.enqueue("mahjong_call", "{\"message\":\"upstream\"}", status: 503)
        server.set("mahjong_call", try MJFixture.text("mahjong_call__ok_pass"))
        let a = mjDevice("f-v302", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.applyState(try MJFixture.state(text: ron))
        await a.store.call(.ron, tiles: [])
        #expect(a.count("call") == 1 && !a.store.isAnsweringCall)
        await a.store.call(.ron, tiles: [])
        #expect(a.count("call") == 2, "실패한 론을 같은 창에서 다시 보낸다")

        let b = mjDevice("f-v302b", server: server)
        server.enqueue("mahjong_call", "{\"message\":\"upstream\"}", status: 503)
        b.store.noteOwnsMatch(mjRoom)
        b.store.applyState(try MJFixture.state(text: ron))
        await b.store.call(.ron, tiles: [])
        b.store.applyState(try MJFixture.state(text: ron))
        guard case .call(let c)? = b.store.myDecision else {
            Issue.record("울기 프롬프트가 있어야 한다")
            return
        }
        #expect(c.answered == nil && c.ron, "서버가 못 받은 답은 프롬프트를 가리지 않는다(answered=\(c.answered ?? "nil"))")
    }

    @Test("V3-02 짝 — 성공한 울기 답은 그대로 단조(가드 (h)): 늦은 answered=nil 조회가 프롬프트를 되살리지 않는다", .gomokuDefaultsCleanup)
    func successfulCallStaysAnswered() async throws {
        // 없으면: V3-02 고침이 성공한 답까지 걷어 늦게 온 조회가 [론]을 되살린다(기준선).
        let ron = try MJFixture.mutated("mahjong_state__call_prompt") { top in
            mjEditState(&top) { st in mjEditNested(&st, "my_decision") { $0["ron"] = true } }
        }
        let server = MJServer()
        server.set("mahjong_call", try MJFixture.text("mahjong_call__ok_pass"))
        let a = mjDevice("f-v302c", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.applyState(try MJFixture.state(text: ron))
        await a.store.passCall()
        a.store.applyState(try MJFixture.state(text: ron))
        if case .call(let c)? = a.store.myDecision {
            #expect(c.answered != nil, "성공한 답 뒤 늦은 조회는 답함으로")
        }
    }

    @Test("V3-03 다른 맥에서 나갔다 같은 방에 다시 들어가 판이 서면 — 로비가 말하는 진행 판은 접은 기록을 걷고 든다", .gomokuDefaultsCleanup)
    func dismissedRoomComesBackWhenLobbySaysActive() async throws {
        // 없으면: 접은 판 가드(a)가 그 id 를 영영 버려, 로비가 진행 중인 내 판 id 를 말해도 · 초인종이 와도 앱을 다시 켤 때까지 로비만 보인다.
        let server = MJServer()
        let a = mjDevice("f-v303", me: mjB, server: server)
        a.store.applyState(try MJFixture.state("mahjong_state__room_three"))
        #expect(a.store.match?.match?.id == mjRoom, "전제: 방을 든다")
        let left = try MJFixture.mutated("mahjong_state__room_three") { top in
            mjEditState(&top) { st in
                var members = st["members"] as? [[String: Any]] ?? []
                for i in members.indices where ((members[i]["user"] as? [String: Any])?["id"] as? String) == mjB {
                    members[i]["state"] = "left"
                }
                st["members"] = members
            }
        }
        a.store.applyState(try MJFixture.state(text: left))
        #expect(a.store.match == nil && a.store.dismissedMatchIDs.contains(mjRoom), "전제: 다른 맥에서 나간 것을 보고 방을 접음")
        server.set("mahjong_lobby", try MJFixture.mutated("mahjong_lobby__ok") { top in
            mjEditNested(&top, "me") { $0["active_match_id"] = mjRoom }
        })
        server.set("mahjong_state", try MJFixture.text("mahjong_state__their_turn"))
        await a.store.refreshLobby()
        #expect(a.store.match?.match?.id == mjRoom && a.store.phase == .playing, "진행 판을 든다 — phase=\(a.store.phase)")
        #expect(!a.store.ownsMatch(mjRoom), "다른 기기가 연 판 — 이 기기 장부엔 안 적는다")
    }

    @Test("V2-01 방 [나가기] ↔ 방장 [시작] 경합 — 옛 서버 not_found 뒤에도 로비로 판을 찾고 · 고친 서버의 ok(진행 판 state)는 바로 든다",
          .gomokuDefaultsCleanup)
    func leaveRacingStartFindsTheMatch() async throws {
        // 없으면: leave 가 not_found(state 없음)이면 방을 접어 그 판의 state 를 모두 버린다 — 이미 앉았고 판돈이 빠진 판이 자동으로
        //   끝까지 가는 동안 앱을 다시 켤 때까지 못 돌아온다.
        let server = MJServer()
        server.set("mahjong_leave", #"{"status":"not_found","server_now_ms":1800000000000}"#)
        server.set("mahjong_lobby", try MJFixture.mutated("mahjong_lobby__ok") { top in
            mjEditNested(&top, "me") { $0["active_match_id"] = mjRoom }
        })
        server.set("mahjong_state", try MJFixture.text("mahjong_state__their_turn"))
        let b = mjDevice("f-v201", me: mjB, server: server)
        b.store.applyState(try MJFixture.state("mahjong_state__room_four_b"))
        #expect(b.store.phase == .room)
        await b.store.leaveRoom()
        await mjWait { b.store.phase == .playing && b.store.stateInFlightID == nil }
        #expect(b.store.phase == .playing && b.store.match?.match?.id == mjRoom, "not_found 뒤 로비가 말하는 판을 든다 — \(b.store.phase)")

        // 고친 서버(n_fix · g_concurrent ⑦): 잠금 뒤 active 면 판 중 나가기(자리 비움) + 그 판 state.
        let fixed = MJServer()
        fixed.set("mahjong_leave", try MJFixture.mutated("mahjong_start__ok") { top in
            top["status"] = "ok"
            mjEditState(&top) { st in
                st["my_seat"] = 1
                st["my_decision"] = NSNull()
            }
        })
        let c = mjDevice("f-v201b", me: mjB, server: fixed)
        c.store.applyState(try MJFixture.state("mahjong_state__room_four_b"))
        await c.store.leaveRoom()
        #expect(c.store.phase == .playing && c.store.match?.match?.id == mjRoom, "ok + 진행 판 state 는 바로 든다 — \(c.store.phase)")
    }

    @Test("V3-04 깨우기 조회가 실패하면 같은 열쇠로 1초 뒤 재시도를 다시 잡는다(상한 그대로)", .gomokuDefaultsCleanup)
    func failedWakeRearms() async throws {
        // 없으면: 깨우기 조회가 실패(503 · 끊김)하면 응답 적용이 없어 다음 깨우기가 안 잡힌다 — 박자 기기 걸음이 그 결정 동안 멎는다.
        let beat = try MJFixture.mutated("mahjong_state__their_turn") { top in
            mjEditState(&top) { st in
                let now = st["server_now_ms"] as? Double ?? 0
                mjEditNested(&st, "match") { $0["wake_seat"] = 0; $0["wake_at_ms"] = now }
            }
        }
        let server = MJServer()
        server.set("mahjong_state", "{\"message\":\"upstream\"}", status: 503)
        let a = mjDevice("f-v304", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.applyState(try MJFixture.state(text: beat))
        a.store.timersEnabled = true
        defer {
            a.store.timersEnabled = false
            a.store.scheduleWake()
        }
        a.store.checkWake(at: a.clock.now.addingTimeInterval(0.01))
        await mjWait { a.count("state") == 1 && a.store.stateInFlightID == nil }
        #expect(a.count("state") == 1)
        #expect(a.store.wakeTask != nil, "실패 뒤 깨우기가 다시 잡혔다")
        #expect(a.store.wakeScheduledKey?.hasPrefix("beat#") == true, "같은 박자 열쇠(재시도 상한이 센다)")
    }

    @Test("V3-05 리치 자동 쯔모기리 차례(서버 마감 = not_before)는 내 시계 링·막대를 그리지 않는다 · 기준선: 보통 차례는 그린다")
    func riichiAutoTurnHasNoClock() throws {
        // 없으면: 링이 서버 마감 대신 '시작 + 5초 + 예비'로 재 25초를 그리는데 버림은 0.7초에 나간다.
        let auto = try MJFixture.mutated("mahjong_start__ok") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "my_decision") { d in
                    let started = d["started_ms"] as? Double ?? 0
                    d["deadline_ms"] = started + 700
                    d["not_before_ms"] = started + 700
                    d["discard"] = [129]
                }
            }
        }
        let clock = MJClock()
        let s = MahjongStore(clock: { clock.now })
        s.applyState(try MJFixture.state(text: auto))
        #expect(MahjongMyClock.window(store: s) == nil, "리치 자동 차례 — 시계 없음")
        let normal = MahjongStore(clock: { clock.now })
        normal.applyState(try MJFixture.state("mahjong_start__ok"))
        #expect(MahjongMyClock.window(store: normal) != nil, "기준선: 보통 차례는 링을 그린다")
    }

    @Test("V3-07 퐁 · 대명깡 조합이 둘 이상(적5 를 낼지)이면 고르기 줄 · 하나면 그 패로 바로 · 치도 같은 규칙")
    func callButtonsLetMeChooseTheRedFive() throws {
        // 없으면: 퐁 · 대명깡 단추가 서버 조합 첫째를 박아 보내 적5 를 손에 남길지 낼지 고를 수 없다(치만 고르기 줄이 있었다).
        func call(pon: [[Int]], minkan: [[Int]] = [], chi: [[Int]] = []) throws -> MahjongDecision.Call {
            let text = try MJFixture.mutated("mahjong_state__call_prompt") { top in
                mjEditState(&top) { st in
                    mjEditNested(&st, "my_decision") { $0["pon"] = pon; $0["minkan"] = minkan; $0["chi"] = chi }
                }
            }
            guard case .call(let c)? = try MJFixture.state(text: text).myDecision else { throw MJVerifyFixError.noCall }
            return c
        }
        let two = try call(pon: [[16, 17], [16, 52]], minkan: [[16, 17, 52]], chi: [[8, 12], [12, 20]])
        guard case .choose(let pons) = MahjongActionsView.plan(.pon, two) else {
            Issue.record("적5 퐁 둘 — 고르기 줄이어야 한다")
            return
        }
        #expect(pons.count == 2)
        #expect(MahjongActionsView.plan(.minkan, two) == .send(two.minkan[0]), "대명깡 하나 — 바로")
        if case .choose = MahjongActionsView.plan(.chi, two) {} else { Issue.record("치 조합 둘 — 고르기 줄") }
        let one = try call(pon: [[109, 110]])
        #expect(MahjongActionsView.plan(.pon, one) == .send(one.pon[0]), "기준선: 퐁 하나 — 그 패로 바로")
        #expect(MahjongActionsView.plan(.chi, one) == .none && MahjongActionsView.plan(.minkan, one) == .none)
    }

    @Test("V2-03 시작 검사에서 빠진 사람 — 서버 실응답(자기 줄 dropped)에서 '판이 시작될 때 방에서 빠졌어요'", .gomokuDefaultsCleanup)
    func droppedSelfRealResponse() async throws {
        // 없으면: 서버가 빠진 사람을 멤버 목록에서 그냥 지우면 클라가 '방이 닫혔어요'로 읽는다(방은 열려 있다) — 서버 n_fix ② 의 짝.
        let raw = try MJFixture.realText("mahjong_state__dropped_self")
        let top = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let st = try #require(top["state"] as? [String: Any])
        let members = try #require(st["members"] as? [[String: Any]])
        let me = try #require(members.first { ($0["state"] as? String) == "dropped" }.flatMap { ($0["user"] as? [String: Any])?["id"] as? String })
        // 빠지기 전(넷 joined) 방을 든 기기 — 같은 응답에서 내 줄을 joined 로 되돌려 만든다.
        let before = try MJFixture.decoder().decode(MahjongActionResponse.self, from: JSONSerialization.data(withJSONObject: {
            var t = top
            var s = st
            s["members"] = members.map { m -> [String: Any] in
                var m = m
                if (m["state"] as? String) == "dropped" { m["state"] = "joined" }
                return m
            }
            t["state"] = s
            return t
        }()))
        let server = MJServer()
        server.set("mahjong_state", raw)
        let d = mjDevice("f-v203", me: me, server: server)
        d.store.applyState(try #require(before.state))
        #expect(d.store.phase == .room)
        await mjRing(d.store)
        #expect(d.store.notice == MahjongNoticeText.droppedAtStart && d.store.phase == .lobby, "notice=\(d.store.notice ?? "nil")")
    }
}

private enum MJVerifyFixError: Error { case noCall }
