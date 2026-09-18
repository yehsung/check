import Foundation
import Testing

// B3 — 소스 계약 테스트가 쪼갠 파일을 **반쪽만** 읽지 않는다는 계약.
//
// CheckCore 를 떼면서 한 파일이던 소스 일곱 개가 맥·코어 두 조각으로 갈렸다(CheckCoreSourceLayout.splitParts). 소스 계약 테스트가
// 그중 한 조각만 읽으면 "이 파일에 X 가 없다" 같은 부정 단언이 다른 조각의 위반을 조용히 통과시킨다 — B3 검증에서 실측했다:
//   · V0312 `#if DEBUG` 금지가 코어 CheckTokenUsage.swift 만 읽어, 맥에 남긴 CheckTokenUsageRow.swift 에 넣은 `#if DEBUG` 가 초록.
//   · V0246 착용 캐릭터 금지가 맥 MiniGameFlappy.swift 만 읽어, 코어 FlappyGame.swift 에 넣은 `selectedCharacter(` 가 초록.
//   · V0316b nil 필터 금지가 맥 CheckOverlayWindow.swift 만 읽어, 코어 CheckPanelVisibility.swift 에 넣은 위반이 초록.
// 떼기 전(7587c02)에는 셋 다 빨갰다. 도우미에 실행 중 가드를 두지 못하는 까닭은 CheckCoreSourceLayout 머리 주석에 있다(폴더 훑기
// 루프가 같은 도우미로 조각을 하나씩 읽는다). 그래서 **테스트 소스를 훑어** 막는다: 쪼갠 파일 이름이 든 문자열 리터럴은
// `CheckCoreSourceLayout.joinedSplitSource(` 의 바로 그 인자여야 한다. (b3-apply 규칙 스크립트도 같은 검사를 적용 끝에 돌린다.)

/// 한 파일에서 조각 이름을 따로 읽어도 되는 자리(이유를 함께 적는다). 더하기 전에 joinedSplitSource 로 바꿀 수 없는지부터 봐라.
private let splitReadAllowlist: [(file: String, name: String, why: String)] = [
    ("V0325TooltipTests.swift", "CheckTokenUsageRow.swift",
     "폴더 훑기로 만든 '파일 이름 → 주석 제거본' 표에서 조각 파일의 .checkTooltip( 개수 **하한**을 센다 — 양의 단언이라 반쪽이어도 조용히 초록이 되지 않는다"),
    ("V0251MessagePeerTests.swift", "WorkTimerStoreMessages.swift",
     "폴더 훑기 결과(파일 이름 × 호출 수)와 비교하는 **기대값** 글자다 — 읽기가 아니다. 훑기는 두 조각을 각자 이름으로 모두 본다"),
    ("V0331MessageDotTests.swift", "WorkTimerStoreMessages.swift",
     "폴더 훑기의 허용 목록·제외 조건에 쓰는 파일 이름이다 — 읽기가 아니다(읽기는 joinedSplitSource). 훑기는 두 조각을 각자 이름으로 본다"),
    ("V0331MessageDotTests.swift", "MessageRules.swift",
     "같은 허용 목록의 코어 조각 이름(안 읽음 재료를 만지는 판정 규칙 본문) — 읽기가 아니다"),
]

/// 테스트 소스의 문자열 리터럴 하나(주석 밖). `precedingCode` 는 리터럴 바로 앞 코드의 끝 80글자(주석·공백 제외).
private struct SplitReadLiteral {
    let line: Int
    let text: String
    let precedingCode: String
}

