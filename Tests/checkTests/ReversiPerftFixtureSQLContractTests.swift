import Foundation
import Testing

// 아잉 뒤집기 수 세기(perft) 기대값의 **집이 하나**인지 보는 소스 계약 — `Fixtures/reversi-perft.json` ↔ 리버시 마이그레이션
// `20261108200000_reversi.sql` 의 `pg_temp.reversi_perft_expect` 행(SPEC §6.2 · 체스 `ChessPerftFixtureSQLContractTests` 틀).
//
// 없으면 어떤 결함이 초록으로 통과하는가: **Swift(`ReversiPerftTests`)와 SQL(적용 시점 자기 검사 §12)이 각자 숫자를 적어
// 둘이 갈리는 것.** 세 구현(SQL · Swift · 파이썬)이 서로를 검산하는 근거는 "같은 픽스처를 본다" 하나뿐이다. 마이그레이션이
// 자기 구현에 맞춰 노드 수를 고치거나, 픽스처에 없는 국면을 더 적거나, 라벨·색을 바꿔 적어도 SQL 쪽 자기 검사는 여전히
// 통과한다 — 그 순간 perft 는 검산이 아니라 자기 확인이 된다. 그래서 행 하나하나를 픽스처와 **글자 단위로** 맞춘다.
//
// 마이그레이션이 지켜야 하는 행 모양(픽스처 `sql_contract` 와 같은 말):
//   ('<라벨>', '<판 64자 .bw>', '<black|white>', <깊이>, <노드>)   -- 색 다음에 정수 둘, 깊이가 먼저
// 그 행들은 **식별자에 `reversi_perft` 가 든 문장** 안에 있어야 한다(예: `pg_temp.reversi_perft_expect`). 문장 단위로 좁히는
// 까닭: 같은 판 글자가 §12 손 사례 jsonb 에도 나오는데, 거기 정수를 깊이·노드로 잘못 읽으면 거짓 빨강이 된다.
// `reversi_perft` 는 depth 0~6 만 받으므로(§3.3) SQL 행의 깊이는 1~6 이어야 하고, 필수는 시작 판 1~4 · 잎 ⓐ~ⓔ 1·2 다.
//
// 마이그레이션 위치(SPEC §6.2 v1.1 — 공용 `CHECK_MIGRATIONS_DIR` 가 **아니다**): `REVERSI_MIGRATION_SQL=<파일>` → 없으면 조상의
// `supabase/migrations/20261108200000_reversi.sql`. `REVERSI_REQUIRE_MIGRATION=1` 이면 파일이 없을 때 건너뛰지 않고 빨갛다
// (초안은 승인 전까지 supabase/migrations 에 안 들어가므로 "없으면 건너뜀"만 두면 재지 않는 초록이다).
//
// 주석은 걷어내고 본다(설명문의 숫자가 단언에 끼지 않게). 단 **픽스처 출처 표기**는 주석에만 있을 수 있어 원문으로 본다.

private let rpfMigrationName = "20261108200000_reversi.sql"
private let rpfFixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/reversi-perft.json")

/// SQL 이 반드시 대조해야 하는 깊이 — 잎은 1 과 2 둘 다(깊이 2 가 "0 이 섞인 합계가 살아남는가" — `array_length('{}',1)` = NULL
/// 결함이 터지는 자리), 시작 판은 1~4(픽스처 `sql_contract`).
private let rpfRequiredLeafDepths = [1, 2]
private let rpfRequiredPositionDepths = [1, 2, 3, 4]
/// `reversi_perft` 가 받는 깊이(§3.3 — 밖이면 22023). 행 깊이가 이 밖이면 적용이 멈추거나 노드 자리를 깊이로 읽은 것이다.
private let rpfSQLDepths = 1...6

private struct RPFError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct RPFFixture: Decodable {
    struct Item: Decodable {
        let label: String
        let board: String
        let color: String
        let counts: [Int]
    }
    let positions: [Item]
    let leaves: [Item]
    let sqlContract: String
    var all: [Item] { positions + leaves }
}

private func rpfFixture() throws -> RPFFixture {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RPFFixture.self, from: Data(contentsOf: rpfFixtureURL))
}

/// 리버시 마이그레이션 한 장의 위치(SPEC §6.2).
private func rpfMigrationURL() -> URL? {
    let fileManager = FileManager.default
    if let path = ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"], !path.isEmpty {
        return fileManager.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations/\(rpfMigrationName)")
        if fileManager.fileExists(atPath: candidate.path) { return candidate }
        directory.deleteLastPathComponent()
    }
    return nil
}

private let rpfMigrationRequired = ProcessInfo.processInfo.environment["REVERSI_REQUIRE_MIGRATION"] == "1"
/// 돌아야 하는가 — 파일이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let rpfMigrationGate = rpfMigrationURL() != nil || rpfMigrationRequired

