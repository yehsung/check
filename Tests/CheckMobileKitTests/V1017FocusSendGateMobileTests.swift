@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.17 — 집중 모드 이식(메시지). 맥 `Tests/checkTests/FocusSendGateTests.swift` 를 본으로 한 폰판이다.
//
// 대표 요청 5·6(2026-11-03, 원문):
//   5. "콕/메세지 창 에서부터 집중 모드인 사람들은 표시가 되게끔 하고 메세지나 찌르기 비활성화 되게."
//   6. "집중모드중인 사람들은 남들 찌르거나 메세지 못보내게 해줘. (자기는 못받으면서 남들한텐 할 수 있는게 안맞음)"
// 대표 결정(되묻지 말 것): 상대가 집중이면 '집중' 표시 · 대화는 열리되 보내기(글·이모티콘)만 막힘. 내가 집중이면 메시지 막힘
// (폰엔 찌르기·울트라 보내는 길이 없다). 확성기·게임 신청은 그대로.
// ★ 결정이 **아닌** 것(현재 상태 — 대표 답 대기, 2026-11-03 결정 카드):
//   D1 폰 [집중 끄기] 단추 — 지금은 없다(profiles PATCH 금지 그대로 · 문장은 "맥에서 집중을 끄면"). 답이 B(끄기 단추)면
//      `MobileForbiddenCalls` 의 focus_mode PATCH 금지 · 이 파일 ⑧(`phoneNeverWritesFocus`) · 내 집중 문장을 함께 고친다.
//   D2 집중 표시 범위 — 지금은 맥과 같은 두 곳(새 대화 사람 줄 · 대화 이름표). 답이 B(대화 목록 줄 · 지금 탭 근무 중 줄)면
//      칩은 `MessagesStore.focusedPeerIDs` 한 곳을 읽는다(판에 칸을 다시 만들지 않는다).
//
// 이 파일이 재는 것:
//  ① 규칙: 내 집중 > 상대 집중 · 모름(nil)은 막지 않음 · 명부 겹치기(뒤 목록이 이긴다) · 입력줄 한 줄의 순서 · 틱 조건
//  ①-2 서버 실출력(맥 하네스 픽스처 Tests/checkTests/Fixtures/directory-rpc): 8칸이면 켠 사람만 잠기고, 옛 7칸이면 아무도 아니다
//  ② 상대 집중 짝 게이트: canSend · canSendSticker · sendDraft · sendSticker — 요청 0건, 글은 남는다(기준선: 집중 아닌 사람은 1건)
//  ③ 내 집중(한 행 GET): true 면 모두에게 막힘 · false·실패·행 없음·null 은 막지 않음 · 실패는 알던 값을 안 바꾼다
//  ④ 서버 sender_focused(맥 하네스 골든): 문구 · 켜짐으로 받아들임 · 다음 누름은 요청 0 · 그보다 먼저 띄운 조회의 답은 버린다
//     · 문구는 상태로 넘어가 맥에서 끈 값을 받으면 사라진다(target_focused 도 명부가 알게 된 뒤 같다 — 검토 2026-11-03)
//  ⑤ 따라잡기: 묻는 때(대화가 설 때 · 대화가 떠 있는 채 앞으로 올 때 · 켜짐으로 알 때만 60초 틱) · 묻지 않는 때
//  ⑥ target_focused 뒤 명부 둘(메시지 · 지금 탭)을 다시 받는다 — 겹치기 순서 함정 · 로컬에서 찍지 않는다 · 새 대화 시트 새로고침도 둘을 받는다
//  ⑦ 내 집중이어도 확성기는 나간다 · ⑧ 금지 호출 0 · profiles 쓰기 0
//  ⑨ 화면 배선 소스 계약(주석 걷기) — 폰 뷰는 맥 스위트도 swift test 도 컴파일하지 않는다
//  ⑩ 데모 픽스처: 명부 다섯 장의 focus_mode 칸 · 상대 집중 장면(하린) · 내 집중 장면(도윤) · 민재 장면은 그대로

private let fgFocused = "peer-focus"      // 명부가 집중이라 말하는 사람
private let fgPlain = "peer-plain"        // 명부가 집중 아님이라 말하는 사람
private let fgAbsent = "peer-absent"      // 칸이 없는 행(옛 서버 모양)
private let fgNull = "peer-null"          // 칸이 null 인 행