/// 주석을 건너뛰며 문자열 리터럴(여러 줄 · raw · 보간 포함)을 뽑는다. 보간 안의 문자열은 바깥 리터럴의 일부로 본다.
private func splitReadLiterals(in source: String) -> [SplitReadLiteral] {
    let s = Array(source.unicodeScalars)
    let n = s.count
    let quote: Unicode.Scalar = "\"", hash: Unicode.Scalar = "#", slash: Unicode.Scalar = "/", star: Unicode.Scalar = "*"
    let backslash: Unicode.Scalar = "\\", newline: Unicode.Scalar = "\n", open: Unicode.Scalar = "(", close: Unicode.Scalar = ")"

    func isRawStart(_ k: Int) -> Bool {
        var j = k
        while j < n, s[j] == hash { j += 1 }
        return j > k && j < n && s[j] == quote
    }
    func skipBlockComment(_ start: Int) -> Int {
        var k = start, depth = 0
        while k + 1 < n {
            if s[k] == slash, s[k + 1] == star { depth += 1; k += 2; continue }
            if s[k] == star, s[k + 1] == slash { depth -= 1; k += 2; if depth == 0 { return k }; continue }
            k += 1
        }
        return n
    }
    func skipLineComment(_ start: Int) -> Int {
        var k = start
        while k < n, s[k] != newline { k += 1 }
        return k
    }
    /// k 는 첫 '#' 또는 '"'. 문자열 끝 다음 위치.
    func scanString(_ start: Int) -> Int {
        var k = start, hashes = 0
        while k < n, s[k] == hash { hashes += 1; k += 1 }
        let multi = k + 2 < n && s[k] == quote && s[k + 1] == quote && s[k + 2] == quote
        k += multi ? 3 : 1
        let quotes = multi ? 3 : 1
        func closesAt(_ p: Int) -> Bool {
            guard p + quotes + hashes <= n else { return false }
            for q in 0..<quotes where s[p + q] != quote { return false }
            for h in 0..<hashes where s[p + quotes + h] != hash { return false }
            return true
        }
        func escapesAt(_ p: Int) -> Bool {
            guard p + 1 + hashes <= n, s[p] == backslash else { return false }
            for h in 0..<hashes where s[p + 1 + h] != hash { return false }
            return true
        }
        while k < n {
            if closesAt(k) { return k + quotes + hashes }
            if escapesAt(k) {
                let j = k + 1 + hashes
                if j < n, s[j] == open { k = scanInterpolation(j + 1); continue }
                k = j + 1
                continue
            }
            if !multi, s[k] == newline { return k }
            k += 1
        }
        return n
    }
    func scanInterpolation(_ start: Int) -> Int {
        var k = start, depth = 1
        while k < n {
            if k + 1 < n, s[k] == slash, s[k + 1] == slash { k = skipLineComment(k); continue }
            if k + 1 < n, s[k] == slash, s[k + 1] == star { k = skipBlockComment(k); continue }
            if s[k] == quote || (s[k] == hash && isRawStart(k)) { k = scanString(k); continue }
            if s[k] == open { depth += 1 } else if s[k] == close {
                depth -= 1
                if depth == 0 { return k + 1 }
            }
            k += 1
        }
        return n
    }

    var out: [SplitReadLiteral] = []
    var recent: [Unicode.Scalar] = []   // 주석·공백을 뺀 최근 코드 글자(리터럴은 자리표시 "…")
    recent.reserveCapacity(256)
    var line = 1
    var i = 0
    func remember(_ c: Unicode.Scalar) {
        recent.append(c)
        if recent.count > 240 { recent.removeFirst(120) }
    }
    while i < n {
        let c = s[i]
        if c == slash, i + 1 < n, s[i + 1] == slash { i = skipLineComment(i); continue }
        if c == slash, i + 1 < n, s[i + 1] == star {
            let end = skipBlockComment(i)
            for k in i..<end where s[k] == newline { line += 1 }
            i = end
            continue
        }
        if c == quote || (c == hash && isRawStart(i)) {
            let end = scanString(i)
            var text = String.UnicodeScalarView()
            text.append(contentsOf: s[i..<end])
            var preceding = String.UnicodeScalarView()
            preceding.append(contentsOf: recent.suffix(80))
            out.append(SplitReadLiteral(line: line, text: String(text), precedingCode: String(preceding)))
            for k in i..<end where s[k] == newline { line += 1 }
            remember(quote); remember("…"); remember(quote)
            i = end
            continue
        }
        if c == newline { line += 1 } else if !c.properties.isWhitespace { remember(c) }
        i += 1
    }
    return out
}

