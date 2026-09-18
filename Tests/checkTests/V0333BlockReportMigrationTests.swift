import Foundation
import Testing
@testable import check
@testable import CheckCore

// 앱스토어 정식 심사 준비(2026-09-18) — **차단·신고 마이그레이션의 소스 계약**.
//
// `20260918180000_blocks_and_reports.sql` 은 애플 심사 지침 1.2(사용자 생성 콘텐츠)가 요구하는 두 가지를 서버에 붙인다:
//   · **차단** — 내가 A 를 차단하면 A 는 나에게 메시지를 못 보내고, A 의 대화가 내 목록에서 사라지고, 오목 신청이 막히고,
//     사람 찾기에서 서로 보이지 않는다. **양방향이다**(한쪽만 막으면 차단이 아니다).
//   · **신고** — 사람 또는 그 사람이 나에게 보낸 메시지 한 건. 사유 4종 + 자유 입력 200자. 같은 대상 24시간 10건.
//     신고하면서 같이 차단할지 고를 수 있다(기본 켬).
//
// 행동은 로컬 Postgres 하네스(replay-harness-v2 · 체인 100개 재생 → 새 파일 3회 연속 적용 → 파일 안 프로브 30건)가 증명했다.
// 여기서 보는 것은 **그 행동을 만드는 문장이 사라지거나 넓어지는 것**이고, 특히 위험한 세 가지다:
//   ① 지금 47명이 쓰는 함수 7개의 **본문을 새로 써서** 그 사이에 들어온 다른 변경(읽음 위치·24시간 보관·숨김 격리 …)을 잃는 것.
//      → 아래 `기존_함수는_정본_본문을_한_줄도_잃지_않았다` 가 정본 파일에서 직접 떠 와 줄 단위로 맞춰 본다.
//   ② 차단 판정을 게이트마다 손으로 다시 적어 **한 방향을 빠뜨리는** 것 → 판정은 `blocked_between` 한 함수만 지나야 한다.
//   ③ 차단 때 **새 status 를 만드는** 것 → 구버전 앱이 모르는 값을 조용히 접어 엉뚱한 문구를 띄운다(숨김 격리와 같은 판단으로
//      'invalid' 를 쓴다).
//
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

// MARK: - 마이그레이션 찾기 · 자르기

private struct BlockContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private let blockMigrationName = "20260918180000_blocks_and_reports.sql"

/// 이 파일이 게이트를 얹는 기존 함수와, 그 함수가 파일 안에서 불리는 이름(헤더 검색용).
private let gatedFunctions: [String] = [
    "send_message", "message_history", "message_unread_summary",
    "app_user_directory", "gomoku_lobby", "gomoku_challenge", "gomoku_respond",
    "poke_user", "ultra_poke_user",
]

/// 숨김 격리(20260917160000)가 **쓰기 경로**로 보고 신원 검사와 같은 if 에서 막은 RPC 를 찾는 표식.
/// 그 파일이 이 한 줄로 막은 함수는 셋이다 — send_message · poke_user · ultra_poke_user.
private let writeGateMarker = "or not public.same_visibility(uid, p_to) then"

/// 숨김 격리의 정본 파일(이 파일이 게이트를 얹는 쓰기 경로의 원천).
private let hiddenAccountsMigrationName = "20260917160000_hidden_accounts.sql"

/// 이 파일이 새로 만드는 RPC 넷(전부 authenticated 전용 · security definer).
private let newRPCs: [(name: String, signature: String)] = [
    ("block_user", "public.block_user(uuid)"),
    ("unblock_user", "public.unblock_user(uuid)"),
    ("list_blocks", "public.list_blocks()"),
    ("report_content", "public.report_content(uuid, text, text, uuid, boolean)"),
]

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫 디렉토리를
/// 잡는다. `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다(V0333DeleteMyAccountMigrationTests 와 같은 방식).
private func blockMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BlockContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var visited: [String] = []
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        visited.append(directory.path)
        directory = directory.deletingLastPathComponent()
    }
    throw BlockContractError(
        "supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", ")). "
            + "워크트리라면 'cp -R /Users/yesung/check/supabase ./supabase' 로 들여오거나 CHECK_MIGRATIONS_DIR 로 알려 줘라."
    )
}

