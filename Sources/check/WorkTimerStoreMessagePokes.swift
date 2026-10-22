import Foundation
import CheckCore

// MARK: - 대화창 찌르기 기록 · 목록 안 읽음 (v0.3.65)
//
// 사용자 결정(2026-10-23, 원문):
//   "콕/메세지 창에서 메세지 안읽은 사람들이 제일 상단에 떴으면 좋겠어. 상단 정렬 순위가 1. 근무중이면서 메세지 아직 안읽은 사람,
//    2. 근무중 아니면서 메세지 아직 안읽은 사람, 3. 근무중이면서 메세지 다 읽거나 없는사람, 4. 근무중 아니면서 메세지 다 읽거나 없는 사람."
//   "사람들이 서로 찌르거나 울트라 찌르기 한거 메세지창에 기록으로 남게끔 해줘. 물론 이것도 24시간 뒤에 기록 사라지는건 동일하고."
//   묻고 정한 것: **안 본 찌르기도 '안 읽음'으로 친다** — 그 사람이 나를 찌른 것은 내가 그 대화를 열어 보기 전까지 안 읽음이다.
//
// ── 이 파일이 지키는 넷 ──
//  ① **조회 박자당 왕복 1회.** 찌르기 기록은 이력 조회(`message_history_with_pokes`)에 같이 온다. 그 함수가 없는 서버(404/PGRST202)면
//     예전 두 단계(`message_history_with_reads` → `message_history`)로 접고, 찌르기 기록·찌르기 안 읽음 없이 지금처럼 동작한다.
//     폴백은 캐시하지 않는다(`fetchMessageHistoryPreferringReads` 와 같은 판단 — db push 는 앱이 떠 있는 동안 끝난다).
//  ② **새 타이머 없음.** 받은 찌르기는 take_pokes 가 이미 들고 온 행을 기록에 **곧바로** 넣는다(메시지 M4 즉시 삽입과 같은 모양) —
//     목록 순서와 열린 대화가 왕복 없이 바뀐다. 보낸 찌르기는 그 사람과의 대화가 떠 있을 때만 이력을 한 번 받는다(이벤트 1회).
//  ③ **메뉴바 빨간 점 · "새 메시지" 알림은 메시지만**이다(`hasUnreadMessages` 는 그대로). 찌르기 안 읽음은 목록 순서와 행의 점에만 쓴다.
//  ④ 찌르기 기록은 `messageHistory` 와 **섞지 않는다**(`MessagePokeLog.swift` 머리 ②).

@MainActor
extension WorkTimerStore {
    // MARK: 파생값

    /// 안 본 찌르기가 있는 상대들(서버 플래그 − 낙관 읽음 − 차단으로 걷어낸 사람). 서버가 찌르기 기록을 모르면 빈 집합이다.
    var unreadPokePeerIDs: Set<String> {
        guard let snapshot = messagePokeLogSnapshot else { return [] }
        let unread = MessagePokeLogRules.unreadPeerIDs(
            log: messagePokeLog,
            snapshot: snapshot,
            optimistic: messagePokeOptimisticReads
        )
        return blockHiddenPeerIDs.isEmpty ? unread : unread.subtracting(blockHiddenPeerIDs)
    }

    /// 목록 순서 · 행의 점이 읽는 **안 읽음 합집합**(메시지 안 읽음 ∪ 안 본 찌르기). 메뉴바 점은 이것을 읽지 않는다(머리 ③).
    var unreadConversationPeerIDs: Set<String> {
        unreadMessagePeerIDs.union(unreadPokePeerIDs)
    }

    /// 지금 고른 사람과의 찌르기 기록(시간순).
    var selectedMessagePokeLog: [MessagePokeLogEntry] {
        guard let peer = selectedMessagePeerID else { return [] }
        return messagePokeLog.filter { $0.peerUserID == peer }
    }

    // MARK: 조회

    /// 이력 한 번 — 찌르기 기록까지 실어 오는 새 조회를 먼저, **그 함수가 없는 서버**면 예전 조회(읽음 칸 → 옛 이력)로 접는다.
    /// 401/403·5xx·네트워크는 접지 않고 던진다(`isMissingMessageReadFunction` — 일시 장애 한 번에 기록이 꺼지면 안 된다).
    func fetchConversationHistory(accessToken: String) async throws -> MessageConversationLoad {
        do {
            let result = try await service.fetchMessageHistoryWithPokes(
                accessToken: accessToken,
                hours: Self.messageHistoryHours,
                limit: Self.messageHistoryLimit
            )
            return MessageConversationLoad(
                history: MessageHistoryLoad(entries: result.messages, hasReadReceipts: true),
                pokes: result.pokes,
                chronology: result.chronology
            )
        } catch let error as SupabaseWorkServiceError where Self.isMissingMessageReadFunction(error) {
            let history = try await fetchMessageHistoryPreferringReads(accessToken: accessToken)
            return MessageConversationLoad(history: history, pokes: nil)
        }
    }

