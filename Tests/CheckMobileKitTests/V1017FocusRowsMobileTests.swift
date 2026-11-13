@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.17 — 집중 표시 넓히기(대표 결정 카드 D2). 본판(잠금 · 두 자리 칩 · 내 집중 조회)은 `V1017FocusSendGateMobileTests.swift`.
//
// 대표 답(원문, 2026-11-03 결재함 — 되묻지 말 것):
//   #d_6A32rmcoJZZd "말 걸 수 있는 줄 전부"(두 곳 + 대화 목록 줄·지금 탭 근무 중 줄, 내가 집중 중이면 메시지 탭 위에 한 줄. 반나절 더)
//   #d_ldP912RctnTt "안내만 (단추 없음)"(추가 일 없음. 덮은 맥의 지난 집중은 맥을 다시 켜야 풀림. 제보가 오면 다음 판에 단추)
//
// 이 파일이 재는 것:
//  ① 규칙: 목록 위 한 줄은 켜짐일 때만(문장은 입력줄 · 서버 거절과 같은 글자) · 대화 목록 줄 · 얼굴 띠 보이스오버의 '집중 중'
//     · 차단해 숨긴 사람은 집중 집합에 들지 않는다(판의 근무 점 · 상태메시지와 같은 규칙)
//  ② 스토어: 목록이 설 때 내 집중을 묻고 · 목록이 떠 있는 채 앞으로 오기 · 켜짐일 때 틱이 묻는다 — 목록도 대화도 없으면 묻지 않는다
//     · 맥에서 끄면 목록 위 한 줄이 사라진다 · 지금 탭은 메시지 스토어의 집합을 그대로 읽는다(출처 한 곳) · 차단 거르기
//  ③ 화면 배선 소스 계약(주석 걷기): 대화 목록 줄 · 목록 위 한 줄 · 얼굴 띠 · 지금 탭 근무 중 줄 · 칩 보이스오버 — 폰 뷰는 swift test 가 컴파일하지 않는다
//  ④ 데모: 목록 장면 하린 줄(집중) · 지금 탭 민트 줄(집중 · 우리 팀) · 내 집중 장면(도윤)의 목록 위 한 줄 — 기준선 장면은 줄이 없다

private let frFocused = "peer-focus"
private let frPlain = "peer-plain"

private enum FrFx {
    static func row(_ id: String, name: String, focus: Bool) -> String {
        #"{"user_id":"\#(id)","display_name":"\#(name)","avatar_url":null,"is_working":true,"message_capable":true,"center":null,"status_message":null,"focus_mode":\#(focus)}"#
    }

    static func directory(plainIsFocused: Bool = false) -> String {
        "[" + [row(frFocused, name: "집중이", focus: true), row(frPlain, name: "보통이", focus: plainIsFocused)].joined(separator: ",") + "]"
    }