/// `--` 줄 주석을 걷어낸다.
private func stripLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 공백을 한 칸으로 접는다(줄바꿈·들여쓰기와 무관하게 비교하려고).
private func squash(_ sql: String) -> String {
    sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// 주석을 걷어내고 한 줄씩 공백을 접은 **코드 줄 목록**(빈 줄 제외, 소문자).
private func codeLines(_ body: String) -> [String] {
    stripLineComments(body)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { squash(String($0)).lowercased() }
        .filter { !$0.isEmpty }
}

private func migrationFiles() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: try blockMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func blockMigrationSQL() throws -> (raw: String, sql: String) {
    let file = try blockMigrationsDirectory().appendingPathComponent(blockMigrationName)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw BlockContractError("\(blockMigrationName) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    let raw = try String(contentsOf: file, encoding: .utf8)
    return (raw, stripLineComments(raw))
}

/// `create [or replace] function public.<name>(` **마지막** 정의의 본문(달러 인용 사이). 없으면 nil.
private func functionBody(of function: String, in sql: String) -> String? {
    var searchStart = sql.startIndex
    var lastHeader: Range<String.Index>?
    while let found = sql.range(of: "function public.\(function)(", options: .caseInsensitive,
                               range: searchStart..<sql.endIndex) {
        // `comment on function …` · `revoke … on function …` 은 정의가 아니다 — 앞에 create 가 붙은 것만 본다.
        let lineStart = sql[sql.startIndex..<found.lowerBound].lastIndex(of: "\n").map { sql.index(after: $0) } ?? sql.startIndex
        if sql[lineStart..<found.lowerBound].lowercased().contains("create") { lastHeader = found }
        searchStart = found.upperBound
    }
    guard let header = lastHeader else { return nil }
    let after = sql[header.upperBound...]
    // `as $tag$` 의 여는 태그를 찾는다(태그는 파일마다 다르다: $function$ · $$ · $fn$ …).
    guard let asRange = after.range(of: "as $", options: .caseInsensitive) else { return nil }
    let tagStart = after.index(asRange.upperBound, offsetBy: -1)      // '$' 위치
    guard let tagEnd = after[after.index(after: tagStart)...].firstIndex(of: "$") else { return nil }
    let tag = String(after[tagStart...tagEnd])
    let bodyStart = after.index(after: tagEnd)
    guard let close = after.range(of: tag, range: bodyStart..<after.endIndex) else { return nil }
    return String(after[bodyStart..<close.lowerBound])
}

/// 이 파일보다 **앞** 번호의 마이그레이션 중 그 함수를 마지막으로 정의한 파일(= 정본).
private func canonicalSource(of function: String) throws -> (file: URL, body: String) {
    var found: (URL, String)?
    for file in try migrationFiles() where file.lastPathComponent < blockMigrationName {
        let sql = try String(contentsOf: file, encoding: .utf8)
        if let body = functionBody(of: function, in: sql) { found = (file, body) }
    }
    guard let found else { throw BlockContractError("\(function) 의 정본을 못 찾았다 — 앞 마이그레이션에 정의가 없다") }
    return found
}

/// 한 마이그레이션이 정의하는 `public.<이름>` 전부(이름은 중복 없이, 본문은 **그 파일의 마지막 정의**).
/// 이름을 손으로 적지 않고 파일에서 뽑으려고 쓴다 — 손으로 적으면 새로 생긴 쓰기 경로가 목록에 안 들어온다.
private func definedFunctionNames(in sql: String) -> [String] {
    var names: [String] = []
    var seen = Set<String>()
    var searchStart = sql.startIndex
    while let found = sql.range(of: "function public.", options: .caseInsensitive, range: searchStart..<sql.endIndex) {
        searchStart = found.upperBound
        let lineStart = sql[sql.startIndex..<found.lowerBound].lastIndex(of: "\n").map { sql.index(after: $0) } ?? sql.startIndex
        guard sql[lineStart..<found.lowerBound].lowercased().contains("create") else { continue }
        let rest = sql[found.upperBound...]
        guard let paren = rest.firstIndex(of: "(") else { continue }
        let name = String(rest[rest.startIndex..<paren]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(" "), seen.insert(name).inserted else { continue }
        names.append(name)
    }
    return names
}

// MARK: - ① 본문을 새로 쓰지 않았다

/// 정본에는 있었는데 새 정의에서 **사라져도 되는** 줄 — 차단 조건을 끼우느라 두 줄로 갈라진 자리뿐이다.
private let allowedRemovedLines: Set<String> = [
    "or not public.same_visibility(uid, p_to) then",
    "or not public.same_visibility(uid, p_opponent) then",
]

/// 새 정의에만 있는 줄 중 `blocked_between` 을 안 부르면서도 **허용되는** 줄 — 위에서 갈라진 앞쪽 반쪽뿐이다.
private let allowedAddedLines: Set<String> = [
    "or not public.same_visibility(uid, p_to)",
    "or not public.same_visibility(uid, p_opponent)",
]

@Test
func 기존_함수는_정본_본문을_한_줄도_잃지_않았다() throws {
    let (_, sql) = try blockMigrationSQL()
    for function in gatedFunctions {
        guard let newBody = functionBody(of: function, in: sql) else {
            Issue.record("\(function) 을 이 마이그레이션이 다시 정의하지 않는다 — 게이트가 붙을 자리가 없다")
            continue
        }
        let canonical = try canonicalSource(of: function)
        let oldLines = codeLines(canonical.body)
        let newLines = codeLines(newBody)
        #expect(!oldLines.isEmpty, "\(function) 정본 본문이 비었다(\(canonical.file.lastPathComponent))")

        // 사라진 줄: 허용 목록 둘 말고는 하나도 없어야 한다. (본문을 새로 쓰면 여기서 무더기로 걸린다.)
        let removed = oldLines.filter { line in !newLines.contains(line) && !allowedRemovedLines.contains(line) }
        #expect(removed.isEmpty,
                "\(function): 정본(\(canonical.file.lastPathComponent))에 있던 줄이 사라졌다 — 본문을 새로 쓰면 그 사이에 들어온 다른 변경을 잃는다. 사라진 줄: \(removed)")

        // 더해진 줄: 차단 게이트(blocked_between)이거나 갈라진 반쪽뿐이어야 한다. (게이트 김에 딴 걸 끼우면 걸린다.)
        let added = newLines.filter { line in
            !oldLines.contains(line) && !line.contains("blocked_between") && !allowedAddedLines.contains(line)
        }
        #expect(added.isEmpty, "\(function): 차단 게이트와 무관한 줄이 끼어들었다.\n더해진 줄: \(added)")

        #expect(newLines.contains { $0.contains("blocked_between") },
                "\(function) 본문에 차단 게이트(blocked_between)가 없다")
    }
}

@Test
func 허용_목록은_같은_줄의_갈라진_반쪽끼리만_짝이다() {
    // 허용 목록 자체의 자기 검사 — 여기에 아무 줄이나 넣어 위 단언을 무력화하지 못하게.
    #expect(allowedRemovedLines.count == allowedAddedLines.count, "갈라진 줄의 앞뒤 짝이 안 맞는다")
    for removed in allowedRemovedLines {
        #expect(removed.hasSuffix(" then"), "허용된 '사라진 줄'이 조건문 끝(then)이 아니다: \(removed)")
        let head = String(removed.dropLast(" then".count))
        #expect(allowedAddedLines.contains(head), "'\(removed)' 의 앞쪽 반쪽('\(head)')이 허용 목록에 없다")
        #expect(removed.contains("same_visibility"),
                "허용 목록이 same_visibility 말고 다른 게이트 줄까지 덮고 있다: \(removed)")
    }
}

