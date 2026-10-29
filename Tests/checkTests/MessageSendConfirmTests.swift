import Foundation
import Testing
@testable import check
@testable import CheckCore

// 2026-10-30 서버 안정화 — 맥 메시지 전송: **서버 행 즉시 표시 · 멱등 키 · 응답 유실 재시도**(스토어).
//
// 배경(docs/plan/service-stability-audit-2026-10-30.md §메시지 표시와 전송 신뢰성): 맥은 성공 뒤 이력이 한 번 더 와야 보낸 말이
// 보였고(추가 왕복), 전송에 멱등 키가 없어 "저장은 됐는데 응답만 잃은" 전송을 다시 보내면 두 통이 될 수 있었다.
// 서버(send_message 3인자)가 ok 에 message_id·created_at 을 싣고 같은 키 재요청을 duplicate 로 접는다(공용 계약 — stab/base).
//
// 이 파일이 재는 일곱(지시서 ①~⑦):
//  ① ok 응답만으로 — 이력 응답 **전에** — 대화에 내 말풍선이 선다(정규화 본문 · 서버 시각 · 서버 id).
//  ② 전송 전에 띄운 느린 이력이 나중에 와도 내 말풍선이 안 사라지고, 그 id 를 실은 다음 이력이 오면 한 줄이다. 60초 상한.
//  ③ 키 없는 옛 서버 응답은 예전 그대로(이력 재조회로만 선다 · 재시도 깃발 안 섬).
//  ④ 깃발 참 → 5xx 다음 ok: 요청 2건 · 같은 키. 깃발 거짓 → 재시도 없음. 재시도 대기 중 로그아웃 → 두 번째 요청 없음.
//  ⑤ 모호한 실패 뒤 같은 본문 = 같은 키, 다른 본문 · 확정 거절 뒤 = 새 키(장부 10분 창 포함).
//  ⑥ 이모티콘 전송은 입력칸 글을 안 지운다(성공 · 실패 · 재시도).
//  ⑦ 내 행 삽입은 안 읽음 집합 · 콕찌르기 목록 순서를 바꾸지 않는다.
//
// 스텁이 못 잡는 것(서버가 실제로 같은 키를 한 행으로 접는가 · 정규화 차이)은 서버 레인(l2s)의 하네스·운영 프로브 몫이다.

private typealias Fx = MessageReadFixture

/// 픽스처의 셋째 사람(공용 픽스처에는 둘뿐이다 — 고치지 않고 여기 둔다).
private let mscPeerC = "00000000-0000-0000-0000-0000000330d4"

/// 서버 created_at 모양(마이크로초 · +00:00) — Fx.now 기준 `offset` 초 뒤, 소수부 `.635997`(반올림하면 다음 초로 넘어가는 값).
private func mscServerCreatedAt(offset: Int) -> String {
    let formatter = ISO8601DateFormatter()
    let whole = formatter.string(from: Fx.now.addingTimeInterval(TimeInterval(offset)))
    return whole.replacingOccurrences(of: "Z", with: ".635997+00:00")
}

/// 위 문자열이 이력 행 눈금(created_epoch — 초 반올림)으로 서는 시각.
private func mscRoundedDate(offset: Int) -> Date {
    Fx.now.addingTimeInterval(TimeInterval(offset + 1))
}

private func mscOK(id: String?, body: String = "안녕", offset: Int = 30, duplicate: Bool = false) -> MessageReadStubProtocol.Reply {
    var object: [String: Any] = ["status": "ok", "body": body, "ring": duplicate ? "duplicate" : "sent"]
    if let id {
        object["message_id"] = id
        object["created_at"] = mscServerCreatedAt(offset: offset)
    }
    if duplicate { object["duplicate"] = true }
    return MessageReadStubProtocol.Reply(body: Fx.json(object))
}

private func mscStatus(_ status: String) -> MessageReadStubProtocol.Reply {
    MessageReadStubProtocol.Reply(body: Fx.json(["status": status]))
}

