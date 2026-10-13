import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.51 — 상태메시지 마이그레이션(`20261014121000_status_message.sql`)의 **소스 계약**.
//
// 행동(정규화 · 40자 · 글자 규칙 · 지우기 · 차단/숨김 · anon 거절 · PATCH 우회 불가)은 로컬 Postgres 하네스
// (replay-harness-v2 · 체인 재생 → 새 파일 3회 적용 → 파일 안 프로브 16건 + 사용자 흉내 테스트)가 증명했다.
// 여기서 보는 것은 **그 행동을 만드는 문장이 사라지거나 넓어지는 것**이다:
//   ① 칸 · CHECK(1~40) · select grant 만 있고 **update grant 가 없다**(PATCH 한 방으로 40자·글자 규칙 우회 금지).
//   ② set_status_message — definer · search_path · `p_text text default null` · 응답 어휘 다섯 · 메시지와 같은 판정 함수 · 실행권.
//   ③ app_user_directory drop+create — 반환 칸 끝에 status_message · 가시성/차단/나 빼기/정렬 줄 · ACL 복원(public·anon 회수).
//   ④ 클라 상수(40)와 서버 상수가 같다 · 클라 정규화 글자 집합이 서버 식과 같다.
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

private let smMigrationName = "20261014121000_status_message.sql"

private struct SMContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 `supabase/migrations` 가 있는 첫 디렉토리를 잡는다
/// (`CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다 — V0333 과 같은 방식).
private func smMigrationsDirectory() throws -> URL {
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
    throw SMContractError("supabase/migrations 를 못 찾았다 — 워크트리라면 CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

private func smStripLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 주석을 걷고 공백을 한 칸으로 접은 소문자 본문.
private func smFlat(_ sql: String) -> String {
    smStripLineComments(sql).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

private func smSQL() throws -> (raw: String, flat: String) {
    let file = try smMigrationsDirectory().appendingPathComponent(smMigrationName)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw SMContractError("\(smMigrationName) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    let raw = try String(contentsOf: file, encoding: .utf8)
    return (raw, smFlat(raw))
}

/// `create [or replace] function public.<name>(` **마지막** 정의의 본문(달러 인용 사이, 접힌 소문자). 없으면 nil.
private func smFunctionBody(_ name: String, in flat: String) -> String? {
    var last: Range<String.Index>?
    var start = flat.startIndex
    while let found = flat.range(of: "function public.\(name)(", range: start..<flat.endIndex) {
        let head = flat[flat.index(found.lowerBound, offsetBy: -min(20, flat.distance(from: flat.startIndex, to: found.lowerBound)))..<found.lowerBound]
        if head.contains("create") { last = found }
        start = found.upperBound
    }
    guard let header = last else { return nil }
    let after = flat[header.upperBound...]
    guard let asRange = after.range(of: " as $") else { return nil }
    let afterAs = after[asRange.upperBound...]
    guard let tagEnd = afterAs.firstIndex(of: "$") else { return nil }
    let tag = "$" + afterAs[afterAs.startIndex..<tagEnd] + "$"
    let bodyStart = afterAs.index(after: tagEnd)
    guard let close = afterAs[bodyStart...].range(of: tag) else { return nil }
    return String(flat[header.lowerBound..<close.upperBound])
}

// MARK: - ① 칸 · 제약 · 권한

@Test
func 상태메시지_칸은_null_가능_text_이고_CHECK_는_길이만_본다() throws {
    let (_, flat) = try smSQL()
    #expect(flat.contains("alter table public.profiles add column if not exists status_message text;"),
            "status_message text 칸(기본값 없음 · null 가능)을 더하지 않는다")
    #expect(flat.contains("check (status_message is null or char_length(status_message) between 1 and 40)"),
            "CHECK 가 null 또는 1~40 코드포인트가 아니다")
    // CHECK 에 판정 함수를 부르지 않는다 — profiles 의 모든 UPDATE 에서 다시 평가되므로, 그 함수가 좁아지는 날 옛 값을 가진 사람의
    // 아바타·집중 모드·app_build 갱신이 통째로 23514 로 죽는다(머리말).
    let checkStart = try #require(flat.range(of: "add constraint profiles_status_message_valid"))
    let checkLine = flat[checkStart.upperBound...].prefix(120)
    #expect(!checkLine.contains("is_message_body"), "CHECK 가 판정 함수를 부른다 — 길이 한 줄만 본다")
}

@Test
func 상태메시지_칸은_select_만_주고_update_는_주지_않는다() throws {
    let (_, flat) = try smSQL()
    #expect(flat.contains("grant select (status_message) on public.profiles to anon, authenticated;"),
            "select grant 가 없다 — 내 값 GET 이 42501 → 403 이다")
    // update grant 의 어떤 꼴도 없다(칸 단위든 표 단위든).
    #expect(!flat.contains("update (status_message"), "status_message 에 update grant 가 있다 — PATCH 로 40자·글자 규칙을 우회한다")
    #expect(!flat.contains("grant update on public.profiles to authenticated"), "표 단위 update grant 를 되살렸다")
    #expect(!flat.contains("grant all on public.profiles"), "표 단위 all grant 를 되살렸다")
    // 사후 단언이 카탈로그로 같은 사실을 되묻는다.
    #expect(flat.contains("has_column_privilege('authenticated', 'public.profiles', 'status_message', 'update')"),
            "사후 단언이 update 권한 부재를 카탈로그로 되묻지 않는다")
}