/// 숨김 격리가 **쓰기 경로**로 보고 막은 RPC 는 차단도 같이 막아야 한다.
///
/// 차단의 약속은 '학대하는 사용자와의 상호작용 차단'이다. 메시지만 막고 찌르기를 두면 차단한 사람이
/// 화면을 통째로 덮는 울트라 찌르기를 그대로 받는다 — 게다가 **사람 찾기에서 서로 안 보이는 것은 목록일 뿐**이라
/// 토큰을 쥔 사람은 rpc/ultra_poke_user 를 상대 uuid 로 직접 부를 수 있다. 목록 필터는 차단이 아니고, 게이트가 차단이다.
///
/// 목록을 손으로 적지 않고 **정본 파일에서 뽑는다**: 20260917160000 이 신원 검사와 같은 if 에서 `same_visibility(uid, p_to)`
/// 로 막은 함수 = 그 파일이 '쓰기 경로'로 판정한 집합이다. 거기에 새 쓰기 RPC 가 생기면 이 테스트가 그것도 요구한다.
@Test
func 숨김_격리가_막은_쓰기_경로는_차단도_막는다() throws {
    let (_, sql) = try blockMigrationSQL()
    let hidden = try String(
        contentsOf: try blockMigrationsDirectory().appendingPathComponent(hiddenAccountsMigrationName), encoding: .utf8
    )
    var writePaths: [String] = []
    for name in definedFunctionNames(in: hidden) {
        guard let body = functionBody(of: name, in: hidden) else { continue }
        if codeLines(body).contains(where: { $0.contains(writeGateMarker) }) { writePaths.append(name) }
    }
    #expect(writePaths.count >= 3,
            "정본에서 쓰기 경로를 \(writePaths.count)개밖에 못 찾았다(\(writePaths)) — 표식(\(writeGateMarker))이 낡았다")

    for name in writePaths {
        guard let body = functionBody(of: name, in: sql) else {
            Issue.record("\(name): 숨김 격리가 쓰기 경로로 막은 함수인데 차단 마이그레이션이 다시 정의하지 않는다 — 차단해도 그 길로는 상대에게 닿는다(목록에서 안 보이는 것은 화면일 뿐, 서버는 uuid 로 부르면 받는다)")
            continue
        }
        #expect(codeLines(body).contains { $0.contains("blocked_between") },
                "\(name) 본문에 차단 게이트(blocked_between)가 없다")
    }
}

