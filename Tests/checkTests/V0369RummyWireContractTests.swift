import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 아잉 큐브 — **서버 계약 합류** 시험(통합 갈래).
//
// 두 가지를 잰다.
// ① 실서버 출력 픽스처(`Fixtures/rummy/server/*.json`, S 갈래가 하네스에서 실제 RPC 를 불러 뜬 43장)가 전부 디코드되고,
//    디코드한 값이 원본 JSON 의 값과 같다(키 이름·중첩·null 자리가 어긋나면 옵셔널이 조용히 nil 이 돼 초록이 되는 결함을 막는다).
//    숨은 정보 규칙(§3.7 — 남의 랙·pool 내용이 어디에도 없다)도 원본 JSON 에서 잰다.
// ② 와이어 요청 본문 키 집합 = 마이그레이션 `20261103120000_rummy.sql` 의 RPC 인자 이름(소스 계약). 이름 하나가 어긋나면
//    PostgREST 가 함수를 못 찾는다(PGRST202) — 스텁 시험은 그걸 못 본다.
//    마이그레이션은 `supabase/`(gitignore) 에 있다 — 워크트리면 메인의 supabase 를 통째 복사하거나 CHECK_MIGRATIONS_DIR 로 가리켜라.

let rwcMigrationName = "20261103120000_rummy.sql"

private let rwcFixtureFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/rummy/server", isDirectory: true)

func rwcMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        directory = directory.deletingLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

/// `--` 주석을 걷은 아잉 큐브 마이그레이션(설명을 지워야만 초록이 되는 시험이 되지 않게).
func rwcMigrationSQL() throws -> String {
    let raw = try String(contentsOf: rwcMigrationsDirectory().appendingPathComponent(rwcMigrationName), encoding: .utf8)
    return raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 마이그레이션에서 `public.<rpc>(` 의 **마지막** 정의가 받는 인자 이름 집합.
func rwcSQLArguments(_ rpc: String, in sql: String) throws -> Set<String>? {
    let pattern = #"create\s+or\s+replace\s+function\s+public\.\#(rpc)\s*\((.*?)\)\s*returns"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    guard let match = regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)).last,
          let range = Range(match.range(at: 1), in: sql) else { return nil }
    let names = sql[range].split(separator: ",").compactMap { part -> String? in
        part.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map { String($0).lowercased() }
    }
    return Set(names)
}

private func rwcDecode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
}

private func rwcFaces(_ any: Any?) -> [String]? { any as? [String] }
private func rwcInt(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue }

@Suite("v0.3.69 아잉 큐브 — 서버 계약 합류(픽스처 · 인자 이름)")
struct V0369RummyWireContractTests {
    private func fixtures() throws -> [(name: String, data: Data, object: [String: Any])] {
        let files = try FileManager.default.contentsOfDirectory(at: rwcFixtureFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { file in
            let data = try Data(contentsOf: file)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "객체가 아니다: \(file.lastPathComponent)")
            return (file.deletingPathExtension().lastPathComponent, data, object)
        }
    }

    @Test("픽스처 43장이 전부 디코드되고 status 가 원본 글자와 같다(모르는 값 .unknown 없음)")
    func allFixturesDecode() throws {
        // 없으면: 실서버가 내는 status 하나를 클라가 몰라 .unknown 으로 접는(버튼이 아무 문구 없이 멎는) 결함이 초록이 된다.
        let all = try fixtures()
        #expect(all.count == 43, "픽스처 \(all.count)장(기대 43 — S-d 산출)")
        for (name, data, object) in all {
            let raw = try #require(object["status"] as? String, "status 없음: \(name)")
            let decoded: RummyRPCStatus
            if name.hasPrefix("lobby") {
                decoded = try rwcDecode(RummyLobby.self, data).status
            } else if name.hasPrefix("ranking") {
                decoded = try rwcDecode(RummyRanking.self, data).status
            } else {
                decoded = try rwcDecode(RummyActionResponse.self, data).status
            }
            #expect(decoded.rawValue == raw, "\(name): status \(raw) → \(decoded)")
            #expect(decoded != .unknown, "\(name): 모르는 status \(raw)")
        }
    }

