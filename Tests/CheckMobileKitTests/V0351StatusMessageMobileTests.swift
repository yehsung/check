@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// v0.3.51 — 상태메시지(폰). 사장님 결정: 40자(코드포인트) · 한 줄 · 만료 없음 · 비우면 지움 · 쿨타임 없음.
//
//  ① 나 > 프로필: 41자는 요청 없이 안내 · 정규화한 값을 `{"p_text": …}` 로 · 지우기는 null · 서버 거절·준비 중·오프라인 문구 ·
//     성공하면 서버가 저장한 값으로 미러/입력 · 저장 뒤 도착한 옛 GET 은 방금 쓴 값을 되돌리지 않는다 · 로그아웃 리셋.
//  ② 메시지 판: 상태는 사람 목록 둘에서만 오고(뒤 목록이 이긴다 · 방금 지운 상태가 남지 않는다) · 나는 빠지고 · 차단한 사람은 걷힌다.
//  ③ 지금 탭: 우리 팀원(팀 상태 조회는 상태를 싣지 않는다)도 다른 팀도 사람 목록에서 상태를 받는다.
// 상태 문장은 전부 합성 문자열이다.

@MainActor
@Suite(.serialized) struct V0351MeStatusMessageTests {
    nonisolated private static let statusPath = "/rest/v1/profiles"

    nonisolated private static func isStatusGET(_ request: MobileStubRequest) -> Bool {
        request.path == statusPath && request.method == "GET" && request.query.contains("select=status_message")
    }

