import AppKit
import SwiftUI
import Testing
@testable import check

// 별명(표시명) UI 회귀.
//
// ⚠️ 전제가 한 번 바뀌었다. 예전 이 파일이 지키던 것은 "편집 행이 팀 목록 안에서 같은 58pt 를 쓴다"였다.
// 별명 편집이 **설정 창(CheckSettingsView/DisplayNameSettingsRow)으로 통째로 이사**하면서 팝오버에는
// 편집 진입(연필 배지)도, 인라인 편집 행도 남지 않았다. 지키는 계약은 셋이다:
//   · 팝오버 팀 목록에 **이름은 계속 보인다**(그리고 내 행은 남의 행과 다르게 보인다).
//   · 이름이 길어져도 **행 높이·창 높이 예산이 움직이지 않는다**(58pt 고정).
//   · 설정 창에서 **쿨타임 안내와 실패 사유가 같은 색으로 그려지지 않는다**(회색 vs danger).
// 픽셀 절대값은 여전히 단언하지 않는다(상대 비교 + 상수와의 비교만).
//
// v0.2.32 정리 기록: 팝오버 인라인 편집 뷰 `DisplayNameEditorRow`(CheckComponents.swift)를 지웠다.
// 소스 호출부가 0이 된 뒤로 **이 파일의 세 테스트만이 그 뷰의 유일한 사용처**였고, 그건 테스트가
// 제품이 아니라 자기 자신을 지키고 있었다는 뜻이다. 그 셋의 처리는 이랬다:
//   · 높이 수납(자연 높이 ≤ memberRowHeight 58pt) — **계약이 함께 죽었다.** 그 58pt 는 팀 목록 행
//     고정 높이였고, 설정 창 행은 그 예산 안에 살지 않는다(창이 세로로 늘어난다). 그래서 지웠다.
//   · 안내 색 분기(쿨타임 회색 / 실패 danger) — **계약은 살아 있다.** 새 집(설정 창)에서 같은 것을
//     재는 렌더 비교로 옮겼다. 옛 뷰를 지우며 이 커버리지까지 잃었으면, "일주일에 한 번" 안내를
//     빨갛게 칠해 사용자가 실패로 읽는 회귀가 무방비가 됐다.
//   · 육안 덤프 — 대상만 새 집으로 갈아 끼웠다(세 상태를 눈으로 보는 도구는 계속 필요하다).

// 헬퍼는 기존 렌더 테스트 파일에서 **복사**한다. 그쪽 헬퍼는 전부 private(파일 스코프)이라 공용화하려면
// 남의 파일을 고쳐야 하고, 병렬 구현 중에 그건 작업 유실로 이어진다.

/// makeTeamStoreLocal 이 세우는 세션의 userID. 팀원 목록의 '내 행' 판정(isMe)이 이 값과 같아야 한다.
private let myUserID = "00000000-0000-0000-0000-000000000002"

// MARK: - 순수 폭 예산

