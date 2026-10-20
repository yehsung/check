import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 캡슐 뽑기 기계 덮개(v0.3.54 · 1.0.8)가 부르는 길 — `MeStore.pullGachaForMachine()` 을 스텁 서버로 **진짜로** 돌린다.
///
/// 기계(코어 `GachaMachineView`)는 손잡이 한 바퀴에 `pull` 을 한 번 부르고, 돌려받은 값으로만 공개를 한다(던지면 공개 없이 한 줄).
/// 그래서 여기서 재는 것은 "그 값이 서버 응답에서 왔는가 · 실패면 값을 안 돌려주는가 · 한 판에 요청 하나인가 · 덮개를 닫아도
/// 결과가 남는가 · 로그아웃 뒤엔 공개가 없는가"다. 기대값은 손으로 적은 글자다.
/// 덮개 뷰(`MeGachaViews.swift`)는 iOS 전용이라 맥 스위트가 못 그린다 — 연결은 맨 아래 소스 계약(주석을 걷은 글자)으로 잰다.
@MainActor
@Suite("나 탭 캡슐 뽑기 기계(v0.3.54)")
struct MeGachaMachineTests {
    typealias Fixture = MeGachaStoreTests

    /// 던진 실패의 한 줄(기계 아래 2.4초). `GachaRevealFailure` 가 아니면 nil.
    private func failureMessage(_ body: () async throws -> GachaRevealOutcome) async -> (outcome: GachaRevealOutcome?, message: String?, error: Error?) {
        do {
            return (try await body(), nil, nil)
        } catch let failure as GachaRevealFailure {
            return (nil, failure.message, failure)
        } catch {
            return (nil, nil, error)
        }
    }

    // MARK: - 결과 세 갈래 — 서버 값이 그대로 기계로

