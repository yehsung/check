import CryptoKit
import Foundation
import Testing

// 서버 마이그레이션 계약(`*_tetris_frames.sql`): 테트리스 판 표시 프레임의 서버 준비.
// 사용자 결정 원문(2026-10-31): 테트리스 대결 1초 보고를 Broadcast 로 "옮기기". 2초로 늘리는 것은 원하지 않는다.
//
// 파일은 적용 때 자기를 증명하고(§0 가드 · §6 단언 · §7 프로브), 흐름은 재생 하네스에서 잰다. 여기서 지키는 것은 저장소 안에서 조용히
// 깨질 수 있는 것이다. supabase/ 는 .gitignore 라 그 파일이 없는 체크아웃에서는 이 묶음을 건너뛴다.
// 주석은 걷고 잰다(저장소 메모 '소스 계약 테스트는 주석 걷기').

private let tfOneWriter = "20261103124000_tetris_one_writer.sql"
private let tfDuel = "20261021120000_tetris_duel.sql"
private let tfSuffix = "_tetris_frames.sql"
// 커밋되는 초안 자리. 이름의 번호(지금 20261108133700)는 자리표시다 — 11-03 에 main 의 20261107120000_token_board_closed_month.sql 과,
// 이어 다른 세션 초안(20261108120000_isul_aing_drink_gift.sql)과 겹쳐 두 번 옮겼고, 푸시 직전 대기열 · 원격 마지막 적용분 · 다른 세션
// 초안을 다시 보고 정한다(gen_migration.py 머리 주석).
private let tfDraftDirectory = "docs/plan/tetris-broadcast/server"

private struct TFError: Error, CustomStringConvertible {
    let description: String
}

private func tfDirectory() -> URL? {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        directory = directory.deletingLastPathComponent()
    }
    return nil
}

private func tfChain() -> [String] {
    guard let directory = tfDirectory(),
          let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
    return names.filter { $0.hasSuffix(".sql") }.sorted()
}

private func tfFileName() -> String? { tfChain().first { $0.hasSuffix(tfSuffix) } }

private func tfRepoRoot() -> URL? {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) { return directory }
        directory = directory.deletingLastPathComponent()
    }
    return nil
}

/// 커밋된 초안 이름들(`<번호>_tetris_frames.sql`). 체인 밖에 있어도 보인다.
private func tfDraftNames() -> [String] {
    guard let root = tfRepoRoot(),
          let names = try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(tfDraftDirectory).path)
    else { return [] }
    return names.filter { $0.hasSuffix(tfSuffix) }.sorted()
}

private func tfVersion(_ name: String) -> String { String(name.prefix(while: { $0.isNumber })) }

private func tfRaw(_ name: String) throws -> String {
    guard let directory = tfDirectory() else { throw TFError(description: "supabase/migrations 를 못 찾았다") }
    return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}

private func tfMine() throws -> String {
    guard let name = tfFileName() else { throw TFError(description: "프레임 파일이 없다") }
    return try tfRaw(name)
}