/// 리터럴에 든 쪼갠 파일 이름(앞 글자가 식별자 글자가 아닌 것만 — "WorkTimerStoreMiniGame.swift" 는 "MiniGame.swift" 가 아니다).
private func splitFileNamesMentioned(in literal: String, names: [String]) -> [String] {
    guard literal.contains(".swift") else { return [] }
    return names.filter { name in
        var rest = literal[...]
        while let hit = rest.range(of: name) {
            if hit.lowerBound == literal.startIndex { return true }
            let before = literal[literal.index(before: hit.lowerBound)]
            if !(before.isLetter || before.isNumber || before == "_") { return true }
            rest = literal[hit.upperBound...]
        }
        return false
    }
}

private struct SplitReadScan {
    var violations: [String] = []
    var joinedReads = 0
    var allowlistHits = Set<String>()
}

/// 한 파일을 훑는다. 위반 = 쪼갠 파일 이름이 든 리터럴이 joinedSplitSource( 의 인자가 아니고 허용 목록에도 없다.
private func scanSplitReads(fileName: String, source: String, into scan: inout SplitReadScan) {
    let names = CheckCoreSourceLayout.splitFileNames.sorted()
    for literal in splitReadLiterals(in: source) {
        for name in splitFileNamesMentioned(in: literal.text, names: names) {
            if literal.precedingCode.hasSuffix("joinedSplitSource(") {
                scan.joinedReads += 1
            } else if splitReadAllowlist.contains(where: { $0.file == fileName && $0.name == name }) {
                scan.allowlistHits.insert("\(fileName)|\(name)")
            } else {
                scan.violations.append("\(fileName):\(literal.line) \(literal.text)")
            }
        }
    }
}

private func splitReadViolations(_ source: String, fileName: String = "Probe.swift") -> [String] {
    var scan = SplitReadScan()
    scanSplitReads(fileName: fileName, source: source, into: &scan)
    return scan.violations
}