    @Test("기계 뽑기: 새 캐릭터 · 중복(조각 칩이 앞 → 뒤) · 황금 — 서버 응답 그대로 · 이름은 카드 이름 · 판마다 요청 하나 · 새 request_id")
    func machinePullReturnsServerOutcome() async throws {
        let harness = await RankMeHarness(label: "me-machine-pull") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 200, shards: 0)))
        await store.loadShop()

        // ① 새 캐릭터(다람쥐).
        harness.enqueue("gacha_pull", Fixture.pullOK("squirrel", duplicate: false, shards: 0, ruby: 150))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 150, shards: 0, owned: ["fox", "squirrel"])))
        let first = try await store.pullGachaForMachine()
        #expect(first == GachaRevealOutcome(characterID: "squirrel", name: "다람쥐", kind: .new, shardCount: 0, shardsGained: 0))
        #expect(harness.requests(rpc: "gacha_pull").count == 1)
        #expect(store.rubyBalance == 150 && harness.model.gomokuHost.rubyBalance == 150, "루비 미러가 서버 값이 아니다")
        #expect(store.isOwned("squirrel") && store.lastGachaResult?.characterID == "squirrel")
        // 돌려받은 때는 이미 다시 읽기까지 끝났다 — [한 번 더] 가 늦은 조회와 겹칠 틈이 없다.
        #expect(!store.isPulling && harness.requests(rpc: "shop_state").count == 2)
        let firstBody = try #require(harness.requests(rpc: "gacha_pull").last?.jsonBody)
        // 1.0.10 번들은 3 을 싣는다(무지개 초상까지 그릴 수 있다 — 번호는 누적이다).
        #expect(Set(firstBody.keys) == ["p_protocol", "p_request_id"] && firstBody["p_protocol"] as? Int == ShopWire.rainbowProtocol)

        // ② 중복(여우) — 칩이 0 → 1 로 오른다.
        harness.enqueue("gacha_pull", Fixture.pullOK("fox", duplicate: true, shards: 1, ruby: 100))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 100, shards: 1, owned: ["fox", "squirrel"])))
        let dup = try await store.pullGachaForMachine()
        #expect(dup.kind == .duplicate && dup.name == "여우")
        #expect(dup.shardCountBefore == 0 && dup.shardCount == 1 && dup.shardsGained == 1)

        // ③ 황금 아잉이.
        harness.enqueue("gacha_pull", Fixture.pullOK("aing_gold", duplicate: false, shards: 1, ruby: 50))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 50, shards: 1, owned: ["fox", "squirrel", "aing_gold"])))
        let gold = try await store.pullGachaForMachine()
        #expect(gold.kind == .gold && gold.name == "황금 아잉이" && !gold.isGoldDuplicate)

        // ④ 서버가 뒤 조각 수를 안 실은 중복 — 칩은 **뽑기 전 화면 값**(1)에서 +1. (기준선: ②는 서버 값을 썼다.)
        harness.enqueue("gacha_pull", .json(#"{"status":"ok","character_id":"ghost","duplicate":true,"ruby_balance":0}"#))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 0, shards: 2, owned: ["fox", "squirrel", "aing_gold", "ghost"])))
        let noShards = try await store.pullGachaForMachine()
        #expect(noShards.kind == .duplicate && noShards.shardCountBefore == 1 && noShards.shardCount == 2,
                "조각 수가 빠진 응답에서 칩 값을 지어냈다: \(noShards)")

        let ids = harness.requests(rpc: "gacha_pull").compactMap { $0.jsonBody["p_request_id"] as? String }
        #expect(ids.count == 4 && Set(ids).count == 4, "답을 받은 뒤의 판이 앞 판의 request_id 를 썼다: \(ids)")
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 실패는 공개가 없다

    @Test("기계 뽑기 실패: 값을 안 돌려주고 한 줄로 던진다 — 클라 모자람(요청 없음) · 서버 insufficient · needs_update · 함수 없음 · 잔량 모름")
    func machinePullFailuresThrowWithoutReveal() async throws {
        let harness = await RankMeHarness(label: "me-machine-refuse") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me

        // 클라가 먼저 막는다(기계도 잔액으로 막지만, 스토어가 마지막 문이다).
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 40)))
        await store.loadShop()
        var r = await failureMessage { try await store.pullGachaForMachine() }
        #expect(r.outcome == nil && r.message == "루비 10개 더 필요해요")
        #expect(harness.requests(rpc: "gacha_pull").isEmpty, "모자란데 요청을 냈다")

        // 서버 insufficient — 서버가 말한 잔량으로 맞추고 던진다.
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 60)))
        await store.loadShop()
        harness.enqueue("gacha_pull", .json(#"{"status":"insufficient","need":50,"have":30}"#))
        r = await failureMessage { try await store.pullGachaForMachine() }
        #expect(r.outcome == nil && r.message == "루비 20개 더 필요해요")
        #expect(store.rubyBalance == 30 && store.lastGachaResult == nil)

        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 100)))
        await store.loadShop()
        harness.enqueue("gacha_pull", .json(#"{"status":"needs_update"}"#))
        r = await failureMessage { try await store.pullGachaForMachine() }
        #expect(r.outcome == nil && r.message == "앱을 업데이트하면 뽑을 수 있어요")

        // 함수가 없는 서버(하네스 기본 응답 PGRST202) — 서버에서 아무것도 안 돌았다 → id 를 버린다.
        r = await failureMessage { try await store.pullGachaForMachine() }
        #expect(r.outcome == nil && r.message == "지금은 뽑을 수 없어요")
        #expect(store.gachaRequestIDs.pull == nil)

        // ok 인데 결과 id 가 빠졌다 — 공개할 것이 없다.
        harness.enqueue("gacha_pull", .json(#"{"status":"ok","ruby_balance":50}"#))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 50)))
        r = await failureMessage { try await store.pullGachaForMachine() }
        #expect(r.outcome == nil && r.message == "뽑지 못했어요. 잠시 후 다시 시도해 주세요")
        #expect(store.lastGachaResult == nil)

        // 잔량을 모른다(응답에 ruby_balance 가 없다 · 처음 읽음) — 0 으로 그려 "모자라요"라 하지 않고 다시 읽는다.
        let fresh = await RankMeHarness(label: "me-machine-unknown") { _ in nil }
        defer { fresh.tearDown() }
        let noBalance = Fixture.shopV2().replacingOccurrences(of: #""ruby_balance":120,"#, with: "")
        fresh.enqueue("shop_state", .json(noBalance))
        await fresh.me.loadShop()
        #expect(fresh.me.rubyBalance == nil && fresh.me.showsGacha, "전제: 뽑기는 열렸고 잔량만 모른다")
        #expect(fresh.me.gachaMachineBlockedReason(machineOwnsPull: false) == "불러오는 중…")
        fresh.enqueue("shop_state", .json(Fixture.shopV2(ruby: 120)))
        r = await failureMessage { try await fresh.me.pullGachaForMachine() }
        #expect(r.outcome == nil && r.message == "불러오는 중…")
        await fresh.quiesceMe()
        #expect(fresh.requests(rpc: "gacha_pull").isEmpty, "잔량을 모르는데 뽑았다")
        #expect(fresh.me.rubyBalance == 120, "잔량을 모르면 다시 읽어야 한다")
        #expect(fresh.me.gachaMachineBlockedReason(machineOwnsPull: false) == nil)
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 결과를 모르는 실패 → 같은 id 로 다시

    @Test("기계 뽑기 연결 실패: 연결 문장으로 던지고 id 를 쥔다 · 다음 판은 같은 id 로 묻고 replayed 결과를 공개한다(두 번 깎지 않는다)")
    func machineRetryReusesRequestID() async throws {
        let harness = await RankMeHarness(label: "me-machine-retry") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 200)))
        await store.loadShop()

        harness.enqueue("gacha_pull", .networkFailure())
        var r = await failureMessage { try await store.pullGachaForMachine() }
        #expect(r.outcome == nil && r.message == "연결이 불안정해요. 잠시 후 다시 시도해 주세요")
        #expect(store.rubyBalance == 200 && store.lastGachaResult == nil, "결과를 모르는데 값을 지어냈다")
        let held = try #require(store.gachaRequestIDs.pull, "결과를 모르는 실패 뒤 id 를 버렸다")

        harness.enqueue("gacha_pull", .json(#"{"message":"boom"}"#, status: 500))
        r = await failureMessage { try await store.pullGachaForMachine() }
        #expect(r.message == "연결이 불안정해요. 잠시 후 다시 시도해 주세요" && store.gachaRequestIDs.pull == held)

        harness.enqueue("gacha_pull", Fixture.pullOK("ghost", duplicate: false, shards: 0, ruby: 150, replayed: true))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 150, owned: ["fox", "ghost"])))
        let replayed = try await store.pullGachaForMachine()
        #expect(replayed.characterID == "ghost" && replayed.kind == .new)
        let ids = harness.requests(rpc: "gacha_pull").compactMap { $0.jsonBody["p_request_id"] as? String }
        #expect(ids.count == 3 && Set(ids) == [held.uuidString.lowercased()], "결과를 모르는 동안 id 가 흔들렸다: \(ids)")
        #expect(store.gachaRequestIDs.pull == nil && store.rubyBalance == 150)
    }

    // MARK: - 한 판에 요청 하나 · 다시 연 덮개

    @Test("떠 있는 뽑기가 있으면 둘째 부름은 요청 없이 던진다 · 다시 연 기계(앞 판을 모른다)는 손잡이가 잠기고, 앞 판을 띄운 기계는 안 잠긴다")
    func onePullPerTurn() async throws {
        let harness = await RankMeHarness(label: "me-machine-once") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 200)))
        await store.loadShop()
        #expect(store.gachaMachineBlockedReason(machineOwnsPull: false) == nil, "기준선: 쉬는 기계는 안 잠긴다")

        let hold = BaseHold.rpc("gacha_pull", host: harness.host)
        harness.enqueue("gacha_pull", Fixture.pullOK("robot", duplicate: false, shards: 0, ruby: 150))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 150, owned: ["fox", "robot"])))
        let firstTurn = Task { try await store.pullGachaForMachine() }
        #expect(await hold.waitHeld())
        #expect(store.isPulling)
        #expect(store.gachaMachineBlockedReason(machineOwnsPull: true) == nil, "자기 판을 띄운 기계를 잠갔다")
        #expect(store.gachaMachineBlockedReason(machineOwnsPull: false) == "앞 뽑기 결과를 받는 중이에요")

        let second = await failureMessage { try await store.pullGachaForMachine() }
        #expect(second.outcome == nil && second.message == "앞 뽑기 결과를 받는 중이에요")
        #expect(hold.held == 1 && harness.requests(rpc: "gacha_pull").count <= 1, "떠 있는데 둘째 요청이 나갔다")

        #expect(await hold.releaseAndWaitDelivered())
        let outcome = try await firstTurn.value
        #expect(outcome.characterID == "robot" && outcome.name == "로봇")
        #expect(harness.requests(rpc: "gacha_pull").count == 1)
        #expect(store.gachaMachineBlockedReason(machineOwnsPull: false) == nil, "끝났는데 손잡이가 잠겨 있다")
    }

    // MARK: - 덮개를 닫아도 결과는 남는다 · 로그아웃이면 공개가 없다

    @Test("공개 전에 덮개를 닫아도(기다리던 쪽 취소) 요청은 끝까지 가고 루비 · 보유 · 카드의 마지막 결과 줄이 선다")
    func closingCoverKeepsTheResult() async throws {
        let harness = await RankMeHarness(label: "me-machine-close") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 200)))
        await store.loadShop()

        let hold = BaseHold.rpc("gacha_pull", host: harness.host)
        harness.enqueue("gacha_pull", Fixture.pullOK("jellyfish", duplicate: false, shards: 0, ruby: 150))
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 150, owned: ["fox", "jellyfish"])))
        let waiting = Task { try await store.pullGachaForMachine() }
        #expect(await hold.waitHeld())
        waiting.cancel()
        #expect(await hold.releaseAndWaitDelivered())
        _ = try? await waiting.value
        await harness.quiesceMe()
        #expect(hold.delivered == 1, "덮개를 닫자 요청이 끊겼다 — 깎였는지 모르는 채 결과가 사라진다")
        #expect(store.rubyBalance == 150 && store.isOwned("jellyfish"))
        let line = try #require(store.lastGachaResult, "닫힌 덮개의 결과가 카드에 안 남았다")
        #expect(GachaText.headline(for: line, name: store.gachaName(line.characterID)) == "새 캐릭터: 해파리")
        #expect(!store.isPulling)
    }

    @Test("뽑기가 떠 있는 동안 로그아웃하면 기계는 결과를 못 받는다(던진다) · 루비 미러 · 보유 · 결과 줄이 안 선다")
    func logoutMidPullNeverReveals() async throws {
        let harness = await RankMeHarness(label: "me-machine-logout") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Fixture.shopV2(ruby: 200)))
        await store.loadShop()

        let hold = BaseHold.rpc("gacha_pull", host: harness.host)
        harness.enqueue("gacha_pull", Fixture.pullOK("aing_gold", duplicate: false, shards: 0, ruby: 150))
        let waiting = Task { try await store.pullGachaForMachine() }
        #expect(await hold.waitHeld())
        await harness.model.session.signOut()
        await harness.barrier()
        hold.release()
        let result = await failureMessage { try await waiting.value }
        #expect(result.outcome == nil, "로그아웃 뒤에 공개할 결과를 돌려줬다")
        await harness.quiesceMe()
        #expect(harness.model.gomokuHost.rubyBalance == nil && store.ownedCharacterIDs == [MeCharacterCards.aingID])
        #expect(store.lastGachaResult == nil && !store.isPulling)
        #expect(store.gachaMachineBlockedReason(machineOwnsPull: false) == "로그인하면 뽑을 수 있어요")
    }

    // MARK: - 폰 문구

    @Test("기계 덮개가 더 쓰는 문구: 앞 판 대기 · 마지막 결과 앞말 — 해요체 · 금지어 없음")
    func machineCopy() {
        #expect(MeText.gachaPullBusy == "앞 뽑기 결과를 받는 중이에요")
        #expect(MeText.gachaLastResult == "방금 뽑은 결과")
        for line in [MeText.gachaPullBusy, MeText.gachaLastResult] {
            for word in ["도박", "베팅"] { #expect(!line.contains(word)) }
        }
    }

    // MARK: - iOS 전용 연결(소스 계약 — 주석을 걷은 글자)

    @Test("덮개 연결: 카드 [뽑기]·금 타일(상점·고르기)이 기계 덮개를 연다 · 짧은 결과 연출은 걷혔다 · 기계는 번들 그림 · 햅틱 · isActive · 스토어 값만")
    func coverWiringContract() throws {
        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeGachaViews.swift")
        #expect(views.contains("fullScreenCover(isPresented: isPresented)"), "기계가 전체 화면 덮개가 아니다")
        #expect(views.contains("GachaMachineView("))
        #expect(views.contains("art: .bundled"), "배포본은 번들 그림을 써야 한다(벡터는 안전망)")
        #expect(views.contains("haptics: haptics") && views.contains("MeGachaHaptics()"), "폰 햅틱을 안 넘긴다")
        #expect(views.contains("isActive: isShown && scenePhase == .active && !showsOdds"),
                "앱이 뒤로 가거나 덮개가 내려가거나 시트가 가려도 기계가 매 프레임 그린다")
        #expect(views.contains("try await store.pullGachaForMachine()"), "기계의 pull 이 스토어 뽑기 몸통을 안 지난다")
        #expect(views.contains("blockedReason: store.gachaMachineBlockedReason(machineOwnsPull: ownsPull)"))
        #expect(views.contains("againEnabled: !store.isPulling"))
        #expect(views.contains("balance: store.rubyBalance ?? 0") && views.contains("shards: store.gachaShards ?? 0"),
                "기계 칩이 스토어의 서버 값이 아니다")
        // 짧은 결과 연출은 걷혔다 — 카드는 기계를 열 뿐 스스로 뽑지 않는다.
        #expect(!views.contains("MeGachaResultView"), "옛 짧은 결과 연출이 남았다")
        #expect(!views.contains("store.pullGacha()"), "카드가 기계를 거치지 않고 바로 뽑는다")
        #expect(views.contains("onPull()"))
        #expect(!views.contains("\"diamond.fill\""))

        let screens = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        #expect(screens.components(separatedBy: ".gachaMachineCover(store: store, isPresented: $showsGachaMachine)").count - 1 == 2,
                "상점·고르기 두 화면이 기계 덮개를 띄우지 않는다")
        #expect(screens.contains("onPull: { showsGachaMachine = true }"), "카드 [뽑기] 가 덮개를 안 연다")
        #expect(screens.components(separatedBy: "store.isGachaOnly(id) else { return }\n                                showsGachaMachine = true").count - 1 == 1,
                "상점의 금 타일이 덮개를 안 연다")
        #expect(screens.contains("if store.showsGacha, !store.isOwned(id), store.isGachaOnly(id) {\n                showsGachaMachine = true"),
                "고르기의 금 타일이 덮개를 안 연다")
        #expect(screens.contains("case \"machine\": showsGachaMachine = true"), "데모 장면(-AingCheckDemoMeGacha machine)이 없다")

        let haptics = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeGachaHaptics.swift")
        #expect(haptics.hasPrefix("#if os(iOS)"))
        #expect(haptics.contains("final class MeGachaHaptics: GachaMachineHaptics"))
        for event in [".ratchet", ".refuse", ".commit", ".rumble", ".land", ".tap(let n)", ".goldFlip", ".reveal:", ".goldReveal", ".shard"] {
            #expect(haptics.contains("case \(event)"), "햅틱 \(event) 가 빠졌다")
        }
        #expect(!haptics.contains("default:"), "모르는 박자를 default 로 삼킨다 — 새 박자가 생겨도 컴파일이 안 알려 준다")
    }
}
