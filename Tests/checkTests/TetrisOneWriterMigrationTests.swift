import CryptoKit
import Foundation
import Testing
@testable import CheckCore

// v0.3.69 — 서버 마이그레이션 계약(20261103124000_tetris_one_writer.sql): 1:1 테트리스 **한 판 한 기기**.
//
// 2026-10-30 두 판(011ef7ee · 5734f1f8): 같은 계정의 맥 두 대가 초인종을 함께 받고 둘 다 판을 세웠다. 입력 없는 쪽의 판이 같은
// tetris_players 행을 덮어쓰고 그 판의 탑아웃(p_topped_out=true)으로 서버가 대결을 닫았다. 이 파일은 그 서버 쪽 마개다.
//
// 마이그레이션은 **적용 시점에 자기를 증명한다**(§0 운영 본문 md5 · §5 사후 단언 · §6 실호출 프로브 12건 — 어긋나면 통째 롤백).
// 그 단언·프로브는 재생 하네스(tools/replay-harness-v2)에서 세 번 적용으로 통과했다. 여기서 지키는 것은 **사람 손이 저장소
// 안에서 조용히 깨뜨릴 수 있는 것**이다:
//   ① 이 파일이 다섯 함수의 **마지막 정의**이고, 본문 = 직전 정본 + 치환표(바이트) — 베껴 온 본문이 흘러내리지 않았다.
//   ② §0 의 md5 핀이 정말 그 본문들의 md5 다(핀이 낡으면 운영 적용이 멈추거나, 재적용 판정이 헛돈다).
//   ③ 쓰기 규칙이 보고·기권에서 **어떤 쓰기·정산보다 앞**에 있고, 사람 행을 쓰거나 정산하는 클라 RPC 가 그 둘뿐이다.
//   ④ 단조 가드 · other_device 응답 모양 · 상태의 my_device · 세션 기록(신청 · 수락) · 실행권이 그대로다.
//   ⑤ 커밋되는 사본(docs/plan/migrations-pending)이 체인 사본과 바이트까지 같다(supabase/ 는 .gitignore).
// 주석은 걷고 잰다(주석 안의 글자로 초록이 되지 않게 — 저장소 메모 '소스 계약 테스트는 주석 걷기').

private let towMigration = "20261103124000_tetris_one_writer.sql"
private let towDuelMigration = "20261021120000_tetris_duel.sql"
private let towWatchersMigration = "20261023120000_match_watchers.sql"

private struct TOWError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 라 git worktree 에는 없을 수 있다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫
/// 디렉토리를 잡는다(V0364 와 같은 방식). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다.
private func towMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TOWError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw TOWError("supabase/migrations 를 못 찾았다")
}

private func towRepoRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) { return directory }
        directory = directory.deletingLastPathComponent()
    }
    throw TOWError("저장소 꼭대기(Package.swift)를 못 찾았다")
}

private func towChain() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: try towMigrationsDirectory().path)
        .filter { $0.hasSuffix(".sql") }.sorted()
}

private func towRaw(_ name: String) throws -> String {
    try String(contentsOf: try towMigrationsDirectory().appendingPathComponent(name), encoding: .utf8)
}

