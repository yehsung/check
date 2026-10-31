#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 판(설계서 §4). 위에서 아래로 머리 줄 → 상대 줄 → 판 → 상태 줄 → 받침대 → 동작 줄이고, 칸 자리는 `GamesRummyMatchLayout` 한 곳에서 나온다.
/// 입력: `store` · `onExit`([나가기] — 기권 확인·놀던 기기는 화면 한 곳이 가른다) · `onReaction`(다음 갈래가 꽂는다 — nil 이면 [반응]이 없다).
/// 다른 기기 판: `store.rummy.isEngagedInCurrentMatch == false` 면 `GamesRummyText.elsewhereTitle` 안내 카드 + 읽기만(입력은 막지 않는다 — 맥과 같다).
/// 탭 막대는 공용 수단으로만 숨긴다(`.hidesTabBar(for: .rummyMatch)`). 머리 줄이 판 안에 있어 내비 막대도 숨기고, 숨기면 시스템 뒤로 쓸기도 함께 꺼진다.
///
/// ── 입력 ──
/// **화면 전체에 제스처 하나**(`inputLayer`)다. 그림 층(판 · 받침대)은 손을 안 받고, 그 위에 빈 층 하나, 다시 그 위에 버튼들(머리 줄 · 동작 줄 · 판 위 조작)이 있어 버튼은 제스처보다 먼저 눌린다.
/// 시작 자리를 `GamesRummyHitTester` 로 가르고 나머지는 `GamesRummyTouchMachine`(순수)이 정한다. 그려지는 자리와 재는 자리가 같은 값에서 나온다.
///
/// ── 성능 ──
/// 이 본문은 손이 움직여도 다시 돌지 않는다 — 본문은 `model.viewport`·`model.drag` 를 **읽지 않는다**. 밀기는 `GamesRummyTablePane`, 손가락은 `GamesRummyFloatingBlock` 잎 뷰만 다시 돈다.
/// `.task`+`.id` 를 쓰지 않는다(맥 0.3.69 재생성 고리 사고). 시간은 `TimelineView` 잎 뷰, 잠깐 떴다 사라지는 표시는 자기 토큰을 확인하는 단발 Task 다.
struct GamesRummyMatchView: View {
    let store: GamesStore
    let onExit: () -> Void
    var onReaction: (() -> Void)? = nil

    private static let space = "rummy.match"

    @State private var model = GamesRummyMatchModel()
    @GestureState private var touching = false
    @ScaledMetric(relativeTo: .subheadline) private var textScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 내 차례 표시: 테두리 빛 단계 · '내 차례' 배지 · 햅틱(차례 정체성으로 한 번만).
    @State private var turnCueKey: String?
    @State private var turnGlowPhase: GamesRummyTurnGlowPhase = .steady
    @State private var turnBadgeShown = false
    @State private var turnCueSerial = 0
    /// 방금 뽑은 타일(3초 빛남).
    @State private var freshDraw: (serial: Int, ids: Set<Int>)?
    @State private var demoPlayed = false

    private var rummy: RummyStore { store.rummy }

    var body: some View {
        GeometryReader { proxy in
            if let match = rummy.match {
                content(match: match, size: demoSize ?? proxy.size)
            }
        }
        .hidesTabBar(for: .rummyMatch)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .defersSystemGestures(on: .bottom)
        .sensoryFeedback(.impact(weight: .medium), trigger: turnCueSerial)
        .sensoryFeedback(.impact(weight: .light), trigger: model.liftSerial)
        .sensoryFeedback(.warning, trigger: model.refuseSerial)
        // 판이 바뀌면(내 차례 끝 · 남의 확정) 끄는 중이던 타일을 거둔다 — 낡은 id 로 놓지 않게.
        .onChange(of: rummy.match?.seq) { _, _ in model.cancelTouch() }
        .onChange(of: touching) { _, now in if !now { model.touchVanished() } }
        .onAppear { cueTurnIfNeeded() }
        .onChange(of: myTurnCueKey) { _, _ in cueTurnIfNeeded() }
        .onChange(of: rummy.lastDraw?.serial) { _, serial in noteDraw(serial) }
    }

    private var demoSize: CGSize? {
        #if DEBUG
        store.demoRummyRoute?.demoSize
        #else
        nil
        #endif
    }

    // MARK: 조립

