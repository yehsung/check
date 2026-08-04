import Foundation
import Testing
@testable import check

// 울트라 찌르기의 **스토어 계약** — 하루 한도(2회) 게이트, 남은 횟수 미러, 안내 문구, KST 자정 리셋,
// 그리고 "울트라 소진이 일반 찌르기를 막지 않는다"는 대조군.
// 와이어(디코드/경로) 계약은 UltraPokeWireContractTests 가, 오버레이 격발은 UltraPokeOverlayTests 가 맡는다.
//
// 스위트로 감싼 이유는 이름 충돌 방지다 — 이 기능의 테스트는 세 파일에서 동시에 자라는데, 최상위
// @Test 함수 이름이 하나라도 겹치면 모듈이 통째로 컴파일되지 않는다(헬퍼 이름도 마찬가지다).
@MainActor
@Suite struct UltraPokeStoreTests {

    // MARK: - 헬퍼

    /// 테스트마다 새 suite 를 쓴다 — .standard 를 공유하면 병렬 테스트가 서로의 저장 세션/설정을 덮어쓴다.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "check-ultra-store-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 근무중·로그인 상태의 스토어. startedAt 을 직접 세우는 이유는 start() 가 동기화 큐까지 돌려
    /// 이 테스트가 세려는 요청에 잡음을 섞기 때문이다(기존 콕찌르기 테스트와 같은 관용구).
    private func makeStore(host: String, session: URLSession) -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: session
        )
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: makeDefaults()
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.startedAt = Date()
        return store
    }

    /// 응답 반영이 Task 라 결과가 나타날 때까지 짧게 폴링한다(기존 sendPokeOkMirrorsCooldownWindow 관용구).
    @discardableResult
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// 요청 기록은 프로세스 전역 버퍼라 테스트마다 고유 호스트로 격리하고 경로로 한 번 더 좁힌다.
    private func ultraRequestCount(host: String) -> Int {
        URLProtocolStub.requests(forHost: host)
            .filter { $0.url?.path == "/rest/v1/rpc/ultra_poke_user" }
            .count
    }

    // MARK: - 한도 상수(U1)

    /// 하루 한도는 **명명 상수 하나**이고 안내 문구가 거기서 파생된다. 리터럴을 흩뿌리면 한도를 바꿀 때
    /// 문구만 옛 숫자로 남아 "하루에 한 번"이라 말하면서 두 번 받아 주는 상태가 된다.
    @Test func ultraDailyLimitIsNamedConstantAndDrivesTheNotice() {
        #expect(WorkTimerStore.ultraPokeDailyLimit == 2)
        #expect(WorkTimerStore.ultraSpentNotice.contains("\(WorkTimerStore.ultraPokeDailyLimit)번"))
    }

    // MARK: - 남은 횟수 문구(U2, 순수)

    /// 모를 때는 **아무 숫자도 말하지 않는다**. 남은 횟수는 울트라 응답으로만 알 수 있어서 '모름' 구간이
    /// 정상적으로 존재하고, 그때 0 이나 한도를 지어내면 화면이 거짓말을 한다.
    @Test func ultraRemainingTextStaysSilentWhenUnknown() {
        #expect(WorkTimerStore.ultraRemainingText(remaining: nil) == nil)
        #expect(WorkTimerStore.ultraRemainingText(remaining: 2) == "오늘 2번 남음")
        #expect(WorkTimerStore.ultraRemainingText(remaining: 1) == "오늘 1번 남음")
        #expect(WorkTimerStore.ultraRemainingText(remaining: 0) == "오늘 몫은 다 썼어요")
        // 서버 이상치(음수)는 숫자로 말할 수 없다 — 침묵한다.
        #expect(WorkTimerStore.ultraRemainingText(remaining: -1) == nil)
    }

    @Test func ultraSentNoticeAppendsRemainingOnlyWhenKnown() {
        #expect(WorkTimerStore.ultraSentNotice(remaining: nil) == "울트라 찌르기 발사!")
        #expect(WorkTimerStore.ultraSentNotice(remaining: 1) == "울트라 찌르기 발사! 오늘 1번 남음")
        #expect(WorkTimerStore.ultraSentNotice(remaining: 0) == "울트라 찌르기 발사! 오늘 몫은 다 썼어요")
    }

    // MARK: - 남은 횟수 미러와 자정 리셋

    /// 2 → 1 → 0 으로 줄고, 0 에서 소진 미러가 함께 선다. 그리고 **KST 자정을 넘기면 모름(nil)으로 돌아간다** —
    /// 이 리셋이 없으면 어제의 "0번 남음"이 오늘 화면에 남아 새 날인데 못 쓴다고 안내한다.
    @Test func ultraRemainingCountsDownAndResetsAfterKSTMidnight() {
        let store = makeStore(host: "ultra-store-quota-test", session: URLSession(configuration: .stubbed))
        // KST 한낮으로 시각을 고정한다(벽시계 의존 제거 — 자정 근처에 돌려도 결과가 같다).
        let today = Date(timeIntervalSince1970: 1_785_888_000)
        let tomorrow = today.addingTimeInterval(24 * 3600)

        store.applyUltraRemaining(2, now: today)
        #expect(store.ultraRemaining(now: today) == 2)
        #expect(store.isUltraPokeSpent(now: today) == false)

        store.applyUltraRemaining(1, now: today)
        #expect(store.ultraRemaining(now: today) == 1)
        #expect(store.isUltraPokeSpent(now: today) == false)

        store.applyUltraRemaining(0, now: today)
        #expect(store.ultraRemaining(now: today) == 0)
        // 0 은 곧 소진이다 — 미러가 서야 다음 시도가 요청 없이 막힌다.
        #expect(store.isUltraPokeSpent(now: today))

        // 자정을 넘기면 어제 값은 답이 될 수 없다.
        #expect(store.ultraRemaining(now: tomorrow) == nil)
        #expect(store.isUltraPokeSpent(now: tomorrow) == false)
        store.refreshUltraQuota(now: tomorrow)
        #expect(store.ultraRemainingToday == nil)
        #expect(store.ultraRemainingDay == nil)
    }

    /// nil 은 '모름'이라 **직전 숫자를 지운다**. 마이그레이션 전 서버는 남은 횟수를 안 실어 주는데,
    /// 그때 옛 숫자를 남기면 방금 한 발 썼는데도 화면이 이전 숫자를 계속 보여준다.
    @Test func applyUltraRemainingNilFallsBackToUnknown() {
        let store = makeStore(host: "ultra-store-unknown-test", session: URLSession(configuration: .stubbed))
        let now = Date(timeIntervalSince1970: 1_785_888_000)

        store.applyUltraRemaining(1, now: now)
        #expect(store.ultraRemaining(now: now) == 1)

        store.applyUltraRemaining(nil, now: now)
        #expect(store.ultraRemaining(now: now) == nil)
        #expect(store.ultraRemainingDay == nil)
    }

    // MARK: - 게이트(요청을 아예 안 내는 경로)

    /// 오늘 몫을 다 쓴 걸 이 맥이 이미 알면 요청 자체를 안 낸다(무료 플랜 헛왕복 금지).
    @Test func sendUltraPokeSkipsRequestWhenAlreadySpentToday() async {
        let host = "ultra-store-spent-test"
        let store = makeStore(host: host, session: URLSession(configuration: .stubbed))
        store.ultraPokeSpentDay = MilestoneTracker.dayKey(Date())

        store.sendUltraPoke(to: "target")
        // 요청이 나갔다면 이 창 안에 기록된다(스텁은 지연 없이 즉시 응답한다).
        try? await Task.sleep(for: .milliseconds(80))

        #expect(ultraRequestCount(host: host) == 0)
        #expect(store.pokeNotice == WorkTimerStore.ultraSpentNotice)
    }

    /// 내가 근무중이 아니면 요청을 안 낸다(일반 찌르기와 같은 선게이트·같은 문구).
    @Test func sendUltraPokeGatesWhenIAmNotWorking() async {
        let host = "ultra-store-not-working-test"
        let store = makeStore(host: host, session: URLSession(configuration: .stubbed))
        store.startedAt = nil

        store.sendUltraPoke(to: "target")
        try? await Task.sleep(for: .milliseconds(80))

        #expect(ultraRequestCount(host: host) == 0)
        #expect(store.pokeNotice == "근무 중일 때만 콕 찌를 수 있어요")
    }

    /// 소진 미러는 **날짜 키**다 — 어제 다 썼다는 기록이 오늘의 발사를 막으면 안 된다.
    @Test func yesterdaySpentMirrorDoesNotBlockToday() async {
        let host = "ultra-store-yesterday-test"
        let store = makeStore(host: host, session: URLSession(configuration: .stubbed))
        store.ultraPokeSpentDay = MilestoneTracker.dayKey(Date().addingTimeInterval(-24 * 3600))

        store.sendUltraPoke(to: "target")
        await waitUntil { ultraRequestCount(host: host) == 1 }

        #expect(ultraRequestCount(host: host) == 1)
    }

    // MARK: - 응답 경로별 상태·문구

    /// 성공: 같은-대상 60초 쿨타임 미러 + 남은 횟수 반영 + 남은 횟수를 담은 안내.
    /// 두 번째 성공에서 0 이 되면 소진 미러가 선다(한도가 2회라는 사실이 화면과 게이트에 동시에 드러난다).
    @Test func sendUltraPokeOkMirrorsCooldownAndCountsDownToZero() async throws {
        let host = "ultra-store-ok-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"ok","ultra_remaining":1}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())
        let sentAt = Date()

        store.sendUltraPoke(to: "target")
        await waitUntil { store.ultraRemainingToday != nil }

        #expect(store.ultraRemainingToday == 1)
        #expect(store.isUltraPokeSpent(now: Date()) == false)   // 아직 한 번 남았다
        #expect(store.pokeNotice == "울트라 찌르기 발사! 오늘 1번 남음")
        let until = try #require(store.pokeCooldownUntil["target"])
        // 발사 시각 기준 하한만 엄격히 본다(상한은 병렬 실행 지연을 흡수) — 검증 대상은 '60초를 미러링했는가'.
        #expect(until.timeIntervalSince(sentAt) >= 60)
        #expect(until.timeIntervalSince(sentAt) <= 60 + 300)

        // 두 번째 발사: 서버가 남은 0 을 알려 준다.
        TokenBoardURLProtocol.setResponse(#"{"status":"ok","ultra_remaining":0}"#, forHost: host)
        store.sendUltraPoke(to: "target2")
        await waitUntil { store.ultraRemainingToday == 0 }

        #expect(store.ultraRemainingToday == 0)
        #expect(store.isUltraPokeSpent(now: Date()))
        #expect(store.pokeNotice == "울트라 찌르기 발사! 오늘 몫은 다 썼어요")
    }

    /// 한도 소진(다른 맥에서 이미 다 씀): 미러를 채워 다음 시도부터 요청을 막고, **쿨타임은 건드리지 않는다**
    /// — 하루 한도와 같은-대상 쿨타임은 다른 축이라 섞으면 대상 버튼이 이유 없이 흐려진다.
    @Test func sendUltraPokeUsedTodayMarksSpentWithoutTouchingCooldown() async {
        let host = "ultra-store-used-today-test"
        TokenBoardURLProtocol.setResponse(
            #"{"status":"ultra_used_today","ultra_remaining":0,"reset_after_seconds":3600}"#,
            forHost: host
        )
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        store.sendUltraPoke(to: "target")
        await waitUntil { store.ultraPokeSpentDay != nil }

        #expect(store.isUltraPokeSpent(now: Date()))
        #expect(store.ultraRemainingToday == 0)
        #expect(store.pokeCooldownUntil["target"] == nil)
        #expect(store.pokeNotice == WorkTimerStore.ultraSpentNotice)
    }

    /// 쿨타임: 몫은 그대로다(서버가 행을 안 남겼다). 무음 실패를 금지한다 — 3초를 꾹 눌러 링을 다 채운 뒤
    /// 아무 문구도 없으면 사용자는 '나갔다'고 읽는다.
    @Test func sendUltraPokeCooldownKeepsQuotaIntactAndSpeaks() async throws {
        let host = "ultra-store-cooldown-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"cooldown","retry_after_seconds":40}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())
        let sentAt = Date()

        store.sendUltraPoke(to: "target")
        await waitUntil { store.pokeCooldownUntil["target"] != nil }

        #expect(store.ultraPokeSpentDay == nil)          // 오늘 몫 미소진
        #expect(store.ultraRemainingToday == nil)        // 서버가 말하지 않았으니 모름 유지
        #expect(store.pokeNotice == "방금 찌른 상대예요. 잠시 후 울트라를 쓸 수 있어요")
        let until = try #require(store.pokeCooldownUntil["target"])
        #expect(until.timeIntervalSince(sentAt) >= 40)
    }

    /// 대상 자리비움: 몫을 태우지 않고, 낡은 근무중 배지를 고치러 디렉토리를 재조회한다.
    @Test func sendUltraPokeTargetNotWorkingKeepsQuota() async {
        let host = "ultra-store-target-off-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"target_not_working"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        store.sendUltraPoke(to: "target")
        await waitUntil { store.pokeNotice != nil }

        #expect(store.pokeNotice == "자리비움 상태에는 찌를 수 없어요")
        #expect(store.ultraPokeSpentDay == nil)
        #expect(store.ultraRemainingToday == nil)
    }

    /// 미지 status(마이그레이션 미적용 서버가 늘릴 수 있는 값)는 .invalid 로 접히고 몫을 태우지 않는다.
    @Test func sendUltraPokeUnknownStatusKeepsQuota() async {
        let host = "ultra-store-unknown-status-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"target_saturated"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        store.sendUltraPoke(to: "target")
        await waitUntil { store.pokeNotice != nil }

        #expect(store.pokeNotice == "지금은 찌를 수 없어요")
        #expect(store.ultraPokeSpentDay == nil)
    }

    // MARK: - 대조군

    /// **울트라 소진은 일반 찌르기를 막지 않는다.** 두 게이트가 한 몸이 되는 순간(예: 선게이트를 sendPoke
    /// 로 옮기는 '정리') 사용자는 하루 두 번 이후 아무도 못 찌르게 된다 — 그 회귀의 유일한 방어선이다.
    @Test func ultraExhaustionDoesNotBlockNormalPoke() async throws {
        let host = "ultra-store-control-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"ok"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())
        let today = MilestoneTracker.dayKey(Date())
        store.ultraPokeSpentDay = today
        store.applyUltraRemaining(0, now: Date())
        store.pokeNotice = "이전 안내"

        store.sendPoke(to: "target")
        await waitUntil { store.pokeCooldownUntil["target"] != nil }

        #expect(store.pokeCooldownUntil["target"] != nil)   // 일반 찌르기는 정상 발사됐다
        #expect(store.pokeNotice == nil)                    // ok → 안내 해제
        // 일반 찌르기는 울트라 장부를 건드리지 않는다(응답에 ultra_remaining 이 없어도 0 으로 접지 않는다).
        #expect(store.ultraPokeSpentDay == today)
        #expect(store.ultraRemainingToday == 0)
    }

    // MARK: - 수신 신선도(순수)

    /// 늦게 도착한 울트라는 **강등**한다(버리지 않는다). 보낸 사람이 하루 몇 번뿐인 몫을 이미 태웠으므로
    /// 누가 찔렀는지는 전해야 하고, 40분 전 울트라가 지금 화면을 덮으면 그건 알림이 아니라 습격이다.
    @Test func freshReceivedPokesDowngradesStaleUltra() {
        let now = Date(timeIntervalSince1970: 1_785_888_000)
        func row(_ id: String, ageSeconds: TimeInterval, kind: String?) -> TakenPokeRow {
            TakenPokeRow(
                id: id,
                fromUser: "u-\(id)",
                fromDisplayName: "이유성",
                fromAvatarUrl: nil,
                createdEpoch: Int(now.timeIntervalSince1970 - ageSeconds),
                kind: kind
            )
        }
        let rows = [
            row("fresh-ultra", ageSeconds: 10, kind: "ultra"),
            row("stale-ultra", ageSeconds: 300, kind: "ultra"),
            row("ancient-ultra", ageSeconds: 7200, kind: "ultra"),
            row("normal", ageSeconds: 300, kind: "normal")
        ]

        let pokes = WorkTimerStore.freshReceivedPokes(rows: rows, now: now)

        // 1시간(pokeDisplayFreshnessSeconds)을 넘긴 7200초짜리만 사라진다.
        #expect(pokes.map(\.id) == ["fresh-ultra", "stale-ultra", "normal"])
        #expect(pokes.map(\.kind) == [.ultra, .normal, .normal])
    }

    // MARK: - 계정 전환

    /// 계정이 바뀌면 남의 하루 몫을 물려받지 않는다. 남기면 새 계정이 자기 울트라를 못 쓰거나,
    /// 반대로 이미 다 쓴 사람이 "1번 남음"을 보고 눌러 서버 거절만 받는다.
    @Test func clearPersistedSessionClearsUltraState() {
        let store = makeStore(host: "ultra-store-clear-test", session: URLSession(configuration: .stubbed))
        let now = Date()
        store.ultraPokeSpentDay = MilestoneTracker.dayKey(now)
        store.applyUltraRemaining(0, now: now)

        store.clearPersistedSession()

        #expect(store.ultraPokeSpentDay == nil)
        #expect(store.ultraRemainingToday == nil)
        #expect(store.ultraRemainingDay == nil)
        #expect(store.isUltraPokeSpent(now: now) == false)
    }
}
