import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.34 — 맥 차단·신고(2026-09-20).
//
// 사용자 요청: "신고같은거 모바일에 추가되었잖아. 그럼 맥에도 추가되어야 하는거 아니야? 신고, 차단 이런거"
//
// 이 스위트가 재는 것(SPEC §3):
//  ① 확인 없이 차단 안 됨(런타임 + 소스 — 차단 왕복은 `private`, 부르는 문은 확인 시트 하나)
//  ② 사유 없이 신고 안 됨 · 200자(코드포인트 — NFD 로 들어와도 200)
//  ③ 낙관적 제거(콕 찌르기 목록 · 열린 대화 · 오목 로비 · 받은 신청 · 배너)와 실패 되돌림
//  ④ 해제 · ⑤ 404(PGRST202) = "아직" · ⑥ 세대 가드(로그아웃 중 늦은 응답)
//  ⑦ 우클릭 메뉴는 받은 말풍선에만 · ⑧ 오목 AI 판엔 메뉴 없음
//  ⑨ 폰과 맥이 같은 문구 원천을 읽는다(소스 계약) · ⑩ 렌더(시트가 팝오버 높이 상한 안 · 노란 상자 없음)
//
// 네트워크는 `MessageReadStubProtocol`(V0330 — 호스트별 스크립트 · 요청 기록)을 쓴다. 스크립트하지 않은 RPC 는 200 `[]` 이다.
// ★ 픽스처 본문은 전부 **합성 문자열**이다. 실제 대화·신고 글을 옮겨 오지 마라(퍼블릭 저장소).

private let brPeerA = MessageReadFixture.peerA
private let brPeerB = MessageReadFixture.peerB

@MainActor
private func brStore(
    _ label: String,
    handler: @escaping MessageReadStubProtocol.Handler = { _, _ in nil }
) -> (store: WorkTimerStore, host: String) {
    makeMessageReadStore("br-\(label)") { call, index in
        if let reply = handler(call, index) { return reply }
        // 콕 찌르기 목록은 두 사람(대화를 닫으면 목록이 다시 받아진다 — 기본 `[]` 이면 대조가 무너진다).
        if call.rpc == "app_user_directory" {
            return MessageReadStubProtocol.Reply(body: brDirectoryJSON)
        }
        return nil
    }
}

private let brDirectoryJSON = MessageReadFixture.json([
    ["user_id": brPeerA, "display_name": "소라", "avatar_url": NSNull(), "is_working": true],
    ["user_id": brPeerB, "display_name": "도윤", "avatar_url": NSNull(), "is_working": false],
])

private func brUser(_ id: String, _ name: String) -> GomokuUser {
    GomokuUser(id: id, displayName: name, avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: false)
}

private func brMatch(id: String, opponent: GomokuUser) -> GomokuMatchState {
    GomokuMatchState(
        id: id, stake: 3, myColor: .black, opponent: opponent, board: GomokuBoard(),
        lastMove: nil, moveCount: 0, turn: .black, deadline: nil, isFinished: false, outcome: nil,
        endReason: nil, rubyDelta: nil, blackPassed: false
    )
}

private func brEntry(id: String, peer: String, isMine: Bool, body: String = "합성 문장") -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id, peerUserID: peer, peerName: "소라", peerAvatarURL: nil, body: body,
        createdAt: MessageReadFixture.now, isMine: isMine
    )
}

