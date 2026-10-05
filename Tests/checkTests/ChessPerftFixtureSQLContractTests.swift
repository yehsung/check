import Foundation
import Testing

// 체스 수 세기 기대값의 **집이 하나**인지 보는 소스 계약 — `Fixtures/chess-perft.json` ↔ 마이그레이션
// `supabase/migrations/20261005140000_chess_rules.sql`.
//
// 없으면 어떤 결함이 초록으로 통과하는가: **Swift 와 SQL 이 각자 숫자를 적어 둘이 갈리는 것.** 두 구현이
// 서로를 검산하는 유일한 근거가 "같은 공표값을 본다"는 것인데, 숫자를 양쪽에 손으로 적으면 한쪽이 자기
// 구현에 맞춰 숫자를 고쳐도 아무도 모른다 — 그 순간 perft 는 검산이 아니라 자기 확인이 된다. 그래서 숫자는
// 픽스처 한 곳에 있고, 마이그레이션은 **베껴 적은 것**이어야 하며, 베낀 값이 어긋나면 여기서 걸린다.
//
// 마이그레이션이 지켜야 하는 행 모양(픽스처 `sql_contract` 와 같은 말이다):
//   ('<라벨>', '<fen>', <깊이>, <노드>)      -- fen 다음에 정수 둘, 깊이가 먼저
// 그 행들은 **식별자에 `chess_perft` 가 든 문장** 안에 있어야 한다(예: `pg_temp.chess_perft_expect`).
// 그렇게 묶는 까닭: 같은 FEN 이 프로브의 `chess_matches` insert 에도 나타나는데, 거기 정수(판돈·남은 ms)를
// 깊이·노드로 잘못 읽으면 이 테스트가 거짓으로 빨개진다. 문장 단위로 좁히면 그 혼동이 원리적으로 없다.
//
// 주석은 걷어내고 본다(이 저장소의 소스 계약 관용구) — 안 걷어내면 설명문에 적은 숫자가 단언에 끼어들어,
// 주석을 지워야만 초록이 되는 자리가 생긴다. 단 **픽스처 출처 표기**는 주석에만 있을 수 있으므로 원문으로 본다.
//
// 마이그레이션이 아직 없을 때는 사유를 남기고 건너뛴다(다음 단계가 만든다). `supabase/` 는 git 밖이라
// 워크트리엔 폴더 자체가 없다 — 그때도 같은 길로 건너뛴다(메모리 `worktree-has-no-supabase-dir`).

private let chessPerftMigrationName = "20261005140000_chess_rules.sql"
private let chessPerftFixtureRelativePath = "Tests/checkTests/Fixtures/chess-perft.json"

/// SQL 이 반드시 대조해야 하는 깊이. 잎은 **1 과 2 둘 다** — 깊이 1 은 "빈 목록이 0 인가", 깊이 2 는
/// "0 이 섞인 합계가 살아남는가"를 보고, 뒤쪽이 바로 `array_length(빈 배열, 1) = NULL` 결함이 터지는 자리다.
/// 공표 여섯은 깊이 1 만 요구한다(깊이 3 이 10만 노드라 PL/pgSQL 에서 적용 시간이 분 단위로 늘어난다 —
/// 더 깊이 재는 것은 **허용**이고, 적은 값은 전부 픽스처와 맞아야 한다).
private let chessPerftRequiredLeafDepths = [1, 2]
private let chessPerftRequiredPositionDepths = [1]

private struct ChessPerftContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// 조상을 훑어 `supabase/migrations` 를 잡는다. `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다(뮤테이션 사본용) —
/// 다른 마이그레이션 계약 테스트(V0338·V0341)와 같은 길이다.
private func chessPerftMigrationsDirectory() -> URL? {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    return nil
}

/// `--` 줄 주석을 걷어낸다. 달러 인용 문자열 안의 `--` 도 같이 잘리므로, 그 줄에 걸리는 단언은 원문으로 둔다.
private func chessPerftStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// SQL 문자열 리터럴을 전부 집는다(`''` 는 글자 하나로 접는다). 값과 **닫는 따옴표 뒤 위치**를 같이 돌려준다 —
/// 깊이·노드는 그 뒤에 적히기 때문이다.
private func chessPerftStringLiterals(_ sql: String) -> [(value: String, after: String.Index)] {
    var out: [(String, String.Index)] = []
    var index = sql.startIndex
    while index < sql.endIndex {
        guard sql[index] == "'" else { index = sql.index(after: index); continue }
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
        out.append((value, cursor))
        index = cursor
    }
    return out
}

