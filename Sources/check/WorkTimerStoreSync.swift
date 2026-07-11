import Foundation

@MainActor
extension WorkTimerStore {
    func refreshTeamStatus() async {
        guard session != nil else {
            return
        }
        let generation = sessionGeneration

        do {
            let members = try await withSessionRetry { activeSession in
                try await service.fetchTeamStatuses(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            teamMembers = members
            applyRemoteOwnStatus()
            stopTimerIfIdle()
            syncMessage = "동기화됨"
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
        }
    }

    func syncCurrentStatus(durationSeconds: Int? = nil, sessionStartedAt: Date? = nil, endedAt: Date? = nil) {
        guard session != nil else {
            snapshot.pendingSync = true
            syncMessage = "로그인 필요"
            return
        }

        let operation: PendingWorkOperation = snapshot.isWorking
            ? .start
            : .stop(durationSeconds: durationSeconds ?? todayDuration)
        pendingOperation = operation
        pendingStopStartedAt = sessionStartedAt
        pendingStopEndedAt = endedAt

        enqueueSync()
    }

    func retryPendingSync() async {
        guard pendingOperation != nil, session != nil else {
            return
        }
        enqueueSync()
        await syncTask?.value
    }

    func enqueueSync() {
        let previous = syncTask
        syncTask = Task { @MainActor [weak self] in
            await previous?.value
            await self?.runPendingSync()
        }
    }

    private func runPendingSync() async {
        guard let operation = pendingOperation, session != nil else {
            return
        }
        let generation = sessionGeneration

        do {
            try await performPendingOperation(operation)
            guard generation == sessionGeneration else { return }
            pendingOperation = nil
            snapshot.pendingSync = false
            await refreshTeamStatus()
        } catch {
            guard generation == sessionGeneration else { return }
            snapshot.pendingSync = true
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
        }
    }

    private func performPendingOperation(_ operation: PendingWorkOperation) async throws {
        switch operation {
        case .start:
            let sessionID = currentSessionID ?? UUID().uuidString
            currentSessionID = sessionID
            try await withSessionRetry { activeSession in
                try await service.startWork(
                    accessToken: activeSession.accessToken,
                    userID: activeSession.userID,
                    sessionID: sessionID
                )
            }
        case .stop(let durationSeconds):
            let startedAt = pendingStopStartedAt ?? Date()
            let endedAt = pendingStopEndedAt ?? Date()
            let fallbackSessionID = currentSessionID ?? UUID().uuidString
            try await withSessionRetry { activeSession in
                try await service.stopWork(
                    accessToken: activeSession.accessToken,
                    userID: activeSession.userID,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: durationSeconds,
                    fallbackSessionID: fallbackSessionID
                )
            }
        }
    }

    private func applyRemoteOwnStatus() {
        guard pendingOperation == nil else {
            return
        }

        guard let session,
              let ownMember = teamMembers.first(where: { $0.id == session.userID })
        else {
            return
        }

        accumulatedSeconds = ownMember.todayDurationSeconds

        switch (ownMember.status, startedAt) {
        case (.working, nil):
            let restoredStart = ownMember.currentSessionStartedAt ?? Date()
            displayNow = Date()
            startedAt = restoredStart
            snapshot = WorkStatusSnapshot(
                status: .working,
                elapsedSeconds: max(0, Int(displayNow.timeIntervalSince(restoredStart)))
            )
            startTimer()
        case (.offWork, .some):
            startedAt = nil
            snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
            stopTimerIfIdle()
        default:
            snapshot.pendingSync = false
        }
    }
}