/// SQL 줄 주석(`--` 부터 줄 끝)을 걷는다. 이 파일들의 본문 문자열에는 `--` 가 없다(— 는 긴 줄표 한 글자다).
private func towStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 공백 덩어리를 한 칸으로(줄바꿈·들여쓰기와 무관하게 문장을 견준다).
private func towFlat(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func towCount(_ haystack: String, _ needle: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

/// 한 파일에서 `create or replace function public.<이름>(` 의 **마지막** 정의(머리 + 본문). 없으면 nil.
/// 달러 인용 태그는 파일마다 다르다(`$fn$` · `$function$`) — `as $태그$` 를 읽어 그 태그로 닫는다.
private func towDefinition(_ name: String, in sql: String) -> (header: String, body: String)? {
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

/// 한 파일이 정의하는 `public.tetris_*` 이름들(내부 도구 `tetris__*` 포함 — 거르는 것은 부르는 쪽).
private func towTetrisNames(in sql: String) -> Set<String> {
    let head = "create or replace function public.tetris_"
    var names: Set<String> = []
    for piece in sql.components(separatedBy: head).dropFirst() {
        let name = "tetris_" + piece.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        if piece.dropFirst(name.count - "tetris_".count).first == "(" { names.insert(name) }
    }
    return names
}

private func towMD5(_ text: String) -> String {
    Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// 치환표 — 직전 정본 본문의 `old`(정확히 1회) → `new`. 마이그레이션은 이 표를 적용해 만든 본문을 그대로 실었다.
/// ★ Swift 의 `"""` 여러 줄 리터럴은 닫는 따옴표 들여쓰기를 걷으므로 SQL 들여쓰기를 바이트로 맞추려고 줄 배열로 쓴다.
private func towLines(_ lines: String...) -> String { lines.joined(separator: "\n") + "\n" }

private struct TOWPatch {
    let old: String
    let new: String
}

private let towPatches: [(name: String, canon: String, patches: [TOWPatch])] = [
    ("tetris__state", towWatchersMigration, [
        TOWPatch(old: towLines(
                    "    'watchers', public.match__watchers('tetris', p_match_id),",
                    "    'ruby_balance', v_bal);"),
                 new: towLines(
                    "    'watchers', public.match__watchers('tetris', p_match_id),",
                    "    'my_device', public.tetris__device(p_match_id, p_uid),",
                    "    'ruby_balance', v_bal);")),
    ]),
    ("tetris_challenge", towDuelMigration, [
        TOWPatch(old: towLines(
                    "  insert into public.tetris_matches(challenger, opponent, stake, status, invite_expires_at)",
                    "  values (uid, p_opponent, p_stake, 'pending', v_exp)",
                    "  returning id into v_id;"),
                 new: towLines(
                    "  -- 한 판 한 기기(20261103124000): 신청을 낸 기기의 세션을 적는다 — 이 자리의 보고·기권은 이 세션만 쓴다.",
                    "  insert into public.tetris_matches(challenger, opponent, stake, status, invite_expires_at, challenger_session)",
                    "  values (uid, p_opponent, p_stake, 'pending', v_exp, public.tetris__session())",
                    "  returning id into v_id;")),
    ]),
    ("tetris_respond", towDuelMigration, [
        TOWPatch(old: towLines(
                    "         seed        = v_seed,",
                    "         start_at    = null",
                    "   where g.id = m.id and g.status = 'pending';"),
                 new: towLines(
                    "         seed        = v_seed,",
                    "         start_at    = null,",
                    "         -- 한 판 한 기기(20261103124000): 수락한 기기의 세션 — 이 자리의 보고·기권은 이 세션만 쓴다.",
                    "         opponent_session = public.tetris__session()",
                    "   where g.id = m.id and g.status = 'pending';")),
    ]),
    ("tetris_report", towDuelMigration, [
        TOWPatch(old: towLines(
                    "  v_sent      int;",
                    "  v_rows      int;",
                    "begin"),
                 new: towLines(
                    "  v_sent      int;",
                    "  v_rows      int;",
                    "  v_dev       text;",
                    "begin")),
        TOWPatch(old: towLines(
                    "  -- ① 누가 불러도 닫힌다(내 침묵도 여기서 잰다 — 15초 넘게 끊겼다 돌아온 보고는 이미 진 판을 받는다)"),
                 new: towLines(
                    "  -- ⓪ 한 판 한 기기(20261103124000): 이 자리를 연 기기(신청·수락한 세션)가 아니면 **아무것도 쓰지 않는다** —",
                    "  --    시간 판정·준비·쓰기·탑아웃 정산보다 앞이다. 같은 계정의 다른 기기가 입력 없이 돌린 판이 진짜 판을 덮어쓰고",
                    "  --    그 판의 탑아웃으로 대결을 닫던 결함(2026-10-30 두 판)의 서버 쪽 마개다.",
                    "  v_dev := public.tetris__device(m.id, uid);",
                    "  if v_dev = 'other' then",
                    "    return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid));",
                    "  end if;",
                    "  -- ① 누가 불러도 닫힌다(내 침묵도 여기서 잰다 — 15초 넘게 끊겼다 돌아온 보고는 이미 진 판을 받는다)")),
        TOWPatch(old: towLines(
                    "    raise exception 'tetris_report: 판 %에 사람 %의 행이 없다 — 수락이 사람 행을 안 만들었다', m.id, uid;",
                    "  end if;"),
                 new: towLines(
                    "    raise exception 'tetris_report: 판 %에 사람 %의 행이 없다 — 수락이 사람 행을 안 만들었다', m.id, uid;",
                    "  end if;",
                    "  -- ⓪' 누계가 뒤로 가면 다른 기기의 보고다(한 기기의 지운 줄·공격 누계는 줄지 않고, 재개는 서버 값에서 잇는다).",
                    "  --     늦게 온 옛 보고(seq 이하)는 아래 ④ 의 stale 이 받는다 — 여기서 다른 기기로 몰지 않는다.",
                    "  if p_seq > me.seq",
                    "     and (coalesce(p_lines, me.lines) < me.lines or coalesce(p_garbage_sent, me.garbage_sent) < me.garbage_sent) then",
                    "    return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid));",
                    "  end if;",
                    "  -- 세션 기록이 없던 판(이 파일 전에 수락된 판)은 거른 뒤의 이 보고가 자리를 잡는다. 세션 없는 토큰이면 아무것도 안 한다.",
                    "  if v_dev is null then",
                    "    perform public.tetris__claim(m.id, uid);",
                    "  end if;")),
    ]),
    ("tetris_resign", towDuelMigration, [
        TOWPatch(old: towLines(
                    "  m     public.tetris_matches%rowtype;",
                    "begin"),
                 new: towLines(
                    "  m     public.tetris_matches%rowtype;",
                    "  v_dev text;",
                    "begin")),
        TOWPatch(old: towLines(
                    "  if public.tetris__due(m.id, v_now) then",
                    "    select * into m from public.tetris_matches g where g.id = m.id;",
                    "  end if;",
                    "  if m.status <> 'active' then",
                    "    return jsonb_build_object('status', 'not_active', 'state', public.tetris__state(m.id, uid));",
                    "  end if;"),
                 new: towLines(
                    "  -- 한 판 한 기기(20261103124000): 이 자리를 연 기기가 아니면 기권도 받지 않는다(쓰기 없음 · 정산 없음).",
                    "  v_dev := public.tetris__device(m.id, uid);",
                    "  if v_dev = 'other' then",
                    "    return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid));",
                    "  end if;",
                    "  if public.tetris__due(m.id, v_now) then",
                    "    select * into m from public.tetris_matches g where g.id = m.id;",
                    "  end if;",
                    "  if m.status <> 'active' then",
                    "    return jsonb_build_object('status', 'not_active', 'state', public.tetris__state(m.id, uid));",
                    "  end if;",
                    "  if v_dev is null then",
                    "    perform public.tetris__claim(m.id, uid);",
                    "  end if;")),
    ]),
]

/// 쓰기 규칙 두 줄(보고 · 기권 공통). 본문에서 이 둘이 먼저 나와야 한다.
private let towDeviceCheck = "v_dev := public.tetris__device(m.id, uid);"
private let towOtherReturn =
    "if v_dev = 'other' then return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid)); end if;"

@Suite("v0.3.69 테트리스 한 판 한 기기 — 서버 마이그레이션 계약(20261103124000)")
struct TetrisOneWriterMigrationTests {

    // MARK: ① 체인의 자리 · 마지막 정의 · 본문 = 정본 + 치환

    @Test("이 파일이 체인 끝(테트리스 두 정본 파일 뒤)이고, 다섯 함수 · 도구 셋의 마지막 정의다 · 직전 정의는 두 정본 파일이다")
    func thisFileIsTheLatestDefinition() throws {
        // 없으면: 뒤 파일이 옛 본문(쓰기 규칙 없는 보고)을 다시 깔아도 초록이다 — 2026-10-30 결함이 조용히 돌아온다.
        let chain = try towChain()
        #expect(chain.count > 100, "마이그레이션을 \(chain.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
        let mine = try #require(chain.firstIndex(of: towMigration), "\(towMigration) 이 체인에 없다")
        for source in [towDuelMigration, towWatchersMigration] {
            let at = try #require(chain.firstIndex(of: source))
            #expect(at < mine, Comment(rawValue: "\(source) 가 이 파일보다 뒤다 — 얹을 정본이 아직 없다"))
        }
        let names = towPatches.map(\.name) + ["tetris__session", "tetris__device", "tetris__claim"]
        for name in names {
            var last: String?
            var beforeMine: String?
            for file in chain {
                let sql = try towRaw(file)
                guard towDefinition(name, in: sql) != nil else { continue }
                if file < towMigration { beforeMine = file }
                last = file
            }
            #expect(last == towMigration, Comment(rawValue: "\(name) 의 마지막 정의가 \(last ?? "없음") 다 — 뒤 파일이 쓰기 규칙을 덮었다면 이 시험의 치환표를 그 파일로 옮겨라"))
            if let canon = towPatches.first(where: { $0.name == name })?.canon {
                #expect(beforeMine == canon, Comment(rawValue: "\(name) 의 직전 정의가 \(beforeMine ?? "없음") 다(기대 \(canon)) — 정본이 바뀌었다"))
            } else {
                #expect(beforeMine == nil, Comment(rawValue: "\(name) 은 이 파일이 처음 만든다(앞 정의 \(beforeMine ?? "")) "))
            }
        }
    }

    @Test("다섯 함수의 새 본문 = 직전 정본 본문 + 치환표(바이트) · 서명 머리는 한 글자도 안 바뀌었다")
    func copiedBodiesEqualCanonPlusPatches() throws {
        // 없으면: 베껴 온 본문의 한 줄이 여기서만 바뀌어도(옛 가드 하나가 빠져도) 운영 적용 전까지 아무도 모른다.
        let mine = try towRaw(towMigration)
        for entry in towPatches {
            let canon = try #require(towDefinition(entry.name, in: try towRaw(entry.canon)), "\(entry.name) 정본이 없다")
            let after = try #require(towDefinition(entry.name, in: mine), "\(entry.name) 을 이 파일이 정의하지 않는다")
            #expect(after.header == canon.header, Comment(rawValue: "\(entry.name) 의 서명 머리가 바뀌었다 — 바꾸면 옛 서명 drop · ACL 재부여가 필요하다(PGRST203)"))
            var expected = canon.body
            for patch in entry.patches {
                #expect(towCount(canon.body, patch.old) == 1, Comment(rawValue: "\(entry.name): 정본에서 치환 자리를 \(towCount(canon.body, patch.old))번 찾았다(기대 1)"))
                #expect(towCount(canon.body, patch.new) == 0, Comment(rawValue: "\(entry.name): 정본에 이미 새 글이 있다 — 치환표가 낡았다"))
                expected = expected.replacingOccurrences(of: patch.old, with: patch.new)
            }
            #expect(after.body == expected, Comment(rawValue: "\(entry.name) 본문이 '정본 + 치환표' 와 다르다 — 베껴 온 본문이 흘러내렸다"))
        }
    }

    // MARK: ② §0 md5 핀

    @Test("§0 핀: 정본 md5 = 정본 본문의 md5 · 재적용 md5 = 이 파일 본문의 md5(다섯 모두) · 정본 하나는 운영 값과 같다")
    func md5PinsMatchTheBodies() throws {
        // 없으면: 핀이 낡아 운영 db push 가 '정본이 아니다' 로 멈추거나, 재적용 판정이 엉뚱한 본문을 덮는다.
        let mine = try towRaw(towMigration)
        let flat = towFlat(mine)
        let signatures = [
            "tetris__state": "public.tetris__state(uuid,uuid)",
            "tetris_challenge": "public.tetris_challenge(integer,uuid,integer)",
            "tetris_respond": "public.tetris_respond(integer,uuid,boolean)",
            "tetris_report": "public.tetris_report(integer,uuid,integer,text,integer,integer,integer,integer,boolean)",
            "tetris_resign": "public.tetris_resign(integer,uuid)",
        ]
        for entry in towPatches {
            let canon = try #require(towDefinition(entry.name, in: try towRaw(entry.canon)))
            let after = try #require(towDefinition(entry.name, in: mine))
            let sig = try #require(signatures[entry.name])
            let row = "('\(sig)', '\(towMD5(canon.body))', '\(towMD5(after.body))')"
            #expect(flat.contains(row), Comment(rawValue: "§0 핀 줄이 없다: \(row)"))
        }
        // 정본 md5 하나를 운영 덤프 값과 맞대 둔다(20261023120000 §1 이 운영에서 같은 본문을 치환 원본으로 받아들였다).
        #expect(towMD5(try #require(towDefinition("tetris__settle", in: try towRaw(towDuelMigration))).body)
                == "78632b103a52f4f037c7aca9f802c8ec", "전제: 저장소 본문 md5 가 운영 md5(20261023132000 §1 핀)와 같은 방식으로 계산된다")
    }

    // MARK: ③ 쓰기 규칙의 자리 · 거는 RPC 전수

    @Test("보고·기권: 기기 검사가 매치 행 잠금 뒤 · 시간 판정 · 사람 행 쓰기 · 정산 · 자리 잡기 · 매치 행 쓰기보다 앞이다")
    func theWriterRuleComesBeforeEveryWrite() throws {
        // 없으면: 다른 기기의 보고가 준비(ready_at)·보고·탑아웃 정산을 먼저 해 놓고 나서야 거절된다 — 거절이 아무것도 못 막는다.
        let mine = try towRaw(towMigration)
        for name in ["tetris_report", "tetris_resign"] {
            let body = towFlat(towStrip(try #require(towDefinition(name, in: mine)).body))
            let check = try #require(body.range(of: towDeviceCheck)?.lowerBound, "\(name) 에 기기 검사가 없다")
            let refuse = try #require(body.range(of: towOtherReturn)?.lowerBound, "\(name) 에 other_device 거절이 없다")
            #expect(check < refuse)
            let lock = try #require(body.range(of: "from public.tetris_matches g where g.id = p_match_id for update")?.lowerBound)
            #expect(lock < check, "\(name): 기기 검사가 매치 행 잠금 앞이다 — 두 기기 경합에서 자리 잡기가 갈라진다")
            for write in ["public.tetris__due(", "update public.tetris_players", "public.tetris__settle(",
                          "public.tetris__claim(", "update public.tetris_matches", "insert into"] {
                for range in body.ranges(of: write) {
                    #expect(refuse < range.lowerBound, Comment(rawValue: "\(name): \"\(write)\" 가 기기 거절보다 앞이다"))
                }
            }
            #expect(towCount(body, "public.tetris__claim(m.id, uid)") == 1)
            #expect(body.contains("if v_dev is null then perform public.tetris__claim(m.id, uid); end if;"),
                    "\(name): 자리 잡기가 '기록 없음' 에만 걸려 있지 않다")
        }
    }

    @Test("사람 행을 쓰거나 판을 정산하는 클라 RPC 는 보고·기권 둘뿐이고, 둘 다 기기 검사를 품는다(체인의 마지막 정의 전수)")
    func everyMutatingRpcCarriesTheWriterRule() throws {
        // 없으면: 뒷날 '판 나가기' 같은 RPC 가 사람 행을 쓰거나 정산하면서 기기 검사를 빠뜨려도 초록이다 — 다른 기기의 손이 다시 판을 닫는다.
        var last: [String: String] = [:]
        for file in try towChain() {
            let sql = try towRaw(file)
            for name in towTetrisNames(in: sql) {
                guard !name.hasPrefix("tetris__") else { continue }      // 내부 도구(클라 실행권 0)
                if let definition = towDefinition(name, in: sql) { last[name] = towFlat(towStrip(definition.body)) }
            }
        }
        // 서버 몫(cron · 청소)은 service_role 만 부른다 — 클라 기기와 무관하다.
        let serverOnly: Set<String> = ["tetris_settle_expired", "tetris_purge"]
        var mutating: [String] = []
        for (name, body) in last where !serverOnly.contains(name) {
            if body.contains("update public.tetris_players") || body.contains("public.tetris__settle(") {
                mutating.append(name)
                #expect(body.contains(towDeviceCheck) && body.contains(towOtherReturn),
                        Comment(rawValue: "\(name) 이 사람 행을 쓰거나 정산하는데 기기 검사가 없다"))
            }
        }
        #expect(mutating.sorted() == ["tetris_report", "tetris_resign"],
                Comment(rawValue: "사람 행을 쓰거나 정산하는 클라 RPC 가 \(mutating.sorted()) 다 — 새 것이면 쓰기 규칙을 넣고 머리말 '거는 곳' 표를 고쳐라"))
        #expect(last.count >= 10, "테트리스 클라 RPC 를 \(last.count)개밖에 못 읽었다 — 전수가 헛돈다")
    }

    // MARK: ④ 단조 가드 · 응답 모양 · my_device · 세션 기록 · 칸 · 도구

    @Test("단조 가드: seq 가 앞선 보고의 줄·공격 누계가 뒤로 가면 other_device — 준비 쓰기 · 자리 잡기보다 앞, 사람 행을 읽은 뒤")
    func monotonicGuardSitsBeforeTheReadyWrite() throws {
        // 없으면: 같은 세션을 쓰는 두 프로세스(한 맥)의 입력 없는 판이 0줄 보고로 진짜 판을 덮는다 — 세션으로는 못 가른다.
        let body = towFlat(towStrip(try #require(towDefinition("tetris_report", in: try towRaw(towMigration))).body))
        let guardText = "if p_seq > me.seq and (coalesce(p_lines, me.lines) < me.lines or coalesce(p_garbage_sent, me.garbage_sent) < me.garbage_sent) then return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid)); end if;"
        let at = try #require(body.range(of: guardText)?.lowerBound, "단조 가드가 없다(또는 seq 비교가 빠졌다 — 늦게 온 옛 보고를 다른 기기로 몬다)")
        let readMe = try #require(body.range(of: "select * into me from public.tetris_players pl")?.lowerBound)
        let ready = try #require(body.range(of: "update public.tetris_players pl set ready_at")?.lowerBound)
        let claim = try #require(body.range(of: "perform public.tetris__claim(m.id, uid);")?.lowerBound)
        #expect(readMe < at && at < ready && at < claim, "단조 가드의 자리가 틀렸다(사람 행 읽기 뒤 · 준비 쓰기와 자리 잡기 앞)")
        // 늦게 온 옛 보고는 여전히 stale 이다(가드가 그 앞을 가로채지 않는다 — seq 비교가 그 장치다).
        #expect(body.contains("if p_seq <= me.seq then return jsonb_build_object('status', 'stale'"))
    }

    @Test("other_device 응답은 언제나 {status, state(부르는 사람 시점)} 한 모양이고, 클라 어휘와 같은 글자다")
    func otherDeviceResponseShape() throws {
        // 없으면: 응답 모양이 갈래마다 달라 클라가 상태를 못 옮기거나(state 없음), 서버·클라 글자가 어긋나 .unknown 으로 접힌다.
        let mine = try towRaw(towMigration)
        let shape = "jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid))"
        var total = 0
        for name in ["tetris_report", "tetris_resign"] {
            let body = towStrip(try #require(towDefinition(name, in: mine)).body)
            #expect(towCount(body, "'other_device'") == towCount(body, shape), Comment(rawValue: "\(name): other_device 가 다른 모양으로도 나간다"))
            total += towCount(body, shape)
        }
        #expect(total == 3, "other_device 갈래가 \(total)개다(기대: 보고 기기 · 보고 단조 · 기권 기기)")
        #expect(TetrisRPCStatus(rawValue: "other_device") == .otherDevice, "클라가 서버 글자를 자기 status 로 못 읽는다")
        #expect(TetrisRPCStatus.otherDevice.rawValue == "other_device")
    }

    @Test("상태 묶음에 my_device(this|other|null) 한 칸 — 판정은 부르는 사람 자기 자리일 때만 · 세션이 없으면 null")
    func stateCarriesMyDevice() throws {
        // 없으면: 새 클라가 자기 판인지 서버에게 물을 길이 없어 '이 기기가 연 판' 기록만 믿는다 — 재설치한 기기가 자기 판을 못 둔다.
        let mine = try towRaw(towMigration)
        let state = towFlat(towStrip(try #require(towDefinition("tetris__state", in: mine)).body))
        #expect(towCount(state, "'my_device', public.tetris__device(p_match_id, p_uid),") == 1)
        let device = towFlat(towStrip(try #require(towDefinition("tetris__device", in: mine)).body))
        #expect(device.contains("if v_cur is null or p_match_id is null or p_uid is null or p_uid is distinct from auth.uid() then return null;"),
                "남의 자리(또는 세션 없는 토큰)를 판정한다")
        #expect(device.contains("when p_uid = g.challenger then g.challenger_session when p_uid = g.opponent then g.opponent_session end"))
        #expect(device.contains("return case when v_have = v_cur then 'this' else 'other' end;"))
        // 와이어 키가 클라 디코더와 같다(snake_case → camelCase).
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(TetrisStatePayload.self, from: Data(#"{"match_id":"m","my_device":"other"}"#.utf8))
        #expect(payload.myDevice == "other")
    }

    @Test("세션 기록: 신청이 challenger_session · 수락 전이가 opponent_session 을 적는다(거절 갈래는 안 적는다) · 칸 둘은 uuid null")
    func sessionsAreRecordedWhereTheDeviceActs() throws {
        // 없으면: 기록이 비어 모든 판이 '기록 없음' 이 되고, 적용 뒤 가드를 지난 첫 보고(입력 없는 기기일 수도)가 자리를 잡는다.
        let mine = try towRaw(towMigration)
        let flatFile = towFlat(towStrip(mine))
        #expect(flatFile.contains("alter table public.tetris_matches add column if not exists challenger_session uuid null;"))
        #expect(flatFile.contains("alter table public.tetris_matches add column if not exists opponent_session uuid null;"))
        let challenge = towFlat(towStrip(try #require(towDefinition("tetris_challenge", in: mine)).body))
        #expect(challenge.contains("insert into public.tetris_matches(challenger, opponent, stake, status, invite_expires_at, challenger_session) values (uid, p_opponent, p_stake, 'pending', v_exp, public.tetris__session())"))
        let respond = towFlat(towStrip(try #require(towDefinition("tetris_respond", in: mine)).body))
        let accept = "set status = 'active', accepted_at = v_start, seed = v_seed, start_at = null, opponent_session = public.tetris__session() where g.id = m.id and g.status = 'pending';"
        #expect(towCount(respond, accept) == 1, "수락 전이가 수락한 기기의 세션을 안 적는다")
        #expect(towCount(respond, "public.tetris__session()") == 1, "수락 말고 다른 자리(거절 등)에서도 세션을 적는다")
        let session = towFlat(towStrip(try #require(towDefinition("tetris__session", in: mine)).body))
        #expect(session == "begin return nullif(auth.jwt() ->> 'session_id', '')::uuid; exception when others then return null; end",
                "세션 도구가 클레임을 그대로 읽고 어떤 오류도 null 로 접는 한 줄이 아니다: \(session)")
        let claim = towFlat(towStrip(try #require(towDefinition("tetris__claim", in: mine)).body))
        #expect(claim.contains("where g.id = p_match_id and g.status = 'active' and ((p_uid = g.challenger and g.challenger_session is null) or (p_uid = g.opponent and g.opponent_session is null));"),
                "자리 잡기가 기록 없는 진행 중 판의 내 자리에만 걸려 있지 않다 — 남의 기록을 덮는다")
    }

    @Test("실행권 그대로: 다섯은 원래 grant 줄과 같고 revoke · drop 이 없다 · 도구 셋은 클라에서 닫고 service_role 만 · 인자는 전부 DEFAULT")
    func grantsAreUnchanged() throws {
        // 없으면: create or replace 뒤에 누가 실행권을 넓히거나(남의 판 자리를 잡는 도구가 열린다) 클라 RPC 를 닫아 대결이 통째로 멈춘다.
        let mine = towStrip(try towRaw(towMigration))
        let flatMine = towFlat(mine)
        let original = towFlat(towStrip(try towRaw(towDuelMigration)))
        let grants = [
            "grant execute on function public.tetris__state(uuid, uuid) to service_role;",
            "grant execute on function public.tetris_challenge(integer, uuid, integer) to authenticated, service_role;",
            "grant execute on function public.tetris_respond(integer, uuid, boolean) to authenticated, service_role;",
            "grant execute on function public.tetris_report(integer, uuid, integer, text, integer, integer, integer, integer, boolean) to authenticated, service_role;",
            "grant execute on function public.tetris_resign(integer, uuid) to authenticated, service_role;",
        ]
        for grant in grants {
            #expect(original.contains(grant), Comment(rawValue: "전제: 원래 파일의 grant 줄이 아니다: \(grant)"))
            #expect(flatMine.contains(grant), Comment(rawValue: "이 파일이 같은 grant 를 다시 주지 않는다: \(grant)"))
        }
        for name in ["tetris__state", "tetris_challenge", "tetris_respond", "tetris_report", "tetris_resign"] {
            #expect(!flatMine.contains("revoke all on function public.\(name)("), Comment(rawValue: "\(name) 의 실행권을 거둔다"))
            #expect(!flatMine.contains("drop function if exists public.\(name)("), Comment(rawValue: "\(name) 을 drop 한다(PGRST202 · ACL 유실)"))
        }
        #expect(!flatMine.contains("drop function public.") && !flatMine.contains("drop function if exists public."))
        for tool in ["tetris__session()", "tetris__device(uuid, uuid)", "tetris__claim(uuid, uuid)"] {
            #expect(flatMine.contains("revoke all on function public.\(tool) from public, anon, authenticated;"))
            #expect(flatMine.contains("grant execute on function public.\(tool) to service_role;"))
            #expect(!flatMine.contains("grant execute on function public.\(tool) to authenticated")
                    && !flatMine.contains("grant execute on function public.\(tool) to anon"), Comment(rawValue: "\(tool) 를 클라에게 연다"))
        }
        #expect(flatMine.contains("create or replace function public.tetris__device(p_match_id uuid default null, p_uid uuid default null)"))
        #expect(flatMine.contains("create or replace function public.tetris__claim(p_match_id uuid default null, p_uid uuid default null)"))
        #expect(flatMine.contains("create or replace function public.tetris__session() returns uuid"))
    }

    // MARK: ⑤ 적용 시점 가드 · 커밋 사본

    @Test("적용 시점 가드가 그대로다 — 잠금 3초 · 정본/재적용 md5 · 사후 단언 · 프로브 12건 · 센티널 롤백 · 스키마 리로드")
    func deployTimeGuardsAreIntact() throws {
        // 없으면: 운영 적용이 긴 트랜잭션 뒤에서 무한히 기다리거나, 프로브가 조용히 no-op 이 되거나, 프로브 행이 운영에 남는다.
        let sql = towStrip(try towRaw(towMigration))
        #expect(sql.contains("perform set_config('lock_timeout', '3s', true);"))
        #expect(sql.contains("lock table public.tetris_matches in access exclusive mode;"))
        #expect(sql.contains("elsif r.md5 = r.canon_md5 then") && sql.contains("elsif r.md5 = r.self_md5 then"))
        #expect(sql.contains("if not (v_first = 5 or v_again = 5) then"), "섞인 상태(일부만 손댄 서버)를 안 멈춘다")
        #expect(sql.contains("v_expected  constant int := 12;"), "프로브 기대 건수가 12 가 아니다")
        #expect(sql.contains("raise exception 'TETRIS_ONE_WRITER_PROBE_ROLLBACK';"), "센티널 롤백이 없다 — 프로브 행이 운영에 남는다")
        #expect(sql.contains("if sqlerrm = 'TETRIS_ONE_WRITER_PROBE_ROLLBACK' then"))
        #expect(sql.contains("notify pgrst, 'reload schema';"))
        // 최상위 트랜잭션 제어 금지(래퍼 트랜잭션을 깨면 원자 적용이 아니다).
        for line in sql.split(separator: "\n") {
            let code = line.trimmingCharacters(in: .whitespaces).lowercased()
            #expect(!(code == "begin;" || code == "commit;" || code == "rollback;"), Comment(rawValue: "최상위 트랜잭션 제어: \(code)"))
        }
        // RESET ROLE 금지(링크드 CLI 세션 42501) — 복귀는 set local role.
        #expect(!sql.lowercased().contains("reset role"))
    }

    @Test("커밋되는 사본(docs/plan/migrations-pending)이 체인 사본과 바이트까지 같다")
    func pendingCopyMatchesTheChain() throws {
        // 없으면: supabase/ 는 .gitignore 라 체인 사본만 고치면 커밋에 옛 판이 남고, 운영에 올리는 사람이 다른 파일을 민다.
        let chainCopy = try towMigrationsDirectory().appendingPathComponent(towMigration)
        let committed = try towRepoRoot().appendingPathComponent("docs/plan/migrations-pending/\(towMigration)")
        let a = try Data(contentsOf: chainCopy)
        let b = try Data(contentsOf: committed)
        #expect(a == b, "두 사본이 다르다 — 고친 쪽을 다른 쪽에 복사하라")
        #expect(a.count > 10_000)
    }
}