/// 스토어가 띄운 차단·신고 Task 가 끝날 때까지(부정형 단언 앞) — 재개 횟수 상한(V0330 `messageReadWait` 와 같은 해법).
@MainActor
private func brDrain() async {
    for _ in 0..<60 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - ① 확인 없이 차단 안 됨

@MainActor
@Suite(.serialized) struct V0334BlockReportStoreTests {
    @Test(.gomokuDefaultsCleanup)
    func 확인_시트를_지나지_않으면_차단이_나가지_않는다() async {
        let (store, host) = brStore("confirm")
        let target = BlockReportTarget(peerID: brPeerA, peerName: "소라")

        // 시트 없이 [차단하기] 문을 두드린다 — 아무 일도 없다.
        store.confirmBlockFromSheet()
        // 메뉴는 시트를 **열기만** 한다(왕복 · 숨김 없음).
        store.openBlockConfirm(target, surface: .message)
        #expect(store.blockReportSheet?.kind == .blockConfirm)
        #expect(store.blockHiddenPeerIDs.isEmpty, "시트를 열었을 뿐인데 걷어냈다")
        // 신고 시트가 떠 있을 때 [차단하기] 문 — 차단 확인이 아니므로 아무 일도 없다.
        store.openReport(target, surface: .message)
        store.confirmBlockFromSheet()
        #expect(store.blockReportSheet?.kind == .report, "신고 시트가 차단 문에 닫혔다")
        #expect(store.blockHiddenPeerIDs.isEmpty)
        await brDrain()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "block_user") == 0, "확인 없이 차단이 나갔다")

        // 확인을 지나면 정확히 한 번 · 그 사람 id 로.
        store.openBlockConfirm(target, surface: .message)
        store.confirmBlockFromSheet()
        #expect(store.blockReportSheet == nil, "[차단하기] 뒤에도 시트가 떠 있다")
        await messageReadWait { store.blockingPeerID == nil }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "block_user") == 1)
        #expect(MessageReadStubProtocol.calls(host: host, rpc: "block_user").first?.json["p_user"] as? String == brPeerA)

        // 나 자신에게는 시트조차 안 열린다(서버도 거절하지만 문을 열 이유가 없다).
        store.openBlockConfirm(BlockReportTarget(peerID: MessageReadFixture.me, peerName: "나"), surface: .message)
        #expect(store.blockReportSheet == nil)
    }

    // MARK: ② 사유 · 200자

    @Test(.gomokuDefaultsCleanup)
    func 사유가_없거나_200자를_넘으면_신고가_나가지_않고_딱_200자는_나간다() async throws {
        let (store, host) = brStore("report-guards") { call, _ in
            call.rpc == "report_content" ? MessageReadStubProtocol.Reply(body: "null") : nil
        }
        let target = BlockReportTarget(peerID: brPeerA, peerName: "소라")
        #expect(store.sendReportFromSheet() == nil, "시트 없이 신고가 나갔다")

        store.openReport(target, surface: .message)
        #expect(store.reportAlsoBlock, "'신고하면서 차단' 이 기본 켬이 아니다")
        #expect(!store.canSubmitReportNow, "사유 없이 [신고 보내기]가 눌린다")
        #expect(store.sendReportFromSheet() == nil)
        #expect(store.reportNotice == BlockReportText.reportReasonRequired, "왜 막혔는지 말하지 않는다")

        store.selectReportReason(.harassment)
        #expect(store.reportNotice == nil, "사유를 골랐는데 '사유를 골라 주세요' 가 남았다")
        store.reportDetailDraft = String(repeating: "가", count: 201)
        #expect(!store.canSubmitReportNow)
        #expect(store.sendReportFromSheet() == nil)
        #expect(store.reportNotice?.contains("200자") == true)
        await brDrain()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "report_content") == 0, "막았어야 할 신고가 나갔다")

        // 딱 200자 — NFD 로 들어와도 서버(char_length) 눈금으로 200이라 나간다.
        store.reportDetailDraft = String(repeating: "가", count: 200).decomposedStringWithCanonicalMapping
        #expect(store.canSubmitReportNow)
        let task = try #require(store.sendReportFromSheet())
        #expect(store.isSendingReport)
        store.closeBlockReportSheet()
        #expect(store.blockReportSheet != nil, "보내는 중에 시트가 닫혔다 — 결과가 어디로도 안 간다")
        #expect(await task.value)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "report_content") == 1)
        let body = MessageReadStubProtocol.calls(host: host, rpc: "report_content").first?.json ?? [:]
        #expect(body["p_target"] as? String == brPeerA)
        #expect(body["p_reason"] as? String == "harassment")
        #expect((body["p_detail"] as? String)?.unicodeScalars.count == 200)
        // 키를 빼지 않고 null 을 싣는다(PostgREST 는 키 집합으로 함수를 고른다 — 빠지면 PGRST202).
        #expect(body["p_message_id"] is NSNull, "사람 신고에 메시지 칸이 빠졌거나 값이 실렸다: \(body)")
        #expect(body["p_block"] as? Bool == true)
        #expect(store.blockReportSheet == nil)
        #expect(store.blockReportNotice == BlockReportNotice(text: BlockReportText.reportSentNotice, isError: false, surface: .message))
        #expect(store.blockHiddenPeerIDs.contains(brPeerA), "차단까지 켜고 보냈는데 걷어내지 않았다")
        #expect(store.reportDetailDraft.isEmpty, "보낸 글이 초안에 남았다 — 다음 신고에 또 실린다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 받은_말풍선_신고는_그_메시지_id_를_싣고_차단을_끄면_걷어내지_않는다() async throws {
        let (store, host) = brStore("report-message") { call, _ in
            call.rpc == "report_content" ? MessageReadStubProtocol.Reply(body: "null") : nil
        }
        let target = try #require(MessageBubbleReportRule.target(for: brEntry(id: "m-7", peer: brPeerA, isMine: false)))
        store.openReport(target, surface: .message)
        store.selectReportReason(.spam)
        store.reportDetailDraft = "   \n "
        store.reportAlsoBlock = false
        let task = try #require(store.sendReportFromSheet())
        #expect(await task.value)
        let body = MessageReadStubProtocol.calls(host: host, rpc: "report_content").first?.json ?? [:]
        #expect(body["p_message_id"] as? String == "m-7", "메시지 신고에 그 메시지 id 가 안 실렸다: \(body)")
        #expect(body["p_detail"] is NSNull, "빈 자유 입력이 빈 글로 실렸다(null 이어야 운영자가 안 헷갈린다)")
        #expect(body["p_block"] as? Bool == false)
        #expect(store.blockHiddenPeerIDs.isEmpty, "차단을 끄고 신고했는데 걷어냈다")
    }

    // MARK: ③ 낙관적 제거 · 실패 되돌림

    @Test(.gomokuDefaultsCleanup)
    func 차단은_서버를_기다리지_않고_걷어내고_실패하면_되돌린다() async {
        let gate = MessageReadStubGate()
        let (store, host) = brStore("optimistic") { call, _ in
            call.rpc == "block_user"
                ? MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#, gate: gate) : nil
        }
        store.pokeDirectory = [
            PokeDirectoryEntry(userID: brPeerA, name: "소라", avatarURL: nil, isWorking: true),
            PokeDirectoryEntry(userID: brPeerB, name: "도윤", avatarURL: nil, isWorking: false),
        ]
        store.pokeDirectoryLoaded = true
        store.gomoku.users = [brUser(brPeerA, "소라"), brUser(brPeerB, "도윤")]
        store.gomoku.incoming = [
            GomokuInvite(id: "invite-a", peer: brUser(brPeerA, "소라"), stake: 3,
                         expiresAt: MessageReadFixture.now.addingTimeInterval(50))
        ]
        store.openMessagePanel(peer: brPeerA)
        // 대조: 차단 전에는 다 서 있다(아래 단언이 늘 참인 채로 초록이 되지 않게).
        #expect(store.visiblePokeDirectory.map(\.userID) == [brPeerA, brPeerB])
        #expect(store.gomoku.visibleUsers.count == 2)
        #expect(store.gomoku.bannerInvite?.id == "invite-a")
        #expect(store.isMessagePanelVisible)

        store.openBlockConfirm(BlockReportTarget(peerID: brPeerA, peerName: "소라"), surface: .message)
        store.confirmBlockFromSheet()
        // 응답 **전에** 이미 사라졌다 — 목록 · 열린 대화 · 오목 로비 · 받은 신청 · 배너.
        #expect(store.visiblePokeDirectory.map(\.userID) == [brPeerB], "콕 찌르기 목록에 그대로 서 있다")
        #expect(!store.isMessagePanelVisible, "차단한 사람과의 대화가 그대로 떠 있다")
        #expect(store.isPokePanelVisible, "결과를 볼 자리(콕 찌르기 목록)로 안 갔다")
        #expect(store.gomoku.visibleUsers.map(\.id) == [brPeerB], "오목 로비에 [도전]과 함께 그대로 서 있다")
        #expect(store.gomoku.visibleIncoming.isEmpty && store.gomoku.bannerInvite == nil, "받은 신청·배너가 남았다")
        #expect(store.gomoku.pendingIncomingInvites.isEmpty, "메뉴바 점의 재료가 남았다")
        // 원본은 서버가 답한 그대로다(실패하면 숨김만 풀면 돌아온다).
        #expect(store.pokeDirectory.count == 2 && store.gomoku.users.count == 2)

        gate.open()
        await messageReadWait { store.blockingPeerID == nil }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "block_user") == 1)
        #expect(store.blockHiddenPeerIDs.isEmpty, "실패했는데 걷어낸 채다")
        #expect(store.visiblePokeDirectory.map(\.userID) == [brPeerA, brPeerB], "실패했는데 목록에 안 돌아왔다")
        #expect(store.gomoku.visibleUsers.count == 2 && store.gomoku.bannerInvite?.id == "invite-a")
        let notice = store.blockReportNotice(on: .message)
        #expect(notice?.isError == true)
        #expect(notice?.text.contains(BlockReportText.checkConnection) == true, "왜 안 됐는지 말하지 않는다: \(notice?.text ?? "nil")")
        #expect(store.blockReportNotice(on: .gomoku) == nil, "팝오버에서 건 차단의 결과가 오목 창에도 선다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 오목_채팅에서_차단하면_그_판의_채팅을_끄고_판은_그대로다() async throws {
        let (store, host) = brStore("gomoku-mute") { call, _ in
            switch call.rpc {
            case "block_user": return MessageReadStubProtocol.Reply(body: "null")
            case "gomoku_chat_mute":
                return MessageReadStubProtocol.Reply(body: MessageReadFixture.json(["status": "ok", "muted": true]))
            default: return nil
            }
        }
        let opponent = brUser(brPeerA, "소라")
        store.gomoku.match = brMatch(id: "11111111-2222-3333-4444-555555555555", opponent: opponent)
        store.gomoku.phase = .playing
        let target = try #require(GomokuChatSafetyRule.target(for: store.gomoku))
        store.openBlockConfirm(target, surface: .gomoku)
        #expect(store.blockReportSheet(on: .gomoku) != nil)
        #expect(store.blockReportSheet(on: .message) == nil, "오목 창에서 연 시트가 팝오버 대화 자리에도 선다")
        store.confirmBlockFromSheet()
        await messageReadWait { store.blockingPeerID == nil && !store.gomoku.isSendingChat }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_chat_mute") == 1, "차단했는데 그 판의 채팅을 안 껐다")
        #expect(MessageReadStubProtocol.calls(host: host, rpc: "gomoku_chat_mute").first?.json["p_muted"] as? Bool == true)
        // 판 자체는 건드리지 않는다(판돈이 걸려 있다) — 기권·나가기가 한 건도 안 나간다.
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_resign") == 0, "차단이 기권을 불렀다")
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_leave") == 0, "차단이 판을 나갔다")
    }

    // MARK: ④ 해제

    @Test(.gomokuDefaultsCleanup)
    func 차단_목록을_받고_해제하면_그_줄과_숨김이_풀린다() async {
        let (store, host) = brStore("unblock") { call, _ in
            switch call.rpc {
            case "list_blocks":
                return MessageReadStubProtocol.Reply(body: MessageReadFixture.json([
                    ["user_id": brPeerA, "display_name": "소라", "avatar_url": NSNull(), "created_epoch": 1_789_621_000]
                ]))
            case "unblock_user": return MessageReadStubProtocol.Reply(body: "null")
            default: return nil
            }
        }
        store.blockHiddenPeerIDs = [brPeerA]
        #expect(store.gomoku.hiddenPeerIDs == [brPeerA], "숨김이 오목 스토어에 안 비친다")
        store.openBlockedPeopleSettings()
        #expect(store.showsBlockedPeopleInSettings)
        await messageReadWait { store.blocksLoaded }
        #expect(store.blockedPeople.map(\.userID) == [brPeerA])
        #expect(store.blockedPeople.first?.name == "소라")
        #expect(store.blockedPeople.first?.blockedAt != nil)
        #expect(BlockedPeoplePageState.of(loaded: store.blocksLoaded, loading: store.blocksLoading,
                                          failed: store.blocksFailed, count: store.blockedPeople.count) == .list)

        store.unblock(brPeerA)
        await messageReadWait { store.unblockingUserIDs.isEmpty }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "unblock_user") == 1)
        #expect(MessageReadStubProtocol.calls(host: host, rpc: "unblock_user").first?.json["p_user"] as? String == brPeerA)
        #expect(store.blockedPeople.isEmpty)
        #expect(store.blockHiddenPeerIDs.isEmpty && store.gomoku.hiddenPeerIDs.isEmpty, "풀었는데 계속 숨어 있다")
        #expect(BlockedPeoplePageState.of(loaded: store.blocksLoaded, loading: store.blocksLoading,
                                          failed: store.blocksFailed, count: store.blockedPeople.count) == .empty,
                "0명인데 빈 상태 문구가 아니다")

        store.closeBlockedPeopleSettings()
        #expect(!store.showsBlockedPeopleInSettings)
    }

    @Test(.gomokuDefaultsCleanup)
    func 해제가_실패하면_줄은_그대로이고_이유를_말한다() async {
        let (store, _) = brStore("unblock-fail") { call, _ in
            switch call.rpc {
            case "list_blocks":
                return MessageReadStubProtocol.Reply(body: MessageReadFixture.json([
                    ["user_id": brPeerA, "display_name": "소라", "avatar_url": NSNull()]
                ]))
            case "unblock_user": return MessageReadStubProtocol.Reply(status: 400, body: #"{"message":"no"}"#)
            default: return nil
            }
        }
        store.openBlockedPeopleSettings()
        await messageReadWait { store.blocksLoaded }
        #expect(store.blockedPeople.first?.blockedAt == nil, "모르는 시각을 지어냈다")
        store.unblock(brPeerA)
        await messageReadWait { store.unblockingUserIDs.isEmpty }
        #expect(store.blockedPeople.map(\.userID) == [brPeerA])
        #expect(store.blockedListNotice?.contains("다시 시도") == true)
    }

    // MARK: ⑤ 404 = 아직

    @Test(.gomokuDefaultsCleanup)
    func 서버가_아직_모르면_고장이_아니라_아직이라고_말한다() async throws {
        let (store, _) = brStore("not-ready") { call, _ in
            ["block_user", "list_blocks", "report_content"].contains(call.rpc)
                ? MessageReadFixture.missingFunction(call.rpc) : nil
        }
        let target = BlockReportTarget(peerID: brPeerA, peerName: "소라")
        store.openBlockConfirm(target, surface: .message)
        store.confirmBlockFromSheet()
        await messageReadWait { store.blockingPeerID == nil }
        #expect(store.blockHiddenPeerIDs.isEmpty)
        #expect(store.blockReportNotice?.text == BlockReportText.serverNotReady)

        store.openBlockedPeopleSettings()
        await messageReadWait { store.blocksLoaded }
        #expect(store.blocksServerNotReady)
        #expect(!store.blocksFailed, "'아직' 을 '고장' 으로 말한다")
        #expect(BlockedPeoplePageState.of(loaded: store.blocksLoaded, loading: store.blocksLoading,
                                          failed: store.blocksFailed, count: store.blockedPeople.count) == .empty)

        store.openReport(target, surface: .message)
        store.selectReportReason(.other)
        store.reportDetailDraft = "합성 설명"
        let task = try #require(store.sendReportFromSheet())
        #expect(await task.value == false)
        #expect(store.reportNotice == BlockReportText.serverNotReady)
        #expect(store.blockReportSheet?.kind == .report, "실패했는데 시트가 닫혔다 — 쓴 글이 사라진다")
        #expect(store.reportDetailDraft == "합성 설명")
    }

    // MARK: ⑥ 세대 가드

    @Test(.gomokuDefaultsCleanup)
    func 로그아웃_뒤에_도착한_차단_신고_응답은_다음_계정을_건드리지_않는다() async throws {
        let blockGate = MessageReadStubGate()
        let reportGate = MessageReadStubGate()
        let (store, host) = brStore("generation") { call, _ in
            switch call.rpc {
            case "block_user":
                return MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"late"}"#, gate: blockGate)
            case "report_content": return MessageReadStubProtocol.Reply(body: "null", gate: reportGate)
            default: return nil
            }
        }
        store.openBlockConfirm(BlockReportTarget(peerID: brPeerA, peerName: "소라"), surface: .message)
        store.confirmBlockFromSheet()
        store.openReport(BlockReportTarget(peerID: brPeerB, peerName: "도윤"), surface: .message)
        store.selectReportReason(.spam)
        let report = try #require(store.sendReportFromSheet())
        await messageReadWait {
            MessageReadStubProtocol.count(host: host, rpc: "block_user") == 1
                && MessageReadStubProtocol.count(host: host, rpc: "report_content") == 1
        }
        #expect(store.blockHiddenPeerIDs == [brPeerA])

        // 로그아웃 → 다른 계정. 다음 계정은 자기가 차단한 사람이 따로 있다.
        store.clearPersistedSession()
        #expect(store.blockHiddenPeerIDs.isEmpty && store.blockReportSheet == nil && !store.isSendingReport,
                "로그아웃이 차단·신고 상태를 안 비웠다")
        store.session = SupabaseSession(accessToken: "access-next", refreshToken: nil,
                                        userID: "00000000-0000-0000-0000-0000000334ff")
        store.blockHiddenPeerIDs = [brPeerB]

        blockGate.open()
        reportGate.open()
        #expect(await report.value == false, "앞 계정의 신고 성공이 다음 계정에 반영됐다")
        await brDrain()
        #expect(store.blockHiddenPeerIDs == [brPeerB], "앞 계정의 늦은 응답이 다음 계정의 숨김을 바꿨다")
        #expect(store.blockReportNotice == nil, "앞 계정의 결과 문구가 다음 계정 화면에 섰다")
        #expect(store.reportNotice == nil)
        #expect(!store.isSendingReport)
    }
}