private enum FgFx {
    /// 명부 한 행. `focus` 가 nil 이면 **칸 자체가 없다**(옛 7칸), "null" 이면 null, 그 밖은 그 글자 그대로.
    static func row(_ id: String, name: String, focus: String?) -> String {
        let tail = focus.map { #","focus_mode":\#($0)"# } ?? ""
        return #"{"user_id":"\#(id)","display_name":"\#(name)","avatar_url":null,"is_working":true,"message_capable":true,"center":null,"status_message":null\#(tail)}"#
    }

    /// 기본 명부: 집중 1 · 집중 아님 1 · 칸 없음 1 · null 1.
    static func directory(focusedIsFocused: Bool = true, plainIsFocused: Bool = false) -> String {
        "[" + [
            row(fgFocused, name: "집중이", focus: focusedIsFocused ? "true" : "false"),
            row(fgPlain, name: "보통이", focus: plainIsFocused ? "true" : "false"),
            row(fgAbsent, name: "옛서버", focus: nil),
            row(fgNull, name: "널이", focus: "null"),
        ].joined(separator: ",") + "]"
    }

    static func myFocus(_ value: Bool) -> MobileStubResponse { .json(#"[{"focus_mode":\#(value)}]"#) }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 맥 하네스가 실서버에서 떠 온 바이트(Tests/checkTests/Fixtures/…) — 스텁이 실어 준다는 가정이 아니라 서버가 내는 모양.
    static func serverFixture(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Tests/checkTests/Fixtures/\(relative)"), encoding: .utf8)
    }
}

@MainActor
private func fgFocusGETs(_ h: MessagesHarness) -> Int {
    h.requests.filter { $0.path == "/rest/v1/profiles" && $0.method == "GET" && $0.queryValue("select") == "focus_mode" }.count
}

@MainActor
private func fgExpectNoProfileWrites(_ h: MessagesHarness, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!h.requests.contains { $0.path == "/rest/v1/profiles" && $0.method != "GET" },
            "폰이 profiles 를 썼다 — 폰은 집중을 켜지도 끄지도 않는다(R9)", sourceLocation: sourceLocation)
    h.expectNoForbiddenCalls(sourceLocation: sourceLocation)
}

// MARK: - ① 규칙

@Suite struct V1017FocusRuleTests {
    @Test("내 집중이 상대 집중보다 앞이고 · 모름(nil)과 꺼짐은 막지 않으며 · 문장은 서버 거절 문구와 같은 글자다")
    func blockOrder() {
        #expect(MessagesFocusRules.block(myFocus: true, peerFocused: true) == .myself)
        #expect(MessagesFocusRules.block(myFocus: true, peerFocused: false) == .myself)
        #expect(MessagesFocusRules.block(myFocus: false, peerFocused: true) == .peer)
        #expect(MessagesFocusRules.block(myFocus: nil, peerFocused: true) == .peer)
        #expect(MessagesFocusRules.block(myFocus: false, peerFocused: false) == nil)
        #expect(MessagesFocusRules.block(myFocus: nil, peerFocused: false) == nil, "모름을 켜짐으로 읽었다 — 일시 장애 한 번에 전부 잠긴다")
        // 미리 막았을 때와 서버가 거절했을 때 같은 문장(`MessagesSendRules.notice`).
        #expect(MessagesFocusBlock.myself.notice == MessagesSendRules.notice(for: .senderFocused, maxLength: nil))
        #expect(MessagesFocusBlock.peer.notice == MessagesSendRules.notice(for: .targetFocused, maxLength: nil))
        #expect(MessagesFocusBlock.myself.notice == MessageNoticeText.senderFocused)
        #expect(MessagesFocusBlock.peer.notice == MessageNoticeText.targetFocused)
        #expect(MessagesFocusBlock.myself.notice != MessagesFocusBlock.peer.notice)
    }

    @Test("명부 겹치기: 뒤(지금 탭) 목록이 이긴다 · 목록에 있는 사람은 그 목록 값이 답 · 칸 없음/null 은 아님 · 나는 빼고")
    func focusedOverlay() {
        func entry(_ id: String, focused: Bool) -> PokeDirectoryEntry {
            var value = PokeDirectoryEntry(userID: id, name: id, avatarURL: nil, isWorking: true)
            value.isFocused = focused
            return value
        }
        func row(_ id: String, focus: Bool?) -> PokeDirectoryRow {
            PokeDirectoryRow(userId: id, displayName: id, avatarUrl: nil, isWorking: true, focusMode: focus)
        }
        // 시트 목록은 둘 다 집중이라 말하지만 지금 탭(더 새 값)은 a 가 껐다고 말한다 — a 는 풀리고 b 는 그대로.
        let both = MessagesFocusRules.focusedPeerIDs(
            nowDirectory: [row("a", focus: false), row("c", focus: nil), row("me", focus: true)],
            messagesDirectory: [entry("a", focused: true), entry("b", focused: true), entry("me", focused: true)],
            me: "me"
        )
        #expect(both == ["b"], "\(both)")
        // 거꾸로: 시트 목록은 아님 · 지금 탭이 켰다 — 켜진다.
        #expect(MessagesFocusRules.focusedPeerIDs(
            nowDirectory: [row("a", focus: true)], messagesDirectory: [entry("a", focused: false)], me: nil) == ["a"])
        // 목록이 하나뿐이어도 된다 · 둘 다 없으면 아무도 아니다.
        #expect(MessagesFocusRules.focusedPeerIDs(nowDirectory: nil, messagesDirectory: [entry("x", focused: true)], me: nil) == ["x"])
        #expect(MessagesFocusRules.focusedPeerIDs(nowDirectory: nil, messagesDirectory: nil, me: nil).isEmpty)
    }

    @Test("입력줄 한 줄: 집중 사유가 결과 문구보다 앞이고 늘 선다 · 집중이 없으면 결과 문구 · 빈 글은 줄 없음")
    func noticeLineOrder() {
        #expect(MessagesComposerRules.noticeLine(focus: .peer, sendNotice: MessagesSendRules.connectionNotice) == MessageNoticeText.targetFocused)
        #expect(MessagesComposerRules.noticeLine(focus: .myself, sendNotice: nil) == MessageNoticeText.senderFocused)
        #expect(MessagesComposerRules.noticeLine(focus: nil, sendNotice: MessagesSendRules.connectionNotice) == MessagesSendRules.connectionNotice)
        #expect(MessagesComposerRules.noticeLine(focus: nil, sendNotice: "") == nil)
        #expect(MessagesComposerRules.noticeLine(focus: nil, sendNotice: nil) == nil)
    }

    @Test("60초 틱 재확인은 켜짐으로 알고 대화가 떠 있을 때만이다")
    func tickCondition() {
        #expect(MessagesFocusRules.rechecksOnTick(myFocus: true, conversationOpen: true))
        #expect(!MessagesFocusRules.rechecksOnTick(myFocus: true, conversationOpen: false))
        #expect(!MessagesFocusRules.rechecksOnTick(myFocus: false, conversationOpen: true))
        #expect(!MessagesFocusRules.rechecksOnTick(myFocus: nil, conversationOpen: true), "모름까지 틱마다 물으면 집중을 안 쓰는 사람도 매분 GET 이다")
    }

    @Test("칩 글자는 맥과 같다('집중' · '집중 중') — 짧아서 Release strings 게이트에 못 쓴다")
    func chipTexts() {
        #expect(MessagesFocusText.personChip == "집중")
        #expect(MessagesFocusText.conversationChip == "집중 중")
        #expect(MessagesFocusText.personChip.utf8.count <= 15 && MessagesFocusText.conversationChip.utf8.count <= 15,
                "칩 글자가 길어졌다 — 그러면 출시 게이트 문구 표 후보가 될 수 있다(이 단언과 MessagesFocusText 주석을 함께 고쳐라)")
        #expect(MessageNoticeText.senderFocused.utf8.count > 15 && MessageNoticeText.targetFocused.utf8.count > 15)
    }
}

