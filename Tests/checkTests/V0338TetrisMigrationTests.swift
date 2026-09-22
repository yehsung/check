import Foundation
import Testing

// v0.3.38 — 서버 마이그레이션 계약(20260923140000_minigame_tetris.sql): 셋째 미니게임 **테트리스**.
//
// 이 파일이 지키는 것은 "테트리스가 돈다"가 아니라 **"기존 두 게임이 안 다쳤다"** 와 **"넓히기가 열어젖히기로
// 둔갑하지 않았다"** 이다. 행동은 마이그레이션 자신이 증명한다 — 파일 안의 §A 어휘 가드 · §G 사후 단언(카탈로그와
// 실호출) · §H 행동 프로브(임시표에 같은 CHECK·같은 트리거를 붙여 쓴다)가 적용 시점에 자기를 되묻고, 어긋나면
// raise exception 으로 통째로 롤백한다. 여기서 보는 것은 **그 단언들과 그 문장들이 사라지거나 넓어지는 것**이다.
//
// 특히 위험한 다섯 가지(전부 아래에 단언이 하나씩 있다):
//   ① 좁은 인라인 CHECK 을 **이름으로 짐작해** 지우려다 조용히 실패하는 것 — 배포는 초록인데 tetris 점수가 전부 23514.
//   ② 넓은 제약을 나중에 붙이는 것(fail-open) — 사이 구간에 상한이 통째로 없다.
//   ③ 칸의 `best_score <= 1000` 을 걷어내면서 **플래피의 유일한 절대 상한**을 아무 데로도 안 옮기는 것.
//   ④ `minigame_score_cap` 의 public EXECUTE 를 회수하는 것 — invoker 트리거라 전원의 점수 쓰기가 42501.
//   ⑤ 상 함수를 옛 판본에서 고치거나 `p_day` 기본값을 잃는 것 — 2026-09-12 PGRST202 의 재현.

private let t38TetrisMigration = "20260923140000_minigame_tetris.sql"
private let t38ScoresMigration = "20260908090000_minigame_scores.sql"
private let t38RoundTokenMigration = "20260914010000_minigame_round_token.sql"
private let t38HiddenAccountsMigration = "20260917160000_hidden_accounts.sql"

