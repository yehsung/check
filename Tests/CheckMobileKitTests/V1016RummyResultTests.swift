@testable import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 아잉 큐브 결과 · 반응 · 모션의 값(설계서 §6·§7). 폰 뷰는 맥 스위트가 못 보고 합성 입력도 금지라, 뷰가 부르는 값을 여기서 잰다. 그림은 데모 라우트 캡처로 본다.
@MainActor
@Suite struct V1016RummyResultTests {
    private static let index = MobileDemoFixtures.load()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func state(_ route: MobileDemoRummyRoute.Scene) throws -> RummyMatchState {
        let id = try #require(route.focusMatchID).uuidString.lowercased()
        let request = MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/rummy_state", query: "", headers: [:],
                                        bodyText: #"{"p_protocol":1,"p_match_id":"\#(id)"}"#)
        let entry = try #require(Self.index.entry(for: request, scenario: route.scenario))
        return try #require(try Self.decoder.decode(RummyActionResponse.self, from: entry.data).state)
    }

    private func faces(_ texts: String...) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

    private func meld(_ id: String, x: Int, y: Int, _ tiles: [RummyBoardTile]) -> RummyBoardMeld {
        RummyBoardMeld(id: id, tiles: tiles, frame: RummyRect(x: x, y: y, width: tiles.count * RummyTableLayout.tileWidth, height: RummyTableLayout.tileHeight), invalid: false)
    }

    private func tile(_ text: String, id: Int? = nil) -> RummyBoardTile {
        RummyBoardTile(id: id, face: RummyFace(text: text)!, highlighted: false)
    }

    private func reaction(_ id: Int, seat: Int, at: Date) -> RummyReactionEvent {
        RummyReactionEvent(id: id, seatNo: seat, sticker: AingSticker.allCases[0], isMine: false, receivedAt: at)
    }

    // MARK: - 결과

    @Test("결과: 서버 등수 순 · 순수익은 payout − 판돈이고 합이 0 · 4인 +2N/0/−N/−N")
    func rowsAndNet() throws {
        let match = try state(.result)
        let rows = GamesRummyResultPlan.rows(match)
        #expect(rows.map(\.finalRank) == [1, 2, 3, 4])
        let nets = rows.map { GamesRummyResultPlan.net($0, stake: match.stake) }
        #expect(nets == [10, 0, -5, -5])
        #expect(nets.reduce(0, +) == 0, "새로 생기는 루비는 없다")
        #expect(GamesRummyResultPlan.winnerName(match) == "초코칩")
        #expect(GamesRummyResultPlan.mine(match)?.displayName == "아잉러")
        #expect(rows.last?.state == .forfeit, "기권은 꼴찌")
    }

    @Test("한 판 더: 같은 판돈 · 공개 여부 · 나와 기권한 사람은 안 부른다(기준선: 2인 판은 상대를 부른다)")
    func rematch() throws {
        let four = GamesRummyResultPlan.rematch(try state(.result))
        #expect(four.stake == 5 && four.isPublic == false)
        #expect(four.invitees.map { $0.uuidString.lowercased().suffix(2) } == ["b2", "b3"], "구름빵(기권) · 나 제외")
        let two = GamesRummyResultPlan.rematch(try state(.resultWon))
        #expect(two.stake == 10 && two.isPublic == true && two.invitees.count == 1)
    }

    @Test("한 판 더 버튼: 요청 중 · 다른 게임 중이면 막고, 잔액은 안 본다")
    func canPlayAgain() {
        #expect(GamesRummyResultPlan.canPlayAgain(isWorking: false, blockedBy: nil))
        #expect(!GamesRummyResultPlan.canPlayAgain(isWorking: true, blockedBy: nil))
        #expect(!GamesRummyResultPlan.canPlayAgain(isWorking: false, blockedBy: .tetris))
    }

    @Test("이긴 장면: 내 순수익 + · 상대 − · 합 0 · 패 18장도 값 그대로")
    func wonScene() throws {
        let match = try state(.resultWon)
        let rows = GamesRummyResultPlan.rows(match)
        #expect(rows.map { GamesRummyResultPlan.net($0, stake: match.stake) } == [10, -10])
        #expect(rows.first?.seatNo == match.mySeatNo)
        #expect(rows.last?.finalRack?.count == 18)
    }

