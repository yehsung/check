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
            await applyFetchedTeamStatuses(members, generation: generation, writeGeneration: writeGeneration)
        } catch {
            // 취소(.task 취소/팝오버 빨리 닫기)는 실패 문구를 남기지 않고 조용히 빠져나간다(사용자 헛경보 금지).
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
        }
    }

    /// 팀 상태 **수신 성공 → 반영**(refreshTeamStatus 의 후반을 그대로 떼어 낸 것 — v0.2.38 S3).
    /// 기존 4 GET 경로와 work_tick 경로가 이 한 함수를 부른다: 세대 가드 → 신선도 스탬프 → 팀 목록 → 전이 감지 →
    /// 방치 세션 자동 마감 → applyRemoteOwnStatus(잠자기 마커 소비 포함) → 스캐빈저 → 문구 정규화의 **순서가 계약**이다.
    /// generation/writeGeneration 은 호출자가 **발사 전에** 캡처한 값이어야 한다(응답 반영 시점이 아니라).
    func applyFetchedTeamStatuses(_ members: [TeamMemberStatus], generation: Int, writeGeneration: Int) async {
        guard generation == sessionGeneration else { return }
        // 성공 수신 시각(팝오버 재오픈 15초 스로틀의 근거 — Q10). 실패/취소는 찍지 않아 다음 오픈이 다시 받는다.
        lastTeamStatusAt = clock()
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
        // applyRemoteOwnStatus 의 강하 통보/잠자기 정정(v0.2.36 W3)이 방금 세운 문구를 같은 패스의
        // "동기화됨" 정규화가 즉시 덮으면 통보는 존재한 적이 없는 것과 같다(침묵 그대로 재현).
        // 이번 호출이 문구를 바꿨을 때만 이 주기의 정규화를 건너뛰고, 다음 정상 폴링이 평소처럼
        // 정규화한다 — autoCloseAbandonedOwnSessionIfNeeded 의 조기 반환이 만드는 것과 같은
        // 한 주기 노출이다(그쪽 문구도 다음 폴링에 "동기화됨"으로 덮인다).
        let messageBeforeApply = syncMessage
        applyRemoteOwnStatus(writeGeneration: writeGeneration)
        stopTimerIfIdle()
        scavengeAbandonedTeamSessionsIfNeeded()
        if syncMessage == messageBeforeApply, syncMessage != "동기화됨" { syncMessage = "동기화됨" }
    }

    // MARK: - 근무 틱 통합 RPC work_tick (v0.2.38 S3 / docs/work-tick.md)

    /// 컴파일 타임 킬스위치. false 면 아래 전부 죽고 v0.2.37 의 다중 호출 경로 그대로다(서버측 킬스위치는
    /// `revoke execute … from authenticated` 한 줄 — 클라는 403 을 보고 이 실행 동안 폴백한다).
    static let workTickEnabled = true

    /// 폴링 본문의 `workTickIfPossible()` 이 되맞춤(reconcileRealtimeWithWorkState) 뒤에 마저 할 일을 넘기는 손잡이.
    /// 기존 순서 `하트비트 → 팀 상태 → 되맞춤 → away` 에서 되맞춤이 팀 상태와 away 사이에 있으므로, 한 응답으로
    /// 받은 away 조각의 **반영 시점**을 그 자리에 맞추려면 틱을 둘로 나눠야 한다(의미 불변).
    enum WorkTickAwayHandoff: Equatable {
        /// RPC 성공 — away 조각을 들고 있다. `finishWorkTick` 이 기존 refreshAwayStateIfNeeded 와 같은 가드로 반영한다.
        case fromTick(away: AwaySyncResponse?, ownerUserID: String, generation: Int)
        /// 폴백 — `finishWorkTick` 이 기존 `refreshAwayStateIfNeeded()` 를 그대로 부른다(요청도 그쪽이 낸다).
        case fallback
        /// 취소·세대 변화 — 아무것도 더 하지 않는다(기존 경로도 이 경우 조용히 빠져나갔다).
        case skipped
    }

    /// 30초 폴링 본문의 `sendHeartbeatIfWorking → refreshTeamStatus` 자리(+ away 조각 수령). 가용하면 work_tick 1건,
    /// 아니면 **그 두 함수를 같은 순서로** 부른다. 실패한 틱은 반드시 폴백으로 즉시 재수행한다(하트비트 유실 창 금지 —
    /// 서버는 하트비트 실패 시 전체를 실패시키므로 실패 응답 = 쓰기 0건이 보장되어 재수행이 안전하다).
    ///
    /// 무소속(`currentTeamID == nil`)은 통합 대상이 아니다: 기존 경로가 팀 GET 을 내지 않아 합칠 것이 없고
    /// (away_sync 만 120초 스로틀로), work_tick 으로 바꾸면 그 사용자에게 요청이 오히려 늘어난다. 기존 함수로 보낸다.
    func workTickIfPossible() async -> WorkTickAwayHandoff {
        guard Self.workTickEnabled, let session, let teamID = currentTeamID else {
            await sendHeartbeatIfWorking()
            await refreshTeamStatus()
            return .fallback
        }
        guard service.workTickGate.isAvailable(now: clock()) else {
            // 이 실행 동안 꺼졌거나(404/403/계약) 1시간 정지 중 — 기존 경로 그대로(진단 카운터만 올린다).
            service.workTickGate.recordFallback()
            await sendHeartbeatIfWorking()
            await refreshTeamStatus()
            return .fallback
        }

        let now = clock()
        // [sendHeartbeatIfWorking 의 앞부분 그대로] 입력 관측은 소유 여부보다 앞이다 — 어느 맥이 세션을 열었든
        // "이 맥에서 사람이 타이핑하고 있다" 는 사실은 같은 무게를 갖는다(주석은 그 함수에 있다).
        let observedInput = advanceMeaningfulInput(now: now)
        // 상태별 인자(docs/work-tick.md 4.4 표). 값의 출처는 기존 요청과 같다:
        //  · 소유 맥: p_session_id = currentSessionID, opened = ownsCurrentSessionStrongly, 입력 관측 → ①+②
        //  · 흡수 맥: p_session_id 없음 + 입력 관측 → ②′(관측 없음이면 서버가 skipped = 쓰기 0, 기존과 같다)
        //  · 세션 ID 없는 소유 맥(강제 로그아웃 후 재로그인 복구 전): 기존 sendHeartbeatIfWorking 이 조용히 반환하던
        //    상태라 p_heartbeat=false(조회만) — 세션 ID 는 applyRemoteOwnStatus 의 default 가지가 되살린다.
        var heartbeat = startedAt != nil
        var sessionID: String?
        var deviceIDToSend: String?
        var openedSession = false
        var lastInputAt: Date?
        if heartbeat {
            if adoptedRemoteSession {
                deviceIDToSend = deviceID
                lastInputAt = observedInput
            } else if let current = currentSessionID {
                sessionID = current
                deviceIDToSend = deviceID
                openedSession = ownsCurrentSessionStrongly
                lastInputAt = observedInput
            } else {
                heartbeat = false
            }
        }
        // 팀 메타는 팝오버가 열려 있고 60초 스로틀을 지났을 때만 싣는다. 스탬프는 setMenuPresented 의
        // refreshTeamMetaIfStale 과 **같은 값**을 보므로 이중 발사가 없다. 실패하면 스탬프를 되돌려 다음 기회가 산다.
        let includeMeta = isMenuPresented
            && now.timeIntervalSince(lastTeamMetaRefreshAt) >= Self.teamMetaRefreshThrottleSeconds
        let metaStampBefore = lastTeamMetaRefreshAt
        if includeMeta { lastTeamMetaRefreshAt = now }

        // 기존 refreshTeamStatus 와 같은 세대 캡처(발사 전). 하트비트 결과는 세대와 무관하게 서버에 이미 반영된 것이라
        // 되돌리지 않는다(기존 하트비트도 ack 로 아무것도 안 했다).
        let generation = sessionGeneration
        let writeGeneration = workStateWriteGeneration
        let goalWriteGeneration = teamGoalWriteGeneration
        let ownerUserID = session.userID
        let outcome = await performWorkTick(
            teamID: teamID,
            heartbeat: heartbeat,
            sessionID: sessionID,
            deviceID: deviceIDToSend,
            openedSession: openedSession,
            lastInputAt: lastInputAt,
            includeMeta: includeMeta
        )
        switch outcome {
        case .cancelled:
            return .skipped
        case .failed:
            // 이 틱을 기존 경로로 즉시 재수행한다. 메타 스탬프는 되돌린다(이번 틱엔 메타를 못 받았다).
            if includeMeta, lastTeamMetaRefreshAt == now { lastTeamMetaRefreshAt = metaStampBefore }
            service.workTickGate.recordFallback()
            await sendHeartbeatIfWorking()
            await refreshTeamStatus()
            return .fallback
        case .success(let response, let members):
            await applyFetchedTeamStatuses(members, generation: generation, writeGeneration: writeGeneration)
            guard generation == sessionGeneration else { return .skipped }
            if let meta = response.meta {
                applyTeamMeta(meta, goalWriteGeneration: goalWriteGeneration)
            }
            return .fromTick(away: response.away, ownerUserID: ownerUserID, generation: generation)
        }
    }

    /// 폴링 본문에서 되맞춤 뒤에 부른다: RPC 로 받은 away 조각을 **기존 refreshAwayStateIfNeeded 와 같은 가드**로
    /// 반영하거나(세션 없음 → 비움 / 비근무 120초 스로틀 안 → 무시 / 스탬프 → 세대·계정 확인 → applyAwaySync),
    /// 폴백이면 그 함수를 그대로 부른다. 스로틀 판정의 `startedAt` 은 이 시점(팀 상태 반영 **뒤**) 값이다 — 기존과 같다.
    /// 비근무 스로틀을 유지하는 이유: work_tick 은 조각을 매 틱 실어 오지만, "비근무에선 2분에 한 번만 판정 재료를
    /// 갱신한다" 는 클라의 반영 의미까지 바꾸지 않기 위해서다(요청 수와 무관한 의미 축).
    func finishWorkTick(_ handoff: WorkTickAwayHandoff) async {
        switch handoff {
        case .skipped:
            return
        case .fallback:
            await refreshAwayStateIfNeeded()
        case .fromTick(let away, let ownerUserID, let generation):
            let now = clock()
            guard let session else {
                clearAwayState()
                return
            }
            if startedAt == nil, now.timeIntervalSince(lastAwaySyncAt) < Self.awaySyncIdleThrottleSeconds {
                return
            }
            lastAwaySyncAt = now
            guard generation == sessionGeneration, session.userID == ownerUserID else { return }
            if let away {
                applyAwaySync(await service.awaySync(from: away), ownerUserID: ownerUserID)
            } else {
                // 조각이 비어 왔다 — 기존 네트워크 실패와 같은 "모른다" 로 접는다(정책을 비워 마감을 멈춘다).
                awayPolicy = nil
                awayOpenSession = nil
            }
        }
    }

    /// 팝오버 즉시 새로고침(activateStoredSession fast path, 15초 신선도 스로틀 뒤)의 팀 상태 1회.
    /// 가용하면 `p_heartbeat=false` 의 work_tick 1건(쓰기 0 — 지금도 refreshTeamStatus 는 하트비트를 안 보낸다),
    /// 아니면 기존 `refreshTeamStatus()`. away/meta 조각은 **반영하지 않는다** — 기존 fast path 도 팀 상태만 받았다.
    func refreshTeamStatusOnDemand() async {
        guard Self.workTickEnabled, session != nil, let teamID = currentTeamID else {
            await refreshTeamStatus()
            return
        }
        guard service.workTickGate.isAvailable(now: clock()) else {
            service.workTickGate.recordFallback()
            await refreshTeamStatus()
            return
        }
        let generation = sessionGeneration
        let writeGeneration = workStateWriteGeneration
        let outcome = await performWorkTick(
            teamID: teamID, heartbeat: false, sessionID: nil, deviceID: nil,
            openedSession: false, lastInputAt: nil, includeMeta: false
        )
        switch outcome {
        case .cancelled:
            return
        case .failed:
            service.workTickGate.recordFallback()
            await refreshTeamStatus()
        case .success(_, let members):
            await applyFetchedTeamStatuses(members, generation: generation, writeGeneration: writeGeneration)
        }
    }

    /// work_tick 한 번의 결과. 성공이면 팀 조각을 `assembleTeamStatuses` 로 조립해 함께 돌려준다(4 GET 경로와 같은 함수).
    enum WorkTickCallOutcome {
        case success(WorkTickResponse, members: [TeamMemberStatus])
        case failed
        case cancelled
    }

    /// 요청 조립·발사·실패 분류(게이트 갱신)까지. 상태 반영은 호출자가 한다.
    /// `p_seen_at`/`p_since`/조립 `now` 는 **벽시계**(기존 upsertStatus 의 `Date()`·fetchTeamStatuses 의 `now: Date()`
    /// 그대로)이고, 게이트의 시각만 주입 시계(clock)다 — 1시간 정지의 만료를 테스트가 시계 전진으로 재현한다.
    private func performWorkTick(
        teamID: String,
        heartbeat: Bool,
        sessionID: String?,
        deviceID: String?,
        openedSession: Bool,
        lastInputAt: Date?,
        includeMeta: Bool
    ) async -> WorkTickCallOutcome {
        let wall = Date()
        let request = await service.makeWorkTickRequest(
            teamID: teamID,
            heartbeat: heartbeat,
            sessionID: sessionID,
            deviceID: deviceID,
            openedSession: openedSession,
            lastInputAt: lastInputAt,
            includeMeta: includeMeta,
            now: wall
        )
        let gate = service.workTickGate
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.workTick(accessToken: activeSession.accessToken, request: request)
            }
            var serverNow: Date?
            if let raw = response.serverNow { serverNow = await service.parseDate(raw) }
            gate.recordSuccess(serverNow: serverNow, localNow: Date())
            let members = await service.assembleTeamStatuses(
                rows: response.statuses ?? [],
                active: response.sessionsActive ?? [],
                weekly: response.sessionsWeekly ?? [],
                devices: response.devices ?? [],
                now: wall
            )
            return .success(response, members: members)
        } catch let failure as WorkTickFailure {
            let now = clock()
            switch failure {
            case .functionMissing(let code):
                gate.disable(reason: "404 함수 없음\(code.map { " \($0)" } ?? "")", at: now)
            case .forbidden(let code):
                gate.disable(reason: "403 실행권 없음\(code.map { " \($0)" } ?? "")", at: now)
            case .contractMismatch(let version):
                gate.disable(reason: "계약 v=\(version.map { String($0) } ?? "없음")", at: now)
            case .undecodable:
                gate.disable(reason: "응답 해석 실패", at: now)
            case .serverError(let status):
                gate.recordTransientFailure(reason: "HTTP \(status)", at: now)
            case .rejected(let status, let code):
                gate.recordTransientFailure(reason: "HTTP \(status)\(code.map { " \($0)" } ?? "")", at: now)
            }
            return .failed
        } catch {
            // 취소는 실패로 세지 않는다(팝오버 빨리 닫기·루프 취소). 그 밖(네트워크·토큰 갱신 실패)은 일시 실패다 —
            // 폴백 경로가 같은 오류를 만나 기존 문구 규약대로 알린다.
            if case .cancelled = classifyAuthError(error) { return .cancelled }
            gate.recordTransientFailure(reason: (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? "\(type(of: error))", at: clock())
            return .failed
        }
    }

    /// work_tick 의 `meta` 조각 반영 — refreshTeamMeta(WorkTimerStoreAuth)와 같은 규약: != 가드, 목표는
    /// 발사 전 세대와 같을 때만(스냅백 방지), 정상 0행(무소속)은 여기서 처리하지 않는다. 참여코드는 `invite_code`
    /// 조각이 있을 때만 반영한다(0행 = nil 확정, 조각 자체가 없으면 기존 값 유지 — loadMyInviteCode 와 같다).
    func applyTeamMeta(_ meta: WorkTickResponse.Meta, goalWriteGeneration: Int) {
        guard let row = meta.memberships?.first else { return }
        let membership = service.membership(from: row)
        if currentTeamID != membership.teamID { currentTeamID = membership.teamID }
        if teamName != membership.teamName { teamName = membership.teamName }
        if teamGoalWriteGeneration == goalWriteGeneration {
            let newGoal = membership.goalHours * 3600
            if teamGoalSeconds != newGoal { teamGoalSeconds = newGoal }
            reconcileInsightsGoal()
        }
        if teamRole != membership.role { teamRole = membership.role }
        if let codes = meta.inviteCode {
            let code = codes.first?.inviteCode
            if myTeamInviteCode != code { myTeamInviteCode = code }
        }
    }

    /// 설정 창 한 줄(진단 전용 — syncMessage 에 폴백 사유를 싣지 않는다).
    var workTickDiagnosticsLine: String {
        service.workTickGate.diagnosticsLine(now: clock())
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
            // ★ `.milestone` 이 아니라 `.goalAchieved` 다. 실사용 신고("주간 목표 달성이 1시간 근무와
            //   똑같아 보인다")의 원인이 정확히 이 한 줄이었다 — 같은 폴짝, 같은 색종이, 말풍선 없음.
            //   **onRewardTrigger 가 아니라 기존 채널을 그대로 탄다**: 이 감지는 근무 여부와 무관한
            //   폴링에서 도는데, 비근무·숨김 사용자가 팀원의 달성 때문에 8초 팝업을 맞으면 안 된다.
            //   보상 채널(shouldBeVisible 우회)은 **내 재화가 실제로 늘었을 때**만 쓴다.
            onReactionTrigger?(.goalAchieved)
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

    /// **팝오버가 열려 있고** 리그 페이지가 노출 중일 때만 순위를 갱신한다(30초 refresh 루프에서 호출).
    /// isLeaderboardVisible 은 팝오버를 닫아도 내려가지 않는다('마지막으로 본 패널' 복원용). 이 플래그만 보면
    /// 닫힌 팝오버가 리그 RPC 를 30초마다 두드린다(v0.2.38 Q7 계측). 다시 열리는 순간의 1회 갱신은
    /// setMenuPresented(true) 의 loadLeaderboard() 가 맡는다. 목표 변경(updateTeamGoal)의 호출은 열린 팝오버 안이다.
    func refreshLeaderboardIfVisible() async {
        guard isMenuPresented, isLeaderboardVisible else { return }
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

    /// **팝오버가 열려 있고** 토큰 보드 페이지가 노출 중일 때만 보드를 갱신한다(30초 refresh 루프에서 호출).
    /// 가드의 근거는 refreshLeaderboardIfVisible 과 같다(Q7). 재오픈 1회 갱신은 setMenuPresented 의 loadTokenBoard().
    func refreshTokenBoardIfVisible() async {
        guard isMenuPresented, isTokenBoardVisible else { return }
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
    ///
    /// v0.2.41: 업로드 전에 Codex 계정 프로브를 간격(30분) 하에 돌린다. 게이트는 업로드와 같다(로그인 + 수집 허용) —
    /// 수집 거부자에게선 프로브(프로세스)도 돌지 않는다. 월 롤오버(들고 있는 값의 달 ≠ 이번 달, **nil 포함** — 달이 바뀌면
    /// TokenUsageStore 가 지난달 스냅샷을 복원하지 않아 nil 이 곧 롤오버의 실제 모양이다)면 force 로 당겨 돈다.
    /// 그 판정은 첫 스캔 전(앱 시작 직후·팝오버 첫 열림)에도 참이라 30초 틱마다 걸리는데, 스토어의 60초 하한
    /// (forcedRefreshFloor)이 프로세스 난사를 막는다 — 첫 스캔이 끝나면(수 초) usage 가 채워져 판정이 꺼진다.
    ///
    /// 프로브는 업로드보다 게이트가 하나 더 있다: **수집 설정이 서버에서 실제로 도착한 뒤**(tokenUsageCollectLoaded) 에만 돈다.
    /// 업로드는 설정 도착 전 기본값(수집)으로 한두 번 나가도 서버 트리거가 버리지만, 프로브는 이 맥에서 외부 프로세스
    /// (`codex app-server`)를 띄우는 일이라 서버가 막을 수 없다 — 거부자의 맥에서 로그인 직후 한 틱이라도 뜨면 프라이버시 규약
    /// 위반이다(리뷰 P2). 설정은 폴링 첫 유효 틱에서 오므로 프로브는 그만큼(수십 초) 늦을 뿐이다.
    /// tokenUsagePublicLoaded 가 아닌 이유(리뷰 2차 P2): 그것은 setTokenUsagePublic 이 GET **전에** 세우는 낙관 플래그라,
    /// 로그인 직후 공개 토글 한 번이 '설정 도착'으로 읽혀 거부자의 맥에서 프로세스가 떴다.
    func uploadTokenUsageIfNeeded(now: Date = Date()) async {
        let usage = tokenUsage.currentMonthUsage
        if session != nil, tokenUsageCollect, tokenUsageCollectLoaded {
            let rolledOver = usage?.month != TokenUsageIncrementalScanner.kstMonthString(now)
            await codexAccount.refreshIfDue(now: now, force: rolledOver)
        }
        await uploadTokenUsageIfNeeded(usage: usage, account: codexAccount.snapshot, accountStatus: codexAccount.lastStatus, now: now)
    }

    /// 변경 게이트 + 60초 스로틀. 마지막 업로드 값과 다르고 60초 지났을 때만 upsert 한다.
    /// nil/총합 0 은 올리지 않는다(보드는 행 없는 팀원을 0 으로 채우므로 빈 행을 만들 필요가 없다) — 단 **계정 월합이 있으면**
    /// 로컬 0 이어도 올린다(`.zst` 만 남은 채 설치한 사람의 Codex 몫은 계정 집계만이 안다; 서버 보드가 greatest 로 쓴다).
    /// 새 기기별 표에 올리고, 옛 표에는 '그 행을 깎지 않을 때만' 같은 값을 올린다(이유는 아래 주석 참조).
    /// 실패는 조용히 — lastUploadedUsage 를 성공 시에만 갱신해 다음 주기에 재시도된다.
    /// 예외로 '스키마 부재'만은 문구로 드러낸다(마이그레이션 미적용을 운영자가 알 방법이 그것뿐이다).
    func uploadTokenUsageIfNeeded(
        usage: TokenUsageMonthly?, account: CodexAccountUsage? = nil, accountStatus: CodexAccountProbeStatus? = nil, now: Date
    ) async {
        guard session != nil else { return }
        // 수집 끔이면 아예 보내지 않는다. 서버 트리거가 어차피 조용히 버리므로 결과는 같지만,
        // 그 사람 맥이 30초마다 헛왕복을 도는 것을 없앤다(설정이 서버에서 도착하기 전 기본값은 수집이라,
        // 로그인 직후 한두 번은 나갈 수 있다 — 그건 서버가 막는다).
        guard tokenUsageCollect else { return }
        guard let usage else { return }
        let accountMonth = account?.monthTotal(usage.month) ?? 0
        guard usage.total > 0 || accountMonth > 0 else { return }
        // 변경 게이트는 usage 와 계정 키 **둘 다** 본다 — usage 가 그대로여도 계정값(월합·누적·상태)이 바뀌면 올린다.
        let accountKey = Self.accountUploadKey(account: account, month: usage.month, status: accountStatus)
        let changed = usage != lastUploadedUsage || accountKey != lastUploadedAccountKey
        guard changed, now.timeIntervalSince(lastTokenUploadAt) >= 60 else { return }
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
                //    **그 읽기는 하루 1회다**(v0.2.38 M8). 이 GET 이 분당 1건씩 나가고 있었는데(계측), 지키려는 상대
                //    (아직 v0.2.10 인 다른 맥)는 브루 자동 갱신 뒤 사실상 없다. 오늘(KST) 이미 읽은 값이 장부에 있으면
                //    그 값과 비교하고, 옛 표에 실제로 쓴 뒤에는 장부를 내 값으로 올려 둔다(서버 행이 그 값이 됐으므로 —
                //    다음 비교가 "내 값이 줄었는데도 덮어쓰기"를 허용하지 않게).
                let mayWriteLegacy: Bool
                if let knownTotal = legacyTokenTotalKnownToday(userID: activeSession.userID, month: usage.month, now: now) {
                    mayWriteLegacy = knownTotal <= usage.total
                } else {
                    do {
                        let currentLegacyTotal = try await service.fetchLegacyTokenUsageTotal(
                            accessToken: activeSession.accessToken,
                            userID: activeSession.userID,
                            month: usage.month
                        )
                        recordLegacyTokenTotal(currentLegacyTotal ?? 0, userID: activeSession.userID, month: usage.month, now: now)
                        mayWriteLegacy = (currentLegacyTotal ?? 0) <= usage.total
                    } catch {
                        mayWriteLegacy = false
                    }
                }
                if mayWriteLegacy {
                    try await service.upsertLegacyTokenUsage(
                        accessToken: activeSession.accessToken,
                        userID: activeSession.userID,
                        usage: usage
                    )
                    recordLegacyTokenTotal(usage.total, userID: activeSession.userID, month: usage.month, now: now)
                }
                // 2) 새 원장은 (user_id, month, device_id) 라 기기 식별자를 함께 올린다 — 맥 2대가 서로를 덮어쓰지 않고
                //    서버 보드 RPC 가 user_id 로 묶어 합산한다(결함1).
                try await service.upsertTokenUsage(
                    accessToken: activeSession.accessToken,
                    userID: activeSession.userID,
                    usage: usage,
                    deviceID: deviceID,
                    account: account,
                    accountStatus: accountStatus,
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
            lastUploadedAccountKey = accountKey
            // 3) 일별 표(v0.2.41 토큰 잔디): 월간 upsert 가 **성공한 직후**, 같은 게이트(로그인·수집 허용·변경·60초) 아래에서
            //    바뀐 날만 올린다. 월간 성공 뒤에 두는 이유: 일별 표 마이그레이션이 아직 없는 서버(404)에서도 월간 업로드와
            //    그 변경 게이트(lastUploadedUsage)는 정상 완결되어 순위판 사용량이 멈추지 않는다 — 일별 실패는 독립이다.
            await uploadTokenUsageDailyIfNeeded(usage: usage, account: account, generation: generation)
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

    /// 일별 표 업로드(v0.2.41 토큰 잔디). **반드시 월간 upsert 가 성공한 직후에만** 부른다(uploadTokenUsageIfNeeded 의 3)) —
    /// 그래야 로그인·수집 허용·변경·60초 게이트를 그대로 물려받고, 요청 순서(월간 → 일별)가 서버 쪽 '월 표가 먼저 정확해진다'
    /// 규약과 일치한다. 수집 거부 가드는 여기서도 한 번 더 건다(게이트는 짝으로 있어야 한다 — 이 함수만 따로 불려도 새지 않게).
    ///
    /// 행 = 현재 월 범위의 (claudeDaily ∪ codexDaily ∪ 그 달 계정 버킷) 날짜 중 **마지막 성공 업로드와 값이 다른 날만**(처음엔 전부).
    /// 실패는 조용히(장부를 갱신하지 않아 다음 주기에 같은 날들이 재시도된다). 스키마 부재(마이그레이션 미적용)만은 월간 경로와
    /// 같은 문구로 드러낸다 — 운영자가 "DB 스키마 필요" 신호를 받을 유일한 길이다.
    func uploadTokenUsageDailyIfNeeded(usage: TokenUsageMonthly, account: CodexAccountUsage?, generation: Int) async {
        guard session != nil, tokenUsageCollect else { return }
        let current = TokenUsageDailyUpload.values(usage: usage, account: account)
        let changed = TokenUsageDailyUpload.changedDays(current: current, lastUploaded: lastUploadedDaily)
        guard !changed.isEmpty else { return }
        do {
            try await withSessionRetry { activeSession in
                try await service.upsertTokenUsageDaily(
                    accessToken: activeSession.accessToken,
                    rows: TokenUsageDailyUpload.rows(
                        userID: activeSession.userID, deviceID: deviceID, days: changed, values: current
                    )
                )
            }
            guard generation == sessionGeneration else { return }
            // 성공에만 장부를 통째로 갈아 끼운다 — 안 바뀐 날은 어차피 같은 값이고, 현재 범위에서 빠진 날(달이 바뀜)은 잊는다.
            lastUploadedDaily = current
        } catch {
            guard generation == sessionGeneration else { return }
            if (error as? SupabaseWorkServiceError) == .databaseSchemaMissing {
                let message = authMessage(for: error, fallback: "동기화 실패")
                if syncMessage != message { syncMessage = message }
            }
        }
    }

    /// 계정 집계의 변경 게이트 키 = 월합|누적|상태. 이 셋 중 하나라도 바뀌면 다른 키다. 스냅샷·상태가 둘 다 없으면 nil.
    /// 받은 시각(fetchedAt)은 **일부러 뺀다** — 넣으면 30분마다 프로브가 성공할 때마다 값이 그대로여도 업로드가 나간다
    /// (하루 48회 헛왕복). 서버의 codex_account_at 은 값이 바뀐 업로드의 시각으로 충분하고, 프로브 생존은 status 가 말한다.
    static func accountUploadKey(account: CodexAccountUsage?, month: String, status: CodexAccountProbeStatus?) -> String? {
        guard account != nil || status != nil else { return nil }
        let monthTotal = account.map { String($0.monthTotal(month)) } ?? "-"
        let lifetime = account?.lifetimeTokens.map(String.init) ?? "-"
        let statusRaw = status.map { String($0.rawValue) } ?? "-"
        return "\(monthTotal)|\(lifetime)|\(statusRaw)"
    }

    // MARK: - 팝오버 없이 도는 배경 스캔 (v0.2.39)

    /// 팝오버가 닫혀 있어도 **근무 중이면** 저빈도로 스캔 → 업로드 → 하트비트.
    ///
    /// 왜 필요한가: 토큰 사용량이 팝오버에 **이중으로** 묶여 있었다. 스캔은 CheckMenuView 의 `.task { runRefreshLoop() }`
    /// 에서만 킥되고(TokenUsageStore.init 은 스캔을 안 켠다), 업로드도 refresh 루프의 `isMenuPresented` 게이트 뒤였다.
    /// 그래서 메뉴바를 안 여는 사람은 Claude/Codex 를 아무리 써도 서버에 0 으로 남았다. 월이 바뀌면 더 나빴다 —
    /// 스냅샷 복원이 '복원값의 달 == 이번 달'에만 걸려 currentMonthUsage 가 nil 이 되고, 업로드의
    /// `guard let usage, usage.total > 0` 이 그 nil 을 걸러 **그 달 내내 한 건도** 안 올라갔다
    /// (실측: 활동 중인데 이번 달 행이 없는 사람 8명, 지난달 수십억 토큰을 쓴 헤비 유저 포함).
    ///
    /// 왜 '근무 중'인가: Claude/Codex 를 쓰는 시간대가 곧 근무 시간대이고, 쉬는 동안 1,600 파일 stat 순회를
    /// 돌리는 것은 v0.2.38 이 걷어낸 바로 그 비용이다. 팝오버가 닫힌 채 앱 시작부터 스캔이 도는 것을 막던
    /// 옛 `isMenuPresented` 게이트의 의도도 이 `startedAt != nil` 가드가 그대로 승계한다.
    func refreshTokenUsageInBackgroundIfDue(now: Date = Date()) async {
        guard session != nil else { return }
        // 수집 거부자에게선 스캔조차 돌리지 않는다 — 업로드가 서버에서 버려지는 것과 별개로,
        // 애초에 그 사람 맥에서 파일을 읽을 이유가 없다(uploadTokenUsageIfNeeded 와 같은 규약).
        guard tokenUsageCollect else { return }
        guard startedAt != nil else { return }
        // 롤오버 판정: 지금 들고 있는 값이 이번 달 것이 아니면(달이 막 바뀌었거나 이번 실행에서 한 번도 안 스캔했다)
        // 서버에 이 달 행이 아예 없다는 뜻이다. 그 창을 10분씩 열어 둘 이유가 없어 주기를 1분으로 줄인다.
        let rolledOver = tokenUsage.currentMonthUsage?.month != TokenUsageIncrementalScanner.kstMonthString(now)
        // ★ 롤오버여도 **60초 하한은 반드시 둔다.** 스캔이 끝난 뒤에도 이 판정이 참으로 남는 경로가 둘 있다:
        //   ⓐ **KST 월 경계 창**: 스캔이 잡은 달과 이 함수가 보는 now 의 달이 갈리는 순간(자정 전후).
        //   ⓑ **총합 0 인 달의 다음 실행**: 그 달 스냅샷이 디스크에 안 남아(영속은 총합 0 을 거른다)
        //      재시작 직후 currentMonthUsage 가 nil 인 채로 시작한다. 첫 스캔 전까지 계속 참이다.
        //   하한이 없으면 그동안 **매 30초 틱마다 전량 순회**가 돈다(= 이 함수가 아끼려던 비용을 정반대로 쓴다).
        //   ⚠️ "총합 0 이면 currentMonthUsage 가 안 채워진다"는 **틀린 근거다** — TokenUsageStore.apply 는
        //      무조건 대입하고, 0 게이트가 걸린 것은 디스크 영속뿐이다. 그 근거로 읽고 하한을 걷어내지 마라.
        let interval: TimeInterval = rolledOver ? 60 : 600
        guard now.timeIntervalSince(lastBackgroundTokenScanAt) >= interval else { return }
        // 스탬프를 **먼저** 찍는다. 아래 await(전량 순회 + 서버 왕복)를 기다리는 사이 다음 틱이 들어와도 이 스탬프에
        // 걸려 되돌아가므로 순회가 겹치지 않는다(uploadTokenUsageIfNeeded 의 lastTokenUploadAt 과 같은 관용구).
        lastBackgroundTokenScanAt = now
        // 롤오버면 3초 스로틀을 무시하고 반드시 한 번 돈다 — '지금 값이 없다'는 것 자체가 스캔의 이유다.
        if rolledOver {
            await tokenUsage.refreshNow()
        } else {
            await tokenUsage.refreshIfStale()
        }
        await uploadTokenUsageIfNeeded(now: now)
        await sendTokenScanHeartbeatIfNeeded(now: now)
    }

    /// 스캔이 돌았다는 **사실 자체**를 서버에 남긴다. 위 업로드가 게이트에서 되돌아가도(총합 0이거나 값이 그대로여도)
    /// 보낸다 — 그게 이 경로의 존재 이유다. 업로드가 침묵하면 서버에서는 "안 쓴 사람"과 "스캐너가 죽은 사람"이
    /// 똑같이 '행 없음'으로 보이고, 그 둘을 가를 신호가 이것 하나뿐이다(files = 이번 스캔이 stat 한 파일 수,
    /// scannedAt = 그 스캔이 끝난 시각. files 0 은 "돌았는데 파일이 없었다", 하트비트 부재는 "안 돌았다").
    ///
    /// 업로드 게이트(총합 0·60초 스로틀·변경 게이트·옛 표 축소 금지)에는 손대지 않는다 — 이 하트비트는 그 옆에
    /// 따로 붙는 별개 경로다. 같은 스캔을 두 번 보고하지 않게 lastScanAt 변경 게이트를 두고, 도장은 **성공에만**
    /// 찍어 실패가 다음 주기에 그대로 재시도되게 한다. 실패는 조용히 삼킨다(진단 신호일 뿐 기능이 아니라,
    /// 문구를 세워 봐야 사용자가 할 수 있는 일이 없다).
    func sendTokenScanHeartbeatIfNeeded(now: Date = Date()) async {
        guard session != nil else { return }
        // 수집 거부자의 스캔 사실도 서버에 남기지 않는다(위 배경 스캔이 이미 막지만, 이 함수만 따로 불려도
        // 프라이버시 규약이 깨지지 않게 여기서도 건다 — 게이트는 짝으로 있어야 한다).
        guard tokenUsageCollect else { return }
        // 이번 실행에서 스캔이 한 번도 안 끝났으면 보고할 사실이 없다(nil = 스캐너가 아직 안 돌았다).
        guard let scannedAt = tokenUsage.lastScanAt else { return }
        guard scannedAt != lastTokenScanHeartbeatAt else { return }
        let files = tokenUsage.lastScanFileCount
        let month = TokenUsageIncrementalScanner.kstMonthString(now)
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.sendTokenScanHeartbeat(
                    accessToken: activeSession.accessToken,
                    userID: activeSession.userID,
                    month: month,
                    // 새 원장(user_id, month, device_id)이 쓰는 **그 기기 식별자 그대로**다. 여기서 따로 만들면
                    // 하트비트가 가리키는 기기와 사용량 행의 기기가 어긋나, 맥 2대인 사람에게서 "스캔은 도는데
                    // 값이 없는 기기"가 유령으로 하나 더 보인다.
                    deviceID: deviceID,
                    files: files,
                    scannedAt: scannedAt
                )
            }
            guard generation == sessionGeneration else { return }
            lastTokenScanHeartbeatAt = scannedAt
        } catch {
            // 조용히 삼킨다 — 도장을 성공에만 찍으므로 다음 주기가 같은 스캔을 그대로 다시 보고한다.
        }
    }

    // MARK: - 옛 표 현재값 하루 1회 장부 (M8)

    /// 옛 표(token_usage_monthly) 현재값 GET 의 하루 1회 장부 키(UserDefaults). 값은
    /// "<userID>|<month>|<KST 날짜>|<total>" — 계정·달·날짜 중 하나라도 다르면 없는 것으로 본다.
    /// 날짜 산식은 codexDiagnosticsStamp 와 같은 TokenUsageIncrementalScanner.dayBounds(now:).date 다
    /// (이 저장소는 KST 경계 산식이 흩어지면 어긋난 이력이 있어, 그 함수 하나만 쓴다).
    static let legacyTokenTotalLedgerKey = "check.tokenUpload.legacyTotalLedger"

    /// 오늘(KST) 이미 읽어 둔(또는 내가 쓴) 옛 표 총량. nil 이면 오늘 아직 안 읽었다 = GET 한 번 나간다.
    func legacyTokenTotalKnownToday(userID: String, month: String, now: Date) -> Int? {
        guard let raw = defaults.string(forKey: Self.legacyTokenTotalLedgerKey) else { return nil }
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == userID,
              parts[1] == month,
              parts[2] == TokenUsageIncrementalScanner.dayBounds(now: now).date,
              let total = Int(parts[3])
        else { return nil }
        return total
    }

    /// 장부에 오늘치 옛 표 총량을 적는다(GET 성공 직후와 옛 표 쓰기 직후, 두 곳에서만 부른다).
    func recordLegacyTokenTotal(_ total: Int, userID: String, month: String, now: Date) {
        let day = TokenUsageIncrementalScanner.dayBounds(now: now).date
        defaults.set("\(userID)|\(month)|\(day)|\(total)", forKey: Self.legacyTokenTotalLedgerKey)
    }

    // MARK: - 팀 상태 신선도 (팝오버 재오픈 스로틀, Q10)

    /// 팝오버 재오픈(activateStoredSession fast path)에서 팀 상태 4 GET 을 건너뛰는 창(초).
    /// 30초 폴링이 도는 동안 사용자가 이 시간 안에 다시 열면 첫 프레임은 캐시(teamMembers)로 그린다.
    static let teamStatusReopenThrottleSeconds: TimeInterval = 15

    /// 팀 상태가 재오픈 스로틀 창 안에 있는가(= fast path 가 4 GET 을 건너뛰어도 되는가).
    /// 근거 스탬프 `lastTeamStatusAt` 은 WorkTimerStore.swift 의 저장 프로퍼티다(δ 가 두었던 약참조 측면 표는 ε 가 이관).
    func teamStatusIsFresh(now: Date) -> Bool {
        now.timeIntervalSince(lastTeamStatusAt) < Self.teamStatusReopenThrottleSeconds
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
        // 프로덕션 스캐너와 같은 Codex 홈(로그인 셸 CODEX_HOME 캐시)을 본다 — 루트가 다르면 항등식이 깨진다.
        let codexHome = CodexAccountUsageProbe.cachedCodexHome()
        return await Task.detached(priority: .utility) {
            CodexUsageDiagnosticsScanner.compute(homeDirectory: home, codexHome: codexHome, month: month, appBuild: build)
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
        // ★ **입력 관측은 소유 여부보다 앞이다.** 사람이 이 맥에서 타이핑하고 있다는 사실은 어느 맥이 세션을
        //   열었든 같은 무게를 갖는다 — 이 한 줄이 없으면 "아이맥에서 시작 → 노트북으로 옮겨 작업"이
        //   결정론적으로 매일 오마감된다(소유 맥의 last_input_at 은 얼어붙고, 노트북은 아무 말도 하지 않는다).
        //   새 타이머는 만들지 않는다: 이 함수가 이미 30초마다 돌고 있다.
        let observedInput = advanceMeaningfulInput(now: clock())
        guard startedAt != nil, session != nil, let teamID = currentTeamID else { return }
        // 흡수 세션이어도 **입력만은** 자기 기기 행에 남긴다. session_id/last_seen_at 은 절대 건드리지 않으므로
        // (SupabaseWorkService.reportDeviceInput) 아래 가드가 지키는 계약 — "흡수 맥은 그 세션의 생존신호를
        // 대신 보내지 않는다" — 은 한 글자도 약해지지 않는다. 그 계약이 깨지면 '아무도 못 닫는 세션'이 된다.
        guard !adoptedRemoteSession else {
            await reportDeviceInputIfPossible(teamID: teamID, lastInputAt: observedInput)
            return
        }
        guard let sessionID = currentSessionID else { return }
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.heartbeat(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    sessionID: sessionID,
                    lastInputAt: awayServerSupported ? observedInput : nil
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
                    openedSession: openedSession,
                    lastInputAt: awayServerSupported ? observedInput : nil
                )
            }
        } catch {
            // 주장 기록 실패는 조용히 무시한다. 못 남기면 상대 맥이 나를 '판정 불가'로 보고 백스톱(7분)으로
            // 되돌아갈 뿐이다 — v0.2.14 와 같은 수준이지 더 나빠지지 않는다.
        }
    }

    /// 비소유 맥(흡수 상태)이 **자기 기기 행에 last_input_at 만** 올린다. 실패는 조용히 무시한다 —
    /// 이 값이 없으면 away 자격이 서지 않아 그 사용자가 면제될 뿐이고, 그건 안전한 쪽이다.
    private func reportDeviceInputIfPossible(teamID: String, lastInputAt: Date?) async {
        guard awayServerSupported, let lastInputAt else { return }
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.reportDeviceInput(
                    accessToken: activeSession.accessToken,
                    teamID: teamID,
                    userID: activeSession.userID,
                    deviceID: deviceID,
                    lastInputAt: lastInputAt
                )
            }
        } catch {
            guard generation == sessionGeneration else { return }
        }
    }

    // MARK: - 자리 비움 정책·복원 (v0.2.35 / docs/away-close.md)

    /// away_sync() 를 불러 정책·판정 재료·복원 대상을 받아 온다. 근무 중에는 매 폴링, 비근무면 스로틀.
    ///
    /// **실패는 전부 "모른다"로 접는다**: 정책을 비우면 evaluateAwaySession 이 그대로 통과하므로 마감이 멈춘다.
    /// 이 방향이 유일하게 안전한 실패다 — 반대(마지막으로 본 임계를 계속 쓰기)는 서버가 임계를 올렸는데도
    /// 옛 값으로 남의 근무를 계속 끊는 상태가 되고, 그걸 되돌릴 수단이 클라 배포뿐이다.
    func refreshAwayStateIfNeeded(now: Date? = nil) async {
        let now = now ?? clock()
        guard let session else {
            // 로그아웃/세션 없음 — 남의 계정 화면에 배너가 남지 않게 통째로 비운다.
            clearAwayState()
            return
        }
        if startedAt == nil, now.timeIntervalSince(lastAwaySyncAt) < Self.awaySyncIdleThrottleSeconds {
            return
        }
        lastAwaySyncAt = now
        let generation = sessionGeneration
        let ownerUserID = session.userID
        do {
            let sync = try await withSessionRetry { activeSession in
                try await service.awaySync(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration, self.session?.userID == ownerUserID else { return }
            applyAwaySync(sync, ownerUserID: ownerUserID)
        } catch is AwaySyncUnavailable {
            // 마이그레이션이 아직 안 나간 서버. 정책을 비워 마감을 멈추고, 새 컬럼 전송도 함께 끈다
            // (그 서버에 last_input_at 을 보내면 하트비트가 400 이 되어 세션이 방치로 마감된다).
            guard generation == sessionGeneration else { return }
            awayServerSupported = false
            awayPolicy = nil
            awayOpenSession = nil
        } catch {
            // 네트워크 실패·취소. 서버 미배포와 달리 스키마 판단은 건드리지 않고 판정 재료만 무효화한다.
            guard generation == sessionGeneration else { return }
            awayPolicy = nil
            awayOpenSession = nil
        }
    }

    /// away_sync 응답을 스토어 상태로 반영한다(요청/응답과 분리해 테스트가 그대로 부를 수 있게 둔다).
    func applyAwaySync(_ sync: AwaySync, ownerUserID: String) {
        // 응답이 왔다 = 이 서버는 자리 비움 스키마를 갖고 있다. 상태가 invalid(비로그인)여도 참이다.
        awayServerSupported = true
        awayStateOwnerUserID = ownerUserID
        awayPolicy = sync.policy
        awayOpenSession = sync.openSession
        if awayRestorable != sync.restorable { awayRestorable = sync.restorable }
        // 복원 대상이 사라졌으면(복원됨·만료·다른 맥이 처리) 제안도 함께 내린다.
        if sync.restorable == nil, awayRestorePromptPending { awayRestorePromptPending = false }
    }

    /// 복원 버튼/말풍선의 액션. **원자 RPC 한 번**으로만 간다(2회 왕복 흉내 금지 — 중간에 죽으면
    /// 열린 세션이 0개나 2개가 된다). 기존 canUndoAutoClose/performUndoAutoClose(스캐빈저 10분 되돌리기)는
    /// 그대로 살아 있고 이 경로와 섞이지 않는다 — 그쪽 가드는 전부 실제 사고에서 나왔다.
    @discardableResult
    func restoreAwaySession() -> Task<Void, Never>? {
        guard !isRestoringAwaySession, restorableAwaySession != nil else { return nil }
        return Task { @MainActor in await performRestoreAwaySession() }
    }

    func performRestoreAwaySession() async {
        guard !isRestoringAwaySession, let restorable = restorableAwaySession else { return }
        guard let session else { return }
        isRestoringAwaySession = true
        defer { isRestoringAwaySession = false }
        let generation = sessionGeneration
        // 복원 왕복 전의 근무 상태 write 세대. 왕복 중 사용자가 [근무 시작]/[근무 종료]를 눌렀다면
        // 그 조작이 최신이므로 로컬 반영을 통째로 건너뛴다(옛 세션으로 현재 세션을 덮어쓰기 금지).
        let writeGeneration = workStateWriteGeneration
        let outcome: AwayRestoreOutcome
        do {
            outcome = try await withSessionRetry { activeSession in
                try await service.restoreAutoClosedSession(
                    accessToken: activeSession.accessToken,
                    sessionID: restorable.sessionID
                )
            }
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "재개 실패")
            return
        }
        guard generation == sessionGeneration, self.session?.userID == session.userID else { return }
        switch outcome {
        case .restored(let sessionID, let serverStartedAt):
            guard writeGeneration == workStateWriteGeneration else {
                awayRestorePromptPending = false
                return
            }
            applyRestoredAwaySession(
                sessionID: sessionID,
                startedAt: serverStartedAt ?? restorable.startedAt,
                closedEndedAt: restorable.endedAt
            )
        case .expired:
            awayRestorable = nil
            awayRestorePromptPending = false
            syncMessage = "복원 시간이 지났어요"
        case .limitReached(let used, let limit):
            awayRestorable = nil
            awayRestorePromptPending = false
            syncMessage = "오늘 복원 횟수를 다 썼어요(\(used)/\(limit))"
        case .notRestorable:
            // 내 것이 아니거나 이미 복원됐다 — 배너를 내린다(재시도해도 같은 답이 온다).
            awayRestorable = nil
            awayRestorePromptPending = false
        case .failed:
            // conflict/invalid/미지 status. **재시도하지 않는다**(서버가 정상 경로에서 주지 않는 답이다).
            awayRestorePromptPending = false
            syncMessage = "재개 실패"
        }
    }

    /// 복원 성공을 로컬 상태에 반영한다. 서버가 이미 한 일(S2 삭제·S1 재개·상태행 갱신·카운터)은
    /// **중복으로 하지 않는다** — 여기서 하는 것은 로컬 미러링뿐이다.
    func applyRestoredAwaySession(sessionID: String, startedAt restoredStart: Date?, closedEndedAt: Date?) {
        guard let restoredStart, let canonical = Self.canonicalSessionID(sessionID) else { return }
        let now = clock()
        // 복원도 내가 확정한 근무 상태 변경이다 — in-flight 였던 낡은 팀 응답이 이 재개를 되돌리지 못하게.
        workStateWriteGeneration &+= 1
        // 마감이 누적에 더해 둔 그 세션의 '오늘 몫'을 도로 뺀다. 안 빼면 이 세션이 다시 진행 세션이 되어
        // 같은 구간을 두 번 세고, 메뉴바·큰 타이머·오버레이가 일제히 두 배로 뛴다(다음 폴링까지).
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        if accumulatedDayStart >= dayStart, let closedEndedAt {
            let contributed = max(0, Int(closedEndedAt.timeIntervalSince(max(restoredStart, dayStart))))
            accumulatedSeconds = max(0, accumulatedSeconds - contributed)
        }
        stampDisplayClocks(now)
        startedAt = restoredStart
        currentSessionID = canonical
        // **강한 소유**: 이 맥이 복원 RPC 를 직접 보내 성공했고, 서버는 그 트랜잭션에서 다른 열린 세션을
        // 전부 지운 뒤 active_session_id 를 이 세션으로 세웠다(= 지금 이 세션을 돌보는 맥은 이 맥이다).
        // performUndoAutoClose 가 강도를 물려받는 것과 근거가 다르다: 저쪽은 '남의 세션을 주워 닫았다가
        // 되돌리는' 경로가 실재해서 승격이 위험하지만, 이 RPC 는 auth.uid() 소유 세션만 되살린다.
        claimSessionOwnership(canonical, strength: .strong)
        // 복원 시각이 아니라 **복원된 세션의 시작 시각**이다. 복원 시각으로 세우면 09:00 시작 → 13:00 마감
        // → 15:00 복원인 사람의 12시간 프롬프트가 다음날 03:00 으로 밀려 총 18시간 세션이 되고,
        // 12시간 안전장치가 복원 경로에서 통째로 무력화된다(performUndoAutoClose 의 규약 그대로).
        longSessionAnchor = restoredStart
        clearLongSessionPrompt()
        sleepBeganAt = nil
        // 버튼을 누른 것 자체가 "사람이 자리에 있다"는 증거다. 서버도 같은 트랜잭션에서 last_input_at 을
        // now 로 민다 — 여기서 로컬을 안 밀면 다음 틱이 옛 입력 시각으로 방금 살린 세션을 다시 마감한다.
        lastMeaningfulInputAt = now
        awayOpenSession = nil
        awayRestorable = nil
        awayRestorePromptPending = false
        // 다음 폴링이 새 열린 세션의 판정 재료를 받아 오게 스로틀을 푼다.
        lastAwaySyncAt = .distantPast
        snapshot = WorkStatusSnapshot(
            status: .working,
            elapsedSeconds: max(0, Int(now.timeIntervalSince(restoredStart)))
        )
        startTimer()
        refreshMenuBarTitle()
        // 근무가 다시 섰으므로 유예형 배너(되돌리기)의 성립 조건도 뒤집힌다.
        refreshTimedBanner(now: now)
        syncMessage = "근무 재개됨"
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
            // 표시 시계는 맞춰 두되 계산은 주입 시계로 한다 — 팝오버 시계는 닫힌 동안 얼어 있다(M1).
            let now = clock()
            stampDisplayClocks(now)
            snapshot = WorkStatusSnapshot(
                status: .working,
                elapsedSeconds: max(0, Int(now.timeIntervalSince(restoredStart)))
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

    func syncCurrentStatus(
        durationSeconds: Int? = nil,
        sessionStartedAt: Date? = nil,
        endedAt: Date? = nil,
        autoCloseReason: AutoCloseReason? = nil
    ) {
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
                // 폴백도 인자 시각 기준이다(팝오버 시계가 아니라 — 닫힌 팝오버에서 그 시계는 얼어 있다, M1).
                operation: .stop(durationSeconds: durationSeconds ?? todayDuration(at: endedAt ?? clock())),
                sessionID: currentSessionID ?? fallbackSessionID,
                sessionStartedAt: sessionStartedAt,
                endedAt: endedAt,
                ownerUserID: ownerUserID,
                autoCloseReason: autoCloseReason
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
            // 깨움 결합 게이트가 서 있으면(v0.2.38 M7) 결합(또는 상한 10초)까지 기다린다 — 뚜껑을 연 직후의 잠자기 정정
            // PATCH 가 Wi-Fi 가 붙기 전에 나가 실패 → "대기" 라벨 → 재시도로 도는 헛왕복을 없앤다. 게이트는 이 큐를
            // 기다리지 않으므로(루프를 내렸다 되살릴 뿐) 순환 대기는 없고, 큐 항목 자체는 영속이라 잃지 않는다.
            await self?.awaitWakeGate()
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
                    fallbackSessionID: item.sessionID,
                    // 사유는 큐 항목이 나른다. 서버가 이 세션을 먼저 닫아 뒀다면(뚜껑 닫고 나간 사람 —
                    // 스캐빈저가 10분 뒤 'abandoned' 로 마감한다) stopWork 가 그 자리에서 사유를 정정해
                    // 복원 대상으로 되돌린다. 정정이 빠지면 오늘 가장 큰 억울함이 그대로 남는다.
                    autoClosedReason: item.autoCloseReason
                )
            }
        }
    }

    /// 내 소유 세션이 서버에서 abandoned 로 닫혀 강하할 때의 사용자 통보 한 줄(v0.2.36 W3).
    /// 노출 수명은 refreshTeamStatus 의 정규화 가드가 준다(세운 그 주기는 살고, 다음 정상 폴링이 덮는다).
    static let remoteAbandonedCloseNotice = "연결이 끊겨 근무가 자동 종료됐어요"

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

        // [v0.2.36 W2 — 잠자기 정정 수용 지점] 서버 스캐빈저가 abandoned(복원 불가)로 먼저 닫아 둔
        // **이 맥 소유** 세션을 폴링이 발견한 순간. didWake 가 아니라 여기가 발화점이어야 하는 이유:
        //  (1) 깨어난 직후엔 폴링 루프의 Task.sleep 이 즉시 재개돼 이 함수가 didWake 보다 먼저 로컬을
        //      내리고, 그 뒤의 handleWake 는 startedAt 가드에서 조기 반환한다(경쟁의 결정적 패자),
        //  (2) 다크웨이크는 didWake 자체가 없다,
        //  (3) 잠자는 사이 앱이 죽으면(업그레이드·크래시) 메모리 상태가 통째로 없다.
        // 세 경우 모두 handleSleep 이 영속해 둔 마커(PendingSleepClose)가 유일한 관측이고, 이 지점은
        // 세 경우 전부가 반드시 지난다. 정정 stop(reason=sleep)이 드레인되면 서버 stopWork 의 0행
        // 갈래가 correctAutoClose 로 사유를 sleep 으로 고쳐 기존 복원 인프라(배너 + 넛지 복원 제안)가
        // 그대로 이어받는다.
        // ★ 아래 서버 today 덮어쓰기보다 **앞**이어야 한다(이중 가산 금지). (a) 갈래의 autoStop 관문은
        //   회계를 스스로 하는데(accumulatedSeconds += 정정 몫), 서버 today 는 이 세션의 abandoned 마감
        //   몫을 이미 포함하므로 먼저 덮으면 같은 구간이 두 번 더해진다. "정정 전 로컬 누적 + 정정 몫"은
        //   handleWake 정상 경로와 같은 값이고, 정정이 서버에 닿은 뒤의 폴링이 서버 값으로 수렴시킨다.
        if ownMember.status == .offWork, let marker = pendingSleepCloseMarker() {
            // 마감 시각 산식은 handleWake 와 동일 계약: min 은 절전 대기 시간만큼의 덤 제거,
            // 바깥 max 는 시작 시각 클램프(0초 세션 = 근무 전체 소실 방지).
            let sleepEndedAt = max(
                marker.sessionStartedAt,
                min(marker.sleepBeganAt, marker.lastInputAt ?? marker.sleepBeganAt)
            )
            if startedAt != nil, !adoptedRemoteSession,
               Self.canonicalSessionID(currentSessionID) == marker.sessionID {
                // (a) 경쟁 갈래: 로컬은 아직 근무중인데 서버는 이미 닫았다. autoStop 관문
                //     (closeOwnedSessionLocally)이 세대 증가·회계·큐잉(reason=sleep)·소유권 해제·
                //     teardown·라벨/배너 갱신·마커 소거까지 전부 수행하므로 여기서는 그중 무엇도
                //     중복하지 않는다(이중 가산·이중 teardown 금지의 근거). 마커 소거를 여기서도
                //     명시하는 이유: 이 소거가 이 갈래의 "정정은 1회"를 지키는 계약이다.
                clearPendingSleepClose()
                closeOwnedSessionLocally(
                    endedAt: sleepEndedAt,
                    message: "잠자기로 자동 근무종료됨",
                    reason: .sleep
                )
                // 서버가 이미 닫은 id 다 — (.offWork,.some) 가지의 기존 계약 그대로 잔존 세션 ID 를
                // 끊는다(닫힌 id 가 재흡수/폴백 POST 로 서버에 되돌아가는 사고 방지). autoStop **뒤**인
                // 이유: 큐 항목이 이 값을 실어야 정정 PATCH 가 그 세션을 명중한다.
                currentSessionID = nil
                // 이후의 강하 로직(startedAt=nil·소유 해제·스냅샷)은 autoStop 이 방금 한 일과 겹친다
                // (이중 teardown) — 여기서 끝낸다. 꼬리의 백스톱/반납 관측도 소유 해제로 전부 no-op 이다.
                return
            }
            if startedAt == nil, isOwnedByThisMac(marker.sessionID) {
                // (b) 재실행 갈래: 잠자는 사이 앱이 죽어 didWake 도 로컬 근무 상태도 없다. 영속 마커 +
                //     영속 소유 ID 가 "그 세션은 잠자기로 닫혔어야 했다"의 증거 전부다. autoStop 은
                //     부를 수 없고(startedAt 가드) 회계도 아래 서버 today 반영이 이미 옳으므로,
                //     정정 stop 항목만 큐에 실어 기존 드레인 → 0행 → correctAutoClose 경로를 태운다.
                clearPendingSleepClose()
                pendingItems.append(PendingWorkItem(
                    id: UUID(),
                    operation: .stop(
                        durationSeconds: max(0, Int(sleepEndedAt.timeIntervalSince(marker.sessionStartedAt)))
                    ),
                    sessionID: marker.sessionID,
                    sessionStartedAt: marker.sessionStartedAt,
                    endedAt: sleepEndedAt,
                    ownerUserID: session.userID,
                    autoCloseReason: .sleep
                ))
                // 서버가 닫은 세션의 소유 표식은 증거 수명을 다했다((.offWork,.some) 가지와 같은 규약 —
                // 남기면 다음 실행이 죽은 ID 를 '내 세션'으로 되찾으려 든다).
                releaseSessionOwnership()
                enqueueSync()
                // 강하시킬 로컬 근무가 없으므로 아래 정상 흐름(서버 today 반영 등)은 그대로 계속한다.
            }
        }

        accumulatedSeconds = ownMember.todayDurationSeconds
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: clock())

        switch (ownMember.status, startedAt) {
        case (.working, nil):
            adoptRemoteSession(ownMember)
        case (.offWork, .some(let closedSessionStart)):
            // [v0.2.36 W3 — 침묵 제거] 이 맥 소유 세션이 서버에서 닫혀 내려가는데(잠자기 마커도 없다 —
            // 깨어있는 채 네트워크 단절 → 10분 뒤 abandoned 마감이 대표) 지금까지는 통보·배너·정정이
            // 전부 0이었다. 피해자는 아무것도 모른 채 재시작 지연을 겪는다. abandoned 는 복원 대상이
            // 아니므로(restorableReasons=['away','sleep']) 기존 10분 되돌리기 배너가 유일한 구제다.
            //
            // 신호 공백 게이트(> 스캐빈저 임계 10분)를 거는 이유: 신선한 신호의 (.offWork,.some) 강하는
            // "다른 맥에서 사용자가 방금 직접 누른 종료"가 대표라 사고가 아니고(통보하면 헛경보),
            // 서버 away 백스톱 마감(하트비트는 살아 신호가 신선하다)은 복원 배너가 따로 알린다.
            // seen 미상은 기존대로 침묵한다(모를 때 헛경보를 만들지 않는다).
            if !adoptedRemoteSession,
               let seen = ownMember.lastSeenAt ?? ownMember.updatedAt,
               clock().timeIntervalSince(seen) > Self.abandonedSessionThresholdSeconds {
                // 되돌리기 대상 등록은 아래 releaseSessionOwnership() 이 증거(소유 강도)를 지우기
                // **전**이어야 한다 — autoCloseAbandonedOwnSessionIfNeeded 의 lastAutoClosedClaimStrength
                // 규약 그대로다(강도 상속 없이는 되돌리기가 강한 소유자를 둘로 만든다).
                lastAutoClosedSessionID = Self.canonicalSessionID(currentSessionID)
                lastAutoClosedStartedAt = closedSessionStart
                lastAutoClosedClaimStrength = isOwnedByThisMac(currentSessionID)
                    ? ownedSessionClaimStrength
                    : .weak
                // 되돌리면 이 세션이 다시 진행 세션이 되므로, 위에서 서버 today 로 덮은 누적에서 도로
                // 빼야 할 이 세션 몫. 서버의 마감 시각은 응답에 없어 마지막 신호(seen)로 근사한다 —
                // 스캐빈저가 정확히 그 시각(coalesce(last_seen_at, updated_at))으로 마감하기 때문이다.
                lastAutoClosedSeconds = max(
                    0,
                    Int(seen.timeIntervalSince(max(closedSessionStart, TeamWeeklyGoal.koreanDayStart(for: clock()))))
                )
                lastAutoClosedAt = clock()
                // performUndoAutoClose 가 이 마감을 실제로 감당하는지는 코드로 확인했다:
                // reopenSession 은 id 필터 PATCH 로 ended_at/duration 을 null 로 되돌리고 상태행을
                // working 으로 세우므로, 누가 닫았든(클라 stopWork/서버 스캐빈저) 닫힌 행의 모양이 같아
                // 동일하게 동작한다. 문구는 refreshTeamStatus 의 정규화 가드가 이 주기 동안 지켜 준다.
                syncMessage = Self.remoteAbandonedCloseNotice
            }
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
        // 표시 시계는 맞춰 두되 계산은 주입 시계로 한다 — 팝오버 시계는 닫힌 동안 얼어 있다(M1).
        let now = clock()
        let restoredStart = ownMember.currentSessionStartedAt ?? now
        stampDisplayClocks(now)
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
            elapsedSeconds: max(0, Int(now.timeIntervalSince(restoredStart)))
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

// MARK: - 일별 토큰 업로드의 순수 계산 (v0.2.41 토큰 잔디)

/// 일별 업로드의 변경 게이트 단위: 하루치 (claude, codex, codexAccount). 값이 하나라도 다르면 '바뀐 날'이다.
/// codexAccount 가 nil 이면 그 날짜의 계정 버킷이 없다는 뜻이고 본문에서 키가 빠진다(TokenUsageDailyUpsertRow 주석).
struct TokenUsageDailyValue: Equatable, Sendable {
    var claude: Int
    var codex: Int
    var codexAccount: Int?
}

/// 월간 사용량 + 계정 스냅샷에서 일별 표에 올릴 값을 고르는 순수 규칙(스토어·테스트 공용).
enum TokenUsageDailyUpload {
    /// 현재 월 범위의 날짜별 값. 키 = usage.month 접두어인 (claudeDaily ∪ codexDaily ∪ 계정 버킷) 날짜.
    /// - 로컬 맵에는 보관 하한(월 시작 − 48시간) 때문에 지난 달 꼬리 이틀이 남아 있을 수 있다 — 그 날들은 이미 그 달에 올렸고
    ///   지금은 부분값이라 **보내지 않는다**(월 접두어 필터). 보내면 서버의 온전한 값을 부분값으로 덮는다.
    /// - 계정 버킷 날짜도 키에 넣는다(스펙의 claudeDaily ∪ codexDaily 보다 넓다): `.zst` 만 남은 채 설치한 사람의 Codex 사용은
    ///   로컬 맵에 없고 계정 버킷에만 있다 — 월간 경로가 "로컬 0 + 계정 > 0" 을 올리는 것과 같은 이유로 일별도 그 날을 남겨야
    ///   다른 맥과 서버 잔디에 그 날이 보인다. 셋 다 0/nil 인 날은 말할 것이 없어 뺀다.
    static func values(usage: TokenUsageMonthly, account: CodexAccountUsage?) -> [String: TokenUsageDailyValue] {
        let prefix = usage.month + "-"
        let buckets = account?.buckets ?? [:]
        var result: [String: TokenUsageDailyValue] = [:]
        for day in Set(usage.claudeDaily.keys).union(usage.codexDaily.keys).union(buckets.keys) where day.hasPrefix(prefix) {
            let value = TokenUsageDailyValue(
                claude: max(0, usage.claudeDaily[day] ?? 0),
                codex: max(0, usage.codexDaily[day] ?? 0),
                codexAccount: buckets[day].map { max(0, $0) }
            )
            guard value.claude > 0 || value.codex > 0 || value.codexAccount != nil else { continue }
            result[day] = value
        }
        return result
    }

    /// 마지막 성공 업로드와 값이 다른 날만(날짜 오름차순 — 요청 본문이 결정적이라 테스트·로그가 읽기 쉽다). 장부가 비어 있으면 전부.
    static func changedDays(current: [String: TokenUsageDailyValue], lastUploaded: [String: TokenUsageDailyValue]) -> [String] {
        current.filter { day, value in lastUploaded[day] != value }.keys.sorted()
    }

    /// 요청 행(days 순서 그대로). values 에 없는 날은 건너뛴다(형이 어긋나도 크래시 없음).
    static func rows(userID: String, deviceID: String, days: [String], values: [String: TokenUsageDailyValue]) -> [TokenUsageDailyUpsertRow] {
        days.compactMap { day in
            guard let value = values[day] else { return nil }
            return TokenUsageDailyUpsertRow(
                userId: userID, day: day, deviceId: deviceID,
                claudeTotal: value.claude, codexTotal: value.codex, codexAccount: value.codexAccount
            )
        }
    }
}
