import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.51 — **확성기 마이그레이션의 소스 계약**(`20261014122000_megaphone.sql`).
//
// 행동은 로컬 Postgres 하네스(replay-harness-v2 사본 · 체인 116개 재생 → 새 파일 3회 연속 적용 → 파일 안 프로브 20건 +
// 씨앗 사용자 흉내 테스트)가 증명했다. 여기서 보는 것은 **그 행동을 만드는 문장이 사라지거나 바뀌는 것**이다:
//   ① 게이트 순서(신원 → 스위치 → 블랙아웃 → 본문 → 자물쇠 → 멱등키 → 쿨타임 → 받는 사람 → 잔량 → 차감·장부 → 원장 → fan-out → 초인종)
//   ② 지갑 자물쇠가 잔량 읽기보다 **앞** · 차감과 장부가 **짝** · 가격은 상수 함수로(리터럴 50 금지)
//   ③ 멱등키 (sender, request_id) · 인자 전부 DEFAULT · 실행권 authenticated 만 · 상수 함수 PUBLIC 실행권 유지
//   ④ 받는 사람 = app_user_directory 의 세 줄 + 집중 모드 제외
//   ⑤ message_history 는 정본 본문을 한 줄도 잃지 않고 **확성기 줄 하나만** 더했다
//
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

