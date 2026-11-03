import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.77 — 빼빼로 장식 미리 굽기는 **가진 사람 · 입은 사람만**(조정자 결정 11-04 — `PeperoPrewarmGate`). 상자 2048×768 + 막대 셋(≈ 13MB ·
// release ~0.7초)을 모든 사람에게 굽던 것(`CakeAingFinish.prewarmDecorTemplates` 안의 한 줄)을 문 하나로 옮겼다. 재는 것:
//  ① 안 가진 사람은 안 굽는다 — 시작(입은 것 아잉 · 가진 것 케이크)도, 빼빼로 없는 상점 상태도 문을 안 연다 · 케이크 · 이슬 미리 굽기는 빼빼로를 안 부른다.
//  ② 입은 사람은 굽는다 — 시작이 연 문이 '이 시각 전엔 굽지 않는다'(시작 + delay) 뒤 메인 밖에서 한 번 · 로컬 저장 선택값이 그 판정의 재료다.
//  ③ 상점 상태가 늦게 와 가진 것이 확인되면 그때 한 번(여러 번 와도 한 번) · 요청이 시작보다 먼저 와도 잃지 않는다.
//  ④ 선물을 받은 순간(받기 성공) 굽는다 — 다른 캐릭터를 받으면 안 연다.
//  ⑤ 배선: 앱 시작이 공용 문을 같은 때(세션 활성화 뒤 · 5초) 연다 · 스토어 기본 문은 공용 문 · 그림 저장소의 새 판 다시 굽기도 그 문을 지난다.
// 굽기는 대역(센다 — 메인이었는가까지)으로 잰다: 공용 장식 캐시를 안 건드려 나란히 도는 빼빼로 시험과 엉키지 않는다. 진짜 굽기(`liveBake`)가
// 메인 밖에서 한 번 굽고 첫 씬이 다시 안 굽는 것은 `V0377PeperoMac3DTests.decorIsPrewarmedOffMain` · 메인 굽기 금지는
// `V0377PeperoReviewFixTests.mainNeverBakesTheDecor`.

/// 굽기 대역 — 불린 스레드가 메인이었는가를 하나씩 적는다.
final class V0377PrewarmBakeSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _onMain: [Bool] = []
    private var _at: [UInt64] = []
    func record() {
        let onMain = Thread.isMainThread
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock { _onMain.append(onMain); _at.append(now) }
    }
    var onMain: [Bool] { lock.withLock { _onMain } }
    /// 구운 시각(부팅 뒤 나노초 — `DispatchTime.uptimeNanoseconds`).
    var at: [UInt64] { lock.withLock { _at } }
}

@MainActor
@Suite struct V0377PeperoPrewarmTests {
    static let pepero = CharacterCatalog.peperoAingID
    static let aing = CharacterCatalog.builtInAingID
    static let strawberry = CharacterCatalog.cakeStrawberryAingID

    static func gate() -> (PeperoPrewarmGate, V0377PrewarmBakeSpy) {
        let spy = V0377PrewarmBakeSpy()
        return (PeperoPrewarmGate(bake: { spy.record() }), spy)
    }

    static func finish(_ work: DispatchWorkItem?) async throws {
        let work = try #require(work, "건 굽기가 없다")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in work.notify(queue: .main) { done.resume() } }
    }

    /// 걸리지 않은 굽기가 정말 안 도는지 볼 만큼 기다린다(건 굽기는 delay 0 이면 곧바로 돈다).
    static func settle() async throws { try await Task.sleep(for: .milliseconds(300)) }

    static func shop(owned: Set<String>) -> ShopStateResponse {
        let rows = [strawberry, CharacterCatalog.isulAingID, pepero].map {
            ShopCharacterRow(id: $0, price: 2000, owned: owned.contains($0), gachaOnly: true, giftOnly: true)
        }
        return ShopStateResponse(rubyBalance: 100, ultraBalance: 1, ultraPrice: V0317ShopTests.realUltraPrice, ultraBuyMax: 20, characters: rows)
    }

