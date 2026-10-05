import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 1:1 체스 **창**과 레이아웃 산식 · 전역 스페이스 모니터 양보 · 앱 배선.
//
// 창은 오목 창(v0.3.27)의 수명 규약을 그대로 쓴다. 여기서 못 박는 것은 **체스에서만 틀릴 수 있는 것**들이다:
//   · 자동저장 이름이 저장소 안 모든 창과 겹치지 않는다(겹치면 자리 저장이 **조용히** 죽는다).
//   · 판 608 이 8 로 나누어떨어진다(칸 76pt 정확) · 세 열·오른쪽 열 항등식.
//   · ★ **미니게임 창의 전역 스페이스 모니터가 체스 창의 키를 양보한다.** 등록이 빠지면 미니게임 창을
//     띄워 둔 채 체스 창에서 누른 스페이스가 삼켜진다(2026-09-17 오목 채팅 사고와 같은 자리).
//   · 닫기와 최소화가 **다른 문**이다 — 최소화는 관전을 남기고 닫기는 내린다.
//   · CheckApp 배선 다섯 줄(창 · 주 스위치 · 띄우기 · 닫기 · 주의 끌기)이 실제로 물려 있다(소스 계약).
//
// 창을 실제로 띄우는 검증은 `CheckPanelVisibility` 알파 0 을 지나고 직렬이다(AppKit 창을 동시에 만들면 SIGSEGV 실측).
// `isVisible` 은 믿지 않는다 — 판정은 '의도'(`isOpen`)와 우리가 만든 창 객체다.

// MARK: - 헬퍼

/// 창 계층만 재는 컨트롤러(콘텐츠는 빈 뷰 — 화면 내용 변화에 창 검증이 끌려다니지 않게). 공유 인스턴스가 아니다.
@MainActor
private func cwController(_ store: ChessStore) -> CheckChessWindowController {
    let controller = CheckChessWindowController()
    controller.configure(store: store, content: { _ in AnyView(Color.clear) })
    return controller
}

private let cwOpponent = ChessUser(
    id: "00000000-0000-0000-0000-00000000000a", displayName: "민수", avatarURL: nil,
    characterID: "fox", isWorking: true, isCapable: true, inMatch: true
)

@MainActor
private func cwActiveMatch() -> ChessMatchState {
    let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    return ChessMatchState(
        id: "match-1", stake: 5, myColor: .white, opponent: cwOpponent, fen: fen,
        position: ChessPosition(fen: fen), plyCount: 0, turn: .white, lastMove: nil, moves: [],
        clock: .initial, isInCheck: false, legalMoves: ChessRules.legalMoves(in: ChessPosition.standard),
        isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, drawOfferBy: nil,
        drawOfferedByMe: false)
}

/// 화면에 올리되 보이지 않게(알파 0) — `yieldsToOtherWindow` 가 `isVisible` 을 요구한다.
/// (V0330MiniGameSpaceYieldTests 의 `syWindow` 와 같은 수법 — 그쪽은 private 이라 복사했다.)
@MainActor
private func cwWindow(identifier: String? = nil) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    if let identifier { window.identifier = NSUserInterfaceItemIdentifier(identifier) }
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    window.orderFrontRegardless()
    return window
}

// MARK: - 레이아웃 산식(순수)

@Test("판 608 은 8 로 나누어떨어진다 — 칸 76pt 정확(체스에서 이 값을 고른 이유)")
func theBoardSideDividesIntoEightWholeSquares() {
    #expect(ChessWindowLayout.contentSize == CGSize(width: 1240, height: 700))
    #expect(ChessWindowLayout.innerSize == CGSize(width: 1200, height: 660))
    #expect(ChessWindowLayout.bodyHeight == 608)
    #expect(ChessWindowLayout.boardSide == 608)
    // ★ 나머지 0 — 64칸이 전부 같은 크기이고 격자에 반 픽셀 이음선이 없다.
    #expect(ChessWindowLayout.cellSide == 76)
    #expect(ChessWindowLayout.cellSide * 8 == ChessWindowLayout.boardSide)
    #expect(ChessWindowLayout.cellSide == ChessWindowLayout.cellSide.rounded(),
            "칸이 \(ChessWindowLayout.cellSide)pt 라 정수가 아니다 — 격자에 이음선이 생긴다")
    // 기준선: 오목의 608 은 **나누어떨어지지 않는다**(14 간격). 체스가 같은 608 을 쓰면서 다른 근거를 가진 이유다.
    #expect((GomokuWindowLayout.boardSide - GomokuWindowLayout.boardSide * 0.06 * 2) / 14 != 76,
            "오목 칸이 76 이면 이 비교가 아무것도 말하지 않는다")
}