    @Test("41자는 요청 없이 안내 · 정규화해 보내고 서버 값으로 맞춘다 · 지우기는 null · 거절·준비 중·오프라인은 이유를 말한다")
    func saveFlow() async throws {
        let harness = await RankMeHarness(label: "me-status") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me

        store.statusMessageDraft = String(repeating: "가", count: 41)
        #expect(store.statusMessageDraftLength == 41)
        #expect(!store.canSaveStatusMessage)
        #expect(await store.saveStatusMessage() == false)
        #expect(store.statusMessageNotice == StatusMessageText.tooLong(40) && store.isStatusMessageNoticeError)
        #expect(harness.requests(rpc: "set_status_message").isEmpty, "41자를 서버로 보냈다")

        harness.enqueue("set_status_message", .json(#"{"status":"ok","status_message":"점심 먹고 올게요"}"#))
        store.statusMessageDraft = "  점심 \n먹고 올게요 "
        #expect(store.canSaveStatusMessage)
        #expect(await store.saveStatusMessage())
        let sent = try #require(harness.requests(rpc: "set_status_message").last)
        #expect(sent.jsonBody["p_text"] as? String == "점심 먹고 올게요", "정규화하지 않은 원문을 보냈다: \(sent.bodyText)")
        #expect(store.statusMessage == "점심 먹고 올게요")
        #expect(store.statusMessageDraft == "점심 먹고 올게요")
        #expect(store.statusMessageNotice == StatusMessageText.saved && !store.isStatusMessageNoticeError)
        #expect(!store.canSaveStatusMessage, "같은 값인데 [저장]이 살아 있다")
        #expect(store.canClearStatusMessage)

        harness.enqueue("set_status_message", .json(#"{"status":"not_text","max_length":40}"#))
        store.statusMessageDraft = "abc\u{202E}def"
        #expect(await store.saveStatusMessage() == false)
        #expect(store.statusMessageNotice == StatusMessageText.notText && store.isStatusMessageNoticeError)
        #expect(store.statusMessage == "점심 먹고 올게요", "거절이 미러를 바꿨다")

        harness.enqueue("set_status_message", .json(#"{"status":"cleared","status_message":null}"#))
        #expect(await store.clearStatusMessage())
        let cleared = try #require(harness.requests(rpc: "set_status_message").last)
        #expect(cleared.bodyText == #"{"p_text":null}"#, "지우기가 p_text 키를 빼고 보냈다: \(cleared.bodyText)")
        #expect(store.statusMessage == nil && store.statusMessageDraft.isEmpty)
        #expect(store.statusMessageNotice == StatusMessageText.cleared)
        #expect(!store.canClearStatusMessage)

        // 응답을 안 걸면 기본 404 PGRST202(옛 서버) → "준비 중".
        store.statusMessageDraft = "준비 전"
        #expect(await store.saveStatusMessage() == false)
        #expect(store.statusMessageNotice == StatusMessageText.serverNotReady)

        harness.enqueue("set_status_message", MobileStubResponse(status: 200, body: Data(), failure: .notConnectedToInternet))
        #expect(await store.saveStatusMessage() == false)
        #expect(store.statusMessageNotice == StatusMessageText.network && store.isStatusMessageNoticeError)
        #expect(store.isUpdatingStatusMessage == false)
        harness.expectNoForbiddenCalls()
    }

    @Test("내 값은 따로 GET · 편집 화면을 열면 입력을 채운다 · 저장 뒤 도착한 옛 GET 은 방금 쓴 값을 덮지 않는다")
    func loadAndRace() async throws {
        let harness = await RankMeHarness(label: "me-status-load") { request in
            guard Self.isStatusGET(request) else { return nil }
            return MobileStubResponse(status: 200, body: Data(#"[{"status_message":"옛 상태"}]"#.utf8), delay: 0.4)
        }
        defer { harness.tearDown() }
        let store = harness.me

        // 느린 GET 이 떠 있는 사이 저장이 성공한다.
        let load = Task { await store.loadStatusMessage() }
        _ = await baseWaitUntil { harness.requests.contains(where: Self.isStatusGET) }
        harness.enqueue("set_status_message", .json(#"{"status":"ok","status_message":"새 상태"}"#))
        store.statusMessageDraft = "새 상태"
        #expect(await store.saveStatusMessage())
        await load.value
        #expect(store.statusMessage == "새 상태", "저장 뒤 도착한 옛 GET 이 방금 쓴 값을 되돌렸다")

        // 다시 읽으면(쓰기 표가 그대로) 서버 값이 들어온다 — 그 GET 은 select 한 칸만 묻는다.
        await store.loadStatusMessage()
        #expect(store.statusMessage == "옛 상태")
        #expect(store.statusMessageLoaded)
        let get = try #require(harness.requests.last(where: Self.isStatusGET))
        #expect(get.queryValue("select") == "status_message", "select 에 다른 칸이 섞였다 — 옛 서버에서 42703 으로 같이 죽는다")

        // 편집 화면을 열면 받아 둔 값으로 입력을 채우고, 닫으면 비운다.
        store.statusMessageDraft = ""
        store.profileDidAppear()
        #expect(store.statusMessageDraft == "옛 상태")
        store.profileDidDisappear()
        #expect(store.statusMessageDraft.isEmpty)
        await harness.quiesceMe()
    }

    @Test("칸이 없는 옛 서버의 GET 실패는 '없음'으로 적지 않는다 · 리셋은 미러를 비운다")
    func oldServerAndReset() async throws {
        let harness = await RankMeHarness(label: "me-status-old") { request in
            guard Self.isStatusGET(request) else { return nil }
            return MobileStubResponse(status: 400, body: Data(#"{"code":"42703","message":"column profiles.status_message does not exist"}"#.utf8))
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadStatusMessage()
        #expect(store.statusMessageLoaded == false)
        #expect(store.statusMessage == nil)

        harness.enqueue("set_status_message", .json(#"{"status":"ok","status_message":"앞 사람"}"#))
        store.statusMessageDraft = "앞 사람"
        #expect(await store.saveStatusMessage())
        store.reset()
        #expect(store.statusMessage == nil && !store.statusMessageLoaded)
        #expect(store.statusMessageDraft.isEmpty && store.statusMessageNotice == nil)
        #expect(!store.isUpdatingStatusMessage)
    }
}

// MARK: - ② 메시지 판

@Suite struct V0351PresenceStatusTests {
    private func row(_ id: String, status: String?) -> PokeDirectoryRow {
        PokeDirectoryRow(userId: id, displayName: id, avatarUrl: nil, isWorking: true, statusMessage: status)
    }

    private func entry(_ id: String, status: String?) -> PokeDirectoryEntry {
        PokeDirectoryEntry(userID: id, name: id, avatarURL: nil, isWorking: false, statusMessage: status)
    }

    @Test("상태는 사람 목록 둘에서만 · 뒤(지금 탭 목록)가 이긴다 · 뒤 목록에서 지운 상태는 남지 않는다 · 나는 빠진다")
    func statusesMerge() {
        let statuses = MessagesPresenceRules.statuses(
            nowDirectory: [row("a", status: "새 값"), row("b", status: nil), row("me", status: "내 상태"), row("d", status: "\u{3164}")],
            messagesDirectory: [entry("a", status: "옛 값"), entry("b", status: "지운 상태"), entry("c", status: "시트에만")],
            me: "me"
        )
        #expect(statuses == ["a": "새 값", "c": "시트에만"])
    }

    @Test("판은 상태를 근무 판정 경로와 무관하게 싣는다 — 팀원·지금 근무 중으로 다시 만들어져도 잃지 않는다")
    func boardCarriesStatusesThroughEveryRebuild() {
        let board = MessagesPresenceRules.board(
            nowWorking: [.init(id: "teammate", name: "민트", avatarURL: nil, center: nil, isStale: false)],
            teamMemberIDs: ["teammate", "idle"],
            nowDirectory: [row("teammate", status: "회의 중"), row("idle", status: "휴가 중"), row("other", status: "재택")],
            messagesDirectory: nil,
            me: "me"
        )
        #expect(board.statuses["teammate"] == "회의 중")
        #expect(board.statuses["idle"] == "휴가 중")
        #expect(board.statuses["other"] == "재택")
        #expect(MessagesPresenceRules.board(nowWorking: [], teamMemberIDs: [], nowDirectory: nil, messagesDirectory: nil, me: "me").statuses.isEmpty)
    }
}

// MARK: - ③ 지금 탭

@MainActor
@Suite(.serialized) struct V0351NowStatusTests {
    @Test("지금 근무 중: 우리 팀원도 다른 팀도 사람 목록에서 상태를 받는다 · 보이는 글자 없는 상태는 줄을 안 만든다")
    func workingPeopleCarryStatus() async throws {
        let h = NowHarness()
        defer { BaseStub.tearDown(host: h.host, storage: h.storage) }
        h.server.override("rpc.app_user_directory", .json(#"""
        [{"user_id":"u-mint","display_name":"민트","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul","status_message":"3시까지 집중 🎧"},
         {"user_id":"u-lime","display_name":"라임","avatar_url":null,"is_working":true,"message_capable":true,"center":null,"status_message":"ㅤ"},
         {"user_id":"u-bori","display_name":"보리","avatar_url":null,"is_working":true,"message_capable":true,"center":"busan","status_message":null},
         {"user_id":"u-coral","display_name":"코랄","avatar_url":null,"is_working":true,"message_capable":true,"center":"busan","status_message":"오늘은 재택"},
         {"user_id":"u-morae","display_name":"모래","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"}]
        """#))
        await h.launch()
        await h.activate()
        let people = h.store.workingPeople(now: h.clock.now)
        let byID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        #expect(byID[NowStubServer.mint]?.isTeammate == true)
        #expect(byID[NowStubServer.mint]?.statusMessage == "3시까지 집중 🎧", "팀원의 상태가 사람 목록에서 안 왔다")
        #expect(byID[NowStubServer.lime]?.statusMessage == nil, "보이는 글자 없는 상태가 줄로 그려진다")
        #expect(byID[NowStubServer.bori]?.statusMessage == nil)
        #expect(byID[NowStubServer.coral]?.isTeammate == false)
        #expect(byID[NowStubServer.coral]?.statusMessage == "오늘은 재택")
        #expect(byID[NowStubServer.morae]?.statusMessage == nil, "칸이 없는 옛 서버 행이 깨졌다")
        // 상태 때문에 새 요청이 생기지 않는다(목록 하나로 온다 — 팀 상태 조회의 select 도 그대로).
        #expect(!h.requests.contains { $0.query.contains("status_message") }, "상태를 따로 묻거나 기존 select 에 끼웠다")
    }
}

// MARK: - ④ 화면(소스 계약)
//
// 폰 뷰는 `#if os(iOS)` 라 맥 `swift test` 가 컴파일조차 안 하고, build-sim 은 줄을 지워도 성공한다 — 위 스토어·판 테스트가 값을
// 실어 날라도 그 값을 **그리는 줄**이 사라지면 아무것도 안 빨개진다(검토 지적, v0.3.51). 그래서 그리는 자리를 글자로 되묻는다.
// 사양이 정한 자리: 새 대화 시트 사람 줄 · 대화 이름표 · 지금 탭 사람 줄(두 크기 갈래 모두) · 나 > 프로필 편집 카드. 대화 목록 줄에는 안 넣는다.
// 주석은 걷어낸 코드만 본다(`IntegrationContractTests.code`) — 설명에 남은 이름으로 초록이 되지 않게.

@MainActor
@Suite struct V0351StatusMessageViewContractTests {
    /// `marker` 가 처음 나오는 자리부터 그 뒤 첫 `{` 의 짝 `}` 까지. 못 찾으면 nil.
    static func block(_ code: String, after marker: String) -> String? {
        guard let start = code.range(of: marker),
              let open = code[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < code.endIndex {
            switch code[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(code[start.lowerBound...index]) }
            default: break
            }
            index = code.index(after: index)
        }
        return nil
    }

    @Test("지금 탭 사람 줄: 접근성 크기 갈래와 보통 갈래 둘 다 상태 줄을 그린다")
    func nowWorkingRowDrawsStatusInBothBranches() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        let row = try #require(Self.block(code, after: "struct NowWorkingRow: View"))
        let body = try #require(Self.block(row, after: "var body: some View"))
        let accessibility = try #require(Self.block(body, after: "if typeSize.isAccessibilitySize"))
        let accessibilityEnd = try #require(body.range(of: accessibility)).upperBound
        let regular = try #require(Self.block(String(body[accessibilityEnd...]), after: "else"))
        #expect(regular.contains("PersonName(") && accessibility.contains("PersonName("), "갈래를 잘못 잘랐다 — 이 단언 자체가 낡았다")
        for (name, branch) in [("접근성 크기", accessibility), ("보통 크기", regular)] {
            #expect(branch.contains("person.statusMessage") && branch.contains("statusText(status"),
                    "\(name) 갈래에서 상태 줄이 사라졌다 — 그 글자 크기의 사용자에게만 상태가 안 보인다")
        }
        let statusText = try #require(Self.block(row, after: "func statusText("))
        #expect(statusText.contains("Text(status)") && statusText.contains(".lineLimit(lineLimit)"))
    }

    @Test("새 대화 시트 사람 줄 · 대화 이름표가 상태를 그리고, 대화 화면이 판의 상태를 이름표에 넘긴다")
    func messagesSurfacesDrawStatus() throws {
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesNewConversationSheet.swift")
        let personRow = try #require(Self.block(sheet, after: "struct MessagesPersonRow: View"))
        let personBody = try #require(Self.block(personRow, after: "var body: some View"))
        #expect(personBody.contains("if let status = person.statusMessage") && personBody.contains("Text(status)"),
                "새 대화 시트 사람 줄에서 상태 줄이 사라졌다")

        let conversation = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift")
        let nameplate = try #require(Self.block(conversation, after: "struct MessagesConversationNameplate: View"))
        let nameplateBody = try #require(Self.block(nameplate, after: "var body: some View"))
        #expect(nameplateBody.contains("if let statusMessage") && nameplateBody.contains("Text(statusMessage)"),
                "대화 이름표에서 상태 줄이 사라졌다")
        let view = try #require(Self.block(conversation, after: "struct MessagesConversationView: View"))
        #expect(view.contains(".statuses[peerID]"), "대화 화면이 판에서 상대의 상태를 꺼내지 않는다 — 이름표는 늘 nil 을 받는다")
        #expect(view.contains("MessagesConversationNameplate(header: header, presence: presence, statusMessage: statusMessage)"),
                "이름표에 상태를 안 넘긴다 — 기본값 nil 로 조용히 빈 줄이 된다")
    }

    @Test("대화 목록 줄에는 상태를 넣지 않는다(사양 — 두 줄 미리보기가 이미 그 자리를 쓴다)")
    func threadRowStaysWithoutStatus() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesTab.swift")
        let threadRow = try #require(Self.block(tab, after: "struct MessagesThreadRow: View"))
        #expect(threadRow.contains("previewLines"), "대화 목록 줄을 잘못 잘랐다 — 이 단언 자체가 낡았다")
        #expect(!threadRow.contains("statusMessage") && !threadRow.contains("statuses["), "대화 목록 줄에 상태가 들어갔다")
    }

    @Test("나 > 프로필: 상태메시지 편집 카드가 본문에 서고 입력 · 카운터 · 저장 · 지우기가 스토어에 닿는다")
    func meProfileHasStatusEditor() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeProfileView.swift")
        let view = try #require(Self.block(code, after: "struct MeProfileView: View"))
        let body = try #require(Self.block(view, after: "var body: some View"))
        #expect(body.contains("statusMessageCard"), "프로필 본문에서 상태메시지 카드가 빠졌다 — 폰에서 상태를 쓸 길이 없다")
        #expect(body.contains("store.profileDidAppear()"), "프로필이 열릴 때 내 상태를 다시 받지 않는다")
        let card = try #require(Self.block(view, after: "var statusMessageCard: some View"))
        for token in ["$store.statusMessageDraft", "store.statusMessageDraftLength", "MeStore.statusMessageMaxLength",
                      "store.statusMessageNotice", "StatusMessageText.save", "StatusMessageText.clear",
                      "action: saveStatus", "action: clearStatus", "store.canSaveStatusMessage"] {
            #expect(card.contains(token), "상태메시지 카드에서 '\(token)' 가 사라졌다")
        }
        #expect(try #require(Self.block(view, after: "func saveStatus()")).contains("store.saveStatusMessage()"))
        #expect(try #require(Self.block(view, after: "func clearStatus()")).contains("store.clearStatusMessage()"))
    }
}