// MARK: - ①-2 · ② 상대 집중 — 서버 실출력 · 스토어 짝 게이트

@MainActor
@Suite(.serialized) struct V1017PeerFocusStoreTests {
    @Test("서버 실출력 8칸: 켠 사람만 집중이고 그 사람에게만 잠긴다 · 옛 7칸: 아무도 잠기지 않는다")
    func serverDirectoryFixtures() async throws {
        let focusedID = "3e240c02-8972-478e-a674-014f498a641b"   // 8칸 픽스처에서 focus_mode true 인 행
        let otherID = "785b5732-75fe-4a71-931a-2e3f06e63505"
        for (file, expectFocused) in [("directory-rpc/app_user_directory__draft_8col.json", true),
                                      ("directory-rpc/app_user_directory__current_7col.json", false)] {
            let text = try FgFx.serverFixture(file)
            let h = await MessagesHarness.make { $0.setDirectory(text) }
            defer { h.tearDown() }
            h.store.loadDirectory(force: true)
            await h.settle()
            #expect(h.store.directory.count == 4, "\(file): 명부 디코드가 깨졌다")
            #expect(h.store.isPeerFocused(focusedID) == expectFocused, "\(file)")
            #expect(!h.store.isPeerFocused(otherID), "\(file)")
            #expect(h.store.focusedPeerIDs == (expectFocused ? [focusedID] : []), "\(file)")
            h.store.setDraft("안녕하세요", for: focusedID)
            h.store.setDraft("안녕하세요", for: otherID)
            #expect(h.store.canSend(to: focusedID) == !expectFocused, "\(file)")
            #expect(h.store.canSend(to: otherID), "\(file): 집중 아닌 사람까지 잠겼다")
        }
    }

    @Test("상대 집중: 글·이모티콘 두 문 모두 요청 0 · 글은 입력칸에 남고 사유는 target_focused 문장 · 집중 아닌 사람은 그대로 나간다(기준선)")
    func peerFocusBlocksBothDoors() async {
        let h = await MessagesHarness.make { $0.setDirectory(FgFx.directory()) }
        defer { h.tearDown() }
        h.store.loadDirectory(force: true)
        h.store.conversationDidAppear(peerID: fgFocused, token: UUID())
        await h.settle()
        #expect(h.store.isPeerFocused(fgFocused))
        #expect(!h.store.isPeerFocused(fgPlain) && !h.store.isPeerFocused(fgAbsent) && !h.store.isPeerFocused(fgNull),
                "집중 아님 · 칸 없음 · null 은 집중이 아니다")

        h.store.setDraft("집중 중인 사람에게", for: fgFocused)
        #expect(h.store.focusBlock(for: fgFocused) == .peer)
        #expect(MessagesComposerRules.noticeLine(focus: h.store.focusBlock(for: fgFocused), sendNotice: h.store.sendNotices[fgFocused])
                == MessageNoticeText.targetFocused, "입력줄 사유 줄이 안 선다")
        #expect(!h.store.canSend(to: fgFocused), "[보내기]가 켜진다")
        #expect(!h.store.canSendSticker(to: fgFocused), "이모티콘 문이 열려 있다 — 짝 게이트의 한쪽이 샌다")
        #expect(!h.store.sendDraft(to: fgFocused, isComposing: false))
        #expect(!h.store.sendSticker(.joy, to: fgFocused))
        await h.settle()
        #expect(h.count("send_message") == 0, "막힌 전송이 서버로 나갔다")
        #expect(h.store.draft(for: fgFocused) == "집중 중인 사람에게", "막혔는데 입력칸이 비었다")
        #expect(h.store.pendingOutgoing.isEmpty)

        // 기준선: 집중이 아닌 사람에게는 글·이모티콘이 그대로 나간다.
        h.store.setDraft("보통 사람에게", for: fgPlain)
        #expect(h.store.focusBlock(for: fgPlain) == nil)
        #expect(h.store.canSend(to: fgPlain) && h.store.canSendSticker(to: fgPlain))
        #expect(h.store.sendDraft(to: fgPlain, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        #expect(h.store.sendSticker(.joy, to: fgPlain))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.count("send_message") == 2)
        fgExpectNoProfileWrites(h)
    }

    @Test("target_focused(대화 중에 상대가 켬): 명부 둘을 다시 받아 칩·잠금이 따라온다 — 지금 탭 명부도 받아야 겹치기에서 이긴다")
    func targetFocusedRefreshesBothDirectories() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory(plainIsFocused: false))
            server.setSend(.json(#"{"status":"target_focused"}"#))
        }
        defer { h.tearDown() }
        h.store.loadDirectory(force: true)
        h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
        await h.settle()
        #expect(h.model.now.hasLoadedDirectory, "전제: 지금 탭 명부가 있어야 겹치기 함정을 잴 수 있다")
        #expect(!h.store.isPeerFocused(fgPlain))
        let directoryBefore = h.count("app_user_directory")
        let nowRefreshBefore = h.model.now.refreshCount

        // 상대가 대화 중에 집중을 켰다 — 서버 명부는 이제 그렇게 말한다.
        h.server.setDirectory(FgFx.directory(plainIsFocused: true))
        h.store.setDraft("방금 켠 사람에게", for: fgPlain)
        #expect(h.store.sendDraft(to: fgPlain, isComposing: false), "명부가 아직 모르니 나간다(서버가 판정)")
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.count("send_message") == 1)
        #expect(h.store.draft(for: fgPlain) == "방금 켠 사람에게", "거절된 글이 입력칸으로 안 돌아왔다")
        #expect(h.count("app_user_directory") >= directoryBefore + 2, "명부를 하나만 다시 받았다 — 지금 탭 옛 값이 덮는다")
        #expect(h.model.now.refreshCount > nowRefreshBefore, "지금 탭 새로고침을 안 불렀다")
        #expect(h.store.isPeerFocused(fgPlain), "다시 받은 뒤에도 잠금이 안 따라왔다")
        #expect(h.store.focusedPeerIDs.contains(fgPlain), "칩이 안 따라왔다")
        #expect(!h.store.canSend(to: fgPlain))
        // 문구는 상태로 넘어갔다 — 결과 문구 자리는 비고, 입력줄은 같은 문장을 집중 판정에서 띄운다.
        #expect(h.store.sendNotices[fgPlain] == nil, "명부가 알게 된 뒤에도 거절 문구를 따로 쥐고 있다 — 상대가 끄면 남는다")
        #expect(MessagesComposerRules.noticeLine(focus: h.store.focusBlock(for: fgPlain), sendNotice: h.store.sendNotices[fgPlain])
                == MessageNoticeText.targetFocused, "넘긴 뒤 입력줄 사유가 사라졌다")

        // 상대가 집중을 껐다 — 지금 탭 다음 새로고침(60초 틱과 같은 길)이 받으면 사유 줄도 [보내기] 잠금도 풀린다(검토 2026-11-03 재현).
        h.server.setDirectory(FgFx.directory(plainIsFocused: false))
        h.model.now.refresh()
        await h.settle()
        #expect(!h.store.isPeerFocused(fgPlain))
        #expect(h.store.canSend(to: fgPlain), "상대가 껐는데 [보내기]가 잠겨 있다")
        #expect(MessagesComposerRules.noticeLine(focus: h.store.focusBlock(for: fgPlain), sendNotice: h.store.sendNotices[fgPlain]) == nil,
                "상대가 껐는데 '지금 집중 중이에요'가 켜진 [보내기] 위에 남았다")
        fgExpectNoProfileWrites(h)
    }

    @Test("target_focused 를 받아도 로컬에서 상대를 집중으로 찍지 않는다 — 명부가 '아님'이면 다시 보낼 수 있다(기존 재전송 시험과 같은 약속)")
    func targetFocusedDoesNotMarkLocally() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory(plainIsFocused: false))
            server.setSend(.json(#"{"status":"target_focused"}"#))
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
        await h.settle()
        h.store.setDraft("한 번", for: fgPlain)
        #expect(h.store.sendDraft(to: fgPlain, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(!h.store.isPeerFocused(fgPlain))
        #expect(h.store.canSend(to: fgPlain))
        // 명부가 아직 모르면 거절 문구가 유일한 사유라 남는다(넘길 상태가 없다 — 위 시험의 '넘긴 뒤 비었다'와 다른 결과).
        #expect(h.store.sendNotices[fgPlain] == MessageNoticeText.targetFocused, "명부가 모르는데 거절 사유를 지웠다")
        #expect(h.store.sendDraft(to: fgPlain, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        #expect(h.count("send_message") == 2)
    }
}

