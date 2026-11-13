// 1:1 대기방(맥 1:1 여섯 게임 공용) — 스토어 · 서버 원문 응답 · 앱 배선 · 로비 렌더.
// 없으면 어떤 결함이 초록으로 통과하는가:
//  · 방장 기기가 '시작됨' 숨을 받아도 판을 이 기기의 판으로 받지 않으면(onRoomStarted 없음) 방장 창이 안 떠 첫 차례를 흘린다 →
//    `pingStartedAdoptsOnce` 가 잡는다(같은 방은 한 번만 — 두 번이면 창이 두 번 뜬다).
//  · 문이 닫혀 있는데 방 탭이 서면 옛 서버에서 빈 탭이 보인다 → `doorClosedHidesTab`.
//  · 게임 초인종이 와도 방 숨을 안 쉬면 방장은 20초 늦게 안다 → `gameSignalPingsOnlyWithOpenRoom`.
// 응답은 하네스(체인 188 + duel_rooms 초안)에서 뽑은 원문(Fixtures/duel-rooms)이다.
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

@MainActor
final class DRScript: DuelRoomServing {
    var replies: [String: [DuelRoomsResponse]] = [:]
    private(set) var calls: [DuelRoomCall] = []

    func on(_ rpc: String, _ responses: DuelRoomsResponse...) { replies[rpc, default: []].append(contentsOf: responses) }

    func call(_ call: DuelRoomCall) async throws -> DuelRoomsResponse {
        calls.append(call)
        guard var list = replies[call.rpcName], let first = list.first else {
            Issue.record("대본에 없는 요청: \(call)")
            throw CancellationError()
        }
        if list.count > 1 { list.removeFirst(); replies[call.rpcName] = list }
        return first
    }

    func count(_ rpc: String) -> Int { calls.filter { $0.rpcName == rpc }.count }
}

func drFixture(_ name: String) throws -> DuelRoomsResponse {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/duel-rooms/\(name).json")
    return try JSONDecoder().decode(DuelRoomsResponse.self, from: Data(contentsOf: url))
}