// MARK: - ② set_status_message

@Test
func 쓰기_RPC_는_definer_이고_p_text_기본값이_있으며_authenticated_만_실행한다() throws {
    let (_, flat) = try smSQL()
    let body = try #require(smFunctionBody("set_status_message", in: flat), "set_status_message 정의가 없다")
    #expect(body.contains("set_status_message(p_text text default null)"), "인자가 `p_text text default null` 이 아니다")
    #expect(body.contains("returns jsonb"))
    #expect(body.contains("security definer"))
    #expect(body.contains("set search_path = public"))
    // 신원: auth.uid() 만 본다(인자로 대상을 받지 않는다 — 남의 상태를 쓸 문이 없다).
    #expect(body.contains("v_uid uuid := auth.uid();"))
    #expect(body.contains("update public.profiles set status_message = v_clean where id = v_uid;"),
            "쓰기가 내 행(auth.uid()) 한 줄이 아니다")
    #expect(body.contains("update public.profiles set status_message = null where id = v_uid;"),
            "지우기가 내 행을 null 로 만들지 않는다")
    // 실행권.
    #expect(flat.contains("revoke execute on function public.set_status_message(text) from public, anon;"))
    #expect(flat.contains("grant execute on function public.set_status_message(text) to authenticated;"))
    #expect(!flat.contains("grant execute on function public.set_status_message(text) to anon"))
}

@Test
func 쓰기_RPC_의_응답_어휘는_다섯이고_판정은_메시지와_같은_함수다() throws {
    let (_, flat) = try smSQL()
    let body = try #require(smFunctionBody("set_status_message", in: flat))
    for status in ["'unauthorized'", "'cleared'", "'not_text'", "'too_long'", "'ok'"] {
        #expect(body.contains("jsonb_build_object('status', \(status)"), "응답 어휘 \(status) 가 없다")
    }
    // 클라가 아는 어휘 밖의 status 를 새로 만들지 않는다(옛 클라가 모르는 값을 접는 사고 — 열거값 확장엔 능력 협상).
    let statuses = body.components(separatedBy: "jsonb_build_object('status', '").dropFirst().map { $0.prefix { $0 != "'" } }
    #expect(Set(statuses.map(String.init)) == ["unauthorized", "cleared", "not_text", "too_long", "ok"],
            "응답 status 어휘가 다섯이 아니다: \(statuses)")
    // 글자 규칙은 메시지 본문과 같은 판정 함수 — 차단 목록이 두 벌이면 갈린다.
    #expect(body.contains("public.is_message_body(v_probe)"))
    // 길이는 상수 함수 하나에서(리터럴 40 을 본문에 다시 적지 않는다).
    #expect(body.contains("public.status_message_max_length()"))
    #expect(!body.contains(" 40"), "본문에 40 을 리터럴로 적었다 — status_message_max_length() 하나만 본다")
    // 글자 규칙이 길이보다 먼저다(41자 + 방향 제어 → not_text).
    let notText = try #require(body.range(of: "'not_text'"))
    let tooLong = try #require(body.range(of: "'too_long'"))
    #expect(notText.lowerBound < tooLong.lowerBound, "길이 판정이 글자 규칙보다 앞이다")
    // 정규화: NFC → 줄바꿈류 묶음 접기 → btrim.
    #expect(body.contains("normalize(coalesce(p_text, ''), nfc)"))
    #expect(flat.contains("create or replace function public.status_message_max_length()"))
    #expect(flat.contains("select 40"))
}

