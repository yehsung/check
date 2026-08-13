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
    // 조절 컨트롤은 헤더 버튼(조작 안내 있음)과 슬라이더(값 컨트롤, 안내 없음)로 이름이 갈린다.
    // '투명도'가 아니라 '진하기'다 — 옆 숫자(opacity × 100)는 1에 가까울수록 커지므로, '투명도'로 부르면
    // 가장 투명한 끝이 "20%" 로 읽혀 뜻이 뒤집힌다(문구 방향 반전 회귀 방지).
    #expect(!TodoBoardStrings.opacityToggle.contains("투명도"))
    #expect(!TodoBoardStrings.opacityLabel.contains("투명도"))
    #expect(TodoBoardStrings.opacityToggle == "배경 진하기 · ⌥ + 스크롤로도 조절")
    #expect(TodoBoardStrings.opacityLabel == "보드 배경 진하기")
    // ⌥+스크롤은 이 툴팁 말고는 사용자에게 닿는 곳이 없다 — 여기서 빠지면 아무도 발견하지 못한다.
    #expect(TodoBoardStrings.opacityToggle.contains("⌥"))
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

// MARK: - 조절 행 펼침 상태(순수)

@Test
func tuningRowStartsCollapsedSoTheBoardOpensClean() {
    // 투명도 **값**은 영속되지만 조절기는 아니다 — 열 때마다 펼쳐져 있으면 목록 자리를 상시로 갉아먹는다.
    #expect(TodoBoardTuningState().isExpanded == false)
}

@Test
func tuningRowTogglesBothWays() {
    var state = TodoBoardTuningState()
    state.toggle()
    #expect(state.isExpanded)
    state.toggle()
    #expect(state.isExpanded == false)
}

@Test
func closingTheBoardCollapsesTheTuningRow() {
    // 다음에 보드를 열면 접혀 있어야 한다. 닫기 버튼·Esc·캐릭터 재클릭 — 경로와 무관하게 같은 결과다.
    var state = TodoBoardTuningState(isExpanded: true)
    state.boardDidClose()
    #expect(state.isExpanded == false)
    // 이미 접혀 있을 때 호출해도 열리지 않는다(토글이 아니라 초기화다).
    state.boardDidClose()
    #expect(state.isExpanded == false)
}

// MARK: - 글자 그림자 세기(순수)

@Test
func textShadowIsCompletelyOffAtTheShippedDefault() {
    // 출고 기본값에서 세기가 0 이 아니면, 설정을 한 번도 만지지 않은 사용자의 화면이 이 기능 때문에 바뀐다.
    #expect(TodoBoardTextShadow.strength(for: TodoBoardAppearance()) == 0)
    #expect(TodoBoardTextShadow.strength(for: TodoBoardAppearance(opacity: TodoBoardAppearance.maxOpacity)) == 0)
}

@Test
func textShadowIsAlwaysOnWhereverTheAppearanceSaysItIsNeeded() {
    // needsTextShadow 가 '그리느냐 마느냐'의 주인이다. 그 구간에 세기 0 인 지점이 하나라도 있으면
    // 배경도 그림자도 대비를 책임지지 않는 틈이 생긴다.
    for opacity in stride(from: TodoBoardAppearance.minOpacity, to: TodoBoardAppearance.blurKnee, by: TodoBoardAppearance.step) {
        let appearance = TodoBoardAppearance(opacity: opacity)
        #expect(appearance.needsTextShadow)
        #expect(TodoBoardTextShadow.strength(for: appearance) >= 0.5)
    }
    // 임계에서 두 스텝 아래로 내려가면 최대다 — 여기부터는 배경이 확실히 손을 놓는다.
    let deep = TodoBoardAppearance(opacity: TodoBoardAppearance.defaultOpacity - TodoBoardAppearance.step * 2)
    #expect(TodoBoardTextShadow.strength(for: deep) == 1)
}