    /// 이력 응답의 찌르기 기록을 반영한다(`performLoadMessageHistory` 가 같은 응답·같은 일련번호로 부른다).
    ///
    /// · 서버가 모르면(`pokes == nil`) 기록·스냅샷·즉시 삽입 장부를 비운다 — 서버가 되돌아간 날 낡은 찌르기 점이 목록 맨 위를 붙들지 않게.
    /// · 즉시 삽입한 찌르기 중 **이 조회보다 나중에 넣은 것**은 남긴다(그 조회는 그 찌르기를 모를 수 있다 — 메시지 M4 와 같은 규칙).
    func applyMessagePokeLog(_ loaded: MessageConversationLoad, serial: Int) {
        let runtime = messageReadRuntime
        guard let serverPokes = loaded.pokes else {
            if !messagePokeLog.isEmpty { messagePokeLog = [] }
            if messagePokeLogSnapshot != nil { messagePokeLogSnapshot = nil }
            if !messagePokeChronology.isEmpty { messagePokeChronology = [:] }
            runtime.pokeLocalArrivalSerials = [:]
            return
        }
        let kept = runtime.survivingLocalPokeArrivals(historySerial: serial, current: messagePokeLog, server: serverPokes)
        // 서버 순서는 **서버 시각 순**으로 세운다 — 응답이 메시지·찌르기를 어떤 차례로 이어 붙여도 "마지막 받은 찌르기"가 흔들리지 않게.
        let serverSorted = MessagePokeLogRules.sorted(serverPokes, chronology: loaded.chronology)
        var serverOrder: [String: Int] = [:]
        for (index, entry) in serverSorted.enumerated() where serverOrder[entry.id] == nil { serverOrder[entry.id] = index }
        let merged = MessagePokeLogRules.sorted(
            serverPokes + kept,
            chronology: loaded.chronology,
            arrivalOrder: runtime.pokeLocalArrivalSerials
        )
        if messagePokeLog != merged { messagePokeLog = merged }
        if messagePokeChronology != loaded.chronology { messagePokeChronology = loaded.chronology }
        let snapshot = MessageHistoryReadSnapshot(serial: serial, serverOrder: serverOrder)
        if messagePokeLogSnapshot != snapshot { messagePokeLogSnapshot = snapshot }
    }

    // MARK: 받은 찌르기 · 보낸 찌르기 (머리 ②)

    /// take_pokes 가 **소비한** 행 중 찌르기(일반·울트라)를 기록에 곧바로 넣는다(drain 이 부른다). 반환값은 넣은 개수.
    ///
    /// · 서버가 찌르기 기록을 모르면 넣지 않는다 — 넣으면 다음 이력에서 사라지는(서버가 안 내려 주는) 줄이 된다.
    /// · 보관 창(24시간) 밖 · 이미 있는 id · 차단으로 걷어낸 사람 · 메시지 행 · 모르는 종류는 넣지 않는다(이력 디코더와 같은 종류 규칙).
    /// · 받은 것이므로 안 읽음이다. 그 사람과의 대화를 **보고 있으면** 곧바로 읽음 판정이 돈다(`evaluateMessageReadMarking`).
    @discardableResult
    func insertConsumedPokesIntoLog(rows: [TakenPokeRow]) -> Int {
        guard messagePokeLogSnapshot != nil, !rows.isEmpty else { return 0 }
        let horizon = clock().addingTimeInterval(-TimeInterval(Self.messageHistoryHours) * 3600)
        var known = Set(messagePokeLog.map(\.id))
        var additions: [MessagePokeLogEntry] = []
        for row in rows {
            // 종류는 **이력 디코더와 같은 규칙**(`MessagePokeLogKind(serverKind:)`)으로 가른다 — 'message' · 모르는 값은 건너뛴다.
            // `PokeKind(rawServerValue:)` 는 말풍선을 위해 모르는 값을 일반으로 접는데, 그 규칙을 여기 쓰면 미래 종류가 "콕 찔렀어요" 줄 ·
            // 안 읽음으로 들어갔다가 다음 이력(서버는 normal · ultra 만 내려 준다)에서 사라진다 — 그동안 그 사람은 점을 단 채 맨 위에 머문다.
            // kind 가 nil 인 행은 종류 칸이 생기기 전 옛 서버의 행이라 일반 찌르기다.
            guard let kind = MessagePokeLogKind(serverKind: row.kind ?? "normal") else { continue }
            guard !row.id.isEmpty, !row.fromUser.isEmpty, !known.contains(row.id),
                  !blockHiddenPeerIDs.contains(row.fromUser)
            else { continue }
            let createdAt = Date(timeIntervalSince1970: TimeInterval(row.createdEpoch))
            guard createdAt >= horizon else { continue }
            known.insert(row.id)
            additions.append(MessagePokeLogEntry(
                id: row.id,
                peerUserID: row.fromUser,
                peerName: row.fromDisplayName.isEmpty ? "사용자" : row.fromDisplayName,
                peerAvatarURL: row.fromAvatarUrl.flatMap { URL(string: $0) },
                createdAt: createdAt,
                isMine: false,
                kind: kind,
                isUnread: true
            ))
        }
        guard !additions.isEmpty else { return 0 }
        let runtime = messageReadRuntime
        // 한 줄에 번호 하나씩, take_pokes 행 순서(= 서버 created_at 순서)대로 — 같은 초 동률의 도착 순서표다(메시지 m4-fix 와 같다).
        for entry in additions { runtime.pokeLocalArrivalSerials[entry.id] = runtime.nextSerial() }
        let merged = MessagePokeLogRules.sorted(
            messagePokeLog + additions,
            chronology: messagePokeChronology,
            arrivalOrder: runtime.pokeLocalArrivalSerials
        )
        if messagePokeLog != merged { messagePokeLog = merged }
        evaluateMessageReadMarking()
        return additions.count
    }