@MainActor
@Suite("1:1 대기방 — 스토어 · 원문 · 배선", .serialized)
struct V03xxDuelRoomsStoreTests {
    @Test("서버 원문 디코드: 목록 · 열기 · 숨(열림/시작) · 참가 · 문 닫힘 · 모르는 상태")
    func fixturesDecode() throws {
        let list = try drFixture("list__ok")
        #expect(list.status == .ok && list.doorOpen == true && list.stakes == [3, 5, 10])
        let room = try #require(list.rooms?.first)
        #expect(room.game == .reversi && room.stake == 5 && room.isOpen && room.host?.displayName == "민수"
                && room.host?.character == "fox")
        #expect(try drFixture("open__ok").myRoom?.isOpen == true)
        let started = try #require(try drFixture("ping__started").myRoom)
        #expect(started.isStarted && started.matchID != nil, "시작된 방은 판 id 를 싣는다")
        let joined = try drFixture("join__ok")
        #expect(joined.status == .ok && joined.matchID == started.matchID && joined.gameRaw == "reversi")
        #expect(try drFixture("join__insufficient").status == .insufficient)
        #expect(try drFixture("join__room_gone").status == .roomGone)
        let closed = try drFixture("list__door_closed")
        #expect(closed.status == .unsupportedClient && closed.doorOpen == false)
        let weird = try JSONDecoder().decode(DuelRoomsResponse.self, from: Data(#"{"status":"brand_new","rooms":[{"id":1}]}"#.utf8))
        #expect(weird.status == .unknown && weird.rooms == [], "모르는 상태 · 깨진 방 줄에도 죽지 않는다")
    }

    @Test("목록: 방 · 문 열림 · 불러옴 표시 / 문 닫힘이면 문 거짓(방 탭을 감춘다)")
    func refreshAndDoor() async throws {
        let script = DRScript()
        script.on("duel_rooms_list", try drFixture("list__ok"), try drFixture("list__door_closed"))
        let store = DuelRoomStore(service: script)
        await store.refresh(.reversi)
        #expect(store.rooms(for: .reversi).count == 1 && store.doorOpen == true && store.loadedGames.contains(.reversi))
        #expect(store.rooms(for: .gomoku).isEmpty)
        await store.refresh(.reversi)
        #expect(store.doorOpen == false, "문 닫힘 응답 → 문 거짓")
    }

    @Test("방장: 열기 → 내 방 · 숨이 '시작됨'이면 그 판을 한 번만 받는다(같은 방 두 번째 숨은 그대로)")
    func pingStartedAdoptsOnce() async throws {
        let script = DRScript()
        script.on("duel_room_open", try drFixture("open__ok"))
        script.on("duel_room_ping", try drFixture("ping__open"), try drFixture("ping__started"))
        let store = DuelRoomStore(service: script, pingSeconds: 3_600)
        var adopted: [(DuelRoomGame, String)] = []
        store.onRoomStarted = { adopted.append(($0, $1)) }
        await store.open(.reversi, stake: 5)
        #expect(store.myOpenRoom(for: .reversi)?.stake == 5 && store.myOpenRoom(for: .gomoku) == nil)
        #expect(store.myOpenRoom(otherThan: .gomoku)?.game == .reversi, "다른 게임 로비는 '열어 둔 방' 한 줄")
        await store.ping()
        #expect(adopted.isEmpty, "아직 열린 방이면 받지 않는다")
        await store.ping()
        let matchID = try #require(try drFixture("ping__started").myRoom?.matchID).lowercased()
        #expect(adopted.count == 1 && adopted.first?.0 == .reversi && adopted.first?.1 == matchID)
        await store.ping()
        #expect(adopted.count == 1, "같은 방의 시작은 한 번만(창이 두 번 뜨지 않게)")
    }

    @Test("참가: ok → 그 판을 받는다 · 모자람 → 안내(판돈) · 방 사라짐 → 목록에서 뺀다")
    func joinOutcomes() async throws {
        let room = try #require(try drFixture("list__ok").rooms?.first)
        let script = DRScript()
        script.on("duel_room_join", try drFixture("join__insufficient"), try drFixture("join__room_gone"), try drFixture("join__ok"))
        script.on("duel_rooms_list", try drFixture("list__ok"))
        let store = DuelRoomStore(service: script)
        store.rooms[.reversi] = [room]
        var joined: [String] = []
        store.onJoined = { joined.append($1) }
        await store.join(room)
        #expect(joined.isEmpty && store.notice == "루비가 모자라요 · 판돈 5")
        await store.join(room)
        #expect(joined.isEmpty && store.notice == DuelRoomText.notice(.roomGone))
        store.rooms[.reversi] = [room]
        await store.join(room)
        #expect(joined.count == 1 && store.notice == nil && store.rooms(for: .reversi).isEmpty, "참가 ok → 판 받기 · 그 방은 목록에서 빠짐")
    }

    @Test("게임 초인종: 열린 방이 있을 때만 숨을 바로 쉰다(1초에 한 번) · 기준선: 방이 없으면 0")
    func gameSignalPingsOnlyWithOpenRoom() async throws {
        let script = DRScript()
        script.on("duel_room_open", try drFixture("open__ok"))
        script.on("duel_room_ping", try drFixture("ping__open"))
        let store = DuelRoomStore(service: script, pingSeconds: 3_600)
        store.handleGameSignal()
        try await Task.sleep(for: .milliseconds(50))
        #expect(script.count("duel_room_ping") == 0, "방이 없으면 숨 0")
        await store.open(.gomoku, stake: 3)
        store.handleGameSignal()
        store.handleGameSignal()
        try await akEventually { script.count("duel_room_ping") == 1 }
        #expect(script.count("duel_room_ping") == 1, "1초 안 두 번째 신호는 합친다")
    }

    @Test("앱 배선: 여섯 게임 초인종만 방 숨 신호 · 방에서 선 판은 그 게임 스토어로")
    func wiring() throws {
        #expect(WorkTimerStore.isDuelRoomGameSignal(.gomokuSignal) && WorkTimerStore.isDuelRoomGameSignal(.alkkagiSignal)
                && WorkTimerStore.isDuelRoomGameSignal(.crossyDuelSignal) && WorkTimerStore.isDuelRoomGameSignal(.tetrisSignal))
        #expect(!WorkTimerStore.isDuelRoomGameSignal(.megaphoneSignal) && !WorkTimerStore.isDuelRoomGameSignal(.rummySignal),
                "기준선: 큐브 · 확성기는 방 숨이 아니다")
        let root = CheckCoreSourceLayout.repoRoot
        let store = try String(contentsOf: root.appendingPathComponent("Sources/check/WorkTimerStore.swift"), encoding: .utf8)
        for line in ["duelRooms.attach(host: self)", "DuelRoomsHub.store = duelRooms",
                     "case .gomoku: await self.gomoku.adoptRoomMatch(matchID)",
                     "case .alkkagi: await self.alkkagi.adoptRoomMatch(matchID)",
                     "duelRooms.onRoomStarted = ", "duelRooms.onJoined = "] {
            #expect(store.contains(line), "배선 줄이 없다: \(line)")
        }
        for (file, game) in [("GomokuPanel", ".gomoku"), ("ChessPanel", ".chess"), ("ReversiPanel", ".reversi"),
                             ("AlkkagiOnlinePanel", ".alkkagi")] {
            let src = try String(contentsOf: root.appendingPathComponent("Sources/check/\(file).swift"), encoding: .utf8)
            #expect(src.contains("DuelRoomsLobbyColumn(game: \(game))"), "\(file) 로비에 방 탭이 없다")
        }
        for (file, game) in [("TetrisDuelPanel", ".tetris"), ("CrossyDuelPanelLobby", ".crossyDuel")] {
            let src = try String(contentsOf: root.appendingPathComponent("Sources/check/\(file).swift"), encoding: .utf8)
            #expect(src.contains("DuelRoomsTab(store: rooms, game: \(game))"), "\(file) 로비에 방 탭이 없다")
        }
    }
}