// MARK: - ⑦ 우클릭 · ⑧ 오목 AI · ⑨ 한 벌 (순수 + 소스 계약)

@MainActor
@Suite struct V0334BlockReportContractTests {
    @Test func 우클릭_신고는_받은_말풍선에만_선다() throws {
        let mine = brEntry(id: "m-mine", peer: brPeerA, isMine: true)
        let received = brEntry(id: "m-in", peer: brPeerA, isMine: false, body: "합성 받은 말")
        #expect(!MessageBubbleReportRule.offersReport(for: mine), "내 말풍선에 신고가 선다")
        #expect(MessageBubbleReportRule.target(for: mine) == nil)
        #expect(MessageBubbleReportRule.offersReport(for: received))
        let target = try #require(MessageBubbleReportRule.target(for: received))
        #expect(target.peerID == brPeerA && target.messageID == "m-in" && target.messageBody == "합성 받은 말")

        let view = try brSource("CheckMessageView.swift")
        // 대화 뷰가 **판정 한 곳**으로 거른 뒤에만 행에 신고를 넘긴다.
        #expect(view.contains("onReport: MessageBubbleReportRule.offersReport(for: entry) ? onReport.map"),
                "받은 말풍선만 고르는 판정을 대화 뷰가 안 지난다")
        let row = try #require(brRegion(view, from: "private struct MessageBubbleRow: View {", to: "// MARK: - 입력줄"))
        let guardRange = try #require(row.range(of: "if let onReport {"))
        let menuRange = try #require(row.range(of: ".contextMenu {"), "말풍선에 우클릭 메뉴가 없다")
        #expect(guardRange.lowerBound < menuRange.lowerBound, "우클릭 메뉴가 신고 갈래 밖에도 붙는다(내 말풍선에도 선다)")
        #expect(row.contains("BlockReportText.reportMessageAction"))
        #expect(row.contains(".textSelection(.enabled)"), "내 말풍선의 글자 선택이 사라졌다")
        #expect(row.components(separatedBy: ".contextMenu {").count - 1 == 1)
    }

    @Test func 오목_채팅의_신고_차단은_사람과_두는_판에만_선다() throws {
        let gomoku = GomokuStore()
        #expect(GomokuChatSafetyRule.target(for: gomoku) == nil, "판이 없는데 신고 대상이 있다")
        gomoku.match = brMatch(id: "\(GomokuAIGame.idPrefix)practice", opponent: brUser("ai", "AI"))
        #expect(GomokuChatSafetyRule.target(for: gomoku) == nil, "AI 연습 판에 신고·차단이 선다")
        gomoku.match = brMatch(id: "11111111-2222-3333-4444-555555555555", opponent: brUser(brPeerA, "소라"))
        let target = try #require(GomokuChatSafetyRule.target(for: gomoku))
        #expect(target.peerID == brPeerA)
        #expect(target.messageID == nil, "대국 채팅 줄 id 를 1:1 메시지 칸에 싣는다(운영자가 못 찾는 행이다)")

        let panel = try brSource("GomokuPanel.swift")
        let card = try #require(brRegion(panel, from: "private struct GomokuChatCard: View {", to: "private struct GomokuChatBubble: View {"))
        #expect(card.contains("GomokuChatSafetyRule.target(for: store)"), "채팅 카드가 AI 판 판정을 안 지난다")
        #expect(card.contains("BlockReportMoreButton {"), "오목 채팅에 ··· 가 없다")
        #expect(card.contains("safety.openReport(target, surface: .gomoku)") && card.contains("safety.openBlockConfirm(target, surface: .gomoku)"))
        #expect(!card.contains("confirmBlockFromSheet"), "채팅 카드가 확인 없이 차단한다")
        // 오목 화면 금지 목록(노란 상자)은 그대로다 — ··· 는 AppKit 팝업이라 그 자리를 그리지 않는다.
        #expect(!panel.contains("Menu("), "오목 화면에 Menu( 가 생겼다")
        // 덮개는 같은 시트 뷰를 쓴다(문구·사유가 두 벌이 되지 않게).
        #expect(panel.contains("BlockReportSheetView(store: safety, sheet: sheet"))
    }

    @Test func 차단을_부르는_문은_확인_시트_하나다() throws {
        let blocks = try brSource("WorkTimerStoreBlocks.swift")
        #expect(blocks.contains("private func blockPeer("), "차단 왕복이 밖으로 열렸다")
        #expect(blocks.components(separatedBy: "blockPeer(").count - 1 == 2, "차단 왕복을 부르는 자리가 하나가 아니다")
        let confirm = try #require(brRegion(blocks, from: "func confirmBlockFromSheet()", to: "private func blockPeer("))
        #expect(confirm.contains("sheet.kind == .blockConfirm"), "확인 시트가 아니어도 차단한다")
        #expect(confirm.contains("blockPeer(sheet.target"))

        // 앱 전체에서 [차단하기] 문을 부르는 자리는 시트 뷰 하나다(메뉴·우클릭은 시트를 열기만 한다).
        var callers: [String] = []
        for (name, code) in try brMacSources() {
            let calls = code.components(separatedBy: "confirmBlockFromSheet(").count - 1
                - (code.components(separatedBy: "func confirmBlockFromSheet(").count - 1)
            if calls > 0 { callers.append("\(name)×\(calls)") }
        }
        #expect(callers == ["CheckBlockReportViews.swift×1"], "확인 시트 밖에서 차단한다: \(callers)")

        // 신고를 보내는 곳도 시트 하나 — 그리고 조합 확정 문을 먼저 지난다(한글 마지막 음절).
        let views = try brSource("CheckBlockReportViews.swift")
        #expect(views.contains("CheckEditorSend.commitThenSend { store.sendReportFromSheet() }"),
                "신고 전송이 조합 확정 문을 안 지난다 — 마지막 음절이 빠진 채 나간다")
        #expect(views.contains("action: submitTapped"))
        var reporters: [String] = []
        for (name, code) in try brMacSources() where code.contains("sendReportFromSheet(") {
            if !code.contains("func sendReportFromSheet(") { reporters.append(name) }
        }
        #expect(reporters == ["CheckBlockReportViews.swift"], "신고를 보내는 화면이 늘었다: \(reporters)")
        // 로그로 새지 않는다(사람이 쓴 문장).
        for code in [blocks, views] {
            #expect(!code.contains("print(") && !code.contains("Logger("), "차단·신고 경로에 로그가 붙었다")
        }
    }

    @Test func 폰과_맥이_같은_문구_원천을_읽는다() throws {
        // 사실 문장은 저장소 전체(맥 · 폰 · 코어)의 **코드**에서 한 파일에만 글자로 있다 — 두 벌이면 한쪽이 언젠가 갈린다.
        let facts = [
            "접수한 신고는 24시간 안에 확인합니다", "서로 메시지를 주고받을 수 없어요", "순위판·팀 현황의 이름은 그대로 남아요",
            "신고를 접수했어요", "사유를 골라 주세요", "신고하면서 차단하기", "무슨 일이 있었는지 적어 주세요",
            "이 메시지 신고하기", "차단한 사람이 없어요", "이 기능이 아직 서버에 준비되지 않았어요",
        ]
        // 한 번만 읽는다(소스 전부를 주석 걷어 읽는 일이라 사실마다 다시 읽으면 메인 액터를 몇 초 붙든다).
        let sources = try brAllSources()
        for fact in facts {
            let files = sources.filter { $0.code.contains(fact) }.map(\.path)
            #expect(files == ["Sources/CheckCore/BlockReportRules.swift"], "'\(fact)' 가 코어 밖에도 있다: \(files)")
        }
        // 두 화면이 같은 표를 부른다.
        for (path, name) in [("Sources/check", "CheckBlockReportViews.swift"), ("Sources/check", "CheckMessageView.swift"),
                             ("Sources/CheckMobileKit/Messages", "MessagesBlockSheets.swift"),
                             ("Sources/CheckMobileKit/Me", "MeBlockedPeopleView.swift")] {
            let code = try brStripComments(String(contentsOf: CheckCoreSourceLayout.repoRoot
                .appendingPathComponent("\(path)/\(name)"), encoding: .utf8))
            #expect(code.contains("BlockReportText."), "\(name) 가 코어 문구 표를 안 읽는다")
        }
        #expect(sources.filter { $0.code.contains("enum MessagesBlockText") || $0.code.contains("enum MessagesBlockRules") }.isEmpty,
                "폰 모듈에 옛 표가 다시 생겼다")

        // 길 안내만 갈린다 — 맥은 [나] 탭이 없다.
        #expect(WorkTimerStore.blockReportPlatform == .mac)
        #expect(BlockReportText.blockConfirmUndoNote(.mac) == "설정 → 차단한 사람에서 언제든 풀 수 있어요.")
        #expect(!BlockReportText.blockConfirmUndoNote(.mac).contains("나 →"))
        #expect(!BlockReportText.blockedListLede(.mac).contains("사람 찾기"), "맥에 없는 표면 이름을 말한다")
        // 맥 확인 시트: 막히는 것 — 메시지 · 콕/울트라 찌르기 · 콕 찌르기 목록(사람 찾기) · 오목 신청.
        let mac = BlockReportText.blockConfirmItems(.mac)
        #expect(mac.count == 3 && mac.first == BlockReportText.blockedMessagesFact)
        for word in ["메시지", "콕 찌르기", "울트라", "오목 신청", "콕 찌르기 목록"] {
            #expect(mac.joined(separator: " ").contains(word), "맥 확인 시트가 '\(word)' 를 말하지 않는다")
        }
        #expect(BlockReportText.blockConfirmScopeNote.contains("순위판"))
        // 사유 넷은 폰 시트와 같은 표(코어 `ContentReportReason`)다.
        #expect(ContentReportReason.allCases.map(\.label) == ["스팸", "욕설·괴롭힘", "부적절한 내용", "기타"])
        #expect(ContentReportDetail.maxLength == 200)
    }

    @Test func 설정에_차단한_사람이_있고_목록은_본문_자리를_바꾼다() throws {
        let settings = try brSource("CheckSettingsView.swift")
        #expect(settings.contains("BlockedPeopleSettingsEntryRow(store: store)"), "설정에 [차단한 사람] 행이 없다")
        #expect(settings.contains("if store.showsBlockedPeopleInSettings {") && settings.contains("CheckBlockedPeopleSettingsPage(store: store)"))
        let window = try brSource("CheckSettingsWindow.swift")
        #expect(window.components(separatedBy: "closeBlockedPeopleSettings()").count - 1 == 2,
                "창을 닫아도 [차단한 사람] 쪽이 남는다(다시 열면 설정 본문이 아니다)")
        // 네 상태 — 빈 목록과 로드 전·실패를 가른다.
        #expect(BlockedPeoplePageState.of(loaded: false, loading: true, failed: false, count: 0) == .loading)
        #expect(BlockedPeoplePageState.of(loaded: false, loading: false, failed: true, count: 0) == .failed)
        #expect(BlockedPeoplePageState.of(loaded: true, loading: false, failed: false, count: 0) == .empty)
        #expect(BlockedPeoplePageState.of(loaded: true, loading: true, failed: false, count: 2) == .list)
    }
}