// MARK: - ③ · ④ · ⑤ 내 집중

@MainActor
@Suite(.serialized) struct V1017MyFocusStoreTests {
    @Test("내 집중 GET: true 면 누구에게도 글·이모티콘 0건(사유 sender_focused) · false/실패/행 없음/null/연결 실패는 막지 않는다")
    func myFocusFetchOutcomes() async {
        let cases: [(String, MobileStubResponse?, Bool?)] = [
            ("켜짐", FgFx.myFocus(true), true),
            ("꺼짐", FgFx.myFocus(false), false),
            ("함수·표 없음(404)", nil, nil),
            ("행 없음", .json("[]"), nil),
            ("칸 null", .json(#"[{"focus_mode":null}]"#), nil),
            ("연결 실패", .networkFailure(), nil),
        ]
        for (label, response, expected) in cases {
            let h = await MessagesHarness.make { server in
                server.setDirectory(FgFx.directory())
                server.setMyFocus(response)
            }
            defer { h.tearDown() }
            #expect(fgFocusGETs(h) == 0, "\(label): 대화가 없는데 내 집중을 물었다(나 탭 조회 수 계약)")
            h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
            await h.settle()
            #expect(fgFocusGETs(h) >= 1, "\(label): 대화가 섰는데 묻지 않았다")
            #expect(h.store.myFocusMode == expected, "\(label): \(String(describing: h.store.myFocusMode))")
            h.store.setDraft("보내 볼게요", for: fgPlain)
            let blocked = expected == true
            #expect(h.store.focusBlock(for: fgPlain) == (blocked ? .myself : nil), "\(label)")
            #expect(h.store.canSend(to: fgPlain) == !blocked, "\(label)")
            #expect(h.store.canSendSticker(to: fgPlain) == !blocked, "\(label)")
            if blocked {
                // 내 집중은 상대 집중보다 앞이다 — 집중인 상대에게도 '내 집중' 사유.
                #expect(h.store.focusBlock(for: fgFocused) == .myself)
                #expect(h.store.focusBlock(for: fgPlain)?.notice == MessageNoticeText.senderFocused)
                #expect(!h.store.sendDraft(to: fgPlain, isComposing: false))
                #expect(!h.store.sendSticker(.joy, to: fgPlain))
                await h.settle()
                #expect(h.count("send_message") == 0, "\(label): 내 집중인데 나갔다")
                #expect(h.store.draft(for: fgPlain) == "보내 볼게요")
            } else {
                #expect(h.store.sendDraft(to: fgPlain, isComposing: false), "\(label)")
                #expect(await baseWaitUntil { !h.store.isSending })
                #expect(h.count("send_message") == 1, "\(label): 모름/꺼짐인데 막혔다")
            }
            fgExpectNoProfileWrites(h)
        }
    }

    @Test("알던 켜짐은 조회 실패·행 없음이 지우지 않는다(기준선이 nil 이 아니다) · 그 뒤 false 를 받으면 풀린다")
    func failureKeepsKnownValue() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory())
            server.setMyFocus(FgFx.myFocus(true))
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
        await h.settle()
        #expect(h.store.myFocusMode == true)
        for broken in [MobileStubResponse.networkFailure(), .json("[]"), .missingFunction("profiles")] {
            h.server.setMyFocus(broken)
            let before = fgFocusGETs(h)
            h.store.appDidEnterBackground()
            h.store.appDidBecomeActive()
            await h.settle()
            #expect(fgFocusGETs(h) == before + 1)
            #expect(h.store.myFocusMode == true, "실패·모름이 알던 켜짐을 지웠다 — 막아야 할 전송이 열린다")
        }
        h.server.setMyFocus(FgFx.myFocus(false))
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(h.store.myFocusMode == false)
        h.store.setDraft("이제 보낼게요", for: fgPlain)
        #expect(h.store.canSend(to: fgPlain))
    }

