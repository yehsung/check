import Foundation
import Testing

// v0.3.41 — 서버 마이그레이션 계약(20260930120000_gomoku_ranking_watch.sql): 오목 **승점 순위표 · 관전 · 전적 컷**.
//
// 행동은 마이그레이션 자신이 증명한다(§7 사후 단언 · §8 흐름 프로브가 적용 시점에 자기를 되묻고 어긋나면 raise 로 통째 롤백).
// 여기서 보는 것은 **그 문장들이 파일에 실제로 있고, 사라지거나 넓어지지 않았는가**다 — db push 전에, 워크트리가 아니라 메인
// 저장소에서(`supabase/` 는 git 밖이라 워크트리엔 폴더가 없다 — 그때 이 파일은 '파일 없음'으로 빨갛다. C25).
//
// 주석은 걷어내고 본다(C22) — 안 걷어내면 "'insert ' 가 없어야 한다" 같은 단언이 설명 문장을 지워야만 초록이 된다.
// 단 **주석이어야 하는 것**(C3 의 draws desc 뜻풀이)과 **달러 태그 규율**(태그 글자가 주석에 있어도 본문이 끝난다)은 원문으로 본다.
//
// 각 시험의 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가"다.

private let t41Migration = "20260930120000_gomoku_ranking_watch.sql"
private let t41BlocksMigration = "20260918180000_blocks_and_reports.sql"
private let t41PreviousTail = "20260928120000_app_notice.sql"

private struct T41Error: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// V0338 과 같은 방식 — 조상을 훑어 `supabase/migrations` 를 잡고, `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다(뮤테이션 사본용).
private func t41MigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw T41Error("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw T41Error("supabase/migrations 를 못 찾았다(워크트리라면 메인 저장소에서 돌려라 — C25). 훑은 조상: \(visited.joined(separator: ", "))")
}

