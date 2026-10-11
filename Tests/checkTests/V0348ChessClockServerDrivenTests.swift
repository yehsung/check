import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.48 — **서버가 10분이라고 말하면 앱이 10분을 그린다.**
//
// 시계 초기값은 서버 상수(`chess_initial_ms()`)이고 `20261012120000_chess_clock_10min.sql` 이 그것을 300000 → 600000 으로
// 올린다. 서버는 앱보다 먼저 올라가고, 이미 나간 맥 앱은 고칠 수 없다. 그래서 물을 것은 "새 앱이 600 을 아는가" 가 아니라
// **"300 이 박힌 앱이 600000 응답을 받으면 무엇을 그리는가"** 다.
//
// ★ 이 파일은 **고치기 전 코드에서도 그대로 컴파일되고 통과하게** 썼다 — 0.3.48 이 더한 `ChessClock.initialMs` 를 한 번도
//   읽지 않고, 스토어의 기본값(옛 300_000 · 새 600_000)에 기대는 단언도 없다. 0.3.44~0.3.47 의 체스 소스는 한 글자도
//   다르지 않으므로(`git diff --stat v0.3.44 b1536c2 -- Sources/**/Chess*` 가 비어 있다 — 2026-10-12 실측), 고치기 전
//   트리(b1536c2)에 이 파일과 픽스처만 얹어 돌린 결과가 곧 **이미 나간 앱의 답**이다(그렇게 돌려 열 건 전부 통과했다).
//   체스가 처음 나간 0.3.43 은 말 미끄러짐만 다르고 여기서 재는 줄(로비 값 덮기 · 판 응답의 시계 · 로봇 판 초기값 ·
//   캡션 · 시계 띠 분모)은 글자까지 같다(태그별 grep 실측 — 그 버전을 빌드해 돌린 것은 아니다).
//   0.3.48 의 박힌 값 쪽 계약은 `V0348ChessClockTenMinuteTests` 가 따로 잰다.
//
// 본문은 손으로 고친 숫자가 아니라 **10분 서버가 실제로 낸 응답**이다(`Fixtures/chess-rpc-clock10/` — 체인 전체 +
// 20261012120000 을 올린 로컬 Postgres 에서 RPC 를 불러 뜬 jsonb, 생성기 `_capture.py.txt`). 대조군은 5분 서버의 응답
// (`Fixtures/chess-rpc/`)이다 — 두 서버가 **다른 값을 말할 때 화면도 다르게 나와야** 이 단언들이 무언가를 잰다.
//
// 재는 것 넷(설계서의 가·나·다·라):
//  (가) 로비의 `initial_ms` 가 캡션과 시계 띠의 분모를, 판 응답의 `white_ms_left`·`black_ms_left` 가 시계 숫자를 정한다
//  (나) 300 을 상한으로 자르거나 5분 지점에서 깃발을 되묻는 자리가 **없다**(가산이 붙어 600000 을 넘는 값도 그대로다)
//  (다) 로봇 판(로컬 시계)은 **로비가 말한 값**으로 열린다
//  (라) 관전 · 결과 화면도 서버가 준 숫자를 그대로 든다
//
// 각 시험의 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가" 다.

// MARK: - 하네스 (V0343ChessStoreTests 의 것을 복사 — 그 파일의 헬퍼는 file-private 이다)

private let sdClock10Directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc-clock10", isDirectory: true)
private let sdLegacyDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)

private struct SDError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 픽스처 **원문**(서버가 낸 글자 그대로).
private func sdText(_ name: String, in directory: URL = sdClock10Directory) throws -> String {
    try String(contentsOf: directory.appendingPathComponent("\(name).json"), encoding: .utf8)
}

private func sdJSON(_ name: String, in directory: URL = sdClock10Directory) throws -> [String: Any] {
    let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SDError("\(name) 는 JSON 객체가 아니다")
    }
    return object
}

