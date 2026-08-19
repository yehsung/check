import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// 울트라 찌르기의 **스토어 계약** — 남은 횟수 미러, 안내 문구, KST 자정 리셋, 살아 있어야 하는 발사 게이트,
// 그리고 "울트라 소진이 일반 찌르기를 막지 않는다"는 대조군.
// 와이어(디코드/경로) 계약은 UltraPokeWireContractTests 가, 오버레이 격발은 UltraPokeOverlayTests 가 맡는다.
//
// **이 파일의 중심 계약은 '표시와 발사의 분리'다.** 서버가 같은 팀 대상에는 하루 한도를 적용하지 않으므로
// (ultraPokeDailyLimit 주석) "오늘 몫 소진"은 더 이상 발사 여부의 답이 아니다. 그래서 소진 미러는
// **표시 전용**이고, 화면이 "오늘 다 썼어요"라고 말하는 그 순간에도 팀원 대상 요청은 그대로 나가야 한다.
// 예전엔 여기 하루 한도 선게이트를 못 박은 테스트가 있었는데, 그 테스트가 지키던 동작이 곧 버그였다:
// 팀 밖 3발째로 한 번 거절당한 사용자가 그날 내내 팀원에게도 못 쏘는(서버는 허락하는데 클라가 요청조차
// 안 내는) 고장이다. 아래 sendUltraPokeStillRequestsWhenLocalMirrorSaysSpent 가 그 자리를 대신한다.
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

    /// 순차 응답 스텁을 문 스토어. **거절 → 허용**처럼 호출 순서에 따라 답이 달라지는 시나리오는
    /// 단일 응답 스텁(TokenBoardURLProtocol)으로는 못 만든다 — 그 스텁은 호스트당 응답 하나뿐이라
    /// 두 번째 응답을 세팅하는 사이에 첫 요청이 아직 안 돌아왔으면 무엇을 받았는지가 경합으로 갈린다.
    private func makeSequenceStore(host: String) -> WorkTimerStore {
        makeStore(host: host, session: UltraSequenceURLProtocol.session())
    }

    /// 이 호스트로 실제로 나간 ultra RPC 본문들(순서대로). 건수와 **대상**을 함께 볼 수 있어야
    /// "발사됐다"가 "다른 대상에게 발사됐다"와 구별된다.
    private func ultraBodies(host: String) -> [String] {
        UltraSequenceURLProtocol.ultraBodies(forHost: host)
    }

    // MARK: - 잔량 안내 문구(U1, 순수)

    /// v0.2.34: **하루 한도 상수가 사라졌다.** 잔량 0 안내는 그 상수에서 파생되지 않고,
    /// "다 썼다"로 끝내지도 않는다 — 회복 방법(미션)까지 같은 줄에서 말해야 한다.
    /// 0잔량 사용자가 3초를 꾹 눌러 서버 거절을 받았을 때 **실제로 읽는 문장**이 이것이다.
    @Test func ultraEmptyNoticeSaysHowToRecoverAndNotADailyLimit() {
        #expect(WorkTimerStore.ultraEmptyNotice == "울트라가 없어요 — 미션으로 충전하세요")
        // 하루 한도 어휘가 되살아나면 계약 상대가 없는 문장이 된다(서버가 그 상수를 지웠다).
        #expect(WorkTimerStore.ultraEmptyNotice.contains("하루에") == false)
        #expect(WorkTimerStore.ultraEmptyNotice.contains("미션"))
    }

    /// 모를 때는 **아무 숫자도 말하지 않는다**. 잔량 키를 안 보내는 서버(구버전)가 실제로 있고,
    /// 그때 "0개예요"라고 말하면 그건 거짓말이다.
    @Test func ultraSentNoticeAppendsBalanceOnlyWhenKnown() {
        #expect(WorkTimerStore.ultraSentNotice(balance: nil) == "울트라 찌르기 발사!")
        #expect(WorkTimerStore.ultraSentNotice(balance: 2) == "울트라 발사! 남은 울트라 2개")
        #expect(WorkTimerStore.ultraSentNotice(balance: 1) == "울트라 발사! 남은 울트라 1개")
        #expect(WorkTimerStore.ultraSentNotice(balance: 0) == "울트라 발사! 이제 0개예요")
    }

    // MARK: - 잔량은 이월된다(하루 스탬프가 없다)

    /// **자정을 넘겨도 잔량은 그대로다.** v0.2.33 의 남은 횟수는 하루 귀속이라 자정에 '모름'으로 되돌렸는데,
    /// 잔량은 이월되는 재화라 그 리셋을 그대로 두면 다음 sync 까지 배지가 조용히 빈칸이 된다.
    /// 이 테스트가 빨개지는 유일한 방법은 잔량에 하루 스탬프를 다시 붙이는 것이다.
    @Test func ultraBalanceCarriesOverAcrossKSTMidnight() {
        let store = makeStore(host: "ultra-store-quota-test", session: URLSession(configuration: .stubbed))

        store.applyUltraBalance(2)
        #expect(store.ultraBalance == 2)
        store.applyUltraBalance(1)
        #expect(store.ultraBalance == 1)
        store.applyUltraBalance(0)
        #expect(store.ultraBalance == 0)

        // 하루가 지나도 스토어는 아무 일도 하지 않는다 — 잔량을 버릴 자리가 코드에 없다.
        // (v0.2.33 은 여기서 refreshUltraQuota 가 값을 nil 로 내렸다.)
        store.applyUltraBalance(3)
        #expect(store.ultraBalance == 3)

        // 음수는 서버 버그이거나 미래 규약이다. 숫자로 말할 수 없으므로 0 으로 접는다.
        store.applyUltraBalance(-1)
        #expect(store.ultraBalance == 0)
    }

    // MARK: - 하루 한도는 게이트가 아니다(뒤집힌 계약)

    /// **소진 미러가 서 있어도 다음 시도는 요청을 낸다.** 예전엔 여기서 요청 0건을 못 박았는데, 그 동작이
    /// 곧 이번에 고친 버그다: 서버는 같은 팀 대상에 하루 한도를 적용하지 않으므로 "오늘 다 썼어요"는
    /// 발사 여부의 답이 아니다. 미러로 막으면 팀 밖 3발째로 한 번 거절당한 사용자가 그날 내내 팀원에게도
    /// 못 쏜다 — 서버는 허락하는데 클라가 요청조차 안 내서, 앱 재시작이나 KST 자정에나 풀리는 고장이다.
    ///
    /// 그리고 문구도 로컬 미러가 아니라 **서버 응답**에서 나온다: 여기선 서버가 ok 를 줬으므로 화면은
    /// 소진 안내가 아니라 발사 안내를 말하고, 쿨타임 미러도 선다(= 진짜로 나갔다는 사실이 화면에 남는다).
    @Test func sendUltraPokeStillRequestsWhenLocalMirrorSaysSpent() async throws {
        let host = "ultra-store-mirror-spent-fires-test"
        // 팀원 대상이라 서버가 허락한 발사. 팀 발사는 하루 집계에서 빠지므로 남은 값은 0 그대로 온다.
        UltraSequenceURLProtocol.enqueue([#"{"status":"ok","ultra_remaining":0}"#], forHost: host)
        let store = makeSequenceStore(host: host)
        let now = Date()
        // 화면이 "울트라 없음"이라고 말하는 바로 그 상태를 만든다.
        store.applyUltraBalance(0)
        #expect(store.ultraBalance == 0)

        store.sendUltraPoke(to: "teammate")
        await waitUntil { self.ultraBodies(host: host).count == 1 }

        // ① 요청이 실제로 나갔다(예전 계약은 여기서 0건이었다).
        #expect(ultraBodies(host: host).count == 1)
        #expect(ultraBodies(host: host).first?.contains("teammate") == true)
        // ② 문구는 미러가 아니라 서버 응답이 정한다.
        await waitUntil { store.pokeCooldownUntil["teammate"] != nil }
        #expect(store.pokeNotice == "울트라 발사! 이제 0개예요")
        #expect(store.pokeNotice != WorkTimerStore.ultraEmptyNotice)
        _ = try #require(store.pokeCooldownUntil["teammate"])
    }

    /// 같은 로컬 상태(소진 미러) + **다른 서버 응답** = 다른 문구. 위 테스트와 짝이다 —
    /// 둘을 나란히 두면 "문구가 서버에서 온다"가 값으로 드러난다(미러에서 왔다면 둘이 같았을 것이다).
    /// 거절이어도 요청은 1건 나간다: 판정의 권위가 서버라는 사실 자체가 여기서 확인된다.
    @Test func ultraSpentNoticeComesFromServerRejectionNotLocalMirror() async {
        let host = "ultra-store-mirror-spent-rejected-test"
        UltraSequenceURLProtocol.enqueue(
            [#"{"status":"ultra_used_today","ultra_remaining":0}"#],
            forHost: host
        )
        let store = makeSequenceStore(host: host)
        store.applyUltraBalance(0)

        store.sendUltraPoke(to: "outsider")
        await waitUntil { store.pokeNotice != nil }

        #expect(ultraBodies(host: host).count == 1)      // 미러가 아니라 서버가 거절했다
        #expect(store.pokeNotice == WorkTimerStore.ultraEmptyNotice)
        // 하루 한도 거절은 쿨타임을 태우지 않는다(서버가 행을 안 남긴다 — 다른 축이다).
        #expect(store.pokeCooldownUntil["outsider"] == nil)
    }

    /// **거절 → 허용 순서.** 팀 밖 대상에게 한 번 거절당한 뒤(하루 한도), 같은 날 다음 시도(팀원 대상)가
    /// 실제로 발사되는가. 이 순서가 이번 변경의 전부다 — 거절 한 번이 그날의 잠금이 되면 안 된다.
    /// 아울러 그동안 화면의 남은 횟수는 **서버 값**을 유지한다(팀 발사는 몫을 늘리지도 줄이지도 않는다).
    @Test func usedTodayRejectionDoesNotStickAndNextTargetStillFires() async throws {
        let host = "ultra-store-reject-then-allow-test"
        UltraSequenceURLProtocol.enqueue(
            [
                // ① 팀 밖 3발째 — 서버가 하루 한도로 거절.
                #"{"status":"ultra_used_today","ultra_remaining":0,"reset_after_seconds":3600}"#,
                // ② 같은 날 팀원 대상 — 서버는 팀원엔 한도를 안 본다. 집계에서 빠지므로 남은 값은 0 그대로.
                #"{"status":"ok","ultra_remaining":0}"#
            ],
            forHost: host
        )
        let store = makeSequenceStore(host: host)

        store.sendUltraPoke(to: "outsider")
        await waitUntil { store.ultraBalance != nil }
        #expect(ultraBodies(host: host).count == 1)
        #expect(store.ultraBalance == 0)                      // 표시 잔량은 0 이 됐다(그게 표시의 일이다)
        #expect(store.pokeNotice == WorkTimerStore.ultraEmptyNotice)

        store.sendUltraPoke(to: "teammate")
        let fired = await waitUntil { self.ultraBodies(host: host).count == 2 }

        // ① 선게이트에 막히지 않고 두 번째 요청이 나갔고, 그 요청의 대상이 새 대상이다.
        #expect(fired)
        let bodies = ultraBodies(host: host)
        #expect(bodies.count == 2)
        #expect(bodies.first?.contains("outsider") == true)
        #expect(bodies.last?.contains("teammate") == true)
        #expect(bodies.last?.contains("outsider") == false)
        // ② 서버가 ok 를 줬으므로 쿨타임 미러와 발사 안내가 선다.
        await waitUntil { store.pokeCooldownUntil["teammate"] != nil }
        let until = try #require(store.pokeCooldownUntil["teammate"])
        #expect(until.timeIntervalSince(Date()) > 0)
        #expect(store.pokeNotice == "울트라 발사! 이제 0개예요")
        // ③ 그동안 잔량 표시는 서버 값 그대로다.
        #expect(store.ultraBalance == 0)
        #expect(store.pokeCooldownUntil["outsider"] == nil)   // 거절당한 쪽은 쿨타임도 안 탔다
    }

    /// **표시 무회귀.** 발사 선게이트를 걷어낸 변경이 표시까지 흔들지 않았는가 —
    /// 서버가 0 을 주면 화면은 "오늘 몫은 다 썼어요"(버튼도 흐려진다), 1 을 주면 "오늘 1번 남음"이다.
    /// 미러는 사라진 게 아니라 **표시 전용으로 살아 있다**는 것이 이 테스트의 주장이다.
    @Test func ultraRemainingDisplayStillMirrorsServerValue() async {
        let zeroHost = "ultra-store-display-zero-test"
        UltraSequenceURLProtocol.enqueue([#"{"status":"ok","ultra_remaining":0}"#], forHost: zeroHost)
        let spentStore = makeSequenceStore(host: zeroHost)
        spentStore.sendUltraPoke(to: "someone")
        await waitUntil { spentStore.ultraBalance != nil }

        #expect(spentStore.ultraBalance == 0)

        let oneHost = "ultra-store-display-one-test"
        UltraSequenceURLProtocol.enqueue([#"{"status":"ok","ultra_remaining":1}"#], forHost: oneHost)
        let leftStore = makeSequenceStore(host: oneHost)
        leftStore.sendUltraPoke(to: "someone")
        await waitUntil { leftStore.ultraBalance != nil }

        #expect(leftStore.ultraBalance == 1)
    }

    // MARK: - 게이트(요청을 아예 안 내는 경로)

    /// **지우면 안 되는 게이트 둘.** 하루 한도 선게이트를 걷어냈다고 선게이트가 통째로 사라진 것이 아니다 —
    /// 로그인 안 됨/근무중 아님은 서버가 확정적으로 거절하는 조건이라 헛왕복을 낼 이유가 없고(무료 플랜),
    /// 근무중 아님은 사용자가 고칠 수 있는 조건이라 문구까지 그 자리에서 말한다.
    @Test func sendUltraPokeStillGatesSignedOutAndNotWorking() async {
        let signedOutHost = "ultra-store-signed-out-test"
        UltraSequenceURLProtocol.enqueue([#"{"status":"ok"}"#], forHost: signedOutHost)
        let signedOut = makeSequenceStore(host: signedOutHost)
        signedOut.session = nil
        signedOut.pokeNotice = nil

        signedOut.sendUltraPoke(to: "target")
        try? await Task.sleep(for: .milliseconds(80))

        #expect(ultraBodies(host: signedOutHost).isEmpty)
        // 로그인 자체가 없으면 말할 화면도 없다 — 문구도 세우지 않는다(sendPoke 와 같은 관용구).
        #expect(signedOut.pokeNotice == nil)

        let notWorkingHost = "ultra-store-seq-not-working-test"
        UltraSequenceURLProtocol.enqueue([#"{"status":"ok"}"#], forHost: notWorkingHost)
        let notWorking = makeSequenceStore(host: notWorkingHost)
        notWorking.startedAt = nil
        // 소진 미러와 무관한 게이트다 — 몫이 남아 있어도 근무중이 아니면 안 나간다.
        notWorking.applyUltraBalance(2)

        notWorking.sendUltraPoke(to: "target")
        try? await Task.sleep(for: .milliseconds(80))

        #expect(ultraBodies(host: notWorkingHost).isEmpty)
        #expect(notWorking.pokeNotice == "근무 중일 때만 콕 찌를 수 있어요")
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

    /// **잔량 0 은 발사를 막지 않는다.** 잔량은 미션으로 그날 중에 늘어나므로, 0을 보고 선게이트를 걸면
    /// 3시간을 채워 서버 잔량이 1이 된 사용자가 앱을 재시작하기 전까지 못 쏜다(v0.2.30 구버전의 그 고장).
    @Test func zeroBalanceDoesNotBlockTheRequest() async {
        let host = "ultra-store-yesterday-test"
        let store = makeStore(host: host, session: URLSession(configuration: .stubbed))
        store.applyUltraBalance(0)

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
        await waitUntil { store.ultraBalance != nil }

        #expect(store.ultraBalance == 1)
        #expect(store.pokeNotice == "울트라 발사! 남은 울트라 1개")
        let until = try #require(store.pokeCooldownUntil["target"])
        // 발사 시각 기준 하한만 엄격히 본다(상한은 병렬 실행 지연을 흡수) — 검증 대상은 '60초를 미러링했는가'.
        #expect(until.timeIntervalSince(sentAt) >= 60)
        #expect(until.timeIntervalSince(sentAt) <= 60 + 300)

        // 두 번째 발사: 서버가 남은 0 을 알려 준다.
        TokenBoardURLProtocol.setResponse(#"{"status":"ok","ultra_remaining":0}"#, forHost: host)
        store.sendUltraPoke(to: "target2")
        await waitUntil { store.ultraBalance == 0 }

        #expect(store.ultraBalance == 0)
        #expect(store.pokeNotice == "울트라 발사! 이제 0개예요")
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
        await waitUntil { store.ultraBalance != nil }

        #expect(store.ultraBalance == 0)
        #expect(store.pokeCooldownUntil["target"] == nil)
        #expect(store.pokeNotice == WorkTimerStore.ultraEmptyNotice)
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

        #expect(store.ultraBalance == nil)        // 서버가 말하지 않았으니 모름 유지(재화는 안 탔다)
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
        #expect(store.ultraBalance == nil)
    }

    /// 미지 status(마이그레이션 미적용 서버가 늘릴 수 있는 값)는 .invalid 로 접히고 몫을 태우지 않는다.
    @Test func sendUltraPokeUnknownStatusKeepsQuota() async {
        let host = "ultra-store-unknown-status-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"target_saturated"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        store.sendUltraPoke(to: "target")
        await waitUntil { store.pokeNotice != nil }

        #expect(store.pokeNotice == "지금은 찌를 수 없어요")
        #expect(store.ultraBalance == nil)
    }

    // MARK: - 대조군

    /// **울트라 소진은 일반 찌르기를 막지 않는다.** 두 게이트가 한 몸이 되는 순간(예: 선게이트를 sendPoke
    /// 로 옮기는 '정리') 사용자는 하루 두 번 이후 아무도 못 찌르게 된다 — 그 회귀의 유일한 방어선이다.
    @Test func ultraExhaustionDoesNotBlockNormalPoke() async throws {
        let host = "ultra-store-control-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"ok"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())
        store.applyUltraBalance(0)
        store.pokeNotice = "이전 안내"

        store.sendPoke(to: "target")
        await waitUntil { store.pokeCooldownUntil["target"] != nil }

        #expect(store.pokeCooldownUntil["target"] != nil)   // 일반 찌르기는 정상 발사됐다
        #expect(store.pokeNotice == nil)                    // ok → 안내 해제
        // 일반 찌르기는 울트라 장부를 건드리지 않는다(응답에 잔량 키가 없어도 잔량을 흔들지 않는다).
        #expect(store.ultraBalance == 0)
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
        store.applyUltraBalance(0)
        store.missions = [MissionProgress(kind: .todayThreeHours, progress: 1, claimedToday: true, cappedToday: false, detail: "x")]
        store.missionsLoaded = true
        store.streakDays = 5
        store.isUltraPanelVisible = true

        store.clearPersistedSession()

        #expect(store.ultraBalance == nil)
        #expect(store.missions.isEmpty)
        #expect(store.missionsLoaded == false)
        #expect(store.streakDays == 0)
        #expect(store.isUltraPanelVisible == false)
    }
}

// MARK: - 뷰 계층: 표시와 발사의 분리

/// 콕찌르기 **뷰 계층**의 울트라 회귀. 여기까지 와야 "표시와 발사의 분리"가 실제로 지켜진다 —
/// 스토어가 아무리 옳아도 화면이 `if canUltra` 로 한 번 더 막으면 사용자에게는 고쳐진 것이 없다.
/// 그 절반만 고쳐진 상태가 이 저장소에서 실제로 일어났고(스토어 선게이트만 제거된 판), 그때 이 계층엔
/// 테스트가 하나도 없었다.
///
/// **왜 제스처를 직접 흉내 내지 않는가**: 3초 홀드는 DragGesture + @State + Task.sleep 이라, 진짜로
/// 누르려면 창을 띄우고 CGEvent 를 쏴야 한다. 이 저장소는 테스트가 데스크톱에 창을 도배한 사고가 있어
/// 그 길이 막혀 있고, 이벤트 타이밍은 잠긴 맥에서 스로틀링으로 거짓 실패한다. 그래서 이 스위트는 두 축으로 나눈다:
///  ① 실제 뷰 트리에서 **값**을 읽어 표시가 소진을 말하는지 + 막는 콜백이 없는지 확인하고,
///  ② 3초 끝의 발사 분기(private struct 안 Task — 값으로도 렌더로도 안 잡힌다)는 **원문 소스 불변식**으로 못 박는다.
/// 발사가 실제로 나가는지는 스토어 계층(UltraPokeStoreTests)이 요청 건수로 증명한다 — 세 축이 모여야
/// "절반만 고쳐진 판"이 초록으로 통과하지 못한다.
@MainActor
@Suite struct UltraPokeViewFireTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "check-ultra-view-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 콕찌르기 패널이 열린 채 **오늘 몫이 소진된** 스토어. 화면은 "다 썼어요"라고 말하는 상태다.
    private func spentPanelStore(host: String, now: Date) -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: UltraSequenceURLProtocol.session()
        )
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: makeDefaults()
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.startedAt = now
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
        store.displayNow = now
        // 팀에 소속돼 있어야 메인 콘텐츠(그 안의 콕찌르기 패널)가 그려진다.
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.teamName = "아잉팀"
        store.pokeDirectory = [
            PokeDirectoryEntry(userID: "teammate", name: "영식", avatarURL: nil, isWorking: true)
        ]
        store.pokeDirectoryLoaded = true
        store.isPokePanelVisible = true
        // 서버가 0 을 알려 준 상태 = 화면이 "울트라 없음"이라고 말하는 그 조건.
        store.applyUltraBalance(0)
        return store
    }

    /// SwiftUI 뷰 **값** 트리에서 타입 이름으로 노드를 찾는다. 패널이 private 타입이라 이름으로 잡는다.
    /// 이름은 **정확히** 맞춰야 한다 — `contains` 로 잡으면 `ModifiedContent<PokePanel, _FrameLayout>` 같은
    /// 포장지에서 멈춰, 자식이 content/modifier 뿐인 노드를 패널이라 착각한다(실제로 그렇게 한 번 헛짚었다).
    /// 클래스로는 내려가지 않는다(스토어는 뷰 트리가 아니고 순환이 있다). 예산은 폭주 방지용이다.
    private func findViewNode(named typeName: String, in value: Any, budget: inout Int) -> Mirror? {
        guard budget > 0 else { return nil }
        budget -= 1
        let mirror = Mirror(reflecting: value)
        if String(describing: mirror.subjectType) == typeName { return mirror }
        guard mirror.displayStyle != .class else { return nil }
        for child in mirror.children {
            if let found = findViewNode(named: typeName, in: child.value, budget: &budget) { return found }
        }
        return nil
    }

    private func child(_ label: String, of mirror: Mirror) -> Any? {
        mirror.children.first { $0.label == label }?.value
    }

    // MARK: - 실제 뷰 트리에서 읽는 표시 계약

    /// **소진 상태의 진짜 뷰 트리**를 열어 표시용 값들을 읽는다: 패널은 canUltra=false 와
    /// "오늘 몫은 다 썼어요"를 받고(= 힌트·툴팁이 소진을 말한다), **막는 콜백은 아예 들고 있지 않다**.
    ///
    /// 이게 렌더 테스트(픽셀 비교)와 다른 점: 픽셀은 문구가 소진이라고 말하는지 못 읽고, 순수 함수 테스트는
    /// 그 함수에 **어떤 값이 들어가는지**를 못 본다. 여기서는 실제 CheckMenuView 가 만든 값이 대상이라
    /// 호출부가 미러를 잘못 읽는 회귀(예: ultraRemainingToday 를 KST 대조 없이 직접 넘기는 판)도 함께 잡힌다.
    ///
    /// **콜백은 부르지 않는다.** Mirror 로 꺼낸 클로저를 `as? (String) -> Void` 로 캐스팅해 호출하면
    /// 인자가 재추상화 썽크를 잘못 타 **메모리 쓰레기**가 넘어간다(실측: p_to 자리에 `"O¹o\u{01}\0\0\0"`).
    /// 초록/빨강이 갈리는 문제가 아니라 미정의 동작이라, 발사 경로는 부르지 않고 스토어 테스트
    /// (sendUltraPokeStillRequestsWhenLocalMirrorSaysSpent)와 소스 불변식 두 축으로 지킨다.
    @Test func spentPanelKeepsSpentDisplayAndCarriesNoBlockingCallback() throws {
        // 이 테스트는 요청을 내지 않는다(값만 읽는다) — 호스트는 스토어 조립에만 쓰인다.
        let host = "ultra-view-spent-display-test"
        let now = Date()
        let store = spentPanelStore(host: host, now: now)

        // 전제: 화면이 소진을 말하는 상태다(이게 아니면 아래 단언들은 아무것도 증명하지 못한다).
        #expect(store.ultraBalance == 0)

        var budget = 400_000
        let panel = try #require(
            findViewNode(named: "PokePanel", in: CheckMenuView(store: store).body, budget: &budget),
            "콕찌르기 패널을 뷰 트리에서 못 찾았다 — 패널이 안 그려지거나 트리 모양이 바뀌었다"
        )

        // v0.2.34: 패널이 받는 표시용 사실이 canUltra(Bool) → ultraBalance(Int?) 로 바뀌었다.
        // **Optional 인 것이 계약의 일부다** — nil("아직 모름")을 0("없다")으로 접으면 앱을 켠 직후
        // 수 초 동안 화면이 "울트라 없음"이라는 만들어 낸 사실을 말한다.
        let balanceChild = try #require(child("ultraBalance", of: panel), "패널이 잔량을 표시용으로 받아야 한다.")
        // ★ `as? Int?` 로는 **못 잡는다**: Any 에 담긴 Int 를 Int? 로 캐스팅하면 암묵적으로 감싸져 성공한다
        //   (실측: 패널을 비옵셔널 Int 로 좁힌 뮤턴트가 그 단언을 통과했다). 런타임 타입을 직접 읽는다.
        #expect(
            String(describing: type(of: balanceChild)) == "Optional<Int>",
            """
            패널이 받는 잔량이 Optional 이 아니다. nil("아직 모름")을 0("없다")으로 접으면
            앱을 켠 직후 수 초 동안 화면이 "울트라 없음"이라는 만들어 낸 사실을 말한다.
            """
        )
        let balance = try #require(balanceChild as? Int?, "잔량은 Int? 다 — 비옵셔널로 좁히면 '모름'이 사라진다.")
        #expect(balance == 0, "서버가 0 을 알려 준 상태에서는 표시용 잔량이 0 이어야 힌트·툴팁이 충전 경로를 말한다.")
        // 그 값이 실제로 만드는 문구를 여기서 확인한다(순수 함수와 호출부를 한 줄로 잇는다).
        #expect(UltraBalanceText.hint(balance: balance) == UltraBalanceText.empty)
        #expect(UltraBalanceText.rowTooltip(balance: balance).contains("미션으로 충전"))
        // 잔량 배지 탭 경로가 패널에 달려 있다 — 0개인 사람이 충전 방법에 닿는 유일한 문이다.
        #expect(
            panel.children.contains { $0.label == "onOpenUltraPanel" },
            "잔량 배지 탭 콜백이 사라졌다. 0개인 사용자가 '어떻게 채우죠?'의 답에 닿을 길이 없어진다."
        )
        // 발사 경로는 살아 있다(값을 부르지는 않는다 — 위 주석의 이유).
        #expect(panel.children.contains { $0.label == "onUltra" }, "울트라 발사 콜백은 소진 상태에서도 그대로 달려 있어야 한다.")
        // 막는 콜백은 아예 사라졌다 — 남겨 두면 다음 사람이 "있으니 쓰자"고 게이트를 되살린다.
        #expect(
            panel.children.contains { $0.label == "onUltraBlocked" } == false,
            "막는 콜백이 패널에 되살아났다. 하루 한도 판정은 서버 한 곳뿐이다(표시와 발사의 분리)."
        )
    }

    /// **울트라 화면이 열리면 토큰 소모량 행이 사라진다** — 다른 네 하위 패널과 같은 규약이다.
    ///
    /// 이걸 빠뜨리면(`isSubPanelOpen` 에 새 플래그를 안 더하면) 그 행이 패널과 함께 그려져 창이
    /// 700pt 상한을 넘고 **푸터가 화면 밖으로 잘린다** — 그 순간 사용자는 로그아웃할 방법을 잃는다.
    /// 대조군(홈 화면에서는 그 행이 실재한다)이 함께 있어야 이 단언이 공허해지지 않는다.
    @Test func openingTheUltraPanelHidesTheTokenUsageRowLikeEveryOtherSubPanel() throws {
        let now = Date()
        let home = spentPanelStore(host: "ultra-subpanel-home", now: now)
        home.isPokePanelVisible = false          // 홈(팀 카드) 화면
        var homeBudget = 400_000
        #expect(
            findViewNode(named: "CheckTokenUsageRow", in: CheckMenuView(store: home).body, budget: &homeBudget) != nil,
            "대조군 실패: 홈 화면에 토큰 소모량 행이 없다 — 이 픽스처로는 아래 단언이 아무것도 증명하지 못한다."
        )

        let ultra = spentPanelStore(host: "ultra-subpanel-open", now: now)
        ultra.isPokePanelVisible = false
        ultra.isUltraPanelVisible = true
        var panelBudget = 400_000
        #expect(
            findViewNode(named: "UltraPanel", in: CheckMenuView(store: ultra).body, budget: &panelBudget) != nil,
            "울트라 화면이 아예 안 그려졌다 — content 의 분기가 빠졌다."
        )
        var rowBudget = 400_000
        #expect(
            findViewNode(named: "CheckTokenUsageRow", in: CheckMenuView(store: ultra).body, budget: &rowBudget) == nil,
            "isSubPanelOpen 이 울트라 화면을 안 센다 — 토큰 행이 함께 그려져 창이 상한을 넘고 푸터가 잘린다."
        )
    }

    // MARK: - 발사 분기(소스 불변식)

    /// **충전 버튼은 하루 한도 사실을 하나도 모른다** — 그래서 그걸로 게이트를 만들 수가 없다.
    ///
    /// 3초 홀드의 마지막 갈림길은 private struct 안의 Task 라 값으로도 렌더로도 잡히지 않는다(창을 띄우고
    /// 3초를 실제로 눌러야 한다 — 이 저장소가 금지한 길이다). 그래서 여기서는 **그 갈림길이 존재할 수 없음**을
    /// 못 박는다: 버튼이 canUltra/onUltraBlocked/소진 미러를 아예 받지 않으면 `if canUltra` 를 되살리는 변경은
    /// 이 테스트를 먼저 빨갛게 만든다(선언을 다시 추가해야 하므로).
    ///
    /// 주석은 걷어내고 **코드만** 본다 — 위 설계를 설명하는 주석이 그 단어들을 정당하게 포함하기 때문이다.
    @Test func chargeButtonHoldsNoQuotaFactsSoItCannotGateTheFire() throws {
        let source = try menuViewSource()
        let fire = Self.codeOnly(try Self.functionBody("private func beginCharge()", in: source))
        let button = Self.codeOnly(try Self.declaration("private struct PokeChargeButton: View {", in: source))

        // ① 발사 지점: 3초가 끝나면 조건 없이 나간다.
        let fireLines = fire
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("onUltra()") }
        #expect(
            fireLines == ["onUltra()"],
            """
            beginCharge 의 3초 홀드 완료는 **조건 없이** onUltra() 를 불러야 한다.
            표시와 발사를 분리한다: canUltra 는 표시 전용(제목 행 힌트·행 툴팁)이고, 여기서 게이트로 쓰면
            서버가 팀원에게 허용하는 발사가 클라에서 막힌다 — 팀 밖 대상에게 한 번 거절당해 소진 미러가 서면
            그날 내내 팀원 울트라가 요청조차 나가지 않는다(앱 재시작이나 KST 자정에나 풀린다).
            하루 한도 판정의 권위는 서버 ultra_poke_user 한 곳뿐이다.
            """
        )
        #expect(
            fire.contains("canUltra") == false,
            """
            beginCharge 본문이 canUltra 를 다시 읽고 있다 = 발사 게이트가 되살아났다는 뜻이다.
            canUltra 는 '오늘 팀 밖 몫이 남았는가'라는 **표시용 사실**일 뿐, 발사 여부의 답이 아니다
            (서버는 같은 팀 대상에 하루 한도를 적용하지 않는다 — WorkTimerStore.ultraPokeDailyLimit 주석).
            """
        )

        // ② 재료 자체를 없애 둔 것이 이 설계의 요점이다 — 버튼이 몫을 모르면 몫으로 게이트를 만들 수 없다.
        #expect(
            button.contains("canUltra") == false,
            "PokeChargeButton 은 하루 한도 사실을 아예 받지 않는다(안 가진 값으로는 게이트를 만들 수 없다)."
        )
        #expect(
            button.contains("onUltraBlocked") == false,
            """
            막는 콜백이 되살아났다. 서버 거절(.ultraUsedToday)이 스토어에서 같은 문장
            (WorkTimerStore.ultraEmptyNotice)을 세우므로 사용자가 보는 결과는 왕복 한 번 뒤의 같은 문구다 —
            클라에 두 번째 판정을 만들 이유가 없다.
            """
        )
        #expect(button.contains("isUltraPokeSpent") == false, "소진 미러는 표시 계층의 값이다. 버튼이 읽으면 그게 게이트가 된다.")
        #expect(button.contains("ultraSpentNotice") == false, "소진 안내는 서버 응답을 받은 스토어가 세운다(문구가 두 곳으로 갈라지지 않게).")
        #expect(button.contains("ultraRemaining") == false, "남은 횟수도 표시용이다 — 버튼이 알면 다음 사람이 그걸로 다시 막는다.")
        // ★ blocker(UI #4) — 개명이 이 목록을 **어휘 맹목**으로 만든다. v0.2.34 에서 사실의 이름이
        //   canUltra/isUltraPokeSpent 에서 ultraBalance 로 바뀌었고, 잔량은 예전 이름보다 훨씬 더
        //   "이걸로 막고 싶다"는 유혹이 크다(0이면 못 쏘는 게 당연해 보인다). 새 이름을 목록에 넣지 않으면
        //   `if ultraBalance > 0` 을 버튼에 심어도 위 단언이 전부 초록이다.
        #expect(button.contains("ultraBalance") == false, "잔량도 표시용이다 — 미션으로 그날 중에 늘어나므로 버튼이 그걸로 막으면 재시작 전까지 못 쏜다.")
        #expect(button.contains("ultraEmptyNotice") == false, "잔량 0 안내는 서버 응답을 받은 스토어가 세운다(문구가 두 곳으로 갈라지지 않게).")
    }

    /// **툴팁은 그대로 잔량을 말한다 — 다만 문장이 바뀌었다(삭제가 아니라 재조준이다).**
    ///
    /// 발사 게이트를 걷어낸 변경이 표시까지 걷어내면, 잔량이 없는 날 화면에는 아무 단서도 남지 않는다
    /// (3초를 눌러 서버 거절을 받기 전까지 알 방법이 없다). 그래서 행은 여전히 잔량을 읽는다.
    ///
    /// 문장이 바뀐 이유: "울트라는 오늘 다 썼어요"는 **하루 몫 시절의 말**이다. 이제 울트라는 재화라
    /// 기다려도 안 차고, 미션을 해야만 찬다 — "다 썼다"는 자정을 기다리게 만드는 거짓말이다.
    @Test func rowTooltipSpeaksBalanceAndTheWayToRefill() throws {
        let source = try menuViewSource()
        let row = Self.codeOnly(try Self.declaration("private struct PokeDirectoryRowView: View {", in: source))

        #expect(
            row.contains("UltraBalanceText.rowTooltip"),
            "행 툴팁은 잔량으로 갈린다 — 표시는 남기고 발사만 서버에 맡긴 것이 이번 변경이다."
        )
        #expect(row.contains("onUltraBlocked") == false, "행도 막는 콜백을 더 이상 나르지 않는다.")

        // 하루 몫 시절의 어휘가 **코드로** 되살아나지 않았는가. 주석은 걷어낸 뒤라 설계 설명은 무죄다.
        // 범위를 행 하나로 좁히지 않고 파일 전체(코드)로 넓힌 이유: 옛 문구가 어디로든 슬쩍
        // 되돌아오면 화면 전체가 다시 "기다리면 찬다"고 말하기 때문이다.
        let code = Self.codeOnly(source)
        for banned in ["오늘 다 썼", "울트라 소진", "번 남음", "하루에"] {
            #expect(
                code.contains(banned) == false,
                """
                v0.2.34 에서 사라진 하루 몫 어휘 "\(banned)" 가 CheckMenuView 코드에 되살아났다.
                울트라는 재화라 자정에 차지 않는다 — 기다리라고 말하는 문장은 전부 거짓말이다.
                """
            )
        }
    }

    /// 잔량 문구가 **하루 몫의 어휘를 쓰지 않는다**(순수 — 값으로 검증한다).
    @Test func ultraBalanceTextNeverSaysDailyQuota() {
        #expect(UltraBalanceText.hint(balance: 0) == "미션으로 충전")
        #expect(UltraBalanceText.hint(balance: 3) == UltraBalanceText.discover)
        // 모를 때는 아무 숫자도 만들지 않는다 — 틀린 숫자를 보여 주느니 발견성 문구를 그대로 둔다.
        #expect(UltraBalanceText.hint(balance: nil) == UltraBalanceText.discover)
        // nil 은 0 이 아니다. 이 등식이 깨지면 앱을 켠 직후 수 초 동안 "없다"는 거짓말이 화면에 뜬다.
        #expect(UltraBalanceText.hint(balance: nil) != UltraBalanceText.hint(balance: 0))
        // 툴팁도 같은 규칙이다(모르면 허용으로 읽는다 — 판정은 서버다).
        #expect(UltraBalanceText.rowTooltip(balance: nil) == UltraBalanceText.rowTooltip(balance: 1))
        #expect(UltraBalanceText.rowTooltip(balance: 0) != UltraBalanceText.rowTooltip(balance: 1))

        let everything = [
            UltraBalanceText.empty,
            UltraBalanceText.discover,
            UltraBalanceText.rowTooltip(balance: 0),
            UltraBalanceText.rowTooltip(balance: 3),
            UltraBalanceText.badgeHelp(balance: 0),
            UltraBalanceText.badgeHelp(balance: nil),
        ]
        for text in everything {
            for banned in ["오늘", "남음", "소진", "하루"] {
                #expect(text.contains(banned) == false, "\"\(text)\" 가 하루 몫 어휘 \"\(banned)\" 를 쓴다.")
            }
        }
        // 배지 숫자는 음수를 만들지 않는다(서버 버그가 화면에 "-1개"로 새지 않게).
        #expect(UltraBalanceText.badge(balance: -3) == "0")
    }

    // MARK: - 소스 읽기 헬퍼

    /// 검사 대상 **원문**을 읽는다(손으로 베낀 복제본을 검사하면 원본이 바뀌어도 초록으로 남는다).
    /// 파일을 못 찾으면 **던진다** — 조용히 통과하면 경로가 바뀐 날 방어망이 사라진 것을 아무도 모른다.
    private func menuViewSource() throws -> String {
        // #filePath = <repo>/Tests/checkTests/UltraPokeTests.swift → 세 번 올라가면 저장소 루트다.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("Sources/check/CheckMenuView.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UltraSourceContractError.sourceUnreadable(url.path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 함수 선언 한 줄부터 **중괄호 깊이가 0 으로 돌아올 때까지**(= 본문 전체)를 잘라낸다.
    /// 깊이는 주석을 걷어낸 코드로만 센다(주석 속 중괄호가 깊이를 망치지 않게).
    private static func functionBody(_ header: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(header) }) else {
            throw UltraSourceContractError.declarationNotFound(header)
        }
        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            collected.append(line)
            let code = codeOnly(line)
            depth += code.filter { $0 == "{" }.count
            depth -= code.filter { $0 == "}" }.count
            if depth == 0, collected.count > 1 || code.contains("}") {
                return collected.joined(separator: "\n")
            }
        }
        throw UltraSourceContractError.declarationNotFound(header)
    }

    /// 선언 한 줄부터 **열 0 의 닫는 중괄호**까지를 잘라낸다(이 파일의 최상위 타입은 전부 그렇게 끝난다).
    private static func declaration(_ header: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(header) }) else {
            throw UltraSourceContractError.declarationNotFound(header)
        }
        guard let endOffset = lines[(start + 1)...].firstIndex(where: { $0 == "}" }) else {
            throw UltraSourceContractError.declarationNotFound(header)
        }
        return lines[start...endOffset].joined(separator: "\n")
    }

    /// 주석을 걷어낸 코드만. 설계를 설명하는 주석이 금지 단어를 정당하게 포함하므로 필수다.
    private static func codeOnly(_ swift: String) -> String {
        swift
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }
}