@Test("창 폭·세로 예산 항등식 — 숫자를 두 곳에 적지 않는다")
func theColumnBudgetsAddUpExactly() {
    let L = ChessWindowLayout.self
    // 대국·결과·관전: [판 | 오른쪽 열]
    #expect(L.boardSide + L.columnSpacing + L.sideColumnWidth == L.innerSize.width)
    #expect(L.sideColumnWidth == 572)
    // 로비: [상대 | 순위 | 오른쪽]
    #expect(L.lobbyUsersWidth + L.columnSpacing + L.lobbyRankWidth == L.lobbyListWidth)
    #expect(L.lobbyListWidth + L.columnSpacing + L.lobbySideWidth == L.innerSize.width)
    #expect(L.lobbyRankWidth == 340 && L.lobbyListWidth == 780)
    // 대국 오른쪽 열 세로: 카드 둘 · 판돈 줄 · 기보 · 동작 줄 · 간격 넷
    #expect(L.playerCardHeight * 2 + L.stakeStatusMinHeight + L.moveListHeight + L.actionRowHeight
            + L.matchSideSpacing * 4 == L.bodyHeight)
    #expect(L.moveListHeight == 322)
    // 기보 줄수: 11 줄이 262 에 **정확히** 든다(12번째부터 스크롤).
    #expect(L.moveListInnerHeight == 262)
    #expect(L.moveVisibleRows == 11)
    let used = CGFloat(L.moveVisibleRows) * L.moveRowHeight + CGFloat(L.moveVisibleRows - 1) * L.moveRowSpacing
    #expect(used <= L.moveListInnerHeight, "기보 \(L.moveVisibleRows)줄이 \(used)pt 라 \(L.moveListInnerHeight)pt 를 넘는다")
    let oneMore = used + L.moveRowSpacing + L.moveRowHeight
    #expect(oneMore > L.moveListInnerHeight, "한 줄 더 넣어도 들어간다 — moveVisibleRows 가 모자라게 세고 있다")
    // 로비 오른쪽 열 세로: 내 전적 · 지금 대결 중 · 받은/보낸 신청 · 간격 둘
    #expect(L.lobbyRecordHeight + L.lobbyLiveHeight + L.lobbyInvitesMaxHeight
            + L.lobbySideSpacing * 2 == L.bodyHeight)
    // 받은/보낸 신청 칸의 예산은 **조각의 합**이다(옛 값 200 은 카드 여백 32 와 제목 20 을 안 세서 모자랐다 —
    // 실제 높이 209pt 를 `V0345ChessRenderGapTests` 가 렌더로 잰다).
    #expect(L.lobbyInvitesMaxHeight == L.cardPadding * 2 + L.lobbyInvitesTitleHeight + L.lobbyInviteCardHeight
            + L.lobbyOutgoingLineHeight + L.lobbyNoticeLineHeight + L.lobbyInvitesSpacing * 3)
    #expect(L.lobbyInvitesMaxHeight == 232)
    #expect(L.lobbyLiveHeight == 280)
    // "지금 대결 중" 카드 다섯 장은 그래도 언제나 보인다(행 36 · 간격 6 → 204 ≤ 남는 높이).
    let liveInner = L.lobbyLiveHeight - L.cardPadding * 2 - L.rankHeaderHeight - L.rankHeaderSpacing
    #expect(36 * 5 + 6 * 4 <= Int(liveInner), "지금 대결 중 카드 다섯 장이 안 들어간다(남는 높이 \(liveInner)pt)")
    // 순위 열: 14행이 548 에 든다
    #expect(L.rankListHeight == 548 && L.rankVisibleRows == 14)
    // 승격 창: 말 넷이 판 칸 크기로 한 줄에 선다
    #expect(L.promotionTileSide == L.cellSide)
    #expect(L.promotionTileSide * 4 + 12 * 3 + 20 * 2 == L.promotionPromptWidth)
}