/// 그 픽스처를 **누가 불렀는가**(매니페스트) — 세션의 user id 가 이 사람이어야 `my_color` 가 맞는다.
private func sdCaller(_ name: String, in directory: URL = sdClock10Directory) throws -> String {
    let manifest = try sdJSON("_manifest", in: directory)
    guard let fixtures = manifest["fixtures"] as? [String: Any],
          let entry = fixtures[name] as? [String: Any],
          let caller = entry["caller"] as? String else {
        throw SDError("\(name): 매니페스트에 caller 가 없다")
    }
    return caller
}

private func sdMatchRow(_ fixture: [String: Any]) throws -> [String: Any] {
    guard let row = fixture["match"] as? [String: Any] else { throw SDError("match 가 없다") }
    return row
}

private func sdInt(_ value: Any?) throws -> Int {
    guard let number = value as? NSNumber else { throw SDError("정수가 아니다: \(String(describing: value))") }
    return number.intValue
}

/// 픽스처의 `match` 와 `state.match` 를 **함께** 고친다(두 자리에 같은 행이 실려 온다 — 한쪽만 고치면 스토어가 읽는
/// 쪽이 옛 값이라 시험이 아무것도 안 잰다). **합성 본문**은 이 함수를 지난 것뿐이고, 쓰는 자리에서 그렇다고 적는다.
private func sdPatchedMatch(_ name: String, _ patch: [String: Any]) throws -> String {
    var fixture = try sdJSON(name)
    func apply(_ row: Any?) -> Any? {
        guard var dictionary = row as? [String: Any] else { return row }
        for (key, value) in patch { dictionary[key] = value }
        return dictionary
    }
    fixture["match"] = apply(fixture["match"])
    if var inner = fixture["state"] as? [String: Any] {
        inner["match"] = apply(inner["match"])
        fixture["state"] = inner
    }
    return String(decoding: try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys]), as: UTF8.self)
}

/// rpc 이름 → 응답 본문 목록(같은 rpc 의 n 번째 호출이 n 번째 본문을 받고, 모자라면 마지막 것이 반복된다).
private func sdHandler(_ map: [String: [String]]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"missing"}"#)
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)])
    }
}

@MainActor
private enum SDRetention {
    /// `WorkTimerStore` 는 체스 스토어를 **약참조**로 들린다 — 버리면 host 가 nil 이 되어 요청이 한 건도 안 나간다.
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func sdStore(
    _ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler
) -> (ChessStore, String) {
    let host = "v0348-c-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0348-chess"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    SDRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    // 실루프를 재우고 `pollTick(at:)` 을 직접 밟아 결정적으로 본다(오목 관용구).
    chess.pollStepSeconds = 3_600
    return (chess, host)
}

private func sdSquare(_ notation: String) throws -> ChessSquare {
    guard let square = ChessSquare(notation) else { throw SDError("칸 이름이 아니다: \(notation)") }
    return square
}

private let sdCaptionTen = "FIDE 규칙 · 백 선공 · 10분 + 한 수 3초"
private let sdCaptionFive = "FIDE 규칙 · 백 선공 · 5분 + 한 수 3초"

@Suite("체스 시계 — 서버가 10분이라고 말할 때 앱이 그리는 것(이미 나간 앱의 대역)")
struct V0348ChessClockServerDrivenTests {

    // MARK: - (가) 캡션 · 시계 띠의 분모는 로비가 정한다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func lobbyInitialMsDrivesTheCaptionAndTheClockBarDenominator() async throws {
        // 없으면: 캡션이 서버 값이 아니라 박힌 상수를 읽어도(= 서버만 올린 날 이미 나간 앱이 계속 "5분" 을 말해도) 초록이다.
        let lobby = "chess_lobby__ok_empty"
        #expect(try sdInt(try sdJSON(lobby)["initial_ms"]) == 600_000, "전제: 10분 서버가 낸 로비다")
        let (store, host) = sdStore("cap10", me: try sdCaller(lobby),
                                    handler: sdHandler(["chess_lobby": [try sdText(lobby)]]))
        await store.refreshLobby()

        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_lobby") == 1)
        #expect(store.hasLoadedLobby)
        #expect(!store.lobbyLoadFailed, "600000 을 말하는 로비를 실패로 접었다")
        #expect(store.notice == nil, "600000 을 말하는 로비에 안내 문구가 붙었다: \(store.notice ?? "")")
        #expect(store.initialMs == 600_000)
        #expect(store.incrementMs == 3_000)
        #expect(store.graceMs == 2_000)
        // 화면이 실제로 읽는 두 자리: 머리글 캡션, 그리고 시계 띠의 분모(`ChessClockFace(total:)`).
        #expect(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs) == sdCaptionTen)
        #expect(Double(store.initialMs) / 1000 == 600)

