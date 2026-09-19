import Foundation
import CheckCore

@MainActor
extension WorkTimerStore {
    /// 실행 직후 저장 세션을 활성화해야 하는지(D1). 키가 없으면(canSync == false) **킥하지 않는다** —
    /// missingAnonKey 는 classifyAuthError 에서 `.fatal` 이라 refreshPersistedSessionIfPossible 이 저장 세션을
    /// 조용히 지운다(아래 clearPersistedSession 분기). 지금까진 팝오버를 직접 연 사람만 그 경로를 밟았지만
    /// 킥은 화면 없이 도므로, 키 없이 `swift run` 한 개발 맥에서 실계정 세션이 아무 화면도 안 보인 채 날아간다.
    var shouldActivateOnLaunch: Bool { isSignedIn && canSync && !hasActivatedStoredSession }

    /// 실행당 1회 저장 세션 활성화를 발사하고 그 Task 를 돌려준다(테스트가 완료를 기다릴 수 있게).
    /// 조건 미달이면 아무것도 하지 않고 nil — 비로그인/키 없음 실행에서 요청이 0건이어야 하는 계약이다.
    @discardableResult
    func activateStoredSessionOnLaunch() -> Task<Void, Never>? {
        guard shouldActivateOnLaunch else { return nil }
        let task = Task { @MainActor [weak self] in
            await self?.performActivateStoredSession()
            self?.launchActivationTask = nil
        }
        launchActivationTask = task
        return task
    }

    /// 팝오버 오픈(.task) 진입점. 실행 킥이 아직 돌고 있으면 **그 완료를 먼저 기다린다** — 기다리지 않으면
    /// 킥의 refresh grant 가 in-flight 인 사이에 fast path 의 confirmMembership 이 회전 전 access token 으로
    /// 나갔다가 401 → 같은 낡은 refresh token 으로 두 번째 grant 를 치게 된다(launchActivationTask 주석 참조).
    func activateStoredSession() async {
        if let launchActivationTask { await launchActivationTask.value }
        await performActivateStoredSession()
    }

    private func performActivateStoredSession() async {
        guard session != nil else {
            return
        }
        // 실행당 1회만 전체 활성화(토큰 회전 + 멤버십 확정)한다. 이후 팝오버 여닫이에선 refresh 만 돌려
        // refresh token 회전(+reuse-detection 리스크)을 없앤다. access token 만료는 401 재시도 경로가 담당한다.
        if hasActivatedStoredSession {
            // 첫 활성화가 오프라인/취소로 멤버십 확정에 실패했으면(membershipConfirmed==false) 재오픈 때 재확정한다 —
            // hasActivatedStoredSession 조기 래치로 확정 경로가 영구 소멸하던 결함을 막는다. 토큰 회전은 여전히 1회다.
            // 방금 확정했으면 팀 상태는 스로틀과 무관하게 받는다(그 전까진 팀이 nil 이라 스탬프가 찍힌 적이 없다).
            if !membershipConfirmed {
                await confirmMembership()
                await refreshTeamStatus()
                return
            }
            // v0.2.38 Q10: 마지막 팀 상태 수신이 15초 안이면 4 GET 을 건너뛴다 — 첫 프레임은 캐시(teamMembers)로
            // 그리고 30초 폴링이 평소처럼 갱신한다. 계측상 팝오버 여닫이마다 나가던 6요청 중 4가 이 호출이었다.
            // (memberships/my_team_invite_code 는 setMenuPresented 의 refreshTeamMetaIfStale 이 60초 스로틀로 따로 관리.)
            guard !teamStatusIsFresh(now: clock()) else { return }
            // v0.2.38 S3: 팀 상태 4 GET 대신 work_tick(p_heartbeat=false) 1건 — 폴백은 그 4 GET 그대로.
            await refreshTeamStatusOnDemand()
            return
        }
        hasActivatedStoredSession = true
        let generation = sessionGeneration
        await refreshPersistedSessionIfPossible()
        guard generation == sessionGeneration else { return }
        await confirmMembership()
        guard generation == sessionGeneration else { return }
        await refreshTeamStatus()
        guard generation == sessionGeneration else { return }
        startStatusRefreshLoop()
        // 지갑을 한 번 맞춘다. 기본 p_days_back=1 이라 **어제 3시간을 채우고 앱을 껐던 사용자의 몫이
        // 여기서 소급된다** — 이 호출이 없으면 그 코인은 영영 안 들어온다.
        syncUltraWallet(reason: .signIn)
        syncEquippedCharacterFromServer(reason: .launch)
        // 사람 아바타의 캐릭터 한 표(2026-09-20) — 세션이 생기는 순간 한 번. 그 뒤로는 팝오버 열기의 60초 스로틀이 맡는다.
        refreshAppUserCharacters()
    }

