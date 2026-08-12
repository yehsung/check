import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - 문구

@Test
func todoBoardStringsAreTheConfirmedProductCopy() {
    // 문구는 사용자가 확정한 제품 결정이라 리팩터링 중에 슬쩍 바뀌면 안 된다. 값으로 못 박아 둔다.
    #expect(TodoBoardStrings.title == "오늘 할 일")
    #expect(TodoBoardStrings.placeholder == "할 일 추가")
    #expect(TodoBoardStrings.emptyTitle == "오늘 할 일이 비어 있어요")
    #expect(TodoBoardStrings.emptyHint == "위에 적고 Enter를 누르세요")
    #expect(TodoBoardStrings.deleted == "삭제됨")
    #expect(TodoBoardStrings.undo == "되돌리기")
    #expect(TodoBoardStrings.footer == "이 목록은 내 맥에만 저장돼요")
}

@Test
func emptyStateKeepsFactAndNextActionOnSeparateLines() {
    // 두 줄이 한 줄로 합쳐지면(또는 한쪽이 사라지면) 처음 여는 사용자가 입력 행을 못 찾는다.
    #expect(TodoBoardStrings.emptyTitle != TodoBoardStrings.emptyHint)
    #expect(TodoBoardStrings.emptyHint.contains("Enter"))
}

@Test
func oldSectionHeaderCarriesTheCount() {
    #expect(TodoBoardStrings.oldSection(count: 0) == "오래된 항목 (0)")
    #expect(TodoBoardStrings.oldSection(count: 3) == "오래된 항목 (3)")
    #expect(TodoBoardStrings.oldSection(count: 12) == "오래된 항목 (12)")
}

@Test
func counterDenominatorComesFromTheRuleNotALiteral() {
    // 분모가 문구 쪽에 하드코딩되면 규칙만 바꿨을 때 화면이 거짓말을 한다.
    #expect(TodoBoardStrings.counter(current: 95) == "95/\(TodoRules.maxTitleLength)")
    #expect(TodoBoardStrings.counter(current: 95) == "95/100")
}

// MARK: - 100자 차단(순수 판정)

@Test
func draftAcceptsExactlyTheMaximumLength() {
    let ninetyNine = String(repeating: "가", count: TodoRules.maxTitleLength - 1)
    let atLimit = ninetyNine + "나"
    #expect(atLimit.count == TodoRules.maxTitleLength)
    #expect(TodoDraftInput.accepted(current: ninetyNine, proposed: atLimit) == atLimit)
}

@Test
func draftBlocksTheCharacterPastTheLimitInsteadOfTruncating() {
    let atLimit = String(repeating: "가", count: TodoRules.maxTitleLength)
    let overflow = atLimit + "나"
    // 잘라서 넣는 게 아니라 '한 글자도 안 들어간' 상태로 되돌린다 — 이미 100자면 더 안 들어간다.
    #expect(TodoDraftInput.accepted(current: atLimit, proposed: overflow) == atLimit)
}

@Test
func draftRejectsAnOverlongPasteWholeRatherThanKeepingItsPrefix() {
    let pasted = String(repeating: "가", count: 150)
    let result = TodoDraftInput.accepted(current: "", proposed: pasted)
    #expect(result.isEmpty)
    // 자동 절단이었다면 앞 100자가 남았을 것이다. 그 동작을 명시적으로 배제한다.
    #expect(result != String(pasted.prefix(TodoRules.maxTitleLength)))
}

@Test
func draftAlwaysAllowsShorteningEvenFromAnOverlongValue() {
    // 어떤 경로로든 100자를 넘긴 값이 필드에 들어와도 지우는 방향까지 막히면 사용자가 갇힌다.
    let overlong = String(repeating: "가", count: 120)
    let shorter = String(overlong.prefix(119))
    #expect(TodoDraftInput.accepted(current: overlong, proposed: shorter) == shorter)
    #expect(TodoDraftInput.accepted(current: overlong, proposed: "").isEmpty)
}

@Test
func draftCountsKoreanSyllablesAsOneCharacterEach() {
    // 한글 한 글자가 자모 3개로 세어지면 실제 한도가 33자로 줄어든다.
    let hundredKorean = String(repeating: "한", count: TodoRules.maxTitleLength)
    #expect(TodoDraftInput.accepted(current: "", proposed: hundredKorean) == hundredKorean)
    #expect(TodoDraftInput.accepted(current: hundredKorean, proposed: hundredKorean + "글") == hundredKorean)
}

@Test
func counterStaysHiddenBelowTheVisibleThreshold() {
    #expect(TodoDraftInput.counterText("") == nil)
    #expect(TodoDraftInput.counterText("오늘 할 일") == nil)
    let justBelow = String(repeating: "가", count: TodoRules.counterVisibleFrom - 1)
    #expect(TodoDraftInput.counterText(justBelow) == nil)
}

