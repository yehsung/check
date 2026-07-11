import Foundation

@MainActor
extension WorkTimerStore {
    func refreshTeamStatus() async {
        guard let session else {
            return
        }

        do {
            teamMembers = try await service.fetchTeamStatuses(accessToken: session.accessToken)
            applyRemoteOwnStatus()
            stopTimerIfIdle()
            syncMessage = "동기화됨"
        } catch {
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
        }
    }

    func syncCurrentStatus(durationSeconds: Int? = nil) {
        guard let session else {
            snapshot.pendingSync = true
            syncMessage = "로그인 필요"
            return
        }

        let isWorking = snapshot.isWorking
        Task {
            do {
                if isWorking {
                    try await service.startWork(accessToken: session.accessToken, userID: session.userID)
                } else {
                    try await service.stopWork(
                        accessToken: session.accessToken,
                        userID: session.userID,
                        durationSeconds: durationSeconds ?? todayDuration
                    )
                }
                snapshot.pendingSync = false
                await refreshTeamStatus()
            } catch {
                snapshot.pendingSync = true
                syncMessage = authMessage(for: error, fallback: "동기화 실패")
            }
        }
    }

    private func applyRemoteOwnStatus() {
        guard let session,
              let ownMember = teamMembers.first(where: { $0.id == session.userID })
        else {
            return
        }

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