    static func myFocus(_ value: Bool) -> MobileStubResponse { .json(#"[{"focus_mode":\#(value)}]"#) }
}

@MainActor
private func frFocusGETs(_ h: MessagesHarness) -> Int {
    h.requests.filter { $0.path == "/rest/v1/profiles" && $0.method == "GET" && $0.queryValue("select") == "focus_mode" }.count
}

// MARK: - ① 규칙

@Suite struct V1017FocusRowRuleTests {
    @Test("목록 위 한 줄: 켜짐일 때만 서고 문장은 입력줄 · 서버 거절(sender_focused)과 같은 글자 · 꺼짐/모름은 줄 없음")
    func listNoticeOnlyWhenOn() {
        #expect(MessagesFocusRules.listNotice(myFocus: true) == MessageNoticeText.senderFocused)
        #expect(MessagesFocusRules.listNotice(myFocus: true) == MessagesFocusBlock.myself.notice)
        #expect(MessageNoticeText.senderFocused.contains("맥에서 집중을 끄면"), "폰엔 [집중 끄기] 단추가 없다(#d_ldP912RctnTt) — 문장이 맥을 가리켜야 한다")
        #expect(MessagesFocusRules.listNotice(myFocus: false) == nil)
        #expect(MessagesFocusRules.listNotice(myFocus: nil) == nil, "모름은 막지 않으므로 말하지도 않는다")
    }

    @Test("대화 목록 줄 보이스오버: 집중이면 근무 줄 뒤에 '집중 중' · 아니면 지금과 한 글자도 같다(기준선)")
    func threadRowAccessibility() {
        let thread = MessageThread(peerUserID: "p", peerName: "하린", peerAvatarURL: nil, messages: [])
        let row = MessagesThreadItem(
            thread: thread, pokes: [], lastActivityAt: Date(timeIntervalSince1970: 0), previewText: "하린님이 콕 찔렀어요",
            lastIsMine: false, previewIsPoke: true, timeText: "13:58", isUnread: false, countBadge: nil, group: 0
        )
        let plain = MessagesThreadListRules.accessibilityText(row: row, presenceLine: "근무 중")
        #expect(plain == "하린, 근무 중, 하린님이 콕 찔렀어요, 13:58")
        #expect(MessagesThreadListRules.accessibilityText(row: row, presenceLine: "근무 중", isFocused: false) == plain)
        #expect(MessagesThreadListRules.accessibilityText(row: row, presenceLine: "근무 중", isFocused: true)
                == "하린, 근무 중, 집중 중, 하린님이 콕 찔렀어요, 13:58")
        // 근무 여부를 모르는 창(점 없음)에서도 집중은 말한다 — 출처가 다르다(명부의 focus_mode).
        #expect(MessagesThreadListRules.accessibilityText(row: row, presenceLine: nil, isFocused: true)
                == "하린, 집중 중, 하린님이 콕 찔렀어요, 13:58")
    }

    @Test("얼굴 띠 보이스오버: 근무 중 · 연결 끊김 뒤에 '집중 중' — 칩은 달지 않는다(대표 답: 얼굴 띠는 보이스오버 말만)")
    func workingStripAccessibility() {
        let working = MessagesWorkingPerson(id: "a", name: "하린", avatarURL: nil, status: .working, center: nil)
        let pending = MessagesWorkingPerson(id: "b", name: "민트", avatarURL: nil, status: .pending, center: nil)
        #expect(MessagesPresenceRules.workingAccessibilityText(working, isFocused: false) == "하린, 근무 중", "기준선(지금 문장)이 바뀌었다")
        #expect(MessagesPresenceRules.workingAccessibilityText(pending, isFocused: false) == "민트, 연결 끊김")
        #expect(MessagesPresenceRules.workingAccessibilityText(working, isFocused: true) == "하린, 근무 중, 집중 중")
        #expect(MessagesPresenceRules.workingAccessibilityText(pending, isFocused: true) == "민트, 연결 끊김, 집중 중")
    }

    @Test("집중 집합은 차단해 숨긴 사람을 넣지 않는다 — 두 명부 어느 쪽에서 왔든(기준선: 숨기지 않으면 든다)")
    func hiddenPeersAreNotFocused() {
        var entry = PokeDirectoryEntry(userID: "a", name: "가", avatarURL: nil, isWorking: true)
        entry.isFocused = true
        let row = PokeDirectoryRow(userId: "b", displayName: "나", avatarUrl: nil, isWorking: true, focusMode: true)
        #expect(MessagesFocusRules.focusedPeerIDs(nowDirectory: [row], messagesDirectory: [entry], me: nil) == ["a", "b"])
        #expect(MessagesFocusRules.focusedPeerIDs(nowDirectory: [row], messagesDirectory: [entry], me: nil, hidden: ["a"]) == ["b"])
        #expect(MessagesFocusRules.focusedPeerIDs(nowDirectory: [row], messagesDirectory: [entry], me: nil, hidden: ["a", "b"]).isEmpty)
    }
}