    func signIn(email: String, password: String) async {
        syncMessage = "로그인 중"
        let generation = sessionGeneration
        do {
            let signedInSession = try await service.signIn(email: email, password: password)
            guard generation == sessionGeneration else { return }
            await completeSignIn(signedInSession, email: email)
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "로그인 실패")
        }
    }

    /// 세션을 손에 넣은 직후의 **공통 마무리**. 비밀번호/OTP 등 세션을 얻는 경로가 늘어나도 로그인 이후의
    /// 일은 반드시 여기 한 곳을 지나게 한다 — 복제하면 언젠가 갈리고, 갈린 쪽은 "로그인은 됐는데 팀이 없다 /
    /// 하트비트가 안 돈다 / 회고가 안 뜬다"처럼 **화면상 정상으로 보이는** 결함으로만 드러난다.
    func completeSignIn(_ signedInSession: SupabaseSession, email: String) async {
        let generation = sessionGeneration
        session = signedInSession
        persistSession(signedInSession, email: email)
        // 강제 로그아웃이 남겨 둔 미반영 근무 큐/진행 중 근무의 주인을 확정한다(같은 계정이면 재생, 다른 계정이면 폐기).
        adoptWorkStateOwner(signedInSession.userID)
        self.password = ""
        await confirmMembership()
        guard generation == sessionGeneration else { return }
        syncMessage = "동기화됨"
        await refreshTeamStatus()
        guard generation == sessionGeneration else { return }
        startStatusRefreshLoop()
        // 개인 기록(히트맵/회고)을 로그인 직후에 받아 온다. 자동 로드의 유일한 진입점이 팝오버 오픈 훅
        // (setMenuPresented → needsInsightsReload)뿐이면, **팝오버를 연 채 로그인하는 정상 동선**에서는
        // 그 훅이 이미 비로그인 시점에 지나가 버려(performLoadInsights 의 session 가드에서 즉시 반환)
        // insights 가 그 팝오버 세션 내내 비어 있다. 리그/토큰보드/찌르기는 사용자가 직접 여는 패널이라
        // 무관하지만, 지난주 회고 배너는 사용자가 열 수 없는 '자동 안내'라 이 경로가 없으면 팝오버를
        // 닫았다 다시 열기 전까지 영영 뜨지 않는다(회귀 지점).
        if needsInsightsReload { await performLoadInsights() }
        // 저장 세션 활성화 경로와 같은 이유로 지갑을 맞춘다(어제 몫 소급).
        syncUltraWallet(reason: .signIn)
        syncEquippedCharacterFromServer(reason: .signIn)
        // 사람 아바타의 캐릭터 한 표(2026-09-20) — 로그인 직후 한 번(팝오버를 연 채 로그인하는 정상 동선은 열기 훅을 이미 지나쳤다).
        refreshAppUserCharacters()
    }

    func signUp(email: String, password: String, displayName: String, center: String? = nil) async {
        syncMessage = "계정 생성 중"
        let generation = sessionGeneration
        do {
            if let createdSession = try await service.signUp(
                email: email, password: password, displayName: displayName, center: center
            ) {
                // 지금 서버(가입 즉시 확인): 예전과 완전히 같다 — 코드 화면 없이 곧장 팀 합류/만들기로 간다.
                guard generation == sessionGeneration else { return }
                await completeSignUp(createdSession, email: email, displayName: displayName, center: center)
            } else {
                // 가입 확인을 켠 서버: 계정은 만들어졌고 확인 메일이 나갔다. 세션은 코드가 통과해야 생기고, 팀 합류/만들기는
                // 그 뒤 **같은 completeSignUp** 에서 이어진다(WorkTimerStoreSignUpOTP.swift). 서버 모드를 따로 묻지 않는다 —
                // 이 nil 이 신호다(SupabaseWorkService.signUp).
                guard generation == sessionGeneration else { return }
                self.password = ""
                syncMessage = "확인 메일 필요"
                enterSignUpConfirmation(email: email, displayName: displayName, center: center)
            }
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "계정 생성 실패")
        }
    }

    /// 가입으로 **세션을 손에 넣은 직후**의 공통 마무리. 즉시 세션이 온 경로(지금 서버)와 코드 검증을 지난 경로(가입 확인을
    /// 켠 서버)가 **둘 다 여기 하나를 지난다** — 두 벌로 갈라 두면 한쪽만 고쳐지는 날이 온다(completeSignIn 과 같은 이유).
    /// `displayName`/`center` 는 가입 요청에 실어 보낸 값이다(서버 트리거가 profiles 에 넣는다). 재시작 뒤 코드 입력 출구로
    /// 들어온 사람은 그 값을 모를 수 있어 Optional 이고, 모르면 미러를 세우지 않는다 — 서버 정본은 가입 때 이미 섰다.
    func completeSignUp(_ createdSession: SupabaseSession, email: String, displayName: String?, center: String?) async {
        let generation = sessionGeneration
        session = createdSession
        persistSession(createdSession, email: email, displayName: displayName)
        // 방금 가입 메타데이터로 실어 보낸 값이다(서버 트리거가 그대로 profiles 에 넣는다).
        // 여기서 미러를 세워 두지 않으면 가입 직후 설정 창이 '불러오는 중'으로 떠 있다가
        // 다음 폴링에서야 값이 나타난다 — 방금 자기가 고른 것을 못 보는 화면이 된다.
        //
        // ★ 모르는 값은 세우지 않는다: signupCenter 는 화면이 채우지만, 그 값이 CenterLabel 의
        //   어휘가 아니면 서버 트리거가 null 로 접으므로 미러도 '아직 모름'으로 둬야 진실과 같다.
        if let center, CenterLabel.isKnown(center) {
            myCenter = center
            myCenterLoaded = true
        }
        // 새 계정이므로 앞 계정이 남긴 큐/진행 중 근무는 여기서 버려진다(오염 금지).
        adoptWorkStateOwner(createdSession.userID)
        self.password = ""
        // 트리거는 더 이상 팀을 만들지 않으므로, 모드에 따라 팀을 만들거나(join 은 하지 않고) 코드로 합류한다.
        if isCreateTeamMode {
            await createTeamAfterSignup()
        } else {
            await joinTeamAfterSignup()
        }
        guard generation == sessionGeneration else { return }
        syncMessage = "동기화됨"
        await refreshTeamStatus()
        guard generation == sessionGeneration else { return }
        startStatusRefreshLoop()
        // 사람 아바타의 캐릭터 한 표(2026-09-20) — 가입으로 세션이 생긴 직후 한 번(로그인 마무리와 같은 이유).
        refreshAppUserCharacters()
    }

    /// 코드 모드 가입 성공 후. signupTeamCode 로 join_team 을 실행하고 confirmMembership 으로 팀을 확정한다.
    /// 코드는 맞았는데 합류가 0행일 때의 문구. **두 자리(가입 직후 · 무소속 화면)가 같은 문장을 쓴다** —
    /// 두 벌로 적으면 한쪽만 낡는다. 서버 근거는 `join_team` 의 센터 게이트다.
    var teamlessJoinBlockedMessage: String { "다른 센터 팀이에요 — 같은 센터 코드인지 확인해 주세요" }

    private func joinTeamAfterSignup() async {
        let generation = sessionGeneration
        let code = signupTeamCode
        // 코드가 비어 있으면 합류 왕복을 내지 않는다. 가입 폼에서는 joinPreview 게이트가 있어 비지 않지만, 재시작 뒤
        // 코드 입력 출구(로그인 폼의 "이메일 확인 필요")로 들어온 사람은 팀 코드를 친 적이 없다 — 빈 코드로 join_team 을
        // 치면 서버 오류만 남기고 결과는 어차피 무소속이다. 곧장 무소속 확정으로 가면 무소속 패널이 그 사람을 받는다.
        // 재시도(allowRetryForFreshSignup)는 방금 낸 합류의 트리거 지연을 기다리는 장치라 합류가 없으면 쓰지 않는다.
        guard !SupabaseWorkService.normalizeInviteCode(code).isEmpty else {
            await confirmMembership()
            return
        }
        do {
            let joined = try await withSessionRetry { activeSession in
                try await service.joinTeam(accessToken: activeSession.accessToken, code: code)
            }
            guard generation == sessionGeneration else { return }
            // 코드가 맞는데도 0행이면 센터 게이트다(위 performJoinTeamWithCode 의 같은 판정).
            // 예전엔 **아무 말 없이** 무소속으로 떨어져서, 부산 연수생이 서울 코드로 가입하면
            // 왜 팀이 없는지 알 길이 없었다.
            if joined == nil { joinPreviewMessage = teamlessJoinBlockedMessage }
        } catch {
            // 합류 실패는 조용히 넘기고 confirmMembership 이 무소속으로 확정하게 둔다(문구는 이후 refresh 가 정리).
            guard generation == sessionGeneration else { return }
        }
        // 가입 직후 확정은 트리거 지연이 없더라도(직접 upsert) 안전하게 재시도 경로를 재사용한다.
        await confirmMembership(allowRetryForFreshSignup: true)
    }

    /// 만들기 모드 가입 성공 후. create_team 으로 팀을 만들고 참여코드를 안내용으로 보관한 뒤 팀을 확정한다.
    private func createTeamAfterSignup() async {
        let generation = sessionGeneration
        let name = createTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = createTeamGoalHours
        // 팀 이름이 비면 만들기 왕복을 내지 않는다(joinTeamAfterSignup 의 빈 코드와 같은 자리 — 재시작 뒤 출구로 들어온 사람).
        guard !name.isEmpty else {
            await confirmMembership()
            return
        }
        do {
            let created = try await withSessionRetry { activeSession in
                try await service.createTeam(accessToken: activeSession.accessToken, name: name, goalHours: goal)
            }
            guard generation == sessionGeneration else { return }
            createdTeamCode = created.inviteCode
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "팀 생성 실패")
        }
        await confirmMembership(allowRetryForFreshSignup: true)
    }

    /// 로그인/세션복구/가입 성공 후 내 팀을 확정한다. 소속이 있으면 currentTeamID/teamName/teamGoalSeconds 를
    /// 서버 값으로 채우고, 없으면 무소속(currentTeamID=nil, teamName="팀", 목표=기본값)으로 둔다.
    /// 가입 직후에는 트리거 타이밍 때문에 빈 값이면 1초 간격으로 3회까지 재시도한다.
    func confirmMembership(allowRetryForFreshSignup: Bool = false) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        let attempts = allowRetryForFreshSignup ? 3 : 1
        for attempt in 0..<attempts {
            // fetch 발사 전 목표 write 세대를 캡처한다. 응답을 반영할 때 값이 바뀌었으면(그 사이 새 목표 write)
            // teamGoalSeconds 대입만 건너뛴다(팀명/역할/코드는 최신 서버값으로 반영).
            let goalWriteGen = teamGoalWriteGeneration
            let membership: (teamID: String, teamName: String, goalHours: Int, role: String)?
            do {
                membership = try await withSessionRetry { activeSession in
                    try await service.fetchOwnMembership(accessToken: activeSession.accessToken, userID: activeSession.userID)
                }
            } catch {
                // 취소/네트워크 오류를 포함한 모든 throw 는 무소속 확정으로 이어지지 않는다. 기존 팀 상태를
                // 유지한 채 조용히 빠져나간다('정상 응답 0행'일 때만 아래에서 무소속으로 확정한다).
                guard generation == sessionGeneration else { return }
                return
            }
            guard generation == sessionGeneration else { return }
            if let membership {
                // 소속 확인 성공 — 확정적 결과. throw(취소/네트워크)로는 여기 오지 않는다.
                membershipConfirmed = true
                currentTeamID = membership.teamID
                teamName = membership.teamName
                // 목표시간은 DB 값(시간) 그대로 초로 환산해 반영한다(캐시/일회성 없음). 단, fetch 발사 후 새 목표를
                // write 했으면(세대 변화) 이 응답은 낡은 값이므로 목표 대입만 건너뛴다(스냅백 방지).
                if teamGoalWriteGeneration == goalWriteGen {
                    teamGoalSeconds = membership.goalHours * 3600
                    // 이 응답이 인사이트 응답보다 늦게 왔다면 회고가 기본 목표로 굳어 있다 — 목표선만 바로잡는다.
                    reconcileInsightsGoal()
                }
                teamRole = membership.role
                // 참여코드는 소속 팀원 누구나 공유할 수 있게 항상 로드한다(코드가 곧 열쇠 — 팀원도 새 동료를 초대).
                await loadMyInviteCode()
                return
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(for: .seconds(1))
                guard generation == sessionGeneration else { return }
            }
        }
        // 정상 응답 0행 — 무소속으로 확정한다(이 역시 확정적 결과다).
        membershipConfirmed = true
        currentTeamID = nil
        teamName = "팀"
        teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
        reconcileInsightsGoal()
        teamRole = nil
        myTeamInviteCode = nil
    }

    /// 소속 팀원이면 my_team_invite_code() RPC 로 참여코드를 로드한다. 실패/무소속이면 nil.
    private func loadMyInviteCode() async {
        let generation = sessionGeneration
        let code: String?
        do {
            code = try await withSessionRetry { activeSession in
                try await service.fetchMyInviteCode(accessToken: activeSession.accessToken)
            }
        } catch {
            // 일시 실패(취소/네트워크)는 try? 로 nil 삼켜 코드 버튼을 깜빡 지우지 말고, 기존 myTeamInviteCode 를
            // 유지한다(대입 스킵). 정상 0행일 때만 아래에서 nil 로 확정한다.
            return
        }
        guard generation == sessionGeneration else { return }
        myTeamInviteCode = code
    }

    /// 지금 착용한 캐릭터를 서버(`profiles.character`)에 밀어 넣는다. **베스트 에포트**다.
    ///
    /// **왜 필요한가**: 선택은 `CharacterSelection` 이 `UserDefaults` 에만 저장한다. 그것만으로는
    /// 내 화면만 바뀌고 **남에게는 영원히 아잉**으로 보인다 — 캐릭터가 남에게 보이는 자리(아바타·울트라) 중 하나인
    /// 울트라 찌르기가 `take_pokes` 의 `from_character`(= 서버 컬럼)를 읽기 때문이다.
    ///
    /// **부르는 곳은 사용자가 이 맥에서 직접 고른 순간뿐이다**(선택기 두 곳의 `onChosen`). 0.3.29 까지는 세션이
    /// 생기는 두 경로(저장 세션 활성화 · 로그인 마무리)에서도 밀었지만, 폰에서도 캐릭터를 바꾸게 되면서 그 밀기가
    /// 폰의 변경을 **말없이 되돌리는** 장치가 됐다(R8). 그 두 경로는 이제 `syncEquippedCharacterFromServer` 로
    /// **읽어서 따른다**.
    ///
    /// `announcesFailure` 가 거짓이면 조용히 넘긴다(사용자가 한 행동이 아닌 경로 — 실패 문구를 띄우면 원인 없는
    /// 경고가 된다). 사용자가 직접 고른 순간에는 참으로 부른다.
    func pushSelectedCharacter(announcesFailure: Bool) {
        let id = CharacterSelection(defaults: characterDefaults,
                                    catalog: CheckCharacter3DScene.catalog).selectedID
        // ★ **Task 를 띄우기 전에** 로컬 쓰기를 적는다. 선택기는 이 함수보다 먼저 로컬을 바꿨는데, Task 첫 줄
        //   (pushCharacter 의 beginPush)이 돌기 전에 떠 있던 서버 조회 응답이 먼저 메인 액터를 잡으면 **방금 고른
        //   캐릭터를 옛 서버값으로 덮는다**. 여기서 적어 두면 그 응답은 낡은 것으로 버려진다.
        characterSync.noteLocalWrite()
        // 내 아바타 칸도 같은 순간에(2026-09-20) — 서버 표는 다음 조회에야 이 값을 안다.
        noteMyEquippedCharacter()
        Task { [weak self] in
            await self?.pushCharacter(id, announcesFailure: announcesFailure)
        }
    }

    /// 위의 실제 본체. 로컬 선택은 **되돌리지 않는다** — 서버가 거절해도 내 화면의 캐릭터는 그대로 둔다
    /// (모르는 id 는 어차피 클라 카탈로그가 아잉으로 접으므로 화면이 깨지지 않는다). `not_owned` 만 예외(아래).
    ///
    /// 반환: 서버가 대답한 status. 네트워크 실패·취소·계정 전환(세대 바뀜)이면 nil — 옮겨 가기 도장이 이 값으로
    /// "판정이 끝났는가"를 가른다(`CharacterSyncDecision.migrationSettled`).
    @discardableResult
    func pushCharacter(_ id: String?, announcesFailure: Bool) async -> String? {
        // 밀기가 떠 있는 동안(시작~끝) 겹친 서버 조회 응답은 전부 버린다 — 그 GET 이 이 쓰기 전의 값을
        // 읽었는지 후의 값을 읽었는지 클라는 알 수 없다(performEquippedCharacterSync 의 가드).
        let sync = characterSync
        sync.beginPush()
        defer { sync.endPush() }
        let generation = sessionGeneration
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.setCharacter(accessToken: activeSession.accessToken, id: id)
            }
            guard generation == sessionGeneration else { return nil }
            switch response.status {
            case "ok":
                break
            case "not_owned":
                // ★ **되돌리기는 `announcesFailure` 와 무관하다.** 이건 '실패 안내'가 아니라 **상태 정합**이다:
                //   로컬엔 유령이 있는데 서버는 아잉이면, 내 화면엔 유령이 서고 **남에게는 아잉**이 보인다
                //   (오버레이·메뉴바는 로컬 값으로 그리고 울트라 찌르기는 서버 컬럼을 읽는다).
                //   두 쪽이 갈린 채로 두지 않는다.
                //
                //   실제로 이 경로로 들어오는 사람: (가) 상점이 붙기 전 빌드에서 이미 캐릭터를 골라 둔
                //   사람(로컬 선택은 있는데 소유권 행이 없다 — 0.3.30 부터는 옮겨 가기 1회 밀기에서)
                //   (나) 기기 두 대 중 한쪽에서만 산 사람.
                revertCharacterToDefault()
            default:
                // unknown_character = 서버 CHECK 에 없는 id. 앱 번들과 서버 명단이 갈린 것이라
                // 사용자가 할 수 있는 일이 없다 — 그래도 조용히 성공한 척하지는 않는다.
                if announcesFailure { syncMessage = "캐릭터 저장 실패" }
            }
            return response.status
        } catch {
            guard generation == sessionGeneration else { return nil }
            if case .cancelled = classifyAuthError(error) { return nil }
            if announcesFailure { syncMessage = "캐릭터 저장 실패" }
            return nil
        }
    }

    /// 로컬 선택을 **아잉으로 되돌린다**(서버가 `not_owned` 로 거절했을 때의 치료).
    ///
    /// 되돌린 사실을 **반드시 한 줄로 말한다** — 아무 말 없이 캐릭터가 바뀌면 버그로 보인다.
    /// 되돌리기는 `CheckCharacterPicker` 를 지나므로 방송(broadcast)이 울고, 메뉴바 아이콘·헤더
    /// 마스코트·오버레이가 **그 자리에서** 아잉으로 다시 그려진다(직접 UserDefaults 를 쓰면 안 울린다).
    func revertCharacterToDefault() {
        let catalog = CheckCharacter3DScene.catalog
        let selection = CharacterSelection(defaults: characterDefaults, catalog: catalog)
        guard selection.selectedID != CharacterCatalog.builtInAingID else { return }
        CheckCharacterPicker.choose(CharacterCatalog.builtInAingID,
                                    selection: selection, broadcast: characterSync.broadcast)
        noteMyEquippedCharacter()
        syncMessage = Self.notOwnedRevertNotice
    }

    /// 되돌렸을 때의 문구(순수 — 값으로 검증한다). 상점으로 가는 길을 함께 말한다.
    nonisolated static let notOwnedRevertNotice = "안 산 캐릭터라 기본으로 돌아갔어요 — 상점에서 살 수 있어요"

    // MARK: - 착용 캐릭터 서버 기준 동기화 (v0.3.30)

    /// 팝오버를 열 때(`setMenuPresented`) 부른다. 60초 스로틀 — 폰에서 바꾼 캐릭터가 맥에 반영되는 길이다.
    func refreshEquippedCharacterIfStale() {
        syncEquippedCharacterFromServer(reason: .popover)
    }

    /// 서버 착용값(`profiles.character`)을 읽어 **로컬 선택을 서버에 맞춘다.** 실행(저장 세션 활성화)·로그인
    /// 마무리·팝오버 열기가 부른다. 이 경로는 원칙적으로 **밀지 않는다** — 쓰기는 사용자가 이 맥에서 고른 순간뿐이다.
    ///
    /// - 서버값이 로컬과 다르면 로컬을 바꾸고 **방송**한다(`CheckCharacterPicker.choose` — 메뉴바·헤더·오버레이가
    ///   고르기와 똑같은 길로 다시 그려진다). 이 빌드가 모르는 캐릭터·가지지 않은 캐릭터면 아잉.
    /// - **조회가 실패하면(네트워크·옛 서버·행 없음) 로컬을 그대로 두고 밀지도 않는다.** 모르는 것을 "기본"으로
    ///   단정하면 선택을 근거 없이 지우고, 밀면 폰의 변경을 되돌린다.
    /// - 예외 한 번: 옮겨 가기(`CharacterSyncDecision` 머리말) — 서버 null · 도장 없음 · 로컬 비기본이면 한 번 민다.
    ///
    /// 팝오버만 60초 스로틀과 겹침 방지를 건다. 실행·로그인은 세션이 생기는 순간이라 늘 읽는다(스로틀 시각은
    /// 찍으므로 실행 직후 팝오버를 열어도 두 번 읽지 않는다). 반환 Task 는 테스트가 완료를 기다리는 손잡이다.
    @discardableResult
    func syncEquippedCharacterFromServer(reason: CharacterSyncReason) -> Task<Void, Never>? {
        guard session != nil else { return nil }
        let sync = characterSync
        let now = clock()
        if reason == .popover {
            guard sync.fetchingToken == nil,
                  now.timeIntervalSince(sync.lastFetchAt) >= CharacterSyncState.popoverThrottleSeconds
            else { return nil }
        }
        sync.lastFetchAt = now
        sync.tokenSeed &+= 1
        let token = sync.tokenSeed
        sync.fetchingToken = token
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performEquippedCharacterSync(token: token)
        }
        sync.lastTask = task
        return task
    }

    private func performEquippedCharacterSync(token: Int) async {
        let sync = characterSync
        // 겹침 표시는 **자기 것일 때만** 내린다 — 로그아웃 뒤 다음 계정의 조회가 이미 새 표를 세웠을 수 있다.
        defer { if sync.fetchingToken == token { sync.fetchingToken = nil } }
        let generation = sessionGeneration
        let writeRevision = sync.localWriteRevision
        let serverID: String?
        do {
            serverID = try await withSessionRetry { activeSession in
                try await service.fetchEquippedCharacter(accessToken: activeSession.accessToken,
                                                         userID: activeSession.userID)
            }
        } catch {
            // 네트워크·옛 서버(컬럼 없음 400)·행 없음·취소: 로컬 그대로, 밀지도 않는다. 다음 기회에 다시 읽는다.
            return
        }
        // 로그아웃 뒤 늦게 온 응답이 다음 계정의 선택을 바꾸지 않게.
        guard generation == sessionGeneration else { return }
        // 조회가 떠 있는 동안 사용자가 이 맥에서 골랐거나 밀기가 오갔으면 이 응답은 그 전의 서버값일 수 있다 —
        // 따라가면 방금 고른 캐릭터가 옛 값으로 튄다. 버리고 다음 팝오버(60초 뒤)에 다시 읽는다.
        guard sync.localWriteRevision == writeRevision, sync.pushesInFlight == 0 else { return }

        let catalog = CheckCharacter3DScene.catalog
        let selection = CharacterSelection(defaults: characterDefaults, catalog: catalog)
        let decision = CharacterSyncDecision.decide(
            serverID: serverID,
            localID: selection.selectedID,
            migrated: defaults.bool(forKey: CharacterSyncDecision.migrationDefaultsKey),
            isKnown: { catalog.manifest(id: $0) != nil },
            isUnlocked: { isCharacterUnlocked($0) }
        )
        switch decision {
        case .keep:
            markCharacterMigrationSettled()
        case .adopt(let id):
            markCharacterMigrationSettled()
            CheckCharacterPicker.choose(id, selection: selection, broadcast: sync.broadcast)
            // 폰에서 바꾼 캐릭터를 따랐다 — 내 아바타 칸도 같은 캐릭터로(2026-09-20).
            noteMyEquippedCharacter()
        case .migrate(let id):
            let status = await pushCharacter(id, announcesFailure: false)
            if CharacterSyncDecision.migrationSettled(byStatus: status) { markCharacterMigrationSettled() }
        }
    }

    /// 옮겨 가기 도장. **스토어의 `defaults`** 에 둔다(다른 1회 도장들과 같은 곳, 앱에선 `characterDefaults` 와 같은
    /// `.standard`). `characterDefaults` 에 두지 않는 이유: 그 값을 `.standard` 로 둔 채 실행 경로를 태우는 기존
    /// 테스트들이 이 도장을 **테스트 프로세스의 전역 도메인**에 남기게 된다.
    private func markCharacterMigrationSettled() {
        guard !defaults.bool(forKey: CharacterSyncDecision.migrationDefaultsKey) else { return }
        defaults.set(true, forKey: CharacterSyncDecision.migrationDefaultsKey)
    }

    /// 이 스토어의 캐릭터 동기화 상태(스로틀·겹침·로컬 쓰기 세대·방송 통로).
    ///
    /// ★ 저장 프로퍼티가 아니라 **연관 객체**다. `WorkTimerStore.swift` 는 같은 묶음의 여러 갈래가 동시에 고치는
    ///   파일이라 이 갈래는 거기에 줄을 더하지 않는다(병합 충돌 최소화). 수명은 스토어와 같고, 스토어마다 따로다 —
    ///   `ObjectIdentifier` 사전으로 두면 테스트가 스토어를 만들고 버릴 때 주소가 재사용돼 **남의 스로틀 시각**을
    ///   물려받는다. 병합 뒤 저장 프로퍼티로 옮겨도 된다(`@ObservationIgnored` — 화면이 읽는 값이 아니다).
    var characterSync: CharacterSyncState {
        if let existing = objc_getAssociatedObject(self, &CharacterSyncState.associationKey) as? CharacterSyncState {
            return existing
        }
        let created = CharacterSyncState()
        objc_setAssociatedObject(self, &CharacterSyncState.associationKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return created
    }

    // MARK: - 상점 / 루비 (v0.3.17)

    /// 상점에서 "울트라"를 가리키는 id. 캐릭터 id 와 같은 칸(`purchasingID`)을 쓰므로 **캐릭터가
    /// 절대 가질 수 없는 이름**이어야 한다(서버 CHECK 의 허용 목록은 전부 소문자 낱말이다).
    static let ultraPurchaseID = "#ultra"

    /// 상점 상태(잔량·가격·보유)를 한 번 읽는다. 진입(`toggleShopPanel`)과 구매 직후가 호출부다.
    ///
    /// **로컬 캐시를 믿지 않는 이유**: 가격도 보유도 다른 기기에서 바뀐다(다른 맥에서 사고 왔을 수 있다).
    /// 캐시만 믿으면 "산 게 안 산 걸로 보이는" 화면이 된다.
    func loadShopState() {
        guard !shopLoading else { return }
        shopLoading = true
        let generation = sessionGeneration
        Task { [weak self] in
            guard let self else { return }
            defer { self.shopLoading = false }
            do {
                let state = try await withSessionRetry { activeSession in
                    try await self.service.fetchShopState(accessToken: activeSession.accessToken)
                }
                guard generation == self.sessionGeneration else { return }
                self.applyShopState(state)
                self.shopLoaded = true
                self.shopFailed = false
            } catch {
                guard generation == self.sessionGeneration else { return }
                // 취소(패널 빠른 닫기)는 실패가 아니다 — 문구를 남기면 헛경보가 된다.
                if case .cancelled = self.classifyAuthError(error) { return }
                self.shopFailed = true
            }
        }
    }

    /// 서버가 말한 상점 상태를 화면 상태로 옮긴다. **nil 은 건너뛴다** — "모른다"를 0 으로 적으면
    /// 잔량이 있는 사람에게 "0개"라고 말하는 화면이 된다(응답 모델이 전 필드 Optional 인 이유와 같다).
    func applyShopState(_ state: ShopStateResponse) {
        if let ruby = state.rubyBalance { rubyBalance = ruby }
        if let ultra = state.ultraBalance { ultraBalance = ultra }
        if let price = state.ultraPrice { ultraPrice = price }
        if let buyMax = state.ultraBuyMax { ultraBuyMax = buyMax }
        guard let rows = state.characters else { return }
        shopCharacters = rows
        // 아잉은 무료라 서버 목록에 없어도 언제나 보유다.
        var owned: Set<String> = [CharacterCatalog.builtInAingID]
        for row in rows where row.owned == true { owned.insert(row.id) }
        ownedCharacterIDs = owned
    }

    /// 상점 카드를 눌렀을 때. **고르기만 한다 — 여기서는 아무것도 사지 않는다.**
    ///
    /// ★ 예전에는 이 함수가 곧바로 `buyCharacter` 를 불렀고, 그래서 사용자가 **실수로 전부 사 버렸다**
    ///   (2026-09-14 신고). 구매로 가는 문은 이제 `confirmShopPurchase()` 하나뿐이다.
    ///
    /// 이미 가진 캐릭터는 **고르지 않는다** — 대신 그 사실을 말한다(침묵하면 눌러도 아무 일이 없어
    /// 고장으로 보인다).
    func selectShopItem(_ selection: ShopSelection) {
        guard purchasingID == nil else { return }
        if case .character(let id) = selection, ownedCharacterIDs.contains(id) {
            shopSelection = nil
            shopNotice = Self.alreadyOwnedNotice
            return
        }
        // 같은 것을 다시 누르면 선택을 푼다(실수로 고른 것을 되돌리는 길).
        shopSelection = (shopSelection == selection) ? nil : selection
        shopNotice = nil
    }

    /// 이미 가진 것을 눌렀을 때의 문구(순수 — 값으로 검증한다).
    nonisolated static let alreadyOwnedNotice = "이미 갖고 있어요"
    /// 아무것도 안 골랐을 때 하단 바가 말하는 것.
    nonisolated static let pickSomethingNotice = "살 것을 골라 주세요"

    /// 지금 고른 것의 값(루비). 모르면 nil — 숫자를 지어내지 않는다.
    var shopSelectionPrice: Int? {
        switch shopSelection {
        case .character(let id): return shopPrice(of: id)
        case .ultra: return ultraPrice
        case nil: return nil
        }
    }

    /// 지금 고른 것을 살 수 있는가. 잔량이나 값을 **모르면 false** 다(모르면서 사지 않는다).
    var canConfirmShopPurchase: Bool {
        guard purchasingID == nil, shopSelection != nil else { return false }
        guard let have = rubyBalance, let price = shopSelectionPrice else { return false }
        return have >= price
    }

    /// ★ **실제 구매는 여기 하나뿐이다.** 하단 [구매하기] 버튼만 이 함수를 부른다 —
    ///   카드 탭에서 이 경로로 새는 길이 생기면 사용자가 또 실수로 산다.
    func confirmShopPurchase() {
        guard let selection = shopSelection, purchasingID == nil else { return }
        guard let have = rubyBalance else {
            loadShopState()
            return
        }
        guard let price = shopSelectionPrice else {
            // 값을 모르면 사지 않는다. 다시 읽어 본다.
            loadShopState()
            return
        }
        guard have >= price else {
            shopNotice = Self.shortfallNotice(need: price, have: have)
            return
        }
        switch selection {
        case .character(let id): buyCharacter(id)
        case .ultra: buyUltra(count: 1)
        }
    }

    /// 캐릭터를 산다. 성공하면 **서버가 준 값으로** 잔량·보유를 갱신한다(클라가 스스로 빼지 않는다).
    func buyCharacter(_ id: String) {
        guard purchasingID == nil else { return }
        purchasingID = id
        shopNotice = nil
        let generation = sessionGeneration
        Task { [weak self] in
            guard let self else { return }
            defer { self.purchasingID = nil }
            do {
                let response = try await withSessionRetry { activeSession in
                    try await self.service.buyCharacter(accessToken: activeSession.accessToken, id: id)
                }
                guard generation == self.sessionGeneration else { return }
                if let ruby = response.rubyBalance { self.rubyBalance = ruby }
                switch response.status {
                case "ok", "already_owned":
                    // already_owned 도 성공으로 접는다 — 다른 기기에서 이미 샀다는 뜻이라
                    // 사용자가 할 일이 없고, 목록을 다시 읽으면 화면이 사실과 맞는다.
                    self.ownedCharacterIDs.insert(id)
                    // 선택을 푼다 — 안 풀면 방금 산 것이 계속 골라진 채 남아 하단 바가 거짓말을 한다.
                    self.shopSelection = nil
                    self.shopNotice = response.status == "ok" ? "샀어요!" : Self.alreadyOwnedNotice
                    self.loadShopState()
                case "insufficient":
                    self.shopNotice = Self.shortfallNotice(need: response.need, have: response.have)
                default:
                    self.shopNotice = "구매 실패"
                }
            } catch {
                guard generation == self.sessionGeneration else { return }
                if case .cancelled = self.classifyAuthError(error) { return }
                self.shopNotice = "구매 실패"
            }
        }
    }

    /// 울트라를 산다(루비 → 울트라).
    func buyUltra(count: Int = 1) {
        guard purchasingID == nil else { return }
        purchasingID = Self.ultraPurchaseID
        shopNotice = nil
        let generation = sessionGeneration
        Task { [weak self] in
            guard let self else { return }
            defer { self.purchasingID = nil }
            do {
                let response = try await withSessionRetry { activeSession in
                    try await self.service.buyUltra(accessToken: activeSession.accessToken, count: count)
                }
                guard generation == self.sessionGeneration else { return }
                if let ruby = response.rubyBalance { self.rubyBalance = ruby }
                if let ultra = response.ultraBalance { self.ultraBalance = ultra }
                switch response.status {
                case "ok":
                    self.shopSelection = nil
                    self.shopNotice = "울트라 \(count)개를 샀어요!"
                case "insufficient":
                    // ★ 서버가 need/have 를 실어 준다 — **캐릭터 구매와 같은 필드다.** 클라가 다시
                    //   계산하면 값을 바꾸는 날 두 곳이 갈린다. 서버가 안 줬을 때만 가격×개수로 접는다.
                    self.shopNotice = Self.shortfallNotice(
                        need: response.need ?? self.ultraPrice.map { $0 * count },
                        have: response.have ?? self.rubyBalance)
                default:
                    self.shopNotice = "구매 실패"
                }
            } catch {
                guard generation == self.sessionGeneration else { return }
                if case .cancelled = self.classifyAuthError(error) { return }
                self.shopNotice = "구매 실패"
            }
        }
    }

    /// 모자란 만큼을 말하는 문구(순수 — 값으로 검증한다). 서버가 숫자를 안 줬으면 **수를 지어내지 않는다.**
    nonisolated static func shortfallNotice(need: Int?, have: Int?) -> String {
        CheckCoreShared.shortfallNotice(need: need, have: have)
    }

    /// 팀 주간 목표시간을 바꾼다(팀원 누구나). 범위(1~168) 밖이거나 이미 변경 중이면 즉시 false 로 무시한다.
    /// 성공 시 목표를 서버 반영값으로 갱신하고 안내 문구를 남기며, 리그 페이지가 열려 있으면 새로고침한다.
    /// 취소(빠른 닫기)는 조용히 넘기고(문구 유지), 그 외 실패는 authMessage 로 알린다.
    /// 반환값(성공 여부)으로 뷰가 편집 행을 닫을지 결정한다(실패 시 값 유지·재시도 가능).
    @discardableResult
    func updateTeamGoal(hours: Int) async -> Bool {
        guard (1...168).contains(hours) else { return false }
        guard !isUpdatingTeamGoal else { return false }
        isUpdatingTeamGoal = true
        defer { isUpdatingTeamGoal = false }
        let generation = sessionGeneration
        do {
            let newGoalHours = try await withSessionRetry { activeSession in
                try await service.setTeamWeeklyGoal(accessToken: activeSession.accessToken, goalHours: hours)
            }
            guard generation == sessionGeneration else { return false }
            teamGoalSeconds = newGoalHours * 3600
            // 개인 기록 회고의 목표선도 새 목표를 따라간다(패널을 다시 열지 않아도 즉시 일치).
            reconcileInsightsGoal()
            // 이 write 이후 도착하는 낡은 멤버십 응답(in-flight refreshTeamMeta/confirmMembership)이 목표를
            // 되돌리지 못하게 세대를 올린다.
            teamGoalWriteGeneration += 1
            syncMessage = "주간 목표 변경됨"
            // 리그 페이지가 열려 있으면 바뀐 목표가 게이지/퍼센트에 즉시 반영되도록 새로고침한다(내부에서 노출 가드).
            await refreshLeaderboardIfVisible()
            return true
        } catch {
            guard generation == sessionGeneration else { return false }
            // 취소(.task 취소/빠른 닫기)는 헛경보 문구를 남기지 않고 조용히 넘긴다.
            if case .cancelled = classifyAuthError(error) { return false }
            syncMessage = authMessage(for: error, fallback: "목표 변경 실패")
            return false
        }
    }

    /// 팝오버를 열 때 60초 스로틀로 팀 메타(목표/이름/역할/참여코드)를 재조회한다. 팀원이 바꾼 목표가
    /// 내 팝오버에 최대 1분 안에 반영되게 한다. 스로틀 시각은 관찰 대상이 아니라 무효화를 유발하지 않는다.
    /// 로그인·소속 상태에서만 동작하고, 무소속 확정은 여기서 하지 않는다(refreshTeamStatus 담당).
    func refreshTeamMetaIfStale(now: Date = Date()) {
        guard session != nil, currentTeamID != nil else { return }
        guard now.timeIntervalSince(lastTeamMetaRefreshAt) >= Self.teamMetaRefreshThrottleSeconds else { return }
        lastTeamMetaRefreshAt = now
        Task { @MainActor in await refreshTeamMeta() }
    }

    /// 멤버십을 재조회해 팀 메타(목표/이름/역할)와 참여코드를 갱신한다. == 가드로 값이 실제로 바뀔 때만
    /// 대입해 폴링이 숨은 잎 뷰를 헛무효화하지 않게 한다. 취소/네트워크 오류는 조용히 넘긴다(다음 기회 재시도).
    func refreshTeamMeta() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        // fetch 발사 전 목표 write 세대를 캡처한다(응답이 낡았는지 판정용).
        let goalWriteGen = teamGoalWriteGeneration
        let membership: (teamID: String, teamName: String, goalHours: Int, role: String)?
        do {
            membership = try await withSessionRetry { activeSession in
                try await service.fetchOwnMembership(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
        } catch {
            return
        }
        // 정상 0행(무소속 확정)은 여기서 처리하지 않는다 — 팀 메타 갱신만이 목적이라 기존 팀 상태를 유지한다.
        guard generation == sessionGeneration, let membership else { return }
        if currentTeamID != membership.teamID { currentTeamID = membership.teamID }
        if teamName != membership.teamName { teamName = membership.teamName }
        // fetch 발사 후 새 목표를 write 했으면(세대 변화) 이 응답은 낡은 목표라 대입을 건너뛴다(스냅백 방지).
        // 팀명/역할/코드는 최신 서버값으로 반영한다.
        if teamGoalWriteGeneration == goalWriteGen {
            let newGoal = membership.goalHours * 3600
            if teamGoalSeconds != newGoal { teamGoalSeconds = newGoal }
            reconcileInsightsGoal()
        }
        if teamRole != membership.role { teamRole = membership.role }
        await loadMyInviteCode()
    }

    /// previewTeamCode() 의 실제 작업. signupTeamCode 를 lookup_team_by_code 로 조회해 미리보기를 갱신한다.
    /// 세션이 아니라 previewGeneration 으로 마지막 요청만 반영한다(비로그인에서도 동작).
    func performPreviewTeamCode() async {
        let generation = previewGeneration
        let code = signupTeamCode
        let normalized = SupabaseWorkService.normalizeInviteCode(code)
        guard !normalized.isEmpty else {
            joinPreview = nil
            joinPreviewMessage = ""
            return
        }
        joinPreviewMessage = "확인 중"
        do {
            let preview = try await service.lookupTeamByCode(code: code)
            guard generation == previewGeneration else { return }
            if let preview {
                joinPreview = preview
                joinPreviewMessage = ""
            } else {
                joinPreview = nil
                joinPreviewMessage = "코드를 확인해 주세요"
            }
        } catch {
            guard generation == previewGeneration else { return }
            joinPreview = nil
            joinPreviewMessage = "코드를 확인해 주세요"
        }
    }

    /// joinTeamWithCode() 의 실제 작업. 로그인 상태에서 signupTeamCode 로 join_team 을 실행하고 팀을 확정한다.
    func performJoinTeamWithCode() async {
        guard session != nil else { return }
        let code = signupTeamCode
        let normalized = SupabaseWorkService.normalizeInviteCode(code)
        guard !normalized.isEmpty else {
            joinPreviewMessage = "팀 코드를 확인해 주세요"
            return
        }
        let generation = sessionGeneration
        do {
            let joined = try await withSessionRetry { activeSession in
                try await service.joinTeam(accessToken: activeSession.accessToken, code: code)
            }
            guard generation == sessionGeneration else { return }
            guard joined != nil else {
                // ★ **여기까지 왔으면 코드는 맞았다** — 바로 위 미리보기(`lookup_team_by_code`)가 팀을 찾아
                //   `joinPreview` 를 세웠기 때문이다. 그런데도 서버가 0행을 냈다면 남은 이유는 하나다:
                //   **다른 센터 팀**이다(`join_team` 의 센터 게이트, 20260912185423_join_team_center_gate.sql).
                //   "코드를 확인해 주세요"라고 말하면 사용자는 멀쩡한 코드를 몇 번이고 다시 친다.
                joinPreviewMessage = teamlessJoinBlockedMessage
                return
            }
            signupTeamCode = ""
            joinPreview = nil
            joinPreviewMessage = ""
            await confirmMembership()
            guard generation == sessionGeneration else { return }
            await refreshTeamStatus()
            guard generation == sessionGeneration else { return }
            startStatusRefreshLoop()
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "합류 실패")
        }
    }

    /// 인증 경로 에러 처분. 취소는 아무 상태도 바꾸지 않고, 일시 네트워크 오류는 세션을 유지하며,
    /// 진짜 만료(SupabaseWorkServiceError 등)만 로그아웃 대상이다. .task 취소로 강제 로그아웃되는 회귀를 막는다.
    typealias AuthErrorDisposition = CheckCore.AuthErrorDisposition

    /// 본문은 코어 `AuthErrorRules.classify` 로 옮겼다(D-base — 폰 세션이 같은 판정을 쓴다). 동작은 같다.
    func classifyAuthError(_ error: Error) -> AuthErrorDisposition {
        AuthErrorRules.classify(error)
    }

    /// 본문은 코어 `AuthErrorRules.message(for:fallback:)` 로 옮겼다(D-base — 폰 로그인 화면이 같은 문장을 쓴다).
    func authMessage(for error: Error, fallback: String) -> String {
        AuthErrorRules.message(for: error, fallback: fallback)
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let currentSession = session else {
            throw SupabaseWorkServiceError.sessionExpired
        }
        let generation = sessionGeneration

        do {
            return try await operation(currentSession)
        } catch let originalError as SupabaseWorkServiceError where originalError == .sessionExpired {
            guard generation == sessionGeneration else { throw originalError }
            guard let refreshToken = currentSession.refreshToken else {
                clearPersistedSession()
                syncMessage = "다시 로그인 필요"
                throw originalError
            }

            let refreshedSession: SupabaseSession
            do {
                // ★ 갱신 주체는 조정자 하나다(SessionRefreshCoordinator 주석). 여기서 직접
                //   service.refreshSession 을 부르면 리얼타임 선제 갱신과 경합해 refresh token 회전이
                //   겹치고, 그 결과가 근무 중 강제 로그아웃이다.
                refreshedSession = try await sessionRefreshCoordinator.refresh(
                    generation: generation,
                    // 인자로 붙잡지 않고 **호출 시점에** 읽는다 — 합류하지 못한 순차 호출이
                    // 이미 회전된 옛 토큰을 재사용하는 것을 막는 유일한 방법이다.
                    tokenProvider: { [weak self] in self?.session?.refreshToken ?? refreshToken },
                    refresh: { [service] token in try await service.refreshSession(refreshToken: token) },
                    apply: { [weak self] session in
                        guard let self, generation == self.sessionGeneration else { return }
                        self.session = session
                        self.persistSession(session)
                    }
                )
            } catch {
                guard generation == sessionGeneration else { throw originalError }
                // 취소/일시 네트워크 오류로 갱신이 실패했으면 세션을 유지한다(throw 는 유지 — 호출부가 재시도).
                // 진짜 만료(refresh token 무효 등)만 로그아웃한다.
                if classifyAuthError(error) == .fatal {
                    clearPersistedSession()
                    syncMessage = "다시 로그인 필요"
                }
                throw originalError
            }

            guard generation == sessionGeneration else { throw originalError }
            session = refreshedSession
            persistSession(refreshedSession)
            return try await operation(refreshedSession)
        }
    }

    func signOut() {
        sessionGeneration += 1

        if let accessToken = session?.accessToken {
            Task {
                await service.signOut(accessToken: accessToken)
            }
        }

        clearPersistedSession()
        startedAt = nil
        accumulatedSeconds = 0
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: Date())
        teamMembers = []
        currentTeamID = nil
        teamName = "팀"
        teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
        teamRole = nil
        teamDirectory = []
        selectedSignupTeamID = nil
        signupTeamCode = ""
        joinPreview = nil
        joinPreviewMessage = ""
        isCreateTeamMode = false
        createTeamName = ""
        createTeamGoalHours = 60
        createdTeamCode = nil
        myTeamInviteCode = nil
        // 가입 화면 센터 선택도 계정에 묶인 입력이다. 남기면 다음 사람이 가입 폼을 열었을 때 앞 사람이
        // 고른 칸이 이미 눌려 있어, 아무것도 안 고르고도 가입 버튼이 살아 있다(미선택 게이트가 무력화된다).
        signupCenter = nil
        currentSessionID = nil
        // 흡수 표식과 영속된 소유 세션 ID 도 함께 내린다. 로그아웃은 startedAt 을 실제로 지우므로(강제 로그아웃의
        // clearPersistedSession 과 달리 여기선 진행 중 근무를 남기지 않는다) 표식이 서술할 세션 자체가 사라진다.
        // 남겨 두면 다음 로그인 후 **내가 직접 시작한** 근무가 흡수로 오인돼 자동 마감·하트비트가 통째로 죽고,
        // 소유 ID 쪽은 이미 끝난 세션을 가리킨 채 다음 실행의 재시작 판정에 끼어든다.
        releaseSessionOwnership()
        pendingItems = []
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        clearRecentAutoCloseResume()
        isEditingWeeklyGoal = false
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        tickerTask?.cancel()
        tickerTask = nil
        refreshMenuBarTitle()
        syncMessage = "로그인 필요"
    }

    private func refreshPersistedSessionIfPossible() async {
        guard let refreshToken = session?.refreshToken else {
            return
        }
        let generation = sessionGeneration

        do {
            let refreshedSession = try await service.refreshSession(refreshToken: refreshToken)
            guard generation == sessionGeneration else { return }
            session = refreshedSession
            persistSession(refreshedSession)
            syncMessage = "동기화됨"
        } catch {
            guard generation == sessionGeneration else { return }
            // .task 취소(팝오버 빨리 닫기)는 조용히, 일시 네트워크 오류는 세션 유지, 진짜 만료만 로그아웃한다.
            switch classifyAuthError(error) {
            case .cancelled:
                return
            case .transient:
                if syncMessage != "동기화 실패" { syncMessage = "동기화 실패" }
            case .fatal:
                clearPersistedSession()
                syncMessage = authMessage(for: error, fallback: "다시 로그인 필요")
            }
        }
    }
}