    @Test("서버 sender_focused(맥 하네스 골든): 문구가 서고 켜짐으로 받아들여 다음 누름은 요청 0 · 글은 남는다")
    func senderFocusedAdopted() async throws {
        let golden = try FgFx.serverFixture("sender-focus-rpc/send_message__sender_focused.json")
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory())
            server.setSend(.json(golden))   // 내 집중 GET 은 404 — 이 폰은 모른다(맥에서 방금 켰다)
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
        await h.settle()
        #expect(h.store.myFocusMode == nil)
        h.store.setDraft("맥에서 켠 줄 모르고", for: fgPlain)
        #expect(h.store.sendDraft(to: fgPlain, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.count("send_message") == 1)
        // 거절 직후 입력줄은 sender_focused 문장이다(기준선) — 결과 문구 자리가 아니라 켜짐을 들인 집중 판정이 띄운다.
        #expect(MessagesComposerRules.noticeLine(focus: h.store.focusBlock(for: fgPlain), sendNotice: h.store.sendNotices[fgPlain])
                == MessageNoticeText.senderFocused,
                "1.0.16 처럼 '잠시 후 다시 시도'로 접혔다: \(String(describing: h.store.sendNotices[fgPlain]))")
        #expect(h.store.sendNotices[fgPlain] == nil, "sender_focused 를 결과 문구로도 적었다 — 맥에서 끈 뒤에도 남는다")
        #expect(h.store.myFocusMode == true, "서버가 알려 준 내 집중을 받아들이지 않았다")
        #expect(h.store.draft(for: fgPlain) == "맥에서 켠 줄 모르고")
        #expect(h.store.focusBlock(for: fgPlain) == .myself)
        #expect(!h.store.sendDraft(to: fgPlain, isComposing: false))
        #expect(!h.store.sendSticker(.joy, to: fgPlain))
        h.store.setDraft("다른 사람에게도", for: fgAbsent)
        #expect(!h.store.sendDraft(to: fgAbsent, isComposing: false), "내 집중은 누구에게나다")
        await h.settle()
        #expect(h.count("send_message") == 1, "받아들인 뒤에도 요청이 또 나갔다")

        // 맥에서 껐다 — 대화를 띄운 채 앞으로 오면 조회(false)가 풀고, 입력줄에 옛 사유가 남지 않는다(검토 2026-11-03 재현 그대로).
        h.server.setMyFocus(FgFx.myFocus(false))
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(h.store.myFocusMode == false)
        #expect(h.store.canSend(to: fgPlain), "맥에서 껐는데 [보내기]가 잠겨 있다")
        #expect(MessagesComposerRules.noticeLine(focus: h.store.focusBlock(for: fgPlain), sendNotice: h.store.sendNotices[fgPlain]) == nil,
                "맥에서 껐는데 '맥에서 집중을 끄면 보낼 수 있어요'가 켜진 [보내기] 위에 남았다")
        fgExpectNoProfileWrites(h)
    }

    @Test("sender_focused 를 들인 뒤 도착한, 그보다 먼저 띄운 조회(false)는 버린다 · 그 뒤 새로 띄운 조회는 반영한다")
    func staleFetchLosesToAdoption() async throws {
        let golden = try FgFx.serverFixture("sender-focus-rpc/send_message__sender_focused.json")
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory())
            server.setMyFocus(FgFx.myFocus(false))
            server.setSend(.json(golden))
        }
        defer { h.tearDown() }
        let hold = BaseHold.install(host: h.host) { $0.path == "/rest/v1/profiles" && $0.queryValue("select") == "focus_mode" }
        h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
        #expect(await hold.waitHeld())
        #expect(h.store.isFetchingMyFocusMode)
        h.store.setDraft("붙잡힌 조회 사이", for: fgPlain)
        #expect(h.store.sendDraft(to: fgPlain, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending && h.store.myFocusMode == true })
        #expect(await hold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { !h.store.isFetchingMyFocusMode })
        await h.barrier()
        #expect(h.store.myFocusMode == true, "먼저 띄운 조회의 낡은 false 가 서버 거절이 알려 준 켜짐을 덮었다")
        // 새로 띄운 조회는 더 새 사실이다 — 반영한다(맥에서 끈 경우).
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(h.store.myFocusMode == false)
    }

    @Test("묻는 때: 대화가 설 때 · 대화가 떠 있는 채 앞으로 올 때 · 켜짐일 때만 틱 — 대화가 없거나 뒤에 있거나 꺼짐이면 묻지 않는다")
    func whenToAsk() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory())
            server.setMyFocus(FgFx.myFocus(true))
        }
        defer { h.tearDown() }
        // 대화 없이 앞으로 오기 — 묻지 않는다.
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(fgFocusGETs(h) == 0)
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(fgFocusGETs(h) == 0, "모르는데 틱이 물었다")

        // ① 대화가 선다.
        let token = UUID()
        h.store.conversationDidAppear(peerID: fgPlain, token: token)
        await h.settle()
        #expect(fgFocusGETs(h) == 1)
        #expect(h.store.myFocusMode == true)

        // ③ 켜짐 + 대화 — 틱이 묻는다. 맥에서 껐다(false) → 풀린다.
        h.server.setMyFocus(FgFx.myFocus(false))
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(fgFocusGETs(h) == 2)
        #expect(h.store.myFocusMode == false)
        // 꺼짐이면 틱은 묻지 않는다.
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(fgFocusGETs(h) == 2, "꺼짐인데 틱이 물었다")

        // ② 대화가 떠 있는 채 앞으로 온다 — 맥에서 다시 켰다.
        h.server.setMyFocus(FgFx.myFocus(true))
        h.store.appDidEnterBackground()
        h.store.refreshMyFocusModeIfFocused()
        await h.settle()
        #expect(fgFocusGETs(h) == 2, "앱이 뒤에 있는데 틱이 물었다")
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(fgFocusGETs(h) == 3)
        #expect(h.store.myFocusMode == true)

        // 대화를 닫으면 켜짐이어도 틱·앞으로 오기 모두 묻지 않는다.
        h.store.conversationDidDisappear(token: token)
        h.store.refreshMyFocusModeIfFocused()
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(fgFocusGETs(h) == 3, "대화가 없는데 물었다")
        fgExpectNoProfileWrites(h)
    }

    @Test("로그아웃·계정 전환은 내 집중을 모름으로 되돌리고, 앞 계정의 늦은 조회는 다음 계정에 닿지 않는다")
    func resetClearsMyFocus() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory())
            server.setMyFocus(FgFx.myFocus(true))
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
        await h.settle()
        #expect(h.store.myFocusMode == true)
        // 앞 계정이 다시 띄운 조회를 붙잡아 둔 채 계정을 바꾼다.
        let hold = BaseHold.install(host: h.host) { $0.path == "/rest/v1/profiles" && $0.queryValue("select") == "focus_mode" }
        h.store.appDidEnterBackground()
        h.store.appDidBecomeActive()
        #expect(await hold.waitHeld())
        await h.switchAccount()
        #expect(h.store.myFocusMode == nil, "앞 계정의 집중이 다음 계정에 남았다")
        #expect(await hold.releaseAndWaitDelivered())
        await h.barrier()
        await baseYield()
        #expect(h.store.myFocusMode == nil, "앞 계정의 늦은 조회가 다음 계정의 값을 세웠다")
    }

    @Test("내 집중이어도 확성기는 나간다(대표 결정 '확성기·게임 신청은 그대로')")
    func megaphoneStillSends() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(FgFx.directory())
            server.setMyFocus(FgFx.myFocus(true))
            server.override("megaphone_info") { _ in .json(MessagesMegaphoneTests.info(recipients: 9, ruby: 130)) }
            server.override("send_megaphone") { _ in
                .json(#"{"status":"ok","duplicate":false,"megaphone_id":"m1","recipients":9,"price":50,"ruby_balance":80}"#)
            }
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: fgPlain, token: UUID())
        await h.settle()
        #expect(h.store.myFocusMode == true)
        #expect(!h.store.canSend(to: fgPlain) || h.store.draft(for: fgPlain).isEmpty)
        let mega = h.store.megaphone
        mega.open()
        _ = await baseWaitUntil { mega.info != nil }
        mega.setDraft("집중 중에도 공지는 나가요")
        mega.requestSend()
        #expect(mega.confirmSend())
        _ = await baseWaitUntil { !mega.isSending && !mega.infoLoading }
        await h.barrier()
        #expect(h.count("send_megaphone") == 1, "내 집중이 확성기까지 막았다")
        fgExpectNoProfileWrites(h)
    }
}

