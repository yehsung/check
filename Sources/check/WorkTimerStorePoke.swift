import Foundation

// 콕찌르기 + 토큰 사용량 공개 설정의 스토어 계층.
// 서버 계약:
//  - poke_user(p_to uuid) RPC: 보낸이·대상 모두 근무중(열린 세션) 필수, 같은 대상 60초 쿨타임. 응답 {status, retry_after_seconds?}.
//  - take_pokes(p_message_capable) RPC: 내 미소비 찔림을 원자적으로 소비하며 반환(보낸이 표시명 포함).
//    이 앱은 **항상 true** 를 보낸다 — 기본 false 는 메시지를 모르는 구버전 클라를 위한 것이라, 빼면 우리도 못 받는다.
//  - app_user_directory() RPC: 앱 사용자 전체(본인 제외) + is_working(열린 세션 존재)
//    + 메시지 수신 가능 여부(대상의 profiles.app_build 기준 — PokeDirectoryEntry.canReceiveMessage).
//  - profiles.app_build / app_version: 이 맥이 자기 버전을 PATCH 한다(reportAppVersionIfNeeded).
//    남이 나에게 메시지를 보낼 수 있는지의 근거라 통계가 아니라 수신 스위치다.
//  - profiles.token_usage_public: 본인 행 select/update(RLS). token_usage_board 는 비공개 유저를 타인에게 숨긴다(본인 행은 유지).
@MainActor
extension WorkTimerStore {
    /// 수신 찔림 폴링 주기(초) — 리얼타임 **미구독**(킬스위치·연결 중·재연결·끊김) 상태의 값. 타이머 자체는
    /// 로그인 중 상시 돌지만, 실제 take_pokes 는 근무중에만 나간다(O1 — takePokesIfWorking).
    /// 전달 지연 상한이자 서버 부하 트레이드오프.
    static let pokePollIntervalSeconds: Double = 15
    /// 리얼타임 **구독 중**의 폴링 주기(초) — v0.2.38 Q8(사장님 결정). 구독 중엔 찌르기가 소켓으로 즉시 오고
    /// 폴링은 "소켓이 조용히 죽은" 극소수 케이스의 안전망일 뿐이라, 그 안전망의 지연 상한을 15→60초로 늦춘다
    /// (근무 8시간 기준 take_pokes 1,920 → 480회). 완전 제거(S4)는 2주 진단 후 별도 결정 — 그때까지
    /// 이 상수와 아래 판정 구조를 지운다거나 합치지 마라.
    static let pokePollIntervalSecondsWhileSubscribed: Double = 60
    /// 이 시간(초)보다 오래된 찔림은 수신해도 표시하지 않는다(서버에선 소비됨) — 새벽 찔림이 아침에 뜨는 어색함 방지.
    /// nonisolated 순수 함수 freshReceivedPokes 가 참조하므로 불변 상수를 nonisolated 로 노출한다.
    nonisolated static let pokeDisplayFreshnessSeconds: TimeInterval = 3600
    /// 찌르기 쿨타임(초). 서버가 강제하고 클라는 표시용 카운트다운만 미러링한다.
    static let pokeCooldownSeconds: TimeInterval = 60
    /// 울트라 표시 신선도(초). 일반 찔림의 1시간(pokeDisplayFreshnessSeconds)과 **일부러 다르다** —
    /// 울트라는 화면 전체를 5초간 덮으므로, 맥이 잠들었다 깨어난 뒤 40분 전 울트라가 갑자기 터지면
    /// 그건 알림이 아니라 습격이다. 정상 전달 지연 상한은 폴링 주기(미구독 15초·구독 중 60초 — 구독 중엔
    /// 소켓이 먼저 울린다)라 120초면 재시도·네트워크 흔들림까지 덮는다.
    nonisolated static let ultraDisplayFreshnessSeconds: TimeInterval = 120
    /// 잔량이 0일 때의 안내. **하루 한도 상수에서 파생하지 않는다** — 그 상수는 이번 릴리스에 서버에서
    /// 사라졌고(재화 경제로 전환), 파생을 남겨 두면 계약 상대가 없는 문장만 코드에 남는다.
    /// 0잔량 사용자가 3초를 꾹 눌러 서버 거절을 받았을 때 **실제로 읽는 문장**이 바로 이것이다 —
    /// 그래서 "다 썼다"로 끝내지 않고 회복 방법(미션)까지 같은 줄에서 말한다.
    nonisolated static let ultraEmptyNotice = "울트라가 없어요 — 미션으로 충전하세요"
    /// 대상이 집중 모드일 때의 안내. 몫도 쿨타임도 소모되지 않았다는 사실까지 말해 준다 —
    /// 안 그러면 사용자는 "한 번 날린 건가?" 하고 남은 횟수를 잘못 센다.
    nonisolated static let targetFocusedNotice = "지금 집중 중이에요. 나중에 찔러 주세요"

    /// 울트라 발사 직후 안내. 잔량을 아는 경우에만 뒤에 덧붙인다.
    /// **모르면 숫자를 지어내지 않는다** — 서버가 잔량 키를 안 보내는 창(구버전 서버)이 실제로 있고,
    /// 그때 "0개예요"라고 말하면 그건 거짓말이다. 순수 함수라 UI 는 자기 문장을 만들지 않는다.
    nonisolated static func ultraSentNotice(balance: Int?) -> String {
        guard let balance else { return "울트라 찌르기 발사!" }
        return balance > 0 ? "울트라 발사! 남은 울트라 \(balance)개" : "울트라 발사! 이제 0개예요"
    }

    /// 콕찌르기 패널 열림/refresh 루프에서 부르는 디렉토리 로드 래퍼(Task 발사).
    func loadPokeDirectory() {
        Task { @MainActor in await performLoadPokeDirectory() }
    }