/// FEN 한 줄 모양인가. 픽스처에 있는지와 **따로** 본다 — 마이그레이션이 픽스처에 없는 국면을 하나 더
/// 적어 넣는 것(= 자기 숫자를 적는 것)을 잡으려면, 먼저 "FEN 처럼 생긴 것"을 다 모아야 한다.
private func chessPerftLooksLikeFEN(_ text: String) -> Bool {
    let fields = text.split(separator: " ", omittingEmptySubsequences: false)
    guard fields.count == 6 else { return false }
    guard fields[0].split(separator: "/", omittingEmptySubsequences: false).count == 8 else { return false }
    guard fields[0].allSatisfy({ "rnbqkpRNBQKP12345678/".contains($0) }) else { return false }
    guard fields[1] == "w" || fields[1] == "b" else { return false }
    guard fields[2] == "-" || fields[2].allSatisfy({ "KQkq".contains($0) }) else { return false }
    let enPassant = Array(fields[3])
    guard fields[3] == "-" || (enPassant.count == 2 && "abcdefgh".contains(enPassant[0]) && "12345678".contains(enPassant[1]))
    else { return false }
    return fields[4].allSatisfy(\.isNumber) && !fields[4].isEmpty
        && fields[5].allSatisfy(\.isNumber) && !fields[5].isEmpty
}

/// `chess_perft` 가 든 문장들(이전 `;` 다음 ~ 다음 `;` 앞). 겹치는 구간은 한 번만 돌려준다.
private func chessPerftRegions(_ sql: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var searchStart = sql.startIndex
    while let hit = sql.range(of: "chess_perft", range: searchStart..<sql.endIndex) {
        searchStart = hit.upperBound
        let before = sql[sql.startIndex..<hit.lowerBound]
        let start = before.lastIndex(of: ";").map { sql.index(after: $0) } ?? sql.startIndex
        let end = sql[hit.upperBound...].firstIndex(of: ";") ?? sql.endIndex
        let range = start..<end
        if !ranges.contains(where: { $0 == range }) { ranges.append(range) }
    }
    return ranges
}

/// 리터럴 뒤에서 행이 끝날 때까지(첫 `)` 또는 `;`) 나오는 정수들. `1_000` 같은 밑줄 표기도 읽는다.
private func chessPerftTrailingIntegers(_ sql: String, after start: String.Index, limit: String.Index) -> [Int] {
    var out: [Int] = []
    var digits = ""
    var index = start
    while index < limit {
        let character = sql[index]
        if character.isNumber || (character == "_" && !digits.isEmpty) {
            if character != "_" { digits.append(character) }
        } else {
            if !digits.isEmpty { out.append(Int(digits) ?? -1); digits = "" }
            if character == ")" || character == ";" { return out }
        }
        index = sql.index(after: index)
    }
    if !digits.isEmpty { out.append(Int(digits) ?? -1) }
    return out
}

@Suite("체스 수 세기 — 픽스처 ↔ 마이그레이션 계약")
struct ChessPerftFixtureSQLContract {

    @Test("픽스처와 체스 마이그레이션이 같은 숫자를 쓴다(마이그레이션이 없으면 사유를 남기고 건너뛴다)")
    func fixtureAndMigrationAgreeOnEveryNumber() throws {
        let fixture = try chessPerftFixture()

        guard let directory = chessPerftMigrationsDirectory() else {
            Issue.record("""
                건너뜀: supabase/migrations 를 못 찾았다. `supabase/` 는 git 밖이라 **워크트리엔 폴더가 없다** —
                이 대조는 메인 저장소(/Users/yesung/check)에서 돌려야 한다(또는 CHECK_MIGRATIONS_DIR 로 가리켜라).
                """, severity: .warning)
            return
        }
        let file = directory.appendingPathComponent(chessPerftMigrationName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            Issue.record("""
                건너뜀: \(chessPerftMigrationName) 이 아직 없다(\(directory.path)). 체스 규칙 마이그레이션을 쓰는 단계가 \
                이 파일을 만들면 이 시험이 스스로 깨어나 대조한다. 그때 지켜야 하는 행 모양: \
                ('<라벨>', '<fen>', <깊이>, <노드>) — 식별자에 chess_perft 가 든 문장 안에.
                """, severity: .warning)
            return
        }

        let raw = try String(contentsOf: file, encoding: .utf8)
        let sql = chessPerftStrip(raw)

        // (0) 출처 표기 — 숫자를 고치려는 사람에게 **집이 어디인지** 파일 안에서 말해 준다.
        //     주석에만 있을 수 있으므로 원문으로 본다.
        #expect(raw.contains(chessPerftFixtureRelativePath),
                "마이그레이션이 픽스처 경로(\(chessPerftFixtureRelativePath))를 안 적었다 — 숫자의 집이 어디인지 파일만 보고 알 수 없다")

        // (1) `chess_perft` 문장들을 모은다. 하나도 없으면 마이그레이션이 수 세기를 **아예 안 재는** 것이다.
        let regions = chessPerftRegions(sql)
        guard !regions.isEmpty else {
            Issue.record("""
                \(chessPerftMigrationName) 에 chess_perft 가 든 문장이 없다 — 마이그레이션이 수 세기를 아예 안 잰다.
                기대값을 베낄 자리: ('<라벨>', '<fen>', <깊이>, <노드>) 행들을 pg_temp.chess_perft_expect 류에 넣어라.
                """)
            return
        }