private struct T38Error: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 라 git worktree 에는 없다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫
/// 디렉토리를 잡는다(V0313·V0333 과 같은 방식). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다 — 뮤테이션 하네스가
/// 공유 체크아웃의 실물을 안 건드리고 **사본에 결함을 심어** 이 단언들이 실제로 빨개지는지 보는 문이다.
private func t38MigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw T38Error("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw T38Error("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
///
/// ⚠️ 이 마이그레이션에는 **문자열 리터럴 안에 `--` 가 네 번** 있다 — §G 가 `pg_proc.prosrc` 에서 주석을 걷어낼 때
/// 쓰는 `'--[^' || chr(10) || ']*'` 패턴이다. 이 헬퍼는 그 줄을 `select regexp_replace(p.prosrc, '` 에서 자른다.
/// 그래서 **그 패턴 자체는 아래에서 raw 원문으로 확인**하고(주석이 걷힌 텍스트에서 찾으면 헛돈다), 걷어낸 텍스트에서는
/// 그 줄에 걸리는 단언을 두지 않는다.
private func t38Strip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func t38Squash(_ text: String) -> String {
    text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
}

private func t38Raw(_ name: String) throws -> String {
    let file = try t38MigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw T38Error("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

private func t38SQL(_ name: String) throws -> String { t38Strip(try t38Raw(name)) }

/// `create [or replace] function public.<헤더>` 부터 그 함수의 달러 인용 본문 끝까지. 태그는 파일마다 다르다
/// (`$$` · `$fn$` · `$function$`) — `as $태그$` 를 읽어 **그 태그로** 닫는다.
private func t38FunctionBody(_ sql: String, header: String) throws -> String {
    guard let start = sql.range(of: header)?.lowerBound else { throw T38Error("함수 헤더가 없다: \(header)") }
    let rest = sql[start...]
    guard let asRange = rest.range(of: "as $") else { throw T38Error("\(header): 달러 인용 시작을 못 찾았다") }
    let tagStart = rest.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = rest[rest.index(after: tagStart)...].firstIndex(of: "$") else {
        throw T38Error("\(header): 달러 인용 태그가 안 닫힌다")
    }
    let tag = String(rest[tagStart...tagEnd])
    let bodyStart = rest.index(after: tagEnd)
    guard let close = rest.range(of: tag, range: bodyStart..<rest.endIndex) else {
        throw T38Error("\(header): 달러 인용 종료 태그 \(tag) 가 없다")
    }
    return String(rest[bodyStart..<close.lowerBound])
}

/// 상 함수 정의 전문(주석을 안 걷은 **원문**). 20260917160000 의 살아 있는 정의와 글자 단위로 대조하려면 원문이어야 한다.
private func t38AwardDefinition(_ raw: String) throws -> String {
    let header = "CREATE OR REPLACE FUNCTION public.minigame_award_daily_prizes(p_day date DEFAULT NULL::date)"
    guard let start = raw.range(of: header)?.lowerBound else { throw T38Error("상 함수 헤더가 없다") }
    let rest = raw[start...]
    guard let open = rest.range(of: "$function$"),
          let close = rest.range(of: "$function$", range: open.upperBound..<rest.endIndex) else {
        throw T38Error("상 함수의 $function$ 짝이 없다")
    }
    return String(rest[rest.startIndex..<close.upperBound])
}

// MARK: - ① 체인에서의 자리

@Test
func 테트리스_마이그레이션은_체인의_마지막이고_원천_세_파일_뒤에_온다() throws {
    let names = try FileManager.default
        .contentsOfDirectory(at: try t38MigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
    #expect(names.count > 30, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
    let index = try #require(names.firstIndex(of: t38TetrisMigration), "\(t38TetrisMigration) 이 체인에 없다")
    for source in [t38ScoresMigration, t38RoundTokenMigration, t38HiddenAccountsMigration] {
        let at = try #require(names.firstIndex(of: source), "\(source) 이 체인에 없다")
        #expect(at < index, "\(source) 보다 앞에 있다 — 넓힐 대상이 아직 안 만들어졌다")
    }
}

// MARK: - ② 어휘·상한 CHECK 확장 (add → drop · 이름을 짐작하지 않는다)

@Test
func 세_표의_어휘와_점수_상한은_넓은_제약을_먼저_붙이고_좁은_것을_정의로_찾아_거둔다() throws {
    let sql = try t38SQL(t38TetrisMigration)

    // 넷 전부. 하나라도 빠지면 rounds → 판 시작 23514 · daily_scores → 제출 23514 ·
    // prizes → 자정 cron 이 터져 그날 **세 게임** 상이 통째로 롤백된다.
    #expect(sql.contains("add constraint minigame_daily_scores_best_score_range\n      check (best_score >= 0 and best_score <= 100000000);"))
    #expect(sql.contains("add constraint minigame_daily_scores_game_known\n      check (game in ('timing_bar','flappy','tetris'));"))
    #expect(sql.contains("add constraint minigame_prizes_game_known\n      check (game in ('timing_bar','flappy','tetris'));"))
    #expect(sql.contains("add constraint minigame_rounds_game_known\n      check (game in ('timing_bar','flappy','tetris'));"))

    // ★ 순서: 넓은 add 가 전부 좁은 drop 보다 **앞**이어야 한다. 뒤집히면 add 실패 시 상한이 통째로 사라진다(fail-open).
    let drop = try #require(sql.range(of: "execute format('alter table %s drop constraint %I', r.rel, r.name)"),
                            "좁은 제약을 execute format 으로 지우는 자리가 없다")
    for added in ["minigame_daily_scores_best_score_range", "minigame_daily_scores_game_known",
                  "minigame_prizes_game_known", "minigame_rounds_game_known"] {
        let add = try #require(sql.range(of: "add constraint \(added)"))
        #expect(add.lowerBound < drop.lowerBound,
                Comment(rawValue: "\(added) 을 좁은 제약 drop 뒤에 붙인다 — 그 사이엔 상한이 없다(fail-open)"))
    }

    // ★ 이름을 짐작하지 않는다. 인라인 CHECK 이름은 Postgres 가 짓는다 — 추측한 이름으로 `drop constraint if exists`
    //   를 쓰면 틀려도 **조용히 성공하고** 좁은 제약을 남긴다(배포는 초록, tetris 점수는 전부 거절).
    #expect(sql.contains("pg_get_constraintdef(c.oid) as def"), "정의를 읽어 찾지 않는다")
    #expect(!sql.contains("drop constraint if exists minigame_daily_scores_game_check"),
            "옛 제약을 이름으로 짐작해 지운다 — 이름이 다르면 조용히 성공하고 좁은 제약이 남는다")
    #expect(!sql.contains("drop constraint if exists minigame_rounds_game_check"))
    #expect(!sql.contains("drop constraint if exists minigame_prizes_game_check"))

    // 사후 단언 셋(붙었다 · 안 남았다 · **상한이 사라지지 않았다**).
    #expect(sql.contains("raise exception '§B 넓은 제약이 %개다(기대 4) — 배포 중단', v_n;"))
    #expect(sql.contains("옛 2게임 목록 제약이 남았다"))
    #expect(sql.contains("옛 best_score 1000 상한이 남았다"))
    #expect(sql.contains("best_score 상한이 통째로 사라졌다"), "fail-open 을 잡는 단언이 없다")

    // 어휘 가드는 **파일이 아니라 표**를 본다(20260913180000:16-18 의 23514 사고 재발 방지).
    for table in ["public.minigame_daily_scores", "public.minigame_prizes", "public.minigame_rounds"] {
        #expect(sql.contains("select string_agg(distinct game, ', ') into v_bad from \(table)\n   where game not in ('timing_bar','flappy','tetris');"),
                Comment(rawValue: "\(table) 의 실제 distinct game 을 안 훑는다"))
    }
}