// MARK: - 비밀번호 재설정(메일 OTP)
//
// 흐름: [비밀번호를 잊었어요] → 이메일 입력 → 6자리 코드 메일 → **코드만** 입력 → **새 비밀번호만** 입력
//      → 로그인 화면 복귀(자동 로그인 없음).
// 브라우저도 딥링크도 타지 않는다(check:// 스킴을 등록한 앱이 없어 메일 링크가 빈 화면만 띄웠다).
//
// 화면을 둘로 쪼갠 이유: 한 화면에서 코드와 새 비밀번호를 함께 받으면 **코드가 틀렸을 때 새 비밀번호까지
// 같이 날아간다**. 자동 로그인을 뺀 이유: 방금 정한 비밀번호를 사용자가 직접 한 번 쳐 봐야 "정말 바뀌었다"가
// 확인되고, 재설정 경로가 로그인 세션을 만들지 않으므로 recovery 토큰이 디스크에 남을 여지도 사라진다.
@MainActor
extension WorkTimerStore {
    /// **첫 발송** 뒤 재전송이 열리기까지의 초. 60초가 아닌 이유: 첫 메일은 실제로 안 오는 일이 있는데
    /// (스팸함·전송 지연) 그때 1분을 붙잡아 두면 사용자가 할 수 있는 일이 아무것도 없다. 5초면 바로 다시
    /// 눌러 볼 수 있다. 서버가 그보다 긴 간격을 강제해 429 를 주면 **서버가 준 초로 덮인다**(아래 429 분기).
    static let passwordResetFirstResendDelaySeconds = 5
    /// **재전송** 뒤 쿨다운(초). GoTrue 는 같은 이메일에 대한 재발송을 기본 60초로 제한하고 429 를 준다.
    /// 서버가 남은 초를 알려주면 그 값을 쓰고, 못 알아내면 이 값으로 떨어진다(틀려도 '늦게 풀린다' 방향이라 안전).
    static let passwordResetResendCooldownSeconds = 60
    /// 새 비밀번호 최소 길이. GoTrue 기본 최소치와 같은 값이라 여기서 통과한 것을 서버가 길이로 거절하지 않는다.
    static let passwordResetMinPasswordLength = 6
    /// OTP 자릿수. GoTrue 메일 템플릿의 `{{ .Token }}` 기본이 6자리 숫자다.
    static let passwordResetCodeLength = 6

