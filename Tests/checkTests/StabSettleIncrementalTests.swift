import Foundation
import Testing

// 서버 안정화 l5(2026-10-30) — 주간 근무 보상 · 도전 미션 매분 정산을 "움직인 사람만 + 15분 전수" 로 바꾼 계약.
// 마이그레이션 20261102220000_settle_incremental.sql. 등가(옛 · 새 지급 행 집합)는 재생 하네스 타임라인이 증명했고,
// 이 파일은 **나중에 깨지기 쉬운 것**만 소스로 지킨다:
//   · 두 *_settle_all 의 마지막 정의가 흔적 후보 · 15분 전수 · 자물쇠 · 사람별 예외 격리를 그대로 갖는다.
//   · 업적 판정(achievements__eval 의 마지막 정의)과 주간 측정이 읽는 표가 전부 흔적 후보에 있다 — 새 계열이 새 표를 읽으면
//     후보에 흔적을 더하라는 신호다(안 더하면 그 계열은 최악 15분 늦고, 15분 안에 사라지는 상태는 놓친다).
// 주석은 걷어내고 잰다(설명을 지워야만 초록이 되는 시험이 되지 않게 — 하우스 규칙).

private let siMigration = "20261102220000_settle_incremental.sql"

private func siMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        directory = directory.deletingLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

private func siStripComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let r = line.range(of: "--") { return line[line.startIndex..<r.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 체인 전체(이름 순)에서 `create … function public.<name>(` 의 **마지막** 정의: (파일 이름, 본문 — 주석 걷음).
private func siLastDefinition(_ name: String) throws -> (file: String, body: String)? {
    let dir = try siMigrationsDirectory()
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".sql") }.sorted()
    var found: (String, String)?
    let head = try NSRegularExpression(pattern: #"create\s+(or\s+replace\s+)?function\s+public\.\#(NSRegularExpression.escapedPattern(for: name))\s*\("#,
                                       options: [.caseInsensitive])
    for f in files {
        let sql = siStripComments(try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8))
        let ns = sql as NSString
        for m in head.matches(in: sql, range: NSRange(location: 0, length: ns.length)) {
            let rest = ns.substring(from: m.range.location) as NSString
            guard let tag = try NSRegularExpression(pattern: #"\bas\s+(\$[a-z_]*\$)"#, options: [.caseInsensitive])
                    .firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length)) else { continue }
            let t = rest.substring(with: tag.range(at: 1))
            let start = tag.range.location + tag.range.length
            let close = rest.range(of: t, range: NSRange(location: start, length: rest.length - start))
            guard close.location != NSNotFound else { continue }
            found = (f, rest.substring(with: NSRange(location: start, length: close.location - start)))
        }
    }
    return found
}

