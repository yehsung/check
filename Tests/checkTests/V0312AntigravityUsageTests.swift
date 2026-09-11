import Foundation
import SQLite3
import Testing
@testable import check

// MARK: - v0.3.12: 안티그래비티 CLI(agy) 사용량 파서 + 스캐너 회귀 그물
//
// 이 파일이 지키는 것은 넷이다.
//   (a) **구조 파싱** — 태그를 따라 걸어 경로로 값을 집는다. 같은 숫자가 다른 경로에 있어도 줍지 않고,
//       사용량 메시지가 두 곳(1.4 · 1.17.2)에 실려도 한 번만 센다. 값만 긁는 파서는 이 두 테스트에서 죽는다.
//   (b) **증분 규약** — 새 idx 행만 더한다. 앞 행은 나중에 압축돼 다시 써지므로(78KB → 1KB 실측)
//       "파일이 줄었으면 전체 재파싱"(Codex 규칙)을 그대로 가져오면 그 대화가 두 배가 된다.
//   (c) **합계 규약** — total = **네 값 전부**(input + output + thinking + cacheRead). 일별(dayContrib)과 월별이
//       한 정의를 쓴다 — 한쪽만 바꾸면 이 파일이 빨개진다(v0312DailyAndMonthlyShareOneTotalDefinition).
//   (d) **2단 읽기의 사실관계** — 셋을 각각 못 박는다.
//       · `-wal` 이 있으면(0바이트라도) 1단(READONLY)이 읽고 **그 디렉터리에 `-shm` 이 생긴다**
//         → v0312StageOneReadsWalDatabaseAndLeavesOnlyShm
//       · `-wal` 이 아예 없으면 1단이 CANTOPEN 이고 2단(`?immutable=1`)이 구하며 **파일이 하나도 안 생긴다**
//         → v0312ReadsWalDatabaseWithoutSidecars
//       · 디렉터리에 쓸 수 없으면 `-wal` 이 있어도 1단이 CANTOPEN 이고 2단이 구한다
//         → v0312ImmutableFallbackRescuesUnwritableDirectory
//       그리고 **왜 항상 immutable 로 읽지 않는가**: 체크포인트 안 된 `-wal` 의 최신 턴은 1단으로만 보인다
//         → v0312ReadsUncheckpointedWalContent (1단을 immutable 로 바꾸면 이 테스트가 빨개진다)
//
// 합성 바이트열로 (a)(b)(c)(d) 를 전부 덮고, 실제 픽스처가 있으면(이 맥) stdout 실측값과 정확히 대조한다.
// 픽스처가 없는 CI 에서는 실데이터 테스트만 조용히 건너뛴다 — 나머지는 환경과 무관하게 돈다.
//
// ## ⚠️ 규칙 — 실데이터 테스트는 **사본에서만** 읽는다 (임시 디렉터리 밖으로 나가지 않는다)
// 1단(READONLY)이 `-wal` 있는 db 를 읽으면 그 디렉터리에 `-shm` 을 만든다. 그래서 테스트가 사용자의 실제
// `~/.gemini/antigravity-cli/conversations/` 를 sqlite 로 직접 열면 **그 폴더에 파일을 남긴다** —
// 앞 판이 실제로 남겼다: 그 폴더의 `*-shm` 두 개와 0바이트 `-wal` 두 개는 birth 가 전부 2026-09-11 15:52:10~11 이고
// (그 시각 `agy` 로그가 없다) **우리 프로브가 그때 두 db 를 읽기쓰기로 연 잔여**다. `agy` 가 남긴 것이 아니다.
// 그 뒤로도 실폴더를 읽을 때마다 그 `-shm` 들의 mtime 이 갱신됐다(2026-09-11 21:15 실측). 지금은 실데이터 대조를 전부
// `v0312MirrorRealConversations()` 가 만든 임시 사본에서 하고, 각 테스트가 끝날 때
// `v0312ExpectRealConversationsUntouched` 로 실제 폴더의 파일 목록이 그대로인지 확인한다.
// **실제 폴더를 sqlite 로 여는 코드를 다시 넣지 마라.** 복사(`copyItem`)·`stat` 은 파일을 만들지 않으므로 괜찮다.

// MARK: - 합성 protobuf 인코더 (테스트 전용)

private func v0312Varint(_ v: UInt64) -> [UInt8] {
    var out = [UInt8]()
    var x = v
    repeat {
        var byte = UInt8(x & 0x7F)
        x >>= 7
        if x != 0 { byte |= 0x80 }
        out.append(byte)
    } while x != 0
    return out
}

private func v0312Tag(_ field: Int, _ wire: UInt8) -> [UInt8] {
    v0312Varint(UInt64(field) << 3 | UInt64(wire))
}

/// varint 필드(wire 0).
private func v0312Num(_ field: Int, _ value: Int) -> [UInt8] {
    v0312Tag(field, 0) + v0312Varint(UInt64(value))
}

/// 길이 접두 필드(wire 2) — 하위 메시지·문자열 공용.
private func v0312Msg(_ field: Int, _ payload: [UInt8]) -> [UInt8] {
    v0312Tag(field, 2) + v0312Varint(UInt64(payload.count)) + payload
}

private func v0312Str(_ field: Int, _ s: String) -> [UInt8] {
    v0312Msg(field, Array(s.utf8))
}

/// 사용량 메시지 하나(필드 번호는 실측 확정값: 2=input, 3=output, 5=cache_read, 9=thinking).
/// **0 인 필드는 쓰지 않는다** — 실제 블롭이 그렇다(클로드 턴에는 cache_read·thinking 필드가 아예 없었다).
private func v0312Usage(input: Int, output: Int, thinking: Int, cacheRead: Int) -> [UInt8] {
    var out = [UInt8]()
    if input != 0 { out += v0312Num(AntigravityGenMetadataParser.inputTokensField, input) }
    if output != 0 { out += v0312Num(AntigravityGenMetadataParser.outputTokensField, output) }
    if cacheRead != 0 { out += v0312Num(AntigravityGenMetadataParser.cacheReadTokensField, cacheRead) }
    if thinking != 0 { out += v0312Num(AntigravityGenMetadataParser.thinkingTokensField, thinking) }
    return out
}

/// 실제 행의 모양을 흉내 낸 합성 블롭.
/// - primary: `1.4` 에 사용량을 싣는가(실제 행은 항상 싣는다).
/// - mirror: `1.17.2` 에 **같은 값**을 한 번 더 싣는가(실제 행은 항상 싣는다 — 두 배 계상 함정).
/// - decoys: `1.2`(스텝 반복 필드) 안에 같은 숫자를 심는다 — 값만 긁는 파서를 잡는 미끼.
/// - padding: 최상위 필드 8 에 채우는 더미 바이트 수. 압축(행이 작게 다시 써지는 것)을 **크기로** 재현하는 데 쓴다 —
///   같은 크기 블롭으로 갈아 끼우면 파일이 줄지 않아 "축소 = 전체 재파싱 금지" 규약을 아예 시험하지 못한다.
private func v0312Row(
    input: Int, output: Int, thinking: Int = 0, cacheRead: Int = 0,
    model: String? = "gemini-3.8-flash",
    primary: Bool = true, mirror: Bool = true, decoys: [Int] = [], padding: Int = 0
) -> [UInt8] {
    let usage = v0312Usage(input: input, output: output, thinking: thinking, cacheRead: cacheRead)
    var gen = [UInt8]()
    for d in decoys {
        // 1.2.* — 스텝 하나. 실제 블롭도 여기에 토큰과 같은 숫자를 담고 있었다(1.9.10.3.1.5.3 = 13).
        gen += v0312Msg(2, v0312Num(2, d) + v0312Num(4, d) + v0312Str(3, "ok"))
    }
    if primary { gen += v0312Msg(AntigravityGenMetadataParser.usageField, usage) }
    if mirror {
        gen += v0312Msg(
            AntigravityGenMetadataParser.usageMirrorOuterField,
            v0312Msg(AntigravityGenMetadataParser.usageMirrorInnerField, usage) + v0312Str(4, "57397d2f5d0b41a4")
        )
    }
    if let model { gen += v0312Str(AntigravityGenMetadataParser.modelField, model) }
    // 최상위: 실제 행처럼 다른 필드(2·4·8)를 섞어 둔다 — 워커가 그것들을 건너뛰어야 한다.
    var blob = [UInt8]()
    blob += v0312Msg(2, [0x00])
    blob += v0312Str(4, "d89e1c22-942e-4b31-a6a4-277d5952f8c3")
    blob += v0312Msg(8, [UInt8](repeating: 0x7F, count: 16 + max(0, padding)))
    blob += v0312Msg(AntigravityGenMetadataParser.genField, gen)
    return blob
}

// MARK: - (a) 구조 파싱

@Test("합성 행에서 네 갈래 토큰과 모델을 실측 필드 번호대로 읽는다")
func v0312ParsesSynthesizedRow() {
    let row = AntigravityGenMetadataParser.parse(
        v0312Row(input: 5282, output: 1, thinking: 0, cacheRead: 8128, model: "gemini-3.8-flash")
    )
    #expect(row?.input == 5282)
    #expect(row?.output == 1)
    #expect(row?.thinking == 0)
    #expect(row?.cacheRead == 8128)
    #expect(row?.model == "gemini-3.8-flash")
    // 합계 규약: **네 값 전부**. 5282 + 1 + 0 + 8128 = 13411.
    // ★ agy 자신의 total_tokens(5283)와는 일부러 다르다 — 그쪽은 캐시읽기를 빼고, 우리는 서버 순위판 산식과
    //   같은 단위로 맞춘다(antigravity_* 네 컬럼 합, 20260911120000). 두 수를 헷갈리지 마라.
    #expect(row?.total == 13411)
    #expect(row?.total != 5283, "agy stdout 의 total_tokens 정의로 되돌아갔다 — 월 표와 어긋난다")
}

