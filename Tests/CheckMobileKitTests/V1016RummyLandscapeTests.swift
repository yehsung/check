@testable import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 판 화면만 가로(설계서 §10). 가장 나쁜 고장은 **잠금이 가로에 남아 앱 전체가 가로로 굳는 것**이다 — 빠져나가는 길마다 방향 값을 잰다.
// 끌기는 합성 입력이 금지이니 다섯 크기에서 "손 궤적 → 놓을 자리 → 편집기 결과" 를 값으로 밟는다.
@MainActor
@Suite(.serialized) struct V1016RummyLandscapeTests {
    private let waits = GamesWaitBudget()

    static let screens = [CGSize(width: 568, height: 320), CGSize(width: 667, height: 354), CGSize(width: 734, height: 372), CGSize(width: 852, height: 393), CGSize(width: 932, height: 430)]

    // MARK: - 방향 규칙

    @Test("방향 규칙 표: 화면이 보이고 판이 도는 동안 + [최종 판]만 가로 · 나머지는 전부 세로")
    func ruleTable() {
        typealias Rule = GamesRummyOrientationRule
        let table: [(RummyStore.Phase, Bool, Bool, Bool)] = [
            (.lobby, false, false, false), (.lobby, false, true, false), (.lobby, true, false, false), (.lobby, true, true, false),
            (.room, false, false, false), (.room, false, true, false), (.room, true, false, false), (.room, true, true, false),
            (.playing, false, false, false), (.playing, false, true, false), (.playing, true, false, true), (.playing, true, true, true),
            (.finished, false, false, false), (.finished, false, true, false), (.finished, true, false, false), (.finished, true, true, true),
        ]
        for (phase, visible, board, wanted) in table {
            #expect(Rule.wants(phase: phase, isScreenVisible: visible, finalBoardShown: board) == wanted, "\(phase) \(visible) \(board)")
            #expect(Rule.orientation(phase: phase, isScreenVisible: visible, finalBoardShown: board) == (wanted ? .landscape : .portrait))
        }
    }

    // MARK: - 빠져나가는 길

    private func playing(_ label: String) async -> RummyWireHarness {
        let harness = RummyWireHarness(label: label)
        harness.serveLobby()
        await harness.signIn()
        #expect(harness.games.rummyInterfaceOrientation == .portrait, "로그인 직후가 세로가 아니다")
        harness.games.rummyScreenDidAppear()
        await harness.barrier()
        #expect(harness.games.rummyInterfaceOrientation == .portrait, "로비가 세로가 아니다")
        harness.apply()
        #expect(harness.rummy.phase == .playing)
        #expect(harness.games.rummyInterfaceOrientation == .landscape, "판 화면이 가로가 아니다")
        return harness
    }