// MARK: - ⑩ 렌더

/// 팝오버 높이 상한(pt). 넘으면 푸터(로그아웃/앱 종료)가 화면 밖으로 잘린다.
private let brPopoverCap: Double = 700

/// 팝오버가 얹을 수 있는 **가장 큰 크롬**(새 버전 배너 + 노트 4줄 149pt + 목표 편집 92pt = 241pt — V0249 와 같은 재료).
private let brWorstNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

@MainActor
@Suite(.serialized) struct V0334BlockReportRenderTests {
    @MainActor
    private func popoverStore(_ label: String) -> WorkTimerStore {
        let (store, _) = brStore(label)
        store.isMenuPresented = true
        store.displayNow = MessageReadFixture.now
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.teamName = "아잉팀"
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
        store.pokeDirectory = [PokeDirectoryEntry(userID: brPeerA, name: "소라", avatarURL: nil, isWorking: true)]
        store.pokeDirectoryLoaded = true
        store.messageHistory = [
            brEntry(id: "r1", peer: brPeerA, isMine: false, body: "합성 받은 말 — 조금 길게 써서 두 줄이 되게 한다"),
            brEntry(id: "s1", peer: brPeerA, isMine: true, body: "합성 보낸 말"),
        ]
        store.messageHistoryLoaded = true
        store.openMessagePanel(peer: brPeerA)
        return store
    }

