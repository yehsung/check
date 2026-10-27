import Foundation
import Testing

// v0.3.64 — 서버 마이그레이션 계약(20261023120000_match_watchers.sql): 관전자 수 + 테트리스 관전.
//
// 마이그레이션은 **적용 시점에 자기를 증명한다**(§11 사후 단언 · §12 흐름 프로브 13건 — 어긋나면 raise
// exception 으로 통째 롤백). 그러니 여기서 또 "서버가 센다"를 흉내 내는 건 값이 없다. 이 파일이 지키는 것은
// 그 단언들과, **사람 손이 조용히 깨뜨릴 수 있는 네 가지**다:
//
//   ① 쓰기가 관전 RPC 안으로 기어들어 가는 것 — gomoku_watch · chess_watch 는 **배포 가드가 본문을
//      토큰으로 검사**한다(20260930120000 §7(6) · 20261005160000 §10). insert/update/delete/for update/
//      realtime.send 가 한 글자라도 들어가면 그 파일들이 스스로 멈춘다. 그래서 등록은 별도 함수여야 하고,
//      이 파일은 그 두 함수를 **재정의하지 않아야** 한다.
//   ② 참가자 제외 게이트가 사라지는 것 — 대국자가 자기 판을 보면 "1명이 보고 있어요" 가 뜬다(자기 자신).
//   ③ 베껴 온 로비·상태 빌더 본문이 **원본에서 흘러내리는 것** — 이 파일은 여섯 함수를 통째로 재정의한다.
//      누가 여기서만 한 줄 고치면 원본 파일과 갈라지고, 다음 사람이 원본을 복사해 오는 순간 그 수정이
//      조용히 사라진다. 그래서 **원본 파일 본문 + watchers 한 줄**과 바이트까지 같은지 여기서 잰다.
//      (서버의 §1/§11(3) 은 '운영 본문' 과 대조한다 — 저장소 안에서의 어긋남은 여기서만 잡힌다.)
//   ④ 인자에서 DEFAULT 가 빠지는 것 — 옛 앱의 `{}` 호출이 PGRST202 다.

private let v0364Migration = "20261023120000_match_watchers.sql"
private let v0364GomokuWatchMigration = "20260930120000_gomoku_ranking_watch.sql"   // gomoku_lobby 최신 정의도 여기다
private let v0364GomokuStateMigration = "20260916220000_gomoku_center.sql"
private let v0364ChessMigration = "20261005160000_chess_duel.sql"
private let v0364TetrisMigration = "20261021120000_tetris_duel.sql"