private func tfStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func tfFlat(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func tfCount(_ haystack: String, _ needle: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

private func tfMD5(_ text: String) -> String {
    Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func tfDefinition(_ name: String, in sql: String) -> (header: String, body: String)? {
    let head = "create or replace function public.\(name)("
    guard let start = sql.range(of: head, options: .backwards)?.lowerBound else { return nil }
    let rest = sql[start...]
    guard let asRange = rest.range(of: "as $") else { return nil }
    let tagStart = rest.index(before: asRange.upperBound)
    guard let tagEnd = rest[rest.index(after: tagStart)...].firstIndex(of: "$") else { return nil }
    let tag = String(rest[tagStart...tagEnd])
    let bodyStart = rest.index(after: tagEnd)
    guard let close = rest.range(of: tag, range: bodyStart..<rest.endIndex) else { return nil }
    return (String(rest[start..<asRange.lowerBound]), String(rest[bodyStart..<close.lowerBound]))
}

private func tfLines(_ lines: String...) -> String { lines.joined(separator: "\n") + "\n" }

/// 치환표: 정본 본문의 old(정확히 1회) → new. 생성기와 같은 표이고, 이 표 밖의 글자는 한 자도 달라지면 안 된다.
private let tfPatches: [(name: String, patches: [(old: String, new: String)])] = [
    ("tetris_report", [
        (tfLines("         last_seen_at    = v_now,"),
         tfLines("         last_seen_at    = v_now,",
                 "         frames_v        = case when coalesce(p_protocol, 0) >= 2 then 1 else 0 end,")),
    ]),
    ("tetris__state", [
        (tfLines("  v_bal  int;"),
         tfLines("  v_bal  int;", "  v_dev  text;", "  v_both boolean;")),
        (tfLines("           'last_seen_ms', public.tetris__ms(ql.last_seen_at), 'topped_out', ql.topped_out_at is not null)",
                 "    into v_me, v_op"),
         tfLines("           'last_seen_ms', public.tetris__ms(ql.last_seen_at), 'topped_out', ql.topped_out_at is not null),",
                 "         coalesce(pl.frames_v, 0) = 1 and coalesce(ql.frames_v, 0) = 1",
                 "    into v_me, v_op, v_both")),
        (tfLines("  select p.ruby_balance into v_bal from public.profiles p where p.id = p_uid;"),
         tfLines("  select p.ruby_balance into v_bal from public.profiles p where p.id = p_uid;",
                 "  v_dev := public.tetris__device(p_match_id, p_uid);")),
        (tfLines("    'my_device', public.tetris__device(p_match_id, p_uid),"),
         tfLines("    'my_device', v_dev,",
                 "    'frames', case when m.status = 'active' and public.tetris_frames_enabled() and v_both",
                 "                    and v_dev is distinct from 'other'",
                 "                   then jsonb_build_object('on', true, 'topic', 'tetris:' || m.id::text)",
                 "                   else null end,")),
    ]),
]

@Suite("테트리스 프레임 서버 파일 계약", .enabled(if: tfFileName() != nil))
struct TetrisFramesMigrationTests {
    @Test("보고 · 상태의 새 본문 = 한 판 한 기기 정본 + 치환표(바이트) · 서명 머리 그대로 · §0 핀이 정본 md5")
    func bodiesAreCanonPlusPatches() throws {
        // 없으면: 베껴 온 본문에서 지갑 잠금 · 기기 검사 · 단조 가드 한 줄이 흘러내려도 운영 적용 전까지 아무도 모른다.
        let mine = try tfMine()
        let canonFile = try tfRaw(tfOneWriter)
        for entry in tfPatches {
            let canon = try #require(tfDefinition(entry.name, in: canonFile))
            let after = try #require(tfDefinition(entry.name, in: mine))
            #expect(after.header == canon.header, Comment(rawValue: "\(entry.name) 의 서명 머리가 바뀌었다"))
            var expected = canon.body
            for patch in entry.patches {
                #expect(tfCount(canon.body, patch.old) == 1, Comment(rawValue: "\(entry.name): 정본에서 치환 자리가 1회가 아니다: \(patch.old)"))
                expected = expected.replacingOccurrences(of: patch.old, with: patch.new)
            }
            #expect(after.body == expected, Comment(rawValue: "\(entry.name) 본문이 '정본 + 치환표' 와 다르다"))
            let pin = tfMD5(canon.body)
            #expect(tfCount(tfStrip(mine), "is distinct from '\(pin)'") >= 2,
                    Comment(rawValue: "\(entry.name) 의 정본 md5 \(pin) 가 §0 가드 · §6 단언에 없다 — 핀이 낡으면 운영 적용이 멈춘다"))
        }
    }

    @Test("이 파일이 보고 · 상태의 마지막 정의이고, 프로토콜 · 침묵 판정 · 정산은 건드리지 않는다")
    func untouchedFunctionsStayUntouched() throws {
        // 없으면: tetris_protocol 을 2 로 올리면 구버전이 진행 중 판까지 unsupported_client 로 막힌다. D10 전에 tetris__due 가 바뀌면 판돈 규칙이 조용히 바뀐다.
        let mine = tfStrip(try tfMine())
        for name in ["tetris_protocol", "tetris__due", "tetris__settle", "tetris_silence_ms", "tetris_attack_cap", "tetris_watch",
                     "tetris__ring", "tetris__device", "tetris__session", "tetris_resign"] {
            #expect(tfDefinition(name, in: mine) == nil, Comment(rawValue: "\(name) 을 이 파일이 다시 정의한다"))
        }
        let duel = try tfRaw(tfDuel)
        let due = try #require(tfDefinition("tetris__due", in: duel))
        #expect(mine.contains("is distinct from '\(tfMD5(due.body))'"), "tetris__due 핀이 정본 md5 가 아니다")
        #expect(tfFlat(try #require(tfDefinition("tetris_protocol", in: duel)).body) == "select 1", "프로토콜 정본이 1 이 아니다")
        let mineName = try #require(tfFileName())
        for file in tfChain() where file > mineName {
            let later = try tfRaw(file)
            for name in ["tetris_report", "tetris__state", "tetris_frame_allowed"] {
                #expect(tfDefinition(name, in: later) == nil, Comment(rawValue: "\(file) 이 \(name) 을 덮는다 — 이 시험의 치환표를 그 파일로 옮겨라"))
            }
        }
    }

    @Test("인가 함수: 접두사 검사가 사용자 · 표 · 예외 블록보다 앞 · 내부 실패는 false · 실행권은 authenticated 까지")
    func allowedFunctionReturnsBeforeReadingOnPoke() throws {
        // 없으면: 함수가 poke: 조인 경로에서 표를 읽거나 예외를 흘려 전원의 초인종 조인이 RlsPolicyError 로 깨진다.
        let mine = tfStrip(try tfMine())
        let body = tfFlat(try #require(tfDefinition("tetris_frame_allowed", in: mine)).body)
        let prefix = try #require(body.range(of: "if v_topic is null or left(v_topic, 7) <> 'tetris:' then return false; end if;")?.lowerBound)
        for later in ["auth.uid()", "public.tetris_matches", "public.tetris__device(", "exception when others then return false;"] {
            let at = try #require(body.range(of: later)?.lowerBound, Comment(rawValue: "\(later) 가 없다"))
            #expect(prefix < at, Comment(rawValue: "\(later) 가 접두사 검사보다 앞이다"))
        }
        // 참가자 · 진행 중 판 조건은 null 에 안전하게(`is distinct from`) — `not in`/`<>` 는 한 칸이 null 이면 식이 null 이 되어 IF 를
        // 지나쳐 true 에 닿는다(11-03 검토 6. 지금은 not null 제약이 막지만 제약이 바뀌어도 닫힌 쪽으로).
        #expect(body.contains("if not found or v_status is distinct from 'active' or (v_uid is distinct from v_a and v_uid is distinct from v_b) then return false; end if;"),
                "참가자 · 진행 중 판 조건이 없다(또는 null 에 안전하지 않다)")
        #expect(!body.contains("not in (v_a, v_b)") && !body.contains("v_status <> 'active'"), "null 에 안전하지 않은 판정이 남았다")
        #expect(body.contains("is distinct from 'other'"), "쓰기의 세션 대조가 없다")
        let flat = tfFlat(mine)
        #expect(flat.contains("revoke all on function public.tetris_frame_allowed(boolean) from public, anon;"))
        #expect(flat.contains("grant execute on function public.tetris_frame_allowed(boolean) to authenticated, service_role;"))
    }

    @Test("정책 둘은 맨 윗문장으로(경고로 삼키지 않는다) · 인가 함수를 부른다 · 파일 앞에 lock_timeout · 최상위 트랜잭션 제어 없음")
    func policiesAreNotSwallowed() throws {
        // 없으면: 정책 실패를 삼키면 기능이 죽은 채 배포되고, 최상위 commit 이 있으면 실패가 파일 전체를 되돌리지 못한다.
        let raw = tfStrip(try tfMine())
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.first.map(String.init) == "set local lock_timeout = '3s';", "첫 문장이 lock_timeout 이 아니다")
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespaces).lowercased()
            #expect(text != "begin;" && text != "commit;" && text != "rollback;", "최상위 트랜잭션 제어가 있다")
        }
        for head in ["create policy \"tetris frames read\" on realtime.messages for select to authenticated",
                     "create policy \"tetris frames write\" on realtime.messages for insert to authenticated"] {
            #expect(lines.contains { $0.hasPrefix(head) }, Comment(rawValue: "정책이 맨 윗문장이 아니다: \(head)"))
        }
        #expect(tfCount(raw, "create policy ") == 2, "정책이 둘이 아니다")
        let flat = tfFlat(raw)
        // 인가 함수는 `(select …)` 로 감싼다(InitPlan — 행마다가 아니라 문장마다 한 번, 찌르기 정책의 `(select auth.uid())` 와 같은 꼴).
        #expect(flat.contains("using (realtime.messages.extension = 'broadcast' and (select public.tetris_frame_allowed(false)));"))
        #expect(flat.contains("with check (realtime.messages.extension = 'broadcast' and (select public.tetris_frame_allowed(true)));"))
        #expect(!flat.contains("poke:%"), "쓰기 정책이 초인종 토픽을 연다")
    }
}

