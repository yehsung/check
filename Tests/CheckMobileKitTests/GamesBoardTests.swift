@testable import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

/// 오목 판 좌표 변환(칸 중심 탭 → 그 칸 · 경계 탭) · 폰 탭 규칙(미리보기 → 같은 칸 재탭 착수) · 보이스오버 문구 · 규칙 예시.
@MainActor
@Suite struct GamesBoardTests {
    // MARK: - 좌표

    @Test("225칸 전부: 교차점 위치를 누르면 그 칸이다 — 폰 판 폭 여럿(소수 폭 포함)")
    func everyIntersectionMapsBack() {
        for side in [300.0, 361.0, 370.5, 402.0 - 32.0] as [CGFloat] {
            let geometry = GomokuPhoneBoardGeometry(side: side)
            for y in 0..<GomokuBoard.size {
                for x in 0..<GomokuBoard.size {
                    let point = GomokuPoint(x: x, y: y)!
                    let center = geometry.location(of: point)
                    #expect(geometry.point(at: center) == point, "side \(side) \(point.notation)")
                    // 칸 안쪽 흔들림(0.45칸)도 같은 칸이다.
                    let wobble = geometry.cell * 0.45
                    for (dx, dy) in [(wobble, 0), (-wobble, 0), (0, wobble), (0, -wobble), (wobble, -wobble)] as [(CGFloat, CGFloat)] {
                        #expect(geometry.point(at: CGPoint(x: center.x + dx, y: center.y + dy)) == point,
                                "side \(side) \(point.notation) offset \(dx),\(dy)")
                    }
                }
            }
        }
    }

    @Test("방향: A1 은 왼쪽 아래 · O15 는 오른쪽 위 · H8 은 한가운데(행은 아래가 1)")
    func orientation() {
        let geometry = GomokuPhoneBoardGeometry(side: 360)
        let a1 = geometry.location(of: GomokuPoint(notation: "A1")!)
        let o15 = geometry.location(of: GomokuPoint(notation: "O15")!)
        let h8 = geometry.location(of: GomokuPoint(notation: "H8")!)
        #expect(a1.x < o15.x && a1.y > o15.y)
        #expect(abs(h8.x - 180) < 0.001 && abs(h8.y - 180) < 0.001)
        #expect(abs(a1.x - geometry.inset) < 0.001 && abs(a1.y - (360 - geometry.inset)) < 0.001)
    }

    @Test("경계 탭: 두 교차점 사이 정확히 반 칸은 가까운 쪽(반올림) · 격자 밖 반 칸까지는 가장자리 칸 · 그 너머는 판 밖(nil)")
    func boundaryTaps() {
        let geometry = GomokuPhoneBoardGeometry(side: 360)
        let cell = geometry.cell
        let inset = geometry.inset
        let a1 = geometry.location(of: GomokuPoint(notation: "A1")!)
        // 가장자리 바깥 반 칸 안쪽 → A1.
        #expect(geometry.point(at: CGPoint(x: inset - cell * 0.49, y: a1.y)) == GomokuPoint(notation: "A1"))
        #expect(geometry.point(at: CGPoint(x: a1.x, y: a1.y + cell * 0.49)) == GomokuPoint(notation: "A1"))
        // 반 칸 넘게 바깥 → nil.
        #expect(geometry.point(at: CGPoint(x: inset - cell * 0.51, y: a1.y)) == nil)
        #expect(geometry.point(at: CGPoint(x: a1.x, y: a1.y + cell * 0.51)) == nil)
        #expect(geometry.point(at: CGPoint(x: 0, y: 0)) == nil, "판 모서리 여백은 판 밖")
        #expect(geometry.point(at: CGPoint(x: 360, y: 360)) == nil)
        let o15 = geometry.location(of: GomokuPoint(notation: "O15")!)
        #expect(geometry.point(at: CGPoint(x: o15.x + cell * 0.49, y: o15.y - cell * 0.49)) == GomokuPoint(notation: "O15"))
        #expect(geometry.point(at: CGPoint(x: o15.x + cell * 0.51, y: o15.y)) == nil)
        // 두 칸 사이: 0.49 는 왼쪽, 0.51 은 오른쪽.
        let h8 = geometry.location(of: GomokuPoint(notation: "H8")!)
        #expect(geometry.point(at: CGPoint(x: h8.x + cell * 0.49, y: h8.y)) == GomokuPoint(notation: "H8"))
        #expect(geometry.point(at: CGPoint(x: h8.x + cell * 0.51, y: h8.y)) == GomokuPoint(notation: "I8"))
        #expect(geometry.point(at: CGPoint(x: h8.x, y: h8.y - cell * 0.51)) == GomokuPoint(notation: "H9"))
    }

    @Test("규칙 예시 자르기(9줄 · D4 원점): H8 이 한가운데, 잘린 판 밖(C3)은 포함되지 않는다")
    func croppedGeometry() {
        let geometry = GomokuPhoneBoardGeometry(side: 180, lines: GomokuPhoneRuleExample.cropLines,
                                                originX: GomokuPhoneRuleExample.cropOriginX,
                                                originY: GomokuPhoneRuleExample.cropOriginY, insetRatio: 0.07)
        let h8 = GomokuPoint(notation: "H8")!
        #expect(abs(geometry.location(of: h8).x - 90) < 0.001)
        #expect(geometry.point(at: CGPoint(x: 90, y: 90)) == h8)
        #expect(geometry.contains(GomokuPoint(notation: "D4")!) && geometry.contains(GomokuPoint(notation: "L12")!))
        #expect(!geometry.contains(GomokuPoint(notation: "C3")!) && !geometry.contains(GomokuPoint(notation: "M13")!))
    }

    // MARK: - 탭 규칙

    private func match(turn: GomokuColor? = .black, moveCount: Int = 0, finished: Bool = false, id: String = "m-1",
                       stones: [String: GomokuColor] = [:]) -> GomokuMatchState {
        var board = GomokuBoard()
        for (notation, color) in stones { board[GomokuPoint(notation: notation)!] = color }
        return GomokuMatchState(
            id: id, stake: 5, myColor: .black,
            opponent: GomokuUser(id: "p", displayName: "구름빵", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: true),
            board: board, lastMove: nil, moveCount: moveCount, turn: finished ? nil : turn, deadline: nil,
            isFinished: finished, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false)
    }

    @Test("첫 탭은 미리보기 → 같은 칸 다시 탭은 착수 → 다른 칸 탭은 미리보기 이동 → 판 밖은 조용")
    func previewThenPlace() {
        let m = match()
        var preview = GomokuTapPreview()
        let h8 = GomokuPoint(notation: "H8")!, g8 = GomokuPoint(notation: "G8")!
        #expect(preview.tap(h8, match: m, isBusy: false, forbidden: [:]) == .preview(h8))
        #expect(preview.visiblePoint(match: m, isBusy: false, forbidden: [:]) == h8)
        #expect(preview.tap(g8, match: m, isBusy: false, forbidden: [:]) == .preview(g8), "다른 칸은 미리보기 이동")
        #expect(preview.tap(h8, match: m, isBusy: false, forbidden: [:]) == .preview(h8), "옮긴 뒤 첫 탭은 다시 미리보기")
        #expect(preview.tap(h8, match: m, isBusy: false, forbidden: [:]) == .place(h8))
        #expect(preview.point == nil, "둔 뒤에는 미리보기가 사라진다")
        #expect(preview.tap(nil, match: m, isBusy: false, forbidden: [:]) == .none)
    }

    @Test("둘 수 없을 때는 미리보기를 세우지 않고 스토어에 넘긴다(상대 차례·왕복 중·돌 있음·금수·끝난 판)")
    func refusalsGoToTheStore() {
        let h8 = GomokuPoint(notation: "H8")!
        let forbidden: [GomokuPoint: GomokuForbiddenReason] = [h8: .doubleThree]
        var preview = GomokuTapPreview()
        #expect(preview.tap(h8, match: match(turn: .white), isBusy: false, forbidden: [:]) == .refuse(h8))
        #expect(preview.tap(h8, match: match(), isBusy: true, forbidden: [:]) == .refuse(h8))
        #expect(preview.tap(h8, match: match(stones: ["H8": .white]), isBusy: false, forbidden: [:]) == .refuse(h8))
        #expect(preview.tap(h8, match: match(), isBusy: false, forbidden: forbidden) == .refuse(h8))
        #expect(preview.tap(h8, match: match(finished: true), isBusy: false, forbidden: [:]) == .refuse(h8))
        #expect(preview.point == nil)
        // 미리보기를 세운 뒤 왕복이 시작되면 그리지 않고, 그 상태의 재탭도 착수가 아니다.
        #expect(preview.tap(h8, match: match(), isBusy: false, forbidden: [:]) == .preview(h8))
        #expect(preview.visiblePoint(match: match(), isBusy: true, forbidden: [:]) == nil)
        #expect(preview.tap(h8, match: match(), isBusy: true, forbidden: [:]) == .refuse(h8))
    }

    @Test("미리보기는 그 판 그 수에서만 산다 — 자동 착수로 수가 넘어갔거나 판이 바뀌면 재탭은 착수가 아니라 미리보기부터")
    func stalePreviewDoesNotPlace() {
        let h8 = GomokuPoint(notation: "H8")!
        var preview = GomokuTapPreview()
        #expect(preview.tap(h8, match: match(moveCount: 4), isBusy: false, forbidden: [:]) == .preview(h8))
        #expect(preview.visiblePoint(match: match(moveCount: 6), isBusy: false, forbidden: [:]) == nil)
        #expect(preview.tap(h8, match: match(moveCount: 6), isBusy: false, forbidden: [:]) == .preview(h8))
        #expect(preview.tap(h8, match: match(moveCount: 6, id: "m-2"), isBusy: false, forbidden: [:]) == .preview(h8))
        #expect(preview.tap(h8, match: match(moveCount: 6, id: "m-2"), isBusy: false, forbidden: [:]) == .place(h8))
    }

    @Test("기권 누름 1초 가드 · 판돈 고르기(재탭 해제) · 잔액 모르면 막지 않음 · 도전 버튼은 근무 여부를 보지 않는다")
    func guardsAndGates() {
        let now = MobileClock.demoInstant
        #expect(!GomokuPhoneResignGuard.acceptsTap(shownAt: now, now: now.addingTimeInterval(0.4)))
        #expect(GomokuPhoneResignGuard.acceptsTap(shownAt: now, now: now.addingTimeInterval(1.0)))
        #expect(GomokuPhoneResignGuard.acceptsTap(shownAt: nil, now: now))

        #expect(GomokuPhoneStakeSelection.toggled(current: nil, tapped: .five) == .five)
        #expect(GomokuPhoneStakeSelection.toggled(current: .five, tapped: .five) == nil)
        #expect(GomokuPhoneStakeSelection.toggled(current: .three, tapped: .ten) == .ten)
        #expect(GomokuPhoneStakeSelection.affordable(.ten, balance: nil))
        #expect(!GomokuPhoneStakeSelection.affordable(.ten, balance: 9))
        #expect(GomokuPhoneStakeSelection.affordable(.five, balance: 5))

        let store = GomokuStore()
        let offWork = GomokuUser(id: "a", displayName: "초코칩", avatarURL: nil, characterID: nil, isWorking: false, isCapable: true, inMatch: false)
        #expect(GomokuPhoneChallengeGate.isEnabled(user: offWork, store: store), "근무 안 함이어도 도전할 수 있어야 한다")
        let outdated = GomokuUser(id: "b", displayName: "보리차", avatarURL: nil, characterID: nil, isWorking: true, isCapable: false, inMatch: false)
        #expect(!GomokuPhoneChallengeGate.isEnabled(user: outdated, store: store))
        store.outgoing = GomokuInvite(id: "i", peer: offWork, stake: 3, expiresAt: now)
        #expect(!GomokuPhoneChallengeGate.isEnabled(user: offWork, store: store), "보낸 신청이 떠 있으면 막는다")
    }

    // MARK: - 보이스오버 · 규칙 예시

    @Test("칸 보이스오버: \"H8, 비어 있음\" · 돌 · 마지막 수 · 자동 착수 · 금수 · 미리보기")
    func cellAccessibility() {
        let h8 = GomokuPoint(notation: "H8")!
        #expect(GomokuPhoneText.cellAccessibility(h8, stone: nil, isLastMove: false, isAuto: false, forbidden: nil, isPreview: false) == "H8, 비어 있음")
        #expect(GomokuPhoneText.cellAccessibility(h8, stone: .black, isLastMove: true, isAuto: false, forbidden: nil, isPreview: false) == "H8, 흑돌, 마지막 수")
        #expect(GomokuPhoneText.cellAccessibility(h8, stone: .white, isLastMove: false, isAuto: true, forbidden: nil, isPreview: false) == "H8, 백돌, 시간이 지나 자동으로 놓인 수")
        #expect(GomokuPhoneText.cellAccessibility(h8, stone: nil, isLastMove: false, isAuto: false, forbidden: .doubleThree, isPreview: false) == "H8, 3-3 금수")
        #expect(GomokuPhoneText.cellAccessibility(h8, stone: nil, isLastMove: false, isAuto: false, forbidden: nil, isPreview: true).hasPrefix("H8, 미리보기 돌"))
    }

    @Test("규칙 예시 여섯은 코어 판정기가 기대값 그대로 판정한다(맥과 같은 코퍼스 좌표)")
    func ruleExamplesMatchTheJudge() {
        #expect(GomokuPhoneRuleExample.all.count == 6)
        for example in GomokuPhoneRuleExample.all {
            let point = GomokuPoint(notation: example.point)!
            #expect(GomokuRules.judge(board: example.board, point: point, color: .black) == example.expected, "\(example.id)")
        }
    }
}
