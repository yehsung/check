import CryptoKit
import Foundation
import Testing
@testable import CheckCore

// 확성기 배너 — 서버 마이그레이션 계약(20261105120000_megaphone_banner.sql · docs/plan/megaphone-banner-contract.md S1~S6).
//
// 확성기를 메시지함 한 줄 대신 화면 배너로 띄우고, 앱 전체에 한 번에 하나(5분)만 나가게 한다. 서버는 전부 덧붙이기다.
// 마이그레이션은 **적용 시점에 자기를 증명한다**(§0 정본 본문 md5 · §8 사후 단언 · §9 실호출 프로브 13건 — 어긋나면 통째 롤백).
// 그 단언·프로브는 재생 하네스(tools/replay-harness-v2 사본)에서 체인 재생 + 세 번 적용으로 통과했다. 여기서 지키는 것은
// **사람 손이 저장소 안에서 조용히 깨뜨릴 수 있는 것**이다:
//   ① 이 파일이 세 함수의 마지막 정의이고, 본문 = 직전 정본 + 치환표(바이트). 새 셋은 이 파일이 처음 만든다.
//   ② §0 md5 핀이 정말 그 본문들의 md5 다.
//   ③ send_megaphone 순서(지갑 → 멱등 → 사람당 → 전역 자물쇠 → 앱 전체 창 → 차감) · scope 두 갈래 · 신호의 예외 삼키기.
//   ④ megaphone_info 의 남은 시간 = 둘 중 긴 쪽 · inbox 의 벽 한 줄 · v2 = v1 + 확성기 줄 제외 · 푸시의 megaphone_id 키.
//   ⑤ 1:1 보내기 · 대화 기록 · 안 읽음 v1 · 가격 상수를 다시 정의하지 않는다 · 커밋 사본이 체인 사본과 바이트까지 같다.
// 주석은 걷고 잰다(주석 안의 글자로 초록이 되지 않게 — 저장소 메모 '소스 계약 테스트는 주석 걷기').

private let mgbMigration = "20261105120000_megaphone_banner.sql"
private let mgbMegaphoneMigration = "20261014122000_megaphone.sql"
private let mgbStickerPushMigration = "20261022070340_sticker_push_label.sql"
private let mgbBlocksMigration = "20260918180000_blocks_and_reports.sql"
private let mgbPrevLatest = "20261104120000_rummy_v2.sql"

private struct MGBError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 라 git worktree 에는 없을 수 있다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫
/// 디렉토리를 잡는다(TetrisOneWriterMigrationTests 와 같은 방식). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다.
private func mgbMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MGBError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw MGBError("supabase/migrations 를 못 찾았다")
}

private func mgbRepoRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) { return directory }
        directory = directory.deletingLastPathComponent()
    }
    throw MGBError("저장소 꼭대기(Package.swift)를 못 찾았다")
}

private func mgbChain() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: try mgbMigrationsDirectory().path)
        .filter { $0.hasSuffix(".sql") }.sorted()
}

private func mgbRaw(_ name: String) throws -> String {
    try String(contentsOf: try mgbMigrationsDirectory().appendingPathComponent(name), encoding: .utf8)
}