@Test
func myRowReservesBadgeWidthEvenWithoutHover() {
    // 별명 상한 12자를 정당화하는 유일한 근거가 이 계산이다. 상한을 올리거나 칩 문구를 늘리면
    // 이 테스트가 **먼저** 빨개져야 한다 — 화면에서 이름이 잘리는 걸 사람이 발견하기 전에.
    //
    // 지금 실제로 그려지는 경로는 hasEditBadge: false 하나다(팝오버는 어떤 행에도 onBeginEditName 을
    // 넘기지 않으므로 연필 배지가 뜨지 않는다 — 아래 myRowStillLooksDifferentFromEveryoneElses 가
    // 소스로 못 박는다). 그래서 **그 경로부터** 잰다.
    #expect(MemberRowNameWidthBudget.fittingKoreanGlyphs(hasEditBadge: false) >= WorkTimerStore.displayNameMaxLength)
    // hasEditBadge: true 는 지금 도달하지 않는 계산이지만 지운다: TeamMemberRow 는 onBeginEditName 을
    // 파라미터로 계속 들고 있고(배지 뷰도 그대로다), 누군가 그 인자를 다시 넘기는 순간 이름 폭이 22pt
    // 줄어든다. 그 순간에도 12자가 들어가는지를 **미리** 재 두는 것이 이 줄의 값이다 — 배지를 되살린
    // 다음에 잘림을 발견하면 이미 사용자가 먼저 본 뒤다.
    #expect(MemberRowNameWidthBudget.fittingKoreanGlyphs(hasEditBadge: true) >= WorkTimerStore.displayNameMaxLength)
    // 배지가 서면 늘 자리를 차지한다(=남의 행보다 좁다). 이 부등호가 뒤집히면 배지가 hover 때만
    // 자리를 만드는 구현으로 되돌아간 것이고, 그러면 마우스가 지날 때마다 이름이 밀린다.
    #expect(
        MemberRowNameWidthBudget.fittingKoreanGlyphs(hasEditBadge: false)
            > MemberRowNameWidthBudget.fittingKoreanGlyphs(hasEditBadge: true)
    )
    // 예산이 음수로 뒤집히면(칩 문구가 길어지는 등) 0 글자를 돌려주며 조용히 통과하는 일이 없게 못 박는다.
    #expect(MemberRowNameWidthBudget.nameWidth(hasEditBadge: true) > 0)
}

// MARK: - 이름이 실제로 그려지는가(아래 높이 비교가 공회전하지 않게)

@MainActor
@Test
func myNameIsStillDrawnInTheTeamList() throws {
    // 예전 이 자리는 CheckMenuView 의 미리보기 플래그(편집 행을 펼친 상태로 그리던 것) on/off 렌더가
    // 달라야 한다고 했다. 편집 행이 설정 창으로 이사한 뒤 그 플래그는 **아무것도 그리지 않게** 됐고,
    // 그대로 뒀다면 같은 그림 둘을 비교하며 조용히 통과했을 자리다(실제로 그렇게 빨개졌다). 플래그는
    // v0.2.32 에 소스에서 지웠다. 남은 계약으로 판정을 바꾼다 — **이름은 계속 보인다.**
    // 이름만 바꾼 두 렌더가 달라야 이름이 화면에 실재한다는 뜻이고, 아래 높이 비교도 그제야 의미가 생긴다.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let mine = try renderPNG(CheckMenuView(store: editorStore(now: now, myName: "영식")))
    let renamed = try renderPNG(CheckMenuView(store: editorStore(now: now, myName: "다른이름")))
    #expect(mine != renamed)
}

@MainActor
@Test
func myRowStillLooksDifferentFromEveryoneElses() throws {
    // ⚠️ 이 테스트의 옛 이름은 editBadgeAppearsOnlyOnMyRow 였고, 근거는 "연필 배지는 내 행에만 붙는다"였다.
    // 배지는 사라졌다 — 팝오버는 이제 MemberRow 에 onBeginEditName 을 **아무 행에도** 넘기지 않는다.
    // 그런데도 이 렌더 비교는 초록이었다: 그림을 가르는 건 배지가 아니라 isMe 강조(내 행 표시)였기 때문이다.
    // 이름을 그 사실에 맞춘다 — 없는 것을 지키는 척하던 테스트는 다음 번엔 아무도 못 믿는다.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let mine = try renderPNG(CheckMenuView(store: editorStore(now: now)))

    let strangerStore = editorStore(now: now)
    strangerStore.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil,
        userID: "00000000-0000-0000-0000-0000000000ff"
    )
    let stranger = try renderPNG(CheckMenuView(store: strangerStore))
    #expect(mine != stranger)

    // 편집 진입은 팝오버 어디에도 없다(설정 창이 별명의 유일한 거처다). 배지를 되살리는 순간
    // "별명을 고치는 자리가 둘"이 되고, 둘 중 하나는 쿨타임/중복 검증을 빠뜨린 쪽이 된다.
    let source = try String(contentsOf: checkMenuViewSourceURLForDisplayNameTests(), encoding: .utf8)
    #expect(!source.contains("onBeginEditName:"))
}

