import Foundation

@MainActor
extension WorkTimerStore {
    func refreshTeamStatus() async {
        guard session != nil else {
            return
        }
        guard let teamID = currentTeamID else {
            // 무소속: 팀 데이터를 비우고 팀 코드 참여 안내 문구만 남긴다. 내용이 같으면 재대입하지 않아
            // 30초 폴링이 숨은 트리를 헛무효화하지 않게 한다.
            if !teamMembers.isEmpty { teamMembers = [] }
            let teamlessMessage = "소속 팀이 없어요 — 팀 코드로 참여해 주세요"
            if syncMessage != teamlessMessage { syncMessage = teamlessMessage }
            return
        }
        let generation = sessionGeneration

        do {
            let members = try await withSessionRetry { activeSession in
                try await service.fetchTeamStatuses(accessToken: activeSession.accessToken, teamID: teamID)
            }
            guard generation == sessionGeneration else { return }
            // 등호 가드로 무효화를 줄이되, 전이 감지는 가드 밖에서 매 refresh 호출한다(대입이 스킵돼도 old==new 라 동작 동일).
            if teamMembers != members { teamMembers = members }
            detectTeamReactions()
            // 앱 시작 복구/폴링에서 서버상 내 세션은 열려 있으나 로컬은 비근무이고 마지막 신호 공백이 크면
            // 그 세션을 마지막 신호 시각으로 자동 마감한다. 자동 마감이 일어나면 restore 로직은 건너뛴다.
            if await autoCloseAbandonedOwnSessionIfNeeded() {
                guard generation == sessionGeneration else { return }
                stopTimerIfIdle()
                return
            }
            guard generation == sessionGeneration else { return }
            applyRemoteOwnStatus()
            stopTimerIfIdle()
            scavengeAbandonedTeamSessionsIfNeeded()
            if syncMessage != "동기화됨" { syncMessage = "동기화됨" }
        } catch {
            // 취소(.task 취소/팝오버 빨리 닫기)는 실패 문구를 남기지 않고 조용히 빠져나간다(사용자 헛경보 금지).
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
        }
    }

    /// 팀 목록 반영 직후 호출. 팀원 출근 인사(offWork→working 전이)와 팀 주간 목표 100% 돌파를 감지해
    /// 리액션을 트리거한다. 첫 로드는 전이로 치지 않는다(seed 만 하고 인사/축하 없음).
    func detectTeamReactions() {
        let now = Date()
        let names = greetingDetector.detect(members: teamMembers, selfID: session?.userID, now: now)
        for name in names {
            onReactionTrigger?(.greeting(name: name))
        }

        let weeklyTotal = teamMembers.reduce(0) { $0 + $1.liveWeeklyDurationSeconds(now: now) }
        let complete = TeamWeeklyGoal(workedSeconds: weeklyTotal, goalSeconds: teamGoalSeconds).isComplete
        defer { teamGoalComplete = complete }
        // 첫 관측(nil)은 전이로 치지 않는다. 미완료→완료 로 바뀌는 순간에만, 1일 1회 축하한다.
        if teamGoalComplete == false, complete, milestoneTracker.fireIfNeeded(MilestoneTracker.teamGoalKey, now: now) {
            onReactionTrigger?(.milestone)
        }
    }