    // 사용자에게 나가는 문장 **그대로**. 한곳에 모아 두는 이유는 문구가 곧 계약이기 때문이다 —
    // 특히 발송 실패/성공 문구는 **계정 존재 여부를 흘리면 안 된다**(recover 는 없는 주소에도 200 을 준다.
    // "가입되지 않은 이메일" 류의 문구는 근거가 없을뿐더러 이 앱을 계정 목록 확인기로 만든다).
    static let passwordResetInvalidEmailMessage = "이메일 주소를 확인해주세요"
    static let passwordResetSentMessage = "메일을 보냈어요 · 오지 않으면 주소를 확인해주세요"
    static let passwordResetAlreadySentMessage = "메일을 이미 보냈어요 · 메일함을 확인해주세요"
    static let passwordResetCooldownMessage = "조금 뒤에 다시 받을 수 있어요"
    static let passwordResetSendFailedMessage = "메일을 보내지 못했어요 · 주소를 확인하고 다시 시도해주세요"
    static let passwordResetNetworkMessage = "네트워크를 확인하고 다시 시도해주세요"
    static let passwordResetInvalidCodeMessage = "메일로 받은 6자리 숫자를 입력해주세요"
    static let passwordResetShortPasswordMessage = "비밀번호 조건 확인 · 6자 이상으로 정해주세요"
    static let passwordResetRejectedPasswordMessage = "비밀번호 조건 확인 · 6자 이상, 이전과 다른 값으로 정해주세요"
    static let passwordResetCodeRejectedMessage = "코드가 맞지 않거나 만료됐어요 · 다시 받기를 눌러주세요"
    static let passwordResetUpdateFailedMessage = "비밀번호를 바꾸지 못했어요 · 다시 시도해주세요"
    /// 재설정 성공 후 **로그인 화면**에 남기는 안내(passwordResetMessage 가 아니라 syncMessage 로 나간다 —
    /// 성공하면 재설정 화면은 사라지고 그 화면의 문구는 함께 청소되기 때문이다).
    /// 자동 로그인을 하지 않으므로 사용자에게 "이제 뭘 해야 하는지"를 이 한 줄이 말해 줘야 한다.
    static let passwordResetChangedSignInMessage = "비밀번호를 바꿨어요 · 새 비밀번호로 로그인해주세요"