@Test
func textShadowFadesInOverTwoSliderStepsInsteadOfPoppingOn() throws {
    // 한 칸에서 0→1 로 켜지면 슬라이더를 끌 때 글자 생김새가 툭 바뀌어 '고장'으로 읽힌다.
    // 사용자가 실제로 밟는 눈금(step 격자)만 본다 — 격자 사이의 값은 조작으로 도달할 수 없다.
    let step = TodoBoardAppearance.step
    let start = TodoBoardAppearance.defaultOpacity
    var previous = 0.0
    var jumps: [Double] = []
    for i in 0...3 {
        let strength = TodoBoardTextShadow.strength(for: TodoBoardAppearance(opacity: start - step * Double(i)))
        jumps.append(strength - previous)
        previous = strength
    }
    // 기본값에서 세 칸 내려오면 이미 최대다.
    #expect(previous == 1)
    // 어떤 한 칸도 절반을 넘게 뛰지 않는다. 하드 스위치(0→1)면 이 줄에서 잡힌다.
    // 여유 0.05 는 0.55-0.45 가 부동소수에서 0.10000000000000003 이 되는 만큼만 봐 주는 것이다.
    #expect(try #require(jumps.max()) <= 0.55)
    // 램프가 실제로 두 칸에 걸쳐 있다(0 이 아닌 칸이 둘 이상).
    #expect(jumps.filter { $0 > 0 }.count >= 2)
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
        onClose: {},
        appearance: TodoBoardAppearance(),
        onOpacityChange: { _ in }
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

// MARK: - 눈으로 볼 PNG 덤프(단언 아님)

/// 사람이 확인할 그림을 한 번에 떨어뜨린다. 경로(CHECK_TODO_SNAPSHOT_DIR)가 없으면 아무것도 하지 않는다 —
/// 그림은 리뷰용이고, 회귀를 지키는 단언은 아래 '픽셀 단언' 절에 있다(CI 는 경로 없이 돈다).
@MainActor
@Test
func todoBoardDumpsReviewSnapshots() throws {
    guard let dir = snapshotDirectory else { return }

    // (a) 빈 상태 — 보드 전체(300×400). 빈 상태의 세로 위치는 리스트 영역 높이가 있어야 판단이 된다.
    try dump(board(items: [], oldItems: []), to: dir, "board-empty.png", boardSized: true)
    // (b) 미완료 3 + 완료 2 + 이월 배지 — 보드 전체와 목록 본문 각각.
    try dump(board(items: mixedItems, oldItems: []), to: dir, "board-mixed.png", boardSized: true)
    // 목록 본문은 보드 안쪽 폭(300 - 좌우 패딩 12·12)으로 **고정해서** 그린다. 폭을 안 주면
    // frame(maxWidth:.infinity) 가 무한 제안을 받아 한 줄짜리 수천 픽셀 그림이 나온다(실제로 그랬다).
    // 배경을 깔아 주는 이유: 목록 본문은 자기 배경이 없어서 투명 위에 흰 글자가 얹힌 PNG 가 나오고,
    // 뷰어가 흰색으로 합성해 버리면 글자가 통째로 사라져 '아무것도 안 그려졌다'로 오해하게 된다.
    try dump(
        rowStack(items: mixedItems, oldItems: []).frame(width: boardContentWidth).padding(12).background(CheckTheme.panel),
        to: dir,
        "rows-mixed.png",
        boardSized: false
    )
    // (c) 아주 긴 제목 하나 — 2줄 말줄임 확인.
    try dump(
        rowStack(items: [longTitledItem], oldItems: []).frame(width: boardContentWidth).padding(12).background(CheckTheme.panel),
        to: dir,
        "rows-long-title.png",
        boardSized: false
    )
    // 빈 상태를 밝은 바탕 위에서도 본다(세로 위치 판단은 밝은 쪽이 더 정직하다).
    try dump(boardOverBackdrop(.white, items: []), to: dir, "tint-over-white-empty.png", boardSized: false)
    // 체크 원 확대: 행 하나를 4배로 그려 왼쪽 끝 픽셀 열을 눈으로 본다.
    try dump(
        todoRow(mixedItems[0]).frame(width: 276).fixedSize().padding(6).background(Color.black),
        to: dir,
        "row-circle-zoom.png",
        boardSized: false,
        scale: 4
    )
    // 틴트 판정용: 흰 바탕 / 밝은 사진 비슷한 바탕 위에 보드를 합성한다.
    // 실제 앱에는 패널의 NSVisualEffectView(.hudWindow) 블러가 한 겹 더 깔려 뒤를 더 어둡게 만들므로,
    // 이 그림은 '블러가 하나도 안 도왔을 때'의 최악 대비다 — 여기서 읽히면 실사용에서는 더 읽힌다.
    try dump(boardOverBackdrop(.white), to: dir, "tint-over-white.png", boardSized: false)
    try dump(boardOverBackdrop(nil), to: dir, "tint-over-bright-photo.png", boardSized: false)
    // 실제 화면에 가장 가까운 한 장: 순백 바탕화면이 hudWindow 재질을 통과한 뒤(실측 0.713) 그 위에 보드.
    try dump(boardOverBackdrop(TodoBoardTint.hudOverWhite), to: dir, "tint-as-shipped-over-white.png", boardSized: false)

    // 틴트 후보별 대비비를 같이 찍어 둔다 — 그림만 보고 '읽을 만한데?' 하고 넘기지 않도록 숫자를 옆에 둔다.
    for candidate in [0.45, 0.55, 0.62, 0.65, 0.72] {
        let bare = try measuredTintContrast(backdrop: .white, opacity: candidate)
        let real = try measuredTintContrast(backdrop: TodoBoardTint.hudOverWhite, opacity: candidate)
        print(String(
            format: "tint %.2f → 블러없음 %.2f/%.2f · 블러포함 %.2f/%.2f (주/보조)",
            candidate, bare.primary, bare.secondary, real.primary, real.secondary
        ))
    }

    // ── UI 개선 리뷰(v0.2.25 후보) ─────────────────────────────────────────────
    // 전부 **밝은 사진 바탕 + 기본 진하기(0.55)** 다. 실제 사용 조건이고, 흰 여백 한 장만 보면
    // "밝은 데서만 그렇다"로 착각한다. 하한(0.20)은 블러가 걷혀 바탕이 그대로 올라오는 최악이라 따로 뽑는다.
    //
    // 축 1 — 목록 면 처리(a 배경에 그냥 / b 카드 / c 행마다 면). 푸터는 출고안으로 고정한다.
    for (name, surface) in [
        ("list-a-plain", TodoBoardListSurface.plain),
        ("list-b-card", .card),
        ("list-c-rowtint", .rowTint)
    ] {
        try dump(variantBoard(listSurface: surface), to: dir, "\(name).png", boardSized: false)
    }
    // 축 2 — 하단 여백(a 그대로 / b 캡션을 목록 바로 아래로 / c 캡션 위에 바닥선). 목록은 출고안으로 고정.
    for (name, placement) in [
        ("footer-a-pinned", TodoBoardFooterPlacement.pinned),
        ("footer-b-underlist", .underList),
        ("footer-c-rule", .pinnedWithRule)
    ] {
        try dump(variantBoard(footerPlacement: placement), to: dir, "\(name).png", boardSized: false)
    }
    // 출고 조합을 세 상태 × 두 진하기로. 구분선이 하한에서도 보이는지는 이 짝을 나란히 봐야 판단이 된다.
    for (name, opacity) in [("default", TodoBoardAppearance.defaultOpacity), ("op020", TodoBoardAppearance.minOpacity)] {
        try dump(variantBoard(opacity: opacity), to: dir, "shipped-mixed-\(name).png", boardSized: false)
        try dump(variantBoard(items: [], opacity: opacity), to: dir, "shipped-empty-\(name).png", boardSized: false)
        try dump(
            variantBoard(items: longTitledMixedItems, opacity: opacity),
            to: dir,
            "shipped-long-title-\(name).png",
            boardSized: false
        )
    }
    // 구분선 세기 후보 3종을 같은 그림 안에 세로로 쌓는다. 따로 뽑으면 눈이 앞 그림을 기억하지 못해
    // "이게 더 진한가?"를 판단할 수 없다 — 세기 비교는 반드시 한 장 안에서 해야 한다.
    for opacity in [TodoBoardAppearance.defaultOpacity, TodoBoardAppearance.minOpacity] {
        try dump(
            separatorCandidates(opacity: opacity),
            to: dir,
            "separator-alphas-\(opacity == TodoBoardAppearance.minOpacity ? "op020" : "default").png",
            boardSized: false
        )
    }

    // 좌표 진단: 행 세 상태의 실제 높이와, 표본이 겨누는 자리의 밝기를 숫자로 남긴다.
    // 그림만으로는 "표본이 1pt 빗나갔다"를 볼 수 없다.
    print(String(
        format: "행 높이(평소/편집/삭제대기) = %@ / %@ / %@",
        String(describing: renderedRowHeight(todoRow(mixedItems[0]))),
        String(describing: renderedRowHeight(todoRow(mixedItems[0], isEditing: true))),
        String(describing: renderedRowHeight(todoRow(mixedItems[0], isPendingDelete: true)))
    ))
    let probed = try boardSurfaceLevels(opacity: TodoBoardAppearance.defaultOpacity, backdrop: .black)
    print(String(
        format: "표본 밝기(검은 바탕) 바탕 %.3f · 입력창 %.3f · 배지 %.3f · 완료 %.3f · 되돌리기 %.3f",
        probed.board, probed.field, probed.badge, probed.doneMark, probed.undo
    ))

    // 조절 슬라이더: 접힘/펼침 두 상태. 펼친 행이 목록을 얼마나 먹는지는 이 두 장을 나란히 봐야 안다.
    try dump(board(items: mixedItems, oldItems: []), to: dir, "tuning-collapsed.png", boardSized: true)
    try dump(
        board(items: mixedItems, oldItems: [], expandsOpacityRow: true),
        to: dir,
        "tuning-expanded.png",
        boardSized: true
    )
    try dump(
        board(items: [], oldItems: [], expandsOpacityRow: true),
        to: dir,
        "tuning-expanded-empty.png",
        boardSized: true
    )

    // 투명도 4점(최소 / 무릎점 / 기본 / 최대)을 순백 바탕과 밝은 사진 위에서. 바탕 밝기는
    // worstCaseBackdrop 로 계산한다 — 낮은 구간에서는 블러가 걷혀 재질 기여가 함께 줄기 때문이다.
    // 무릎점(0.52)은 슬라이더 눈금(0.05 격자)에 없는 값이라 그림만으로는 오해하기 쉽다 —
    // 사용자가 실제로 밟는 이웃 두 칸(0.50 = 그림자 첫 등장, 0.45 = 최대)을 같이 뽑는다.
    for (name, opacity) in [
        ("min", TodoBoardAppearance.minOpacity),
        ("knee-full", TodoBoardAppearance.defaultOpacity - TodoBoardAppearance.step * 2),
        ("knee-half", TodoBoardAppearance.defaultOpacity - TodoBoardAppearance.step),
        ("knee", TodoBoardAppearance.blurKnee),
        ("default", TodoBoardAppearance.defaultOpacity),
        ("max", TodoBoardAppearance.maxOpacity)
    ] {
        try dump(
            boardOverBackdrop(worstCaseBackdrop(opacity: opacity), opacity: opacity),
            to: dir,
            "opacity-\(name)-over-white.png",
            boardSized: false
        )
        try dump(
            boardOverBackdrop(nil, opacity: opacity),
            to: dir,
            "opacity-\(name)-over-photo.png",
            boardSized: false
        )
        let strength = TodoBoardTextShadow.strength(for: TodoBoardAppearance(opacity: opacity))
        let white = try measuredHaloContrast(backdrop: worstCaseBackdrop(opacity: opacity), opacity: opacity)
        let photo = try measuredHaloContrast(backdrop: brightPhotoAverage, opacity: opacity)
        print(String(
            format: "opacity %.2f (%@) 그림자세기 %.2f → 순백 %.2f→%.2f · 사진 %.2f→%.2f (그림자 끄기→켜기)",
            opacity, name as NSString, strength, white.plain, white.halo, photo.plain, photo.halo
        ))
    }
}

// MARK: - 픽셀 단언 — 체크 원 잘림

/// 행이 자기 레이아웃 폭 밖으로 한 점이라도 새면, 목록을 감싼 ScrollView 가 딱 그만큼을 잘라 낸다.
/// Circle().stroke 는 선 굵기의 절반(1.5/2 = 0.75pt)을 도형 **바깥**에 그리므로 여기서 샌다 —
/// 사용자가 신고한 '원 왼쪽 끝이 살짝 잘림'의 정체다. strokeBorder 는 안쪽으로 그려 새지 않는다.
@MainActor
@Test
func checkCircleNeverPaintsOutsideTheRowSoTheScrollContainerCannotClipIt() throws {
    // 행 바깥에 6pt 검정 여백을 두른다. 행이 밖으로 그린 그림이 있으면 이 여백에 찍힌다.
    let margin: CGFloat = 6
    let pixels = try renderPixels(
        todoRow(mixedItems[0], previewHovering: true)
            .frame(width: 276)
            .fixedSize()
            .padding(margin)
            .background(Color.black)
    )
    let marginPx = Int(margin) * pixels.scale

    // 왼쪽 여백 열 전체가 순수 검정이어야 한다(= 행이 왼쪽으로 새지 않았다).
    #expect(pixels.paintedColumn(in: 0..<marginPx) == nil)
    // 오른쪽도 같이 본다 — ✕ 버튼 쪽이 새면 오른쪽 끝이 잘린다.
    #expect(pixels.paintedColumn(in: (pixels.width - marginPx)..<pixels.width) == nil)
}

/// 앞 테스트만 있으면 '행에 여백을 더 넣어 원을 안쪽으로 밀기'라는 가짜 수정도 통과한다(실제로 그렇게
/// 고쳐져 있었다). 원은 행의 왼쪽 끝에 **붙어** 있어야 한다 — 헤더 제목·구분선·입력 상자·하단 캡션이 모두
/// 같은 왼쪽 기준선에 서 있는데 행만 들여쓰면 그 줄이 혼자 어긋난다.
@MainActor
@Test
func checkCircleStartsFlushWithTheRowsLeadingEdge() throws {
    let margin: CGFloat = 6
    let pixels = try renderPixels(
        todoRow(mixedItems[0])
            .frame(width: 276)
            .fixedSize()
            .padding(margin)
            .background(Color.black)
    )
    let rowLeft = Int(margin) * pixels.scale
    // 행 왼쪽 끝에서 첫 1pt(= 2px) 안에 원의 선이 이미 찍혀 있어야 한다.
    // strokeBorder 는 16pt 상자 안쪽에 붙여 그리므로 x=0 열부터 선이 온전히 들어온다.
    #expect(pixels.paintedColumn(in: rowLeft..<(rowLeft + pixels.scale)) != nil)
}

// MARK: - 픽셀 단언 — 목록의 구조(구분선 · 배지 자리 · 완료 위계)
//
// ☠︎ 실사용 신고(v0.2.24): "투두 리스트 창 UI가 너무 가독성이 떨어져. **각각의 항목들끼리 구분되는 선도
// 있으면 좋을 거 같고.** 전체적으로 좀 이상해."
// 아래 세 테스트는 그 신고에 대한 답 셋을 각각 픽셀로 못 박는다.

/// 행과 행 사이에 hairline 이 있고, 그 선이 **하한(0.20)에서도** 살아 있는가.
///
/// 두 진하기에서 다 재는 이유: 선은 흰색 알파라 진하기를 내리면(=뒤의 밝은 화면이 올라오면) 알파만으로는
/// 먼저 사라진다. 살려 두는 건 헤일로이고, 헤일로는 `todoBoardInkHalo()` 를 **선에 직접** 걸었을 때만 붙는다.
/// 배율(`todoBoardSurface`)을 실수로 곱해 두면 하한에서 선이 3분의 1로 옅어지는데, 검은 바탕 렌더에서는
/// 그게 바로 픽셀로 나온다.
@MainActor
@Test
func rowsAreSeparatedByAnIndentedHairlineAtEveryOpacity() throws {
    for opacity in [TodoBoardAppearance.defaultOpacity, TodoBoardAppearance.minOpacity] {
        let pixels = try renderPixels(
            rowStack(items: mixedItems, oldItems: [])
                .frame(width: boardContentWidth)
                .fixedSize()
                .background(Color.black)
                .environment(\.todoBoardAppearance, TodoBoardAppearance(opacity: opacity))
        )
        let inset = Int(TodoBoardRowSeparator.leadingInset) * pixels.scale
        // 들여쓴 구간(선이 지나가는 곳)이 거의 다 칠해진 가로줄을 센다. 임계 15 는 검은 바탕 위
        // 흰색 0.06(=15)과 0.09(=23) 사이가 아니라 **잡음 위**에 있는 값이다(글자 안티에일리어싱은 산발적이라
        // 한 줄을 통째로 채우지 못한다).
        var separatorRows: [Int] = []
        for y in 0..<pixels.height {
            var lit = 0
            for x in (inset + 2)..<(pixels.width - 2) where pixels.rgb(x: x, y: y).g >= 15 { lit += 1 }
            if lit >= Int(Double(pixels.width - inset - 4) * 0.95) { separatorRows.append(y) }
        }
        // 1pt 선은 scale 2 에서 2px 이므로, 붙어 있는 줄을 한 덩어리로 묶어 개수를 센다.
        var groups = 0
        for (i, y) in separatorRows.enumerated() where i == 0 || y - separatorRows[i - 1] > 1 { groups += 1 }
        // 항목 5개 → 선 4개. **마지막 행 아래에는 긋지 않는다** — 하나 더 있으면 아래에 뭔가 더 있다는 뜻이 된다.
        #expect(groups == mixedItems.count - 1, "진하기 \(opacity): 구분선 \(groups)개")
        // 들여쓰기: 선이 지나가는 줄이라도 체크 원 컬럼(0…24pt)은 비어 있어야 한다.
        // 전체 폭으로 그으면 선이 원 아래를 지나 원을 칸막이 안에 가둔 것처럼 보인다.
        for y in separatorRows {
            let leading = (0..<(inset - 2)).contains { pixels.rgb(x: $0, y: y).g >= 15 }
            #expect(!leading, "진하기 \(opacity): 구분선이 텍스트 컬럼 왼쪽까지 나갔다(y=\(y))")
        }
    }
}

/// 이월 배지("3일 전")가 행의 **오른쪽 끝**에 있어서 다섯 줄의 제목이 전부 같은 x 에서 시작하는가.
///
/// 배지를 체크 원과 제목 사이에 두면 그 줄의 제목만 배지 폭만큼 밀린다 — 목록을 훑는 눈은 왼쪽 세로선
/// 하나를 따라 내려가므로 한 줄만 어긋나도 매번 거기서 걸린다. 그래서 재는 것은 배지의 좌표가 아니라
/// **제목 시작 x 의 일치**다(배지를 앞으로 되돌리면 그 줄만 값이 달라진다).
@MainActor
@Test
func everyTitleStartsAtTheSameXBecauseTheCarryBadgeMovedToTheTrailingEdge() throws {
    let pixels = try renderPixels(
        rowStack(items: mixedItems, oldItems: [])
            .frame(width: boardContentWidth)
            .fixedSize()
            .background(Color.black)
    )
    let pitch = (Int(TodoBoardRowView.minHeight) + 1) * pixels.scale
    let checkColumn = 20 * pixels.scale
    // 글자만 고르는 임계 95: 완료 줄의 흐린 제목(흰 0.42 → 107)은 넘고, 배지 캡슐 채움(흰 0.10 → 26)과
    // 구분선(흰 0.09 → 23)은 못 넘는다. 체크 원 컬럼은 아예 건너뛴다(원 자체가 잉크다).
    var starts: [Int] = []
    for index in mixedItems.indices {
        let top = pitch * index
        let rows = top..<(top + Int(TodoBoardRowView.minHeight) * pixels.scale)
        var first: Int?
        for x in checkColumn..<pixels.width where rows.contains(where: { pixels.rgb(x: x, y: $0).g >= 95 }) {
            first = x
            break
        }
        starts.append(try #require(first, "행 \(index): 제목 잉크를 못 찾았다"))
    }
    let spread = try #require(starts.max()) - (try #require(starts.min()))
    // 허용 1pt 는 글리프 안티에일리어싱이 첫 열을 살짝 흐리게 시작하는 만큼이다.
    // 배지가 앞으로 돌아가면 그 줄만 배지 폭(≈38pt)만큼 벌어져 여기서 죽는다.
    #expect(spread <= pixels.scale, "제목 시작 x 가 줄마다 다르다: \(starts)")
}

/// 완료 항목의 체크 표시가 **자기 줄의 제목보다 밝지 않은가.**
///
/// 예전에는 완료 원이 CheckTheme.working(연두, 채도 100%)이라 화면에서 가장 밝은 것이 '끝난 일'이었다 —
/// 제목은 흐리게(0.42) 하고 취소선까지 그어 물러나게 만들어 놓고 아이콘만 튀면 위계가 뒤집힌다.
/// 밝기 비교와 색 비교를 **둘 다** 하는 이유: 알파만 낮춘 연두는 밝기 검사를 통과할 수 있고,
/// 무채색이지만 밝은 회색은 색 검사를 통과할 수 있다.
@MainActor
@Test
func theCompletedCheckMarkNeverOutshinesTheTitleItBelongsTo() throws {
    let pixels = try renderPixels(
        todoRow(mixedItems[4])
            .frame(width: boardContentWidth)
            .fixedSize()
            .background(Color.black)
    )
    #expect(mixedItems[4].isDone)
    func brightest(_ columns: Range<Int>) -> (level: Double, chroma: Int) {
        var level = 0.0
        var chroma = 0
        for y in 0..<pixels.height {
            for x in columns {
                let p = pixels.rgb(x: x, y: y)
                level = max(level, Double(p.r + p.g + p.b) / 3)
                chroma = max(chroma, p.g - p.r)
            }
        }
        return (level, chroma)
    }
    let mark = brightest(0..<(18 * pixels.scale))
    let title = brightest((24 * pixels.scale)..<pixels.width)
    // 연두 글리프는 평균 158, 흐린 제목은 107 이라 1.48배였다. 무채색으로 내린 지금은 117/107 = 1.09.
    // 문턱 1.2 는 그 사이다(안티에일리어싱으로 양쪽이 함께 몇 % 흔들려도 판정이 안 뒤집힌다).
    #expect(mark.level <= title.level * 1.2, "완료 체크 \(mark.level) vs 완료 제목 \(title.level)")
    // 연두(0.35, 0.88, 0.63)는 초록−빨강이 135 다. 무채색 잉크는 0 이라 여유가 크다.
    #expect(mark.chroma <= 20, "완료 체크에 색이 돌아왔다(g-r=\(mark.chroma))")
}

/// 목록을 카드로 감싸는 변형(`.card`)의 **면**도 진하기를 따라 옅어지는가.
///
/// 출고 기본은 `.plain` 이라 이 면은 지금 화면에 없다 — 그래서 기존 표면 테스트가 이 면을 못 본다.
/// 그런데 이 축은 사용자가 고르면 그날로 출고가 되는 값이라, 고른 뒤에 "카드만 검은 판때기로 남는다"는
/// 같은 신고를 다시 받게 두면 안 된다. 검은 바탕에서 재는 이유는 기존 surfaceFills… 와 같다:
/// 밝은 바탕에서는 흰 채움의 알파를 바꿔도 픽셀이 거의 안 움직여, 배율을 빼먹은 구현이 그대로 통과한다.
@MainActor
@Test
func theCardVariantsFillFadesWithTheSliderLikeEveryOtherSurface() throws {
    func levels(opacity: Double) throws -> (card: Double, board: Double) {
        let pixels = try renderPixels(
            ZStack {
                Color.black
                board(items: mixedItems, oldItems: [], opacity: opacity, listSurface: .card)
                    .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            }
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
        )
        // 카드 안쪽의 빈 자리(마지막 행 아래)와, 카드 **밖**의 맨 보드(캡션 오른쪽).
        return (pixels.meanLevel(in: (x: 150...250, y: 300...340)), pixels.meanLevel(in: (x: 200...260, y: 376...386)))
    }
    let shipped = try levels(opacity: TodoBoardAppearance.defaultOpacity)
    let floor = try levels(opacity: TodoBoardAppearance.minOpacity)
    // 카드가 실제로 보드보다 밝게 그려지긴 하는지부터(면이 아예 없으면 아래 비교가 무의미하다).
    #expect(shipped.card > shipped.board * 1.1)
    // 배율을 안 받으면 하한에서 카드/바탕 비가 1.37 → 2.06 으로 벌어진다(고정 알파는 바탕만 옅어지므로).
    #expect(abs(floor.card / floor.board - shipped.card / shipped.board) <= 0.35)
}

/// 표본 좌표가 실제로 그 면 위에 있는가. **이 테스트가 없으면 나머지 표면 테스트가 조용히 무의미해진다** —
/// 레이아웃이 바뀌어 표본이 빗나가면 그 자리는 그냥 보드 바탕이고, 바탕은 어느 투명도에서든 자기 자신과
/// 같으므로 "면이 바탕을 따라간다"가 자동으로 참이 된다(v0.2.25 에서 행 높이와 배지 자리가 둘 다 움직였다).
@MainActor
@Test
func surfaceProbesActuallyLandOnTheirSurfacesNotOnBareBoard() throws {
    let m = try boardSurfaceLevels(opacity: TodoBoardAppearance.defaultOpacity, backdrop: .black)
    // 입력창은 검정 채움이라 바탕보다 어둡고, 나머지 셋은 흰색·accent 채움이라 밝다.
    #expect(m.field < m.board * 0.95, "입력창 표본이 빗나갔다(\(m.field) vs 바탕 \(m.board))")
    #expect(m.badge > m.board * 1.15, "이월 캡슐 표본이 빗나갔다(\(m.badge) vs 바탕 \(m.board))")
    #expect(m.doneMark > m.board * 1.15, "완료 표시 표본이 빗나갔다(\(m.doneMark) vs 바탕 \(m.board))")
    #expect(m.undo > m.board * 1.15, "되돌리기 배지 표본이 빗나갔다(\(m.undo) vs 바탕 \(m.board))")
}

// MARK: - 픽셀 단언 — 빈 상태 정렬

@MainActor
@Test
func emptyStateIsHorizontallyCentredInTheBoardWidth() throws {
    let pixels = try renderPixels(
        rowStack(items: [], oldItems: [])
            .frame(width: 276)
            .fixedSize()
            .background(Color.black)
    )
    let box = try #require(pixels.paintedBounds())
    let leftGap = box.minX
    let rightGap = pixels.width - 1 - box.maxX
    // 좌우 여백이 같아야 가운데다. VStack(alignment:.center) 만으로는 VStack 폭이 글자에 맞춰져
    // 통째로 왼쪽에 붙는다 — 바깥 frame(maxWidth:.infinity, alignment:.center) 가 먹는지를 픽셀로 본다.
    #expect(abs(leftGap - rightGap) <= 2 * pixels.scale)
    // 두 줄이 실제로 폭의 한가운데를 지나는지도 본다(글자가 사라져 버린 경우를 배제).
    #expect(leftGap > 4 * pixels.scale)
}

@MainActor
@Test
func emptyStateIsVerticallyCentredInTheListAreaNotGluedToTheTop() throws {
    // 리스트 영역(400pt 보드에서 약 278pt) 안에서 빈 상태가 어디에 앉는지.
    // 상단 28pt 만 띄우던 시절에는 위 여백 29.5pt / 아래 여백 215pt 였다 — 그림으로 보면 입력 상자에 붙어
    // 아래가 통째로 비어 '그리다 만 화면'이 된다.
    let listHeight: CGFloat = 278
    let pixels = try renderPixels(
        rowStack(items: [], oldItems: [])
            .frame(width: 276, height: listHeight, alignment: .top)
            .background(Color.black)
    )
    let box = try #require(pixels.paintedBounds())
    let top = CGFloat(box.minY) / CGFloat(pixels.scale)
    let bottom = listHeight - CGFloat(box.maxY + 1) / CGFloat(pixels.scale)
    // 위아래 여백이 같아야 한다. 허용 오차 6pt 는 글자 상자의 위아래 여백(어센더/디센더)이
    // 잉크의 경계 상자와 정확히 같지 않아서 생기는 차이다.
    #expect(abs(top - bottom) <= 6)
    // 상단 붙임(28pt)이 다시 들어오면 이 줄에서 잡힌다.
    #expect(top >= listHeight * 0.25)
}

/// 위 두 테스트는 목록 본문(TodoBoardRowStack)만 본다 — 보드가 그 본문을 ScrollView 로 감싸는 순간
/// 세로 높이 제안이 무한이 되어 가운데 정렬이 조용히 죽는다. 그래서 **앱이 실제로 쓰는 경로**
/// (스냅샷 플래그를 끈 CheckTodoBoardView)로 한 번 더 그려서 위치를 확인한다.
@MainActor
@Test
func emptyBoardCentresTheEmptyStateOnTheRealRenderPathNotOnlyInTheSnapshotPath() throws {
    let realBoard = CheckTodoBoardView(
        items: [],
        oldItems: [],
        todayKey: sampleTodayKey,
        isOldSectionExpanded: false,
        editingID: nil,
        pendingDeleteID: nil,
        draft: .constant(""),
        onSubmitDraft: {},
        onToggleDone: { _ in },
        onBeginEdit: { _ in },
        onCommitEdit: { _, _ in },
        onCancelEdit: {},
        onDelete: { _ in },
        onUndoDelete: { _ in },
        onToggleOldSection: {},
        onClose: {},
        appearance: TodoBoardAppearance(),
        onOpacityChange: { _ in }
        // clipsOverflowInsteadOfScroll 를 주지 않는다 — 앱과 똑같은 경로로 그린다.
    )
    let pixels = try renderPixels(
        realBoard
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            .background(Color.black)
    )
    // 보드 배경(틴트)이 이미 온 화면을 덮으므로 '검정이 아닌 것' 으로는 글자를 못 고른다.
    // 밝기 90 위만 센다 — 틴트 위 배경은 24~34, 빈 상태 글자는 150~180 이라 사이가 넉넉히 벌어진다.
    // y 밴드는 입력 상자 아래(100pt)부터 하단 캡션 위(350pt)까지 — 그 사이에 있는 잉크는 빈 상태 두 줄뿐이다.
    let band = (100 * pixels.scale)..<(350 * pixels.scale)
    let box = try #require(pixels.paintedBounds(threshold: 90, rows: band))
    let centre = CGFloat(box.minY + box.maxY) / 2 / CGFloat(pixels.scale)
    // 리스트 영역은 대략 91~369pt(헤더 24 + 구분선 17 + 입력 32 + 위 여백 6 / 아래 캡션 19)이고 그 중앙은 230pt.
    #expect(abs(centre - 230) <= 20)

    // 가로도 여기서 같이 본다. 위쪽 emptyStateIsHorizontallyCentredInTheBoardWidth 는 목록 본문만
    // **테스트가 준 폭**에 넣고 그리는데, `.frame(width:)` 는 아무것도 안 해도 자식을 가운데에 놓는다 —
    // 즉 그 테스트만으로는 '가운데 정렬 코드'가 통째로 사라져도 초록이다(실측으로 확인).
    // 앱 경로로 그리면 정렬을 실제로 누가 하는지가 픽셀에 나온다.
    let leftGap = CGFloat(box.minX) / CGFloat(pixels.scale)
    let rightGap = CGFloat(pixels.width - 1 - box.maxX) / CGFloat(pixels.scale)
    #expect(abs(leftGap - rightGap) <= 3)
    // 좌상단에 붙어 버린 경우를 배제한다(보드 안쪽 왼쪽 기준선은 12pt다).
    #expect(leftGap > 30)

    // 하단 캡션이 **실제로 그려지는지**도 여기서 본다. 문구 상수만 지키던 시절에는 캡션을 통째로 지워도
    // 스위트가 초록이었다(뮤테이션으로 확인). 이건 이 목록이 서버로 안 간다는 유일한 안내라,
    // 조용히 사라지면 사용자가 사적인 메모를 적을 근거가 없어진다.
    // 임계 90 은 위 밴드와 같다. 70 으로 두면 보드 테두리(흰 0.18)의 파랑 채널이 74 라 좌우 끝이 걸려,
    // 캡션을 통째로 지워도 '뭔가 그려져 있다'가 되어 버린다(뮤테이션으로 확인).
    let footerBand = (355 * pixels.scale)..<(392 * pixels.scale)
    let footer = try #require(pixels.paintedBounds(threshold: 90, rows: footerBand))
    // 왼쪽 기준선(12pt)에 붙어 있고, 한 줄짜리 문구만큼의 폭이 있다.
    #expect(CGFloat(footer.minX) / CGFloat(pixels.scale) < 20)
    #expect(footer.maxX - footer.minX >= 100 * pixels.scale)
}

@MainActor
@Test
func emptyStateStopsCentringAsSoonAsThereAreRows() throws {
    // 가운데 정렬은 빈 상태 전용이다 — 항목이 생기면 첫 행이 위에서부터 쌓여야 한다.
    let listHeight: CGFloat = 278
    let pixels = try renderPixels(
        rowStack(items: [mixedItems[0]], oldItems: [])
            .frame(width: 276, height: listHeight, alignment: .top)
            .background(Color.black)
    )
    let box = try #require(pixels.paintedBounds())
    #expect(CGFloat(box.minY) / CGFloat(pixels.scale) < 12)
}

// MARK: - 픽셀 단언 — 틴트 위 글자 대비

@MainActor
@Test
func boardTintKeepsTextReadableOnAPureWhiteDesktopAtTheShippedDefault() throws {
    // 가장 밝은 바탕화면(순백)이 패널의 hudWindow 재질을 통과한 뒤 그 위에 틴트를 얹은, 실제 화면에
    // 가장 가까운 조건에서 합성된 픽셀을 읽어 WCAG 대비비를 계산한다.
    // 실측(기본값 0.55): 본문 4.90:1, 보조 3.43:1.
    //
    // 투명도가 가변이 된 뒤로 이 corridor 는 **기본값에서만** 지켜진다. 사용자가 그 아래로 내리면
    // 여기 숫자는 당연히 무너지고, 그 구간은 `needsTextShadow` 가 글자 헤일로로 넘겨받는다
    // (아래 haloLiftsLocalContrast… 테스트가 그 인계가 실제로 이뤄지는지 픽셀로 잰다).
    let measured = try measuredTintContrast(backdrop: TodoBoardTint.hudOverWhite)
    // 본문 글자는 AA 본문 기준 4.5:1 을 넘겨야 한다 — 여기가 무너지면 밝은 바탕화면에서 할 일이 안 읽힌다.
    #expect(measured.primary >= 4.5)
    // 보조 글자(하단 캡션·힌트·배지)는 일부러 흐린 색이라 4.5 를 목표로 하지 않는다.
    // 대신 UI 요소 기준 3:1 은 지킨다 — 이 아래로 내려가면 '있는지 없는지 모르겠는' 회색이 된다.
    #expect(measured.secondary >= 3.0)
}

@MainActor
@Test
func boardTintFollowsTheAppearanceValueInsteadOfAFixedLiteral() throws {
    // 슬라이더가 실제로 배경 알파를 움직이는지. 흰 바탕 위 보드 배경 픽셀은 투명도가 오를수록
    // **단조로 어두워져야** 한다(틴트는 어두운 색이다). 알파가 리터럴로 고정돼 있으면 세 값이 같아진다.
    let lowest = try boardBackgroundPixel(over: .white, opacity: TodoBoardAppearance.minOpacity)
    let shipped = try boardBackgroundPixel(over: .white, opacity: TodoBoardAppearance.defaultOpacity)
    let highest = try boardBackgroundPixel(over: .white, opacity: TodoBoardAppearance.maxOpacity)

    #expect(lowest.g > shipped.g)
    #expect(shipped.g > highest.g)
    // 끝에서 끝까지의 차이가 눈에 보이는 크기여야 한다 — 조절 범위가 실제로 무언가를 바꾼다는 뜻이다.
    // 실측: 최소 208, 기본 118, 최대 56 (초록 채널).
    #expect(lowest.g - highest.g >= 100)
}

@MainActor
@Test
func boardTintStillLetsTheDesktopShowThrough() throws {
    // 대비만 보고 틴트를 올리면 0.72 로 되돌아간다 — 사용자가 "뒤가 거의 안 비친다"고 물린 값이다.
    // 위 테스트(읽힌다)와 이 테스트(비친다)가 같이 있어야 값이 두 요구 사이에 갇힌다.
    //
    // 색 계산이 아니라 **보드 뷰를 통째로** 흰 바탕/검은 바탕 위에 그려서 배경 픽셀을 비교한다 —
    // 누군가 블러를 다시 SwiftUI `.background()` 로 집어넣어(= 호스팅 뷰가 불투명 합성) 보드가 뒤를
    // 완전히 가리는 옛 버그를 되살리면, 두 그림의 배경 픽셀이 같아지므로 여기서 잡힌다.
    let overWhite = try boardBackgroundPixel(over: .white)
    let overBlack = try boardBackgroundPixel(over: .black)
    // 바탕화면이 흰색일 때와 검은색일 때 보드 배경 픽셀이 충분히 달라야 뒤가 비치는 것이다.
    // 차이는 대략 (1-틴트)×255 다: 0.55 → 115, 0.65 → 89, 0.72 → 71.
    // 90 을 문턱으로 두면 틴트 상한이 약 0.645 로 잡혀, 물린 값(0.72)은 확실히 막고 미세 조정 여지는 남는다.
    #expect(overWhite.r - overBlack.r >= 90)
    #expect(overWhite.g - overBlack.g >= 90)
    #expect(overWhite.b - overBlack.b >= 90)
}

// MARK: - 픽셀 단언 — 표면이 바탕과 함께 옅어진다
//
// ☠︎ 실사용 신고: "투명도를 올리면 대부분을 차지하는 컬러는 투명해지는데 **할 일 추가하는 박스 색상은
// 오히려 더 진해져.** 두 색상은 상대적인 색상 차이가 있는 거지, 투명도 올리면 둘 다 투명해져야지."
//
// 재현된 원인은 둘이었고 둘 다 여기서 지킨다(수정 전 실측, 순백 바탕·sRGB 성분 평균):
//  op    보드바탕   입력창(수정전)  입력창(수정후)
//  0.95  0.2366    0.1896         0.1896   ← 출고 위쪽: 그대로
//  0.55  0.5582    0.4458         0.4458   ← 출고 기본값: **픽셀 동일**
//  0.52  0.5817    0.4654         0.4719
//  0.50  0.5974    0.3007         0.4557   ← 한 칸 내렸을 뿐인데 박스만 35% 어두워졌다(수정 전)
//  0.45  0.6392    0.1273         0.4068
//  0.20  0.8392    0.1664         0.5909   ← 하한: 수정 전에는 **출고값보다도 어두웠다**
//
// (1) 표면 채움이 고정 알파였다 → `TodoBoardAppearance.surfaceAlpha` 로 연동.
// (2) 헤일로를 보드 콘텐츠에 통째로 걸어 **면까지 그림자 원본**이 됐다 → 잉크에만 건다
//     (`todoBoardInkHalo`). 0.52→0.50 한 칸에서 벌어지는 위 붕괴는 거의 전부 이쪽이다.

@MainActor
@Test
func inputFieldFadesWithTheBoardInsteadOfDarkeningAgainstIt() throws {
    // 밝은 바탕 두 장에서 같이 본다 — 순백만 보면 "흰 여백에서만 그렇다"로 착각한다.
    for backdrop in [Color.white, brightPhotoAverage] {
        let shipped = try boardSurfaceLevels(opacity: TodoBoardAppearance.defaultOpacity, backdrop: backdrop)
        let floor = try boardSurfaceLevels(opacity: TodoBoardAppearance.minOpacity, backdrop: backdrop)
        let knee = try boardSurfaceLevels(opacity: TodoBoardAppearance.blurKnee, backdrop: backdrop)
        // 사용자가 실제로 밟는 눈금. 무릎점 바로 아래 한 칸이 신고가 나온 자리다.
        let oneStepBelowKnee = try boardSurfaceLevels(
            opacity: TodoBoardAppearance.defaultOpacity - TodoBoardAppearance.step,
            backdrop: backdrop
        )

        // 1) 신고 문장 그대로: 가장 투명하게 두면 입력창도 **밝아져야** 한다.
        //    수정 전 0.1664 < 출고 0.4458 이었다(= 투명하게 할수록 박스만 진해진다).
        #expect(floor.field > shipped.field)

        // 2) 한 칸 내렸을 때의 붕괴. 수정 전 0.4654 → 0.3007(0.65배), 수정 후 0.4719 → 0.4557(0.97배).
        //    바탕은 같은 칸에서 **밝아지므로**, 박스만 10% 넘게 어두워지면 그건 사용자가 신고한 그 계단이다.
        #expect(oneStepBelowKnee.field >= knee.field * 0.9)

        // 3) 어느 지점에서도 채움이 바탕보다 지나치게 어두워지지 않는다. 출고값의 어두운 몫은 0.201
        //    (= fieldFill 알파 0.20 그대로)이고, 헤일로가 켜지는 구간에서도 그 2.2배를 넘지 않아야 한다.
        //    수정 전 최댓값은 0.802(4배)였다. 실측 최댓값은 0.45 에서 0.364.
        let shippedDarkening = BoardSurfaceLevels.darkening(shipped.field, under: shipped.board)
        for opacity in sampledOpacities {
            let measured = try boardSurfaceLevels(opacity: opacity, backdrop: backdrop)
            let darkening = BoardSurfaceLevels.darkening(measured.field, under: measured.board)
            #expect(
                darkening <= shippedDarkening * 2.2,
                "투명도 \(opacity): 입력창이 바탕보다 \(darkening) 만큼 어둡다(출고 \(shippedDarkening))"
            )
        }
    }
}

/// 입력창만 고치면 같은 클래스의 나머지(이월 캡슐·완료 원·되돌리기 배지)가 그대로 남는다.
/// 전부 "면"이라 같은 규칙을 받아야 한다.
@MainActor
@Test
func everyBoardSurfaceStopsTurningIntoADarkSlabOnABrightDesktop() throws {
    for backdrop in [Color.white, brightPhotoAverage] {
        for opacity in sampledOpacities {
            let m = try boardSurfaceLevels(opacity: opacity, backdrop: backdrop)
            func darkening(_ surface: Double) -> Double {
                BoardSurfaceLevels.darkening(surface, under: m.board)
            }
            // 이월 캡슐은 **흰색** 0.10 이다. 어두운 보드 위에서는 살짝 밝은 칩인데, 수정 전에는
            // 밝은 바탕에서 오히려 바탕보다 0.358 만큼 어두운 회색 덩어리가 됐다(헤일로가 면을 먹었다).
            // 수정 후 최댓값 0.152.
            #expect(darkening(m.badge) <= 0.25, "투명도 \(opacity): 이월 캡슐 \(darkening(m.badge))")
            // 완료 표시·되돌리기 배지는 글리프가 작은 면 안에 꽉 차 있어 글자 헤일로를 완전히 피할 수 없다.
            // 그래서 기준이 캡슐보다 느슨하다 — 그래도 수정 전(0.670 / 0.605)은 확실히 밖이고,
            // 수정 후 실측은 0.417 / 0.424 다.
            #expect(darkening(m.doneMark) <= 0.45, "투명도 \(opacity): 완료 표시 \(darkening(m.doneMark))")
            #expect(darkening(m.undo) <= 0.45, "투명도 \(opacity): 되돌리기 배지 \(darkening(m.undo))")
        }
    }
}

/// 위 두 테스트는 **밝은** 바탕만 본다. 밝은 바탕에서는 흰색·연두색 채움의 알파를 바꿔도 픽셀이 거의
/// 안 움직여서(둘 다 밝다), 배율을 입력창에만 걸고 나머지를 빼먹은 구현이 그대로 통과한다.
/// 어두운 바탕에서는 반대로 그 채움들이 유일하게 밝은 것이라 알파가 픽셀에 그대로 드러난다 —
/// 여기가 `surfaceAlpha` 자체를 지키는 자리다.
@MainActor
@Test
func surfaceFillsScaleWithTheSliderInsteadOfKeepingAFixedAlpha() throws {
    let shipped = try boardSurfaceLevels(opacity: TodoBoardAppearance.defaultOpacity, backdrop: .black)
    let floor = try boardSurfaceLevels(opacity: TodoBoardAppearance.minOpacity, backdrop: .black)

    // 사용자가 말한 "상대적인 색상 차이": 표면과 바탕의 밝기 **비**가 조절 범위 끝에서도 유지돼야 한다.
    // 알파를 고정해 두면 바탕만 어두워지므로 이 비가 커진다(= 표면만 도드라진다).
    func ratioGap(_ surface: (BoardSurfaceLevels) -> Double) -> Double {
        abs(surface(floor) / floor.board - surface(shipped) / shipped.board)
    }
    // 입력창(검정 0.20): 수정 전 0.227 vs 0.796(차 0.569) → 수정 후 0.778 vs 0.796(차 0.018).
    #expect(ratioGap(\.field) <= 0.35)
    // 이월 캡슐(흰색 0.10): 수정 전 2.238 vs 1.582(차 0.656) → 수정 후 1.372 vs 1.582(차 0.210).
    // 배율을 캡슐에 안 걸면 하한에서 3.4배까지 벌어진다.
    #expect(ratioGap(\.badge) <= 0.35)
}

/// 면에서 헤일로를 걷어냈다고 **잉크에서까지** 걷히면 안 된다. 낮은 투명도에서 글자가 읽히는 근거가
/// 헤일로 하나뿐이기 때문이다(`haloLiftsLocalContrastWhereTheTintCanNoLongerCarryIt` 는 헤일로 함수를
/// 직접 불러서 재므로, 보드가 그 함수를 **안 부르게** 되어도 초록이다 — 그 구멍을 여기서 막는다).
@MainActor
@Test
func theBoardStillPutsTheHaloOnInkAfterTheSurfacesLeftIt() throws {
    func darkestInk(opacity: Double) throws -> (ink: Double, brightest: Double, board: Double) {
        let pixels = try renderPixels(
            ZStack {
                Color.white
                board(items: mixedItems, oldItems: [], opacity: opacity)
                    .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            }
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
        )
        // 첫 행 제목이 지나가는 띠. 헤일로가 없으면 여기서 가장 어두운 픽셀도 보드 바탕 언저리다
        // (글자는 흰색이라 바탕보다 **밝다**). 헤일로가 있으면 획 둘레가 확 어두워진다.
        var darkest = 1.0
        var brightest = 0.0
        for y in (100 * pixels.scale)...(114 * pixels.scale) {
            for x in (80 * pixels.scale)...(270 * pixels.scale) {
                let p = pixels.rgb(x: x, y: y)
                let level = Double(p.r + p.g + p.b) / (3 * 255)
                darkest = min(darkest, level)
                brightest = max(brightest, level)
            }
        }
        return (darkest, brightest, pixels.meanLevel(in: BoardSurfaceProbe.board))
    }

    let floor = try darkestInk(opacity: TodoBoardAppearance.minOpacity)
    // 하한에서는 글자 둘레가 바탕의 절반 아래로 내려가야 한다(= 헤일로가 실제로 깔렸다).
    #expect(floor.ink <= floor.board * 0.5)
    // ★ 그리고 **글자 자신은 한 톨도 옅어지지 않는다.** 표면 배율이 실수로 글자까지 번지면
    //   (`foregroundStyle` 에 곱하면) 획 한가운데 밝기가 primaryText(흰색 0.94)에서 곧바로 내려앉는다 —
    //   하한에서 0.94 → 0.34 면 획 중심이 0.94 대신 0.4 언저리가 된다. 0.85 문턱은 그 사이다.
    #expect(floor.brightest >= 0.85)

    // 그리고 출고 기본값에서는 한 톨도 없어야 한다 — 여기서 어두워지면 '픽셀 동일' 보증이 깨진 것이다.
    // 흰 글자만 있는 띠라 가장 어두운 픽셀이 곧 보드 바탕이다.
    let shipped = try darkestInk(opacity: TodoBoardAppearance.defaultOpacity)
    #expect(shipped.ink >= shipped.board * 0.98)
}

/// 편집 중인 줄의 **accent 테두리는 배율을 받지 않는다.** 이게 이 수정의 안전망이다 —
/// 채움이 옅어질수록 "지금 이 줄을 고치는 중"이라는 신호는 이 파란 선 하나에 남는다.
///
/// 검은 바탕 위에서 **파랑 − 빨강**의 최댓값을 본다. 파랑 채널만 보면 안 된다 —
/// 같은 행의 체크 원 테두리(흰색 0.32)가 검은 바탕에서 파랑 82 를 내는데, 그건 배율과 무관하게
/// 늘 같은 값이라 테두리가 3분의 1로 줄어도 최댓값이 안 움직인다(실제로 그렇게 틀려서 변형이 살아남았다).
/// accent(0.33, 0.67, 1.0)는 파랑이 빨강보다 훨씬 큰 유일한 색이고, 무채색 잉크는 이 차가 0,
/// ImageRenderer 의 노란 상자·빨간 금지 표시는 음수라 표본에 걸리지 않는다.
@MainActor
@Test
func theFocusBorderOfAnEditedRowKeepsItsFullAlphaAtEveryOpacity() throws {
    func maxBlue(opacity: Double) throws -> Int {
        let pixels = try renderPixels(
            todoRow(mixedItems[0], isEditing: true)
                .frame(width: boardContentWidth)
                .fixedSize()
                .background(Color.black)
                .environment(\.todoBoardAppearance, TodoBoardAppearance(opacity: opacity))
        )
        var bluest = 0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let p = pixels.rgb(x: x, y: y)
                bluest = max(bluest, p.b - p.r)
            }
        }
        return bluest
    }
    let shipped = try maxBlue(opacity: TodoBoardAppearance.defaultOpacity)
    // 테두리가 실제로 그려지긴 하는지부터. 실측 77(= accent 0.45 를 검은 바탕에 얹은 파랑 115 − 빨강 38).
    #expect(shipped > 60)
    // 하한에서도 같은 세기여야 한다. 배율을 여기까지 곱하면 알파 0.45 → 0.164 로 3분의 1이 된다.
    #expect(try maxBlue(opacity: TodoBoardAppearance.minOpacity) >= Int(Double(shipped) * 0.9))
}