@Test("판 좌표계: 64칸 왕복 · 방향 뒤집기 · 판 밖은 nil")
func theBoardGeometryRoundTripsEverySquareInBothOrientations() throws {
    for orientation in ChessColor.allCases {
        let g = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: orientation)
        // CGRect 는 macOS 14 에서 Hashable 이 아니다(15 부터) — 자리를 글자로 바꿔 센다.
        var seen = Set<String>()
        for index in 0..<64 {
            let square = try #require(ChessSquare(index: index))
            let box = g.rect(of: square)
            // **상수와 묶는다** — 76 을 글자로 적으면 cellSide 를 바꿔도 이 시험이 아무 말을 안 한다.
            #expect(box.width == ChessWindowLayout.cellSide && box.height == ChessWindowLayout.cellSide)
            #expect(box.width == 76 && box.height == 76)
            #expect(seen.insert("\(box.minX),\(box.minY)").inserted,
                    "\(orientation) 에서 \(square.notation) 이 다른 칸과 같은 자리다")
            // 칸 중앙 · 네 모서리 안쪽이 모두 그 칸으로 되돌아온다.
            for probe in [CGPoint(x: box.midX, y: box.midY),
                          CGPoint(x: box.minX + 1, y: box.minY + 1),
                          CGPoint(x: box.maxX - 1, y: box.maxY - 1)] {
                #expect(g.square(at: probe) == square,
                        "\(orientation) \(square.notation): \(probe) 가 \(g.square(at: probe)?.notation ?? "nil") 로 떨어진다")
            }
        }
        #expect(seen.count == 64)
        // 판 밖은 아무 칸도 아니다(**반 칸 관용이 없다** — 오목과 다른 점).
        #expect(g.square(at: CGPoint(x: -1, y: 10)) == nil)
        #expect(g.square(at: CGPoint(x: 10, y: -1)) == nil)
        #expect(g.square(at: CGPoint(x: g.side, y: 10)) == nil)
        #expect(g.square(at: CGPoint(x: 10, y: g.side)) == nil)
    }

    // ★ 기준선이 갈린다: 내 색이 아래로 온다(흑으로 두면 판이 뒤집힌다).
    let white = ChessBoardGeometry(side: 608, orientation: .white)
    let black = ChessBoardGeometry(side: 608, orientation: .black)
    let a1 = try #require(ChessSquare("a1"))
    let h8 = try #require(ChessSquare("h8"))
    #expect(white.rect(of: a1) == CGRect(x: 0, y: 532, width: 76, height: 76), "백 기준 a1 이 왼쪽 **아래**가 아니다")
    #expect(black.rect(of: a1) == CGRect(x: 532, y: 0, width: 76, height: 76), "흑 기준 a1 이 오른쪽 **위**가 아니다")
    #expect(white.rect(of: a1) == black.rect(of: h8), "방향을 뒤집었는데 a1 과 h8 이 자리를 안 바꿨다")
    #expect(white.rect(of: a1) != black.rect(of: a1), "orientation 이 그림을 안 바꾼다 — 흑으로 두면 판이 거꾸로 보인다")
}

@Test("기보 짝 짓기는 색으로 한다 — 홀짝으로 자르면 흑이 먼저 둔 판에서 한 칸씩 밀린다")
func theMoveLogPairsByColorNotByIndex() throws {
    func record(_ seq: Int, _ color: ChessColor, _ san: String) -> ChessMoveRecord {
        ChessMoveRecord(seq: seq, color: color, move: ChessMove(from: ChessSquare("e2")!, to: ChessSquare("e4")!),
                        san: san, fen: "x", msLeft: 1000, msSpent: 1)
    }
    // 백부터: 1. e4 e5 / 2. Nf3
    let normal = ChessMoveLog.rows([record(1, .white, "e4"), record(2, .black, "e5"), record(3, .white, "Nf3")])
    #expect(normal.map(\.number) == [1, 2])
    #expect(normal[0].white?.san == "e4" && normal[0].black?.san == "e5")
    #expect(normal[1].white?.san == "Nf3" && normal[1].black == nil)

    // ★ 기준선이 갈린다 — **흑이 먼저** 둔 기록. 홀짝으로 잘랐다면 첫 줄의 백 칸에 흑 수가 들어간다.
    let blackFirst = ChessMoveLog.rows([record(1, .black, "e5"), record(2, .white, "Nf3"), record(3, .black, "Nc6")])
    #expect(blackFirst[0].white == nil, "흑이 먼저 둔 판에서 흑 수가 백 칸에 들어갔다")
    #expect(blackFirst[0].black?.san == "e5")
    #expect(blackFirst[1].white?.san == "Nf3" && blackFirst[1].black?.san == "Nc6")
    #expect(ChessMoveLog.rows([]).isEmpty)
}