/// 찌르기의 차단 게이트도 **신원 검사와 같은 if** 에 있어야 한다(블랙아웃이 '신원 검사 직후'라는 기존 계약을 흔들지 않게).
/// 같은 이유로 쿨타임 기록·잔량 차감·장부·초인종보다 앞이라, 차단된 시도가 보낸이의 60초도 루비도 태우지 않는다.
@Test
func 찌르기_차단_게이트는_블랙아웃보다_앞이다() throws {
    let (_, sql) = try blockMigrationSQL()
    for function in ["poke_user", "ultra_poke_user"] {
        guard let body = functionBody(of: function, in: sql) else {
            Issue.record("\(function) 을 이 마이그레이션이 다시 정의하지 않는다"); continue
        }
        let flat = squash(stripLineComments(body)).lowercased()
        guard let gate = flat.range(of: "public.blocked_between(uid, p_to)") else {
            Issue.record("\(function) 에 차단 게이트가 없다"); continue
        }
        guard let blackout = flat.range(of: "public.poke_blackout_active()") else {
            Issue.record("\(function) 에서 블랙아웃 게이트를 못 찾았다 — 정본이 낡았다"); continue
        }
        #expect(gate.lowerBound < blackout.lowerBound,
                "\(function) 의 차단 게이트가 블랙아웃 뒤로 갔다 — 블랙아웃은 신원 검사 **직후**가 계약이다")
        // 쿨타임·잔량·장부보다 앞이라는 것도 같은 한 줄로 보장된다(신원 if 안에 있으면 그 아래 전부보다 앞이다).
        if let insert = flat.range(of: "insert into public.pokes") {
            #expect(gate.lowerBound < insert.lowerBound,
                    "\(function): 차단된 시도가 pokes 행을 남긴다 — 보낸이의 60초 쿨타임이 탄다")
        }
    }
}

@Test
func 이_파일이_고친_아홉_함수의_최종_정의다() throws {
    // 뒤 번호 파일이 다시 정의하면 차단 게이트가 조용히 사라진다(20260917140000 이 그렇게 검사를 지운 전례).
    var laterRedefinitions: [String] = []
    for file in try migrationFiles() where file.lastPathComponent > blockMigrationName {
        let sql = try String(contentsOf: file, encoding: .utf8)
        for function in gatedFunctions where functionBody(of: function, in: sql) != nil {
            laterRedefinitions.append("\(file.lastPathComponent):\(function)")
        }
    }
    #expect(laterRedefinitions.isEmpty,
            "이 파일 뒤에서 다시 정의된 함수가 있다: \(laterRedefinitions). 그 파일에도 차단 게이트를 넣고 이 테스트를 옮겨라.")
}

// MARK: - ② 차단 판정은 한 함수만 지난다

@Test
func 게이트는_user_blocks_를_직접_조회하지_않는다() throws {
    let (_, sql) = try blockMigrationSQL()
    for function in gatedFunctions {
        guard let body = functionBody(of: function, in: sql) else { continue }
        #expect(!stripLineComments(body).lowercased().contains("user_blocks"),
                "\(function) 이 user_blocks 를 직접 읽는다 — 판정은 blocked_between 한 함수만 지나야 한다(손으로 다시 적으면 한 방향을 빠뜨린다: 차단은 양방향이다)")
    }
}

@Test
func 차단_판정_함수는_양방향을_한_문장에서_본다() throws {
    let (_, sql) = try blockMigrationSQL()
    guard let body = functionBody(of: "blocked_between", in: sql) else {
        Issue.record("blocked_between 정의가 없다"); return
    }
    let flat = squash(stripLineComments(body)).lowercased()
    #expect(flat.contains("b.blocker = p_a and b.blocked = p_b"), "a→b 방향 조건이 없다: \(flat)")
    #expect(flat.contains("b.blocker = p_b and b.blocked = p_a"), "b→a 방향 조건이 없다 — 차단이 한 방향뿐이다: \(flat)")
    #expect(flat.contains(" or "), "두 방향이 or 로 묶이지 않았다: \(flat)")
    #expect(flat.hasPrefix("select exists"), "존재 판정이 아니다: \(flat)")
}