@Test("쪼갠 파일은 소스 계약 테스트에서 joinedSplitSource 로만 읽는다(반쪽 읽기 금지)")
func splitSourcesAreNeverReadByHalfInSourceContracts() throws {
    let testsDirectory = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Tests/checkTests", isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(atPath: testsDirectory.path)
        .filter { $0.hasSuffix(".swift") }
        // 길잡이 자신(splitParts 표)과 이 파일(자기 시험 조각)은 이름을 적는 것이 일이다.
        .filter { $0 != "CheckCoreSourceLayout.swift" && $0 != "CheckCoreSourceLayoutTests.swift" }
        .sorted()
    #expect(files.count > 100, "테스트 폴더를 못 읽었다(\(files.count)개) — 이 검사가 헛돈다")

    var scan = SplitReadScan()
    for file in files {
        let source = try String(contentsOf: testsDirectory.appendingPathComponent(file), encoding: .utf8)
        scanSplitReads(fileName: file, source: source, into: &scan)
    }
    let violations = scan.violations
    #expect(violations.isEmpty, """
        쪼갠 파일을 이름 하나(또는 글자 그대로의 경로)로 읽는 자리 — CheckCoreSourceLayout.joinedSplitSource("<떼기 전 이름>") 으로 \
        읽어라(반쪽만 읽으면 부정 단언이 다른 조각의 위반을 조용히 통과시킨다):
        \(violations.joined(separator: "\n"))
        """)
    // ★ 기준선이 실제로 다르다: 스캐너가 리터럴을 아예 못 뽑아 초록이 되는 일을 막는다. 반쪽 읽기를 고치기 전에도 이어 읽기가
    //   4곳(V0241 · V0243 · V0246 타이밍 바 · V0246 플래피) 있었다 — 그것조차 못 찾으면 위 "위반 없음"은 헛돈 것이다.
    #expect(scan.joinedReads >= 4, "joinedSplitSource 읽기를 \(scan.joinedReads)곳만 찾았다 — 스캐너가 리터럴을 못 뽑는다")
    // 허용 목록이 낡으면(자리가 사라지면) 지운다 — 쓰이지 않는 예외가 새 반쪽 읽기의 숨을 자리가 되지 않게.
    for entry in splitReadAllowlist {
        #expect(scan.allowlistHits.contains("\(entry.file)|\(entry.name)"), "허용 목록 \(entry.file) · \(entry.name) 자리가 없다 — 목록에서 지워라")
    }
}

@Test("반쪽 읽기 스캐너 자기 시험: 반쪽 읽기는 잡고, 이어 읽기·주석·비슷한 이름은 놓아준다")
func splitReadScannerCatchesHalfReadsAndIgnoresLookAlikes() {
    let halfReads = [
        #"let s = try String(contentsOf: root.appendingPathComponent("Sources/check/MiniGameFlappy.swift"), encoding: .utf8)"#,
        #"let raw = try String(contentsOf: agSourceURL("CheckTokenUsage.swift"), encoding: .utf8)"#,
        #"let c = try code("Sources/CheckCore/FlappyGame.swift")"#,
        "for game in [\"MiniGameTimingBar.swift\", \"X.swift\"] { _ = game }",
        "let s = \"\"\"\n  Sources/check/CheckOverlayWindow.swift\n  \"\"\"",
        ##"let s = #"Sources/check/TodoSync.swift"#"##,
        // 허용 목록은 파일에 묶인다 — 다른 파일에서 같은 조각 이름을 읽으면 잡는다.
        #"let row = sources["CheckTokenUsageRow.swift"]"#,
    ]
    for snippet in halfReads {
        #expect(splitReadViolations(snippet).count == 1, "반쪽 읽기를 못 잡았다: \(snippet)")
    }
    let fine = [
        #"let s = try CheckCoreSourceLayout.joinedSplitSource("MiniGameFlappy.swift")"#,
        "let s = try CheckCoreSourceLayout.joinedSplitSource(\n    \"CheckOverlayWindow.swift\"\n)",
        #"let g = try String(contentsOf: url("WorkTimerStoreMiniGame.swift"), encoding: .utf8)"#,
        #"let t = try String(contentsOf: url("WorkTimerStoreTodoSync.swift"), encoding: .utf8)"#,
        "// 옛날엔 \"Sources/check/MiniGame.swift\" 를 읽었다",
        "/* \"CheckTokenUsage.swift\" /* 겹친 주석 */ */ let x = 1",
        #"let s = "\(dir)/\(name)""#,
    ]
    for snippet in fine {
        #expect(splitReadViolations(snippet).isEmpty, "반쪽 읽기가 아닌데 잡았다: \(snippet)")
    }
    #expect(splitReadViolations(#"let row = sources["CheckTokenUsageRow.swift"]"#, fileName: "V0325TooltipTests.swift").isEmpty,
            "허용 목록 자리를 잡았다")
    // 보간 안의 문자열도 바깥 리터럴의 일부다 — 리터럴 경계를 잃으면 뒤 코드가 통째로 문자열로 먹혀 반쪽 읽기를 놓친다.
    let interpolated = #"let a = "\(f("x"))"; let b = try String(contentsOf: u("CheckOverlayReactions.swift"), encoding: .utf8)"#
    #expect(splitReadViolations(interpolated).count == 1)
}

@Test("쪼갠 파일 표의 조각은 전부 실제로 있고, 떼기 전 이름은 조각 하나의 이름이다")
func splitPartsTablePointsAtRealFiles() {
    for (name, parts) in CheckCoreSourceLayout.splitParts {
        // 둘이 기본이고, SupabaseWorkService.swift 만 셋이다(w16 — 가입의 join_team·create_team 을 게이트 없는 SignUp 조각으로 뗐다).
        let expectedCount = name == "SupabaseWorkService.swift" ? 3 : 2
        #expect(parts.count == expectedCount, "\(name): 조각 \(parts.count)개")
        for part in parts {
            let exists = FileManager.default.fileExists(atPath: CheckCoreSourceLayout.repoRoot.appendingPathComponent(part).path)
            #expect(exists, "\(name) 의 조각 \(part) 가 없다 — joinedSplitSource 가 던진다. 이름이 바뀌었으면 표를 고쳐라")
        }
        #expect(parts.contains { ($0 as NSString).lastPathComponent == name }, "\(name) 이 조각 경로 어디에도 없다")
    }
}
