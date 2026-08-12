import Foundation

// 콕찌르기 + 토큰 사용량 공개 설정의 스토어 계층.
// 서버 계약:
//  - poke_user(p_to uuid) RPC: 보낸이·대상 모두 근무중(열린 세션) 필수, 같은 대상 60초 쿨타임. 응답 {status, retry_after_seconds?}.
//  - take_pokes() RPC: 내 미소비 찔림을 원자적으로 소비하며 반환(보낸이 표시명 포함).
//  - app_user_directory() RPC: 앱 사용자 전체(본인 제외) + is_working(열린 세션 존재).
//  - profiles.token_usage_public: 본인 행 select/update(RLS). token_usage_board 는 비공개 유저를 타인에게 숨긴다(본인 행은 유지).
@MainActor
extension WorkTimerStore {
    /// 수신 찔림 폴링 주기(초). 타이머 자체는 로그인 중 상시 돌지만, 실제 take_pokes 는 근무중에만 나간다
    /// (O1 — takePokesIfWorking). 전달 지연 상한이자 서버 부하 트레이드오프.
    static let pokePollIntervalSeconds: Double = 15
    /// 이 시간(초)보다 오래된 찔림은 수신해도 표시하지 않는다(서버에선 소비됨) — 새벽 찔림이 아침에 뜨는 어색함 방지.
    /// nonisolated 순수 함수 freshReceivedPokes 가 참조하므로 불변 상수를 nonisolated 로 노출한다.
    nonisolated static let pokeDisplayFreshnessSeconds: TimeInterval = 3600
    /// 찌르기 쿨타임(초). 서버가 강제하고 클라는 표시용 카운트다운만 미러링한다.
    static let pokeCooldownSeconds: TimeInterval = 60
    /// 울트라 하루 한도(보낸 사람 기준·대상 무관·KST 자정 리셋). 서버 ultra_poke_user 의 ultra_poke_daily_limit 과
    /// **같은 값이어야 한다** — 어긋나면 클라가 "1번 남음"이라 말한 뒤 서버가 거절하는 무언의 모순이 된다.
    /// 한도를 바꿀 땐 서버 상수와 이 한 줄만 고치면 된다(안내 문구·게이트가 전부 여기서 파생된다).
    nonisolated static let ultraPokeDailyLimit = 2
    /// 울트라 표시 신선도(초). 일반 찔림의 1시간(pokeDisplayFreshnessSeconds)과 **일부러 다르다** —
    /// 울트라는 화면 전체를 5초간 덮으므로, 맥이 잠들었다 깨어난 뒤 40분 전 울트라가 갑자기 터지면
    /// 그건 알림이 아니라 습격이다. 정상 전달 지연 상한은 폴링 주기(15초)라 120초면 재시도·네트워크
    /// 흔들림까지 덮는다.
    nonisolated static let ultraDisplayFreshnessSeconds: TimeInterval = 120
    /// 하루 한도 소진 안내. 문장을 한도 상수에서 만들어, 상수만 바꾸면 문구가 저절로 따라오게 한다.
    nonisolated static let ultraSpentNotice = "울트라 찌르기는 하루에 \(WorkTimerStore.ultraPokeDailyLimit)번까지예요"
    /// 대상이 집중 모드일 때의 안내. 몫도 쿨타임도 소모되지 않았다는 사실까지 말해 준다 —
    /// 안 그러면 사용자는 "한 번 날린 건가?" 하고 남은 횟수를 잘못 센다.
    nonisolated static let targetFocusedNotice = "지금 집중 중이에요. 나중에 찔러 주세요"

    /// 남은 횟수 안내 문구. **모르면 nil** 이고, 그때 화면은 아무 숫자도 말하지 않는다 —
    /// 남은 횟수는 울트라 응답으로만 알 수 있어서 '아직 모름' 구간이 정상적으로 존재하고,
    /// 틀린 숫자를 보여주느니 침묵하는 편이 낫기 때문이다(그래서 이걸 알자고 새 GET 을 만들지 않는다).
    /// 순수 함수라 UI 는 이 함수만 쓰고 자기 문장을 만들지 않는다(문구가 두 곳으로 갈라지지 않게).
    nonisolated static func ultraRemainingText(remaining: Int?) -> String? {
        guard let remaining, remaining >= 0 else { return nil }
        return remaining == 0 ? "오늘 몫은 다 썼어요" : "오늘 \(remaining)번 남음"
    }