private struct V0364Error: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 라 git worktree 에는 없다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫
/// 디렉토리를 잡는다(V0313·V0338 과 같은 방식). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다(뮤테이션 하네스의 문).
private func v0364MigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw V0364Error("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw V0364Error("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

private func v0364Raw(_ name: String) throws -> String {
    let file = try v0364MigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw V0364Error("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
///
/// ⚠️ 이 마이그레이션에는 **문자열 리터럴 안에 `--`** 가 있다(`'--[^' || chr(10) || ']*'` — §11 이 pg_proc.prosrc
/// 에서 주석을 걷을 때 쓰는 패턴). 이 헬퍼는 그 줄을 거기서 자른다. 그래서 걷어낸 텍스트에서는 그 줄에
/// 걸리는 단언을 두지 않는다(본문 바이트 대조는 **원문**으로 한다).
private func v0364Strip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// `create [or replace] function public.<헤더>` 부터 그 함수의 달러 인용 본문 끝까지(**본문만**).
/// 태그는 파일마다 다르다(`$fn$` · `$function$`) — `as $태그$` 를 읽어 그 태그로 닫는다.
private func v0364Body(_ sql: String, header: String, in file: String) throws -> String {
    let occurrences = sql.components(separatedBy: header).count - 1
    guard occurrences == 1 else {
        throw V0364Error("\(file): 함수 헤더 \"\(header)\" 가 \(occurrences) 번 나온다(기대 1)")
    }
    guard let start = sql.range(of: header)?.lowerBound else { throw V0364Error("\(file): 함수 헤더가 없다: \(header)") }
    let rest = sql[start...]
    guard let asRange = rest.range(of: "as $", options: .caseInsensitive) else {
        throw V0364Error("\(file) \(header): 달러 인용 시작을 못 찾았다")
    }
    let tagStart = rest.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = rest[rest.index(after: tagStart)...].firstIndex(of: "$") else {
        throw V0364Error("\(file) \(header): 달러 인용 태그가 안 닫힌다")
    }
    let tag = String(rest[tagStart...tagEnd])
    let bodyStart = rest.index(after: tagEnd)
    guard let close = rest.range(of: tag, range: bodyStart..<rest.endIndex) else {
        throw V0364Error("\(file) \(header): 달러 인용 종료 태그 \(tag) 가 없다")
    }
    return String(rest[bodyStart..<close.lowerBound])
}

private func v0364Count(_ haystack: String, _ needle: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

// MARK: - ① 체인에서의 자리

@Test("관전자 마이그레이션은 오목 관전·체스·테트리스 파일 뒤에 온다")
func v0364MigrationComesAfterItsSources() throws {
    let names = try FileManager.default
        .contentsOfDirectory(at: try v0364MigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
    #expect(names.count > 100, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
    let index = try #require(names.firstIndex(of: v0364Migration), "\(v0364Migration) 이 체인에 없다")
    for source in [v0364GomokuWatchMigration, v0364GomokuStateMigration, v0364ChessMigration, v0364TetrisMigration] {
        let at = try #require(names.firstIndex(of: source), "\(source) 이 체인에 없다")
        #expect(at < index, Comment(rawValue: "\(source) 보다 앞에 있다 — 얹을 대상이 아직 안 만들어졌다"))
    }
}

// MARK: - ② 표 · 상수 · 새 함수 일곱

@Test("표 match_watchers 는 RLS 를 켜고 정책 0 · 클라 표 권한 0 · auth.users cascade FK 로 선다")
func v0364WatcherTableIsLockedDown() throws {
    let sql = v0364Strip(try v0364Raw(v0364Migration))
    #expect(sql.contains("create table if not exists public.match_watchers ("),
            "표를 if not exists 로 만들지 않는다 — 재적용에서 죽는다")
    #expect(sql.contains("game         text        not null check (game in ('gomoku', 'chess', 'tetris'))"))
    #expect(sql.contains("user_id      uuid        not null references auth.users(id) on delete cascade"),
            "탈퇴자 행이 남아 관전자 수를 부풀린다")
    #expect(sql.contains("primary key (game, match_id, user_id)"), "upsert 가 설 기본 키가 없다")
    #expect(sql.contains("create index if not exists match_watchers_fresh_idx"))
    #expect(sql.contains("revoke all on table public.match_watchers from public, anon, authenticated;"))
    #expect(sql.contains("alter table public.match_watchers enable row level security;"))
    #expect(!sql.contains("create policy"), "정책을 만들면 definer RPC 전용 규약이 깨진다")
    // 사후 단언이 그 넷을 실제로 되묻는지(단언이 사라지면 규약은 주석일 뿐이다)
    #expect(sql.contains("c.relrowsecurity"))
    #expect(sql.contains("from pg_policies where schemaname = 'public' and tablename = 'match_watchers'"))
    #expect(sql.contains("has_table_privilege('authenticated', 'public.match_watchers', v_tok)"))
    #expect(sql.contains("c.confrelid = 'auth.users'::regclass and c.confdeltype = 'c'"))
}

@Test("상수 둘은 immutable·PUBLIC 유지이고 값은 15초·180초다")
func v0364ConstantsAreImmutableAndPublic() throws {
    let sql = v0364Strip(try v0364Raw(v0364Migration))
    #expect(sql.contains("create or replace function public.match_watch_ttl_seconds()\nreturns int language sql immutable as $fn$ select 15 $fn$;"))
    #expect(sql.contains("create or replace function public.tetris_watch_tail_seconds()\nreturns int language sql immutable as $fn$ select 180 $fn$;"))
    #expect(sql.contains("grant execute on function public.match_watch_ttl_seconds()  to public, anon, authenticated, service_role;"))
    #expect(sql.contains("grant execute on function public.tetris_watch_tail_seconds() to public, anon, authenticated, service_role;"))
    // 꼬리는 체스와 **같아야** 한다 — 상수 값만 보면 180 을 30일로 바꾼 사본도 통과한다.
    #expect(sql.contains("public.tetris_watch_tail_seconds() <> public.chess_watch_tail_seconds()"),
            "테트리스 꼬리가 체스 꼬리와 같은지 되묻지 않는다")
}

@Test("새 함수 일곱이 다 있고 속성·실행권·전 인자 DEFAULT 가 계약대로다")
func v0364NewFunctionsExistWithContract() throws {
    let sql = v0364Strip(try v0364Raw(v0364Migration))

    // 세기: stable · definer · 내부 전용(authenticated 까지 회수)
    #expect(sql.contains("create or replace function public.match__watchers(p_game text, p_match_id uuid)"))
    #expect(sql.contains("revoke all on function public.match__watchers(text, uuid) from public, anon, authenticated;"))
    #expect(sql.contains("grant execute on function public.match__watchers(text, uuid) to service_role;"))
    #expect(!sql.contains("grant execute on function public.match__watchers(text, uuid) to authenticated"),
            "세는 함수에 클라 실행권을 주면 임의 판의 관전자 수를 캐물을 수 있다")

    // 등록: volatile · definer · 로그인한 사람만
    #expect(sql.contains("create or replace function public.match_watch_ping(p_game text, p_match_id uuid)"))
    #expect(sql.contains("revoke all on function public.match_watch_ping(text, uuid) from public, anon;"))
    #expect(sql.contains("grant execute on function public.match_watch_ping(text, uuid) to authenticated, service_role;"))

    // 청소: service_role 전용 + cron 5분
    #expect(sql.contains("create or replace function public.match_watchers_purge()"))
    #expect(sql.contains("revoke all on function public.match_watchers_purge() from public, anon, authenticated;"))
    #expect(sql.contains("grant execute on function public.match_watchers_purge() to service_role;"))
    #expect(sql.contains("'match-watchers-purge',"))
    #expect(sql.contains("'*/5 * * * *',"))
    #expect(sql.contains("select public.match_watchers_purge();"))
    #expect(sql.contains("public.match_watch_ttl_seconds() * 100"), "청소 기준이 TTL 100배가 아니다")

    // 관전 RPC 넷: 인자가 전부 DEFAULT 여야 옛 앱의 {} 호출이 산다
    let signatures = [
        "create or replace function public.tetris_watch(p_protocol int default 0, p_match_id uuid default null)",
        "create or replace function public.gomoku_watch_live(p_protocol int default 0, p_match_id uuid default null,\n                                                    p_since_seq int default 0)",
        "create or replace function public.chess_watch_live(p_protocol int default 0, p_match_id uuid default null,\n                                                   p_since_seq int default 0)",
        "create or replace function public.tetris_watch_live(p_protocol int default 0, p_match_id uuid default null)",
    ]
    for signature in signatures {
        #expect(sql.contains(signature), Comment(rawValue: "시그니처가 다르다(전 인자 DEFAULT): \(signature.prefix(70))"))
    }
    for fn in ["public.tetris_watch(integer, uuid)", "public.gomoku_watch_live(integer, uuid, integer)",
               "public.chess_watch_live(integer, uuid, integer)", "public.tetris_watch_live(integer, uuid)"] {
        #expect(sql.contains("revoke all on function \(fn) from public, anon;"),
                Comment(rawValue: "\(fn) 의 anon 회수가 없다"))
        #expect(sql.contains("grant execute on function \(fn) to authenticated, service_role;"),
                Comment(rawValue: "\(fn) 의 grant 가 없다"))
    }

    // 멱등 규약: 이 파일은 운영 객체를 떨어뜨리지 않는다(pg_temp 작업 표만 지운다).
    #expect(!sql.contains("drop function"), "drop function 은 멱등 규약 위반이다")
    #expect(!sql.contains("drop table if exists public."), "운영 표를 떨어뜨린다")
    #expect(v0364Count(sql, "drop table if exists pg_temp.") == 6, "pg_temp 작업 표 3개를 앞뒤로 정리하지 않는다")
}