@Test("사용량 메시지가 1.4 와 1.17.2 에 두 번 실려도 한 번만 센다")
func v0312DoesNotDoubleCountMirror() {
    let both = AntigravityGenMetadataParser.parse(v0312Row(input: 15426, output: 13, primary: true, mirror: true))
    #expect(both?.input == 15426)
    #expect(both?.output == 13)
    // 미러를 더하는 파서라면 30852 가 된다. facts.md 가 본 "varint 2회"가 바로 이 미러다.
    #expect(both?.input != 30852)
}

@Test("정본(1.4)이 압축으로 사라져도 미러(1.17.2)로 떨어진다")
func v0312FallsBackToMirror() {
    let mirrorOnly = AntigravityGenMetadataParser.parse(
        v0312Row(input: 15426, output: 13, primary: false, mirror: true)
    )
    #expect(mirrorOnly?.input == 15426)
    #expect(mirrorOnly?.output == 13)
}

@Test("같은 숫자가 다른 경로에 있어도 줍지 않는다")
func v0312IgnoresDecoysOnOtherPaths() {
    // 스텝(1.2.*) 안에 5282·8128 을 심어 두고, 진짜 사용량은 다른 값으로 둔다.
    let row = AntigravityGenMetadataParser.parse(
        v0312Row(input: 777, output: 3, cacheRead: 11, decoys: [5282, 8128])
    )
    #expect(row?.input == 777)
    #expect(row?.output == 3)
    #expect(row?.cacheRead == 11)
    #expect(row?.total == 791)

    // 사용량 메시지가 아예 없으면(미끼만 있으면) 행을 채택하지 않는다 — 미끼로 숫자를 지어내면 안 된다.
    let onlyDecoys = AntigravityGenMetadataParser.parse(
        v0312Row(input: 0, output: 0, primary: false, mirror: false, decoys: [5282, 8128])
    )
    #expect(onlyDecoys == nil)
}

@Test("깨진 바이트열은 부분 채택 없이 통째로 버린다")
func v0312RejectsMalformedBytes() {
    var bytes = v0312Row(input: 5282, output: 1)
    // 꼬리를 잘라 길이 접두가 버퍼를 넘치게 만든다.
    bytes.removeLast(12)
    #expect(AntigravityGenMetadataParser.parse(bytes) == nil)

    // 길이 접두가 남은 바이트보다 큰 필드.
    let overlong = v0312Tag(1, 2) + v0312Varint(9_999)
    #expect(AntigravityGenMetadataParser.parse(overlong) == nil)

    // 필드 번호 0(무효 태그).
    #expect(AntigravityGenMetadataParser.parse([0x00, 0x01]) == nil)

    // 빈 블롭.
    #expect(AntigravityGenMetadataParser.parse([UInt8]()) == nil)
}

@Test("정상성 상한을 넘는 토큰 값이면 그 행을 버린다")
func v0312RejectsInsaneTokenCounts() {
    let sane = AntigravityGenMetadataParser.maxPlausibleTokens
    #expect(AntigravityGenMetadataParser.parse(v0312Row(input: sane, output: 0))?.input == sane)
    // 1억 + 1 → 우리가 남의 필드를 읽고 있다는 뜻이다. 부분 채택하지 않는다.
    #expect(AntigravityGenMetadataParser.parse(v0312Row(input: sane + 1, output: 0)) == nil)
}

@Test("모델 필드는 짧은 인쇄 가능 ASCII 만 받는다 (본문 유출 방벽)")
func v0312ModelIdentifierGate() {
    #expect(AntigravityGenMetadataParser.parse(v0312Row(input: 10, output: 1, model: "claude-sonnet-4-6"))?.model
            == "claude-sonnet-4-6")
    // 개행이 섞인 텍스트 = 본문 조각. 모델로 받지 않는다(행 자체는 살아 있다).
    let withNewline = AntigravityGenMetadataParser.parse(v0312Row(input: 10, output: 1, model: "안녕\n오늘 회의록"))
    #expect(withNewline?.input == 10)
    #expect(withNewline?.model == nil)
    // 64바이트 초과.
    let long = String(repeating: "a", count: AntigravityGenMetadataParser.maxModelIdentifierBytes + 1)
    #expect(AntigravityGenMetadataParser.parse(v0312Row(input: 10, output: 1, model: long))?.model == nil)
    // 모델 필드가 없어도 토큰은 읽힌다.
    #expect(AntigravityGenMetadataParser.parse(v0312Row(input: 10, output: 1, model: nil))?.model == nil)
}

// MARK: - 합성 sqlite 대화 파일

private let v0312SQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// gen_metadata 표만 있는 최소 대화 db 를 만든다(실제 스키마와 같은 컬럼).
///
/// - walMode: 실제 대화 db 처럼 **WAL 모드**로 만들고, 다 쓴 뒤 `-wal`·`-shm` 을 지운다.
///   `agy` 가 정상 종료하면 sqlite 가 마지막 연결에서 사이드카를 지우므로 **이것이 사용자 맥의 정상 상태**다
///   (헤더 18~19바이트는 02 02 로 남는다). 그 db 는 읽기 전용으로 열 수 없어 2단(immutable)이 필요하다.
/// - vacuum: 쓰기 뒤 `vacuum` 을 돌려 **파일을 실제로 줄인다**. sqlite 는 행이 작아져도 페이지를 반납하지 않아
///   vacuum 없이는 파일 크기가 그대로다 — 그러면 "축소 = 전체 재파싱 금지" 규약을 시험할 수 없다.
private func v0312WriteConversation(
    at url: URL, rows: [(idx: Int, data: [UInt8])], mtime: Date,
    walMode: Bool = false, vacuum: Bool = false
) {
    var db: OpaquePointer?
    #expect(url.path.withCString {
        sqlite3_open_v2($0, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    } == SQLITE_OK)
    if walMode { sqlite3_exec(db, "pragma journal_mode=wal", nil, nil, nil) }
    sqlite3_exec(
        db,
        "create table if not exists gen_metadata (`idx` integer, `data` blob, `size` integer not null default 0, primary key (`idx`))",
        nil, nil, nil
    )
    for r in rows {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "insert or replace into gen_metadata (idx, data, size) values (?, ?, ?)", -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, Int64(r.idx))
        r.data.withUnsafeBytes { buf in
            _ = sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count), v0312SQLiteTransient)
        }
        sqlite3_bind_int64(stmt, 3, Int64(r.data.count))
        #expect(sqlite3_step(stmt) == SQLITE_DONE)
        sqlite3_finalize(stmt)
    }
    if vacuum { sqlite3_exec(db, "vacuum", nil, nil, nil) }
    if walMode { sqlite3_exec(db, "pragma wal_checkpoint(TRUNCATE)", nil, nil, nil) }
    sqlite3_close(db)
    if walMode {
        // 정상 종료한 `agy` 의 상태를 그대로 만든다. (sqlite 가 스스로 지우기도 하지만 빌드/버전에 기대지 않는다.)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }
    // mtime 은 db 를 닫은 뒤에 찍는다 — sqlite 가 마지막 flush 로 다시 건드리면 우리가 정한 시각이 날아간다.
    try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
}

/// 파일 크기(바이트). 축소 규약 테스트가 "정말 줄었는가"를 재는 데 쓴다.
private func v0312FileSize(_ url: URL) -> Int {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.size] as? Int) ?? -1
}

/// sqlite 헤더 18~19바이트(= 파일 포맷 읽기/쓰기 버전). `02 02` 가 WAL 모드다.
private func v0312JournalHeader(_ url: URL) -> [UInt8] {
    guard let data = try? Data(contentsOf: url), data.count > 19 else { return [] }
    return [data[18], data[19]]
}

private func v0312HasSidecars(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path + "-wal")
        || FileManager.default.fileExists(atPath: url.path + "-shm")
}

/// 스캐너의 상태 키는 디렉터리 순회가 돌려준 경로다. 임시 디렉터리(`/var/folders/...`)는 `/private` 심볼릭 링크라
/// 우리가 만든 URL 과 문자열이 다를 수 있다 — 테스트는 파일 이름으로 찾는다(프로덕션의 홈 경로에는 없는 문제다).
private func v0312State(_ states: [String: AntigravityFileProgress], _ name: String) -> AntigravityFileProgress? {
    states.first { ($0.key as NSString).lastPathComponent == name }?.value
}

private func v0312TempConversations() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("v0312-agy-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(AntigravityUsageScanner.conversationsSubpath, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// 열려 있는 db 핸들에 한 행을 쓴다. **쓰기 연결을 열어 둔 채로** 커밋해 `agy` 가 돌고 있는 상태를 재현하는
/// 테스트가 쓴다(그 상태에서만 최신 턴이 `-wal` 안에만 있다).
private func v0312InsertRow(_ db: OpaquePointer?, idx: Int, data: [UInt8]) {
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, "insert or replace into gen_metadata (idx, data, size) values (?, ?, ?)", -1, &stmt, nil)
    sqlite3_bind_int64(stmt, 1, Int64(idx))
    data.withUnsafeBytes { buf in
        _ = sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count), v0312SQLiteTransient)
    }
    sqlite3_bind_int64(stmt, 3, Int64(data.count))
    #expect(sqlite3_step(stmt) == SQLITE_DONE)
    sqlite3_finalize(stmt)
}

/// `?immutable=1` **로만** 열어 본 최대 idx. "항상 immutable 로 읽으면 무엇을 놓치는가"를 재는 자리에만 쓴다.
/// 실패는 음수로 돌려준다(단언 메시지에 그대로 실린다).
private func v0312MaxIdxViaImmutable(_ url: URL) -> Int {
    var db: OpaquePointer?
    let uri = AntigravityConversationReader.immutableURI(path: url.path)
    guard uri.withCString({ sqlite3_open_v2($0, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) }) == SQLITE_OK,
          let handle = db
    else { if db != nil { sqlite3_close(db) }; return -2 }
    defer { sqlite3_close(handle) }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, "select coalesce(max(idx), -1) from gen_metadata", -1, &stmt, nil) == SQLITE_OK,
          let query = stmt
    else { if stmt != nil { sqlite3_finalize(stmt) }; return -3 }
    defer { sqlite3_finalize(query) }
    return sqlite3_step(query) == SQLITE_ROW ? Int(sqlite3_column_int64(query, 0)) : -4
}

