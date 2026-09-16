import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - 별명·팀 이름 칸의 한글 조합 (사용자 신고 2026-09-14)
//
// 신고: "닉네임 변경할때나 팀명 입력할때 마지막 글자 입력 반영 안되는 버그 있어. 한국어 특유의 완성전에
//        반영 안되는 버그 같은데 개선해줘. 지금 메세지 보내기 기능 채팅처럼 하면 될듯"
//
// **v0.3.14 답장 칸(V0314FeedbackReplyIMETests)과 같은 결함이고, 같은 문으로 막는다.** 칸 셋이 모두
// `TextField`(→ `NSTextField`)이고 글자는 창이 빌려주는 필드 에디터가 받는다. 조합 중인 마지막 음절은
// 바인딩에 안 올라온다 — 그 상태로 저장·가입 동작이 값을 읽으면 그 음절이 빠진다.
//
// 칸: 설정 창 별명(`DisplayNameSettingsRow`) · 가입 화면 별명·팀 이름 · 무소속 화면 팀 이름(둘 다 `CredentialField`).
// 수리: 셋 다 `FeedbackReplySend`(CheckFeedbackView.swift)를 지난다 — 칸에 창 표식, 동작 앞에 확정.
// 칸이 서로 다른 창(설정 창 · 팝오버)에 서므로 문이 **자리(Slot)마다** 창을 따로 기억한다(⑥).

// MARK: - 하네스 (이 파일 전용 — nf 접두)

@MainActor
private func nfSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func nfAll(_ view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap { nfAll($0) }
}

/// 필드 에디터는 **창이 key 가 될 수 있을 때만** 선다(V0314 하네스와 같은 이유).
private final class NFKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private let nfUserID = "00000000-0000-0000-0000-000000000002"

@MainActor
private func nfDefaults() -> UserDefaults {
    let suite = "v0321-name-ime-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 실홈을 안 읽는 토큰 스토어 — 팝오버의 `.task` 갱신 루프가 테스트 중 실제 홈을 훑지 않게.
@MainActor
private func nfInertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: nfDefaults(),
        homeDirectory: tmp.appendingPathComponent("check-v0321-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0321-token-cache-\(id).json", isDirectory: false)
    )
}

/// 가입(팀 만들기 모드) 스토어. 네트워크는 `URLProtocolStub` — 가입·팀 생성이 실제로 끝까지 돈다.
@MainActor
private func nfSignUpStore(host: String, displayName: String, teamName: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: nfDefaults(),
        tokenUsage: nfInertTokenStore()
    )
    store.isMenuPresented = true
    store.email = "founder@example.com"
    store.password = "team-password"
    store.displayName = displayName
    store.isCreateTeamMode = true
    store.createTeamName = teamName
    store.createTeamGoalHours = 50
    store.signupCenter = CenterLabel.seoul
    return store
}

/// 제품 화면을 투명한 key 창에 올린다(v0.2.26 규약 — 스위트가 도는 동안 실제 데스크톱에 화면이 뜨지 않게).
@MainActor
private func nfMount<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> (NSWindow, NSView) {
    let hosting = NSHostingView(rootView: view.frame(width: width, height: height))
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NFKeyWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    nfSpin()
    window.alphaValue = 0
    window.makeKeyAndOrderFront(nil)
    nfSpin()
    return (window, hosting)
}

/// 비밀번호가 아닌 편집 칸 가운데 `stringValue` 가 `value` 인 것.
@MainActor
private func nfTextField(in root: NSView, value: String) throws -> NSTextField {
    try #require(
        nfAll(root)
            .compactMap { $0 as? NSTextField }
            .first { $0.isEditable && !($0 is NSSecureTextField) && $0.stringValue == value },
        "값이 \(value.debugDescription) 인 편집 칸이 없다"
    )
}

