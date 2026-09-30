import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.41 — 오목 **순위표 · 관전** 서버↔앱 응답 계약(실제 SQL 출력) + 정렬 판정의 독립 검산 + 픽스처가 픽셀을 만드는지.
//
// 픽스처 `Fixtures/gomoku-rpc/gomoku_ranking__*.json` · `gomoku_watch__*.json` 은 스텁 추측이 아니다 — 로컬 하네스(체인 전체 +
// 20260930120000_gomoku_ranking_watch.sql)에 harness.login 으로 authenticated 흉내를 내 RPC 를 **실제로 부른 jsonb 출력 그대로**다.
// 생성기는 `_gen_fixtures_v0341.py.txt`, 호출자·준비 SQL 은 `_manifest.json` 의 fixtures 에 있다(2026-09-30 실측).
//
// 네 갈래: ① 모양(매니페스트·키 집합·값이 DECISIONS C1·C3 과 PLAN 의 response_keys 대로인가) ② 정렬 판정(GomokuRankingOrder)을
// **독립 산식**으로 검산 — 기준선이 입력과 같으면 그 테스트는 영원히 초록이라, 부호를 뒤집은 튜플 오름차순 정렬과 튜플 `>` 로 센 순위라는
// 다른 식으로 기대를 만들고 입력은 뒤섞어 넣는다 ③ 스토어 계약 — 픽스처를 스텁에 물려 스토어가 실제 서버 모양을 화면 값으로 어떻게 옮기고
// 다음 요청을 어떻게 내는가 ④ 렌더 — 픽스처에서 나온 화면 값이 순위 열 행과 판의 돌, 상태 상자 전환을 실제 픽셀로 만드는가(C23 — 새 사각형).
//
// 각 시험의 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가"다. UserDefaults 는 `GomokuTestDefaults.make`(격리 스위트 — C21).

// MARK: - 픽스처 도구

private struct FxError: Error, CustomStringConvertible {
    let description: String
}

private let fxDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/gomoku-rpc", isDirectory: true)

private let fxRankingNames = ["gomoku_ranking__ok", "gomoku_ranking__ok_me_unranked", "gomoku_ranking__ok_empty",
                              "gomoku_ranking__unauthorized", "gomoku_ranking__unsupported_client"]
private let fxWatchNames = ["gomoku_watch__ok_since0", "gomoku_watch__ok_since2", "gomoku_watch__ok_as_player", "gomoku_watch__ok_overdue",
                            "gomoku_watch__ok_finished", "gomoku_watch__not_found", "gomoku_watch__unauthorized", "gomoku_watch__unsupported_client"]

private func fxData(_ name: String) throws -> Data {
    try Data(contentsOf: fxDirectory.appendingPathComponent("\(name).json"))
}

private func fxText(_ name: String) throws -> String {
    String(decoding: try fxData(name), as: UTF8.self)
}

private func fxJSON(_ name: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: fxData(name)) as? [String: Any] else {
        throw FxError(description: "\(name) 는 JSON 객체가 아니다")
    }
    return object
}

private func fxDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

private func fxDecode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try fxDecoder().decode(type, from: try fxData(name))
}

private func fxManifest() throws -> [String: Any] { try fxJSON("_manifest") }

private func fxUser(_ key: String) throws -> String {
    guard let value = (try fxManifest()["users"] as? [String: String])?[key] else { throw FxError(description: "manifest users.\(key) 없음") }
    return value
}

