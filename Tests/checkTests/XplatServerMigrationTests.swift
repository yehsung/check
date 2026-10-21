import Foundation
import Testing

// xplat(Android·Windows) 서버 초안 M1~M5 의 **파일 계약**.
//
// 초안은 저장소 밖 비공개 스테이징에 있다(맥 출시의 db push 가 에이전트 초안까지 올리지 않게 — supabase/ 는 git 밖).
// 스테이징은 환경변수 `CHECK_XPLAT_STAGING` 으로 받는다.
//   · 없거나 빈 값 → 스테이징 전용 묶음은 건너뛴다(체인 묶음은 아래 문턱을 따른다).
//   · `1` → 기본 스테이징 경로 `$HOME/.claude/projects/-Users-yesung-check/xplat-staging`.
//   · 그 밖의 값 → 그 경로.
//   · 값이 있는데 `migrations-draft/` 를 가진 디렉터리가 아니면 **빨강**이다(조용히 건너뛰어 "통과"로 찍히지 않게).
// 기본 체인은 `CHECK_MIGRATIONS_DIR`(다른 마이그레이션 시험과 같은 이름) 또는 조상의 `supabase/migrations` 다 — 워크트리에는
// 그 폴더가 없으니 덮어써서 돌린다.
//
// **단계별 문턱**: 서버 ①(M1~M3) · ③(+M4) · ④(+M5)는 초안을 나눠 옮긴다. 체인 묶음은 "이번 체인에 들어온 초안"만 잰다 —
// 스테이징이 있으면 다섯 다, 없으면 기본 체인에 옮겨진 것만(M1 부터 끊김 없이). M4·M5 를 보는 단언은 그 초안이 들어온
// 모양에서만 돈다. 아직 안 옮긴 단계는 그 단계의 대조(예: M5 전에는 fork_safe 리터럴이 M5 대상 세 함수에만 있다)로 잰다.
//
// 행동은 초안 자신이 증명한다(사후 단언 · 센티널 롤백 프로브 — 하네스에서 3회 멱등). 여기서 보는 것은 SQL 단언이 적용 순간에만
// 도는 규칙을 **파일 기준으로 영구히** 재는 것이다(B§2-6): 마지막 정의가 초안인가, ios 만 아는 함수가 없는가, 발송 경로 계약,
// fork_safe 리터럴 0, 정본 md5 핀, V0341 등록 패치, 되돌림 초안, payload 정본 두 벌이 같은가.
// 각 시험의 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가" 다.

private struct XpError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private enum Xp {
    static let order = ["M1", "M2", "M3", "M4", "M5"]
    static let drafts = [
        "M1": "_client_platforms_android_windows.sql",
        "M2": "_device_capable_platforms.sql",
        "M3": "_desktop_windows_axis.sql",
        "M4": "_push_fcm_desktop_suppress.sql",
        "M5": "_token_fork_safe_windows.sql",
    ]
    /// `CHECK_XPLAT_STAGING=1` 이 가리키는 곳(HOME 아래 · 메인 체크아웃 /Users/yesung/check 의 Claude 프로젝트 폴더).
    static let defaultStagingSuffix = ".claude/projects/-Users-yesung-check/xplat-staging"

    enum StagingSetting {
        case absent
        case dir(URL)
        case invalid(String)
    }

    static let stagingSetting: StagingSetting = {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["CHECK_XPLAT_STAGING"], !raw.isEmpty else { return .absent }
        let path: String
        if raw == "1" {
            let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
            path = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(defaultStagingSuffix).path
        } else {
            path = raw
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return .invalid("CHECK_XPLAT_STAGING=\(raw) → \(path) 가 디렉터리가 아니다(1 = 기본 스테이징 경로, 그 밖은 경로)")
        }
        let draftDir = url.appendingPathComponent("migrations-draft", isDirectory: true)
        guard FileManager.default.fileExists(atPath: draftDir.path, isDirectory: &isDir), isDir.boolValue else {
            return .invalid("CHECK_XPLAT_STAGING=\(raw) → \(path) 에 migrations-draft/ 가 없다 — 스테이징 폴더가 아니다")
        }
        return .dir(url)
    }()

    /// 변수가 있다(올바르든 아니든). 있으면 스테이징 전용 묶음이 돌고, 틀린 값이면 그 안에서 빨갛다.
    static var stagingRequested: Bool {
        if case .absent = stagingSetting { return false }
        return true
    }