    // MARK: 입력 정규화·사전 검증

    /// 재설정 경로가 쓰는 이메일 정규화. **발송과 검증이 같은 문자열을 써야** GoTrue 가 같은 사용자로 본다 —
    /// 코드 화면에서 사용자가 주소를 다시 타이핑하지 않게 하려면 앱이 한 번 접어 두는 편이 확실하다.
    nonisolated static func normalizedResetEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 이메일 형식의 **최소** 검증. 최종 판정자는 서버이고, 이건 "@ 도 없는 입력"으로 왕복(과 60초 쿨다운)을
    /// 태우지 않기 위한 사전 필터다. 정규식으로 RFC 를 흉내 내지 않는다 — 그 흉내가 정상 주소를 막는 쪽으로
    /// 틀리면 사용자는 앱 안에서 영영 비밀번호를 못 바꾼다(지금 고치려는 상황과 정확히 같은 상태가 된다).
    nonisolated static func isPlausibleResetEmail(_ email: String) -> Bool {
        guard !email.contains(where: { $0.isWhitespace }) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// 코드 정규화. 메일에서 복사하면 공백·하이픈이 섞여 오므로 ASCII 숫자만 남긴다(붙여넣기를 관대하게).
    /// 비ASCII 숫자(전각 등)를 남기지 않는 이유는 서버가 그걸 같은 코드로 보지 않기 때문이다.
    nonisolated static func normalizedResetCode(_ raw: String) -> String {
        String(raw.filter { $0.isASCII && $0.isNumber })
    }

    // MARK: 진입/종료

    /// idle → enterEmail. 로그인 폼에 이미 적혀 있는 이메일을 미리 채운다(그 사람이 방금 로그인에 실패한
    /// 그 주소가 거의 항상 정답이다). 앞선 흐름의 잔재는 여기서 통째로 청소하고 시작한다.
    func beginPasswordReset(email: String) {
        clearPasswordResetState()
        passwordResetEmail = Self.normalizedResetEmail(email)
        passwordResetPhase = .enterEmail
    }

    /// 어느 단계에서든 idle 로 되돌린다(sending/submitting 중 취소 포함).
    func cancelPasswordReset() {
        clearPasswordResetState()
    }

    /// 재설정 상태 전부를 내리는 **유일한 지점**. 취소와 성공이 같은 코드를 지나게 해 두 경로가 갈리지 않게 한다
    /// (성공 뒤에만 코드·이메일·문구가 남는 식의 어긋남을 구조적으로 없앤다).
    ///
    /// 세대를 **가장 먼저** 올린다: 이 줄 이후 도착하는 응답은 전부 '이미 닫힌 흐름의 것'이 되어 상태를 못 쓴다.
    /// 그다음 Task 를 취소해 날아가 있는 URLSession 요청 자체를 끊는다(세대만으로는 요청이 끝까지 살아 서버에
    /// 헛부하를 남긴다). 이 순서가 뒤집히면 취소와 세대 증가 사이의 틈으로 응답이 들어와 상태를 되살린다.
    private func clearPasswordResetState() {
        passwordResetGeneration &+= 1
        passwordResetTask?.cancel()
        passwordResetTask = nil
        passwordResetCooldownTask?.cancel()
        passwordResetCooldownTask = nil
        passwordResetPhase = .idle
        passwordResetMessage = nil
        passwordResetEmail = ""
        passwordResetResendSeconds = 0
        // 발송 차수도 되돌린다. 남겨 두면 다음에 연 재설정 화면의 **첫 발송**이 앞 흐름의 차수를 물려받아
        // 60초로 잠겨, "맨 처음엔 5초"라는 계약이 두 번째 흐름부터 조용히 깨진다.
        passwordResetSendCount = 0
        // 검증까지 끝난 세션도 반드시 버린다 — 남기면 다음 사람이 연 재설정 화면이 앞 사람의 계정 토큰으로
        // 비밀번호를 바꾼다(같은 맥을 여럿이 쓰는 상황에서 실제로 성립하는 경로다).
        passwordResetVerifiedSession = nil
    }

    // MARK: 코드 발송

    /// enterEmail → sending → enterCode. 형식 검증과 쿨다운은 **왕복 전에** 건다.
    func requestPasswordResetCode(email: String) async {
        let normalized = Self.normalizedResetEmail(email)
        guard Self.isPlausibleResetEmail(normalized) else {
            passwordResetEmail = normalized
            passwordResetMessage = Self.passwordResetInvalidEmailMessage
            // idle 에서 직접 불린 경우에도 사용자가 문구를 볼 화면이 있어야 한다.
            if passwordResetPhase != .enterCode { passwordResetPhase = .enterEmail }
            return
        }
        // 쿨다운 중이면 서버가 어차피 429 다. 헛왕복은 서버의 카운터만 더 밀어 대기를 늘린다.
        guard passwordResetResendSeconds <= 0 else {
            passwordResetMessage = Self.passwordResetCooldownMessage
            return
        }
        passwordResetEmail = normalized
        passwordResetMessage = nil
        passwordResetPhase = .sending
        // 새 왕복은 앞선 왕복을 무효화한다(연타·재입력이 겹쳐도 마지막 것만 상태를 쓴다).
        passwordResetGeneration &+= 1
        let generation = passwordResetGeneration
        passwordResetTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRequestPasswordResetCode(email: normalized, generation: generation)
        }
        passwordResetTask = task
        await task.value
        if passwordResetTask == task { passwordResetTask = nil }
    }