    /// 울트라 발사 직후 안내. 남은 횟수를 아는 경우에만 뒤에 덧붙인다.
    nonisolated static func ultraSentNotice(remaining: Int?) -> String {
        guard let tail = ultraRemainingText(remaining: remaining) else { return "울트라 찌르기 발사!" }
        return "울트라 찌르기 발사! " + tail
    }

    /// 콕찌르기 패널 열림/refresh 루프에서 부르는 디렉토리 로드 래퍼(Task 발사).
    func loadPokeDirectory() {
        Task { @MainActor in await performLoadPokeDirectory() }
    }

    /// refresh 루프 전용 — 패널이 노출 중일 때만 재조회.
    func refreshPokeDirectoryIfVisible() async {
        guard isPokePanelVisible else { return }
        await performLoadPokeDirectory()
    }

    /// app_user_directory RPC 로 앱 사용자 전체(본인 제외)를 받아 근무중 먼저·이름순으로 반영한다.
    /// 서버 정렬은 신뢰하지 않고 클라가 다시 정렬한다. 성공하면 pokeDirectoryLoaded 를 세워 '아직 아무도 없음'과
    /// 로드 전/실패를 구분한다. 아울러 만료된 쿨타임 엔트리를 정리한다(딕셔너리 무한 성장 방지). 실패는 조용히.
    func performLoadPokeDirectory() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        do {
            let rows = try await withSessionRetry { activeSession in
                try await service.fetchPokeDirectory(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            let entries = rows.toPokeDirectoryEntries().sortedForPokeDisplay()
            if pokeDirectory != entries { pokeDirectory = entries }
            if !pokeDirectoryLoaded { pokeDirectoryLoaded = true }
            // 지난 쿨타임 엔트리 정리(만료분 제거). displayNow 가 아니라 지금 시각 기준으로 판정한다.
            let now = Date()
            pokeCooldownUntil = pokeCooldownUntil.filter { $0.value > now }
        } catch {
            // 취소는 조용히. 그 외 실패도 문구를 흔들지 않고 다음 주기/재오픈에서 재시도한다.
            if case .cancelled = classifyAuthError(error) { return }
        }
    }

    /// 대상에게 콕 찌르기. 성공/서버 쿨다운 응답으로 pokeCooldownUntil 갱신, 실패 사유는 pokeNotice 반영.
    func sendPoke(to userID: String) {
        guard session != nil else { return }
        // 클라 선게이트: 근무중이 아니면 요청을 발사하지 않고 안내만 남긴다(서버도 이중 강제).
        guard startedAt != nil else {
            pokeNotice = "근무 중일 때만 콕 찌를 수 있어요"
            return
        }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                let response = try await withSessionRetry { activeSession in
                    try await service.sendPoke(accessToken: activeSession.accessToken, to: userID)
                }
                guard generation == sessionGeneration else { return }
                switch PokeSendOutcome(response: response) {
                case .ok:
                    pokeCooldownUntil[userID] = Date().addingTimeInterval(Self.pokeCooldownSeconds)
                    pokeNotice = nil
                case .cooldown(let retryAfterSeconds):
                    pokeCooldownUntil[userID] = Date().addingTimeInterval(TimeInterval(retryAfterSeconds))
                case .ultraUsedToday:
                    // poke_user 는 이 status 를 절대 내지 않는다(두 RPC 가 status 어휘만 공유한다).
                    // 컴파일 망라를 위한 도달 불가 분기 — 그래도 무음으로 삼키지는 않는다.
                    pokeNotice = Self.ultraSpentNotice
                case .notWorking:
                    pokeNotice = "근무 중일 때만 콕 찌를 수 있어요"
                case .targetNotWorking:
                    // 대상이 자리비움 — 서버가 거부했다. 내 디렉토리의 근무중 배지가 낡았다는 뜻이라
                    // 즉시 재조회해 자리비움으로 갱신한다(다음 시도부터 버튼도 비활성으로 선게이트됨).
                    pokeNotice = "자리비움 상태에는 찌를 수 없어요"
                    loadPokeDirectory()
                case .targetFocused:
                    pokeNotice = Self.targetFocusedNotice
                case .invalid:
                    pokeNotice = "지금은 찌를 수 없어요"
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                pokeNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
            }
        }
    }