    @Test("들어오고 나가기: 판 화면이 사라지면 세로 · 돌아오면 가로(로비가 든 판을 다시 읽는다) · 앱을 내렸다 올려도 가로 그대로")
    func screenLifetime() async {
        let harness = await playing("rummy-orient-life")
        harness.serveLobby(activeMatchID: RummyWireHarness.matchID)
        harness.server.setDefault("rummy_state", json: #"{"status":"ok","state":\#(RummyWireJSON.state(nowMs: harness.nowMs, status: "active", mySeatState: "playing", turnSeat: 1))}"#)
        harness.games.rummyScreenDidDisappear()
        #expect(harness.games.rummyInterfaceOrientation == .portrait, "화면이 사라졌는데 가로에 남았다")
        harness.games.rummyScreenDidAppear()
        #expect(await waits.wait { harness.rummy.phase == .playing }, "돌아왔는데 판이 안 선다")
        #expect(harness.games.rummyInterfaceOrientation == .landscape)
        harness.games.appDidEnterBackground()
        #expect(harness.games.rummyInterfaceOrientation == .landscape, "앱을 내리는 것은 화면을 떠나는 것이 아니다")
        harness.games.rummyScreenDidDisappear()
        await harness.tearDown()
    }

    @Test("판이 끝나 결과로: 세로 · [최종 판]을 펴면 가로 · 접으면 세로 · 로비로 나가면 세로")
    func resultAndFinalBoard() async {
        let harness = await playing("rummy-orient-result")
        let games = harness.games
        harness.apply(status: "finished", mySeatState: "done")
        #expect(harness.rummy.phase == .finished)
        #expect(games.rummyInterfaceOrientation == .portrait, "결과가 가로에 남았다")
        games.setRummyFinalBoardShown(true)
        #expect(games.isRummyFinalBoardShown)
        #expect(games.rummyInterfaceOrientation == .landscape, "[최종 판]이 가로가 아니다")
        games.setRummyFinalBoardShown(false)
        #expect(games.rummyInterfaceOrientation == .portrait)
        games.setRummyFinalBoardShown(true)
        harness.rummy.dismissResult()
        await harness.barrier()
        #expect(harness.rummy.phase != .finished)
        #expect(games.rummyInterfaceOrientation == .portrait, "결과를 닫았는데 가로에 남았다")
        #expect(!games.isRummyFinalBoardShown)
        games.setRummyFinalBoardShown(true)
        #expect(!games.isRummyFinalBoardShown, "결과가 아닌데 최종 판이다")
        await harness.tearDown()
    }

    @Test("[최종 판]을 편 채 다른 판의 결과가 서면 표시를 물려받지 않는다(저절로 가로가 안 된다)")
    func finalBoardNotInherited() async throws {
        let harness = await playing("rummy-orient-next-result")
        let games = harness.games
        harness.apply(status: "finished", mySeatState: "done")
        games.setRummyFinalBoardShown(true)
        #expect(games.rummyInterfaceOrientation == .landscape, "기준선: 앞 판의 [최종 판]이 가로가 아니다")

        let next = "a0000000-0000-4000-8000-0000000000f2"
        let text = RummyWireJSON.state(nowMs: harness.nowMs, id: next, status: "finished", mySeatState: "done", turnSeat: 1)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let state = try decoder.decode(RummyMatchState.self, from: Data(text.utf8))
        #expect(harness.rummy.applyState(state) == .applied)
        #expect(harness.rummy.match?.id == UUID(uuidString: next), "기준선: 다음 판이 안 섰다")
        #expect(harness.rummy.phase == .finished, "기준선: 다음 판이 결과가 아니다")
        #expect(!games.isRummyFinalBoardShown, "다음 판 결과가 표시를 물려받았다")
        #expect(games.rummyInterfaceOrientation == .portrait, "다음 판 결과가 저절로 가로가 됐다")
        await harness.tearDown()
    }

    @Test("[최종 판]을 편 채 화면이 사라지면 표시도 지운다(돌아와도 저절로 가로가 안 된다)")
    func finalBoardClearedWithTheScreen() async {
        let harness = await playing("rummy-orient-board-gone")
        harness.apply(status: "finished", mySeatState: "done")
        harness.games.setRummyFinalBoardShown(true)
        harness.games.rummyScreenDidDisappear()
        #expect(harness.games.rummyInterfaceOrientation == .portrait)
        #expect(!harness.games.isRummyFinalBoardShown)
        await harness.tearDown()
    }

    @Test("로그아웃 · 세션 끝 · reset: 화면이 사라졌다는 소식 없이도 세로다")
    func sessionEnd() async {
        let signOut = await playing("rummy-orient-signout")
        await signOut.model.session.signOut()
        await signOut.barrier()
        #expect(signOut.games.rummyInterfaceOrientation == .portrait, "로그아웃했는데 가로에 남았다")
        #expect(!signOut.games.isRummyScreenVisible)
        await signOut.tearDown()

        let store = await playing("rummy-orient-reset")
        store.games.reset()
        #expect(store.games.rummyInterfaceOrientation == .portrait, "화면 깃발을 내렸는데 가로에 남았다")
        await store.tearDown()

        let core = await playing("rummy-orient-core-reset")
        core.rummy.reset()
        #expect(core.rummy.phase == .lobby)
        #expect(core.games.rummyInterfaceOrientation == .portrait, "코어가 비었는데 가로에 남았다")
        core.games.rummyScreenDidDisappear()
        await core.tearDown()
    }

    @Test("이 기기가 큐브를 못 하는 안내가 서 있으면 판을 안 그리니 세로다")
    func unavailableIsPortrait() async {
        let harness = await playing("rummy-orient-update")
        harness.rummy.availability = .updateRequired
        #expect(harness.games.rummyInterfaceOrientation == .portrait)
        harness.rummy.availability = .available
        #expect(harness.games.rummyInterfaceOrientation == .landscape)
        harness.games.rummyScreenDidDisappear()
        await harness.tearDown()
    }

    @Test("놀던 기기의 판을 그냥 닫기: 아무 요청 없이 세로로 돌아간다")
    func idleDeviceLeaves() async {
        let harness = await playing("rummy-orient-idle")
        #expect(!harness.rummy.isEngagedInCurrentMatch)
        let leaves = harness.count("rummy_leave")
        harness.games.rummyScreenDidDisappear()
        await harness.barrier()
        #expect(harness.games.rummyInterfaceOrientation == .portrait)
        #expect(harness.count("rummy_leave") == leaves, "놀던 기기가 나가기를 보냈다")
        await harness.tearDown()
    }

    // MARK: - 판 위에 스스로 뜨는 시트

    @Test("알림 설명 시트: 판이 가로로 서 있으면 미룬다 · 세로로 돌아오면 다시 판정한다")
    func primerWaitsForPortrait() async {
        let harness = RummyWireHarness(label: "rummy-orient-primer")
        harness.serveLobby()
        await harness.signIn()
        let push = harness.model.push
        #expect(push.shouldPresentPrimer(status: .notDetermined), "기준선: 판 밖에서는 띄울 때다")
        harness.games.rummyScreenDidAppear()
        await harness.barrier()
        harness.apply()
        #expect(harness.games.rummyInterfaceOrientation == .landscape)
        #expect(!push.shouldPresentPrimer(status: .notDetermined), "가로 판 위에 설명 시트가 뜬다")
        harness.apply(status: "finished", mySeatState: "done")
        #expect(push.shouldPresentPrimer(status: .notDetermined), "결과(세로)인데 안 띄운다")
        harness.games.setRummyFinalBoardShown(true)
        #expect(!push.shouldPresentPrimer(status: .notDetermined), "[최종 판](가로) 위에 설명 시트가 뜬다")
        harness.games.rummyScreenDidDisappear()
        #expect(push.shouldPresentPrimer(status: .notDetermined))
        await harness.tearDown()
    }

    @Test("생일 선물 시트: 놀던 기기의 가로 판 위에 안 뜬다(확성기는 뜬다) · 판을 떠나면 다음 기회에 뜬다")
    func giftWaitsForPortrait() async throws {
        let harness = await playing("rummy-orient-gift")
        #expect(!harness.rummy.isEngagedInCurrentMatch)
        #expect(!harness.games.isAnyMatchScreenVisible, "기준선: 놀던 기기는 확성기를 안 미룬다")
        #expect(harness.model.me.isGameScreenUp, "놀던 기기의 가로 판 위에 선물 시트가 뜬다")
        harness.games.rummyScreenDidDisappear()
        #expect(!harness.model.me.isGameScreenUp)
        await harness.tearDown()

        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root.contains("model.games.rummyInterfaceOrientation != .landscape"), "시트 바인딩이 가로 판을 안 피한다")
    }