// MARK: - 픽셀 단언 — 글자 헤일로

@MainActor
@Test
func haloLiftsLocalContrastWhereTheTintCanNoLongerCarryIt() throws {
    // 하한(0.20)은 이 기능이 만들 수 있는 최악의 조건이다. 그 지점에서는 `blurAlpha` 가 0 이라
    // **재질까지 통째로 걷혀** 순백 바탕화면이 그대로 올라온다 — hudOverWhite(0.713)로 재면 실제보다 후하다.
    // 판 배경만으로는 1.4:1(흰 글자가 흰 판 위에 뜬 꼴)이고, 여기서 가독을 떠받치는 건 헤일로 하나뿐이다.
    let measured = try measuredHaloContrast(
        backdrop: worstCaseBackdrop(opacity: TodoBoardAppearance.minOpacity),
        opacity: TodoBoardAppearance.minOpacity
    )
    // 그림자 없이는 사실상 안 읽힌다 — 이 숫자가 이미 높으면 아래 비교가 의미를 잃는다. 실측 1.44:1.
    #expect(measured.plain < 2.0)
    // 헤일로가 국소 대비를 AA 본문 기준(4.5:1) 위로 끌어올려야 한다. 실측 5.14:1.
    #expect(measured.halo >= 4.5)
    // '조금 나아짐'이 아니라 판이 뒤집혀야 한다.
    #expect(measured.halo >= measured.plain * 2.5)
}

