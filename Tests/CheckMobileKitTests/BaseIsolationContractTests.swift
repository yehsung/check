import Foundation
import Testing

/// 맥 전용 쓰기 격리의 **소스 계약**(컴파일 증거는 iOS 빌드와 strings 검사가 따로 낸다).
/// 주석은 걷어내고 본다 — 설명문에 경로 이름이 들어 있어도 계약이 흔들리지 않게(하우스 규칙).
@Suite struct BaseIsolationContractTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 폰이 부르면 안 되는 서버 경로(SPEC-ios §0-2).
    static let macOnlyPaths = [
        "/rest/v1/rpc/take_pokes", "/rest/v1/rpc/work_tick", "/rest/v1/rpc/close_abandoned_work_sessions",
        "/rest/v1/rpc/ultra_wallet_sync", "/rest/v1/rpc/buy_ultra", "/rest/v1/rpc/poke_user", "/rest/v1/rpc/ultra_poke_user",
        "/rest/v1/work_statuses", "/rest/v1/work_status_devices", "/rest/v1/token_usage_device_monthly",
        "/rest/v1/token_usage_monthly", "/rest/v1/rpc/join_team", "/rest/v1/rpc/create_team", "/rest/v1/rpc/away_sync",
    ]
    static let macOnlyMethods = [
        "func takePokes(", "func workTick(", "func closeAbandonedSessions(", "func syncUltraWallet(", "func buyUltra(",
        "func updateAppVersion(", "func updateFocusMode(", "func startWork(", "func stopWork(", "func heartbeat(",
        "func upsertStatusDevice(", "func reportDeviceInput(", "func reopenSession(", "func upsertTokenUsage(",
        "func sendPoke(", "func sendUltraPoke(",
    ]

    @Test("맥 전용 쓰기는 전부 #if os(macOS) 조각에 있고, 공유 서비스 파일에는 경로·메서드가 한 줄도 없다")
    func macOnlyWritesAreIsolated() throws {
        let macOnlyRaw = try source("Sources/CheckCore/SupabaseWorkServiceMacOnly.swift")
        let macOnly = stripComments(macOnlyRaw)
        let shared = stripComments(try source("Sources/CheckCore/SupabaseWorkService.swift"))
        let code = macOnly.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(code.first == "import Foundation")
        #expect(code.dropFirst().first == "#if os(macOS)", "격리 조각이 #if os(macOS) 로 시작하지 않는다")
        #expect(code.last == "#endif")
        // RPC 는 이름 자체가 쓰기다 — 공유 파일에 경로가 한 번도 없어야 한다. 표(work_statuses 등)는 읽기 GET 이 공유 파일에 남는 것이 맞다
        // (지금 탭이 팀 상태를 읽는다) — 표 쓰기의 부재는 아래 메서드 목록과 폰 스토어 테스트의 금지 호출 대조군이 본다.
        for path in Self.macOnlyPaths where path.hasPrefix("/rest/v1/rpc/") {
            #expect(!shared.contains("\"\(path)\""), "공유 서비스에 \(path) 가 남았다 — iOS 바이너리에 실린다")
            #expect(macOnly.contains("\"\(path)\""), "\(path) 가 격리 조각에 없다(대조군 — 옮긴 곳이 맞는가)")
        }
        for method in Self.macOnlyMethods {
            #expect(macOnly.contains(method), "\(method) 가 격리 조각에 없다")
            #expect(!shared.contains(method), "\(method) 가 공유 서비스에 남았다")
        }
        #expect(macOnly.contains("ProfileAppVersionUpdateRequest"), "app_build PATCH 본문 모델도 격리한다")
        #expect(!stripComments(try source("Sources/CheckCore/SupabaseWorkModels.swift")).contains("struct ProfileAppVersionUpdateRequest"))

        // work_tick 가용성 게이트(타입 · 서비스 프로퍼티 · 진단 문구 "work_tick 사용")도 맥 전용이다 — 폰 Release 바이너리 strings 에
        // work_tick 이 남던 자리(dbase-verify). 프로퍼티는 저장 프로퍼티라 확장으로 못 옮겨 actor 본문 안에서 #if os(macOS) 로 가린다.
        #expect(macOnly.contains("package final class WorkTickGate"), "게이트 타입이 격리 조각에 없다")
        #expect(!shared.contains("class WorkTickGate"), "게이트 타입이 공유 서비스에 남았다")
        #expect(!shared.contains("\"work_tick"), "공유 서비스 코드에 work_tick 문자열이 남았다")
        let property = try #require(shared.range(of: "let workTickGate = WorkTickGate()"), "대조: 프로퍼티를 못 찾았다(이름이 바뀌었나)")
        let before = shared[shared.startIndex..<property.lowerBound]
        let lastIf = before.range(of: "#if os(macOS)", options: .backwards)?.lowerBound
        let lastEnd = before.range(of: "#endif", options: .backwards)?.lowerBound
        #expect(lastIf != nil && (lastEnd == nil || lastEnd! < lastIf!), "workTickGate 프로퍼티가 #if os(macOS) 안에 있지 않다")
    }

    @Test("폰 소스(CheckMobileKit · CheckMobileShared · CheckWidgetsKit)는 WorkTimerStore 와 맥 전용 호출을 부르지 않는다")
    func mobileSourcesNeverReferenceMacOnly() throws {
        let banned = ["WorkTimerStore", ".takePokes(", ".workTick(", ".closeAbandonedSessions(", ".syncUltraWallet(", ".buyUltra(",
                      ".updateAppVersion(", ".updateFocusMode(", ".heartbeat(", ".startWork(", ".stopWork(", "applyFetchedTeamStatuses"]
        var scanned = 0
        for folder in ["Sources/CheckMobileKit", "Sources/CheckMobileShared", "Sources/CheckWidgetsKit"] {
            let base = Self.root.appendingPathComponent(folder)
            let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                scanned += 1
                let code = stripComments(try String(contentsOf: url, encoding: .utf8))
                for word in banned {
                    #expect(!code.contains(word), "\(url.lastPathComponent) 가 \(word) 를 참조한다")
                }
            }
        }
        #expect(scanned >= 20, "훑은 파일이 \(scanned)개뿐이다 — 경로가 틀렸다(공허한 초록 방지)")
    }

    @Test("데모·스텁 서버는 #if DEBUG 안에만 있다(Release 에서 컴파일되지 않는다)")
    func demoIsDebugOnly() throws {
        for file in ["Sources/CheckMobileKit/Demo/MobileDemo.swift", "Sources/CheckMobileKit/Demo/MobileStubURLProtocol.swift"] {
            let code = stripComments(try source(file)).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            #expect(code.first == "#if DEBUG", "\(file) 이 #if DEBUG 로 시작하지 않는다")
            #expect(code.last == "#endif")
        }
        let model = stripComments(try source("Sources/CheckMobileKit/App/MobileAppModel.swift"))
        let demoUse = try #require(model.range(of: "MobileDemo.environment("))
        let before = model[model.startIndex..<demoUse.lowerBound]
        #expect(before.components(separatedBy: "#if DEBUG").count > before.components(separatedBy: "#endif").count,
                "앱 모델의 데모 조립 호출이 #if DEBUG 밖에 있다")
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(relative), encoding: .utf8)
    }
}

/// `//` · `/* */` 주석을 걷어낸다(문자열 리터럴 안의 `//` 는 남긴다).
func stripComments(_ source: String) -> String {
    var out = ""
    var inString = false, inLine = false, inBlock = false, escaped = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; i += 1 }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; i += 1
        } else if c == "/", next == "*" {
            inBlock = true; i += 1
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        i += 1
    }
    return out
}