// MARK: - ③ 참가자 제외 게이트(이게 없으면 내 판에 "1명이 보고 있어요" 가 뜬다)

@Test("match_watch_ping 은 쓰기 전에 참가자를 거르고 세 게임 모두 숨김 격리 두 조건을 건다")
func v0364PingExcludesPlayersAndKeepsVisibilityGate() throws {
    let sql = try v0364Raw(v0364Migration)
    let body = v0364Strip(try v0364Body(sql, header: "create or replace function public.match_watch_ping(", in: v0364Migration))

    // 참가자 판정: 오목은 black/white, 체스·테트리스는 challenger/opponent
    #expect(body.contains("coalesce(uid in (g.black, g.white), false)"), "오목 참가자 칸(black/white)을 안 본다")
    #expect(v0364Count(body, "coalesce(uid in (g.challenger, g.opponent), false)") == 2,
            "체스·테트리스 참가자 칸(challenger/opponent)을 둘 다 보지 않는다")

    // **쓰기 전에** 돌려보낸다 — 분기가 insert 뒤로 밀리면 참가자 행이 생긴다
    let selfBranch = try #require(body.range(of: "if v_self then"), "참가자 분기가 없다")
    let insert = try #require(body.range(of: "insert into public.match_watchers"), "upsert 가 없다")
    #expect(selfBranch.lowerBound < insert.lowerBound,
            "참가자 분기가 insert 뒤에 있다 — 대국자 행이 생겨 자기 판에 '1명이 보고 있어요' 가 뜬다")

    // 게이트: 세 게임 × 두 사람 = 6회. 하나라도 빠지면 그 게임만 숨김 격리가 샌다.
    #expect(v0364Count(body, "public.same_visibility(uid, g.challenger)") == 3)
    #expect(v0364Count(body, "public.same_visibility(uid, g.opponent)") == 3)
    #expect(v0364Count(body, "g.status = 'active'") == 3)
    #expect(body.contains("interval '3 minutes'"), "오목 꼬리가 gomoku_watch 와 같은 글자가 아니다")
    #expect(body.contains("public.chess_watch_tail_seconds()"))
    #expect(body.contains("public.tetris_watch_tail_seconds()"))
    #expect(body.contains("p_game not in ('gomoku', 'chess', 'tetris')"), "모르는 게임 이름을 안 거른다")

    // 쓰는 자리는 둘뿐이다(upsert 하나 · 그 판의 TTL 밖 행 지우기 하나)
    #expect(v0364Count(body, "insert into") == 1)
    #expect(v0364Count(body, "delete from") == 1)
    #expect(body.contains("on conflict (game, match_id, user_id) do update set last_seen_at = excluded.last_seen_at"))

    // 세는 함수는 읽기 전용이고 TTL 을 쓴다
    let counter = v0364Strip(try v0364Body(sql, header: "create or replace function public.match__watchers(", in: v0364Migration))
    for forbidden in ["insert ", "update ", "delete ", "for update"] {
        #expect(!counter.contains(forbidden), Comment(rawValue: "match__watchers 본문에 \"\(forbidden)\" 가 있다"))
    }
    #expect(counter.contains("public.match_watch_ttl_seconds()"), "죽은 관전자까지 센다")

    // 마이그레이션 자신도 그 불변식을 적용 시점에 되묻는다(단언이 사라지면 여기 혼자 남는다)
    let whole = v0364Strip(sql)
    #expect(whole.contains("③ 참가자가 관전자로 세어졌다"))
    #expect(whole.contains("③ 참가자 행이 표에 생겼다"))
}