private let msc504 = MessageReadStubProtocol.Reply(status: 504, body: #"{"message":"upstream request timeout"}"#)

/// 대화를 연다(패널 · 상대 · 첫 이력). 팝오버가 떠 있고 대화 뷰가 서 있다.
@MainActor
private func mscOpenConversation(_ store: WorkTimerStore, peer: String = Fx.peerA) async {
    store.isMenuPresented = true
    store.messageConversationViewDidAppear(UUID())
    store.openMessagePanel(peer: peer)
    await messageReadWait { store.messageHistoryLoaded && messageReadIdle(store) }
}

@MainActor
private func mscSendCalls(_ host: String) -> [MessageReadStubProtocol.Call] {
    MessageReadStubProtocol.calls(host: host, rpc: "send_message")
}

@MainActor
private func mscKey(_ call: MessageReadStubProtocol.Call) -> String? {
    call.json["p_client_message_id"] as? String
}

/// 전송 하나가 끝날 때까지(잠금이 풀리고 문구가 섰다). 따라 붙은 이력·읽음 왕복까지 기다린다.
@MainActor
private func mscWaitSent(_ store: WorkTimerStore) async {
    await messageReadWait { !store.isSendingMessage && store.messageNotice != nil }
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Suite("MessageSendConfirm")
struct MessageSendConfirmTests {
    // MARK: ① 서버 행 즉시 표시

    @Test(.gomokuDefaultsCleanup)
    func ok_응답만으로_이력_전에_내_말풍선이_선다() async throws {
        let late = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("msc-ok") { call, index in
            switch call.rpc {
            case "message_history_with_reads":
                var rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, body: "먼저 온 말", epoch: Int(Fx.now.timeIntervalSince1970) - 120, unread: false, name: "다람쥐")]
                guard index >= 1 else { return Fx.historyReply(rows) }
                rows.append(Fx.readsRow(id: "s1", peer: Fx.peerA, isMine: true, body: "안녕", epoch: Int(mscRoundedDate(offset: 30).timeIntervalSince1970), readByPeer: false, name: "다람쥐"))
                return Fx.historyReply(rows, gate: late)
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return mscOK(id: "s1")
            default: return nil
            }
        }
        await mscOpenConversation(store)
        store.messageDraft = "  안녕 \n"
        store.sendDraftMessage()
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads") == 2 }
        await messageReadWait { !store.isSendingMessage }

        // 전송 뒤 이력은 문에 붙잡혀 있다 — 그래도 말풍선은 서 있어야 한다.
        let row = try #require(store.selectedMessageThread?.messages.last, "ok 응답만으로는 말풍선이 안 섰다(이력 왕복을 기다린다)")
        #expect(row.id == "s1", "서버 id 가 아니다 — 다음 이력의 진짜 행과 두 줄이 된다")
        #expect(row.isMine)
        #expect(row.body == "안녕", "전선에 실린 정규화 본문이 아니다")
        #expect(row.createdAt == mscRoundedDate(offset: 30), "서버 created_at(이력 눈금 — 초 반올림)이 아니다")
        #expect(row.readByPeer == false, "읽음을 아는 서버인데 1 이 안 붙었다")
        #expect(row.isUnread == nil)
        #expect(row.peerName == "다람쥐", "이미 아는 이름 대신 지어낸 이름이 들어갔다 — 머리 이름이 한 왕복 동안 바뀐다")
        #expect(store.messageDraft == "", "초안 전송 성공인데 입력칸이 안 비었다")
        let firstCall = try #require(mscSendCalls(host).first)
        #expect(mscKey(firstCall)?.count == 36, "멱등 키가 안 실렸다")

        late.open()
        await messageReadWait { messageReadIdle(store) }
        #expect(store.messageHistory.filter { $0.id == "s1" }.count == 1, "서버 이력이 오자 말풍선이 두 개가 됐다")
        #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "s1"])
        #expect(store.messageReadRuntime.confirmedSentRows.isEmpty, "그 id 를 실은 이력이 온 뒤에도 장부가 남았다")
        #expect(store.messageReadRuntime.sendLedger.serverConfirmsRows, "message_id 를 봤는데 재시도 깃발이 안 섰다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 이력에_없는_상대는_목록_이름으로_채운다() async {
        let gate = MessageReadStubGate()
        let (store, _) = makeMessageReadStore("msc-name") { call, index in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([], gate: index >= 1 ? gate : nil)
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return mscOK(id: "s9", body: "처음 뵙겠어요")
            default: return nil
            }
        }
        store.pokeDirectory = [PokeDirectoryEntry(userID: Fx.peerB, name: "고슴도치", avatarURL: URL(string: "https://example.com/b.png"), isWorking: true)]
        await mscOpenConversation(store, peer: Fx.peerB)
        store.sendMessage(to: Fx.peerB, body: "처음 뵙겠어요")
        await messageReadWait { store.messageHistory.contains { $0.id == "s9" } }
        let row = store.messageHistory.first { $0.id == "s9" }
        #expect(row?.peerName == "고슴도치")
        #expect(row?.peerAvatarURL?.absoluteString == "https://example.com/b.png")
        gate.open()
        await messageReadWait { messageReadIdle(store) && !store.isSendingMessage }
    }

    // MARK: ② 늦게 온 옛 이력 · 60초 상한

    @Test(.gomokuDefaultsCleanup)
    func 전송_전에_띄운_느린_이력이_내_말풍선을_지우지_않는다() async throws {
        let early = MessageReadStubGate()
        let after = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("msc-race") { call, index in
            let m0 = Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, epoch: Int(Fx.now.timeIntervalSince1970) - 120, unread: false)
            switch call.rpc {
            case "message_history_with_reads":
                switch index {
                case 0: return Fx.historyReply([m0])
                case 1: return Fx.historyReply([m0], gate: early)   // 전송 **전에** 띄웠다 — s1 을 모른다
                default:
                    // 전송 뒤에 띄웠다 — 서버 판(상대가 이미 읽었다: 1 이 사라진 값으로 구별한다).
                    let s1 = Fx.readsRow(id: "s1", peer: Fx.peerA, isMine: true, body: "안녕", epoch: Int(mscRoundedDate(offset: 30).timeIntervalSince1970), readByPeer: true)
                    return Fx.historyReply([m0, s1], gate: after)
                }
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return mscOK(id: "s1")
            default: return nil
            }
        }
        await mscOpenConversation(store)
        let slow = Task { @MainActor in await store.performLoadMessageHistory() }
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads") == 2 }

        store.sendMessage(to: Fx.peerA, body: "안녕")
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads") == 3 && !store.isSendingMessage }
        #expect(store.messageHistory.map(\.id) == ["m0", "s1"], "전제: ok 응답으로 내 말이 섰다")

        // 전송 전에 띄운 옛 응답이 **먼저** 도착한다(뒤의 조회는 아직 붙잡혀 있다 — 번호 가드로 버려지지 않는 순서).
        early.open()
        await slow.value
        #expect(store.messageHistory.map(\.id) == ["m0", "s1"], "전송 전에 띄운 늦은 이력이 방금 보낸 말풍선을 지웠다")
        #expect(store.messageReadRuntime.confirmedSentRows["s1"] != nil, "그 id 를 모르는 응답에 장부가 지워졌다")

        after.open()
        await messageReadWait { messageReadIdle(store) && store.messageHistory.last?.readByPeer == true }
        let mine = store.messageHistory.filter { $0.id == "s1" }
        #expect(mine.count == 1, "서버 행과 로컬 행이 두 줄이 됐다")
        #expect(mine.first?.readByPeer == true, "그 id 를 실은 서버 이력이 로컬 행을 못 이겼다")
        #expect(store.messageReadRuntime.confirmedSentRows.isEmpty)
    }

    @Test(.gomokuDefaultsCleanup)
    func 서버가_60초_동안_모르면_서버가_이긴다() async {
        let (store, _) = makeMessageReadStore("msc-cap") { call, _ in
            switch call.rpc {
            case "message_history_with_reads":
                // 서버는 끝내 s1 을 싣지 않는다(복제 지연 · 보관 창 밖을 흉내 낸다).
                return Fx.historyReply([Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, epoch: Int(Fx.now.timeIntervalSince1970) - 120, unread: false)])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return mscOK(id: "s1")
            default: return nil
            }
        }
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "안녕")
        await mscWaitSent(store)
        #expect(store.messageHistory.map(\.id) == ["m0", "s1"], "60초 안인데 그 id 를 모르는 이력이 내 말을 지웠다")

        store.clock = { Fx.now.addingTimeInterval(59) }
        await store.performLoadMessageHistory()
        #expect(store.messageHistory.map(\.id) == ["m0", "s1"])

        store.clock = { Fx.now.addingTimeInterval(60) }
        await store.performLoadMessageHistory()
        #expect(store.messageHistory.map(\.id) == ["m0"], "60초가 지나도 서버가 모르는 로컬 행이 남았다")
        #expect(store.messageReadRuntime.confirmedSentRows.isEmpty)
    }

    // MARK: ③ 옛 서버

    @Test(.gomokuDefaultsCleanup)
    func 키_없는_옛_서버_응답은_이력_재조회로만_선다() async {
        let late = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("msc-legacy") { call, index in
            switch call.rpc {
            case "message_history_with_reads":
                guard index >= 1 else { return Fx.historyReply([]) }
                return Fx.historyReply([Fx.readsRow(id: "s1", peer: Fx.peerA, isMine: true, body: "안녕", readByPeer: false)], gate: late)
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return mscOK(id: nil)
            default: return nil
            }
        }
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "안녕")
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads") == 2 && !store.isSendingMessage }
        #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
        #expect(store.messageHistory.isEmpty, "옛 서버 응답으로 로컬 행을 지어냈다")
        #expect(store.messageReadRuntime.confirmedSentRows.isEmpty)
        #expect(!store.messageReadRuntime.sendLedger.serverConfirmsRows, "옛 서버인데 재시도 깃발이 섰다 — 재시도가 두 통을 만든다")

        late.open()
        await messageReadWait { messageReadIdle(store) && !store.messageHistory.isEmpty }
        #expect(store.messageHistory.map(\.id) == ["s1"], "옛 서버에서 이력 재조회가 내 말을 안 세웠다")
    }

    // MARK: ④ 응답 유실 재시도

    @Test(.gomokuDefaultsCleanup)
    func 깃발이_서면_5xx_뒤_같은_키로_한_번_다시_보낸다() async throws {
        let (store, host) = makeMessageReadStore("msc-retry") { call, index in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message":
                switch index {
                case 0: return mscOK(id: "s1", body: "첫 말")
                case 1: return msc504
                default: return mscOK(id: "s2", body: "둘째 말", offset: 40)
                }
            default: return nil
            }
        }
        let sleep = MessageReadSleepGate()
        store.messageSendRetrySleep = sleep.sleep
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "첫 말")
        await mscWaitSent(store)
        #expect(store.messageReadRuntime.sendLedger.serverConfirmsRows)

        store.messageNotice = nil
        store.sendMessage(to: Fx.peerA, body: "둘째 말")
        await messageReadWait { sleep.sleepers == 1 }
        #expect(sleep.requestedSeconds == [WorkTimerStore.messageSendRetryDelaySeconds])
        #expect(WorkTimerStore.messageSendRetryDelaySeconds == 1.5)
        #expect(store.isSendingMessage, "재시도를 기다리는 동안 잠금이 풀렸다 — 그 사이 두 번째 전송이 끼면 키가 둘이 된다")
        #expect(store.messageNotice == nil, "재시도 전에 실패 문구를 먼저 띄웠다")
        #expect(mscSendCalls(host).count == 2)

        sleep.open()
        await mscWaitSent(store)
        let calls = mscSendCalls(host)
        #expect(calls.count == 3, "응답 유실 재시도가 한 번이 아니다: \(calls.count - 1)건")
        let retryKey = try #require(mscKey(calls[2]))
        #expect(mscKey(calls[1]) == retryKey, "재시도가 다른 키로 나갔다 — 서버가 두 통으로 저장한다")
        #expect(mscKey(calls[0]) != retryKey, "다른 전송과 키가 같다")
        #expect(retryKey == retryKey.lowercased())
        #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
        #expect(store.messageHistory.filter { $0.id == "s2" }.count == 1)
        #expect(store.messageReadRuntime.sendLedger.unanswered.isEmpty, "재시도가 성공했는데 모호 기억이 남았다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 깃발이_없으면_5xx_는_재시도하지_않는다() async {
        let (store, host) = makeMessageReadStore("msc-noretry") { call, _ in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return msc504
            default: return nil
            }
        }
        store.messageSendRetrySleep = { _ in }
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "안녕")
        await mscWaitSent(store)
        #expect(mscSendCalls(host).count == 1, "키를 거른다는 증거 없이 재시도했다 — 옛 서버면 두 통이다")
        #expect(store.messageNotice == "연결이 불안정해요. 잠시 후 다시 시도해 주세요")
        #expect(store.messageReadRuntime.sendLedger.unanswered.count == 1, "답을 못 받은 전송을 기억하지 않았다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 재시도_대기_중_로그아웃하면_두_번째_요청이_없다() async {
        let (store, host) = makeMessageReadStore("msc-logout") { call, index in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return index == 0 ? mscOK(id: "s1") : msc504
            default: return nil
            }
        }
        let sleep = MessageReadSleepGate()
        store.messageSendRetrySleep = sleep.sleep
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "안녕")
        await mscWaitSent(store)
        store.sendMessage(to: Fx.peerA, body: "또")
        await messageReadWait { sleep.sleepers == 1 }

        store.clearPersistedSession()
        #expect(!store.messageReadRuntime.sendLedger.serverConfirmsRows, "로그아웃이 재시도 깃발을 안 지웠다")
        // 자는 동안 **다른 계정으로 다시 로그인**했다 — 가드가 없으면 앞 계정의 말이 새 토큰으로 나간다.
        store.session = SupabaseSession(accessToken: "access-token-2", refreshToken: nil, userID: mscPeerC)
        sleep.open()
        await messageReadWait(0.5) { mscSendCalls(host).count > 2 }
        #expect(mscSendCalls(host).count == 2, "로그아웃 뒤에 앞 계정의 재시도가 나갔다")
        #expect(store.messageReadRuntime.sendLedger.unanswered.isEmpty, "새 계정 장부에 앞 계정의 기억이 섰다")
        #expect(!store.isSendingMessage)
    }

    @Test(arguments: [
        (URLError(.timedOut) as Error, true),
        (URLError(.networkConnectionLost) as Error, true),
        (URLError(.cannotConnectToHost) as Error, true),
        (URLError(.notConnectedToInternet) as Error, true),
        (SupabaseWorkServiceError.invalidResponse(504) as Error, true),
        (SupabaseWorkServiceError.invalidResponse(500) as Error, true),
        (SupabaseWorkServiceError.invalidResponse(404) as Error, false),
        (SupabaseWorkServiceError.invalidResponse(400) as Error, false),
        (SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil) as Error, false),
        (SupabaseWorkServiceError.sessionExpired as Error, false),
        (SupabaseWorkServiceError.databaseSchemaMissing as Error, false),
        (URLError(.cancelled) as Error, false),
        (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")) as Error, false)
    ])
    func 모호한_실패의_판정표(error: Error, ambiguous: Bool) {
        #expect(WorkTimerStore.isAmbiguousMessageSendFailure(error) == ambiguous, "\(error)")
    }

    // MARK: ⑤ 멱등 키 재사용

    @Test(.gomokuDefaultsCleanup)
    func 모호한_실패_뒤_같은_본문은_같은_키_다른_본문과_확정_거절_뒤는_새_키() async throws {
        let (store, host) = makeMessageReadStore("msc-key") { call, index in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message":
                switch index {
                case 0, 1: return msc504                  // 답 없음 · 답 없음
                case 2, 3: return mscStatus("target_focused")   // 확정 거절 · 확정 거절
                default: return mscStatus("target_focused")
                }
            default: return nil
            }
        }
        await mscOpenConversation(store)
        func send(_ body: String) async {
            store.messageNotice = nil
            store.sendMessage(to: Fx.peerA, body: body)
            await mscWaitSent(store)
        }
        await send("밥?")            // 0: 504 — 기억
        await send("  밥?\n")        // 1: 전선 본문이 같다 → 같은 키(또 504)
        await send("밥 먹었어?")      // 2: 다른 본문 → 새 키(확정 거절)
        await send("밥?")            // 3: 여전히 기억 → 같은 키(확정 거절 → 잊음)
        await send("밥?")            // 4: 확정 답 뒤 → 새 키
        let keys = mscSendCalls(host).map(mscKey)
        #expect(keys.count == 5)
        let first = try #require(keys[0])
        #expect(keys[1] == first, "답을 못 받은 같은 말의 다시 보내기가 새 키로 나갔다 — 저장됐으면 두 통이다")
        #expect(keys[2] != first, "다른 본문에 같은 키를 실었다 — 서버가 앞 글을 돌려주고 새 글이 사라진다")
        #expect(keys[3] == first)
        #expect(keys[4] != first, "확정 거절을 받은 뒤에도 같은 키를 썼다")
        #expect(Set(keys.compactMap { $0 }).count == 3)
        #expect(store.messageReadRuntime.sendLedger.unanswered.isEmpty)
    }

    @Test(.gomokuDefaultsCleanup)
    func 다른_상대에게_같은_본문은_새_키() async throws {
        let (store, host) = makeMessageReadStore("msc-peer") { call, _ in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return msc504
            default: return nil
            }
        }
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "밥?")
        await mscWaitSent(store)
        store.messageNotice = nil
        store.sendMessage(to: Fx.peerB, body: "밥?")
        await mscWaitSent(store)
        let keys = mscSendCalls(host).map(mscKey)
        #expect(keys.count == 2 && keys[0] != nil && keys[0] != keys[1])
    }

    @Test
    func 장부는_10분_창과_상한을_지킨다() {
        var ledger = MessageSendLedger()
        let t0 = Fx.now
        let key = ledger.key(peer: "p", body: "밥?", now: t0)
        #expect(key == key.lowercased() && UUID(uuidString: key) != nil)
        ledger.rememberUnanswered(peer: "p", body: "밥?", key: key, at: t0)
        #expect(ledger.key(peer: "p", body: " 밥? ", now: t0.addingTimeInterval(599)) == key)
        // 같은 키의 두 번째 실패는 처음 시각을 지킨다(창은 첫 실패에서 잰다).
        ledger.rememberUnanswered(peer: "p", body: "밥?", key: key, at: t0.addingTimeInterval(300))
        #expect(ledger.key(peer: "p", body: "밥?", now: t0.addingTimeInterval(600)) != key, "10분이 지나도 옛 키를 썼다")
        #expect(ledger.unanswered.isEmpty)

        for index in 0..<(MessageSendLedger.capacity + 4) {
            ledger.rememberUnanswered(peer: "p", body: "말 \(index)", key: "k\(index)", at: t0)
        }
        #expect(ledger.unanswered.count == MessageSendLedger.capacity)
        #expect(ledger.unanswered.first?.key == "k4", "상한을 넘으면 오래된 것부터 버린다")
        ledger.settle(key: "k10")
        #expect(!ledger.unanswered.contains { $0.key == "k10" })
    }

    // MARK: ⑥ 이모티콘은 입력칸을 안 지운다

    @Test(.gomokuDefaultsCleanup)
    func 이모티콘_전송은_성공_실패_재시도_모두_입력칸_글을_지킨다() async {
        let (store, host) = makeMessageReadStore("msc-sticker") { call, index in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message":
                switch index {
                case 0: return mscOK(id: "s1", body: AingSticker.joy.token)      // 성공(깃발이 선다)
                case 1: return msc504                                            // 실패 →
                case 2: return mscOK(id: "s2", body: AingSticker.surprised.token, offset: 40)  // 재시도 성공
                default: return msc504                                           // 실패 → 재시도도 실패
                }
            default: return nil
            }
        }
        store.messageSendRetrySleep = { _ in }
        await mscOpenConversation(store)
        store.messageDraft = "쓰던 글"

        #expect(store.sendSticker(.joy))
        await mscWaitSent(store)
        #expect(store.messageDraft == "쓰던 글", "이모티콘 성공이 쓰던 글을 지웠다")
        #expect(store.messageHistory.first { $0.id == "s1" }?.body == AingSticker.joy.token)

        store.messageNotice = nil
        #expect(store.sendSticker(.surprised))
        await mscWaitSent(store)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 3, "전제: 재시도 한 번")
        #expect(store.messageDraft == "쓰던 글", "이모티콘 재시도 성공이 쓰던 글을 지웠다")

        store.messageNotice = nil
        #expect(store.sendSticker(.joy))
        await mscWaitSent(store)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 5)
        #expect(store.messageNotice == "연결이 불안정해요. 잠시 후 다시 시도해 주세요")
        #expect(store.messageDraft == "쓰던 글", "이모티콘 실패가 쓰던 글을 지웠다")
    }

    // MARK: ⑦ 안 읽음 · 목록 순서

    @Test(.gomokuDefaultsCleanup)
    func 내_행_삽입은_안_읽음과_목록_순서를_안_바꾼다() async {
        let late = MessageReadStubGate()
        let epoch = Int(Fx.now.timeIntervalSince1970)
        let (store, _) = makeMessageReadStore("msc-order") { call, index in
            switch call.rpc {
            case "message_history_with_reads":
                // B 가 보낸 안 읽은 말 하나 · A 와는 읽은 대화. 전송 뒤 조회는 붙잡아 둔다(삽입 직후의 판을 잰다).
                let rows = [
                    Fx.readsRow(id: "a0", peer: Fx.peerA, isMine: false, epoch: epoch - 300, unread: false, name: "가"),
                    Fx.readsRow(id: "b0", peer: Fx.peerB, isMine: false, epoch: epoch - 200, unread: true, name: "나")
                ]
                return Fx.historyReply(rows, gate: index >= 1 ? late : nil)
            case "message_unread_summary": return Fx.summaryReply([(Fx.peerB, 1)])
            case "mark_messages_read": return Fx.markReply()
            case "send_message": return mscOK(id: "s1", offset: 30)
            default: return nil
            }
        }
        store.pokeDirectory = [
            PokeDirectoryEntry(userID: Fx.peerA, name: "가", avatarURL: nil, isWorking: false),
            PokeDirectoryEntry(userID: Fx.peerB, name: "나", avatarURL: nil, isWorking: false),
            PokeDirectoryEntry(userID: mscPeerC, name: "다", avatarURL: nil, isWorking: true)
        ]
        await mscOpenConversation(store, peer: Fx.peerA)
        let unreadBefore = store.unreadMessagePeerIDs
        let orderBefore = PokePanelOrder.sorted(
            store.pokeDirectory, unreadMessagePeerIDs: store.unreadMessagePeerIDs, unreadPokePeerIDs: store.unreadPokePeerIDs
        ).map(\.userID)
        #expect(unreadBefore == [Fx.peerB], "전제: B 만 안 읽음")

        store.sendMessage(to: Fx.peerA, body: "안녕")
        await messageReadWait { store.messageHistory.contains { $0.id == "s1" } && !store.isSendingMessage }
        #expect(store.unreadMessagePeerIDs == unreadBefore, "내 말 한 줄이 안 읽음 집합을 바꿨다")
        #expect(store.hasUnreadMessages)
        let orderAfter = PokePanelOrder.sorted(
            store.pokeDirectory, unreadMessagePeerIDs: store.unreadMessagePeerIDs, unreadPokePeerIDs: store.unreadPokePeerIDs
        ).map(\.userID)
        #expect(orderAfter == orderBefore, "내 말 한 줄이 콕찌르기 목록 순서를 바꿨다")
        #expect(store.messageHistory.first { $0.id == "s1" }?.isUnread == nil)
        late.open()
        await messageReadWait { messageReadIdle(store) }
    }

    // MARK: 반박 검증 보강(2026-10-30) — 서버 저장 본문 · 이미 선 행 · 왕복 중 로그아웃

    /// K1: 서버만 하는 접기(빈 줄 셋 → 둘)가 걸린 글은 **서버가 ok 에 실은 저장 본문**으로 선다 — 클라 본문으로 세우면
    /// 다음 이력이 같은 id 로 갈아 끼울 때 글자가 한 번 바뀐다.
    @Test(.gomokuDefaultsCleanup)
    func 즉시_말풍선은_서버가_저장한_본문으로_선다() async {
        let late = MessageReadStubGate()
        let stored = "가\n\n나"
        let (store, host) = makeMessageReadStore("msc-body") { call, index in
            switch call.rpc {
            case "message_history_with_reads":
                guard index >= 1 else { return Fx.historyReply([]) }
                return Fx.historyReply([Fx.readsRow(id: "s1", peer: Fx.peerA, isMine: true, body: stored, epoch: Int(mscRoundedDate(offset: 30).timeIntervalSince1970), readByPeer: false)], gate: late)
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message": return mscOK(id: "s1", body: stored)
            default: return nil
            }
        }
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "가\n\n\n나")
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads") == 2 && !store.isSendingMessage }
        #expect(store.messageHistory.map(\.body) == [stored], "즉시 말풍선이 서버 저장 본문이 아니다 — 다음 이력에서 글자가 바뀐다")
        late.open()
        await messageReadWait { messageReadIdle(store) }
        #expect(store.messageHistory.map(\.body) == [stored])
        #expect(store.messageHistory.count == 1)
    }

    /// 왕복 중에 띄운 이력이 **먼저** 그 행을 실어 왔다(또는 재전송의 duplicate 가 이미 선 행을 돌려줬다) — ok 가 와도 한 줄이다.
    @Test(.gomokuDefaultsCleanup)
    func 이미_선_행에_ok_가_와도_한_줄이다() async {
        let sendGate = MessageReadStubGate()
        let late = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("msc-dup") { call, index in
            let s1 = Fx.readsRow(id: "s1", peer: Fx.peerA, isMine: true, body: "안녕", epoch: Int(mscRoundedDate(offset: 30).timeIntervalSince1970), readByPeer: false)
            switch call.rpc {
            case "message_history_with_reads":
                switch index {
                case 0: return Fx.historyReply([])
                case 1: return Fx.historyReply([s1])              // 왕복 중에 띄웠다 — 서버는 이미 저장했다
                default: return Fx.historyReply([s1], gate: late)  // ok 뒤에 따라오는 조회(붙잡아 둔다)
                }
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message":
                var reply = mscOK(id: "s1", duplicate: true)
                reply.gate = sendGate
                return reply
            default: return nil
            }
        }
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "안녕")
        await messageReadWait { mscSendCalls(host).count == 1 }
        await store.performLoadMessageHistory()
        #expect(store.messageHistory.map(\.id) == ["s1"], "전제: 왕복 중에 띄운 이력이 그 행을 먼저 세웠다")

        sendGate.open()
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads") == 3 && !store.isSendingMessage }
        #expect(store.messageHistory.filter { $0.id == "s1" }.count == 1, "이미 선 행에 ok 가 오자 말풍선이 두 개가 됐다")
        #expect(store.messageReadRuntime.confirmedSentRows.isEmpty, "넣지 않은 줄을 장부에 적었다")
        late.open()
        await messageReadWait { messageReadIdle(store) }
        #expect(store.messageHistory.map(\.id) == ["s1"])
    }

    /// 전송 왕복 중에 로그아웃하고 다른 계정으로 들어왔다 — 앞 계정의 ok 가 늦게 와도 새 계정의 이력·장부·깃발·문구에 서지 않는다.
    @Test(.gomokuDefaultsCleanup)
    func 전송_왕복_중_로그아웃하면_앞_계정의_말이_새_계정에_서지_않는다() async {
        let sendGate = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("msc-gen") { call, _ in
            switch call.rpc {
            case "message_history_with_reads": return Fx.historyReply([])
            case "message_unread_summary": return Fx.summaryReply([])
            case "send_message":
                var reply = mscOK(id: "s1")
                reply.gate = sendGate
                return reply
            default: return nil
            }
        }
        await mscOpenConversation(store)
        store.sendMessage(to: Fx.peerA, body: "안녕")
        await messageReadWait { mscSendCalls(host).count == 1 }

        store.clearPersistedSession()
        store.session = SupabaseSession(accessToken: "access-token-2", refreshToken: nil, userID: mscPeerC)
        let historyCalls = MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads")
        sendGate.open()
        await messageReadWait(0.5) { !store.messageHistory.isEmpty }
        #expect(store.messageHistory.isEmpty, "앞 계정의 말이 새 계정 이력에 섰다")
        #expect(store.messageReadRuntime.confirmedSentRows.isEmpty, "앞 계정의 줄이 새 계정 장부에 남았다")
        #expect(!store.messageReadRuntime.sendLedger.serverConfirmsRows, "앞 계정의 응답이 새 계정의 재시도 깃발을 세웠다")
        #expect(store.messageNotice != WorkTimerStore.messageSentNotice, "앞 계정의 결과 문구가 새 계정 화면에 섰다")
        #expect(MessageReadStubProtocol.count(host: host, rpc: "message_history_with_reads") == historyCalls)
    }
}
