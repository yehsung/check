import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 — **서버 초안 두 장 ↔ 클라 상수·어휘 대조**(MJ/SPEC.md §6.3 T `V03xxMahjongMigrationContractTests` · §1 시험 변수).
// 초안은 승인 전엔 `supabase/migrations` 밖(`MJ/server/{rules,table}`)에 있다 — 변수 `MAHJONG_RULES_SQL` · `MAHJONG_TABLE_SQL` 로 주고,
// 없으면 기본 자리(`supabase/migrations/2026110822{0000_mahjong_rules,1000_mahjong_table}.sql`)를 본다. 둘 다 없으면 건너뛴다.
// `MAHJONG_REQUIRE_MIGRATION=1` 이면 건너뜀 0 — 파일이 없으면 빨강(통합 검증에서 한 번 켠다).
// 공용 `CHECK_MIGRATIONS_DIR` 는 쓰지 않는다(그 변수는 체인 전체를 읽는 시험 수십 개가 같이 본다).
//
// 각 시험 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가".

private enum MMC {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var required: Bool { env["MAHJONG_REQUIRE_MIGRATION"] == "1" }

    static func path(_ key: String, _ fallback: String) -> String {
        env[key].flatMap { $0.isEmpty ? nil : $0 } ?? root.appendingPathComponent("supabase/migrations/\(fallback)").path
    }

    static var rulesPath: String { path("MAHJONG_RULES_SQL", "20261108220000_mahjong_rules.sql") }
    static var tablePath: String { path("MAHJONG_TABLE_SQL", "20261108221000_mahjong_table.sql") }
    static var enabled: Bool {
        required || FileManager.default.fileExists(atPath: rulesPath) || FileManager.default.fileExists(atPath: tablePath)
    }

    static func read(_ path: String) throws -> String {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw MMCError("초안이 없다: \(path)")
        }
        return text
    }

    /// `create or replace function public.<name>(` 의 인자 목록 원문.
    static func argumentList(_ sql: String, function: String) -> String? {
        guard let head = sql.range(of: "create or replace function public.\(function)(") else { return nil }
        var depth = 1
        var index = head.upperBound
        while index < sql.endIndex, depth > 0 {
            if sql[index] == "(" { depth += 1 } else if sql[index] == ")" { depth -= 1 }
            index = sql.index(after: index)
        }
        return String(sql[head.upperBound..<sql.index(before: index)])
    }

    /// `public.mahjong_<name>() returns … select <값> $fn$` 의 값 글자.
    static func constant(_ sql: String, _ name: String) -> String? {
        guard let head = sql.range(of: "create or replace function public.\(name)()"),
              let select = sql.range(of: "select ", range: head.upperBound..<sql.endIndex),
              let end = sql.range(of: " $fn$", range: select.upperBound..<sql.endIndex) else { return nil }
        return sql[select.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(_ pattern: String, in text: String) -> [[String]] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
    }
}

private struct MMCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@Suite("아잉 마작 서버 초안 대조 — RPC 집합 · 인자 DEFAULT · 초인종 이름 · 일일 미션 · 역 순서 · 상수 · status 어휘",
       .enabled(if: MMC.enabled, "두 초안이 없다 — MAHJONG_RULES_SQL·MAHJONG_TABLE_SQL 을 주거나 MAHJONG_REQUIRE_MIGRATION=1"))