/// `--` 줄 주석을 걷어낸다. 달러 인용 문자열 안의 `--`(§7 의 `'--[^\n]*'` 패턴)도 같이 잘리므로, 그 줄에 걸리는 단언은 원문으로 둔다.
private func t41Strip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func t41Squash(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func t41Raw(_ name: String) throws -> String {
    let file = try t41MigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw T41Error("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

private func t41SQL() throws -> (raw: String, sql: String) {
    let raw = try t41Raw(t41Migration)
    return (raw, t41Strip(raw))
}

/// `header` 로 시작하는 **마지막** 정의의 달러 인용 본문(태그는 `as $태그$` 를 읽어 그 태그로 닫는다 — `AS $function$` 도 같은 길).
private func t41FunctionBody(_ sql: String, header: String) throws -> String {
    var searchStart = sql.startIndex
    var last: Range<String.Index>?
    while let found = sql.range(of: header, range: searchStart..<sql.endIndex) {
        last = found
        searchStart = found.upperBound
    }
    guard let start = last?.lowerBound else { throw T41Error("함수 헤더가 없다: \(header)") }
    let rest = sql[start...]
    guard let asRange = rest.range(of: "as $", options: .caseInsensitive) else { throw T41Error("\(header): 달러 인용 시작을 못 찾았다") }
    let tagStart = rest.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = rest[rest.index(after: tagStart)...].firstIndex(of: "$") else {
        throw T41Error("\(header): 달러 인용 태그가 안 닫힌다")
    }
    let tag = String(rest[tagStart...tagEnd])
    let bodyStart = rest.index(after: tagEnd)
    guard let close = rest.range(of: tag, range: bodyStart..<rest.endIndex) else {
        throw T41Error("\(header): 달러 인용 종료 태그 \(tag) 가 없다")
    }
    return String(rest[bodyStart..<close.lowerBound])
}

/// 헤더와 `as $` 사이의 속성 줄(returns · language · stable · security definer · set search_path)을 한 줄로.
private func t41Attributes(_ sql: String, header: String) throws -> String {
    guard let start = sql.range(of: header)?.upperBound else { throw T41Error("함수 헤더가 없다: \(header)") }
    let rest = sql[start...]
    guard let asRange = rest.range(of: "as $", options: .caseInsensitive) else { throw T41Error("\(header): as $ 가 없다") }
    return t41Squash(String(rest[rest.startIndex..<asRange.lowerBound])).lowercased()
}

private func t41Count(_ needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchStart = text.startIndex
    while let found = text.range(of: needle, range: searchStart..<text.endIndex) {
        count += 1
        searchStart = found.upperBound
    }
    return count
}

/// `do $tag$ … $tag$;` 블록(원문). 태그가 정확히 2회여야 한다 — 3회면 주석에 태그 글자를 적은 것이다(2026-09-14 app_release 사고).
private func t41Block(_ raw: String, tag: String) throws -> String {
    guard let open = raw.range(of: tag) else { throw T41Error("\(tag) 블록이 없다") }
    guard let close = raw.range(of: tag, range: open.upperBound..<raw.endIndex) else { throw T41Error("\(tag) 가 안 닫힌다") }
    return String(raw[open.upperBound..<close.lowerBound])
}

/// §1 치환표의 두 `$patch$` 본문(old, new) — 원문 그대로(줄 끝 공백까지 바이트로 비교해야 한다).
private func t41Patch(_ raw: String) throws -> (old: String, new: String) {
    var pieces: [String] = []
    var searchStart = raw.startIndex
    var marks: [String.Index] = []
    while let found = raw.range(of: "$patch$", range: searchStart..<raw.endIndex) {
        marks.append(found.lowerBound)
        marks.append(found.upperBound)
        searchStart = found.upperBound
    }
    guard marks.count == 8 else { throw T41Error("$patch$ 가 \(marks.count / 2)회다(기대 4) — 치환표가 두 조각이 아니다") }
    pieces.append(String(raw[marks[1]..<marks[2]]))
    pieces.append(String(raw[marks[5]..<marks[6]]))
    return (pieces[0], pieces[1])
}

private let t41LobbyHeader = "CREATE OR REPLACE FUNCTION public.gomoku_lobby(p_protocol integer DEFAULT 0)"
private let t41EpochHeader = "create or replace function public.gomoku_record_epoch()"
private let t41RecordHeader = "create or replace function public.gomoku__record(p_uid uuid)"
private let t41RankingHeader = "create or replace function public.gomoku_ranking(p_protocol int default 0)"
private let t41WatchHeader =
    "create or replace function public.gomoku_watch(p_protocol int default 0, p_match_id uuid default null, p_since_seq int default 0)"

// MARK: - ① 체인에서의 자리 · 파일 규율

@Test
func 순위_관전_마이그레이션은_정본_뒤에_오고_금지_문장이_없다() throws {
    // 없으면: 앞 번호로 끼워 넣은 파일이 운영에서 순서가 뒤집혀 §1 전제가 죽거나, drop function 한 줄이 로비(gomoku__record 에 의존)를 끊거나,
    // 최상위 commit 이 운영 CLI 의 래퍼 트랜잭션을 깨 반쪽만 적용된 채 남아도 초록이다.
    //
    // ★ 여기 있던 `index == names.count - 1`("내가 체인의 마지막이다")은 **지웠다** — 그건 뜻이 아니라 대리 지표였다.
    //   지키려던 뜻("로비를 또 덮으면 컷이 사라진다")은 아래 ①-b 가 직접 잰다. 파일이 뒤에 생기는 것 자체는 결함이 아니고
    //   (2026-10-05 체스 세 파일), 반대로 뒤에 아무 파일이 없어도 **같은 파일 안에서** 로비를 두 번째로 덮으면 옛 대리는 눈이 멀었다.
    let names = try FileManager.default
        .contentsOfDirectory(at: try t41MigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
    #expect(names.count > 100, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
    let index = try #require(names.firstIndex(of: t41Migration), "\(t41Migration) 이 체인에 없다")
    let previous = try #require(names.firstIndex(of: t41PreviousTail))
    let blocks = try #require(names.firstIndex(of: t41BlocksMigration))
    #expect(previous < index && blocks < index, "정본(blocks)·직전 꼬리(app_notice)보다 뒤여야 한다")

    let (raw, sql) = try t41SQL()
    let lower = sql.lowercased()
    #expect(!lower.contains("drop function"), "drop function 이 있다 — 넷 중 둘은 로비의 일부라 지우면 로비가 죽는다")
    #expect(!lower.contains("reset role"), "RESET ROLE 이 있다 — CLI 링크드 연결은 세션 사용자로 떨어져 42501(메모리: 프로브 RESET ROLE 함정)")
    #expect(lower.contains("execute format('set local role %i', v_exec_role)"), "실행 역할 복귀가 set local role 이 아니다")
    for line in sql.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
        #expect(!["begin;", "commit;", "rollback;", "start transaction;"].contains(line),
                "최상위 트랜잭션 제어 '\(line)' — 운영 CLI 래퍼 트랜잭션을 깬다(하네스 apply_as_cli 는 rc 4)")
    }
    let lastLine = sql.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
    #expect(lastLine == "notify pgrst, 'reload schema';", "파일 끝이 notify pgrst 가 아니다: \(lastLine ?? "")")

    // 달러 태그 규율: 세 블록 태그가 원문에 각 정확히 2회, 블록 안 `--` 주석에 자기 태그 글자가 없다.
    for tag in ["$pre$", "$assert$", "$probe$"] {
        #expect(t41Count(tag, in: raw) == 2, "\(tag) 가 \(t41Count(tag, in: raw))회 — 주석에 태그 글자를 적으면 그 자리에서 본문이 끝난다")
        let block = try t41Block(raw, tag: tag)
        for line in block.split(separator: "\n") {
            if let dash = line.range(of: "--") {
                #expect(!line[dash.upperBound...].contains(tag), "\(tag) 블록 주석에 자기 태그가 있다: \(line)")
            }
        }
    }
    #expect(t41Count("$patch$", in: raw) == 4, "치환표 $patch$ 가 4회가 아니다")
    // 정의 순서: 컷 → 술어 → 로비 → 순위 → 관전(sql 함수 본문은 만들 때 검증된다 — 술어가 컷보다 앞이면 그 자리에서 죽는다).
    let positions = try [t41EpochHeader, t41RecordHeader, t41LobbyHeader, t41RankingHeader, t41WatchHeader].map {
        try #require(sql.range(of: $0)?.lowerBound, "\($0) 없음")
    }
    #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 }, "함수 정의 순서가 컷 → 술어 → 로비 → 순위 → 관전이 아니다")
}

// MARK: - ①-b 내가 만든 함수의 **마지막 정의**가 내 것이다(옛 "내가 체인의 마지막이다" 의 뜻)

/// 걷어낸 SQL 에서 `create [or replace] function public.<이름>(` 로 **정의되는** 이름 전부(등장 순서 · 중복 제거).
/// 이름을 손으로 적지 않고 파일에서 뽑는다 — 손으로 적으면 이 파일에 함수를 더한 사람이 목록을 안 고치고 지나간다.
/// 같은 줄에 `create` 가 있는 것만 센다: `comment on function` · `revoke all on function` 은 정의가 아니고,
/// `execute 'create or replace function public.x(…)'`(동적 정의)는 같은 줄에 create 가 있어 같이 잡힌다.
private func t41DefinedPublicFunctions(in sql: String) -> [String] {
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
        guard !name.isEmpty, !name.contains(where: { $0.isWhitespace }), seen.insert(name).inserted else { continue }
        names.append(name)
    }
    return names
}

/// 그 이름의 **마지막** 정의 본문(달러 인용 사이, 태그는 `as $태그$` 를 읽어 그 태그로 닫는다). 정의가 없으면 nil.
/// 이름으로 찾는다 — 뒤 파일이 쓸 헤더 글자(대소문자 · 인자 DEFAULT 표기)를 우리가 미리 알 수 없다.
private func t41BodyOfFunction(_ name: String, in sql: String) -> String? {
    var searchStart = sql.startIndex
    var last: Range<String.Index>?
    while let found = sql.range(of: "function public.\(name)(", options: .caseInsensitive, range: searchStart..<sql.endIndex) {
        let lineStart = sql[sql.startIndex..<found.lowerBound].lastIndex(of: "\n").map { sql.index(after: $0) } ?? sql.startIndex
        if sql[lineStart..<found.lowerBound].lowercased().contains("create") { last = found }
        searchStart = found.upperBound
    }
    guard let header = last else { return nil }
    let rest = sql[header.upperBound...]
    guard let asRange = rest.range(of: "as $", options: .caseInsensitive) else { return nil }
    let tagStart = rest.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = rest[rest.index(after: tagStart)...].firstIndex(of: "$") else { return nil }
    let tag = String(rest[tagStart...tagEnd])
    let bodyStart = rest.index(after: tagEnd)
    guard let close = rest.range(of: tag, range: bodyStart..<rest.endIndex) else { return nil }
    return String(rest[bodyStart..<close.lowerBound])
}

/// 이 파일이 만드는 함수가 **각자 세운 계약**. 뒤 파일이 그 함수를 다시 만들어도 되지만, 그때 이 토큰들을 재서
/// "컷(과 관전의 읽기 전용)이 살아 있다"를 증명해야 한다 — 허용 목록에 이름만 적는 것은 측정이 아니다.
/// 비교는 **공백 접은 소문자 본문**으로(`insert ` 처럼 뒤 공백까지가 토큰인 것들이 있다).
/// 키 집합이 이 파일이 실제로 만드는 이름 집합과 **정확히** 같아야 한다 — 함수를 더하면 계약도 적어야 한다.
private let t41SurvivalContract: [String: (required: [String], forbidden: [String])] = [
    // 컷 자신: 첫 배포값은 -infinity 상수다. 뒤 파일이 '지금'으로 다시 만들면 전원의 전적이 0 이 된 채 나간다.
    "gomoku_record_epoch": (["'-infinity'::timestamptz"], []),
    // 컷의 **유일한** 소비자: 컷 호출과 finished_at 비교가 둘 다 있어야 한다(한쪽만 남으면 컷이 무음으로 꺼진다).
    "gomoku__record": (["public.gomoku_record_epoch()", "g.finished_at >="], []),
    // 로비 me: 정본 술어 한 줄로 집계한다. 옛 본문(20260918180000:790-795)의 인라인 집계가 돌아오면 그 순간 컷이 사라진다
    // — 정본의 그 6줄에는 finished_at 비교가 **아예 없다**(실측). 컷을 로비에 인라인하는 것도 금지(②와 같은 뜻).
    "gomoku_lobby": (["public.gomoku__record(uid)"], ["count(*) filter (where g.winner = uid)", "finished_at >="]),
    // 순위표: 같은 술어를 lateral 로 부른다(로비 me 와 어긋나지 않게) · 컷은 캡션용으로만 읽고 인라인하지 않는다.
    "gomoku_ranking": (["public.gomoku__record(p.id)"], ["finished_at >="]),
    // 관전: 읽기 전용(④ C2 의 쓰기 넷). 뒤 파일이 '편의상' 한 줄을 끼우는 그 사고가 여기서 걸린다.
    "gomoku_watch": ([], ["insert ", "update ", "delete ", "gomoku__catchup"]),
]

/// 뒤 파일이 **오목 RPC 를 일부러 다시 만드는** 자리. `why` 는 사람이 읽는 근거고, required/forbidden 은 **그 근거가
/// 실제로 성립하는지**를 재는 자다 — "그 둘은 봐준다"로 끝내면 다음 덮어쓰기를 아무도 못 본다.
///
/// 2026-10-05 체스(20261005160000) 가 `gomoku_challenge`·`gomoku_respond` 를 다시 만든다: 지배 문서 B8("한 사람은 한 판만,
/// 반대도")을 지키려고 busy 게이트 네 `exists` 를 `public.chess__busy(...)` 로 바꿨다. 수리 전 실측 — 체스 active 인 a 가
/// 오목 신청을 받아 두 판을 동시에 들고, 체스의 누적 피셔 시계가 오목 두는 동안 흘러 timeout 패로 판돈 2배를 상대에게 줬다.
///
/// **이 덮어쓰기가 컷을 못 지우는 이유는 측정된다**: 두 함수는 전적을 **보고하지 않는다**(정본에도 집계가 0회 — 실측).
/// 그래서 forbidden 에 술어·컷·인라인 집계를 넣는다 — 뒷날 누가 이 둘에 전적을 싣는 순간 "예외가 안전한 이유"가 무너지고
/// 여기서 먼저 빨개진다. required 는 거꾸로 **근거가 아직 거기 있는지**(체스 busy 게이트 · 차단 · 숨김 격리)를 잰다.
private let t41IntendedGomokuRewrites: [String: (why: String, required: [String], forbidden: [String])] = [
    "20261005160000_chess_duel.sql:gomoku_challenge": (
        "B8 반대 방향 — busy 게이트가 체스를 본다(chess_duel §7A.1)",
        ["public.chess__busy(", "public.blocked_between(", "public.same_visibility("],
        ["public.gomoku__record(", "public.gomoku_record_epoch()", "finished_at >=", "count(*) filter (where g.winner"]
    ),
    "20261005160000_chess_duel.sql:gomoku_respond": (
        "B8 반대 방향 — busy 게이트가 체스를 본다(chess_duel §7A.1)",
        ["public.chess__busy(", "public.blocked_between(", "public.same_visibility("],
        ["public.gomoku__record(", "public.gomoku_record_epoch()", "finished_at >=", "count(*) filter (where g.winner"]
    ),
]

@Test
func 뒤_파일은_이_파일이_만든_함수를_다시_만들지_않고_의도된_오목_덮어쓰기는_컷을_안_건드린다() throws {
    // 없으면: 뒤 번호 파일이 gomoku_lobby 를 **옛 본문**(인라인 집계 6줄)으로 다시 만들어 전적 컷이 조용히 사라져도 초록이다.
    // 운영에서 보이는 모습은 "컷을 KST 로 재정의했는데 로비 전적만 안 바뀜" — 순위표와 로비 me 가 영구히 어긋난다.
    let directory = try t41MigrationsDirectory()
    let names = try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
    let index = try #require(names.firstIndex(of: t41Migration), "\(t41Migration) 이 체인에 없다")
    let later = Array(names[(index + 1)...])

    let (_, mySQL) = try t41SQL()
    let mine = t41DefinedPublicFunctions(in: mySQL)
    // 계약표가 이 파일을 따라온다 — 함수를 더하고 계약을 안 적으면 그 함수는 아무도 안 지킨다(검사가 공허해지는 자리).
    #expect(Set(mine) == Set(t41SurvivalContract.keys),
            "이 파일이 만드는 함수 \(mine) 와 생존 계약표 \(t41SurvivalContract.keys.sorted()) 가 다르다 — 더한 함수의 계약을 적어라")
    // 계약이 **지금 이 파일에서** 성립한다(기준선이 틀리면 뒤 파일 판정도 틀린다 — 기준선이 같은 입력이면 그 검사는 영원히 초록).
    for (name, contract) in t41SurvivalContract {
        let body = t41Squash(try #require(t41BodyOfFunction(name, in: mySQL), "\(name) 본문을 못 떴다")).lowercased()
        for token in contract.required { #expect(body.contains(token), "\(name): 이 파일 본문에 '\(token)' 이 없다 — 계약표가 낡았다") }
        for token in contract.forbidden { #expect(!body.contains(token), "\(name): 이 파일 본문에 '\(token)' 이 있다 — 계약표가 낡았다") }
    }

    var seenRewrites: Set<String> = []
    for file in later {
        let sql = t41Strip(try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8))
        for name in t41DefinedPublicFunctions(in: sql) {
            let key = "\(file):\(name)"
            // ㉠ 내가 만든 함수를 뒤에서 다시 만드는 자리 — 계약을 재서 통과시킨다(덮어써도 컷이 살아 있으면 괜찮다).
            if let contract = t41SurvivalContract[name] {
                guard let raw = t41BodyOfFunction(name, in: sql) else {
                    Issue.record("\(key): 다시 만드는데 본문을 못 떴다 — 손으로 봐라"); continue
                }
                let body = t41Squash(raw).lowercased()
                for token in contract.required {
                    #expect(body.contains(token), "\(key): 이 파일이 \(name) 을 다시 만드는데 '\(token)' 이 없다 — 전적 컷이 사라졌다")
                }
                for token in contract.forbidden {
                    #expect(!body.contains(token), "\(key): 다시 만든 \(name) 본문에 '\(token)' 이 있다 — 옛 본문을 베꼈다(컷이 사라진다)")
                }
                continue
            }
            // ㉡ 그 밖의 오목 RPC 를 다시 만드는 자리 — 이름으로 등록하고, 등록한 근거를 측정한다.
            guard name.hasPrefix("gomoku") else { continue }
            guard let rewrite = t41IntendedGomokuRewrites[key] else {
                Issue.record("\(key): 뒤 파일이 오목 RPC 를 다시 만든다 — t41IntendedGomokuRewrites 에 근거와 측정 토큰을 적어라")
                continue
            }
            seenRewrites.insert(key)
            guard let raw = t41BodyOfFunction(name, in: sql) else {
                Issue.record("\(key): 등록된 덮어쓰기인데 본문을 못 떴다 — 측정이 공허하다"); continue
            }
            let body = t41Squash(raw).lowercased()
            for token in rewrite.required {
                #expect(body.contains(token), "\(key)(\(rewrite.why)): '\(token)' 이 없다 — 등록한 근거가 본문에 없다")
            }
            for token in rewrite.forbidden {
                #expect(!body.contains(token),
                        "\(key)(\(rewrite.why)): '\(token)' 이 생겼다 — 전적을 보고하지 않는다는 전제가 깨졌다. 이 덮어쓰기는 이제 컷을 지울 수 있다")
            }
        }
    }
    // 등록해 둔 덮어쓰기가 실제로 없으면 목록이 낡은 것이다(파일 이름을 바꾸고 목록을 안 고치면 측정이 공허하게 초록이 된다).
    #expect(seenRewrites == Set(t41IntendedGomokuRewrites.keys),
            "등록했는데 파일에 없는 덮어쓰기: \(Set(t41IntendedGomokuRewrites.keys).subtracting(seenRewrites)) — 목록을 고쳐라")
}