@Test
func 차단_판정_함수는_클라가_못_부른다() throws {
    let (_, sql) = try blockMigrationSQL()
    let flat = squash(sql).lowercased()
    #expect(flat.contains("revoke all on function public.blocked_between(uuid, uuid) from public, anon, authenticated"),
            "blocked_between 의 클라 실행권 회수 줄이 없다 — 임의의 두 uuid 의 차단 관계를 캐묻는 통로가 된다")
    #expect(!flat.contains("grant execute on function public.blocked_between"),
            "blocked_between 에 실행권을 주는 줄이 있다 — 내부 전용이어야 한다")
}

// MARK: - ③ 차단은 새 status 를 만들지 않는다

@Test
func 차단_거절은_기존_invalid_어휘를_쓴다() throws {
    let (_, sql) = try blockMigrationSQL()
    for function in ["send_message", "gomoku_challenge", "gomoku_respond", "poke_user", "ultra_poke_user"] {
        guard let body = functionBody(of: function, in: sql) else { continue }
        let flat = squash(stripLineComments(body)).lowercased()
        for invented in ["'blocked'", "'you_are_blocked'", "'target_blocked'", "'block'"] {
            #expect(!flat.contains("'status', \(invented)") && !flat.contains("'status',\(invented)"),
                    "\(function) 이 차단용 새 status(\(invented))를 만든다 — 구버전 앱은 모르는 값을 조용히 접는다. 숨김 격리와 같이 'invalid' 를 써라")
        }
    }
    // send_message 의 차단 게이트는 **신원/invalid 검사와 같은 if** 다(블랙아웃이 '신원 검사 직후'여야 한다는 기존 계약).
    guard let send = functionBody(of: "send_message", in: sql) else { return }
    let flatSend = squash(stripLineComments(send)).lowercased()
    guard let gate = flatSend.range(of: "public.blocked_between(uid, p_to)"),
          let blackout = flatSend.range(of: "public.poke_blackout_active()") else {
        Issue.record("send_message 에서 차단 게이트나 블랙아웃 게이트를 못 찾았다"); return
    }
    #expect(gate.lowerBound < blackout.lowerBound,
            "send_message 의 차단 게이트가 블랙아웃 게이트 뒤로 갔다 — 블랙아웃은 신원 검사 **직후**가 계약이다")
}

// MARK: - ④ 표 둘: 칸 · FK 삭제 규칙 · 권한

@Test
func 새_표의_FK_는_auth_users_로만_가고_삭제_규칙이_정해져_있다() throws {
    let (_, sql) = try blockMigrationSQL()
    let flat = squash(sql).lowercased()
    for column in ["blocker uuid not null references auth.users(id) on delete cascade",
                   "blocked uuid not null references auth.users(id) on delete cascade"] {
        #expect(flat.contains(column), "user_blocks 의 칸 선언이 다르다: \(column)")
    }
    #expect(flat.contains("reporter uuid references auth.users(id) on delete set null"),
            "content_reports.reporter 가 on delete set null 이 아니다 — 계정을 지우면 신고가 함께 사라지거나(cascade) 계정 삭제가 23503 으로 죽는다(not null)")
    #expect(flat.contains("target_user uuid not null references auth.users(id) on delete cascade"),
            "content_reports.target_user 가 on delete cascade 가 아니다 — 20260918120000 §0 의 단언이 배포를 막는다")
    // ★ profiles·messages 로 가는 FK 를 더하면 PostgREST 임베드가 모호해져 기존 조회가 400 이 된다.
    for table in ["references public.profiles", "references public.messages", "references public.teams"] {
        #expect(!flat.contains(table), "새 표가 \(table) FK 를 건다 — PostgREST 임베드가 모호해져 기존 조회가 400 이 된다")
    }
    // message_id 는 FK 가 아니다(메시지는 24시간 뒤 청소된다) — 대신 본문을 스냅숏한다.
    #expect(flat.contains("message_id uuid,"), "content_reports.message_id 선언이 다르다 — FK 없는 plain uuid 여야 한다")
    #expect(flat.contains("message_body text check"), "신고 순간의 메시지 본문 스냅숏 칸이 없다 — 24시간 뒤 신고가 빈칸이 된다")
}