private func fxNumber(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

private func fxKeys(_ object: Any?) -> [String] { ((object as? [String: Any])?.keys).map { Array($0).sorted() } ?? [] }

// MARK: - ① 모양

@Test
func 순위_관전_픽스처는_전부_매니페스트에_있고_호출자와_인자가_맞는다() throws {
    // 없으면: 누가 손으로 json 을 고쳐 넣어도(서버가 못 내는 모양) 아무도 모른다 — 매니페스트의 호출자·인자가 그 응답이 어디서 왔는지 말한다.
    let onDisk = try FileManager.default.contentsOfDirectory(atPath: fxDirectory.path)
        .filter { ($0.hasPrefix("gomoku_ranking__") || $0.hasPrefix("gomoku_watch__")) && $0.hasSuffix(".json") }
        .map { String($0.dropLast(5)) }
    #expect(Set(onDisk) == Set(fxRankingNames + fxWatchNames), "디스크의 픽스처 집합이 다르다: \(onDisk.sorted())")
    let fixtures = try #require(try fxManifest()["fixtures"] as? [String: Any])
    let mWatch = try fxUser("m_watch")
    let oldFinished = try fxUser("m_fin_old")
    for name in fxRankingNames + fxWatchNames {
        let entry = try #require(fixtures[name] as? [String: Any], "manifest 에 \(name) 이 없다")
        let rpc = try #require(entry["rpc"] as? String)
        let family = name.hasPrefix("gomoku_ranking__") ? "public.gomoku_ranking(" : "public.gomoku_watch("
        #expect(rpc.hasPrefix(family), "\(name): rpc \(rpc)")
        #expect(["rollback", "commit"].contains(entry["end"] as? String ?? ""), "\(name): end")
        if name.hasSuffix("__unauthorized") {
            #expect(entry["caller"] is NSNull, "\(name): 클레임 없는 호출이어야 한다(호출자 null)")
        } else {
            #expect((entry["caller"] as? String)?.count == 36, "\(name): 호출자 uuid 가 없다")
        }
        if name.hasSuffix("__unsupported_client") { #expect(rpc.contains("(0"), "\(name): p_protocol 0 이어야 한다") }
        if name.hasPrefix("gomoku_watch__"), name != "gomoku_watch__not_found" { #expect(rpc.contains(mWatch), "\(name): 관전 판 id") }
    }
    #expect((fixtures["gomoku_watch__ok_since2"] as? [String: Any])?["rpc"] as? String == "public.gomoku_watch(1, '\(mWatch)', 2)")
    #expect((fixtures["gomoku_watch__ok_finished"] as? [String: Any])?["rpc"] as? String == "public.gomoku_watch(1, '\(mWatch)', 3)")
    #expect(((fixtures["gomoku_watch__not_found"] as? [String: Any])?["rpc"] as? String)?.contains(oldFinished) == true,
            "not_found 는 '어제 끝난 판'(3분 꼬리 밖)으로 떠야 C1 을 증명한다")
    #expect(((fixtures["gomoku_watch__ok_finished"] as? [String: Any])?["setup"] as? String)?.contains("turn = null") == true,
            "끝난 판 픽스처의 준비 SQL 에 turn = null 이 없다(CHECK)")
    // 호출자는 매니페스트 users 의 사람이다(C 가 제3자, A 가 참가자, F 가 0판).
    let a = try fxUser("A"), c = try fxUser("C"), f = try fxUser("F")
    #expect((fixtures["gomoku_watch__ok_since0"] as? [String: Any])?["caller"] as? String == c)
    #expect((fixtures["gomoku_watch__ok_as_player"] as? [String: Any])?["caller"] as? String == a)
    #expect((fixtures["gomoku_ranking__ok_me_unranked"] as? [String: Any])?["caller"] as? String == f)
}

@Test
func 실서버_순위_응답의_모양은_response_keys_와_같고_동률_축_셋이_다_드러난다() throws {
    // 없으면: 서버가 rows 를 안 싣거나(0행에 null), points 를 빼거나, 동률에 다른 rank 를 주거나, 줄 순서를 user_id 로 안 고정해도 —
    // 스토어는 Optional 로 다 받아 주므로 — 앱 쪽 테스트는 전부 초록이다.
    let a = try fxUser("A"), b = try fxUser("B"), c = try fxUser("C"), d = try fxUser("D"), e = try fxUser("E"), f = try fxUser("F")
    let ok = try fxJSON("gomoku_ranking__ok")
    #expect(fxKeys(ok) == ["me", "record_since_ms", "rows", "server_now_ms", "status"])
    #expect(fxKeys(ok["me"]) == ["draws", "losses", "points", "rank", "wins"])
    #expect(ok["record_since_ms"] is NSNull, "컷이 -infinity 인데 record_since_ms 가 null 이 아니다")
    let rows = try #require(ok["rows"] as? [[String: Any]])
    #expect(rows.count == 5)
    for row in rows {
        #expect(fxKeys(row) == ["avatar_url", "center", "character", "display_name", "draws", "losses", "points", "rank", "user_id", "wins"],
                "행 키: \(fxKeys(row))")
        #expect(row["points"] as? Int == (row["wins"] as? Int ?? 0) - (row["losses"] as? Int ?? 0), "points ≠ wins − losses: \(row)")
    }
    // 설계한 전적: A +3 · E 0 · B/D −1 완전 동률(1승 2패 1무) · C −1(1승 2패 0무) → 순서 A E B D C, rank 1 2 3 3 5.
    #expect(rows.map { $0["user_id"] as? String } == [a, e, b, d, c], "줄 순서가 승점 desc → 승 desc → 무 desc → user_id asc 가 아니다")
    #expect(rows.map { $0["rank"] as? Int } == [1, 2, 3, 3, 5], "rank() 모양(동률 같은 숫자, 다음 건너뜀)이 아니다")
    #expect(rows[2]["wins"] as? Int == 1 && rows[2]["draws"] as? Int == 1 && rows[4]["wins"] as? Int == 1 && rows[4]["draws"] as? Int == 0,
            "C 가 B·D 뒤인 것은 draws desc(같은 승점·승수면 더 많이 둔 쪽이 위)여야 한다")
    #expect(b < d, "완전 동률 B·D 의 줄 순서가 user_id 오름차순임을 이 픽스처로 증명하려면 B < D 여야 한다")
    let me = try #require(ok["me"] as? [String: Any])
    #expect(me["rank"] as? Int == 1 && me["wins"] as? Int == 3 && me["losses"] as? Int == 0 && me["draws"] as? Int == 1 && me["points"] as? Int == 3)

    let unranked = try fxJSON("gomoku_ranking__ok_me_unranked")
    let unrankedMe = try #require(unranked["me"] as? [String: Any])
    #expect(unrankedMe["rank"] is NSNull && unrankedMe["points"] as? Int == 0 && unrankedMe["wins"] as? Int == 0, "0판인데 me.rank 가 null 이 아니다")
    #expect((unranked["rows"] as? [[String: Any]])?.count == 5 && !((unranked["rows"] as? [[String: Any]]) ?? []).contains { $0["user_id"] as? String == f },
            "0판 사용자가 rows 에 섰다")
    let empty = try fxJSON("gomoku_ranking__ok_empty")
    #expect((empty["rows"] as? [Any])?.isEmpty == true && ((empty["me"] as? [String: Any])?["rank"]) is NSNull, "빈 표: rows [] · me.rank null")
    #expect(try fxKeys(fxJSON("gomoku_ranking__unauthorized")) == ["status"])
    #expect(try fxKeys(fxJSON("gomoku_ranking__unsupported_client")) == ["server_now_ms", "status"])
    for name in fxRankingNames {
        let response = try fxDecode(GomokuRankingResponse.self, name)
        let raw = try fxJSON(name)["status"] as? String
        #expect(response.status.rawValue == raw, "\(name): status 가 접혔다")
    }
}