// MARK: - ④ 테트리스 관전은 읽기 전용이다

@Test("tetris_watch 본문에 쓰기·잠금·정산 토큰이 없고 게이트·응답 키가 다 있다")
func v0364TetrisWatchIsReadOnly() throws {
    let sql = try v0364Raw(v0364Migration)
    let body = v0364Strip(try v0364Body(sql, header: "create or replace function public.tetris_watch(p_protocol", in: v0364Migration))

    for forbidden in ["insert ", "update ", "delete ", "for update", "pg_advisory", "realtime.send",
                      "tetris__settle(", "tetris__due(", "tetris__ring(", "'ruby_balance'", "'seed'",
                      "ultra_wallet:",
                      // ★ 비로그인 어휘는 테트리스 가족의 것(not_signed_in)이다. 오목·체스 관전의 unauthorized 가
                      //   섞여 들어오면 클라의 테트리스 전선이 못 알아보고 '알 수 없는 실패' 로 접는다.
                      "'unauthorized'"] {
        #expect(!body.contains(forbidden),
                Comment(rawValue: "tetris_watch 본문에 \"\(forbidden)\" 가 있다 — 관전은 읽기 전용이다"))
    }
    // 대기 신청은 관전 대상이 아니다. 응답 키 'pending'(대기 방해 줄)과 겹치니 **상태 비교 글자**로 본다.
    #expect(!body.contains("= 'pending'"), "pending 상태를 열면 제3자가 누가 누구에게 신청했는지 본다")

    for required in ["'not_found'", "'not_signed_in'", "'unsupported_client'",
                     "g.status = 'active'", "g.status = 'finished'",
                     "public.tetris_watch_tail_seconds()",
                     "public.same_visibility(uid, m.challenger)", "public.same_visibility(uid, m.opponent)",
                     "least(m.challenger, m.opponent)", "greatest(m.challenger, m.opponent)",
                     "coalesce(p_protocol, 0) < public.tetris_protocol()",
                     "'board', pl.board", "'topped_out'", "'last_seen_ms'",
                     "'result', m.result", "'winner', m.winner", "'reason', m.end_reason"] {
        #expect(body.contains(required),
                Comment(rawValue: "tetris_watch 본문에 \"\(required)\" 가 없다 — 게이트·자리 순서·응답 키 계약이 깨졌다"))
    }
    // board 를 가공하지 않는다(길이·문자 집합은 표의 CHECK 가 이미 지킨다)
    #expect(!body.contains("substr(pl.board"), "board 를 잘라 보낸다 — tetris_players.board 그대로여야 한다")

    // 끝난 판의 결과를 지어내지 않는다: 결과 네 칸은 전부 행에서 그대로 온다.
    // ★ winner 가 **서버에서** 와야 한다 — 관전자는 두 사람을 uuid 오름차순 a/b 자리로만 받으므로
    //   result('challenger_win')만으로는 누가 이겼는지 못 가린다(클라가 역산하면 거짓말하는 자리다).
    #expect(body.contains("'finished_ms', public.tetris__ms(m.finished_at)"))
    #expect(!body.contains("'time_cap'"), "관전이 사유를 지어낸다")

    // 흐름 프로브가 그것을 결과로도 되묻는다
    let whole = v0364Strip(sql)
    #expect(whole.contains("⑪ 테트리스 관전이 썼다"))
    #expect(whole.contains("⑦ 상한을 넘긴 판인데 관전이 결과를 지어냈거나 값이 다르다"))
    #expect(whole.contains("⑦ 꼬리 안에서 끝난 판의 결과·승자가 다르다"),
            "꼬리 안에서 끝난 판의 승자를 결과로 되묻는 프로브가 없다")
    #expect(whole.contains("⑧ 클레임 없는 호출이 not_signed_in 이 아니다"),
            "비로그인 어휘를 결과로 되묻는 프로브가 없다 — 토큰만 보면 두 낱말이 다 들어 있는 사본도 통과한다")
}