private func rpfMigrationRaw() throws -> String {
    guard let url = rpfMigrationURL() else {
        throw RPFError("""
            리버시 마이그레이션이 없다(REVERSI_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"] ?? "(없음)")) — \
            REVERSI_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
            """)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// `--` 줄 주석을 걷어낸다(판 문자열은 `.bw` 뿐이라 `--` 가 없다 — §2.2 가 `-` 를 금지한 까닭).
private func rpfStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// SQL 문자열 리터럴(`''` 는 글자 하나). 값 · 여는 따옴표 위치 · 닫는 따옴표 뒤 위치.
private func rpfStringLiterals(_ sql: String) -> [(value: String, start: String.Index, after: String.Index)] {
    var out: [(String, String.Index, String.Index)] = []
    var index = sql.startIndex
    while index < sql.endIndex {
        guard sql[index] == "'" else { index = sql.index(after: index); continue }
        let start = index
        var cursor = sql.index(after: index)
        var value = ""
        while cursor < sql.endIndex {
            if sql[cursor] == "'" {
                let next = sql.index(after: cursor)
                if next < sql.endIndex, sql[next] == "'" {
                    value.append("'")
                    cursor = sql.index(after: next)
                    continue
                }
                cursor = next
                break
            }
            value.append(sql[cursor])
            cursor = sql.index(after: cursor)
        }
        out.append((value, start, cursor))
        index = cursor
    }
    return out
}

/// 판 한 장 모양인가(64자 `.bw`). 픽스처에 있는지와 **따로** 본다 — 픽스처에 없는 국면을 마이그레이션이 더 적는 것(= 자기 숫자를
/// 적는 것)을 잡으려면 "판처럼 생긴 것"을 먼저 다 모아야 한다.
private func rpfLooksLikeBoard(_ text: String) -> Bool {
    text.count == 64 && text.allSatisfy { $0 == "." || $0 == "b" || $0 == "w" }
}

/// `reversi_perft` 가 든 문장들(이전 `;` 다음 ~ 다음 `;` 앞). 겹치는 구간은 한 번만.
private func rpfRegions(_ sql: String) -> [String] {
    var ranges: [Range<String.Index>] = []
    var searchStart = sql.startIndex
    while let hit = sql.range(of: "reversi_perft", range: searchStart..<sql.endIndex) {
        searchStart = hit.upperBound
        let start = sql[sql.startIndex..<hit.lowerBound].lastIndex(of: ";").map { sql.index(after: $0) } ?? sql.startIndex
        let end = sql[hit.upperBound...].firstIndex(of: ";") ?? sql.endIndex
        let range = start..<end
        if !ranges.contains(range) { ranges.append(range) }
    }
    return ranges.map { String(sql[$0]) }
}

/// 두 위치 사이가 쉼표 하나와 공백뿐인가(행 안의 이웃 칸인가).
private func rpfOnlyComma(_ text: String, from: String.Index, to: String.Index) -> Bool {
    guard from <= to else { return false }
    let gap = text[from..<to].filter { !$0.isWhitespace }
    return gap == ","
}

/// 리터럴 뒤에서 행이 끝날 때까지(첫 `)` 또는 `;`) 나오는 정수들.
private func rpfTrailingIntegers(_ text: String, after start: String.Index) -> [Int] {
    var out: [Int] = []
    var digits = ""
    var index = start
    while index < text.endIndex {
        let character = text[index]
        if character.isNumber || (character == "_" && !digits.isEmpty) {
            if character != "_" { digits.append(character) }
        } else {
            if !digits.isEmpty { out.append(Int(digits) ?? -1); digits = "" }
            if character == ")" || character == ";" { return out }
        }
        index = text.index(after: index)
    }
    if !digits.isEmpty { out.append(Int(digits) ?? -1) }
    return out
}

@Suite("아잉 뒤집기 수 세기 — 픽스처 ↔ 마이그레이션 계약")
struct ReversiPerftFixtureSQLContractTests {

    // 없으면: 마이그레이션이 노드 수·깊이·라벨·색을 자기 구현에 맞춰 적거나, 픽스처에 없는 국면을 더 적거나, 잎(ⓐⓑ — NULL 합계
    // 결함을 ms 안에 밟는 자리)을 빼도 SQL 자기 검사는 통과하고 다른 시험은 마이그레이션을 안 읽어 초록이다.
    @Test(.enabled(if: rpfMigrationGate))
    func 픽스처와_리버시_마이그레이션이_같은_행을_쓴다() throws {
        let fixture = try rpfFixture()
        #expect(fixture.positions.count == 1 && fixture.leaves.count == 5,
                "픽스처 모양이 바뀌었다(positions \(fixture.positions.count) · leaves \(fixture.leaves.count)) — 이 대조의 필수 목록을 함께 고쳐라")
        #expect(fixture.sqlContract.contains("reversi_perft_expect"), "픽스처 sql_contract 가 행이 들어갈 문장을 말하지 않는다")

        let raw = try rpfMigrationRaw()
        let sql = rpfStrip(raw)

        // (0) 출처 표기 — 숫자를 고치려는 사람에게 집이 어디인지 파일 안에서 말해 준다(주석에만 있을 수 있어 원문으로 본다).
        #expect(raw.contains("reversi-perft.json"), "마이그레이션이 픽스처(reversi-perft.json)를 출처로 안 적었다")

        // (1) `reversi_perft` 문장들. 하나도 없으면 SQL 이 수 세기를 아예 안 잰다.
        let regions = rpfRegions(sql)
        try #require(!regions.isEmpty, "\(rpfMigrationName) 에 reversi_perft 가 든 문장이 없다 — SQL 이 수 세기를 안 잰다")

        let byBoard = Dictionary(fixture.all.map { ($0.board, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [String: Set<Int>] = [:]
        var rowCount = 0

        for region in regions {
            let literals = rpfStringLiterals(region)
            for (offset, literal) in literals.enumerated() where rpfLooksLikeBoard(literal.value) {
                rowCount += 1
                guard let item = byBoard[literal.value] else {
                    Issue.record("""
                        마이그레이션이 픽스처에 없는 국면의 수 세기를 적었다 — '각자 숫자를 적는' 것이다.
                        판: \(literal.value)
                        픽스처(Fixtures/reversi-perft.json)에 먼저 넣고(make_perft.py) Swift 로 확인한 뒤 베껴라.
                        """)
                    continue
                }
                // 라벨 — 판 바로 앞 칸. 글자 그대로 같아야 SQL 실패 문구가 픽스처 라벨로 사람을 데려간다.
                guard offset > 0, rpfOnlyComma(region, from: literals[offset - 1].after, to: literal.start) else {
                    Issue.record("\(item.label): 판 앞에 라벨 칸이 없다 — 행 모양은 ('<라벨>', '<판>', '<색>', <깊이>, <노드>)")
                    continue
                }
                #expect(literals[offset - 1].value == item.label,
                        "\(item.label): 마이그레이션 라벨 '\(literals[offset - 1].value)' ≠ 픽스처 라벨 '\(item.label)'")
                // 색 — 판 바로 뒤 칸. 다른 색이면 같은 판이라도 다른 국면이다(노드 수가 다르다).
                guard offset + 1 < literals.count,
                      rpfOnlyComma(region, from: literal.after, to: literals[offset + 1].start) else {
                    Issue.record("\(item.label): 판 뒤에 색 칸이 없다 — 행 모양은 ('<라벨>', '<판>', '<색>', <깊이>, <노드>)")
                    continue
                }
                let color = literals[offset + 1]
                #expect(color.value == item.color, "\(item.label): 마이그레이션 색 '\(color.value)' ≠ 픽스처 색 '\(item.color)'")

                let integers = rpfTrailingIntegers(region, after: color.after)
                guard integers.count == 2 else {
                    Issue.record("\(item.label): 색 뒤에 정수가 \(integers.count)개다(\(integers)) — 깊이·노드 둘만 와야 한다")
                    continue
                }
                let (depth, nodes) = (integers[0], integers[1])
                guard rpfSQLDepths.contains(depth) else {
                    Issue.record("""
                        \(item.label): 깊이가 \(depth) 다(노드 자리는 \(nodes)). reversi_perft 는 depth 0~6 만 받는다 —
                        깊이·노드 순서가 바뀌었거나, 적용 시점에 22023 으로 멈출 행이다.
                        """)
                    continue
                }
                guard depth <= item.counts.count else {
                    Issue.record("\(item.label) 깊이 \(depth): 픽스처에 그 깊이 기대값이 없다 — 마이그레이션이 숫자를 지어내면 안 된다")
                    continue
                }
                #expect(nodes == item.counts[depth - 1], """
                    \(item.label) 깊이 \(depth): 마이그레이션 \(nodes) ≠ 픽스처 \(item.counts[depth - 1]).
                    둘 중 하나가 자기 구현에 맞춰 고쳐진 것이다 — 숫자를 내리지 말고 구현을 고쳐라.
                    """)
                found[item.board, default: []].insert(depth)
            }
        }

        // (2) 빠뜨린 자리. 잎이 빠지면 NULL 합계 결함이 깊이를 올려야만 밟히는 상태로 되돌아간다.
        for item in fixture.leaves {
            for depth in rpfRequiredLeafDepths {
                #expect(found[item.board]?.contains(depth) == true,
                        "\(item.label) 깊이 \(depth) 를 마이그레이션이 안 잰다 — 잎은 빈 합법 수 목록을 ms 안에 밟는 자리다, 빼지 마라")
            }
        }
        for item in fixture.positions {
            for depth in rpfRequiredPositionDepths {
                #expect(found[item.board]?.contains(depth) == true,
                        "\(item.label) 깊이 \(depth) 를 마이그레이션이 안 잰다 — 시작 판은 1~4 가 필수다(sql_contract)")
            }
        }

        // (3) 읽은 행 수 — 파서가 조용히 0 줄을 읽고 통과하는 일을 막는다(모양이 아니라 결과를 잰다).
        let minimum = fixture.leaves.count * rpfRequiredLeafDepths.count
            + fixture.positions.count * rpfRequiredPositionDepths.count
        #expect(rowCount >= minimum, "수 세기 행을 \(rowCount)줄만 읽었다(최소 \(minimum)줄) — 파서가 행을 못 찾았거나 마이그레이션이 비었다")
    }
}