@Test
func 실서버_관전_응답의_모양은_판만이고_C1_의_경계가_픽스처에_그대로다() throws {
    // 없으면: 관전 응답에 chat·my_color 가 슬쩍 실려 오거나, 끝난 판에 deadline_ms 가 남거나, 3분 꼬리 밖의 판이 ok 로 열려도 앱 테스트는 초록이다.
    let a = try fxUser("A"), b = try fxUser("B"), mWatch = try fxUser("m_watch")
    let topKeys = ["auto_abandon_streak", "black_auto_streak", "black_user", "match", "moves", "server_now_ms", "status", "white_auto_streak", "white_user"]
    let matchKeys = ["black", "board", "challenger", "deadline_ms", "end_reason", "finished_ms", "id", "move_count", "opponent", "result",
                     "stake", "started_ms", "status", "turn", "turn_started_ms", "white", "winner"]
    for name in ["gomoku_watch__ok_since0", "gomoku_watch__ok_since2", "gomoku_watch__ok_as_player", "gomoku_watch__ok_overdue", "gomoku_watch__ok_finished"] {
        let object = try fxJSON(name)
        #expect(fxKeys(object) == topKeys, "\(name) 최상위 키: \(fxKeys(object))")
        #expect(fxKeys(object["match"]) == matchKeys, "\(name) match 키: \(fxKeys(object["match"]))")
        #expect(fxKeys(object["black_user"]) == ["avatar_url", "center", "character", "display_name", "user_id"], "\(name) black_user 키")
        let match = try #require(object["match"] as? [String: Any])
        #expect(match["id"] as? String == mWatch && match["black"] as? String == a && match["white"] as? String == b && match["stake"] as? Int == 5)
        #expect((object["black_user"] as? [String: Any])?["user_id"] as? String == a, "\(name): black_user 가 흑이 아니다")
        #expect((object["white_user"] as? [String: Any])?["user_id"] as? String == b)
        let response = try fxDecode(GomokuWatchResponse.self, name)
        #expect(response.status == .ok && response.match?.id == mWatch && response.blackUser?.userId == a, "\(name) 디코드")
    }
    // since 0: 2수 · 흑 차례 · 마감 = turn_started + 30s · 판 문자열은 수순으로 다시 쌓은 판과 같다(y*15+x).
    let since0 = try fxJSON("gomoku_watch__ok_since0")
    let match0 = try #require(since0["match"] as? [String: Any])
    let moves0 = try #require(since0["moves"] as? [[String: Any]])
    #expect(moves0.map { $0["seq"] as? Int } == [1, 2] && match0["move_count"] as? Int == 2 && match0["turn"] as? String == "black")
    #expect((fxNumber(match0["deadline_ms"]) ?? 0) - (fxNumber(match0["turn_started_ms"]) ?? 0) == 30_000, "deadline_ms ≠ turn_started_ms + 30초")
    #expect(match0["status"] as? String == "active" && match0["deadline_ms"] != nil && !(match0["deadline_ms"] is NSNull))
    var rebuilt = GomokuBoard()
    for move in moves0 {
        let point = try #require(GomokuPoint(x: move["x"] as? Int ?? -1, y: move["y"] as? Int ?? -1))
        rebuilt[point] = GomokuColor(rawValue: move["color"] as? String ?? "")
    }
    #expect(rebuilt.serverString == match0["board"] as? String, "서버 board 문자열이 수순과 다르다")
    // since 2: seq 3 하나만 · move_count 3 · 백 차례(증분 요청의 답).
    let since2 = try fxJSON("gomoku_watch__ok_since2")
    #expect((since2["moves"] as? [[String: Any]])?.map { $0["seq"] as? Int } == [3])
    #expect((since2["match"] as? [String: Any])?["move_count"] as? Int == 3 && (since2["match"] as? [String: Any])?["turn"] as? String == "white")
    // 마감이 지난 판: deadline_ms < server_now_ms 인데 status 는 active — 관전은 따라잡지 않는다(C19 의 서버 쪽 사실).
    let overdue = try fxJSON("gomoku_watch__ok_overdue")
    let overdueMatch = try #require(overdue["match"] as? [String: Any])
    #expect((fxNumber(overdueMatch["deadline_ms"]) ?? .infinity) < (fxNumber(overdue["server_now_ms"]) ?? 0), "마감이 안 지났다")
    #expect(overdueMatch["status"] as? String == "active" && overdueMatch["move_count"] as? Int == 3)
    // 관전 중 끝난 판(3분 꼬리 안): finished · 승자 A · five · deadline null · finished_ms · turn null · since 3 이라 moves [].
    let finished = try fxJSON("gomoku_watch__ok_finished")
    let finishedMatch = try #require(finished["match"] as? [String: Any])
    #expect(finishedMatch["status"] as? String == "finished" && finishedMatch["result"] as? String == "black_win"
            && finishedMatch["winner"] as? String == a && finishedMatch["end_reason"] as? String == "five")
    #expect(finishedMatch["deadline_ms"] is NSNull && finishedMatch["turn"] is NSNull && fxNumber(finishedMatch["finished_ms"]) != nil)
    #expect((finished["moves"] as? [Any])?.isEmpty == true)
    // 거절 가족: not_found(어제 끝난 판 — 3분 꼬리 밖)·unauthorized 는 status 하나, unsupported_client 는 server_now_ms 도.
    let notFound = try fxJSON("gomoku_watch__not_found")
    #expect(fxKeys(notFound) == ["status"] && notFound["status"] as? String == "not_found")
    #expect(try fxKeys(fxJSON("gomoku_watch__unauthorized")) == ["status"])
    #expect(try fxKeys(fxJSON("gomoku_watch__unsupported_client")) == ["server_now_ms", "status"])
    for name in fxWatchNames {
        let response = try fxDecode(GomokuWatchResponse.self, name)
        let raw = try fxJSON(name)["status"] as? String
        #expect(response.status != .unknown && response.status.rawValue == raw, "\(name): status")
    }
}

// MARK: - ② 정렬 판정의 독립 검산

private struct FxRecord: Equatable {
    let points: Int
    let wins: Int
    let draws: Int
    let id: String
}

/// 결정적 난수(LCG) — 실행마다 같은 표. 표준 라이브러리의 시스템 난수는 실패를 재현할 수 없다.
private struct FxLCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

/// **독립 산식 1** — 부호를 뒤집은 튜플의 오름차순 정렬(스토어의 `precedes` 는 축을 하나씩 비교하는 if 사슬이다 — 다른 식이어야 검산이다).
private func fxIndependentOrder(_ records: [FxRecord]) -> [FxRecord] {
    records.sorted { (-$0.points, -$0.wins, -$0.draws, $0.id) < (-$1.points, -$1.wins, -$1.draws, $1.id) }
}

/// **독립 산식 2** — rank() = 1 + (앞 세 축의 튜플이 엄격히 큰 행 수). 서버 프로브 ⑨ 가 SQL 로 재는 식과 같은 뜻이다.
private func fxIndependentRanks(_ records: [FxRecord]) -> [Int] {
    records.map { mine in 1 + records.filter { ($0.points, $0.wins, $0.draws) > (mine.points, mine.wins, mine.draws) }.count }
}

private func fxShuffled(_ records: [FxRecord], seed: UInt64) -> [FxRecord] {
    var copy = records
    var rng = FxLCG(state: seed)
    for index in stride(from: copy.count - 1, to: 0, by: -1) {
        copy.swapAt(index, rng.below(index + 1))
    }
    return copy
}

private func fxKey(_ record: FxRecord) -> GomokuRankingOrder.Key {
    GomokuRankingOrder.Key(points: record.points, wins: record.wins, draws: record.draws, userID: record.id)
}

private func fxEntry(_ record: FxRecord, rank: Int) -> GomokuRankEntry {
    let user = GomokuUser(id: record.id, displayName: record.id.suffix(4).description, avatarURL: nil, characterID: nil,
                          isWorking: false, isCapable: false, inMatch: false)
    return GomokuRankEntry(id: record.id, rank: rank, user: user, wins: record.wins, losses: record.wins - record.points, draws: record.draws, points: record.points)
}

