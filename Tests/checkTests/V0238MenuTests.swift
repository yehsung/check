import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.2.38 α: 콕찌르기 패널의 초 단위 의존을 잎으로 (성능 감사 결함)
//
// 재현하는 결함: 근무 중 팝오버를 닫아도 CheckMenuView 뷰 트리가 상주하고, 1초 티커(store.displayNow)가 매초 팝오버
// 루트를 재평가·재레이아웃했다. 찔림 패널을 마지막으로 보고 닫으면 유휴 CPU 2.9%→4.46% (15초 샘플: main 비대기 317,
// NSHostingView.minSize/ViewGraph.sizeThatFits 113~115, PokePanel.body/entryList/sortedEntries/PokeDirectoryRowView.body
// 매초). 원인은 두 가지 루트 읽기였다 — CheckMenuView.body 의 `now: store.displayNow` /
// `isPokeDisconnected: shouldWarn(now: store.displayNow)` 와, PokePanel.rows 가 행마다 값으로 풀던
// `cooldownRemaining(entry.userID)`.
//
// 고친 뒤의 불변식(이 파일이 못 박는다):
//  (a) displayNow 를 60번 밀어도 팝오버 루트 body·PokePanel body·정렬·행 본체는 다시 돌지 않고, 초 단위 잎(MenuClockLeaf)만
//      60번 돈다. 정렬은 body 당 1회다(예전엔 3회).
//  (b) 쿨타임 만료 순간 버튼이 활성으로 바뀌는 UX 는 그대로다(잎이 매초 다시 판정한다).
//  (c) 팝오버가 닫혀 있으면(isMenuPresented == false) 잎조차 초침에 반응하지 않는다 — menuClockNow 가 displayNow 를
//      읽지 않는다. 재오픈은 MenuClockLeaf 의 controlActiveState 의존이 잎을 한 번 깨워 관찰을 되살린다.
//
// plist: 고정 이름 스위트 하나만 쓴다(UUID 스위트는 실행마다 ~/Library/Preferences 에 빈 plist 를 영구히 쌓는다 —
// 이 맥에 이미 15만 개가 있다).

// MARK: - 픽스처

private let v0238SuiteName = "check-v0238-menu-tests"
private let v0238TokenSuiteName = "check-v0238-menu-token-tests"

private func v0238Defaults(_ suiteName: String = v0238SuiteName) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 렌더용 격리 토큰 스토어(빈 홈 + 격리 defaults). 고정 경로다 — 이름이 매번 달라지면 tmp 에 홈이 쌓인다.
@MainActor
private func v0238InertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: v0238Defaults(v0238TokenSuiteName),
        homeDirectory: tmp.appendingPathComponent("check-v0238-menu-token-home", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0238-menu-token-cache.json", isDirectory: false)
    )
}

/// 콕찌르기 패널이 열린 로그인 스토어. 전원 근무중(= 쿨타임만 아니면 전 행이 활성 분기)이라 쿨타임 전이가 그림에서
/// 유일한 차이가 된다. 기본으로 u2 한 명이 now+37 까지 쿨타임 중이다.
@MainActor
private func makePokeStore(
    now: Date,
    memberCount: Int = 5,
    cooling: [String: TimeInterval] = ["u2": 37]
) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: v0238Defaults(),
        tokenUsage: v0238InertTokenStore()
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다(고정 displayNow 보존·티커 미발사).
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
    store.displayNow = now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    let names = ["영식", "민수", "지현", "서준", "하윤", "도현", "예린", "태우", "보라", "시우"]
    store.pokeDirectory = (0..<memberCount).map { index in
        PokeDirectoryEntry(userID: "u\(index + 1)", name: names[index % names.count], avatarURL: nil, isWorking: true)
    }
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    store.pokeCooldownUntil = cooling.mapValues { now.addingTimeInterval($0) }
    return store
}

@MainActor
private func cancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

// MARK: - 관찰 계측 (SwiftUI 가 하는 일을 흉내 낸다)