    @Test("문구: 등수 글자 · 기권 · 접근성 한 줄 · 기권 확인은 설계서 문장 · 판 보기는 지금 버튼을 말한다")
    func copy() throws {
        #expect(GamesRummyText.myResult(rank: 2, forfeited: false) == "2등")
        #expect(GamesRummyText.myResult(rank: 4, forfeited: true) == "기권 · 4등")
        #expect(GamesRummyText.remainingCount(3) == "남은 타일 3장")
        #expect(GamesRummyText.resultRowAccessibility(rank: 1, name: "나나", isMe: true, forfeited: false, score: 44, net: 10, rackCount: 0)
            == "1등, 나나, 나, 점수 +44, 루비 +10")
        #expect(GamesRummyText.forfeitDetail == "나가면 기권돼 꼴찌가 되고 판돈을 잃어요.")
        #expect(GamesRummyText.forfeitTitle != GamesRummyText.forfeitDetail)
        let view = try #require(GamesRummyText.rules.first { $0.title == "판 보기" })
        #expect(!view.detail.contains("[전체 보기]"), "확대 토글은 글자 없는 기호다")
    }

    // MARK: - 반응

    @Test("말풍선: 자리마다 최신 하나 · 2.5초가 지나면 없다")
    func reactionVisibility() {
        let now = Date(timeIntervalSince1970: 1_000)
        let feed = [reaction(1, seat: 1, at: now.addingTimeInterval(-2)), reaction(2, seat: 1, at: now.addingTimeInterval(-0.5)),
                    reaction(3, seat: 2, at: now.addingTimeInterval(-2.5)), reaction(4, seat: 3, at: now.addingTimeInterval(-2.49))]
        #expect(GamesRummyReactionPlan.visible(feed, at: now).map(\.id) == [2, 4], "만료 경계·최신 고르기")
        #expect(GamesRummyReactionPlan.visible([], at: now).isEmpty)
    }

    @Test("말풍선 프레임: 띄울 것이 없으면 시계가 멈추고(빈 목록) · 마지막 만료 뒤 한 프레임에서 끝난다 — 그 프레임엔 아무것도 안 보인다")
    func reactionFramesStop() throws {
        let clock = Date(timeIntervalSince1970: 1_000)
        let wall = Date(timeIntervalSince1970: 9_000)
        #expect(GamesRummyReactionPlan.frames(feed: [], clockNow: clock, wallNow: wall).isEmpty)
        let old = [reaction(1, seat: 1, at: clock.addingTimeInterval(-3))]
        #expect(GamesRummyReactionPlan.frames(feed: old, clockNow: clock, wallNow: wall).isEmpty, "끝난 말풍선이 시계를 돌린다")

        let live = [reaction(1, seat: 1, at: clock.addingTimeInterval(-1))]
        let frames = GamesRummyReactionPlan.frames(feed: live, clockNow: clock, wallNow: wall)
        let last = try #require(frames.last)
        #expect(frames.first! > wall)
        #expect(frames.count < 60, "1.5초 남았는데 프레임이 \(frames.count)개")
        let elapsed = last.timeIntervalSince(wall)
        #expect(elapsed >= 1.5 && elapsed < 1.6)
        #expect(GamesRummyReactionPlan.visible(live, at: clock.addingTimeInterval(elapsed)).isEmpty, "마지막 프레임이 말풍선을 못 지운다")
    }

    @Test("말풍선 수명 곡선: 끝 0.3초만 선형으로 사라진다 · 튀어나오기는 0.22초 뒤 1")
    func reactionCurves() {
        #expect(GamesRummyReactionPlan.opacity(age: 2.19) == 1)
        #expect(abs(GamesRummyReactionPlan.opacity(age: 2.35) - 0.5) < 0.001, "선형이 아니다")
        #expect(GamesRummyReactionPlan.opacity(age: 2.5) == 0)
        #expect(abs(GamesRummyReactionPlan.scale(age: 0) - 0.5) < 0.0001)
        #expect(GamesRummyReactionPlan.scale(age: 0.22) == 1)
    }

    @Test("말풍선 자리: 판 화면(가로)은 왼쪽 열 카드 오른쪽 · 화면 안 · 결과 화면(세로)은 위 끝 줄이면 아래로 · 그 밖은 위로")
    func reactionPlacement() {
        let height = GamesRummyReactionPlan.bubbleHeight
        for size in [CGSize(width: 667, height: 354), CGSize(width: 734, height: 372), CGSize(width: 932, height: 430)] {
            let layout = GamesRummyMatchLayout(size: size)
            for card in [layout.opponentCard(0), layout.opponentCard(1), layout.opponentCard(2), layout.mySeatCard] {
                #expect(GamesRummyReactionPlan.side(for: card, bounds: size) == .trailing)
                let center = GamesRummyReactionPlan.center(for: card, side: .trailing, bounds: size)
                #expect(center.x - height / 2 > card.maxX, "카드를 가린다")
                #expect(center.y - height / 2 >= 0 && center.y + height / 2 <= size.height, "\(size): 화면 밖 \(center)")
                #expect(center.x + height / 2 < layout.rightColumn.minX, "오른쪽 열까지 간다")
            }
        }
        for width: CGFloat in [320, 393, 430] {
            let bounds = CGSize(width: width, height: 700)
            let top = CGRect(x: 0, y: 48, width: 100, height: 48)
            #expect(GamesRummyReactionPlan.side(for: top, bounds: bounds) == .below)
            let center = GamesRummyReactionPlan.center(for: top, side: .below, bounds: bounds)
            #expect(center.x - height / 2 >= 0 && center.y - height / 2 > top.maxY)
            let row = CGRect(x: 0, y: 500, width: width, height: 118)
            #expect(GamesRummyReactionPlan.side(for: row, bounds: bounds) == .above)
            let mine = GamesRummyReactionPlan.center(for: row, side: .above, bounds: bounds)
            #expect(mine.y + height / 2 < row.minY && abs(mine.x - width / 2) < 0.5)
            let right = GamesRummyReactionPlan.center(for: CGRect(x: width - 40, y: 200, width: 40, height: 40), side: .above, bounds: bounds)
            #expect(right.x + height / 2 <= width)
        }
    }

    @Test("소스 계약: 말풍선은 .task · .id 재생성 고리가 없고 설계서대로 시각 비교 + 정해진 프레임으로 끝난다")
    func reactionSourceContract() throws {
        for file in ["GamesRummyReaction.swift", "GamesRummyResult.swift", "GamesRummyMotion.swift", "GamesRummyMatch.swift", "GamesRummyTableCanvas.swift", "GamesRummyRackView.swift"] {
            let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/" + file)
            #expect(!code.contains(".task("), "\(file): .task 고리")
            #expect(!code.contains(".task {"), "\(file): .task 고리")
            #expect(!code.contains(".id("), "\(file): 정체성 교체")
            #expect(!code.contains(".transition(.opacity"), "\(file): 불투명도 전환")
        }
        let reaction = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyReaction.swift")
        #expect(reaction.contains(".explicit(GamesRummyReactionPlan.frames("), "말풍선이 끝나도 시계가 돈다")
        #expect(reaction.contains("rummy.clock()"), "데모 시계를 안 읽는다")
        // 기준선: 소스를 실제로 읽었다.
        #expect(reaction.contains("GamesRummyReactionLayer"))
        let rack = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyRackView.swift")
        #expect(!rack.contains("accent.opacity(pulse"), "내 차례 빛 불투명도를 이징으로 깎는다")
    }

    @Test("자리표시: 아잉 큐브 폰 소스에 남은 자리표시가 없다")
    func noPlaceholders() throws {
        let hits = try IntegrationContractTests.files(containing: ["GamesRummyText.placeholder", "자리표시 —"], under: "Sources/CheckMobileKit")
        #expect(hits.isEmpty, "\(hits)")
    }

    // MARK: - 모션

    @Test("정렬 시차: 읽는 순서대로 25ms 씩 · 모든 타일이 있다")
    func sortStagger() {
        let editor = RummyTurnEditor(table: [], rack: faces("D3", "A1", "C2", "B9", "A2"), initialDone: true)
        let stagger = GamesRummyRackMotion.sortStagger(editor, mode: .number)
        var sorted = editor
        sorted.sortRack(.number)
        let order = sorted.rackLayout.readingOrder
        #expect(stagger.count == 5)
        for (position, id) in order.enumerated() {
            #expect(abs((stagger[id] ?? -1) - Double(position) * 0.025) < 0.0001)
        }
    }

    @Test("뽑기 비행: 새 사건은 날아오는 중 → 내려앉음 → 끝 · 동작 줄이기면 없다 · 옛 사건은 안 난다")
    func drawFlight() {
        let event = RummyDrawEvent(serial: 3, tiles: [RummyDrawnTile(tileID: 7, face: RummyFace(text: "A1")!, slot: RummyRackSlot(row: 0, halfCol: 0))])
        let flying = GamesRummyRackMotion.flight(lastDraw: event, landedSerial: 2, doneSerial: 2, reduceMotion: false)
        #expect(flying?.ids == [7] && flying?.landed == false)
        #expect(GamesRummyRackMotion.flight(lastDraw: event, landedSerial: 3, doneSerial: 2, reduceMotion: false)?.landed == true)
        #expect(GamesRummyRackMotion.flight(lastDraw: event, landedSerial: 3, doneSerial: 3, reduceMotion: false) == nil)
        #expect(GamesRummyRackMotion.flight(lastDraw: event, landedSerial: nil, doneSerial: nil, reduceMotion: true) == nil)
        #expect(GamesRummyRackMotion.flight(lastDraw: nil, landedSerial: nil, doneSerial: nil, reduceMotion: false) == nil)
    }

    @Test("뽑기 출발점: 오른쪽 열 [뽑기] 칸 가운데(받침대 칸 좌표) · 네 크기")
    func drawOrigin() {
        for size in [CGSize(width: 667, height: 354), CGSize(width: 734, height: 372), CGSize(width: 852, height: 393), CGSize(width: 932, height: 430)] {
            let layout = GamesRummyMatchLayout(size: size)
            let origin = layout.drawOrigin
            let screen = CGPoint(x: origin.x + layout.rack.minX, y: origin.y + layout.rack.minY)
            #expect(layout.draw.contains(screen), "\(size): \(screen)")
            #expect(screen == CGPoint(x: layout.draw.midX, y: layout.draw.midY))
            #expect(origin.x > layout.rack.width, "받침대 오른쪽에서 출발해야 한다")
        }
    }

    @Test("판 변화: 그대로면 nil · 묶음이 옮겨지면 그 타일만 · 새로 낸 타일은 안 난다")
    func boardMotionMoves() throws {
        let old = [meld("a", x: 40, y: 16, [tile("A1"), tile("A2"), tile("A3")]), meld("b", x: 400, y: 16, [tile("B4"), tile("B5"), tile("B6")])]
        #expect(GamesRummyBoardMotion.make(from: old, to: old) == nil)
        #expect(GamesRummyBoardMotion.make(from: [], to: old) == nil, "처음 그릴 때 날면 안 된다")

        let moved = [old[0], meld("b", x: 100, y: 200, old[1].tiles)]
        let motion = try #require(GamesRummyBoardMotion.make(from: old, to: moved))
        #expect(motion.moves.map(\.face.text) == ["B4", "B5", "B6"])
        #expect(motion.hidden == Set((0..<3).map { GamesRummyBoardMotion.Slot(meld: 1, tile: $0) }))
        let width = CGFloat(RummyTableLayout.tileWidth)
        #expect(motion.moves[1].from == CGPoint(x: 400 + width, y: 16) && motion.moves[1].to == CGPoint(x: 100 + width, y: 200))

        let grown = [meld("a", x: 40, y: 16, [tile("A1"), tile("A2"), tile("A3"), tile("A4")]), old[1]]
        #expect(GamesRummyBoardMotion.make(from: old, to: grown) == nil, "뒤에 붙인 타일 때문에 나머지가 날면 안 된다")
    }

    @Test("판 변화: 같은 면 둘은 가만히 있는 쪽이 먼저 짝 — 엇갈려 날지 않는다")
    func boardMotionDuplicates() throws {
        let old = [meld("a", x: 40, y: 16, [tile("A1"), tile("B1"), tile("C1")]), meld("b", x: 400, y: 16, [tile("A1"), tile("A2"), tile("A3")])]
        // 앞 묶음이 옮겨졌고, 뒤 묶음의 A1 은 그 자리에 있다 — 뒤의 A1 이 날면 틀린다.
        let new = [old[1], meld("a2", x: 40, y: 300, old[0].tiles)]
        let motion = try #require(GamesRummyBoardMotion.make(from: old, to: new))
        #expect(motion.moves.count == 3)
        #expect(motion.moves.allSatisfy { $0.to.y == 300 && $0.from.y == 16 && $0.from.x < 200 }, "\(motion.moves)")
    }

    @Test("판 변화: 방금 손으로 놓은 타일은 안 난다(손이 놓은 자리가 제자리) · 끼워 넣어 밀린 이웃은 난다")
    func boardMotionExcludesDrop() throws {
        let old = [meld("a", x: 40, y: 16, [tile("A1", id: 1), tile("A3", id: 3), tile("A4", id: 4)]), meld("b", x: 400, y: 16, [tile("A2", id: 2), tile("B2", id: 5), tile("C2", id: 6)])]
        let new = [meld("a", x: 40, y: 16, [tile("A1", id: 1), tile("A2", id: 2), tile("A3", id: 3), tile("A4", id: 4)]), meld("b", x: 400, y: 16, [tile("B2", id: 5), tile("C2", id: 6)])]
        let motion = try #require(GamesRummyBoardMotion.make(from: old, to: new, excluding: [2]))
        #expect(!motion.moves.contains { $0.face.text == "A2" }, "놓은 타일이 옛 자리에서 날아온다")
        #expect(Set(motion.moves.map(\.face.text)) == ["A3", "A4", "B2", "C2"])
        let without = try #require(GamesRummyBoardMotion.make(from: old, to: new))
        #expect(without.moves.contains { $0.face.text == "A2" }, "기준선: 빼지 않으면 난다")
    }

    @Test("판 변화: id 를 다시 쓴 새 편집기는 면으로 짝짓는다 · 너무 많으면 건너뛴다")
    func boardMotionIDsAndLimit() throws {
        let old = [meld("a", x: 40, y: 16, [tile("A1", id: 1), tile("A2", id: 2), tile("A3", id: 3)])]
        let new = [meld("a", x: 40, y: 16, [tile("B7", id: 1), tile("B8", id: 2), tile("B9", id: 3)])]
        #expect(GamesRummyBoardMotion.make(from: old, to: new) == nil, "다른 면이 같은 id 로 날아간다")

        let many = (0..<14).map { index in meld("m\(index)", x: 40, y: index * 40, [tile("A1"), tile("A2"), tile("A3")]) }
        let shifted = many.enumerated().map { index, item in meld(item.id, x: 300, y: index * 40, item.tiles) }
        // 같은 면이 여럿이라 자리가 다른 것끼리 짝이 지어진다 — 42장은 상한을 넘는다.
        #expect(GamesRummyBoardMotion.make(from: many, to: shifted) == nil)
        #expect(GamesRummyBoardMotion.make(from: Array(many.prefix(5)), to: Array(shifted.prefix(5)))?.moves.count == 15)
    }

    @Test("손에 놓은 기록: 놓으면 그 id · 묶음 이동은 그 묶음 전부 · 새 손이 닿으면 비운다")
    func recentDrop() {
        let model = GamesRummyMatchModel()
        #expect(model.recentDropIDs.isEmpty)
        let editor = RummyTurnEditor(table: [faces("A1", "A2", "A3")], rack: faces("A4", "B1"), initialDone: true)
        let scene = GamesRummyBoardScene.make(match: nil, editor: editor, isMyTurn: true, otherDraft: nil)
        let layout = GamesRummyMatchLayout(size: CGSize(width: 734, height: 372))
        let context = GamesRummyTouchContext(layout: layout, scene: scene, editor: editor, isMyTurn: true, editable: true)
        let rackID = editor.rack[0].id
        let slot = editor.rackLayout.slot(of: rackID)!
        let frame = context.rack.frame(slot)
        let start = CGPoint(x: frame.midX + layout.rack.minX, y: frame.midY + layout.rack.minY)
        let target = CGPoint(x: layout.table.midX, y: layout.table.maxY - 20 + GamesRummyGestureRules.fingerLift)
        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        model.touchChanged(start: start, location: target, context: context)
        _ = model.touchEnded(at: target, context: context)
        #expect(model.recentDropIDs == [rackID])
        model.touchChanged(start: start, location: start, context: context, holdDelay: 3_600)
        #expect(model.recentDropIDs.isEmpty, "낡은 기록이 다음 판 변화를 막는다")
        model.cancelTouch()
    }
}