@Test
func 순위_정렬_판정은_독립_산식의_기대_순서와_같고_결정적이다() throws {
    // 없으면: `precedes` 가 draws 축을 빼먹거나 user_id 를 내림차순으로 봐도, 자기 규칙으로 만든 픽스처(기준선 = 입력)만 넣는 테스트는 영원히 초록이다.
    // 값 범위를 좁게 잡아(승점 7가지 · 승 5가지 · 무 3가지) 120건 안에 완전 동률·무만 다른 쌍·승만 다른 쌍이 반드시 생긴다.
    var rng = FxLCG(state: 41)
    var ids = (0..<120).map { String(format: "00000000-0000-4000-8000-%012d", $0) }
    ids = fxShuffled(ids.map { FxRecord(points: 0, wins: 0, draws: 0, id: $0) }, seed: 7).map(\.id)   // id 순서 ≠ 생성 순서
    let records = ids.map { FxRecord(points: rng.below(7) - 3, wins: rng.below(5), draws: rng.below(3), id: $0) }
    let expected = fxIndependentOrder(records)
    let pairs = Array(zip(expected, expected.dropFirst()))
    #expect(pairs.contains { ($0.points, $0.wins, $0.draws) == ($1.points, $1.wins, $1.draws) }, "표에 완전 동률이 없다 — 이 검산이 user_id 축을 못 본다")
    #expect(pairs.contains { $0.points == $1.points && $0.wins == $1.wins && $0.draws > $1.draws }, "무만 다른 이웃이 없다 — draws 축을 못 본다")
    #expect(pairs.contains { $0.points == $1.points && $0.wins > $1.wins }, "승만 다른 이웃이 없다 — wins 축을 못 본다")

    let keys = expected.map(fxKey)
    #expect(GomokuRankingOrder.isSorted(keys), "독립 산식의 순서를 판정이 '정렬됨'으로 보지 않는다")
    for (lhs, rhs) in zip(keys, keys.dropFirst()) {
        #expect(GomokuRankingOrder.precedes(lhs, rhs) && !GomokuRankingOrder.precedes(rhs, lhs), "이웃 쌍의 엄격 순서가 깨졌다: \(lhs) ↔ \(rhs)")
        #expect(GomokuRankingOrder.ties(lhs, rhs) == ((lhs.points, lhs.wins, lhs.draws) == (rhs.points, rhs.wins, rhs.draws)))
    }
    // 뒤섞은 두 입력: 판정은 거짓, 독립 산식으로 다시 세우면 둘 다 같은 순서(결정성 — 입력 순서에 안 기댄다).
    let shuffledA = fxShuffled(records, seed: 1), shuffledB = fxShuffled(records, seed: 2)
    #expect(shuffledA != expected && shuffledB != expected && shuffledA != shuffledB, "섞이지 않았다 — 기준선이 입력과 같다")
    #expect(!GomokuRankingOrder.isSorted(shuffledA.map(fxKey)) && !GomokuRankingOrder.isSorted(shuffledB.map(fxKey)))
    #expect(fxIndependentOrder(shuffledA) == expected && fxIndependentOrder(shuffledB) == expected)
    // 축을 하나씩 뒤집은 판정이 있었다면 잡혔을 자리들 — 이웃을 바꾸면 거짓.
    for index in stride(from: 0, to: keys.count - 1, by: 17) {
        var swapped = keys
        swapped.swapAt(index, index + 1)
        #expect(!GomokuRankingOrder.isSorted(swapped), "\(index)·\(index + 1) 을 바꿨는데 정렬됨")
    }
    // rank() 모양: 독립 산식의 순위 == 판정의 규칙, 하나만 흔들어도 거짓, 완전 동률 뒤에는 건너뛴 숫자.
    let ranks = fxIndependentRanks(expected)
    let entries = zip(expected, ranks).map { fxEntry($0, rank: $1) }
    #expect(GomokuRankingOrder.isSorted(entries) && GomokuRankingOrder.ranksMatchServerRule(entries))
    #expect(ranks.first == 1 && ranks == ranks.sorted(), "순위가 1 에서 시작해 단조롭지 않다")
    let tieIndex = try #require(pairs.firstIndex { ($0.points, $0.wins, $0.draws) == ($1.points, $1.wins, $1.draws) })
    #expect(ranks[tieIndex] == ranks[tieIndex + 1], "완전 동률에 다른 순위")
    // 동률 묶음 다음의 첫 다른 줄: 순위 = 자기 자리 + 1(앞이 전부 엄격히 낫다) 이라 동률 순위보다 2 이상 크다(3,3,5 모양).
    if let next = expected.indices.first(where: { $0 > tieIndex && (expected[$0].points, expected[$0].wins, expected[$0].draws)
                                                    != (expected[tieIndex].points, expected[tieIndex].wins, expected[tieIndex].draws) }) {
        #expect(ranks[next] == next + 1 && ranks[next] >= ranks[tieIndex] + 2, "동률 뒤에서 숫자를 건너뛰지 않는다: \(ranks[tieIndex...next])")
    }
    var wrong = entries
    wrong[tieIndex + 1] = fxEntry(expected[tieIndex + 1], rank: ranks[tieIndex + 1] + 1)
    #expect(!GomokuRankingOrder.ranksMatchServerRule(wrong), "동률에 다른 순위를 줬는데 통과했다")

    // 실서버 픽스처도 같은 검산을 지난다: 행을 섞어 독립 산식으로 세우면 서버가 준 순서·순위 그대로다.
    let response = try fxDecode(GomokuRankingResponse.self, "gomoku_ranking__ok")
    let rows = response.rows ?? []
    let fixture = rows.map { FxRecord(points: $0.points ?? 0, wins: $0.wins ?? 0, draws: $0.draws ?? 0, id: $0.userId ?? "") }
    let reordered = fxIndependentOrder(fxShuffled(fixture, seed: 3))
    #expect(reordered.map(\.id) == fixture.map(\.id), "실서버 rows 의 순서가 독립 산식과 다르다 — 서버 order by 가 바뀌었다")
    #expect(fxIndependentRanks(reordered) == rows.map { $0.rank ?? 0 }, "실서버 rank 가 독립 산식과 다르다")
    #expect(GomokuRankingOrder.isSorted(rows) && GomokuRankingOrder.ranksMatchServerRule(GomokuStore.rankingBoard(from: response).entries))
    #expect(rows.compactMap(GomokuRankingOrder.Key.init).count == rows.count, "user_id 없는 행이 있다")
}