    static var staging: URL? {
        if case .dir(let url) = stagingSetting { return url }
        return nil
    }

    static func stagingDir() throws -> URL {
        switch stagingSetting {
        case .dir(let url): return url
        case .invalid(let message): throw XpError(message)
        case .absent: throw XpError("CHECK_XPLAT_STAGING 이 없다(건너뛰어야 했다)")
        }
    }

    /// 기본 체인(supabase/migrations)에 이미 옮겨진 초안 단계(이름 꼬리로 찾는다).
    static let baseDraftStages: [String] = order.filter { baseHasDraft($0) }

    /// 이번 실행의 체인에 들어온 초안 단계 — 스테이징이 있으면 다섯 다(합친다), 없으면 기본 체인에 옮겨진 것만.
    static let stages: [String] = stagingRequested ? order : baseDraftStages

    static func has(_ m: String) -> Bool { stages.contains(m) }

    /// 체인 기준 묶음의 문턱. 지금은 스테이징이 있을 때만 돈다(초안이 저장소 밖에 있다).
    /// 서버 ① 커밋(M1~M3 을 supabase/migrations 로 옮기는 커밋)에서 swift-patches/0002 가 이 줄을
    /// `stagingRequested || !baseDraftStages.isEmpty` 로 바꿔 상시로 켠다. 빠뜨리면 `xplat_스테이징_변수와_단계_문턱` 이 빨갛다.
    static var chainEnabled: Bool { stagingRequested }

    static func baseHasDraft(_ m: String) -> Bool {
        guard let base = try? baseMigrations(), let names = try? sqlFiles(base) else { return false }
        return names.contains { $0.hasSuffix(drafts[m]!) }
    }

