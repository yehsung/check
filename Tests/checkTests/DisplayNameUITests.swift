import AppKit
import SwiftUI
import Testing
@testable import check

// 별명(표시명) 인라인 편집 UI 회귀. 이 파일이 지키는 것은 하나다 —
// **편집 행이 팀 목록 안에서 같은 58pt 를 쓰고, 그래서 창 높이 예산이 하나도 움직이지 않는다.**
// 픽셀 절대값은 단언하지 않는다(상대 비교 + 상수와의 비교만).

// 헬퍼는 기존 렌더 테스트 파일에서 **복사**한다. 그쪽 헬퍼는 전부 private(파일 스코프)이라 공용화하려면
// 남의 파일을 고쳐야 하고, 병렬 구현 중에 그건 작업 유실로 이어진다.

/// makeTeamStoreLocal 이 세우는 세션의 userID. 팀원 목록의 '내 행' 판정(isMe)이 이 값과 같아야 한다.
private let myUserID = "00000000-0000-0000-0000-000000000002"

// MARK: - 순수 폭 예산

@Test
func myRowReservesBadgeWidthEvenWithoutHover() {
    // 별명 상한 12자를 정당화하는 유일한 근거가 이 계산이다. 상한을 올리거나 배지를 하나 더 세우면
    // 이 테스트가 **먼저** 빨개져야 한다 — 화면에서 이름이 잘리는 걸 사람이 발견하기 전에.
    #expect(MemberRowNameWidthBudget.fittingKoreanGlyphs(hasEditBadge: true) >= WorkTimerStore.displayNameMaxLength)
    // 배지는 hover 와 무관하게 늘 자리를 차지한다(=남의 행보다 좁다). 이 부등호가 뒤집히면
    // 배지가 hover 때만 자리를 만드는 구현으로 되돌아간 것이고, 그러면 마우스가 지날 때마다 이름이 밀린다.
    #expect(
        MemberRowNameWidthBudget.fittingKoreanGlyphs(hasEditBadge: false)
            > MemberRowNameWidthBudget.fittingKoreanGlyphs(hasEditBadge: true)
    )
    // 예산이 음수로 뒤집히면(칩 문구가 길어지는 등) 0 글자를 돌려주며 조용히 통과하는 일이 없게 못 박는다.
    #expect(MemberRowNameWidthBudget.nameWidth(hasEditBadge: true) > 0)
}

// MARK: - 편집 행이 실제로 그려지는가(아래 높이 비교가 공회전하지 않게)

@MainActor
@Test
func nameEditorRowIsActuallyRendered() throws {
    // 이걸 먼저 못 박지 않으면 아래 높이 비교가 '같은 그림 둘'을 비교하며 조용히 통과한다.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let normal = try renderPNG(CheckMenuView(store: editorStore(now: now)))
    let editing = try renderPNG(CheckMenuView(store: editorStore(now: now), previewEditingDisplayName: true))
    #expect(normal != editing)
}

@MainActor
@Test
func editBadgeAppearsOnlyOnMyRow() throws {
    // 연필 배지는 내 행에만 붙는다(진입점이 하나뿐이라는 계약의 시각적 실증).
    // 같은 팀원 목록을 두 번 그리되 세션 userID 만 바꾼다 — 아무도 내가 아니면 배지가 없어 그림이 달라야 한다.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let mine = try renderPNG(CheckMenuView(store: editorStore(now: now)))

    let strangerStore = editorStore(now: now)
    strangerStore.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil,
        userID: "00000000-0000-0000-0000-0000000000ff"
    )
    let stranger = try renderPNG(CheckMenuView(store: strangerStore))
    #expect(mine != stranger)
}

// MARK: - 창 높이 예산 무영향(이 항목의 핵심 주장)

@MainActor
@Test
func nameEditorRowKeepsPopoverHeight() throws {
    // 편집 행은 내 행을 **대체**하고 같은 memberRowHeight 로 고정된다 → 목록 총 높이·창 높이가 불변.
    // 절대값이 아니라 두 렌더의 상대 비교다(픽셀 절대값 단언 금지 규약).
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let normal = try #require(renderedPixelHeight(CheckMenuView(store: editorStore(now: now))))
    let editing = try #require(
        renderedPixelHeight(CheckMenuView(store: editorStore(now: now), previewEditingDisplayName: true))
    )
    #expect(normal == editing)
}

@MainActor
@Test
func nameEditorRowStaysUnderHeightCap() throws {
    // 최악 조합: 스크롤 상한을 넘는 팀원 수 + 새 버전 배너 + 편집 행. 기존 최악 조합 테스트의 (a)~(e)는
    // 손대지 않는다 — 그쪽 픽스처를 바꾸면 이미 검증된 조합의 측정값이 함께 흔들린다.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let store = editorStore(now: now, memberCount: 8)
    let pixels = try #require(
        renderedPixelHeight(CheckMenuView(store: store, previewUpdateBanner: true, previewEditingDisplayName: true))
    )
    // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
    #expect(Double(pixels) / 2.0 <= 700.0)
}

@MainActor
@Test
func displayNameEditorRowFitsMemberRowHeight() throws {
    // 편집 행 자연 높이가 58pt 를 넘으면 호출부의 .frame(height:)가 내용을 눌러 캡션이 잘린다.
    // 픽셀 절대값이 아니라 **상수와의 비교**다.
    let row = editorRow(notice: "\(WorkTimerStore.displayNameMaxLength)자까지 · 다른 사람과 겹칠 수 없어요", isError: false)
    // 폭 268 = 팀 카드 콘텐츠 292 에서 좌우 여유를 조금 뺀 값(행이 실제로 놓이는 폭보다 좁게 잡아 보수적으로 본다).
    let pixels = try #require(renderedPixelHeight(row, width: 268))
    #expect(Double(pixels) / 2.0 <= Double(CheckTheme.memberRowHeight))
}