    /// refresh 루프 전용 — **팝오버가 열려 있고** 패널이 노출 중일 때만 재조회.
    /// isPokePanelVisible 은 팝오버를 닫아도 내려가지 않는다('마지막으로 본 패널'을 다음 오픈에 그대로 보여 주기
    /// 위한 값이다). 그래서 이 플래그만 보면 닫힌 팝오버가 app_user_directory(6.4KB/37행)를 30초마다 두드린다
    /// (v0.2.38 Q7 계측). 다시 열리는 순간의 1회 갱신은 setMenuPresented(true) 의 loadPokeDirectory() 가 맡는다.
    func refreshPokeDirectoryIfVisible() async {
        guard isMenuPresented, isPokePanelVisible else { return }
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
                    pokeNotice = Self.ultraEmptyNotice
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

    /// 울트라 찌르기. 선게이트는 일반 sendPoke 와 **정확히 같다**(로그인 + 근무중). 잔량은 여기서 막지 않는다.
    /// 서버 게이트 순서는 invalid → 보낸이근무 → 대상근무 → 집중모드 → 관리자 → 재화 → 쿨타임이고,
    /// 여기 매핑도 그 어휘를 따른다(docs/ultra-economy.md §3 — 그 순서가 계약이다).
    ///
    /// **로컬 잔량(ultraBalance)으로 요청을 막지 않는 이유**: 잔량은 미션으로 **그날 중에 늘어난다**.
    /// 0을 보고 선게이트를 걸면, 3시간을 채워 서버 잔량이 1이 된 사용자가 앱을 재시작하기 전까지
    /// 못 쏜다 — 서버는 허락하는데 클라가 요청을 안 내서. v0.2.30 의 구버전이 정확히 그 상태이고
    /// (CheckMenuView:2590 의 `if canUltra`), 그래서 서버가 구버전에는 밑바닥 2를 계속 준다.
    /// 표시(잔량 배지·툴팁)와 발사 허용(서버 판정)을 갈라 두는 것이 이 함수의 요점이다.
    func sendUltraPoke(to userID: String) {
        guard session != nil else { return }
        guard startedAt != nil else {
            pokeNotice = "근무 중일 때만 콕 찌를 수 있어요"
            return
        }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                let response = try await withSessionRetry { activeSession in
                    try await service.sendUltraPoke(accessToken: activeSession.accessToken, to: userID)
                }
                guard generation == sessionGeneration else { return }
                switch PokeSendOutcome(response: response) {
                case .ok:
                    // 울트라도 pokes 행을 남기므로 서버의 같은-대상 60초 쿨타임이 함께 시작된다.
                    // 여기서 미러를 안 맞추면 버튼이 활성인 채로 남아 다음 탭이 확정 cooldown 을 받는다.
                    //
                    // withSessionRetry 가 토큰 갱신으로 이 RPC 를 재발사한 경우, 서버엔 이미 행이 있어
                    // 두 번째 응답이 하루 한도를 하나 더 깎은 값으로 온다 — 남은 횟수는 서버 값이 진실이므로
                    // 그대로 반영한다(로컬 추측으로 덮지 않는다).
                    pokeCooldownUntil[userID] = Date().addingTimeInterval(Self.pokeCooldownSeconds)
                    // 서버 값이 유일한 진실이다. nil(= 키를 안 보내는 서버)이면 **덮지 않는다** —
                    // 직전에 알던 잔량을 모름으로 되돌리면 배지가 "—"로 깜빡인다.
                    if let balance = response.ultraBalanceForDisplay { applyUltraBalance(balance) }
                    pokeNotice = Self.ultraSentNotice(balance: response.ultraBalanceForDisplay ?? ultraBalance)
                    // ★ 잔량이 **줄어드는 유일한 순간**이다. 서버는 대기 중인 랩(v0.2.41)을 "잔량이
                    //   상한 밑으로 내려간 다음 sync"에 지급하므로, 여기서 한 번 걷어차지 않으면
                    //   그 사람은 최대 5분(.periodic 스로틀)을 기다린다 — 방금 쓴 대가로 받는 것이라
                    //   지연이 그대로 "안 주네?"로 읽힌다.
                    //   ★ 랩 스로틀 키(ultraLapKey)가 대신해 주지 못한다: 그 키는 **로컬 누적 근무초**
                    //     (todayDuration)를 3시간으로 나눈 값이라 대기 중에도 6·9시간에서 그냥 오른다.
                    //     즉 그쪽은 **근무 시간**이 만드는 발화고, 여기는 **잔량이 줄어드는 순간**이 만드는
                    //     발화다. 울트라를 써도 todayDuration 은 1초도 안 움직이므로 두 발화는 겹치지
                    //     않는다 — 지금 이 지점이 없으면 방금 쓴 사람에게 즉시 지급할 경로가 없다.
                    syncUltraWallet(reason: .missionCandidate)
                case .ultraUsedToday:
                    // 상태 어휘는 서버가 확정한 7개 중 하나이고 이름만 옛것이다(ultra_used_today).
                    // 의미는 이제 "잔량 0"이다 — 팀 무제한이 폐지돼 팀원에게도 재화를 쓴다.
                    // status 자체가 '재화 없음'의 권위다 — 서버가 잔량을 안 실어 줘도 0으로 본다.
                    applyUltraBalance(response.ultraBalanceForDisplay ?? 0)
                    pokeNotice = Self.ultraEmptyNotice
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
                    // 집중 모드도 재화를 태우지 않는다 — 서버가 재화 차감보다 **앞에서** 거절하므로
                    // 여기서 잔량을 건드리면 안 된다(멀쩡한 재화를 화면에서만 깎게 된다).
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

    // MARK: - 울트라 재화 지갑 (ultra_wallet_sync)
    //
    // 이 절의 전제 하나만 기억하면 된다: **ultra_wallet_sync 는 읽기가 아니다.**
    // 밑바닥 보정과 미션 적립이 그 호출 안에서 일어난다. 그래서 "안 부르면 못 받는다" 이고,
    // 호출 지점이 넷인 것은 화면을 위해서가 아니라 **재화가 소실되지 않게** 하기 위해서다.

    /// `.periodic` 스로틀 주기(초). 15초 폴링에 그냥 얹으면 사용자당 하루 수천 왕복이 된다(무료 플랜).
    /// 5분이면 3시간 임계를 넘긴 사용자가 늦어도 5분 안에 코인을 받는다.
    static let ultraWalletSyncThrottleSeconds: TimeInterval = 300

    /// 지갑 sync 를 부르는 이유. **진단 문자열이 아니라 호출 지점의 목록이다** —
    /// 이 enum 의 케이스가 곧 "코인이 소실되지 않는 이유" 넷이다.
    enum UltraSyncReason: String, Equatable, Sendable {
        /// 로그인/저장 세션 활성화 직후. 어제 몫 소급(p_days_back=1)이 여기서 걸린다.
        case signIn
        /// 콕찌르기 패널 또는 울트라 패널을 연 순간. 화면에 낡은 숫자를 그리지 않기 위해서다.
        case panelOpen
        /// 랩 임계를 넘은 순간(클라 hour3 마일스톤, 랩마다 1회) **그리고 울트라 발사에 성공한 순간**.
        /// 뒤쪽이 v0.2.41 에서 붙었다: 대기 중인 랩은 "잔량이 상한 밑으로 내려간 다음 sync"에 지급되는데,
        /// 잔량이 줄어드는 순간이 발사 하나뿐이라 거기서 묻지 않으면 5분 뒤에야 들어온다.
        case missionCandidate
        /// 폴링 tick 의 5분 스로틀. **근무중일 때만.** 위 셋을 전부 놓친 사용자의 마지막 그물이다.
        case periodic
    }

    /// Task 발사 래퍼. 호출부는 결과를 기다리지 않는다(화면은 @Observable 로 따라온다).
    func syncUltraWallet(reason: UltraSyncReason) {
        Task { @MainActor in await performSyncUltraWallet(reason: reason) }
    }

    /// 폴링 tick 전용 — 근무중이고 스로틀이 열렸을 때만 발사한다. **요청 0건이 기본값이다.**
    func syncUltraWalletIfDue(now: Date) {
        guard startedAt != nil else { return }
        if let last = lastUltraWalletSyncAt,
           now.timeIntervalSince(last) < Self.ultraWalletSyncThrottleSeconds {
            return
        }
        syncUltraWallet(reason: .periodic)
    }

    /// 실제 왕복. 응답을 잔량·미션·스트릭에 반영하고, **이번 호출에서 받은** 미션이 있으면 연출과 안내를 남긴다.
    func performSyncUltraWallet(reason: UltraSyncReason) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        // 스탬프는 **발사 시점**에 찍는다. 성공에만 찍으면 서버가 죽어 있는 동안 매 tick 이 재시도해
        // 15초마다 왕복이 나간다(reportAppVersionIfNeeded 와 반대 규약인 이유: 저쪽은 실패해도 요청 1건이
        // 아니라 '수신 스위치 영구 off' 라는 회복 불가 상태를 만들지만, 여기 실패의 대가는 5분 지연뿐이다).
        lastUltraWalletSyncAt = clock()
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.syncUltraWallet(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            applyUltraWallet(response)
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            // 실패는 **잔량을 지우지 않는다.** 알던 숫자를 버리면 배지가 "—"로 깜빡이는데,
            // 재화는 이월되므로 직전 값이 지금도 거의 확실히 맞다. 대신 진단 플래그만 세운다.
            ultraBalanceFailed = true
        }
    }

    /// 응답 반영(순수 상태 전이 — 네트워크 없음). 테스트가 이 한 함수로 규칙을 고정한다.
    func applyUltraWallet(_ response: UltraWalletResponse) {
        guard response.isOK else {
            // status == "invalid" = 비로그인/프로필 없음. **서버 오류가 아니다.**
            // 실패 플래그를 세우면 화면이 "못 읽었어요 + 재시도" 를 띄우는데, 재시도해도 같은 답이 온다.
            ultraBalanceFailed = false
            return
        }
        ultraBalanceFailed = false
        applyUltraBalance(response.balance)
        if let cap = response.balanceCap, ultraBalanceCap != cap { ultraBalanceCap = cap }
        // 무제한 깃발은 **서버가 준 값 그대로**다. nil(구버전 서버)은 isUnlimited 가 false 로 접는다 —
        // 모를 때 무제한이라고 말하면 그건 만들어 낸 사실이다.
        if ultraUnlimited != response.isUnlimited { ultraUnlimited = response.isUnlimited }
        let rows = MissionProgress.rows(from: response)
        if missions != rows { missions = rows }
        if !missionsLoaded { missionsLoaded = true }
        if streakDays != response.streakDays { streakDays = response.streakDays }
        if streakIncludesToday != response.streakIncludesToday {
            streakIncludesToday = response.streakIncludesToday
        }
        if let target = response.missions.first(where: { $0.key == MissionProgress.Kind.todayThreeHours.rawValue })?.targetSeconds,
           target > 0, ultraMissionTargetSeconds != target {
            ultraMissionTargetSeconds = target
        }

        // ★ granted_now 가 **유일한** 연출 트리거다. claimed 는 "오늘 몫을 이미 받았다"라서
        //   5분마다 참이고, 그걸 트리거로 쓰면 근무 내내 2초 연출이 반복된다.
        //   어제 몫 소급도 여기 걸린다(kst_day 를 가리지 않는 것이 의도다 — 받았으면 알려야 한다).
        guard response.missions.contains(where: { $0.grantedNow }) else { return }
        // 연출은 2초면 사라진다. 자리를 비운 사용자에게 그것만으로는 아무 증거도 남지 않으므로
        // **지속 증거**를 같은 지점에서 남긴다(패널을 열면 이 줄이 그를 기다린다).
        // 랩 반복 지급이라 오늘 몫이 항상 1개는 아니다. granted_now 행들의 lapsGranted 최대값이
        // **오늘 실제로 받은 랩 수**다(어제 소급 행이 섞여도 큰 쪽이 오늘 몫이다). 0 은 랩 이전 서버가
        // 그 키를 안 보낸 것이므로 1로 접는다 — "오늘 0개"는 받은 사람에게 거짓말이다.
        let lapsToday = response.missions.filter { $0.grantedNow }.map { $0.lapsGranted }.max() ?? 1
        missionNotice = lapsToday >= 2
            ? "3시간 채웠어요 — 울트라 +1 (오늘 \(lapsToday)개)"
            : "3시간 채웠어요 — 울트라 +1"
        onRewardTrigger?(.ultraCharged)
    }

    /// 잔량 대입(@Observable 동등성 가드 + 음수 방어). 음수는 서버 버그이거나 미래 규약이라 0으로 접는다.
    func applyUltraBalance(_ value: Int) {
        let normalized = max(0, value)
        if ultraBalance != normalized { ultraBalance = normalized }
    }

    /// 표시용 쿨타임 잔여 초(0이면 찌르기 가능). displayNow 티커 기준으로 매초 줄어든다.
    func pokeCooldownRemaining(for userID: String, now: Date) -> Int {
        guard let until = pokeCooldownUntil[userID] else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    /// 수신 찔림 폴링 시작(idempotent). startStatusRefreshLoop 와 같은 지점에서 켜지고 clearPersistedSession 이 끈다.
    /// 15초마다 localExpiryTick() 1회분을 돈다.
    /// 루프는 sleep 먼저·폴링 나중이다 — 시작 즉시 네트워크 콜을 내지 않아 기존 단위테스트의 요청 목록 단언이 흔들리지 않는다
    /// (앱 상시 실행이라 첫 전달 15초 지연은 무해).
    func startPokePolling() {
        guard pokePollTask == nil else { return }
        pokePollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // 주기는 **매 반복의 앞**에서 다시 읽는다 — 구독/해제 전이는 지금 자는 구간이 끝난 다음 tick 부터
                // 새 주기를 탄다(Q8). 자는 도중에 깨워 재계산하지 않는다: 그러면 전이가 요동칠 때 tick 이 몰린다.
                let interval = self?.pokePollIntervalSecondsNow ?? Self.pokePollIntervalSeconds
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(2))
                if Task.isCancelled { return }
                guard let self else { return }
                await self.localExpiryTick()
            }
        }
    }