private enum UltraSourceContractError: Error {
    /// 검사할 선언을 못 찾았다. 이름이 바뀌었으면 **테스트를 함께 옮겨라** — 못 찾은 것을 통과로 접으면
    /// 그 순간 방어망이 사라지고, 다음 사람이 게이트를 되살려도 스위트는 초록이다.
    case declarationNotFound(String)
    /// 소스 파일 자체를 못 읽었다(경로 규약이 바뀐 경우). 같은 이유로 조용히 통과시키지 않는다.
    case sourceUnreadable(String)
}

// MARK: - 순차 응답 스텁(거절 → 허용)

/// 호스트별 **응답 큐**와 요청 로그를 들고 있는 울트라 전용 URLProtocol.
///
/// 기존 스텁 둘로는 이 파일의 새 계약을 못 세운다:
///  · URLProtocolStub 은 요청을 세지만 ultra RPC 에 응답을 등록할 자리가 없어 **빈 본문**이 돌아간다 —
///    그러면 스토어는 디코드 실패 catch 로 떨어져 "연결이 불안정해요"만 남고, 서버 응답이 문구를 가른다는
///    주장(이 파일의 중심)이 아예 검증되지 않는다.
///  · TokenBoardURLProtocol 은 호스트당 응답이 하나뿐이라 '거절 → 허용' 순서를 만들 수 없다.
///    두 번째 응답을 세팅하는 사이 첫 요청이 아직 안 돌아왔으면 무엇을 받았는지가 경합으로 갈린다.
///
/// 큐는 **ultra RPC 경로에만** 적용한다. 다른 경로(디렉토리 재조회 등)가 끼어들어 답을 한 칸 먹어 버리면
/// 순서 시나리오가 조용히 어긋나기 때문이다. 큐가 마르면 마지막 답을 반복한다.
final class UltraSequenceURLProtocol: URLProtocol {
    static let ultraPath = "/rest/v1/rpc/ultra_poke_user"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var queuesByHost: [String: [String]] = [:]
    private nonisolated(unsafe) static var lastByHost: [String: String] = [:]
    private nonisolated(unsafe) static var ultraBodiesByHost: [String: [String]] = [:]