@MainActor
@Test
func editorNoticeErrorFlagChangesRendering() throws {
    // 쿨타임 안내(회색)와 실패 사유(danger)가 같은 색으로 그려지면 사용자는 "일주일에 한 번" 안내를
    // 실패로 읽는다. 두 렌더가 실제로 달라야 그 분기가 화면에 존재한다는 뜻이다.
    let errorPNG = try renderPNG(editorRow(notice: "이미 쓰고 있는 별명이에요", isError: true), width: 268)
    let plainPNG = try renderPNG(editorRow(notice: "이미 쓰고 있는 별명이에요", isError: false), width: 268)
    #expect(errorPNG != plainPNG)
}

// MARK: - 육안 확인 덤프(env 지정 시에만)

@MainActor
@Test
func dumpDisplayNameEditorSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_DISPLAY_NAME_SNAPSHOT_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

    func dump(_ row: DisplayNameEditorRow, _ name: String) throws {
        let png = try renderPNG(row.padding(12).background(CheckTheme.panel), width: 292)
        try png.write(to: base.appendingPathComponent(name))
    }

    try dump(
        editorRow(notice: "\(WorkTimerStore.displayNameMaxLength)자까지 · 다른 사람과 겹칠 수 없어요", isError: false),
        "display-name-editor-default.png"
    )
    try dump(
        editorRow(notice: "일주일에 한 번만 바꿀 수 있어요 · 8월 11일부터", isError: false, isLocked: true),
        "display-name-editor-cooldown.png"
    )
    try dump(editorRow(notice: "이미 쓰고 있는 별명이에요", isError: true), "display-name-editor-error.png")

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try renderPNG(CheckMenuView(store: editorStore(now: now), previewEditingDisplayName: true))
        .write(to: base.appendingPathComponent("display-name-editor-popover.png"))
    try renderPNG(CheckMenuView(store: editorStore(now: now)))
        .write(to: base.appendingPathComponent("display-name-badge-popover.png"))
}

// MARK: - 픽스처

/// 편집 행 단독 렌더용 픽스처. 입력은 .constant 로 고정한다 — 렌더 테스트는 타이핑을 하지 않으므로
/// 진짜 Binding 이 필요 없고, 상태를 두면 렌더 간 값이 남아 비교가 흔들린다.
@MainActor
private func editorRow(notice: String, isError: Bool, isLocked: Bool = false) -> DisplayNameEditorRow {
    DisplayNameEditorRow(
        avatarName: "영식",
        text: .constant("영식"),
        isLocked: isLocked,
        isSaving: false,
        notice: notice,
        isNoticeError: isError,
        onSave: {},
        onCancel: {}
    )
}

/// 별명 편집을 그릴 수 있는 팀 스토어. **내 행이 실제로 존재해야** 한다 —
/// 기존 렌더 픽스처(steadyMembers)는 id 가 "aaaaaaaa-…" 라 어떤 멤버도 내가 아니고, 그대로 쓰면
/// previewEditingDisplayName 을 켜도 isMe 분기가 열리지 않아 편집 행이 아예 안 그려진다.
@MainActor
private func editorStore(now: Date, memberCount: Int = 3) -> WorkTimerStore {
    let store = makeTeamStoreLocal(members: steadyMembersIncludingMe(count: memberCount), now: now)
    store.displayNameDraft = "영식"
    return store
}

/// 첫 멤버의 id 를 스토어의 session.userID 와 **같게** 만든 표본.
@MainActor
private func steadyMembersIncludingMe(count: Int) -> [TeamMemberStatus] {
    var members = steadyMembersLocal(count: max(1, count))
    members[0] = TeamMemberStatus(
        id: myUserID,
        name: "나",
        status: .offWork,
        updatedAt: nil,
        currentSessionStartedAt: nil,
        weeklyDurationSeconds: 3_600
    )
    return members
}

/// 헤더 높이가 팀원 수와 무관하게 일정하도록 만든 N인 표본(전원 근무종료·고정 주간 1h).
@MainActor
private func steadyMembersLocal(count: Int) -> [TeamMemberStatus] {
    (0..<count).map { i in
        TeamMemberStatus(
            id: "aaaaaaaa-0000-0000-0000-\(String(format: "%012d", i))",
            name: "멤버\(i)",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 3_600
        )
    }
}

@MainActor
private func makeTeamStoreLocal(members: [TeamMemberStatus], now: Date) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다
    // (고정 displayNow 보존 · 티커 미발사).
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: myUserID)
    store.displayNow = now
    store.teamMembers = members
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    return store
}

@MainActor
private func renderPNG(_ view: some View, width: CGFloat = 340) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw DisplayNameRenderError.failed
    }
    return pngData
}

@MainActor
private func renderedPixelHeight(_ view: some View, width: CGFloat = 340) -> Int? {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return nil
    }
    return bitmap.pixelsHigh
}

private enum DisplayNameRenderError: Error {
    case failed
}

private func isolatedRenderDefaults() -> UserDefaults {
    let suiteName = "check-display-name-ui-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 렌더 테스트용 격리 토큰 스토어(빈 임시 홈 + 격리 defaults). CheckMenuView 의 .task 갱신 루프가
/// ImageRenderer 렌더 중에 돌더라도 실홈 스캔이나 테스트 러너 .standard 오염이 일어나지 않는다.
@MainActor
private func inertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: isolatedRenderDefaults(),
        homeDirectory: tmp.appendingPathComponent("check-display-name-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-display-name-token-cache-\(id).json", isDirectory: false)
    )
}