/// 디렉터리의 파일 이름 목록(정렬). "아무 파일도 안 생겼다"를 `-wal`·`-shm` 두 이름이 아니라
/// **목록 전체**로 재는 데 쓴다 — sqlite 가 `-journal` 같은 다른 이름을 남겨도 잡힌다.
private func v0312DirectoryListing(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
}

/// 디렉터리의 **지문**: 이름 + 크기 + mtime. 실제 폴더 감시에만 쓴다.
/// 이름만 보면 놓치는 경우가 있다 — 사용자 폴더에는 이미 `-shm` 이 있고(앞 판 테스트가 남겼다),
/// 그 파일을 다시 읽으면 **이름은 그대로인데 `-shm` 의 mtime 이 바뀐다**(실측: 같은 db 를 두 번 읽으면
/// -shm mtime 이 1.2초 차이로 갱신됐다). 그래서 크기·mtime 까지 본다.
private func v0312DirectoryFingerprint(_ url: URL) -> [String] {
    let fm = FileManager.default
    return ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted().map { name in
        let a = try? fm.attributesOfItem(atPath: url.appendingPathComponent(name).path)
        let size = (a?[.size] as? Int) ?? -1
        let mtime = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "\(name)|\(size)|\(mtime)"
    }
}

/// 사용자의 **실제** 대화 디렉터리. 여기는 `stat`·`copyItem` 말고는 아무것도 하지 않는다(머리말 §규칙).
private var v0312RealConversations: URL {
    AntigravityUsageScanner.conversationsDirectory(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
}

/// 실제 대화 디렉터리의 **사본**을 임시 폴더에 만든다. `.db` 와 (있으면) `-wal` 만 가져온다 —
/// `-shm` 은 `-wal` 에서 재계산되는 파생 파일이라 sqlite 가 사본 옆에 새로 만든다(그게 이 사본의 요점이기도 하다:
/// `-shm` 이 **사용자 폴더가 아니라 임시 폴더에** 생긴다).
///
/// 돌려주는 `realBefore` 는 복사 직전에 찍은 실제 폴더의 **지문**(이름+크기+mtime)이다. 테스트는 끝에서
/// `v0312ExpectRealConversationsUntouched` 로 그것과 비교한다. `dbNames` 는 실제로 사본에 실린 대화 db 이름들이다.
///
/// nil 은 **"이 기기엔 잴 것이 없다"** 하나만 뜻한다(디렉터리가 없거나 `.db` 가 하나도 없다 — CI). 그 외에는
/// 사본이 비지 않았음을 여기서 단언한다: 사본이 비면 호출자의 루프가 한 바퀴도 안 돌아 **아무것도 안 재고 초록**이 되고,
/// 그게 이번에 잡힌 결함이다(복사가 조용히 실패해도 세 테스트가 전부 통과했다).
private func v0312MirrorRealConversations() -> (dir: URL, realBefore: [String], dbNames: [String])? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: v0312RealConversations.path) else { return nil }
    let dbNames = v0312DirectoryListing(v0312RealConversations).filter { $0.hasSuffix(".db") }
    guard !dbNames.isEmpty else { return nil }
    let before = v0312DirectoryFingerprint(v0312RealConversations)
    let mirror = v0312TempConversations()
    for name in dbNames {
        try? fm.copyItem(
            at: v0312RealConversations.appendingPathComponent(name),
            to: mirror.appendingPathComponent(name)
        )
        let wal = name + "-wal"
        guard fm.fileExists(atPath: v0312RealConversations.appendingPathComponent(wal).path) else { continue }
        try? fm.copyItem(
            at: v0312RealConversations.appendingPathComponent(wal),
            to: mirror.appendingPathComponent(wal)
        )
    }
    #expect(v0312DirectoryListing(mirror).filter { $0.hasSuffix(".db") } == dbNames,
            "사본에 대화 db 가 덜 실렸다 — 아래 단언들이 아무것도 재지 않고 초록이 된다: \(v0312DirectoryListing(mirror))")
    return (mirror, before, dbNames)
}

/// 실제 폴더에 **지금 있는** 픽스처 이름들(`stat` 만 한다 — 머리말 §규칙). 비어 있으면 이 기기엔 실측 픽스처가
/// 없다는 뜻이고 실데이터 테스트는 조용히 지나간다. 비어 있지 않으면 그 수만큼을 **실제로 읽었는지** 단언한다 —
/// 그래야 사본이 비었을 때 무측정 초록이 되지 않는다.
private func v0312PresentFixtureNames() -> [String] {
    let listing = Set(v0312DirectoryListing(v0312RealConversations))
    return v0312Fixtures.keys.filter { listing.contains($0) }.sorted()
}