// MARK: - 창 높이 예산 무영향(이 항목의 핵심 주장)

@MainActor
@Test
func longNamesDoNotMoveThePopoverHeight() throws {
    // 옛 주장("편집 행이 내 행을 대체하고 같은 memberRowHeight 를 쓴다")의 편집 행이 사라졌으므로,
    // 같은 예산을 지금 실제로 흔들 수 있는 값으로 다시 잰다 — **상한 길이 별명**이다.
    // 이름이 길어져 두 줄이 되거나 minimumScaleFactor 대신 줄바꿈이 나면 행이 부풀고 창이 자란다.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let short = try #require(renderedPixelHeight(CheckMenuView(store: editorStore(now: now, myName: "나"))))
    let longest = try #require(
        renderedPixelHeight(
            CheckMenuView(
                store: editorStore(now: now, myName: String(repeating: "밝", count: WorkTimerStore.displayNameMaxLength))
            )
        )
    )
    #expect(short == longest)
}

@MainActor
@Test
func longestNameStaysUnderHeightCap() throws {
    // 최악 조합: 스크롤 상한을 넘는 팀원 수 + 새 버전 배너 + 상한 길이 별명. 기존 최악 조합 테스트의
    // (a)~(e)는 손대지 않는다 — 그쪽 픽스처를 바꾸면 이미 검증된 조합의 측정값이 함께 흔들린다.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let store = editorStore(
        now: now,
        memberCount: 8,
        myName: String(repeating: "밝", count: WorkTimerStore.displayNameMaxLength)
    )
    let pixels = try #require(renderedPixelHeight(CheckMenuView(store: store, previewUpdateBanner: true)))
    // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
    #expect(Double(pixels) / 2.0 <= 700.0)
}

// MARK: - 안내 색 분기(설정 창)

@MainActor
@Test
func displayNameNoticeErrorFlagChangesRenderingInTheSettingsWindow() throws {
    // 쿨타임 안내(회색)와 실패 사유(danger)가 같은 색으로 그려지면 사용자는 "일주일에 한 번" 안내를
    // 실패로 읽는다. 두 렌더가 실제로 달라야 그 분기가 화면에 존재한다는 뜻이다.
    //
    // ⚠️ 문구는 **같게 두고 플래그만 뒤집는다.** 문구까지 바꾸면 글자 모양 차이로 그림이 달라져,
    // 색 분기가 통째로 사라져도 초록으로 통과한다(뷰가 notice != nil 로 색을 추측하던 시절의 그 버그다).
    let errorPNG = try renderPNG(settingsView(notice: "이미 쓰고 있는 별명이에요", isError: true), width: settingsWidth)
    let plainPNG = try renderPNG(settingsView(notice: "이미 쓰고 있는 별명이에요", isError: false), width: settingsWidth)
    #expect(errorPNG != plainPNG)

    // 같은 플래그로 두 번 그리면 **같은 그림**이어야 한다. 이 줄이 없으면 위 != 는 색 분기가 아니라
    // 픽스처의 잡음(스토어마다 새로 만드는 격리 defaults·토큰 홈 등)으로도 초록이 될 수 있다 —
    // 그러면 색 분기를 통째로 걷어내도 이 테스트는 계속 통과한다.
    let plainAgain = try renderPNG(settingsView(notice: "이미 쓰고 있는 별명이에요", isError: false), width: settingsWidth)
    #expect(plainPNG == plainAgain, "같은 상태를 두 번 그렸는데 그림이 다르다 — 픽스처가 결정적이지 않다")
}

// MARK: - 육안 확인 덤프(env 지정 시에만)