@Test("이 파일은 배포 가드가 걸린 gomoku_watch·chess_watch 본문을 건드리지 않는다")
func v0364DoesNotRedefineGuardedWatchRPCs() throws {
    let sql = v0364Strip(try v0364Raw(v0364Migration))
    #expect(!sql.contains("create or replace function public.gomoku_watch(p_protocol"),
            "gomoku_watch 를 재정의한다 — 20260930120000 §7(6) 의 토큰 가드가 멈춘다")
    #expect(!sql.contains("create or replace function public.chess_watch(p_protocol"),
            "chess_watch 를 재정의한다 — 20261005160000 §10 의 토큰 가드가 멈춘다")
    // 껍데기는 원본을 그대로 부르고 ok 일 때만 등록한다
    for (header, call, ping) in [
        ("create or replace function public.gomoku_watch_live(",
         "public.gomoku_watch(p_protocol, p_match_id, p_since_seq)", "public.match_watch_ping('gomoku', p_match_id)"),
        ("create or replace function public.chess_watch_live(",
         "public.chess_watch(p_protocol, p_match_id, p_since_seq)", "public.match_watch_ping('chess', p_match_id)"),
        ("create or replace function public.tetris_watch_live(",
         "public.tetris_watch(p_protocol, p_match_id)", "public.match_watch_ping('tetris', p_match_id)"),
    ] {
        let body = v0364Strip(try v0364Body(try v0364Raw(v0364Migration), header: header, in: v0364Migration))
        #expect(body.contains(call), Comment(rawValue: "\(header) 가 원본 관전 RPC 를 안 부른다"))
        #expect(body.contains(ping), Comment(rawValue: "\(header) 가 생존 신호를 안 올린다"))
        #expect(body.contains("if v->>'status' = 'ok' then"),
                Comment(rawValue: "\(header) 가 ok 가 아닐 때도 등록한다 — 못 보는 판에 발자국이 남는다"))
    }
}