    private func performRequestPasswordResetCode(email: String, generation: Int) async {
        do {
            try await service.sendPasswordResetCode(email: email)
            guard generation == passwordResetGeneration else { return }
            passwordResetPhase = .enterCode
            passwordResetMessage = Self.passwordResetSentMessage
            startPasswordResetCooldown(seconds: consumeResendCooldownSeconds())
        } catch {
            guard generation == passwordResetGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            if let serverSeconds = passwordResetRateLimitSeconds(for: error) {
                // 429 = "방금 이미 보냈다". 코드는 이미 메일함으로 가는 중이므로 입력 화면으로 넘긴다 —
                // 이메일 화면에 붙잡아 두면 **받은 코드를 넣을 자리가 없어** 사용자가 그 시간을 헛되이 기다린다.
                passwordResetPhase = .enterCode
                passwordResetMessage = Self.passwordResetAlreadySentMessage
                // 차수는 여기서도 올린다(이 시도도 '한 번 눌렀다'이므로 다음 잠금은 재전송분 60초다).
                // 다만 **남은 초는 서버가 진실이다** — 서버의 최소 간격 설정이 우리 5초보다 길면(지금 60초)
                // 우리 값을 그대로 쓰는 순간 사용자는 열린 버튼을 눌러 429 만 한 번 더 맞는다.
                consumeResendCooldownSeconds()
                startPasswordResetCooldown(seconds: serverSeconds)
                return
            }
            passwordResetPhase = .enterEmail
            passwordResetMessage = passwordResetSendFailureMessage(for: error)
        }
    }