// MARK: - ③ 게임별 상한은 한 함수가 쥔다 · public EXECUTE 를 회수하지 않는다

@Test
func 점수_상한은_한_함수에_모이고_실행권을_회수하지_않는다() throws {
    let sql = try t38SQL(t38TetrisMigration)

    #expect(sql.contains("create or replace function public.minigame_score_cap(p_game text)\nreturns int language sql immutable as $$"))
    #expect(sql.contains("when 'timing_bar' then 1000"), "타이밍바 상한이 움직였다")
    #expect(sql.contains("when 'flappy'     then 999"), "플래피 상한이 움직였다")
    #expect(sql.contains("when 'tetris'     then 100000000"))
    #expect(sql.contains("else 0"), "모르는 게임의 상한이 0 이 아니면 어휘 밖 점수가 통과한다")

    // ★★ 회수 금지. guard_minigame_score 는 invoker 라(20260908090000:102-104) 여기서 public EXECUTE 를 거두면
    //    **모든 사용자의 모든 점수 쓰기가 42501** 이 된다. grant 는 덧붙이기이지 회수가 아니다.
    #expect(sql.contains("grant execute on function public.minigame_score_cap(text) to authenticated, service_role;"))
    #expect(!sql.contains("on function public.minigame_score_cap(text) from"),
            "minigame_score_cap 의 실행권을 회수한다 — invoker 트리거가 전원 42501 이 된다")

    // 트리거는 한 줄만 바뀐다: 상한을 **한 곳**에서만 읽고, invoker 그대로다.
    let guardBody = try t38FunctionBody(sql, header: "create or replace function public.guard_minigame_score()")
    #expect(guardBody.contains("v_max int := public.minigame_score_cap(new.game);"))
    #expect(!guardBody.contains("case new.game when 'timing_bar' then 1000"),
            "옛 case 상한이 본문에 남았다 — 상한이 두 곳에 있으면 갈리는 날 한쪽만 고쳐진다")
    #expect(!guardBody.contains("security definer"), "트리거는 다른 표를 읽지 않으므로 invoker 여야 한다")
    #expect(guardBody.contains("raise exception 'MINIGAME_SCORE_OUT_OF_RANGE'"))
    // 나머지 본문은 원본(20260908090000:105-131) 그대로다 — 날짜·판수·하향방지가 트리거 몫이라는 규약.
    #expect(guardBody.contains("new.day     := (now() at time zone 'Asia/Seoul')::date;"))
    #expect(guardBody.contains("new.plays   := old.plays + 1;"))
    #expect(guardBody.contains("if new.best_score <= old.best_score then\n      new.best_score := old.best_score;\n      new.best_at    := old.best_at;"))

    // 사후 단언이 실행권을 실제로 되묻는가(상수 헬퍼 다섯).
    #expect(sql.contains("array['minigame_score_cap(text)', 'minigame_min_seconds(text,integer)',\n                               'minigame_round_ttl()', 'minigame_time_margin()', 'minigame_kst_today()']"))
}