// MARK: - ③ app_user_directory

@Test
func 사람_찾기_명부는_상태메시지를_맨_끝_칸으로_싣고_가시성과_차단을_그대로_지킨다() throws {
    let (_, flat) = try smSQL()
    #expect(flat.contains("drop function if exists public.app_user_directory();"),
            "반환 칸이 바뀌는데 drop 이 없다(42P13)")
    let body = try #require(smFunctionBody("app_user_directory", in: flat))
    #expect(body.contains(
        "returns table(user_id uuid, display_name text, avatar_url text, is_working boolean, message_capable boolean, center text, status_message text)"
    ), "반환 칸 끝이 status_message 가 아니다(클라 디코더는 키를 골라 읽지만 순서도 계약이다)")
    for line in [
        "where auth.uid() is not null",
        "and p.id <> auth.uid()",
        "and public.same_visibility(auth.uid(), p.id)",
        "and not public.blocked_between(auth.uid(), p.id)",
        "order by is_working desc, coalesce(p.display_name, '사용자')",
        "p.center, p.status_message from public.profiles p",
        "stable security definer",
        "set search_path to 'public'",
    ] {
        #expect(body.contains(line), "app_user_directory 에 '\(line)' 이 없다")
    }
    // drop+create 가 지운 ACL 을 되살린다 — create 는 PUBLIC 에 실행권을 준다.
    for grant in [
        "revoke all on function public.app_user_directory() from public;",
        "revoke all on function public.app_user_directory() from anon;",
        "grant execute on function public.app_user_directory() to authenticated;",
        "grant execute on function public.app_user_directory() to service_role;",
    ] {
        #expect(flat.contains(grant), "ACL 복원 줄 '\(grant)' 이 없다")
    }
    #expect(!flat.contains("grant execute on function public.app_user_directory() to anon"))
    // 교체 전후 불변(전 사용자의 눈) 단언이 살아 있다.
    #expect(flat.contains("_sm_dir_before") && flat.contains("except all"), "교체 전후 multiset 불변 단언이 없다")
}

@Test
func 새_파일은_상태메시지_밖의_함수를_다시_정의하지_않는다() throws {
    let (_, flat) = try smSQL()
    // V0333 이 지키는 아홉 함수 중 이 파일이 다시 정의하는 것은 app_user_directory 하나뿐이다(V0333 허용 목록에 등록).
    for function in ["send_message", "message_history", "message_unread_summary", "gomoku_lobby", "gomoku_challenge",
                     "gomoku_respond", "poke_user", "ultra_poke_user", "take_pokes", "report_content", "work_tick"] {
        #expect(smFunctionBody(function, in: flat) == nil, "\(function) 을 다시 정의했다 — 이 파일의 범위가 아니다")
    }
    // 새 표 · FK 를 만들지 않는다(PostgREST 임베드 모호성은 FK 로만 생긴다).
    #expect(!flat.contains("create table public."), "새 표를 만든다")
    #expect(!flat.contains("references "), "FK 를 만든다 — 임베드 모호성(PGRST201)을 따져라")
}

// MARK: - ④ 클라와 서버가 같은 눈금

@Test
func 클라_상한과_정규화_집합이_서버와_같다() throws {
    let (raw, flat) = try smSQL()
    #expect(CheckCoreShared.statusMessageMaxLength == 40)
    #expect(StatusMessage.maxLength == 40)
    #expect(flat.contains("returns integer language sql immutable parallel safe as $max_len$ select 40 $max_len$"))
    // 줄바꿈류·앞뒤 공백 글자 집합(서버 식) — 클라 `StatusMessage.sanitized` 가 같은 집합을 쓴다(머리말 ②③).
    #expect(raw.contains(#"U&'[\0020]*[\0009\000a\000b\000c\000d\0085\2028\2029][\0020\0009\000a\000b\000c\000d\0085\2028\2029]*'"#))
    #expect(raw.contains(#"U&'\0020\0009\000a\000b\000c\000d\00a0\200b\feff\3000'"#))
    // 같은 사실을 클라 쪽에서: 서버 프로브 ① 의 입력이 클라 정규화에서 같은 값이 된다.
    #expect(StatusMessage.sanitized("  점심 \r\n \r\n먹으러\t가요  ") == "점심 먹으러 가요")
    #expect(StatusMessage.sanitized("점심  먹자") == "점심  먹자")
}