    /// 이 호스트의 응답을 **순서대로** 등록한다(호스트별 로그도 함께 비운다 — 테스트마다 고유 호스트를 쓴다).
    static func enqueue(_ responses: [String], forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        queuesByHost[host] = responses
        lastByHost[host] = responses.last ?? "{}"
        ultraBodiesByHost[host] = []
    }

    /// 이 호스트로 나간 ultra RPC 요청 본문들(순서대로).
    static func ultraBodies(forHost host: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return ultraBodiesByHost[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UltraSequenceURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// URLSession 이 httpBody 를 스트림으로 바꿔 넘겨도 읽을 수 있게 스트림 폴백을 둔다
    /// (다른 스텁들과 같은 관용구 — 여기서 본문을 못 읽으면 '어느 대상에게 나갔는가'가 검증 불가가 된다).
    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        // **hasBytesAvailable 로 돌지 않는 이유**: 그 값은 '아직 안 왔다'와 '끝났다'를 구별하지 못한다.
        // URLSession 이 본문을 바운드 스트림으로 바꿔 넘기므로, 생산자가 첫 바이트를 넣기 전에 물어보면
        // false 가 돌아와 본문이 통째로 빈 문자열로 기록된다 — 그러면 "어느 대상에게 나갔는가" 단언이
        // 무작위로 빨개진다(이 파일의 뷰 테스트에서 실제로 재현됐다). read 는 바이트가 올 때까지 블록하고
        // EOF 에서 0 을 주므로, 그걸 종료 조건으로 삼는 편이 유일하게 결정적이다.
        // 상한은 폭주 방지용이다(이 스텁이 보는 본문은 RPC 인자 몇 바이트뿐이다).
        while data.count < 64 * 1024 {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let isUltra = request.url?.path == Self.ultraPath
        let body = Self.bodyText(from: request)

        Self.lock.lock()
        let json: String
        if isUltra {
            Self.ultraBodiesByHost[host, default: []].append(body)
            var queue = Self.queuesByHost[host] ?? []
            if queue.isEmpty {
                json = Self.lastByHost[host] ?? "{}"
            } else {
                json = queue.removeFirst()
                Self.queuesByHost[host] = queue
            }
        } else {
            json = "[]"
        }
        Self.lock.unlock()

        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// ─────────────────────────────────────────────────────────────────────────────────────
// MARK: - 관리자 무제한(v0.2.35)
//
// 사실관계: 서버 `ultra_poke_user` 는 `profiles.role = 'admin'` 이면 잔량 검사를 건너뛰고 즉시 발사한다
// (20260809160000 이 세우고 20260814015000 이 role 조회로 바꾼 뒤 계속). 그런데 화면은 잔량 숫자(⚡N)를
// 그대로 그렸다 — 관리자에게 그 숫자는 아무 뜻도 없다(쓰지 않으니 줄지도 않는다).
//
// **이 스위트가 지키는 것은 셋이다:**
//  (가) 그 사실을 **서버가 말해 준다**. 클라는 role 을 추측하지 않는다 — 응답의 `unlimited` 불린 하나가
//       유일한 입력이고, 그 값이 없는 서버(마이그레이션 전)에서도 디코드가 살아야 한다.
//  (나) 화면이 그 사실을 **말한다**. 배지는 숫자 대신 기호 하나, 울트라 화면은 "무제한".
//  (다) **관리자가 아닌 사람에게는 지금과 완전히 같다**(회귀 0). 픽셀까지 같아야 한다.
@MainActor
@Suite struct UltraUnlimitedFlagTests {

    // MARK: - 픽스처

    /// 서버 응답 한 벌. `unlimited` 만 갈아 끼울 수 있게 조각으로 만든다 —
    /// 나머지 키를 손으로 두 번 적으면 "구버전 응답"과 "신버전 응답"이 다른 이유가 흐려진다.
    private static func walletJSON(unlimited: String?) -> String {
        let flag = unlimited.map { "\"unlimited\":\($0)," } ?? ""
        return """
        {"status":"ok",\(flag)"balance":3,"balance_cap":5,"daily_floor":1,"day":"2026-08-20",
         "floor_applied":false,
         "missions":[{"key":"work3h","kst_day":"2026-08-20","target_seconds":10800,
                      "progress_seconds":9321,"claimed":false,"granted_now":false,"capped":false}],
         "worked_seconds_closed":8121,"worked_seconds_open":1200,
         "streak_days":5,"streak_includes_today":true,"measured_at":1755561234}
        """
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "check-ultra-unlimited-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeService(host: String) -> SupabaseWorkService {
        SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: UltraWalletSyncURLProtocol.session()
        )
    }

    private func makeStore(host: String) -> WorkTimerStore {
        let store = WorkTimerStore(
            service: makeService(host: host),
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: makeDefaults()
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        return store
    }

    // MARK: - (가) 서버가 말해 준다 — 실제 HTTP → 실제 디코더 왕복

    /// **이 마이그레이션 이전 서버**(키가 아예 없다)에서도 지갑 동기화가 살아 있는가.
    ///
    /// 이 테스트 하나가 `unlimited` 를 Optional 로 둔 이유 전부다. 비옵셔널로 바꾸면(= `decode` 로
    /// 바꾸면) 이 응답에서 디코드가 **통째로 throw** 되고, 잔량·미션·스트릭이 함께 사라진다 —
    /// 화면은 "못 읽었어요"를 띄우는데 실제 원인은 "곁가지 키 하나가 없다"이다.
    /// 그래서 나머지 필드까지 값으로 확인한다: 통째로 죽었는지 곁가지만 없는지를 이 줄들이 가른다.
    @Test func serverWithoutTheFlagStillDecodesAndMeansNotUnlimited() async throws {
        let host = "ultra-unlimited-old-server-test"
        UltraWalletSyncURLProtocol.stub(Self.walletJSON(unlimited: nil), forHost: host)

        let response = try await makeService(host: host).syncUltraWallet(accessToken: "t")

        // 곁가지가 없다고 본체가 죽지 않았다.
        #expect(response.isOK)
        #expect(response.balance == 3)
        #expect(response.balanceCap == 5)
        #expect(response.missions.count == 1)
        #expect(response.streakDays == 5)
        // 그리고 **모른다**. 모를 때의 해석은 "무제한이 아니다" 한 쪽뿐이다 —
        // 반대로 접으면 구버전 서버에 붙은 전원의 화면이 "무제한"이라고 거짓말한다.
        #expect(response.unlimited == nil)
        #expect(response.isUnlimited == false)
    }

    /// 신버전 서버의 두 값이 그대로 실려 온다. false 쪽이 **음성 대조군**이다 —
    /// 이게 없으면 `isUnlimited` 가 상수 true 로 굳어도 위 테스트만으로는 못 잡는다.
    @Test func serverFlagRidesThroughTheRealDecoderBothWays() async throws {
        let onHost = "ultra-unlimited-admin-server-test"
        UltraWalletSyncURLProtocol.stub(Self.walletJSON(unlimited: "true"), forHost: onHost)
        let admin = try await makeService(host: onHost).syncUltraWallet(accessToken: "t")
        #expect(admin.unlimited == true)
        #expect(admin.isUnlimited)
        // 무제한이어도 잔량 키는 그대로 온다(서버가 빼면 클라가 깨진다 — 마이그레이션 단언이 그걸 못 박는다).
        #expect(admin.balance == 3)

        let offHost = "ultra-unlimited-member-server-test"
        UltraWalletSyncURLProtocol.stub(Self.walletJSON(unlimited: "false"), forHost: offHost)
        let member = try await makeService(host: offHost).syncUltraWallet(accessToken: "t")
        #expect(member.unlimited == false)
        #expect(member.isUnlimited == false)
    }

    /// `status: "invalid"`(비로그인)는 status 외의 키를 하나도 보내지 않는다 — 그 응답에서도
    /// 디코드가 살아야 하고, 무제한은 **거짓**이어야 한다(모르면 무제한이 아니다).
    @Test func invalidResponseNeitherThrowsNorClaimsUnlimited() async throws {
        let host = "ultra-unlimited-invalid-server-test"
        UltraWalletSyncURLProtocol.stub(#"{"status":"invalid"}"#, forHost: host)
        let response = try await makeService(host: host).syncUltraWallet(accessToken: "t")
        #expect(response.isOK == false)
        #expect(response.unlimited == nil)
        #expect(response.isUnlimited == false)
    }

    // MARK: - 스토어가 그 값을 나른다

    @Test func storeCarriesTheServerFlagAndNeverInventsIt() async throws {
        let host = "ultra-unlimited-store-test"
        let store = makeStore(host: host)
        #expect(store.ultraUnlimited == false, "기본값은 '아직 모른다'의 안전한 쪽이어야 한다.")

        UltraWalletSyncURLProtocol.stub(Self.walletJSON(unlimited: "true"), forHost: host)
        store.applyUltraWallet(try await makeService(host: host).syncUltraWallet(accessToken: "t"))
        #expect(store.ultraUnlimited)
        #expect(store.ultraBalance == 3, "무제한이라고 잔량 미러를 버리지 않는다(서버는 여전히 값을 보낸다).")

        // 서버가 마음을 바꾸면(강등·구버전 서버로의 폴백) 화면도 따라 내려온다. 접착식이면 안 된다.
        UltraWalletSyncURLProtocol.stub(Self.walletJSON(unlimited: nil), forHost: host)
        store.applyUltraWallet(try await makeService(host: host).syncUltraWallet(accessToken: "t"))
        #expect(store.ultraUnlimited == false)
    }

    /// 계정이 바뀌면 남의 무제한을 물려받지 않는다(잔량·상한과 같은 규약).
    @Test func clearingTheSessionClearsUnlimitedToo() {
        let store = makeStore(host: "ultra-unlimited-clear-test")
        store.ultraUnlimited = true
        store.clearPersistedSession()
        #expect(store.ultraUnlimited == false)
    }

    // MARK: - (나) 화면이 그 사실을 말한다 — 문구(순수)

    @Test func unlimitedCopySaysSoWithoutInventingADailyQuota() {
        // 배지는 **한 글자**다. 폭 예산이 그 전제 위에 서 있다(아래 폭 테스트가 실측으로 못 박는다).
        #expect(UltraBalanceText.badge(balance: 0, unlimited: true) == "∞")
        #expect(UltraBalanceText.unlimitedBadge.count == 1)
        // 잔량이 0 이어도 "0" 이라고 말하지 않는다 — 관리자는 재화를 안 써서 0 에 머무는 것이 정상이고,
        // 그 사람에게 0 은 "못 쏜다"는 거짓말이다(서버는 그래도 발사한다).
        #expect(UltraBalanceText.badge(balance: 0, unlimited: true) != UltraBalanceText.badge(balance: 0))
        // 힌트는 언제나 발견성 문구다 — 채울 것이 없는 사람에게 충전을 권하지 않는다.
        #expect(UltraBalanceText.hint(balance: 0, unlimited: true) == UltraBalanceText.discover)
        #expect(UltraBalanceText.hint(balance: nil, unlimited: true) == UltraBalanceText.discover)
        // 행 툴팁도 같은 규칙(잔량 0 이어도 "없음"을 말하지 않는다).
        #expect(
            UltraBalanceText.rowTooltip(balance: 0, unlimited: true)
                == UltraBalanceText.rowTooltip(balance: 3)
        )
        // 배지 툴팁은 기호의 뜻을 **말로** 푼다. 그 자리에 숫자가 있던 것을 기억하는 사람이
        // ∞ 를 "못 읽었다"로 오해하지 않게 하는 유일한 장치다.
        #expect(UltraBalanceText.badgeHelp(balance: 0, unlimited: true).contains("무제한"))
        #expect(UltraBalanceText.badgeHelp(balance: 0, unlimited: true).contains("충전") == false)

        // 울트라 화면은 폭이 넉넉하다 — 여기서는 기호가 아니라 말을 쓴다.
        #expect(UltraPanelCopy.balanceText(0, unlimited: true) == "무제한")
        #expect(UltraPanelCopy.balanceText(nil, unlimited: true) == "무제한")
        #expect(UltraPanelCopy.heroCaption(balance: 0, hasFailed: false, unlimited: true).contains("잔량"))
        // 실패보다 앞이다: "최신 **잔량**을 못 읽었어요"는 잔량이 뜻을 갖지 않는 사람에게 정보가 아니다
        // (sync 실패 사실은 미션 목록의 문구와 [다시 시도]가 hasFailed 로 따로 말한다).
        #expect(
            UltraPanelCopy.heroCaption(balance: 0, hasFailed: true, unlimited: true)
                != UltraPanelCopy.failedCaption
        )

        // 하루 몫 시절의 어휘가 새 문장으로 되살아나지 않았는가(기존 계약 계승).
        let added = [
            UltraBalanceText.badgeHelp(balance: 0, unlimited: true),
            UltraPanelCopy.unlimitedBalance,
            UltraPanelCopy.unlimitedCaption,
        ]
        for text in added {
            for banned in ["오늘", "남음", "소진", "하루"] {
                #expect(text.contains(banned) == false, "\"\(text)\" 가 하루 몫 어휘 \"\(banned)\" 를 쓴다.")
            }
        }
    }

    // MARK: - (다) 회귀 0 — 관리자가 아닌 사람의 문구는 글자 하나까지 같다

    @Test func nonAdminCopyIsCharacterForCharacterUnchanged() {
        for balance in [nil, 0, 1, 3, 5] as [Int?] {
            #expect(UltraBalanceText.hint(balance: balance, unlimited: false) == UltraBalanceText.hint(balance: balance))
            #expect(
                UltraBalanceText.rowTooltip(balance: balance, unlimited: false)
                    == UltraBalanceText.rowTooltip(balance: balance)
            )
            #expect(
                UltraBalanceText.badgeHelp(balance: balance, unlimited: false)
                    == UltraBalanceText.badgeHelp(balance: balance)
            )
            #expect(UltraPanelCopy.balanceText(balance, unlimited: false) == UltraPanelCopy.balanceText(balance))
            for failed in [false, true] {
                #expect(
                    UltraPanelCopy.heroCaption(balance: balance, hasFailed: failed, unlimited: false)
                        == UltraPanelCopy.heroCaption(balance: balance, hasFailed: failed)
                )
            }
        }
        #expect(UltraBalanceText.badge(balance: 3, unlimited: false) == "3")
        #expect(UltraBalanceText.badge(balance: -3, unlimited: false) == "0")
    }