// MARK: - ③ 스토어 계약(픽스처 → 스토어)

@MainActor
private enum FxRetention {
    static var stores: [WorkTimerStore] = []
}

/// `queues[rpc]` 의 픽스처 본문을 그 rpc 의 호출 순서대로 돌려준다. 큐 밖의 호출은 500(스토어의 실패 경로 — 화면을 안 바꾼다).
/// 주 스위치(C11)를 켜고 창을 보이게 둔다 — 맥 배선을 흉내 낸 것이고, 폴링 루프는 재운다(걸음은 직접 밟는다).
@MainActor
private func makeFixtureStore(_ label: String, me: String, queues: [String: [String]]) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0341-fx-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    let frozen = queues
    GomokuStubProtocol.register(host: host) { rpc, _, index in
        guard let list = frozen[rpc], index < list.count else {
            return GomokuStubProtocol.Reply(status: 500, body: #"{"message":"not scripted"}"#)
        }
        return GomokuStubProtocol.Reply(body: list[index])
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let defaults = GomokuTestDefaults.make("v0341-fixture")
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    FxRetention.stores.append(store)
    let gomoku = store.gomoku
    gomoku.spectatorFeaturesEnabled = true
    gomoku.pollStepSeconds = 3_600
    gomoku.isWindowVisible = true
    return (store, gomoku, host)
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥔다 — V0327 계약 테스트와 같은 해법).
@MainActor
private func fxWait(_ timeout: TimeInterval = 30, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func fxLastBody(_ host: String, _ rpc: String) -> [String: Any] {
    GomokuStubProtocol.calls(host: host, rpc: rpc).last?.json ?? [:]
}

/// 서버 순간 → 기기 시계 기대값: 응답의 server_now_ms 를 "지금"으로 놓았을 때 그 키가 지금부터 몇 초 뒤인가.
private func fxSecondsFromNow(_ object: [String: Any], key: String) -> TimeInterval {
    let match = object["match"] as? [String: Any] ?? [:]
    return ((fxNumber(match[key]) ?? 0) - (fxNumber(object["server_now_ms"]) ?? 0)) / 1000
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_관전_응답을_스토어가_판_수순_마감_두_사람으로_옮기고_증분으로_묻다가_끝나면_멈춘다() async throws {
    // 없으면: 스토어가 로비 a/b 로 흑백을 짐작하거나(C15), 두 번째 요청을 0 으로 다시 내거나(증분 없음), 끝난 응답 뒤에도 2초 폴링을 계속 내도
    // 손으로 쓴 스텁 응답으로는 안 보인다 — 서버 정규화·키 이름·null 처리는 실서버 출력에서만 잡힌다.
    let a = try fxUser("A"), b = try fxUser("B"), mWatch = try fxUser("m_watch")
    let (_, gomoku, host) = makeFixtureStore("watch", me: try fxUser("C"), queues: [
        "gomoku_watch": [try fxText("gomoku_watch__ok_since0"), try fxText("gomoku_watch__ok_since2"), try fxText("gomoku_watch__ok_finished")]
    ])
    #expect(gomoku.canPollSpectatorFeatures, "주 스위치·창·세션이 켜져 있어야 이 시험이 뜻이 있다")
    gomoku.startWatching(matchID: mWatch.uppercased())          // 로비 목록에 없는 판(씨앗 없음) — 얼굴 없는 로딩 상태로 들어가 응답이 채운다
    await fxWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_watch") == 1 && gomoku.spectating?.hasServerState == true }
    let first = GomokuStubProtocol.calls(host: host, rpc: "gomoku_watch").first?.json ?? [:]
    #expect(first["p_match_id"] as? String == mWatch && first["p_since_seq"] as? Int == 0 && first["p_protocol"] as? Int == 2, "첫 요청: \(first)")

    let since0 = try fxJSON("gomoku_watch__ok_since0")
    var watch = try #require(gomoku.spectating)
    #expect(watch.id == mWatch && watch.faces.isEmpty, "씨앗 없이 들어갔는데 얼굴이 있다")
    #expect(watch.black?.id == a && watch.white?.id == b, "흑·백은 서버 black_user/white_user 로만 선다(C15)")
    #expect(watch.black?.displayName == "abto.app" && watch.white?.characterID == "jellyfish" && watch.white?.avatarURL == "https://example.invalid/avatar-b.png")
    #expect(watch.stake == 5 && watch.turn == .black && watch.moveCount == 2 && watch.appliedSeq == 2 && !watch.isFinished)
    #expect(watch.board.stoneCount == 2 && watch.board[GomokuPoint(x: 7, y: 7)!] == .black && watch.board[GomokuPoint(x: 7, y: 8)!] == .white)
    #expect(watch.lastMove == GomokuPoint(x: 7, y: 8) && watch.autoPoints.isEmpty && watch.winner == nil && watch.endReason == nil)
    let deadline = try #require(watch.deadline)
    #expect(abs(deadline.timeIntervalSinceNow - fxSecondsFromNow(since0, key: "deadline_ms")) < 0.5, "마감이 server_now_ms 보정과 다르다: \(deadline)")
    let started = try #require(watch.startedAt)
    #expect(abs(started.timeIntervalSinceNow - fxSecondsFromNow(since0, key: "started_ms")) < 0.5, "시작 시각 보정")
    #expect(gomoku.shouldPollWatch, "진행 중인 판이면 폴링 대상이다")

    // 증분: 다음 요청은 appliedSeq(2) 로 묻고, 답(seq 3 하나)을 판에 얹는다.
    await gomoku.refreshWatch()
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_watch") == 2)
    #expect(fxLastBody(host, "gomoku_watch")["p_since_seq"] as? Int == 2, "두 번째 요청이 증분이 아니다: \(fxLastBody(host, "gomoku_watch"))")
    watch = try #require(gomoku.spectating)
    #expect(watch.moveCount == 3 && watch.appliedSeq == 3 && watch.turn == .white && watch.board.stoneCount == 3)
    #expect(watch.board[GomokuPoint(x: 8, y: 8)!] == .black && watch.lastMove == GomokuPoint(x: 8, y: 8))

    // 끝남: since 3 응답이 finished — 결과가 서고 폴링이 멈춘다(그 뒤 pollTick 이 아무리 와도 요청 없음).
    await gomoku.refreshWatch()
    #expect(fxLastBody(host, "gomoku_watch")["p_since_seq"] as? Int == 3)
    watch = try #require(gomoku.spectating, "끝난 판은 [나가기] 전까지 화면에 남는다")
    #expect(watch.isFinished && watch.winner == .black && watch.endReason == .five && watch.turn == nil && watch.deadline == nil)
    #expect(watch.board.stoneCount == 3, "끝난 응답(moves [])이 판을 비웠다 — 판 문자열은 서버 board 가 권위다")
    #expect(!gomoku.shouldPollWatch)
    await gomoku.pollSpectatorFeatures(at: Date().addingTimeInterval(600))
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_watch") == 3, "끝난 뒤에도 관전을 또 물었다")

    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0, "관전이 gomoku_state 를 불렀다 — 참가자 게이트에 걸리는 길")
    #expect(gomoku.chat.isEmpty && gomoku.notice == nil && gomoku.match == nil && gomoku.phase == .lobby)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_거절_응답은_관전을_내리고_안내_한_줄만_남긴다() async throws {
    // 없으면: not_found(3분 꼬리 밖)를 받고도 빈 판 "관전 중"이 2초 폴링을 영영 돌거나(C17), unauthorized 를 모르는 모양으로 삼켜 같은 화면이 굳어도 초록이다.
    let mWatch = try fxUser("m_watch"), me = try fxUser("C")
    let (_, gone, goneHost) = makeFixtureStore("gone", me: me, queues: ["gomoku_watch": [try fxText("gomoku_watch__not_found")]])
    gone.startWatching(matchID: mWatch)
    await fxWait { GomokuStubProtocol.count(host: goneHost, rpc: "gomoku_watch") == 1 && gone.spectating == nil }
    #expect(gone.spectating == nil && gone.notice == GomokuNoticeText.watchGone && !gone.shouldPollWatch)

    let (_, old, oldHost) = makeFixtureStore("old", me: me, queues: ["gomoku_watch": [try fxText("gomoku_watch__unsupported_client")]])
    old.startWatching(matchID: mWatch)
    await fxWait { GomokuStubProtocol.count(host: oldHost, rpc: "gomoku_watch") == 1 && old.spectating == nil }
    #expect(old.spectating == nil && old.notice == GomokuNoticeText.updateMine)

    // unauthorized 는 status 하나뿐인 거절 — 연속 watchFailureLimit(3)회면 내리고 연결 안내(빈 판이 영영 돌지 않게).
    let (_, unauth, unauthHost) = makeFixtureStore("unauth", me: me, queues: ["gomoku_watch": Array(repeating: try fxText("gomoku_watch__unauthorized"), count: 3)])
    unauth.startWatching(matchID: mWatch)
    await fxWait { GomokuStubProtocol.count(host: unauthHost, rpc: "gomoku_watch") == 1 && !unauth.watchRuntime.watchInFlight }
    #expect(unauth.spectating != nil && unauth.notice == nil, "한 번의 거절에 판을 내리면 잠깐의 흔들림에 관전이 사라진다")
    await unauth.refreshWatch()
    await unauth.refreshWatch()
    #expect(GomokuStubProtocol.count(host: unauthHost, rpc: "gomoku_watch") == GomokuStore.watchFailureLimit)
    #expect(unauth.spectating == nil && unauth.notice == GomokuNoticeText.checkConnection, "연속 거절 뒤에도 빈 판이 서 있다")
    for host in [goneHost, oldHost, unauthHost] {
        #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0)
    }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_순위_응답을_스토어가_순서_그대로_옮기고_내_순위는_로비_전적과_맞을_때만_낸다() async throws {
    // 없으면: 스토어가 재정렬해 서버·앱 두 규칙이 갈리거나, 0판 응답의 me.rank null 을 0위로 접거나, 거절 status 가 안내줄로 새거나,
    // 머리글이 로비 전적(0승)과 순위 응답(3승·1위)을 한 문장에 섞어도 초록이다(C16).
    let a = try fxUser("A")
    let (_, gomoku, host) = makeFixtureStore("ranking", me: a, queues: [
        "gomoku_ranking": [try fxText("gomoku_ranking__ok"), try fxText("gomoku_ranking__ok_me_unranked"), try fxText("gomoku_ranking__ok_empty"),
                           try fxText("gomoku_ranking__unsupported_client"), try fxText("gomoku_ranking__unauthorized")]
    ])
    await gomoku.loadRanking()
    #expect(Set(fxLastBody(host, "gomoku_ranking").keys) == ["p_protocol"], "요청 키: \(fxLastBody(host, "gomoku_ranking"))")
    let ok = try fxJSON("gomoku_ranking__ok")
    let rows = try #require(ok["rows"] as? [[String: Any]])
    let board = try #require(gomoku.ranking)
    #expect(board.entries.map(\.id) == rows.compactMap { ($0["user_id"] as? String)?.lowercased() }, "entries 순서 ≠ 서버 rows 순서(재정렬했다)")
    #expect(board.entries.map(\.rank) == [1, 2, 3, 3, 5] && board.entries.map(\.points) == [3, 0, -1, -1, -1])
    #expect(board.entries.map(\.wins) == [3, 1, 1, 1, 1] && board.entries.map(\.losses) == [0, 1, 2, 2, 2] && board.entries.map(\.draws) == [1, 1, 1, 1, 0],
            "행에 승·패·무가 같이 실려야 한다(U2)")
    #expect(board.entries[0].user.displayName == "abto.app" && board.entries[2].user.characterID == "jellyfish" && board.entries[0].user.center != nil)
    #expect(board.me == GomokuMyRank(rank: 1, wins: 3, losses: 0, draws: 1, points: 3) && board.recordSince == nil)
    #expect(gomoku.hasLoadedRanking && !gomoku.rankingLoadFailed && !gomoku.rankingUnavailable && gomoku.notice == nil)
    #expect(GomokuRankingOrder.isSorted(board.entries) && GomokuRankingOrder.ranksMatchServerRule(board.entries))
    // C16: 로비를 아직 못 받았으면 순위 응답이 유일한 출처 · 로비 전적(0.3.28 픽스처 gomoku_lobby__ok 의 me — 다른 서버 순간의 값이라
    // 순위표 me 와 다르다)과 다르면 순위를 내지 않는다. 기대 전적은 픽스처에서 읽는다(손으로 적은 0/0/0 은 틀렸었다 — 실측).
    #expect(gomoku.myRankConsistentWithRecord?.rank == 1)
    let lobby = try fxDecode(GomokuLobbyResponse.self, "gomoku_lobby__ok")
    let lobbyRecord = GomokuRecord(wins: lobby.me?.wins ?? 0, losses: lobby.me?.losses ?? 0, draws: lobby.me?.draws ?? 0)
    #expect(lobbyRecord != GomokuRecord(wins: 3, losses: 0, draws: 1), "로비 픽스처의 전적이 순위 픽스처와 같아졌다 — 이 검사가 헛돈다")
    gomoku.applyLobby(lobby)
    #expect(gomoku.record == lobbyRecord && gomoku.myRankConsistentWithRecord == nil, "로비 전적과 다른 순위 응답을 머리글에 붙였다")

    await gomoku.loadRanking()                                    // F(0판) 시점의 응답을 내가 받았다고 치면 — me.rank null 그대로
    #expect(gomoku.ranking?.me?.rank == nil && gomoku.ranking?.me?.points == 0 && gomoku.ranking?.entries.count == 5)
    await gomoku.loadRanking()                                    // 빈 표(초기화 직후 모양)
    #expect(gomoku.ranking?.entries.isEmpty == true && gomoku.ranking?.me?.rank == nil && !gomoku.rankingLoadFailed)
    await gomoku.loadRanking()                                    // unsupported_client — 실패 깃발만, 목록은 그대로, 안내 없음
    #expect(gomoku.rankingLoadFailed && gomoku.ranking?.entries.isEmpty == true && gomoku.notice == nil)
    await gomoku.loadRanking()                                    // unauthorized — 같은 길
    #expect(gomoku.rankingLoadFailed && gomoku.notice == nil && !gomoku.rankingUnavailable)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_ranking") == 5)
}

// MARK: - ④ 렌더 — 픽스처가 픽셀을 만든다(C23: 상대 열·순위 열·판·상태 상자 사각형을 따로 만든다)

private enum FxRenderError: Error { case failed }

private let fxMe = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

@MainActor
private func fxPanel(_ store: GomokuStore) -> some View {
    GomokuPanel(store: store, me: { fxMe }, clipsOverflowInsteadOfScroll: true)
}

@MainActor
private func fxBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw FxRenderError.failed }
    return bitmap
}

