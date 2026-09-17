import Foundation
import XCTest

// 실서버 e2e 도우미(w5/e2e). **운영 서버의 숨김 심사 계정 두 개만** 쓴다.
//
// - 자격 증명·토큰·anon 키는 저장소에 두지 않는다. `xcodebuild test` 를 부르는 셸이 `TEST_RUNNER_AING_E2E_*` 로 넘기고
//   (xcodebuild 가 접두어를 떼어 테스트 러너 환경에 넣는다), 하나라도 없으면 테스트는 전부 skip 한다.
// - 서버 쓰기는 두 계정의 **사용자 JWT** 로 하는 정상 앱 동작(RPC)뿐이다. service_role·Admin API 는 쓰지 않는다.
// - 로그·첨부에 토큰·비밀번호·이메일을 남기지 않는다(로그인 화면은 스크린샷을 찍지 않는다).

struct E2EEnv {
    let supabaseURL: URL
    let anonKey: String
    let aEmail: String
    let aPassword: String
    let aID: String
    let aName: String
    let aToken: String
    let bEmail: String
    let bPassword: String
    let bID: String
    let bName: String
    let bToken: String
    /// 실행마다 다른 짧은 꼬리표(메시지·할 일 제목을 이 실행 것으로 가려낸다).
    let nonce: String

    static func load() throws -> E2EEnv {
        let env = ProcessInfo.processInfo.environment
        func value(_ key: String) throws -> String {
            guard let v = env["AING_E2E_" + key], !v.isEmpty else {
                throw XCTSkip("AING_E2E_\(key) 가 없어 실서버 e2e 를 건너뛴다(TEST_RUNNER_AING_E2E_* 로 넘긴다)")
            }
            return v
        }
        guard let url = URL(string: try value("SUPABASE_URL")) else { throw XCTSkip("AING_E2E_SUPABASE_URL 형식이 아니다") }
        return E2EEnv(
            supabaseURL: url,
            anonKey: try value("ANON_KEY"),
            aEmail: try value("A_EMAIL"),
            aPassword: try value("A_PASSWORD"),
            aID: try value("A_ID").lowercased(),
            aName: try value("A_NAME"),
            aToken: try value("A_TOKEN"),
            bEmail: try value("B_EMAIL"),
            bPassword: try value("B_PASSWORD"),
            bID: try value("B_ID").lowercased(),
            bName: try value("B_NAME"),
            bToken: try value("B_TOKEN"),
            nonce: env["AING_E2E_NONCE"].flatMap { $0.isEmpty ? nil : $0 } ?? String(UUID().uuidString.prefix(6)).lowercased()
        )
    }
}

enum E2EWho { case a, b }

/// PostgREST 호출(사용자 JWT). 응답은 JSONSerialization 값 그대로.
struct E2EServer {
    let env: E2EEnv

    struct Failure: Error, CustomStringConvertible {
        let status: Int
        let body: String
        var description: String { "HTTP \(status) \(body.prefix(300))" }
    }

    func token(_ who: E2EWho) -> String { who == .a ? env.aToken : env.bToken }

    func rpc(_ fn: String, as who: E2EWho, _ body: [String: Any] = [:]) async throws -> Any {
        try await send("POST", "/rest/v1/rpc/\(fn)", as: who, body: body)
    }

    func get(_ pathAndQuery: String, as who: E2EWho) async throws -> Any {
        try await send("GET", "/rest/v1/\(pathAndQuery)", as: who, body: nil)
    }