// MARK: - 창 수명

@MainActor
@Suite(.serialized)
struct ChessWindowLifecycleTests {
    @Test
    func chessWindowIdentityMatchesTheContract() {
        #expect(CheckChessWindowController.windowTitle == "1:1 체스")
        #expect(CheckChessWindowController.frameAutosaveName == "check.chess.window")
        #expect(CheckChessWindowController.frameAutosaveName != CheckGomokuWindowController.frameAutosaveName)
        #expect(CheckChessWindowController.frameAutosaveName != CheckMiniGameWindowController.frameAutosaveName)
        #expect(CheckChessWindowController.frameAutosaveName != CheckSettingsWindowController.frameAutosaveName)
        #expect(CheckChessWindowController.fixedContentSize == NSSize(width: 1240, height: 700))

        let window = CheckChessWindowController.makeWindow()
        defer { window.close() }
        #expect(window.title == "1:1 체스")
        #expect(window.styleMask.contains(.titled) && window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.resizable), "크기가 바뀌면 판 좌표계가 창에 딸려 흔들린다")
        #expect(!window.isReleasedWhenClosed, "닫힘에 해제가 딸리면 다음 show() 가 해제된 창을 만진다")
        #expect(!window.hidesOnDeactivate, "다른 앱을 누르면 창이 사라진다 — 대국은 계속되는데 판이 안 보인다")
        #expect(window.appearance?.name == .darkAqua)
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        // ★ 식별자가 **자동저장 이름과 같아야** 전역 스페이스 모니터가 이 창을 알아본다(아래 양보 시험의 전제).
        #expect(window.identifier?.rawValue == CheckChessWindowController.frameAutosaveName)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
    }

    @Test
    func theWindowIsLazyIdempotentAndSurvivesClose() throws {
        let store = ChessStore()
        store.pollStepSeconds = 3_600
        let controller = cwController(store)
        defer { controller.discardWindowForTesting(); store.stopPolling() }

        #expect(!controller.hasWindow, "배선만으로 창이 만들어졌다")
        #expect(controller.lastVisibilityNotice == nil)

        controller.show()
        #expect(controller.hasWindow && controller.isOpen)
        #expect(controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹쳐 자리 저장이 죽었다")
        #expect(controller.lastVisibilityNotice == true, "창을 열었는데 스토어에 '보임'을 안 알렸다 — 로비 재조회가 안 돈다")
        #expect(store.isWindowVisible, "스토어가 '보임'을 안 받았다")
        let first = try #require(controller.currentWindow)
        let before = NSApp.map { $0.windows.count }
        controller.show()
        controller.show()
        #expect(NSApp.map { $0.windows.count } == before, "show() 를 더 불렀더니 창이 늘었다(멱등 위반)")
        #expect(controller.currentWindow === first)

        controller.close()
        #expect(!controller.isOpen)
        #expect(controller.hasWindow, "닫기가 창을 파괴했다 — 옮겨 둔 자리가 매번 초기화된다")
        #expect(controller.lastVisibilityNotice == false, "닫았는데 '안 보임'을 안 알렸다 — 안 보이는 창의 폴링이 계속 돈다")
        #expect(!store.isWindowVisible)
        controller.show()
        #expect(controller.isOpen && controller.lastVisibilityNotice == true, "다시 열었는데 재조회의 문('보임')이 안 열렸다")
    }

    @Test
    func withoutWiringShowDoesNothing() {
        let controller = CheckChessWindowController()
        controller.show()
        #expect(!controller.hasWindow)
        #expect(!controller.isOpen)
    }

    @Test
    func losingKeyOrClosingTheWindowDoesNotEndTheMatch() throws {
        // 가장 강한 형태로 못 박는다: 키 상실 처리기 자체가 **없다**.
        #expect(!CheckChessWindowController().responds(to: #selector(NSWindowDelegate.windowDidResignKey(_:))),
                "체스 창이 키 상실에 반응한다 — 다른 앱을 잠깐 보는 것이 대국 중단이 되면 안 된다")

        let store = ChessStore()
        store.pollStepSeconds = 3_600
        let match = cwActiveMatch()
        store.phase = .playing
        store.match = match
        let controller = cwController(store)
        defer { controller.discardWindowForTesting(); store.stopPolling() }
        controller.show()
        let window = try #require(controller.currentWindow)

