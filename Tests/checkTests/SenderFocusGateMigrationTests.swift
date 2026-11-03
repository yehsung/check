import Foundation
import Testing

// 보낸이 집중 차단(20261108121000_sender_focus_gate · 대표 결정 2026-11-03 "찌르기·메시지만" · "지금 서버에서도 막기")의 **소스 계약**.
//
// 흐름(집중 보낸이 → sender_focused · 쓰기 0 · 같은 키 재시도 duplicate)은 그 파일의 §5 프로브와 재생 하네스가 실제 DB 로 잰다.
// 여기서는 **최종 정의**(마이그레이션 폴더에서 그 함수를 마지막으로 create 한 파일 — 이 파일로 못 박지 않는다)에 대해 잰다:
//   ① 세 함수(send_message · poke_user · ultra_poke_user)의 최종 정의에 보낸이 집중 조각이 **정확히 한 번** 있고 자리가 계약대로다
//      — 멱등 재생(send_message) · 신원/invalid · 발표 주간 · 보낸이 근무(찌르기) **뒤**, 상대 집중(target_focused) **앞**,
//        모든 쓰기(insert · 울트라 재화 · 잔량 · 장부) · 초인종 **앞**.
//      그래서 뒷날 누가 세 함수를 다시 정의하면서 조각을 빼거나 insert 뒤로 옮기거나 상대 칸(p_to)을 읽게 바꾸면 여기서 빨개진다
//      (검토 11-03 P2: 전에는 'sender_focused' 글자가 본문에 있는지만 봤다).
//   ② send_message 최종 정의가 멱등 키 계약을 그대로 지닌다(3인자 · 키 기본값 null · on conflict) — 운영 정본에서 출발했다는 증거.
//   ③ 막지 않는 길: 확성기(send_megaphone) · 게임 안 채팅(gomoku_chat_send) · 큐브 반응(rummy_react)의 최종 정의는 보낸이 집중을
//      보지 않는다(대표 결정 범위 "찌르기·메시지만").
//
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다). 비교는 공백을 전부 걷은 소문자로 한다
// (함수마다 `'status', '…'` · `'status','…'` 문체가 달라도 같은 조각으로 본다).
// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 찾고, `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다.

private let sfgMigrationName = "20261108121000_sender_focus_gate.sql"

/// 보낸이 집중 조각(공백 걷음 · 소문자). 반드시 **보낸이**(uid) 칸을 읽는다 — p_to 를 읽으면 상대 집중과 같은 뜻이 된다.
private let sfgFragment =
    "ifexists(select1frompublic.profileswhereid=uidandfocus_mode)thenreturnjsonb_build_object('status','sender_focused');endif;"

private struct SFGContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private func sfgMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SFGContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw SFGContractError("supabase/migrations 를 못 찾았다 — 워크트리라면 CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

private func sfgStripLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func sfgDespace(_ sql: String) -> String {
    String(sql.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init)).lowercased()
}