    private func content(match: RummyMatchState, size: CGSize) -> some View {
        let editor = rummy.editor
        let isMyTurn = rummy.isMyTurn && editor != nil
        let scene = GamesRummyBoardScene.make(match: match, editor: editor, isMyTurn: isMyTurn, otherDraft: rummy.otherDraft)
        let rows = model.frozenRows ?? editor?.rackLayout.rowCount ?? RummyRackLayout.baseRows
        let layout = GamesRummyMatchLayout(size: size, rackRows: rows,
                                           actionHeight: GamesRummyMatchLayout.actionHeight(textScale: textScale))
        let context = GamesRummyTouchContext(layout: layout, scene: scene, editor: editor, isMyTurn: isMyTurn,
                                             editable: isMyTurn && !rummy.isWorking)
        let mine = GamesRummySeats.mine(match)
        let line = GamesRummyStatusLine.make(notice: rummy.notice, isMyTurn: isMyTurn, editor: editor,
                                             turnName: GamesRummySeats.turnSeat(match)?.displayName, mySeatState: mine?.state)
        return ZStack(alignment: .topLeading) {
            // 그림 층 — 손을 안 받는다.
            GamesRummyTablePane(model: model, scene: scene, size: layout.table.size, editable: context.editable)
                .place(layout.table)
            GamesRummyTableStrip(match: match, isMyTurn: isMyTurn, hasOtherDraft: rummy.otherDraft != nil)
                .frame(width: layout.table.width, height: layout.table.height, alignment: .bottom)
                .place(layout.table)
            if !rummy.isEngagedInCurrentMatch {
                // 묶음은 위부터 깔린다 — 안내가 타일을 가리지 않게 아래쪽(직전 사건 줄 위)에.
                GamesRummyElsewhereCard()
                    .padding(.bottom, 38)
                    .frame(width: layout.table.width, height: layout.table.height, alignment: .bottom)
                    .place(layout.table)
            }
            if turnBadgeShown, isMyTurn {
                GamesRummyTurnBadge()
                    .transition(.scale(scale: 0.85))
                    .position(x: layout.table.midX, y: layout.table.midY)
            }
            GamesRummyStatusRow(line: line, plan: editor?.initialPlanPoints.map { (table: isMyTurn ? $0.table : 0, rack: $0.rack) })
                .place(layout.status)
            GamesRummyRackPane(model: model, tiles: editor?.rack ?? [], layout: context.rackLayout, geometry: context.rack,
                               rackMelds: editor?.rackMelds ?? [], turnGlow: isMyTurn ? turnGlowPhase : nil,
                               freshIDs: freshDraw?.ids ?? [])
                .anchorPreference(key: GamesRummySeatAnchorKey.self, value: .bounds) { anchor in
                    match.mySeatNo.map { [$0: anchor] } ?? [:]
                }
                .place(layout.rack)
            // 입력 층 — 화면 전체.
            inputLayer(context: context)
                .frame(width: size.width, height: size.height)
            // 버튼 층 — 입력 층보다 위라 먼저 눌린다.
            GamesRummyMatchHeader(match: match, onExit: onExit, onReaction: onReaction, onRules: { rummy.rulesShown = true })
                .place(layout.header)
            GamesRummyOpponentRow(rummy: rummy, match: match)
                .place(layout.opponents)
            GamesRummyTableControls(model: model, scene: scene, size: layout.table.size,
                                    badgeLift: rummy.isEngagedInCurrentMatch ? 36 : 104)
                .place(layout.table)
            GamesRummyActionRow(rummy: rummy, match: match, editor: editor, isMyTurn: isMyTurn, width: size.width,
                                textScale: textScale, onSort: rummy.sortRack)
                .frame(width: layout.actions.width, height: layout.actions.height)
                .place(layout.actions)
            // 손에 든 타일 — 맨 위.
            GamesRummyFloatingBlock(model: model, context: context)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .onAppear {
            model.tableSizeChanged(layout.table.size)
            playDemoIfNeeded(context: context)
        }
        .onChange(of: layout.table.size) { _, new in model.tableSizeChanged(new) }
        .onChange(of: editor != nil) { _, _ in playDemoIfNeeded(context: context) }
    }

    private func inputLayer(context: GamesRummyTouchContext) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        model.touchChanged(start: value.startLocation, location: value.location, context: context)
                    }
                    .onEnded { value in
                        GamesRummyMatchModel.apply(model.touchEnded(at: value.location, context: context), to: rummy)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        model.pinchChanged(magnification: value.magnification, anchor: value.startLocation, context: context)
                    }
                    .onEnded { _ in model.pinchEnded(touching: touching) }
            )
            .accessibilityHidden(true)
    }

    // MARK: 내 차례 표시 — 화면 안에서만(소리·알림 없음)

    private var myTurnCueKey: String? {
        guard let match = rummy.match, rummy.isMyTurn, rummy.editor != nil, match.status == .active else { return nil }
        return RummyEditorKey(match).text
    }

    /// 내 차례가 새로 왔으면 받침대 테두리를 한 번 크게 빛내고(0.8초 뒤 은은하게) 판 가운데 '내 차례' 배지를 1.3초 띄운다 · 햅틱 한 번. 동작 줄이기면 펄스·배지 없이 은은한 테두리만.
    private func cueTurnIfNeeded() {
        guard let key = myTurnCueKey, key != turnCueKey else { return }
        turnCueKey = key
        turnCueSerial += 1
        guard !reduceMotion else {
            turnGlowPhase = .steady
            return
        }
        turnGlowPhase = .pulse
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { turnBadgeShown = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard turnCueKey == key else { return }
            turnGlowPhase = .steady
            try? await Task.sleep(for: .milliseconds(500))
            guard turnCueKey == key else { return }
            turnBadgeShown = false
        }
    }

    private func noteDraw(_ serial: Int?) {
        guard let serial, let event = rummy.lastDraw else { return }
        freshDraw = (serial, Set(event.tiles.map(\.tileID)))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if freshDraw?.serial == serial { freshDraw = nil }
        }
    }

    /// 데모 스크린샷 전용: 끌기 도중 모습을 세운다. Release 에서는 한 줄도 돌지 않는다.
    private func playDemoIfNeeded(context: GamesRummyTouchContext) {
        #if DEBUG
        guard !demoPlayed, let route = store.demoRummyRoute, context.editor != nil else { return }
        demoPlayed = true
        model.tableSizeChanged(context.layout.table.size)
        if route.demoFullView { model.toggleFullView() }
        if let touch = route.demoTouch { model.playDemo(touch, context: context) }
        #endif
    }
}

private extension View {
    /// 칸 사각형 그대로 놓는다(판 화면 좌표).
    func place(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}
#endif