/// withObservationTracking 의 onChange(@Sendable)에서 결과를 받아 두는 상자. 통지는 값을 바꾼 그 스레드에서
/// 동기로 오므로(여기선 메인) 락 없이 안전하다.
private final class ObservationFlag: @unchecked Sendable {
    var value = false
}

/// 뷰 노드 하나의 "SwiftUI 식" 생애: body 를 평가하며 관찰 등록 → 등록한 값이 바뀌면 무효화 → 다음 기회에 재평가(재등록).
/// evaluations 가 곧 "그 노드의 body 가 몇 번 돌았는가"다.
@MainActor
private final class TrackedNode {
    private(set) var evaluations = 0
    private let flag = ObservationFlag()
    private let evaluate: () -> Void

    init(_ evaluate: @escaping () -> Void) {
        self.evaluate = evaluate
    }

    var isInvalidated: Bool { flag.value }

    func render() {
        evaluations += 1
        flag.value = false
        let flag = self.flag
        withObservationTracking { evaluate() } onChange: { flag.value = true }
    }

    /// 티커 한 틱 뒤 SwiftUI 가 할 일: 무효화된 노드만 다시 평가한다.
    func settle() {
        if flag.value { render() }
    }
}

/// SwiftUI 뷰 **값** 트리에서 타입 이름이 정확히 일치하는 노드의 값을 찾는다(패널이 private 타입이라 이름으로 잡는다).
/// 클래스로는 내려가지 않는다(스토어는 뷰 트리가 아니고 순환이 있다). 예산은 폭주 방지용이다.
private func findViewValue(named typeName: String, in value: Any, budget: inout Int) -> Any? {
    guard budget > 0 else { return nil }
    budget -= 1
    let mirror = Mirror(reflecting: value)
    if String(describing: mirror.subjectType) == typeName { return value }
    guard mirror.displayStyle != .class else { return nil }
    for child in mirror.children {
        if let found = findViewValue(named: typeName, in: child.value, budget: &budget) { return found }
    }
    return nil
}

/// CheckMenuView 루트 body 에서 PokePanel 값을 꺼내 `any View` 로 돌려준다.
@MainActor
private func extractPokePanel(from root: CheckMenuView) throws -> any View {
    var budget = 400_000
    let value = try #require(
        findViewValue(named: "PokePanel", in: root.body, budget: &budget),
        "콕찌르기 패널을 뷰 트리에서 못 찾았다 — 패널이 안 그려지거나 트리 모양이 바뀌었다."
    )
    return try #require(value as? any View)
}

/// 존재형 뷰의 body 를 연다(SE-0352 암묵적 열기). 결과는 다시 존재형이다.
@MainActor
private func evaluateBody(of view: any View) -> any View {
    view.body
}

// MARK: - 실제 SwiftUI 그래프 위의 계측

private enum V0238RenderError: Error { case failed }

/// 뷰 하나를 ImageRenderer 에 올려 **같은 그래프**를 유지한 채 다시 그린다. 관찰된 값이 바뀌면 SwiftUI 는 무효화된 노드만
/// 다시 평가하는데, 그 갱신은 런루프 한 바퀴 뒤에 처리되므로(첫 실측: 펌프 없이 nsImage 만 다시 읽으면 캐시된 그림이
/// 그대로 나온다) 매 렌더 앞에 메인 런루프를 잠깐 돌린다. 그러면 PokePanelRenderProbe 의 카운터가 곧
/// "어느 body 가 몇 번 돌았는가"가 된다 — 이 파일이 SwiftUI 의 재평가 반경을 실측하는 방법이다.
@MainActor
private final class LiveRenderHarness {
    private let renderer: ImageRenderer<AnyView>

    init(_ content: some View) {
        renderer = ImageRenderer(content: AnyView(content.frame(width: 340).fixedSize()))
        renderer.scale = 2
    }

    @discardableResult
    func render() throws -> Data {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw V0238RenderError.failed }
        return png
    }
}