/// 주석을 걷은 SQL 에서 `create … function public.<이름>(` **마지막** 헤더의 인자 원문과 본문(달러 인용 사이).
private func sfgDefinition(of function: String, in code: String) -> (arguments: String, body: String)? {
    var searchStart = code.startIndex
    var lastHeader: Range<String.Index>?
    while let found = code.range(of: "function public.\(function)(", options: .caseInsensitive,
                                 range: searchStart..<code.endIndex) {
        let lineStart = code[code.startIndex..<found.lowerBound].lastIndex(of: "\n").map { code.index(after: $0) } ?? code.startIndex
        if code[lineStart..<found.lowerBound].lowercased().contains("create") { lastHeader = found }
        searchStart = found.upperBound
    }
    guard let header = lastHeader else { return nil }
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

/// 폴더 전체에서 그 함수를 **마지막으로** create 한 파일과 그 정의(번호 순 — 운영 CLI 적용 순서).
private func sfgFinalDefinition(of function: String) throws -> (file: String, arguments: String, body: String) {
    let files = try FileManager.default.contentsOfDirectory(at: try sfgMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var found: (String, String, String)?
    for file in files {
        let code = sfgStripLineComments(try String(contentsOf: file, encoding: .utf8))
        if let definition = sfgDefinition(of: function, in: code) {
            found = (file.lastPathComponent, definition.arguments, definition.body)
        }
    }
    guard let found else { throw SFGContractError("\(function) 의 정의가 마이그레이션 폴더에 없다") }
    return found
}

private func sfgOccurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

/// 순서 사슬: 각 자리는 본문에 있어야 하고, 앞 자리의 **첫** 위치보다 뒤에서 처음 나와야 한다.
private func sfgExpectOrder(_ chain: [String], in body: String, _ label: String) {
    var previous = body.startIndex
    var previousAnchor = "(본문 시작)"
    for anchor in chain {
        guard let range = body.range(of: anchor) else {
            Issue.record("\(label): '\(anchor)' 이 최종 정의에 없다")
            return
        }
        #expect(range.lowerBound >= previous, "\(label): '\(anchor)' 이 '\(previousAnchor)' 보다 앞에 있다 — 자리 계약이 깨졌다")
        previous = range.lowerBound
        previousAnchor = anchor
    }
}

@Suite("보낸이 집중 차단(20261108121000) 소스 계약")
struct SenderFocusGateMigrationTests {

    @Test("① 세 함수 최종 정의 — 조각은 정확히 한 번 · 보낸이(uid) 칸 · 재생/신원/발표 주간 뒤 · 상대 집중과 모든 쓰기 앞")
    func 보낸이_집중_조각은_쓰기와_상대_집중보다_앞이다() throws {
        // send_message: 멱등 재생 → 신원/invalid → 발표 주간 → [보낸이 집중] → 본문 → 상대 집중 → 폭주 → insert → 초인종
        let message = try sfgFinalDefinition(of: "send_message")
        let messageBody = sfgDespace(message.body)
        #expect(sfgOccurrences(of: sfgFragment, in: messageBody) == 1,
                "send_message 최종 정의(\(message.file))에 보낸이 집중 조각이 정확히 한 번 있어야 한다")
        sfgExpectOrder([
            "m.client_message_id=p_client_message_id",
            "public.blocked_between(uid,p_to)",
            "public.poke_blackout_active()",
            sfgFragment,
            "public.normalize_message_body(p_body)",
            "jsonb_build_object('status','target_focused')",
            "public.message_flood_limit()",
            "insertintopublic.messages",
            "public.poke_ring(p_to)",
        ], in: messageBody, "send_message(\(message.file))")

        // poke_user: 신원/invalid → 발표 주간 → 보낸이 근무 → [보낸이 집중] → 대상 자리비움 → 상대 집중 → 폰 → insert → 초인종
        let poke = try sfgFinalDefinition(of: "poke_user")
        let pokeBody = sfgDespace(poke.body)
        #expect(sfgOccurrences(of: sfgFragment, in: pokeBody) == 1,
                "poke_user 최종 정의(\(poke.file))에 보낸이 집중 조각이 정확히 한 번 있어야 한다")
        sfgExpectOrder([
            "public.blocked_between(uid,p_to)",
            "public.poke_blackout_active()",
            "jsonb_build_object('status','not_working')",
            sfgFragment,
            "jsonb_build_object('status','target_not_working')",
            "jsonb_build_object('status','target_focused')",
            "public.phone_work__poke_unreachable(p_to)",
            "insertintopublic.pokes",
            "public.poke_ring(p_to)",
        ], in: pokeBody, "poke_user(\(poke.file))")

        // ultra_poke_user: … 보낸이 근무 → [보낸이 집중] → 대상 자리비움 → 상대 집중 → 폰 → (관리자 · 재화 · 잔량 · 장부 · 발사)
        let ultra = try sfgFinalDefinition(of: "ultra_poke_user")
        let ultraBody = sfgDespace(ultra.body)
        #expect(sfgOccurrences(of: sfgFragment, in: ultraBody) == 1,
                "ultra_poke_user 최종 정의(\(ultra.file))에 보낸이 집중 조각이 정확히 한 번 있어야 한다")
        sfgExpectOrder([
            "public.blocked_between(uid,p_to)",
            "public.poke_blackout_active()",
            "jsonb_build_object('status','not_working')",
            sfgFragment,
            "jsonb_build_object('status','target_not_working')",
            "jsonb_build_object('status','target_focused')",
            "public.phone_work__poke_unreachable(p_to)",
        ], in: ultraBody, "ultra_poke_user(\(ultra.file))")
        // 쓰기는 분기가 여럿이다(관리자 무제한 분기가 재화보다 앞) — 조각이 **모든** 쓰기의 첫 자리보다 앞인지 본다.
        if let fragment = ultraBody.range(of: sfgFragment) {
            for write in ["insertintopublic.pokes", "public.ultra_wallet_touch(uid)",
                          "updatepublic.profilessetultra_balance", "insertintopublic.ultra_ledger", "public.poke_ring(p_to)"] {
                let first = try #require(ultraBody.range(of: write), "ultra_poke_user 에 '\(write)' 이 없다")
                #expect(fragment.upperBound <= first.lowerBound,
                        "ultra_poke_user(\(ultra.file)): 보낸이 집중 조각이 '\(write)' 뒤에 있다 — 거절이 몫·장부·초인종을 태운다")
            }
        }
    }

    @Test("② send_message 최종 정의는 멱등 키 계약을 그대로 지닌다(3인자 · 키 기본값 null · on conflict)")
    func send_message_최종_정의는_멱등_계약을_지닌다() throws {
        let message = try sfgFinalDefinition(of: "send_message")
        let declared = message.arguments.split(separator: ",").map { argument -> String in
            // pg_get_functiondef 문체(`DEFAULT NULL::uuid`)와 손으로 쓴 문체(`default null`)를 같은 것으로 본다.
            argument.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
                .replacingOccurrences(of: "default null::uuid", with: "default null")
        }
        #expect(declared == ["p_to uuid", "p_body text", "p_client_message_id uuid default null"],
                "send_message 최종 정의(\(message.file))의 인자가 멱등 키 계약과 다르다: \(declared)")
        let body = sfgDespace(message.body)
        #expect(body.contains("onconflict(from_user,client_message_id)whereclient_message_idisnotnulldonothing"),
                "send_message 최종 정의(\(message.file))에 멱등 insert(on conflict)가 없다 — 운영 정본에서 출발하지 않았다")
        #expect(body.contains("andmegaphone_idisnull"),
                "send_message 최종 정의(\(message.file))의 폭주 집계가 확성기 줄을 다시 센다(20261107130000 이 뺀 것)")
    }

    @Test("③ 막지 않는 길 — 확성기 · 게임 안 채팅 · 큐브 반응은 보낸이 집중을 보지 않는다")
    func 확성기와_게임_채팅은_보낸이_집중을_보지_않는다() throws {
        for function in ["send_megaphone", "gomoku_chat_send", "rummy_react"] {
            let definition = try sfgFinalDefinition(of: function)
            let body = sfgDespace(definition.body)
            #expect(!body.contains("sender_focused"),
                    "\(function)(\(definition.file))가 sender_focused 를 낸다 — 대표 결정 범위('찌르기·메시지만') 밖이다")
            #expect(!body.contains("whereid=uidandfocus_mode") && !body.contains("whereid=v_uidandfocus_mode"),
                    "\(function)(\(definition.file))가 보낸이 집중을 본다 — 대표 결정 범위('찌르기·메시지만') 밖이다")
        }
    }

    @Test("④ 이 마이그레이션이 폴더에 있다 — 없으면 위 계약은 빈말이다")
    func 보낸이_집중_마이그레이션이_있다() throws {
        let file = try sfgMigrationsDirectory().appendingPathComponent(sfgMigrationName)
        #expect(FileManager.default.fileExists(atPath: file.path), "\(sfgMigrationName) 이 마이그레이션 폴더에 없다")
    }
}
