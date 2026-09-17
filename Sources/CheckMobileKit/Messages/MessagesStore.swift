import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 메시지 탭 스토어(SPEC-ios §3.3 · SPEC-ios-build D4). Foundation·Observation 만 쓴다 — macOS `swift test` 로 검증한다.
///
/// 자리 API(기반이 부르는 것 — 이름·모양을 지킨다)
/// - `init(context:)` — 앱 모델이 로그인 여부와 무관하게 한 번 만든다. 네트워크를 부르지 않는다(실시간 핸들러 등록만).
/// - `appDidBecomeActive()` — 로그인 상태에서 active 가 될 때 · active 인 채로 로그인이 끝났을 때.
/// - `appDidEnterBackground()` — background 로 갈 때(보이는 대화 표시를 내리고 기다리던 창을 닫는다).
/// - `reset()` — 로그아웃·치명 만료로 세대가 바뀐 직후(계정에 묶인 값을 전부 비운다).
/// - `badgeCount` — 탭 배지 = 안 읽은 메시지 수(서버 판정 − 낙관 읽음, `MessagesBadgeRules`).
/// - `didReceiveMessagePush(peerID:)` — 푸시 코디네이터(D9)가 메시지 푸시를 받았을 때(포그라운드) 부르는 새로고침 문.
///
/// ── 이 스토어가 지키는 것(맥 `WorkTimerStoreMessages` 의 v0.3.30~0.3.31 규칙을 폰 수명으로 옮긴 것) ──
/// ① **take_pokes 를 부르지 않는다.** 새 메시지는 실시간 신호·푸시·화면 표시가 **조회**(요약 · 이력)로 갚는다. iOS 서비스에는 그 메서드가
///    컴파일되지도 않는다(`SupabaseWorkServiceMacOnly.swift`).
/// ② **읽음은 서버가 판정한다.** 안 읽음은 서버 플래그(이력 `isUnread` · 요약), 경계는 메시지 id, 선후는 요청 일련번호다 — 시각을 비교하지 않는다.
///    읽음을 올리는 자리는 `evaluateReadMarking()` 하나다: **앱이 active 이고 그 대화 화면이 떠 있을 때만**.
/// ③ **메시지 활동 새로고침은 겹치지 않는다**(`requestActivityRefresh` — 돌고 있으면 뒤따르는 한 번으로 합친다).
///    그래도 모든 이력 응답은 **띄운 순서 번호**로 거른다 — 먼저 띄운 늦은 응답이 나중 응답이 그린 새 줄을 지우지 않는다(맥 M4 원칙).
/// ④ **열린 대화는 신호 뒤 곧바로 이력을 받는다**(스로틀 없음 — 실시간 러너의 1초 합치기만). 닫힌 대화는 요약만 받고 이력은 "낡음"으로 적어
///    다음에 화면이 서는 순간 받는다.
/// ⑤ 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정의 대화·점·경계·입력칸을 건드리지 않는다.
@MainActor
@Observable
package final class MessagesStore {
    @ObservationIgnored package let context: MobileContext

    // MARK: 이력 · 읽음

    /// 이력(오래된 것 → 최신, 같은 초는 서버 순서). 모든 대화가 이 한 배열에서 묶인다(`threads`).
    package private(set) var history: [MessageHistoryEntry] = []
    /// 읽음 칸을 실어 온 마지막 이력의 사실(요청 번호 · 서버 순서). nil = 아직 없거나 서버가 읽음을 모른다.
    package private(set) var historySnapshot: MessageHistoryReadSnapshot?
    /// 서버가 읽음 기능을 아는가(`message_history_with_reads` 성공). false 면 화면은 1 을 그리지 않는다.
    package private(set) var readReceiptsAvailable = false
    package private(set) var historyLoaded = false
    package private(set) var historyLoading = false
    package private(set) var historyFailed = false
    package private(set) var summary: MessageUnreadSummarySnapshot?
    package private(set) var optimisticReads: [String: MessageOptimisticRead] = [:]
    /// 읽음을 모르는 옛 서버용 도장(대화를 본 순간). 서버가 읽음을 알면 쓰이지 않는다.
    package private(set) var legacyReadStamps: [String: Date] = [:]

    // MARK: 사람 찾기

    package private(set) var directory: [PokeDirectoryEntry] = []
    package private(set) var directoryLoaded = false
    package private(set) var directoryLoading = false
    package private(set) var directoryFailed = false

    // MARK: 화면 · 입력

    package private(set) var isAppActive = false
    /// 메시지 탭의 대화 목록이 떠 있는가(탭 화면이 알린다).
    package private(set) var isListVisible = false
    /// 지금 떠 있는 대화 화면의 상대(여럿이면 마지막으로 선 것). 라우터의 `visibleConversationPeerID` 는 앱이 active 일 때만 이 값이다.
    package private(set) var openConversationPeerID: String?
    /// 상대별 입력 중인 글(대화를 나갔다 와도 남는다 · 로그아웃이면 비운다).
    package private(set) var drafts: [String: String] = [:]
    /// 보내기를 누른 뒤 서버 이력이 들고 올 때까지 대화 끝에 서는 자리 말풍선.
    package private(set) var pendingOutgoing: [MessagesPendingOutgoing] = []
    /// 상대별 전송 실패 안내(입력칸 위 한 줄). 성공은 문구를 세우지 않는다.
    package private(set) var sendNotices: [String: String] = [:]
    /// 전송 왕복 중인가. **한 번에 하나** — 순서가 곧 상대가 읽는 순서라 두 전송을 나란히 띄우지 않는다.
    package private(set) var isSending = false

    // MARK: 조절 값(테스트가 바꾼다)

    /// 목록이 설 때 이력을 다시 받는 최소 간격(초). 사이의 변화는 실시간 신호·푸시가 메운다. 낡음 표시가 있으면 무시한다.
    @ObservationIgnored package var listRefreshThrottleSeconds: TimeInterval = 15
    /// 사람 찾기 목록을 다시 받는 최소 간격(초).
    @ObservationIgnored package var directoryRefreshThrottleSeconds: TimeInterval = 60
    /// 읽음 처리 성공 뒤 요약을 다시 받기 전에 기다리는 창(초). 서버가 읽은 사람 채널로 되돌려 보내는 `message_read` 메아리가
    /// 그 안에 오면 그 새로고침이 이 몫을 맡는다(맥 m-fix2 · 부록 B-2). 소켓이 없으면 창이 닫힐 때 한 번 받는다.
    @ObservationIgnored package var postMarkRefreshSeconds: TimeInterval = 1.5
    /// 기다리기(테스트는 즉시 돌아오거나 손으로 푸는 것으로 바꾼다).
    @ObservationIgnored package var sleep: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }

    @ObservationIgnored private var runtime = MessagesRuntime()
    @ObservationIgnored private var registrations: [MobileRealtimeRegistration] = []

    package init(context: MobileContext) {
        self.context = context
        // 등록은 네트워크가 아니다. 핸들러가 스스로 로그인·active·세대를 확인한다(등록은 reset 뒤에도 살아 있다).
        registrations.append(context.onMessageActivity { [weak self] in self?.realtimeMessageActivity() })
        registrations.append(context.onMessageRead { [weak self] in self?.realtimeMessageRead() })
    }

    // MARK: - 자리 API

    package func appDidBecomeActive() {
        isAppActive = true
        syncRouterVisibility()
        guard isSignedIn else { return }
        // 포그라운드 진입: 요약은 언제나, 이력은 메시지 화면이 떠 있으면 곧바로(아니면 낡음으로 적고 화면이 설 때).
        requestActivityRefresh()
        evaluateReadMarking()
    }

    package func appDidEnterBackground() {
        isAppActive = false
        syncRouterVisibility()
        runtime.postMarkWindowTask?.cancel()
        runtime.postMarkWindowTask = nil
    }

    package func reset() {
        runtime.cancelAll()
        runtime = MessagesRuntime()
        history = []
        historySnapshot = nil
        readReceiptsAvailable = false
        historyLoaded = false
        historyLoading = false
        historyFailed = false
        summary = nil
        optimisticReads = [:]
        legacyReadStamps = [:]
        directory = []
        directoryLoaded = false
        directoryLoading = false
        directoryFailed = false
        isListVisible = false
        openConversationPeerID = nil
        drafts = [:]
        pendingOutgoing = []
        sendNotices = [:]
        isSending = false
        context.router.visibleConversationPeerID = nil
    }

    /// 탭 배지 = 안 읽은 메시지 수.
    package var badgeCount: Int {
        MessagesBadgeRules.unreadCount(
            history: history,
            historySnapshot: historySnapshot,
            summary: summary,
            optimistic: optimisticReads,
            legacyStamps: legacyReadStamps
        )
    }

    /// 메시지 푸시를 받았다(D9 — 포그라운드 표시 정책과 무관하게 부른다). 요약은 곧바로, 그 대화가 떠 있으면 이력도 곧바로.
    package func didReceiveMessagePush(peerID: String?) {
        guard isSignedIn else { return }
        let conversationOpen = peerID.map { $0 == openConversationPeerID } ?? false
        requestActivityRefresh(includeHistory: isAppActive && conversationOpen)
    }

    // MARK: - 파생값

    package var isSignedIn: Bool { context.session.isSignedIn }

    /// 대화 목록(최근 대화순). 같은 초는 서버 순서로 깬다.
    package var threads: [MessageThread] {
        MessageThreadBuilder.threads(from: history, serverOrder: historySnapshot?.serverOrder)
    }

    package var unreadPeerIDs: Set<String> {
        MessageUnreadRules.unreadPeerIDs(
            history: history,
            historySnapshot: historySnapshot,
            summary: summary,
            optimistic: optimisticReads,
            legacyStamps: legacyReadStamps
        )
    }

    package func thread(for peerID: String) -> MessageThread? {
        threads.first { $0.peerUserID == peerID }
    }

    /// 대화 머리 이름: 이력(가장 최신 이름) → 사람 찾기 목록 → nil.
    package func peerName(for peerID: String) -> String? {
        if let thread = thread(for: peerID) { return thread.peerName }
        return directory.first { $0.userID == peerID }?.name
    }

    package func peerAvatarURL(for peerID: String) -> URL? {
        if let url = thread(for: peerID)?.peerAvatarURL { return url }
        return directory.first { $0.userID == peerID }?.avatarURL
    }

    package func conversationItems(for peerID: String) -> [MessagesConversationItem] {
        MessagesConversationRules.items(
            messages: thread(for: peerID)?.messages ?? [],
            pending: pendingOutgoing.filter { $0.peerUserID == peerID },
            receiptsAvailable: readReceiptsAvailable,
            now: context.clock.now()
        )
    }

    package func draft(for peerID: String) -> String {
        drafts[peerID] ?? ""
    }

    package func setDraft(_ text: String, for peerID: String) {
        guard !peerID.isEmpty else { return }
        if drafts[peerID] != text { drafts[peerID] = text }
    }

    /// 확정된 입력으로 지금 보낼 수 있는가(왕복 중 아님 · 본문이 서버 경계 안). 근무 여부는 보지 않는다(서버도 안 본다 — v0.3.30).
    package func canSend(to peerID: String) -> Bool {
        guard isSignedIn, !peerID.isEmpty, !isSending else { return false }
        if case .ok = MessageBody.validate(draft(for: peerID)) { return true }
        return false
    }

    package func filteredDirectory(query: String) -> [PokeDirectoryEntry] {
        MessagesDirectoryRules.filter(directory, query: query)
    }

    // MARK: - 화면 사건(탭 화면이 부른다)

    package func listDidAppear() {
        isListVisible = true
        guard isSignedIn else { return }
        let now = context.clock.now()
        let due = !historyLoaded || runtime.historyStale
            || now.timeIntervalSince(runtime.lastListRefreshAt) >= listRefreshThrottleSeconds
        guard due else { return }
        runtime.lastListRefreshAt = now
        requestActivityRefresh(includeHistory: true)
    }

    package func listDidDisappear() {
        isListVisible = false
    }

    /// 당겨서 새로고침(스로틀 없음 — 사람이 직접 청한 것). 끝날 때까지 기다린다.
    package func refreshNow() async {
        guard isSignedIn else { return }
        runtime.lastListRefreshAt = context.clock.now()
        await requestActivityRefresh(includeHistory: true)?.value
    }

    /// 대화 화면이 섰다. `token` 은 뷰 인스턴스마다 다르다 — 같은 상대의 새 화면이 옛 화면의 사라짐보다 먼저 서도 표시가 꺼지지 않게.
    package func conversationDidAppear(peerID: String, token: UUID) {
        guard !peerID.isEmpty else { return }
        runtime.shownConversations.removeAll { $0.token == token }
        runtime.shownConversations.append((token, peerID))
        openConversationPeerID = peerID
        syncRouterVisibility()
        guard isSignedIn else { return }
        legacyReadStamps[peerID] = context.clock.now()
        evaluateReadMarking()
        // 대화가 서면 언제나 최신을 받는다(스로틀 없음 — 합치기만).
        requestActivityRefresh(includeHistory: true)
        if thread(for: peerID) == nil, !directoryLoaded {
            loadDirectory()
        }
    }

    package func conversationDidDisappear(token: UUID) {
        runtime.shownConversations.removeAll { $0.token == token }
        let current = runtime.shownConversations.last?.peerID
        if openConversationPeerID != current { openConversationPeerID = current }
        syncRouterVisibility()
    }

    // MARK: - 보내기

    /// [보내기]. **조합 중이면 보내지 않는다**(`isComposing` — 화면이 조합을 확정한 뒤 다시 부른다). 보냈으면(왕복을 띄웠으면) true.
    ///
    /// 누르는 즉시 입력칸을 비우고 자리 말풍선을 세운다(메신저 감각). 서버가 거절하면 말풍선을 거두고, 그 사이 새로 친 글이 없으면
    /// 입력칸에 글을 되돌리고 문구를 세운다 — **보내지 못한 글은 사라지지 않는다**(맥: "실패해도 글은 남는다").
    @discardableResult
    package func sendDraft(to peerID: String, isComposing: Bool) -> Bool {
        guard !isComposing, canSend(to: peerID) else { return false }
        guard case .ok(let body) = MessageBody.validate(draft(for: peerID)) else { return false }
        let generation = context.generation
        let localID = UUID().uuidString.lowercased()
        pendingOutgoing.append(MessagesPendingOutgoing(
            id: localID, peerUserID: peerID, body: body, createdAt: context.clock.now(), state: .sending
        ))
        drafts[peerID] = ""
        sendNotices[peerID] = nil
        isSending = true
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            var notice: String?
            var succeeded = false
            var cancelled = false
            var refreshesDirectory = false
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.sendMessage(accessToken: session.accessToken, to: peerID, body: body)
                }
                guard generation == self.context.generation else { return }
                let outcome = MessageSendOutcome(response: response)
                notice = MessagesSendRules.notice(for: outcome, maxLength: response.maxLength)
                succeeded = outcome == .ok
                refreshesDirectory = outcome == .targetNotWorking
            } catch {
                guard generation == self.context.generation else { return }
                if case .cancelled = AuthErrorRules.classify(error) {
                    cancelled = true
                } else {
                    notice = MessagesSendRules.connectionNotice
                }
            }
            self.isSending = false
            if succeeded {
                if let index = self.pendingOutgoing.firstIndex(where: { $0.id == localID }) {
                    self.pendingOutgoing[index].state = .sent(settledSerial: self.runtime.nextSerial())
                }
                // 방금 보낸 말이 서버 행으로 서게 이력을 곧바로 받는다(자리 말풍선은 그 응답이 거둔다).
                self.requestActivityRefresh(includeHistory: true)
                return
            }
            self.pendingOutgoing.removeAll { $0.id == localID }
            if self.draft(for: peerID).isEmpty { self.drafts[peerID] = body }
            if !cancelled, let notice { self.sendNotices[peerID] = notice }
            if refreshesDirectory { self.loadDirectory(force: true) }
        }
        return true
    }

    // MARK: - 사람 찾기

    /// `app_user_directory`(읽기). 새 대화 시트가 설 때 · 이름을 모르는 대화가 설 때.
    package func loadDirectory(force: Bool = false) {
        guard isSignedIn, !directoryLoading else { return }
        let now = context.clock.now()
        if !force, directoryLoaded, now.timeIntervalSince(runtime.lastDirectoryLoadAt) < directoryRefreshThrottleSeconds { return }
        runtime.lastDirectoryLoadAt = now
        let generation = context.generation
        directoryLoading = true
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rows = try await self.context.withMobileSessionRetry { session in
                    try await service.fetchPokeDirectory(accessToken: session.accessToken)
                }
                guard generation == self.context.generation else { return }
                self.directoryLoading = false
                self.directory = rows.toPokeDirectoryEntries().sortedForPokeDisplay()
                self.directoryLoaded = true
                self.directoryFailed = false
            } catch {
                guard generation == self.context.generation else { return }
                self.directoryLoading = false
                if case .cancelled = AuthErrorRules.classify(error) { return }
                if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                    self.directoryLoaded = true
                } else {
                    self.directoryFailed = true
                }
            }
        }
    }

    // MARK: - 메시지 활동 새로고침

    /// 요약 1회(+ 메시지 화면이 떠 있거나 `includeHistory` 면 이력 1회 — 나란히). 돌고 있으면 뒤따르는 한 번으로 합친다.
    /// 이력을 건너뛰면 "낡음"을 적어 다음에 화면이 설 때 스로틀과 무관하게 받는다.
    @discardableResult
    package func requestActivityRefresh(includeHistory: Bool = false) -> Task<Void, Never>? {
        guard isSignedIn else { return nil }
        if includeHistory || isMessagesScreenVisible {
            runtime.activityWantsHistory = true
        } else {
            runtime.historyStale = true
        }
        if let running = runtime.activityTask {
            runtime.activityAgain = true
            return running
        }
        let generation = context.generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                // 루프 안에서 먼저 내린다 — 이번 조회가 도는 동안 온 계기를 지우지 않게.
                self.runtime.activityAgain = false
                let wantsHistory = self.runtime.activityWantsHistory
                self.runtime.activityWantsHistory = false
                if wantsHistory {
                    async let summaryDone: Void = self.performLoadSummary()
                    async let historyDone: Void = self.performLoadHistory()
                    _ = await (summaryDone, historyDone)
                } else {
                    await self.performLoadSummary()
                }
                guard generation == self.context.generation else { return }
            } while self.runtime.activityAgain
            self.runtime.activityTask = nil
        }
        runtime.activityTask = task
        return task
    }

    /// 이력 1회. 모든 이력 조회가 이 문을 지난다 — **띄운 순서 번호**가 반영 여부를 정한다.
    package func performLoadHistory() async {
        guard isSignedIn else { return }
        let generation = context.generation
        let serial = runtime.nextSerial()
        runtime.lastHistoryLaunchSerial = serial
        runtime.historyInFlight += 1
        if !historyLoading { historyLoading = true }
        defer {
            if generation == context.generation {
                runtime.historyInFlight -= 1
                if runtime.historyInFlight == 0, historyLoading { historyLoading = false }
            }
        }
        do {
            let loaded = try await context.withMobileSessionRetry { session in
                try await fetchHistoryPreferringReads(accessToken: session.accessToken)
            }
            guard generation == context.generation else { return }
            // 더 나중에 띄운 조회가 이미 반영됐다 — 이 응답은 그보다 낡은 서버 상태다(새 줄·꺼진 1 을 되돌리면 안 된다).
            guard serial > runtime.lastAppliedHistorySerial else { return }
            runtime.lastAppliedHistorySerial = serial
            if let staleSince = runtime.historyStaleSerial, serial > staleSince {
                runtime.historyStaleSerial = nil
            }
            let previousIDs = Set(history.map(\.id))
            let sorted = loaded.entries.sortedForMessageHistory(serverOrder: loaded.hasReadReceipts ? loaded.serverOrder : nil)
            if history != sorted { history = sorted }
            if loaded.hasReadReceipts {
                let snapshot = MessageHistoryReadSnapshot(serial: serial, serverOrder: loaded.serverOrder)
                if historySnapshot != snapshot { historySnapshot = snapshot }
                if !readReceiptsAvailable { readReceiptsAvailable = true }
            } else {
                if historySnapshot != nil { historySnapshot = nil }
                if readReceiptsAvailable { readReceiptsAvailable = false }
            }
            let reconciled = MessagesPendingRules.reconcile(
                pending: pendingOutgoing, previousHistoryIDs: previousIDs, applied: sorted, appliedSerial: serial
            )
            if reconciled != pendingOutgoing { pendingOutgoing = reconciled }
            if !historyLoaded { historyLoaded = true }
            if historyFailed { historyFailed = false }
            // 새 이력 — 떠 있는 대화에 서버 기준 안 읽은 말이 있으면 올린다(새로 도착한 말 포함).
            evaluateReadMarking()
        } catch {
            guard generation == context.generation else { return }
            if case .cancelled = AuthErrorRules.classify(error) { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 두 이력 함수가 다 없는 서버 — 실패가 아니라 "받을 것이 없다". 빈 이력으로 조용히 접는다.
                if !historyLoaded { historyLoaded = true }
                if readReceiptsAvailable { readReceiptsAvailable = false }
                runtime.historyStaleSerial = nil
            } else {
                if !historyFailed { historyFailed = true }
            }
        }
    }

    /// `message_history_with_reads` → 없는 서버(404/PGRST202)면 옛 `message_history`(읽음 모름). 폴백은 캐시하지 않는다(맥과 같은 판단).
    private func fetchHistoryPreferringReads(accessToken: String) async throws -> MessageHistoryLoad {
        do {
            let entries = try await context.service.fetchMessageHistoryWithReads(
                accessToken: accessToken,
                hours: MessageNoticeText.historyHours,
                limit: MessageNoticeText.historyLimit
            )
            return MessageHistoryLoad(entries: entries, hasReadReceipts: true)
        } catch let error as SupabaseWorkServiceError where Self.isMissingFunction(error) {
            let entries = try await context.service.fetchMessageHistory(
                accessToken: accessToken,
                hours: MessageNoticeText.historyHours,
                limit: MessageNoticeText.historyLimit
            )
            return MessageHistoryLoad(entries: entries, hasReadReceipts: false)
        }
    }

    /// "이 서버에는 그 함수가 없다"(맥 `isMissingMessageReadFunction` 과 같은 판정). 401/403·5xx·네트워크는 넣지 않는다.
    package nonisolated static func isMissingFunction(_ error: SupabaseWorkServiceError) -> Bool {
        switch error {
        case .databaseSchemaMissing: return true
        case .invalidResponse(let status): return status == 404
        default: return false
        }
    }

    /// 요약 1회.
    package func performLoadSummary() async {
        guard isSignedIn else { return }
        let generation = context.generation
        let serial = runtime.nextSerial()
        runtime.lastSummaryLaunchSerial = serial
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await context.service.fetchMessageUnreadSummary(accessToken: session.accessToken)
            }
            guard generation == context.generation else { return }
            guard let value = response.summary else { return }
            // 늦게 온 옛 요약이 새 요약을 덮지 않게(이력과 같은 번호 규칙).
            guard serial > (summary?.serial ?? 0) else { return }
            let snapshot = MessageUnreadSummarySnapshot(serial: serial, summary: value)
            if summary != snapshot { summary = snapshot }
        } catch {
            // 함수 없음·장애 — 요약 없이 이력(또는 옛 도장) 기준으로 산다. 문구를 세우지 않는다(배지 재료일 뿐이다).
        }
    }

    // MARK: - 읽음

    /// **읽음을 올리는 유일한 자리.** 앱 active · 그 대화 화면이 떠 있음 · 서버 기준 안 읽은 받은 말이 있음 — 셋이 다 맞을 때만.
    package func evaluateReadMarking() {
        guard isSignedIn, isAppActive,
              let peer = openConversationPeerID,
              let snapshot = historySnapshot,
              let through = MessageUnreadRules.markTarget(
                  peer: peer, history: history, snapshot: snapshot, optimistic: optimisticReads[peer]
              )
        else { return }
        markRead(peer: peer, through: through)
    }

    /// 읽음 처리 1회. 상대별로 겹치지 않는다(날아가는 중이면 끝난 뒤 한 번 더 판정). 응답 전에 낙관 읽음으로 점·배지를 곧바로 끈다 —
    /// 실패해도 되돌리지 않고(정산만), 그보다 나중에 띄운 서버 조회가 사실을 말한다.
    private func markRead(peer: String, through: String) {
        guard !runtime.markInFlight.contains(peer) else {
            runtime.markAgain.insert(peer)
            return
        }
        runtime.markInFlight.insert(peer)
        let record = MessageOptimisticRead(throughID: through, recordedSerial: runtime.nextSerial())
        if optimisticReads[peer] != record { optimisticReads[peer] = record }
        let generation = context.generation
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            var succeeded = false
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.markMessagesRead(accessToken: session.accessToken, peerUserID: peer, throughMessageID: through)
                }
                succeeded = response.isOK
            } catch {
                // 취소·네트워크·함수 없음 — "이번엔 못 올렸다". 낙관 표시는 되돌리지 않는다.
            }
            guard generation == self.context.generation else { return }
            self.runtime.markInFlight.remove(peer)
            self.settleOptimisticRead(peer: peer, through: through, succeeded: succeeded)
            if succeeded { self.schedulePostMarkRefresh() }
            if self.runtime.markAgain.remove(peer) != nil { self.evaluateReadMarking() }
        }
    }

    private func settleOptimisticRead(peer: String, through: String, succeeded: Bool) {
        guard var record = optimisticReads[peer], record.throughID == through, record.settledSerial == nil else { return }
        record.settledSerial = runtime.nextSerial()
        record.failed = !succeeded
        optimisticReads[peer] = record
    }

    /// 읽음 성공 뒤 요약을 한 번 — 창 안에 다른 새로고침(메아리 신호 등)이 이미 떴으면 그것이 맡는다.
    private func schedulePostMarkRefresh() {
        runtime.postMarkPendingSerial = runtime.serial
        guard runtime.postMarkWindowTask == nil else { return }
        let generation = context.generation
        let seconds = postMarkRefreshSeconds
        let sleep = sleep
        runtime.postMarkWindowTask = Task { @MainActor [weak self] in
            await sleep(seconds)
            guard let self, !Task.isCancelled, generation == self.context.generation else { return }
            self.runtime.postMarkWindowTask = nil
            guard self.runtime.lastSummaryLaunchSerial <= self.runtime.postMarkPendingSerial else { return }
            self.requestActivityRefresh()
        }
    }

    // MARK: - 실시간 핸들러

    private func realtimeMessageActivity() {
        guard isSignedIn, isAppActive else { return }
        requestActivityRefresh()
    }

    private func realtimeMessageRead() {
        guard isSignedIn, isAppActive else { return }
        requestActivityRefresh()
    }

    // MARK: - 내부

    /// 메시지 화면(목록 또는 대화)이 지금 보이는가.
    private var isMessagesScreenVisible: Bool {
        isAppActive && (isListVisible || openConversationPeerID != nil)
    }

    private func syncRouterVisibility() {
        let visible = isAppActive ? openConversationPeerID : nil
        if context.router.visibleConversationPeerID != visible {
            context.router.visibleConversationPeerID = visible
        }
    }

    // MARK: - 테스트 창구

    /// 기다리는 새로고침·읽음 창(테스트가 끝날 때까지 기다린다).
    package var pendingActivityTask: Task<Void, Never>? { runtime.activityTask }
    package var pendingPostMarkTask: Task<Void, Never>? { runtime.postMarkWindowTask }
    package var isMarkingRead: Bool { !runtime.markInFlight.isEmpty }
    package var isHistoryStale: Bool { runtime.historyStale }
}