/// SQL 줄 주석(`--` 부터 줄 끝)을 걷는다. 이 파일들의 본문 문자열에는 `--` 가 없다(— 는 긴 줄표 한 글자다).
private func mgbStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 공백 덩어리를 한 칸으로(줄바꿈·들여쓰기와 무관하게 문장을 견준다).
private func mgbFlat(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func mgbCount(_ haystack: String, _ needle: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

/// 첫 등장 위치(없으면 nil) — 순서 계약을 잴 때 쓴다.
private func mgbAt(_ haystack: String, _ needle: String) -> String.Index? {
    haystack.range(of: needle)?.lowerBound
}

/// 한 파일에서 `create or replace function public.<이름>(` 의 **마지막** 정의(머리 + 본문). 없으면 nil.
/// 달러 인용 태그는 파일마다 다르다(`$fn$` · `$send$`) — `as $태그$` 를 읽어 그 태그로 닫는다.
private func mgbDefinition(_ name: String, in sql: String) -> (header: String, body: String)? {
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

private func mgbMD5(_ text: String) -> String {
    Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// ★ Swift 의 `"""` 여러 줄 리터럴은 닫는 따옴표 들여쓰기를 걷으므로 SQL 들여쓰기를 바이트로 맞추려고 줄 배열로 쓴다.
private func mgbLines(_ lines: String...) -> String { lines.joined(separator: "\n") + "\n" }

private struct MGBPatch {
    let old: String
    let new: String
}

/// 치환표 — 직전 정본 본문의 `old`(정확히 1회) → `new`. 마이그레이션은 이 표를 적용해 만든 본문을 그대로 실었다.
private let mgbPatches: [(name: String, canon: String, patches: [MGBPatch])] = [
    ("send_megaphone", mgbMegaphoneMigration, [
        MGBPatch(old: mgbLines("  v_cool    constant int := public.megaphone_cooldown_seconds();"),
                 new: mgbLines("  v_cool    constant int := public.megaphone_cooldown_seconds();",
                               "  v_gcool   constant int := public.megaphone_global_cooldown_seconds();")),
        MGBPatch(old: mgbLines("  v_last    timestamptz;"),
                 new: mgbLines("  v_last    timestamptz;",
                               "  v_glast   timestamptz;")),
        MGBPatch(old: mgbLines(
                    "    return jsonb_build_object('status', 'cooldown', 'cooldown_seconds', v_cool,",
                    "                              'retry_after_seconds',",
                    "                              greatest(1, ceil(extract(epoch from (v_last + make_interval(secs => v_cool) - now())))::int));",
                    "  end if;"),
                 new: mgbLines(
                    "    return jsonb_build_object('status', 'cooldown', 'scope', 'self', 'cooldown_seconds', v_cool,",
                    "                              'retry_after_seconds',",
                    "                              greatest(1, ceil(extract(epoch from (v_last + make_interval(secs => v_cool) - now())))::int));",
                    "  end if;",
                    "",
                    "  -- 앱 전체 한 번에 하나(20261105120000): 누가 보내면 그 뒤 megaphone_global_cooldown_seconds() 동안 아무도 못 보낸다.",
                    "  --   멱등키 · 사람당 창 **뒤**라 같은 요청 재시도는 자기가 연 창에 안 막히고, 자기 창이면 self 로 답한다.",
                    "  --   자물쇠(지갑 다음 · 언제나 이 순서)를 쥔 뒤의 새 스냅숏으로 읽는다 — 동시에 온 두 사람 중 하나만 지난다.",
                    "  --   같은 쪽 계정(same_visibility)만 센다 — 숨김(심사 · 시험) 계정의 확성기가 실사용자를 막지 않는다.",
                    "  perform pg_advisory_xact_lock(hashtext('megaphone_global'));",
                    "  select max(m.created_at) into v_glast",
                    "    from public.megaphones m",
                    "   where m.created_at > now() - make_interval(secs => v_gcool)",
                    "     and public.same_visibility(uid, m.sender);",
                    "  if v_glast is not null and v_glast + make_interval(secs => v_gcool) > now() then",
                    "    return jsonb_build_object('status', 'cooldown', 'scope', 'global', 'cooldown_seconds', v_gcool,",
                    "                              'retry_after_seconds',",
                    "                              greatest(1, ceil(extract(epoch from (v_glast + make_interval(secs => v_gcool) - now())))::int));",
                    "  end if;")),
        MGBPatch(old: mgbLines(
                    "    if public.poke_ring(v_target) = 'sent' then v_sent := v_sent + 1; else v_failed := v_failed + 1; end if;",
                    "  end loop;"),
                 new: mgbLines(
                    "    if public.poke_ring(v_target) = 'sent' then v_sent := v_sent + 1; else v_failed := v_failed + 1; end if;",
                    "    -- 배너 신호(20261105120000): 새 앱은 이걸 듣고 megaphone_inbox 를 다시 부른다(payload 는 믿지 않는다). 옛 앱은 접는다.",
                    "    --   실패는 삼킨다 — 신호가 루비 차감 · fan-out 을 되돌리면 안 된다(초인종과 같은 결).",
                    "    begin",
                    "      perform realtime.send(jsonb_build_object('v', 1, 'm', v_id), 'megaphone', public.poke_topic(v_target), true);",
                    "    exception when others then",
                    "      raise warning 'send_megaphone: 배너 신호를 삼켰다(SQLSTATE %) — 루비 · 메시지는 그대로', sqlstate;",
                    "    end;",
                    "  end loop;")),
    ]),
    ("megaphone_info", mgbMegaphoneMigration, [
        MGBPatch(old: mgbLines("  v_remain int := 0;"),
                 new: mgbLines("  v_remain int := 0;",
                               "  v_glast  timestamptz;",
                               "  v_gleft  int := 0;")),
        MGBPatch(old: mgbLines("  select count(*)::int into v_n from public.megaphone__recipients(uid);"),
                 new: mgbLines(
                    "  -- 앱 전체 창(20261105120000): send_megaphone 과 같은 창 · 같은 쪽 계정의 마지막 확성기.",
                    "  select max(m.created_at) into v_glast",
                    "    from public.megaphones m",
                    "   where m.created_at > now() - make_interval(secs => public.megaphone_global_cooldown_seconds())",
                    "     and public.same_visibility(uid, m.sender);",
                    "  if v_glast is not null then",
                    "    v_gleft := greatest(0, ceil(extract(epoch from",
                    "                 (v_glast + make_interval(secs => public.megaphone_global_cooldown_seconds()) - now())))::int);",
                    "  end if;",
                    "  select count(*)::int into v_n from public.megaphone__recipients(uid);")),
        MGBPatch(old: mgbLines("    'cooldown_remaining_seconds', v_remain,"),
                 new: mgbLines(
                    "    -- 옛 앱 작성 화면은 이 한 칸만 본다 — 둘 중 긴 쪽이라야 \"N분 뒤에\" 가 맞는다.",
                    "    'cooldown_remaining_seconds', greatest(v_remain, v_gleft),",
                    "    'global_cooldown_seconds', public.megaphone_global_cooldown_seconds(),",
                    "    'global_cooldown_remaining_seconds', v_gleft,",
                    "    'cooldown_scope', case when v_remain > 0 and v_remain >= v_gleft then 'self'",
                    "                           when v_gleft > 0 then 'global' end,")),
    ]),
    ("push_on_message_insert", mgbStickerPushMigration, [
        MGBPatch(old: mgbLines("                   'collapse_id', null)));"),
                 new: mgbLines(
                    "                   'collapse_id', null))",
                    "      -- 확성기 줄만(20261105120000): 최상위 megaphone_id — 새 폰은 눌러 들어오면 배너로 띄운다. 평범한 1:1 은 키가 없다.",
                    "      || case when new.megaphone_id is not null",
                    "              then jsonb_build_object('megaphone_id', new.megaphone_id)",
                    "              else '{}'::jsonb end);")),
    ]),
]

/// 이 파일이 처음 만드는 셋(앞 파일에 정의가 없어야 한다).
private let mgbNewNames = ["megaphone_global_cooldown_seconds", "megaphone_inbox", "message_unread_summary_v2"]

/// 이 파일 본문(주석 걷음).
private func mgbBody(_ name: String) throws -> String {
    let def = try #require(mgbDefinition(name, in: try mgbRaw(mgbMigration)), "\(name) 을 이 파일이 정의하지 않는다")
    return mgbStrip(def.body)
}

@Suite("확성기 배너 — 서버 마이그레이션 계약(20261105120000)")
struct MegaphoneBannerMigrationTests {

    // MARK: ① 체인의 자리 · 마지막 정의 · 본문 = 정본 + 치환

    @Test("이 파일이 운영 마지막(rummy_v2) 뒤이고, 세 함수의 마지막 정의 · 직전 정의는 정본 파일 · 새 셋은 이 파일이 처음 만든다")
    func thisFileIsTheLatestDefinition() throws {
        // 없으면: 뒤 파일이 옛 본문(앱 전체 창 없는 send_megaphone)을 다시 깔아도 초록이다.
        let chain = try mgbChain()
        #expect(chain.count > 100, "마이그레이션을 \(chain.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
        let mine = try #require(chain.firstIndex(of: mgbMigration), "\(mgbMigration) 이 체인에 없다")
        for source in [mgbMegaphoneMigration, mgbStickerPushMigration, mgbBlocksMigration, mgbPrevLatest] {
            let at = try #require(chain.firstIndex(of: source), "\(source) 가 체인에 없다")
            #expect(at < mine, Comment(rawValue: "\(source) 가 이 파일보다 뒤다"))
        }
        for name in mgbPatches.map(\.name) + mgbNewNames {
            var last: String?
            var beforeMine: String?
            for file in chain {
                guard mgbDefinition(name, in: try mgbRaw(file)) != nil else { continue }
                if file < mgbMigration { beforeMine = file }
                last = file
            }
            #expect(last == mgbMigration, Comment(rawValue: "\(name) 의 마지막 정의가 \(last ?? "없음") 다 — 뒤 파일이 덮었다면 이 시험의 치환표를 그 파일로 옮겨라"))
            if let canon = mgbPatches.first(where: { $0.name == name })?.canon {
                #expect(beforeMine == canon, Comment(rawValue: "\(name) 의 직전 정의가 \(beforeMine ?? "없음") 다(기대 \(canon)) — 정본이 바뀌었다"))
            } else {
                #expect(beforeMine == nil, Comment(rawValue: "\(name) 은 이 파일이 처음 만든다(앞 정의 \(beforeMine ?? ""))"))
            }
        }
    }

    @Test("세 함수의 새 본문 = 직전 정본 본문 + 치환표(바이트) · 서명 머리는 한 글자도 안 바뀌었다")
    func copiedBodiesEqualCanonPlusPatches() throws {
        // 없으면: 베껴 온 본문의 한 줄(멱등키 · 차감 · fan-out · 푸시 type)이 여기서만 바뀌어도 운영 적용 전까지 아무도 모른다.
        let mine = try mgbRaw(mgbMigration)
        for entry in mgbPatches {
            let canon = try #require(mgbDefinition(entry.name, in: try mgbRaw(entry.canon)), "\(entry.name) 정본이 없다")
            let after = try #require(mgbDefinition(entry.name, in: mine), "\(entry.name) 을 이 파일이 정의하지 않는다")
            #expect(after.header == canon.header, Comment(rawValue: "\(entry.name) 의 서명 머리가 바뀌었다 — 바꾸면 옛 서명 drop · ACL 재부여가 필요하다(PGRST203)"))
            var expected = canon.body
            for patch in entry.patches {
                #expect(mgbCount(canon.body, patch.old) == 1, Comment(rawValue: "\(entry.name): 정본에서 치환 자리를 \(mgbCount(canon.body, patch.old))번 찾았다(기대 1)"))
                #expect(mgbCount(canon.body, patch.new) == 0, Comment(rawValue: "\(entry.name): 정본에 이미 새 글이 있다 — 치환표가 낡았다"))
                expected = expected.replacingOccurrences(of: patch.old, with: patch.new)
            }
            // 비교 기준선: 정본 그대로는 이 파일 본문이 아니다(치환이 실제로 본문을 바꿨다).
            #expect(canon.body != after.body, Comment(rawValue: "\(entry.name): 이 파일 본문이 정본과 같다 — 치환이 빠졌다"))
            #expect(after.body == expected, Comment(rawValue: "\(entry.name) 본문이 '정본 + 치환표' 와 다르다 — 베껴 온 본문이 흘러내렸다"))
        }
    }

    // MARK: ② §0 md5 핀

    @Test("§0 핀: 정본 md5 = 정본 본문의 md5 · 재적용 md5 = 이 파일 본문의 md5(셋 모두) · 정본은 재생 클러스터에서 뜬 값과 같다")
    func md5PinsMatchTheBodies() throws {
        // 없으면: 핀이 낡아 운영 db push 가 '정본이 아니다' 로 멈추거나, 재적용 판정이 엉뚱한 본문을 덮는다.
        let mine = try mgbRaw(mgbMigration)
        let flat = mgbFlat(mine)
        let signatures = [
            "send_megaphone": "public.send_megaphone(text,uuid)",
            "megaphone_info": "public.megaphone_info()",
            "push_on_message_insert": "public.push_on_message_insert()",
        ]
        // 2026-10-30 로컬 재생 클러스터(체인 전체 적용)에서 md5(prosrc) 로 뜬 값.
        let measuredCanon = [
            "send_megaphone": "da0ec946b8cb1cf01acad8ba26dba2b1",
            "megaphone_info": "aac80255efae548333eb9b2a71f0bb1f",
            "push_on_message_insert": "ebbeefee1a3296d78a362fa36bc8e440",
        ]
        for entry in mgbPatches {
            let canon = try #require(mgbDefinition(entry.name, in: try mgbRaw(entry.canon)))
            let after = try #require(mgbDefinition(entry.name, in: mine))
            let canonMD5 = mgbMD5(canon.body)
            let selfMD5 = mgbMD5(after.body)
            #expect(canonMD5 == measuredCanon[entry.name], Comment(rawValue: "\(entry.name) 정본 본문 md5 \(canonMD5) 가 재생 클러스터 값과 다르다 — 정본 파일이 바뀌었다"))
            #expect(canonMD5 != selfMD5, Comment(rawValue: "\(entry.name): 정본과 이 파일 md5 가 같다 — 첫 적용/재적용을 못 가른다"))
            let sig = try #require(signatures[entry.name])
            #expect(flat.contains("('\(sig)', '\(canonMD5)', '\(selfMD5)')"),
                    Comment(rawValue: "§0 핀 줄이 (\(sig), 정본 \(canonMD5), 이 파일 \(selfMD5)) 가 아니다 — 본문을 고쳤으면 핀도 고쳐라"))
        }
    }

    // MARK: ③ send_megaphone — 순서 · scope 두 갈래 · 신호

    @Test("send_megaphone 순서: 지갑 자물쇠 → 멱등키 → 사람당 창(self) → 전역 자물쇠 → 앱 전체 창(global) → 받는 사람 → 차감")
    func sendMegaphoneOrder() throws {
        // 없으면: 앱 전체 창이 멱등키 앞이면 같은 요청 재시도가 자기가 연 창에 막혀 '실패' 로 보이고(돈은 이미 나갔다),
        //         차감 뒤면 막힌 사람의 루비가 나간다. 자물쇠가 확인 뒤면 동시에 온 두 사람이 둘 다 지난다.
        let body = try mgbBody("send_megaphone")
        let order = [
            "perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || uid::text));",
            "select m.* into v_prev from public.megaphones m where m.sender = uid and m.request_id = v_req;",
            "return jsonb_build_object('status', 'cooldown', 'scope', 'self',",
            "perform pg_advisory_xact_lock(hashtext('megaphone_global'));",
            "select max(m.created_at) into v_glast",
            "return jsonb_build_object('status', 'cooldown', 'scope', 'global',",
            "from public.megaphone__recipients(uid) as r(id);",
            "update public.profiles set ruby_balance = ruby_balance - v_price",
        ]
        var previous: String.Index?
        for token in order {
            #expect(mgbCount(body, token) == 1, Comment(rawValue: "send_megaphone 에 \"\(token)\" 이 \(mgbCount(body, token))번이다(기대 1)"))
            guard let at = mgbAt(body, token) else { continue }
            if let previous { #expect(previous < at, Comment(rawValue: "send_megaphone 에서 \"\(token)\" 이 앞 단계보다 앞이다")) }
            previous = at
        }
        // 비교 기준선: 정본에는 전역 자물쇠가 없다 — 이 순서는 이 파일이 만든 것이다.
        let canon = mgbStrip(try #require(mgbDefinition("send_megaphone", in: try mgbRaw(mgbMegaphoneMigration))).body)
        #expect(!canon.contains("megaphone_global"))
        // 전역 자물쇠는 이 함수만 쥔다(다른 함수가 쥐면 지갑 → 전역 순서가 깨져 교착이 생길 수 있다).
        for file in try mgbChain() where file != mgbMigration {
            #expect(!mgbStrip(try mgbRaw(file)).contains("hashtext('megaphone_global')"),
                    Comment(rawValue: "\(file) 이 megaphone_global 자물쇠를 쥔다 — 잠금 순서를 다시 따져라"))
        }
    }

    @Test("scope 두 갈래: 사람당은 self + 사람당 초, 앱 전체는 global + 앱 전체 초 · 앱 전체 창은 같은 쪽 계정만 · 상수는 함수로")
    func cooldownScopes() throws {
        // 없으면: 숨김(심사) 계정의 확성기가 실사용자 5분을 막거나, 새 앱이 '다음 확성기까지' 와 '내 쿨' 을 못 가른다.
        let body = mgbFlat(try mgbBody("send_megaphone"))
        #expect(body.contains("return jsonb_build_object('status', 'cooldown', 'scope', 'self', 'cooldown_seconds', v_cool, 'retry_after_seconds', greatest(1, ceil(extract(epoch from (v_last + make_interval(secs => v_cool) - now())))::int));"))
        #expect(body.contains("return jsonb_build_object('status', 'cooldown', 'scope', 'global', 'cooldown_seconds', v_gcool, 'retry_after_seconds', greatest(1, ceil(extract(epoch from (v_glast + make_interval(secs => v_gcool) - now())))::int));"))
        #expect(body.contains("from public.megaphones m where m.created_at > now() - make_interval(secs => v_gcool) and public.same_visibility(uid, m.sender);"),
                "앱 전체 창이 같은 쪽 계정(same_visibility)으로 안 잰다")
        #expect(body.contains("v_gcool constant int := public.megaphone_global_cooldown_seconds();"))
        #expect(body.contains("v_price constant int := public.megaphone_ruby_price();"), "가격을 megaphone_ruby_price() 로 안 부른다(V0354)")
        #expect(!body.contains("300"), "앱 전체 초를 리터럴로 적었다 — 상수 함수만 부른다")
        #expect(mgbCount(body, "'status', 'cooldown'") == 2, "cooldown 응답이 두 갈래가 아니다")
        // 비교 기준선: 정본의 cooldown 응답에는 scope 가 없다(옛 앱이 받던 모양 — 키만 더했다).
        let canon = mgbFlat(mgbStrip(try #require(mgbDefinition("send_megaphone", in: try mgbRaw(mgbMegaphoneMigration))).body))
        #expect(canon.contains("return jsonb_build_object('status', 'cooldown', 'cooldown_seconds', v_cool,"))
        #expect(!canon.contains("'scope'"))
        // 상수: immutable 300 · PUBLIC 실행권을 회수하지 않는다(42501 함정).
        let constant = try #require(mgbDefinition("megaphone_global_cooldown_seconds", in: try mgbRaw(mgbMigration)))
        #expect(mgbFlat(constant.header + "as $fn$" + constant.body) == "create or replace function public.megaphone_global_cooldown_seconds() returns int language sql immutable as $fn$ select 300")
        #expect(!mgbStrip(try mgbRaw(mgbMigration)).contains("on function public.megaphone_global_cooldown_seconds() from"),
                "상수의 실행권을 회수한다 — definer 함수가 42501 로 죽는다")
    }

    @Test("배너 신호: 받는 사람마다 초인종 다음에 realtime 'megaphone' {v:1, m:id} · 예외는 삼킨다(루비 · fan-out 을 안 되돌린다)")
    func megaphoneSignalIsSwallowed() throws {
        // 없으면: 신호 실패가 트랜잭션을 되돌려 확성기가 통째로 사라지거나, 새 앱이 확성기 울림과 DM 울림을 못 가른다.
        let body = mgbFlat(try mgbBody("send_megaphone"))
        let loop = "foreach v_target in array v_targets loop if public.poke_ring(v_target) = 'sent' then v_sent := v_sent + 1; else v_failed := v_failed + 1; end if; begin perform realtime.send(jsonb_build_object('v', 1, 'm', v_id), 'megaphone', public.poke_topic(v_target), true); exception when others then raise warning"
        #expect(body.contains(loop), "신호가 초인종 다음 · begin/exception 안에 없다")
        #expect(mgbCount(body, "realtime.send(") == 1)
        // 신호는 fan-out(messages 삽입) 뒤 — 새 앱이 신호를 듣고 부르는 inbox 가 그 줄을 본다.
        let insert = try #require(mgbAt(body, "insert into public.messages (from_user, to_user, body, megaphone_id)"))
        let signal = try #require(mgbAt(body, "'megaphone', public.poke_topic(v_target), true)"))
        #expect(insert < signal)
        // 비교 기준선: 정본의 초인종 줄 뒤에는 바로 end loop 다.
        let canon = mgbFlat(mgbStrip(try #require(mgbDefinition("send_megaphone", in: try mgbRaw(mgbMegaphoneMigration))).body))
        #expect(canon.contains("v_failed := v_failed + 1; end if; end loop;"))
        #expect(!canon.contains("realtime.send("))
    }

    // MARK: ④ info · inbox · v2 · 푸시

    @Test("megaphone_info: 남은 시간 = max(사람당, 앱 전체) · 새 키 셋 · 옛 키 전부 그대로 · 앱 전체 창은 send 와 같은 술어")
    func megaphoneInfoKeys() throws {
        // 없으면: 옛 앱 작성 화면이 앱 전체 창 동안 '지금 보낼 수 있어요' 를 말하고 보내면 막힌다.
        let body = mgbFlat(try mgbBody("megaphone_info"))
        #expect(body.contains("'cooldown_remaining_seconds', greatest(v_remain, v_gleft),"))
        #expect(body.contains("'global_cooldown_seconds', public.megaphone_global_cooldown_seconds(),"))
        #expect(body.contains("'global_cooldown_remaining_seconds', v_gleft,"))
        #expect(body.contains("'cooldown_scope', case when v_remain > 0 and v_remain >= v_gleft then 'self' when v_gleft > 0 then 'global' end,"))
        #expect(body.contains("where m.created_at > now() - make_interval(secs => public.megaphone_global_cooldown_seconds()) and public.same_visibility(uid, m.sender);"))
        #expect(body.contains("'price', public.megaphone_ruby_price(),"), "가격을 megaphone_ruby_price() 로 안 부른다(V0354)")
        for key in ["'status', 'ok'", "'enabled',", "'price',", "'cooldown_seconds',", "'recipients',", "'max_length',", "'ruby_balance',"] {
            #expect(body.contains(key), Comment(rawValue: "megaphone_info 에서 옛 키 \(key) 가 빠졌다 — 옛 앱 디코드가 깨진다"))
        }
        // 비교 기준선: 정본은 사람당 남은 초만 말했다.
        let canon = mgbFlat(mgbStrip(try #require(mgbDefinition("megaphone_info", in: try mgbRaw(mgbMegaphoneMigration))).body))
        #expect(canon.contains("'cooldown_remaining_seconds', v_remain,"))
    }

    @Test("megaphone_inbox: 벽은 to_user = auth.uid() 한 줄 · 확성기 표식 · 차단 · 24시간 상한 · 최신 20 · 로그인만 · 인자 DEFAULT")
    func inboxWall() throws {
        // 없으면: 남이 받은 확성기 줄이 보이거나(벽), 아무나 보낸 📢 1:1 이 배너가 되거나(표식), 차단한 사람이 화면에 뜬다.
        let raw = try mgbRaw(mgbMigration)
        let def = try #require(mgbDefinition("megaphone_inbox", in: raw))
        let body = mgbFlat(mgbStrip(def.body))
        #expect(mgbFlat(def.header).hasPrefix("create or replace function public.megaphone_inbox(p_hours integer default 24) returns table(message_id uuid, megaphone_id uuid, sender_id uuid, sender_display_name text, sender_avatar_url text, body text, created_at timestamptz, created_epoch bigint) language sql stable security definer set search_path = public"))
        #expect(mgbCount(body, "to_user") == 1, "벽 줄 말고 to_user 를 또 본다 — 벽은 한 줄이다")
        #expect(body.contains("where m.to_user = auth.uid() and m.megaphone_id is not null and not public.blocked_between(auth.uid(), m.from_user) and m.created_at >= now() - make_interval(hours => least(greatest(coalesce(p_hours, 24), 1), 24))"))
        #expect(body.contains("order by m.created_at desc, m.id desc limit 20"))
        #expect(body.contains("left join public.profiles pr on pr.id = m.from_user"), "profiles 를 함수 안에서 조인하지 않는다(임베드 모호성)")
        #expect(body.contains("coalesce(pr.display_name, '사용자')"))
        #expect(body.contains("then substr(m.body, char_length(public.megaphone_prefix()) + 1)"), "본문 접두를 안 뗀다")
        #expect(!body.contains("📢"), "접두를 리터럴로 적었다 — megaphone_prefix() 만 부른다")
        let flat = mgbFlat(mgbStrip(raw))
        #expect(flat.contains("revoke all on function public.megaphone_inbox(integer) from public, anon; grant execute on function public.megaphone_inbox(integer) to authenticated;"))
        // 비교 기준선: 표식 없는 대화 기록 RPC 는 확성기 줄을 가르지 않는다 — 가르는 근거는 megaphone_id 하나뿐이다.
        #expect(!body.contains("like") && !body.contains("starts_with"), "본문 접두로 확성기를 고른다 — 아무나 📢 로 쓸 수 있다")
    }

    @Test("message_unread_summary_v2 = 안 읽음 v1 본문(20260918180000) + 확성기 줄 제외 한 줄 · v1 은 그대로")
    func unreadSummaryV2() throws {
        // 없으면: 새 앱이 확성기 줄을 숨겨도 서버가 세어 배지(메뉴바 점 · 탭 · 아이콘)가 영영 안 꺼진다.
        let v1 = try #require(mgbDefinition("message_unread_summary", in: try mgbRaw(mgbBlocksMigration)), "v1 정본이 없다")
        let v2 = try #require(mgbDefinition("message_unread_summary_v2", in: try mgbRaw(mgbMigration)))
        let added = mgbLines(
            "         -- 확성기 줄(20261105120000): 배너로만 보이고 메시지함에 없다 — 세면 배지가 꺼지지 않는다.",
            "         and m.megaphone_id is null")
        #expect(mgbCount(v2.body, added) == 1, "v2 에 확성기 줄 제외 한 줄이 없다")
        // v2 에서 그 한 줄을 빼면 v1 본문과 바이트까지 같다 — 벽 · 차단 · 보존 시간 · 읽음 경계는 v1 그대로다.
        #expect(v2.body.replacingOccurrences(of: added, with: "") == v1.body, "v2 가 v1 본문 + 한 줄이 아니다")
        #expect(mgbFlat(v2.header) == mgbFlat(v1.header).replacingOccurrences(of: "message_unread_summary(", with: "message_unread_summary_v2("))
        // 비교 기준선: v1 은 확성기 줄을 센다.
        #expect(!v1.body.contains("megaphone_id"))
        let flat = mgbFlat(mgbStrip(try mgbRaw(mgbMigration)))
        #expect(flat.contains("revoke all on function public.message_unread_summary_v2() from public, anon; grant execute on function public.message_unread_summary_v2() to authenticated;"))
    }

    @Test("푸시: 확성기 줄일 때만 최상위 megaphone_id · type message · category MESSAGE · 이모티콘 라벨 · 예외 삼키기 그대로")
    func pushPayloadKey() throws {
        // 없으면: 새 폰이 확성기 푸시를 눌러도 배너를 못 띄우거나, 아무 1:1 이 megaphone_id 를 달아 배너가 된다.
        let body = mgbFlat(try mgbBody("push_on_message_insert"))
        #expect(body.contains("'collapse_id', null)) || case when new.megaphone_id is not null then jsonb_build_object('megaphone_id', new.megaphone_id) else '{}'::jsonb end);"))
        #expect(mgbCount(body, "'megaphone_id'") == 1)
        for token in ["'category', 'MESSAGE',", "'type', 'message',", "'body', public.sticker_push_label(new.body)),",
                      "'thread-id', 'message-' || new.from_user::text),", "exception when others then raise warning 'push_on_message_insert: 발송함 적재를 삼켰다"] {
            #expect(body.contains(token), Comment(rawValue: "푸시에서 \(token) 이 빠졌다 — 옛 폰이 의존한다"))
        }
        // 비교 기준선: 정본 페이로드에는 확성기 표식이 없다.
        let canon = mgbFlat(mgbStrip(try #require(mgbDefinition("push_on_message_insert", in: try mgbRaw(mgbStickerPushMigration))).body))
        #expect(!canon.contains("megaphone_id"))
    }

    // MARK: ⑤ 건드리지 않는 것 · 적용 시점 가드 · 커밋 사본

    @Test("다시 정의하지 않는다: 1:1 보내기 · 대화 기록 · 안 읽음 v1 · 가격 상수 · 대화+찌르기 기록(주석 포함 원문)")
    func doesNotRedefineGatedFunctions() throws {
        // 없으면: V0333 관문 · 멱등 시험 · V0354 · V0365 가 이 파일을 '마지막 정의' 로 잡아 빨갛게 되거나, 옛 앱 RPC 가 바뀐다.
        let raw = try mgbRaw(mgbMigration)
        for name in ["send_message", "message_history", "message_unread_summary", "megaphone_ruby_price",
                     "message_history_with_pokes", "message_history_with_reads"] {
            #expect(!raw.contains("function public.\(name)("), Comment(rawValue: "원문(주석 포함)에 function public.\(name)( 가 있다"))
        }
        // 비교 기준선: v2 의 이름은 v1 정규식(function public.message_unread_summary\() 에 안 걸린다.
        #expect(raw.contains("function public.message_unread_summary_v2("))
        // 인자는 전부 DEFAULT(PGRST202 전례).
        for name in ["send_megaphone", "megaphone_inbox"] {
            let header = try #require(mgbDefinition(name, in: raw)).header
            let args = header.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
            for arg in args.split(separator: ",") {
                #expect(arg.lowercased().contains(" default "), Comment(rawValue: "\(name) 의 인자 \(arg) 에 DEFAULT 가 없다"))
            }
        }
    }

    @Test("적용 시점 가드가 그대로다 — 잠금 3초 · 정본/재적용 md5 · 사후 단언 · 프로브 13건 · 센티널 롤백 · 스키마 리로드")
    func deployTimeGuardsAreIntact() throws {
        // 없으면: 운영 적용이 프로브 없이 지나가거나, 프로브의 확성기 · 메시지 · 발송함 행이 운영에 남는다.
        let raw = try mgbRaw(mgbMigration)
        let sql = mgbStrip(raw)
        #expect(sql.contains("perform set_config('lock_timeout', '3s', true);"))
        #expect(sql.contains("elsif r.md5 = r.canon_md5 then") && sql.contains("elsif r.md5 = r.self_md5 then"))
        #expect(sql.contains("if not (v_first = 3 or v_again = 3) then"), "섞인 상태(일부만 손댄 서버)를 안 멈춘다")
        #expect(sql.contains("v_expected  constant int := 13;"), "프로브 기대 건수가 13 이 아니다")
        #expect(sql.contains("raise exception 'MEGAPHONE_BANNER_PROBE_ROLLBACK';"), "센티널 롤백이 없다 — 프로브 행이 운영에 남는다")
        #expect(sql.contains("if sqlerrm = 'MEGAPHONE_BANNER_PROBE_ROLLBACK' then"))
        #expect(sql.contains("notify pgrst, 'reload schema';"))
        // 프로브가 재는 갈래(전역 · 멱등 · 사람당 · 숨김 · v2 · 푸시) — 실호출 줄이 그대로 있다.
        let flat = mgbFlat(sql)
        for token in ["v := pg_temp.mgb_send(b, '나도 보낸다', gen_random_uuid()); if v ->> 'status' is distinct from 'cooldown' or v ->> 'scope' is distinct from 'global'",
                      "v := pg_temp.mgb_send(a, '실사용자 확성기', ra); if v ->> 'status' is distinct from 'ok' or (v ->> 'duplicate')::boolean is distinct from true",
                      "v := pg_temp.mgb_send(a, '또 보낸다', gen_random_uuid()); if v ->> 'status' is distinct from 'cooldown' or v ->> 'scope' is distinct from 'self'",
                      "v := pg_temp.mgb_send(h1, '숨김 쪽 확성기', gen_random_uuid()); if v ->> 'status' is distinct from 'ok' then",
                      "(v2 ->> 'total')::int - (v2_0 ->> 'total')::int is distinct from 1",
                      "or v ? 'megaphone_id' or v ->> 'type' is distinct from 'message' then"] {
            #expect(flat.contains(token), Comment(rawValue: "§9 프로브에서 실호출 줄이 빠졌다: \(token.prefix(60))"))
        }
        for line in sql.split(separator: "\n") {
            let code = line.trimmingCharacters(in: .whitespaces).lowercased()
            #expect(!(code == "begin;" || code == "commit;" || code == "rollback;"), Comment(rawValue: "최상위 트랜잭션 제어: \(code)"))
        }
        #expect(!sql.lowercased().contains("reset role"))
        // do 블록 주석에 달러 인용 태그 글자 금지(태그를 닫아 본문이 끊긴다). 주석 줄만 본다.
        for line in raw.split(separator: "\n") {
            guard let range = line.range(of: "--") else { continue }
            let comment = line[range.upperBound...]
            #expect(comment.range(of: #"\$[a-z_]*\$"#, options: .regularExpression) == nil,
                    Comment(rawValue: "주석에 달러 인용 태그 글자가 있다: \(line)"))
        }
    }

    @Test("커밋되는 사본(docs/plan/migrations-pending)이 체인 사본과 바이트까지 같다")
    func pendingCopyMatchesTheChain() throws {
        // 없으면: supabase/ 는 .gitignore 라 체인 사본만 고치면 커밋에 옛 판이 남고, 운영에 올리는 사람이 다른 파일을 민다.
        let chainCopy = try mgbMigrationsDirectory().appendingPathComponent(mgbMigration)
        let committed = try mgbRepoRoot().appendingPathComponent("docs/plan/migrations-pending/\(mgbMigration)")
        let a = try Data(contentsOf: chainCopy)
        let b = try Data(contentsOf: committed)
        #expect(a == b, "두 사본이 다르다 — 고친 쪽을 다른 쪽에 복사하라")
        #expect(a.count > 10_000)
    }
}