private func fxSave(_ bitmap: NSBitmapImageRep, name: String) {
    MiniGameSnapshots.save(bitmap, name: "v0341-fixture-\(name).png", sub: "gomoku")
}

private func fxYellowPixels(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if data[o] >= 240 && data[o + 1] >= 195 && data[o + 2] <= 40 { hits += 1 }
        }
    }
    return hits
}

private func fxMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData, lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 255 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 255 }
    var worst = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            for channel in 0..<min(3, spp) { worst = max(worst, abs(Int(a[offset + channel]) - Int(b[offset + channel]))) }
        }
    }
    return worst
}

/// 넓은 중성 획이 있는 행(카드·행 상자의 윗변·아랫변). V0341 렌더 테스트와 같은 판정식 — 높이 34 짝이 있으면 행 상자다.
private func fxWideRows(_ bitmap: NSBitmapImageRep, rect: CGRect, minimum: Int) -> [Int] {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return [] }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let ax0 = max(0, Int(rect.minX * 2)), ax1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    var rows: [Int] = []
    for y in Int(rect.minY)...Int(rect.maxY) {
        let py = min(max(y * 2, 0), bitmap.pixelsHigh - 1)
        var hits = 0
        for x in ax0...ax1 {
            let o = py * bpr + x * spp
            let r = Int(data[o]), b = Int(data[o + 2])
            if r >= 62 && r <= 120 && abs(r - b) <= 40 { hits += 1 }
        }
        if hits >= minimum { rows.append(y) }
    }
    return rows
}

