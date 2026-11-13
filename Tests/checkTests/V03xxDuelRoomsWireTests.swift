// 1:1 대기방 — **운영 디코더 왕복**(SupabaseWorkService → `duelRPC` → `.convertFromSnakeCase` 디코더 → DuelRoomsResponse).
//
// 왜 따로 두는가: V03xxDuelRoomsTests 는 원문 픽스처를 **평범한 JSONDecoder()** 로 읽는다. 운영 디코더는 키를 먼저 카멜로
// 바꾸므로(`created_ms` → `createdMs`) 스네이크 원문 키로 적은 CodingKeys 는 운영에서 한 번도 맞지 않는다 — 방 줄은 전부
// 떨어지고(createdMs 필수) 내 방 · 판 id · 서버 시각 · 루비는 nil 이 된다. 그래도 평범한 디코더 테스트는 초록이다.
// 0.3.83 운영 실측: 방 90개 열림 · 참가 0 · 방장 방은 거듭 'replaced'(방장 앱이 제 방을 못 알아봐 다시 연다).
//
// 없으면 어떤 결함이 초록으로 통과하는가:
//  · 목록 원문의 방 줄이 운영 디코더에서 떨어져 [방] 탭이 늘 비어 보인다 → `duelRoomsWireListDecodesThroughService`.
//  · 방장 앱이 연 방 · 시작된 방(판 id)을 못 읽어 숨을 안 쉬고 판을 못 받는다 → `duelRoomsWireStoreThroughLiveAdapter`.
//  · 고친 디코드가 평범한 디코더 쪽(기존 픽스처 테스트)을 깨거나 두 디코더가 다른 값을 낸다 → `duelRoomsWireHarnessFixturesBothDecoders`.
//  · 디코드를 고치다 요청 본문 키(p_game · p_stake · p_room · p_protocol)가 바뀐다 → `duelRoomsWireRequestBodiesUnchanged`.
// 응답 모양은 서버 20261112120000_duel_rooms.sql 의 `duel__room_json` · `duel_rooms_list` · `duel_room_*` 의 jsonb_build_object 키
// 그대로이고, 하네스 원문은 Fixtures/duel-rooms 다. 이름 · id 는 합성 값이다.
import Foundation
import Testing
@testable import check
@testable import CheckCore

private let drwNowMs: Double = 1_794_293_541_576
private let drwMatchID = "87174E14-FCE5-444F-A24E-2C393E516C75"
private let drwMyRoomID = "00000000-0000-4000-8000-0000000000e1"
private let drwRoomA = "00000000-0000-4000-8000-0000000000a1"
private let drwRoomB = "00000000-0000-4000-8000-0000000000b2"
private let drwHostA = "00000000-0000-4000-8000-0000000001a1"
private let drwHostB = "00000000-0000-4000-8000-0000000001b2"

/// nil → JSON null(서버 jsonb 의 null 칸).
private func drwOpt(_ value: Any?) -> Any { value ?? NSNull() }

private func drwHostName(_ label: String) -> String {
    "v03xx-duel-rooms-wire-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
}

private func drwService(_ hostName: String) -> SupabaseWorkService {
    SupabaseWorkService(projectURL: URL(string: "http://\(hostName)")!, anonKey: "anon-test-key",
                        session: GomokuStubProtocol.session())
}

/// `duel__room_json(r)` 한 줄 — 키 열 개 + host 네 칸(서버 원문 그대로의 스네이크).
private func drwRoom(id: String, game: String = "reversi", stake: Int = 5, status: String = "open", createdMs: Double,
                     matchID: String? = nil, closeReason: String? = nil, hostID: String, name: String,
                     avatar: String? = nil, character: String? = nil) -> [String: Any] {
    ["id": id, "game": game, "stake": stake, "status": status,
     "created_ms": createdMs, "seen_ms": createdMs + 3_000, "expires_ms": createdMs + 1_800_000,
     "match_id": drwOpt(matchID), "close_reason": drwOpt(closeReason),
     "host": ["user_id": hostID, "display_name": name, "avatar_url": drwOpt(avatar), "character": drwOpt(character)]]
}