/// 패널만 올린 하네스. 헤더 타이머(TodayTimerText)처럼 패널 밖에서 매초 바뀌는 픽셀을 빼고 **패널 픽셀만** 비교할 때 쓴다.
/// 패널 값은 루트 body 에서 한 번 꺼낸 스냅샷이라 entries 같은 값 입력은 굳어 있지만, 클로저는 살아 있어 잎은 시계를 따라간다.
@MainActor
private func panelHarness(for store: WorkTimerStore) throws -> LiveRenderHarness {
    LiveRenderHarness(AnyView(try extractPokePanel(from: CheckMenuView(store: store))))
}

// MARK: - 테스트

@MainActor
@Suite(.serialized)
struct V0238MenuTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: (a) 루트/패널 body 는 초침을 관찰하지 않는다

    @Test func menuRootAndPokePanelBodiesIgnoreSixtyTicks() throws {
        let store = makePokeStore(now: Self.t0)
        defer { cancelTasks(store) }
        let root = CheckMenuView(store: store)

        // 루트 body 를 SwiftUI 처럼 관찰 등록하며 1회 평가하고, 그 결과에서 패널 값을 꺼내 패널 body 도 1회 평가한다.
        var rootBody: Any = EmptyView()
        let rootNode = TrackedNode { rootBody = root.body }
        rootNode.render()
        var budget = 400_000
        let panelValue = try #require(findViewValue(named: "PokePanel", in: rootBody, budget: &budget))
        let panel = try #require(panelValue as? any View)
        PokePanelRenderProbe.reset()
        let panelNode = TrackedNode { _ = evaluateBody(of: panel) }
        panelNode.render()
        #expect(PokePanelRenderProbe.panelBodies == 1)
        #expect(PokePanelRenderProbe.sortCalls == 1, "정렬은 body 당 1회여야 한다(예전엔 rowCount/rows 가 각자 정렬해 3회였다).")

        // 티커 60틱. 어느 틱에서도 루트/패널은 무효화되지 않는다 — 초 단위 읽기는 잎(MenuClockLeaf) 안에서만 일어난다.
        for tick in 1...60 {
            store.displayNow = Self.t0.addingTimeInterval(TimeInterval(tick))
            rootNode.settle()
            panelNode.settle()
        }
        #expect(rootNode.evaluations == 1, "팝오버 루트 body 가 초침에 다시 돌았다 — `now: store.displayNow` 류의 루트 읽기가 되살아났다.")
        #expect(panelNode.evaluations == 1, "PokePanel body 가 초침에 다시 돌았다 — 패널이 시계/쿨타임 클로저를 직접 부르고 있다.")
        #expect(PokePanelRenderProbe.panelBodies == 1)
        #expect(PokePanelRenderProbe.sortCalls == 1, "60틱 동안 목록이 다시 정렬됐다 — 정렬은 entries 가 바뀔 때만 돌아야 한다.")

        // 대조군: 추적이 살아 있다. 루트가 실제로 읽는 값(찌르기 안내)이 바뀌면 루트는 반드시 다시 돈다.
        store.pokeNotice = "방금 찌른 상대예요"
        rootNode.settle()
        #expect(rootNode.evaluations == 2, "루트 추적이 소진됐거나 등록되지 않았다 — 위 단언들은 공허하다.")
    }

    // MARK: (a') 실제 SwiftUI 그래프: 60틱 동안 잎만 돈다

    @Test func onlyClockLeavesRedrawAcrossSixtyTicksOnTheLiveGraph() throws {
        let memberCount = 5
        let store = makePokeStore(now: Self.t0, memberCount: memberCount, cooling: ["u2": 600])
        defer { cancelTasks(store) }
        // 팝오버 전체를 올린다 — 패널 밖 잎(헤더 타이머 등)도 함께 돌지만 계측은 패널 서브트리만 센다. 전체를 올려야
        // 대조군(entries 변경 → 루트 재평가 → 패널 재구성)이 실제 앱과 같은 경로로 돈다.
        PokePanelRenderProbe.reset()
        let harness = LiveRenderHarness(CheckMenuView(store: store))
        try harness.render()
        // 첫 렌더: 패널 body 가 도는 만큼만 정렬한다(body 당 1회). 행 본체는 사람 수만큼, 잎은 행 속 버튼 + 안내줄.
        let firstPanelBodies = PokePanelRenderProbe.panelBodies
        #expect(firstPanelBodies >= 1)
        #expect(PokePanelRenderProbe.sortCalls == firstPanelBodies, "한 body 안에서 정렬이 여러 번 돌았다.")
        #expect(PokePanelRenderProbe.rowBodies >= memberCount)
        #expect(PokePanelRenderProbe.leafBodies >= memberCount + 1)

        // 60틱. 무효화된 노드만 다시 평가된다 — 잎(행마다 찌르기 버튼 1 + 안내줄 1)만 매 틱 돈다.
        PokePanelRenderProbe.reset()
        for tick in 1...60 {
            store.displayNow = Self.t0.addingTimeInterval(TimeInterval(tick))
            try harness.render()
        }
        #expect(PokePanelRenderProbe.panelBodies == 0, "PokePanel body 가 초침에 다시 돌았다(\(PokePanelRenderProbe.panelBodies)회).")
        #expect(PokePanelRenderProbe.sortCalls == 0, "60틱 동안 목록이 다시 정렬됐다(\(PokePanelRenderProbe.sortCalls)회).")
        #expect(PokePanelRenderProbe.rowBodies == 0, "행 본체가 초침에 다시 돌았다(\(PokePanelRenderProbe.rowBodies)회) — 행이 쿨타임 클로저를 직접 부르고 있다.")
        #expect(
            PokePanelRenderProbe.leafBodies == 60 * (memberCount + 1),
            "잎은 틱마다 정확히 (행 수 + 안내줄) 만큼 돌아야 한다: 기대 \(60 * (memberCount + 1)), 실측 \(PokePanelRenderProbe.leafBodies)."
        )

        // 대조군: 입력(entries)이 바뀌면 루트가 다시 돌아 패널 body 와 정렬이 돈다 — 계측이 살아 있고, 정렬은 그때만 한다.
        PokePanelRenderProbe.reset()
        store.pokeDirectory = Array(store.pokeDirectory.dropLast())
        try harness.render()
        #expect(PokePanelRenderProbe.panelBodies >= 1, "entries 변경에 패널이 다시 돌지 않았다 — 계측/그래프가 죽어 있다.")
        #expect(PokePanelRenderProbe.sortCalls == PokePanelRenderProbe.panelBodies, "한 body 안에서 정렬이 여러 번 돌았다.")
        #expect(PokePanelRenderProbe.rowBodies >= memberCount - 1)
    }

    // MARK: (b) 쿨타임 만료 순간 버튼이 활성으로 바뀐다 (기존 UX 불변)

    @Test func cooldownExpiryStillFlipsTheButtonToActiveOnTheLiveGraph() throws {
        let store = makePokeStore(now: Self.t0, cooling: ["u2": 37])
        defer { cancelTasks(store) }
        let harness = try panelHarness(for: store)
        let cooling = try harness.render()

        // 만료 1초 전까지는 그대로(흐린 비활성).
        store.displayNow = Self.t0.addingTimeInterval(36)
        #expect(try harness.render() == cooling, "만료 전인데 그림이 바뀌었다.")
        // 만료 순간 활성(accent 원형)으로 바뀐다 — 잎이 매초 다시 판정한 결과다.
        store.displayNow = Self.t0.addingTimeInterval(37)
        let expired = try harness.render()
        #expect(expired != cooling, "쿨타임이 끝났는데 버튼이 흐린 채다 — 잎이 시계를 읽지 않거나 값이 굳었다.")

        // 대조군: 처음부터 쿨타임이 없던 패널과 바이트까지 같다 = 만료 뒤 화면은 '쿨타임 없음'과 구별되지 않는다.
        let control = makePokeStore(now: Self.t0, cooling: [:])
        defer { cancelTasks(control) }
        let never = try panelHarness(for: control).render()
        #expect(expired == never)
    }

    // MARK: (c) 닫힌 팝오버의 잎은 초침에 반응하지 않는다

    @Test func closedPopoverFreezesTheClockAndTheLeaves() throws {
        let store = makePokeStore(now: Self.t0, cooling: ["u2": 37])
        defer { cancelTasks(store) }

        // 시계 게이트 자체: 열려 있으면 displayNow, 닫혀 있으면 고정값(displayNow 를 읽지 않는다).
        #expect(store.menuClockNow == Self.t0)
        store.isMenuPresented = false
        #expect(store.menuClockNow == WorkTimerStore.menuClockFrozen)
        let clockNode = TrackedNode { _ = store.menuClockNow }
        clockNode.render()
        store.displayNow = Self.t0.addingTimeInterval(1)
        #expect(!clockNode.isInvalidated, "닫힌 팝오버의 menuClockNow 가 displayNow 를 읽었다 — 게이트가 없다.")

        // 실제 그래프: 닫힌 채 60틱을 밀어도 **아무 body 도** 돌지 않고, 쿨타임이 끝난 뒤에도 그림은 굳어 있다.
        // (고정값 distantPast 는 "아직 시작 안 함" — 쿨타임 중이던 대상은 계속 흐리고, 나머지는 그대로 활성이다.)
        let harness = try panelHarness(for: store)
        let frozen = try harness.render()
        PokePanelRenderProbe.reset()
        for tick in 1...60 {
            store.displayNow = Self.t0.addingTimeInterval(TimeInterval(tick))
            #expect(try harness.render() == frozen)
        }
        #expect(PokePanelRenderProbe.panelBodies == 0)
        #expect(PokePanelRenderProbe.rowBodies == 0)
        #expect(PokePanelRenderProbe.leafBodies == 0, "닫힌 팝오버에서 잎이 초침에 돌았다(\(PokePanelRenderProbe.leafBodies)회) — 게이트가 새고 있다.")

        // 닫힌 채의 그림은 '열린 채 t0'의 그림과 같다(u2 흐림·나머지 활성) — 고정값이 안전한 쪽(못 찌름)으로 굳는다.
        let openAtT0 = makePokeStore(now: Self.t0, cooling: ["u2": 37])
        defer { cancelTasks(openAtT0) }
        #expect(try panelHarness(for: openAtT0).render() == frozen)
    }

    @Test func menuClockLeafStopsTrackingWhenClosedAndResumesAfterOneReevaluation() {
        let store = makePokeStore(now: Self.t0, cooling: ["u2": 37])
        defer { cancelTasks(store) }
        // 프로덕션과 같은 모양의 잎: 읽기 클로저가 menuClockNow 를 거쳐 쿨타임 잔여를 계산한다.
        let leaf = MenuClockLeaf(read: { store.pokeCooldownRemaining(for: "u2", now: store.menuClockNow) }) { remaining in
            Text("\(remaining)")
        }
        let node = TrackedNode { _ = leaf.body }

        // 열림: 틱마다 무효화 → 재평가(60틱이면 61회).
        node.render()
        for tick in 1...60 {
            store.displayNow = Self.t0.addingTimeInterval(TimeInterval(tick))
            node.settle()
        }
        #expect(node.evaluations == 61, "열린 팝오버의 잎은 틱마다 돌아야 한다(만료 순간을 그 잎이 잡는다).")

        // 열림→닫힘: 마지막 등록이 남아 있어 **다음 한 틱**에 한 번 더 돌고(닫힌 가지로 옮겨 앉음), 그 뒤로는 조용하다.
        store.isMenuPresented = false
        store.displayNow = Self.t0.addingTimeInterval(61)
        node.settle()
        #expect(node.evaluations == 62)
        for tick in 62...120 {
            store.displayNow = Self.t0.addingTimeInterval(TimeInterval(tick))
            node.settle()
        }
        #expect(node.evaluations == 62, "닫힌 팝오버의 잎이 초침에 돌았다 — menuClockNow 게이트가 없다.")

        // 닫힘→열림: 등록이 비어 있어 displayNow 갱신만으로는 깨어나지 못한다(설계상 사실 — 그래서 MenuClockLeaf 가
        // controlActiveState 에 의존한다). 창이 키를 얻어 잎이 **한 번** 재평가되면 그 뒤로는 다시 틱마다 돈다.
        store.isMenuPresented = true
        store.displayNow = Self.t0.addingTimeInterval(121)
        node.settle()
        #expect(node.evaluations == 62)
        node.render()                                   // = 창 키 획득이 만드는 재평가
        store.displayNow = Self.t0.addingTimeInterval(122)
        node.settle()
        #expect(node.evaluations == 64, "재오픈 뒤 첫 재평가가 displayNow 관찰을 되살리지 못했다.")
    }

    @Test func frozenClockReadsAsSafeSideEverywhereItIsConsumed() {
        // 닫힌 팝오버의 고정값이 각 소비처에서 트랩 없이, '못 찌름/경고 없음/방금' 쪽으로 읽히는지 값으로 못 박는다.
        let frozen = WorkTimerStore.menuClockFrozen
        let store = makePokeStore(now: Self.t0, cooling: ["u2": 37])
        defer { cancelTasks(store) }
        store.messageCooldownUntil = ["u3": Self.t0.addingTimeInterval(20)]
        #expect(store.pokeCooldownRemaining(for: "u2", now: frozen) > 0)         // 쿨타임 중이던 사람은 계속 못 찌름
        #expect(store.pokeCooldownRemaining(for: "u1", now: frozen) == 0)        // 기록 없는 사람은 그대로 활성
        #expect(store.messageCooldownRemaining(for: "u3", now: frozen) > 0)
        #expect(PokeMessageReceiptStrip.ageText(receivedAt: Self.t0, now: frozen) == "방금")
        let backoff = Backoff(attempt: 3, retryAt: Self.t0, failingSince: Self.t0.addingTimeInterval(-3_600))
        #expect(!PokeConnectionNotice.shouldWarn(state: .reconnecting(backoff), now: frozen))
        // .failed 는 시계와 무관하게 경고다 — 고정값이 그 사실까지 지우지는 않는다.
        #expect(PokeConnectionNotice.shouldWarn(state: .failed(backoff, .exhausted), now: frozen))
    }

    // MARK: 소스 계약 — 의존이 어디에 있는지 (런타임 계측이 못 보는 자리를 문자열로 못 박는다)

    @Test func popoverRootPassesTheClockAsClosuresNeverAsValues() throws {
        let source = swiftCodeStrippingComments(try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8))
        let root = try #require(swiftTypeBody(source, name: "CheckMenuView"))
        #expect(
            !root.contains("store.displayNow"),
            "CheckMenuView body 가 displayNow 를 값으로 읽는다 — 그 한 줄이 팝오버 전체를 매초 무효화한다(감사 결함의 원형)."
        )
        #expect(root.contains("clock: { store.menuClockNow }"), "패널의 시계는 menuClockNow 를 읽는 클로저여야 한다(닫힘 게이트 포함).")
        #expect(root.contains("cooldownRemaining: { store.pokeCooldownRemaining(for: $0, now: store.menuClockNow) }"))
        #expect(root.contains("messageCooldownRemaining: { store.messageCooldownRemaining(for: $0, now: store.menuClockNow) }"))
        #expect(root.contains("isPokeDisconnected: {"), "연결 경고 판정은 클로저로 넘겨 안내줄 잎이 불러야 한다.")
        #expect(!root.contains("isPokeDisconnected: PokeConnectionNotice.shouldWarn("))
    }

    @Test func pokePanelAndRowNeverCallTheClockThemselves() throws {
        let source = swiftCodeStrippingComments(try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8))

        let panel = try #require(swiftTypeBody(source, name: "PokePanel"))
        #expect(!panel.contains("displayNow"), "PokePanel 이 displayNow 를 안다 — 값+클로저 설계가 깨졌다.")
        #expect(!panel.contains("let now: Date"), "루트 `now` 저장 프로퍼티가 되살아났다 — 그게 팝오버 루트의 초 단위 의존이었다.")
        #expect(!panel.contains("Date()"))
        #expect(panel.contains("let clock: () -> Date"))
        #expect(panel.contains("MenuClockLeaf(read: clock)"), "수신 시각은 잎이 읽어야 한다.")
        #expect(!panel.contains("clock()"), "패널 body 가 시계를 직접 불렀다.")
        #expect(
            panel.contains("cooldownRemaining: { cooldownRemaining(entry.userID) }"),
            "행에는 쿨타임 **읽기 클로저**를 내려야 한다 — 값으로 풀면 패널 body 가 초당 재평가로 돌아간다."
        )
        #expect(!panel.contains("remainingCooldown: cooldownRemaining("))
        for line in panel.split(separator: "\n") where line.contains("messageCooldownRemaining(entry.userID)") {
            #expect(line.contains("MenuClockLeaf(read:"), "작성기 쿨타임은 잎 안에서만 읽어야 한다: \(line.trimmingCharacters(in: .whitespaces))")
        }
        #expect(!panel.contains("isPokeDisconnected()"), "연결 경고 판정을 패널 body 가 직접 불렀다.")
        #expect(panel.contains("PokePanelNoticeLine("), "안내줄이 잎(PokePanelNoticeLine)이 아니다.")
        // 정렬은 body 맨 위에서 한 번 — computed 프로퍼티(sortedEntries)로 되돌리면 한 body 에 세 번 정렬한다.
        #expect(panel.contains("let sorted = Self.sortedForDisplay(entries)"))
        #expect(!panel.contains("var sortedEntries"))

        let row = try #require(swiftTypeBody(source, name: "PokeDirectoryRowView"))
        #expect(row.contains("let cooldownRemaining: () -> Int"))
        #expect(row.contains("MenuClockLeaf(read: cooldownRemaining)"), "찌르기 버튼의 쿨타임 판정은 잎 안에서만 읽어야 한다.")
        #expect(!row.contains("cooldownRemaining()"), "행 본체가 쿨타임 클로저를 직접 불렀다 — 행 전체가 매초 돈다.")

        let notice = try #require(swiftTypeBody(source, name: "PokePanelNoticeLine"))
        #expect(notice.contains("MenuClockLeaf(read: isPokeDisconnected)"))
        #expect(!notice.contains("isPokeDisconnected()"))
    }

    @Test func menuClockLeafDependsOnWindowKeyStateSoReopenWakesIt() throws {
        // 닫힌 동안 잎의 관찰 등록이 비므로(위 테스트), 재오픈 때 잎을 깨우는 것은 이 환경값 의존 하나뿐이다.
        // 이 줄을 지우면 헤드리스 테스트는 전부 초록인 채로, 실제 앱에서 팝오버를 다시 열었을 때 쿨타임 버튼이
        // 다음 디렉토리 폴링(최대 30초)까지 굳는다.
        let source = swiftCodeStrippingComments(try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8))
        let leaf = try #require(swiftTypeBody(source, name: "MenuClockLeaf"))
        #expect(leaf.contains("@Environment(\\.controlActiveState)"), "재오픈 트리거(controlActiveState 의존)가 사라졌다.")
        #expect(leaf.contains("content(read())"), "읽기는 잎 body 안에서 일어나야 한다.")
    }
}

// MARK: - 소스 계약 헬퍼 (CheckMenuRenderTests 의 것과 같은 규약 — 그 파일의 헬퍼는 private 이다)

private func checkMenuViewSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/V0238MenuTests.swift
        .deletingLastPathComponent()          // Tests/checkTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // (repo root)
        .appendingPathComponent("Sources/check/CheckMenuView.swift")
}

/// 소스에서 주석(`//` 줄 주석 · `/* */` 블록 주석)을 걷어낸 코드만 남긴다. 이 저장소는 "왜"를 주석에 길게 적으므로,
/// 주석을 안 걷으면 설명문이 단언에 걸려 **설명을 지워야만 초록**이 된다.
private func swiftCodeStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}

/// `struct <name>` 선언(제네릭 `<...>` 포함)의 중괄호 본문만 잘라 낸다(중괄호 균형으로 끝을 찾는다).
private func swiftTypeBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "struct \(name):") ?? source.range(of: "struct \(name)<"),
          let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex)
    else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open.upperBound..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}