@MainActor
@Test
func haloAlsoWorksOnABrightPhotoNotOnlyOnFlatWhite() throws {
    // 순백 한 장만 지키면 '흰 여백에서만 안 읽힌다'로 착각한다. 밝은 사진(=고주파 무늬) 위에서도
    // 넓은 그림자가 글자 둘레의 잔무늬를 눌러야 한다.
    let measured = try measuredHaloContrast(backdrop: brightPhotoAverage, opacity: TodoBoardAppearance.minOpacity)
    #expect(measured.halo >= 4.5)
    #expect(measured.halo >= measured.plain * 2.5)
}

@MainActor
@Test
func haloIsCompletelyAbsentAtTheShippedDefault() throws {
    // 기본값에서 그림자가 한 톨이라도 찍히면, 설정을 안 만진 사용자의 화면이 이 기능 때문에 바뀐다.
    let measured = try measuredHaloContrast(backdrop: TodoBoardTint.hudOverWhite, opacity: TodoBoardAppearance.defaultOpacity)
    #expect(measured.halo == measured.plain)
}

// MARK: - 픽셀 단언 — 조절 행 레이아웃

/// 펼친 행이 목록을 **덮지 않고 밀어낸다**(오버레이가 아니라 레이아웃 참여).
@MainActor
@Test
func expandingTheTuningRowPushesTheBoardContentDownInsteadOfCoveringIt() throws {
    let collapsed = try dividerY(of: board(items: [], oldItems: []))
    let expanded = try dividerY(of: board(items: [], oldItems: [], expandsOpacityRow: true))
    // 오버레이였다면 구분선이 제자리에 있다.
    #expect(expanded > collapsed)
    // 밀린 양 = 조절 행 높이(22) + 위 여백(6) = 28pt. 이보다 크면 행이 뚱뚱해진 것이고,
    // 작으면 행이 눌려 슬라이더 손잡이가 잘린다.
    #expect(abs((expanded - collapsed) - 28) <= 2)
}