// MARK: - ④ 두 RPC — 시그니처 불변 · 화이트리스트만 넓힌다 · 플래피 999 신설

@Test
func 두_RPC_는_시그니처를_안_바꾸고_화이트리스트만_넓히며_플래피_상한을_신설한다() throws {
    let sql = try t38SQL(t38TetrisMigration)

    // `drop function` 이 하나라도 있으면 시그니처·기본값이 날아간다(2026-09-12 PGRST202).
    #expect(!sql.lowercased().contains("drop function"),
            "drop function 이 있다 — create or replace 만 써야 구버전 클라 호출이 안 깨진다")

    #expect(sql.contains("create or replace function public.minigame_start_round(p_game text)"))
    #expect(sql.contains("create or replace function public.minigame_submit_score(p_game text, p_score int, p_token uuid)"))

    let start = try t38FunctionBody(sql, header: "create or replace function public.minigame_start_round(p_game text)")
    let submit = try t38FunctionBody(sql, header: "create or replace function public.minigame_submit_score(p_game text, p_score int, p_token uuid)")
    for (name, body) in [("start_round", start), ("submit_score", submit)] {
        #expect(body.contains("if p_game is null or p_game not in ('timing_bar', 'flappy', 'tetris') then"),
                Comment(rawValue: "\(name) 의 화이트리스트가 세 게임이 아니다"))
    }

    // ★ 칸의 `<= 1000` 이 플래피의 **유일한 절대 상한**이었다. §B 가 그걸 1억으로 넓히는 순간 사라지므로
    //   제출 RPC 에 게임별 상한을 신설해야 한다 — 그리고 그 검사는 시간 하한보다 **먼저** 와야 한다.
    #expect(submit.contains("v_cap := public.minigame_score_cap(p_game);"))
    #expect(submit.contains("if p_score > v_cap then\n    return jsonb_build_object('status', 'invalid', 'max', v_cap);"))
    #expect(!submit.contains("if p_game = 'timing_bar' and p_score > 1000 then"),
            "옛 타이밍바 전용 상한이 남았다 — 플래피 999 가 신설되지 않았다")
    let capGate = try #require(submit.range(of: "if p_score > v_cap then"))
    let timeGate = try #require(submit.range(of: "v_need    := public.minigame_min_seconds(p_game, p_score);"))
    #expect(capGate.lowerBound < timeGate.lowerBound, "구조적 최대가 시간 하한 뒤에 있다 — 불가능한 값이 기다리면 통과한다")

    // 종전 검사 넷이 그대로 있고, 트리거 몫(날짜 리터럴·하향방지)을 다시 적지 않는다
    // (20260914010000:490-506 의 계약을 그대로 이어받는다).
    for needle in ["for update", "'no_token'", "'token_used'", "'token_expired'", "'too_fast'",
                   "public.minigame_round_ttl()", "public.minigame_kst_today()", "'improved'"] {
        #expect(submit.contains(needle), Comment(rawValue: "제출 RPC 에서 \(needle) 가 사라졌다"))
    }
    #expect(!submit.contains("Asia/Seoul"), "제출 RPC 가 날짜 규약을 다시 적는다")
    #expect(!submit.contains("greatest("), "제출 RPC 가 하향 방지를 다시 적는다")

    // 라운드 토큰 TTL 은 이 파일이 **건드리지 않는다**(30분 그대로). 게임별 TTL 함수를 만들지도 않는다 —
    // minigame_round_ttl() 은 minigame_purge_rounds 의 삭제 바닥이기도 해서 값을 움직이면 청소 주기가 같이 움직인다.
    #expect(!sql.contains("minigame_round_ttl_for"), "게임별 TTL 함수가 생겼다 — 확정 스펙이 폐기한 갈래다")
    #expect(!sql.contains("create or replace function public.minigame_round_ttl()"),
            "TTL 함수를 다시 정의한다 — 청소 바닥까지 같이 움직인다")
    #expect(sql.contains("public.minigame_round_ttl() <> interval '30 minutes'"), "TTL 이 안 움직였다는 단언이 없다")

    // 실행권 재부여(anon 금지 · authenticated 허용).
    #expect(sql.contains("revoke execute on function public.minigame_start_round(text) from public, anon;"))
    #expect(sql.contains("grant  execute on function public.minigame_start_round(text) to authenticated;"))
    #expect(sql.contains("revoke execute on function public.minigame_submit_score(text, int, uuid) from public, anon;"))
    #expect(sql.contains("grant  execute on function public.minigame_submit_score(text, int, uuid) to authenticated;"))
}