        // AppKit 이 던지는 그 알림을 그대로 던진다(메서드 직접 호출은 배선이 빠져도 초록이다).
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: window)
        #expect(store.match == match, "키를 잃었더니 대국이 바뀌었다")
        #expect(store.phase == .playing)
        #expect(controller.isOpen, "키를 잃은 것은 닫힌 것이 아니다")
        #expect(controller.lastVisibilityNotice == true, "키를 잃었다고 '안 보임'을 알렸다 — 판을 보고 있는 사람의 동기화가 멎는다")

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(!controller.isOpen)
        #expect(controller.lastVisibilityNotice == false)
        #expect(store.match == match, "창을 닫았더니 대국이 바뀌었다 — 닫기는 기권이 아니다")
        #expect(store.phase == .playing)
    }

    /// ★ **최소화는 관전을 남기고, 닫기는 내린다.** 두 통지를 합치면(또는 닫기 쪽에서 빼면) 한쪽이 무너진다.
    ///
    /// 없으면: `notifyClosed()` 를 `notifyVisibility` 안으로 접어 넣어도 초록이다 — 그러면 남의 판을 보다
    /// 최소화했다 되살리면 로비로 떨어진다. 반대로 `windowWillClose` 에서 빼면 창을 닫고 다시 열었을 때
    /// 로비가 아니라 남의 진행 중인 판이 선다.
    @Test
    func minimizingKeepsTheWatchButClosingEndsIt() throws {
        func watching(finished: Bool) -> ChessSpectateState {
            var state = ChessSpectateState(id: "m-watch", faces: [cwOpponent], stake: 5)
            state.isFinished = finished
            return state
        }

        // ① 진행 중인 관전 + **최소화** → 남는다.
        let keep = ChessStore()
        keep.pollStepSeconds = 3_600
        keep.spectatorFeaturesEnabled = true
        keep.spectating = watching(finished: false)
        let keepController = cwController(keep)
        defer { keepController.discardWindowForTesting(); keep.stopPolling() }
        keepController.show()
        let keepWindow = try #require(keepController.currentWindow)
        keepController.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: keepWindow))
        #expect(keepController.lastVisibilityNotice == false, "최소화가 '안 보임'을 안 알렸다 — 치운 창의 폴링이 계속 돈다")
        #expect(keep.spectating != nil, "최소화만 했는데 관전이 내려갔다 — 되살리면 로비로 떨어진다")

        // ② 같은 가게에서 **닫기** → 내려간다(기준선이 갈린다: 같은 입력, 다른 통지, 다른 답).
        keepController.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: keepWindow))
        #expect(keep.spectating == nil, "창을 닫았는데 관전이 남았다 — 한 시간 뒤 열어도 낡은 남의 판이 선다")

        // ③ **끝난** 관전은 최소화에서도 내려간다(재조회가 없어 그대로 두면 영원히 낡는다).
        let done = ChessStore()
        done.pollStepSeconds = 3_600
        done.spectatorFeaturesEnabled = true
        done.spectating = watching(finished: true)
        let doneController = cwController(done)
        defer { doneController.discardWindowForTesting(); done.stopPolling() }
        doneController.show()
        let doneWindow = try #require(doneController.currentWindow)
        doneController.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: doneWindow))
        #expect(done.spectating == nil, "끝난 판을 관전한 채 치웠는데 그대로 남았다")
    }

    /// 가림은 **폴링만** 멈춘다 — `isWindowVisible` 과 시계 잎 뷰는 그대로다.
    @Test
    func occlusionStopsPollingButNotVisibility() throws {
        let store = ChessStore()
        store.pollStepSeconds = 3_600
        let controller = cwController(store)
        defer { controller.discardWindowForTesting(); store.stopPolling() }
        controller.show()
        controller.applyOcclusion(visible: false)
        #expect(controller.lastOcclusionNotice == false)
        #expect(store.isWindowVisible, "가려졌다고 '안 보임'까지 됐다 — 보이는 창의 시계가 멈춘다")
        controller.applyOcclusion(visible: true)
        #expect(controller.lastOcclusionNotice == true)
        #expect(store.isWindowVisible)
    }
}

// MARK: - 전역 스페이스 모니터 양보 (B2 — 이 작업의 ★)