private struct MegaphoneMigrationError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private let megaphoneMigrationName = "20261014122000_megaphone.sql"

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 찾는다(`CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다).
private func megaphoneMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
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
    throw MegaphoneMigrationError("supabase/migrations 를 못 찾았다 — CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

private func megaphoneStripComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func megaphoneSquash(_ sql: String) -> String {
    sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

private func megaphoneSQL() throws -> (raw: String, code: String) {
    let file = try megaphoneMigrationsDirectory().appendingPathComponent(megaphoneMigrationName)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw MegaphoneMigrationError("\(megaphoneMigrationName) 이 없다")
    }
    let raw = try String(contentsOf: file, encoding: .utf8)
    return (raw, megaphoneStripComments(raw))
}

/// `create [or replace] function public.<name>(` **마지막** 정의의 본문(달러 인용 사이 — 태그는 파일마다 다르다).
private func megaphoneFunctionBody(_ name: String, in sql: String) -> String? {
    var searchStart = sql.startIndex
    var lastHeader: Range<String.Index>?
    while let found = sql.range(of: "function public.\(name)(", options: .caseInsensitive, range: searchStart..<sql.endIndex) {
        let lineStart = sql[sql.startIndex..<found.lowerBound].lastIndex(of: "\n").map { sql.index(after: $0) } ?? sql.startIndex
        if sql[lineStart..<found.lowerBound].lowercased().contains("create") { lastHeader = found }
        searchStart = found.upperBound
    }
    guard let header = lastHeader else { return nil }
    let after = sql[header.upperBound...]
    guard let asRange = after.range(of: "as $", options: .caseInsensitive) else { return nil }
    let tagStart = after.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = after[after.index(after: tagStart)...].firstIndex(of: "$") else { return nil }
    let tag = String(after[tagStart...tagEnd])
    let bodyStart = after.index(after: tagEnd)
    guard let close = after.range(of: tag, range: bodyStart..<after.endIndex) else { return nil }
    return String(after[bodyStart..<close.lowerBound])
}

/// 주석을 걷어낸 본문에서 `needle` 이 처음 나오는 자리(공백 접기 후). 없으면 nil.
private func position(of needle: String, in squashed: String) -> String.Index? {
    squashed.range(of: needle.lowercased())?.lowerBound
}

@Suite struct V0351MegaphoneMigrationTests {
    @Test("상수: 가격 50 · 쿨타임 600 · 스위치 true · 표식 📢 — 그리고 PUBLIC 실행권을 회수하지 않는다")
    func constants() throws {
        let (_, code) = try megaphoneSQL()
        // 한 줄 정의를 통째로 본다(킬스위치는 파일 안 프로브가 잠깐 false 로 다시 정의했다가 되돌리므로 '마지막 정의'로 찾지 않는다).
        let flat0 = megaphoneSquash(code)
        for (name, ret, value) in [("megaphone_ruby_price", "int", "select 50"), ("megaphone_cooldown_seconds", "int", "select 600"),
                                   ("megaphone_enabled", "boolean", "select true")] {
            #expect(flat0.contains("create or replace function public.\(name)() returns \(ret) language sql immutable as $fn$ \(value) $fn$;"),
                    "\(name) 이 \(value) 가 아니다")
        }
        let prefix = try #require(megaphoneFunctionBody("megaphone_prefix", in: code))
        #expect(prefix.contains(#"U&'\+01F4E2' || ' '"#), "표식이 📢 + 공백이 아니다")
        // shop.sql:95-107 의 42501 함정 — 상수 함수의 실행권을 회수하면 소유자가 다른 definer 함수가 죽는다.
        let flat = megaphoneSquash(code)
        for name in ["megaphone_ruby_price", "megaphone_cooldown_seconds", "megaphone_enabled", "megaphone_prefix", "megaphone_max_length"] {
            #expect(!flat.contains("on function public.\(name)() from"), "\(name) 의 실행권을 회수한다 — 42501 함정")
        }
    }

    @Test("send_megaphone: 인자 둘 다 DEFAULT · authenticated 전용 · definer + search_path 고정")
    func sendSignatureAndGrants() throws {
        let (_, code) = try megaphoneSQL()
        let flat = megaphoneSquash(code)
        #expect(flat.contains("create or replace function public.send_megaphone(p_body text default null, p_request_id uuid default null)"),
                "send_megaphone 서명이 바뀌었다 — 인자 둘 다 DEFAULT 여야 한다(PGRST202 전례)")
        #expect(flat.contains("revoke all on function public.send_megaphone(text, uuid) from public, anon;"))
        #expect(flat.contains("grant execute on function public.send_megaphone(text, uuid) to authenticated;"))
        #expect(flat.contains("revoke all on function public.megaphone_info() from public, anon;"))
        #expect(flat.contains("grant execute on function public.megaphone_info() to authenticated;"))
        #expect(flat.contains("revoke all on function public.megaphone__recipients(uuid) from public, anon, authenticated;"),
                "받는 사람 술어가 클라에 열린다")
        for name in ["send_megaphone", "megaphone_info", "megaphone__recipients"] {
            let header = try #require(flat.range(of: "create or replace function public.\(name)("))
            let tail = String(flat[header.upperBound...].prefix(260))
            #expect(tail.contains("security definer") && tail.contains("set search_path = public"),
                    "\(name) 이 security definer + search_path 고정이 아니다: \(tail)")
        }
    }

    @Test("앱이 싣는 키(p_body · p_request_id) = 서버가 선언한 인자")
    func clientKeysMatchServerArguments() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(SendMegaphoneRequest(pBody: "안녕", pRequestId: "r"))
        let keys = Set((try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]).keys)
        #expect(keys == ["p_body", "p_request_id"], "앱이 싣는 키: \(keys)")
        let (_, code) = try megaphoneSQL()
        let flat = megaphoneSquash(code)
        for key in keys {
            #expect(flat.contains("\(key) "), "서버 인자에 \(key) 가 없다 — PostgREST 가 함수를 못 찾는다")
        }
    }

    @Test("게이트 순서: 신원 → 스위치 → 블랙아웃 → 본문 → 자물쇠 → 멱등키 → 쿨타임 → 받는 사람 → 잔량 → 차감 → 장부 → 원장 → fan-out → 초인종")
    func gateOrder() throws {
        let (_, code) = try megaphoneSQL()
        let body = megaphoneSquash(try #require(megaphoneFunctionBody("send_megaphone", in: code)))
        let steps = [
            "if uid is null then",
            "public.megaphone_enabled()",
            "public.poke_blackout_active()",
            "public.normalize_message_body(p_body)",
            "public.is_message_body(v_full)",
            "pg_advisory_xact_lock(hashtext('ultra_wallet:' || uid::text))",
            "m.request_id = v_req",
            "v_last + make_interval(secs => v_cool) > now()",
            "public.megaphone__recipients(uid)",
            "'no_recipients'",
            "for update",
            "'insufficient'",
            "update public.profiles set ruby_balance = ruby_balance - v_price",
            "insert into public.ruby_ledger",
            "insert into public.megaphones",
            "insert into public.messages (from_user, to_user, body, megaphone_id)",
            "public.poke_ring(v_target)",
        ]
        var previous: String.Index?
        var previousStep = ""
        for step in steps {
            let at = try #require(position(of: step, in: body), "send_megaphone 에 [\(step)] 이 없다")
            if let previous {
                #expect(previous < at, "[\(previousStep)] 이 [\(step)] 보다 뒤에 있다 — 순서가 계약이다")
            }
            previous = at
            previousStep = step
        }
    }

    @Test("돈: 가격은 상수 함수로(리터럴 50 금지) · 차감과 장부가 짝 · spend:megaphone · 쿨타임도 상수 함수")
    func money() throws {
        let (_, code) = try megaphoneSQL()
        let body = megaphoneSquash(try #require(megaphoneFunctionBody("send_megaphone", in: code)))
        #expect(body.contains("v_price constant int := public.megaphone_ruby_price();"), "가격을 상수 함수로 안 읽는다")
        #expect(body.contains("v_cool constant int := public.megaphone_cooldown_seconds();"), "쿨타임을 상수 함수로 안 읽는다")
        #expect(body.range(of: #"(^|[^0-9])50([^0-9]|$)"#, options: .regularExpression) == nil,
                "send_megaphone 본문에 리터럴 50 이 있다 — 가격은 megaphone_ruby_price() 한 곳에만")
        #expect(body.range(of: #"(^|[^0-9])600([^0-9]|$)"#, options: .regularExpression) == nil,
                "send_megaphone 본문에 리터럴 600 이 있다 — 쿨타임은 megaphone_cooldown_seconds() 한 곳에만")
        #expect(body.contains("'spend:megaphone', -v_price, v_bal"), "장부 사유·차감액·잔량이 짝이 아니다")
        #expect(body.contains("jsonb_build_object('megaphone_id', v_id, 'recipients', v_n, 'price', v_price)"),
                "장부 detail 에 원장 id · 받는 사람 수 · 가격이 없다")
        let info = megaphoneSquash(try #require(megaphoneFunctionBody("megaphone_info", in: code)))
        #expect(info.contains("'price', public.megaphone_ruby_price()") && info.contains("public.megaphone__recipients(uid)"),
                "미리보기가 가격·받는 사람을 같은 함수로 안 센다")
    }

    @Test("멱등키: (sender, request_id) 유니크 · 같은 키는 처음 결과를 duplicate 로")
    func idempotency() throws {
        let (_, code) = try megaphoneSQL()
        let flat = megaphoneSquash(code)
        #expect(flat.contains("constraint megaphones_sender_request_key unique (sender, request_id)"))
        let body = megaphoneSquash(try #require(megaphoneFunctionBody("send_megaphone", in: code)))
        #expect(body.contains("'duplicate', true"), "같은 요청의 재시도가 duplicate 로 답하지 않는다")
        #expect(body.contains("v_req uuid := coalesce(p_request_id, gen_random_uuid())"), "키가 없는 요청의 처리가 바뀌었다")
    }

    @Test("받는 사람: 본인 제외 · same_visibility · blocked_between · 집중 모드 제외 — 팀 조건 없음")
    func recipients() throws {
        let (_, code) = try megaphoneSQL()
        let body = megaphoneSquash(try #require(megaphoneFunctionBody("megaphone__recipients", in: code)))
        #expect(body.contains("p.id <> p_sender"))
        #expect(body.contains("public.same_visibility(p_sender, p.id)"))
        #expect(body.contains("not public.blocked_between(p_sender, p.id)"))
        #expect(body.contains("not coalesce(p.focus_mode, false)"), "집중 모드(메시지의 유일한 수신 거부 수단)를 안 본다")
        #expect(!body.contains("memberships") && !body.contains("team_id"), "확성기 대상에 팀 조건이 들어갔다")
        #expect(!body.contains("user_blocks"), "차단을 user_blocks 로 직접 읽는다 — 판정은 blocked_between 한 함수만")
    }

    @Test("표: 원장 FK 는 같은 줄 cascade · RLS · 클라 권한 0 · messages.megaphone_id 는 원장으로 cascade")
    func tables() throws {
        let (_, code) = try megaphoneSQL()
        let lines = code.split(separator: "\n").map { megaphoneSquash(String($0)) }
        #expect(lines.contains { $0.contains("sender uuid not null references auth.users(id) on delete cascade") })
        let flat = megaphoneSquash(code)
        #expect(flat.contains("alter table public.megaphones enable row level security;"))
        #expect(flat.contains("revoke all on public.megaphones from public, anon, authenticated;"))
        #expect(!flat.contains("grant select on public.megaphones to authenticated"))
        #expect(flat.contains("foreign key (megaphone_id) references public.megaphones(id) on delete cascade"))
        #expect(flat.contains("alter table public.messages add column if not exists megaphone_id uuid;"))
        // PostgREST 임베드 모호성: 원장은 profiles·teams 를 가리키지 않는다.
        #expect(!flat.contains("references public.profiles"), "새 FK 가 profiles 로 간다 — 기존 임베드가 400 이 된다")
    }

    @Test("message_history: 정본 본문을 한 줄도 잃지 않고 확성기 줄 하나만 더했다")
    func messageHistoryKeepsCanonicalBody() throws {
        let directory = try megaphoneMigrationsDirectory()
        let canonicalRaw = try String(contentsOf: directory.appendingPathComponent("20260918180000_blocks_and_reports.sql"),
                                      encoding: .utf8)
        let canonical = try #require(megaphoneFunctionBody("message_history", in: canonicalRaw))
        let (raw, _) = try megaphoneSQL()
        let mine = try #require(megaphoneFunctionBody("message_history", in: raw))
        func codeLines(_ body: String) -> [String] {
            megaphoneStripComments(body).split(separator: "\n").map { megaphoneSquash(String($0)) }.filter { !$0.isEmpty }
        }
        let oldLines = codeLines(canonical)
        let newLines = codeLines(mine)
        let added = "and not (m.from_user = v_uid and m.megaphone_id is not null)"
        #expect(newLines.filter { $0 == added }.count == 1, "확성기 줄이 정확히 한 번 있지 않다")
        #expect(newLines.filter { $0 != added } == oldLines, "확성기 줄 말고도 바뀌었다 — 벽·차단·limit 이 그대로여야 한다")
        // 벽과 차단 줄이 살아 있다(정본 대조가 공허하게 초록이 되지 않게 직접도 본다).
        #expect(newLines.contains("where (m.from_user = v_uid or m.to_user = v_uid)"))
        #expect(newLines.contains { $0.contains("not public.blocked_between(v_uid,") })
        // 반환 모양(10칸)과 서명이 그대로다 — create or replace 로만(drop 은 실행권을 버린다).
        let flat = megaphoneSquash(megaphoneStripComments(raw))
        #expect(flat.contains("create or replace function public.message_history(p_hours int default 12, p_limit int default 200)"))
        #expect(!flat.contains("drop function if exists public.message_history"), "message_history 를 drop 한다 — 실행권을 잃는다")
    }

    @Test("원장 24시간 청소 함수 + 매시 :29 cron · 클라 실행권 없음")
    func cleanup() throws {
        let (_, code) = try megaphoneSQL()
        let body = megaphoneSquash(try #require(megaphoneFunctionBody("cleanup_old_megaphones", in: code)))
        #expect(body.contains("public.message_retention_hours()"), "보관 창을 리터럴로 적었다 — message_retention_hours() 한 곳에만")
        let flat = megaphoneSquash(code)
        #expect(flat.contains("cron.schedule('cleanup-old-megaphones', '29 * * * *'"))
        #expect(flat.contains("revoke execute on function public.cleanup_old_megaphones() from anon, authenticated;"))
    }

    @Test("파일 안 흐름 프로브가 있고 센티널로 롤백한다")
    func probeExists() throws {
        let (_, code) = try megaphoneSQL()
        let flat = megaphoneSquash(code)
        #expect(flat.contains("raise exception 'mega_probe_rollback'"), "센티널 롤백이 없다 — 합성 행이 운영에 남는다")
        #expect(flat.contains("v_expected constant int := 20;"), "프로브 개수 가드가 없다")
        // 운영 안전: 실사용자에게 보내 보기 전에 받는 사람이 합성 계정뿐임을 먼저 확인한다.
        #expect(flat.contains("이 상태로는 보내 보지 않는다"))
    }
}