// MARK: - ⑨ 화면 배선 — 짝 게이트의 뷰 쪽 자리(주석을 걷고 선언 블록 안만 잰다)

@MainActor
@Suite struct V1017FocusWiringContractTests {
    @Test("입력줄: [보내기]가 집중 판정을 보고(조합 중에도) · 사유 줄은 규칙 하나로 결과 문구보다 앞 · 결과 문구를 직접 그리는 길이 없다")
    func composerLocksAndExplains() throws {
        let code = try Self.code("Sources/CheckMobileKit/Messages/MessagesComposerView.swift")
        let enabled = try Self.block(of: "private var sendEnabled: Bool", in: code)
        #expect(enabled.contains("store.focusBlock(for: peerID) == nil"), "[보내기]가 집중을 안 본다 — 눌리는 척만 한다")
        let guardLine = try #require(enabled.range(of: "store.focusBlock(for: peerID) == nil"))
        let composing = try #require(enabled.range(of: "isComposing ||"))
        #expect(guardLine.lowerBound < composing.lowerBound, "조합 중이면 집중 판정을 건너뛴다")

        let composer = try Self.block(of: "struct MessagesComposerView: View", in: code)
        #expect(composer.contains("MessagesComposerRules.noticeLine(focus: store.focusBlock(for: peerID), sendNotice: store.sendNotices[peerID])"),
                "입력칸 위 줄이 집중 사유를 안 띄운다")
        #expect(composer.components(separatedBy: "store.sendNotices[").count - 1 == 1,
                "결과 문구를 규칙 밖에서 따로 그린다 — 두 줄이 서거나 사유가 뒤로 밀린다")

        let sheet = try Self.block(of: "private struct MessagesStickerSheet", in: code)
        #expect(sheet.contains("MessagesComposerRules.noticeLine(focus: store.focusBlock(for: peerID), sendNotice: notice)"),
                "이모티콘 시트가 집중 사유를 고르기 전에 안 띄운다(입력줄 줄은 시트 뒤에 가린다)")
        let pick = try Self.block(of: "private func pick(", in: code)
        #expect(pick.contains("store.focusBlock(for: peerID)"), "고른 뒤 실패 사유가 집중을 모른다 — '보내는 중'으로 접힌다")
        #expect(!pick.contains("setDraft(") && !pick.contains(".draft("), "이모티콘 길이 초안을 만진다")
    }

    @Test("대화 화면: 이름표에 스토어의 상대 집중을 넘기고 이름 옆 '집중 중' 칩 · 보이스오버에도 잇는다")
    func nameplateShowsFocusChip() throws {
        let code = try Self.code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift")
        let view = try Self.block(of: "struct MessagesConversationView: View", in: code)
        #expect(view.contains("let peerFocused = store.isPeerFocused(peerID)"), "대화 화면이 잠금과 같은 판정으로 칩을 안 고른다")
        #expect(view.contains("MessagesConversationNameplate(header: header, presence: presence, statusMessage: statusMessage, isFocused: peerFocused)"),
                "이름표에 집중을 안 넘긴다 — 기본값 false 로 조용히 빈다")
        let nameplate = try Self.block(of: "struct MessagesConversationNameplate: View", in: code)
        let body = try Self.block(of: "var body: some View", in: nameplate)
        let chip = try Self.block(of: "if isFocused", in: body)
        #expect(chip.contains("FocusChip(text: MessagesFocusText.conversationChip)"), "이름 옆 '집중 중' 칩이 없다")
        #expect(body.contains("isFocused ? MessagesFocusText.accessibility : nil"), "보이스오버가 집중을 안 읽는다(children: .ignore)")
    }

    @Test("새 대화 시트: 사람 줄이 스토어 판정으로 '집중' 칩을 달고 보이스오버에 잇는다")
    func personRowShowsFocusChip() throws {
        let code = try Self.code("Sources/CheckMobileKit/Messages/MessagesNewConversationSheet.swift")
        let sheet = try Self.block(of: "struct MessagesNewConversationSheet: View", in: code)
        #expect(sheet.contains("let focused = store.focusedPeerIDs"), "시트가 잠금과 같은 출처(focusedPeerIDs)를 한 번 받지 않는다")
        #expect(sheet.contains("MessagesPersonRow(person: person, isFocused: focused.contains(person.userID))"),
                "사람 줄이 잠금과 다른 값(시트 명부 행)으로 칩을 고른다")
        #expect(!sheet.contains("isPeerFocused("), "줄마다 겹치기를 다시 한다(사람 수의 제곱)")
        // 당겨서 새로고침 · [다시 시도]는 명부 둘을 받는다 — 시트 명부만 받으면 지금 탭 옛 값이 칩을 덮는다(검토 2026-11-03).
        #expect(sheet.contains(".refreshable { store.refreshPeopleDirectories() }"), "당겨서 새로고침이 지금 탭 명부를 안 받는다")
        #expect(sheet.contains("action: { store.refreshPeopleDirectories() }"), "[다시 시도]가 지금 탭 명부를 안 받는다")
        #expect(!sheet.contains("loadDirectory(force: true)"), "시트가 메시지 명부만 다시 받는 길이 남았다")
        let row = try Self.block(of: "struct MessagesPersonRow: View", in: code)
        let body = try Self.block(of: "var body: some View", in: row)
        #expect(body.contains("chips: Self.chips(isFocused: isFocused)"), "이름 줄에 칩을 안 넘긴다")
        #expect(body.contains("isFocused ? MessagesFocusText.accessibility : nil"), "보이스오버가 집중을 안 읽는다")
        let chips = try Self.block(of: "static func chips(isFocused: Bool)", in: row)
        #expect(chips.contains(".focus(MessagesFocusText.personChip)"), "칩이 '집중' 보라 칩이 아니다")
    }

    @Test("집중의 출처는 스토어 한 곳이다: 판에는 집중 칸이 없고 · 화면은 focusedPeerIDs/isPeerFocused 만 읽는다(검토 2026-11-03 — 출처 두 벌)")
    func singleFocusSource() throws {
        let rules = try Self.code("Sources/CheckMobileKit/Messages/MessagesRules.swift")
        let board = try Self.block(of: "package struct MessagesPresenceBoard", in: rules)
        #expect(!board.contains("focused"), "판에 집중 칸이 다시 생겼다 — 잠금(focusedPeerIDs)과 다른 출처가 된다")
        let store = try Self.code("Sources/CheckMobileKit/Messages/MessagesStore.swift")
        // 겹치기 함수를 부르는 곳은 스토어에서 `focusedPeerIDs` 하나다(잠금 · 칩 · 시트가 모두 여기서 받는다).
        #expect(store.components(separatedBy: "MessagesFocusRules.focusedPeerIDs(").count - 1 == 1, "스토어가 겹치기를 두 군데서 한다")
        let isPeer = try Self.block(of: "package func isPeerFocused(", in: store)
        #expect(isPeer.contains("focusedPeerIDs.contains(peerID)"))
    }

    @Test("칩 부품: PersonName 의 .focus 가 FocusChip 한 조각을 부르고, 그 색은 aiToken 이다(맥 '집중' 칩과 같은 계열)")
    func focusChipComponent() throws {
        let code = try Self.code("Sources/CheckMobileKit/Components/PersonComponents.swift")
        let badges = try Self.block(of: "private var badges: some View", in: code)
        let focusCase = try #require(badges.range(of: "case .focus(let text):"))
        #expect(badges[focusCase.upperBound...].hasPrefix("\n                FocusChip(text: text)"), "PersonName 의 집중 칩이 FocusChip 을 안 부른다")
        let chip = try Self.block(of: "package struct FocusChip: View", in: code)
        #expect(chip.contains("MobileTheme.aiToken"), "집중 칩이 aiToken 보라가 아니다")
    }

    @Test("지금 탭 60초 틱이 메시지 스토어의 내 집중 재확인을 부른다(조건 판정은 메시지 스토어 한 곳)")
    func nowTickAsksMessagesStore() throws {
        let code = try Self.code("Sources/CheckMobileKit/Now/NowStore.swift")
        let timer = try Self.block(of: "private func armRefreshTimer()", in: code)
        #expect(timer.contains("self.context.links.messages?.refreshMyFocusModeIfFocused()"), "틱이 내 집중을 따라잡지 않는다")
        #expect(!timer.contains("fetchMyFocusMode"), "지금 탭이 조회를 직접 한다 — 주인이 둘이 된다")
    }

    @Test("폰은 집중을 쓰지 않는다: focus_mode PATCH 금지 칸 그대로 · 폰 소스에 집중 쓰기 호출 없음")
    func phoneNeverWritesFocus() throws {
        #expect(MobileForbiddenCalls.forbiddenProfileColumns.contains("focus_mode"))
        let offenders = try IntegrationContractTests.files(containing: ["updateFocusMode(", "ProfileFocusModeUpdateRequest"],
                                                           under: "Sources/CheckMobileKit")
        #expect(offenders.isEmpty, "폰 소스가 집중을 쓴다: \(offenders)")
    }

    // MARK: 도우미

    private static func code(_ relative: String) throws -> String {
        try IntegrationContractTests.code(relative)
    }

    /// 선언 머리부터 **중괄호가 닫히는 곳까지**(글자 수로 자르는 창은 다음 블록으로 샌다 — `V1012StickerViewContractTests.block` 과 같은 이유).
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