        // (2) 그 문장들에서 (fen, 깊이) → 노드 를 읽는다.
        let fixtureNodes: [String: [Int: Int]] = Dictionary(uniqueKeysWithValues: fixture.all.map { item in
            (item.fen, Dictionary(uniqueKeysWithValues: item.counts.enumerated().map { ($0.offset + 1, $0.element) }))
        })
        let fixtureLabels: [String: String] = Dictionary(uniqueKeysWithValues: fixture.all.map { ($0.fen, $0.label) })
        var found: [String: [Int: Int]] = [:]
        var rowCount = 0

        for region in regions {
            // 구간을 **한 번** 문자열로 떠 둔다 — 리터럴이 돌려주는 인덱스는 그 문자열의 것이라,
            // 매번 새로 떠서 쓰면 다른 문자열의 인덱스를 쓰는 셈이 된다.
            let regionText = String(sql[region])
            for literal in chessPerftStringLiterals(regionText) where chessPerftLooksLikeFEN(literal.value) {
                let integers = chessPerftTrailingIntegers(regionText, after: literal.after, limit: regionText.endIndex)
                rowCount += 1

                guard fixtureNodes[literal.value] != nil else {
                    Issue.record("""
                        마이그레이션이 픽스처에 없는 국면의 수 세기를 적었다 — 이게 바로 '각자 숫자를 적는' 것이다.
                        FEN: \(literal.value)
                        픽스처(\(chessPerftFixtureRelativePath))에 그 국면을 먼저 넣고, Swift 로 값을 확인한 뒤 베껴라.
                        """)
                    continue
                }
                guard integers.count == 2 else {
                    Issue.record("""
                        \(fixtureLabels[literal.value] ?? literal.value): fen 뒤에 정수가 \(integers.count)개다(\(integers)).
                        행 모양은 ('<라벨>', '<fen>', <깊이>, <노드>) — fen 다음에 **깊이·노드 둘만** 와야 한다.
                        """)
                    continue
                }
                let (depth, nodes) = (integers[0], integers[1])
                guard (1...9).contains(depth) else {
                    Issue.record("""
                        \(fixtureLabels[literal.value] ?? literal.value): 깊이가 \(depth) 다(노드 자리는 \(nodes)).
                        순서가 바뀐 것 같다 — fen 다음은 **깊이**가 먼저고 노드가 나중이다.
                        """)
                    continue
                }
                guard let expected = fixtureNodes[literal.value]?[depth] else {
                    Issue.record("""
                        \(fixtureLabels[literal.value] ?? literal.value) 깊이 \(depth): 픽스처에 그 깊이 기대값이 없다.
                        픽스처에 그 깊이를 먼저 더하고(Swift 로 확인), 그 값을 베껴라 — 마이그레이션이 숫자를 **지어내면 안 된다**.
                        """)
                    continue
                }
                #expect(nodes == expected, """
                    \(fixtureLabels[literal.value] ?? literal.value) 깊이 \(depth): 마이그레이션 \(nodes) ≠ 픽스처 \(expected).
                    둘 중 하나가 자기 구현에 맞춰 고쳐진 것이다 — 공표값은 픽스처에 있다. 숫자를 내리지 말고 구현을 고쳐라.
                    """)
                found[literal.value, default: [:]][depth] = nodes
            }
        }

        // (3) 빠뜨린 자리. 특히 **잎 셋**이 빠지면 NULL 합계 결함이 깊이를 올려야만 밟히는 상태로 되돌아간다.
        for item in fixture.leaves {
            for depth in chessPerftRequiredLeafDepths {
                #expect(found[item.fen]?[depth] != nil, """
                    \(item.label) 깊이 \(depth) 를 마이그레이션이 안 잰다. 잎 자리는 ms 에 끝나고, SQL 에서
                    array_length(빈 배열, 1) 이 0 아닌 NULL 이라는 결함을 **여기서만** 싸게 잡는다 — 빼지 마라.
                    """)
            }
        }
        for item in fixture.positions {
            for depth in chessPerftRequiredPositionDepths {
                #expect(found[item.fen]?[depth] != nil, """
                    \(item.label) 깊이 \(depth) 를 마이그레이션이 안 잰다 — 공표 여섯은 적어도 깊이 1(합법 수 개수)을
                    SQL 쪽에서도 세야 한다. 안 세면 두 구현 중 어느 쪽도 상대를 검산하지 않는다.
                    """)
            }
        }

        // (4) 읽은 행이 몇 개인지 남긴다 — 파서가 조용히 0 줄을 읽고 통과하는 일을 막는다(모양이 아니라 결과를 재라).
        let minimumRows = fixture.leaves.count * chessPerftRequiredLeafDepths.count
            + fixture.positions.count * chessPerftRequiredPositionDepths.count
        #expect(rowCount >= minimumRows,
                "마이그레이션에서 수 세기 행 \(rowCount)줄만 읽었다(최소 \(minimumRows)줄) — 파서가 행을 못 찾았거나 마이그레이션이 비었다")
    }
}