    private func send(_ method: String, _ path: String, as who: E2EWho, body: [String: Any]?) async throws -> Any {
        guard let url = URL(string: env.supabaseURL.absoluteString + path) else { throw Failure(status: 0, body: "bad url") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(env.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + token(who), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        if data.isEmpty { return NSNull() }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

extension XCTestCase {
    /// 시각과 함께 한 줄 — xcodebuild 출력에서 `E2E|` 로 골라 본다.
    func log(_ text: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("E2E| \(stamp) \(text)")
    }

    @MainActor
    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        log("shot \(name)")
    }

    @MainActor
    func dumpTree(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "tree-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 조건이 참이 될 때까지 기다린다(비동기 확인 — 서버 조회 등). 걸린 초를 돌려준다(끝내 거짓이면 nil).
    @MainActor
    func eventually(timeout: TimeInterval, poll: TimeInterval = 1, _ check: () async throws -> Bool) async rethrows -> TimeInterval? {
        let start = Date()
        while true {
            if try await check() { return Date().timeIntervalSince(start) }
            if Date().timeIntervalSince(start) > timeout { return nil }
            try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
        }
    }

    /// UI 조건(동기 확인)을 기다린다. 걸린 초 또는 nil.
    @MainActor
    func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.25, _ check: () -> Bool) -> TimeInterval? {
        let start = Date()
        while true {
            if check() { return Date().timeIntervalSince(start) }
            if Date().timeIntervalSince(start) > timeout { return nil }
            RunLoop.current.run(until: Date().addingTimeInterval(poll))
        }
    }
}

@MainActor
enum E2EUI {
    static func anyElement(_ app: XCUIApplication, labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    static func tab(_ app: XCUIApplication, _ title: String) {
        let button = app.tabBars.buttons[title]
        if button.waitForExistence(timeout: 10) {
            // 로그인 직후(키보드가 내려가는 중)에는 탭 막대가 잠깐 누를 수 없는 자리에 있다(hit point {-1,-1}) — 잠깐 기다린다.
            // iOS 27 시뮬레이터의 탭 막대 버튼은 평소에도 isHittable 이 거짓으로 나올 때가 있어(탭은 된다) 오래 기다리지 않는다.
            let deadline = Date().addingTimeInterval(3)
            while !button.isHittable, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            // 눌렸는지(선택됐는지) 확인하고 안 됐으면 다시 누른다(최대 3번).
            for _ in 0..<3 {
                button.tap()
                let selectedBy = Date().addingTimeInterval(2)
                while !button.isSelected, Date() < selectedBy {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                }
                if button.isSelected { break }
            }
        } else {
            // 탭 막대 구현이 바뀌어 tabBars 로 안 잡히는 경우의 대비.
            app.buttons[title].firstMatch.tap()
        }
    }

    /// 로그인 화면이면 로그인한다. 이미 탭 화면이면 아무것도 안 한다. 돌려주는 값: 로그인 폼을 거쳤는가.
    @discardableResult
    static func signInIfNeeded(_ app: XCUIApplication, email: String, password: String, test: XCTestCase) -> Bool {
        let tabBar = app.tabBars.firstMatch
        let loginButton = app.buttons["로그인"]
        _ = test.waitUntil(timeout: 25) { tabBar.exists || loginButton.exists }
        if tabBar.exists { return false }
        XCTAssertTrue(loginButton.exists, "로그인 화면도 탭 화면도 아니다")
        let emailField = app.textFields.firstMatch
        // 저장된 이메일(앞 계정)이 미리 채워져 있을 수 있다 — 커서를 끝에 두고(오른쪽 끝을 누른다) 지운 뒤 적는다.
        let prefilled = (emailField.value as? String).flatMap { $0 == "name@example.com" ? nil : $0 } ?? ""
        emailField.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if !prefilled.isEmpty {
            emailField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: prefilled.count + 4))
        }
        let cleared = (emailField.value as? String).map { $0.isEmpty || $0 == "name@example.com" } ?? true
        test.log("signIn prefilledLength=\(prefilled.count) prefilledIsTarget=\(prefilled == email) clearedBeforeTyping=\(cleared)")
        emailField.typeText(email)
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText(password)
        loginButton.tap()
        if !tabBar.waitForExistence(timeout: 30) {
            let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.contains(email) && !$0.contains(password) }
            test.log("signIn FAILED texts=\(texts)")
            XCTFail("로그인 뒤 탭 화면이 뜨지 않았다")
        }
        return true
    }

    /// 로그인 직후 시스템 "암호를 저장하겠습니까?" 창이 뜨면 "지금 안 함"(시뮬레이터 실측 — 이 창이 알림 설명 시트를 가려
    /// 시트 버튼이 눌리지 않았다). 창은 앱 또는 SpringBoard 쪽에 잡힌다.
    @discardableResult
    static func dismissSavePasswordPrompt(_ app: XCUIApplication, timeout: TimeInterval = 4) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let candidates = ["지금 안 함", "Not Now"].flatMap { [app.buttons[$0], springboard.buttons[$0]] }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let button = candidates.first(where: { $0.exists }) {
                button.tap()
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }

    /// 로그인 직후 알림 설명 시트 → 시스템 권한 창. allow 면 켜고, 아니면 "나중에".
    static func handlePushPrimer(_ app: XCUIApplication, allow: Bool, test: XCTestCase) -> String {
        let passwordPrompt = dismissSavePasswordPrompt(app)
        if passwordPrompt { test.log("save-password prompt dismissed") }
        let title = app.staticTexts["알림을 켜 둘까요?"]
        guard title.waitForExistence(timeout: 8) else { return "primer-not-shown" }
        test.shot("push-primer")
        if !allow {
            app.buttons["나중에"].tap()
            return "primer-later"
        }
        app.buttons["알림 켜기"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "허용"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 6) {
                test.shot("push-system-alert")
                button.tap()
                return "system-alert-\(label)"
            }
        }
        return "system-alert-not-found"
    }
}