private func drwMine(status: String = "open", matchID: String? = nil, closeReason: String? = nil) -> [String: Any] {
    drwRoom(id: drwMyRoomID, status: status, createdMs: drwNowMs - 70_000, matchID: matchID, closeReason: closeReason,
            hostID: "00000000-0000-4000-8000-000000000001", name: "나", character: "jelly")
}

private func drwJSON(_ object: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

/// `duel_rooms_list` ok — status · protocol · server_now_ms · stakes · door_open · rooms · my_room.
private func drwListBody(mine: [String: Any]? = drwMine()) throws -> String {
    try drwJSON([
        "status": "ok", "protocol": 1, "server_now_ms": drwNowMs, "stakes": [3, 5, 10], "door_open": true,
        "rooms": [
            drwRoom(id: drwRoomA, createdMs: drwNowMs - 120_000, hostID: drwHostA, name: "민수", character: "fox"),
            drwRoom(id: drwRoomB, stake: 10, createdMs: drwNowMs - 12_000, hostID: drwHostB, name: "서연",
                    avatar: "https://example.invalid/avatar-b.png", character: "ghost"),
        ],
        "my_room": drwOpt(mine),
    ])
}

private func drwFixtureText(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/duel-rooms/\(name).json")
    return try String(contentsOf: url, encoding: .utf8)
}

/// 운영 길 한 번: 스텁 서버가 `body` 를 돌려주고 `duelRPC` 가 서비스 디코더로 읽는다. 보낸 본문도 돌려준다.
@MainActor
private func drwRoundTrip(_ call: DuelRoomCall, replying body: String) async throws -> (DuelRoomsResponse, [String: Any]) {
    let hostName = drwHostName("rt")
    GomokuStubProtocol.register(host: hostName) { _, _, _ in .init(body: body) }
    let response: DuelRoomsResponse = try await drwService(hostName)
        .duelRPC(call.rpcName, body: call.body, accessToken: "access-token")
    let sent = GomokuStubProtocol.calls(host: hostName)
    #expect(sent.map(\.rpc) == [call.rpcName])
    return (response, sent.first?.json ?? [:])
}

/// 두 디코드가 같은 값을 냈는가(DuelRoomsResponse 는 Equatable 이 아니다 — 칸마다 잰다).
private func drwSame(_ a: DuelRoomsResponse, _ b: DuelRoomsResponse) -> Bool {
    a.status == b.status && a.serverNowMs == b.serverNowMs && a.stakes == b.stakes && a.doorOpen == b.doorOpen
        && a.rooms == b.rooms && a.myRoom == b.myRoom && a.room == b.room && a.need == b.need && a.have == b.have
        && a.reason == b.reason && a.matchID == b.matchID && a.gameRaw == b.gameRaw && a.rubyBalance == b.rubyBalance
}

@MainActor
@Suite("1:1 대기방 — 운영 디코더 왕복(duelRPC · snake→camel)", .serialized)
struct V03xxDuelRoomsWireTests {
    @Test("목록 원문(방 둘 + 내 방)이 운영 디코더에서 그대로 선다 — 방 줄 · 방장 · 내 방 · 서버 시각 · 문 · 판돈")
    func duelRoomsWireListDecodesThroughService() async throws {
        let (response, sent) = try await drwRoundTrip(.list(.reversi), replying: try drwListBody())
        #expect(response.status == .ok)
        #expect(response.doorOpen == true, "door_open 이 운영 디코더에서 빠졌다")
        #expect(response.serverNowMs == drwNowMs, "server_now_ms 가 운영 디코더에서 빠졌다")
        #expect(response.stakes == [3, 5, 10])
        let rooms = response.rooms ?? []
        #expect(rooms.count == 2, "방 줄이 운영 디코더에서 떨어졌다(created_ms 등) — [방] 탭이 늘 빈다: \(rooms.count)")
        if rooms.count == 2 {
            #expect(rooms[0] == DuelRoom(id: drwRoomA, game: .reversi, stake: 5, createdMs: drwNowMs - 120_000,
                                         seenMs: drwNowMs - 117_000, expiresMs: drwNowMs - 120_000 + 1_800_000,
                                         host: DuelRoomHost(userID: drwHostA, displayName: "민수", character: "fox")))
            #expect(rooms[1].stake == 10 && rooms[1].host?.avatarURL == "https://example.invalid/avatar-b.png"
                    && rooms[1].host?.userID == drwHostB && rooms[1].host?.displayName == "서연")
        }
        let mine = response.myRoom
        #expect(mine?.id == drwMyRoomID && mine?.isOpen == true && mine?.game == .reversi,
                "my_room 이 운영 디코더에서 nil — 방장 앱이 제 방을 못 알아본다")
        #expect(sent["p_game"] as? String == "reversi" && sent["p_protocol"] as? Int == 1 && sent.count == 2)
    }

    @Test("하네스 원문 아홉 개: 운영 디코더와 평범한 디코더가 같은 값 · 칸이 실제로 찬다(판 id · 루비 · 필요 · 문 · 시각)")
    func duelRoomsWireHarnessFixturesBothDecoders() async throws {
        var production: [String: DuelRoomsResponse] = [:]
        for name in ["list__ok", "list__door_closed", "open__ok", "open__insufficient", "ping__open", "ping__started",
                     "join__ok", "join__insufficient", "join__room_gone"] {
            let text = try drwFixtureText(name)
            let plain = try JSONDecoder().decode(DuelRoomsResponse.self, from: Data(text.utf8))
            let (live, _) = try await drwRoundTrip(.ping, replying: text)
            #expect(drwSame(plain, live), "\(name): 운영 디코더와 평범한 디코더가 다른 값을 낸다")
            production[name] = live
        }
        let list = try #require(production["list__ok"])
        #expect(list.rooms?.count == 1 && list.rooms?.first?.createdMs == 1_794_293_541_575
                && list.rooms?.first?.host?.userID == "b03bcc8f-508f-42f8-8b48-59fd9dd4c462"
                && list.serverNowMs == 1_794_293_541_576 && list.doorOpen == true)
        let closed = try #require(production["list__door_closed"])
        #expect(closed.status == .unsupportedClient && closed.doorOpen == false && closed.serverNowMs == 1_794_293_541_588)
        let opened = try #require(production["open__ok"])
        #expect(opened.myRoom?.isOpen == true && opened.rubyBalance == 100 && opened.serverNowMs == 1_794_293_541_575)
        let poor = try #require(production["open__insufficient"])
        #expect(poor.status == .insufficient && poor.need == 3 && poor.have == 2 && poor.rubyBalance == 2)
        #expect(production["ping__open"]?.myRoom?.seenMs == 1_794_293_541_578)
        let started = try #require(production["ping__started"]?.myRoom)
        #expect(started.isStarted && started.matchID == "87174e14-fce5-444f-a24e-2c393e516c75" && started.closeReason == "joined")
        let joined = try #require(production["join__ok"])
        #expect(joined.status == .ok && joined.matchID == "87174e14-fce5-444f-a24e-2c393e516c75" && joined.gameRaw == "reversi"
                && joined.room?.isStarted == true && joined.serverNowMs == 1_794_293_541_587)
        let joinPoor = try #require(production["join__insufficient"])
        #expect(joinPoor.need == 5 && joinPoor.have == 2 && joinPoor.reason == "insufficient")
        #expect(production["join__room_gone"]?.status == .roomGone)
    }

    @Test("스토어 운영 어댑터(attach(host:)): 열기 → 내 방 · 목록 → 남의 방 둘 · 서버 시계 · 숨 '시작됨' → 판 한 번 · 참가 → 판")
    func duelRoomsWireStoreThroughLiveAdapter() async throws {
        let hostName = drwHostName("store")
        let list = try drwListBody()
        let opened = try drwJSON(["status": "ok", "server_now_ms": drwNowMs, "my_room": drwMine(), "ruby_balance": 100])
        let pinged = try drwJSON(["status": "ok", "server_now_ms": drwNowMs + 20_000,
                                  "my_room": drwMine(status: "started", matchID: drwMatchID, closeReason: "joined")])
        let joined = try drwJSON([
            "status": "ok", "game": "reversi", "match_id": drwMatchID, "server_now_ms": drwNowMs + 30_000, "state": ["status": "ok"],
            "room": drwRoom(id: drwRoomA, status: "started", createdMs: drwNowMs - 120_000, matchID: drwMatchID,
                            closeReason: "joined", hostID: drwHostA, name: "민수", character: "fox"),
        ])
        GomokuStubProtocol.register(host: hostName) { rpc, _, _ in
            switch rpc {
            case "duel_rooms_list": return .init(body: list)
            case "duel_room_open": return .init(body: opened)
            case "duel_room_ping": return .init(body: pinged)
            case "duel_room_join": return .init(body: joined)
            default: return .init(status: 500, body: "{}")
            }
        }
        let host = AKHost(hostName: hostName)
        let frozen = Date(timeIntervalSince1970: 1_794_293_000)
        let store = DuelRoomStore(clock: { frozen }, pingSeconds: 3_600)
        store.attach(host: host)
        defer { store.reset() }
        var started: [(DuelRoomGame, String)] = []
        var joinedMatches: [(DuelRoomGame, String)] = []
        store.onRoomStarted = { started.append(($0, $1)) }
        store.onJoined = { joinedMatches.append(($0, $1)) }

        await store.open(.reversi, stake: 5)
        #expect(store.notice == nil && store.doorOpen == true)
        #expect(store.myOpenRoom(for: .reversi)?.id == drwMyRoomID, "방장 앱이 방금 연 제 방을 못 알아본다(다시 열면 'replaced')")

        await store.refresh(.reversi)
        #expect(store.loadedGames.contains(.reversi))
        #expect(store.rooms(for: .reversi).map(\.id) == [drwRoomA, drwRoomB], "남의 방이 [방] 탭에 안 선다")
        #expect(store.serverNowMs == drwNowMs, "서버 시각(server_now_ms)으로 시계를 맞추지 못했다")
        if let first = store.rooms(for: .reversi).first {
            #expect(store.waitedSeconds(first) == 120)
        }

        await store.ping()
        #expect(started.count == 1 && started.first?.0 == .reversi && started.first?.1 == drwMatchID.lowercased(),
                "숨이 '시작됨 + 판 id' 를 돌려줘도 방장 기기가 판을 받지 않는다")
        await store.ping()
        #expect(started.count == 1, "같은 방의 시작은 한 번만")

        let target = try #require(store.rooms(for: .reversi).first)
        await store.join(target)
        #expect(joinedMatches.count == 1 && joinedMatches.first?.1 == drwMatchID.lowercased(), "참가 ok 의 match_id 를 못 읽었다")
        #expect(store.notice == nil && !store.rooms(for: .reversi).contains { $0.id == drwRoomA })

        let calls = GomokuStubProtocol.calls(host: hostName)
        #expect(calls.map(\.rpc) == ["duel_room_open", "duel_rooms_list", "duel_room_ping", "duel_room_ping", "duel_room_join"])
        withExtendedLifetime(host) {}
    }

    @Test("요청 본문 다섯 갈래의 키는 그대로(p_game · p_stake · p_room · p_protocol) — 서비스 인코더(convertToSnakeCase)를 거쳐도")
    func duelRoomsWireRequestBodiesUnchanged() async throws {
        let ok = #"{"status":"ok"}"#
        let cases: [(DuelRoomCall, [String: Any])] = [
            (.list(.crossyDuel), ["p_game": "crossy_duel", "p_protocol": 1]),
            (.open(.alkkagi, stake: 10), ["p_game": "alkkagi", "p_stake": 10, "p_protocol": 1]),
            (.close(roomID: drwMyRoomID), ["p_room": drwMyRoomID, "p_protocol": 1]),
            (.ping, ["p_protocol": 1]),
            (.join(roomID: drwRoomA), ["p_room": drwRoomA, "p_protocol": 1]),
        ]
        for (call, expected) in cases {
            let (response, sent) = try await drwRoundTrip(call, replying: ok)
            #expect(response.status == .ok)
            #expect(NSDictionary(dictionary: sent).isEqual(to: expected), "\(call.rpcName) 본문이 바뀌었다: \(sent)")
        }
    }
}