@Test
func counterAppearsFromTheThresholdThroughTheLimit() {
    let atThreshold = String(repeating: "가", count: TodoRules.counterVisibleFrom)
    #expect(TodoDraftInput.counterText(atThreshold) == "\(TodoRules.counterVisibleFrom)/\(TodoRules.maxTitleLength)")
    let atLimit = String(repeating: "가", count: TodoRules.maxTitleLength)
    #expect(TodoDraftInput.counterText(atLimit) == "100/100")
}

// MARK: - 행 높이 불변(상대 비교 — 절대 픽셀 단언 아님)

@MainActor
@Test
func rowKeepsTheSameHeightWhileEditingAndWhilePendingDelete() {
    // 삭제 대기·인라인 편집이 행 높이를 바꾸면 아래 행들이 통째로 밀려, 방금 겨눈 다음 클릭 목표가 도망간다.
    // 절대 픽셀 값이 아니라 세 상태의 높이가 '서로 같은지'만 본다.
    let item = todoFixture(index: 0, title: "설계 리뷰 코멘트 정리")
    let normal = renderedRowHeight(todoRow(item))
    let editing = renderedRowHeight(todoRow(item, isEditing: true))
    let pending = renderedRowHeight(todoRow(item, isPendingDelete: true))

    #expect(normal != nil)
    #expect(normal == editing)
    #expect(normal == pending)
}

@MainActor
@Test
func hoverDeleteButtonDoesNotResizeTheRow() {
    // ✕ 는 자리를 늘 잡고 opacity 만 바뀐다 — 마우스가 들어올 때 제목 폭이 줄며 글자가 다시 흐르면 안 된다.
    let item = todoFixture(index: 1, title: "hover 시에도 레이아웃은 그대로여야 한다")
    #expect(renderedRowHeight(todoRow(item)) == renderedRowHeight(todoRow(item, previewHovering: true)))
}

// MARK: - 렌더 스냅샷

