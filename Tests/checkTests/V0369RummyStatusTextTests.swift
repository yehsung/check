import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 아잉 큐브 — 렌더 검토에서 나온 글자 두 가지와 C-fix 갈래가 넣은 작은 판단들의 단위 시험.
//  · 내 차례 상태 줄: 첫 등록 뒤 판을 바꿨는데 [완료]가 꺼지면 꺼진 이유(설계서 §4.3 표 문구) — `RummyText.myTurnStatus`
//  · 로비 사람 목록 머리: 방 없음 · 내가 방장 · 남의 방 — `RummyText.peopleCaption(inRoom:amHost:)`
//  · stale 문구는 동작마다 다르다(V5-D5) · 같은 차례 판단(`RummyEditorKey` · `RummyTurnEditor.standsOn`, V3-1·V5-D1)

private func stFaces(_ texts: [String]) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

private func stEditor(table: [[String]] = [["D1", "D2", "D3"]], rack: [String] = ["A10", "A11", "A12", "B5", "C9"],
                      initialDone: Bool) -> RummyTurnEditor {
    RummyTurnEditor(table: table.map(stFaces), rack: stFaces(rack), initialDone: initialDone)
}

private func stRackID(_ editor: RummyTurnEditor, _ text: String) throws -> Int {
    try #require(editor.rack.first { $0.face.text == text }?.id)
}

@Suite("v0.3.69 아잉 큐브 — 상태 줄 이유 · 사람 목록 머리 · stale 문구 · 같은 차례")
@MainActor
struct V0369RummyStatusTextTests {
    @Test("내 차례 상태 줄 — 안 바꿨으면 '끌어 놓으세요', 바꿨는데 [완료]가 꺼지면 §4.3 이유, 맞추면 다시 '끌어 놓으세요'")
    func myTurnStatusShowsWhySubmitIsOff() throws {
        var editor = stEditor(initialDone: true)
        #expect(RummyText.myTurnStatus(editor) == RummyText.myTurn)

        // B5 하나만 새 세트로 — 맞지 않는 묶음.
        #expect(editor.move(try stRackID(editor, "B5"), to: .newMeld))
        #expect(editor.isChanged && !editor.canSubmit)
        #expect(editor.reason == .invalidMeld)
        #expect(RummyText.myTurnStatus(editor) == "맞지 않는 묶음이 있어요.")

        // 되돌리고 A10·A11·A12 로 맞는 세트 — [완료]가 켜지면 이유 대신 기본 문구.
        editor.reset()
        #expect(editor.move(try stRackID(editor, "A10"), to: .newMeld))
        let meld = editor.melds.count - 1
        #expect(editor.move(try stRackID(editor, "A11"), to: .meld(meld, index: nil)))
        #expect(editor.move(try stRackID(editor, "A12"), to: .meld(meld, index: nil)))
        #expect(editor.canSubmit)
        #expect(RummyText.myTurnStatus(editor) == RummyText.myTurn)
    }

    @Test("내 차례 상태 줄 — 첫 등록 전엔 진행 점수 그대로, 판 묶음을 건드렸으면 그 이유")
    func myTurnStatusBeforeInitial() throws {
        var editor = stEditor(initialDone: false)
        #expect(RummyText.myTurnStatus(editor) == RummyText.initialProgress(0))
        #expect(editor.move(try stRackID(editor, "A10"), to: .newMeld))
        #expect(RummyText.myTurnStatus(editor) == RummyText.initialProgress(editor.initialPoints))

        // 판의 A1-A4 에서 A4 를 떼어 내 A5·A6 과 새 세트 — 묶음은 모두 맞지만 첫 등록 차례에 판 묶음을 건드렸다.
        var touched = stEditor(table: [["A1", "A2", "A3", "A4"]], rack: ["A5", "A6", "C10", "C11", "C12"],
                               initialDone: false)
        let a4 = try #require(touched.melds.first?.first { $0.face.text == "A4" }?.id)
        let tookA4 = touched.move(a4, to: .newMeld)
        #expect(tookA4)
        let meld = touched.melds.count - 1
        #expect(touched.move(try stRackID(touched, "A5"), to: .meld(meld, index: nil)))
        #expect(touched.move(try stRackID(touched, "A6"), to: .meld(meld, index: nil)))
        #expect(touched.reason == .initialTableTouched)
        #expect(RummyText.myTurnStatus(touched) == "첫 등록 차례에는 판에 있던 묶음을 건드릴 수 없어요.")
    }

