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