@Test
func 새_표는_RLS_를_켜고_기본_특권을_먼저_회수한다() throws {
    let (_, sql) = try blockMigrationSQL()
    let flat = squash(sql).lowercased()
    for table in ["user_blocks", "content_reports"] {
        #expect(flat.contains("alter table public.\(table) enable row level security"), "\(table) 에 RLS 를 안 켰다")
        #expect(flat.contains("revoke all on table public.\(table) from public, anon, authenticated, service_role"),
                "\(table) 의 기본 특권 회수가 빠졌다 — Supabase default privileges 가 anon 에게 전권을 붙인다")
    }
    // 신고를 넣는 길은 RPC 하나다(24시간 상한·사유 어휘·메시지 벽이 우회되지 않게).
    #expect(flat.contains("grant select on public.content_reports to authenticated"),
            "본인이 낸 신고를 읽는 grant 가 없다")
    #expect(!flat.contains("grant insert on public.content_reports to authenticated")
                && !flat.contains("grant select, insert on public.content_reports to authenticated"),
            "authenticated 에게 content_reports insert 를 줬다 — 넣는 길은 report_content 하나여야 한다")
    for policy in ["users read own blocks", "users insert own blocks", "users delete own blocks", "users read own reports"] {
        #expect(flat.contains("create policy \"\(policy)\""), "정책이 없다: \(policy)")
    }
    #expect(flat.contains("using (blocker = auth.uid())") && flat.contains("with check (blocker = auth.uid())"),
            "차단 정책의 벽이 auth.uid() 가 아니다")
    #expect(flat.contains("using (reporter = auth.uid())"), "신고 읽기 정책의 벽이 auth.uid() 가 아니다")
}

// MARK: - ⑤ 새 RPC 넷

@Test
func 새_RPC_넷은_definer_이고_authenticated_전용이다() throws {
    let (_, sql) = try blockMigrationSQL()
    let flat = squash(sql).lowercased()
    for rpc in newRPCs {
        guard let body = functionBody(of: rpc.name, in: sql) else {
            Issue.record("\(rpc.name) 정의가 없다"); continue
        }
        #expect(!body.isEmpty)
        // 헤더(create … as $tag$ 직전)에 속성이 있다.
        guard let headerStart = sql.range(of: "function public.\(rpc.name)(", options: .caseInsensitive),
              let asRange = sql.range(of: "as $", options: .caseInsensitive, range: headerStart.upperBound..<sql.endIndex) else {
            Issue.record("\(rpc.name) 헤더를 못 읽었다"); continue
        }
        let header = squash(String(sql[headerStart.lowerBound..<asRange.lowerBound])).lowercased()
        #expect(header.contains("security definer"), "\(rpc.name) 이 security definer 가 아니다: \(header)")
        #expect(header.contains("set search_path = public"), "\(rpc.name) 의 search_path 고정이 없다: \(header)")
        #expect(!header.contains("security invoker"), "\(rpc.name) 이 invoker 다: \(header)")

        let signature = rpc.signature.lowercased()
        #expect(flat.contains("revoke all on function \(signature) from public, anon"),
                "\(rpc.name) 의 public·anon 회수 줄이 없다 — Supabase 는 새 함수에 anon 실행권을 딸려 보낸다")
        #expect(flat.contains("grant execute on function \(signature) to authenticated"),
                "\(rpc.name) 을 authenticated 에게 주는 줄이 없다 — 폰이 42501 을 받는다")
        #expect(!flat.contains("grant execute on function \(signature) to anon"), "\(rpc.name) 을 anon 에게 줬다")
    }
    // 사후 단언이 글자가 아니라 카탈로그로 되묻는다.
    #expect(flat.contains("has_function_privilege('anon'"), "anon 차단을 카탈로그로 되묻는 사후 단언이 없다")
    #expect(flat.contains("has_function_privilege('authenticated'"), "authenticated 허용을 되묻는 사후 단언이 없다")
}

@Test
func 신고_RPC_는_폰이_생략하는_인자에_default_를_갖는다() throws {
    // 2026-09-12 미니게임 장애: default 가 떨어지자 PostgREST 가 그 모양의 함수를 못 찾아 PGRST202(404)를 냈다.
    let (_, sql) = try blockMigrationSQL()
    guard let paren = sql.range(of: "function public.report_content(", options: .caseInsensitive),
          let close = sql.range(of: ")", range: paren.upperBound..<sql.endIndex) else {
        Issue.record("report_content 헤더를 못 읽었다"); return
    }
    let args = squash(String(sql[paren.upperBound..<close.lowerBound])).lowercased()
    #expect(args.contains("p_detail text default null"), "p_detail 에 default 가 없다: \(args)")
    #expect(args.contains("p_message_id uuid default null"), "p_message_id 에 default 가 없다: \(args)")
    #expect(args.contains("p_block boolean default true"), "p_block 의 default 가 true 가 아니다 — 신고하면 기본으로 차단한다: \(args)")
    #expect(args.hasPrefix("p_target uuid, p_reason text"), "필수 인자 둘의 자리·타입이 다르다: \(args)")
}