    /// 찌르기를 보냈다(`sendPoke`·`sendUltraPoke` 의 성공 갈래). 그 사람과의 대화가 **떠 있을 때만** 이력을 한 번 받는다 —
    /// 보낸 행의 id 는 응답에 없어서 바로 넣을 수 없다. 대화가 안 떠 있으면 아무것도 안 한다: 대화를 여는 문(`openMessagePanel`)이
    /// 언제나 이력을 받으므로 그때 보인다(지금 화면 배치에서는 찌르기 목록과 대화가 동시에 뜨지 않는다 — 이 갈래는 그 배치가 바뀌는 날의 몫이다).
    func refreshConversationAfterPokeSent(to userID: String) {
        guard isMessageConversationOnScreen, selectedMessagePeerID == userID else { return }
        loadMessageHistory()
    }

    // MARK: 읽음 올리기 (판정은 `evaluateMessageReadMarking` 하나)

    /// 읽음 올리기 왕복 한 번.
    ///
    /// · 찌르기 경계가 없으면 **옛 호출 그대로**(`mark_messages_read {p_peer, p_through}`) — 옛 서버에서도 같은 본문이다.
    /// · 찌르기 경계가 있으면 `mark_conversation_read {p_peer, p_through_message?, p_through_poke}` 한 번(서버가 메시지 갈래를 옛 함수에
    ///   그대로 맡겨 읽음 신호까지 같다). 메시지 경계가 없으면 그 키를 싣지 않는다 — 서버는 null 갈래를 **안 움직인다**
    ///   (옛 함수의 null = "최신까지" 와 다르다: 찌르기만 보려고 연 순간 화면에 안 그린 메시지까지 읽음이 되면 안 된다).
    /// · 그 함수가 없는 서버(404/PGRST202)면 메시지 경계만 옛 함수로 한 번 더 부른다 — 찌르기 하나 때문에 메시지 읽음까지 못 올리면
    ///   상대 화면의 1 이 안 꺼진다. 찌르기만 올리던 호출이면 올릴 것이 없다(던진다 → 실패로 정산).
    func performConversationReadMark(
        accessToken: String,
        peer: String,
        throughMessageID: String?,
        throughPokeID: String?
    ) async throws -> ConversationReadMarkOutcome {
        guard let throughPokeID else {
            let response = try await service.markMessagesRead(
                accessToken: accessToken, peerUserID: peer, throughMessageID: throughMessageID
            )
            return ConversationReadMarkOutcome(messageMarked: response.isOK, pokeMarked: false)
        }
        do {
            let response = try await service.markConversationRead(
                accessToken: accessToken, peerUserID: peer, throughMessageID: throughMessageID, throughPokeID: throughPokeID
            )
            return ConversationReadMarkOutcome(messageMarked: response.isOK, pokeMarked: response.isOK)
        } catch let error as SupabaseWorkServiceError where Self.isMissingMessageReadFunction(error) {
            guard let throughMessageID else { throw error }
            let response = try await service.markMessagesRead(
                accessToken: accessToken, peerUserID: peer, throughMessageID: throughMessageID
            )
            return ConversationReadMarkOutcome(messageMarked: response.isOK, pokeMarked: false)
        }
    }

    /// 찌르기 낙관 읽음을 정산한다(`settleOptimisticRead` 의 짝). 그 사이 더 새 경계가 세워졌으면 건드리지 않는다.
    func settlePokeOptimisticRead(peer: String, through: String, succeeded: Bool) {
        guard var record = messagePokeOptimisticReads[peer], record.throughID == through, record.settledSerial == nil else {
            return
        }
        record.settledSerial = messageReadRuntime.nextSerial()
        record.failed = !succeeded
        messagePokeOptimisticReads[peer] = record
    }
}

/// 읽음 올리기 한 번의 결과 — 메시지 경계와 찌르기 경계가 **각자** 올랐는가(옛 서버로 접히면 메시지만 오른다).
struct ConversationReadMarkOutcome: Equatable, Sendable {
    var messageMarked: Bool
    var pokeMarked: Bool
}
