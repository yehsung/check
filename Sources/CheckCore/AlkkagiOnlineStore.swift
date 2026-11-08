import Foundation
import Observation

/// Server snapshots are authoritative. This store never advances the game or runs a frame loop.
@Observable @MainActor
package final class AlkkagiOnlineStore {
    package private(set) var users: [AlkkagiPeer] = []
    package private(set) var incoming: [AlkkagiInvite] = []
    package private(set) var outgoing: AlkkagiInvite?
    package private(set) var me: AlkkagiPeer?
    package private(set) var state: AlkkagiMatch?
    package private(set) var chat: [AlkkagiChatMessage] = []
    package private(set) var notice: String?
    package private(set) var isBusy = false
    package private(set) var isLoading = false
    package private(set) var isSendingChat = false
    package private(set) var serverMissing = false
    package private(set) var isWindowVisible = false
    package private(set) var isWindowOccluded = false
    package var hiddenPeerIDs: Set<String> = [] {
        didSet {
            guard hiddenPeerIDs != oldValue else { return }
            users = users.filter { !isPeerHidden($0.id) }
            incoming = incoming.filter { !isPeerHidden($0.opponent.id) }
            if let outgoing, isPeerHidden(outgoing.opponent.id) { self.outgoing = nil }
            scheduleInviteExpiry()
            if isAvailable { requestSync() }
        }
    }

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (AlkkagiInvite) -> Void)?
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?

    @ObservationIgnored var service: (any AlkkagiServing)?
    @ObservationIgnored package private(set) var resetGeneration = 0
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let pollSeconds: Double
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var inviteExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var lastLobbyRefresh: Date?
    @ObservationIgnored private var pendingLobby = false
    @ObservationIgnored private var pendingUsers = false
    @ObservationIgnored private var pendingMatch = false
    @ObservationIgnored private var focusMatchID: UUID?
    @ObservationIgnored private var matchGeneration = 0
    @ObservationIgnored private var muteGeneration = 0
    @ObservationIgnored private var requestSequence = 0
    @ObservationIgnored private var lobbySequence = 0
    @ObservationIgnored private var clockSequence = 0
    @ObservationIgnored private var seenInviteIDs: Set<String> = []
    @ObservationIgnored private var seenFinishedMatchIDs: Set<String> = []
    @ObservationIgnored private var dismissedMatchIDs: Set<String> = []
    @ObservationIgnored private var refreshedDeadline: String?
    private var serverClockOffsetMs: Double?
    private var isAvailable = false

    package init(service: (any AlkkagiServing)? = nil, clock: @escaping () -> Date = Date.init,
                 pollSeconds: Double = 3) {
        self.service = service
        self.clock = clock
        self.pollSeconds = pollSeconds.isFinite && pollSeconds > 0 ? pollSeconds : 3
    }

    deinit {
        syncTask?.cancel()
        pollTask?.cancel()
        deadlineTask?.cancel()
        inviteExpiryTask?.cancel()
    }

    package var estimatedServerNowMs: Double {
        let now = clock().timeIntervalSince1970 * 1000 + (serverClockOffsetMs ?? 0)
        return now.isFinite ? now : 0
    }

    package var remainingSeconds: Double {
        guard let state, let deadline = state.deadlineMs,
              state.phase != .finished, deadline.isFinite else { return 0 }
        if state.phase == .rolling {
            guard let shot = state.shot, shot.startedAtMs.isFinite else { return 0 }
            return max(0, (deadline - shot.startedAtMs) / 1000)
        }
        return max(0, (deadline - estimatedServerNowMs) / 1000)
    }

    package var isMyTurn: Bool {
        guard let state else { return false }
        switch state.phase {
        case .placing: return !state.myReady
        case .aiming: return state.currentPlayer == state.myColor
        case .rolling, .finished, .unknown: return false
        }
    }

    package var canPlace: Bool {
        canAct && isMyTurn && state?.phase == .placing
    }

    package var canShoot: Bool {
        canAct && isMyTurn && state?.phase == .aiming
    }

    private var canAct: Bool {
        guard service != nil, isAvailable, !serverMissing, !isBusy,
              serverClockOffsetMs != nil, let state, let deadline = state.deadlineMs else { return false }
        return deadline > estimatedServerNowMs
    }

    package func challenge(opponentID: String) async {
        guard !isBusy, isAvailable, state == nil, outgoing == nil,
              !isPeerHidden(opponentID),
              let opponent = UUID(uuidString: opponentID),
              opponent != me.flatMap({ UUID(uuidString: $0.id) }),
              users.first(where: { UUID(uuidString: $0.id) == opponent })?.busy != true else { return }
        await act(.challenge(opponentID: opponent, actionID: UUID()))
    }

    package func respond(inviteID: String, accept: Bool) async {
        guard !isBusy, isAvailable, state == nil, let id = UUID(uuidString: inviteID),
              let invite = incoming.first(where: { UUID(uuidString: $0.id) == id }) else { return }
        guard invite.expiresAtMs > estimatedServerNowMs else {
            await refreshLobby()
            return
        }
        let generation = resetGeneration
        let response = await act(.respond(matchID: id, accept: accept, actionID: UUID()))
        if generation == resetGeneration, response?.status == .ok {
            incoming.removeAll { UUID(uuidString: $0.id) == id }
        }
    }

    package func cancelChallenge() async {
        guard !isBusy, let outgoing, let id = UUID(uuidString: outgoing.id) else { return }
        let generation = resetGeneration
        let response = await act(.cancel(matchID: id, actionID: UUID()))
        if generation == resetGeneration, response?.status == .ok,
           self.outgoing.flatMap({ UUID(uuidString: $0.id) }) == id { self.outgoing = nil }
    }

    package func place(stoneID: Int, at position: AlkkagiVector) async {
        guard canPlace, let state, let id = UUID(uuidString: state.id),
              state.canonicalGame?.canPlace(stoneID: stoneID, at: position) == true else { return }
        await act(.place(matchID: id, expectedPlacementRevision: state.placementRevision, stoneID: stoneID,
                         position: position, actionID: UUID()))
    }

    package func confirmPlacement() async {
        guard canPlace, let state, let id = UUID(uuidString: state.id) else { return }
        let ownStones = state.stones.filter { $0.owner == state.myColor }
        guard ownStones.count == 5, ownStones.allSatisfy({ $0.isPlaced && !$0.isOut }) else { return }
        await act(.ready(matchID: id, expectedPlacementRevision: state.placementRevision, actionID: UUID()))
    }

    package func shoot(stoneID: Int, pull: AlkkagiVector, actionID: UUID? = nil) async {
        guard canShoot, let state, let id = UUID(uuidString: state.id),
              var game = state.canonicalGame, game.shoot(stoneID: stoneID, pull: pull) else { return }
        await act(.shoot(matchID: id, expectedRevision: state.revision, stoneID: stoneID,
                         pull: pull, actionID: actionID ?? UUID()))
    }

    package func resign() async {
        guard !isBusy, let state, state.phase != .finished,
              let id = UUID(uuidString: state.id) else { return }
        await act(.resign(matchID: id, expectedRevision: state.revision, actionID: UUID()))
    }

    package func sendChat(body: String) async {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSendingChat, isAvailable, let state, !state.muted,
              let id = UUID(uuidString: state.id) else { return }
        guard !body.isEmpty, body.unicodeScalars.count <= 100 else {
            notice = "대화는 100자까지 보낼 수 있어요."
            return
        }
        let generation = resetGeneration
        isSendingChat = true
        defer { if generation == resetGeneration { isSendingChat = false } }
        _ = await perform(.chatSend(matchID: id, body: body, actionID: UUID()))
    }

    package func setMuted(_ muted: Bool) async {
        guard !isBusy, let state, state.muted != muted,
              let id = UUID(uuidString: state.id) else { return }
        muteGeneration &+= 1
        let generation = resetGeneration
        let response = await act(.chatMute(matchID: id, muted: muted, actionID: UUID()))
        if generation == resetGeneration, response?.status == .ok,
           self.state.flatMap({ UUID(uuidString: $0.id) }) == id { self.state?.muted = muted }
    }

    package func leaveFinishedMatch() async {
        guard !isBusy, let state, state.phase == .finished,
              let id = UUID(uuidString: state.id) else { return }
        let generation = resetGeneration
        let response = await act(.leave(matchID: id, expectedRevision: state.revision, actionID: UUID()))
        guard generation == resetGeneration, response?.status == .ok,
              self.state.flatMap({ UUID(uuidString: $0.id) }) == id else { return }
        dismissedMatchIDs.insert(id.uuidString.lowercased())
        matchGeneration &+= 1
        self.state = nil
        chat = []
        focusMatchID = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        await refreshLobby()
    }

    package func refreshLobby() async { await synchronize(lobby: true, match: false, users: true) }
    package func refreshMatch() async { await synchronize(lobby: false, match: true) }

    package func refreshLobbyIfStale() {
        guard lastLobbyRefresh.map({ clock().timeIntervalSince($0) >= 60 }) ?? true else { return }
        requestSync()
    }

    package func handleSignal() { requestSync() }
    package func realtimeDidJoin() { requestSync() }
    package func systemDidWake() { requestSync() }

    package func openWindow(focusMatchID: String? = nil) {
        self.focusMatchID = focusMatchID.flatMap(UUID.init(uuidString:))
        requestSync()
        presentWindow?()
    }

    package func windowDidShow() {
        isWindowVisible = true
        if !isWindowOccluded {
            startPolling()
            scheduleDeadlineRefresh()
            requestSync()
        }
    }

    package func windowDidHide() {
        isWindowVisible = false
        isWindowOccluded = false
        stopPolling()
    }

    package func windowDidClose() {
        windowDidHide()
        if state?.phase == .finished {
            let generation = resetGeneration
            Task { @MainActor [weak self] in
                guard let self, generation == self.resetGeneration else { return }
                await self.leaveFinishedMatch()
            }
        }
    }

    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible && isWindowVisible {
            startPolling()
            scheduleDeadlineRefresh()
            requestSync()
        } else {
            stopPolling()
        }
    }

    /// Clears account state but deliberately retains the injected service/weak-host adapter.
    package func reset() {
        resetGeneration &+= 1
        matchGeneration &+= 1
        muteGeneration &+= 1
        syncTask?.cancel()
        syncTask = nil
        stopPolling()
        inviteExpiryTask?.cancel()
        inviteExpiryTask = nil
        lastLobbyRefresh = nil
        pendingLobby = false
        pendingUsers = false
        pendingMatch = false
        focusMatchID = nil
        users = []
        incoming = []
        outgoing = nil
        me = nil
        state = nil
        chat = []
        notice = nil
        isBusy = false
        isLoading = false
        isSendingChat = false
        serverMissing = false
        isAvailable = false
        hiddenPeerIDs = []
        isWindowVisible = false
        isWindowOccluded = false
        serverClockOffsetMs = nil
        seenInviteIDs = []
        seenFinishedMatchIDs = []
        dismissedMatchIDs = []
        refreshedDeadline = nil
        requestSequence = 0
        lobbySequence = 0
        clockSequence = 0
        dismissWindow?()
    }

    private struct RequestContext {
        let generation: Int
        let matchGeneration: Int
        let muteGeneration: Int
        let sequence: Int
        let sentAtMs: Double
    }

    @discardableResult
    private func act(_ call: AlkkagiCall) async -> AlkkagiResponse? {
        guard !isBusy, service != nil else { return nil }
        let generation = resetGeneration
        isBusy = true
        notice = nil
        defer { if generation == resetGeneration { isBusy = false } }
        return await perform(call)
    }

    private func perform(_ call: AlkkagiCall) async -> AlkkagiResponse? {
        guard let service else { return nil }
        requestSequence &+= 1
        let context = RequestContext(generation: resetGeneration, matchGeneration: matchGeneration,
                                     muteGeneration: muteGeneration, sequence: requestSequence,
                                     sentAtMs: clock().timeIntervalSince1970 * 1000)
        do {
            let response = try await service.call(call)
            guard context.generation == resetGeneration, !Task.isCancelled else { return nil }
            guard response.protocolVersion == 1, response.serverNowMs.isFinite else {
                isAvailable = false
                notice = "앱을 업데이트한 뒤 다시 시도해 주세요."
                return nil
            }
            if context.sequence >= clockSequence {
                let receivedAtMs = clock().timeIntervalSince1970 * 1000
                let midpoint = context.sentAtMs / 2 + receivedAtMs / 2
                let offset = response.serverNowMs - midpoint
                if midpoint.isFinite, offset.isFinite {
                    serverClockOffsetMs = offset
                    clockSequence = context.sequence
                }
            }
            if response.status == .notSignedIn {
                reset()
                return nil
            }
            guard response.status != .unsupportedClient, response.status != .unknown else {
                isAvailable = false
                notice = "앱을 업데이트한 뒤 다시 시도해 주세요."
                return nil
            }
            if let state = response.state, state.canonicalGame == nil {
                isAvailable = false
                notice = "대전을 다시 불러와 주세요."
                return nil
            }
            serverMissing = false
            isAvailable = true
            apply(response, for: call, context: context)
            guard context.generation == resetGeneration else { return nil }
            notice = notice(for: response.status)
            return response
        } catch {
            guard context.generation == resetGeneration, !Task.isCancelled,
                  !(error is CancellationError) else { return nil }
            switch error as? AlkkagiServiceError {
            case .serverMissing:
                serverMissing = true
                isAvailable = false
                notice = "아직 온라인 대전을 사용할 수 없어요."
            case .notSignedIn:
                reset()
            case .unavailable:
                isAvailable = false
                notice = "로그인한 뒤 다시 시도해 주세요."
            default:
                notice = "연결을 확인하고 다시 시도해 주세요."
            }
            return nil
        }
    }

    private func apply(_ response: AlkkagiResponse, for call: AlkkagiCall, context: RequestContext) {
        if context.sequence >= lobbySequence {
            if let me = response.me { self.me = me }
            if let users = response.users { self.users = users.filter { !isPeerHidden($0.id) } }
            if let incoming = response.incoming {
                self.incoming = incoming.filter { !isPeerHidden($0.opponent.id) }
                for invite in self.incoming where seenInviteIDs.insert(invite.id.lowercased()).inserted {
                    if invite.expiresAtMs > estimatedServerNowMs { onInviteArrived?(invite) }
                    guard context.generation == resetGeneration else { return }
                }
            }
            if case .lobby = call {
                outgoing = response.outgoing
                lastLobbyRefresh = clock()
            } else if response.incoming != nil || response.outgoing != nil {
                outgoing = response.outgoing
            }
            lobbySequence = context.sequence
            if let outgoing, isPeerHidden(outgoing.opponent.id) { self.outgoing = nil }
            scheduleInviteExpiry()
        }
        guard var next = response.state, let id = UUID(uuidString: next.id),
              !dismissedMatchIDs.contains(id.uuidString.lowercased()),
              next.canonicalGame != nil else { return }
        if let requestedID = call.parameters.pMatchID, requestedID != id { return }
        if let me {
            let ownID = next.myColor == .black ? next.black.id : next.white.id
            guard let ownID = UUID(uuidString: ownID), let meID = UUID(uuidString: me.id),
                  ownID == meID else { return }
        }
        let sameMatch = state.flatMap { UUID(uuidString: $0.id) } == id
        guard sameMatch || context.matchGeneration == matchGeneration else { return }
        let old = sameMatch ? state : nil
        var messages = Dictionary(chat.filter { _ in sameMatch }.map { ($0.seq, $0) }, uniquingKeysWith: { first, _ in first })
        for message in next.chat where message.seq > 0 && message.seq <= next.chatSeq
            && message.sentAtMs.isFinite && message.body.unicodeScalars.count <= 100 {
            if messages[message.seq] == nil { messages[message.seq] = message }
        }
        chat = messages.values.sorted { $0.seq < $1.seq }
        if let old, old.revision > next.revision { next = old }
        next.chatSeq = max(next.chatSeq, response.state?.chatSeq ?? 0, old?.chatSeq ?? 0)
        next.chat = chat
        if context.muteGeneration != muteGeneration, let old { next.muted = old.muted }
        if !sameMatch { matchGeneration &+= 1 }
        state = next
        focusMatchID = nil
        if next.phase == .finished, seenFinishedMatchIDs.insert(id.uuidString.lowercased()).inserted {
            onMatchFinished?()
            guard context.generation == resetGeneration else { return }
        }
        if !sameMatch, !(isWindowVisible && !isWindowOccluded) {
            presentWindow?()
            guard context.generation == resetGeneration else { return }
            requestAttention?()
        }
        scheduleDeadlineRefresh()
    }

    private func notice(for status: AlkkagiRPCStatus) -> String? {
        switch status {
        case .ok: nil
        case .stale: "판이 바뀌었어요. 다시 선택해 주세요."
        case .busy, .targetBusy, .alreadyPending: "이미 다른 대전이나 신청이 있어요."
        case .expired, .notPending: "신청 시간이 지났어요."
        case .notFound, .notActive: "대전을 찾을 수 없어요."
        case .muted: "대화를 켠 뒤 보내 주세요."
        case .rateLimited: "잠시 뒤 다시 보내 주세요."
        case .notSignedIn: "로그인한 뒤 다시 시도해 주세요."
        case .unsupportedClient, .unknown: "앱을 업데이트한 뒤 다시 시도해 주세요."
        case .invalid, .forbidden: "지금은 할 수 없는 동작이에요."
        }
    }

    private func isPeerHidden(_ id: String) -> Bool {
        hiddenPeerIDs.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
    }

    private func requestSync() {
        guard service != nil else { return }
        pendingLobby = true
        pendingUsers = pendingUsers || (isWindowVisible && !isWindowOccluded)
        pendingMatch = true
        startSyncIfNeeded()
    }

    private func synchronize(lobby: Bool, match: Bool, users: Bool = false) async {
        guard service != nil else { return }
        pendingLobby = pendingLobby || lobby
        pendingUsers = pendingUsers || users
        pendingMatch = pendingMatch || match
        startSyncIfNeeded()
        await syncTask?.value
    }

    private func startSyncIfNeeded() {
        guard syncTask == nil else { return }
        let generation = resetGeneration
        syncTask = Task { @MainActor [weak self] in
            guard let self, generation == self.resetGeneration else { return }
            self.isLoading = true
            defer {
                if generation == self.resetGeneration {
                    self.isLoading = false
                    self.syncTask = nil
                }
            }
            while generation == self.resetGeneration, !Task.isCancelled {
                let lobby = self.pendingLobby
                let users = self.pendingUsers
                let match = self.pendingMatch
                self.pendingLobby = false
                self.pendingUsers = false
                self.pendingMatch = false
                guard lobby || match else { return }
                if lobby {
                    _ = await self.perform(.lobby(users: users))
                }
                guard generation == self.resetGeneration, !Task.isCancelled else { return }
                let focus = self.focusMatchID
                let isInvite = focus.map { id in
                    self.incoming.contains { UUID(uuidString: $0.id) == id }
                        || self.outgoing.flatMap { UUID(uuidString: $0.id) } == id
                } ?? false
                let id = isInvite ? self.state.flatMap { UUID(uuidString: $0.id) }
                    : focus ?? self.state.flatMap { UUID(uuidString: $0.id) }
                if match, let id {
                    let since = self.state.flatMap { UUID(uuidString: $0.id) } == id ? self.state?.chatSeq ?? 0 : 0
                    _ = await self.perform(.state(matchID: id, sinceChatSeq: since))
                }
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil, service != nil, isWindowVisible, !isWindowOccluded else { return }
        let generation = resetGeneration
        let seconds = min(pollSeconds, Double(UInt64.max / 1_000_000_000))
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard let self, generation == self.resetGeneration,
                      self.isWindowVisible, !self.isWindowOccluded else { return }
                self.requestSync()
            }
        }
    }

    // Invitation badges also expire while the game window is closed, without polling.
    private func scheduleInviteExpiry() {
        inviteExpiryTask?.cancel()
        inviteExpiryTask = nil
        let now = estimatedServerNowMs
        incoming.removeAll { !$0.expiresAtMs.isFinite || $0.expiresAtMs <= now }
        if let outgoing, !outgoing.expiresAtMs.isFinite || outgoing.expiresAtMs <= now {
            self.outgoing = nil
        }
        let deadlines = incoming.map(\.expiresAtMs) + [outgoing?.expiresAtMs].compactMap { $0 }
        guard let deadline = deadlines.min() else { return }
        let seconds = max(0, (deadline - now) / 1000)
        guard seconds.isFinite, seconds < Double(UInt64.max / 1_000_000_000) else { return }
        let generation = resetGeneration
        inviteExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, !Task.isCancelled, generation == self.resetGeneration else { return }
            self.scheduleInviteExpiry()
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private var deadlineKey: String? {
        guard let state, let deadline = state.deadlineMs, state.phase != .finished else { return nil }
        return "\(state.id.lowercased()):\(state.revision):\(deadline)"
    }

    private var refreshDeadlineMs: Double? {
        guard let state else { return nil }
        if state.phase == .rolling, let shot = state.shot {
            return shot.startedAtMs + shot.duration * 1000
        }
        return state.deadlineMs
    }

    private func refreshExpiredDeadline() {
        guard isWindowVisible, !isWindowOccluded, let key = deadlineKey,
              key != refreshedDeadline else { return }
        refreshedDeadline = key
        requestSync()
    }

    private func scheduleDeadlineRefresh() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard isWindowVisible, !isWindowOccluded, let deadline = refreshDeadlineMs,
              deadline.isFinite, let key = deadlineKey, key != refreshedDeadline else { return }
        let seconds = max(0, (deadline - estimatedServerNowMs) / 1000)
        guard seconds.isFinite, seconds < Double(UInt64.max / 1_000_000_000) else { return }
        let generation = resetGeneration
        deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, !Task.isCancelled, generation == self.resetGeneration,
                  self.deadlineKey == key else { return }
            self.refreshExpiredDeadline()
        }
    }
}