// MARK: - ⑤ 시간 하한 — tetris 가지만 더하고 기존 두 갈래는 글자 하나 안 바뀐다

@Test
func 시간_하한의_기존_두_갈래는_원본과_글자가_같고_tetris_는_advance_축의_닫힌_식이다() throws {
    let header = "create or replace function public.minigame_min_seconds(p_game text, p_score int)"
    let newBody = try t38FunctionBody(try t38SQL(t38TetrisMigration), header: header)
    let oldBody = try t38FunctionBody(try t38SQL(t38RoundTokenMigration), header: header)

    // ★ 기존 두 갈래를 **원본과 대조**한다. "바꾸지 마라"를 사람 눈이 아니라 비교로 지킨다 —
    //   20260914010000:507-508 의 사후 단언이 타이밍바 3.6219 · 플래피29 를 정확 비교하기 때문에
    //   여기가 한 글자라도 움직이면 **이미 적용된 파일**이 재적용에서 빨개진다.
    let newLegacy = try #require(t38Slice(newBody, from: "if p_game = 'timing_bar' then", to: "elsif p_game = 'tetris' then"))
    let oldLegacy = try #require(t38Slice(oldBody, from: "if p_game = 'timing_bar' then", to: "else\n"))
    #expect(t38Squash(newLegacy) == t38Squash(oldLegacy), """
        timing_bar·flappy 갈래가 원본과 다르다 — 기존 두 게임의 하한이 움직였다.
        새: \(t38Squash(newLegacy))
        옛: \(t38Squash(oldLegacy))
        """)
    // 비교가 헛돌지 않는다는 근거: 두 갈래 텍스트가 비어 있지 않고 두 게임 이름을 다 갖고 있다.
    #expect(t38Squash(newLegacy).count > 200 && newLegacy.contains("elsif p_game = 'flappy' then"))

    // tetris 갈래 — advance 축(조각+줄)의 닫힌 식. 시간도 프레임도 아니다.
    #expect(newBody.contains("elsif p_game = 'tetris' then"))
    #expect(newBody.contains("v_l := least(30, case when v_a < 280 then 1 + v_a / 20 else 15 + (v_a - 280) / 50 end);"))
    #expect(newBody.contains("v_cap := v_cap + 5000 * v_l;"))
    #expect(newBody.contains("exit when v_cap >= v_n or v_a >= 4000;"), "루프 안전 탈출이 없다 — int 최대 입력에서 안 끝난다")
    #expect(newBody.contains("return round((0.1 * v_a + 0.025 * greatest(0, (4 * v_a - 200) / 14.0))\n                 * public.minigame_time_margin(), 4);"))
    #expect(newBody.contains("if v_n <= 0 then return 0::numeric; end if;"), "0점이 0초가 아니면 즉사한 판이 거절된다")
    // `else return 0` 뒤가 아니라 **elsif** 여야 한다(뒤로 밀리면 하한이 통째로 0 이 된다).
    let tetrisBranch = try #require(newBody.range(of: "elsif p_game = 'tetris' then"))
    let fallback = try #require(newBody.range(of: "return 0::numeric;\n  end if;"))
    #expect(tetrisBranch.lowerBound < fallback.lowerBound)
}

/// `from` 부터 `to` 직전까지. 둘 중 하나라도 없으면 nil — 자르기가 헛돌면 비교가 통째로 무의미해지므로 호출자가 #require 한다.
private func t38Slice(_ text: String, from: String, to: String) -> String? {
    guard let start = text.range(of: from)?.lowerBound,
          let end = text.range(of: to, range: start..<text.endIndex)?.lowerBound else { return nil }
    return String(text[start..<end])
}

// MARK: - ⑥ 자정 루비 상 — 살아 있는 판본을 그대로 복사하고 배열 한 줄만

@Test
func 상_함수는_살아_있는_최신_판본과_게임_배열_한_줄만_다르다() throws {
    let mine = try t38AwardDefinition(try t38Raw(t38TetrisMigration))
    let live = try t38AwardDefinition(try t38Raw(t38HiddenAccountsMigration))

    // ★ 이 함수는 네 판본으로 재정의돼 왔다. 옛 판본을 골라 고치면 살아 있는 정의가 그대로 두 게임만 돌려
    //   테트리스 1등에게 상이 안 나간다 — 그래서 **최신 판본과 줄 단위로 대조**하고 다른 줄이 하나뿐임을 요구한다.
    let mineLines = mine.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let liveLines = live.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(mineLines.count == liveLines.count, "상 함수의 줄 수가 다르다(\(mineLines.count) vs \(liveLines.count)) — 통째로 복사한 것이 아니다")
    guard mineLines.count == liveLines.count else { return }
    let differing = zip(mineLines, liveLines).enumerated().filter { $0.element.0 != $0.element.1 }
    // ⚠️ `#expect` 의 두 번째 인자는 `Comment?` 다 — **문자열 리터럴(보간 포함)만** 받는다.
    //    `"..." + 배열.joined()` 은 String 식이라 컴파일되지 않는다(배선 단계에서 잡았다). 보간 하나로 접는다.
    let differingReport = differing
        .map { "  \($0.offset + 1): \($0.element.1.trimmingCharacters(in: .whitespaces)) → \($0.element.0.trimmingCharacters(in: .whitespaces))" }
        .joined(separator: "\n")
    #expect(differing.count == 1, "다른 줄이 \(differing.count)개다 — 배열 한 줄만 바꿔야 한다:\n\(differingReport)")
    if let only = differing.first {
        #expect(only.element.0.contains("foreach v_game in array array['timing_bar', 'flappy', 'tetris'] loop"))
        #expect(only.element.1.contains("foreach v_game in array array['timing_bar', 'flappy'] loop"))
    }

    // p_day 기본값 — 잃으면 cron 의 인자 없는 호출이 함수를 못 찾는다(2026-09-12 PGRST202, 미니게임 창이 통째로 빈 화면).
    #expect(mine.hasPrefix("CREATE OR REPLACE FUNCTION public.minigame_award_daily_prizes(p_day date DEFAULT NULL::date)"))

    // 잃으면 안 되는 것들이 복사본 안에 그대로 있는가(줄 단위 대조가 이미 보장하지만, 사라졌을 때 이름을 불러 준다).
    let sql = try t38SQL(t38TetrisMigration)
    for needle in ["public.minigame_prize_quorum()", "public.ruby_prize_amounts()", "pg_advisory_xact_lock",
                   "on conflict (day, game, rank) do nothing", "coalesce(p.minigame_public, true)",
                   "order by s.best_score desc, s.best_at asc, s.user_id", "'prize:minigame:'"] {
        #expect(sql.contains(needle), Comment(rawValue: "상 함수에서 \(needle) 가 사라졌다"))
    }
    #expect(!mine.contains("least("), "상 함수에 least( 가 있다 — 장부와 잔량이 어긋난다")

    // ACL: authenticated 에게 절대 열지 않는다(자기에게 루비를 주는 함수다).
    #expect(sql.contains("revoke all     on function public.minigame_award_daily_prizes(date) from public;\nrevoke execute on function public.minigame_award_daily_prizes(date) from public, anon, authenticated;\ngrant  execute on function public.minigame_award_daily_prizes(date) to service_role;"))
    #expect(!sql.contains("minigame_award_daily_prizes(date) to authenticated"))
}

// MARK: - ⑦ 게임 중립 RPC 는 다시 정의하지 않는다

@Test
func 이_파일은_게임_중립_RPC_를_다시_정의하지_않는다() throws {
    let sql = try t38SQL(t38TetrisMigration).lowercased()
    // minigame_board 를 여기서 다시 정의하면 V0313 의 "최종 정의 파일명" 단언이 빨개지고,
    // 무엇보다 p_day 기본값을 다시 적어야 하는 위험이 생긴다. 둘 다 p_game 을 자유 text 로 받아 tetris 를 이미 처리한다.
    for function in ["minigame_board", "minigame_yesterday_winner"] {
        #expect(!sql.contains("create function public.\(function)("), Comment(rawValue: "\(function) 을 다시 정의한다"))
        #expect(!sql.contains("create or replace function public.\(function)("), Comment(rawValue: "\(function) 을 다시 정의한다"))
    }
}

// MARK: - ⑧ 옛 파일은 한 글자도 안 고쳤다 (V0246 의 전제)

@Test
func 옛_두_파일의_좁은_문장은_그대로_남아_있다() throws {
    // V0246 이 20260908090000 한 파일만 읽고 옛 문자열을 요구한다 — 새 파일로만 넓혔다는 사실을 여기서도 못 박는다.
    // (이 단언이 빨개진다면 누군가 이미 적용된 마이그레이션을 편집한 것이다.)
    let scores = try t38SQL(t38ScoresMigration)
    #expect(scores.contains("game text not null check (game in ('timing_bar','flappy'))"))
    #expect(scores.contains("best_score integer not null default 0 check (best_score >= 0 and best_score <= 1000)"))
    #expect(scores.contains("foreach v_game in array array['timing_bar', 'flappy'] loop"))
    let token = try t38SQL(t38RoundTokenMigration)
    #expect(token.contains("game       text not null check (game in ('timing_bar','flappy'))"))
    #expect(token.contains("if p_game = 'timing_bar' and p_score > 1000 then"))
}

// MARK: - ⑨ 자기를 되묻는 블록들 · 달러 인용 짝 · 운영 표에 쓰지 않는다

@Test
func 적용_시점에_카탈로그와_실호출로_자기를_되묻는다() throws {
    let raw = try t38Raw(t38TetrisMigration)
    let sql = t38Strip(raw)

    for tag in ["$mg_vocab$", "$mg_widen$", "$mg_post$", "$mg_probe$"] {
        let count = raw.components(separatedBy: tag).count - 1
        #expect(count == 2, "달러 인용 태그 \(tag) 가 \(count)번이다 — 짝이 안 맞으면 본문이 그 자리에서 끝난다")
    }
    // 달러 인용 안 주석 함정: 블록 안 주석에 태그 글자를 쓰면 본문이 거기서 끝난다.
    for tag in ["$mg_vocab$", "$mg_widen$", "$mg_post$", "$mg_probe$"] {
        for line in raw.split(separator: "\n") where line.contains(tag) {
            #expect(!line.contains("--"), Comment(rawValue: "주석 줄에 \(tag) 가 있다 — 달러 인용이 거기서 닫힌다: \(line)"))
        }
    }

    // §G 가 주석을 걷어낸 prosrc 를 본다(안 걷으면 설명을 지워야만 통과하는 단언이 된다).
    // ⚠️ 이 패턴 자체가 문자열 안에 `--` 를 담고 있어 **raw 원문**에서 찾아야 한다(위 t38Strip 주석 참고).
    #expect(raw.contains("regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')"),
            "사후 단언이 prosrc 의 주석을 안 걷어낸다")

    // 검산표의 값들이 리터럴로 박혀 있는가(확정 스펙의 표와 같은 숫자).
    for value in ["3.6219", "20.9440", "0.1900", "3.8000", "6.7857", "10.1446", "19.0000", "109.1821"] {
        #expect(sql.contains(value), Comment(rawValue: "하한 검산값 \(value) 가 없다"))
    }
    #expect(sql.contains("public.minigame_score_cap('tetris') <> 100000000"))
    #expect(sql.contains("public.minigame_score_cap('timing_bar') <> 1000 or public.minigame_score_cap('flappy') <> 999"))
    #expect(sql.contains("tetris 하한이 단조가 아니다"), "단조 증가 단언이 없다")
    #expect(sql.contains("pg_get_function_arguments('public.minigame_award_daily_prizes(date)'::regprocedure)"))
    #expect(sql.contains("'p_day date DEFAULT NULL::date'"), "사후 단언이 p_day 기본값을 정확 비교하지 않는다")

    // §H 행동 프로브: **임시표**에 같은 CHECK·같은 트리거를 붙여 잰다 — 운영 표에는 한 행도 안 쓴다.
    #expect(sql.contains("(like public.minigame_daily_scores including defaults including constraints) on commit drop;"))
    #expect(sql.contains("execute function public.guard_minigame_score();"), "프로브가 진짜 트리거를 안 붙인다")
    #expect(sql.contains("v_want  int  := 14;"))
    #expect(sql.contains("raise exception '§H 프로브가 %개만 돌았다(기대 %) — 단언이 조용히 건너뛰어졌다, 배포 중단', probes, v_want;"))
    let probe = try #require(t38Slice(sql, from: "do $mg_probe$", to: "$mg_probe$;"))
    #expect(!probe.contains("insert into public."), "프로브가 운영 표에 쓴다 — 임시표에만 써야 한다")
    #expect(!probe.contains("insert into auth."), "프로브가 운영 표에 쓴다")

    // 스키마 캐시 리로드 · 최상위 트랜잭션 제어 없음(운영 CLI 가 파일을 한 트랜잭션으로 감싼다).
    #expect(sql.contains("notify pgrst, 'reload schema';"))
    for line in sql.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).lowercased() == "begin;" {
        Issue.record("최상위 begin; 이 있다: \(line)")
    }
}