    /// 방금 끝난 발송 뒤에 걸 쿨다운(초)을 정하고 발송 차수를 한 칸 올린다.
    /// 차수를 **여기 한 곳에서만** 올려, "5초냐 60초냐"의 판정과 카운트가 갈릴 여지를 없앤다.
    @discardableResult
    private func consumeResendCooldownSeconds() -> Int {
        let seconds = passwordResetSendCount == 0
            ? Self.passwordResetFirstResendDelaySeconds
            : Self.passwordResetResendCooldownSeconds
        passwordResetSendCount += 1
        return seconds
    }

    /// 재발송 카운트다운을 건다. 남은 초는 **주입 clock 기준 데드라인에서 매번 다시 계산**한다 —
    /// 1초씩 빼기만 하면 잠자기·스케줄 지연이 그대로 누적 오차가 되어 버튼이 실제보다 늦게(또는 일찍) 풀린다.
    /// 대기는 주입 가능한 passwordResetSleep 이라 테스트가 60초를 실제로 자지 않는다.
    func startPasswordResetCooldown(seconds: Int) {
        let seconds = min(max(seconds, 1), 600)
        passwordResetCooldownTask?.cancel()
        passwordResetResendSeconds = seconds
        let deadline = clock().addingTimeInterval(TimeInterval(seconds))
        // 세대를 캡처하지 않는다 — 카운트다운을 멈추는 길은 이 Task 의 취소뿐이다(위 cancel + clearPasswordResetState).
        passwordResetCooldownTask = runResendCountdown(
            deadline: deadline,
            apply: { [weak self] remaining in
                guard let self, self.passwordResetResendSeconds != remaining else { return }
                self.passwordResetResendSeconds = remaining
            }
        )
    }