@MainActor
@Test
func expandedTuningRowActuallyDrawsAControlRatherThanEmptySpace() throws {
    // '높이만 차지하는 빈 행'과 진짜 슬라이더를 구분한다. 헤더와 구분선 사이 밴드에 잉크가 있어야 한다.
    // ImageRenderer 는 슬라이더(AppKit 백킹)를 노란 막대로 그린다 — 렌더 아티팩트지만, 보드 팔레트에는
    // 노란색이 한 톨도 없으므로 '여기 AppKit 컨트롤이 있다'는 증거로는 오히려 정확하다.
    let expanded = try renderPixels(
        board(items: [], oldItems: [], expandsOpacityRow: true)
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            .background(Color.black)
    )
    let collapsed = try renderPixels(
        board(items: [], oldItems: [])
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            .background(Color.black)
    )
    // 밴드는 헤더 아래(38pt)부터 접힘 상태의 입력 상자 위(50pt)까지 — 접힘에서는 구분선 말고 아무것도 없고,
    // 펼침에서는 조절 행이 통째로 여기 들어온다.
    let band = (38 * expanded.scale)..<(50 * expanded.scale)
    #expect(yellowWidth(in: expanded, rows: band) >= 180 * expanded.scale)
    #expect(yellowWidth(in: collapsed, rows: band) == 0)
}

@MainActor
@Test
func emptyStateStaysCentredInTheShrunkenListWhenTheTuningRowIsOpen() throws {
    // 펼친 행이 목록 높이를 갉아먹으므로 빈 상태의 중앙도 그만큼 내려와야 한다. 세로 중앙 정렬이
    // 이 행 때문에 죽으면(예: 리스트가 무한 높이 제안을 받으면) 두 줄이 입력 상자에 붙는다.
    let pixels = try renderPixels(
        board(items: [], oldItems: [], expandsOpacityRow: true)
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            .background(Color.black)
    )
    let band = (128 * pixels.scale)..<(350 * pixels.scale)
    let box = try #require(pixels.paintedBounds(threshold: 90, rows: band))
    let centre = CGFloat(box.minY + box.maxY) / 2 / CGFloat(pixels.scale)
    // 접힘 상태의 리스트는 91…369pt(중앙 230), 펼치면 위가 28pt 내려가 119…369pt(중앙 244)다.
    #expect(abs(centre - 244) <= 20)
}

// MARK: - 실제 패널 위에서 — 닫으면 접힌다