    private func bitmap(_ store: WorkTimerStore, worstChrome: Bool) throws -> NSBitmapImageRep {
        let view = CheckMenuView(
            store: store,
            previewClipsOverflowList: true,
            previewGoalEditing: worstChrome,
            previewUpdateBanner: worstChrome,
            previewUpdateNotes: worstChrome ? brWorstNotes : [],
            previewPlainTextEditors: true
        )
        return try brRender(view)
    }

    @Test(.gomokuDefaultsCleanup)
    func 신고_시트와_차단_확인이_팝오버_높이_상한_안에_선다() throws {
        for worst in [false, true] {
            let conversation = try bitmap(popoverStore("render-conv-\(worst)"), worstChrome: worst)
            brSave(conversation, name: "v0334-conversation-more\(worst ? "-worst" : "").png")
            #expect(Double(conversation.pixelsHigh) / 2 <= brPopoverCap, "··· 가 선 대화 화면이 700pt 상한을 넘었다")

            let reportStore = popoverStore("render-report-\(worst)")
            let received = try #require(MessageBubbleReportRule.target(for: reportStore.messageHistory[0]))
            reportStore.openReport(received, surface: .message)
            reportStore.selectReportReason(.harassment)
            reportStore.reportDetailDraft = String(repeating: "합성 설명 ", count: 37)   // 221자 — 넘친 상태(카운터 · 빨간 테두리)
            reportStore.reportNotice = BlockReportText.serverNotReady                      // 가장 긴 안내 줄까지
            let report = try bitmap(reportStore, worstChrome: worst)
            brSave(report, name: "v0334-report-sheet\(worst ? "-worst" : "").png")

            let confirmStore = popoverStore("render-confirm-\(worst)")
            confirmStore.openBlockConfirm(BlockReportTarget(peerID: brPeerA, peerName: String(repeating: "김수한무", count: 4)),
                                          surface: .message)
            let confirm = try bitmap(confirmStore, worstChrome: worst)
            brSave(confirm, name: "v0334-block-confirm\(worst ? "-worst" : "").png")

            for (name, image) in [("신고 시트", report), ("차단 확인", confirm)] {
                let height = Double(image.pixelsHigh) / 2
                #expect(height <= brPopoverCap, "\(name)(\(worst ? "가장 큰 크롬" : "크롬 없음"))가 \(height)pt — 700pt 상한을 넘었다")
                #expect(image.pixelsWide == 414 * 2, "\(name)가 팝오버 폭을 밀어냈다")
                #expect(brYellowPixels(image) == 0, "\(name)에 노란 상자가 있다 — Menu/TextEditor 가 섞였다")
                // 시트는 대화와 **다른 그림**이다(대화 자리에 선다).
                #expect(brDiffers(image, conversation), "\(name)가 대화 화면과 같은 그림이다 — 시트가 안 섰다")
            }
            #expect(brDiffers(report, confirm), "신고 시트와 차단 확인이 같은 그림이다")
        }
    }