/// ★ 미니게임 창을 띄워 둔 채 **체스 창**에서 누른 스페이스는 체스 몫이다.
///
/// 없으면: `MiniGameSpaceKey.standaloneWindowIDs` 에서 체스 창을 빼도 초록이다. 그러면 미니게임 창을
/// 열어 둔 사람의 체스 입력이 삼켜져(점프로 소비되어) 돌아오지 않는다 — 2026-09-17 오목 채팅 사고와
/// **같은 자리, 같은 증상**이다.
@MainActor
@Test
func spacePressedInTheChessWindowIsNeverTakenByTheMiniGame() {
    let game = cwWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    let chess = cwWindow(identifier: CheckChessWindowController.frameAutosaveName)
    let gomoku = cwWindow(identifier: CheckGomokuWindowController.frameAutosaveName)
    let unknown = cwWindow()                                  // 식별자 없음 = 모르는 창(팝오버·할 일 보드)
    defer { [game, chess, gomoku, unknown].forEach { $0.orderOut(nil) } }

    #expect(chess.isVisible, "전제: 올린 창")
    #expect(MiniGameSpaceKey.yieldsToOtherWindow(chess, gameWindow: game),
            "체스 창으로 간 스페이스를 미니게임이 삼킨다 — standaloneWindowIDs 에 체스 창이 빠졌다")
    // ★ 기준선이 갈린다: 모르는 창(글을 쓰지 않는)에는 **양보하지 않는다**. 둘이 같은 답이면 이 단언은
    //   "모든 창에 양보한다"를 말하는 것이고 등록을 지워도 초록이다.
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(unknown, gameWindow: game),
            "전제: 모르는 창에는 양보하지 않는다 — 이 답이 참이면 위 단언이 아무것도 안 잰다")
    // 오목은 전부터 들어 있다(목록 자체가 비어 버리는 변경도 잡는다).
    #expect(MiniGameSpaceKey.yieldsToOtherWindow(gomoku, gameWindow: game))
    #expect(MiniGameSpaceKey.standaloneWindowIDs.count == 3,
            "독립 창 목록이 \(MiniGameSpaceKey.standaloneWindowIDs) 다 — 창을 더했는데 등록을 안 했거나 그 반대다")
}

// MARK: - 소스 계약

/// 닫기와 '안 보임'은 **다른 문**이다. 위 결과 시험(`minimizingKeepsTheWatchButClosingEndsIt`)의 짝이다 —
/// 거기서 재는 것은 "지금 그렇게 동작하는가" 이고 여기서 재는 것은 "두 문이 섞이지 않았는가" 다.
@Test
func chessClosingIsItsOwnDoorNotJustInvisibility() throws {
    let source = cwStripped(try cwSource("CheckChessWindow.swift"))
    let willClose = try #require(cwFunctionBody(source, name: "windowWillClose"))
    let programmatic = try #require(cwFunctionBody(source, name: "close"))
    let visibility = try #require(cwFunctionBody(source, name: "notifyVisibility"))
    let miniaturize = try #require(cwFunctionBody(source, name: "windowDidMiniaturize"))
    let closed = try #require(cwFunctionBody(source, name: "notifyClosed"))

    #expect(willClose.contains("notifyClosed()"), "빨간 점 닫기가 스토어에 '닫혔다'를 안 알린다 — 관전이 남는다")
    #expect(programmatic.contains("notifyClosed()"),
            "프로그램 닫기(로그아웃)가 '닫혔다'를 안 알린다 — orderOut 은 windowWillClose 를 안 보낸다")
    #expect(closed.contains("store.windowDidClose()"), "notifyClosed 가 스토어 문을 안 부른다")
    #expect(!visibility.contains("notifyClosed") && !visibility.contains("windowDidClose"),
            "'안 보임' 통지에 닫기가 섞였다 — windowDidMiniaturize 도 이 문을 지나므로 최소화가 관전을 죽인다")
    #expect(!miniaturize.contains("notifyClosed") && !miniaturize.contains("windowDidClose"),
            "최소화가 닫기로 취급된다 — 되살리면 로비로 떨어진다")
    #expect(miniaturize.contains("notifyVisibility(false)"))
}