    /// 폴링 1회분 본문. sleep 과 분리해 둔 이유는 테스트다 — 게이트 순서를 실증하려면 tick 을 직접 불러야 하는데,
    /// 루프에 인라인돼 있으면 실시간 15초를 기다리거나 주기 상수를 전역 var 로 여는 수밖에 없다. 후자는
    /// 병렬로 도는 다른 스위트가 서로의 값을 덮어써 무음으로 깨진다(URLProtocolStub.delayedHosts 에서 이미 겪었다).
    /// 세션이 없으면 요청 0건으로 빠지고 루프는 다음 tick 을 계속 돈다(로그인 복구를 기다리는 것).
    func localExpiryTick() async {
        guard session != nil else { return }
        // 표시를 기다리다 5분이 지난 메시지를 큐에서 버린다(요청 0건 — 순수 로컬 판정, 위 한 줄과 같은 이유).
        // **근무중 게이트 앞이 핵심이다**: 근무를 끝내 캐릭터가 사라진 뒤가 바로 큐가 가장 오래 밀리는 구간이라,
        // 게이트 뒤에 두면 정확히 필요한 때 안 돈다.
        expireStaleMessages(now: clock())
        // 1시간 지난 '최근 표시 메시지'도 여기서 버린다(요청 0건 — 순수 로컬 판정, 위 한 줄과 같은 이유).
        // 근무중 게이트 앞에 두는 것이 핵심이다: 비근무 구간이야말로 자리를 비운 사이 받은 말이 낡는 구간이다.
        // 위 5분과 **다른 상수인 것이 의도다** — 그 이유는 expireLastShownMessage 주석에 있다.
        expireLastShownMessage(now: clock())
        // 공개 설정 1회 로드는 아래 근무중 게이트보다 **앞**이다. 뒤로 내리면 근무를 한 번도 시작하지 않은 사용자가
        // 자기 token_usage_public 서버값을 영영 못 읽어, 로그인 직후의 낙관 기본값 true 가 교정되지 않는다
        // — 비공개로 꺼 둔 사람의 토큰 사용량이 다음 실행마다 공개로 되살아나 보인다.
        await loadTokenUsagePrivacyIfNeeded()
        // 집중 모드 1단 만료도 근무중 게이트 **앞**이다(요청 0건 — 켜져 있지 않으면 첫 가드에서 빠진다).
        // 티커는 비근무 + 팝오버 닫힘이면 멈추므로, 퇴근 뒤 켜 둔 1단을 푸는 자리는 로그인 중 상시 도는 이 폴링뿐이다.
        // 뒤로 내리면 "근무를 끝낸 뒤 3시간"이 영영 오지 않는다 — 정확히 그 사람들이 켜 놓고 까먹는 사람들이다.
        evaluateFocusStageExpiry(now: clock())
        // 내 버전 보고도 근무중 게이트 **앞**이다(공개 설정 로드와 같은 자리·같은 이유). 뒤로 내리면 근무를
        // 한 번도 시작하지 않은 사용자의 app_build 가 서버에서 영영 null 로 남고, 그 사람은 팀원 목록에서
        // '메시지 못 받는 사람'으로 굳는다 — 정작 그가 근무를 시작하는 순간에도 그렇다(목록은 그 전에 그려진다).
        // 평소 요청은 0건이다: 아래 변경 게이트가 실행당 한 번만 통과시킨다.
        await reportAppVersionIfNeeded()
        // 근무중이면 5분에 1회 지갑을 맞춘다(요청 0~1건 — 아래 스로틀이 막는다).
        // ★ 이 자리가 blocker(서버 #3)의 마지막 그물이다: 근무만 하고 패널을 한 번도 안 연 사용자는
        //   .panelOpen 도 .signIn 도 안 타고, 3시간 마일스톤은 하루 1회뿐이라 그 순간 네트워크가 끊겨 있으면
        //   그날 sync 가 0회가 된다 — 그러면 서버가 미션을 평가할 기회 자체가 없어 코인이 영구 소실된다.
        //   (다음 날 p_days_back=1 이 어제 몫을 소급하지만, 이틀 연속으로 놓치면 그건 사라진다.)
        syncUltraWalletIfDue(now: clock())
        // ★ 리얼타임 킬스위치. **폴링 경로를 지우지 않았다** — 리얼타임이 실제로 구독 중일 때만 쉰다.
        //   판정을 여기 한 줄에만 두는 것이 핵심이다(RealtimeState.isSubscribed 주석):
        //   두 곳에서 갈라 판정하면 "리얼타임은 반쯤 죽었는데 폴링도 안 도는" 완전한 침묵이 만들어진다.
        //   출시 시점 realtimeState 는 .idle(.disabled) 라 이 가드는 언제나 통과한다 = 지금과 같다.
        if !pollingIsPausedByRealtime {
            await takePokesIfWorking()
        }
    }

    /// v0.2.34 는 **리얼타임을 켜되 폴링을 함께 돌린다**(사장님 확정).
    ///
    /// 이 상수가 true 인 동안 아래 판정은 언제나 false 다 = 억제가 없다. 왜 켜자마자 안 떼는가:
    /// e2e 배달은 **내 맥 1대·안정된 wifi·깨어 있는 상태**에서만 증명됐다. 증명 못 한 것은 38명이
    /// 실제로 겪는 것들이다 — 뚜껑 여닫기, VPN 전환, 절전 복귀, 카페 wifi. 좀비 소켓 감지·백오프
    /// 재연결·캐치업은 **단위 테스트로만** 검증됐고 실환경에서 한 번도 돌지 않았다.
    /// 폴링을 남기면 그 로직이 틀렸을 때 **30초 지연으로 열화**되고, 떼면 **찌르기가 아예 안 온다**.
    /// 그리고 안 오는 것은 **아무도 신고하지 않는다** — 이 앱의 최악 실패 모드는 침묵이다.
    ///
    /// 중복 소비 걱정은 없다: 링과 폴링이 같은 찌름을 동시에 집어도 take_pokes 가 원자적으로
    /// 소비하므로 두 번째는 빈손으로 돌아온다. 그 원자성이 초인종 설계가 성립하는 근거 그 자체다.
    ///
    /// **떼는 조건**: 실사용에서 리얼타임이 안정적임이 확인되면 이 상수를 지우고 억제를 되살린다(v0.2.35).
    /// 그때 판정이 다시 `realtimeState.isSubscribed` 하나로 돌아간다.
    static let pollingKeepsRunningAlongsideRealtime = true

    /// 링 구독 신호의 **단일 읽기 지점**. 폴링 억제(pollingIsPausedByRealtime)와 폴링 주기
    /// (pokePollIntervalSecondsNow)가 둘 다 여기서 파생한다 — 같은 신호를 두 곳에서 따로 읽으면 한쪽만
    /// 고쳐진 날 "리얼타임은 반쯤 죽었는데 폴링은 60초로 늘어져 있는" 반쪽 침묵이 된다.
    var realtimeRingIsSubscribed: Bool { realtimeState.isSubscribed }

    /// 폴링이 리얼타임에 자리를 내줬는가. **폴링 억제 판정의 단일 출처다.**
    var pollingIsPausedByRealtime: Bool {
        Self.pollingKeepsRunningAlongsideRealtime ? false : realtimeRingIsSubscribed
    }

    /// 지금 이 순간의 take_pokes 폴링 주기(초). 구독 중 60초, 그 외(킬스위치 `.idle(.disabled)`·연결 중·
    /// 재연결·실패·비근무) 15초 — v0.2.38 Q8. 루프가 매 반복 앞에서 읽으므로 전이는 다음 tick 부터 반영된다.
    var pokePollIntervalSecondsNow: Double {
        realtimeRingIsSubscribed ? Self.pokePollIntervalSecondsWhileSubscribed : Self.pokePollIntervalSeconds
    }