@Test
func 신고는_사유_네_종과_200자_상한과_24시간_10건을_같은_값으로_본다() throws {
    let (_, sql) = try blockMigrationSQL()
    let flat = squash(sql).lowercased()
    #expect(flat.contains("check (reason in ('spam','harassment','inappropriate','other'))"),
            "표 CHECK 의 사유 어휘가 넷이 아니다")
    guard let body = functionBody(of: "report_content", in: sql) else { Issue.record("report_content 가 없다"); return }
    let flatBody = squash(stripLineComments(body)).lowercased()
    #expect(flatBody.contains("p_reason not in ('spam','harassment','inappropriate','other')"),
            "RPC 가 표와 같은 사유 어휘를 못 박지 않는다 — 모르는 값이 CHECK(23514)로 흘러가면 클라가 원인을 못 읽는다")
    #expect(flatBody.contains("public.content_report_detail_max()"), "자유 입력 상한을 상수 함수로 안 본다")
    #expect(flatBody.contains("public.content_report_rate_limit()"), "24시간 상한을 상수 함수로 안 본다")
    #expect(flat.contains("select 200"), "content_report_detail_max() 가 200 이 아니다")
    #expect(flat.contains("select 10"), "content_report_rate_limit() 가 10 이 아니다")
    #expect(flatBody.contains("where reporter = v_uid and target_user = p_target"),
            "상한이 '같은 대상에' 걸리지 않는다(대상을 바꿔 가며 우회되거나, 전역이면 다른 사람 신고까지 막힌다)")
    // 메시지 id 의 벽: 그 사람이 **나에게** 보낸 행만.
    #expect(flatBody.contains("where m.id = p_message_id and m.from_user = p_target and m.to_user = v_uid"),
            "메시지 신고의 벽이 없다 — 남의 대화 메시지를 신고에 실어 읽어 낼 수 있다")
    // 신고와 차단은 한 트랜잭션이다(신고만 남고 차단이 안 걸리는 중간 상태가 없다).
    #expect(flatBody.contains("insert into public.user_blocks (blocker, blocked) values (v_uid, p_target)"),
            "p_block 일 때 같은 함수에서 차단을 걸지 않는다")
}

@Test
func 차단_해제는_내가_건_행만_지운다() throws {
    let (_, sql) = try blockMigrationSQL()
    guard let body = functionBody(of: "unblock_user", in: sql) else { Issue.record("unblock_user 가 없다"); return }
    let flat = squash(stripLineComments(body)).lowercased()
    #expect(flat.contains("delete from public.user_blocks where blocker = v_uid and blocked = p_user"),
            "해제가 '내가 건 행'으로 묶이지 않았다 — 상대가 나를 차단한 행까지 지우면 차단이 무력해진다: \(flat)")
    #expect(!flat.contains("<>") && !flat.contains("!="), "본인 **제외** 조건이 들어갔다: \(flat)")
    guard let list = functionBody(of: "list_blocks", in: sql) else { Issue.record("list_blocks 가 없다"); return }
    #expect(squash(stripLineComments(list)).lowercased().contains("where b.blocker = auth.uid()"),
            "list_blocks 의 벽이 auth.uid() 가 아니다 — 남의 차단 목록 열람 창구가 된다")
}

// MARK: - ⑥ 배포 안전장치