// MARK: - 로비 렌더(여섯 게임 · 시안 PNG)

@MainActor
private func drSeededStore(door: Bool = true, mine: DuelRoom? = nil) throws -> DuelRoomStore {
    let store = DuelRoomStore(clock: { Date(timeIntervalSince1970: 1_794_293_600) })
    store.doorOpen = door
    store.myRoom = mine
    let now = 1_794_293_600_000.0
    func room(_ n: Int, _ name: String, _ character: String, stake: Int, minutesAgo: Double, game: DuelRoomGame) -> DuelRoom {
        DuelRoom(id: "00000000-0000-4000-8000-0000000000\(10 + n)", game: game, stake: stake, createdMs: now - minutesAgo * 60_000,
                 host: DuelRoomHost(userID: "00000000-0000-4000-8000-0000000001\(10 + n)", displayName: name, character: character))
    }
    for game in DuelRoomGame.allCases {
        store.rooms[game] = [room(1, "민수", "fox", stake: 5, minutesAgo: 2, game: game),
                             room(2, "서연", "ghost", stake: 10, minutesAgo: 0.2, game: game),
                             room(3, "준호", "squirrel", stake: 3, minutesAgo: 7, game: game)]
        store.loadedGames.insert(game)
    }
    store.rubyBalanceSource = { 42 }
    return store
}

@MainActor
private func drBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.environment(\.colorScheme, .dark), scale: 2) else { throw CancellationError() }
    return bitmap
}

@MainActor
private func drSave(_ bitmap: NSBitmapImageRep, _ name: String) { MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "duel-rooms") }