/// 여기만 ImageRenderer 가 아니라 **진짜 NSPanel + NSHostingView** 를 쓴다. 이유는 하나다 —
/// '보드를 닫으면 조절 행이 접힌다'는 창의 생명주기에 달린 동작이라, 뷰를 따로 그려서는 재현이 안 된다.
///
/// 이 테스트가 지키는 것: 컨트롤러가 패널을 **파괴하지 않고 orderOut 만** 하기 때문에 SwiftUI 의
/// `.onDisappear` 는 영영 불리지 않는다(실측). 그래서 보드는 창 가시성을 직접 본다.
/// 누군가 그 관찰을 `.onDisappear` 로 '단순화'하면 이 테스트가 빨개진다.
@MainActor
@Test
func hidingTheRealPanelCollapsesTheTuningRowBeforeItIsShownAgain() throws {
    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: TodoBoardAnchor.boardSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.isReleasedWhenClosed = false
    // 보드 배경은 반투명이라 창 배경이 그대로 비친다. 검정으로 고정해야 잉크 판정이 흔들리지 않는다.
    panel.backgroundColor = .black
    panel.isOpaque = true
    // 앱과 같은 고정 외관. 이걸 빼면 시스템이 밝은 테마일 때 컨트롤이 밝은 배경 기준으로 그려진다.
    panel.appearance = NSAppearance(named: .darkAqua)

    // 보드 아래에 검정을 직접 깐다. 호스팅 뷰는 배경이 투명이라, cacheDisplay 로 뜬 비트맵에서는
    // 반투명 틴트가 알파를 그대로 달고 나와(합성 전 색) 잉크 판정이 통째로 흔들린다.
    let hosting = NSHostingView(
        rootView: AnyView(
            ZStack {
                Color.black
                board(items: [], oldItems: [], expandsOpacityRow: true)
            }
        )
    )
    hosting.frame = NSRect(origin: .zero, size: TodoBoardAnchor.boardSize)
    hosting.autoresizingMask = [.width, .height]
    panel.contentView?.addSubview(hosting)
    defer { panel.orderOut(nil) }

    panel.orderFrontRegardless()
    spinRunLoop()
    // 씨앗이 먹었다 = 펼친 상태로 떠 있다. 구분선이 조절 행 아래(≈72pt)로 밀려 있어야 한다.
    let expandedDivider = try #require(dividerY(of: hosting))
    #expect(expandedDivider > 60)

    // 닫기(컨트롤러가 하는 것과 똑같이 orderOut — close() 도 이 한 줄이다).
    panel.orderOut(nil)
    spinRunLoop()
    panel.orderFrontRegardless()
    spinRunLoop()

    // 다시 열면 접혀 있어야 한다 — 구분선이 헤더 바로 아래(≈44pt)로 돌아온다.
    let reopenedDivider = try #require(dividerY(of: hosting))
    #expect(reopenedDivider < 60)
    #expect(abs((expandedDivider - reopenedDivider) - 28) <= 3)
}

// MARK: - 픽셀 단언 — 모서리 곡선

/// 보드를 자르는 곡선은 반드시 스퀘어클(.continuous)이어야 한다. 패널 쪽은 같은 모서리를 CALayer 로 자르고
/// 그쪽 cornerCurve 가 .continuous 로 맞춰져 있는데, 여기만 원호(.circular)로 바뀌거나 style 을 생략하면
/// 반지름이 같아도 곡선이 달라져 재질과 틴트의 경계가 몇 px 어긋난 실선으로 남는다.
///
/// 두 곡선은 픽셀로 구별된다. 반지름 14 에서 원호는 맨 윗줄 x=14pt 부터 칠해지지만, 스퀘어클은 모서리를
/// 훨씬 길게 물고 들어가 그보다 오른쪽에서 시작한다.
@MainActor
@Test
func boardCornerUsesTheContinuousCurveThatMatchesThePanelLayer() throws {
    // 흰 바탕 위에 그린다 — 보드 배경(흰 위에서 약 148)과 바깥(255)의 간격이 커서 경계가 또렷하다.
    // scale 4 인 이유: 이 판정은 맨 윗줄 한 줄이 곡선의 몇 pt 를 평균하느냐에 달려 있다.
    // scale 2 는 두 곡선이 1.5pt 밖에 안 벌어지고(문턱까지 1픽셀), scale 8 은 줄이 너무 얇아져
    // 두 곡선이 거의 붙어 버린다(실측으로 둘 다 확인). scale 4 에서 2.5pt 로 가장 크게 벌어진다.
    let pixels = try renderPixels(
        ZStack {
            Color.white
            board(items: [], oldItems: [])
                .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
        }
        .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height),
        scale: 4
    )
    // 맨 윗줄(y=0)에서 보드가 시작되는 열. 두 곡선이 가장 크게 갈리는 줄이 여기다 —
    // 한 줄만 내려와도 차이가 0.25pt 로 줄어 구분이 안 된다(실측으로 확인).
    var start = CGFloat(pixels.width) / CGFloat(pixels.scale)
    for x in 0..<(pixels.width / 2) where pixels.rgb(x: x, y: 0).b <= 200 {
        start = CGFloat(x) / CGFloat(pixels.scale)
        break
    }
    // 실측(반지름 14, scale 4): .continuous 14.75pt, .circular 12.25pt. 문턱은 그 사이 한가운데다.
    // 이 테스트는 '눈에 띄는 차이'를 지키는 게 아니다 — 모서리 전체 면적으로 보면 두 곡선은 1.3% 밖에
    // 안 다르다. 지키는 것은 패널 레이어(cornerCurve = .continuous)와 **짝이 맞는지** 하나다.
    #expect(start >= 13.5)
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

// MARK: - 리뷰용 픽스처(미완료 3 + 완료 2 + 이월 배지)

/// 임무별 렌더 상태 (b). 이월 배지가 붙은 항목 1개(3일 전)를 섞어 둔다.
private let mixedItems: [TodoItem] = [
    todoFixture(index: 10, title: "설계 문서 초안 마무리", originDayKey: "20260809"),
    todoFixture(index: 11, title: "투두 보드 리뷰 반영", originDayKey: "20260812"),
    todoFixture(index: 12, title: "릴리스 노트 초안", originDayKey: "20260812"),
    todoFixture(index: 13, title: "빌드 스크립트 정리", originDayKey: "20260812", doneAt: fixedNow),
    todoFixture(index: 14, title: "스크린샷 다시 찍기", originDayKey: "20260812", doneAt: fixedNow)
]

/// 임무별 렌더 상태 (c). 한도(100자)까지 채운 제목 — 2줄 말줄임을 눈으로 본다.
private let longTitledItem = todoFixture(
    index: 15,
    title: String(repeating: "아주긴제목", count: 20),
    originDayKey: "20260812"
)

@MainActor
private func board(
    items: [TodoItem],
    oldItems: [TodoItem],
    opacity: Double = TodoBoardAppearance.defaultOpacity,
    expandsOpacityRow: Bool = false,
    pendingDeleteID: UUID? = nil,
    listSurface: TodoBoardListSurface = .plain,
    footerPlacement: TodoBoardFooterPlacement = .pinnedWithRule
) -> CheckTodoBoardView {
    CheckTodoBoardView(
        items: items,
        oldItems: oldItems,
        todayKey: sampleTodayKey,
        isOldSectionExpanded: false,
        editingID: nil,
        pendingDeleteID: pendingDeleteID,
        draft: .constant(""),
        onSubmitDraft: {},
        onToggleDone: { _ in },
        onBeginEdit: { _ in },
        onCommitEdit: { _, _ in },
        onCancelEdit: {},
        onDelete: { _ in },
        onUndoDelete: { _ in },
        onToggleOldSection: {},
        onClose: {},
        appearance: TodoBoardAppearance(opacity: opacity),
        onOpacityChange: { _ in },
        // ImageRenderer 는 ScrollView 안쪽을 그리지 못한다 — 스냅샷에서만 스크롤을 벗긴다.
        clipsOverflowInsteadOfScroll: true,
        previewExpandsOpacityRow: expandsOpacityRow,
        // 기본값은 **출고 그림**과 같게 둔다(테스트가 앱과 다른 것을 재면 안 된다).
        listSurface: listSurface,
        footerPlacement: footerPlacement
    )
}

/// 변형 비교용 한 장: 밝은 사진 비슷한 바탕 위에 보드를 얹는다(실제 사용 조건).
/// 판정에 필요한 건 보드 안쪽이지만 바탕을 함께 넣는 이유는, 반투명 판은 **뒤가 무엇이냐로 읽힘이 갈리기**
/// 때문이다 — 검은 바탕에 얹어 놓고 고른 색은 밝은 화면에서 다른 것이 된다.
@MainActor
private func variantBoard(
    items: [TodoItem] = mixedItems,
    opacity: Double = TodoBoardAppearance.defaultOpacity,
    listSurface: TodoBoardListSurface = .plain,
    footerPlacement: TodoBoardFooterPlacement = .pinnedWithRule
) -> some View {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.96, blue: 0.86),
                Color(red: 0.86, green: 0.93, blue: 1.0),
                Color(red: 1.0, green: 0.98, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        board(
            items: items,
            oldItems: [],
            opacity: opacity,
            listSurface: listSurface,
            footerPlacement: footerPlacement
        )
        .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
    }
    .frame(width: 360, height: 460)
}

/// 아주 긴 제목이 섞인 목록. 한 줄짜리 이웃이 있어야 '긴 제목만 2줄로 흐르고 나머지 줄의 시작점은 그대로'가
/// 그림에서 확인된다(긴 제목 하나만 그리면 정렬이 깨졌는지 알 수 없다).
private let longTitledMixedItems: [TodoItem] = [
    mixedItems[0],
    longTitledItem,
    mixedItems[3]
]

/// 구분선 세기 후보 3종(0.06 / 0.09 / 0.14)을 한 장에 세로로 쌓는다. 같은 진하기·같은 바탕에서
/// 나란히 놓아야 "안 보인다 / 딱 좋다 / 시끄럽다"가 갈린다.
@MainActor
private func separatorCandidates(opacity: Double) -> some View {
    let appearance = TodoBoardAppearance(opacity: opacity)
    func strip(_ alpha: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: "흰색 %.2f", alpha))
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.secondaryText)
                .todoBoardInkHalo()
                .padding(.bottom, 2)
            todoRow(mixedItems[0])
            TodoBoardRowSeparator(alpha: alpha)
            todoRow(mixedItems[1])
            TodoBoardRowSeparator(alpha: alpha)
            todoRow(mixedItems[3])
        }
        .frame(width: boardContentWidth)
    }
    return ZStack {
        LinearGradient(
            colors: [Color(red: 0.99, green: 0.96, blue: 0.86), Color(red: 0.86, green: 0.93, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        VStack(alignment: .leading, spacing: 14) {
            strip(0.06)
            strip(TodoBoardRowSeparator.defaultAlpha)
            strip(0.14)
        }
        .padding(12)
        .background(CheckTheme.panel.opacity(appearance.tintAlpha))
        .environment(\.todoBoardAppearance, appearance)
    }
    .frame(width: 340, height: 420)
}

@MainActor
private func rowStack(items: [TodoItem], oldItems: [TodoItem]) -> TodoBoardRowStack {
    TodoBoardRowStack(
        items: items,
        oldItems: oldItems,
        todayKey: sampleTodayKey,
        isOldSectionExpanded: true,
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
}

/// 보드 안쪽 폭. 300pt 보드에서 좌우 패딩 12 를 뺀 값 — 목록 본문을 이 폭으로 고정해 그린다.
private let boardContentWidth: CGFloat = TodoBoardAnchor.boardSize.width - 24

/// 주어진 바탕색 위에 **실제 보드 뷰**를 얹고, 글자·선이 하나도 없는 자리의 배경 픽셀을 읽는다.
/// 표본 지점은 빈 보드의 리스트 아래쪽(150, 330) — 빈 상태 두 줄은 230pt 근처에 있고 하단 캡션은
/// 왼쪽 끝에 붙어 있어, 이 점에는 보드 배경 말고 아무것도 없다.
@MainActor
private func boardBackgroundPixel(
    over backdrop: Color,
    opacity: Double = TodoBoardAppearance.defaultOpacity
) throws -> (r: Int, g: Int, b: Int) {
    let pixels = try renderPixels(
        ZStack {
            backdrop
            board(items: [], oldItems: [], opacity: opacity)
                .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
        }
        .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
    )
    return pixels.rgb(x: 150 * pixels.scale, y: 330 * pixels.scale)
}

/// 밝은 바탕화면 위에 보드를 얹은 그림. backdrop 이 nil 이면 사진 비슷한 밝은 그라디언트를 깐다 —
/// 순백 한 장만 보면 '흰 여백에서만 안 읽힌다'로 착각하기 쉽다.
@MainActor
private func boardOverBackdrop(
    _ backdrop: Color?,
    items: [TodoItem] = mixedItems,
    opacity: Double = TodoBoardAppearance.defaultOpacity,
    expandsOpacityRow: Bool = false
) -> some View {
    ZStack {
        if let backdrop {
            backdrop
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.96, blue: 0.86),
                    Color(red: 0.86, green: 0.93, blue: 1.0),
                    Color(red: 1.0, green: 0.98, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        board(items: items, oldItems: [], opacity: opacity, expandsOpacityRow: expandsOpacityRow)
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
    }
    .frame(width: 360, height: 460)
}

// MARK: - PNG 덤프

/// 그림을 남길 폴더. 환경변수가 없거나 폴더가 없으면 nil — CI 에서는 덤프 전체가 조용히 건너뛰어진다.
private var snapshotDirectory: URL? {
    guard let raw = ProcessInfo.processInfo.environment["CHECK_TODO_SNAPSHOT_DIR"], !raw.isEmpty else {
        return nil
    }
    let url = URL(fileURLWithPath: raw, isDirectory: true)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
        return nil
    }
    return url
}

@MainActor
private func dump(
    _ view: some View,
    to dir: URL,
    _ name: String,
    boardSized: Bool,
    scale: CGFloat = 2
) throws {
    let sized = boardSized
        ? AnyView(view.frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height))
        : AnyView(view.fixedSize())
    let renderer = ImageRenderer(content: sized)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw TodoBoardRenderError.failed
    }
    try png.write(to: dir.appendingPathComponent(name))
}

// MARK: - 픽셀 읽기

/// 렌더 결과를 sRGB 8bit 로 다시 그려 읽은 버퍼. NSBitmapImageRep 를 그대로 쓰면 색공간·프리멀티플라이가
/// 기기마다 달라 픽셀 비교가 흔들린다 — 여기서 한 번 정규화한다. y=0 은 그림의 맨 윗줄이다.
private struct RenderedPixels {
    let width: Int
    let height: Int
    let scale: Int
    let bytes: [UInt8]

    func rgb(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// 기본 임계 8. sRGB 반올림 잡음 위, 가장 흐린 선(흰 0.32 → 82) 아래로 잡아
    /// 안티에일리어싱 끄트머리까지 '그려진 것'으로 센다(검정 배경 위에 그린 그림 전용).
    /// 보드 전체처럼 배경 자체에 틴트가 깔린 그림에서는 임계를 올려서 글자만 골라야 한다.
    private func isPainted(x: Int, y: Int, threshold: Int) -> Bool {
        let p = rgb(x: x, y: y)
        return max(p.r, max(p.g, p.b)) >= threshold
    }

    /// 주어진 열 범위에서 처음으로 뭔가 그려진 열. 없으면 nil.
    func paintedColumn(in columns: Range<Int>, threshold: Int = 8) -> Int? {
        for x in columns where (0..<height).contains(where: { isPainted(x: x, y: $0, threshold: threshold) }) {
            return x
        }
        return nil
    }

    /// 그려진 픽셀 전체의 경계 상자. 아무것도 없으면 nil.
    func paintedBounds(
        threshold: Int = 8,
        rows: Range<Int>? = nil
    ) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in (rows ?? 0..<height).clamped(to: 0..<height) {
            for x in 0..<width where isPainted(x: x, y: y, threshold: threshold) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (minX, maxX, minY, maxY)
    }

    /// 주어진 가로 띠의 모든 픽셀 휘도. 백분위로 '잉크'와 '획 옆 배경'을 갈라내는 데 쓴다.
    func luminances(rows: Range<Int>) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(rows.count * width)
        for y in rows.clamped(to: 0..<height) {
            for x in 0..<width {
                out.append(relativeLuminance(rgb(x: x, y: y)))
            }
        }
        return out
    }
}

@MainActor
private func renderPixels(_ view: some View, scale: CGFloat = 2) throws -> RenderedPixels {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let cg = renderer.cgImage else { throw TodoBoardRenderError.failed }
    let w = cg.width, h = cg.height
    let count = w * h * 4
    let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    defer { raw.deallocate() }
    raw.initialize(repeating: 0, count: count)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
              data: raw,
              width: w,
              height: h,
              bitsPerComponent: 8,
              bytesPerRow: w * 4,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        throw TodoBoardRenderError.failed
    }
    // CGBitmapContext 는 메모리 첫 줄이 그림의 맨 윗줄이다 — 그래서 아래 y 인덱스는 위에서부터 센다.
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return RenderedPixels(
        width: w,
        height: h,
        scale: Int(scale),
        bytes: Array(UnsafeBufferPointer(start: raw, count: count))
    )
}