    /// 오늘(KST) 울트라 몫을 다 썼는가. MilestoneTracker.dayKey 와 같은 눈금(Asia/Seoul yyyyMMdd)을 써
    /// 자정 롤오버가 리그·마일스톤과 어긋나지 않게 한다. 비교로 판정하므로 날이 바뀌면 저절로 풀린다.
    func isUltraPokeSpent(now: Date) -> Bool { ultraPokeSpentDay == MilestoneTracker.dayKey(now) }

    /// 오늘 남은 울트라 횟수(모르면 nil). 스탬프가 오늘이 아니면 어제 값이라 **모름으로 답한다** —
    /// 이 비교가 없으면 자정을 넘긴 뒤에도 어제의 "0번 남음"이 화면에 남는다.
    func ultraRemaining(now: Date) -> Int? {
        guard ultraRemainingDay == MilestoneTracker.dayKey(now) else { return nil }
        return ultraRemainingToday
    }

    /// 날이 바뀌었으면 어제의 남은 횟수를 '모름'으로 되돌린다(다음 울트라 응답이 진실을 채운다).
    /// 남은 횟수를 알자고 새 요청을 만들지 않기로 했으므로, 로컬이 할 수 있는 정직한 일은 '버리는 것'뿐이다.
    func refreshUltraQuota(now: Date) {
        guard ultraRemainingDay != MilestoneTracker.dayKey(now) else { return }
        if ultraRemainingToday != nil { ultraRemainingToday = nil }
        if ultraRemainingDay != nil { ultraRemainingDay = nil }
    }

    /// 오늘 몫 소진 미러를 세운다(@Observable 동등성 가드 — 같은 값 재대입도 관찰자를 발화시킨다).
    func markUltraSpent(now: Date) {
        let key = MilestoneTracker.dayKey(now)
        if ultraPokeSpentDay != key { ultraPokeSpentDay = key }
    }

    /// 서버가 실어 준 남은 횟수를 반영한다. **값이 없으면 '모름'(nil)으로 되돌린다** — 직전 숫자를 남기면
    /// 방금 한 발 썼는데도 옛 숫자를 계속 보여준다(마이그레이션 전 서버는 이 필드를 아예 안 보낸다).
    /// 0 이면 오늘 몫 소진이므로 소진 미러도 함께 세운다 — 그래야 다음 시도가 요청 없이 막힌다.
    func applyUltraRemaining(_ value: Int?, now: Date) {
        // 음수는 서버 버그이거나 미래 규약이다. 숫자로 말할 수 없는 값이므로 0 으로 접는다.
        let normalized = value.map { max(0, $0) }
        if ultraRemainingToday != normalized { ultraRemainingToday = normalized }
        let stamp = normalized == nil ? nil : MilestoneTracker.dayKey(now)
        if ultraRemainingDay != stamp { ultraRemainingDay = stamp }
        if normalized == 0 { markUltraSpent(now: now) }
    }