    @Test(.gomokuDefaultsCleanup)
    func 오목_창의_신고_덮개는_같은_시트를_노란_상자_없이_그린다() throws {
        let (store, _) = brStore("render-gomoku")
        let gomoku = store.gomoku
        gomoku.phase = .playing
        gomoku.isWindowVisible = false
        gomoku.match = brMatch(id: "11111111-2222-3333-4444-555555555555", opponent: brUser(brPeerA, "소라"))
        let me = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
        let plain = try brRender(GomokuPanel(store: gomoku, me: { me }, clipsOverflowInsteadOfScroll: true, safety: store))
        let noHandle = try brRender(GomokuPanel(store: gomoku, me: { me }, clipsOverflowInsteadOfScroll: true))
        // 사람과 두는 판이면 채팅 머리에 ··· 가 선다(손잡이가 있을 때만).
        #expect(brDiffers(plain, noHandle), "사람과 두는 판인데 채팅 머리에 ··· 가 없다")

        store.openReport(try #require(GomokuChatSafetyRule.target(for: gomoku)), surface: .gomoku)
        store.selectReportReason(.spam)
        let sheet = try brRender(GomokuPanel(store: gomoku, me: { me }, clipsOverflowInsteadOfScroll: true, safety: store))
        brSave(sheet, name: "v0334-gomoku-report.png")
        #expect(sheet.pixelsWide == plain.pixelsWide && sheet.pixelsHigh == plain.pixelsHigh, "덮개가 창 크기를 바꿨다")
        #expect(brYellowPixels(sheet) == 0, "오목 신고 덮개에 노란 상자가 있다")
        #expect(brDiffers(sheet, plain), "오목 창에 신고 덮개가 안 섰다")
        // 팝오버 대화 자리에는 서지 않는다(연 자리에만).
        #expect(store.blockReportSheet(on: .message) == nil)

        // 안전 손잡이가 없으면(렌더 테스트·미리보기) 시트가 떠 있어도 덮개를 그리지 않는다.
        let without = try brRender(GomokuPanel(store: gomoku, me: { me }, clipsOverflowInsteadOfScroll: true))
        #expect(!brDiffers(without, noHandle), "손잡이 없는 창에 덮개가 섰다")

        // AI 판에는 ··· 가 서지 않는다 — 채팅 카드 자리에 안내 카드가 서고, 손잡이가 있어도 그림이 같다.
        store.closeBlockReportSheet()
        gomoku.match = brMatch(id: "\(GomokuAIGame.idPrefix)render", opponent: brUser("ai", "AI"))
        let aiWith = try brRender(GomokuPanel(store: gomoku, me: { me }, clipsOverflowInsteadOfScroll: true, safety: store))
        let aiWithout = try brRender(GomokuPanel(store: gomoku, me: { me }, clipsOverflowInsteadOfScroll: true))
        #expect(!brDiffers(aiWith, aiWithout), "AI 판에 신고·차단 입구가 섰다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 설정의_차단한_사람_목록은_빈_상태와_목록을_창_안에_그린다() throws {
        let (store, _) = brStore("render-settings")
        store.showsBlockedPeopleInSettings = true
        store.blocksLoaded = true
        let empty = try brRender(CheckSettingsView(store: store, launchAtLoginSeed: false)
            .frame(width: CheckSettingsView.preferredWidth))
        brSave(empty, name: "v0334-settings-blocked-empty.png")

        store.blockedPeople = (0..<3).map { index in
            BlockedUser(userID: "u\(index)", name: ["소라", "도윤", "김수한무김수한무"][index], avatarURL: nil,
                        blockedAt: index == 2 ? nil : MessageReadFixture.now.addingTimeInterval(-Double(index + 1) * 86_400))
        }
        store.blockedListNotice = BlockReportRules.notice(for: .network, action: .unblock)
        let list = try brRender(CheckSettingsView(store: store, launchAtLoginSeed: false)
            .frame(width: CheckSettingsView.preferredWidth))
        brSave(list, name: "v0334-settings-blocked-list.png")

        for (name, image) in [("빈 목록", empty), ("목록", list)] {
            #expect(Double(image.pixelsHigh) / 2 <= CheckSettingsWindowController.defaultContentSize.height,
                    "\(name) 화면이 설정 창 높이를 넘었다")
            #expect(brYellowPixels(image) == 0, "\(name) 화면에 노란 상자가 있다")
        }
        #expect(brDiffers(empty, list), "0명과 3명이 같은 그림이다 — 빈 상태 문구가 목록을 대신한다")
        // 설정 본문과 자리를 바꾼다 — 본문으로 돌아가면 다른 그림이다.
        store.closeBlockedPeopleSettings()
        let settings = try brRender(CheckSettingsView(store: store, launchAtLoginSeed: false)
            .frame(width: CheckSettingsView.preferredWidth))
        #expect(brDiffers(settings, list), "[차단한 사람] 쪽이 설정 본문 자리를 안 바꿨다")
    }
}