/// 비관찰 장부. 로그아웃이 통째로 새것으로 바꾼다(옛 작업이 새 장부를 만지지 않게 — 세대 가드와 함께).
@MainActor
private final class MessagesRuntime {
    private(set) var serial = 0
    var lastAppliedHistorySerial = 0
    var lastHistoryLaunchSerial = 0
    var lastSummaryLaunchSerial = 0
    var historyInFlight = 0
    var activityTask: Task<Void, Never>?
    var activityAgain = false
    var activityWantsHistory = false
    /// 이력을 건너뛴 계기의 순간(그보다 나중에 띄운 이력이 반영되면 내린다). nil = 낡지 않음.
    var historyStaleSerial: Int?
    var lastListRefreshAt: Date = .distantPast
    var lastDirectoryLoadAt: Date = .distantPast
    var markInFlight: Set<String> = []
    var markAgain: Set<String> = []
    var postMarkWindowTask: Task<Void, Never>?
    var postMarkPendingSerial = 0
    var shownConversations: [(token: UUID, peerID: String)] = []

    nonisolated init() {}

    var historyStale: Bool {
        get { historyStaleSerial != nil }
        set { historyStaleSerial = newValue ? serial : nil }
    }

    func nextSerial() -> Int {
        serial += 1
        return serial
    }

    func cancelAll() {
        activityTask?.cancel()
        activityTask = nil
        postMarkWindowTask?.cancel()
        postMarkWindowTask = nil
    }
}