// MARK: - ⑤ 로비 셋 · 상태 빌더 셋 — 원본 본문 + watchers 한 줄과 바이트까지 같다

/// (새 파일 안의 함수 본문) == (원본 파일 안의 같은 함수 본문에 `watchers` 한 줄만 끼운 것).
/// 바이트 대조라 **주석 한 글자**만 달라도 빨갛다 — 그게 요점이다(베껴 온 본문이 원본에서 흘러내리는 것을 막는다).
private struct V0364Patch {
    let label: String
    let sourceFile: String
    let header: String
    let newHeader: String
    let old: String
    let new: String
}

/// 줄들을 그대로 이어 붙인다(끝에 줄바꿈 하나). ★ Swift 의 `"""` 여러 줄 리터럴은 닫는 따옴표의 들여쓰기를
/// 모든 줄에서 **걷어낸다** — SQL 들여쓰기를 바이트까지 맞춰야 하는 여기서는 쓸 수 없다.
private func v0364Lines(_ lines: String...) -> String { lines.joined(separator: "\n") + "\n" }

private let v0364Patches: [V0364Patch] = [
    V0364Patch(label: "gomoku_lobby",
               sourceFile: v0364GomokuWatchMigration,
               header: "CREATE OR REPLACE FUNCTION public.gomoku_lobby(p_protocol integer DEFAULT 0)",
               newHeader: "CREATE OR REPLACE FUNCTION public.gomoku_lobby(p_protocol integer DEFAULT 0)",
               old: v0364Lines(
                   "               'stake', g.stake,",
                   "               'started_ms', public.gomoku__ms(g.accepted_at)) as obj"),
               new: v0364Lines(
                   "               'stake', g.stake,",
                   "               'watchers', public.match__watchers('gomoku', g.id),",
                   "               'started_ms', public.gomoku__ms(g.accepted_at)) as obj")),
    V0364Patch(label: "chess_lobby",
               sourceFile: v0364ChessMigration,
               header: "create or replace function public.chess_lobby(p_protocol int default 0)",
               newHeader: "create or replace function public.chess_lobby(p_protocol int default 0)",
               old: v0364Lines(
                   "               'stake', g.stake,",
                   "               'started_ms', public.chess__ms(g.accepted_at)) as obj"),
               new: v0364Lines(
                   "               'stake', g.stake,",
                   "               'watchers', public.match__watchers('chess', g.id),",
                   "               'started_ms', public.chess__ms(g.accepted_at)) as obj")),
    V0364Patch(label: "tetris_lobby",
               sourceFile: v0364TetrisMigration,
               header: "create or replace function public.tetris_lobby(p_protocol int default 0)",
               newHeader: "create or replace function public.tetris_lobby(p_protocol int default 0)",
               old: v0364Lines(
                   "               'stake', g.stake,",
                   "               'started_at_ms', public.tetris__ms(coalesce(g.start_at, g.accepted_at))) as obj"),
               new: v0364Lines(
                   "               'stake', g.stake,",
                   "               'watchers', public.match__watchers('tetris', g.id),",
                   "               'started_at_ms', public.tetris__ms(coalesce(g.start_at, g.accepted_at))) as obj")),
    V0364Patch(label: "gomoku__state",
               sourceFile: v0364GomokuStateMigration,
               header: "create or replace function public.gomoku__state(p_match_id uuid, p_uid uuid, p_since_seq int default 0)",
               newHeader: "create or replace function public.gomoku__state(p_match_id uuid, p_uid uuid, p_since_seq int default 0)",
               old: v0364Lines(
                   "                                 when p_uid = m.white then m.black_auto_streak else 0 end,",
                   "    'server_now_ms', public.gomoku__ms(clock_timestamp()));"),
               new: v0364Lines(
                   "                                 when p_uid = m.white then m.black_auto_streak else 0 end,",
                   "    'watchers', public.match__watchers('gomoku', p_match_id),",
                   "    'server_now_ms', public.gomoku__ms(clock_timestamp()));")),
    V0364Patch(label: "chess__state",
               sourceFile: v0364ChessMigration,
               header: "create or replace function public.chess__state(p_match_id uuid, p_uid uuid, p_since_seq int default 0)",
               newHeader: "create or replace function public.chess__state(p_match_id uuid, p_uid uuid, p_since_seq int default 0)",
               old: v0364Lines(
                   "    'legal_moves', v_legal,",
                   "    'server_now_ms', public.chess__ms(clock_timestamp()));"),
               new: v0364Lines(
                   "    'legal_moves', v_legal,",
                   "    'watchers', public.match__watchers('chess', p_match_id),",
                   "    'server_now_ms', public.chess__ms(clock_timestamp()));")),
    V0364Patch(label: "tetris__state",
               sourceFile: v0364TetrisMigration,
               header: "create or replace function public.tetris__state(p_match_id uuid, p_uid uuid)",
               newHeader: "create or replace function public.tetris__state(p_match_id uuid, p_uid uuid)",
               old: v0364Lines(
                   "    'end_reason', m.end_reason,",
                   "    'ruby_balance', v_bal);"),
               new: v0364Lines(
                   "    'end_reason', m.end_reason,",
                   "    'watchers', public.match__watchers('tetris', p_match_id),",
                   "    'ruby_balance', v_bal);")),
]