    /// 10분 넘게 하트비트가 끊긴(방치) 팀원이 있으면 서버 스캐빈저 RPC(close_abandoned_work_sessions)를
    /// 발사해 그 세션들을 마지막 신호 시각으로 마감하게 한다. 서버 cron 이 주 경로이고, 이건 "누군가
    /// 팝오버를 보고 있는 동안 더 빨리" 정리해 주는 보정이다. 5분 스로틀로 폴링마다 난사하지 않는다.
    /// stale 판정은 자기/타인을 가리지 않고 동일 규칙(신호 공백 > 10분)으로 본다 — 살아 있는 내 앱은
    /// 하트비트가 가므로 정상적으론 대상이 되지 않는다. 성공하면 정리 결과를 반영하려 팀을 한 번 더 새로고침한다.
    func scavengeAbandonedTeamSessionsIfNeeded(now: Date = Date()) {
        let hasAbandoned = teamMembers.contains { member in
            guard case .staleWorking = member.presence(now: now),
                  let seen = member.lastSeenAt ?? member.updatedAt
            else {
                return false
            }
            return now.timeIntervalSince(seen) > Self.abandonedSessionThresholdSeconds
        }
        guard hasAbandoned, now.timeIntervalSince(lastScavengeAt) >= Self.scavengeThrottleSeconds else {
            return
        }
        lastScavengeAt = now
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                _ = try await withSessionRetry { activeSession in
                    try await service.closeAbandonedSessions(accessToken: activeSession.accessToken)
                }
                guard generation == sessionGeneration else { return }
                await refreshTeamStatus()
            } catch {
                // 실패는 조용히 무시한다(서버 cron 이 주 경로 — 다음 주기에 자연히 재시도).
            }
        }
    }

    /// 팀 리그 순위를 로드한다(Task 발사). 페이지를 여는 순간과 재조회 버튼에서 호출한다.
    func loadLeaderboard() {
        Task { @MainActor in await performLoadLeaderboard() }
    }

    /// 리그 페이지가 열려 있는 동안만 순위를 갱신한다(30초 refresh 루프에서 호출).
    func refreshLeaderboardIfVisible() async {
        guard isLeaderboardVisible else { return }
        await performLoadLeaderboard()
    }

    /// team_weekly_leaderboard RPC 로 순위를 받아 1인당 평균 근무시간 내림차순(동률 시 이름)으로
    /// 정렬해 반영한다. 목표가 1인당이라 정렬 기준도 총합이 아니라 평균이다. 서버 정렬은 신뢰하지 않고
    /// 클라에서 다시 정렬한다. 실패 시 안내만 남긴다.
    func performLoadLeaderboard() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        do {
            let entries = try await withSessionRetry { activeSession in
                try await service.fetchTeamLeaderboard(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            let sorted = entries.sortedByAverageDescending()
            if leaderboard != sorted { leaderboard = sorted }
        } catch {
            // 취소는 실패 문구를 남기지 않고 조용히 빠져나간다.
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            if syncMessage != "리그 불러오기 실패" { syncMessage = "리그 불러오기 실패" }
        }
    }

    // MARK: - 팀원 이번 달 AI 토큰 보드

    /// 토큰 보드를 로드한다(Task 발사). 페이지를 여는 순간과 팝오버 재오픈에서 호출한다.
    func loadTokenBoard() {
        Task { @MainActor in await performLoadTokenBoard() }
    }

    /// 토큰 보드 페이지가 열려 있는 동안만 보드를 갱신한다(30초 refresh 루프에서 호출).
    func refreshTokenBoardIfVisible() async {
        guard isTokenBoardVisible else { return }
        await performLoadTokenBoard()
    }

    /// 팀원 이번 달 토큰 행을 조회해 팀원 목록과 결합·정렬(total 내림차순, 동률 이름)해 반영한다.
    /// 팀원인데 행이 없으면 total 0 으로 채워 전원을 보여 준다("다들 0부터"). 팀원 목록이 아직 없으면 비운다(로딩 중립).
    /// 서버 정렬은 신뢰하지 않고 클라에서 다시 정렬한다. 실패는 조용히 — 다음 주기/재오픈에서 다시 시도한다.
    func performLoadTokenBoard() async {
        guard session != nil, currentTeamID != nil else { return }
        let members = teamMembers
        let memberIDs = members.map(\.id)
        guard !memberIDs.isEmpty else {
            if !tokenBoard.isEmpty { tokenBoard = [] }
            return
        }
        let month = TokenUsageMonthKey.current()
        let generation = sessionGeneration
        do {
            let rows = try await withSessionRetry { activeSession in
                try await service.fetchTokenBoard(accessToken: activeSession.accessToken, memberIDs: memberIDs, month: month)
            }
            guard generation == sessionGeneration else { return }
            let entries = members.combinedTokenBoard(rows: rows).sortedByTotalDescending()
            if tokenBoard != entries { tokenBoard = entries }
        } catch {
            // 취소는 조용히 빠져나간다. 그 외 실패도 문구를 흔들지 않고 다음 주기/재오픈에서 재시도한다.
            if case .cancelled = classifyAuthError(error) { return }
        }
    }

    /// 팝오버 열림/refresh 루프에서 부르는 업로드 진입점. D1 의 로컬 월간 사용량을 읽어 게이트 판정 후 upsert 한다.
    /// (TokenUsageStore.shared 의존은 이 얇은 래퍼에만 둔다 — 결정 로직/테스트는 usage 주입 오버로드가 담당.)
    func uploadTokenUsageIfNeeded(now: Date = Date()) async {
        await uploadTokenUsageIfNeeded(usage: TokenUsageStore.shared.currentMonthUsage, now: now)
    }

    /// 변경 게이트 + 60초 스로틀. 마지막 업로드 값과 다르고 60초 지났을 때만 upsert 한다.
    /// nil/총합 0 은 올리지 않는다(보드는 행 없는 팀원을 0 으로 채우므로 빈 행을 만들 필요가 없다).
    /// 실패는 조용히 — lastUploadedUsage 를 성공 시에만 갱신해 다음 주기에 재시도된다.
    func uploadTokenUsageIfNeeded(usage: TokenUsageMonthly?, now: Date) async {
        guard session != nil else { return }
        guard let usage, usage.total > 0 else { return }
        guard usage != lastUploadedUsage, now.timeIntervalSince(lastTokenUploadAt) >= 60 else { return }
        // 시도 시각을 먼저 스탬프해, 실패하더라도 60초 안에는 재시도하지 않는다(난사 방지).
        lastTokenUploadAt = now
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.upsertTokenUsage(accessToken: activeSession.accessToken, userID: activeSession.userID, usage: usage)
            }
            guard generation == sessionGeneration else { return }
            // 성공 시에만 마지막 업로드 값을 갱신한다 — 실패면 값이 그대로라 다음 60초 후 변경 게이트가 다시 통과한다.
            lastUploadedUsage = usage
        } catch {
            // 조용히 무시하고 다음 주기에 재시도한다(표시 문구를 흔들지 않는다).
        }
    }

    /// 근무중일 때 서버에 생존신호(last_seen_at)를 보낸다. 근무중이 아니거나 세션 정보가 없으면 보내지 않는다.
    func sendHeartbeatIfWorking() async {
        guard startedAt != nil, session != nil, let sessionID = currentSessionID, let teamID = currentTeamID else {
            return
        }
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.heartbeat(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    sessionID: sessionID
                )
            }
        } catch {
            // 하트비트 실패는 조용히 무시하고 다음 주기에 재시도한다(표시 문구를 흔들지 않는다).
            guard generation == sessionGeneration else { return }
        }
    }

    /// 서버상 내 세션이 열려 있고 로컬은 비근무(startedAt==nil, pendingItems 비어 있음)이며 마지막 신호와의
    /// 공백이 90초를 넘으면 그 세션을 마지막 신호 시각으로 마감한다. 마감했으면 true.
    /// 네트워크가 끊긴 채 앱이 계속 살아 일하던 경우(startedAt != nil)는 절대 마감하지 않는다.
    private func autoCloseAbandonedOwnSessionIfNeeded() async -> Bool {
        guard startedAt == nil, pendingItems.isEmpty else { return false }
        guard let teamID = currentTeamID else { return false }
        guard let session, let member = teamMembers.first(where: { $0.id == session.userID }) else {
            return false
        }
        guard member.status == .working, let sessionStart = member.currentSessionStartedAt else {
            return false
        }
        guard let seen = member.lastSeenAt ?? member.updatedAt, Date().timeIntervalSince(seen) > 90 else {
            return false
        }

        accumulatedSeconds = member.todayDurationSeconds
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: Date())
        let duration = max(0, Int(seen.timeIntervalSince(sessionStart)))
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.stopWork(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    startedAt: sessionStart,
                    endedAt: seen,
                    durationSeconds: duration,
                    fallbackSessionID: member.activeSessionID ?? currentSessionID ?? UUID().uuidString
                )
            }
            guard generation == sessionGeneration else { return true }
            lastAutoClosedSessionID = member.activeSessionID
            lastAutoClosedStartedAt = sessionStart
            startedAt = nil
            currentSessionID = nil
            snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
            refreshMenuBarTitle()
            syncMessage = "자리 비움으로 자동 근무종료됨"
        } catch {
            guard generation == sessionGeneration else { return true }
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
        }
        return true
    }

    var canUndoAutoClose: Bool {
        lastAutoClosedSessionID != nil
    }

    /// 자리 비움 자동 마감을 되돌린다(뷰 배선은 이번 웨이브 범위 밖 — 코어만 제공).
    @discardableResult
    func undoAutoClose() -> Task<Void, Never>? {
        guard canUndoAutoClose else { return nil }
        return Task { @MainActor in await performUndoAutoClose() }
    }

    func performUndoAutoClose() async {
        guard let sessionID = lastAutoClosedSessionID, let restoredStart = lastAutoClosedStartedAt else {
            return
        }
        guard let teamID = currentTeamID else { return }
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.reopenSession(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    sessionID: sessionID
                )
            }
            guard generation == sessionGeneration else { return }
            startedAt = restoredStart
            currentSessionID = sessionID
            longSessionAnchor = restoredStart
            displayNow = Date()
            snapshot = WorkStatusSnapshot(
                status: .working,
                elapsedSeconds: max(0, Int(displayNow.timeIntervalSince(restoredStart)))
            )
            lastAutoClosedSessionID = nil
            lastAutoClosedStartedAt = nil
            startTimer()
            refreshMenuBarTitle()
            syncMessage = "근무 재개됨"
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "재개 실패")
        }
    }

    /// 아바타 업로드 + 프로필 갱신 + 팀 새로고침. 결과는 syncMessage 로 알린다.
    func updateAvatar(imageData: Data) {
        Task { @MainActor in await performAvatarUpdate(imageData: imageData) }
    }

    func performAvatarUpdate(imageData: Data) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        do {
            _ = try await withSessionRetry { activeSession in
                try await service.uploadAvatar(
                    accessToken: activeSession.accessToken,
                    userID: activeSession.userID,
                    imageData: imageData
                )
            }
            guard generation == sessionGeneration else { return }
            await refreshTeamStatus()
            guard generation == sessionGeneration else { return }
            syncMessage = "프로필 사진 변경됨"
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "사진 업로드 실패")
        }
    }

    func syncCurrentStatus(durationSeconds: Int? = nil, sessionStartedAt: Date? = nil, endedAt: Date? = nil) {
        guard session != nil else {
            snapshot.pendingSync = true
            syncMessage = "로그인 필요"
            refreshMenuBarTitle()
            return
        }

        // 조작을 큐에 추가한다(덮어쓰지 않는다). 각 항목은 자체 세션 정보를 동봉해 나중 드레인에서 정확히 재생된다.
        let item: PendingWorkItem
        if snapshot.isWorking {
            item = PendingWorkItem(
                id: UUID(),
                operation: .start,
                sessionID: currentSessionID ?? UUID().uuidString,
                sessionStartedAt: startedAt,
                endedAt: nil
            )
        } else {
            item = PendingWorkItem(
                id: UUID(),
                operation: .stop(durationSeconds: durationSeconds ?? todayDuration),
                sessionID: currentSessionID ?? UUID().uuidString,
                sessionStartedAt: sessionStartedAt,
                endedAt: endedAt
            )
        }
        // in-flight 동안 '대기' 표시를 켜지 않는다(정상 왕복마다 라벨이 깜빡이는 것 방지).
        // 실패 시 runPendingSync 의 catch 가 pendingSync 를 켜고, 드레인 완료가 끈다.
        pendingItems.append(item)
        refreshMenuBarTitle()

        enqueueSync()
    }

    func retryPendingSync() async {
        guard !pendingItems.isEmpty, session != nil else {
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
        guard session != nil, !pendingItems.isEmpty else {
            return
        }
        let generation = sessionGeneration

        // 큐를 순서대로 드레인한다. 한 항목이라도 실패하면 그 지점에서 멈춰(순서 보존) 다음 주기에 재시도한다.
        while let item = pendingItems.first {
            do {
                try await performPendingOperation(item)
                // 서버 실행이 끝난 항목은 세대와 무관하게 큐에서 제거한다 — 큐는 clearPersistedSession 을 살아남는
                // 로컬 장부라, 완료 항목이 세대 증가로 잔류하면 재로그인 후 같은 sessionID 로 이중 재생(409)된다.
                if pendingItems.first?.id == item.id {
                    pendingItems.removeFirst()
                }
                guard generation == sessionGeneration else { return }
            } catch {
                guard generation == sessionGeneration else { return }
                snapshot.pendingSync = true
                syncMessage = authMessage(for: error, fallback: "동기화 실패")
                refreshMenuBarTitle()
                return
            }
        }

        guard generation == sessionGeneration else { return }
        snapshot.pendingSync = false
        refreshMenuBarTitle()
        await refreshTeamStatus()
    }

    private func performPendingOperation(_ item: PendingWorkItem) async throws {
        guard let teamID = currentTeamID else {
            // 소속 팀이 없으면 근무 시작/종료를 서버에 반영할 수 없다.
            throw SupabaseWorkServiceError.authMessage("소속 팀이 없어요 — 팀 코드로 참여해 주세요")
        }
        switch item.operation {
        case .start:
            // 항목이 동봉한 세션ID/시작시각을 쓴다 — 오프라인 복구 시 서버 started_at 이 실제 시작시각으로 기록된다.
            try await withSessionRetry { activeSession in
                try await service.startWork(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    sessionID: item.sessionID,
                    startedAt: item.sessionStartedAt ?? Date()
                )
            }
        case .stop(let durationSeconds):
            try await withSessionRetry { activeSession in
                try await service.stopWork(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    startedAt: item.sessionStartedAt ?? Date(),
                    endedAt: item.endedAt ?? Date(),
                    durationSeconds: durationSeconds,
                    fallbackSessionID: item.sessionID
                )
            }
        }
    }

    private func applyRemoteOwnStatus() {
        guard pendingItems.isEmpty else {
            return
        }

        guard let session,
              let ownMember = teamMembers.first(where: { $0.id == session.userID })
        else {
            return
        }

        accumulatedSeconds = ownMember.todayDurationSeconds
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: Date())

        switch (ownMember.status, startedAt) {
        case (.working, nil):
            let restoredStart = ownMember.currentSessionStartedAt ?? Date()
            displayNow = Date()
            startedAt = restoredStart
            currentSessionID = ownMember.activeSessionID ?? currentSessionID
            longSessionAnchor = restoredStart
            snapshot = WorkStatusSnapshot(
                status: .working,
                elapsedSeconds: max(0, Int(displayNow.timeIntervalSince(restoredStart)))
            )
            startTimer()
        case (.offWork, .some):
            startedAt = nil
            longSessionAnchor = nil
            clearLongSessionPrompt()
            snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
            stopTimerIfIdle()
        default:
            snapshot.pendingSync = false
        }
        // 세 분기 모두 snapshot/accumulated 를 건드리므로 라벨 문자열을 한곳에서 재계산한다(== 가드는 내부에서).
        refreshMenuBarTitle()
    }
}