// MARK: - 대비비(WCAG)

/// 실제 렌더 픽셀에서 읽은 배경/글자 색으로 계산한 대비비.
private struct TintContrast {
    let primary: Double
    let secondary: Double
    let background: (r: Int, g: Int, b: Int)
}

/// 보드 배경 위에 얹힌 글자색을 **렌더된 픽셀에서** 뽑아 대비비를 낸다. 값(0.55·0.94)을 손으로 계산하면
/// 합성 방식이 바뀌었을 때(예: 블렌드 모드·색공간) 계산만 맞고 화면은 틀린 상태가 된다.
/// 글자 대신 같은 색의 사각형을 얹는 이유: 글리프는 안티에일리어싱 때문에 '획 속' 픽셀을 찾아야 하는데
/// 그 위치가 폰트에 따라 흔들린다. 채운 사각형이면 한가운데 한 점이 곧 정확한 합성 결과다.
@MainActor
private func measuredTintContrast(
    backdrop: Color,
    opacity: Double = TodoBoardAppearance.defaultOpacity
) throws -> TintContrast {
    func sample(_ overlay: Color?) throws -> (r: Int, g: Int, b: Int) {
        let probe = ZStack {
            backdrop
            Rectangle()
                .fill(CheckTheme.panel.opacity(opacity))
                .frame(width: 40, height: 40)
                .overlay(overlay ?? .clear)
        }
        .frame(width: 60, height: 60)
        let pixels = try renderPixels(probe, scale: 2)
        return pixels.rgb(x: pixels.width / 2, y: pixels.height / 2)
    }
    let bg = try sample(nil)
    return TintContrast(
        primary: contrastRatio(try sample(CheckTheme.primaryText), bg),
        secondary: contrastRatio(try sample(CheckTheme.secondaryText), bg),
        background: bg
    )
}

// MARK: - 국소 대비(글자 헤일로)

/// 그림자를 켰을 때와 껐을 때의 **국소** 대비. 헤일로는 판 전체의 색을 바꾸지 않고 획 둘레만 어둡게 만든다 —
/// 그래서 여기서 '배경'으로 삼는 것은 판의 색이 아니라 글자가 실제로 얹혀 있는 그 자리의 어두운 쪽 픽셀이다
/// (macOS 바탕화면 아이콘 이름표가 임의의 사진 위에서 읽히는 것과 같은 원리).
private struct HaloContrast {
    /// 그림자를 끈 같은 그림에서 잰 값. 비교 기준.
    let plain: Double
    /// 실제 세기(TodoBoardTextShadow.strength)로 그린 그림에서 잰 값.
    let halo: Double
}

/// 밝은 사진 바탕의 대표색. `boardOverBackdrop(nil)` 이 까는 그라디언트의 평균쯤 되는 밝은 크림색이다 —
/// 그림에는 그라디언트를 쓰고 숫자에는 단색을 쓰는 이유는, 표본 지점마다 배경이 달라지면 백분위가 흔들려
/// '그림자가 올린 몫'과 '배경이 원래 어두웠던 몫'을 구분할 수 없기 때문이다.
private let brightPhotoAverage = Color(red: 0.95, green: 0.96, blue: 0.95)

/// 주어진 투명도에서 **실제로 글자 뒤에 오는 밝기**. 순백 바탕화면이 hudWindow 재질을 통과한 결과인데,
/// 재질의 기여는 블러 뷰의 알파(`blurAlpha`)에 비례해 줄어든다 — 낮은 구간에서는 재질이 걷혀 바탕이
/// 그대로 올라오므로, 어디서나 0.713 을 쓰면 최악 구간에서 실제보다 후한 숫자가 나온다.
/// 계산은 정본(TodoBoardTint.materialLevel)에 맡긴다.
private func worstCaseBackdrop(opacity: Double) -> Color {
    Color(white: TodoBoardTint.materialLevel(
        over: 1.0,
        blurAlpha: TodoBoardAppearance(opacity: opacity).blurAlpha
    ))
}

/// 실제 글자(글리프)를 그려서 국소 대비를 잰다. 채운 사각형이 아니라 글자인 이유: 헤일로가 지켜야 하는 것은
/// **획 사이로 올라오는 밝은 배경**이고, 그건 획이 얇을수록 어려워진다. 사각형으로 재면 언제나 후하게 나온다.
@MainActor
private func measuredHaloContrast(backdrop: Color, opacity: Double) throws -> HaloContrast {
    let appearance = TodoBoardAppearance(opacity: opacity)

    func measure(strength: Double) throws -> Double {
        let pixels = try renderPixels(
            ZStack {
                backdrop
                Text("오늘 할 일 가나다 ABC 123")
                    .font(.subheadline)
                    .foregroundStyle(CheckTheme.primaryText)
                    .frame(width: 220, height: 60)
                    // 그림자는 화면과 **같은 함수**로 건다(겹수·반경을 여기 베끼면 측정만 후해진다).
                    // 순서도 같다 — 그림자는 콘텐츠에, 틴트는 그 뒤에.
                    .todoBoardTextHalo(strength: strength)
                    .background(CheckTheme.panel.opacity(appearance.tintAlpha))
            }
            .frame(width: 220, height: 60)
        )
        // 글자가 지나가는 가로 띠만 본다. 위아래 빈 곳까지 넣으면 백분위가 판 배경 쪽으로 쏠린다.
        let band = (24 * pixels.scale)..<(36 * pixels.scale)
        let luminances = pixels.luminances(rows: band).sorted()
        guard luminances.count > 20 else { throw TodoBoardRenderError.failed }
        func percentile(_ p: Double) -> Double {
            luminances[min(luminances.count - 1, max(0, Int(Double(luminances.count - 1) * p)))]
        }
        // 잉크 = 상위 5%(획 한가운데), 국소 배경 = 하위 25%(획 바로 옆 — 그림자가 켜지면 여기가 어두워진다).
        // 두 그림에 **같은 자로** 대므로, 차이는 오롯이 그림자가 만든 몫이다.
        let ink = percentile(0.95)
        let local = percentile(0.25)
        return (max(ink, local) + 0.05) / (min(ink, local) + 0.05)
    }

    return HaloContrast(
        plain: try measure(strength: 0),
        halo: try measure(strength: TodoBoardTextShadow.strength(for: appearance))
    )
}

/// 주어진 가로 띠에서 노란 픽셀이 차지하는 최대 가로 폭(px). ImageRenderer 가 AppKit 백킹 컨트롤을
/// 그리지 못해 남기는 노란 막대를 센다 — 보드 팔레트에는 노란색이 없으므로 오검출이 없다.
private func yellowWidth(in pixels: RenderedPixels, rows: Range<Int>) -> Int {
    var widest = 0
    for y in rows.clamped(to: 0..<pixels.height) {
        var minX = pixels.width, maxX = -1
        for x in 0..<pixels.width {
            let p = pixels.rgb(x: x, y: y)
            // 노랑 = R,G 가 높고 B 가 낮다.
            if p.r > 170 && p.g > 150 && p.b < 90 {
                minX = min(minX, x); maxX = max(maxX, x)
            }
        }
        if maxX >= 0 { widest = max(widest, maxX - minX + 1) }
    }
    return widest
}

/// 헤더 아래 첫 **가로 구분선**의 y(pt). 조절 행이 펼쳐지면 이 선이 통째로 아래로 밀리므로,
/// 레이아웃이 어느 상태인지 한 숫자로 말해 준다.
///
/// 왜 입력 상자가 아니라 구분선인가: ImageRenderer 는 AppKit 백킹 컨트롤(TextField·Slider)을 똑같이
/// **노란 막대**로 그린다 — 조절 행을 펼치면 슬라이더가 입력 상자보다 위에 노랗게 찍혀, 노랑을 찾으면
/// 접힘/펼침에서 서로 다른 것을 재게 된다(실제로 그렇게 틀렸다). 구분선은 두 상태에서 같은 것 하나다.
@MainActor
private func dividerY(of board: some View) throws -> CGFloat {
    let pixels = try renderPixels(
        board
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            .background(Color.black)
    )
    let left = 12 * pixels.scale
    let right = (Int(TodoBoardAnchor.boardSize.width) - 12) * pixels.scale
    // 30pt 아래부터 본다. 맨 윗줄에는 보드 테두리(흰 0.18)가 폭을 가로질러 있어 구분선과 구별되지 않는다.
    for y in (30 * pixels.scale)..<pixels.height {
        var lit = 0
        for x in left..<right where pixels.rgb(x: x, y: y).g >= 40 { lit += 1 }
        // 내용 폭의 95% 이상이 밝은 줄 = 구분선. 슬라이더 트랙(≈234/276 = 85%)은 안 걸린다.
        if lit >= Int(Double(right - left) * 0.95) {
            return CGFloat(y) / CGFloat(pixels.scale)
        }
    }
    throw TodoBoardRenderError.failed
}