@Test("로비 셋·상태 빌더 셋은 원본 파일 본문에 watchers 한 줄만 끼운 것과 바이트까지 같다")
func v0364CopiedBodiesEqualSourcePlusOneLine() throws {
    let mine = try v0364Raw(v0364Migration)
    for patch in v0364Patches {
        let source = try v0364Raw(patch.sourceFile)
        let before = try v0364Body(source, header: patch.header, in: patch.sourceFile)
        let after = try v0364Body(mine, header: patch.newHeader, in: v0364Migration)
        #expect(v0364Count(before, patch.old) == 1,
                Comment(rawValue: "\(patch.label): 원본(\(patch.sourceFile))에서 끼울 자리를 \(v0364Count(before, patch.old)) 번 찾았다(기대 1)"))
        #expect(v0364Count(before, patch.new) == 0,
                Comment(rawValue: "\(patch.label): 원본에 이미 watchers 가 있다 — 치환표가 낡았다"))
        let expected = before.replacingOccurrences(of: patch.old, with: patch.new)
        #expect(after == expected,
                Comment(rawValue: "\(patch.label) 의 본문이 '원본 + watchers 한 줄' 과 다르다 — 베껴 온 본문이 \(patch.sourceFile) 에서 흘러내렸다"))
    }
}

@Test("여섯 함수 각각이 자기 게임의 세기 함수를 정확히 한 번만 부른다")
func v0364EachBuilderCountsItsOwnGameOnce() throws {
    let mine = try v0364Raw(v0364Migration)
    let expected: [(String, String)] = [
        ("CREATE OR REPLACE FUNCTION public.gomoku_lobby(", "public.match__watchers('gomoku', g.id)"),
        ("create or replace function public.chess_lobby(", "public.match__watchers('chess', g.id)"),
        ("create or replace function public.tetris_lobby(", "public.match__watchers('tetris', g.id)"),
        ("create or replace function public.gomoku__state(", "public.match__watchers('gomoku', p_match_id)"),
        ("create or replace function public.chess__state(", "public.match__watchers('chess', p_match_id)"),
        ("create or replace function public.tetris__state(", "public.match__watchers('tetris', p_match_id)"),
    ]
    for (header, token) in expected {
        let body = v0364Strip(try v0364Body(mine, header: header, in: v0364Migration))
        #expect(v0364Count(body, token) == 1,
                Comment(rawValue: "\(header) 본문의 \"\(token)\" 가 \(v0364Count(body, token)) 회다(기대 1)"))
        #expect(v0364Count(body, "public.match__watchers(") == 1,
                Comment(rawValue: "\(header) 본문이 남의 게임 이름까지 센다"))
    }
}