    /// 이 맥의 앱 버전을 서버 profiles 에 남긴다(실행당 1회). 서버가 이 값으로 **남이 나에게 메시지를 보낼 수
    /// 있는지**를 판정하므로(send_message 의 target_outdated), 이건 통계 수집이 아니라 수신 스위치다.
    ///
    /// 게이트 3겹, 순서에 전부 이유가 있다:
    ///  1. 세션 없음 → 0건. 보고할 프로필 자체가 없다.
    ///  2. 번들에서 못 읽음 → 0건. 개발 빌드에는 CFBundleVersion 이 없거나 이상한 값이 들어 있는데,
    ///     거기서 폴백 숫자를 올리면 서버가 나를 구버전으로 보고 **남의 전송을 막는다**(AppVersionReport 주석).
    ///  3. 이번 실행에서 같은 (계정+버전)을 이미 보냈으면 → 0건. 15초 폴링에 그냥 얹으면 사용자당 하루
    ///     3,840~5,760회의 PATCH 가 된다(takePokesIfWorking 주석이 센 그 숫자다).
    ///
    /// 실패는 조용히 삼킨다 — 도장을 **성공에만** 찍으므로 다음 tick 이 그대로 재시도한다(lastUploadedUsage 규약).
    /// 컬럼/권한이 없는 서버(마이그레이션 미적용)에서는 매 tick 400/403 을 한 번씩 먹지만, 그 실패는 화면에도
    /// 다른 기능에도 닿지 않는다. 여기서 도장을 미리 찍어 재시도를 막으면 db push 가 끝난 뒤에도 이 맥만
    /// 영영 구버전으로 남는다.
    func reportAppVersionIfNeeded() async {
        guard let activeSession = session else { return }
        guard let report = appVersionProvider() else { return }
        let stamp = "\(activeSession.userID)|\(report.build)|\(report.version)"
        guard reportedAppVersionStamp != stamp else { return }
        let generation = sessionGeneration
        do {
            try await withSessionRetry { retrySession in
                try await service.updateAppVersion(
                    accessToken: retrySession.accessToken,
                    userID: retrySession.userID,
                    report: report
                )
            }
            guard generation == sessionGeneration else { return }
            reportedAppVersionStamp = stamp
        } catch {
            // 취소·네트워크·컬럼 부재 전부 여기로 온다. 도장을 안 찍었으므로 다음 폴링 tick 이 다시 시도한다.
        }
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
    /// ★ blocker(리얼타임 #5) — 이 가드는 **리얼타임 경로에서도 유지된다.**
    /// work_sessions_one_open_per_user 때문에 회사 맥이 근무중이면 집 맥은 확정적으로 비근무인데,
    /// 초인종은 두 맥 모두에 도착한다. 집 맥도 take_pokes 를 쏘면 단일 UPDATE…RETURNING 이 한쪽만
    /// 이기게 하므로 **회사 맥에는 아무것도 안 오고**, 집 맥은 CheckOverlayWindow 의 peek 경로가
    /// shouldBeVisible 게이트를 안 보므로 8초짜리 팝업을 띄운다.
    ///
    /// `adoptedRemoteSession` 도 함께 막는다: 흡수 세션의 주인은 다른 맥이다. 로컬 startedAt 이
    /// 서 있어도 그 근무는 이 맥의 것이 아니므로, 여기서 소비하면 진짜 주인이 못 본다.
    func takePokesIfWorking() async {
        guard startedAt != nil, !adoptedRemoteSession else { return }
        await drainReceivedPokes()
    }

    /// take_pokes 1회 원자 수신+소비 후 1시간 이내 신선분만 onPokesReceived 로 흘린다.
    /// 폴링 tick 과 근무 종료 꼬리 회수가 이 한 몸을 공유한다 — 소비가 원자적이라 경로가 갈라지면
    /// 한쪽이 삼킨 찔림을 다른 쪽이 다시 볼 방법이 없다.
    /// 세대 재확인이 없으면 로그아웃/재로그인 사이에 도착한 응답이 새 계정 화면에 앞 계정의 말풍선을 띄운다.
    @discardableResult
    func drainReceivedPokes() async -> DrainOutcome {
        guard session != nil else { return .failed("세션 없음") }
        let generation = sessionGeneration
        do {
            let rows = try await withSessionRetry { activeSession in
                try await service.takePokes(accessToken: activeSession.accessToken)
            }
            // 세대가 갈렸으면 이 응답은 앞 계정의 것이다. **소비는 이미 서버에서 일어났으므로**
            // 성공으로 보고할 수도 없다 — 캐치업이 "따라잡았다"고 판단하면 새 계정의 미소비분을 놓친다.
            guard generation == sessionGeneration else { return .failed("세션 세대 변경") }
            let now = Date()
            let batch = WorkTimerStore.freshReceivedPokes(rows: rows, now: now)
            if !batch.isEmpty {
                onPokesReceived?(batch)
            }
            // 같은 응답이 둘로 갈리는 **유일한 지점**. 메시지는 찔림 리액션(움찔·"콕 찔렀어요" 말풍선)을 타지 않고
            // 자기 큐로 간다 — 위 batch 에는 메시지가 애초에 들어 있지 않으므로(freshReceivedPokes 의 kind 가드)
            // 한 행이 두 경로를 동시에 타는 일은 없다.
            enqueueReceivedMessages(WorkTimerStore.freshReceivedMessages(rows: rows, now: now))
            // count 는 **소비된 행 전체 수**(신선도 필터 이전)다. 초인종 페이로드의 pending 과 견주면
            // 소비 경로가 새는지 보이는데, 필터 뒤 개수를 세면 '오래돼서 안 보여준 것'까지 유실로 오진한다.
            return .ok(count: rows.count)
        } catch {
            // 화면은 여전히 조용하다(다음 tick 에 재시도). 바뀐 것은 **호출부가 실패를 알 수 있다**는 것뿐이고,
            // 그게 리얼타임 캐치업이 재시도할 수 있는 유일한 근거다.
            return .failed(String(describing: error))
        }
    }

    /// drain 요청을 **직렬화**한다. 이미 돌고 있으면 새로 쏘지 않고 트레일링 한 번으로 접는다 —
    /// 1초 안에 두 명이 찌르면 초인종이 두 번 울리는데, 그때 take_pokes 를 두 번 동시에 쏘면
    /// 원자 소비가 한쪽만 이겨 나머지 응답은 빈 배열이다(그리고 두 요청 모두 무료 플랜 왕복을 쓴다).
    ///
    /// ★ blocker(리얼타임 #2) — **defer 를 쓰지 마라.** `defer { drainInFlight = nil }` 은 스코프 종료
    ///   시점에 실행되므로, 트레일링을 소비하러 재진입하는 시점에도 drainInFlight 가 여전히 non-nil 이다.
    ///   그러면 재진입이 자기 자신에게 막혀 pending 만 다시 세우고 아무도 안 돈다 = **두 번째 찌르기가
    ///   영영 유실된다**(폴링을 지운 구성에서는 회복 경로가 0이다). 루프로 소비하고 **그 뒤에** 비운다.
    func requestDrain() {
        guard drainInFlight == nil else {
            drainPendingTrailing = true
            return
        }
        drainInFlight = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 drain 이 도는 동안 도착한 신호를 지운다.
                self.drainPendingTrailing = false
                _ = await self.drainReceivedPokes()
            } while self.drainPendingTrailing
            self.drainInFlight = nil
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
        // 리얼타임이 구독 중이면 꼬리 회수가 필요 없다 — 그 15초 창은 폴링 게이트가 만든 것이고,
        // 구독 중에는 초인종이 즉시 requestDrain 을 부르므로 이미 비어 있다. 여기서 한 번 더 쏘면
        // 근무 종료 순간에 확정적으로 빈 배열을 받는 왕복이 하나 는다.
        guard !pollingIsPausedByRealtime else { return nil }
        return Task { @MainActor [weak self] in
            await self?.drainReceivedPokes()
        }
    }

    /// take_pokes 응답 행 → 수신 찔림으로 매핑하고 신선도(1시간 이내)로 거른다. 순수 static 함수라 테스트로 고정한다.
    /// 액터 상태를 건드리지 않는 순수 함수라 nonisolated — 테스트가 동기 컨텍스트에서 직접 호출한다.
    nonisolated static func freshReceivedPokes(rows: [TakenPokeRow], now: Date) -> [ReceivedPoke] {
        rows.compactMap { row in
            var kind = PokeKind(rawServerValue: row.kind)
            // 메시지 행은 여기서 **빠진다**. 이 한 줄이 없으면 "밥?" 하고 보낸 메시지가 평범한
            // "…님이 콕 찔렀어요!" 말풍선으로 둔갑한다(본문은 어디에도 안 뜬 채 서버에서 소비만 된다).
            // 갈라내는 지점은 여기 하나뿐이라, 찔림/울트라 처리는 아래 그대로 남는다.
            guard kind != .message else { return nil }
            let createdAt = Date(timeIntervalSince1970: TimeInterval(row.createdEpoch))
            let age = now.timeIntervalSince(createdAt)
            guard age <= pokeDisplayFreshnessSeconds else { return nil }
            // 늦게 도착한 울트라는 전체화면 격발을 포기하고 평범한 움찔로 **강등**한다(버리지 않는다) —
            // 보낸 사람이 하루 몇 번뿐인 몫을 이미 태웠으므로 최소한 누가 찔렀는지는 전해야 한다.
            if kind == .ultra, age > ultraDisplayFreshnessSeconds { kind = .normal }
            return ReceivedPoke(id: row.id, fromName: row.fromDisplayName, createdAt: createdAt, kind: kind)
        }
    }

    // MARK: - 메시지 수신 (찔림과 같은 표·같은 RPC·같은 폴링)
    //
    // 메시지는 찔림과 **같은 표(pokes.kind = "message")·같은 RPC(take_pokes)·같은 폴링**을 탄다.
    // 갈라지는 곳은 정확히 한 군데다: 받은 행을 어느 표시 경로로 보내는가(freshReceivedPokes 의 kind 가드).
    //
    // ★ **보내기는 여기 없다**(v0.2.49). 전송·이력·창은 `WorkTimerStoreMessages.swift` 로 옮겼다 —
    //   그날부터 메시지는 쿨타임이 없고(찌르기만 60초다) 200자를 쓰며 12시간 이력을 갖는, 찌르기와
    //   성격이 다른 기능이 됐다. 이 파일에 남은 것은 **말풍선 큐**뿐이다.
    //
    // ★ **쿨타임 미러(messageCooldownUntil)와 messageCooldownRemaining 은 통째로 지웠다.**
    //   되살리지 마라 — 서버가 send_message 에서 `cooldown` 을 영원히 내지 않으므로, 그 값을 다시 두면
    //   아무도 갱신하지 않는 미러가 화면에 카운트다운을 그리게 된다(사장님이 없애라고 한 바로 그것).

    /// 표시 대기 큐 상한. 자리를 비운 사이 큐가 무한히 자라 화면이 몇 시간 전 대화를 순서대로 재생하는 것을 막는다.
    nonisolated static let messageQueueLimit = 20

    /// **말풍선 전달 창(초) = 5분.** 보낸 지 이 시간이 지나면 **말풍선으로는** 띄우지 않는다 — 사장님 확정:
    /// "2시간 전에 보낸 메시지가 뜨는 건 이상하다. 5분 안에 도달 못 하면 그냥 안 전하는 게 자연스럽다."
    ///
    /// ★ **이력(message_history)의 12시간과 혼동하지 마라.** 둘은 다른 질문의 답이다:
    ///   이 5분은 "지금 화면 위로 튀어나올 것인가"이고, 12시간은 "창을 열었을 때 읽을 수 있는가"다.
    ///   메시지 창이 생기기 전에는 말풍선이 유일한 표시 수단이라 이 값이 곧 소멸 시각이었지만,
    ///   이제는 아니다 — 5분이 지나 말풍선을 못 본 말도 창에는 12시간 남아 있다.
    ///
    /// **찔림의 1시간(pokeDisplayFreshnessSeconds)과 일부러 다른 상수인 이유**: 두 알림의 값이 다르다.
    /// 찔림은 "누가 나를 불렀다"라 한참 뒤에 알아도 의미가 남지만, 메시지는 그 순간의 말이라
    /// 늦게 화면을 덮으면 방해가 된다. 울트라가 같은 이유로 120초를 따로 가진다.
    nonisolated static let messageDisplayFreshnessSeconds: TimeInterval = 300
    /// 지금 화면에 띄울 메시지 1건(없으면 nil). 말풍선은 한 번에 하나뿐이라 **큐의 맨 앞이 곧 화면**이다.
    var currentMessage: ReceivedMessage? { receivedMessages.first }

    /// 지금 것 뒤에 몇 건이 더 기다리는가. UI 가 "+2" 같은 표시로 '아직 남았다'를 알려 줄 수 있게 노출한다.
    var waitingMessageCount: Int { max(0, receivedMessages.count - 1) }