    // MARK: - 폭 예산 — 기호를 고른 근거를 **실측으로** 못 박는다

    /// "∞ 는 숫자 한 자리보다 넓지만 두 자리보다 좁다"가 이 기능의 폭 결정 전부다.
    ///
    /// 왜 예산을 고치지 않고 기호를 골랐는가: 이 파일에는 이미
    /// `hintWidth(digits: 2) >= longestHintWidth` 단언이 있다(상한이 두 자리로 올라갈 날을 대비해
    /// 세워 둔 것). ∞ 가 두 자리보다 좁다면 **무제한 배지의 여유는 그 단언이 이미 증명해 둔 여유의
    /// 부분집합**이다 — 새 예산을 세울 필요가 없다. 반대로 "무제한" 3글자를 배지에 넣었다면
    /// caption2 로 재도 21pt 라 세 자리 숫자보다 넓어, 힌트가 말줄임되는 첫 조합이 됐을 것이다.
    @Test func unlimitedBadgeFitsInsideTheHeadroomTheTwoDigitAssertionAlreadyProved() {
        #expect(PokeTitleRowWidthBudget.unlimitedBadgeWidth > PokeTitleRowWidthBudget.badgeWidth(digits: 1))
        #expect(PokeTitleRowWidthBudget.unlimitedBadgeWidth <= PokeTitleRowWidthBudget.badgeWidth(digits: 2))
        // 그래서 가장 긴 힌트가 말줄임 없이 들어간다.
        #expect(PokeTitleRowWidthBudget.hintWidthWhenUnlimited >= PokeTitleRowWidthBudget.longestHintWidth)
        #expect(PokeTitleRowWidthBudget.hintKoreanGlyphsWhenUnlimited >= UltraBalanceText.empty.count)
        // 대조군: 예산이 배지를 실제로 센다(안 세면 위 부등식은 아무것도 안 지킨다).
        #expect(PokeTitleRowWidthBudget.hintWidthWhenUnlimited < PokeTitleRowWidthBudget.hintWidth(digits: 1))
    }