    /// 아무 데도 안 나가는 스토어(받기 뒤 상점 다시 읽기 · 다음 선물 묻기가 스텁으로 간다) + 시험 문 + 창 대역.
    static func store(_ gate: PeperoPrewarmGate, function: String = #function) -> WorkTimerStore {
        let store = V0317ShopTests.plainStore(service: V0317ShopTests.offlineService("v0377-prewarm-\(function.prefix(24))"), function: function)
        store.peperoPrewarmGate = gate
        store.cakeGiftWindowHooks = CakeGiftWindowHooks(show: { _ in }, close: {}, isOpen: { false }, returnToPopover: {})
        V0354CoreStub.retain(store)
        return store
    }

    // MARK: ① 안 가진 사람

    @Test("안 가진 사람은 안 굽는다: 시작(입은 것 아잉 · 가진 것 케이크) · 빼빼로 없는 상점 상태 · 다른 캐릭터 받기 모두 문을 안 연다 · 케이크 · 이슬 미리 굽기는 빼빼로를 안 부른다")
    func nonOwnerNeverBakes() async throws {
        #expect(!PeperoPrewarmGate.wants(wornID: Self.aing, ownedIDs: [Self.aing, Self.strawberry]))
        #expect(PeperoPrewarmGate.wants(wornID: Self.pepero, ownedIDs: [Self.aing]))
        #expect(PeperoPrewarmGate.wants(wornID: Self.aing, ownedIDs: [Self.aing, Self.pepero]))

        let (gate, spy) = Self.gate()
        #expect(gate.arm(after: 0, wornID: Self.aing, ownedIDs: [Self.aing, Self.strawberry]) == nil, "안 가진 사람의 시작이 굽기를 걸었다")
        let store = Self.store(gate)
        store.applyShopState(Self.shop(owned: [Self.strawberry, CharacterCatalog.isulAingID]))
        store.applyCakeGiftClaim(.received(characterID: Self.strawberry, replayed: false), giftID: "5e5e2222-0000-4000-8000-00000000b011")
        try await Self.settle()
        #expect(gate.scheduledCount == 0 && spy.onMain.isEmpty, "안 가진 사람에게 빼빼로 장식을 구웠다 — 건 \(gate.scheduledCount) · 구움 \(spy.onMain)")
        #expect(store.ownedCharacterIDs.contains(Self.strawberry), "받기가 보유에 안 들어갔다(기준선)")

        // 케이크 · 이슬 미리 굽기(모든 사람)는 빼빼로를 굽지 않는다 — 그 한 줄이 남으면 13MB 를 다시 모든 사람에게 굽는다.
        let cake = V0366CakeMac3DTests.normalized(try V0366CakeMac3DTests.region(try V0366CakeMac3DTests.source("Sources/check/CakeAingFinish.swift"),
                                                                            from: "static func prewarmDecorTemplates(", to: "/// 시험 전용"))
        #expect(cake.contains("IsulAingFinish.decorNode()"), "구획을 잘못 잘랐다(기준선 — 이슬은 있어야 한다)")
        #expect(!cake.contains("PeperoAingFinish") && !cake.contains("PeperoPrewarmGate"), "케이크 · 이슬 미리 굽기가 빼빼로를 굽는다 — \(cake)")
    }

    // MARK: ② 입은 사람

