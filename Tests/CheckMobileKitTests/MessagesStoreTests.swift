import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 메시지 탭 스토어 시나리오(SPEC-ios §3.3 · D4). 앱 모델 전체(세션 · 실시간 러너 · 라우터)를 스텁 서버 위에 세워 **경로로** 잰다.
/// 모든 시나리오 끝에 금지 경로 0건을 단언한다.
@MainActor
@Suite(.serialized) struct MessagesStoreTests {
    typealias Row = MessagesStubServer.Row
    static let peerA = "peer-a"
    static let peerB = "peer-b"

    // MARK: - 새로고침 계기

    @Test("활성화: 요약만 받아 배지를 세우고(목록이 안 보이면 이력은 낡음으로), 목록이 서면 곧바로 이력 · 15초 안 재표시는 스로틀 · 지나면 다시")
    func activationAndListThrottle() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0), .received("a2", from: Self.peerA, at: 10)])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 2)]))
        }
        defer { h.tearDown() }
        #expect(h.count("message_unread_summary") == 1)
        #expect(h.count("message_history_with_reads") == 0, "메시지 화면이 안 보이는데 이력을 받았다")
        #expect(h.store.badgeCount == 2)
        #expect(h.model.badges.badge(for: .messages) == 2)
        #expect(h.store.isHistoryStale)

        h.store.listDidAppear()
        await h.settle()
        #expect(h.count("message_history_with_reads") == 1)
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerA])
        #expect(h.store.unreadPeerIDs == [Self.peerA])
        #expect(!h.store.isHistoryStale)

        h.store.listDidDisappear()
        h.store.listDidAppear()
        await h.settle()
        #expect(h.count("message_history_with_reads") == 1, "15초 안에 다시 선 목록이 또 받았다")

        h.clock.advance(16)
        h.store.listDidDisappear()
        h.store.listDidAppear()
        await h.settle()
        #expect(h.count("message_history_with_reads") == 2)
        h.expectNoForbiddenCalls()
    }

    @Test("닫힌 메시지 탭에 온 신호는 요약만 받고 이력은 낡음 — 목록이 서면 스로틀과 무관하게 곧바로 받는다")
    func signalWhileHiddenMarksStale() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0)])
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        h.store.listDidDisappear()
        let before = h.count("message_history_with_reads")

        h.server.appendRow(.received("a2", from: Self.peerA, at: 20))
        h.transport.emit(.joined)
        h.transport.emit(.broadcast(event: "ring"))
        h.model.realtime.flushCoalescedSignals()
        await h.settle()
        #expect(h.count("message_history_with_reads") == before)
        #expect(h.store.isHistoryStale)

        h.store.listDidAppear()   // 스로틀(15초) 안이지만 낡음이 우회한다
        await h.settle()
        #expect(h.count("message_history_with_reads") == before + 1)
        #expect(h.store.history.map(\.id) == ["a1", "a2"])
        h.expectNoForbiddenCalls()
    }

    // MARK: - 열린 대화 즉시 반영(M4 원칙)

    @Test("열린 대화: ring 신호 뒤 곧바로 이력을 받아 새 줄이 서고 읽음까지 올린다(재진입 없음) · take_pokes 0")
    func openConversationShowsArrivalImmediately() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0, unread: false), .sent("m1", to: Self.peerA, at: 5, read: true)])
        }
        defer { h.tearDown() }
        let token = UUID()
        h.store.conversationDidAppear(peerID: Self.peerA, token: token)
        await h.settle()
        #expect(h.count("mark_messages_read") == 0, "안 읽은 말이 없는데 읽음을 올렸다")
        let historyBefore = h.count("message_history_with_reads")

        h.server.appendRow(.received("a2", from: Self.peerA, body: "지금 막 온 말", at: 30))
        h.transport.emit(.joined)
        h.transport.emit(.broadcast(event: "ring"))
        h.model.realtime.flushCoalescedSignals()
        #expect(await baseWaitUntil { h.store.thread(for: Self.peerA)?.lastMessage?.id == "a2" }, "신호 뒤 새 줄이 안 섰다")
        await h.settle()
        #expect(h.count("message_history_with_reads") == historyBefore + 1, "신호 한 번에 이력 한 번")
        #expect(h.count("mark_messages_read") == 1)
        #expect(h.bodies("mark_messages_read").first?.contains(#""p_through":"a2""#) == true)
        #expect(h.bodies("mark_messages_read").first?.contains(#""p_peer":"peer-a""#) == true)
        h.expectNoForbiddenCalls()
    }

    @Test("겹친 늦은 응답: 먼저 띄운 이력이 늦게 와도 나중 이력이 그린 새 줄을 지우지 않는다")
    func lateOverlappingHistoryDoesNotEraseNewLine() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0, unread: false)])
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        #expect(h.store.history.map(\.id) == ["a1"])

        let old: [Row] = [.received("a1", from: Self.peerA, at: 0, unread: false)]
        let new: [Row] = old + [.received("a2", from: Self.peerA, body: "새 줄", at: 40, unread: false)]
        h.server.scriptHistory([(delay: 0.4, rows: old), (delay: 0, rows: new)])
        let first = Task { await h.store.performLoadHistory() }
        try? await Task.sleep(for: .milliseconds(50))
        await h.store.performLoadHistory()
        #expect(h.store.history.map(\.id) == ["a1", "a2"])
        await first.value
        #expect(h.store.history.map(\.id) == ["a1", "a2"], "먼저 띄운 늦은 응답이 새 줄을 지웠다")
        h.expectNoForbiddenCalls()
    }

    // MARK: - 읽음

    @Test("읽음 조건 표: active + 그 대화가 떠 있음 + 서버 기준 안 읽음일 때만 — 목록만·다른 대화·background 는 0회")
    func readMarkingConditions() async {
        let h = await MessagesHarness.make { server in
            server.setRows([
                .received("a1", from: Self.peerA, at: 0), .received("a2", from: Self.peerA, at: 10),
                .received("b1", from: Self.peerB, at: 20),
            ])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 2), (Self.peerB, 1)]))
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        #expect(h.count("mark_messages_read") == 0, "목록만 봤는데 읽음을 올렸다")

        // 다른 사람(B)과의 대화 → A 는 올리지 않는다.
        let tokenB = UUID()
        h.store.conversationDidAppear(peerID: Self.peerB, token: tokenB)
        await h.settle()
        #expect(h.bodies("mark_messages_read").allSatisfy { $0.contains(Self.peerB) && !$0.contains(Self.peerA) })
        #expect(h.count("mark_messages_read") == 1)
        h.store.conversationDidDisappear(token: tokenB)

        // background 에서 대화가 서면(복원 등) 올리지 않는다.
        h.model.sceneDidEnterBackground()
        let tokenA = UUID()
        h.store.conversationDidAppear(peerID: Self.peerA, token: tokenA)
        await h.settle()
        #expect(!h.bodies("mark_messages_read").contains { $0.contains(Self.peerA) }, "background 에서 읽음을 올렸다")
        #expect(h.model.router.visibleConversationPeerID == nil, "background 인데 보이는 대화로 적었다")

        // active 로 돌아오면 그 자리에서 올린다(마지막 받은 id).
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(h.model.router.visibleConversationPeerID == Self.peerA)
        let marksA = h.bodies("mark_messages_read").filter { $0.contains(Self.peerA) }
        #expect(marksA.count == 1)
        #expect(marksA.first?.contains(#""p_through":"a2""#) == true)
        h.expectNoForbiddenCalls()
    }

    @Test("낙관 읽음: 응답 전에 점·배지가 곧바로 꺼지고, 성공 뒤 소켓 메아리가 없으면 창이 닫힐 때 요약 한 번")
    func optimisticReadAndPostMarkRefresh() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0)])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 1)]))
            server.setMarkDelay(0.4)
        }
        defer { h.tearDown() }
        h.store.postMarkRefreshSeconds = 0.2
        #expect(h.store.badgeCount == 1)
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        #expect(await baseWaitUntil { h.store.isMarkingRead })
        #expect(h.store.badgeCount == 0, "응답 전에 배지가 안 꺼졌다")
        #expect(h.store.unreadPeerIDs.isEmpty)
        // 대화가 서며 띄운 새로고침(요약·이력)이 끝나기를 기다린다 — 읽음 왕복(0.4초)은 아직 날아가는 중이다.
        #expect(await baseWaitUntil { h.store.pendingActivityTask == nil })
        #expect(h.store.isMarkingRead)
        #expect(h.store.badgeCount == 0, "읽음 왕복 중에 온 이력이 점을 되살렸다")
        let summariesBefore = h.count("message_unread_summary")

        h.server.setRows([.received("a1", from: Self.peerA, at: 0, unread: false)])
        h.server.setSummary(MessagesStubServer.summary([]))
        #expect(await baseWaitUntil { !h.store.isMarkingRead })
        #expect(await baseWaitUntil { h.count("message_unread_summary") == summariesBefore + 1 }, "읽음 성공 뒤 요약을 다시 안 받았다")
        await h.settle()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(h.count("message_unread_summary") == summariesBefore + 1)
        #expect(h.store.badgeCount == 0)
        h.expectNoForbiddenCalls()
    }

    @Test("읽음 성공 뒤 소켓 메아리(message_read)가 창 안에 오면 그 새로고침이 맡는다 — 요약이 두 번 나가지 않는다")
    func postMarkEchoCoalesces() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0)])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 1)]))
        }
        defer { h.tearDown() }
        let released = BaseLockedBox(false)
        h.store.sleep = { _ in
            while !released.get() { try? await Task.sleep(for: .milliseconds(5)) }
        }
        h.transport.emit(.joined)
        h.model.realtime.flushCoalescedSignals()
        await h.settle()
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        #expect(h.count("mark_messages_read") == 1)
        #expect(h.store.pendingPostMarkTask != nil)
        let summaries = h.count("message_unread_summary")

        h.transport.emit(.broadcast(event: "message_read"))   // 서버가 읽은 사람 채널로 되돌려 보낸 메아리
        h.model.realtime.flushCoalescedSignals()
        await h.settle()
        #expect(h.count("message_unread_summary") == summaries + 1)
        released.mutate { $0 = true }
        #expect(await baseWaitUntil { h.store.pendingPostMarkTask == nil })
        await h.settle()
        #expect(h.count("message_unread_summary") == summaries + 1, "메아리가 맡았는데 창이 또 요약을 받았다")
        h.expectNoForbiddenCalls()
    }

    @Test("읽음 신호(message_read) 한 번만으로 열린 대화의 이력을 다시 받아 내 말풍선 옆 1 이 사라진다 — 조인 따라잡기는 미리 끝내 둔다")
    func readSignalClearsUnreadOne() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0, unread: false), .sent("m1", to: Self.peerA, at: 10, read: false)])
        }
        defer { h.tearDown() }
        // 조인 따라잡기(catchUp → 이력)를 1 을 보기 **전에** 끝낸다 — 그 새로고침이 읽음 신호의 몫을 대신해 테스트가 공허했다(messages-verify M33).
        h.transport.emit(.joined)
        h.model.realtime.flushCoalescedSignals()
        await h.settle()
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        func showsOne() -> Bool {
            h.store.conversationItems(for: Self.peerA).contains { if case .bubble(let line) = $0 { return line.showsUnreadOne } else { return false } }
        }
        #expect(showsOne())
        let historyBefore = h.count("message_history_with_reads")
        h.server.setRead(peer: Self.peerA)
        h.transport.emit(.broadcast(event: "message_read"))
        h.model.realtime.flushCoalescedSignals()
        #expect(await baseWaitUntil(timeout: 2) { !showsOne() }, "읽음 신호 뒤에도 1 이 남았다")
        await h.settle()
        #expect(h.count("message_history_with_reads") == historyBefore + 1, "읽음 신호 한 번에 열린 대화 이력 한 번")
        h.expectNoForbiddenCalls()
    }

    @Test("읽음 처리가 네트워크로 실패하면 점은 낙관으로 꺼진 채, 다음 이력에서 같은 경계로 다시 올린다(나가도 점이 되살아나지 않게)")
    func failedMarkRetriesOnNextHistory() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0)])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 1)]))
            server.setMark(.networkFailure())
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        #expect(h.count("mark_messages_read") == 1)
        #expect(h.store.optimisticReads[Self.peerA]?.failed == true, "실패한 읽음이 실패로 정산되지 않았다")
        #expect(h.store.badgeCount == 0, "낙관 읽음은 실패해도 되돌리지 않는다")

        h.server.setMark(.json(#"{"status":"ok","advanced":true,"unread":0}"#))
        await h.store.refreshNow()
        await h.settle()
        #expect(h.count("mark_messages_read") == 2, "실패한 읽음 처리를 다음 이력에서 다시 올리지 않았다")
        #expect(h.bodies("mark_messages_read").last?.contains(#""p_through":"a1""#) == true)
        #expect(h.store.optimisticReads[Self.peerA]?.failed == false)
        h.expectNoForbiddenCalls()
    }

    @Test("읽음 왕복 중에 새 말이 오면 겹쳐 띄우지 않고, 그 왕복이 끝나는 대로 새 경계로 한 번 더 올린다")
    func markAgainAfterInFlight() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0)])
            server.setMarkDelay(0.5)
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        #expect(await baseWaitUntil { h.store.isMarkingRead })
        #expect(await baseWaitUntil { h.store.pendingActivityTask == nil })
        h.server.appendRow(.received("a2", from: Self.peerA, at: 20))
        await h.store.refreshNow()
        #expect(h.store.isMarkingRead, "왕복(0.5초)이 이미 끝나 이 시나리오를 재지 못한다")
        #expect(h.count("mark_messages_read") == 1, "왕복 중에 두 번째 읽음을 나란히 띄웠다")
        #expect(await baseWaitUntil { h.bodies("mark_messages_read").contains { $0.contains(#""p_through":"a2""#) } },
                "왕복이 끝난 뒤 a2 로 다시 올리지 않았다")
        await h.settle()
        #expect(h.count("mark_messages_read") == 2)
        h.expectNoForbiddenCalls()
    }

    @Test("읽음 함수가 없는 서버: message_history 로 접고 1·읽음 처리를 하지 않는다(옛 도장 규칙)")
    func fallsBackWithoutReadReceipts() async {
        let h = await MessagesHarness.make { server in
            server.setWithReadsMissing(true)
            server.setSummary("")
            server.setRows([.received("a1", from: Self.peerA, at: 0), .sent("m1", to: Self.peerA, at: 10)])
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        #expect(h.count("message_history") == 1)
        #expect(!h.store.readReceiptsAvailable)
        #expect(h.store.unreadPeerIDs == [Self.peerA], "도장이 없으면 받은 대화는 안 읽음")
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        #expect(h.count("mark_messages_read") == 0)
        #expect(h.store.unreadPeerIDs.isEmpty, "대화를 본 도장이 점을 꺼야 한다")
        #expect(!h.store.conversationItems(for: Self.peerA).contains { if case .bubble(let l) = $0 { return l.showsUnreadOne } else { return false } })
        h.expectNoForbiddenCalls()
    }

    // MARK: - 불러오기 실패

    @Test("오프라인 첫 진입: 이력·사람 찾기가 실패하면 '불러오는 중'에 멈추지 않고 실패 화면 · 머리는 가짜 이름 대신 일반 아이콘 · 다시 시도로 둘 다 회복")
    func offlineFirstEntryShowsFailureAndRecovers() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(#"[{"user_id":"peer-z","display_name":"지우","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"}]"#)
        }
        defer { h.tearDown() }
        let offline = BaseLockedBox(true)
        for rpc in ["message_history_with_reads", "app_user_directory"] {
            h.server.override(rpc) { _ in offline.get() ? .networkFailure() : nil }
        }
        h.store.conversationDidAppear(peerID: "peer-z", token: UUID())
        await h.settle()
        #expect(h.store.historyFailed, "오프라인 이력 실패가 실패로 적히지 않았다")
        #expect(!h.store.historyLoaded)
        #expect(!h.store.historyLoading)
        let failure = MessagesConversationRules.emptyState(loaded: h.store.historyLoaded, failed: h.store.historyFailed)
        #expect(failure.title == "대화를 불러오지 못했어요")
        #expect(failure.showsRetry)
        #expect(h.store.directoryFailed)
        let unknown = h.store.conversationHeader(for: "peer-z")
        #expect(unknown.title == MessagesConversationHeader.fallbackTitle)
        #expect(unknown.avatarName == nil, "이름을 모르는데 이니셜 아바타를 세웠다")
        #expect(unknown.accessibilityLabel == MessagesConversationHeader.unknownAccessibilityLabel)

        offline.mutate { $0 = false }
        await h.store.retryConversation(peerID: "peer-z")
        await h.settle()
        #expect(!h.store.historyFailed)
        #expect(h.store.historyLoaded)
        #expect(h.store.directoryLoaded)
        let known = h.store.conversationHeader(for: "peer-z")
        #expect(known.title == "지우")
        #expect(known.avatarName == "지우")
        #expect(MessagesConversationRules.emptyState(loaded: h.store.historyLoaded, failed: h.store.historyFailed).title == "아직 주고받은 메시지가 없어요")
        h.expectNoForbiddenCalls()
    }

    // MARK: - 보내기

    @Test("보내기: 누르는 즉시 입력칸이 비고 자리 말풍선이 서며, 성공 뒤 이력이 진짜 행으로 바꾼다 — 근무 여부와 무관")
    func sendSuccess() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0, unread: false)])
            server.setSendDelay(0.3)
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        h.store.setDraft("  안녕하세요\n반가워요  ", for: Self.peerA)
        // 보내기부터의 요청만 잰다(지금 탭 활성화의 work_statuses·work_sessions GET 은 보내기와 무관한 병합 이웃 몫).
        let requestsBeforeSend = h.requests.count
        #expect(h.store.canSend(to: Self.peerA))
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(h.store.draft(for: Self.peerA).isEmpty)
        #expect(h.store.pendingOutgoing.map(\.body) == ["안녕하세요\n반가워요"])
        #expect(h.store.isSending)
        #expect(!h.store.canSend(to: Self.peerA))
        #expect(h.store.conversationItems(for: Self.peerA).last?.id.hasPrefix("pending-") == true)

        h.server.appendRow(.sent("m1", to: Self.peerA, body: "안녕하세요\n반가워요", at: 60))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.pendingOutgoing.isEmpty, "진짜 행이 왔는데 자리 말풍선이 남았다")
        #expect(h.store.thread(for: Self.peerA)?.messages.map(\.id) == ["a1", "m1"])
        #expect(h.store.sendNotices[Self.peerA] == nil)
        let sendBody = h.bodies("send_message").first ?? ""
        #expect(sendBody.contains(#""p_to":"peer-a""#))
        #expect(sendBody.contains("반가워요"))
        #expect(!h.requests.dropFirst(requestsBeforeSend).contains { $0.path.contains("work_") }, "보내기가 근무 경로를 건드렸다")
        h.expectNoForbiddenCalls()
    }

    @Test("보내기 실패: target_focused 는 코어 문구 · 글은 입력칸으로 돌아오고 자리 말풍선은 거둔다 · 네트워크 실패는 연결 문구")
    func sendFailures() async {
        let h = await MessagesHarness.make { server in
            server.setSend(.json(#"{"status":"target_focused"}"#))
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        h.store.setDraft("집중 중인 사람에게", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        #expect(h.store.sendNotices[Self.peerA] == "지금 집중 중이에요. 나중에 보내 주세요")
        #expect(h.store.draft(for: Self.peerA) == "집중 중인 사람에게")
        #expect(h.store.pendingOutgoing.isEmpty)

        h.server.setSend(.networkFailure())
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(h.store.sendNotices[Self.peerA] == nil, "누르는 순간 옛 문구를 내린다")
        #expect(await baseWaitUntil { !h.store.isSending })
        #expect(h.store.sendNotices[Self.peerA] == MessagesSendRules.connectionNotice)
        #expect(h.store.draft(for: Self.peerA) == "집중 중인 사람에게")

        h.server.setSend(.json(#"{"status":"too_long","max_length":150}"#))
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        #expect(h.store.sendNotices[Self.peerA] == "메시지는 150자까지예요. 줄여서 보내 주세요")
        h.expectNoForbiddenCalls()
    }

    @Test("한글 조합 중이면 보내지 않는다(요청 0) · 빈 글·200자 초과도 네트워크를 타지 않는다")
    func sendGuards() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        h.store.setDraft("안녕하세", for: Self.peerA)
        #expect(!h.store.sendDraft(to: Self.peerA, isComposing: true))
        #expect(h.store.draft(for: Self.peerA) == "안녕하세")
        h.store.setDraft("   \n ", for: Self.peerA)
        #expect(!h.store.sendDraft(to: Self.peerA, isComposing: false))
        h.store.setDraft(String(repeating: "가", count: 201), for: Self.peerA)
        #expect(!h.store.canSend(to: Self.peerA))
        #expect(!h.store.sendDraft(to: Self.peerA, isComposing: false))
        await h.settle()
        #expect(h.count("send_message") == 0)
        h.expectNoForbiddenCalls()
    }

    // MARK: - 푸시 · 보이는 대화 · 사람 찾기

    @Test("푸시 진입점: 떠 있는 대화의 푸시면 이력까지 곧바로, 다른 사람 푸시면 요약만(이력은 낡음)")
    func pushEntryPoint() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0, unread: false)])
        }
        defer { h.tearDown() }
        let token = UUID()
        h.store.conversationDidAppear(peerID: Self.peerA, token: token)
        await h.settle()
        h.store.conversationDidDisappear(token: token)
        let history = h.count("message_history_with_reads")
        let summaries = h.count("message_unread_summary")

        h.store.didReceiveMessagePush(peerID: Self.peerB)
        await h.settle()
        #expect(h.count("message_unread_summary") == summaries + 1)
        #expect(h.count("message_history_with_reads") == history)
        #expect(h.store.isHistoryStale)

        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        let afterOpen = h.count("message_history_with_reads")
        h.server.appendRow(.received("a2", from: Self.peerA, at: 50))
        h.store.didReceiveMessagePush(peerID: Self.peerA)
        await h.settle()
        #expect(h.count("message_history_with_reads") == afterOpen + 1)
        #expect(h.store.thread(for: Self.peerA)?.lastMessage?.id == "a2")
        h.expectNoForbiddenCalls()
    }

    @Test("보이는 대화 표시: 같은 상대의 새 화면이 옛 화면의 사라짐보다 먼저 서도 꺼지지 않는다 · 모두 사라지면 nil")
    func visibleConversationTokens() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let old = UUID()
        let new = UUID()
        h.store.conversationDidAppear(peerID: Self.peerA, token: old)
        h.store.conversationDidAppear(peerID: Self.peerA, token: new)
        h.store.conversationDidDisappear(token: old)
        #expect(h.store.openConversationPeerID == Self.peerA)
        #expect(h.model.router.visibleConversationPeerID == Self.peerA)
        h.store.conversationDidAppear(peerID: Self.peerB, token: old)
        #expect(h.model.router.visibleConversationPeerID == Self.peerB)
        h.store.conversationDidDisappear(token: old)
        #expect(h.model.router.visibleConversationPeerID == Self.peerA)
        h.store.conversationDidDisappear(token: new)
        #expect(h.store.openConversationPeerID == nil)
        #expect(h.model.router.visibleConversationPeerID == nil)
        await h.settle()
        h.expectNoForbiddenCalls()
    }

    @Test("사람 찾기: app_user_directory 를 근무 중 먼저로 받고, 이력이 없는 상대의 대화 머리 이름을 채운다")
    func directoryAndPeerName() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory("""
            [{"user_id":"peer-z","display_name":"지우","avatar_url":null,"is_working":false,"message_capable":true,"center":"busan"},
             {"user_id":"peer-y","display_name":"하린","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"}]
            """)
        }
        defer { h.tearDown() }
        // 지금 탭 활성화도 같은 RPC 를 부른다(병합 이웃) — 메시지 스토어가 더한 수만 잰다.
        let directoryBefore = h.count("app_user_directory")
        #expect(h.store.peerName(for: "peer-z") == nil)
        h.store.conversationDidAppear(peerID: "peer-z", token: UUID())
        await h.settle()
        #expect(h.count("app_user_directory") == directoryBefore + 1)
        #expect(h.store.directory.map(\.name) == ["하린", "지우"])
        #expect(h.store.directory.first?.center == "서울")
        #expect(h.store.peerName(for: "peer-z") == "지우")
        #expect(h.store.filteredDirectory(query: "ㅈㅇ").map(\.userID) == ["peer-z"])
        h.store.loadDirectory()
        await h.settle()
        #expect(h.count("app_user_directory") == directoryBefore + 1, "60초 안 재조회")
        h.expectNoForbiddenCalls()
    }

    // MARK: - 세대

    @Test("로그아웃: 떠 있던 이력 응답이 늦게 와도 다음 계정 화면에 안 들어가고, 입력칸·자리 말풍선·보이는 대화가 비워진다")
    func signOutDropsLateResponses() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0)])
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()
        #expect(!h.store.history.isEmpty)
        h.store.setDraft("쓰던 글", for: Self.peerA)
        h.server.scriptHistory([(delay: 0.5, rows: [.received("x9", from: Self.peerB, at: 99)])])
        let late = Task { await h.store.performLoadHistory() }
        try? await Task.sleep(for: .milliseconds(50))

        await h.model.session.signOut()
        #expect(h.store.history.isEmpty)
        #expect(h.store.drafts.isEmpty)
        #expect(h.store.badgeCount == 0)
        #expect(h.model.router.visibleConversationPeerID == nil)
        await late.value
        #expect(h.store.history.isEmpty, "로그아웃 뒤 늦게 온 이력이 들어왔다")
        #expect(!h.store.historyLoading)
        #expect(h.store.summary == nil)
        h.expectNoForbiddenCalls()
    }

    // 계정 전환(로그아웃 → 다른 사용자로 로그인) 뒤에 앞 계정의 늦은 응답이 도착하는 경로 — 세대 가드마다 한 시나리오(messages-verify M17·M18·M20·M22).
    // 늦은 응답은 0.6초 뒤에 온다. 새는지 보는 창(1.5초)은 다음 계정 로그인이 끝난 뒤부터 잰다 — 새면 곧바로 잡힌다.

    @Test("계정 전환: 앞 계정이 띄운 요약이 늦게 와도 다음 계정 배지에 안 들어간다")
    func lateSummaryDoesNotLeakIntoNextAccount() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let summariesBefore = h.count("message_unread_summary")
        h.server.overrideFirst("message_unread_summary", .json(MessagesStubServer.summary([(Self.peerA, 5)]), delay: 0.6))
        let late = Task { await h.store.performLoadSummary() }
        #expect(await baseWaitUntil { h.count("message_unread_summary") == summariesBefore + 1 })
        await h.switchAccount()
        #expect(h.count("message_unread_summary") >= summariesBefore + 2, "다음 계정의 활성화 요약을 받지 않았다")
        await late.value
        await h.settle()
        #expect(h.store.badgeCount == 0, "앞 계정 요약이 다음 계정 배지로 들어왔다: \(h.store.badgeCount)")
        #expect(h.store.summary?.summary.total ?? 0 == 0)
        h.expectNoForbiddenCalls()
    }

    @Test("계정 전환: 앞 계정이 누른 전송의 늦은 거절(target_focused)이 다음 계정 입력칸·문구에 안 들어간다")
    func lateSendRejectionDoesNotLeakIntoNextAccount() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        h.server.setSend(.json(#"{"status":"target_focused"}"#))
        h.server.setSendDelay(0.6)
        h.store.setDraft("앞 계정의 글", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { h.count("send_message") == 1 })
        #expect(h.store.isSending, "거절이 로그아웃 전에 이미 돌아와 늦은 응답을 재지 못한다")
        await h.switchAccount()
        #expect(h.store.drafts.isEmpty && h.store.pendingOutgoing.isEmpty && !h.store.isSending)
        let clean = await h.staysFalse(for: 1.5) {
            !h.store.drafts.isEmpty || !h.store.sendNotices.isEmpty || !h.store.pendingOutgoing.isEmpty
        }
        #expect(clean, "앞 계정 글·문구가 다음 계정에 섰다: \(h.store.drafts) \(h.store.sendNotices)")
        h.expectNoForbiddenCalls()
    }

    @Test("계정 전환: 앞 계정이 누른 전송의 늦은 네트워크 실패가 다음 계정 입력칸·연결 문구로 안 들어간다")
    func lateSendFailureDoesNotLeakIntoNextAccount() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        // 스텁은 전송 응답의 지연을 `setSendDelay` 로 덮어쓴다 — 실패 응답에 지연을 실으면 0 으로 지워져 로그아웃 전에 끝났다(첫 변이 실행에서 M18 이 살아남은 원인).
        h.server.setSend(.networkFailure())
        h.server.setSendDelay(0.6)
        h.store.setDraft("앞 계정의 글", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { h.count("send_message") == 1 })
        #expect(h.store.isSending, "전송 실패가 로그아웃 전에 이미 돌아와 늦은 응답을 재지 못한다")
        await h.switchAccount()
        let clean = await h.staysFalse(for: 1.5) {
            !h.store.drafts.isEmpty || !h.store.sendNotices.isEmpty || !h.store.pendingOutgoing.isEmpty
        }
        #expect(clean, "앞 계정 글·연결 문구가 다음 계정에 섰다: \(h.store.drafts) \(h.store.sendNotices)")
        h.expectNoForbiddenCalls()
    }

    @Test("계정 전환: 앞 계정이 띄운 사람 찾기가 늦게 와도 다음 계정 목록에 안 들어가고, 다음 계정은 자기 목록을 받는다")
    func lateDirectoryDoesNotLeakIntoNextAccount() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(#"[{"user_id":"new-friend","display_name":"새계정친구","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"}]"#)
        }
        defer { h.tearDown() }
        h.server.overrideFirst("app_user_directory", .json(
            #"[{"user_id":"old-friend","display_name":"앞계정친구","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"}]"#,
            delay: 0.6
        ))
        let directoryBefore = h.count("app_user_directory")
        h.store.loadDirectory()
        #expect(await baseWaitUntil { h.count("app_user_directory") == directoryBefore + 1 })
        #expect(h.store.directoryLoading, "사람 찾기가 로그아웃 전에 이미 돌아와 늦은 응답을 재지 못한다")
        await h.switchAccount()
        let clean = await h.staysFalse(for: 1.5) { h.store.directoryLoaded || !h.store.directory.isEmpty }
        #expect(clean, "앞 계정 사람 목록이 다음 계정에 들어왔다: \(h.store.directory.map(\.userID))")
        h.store.loadDirectory()
        await h.settle()
        #expect(h.store.directory.map(\.userID) == ["new-friend"], "다음 계정이 자기 사람 목록을 받지 못했다")
        h.expectNoForbiddenCalls()
    }

    @Test("겹친 요약: 먼저 띄운 요약이 늦게 와도 나중 요약을 덮지 않는다(배지가 옛 숫자로 되살아나지 않는다)")
    func lateOverlappingSummaryDoesNotOverwrite() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let summariesBefore = h.count("message_unread_summary")
        h.server.overrideFirst("message_unread_summary", .json(MessagesStubServer.summary([(Self.peerA, 3)]), delay: 0.5))
        let early = Task { await h.store.performLoadSummary() }
        #expect(await baseWaitUntil { h.count("message_unread_summary") == summariesBefore + 1 })
        await h.store.performLoadSummary()
        #expect(h.store.badgeCount == 0)
        let newerSerial = h.store.summary?.serial
        #expect(newerSerial != nil)
        await early.value
        #expect(h.store.badgeCount == 0, "먼저 띄운 늦은 요약(3)이 새 요약(0)을 덮었다: \(h.store.badgeCount)")
        #expect(h.store.summary?.serial == newerSerial)
        h.expectNoForbiddenCalls()
    }
}