    /// 재발송 카운트다운 루프 **본체**(비밀번호 재설정 · 가입 확인 공용). 남은 초는 주입 clock 기준 데드라인에서 매 틱
    /// 다시 계산하고, 대기는 주입 passwordResetSleep 이다 — 두 흐름이 같은 시계·같은 수면을 쓰므로 테스트의 얼린 시계가
    /// 양쪽에 그대로 통한다.
    /// 값 대입은 호출자의 `apply` 가 한다(같은 값이면 대입하지 않는 == 가드도 호출자 몫 — 관찰 무효화를 아끼는 기존 규약).
    ///
    /// ★ **끊는 것은 Task 취소뿐이다 — 세대(generation)를 보지 않는다.** 예전엔 호출자가 캡처한 세대를 매 틱 확인했고,
    /// 그 때문에 코드를 한 번 틀리면 [다시 받기]가 **영영 안 풀렸다**: 검증·재전송은 '늦게 온 응답을 버리려고' 왕복마다
    /// 세대를 올리는데, 카운트다운은 그 신호를 '멈추라'로 읽고 남은 초를 0 으로 내리지 못한 채 빠져나갔다(회색 "다시 받기
    /// (47초)" 가 굳고 탈출구는 "로그인으로 돌아가기"뿐인데 화면이 그걸 말해 주지 않는다).
    /// 두 장치는 뜻이 다르다 — 세대는 **응답 폐기**, Task 취소는 **중단**이다. 카운트다운을 실제로 멈춰야 하는 자리
    /// (흐름 청소 clear*State · 새 쿨다운 시작 start*Cooldown)는 전부 이 Task 를 직접 취소하므로 이것으로 충분하다.
    func runResendCountdown(
        deadline: Date,
        apply: @escaping @MainActor (Int) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = Int(ceil(deadline.timeIntervalSince(self.clock())))
                guard remaining > 0 else {
                    apply(0)
                    return
                }
                apply(remaining)
                let sleep = self.passwordResetSleep
                await sleep(1)
            }
        }
    }

    // MARK: 코드 검증(1단계)

    /// enterCode → verifying → (성공) enterNewPassword. 코드 6자리는 **왕복 전에** 거른다.
    ///
    /// 이 단계는 비밀번호를 아직 모른다 — 하는 일은 "코드가 맞나"뿐이고, 성공하면 그 대가로 받은 recovery
    /// 세션을 손에 쥐고 다음 화면으로 넘긴다. 실패하면 enterCode 에 그대로 머문다([다시 받기]가 그 화면에 있다).
    func verifyPasswordResetCode(code: String) async {
        let normalizedCode = Self.normalizedResetCode(code)
        guard normalizedCode.count == Self.passwordResetCodeLength else {
            passwordResetMessage = Self.passwordResetInvalidCodeMessage
            return
        }
        guard !passwordResetEmail.isEmpty else {
            // 어느 주소로 보냈는지 모르면 검증할 수 없다(발송 화면부터 다시).
            passwordResetPhase = .enterEmail
            passwordResetMessage = Self.passwordResetInvalidEmailMessage
            return
        }
        // 이미 검증을 통과해 세션을 쥐고 있으면 **왕복하지 않고** 곧장 다음 화면으로 넘긴다.
        // OTP 는 1회용이라 같은 코드를 서버에 다시 보내면 반드시 튕기고, 그러면 사용자는 멀쩡한 코드를
        // 버린 채 재발송 쿨다운에 갇힌다(비밀번호 화면에서 뒤로 돌아왔다가 다시 진행하는 동선이 정확히 이것).
        if passwordResetVerifiedSession != nil {
            passwordResetMessage = nil
            passwordResetPhase = .enterNewPassword
            return
        }
        passwordResetMessage = nil
        passwordResetPhase = .verifying
        passwordResetGeneration &+= 1
        let generation = passwordResetGeneration
        passwordResetTask?.cancel()
        let email = passwordResetEmail
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performVerifyPasswordResetCode(email: email, code: normalizedCode, generation: generation)
        }
        passwordResetTask = task
        await task.value
        if passwordResetTask == task { passwordResetTask = nil }
    }

    private func performVerifyPasswordResetCode(email: String, code: String, generation: Int) async {
        do {
            let verified = try await service.verifyPasswordResetCode(email: email, code: code)
            guard generation == passwordResetGeneration else { return }
            // 세션은 **여기서만** 보관하고 절대 영속하지 않는다(persistSession 을 태우지 않는다).
            passwordResetVerifiedSession = verified
            passwordResetPhase = .enterNewPassword
            passwordResetMessage = nil
        } catch {
            guard generation == passwordResetGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            passwordResetPhase = .enterCode
            passwordResetMessage = passwordResetVerifyFailureMessage(for: error)
        }
    }

    // MARK: 새 비밀번호 설정(2단계)

    /// enterNewPassword → submitting → (성공) idle + 로그인 화면. 비밀번호 길이는 **왕복 전에** 거른다.
    func submitNewPassword(_ newPassword: String) async {
        // 길이는 그래핌으로 센다. 서버(코드포인트)보다 **엄격한 쪽**이라 여기 통과한 값을 서버가 길이로
        // 거절하는 일은 없다(반대 방향으로 조금 보수적인 것은 안전하다).
        guard newPassword.count >= Self.passwordResetMinPasswordLength else {
            passwordResetMessage = Self.passwordResetShortPasswordMessage
            return
        }
        // 손에 쥔 recovery 세션이 이 단계의 전부다. 없으면 바꿀 수단 자체가 없으므로 코드 화면으로 되돌린다.
        guard let verified = passwordResetVerifiedSession else {
            passwordResetPhase = .enterCode
            passwordResetMessage = Self.passwordResetCodeRejectedMessage
            return
        }
        passwordResetMessage = nil
        passwordResetPhase = .submitting
        passwordResetGeneration &+= 1
        let generation = passwordResetGeneration
        passwordResetTask?.cancel()
        let email = passwordResetEmail
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSubmitNewPassword(
                email: email,
                verified: verified,
                newPassword: newPassword,
                generation: generation
            )
        }
        passwordResetTask = task
        await task.value
        if passwordResetTask == task { passwordResetTask = nil }
    }

    private func performSubmitNewPassword(
        email: String,
        verified: SupabaseSession,
        newPassword: String,
        generation: Int
    ) async {
        do {
            try await service.updatePassword(accessToken: verified.accessToken, newPassword: newPassword)
        } catch {
            guard generation == passwordResetGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            // 붙잡아 둔 세션까지 죽었으면 그 세션으로는 두 번 다시 못 바꾼다 — 버려서 재시도가 코드 검증부터
            // 다시 타게 한다(남겨 두면 같은 실패만 무한 반복한다).
            if let serviceError = error as? SupabaseWorkServiceError,
               serviceError == .sessionExpired || serviceError == .otpInvalidOrExpired {
                passwordResetVerifiedSession = nil
                passwordResetPhase = .enterCode
                passwordResetMessage = passwordResetUpdateFailureMessage(for: error)
                return
            }
            // 그 밖의 거절(6자 미만·이전과 동일·일시 네트워크)은 **비밀번호만** 다시 받으면 되는 일이다.
            // 화면도 세션도 그대로 두어 사용자가 값만 고쳐 곧장 다시 누를 수 있게 한다 — 여기서 세션을 버리면
            // 1회용 OTP 가 날아가 "조건에 안 맞는 비밀번호를 한 번 골랐다"는 이유로 코드부터 다시 받아야 한다.
            passwordResetPhase = .enterNewPassword
            passwordResetMessage = passwordResetUpdateFailureMessage(for: error)
            return
        }
        guard generation == passwordResetGeneration else { return }

        // 새 비밀번호가 섰다. **여기서 로그인시키지 않는다**(completeSignIn 을 부르지 않는다):
        // 재설정은 로그인이 아니라 비밀번호 교체이고, 사장님 요청대로 사용자가 새 비밀번호로 직접 로그인해
        // "정말 바뀌었다"를 스스로 확인해야 한다. 부수 효과로 recovery 세션이 디스크(persistSession)에 남지
        // 않으므로, 다음 실행이 그 토큰으로 되살아나는 경로도 함께 사라진다.
        //
        // 폴링·하트비트·팀 확정은 전부 completeSignIn 안에서만 시작된다 — 그것을 부르지 않는 이 경로에서는
        // 애초에 시작되지 않는다(= 로그아웃인데 백그라운드만 도는 유령 상태가 성립할 수 없다).
        //
        // 청소 전에 핸들을 **반드시 먼저 뗀다**: clearPasswordResetState 의 일은 날아가 있는 왕복을 끊는 것인데,
        // 여기서 그 '날아가 있는 왕복'은 **지금 실행 중인 이 Task 자신**이다. 떼지 않으면 스스로를 취소한다.
        passwordResetTask = nil
        // 보관 세션은 이 안에서 버려진다(clearPasswordResetState → passwordResetVerifiedSession = nil).
        clearPasswordResetState()
        // 로그인 폼을 방금 바꾼 계정으로 채워 둔다 — 주소를 다시 타이핑시키지 않는다.
        self.email = email
        // 비밀번호 칸은 비운다. 여기 남아 있는 값은 방금 **바뀌기 전** 비밀번호(로그인에 실패해서 이 흐름에
        // 들어왔다)라, 그대로 두면 사용자가 그걸로 로그인 버튼을 눌러 또 실패한다.
        self.password = ""
        // 재설정 화면은 사라지므로 안내는 로그인 화면의 상태줄(syncMessage)로 옮겨 싣는다.
        syncMessage = Self.passwordResetChangedSignInMessage
    }

    // MARK: 오류 → 한국어 문구

    /// 키 부재/스키마처럼 **사용자가 아니라 설치가 잘못된** 경우. 재설정 문맥에서도 뜻이 같으므로 기존 문구를 쓴다.
    private func passwordResetConfigMessage(for error: Error) -> String? {
        guard let serviceError = error as? SupabaseWorkServiceError else { return nil }
        switch serviceError {
        case .missingAnonKey, .invalidAPIKey, .databaseSchemaMissing:
            return authMessage(for: serviceError, fallback: Self.passwordResetSendFailedMessage)
        default:
            return nil
        }
    }

    /// 레이트리밋이면 **걸어야 할 쿨다운 초**, 아니면 nil.
    ///
    /// 서버가 남은 초를 말해 주면(`over_email_send_rate_limit` 본문의 "…after N seconds") 그 값을 그대로 쓰고,
    /// 말해 주지 않으면(`over_request_rate_limit` 처럼 초가 아예 없는 본문) 기본 60초로 떨어진다.
    /// nil 을 0초로 취급하면 안 된다 — 버튼이 곧바로 열려 사용자가 429 를 한 번 더 맞는다.
    func passwordResetRateLimitSeconds(for error: Error) -> Int? {
        guard case .rateLimited(let retryAfterSeconds) = error as? SupabaseWorkServiceError else { return nil }
        return retryAfterSeconds ?? Self.passwordResetResendCooldownSeconds
    }

    /// 발송 실패 문구. private 이 아닌 이유: 가입 확인의 재전송(WorkTimerStoreSignUpOTP.swift)이 같은 문장을 쓴다 —
    /// 메일이 안 나간 이유(설정·네트워크·그 밖)는 두 흐름에서 같고, 문구를 두 벌로 두면 한쪽만 낡는다.
    func passwordResetSendFailureMessage(for error: Error) -> String {
        if let config = passwordResetConfigMessage(for: error) { return config }
        if classifyAuthError(error) == .transient { return Self.passwordResetNetworkMessage }
        return Self.passwordResetSendFailedMessage
    }

    /// 검증 실패 문구. **만료와 불일치를 가르지 않는다** — GoTrue 는 계정/코드 존재를 흘리지 않으려고 둘 다
    /// 같은 403(otp_expired, "Token has expired or is invalid")으로 주므로 가르는 것이 애초에 불가능하고,
    /// 어느 쪽이든 **사용자가 할 일은 '다시 받기'로 같다**. recovery 토큰이 죽은 경우(.sessionExpired)도 같은 결론이다.
    func passwordResetVerifyFailureMessage(for error: Error) -> String {
        if let config = passwordResetConfigMessage(for: error) { return config }
        // 레이트리밋 판정이 transient 보다 앞이다 — classifyAuthError 는 429 를 transient 로 보기 때문이다.
        if passwordResetRateLimitSeconds(for: error) != nil { return Self.passwordResetCooldownMessage }
        if classifyAuthError(error) == .transient { return Self.passwordResetNetworkMessage }
        return Self.passwordResetCodeRejectedMessage
    }

    func passwordResetUpdateFailureMessage(for error: Error) -> String {
        if let config = passwordResetConfigMessage(for: error) { return config }
        if passwordResetRateLimitSeconds(for: error) != nil { return Self.passwordResetCooldownMessage }
        if classifyAuthError(error) == .transient { return Self.passwordResetNetworkMessage }
        guard let serviceError = error as? SupabaseWorkServiceError else {
            return Self.passwordResetUpdateFailedMessage
        }
        switch serviceError {
        // .weakPassword 로도, .samePasswordReuse 로도 올 수 있다. 공용 매핑이 "password" 를 담은 모든 메시지를
        // .weakPassword 로 뭉개기 때문에 지금은 사실상 전자로만 오지만(SupabaseWorkModels 의 근거 주석 참조),
        // 어느 쪽이든 사용자가 할 일은 하나다 — 그래서 문구가 두 사유를 함께 말한다.
        case .weakPassword, .samePasswordReuse:
            return Self.passwordResetRejectedPasswordMessage
        // recovery 토큰이 죽었다(만료/bad_jwt). 이 세션으로는 두 번 다시 못 바꾸므로 코드부터 다시 받아야 한다.
        case .sessionExpired, .otpInvalidOrExpired:
            return Self.passwordResetCodeRejectedMessage
        default:
            return Self.passwordResetUpdateFailedMessage
        }
    }
}

/// 착용 캐릭터 서버 동기화의 스토어 곁 상태(v0.3.30). `WorkTimerStore.characterSync` 가 스토어마다 하나 붙인다.
/// 화면이 읽는 값이 없다 — 관찰 대상이 아니다.
@MainActor
final class CharacterSyncState {
    /// 팝오버 열기 스로틀. 팀 메타·오목 받은 신청과 같은 60초다(무료 플랜 — 여닫이마다 GET 을 내지 않는다).
    static let popoverThrottleSeconds: TimeInterval = 60

    /// 연관 객체 키. 주소만 쓰고 값은 안 읽는다.
    nonisolated(unsafe) static var associationKey: UInt8 = 0

    /// 마지막 조회를 **발사한** 시각(성공 여부 무관 — 실패한 서버를 여닫이마다 두드리지 않게).
    var lastFetchAt: Date = .distantPast
    /// 떠 있는 조회의 표. nil 이면 안 떠 있다.
    var fetchingToken: Int?
    var tokenSeed = 0
    /// 마지막으로 띄운 조회 Task(테스트가 완료를 기다린다).
    var lastTask: Task<Void, Never>?

    /// 이 맥의 로컬 쓰기(사용자 고르기·밀기 시작/끝) 세대. 조회는 발사 때 이 값을 붙잡고, 응답 때 달라졌으면 버린다.
    private(set) var localWriteRevision = 0
    /// 떠 있는 `set_character` 수.
    private(set) var pushesInFlight = 0

    /// 되그릴 쪽에 알리는 통로. 앱은 `.shared`, **테스트는 자기 인스턴스**(전역을 흔들면 병렬 스위트가 빨개진다).
    var broadcast: CharacterSelectionBroadcast = .shared

    func noteLocalWrite() { localWriteRevision &+= 1 }

    func beginPush() {
        pushesInFlight += 1
        localWriteRevision &+= 1
    }

    func endPush() {
        pushesInFlight -= 1
        localWriteRevision &+= 1
    }
}