private func siPublicRefs(_ body: String) -> Set<String> {
    let re = try! NSRegularExpression(pattern: #"public\.([a-z_0-9]+)"#)
    let ns = body as NSString
    return Set(re.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
}

private func siSquash(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

@Suite("서버 안정화 l5 — 정산 매분 경로(움직인 사람만 + 15분 전수)")
struct StabSettleIncrementalTests {
    @Test("두 *_settle_all 의 마지막 정의: 흔적 후보 · 15분 전수 갈래 · 같은 자물쇠 · 사람별 예외 격리 · mode 키")
    func settleAllShape() throws {
        for (fn, candidates, lock, settle) in [
            ("weekly_work_settle_all", "weekly_work__settle_candidates", "weekly_work_settle_all", "weekly_work__settle(r.user_id, true)"),
            ("achievements_settle_all", "achievements__settle_candidates", "achievements_settle_all", "achievements_settle(r.user_id)"),
        ] {
            let def = try #require(try siLastDefinition(fn), "\(fn) 정의가 없다")
            #expect(def.file == siMigration, "\(fn) 의 마지막 정의가 \(def.file) 다 — 매분 경로를 다시 전수로 되돌렸나")
            let b = siSquash(def.body)
            #expect(b.contains("public.settle__mode(v_now)"), "\(fn): 갈래를 settle__mode 로 정하지 않는다")
            #expect(b.contains("public.\(candidates)(v_now, v_mode = 'full')"), "\(fn): 흔적 후보를 안 부른다")
            #expect(b.contains("pg_try_advisory_xact_lock(hashtext('\(lock)'))"), "\(fn): 겹친 실행 자물쇠 이름이 바뀌었다")
            #expect(b.contains("public.\(settle)"), "\(fn): 사람별 정산 호출이 바뀌었다")
            #expect(b.contains("exception when others"), "\(fn): 사람별 예외 격리가 없다")
            #expect(b.contains("'mode', v_mode"), "\(fn): 반환에 mode 가 없다")
        }
    }

    @Test("15분 전수: KST 분 % 15 = 0 · KST 00:00–00:04 · 흔적 창 10분")
    func fullSweepCadence() throws {
        let mode = siSquash(try #require(try siLastDefinition("settle__mode")).body)
        #expect(mode.contains("at time zone 'asia/seoul'"))
        #expect(mode.contains("::int % 15 = 0"))
        #expect(mode.contains("::int = 0 and extract(minute from (p_now at time zone 'asia/seoul'))::int < 5"))
        let window = siSquash(try #require(try siLastDefinition("settle__active_window")).body)
        #expect(window.contains("interval '10 minutes'"))
    }

    @Test("업적 판정이 읽는 표마다 흔적 후보가 있다(새 계열이 새 표를 읽으면 여기서 빨강)")
    func achievementInputsHaveSignals() throws {
        let eval = try #require(try siLastDefinition("achievements__eval"))
        // 흔적 없이도 되는 것: 상수 · 설정 함수, 집계표(pokes 의 같은 트랜잭션 트리거), 팀 숨김(관리자 — 15분 전수).
        let noSignalNeeded: Set<String> = ["achievement_defs", "achievement_minigame_games", "achievements__launch_at",
                                           "achievement_poke_tally", "teams"]
        let cands = siSquash(try #require(try siLastDefinition("achievements__settle_candidates")).body)
        for t in siPublicRefs(eval.body).subtracting(noSignalNeeded).sorted() {
            #expect(cands.contains("from public.\(t) "), "achievements__eval(\(eval.file))이 읽는 \(t) 의 흔적이 후보에 없다")
        }
        #expect(cands.contains("from public.pokes "), "찌르기 흔적(pokes.created_at)이 없다")
        #expect(cands.contains("join public.memberships mm on mm.team_id = mj.team_id"), "팀 합류의 받는 쪽(멤버 전원)을 안 본다")
        for game in ["gomoku_matches", "chess_matches"] {
            #expect(cands.contains("from public.\(game) g cross join lateral (values (g.challenger), (g.opponent)) u(uid)"),
                    "\(game): 끝난 판의 두 사람을 다 안 본다")
        }
    }

    @Test("full 갈래는 옛 후보식 전부다 — p_full 이 후보를 넓히지 않으면 흔적 없는 변화가 15분이 아니라 영영 안 잡힌다")
    func fullBranchCoversOldCandidates() throws {
        // 반박 검증(2026-10-30): 주간 후보의 `p_full or` 를 지운 뮤테이션이 마이그레이션 §4 와 이 파일을 다 통과했다
        // (하네스 재생 DB 에 근무 세션이 없어 §4 의 데이터 대조가 빈다). 그래서 모양을 글자로도 묶는다.
        let weekly = siSquash(try #require(try siLastDefinition("weekly_work__settle_candidates")).body)
        #expect(weekly.contains("where s.started_at >= w.from_ts - interval '7 days' and s.started_at < p_now "
                                + "and (s.ended_at is null or s.ended_at >= w.from_ts)"),
                "주간 base 가 옛 weekly_work_settle_all 후보식과 다르다")
        #expect(weekly.contains("where p_full or b.user_id in (select r.user_id from recent r)"),
                "주간 후보가 p_full 일 때 base 전부를 돌려주지 않는다")
        let ach = siSquash(try #require(try siLastDefinition("achievements__settle_candidates")).body)
        #expect(ach.contains("where p.is_hidden is not true and exists (select 1 from public.achievement_defs() d "
                             + "where not exists (select 1 from public.achievement_progress ap where ap.user_id = p.id and ap.key = d.key))"),
                "업적 base 가 옛 achievements_settle_all 후보식과 다르다")
        #expect(ach.contains("and (p_full or p.id in (select r.user_id from recent r))"),
                "업적 후보가 p_full 일 때 base 전부를 돌려주지 않는다")
        // 배포 때의 데이터 대조(§4(4))는 두 함수 다 있어야 한다 — 운영 데이터에서는 이것이 마지막 그물이다.
        let mig = siSquash(siStripComments(try String(contentsOf: try siMigrationsDirectory().appendingPathComponent(siMigration),
                                                       encoding: .utf8)))
        #expect(mig.contains("업적 전수 후보가 옛 후보식과"), "§4(4) 업적 full 대조가 없다")
        #expect(mig.contains("주간 전수 후보가 옛 후보식과"), "§4(4) 주간 full 대조가 없다")
    }

    @Test("주간 측정이 읽는 표는 work_sessions · work_statuses 뿐이고 둘 다 흔적 후보에 있다")
    func weeklyInputsHaveSignals() throws {
        var refs = Set<String>()
        for fn in ["weekly_work__settle", "weekly_work__seconds", "work_seconds_on__exact"] {
            refs.formUnion(siPublicRefs(try #require(try siLastDefinition(fn), "\(fn) 정의가 없다").body))
        }
        let known: Set<String> = ["profiles", "weekly_work_tiers", "weekly_work_achieved", "weekly_work_first_week", "ruby_ledger",
                                  "weekly_work__reason", "weekly_work__seconds", "work_seconds_on__exact", "work_sessions",
                                  "work_statuses"]
        #expect(refs.subtracting(known).isEmpty, "주간 측정이 새 것을 읽는다: \(refs.subtracting(known).sorted()) — 흔적을 더하라")
        let cands = siSquash(try #require(try siLastDefinition("weekly_work__settle_candidates")).body)
        #expect(cands.contains("from public.work_sessions s where (s.ended_at is null and s.started_at < p_now)"), "열린 세션을 안 본다")
        for col in ["s.started_at", "s.ended_at", "s.auto_closed_at", "s.restored_at", "st.updated_at", "st.last_seen_at"] {
            #expect(cands.contains("\(col) >= p_now - public.settle__active_window()"), "주간 흔적 \(col) 이 없다")
        }
    }
}