    /// 지금 것의 표시가 끝났음을 알리고 다음 건을 올린다.
    /// **큐를 미는 권한이 UI 에 있는 이유**: 말풍선이 몇 초 떠 있는지를 아는 쪽이 표시 계층이다. 스토어가
    /// 타이머로 자동 회전시키면 표시 시간과 회전 주기가 두 곳에서 따로 정해져, 언젠가 한 건이 뜨자마자 밀린다.
    func consumeCurrentMessage() {
        guard !receivedMessages.isEmpty else { return }
        // 큐에서 빼되 **버리지 않고 옮겨 담는다**. 말풍선은 몇 초 만에 사라지므로 여기서 놓아 버리면
        // 자리를 비운 사이 온 글자는 앱 어디에도 안 남는다(서버는 take_pokes 로 이미 원자 소비했다).
        // 큐가 비어도 이 값은 남아 팝오버가 "놓친 것"을 보여줄 수 있다.
        // 큐가 비어 있으면 위 가드에서 빠지므로 **직전 표시분이 그대로 유지된다** — 표시가 끝났다는 신호가
        // 한 번 더 와도 화면이 갑자기 비지 않는다.
        lastShownMessage = receivedMessages.removeFirst()
    }

    /// 표시를 기다리다 5분이 지난 메시지를 **큐에서 버린다**(알리지 않는다).
    ///
    /// **도착 필터(freshReceivedMessages)만으로는 부족한 이유가 이 함수의 존재 이유다.** 말풍선은 한 번에
    /// 하나뿐이라, 다른 말풍선(자동 시작 안내·1등 출근·업데이트 알림)이 떠 있거나 울트라가 격발 중이면
    /// 메시지는 **양보하고 큐에 남는다**. 근무를 끝내 캐릭터가 사라지면 더 오래 남는다. 그 대기 구간에서
    /// 5분이 지나면 서버는 "안 전한다"고 정한 말을 화면만 뒤늦게 띄우게 된다 — 그게 어긋남이다.
    ///
    /// **버렸다고 사용자에게 알리지 않는다.** 보낸 사람은 전송 시점에 이미 답을 받았고(ok/target_outdated 등),
    /// 못 받은 사람은 애초에 그런 말이 있었는지 모른다. 여기서 "놓친 메시지가 있어요"를 띄우면 내용을 모르는
    /// 알림만 남아, 사용자가 할 수 있는 일이 없는 불안만 만든다.
    ///
    /// 요청 0건짜리 순수 로컬 판정이라 refreshUltraQuota/expireLastShownMessage 와 **같은 자리**(pokePollTick)에
    /// 붙는다. 그래서 실제 정밀도는 **5분 + 최대 1폴링 주기(15초)** 다 — 표시 직전에 정확히 재고 싶으면
    /// 화면이 currentMessage 를 읽기 전에 이 함수를 인자 없이 부르면 된다(now 는 주입 시계로 채워진다).
    func expireStaleMessages(now: Date? = nil) {
        guard !receivedMessages.isEmpty else { return }
        let now = now ?? clock()
        let fresh = receivedMessages.filter {
            now.timeIntervalSince($0.createdAt) <= Self.messageDisplayFreshnessSeconds
        }
        // == 가드: 버릴 게 없는 평소엔 대입조차 하지 않는다(@Observable 은 같은 값 재대입도 관찰자를 깨운다).
        if fresh.count != receivedMessages.count { receivedMessages = fresh }
    }

    /// 나이가 지난 '최근 표시 메시지'를 버린다. **여기만 1시간(pokeDisplayFreshnessSeconds)이다** —
    /// 위 5분 규칙과 헷갈리지 마라. 성격이 다르다: 5분은 "아직 한 번도 안 뜬 말을 지금 전할 것인가"의
    /// 전달 판정이고, 이 칸은 "이미 떴는데 못 본 것을 다시 볼 수 있는가"의 확인 창이다. 이미 화면에 나간
    /// 말이라 늦게 다시 봐도 거짓이 되지 않고, 팝오버는 사용자가 직접 열어서 보는 자리다.
    ///
    /// 패널을 한 번도 안 열어 본 사용자에게는 closePokePanel 의 소비가 영영 안 오므로, 이 만료가 없으면
    /// 어제 받은 "밥?"이 다음 날 팝오버에 그대로 떠 있다. 요청 0건짜리 순수 로컬 판정이라
    /// refreshUltraQuota 와 **같은 자리**(pokePollTick)에 붙인다.
    func expireLastShownMessage(now: Date) {
        guard let last = lastShownMessage else { return }
        guard now.timeIntervalSince(last.createdAt) > Self.pokeDisplayFreshnessSeconds else { return }
        lastShownMessage = nil
    }