// MARK: - ② 스토어

@MainActor
@Suite(.serialized) struct V1017FocusRowStoreTests {
    @Test("목록이 설 때 내 집중을 묻는다 · 목록이 떠 있는 채 앞으로 오면 묻고 · 켜짐이면 틱도 묻는다 — 목록이 내려가면 다시 묻지 않는다")
    func listAsksMyFocus() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FrFx.directory())
            server.setMyFocus(FrFx.myFocus(true))
        }
        defer { h.tearDown() }
        // 기준선: 메시지 화면이 없으면 앞으로 오기 · 틱 모두 묻지 않는다(나 탭 조회 수 계약 — MeStoreTests 루트).
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(frFocusGETs(h) == 0, "메시지 화면이 없는데 물었다")

        // ①-2 목록이 선다 → 묻는다 → 켜짐 → 목록 위 한 줄.
        h.store.listDidAppear()
        await h.settle()
        #expect(frFocusGETs(h) == 1, "목록이 섰는데 내 집중을 안 물었다 — 목록 위 한 줄이 맥에서 켠 집중을 모른다")
        #expect(h.store.myFocusMode == true)
        #expect(MessagesFocusRules.listNotice(myFocus: h.store.myFocusMode) == MessageNoticeText.senderFocused)

        // ③ 켜짐 + 목록 — 틱이 묻는다. 맥에서 껐다(false) → 한 줄이 사라진다.
        h.server.setMyFocus(FrFx.myFocus(false))
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(frFocusGETs(h) == 2, "켜짐인데 목록에서 틱이 안 물었다 — 맥에서 끈 집중이 목록에 남는다")
        #expect(h.store.myFocusMode == false)
        #expect(MessagesFocusRules.listNotice(myFocus: h.store.myFocusMode) == nil, "맥에서 껐는데 목록 위 한 줄이 남았다")
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(frFocusGETs(h) == 2, "꺼짐인데 틱이 물었다")

        // ② 목록이 떠 있는 채 앞으로 온다 — 맥에서 다시 켰다.
        h.server.setMyFocus(FrFx.myFocus(true))
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(frFocusGETs(h) == 3, "목록이 떠 있는데 앞으로 오기가 안 물었다")
        #expect(h.store.myFocusMode == true)

        // 목록이 내려가면(다른 탭) 켜짐이어도 틱 · 앞으로 오기 모두 묻지 않는다.
        h.store.listDidDisappear()
        h.store.refreshMyFocusModeIfFocused()
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(frFocusGETs(h) == 3, "메시지 화면이 없는데 물었다")
        #expect(!h.requests.contains { $0.path == "/rest/v1/profiles" && $0.method != "GET" }, "폰이 profiles 를 썼다(R9)")
        h.expectNoForbiddenCalls()
    }

    @Test("목록을 당겨 새로고침하면 내 집중을 다시 묻는다 — 맥에서 켠 집중은 한 줄이 서고 끈 집중은 60초 틱을 기다리지 않고 사라진다(검토 지적)")
    func pullToRefreshAsksMyFocus() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FrFx.directory())
            server.setMyFocus(FrFx.myFocus(false))
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        #expect(frFocusGETs(h) == 1)
        #expect(MessagesFocusRules.listNotice(myFocus: h.store.myFocusMode) == nil, "기준선: 꺼짐이면 목록 위 한 줄이 없다")

        // 맥에서 켰다 → 목록에 머문 채 당긴다(틱은 꺼짐이라 돌지 않는다 — 당기기가 유일한 길이다).
        h.server.setMyFocus(FrFx.myFocus(true))
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(frFocusGETs(h) == 1, "기준선: 꺼짐인데 틱이 물었다")
        await h.store.refreshNow()
        await h.settle()
        #expect(frFocusGETs(h) == 2, "당겨도 내 집중을 안 물었다 — 맥에서 켠 집중이 목록 위 한 줄에 안 선다")
        #expect(MessagesFocusRules.listNotice(myFocus: h.store.myFocusMode) == MessageNoticeText.senderFocused)

        // 맥에서 껐다 → 당기면 바로 사라진다.
        h.server.setMyFocus(FrFx.myFocus(false))
        await h.store.refreshNow()
        await h.settle()
        #expect(frFocusGETs(h) == 3)
        #expect(MessagesFocusRules.listNotice(myFocus: h.store.myFocusMode) == nil, "맥에서 끈 집중이 당긴 뒤에도 남았다")
        #expect(!h.requests.contains { $0.path == "/rest/v1/profiles" && $0.method != "GET" }, "폰이 profiles 를 썼다(R9)")
        h.expectNoForbiddenCalls()
    }

    @Test("목록에서 돌아올 때마다 묻되 날아가는 중이면 겹쳐 띄우지 않는다(조회 규칙은 refreshMyFocusMode 그대로)")
    func listAppearDoesNotStackFetches() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FrFx.directory())
            server.setMyFocus(FrFx.myFocus(true))
        }
        defer { h.tearDown() }
        let hold = BaseHold.install(host: h.host) { $0.path == "/rest/v1/profiles" && $0.queryValue("select") == "focus_mode" }
        h.store.listDidAppear()
        #expect(await hold.waitHeld())
        #expect(h.store.isFetchingMyFocusMode)
        h.store.listDidDisappear()
        h.store.listDidAppear()
        h.store.listDidDisappear()
        h.store.listDidAppear()
        await baseYield()
        // 붙잡은 첫 조회는 아직 스텁에 닿지 않았다(상한 1 — 둘째부터는 붙잡지 않고 곧장 스텁으로 간다). 여기서 0 이 아니면 겹쳐 띄운 것이다.
        #expect(hold.held == 1)
        #expect(frFocusGETs(h) == 0, "날아가는 조회 위에 또 띄웠다")
        #expect(await hold.releaseAndWaitDelivered())
        await h.settle()
        #expect(frFocusGETs(h) == 1)
        #expect(h.store.myFocusMode == true)
        // 끝난 뒤 다시 서면 또 묻는다(시간 스로틀 없음 — 맥에서 방금 끈 집중이 목록에 남지 않게).
        h.store.listDidDisappear()
        h.store.listDidAppear()
        await h.settle()
        #expect(frFocusGETs(h) == 2)
    }

    @Test("지금 탭은 메시지 스토어의 집중 집합을 그대로 읽는다 · 차단해 숨기면 두 탭 모두에서 빠진다(기준선: 숨기기 전엔 든다)")
    func nowReadsMessagesFocusAndBlockHides() async {
        let h = await MessagesHarness.make { $0.setDirectory(FrFx.directory()) }
        defer { h.tearDown() }
        #expect(h.model.now.hasLoadedDirectory, "전제: 지금 탭 명부가 있어야 겹치기를 잴 수 있다")
        #expect(h.store.focusedPeerIDs == [frFocused])
        #expect(h.model.now.focusedPeerIDs == h.store.focusedPeerIDs, "지금 탭이 다른 출처로 집중을 읽는다")

        // 상대가 집중을 켰다 — 지금 탭 명부만 새로 받아도 두 탭이 함께 따라온다(메시지 명부는 안 받았다).
        h.server.setDirectory(FrFx.directory(plainIsFocused: true))
        h.model.now.refresh()
        await h.settle()
        #expect(h.store.focusedPeerIDs == [frFocused, frPlain])
        #expect(h.model.now.focusedPeerIDs == [frFocused, frPlain])

        // 차단해 숨겼다 — 서버가 다음 조회에서 빼기 전의 창. 근무 점 · 상태메시지처럼 집중도 걷는다.
        h.store.hiddenBlockedPeerIDs = [frFocused]
        #expect(h.store.focusedPeerIDs == [frPlain], "차단해 숨긴 사람에게 '집중' 칩이 남는다")
        #expect(h.model.now.focusedPeerIDs == [frPlain], "지금 탭 근무 중 줄에 차단한 사람의 칩이 남는다")
        #expect(!h.store.isPeerFocused(frFocused))
        // 차단이 실패해 되돌아오면(숨김을 푼다) 다시 든다.
        h.store.hiddenBlockedPeerIDs = []
        #expect(h.model.now.focusedPeerIDs == [frFocused, frPlain])
    }
}