        // ★ 대조군: **5분 서버**의 로비를 먹인 같은 코드는 5분을 말한다 — 캡션이 상수가 아니라 응답을 따른다는 증거다.
        let (legacy, _) = sdStore("cap5", me: try sdCaller(lobby, in: sdLegacyDirectory),
                                  handler: sdHandler(["chess_lobby": [try sdText(lobby, in: sdLegacyDirectory)]]))
        await legacy.refreshLobby()
        #expect(legacy.initialMs == 300_000)
        #expect(ChessText.subtitle(initialMs: legacy.initialMs, incrementMs: legacy.incrementMs) == sdCaptionFive)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aRunningAppFollowsTheServerWhenTheValueChangesUnderIt() async throws {
        // 없으면: 값을 **처음 한 번만** 받아 굳히는 구현이 통과한다 — 서버를 올리는 순간 켜져 있던 앱은 다시 켤 때까지
        // 5분 캡션으로 10분 판을 연다. 배포 순간의 모양 그대로다: 같은 스토어가 5분 로비를 읽고, 그다음 10분 로비를 읽는다.
        let lobby = "chess_lobby__ok_empty"
        let (store, host) = sdStore("flip", me: try sdCaller(lobby), handler: sdHandler([
            "chess_lobby": [try sdText(lobby, in: sdLegacyDirectory), try sdText(lobby)]
        ]))
        await store.refreshLobby()
        #expect(store.initialMs == 300_000)
        #expect(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs) == sdCaptionFive)

        await store.refreshLobby()
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_lobby") == 2)
        #expect(store.initialMs == 600_000)
        #expect(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs) == sdCaptionTen)
    }

    // MARK: - (가) 시계 숫자는 판 응답이 정한다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func matchClockShowsTenMinutesStraightFromTheServerRow() async throws {
        // 없으면: 판 응답의 남은 시간을 앱의 초기값으로 덮거나 그 아래로 누르는 구현이 통과한다 — 10분 판이 5:00 에서 시작한다.
        // ★ 로비를 **읽지 않고** 판부터 연다(로비 조회가 실패한 앱의 모양). 시계 숫자는 그래도 서버 값이어야 한다.
        let name = "chess_state__ok_initial_my_turn"
        let fixture = try sdJSON(name)
        let row = try sdMatchRow(fixture)
        let matchID = try #require(row["id"] as? String)
        let (store, _) = sdStore("clock", me: try sdCaller(name),
                                 handler: sdHandler(["chess_state": [try sdText(name)]]))
        await store.refreshMatch(id: matchID)

        let match = try #require(store.match)
        #expect(match.myColor == .white)
        #expect(match.isMyTurn)
        #expect(match.clock.whiteMsLeft == 600_000)
        #expect(match.clock.blackMsLeft == 600_000)
        #expect(match.clock.incrementMs == 3_000)
        #expect(match.clock.running == .white)

        let turnStarted = try #require(store.deviceDate(serverMs: row["turn_started_ms"] as? Double))
        // 차례가 시작된 순간 둘 다 10분, 30초 뒤에는 도는 쪽만 9분 30초다.
        #expect(abs(match.clock.remainingSeconds(.white, now: turnStarted) - 600) < 0.001)
        #expect(match.clock.remainingSeconds(.black, now: turnStarted) == 600)
        let later = turnStarted.addingTimeInterval(30)
        #expect(abs(match.clock.remainingSeconds(.white, now: later) - 570) < 0.001)
        #expect(match.clock.remainingSeconds(.black, now: later) == 600)
        // 마감은 시작 + 10분이다(서버 `deadline_ms` 와 같은 값).
        let deadline = try #require(match.clock.deadline)
        #expect(abs(deadline.timeIntervalSince(turnStarted) - 600) < 0.001)
        let serverDeadline = try #require(store.deviceDate(serverMs: row["deadline_ms"] as? Double))
        #expect(abs(deadline.timeIntervalSince(serverDeadline)) < 0.001)