    /// take_pokes 응답에서 **메시지 행만** 골라 신선분을 도착 순으로 돌려준다. 순수 static 이라 테스트로 고정한다.
    /// 신선도는 **메시지 전용 5분**(messageDisplayFreshnessSeconds)이다 — 찔림의 1시간과 갈라 둔 근거는
    /// 그 상수 주석에 있다. 서버 take_pokes 도 같은 5분으로 거르므로 정상 경로에서 이 필터는 거의 발화하지
    /// 않는다. 그럼에도 두는 이유: 서버가 아직 그 규칙을 모르는 구간(마이그레이션 전)과 응답이 늦게 도착한
    /// 경우가 남고, 그때 화면만 혼자 낡은 말을 띄우면 서버 규칙과 어긋난다.
    /// 서버 반환 순서는 신뢰하지 않고 시각으로 다시 세운다
    /// (sortedForPokeDisplay 와 같은 규약) — 순서가 곧 사용자가 읽는 순서이기 때문이다.
    nonisolated static func freshReceivedMessages(rows: [TakenPokeRow], now: Date) -> [ReceivedMessage] {
        rows.compactMap { row -> ReceivedMessage? in
            guard PokeKind(rawServerValue: row.kind) == .message else { return nil }
            // 본문 정규화는 **보낼 때와 같은 함수**(MessageBody.sanitized)를 쓴다 — 여기서 자체 trim 을 만들면
            // 제어문자·방향 오버라이드가 말풍선 한 줄을 깨는 경로가 수신 쪽에만 남는다.
            // 비면 버린다: 빈 말풍선은 "누가 뭘 보냈는데 내용이 없다"로 읽혀 사용자가 앱을 의심하게 만든다.
            // 길이는 **재검사하지 않는다** — 서버 상한이 늘면 그건 새 진실이지 오류가 아니다.
            let body = MessageBody.sanitized(row.body ?? "")
            guard !body.isEmpty else { return nil }
            let createdAt = Date(timeIntervalSince1970: TimeInterval(row.createdEpoch))
            guard now.timeIntervalSince(createdAt) <= messageDisplayFreshnessSeconds else { return nil }
            return ReceivedMessage(
                id: row.id,
                fromName: row.fromDisplayName,
                body: body,
                createdAt: createdAt,
                // 보낸이 id 를 여기서 함께 나른다 — 팝오버의 수신 줄이 "그 사람 대화"를 열 수 있는 근거다.
                fromUserID: row.fromUser
            )
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// 수신 메시지를 큐 뒤에 붙인다. 같은 id 는 무시한다 — take_pokes 는 원자 소비라 정상 경로에선 중복이 없지만,
    /// withSessionRetry 가 토큰 갱신으로 같은 RPC 를 재발사한 창에서는 같은 행을 두 번 볼 수 있고
    /// 그때 말풍선이 같은 말을 두 번 띄우면 사용자는 상대가 두 번 보냈다고 읽는다.
    /// 상한을 넘으면 **오래된 쪽부터** 버린다 — 지금 부르는 사람을 놓치는 편이 더 나쁘다.
    func enqueueReceivedMessages(_ messages: [ReceivedMessage]) {
        guard !messages.isEmpty else { return }
        let known = Set(receivedMessages.map(\.id))
        let arrivals = messages.filter { !known.contains($0.id) }
        guard !arrivals.isEmpty else { return }
        var queue = receivedMessages + arrivals
        if queue.count > Self.messageQueueLimit {
            queue.removeFirst(queue.count - Self.messageQueueLimit)
        }
        receivedMessages = queue
        // ★ **여기가 "창을 열어 둔 채로 메시지가 오면 그 자리에서 나타난다"의 유일한 근거다**(v0.2.49).
        //   새 타이머를 만들지 않고 이미 도는 수신 폴링(15초)에 얹는다 — 무료 플랜에 상시 요청을
        //   하나 더 얹지 않는다는 규약(제보 목록·미니게임 순위와 같다).
        //   창이 닫혀 있으면 아무 요청도 안 나간다: 이력은 창을 열 때 어차피 한 번 받는다.
        refreshMessageHistoryOnArrival()
    }

    /// 로그인 후 내 토큰 사용량 공개·수집 설정을 서버값으로 1회 로드한다(폴링 첫 유효 tick 에서 부른다).
    /// 성공 시에만 loaded 플래그를 세워, 실패하면 다음 tick 에 다시 시도할 수 있게 한다.
    ///
    /// 게이트는 **수집 설정 수신**(tokenUsageCollectLoaded)이다 — 공개 플래그(tokenUsagePublicLoaded)는 사용자가 GET 전에 토글하면
    /// 먼저 서는 낙관 플래그라, 그것을 게이트로 쓰면 로그인 직후 토글 한 번에 이 GET 이 영영 안 나가 수집 설정도 못 받고
    /// Codex 계정 프로브도 그 세션 내내 잠긴다. 그래서 GET 은 수집 설정을 받을 때까지 나가되, 공개 여부는 사용자가 이미 골랐으면
    /// (tokenUsagePublicLoaded) 서버값으로 덮지 않는다(PATCH 가 아직 안 닿은 낡은 값일 수 있다 — 옛 규약 그대로).
    func loadTokenUsagePrivacyIfNeeded() async {
        guard !tokenUsageCollectLoaded, session != nil else { return }
        let generation = sessionGeneration
        // GET 을 보내기 **전의** 집중 모드 선택 번호. 응답이 오기 전에 사용자가 버튼을 눌렀으면 이 응답이 더 낡았다.
        let focusIntentAtRequest = focusIntentSerial
        do {
            let settings = try await withSessionRetry { activeSession in
                try await service.fetchTokenUsageSettings(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration else { return }
            if !tokenUsagePublicLoaded, tokenUsagePublic != settings.isPublic { tokenUsagePublic = settings.isPublic }
            // 수집 설정은 사용자가 앱에서 바꾸는 값이 아니라 서버가 정하는 값이라 낙관 갱신도 토글도 없다.
            // 앱 게이트는 통신 낭비를 줄이는 부수 장치일 뿐 — 실효는 서버 트리거가 낸다(구버전도 함께 막힌다).
            if tokenUsageCollect != settings.collects { tokenUsageCollect = settings.collects }
            // 여기서 세운다 — 서버 응답을 **실제로 받은** 유일한 자리다(아래 별명 쿨타임 GET 은 try? 라 이 사실과 무관하다).
            tokenUsageCollectLoaded = true
            // 집중 모드도 같은 GET 으로 받는다(요청 추가 0). 컬럼이 없는 서버에서는 false 로 와서 기존 동작이 유지된다.
            // v0.2.51: 서버값을 그대로 대입하지 않고 이 맥의 단계 기록과 합친다 — 서버 꺼짐이면 기록을 지우고,
            // 서버 켜짐 + 앱이 꺼져 있던 동안 끝난 1단이면 **여기서 곧바로** PATCH false 를 건다(앱 재시작 만료).
            applyServerFocusMode(settings.focusMode, intentSerialAtRequest: focusIntentAtRequest)
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
            // 미니게임 순위 공개도 **따로** GET 한다(컬럼이 없는 서버에서 위 설정 GET 이 같이 죽지 않게 — 별명 쿨타임과 같은 규약).
            // 사용자가 이미 골랐으면(miniGamePublicLoaded) 낡은 서버값으로 덮지 않는다. 실패는 nil = 공개(기본)로 둔다.
            let miniGame = try? await withSessionRetry { activeSession in
                try await service.fetchMiniGamePublic(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration else { return }
            if !miniGamePublicLoaded, let miniGame, miniGamePublic != miniGame { miniGamePublic = miniGame }
            if miniGame != nil { miniGamePublicLoaded = true }
            // 소속 센터도 **따로** GET 한다(v0.3.13). 위 두 GET 과 같은 이유다.
            await loadMyCenterIfNeeded()
            guard generation == sessionGeneration else { return }
            tokenUsagePublicLoaded = true
        } catch {
            // 조용히 무시한다 — loaded 는 성공 시에만 서므로 다음 폴링 tick 에 재시도된다.
        }
    }

    /// 내 소속 센터(profiles.center)를 **아직 모를 때만** 서버에서 받아 온다.
    ///
    /// **별도 GET 인 이유**: 기존 설정 GET(fetchTokenUsageSettings)의 select 에 center 를 끼우면 마이그레이션이
    /// 아직 안 간 서버에서 42703 → 그 요청이 통째로 400 이 되어 **토큰 공개·수집·집중 모드까지** 같이 못 읽는다
    /// (SupabaseWorkService 1543~1552 가 그 사고를 기록한다). 별명 쿨타임·미니게임 공개와 같은 규약이다.
    ///
    /// **부르는 곳이 둘인 이유**: 로그인 후 설정 로드에서 한 번 부르고(그래야 설정 창을 열었을 때 이미 값이 있다),
    /// 설정 창의 센터 행이 뜰 때 또 부른다. 첫 번째가 네트워크 blip 으로 실패하면 그 함수는 다시 안 돈다
    /// (tokenUsageCollectLoaded 가 서 있으면 통째로 건너뛴다) — 그러면 그 세션 내내 설정 창이 '불러오는 중'에
    /// 멈춰 **자기 센터를 끝내 못 본다**(그 자리엔 고칠 길이 없으니 남는 건 못 보는 것뿐이다).
    /// 두 번째 호출이 그 유일한 복구 경로다. 이미 받았으면(myCenterLoaded) 즉시 반환하므로 창을 여닫아도
    /// 왕복은 늘지 않는다.
    ///
    /// ★ 실패와 '미지정'을 **가르는 것이 이 함수의 전부다.** 실패면 플래그를 안 세워 다음 기회에 다시 묻고,
    ///   성공이면 값이 nil 이어도(= 아직 안 고른 사람) 플래그를 세워 '미지정'을 정직하게 그린다.
    ///   `try?` 를 쓰지 않는 이유가 이것이다 — `String??` 을 풀면 두 nil 이 같은 자리에서 뭉개진다.
    func loadMyCenterIfNeeded() async {
        guard !myCenterLoaded, session != nil else { return }
        let generation = sessionGeneration
        do {
            let serverCenter = try await withSessionRetry { activeSession in
                try await service.fetchMyCenter(
                    accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration else { return }
            // 기다리는 사이 다른 호출(설정 로드 ↔ 설정 창 행)이 먼저 값을 채웠으면 그걸로 끝난다 —
            // 두 응답이 같은 값이라도 두 번 대입하면 관찰 갱신이 한 번 더 돌아 화면이 괜히 다시 그려진다.
            guard !myCenterLoaded else { return }
            if myCenter != serverCenter { myCenter = serverCenter }
            myCenterLoaded = true
        } catch {
            // 조용히 무시한다 — 플래그가 안 서므로 설정 창을 다시 열 때 재시도된다.
        }
    }

    // ★ `setMyCenter(_:)` 는 **일부러 없다**(사장님 지시 2026-09-12, v0.3.13 2차). 센터는 가입 때
    //   한 번 고르고 그 뒤로는 본인이 못 바꾼다 — 강제 수단은 서버 권한이다(`profiles.center` 에
    //   `grant update` 를 주지 않았다). 낙관 반영 + PATCH 세터를 여기 다시 두면 화면이 먼저 바뀌었다가
    //   거절이 조용히 원복해서, 사용자는 자기가 바꿨다고 믿은 채 아무 안내도 못 받는다(가장 나쁜 실패).
    //   잘못 고른 사람은 운영자가 SQL 로 고친다. 다시 만들려면 서버 grant 부터 되돌리고 실패 안내를 먼저 설계하라.
    //   미러(`myCenter`)를 쓰는 쪽은 읽기 GET 하나뿐이다 — 위 `loadMyCenterIfNeeded()`.

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

    // MARK: - 집중 모드 2단 (v0.2.51)
    //
    // 사용자 지시(2026-09-11): "켜 놨다가 까먹고 안 끄는 사람이 여럿 있다. 1단은 3시간 뒤 자동으로 풀리고,
    // 2단은 지금처럼 끌 때까지 계속. 버튼 한 번이면 1단, 두 번 눌러야 2단."
    //
    // 켜 두면 남이 나를 찌를 수 없다 — 판정은 여전히 **서버**가 한다(poke_user/ultra_poke_user 게이트). 그래서 구버전 앱을
    // 쓰는 팀원도 내 집중 모드를 존중하고, 이 계층은 화면 표시와 '언제 끌지'만 맡는다.
    //
    // ★ **만료는 클라가 한다. 서버는 한 줄도 바뀌지 않았다**(같은 날 사용자 결정 — "굳이 서버에서 할 필요가 있을까?
    //   앱이 다시 켜진 시점에 자동으로 풀어지게끔 하면 되는 거 아니야?"). 서버가 아는 것은 여전히 `profiles.focus_mode`
    //   불리언 하나이고, 3시간이 지나면 **앱이 켜져 있을 때 앱이** PATCH false 를 보낸다.
    //   앱이 꺼져 있는 동안 서버에 true 가 남아도 해가 없다: 앱이 꺼진 사람은 근무중이 아니라 찌르기·메시지가
    //   이미 `target_not_working` 으로 막힌다. 집중 모드는 "앱이 켜져 있을 때 방해받지 않기"를 위한 것이다.
    //   **"서버 만료가 더 정확하다"며 서버로 옮기지 마라** — 사용자가 명시적으로 기각한 설계다(컬럼·RPC·구버전 호환이
    //   통째로 따라온다). 앱이 다시 켜지면 설정 로드 직후(applyServerFocusMode) 그 자리에서 풀린다.

    /// 1단(시간제) 집중의 길이. **이 한 곳에서만** 정한다 — 버튼 툴팁의 "3시간"도 여기서 파생한다
    /// (숫자를 문구에 베껴 두면 상수를 바꾼 날 화면만 옛 시간을 말한다 — UltraBalanceText 와 같은 교훈).
    nonisolated static let focusTimedDuration: TimeInterval = 3 * 60 * 60

    /// 1단 만료 PATCH false 가 실패했을 때 다시 보내기까지의 최소 간격(초).
    /// 틱은 팝오버가 열려 있으면 **1초마다** 오므로, 이 간격이 없으면 서버가 죽은 동안(무료 플랜 일시정지 5xx)
    /// 38명의 맥이 매초 PATCH 를 두드린다. 0 으로 줄이지 마라.
    nonisolated static let focusExpiryRetrySeconds: TimeInterval = 60

    /// 사용자 누름이 실패했을 때의 안내(옛 토글과 같은 문장).
    nonisolated static let focusModeChangeFailedNotice = "집중 모드를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요"

    /// 사용자별 단계 기록 키. **userID 가 키에 들어가는 것이 요점이다** — 한 키로 두면 같은 맥에서 계정을 바꾼 다음 사람이
    /// 앞 사람의 1단(남은 시간까지)을 물려받는다. 대소문자는 접는다(세션 복원 경로마다 UUID 표기가 다를 수 있다).
    nonisolated static func focusStageRecordKey(userID: String) -> String {
        "focusStageRecord.\(userID.lowercased())"
    }

    /// 이 맥에 남은 그 사용자의 단계 기록. 없거나 깨졌으면 nil — 서버가 켜져 있다면 always(2단)로 읽힌다.
    /// `.standard` 가 아니라 주입된 `defaults` 를 쓴다(테스트가 실제 기본값을 더럽히지 않게).
    func focusStageRecord(for userID: String) -> FocusStageRecord? {
        guard let data = defaults.data(forKey: Self.focusStageRecordKey(userID: userID)) else { return nil }
        return try? JSONDecoder().decode(FocusStageRecord.self, from: data)
    }

    /// 단계 기록을 쓴다(nil 이면 지운다). 실제로 바뀐 때만 관찰 카운터를 올린다 — 같은 값 재기록이 버튼을 다시 그리지 않게.
    func writeFocusStageRecord(_ record: FocusStageRecord?, for userID: String) {
        let key = Self.focusStageRecordKey(userID: userID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // 같은 기록 = 같은 바이트(아래 비교가 뜻을 갖게)
        let new = record.flatMap { try? encoder.encode($0) }
        guard defaults.data(forKey: key) != new else { return }
        if let new {
            defaults.set(new, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        focusStageRevision &+= 1
    }

    /// 표시용 단계(파생값). **부수효과가 없다** — 뷰 잎이 매초 부를 수 있어야 해서다.
    /// 만료로 판정돼도 여기서는 요청을 보내지 않는다: 실제 해제(PATCH false)는 이미 도는 자리의
    /// evaluateFocusStageExpiry 가 건다. body 에서 네트워크를 쏘면 재평가 횟수만큼 요청이 나간다.
    /// 로그인하지 않았으면 off 다(기록은 사용자별이라 읽을 주인이 없다 — 남의 기록이 비로그인 화면에 새지 않는다).
    func focusStage(now: Date) -> FocusStage {
        guard focusMode, let userID = session?.userID else { return .off }
        _ = focusStageRevision
        return FocusStagePolicy.stage(serverOn: true, record: focusStageRecord(for: userID), now: now)
    }

    /// 버튼 잎이 부르는 읽기(단계 + 1단 남은 초). `now` 는 **1단 기록이 있을 때만 평가된다**(@autoclosure).
    /// 꺼짐·2단에서 시계를 읽으면 그 잎이 초침(displayNow)에 관찰 등록돼, 보일 게 없는데도 매초 다시 그려진다.
    func focusStageFace(now: @autoclosure () -> Date) -> FocusStageFace {
        guard focusMode, let userID = session?.userID else { return .off }
        _ = focusStageRevision
        let record = focusStageRecord(for: userID)
        guard let record, record.stage == .timed, let until = record.until else {
            // 시계가 필요 없는 가지: 기록 없음·2단 → always, until 이 없는 깨진 1단 → off(정책이 시계 없이 판정한다).
            return FocusStageFace(stage: FocusStagePolicy.stage(serverOn: true, record: record, now: now()))
        }
        let current = now()
        let stage = FocusStagePolicy.stage(serverOn: true, record: record, now: current)
        guard stage == .timed else { return FocusStageFace(stage: stage) }
        return FocusStageFace(stage: .timed, remainingSeconds: max(0, Int(until.timeIntervalSince(current))))
    }

    /// 집중 모드 버튼 한 번. `off → 1단(3시간) → 2단(계속) → off` 순환(사용자 지시 2026-09-11).
    /// 1단이 막 끝났지만 아직 해제 요청 전인 순간(화면은 이미 off 로 읽힌다)에 누르면 새 1단이 시작된다 —
    /// 화면에 보이는 단계에서 한 칸 가는 것이 사용자가 기대하는 동작이다.
    func cycleFocusStage() {
        let now = clock()
        switch focusStage(now: now) {
        case .off: commitFocusStage(.timed, now: now)
        case .timed: commitFocusStage(.always, now: now)
        case .always: commitFocusStage(.off, now: now)
        }
    }

    /// 켜짐/꺼짐만 아는 옛 진입점. 켜면 **2단(always)** 과 같다 — 만료를 말하지 않고 켰으면 무기한(옛 의미 그대로).
    /// 같은 값 재설정은 아무 일도 하지 않는다(@Observable 무효화·헛왕복 방지 — FocusModeTests 가 요청 수로 못 박는다).
    func setFocusMode(_ enabled: Bool) {
        guard focusMode != enabled else { return }
        guard session != nil else {
            // 로그인 전: 보낼 곳도, 기록을 쓸 주인도 없다. 옛 규약대로 미러만 바꾼다.
            focusMode = enabled
            return
        }
        commitFocusStage(enabled ? .always : .off, now: clock())
    }

    /// CheckMenuView 의 옛 버튼이 아직 이 이름을 부른다. **cycleFocusStage 로 위임한다** — 옛 뜻(켜짐↔꺼짐)으로 두면
    /// 새 버튼 배선 전의 옛 버튼이 기록 없이 켜서, 1단이 존재하지 않는 불일치 상태(곧바로 2단)가 생긴다.
    func toggleFocusMode() {
        cycleFocusStage()
    }

    /// 사용자가 고른 단계를 반영한다: 기록 → 화면(낙관) → 서버 맞추기.
    /// 순서가 중요하다 — 기록을 먼저 써야 focusMode 가 바뀌어 잎이 다시 그려질 때 새 단계를 읽는다.
    private func commitFocusStage(_ target: FocusStage, now: Date) {
        guard let userID = session?.userID else { return }
        focusIntentSerial &+= 1
        // 사용자가 직접 골랐다 — 만료 재시도 대기는 여기서 끝난다. 남겨 두면 방금 새로 켠 1단을
        // 예전 만료의 재시도가 뒤늦게 false 로 꺼 버린다.
        focusExpiryRetryAt = nil
        let record: FocusStageRecord?
        switch target {
        case .off: record = nil
        case .timed: record = FocusStageRecord(stage: .timed, until: now.addingTimeInterval(Self.focusTimedDuration))
        case .always: record = FocusStageRecord(stage: .always, until: nil)
        }
        writeFocusStageRecord(record, for: userID)
        let serverOn = target != .off
        if focusMode != serverOn { focusMode = serverOn }
        // 1단 → 2단은 서버값이 이미 true 라 여기서 요청이 나가지 않는다(아래 함수의 '같음' 가드).
        // 서버가 아직 false 로 알고 있으면(1단 PATCH 가 확인되지 않았으면) 그때는 보낸다.
        reconcileFocusModeWithServer()
    }

    /// 화면의 켜짐/꺼짐(focusMode)을 서버에 맞춘다. **한 번에 한 요청만** 날린다.
    ///
    /// 왜 한 줄로 세우나: 2단이 생기면서 버튼을 연달아 누르는 일이 흔해졌다(off→1단→2단→off 가 1초 안에 세 번).
    /// 누를 때마다 PATCH 를 병렬로 쏘면 true 와 false 가 동시에 날아가고 서버에는 **나중에 커밋된 쪽**이 남는다 —
    /// 화면은 꺼짐인데 서버는 켜짐인 채로 굳을 수 있고, 그러면 다음 실행에서 '기록 없음 = 2단'으로 되살아난다.
    /// 날아가는 동안의 선택은 완료 뒤 이 함수가 다시 불려 **마지막 의도 하나만** 보낸다.
    func reconcileFocusModeWithServer() {
        guard focusPatchInFlight == nil, let userID = session?.userID else { return }
        let desired = focusMode
        guard focusModeServerValue != desired else {
            // 이미 서버와 같다. 꺼짐으로 확정됐으면 남은 기록(만료된 1단)과 재시도 대기를 비운다.
            if !desired { settleFocusOff(userID: userID) }
            return
        }
        focusPatchInFlight = desired
        let generation = sessionGeneration
        Task { @MainActor in
            var succeeded = false
            var cancelled = false
            do {
                try await withSessionRetry { activeSession in
                    try await service.updateFocusMode(
                        accessToken: activeSession.accessToken,
                        userID: activeSession.userID,
                        enabled: desired
                    )
                }
                succeeded = true
            } catch {
                if case .cancelled = classifyAuthError(error) { cancelled = true }
            }
            // 로그아웃·계정 교체 뒤에 도착한 결과는 새 사용자의 화면을 만지지 않는다(clearPersistedSession 이 장부를 이미 비웠다).
            guard generation == sessionGeneration else { return }
            focusPatchInFlight = nil
            finishFocusPatch(sent: desired, succeeded: succeeded, cancelled: cancelled, userID: userID)
        }
    }

    private func finishFocusPatch(sent: Bool, succeeded: Bool, cancelled: Bool, userID: String) {
        if succeeded {
            focusModeServerValue = sent
        } else if focusMode == sent {
            // 날아가는 동안 의도가 바뀌지 않았다 = 이 실패가 곧 지금 화면의 실패다.
            if !sent, let record = focusStageRecord(for: userID), FocusStagePolicy.isExpired(record, now: clock()) {
                // ★ 만료 경로는 **원복하지 않는다.** 사용자의 의도는 이미 꺼짐이다(3시간이 끝났다). 옛 토글의
                //   `focusMode = previous` 를 여기서 하면 "풀렸다가 다시 켜진" 깜빡임이 되고, 끝난 1단이 기록 없는 켜짐 = 2단처럼 남는다.
                //   화면은 off 로 둔 채 최소 60초 뒤에 다시 보낸다. 기록은 성공할 때까지 **남긴다** — 지금 지우면 앱이 꺼졌다
                //   켜질 때 '서버 true + 기록 없음' = 2단으로 되살아난다. 사용자가 누른 일이 아니라 안내도 띄우지 않는다.
                focusExpiryRetryAt = clock().addingTimeInterval(Self.focusExpiryRetrySeconds)
                return
            }
            // 취소는 실패로 세지 않는다(옛 토글 규약 — 원복도 안내도 없다).
            if cancelled { return }
            // 사용자 누름의 실패: 서버가 들고 있다고 확인된 값으로 화면을 되돌린다(옛 토글의 원복 규약).
            let restored = focusModeServerValue ?? !sent
            if focusMode != restored { focusMode = restored }
            if !restored { writeFocusStageRecord(nil, for: userID) }
            pokeNotice = Self.focusModeChangeFailedNotice
            return
        }
        // 날아가는 동안 사용자가 다시 골랐으면(또는 방금 확정됐으면) 마지막 선택을 이어서 맞춘다.
        reconcileFocusModeWithServer()
    }

    /// 꺼짐이 화면과 서버 양쪽에서 확정됐다 — 남은 기록(만료된 1단)과 재시도 대기를 비운다.
    private func settleFocusOff(userID: String) {
        focusExpiryRetryAt = nil
        writeFocusStageRecord(nil, for: userID)
    }

    /// 1단 만료 확인. **새 타이머를 만들지 않고** 이미 도는 자리에서 부른다:
    ///  · 티커 `tick()` — 팝오버가 열려 있으면 1초, 근무 중 닫혀 있으면 최대 60초(감속). 단 **비근무 + 팝오버 닫힘이면
    ///    티커 자체가 멈춘다**(stopTimerIfIdle) — 퇴근 뒤 켜 둔 1단은 이 자리만으로는 영영 안 풀린다.
    ///  · 수신 폴링 `localExpiryTick()` — 로그인 중 상시 15초(리얼타임 구독 중 60초). 위 공백을 이것이 메운다.
    ///  · 잠자기에서 깨어날 때 `handleWake` — 켜 두고 덮개를 닫은 다음 날 아침이 가장 흔한 만료 시점이다.
    ///  · 설정 로드 직후 `applyServerFocusMode` — 앱이 꺼져 있던 동안 끝난 1단.
    /// 시각은 전부 `clock()` 이다. 켤 때도 같은 시계로 until 을 적었으므로 맥 시계가 틀어져 있어도 3시간은 3시간이다.
    func evaluateFocusStageExpiry(now: Date) {
        // 빠른 길: 켜져 있지도 재시도를 기다리지도 않으면 defaults 조차 읽지 않는다(틱마다 불린다).
        guard focusMode || focusExpiryRetryAt != nil, let userID = session?.userID else { return }
        guard let record = focusStageRecord(for: userID), FocusStagePolicy.isExpired(record, now: now) else { return }
        if focusMode {
            // 처음 감지: 화면을 곧바로 off 로 두고(사용자 의도는 이미 꺼짐) 서버에 맞춘다. 요청은 in-flight 가드로 한 건뿐이다.
            focusIntentSerial &+= 1
            focusMode = false
            reconcileFocusModeWithServer()
        } else if let retryAt = focusExpiryRetryAt, now >= retryAt, focusPatchInFlight == nil {
            focusExpiryRetryAt = nil
            reconcileFocusModeWithServer()
        }
    }

    /// 설정 GET 이 가져온 서버값을 반영한다(로그인 후 1회 — loadTokenUsagePrivacyIfNeeded).
    /// `intentSerialAtRequest` 는 GET 을 보내기 **전에** 읽은 focusIntentSerial 이다.
    func applyServerFocusMode(_ serverOn: Bool, intentSerialAtRequest: Int) {
        guard let userID = session?.userID else { return }
        // 날아가는 PATCH 가 있으면 그 결과가 곧 서버값을 알려 준다 — 그보다 먼저 떠난 이 응답은 낡았다.
        guard focusPatchInFlight == nil else { return }
        // GET 이 나간 뒤 이 맥에서 고른 것이 **서버에 닿았다면** 이 응답이 더 낡았다 — 화면을 덮지 않는다.
        // (옛 코드는 덮었고, 그러면 방금 켠 1단이 꺼짐으로 보이는데 서버는 켜짐으로 남는다.)
        // 서버값을 끝내 확인하지 못했다면(그 누름이 실패했다면) 이 응답이 아는 것 중 가장 새롭다 — 반영한다.
        if focusIntentSerial != intentSerialAtRequest, focusModeServerValue != nil { return }
        focusModeServerValue = serverOn
        guard serverOn else {
            // 서버가 꺼짐이다 — 다른 맥에서 껐거나 서버가 덮었다. 이 맥의 기록은 이제 아무것도 서술하지 않는다.
            if focusMode { focusMode = false }
            settleFocusOff(userID: userID)
            return
        }
        if let record = focusStageRecord(for: userID), FocusStagePolicy.isExpired(record, now: clock()) {
            if focusExpiryRetryAt != nil {
                // 이미 한 번 실패해 재시도를 기다리는 중이다 — 60초 간격은 이 경로에서도 지킨다(재시도 판정은 한 곳).
                // 여기서 곧바로 보내면 실패 직후의 첫 설정 로드가 간격을 건너뛴 재시도가 된다.
                evaluateFocusStageExpiry(now: clock())
                return
            }
            // 앱이 꺼져 있던 동안 1단이 끝났다 — 켜진 화면을 한 번도 그리지 않고 곧바로 해제한다.
            if focusMode { focusMode = false }
            reconcileFocusModeWithServer()
            return
        }
        // ★ 서버 켜짐 + 기록 없음 = **2단(always)**. 요청도 기록 쓰기도 없다 — 기록이 없다는 것 자체가 always 다
        //   (기존 사용자 전환, 2026-09-11 사용자 지시. 근거와 금지 사항은 FocusStagePolicy.stage 주석).
        if !focusMode { focusMode = true }
    }
}

/// 집중 모드 단계(v0.2.51 — 사용자 지시 2026-09-11). 서버는 켜짐/꺼짐만 안다 — **어느 단으로 켰는지는 이 맥만 안다.**
enum FocusStage: String, Codable, Equatable, Sendable {
    /// 꺼짐(찌르기를 받는다).
    case off
    /// 1단 — 3시간 뒤 이 앱이 스스로 끈다(WorkTimerStore.focusTimedDuration).
    case timed
    /// 2단 — 끌 때까지 계속(v0.2.50 까지의 집중 모드와 같다).
    case always
}

/// 이 맥에 남기는 단계 기록(사용자별 키 — WorkTimerStore.focusStageRecordKey).
/// off 는 기록하지 않는다: 기록 삭제가 곧 off 이고, **기록이 없다는 것 = (서버가 켜져 있다면) always** 다.
struct FocusStageRecord: Codable, Equatable, Sendable {
    let stage: FocusStage
    /// 1단의 해제 시각(스토어 clock 기준). 2단은 nil.
    let until: Date?
}

/// 단계 판정(순수 함수). 스토어와 테스트가 **같은 표**를 읽는다.
enum FocusStagePolicy {
    static func stage(serverOn: Bool, record: FocusStageRecord?, now: @autoclosure () -> Date) -> FocusStage {
        // 서버 꺼짐이 최우선이다 — 기록이 뭐라 하든 off(다른 맥에서 껐거나 서버가 덮었다).
        guard serverOn else { return .off }
        guard let record else {
            // ★ 서버 켜짐 + 이 맥에 기록 없음 = **always(2단)**. 업데이트 전부터 켜 둔 사람이 여기로 온다.
            //   2026-09-11 사용자 지시: "업데이트 할 때 이미 집중모드 켜 둔 사람들 2단으로 해 놔 줘."
            //   앞 판의 "기록 없는 기존 사용자는 1단으로 전환해 3시간을 센다"는 **사용자가 명시적으로 취소했다.**
            //   "잊은 사람을 정리한다"는 그럴듯한 이유로 여기를 .timed/.off 로 바꾸지 마라 — 켜 둔 사람이 업데이트 한 번에
            //   말없이 풀린다. "딱 한 번만 전환"하는 표지(marker)도 만들지 마라 — 기록 없음 자체가 always 의 뜻이다.
            //   다른 맥에서 1단으로 켠 경우도 이 맥에는 기록이 없어 always 로 보인다. 그 맥이 3시간 뒤 끄면
            //   이 맥은 다음 설정 로드에서 서버 꺼짐을 받아 맞춰진다.
            return .always
        }
        switch record.stage {
        case .timed:
            return isExpired(record, now: now()) ? .off : .timed
        case .always, .off:
            // off 기록은 쓰지 않는다 — 누가 남겼어도 어느 단인지 말해 주지 않으므로 기록 없음과 같게 읽는다.
            return .always
        }
    }

    /// 1단이 끝났는가. **정확히 until 에서** 끝난다(경계 포함) — "곧 해제"가 0초에서 멈춰 서 있지 않게.
    /// until 이 없는 1단은 깨진 기록이다. 무기한으로 읽지 않고 끝난 것으로 본다(1단의 뜻이 '끝이 있다'다).
    static func isExpired(_ record: FocusStageRecord, now: @autoclosure () -> Date) -> Bool {
        guard record.stage == .timed else { return false }
        guard let until = record.until else { return true }
        return now() >= until
    }
}

/// 집중 모드 버튼이 그리는 한 장면(값). 시계를 이미 푼 결과다 — 뷰는 이 값만 보고 그린다.
struct FocusStageFace: Equatable, Sendable {
    let stage: FocusStage
    /// 1단일 때만 값이 있다(남은 초, 0 이상). 꺼짐·2단에서 nil 인 것은 시계를 읽지 않았다는 뜻이기도 하다.
    let remainingSeconds: Int?

    init(stage: FocusStage, remainingSeconds: Int? = nil) {
        self.stage = stage
        self.remainingSeconds = remainingSeconds
    }

    static let off = FocusStageFace(stage: .off)
}

/// 수신한 짧은 메시지 한 건. 찔림(ReceivedPoke)과 **다른 타입인 것이 요점**이다 — 같은 타입에 body 를
/// 옵셔널로 얹으면 "본문이 nil 인 메시지"와 "본문이 딸린 찔림"이 타입상 가능해지고, 그 두 불가능한 상태를
/// 표시 계층이 매번 다시 방어해야 한다. 갈라진 채로 두면 말풍선은 분기 없이 body 를 그린다.
/// Identifiable 인 이유: 큐를 그대로 ForEach 에 태울 수 있게(id 는 서버 pokes 행 id 라 전역 유일).
struct ReceivedMessage: Equatable, Identifiable {
    let id: String
    /// 보낸이 별명(서버가 실어 준 표시명).
    let fromName: String
    /// 정규화된 본문(앞뒤 공백 제거, 비어 있지 않음이 보장된다 — freshReceivedMessages 가 거른다).
    let body: String
    let createdAt: Date
    /// 보낸이의 user id(v0.2.49). **팝오버의 '최근 받은 메시지' 줄을 진입점으로 만들려고 더했다** —
    /// 별명만으로는 어느 대화를 열지 고를 수 없고(동명이인·별명 변경), id 없이 이름으로 찾으면
    /// 그 순간 엉뚱한 사람의 대화가 열린다. 그건 메신저에서 가장 나쁜 종류의 오작동이다.
    ///
    /// 기본값이 nil 인 이유는 **하위호환**이다: 이 인자를 모르는 기존 호출부(테스트 픽스처 포함)가
    /// 무수정으로 컴파일된다. nil 이면 그 줄은 버튼이 아니라 표시 줄로만 그린다 — 상대 없이 대화에 들어가는 문을 만들지 않는다(2026-09-11).
    let fromUserID: String?

    init(id: String, fromName: String, body: String, createdAt: Date, fromUserID: String? = nil) {
        self.id = id
        self.fromName = fromName
        self.body = body
        self.createdAt = createdAt
        self.fromUserID = fromUserID
    }
}