// MARK: - ③ 화면 배선 — 뷰 쪽 자리(주석을 걷고 선언 블록 안만 잰다)

@MainActor
@Suite struct V1017FocusRowWiringContractTests {
    @Test("대화 목록: 집합을 한 번 받아 줄마다 contains · 줄은 공용 칩 조각과 보이스오버에 집중을 잇는다 · 목록 위 한 줄은 규칙 하나")
    func threadListWiring() throws {
        let code = try Self.code("Sources/CheckMobileKit/Messages/MessagesTab.swift")
        let list = try Self.block(of: "struct MessagesListView: View", in: code)
        #expect(list.contains("let focused = store.focusedPeerIDs"), "목록이 잠금과 같은 출처(focusedPeerIDs)를 안 받는다")
        #expect(list.contains("MessagesThreadRow(row: row, presence: presence.peers[row.peerUserID], isFocused: focused.contains(row.peerUserID))"),
                "대화 목록 줄에 집중을 안 넘긴다 — 기본값 false 로 조용히 빈다")
        #expect(!list.contains("isPeerFocused("), "줄마다 겹치기를 다시 한다(사람 수의 제곱)")
        #expect(list.contains("MessagesWorkingStrip(people: presence.working, focused: focused,"), "얼굴 띠에 집중을 안 넘긴다")
        #expect(list.contains("if let focusNotice = MessagesFocusRules.listNotice(myFocus: store.myFocusMode)"), "목록 위 한 줄이 규칙을 안 지난다")
        #expect(list.contains("InlineNotice(text: focusNotice"), "목록 위 한 줄을 안 그린다")
        // 집중 끄기 단추는 없다(대표 답 #d_ldP912RctnTt "안내만 (단추 없음)").
        #expect(!code.contains("집중 끄기") && !code.contains("updateFocusMode("), "목록에 집중 끄기 단추가 생겼다")