// MARK: - ⑥ 적용 시점 단언이 살아 있는가(이 파일 혼자 남으면 규약은 주석일 뿐이다)

@Test("적용 시점 가드가 그대로다 — 직전 본문 대조 · 프로브 13건 · 센티널 롤백")
func v0364DeployTimeGuardsAreIntact() throws {
    let sql = v0364Strip(try v0364Raw(v0364Migration))
    #expect(sql.contains("create table pg_temp.mw_before as"), "적용 직전 본문을 안 적는다 — 치환 대조가 성립하지 않는다")
    #expect(sql.contains("replace(r.before_src, r.old_txt, r.new_txt) <> v_raw"),
            "\"직전 본문 + 치환 = 지금 본문\" 을 안 되묻는다")
    #expect(sql.contains("v_expected  constant int := 13;"), "프로브 기대 건수가 13 이 아니다")
    #expect(sql.contains("raise exception 'MATCH_WATCHERS_PROBE_ROLLBACK';"), "센티널 롤백이 없다 — 프로브 행이 운영에 남는다")
    #expect(sql.contains("프로브가 % 건만 돌았다"), "프로브가 조용히 no-op 이 되는 것을 안 막는다")
    #expect(sql.contains("notify pgrst, 'reload schema';"), "스키마 리로드 통지가 없다 — PostgREST 가 새 RPC 를 모른다")
    // 운영 쓰기 금지 규약: 이 파일은 사용자 표를 손대지 않는다(프로브는 롤백되는 블록 안에서만 쓴다).
    #expect(!sql.contains("update public.profiles set ruby_balance"), "이 마이그레이션이 지갑을 건드린다")
}