    /// 울트라 찌르기. 일반 sendPoke 와 게이트는 같고(근무중 선게이트) 하루 한도 로컬 미러가 하나 더 붙는다.
    /// 서버 게이트 순서는 invalid → 보낸이근무 → 대상근무 → 하루한도 → 쿨타임이고, 여기 매핑도 그 어휘를 따른다.
    func sendUltraPoke(to userID: String) {
        guard session != nil else { return }
        guard startedAt != nil else {
            pokeNotice = "근무 중일 때만 콕 찌를 수 있어요"
            return
        }
        let sentAt = clock()
        // 날이 바뀌었으면 어제의 남은 횟수부터 버린다 — 안 버리면 어제 "0번 남음"이 오늘 안내로 샌다.
        refreshUltraQuota(now: sentAt)
        // 이 맥이 이미 오늘 몫을 다 쓴 걸 알면 요청 자체를 안 낸다. 다른 맥에서 썼다면 미러가 비어 있으므로
        // 서버가 ultra_used_today 로 가르쳐 주고, 그때 미러를 채워 다음 시도부터 막는다.
        if isUltraPokeSpent(now: sentAt) {
            pokeNotice = Self.ultraSpentNotice
            return
        }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                let response = try await withSessionRetry { activeSession in
                    try await service.sendUltraPoke(accessToken: activeSession.accessToken, to: userID)
                }
                guard generation == sessionGeneration else { return }
                let now = clock()
                switch PokeSendOutcome(response: response) {
                case .ok:
                    // 울트라도 pokes 행을 남기므로 서버의 같은-대상 60초 쿨타임이 함께 시작된다.
                    // 여기서 미러를 안 맞추면 버튼이 활성인 채로 남아 다음 탭이 확정 cooldown 을 받는다.
                    //
                    // withSessionRetry 가 토큰 갱신으로 이 RPC 를 재발사한 경우, 서버엔 이미 행이 있어
                    // 두 번째 응답이 하루 한도를 하나 더 깎은 값으로 온다 — 남은 횟수는 서버 값이 진실이므로
                    // 그대로 반영한다(로컬 추측으로 덮지 않는다).
                    pokeCooldownUntil[userID] = Date().addingTimeInterval(Self.pokeCooldownSeconds)
                    applyUltraRemaining(response.ultraRemainingForDisplay, now: now)
                    pokeNotice = Self.ultraSentNotice(remaining: ultraRemaining(now: now))
                case .ultraUsedToday:
                    // status 자체가 '오늘 몫 없음'의 권위다 — 서버가 남은 횟수를 안 실어 줘도(구버전) 0 으로 본다.
                    applyUltraRemaining(response.ultraRemainingForDisplay ?? 0, now: now)
                    markUltraSpent(now: now)
                    pokeNotice = Self.ultraSpentNotice
                case .cooldown(let retryAfterSeconds):
                    pokeCooldownUntil[userID] = Date().addingTimeInterval(TimeInterval(retryAfterSeconds))
                    // 3초를 꾹 눌러 링을 다 채운 뒤 아무 문구도 안 뜨면, 버튼이 쿨타임으로 흐려지는 것과
                    // 겹쳐 사용자는 '울트라가 나갔다'고 읽는다. 실제로는 안 나갔고 오늘 몫도 그대로다 —
                    // 그 두 사실을 여기서 말하지 않으면 알 방법이 화면에 없다.
                    pokeNotice = "방금 찌른 상대예요. 잠시 후 울트라를 쓸 수 있어요"
                case .notWorking:
                    pokeNotice = "근무 중일 때만 콕 찌를 수 있어요"
                case .targetNotWorking:
                    // 대상 자리비움은 몫을 태우지 않는다(서버가 행을 안 남긴다). 디렉토리 배지가 낡았다는
                    // 뜻이므로 즉시 재조회해 다음 시도부터 버튼이 선게이트되게 한다.
                    pokeNotice = "자리비움 상태에는 찌를 수 없어요"
                    loadPokeDirectory()
                case .targetFocused:
                    // 집중 모드도 몫을 태우지 않는다 — 서버가 하루 한도 검사보다 **앞에서** 거절하므로
                    // 여기서 남은 횟수를 건드리면 안 된다(멀쩡한 몫을 화면에서만 깎게 된다).
                    pokeNotice = Self.targetFocusedNotice
                case .invalid:
                    pokeNotice = "지금은 찌를 수 없어요"
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                // 마이그레이션 미적용 서버(404/PGRST202)도 여기로 떨어진다 — 울트라만 조용히 못 쓰고
                // 일반 찌르기는 그대로 산다.
                pokeNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
            }
        }
    }

    /// 표시용 쿨타임 잔여 초(0이면 찌르기 가능). displayNow 티커 기준으로 매초 줄어든다.
    func pokeCooldownRemaining(for userID: String, now: Date) -> Int {
        guard let until = pokeCooldownUntil[userID] else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    /// 수신 찔림 폴링 시작(idempotent). startStatusRefreshLoop 와 같은 지점에서 켜지고 clearPersistedSession 이 끈다.
    /// 15초마다 pokePollTick() 1회분을 돈다.
    /// 루프는 sleep 먼저·폴링 나중이다 — 시작 즉시 네트워크 콜을 내지 않아 기존 단위테스트의 요청 목록 단언이 흔들리지 않는다
    /// (앱 상시 실행이라 첫 전달 15초 지연은 무해).
    func startPokePolling() {
        guard pokePollTask == nil else { return }
        pokePollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pokePollIntervalSeconds), tolerance: .seconds(2))
                if Task.isCancelled { return }
                guard let self else { return }
                await self.pokePollTick()
            }
        }
    }

    /// 폴링 1회분 본문. sleep 과 분리해 둔 이유는 테스트다 — 게이트 순서를 실증하려면 tick 을 직접 불러야 하는데,
    /// 루프에 인라인돼 있으면 실시간 15초를 기다리거나 주기 상수를 전역 var 로 여는 수밖에 없다. 후자는
    /// 병렬로 도는 다른 스위트가 서로의 값을 덮어써 무음으로 깨진다(URLProtocolStub.delayedHosts 에서 이미 겪었다).
    /// 세션이 없으면 요청 0건으로 빠지고 루프는 다음 tick 을 계속 돈다(로그인 복구를 기다리는 것).
    func pokePollTick() async {
        guard session != nil else { return }
        // 자정을 넘겼으면 어제의 울트라 남은 횟수를 여기서 버린다(요청 0건 — 순수 로컬 판정).
        // 발사 시점에도 같은 판정을 하지만, 패널을 열어 둔 채 자정을 넘긴 사용자에게 "0번 남음"이
        // 눌러 보기 전까지 남아 있는 것을 막으려면 상시 폴링에도 붙여야 한다.
        refreshUltraQuota(now: clock())
        // 공개 설정 1회 로드는 아래 근무중 게이트보다 **앞**이다. 뒤로 내리면 근무를 한 번도 시작하지 않은 사용자가
        // 자기 token_usage_public 서버값을 영영 못 읽어, 로그인 직후의 낙관 기본값 true 가 교정되지 않는다
        // — 비공개로 꺼 둔 사람의 토큰 사용량이 다음 실행마다 공개로 되살아나 보인다.
        await loadTokenUsagePrivacyIfNeeded()
        await takePokesIfWorking()
    }

    /// 근무중일 때만 수신 찔림을 소비한다(O1). 게이트 기준을 snapshot.isWorking 이 아니라 startedAt != nil 로 잡은 이유는
    /// sendPoke 의 선게이트(:57)·서버의 '열린 세션' 조건과 같은 눈금을 써야 보내는 쪽과 받는 쪽 판정이 어긋나지 않기 때문이다.
    ///
    /// 이 가드가 없으면: 서버가 poke 생성 시점에 대상의 열린 세션을 요구하므로
    /// (supabase/migrations/20260724030000_poke_target_working.sql — target_not_working) 비근무 구간의 take_pokes 응답은
    /// 원리상 확정적으로 빈 배열인데, 로그인만 해 둔 맥이 24시간 15초마다(사용자당 하루 3,840~5,760회) 그 빈 배열을
    /// 받으러 나간다. 무료 플랜에서 이건 순수한 낭비다.
    ///
    /// 이 가드가 만드는 부작용 2개:
    ///  ① 마지막 tick 이후 근무 종료까지의 최대 15초 창에 도착한 찔림이 폴링으로는 영영 안 잡힌다 →
    ///     사용자가 직접 누른 종료 경로에서 flushPokesOnWorkEnd() 로 한 번만 꼬리를 회수한다.
    ///  ② 이 상시 폴링이 무료 플랜의 '7일 비활동 프로젝트 일시정지'를 막아 주던 부수효과가 사라진다 →
    ///     D1(실행 시 저장 세션 킥 + 상시 refresh 루프)이 그 몫을 대신 낸다. D1 없이 이것만 넣으면
    ///     로그인만 하고 근무를 안 하는 주에 프로젝트가 정지돼 팀 전원이 동기화를 잃는다.
    ///
    /// 남는 구멍: 로컬은 비근무인데 서버엔 열린 세션이 남은 구간(오프라인 종료·크래시 후 흡수 전)의 찔림은
    /// 소비되지 않는다. 그건 서버 7일 cron 이 정리한다.
    func takePokesIfWorking() async {
        guard startedAt != nil else { return }
        await drainReceivedPokes()
    }

    /// take_pokes 1회 원자 수신+소비 후 1시간 이내 신선분만 onPokesReceived 로 흘린다.
    /// 폴링 tick 과 근무 종료 꼬리 회수가 이 한 몸을 공유한다 — 소비가 원자적이라 경로가 갈라지면
    /// 한쪽이 삼킨 찔림을 다른 쪽이 다시 볼 방법이 없다.
    /// 세대 재확인이 없으면 로그아웃/재로그인 사이에 도착한 응답이 새 계정 화면에 앞 계정의 말풍선을 띄운다.
    func drainReceivedPokes() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        do {
            let rows = try await withSessionRetry { activeSession in
                try await service.takePokes(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            let batch = WorkTimerStore.freshReceivedPokes(rows: rows, now: Date())
            if !batch.isEmpty {
                onPokesReceived?(batch)
            }
        } catch {
            // 취소/일시 오류는 조용히 넘긴다(다음 tick 에 재시도).
        }
    }

    /// 근무 종료 직후 찔림 꼬리를 1회 회수하는 진입점. 근무중 게이트 때문에 마지막 tick 이후 종료까지의
    /// 최대 15초 창에 도착한 찔림이 폴링으로는 영영 안 잡히기 때문이다. 이 시점엔 stop() 이 startedAt 을 이미
    /// nil 로 내린 뒤라 takePokesIfWorking 을 거치면 가드에 막힌다 — 그래서 drainReceivedPokes 를 직접 부른다.
    ///
    /// **호출부 계약**: 사용자가 직접 누른 종료(stop)에서만 부른다.
    ///  · 자동 마감(잠자기·12시간·자리비움)에서는 부르지 않는다 — 자리에 없다는 판정이 마감 사유라 말풍선을 볼 사람이 없다.
    ///  · 앱 종료 시퀀스(applicationShouldTerminate → finishWorkBeforeQuit → stop)에서도 부르지 않는다 —
    ///    take_pokes 는 서버에서 원자 소비라 응답을 받기 전에 프로세스가 죽으면 그 찔림은 영구 소실된다
    ///    (다음 실행이 1시간 신선도 안에서 보여줄 수 있었던 것). 종료 시점 역시 볼 사람이 0이라 이득도 없다.
    ///
    /// 반환 Task 는 테스트가 완료를 기다리기 위한 것이다(호출부는 무시해도 된다 — @discardableResult).
    /// 세션이 없으면 Task 조차 만들지 않고 nil 을 돌려준다(로그아웃 후 stop 경로의 헛발사 방지).
    @discardableResult
    func flushPokesOnWorkEnd() -> Task<Void, Never>? {
        guard session != nil else { return nil }
        return Task { @MainActor [weak self] in
            await self?.drainReceivedPokes()
        }
    }

    /// take_pokes 응답 행 → 수신 찔림으로 매핑하고 신선도(1시간 이내)로 거른다. 순수 static 함수라 테스트로 고정한다.
    /// 액터 상태를 건드리지 않는 순수 함수라 nonisolated — 테스트가 동기 컨텍스트에서 직접 호출한다.
    nonisolated static func freshReceivedPokes(rows: [TakenPokeRow], now: Date) -> [ReceivedPoke] {
        rows.compactMap { row in
            let createdAt = Date(timeIntervalSince1970: TimeInterval(row.createdEpoch))
            let age = now.timeIntervalSince(createdAt)
            guard age <= pokeDisplayFreshnessSeconds else { return nil }
            var kind = PokeKind(rawServerValue: row.kind)
            // 늦게 도착한 울트라는 전체화면 격발을 포기하고 평범한 움찔로 **강등**한다(버리지 않는다) —
            // 보낸 사람이 하루 몇 번뿐인 몫을 이미 태웠으므로 최소한 누가 찔렀는지는 전해야 한다.
            if kind == .ultra, age > ultraDisplayFreshnessSeconds { kind = .normal }
            return ReceivedPoke(id: row.id, fromName: row.fromDisplayName, createdAt: createdAt, kind: kind)
        }
    }

    /// 로그인 후 내 토큰 사용량 공개 여부를 서버값으로 1회 로드한다(폴링 첫 유효 tick 에서 부른다).
    /// 성공 시에만 loaded 플래그를 세워, 실패하면 다음 tick 에 다시 시도할 수 있게 한다.
    func loadTokenUsagePrivacyIfNeeded() async {
        guard !tokenUsagePublicLoaded, session != nil else { return }
        let generation = sessionGeneration
        do {
            let settings = try await withSessionRetry { activeSession in
                try await service.fetchTokenUsageSettings(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration else { return }
            if tokenUsagePublic != settings.isPublic { tokenUsagePublic = settings.isPublic }
            // 수집 설정은 사용자가 앱에서 바꾸는 값이 아니라 서버가 정하는 값이라 낙관 갱신도 토글도 없다.
            // 앱 게이트는 통신 낭비를 줄이는 부수 장치일 뿐 — 실효는 서버 트리거가 낸다(구버전도 함께 막힌다).
            if tokenUsageCollect != settings.collects { tokenUsageCollect = settings.collects }
            // 집중 모드도 같은 GET 으로 받는다(요청 추가 0). 컬럼이 없는 서버에서는 false 로 와서 기존 동작이 유지된다.
            if focusMode != settings.focusMode { focusMode = settings.focusMode }
            // 별명 쿨타임 기준 시각. 실패해도 위 두 설정은 이미 반영됐다 — 쿨타임만 '아직 모름'으로 남고
            // 서버가 최종 판정한다. 컬럼이 없는 서버(마이그레이션 전)에서는 이 GET 이 400 이지만 여기서
            // try? 로 삼키므로 토큰 공개/수집 설정은 그대로 산다(요청을 하나로 합치면 그게 같이 죽는다).
            let changedAt = try? await withSessionRetry { activeSession in
                try await service.fetchDisplayNameChangedAt(
                    accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration else { return }
            if displayNameChangedAt != changedAt { displayNameChangedAt = changedAt }
            if let changedAt {
                // 해제는 KST 자정 기준이다(서버 20260812110000 과 같은 계산) — 시각 단위로 재면
                // "N월 N일부터" 안내가 그날 아침에 거짓이 된다.
                let availableAt = Self.displayNameUnlockDate(changedAt: changedAt)
                if displayNameAvailableAt != availableAt { displayNameAvailableAt = availableAt }
            }
            refreshDisplayNameLock()
            tokenUsagePublicLoaded = true
        } catch {
            // 조용히 무시한다 — loaded 는 성공 시에만 서므로 다음 폴링 tick 에 재시도된다.
        }
    }

    /// 내 토큰 사용량 공개 여부 토글(낙관 반영 → PATCH, 실패 시 원복).
    func setTokenUsagePublic(_ isPublic: Bool) {
        guard tokenUsagePublic != isPublic else { return }
        let previous = tokenUsagePublic
        tokenUsagePublic = isPublic
        // 사용자가 명시적으로 정한 값이므로 로드 완료로 간주한다(폴링 첫 tick 이 이 선택을 덮지 않게).
        tokenUsagePublicLoaded = true
        guard session != nil else { return }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.updateTokenUsagePublic(accessToken: activeSession.accessToken, userID: activeSession.userID, isPublic: isPublic)
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                // 실패 시 이전 값으로 원복한다(낙관 대입 취소).
                tokenUsagePublic = previous
            }
        }
    }

    /// 집중 모드 토글(낙관 반영 → PATCH, 실패 시 원복). 토큰 공개 토글과 같은 규약이다.
    ///
    /// 켜 두면 남이 나를 찌를 수 없다 — 판정은 **서버**가 한다(poke_user/ultra_poke_user 게이트).
    /// 그래서 구버전 앱을 쓰는 팀원도 내 집중 모드를 존중하게 되고, 클라 미러는 화면 표시용일 뿐이다.
    func setFocusMode(_ enabled: Bool) {
        guard focusMode != enabled else { return }
        let previous = focusMode
        focusMode = enabled
        guard session != nil else { return }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.updateFocusMode(
                        accessToken: activeSession.accessToken,
                        userID: activeSession.userID,
                        enabled: enabled
                    )
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                focusMode = previous
                pokeNotice = "집중 모드를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요"
            }
        }
    }

    func toggleFocusMode() {
        setFocusMode(!focusMode)
    }
}