@MainActor
@Test
func checkTodoBoardRendersSnapshot() throws {
    // 보드 전체(반투명 배경·헤더·입력 행·하단 캡션)의 뼈대 확인. ImageRenderer 는 ScrollView 안쪽과
    // AppKit TextField 를 그리지 못하므로 목록 알맹이는 아래 rowStack 스냅샷에서 따로 본다.
    let view = CheckTodoBoardView(
        items: sampleItems,
        oldItems: sampleOldItems,
        todayKey: sampleTodayKey,
        isOldSectionExpanded: false,
        editingID: nil,
        pendingDeleteID: sampleItems[3].id,
        draft: .constant(String(repeating: "가", count: 95)),
        onSubmitDraft: {},
        onToggleDone: { _ in },
        onBeginEdit: { _ in },
        onCommitEdit: { _, _ in },
        onCancelEdit: {},
        onDelete: { _ in },
        onUndoDelete: { _ in },
        onToggleOldSection: {},
        onClose: {}
    )
    let png = try renderTodoBoardPNG(view)
    #expect(!png.isEmpty)
    if let path = ProcessInfo.processInfo.environment["CHECK_TODO_BOARD_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func todoRowStackRendersEveryRowShapeAtBoardContentWidth() throws {
    // 보드 안쪽 폭(300 - 좌우 패딩 12·12 = 276)에서 완료(취소선)·이월 배지·삭제 대기·오래된 항목 접기가
    // 한 장에 다 나오는 장면. 절대 픽셀은 단언하지 않고, 사람이 눈으로 확인할 그림만 남긴다.
    let stack = TodoBoardRowStack(
        items: sampleItems,
        oldItems: sampleOldItems,
        todayKey: sampleTodayKey,
        isOldSectionExpanded: true,
        editingID: nil,
        pendingDeleteID: sampleItems[3].id,
        onToggleDone: { _ in },
        onBeginEdit: { _ in },
        onCommitEdit: { _, _ in },
        onCancelEdit: {},
        onDelete: { _ in },
        onUndoDelete: { _ in },
        onToggleOldSection: {},
        previewHovering: true
    )
    let png = try renderTodoRowPNG(stack)
    #expect(!png.isEmpty)
    if let path = ProcessInfo.processInfo.environment["CHECK_TODO_ROWS_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func todoRowStackRendersEmptyStateAndFullLengthTitle() throws {
    // 빈 상태 2줄, 그리고 100자(한도) 제목이 276pt 폭에서 2줄까지만 흐르고 말줄임되는지 확인용.
    let empty = TodoBoardRowStack(
        items: [],
        oldItems: [],
        todayKey: sampleTodayKey,
        isOldSectionExpanded: false,
        editingID: nil,
        pendingDeleteID: nil,
        onToggleDone: { _ in },
        onBeginEdit: { _ in },
        onCommitEdit: { _, _ in },
        onCancelEdit: {},
        onDelete: { _ in },
        onUndoDelete: { _ in },
        onToggleOldSection: {}
    )
    #expect(try !renderTodoRowPNG(empty).isEmpty)

    let longTitled = todoFixture(
        index: 6,
        title: String(repeating: "긴제목", count: 33) + "끝",
        originDayKey: "20260811"
    )
    #expect(longTitled.title.count == TodoRules.maxTitleLength)
    let png = try renderTodoRowPNG(todoRow(longTitled, previewHovering: true))
    #expect(!png.isEmpty)
    if let path = ProcessInfo.processInfo.environment["CHECK_TODO_ROW_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - 픽스처 · 렌더 도우미

/// 고정 시각. 스냅샷이 실행 시각에 따라 달라지지 않게 한다(생성/완료 시각은 화면에 안 뜨지만 결정성은 지킨다).
private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)

/// 스냅샷 기준일(KST). 이월 배지가 실행 날짜에 따라 흔들리지 않도록 픽스처와 함께 고정한다.
private let sampleTodayKey = "20260812"

/// 오늘 목록 표본: 3일 전 이월 / 어제 이월 / 오늘 완료(취소선) / 삭제 대기.
private let sampleItems: [TodoItem] = [
    todoFixture(index: 0, title: "설계 문서 초안 마무리", originDayKey: "20260809"),
    todoFixture(index: 1, title: "투두 보드 리뷰 반영", originDayKey: "20260811"),
    todoFixture(index: 2, title: "빌드 스크립트 정리", originDayKey: "20260812", doneAt: fixedNow),
    todoFixture(index: 3, title: "실수로 지운 항목", originDayKey: "20260812")
]

/// 7일 넘게 끌고 온 미완료 표본(하단 접힘 영역).
private let sampleOldItems: [TodoItem] = [
    todoFixture(index: 4, title: "언젠가 손볼 리팩터링", originDayKey: "20260701"),
    todoFixture(index: 5, title: "미뤄 둔 문서 정리", originDayKey: "20260630")
]

/// TodoItem 픽스처. 계약의 메모리와이즈 이니셜라이저를 **여기 한 곳에서만** 부른다 —
/// 모델 쪽 이니셜라이저가 바뀌어도 고칠 자리가 한 줄이다.
private func todoFixture(
    index: Int,
    title: String,
    originDayKey: String = "20260812",
    doneAt: Date? = nil
) -> TodoItem {
    TodoItem(
        id: UUID(uuidString: "0000000A-0000-0000-0000-\(String(format: "%012d", index))")!,
        title: title,
        createdAt: fixedNow,
        updatedAt: fixedNow,
        completedAt: doneAt,
        deletedAt: nil,
        originDayKey: originDayKey
    )
}

@MainActor
private func todoRow(
    _ item: TodoItem,
    isEditing: Bool = false,
    isPendingDelete: Bool = false,
    previewHovering: Bool = false
) -> TodoBoardRowView {
    TodoBoardRowView(
        item: item,
        todayKey: sampleTodayKey,
        isEditing: isEditing,
        isPendingDelete: isPendingDelete,
        onToggleDone: { _ in },
        onBeginEdit: { _ in },
        onCommitEdit: { _, _ in },
        onCancelEdit: {},
        onDelete: { _ in },
        onUndoDelete: { _ in },
        previewHovering: previewHovering
    )
}

/// 보드는 패널이 주는 300×400 을 그대로 재현해 그린다(뷰가 스스로 크기를 정하지 않으므로 여기서 준다).
@MainActor
private func renderTodoBoardPNG(_ view: some View) throws -> Data {
    try pngData(from: ImageRenderer(content: view.frame(width: 300, height: 400)))
}

/// 행 하나를 보드 안쪽 폭으로 그린다. 높이는 행이 스스로 정한 값(고정하지 않는다).
@MainActor
private func renderTodoRowPNG(_ view: some View, width: CGFloat = 276) throws -> Data {
    try pngData(from: ImageRenderer(content: view.frame(width: width).fixedSize()))
}

/// 행 높이를 픽셀로 읽는다. 값 자체를 단언하지 않고 상태끼리 비교하는 데만 쓴다.
@MainActor
private func renderedRowHeight(_ view: some View, width: CGFloat = 276) -> Int? {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else {
        return nil
    }
    return bitmap.pixelsHigh
}

@MainActor
private func pngData<Content: View>(from renderer: ImageRenderer<Content>) throws -> Data {
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw TodoBoardRenderError.failed
    }
    return png
}

private enum TodoBoardRenderError: Error {
    case failed
}