// MARK: - 진짜 창 위에서 재기

/// 런루프를 잠깐 돌린다. 창 순서 조작 → KVO → MainActor 홉 → SwiftUI 갱신 → 그리기까지가
/// 여러 턴에 걸쳐 일어나므로, 곧바로 픽셀을 읽으면 아직 옛 그림이다.
@MainActor
private func spinRunLoop(_ seconds: TimeInterval = 0.4) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 헤더 아래 첫 **가로 구분선**의 y(pt). 조절 행이 펼쳐지면 이 선이 통째로 아래로 밀리므로,
/// 창 안에서 레이아웃이 어느 상태인지 한 숫자로 말해 준다.
///
/// ImageRenderer 가 아니라 `cacheDisplay` 로 읽는다 — 창에 얹힌 **그 뷰 자체**를 봐야
/// 창을 내렸다 올린 뒤의 상태가 잡힌다(ImageRenderer 는 매번 새 뷰를 만들어 씨앗부터 다시 굴린다).
@MainActor
private func dividerY(of view: NSView) -> CGFloat? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    let scale = max(1, rep.pixelsWide / Int(view.bounds.width))
    // 좌우 패딩 12 를 뺀 내용 폭. 구분선은 이 폭을 꽉 채우고, 슬라이더는 퍼센트 라벨 자리만큼 짧다.
    let left = 12 * scale
    let right = (Int(view.bounds.width) - 12) * scale
    // 30pt 아래부터 본다. 맨 윗줄에는 보드 테두리(흰 0.18)가 폭을 가로질러 있어 구분선과 구별되지 않는다.
    for y in (30 * scale)..<rep.pixelsHigh {
        var lit = 0
        for x in left..<right {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            // 임계 0.16: 검정 위 보드 배경은 0.10 근처, 구분선(흰 0.14)은 그 위로 확실히 올라온다.
            if max(color.redComponent, max(color.greenComponent, color.blueComponent)) > 0.16 { lit += 1 }
        }
        // 내용 폭의 95% 이상이 이어서 밝은 줄 = 구분선. 슬라이더 트랙(≈234pt/276pt = 85%)은 안 걸린다.
        if lit >= Int(Double(right - left) * 0.95) {
            return CGFloat(y) / CGFloat(scale)
        }
    }
    return nil
}

// MARK: - 표면 밝기 재기(면이 바탕을 따라가는가)

/// 한 장의 보드에서 잰 **바탕과 표면들의 밝기**(WCAG 상대휘도, 0…1).
///
/// 왜 절대 픽셀이 아니라 이 묶음인가: 이 신고("투명도를 올리면 박스만 더 진해진다")는 두 밝기의 **관계**가
/// 무너진 것이지 어느 한 픽셀 값이 틀린 게 아니다. 바탕이 밝아질 때 표면이 같이 밝아지는지를 보려면
/// 같은 그림에서 둘을 함께 재야 한다.
private struct BoardSurfaceLevels {
    /// 잉크가 하나도 없는 보드 안쪽(= 사용자가 "대부분을 차지하는 컬러"라고 부른 것).
    let board: Double
    /// 입력 상자 채움. **신고된 그 면이다.**
    let field: Double
    /// 이월 캡슐(흰색 0.10) 채움.
    let badge: Double
    /// 완료 표시(체크 원) 전체 — 채움·테두리·글리프가 한 점에 겹쳐 있어 통째로 잰다.
    let doneMark: Double
    /// 되돌리기 배지(accent 0.14) 채움.
    let undo: Double

    /// 표면이 보드 바탕보다 얼마나 어두운가(0 = 같음, 1 = 완전한 검정). **비율**로 재는 이유는
    /// 바탕이 밝아질수록 같은 알파가 더 큰 절대차를 만들기 때문이다 — 절대차로 재면 밝은 바탕에서만
    /// 실패하는 자를 쓰게 된다.
    static func darkening(_ surface: Double, under board: Double) -> Double {
        (board - surface) / board
    }
}

/// 표면을 재는 투명도 지점. **사용자가 실제로 밟는 눈금**(0.05 격자)과 두 끝, 그리고 무릎점을 섞는다 —
/// 무릎점(0.52)은 격자에 없지만 헤일로가 꺼지는 마지막 지점이라 경계 확인에 필요하다.
private let sampledOpacities: [Double] = [
    TodoBoardAppearance.minOpacity,
    0.45,
    TodoBoardAppearance.defaultOpacity - TodoBoardAppearance.step,
    TodoBoardAppearance.blurKnee,
    TodoBoardAppearance.defaultOpacity,
    TodoBoardAppearance.maxOpacity
]

/// 표본 자리(pt). 전부 **보드 한 장에서 같이** 재므로 좌표는 `board(items: mixedItems…)` 레이아웃에 묶여 있다:
/// 헤더 12…36 · 구분선 44 · 입력 상자 53…85 · 목록 91 부터 **31pt 간격**(행 30 + 구분선 1) 5행(…245) ·
/// 캡션 위 가로선 ≈367 · 하단 캡션 ≈374.
///
/// ☠︎ 이 좌표들은 UI 개선(v0.2.25 후보)에서 **따라 옮긴 것**이다. 두 가지가 움직였다:
/// (1) 행 높이 36 → 31(행 30 + 구분선 1)이라 넷째 행의 체크 원이 15pt 올라왔고,
/// (2) 이월 배지가 체크 원 옆에서 **행 오른쪽 끝**으로 갔다.
/// 좌표를 안 옮기면 테스트가 조용히 통과한다 — 표본이 빗나가면 그 자리는 그냥 보드 바탕이고,
/// 바탕은 어느 투명도에서든 자기 자신과 같으므로 "면이 바탕을 따라간다"가 자동으로 참이 된다.
/// 그래서 아래 `probesActuallyLandOnTheirSurfaces` 가 표본이 실제로 면 위에 있는지를 먼저 확인한다.
/// (@MainActor 인 이유는 순전히 배선이다 — 아래 rowPitch 가 뷰의 static 상수를 읽는데 그 뷰가 MainActor 다.
///  상수를 여기 베껴 두면 행 높이를 바꿔도 표본이 안 따라와서, 이 파일이 막으려는 바로 그 상태가 된다.)
@MainActor
private enum BoardSurfaceProbe {
    /// 목록 첫 행의 위쪽 y(pt). 보드 패딩 12 + 헤더 24 + 구분선 17 + 입력 32 + 목록 위 여백 6.
    static let firstRowTop = 91
    /// 행 하나가 잡아먹는 세로 간격 = 행 높이 + 구분선 1px.
    static let rowPitch = Int(TodoBoardRowView.minHeight) + 1

    /// n번째 행(0부터)의 위쪽 y.
    static func rowTop(_ index: Int) -> Int { firstRowTop + rowPitch * index }

    /// 목록이 끝난 뒤의 빈 바탕. 잉크도 헤일로도 닿지 않는 자리다(마지막 행이 245pt 에서 끝난다).
    static let board = (x: 150...250, y: 300...340)
    /// 입력 상자의 **왼쪽 안쪽 띠**. 가운데를 못 쓰는 이유는 ImageRenderer 가 TextField 를 노란 상자로
    /// 그리기 때문이다(렌더 아티팩트). 상자 내용은 좌우 패딩 10pt 안쪽(x≥22)부터라, x 14…20 은
    /// 노란 상자가 아니라 채움 도형이다. ⚠︎ 그래도 노란 상자의 그림자가 옆으로 번져 오므로 이 값은
    /// 실제 앱보다 **어둡게** 나온다 — 판정에 유리한 쪽이 아니라 불리한 쪽으로 치우친 표본이다.
    static let field = (x: 14...20, y: 56...80)
    /// 이월 캡슐(첫 행)의 **오른쪽 끝 쪽** 띠. 배지가 행 오른쪽으로 옮겨 갔고, 그 오른쪽에는 ✕ 자리(16pt)가
    /// 늘 비워져 있다. 캡슐이 작아 글자 헤일로를 완전히 피할 수는 없어 글자 **위쪽** 띠를 고른다.
    ///
    /// ⚠︎ y 를 옛 좌표(99…102)에서 두 칸 올린 이유는 캡슐이 옮겨 가서가 아니라 **행이 낮아져서**다.
    /// 행 높이가 34→30 이 되며 안쪽 내용(29pt)이 가운데 정렬로 2.5pt → 0.5pt 만 내려오게 됐고,
    /// 그만큼 캡슐 전체가 위로 올라왔다(실측: 캡슐 98…112, 글자 잉크 102…109).
    /// 옛 띠를 그대로 두면 글자 잉크와 그 헤일로를 재게 되어, 재려던 것(캡슐 **채움**이 바탕을 따라 옅어지는가)
    /// 대신 "글자 그림자가 얼마나 진한가"를 재게 된다.
    ///
    /// 새 띠는 옛 띠의 **구성**(위 1pt 는 맨 바탕, 아래 3pt 는 캡슐 채움)을 그대로 옮긴 것이다. 그 증거로
    /// 검은 바탕에서 잰 캡슐/바탕 비가 이 변경 전후로 거의 같다: 기본값 1.582 → 1.635, 하한 1.372 → 1.361.
    /// 즉 캡슐 자체는 한 톨도 안 바뀌었고 표본만 따라 옮겼다(띠를 1pt 만 올리면 채움만 재게 되어 같은 비가
    /// 1.816 / 1.464 로 나온다 — 숫자가 달라지는 건 화면이 바뀌어서가 아니라 자를 바꿔서다).
    static let badge = (x: 236...258, y: (rowTop(0) + 6)...(rowTop(0) + 10))
    /// 완료 표시(넷째 행)의 체크 원 전체.
    static let doneMark = (x: 13...27, y: (rowTop(3) + 8)...(rowTop(3) + 20))
    /// 되돌리기 배지(삭제 대기 행)의 오른쪽 캡슐. 첫 행을 삭제 대기로 두고 잰다.
    static let undo = (x: 232...276, y: (rowTop(0) + 9)...(rowTop(0) + 25))
}

@MainActor
private func boardSurfaceLevels(opacity: Double, backdrop: Color) throws -> BoardSurfaceLevels {
    func levels(of view: some View) throws -> RenderedPixels {
        try renderPixels(
            ZStack {
                backdrop
                view.frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
            }
            .frame(width: TodoBoardAnchor.boardSize.width, height: TodoBoardAnchor.boardSize.height)
        )
    }
    let normal = try levels(of: board(items: mixedItems, oldItems: [], opacity: opacity))
    // 되돌리기 배지는 삭제 대기 행에만 있다. 같은 보드에 둘 다 띄울 수 없어 한 장 더 그린다.
    let deleting = try levels(
        of: board(items: mixedItems, oldItems: [], opacity: opacity, pendingDeleteID: mixedItems[0].id)
    )
    return BoardSurfaceLevels(
        board: normal.meanLevel(in: BoardSurfaceProbe.board),
        field: normal.meanLevel(in: BoardSurfaceProbe.field),
        badge: normal.meanLevel(in: BoardSurfaceProbe.badge),
        doneMark: normal.meanLevel(in: BoardSurfaceProbe.doneMark),
        undo: deleting.meanLevel(in: BoardSurfaceProbe.undo)
    )
}

extension RenderedPixels {
    /// pt 단위 사각형 안의 평균 상대휘도. 한 점만 읽으면 안티에일리어싱·헤일로 기울기 위에 판정이 서게 되어
    /// 좌표 1pt 차이로 결과가 바뀐다.
    func meanLevel(in rect: (x: ClosedRange<Int>, y: ClosedRange<Int>)) -> Double {
        var total = 0.0
        var count = 0
        for y in (rect.y.lowerBound * scale)...(rect.y.upperBound * scale) {
            for x in (rect.x.lowerBound * scale)...(rect.x.upperBound * scale) {
                guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                let p = rgb(x: x, y: y)
                total += Double(p.r + p.g + p.b) / (3 * 255)
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }
}

/// WCAG 2.x 상대 휘도.
private func relativeLuminance(_ p: (r: Int, g: Int, b: Int)) -> Double {
    func channel(_ v: Int) -> Double {
        let c = Double(v) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(p.r) + 0.7152 * channel(p.g) + 0.0722 * channel(p.b)
}

private func contrastRatio(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Double {
    let la = relativeLuminance(a), lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
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