private func drDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let da = a.bitmapData, let db = b.bitmapData, a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 255 }
    var worst = 0
    let spp = a.samplesPerPixel, bpr = a.bytesPerRow
    for y in stride(from: Int(rect.minY * 2), to: min(Int(rect.maxY * 2), a.pixelsHigh), by: 3) {
        for x in stride(from: Int(rect.minX * 2), to: min(Int(rect.maxX * 2), a.pixelsWide), by: 3) {
            let o = y * bpr + x * spp
            worst = max(worst, abs(Int(da[o]) - Int(db[o])), abs(Int(da[o + 1]) - Int(db[o + 1])))
        }
    }
    return worst
}

@MainActor
@Suite("1:1 대기방 — 여섯 로비 렌더", .serialized)
struct V03xxDuelRoomsRenderTests {
    private func lobbies() -> [(String, AnyView)] {
        [("1-gomoku", AnyView(GomokuPanel(store: GomokuStore(), clipsOverflowInsteadOfScroll: true))),
         ("2-chess", AnyView(ChessPanel(store: ChessStore(), clipsOverflowInsteadOfScroll: true))),
         ("3-tetris", AnyView(TetrisDuelPanel(store: TetrisDuelStore(), clipsOverflowInsteadOfScroll: true))),
         ("4-reversi", AnyView(ReversiPanel(store: ReversiStore(), clipsOverflowInsteadOfScroll: true))),
         ("5-crossy", AnyView(CrossyDuelPanel(store: CrossyDuelStore(), clipsOverflowInsteadOfScroll: true))),
         ("6-alkkagi", AnyView(AlkkagiOnlinePanel(store: AlkkagiOnlineStore(), clipsOverflowInsteadOfScroll: true)))]
    }

    @Test("문이 열리면 여섯 로비 왼쪽 열 맨 위에 방 탭(방 셋) · 기준선: 문 닫힘이면 그 자리가 원래 로비 그대로")
    func sixLobbiesShowRoomsTab() throws {
        let saved = DuelRoomsHub.store
        defer { DuelRoomsHub.store = saved }
        for (name, view) in lobbies() {
            DuelRoomsHub.store = try drSeededStore(door: true)
            let open = try drBitmap(view)
            drSave(open, name)
            DuelRoomsHub.store = try drSeededStore(door: false)
            let closed = try drBitmap(view)
            let left = CGRect(x: 20, y: 72, width: 380, height: 300)
            let diff = drDiff(open, closed, rect: left)
            print("[대기방] \(name) 왼쪽 열 차 \(diff)")
            #expect(diff > 60, "\(name): 문을 열어도 왼쪽 열이 그대로다(방 탭이 안 섰다)")
        }
    }

    @Test("방 탭 세 모양 — 방 만들기 펼침 · 내 방(기다리는 중) · 다른 게임에 연 방")
    func roomStates() throws {
        let saved = DuelRoomsHub.store
        defer { DuelRoomsHub.store = saved }
        let base = try drSeededStore()
        let creating = try drBitmap(DuelRoomsTab(store: base, game: .reversi, loadsRooms: false, initiallyCreating: true)
                                        .frame(width: 420, height: 560).padding(20).background(CheckTheme.background))
        drSave(creating, "7-create")
        let mineRoom = DuelRoom(id: "00000000-0000-4000-8000-000000000099", game: .reversi, stake: 5,
                                createdMs: 1_794_293_600_000 - 70_000)
        let mine = try drBitmap(DuelRoomsTab(store: try drSeededStore(mine: mineRoom), game: .reversi, loadsRooms: false)
                                    .frame(width: 420, height: 560).padding(20).background(CheckTheme.background))
        drSave(mine, "8-my-room")
        let other = try drBitmap(DuelRoomsTab(store: try drSeededStore(mine: mineRoom), game: .gomoku, loadsRooms: false)
                                     .frame(width: 420, height: 560).padding(20).background(CheckTheme.background))
        drSave(other, "9-other-game-room")
        let full = CGRect(x: 20, y: 20, width: 420, height: 200)
        #expect(drDiff(creating, mine, rect: full) > 60 && drDiff(mine, other, rect: full) > 60, "세 모양이 같게 그려졌다")
    }
}