// MARK: - ② 전적 컷(U5) · 정본 술어

@Test
func 컷은_마이너스_무한대_상수이고_실행권을_거두지_않으며_술어가_유일한_소비자다() throws {
    // 없으면: 첫 배포값이 '지금'이면 전원의 전적이 0 이 된 채 나가고(되돌릴 순 있지만 순위표가 빈 채 첫인상), 컷을 revoke 하면 소유자가 다른
    // definer 가 부를 때 42501(2026-09-13 free_character_id), 프로브가 운영 컷을 재정의하면 그 순간 실사용자 전적이 흔들린다(C5).
    let (raw, sql) = try t41SQL()
    #expect(t41Count(t41EpochHeader, in: sql) == 1, "컷 정의가 \(t41Count(t41EpochHeader, in: sql))회 — 프로브 안에서 재정의하면 안 된다(C5)")
    let epoch = try t41FunctionBody(sql, header: t41EpochHeader)
    #expect(t41Squash(epoch) == "select '-infinity'::timestamptz", "첫 배포값이 -infinity 가 아니다: \(epoch)")
    #expect(try t41Attributes(sql, header: t41EpochHeader) == "returns timestamptz language sql immutable",
            "컷은 immutable · invoker(not security definer) 여야 한다")
    #expect(!sql.contains("revoke all on function public.gomoku_record_epoch"), "컷의 실행권을 거뒀다 — 오목 상수 관용구(PUBLIC 유지)와 다르다")
    let probe = t41Strip(try t41Block(raw, tag: "$probe$"))
    #expect(!probe.contains("gomoku_record_epoch() returns"), "프로브가 운영 컷을 재정의한다(C5) — 로컬 하네스에서만")
    #expect(probe.contains("public.gomoku_record_epoch() <> '-infinity'::timestamptz"), "프로브 뒤 컷 원복 확인이 없다")

    let record = t41Strip(try t41FunctionBody(sql, header: t41RecordHeader))
    for token in ["public.gomoku_record_epoch()", "g.finished_at >=", "g.status = 'finished'", "g.winner = p_uid",
                  "is distinct from p_uid", "g.result = 'draw'", "g.result <> 'draw'", "g.challenger = p_uid or g.opponent = p_uid"] {
        #expect(record.contains(token), "gomoku__record 본문에 '\(token)' 이 없다 — 컷·집계식이 로비 정본(20260918180000:790-795)과 다르다")
    }
    #expect(try t41Attributes(sql, header: t41RecordHeader)
            == "returns table(wins int, losses int, draws int) language sql stable security definer set search_path = public")
    #expect(sql.contains("revoke all on function public.gomoku__record(uuid) from public, anon, authenticated;"),
            "술어가 내부 전용이 아니다 — 임의 uuid 의 전적을 캐묻는 통로가 된다")
    #expect(sql.contains("grant execute on function public.gomoku__record(uuid) to service_role;"))
    // 컷은 술어 한 줄뿐이다 — 로비·순위표 어디에도 finished_at 비교를 인라인하지 않는다(한쪽이 인라인하면 영구히 어긋난다).
    let lobby = t41Strip(try t41FunctionBody(sql, header: t41LobbyHeader))
    let ranking = t41Strip(try t41FunctionBody(sql, header: t41RankingHeader))
    #expect(!lobby.contains("finished_at >=") && !ranking.contains("finished_at >="), "컷을 인라인한 자리가 있다")
    #expect(t41Count("public.gomoku_record_epoch()", in: t41Strip(try t41FunctionBody(sql, header: t41RankingHeader))) == 1,
            "순위표는 record_since_ms 캡션용으로 컷을 한 번만 읽는다")
}