        // 화면 글자: 스토어가 든 초를 잎 뷰가 이 함수로 그린다.
        let shown = try #require(store.remainingSeconds(.white, now: turnStarted))
        #expect(ChessText.clock(shown) == "10:00")
        #expect(ChessText.clockAccessibility(shown) == "남은 시간 10분 0초")
        #expect(ChessText.clock(try #require(store.remainingSeconds(.white, now: later))) == "9:30")

        // ★ 대조군: 5분 서버가 낸 같은 장면은 5:00 이다.
        let (legacy, _) = sdStore("clock5", me: try sdCaller(name, in: sdLegacyDirectory),
                                  handler: sdHandler(["chess_state": [try sdText(name, in: sdLegacyDirectory)]]))
        let legacyRow = try sdMatchRow(try sdJSON(name, in: sdLegacyDirectory))
        await legacy.refreshMatch(id: legacyRow["id"] as? String)
        let legacyMatch = try #require(legacy.match)
        let legacyStarted = try #require(legacy.deviceDate(serverMs: legacyRow["turn_started_ms"] as? Double))
        #expect(legacyMatch.clock.whiteMsLeft == 300_000)
        #expect(ChessText.clock(try #require(legacy.remainingSeconds(.white, now: legacyStarted))) == "5:00")
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func acceptingAnInviteOpensATenMinuteBoardForBlack() async throws {
        // 없으면: 수락 응답(`chess_respond`)의 상태 봉투만 다른 길로 읽어 시계를 자리표시(옛 5분)로 두는 구현이 통과한다 —
        // 수락한 사람만 5:00 을 보고 상대는 10:00 을 본다.
        let name = "chess_respond__accept_ok"
        let fixture = try sdJSON(name)
        let row = try sdMatchRow(fixture)
        let matchID = try #require(row["id"] as? String)
        let (store, host) = sdStore("accept", me: try sdCaller(name),
                                    handler: sdHandler(["chess_respond": [try sdText(name)]]))
        await store.respond(inviteID: matchID, accept: true)

        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_respond") == 1)
        let match = try #require(store.match)
        #expect(match.id == matchID)
        #expect(match.myColor == .black, "픽스처는 흑(B)이 수락한 응답이다")
        #expect(match.turn == .white)
        #expect(match.clock.whiteMsLeft == 600_000)
        #expect(match.clock.blackMsLeft == 600_000)
        #expect(match.whiteGraceMs == 2_000)
        #expect(match.blackGraceMs == 2_000)
        let turnStarted = try #require(store.deviceDate(serverMs: row["turn_started_ms"] as? Double))
        let pair = try #require(store.remainingSecondsPair(now: turnStarted))
        #expect(ChessText.clock(pair.mine) == "10:00")
        #expect(ChessText.clock(pair.opponent) == "10:00")
    }