// 위 묶음은 초안이 체인(supabase/migrations)에 들어가야 돈다. 번호 겹침은 초안이 아직 docs 에 있을 때 생기므로 따로 잰다.
@Suite("테트리스 프레임 초안 번호", .enabled(if: tfDirectory() != nil && !tfDraftNames().isEmpty))
struct TetrisFramesDraftNumberTests {
    @Test("커밋된 초안은 하나 · 번호가 체인의 다른 파일과 겹치지 않고 한 판 한 기기 정본 뒤다 · 체인에 들어갔으면 바이트까지 같다")
    func draftVersionDoesNotCollide() throws {
        // 없으면: 11-03 에 초안 번호 20261107120000 이 main 의 token_board_closed_month 와 겹쳤는데 아무 시험도 몰랐다(초안이 체인 밖이라
        // 위 묶음은 건너뛴다). CLI 는 버전 번호로만 적용 여부를 가린다 — 두 파일이 같은 대기열에 있으면 키 충돌로 멈추고, 같은 번호의 다른
        // 파일이 먼저 원격에 적혔으면 이 파일은 적용된 것으로 보여 **조용히 건너뛰어진다**. 이 시험은 체인과의 겹침만 잰다. 아직 체인 밖인
        // 다른 세션 초안(같은 날 20261108120000 이 그랬다)과 원격 마지막 적용분은 푸시 직전 `supabase migration list` 와 초안 번호 검사로
        // 본다(앞서면 db push 가 --include-all 을 강요해 대기열 전체가 올라간다).
        let drafts = tfDraftNames()
        #expect(drafts.count == 1, Comment(rawValue: "초안이 \(drafts.count)개다: \(drafts)"))
        let draft = try #require(drafts.first)
        let version = tfVersion(draft)
        #expect(version.count == 14, Comment(rawValue: "초안 번호 '\(version)' 이 14자리가 아니다"))
        #expect(draft > tfOneWriter, "초안 번호가 얹을 정본(20261103124000)보다 앞이다")
        let chain = tfChain()
        #expect(chain.count > 100, Comment(rawValue: "마이그레이션을 \(chain.count)개밖에 못 읽었다 — 이 검사가 헛돈다"))
        let clash = chain.filter { tfVersion($0) == version && $0 != draft }
        #expect(clash.isEmpty, Comment(rawValue: "초안 번호 \(version) 이 체인의 \(clash) 와 겹친다 — 뒤로 다시 밀어라(파일 이름 · rollback.sql 머리 · gen_migration.py)"))
        if chain.contains(draft), let directory = tfDirectory(), let root = tfRepoRoot() {
            let inChain = try Data(contentsOf: directory.appendingPathComponent(draft))
            let committed = try Data(contentsOf: root.appendingPathComponent("\(tfDraftDirectory)/\(draft)"))
            #expect(inChain == committed, "체인 사본과 커밋된 초안이 다르다 — 생성기(gen_migration.py)로 다시 만들어 두 곳에 같게 둬라")
        }
    }
}
