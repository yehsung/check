import Foundation
import Testing
@testable import CheckCore

// 서버 안정화(2026-10-30 · 레인 l2s) — send_message 멱등 키 마이그레이션(20261102200000)의 **소스 계약**.
//
// 흐름(같은 키 두 번 = 행 1 · duplicate · 동시 경합 = 행 1 · 이름 인자 2개 = 옛 모양 ok)은 그 파일의 §5 프로브와
// 재생 하네스가 실제 DB 로 잰다. 여기서는 그 증거의 **전제**가 뒷날 조용히 사라지지 않게 글자로 못 박는다:
//   ① 최종 정의가 이 파일이고 3인자 · 키는 기본값 null(앱이 키를 빼면 2인자로 나간다 — 2026-09-12 PGRST202 의 그 규칙)
//   ② 옛 2인자를 **같은 파일**에서 지운다(남기면 2인자 호출이 PGRST203 으로 전부 막힌다)
//   ③ 멱등 조회가 모든 게이트보다 앞이고, 기존 게이트 순서는 그대로다
//   ④ drop 이 버린 ACL · COMMENT 를 운영과 똑같이 되돌린다
//   ⑤ 새 status 어휘를 만들지 않는다(옛 앱이 모르는 값을 조용히 접는다)
//
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 찾고, `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다.

private let idemMigrationName = "20261102200000_message_idempotency.sql"

private struct IdemContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private func idemMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IdemContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
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
    throw IdemContractError("supabase/migrations 를 못 찾았다 — 워크트리라면 CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

private func idemStripLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func idemSquash(_ sql: String) -> String {
    sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func idemMigrationRaw() throws -> String {
    let file = try idemMigrationsDirectory().appendingPathComponent(idemMigrationName)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw IdemContractError("\(idemMigrationName) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

/// 주석을 걷은 SQL 에서 `create [or replace] function public.send_message(` **마지막** 헤더의 인자 원문과 본문(달러 인용 사이).
private func idemSendMessageDefinition(in code: String) -> (arguments: String, body: String)? {
    var searchStart = code.startIndex
    var lastHeader: Range<String.Index>?
    while let found = code.range(of: "function public.send_message(", options: .caseInsensitive,
                                 range: searchStart..<code.endIndex) {
        let lineStart = code[code.startIndex..<found.lowerBound].lastIndex(of: "\n").map { code.index(after: $0) } ?? code.startIndex
        if code[lineStart..<found.lowerBound].lowercased().contains("create") { lastHeader = found }
        searchStart = found.upperBound
    }
    guard let header = lastHeader else { return nil }
    // 인자 목록: 괄호 중첩을 세어 닫는다.
    var depth = 1
    var index = header.upperBound
    while index < code.endIndex, depth > 0 {
        if code[index] == "(" { depth += 1 }
        if code[index] == ")" { depth -= 1 }
        if depth > 0 { index = code.index(after: index) }
    }
    guard depth == 0 else { return nil }
    let arguments = String(code[header.upperBound..<index])
    let after = code[index...]
    guard let asRange = after.range(of: "as $", options: .caseInsensitive) else { return nil }
    let tagStart = after.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = after[after.index(after: tagStart)...].firstIndex(of: "$") else { return nil }
    let tag = String(after[tagStart...tagEnd])
    let bodyStart = after.index(after: tagEnd)
    guard let close = after.range(of: tag, range: bodyStart..<after.endIndex) else { return nil }
    return (arguments, String(after[bodyStart..<close.lowerBound]))
}

/// 앱이 실제로 보내는 키 집합 — 진짜 요청 구조체를 서비스와 같은 설정의 인코더로 인코딩한다(V0313 과 같은 방식).
private func idemSentKeys(_ body: SendMessageRequest) throws -> Set<String> {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase   // SupabaseWorkService.init 과 같은 설정
    let data = try encoder.encode(body)
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw IdemContractError("본문이 JSON 객체가 아니다")
    }
    return Set(object.keys)
}

@Suite("send_message 멱등 키 마이그레이션(20261102200000) 소스 계약")
struct MessageIdempotencyMigrationTests {

    @Test("① 최종 정의는 이 파일의 3인자 — 앱이 빼는 키는 기본값 null")
    func 최종_정의는_이_파일의_3인자다() throws {
        let directory = try idemMigrationsDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var finalFile: String?
        for file in files {
            let code = idemStripLineComments(try String(contentsOf: file, encoding: .utf8))
            if idemSendMessageDefinition(in: code) != nil { finalFile = file.lastPathComponent }
        }
        #expect(finalFile == idemMigrationName, "send_message 의 최종 정의가 \(finalFile ?? "없음") 이다 — 뒤 번호 파일이 멱등 키를 되돌린다")

        let code = idemStripLineComments(try idemMigrationRaw())
        let definition = try #require(idemSendMessageDefinition(in: code), "이 파일에 send_message create 헤더가 없다")
        let declared = definition.arguments.split(separator: ",")
            .map { idemSquash(String($0)).lowercased() }
        #expect(declared == ["p_to uuid", "p_body text", "p_client_message_id uuid default null"],
                "인자 선언이 계약과 다르다: \(declared)")

        // 키 없는 앱(nil) = 2인자 · 키 있는 앱 = 3인자. 빠지는 인자는 반드시 default 를 갖는다.
        let withoutKey = try idemSentKeys(SendMessageRequest(pTo: "00000000-0000-4000-8000-000000000001", pBody: "가"))
        let withKey = try idemSentKeys(SendMessageRequest(pTo: "00000000-0000-4000-8000-000000000001", pBody: "가",
                                                          pClientMessageId: "0b6e6f0e-3f7a-4a51-9d55-6f0b8a1e2c33"))
        #expect(withoutKey == ["p_to", "p_body"])
        #expect(withKey == ["p_to", "p_body", "p_client_message_id"])
        for argument in declared {
            let name = String(argument.split(separator: " ").first ?? "")
            if !withoutKey.contains(name) {
                #expect(argument.contains("default null"), "앱이 빼는 인자 '\(name)' 에 default null 이 없다 — 2인자 호출이 PGRST202 다")
            }
        }
    }

    @Test("② 옛 2인자는 같은 파일에서 create 보다 먼저 지운다(PGRST203)")
    func 옛_2인자는_같은_파일에서_지운다() throws {
        let flat = idemSquash(idemStripLineComments(try idemMigrationRaw())).lowercased()
        let drop = try #require(flat.range(of: "drop function if exists public.send_message(uuid, text);"),
                                "옛 2인자 send_message 를 지우는 줄이 없다 — 3인자 기본값과 겹쳐 2인자 호출이 PGRST203 이다")
        let create = try #require(flat.range(of: "create or replace function public.send_message(p_to uuid, p_body text, p_client_message_id uuid default null)"))
        #expect(drop.lowerBound < create.lowerBound, "drop 이 create 뒤에 있다")
        // 사후 단언이 카탈로그로도 되묻는다(오버로드 정확히 하나).
        #expect(flat.contains("p.proname = 'send_message' and p.pronamespace = 'public'::regnamespace"))
    }

    @Test("③ 멱등 조회 → 신원 → 발표 주간 → 본문 → 집중 → 폭주 → insert(on conflict) → 초인종")
    func 멱등_조회는_모든_게이트보다_앞이다() throws {
        let code = idemStripLineComments(try idemMigrationRaw())
        let body = idemSquash(try #require(idemSendMessageDefinition(in: code)).body).lowercased()
        let anchors = [
            "if uid is not null and p_client_message_id is not null then",
            "m.client_message_id = p_client_message_id",
            "if uid is null or p_to = uid",
            "or public.blocked_between(uid, p_to) then",
            "public.poke_blackout_active()",
            "public.normalize_message_body(p_body)",
            "focus_mode",
            "public.message_flood_limit()",
            "on conflict (from_user, client_message_id) where client_message_id is not null do nothing",
            "returning id, created_at into v_msg_id, v_msg_at",
            "ring := public.poke_ring(p_to);",
            "'message_id',v_msg_id,'created_at',v_msg_at);",
        ]
        var previous = body.startIndex
        for anchor in anchors {
            let found = try #require(body.range(of: anchor), "본문에 '\(anchor)' 가 없다")
            #expect(found.lowerBound >= previous, "'\(anchor)' 의 자리가 계약 순서보다 앞이다")
            previous = found.lowerBound
        }
        // duplicate 는 멱등 게이트 · 경합 두 자리에만 있고 둘 다 초인종 전이다.
        #expect(body.components(separatedBy: "'ring','duplicate'").count - 1 == 2)
        #expect(body.components(separatedBy: "'duplicate',true").count - 1 == 2)
        #expect(body.components(separatedBy: "public.poke_ring(").count - 1 == 1, "초인종이 한 자리가 아니다")
    }

    @Test("운영 정본 줄 보존 — min_message_build 선언 · blackout-gate 마커 · 숨김/차단 · 운영 md5 사전 단언")
    func 운영_정본_줄을_지우지_않는다() throws {
        let raw = try idemMigrationRaw()
        let code = idemStripLineComments(raw)
        let body = try #require(idemSendMessageDefinition(in: code)).body
        for line in [
            "  message_min_build constant int := public.min_message_build();",
            "  --▼ blackout-gate 20260820060000 ▼",
            "  --▲ blackout-gate 20260820060000 ▲",
            "     or not public.same_visibility(uid, p_to)",
            "     or public.blocked_between(uid, p_to) then",
            "    return jsonb_build_object('status','target_focused');",
            "    return jsonb_build_object('status','flood','code','MESSAGE_FLOOD','retry_after_seconds',60);",
        ] {
            #expect(raw.contains(line), "운영 정본 줄이 사라졌다: \(line)")
        }
        // 첫 적용은 옛 2인자 본문이 운영 정본(바이트)일 때만 — 정본이 아니면 그 위에 얹지 않는다.
        #expect(code.contains("'75c4694395380c9af96c94d3dfa95600'"), "운영 정본 md5 사전 단언이 없다")
        #expect(!body.contains("insert into public.messages (from_user, to_user, body) values (uid, p_to, cleaned);"),
                "옛 insert(키 없음)가 본문에 남았다")
    }

    @Test("④ 실행권 · 주석을 운영과 똑같이 되돌린다(anon · PUBLIC 없음)")
    func 실행권은_운영과_같다() throws {
        let flat = idemSquash(idemStripLineComments(try idemMigrationRaw())).lowercased()
        #expect(flat.contains("revoke all on function public.send_message(uuid, text, uuid) from public, anon;"))
        #expect(flat.contains("grant execute on function public.send_message(uuid, text, uuid) to authenticated, service_role;"))
        #expect(flat.contains("comment on function public.send_message(uuid, text, uuid) is"))
        // 파일의 grant 문 전부: 받는 쪽에 anon · PUBLIC 이 없다.
        let grants = flat.components(separatedBy: "grant ").dropFirst().map { String($0.prefix { $0 != ";" }) }
        #expect(!grants.isEmpty)
        for grant in grants {
            let grantees = grant.range(of: " to ", options: .backwards).map { String(grant[$0.upperBound...]) } ?? ""
            #expect(!grantees.contains("anon") && !grantees.contains("public"), "anon · PUBLIC 에 실행권을 주는 grant 가 있다: \(grant)")
        }
    }

    @Test("⑤ 새 status 어휘를 만들지 않는다")
    func 새_status_어휘를_만들지_않는다() throws {
        let code = idemStripLineComments(try idemMigrationRaw())
        let body = try #require(idemSendMessageDefinition(in: code)).body
        let regex = try NSRegularExpression(pattern: #"'status',\s*'([a-z_]+)'"#)
        let values = Set(regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap {
            Range($0.range(at: 1), in: body).map { String(body[$0]) }
        })
        #expect(values == ["ok", "invalid", "blackout", "too_long", "not_text", "target_focused", "flood"],
                "send_message 의 status 어휘가 바뀌었다: \(values.sorted())")
    }

    @Test("칸 · 부분 유니크 색인 · 잠금 상한 · 센티널 프로브")
    func 칸과_색인과_프로브() throws {
        let raw = try idemMigrationRaw()
        let code = idemStripLineComments(raw)
        let flat = idemSquash(code).lowercased()
        #expect(flat.contains("alter table public.messages add column if not exists client_message_id uuid;"))
        // on conflict 의 추론 대상(술어 포함)이 이 색인과 같아야 한다 — 다르면 42P10 으로 모든 전송이 터진다.
        #expect(flat.contains("create unique index if not exists messages_from_client_message_id_key on public.messages (from_user, client_message_id) where client_message_id is not null;"))
        // 첫 문장이 잠금 상한(3초)이다 — 긴 트랜잭션 뒤에서 무한히 기다리며 메시지 경로를 줄 세우지 않는다.
        let firstCode = code.split(separator: "\n").map { idemSquash(String($0)) }.first { !$0.isEmpty }
        #expect(firstCode == "do $lk$")
        #expect(flat.contains("perform set_config('lock_timeout', '3s', true); lock table public.messages in access exclusive mode;"))
        // 프로브: 권한 없으면 건너뜀 · 센티널 롤백 · RESET ROLE 금지 · 최상위 트랜잭션 제어 없음.
        #expect(flat.contains("has_table_privilege('auth.users', 'insert')"))
        #expect(flat.contains("raise exception 'msgidem_probe_rollback';"))
        #expect(!flat.contains("reset role"))
        let lines = code.split(separator: "\n").map { idemSquash(String($0)).lowercased() }
        #expect(!lines.contains("begin;") && !lines.contains("commit;") && !lines.contains("rollback;"),
                "최상위 begin/commit 이 있다 — CLI 가 파일을 트랜잭션으로 감싼다")
    }
}