    // MARK: - (나) 300 에서 자르거나 5분 지점에서 깃발을 되묻는 자리가 없다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func clockAboveTheOldInitialIsNeitherClampedNorRefused() async throws {
        // 없으면: `min(서버 값, 초기값)` 류의 상한이 통과한다 — 10분 판의 시계가 5:00 에 붙어 있다가 서버의 진짜 남은
        // 시간이 5분 아래로 내려와야 움직이기 시작한다. 5분 서버의 픽스처로는 이 상한이 **한 번도 닿지 않는다**.
        let initial = "chess_state__ok_initial_my_turn"
        let moved = "chess_move__ok_white_first"
        let movedRow = try sdMatchRow(try sdJSON(moved))
        let whiteAfter = try sdInt(movedRow["white_ms_left"])
        #expect(whiteAfter > 600_000, "전제: 가산이 붙어 초기값을 넘은 응답이다(\(whiteAfter))")
        let matchID = try #require(movedRow["id"] as? String)
        let (store, host) = sdStore("noclamp", me: try sdCaller(initial), handler: sdHandler([
            "chess_state": [try sdText(initial)], "chess_move": [try sdText(moved)]
        ]))
        await store.refreshMatch(id: matchID)
        await store.tap(try sdSquare("e2"))
        await store.tap(try sdSquare("e4"))

        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_move") == 1)
        let match = try #require(store.match)
        #expect(match.plyCount == 1)
        #expect(match.turn == .black)
        // 가산이 붙어 **초기값을 넘은** 숫자가 한 ms 도 안 깎이고 그대로 섰다.
        #expect(match.clock.whiteMsLeft == whiteAfter)
        #expect(match.clock.blackMsLeft == 600_000)
        #expect(store.notice == nil, "초기값을 넘은 시계에 안내 문구가 붙었다: \(store.notice ?? "")")
        // 백은 멈춘 쪽이라 언제 물어도 그 값이다 — 화면은 10:02 를 그린다.
        let white = try #require(store.remainingSeconds(.white, now: store.clock().addingTimeInterval(3_600)))
        #expect(white == Double(whiteAfter) / 1000)
        #expect(ChessText.clock(white) == String(format: "%d:%02d", whiteAfter / 60_000, (whiteAfter / 1000) % 60))

        // 더 멀리(합성 본문 — 서버 원문의 판 행에서 두 칸만 바꿨다): 30분을 줘도 30분이다. 상한은 어디에도 없다.
        let (far, _) = sdStore("far", me: try sdCaller(initial), handler: sdHandler([
            "chess_state": [try sdPatchedMatch(initial, ["white_ms_left": 1_800_000, "black_ms_left": 1_799_000])]
        ]))
        await far.refreshMatch(id: matchID)
        let farMatch = try #require(far.match)
        #expect(farMatch.clock.whiteMsLeft == 1_800_000)
        #expect(farMatch.clock.blackMsLeft == 1_799_000)
        #expect(ChessText.clock(Double(farMatch.clock.blackMsLeft) / 1000) == "29:59")
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func flagIsNotReportedAtTheOldFiveMinuteMark() async throws {
        // 없으면: 깃발 되묻기가 서버가 준 남은 시간이 아니라 박힌 300초로 계산돼도 초록이다 — 10분 판의 5분 지점부터
        // 내 차례인데도 앱이 1초마다 `chess_state` 를 쏜다(무료 플랜 예산), 그리고 화면은 0.0 을 그린다.
        let name = "chess_state__ok_initial_my_turn"
        let row = try sdMatchRow(try sdJSON(name))
        let matchID = try #require(row["id"] as? String)
        let (store, host) = sdStore("flag", me: try sdCaller(name),
                                    handler: sdHandler(["chess_state": [try sdText(name)]]))
        await store.refreshMatch(id: matchID)
        store.isWindowVisible = true
        let match = try #require(store.match)
        let turnStarted = try #require(store.deviceDate(serverMs: row["turn_started_ms"] as? Double))
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1)