/// 칸에 **입력기가 부르는 그 문으로** 글을 넣는다: 확정 음절은 `insertText`, 마지막 음절은 `setMarkedText`.
/// 칸에 이미 있던 글자는 통째로 갈아 끼운다(설정 창 별명은 현재 이름으로 채워진 채 열린다).
@MainActor
private func nfCompose(in window: NSWindow, field: NSTextField, typed: String, marked: String) throws -> NSTextView {
    _ = window.makeFirstResponder(field)
    nfSpin()
    let editor = try #require(field.currentEditor() as? NSTextView, "칸에 필드 에디터가 안 섰다 — 조합을 심을 자리가 없다")
    editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
    for character in typed {
        editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        nfSpin(0.01)
    }
    nfSpin()
    if !marked.isEmpty {
        editor.setMarkedText(
            marked,
            selectedRange: NSRange(location: (marked as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        nfSpin()
    }
    return editor
}

/// 조건이 설 때까지 기다린다(V0314 의 `frWait` 와 같은 상한 — 전체 스위트 부하에서 메인 액터 홉이 늦게 온다).
private func nfWait(_ condition: @Sendable () async -> Bool) async {
    for _ in 0..<2000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func nfDidRequest(host: String, path: String) -> Bool {
    URLProtocolStub.requests(forHost: host).contains { $0.url?.path == path }
}

/// 제품 소스를 **주석 없이** 읽는다(설명을 지워야만 초록이 되는 테스트를 만들지 않으려고).
private func nfSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)      // Tests/checkTests/V0321NameFieldIMETests.swift
        .deletingLastPathComponent()                // Tests/checkTests
        .deletingLastPathComponent()                // Tests
        .deletingLastPathComponent()                // (repo root)
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
    return nfStripComments(try String(contentsOf: url, encoding: .utf8))
}

private func nfStripComments(_ source: String) -> String {
    var out = ""
    var inString = false
    var index = source.startIndex
    while index < source.endIndex {
        let character = source[index]
        let next = source.index(after: index)
        if character == "\"" { inString.toggle(); out.append(character); index = next; continue }
        if !inString, character == "/", next < source.endIndex, source[next] == "/" {
            while index < source.endIndex, source[index] != "\n" { index = source.index(after: index) }
            continue
        }
        if !inString, character == "/", next < source.endIndex, source[next] == "*" {
            var cursor = source.index(after: next)
            while cursor < source.endIndex {
                if source[cursor] == "*", source.index(after: cursor) < source.endIndex,
                   source[source.index(after: cursor)] == "/" {
                    cursor = source.index(cursor, offsetBy: 2)
                    break
                }
                cursor = source.index(after: cursor)
            }
            index = cursor
            continue
        }
        out.append(character)
        index = next
    }
    return out
}

/// 이 파일의 테스트끼리는 **직렬**로 돈다 — 같은 자리(`.authForm`)의 창을 두 테스트가 번갈아 적으면
/// 서로의 확정 대상을 덮는다(문은 자리마다 창 하나를 기억한다).
@Suite(.serialized)
@MainActor
struct V0321NameFieldIMETests {

    // MARK: ① 바닥 사실: 가입 화면 팀 이름 칸은 조합 중 한 음절 뒤처진다

    /// 수리를 재지 않는다 — 수리가 상대할 세계를 못 박는다. 칸이 NSTextField 가 아니게 되거나 바인딩이 조합 중
    /// 음절까지 받게 되면 여기서 먼저 빨개져야, 아래 테스트가 "무엇을 재는지 모른 채" 초록으로 남지 않는다.
    @Test func theSignUpTeamNameFieldLagsOneSyllableWhileComposing() throws {
        let store = nfSignUpStore(host: "v0321-ground", displayName: "영식", teamName: "")
        let (window, hosting) = nfMount(CheckMenuView(store: store, initialAuthMode: .signUp), width: 340, height: 720)
        defer { window.orderOut(nil) }
        try #require(FeedbackReplySend.window(for: .authForm) === window, "가입 화면의 칸이 자기 창을 확정 문에 안 알렸다")

        let field = try nfTextField(in: hosting, value: "")
        let editor = try nfCompose(in: window, field: field, typed: "새벽러", marked: "너")

        #expect(editor.isFieldEditor, "글자를 받는 것이 필드 에디터가 아니다 — 조합이 다른 곳에 있다")
        #expect(editor.hasMarkedText(), "이 칸에서는 2벌식 한글이 표시 글자를 안 쓴다 — 전제가 통째로 다르다")
        #expect(field.stringValue == "새벽러너", "필드: \(field.stringValue.debugDescription)")
        #expect(store.createTeamName == "새벽러",
                "바인딩이 조합 중 음절까지 갖고 있다 — 그렇다면 수리도 아래 테스트도 재는 것이 없다: \(store.createTeamName.debugDescription)")
    }

    // MARK: ② 결함: 문을 안 지나면 팀이 마지막 음절 없이 만들어진다 (대조군)

    /// **기준선이 달라야 한다.** 옛 배선(`store.signUp()` 직접 호출)을 그대로 태워 ③과 문 하나만 다른 값을 만든다.
    @Test func withoutTheDoorTheTeamIsCreatedWithoutItsLastSyllable() async throws {
        let host = "v0321-team-nodoor"
        let store = nfSignUpStore(host: host, displayName: "영식", teamName: "")
        let (window, hosting) = nfMount(CheckMenuView(store: store, initialAuthMode: .signUp), width: 340, height: 720)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
            window.orderOut(nil)
        }
        let field = try nfTextField(in: hosting, value: "")
        _ = try nfCompose(in: window, field: field, typed: "새벽러", marked: "너")

        store.signUp()
        await nfWait { nfDidRequest(host: host, path: "/rest/v1/rpc/create_team") }

        let sent = URLProtocolStub.bodyText(forHost: host)
        #expect(nfDidRequest(host: host, path: "/rest/v1/rpc/create_team"), "팀 생성 요청이 안 나갔다")
        #expect(sent.contains("새벽러"), "팀 이름이 아예 안 실렸다: \(sent)")
        #expect(!sent.contains("새벽러너"), "문 없이도 마지막 음절이 실렸다 — 그렇다면 ③이 재는 차이가 없다: \(sent)")
    }

    // MARK: ③ 수리: [팀 만들고 시작하기] 동작이 조합 중이던 음절까지 보낸다

    /// 두 가지를 이어 붙인다(V0314 ③과 같은 구조): 버튼의 동작이 그 문 한 줄이라는 것(SwiftUI Button 은 헤드리스에서
    /// 못 누른다), 그리고 올린 화면 그대로 그 한 줄을 태우면 **서버로 나가는 팀 이름**에 조합 중이던 음절이 실린다는 것.
    @Test func theCreateTeamActionShipsTheComposingTeamNameSyllable() async throws {
        let menu = try nfSource("CheckMenuView.swift")
        try #require(menu.contains("FeedbackReplySend.commitThenSend(slot: .authForm) { store.signUp() }"),
                     "가입 버튼이 확정 문을 안 지난다 — 아래 값 측정이 화면이 안 지나는 길을 재게 된다")

        let host = "v0321-team-door"
        let store = nfSignUpStore(host: host, displayName: "영식", teamName: "")
        let (window, hosting) = nfMount(CheckMenuView(store: store, initialAuthMode: .signUp), width: 340, height: 720)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
            window.orderOut(nil)
        }
        let field = try nfTextField(in: hosting, value: "")
        _ = try nfCompose(in: window, field: field, typed: "새벽러", marked: "너")
        try #require(store.createTeamName == "새벽러", "전제가 안 만들어졌다: \(store.createTeamName.debugDescription)")
        try #require(FeedbackReplySend.window(for: .authForm) === window, "팀 이름 칸이 선 창을 문이 못 찾는다")

        // 버튼이 하는 일 그대로.
        FeedbackReplySend.commitThenSend(slot: .authForm) { store.signUp() }
        // 확정은 동기다 — 가입이 읽기 **전에** 이미 전체 이름이다.
        #expect(store.createTeamName == "새벽러너", "확정이 바인딩을 못 올렸다: \(store.createTeamName.debugDescription)")
        await nfWait { nfDidRequest(host: host, path: "/rest/v1/rpc/create_team") }

        let sent = URLProtocolStub.bodyText(forHost: host)
        #expect(nfDidRequest(host: host, path: "/rest/v1/rpc/create_team"), "팀 생성 요청이 안 나갔다")
        #expect(sent.contains("새벽러너"), "[팀 만들고 시작하기]가 마지막 글자를 잃은 채 팀을 만들었다: \(sent)")
    }

    // MARK: ④ 수리: 가입 화면 별명도 같은 문으로 끝 음절까지 간다

    @Test func theSignUpActionShipsTheComposingDisplayNameSyllable() async throws {
        let host = "v0321-signup-name"
        let store = nfSignUpStore(host: host, displayName: "", teamName: "새벽러너")
        let (window, hosting) = nfMount(CheckMenuView(store: store, initialAuthMode: .signUp), width: 340, height: 720)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
            window.orderOut(nil)
        }
        let field = try nfTextField(in: hosting, value: "")
        _ = try nfCompose(in: window, field: field, typed: "영", marked: "식")
        try #require(store.displayName == "영", "전제가 안 만들어졌다(별명 칸이 아닌 칸을 잡았다?): \(store.displayName.debugDescription)")
        try #require(FeedbackReplySend.window(for: .authForm) === window, "별명 칸이 선 창을 문이 못 찾는다")

        FeedbackReplySend.commitThenSend(slot: .authForm) { store.signUp() }
        await nfWait { nfDidRequest(host: host, path: "/auth/v1/signup") }

        let sent = URLProtocolStub.bodyText(forHost: host)
        #expect(nfDidRequest(host: host, path: "/auth/v1/signup"), "가입 요청이 안 나갔다")
        #expect(sent.contains("영식"), "[팀 만들고 시작하기]가 별명의 마지막 글자를 잃은 채 가입했다: \(sent)")
    }

    // MARK: ⑤ 수리: 설정 창 별명 칸의 조합을 문이 찾아 확정한다

    /// [저장] 버튼이 **실제로 빠지는 갈래**다(아래 ⑤-b 가 Enter 는 원래 안 빠진다는 것을 잰다). SwiftUI Button 은
    /// 헤드리스에서 못 누르고 `save()` 는 `@State` 초안을 읽어 뷰 밖에서 부를 수 없다 — 그래서 V0314 ④ 와 같은 방식으로
    /// 두 가지를 이어 붙인다: `save()` 첫 줄이 이 문이라는 것(⑦ 소스 계약), 그리고 **올린 설정 창에서 이 문이
    /// 별명 칸의 조합을 실제로 찾아 화면에 보이던 그대로 확정한다**는 것(여기서 값으로).
    @Test func theSettingsNicknameCompositionIsCommittedByTheDoor() throws {
        let store = WorkTimerStore(
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: nfDefaults(),
            tokenUsage: nfInertTokenStore()
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: nfUserID)
        store.displayName = "영식"

        let (window, hosting) = nfMount(CheckSettingsView(store: store, launchAtLoginSeed: false), width: 480, height: 760)
        defer { window.orderOut(nil) }
        try #require(FeedbackReplySend.window(for: .settingsDisplayName) === window, "별명 칸이 자기 창을 확정 문에 안 알렸다")
        let field = try nfTextField(in: hosting, value: "영식")
        let editor = try nfCompose(in: window, field: field, typed: "김철", marked: "수")
        try #require(editor.hasMarkedText(), "조합을 못 심었다 — 이 테스트가 재는 것이 없다")

        #expect(FeedbackReplySend.commitActiveComposition(slot: .settingsDisplayName),
                "설정 창 별명 칸에 조합이 있는데 문이 못 찾았다 — [저장]이 마지막 글자 없이 나간다")
        #expect(editor.string == "김철수", "확정이 글자를 버렸다: \(editor.string.debugDescription)")
        #expect(field.stringValue == "김철수", "필드: \(field.stringValue.debugDescription)")
        #expect(!editor.hasMarkedText(), "확정했는데 표시 글자가 남아 있다 — 다음 글자가 이 음절에 다시 붙는다")
        #expect(window.firstResponder === editor, "확정이 포커스를 뺏었다 — 저장 뒤 이어 쓰려면 다시 눌러야 한다")
        #expect(!FeedbackReplySend.commitActiveComposition(slot: .settingsDisplayName), "확정할 것이 없는데 뭔가 했다")
    }

    // MARK: ⑤-b 바닥 사실: Enter 는 원래 끝 음절까지 간다

    /// **수리를 재지 않는다**(문을 빼도 초록이다 — 뮤테이션으로 확인했다). 잰 사실은 이것이다: 필드 에디터는
    /// 줄바꿈을 받으면 조합을 **스스로** 확정한 뒤 편집을 끝내므로, `.onSubmit(save)` 가 읽는 `draft` 에는 이미
    /// 마지막 음절이 있다. 사용자가 겪은 "마지막 글자가 빠진다"는 Enter 가 아니라 **[저장] 버튼**(클릭은 확정을
    /// 안 부른다) 갈래다. 문을 Enter 에도 태우는 것은 무해하다 — 조합이 없으면 문은 아무 일도 안 한다.
    /// 여기가 빨개지면 Enter 도 빠지는 세계가 된 것이니 ⑤와 ⑦의 전제를 다시 봐라.
    @Test func enterInTheSettingsNicknameFieldAlreadyShipsTheLastSyllable() async throws {
        let host = "v0321-settings-enter"
        let path = "/rest/v1/rpc/set_display_name"
        FeedbackURLProtocol.reset(host: host)
        FeedbackURLProtocol.set(.init(status: 200, body: #"{"status":"ok","display_name":"김철수"}"#), host: host, path: path)
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: FeedbackURLProtocol.session()
        )
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: nfDefaults(),
            tokenUsage: nfInertTokenStore()
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: nfUserID)
        store.displayName = "영식"

        let (window, hosting) = nfMount(CheckSettingsView(store: store, launchAtLoginSeed: false), width: 480, height: 760)
        defer { window.orderOut(nil) }
        let field = try nfTextField(in: hosting, value: "영식")
        let editor = try nfCompose(in: window, field: field, typed: "김철", marked: "수")
        try #require(editor.hasMarkedText(), "조합을 못 심었다")

        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await nfWait { FeedbackURLProtocol.count(host: host, path: path) > 0 }

        let sent = FeedbackURLProtocol.sentBodies(host: host, path: path).first ?? ""
        #expect(FeedbackURLProtocol.count(host: host, path: path) == 1, "Enter 가 저장을 안 태웠다")
        #expect(sent.contains("김철수"), "Enter 저장이 마지막 글자를 잃었다 — 필드 에디터가 더는 줄바꿈에서 확정하지 않는다: \(sent)")
    }

    // MARK: ⑥ 자리가 서로의 창을 덮지 않는다

    /// 설정 창(별명)과 팝오버(가입 화면)가 **둘 다 떠 있을 때**, 나중에 선 팝오버의 표식이 설정 창의 표식을
    /// 덮으면 설정 창의 확정이 조용히 no-op 이 된다. 문이 자리마다 창을 따로 기억하는지 값으로 못 박는다.
    @Test func aWindowOfAnotherSlotDoesNotStealTheComposingField() throws {
        let settingsStore = WorkTimerStore(
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: nfDefaults(),
            tokenUsage: nfInertTokenStore()
        )
        settingsStore.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: nfUserID)
        settingsStore.displayName = "영식"
        let (settingsWindow, settingsHosting) = nfMount(
            CheckSettingsView(store: settingsStore, launchAtLoginSeed: false), width: 480, height: 760
        )
        defer { settingsWindow.orderOut(nil) }
        let field = try nfTextField(in: settingsHosting, value: "영식")
        let editor = try nfCompose(in: settingsWindow, field: field, typed: "김철", marked: "수")

        // 나중에 다른 창의 칸이 표식을 붙인다(팝오버의 가입 화면이 서는 순간과 같다).
        // ★ 진짜 가입 화면을 올리지 않는 이유(실측): 그 화면은 뜨자마자 별명 칸에 포커스를 주는데, SwiftUI 의
        //   필드 에디터가 **창을 건너 옮겨 가** 설정 창의 조합이 그 자리에서 끝났다(에디터 글자가 가입 화면
        //   별명 "영식"으로 바뀌었다). 그건 이 테스트가 재려는 "자리 덮어쓰기"와 다른 사건이라, 포커스를 안 뺏는
        //   빈 창을 그 자리에 적는다. 칸이 실제로 표식을 붙이는지는 ①·③·④ 가 이미 값으로 잰다.
        let authWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: true
        )
        authWindow.isReleasedWhenClosed = false
        FeedbackReplySend.register(authWindow, slot: .authForm)
        try #require(FeedbackReplySend.window(for: .authForm) === authWindow, "다른 자리에 창을 못 적었다 — 이 테스트가 재는 것이 없다")

        #expect(FeedbackReplySend.window(for: .settingsDisplayName) === settingsWindow,
                "가입 화면의 표식이 설정 창 자리를 덮었다")
        #expect(!FeedbackReplySend.commitActiveComposition(slot: .authForm),
                "가입 화면 자리의 확정이 설정 창의 조합을 건드렸다")
        #expect(editor.hasMarkedText(), "설정 창의 조합이 남의 자리 확정에 끝났다")
        #expect(FeedbackReplySend.commitActiveComposition(slot: .settingsDisplayName),
                "설정 창 자리의 확정이 자기 조합을 못 찾았다")
        #expect(editor.string == "김철수", "확정이 글자를 버렸다: \(editor.string.debugDescription)")
        #expect(!editor.hasMarkedText(), "확정했는데 표시 글자가 남아 있다")
    }

    // MARK: ⑦ 소스 계약: 이름을 내보내는 모든 갈래가 문을 지난다

    /// 값 측정(②~⑤)은 한 갈래씩만 잰다. 계약이 막는 것은 **확정을 건너뛰는 갈래가 늘어나는 것**이다 —
    /// v0.3.11 의 결함이 정확히 "몇 갈래는 확정을 지나고 한 갈래는 안 지난" 모양이었다.
    @Test func everyNameSubmitTravelsThroughTheDoor() throws {
        let menu = try nfSource("CheckMenuView.swift")
        let door = "FeedbackReplySend.commitThenSend(slot: .authForm) { store.signUp() }"
        let wrapped = menu.components(separatedBy: door).count - 1
        let calls = menu.components(separatedBy: "store.signUp()").count - 1
        #expect(wrapped == 4, "가입·팀 만들기 제출(Enter · 가입 · 팀 만들기 · 무소속 팀 만들기)이 문을 지나는 자리가 \(wrapped)곳이다")
        #expect(calls == wrapped, "문을 안 지나는 store.signUp() 호출이 있다(\(calls - wrapped)곳) — 그 갈래에서 마지막 글자가 빠진다")

        let components = try nfSource("CheckComponents.swift")
        #expect(components.contains(".onSubmit { FeedbackReplySend.commitThenSend(slot: .authForm) { onSubmit?() } }"),
                "CredentialField 의 Enter 가 확정 없이 넘어간다")
        #expect(components.contains(".background(FeedbackReplyWindowAnchor(slot: .authForm)"),
                "CredentialField 가 자기 창을 확정 문에 안 알린다 — 문이 칸을 못 찾아 no-op 이 된다")

        let settings = try nfSource("CheckSettingsView.swift")
        #expect(settings.contains(".background(FeedbackReplyWindowAnchor(slot: .settingsDisplayName)"),
                "설정 창 별명 칸이 자기 창을 확정 문에 안 알린다")
        #expect(settings.contains(".onSubmit(save)") && settings.contains("Button(action: save)"),
                "Enter 와 [저장]이 같은 save 를 안 부른다 — ⑤가 재는 길과 버튼 길이 갈린다")
        let save = try #require(settings.range(of: "private func save() {"), "save() 를 못 찾았다")
        let commit = try #require(
            settings.range(of: "FeedbackReplySend.commitActiveComposition(slot: .settingsDisplayName)", range: save.upperBound..<settings.endIndex),
            "save() 가 조합을 확정하지 않는다"
        )
        let guardLine = try #require(settings.range(of: "guard canSave", range: save.upperBound..<settings.endIndex))
        #expect(commit.lowerBound < guardLine.lowerBound, "save() 가 확정보다 먼저 canSave·draft 를 읽는다 — 순서가 뜻이다")

        // 확정 자체는 여전히 문 안 **한 곳**에만 적혀 있다(V0314 ⑥ 과 같은 규약).
        let feedback = try nfSource("CheckFeedbackView.swift")
        #expect(feedback.components(separatedBy: "editor.unmarkText()").count - 1 == 1,
                "확정을 손으로 부르는 자리가 문 밖에도 있다")
    }
}