private func fxBoxTops(_ bitmap: NSBitmapImageRep, rect: CGRect, height: Int, minimum: Int) -> [Int] {
    let wide = fxWideRows(bitmap, rect: rect, minimum: minimum)
    return wide.filter { wide.contains($0 + height) }
}

private var fxBodyTop: CGFloat { GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing }

private var fxUsersColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding, y: fxBodyTop, width: GomokuWindowLayout.lobbyUsersWidth, height: GomokuWindowLayout.bodyHeight)
}

private var fxRankColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.lobbyUsersWidth + GomokuWindowLayout.columnSpacing,
           y: fxBodyTop, width: GomokuWindowLayout.lobbyRankWidth, height: GomokuWindowLayout.bodyHeight)
}

private var fxLobbySideColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.lobbyListWidth + GomokuWindowLayout.columnSpacing,
           y: fxBodyTop, width: GomokuWindowLayout.lobbySideWidth, height: GomokuWindowLayout.bodyHeight)
}

private var fxBoardRect: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding, y: fxBodyTop, width: GomokuWindowLayout.boardSide, height: GomokuWindowLayout.boardSide)
}

private var fxSideColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.boardSide + GomokuWindowLayout.columnSpacing,
           y: fxBodyTop, width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.bodyHeight)
}

private var fxWatchStatusBox: CGRect {
    let cardsBottom = fxSideColumn.minY + GomokuWindowLayout.playerCardHeight * 2 + GomokuWindowLayout.matchSideSpacing
    return CGRect(x: fxSideColumn.minX + GomokuWindowLayout.stakeChipWidth + GomokuWindowLayout.matchSideSpacing,
                  y: cardsBottom + GomokuWindowLayout.matchSideSpacing,
                  width: GomokuWindowLayout.sideColumnWidth - GomokuWindowLayout.stakeChipWidth - GomokuWindowLayout.matchSideSpacing,
                  height: GomokuWindowLayout.spectateStatusMinHeight)
}

@MainActor
private func fxLobbyStore() -> GomokuStore {
    let store = GomokuStore()
    store.users = [
        GomokuUser(id: "00000000-0000-4000-8000-000000000011", displayName: "민수", avatarURL: nil, characterID: "fox",
                   isWorking: true, isCapable: true, inMatch: false),
        GomokuUser(id: "00000000-0000-4000-8000-000000000012", displayName: "준호", avatarURL: nil, characterID: "squirrel",
                   isWorking: true, isCapable: true, inMatch: false),
    ]
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.rubyBalance = 42
    store.hasLoadedLobby = true
    return store
}