// MARK: - 헬퍼

private enum BRRenderError: Error { case failed }

@MainActor
private func brRender(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw BRRenderError.failed }
    return bitmap
}

private func brSave(_ bitmap: NSBitmapImageRep, name: String) {
    MessagePanelSnapshots.save(bitmap, name: name)
}

/// ImageRenderer 가 AppKit 기반 컨트롤을 대신 그리는 노란 상자(255,204,0)의 픽셀 수.
private func brYellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var hits = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if data[o] >= 240 && data[o + 1] >= 195 && data[o + 2] <= 40 { hits += 1 }
        }
    }
    return hits
}

/// 두 그림이 눈에 띄게 다른가(채널 합 차이 > 15/255). 크기가 다르면 그것만으로 다르다.
///
/// **원시 바이트로 잰다** — `colorAt` 은 픽셀마다 NSColor 를 만들어 2480×1400 한 장에 몇 초를 메인 액터에서 쓴다. 그 사이 같은
/// 액터에서 도는 벽시계 민감 테스트(울트라 5초 덮기 등)가 밀려 엉뚱한 곳이 빨개진다(2026-09-20 실측 — 이 헬퍼가 원인이었다).
private func brDiffers(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, tolerance: Int = 15) -> Bool {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return true }
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.samplesPerPixel >= 3, lhs.samplesPerPixel == rhs.samplesPerPixel,
          lhs.bytesPerRow == rhs.bytesPerRow else { return true }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    for y in stride(from: 0, to: lhs.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: lhs.pixelsWide, by: 2) {
            let o = y * bpr + x * spp
            let delta = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            if delta > tolerance { return true }
        }
    }
    return false
}