    /// ★ 위 상수가 **현실과 맞는가**를 렌더로 잰다. 순수 계산끼리만 비교하면 상수를 아무 값으로
    /// 바꿔도 초록이다 — 그 사각지대를 이 테스트가 닫는다(실제 폰트로 그린 픽셀 폭을 본다).
    @Test func theInfinityGlyphMeasuresBetweenOneAndTwoDigitsForReal() throws {
        let oneDigit = try ultraUnlimitedRenderedSize(UltraBalanceBadge(balance: 5, action: {}))
        let twoDigits = try ultraUnlimitedRenderedSize(UltraBalanceBadge(balance: 42, action: {}))
        let unlimited = try ultraUnlimitedRenderedSize(
            UltraBalanceBadge(balance: 0, isUnlimited: true, action: {})
        )
        // 전제: 자릿수가 실제로 폭을 만든다(이게 아니면 아래 부등식은 잡음과 구별되지 않는다).
        #expect(twoDigits.w > oneDigit.w)
        // 본론: ∞ 는 한 자리보다 넓고 두 자리보다 좁다 = unlimitedGlyphWidth 의 근거.
        #expect(unlimited.w > oneDigit.w, "∞ 를 1자리로 재고 있다 — 예산이 조용히 거짓말한다.")
        #expect(unlimited.w <= twoDigits.w, "∞ 가 두 자리보다 넓다 — 폭 예산을 다시 세워야 한다.")
        // 높이는 안 변한다(제목 행이 무제한 여부로 흔들리면 700pt 예산이 갉인다).
        #expect(unlimited.h == oneDigit.h)
    }

