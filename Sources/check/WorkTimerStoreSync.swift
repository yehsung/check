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
        // 근무 상태 write 세대를 fetch 발사 전에 캡처한다. 응답이 도착했을 때 값이 달라졌다면 그 사이 사용자가
        // 시작/종료를 눌렀다는 뜻이므로, 낡은 스냅샷으로 내 상태를 되돌리지 않는다(팀원 목록 반영은 그대로 한다).
        let writeGeneration = workStateWriteGeneration

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
            if writeGeneration == workStateWriteGeneration, await autoCloseAbandonedOwnSessionIfNeeded() {
                guard generation == sessionGeneration else { return }
                stopTimerIfIdle()
                return
            }
            guard generation == sessionGeneration else { return }
            applyRemoteOwnStatus(writeGeneration: writeGeneration)
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

    /// 팀의 이번 주 1인당 평균 근무 초(총합 ÷ 인원). 리그 표시(TeamLeaderboardEntry.averageSeconds)와 같은 규약이라
    /// 화면에 보이는 진행률과 축하 발화 기준이 어긋나지 않는다. 인원 0(로드 전)이면 0.
    func teamWeeklyAverageSeconds(now: Date = Date()) -> Int {
        guard !teamMembers.isEmpty else { return 0 }
        let total = teamMembers.reduce(0) { $0 + $1.liveWeeklyDurationSeconds(now: now) }
        return total / teamMembers.count
    }

    /// 팀 목록 반영 직후 호출. 팀원 출근 인사(offWork→working 전이)와 팀 주간 목표 100% 돌파를 감지해
    /// 리액션을 트리거한다. 첫 로드는 전이로 치지 않는다(seed 만 하고 인사/축하 없음).
    func detectTeamReactions() {
        let now = Date()
        let names = greetingDetector.detect(members: teamMembers, selfID: session?.userID, now: now)
        for name in names {
            onReactionTrigger?(.greeting(name: name))
        }

        // 주간 목표는 팀 총합이 아니라 "각자 이번 주 이만큼"인 1인당 약속이다. 그래서 달성 판정도 리그와 같은
        // 1인당 평균(총합 ÷ 인원) 기준으로 본다 — 총합을 1인당 목표와 견주면 인원이 많을수록 일찍 터져서,
        // 5명 팀에 60시간 목표면 각자 12시간만 해도 축하가 나가던 오발화가 있었다.
        let complete = TeamWeeklyGoal(
            workedSeconds: teamWeeklyAverageSeconds(now: now),
            goalSeconds: teamGoalSeconds
        ).isComplete
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

    /// 이번 달 토큰 순위를 조회해(앱 사용자 전체 공개 RPC) 정렬(total 내림차순, 동률 이름)해 반영한다.
    /// 행이 자체 완결(이름/아바타 포함)이라 팀원 목록 결합이 없다 — 업로드한 사용자만 뜬다(월초엔 각자 앱이 열리며 자연 등장).
    /// 서버 정렬은 신뢰하지 않고 클라에서 다시 정렬한다. 성공하면 tokenBoardLoaded 를 세워 빈 목록의 '아직 없음' 문구를
    /// 로드 전/실패와 구분한다. 실패는 조용히 — 다음 주기/재오픈에서 다시 시도한다.
    func performLoadTokenBoard() async {
        guard session != nil else { return }
        // 보고 있는 달(‹ › 로 이동 가능, 기본은 이번 달)을 조회한다 — 이번 달로 하드코딩하면 과거 달 보기가 무력화된다.
        let month = tokenBoardMonth
        let generation = sessionGeneration
        // 진행중 표시(‹ › 월 이동 직후 빈 목록 자리에 동기화 문구 대신 "불러오는 중…"을 띄우기 위함).
        if !tokenBoardLoading { tokenBoardLoading = true }
        // 재시도가 시작되면 직전 실패 표시를 내린다 — 다시 "불러오는 중…"으로 돌아가야 [다시 시도] 가 먹힌 것이 보인다.
        if tokenBoardFailed { tokenBoardFailed = false }
        // 이 조회가 끝나면(성공·실패·취소 무관) 진행중 표시를 내린다. 단, 그 사이 달이 바뀌었으면 새 조회가
        // 이미 켜 둔 표시라 건드리지 않는다 — 연달아 ‹ 를 눌러도 "불러오는 중…"이 끊기지 않는다.
        defer { if month == tokenBoardMonth, tokenBoardLoading { tokenBoardLoading = false } }
        do {
            let rows = try await withSessionRetry { activeSession in
                try await service.fetchTokenBoard(accessToken: activeSession.accessToken, month: month)
            }
            guard generation == sessionGeneration else { return }
            // 응답이 오는 사이 ‹ › 로 달을 옮겼으면 이 응답은 낡은 달의 것이라 버린다(월 이동 스냅백 방지).
            guard month == tokenBoardMonth else { return }
            let entries = rows.toTokenBoardEntries().sortedByTotalDescending()
            if tokenBoard != entries { tokenBoard = entries }
            // 성공 로드 완료 표시(빈 목록이어도 '아직 아무도 안 올림'과 로드 전/실패를 구분하기 위함).
            if !tokenBoardLoaded { tokenBoardLoaded = true }
            if tokenBoardFailed { tokenBoardFailed = false }
        } catch {
            // 취소(팝오버 빨리 닫기 등)는 실패가 아니다 — 표시를 흔들지 않고 조용히 빠져나간다.
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            // 응답을 기다리는 사이 달을 옮겼으면 이 실패는 낡은 달의 것이다(새 조회가 스스로 표시를 세운다).
            guard month == tokenBoardMonth else { return }
            // 그 외 실패는 반드시 표시로 남긴다. 예전엔 아무 상태도 세우지 않아 (로드 전 + 진행중 아님 + 빈 목록)
            // 조합이 남았고, 그러면 본문 자리에 syncMessage("동기화됨" 등 무관한 문구)가 그대로 떴다(회귀 지점).
            if !tokenBoardFailed { tokenBoardFailed = true }
        }
    }

    /// 팝오버 열림/refresh 루프에서 부르는 업로드 진입점. D1 의 로컬 월간 사용량을 읽어 게이트 판정 후 upsert 한다.
    /// (토큰 스토어 의존은 이 얇은 래퍼에만 둔다 — 주입된 tokenUsage 를 읽어, 결정 로직/테스트는 usage 주입 오버로드가 담당.)
    func uploadTokenUsageIfNeeded(now: Date = Date()) async {
        await uploadTokenUsageIfNeeded(usage: tokenUsage.currentMonthUsage, now: now)
    }

    /// 변경 게이트 + 60초 스로틀. 마지막 업로드 값과 다르고 60초 지났을 때만 upsert 한다.
    /// nil/총합 0 은 올리지 않는다(보드는 행 없는 팀원을 0 으로 채우므로 빈 행을 만들 필요가 없다).
    /// 새 기기별 표에 올리고, 옛 표에는 '그 행을 깎지 않을 때만' 같은 값을 올린다(이유는 아래 주석 참조).
    /// 실패는 조용히 — lastUploadedUsage 를 성공 시에만 갱신해 다음 주기에 재시도된다.
    /// 예외로 '스키마 부재'만은 문구로 드러낸다(마이그레이션 미적용을 운영자가 알 방법이 그것뿐이다).
    func uploadTokenUsageIfNeeded(usage: TokenUsageMonthly?, now: Date) async {
        guard session != nil else { return }
        guard let usage, usage.total > 0 else { return }
        guard usage != lastUploadedUsage, now.timeIntervalSince(lastTokenUploadAt) >= 60 else { return }
        // 시도 시각을 먼저 스탬프해, 실패하더라도 60초 안에는 재시도하지 않는다(난사 방지).
        lastTokenUploadAt = now
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                // 1) 옛 표(token_usage_monthly)를 먼저 갱신한다 — v0.2.10 과 같은 요청이다.
                //    먼저 보내는 이유: 새 표 마이그레이션이 아직 적용되지 않았더라도 이 갱신은 성공해
                //    그 사이 사용량이 통째로 멈추지 않는다.
                //    단, **그 행을 깎는 쓰기는 금지**한다. 이 표는 키가 (user_id, month) 라 맥 2대가 한 행을 공유하는데,
                //    아직 v0.2.10 인 주력 맥이 200M 을 올려 둔 행을 v0.2.11 인 보조 맥이 자기 2M 으로 덮으면
                //    보드의 '큰 쪽' 규칙이 비교할 옛 값 자체가 2M 이 되어(기기 합산과 동률) 주력 맥의 200M 이
                //    순위에서 사라진다 — 마지막으로 팝오버를 연 맥의 값으로 널뛰던 결함1 이 그대로 재현된다.
                //    그래서 현재 행을 먼저 읽어 내 값이 그보다 작지 않을 때만 덮어쓴다(행이 없으면 그냥 쓴다).
                //    (더 큰 값이 이 맥의 v0.2.9 이하 시절 과다계상 잔재인 경우의 정정은 서버 보드가 맡는다 —
                //     기기 행이 처음 생긴 뒤로 갱신이 끊긴 옛 행은 화석으로 보고 무시한다.)
                //    읽지 못하면(네트워크/권한) 덮어쓰지 않는다 — 모르면 파괴하지 않는 쪽이 안전하다.
                //    새 표 업로드는 아래에서 그대로 진행하고, 실패한 읽기는 다음 주기에 다시 시도된다.
                let mayWriteLegacy: Bool
                do {
                    let currentLegacyTotal = try await service.fetchLegacyTokenUsageTotal(
                        accessToken: activeSession.accessToken,
                        userID: activeSession.userID,
                        month: usage.month
                    )
                    mayWriteLegacy = (currentLegacyTotal ?? 0) <= usage.total
                } catch {
                    mayWriteLegacy = false
                }
                if mayWriteLegacy {
                    try await service.upsertLegacyTokenUsage(
                        accessToken: activeSession.accessToken,
                        userID: activeSession.userID,
                        usage: usage
                    )
                }
                // 2) 새 원장은 (user_id, month, device_id) 라 기기 식별자를 함께 올린다 — 맥 2대가 서로를 덮어쓰지 않고
                //    서버 보드 RPC 가 user_id 로 묶어 합산한다(결함1).
                try await service.upsertTokenUsage(
                    accessToken: activeSession.accessToken,
                    userID: activeSession.userID,
                    usage: usage,
                    deviceID: deviceID
                )
            }
            guard generation == sessionGeneration else { return }
            // 성공 시에만 마지막 업로드 값을 갱신한다 — 실패면 값이 그대로라 다음 60초 후 변경 게이트가 다시 통과한다.
            lastUploadedUsage = usage
        } catch {
            guard generation == sessionGeneration else { return }
            // 스키마 부재(= 새 표 마이그레이션 미적용)만은 조용히 넘기지 않는다. 예전엔 모든 실패를 삼켜,
            // 운영자가 docs/release.md 가 지시한 신호("DB 스키마 필요")를 영원히 못 받았다(순위 조회는 옛 RPC 라 멀쩡해
            // 실패를 시사하는 표시가 아무것도 없었다). 나머지 실패(네트워크 등)는 그대로 조용히 다음 주기 재시도.
            if (error as? SupabaseWorkServiceError) == .databaseSchemaMissing {
                let message = authMessage(for: error, fallback: "동기화 실패")
                if syncMessage != message { syncMessage = message }
            }
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
        // 마감 RPC 왕복 전의 근무 상태 write 세대를 캡처한다. 응답을 반영할 때 값이 달라졌다면 그 사이 사용자가
        // [근무 시작]을 눌렀다는 뜻이고, 그때 로컬을 옛 세션 기준으로 오프로 되돌리면 방금 만든 세션이 서버에
        // 열린 채 추적을 잃는다(팀원 화면 '근무중' 고착 + 되돌리기 배너가 옛 세션으로 갈아치움).
        let writeGeneration = workStateWriteGeneration
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

        // 마감하는 세션의 '오늘 몫'(KST 자정 클리핑). 서버 스냅샷의 todayDurationSeconds 는 마감 **전** 값이라
        // 이 세션을 아직 포함하지 않으므로 여기서 더해 준다. 그래야 (1) 마감 직후 표시가 세션 몫만큼 꺼지지 않고,
        // (2) 곧 도착할 정상 폴링이 채워 넣는 서버 today(= 이 세션 포함)와 값이 같아져, 되돌리기가 폴링 전/후
        // 어느 시점에 눌리든 lastAutoClosedSeconds 를 그대로 빼면 정합해진다.
        let closedTodaySeconds = max(
            0,
            Int(seen.timeIntervalSince(max(sessionStart, TeamWeeklyGoal.koreanDayStart(for: Date()))))
        )
        accumulatedSeconds = member.todayDurationSeconds + closedTodaySeconds
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
            // 세대 재확인(await 이후). 사용자가 왕복 중 새 근무를 시작/종료했다면 그 조작이 최신이므로
            // 서버 마감만 유효로 두고 로컬 반영(오프 스냅백 + 되돌리기 대상 등록)은 통째로 건너뛴다.
            // 서버에 열린 새 세션은 그대로 살아 있고, 지금 로컬 상태가 그 세션을 정확히 가리키고 있다.
            guard writeGeneration == workStateWriteGeneration else { return true }
            lastAutoClosedSessionID = member.activeSessionID
            lastAutoClosedStartedAt = sessionStart
            // 되돌릴 때 누적에서 도로 빼야 할 몫(위에서 누적에 넣은 값과 같은 수). 되돌리면 이 세션이 다시
            // 진행 세션이 되어 startedAt 기준으로 라이브 계산되므로, 빼지 않으면 그 구간을 두 번 센다.
            lastAutoClosedSeconds = closedTodaySeconds
            // 되돌리기 배너의 유효기간 시작점. 이 스탬프가 없으면 배너를 띄우지 않는다(무기한 상주 금지).
            lastAutoClosedAt = Date()
            startedAt = nil
            currentSessionID = nil
            snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
            refreshMenuBarTitle()
            // 되돌리기 배너를 띄우는 유일한 지점. 뷰가 매초 판정하지 않도록 상태로 밀어 넣는다.
            refreshTimedBanner()
            syncMessage = "자리 비움으로 자동 근무종료됨"
        } catch {
            guard generation == sessionGeneration else { return true }
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
        }
        return true
    }

    /// 되돌리기 배너 노출/실행 조건. 세 가지를 모두 만족해야 한다:
    /// (1) 되돌릴 자동 마감 세션이 있고, (2) 지금 근무중이 **아니고**(근무중이면 되돌리기가 현 세션을 옛 세션으로
    /// 갈아치운다), (3) 자동 마감 후 유예(autoCloseUndoWindowSeconds) 안이다(무기한 상주 금지).
    func canUndoAutoClose(now: Date = Date()) -> Bool {
        guard lastAutoClosedSessionID != nil, lastAutoClosedStartedAt != nil else { return false }
        guard startedAt == nil else { return false }
        guard let closedAt = lastAutoClosedAt else { return false }
        return now.timeIntervalSince(closedAt) <= Self.autoCloseUndoWindowSeconds
    }

    /// 자리 비움 자동 마감을 되돌린다. canUndoAutoClose 가 참인 동안 헤더 인라인 배너의 [되돌리기]가 이걸 부른다.
    /// 조건을 잃은 뒤(유예 만료/새 근무 시작) 눌린 경우엔 되돌리지 않고 잔여 대상을 정리만 한다.
    @discardableResult
    func undoAutoClose() -> Task<Void, Never>? {
        guard canUndoAutoClose() else {
            clearAutoCloseUndo()
            return nil
        }
        return Task { @MainActor in await performUndoAutoClose() }
    }

    func performUndoAutoClose() async {
        guard let sessionID = lastAutoClosedSessionID, let restoredStart = lastAutoClosedStartedAt else {
            return
        }
        // 되돌리기 성공 시 누적에서 뺄 몫. clearAutoCloseUndo 가 0으로 되돌리기 전에 미리 붙잡아 둔다.
        let closedSeconds = lastAutoClosedSeconds
        // 진행 중인 근무가 있으면 절대 되돌리지 않는다 — startedAt/currentSessionID 를 옛 세션으로 덮으면
        // 방금 만든 세션이 서버에 열린 채 방치되고(팀원 화면엔 계속 근무중) 타이머가 과거로 점프한다.
        guard startedAt == nil else {
            clearAutoCloseUndo()
            return
        }
        guard let teamID = currentTeamID else { return }
        let generation = sessionGeneration
        // 재개 RPC 왕복 전의 근무 상태 write 세대. 위 startedAt 가드는 await '이전'만 보므로, 응답을 반영할 때
        // 이 값을 한 번 더 확인해야 왕복 중 시작한 근무를 옛 세션으로 갈아치우지 않는다.
        let writeGeneration = workStateWriteGeneration
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
            // 세대/근무 상태 재확인(await 이후). 왕복 중 사용자가 [근무 시작]을 눌렀다면 그 세션이 최신이므로
            // 옛 세션으로 startedAt/currentSessionID 를 덮지 않고 되돌리기 대상만 정리한다(타이머 과거 점프 금지).
            // 서버에서 다시 열린 옛 세션은 하트비트가 없어 서버 스캐빈저가 마지막 신호 시각으로 정리한다.
            guard writeGeneration == workStateWriteGeneration, startedAt == nil else {
                clearAutoCloseUndo()
                return
            }
            // 되돌리기도 내가 확정한 근무 상태 변경이라 세대를 올린다 — 이 순간 in-flight 였던 팀 상태 응답이
            // 방금 재개한 근무를 다시 '종료'로 되돌리지 못하게 한다.
            workStateWriteGeneration &+= 1
            // 되돌린 세션의 '오늘 몫'을 누적에서 뺀다. 이 세션은 지금부터 다시 진행 세션이라 todayDuration 이
            // startedAt 기준으로 라이브 계산하므로, 누적에 남겨 두면 같은 구간을 두 번 세어 메뉴바 라벨·팝오버
            // 큰 타이머·캐릭터 오버레이가 일제히 두 배로 뛴다(다음 폴링 전까지 유지).
            // 날짜 스탬프(accumulatedDayStart)는 건드리지 않는다 — 자정을 넘겼다면 남은 값은 어제 몫이라
            // 오늘 기여로 승격시키면 안 된다.
            accumulatedSeconds = max(0, accumulatedSeconds - closedSeconds)
            startedAt = restoredStart
            currentSessionID = sessionID
            longSessionAnchor = restoredStart
            displayNow = Date()
            snapshot = WorkStatusSnapshot(
                status: .working,
                elapsedSeconds: max(0, Int(displayNow.timeIntervalSince(restoredStart)))
            )
            clearAutoCloseUndo()
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
        // 소유자(userID)도 함께 실어, 강제 로그아웃 후 다른 계정이 로그인하면 그 계정 것이 아닌 항목만 버린다.
        let ownerUserID = session?.userID
        let item: PendingWorkItem
        if snapshot.isWorking {
            item = PendingWorkItem(
                id: UUID(),
                operation: .start,
                sessionID: currentSessionID ?? UUID().uuidString,
                sessionStartedAt: startedAt,
                endedAt: nil,
                ownerUserID: ownerUserID
            )
        } else {
            item = PendingWorkItem(
                id: UUID(),
                operation: .stop(durationSeconds: durationSeconds ?? todayDuration),
                sessionID: currentSessionID ?? UUID().uuidString,
                sessionStartedAt: sessionStartedAt,
                endedAt: endedAt,
                ownerUserID: ownerUserID
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
                // 서버 실행이 끝난 항목은 세대와 무관하게 큐에서 제거한다(세대 가드보다 앞에 둔다) — 세대 증가로
                // 완료 항목이 잔류하면 큐는 clearPersistedSession(강제 로그아웃)을 살아남는 로컬 장부라
                // 재로그인 후 같은 sessionID 로 이중 재생(409)된다. 계정이 바뀐 경우엔 로그인 시점의
                // adoptWorkStateOwner 가 이미 남의 항목을 걷어냈으므로 first 가 달라져 이 제거가 no-op 이 된다.
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

    /// 서버 스냅샷의 '내 행'을 로컬 상태로 흡수한다(앱 재시작 복구/타 기기 조작 반영).
    /// writeGeneration 은 이 응답을 발사하기 직전의 workStateWriteGeneration 이다. 값이 그 사이 올랐다면
    /// (= 사용자가 방금 시작/종료를 눌렀다면) 흡수를 통째로 건너뛴다 — 낡은 응답이 방금 누른 조작을 되돌리는
    /// 스냅백 금지. 팀원 목록/문구 반영은 호출자가 이미 마친 뒤라 팀 뷰는 정상적으로 갱신된다.
    func applyRemoteOwnStatus(writeGeneration: Int) {
        guard writeGeneration == workStateWriteGeneration else {
            return
        }

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
            // (.working, .some) + 세션ID 만 비어 있는 조합이 실재한다: 토큰 만료 강제 로그아웃이 currentSessionID 만
            // 지우고 진행 중 근무(startedAt)와 큐는 일부러 남기기 때문이다(clearPersistedSession 주석). 같은 계정으로
            // 다시 로그인하면 근무는 그대로 흐르는데 세션ID 가 없어 sendHeartbeatIfWorking 이 매 폴링마다 조용히
            // 반환하고(생존신호 영구 정지), 90초 뒤 팀원 화면에 '자리비움', 10분 뒤에는 내 앱의 스캐빈저가
            // close_abandoned_work_sessions 로 내 세션을 로그아웃 시각으로 마감해 그 뒤 근무가 통째로 유실됐다.
            // 서버가 여전히 '근무중'으로 들고 있는 그 행의 세션ID 로 되살린다(값이 남아 있으면 건드리지 않는다 —
            // 다른 맥이 연 세션을 여기서 가로채지 않기 위함이며, pendingItems 가 빈 것은 위에서 이미 확인했다).
            if startedAt != nil, currentSessionID == nil, ownMember.status == .working,
               let restoredSessionID = ownMember.activeSessionID {
                currentSessionID = restoredSessionID
            }
            snapshot.pendingSync = false
        }
        // 세 분기 모두 snapshot/accumulated 를 건드리므로 라벨 문자열을 한곳에서 재계산한다(== 가드는 내부에서).
        refreshMenuBarTitle()
        // 원격 흡수로 근무 상태가 뒤집혔으면 유예형 배너 성립 조건도 함께 뒤집힌다(다른 기기에서 시작/종료).
        refreshTimedBanner()
    }
}