// MARK: - ③ gomoku_lobby = 정본 + 치환 1곳(바이트)

@Test
func 로비_본문은_blocks_정본에_치환_하나를_적용한_것과_바이트까지_같다() throws {
    // 없으면: center 판(gomoku_capable·숨김 격리·차단 게이트가 없는 본문)을 베낀 낡은 로비가 워크트리에서 초록으로 통과해 db push 순간에야
    // §7 (3) 이 멈추거나 — §1 을 안 썼다면 — 조용히 게이트 셋이 사라진다.
    let (raw, sql) = try t41SQL()
    let blocksRaw = try t41Raw(t41BlocksMigration)
    let canonical = try t41FunctionBody(blocksRaw, header: t41LobbyHeader)
    let mine = try t41FunctionBody(raw, header: t41LobbyHeader)
    let patch = try t41Patch(raw)
    #expect(t41Count(patch.old, in: canonical) == 1, "치환할 옛 집계 6줄이 정본에 정확히 1회 있어야 한다(\(t41Count(patch.old, in: canonical))회)")
    #expect(!canonical.contains(patch.new) && mine.contains(patch.new))
    #expect(canonical.replacingOccurrences(of: patch.old, with: patch.new) == mine,
            "새 로비 본문 ≠ 정본 + 치환 — 손으로 옮겼거나 정본이 아닌 판을 베꼈다. 스크립트로 다시 생성해라")
    #expect(t41Squash(patch.new).contains("select r.wins, r.losses, r.draws into v_wins, v_losses, v_draws from public.gomoku__record(uid) r;"))

    // 헤더는 pg_dump 꼴 그대로(대문자 · SET search_path TO 'public') — proconfig 는 'search_path=public' 한 원소로 저장된다.
    #expect(raw.contains(t41LobbyHeader + "\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$"),
            "로비 헤더가 정본(pg_dump 꼴)과 다르다")
    let lobby = t41Strip(mine)
    for token in ["blocked_between", "public.gomoku_capable(p.id)", "gomoku_turn_grace_seconds()", "limit 20", "public.gomoku__record(uid)",
                  "'matches'", "'started_ms'", "least(g.challenger", "greatest(g.challenger", "'in_match'", "'center', p.center", "work_sessions"] {
        #expect(lobby.contains(token), "로비 본문에서 '\(token)' 이 사라졌다 — 낡은 정본을 덮어썼다")
    }
    #expect(t41Count("public.same_visibility(", in: lobby) >= 2, "숨김 격리가 users[]·matches[] 두 자리에 있어야 한다")
    for token in ["'board'", "'turn'", "'move_count'", "g.board", "g.move_count", "make_interval(secs => public.gomoku_turn_seconds()",
                  "count(*) filter (where g.winner = uid)", "gomoku_min_build()", "center ="] {
        #expect(!lobby.contains(token), "로비 본문에 '\(token)' 이 있다 — 판 내용 금지 · 옛 인라인 집계 금지 · 센터 필터 금지")
    }
    // §1 이 직전 본문을 적고 §7 (3) 이 두 갈래(첫 적용 = 직전 + 치환, 재적용 = 치환 결과 존재)로 되묻는다.
    let assertBlock = t41Strip(try t41Block(raw, tag: "$assert$"))
    #expect(sql.contains("create table pg_temp.grw_before as") && sql.contains("create table pg_temp.grw_expect"))
    #expect(assertBlock.contains("if replace(v_before.src, v_old, v_new) <> v_raw then") && assertBlock.contains("elsif position(v_new in v_raw) = 0 then"),
            "로비 '직전 + 치환' 두 갈래 되묻기가 없다")
}

