import Foundation
import Testing
@testable import check
@testable import CheckCore

// 공유 행 쓰기 게이트 — **확인된 세션만 방송한다**(v0.3.45).
//
// ── 왜 이 스위트가 있나 (2026-10-09 운영 사고) ─────────────────────────────────────────────────
// 맥 2대 사용자. 아이맥이 세션을 열어 둔 채 남았고 맥북의 [근무 시작] INSERT 가 부분 유니크
// work_sessions_one_open_per_user 로 23505 에 걸렸다. 그 세션 행은 **서버에 들어간 적이 없다.**
// 그런데 하트비트는 큐를 안 지나가서 30초마다 그 클라 생성 UUID 를 공유 행에 써넣었고, 서버는
// 이렇게 보였다(실측):
//
//   work_statuses      : status=working, active_session_id=943df952…  ← work_sessions 에 없는 id
//   work_status_devices: 맥북 → 943df952…(유령) · 아이맥 → af5db2ec…(실재)  ← 둘 다 opened_session=true
//
// 이 스위트가 재는 것은 **음성**이다: 확인되지 않은 세션은 공유 행에 한 건도 못 올라간다.
// 양성(정상 근무는 신호가 나간다)은 AdoptedSessionSyncTests.ownSessionStillHeartbeats 가 대조군으로 지킨다.
// 둘 다 필요하다 — 게이트가 하트비트를 통째로 죽이면 10분 스캐빈저가 그 사람 근무를 전량 날린다.

@MainActor
private func makeGateStore(
    host: String,
    userID: String = "00000000-0000-0000-0000-000000000002"
) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let suiteName = CheckTestScratch.uniqueSuitePath()
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

/// 이 맥이 남긴 **세션 주장**(work_statuses upsert) 건수.
@MainActor
private func statusUpserts(host: String) -> Int {
    URLProtocolStub.requests(forHost: host)
        .filter { $0.url?.path == "/rest/v1/work_statuses" && $0.httpMethod == "POST" }
        .count
}

/// 이 맥이 남긴 **기기별 소유 주장**(work_status_devices upsert) 건수.
@MainActor
private func deviceClaims(host: String) -> Int {
    URLProtocolStub.requests(forHost: host)
        .filter { $0.url?.path == "/rest/v1/work_status_devices" && $0.httpMethod == "POST" }
        .count
}

@MainActor
@Suite("v0.3.45 확인된 세션만 공유 행에 닿는다")
struct V0345ConfirmedSessionGate {

    /// 핵심 음성 단언. 사고 당시의 로컬 상태를 그대로 세운다: 근무 중이라고 믿고 세션 id 도 들고 있는데
    /// **서버가 그 행을 확인해 준 적이 없다**(= INSERT 가 23505 로 거절됐다).
    @Test func 확인안된_세션은_공유행에_한건도_못_올라간다() async {
        let host = "gate-unconfirmed-test"
        let store = makeGateStore(host: host)
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

        store.startedAt = Date().addingTimeInterval(-600)
        store.currentSessionID = "943df952-292e-4d8e-8486-309f54b85f55"
        store.confirmedServerSessionID = nil          // 서버가 확인해 준 적 없다
        store.adoptedRemoteSession = false

        let statusBefore = statusUpserts(host: host)
        let deviceBefore = deviceClaims(host: host)
        await store.sendHeartbeatIfWorking()

        #expect(statusUpserts(host: host) - statusBefore == 0)
        #expect(deviceClaims(host: host) - deviceBefore == 0)
    }

    /// 짝 조건. 도장이 있어도 **그 사이 세션이 바뀌면** 무효다 — 지우기를 빠뜨려 옛 도장이 새 세션을
    /// 세탁하는 실패 모드를 구조적으로 없앤 것이 `confirmedSessionID` 의 존재 이유다.
    @Test func 도장은_그_세션에만_붙는다() {
        let store = makeGateStore(host: "gate-pairing-test")
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

        store.currentSessionID = "11111111-1111-1111-1111-111111111111"
        store.confirmedServerSessionID = "11111111-1111-1111-1111-111111111111"
        #expect(store.confirmedSessionID == "11111111-1111-1111-1111-111111111111")

        // 새 세션이 열렸다 — 옛 도장은 **자동으로** 무효가 된다(지우는 코드가 없어도).
        store.currentSessionID = "22222222-2222-2222-2222-222222222222"
        #expect(store.confirmedSessionID == nil)
    }

