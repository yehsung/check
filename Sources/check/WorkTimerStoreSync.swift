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
            // 멤버십이 한 번도 확정된 적 없으면 '무소속'이라 단정하지 않는다. D1(실행 킥) 이후 이 분기는 팝오버를
            // 한 번도 열지 않아도 매 주기 돌기 때문에, 오프라인 부팅으로 킥이 실패해 currentTeamID 가 nil 로 남은
            // 사용자에게 "소속 팀이 없어요"가 화면 한 번 안 거치고 그대로 뜬다 — 멀쩡히 팀에 속한 사람이 팀 코드를
            // 다시 입력하러 가는 오안내다. 확정 전에는 문구를 건드리지 않고 refresh 루프의 재확정을 기다린다.
            guard membershipConfirmed else { return }
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
        // 수집 끔이면 아예 보내지 않는다. 서버 트리거가 어차피 조용히 버리므로 결과는 같지만,
        // 그 사람 맥이 30초마다 헛왕복을 도는 것을 없앤다(설정이 서버에서 도착하기 전 기본값은 수집이라,
        // 로그인 직후 한두 번은 나갈 수 있다 — 그건 서버가 막는다).
        guard tokenUsageCollect else { return }
        guard let usage, usage.total > 0 else { return }
        guard usage != lastUploadedUsage, now.timeIntervalSince(lastTokenUploadAt) >= 60 else { return }
        // 시도 시각을 먼저 스탬프해, 실패하더라도 60초 안에는 재시도하지 않는다(난사 방지).
        // 이 한 줄이 아래 await 동안의 재진입도 함께 막는다 — 진단 계산을 기다리는 사이 다른 호출이 들어와도
        // 이 스탬프에 걸려 되돌아가므로 같은 주기가 두 번 올라가지 않는다.
        lastTokenUploadAt = now
        // Codex 집계 진단(빌드+KST 날짜당 1회 = 하루 1회). **이 줄이 수집 거부 가드 뒤에 있는 것이 요건이다** — 위
        // `guard tokenUsageCollect` 에서 이미 빠져나가므로 거부자에게선 계산도 업로드도 일어나지 않는다.
        // 오늘 이미 보고했으면 nil 을 돌려주며 스캔 자체를 건너뛴다(전량 순회라 비싸다).
        // now 를 넘기는 이유: 도장 산식이 KST 날짜를 쓰는데, 판정과 아래 찍기가 **같은 now** 를 봐야
        // 자정을 걸친 업로드에서 "판정은 어제·도장은 오늘"로 갈려 하루가 통째로 재보고되는 일이 없다.
        let diagnostics = await codexDiagnosticsIfUnreported(month: usage.month, now: now)
        // 세대는 이 await 뒤에 잡는다 — 스캔을 기다리는 사이 계정이 갈렸다면 아래 요청은 새 세션으로 나가므로,
        // 비교 대상도 그 시점의 세대여야 멀쩡한 업로드가 헛되이 버려지지 않는다.
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
                    deviceID: deviceID,
                    diagnostics: diagnostics
                )
            }
            // 진단 '보고 완료' 도장은 서버 쓰기가 실제로 성공했을 때만 찍는다 — 실패하면 값이 그대로라
            // 다음 기회에 다시 계산·전송된다. 세대 가드보다 **앞**인 이유: 도장의 근거는 "이 맥의 이 빌드가
            // 이 달치 진단을 서버에 남겼다"는 사실이고, 응답을 기다리는 사이 계정이 갈렸더라도 그 사실은 변하지 않는다.
            // (여기서 멈추면 다음 주기가 0.4초짜리 전량 스캔을 한 번 더 헛돌 뿐이라 손해도 크지 않지만,
            //  같은 값을 두 번 올리는 것보다 한 번 올린 것을 정확히 기록하는 편이 낫다.)
            // 한계 하나는 분명히 해 둔다: 이 도장이 증명하는 것은 **전송 성공**이지 **저장 확인**이 아니다.
            // 서버의 수집 거부 트리거는 행을 조용히 버리고도 204 를 돌려주므로(설정이 아직 안 내려온 창에서
            // 일어날 수 있다), 그 경우 이 달의 진단은 다시 시도되지 않는다 — 거부자에게는 그게 옳은 결과다.
            // 도장에 쓰는 build/now 는 방금 판정에 쓴 값 그 자체다(진단이 잰 빌드 + 위 게이트가 본 같은 now).
            if let diagnostics {
                defaults.set(
                    Self.codexDiagnosticsStamp(build: diagnostics.appBuild, now: now),
                    forKey: Self.codexDiagnosticsReportedStampKey
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

    /// 마지막으로 Codex 진단을 **서버에 올린** 시점의 도장(UserDefaults). 값은 "<CFBundleVersion>:<KST 날짜>"
    /// 문자열이다(예 "39:2026-08-18"). 진단 관련 키는 이것 하나뿐이다 — 빌드만 담던 키는 남기지 않았다.
    ///
    /// **왜 빌드만으로는 안 되는가**(이 도장의 출발점): 진단이 답해야 하는 질문은 "**지금** 왜 부풀었나"다.
    /// 빌드 단위 도장이면 **설치당 한 번**이 되어, 한 번 찍힌 사람은 그 뒤로 거의 빈 스냅샷을 서버에 고정해 둔 채
    /// 정작 사용량만 쌓는다(실측: 이 맥의 2026-08 은 전 필드 0, 6·7월엔 실데이터).
    ///
    /// **왜 월로도 모자라는가**(월 → 날짜로 바꾼 이유, 두 가지):
    /// (1) 진단과 codex_input 의 **시각 어긋남**. codex_input 은 30초마다 갱신되는데 진단은 도장당 1회라,
    ///     월 도장이면 스냅샷과 현재값이 최대 한 달까지 벌어진다(음수 정정량 사고의 원인).
    /// (2) **재발을 못 본다**. v0.2.32 가 고친 증분 캐시 유령 항목이 다시 쌓이는지는 반복 측정으로만 보이는데,
    ///     월 도장은 사용자당 월 1표본뿐이라 시계열이 서지 않는다. 날짜 도장이면 하루 1표본이 쌓인다.
    /// 비용은 무시할 수준이다 — 전량 패스가 이 맥 실측 444파일 0.39초, 하루 한 번이다.
    ///
    /// **마이그레이션 코드는 없다.** 옛 키에 월 형식("39:2026-08")이 들어 있던 사용자는 날짜 형식과 자연히
    /// 불일치해 다음 실행에 1회 더 보고하고 그 뒤로 하루 1회 리듬을 탄다 — 그게 원하는 동작이다.
    ///
    /// **UserDefaults 에 영속하는 이유**(reportedAppVersionStamp 는 일부러 메모리에만 둔다):
    /// 저쪽은 못 보내면 남이 나에게 메시지를 못 보내는 **기능**이라 실행마다 다시 말해 자가치유해야 하지만,
    /// 이쪽은 그 달에 한 번 받으면 그만인 **계측**이고 값을 만드는 데 전량 디스크 순회가 든다. 실행마다 다시 재면
    /// 앱을 자주 켜는 사람에게만 반복 비용을 물리면서 서버에는 같은 숫자가 다시 쌓인다.
    ///
    /// 계정별 접미사가 없다: 진단은 이 **맥의 로그**를 잰 값이라 누가 로그인해 있든 같은 숫자가 나온다
    /// (deviceIDKey 와 같은 성격 — 기기 단위 사실이다).
    static let codexDiagnosticsReportedStampKey = "check.codexDiag.reportedStamp"

    /// 도장 문자열의 **유일한** 산식. 건너뛸지 판정하는 곳(codexDiagnosticsIfUnreported)과 찍는 곳
    /// (업로드 성공 지점)이 반드시 이 함수를 함께 쓴다 — 두 곳이 각자 문자열을 만들면 한 글자만 어긋나도
    /// 판정이 영영 불일치해 30초마다 전량 스캔을 도는(정반대의) 사고가 된다.
    ///
    /// 날짜는 **TokenUsageIncrementalScanner.dayBounds(now:).date** 가 준다 — 여기서 새로 계산하지 않는다.
    /// 이 저장소는 KST 경계 산식이 흩어지면 어긋난 이력이 있어, "오늘 +N" 창을 가르는 그 함수 하나만 쓴다
    /// (D1 이 usage.todayDate 에 담는 값과 같은 산식이라, 도장의 날짜와 업로드한 행의 날짜가 어긋나지 않는다).
    static func codexDiagnosticsStamp(build: Int, now: Date) -> String {
        "\(build):\(TokenUsageIncrementalScanner.dayBounds(now: now).date)"
    }

    /// 이 빌드·오늘(KST) 아직 진단을 보고하지 않았다면 계산해 돌려준다. 이미 보고했거나 빌드를 모르면 **nil**
    /// (= 업로드 본문에 codex_diag_* 키가 붙지 않고, 서버의 기존 진단값이 그대로 보존된다).
    ///
    /// 호출 규약: **반드시 `guard tokenUsageCollect` 뒤에서 부를 것.** 수집을 거부한 사람에게선 업로드는 물론
    /// 계산(홈 디렉터리 순회)도 일어나면 안 된다. 이 함수 자신은 그 플래그를 보지 않는다 — 가드는 호출부에 있다.
    ///
    /// 비싼 부분(전량 순회, 실측 0.39초/444파일)은 Task.detached(.utility) 에서 돈다. 메인 액터는 await 로
    /// 비켜 주므로 화면은 멈추지 않는다. 30초마다 이 비용을 치르지 않게 막는 것이 위의 도장이다(하루 1회로 줄인다).
    ///
    /// month 와 now 는 역할이 다르다: **month 는 무엇을 재는가**(스캐너가 집계할 대상 달 = 업로드하는 행의 달),
    /// **now 는 언제 재는가**(도장의 날짜). 둘을 한 인자로 합치지 마라 — 달 경계 첫날에 어제(지난달) 도장으로
    /// 이번 달 진단을 건너뛰거나 그 반대가 된다.
    ///
    /// 빌드를 모르면(개발 빌드 등 CFBundleVersion 미심음) 계산하지 않는다: 진단값은 **어느 산식이 만든
    /// 숫자인가**와 짝일 때만 쓸모가 있어서, 출처 없는 숫자를 서버에 남기면 코호트 분석이 오히려 오염된다
    /// (AppVersionReport 가 '모르면 침묵'을 택한 것과 같은 판단).
    ///
    /// 실패는 없다 — 스캐너는 던지지 않고, 홈에 ~/.codex 가 없으면 0으로 채운 스냅샷을 돌려준다
    /// (그 0 도 "이 기기는 Codex 를 안 쓴다"는 유효한 관측이다). 이 함수가 어떤 값을 돌려주든 본 기능인
    /// 토큰 업로드는 그대로 진행된다.
    func codexDiagnosticsIfUnreported(month: String, now: Date) async -> CodexUsageDiagnostics? {
        guard let build = appVersionProvider()?.build, build > 0 else { return nil }
        // 이 빌드 + 오늘 날짜로 이미 한 번 올렸으면 여기서 끝난다 — 스캔에 들어가지 않는다.
        guard defaults.string(forKey: Self.codexDiagnosticsReportedStampKey)
                != Self.codexDiagnosticsStamp(build: build, now: now) else { return nil }
        // 홈은 메인 액터에서 미리 읽어 값으로 넘긴다(detached 클로저가 캡처하는 것은 Sendable 한 URL 뿐).
        let home = FileManager.default.homeDirectoryForCurrentUser
        return await Task.detached(priority: .utility) {
            CodexUsageDiagnosticsScanner.compute(homeDirectory: home, month: month, appBuild: build)
        }.value
    }

    /// 근무중일 때 서버에 생존신호(last_seen_at)를 보낸다. 근무중이 아니거나 세션 정보가 없으면 보내지 않는다.
    func sendHeartbeatIfWorking() async {
        // 하트비트는 '내가 이 세션의 소유 맥이다'라는 선언이다. 흡수 세션(다른 맥이 연 세션)에서 보내면
        // work_statuses.last_seen_at 이 계속 신선해져 close_abandoned_work_sessions
        // (coalesce(last_seen_at, updated_at) < now() - 10분)가 **영영 발화하지 못한다**. 이 맥의 자동 마감
        // (잠자기·12시간·종료 동기화)이 흡수 세션을 건드리지 않게 막아 둔 상태에서 하트비트만 남으면
        // 그 세션은 '아무도 못 닫는 세션'이 된다 — 맥A 를 꺼도 맥B 가 밤새 생존신호를 대신 보내
        // 타이머가 40시간이 되고 팀원 화면은 '근무중'에 고착된다.
        // 이 한 줄이 연쇄를 닫는다: 소유 맥 사라짐 → 신호 공백 10분 → 흡수 맥 자신의 클라 스캐빈저
        // (scavengeAbandonedTeamSessionsIfNeeded 는 stale 판정에 자타 구분이 없어 내 행도 대상이고,
        // 서버 RPC 는 security definer 라 내 세션을 마감한다) → 다음 폴링이 (.offWork, .some) 로
        // 로컬을 정확히 내린다. 사용자가 직접 누른 종료(stop)는 이 가드와 무관하게 그대로 나간다.
        guard !adoptedRemoteSession else { return }
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
        // 기기별 소유 주장(work_status_devices). 위 가드를 다 통과했다는 것은 '이 맥이 이 세션의 소유자라고
        // 믿고 있다'는 뜻이므로, 그 사실을 **다른 맥이 지울 수 없는 자리**에 남긴다 — 공유 셀(work_statuses)은
        // 내가 폴링 직전에 매번 덮어써 남의 흔적이 남지 않아, 시각만으로는 다른 인스턴스의 존재를 원리적으로
        // 관측할 수 없다(실측 seen−mine = [-0.89, -0.89, -0.90]).
        // 상태 upsert 와 **별도 do/catch** 인 이유: 이 표가 없는 서버(마이그레이션 미적용)에서 404 가 나도
        // 하트비트 자체는 이미 나갔어야 하고, 실패가 위 경로의 재시도/문구에 아무 영향도 주면 안 되기 때문이다.
        guard generation == sessionGeneration else { return }
        // 강/약을 **함께** 싣는다. 이 값이 없으면 상대 맥은 내 주장이 사실인지 추측인지 알 길이 없어 반납을
        // 사전식 device_id 로 정할 수밖에 없고, 그건 랜덤 UUID 라 절반의 배치에서 진짜 소유자를 밀어낸다.
        // 매 하트비트마다 **지금의** 강도를 덮어써, 옛 세션의 strong 이 다음 세션의 약한 주장에 눌러앉지 않게 한다.
        let openedSession = ownsCurrentSessionStrongly
        do {
            try await withSessionRetry { activeSession in
                try await service.upsertStatusDevice(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    deviceID: deviceID,
                    sessionID: sessionID,
                    openedSession: openedSession
                )
            }
        } catch {
            // 주장 기록 실패는 조용히 무시한다. 못 남기면 상대 맥이 나를 '판정 불가'로 보고 백스톱(7분)으로
            // 되돌아갈 뿐이다 — v0.2.14 와 같은 수준이지 더 나빠지지 않는다.
        }
    }

    /// 서버상 내 세션이 열려 있고 로컬은 비근무(startedAt==nil, pendingItems 비어 있음)이며 마지막 신호와의
    /// 공백이 adoptedReclaimStaleSeconds(7분)를 넘으면 그 세션을 마지막 신호 시각으로 마감한다. 마감했으면 true.
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
        // 임계는 백스톱과 **같은 상수**에서 나온다(= sleepGraceSeconds + 4주기 = 7분). 하드코딩 90초이던 시절,
        // 같은 계약("이 앱 자신의 규약상 6분까지의 무신호는 정상 근무다" — adoptedReclaimStaleSeconds 주석)을
        // 두 임계가 서로 다르게 해석했다: 맥 A 가 뚜껑을 3분 닫고 낮잠 중인데(A 자신은 잠자기 유예 안이라
        // 그대로 근무를 이어간다) 맥 B 를 켜는 것만으로 A 의 **살아 있는** 세션이 마감됐다
        // (실측: PATCH 1건, ended_at = 180.9초 전, "자리 비움으로 자동 근무종료됨"). 그 뒤 A 의 근무는 통째로 유실된다.
        // 한 상수에서 파생시키면 '주장(백스톱)'과 '마감(여기)'이 구성상 어긋날 수 없어 한쪽만 바뀌는 재발이 불가능하다.
        // 상한도 그대로다: 7분 + 관측 1주기 ≈ 7.5분 < 10분(abandonedSessionThresholdSeconds) — 스캐빈저까지 여유가 남는다.
        // '지금'은 전부 주입 시계에서 온다(clock). 프로덕션은 Date() 그대로이고, 테스트는 이 계약이 KST
        // 자정과 얼마나 떨어진 시각에 실행되는지에 좌우되지 않게 시각을 고정한다.
        let now = clock()
        guard let seen = member.lastSeenAt ?? member.updatedAt,
              now.timeIntervalSince(seen) > Self.adoptedReclaimStaleSeconds
        else {
            return false
        }

        // 마감하는 세션의 '오늘 몫'(KST 자정 클리핑). 서버 스냅샷의 todayDurationSeconds 는 마감 **전** 값이라
        // 이 세션을 아직 포함하지 않으므로 여기서 더해 준다. 그래야 (1) 마감 직후 표시가 세션 몫만큼 꺼지지 않고,
        // (2) 곧 도착할 정상 폴링이 채워 넣는 서버 today(= 이 세션 포함)와 값이 같아져, 되돌리기가 폴링 전/후
        // 어느 시점에 눌리든 lastAutoClosedSeconds 를 그대로 빼면 정합해진다.
        let closedTodaySeconds = max(
            0,
            Int(seen.timeIntervalSince(max(sessionStart, TeamWeeklyGoal.koreanDayStart(for: now))))
        )
        accumulatedSeconds = member.todayDurationSeconds + closedTodaySeconds
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: now)
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
                    fallbackSessionID: Self.canonicalSessionID(member.activeSessionID)
                        ?? currentSessionID
                        ?? Self.canonicalSessionID(UUID().uuidString)!
                )
            }
            guard generation == sessionGeneration else { return true }
            // 세대 재확인(await 이후). 사용자가 왕복 중 새 근무를 시작/종료했다면 그 조작이 최신이므로
            // 서버 마감만 유효로 두고 로컬 반영(오프 스냅백 + 되돌리기 대상 등록)은 통째로 건너뛴다.
            // 서버에 열린 새 세션은 그대로 살아 있고, 지금 로컬 상태가 그 세션을 정확히 가리키고 있다.
            guard writeGeneration == workStateWriteGeneration else { return true }
            lastAutoClosedSessionID = Self.canonicalSessionID(member.activeSessionID)
            lastAutoClosedStartedAt = sessionStart
            // 이 세션을 **누가 열었는지**를 releaseSessionOwnership() 이 증거를 지우기 전에 붙잡아 둔다.
            // 되돌리기가 무조건 '강한 소유'를 주장하면 강한 소유자가 두 명이 될 수 있다: 맥 A 의 세션 S 가
            // 7분 침묵으로 **맥 B** 에게 자동 마감되고 B 사용자가 [되돌리기]를 누르면, S 를 실제로 연 것은
            // A 인데 B 도 strong 이 된다 → 두 strong 이 만나면 규칙이 다시 사전식 동전 던지기로 떨어진다.
            // 마감 전에 이 맥이 그 세션의 소유자였을 때만 강도를 물려받아, "강한 소유자는 최대 한 명"이라는
            // 이 규칙의 전제를 되돌리기 경로에서도 깨지지 않게 한다.
            lastAutoClosedClaimStrength = isOwnedByThisMac(member.activeSessionID)
                ? ownedSessionClaimStrength
                : .weak
            // 되돌릴 때 누적에서 도로 빼야 할 몫(위에서 누적에 넣은 값과 같은 수). 되돌리면 이 세션이 다시
            // 진행 세션이 되어 startedAt 기준으로 라이브 계산되므로, 빼지 않으면 그 구간을 두 번 센다.
            lastAutoClosedSeconds = closedTodaySeconds
            // 되돌리기 배너의 유효기간 시작점. 이 스탬프가 없으면 배너를 띄우지 않는다(무기한 상주 금지).
            // 판정(canUndoAutoClose)과 **같은 시계**로 찍어야 한다 — 한쪽만 실제 시각이면 시계를 고정한
            // 테스트에서 배너가 유예 밖으로 보여 되돌리기가 통째로 죽는다.
            lastAutoClosedAt = clock()
            startedAt = nil
            currentSessionID = nil
            // 이 경로는 세션을 **실제로 마감한다**(위 stopWork). 그런데 소유 표식/영속 ID 를 내리지 않아
            // 닫힌 세션 ID 가 UserDefaults 에 그대로 남았다: 다음 실행이 그 죽은 ID 를 '내 세션'으로 되찾으려
            // 들고(1차 판정 오염), 그 사이 서버가 같은 사용자에게 연 **다른** 세션이 있으면 그 세션을 내 것이라
            // 우기게 된다. 마감했으면 소유권도 함께 놓는 것이 대칭이다(stop/autoStop 과 같은 규약).
            // 위 writeGeneration 가드를 통과한 뒤라, 왕복 중 사용자가 새로 시작한 근무의 소유 ID 를
            // 지워 버릴 위험은 없다(그 경우 이 블록 자체에 들어오지 못한다).
            releaseSessionOwnership()
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
    /// now 가 Optional 인 이유는 refreshTimedBanner 와 같다(인스턴스 메서드 기본 인자는 self.clock 을 못 읽는다).
    func canUndoAutoClose(now: Date? = nil) -> Bool {
        let now = now ?? clock()
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
        // 되돌릴 세션 ID 도 정규화 경유다 — 이 값이 곧 currentSessionID/소유 ID 가 되고, 다음 폴링에서
        // 서버가 돌려주는 소문자 값과 비교된다(대문자로 들어오면 재개하자마자 흡수로 뒤집힌다).
        guard let sessionID = Self.canonicalSessionID(lastAutoClosedSessionID),
              let restoredStart = lastAutoClosedStartedAt
        else {
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
            // 되돌리기는 사용자가 이 세션의 소유권을 **명시적으로 주장한** 것이다(내 손으로 reopen 을 보냈다).
            // 표식을 내려야 하트비트가 다시 나가고, 안 그러면 재개하자마자 신호가 끊겨 10분 뒤 스캐빈저가
            // 방금 되살린 세션을 도로 마감한다. 소유 ID 도 함께 영속해, 재개 직후 앱이 재시작돼도
            // 이 세션이 다시 '남의 것'으로 판정되지 않게 한다.
            // 강도는 **마감 직전에 이 맥이 그 세션의 소유자였는가**를 그대로 물려받는다(자세한 근거는
            // autoCloseAbandonedOwnSessionIfNeeded 의 lastAutoClosedClaimStrength 주석).
            // 내가 연 세션을 내가 닫았다가 되돌린 경우에만 strong 이고, 남의 세션을 주워 닫았다가 되돌린
            // 경우는 weak 다 — 그래야 강한 소유자가 둘이 되어 규칙이 동전 던지기로 되돌아가지 않는다.
            claimSessionOwnership(sessionID, strength: lastAutoClosedClaimStrength)
            longSessionAnchor = restoredStart
            displayNow = clock()
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

    /// 별명(표시명) 변경. 서버 set_display_name 이 정규화·길이·중복·쿨타임을 **전부** 판정하고 여기서는
    /// 그 status 를 화면 문구로 옮기기만 한다. 반환값(성공 여부)으로 뷰가 편집 행을 닫을지 정한다
    /// (실패면 입력을 유지해 바로 고쳐 재시도할 수 있게 한다).
    ///
    /// **문구(syncMessage)는 반드시 refreshTeamStatus 뒤에 세운다.** 그 함수가 성공 경로 끝에서 syncMessage 를
    /// "동기화됨"으로 덮으므로 앞에 두면 안내가 즉시 사라진다 — 바로 위 performAvatarUpdate 가 같은 이유로
    /// 같은 순서를 쓴다.
    @discardableResult
    func updateDisplayName(_ raw: String) async -> Bool {
        // 연타 가드가 없으면 저장 버튼 두 번에 두 요청이 나가고, 첫 요청이 성공한 뒤 두 번째가 unchanged/cooldown 을
        // 받아 방금 성공한 화면 위에 실패 문구를 덮는다.
        guard session != nil, !isUpdatingDisplayName else { return false }
        let name = Self.normalizedDisplayName(raw)
        guard !name.isEmpty else {
            displayNameNotice = "별명을 입력해 주세요"
            isDisplayNameNoticeError = true
            return false
        }
        guard name.unicodeScalars.count <= Self.displayNameMaxLength else {
            displayNameNotice = "별명은 \(Self.displayNameMaxLength)자까지 쓸 수 있어요"
            isDisplayNameNoticeError = true
            return false
        }
        isUpdatingDisplayName = true
        defer { isUpdatingDisplayName = false }
        let generation = sessionGeneration
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.setDisplayName(accessToken: activeSession.accessToken, name: name)
            }
            guard generation == sessionGeneration else { return false }
            switch DisplayNameChangeOutcome(response: response) {
            case .ok(let applied):
                // 서버가 실제로 저장한 값을 그대로 쓴다 — 클라 정규화와 한 글자라도 다르면 다음 폴링에서
                // 이름이 눈앞에서 바뀌는 깜빡임이 된다(그래서 낙관 대입도 하지 않는다).
                let stored = applied.isEmpty ? name : applied
                if displayName != stored { displayName = stored }
                defaults.set(stored, forKey: Self.displayNameKey)
                let now = Date()
                displayNameChangedAt = now
                displayNameAvailableAt = now.addingTimeInterval(Self.displayNameCooldownSeconds)
                displayNameNotice = nil
                isDisplayNameNoticeError = false
                refreshDisplayNameLock(now: now)
                // 팀 목록 내 행 이름은 서버 응답에서 온다 — 낙관 대입 대신 왕복 후 갱신(아바타와 같은 규약).
                await refreshTeamStatus()
                guard generation == sessionGeneration else { return false }
                syncMessage = "별명 변경됨"          // ← 반드시 refresh 뒤
                return true
            case .unchanged:
                // 이미 같은 이름 — 서버가 아무것도 바꾸지 않았고 쿨타임도 소모되지 않았다. 조용히 닫는다.
                displayNameNotice = nil
                isDisplayNameNoticeError = false
                return true
            case .taken:
                displayNameNotice = "이미 쓰고 있는 별명이에요"
                isDisplayNameNoticeError = true
                return false
            case .cooldown(let retryAfterSeconds):
                // 서버가 준 잔여 시간을 **그대로** 만료 시각으로 쓴다(기준 시각 역산 없음 — 왕복은 경계에서
                // 화면의 월·일을 하루 밀어 버릴 여지만 키운다).
                let availableAt = Date().addingTimeInterval(TimeInterval(retryAfterSeconds))
                displayNameAvailableAt = availableAt
                displayNameNotice = Self.displayNameCooldownMessage(availableAt: availableAt)
                isDisplayNameNoticeError = false     // 쿨타임은 오류가 아니라 상태다.
                refreshDisplayNameLock()
                return false
            case .tooLong(let maxLength):
                displayNameNotice = "별명은 \(maxLength)자까지 쓸 수 있어요"
                isDisplayNameNoticeError = true
                return false
            case .empty:
                displayNameNotice = "별명을 입력해 주세요"
                isDisplayNameNoticeError = true
                return false
            case .invalid:
                // 마이그레이션 미적용 서버의 RPC 404(PGRST202)도 여기로 수렴한다.
                displayNameNotice = "지금은 별명을 바꿀 수 없어요"
                isDisplayNameNoticeError = true
                return false
            }
        } catch {
            guard generation == sessionGeneration else { return false }
            if case .cancelled = classifyAuthError(error) { return false }
            displayNameNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
            isDisplayNameNoticeError = true
            return false
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
        // 세션 ID 가 없어 새로 만드는 폴백도 정규화해 둔다 — 이 값이 그대로 서버 work_sessions.id 가 되고,
        // 다음 폴링에서 소문자로 되돌아와 로컬 값과 비교되기 때문이다(정규화 지점을 한 곳으로 모으는 규약).
        let fallbackSessionID = Self.canonicalSessionID(UUID().uuidString)!
        let item: PendingWorkItem
        if snapshot.isWorking {
            item = PendingWorkItem(
                id: UUID(),
                operation: .start,
                sessionID: currentSessionID ?? fallbackSessionID,
                sessionStartedAt: startedAt,
                endedAt: nil,
                ownerUserID: ownerUserID
            )
        } else {
            item = PendingWorkItem(
                id: UUID(),
                operation: .stop(durationSeconds: durationSeconds ?? todayDuration),
                sessionID: currentSessionID ?? fallbackSessionID,
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
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: clock())

        switch (ownMember.status, startedAt) {
        case (.working, nil):
            adoptRemoteSession(ownMember)
        case (.offWork, .some):
            startedAt = nil
            // 흡수 세션이든 이 맥이 연 세션이든 서버에서 이미 닫혔다 — 표식과 잔존 세션ID를 **함께** 끊는다.
            // 예전엔 currentSessionID 를 남겨, 이미 닫힌 id 가 뒤이은 경로로 서버에 되돌아갔다:
            // (1) 다음 폴링이 (.working, nil) 로 재흡수할 때 activeSessionID 가 비어 온 찢어진 읽기면
            //     이 낡은 id 가 살아남아(?? currentSessionID) 하트비트의 active_session_id 로 올라간다.
            // (2) autoCloseAbandonedOwnSessionIfNeeded 의 fallbackSessionID 사슬(member.activeSessionID
            //     ?? currentSessionID)이 닫힌 id 를 집어 폴백 POST 를 만드는데, 그 POST 는
            //     on_conflict=id + ignore-duplicates 라 서버가 **조용히 버린다** — 마감 기록이 통째로 유실된다.
            // 상태표 쪽 좀비는 트리거(20260717040000)가 강등해 주지만 work_sessions 쓰기는 걸러 주지 않는다.
            currentSessionID = nil
            // 영속된 소유 ID 도 여기서 끊는다 — 서버가 닫았다는 것은 이 맥이 되찾을 세션이 더는 없다는 뜻이다.
            // 남기면 다음 실행이 이미 닫힌 ID 를 '내 세션'으로 되찾으려 들어 죽은 세션에 하트비트를 쏜다.
            releaseSessionOwnership()
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
            // 서버가 여전히 '근무중'으로 들고 있는 그 행의 세션ID 로 되살린다.
            //
            // 세션ID 가 **다른 값으로 남아 있는** 경우는 이제 재흡수한다(계약 변경). 부분 유니크 인덱스
            // (work_sessions_one_open_per_user, where ended_at is null)상 사용자당 열린 세션은 하나뿐이라,
            // 서버가 다른 id 를 들고 있다는 것은 내가 든 id 가 **이미 닫혔다**는 뜻이다. 이 재흡수가 없으면
            // 흡수 세션의 자동 마감을 막은 뒤로 흡수 맥이 어제 시작시각을 든 채 오늘 세션을 미러링해
            // 타이머가 20시간이 된다(= 자동 마감 차단이 더 나쁜 버그가 되는 지점이라 반드시 한 커밋).
            //
            // 비교는 **반드시 정규화 경유**다. 서버가 돌려주는 값은 Postgres uuid 라 소문자이고 앱이 만든
            // 값은 대문자였다 — 원시 != 로 비교하던 시절 이 조건은 **항상 참**이었고, 그래서 근무 시작 후
            // 첫 폴링(≈30초)마다 내가 방금 연 세션이 '서버가 다른 id 를 들고 있다'로 오독돼 흡수로 뒤집혔다.
            // 흡수가 되면 하트비트가 멈추고, 그 창에서 뚜껑을 5분 넘게 닫거나 앱을 끄면 마감이 나가지 못해
            // 스캐빈저가 시작 시각으로 마감한다(= 그 근무가 0초로 기록된다).
            let localSessionID = Self.canonicalSessionID(currentSessionID)
            if ownMember.status == .working,
               let serverSessionID = Self.canonicalSessionID(ownMember.activeSessionID),
               serverSessionID != localSessionID {
                if localSessionID == nil, startedAt != nil {
                    // 강제 로그아웃 → 재로그인 복구. 진행 중 근무는 이 맥의 것 그대로이므로 표식은 건드리지 않는다.
                    // 영속된 소유 ID 도 손대지 않는다: clearPersistedSession 이 그 키를 일부러 남기므로
                    // 이 세션이 내 것이었다면 값은 이미 살아 있고, 흡수 세션이었다면 여기서 소유를 주장하는 순간
                    // 살아 있는 다른 맥의 근무를 가로챈다.
                    currentSessionID = serverSessionID
                } else if ownMember.currentSessionStartedAt != nil {
                    // 열린 세션 행이 실제로 함께 온 경우에만 재흡수한다. work_statuses 와 work_sessions 는
                    // 병렬 GET 이라(SupabaseWorkService.swift:88) 찢어진 읽기에서 상태표만 먼저 도착하면
                    // currentSessionStartedAt 이 nil 이 되고, 그대로 흡수하면 시작시각이 now 로 리셋돼
                    // 진행 중이던 근무 시간이 0초로 증발한다.
                    adoptRemoteSession(ownMember)
                }
            }
            snapshot.pendingSync = false
        }
        // 오판 자가정정(릴리스 규칙). 백스톱은 '주장하는' 방향뿐이라 한 번 틀리면 되돌릴 길이 없었다 —
        // 이 대칭 규칙이 그 고착을 푼다. 백스톱 관측보다 **앞서** 돌아야, 방금 흡수로 되돌아간 상태의
        // 첫 관측이 같은 폴링에서 곧바로 seed 되어 '전진 없음' 시계가 그 시점부터 다시 시작한다.
        releaseOwnershipIfAnotherDeviceClaims(ownMember)
        // 흡수 상태의 생존성 백스톱. 분기와 무관하게 **매 폴링** 돌아야 한다 — 정상 흡수 상태는 위 switch 의
        // default 로 빠져 아무 것도 하지 않으므로, 여기서 보지 않으면 '전진 여부'를 관측할 지점이 아예 없다.
        updateAdoptedPresenceTracking(ownMember)
        // 세 분기 모두 snapshot/accumulated 를 건드리므로 라벨 문자열을 한곳에서 재계산한다(== 가드는 내부에서).
        refreshMenuBarTitle()
        // 원격 흡수로 근무 상태가 뒤집혔으면 유예형 배너 성립 조건도 함께 뒤집힌다(다른 기기에서 시작/종료).
        refreshTimedBanner()
    }

    /// 서버가 들고 있는 내 열린 세션을 로컬 상태로 되살린다(앱 재시작 복구 / 다른 맥이 시작한 근무 미러링).
    /// 되살리는 모양은 같지만 **소유권 판정은 세션 ID 로 갈린다**:
    /// - 서버의 activeSessionID == 이 맥이 영속해 둔 소유 ID → 내가 **이전 실행에서 연 내 세션**이다.
    ///   표식을 내려 하트비트를 즉시 재개한다. 이 갈래가 없던 시절엔 근무 중 재시작이 반드시 흡수로 판정돼
    ///   생존신호가 영구 정지했고, 90초 뒤 팀원 화면은 '연결 끊김', 10분 뒤 내 앱 자신의 스캐빈저가
    ///   내 살아 있는 세션을 마감했다(사유 문구도 되돌리기도 없이).
    /// - 다르거나 알 수 없으면 → 다른 맥이 연 세션이다. adoptedRemoteSession 표식을 세워 이 맥의 자동 마감
    ///   경로와 하트비트를 그 세션에서 통째로 물러나게 한다(사용자가 직접 누른 종료는 그대로 허용).
    ///
    /// 대입은 전부 != 가드를 건다. 이 함수는 재흡수 경로에서 30초 폴링마다 재진입할 수 있는데,
    /// @Observable 은 같은 값 대입도 관찰자를 발화시켜 팝오버 서브트리 전체가 매 폴링 무효화된다.
    /// (호출자인 applyRemoteOwnStatus 가 끝에서 refreshMenuBarTitle/refreshTimedBanner 를 부르므로 여기선 생략한다.)
    private func adoptRemoteSession(_ ownMember: TeamMemberStatus) {
        let restoredStart = ownMember.currentSessionStartedAt ?? clock()
        displayNow = clock()
        if startedAt != restoredStart { startedAt = restoredStart }
        // activeSessionID 가 비어 온 찢어진 읽기에서는 내가 들고 있던 id 를 유지한다(nil 로 덮으면 하트비트가 끊긴다).
        // 서버에서 온 값은 여기서 정규화한다 — 아래 1차 판정(isOwnedByThisMac)과 currentSessionID 대입이
        // 모두 이 값을 쓰므로, 이 한 줄이 '서버 소문자 vs 로컬 대문자' 축을 이 함수 전체에서 없앤다.
        let resolvedID = Self.canonicalSessionID(ownMember.activeSessionID) ?? currentSessionID
        if currentSessionID != resolvedID { currentSessionID = resolvedID }
        // 12시간 카운터도 서버 시작시각 기준으로 되맞춘다 — 옛 앵커를 남기면 흡수 직후 확인 배너가 즉시 터진다.
        if longSessionAnchor != restoredStart { longSessionAnchor = restoredStart }
        clearLongSessionPrompt()
        // 직전 로컬 세션이 남긴 잠자기 스탬프를 끊는다. 남겨 두면 깨어날 때 남의 세션을 옛 잠자기 시각으로 마감한다.
        sleepBeganAt = nil
        // 1차 판정(결정적). start() 가 클라에서 만든 세션 ID 를 영속해 두므로, 서버가 든 ID 와 같으면
        // 그건 '재시작한 나'이지 '남의 맥'이 아니다 — 이 한 줄이 재시작 자살 연쇄를 끊는다.
        if isOwnedByThisMac(resolvedID) {
            // 강도는 **영속된 값을 그대로 물려받는다**(strong 으로 승격시키지 않는다). 이 갈래는 "영속해 둔
            // 소유 ID 와 서버 세션이 같다"만 말하는데, 그 ID 는 start() 가 남긴 것일 수도 있고 백스톱이
            // 추측으로 남긴 것일 수도 있다. 여기서 strong 으로 올리면 추측이 **재시작 한 번으로 사실이 되어**
            // (weak→persist→restart→strong) 진짜 소유자가 이 맥 앞에서 물러난다 — 없애려던 사고를
            // 세탁 경로로 되살리는 셈이다.
            claimSessionOwnership(resolvedID, strength: ownedSessionClaimStrength)
        } else {
            adoptedRemoteSession = true
            // 생존신호 관측은 이 세션에 대해 처음부터 다시 시작해야 한다(직전 세션의 신호를 근거로 쓰면
            // 첫 폴링에 곧장 소유권을 주장해 살아 있는 남의 근무를 가로챈다). 초기화는 호출자 뒤에 도는
            // updateAdoptedPresenceTracking 이 세션 ID 불일치를 보고 수행한다.
        }
        snapshot = WorkStatusSnapshot(
            status: .working,
            elapsedSeconds: max(0, Int(displayNow.timeIntervalSince(restoredStart)))
        )
        startTimer()
    }

    /// 생존성 백스톱(2차). 영속된 소유 ID 가 없는 실행에서도 내 세션을 되찾게 하는 유일한 구조대다.
    /// **가장 중요한 케이스는 v0.2.14 → v0.2.15 업그레이드 재시작**이다 — 그 순간 근무 중인 사람은 전원이
    /// 소유 ID 없이 재시작하므로, 1차 판정만으로는 한 명도 빠짐없이 '내 앱이 내 세션을 죽이는' 연쇄를 탄다.
    ///
    /// 판정은 신선도가 아니라 **전진 여부**다. 살아 있는 소유 인스턴스가 있으면 30초마다 하트비트로
    /// last_seen_at 이 전진하므로 절대 주장하지 않는다(= 원래 D2 성질 보존). 신선도만 보면 빠른 재시작
    /// (신호가 아직 신선)과 살아 있는 남의 근무를 가를 수 없어 반드시 전진을 본다.
    ///
    /// 주장하려면 **세 조건이 모두** 성립해야 한다(하나라도 빠지면 살아 있는 맥의 근무를 가로챈다):
    ///  1. 연속 '전진 없음'을 adoptedReclaimMinObservations 회 이상 관측했다,
    ///  2. **내 시계로 잰** 정체 지속이 adoptedReclaimStaleSeconds(7분) 이상이다,
    ///  3. 신호의 나이(now - lastSeenAt)도 같은 임계를 넘었다.
    /// 2 와 3 을 함께 요구하는 이유는 last_seen_at 을 **상대가 자기 시계로 쓰기** 때문이다
    /// (SupabaseWorkService.upsertStatus — DB 기본값/트리거가 덮어 주지 않는다). 나이만 보면 두 맥의 시계가
    /// 어긋난 만큼 처음부터 임계를 넘긴 것처럼 보여, 하트비트가 딱 한 번 밀리는 순간 곧바로 주장이 성립했다.
    /// 반대로 내 시계로 잰 정체만 보면 상대가 값을 아주 느리게라도 갱신하는 병리 상황을 못 거른다.
    ///
    /// 임계가 90초가 아니라 7분인 이유는 adoptedReclaimStaleSeconds 주석을 보라 — 이 앱 자신의 계약상
    /// 6분까지의 무신호는 정상 근무다(잠자기 5분 유예). 노출 상한은 임계 + 관측 1주기 ≈ 7.5분이라
    /// 10분 스캐빈저보다 여전히 앞선다.
    func updateAdoptedPresenceTracking(_ ownMember: TeamMemberStatus, now: Date = Date()) {
        guard adoptedRemoteSession, startedAt != nil else {
            resetAdoptedPresenceTracking()
            return
        }
        let seen = ownMember.lastSeenAt ?? ownMember.updatedAt
        let sessionID = Self.canonicalSessionID(currentSessionID)
        // 첫 관측(또는 세션이 바뀐 직후)은 비교 대상이 없다 — 값만 적어 두고 다음 폴링을 기다린다.
        // 여기서 나이만 보고 주장하면, 네트워크가 잠깐 끊겨 신호가 밀린 살아 있는 맥의 근무를 가로챈다.
        guard adoptedLastSeenSessionID == sessionID, let previous = adoptedLastSeenAt else {
            adoptedLastSeenSessionID = sessionID
            adoptedLastSeenAt = seen
            adoptedStallBeganAt = nil
            adoptedStallObservations = 0
            return
        }
        if let seen, seen > previous {
            // 전진했다 = 다른 인스턴스가 살아서 하트비트를 보내고 있다. 흡수 상태를 그대로 유지하고
            // 정체 장부를 **완전히 되돌린다** — 누적으로 세면 '가끔 한 번 밀리는' 정상 맥도 결국 임계에 닿는다.
            adoptedLastSeenAt = seen
            adoptedStallBeganAt = nil
            adoptedStallObservations = 0
            return
        }
        // 신호 미상(seen == nil)은 presence 규칙과 같이 '살아 있음'으로 본다 — 모를 때 뺏지 않는다.
        // 정체 장부도 건드리지 않는다(서버가 값을 잠깐 빼먹은 것으로 주장이 성립해선 안 된다).
        guard let seen else { return }
        // 전진 없음. 정체의 시작을 **내 시계로** 찍고 관측 횟수를 센다.
        if adoptedStallBeganAt == nil { adoptedStallBeganAt = now }
        adoptedStallObservations += 1
        guard adoptedStallObservations >= Self.adoptedReclaimMinObservations,
              let stallBeganAt = adoptedStallBeganAt,
              now.timeIntervalSince(stallBeganAt) >= Self.adoptedReclaimStaleSeconds,
              now.timeIntervalSince(seen) > Self.adoptedReclaimStaleSeconds
        else {
            return
        }
        // 전진 없음이 여러 폴링에 걸쳐 7분 넘게 확인됐다 — 하지만 **남의 기기가 이 세션을 주장한 기록이
        // 있으면 되찾지 않는다**(강약 불문). 그 행은 "이 세션을 연/돌보던 맥이 따로 있다"는 물증이다:
        // 그 맥이 죽었다면 옳은 결말은 스캐빈저가 마지막 신호 시각으로 마감하는 것이지(+10분, ended_at 정확),
        // 내가 이어받아 하트비트로 되살리는 것이 아니다 — 이어받는 순간 last_seen 이 계속 신선해져 스캐빈저가
        // 영영 발화하지 못하고, 뚜껑 닫고 퇴근한 사람의 타이머가 밤새 흐른다(사용자 불만 "원하지 않는데
        // 계속 동작"의 원인). 그 맥이 살아 있다면 신호가 다시 전진해 어차피 여기 오지 않는다.
        // 내 기기 행이거나 행이 아예 없으면(구버전 맥/표 없는 서버 = 판정 불가) 원래대로 이어받는다 —
        // 업그레이드 재시작·소유 ID 유실 실행의 자기 구조는 그대로 살아 있어야 한다.
        let foreignDeviceClaimsThisSession = ownMember.deviceClaims.contains { claim in
            !claim.deviceID.isEmpty
                && claim.deviceID != deviceID
                && Self.canonicalSessionID(claim.sessionID) == sessionID
        }
        guard !foreignDeviceClaimsThisSession else { return }
        // 이 세션을 돌보는 인스턴스가 아무 데도 없다는 뜻이므로 내가 이어받는다 — 안 그러면 아무도 닫지
        // 못한 채 방치되고 타이머만 계속 흐른다.
        // **약한 소유**: 이건 관측에 근거한 추측이지 사실이 아니다. 상대의 네트워크가 7분 끊겼을 뿐일 수도
        // 있고, 그때 진짜 소유 맥이 돌아오면 **내가** 물러나야 한다. 이 한 줄이 그 판정을 결정적으로 만든다
        // (예전엔 사전식 device_id 비교라 정확히 절반의 배치에서 진짜 소유자가 대신 물러났다).
        claimSessionOwnership(currentSessionID, strength: .weak)
    }

    /// 오판 자가정정(릴리스 규칙). 백스톱/1차 판정은 소유권을 **세우는** 방향뿐이라, 한 번 잘못 주장하면
    /// 남의 세션 ID 가 이 맥의 소유 ID 로 영속되어 재시작해도 그대로 '내 세션'으로 확정됐다(영구 고착).
    /// 그 상태를 두면 두 맥이 같은 세션에 생존신호를 쏘아 스캐빈저가 영영 발화하지 못하고, 한쪽의 잠자기가
    /// 다른 쪽의 **살아 있는** 근무를 자기가 뚜껑 닫은 시각으로 마감한다(그 뒤 근무 전량 유실).
    ///
    /// **왜 시각 비교가 아니라 기기 신원인가**(이 함수의 전부다): 폴링 루프는 하트비트를 먼저 쓰고 그 다음
    /// 읽는다(WorkTimerStore.startStatusRefreshLoop). 그래서 work_statuses 에서 읽히는 last_seen_at 은 언제나
    /// 1초 전 내가 쓴 내 값이고(계량 실증 seen−mine = [-0.89, -0.89, -0.90]), 상대가 그 사이 쓴 값은 내 다음
    /// 쓰기에 덮여 내 눈에 띄지 않는다. 즉 **시각만으로는 다른 인스턴스의 존재를 원리적으로 관측할 수 없다** —
    /// 옛 규칙(서버 신호가 내 하트비트보다 60초 앞서면 반납)은 상대 시계가 내 앞에 있을 때만 발화했으니,
    /// 시계가 맞을수록 죽는 규칙이었다. 그 자리를 기기별 행(work_status_devices)이 대신한다: 내 upsert 는
    /// 남의 행을 건드릴 수 없으므로 증거가 지워지지 않는다.
    ///
    /// 반납하려면 **네 조건이 모두** 성립해야 한다(하나라도 빠지면 멀쩡한 내 근무를 스스로 놓는다):
    ///  1. 그 행이 **남의 기기**다(내 기기 행은 내가 쓴 것이라 정보량이 0 이다),
    ///  2. 그 행이 **내 세션 ID** 를 들고 있다 — 없으면 정상적인 맥 간 인수인계(A 가 끝내고 B 가 새 세션 시작)에서
    ///     B 가 방금 연 자기 세션을 남의 것으로 오인해 즉시 반납한다,
    ///  3. 그 행의 last_seen_at 이 **직전 폴링 대비 전진**했다 — 첫 관측은 증거가 아니다(그 행은 몇 시간 전
    ///     죽은 맥이 남긴 화석일 수 있다). 그래서 감지에 2폴링(≈60초)이 걸리지만, 사고(뚜껑 6분)까지는 넉넉하다,
    ///  4. **내가 물러날 쪽이다**(yieldsToClaim — 주장 강도 우선, 동급일 때만 사전식). 아래 함수 주석 참조.
    ///
    /// **일방향 원칙**: 신선하게 전진하는 남의 주장은 반납의 증거다. 그 **부재는 아무것도 증명하지 않는다** —
    /// 기기 행이 없다고 "내가 유일 소유자"라고 단정하지 않는다(소유 주장은 여전히 1차 판정 + 백스톱 7분만 한다).
    /// 이 한 줄이 혼합 함대(이 표를 모르는 v0.2.10~v0.2.16 맥)의 침묵을 '다른 맥 없음'으로 승격시키지 않는다.
    func releaseOwnershipIfAnotherDeviceClaims(_ ownMember: TeamMemberStatus) {
        guard !adoptedRemoteSession, startedAt != nil, ownMember.status == .working else { return }
        guard let sessionID = Self.canonicalSessionID(currentSessionID) else { return }
        // 서버가 다른 세션을 들고 있는 경우는 이 규칙의 대상이 아니다(재흡수 분기가 이미 처리한다).
        guard Self.canonicalSessionID(ownMember.activeSessionID) == sessionID else { return }
        // 세션이 바뀌었으면 장부를 처음부터 — 이전 세션에서 본 남의 신호를 새 세션의 '전진' 근거로 쓰면
        // 방금 내가 연 세션을 첫 폴링에 그대로 반납한다.
        if foreignDeviceTrackingSessionID != sessionID {
            foreignDeviceTrackingSessionID = sessionID
            foreignDeviceLastSeenAt = [:]
        }

        var shouldRelease = false
        for claim in ownMember.deviceClaims {
            guard !claim.deviceID.isEmpty, claim.deviceID != deviceID else { continue }
            // 서버가 uuid 를 소문자로 돌려주므로 세션 비교는 반드시 정규화 경유다(원시 비교였다면 이 조건이
            // 항상 거짓이 되어 규칙이 통째로 죽는다 — canonicalSessionID 주석의 그 함정 그대로다).
            guard Self.canonicalSessionID(claim.sessionID) == sessionID else { continue }
            guard let seen = claim.lastSeenAt else { continue }
            let previous = foreignDeviceLastSeenAt[claim.deviceID]
            foreignDeviceLastSeenAt[claim.deviceID] = seen
            // 첫 관측은 값만 적어 두고 판정하지 않는다(전진을 봐야 '지금 살아 있다'가 성립한다).
            guard let previous, seen > previous else { continue }
            // 여기까지 왔다 = "살아 있는 **남의 맥**이 **내 세션**에 지금 신호를 보내고 있다"는 사실이 섰다.
            // 남은 질문은 하나뿐이다 — 둘 중 누가 물러나는가.
            guard yieldsToClaim(claim) else { continue }
            shouldRelease = true
        }
        guard shouldRelease else { return }

        // 소유권 반납. releaseSessionOwnership() 을 쓰지 않는 이유는 그 함수가 표식을 **내려서**
        // '내가 연 세션'으로 만들기 때문이다 — 여기서 필요한 것은 정확히 그 반대(흡수 상태로 복귀)다.
        adoptedRemoteSession = true
        setOwnedWorkSessionID(nil)
        // 관측 장부를 비워 백스톱이 이 세션을 처음부터 다시 지켜보게 한다. 상대가 정말 살아 있으면 값이
        // 계속 전진해 영영 주장하지 않고, 상대가 사라지면 7분 뒤 정상적으로 되찾는다.
        resetAdoptedPresenceTracking()
        resetForeignDeviceTracking()
    }

    /// 살아 있는 남의 주장 앞에서 **내가** 물러나야 하는가. 반납 규칙의 마지막 한 줄이자, 이 라운드가 바꾼 것.
    ///
    /// **예전(사전식 단독)**: `claim.deviceID < deviceID`. 이 비교는 "누가 진짜 세션을 열었는가"를 전혀 보지
    /// 않는다. deviceID 는 랜덤 UUID 라 두 배치가 정확히 50:50 이고, 절반에서는 **진짜 소유자가 물러났다** —
    /// 그 뒤 오판한 맥이 뚜껑을 6분 닫으면 살아 있는 세션이 마감되고, 진짜 소유자의 수동 [근무 종료]는
    /// `ended_at=is.null` 필터가 0행이라 PATCH 도 못 하고 폴백 POST 도 ignore-duplicates 로 서버가 버려서
    /// **마감 기록이 0건**이 된다(= v0.2.16 사고가 바이트 그대로 재현). 동전 던지기가 유일한 결정자였다.
    ///
    /// **지금**: 앱 안에 이미 결정적 구분자가 있다. 소유는 두 출처로만 생긴다 —
    /// start()/되돌리기 재개가 세운 **강한 소유**(이 맥이 실제로 열었다)와 백스톱이 세운 **약한 소유**(추측).
    /// `work_sessions_one_open_per_user` 부분 유니크상 열린 세션은 사용자당 하나뿐이라 **강한 소유자는 최대
    /// 한 명**이다. 그러므로 규칙은 자명하다: **약한 쪽이 언제나 강한 쪽에게 물러난다.** 배치(사전식 순서)와
    /// 무관하게 항상 진짜 소유자가 남는다.
    ///
    /// 둘 다 약할 때만 사전식으로 대칭을 깬다. 이 폴백이 없으면 양쪽이 서로를 보고 동시에 반납해 아무도
    /// 하트비트를 안 보내고, 7분 뒤 양쪽이 동시에 재주장하는 7.5분 주기 발진이 생긴다(그 사이 두 맥 다
    /// 흡수 상태라 자기 잠자기·종료 마감조차 걸지 못한다). 진 쪽은 흡수 = 미러링이라 화면 표시는 정상이다.
    ///
    /// 둘 다 강한 경우(위 유니크 인덱스상 성립할 수 없다 — 서버가 두 번째 start 를 23505 로 거절한다)에도
    /// 사전식으로 떨어뜨린다: 불가능하다고 믿는 상태에서 **아무도 물러나지 않는 것**이 가장 나쁘기 때문이다.
    private func yieldsToClaim(_ claim: StatusDeviceClaim) -> Bool {
        // 강/약이 갈리면 강한 쪽이 이긴다(= 약한 쪽인 내가 물러난다).
        if claim.openedSession != ownsCurrentSessionStrongly {
            return claim.openedSession
        }
        // 동급이면 결정적·대칭인 사전식으로 정확히 한쪽만 물러나게 한다.
        return claim.deviceID < deviceID
    }
}