    // MARK: - 픽셀 — 배지가 **실제로** 다른 것을 그린다

    @Test func theBadgeActuallyDrawsSomethingElseWhenUnlimited() throws {
        let plain = try ultraUnlimitedRenderPNG(UltraBalanceBadge(balance: 0, action: {}), width: 60)
        let plainTwin = try ultraUnlimitedRenderPNG(UltraBalanceBadge(balance: 0, action: {}), width: 60)
        let unlimited = try ultraUnlimitedRenderPNG(
            UltraBalanceBadge(balance: 0, isUnlimited: true, action: {}), width: 60
        )
        // 대조군 먼저: 같은 입력이면 바이트까지 같다.
        #expect(plain == plainTwin)
        #expect(plain != unlimited, "무제한인데 배지가 잔량 0 과 같은 그림이다 — 화면이 아무 말도 안 한다.")
        // 회귀 0: 깃발을 끄면 **바이트까지** 예전 그림이다(기본 인자 생략과 명시가 같아야 한다).
        let explicitlyOff = try ultraUnlimitedRenderPNG(
            UltraBalanceBadge(balance: 0, isUnlimited: false, action: {}), width: 60
        )
        #expect(plain == explicitlyOff)
    }

    // MARK: - 패널 두 장 — 사장님이 실제로 보는 화면이 바뀌는가