/// 관전 픽스처를 헤드리스 스토어에 적용해 화면 값으로(스토어 경계 `applyWatch` 를 그대로 지난다 — 매퍼만 부르면 흑백·마감 보정을 건너뛴다).
@MainActor
private func fxApplied(_ name: String, since: Int, into store: GomokuStore) throws -> GomokuSpectateState {
    if store.spectating == nil { store.spectating = GomokuSpectateState(id: try fxUser("m_watch")) }
    store.applyWatch(try fxDecode(GomokuWatchResponse.self, name), requestedSince: since)
    return try #require(store.spectating, "\(name) 을 적용했는데 관전이 내려갔다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_순위_픽스처가_순위_열에_다섯_행을_그리고_빈_표는_행이_없다() throws {
    // 없으면: 매퍼가 행을 다 떨어뜨려(rank·user_id 를 못 읽어) 순위 열이 카드 크롬만 그리거나, 빈 표가 자리표시 행으로 채워져도 스토어 테스트는 초록이다.
    let full = fxLobbyStore()
    full.ranking = GomokuStore.rankingBoard(from: try fxDecode(GomokuRankingResponse.self, "gomoku_ranking__ok"))
    let empty = fxLobbyStore()
    empty.ranking = GomokuStore.rankingBoard(from: try fxDecode(GomokuRankingResponse.self, "gomoku_ranking__ok_empty"))
    let fullBitmap = try fxBitmap(fxPanel(full))
    let emptyBitmap = try fxBitmap(fxPanel(empty))
    fxSave(fullBitmap, name: "rank-ok")
    fxSave(emptyBitmap, name: "rank-empty")
    #expect(full.ranking?.entries.count == 5 && empty.ranking?.entries.isEmpty == true)
    #expect(fxYellowPixels(fullBitmap, rect: fxRankColumn) == 0 && fxYellowPixels(emptyBitmap, rect: fxRankColumn) == 0, "노란 상자 — Picker/Menu 가 섞였다")
    #expect(fxMaxChannelDifference(fullBitmap, emptyBitmap, rect: fxRankColumn) > 60, "5행과 0행의 순위 열이 같다 — 행이 안 그려진다")
    let rowTops = fxBoxTops(fullBitmap, rect: fxRankColumn, height: Int(GomokuWindowLayout.rankRowHeight), minimum: 500)
    #expect(rowTops.count == 5, "실서버 5행인데 행 상자가 \(rowTops.count)장이다(윗변 \(rowTops))")
    #expect(fxBoxTops(emptyBitmap, rect: fxRankColumn, height: Int(GomokuWindowLayout.rankRowHeight), minimum: 500).isEmpty, "빈 표에 행 상자가 있다")
    #expect(fxMaxChannelDifference(fullBitmap, emptyBitmap, rect: fxUsersColumn) <= 2 && fxMaxChannelDifference(fullBitmap, emptyBitmap, rect: fxLobbySideColumn) <= 2,
            "순위 열이 상대 목록·오른쪽 열을 흔들었다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_관전_픽스처가_판에_돌을_그리고_상태_상자가_진행_마감지남_끝남을_가른다() throws {
    // 없으면: 매퍼가 서버 board 문자열을 못 읽어 빈 판을 그리거나, 상태 상자가 마감·끝남과 무관하게 한 문장으로 굳어도(C19) 스토어 테스트는 초록이다.
    let a = try fxUser("A")
    let live = fxLobbyStore()
    var liveState = try fxApplied("gomoku_watch__ok_since0", since: 0, into: live)
    #expect(liveState.hasServerState && liveState.board.stoneCount == 2)
    liveState.deadline = Date().addingTimeInterval(20)              // 픽스처의 마감은 실측 순간이라 이미 지났다 — 진행 중 모양은 마감을 앞으로 둔다
    live.spectating = liveState
    let blank = fxLobbyStore()
    var blankState = liveState
    blankState.board = GomokuBoard()
    blankState.lastMove = nil
    blank.spectating = blankState
    let ended = fxLobbyStore()
    _ = try fxApplied("gomoku_watch__ok_since0", since: 0, into: ended)
    _ = try fxApplied("gomoku_watch__ok_since2", since: 2, into: ended)
    let endedState = try fxApplied("gomoku_watch__ok_finished", since: 3, into: ended)
    let overdue = fxLobbyStore()
    let overdueState = try fxApplied("gomoku_watch__ok_overdue", since: 0, into: overdue)

    let liveBitmap = try fxBitmap(fxPanel(live))
    let blankBitmap = try fxBitmap(fxPanel(blank))
    let endedBitmap = try fxBitmap(fxPanel(ended))
    let overdueBitmap = try fxBitmap(fxPanel(overdue))
    fxSave(liveBitmap, name: "watch-live")
    fxSave(endedBitmap, name: "watch-ended")
    fxSave(overdueBitmap, name: "watch-overdue")

    #expect(fxMaxChannelDifference(liveBitmap, blankBitmap, rect: fxBoardRect) > 60, "실서버 판(돌 2)과 빈 판이 같은 픽셀이다 — 돌이 안 그려진다")
    #expect(fxYellowPixels(liveBitmap, rect: fxSideColumn) == 0, "관전 오른쪽 열에 노란 상자")
    let now = Date()
    #expect(GomokuWatchStatusRule.kind(for: liveState, now: now) == .turn(.black))
    #expect(GomokuWatchStatusRule.kind(for: overdueState, now: now) == .overdue, "마감이 지난 실서버 판이 '차례'로 판정된다(C19)")
    #expect(GomokuWatchStatusRule.kind(for: endedState, now: now) == .ended)
    #expect(endedState.isFinished && endedState.winner == .black && endedState.board.stoneCount == 3)
    #expect(GomokuWatchStatusRule.text(for: endedState, now: now).contains("abto.app"), "끝난 판의 승자 이름이 서버 black_user 에서 오지 않는다")
    #expect(!GomokuWatchStatusRule.text(for: overdueState, now: now).contains("졌"), "마감이 지났다고 '졌다'고 말한다(C19)")
    #expect(fxMaxChannelDifference(liveBitmap, endedBitmap, rect: fxWatchStatusBox) > 60, "진행 중과 끝남의 상태 상자가 같은 픽셀이다")
    #expect(fxMaxChannelDifference(liveBitmap, overdueBitmap, rect: fxWatchStatusBox) > 60, "진행 중과 마감 지남의 상태 상자가 같은 픽셀이다")
    #expect(fxMaxChannelDifference(endedBitmap, overdueBitmap, rect: fxWatchStatusBox) > 60, "끝남과 마감 지남의 상태 상자가 같은 픽셀이다")
    #expect(a == endedState.black?.id, "픽스처의 흑(A)이 화면 값의 흑이 아니다")
}