// MARK: - ④ gomoku_watch — 허용 조건(C1) · 금지 문자열 10개(C2)

@Test
func 관전은_진행_중이거나_3분_안에_끝난_판만_열고_쓰기_잠금_채팅_토큰이_없다() throws {
    // 없으면: finished 를 나이 제한 없이 열어 match_id 하나로 30일간 남의 끝난 판을 아카이브처럼 열람하거나, 누가 '편의상' perform gomoku__catchup
    // 한 줄을 넣어 관전자가 남의 판에 자동 착수·정산을 일으켜도(STABLE 은 그것을 막지 못한다 — 실측) 초록이다.
    let (raw, sql) = try t41SQL()
    #expect(try t41Attributes(sql, header: t41WatchHeader) == "returns jsonb language plpgsql stable security definer set search_path = public")
    let watch = t41Squash(t41Strip(try t41FunctionBody(sql, header: t41WatchHeader))).lowercased()
    let allowed = "if not found or not (m.status = 'active' or (m.status = 'finished' and m.finished_at >= clock_timestamp() - interval '3 minutes')) "
        + "or not public.same_visibility(uid, m.challenger) or not public.same_visibility(uid, m.opponent) then return jsonb_build_object('status', 'not_found'); end if;"
    #expect(watch.contains(allowed), "관전 허용 조건이 C1(active 또는 3분 이내 finished, 숨김 격리 두 조건, 그 밖은 not_found)과 다르다")
    #expect(watch.contains("select * into m from public.gomoku_matches g where g.id = p_match_id;"), "판을 읽는 select 에 잠금이 붙었거나 모양이 다르다")
    #expect(watch.contains("mv.seq > greatest(coalesce(p_since_seq, 0), 0)"), "증분(p_since_seq 이후만) 조건이 없다")
    // C2 금지 문자열 10개 + 채팅·시점 의존 키. 'update '·'insert '·'delete ' 는 뒤 공백까지가 토큰이다(deadline_ms 의 'update' 오탐 없이).
    let forbidden = ["gomoku__catchup", "gomoku__settle", "gomoku_ring", "gomoku__chat", "for update", "pg_advisory",
                     "insert ", "update ", "delete ", "realtime.send",
                     "gomoku_chat", "gomoku__state(", "gomoku_move(", "gomoku_resign(", "ultra_wallet:", "blocked_between",
                     "'my_color'", "'ruby_balance'", "'chat'", "'chat_seq'", "'my_muted'", "'opponent_muted'", "'chat_capable'", "'state'"]
    for token in forbidden {
        #expect(!watch.contains(token), "gomoku_watch 본문에 '\(token)' 이 있다")
    }
    for key in ["'id'", "'status'", "'stake'", "'black'", "'white'", "'challenger'", "'opponent'", "'move_count'", "'turn'", "'deadline_ms'",
                "'turn_started_ms'", "'started_ms'", "'result'", "'end_reason'", "'winner'", "'finished_ms'", "'board'",
                "'moves'", "'black_user'", "'white_user'", "'black_auto_streak'", "'white_auto_streak'", "'auto_abandon_streak'"] {
        #expect(watch.contains(key), "gomoku_watch 응답 키 \(key) 가 없다 — 클라 GomokuWatchResponse/GomokuMatchRow 가 읽는 키다")
    }
    #expect(watch.contains("'deadline_ms', case when m.status = 'active'"), "끝난 판의 deadline_ms 가 null 로 접히지 않는다")
    #expect(sql.contains("revoke all on function public.gomoku_watch(integer, uuid, integer) from public, anon;"))
    #expect(sql.contains("grant execute on function public.gomoku_watch(integer, uuid, integer) to authenticated, service_role;"))
    // §7 (6) 이 같은 10개를 배포 시점에 되묻는다 — 여기 목록에서 하나를 빼면 서버 단언도 같이 빠진 것이다.
    let assertBlock = t41Strip(try t41Block(raw, tag: "$assert$"))
    for token in ["gomoku__catchup", "gomoku__settle", "gomoku_ring", "gomoku__chat", "for update", "pg_advisory", "insert ", "update ", "delete ", "realtime.send"] {
        #expect(assertBlock.contains("'\(token)'"), "§7 (6) 의 금지 목록에 '\(token)' 이 없다")
    }
    #expect(assertBlock.contains("to_regprocedure('public.gomoku_watch(integer,uuid,integer)')"), "§7 (6) 이 관전 본문을 읽지 않는다")
    #expect(assertBlock.contains("m.finished_at >= clock_timestamp() - interval ''3 minutes''"), "§7 (6) 이 3분 꼬리를 되묻지 않는다")
    // 흐름 프로브 ⑬: 마감 지난 판을 두 번 관전해도 행 수·xmin 이 그대로(STABLE 이 아니라 이것이 읽기 전용의 증명).
    let probe = t41Strip(try t41Block(raw, tag: "$probe$"))
    #expect(probe.contains("g.xmin::text") && probe.contains("v_xmin2 <> v_xmin"), "프로브 ⑬ 의 xmin 불변 확인이 없다")
    #expect(probe.contains("interval '90 seconds'"), "프로브 ⑬ 이 마감 지난 판을 만들지 않는다")
}