    /// 콕찌르기 화면(배지가 사는 자리)과 울트라 화면(큰 글자가 사는 자리) **둘 다** 바뀌어야 한다.
    /// 값 테스트는 문구가 옳은지만 보고, 그 문구가 화면에 닿는지는 못 본다 — UltraPanel 은 private 라
    /// 뷰 트리로 열 수도 없다. 그래서 메뉴 전체를 그려 픽셀로 가른다.
    @Test func bothPanelsChangeForAnAdminAndNoOneElsesPixelsMove() throws {
        for visible in [PanelUnderTest.poke, .ultra] {
            let plain = try ultraUnlimitedRenderPNG(CheckMenuView(store: panelStore(visible, unlimited: false)))
            let twin = try ultraUnlimitedRenderPNG(CheckMenuView(store: panelStore(visible, unlimited: false)))
            let unlimited = try ultraUnlimitedRenderPNG(CheckMenuView(store: panelStore(visible, unlimited: true)))
            // 대조군: 같은 입력이면 바이트까지 같다(이게 없으면 아래 부등식은 렌더 잡음과 구별되지 않는다).
            #expect(plain == twin, "\(visible) 픽스처가 결정적이지 않다 — 아래 부등식이 공허해진다.")
            #expect(plain != unlimited, "\(visible) 화면이 무제한을 말하지 않는다 — 여전히 잔량 숫자를 그린다.")
        }
    }