    static func baseMigrations() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { throw XpError("CHECK_MIGRATIONS_DIR 가 없다: \(override)") }
            return url
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let c = dir.appendingPathComponent("supabase/migrations", isDirectory: true)
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir = dir.deletingLastPathComponent()
        }
        throw XpError("기본 체인(supabase/migrations)을 못 찾았다 — 워크트리라면 CHECK_MIGRATIONS_DIR 로 128개 사본을 주어라")
    }

    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        throw XpError("저장소 꼭대기(Package.swift)를 못 찾았다")
    }

    static func sqlFiles(_ dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".sql") }.sorted()
    }

    static func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    /// 기본 체인 ∪ 초안(이름 순 · 스테이징이 있을 때). 같은 이름이 양쪽에 있으면(서버 ① 뒤) 바이트가 같아야 한다.
    static func mergedChain() throws -> [(name: String, url: URL)] {
        let base = try baseMigrations()
        var byName: [String: URL] = [:]
        for n in try sqlFiles(base) { byName[n] = base.appendingPathComponent(n) }
        guard stagingRequested else { return byName.keys.sorted().map { ($0, byName[$0]!) } }
        let draftDir = try stagingDir().appendingPathComponent("migrations-draft", isDirectory: true)
        for n in try sqlFiles(draftDir) {
            let d = draftDir.appendingPathComponent(n)
            if let existing = byName[n], try read(existing) != read(d) {
                throw XpError("\(n) 이 기본 체인과 스테이징에 **다른 내용**으로 있다 — 옮긴 뒤 고쳤으면 한쪽을 맞춰라")
            }
            byName[n] = d
        }
        return byName.keys.sorted().map { ($0, byName[$0]!) }
    }

    /// 초안 파일(합친 체인에서 이름 꼬리로 찾는다 — 서버 ① 뒤에는 기본 체인에 있다). 이번 체인에 안 들어온 단계를 부르면 오류다.
    static func draft(_ m: String) throws -> (name: String, url: URL) {
        guard has(m) else { throw XpError("\(m) 은 이번 체인에 들어온 단계(\(stages))가 아니다 — 시험이 단계 문턱을 빠뜨렸다") }
        let hits = try mergedChain().filter { $0.name.hasSuffix(drafts[m]!) }
        guard hits.count == 1 else { throw XpError("\(m) 초안(*\(drafts[m]!))이 체인에 \(hits.count)개다") }
        return hits[0]
    }

    static func draftName(_ m: String) throws -> String { try draft(m).name }

    static func stripLineComment(_ line: Substring) -> Substring {
        if let r = line.range(of: "--") { return line[line.startIndex..<r.lowerBound] }
        return line
    }

    /// 이 파일의 정의 머리(같은 줄에 create 가 있는 `function public.<이름>(` — 주석 부분은 걷고 본다).
    /// 이름마다 **마지막** 머리의 위치(sql 의 인덱스)를 한 번의 줄 훑기로 모은다.
    static func definitionHeads(_ sql: String) -> [(name: String, head: String.Index)] {
        var order: [String] = []
        var last: [String: String.Index] = [:]
        for raw in sql.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = stripLineComment(raw)
            guard code.range(of: "create", options: .caseInsensitive) != nil,
                  let r = code.range(of: "function public.", options: .caseInsensitive) else { continue }
            let rest = code[r.upperBound...]
            guard let p = rest.firstIndex(of: "(") else { continue }
            let name = String(rest[rest.startIndex..<p]).trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, !name.contains(where: { $0.isWhitespace || $0 == "\"" }) else { continue }
            if last[name] == nil { order.append(name) }
            last[name] = r.lowerBound
        }
        return order.map { ($0, last[$0]!) }
    }

    static func definedFunctions(_ sql: String) -> [String] { definitionHeads(sql).map(\.name) }

    /// 머리 위치에서 시작하는 정의의 본문(원문 — `as $태그$` 와 같은 태그 사이).
    static func body(at head: String.Index, in sql: String) -> String? {
        guard let asR = sql.range(of: "as $", options: .caseInsensitive, range: head..<sql.endIndex) else { return nil }
        let tagStart = sql.index(before: asR.upperBound)
        guard let tagEnd = sql[sql.index(after: tagStart)...].firstIndex(of: "$") else { return nil }
        let tag = sql[tagStart...tagEnd]
        let bodyStart = sql.index(after: tagEnd)
        guard let close = sql.range(of: tag, range: bodyStart..<sql.endIndex) else { return nil }
        return String(sql[bodyStart..<close.lowerBound])
    }

    static func lastBody(_ name: String, in sql: String) -> String? {
        guard let h = definitionHeads(sql).last(where: { $0.name == name.lowercased() }) else { return nil }
        return body(at: h.head, in: sql)
    }

    static func codeOnly(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: false).map { stripLineComment($0) }.joined(separator: "\n")
    }

    static func count(_ needle: String, _ hay: String) -> Int { hay.components(separatedBy: needle).count - 1 }

    /// 마지막 정의가 있는 파일과 본문(이름 → (파일, 본문)). 체인을 **한 번만** 읽고 훑는다 — 시험마다 다시 파싱하면
    /// 병렬 실행에서 CPU 를 오래 잡아 시간 민감한 남의 시험(전역 큐 2초 대기)을 굶긴다(실측: 드레인 시험 2/2 빨강).
    static func lastDefinitions() throws -> [String: (file: String, body: String)] { try lastDefinitionsCache.get() }

    private static let lastDefinitionsCache: Result<[String: (file: String, body: String)], XpError> = {
        do {
            var located: [String: (file: String, sql: String, head: String.Index)] = [:]
            for (name, url) in try mergedChain() {
                let sql = try read(url)
                for h in definitionHeads(sql) { located[h.name] = (name, sql, h.head) }
            }
            var out: [String: (file: String, body: String)] = [:]
            for (fn, w) in located {
                if let b = body(at: w.head, in: w.sql) { out[fn] = (w.file, b) }
            }
            return .success(out)
        } catch let e as XpError {
            return .failure(e)
        } catch {
            return .failure(XpError("\(error)"))
        }
    }()
}