    /// 대문자로 들고 있어도 짝 조건이 성립해야 한다(이 저장소의 정규화 규약 — 서버는 소문자 uuid 다).
    @Test func 도장_비교는_대소문자를_넘는다() {
        let store = makeGateStore(host: "gate-canonical-test")
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

        store.currentSessionID = "AABBCCDD-0000-0000-0000-000000000001"
        store.confirmedServerSessionID = "aabbccdd-0000-0000-0000-000000000001"
        #expect(store.confirmedSessionID == "aabbccdd-0000-0000-0000-000000000001")
    }

    /// 도장 규칙 (c): 폴링이 **다른** 열린 행을 들고 오면 즉시 지운다.
    /// 2026-10-09 아이맥이 이 지움이 없어서, 내가 그 세션을 마감한 뒤에도 4시간 동안 닫힌 id 를 방송했다.
    @Test func 열린행이_다르면_도장을_지운다() {
        let userID = "00000000-0000-0000-0000-000000000002"
        let store = makeGateStore(host: "gate-rule-c-test", userID: userID)
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

        let mine = "aaaaaaaa-0000-0000-0000-000000000001"
        let theirs = "bbbbbbbb-0000-0000-0000-000000000002"
        store.startedAt = Date().addingTimeInterval(-600)
        store.currentSessionID = mine
        store.confirmedServerSessionID = mine
        store.teamMembers = [
            TeamMemberStatus(
                id: userID, name: "영식", status: .working, updatedAt: Date(),
                currentSessionStartedAt: Date().addingTimeInterval(-300),
                weeklyDurationSeconds: 0, todayDurationSeconds: 0, avatarURL: nil,
                lastSeenAt: Date(), activeSessionID: mine,
                openSession: OpenSessionFact(id: theirs, startedAt: Date().addingTimeInterval(-300))
            )
        ]

        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        #expect(store.confirmedServerSessionID != mine)
    }

    /// (c)의 반대쪽: **찢어진 읽기는 지우지 않는다.** work_statuses 와 work_sessions 는 병렬 GET 이라
    /// 상태표만 먼저 도착하면 열린 행이 비어 온다. 그때 지우면 멀쩡한 세션의 하트비트가 한 주기 끊긴다.
    /// 증거의 부재는 아무것도 증명하지 않는다.
    @Test func 찢어진_읽기는_도장을_지우지_않는다() {
        let userID = "00000000-0000-0000-0000-000000000002"
        let store = makeGateStore(host: "gate-torn-read-test", userID: userID)
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

        let mine = "aaaaaaaa-0000-0000-0000-000000000003"
        store.startedAt = Date().addingTimeInterval(-600)
        store.currentSessionID = mine
        store.confirmedServerSessionID = mine
        store.teamMembers = [
            TeamMemberStatus(
                id: userID, name: "영식", status: .working, updatedAt: Date(),
                currentSessionStartedAt: nil,      // 찢어진 읽기
                weeklyDurationSeconds: 0, todayDurationSeconds: 0, avatarURL: nil,
                lastSeenAt: Date(), activeSessionID: mine,
                openSession: nil                   // 열린 행이 아직 안 왔다
            )
        ]

        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        #expect(store.confirmedServerSessionID == mine)
    }

    /// 소유를 내려놓으면 도장도 내려놓는다. 남기면 다른 맥이 세션을 닫아도 이 맥이 닫힌 id 로 공유 행을 덮는다.
    @Test func 소유를_내려놓으면_도장도_내려놓는다() {
        let store = makeGateStore(host: "gate-release-test")
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

        store.currentSessionID = "cccccccc-0000-0000-0000-000000000004"
        store.confirmedServerSessionID = "cccccccc-0000-0000-0000-000000000004"
        store.releaseSessionOwnership()

        #expect(store.confirmedServerSessionID == nil)
        #expect(store.confirmedSessionID == nil)
    }
}