@Test
func theChessWindowNeverEndsTheMatchOnItsOwn() throws {
    let source = cwStripped(try cwSource("CheckChessWindow.swift"))
    #expect(!source.contains("InterruptToken"), "창이 판 중단 신호를 올린다")
    #expect(!source.contains("resign("), "창 수명이 기권을 부른다")
    #expect(!source.contains("func windowDidResignKey("), "키 상실 처리기가 생겼다")
    #expect(source.contains("frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)"),
            "자동저장 반환값을 버린다 — 이름이 겹쳐도 아무도 모른다")
    #expect(source.contains("old.setFrameAutosaveName(\"\")"), "재생성 때 자동저장 이름을 안 놓는다")
    let occlusion = try #require(cwFunctionBody(source, name: "windowDidChangeOcclusionState"))
    let apply = try #require(cwFunctionBody(source, name: "applyOcclusion"))
    #expect(occlusion.contains("occlusionState.contains(.visible)") && occlusion.contains("applyOcclusion("))
    #expect(apply.contains("windowOcclusionDidChange(visible: visible)"))
    #expect(!occlusion.contains("windowDidHide") && !apply.contains("windowDidHide") && !apply.contains("notifyVisibility"),
            "가림 통지가 '안 보임'으로 번졌다")
}

/// 앱 배선. **전부 빠져도 컴파일·스토어 테스트는 조용히 초록이다**(스토어 쪽 문이 옵셔널이라 `?.` 가 삼킨다).
@Test
func theAppWiresTheChessWindowAndItsMasterSwitch() throws {
    let app = cwStripped(try cwSource("CheckApp.swift"))
    #expect(app.contains("CheckChessWindowController.shared.configure(store: store.chess"),
            "체스 창에 스토어가 안 물린다 — 창은 뜨지만 플레이스홀더다")
    #expect(app.contains("ChessPlayerFace.me(from: self.store)"),
            "내 얼굴을 넘기지 않는다 — 내 카드가 '나' + 기본 캐릭터로 남는다")
    let wire = try #require(cwFunctionBody(app, name: "wireChess"))
    #expect(wire.contains("chess.presentWindow = { CheckChessWindowController.shared.show() }"),
            "openWindow 가 창을 띄우는 문이 없다 — 미니게임 입구가 상태만 불러오고 창은 안 뜬다")
    #expect(wire.contains("chess.dismissWindow = { CheckChessWindowController.shared.close() }"),
            "로그아웃의 reset() 이 창을 닫지 못한다 — 내용이 빈 창이 남는다")
    // ★ 주 스위치. 지워지면 순위 열은 영영 "불러오고 있어요" 이고 [관전] 은 아무 요청도 안 낸다(화면이 멀쩡해 보인다).
    #expect(wire.contains("chess.spectatorFeaturesEnabled = true"),
            "순위·관전 주 스위치가 안 켜진다 — 순위는 영영 로딩이고 [관전] 은 무반응이다")
    #expect(wire.contains("ChessAccountWatcher(userID:"), "계정 전환 감시가 없다 — 다음 사람이 앞 계정의 창을 본다")
    #expect(app.contains("wireChess()"), "wireChess() 를 아무도 안 부른다")

    // 미니게임 창 머리글 입구 — 버튼과 배선 **두 조각**을 다 본다(한쪽만 보면 버튼은 있는데 아무 데도 안 이어진다).
    let miniGame = cwStripped(try cwSource("MiniGamePanel.swift"))
    #expect(miniGame.contains("MiniGameChessEntryButton { onChess() }"),
            "미니게임 머리글에 체스 입구 버튼이 없다")
    #expect(miniGame.contains("onChess: { store.chess.openWindow(focusMatchID: nil) }"),
            "미니게임 헤더 입구가 체스 창을 안 연다")
    #expect(miniGame.contains("CheckChessWindowController.frameAutosaveName"),
            "전역 스페이스 모니터의 독립 창 목록에 체스 창이 없다(B2)")

    // 소유자가 체스 스토어를 들고, 로그아웃·계정 전환에서 내린다.
    let owner = cwStripped(try cwSource("WorkTimerStore.swift"))
    #expect(owner.contains("let chess: ChessStore"), "소유자가 체스 스토어를 안 든다")
    #expect(owner.contains("chess.attach(host: self)"), "체스 스토어에 host 가 안 물려 요청이 한 건도 안 나간다")
    #expect(owner.components(separatedBy: "chess.reset()").count - 1 >= 2,
            "로그아웃·계정 전환 두 경로에서 체스를 안 내린다 — 다음 사람이 앞 계정의 판을 본다")
    #expect(owner.contains("chess.hiddenPeerIDs = blockHiddenPeerIDs"),
            "차단이 체스에 안 비친다 — 차단했는데 체스 로비에 그대로 남는다")
}