    @Test("state 가 실린 응답마다 디코드 값 = 원본 값(seq·자리·랙·판·더미·차례·작업 판·끝 이유·정산)")
    func stateValuesRoundTrip() throws {
        // 없으면: 키 이름 하나(예: turn_deadline_ms)가 어긋나도 옵셔널이 nil 로 조용히 비어 남은 시간이 안 뜨는 결함이 초록이 된다.
        var checked = 0
        for (name, data, object) in try fixtures() {
            guard let rawState = object["state"] as? [String: Any] else { continue }
            let state = try #require(try rwcDecode(RummyActionResponse.self, data).state, "\(name): state 디코드 실패")
            checked += 1
            #expect(state.id.uuidString.lowercased() == rawState["id"] as? String, "\(name): id")
            #expect(state.status?.rawValue == rawState["status"] as? String, "\(name): status")
            #expect(state.status != .unknown, "\(name): 모르는 판 status")
            #expect(state.seq == rwcInt(rawState["seq"]), "\(name): seq")
            #expect(state.stake == rwcInt(rawState["stake"]), "\(name): stake")
            #expect(state.mySeatNo == rwcInt(rawState["my_seat_no"]), "\(name): my_seat_no")
            #expect(state.myRack?.map(\.text) == rwcFaces(rawState["my_rack"]), "\(name): my_rack")
            #expect(state.poolCount == rwcInt(rawState["pool_count"]), "\(name): pool_count")
            #expect(state.turnSeatNo == rwcInt(rawState["turn_seat_no"]), "\(name): turn_seat_no")
            #expect((state.turnDeadlineMs != nil) == (rawState["turn_deadline_ms"] is NSNumber), "\(name): turn_deadline_ms")
            #expect(state.endReason?.rawValue == rawState["end_reason"] as? String, "\(name): end_reason")
            let rawTable = (rawState["table"] as? [[String]]) ?? []
            #expect(state.table?.map { $0.map(\.text) } ?? [] == rawTable, "\(name): table")
            let rawDraft = rawState["draft"] as? [String: Any]
            #expect(state.draft?.table?.map { $0.map(\.text) } == rawDraft?["table"] as? [[String]], "\(name): draft.table")
            #expect(state.draft?.draftSeq == rwcInt(rawDraft?["draft_seq"]), "\(name): draft_seq")
            let rawEvent = rawState["last_event"] as? [String: Any]
            #expect(state.lastEvent?.kind == rawEvent?["kind"] as? String, "\(name): last_event.kind")
            let rawSeats = (rawState["seats"] as? [[String: Any]]) ?? []
            #expect(state.seats?.count == rawSeats.count, "\(name): 자리 수")
            for (seat, rawSeat) in zip(state.seats ?? [], rawSeats) {
                #expect(seat.userId.uuidString.lowercased() == rawSeat["user_id"] as? String, "\(name): seat user_id")
                #expect(seat.state?.rawValue == rawSeat["state"] as? String, "\(name): seat state")
                #expect(seat.state != .unknown, "\(name): 모르는 자리 state")
                #expect(seat.seatNo == rwcInt(rawSeat["seat_no"]), "\(name): seat_no")
                #expect(seat.rackCount == rwcInt(rawSeat["rack_count"]), "\(name): rack_count")
                #expect(seat.finalRank == rwcInt(rawSeat["final_rank"]), "\(name): final_rank")
                #expect(seat.payout == rwcInt(rawSeat["payout"]), "\(name): payout")
                #expect(seat.finalRack?.map(\.text) == rwcFaces(rawSeat["final_rack"]), "\(name): final_rack")
            }
            // §3.7 숨은 정보: 남의 랙·pool 내용은 어떤 응답에도 없다. 내 랙은 내가 playing 일 때만.
            #expect(rawState["pool"] == nil, "\(name): pool 내용이 실렸다")
            for rawSeat in rawSeats { #expect(rawSeat["rack"] == nil, "\(name): 자리 rack 내용이 실렸다") }
            if state.status != .finished {
                for rawSeat in rawSeats { #expect(rawSeat["final_rack"] is NSNull || rawSeat["final_rack"] == nil, "\(name): 끝나기 전 final_rack") }
            }
            if state.myRack != nil {
                let me = state.seats?.first { $0.seatNo == state.mySeatNo }
                #expect(me?.state == .playing, "\(name): playing 아닌데 my_rack 이 실렸다")
                #expect(me?.rackCount == state.myRack?.count, "\(name): 내 rack_count ≠ my_rack 장수")
            }
        }
        #expect(checked >= 25, "state 를 실은 픽스처 \(checked)장")
    }

    @Test("핵심 값: 시작 14장·더미 장수 · 거절 이유 · 끝 정산 제로섬 · 방 취소 · 로비 상수 · 순위")
    func keyValues() throws {
        // 없으면: 디코드는 되는데 뜻이 어긋난(예: 시작 판 더미 장수, 정산 합) 서버 변경이 클라 시험에서 안 보인다.
        let map = Dictionary(uniqueKeysWithValues: try fixtures().map { ($0.name, $0.data) })
        func action(_ name: String) throws -> RummyActionResponse {
            try rwcDecode(RummyActionResponse.self, try #require(map[name], "픽스처 없음: \(name)"))
        }

        let start = try #require(try action("start_ok").state)
        let n = try #require(start.seatCount)
        #expect((2...4).contains(n))
        #expect(start.myRack?.count == 14)
        #expect(start.poolCount == 106 - 14 * n, "시작 더미 = 106 − 14n")
        #expect(start.seats?.filter { $0.state == .playing }.count == n)
        #expect(start.seats?.allSatisfy { $0.state != .playing || $0.rackCount == 14 } == true)
        #expect(start.lastEvent?.kind == "start")
        #expect(start.graceMs == 2000)
        if let started = start.turnStartedMs, let deadline = start.turnDeadlineMs {
            #expect(abs(deadline - started - 60_000) < 1, "차례 60초")
        }

        #expect(try action("play_rejected").reason == .invalidMeld)
        #expect(try action("play_rejected_initial_under_30").reason == .initialUnder30)
        #expect(try action("play_rejected").state?.status == .active, "거절에도 state 가 실린다")
        #expect(try action("draft_ok").draftSeq == 1)
        #expect(try action("create_ok").matchId != nil)
        #expect(try action("create_insufficient").have == 2)
        #expect(try action("create_insufficient").need == 3)
        #expect(try action("create_invalid").stakes == [3, 5, 10])
        #expect(try action("unsupported_client").status == .unsupportedClient)
        #expect(try action("gomoku_challenge_target_busy").status == .targetBusy, "아잉 큐브 자리가 오목 신청을 막는다(chess__busy)")
        #expect(try action("leave_host_cancel").state?.status == .cancelled)
        #expect(try action("leave_forfeit_ok").state?.seats?.contains { $0.state == .forfeit } == true)
        #expect(try action("draw_pass").state?.lastEvent?.kind == "pass")
        #expect(try action("draw_ok").state?.lastEvent?.kind == "draw")
        #expect(try action("state_after_timeout_draw").state?.lastEvent?.kind == "timeout_draw")
        #expect(try action("state_active_other_draft").state?.draft?.table?.isEmpty == false)

        for name in ["state_finished", "play_ok_finish"] {
            let finished = try #require(try action(name).state)
            #expect(finished.status == .finished, "\(name)")
            #expect(finished.endReason == .rackEmpty, "\(name)")
            #expect(finished.myRack == nil, "\(name): 끝난 판에 my_rack")
            let seats = finished.seats ?? []
            let count = try #require(finished.seatCount)
            let stake = try #require(finished.stake)
            #expect(seats.map { $0.payout ?? -1 }.reduce(0, +) == count * stake, "\(name): Σpayout = n·stake")
            #expect(seats.allSatisfy { $0.finalRank != nil && $0.payout != nil && $0.isWinner != nil }, "\(name)")
            // 게임 점수는 끝까지 한 자리(done)에만 있다 — 기권 자리는 null(§2 점수는 playing 자리끼리만).
            #expect(seats.allSatisfy { ($0.state == .done) == ($0.finalScore != nil) }, "\(name): 점수 자리")
            // 루비·등수도 공용 순수 함수(§2.1)와 같은 답이다 — 서버 rummy_payouts ↔ RummyRules.payouts.
            let bySeat = seats.sorted { ($0.seatNo ?? 0) < ($1.seatNo ?? 0) }
            // 분배 입력 점수는 화면 점수가 아니라 §2.1 0번(막힘 끝 공동 최소 집단 ⌊P/m⌋)이다 — 서버 rummy__settle 과 같은 길.
            let done = bySeat.filter { $0.state == .done }
            let payoutScore = Dictionary(uniqueKeysWithValues: zip(done.map { $0.seatNo ?? 0 },
                                                                   RummyRules.payoutScores(racks: done.map { $0.finalRack ?? [] })))
            let expected = RummyRules.payouts(seatCount: count, stake: stake, seats: bySeat.map {
                RummyPayoutSeat(active: $0.state == .done, score: payoutScore[$0.seatNo ?? 0] ?? 0, tiles: $0.finalRack?.count ?? 0,
                                seat: $0.seatNo ?? 0, forfeitOrder: $0.forfeitOrder)
            })
            #expect(bySeat.map { $0.payout ?? -1 } == expected.payouts, "\(name): payouts")
            #expect(bySeat.map { $0.finalRank ?? -1 } == expected.ranks, "\(name): ranks")
            #expect(seats.contains { $0.isWinner == true }, "\(name): 승자 없음")
            // 끝 점수도 공용 순수 함수와 같은 답이다(R-22~R-24 — 서버 rummy_score_final ↔ RummyRules.finalScores).
            let playing = seats.filter { $0.state == .done }.sorted { ($0.seatNo ?? 0) < ($1.seatNo ?? 0) }
            let scores = RummyRules.finalScores(racks: playing.map { $0.finalRack ?? [] }).scores
            #expect(playing.map { $0.finalScore ?? .min } == scores, "\(name): 점수 \(scores)")
        }

        let lobby = try rwcDecode(RummyLobby.self, try #require(map["lobby_with_room_invites_public"]))
        #expect(lobby.stakes == [3, 5, 10])
        #expect(lobby.turnSeconds == 60)
        #expect(lobby.roomTtlSeconds == 600)
        #expect(lobby.me?.room != nil)
        #expect(lobby.me?.room?.maxSeats == 4)
        #expect(lobby.invites?.isEmpty == false)
        #expect(lobby.publicRooms?.isEmpty == false)
        #expect(lobby.publicRooms?.allSatisfy { $0.isPublic == true } == true)
        let empty = try rwcDecode(RummyLobby.self, try #require(map["lobby_empty"]))
        #expect(empty.me?.room == nil)
        #expect(empty.invites?.isEmpty == true)

        let ranking = try rwcDecode(RummyRanking.self, try #require(map["ranking"]))
        #expect(ranking.rows?.isEmpty == false)
        #expect(ranking.rows?.allSatisfy { ($0.games ?? 0) > 0 } == true, "0판 행은 빠진다")
    }

    @Test("와이어 RPC 12개가 마이그레이션에 있고, 모두 p_protocol 을 받는다(소스 계약)")
    func everyClientRPCExistsInMigration() throws {
        // 없으면: 클라가 부르는 이름이 서버에 없어(오타·이름 바꿈) 모든 버튼이 404 인데 스텁 시험은 초록이다.
        let sql = try rwcMigrationSQL()
        for rpc in RummyWire.RPC.all {
            let args = try rwcSQLArguments(rpc, in: sql)
            #expect(args != nil, "\(rpc) 정의가 \(rwcMigrationName) 에 없다")
            #expect(args?.contains("p_protocol") == true, "\(rpc) 가 p_protocol 을 안 받는다")
        }
        // 클라 실행권: 상수 rummy_protocol 이 클라 프로토콜과 같다(서버가 올리면 이 시험이 먼저 빨개진다).
        let protocolRegex = try NSRegularExpression(
            pattern: #"function\s+public\.rummy_protocol\s*\(\s*\).*?select\s+(\d+)"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators])
        let match = try #require(protocolRegex.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)))
        let value = Int(sql[Range(match.range(at: 1), in: sql)!])
        #expect(value == RummyWire.protocolVersion, "rummy_protocol() = \(value ?? -1)")
    }
}

/// 일일 미션 여덟째 줄(`daily_rummy`, 서버 §3.9)의 아이콘이 별(모르는 게임)이 아니라 큐브 입구 기호다.
@Test("일일 미션 rummy 줄 아이콘 = 큐브 입구 기호(별 대체 아님) · 마이그레이션 정의표에 daily_rummy 줄")
@MainActor
func v0368DailyRummyMissionIcon() throws {
    // 없으면: 여덟째 줄이 대체 별 아이콘으로 떠 무슨 게임인지 모르는 결함이 초록이 된다.
    #expect(DailyMissionCopy.icon(game: "rummy") == RummyEntryIcon.resolved)
    #expect(DailyMissionCopy.icon(game: "rummy") != AchievementCopy.fallbackIcon)
    let sql = try rwcMigrationSQL()
    let row = try NSRegularExpression(
        pattern: #"\(\s*'daily_rummy'\s*,\s*'rummy'\s*,\s*'아잉 큐브 한 판 하기'\s*,\s*'맥에서 할 수 있어요'\s*,\s*5\s*,\s*1\s*,\s*70\s*\)"#)
    #expect(row.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)) != nil, "daily_rummy 정의 줄(§1)이 없다")
}