    /// 무제한 표시가 **새 줄을 만들지 않는다.** 배지가 제목 행에 얹혀 있다는 주장의 실증이다
    /// (창 높이 상한 700pt 예산 — 줄이 하나 늘면 그만큼 갉아먹는다).
    @Test func unlimitedAddsNoNewLineToEitherPanel() throws {
        for visible in [PanelUnderTest.poke, .ultra] {
            let plain = try #require(ultraUnlimitedRenderedHeight(CheckMenuView(store: panelStore(visible, unlimited: false))))
            let unlimited = try #require(ultraUnlimitedRenderedHeight(CheckMenuView(store: panelStore(visible, unlimited: true))))
            #expect(plain == unlimited, "\(visible) 높이가 무제한 여부로 흔들린다 = 줄이 생겼다.")
            #expect(Double(unlimited) / 2.0 <= 700.0)
        }
    }

    /// ★ 픽셀은 "화면이 달라졌다"까지만 말한다. **어느 문구가 그 자리에 닿았는지**는 못 읽는다 —
    /// 실제로 울트라 화면의 큰 글자 분기를 통째로 지워도 위 부등식은 초록이었다(히어로 아이콘 색이
    /// isCharged 로 함께 바뀌기 때문이다. 뮤테이션으로 확인했다). UltraPanel 은 private 라 뷰 트리로
    /// 열 수도 없으므로, 그 사각지대는 **원문 계약**으로 닫는다.
    ///
    /// 주석을 걷어낸 코드만 본다 — 안 그러면 설명을 지워야만 초록이 되는 테스트가 된다.
    @Test func theUltraPanelActuallyAsksTheCopyForTheUnlimitedWording() throws {
        let source = Self.codeOnly(try Self.menuViewSource())
        let panel = try Self.structBody("private struct UltraPanel: View {", in: source)
        #expect(
            panel.contains("UltraPanelCopy.balanceText(balance, unlimited: isUnlimited)"),
            "울트라 화면의 큰 글자가 무제한을 안 묻는다 — 관리자에게 여전히 숫자를 그린다."
        )
        #expect(
            panel.contains("unlimited: isUnlimited"),
            "히어로 보조문장도 같은 사실을 받아야 한다(문구만 옳고 화면엔 안 닿는 상태를 막는다)."
        )
        // 단위는 셀 수 있을 때만 붙는다("무제한 개"는 말이 아니다).
        #expect(panel.contains("if !isUnlimited {"), "단위 \"개\" 가 무제한일 때도 붙는다.")
        // 대조군: 추출이 실제로 한 선언만 잘라 왔다(전체를 돌려주면 위 단언은 공허하다).
        #expect(panel.contains("struct MissionRowView") == false, "선언 추출 범위가 너무 넓다.")
        #expect(panel.contains("heroCard"), "선언 추출 범위가 너무 좁다 — 히어로 카드를 못 담았다.")
    }

    // MARK: - 소스 읽기 헬퍼(이 스위트 전용 — 다른 파일의 동명 헬퍼와 겹치지 않게 static 으로 둔다)

    private static func menuViewSource() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("Sources/check/CheckMenuView.swift")
        // 못 읽으면 **던진다** — 조용히 통과하면 경로가 바뀐 날 방어망이 사라진 것을 아무도 모른다.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UltraUnlimitedSourceError.unreadable(url.path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 줄 주석을 걷어낸 코드. 문자열 리터럴 안의 `//` 는 이 파일에 없다(있으면 이 헬퍼를 고쳐야 한다).
    private static func codeOnly(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// 선언 한 줄부터 **중괄호 깊이가 0 으로 돌아올 때까지**(= 본문 전체)를 잘라낸다.
    private static func structBody(_ header: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(header) })
        else { throw UltraUnlimitedSourceError.declarationNotFound(header) }
        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0, collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    private enum PanelUnderTest { case poke, ultra }

    /// 두 패널 중 하나만 열린 결정적 스토어. **무제한 말고는 아무것도 다르지 않다** —
    /// 잔량도 목록도 안내줄도 같다. 그래야 위 부등식이 "무제한 표시"만을 잡는다.
    private func panelStore(_ visible: PanelUnderTest, unlimited: Bool) -> WorkTimerStore {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(host: "ultra-unlimited-panel-render-test")
        store.startedAt = now
        store.displayNow = now
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.teamName = "아잉팀"
        store.pokeDirectory = [
            PokeDirectoryEntry(userID: "teammate", name: "영식", avatarURL: nil, isWorking: true)
        ]
        store.pokeDirectoryLoaded = true
        // ★ 잔량 0 = 관리자의 정상 상태다(재화를 안 쓰므로 늘지도 줄지도 않는다).
        //   그래서 이 값이 무제한 표시의 가장 가혹한 조건이다: 잘못 만들면 화면이 "울트라 없음"이라고 말한다.
        store.applyUltraBalance(0)
        store.missionsLoaded = true
        store.ultraUnlimited = unlimited
        switch visible {
        case .poke: store.isPokePanelVisible = true
        case .ultra: store.isUltraPanelVisible = true
        }
        return store
    }
}

// MARK: - 무제한 테스트 전용 렌더/스텁 헬퍼
//
// 이름을 전부 고유하게 짓는 이유는 이 파일 머리의 경고 그대로다: 모듈 전역에서 이름이 겹치면
// 테스트 타깃이 통째로 컴파일되지 않는다(다른 파일에도 renderPNG 가 산다).

@MainActor
private func ultraUnlimitedRenderPNG(_ view: some View, width: CGFloat = 340) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { throw UltraUnlimitedRenderError.failed }
    return png
}

@MainActor
private func ultraUnlimitedRenderedHeight(_ view: some View, width: CGFloat = 340) -> Int? {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.pixelsHigh
}

/// 자연 크기로 그린 픽셀 크기. **폭 자체가 계약인 배지 전용** — `.frame(width:)` 로 고정하면
/// "기호가 숫자보다 넓다"가 픽셀에서 사라진다.
@MainActor
private func ultraUnlimitedRenderedSize(_ view: some View) throws -> (w: Int, h: Int) {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw UltraUnlimitedRenderError.failed }
    return (bitmap.pixelsWide, bitmap.pixelsHigh)
}

private enum UltraUnlimitedRenderError: Error { case failed }

private enum UltraUnlimitedSourceError: Error {
    case unreadable(String)
    case declarationNotFound(String)
}

/// `ultra_wallet_sync` 응답만 흉내 내는 스텁. **기존 UltraSequenceURLProtocol 을 건드리지 않는 이유**는
/// 그쪽이 찌르기 순차 시나리오 전용이라, 지갑 경로를 끼워 넣으면 이 파일의 다른 테스트가 보는 큐 규칙이
/// 바뀌기 때문이다. 호스트별로 격리한다(요청 기록은 프로세스 전역이다).
final class UltraWalletSyncURLProtocol: URLProtocol {
    static let walletPath = "/rest/v1/rpc/ultra_wallet_sync"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var bodiesByHost: [String: String] = [:]

    static func stub(_ json: String, forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        bodiesByHost[host] = json
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UltraWalletSyncURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        let stubbed = Self.bodiesByHost[host]
        Self.lock.unlock()
        // 지갑 경로가 아니면 빈 배열(다른 경로가 이 스텁을 타고 들어와도 조용히 지나가게).
        let json = (request.url?.path == Self.walletPath) ? (stubbed ?? "{}") : "[]"
        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
