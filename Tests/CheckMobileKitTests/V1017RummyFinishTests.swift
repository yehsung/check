@testable import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 아잉 큐브 검토 지적을 고친 자리의 못(방향과 무관한 것). 합성 입력이 금지라 손 궤적을 실제 화면과 같은 재료로 밟고 결과 값을 잰다.
@MainActor
@Suite struct V1017RummyFinishTests {
    private typealias Input = GamesRummyMatchInputTests

    private static let matchID = UUID(uuidString: "d0000000-0000-4000-8000-0000000000aa")!
    private static let thisTurn = RummyEditorKey(matchID: matchID, turnSeatNo: 0, turnStartedMs: 1_000, seq: 3)
    private static let nextTurn = RummyEditorKey(matchID: matchID, turnSeatNo: 1, turnStartedMs: 2_000, seq: 4)

    private func context(_ editor: RummyTurnEditor? = Input.editor()) -> GamesRummyTouchContext {
        var context = Input.context(editor)
        context.turnKey = Self.thisTurn
        return context
    }

    /// 받침대 타일을 집어 끄는 중인 모델.
    private func dragging(_ context: GamesRummyTouchContext) -> (GamesRummyMatchModel, CGPoint) {
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let start = Input.rackPoint("C2", context)
        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 100), context: context)
        return (model, start)
    }

    // MARK: - 판이 바뀌었을 때의 손

    @Test("차례가 바뀌면 쥔 타일을 거두고 손을 뗄 때까지 무시한다 — 다음 사건이 처음 누른 자리를 새 판에서 다시 집지 않는다")
    func turnChangeAbandonsUntilLift() {
        let context = context()
        let (model, start) = dragging(context)
        #expect(model.drag != nil)
        model.boardChanged(editor: Input.editor(), turnKey: Self.nextTurn)
        #expect(model.drag == nil && model.draggingIDs.isEmpty && model.frozenRows == nil)
        #expect(model.machine.phase == .ignoring)
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 140), context: context)
        #expect(model.drag == nil, "손을 안 뗐는데 새 판에서 타일이 다시 집혔다")
        #expect(model.machine.phase == .ignoring)
        #expect(model.touchEnded(at: start, context: context) == .none, "거둔 손이 타일을 놓았다")
        #expect(model.machine.isIdle)
        // 다음 손은 새로 분류된다.
        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        #expect(!model.machine.isIdle && model.machine.holdsBoard)
        model.cancelTouch()
    }

    @Test("판 밀기는 판이 바뀌어도 그대로다 — 다음 이동은 그 걸음만큼만 민다(끈 거리 전체로 튀지 않는다)")
    func panSurvivesBoardChange() {
        let context = context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let start = Input.screen(CGPoint(x: 300, y: 300), context.with(viewport: model.viewport))
        model.touchChanged(start: start, location: start, context: context)
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 30), context: context)
        guard case .panning = model.machine.phase else {
            Issue.record("빈 펠트가 밀기로 안 잡혔다: \(model.machine.phase)")
            return
        }
        let before = model.viewport.origin.y
        #expect(before > 0, "기준선: 밀기가 움직이지 않으면 이 시험은 아무것도 안 잰다")
        model.boardChanged(editor: Input.editor(), turnKey: Self.nextTurn)
        guard case .panning = model.machine.phase else {
            Issue.record("판이 바뀌자 밀기가 거둬졌다: \(model.machine.phase)")
            return
        }
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 50), context: context)
        #expect(abs(model.viewport.origin.y - before - 20 / model.viewport.scale) < 0.001, "끈 거리 전체로 튀었다")
        model.touchEnded(at: start, context: context)
    }

    @Test("같은 차례에 seq 만 오르면(남의 기권) 쥔 타일을 안 거둔다 · 쥔 id 가 사라지면 거둔다")
    func sameTurnKeepsHoldUnlessTilesVanish() {
        let context = context()
        let (kept, _) = dragging(context)
        kept.boardChanged(editor: Input.editor(), turnKey: Self.thisTurn)
        #expect(kept.drag != nil, "같은 판인데 끌기가 거둬졌다")
        kept.cancelTouch()

        let (lost, _) = dragging(context)
        // 받침대가 준 편집기 — 쥔 C2 의 id 가 없다.
        let smaller = RummyTurnEditor(table: [Input.faces("A1", "A2", "A3")], rack: Input.faces("A4"), initialDone: true,
                                      tableLayout: [RummyPoint(x: 100, y: 50)])
        let held = Input.id("C2", in: Input.editor())
        #expect(!smaller.rack.contains { $0.id == held } && !smaller.melds.joined().contains { $0.id == held }, "기준선: 쥔 id 가 새 편집기에 남아 있다")
        lost.boardChanged(editor: smaller, turnKey: Self.thisTurn)
        #expect(lost.drag == nil && lost.machine.phase == .ignoring)
        lost.cancelTouch()

        // 편집기가 사라졌다.
        let (gone, _) = dragging(context)
        gone.boardChanged(editor: nil, turnKey: Self.thisTurn)
        #expect(gone.machine.phase == .ignoring)
        gone.cancelTouch()
    }

    @Test("쥔 것의 생존: 꾹 눌러 집은 덩어리 · 손잡이 묶음 번호는 그 번호의 내용으로 견준다")
    func holdSurvivalValues() {
        let editor = Input.editor()
        let context = context(editor)
        // 묶음 순서가 바뀐 편집기 — 번호는 있어도 내용이 다르다.
        let swapped = RummyTurnEditor(table: [Input.faces("B4", "B5", "B6", "B7"), Input.faces("A1", "A2", "A3")],
                                      rack: Input.faces("A4", "C1", "C2", "C3", "D9"), initialDone: true,
                                      tableLayout: [RummyPoint(x: 800, y: 50), RummyPoint(x: 100, y: 50)])
        var pressed = GamesRummyTouchMachine()
        pressed.down(Input.rackPoint("C2", context), context)
        let lifted = pressed.holdElapsed(context)
        #expect(lifted != nil)
        #expect(pressed.holdSurvives(in: editor, was: editor))
        #expect(!pressed.holdSurvives(in: nil, was: editor))

        let frame = context.scene.layout.frame(of: 0)!
        let edge = Input.screen(CGPoint(x: CGFloat(frame.x), y: CGFloat(frame.y) + 30), context)
        var handle = GamesRummyTouchMachine()
        handle.down(CGPoint(x: edge.x - 10, y: edge.y), context)
        guard case .handle = handle.phase else {
            Issue.record("손잡이가 안 잡혔다: \(handle.phase)")
            return
        }
        #expect(handle.holdSurvives(in: editor, was: editor))
        #expect(!handle.holdSurvives(in: swapped, was: editor), "번호만 같은 다른 묶음을 옮기게 된다")
        _ = handle.move(Input.finger(under: Input.screen(CGPoint(x: 300, y: 300), context)), context)
        #expect(handle.drag != nil)
        #expect(handle.holdSurvives(in: editor, was: editor))
        #expect(!handle.holdSurvives(in: swapped, was: editor), "번호만 같은 다른 묶음을 옮기게 된다")
    }

    // MARK: - 핀치 · 동작 버튼

    @Test("핀치 취소: onEnded 없이 손이 사라져도 배율을 맞추고 다음 핀치는 지금 배율에서 시작한다 · 읽기 전용 밀기가 산다")
    func cancelledPinchIsCleanedUp() async {
        let model = GamesRummyMatchModel()
        let base = model.viewport.scale
        model.pinch(magnification: 1.2, tableAnchor: .zero)
        let zoomed = model.viewport.scale
        #expect(zoomed > base && model.renderScale == base, "기준선: 핀치 중엔 그린 배율이 그대로다")
        let origin = model.viewport.origin
        model.readOnlyPan(by: CGSize(width: -40, height: 0))
        #expect(model.viewport.origin == origin, "핀치 중에 밀렸다")

        model.touchVanished()
        #expect(await baseWaitUntil { model.renderScale == zoomed }, "취소된 핀치가 흐린 채 남았다")
        model.pinch(magnification: 1, tableAnchor: .zero)
        #expect(model.viewport.scale == zoomed, "다음 핀치가 낡은 기준에서 튀었다")
        model.pinchEnded(touching: false)
        model.readOnlyPan(by: CGSize(width: -40, height: 0))
        #expect(model.viewport.origin != origin, "읽기 전용 밀기가 죽었다")

        model.pinch(magnification: 1.1, tableAnchor: .zero)
        model.cancelTouch()
        #expect(model.renderScale == model.viewport.scale)
    }

    @Test("동작 버튼: 타일을 누르거나 끄는 동안만 잠긴다 · 판 밀기 · 쉬는 동안은 안 잠긴다")
    func actionsLockWhileHolding() {
        let context = context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        #expect(!model.locksActions)
        let start = Input.rackPoint("C2", context)
        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        #expect(model.locksActions, "누른 동안 [되돌리기]가 눌린다")
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 100), context: context)
        #expect(model.locksActions, "끄는 동안 [되돌리기]가 눌린다")
        model.touchEnded(at: start, context: context)
        #expect(!model.locksActions)
        let felt = Input.screen(CGPoint(x: 300, y: 300), context.with(viewport: model.viewport))
        model.touchChanged(start: felt, location: felt, context: context)
        #expect(!model.locksActions, "판을 미는데 동작 버튼이 죽었다")
        model.touchEnded(at: felt, context: context)
    }

    // MARK: - 상태 줄

    @Test("상태 줄: 내 시간 초과 N/3 은 어떤 글자가 떠 있어도 보인다 · 남의 차례엔 손댄 기기에만 90초 안내")
    func statusLineWarnings() {
        let editor = Input.editor()
        let waiting = GamesRummyStatusLine.make(notice: nil, isMyTurn: false, editor: nil, turnName: "구름", mySeatState: .playing,
                                                myTimeoutStreak: 2, engaged: true)
        #expect(waiting.text == "앱을 90초 넘게 내리면 기권돼요")
        #expect(waiting.warning == "시간 초과 2/3")
        let idle = GamesRummyStatusLine.make(notice: nil, isMyTurn: false, editor: nil, turnName: "구름", mySeatState: .playing,
                                             myTimeoutStreak: 0, engaged: false)
        #expect(idle.text == GamesRummyText.turnOf("구름"), "놀던 기기에 기권 안내가 떴다")
        #expect(idle.warning == nil)
        let mine = GamesRummyStatusLine.make(notice: nil, isMyTurn: true, editor: editor, turnName: nil, mySeatState: .playing,
                                             myTimeoutStreak: 1, engaged: true)
        #expect(mine.text == GamesRummyText.myTurnStatus(editor))
        #expect(mine.warning == "시간 초과 1/3", "내 차례에 경고가 안 보인다")
        let notice = GamesRummyStatusLine.make(notice: "서버 말", isMyTurn: true, editor: editor, turnName: nil, mySeatState: .playing,
                                               myTimeoutStreak: 2, engaged: true)
        #expect(notice.text == "서버 말" && notice.warning == "시간 초과 2/3", "안내줄에 경고가 밀렸다")
        let out = GamesRummyStatusLine.make(notice: nil, isMyTurn: false, editor: nil, turnName: "구름", mySeatState: .forfeit,
                                            myTimeoutStreak: 3, engaged: true)
        #expect(out.text == GamesRummyText.spectating && out.warning == nil, "기권한 자리에 경고가 남았다")
    }

    // MARK: - 기하 · 모션(방향 무관)

    @Test("위아래 가림: 위·아래 묶음을 세고(좌우 배지와 겹쳐 안 센다) 배지를 누르면 보인다 · 가장자리 자동 밀기도 세로로 민다")
    func verticalOffscreen() {
        var view = GamesRummyViewport(viewport: CGSize(width: 548, height: 200))
        view.zoom(to: 1, anchor: .zero)
        let below = RummyRect(x: 100, y: 500, width: 120, height: 56)
        let farRight = RummyRect(x: 1_000, y: 500, width: 120, height: 56)
        #expect(view.offscreenVerticalCounts([below, farRight]).down == 1, "좌우 배지가 세는 묶음을 또 셌다")
        #expect(view.offscreenVerticalCounts([below]).up == 0)
        view.reveal(.down, frames: [below])
        #expect(view.offscreenVerticalCounts([below]).down == 0, "배지를 눌러도 안 보인다")
        #expect(view.origin.y > 0)
        #expect(view.offscreenVerticalCounts([RummyRect(x: 100, y: 0, width: 120, height: 56)]).up == 1)
        view.reveal(.up, frames: [RummyRect(x: 100, y: 0, width: 120, height: 56)])
        #expect(view.origin.y == 0)

        let top = view.origin.y
        var moved = view.edgePan(pointer: CGPoint(x: 200, y: 190), deltaTime: 0.1)
        #expect(moved, "아래 가장자리에서 안 밀렸다")
        #expect(view.origin.y > top)
        let lowered = view.origin.y
        moved = view.edgePan(pointer: CGPoint(x: 200, y: 5), deltaTime: 0.05)
        #expect(moved)
        #expect(view.origin.y < lowered)
        moved = view.edgePan(pointer: CGPoint(x: 200, y: 100), deltaTime: 0.1)
        #expect(!moved, "가운데에서 밀렸다")
    }

    private func tile(_ text: String, id: Int) -> RummyBoardTile {
        RummyBoardTile(id: id, face: RummyFace(text: text)!, highlighted: false)
    }

    private func meld(_ id: String, x: Int, y: Int, _ tiles: [RummyBoardTile]) -> RummyBoardMeld {
        RummyBoardMeld(id: id, tiles: tiles, frame: RummyRect(x: x, y: y, width: tiles.count * RummyTableLayout.tileWidth, height: RummyTableLayout.tileHeight), invalid: false)
    }

    @Test("놓은 타일: 손 놓은 자리가 들어갈 자리와 다르면 거기서 미끄러진다 · 같거나 값이 없으면 바로 선다")
    func droppedTileLands() throws {
        let old = [meld("a", x: 40, y: 16, [tile("A1", id: 1), tile("A3", id: 3)])]
        let new = [meld("a", x: 40, y: 16, [tile("A1", id: 1), tile("A2", id: 9), tile("A3", id: 3)])]
        let width = CGFloat(RummyTableLayout.tileWidth)
        let home = CGPoint(x: 40 + width, y: 16)
        let from = CGPoint(x: 300, y: 200)
        let motion = try #require(GamesRummyBoardMotion.make(from: old, to: new, excluding: [9], landing: [9: from]))
        let landed = try #require(motion.moves.first { $0.face.text == "A2" }, "놓은 타일이 순간 이동했다")
        #expect(landed.from == from && landed.to == home)
        let silent = GamesRummyBoardMotion.make(from: old, to: new, excluding: [9], landing: [9: home])
        #expect(silent?.moves.contains { $0.face.text == "A2" } != true, "제자리에 놓았는데 날았다")
        let none = GamesRummyBoardMotion.make(from: old, to: new, excluding: [9])
        #expect(none?.moves.contains { $0.face.text == "A2" } != true)
    }

    // MARK: - 문구

    @Test("문구: 기권 확인 · 규칙 기권 줄 · 빈 상태 · 낱말 한 쌍 · 점수 부호 · 순위는 'N위' · 내가 이기면 이름을 안 부른다")
    func copy() throws {
        #expect(GamesRummyText.forfeitDetail == "나가면 기권돼 꼴찌가 되고 판돈을 잃어요.")
        let forfeit = try #require(GamesRummyText.rules.first { $0.title == "기권" })
        #expect(forfeit.detail.contains("뒤로 단추로 판을 나가거나"), "판 화면에 없는 단추를 말한다: \(forfeit.detail)")
        #expect(!forfeit.detail.contains("[나가기]"))
        #expect(GamesRummyText.joinEmpty == "받은 초대나 열린 공개 탁자가 생기면 이 화면 맨 위에 떠요")
        #expect(GamesRummyText.seated == GamesRummyText.joined && GamesRummyText.waitingAnswer == GamesRummyText.invited,
                "같은 상태를 의자 카드와 사람 행이 다른 낱말로 부른다")
        #expect(GamesRummyText.score(-36) == "점수 −36" && GamesRummyText.score(44) == "점수 +44" && GamesRummyText.score(0) == "점수 0")
        #expect(GamesRummyText.myRankLine(rank: 2, games: 12, wins: 5).hasPrefix("2위 · "))
        #expect(GamesRummyText.endReason(.rackEmpty, winner: "나나", winnerIsMe: true) == "랙을 비웠어요")
        #expect(GamesRummyText.endReason(.rackEmpty, winner: "구름") == "구름님이 랙을 비웠어요")
        #expect(GamesRummyText.endReason(.lastStanding, winner: "나나", winnerIsMe: true) == "혼자 남아 끝났어요")
    }

    // MARK: - 뷰 배선(폰 뷰는 맥 스위트가 못 본다 — 소스 계약)

    @Test("배선: 방의 시스템 뒤로를 숨기고 [나가기] 판단을 탄다 · 판 동작 버튼 잠금 · 판 변화 · 규칙 시트 머리 · 머리 단추 · 계정 삭제 앞 이탈 없음")
    func viewWiring() throws {
        let room = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyRoom.swift")
        #expect(room.contains(".navigationBarBackButtonHidden(true)"), "뒤로로 나오면 자리가 남아 판돈을 잃는다")
        #expect(room.contains("Button(action: onExit)"), "뒤로 자리가 [나가기] 판단을 안 탄다")
        #expect(room.contains("GamesRummyPeopleSection"))

        let rows = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyLobbyRows.swift")
        #expect(rows.contains("room == nil ? GamesRummyText.readyHeader : GamesRummyText.peopleHeader"), "방 안 머리가 '초대 가능' 이다")

        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyMatch.swift")
        #expect(match.contains(".allowsHitTesting(!model.locksActions)"), "끄는 동안 동작 버튼이 눌린다")
        #expect(match.contains("model.boardChanged(editor: rummy.editor, turnKey:"))
        #expect(match.contains("turnKey: RummyEditorKey(match)"), "손이 차례를 모른다 — 차례가 바뀌어도 안 거둔다")
        #expect(match.contains("myTimeoutStreak: mine?.timeoutStreak"), "내 시간 초과가 상태 줄로 안 간다")
        #expect(match.contains("engaged: rummy.isEngagedInCurrentMatch"))
        #expect(match.contains("guard rummy.isEngagedInCurrentMatch else {"), "놀던 기기가 차례마다 울린다")

        let chrome = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyMatchChrome.swift")
        #expect(chrome.contains(#"GamesRummyColumnButton(systemImage: "book""#) && !chrome.contains("questionmark.circle"), "규칙 기호가 다른 화면과 다르다")
        #expect(chrome.contains(#"GamesRummyColumnButton(systemImage: "chevron.left""#))
        #expect(chrome.contains("line.warning"), "상태 줄이 경고를 안 그린다")

        let rules = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyRules.swift")
        #expect(rules.contains("SheetHeader(GamesRummyText.rulesTitle") && !rules.contains("NavigationStack"))

        let result = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyResult.swift")
        #expect(result.contains("@GestureState private var lastPan"), "취소된 밀기가 낡은 값을 남긴다")
        #expect(result.contains(".onChange(of: pinching)"), "취소된 핀치가 안 닫힌다")

        let session = try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSessionStore.swift")
        let app = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileAppModel.swift")
        #expect(!session.contains("beforeAccountDeletion") && !app.contains("beforeAccountDeletion"))
    }
}