// MARK: - ⑤ gomoku_ranking — 동률 축(C3) · 격리 · 상한

@Test
func 순위표는_승점_승_무_순으로_서고_user_id_로_고정되며_차단은_안_거른다() throws {
    // 없으면: 누가 order by 를 wins desc 먼저로 바꾸거나 blocked_between 을 끼워 '차단한 사람만 빈칸'(차단이 샌다)이 돼도, rank() 가 네 축을 다 봐
    // 동률이 사라져도 초록이다 — 앱의 GomokuRankingOrder 는 서버 규칙을 옮긴 판정이라 서버가 바뀌면 여기서 먼저 보여야 한다.
    let (raw, sql) = try t41SQL()
    #expect(try t41Attributes(sql, header: t41RankingHeader) == "returns jsonb language plpgsql stable security definer set search_path = public")
    let rawBody = try t41FunctionBody(raw, header: t41RankingHeader)
    let ranking = t41Squash(t41Strip(rawBody))
    #expect(ranking.contains("rank() over (order by c.points desc, c.wins desc, c.draws desc) as rnk"), "rank() 축이 points → wins → draws 세 축이 아니다")
    #expect(ranking.contains("order by x.rnk, x.id), '[]'::jsonb)"), "줄 순서의 마지막 축이 user_id 가 아니다(결정성)")
    #expect(ranking.contains("from (select * from ranked order by rnk, id limit 100) x;"), "상한 100·정렬 축이 다르다")
    #expect(ranking.contains("cross join lateral public.gomoku__record(p.id) r"), "순위표가 정본 술어를 안 부른다 — 로비 me 와 어긋난다")
    #expect(ranking.contains("where public.same_visibility(uid, p.id)"), "숨김 격리(나 포함)가 없다")
    #expect(ranking.contains("and (r.wins + r.losses + r.draws) > 0"), "0판 제외가 없다 — 초기화 직후 전원 공동 1위")
    #expect(ranking.contains("(r.wins - r.losses) as points"), "승점 = 승 − 패 가 아니다(U1)")
    #expect(ranking.contains("case when v_epoch = '-infinity'::timestamptz then null else public.gomoku__ms(v_epoch) end"),
            "-infinity 를 null 로 접지 않는다 — gomoku__ms(-inf) 는 floor 에서 죽는다")
    for key in ["'record_since_ms'", "'me'", "'rows'", "'rank'", "'user_id'", "'display_name'", "'avatar_url'", "'character'", "'center'",
                "'wins'", "'losses'", "'draws'", "'points'"] {
        #expect(ranking.contains(key), "gomoku_ranking 응답 키 \(key) 가 없다(U2: 승점과 승·패·무를 같이 싣는다)")
    }
    for token in ["blocked_between", "for update", "pg_advisory", "insert ", "update ", "delete ", "gomoku_chat", "center =", "gomoku_min_build()"] {
        #expect(!ranking.lowercased().contains(token), "gomoku_ranking 본문에 '\(token)' 이 있다")
    }
    // C3: draws desc 의 뜻은 **주석**으로 남긴다 — 실측 (1승 1패 1무) 가 (1승 1패 0무) 앞. 이건 원문에서 본다(걷어내면 없어지는 게 맞다).
    #expect(rawBody.contains("더 많이 둔 쪽이 위"), "draws desc 의 뜻풀이 주석이 없다(C3)")
    #expect(rawBody.contains("(1,1,1)") || rawBody.contains("1승 1패 1무"), "동률 예시가 주석에 없다(C3)")
    #expect(sql.contains("revoke all on function public.gomoku_ranking(integer) from public, anon;"))
    #expect(sql.contains("grant execute on function public.gomoku_ranking(integer) to authenticated, service_role;"))
    // §7 (6) 이 축 순서를 되묻고, ⑨ 가 동률 모양(A < B < D < C = E, F ≥ C + 2)을 합성 갈래에서 잰다.
    let assertBlock = t41Strip(try t41Block(raw, tag: "$assert$"))
    #expect(assertBlock.contains("position('points desc' in v_src) < position('wins desc' in v_src)"), "§7 (6) 축 순서 되묻기가 없다")
    let probe = t41Strip(try t41Block(raw, tag: "$probe$"))
    #expect(probe.contains("v_rk_c = v_rk_e and v_rk_f >= v_rk_c + 2"), "프로브 ⑨ 의 완전 동률·rank() 간격 확인이 없다")
    #expect(probe.contains("array[least(v_c, v_e), greatest(v_c, v_e)]"), "프로브 ⑨ 의 동률 줄 순서(user_id asc) 확인이 없다")
}

