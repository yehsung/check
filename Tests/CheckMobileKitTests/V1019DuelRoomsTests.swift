@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.19 — 1:1 대기방(맥 0.3.83 과 같은 코어 `DuelRoomStore` · 서버 duel-rooms · 대표 #d_xygj8oZRFlfH 1번).
// 스토어 규칙(숨 · 시작 · 참가 · 문)은 코어라 맥 `V03xxDuelRoomsTests` 가 잰다. 여기서는 폰 배선 · 절 판정 · 실시간 숨 · 여섯 로비를 잰다.

@MainActor
private final class PhoneDRScript: DuelRoomServing {
    var replies: [String: [DuelRoomsResponse]] = [:]
    private(set) var calls: [DuelRoomCall] = []
    func on(_ rpc: String, _ responses: DuelRoomsResponse...) { replies[rpc, default: []].append(contentsOf: responses) }
    func call(_ call: DuelRoomCall) async throws -> DuelRoomsResponse {
        calls.append(call)
        guard var list = replies[call.rpcName], let first = list.first else { throw CancellationError() }
        if list.count > 1 { list.removeFirst(); replies[call.rpcName] = list }
        return first
    }
}

private func fixture(_ name: String) throws -> DuelRoomsResponse {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("checkTests/Fixtures/duel-rooms/\(name).json")
    return try JSONDecoder().decode(DuelRoomsResponse.self, from: Data(contentsOf: url))
}

@MainActor
@Suite("폰 1.0.19 — 1:1 대기방", .serialized)
struct V1019DuelRoomsTests {
    @Test("절 판정: 루비를 모르면 막지 않는다 · 모자라면 [참가]가 꺼진다 · 이 게임에 내 방이 열려 있으면 다른 방에 못 든다")
    func rules() async throws {
        #expect(GamesDuelRoomsRules.affordable(stake: 5, balance: nil))
        #expect(GamesDuelRoomsRules.affordable(stake: 5, balance: 5) && !GamesDuelRoomsRules.affordable(stake: 10, balance: 9))
        #expect(GamesDuelRoomsRules.refreshSeconds == 15, "맥 DuelRoomsTab 과 같은 주기")
        let script = PhoneDRScript()
        script.on("duel_rooms_list", try fixture("list__ok"))
        let store = DuelRoomStore(service: script)
        var balance: Int? = 100
        store.rubyBalanceSource = { balance }
        await store.refresh(.reversi)
        #expect(store.doorOpen == true)
        let room = try #require(store.rooms(for: .reversi).first)
        #expect(GamesDuelRoomsRules.canJoin(room, store: store, game: .reversi))
        balance = room.stake - 1
        #expect(!GamesDuelRoomsRules.canJoin(room, store: store, game: .reversi), "루비가 모자란데 [참가]가 켜졌다")
    }

    @Test("실시간: 여섯 게임 초인종만 방 숨을 부른다(마작 · 큐브 · 확성기 · 메시지는 아니다)")
    func gameSignals() {
        for effect: RealtimeEffect in [.gomokuSignal, .chessSignal, .tetrisSignal, .reversiSignal, .crossyDuelSignal, .alkkagiSignal] {
            #expect(MobileRealtimeRunner.isDuelRoomGameSignal(effect), "\(effect)")
        }
        for effect: RealtimeEffect in [.mahjongSignal, .rummySignal, .megaphoneSignal, .drain] {
            #expect(!MobileRealtimeRunner.isDuelRoomGameSignal(effect), "\(effect)")
        }
    }

    @Test("배선: 앱이 방 스토어를 붙이고 · 방에서 선 판은 여섯 게임 스토어가 받는다(adoptRoomMatch) · 루비 미러 · 로그아웃 reset · 실시간 — 주석을 걷고 본다")
    func wiring() throws {
        let app = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileAppModel.swift").filter { !$0.isWhitespace }
        #expect(app.contains("letduelRooms=DuelRoomStore(clock:{clock.now()})") && app.contains("duelRooms.attach(host:host)"))
        #expect(app.contains("duelRooms.onRoomStarted=adoptRoomMatch") && app.contains("duelRooms.onJoined=adoptRoomMatch"))
        for call in ["gomoku?.adoptRoomMatch(matchID)", "chess?.adoptRoomMatch(matchID)", "tetris?.adoptRoomMatch(matchID)",
                     "reversi?.adoptRoomMatch(matchID)", "crossyDuel?.adoptRoomMatch(matchID)", "alkkagi?.adoptRoomMatch(matchID)"] {
            #expect(app.contains(call), "\(call) 가 없다 — 방에서 선 판을 그 게임이 받지 않는다")
        }
        #expect(app.contains("duelRooms.rubyBalanceSource={[weakhost]inhost?.rubyBalance}"))
        #expect(app.contains("realtime.duelRooms=duelRooms") && app.contains("context.duelRooms.reset()"))
        let runner = try IntegrationContractTests.code("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift").filter { !$0.isWhitespace }
        #expect(runner.contains("ifSelf.isDuelRoomGameSignal(effect){duelRooms?.handleGameSignal()}"))
    }

    @Test("여섯 로비: 각 로비가 자기 게임으로 '기다리는 방' 절을 세운다(받은 · 보낸 신청 아래) — 주석을 걷고 본다")
    func sixLobbies() throws {
        let lobbies: [(String, String)] = [
            ("GamesGomokuScreen", ".gomoku"), ("GamesChessScreen", ".chess"), ("GamesTetrisDuelScreen", ".tetris"),
            ("GamesReversiScreen", ".reversi"), ("GamesCrossyDuelScreen", ".crossyDuel"), ("GamesAlkkagiScreen", ".alkkagi"),
        ]
        for (file, game) in lobbies {
            let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/\(file).swift").filter { !$0.isWhitespace }
            #expect(code.contains("GamesDuelRoomsSection(store:store.context.duelRooms,game:\(game)"), "\(file) 에 대기방 절이 없다")
        }
        let section = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesDuelRooms.swift").filter { !$0.isWhitespace }
        #expect(section.contains("ifstore.doorOpen==true{content}"), "문이 닫혀도 절이 선다")
        #expect(section.contains(".task(id:game){awaitpoll()}") && section.contains("while!Task.isCancelled,store.doorOpen==true"),
                "문이 닫혀도 15초마다 묻는다")
        #expect(section.contains("awaitstore.join(room)") && section.contains("awaitstore.open(game,stake:store.selectedStake)"))
        #expect(section.contains("awaitstore.closeMyRoom()"))
    }
}