        let row = try Self.block(of: "struct MessagesThreadRow: View", in: code)
        let rowBody = try Self.block(of: "var body: some View", in: row)
        #expect(rowBody.contains("chips: PersonName.focusChips(isFocused: isFocused)"), "대화 목록 줄 이름에 '집중' 칩을 안 단다")
        let spoken = try Self.block(of: "private var accessibilityText: String", in: row)
        #expect(spoken.contains("isFocused: isFocused"), "대화 목록 줄 보이스오버가 집중을 안 읽는다(children: .ignore)")

        let strip = try Self.block(of: "private struct MessagesWorkingStrip: View", in: code)
        #expect(strip.contains("MessagesPresenceRules.workingAccessibilityText(person, isFocused: focused.contains(person.id))"),
                "얼굴 띠 보이스오버가 집중을 안 읽는다")
        #expect(!strip.contains("FocusChip") && !strip.contains("focusChips("), "얼굴 띠에 칩을 달았다(대표 답: 보이스오버 말만)")
    }

    @Test("지금 탭 근무 중 줄: 스토어 집합을 한 번 받아 그룹 → 줄로 넘기고 · 우리 팀 · 다른 팀 두 모양(보통 · 큰 글자) 모두 칩을 단다")
    func nowWorkingRowsWiring() throws {
        let code = try Self.code("Sources/CheckMobileKit/Now/NowTab.swift")
        let section = try Self.block(of: "struct NowWorkingSection: View", in: code)
        #expect(section.contains("let focused = store.focusedPeerIDs"), "지금 탭이 메시지 스토어와 다른 출처로 집중을 읽는다")
        #expect(section.components(separatedBy: "NowWorkingGroup(").count - 1 == 3)
        #expect(section.components(separatedBy: "focused: focused").count - 1 == 3, "근무 중 그룹 셋 중 집중을 안 넘기는 자리가 있다")
        let group = try Self.block(of: "struct NowWorkingGroup: View", in: code)
        #expect(group.contains("NowWorkingRow(person: person, isFocused: focused.contains(person.id),"), "그룹이 줄에 집중을 안 넘긴다")
        let row = try Self.block(of: "struct NowWorkingRow: View", in: code)
        let body = try Self.block(of: "var body: some View", in: row)
        #expect(body.components(separatedBy: "PersonName(person.name, center: person.center, chips: PersonName.focusChips(isFocused: isFocused))").count - 1 == 2,
                "보통 · 큰 글자 두 모양 중 한쪽 이름 줄에 칩이 없다")
        #expect(!body.contains("PersonName(person.name, center: person.center)\n"), "칩 없는 옛 이름 줄이 남았다")

        let store = try Self.code("Sources/CheckMobileKit/Now/NowStore.swift")
        let source = try Self.block(of: "package var focusedPeerIDs: Set<String>", in: store)
        #expect(source.contains("context.links.messages?.focusedPeerIDs"), "지금 탭이 집중을 따로 겹친다 — 출처가 두 벌이 된다")
        #expect(!store.contains("MessagesFocusRules.focusedPeerIDs("), "지금 탭이 겹치기 규칙을 직접 부른다")
    }

    @Test("칩 보이스오버: 조각을 하나씩 읽는 줄(지금 탭)에서 칩이 '집중 중'으로 읽힌다 · 사람 줄 셋이 한 칩 조각을 부른다")
    func chipSpeaksAndIsShared() throws {
        let components = try Self.code("Sources/CheckMobileKit/Components/PersonComponents.swift")
        let chip = try Self.block(of: "package struct FocusChip: View", in: components)
        #expect(chip.contains(".accessibilityLabel(Text(MessagesFocusText.accessibility))"), "지금 탭 줄에서 칩이 '집중'(상태 이름)으로만 읽힌다")
        let callers = try IntegrationContractTests.files(containing: ["PersonName.focusChips(isFocused:"], under: "Sources/CheckMobileKit")
        #expect(callers == [
            "Sources/CheckMobileKit/Messages/MessagesNewConversationSheet.swift",
            "Sources/CheckMobileKit/Messages/MessagesTab.swift",
            "Sources/CheckMobileKit/Now/NowTab.swift",
        ], "사람 줄 칩 조각을 부르는 자리: \(callers)")
    }

    // MARK: 도우미

    private static func code(_ relative: String) throws -> String {
        try IntegrationContractTests.code(relative)
    }

    /// 선언 머리부터 **중괄호가 닫히는 곳까지**(`V1017FocusWiringContractTests.block` 과 같은 자르기).
    private static func block(of marker: String, in source: String) throws -> String {
        let hit = try #require(source.range(of: marker), "대조: '\(marker)' 를 못 찾았다(이름이 바뀌었나)")
        var depth = 0
        var started = false
        var out = ""
        for character in source[hit.upperBound...] {
            if character == "{" {
                depth += 1
                started = true
            }
            if started { out.append(character) }
            if character == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }
        #expect(started, "대조: '\(marker)' 뒤에 블록이 없다")
        return out
    }
}