/// ★ 이번 수리의 핵심 단언. 실데이터 테스트가 사용자의 실제 폴더에 파일을 만들거나 지우지 않았는지 확인한다.
/// 이 줄이 빨개지면 어딘가가 실제 폴더를 sqlite 로 열었다는 뜻이다(머리말 §규칙).
private func v0312ExpectRealConversationsUntouched(_ before: [String], _ label: String) {
    let after = v0312DirectoryFingerprint(v0312RealConversations)
    #expect(after == before, """
        \(label): 사용자의 실제 conversations/ 가 바뀌었다(이름·크기·mtime).
        before=\(before)
        after =\(after)
        테스트는 사본(v0312MirrorRealConversations)에서만 읽어야 한다 — 머리말 §규칙.
        (테스트를 돌리는 동안 `agy` 가 실제로 돌고 있었다면 이 줄이 그 때문일 수도 있다. 그 경우만 예외다.)
        """)
}

/// KST 2026-09-11 15:40 = UTC 06:40. 자정에서 멀어 ±몇 시간을 흔들어도 일자가 안 바뀐다.
private let v0312Now = Date(timeIntervalSince1970: 1_789_108_800)
private let v0312Day = "2026-09-11"
private let v0312Month = "2026-09"

// MARK: - (b) 증분 규약

@Test("새 idx 행만 더한다 — 앞 행이 압축돼 파일이 **줄어도** 재계상하지 않는다")
func v0312IncrementalCountsOnlyNewRows() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-a.db")
    let first = v0312Now.addingTimeInterval(-600)
    // idx0 을 실측처럼 크게 쓴다(78KB). 이 크기가 있어야 다음 쓰기에서 **파일이 실제로 줄고**,
    // 그래야 "축소 = 전체 재파싱"(Codex 규칙)을 잘못 들여왔을 때 이 테스트가 잡는다.
    v0312WriteConversation(at: file, rows: [
        (0, v0312Row(input: 15426, output: 13, model: "claude-sonnet-4-6", padding: 78_000)),
        (1, v0312Row(input: 5567, output: 67, thinking: 66, cacheRead: 8126, model: "gemini-3.8-flash")),
    ], mtime: first, vacuum: true)
    let sizeBefore = v0312FileSize(file)

    var states: [String: AntigravityFileProgress] = [:]
    let r1 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r1.totals.input == 15426 + 5567)
    #expect(r1.totals.output == 13 + 67)
    #expect(r1.totals.thinking == 66)
    #expect(r1.totals.cacheRead == 8126)
    #expect(r1.stats.rowsIngested == 2)
    #expect(v0312State(states, file.lastPathComponent)?.lastIdx == 1)

    // 다시 스캔 — 아무것도 안 변했으면 파일을 열지도 않고 합계도 그대로다.
    let r2 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r2.totals == r1.totals)
    #expect(r2.stats.filesRead == 0)
    #expect(r2.stats.rowsIngested == 0)

    // 실제 CLI 가 하는 일: idx0 을 **작게 다시 쓰고**(압축, 실측 78,206B → 1,067B) idx2 를 덧붙인다.
    v0312WriteConversation(at: file, rows: [
        (0, v0312Row(input: 15426, output: 13, model: "claude-sonnet-4-6")),
        (2, v0312Row(input: 100, output: 7, model: "gemini-3.8-flash")),
    ], mtime: v0312Now, vacuum: true)
    let sizeAfter = v0312FileSize(file)
    // ★ 전제 확인. 파일이 실제로 줄지 않았다면 아래 기대는 아무것도 시험하지 못한다 —
    //   초판이 같은 크기 블롭으로 갈아 끼우는 바람에 이 규약이 검증 없이 통과했다(검토자 지적).
    #expect(sizeAfter < sizeBefore, "축소를 못 만들었다: \(sizeBefore) → \(sizeAfter)")

    let r3 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r3.stats.rowsIngested == 1, "줄어든 파일을 전체 재파싱했다 — 이미 센 행이 두 번 들어간다")
    #expect(r3.totals.input == 15426 + 5567 + 100)
    #expect(r3.totals.output == 13 + 67 + 7)
    #expect(v0312State(states, file.lastPathComponent)?.lastIdx == 2)
    // 재계상이 일어났다면 입력이 15426 만큼 더 커졌을 것이다.
    #expect(r3.totals.input != 15426 * 2 + 5567 + 100)
    // 파일 크기·mtime 은 그대로 상태에 찍힌다(축소를 '못 읽은 파일'로 오해해 매번 다시 열지 않는다).
    #expect(v0312State(states, file.lastPathComponent)?.size == sizeAfter)
    let r4 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r4.stats.filesRead == 0)
}

@Test("한 스캔 상한에 걸리면 다음 스캔이 이어읽는다 — 무변경 스킵에 묶이지 않는다")
func v0312ResumesAfterRowLimit() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-many.db")
    v0312WriteConversation(
        at: file,
        rows: (0..<5).map { (idx: $0, data: v0312Row(input: 100, output: 10)) },
        mtime: v0312Now
    )

    // 상한을 2로 낮춰 이어읽기를 싸게 재현한다(프로덕션 상한은 1024).
    var states: [String: AntigravityFileProgress] = [:]
    let r1 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now, rowLimit: 2)
    #expect(r1.stats.rowsIngested == 2)
    #expect(v0312State(states, file.lastPathComponent)?.lastIdx == 1)

    // 파일은 한 바이트도 안 변했다. 여기서 '무변경 스킵'에 걸리면 남은 세 행은 다음 쓰기 전까지 영영 안 읽힌다.
    let r2 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now, rowLimit: 2)
    #expect(r2.stats.rowsIngested == 2)
    let r3 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now, rowLimit: 2)
    #expect(r3.stats.rowsIngested == 1)
    #expect(r3.totals.input == 500)
    #expect(r3.totals.output == 50)
    #expect(v0312State(states, file.lastPathComponent)?.lastIdx == 4)

    // 다 읽은 뒤에는 무변경 스킵이 다시 산다(매 스캔 전량 재순회 방지).
    let r4 = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now, rowLimit: 2)
    #expect(r4.stats.filesRead == 0)
    #expect(r4.totals == r3.totals)

    // 리더 단독 계약: 상한에 딱 걸리면 truncated 가 선다.
    let full = AntigravityConversationReader.read(path: file.path, afterIdx: -1, limit: 5)
    #expect(full.truncated)
    #expect(full.rows.count == 5)
    let partial = AntigravityConversationReader.read(path: file.path, afterIdx: 3, limit: 5)
    #expect(!partial.truncated)
    #expect(partial.rows.count == 1)
}

@Test("KST 일별 맵과 모델 맵을 만든다 — 셋 다 같은 네 값 정의로 쌓는다")
func v0312BuildsDailyAndModelMaps() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-b.db")
    v0312WriteConversation(at: file, rows: [
        (0, v0312Row(input: 100, output: 10, thinking: 5, cacheRead: 9_000, model: "claude-sonnet-4-6")),
        (1, v0312Row(input: 200, output: 20, model: "gemini-3.8-flash")),
    ], mtime: v0312Now)

    var states: [String: AntigravityFileProgress] = [:]
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r.totals.daily[v0312Day] == 9_115 + 220)
    #expect(r.totals.total == 9_335)
    #expect(r.totals.cacheRead == 9_000)
    #expect(r.totals.models["claude-sonnet-4-6"] == 9_115)
    #expect(r.totals.models["gemini-3.8-flash"] == 220)
    // 일별 합 == 월 total(같은 달 안이면 항등식이다).
    #expect(r.totals.daily.values.reduce(0, +) == r.totals.total)
}

/// ★ **일별과 월별은 한 정의를 쓴다** — 네 값 전부(캐시읽기 포함). 초판은 일별만 세 값이라 실측에서 38% 작았다
/// (26,422 vs 42,676). 잔디를 붙이는 날 그 차이가 그대로 화면에 나온다.
/// 이 테스트는 **한쪽만 고치면 빨개진다**: ①은 행의 정의를, ②③④⑤는 그 정의가 월·일·파일상태·모델맵에
/// 똑같이 흐르는지를 각각 따로 못 박는다. 캐시읽기가 나머지 셋보다 큰 행을 써서 정의가 갈리면 값이 크게 벌어지게 했다.
@Test("일별 정의와 월별 정의는 같아야 한다 — 한쪽만 바꾸면 빨개진다")
func v0312DailyAndMonthlyShareOneTotalDefinition() {
    // ① 행의 합계 규약 자체.
    #expect(AntigravityGenRow(input: 1, output: 2, thinking: 4, cacheRead: 8).total == 15,
            "행의 total 에서 캐시읽기가 빠졌다 — 월 정의(서버 네 컬럼 합)와 갈린다")

    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-def.db")
    v0312WriteConversation(at: file, rows: [
        // 실측 모양(입력 5,282 · 캐시읽기 8,128) — 캐시가 입력보다 크다.
        (0, v0312Row(input: 5_282, output: 1, cacheRead: 8_128, model: "gemini-3.8-flash")),
        (1, v0312Row(input: 100, output: 10, thinking: 5, cacheRead: 9_000, model: "claude-sonnet-4-6")),
    ], mtime: v0312Now)

    var states: [String: AntigravityFileProgress] = [:]
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)

    // ② 월 합계 = 네 값.
    #expect(r.totals.total == r.totals.input + r.totals.output + r.totals.thinking + r.totals.cacheRead)
    #expect(r.totals.total == 22_526)
    // ③ 일별 합 == 월 합계. 한쪽만 세 값이면 17,128 만큼 어긋난다(= 캐시읽기 합).
    #expect(r.totals.daily.values.reduce(0, +) == r.totals.total)
    #expect(r.totals.daily[v0312Day] == 22_526)
    // ④ 파일 상태(캐시에 저장됐다 복원되는 값)도 같은 정의.
    let state = v0312State(states, file.lastPathComponent)
    #expect(state?.monthTotal == r.totals.total)
    #expect(state?.dayContrib.values.reduce(0, +) == state?.monthTotal)
    // ⑤ 모델 맵도 같은 정의(도구 믹스가 다른 단위로 그려지면 캡션이 총합과 어긋난다).
    #expect(r.totals.models.values.reduce(0, +) == r.totals.total)
    #expect(r.totals.models["gemini-3.8-flash"] == 13_411)
}

@Test("월이 바뀌면 기여분만 비우고 lastIdx 는 지킨다")
func v0312MonthRolloverKeepsLastIdx() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-c.db")
    v0312WriteConversation(at: file, rows: [(0, v0312Row(input: 1_000, output: 100))], mtime: v0312Now)

    var states: [String: AntigravityFileProgress] = [:]
    _ = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(v0312State(states, file.lastPathComponent)?.monthKey == v0312Month)
    #expect(v0312State(states, file.lastPathComponent)?.lastIdx == 0)

    // 한 달 뒤: 같은 파일을 한 번 더 건드린다(mtime 만 갱신, 새 행 없음).
    let nextMonth = v0312Now.addingTimeInterval(30 * 24 * 3_600)
    try? FileManager.default.setAttributes([.modificationDate: nextMonth], ofItemAtPath: file.path)
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: nextMonth)
    // 지난달 기여는 사라지고, 이미 센 idx0 은 다시 세지 않는다 → 0.
    #expect(r.totals.total == 0)
    #expect(v0312State(states, file.lastPathComponent)?.lastIdx == 0)
    #expect(v0312State(states, file.lastPathComponent)?.monthKey == TokenUsageIncrementalScanner.kstMonthString(nextMonth))
}

@Test("이번 달 이전 mtime 파일은 열지도 않는다 (월 창 규약)")
func v0312MonthWindowPrefilter() {
    let dir = v0312TempConversations()
    let old = dir.appendingPathComponent("conv-old.db")
    v0312WriteConversation(
        at: old, rows: [(0, v0312Row(input: 9_999, output: 9))],
        mtime: v0312Now.addingTimeInterval(-45 * 24 * 3_600)
    )
    var states: [String: AntigravityFileProgress] = [:]
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r.stats.filesStatted == 0)
    #expect(r.totals.total == 0)
    #expect(states.isEmpty)
}

// MARK: - (d) 사이드카 없는 WAL db (v0.3.12 P0)

/// ★ **`agy` 가 정상 종료하면 `-wal`·`-shm` 을 지운다.** 그 db 는 헤더가 여전히 WAL(02 02)인데 공유 메모리 인덱스가
/// 없다. 읽기 전용 연결이 `-shm` 을 만들지 **않는 것은 이 경우뿐**이다(`-wal` 이 있으면 만든다 —
/// v0312StageOneReadsWalDatabaseAndLeavesOnlyShm 이 그쪽을 잰다).
/// 실측(2026-09-11, 이 맥에서 `agy -p` 한 번으로 만든 새 대화 26bdd50a…): `sqlite3_open_v2` 는 성공하고
/// `sqlite3_prepare_v2` 가 SQLITE_CANTOPEN(14) 으로 죽었다.
///
/// 이게 **깨끗한 사용자 맥의 정상 경로**다 — 고치기 전에는 그런 사람의 안티그래비티 집계가 통째로 0 이었다.
/// (개발 맥에서 안 보인 이유: `agy` 를 띄워 둬서가 아니라 **우리 프로브가 두 db 를 읽기쓰기로 열어** 사이드카를
///  남겨 놨기 때문이다 — 머리말 §규칙의 15:52 잔여. 그 뒤 `agy` 가 새로 만든 두 대화에는 사이드카가 없다.)
///
/// 여기서 같이 재는 것: **2단 읽기는 파일을 하나도 만들지 않는다.** `-wal`·`-shm` 두 이름이 아니라
/// 디렉터리 **목록 전체**를 전후로 비교한다 — sqlite 가 `-journal` 같은 다른 이름을 남겨도 잡힌다.
@Test("사이드카 없는 WAL db 를 읽는다 — agy 정상 종료 뒤의 정상 상태 · 파일을 하나도 안 만든다")
func v0312ReadsWalDatabaseWithoutSidecars() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-wal.db")
    // 실측 새 대화(26bdd50a…)의 stdout 값: 4924 / 113 / 112 / 8127.
    v0312WriteConversation(
        at: file,
        rows: [(0, v0312Row(input: 4_924, output: 113, thinking: 112, cacheRead: 8_127))],
        mtime: v0312Now, walMode: true
    )

    // 전제 확인 — 이게 아니면 이 테스트는 아무것도 재지 않는다.
    #expect(v0312JournalHeader(file) == [0x02, 0x02], "WAL 헤더가 아니다 — 재현이 안 됐다")
    #expect(!v0312HasSidecars(file), "사이드카가 남아 있다 — 재현이 안 됐다")

    let sizeBefore = v0312FileSize(file)
    let mtimeBefore = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    let listingBefore = v0312DirectoryListing(dir)

    let read = AntigravityConversationReader.read(path: file.path, afterIdx: -1)
    #expect(read.outcome == .ok, "사이드카 없는 WAL db 를 못 읽었다 — 깨끗한 사용자 맥의 집계가 통째로 0 이 된다")
    #expect(read.usedImmutableFallback, "1단으로 읽혔다면 이 테스트가 재현하려던 상태가 아니다")
    #expect(read.rows.count == 1)
    #expect(read.rows.first?.row.total == 4_924 + 113 + 112 + 8_127)

    // ★ `-wal` 이 없으면 우리는 파일을 하나도 만들지 않는다. 이름 둘이 아니라 목록 전체로 잰다.
    #expect(v0312DirectoryListing(dir) == listingBefore,
            "사이드카 없는 db 를 읽었는데 디렉터리에 파일이 생겼다: \(v0312DirectoryListing(dir)) vs \(listingBefore)")
    #expect(!v0312HasSidecars(file), "우리가 -wal/-shm 을 만들었다 — 남의 파일을 건드린 것이다")
    #expect(v0312FileSize(file) == sizeBefore)
    #expect((try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) == mtimeBefore)

    // 스캐너까지 같은 값이 흐르고, 계측이 "2단으로 구했다"를 남긴다.
    var states: [String: AntigravityFileProgress] = [:]
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r.totals.total == 13_276)
    #expect(r.stats.immutableReads == 1)
    #expect(r.stats.openFailures == 0)
    #expect(r.stats.queryFailures == 0)
    #expect(r.stats.filesRead == 1)
}

/// ★ **`-wal` 이 있으면 1단이 읽는다 — 그리고 그 대가로 `-shm` 이 생긴다.**
/// 이것이 이번 수리의 정정 사항이다. 앞 판 주석과 보고는 "읽기 전용이라 사용자 파일을 하나도 만들지 않는다"고
/// 적었지만 거짓이었다: 읽기 전용 연결이 `-shm` 을 못 만드는 것은 **`-wal` 이 아예 없을 때뿐**이고,
/// `-wal` 이 있으면 디렉터리 쓰기 권한만으로 `-shm` 을 만든다. 그 사실을 여기서 **합성 db 로** 재현한다 —
/// 실폴더의 사이드카를 증거로 들지 않는 이유는 머리말 §규칙에 적었다(그 0바이트 `-wal` 들은 `agy` 상태가 아니라
/// 우리 프로브가 15:52 에 남긴 잔여다).
///
/// 그래도 **동작은 이대로가 맞다**: `-shm` 은 `-wal` 에서 재계산되는 파생 파일이고 `.db` 본체는 안 바뀐다.
/// 반대로 항상 immutable 로 열면 체크포인트 안 된 최신 턴을 놓친다(v0312ReadsUncheckpointedWalContent).
/// 여기서 재는 것: (1) 1단으로 읽힌다 · (2) 생기는 파일은 `-shm` **하나뿐**이다 · (3) `.db` 는 그대로다.
@Test("`-wal` 이 있으면 1단으로 읽고, 생기는 파일은 `-shm` 하나뿐이다")
func v0312StageOneReadsWalDatabaseAndLeavesOnlyShm() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-wal-left.db")
    v0312WriteConversation(
        at: file, rows: [(0, v0312Row(input: 500, output: 5))], mtime: v0312Now, walMode: true
    )
    // 재현할 모양: 0바이트 `-wal` 만 있고 `-shm` 은 아직 없다 — 1단이 `-shm` 을 **새로 만드는** 순간을 재려면
    // 이 출발점이어야 한다. (실폴더에도 0바이트 `-wal` 두 개가 있지만 그건 `agy` 상태가 아니라 우리 프로브가
    //  15:52 에 남긴 잔여이고 옆에 `-shm` 까지 이미 있다 — 머리말 §규칙. 그래서 증거는 여기서 합성해 만든다.)
    #expect(FileManager.default.createFile(atPath: file.path + "-wal", contents: Data()))
    #expect(!FileManager.default.fileExists(atPath: file.path + "-shm"), "재현이 안 됐다 — -shm 이 이미 있다")

    let sizeBefore = v0312FileSize(file)
    let mtimeBefore = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date

    let read = AntigravityConversationReader.read(path: file.path, afterIdx: -1)
    #expect(read.outcome == .ok)
    #expect(!read.usedImmutableFallback, "-wal 이 있는데 1단이 못 열었다 — 최신 턴을 놓치는 경로로 떨어졌다")
    #expect(read.rows.first?.row.total == 505)

    // (2) 새로 생긴 파일은 `-shm` 하나뿐이다. 거짓이던 주석을 여기서 사실로 못 박는다.
    #expect(FileManager.default.fileExists(atPath: file.path + "-shm"), """
        -wal 이 있는데 -shm 이 안 생겼다. sqlite 동작이 바뀐 것이므로
        AntigravityConversationReader 의 §사이드카의 사실관계 표를 다시 재고 고쳐라.
        """)
    #expect(v0312DirectoryListing(dir).sorted()
        == [file.lastPathComponent, file.lastPathComponent + "-shm", file.lastPathComponent + "-wal"].sorted(),
        "예상 밖의 파일이 생겼다: \(v0312DirectoryListing(dir))")

    // (3) `.db` 본체는 한 바이트도 안 바뀐다 — 이게 '건드리지 않는다'의 진짜 내용이다.
    #expect(v0312FileSize(file) == sizeBefore, ".db 크기가 바뀌었다")
    #expect((try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) == mtimeBefore,
            ".db mtime 이 바뀌었다")
}

/// ★ **왜 항상 immutable 로 읽지 않는가 — 체크포인트 안 된 최신 턴을 통째로 놓친다.**
/// `agy` 가 돌고 있는 동안 마지막 턴은 `.db` 가 아니라 `-wal` 안에만 있다. `?immutable=1` 은 `-wal` 을 아예 읽지
/// 않으므로 그 턴이 안 보이고, 대화가 끝나면(다음 쓰기가 없으면) **영영 안 잡힌다**.
/// 이 테스트가 1단 우선 순서의 근거다: 1단을 immutable 로 바꾸면 여기가 빨개진다.
@Test("체크포인트 안 된 `-wal` 의 최신 턴까지 읽는다 — 항상 immutable 이면 그 턴을 놓친다")
func v0312ReadsUncheckpointedWalContent() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-live.db")

    // `agy` 가 지금 돌고 있는 상태: 쓰기 연결을 **열어 둔 채로** 최신 턴을 커밋한다.
    var db: OpaquePointer?
    #expect(file.path.withCString {
        sqlite3_open_v2($0, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    } == SQLITE_OK)
    defer { sqlite3_close(db) }
    sqlite3_exec(db, "pragma journal_mode=wal", nil, nil, nil)
    // 자동 체크포인트를 끊어야 최신 행이 `-wal` 에 남는다(안 끊으면 sqlite 가 알아서 `.db` 로 내려버린다).
    sqlite3_exec(db, "pragma wal_autocheckpoint=0", nil, nil, nil)
    sqlite3_exec(
        db,
        "create table if not exists gen_metadata (`idx` integer, `data` blob, `size` integer not null default 0, primary key (`idx`))",
        nil, nil, nil
    )
    v0312InsertRow(db, idx: 0, data: v0312Row(input: 1_000, output: 10))
    sqlite3_exec(db, "pragma wal_checkpoint(TRUNCATE)", nil, nil, nil)   // idx0 은 `.db` 로 내려간다
    v0312InsertRow(db, idx: 1, data: v0312Row(input: 2_000, output: 20)) // idx1 은 `-wal` 에만 남는다

    // 전제 확인 — 최신 행이 정말 `-wal` 안에만 있는가.
    #expect(FileManager.default.fileExists(atPath: file.path + "-shm"), "쓰기 연결이 있는데 -shm 이 없다")
    #expect(v0312MaxIdxViaImmutable(file) == 0, """
        immutable 로 최신 행이 보였다 — 이 테스트가 재현하려던 상태가 아니다
        (본 최대 idx: \(v0312MaxIdxViaImmutable(file))).
        """)

    // 1단은 `-wal` 까지 본다 → 두 행 전부.
    let read = AntigravityConversationReader.read(path: file.path, afterIdx: -1)
    #expect(read.outcome == .ok)
    #expect(!read.usedImmutableFallback, "1단이 못 열었다 — 사이드카가 다 있는데 2단으로 떨어졌다")
    #expect(read.rows.count == 2, "체크포인트 안 된 최신 턴을 놓쳤다 — 항상 immutable 로 읽으면 이렇게 된다")
    #expect(read.maxIdx == 1)
    #expect(read.rows.reduce(0) { $0 + $1.row.total } == 1_010 + 2_020)
}

/// ★ **디렉터리에 쓸 수 없으면 `-wal` 이 있어도 1단이 CANTOPEN 이고, 2단이 구한다.**
/// `-shm` 을 만들 수 없기 때문이다(권한 0500 인 대화 폴더 실측). 이 경로에서는 우리가 파일을 만들 **수 없다**는
/// 것도 같이 증명된다 — 목록이 전후로 같다.
@Test("쓸 수 없는 디렉터리에서도 2단이 구한다 — 그 경로에선 파일을 만들 수도 없다")
func v0312ImmutableFallbackRescuesUnwritableDirectory() throws {
    let fm = FileManager.default
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-locked.db")
    v0312WriteConversation(
        at: file, rows: [(0, v0312Row(input: 900, output: 90, thinking: 9, cacheRead: 1))],
        mtime: v0312Now, walMode: true
    )
    // `-wal` 이 있으니 **쓸 수 있는** 디렉터리라면 1단이 읽었을 파일이다(그 대조는 위 테스트가 한다).
    #expect(fm.createFile(atPath: file.path + "-wal", contents: Data()))

    try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }

    // root 로 돌리면 권한이 무의미하다 — 그때는 이 테스트가 재는 게 없으니 조용히 지나간다.
    let canary = dir.appendingPathComponent("canary.tmp")
    if fm.createFile(atPath: canary.path, contents: Data()) {
        try? fm.removeItem(at: canary)
        return
    }

    let listingBefore = v0312DirectoryListing(dir)
    let read = AntigravityConversationReader.read(path: file.path, afterIdx: -1)
    #expect(read.outcome == .ok, "쓸 수 없는 디렉터리에서 2단이 구하지 못했다 — 그 사람 집계가 통째로 0 이 된다")
    #expect(read.usedImmutableFallback, "1단이 읽었다 = -shm 을 만들 수 있었다는 뜻이라 재현이 안 됐다")
    #expect(read.rows.first?.row.total == 1_000)
    #expect(v0312DirectoryListing(dir) == listingBefore, "쓸 수 없는 디렉터리에 파일이 생겼다(있을 수 없는 일이다)")
}

/// 2단(immutable)은 잠금을 아예 쓰지 않는다 — 그래서 읽는 사이에 `agy` 가 끼어들면 찢긴 값을 읽을 수 있다.
/// 그 위험을 막는 것이 **크기·mtime 울타리**이고, 울타리가 깨지면 읽은 값을 **통째로** 버린다(부분 채택 없음 —
/// 찢긴 블롭은 파서가 거를 수도, 못 거를 수도 있다). 못 읽은 것은 손실이 아니라 지연이다: 다음 스캔이 다시 잡는다.
@Test("2단으로 읽는 사이에 파일이 바뀌면 그 읽기를 통째로 버린다")
func v0312ImmutableReadDiscardsWhatChangedUnderIt() {
    let dir = v0312TempConversations()
    let file = dir.appendingPathComponent("conv-race.db")
    v0312WriteConversation(
        at: file, rows: [(0, v0312Row(input: 1_000, output: 100))], mtime: v0312Now, walMode: true
    )

    // 울타리가 온전하면 정상적으로 읽힌다(대조 축 — 아래 빨강이 울타리 때문임을 보이려면 이 줄이 필요하다).
    let calm = AntigravityConversationReader.read(path: file.path, afterIdx: -1)
    #expect(calm.outcome == .ok)

    // 읽는 사이에 누가 파일을 건드렸다.
    let raced = AntigravityConversationReader.read(path: file.path, afterIdx: -1) {
        try? FileManager.default.setAttributes(
            [.modificationDate: v0312Now.addingTimeInterval(1)], ofItemAtPath: file.path
        )
    }
    #expect(raced.outcome == .changedDuringRead)
    #expect(raced.rows.isEmpty, "찢겼을 수 있는 값을 부분 채택했다")
    #expect(raced.maxIdx == -1, "진행 상태를 전진시키면 그 행을 영영 다시 안 읽는다")

    // 스캐너는 그 파일의 상태를 건드리지 않고 '열기 실패' 칸에 센다 → 다음 스캔이 다시 잡는다.
    var states: [String: AntigravityFileProgress] = [:]
    let again = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(again.totals.total == 1_100, "울타리가 정상 경로까지 막았다")
}

/// 2단은 경로를 URI 로 바꿔 연다 — 그래서 **경로에 뭐가 들어 있든** 견뎌야 한다.
/// 한글 사용자 이름은 흔하고, `?` 나 `#` 이 든 폴더도 macOS 에선 합법이다. 이스케이프가 새면
/// `?` 뒤가 쿼리로 잘리거나 `#` 뒤가 통째로 날아가 그 사람만 집계가 0 이 된다.
@Test("2단 경로 이스케이프 — 한글·공백·물음표·샵이 든 경로에서도 읽는다")
func v0312ImmutableFallbackSurvivesAwkwardPaths() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("v0312 예성 #1 ?q-\(UUID().uuidString)", isDirectory: true)
    let dir = base.appendingPathComponent(AntigravityUsageScanner.conversationsSubpath, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let file = dir.appendingPathComponent("conv-awkward.db")
    v0312WriteConversation(
        at: file, rows: [(0, v0312Row(input: 700, output: 70, thinking: 7, cacheRead: 3))],
        mtime: v0312Now, walMode: true
    )
    #expect(!v0312HasSidecars(file))

    // URI 에 원문 문자가 그대로 새어 나가지 않는다(이 단언이 인코딩 자체를 못 박는다).
    let uri = AntigravityConversationReader.immutableURI(path: file.path)
    #expect(uri.hasSuffix("?immutable=1"))
    #expect(!uri.dropLast("?immutable=1".count).contains("?"), "경로의 ? 가 안 감싸졌다 — 쿼리가 잘린다")
    #expect(!uri.contains("#"), "경로의 # 이 안 감싸졌다 — 뒤가 통째로 날아간다")
    #expect(!uri.contains("예성"), "비ASCII 가 그대로 실렸다")

    let read = AntigravityConversationReader.read(path: file.path, afterIdx: -1)
    #expect(read.outcome == .ok, "괴상한 경로에서 2단이 실패했다")
    #expect(read.rows.first?.row.total == 780)
}

/// 열기 실패와 질의 실패는 처방이 다르다 — 앞은 재시도로 풀리고 뒤는 안 풀린다. 그래서 갈라 센다.
/// (사이드카 없는 WAL 이 1단 `prepare` 에서 CANTOPEN 으로 죽는 것은 **실패가 아니라 2단으로 가는 신호**다.
///  그 경로는 v0312ReadsWalDatabaseWithoutSidecars 가, 2단까지 실패하는 경로는
///  v0312OpenFailuresStandWhenBothStagesFail 이 잰다.)
@Test("열기 실패와 질의 실패를 갈라 센다")
func v0312SeparatesOpenFailuresFromQueryFailures() {
    // (1) 없는 파일 = 열기 실패. 2단으로 내려가 봐야 마찬가지라 outcome 은 .openFailed 다.
    let missing = AntigravityConversationReader.read(path: "/nonexistent/dir/none.db", afterIdx: -1)
    #expect(missing.outcome == .openFailed)

    // (2) 표가 없는 남의 db = 질의 실패. CANTOPEN 이 아니므로 2단으로 떨어지지도 않는다(같은 실패를 두 번 하지 않는다).
    let dir = v0312TempConversations()
    let foreign = dir.appendingPathComponent("not-a-conversation.db")
    var db: OpaquePointer?
    _ = foreign.path.withCString { sqlite3_open_v2($0, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) }
    sqlite3_exec(db, "create table other (a integer)", nil, nil, nil)
    sqlite3_close(db)
    try? FileManager.default.setAttributes([.modificationDate: v0312Now], ofItemAtPath: foreign.path)

    let read = AntigravityConversationReader.read(path: foreign.path, afterIdx: -1)
    #expect(read.outcome == .queryFailed)
    #expect(!read.usedImmutableFallback)

    // (3) 스캐너 계측이 둘을 다른 칸에 센다.
    var states: [String: AntigravityFileProgress] = [:]
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r.stats.queryFailures == 1)
    #expect(r.stats.openFailures == 0)
    #expect(r.stats.readFailures == 1)
    #expect(r.totals.isEmpty)
}

/// ★ **2단까지 못 열면 `openFailures` 에 선다** — 집계만 조용히 0 이 되는 길이 없어야 한다.
/// v0.3.12 의 P0 은 "통째로 못 읽는데 계측이 전부 0"이었다. 그 재발을 막는 그물이 이 테스트다.
///
/// 앞 판은 `prepare` 의 CANTOPEN 을 `.openFailed` 로 가르는 분기로 이걸 지키려 했는데, 그 분기는 **되돌려도
/// 아무 테스트가 안 빨개졌다**(뮤테이션 M2 생존). 이유가 있었다 — 그 값은 호출자에게 도달하지 않는다:
///   · 1단의 CANTOPEN 은 `read` 가 `code` 를 보고 2단으로 내려가므로 `outcome` 이 버려진다.
///   · 2단(immutable)의 `prepare` 는 CANTOPEN 을 내지 않는다. 열기 실패는 전부 `sqlite3_open_v2` 에서 14 로
///     떨어지고(없는 경로 · 권한 000 파일 · 경로가 디렉터리), `prepare` 가 실패하는 경우는 26(NOTADB) ·
///     11(CORRUPT) · 1(표 없음)뿐이었다(2026-09-11, 열 가지 입력 실측).
/// 그래서 그 분기를 지우고(`AntigravityConversationReader.attempt` 주석) **검증할 수 있는 자리**만 남겼다:
/// 열기 실패는 `openRC` 에서 선다. 아래가 그 자리를 되묻는다 — `out.outcome = .openFailed` 를 `.queryFailed` 로
/// 바꾸면 이 테스트가 빨개진다.
@Test("2단까지 열지 못하면 openFailures 에 선다 — 침묵하지 않는다")
func v0312OpenFailuresStandWhenBothStagesFail() throws {
    let fm = FileManager.default
    let dir = v0312TempConversations()

    // (1) 권한 0 인 파일. 1단·2단 **양쪽에서** `sqlite3_open_v2` 가 CANTOPEN(14) 이다.
    let locked = dir.appendingPathComponent("conv-unreadable.db")
    v0312WriteConversation(
        at: locked, rows: [(0, v0312Row(input: 1_234, output: 5))], mtime: v0312Now, walMode: true
    )
    try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked.path) }
    // root 로 돌리면 권한이 무의미하다 — 그때는 재는 게 없으니 조용히 지나간다.
    guard !fm.isReadableFile(atPath: locked.path) else { return }

    let read = AntigravityConversationReader.read(path: locked.path, afterIdx: -1)
    #expect(read.outcome == .openFailed, "열지 못한 파일이 '표가 없다'로 접혔다 — 열기 실패 계측이 눈이 먼다")
    #expect(read.usedImmutableFallback, "2단까지 내려가지 않았다")
    #expect(read.rows.isEmpty)
    #expect(read.maxIdx == -1, "못 읽은 파일의 진행 상태를 전진시키면 그 행을 영영 다시 안 읽는다")

    // (2) 없는 경로도 같은 칸이다 — 여기는 울타리(`fence`)조차 세울 수 없는 경로다.
    let gone = AntigravityConversationReader.read(path: dir.appendingPathComponent("gone.db").path, afterIdx: -1)
    #expect(gone.outcome == .openFailed)

    // (3) 스캐너 계측: 열기 실패 칸에 선다. 질의 실패 칸에 섞이면 둘을 가른 의미가 없다.
    var states: [String: AntigravityFileProgress] = [:]
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r.stats.openFailures == 1, "열기 실패가 어느 계측에도 안 남았다 — v0.3.12 P0 의 재발이다")
    #expect(r.stats.queryFailures == 0, "열기 실패가 질의 실패 칸에 섞였다")
    #expect(r.stats.readFailures == 1)
    #expect(r.stats.filesRead == 0)
    #expect(r.stats.immutableReads == 0)
    #expect(r.totals.isEmpty)
    #expect(states.isEmpty, "못 읽은 파일의 상태를 남기면 다음 스캔이 무변경으로 건너뛴다")
}

@Test("gen_metadata 가 없는 db 는 상태를 남기지 않고 지나간다")
func v0312SkipsForeignDatabases() {
    let dir = v0312TempConversations()
    let foreign = dir.appendingPathComponent("not-a-conversation.db")
    var db: OpaquePointer?
    _ = foreign.path.withCString { sqlite3_open_v2($0, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) }
    sqlite3_exec(db, "create table other (a integer)", nil, nil, nil)
    sqlite3_close(db)
    try? FileManager.default.setAttributes([.modificationDate: v0312Now], ofItemAtPath: foreign.path)

    var states: [String: AntigravityFileProgress] = [:]
    let r = AntigravityUsageScanner.update(states: &states, conversationsDirectory: dir, now: v0312Now)
    #expect(r.totals.isEmpty)
    #expect(states.isEmpty)
}

@Test("파일 상태는 배열 튜플로 왕복한다")
func v0312FileProgressCodableRoundTrip() throws {
    let s = AntigravityFileProgress(
        size: 147_456, mtimeMicros: 1_789_108_800_000_000, lastIdx: 7, monthKey: v0312Month,
        monthInput: 15426, monthOutput: 13, monthThinking: 66, monthCacheRead: 8126,
        dayContrib: [v0312Day: 15_505], modelContrib: ["claude-sonnet-4-6": 15_439]
    )
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(AntigravityFileProgress.self, from: data) == s)
    // 압축 인코딩이어야 한다(이름키 JSON 이면 훨씬 길어진다).
    #expect(String(decoding: data, as: UTF8.self).hasPrefix("[147456,"))
}

// MARK: - (d) 읽기 전용 + 실제 픽스처 대조

/// 이 맥의 실측 픽스처. 있으면 정확히 대조하고, 없으면(CI·다른 기기) 조용히 건너뛴다.
/// 값의 출처는 `agy --output-format json` 의 stdout 이다 — facts.md 2026-09-11.
/// **주의**: stdout 의 usage 는 대화 누적이고 gen_metadata 행은 턴당이다. 그래서 여러 턴 대화는
/// "행의 합"이 마지막 턴 stdout 과 같아야 한다(아래 주석의 항등식).
private struct V0312Fixture {
    var input: Int
    var output: Int
    var thinking: Int
    var cacheRead: Int
    var models: [String]
    var rows: Int
}

/// ## ⚠️ 이 맥의 대화 4건 — 무엇이 무엇인지 (같은 파일을 또 만들지 마라)
/// `agy` 호출은 사용자 구글 쿼터를 쓴다. 네 건으로 필드 번호·압축·사이드카 세 가지가 전부 덮이므로
/// **새 대화를 만들 이유가 없다.** 로그는 `~/.gemini/antigravity-cli/log/` 에 있다.
///
/// | conversation id | 만든 로그 | 무엇 | 지금 옆에 있는 것 | 이 표에서 지키는 것 |
/// |---|---|---|---|---|
/// | `4bc6f72b…` | cli-20260911_153434 | 제미나이 1턴 | `-wal`(0바이트)+`-shm` — **우리 잔여** | 필드 번호 1.4.2/3/5 · 1턴 stdout 항등식 |
/// | `295b1ce6…` | cli-20260911_153531 → _153625 (`-c` 이어쓰기) | 클로드 1턴 + 제미나이 1턴 | `-wal`(0바이트)+`-shm` — **우리 잔여** | **행의 합 == 누적 stdout** · 압축된 idx0(1,067B) |
/// | `1010584c…` | cli-20260911_173819 | 제미나이 1턴 (새 대화 ①) | 없음 | cache_read·thinking 이 **아예 없는** 행(필드 없음 = 0) |
/// | `26bdd50a…` | cli-20260911_175401 | 제미나이 1턴 (새 대화 ②) | 없음 | 사이드카 없는 WAL db 의 실물 — 2단 전략의 증거 |
///
/// ⚠️ 넷째 칸을 `agy` 의 상태로 읽지 마라. 앞 두 건의 0바이트 `-wal` 과 `-shm` 은 birth 가 전부 15:52:10~11 이고
/// (그 시각 `agy` 로그가 없다) **우리 프로브가 그때 두 db 를 읽기쓰기로 연 잔여**다. `agy` 가 정상 종료한 뒤의 모양은
/// 뒤 두 건처럼 **사이드카 0** 이고, 그것이 깨끗한 사용자 맥의 정상이다(2단 전략의 존재 이유).
///
/// 앞 보고가 "새 대화 1회"라고 적었는데 **2회**였다(17:38 · 17:54 — 위 표의 ①②). 쿼터 신고를 정정해 둔다.
private let v0312Fixtures: [String: V0312Fixture] = [
    // 제미나이 1턴. stdout: input 5282 / output 1 / thinking 0 / cache_read 8128 / total 5283.
    "4bc6f72b-74f0-44e1-a56e-771d9a2a5e93.db": .init(
        input: 5282, output: 1, thinking: 0, cacheRead: 8128, models: ["gemini-3.8-flash"], rows: 1
    ),
    // 클로드 1턴(15426/13) + 제미나이 1턴(5567/67/66/8126). 두 번째 턴의 stdout 은 **누적**인 20993/80/66/8126 이었다:
    //   15426 + 5567 = 20993 · 13 + 67 = 80 · 0 + 66 = 66 · 0 + 8126 = 8126.
    // idx0 은 1,067B 로 압축된 행이다 — 압축 뒤에도 토큰과 모델이 남는다는 사실을 이 대조가 지킨다.
    "295b1ce6-2806-4de1-a282-ba903278ac63.db": .init(
        input: 20993, output: 80, thinking: 66, cacheRead: 8126,
        models: ["claude-sonnet-4-6", "gemini-3.8-flash"], rows: 2
    ),
    // 새 대화 ① — 2026-09-11 17:38(cli-20260911_173819). 사이드카 없음.
    //   cache_read·thinking 필드가 **아예 없는** 행이다 → "필드 없음 = 0"(protobuf 기본값) 규약의 실물 증거.
    //   여기서 0 이 아닌 값이 나오면 파서가 남의 경로를 줍고 있다는 뜻이다.
    "1010584c-f27a-4883-a7d3-ef3c00c565f1.db": .init(
        input: 13408, output: 3, thinking: 0, cacheRead: 0, models: ["gemini-3.8-flash"], rows: 1
    ),
    // 새 대화 ② — 2026-09-11 17:54(cli-20260911_175401), `agy -p "Reply with exactly: OK"`. **사이드카가 없다**.
    //   stdout: input 4924 / output 113 / thinking 112 / cache_read 8127.
    //   1단(READONLY)으로는 prepare 가 CANTOPEN(14) 으로 죽는 파일이라, 이 한 줄이 2단 전략의 실물 증거다.
    "26bdd50a-2cef-4620-bd2f-5085b7c8b0f9.db": .init(
        input: 4924, output: 113, thinking: 112, cacheRead: 8127, models: ["gemini-3.8-flash"], rows: 1
    ),
]

@Test("실제 대화 db **사본**을 읽어 stdout 실측값과 정확히 맞춘다 (픽스처 없으면 건너뜀)")
func v0312MatchesRealFixtures() {
    // 실폴더에 있는 픽스처 이름을 **먼저** 센다. 이 수가 0 이면 이 기기엔 잴 것이 없다(건너뜀).
    // 0 이 아니면 아래 루프가 정확히 그 수만큼 돌아야 한다 — 사본이 비어 한 바퀴도 안 도는 초록을 막는다.
    let present = v0312PresentFixtureNames()
    guard !present.isEmpty else { return }
    guard let mirror = v0312MirrorRealConversations() else { return }
    defer { v0312ExpectRealConversationsUntouched(mirror.realBefore, "v0312MatchesRealFixtures") }

    var stageOne = 0
    var stageTwo = 0
    for (name, expected) in v0312Fixtures {
        let url = mirror.dir.appendingPathComponent(name)
        // 이 기기에만 있는 실측 픽스처다 — 없으면 그 건만 건너뛴다(합성 테스트가 같은 규약을 이미 덮는다).
        guard FileManager.default.fileExists(atPath: url.path) else { continue }

        // 사본의 `-wal` 유무가 곧 이 파일이 어느 단계로 읽힐지를 정한다(사본이라 원본과 같은 모양이다).
        let hadWal = FileManager.default.fileExists(atPath: url.path + "-wal")
        // `.db` 본체는 한 바이트도 안 바뀌어야 한다.
        let before = try? FileManager.default.attributesOfItem(atPath: url.path)

        let read = AntigravityConversationReader.read(path: url.path, afterIdx: -1)
        #expect(read.outcome == .ok, "\(name) 을 읽지 못했다")
        #expect(read.rejected == 0, "\(name): 파싱이 거부한 행이 있다")
        #expect(read.rows.count == expected.rows, "\(name): 행 수")

        // 행의 합 == 그 대화 마지막 턴의 stdout usage.
        let input = read.rows.reduce(0) { $0 + $1.row.input }
        let output = read.rows.reduce(0) { $0 + $1.row.output }
        let thinking = read.rows.reduce(0) { $0 + $1.row.thinking }
        let cacheRead = read.rows.reduce(0) { $0 + $1.row.cacheRead }
        #expect(input == expected.input, "\(name): input \(input) != \(expected.input)")
        #expect(output == expected.output, "\(name): output \(output) != \(expected.output)")
        #expect(thinking == expected.thinking, "\(name): thinking \(thinking) != \(expected.thinking)")
        #expect(cacheRead == expected.cacheRead, "\(name): cache_read \(cacheRead) != \(expected.cacheRead)")
        #expect(read.rows.compactMap { $0.row.model } == expected.models, "\(name): 모델 식별자")

        // ★ 실데이터로 확인하는 사실관계: `-wal` 이 있으면 1단으로 읽히고, 없으면 2단이 구한다.
        #expect(read.usedImmutableFallback == !hadWal,
                "\(name): -wal 유무와 단계가 어긋났다 (wal=\(hadWal), 2단=\(read.usedImmutableFallback))")
        if hadWal {
            stageOne += 1
            // 1단은 `-shm` 을 만든다 — **사용자 폴더가 아니라 이 임시 사본 옆에** 생긴다는 게 요점이다.
            #expect(FileManager.default.fileExists(atPath: url.path + "-shm"),
                    "\(name): -wal 이 있는데 -shm 이 안 생겼다 — 사실관계가 바뀌었다면 주석을 다시 재라")
        } else {
            stageTwo += 1
            #expect(!v0312HasSidecars(url), "\(name): 사이드카 없는 db 를 읽었는데 파일이 생겼다")
        }

        let after = try? FileManager.default.attributesOfItem(atPath: url.path)
        #expect(before?[.size] as? Int == after?[.size] as? Int, "\(name): 스캔이 .db 크기를 바꿨다")
        #expect(before?[.modificationDate] as? Date == after?[.modificationDate] as? Date,
                "\(name): 스캔이 .db mtime 을 바꿨다")
    }
    // ★ 무측정 초록 금지: 실폴더에 있던 픽스처를 **전부** 실제로 읽었어야 한다(단계별 분포는 기기마다 다르다).
    #expect(stageOne + stageTwo == present.count,
            "실폴더 픽스처 \(present.count)건 중 \(stageOne + stageTwo)건만 읽었다 — 사본이 비었거나 이름이 어긋났다")
    #expect(stageOne + stageTwo >= 1, "한 건도 안 읽고 통과할 뻔했다")
}

/// ★ **사이드카를 지운 사본에서도 같은 값이 나와야 한다.** 사본의 `.db` 만 다시 임시 폴더로 옮기면
/// 깨끗한 사용자 맥(= `agy` 정상 종료 뒤)의 상태가 그대로 재현된다. 여기서 값이 달라지면 그 사람의 집계가 다르다.
/// (실제 폴더는 이 테스트에서도 `copyItem` 으로만 스친다 — 머리말 §규칙.)
@Test("사이드카를 지운 사본도 같은 값을 낸다 (픽스처 없으면 건너뜀)")
func v0312RealFixturesReadTheSameWithoutSidecars() throws {
    let present = v0312PresentFixtureNames()
    guard !present.isEmpty else { return }
    guard let mirror = v0312MirrorRealConversations() else { return }
    defer {
        v0312ExpectRealConversationsUntouched(mirror.realBefore, "v0312RealFixturesReadTheSameWithoutSidecars")
    }
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("v0312-nosidecar-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    var checked = 0
    for (name, expected) in v0312Fixtures {
        let source = mirror.dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else { continue }

        // **`.db` 만** 옮긴다 — 사이드카는 일부러 두고 온다.
        let copy = scratch.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: copy)
        #expect(!v0312HasSidecars(copy))
        let listing = v0312DirectoryListing(scratch)

        let read = AntigravityConversationReader.read(path: copy.path, afterIdx: -1)
        #expect(read.outcome == .ok, "\(name): 사이드카 없는 사본을 못 읽었다")
        #expect(read.rows.count == expected.rows, "\(name): 행 수")
        #expect(read.rows.reduce(0) { $0 + $1.row.input } == expected.input, "\(name): input")
        #expect(read.rows.reduce(0) { $0 + $1.row.output } == expected.output, "\(name): output")
        #expect(read.rows.reduce(0) { $0 + $1.row.thinking } == expected.thinking, "\(name): thinking")
        #expect(read.rows.reduce(0) { $0 + $1.row.cacheRead } == expected.cacheRead, "\(name): cache_read")
        #expect(read.rows.compactMap { $0.row.model } == expected.models, "\(name): 모델")
        // 사이드카가 없으므로 2단으로 읽혔어야 한다(1단이 읽었다면 재현이 안 된 것이다).
        #expect(read.usedImmutableFallback, "\(name): 1단으로 읽혔다 — 이 파일은 WAL 이 아니다")
        // 2단은 파일을 하나도 만들지 않는다 — `-wal`·`-shm` 두 이름이 아니라 **목록 전체**로 본다.
        #expect(v0312DirectoryListing(scratch) == listing, "\(name): 2단 읽기가 파일을 만들었다")

        try FileManager.default.removeItem(at: copy)
        checked += 1
    }
    // ★ 무측정 초록 금지: 실폴더에 있던 픽스처를 **전부** 사이드카 없는 사본으로 다시 읽었어야 한다.
    #expect(checked == present.count,
            "실폴더 픽스처 \(present.count)건 중 \(checked)건만 읽었다 — 사본이 비면 이 루프가 한 바퀴도 안 돈다")
    #expect(checked >= 1, "한 건도 안 읽고 통과할 뻔했다")
}

@Test("실제 대화 디렉터리의 **사본**을 통째로 스캔해도 규약이 유지된다 (없으면 건너뜀)")
func v0312RealDirectoryInvariants() {
    guard let mirror = v0312MirrorRealConversations() else { return }
    defer { v0312ExpectRealConversationsUntouched(mirror.realBefore, "v0312RealDirectoryInvariants") }

    // `now` 를 벽시계가 아니라 **사본에서 가장 새 db 의 mtime** 으로 잡는다. 스캐너의 월 창이 그 파일을 반드시
    // 포함하므로, 달이 바뀌어도 이 테스트가 조용히 "볼 파일 0 건"으로 미끄러지지 않는다(= 무측정 초록 금지).
    let mtimes = mirror.dbNames.compactMap { name -> Date? in
        try? FileManager.default.attributesOfItem(
            atPath: mirror.dir.appendingPathComponent(name).path
        )[.modificationDate] as? Date
    }
    guard let now = mtimes.max() else {
        Issue.record("사본의 db mtime 을 하나도 못 읽었다")
        return
    }

    var states: [String: AntigravityFileProgress] = [:]
    let first = AntigravityUsageScanner.update(states: &states, conversationsDirectory: mirror.dir, now: now)
    // ★ 무측정 초록 금지: 적어도 한 건은 **정말로 열어서 행을 들여왔다**. 아래 항등식들은 전부 0 == 0 으로도 서므로
    //   이 세 줄이 없으면 사본이 비어도(또는 창 밖이어도) 이 테스트는 통째로 초록이다.
    #expect(first.stats.filesRead >= 1, "사본에서 연 파일이 없다 — 아래 항등식은 0 == 0 으로 통과한다")
    #expect(first.stats.rowsIngested >= 1, "행을 하나도 안 들여왔다 — 아래 항등식은 0 == 0 으로 통과한다")
    #expect(first.totals.total > 0, "합계가 0 이다 — 실데이터를 읽었다면 있을 수 없다")
    // total = 네 값 전부(cacheRead 포함) — 월 표의 antigravity_* 네 컬럼 합과 같은 정의.
    #expect(first.totals.total
        == first.totals.input + first.totals.output + first.totals.thinking + first.totals.cacheRead)
    // 일별 합 == 월 total. 귀속 시각이 min(mtime, now) 이라 이번 달 창 안에 전부 들어간다.
    #expect(first.totals.daily.values.reduce(0, +) == first.totals.total)
    // 모델 맵은 total 의 부분집합이다(모델을 못 읽은 행이 있으면 작을 수 있다).
    #expect(first.totals.models.values.reduce(0, +) <= first.totals.total)
    // 모델 식별자에 본문이 섞이지 않는다.
    for m in first.totals.models.keys {
        #expect(m.count <= AntigravityGenMetadataParser.maxModelIdentifierBytes)
        #expect(m.allSatisfy { $0.isASCII && !$0.isNewline })
    }
    // 못 읽은 파일이 있으면 그 사실이 계측에 남는다(집계만 조용히 작아지는 길이 없다).
    #expect(first.stats.queryFailures == 0, "실데이터 사본에 우리가 못 읽는 db 가 있다")
    #expect(first.stats.openFailures == 0, "실데이터 사본을 열지 못했다")
    // 두 번째 스캔은 아무것도 더하지 않는다(증분 규약) — 실데이터에서도 재계상이 없어야 한다.
    let second = AntigravityUsageScanner.update(states: &states, conversationsDirectory: mirror.dir, now: now)
    #expect(second.totals.total == first.totals.total)
    #expect(second.stats.rowsIngested == 0)
}