@Test
func 마이그레이션은_적용_직후_자기_결과를_되묻고_삭제_경로를_다시_잰다() throws {
    let (_, sql) = try blockMigrationSQL()
    let flat = squash(sql).lowercased()
    // 남의 수정을 조용히 되돌리지 않는다: 직전 본문 기록 + "직전 + 치환 = 지금" 비교.
    #expect(flat.contains("create table pg_temp.blocks_before"), "직전 본문을 기록하는 임시 표가 없다")
    #expect(flat.contains("create table pg_temp.blocks_expect"), "치환표가 없다")
    #expect(flat.contains("replace(r.src, r.old_txt, r.new_txt) <> v_src"),
            "'새 본문 = 직전 본문 + 이 파일의 치환' 비교가 없다 — 그 사이 누가 고친 것을 조용히 덮어쓴다")
    // 20260918120000 §0 과 같은 폐쇄 검사를 새 표까지 넣고 다시 돈다(그 파일은 번호가 앞이라 새 표를 못 본다).
    #expect(flat.contains("c.confdeltype = 'c'") && flat.contains("c.confdeltype <> 'c'"),
            "계정 삭제 경로의 cascade 폐쇄 검사가 없다")
    #expect(flat.contains("'public.content_reports'::regclass and c.confdeltype = 'n'"),
            "신고함의 set null 을 예외 목록에 적지 않았다 — 그대로면 이 파일이 자기 단언에 걸린다")
    // 프로브는 센티널로 통째 롤백하고, 조용히 no-op 이 되지 않게 건수를 센다.
    #expect(flat.contains("blk_probe_rollback"), "프로브 롤백 센티널이 없다 — 운영에 합성 행이 남는다")
    #expect(flat.contains("if probes <> v_expected then"), "프로브 건수 검사가 없다 — 단언이 조용히 no-op 이어도 초록이 된다")
    #expect(flat.contains("notify pgrst, 'reload schema'"), "PostgREST 스키마 재적재가 없다 — 첫 호출이 PGRST202/404 다")
    // 최상위 begin/commit 은 두지 않는다(같은 파일 3회 적용이 같은 결과여야 한다).
    #expect(!flat.hasPrefix("begin;"), "최상위 begin 이 있다")
}

// MARK: - ⑦ 처리방침이 서버 사실과 어긋나지 않는다

/// `docs/` 가 있는 저장소 뿌리(워크트리·본 저장소 어느 쪽에서 돌려도).
private func repositoryRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("docs/privacy.md").path) {
            return directory
        }
        directory = directory.deletingLastPathComponent()
    }
    throw BlockContractError("docs/privacy.md 를 못 찾았다")
}

/// 신고는 **남의 메시지 본문을 복사해 기한 없이** 들고 있다. 그 사실이 공개 처리방침과 어긋나면 안 된다.
///
/// 처리방침은 1:1 메시지를 "서버가 24시간 뒤 자동 삭제합니다"라고 **단정**한다. 이 마이그레이션이 붙인
/// `content_reports.message_body` 는 신고당한 메시지 본문을 스냅숏해 두고(24시간 청소가 지워도 남게 하려는 것이 목적이다),
/// 지우는 길은 authenticated·service_role 어느 쪽에도 없다. 애플 심사에 그 URL 이 들어가므로 문장이 사실이어야 한다.
@Test
func 처리방침이_신고_본문_스냅숏을_적는다() throws {
    let (_, sql) = try blockMigrationSQL()
    let flat = squash(sql).lowercased()
    // 전제 — 스냅숏이 진짜 있고, 지우는 길이 없다(전제가 사라지면 이 계약도 함께 고쳐야 한다).
    #expect(flat.contains("message_body text"), "content_reports 에 본문 스냅숏 칸이 없다 — 이 계약의 전제가 사라졌다")
    #expect(!flat.contains("grant select, update, delete on public.content_reports"),
            "신고에 DELETE 를 열었다면 '기한 없이 남는다'가 아니다 — 처리방침 문장과 함께 이 테스트를 고쳐라")

    let privacy = try String(contentsOf: try repositoryRoot().appendingPathComponent("docs/privacy.md"), encoding: .utf8)
    let lines = privacy.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    let messageBullet = try #require(lines.first { $0.contains("1:1 메시지(") }, "처리방침에 1:1 메시지 항목이 없다")
    #expect(messageBullet.contains("신고"),
            "처리방침이 1:1 메시지를 '24시간 뒤 자동 삭제'라고 단정하는데 신고 본문 스냅숏(message_body)은 기한 없이 남는다 — 그 예외를 같은 줄에 적어라: \(messageBullet)")

    #expect(lines.contains { $0.contains("신고") && $0.contains("보관 기간") },
            "처리방침의 '수집하는 데이터'에 신고 기록(대상·사유·자유 입력·본문 스냅숏)과 그 보관 기간이 없다 — 제보함 항목과 같은 방식으로 적어라")
    #expect(lines.contains { $0.contains("차단") && $0.contains("본인만") },
            "처리방침에 차단 기록(누구를 언제 차단했는지)이 없다 — 서버가 새로 저장하는 항목이다")

    // 계정 삭제 절: 신고가 어떻게 되는지(내가 낸 것은 익명으로 남고, 내가 신고당한 것은 사라진다)를 적어야 한다.
    let deletionSection = try #require(privacy.range(of: "같이 처리되는 것:"), "계정 삭제 절을 못 찾았다")
    #expect(privacy[deletionSection.upperBound...].contains("신고"),
            "계정 삭제 절이 신고를 안 적는다 — 내가 낸 신고는 작성자 연결만 끊기고(set null) 내가 신고당한 기록은 함께 사라진다(cascade)")
}