// MARK: - ④ 데모

@MainActor
@Suite(.serialized) struct V1017FocusRowDemoTests {
    static let harin = "d0000000-0000-4000-8000-0000000000b5"
    static let doyun = "d0000000-0000-4000-8000-0000000000b4"
    static let mint = "d0000000-0000-4000-8000-000000000102"

    @Test("목록 장면: 대화 목록에 집중인 하린 줄이 선다(찌르기만 있는 맨 윗줄) · 내 집중은 꺼짐이라 목록 위 한 줄이 없다(기준선)")
    func listSceneShowsFocusedRow() async throws {
        let demo = await MessagesDemoFixtureTests.make(route: "messages")
        defer { demo.tearDown() }
        demo.store.listDidAppear()
        await demo.settle()
        #expect(await baseWaitUntil { demo.model.now.hasLoadedDirectory && !demo.store.isFetchingMyFocusMode })
        let rows = demo.store.threadItems(now: MobileClock.demoInstant)
        let focused = demo.store.focusedPeerIDs
        #expect(rows.filter { focused.contains($0.peerUserID) }.map(\.peerName) == ["하린"], "목록에 집중 줄이 하린 하나가 아니다")
        #expect(rows.first?.peerUserID == Self.harin)
        #expect(demo.store.myFocusMode == false, "기본 내 집중 픽스처(false)에 안 닿는다")
        #expect(MessagesFocusRules.listNotice(myFocus: demo.store.myFocusMode) == nil, "내 집중이 아닌데 목록 위 한 줄이 선다")
        // 얼굴 띠: 하린은 근무 중이라 띠에 서고 보이스오버가 집중을 말한다.
        let strip = demo.store.presenceBoard(now: MobileClock.demoInstant).working
        let harin = try #require(strip.first { $0.id == Self.harin }, "전제: 하린은 근무 중이라 얼굴 띠에 선다")
        #expect(MessagesPresenceRules.workingAccessibilityText(harin, isFocused: focused.contains(harin.id)) == "하린, 근무 중, 집중 중")
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }

    @Test("내 집중 장면(도윤): 목록이 서면 내 집중을 물어 목록 위 한 줄(sender_focused 문장)이 선다 — 대화에서 돌아온 목록도 같다")
    func myFocusSceneShowsListNotice() async {
        let demo = await MessagesDemoFixtureTests.make(route: "messages/\(Self.doyun)")
        defer { demo.tearDown() }
        demo.store.listDidAppear()
        #expect(await baseWaitUntil { demo.store.myFocusMode == true && !demo.store.isFetchingMyFocusMode })
        #expect(MessagesFocusRules.listNotice(myFocus: demo.store.myFocusMode) == MessageNoticeText.senderFocused)
        // 대화를 열었다 닫고 목록으로 돌아와도 그대로다(목록이 다시 물어도 같은 답).
        let token = UUID()
        demo.store.listDidDisappear()
        demo.store.conversationDidAppear(peerID: Self.doyun, token: token)
        await demo.settle()
        demo.store.conversationDidDisappear(token: token)
        demo.store.listDidAppear()
        #expect(await baseWaitUntil { !demo.store.isFetchingMyFocusMode })
        #expect(MessagesFocusRules.listNotice(myFocus: demo.store.myFocusMode) == MessageNoticeText.senderFocused)
        #expect(!demo.requests.contains { $0.path == "/rest/v1/profiles" && $0.method != "GET" })
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }

    @Test("지금 탭 장면: 근무 중 줄에 민트(우리 팀 · 상태 '3시까지 집중할게요')만 집중이다")
    func nowSceneShowsMint() async {
        let demo = await MessagesDemoFixtureTests.make(route: "now")
        defer { demo.tearDown() }
        let now = demo.model.now
        #expect(await baseWaitUntil { now.hasLoadedDirectory && now.hasLoadedTeam && now.refreshTask == nil })
        let people = now.workingPeople(now: MobileClock.demoInstant)
        let focused = now.focusedPeerIDs
        #expect(people.filter { focused.contains($0.id) }.map(\.name) == ["민트"], "근무 중 줄 집중: \(people.filter { focused.contains($0.id) }.map(\.name))")
        let mint = people.first { $0.id == Self.mint }
        #expect(mint?.isTeammate == true, "전제: 민트는 우리 팀 줄이다 — 다른 팀 줄만 칩을 달면 데모에서 안 보인다")
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }
}