// MARK: - ⑩ 데모 픽스처

@MainActor
@Suite(.serialized) struct V1017FocusDemoFixtureTests {
    static let harin = "d0000000-0000-4000-8000-0000000000b5"
    static let doyun = "d0000000-0000-4000-8000-0000000000b4"

    @Test("명부 다섯 장: 모든 행에 focus_mode 칸 · 한 장에 한 명만 켜짐 · 메시지 쪽은 하린(민재 아님 — 민재 장면은 서버 거절을 보여 준다)")
    func directoryFixturesCarryFocusColumn() throws {
        let base = "Sources/CheckMobileKit/Demo/Fixtures/"
        let files: [(String, String)] = [
            ("messages/_messages/rpc.app_user_directory.json", Self.harin),
            ("messages/_messages-d0000000-0000-4000-8000-0000000000b1/rpc.app_user_directory.json", Self.harin),
            ("messages/_messages-d0000000-0000-4000-8000-0000000000b9/rpc.app_user_directory.json", Self.harin),
            ("messages/_messages-d0000000-0000-4000-8000-0000000000b4/rpc.app_user_directory.json", Self.harin),
            ("messages/_messages-d0000000-0000-4000-8000-0000000000b5/rpc.app_user_directory.json", Self.harin),
            ("now/_now/rpc.app_user_directory.json", "d0000000-0000-4000-8000-000000000102"),
            ("now/_now-teamless/rpc.app_user_directory.json", "d0000000-0000-4000-8000-000000000102"),
        ]
        for (relative, focused) in files {
            let data = try Data(contentsOf: FgFx.root.appendingPathComponent(base + relative))
            let rows = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]], "\(relative)")
            #expect(rows.allSatisfy { $0["focus_mode"] is Bool }, "\(relative): focus_mode 칸이 빠진 행이 있다(8칸 서버 모양이 아니다)")
            let on = rows.filter { ($0["focus_mode"] as? Bool) == true }.compactMap { $0["user_id"] as? String }
            #expect(on == [focused], "\(relative): \(on)")
            #expect(!on.contains(MessagesDemoFixtureTests.minjae), "\(relative): 민재를 켜면 입력칸 장면(서버 거절)이 미리 막힌다")
        }
    }

    @Test("목록 장면: 하린 한 명만 집중 · 민재 대화 장면은 미리 막히지 않는다(서버 target_focused 장면 그대로)")
    func listAndMinjaeScenes() async {
        let demo = await MessagesDemoFixtureTests.make(route: "messages")
        defer { demo.tearDown() }
        demo.store.loadDirectory(force: true)
        await demo.settle()
        #expect(demo.store.focusedPeerIDs == [Self.harin])
        #expect(demo.store.isPeerFocused(Self.harin))
        #expect(!demo.store.isPeerFocused(MessagesDemoFixtureTests.minjae))
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)

        let minjae = await MessagesDemoFixtureTests.make(route: "messages/\(MessagesDemoFixtureTests.minjae)")
        defer { minjae.tearDown() }
        minjae.store.conversationDidAppear(peerID: MessagesDemoFixtureTests.minjae, token: UUID())
        await minjae.settle()
        #expect(await baseWaitUntil { !minjae.store.isFetchingMyFocusMode })
        #expect(minjae.store.myFocusMode == false, "기본 내 집중 픽스처(false)에 안 닿는다")
        #expect(minjae.store.focusBlock(for: MessagesDemoFixtureTests.minjae) == nil)
    }

    @Test("상대 집중 장면(하린): 대화는 열리고 '집중 중' · 글·이모티콘 잠금 · 사유는 target_focused · 요청 0")
    func peerFocusScene() async {
        let demo = await MessagesDemoFixtureTests.make(route: "messages/\(Self.harin)")
        defer { demo.tearDown() }
        demo.store.conversationDidAppear(peerID: Self.harin, token: UUID())
        await demo.settle()
        #expect(await baseWaitUntil { demo.store.directoryLoaded && !demo.store.isFetchingMyFocusMode })
        #expect(demo.store.peerName(for: Self.harin) == "하린")
        #expect(demo.store.myFocusMode == false)
        #expect(demo.store.isPeerFocused(Self.harin))
        #expect(demo.store.focusBlock(for: Self.harin) == .peer)
        #expect(!demo.store.canSendSticker(to: Self.harin))
        #expect(!demo.store.sendSticker(.joy, to: Self.harin))
        await demo.settle()
        #expect(!demo.requests.contains { $0.rpcName == "send_message" })
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }

    @Test("내 집중 장면(도윤): 장면 픽스처가 내 집중 true → 사유는 sender_focused('맥에서 집중을 끄면') · 요청 0")
    func myFocusScene() async {
        let demo = await MessagesDemoFixtureTests.make(route: "messages/\(Self.doyun)")
        defer { demo.tearDown() }
        demo.store.conversationDidAppear(peerID: Self.doyun, token: UUID())
        await demo.settle()
        #expect(await baseWaitUntil { demo.store.myFocusMode == true && !demo.store.isFetchingMyFocusMode })
        #expect(!demo.store.isPeerFocused(Self.doyun))
        #expect(demo.store.focusBlock(for: Self.doyun) == .myself)
        #expect(demo.store.focusBlock(for: Self.doyun)?.notice == MessageNoticeText.senderFocused)
        #expect(!demo.store.canSendSticker(to: Self.doyun))
        #expect(!demo.requests.contains { $0.rpcName == "send_message" })
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }
}