@MainActor
@Test
func dumpDisplayNameSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_DISPLAY_NAME_SNAPSHOT_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

    func dump(_ view: some View, _ name: String) throws {
        try renderPNG(view, width: settingsWidth).write(to: base.appendingPathComponent(name))
    }

    // 안내 한 줄이 가지는 세 얼굴(도움말·쿨타임·실패). 셋을 나란히 눈으로 봐야 "쿨타임이 실패처럼
    // 보이지 않는가"를 사람이 판정할 수 있다 — 렌더 비교는 '다르다'까지만 말해 준다.
    try dump(settingsView(notice: nil, isError: false), "display-name-settings-default.png")
    try dump(
        // 미래 시각이어야 한다 — 뷰가 onAppear 에서 refreshDisplayNameLock() 으로 잠금을 재평가하므로,
        // 과거 날짜를 주면 잠금이 그 자리에서 풀려 쿨타임 대신 기본 도움말이 찍힌다.
        settingsView(notice: nil, isError: false, availableAt: Date(timeIntervalSince1970: 4_102_444_800)),
        "display-name-settings-cooldown.png"
    )
    try dump(settingsView(notice: "이미 쓰고 있는 별명이에요", isError: true), "display-name-settings-error.png")

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try renderPNG(CheckMenuView(store: editorStore(now: now)))
        .write(to: base.appendingPathComponent("display-name-team-list.png"))
}

// MARK: - 픽스처

/// 설정 창 렌더 폭. 창 배선 쪽이 참고하는 값과 같은 상수를 쓴다(여기서 340 같은 팝오버 폭을 쓰면
/// 설명 한 줄이 접혀 두 줄이 되고, 그 줄바꿈이 색 분기보다 먼저 그림을 흔든다).
@MainActor
private var settingsWidth: CGFloat { CheckSettingsView.preferredWidth }

/// 별명 행이 특정 안내 상태로 그려진 설정 창.
/// - notice: 스토어가 세운 사유(중복/길이). nil 이면 뷰가 기본 도움말이나 쿨타임 문구를 고른다.
/// - availableAt: 주면 잠금(쿨타임) 상태로 그린다.
///
/// launchAtLoginSeed 를 **반드시** 준다 — 안 주면 렌더가 실제 로그인 항목(SMAppService)을 읽어
/// 테스트가 이 맥의 시스템 상태에 의존하게 된다.
@MainActor
private func settingsView(notice: String?, isError: Bool, availableAt: Date? = nil) -> CheckSettingsView {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: myUserID)
    store.displayName = "영식"
    store.displayNameNotice = notice
    store.isDisplayNameNoticeError = isError
    if let availableAt {
        store.displayNameAvailableAt = availableAt
        store.isDisplayNameLocked = true
    }
    return CheckSettingsView(store: store, launchAtLoginSeed: false)
}

/// 내 행이 실제로 들어 있는 팀 스토어. **내 행이 존재해야** 한다 —
/// 기존 렌더 픽스처(steadyMembers)는 id 가 "aaaaaaaa-…" 라 어떤 멤버도 내가 아니고,
/// 그대로 쓰면 isMe 분기가 한 번도 열리지 않아 이 파일의 비교가 전부 공회전한다.
@MainActor
private func editorStore(now: Date, memberCount: Int = 3, myName: String = "나") -> WorkTimerStore {
    let store = makeTeamStoreLocal(members: steadyMembersIncludingMe(count: memberCount, myName: myName), now: now)
    store.displayNameDraft = myName
    return store
}

/// 첫 멤버의 id 를 스토어의 session.userID 와 **같게** 만든 표본.
@MainActor
private func steadyMembersIncludingMe(count: Int, myName: String = "나") -> [TeamMemberStatus] {
    var members = steadyMembersLocal(count: max(1, count))
    members[0] = TeamMemberStatus(
        id: myUserID,
        name: myName,
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

/// `Sources/check/CheckMenuView.swift` 경로. 렌더 테스트 파일의 같은 이름 헬퍼는 그쪽 파일 스코프
/// private 이라 여기서 못 쓴다(공용화하려면 남의 파일을 고쳐야 하고, 그건 병렬 작업에서 유실로 이어진다).
private func checkMenuViewSourceURLForDisplayNameTests() -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/DisplayNameUITests.swift
        .deletingLastPathComponent()          // Tests/checkTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // (repo root)
        .appendingPathComponent("Sources/check/CheckMenuView.swift")
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