    @Test("입은 사람은 굽는다: 로컬 저장 선택값이 빼빼로면 시작이 연 문이 delay 뒤 메인 밖에서 한 번 굽는다(그 전엔 안 돈다) · 거듭 열어도 같은 손잡이")
    func wearerBakesAfterTheLaunchDelay() async throws {
        let defaults = CheckTestScratch.defaults("v0377-prewarm-worn", function: #function)
        #expect(CharacterSelection(defaults: defaults, catalog: CheckCharacter3DScene.catalog).select(Self.pepero), "빼빼로를 못 골랐다(기준선)")
        let worn = CheckCharacter3DScene.selectedCharacter(defaults: defaults).id
        #expect(worn == Self.pepero, "저장된 선택이 빼빼로로 안 읽힌다 — \(worn)")

        let (gate, spy) = Self.gate()
        // 시작은 상점 상태 전이라 가진 것이 아잉뿐이다 — 입은 것만으로 연다.
        let armedAt = DispatchTime.now().uptimeNanoseconds
        let work = gate.arm(after: 0.4, wornID: worn, ownedIDs: [Self.aing])
        #expect(work != nil, "입은 사람의 시작이 굽기를 안 걸었다")
        try await Self.finish(work)
        #expect(spy.onMain == [false], "입은 사람의 미리 굽기가 메인 밖에서 한 번이 아니다 — \(spy.onMain)")
        // 시각으로 잰다(메인이 바쁘면 짧은 잠이 늦게 깨 '아직 안 돌았다'를 못 본다).
        let waited = Double((spy.at.first ?? armedAt) &- armedAt) / 1e9
        #expect(waited >= 0.39, "시작이 정한 때(+0.4초)보다 먼저 구웠다(\(waited)초) — 시작의 급한 일과 겹친다")
        #expect(gate.request() === work && gate.arm(after: 0, wornID: worn, ownedIDs: [Self.aing, Self.pepero]) === work, "둘째 요청이 새 굽기를 걸었다")
        try await Self.settle()
        #expect(gate.scheduledCount == 1 && spy.onMain == [false], "거듭 열었더니 또 구웠다 — \(spy.onMain)")
    }

    // MARK: ③ 상점 상태가 늦게 온다

    @Test("상점 상태가 늦게 와 가진 것이 확인되면 그때 한 번 굽는다(여러 번 와도 한 번 · 메인 밖) · 요청이 시작보다 먼저 와도 시작이 열 때 건다")
    func lateShopStateBakesOnce() async throws {
        let (gate, spy) = Self.gate()
        #expect(gate.arm(after: 0, wornID: Self.aing, ownedIDs: [Self.aing]) == nil, "시작이 아직 모르는 보유로 굽기를 걸었다")
        let store = Self.store(gate)
        store.applyShopState(Self.shop(owned: [Self.strawberry]))
        #expect(gate.scheduledCount == 0, "빼빼로 없는 상점 상태가 굽기를 걸었다")
        store.applyShopState(Self.shop(owned: [Self.strawberry, Self.pepero]))
        #expect(gate.scheduledCount == 1, "가진 것이 확인됐는데 굽기를 안 걸었다")
        store.applyShopState(Self.shop(owned: [Self.pepero]))
        store.applyShopState(Self.shop(owned: [Self.pepero]))
        try await Self.finish(gate.request())
        try await Self.settle()
        #expect(gate.scheduledCount == 1 && spy.onMain == [false], "상점 상태가 거듭 와서 또 구웠다(또는 메인에서) — 건 \(gate.scheduledCount) · \(spy.onMain)")

        // 차례가 바뀌어도(시작 전에 상점 상태) 요청을 잃지 않는다 — 기억했다가 시작이 열 때 건다.
        let (early, earlySpy) = Self.gate()
        let earlyStore = Self.store(early)
        earlyStore.applyShopState(Self.shop(owned: [Self.pepero]))
        try await Self.settle()
        #expect(early.scheduledCount == 0 && earlySpy.onMain.isEmpty, "시작이 문을 열기 전에 구웠다")
        try await Self.finish(early.arm(after: 0, wornID: Self.aing, ownedIDs: [Self.aing]))
        #expect(earlySpy.onMain == [false], "시작 전에 온 요청을 잃었다 — \(earlySpy.onMain)")
    }

    // MARK: ④ 선물 받기

    @Test("선물을 받은 순간 굽는다: 빼빼로 받기 성공(.received) 뒤 메인 밖에서 한 번 · 이미 받았던 것(.alreadyClaimed)도 가진 것이라 같은 문 · 한 번만")
    func giftClaimBakes() async throws {
        let (gate, spy) = Self.gate()
        #expect(gate.arm(after: 0, wornID: Self.aing, ownedIDs: [Self.aing]) == nil)
        let store = Self.store(gate)
        store.applyCakeGiftClaim(.received(characterID: Self.pepero, replayed: false), giftID: "5e5e1111-0000-4000-8000-00000000b011")
        #expect(store.ownedCharacterIDs.contains(Self.pepero) && store.cakeGiftReceivedID == Self.pepero, "받기가 보유에 안 들어갔다(기준선)")
        #expect(gate.scheduledCount == 1, "빼빼로를 받았는데 굽기를 안 걸었다")
        try await Self.finish(gate.request())
        #expect(spy.onMain == [false], "받은 뒤 굽기가 메인 밖에서 한 번이 아니다 — \(spy.onMain)")

        let (other, otherSpy) = Self.gate()
        _ = other.arm(after: 0, wornID: Self.aing, ownedIDs: [Self.aing])
        let otherStore = Self.store(other)
        otherStore.applyCakeGiftClaim(.alreadyClaimed(characterID: Self.pepero), giftID: "5e5e3333-0000-4000-8000-00000000b011")
        try await Self.finish(other.request())
        #expect(other.scheduledCount == 1 && otherSpy.onMain == [false], "이미 받았던 빼빼로(다른 기기)가 문을 안 열었다")
    }

    // MARK: ⑤ 배선

    @Test("배선: 앱 시작이 공용 문을 세션 활성화 뒤 · 케이크와 같은 5초로 열고 입은 것은 로컬 저장 선택값으로 · 스토어 기본 문은 공용 문 · 새 판 다시 굽기도 그 문")
    func wiring() throws {
        let launch = V0366CakeMac3DTests.normalized(try V0366CakeMac3DTests.source("Sources/check/CheckApp.swift"))
        let kick = try #require(launch.range(of: "store.activateStoredSessionOnLaunch()"))
        let arm = try #require(launch.range(of: "PeperoPrewarmGate.shared.arm(after: 5,"), "앱 시작이 빼빼로 미리 굽기 문을 안 연다")
        #expect(kick.upperBound <= arm.lowerBound, "빼빼로 미리 굽기 문이 세션 활성화보다 앞이다")
        let call = String(launch[arm.lowerBound...].prefix(220))
        #expect(call.contains("CheckCharacter3DScene.selectedCharacter(defaults: store.characterDefaults).id")
                && call.contains("ownedIDs: store.ownedCharacterIDs"), "시작이 입은 것 · 가진 것을 안 넘긴다 — \(call)")

        #expect(V0317ShopTests.plainStore().peperoPrewarmGate === PeperoPrewarmGate.shared, "스토어 기본 문이 공용 문이 아니다 — 앱이 연 문과 다른 문을 두드린다")

        let art = V0366CakeMac3DTests.normalized(try V0366CakeMac3DTests.source("Sources/check/PeperoArt.swift"))
        #expect(art.contains("PeperoPrewarmGate.shared.rebakeForNewSheet {"), "새 판 다시 굽기가 문을 안 지난다 — 안 가진 사람도 굽는다")
        #expect(!art.contains("DispatchQueue.global"), "그림 저장소가 문 밖에서 장식을 굽는다")
    }

    @Test("새 판 다시 굽기: 구울 사람이면 시작 문 뒤 메인 밖에서 한 번 더 · 안 구울 사람 · 시작 전엔 안 굽는다")
    func newSheetRebakeFollowsTheGate() async throws {
        let (gate, spy) = Self.gate()
        let rebaked = V0377PrewarmBakeSpy()
        gate.rebakeForNewSheet { rebaked.record() }
        _ = gate.arm(after: 0, wornID: Self.aing, ownedIDs: [Self.aing])
        gate.rebakeForNewSheet { rebaked.record() }
        try await Self.settle()
        #expect(rebaked.onMain.isEmpty && gate.scheduledCount == 0, "안 구울 사람(또는 시작 전)에게 새 판을 구웠다 — \(rebaked.onMain)")
        try await Self.finish(gate.request())
        gate.rebakeForNewSheet { rebaked.record() }
        try await Self.settle()
        #expect(spy.onMain == [false] && rebaked.onMain == [false] && gate.scheduledCount == 2, "구울 사람의 새 판을 메인 밖에서 한 번 다시 굽지 않았다 — \(rebaked.onMain)")
    }
}
