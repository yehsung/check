import Foundation

// 콕찌르기 + 토큰 사용량 공개 설정의 스토어 계층.
// 서버 계약:
//  - poke_user(p_to uuid) RPC: 보낸이·대상 모두 근무중(열린 세션) 필수, 같은 대상 60초 쿨타임. 응답 {status, retry_after_seconds?}.
//  - take_pokes() RPC: 내 미소비 찔림을 원자적으로 소비하며 반환(보낸이 표시명 포함).
//  - app_user_directory() RPC: 앱 사용자 전체(본인 제외) + is_working(열린 세션 존재).
//  - profiles.token_usage_public: 본인 행 select/update(RLS). token_usage_board 는 비공개 유저를 타인에게 숨긴다(본인 행은 유지).
@MainActor
extension WorkTimerStore {
    /// 수신 찔림 폴링 주기(초). 로그인 중 상시 — 전달 지연 상한이자 서버 부하 트레이드오프.
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
    /// 15초 루프에서 take_pokes 로 원자 수신+소비하고, 1시간 이내 신선 찔림만 onPokesReceived 로 흘린다.
    /// 루프는 sleep 먼저·폴링 나중이다 — 시작 즉시 네트워크 콜을 내지 않아 기존 단위테스트의 요청 목록 단언이 흔들리지 않는다
    /// (앱 상시 실행이라 첫 전달 15초 지연은 무해). 첫 유효 tick 에 내 공개 설정 서버값을 1회 로드한다.
    func startPokePolling() {
        guard pokePollTask == nil else { return }
        pokePollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pokePollIntervalSeconds), tolerance: .seconds(2))
                if Task.isCancelled { return }
                guard let self else { return }
                guard self.session != nil else { continue }
                // 첫 유효 tick 에 내 공개 설정을 서버값으로 1회 맞춘다(로그인 직후 낙관 기본값 true 를 교정).
                await self.loadTokenUsagePrivacyIfNeeded()
                let generation = self.sessionGeneration
                do {
                    let rows = try await self.withSessionRetry { activeSession in
                        try await self.service.takePokes(accessToken: activeSession.accessToken)
                    }
                    guard generation == self.sessionGeneration else { continue }
                    let batch = WorkTimerStore.freshReceivedPokes(rows: rows, now: Date())
                    if !batch.isEmpty {
                        self.onPokesReceived?(batch)
                    }
                } catch {
                    // 취소/일시 오류는 조용히 넘긴다(다음 tick 에 재시도).
                }
            }
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