/// 제품 소스를 주석 없이 읽는다(설명문의 낱말이 단언에 걸려 "주석을 지워야 초록"이 되지 않게).
private func brSource(_ name: String) throws -> String {
    try brStripComments(String(contentsOf: CheckCoreSourceLayout.repoRoot
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)"), encoding: .utf8))
}

/// 맥 앱 소스 전부(파일 이름 · 주석 걷은 코드).
private func brMacSources() throws -> [(String, String)] {
    let names = try FileManager.default.contentsOfDirectory(atPath: CheckCoreSourceLayout.macDirectory.path)
        .filter { $0.hasSuffix(".swift") }.sorted()
    return try names.map { name in
        (name, try brStripComments(String(contentsOf: CheckCoreSourceLayout.macDirectory.appendingPathComponent(name),
                                          encoding: .utf8)))
    }
}

/// 저장소의 모든 Swift 소스(맥 · 코어 · 폰 · 위젯) — 저장소 기준 경로와 주석 걷은 코드.
private func brAllSources() throws -> [(path: String, code: String)] {
    let root = CheckCoreSourceLayout.repoRoot
    let base = root.appendingPathComponent("Sources")
    guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
    var found: [(path: String, code: String)] = []
    let rootPath = root.standardizedFileURL.path
    for case let url as URL in walker where url.pathExtension == "swift" {
        let code = brStripComments(try String(contentsOf: url, encoding: .utf8))
        found.append((String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1)), code))
    }
    return found.sorted { $0.path < $1.path }
}

private func brRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let lower = source.range(of: start) else { return nil }
    guard let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        return String(source[lower.lowerBound...])
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

/// `//`·`/* */` 주석을 걷어낸다(문자열 안의 `//` 는 남긴다).
private func brStripComments(_ source: String) -> String {
    var out = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let ch = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if ch == "\n" { inLineComment = false; out.append(ch) }
        } else if inBlockComment {
            if ch == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            out.append(ch)
            if ch == "\"", previous != "\\" { inString = false }
        } else if ch == "/", next == "/" {
            inLineComment = true
            index += 1
        } else if ch == "/", next == "*" {
            inBlockComment = true
            index += 1
        } else {
            if ch == "\"" { inString = true }
            out.append(ch)
        }
        previous = ch
        index += 1
    }
    return out
}