    // MARK: - 소스 — 시스템 쪽 배선은 시뮬레이터 빌드만 본다

    @Test("소스 계약: 방향 합이 plist · project.yml 에 있고 · 델리게이트는 패키지 값만 돌려주고 · 잠금은 값을 쥐지 않고 · 드라이버는 루트에 있다")
    func systemWiring() throws {
        let names = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
        let plist = try IntegrationContractTests.code("ios/App/Info.plist")
        let yml = try IntegrationContractTests.code("ios/project.yml")
        for name in names {
            #expect(plist.contains(name), "\(name)")
            #expect(yml.contains(name), "\(name)")
        }
        // 첫 번째가 세로여야 앱이 세로로 뜬다.
        #expect(plist.range(of: names[0])!.lowerBound < plist.range(of: names[1])!.lowerBound)
        let delegate = try IntegrationContractTests.code("ios/App/AppDelegate.swift")
        #expect(delegate.contains("supportedInterfaceOrientationsFor window"))
        #expect(delegate.contains("model.supportedInterfaceOrientations"))
        let orientation = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyOrientation.swift")
        #expect(!orientation.contains("static var"), "잠금이 값을 쥐면 푸는 길을 잊을 수 있다")
        #expect(orientation.contains("games.rummyInterfaceOrientation"))
        #expect(orientation.contains("requestGeometryUpdate"))
        #expect(orientation.contains("setNeedsUpdateOfSupportedInterfaceOrientations"))
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root.contains("GamesRummyOrientationDriver(games: model.games)"), "알리는 자리가 없으면 돌지 않는다")
    }

    @Test("돌기를 기다리는 동안 전환을 다시 청한다(앱 복귀까지 기다리면 차례 시간이 흐른다) · 나갈 길이 늘 있다")
    func rotatingViewRetries() throws {
        #expect(GamesRummyOrientationRule.retryInterval > 0 && GamesRummyOrientationRule.retryInterval <= 2)
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyMatch.swift")
        let view = try #require(match.components(separatedBy: "struct GamesRummyRotatingView").last)
        #expect(view.contains("GamesRummyOrientationRule.retryInterval"))
        #expect(view.contains("GamesRummyOrientationLock.apply(games.rummyInterfaceOrientation)"), "값을 고정하면 나가는 중에도 가로를 청한다")
        #expect(view.contains("accessibilityLabel: GamesRummyText.leave"))
        #expect(view.contains(".onDisappear { retryTask?.cancel() }"), "돌고 나서도 계속 청한다")
    }

    @Test("반응: 판의 작은 판과 결과의 시트는 값이 따로다 — 하나로 쓰면 작은 판을 연 채 판이 끝날 때 시트가 떴다 내려간다")
    func reactionStatesAreSeparate() throws {
        let screen = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyScreen.swift")
        #expect(screen.contains("GamesRummyMatchView(store: store, onExit: requestExit, onReaction: { reactionPanelOpen = true })"))
        #expect(screen.contains("GamesRummyResultView(store: store, inviteQueue: inviteQueue, onReaction: { reactionSheetOpen = true })"))
        #expect(screen.contains(".sheet(isPresented: $reactionSheetOpen)"))
    }

    @Test("규칙 문구: [전체 보기] 자리를 지금 배치대로 말한다")
    func rulesSayWhereFullViewIs() throws {
        let view = try #require(GamesRummyText.rules.first { $0.title == "판 보기" })
        #expect(view.detail.contains("오른쪽 열 위쪽 버튼"))
        #expect(!view.detail.contains("판 오른쪽 아래"))
    }

    // MARK: - 크기 변경

    private func editor() -> RummyTurnEditor { GamesRummyMatchInputTests.editor() }

    @Test("크기 변경: 처음 재는 것은 변화가 아니다 · 끌기 · 누르기 · 밀기 · 핀치를 거두고 손 뗄 때까지 무시한다 · 뗀 다음 손은 새로 분류된다")
    func screenSizeChange() {
        let size = CGSize(width: 734, height: 372)
        let context = GamesRummyMatchInputTests.context(size: size)
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let start = GamesRummyMatchInputTests.rackPoint("C2", context)
        let moved = CGPoint(x: start.x, y: start.y - 100)

        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        model.touchChanged(start: start, location: moved, context: context)
        model.screenSizeChanged(size)
        #expect(model.drag != nil, "처음 재는 크기에 끌기가 거둬졌다")
        model.screenSizeChanged(size)
        #expect(model.drag != nil, "같은 크기인데 거둬졌다")

        // 끌기 → 돌았다.
        model.screenSizeChanged(CGSize(width: 372, height: 734))
        #expect(model.drag == nil && model.draggingIDs.isEmpty && model.frozenRows == nil)
        #expect(!model.machine.isIdle, "쉬는 상태면 다음 사건이 처음 누른 자리를 다시 집는다")
        model.touchChanged(start: start, location: CGPoint(x: moved.x + 30, y: moved.y), context: context)
        #expect(model.drag == nil, "손을 안 뗐는데 다시 집혔다")
        #expect(model.touchEnded(at: moved, context: context) == .none, "거둔 끌기가 놓였다")
        #expect(model.machine.isIdle)
        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        #expect(!model.machine.isIdle)
        model.touchChanged(start: start, location: moved, context: context)
        #expect(model.drag != nil, "다음 손이 안 먹는다")
        model.cancelTouch()

        // 판 밀기 → 돌았다.
        model.screenSizeChanged(size)
        let felt = GamesRummyMatchInputTests.screen(CGPoint(x: 300, y: 300), context)
        model.touchChanged(start: felt, location: felt, context: context)
        model.touchChanged(start: felt, location: CGPoint(x: felt.x, y: felt.y - 20), context: context)
        let origin = model.viewport.origin
        #expect(origin.y > 0)
        model.screenSizeChanged(CGSize(width: 800, height: 372))
        model.touchChanged(start: felt, location: CGPoint(x: felt.x, y: felt.y - 80), context: context)
        #expect(model.viewport.origin == origin, "돈 뒤에도 밀린다")
        _ = model.touchEnded(at: felt, context: context)

        // 핀치 → 돌았다: 닫혀야 다음 핀치가 낡은 기준에서 안 튄다.
        model.screenSizeChanged(size)
        model.pinch(magnification: 1.3, tableAnchor: .zero)
        #expect(model.renderScale != model.viewport.scale)
        model.screenSizeChanged(CGSize(width: 800, height: 372))
        #expect(model.renderScale == model.viewport.scale, "핀치가 열린 채 남았다")
        model.cancelTouch()
    }

    @Test("왼쪽 가로 ↔ 오른쪽 가로(크기가 같다): 처음 재는 것과 같은 쪽은 변화가 아니다 · 뒤집히면 끌기 · 밀기 · 핀치를 거두고 손 뗄 때까지 무시한다")
    func landscapeFlip() {
        let size = CGSize(width: 734, height: 372)
        let context = GamesRummyMatchInputTests.context(size: size)
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let start = GamesRummyMatchInputTests.rackPoint("C2", context)
        let moved = CGPoint(x: start.x, y: start.y - 100)

        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        model.touchChanged(start: start, location: moved, context: context)
        model.landscapeSideChanged(.left)
        #expect(model.drag != nil, "처음 재는 방향에 끌기가 거둬졌다")
        model.landscapeSideChanged(.left)
        #expect(model.drag != nil, "같은 쪽인데 거둬졌다")

        model.landscapeSideChanged(.right)
        #expect(model.drag == nil && model.draggingIDs.isEmpty && model.frozenRows == nil, "뒤집혔는데 타일을 쥐고 있다")
        #expect(!model.machine.isIdle, "쉬는 상태면 다음 사건이 처음 누른 자리를 다시 집는다")
        model.touchChanged(start: start, location: CGPoint(x: moved.x + 30, y: moved.y), context: context)
        #expect(model.drag == nil, "손을 안 뗐는데 다시 집혔다")
        #expect(model.touchEnded(at: moved, context: context) == .none, "거둔 끌기가 놓였다")
        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        model.touchChanged(start: start, location: moved, context: context)
        #expect(model.drag != nil, "다음 손이 안 먹는다")
        model.cancelTouch()

        model.pinch(magnification: 1.3, tableAnchor: .zero)
        #expect(model.renderScale != model.viewport.scale)
        model.landscapeSideChanged(.left)
        #expect(model.renderScale == model.viewport.scale, "핀치가 열린 채 남았다")
        model.cancelTouch()
    }

    @Test("자동 밀기(다섯 크기): 받침대 → 판 길목에서는 안 민다 · 안쪽에 한 번 들어온 뒤에는 민다 · 판 아래로 나갔다 오면 다시 꺼진다 · 판에서 출발한 끌기는 처음부터 민다")
    func edgeArming() {
        for size in Self.screens {
            let base = editor()
            let c = context(base, size)
            let table = c.layout.table
            let model = GamesRummyMatchModel(tableSize: table.size)
            model.tableSizeChanged(table.size)
            let start = rackPoint("D9", c)
            let finger: (CGFloat, CGFloat) -> CGPoint = { c.layout.finger(forPointer: CGPoint(x: $0, y: $1)) }
            #expect(model.viewport.origin == .zero)
            #expect(GamesRummyViewport(viewport: table.size).visibleLogical.height < 640, "\(size) 기준선: 밀 수 있는 보기가 아니다")

            // 손이 초당 200pt 로 받침대 → 판 윗줄까지. 틱마다 잰다.
            model.touchChanged(start: start, location: start, context: c, holdDelay: 3_600)
            let aim = finger(table.midX, table.minY + 40)
            let steps = max(1, Int(hypot(aim.x - start.x, aim.y - start.y) / 3.2))
            var sawZone = false
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let at = CGPoint(x: start.x + (aim.x - start.x) * t, y: start.y + (aim.y - start.y) * t)
                model.touchChanged(start: start, location: at, context: c)
                if let pointer = model.drag?.pointer, table.contains(pointer), pointer.y > table.maxY - GamesRummyViewport.edgeZone { sawZone = true }
                model.edgeTick(deltaTime: 0.016)
                #expect(model.viewport.origin == .zero, "\(size) \(step)/\(steps): 지나가는 길에 판이 밀렸다 \(model.viewport.origin)")
            }
            #expect(sawZone, "\(size) 기준선: 궤적이 아래쪽 구역을 안 지났다")

            // 안쪽에 들어왔으니 켜졌다 — 아래쪽 구역으로 돌아가면 민다.
            model.touchChanged(start: start, location: finger(table.midX, table.maxY - 10), context: c)
            model.edgeTick(deltaTime: 0.1)
            let pushed = model.viewport.origin.y
            #expect(pushed > 0, "\(size): 안쪽에 들어온 뒤인데 안 민다")

            // 판 아래(받침대)로 나갔다 올라오면 다시 꺼진다.
            model.touchChanged(start: start, location: finger(table.midX, c.layout.rack.midY), context: c)
            model.edgeTick(deltaTime: 0.1)
            model.touchChanged(start: start, location: finger(table.midX, table.maxY - 10), context: c)
            for _ in 0..<30 { model.edgeTick(deltaTime: 0.016) }
            #expect(model.viewport.origin.y == pushed, "\(size): 받침대에 다녀온 길목에서 밀렸다")
            model.touchChanged(start: start, location: finger(table.midX, table.midY), context: c)
            model.touchChanged(start: start, location: finger(table.midX, table.maxY - 10), context: c)
            model.edgeTick(deltaTime: 0.1)
            #expect(model.viewport.origin.y > pushed, "\(size): 다시 들어온 뒤인데 안 민다")
            model.cancelTouch()

            // 받침대 왼끝 타일을 곧장 위로 — 왼쪽 구역도 켜지지 않는다.
            let side = GamesRummyMatchModel(tableSize: table.size)
            side.tableSizeChanged(table.size)
            side.touchChanged(start: start, location: start, context: c, holdDelay: 3_600)
            side.touchChanged(start: start, location: finger(table.minX + 10, table.midY), context: c)
            for _ in 0..<30 { side.edgeTick(deltaTime: 0.016) }
            #expect(side.viewport.origin == .zero, "\(size): 왼끝으로 올라가는 길에 판이 밀렸다")
            side.cancelTouch()

            // 판에서 출발한 끌기는 곧바로 민다.
            let board = GamesRummyMatchModel(tableSize: table.size)
            board.tableSizeChanged(table.size)
            let tile = screen(CGPoint(x: 100 + 80 + 20, y: 78), c)
            board.touchChanged(start: tile, location: tile, context: c, holdDelay: 3_600)
            board.touchChanged(start: tile, location: finger(table.midX, table.maxY - 10), context: c)
            board.edgeTick(deltaTime: 0.1)
            #expect(board.viewport.origin.y > 0, "\(size): 판에서 출발한 끌기가 안 민다")
            board.cancelTouch()
        }
    }

    @Test("칸은 세로 크기로 불려도 음수가 안 된다(전환 중 한 프레임 · 안전 그림 조건)")
    func portraitFrameIsSafe() {
        #expect(!GamesRummyMatchLayout.isLandscape(CGSize(width: 393, height: 759)))
        #expect(!GamesRummyMatchLayout.isLandscape(CGSize(width: 400, height: 400)))
        #expect(GamesRummyMatchLayout.isLandscape(CGSize(width: 734, height: 372)))
        for size in [CGSize(width: 393, height: 759), CGSize(width: 100, height: 100), .zero] {
            let layout = GamesRummyMatchLayout(size: size)
            for cell in [layout.table, layout.rack, layout.status, layout.submit, layout.sort, layout.mySeatCard, layout.opponentCard(2)] {
                #expect(cell.width >= 0 && cell.height >= 0, "\(size): \(cell)")
            }
            _ = GamesRummyRackGeometry(size: layout.rack.size).frame(RummyRackSlot(row: 1, halfCol: 30))
            _ = GamesRummyViewport(viewport: layout.table.size).transform
        }
    }

    // MARK: - 끌기 궤적 — 다섯 크기

    private func context(_ editor: RummyTurnEditor, _ size: CGSize, viewport: GamesRummyViewport? = nil) -> GamesRummyTouchContext {
        let layout = GamesRummyMatchLayout(size: size, rackRows: editor.rackLayout.rowCount)
        let scene = GamesRummyBoardScene.make(match: nil, editor: editor, isMyTurn: true, otherDraft: nil)
        return GamesRummyTouchContext(layout: layout, viewport: viewport, scene: scene, editor: editor, isMyTurn: true, editable: true)
    }

    private func screen(_ logical: CGPoint, _ context: GamesRummyTouchContext) -> CGPoint {
        let local = context.viewport.transform.toScreen(logical)
        return CGPoint(x: local.x + context.layout.table.minX, y: local.y + context.layout.table.minY)
    }

    private func rackPoint(_ face: String, _ context: GamesRummyTouchContext) -> CGPoint {
        GamesRummyMatchInputTests.rackPoint(face, context)
    }

    private func trace(_ start: CGPoint, toPointer pointer: CGPoint, _ context: GamesRummyTouchContext, hold: Bool = false) -> GamesRummyDropAction {
        GamesRummyMatchInputTests.trace(start, to: context.layout.finger(forPointer: pointer), context, hold: hold)
    }

    @Test("궤적(다섯 크기): 받침대 → 묶음 · 받침대 → 빈 펠트 · 판 → 판 · 판 → 받침대 거절 · 내가 낸 타일 → 받침대 · 손잡이 묶음 이동 · 덩어리째")
    func trajectories() {
        for size in Self.screens {
            let base = editor()
            let c = context(base, size)
            let id: (String) -> Int = { GamesRummyMatchInputTests.id($0, in: base) }

            #expect(trace(rackPoint("A4", c), toPointer: screen(CGPoint(x: 100 + 120 - 6, y: 78), c), c)
                    == .moveTiles([id("A4")], .meld(0, index: 3)), "\(size) 받침대 → 묶음")
            #expect(trace(rackPoint("D9", c), toPointer: screen(CGPoint(x: 300, y: 300), c), c)
                    == .moveTiles([id("D9")], .newMeldAt(RummyPoint(x: 280, y: 272))), "\(size) 받침대 → 펠트")
            #expect(trace(screen(CGPoint(x: 100 + 80 + 20, y: 78), c), toPointer: screen(CGPoint(x: 810, y: 78), c), c)
                    == .moveTiles([id("A3")], .meld(1, index: 0)), "\(size) 판 → 판")

            let rackMid = CGPoint(x: c.layout.rack.midX, y: c.layout.rack.midY)
            #expect(trace(screen(CGPoint(x: 100 + 40 + 20, y: 78), c), toPointer: rackMid, c) == .refused, "\(size) 판 → 받침대")

            var played = base
            let moved = played.moveBlock([id("A4")], to: .meld(0, index: 3))
            #expect(moved)
            let p = context(played, size)
            guard case .moveTiles([id("A4")], .rackSlot) = trace(screen(CGPoint(x: 100 + 120 + 20, y: 78), p), toPointer: rackMid, p) else {
                Issue.record("\(size): 내가 낸 타일이 받침대로 안 돌아간다")
                continue
            }

            let edge = screen(CGPoint(x: 100, y: 78), c)
            let handle = CGPoint(x: edge.x - 10, y: edge.y)
            #expect(c.hit(handle) == .meldHandle(0), "\(size) 손잡이")
            guard case .moveSet(0, _) = trace(handle, toPointer: screen(CGPoint(x: 300, y: 300), c), c) else {
                Issue.record("\(size): 손잡이가 묶음을 안 옮긴다")
                continue
            }

            let chain = ["C1", "C2", "C3"].map(id)
            #expect(trace(rackPoint("C2", c), toPointer: screen(CGPoint(x: 300, y: 300), c), c, hold: true)
                    == .moveTiles(chain, .newMeldAt(RummyPoint(x: 240, y: 272))), "\(size) 덩어리째")
        }
    }

    @Test("궤적(다섯 크기): 세로로 밀린 판에서 놓기 · 받침대 위아래 줄 옮기기(아랫줄까지 화면 안의 손으로) · 좌표 왕복")
    func scrolledAndRack() {
        for size in Self.screens {
            let base = GamesRummyMatchInputTests.editor(farMeldX: 650, farMeldY: 560)
            var view = GamesRummyViewport(viewport: GamesRummyMatchLayout(size: size).table.size)
            let d9 = GamesRummyMatchInputTests.id("D9", in: base), a3 = GamesRummyMatchInputTests.id("A3", in: base)
            let plain = context(base, size, viewport: view)
            let want = CGPoint(x: 660, y: 588)
            #expect(screen(want, plain).y > plain.layout.table.maxY, "\(size) 기준선: 아래 묶음이 처음엔 칸 밖")
            view.pan(by: CGSize(width: 0, height: -100_000))
            let scrolled = context(base, size, viewport: view)
            #expect(screen(want, scrolled).y < scrolled.layout.table.maxY, "\(size): 밀어도 안 보인다")
            #expect(trace(rackPoint("D9", scrolled), toPointer: screen(want, scrolled), scrolled)
                    == .moveTiles([d9], .meld(1, index: 0)), "\(size) 밀린 판에 놓기")
            #expect(scrolled.hit(screen(CGPoint(x: 660, y: 588), scrolled)) != .felt, "\(size) 밀린 판 타일이 안 눌린다")
            _ = a3

            // 받침대 칸 왕복 — 위 · 아랫줄 어디로든, 손은 세이프 영역 안에 있다.
            for (row, half) in [(0, 20), (1, 0), (1, 30)] {
                let c = context(base, size)
                let frame = c.rack.frame(RummyRackSlot(row: row, halfCol: half))
                let pointer = CGPoint(x: c.layout.rack.minX + frame.midX, y: c.layout.rack.minY + frame.midY)
                let finger = c.layout.finger(forPointer: pointer)
                #expect(finger.y <= size.height, "\(size) \(row)줄: 손이 화면 밖")
                #expect(trace(rackPoint("D9", c), toPointer: pointer, c)
                        == .moveTiles([d9], .rackSlot(RummyRackSlot(row: row, halfCol: half))), "\(size) \(row)/\(half)")
            }
        }
    }

    // MARK: - 상태 줄 꼬리

    @Test("상태 줄 꼬리: 내 차례엔 차례 글자 없음 · 남의 차례 · 놓는 중 · 상태 글자와 같으면 비운다")
    func statusTail() async {
        let harness = RummyWireHarness(label: "rummy-orient-tail")
        guard let mine = harness.decodedState(turnSeat: 0), let other = harness.decodedState(turnSeat: 1) else {
            Issue.record("state 픽스처")
            await harness.tearDown()
            return
        }
        let quiet = GamesRummyStatusLine(text: "", tone: .quiet)
        #expect(GamesRummyStatusTail.make(match: mine, isMyTurn: true, hasOtherDraft: false, line: quiet).turn == nil)
        let name = GamesRummySeats.turnSeat(other)?.displayName ?? ""
        let waiting = GamesRummyStatusTail.make(match: other, isMyTurn: false, hasOtherDraft: false, line: quiet)
        #expect(waiting.turn == GamesRummyText.turnOf(name) && !waiting.isPlacing)
        let placing = GamesRummyStatusTail.make(match: other, isMyTurn: false, hasOtherDraft: true, line: quiet)
        #expect(placing.turn == GamesRummyText.placing(name) && placing.isPlacing)
        let same = GamesRummyStatusLine(text: GamesRummyText.turnOf(name), tone: .quiet)
        #expect(GamesRummyStatusTail.make(match: other, isMyTurn: false, hasOtherDraft: false, line: same).turn == nil, "같은 말을 두 번 한다")
        await harness.tearDown()
    }
}