    @Test("로비 사람 목록 머리 — 방 없음 · 내가 방장 · 남의 방")
    func peopleCaptionFollowsMyRole() {
        #expect(RummyText.peopleCaption(inRoom: false, amHost: false) == "방장이 되면 여기서 사람을 골라 초대해요")
        #expect(RummyText.peopleCaption(inRoom: true, amHost: true) == "초대할 사람을 골라요")
        #expect(RummyText.peopleCaption(inRoom: true, amHost: false) == "방장만 초대할 수 있어요")
    }

    @Test("stale 문구 — 차례 동작(완료·뽑기·작업)만 '차례가 넘어갔어요', 나머지(시작 등)는 '다시 시도'")
    func staleTextDependsOnAction() {
        for action in [RummyNoticeText.Action.play, .draw, .draft] {
            #expect(RummyNoticeText.status(.stale, for: action) == RummyNoticeText.turnPassed)
        }
        for action in [RummyNoticeText.Action.start, .join, .leave, .create, .invite] {
            #expect(RummyNoticeText.status(.stale, for: action) == RummyNoticeText.tryAgain)
        }
        #expect(RummyNoticeText.status(.notYourTurn, for: .play) == RummyNoticeText.turnPassed)
    }

    @Test("같은 차례 — 키는 판·차례 자리·차례 시작 시각(seq 무관), 시각이 없으면 seq 로 가른다")
    func editorKeyIsTurnIdentity() {
        let id = UUID()
        let a = RummyEditorKey(matchID: id, turnSeatNo: 0, turnStartedMs: 1_000, seq: 5)
        let b = RummyEditorKey(matchID: id, turnSeatNo: 0, turnStartedMs: 1_000, seq: 6)
        #expect(a == b)
        #expect(a.text == b.text)
        #expect(a != RummyEditorKey(matchID: id, turnSeatNo: 0, turnStartedMs: 2_000, seq: 6))
        #expect(a != RummyEditorKey(matchID: id, turnSeatNo: 1, turnStartedMs: 1_000, seq: 5))
        #expect(RummyEditorKey(matchID: id, turnSeatNo: 0, turnStartedMs: nil, seq: 5)
                != RummyEditorKey(matchID: id, turnSeatNo: 0, turnStartedMs: nil, seq: 6))
    }

    @Test("편집기 standsOn — 같은 확정 판·랙(순서 무관)이면 참, 하나라도 다르면 거짓")
    func editorStandsOnItsStart() throws {
        var editor = stEditor(initialDone: true)
        #expect(editor.move(try stRackID(editor, "B5"), to: .newMeld))   // 작업 중이어도 시작점으로 잰다
        #expect(editor.standsOn(table: [stFaces(["D1", "D2", "D3"])], rack: stFaces(["C9", "B5", "A12", "A11", "A10"])))
        #expect(!editor.standsOn(table: [stFaces(["D1", "D2", "D3"])], rack: stFaces(["A10", "A11", "A12", "B5"])))
        #expect(!editor.standsOn(table: [stFaces(["D1", "D2", "D3"])], rack: stFaces(["A10", "A11", "A12", "B5", "C8"])))
        #expect(!editor.standsOn(table: [], rack: stFaces(["A10", "A11", "A12", "B5", "C9"])))
    }
}