struct V03xxMahjongMigrationContractTests {
    // 없으면: 판 파일에 클라가 모르는 RPC 가 생기거나(또는 클라 RPC 가 서버에 없어) 404 가 운영에서야 드러난다. 머리글(`mahjong_`)로
    // 세면 판정 함수(service_role 전용)까지 섞이므로 계약 표에서 **'rpc' 로 실행권을 받는 함수**로 센다(D2).
    @Test func clientRPCsAreExactlyTheGrantedOnes() throws {
        let table = try MMC.read(MMC.tablePath)
        let granted = Set(MMC.matches(#"array\['public\.(mahjong_[a-z_]+)\([^']*\)', 'rpc'\]"#, in: table).compactMap(\.first))
        #expect(granted == Set(MahjongWire.RPC.allCases.map(\.rawValue)), "판 파일 rpc \(granted.sorted())")
        #expect(granted.count == 13)
        // ★ 기준선: 같은 표에서 'rpc' 아닌 줄(상수·내부)은 다른 집합이다.
        let all = Set(MMC.matches(#"array\['public\.(mahjong_[a-z_]+)\("#, in: table).compactMap(\.first))
        #expect(all.count > granted.count)
        for rpc in granted {
            let args = try #require(MMC.argumentList(table, function: rpc), "\(rpc) 정의가 없다")
            #expect(args.hasPrefix("p_protocol int default 0"), "\(rpc): 첫 인자가 p_protocol int default 0 이 아니다")
            for arg in args.split(separator: ",") {
                #expect(arg.lowercased().contains(" default "), "\(rpc): DEFAULT 없는 인자 \(arg)")
            }
        }
        // 오목 머리 정의 금지(V0341 파서가 오목 함수로 센다).
        let rules = try MMC.read(MMC.rulesPath)
        #expect(!table.contains("function public.gomoku_") && !rules.contains("function public.gomoku_"))
    }

    // 없으면: 서버가 다른 이벤트 이름으로 울리면 맥은 그 초인종을 '모르는 이름'으로 접어 버림마다 take_pokes 를 한 번 더 부른다.
    @Test func theServerRingsTheClientEventName() throws {
        let table = try MMC.read(MMC.tablePath)
        let events = Set(MMC.matches(#"perform realtime\.send\([\s\S]*?\),\s*'([a-z_]+)'"#, in: table).compactMap(\.first))
        #expect(events == [RealtimeLinkConstants.mahjongBroadcastEvent], "초인종 이름 \(events)")
    }

    // 없으면: 일일 미션 줄의 키·게임 이름이 클라 꼬리(`refreshAchievementsAfterGameResult(game: "mahjong")`)와 갈려 판을 끝내도 미션이 안 오른다.
    @Test func theDailyMissionRowMatchesTheClientKey() throws {
        let table = try MMC.read(MMC.tablePath)
        let rows = MMC.matches(#"\('(daily_mahjong)',\s*'([a-z_]+)',\s*'([^']+)',\s*'([^']+)',\s*(\d+),\s*(\d+),\s*(\d+)\)"#, in: table)
        let row = try #require(rows.first, "daily_mahjong 줄이 없다")
        #expect(row[0] == DailyMissionStatus.key(game: row[1]) && row[1] == "mahjong")
        #expect(row[2] == "\(MahjongNoticeText.gameName) 한 판 하기" && row[4] == "5" && row[5] == "1" && row[6] == "90")
        #expect(Set(rows.map { $0.joined(separator: "|") }).count == 1, "판 파일 안 daily_mahjong 줄들이 서로 다르다")
    }

    // 없으면: 역 표시 순서가 서버(결과 wins[].yaku 순서)와 클라(역 표·연습판)에서 갈린다.
    @Test func theYakuOrderMatches() throws {
        let rules = try MMC.read(MMC.rulesPath)
        let body = try #require(MMC.constant(rules, "mahjong_yaku_order"))
        let ids = MMC.matches(#"'([a-z0-9_]+)'"#, in: body).compactMap(\.first)
        #expect(ids == MahjongYaku.order.map(\.rawValue))
    }

    // 없으면: 시계(5+20·유예 1초)·판돈·쉬는 시간·방 확인·복귀 쿨다운이 서버와 클라에서 갈려 클라가 마감 전에 자동 처리를 그리거나 늦은 답을 보낸다.
    @Test func theConstantsMatch() throws {
        let table = try MMC.read(MMC.tablePath)
        func int(_ name: String) throws -> Int { try #require(Int(MMC.constant(table, name) ?? ""), "\(name)") }
        #expect(try int("mahjong_protocol") == MahjongWire.protocolVersion)
        #expect(try int("mahjong_base_ms") == MahjongClock.baseMs)
        #expect(try int("mahjong_bank_ms") == MahjongClock.bankFullMs)
        #expect(try int("mahjong_grace_ms") == MahjongClock.graceMs)
        #expect(Double(try int("mahjong_back_cooldown_ms")) == MahjongTableEngine.backCooldownMs)
        #expect(Double(try int("mahjong_room_check_seconds")) == MahjongStore.roomCheckSeconds)
        #expect(Double(try int("mahjong_hand_pause_ms")) / 1_000 == MahjongStore.practiceHandRestSeconds(winners: 1))
        #expect(Double(try int("mahjong_extra_win_pause_ms")) / 1_000
                    == MahjongStore.practiceHandRestSeconds(winners: 2) - MahjongStore.practiceHandRestSeconds(winners: 1))
        // 보조 쯔모기리·연습판 멈춤의 [0.5, 1.0]초 = 바닥 500 + 폭 500.
        let floorMin = try int("mahjong_floor_min_ms")
        let floorSpan = try int("mahjong_floor_span_ms")
        #expect(floorMin == 500 && floorSpan == 500)
        let stakes = MMC.matches(#"(\d+)"#, in: try #require(MMC.constant(table, "mahjong_stakes"))).compactMap(\.first)
        #expect(stakes == MahjongStake.allCases.map { String($0.rawValue) })
        let formats = MMC.matches(#"'([a-z]+)'"#, in: try #require(MMC.constant(table, "mahjong_formats"))).compactMap(\.first)
        #expect(formats == MahjongFormat.allCases.map(\.rawValue))
        // wake_step(박자 기기 5초 걸음)는 서버 판정이라 클라 상수가 없다 — 클라는 응답의 wake_at_ms 를 그대로 쓴다.
        #expect(try int("mahjong_wake_step_ms") == 5_000)
    }

    // 없으면: 서버가 새 status 를 내는데 클라가 몰라 `.unknown`(문구 없음)으로 접히거나, 클라가 서버에 없는 status 를 기다린다.
    @Test func theStatusVocabularyMatches() throws {
        let table = try MMC.read(MMC.tablePath)
        // 응답 봉투의 머리 칸만(`jsonb_build_object('status', '<값>'` — 사후 단언의 키 이름 배열 `'status', 'turn_seat'` 류는 status 가 아니다).
        let sql = Set(MMC.matches(#"jsonb_build_object\(\s*'status',\s*'([a-z_]+)'"#, in: table).compactMap(\.first))
        let swift = Set(MahjongRPCStatus.allCases.filter { $0 != .unknown }.map(\.rawValue))
        #expect(sql == swift, "SQL 만: \(sql.subtracting(swift).sorted()) · Swift 만: \(swift.subtracting(sql).sorted())")
        #expect(sql.contains("too_early"))
    }
}