/// 체스 창 루트의 **두 줄** — 말풍선 툴팁 레이어와 남의 캐릭터 한 표.
///
/// ★ 이 시험이 왜 체스 쪽에도 있어야 하는가: 두 줄을 지키는 그물은 저장소 전수목록(V0325·V0335)뿐이었고
///   그 둘은 "있으면 빨강" 방향으로 걸려 있었다(새 창을 더하면 숫자가 어긋나 빨개진다). 2026-10-05 실측:
///   `ChessPanel` 에서 `.checkTooltipLayer()` 와 `.appUserAvatarCharacters(from: safety)` **두 줄을 지우면**
///   그 둘이 **초록**이 되고 체스 자신의 40건은 한 건도 안 빨개졌다 — 즉 "지우는 것" 이 초록으로 가는 가장
///   짧은 길이었다. 이 시험이 그 길을 막는다.
@Test
func theChessWindowRootCarriesTheTooltipLayerAndTheCharacterTable() throws {
    let panel = cwStripped(try cwSource("ChessPanel.swift"))
    // 창 고정 프레임·배경·전경색 **뒤**다(판·목록 클리핑 바깥 — 안쪽에 두면 말풍선이 카드에 잘린다).
    #expect(panel.contains("height: ChessWindowLayout.contentSize.height, alignment: .topLeading) "
                           + ".background(CheckTheme.background) .foregroundStyle(CheckTheme.primaryText) "
                           + ".checkTooltipLayer() .appUserAvatarCharacters(from: safety)"),
            "체스 창 루트의 툴팁 레이어·캐릭터 표 두 줄이 그 자리에 없다 — 툴팁이 안 뜨고 남의 얼굴이 전부 이니셜이 된다")
    #expect(cwCount(".checkTooltipLayer()", in: panel) == 1, "체스 창에 레이어가 하나가 아니다")
    #expect(cwCount(".appUserAvatarCharacters(from:", in: panel) == 1, "체스 창에 캐릭터 표가 하나가 아니다")
    // 레이어가 **실제로 쓰이는** 자리도 함께 본다: 레이어만 있고 `.checkTooltip(` 이 한 곳도 없으면 장식이다.
    #expect(cwCount(".checkTooltip(", in: panel) >= 3,
            "체스 창에 말풍선 툴팁을 붙인 자리가 \(cwCount(".checkTooltip(", in: panel))곳뿐이다 — 레이어가 장식이다")
    // 표를 흘리는 쪽(창 → 패널 → 앱 스토어) 세 조각이 다 있어야 표가 비지 않는다.
    #expect(cwStripped(try cwSource("CheckChessWindow.swift"))
        .contains("ChessPanel(store: chess, me: me, safety: safety)"))
    #expect(cwStripped(try cwSource("CheckApp.swift")).contains("}, safety: store)"))
}

/// 저장소 안 모든 창의 자동저장 이름이 서로 다르다(겹치면 자리 저장이 **조용히** 죽는다).
@Test
func everyWindowAutosaveNameIsStillUniqueAfterAddingChess() throws {
    let directory = cwSourcesDirectory()
    let enumerator = try #require(FileManager.default.checkSourcesEnumerator(at: directory, includingPropertiesForKeys: nil))
    var names: [String] = []
    for case let file as URL in enumerator where file.pathExtension == "swift" {
        let text = cwStripped(try String(contentsOf: file, encoding: .utf8))
        var rest = Substring(text)
        while let found = rest.range(of: "frameAutosaveName = \"") {
            let after = rest[found.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            names.append(String(after[..<end]))
            rest = after[end...]
        }
    }
    #expect(names.contains("check.chess.window"))
    #expect(names.contains("check.gomoku.window"))
    #expect(names.count >= 4, "창 이름을 못 찾았다(\(names)) — 이 테스트가 아무것도 안 잰다")
    #expect(Set(names).count == names.count, "자동저장 이름이 겹친다: \(names)")
}

// MARK: - 소스 헬퍼(다른 파일의 것은 private 이라 복사 — V0317ShopTests.stripped 와 같은 규칙)

private func cwSourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
}

private func cwSource(_ name: String) throws -> String {
    try String(contentsOf: cwSourcesDirectory().appendingCheckSourcePath(name), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다. **안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다.**
private func cwStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// 걷어낸 소스에서 그 글자가 몇 번 나오는가(겹치지 않게 센다).
private func cwCount(_ needle: String, in source: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = Substring(source)
    while let found = rest.range(of: needle) {
        count += 1
        rest = rest[found.upperBound...]
    }
    return count
}

private func cwFunctionBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "func \(name)(") else { return nil }
    guard let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else { return nil }
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
