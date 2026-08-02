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
                case .notWorking:
                    pokeNotice = "근무 중일 때만 콕 찌를 수 있어요"
                case .targetNotWorking:
                    // 대상이 자리비움 — 서버가 거부했다. 내 디렉토리의 근무중 배지가 낡았다는 뜻이라
                    // 즉시 재조회해 자리비움으로 갱신한다(다음 시도부터 버튼도 비활성으로 선게이트됨).
                    pokeNotice = "자리비움 상태에는 찌를 수 없어요"
                    loadPokeDirectory()
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
            guard now.timeIntervalSince(createdAt) <= pokeDisplayFreshnessSeconds else { return nil }
            return ReceivedPoke(id: row.id, fromName: row.fromDisplayName, createdAt: createdAt)
        }
    }

    /// 로그인 후 내 토큰 사용량 공개 여부를 서버값으로 1회 로드한다(폴링 첫 유효 tick 에서 부른다).
    /// 성공 시에만 loaded 플래그를 세워, 실패하면 다음 tick 에 다시 시도할 수 있게 한다.
    func loadTokenUsagePrivacyIfNeeded() async {
        guard !tokenUsagePublicLoaded, session != nil else { return }
        let generation = sessionGeneration
        do {
            let isPublic = try await withSessionRetry { activeSession in
                try await service.fetchTokenUsagePublic(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration else { return }
            if tokenUsagePublic != isPublic { tokenUsagePublic = isPublic }
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
}