        // 옛 초기값(300초)을 막 넘긴 순간: 내 차례이고 시간은 4분 59초가 남았다 — 되물을 것이 없다.
        #expect(!match.isFlagOverdue(now: turnStarted.addingTimeInterval(301), graceSeconds: store.graceSeconds))
        await store.pollTick(at: turnStarted.addingTimeInterval(301))
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1, "5분 지점에서 깃발을 되물었다")
        #expect(ChessText.clock(try #require(store.remainingSeconds(.white, now: turnStarted.addingTimeInterval(301))))
                == "4:59")

        // 10분을 다 쓰고도 서버 유예 예산(2초) 안이면 아직 아니다. 그것까지 넘기면 조회 한 번으로 신고한다.
        #expect(!match.isFlagOverdue(now: turnStarted.addingTimeInterval(601.5), graceSeconds: store.graceSeconds))
        #expect(match.isFlagOverdue(now: turnStarted.addingTimeInterval(602.5), graceSeconds: store.graceSeconds))
        await store.pollTick(at: turnStarted.addingTimeInterval(602.5))
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 2, "10분 + 유예를 넘겼는데 신고하지 않았다")

        // ★ 대조군: 5분 서버의 같은 장면은 **바로 그 301초에서 2.5초 뒤** 깃발이다 — 문턱이 서버 값을 따라 움직인다.
        let legacyRow = try sdMatchRow(try sdJSON(name, in: sdLegacyDirectory))
        let (legacy, _) = sdStore("flag5", me: try sdCaller(name, in: sdLegacyDirectory),
                                  handler: sdHandler(["chess_state": [try sdText(name, in: sdLegacyDirectory)]]))
        await legacy.refreshMatch(id: legacyRow["id"] as? String)
        let legacyMatch = try #require(legacy.match)
        let legacyStarted = try #require(legacy.deviceDate(serverMs: legacyRow["turn_started_ms"] as? Double))
        #expect(legacyMatch.isFlagOverdue(now: legacyStarted.addingTimeInterval(302.5), graceSeconds: legacy.graceSeconds))
        #expect(!match.isFlagOverdue(now: turnStarted.addingTimeInterval(302.5), graceSeconds: store.graceSeconds))
    }

    // MARK: - (다) 로봇 판은 로비가 말한 값으로 열린다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func robotMatchOpensWithTheValueTheLobbyAnnounced() async throws {
        // 없으면: 로봇 판이 서버 값이 아니라 자기 기본값으로만 열려도 초록이다 — 서버를 10분으로 올린 뒤 이미 나간 앱에서
        // 사람과 두는 판은 10분인데 로봇과 두는 판은 5분이다(같은 창, 같은 캡션 아래).
        let lobby = "chess_lobby__ok_empty"
        let (store, host) = sdStore("robot10", me: try sdCaller(lobby),
                                    handler: sdHandler(["chess_lobby": [try sdText(lobby)]]))
        await store.refreshLobby()
        store.startAIMatch(humanColor: .white)

        let opened = try #require(store.match)
        #expect(store.isAIMatch)
        #expect(opened.clock.whiteMsLeft == 600_000)
        #expect(opened.clock.blackMsLeft == 600_000)
        #expect(store.aiGame?.msLeft(.white) == 600_000)
        #expect(store.aiGame?.msLeft(.black) == 600_000)
        #expect(opened.clock.incrementMs == 3_000)
        // 캡션과 판이 같은 말을 한다.
        #expect(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs) == sdCaptionTen)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 0, "로봇 판이 서버에 상태를 물었다")
        store.reset()

        // ★ 대조군: 5분 서버의 로비를 읽은 앱의 로봇 판은 5분이다 — 로봇 판이 **로비 값을 따른다**는 증거다.
        let (legacy, _) = sdStore("robot5", me: try sdCaller(lobby, in: sdLegacyDirectory),
                                  handler: sdHandler(["chess_lobby": [try sdText(lobby, in: sdLegacyDirectory)]]))
        await legacy.refreshLobby()
        legacy.startAIMatch(humanColor: .white)
        #expect(legacy.match?.clock.whiteMsLeft == 300_000)
        #expect(legacy.aiGame?.msLeft(.black) == 300_000)
        legacy.reset()
    }

    // MARK: - (라) 관전 · 결과 화면

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func spectatorSeesTheServerClock() async throws {
        // 없으면: 관전 시계가 판 응답이 아니라 자리표시(옛 5분)에서 출발해도 초록이다 — 대국자는 10:00 을 보는데
        // 구경하는 사람은 5:00 을 본다.
        let name = "chess_watch__ok_active"
        let fixture = try sdJSON(name)
        let row = try sdMatchRow(fixture)
        let matchID = try #require(row["id"] as? String)
        let (store, host) = sdStore("watch", me: try sdCaller(name),
                                    handler: sdHandler(["chess_watch": [try sdText(name)]]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.spectating = ChessSpectateState(id: matchID)
        await store.refreshWatch()

        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_watch") == 1)
        let watched = try #require(store.spectating)
        #expect(watched.plyCount == 0)
        #expect(watched.clock.whiteMsLeft == 600_000)
        #expect(watched.clock.blackMsLeft == 600_000)
        #expect(watched.clock.running == .white)
        let turnStarted = try #require(store.deviceDate(serverMs: row["turn_started_ms"] as? Double))
        #expect(ChessText.clock(watched.clock.remainingSeconds(.white, now: turnStarted)) == "10:00")
        #expect(ChessText.clock(watched.clock.remainingSeconds(.black, now: turnStarted)) == "10:00")
        // 5분 지점에서도 관전 시계는 5분이 남았다(0 에서 굳지 않는다).
        #expect(ChessText.clock(watched.clock.remainingSeconds(.white, now: turnStarted.addingTimeInterval(300)))
                == "5:00")
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func finishedBoardKeepsTheClocksTheServerEndedWith() async throws {
        // 없으면: 끝난 판의 시계를 초기값으로 되돌리거나 자르는 구현이 통과한다 — 결과 화면이 "10:02 대 10:00" 으로 끝난
        // 판을 "5:00 대 5:00" 으로 그린다. 결과·사유·루비는 시계와 무관하게 그대로여야 한다.
        let name = "chess_state__ok_finished_winner"
        let fixture = try sdJSON(name)
        let row = try sdMatchRow(fixture)
        let matchID = try #require(row["id"] as? String)
        let white = try sdInt(row["white_ms_left"])
        let black = try sdInt(row["black_ms_left"])
        #expect(white > 600_000 && black == 600_000, "전제: 백이 한 수 두고(가산) 흑이 기권한 판이다")
        let (store, _) = sdStore("done", me: try sdCaller(name),
                                 handler: sdHandler(["chess_state": [try sdText(name)]]))
        await store.refreshMatch(id: matchID)

        let match = try #require(store.match)
        #expect(match.isFinished)
        #expect(match.outcome == .won)
        #expect(match.endReason == .resign)
        #expect(match.rubyDelta == match.stake)
        #expect(match.stake == 5)
        #expect(match.clock.whiteMsLeft == white)
        #expect(match.clock.blackMsLeft == black)
        // 끝난 판의 시계는 멈춰 있다 — 한 시간 뒤에 물어도 같은 숫자다.
        #expect(match.clock.running == nil)
        let muchLater = store.clock().addingTimeInterval(3_600)
        #expect(match.clock.remainingSeconds(.white, now: muchLater) == Double(white) / 1000)
        #expect(ChessText.clock(match.clock.remainingSeconds(.black, now: muchLater)) == "10:00")
        #expect(!match.isFlagOverdue(now: muchLater, graceSeconds: store.graceSeconds))
    }

    // MARK: - 시계 칸: 다섯 글자가 들어간다

    @Test
    @MainActor
    func tenMinuteClockTextFitsTheClockCell() {
        // 없으면: 시계 칸 폭이 "5:00"(네 글자)에 맞춰져 있어 "10:00" 이 줄어들거나 잘려도 초록이다.
        // `ChessClockFace` 는 20pt 굵은 숫자를 monospacedDigit 로, 좌우 6pt 안쪽에 그린다(같은 서체로 폭을 잰다).
        let font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let inner = ChessWindowLayout.clockWidth - 6 * 2
        // 가산으로 10분을 넘긴 값(10:03)과 한참 벌어 둔 값(19:59)까지 — 숫자 폭이 같아 다섯 글자면 전부 같은 폭이다.
        for seconds in [600.0, 603.0, 1_199.0] {
            let text = ChessText.clock(seconds)
            #expect(text.count == 5, "\(text)")
            #expect(width(text) <= inner, "\(text) 는 \(width(text))pt — 칸 안쪽 \(inner)pt 를 넘는다")
        }
        // ★ 기준선: 이 자가 글자 수를 실제로 잰다(네 글자보다 다섯 글자가 넓다) — 늘 통과하는 자가 아니다.
        #expect(width(ChessText.clock(600)) > width(ChessText.clock(300)))
        #expect(width("100:00:00") > inner, "아홉 글자도 들어간다면 이 자는 아무것도 재지 않는다")
    }
}