// MARK: - ⑥ 사후 단언은 존재 기반(C4) · 프로브 규율(C6·C7)

@Test
func 사후_단언은_함수_수_델타가_아니라_존재로_되묻고_프로브는_pending_없이_부분열만_본다() throws {
    // 없으면: '§0 + 4' 델타 단언이 같은 파일 2회 적용(하네스 멱등 검증)에서 반드시 죽고, 프로브가 pending 행을 넣어 push_outbox 트리거·유니크 인덱스를
    // 건드리거나 rows 를 절대 배열로 비교해 운영에서 확률적으로 db push 가 중단돼도 초록이다.
    let (raw, sql) = try t41SQL()
    let assertBlock = t41Strip(try t41Block(raw, tag: "$assert$"))
    #expect(!assertBlock.contains("+ 4") && !assertBlock.contains("+4"), "함수 수 델타 단언(§0 + 4)이 있다 — 재적용에서 죽는다(C4)")
    #expect(!sql.contains("proname like 'gomoku%'"), "gomoku% 함수 수를 센다 — 존재로 단언해라(C4)")
    for fn in ["'public.gomoku_record_epoch()'", "'public.gomoku__record(uuid)'", "'public.gomoku_ranking(integer)'", "'public.gomoku_watch(integer,uuid,integer)'"] {
        #expect(assertBlock.contains(fn), "§7 존재 단언 목록에 \(fn) 이 없다")
    }
    #expect(assertBlock.contains("if to_regprocedure(r.fn) is null then raise exception '(7) % 가 없다"), "(7) 이 to_regprocedure 존재 단언이 아니다")
    #expect(assertBlock.contains("'p_protocol integer DEFAULT 0, p_match_id uuid DEFAULT NULL::uuid, p_since_seq integer DEFAULT 0'"),
            "관전 시그니처(전 인자 DEFAULT) 단언이 없다 — 하나라도 빠지면 폰의 {} 호출이 PGRST202")

    let probeRaw = try t41Block(raw, tag: "$probe$")
    let probe = t41Strip(probeRaw)
    let marker = try #require(probeRaw.range(of: "v_expected  constant int := "), "v_expected 상수가 없다")
    let expected = try #require(Int(probeRaw[marker.upperBound...].prefix { $0.isNumber }), "v_expected 값을 못 읽었다")
    #expect(t41Count("probes := probes + 1;", in: probe) == expected,
            "probes 증가 \(t41Count("probes := probes + 1;", in: probe))건 ≠ v_expected \(expected) — 프로브 하나가 조용히 no-op")
    #expect(probe.contains("raise exception 'GOMOKU_RECORD_PROBE_ROLLBACK';") && probe.contains("if sqlerrm <> 'GOMOKU_RECORD_PROBE_ROLLBACK' then raise; end if;"),
            "센티널 롤백·재던지기가 없다")
    #expect(probe.contains("if probes <> v_expected then"), "프로브 수 일치 확인이 없다")
    // insert into public. 은 프로브 블록 안에만(밖은 표를 만들지도 채우지도 않는다 — §1 은 pg_temp 뿐).
    let probeRangeInSQL = try #require(sql.range(of: "do $probe$"))
    var searchStart = sql.startIndex
    while let found = sql.range(of: "insert into public.", range: searchStart..<sql.endIndex) {
        #expect(found.lowerBound > probeRangeInSQL.lowerBound, "프로브 밖에 insert into public. 이 있다")
        searchStart = found.upperBound
    }
    #expect(!probe.contains("'pending'"), "프로브가 pending 행을 만든다(C7) — push_outbox 트리거·one_pending_out 유니크와 충돌")
    #expect(probe.contains("where (t.e->>'user_id')::uuid = any (v_gen)"), "프로브 ⑧ 이 픽스처 부분열로 거르지 않는다(C6 — 운영 실사용자 행)")
    #expect(!probe.contains("v_res->'rows' <> jsonb_build_array") && !probe.contains("v_res->'rows' = jsonb_build_array"), "rows 를 절대 배열과 비교한다(C6)")
    #expect(probe.contains("push_outbox"), "프로브 잔여 확인 목록에 push_outbox 가 없다")
    #expect(probe.contains("has_table_privilege('auth.users', 'INSERT')"), "합성/빌림 두 갈래가 없다")
    #expect(probe.contains("turn = null") || probe.contains("turn = null\n"), "⑫ 의 finished update 에 turn = null 이 없다 — CHECK(duel:151) 위반")
}