@Suite("xplat 서버 초안 M1~M5 — 체인 기준 계약(이번 체인에 들어온 단계만)", .enabled(if: Xp.chainEnabled, "CHECK_XPLAT_STAGING 이 없고 기본 체인에 초안이 없으면 건너뛴다"))
struct XplatServerChainTests {
    @Test("들어온 초안 — 이름 모양 · 기본 체인 뒤 타임스탬프 · 버전 중복 0 · 최상위 트랜잭션 제어 0 · 달러 태그 짝")
    func 초안_모양() throws {
        // 없으면: 타임스탬프가 체인 마지막보다 작은 초안이 운영 CLI 에서 순서가 틀어지거나, 파일 안 begin/commit 이 원자 적용을 깬다.
        let base = try Xp.sqlFiles(try Xp.baseMigrations())
        let lastBase = try #require(base.last)
        var versions = Set(base.compactMap { $0.split(separator: "_").first.map(String.init) })
        #expect(!Xp.stages.isEmpty, "체인 묶음이 켜졌는데 들어온 초안이 0개다")
        for m in Xp.stages {
            let (name, url) = try Xp.draft(m)
            #expect(name.range(of: #"^[0-9]{14}_[a-z0-9_]+\.sql$"#, options: .regularExpression) != nil, "\(name): 운영 CLI 이름 모양이 아니다")
            #expect(name > lastBase || base.contains(name), "\(name) 이 기본 체인 마지막(\(lastBase))보다 앞이다")
            let v = String(name.prefix(14))
            if !base.contains(name) { #expect(versions.insert(v).inserted, "\(name): 버전 \(v) 중복") }
            let raw = try Xp.read(url)
            for line in raw.split(separator: "\n") {
                let t = Xp.stripLineComment(line).trimmingCharacters(in: .whitespaces).lowercased()
                #expect(!["begin;", "commit;", "rollback;", "begin transaction;"].contains(t), "\(name): 최상위 트랜잭션 제어 '\(t)'")
                // 달러 인용 안 주석 함정: 주석에 태그 글자를 쓰면 그 자리에서 본문이 끝난다.
                if let r = line.range(of: "--") {
                    let comment = line[r.upperBound...]
                    #expect(comment.range(of: #"\$[a-z_]*\$"#, options: .regularExpression) == nil, "\(name): 주석 속 달러 태그 — \(line)")
                }
            }
            let tagRegex = try NSRegularExpression(pattern: #"\$[a-z_]*\$"#)
            let tags = tagRegex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).compactMap {
                Range($0.range, in: raw).map { String(raw[$0]) }
            }
            for tag in Set(tags) where tag != "$$" {
                #expect(tags.filter { $0 == tag }.count % 2 == 0, "\(name): \(tag) 가 홀수 번 — 인용이 안 닫혔다")
            }
        }
    }

    @Test("마지막 정의 = 초안(들어온 단계마다) — register_device·capable 4종·발송 3함수·토큰 3함수 등을 옛 파일 재정의가 되돌리지 못한다")
    func 마지막_정의() throws {
        // 없으면: 20260917130000(client_devices) · 20260917150000(gomoku capable) 같은 옛 파일이 초안 뒤에 다시 들어와도 초록이다
        //         (그 파일의 프로브는 android 를 invalid 로 **기대**한다 — B§8).
        let last = try Xp.lastDefinitions()
        let expect: [String: [String]] = [
            "M1": ["register_device", "register_device_fcm", "client_release", "client_publish_release", "client_publish_release_v2"],
            "M2": ["gomoku_capable", "gomoku_chat_capable", "chess_capable", "tetris_capable", "achievements__eval", "achievement_defs",
                   "gomoku_device_min_build", "gomoku_chat_device_min_build", "chess_device_min_build", "tetris_device_min_build"],
            "M3": ["phone_work__poke_unreachable", "ultra_wallet_touch", "phone_work__session_json", "app_current_notice",
                   "app_current_notice_for", "desktop_device_platform", "windows_device_build", "ultra_windows_floor_build"],
            "M4": ["push__enqueue", "push_outbox_claim", "push_outbox_complete", "push__at_desktop", "push_windows_surface_min_build"],
            "M5": ["token_usage_board", "codex_account_group", "token_scan_health", "token_device_fork_safe"],
        ]
        for m in Xp.order {
            let fns = try #require(expect[m])
            if Xp.has(m) {
                let file = try Xp.draftName(m)
                for fn in fns {
                    #expect(last[fn]?.file == file, "\(fn) 의 마지막 정의가 \(last[fn]?.file ?? "없음") 이다(기대 \(file))")
                }
            } else {
                // 아직 안 들어온 단계: 그 단계가 처음 만드는 함수가 체인에 먼저 나타나면 안 된다(초안 일부만 손으로 옮긴 사고).
                let fresh = ["register_device_fcm", "client_publish_release_v2", "gomoku_device_min_build", "app_current_notice_for",
                             "push__at_desktop", "push_windows_surface_min_build", "token_device_fork_safe"]
                for fn in fns where fresh.contains(fn) {
                    #expect(last[fn] == nil, "\(m) 가 안 들어왔는데 \(fn) 이 \(last[fn]?.file ?? "") 에 정의돼 있다")
                }
            }
        }
    }

    @Test("capable 4종(M2) — 본문에 'ios' 0 · 플랫폼 분기 호출 1 · 공통 A(M1~M3 뒤): 'ios' 를 품은 함수는 'android' 도 품는다(파일 기준)")
    func ios_만_아는_함수_없음() throws {
        // 없으면: 누가 capable 을 ios 판으로 되돌리거나, 새 함수가 'ios' 만 말해 Android·Windows 갈래가 조용히 빠져도 초록이다.
        let last = try Xp.lastDefinitions()
        try #require(Xp.has("M2") && Xp.has("M3"), "서버 ① 은 M1~M3 을 함께 옮긴다 — 이번 체인 \(Xp.stages)")
        for fn in ["gomoku_capable", "gomoku_chat_capable", "chess_capable", "tetris_capable"] {
            let body = Xp.codeOnly(try #require(last[fn]?.body, "\(fn) 본문 없음"))
            #expect(Xp.count("'ios'", body) == 0, "\(fn) 에 'ios' 가 남았다")
            #expect(Xp.count("_device_min_build(d.platform)", body) == 1, "\(fn) 의 플랫폼 분기 호출이 1회가 아니다")
        }
        let iosOnly = last.filter { $0.value.body.contains("'ios'") && !$0.value.body.contains("'android'") }.keys.sorted()
        #expect(iosOnly.isEmpty, "ios 만 아는 함수(마지막 정의 기준): \(iosOnly)")
    }

    @Test("FCM 등록(M1) · 출처 windows(M3) · 발송(M4: lower 금지 · push__at_desktop · provider · FCM 비우기 줄 lower 0) 계약")
    func 발송_계약() throws {
        // 없으면: FCM 토큰을 소문자로 저장·비교해(push_pipeline 의 APNs 함정) Android 알림이 영구히 안 가거나, 억제가 옛 맥 판정으로 돌아가도 초록이다.
        let last = try Xp.lastDefinitions()
        try #require(Xp.has("M1") && Xp.has("M3"), "서버 ① 은 M1~M3 을 함께 옮긴다 — 이번 체인 \(Xp.stages)")
        let fcm = Xp.codeOnly(try #require(last["register_device_fcm"]?.body))
        #expect(!fcm.contains("lower("))
        #expect(!fcm.contains("profiles"))
        #expect(fcm.contains("btrim("))
        #expect(fcm.contains("'android'"))
        #expect(!(try #require(last["register_device"]?.body)).contains("profiles"), "register_device 는 profiles 글자 0(client_devices.sql:12-13)")
        #expect(Xp.codeOnly(try #require(last["phone_work__session_json"]?.body)).contains("then 'windows'"), "§8-1 origin 'windows'")
        let enqueue = Xp.codeOnly(try #require(last["push__enqueue"]?.body))
        let claim = Xp.codeOnly(try #require(last["push_outbox_claim"]?.body))
        let complete = Xp.codeOnly(try #require(last["push_outbox_complete"]?.body))
        let fcmLines = complete.split(separator: "\n").filter { $0.contains("fcm_token") || $0.contains("btrim(t, E") }
        if Xp.has("M4") {
            #expect(enqueue.contains("d.fcm_token is not null"))
            #expect(enqueue.contains("public.push__at_desktop(p_user, p_kind)"))
            #expect(!enqueue.contains("push__at_mac("))
            #expect(enqueue.contains("(p_kind in ('message', 'gomoku_invite') or p_kind = 'chess_invite')"), "억제 목록 글자열(push_pipeline §6)")
            #expect(claim.contains("'provider'") && claim.contains("d.user_id = c.user_id") && claim.contains("d.user_id = o.user_id"))
            #expect(!fcmLines.isEmpty && fcmLines.allSatisfy { !$0.contains("lower(") }, "FCM 비우기 줄에 lower(: \(fcmLines)")
            let desktop = Xp.codeOnly(try #require(last["push__at_desktop"]?.body))
            #expect(desktop.contains("<> all") && desktop.contains("can_show"), "못 띄우는 Windows 입력을 빼는 귀속 규칙(B-9.8)")
        } else {
            // M4 전(서버 ① 뒤): 발송 경로는 옛 APNs 판 그대로여야 한다 — FCM 기기를 고르는 발송이 M4 없이 생기면(공급자 판정 없는
            // 옛 Edge 가 provider 없는 FCM 토큰을 APNs 로 보낸다) 안 된다. M1 이 fcm_token 칸을 더해도 발송 함수는 그 칸을 모른다.
            #expect(!enqueue.contains("fcm_token") && !claim.contains("fcm_token") && fcmLines.isEmpty,
                    "M4 전에 발송 함수가 fcm_token 을 안다: enqueue \(enqueue.contains("fcm_token")) · claim \(claim.contains("fcm_token")) · complete \(fcmLines)")
            #expect(enqueue.contains("push__at_mac("), "M4 전 억제는 옛 맥 판정(push__at_mac) 그대로")
        }
    }

    @Test("fork_safe 리터럴(공통 E: M5 뒤 0 · 전에는 M5 대상 세 함수에만) · 새 플랫폼 상수는 도달 불가로 시작 · 울트라 Windows 경제 1")
    func 상수와_fork_safe() throws {
        // 없으면: Windows 빌드를 맥 52 와 비교하는 리터럴이 남거나, 예측 빌드 번호를 박은 상수가 대조 없이 대결을 연다(체스 1.0.5 사고).
        let last = try Xp.lastDefinitions()
        let literal = Set(last.filter { $0.value.body.range(of: #"codex_diag_build\s*,\s*0\s*\)\s*(>=|<)\s*52"#, options: .regularExpression) != nil }.keys)
        if Xp.has("M5") {
            #expect(literal.isEmpty, "fork_safe 리터럴이 남은 함수: \(literal.sorted())")
        } else {
            let m5Targets: Set<String> = ["token_usage_board", "codex_account_group", "token_scan_health"]
            #expect(!literal.isEmpty && literal.isSubset(of: m5Targets), "M5 전 fork_safe 리터럴은 M5 대상 세 함수에만 있어야 한다: \(literal.sorted())")
        }
        let unreachable: [String: [String]] = [
            "M2": ["gomoku_android_min_build", "gomoku_windows_min_build", "gomoku_chat_android_min_build", "gomoku_chat_windows_min_build",
                   "chess_android_min_build", "chess_windows_min_build", "tetris_android_min_build", "tetris_windows_min_build"],
            "M3": ["phone_work_poke_windows_min_build"],
            "M4": ["push_windows_message_min_build"],
            "M5": ["token_windows_fork_safe_build"],
        ]
        for (m, fns) in unreachable.sorted(by: { $0.key < $1.key }) {
            guard Xp.has(m) else {
                for fn in fns { #expect(last[fn] == nil, "\(m) 가 안 들어왔는데 상수 \(fn) 이 있다(\(last[fn]?.file ?? ""))") }
                continue
            }
            let draftFile = try Xp.draftName(m)
            for fn in fns {
                let def = try #require(last[fn], "\(fn) 정의 없음")
                let value = def.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if def.file == draftFile {
                    #expect(value == "select 2147483647", "\(fn) 의 첫 값이 도달 불가가 아니다: \(value)")
                } else {
                    // 서버 ⑤·⑥ 의 한 줄 파일이 내렸다 — 양의 정수여야 한다(V0341 등록은 그 커밋의 swift 패치가 맡는다).
                    #expect(def.file > draftFile && value.range(of: #"^select [1-9][0-9]*$"#, options: .regularExpression) != nil,
                            "\(fn) = \(value) (\(def.file))")
                }
            }
        }
        if Xp.has("M3") {
            #expect(last["ultra_windows_new_economy_build"]?.body.trimmingCharacters(in: .whitespacesAndNewlines) == "select 1")
        }
        if Xp.has("M5") {
            #expect(last["token_mac_fork_safe_build"]?.body.trimmingCharacters(in: .whitespacesAndNewlines) == "select 52")
        }
    }
}

@Suite("xplat 서버 초안 — 스테이징 전용(핀 · 패치 · 되돌림 · payload 두 벌)", .enabled(if: Xp.stagingRequested, "CHECK_XPLAT_STAGING 이 없으면 건너뛴다"))
struct XplatServerStagingTests {
    @Test("정본 md5 19개(B§9-2 18 + tetris) — 초안 사전 단언 핀이 (함수 서명, 정본 md5) 한 쌍으로 canonical-defs/MD5.txt 와 같다")
    func 정본_md5_핀() throws {
        // 없으면: 운영 본문이 그 사이 바뀌었는데 초안이 옛 정본을 가정한 채 create or replace 해 남의 수정을 조용히 되돌린다.
        //         md5 와 함수가 따로따로 초안 어딘가에 있기만 하면 통과하는 판(두 함수의 핀이 서로 뒤바뀐 사고)도 막는다.
        let staging = try Xp.stagingDir()
        let md5Text = try Xp.read(staging.appendingPathComponent("tools/canonical-defs/MD5.txt"))
        var pins: [String: (sig: String, md5: String)] = [:]
        for line in md5Text.split(separator: "\n") {
            let p = line.split(separator: " ")
            if p.count >= 3 { pins[String(p[0])] = (String(p[1]), String(p[2])) }
        }
        #expect(pins.count == 19, "MD5.txt 가 19줄이 아니다: \(pins.count)")
        var drafts = ""
        for m in Xp.order { drafts += try Xp.read(try Xp.draft(m).url) }
        for (fn, pin) in pins.sorted(by: { $0.key < $1.key }) {
            #expect(pin.md5.range(of: #"^[0-9a-f]{32}$"#, options: .regularExpression) != nil, "\(fn): md5 모양 \(pin.md5)")
            #expect(pin.sig.hasPrefix("\(fn)(") && pin.sig.hasSuffix(")"), "\(fn): 서명 \(pin.sig)")
            // 핀 한 줄: ('public.<서명>', '<정본 md5>', '<새 md5>') — 서명과 정본 md5 가 같은 튜플에 있어야 한다.
            let pattern = #"\('public\."# + NSRegularExpression.escapedPattern(for: pin.sig) + #"',\s*'"# + pin.md5 + #"',\s*'[0-9a-f]{32}'\)"#
            let hits = try NSRegularExpression(pattern: pattern).numberOfMatches(in: drafts, range: NSRange(drafts.startIndex..., in: drafts))
            #expect(hits == 1, "('public.\(pin.sig)', '\(pin.md5)', …) 핀 튜플이 초안에 \(hits)개다(기대 1)")
        }
        #expect(pins["tetris_capable"]?.md5 == "4316e54d6ed2f51f15e5376bb23d9150", "tetris 정본은 20261022120000:199 의 운영 값과 같아야 한다")
    }

    @Test("V0341 등록 패치 — M2 가 정의하는 gomoku 접두 함수마다 '<파일>:<함수>' 키가 있다 · 되돌림 초안 5개")
    func 패치와_되돌림() throws {
        // 없으면: M2 를 migrations 로 옮기는 커밋에서 V0341 이 빨개져 맥 출시가 막히거나(M-4), 되돌림 초안이 빠진 채 서버 ① 에 간다.
        let staging = try Xp.stagingDir()
        let (m2, m2URL) = try Xp.draft("M2")
        let sql = try Xp.read(m2URL)
        let gomoku = Xp.definedFunctions(Xp.codeOnly(sql)).filter { $0.hasPrefix("gomoku") }
        #expect(gomoku.count == 8, "M2 의 gomoku 접두 함수가 \(gomoku.count)개다(기대 8): \(gomoku)")
        let patches = try FileManager.default.contentsOfDirectory(atPath: staging.appendingPathComponent("swift-patches").path)
            .filter { $0.hasSuffix(".patch") }
        let v0341 = try #require(patches.first { $0.contains("V0341") }, "swift-patches 에 V0341 패치가 없다")
        let patch = try Xp.read(staging.appendingPathComponent("swift-patches/\(v0341)"))
        for fn in gomoku { #expect(patch.contains("\"\(m2):\(fn)\""), "V0341 패치에 \(m2):\(fn) 등록이 없다") }
        let reverts = try FileManager.default.contentsOfDirectory(atPath: staging.appendingPathComponent("revert").path).filter { $0.hasSuffix(".sql") }
        for m in Xp.order {
            let r = reverts.filter { $0.hasPrefix("revert-\(m)-") }
            #expect(r.count == 1, "\(m) 되돌림 초안이 \(r.count)개")
            if let f = r.first {
                #expect(f.range(of: #"^[0-9]+_"#, options: .regularExpression) == nil, "\(f): migrations 이름 모양이면 실수로 체인에 섞인다")
            }
        }
    }

    @Test("payload 정본 두 벌(저장소 contract/push/payloads · 스테이징 push-send/fixtures/payloads)이 바이트로 같다")
    func payload_두_벌() throws {
        // 없으면: SQL 트리거를 고쳐 payload 를 다시 떴는데 한쪽만 갱신해 Kotlin 시험과 Deno 번역 골든이 서로 다른 입력을 본다.
        let repo = try Xp.repoRoot().appendingPathComponent("contract/push/payloads")
        let edge = try Xp.stagingDir().appendingPathComponent("push-send/fixtures/payloads")
        for kind in ["message", "gomoku_invite", "chess_invite", "feedback_reply", "work_check"] {
            let a = try Data(contentsOf: repo.appendingPathComponent("\(kind).json"))
            let b = try Data(contentsOf: edge.appendingPathComponent("\(kind).json"))
            #expect(a == b, "\(kind).json 두 벌이 다르다")
        }
    }
}

// MARK: - 스테이징 없이도 도는 시험(§8-9 · M-15 · 문턱 위생)

@Test("CHECK_XPLAT_STAGING 은 비었거나 스테이징 폴더(1 = 기본 경로) · 기본 체인의 초안은 M1 부터 끊김 없다 · 들어왔으면 체인 묶음이 켜져 있다")
func xplat_스테이징_변수와_단계_문턱() throws {
    // 없으면: 변수를 틀리게 줘도(계획 원문의 =1 · 오타 경로) 두 묶음이 조용히 건너뛰어 "통과"로 찍히거나, 서버 ① 커밋에서
    //         0002 를 빠뜨려 체인 묶음이 꺼진 채 초록이거나, M4 만 먼저 옮긴 사고가 지나간다.
    if case .invalid(let message) = Xp.stagingSetting {
        Issue.record(Comment(rawValue: message))
    }
    let base = Xp.baseDraftStages
    #expect(base == Array(Xp.order.prefix(base.count)), "기본 체인의 초안 단계가 M1 부터 이어지지 않는다: \(base)")
    if !base.isEmpty {
        #expect(Xp.chainEnabled, "기본 체인에 초안 \(base) 이 들어왔는데 체인 묶음이 꺼져 있다 — swift-patches/0002 를 같은 커밋에 적용하라")
    }
}

@Test("저장소 꼭대기에 backups/ 가 없다 · payload 정본 5종은 kind 와 type 이 같고 비밀 모양 글자가 0")
func xplat_저장소_위생() throws {
    // 없으면: push-send 백업을 상대경로로 만들어 비공개 서버 코드(testing_keys 포함)가 공개 저장소의 다음 git add 에 실린다.
    let root = try Xp.repoRoot()
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("backups").path), "저장소 꼭대기 backups/ — push-send 백업은 저장소 밖 절대경로로(공개 저장소로 샌다)")
    let dir = root.appendingPathComponent("contract/push/payloads")
    let jsons = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
    #expect(jsons == ["chess_invite.json", "feedback_reply.json", "gomoku_invite.json", "message.json", "work_check.json"])
    for f in jsons {
        let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(obj["type"] as? String == String(f.dropLast(5)), "\(f): type 이 kind 와 다르다")
        let aps = try #require(obj["aps"] as? [String: Any])
        let alert = try #require(aps["alert"] as? [String: Any])
        #expect(alert["title"] is String && alert["body"] is String)
        #expect((obj["_apns"] as? [String: Any])?["expiration"] is NSNumber)
        // 비밀 모양 — 패턴 글자 자체가 커밋 전 비밀 검사(같은 정규식)에 걸리지 않게 조각으로 잇는다.
        let secretShapes = ["ey" + #"J[A-Za-z0-9_-]{20,}"#, "service" + "_role", "sk" + "-ant-", #"BEGIN [A-Z ]*PRIV"# + "ATE KEY", #"\.supa"# + #"base\.co"#]
        for bad in secretShapes {
            #expect(text.range(of: bad, options: .regularExpression) == nil, "\(f) 에 비밀 모양 '\(bad)'")
        }
    }
}
