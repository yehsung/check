import AppKit
import SwiftUI
import Testing
@testable import check

@MainActor
@Test
func checkMenuViewRendersSnapshot() throws {
    let store = WorkTimerStore(environment: [
        "CHECK_SUPABASE_ANON_KEY": "local-test-key"
    ], defaults: isolatedRenderDefaults())
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    // 팀이 확정돼 있어야(currentTeamID != nil) 무소속 패널이 아닌 메인 팀 화면이 그려진다.
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamMembers = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .working,
            updatedAt: nil,
            currentSessionStartedAt: Date(timeIntervalSinceNow: -3_600),
            weeklyDurationSeconds: 14_400
        ),
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000001",
            name: "yesung",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 7_200
        )
    ]
    let view = CheckMenuView(store: store)
        .frame(width: 340)
        .fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("CheckMenuView should render to a PNG snapshot")
        return
    }

    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_RENDER_SNAPSHOT_PATH"] {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersCompletedWeeklyGoalSnapshot() throws {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamMembers = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .working,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 62 * 60 * 60
        )
    ]
    let view = CheckMenuView(store: store)
        .frame(width: 340)
        .fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("Completed CheckMenuView should render to a PNG snapshot")
        return
    }

    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_COMPLETE_RENDER_SNAPSHOT_PATH"] {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersFortyHourGoalSnapshot() throws {
    // 팀 목표 40시간(teams.weekly_goal_hours=40 → store.teamGoalSeconds)이 게이지 분모로 반영된 메인 화면.
    // 게이지 표기가 "/ 40시간 00분"으로 나오는지(기본 60시간이 아니라) 육안 확인용.
    let now = Date()
    let members = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 12 * 3600,
            avatarURL: CheckMascotAssets.url(for: .neutral)
        ),
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000001",
            name: "민수",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 8 * 3600
        )
    ]
    let store = makeTeamStore(members: members, now: now)
    // 목표시간은 store.teamGoalSeconds 로만 결정된다(앱엔 목표 입력 UI 없음). 40시간으로 고정해 렌더한다.
    store.teamGoalSeconds = 40 * 3600

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_GOAL_40H_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersLoginModeSnapshot() throws {
    // 기본 진입 화면 = 로그인 모드. 별명 필드가 없어야 하고, 하단 "가입하기" 링크로만 가입에 접근한다.
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.email = "member@example.com"
    store.password = "team-password"

    let view = CheckMenuView(store: store)
        .frame(width: 340)
        .fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("Login-mode CheckMenuView should render to a PNG snapshot")
        return
    }

    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_LOGIN_MODE_RENDER_SNAPSHOT_PATH"] {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersSignupNicknameSnapshot() throws {
    // 가입 모드 렌더: 별명 필드 + "이미 계정이 있나요? 로그인" 복귀 링크가 보여야 한다.
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.displayName = "영식"
    store.email = "member@example.com"
    store.password = "team-password"

    let view = CheckMenuView(store: store, initialAuthMode: .signUp)
        .frame(width: 340)
        .fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("Signup CheckMenuView should render to a PNG snapshot")
        return
    }

    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_SIGNUP_RENDER_SNAPSHOT_PATH"] {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersLoginErrorSnapshot() throws {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.email = "member@example.com"
    store.password = "wrong-password"
    store.syncMessage = "로그인 정보 오류"

    let view = CheckMenuView(store: store)
        .frame(width: 340)
        .fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("Login-error CheckMenuView should render to a PNG snapshot")
        return
    }

    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_LOGIN_ERROR_RENDER_SNAPSHOT_PATH"] {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersASCIIWarningSnapshot() throws {
    // 비밀번호 필드에 "영어 문자만 입력할 수 있어요" 안내가 떠 있는 상태의 로그인 패널.
    // 캡션/테두리 강조가 340pt 폭 안에서 잘림·밀림 없이 수납되는지 확인한다.
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.email = "member@example.com"
    store.password = "team-password"

    let view = CheckMenuView(store: store, previewASCIIWarning: true)
        .frame(width: 340)
        .fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("ASCII-warning CheckMenuView should render to a PNG snapshot")
        return
    }

    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_ASCII_WARNING_SNAPSHOT_PATH"] {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func menuBarStatusLabelFitsWithinBarHeight() throws {
    // 메뉴바(높이 ~22pt)에 라벨을 얹었을 때 캐릭터가 바 높이 안에 온전히 들어가야 한다.
    for (snapshot, envKey) in [
        (WorkStatusSnapshot(status: .working, elapsedSeconds: 3_661), "CHECK_MENUBAR_WORKING_SNAPSHOT_PATH"),
        (WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0), "CHECK_MENUBAR_OFFWORK_SNAPSHOT_PATH")
    ] {
        let view = MenuBarStatusLabel(snapshot: snapshot)
            .frame(height: 22)
            .padding(.horizontal, 6)
            .background(Color(red: 0.12, green: 0.13, blue: 0.17))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 4

        guard let image = renderer.nsImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            Issue.record("MenuBarStatusLabel should render to a PNG snapshot")
            return
        }

        // 라벨 전체 높이가 22pt(바 높이)를 넘지 않아야 한다 — 캐릭터 잘림 회귀 방지.
        #expect(image.size.height <= 22 + 0.5)
        #expect(image.size.width > 0)
        if let path = ProcessInfo.processInfo.environment[envKey] {
            try pngData.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - A2: 콘텐츠 맞춤(동적) 창 높이 — 상태별 콘텐츠에 맞게 자라되 상한(≤700pt) 안에 머문다

@MainActor
@Test
func windowHeightAdaptsToContentWithinCap() throws {
    // 창 높이는 이제 상태별 콘텐츠에 맞춰 변한다(고정 상수 폐기). 다음을 검증한다:
    //  (a) 로그인(짧은 폼) < 메인(3명)
    //  (b) 메인(2명) < 메인(5명) — 팀원 수에 비례해 성장
    //  (c) 메인(10명) == 메인(7명) — maxVisibleRows(7) 스크롤 상한에서 높이 고정
    //  (d) 모든 상태 ≤ 700pt 상한
    // 픽셀 높이는 ImageRenderer 렌더 결과에서 읽는다(scale 2 → 포인트 높이 = 픽셀/2).
    let now = Date()

    // 헤더 높이가 팀원 수와 무관하게 일정한 표본으로 리스트 성장/상한만 순수 비교한다(steadyMembers).
    func mainHeight(_ count: Int) throws -> Int {
        try #require(renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: steadyMembers(count: count), now: now))))
    }

    let login = try #require(renderedPixelHeight(CheckMenuView(store: makeLoginStore(syncMessage: "로그인 필요"))))
    let main2 = try mainHeight(2)
    let main3 = try mainHeight(3)
    let main5 = try mainHeight(5)
    let main7 = try mainHeight(7)
    let main10 = try mainHeight(10)

    // (a) 로그인 < 메인(3명): 로그인 폼이 팀 화면보다 짧다.
    #expect(login < main3)
    // (b) 팀원 수 비례 성장: 2명 < 5명.
    #expect(main2 < main5)
    // (c) 스크롤 상한: 7명 초과(10명)도 높이는 7행(maxVisibleRows)에서 고정된다.
    #expect(main10 == main7)

    // (d) 모든 상태 ≤ 700pt (scale 2 → 픽셀/2). 로그인/오류/가입(코드/만들기)/코드공유/무소속/owner/
    //     메인 각종/12h 배너/리더보드(3팀·상한) 포함.

    // 리더보드 스크롤 상한(6팀 초과)까지 채운 상태 — 팀 행이 팀원 행보다 높으므로 상한 검증에 포함.
    let cappedLeaderboardStore = makeTeamStore(members: [], now: now)
    cappedLeaderboardStore.currentTeamID = URLProtocolStub.stubTeamID
    cappedLeaderboardStore.leaderboard = manyLeaderboardEntries(count: 12)
    cappedLeaderboardStore.isLeaderboardVisible = true

    let allHeights: [Int] = try [
        login,
        try #require(renderedPixelHeight(CheckMenuView(store: makeLoginStore(syncMessage: "로그인 정보 오류"), previewASCIIWarning: true))),
        // 가입(코드 모드) — 미리보기 성공/실패.
        try #require(renderedPixelHeight(CheckMenuView(store: signupCodeStore(preview: true), initialAuthMode: .signUp))),
        try #require(renderedPixelHeight(CheckMenuView(store: signupCodeStore(preview: false), initialAuthMode: .signUp))),
        // 가입(팀 만들기 모드).
        try #require(renderedPixelHeight(CheckMenuView(store: createTeamStore(), initialAuthMode: .signUp))),
        // 가입 성공 직후 코드 공유 카드.
        try #require(renderedPixelHeight(CheckMenuView(store: createdCodeStore(), initialAuthMode: .signUp))),
        // 무소속 패널(코드 참여 / 새 팀 만들기).
        try #require(renderedPixelHeight(CheckMenuView(store: teamlessStore(createMode: false)))),
        try #require(renderedPixelHeight(CheckMenuView(store: teamlessStore(createMode: true)))),
        // owner 팀 카드에서 참여코드 인라인 노출.
        try #require(renderedPixelHeight(CheckMenuView(store: ownerCodeStore(now: now), previewOwnerCodeRevealed: true))),
        try #require(renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: [], now: now)))),
        try #require(renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: presenceMembers(now: now), now: now)))),
        main10,
        // 실데이터 톤의 10명(active/stale/off 혼합) — 가장 큰 메인 상태.
        try #require(renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 10), now: now)))),
        try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewLongSessionBanner: true))),
        try #require(renderedPixelHeight(CheckMenuView(store: makeLeaderboardStore()))),
        try #require(renderedPixelHeight(CheckMenuView(store: cappedLeaderboardStore)))
    ]

    for pixelHeight in allHeights {
        // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
        #expect(Double(pixelHeight) / 2.0 <= 700.0)
    }
}

// MARK: - A3: Enter-키 포커스 체이닝 순서

@Test
func authFocusChainingFollowsFieldOrder() {
    // 가입: 별명 → 이메일 → 비밀번호 → 제출(nil)
    #expect(AuthFocusField.displayName.nextField(mode: .signUp) == .email)
    #expect(AuthFocusField.email.nextField(mode: .signUp) == .password)
    #expect(AuthFocusField.password.nextField(mode: .signUp) == nil)
    // 로그인: 이메일 → 비밀번호 → 제출(nil). 별명 필드는 로그인 모드에 없으므로 제출로 취급한다.
    #expect(AuthFocusField.email.nextField(mode: .signIn) == .password)
    #expect(AuthFocusField.password.nextField(mode: .signIn) == nil)
    #expect(AuthFocusField.displayName.nextField(mode: .signIn) == nil)
}

// MARK: - E1: 팀원 3상태(active/stale/off) 표시

@MainActor
@Test
func checkMenuViewRendersPresenceTeamSnapshot() throws {
    // active(라이브 틱)·stale(연결 끊김·동결·"마지막 확인 N분 전")·off(회색) 세 상태가 한 목록에 섞여
    // 각 칩/보조줄/아바타가 340pt 폭 안에서 잘림·겹침 없이 수납되는지 확인한다.
    let store = makeSignedInStore()
    let now = Date()
    store.displayNow = now
    store.teamMembers = [
        // active + 아바타 이미지(내 행). updatedAt nil → lastSeenAt nil → activeWorking, 라이브 틱.
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .working,
            updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3_661),
            weeklyDurationSeconds: 14_400,
            avatarURL: CheckMascotAssets.url(for: .neutral)
        ),
        // stale. updatedAt(=lastSeenAt) 7분 전 → >90초 → staleWorking. 현재/주간은 마지막 신호에서 동결.
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000003",
            name: "민수",
            status: .working,
            updatedAt: now.addingTimeInterval(-420),
            currentSessionStartedAt: now.addingTimeInterval(-7_620),
            weeklyDurationSeconds: 28_800
        ),
        // off. 회색 칩 + 주간 누적만.
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000001",
            name: "yesung",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 7_200
        )
    ]

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_PRESENCE_TEAM_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - K: 팀별 이번 주 페이지

@MainActor
@Test
func checkMenuViewRendersLeaderboardSnapshot() throws {
    // 팀별 이번 주 페이지: 3팀(1인당 평균 내림차순), 우리 팀(2번째)에 "우리 팀" 칩, 평균/목표 미니 게이지·% +
    // "각자 목표 G시간 · 총 X시간 · N명 · M명 근무중" 캡션이 340pt 폭 안에서 잘림·겹침 없이 수납되는지 육안
    // 확인한다. 메인 숫자는 "평균 X시간 Y분", 메달·트로피·순위 숫자는 없어야 한다.
    let store = makeLeaderboardStore()

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_LEADERBOARD_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

/// 1인당 목표 교정 육안 확인용 스냅샷 2종을 CHECK_PERPERSON_SNAPSHOT_DIR 로 덤프한다(지정 시에만).
///  - my-team-card.png: 내 진행률 게이지("내 12시간 30분 / 60시간 · 21%") + 멤버 ✓ 정확히 1명(목표 달성).
///  - leaderboard.png: 3팀(평균 역전, 우리 팀 2번째) 팀별 이번 주 페이지.
@MainActor
@Test
func dumpPerPersonGoalSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_PERPERSON_SNAPSHOT_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let now = Date()

    // 내 팀 카드: 목표 60시간(1인당). 내 행(userID ...002) 주간 12시간 30분 → 게이지 내 진행률 ≈ 21%.
    // "성실"만 주간 61시간(≥60h)이라 ✓ 1명, "민수"는 30시간이라 ✓ 없음.
    let myID = "00000000-0000-0000-0000-000000000002"
    let members = [
        TeamMemberStatus(
            id: myID, name: "영식", status: .offWork, updatedAt: nil,
            currentSessionStartedAt: nil, weeklyDurationSeconds: 12 * 3600 + 30 * 60,
            avatarURL: CheckMascotAssets.url(for: .neutral)
        ),
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000001", name: "성실", status: .working, updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3_600), weeklyDurationSeconds: 61 * 3600
        ),
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000003", name: "민수", status: .offWork, updatedAt: nil,
            currentSessionStartedAt: nil, weeklyDurationSeconds: 30 * 3600
        )
    ]
    let cardStore = makeTeamStore(members: members, now: now)
    cardStore.teamGoalSeconds = 60 * 3600
    let cardPNG = try renderPNG(CheckMenuView(store: cardStore))
    try cardPNG.write(to: base.appendingPathComponent("my-team-card.png"))

    let leaderboardPNG = try renderPNG(CheckMenuView(store: makeLeaderboardStore()))
    try leaderboardPNG.write(to: base.appendingPathComponent("leaderboard.png"))
}

// MARK: - E2: 아바타(이미지 1 + 이니셜 2)

@MainActor
@Test
func checkAvatarViewRendersMixedSnapshot() throws {
    // 원격(파일 URL) 이미지 아바타 1명 + 이니셜 폴백 2명이 원형으로 선명하게 그려지는지 확인한다.
    let imageURL = try #require(CheckMascotAssets.url(for: .neutral))
    let view = VStack(spacing: 14) {
        HStack(spacing: 12) {
            CheckAvatarView(name: "영식", avatarURL: imageURL, size: 26)
            CheckAvatarView(name: "민수", size: 26)
            CheckAvatarView(name: "yesung", size: 26)
        }
        HStack(spacing: 12) {
            CheckAvatarView(name: "영식", avatarURL: imageURL, size: 44)
            CheckAvatarView(name: "민수", size: 44)
            CheckAvatarView(name: "yesung", size: 44)
        }
    }
    .padding(20)
    .background(CheckTheme.panel)

    let png = try renderPNG(view, width: 260)
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_AVATAR_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - E4: 12시간 확인 배너

@MainActor
@Test
func longSessionBannerRendersSnapshot() throws {
    // 배너 컴포넌트를 직접 초기화해 렌더한다(스텁 store로는 활성화 불가). 잘림·겹침 없이 그려져야 한다.
    let banner = LongSessionBanner(onConfirm: {})
        .frame(width: 316, height: 88)
    let png = try renderPNG(banner, width: 316)
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_LONG_SESSION_BANNER_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersLongSessionBannerContextSnapshot() throws {
    // 배너가 헤더 카드 위 overlay로 얹힌 실제 배치를 확인한다(previewLongSessionBanner로 강제).
    let store = makeSignedInStore()
    let png = try renderPNG(CheckMenuView(store: store, previewLongSessionBanner: true))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_LONG_SESSION_BANNER_CONTEXT_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - F 스냅샷 덤프 (육안 확인용, CHECK_SNAPSHOT_DIR 지정 시에만 기록)

@MainActor
@Test
func dumpTrackFSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let now = Date()

    func write(_ view: some View, _ name: String, width: CGFloat = 340) throws {
        let png = try renderPNG(view, width: width)
        try png.write(to: base.appendingPathComponent(name))
    }

    // 로그인 모드(기본 진입).
    let loginStore = makeLoginStore(syncMessage: "로그인 필요")
    try write(CheckMenuView(store: loginStore), "login.png")

    // 가입(코드 모드): 미리보기 성공 / 실패.
    try write(CheckMenuView(store: signupCodeStore(preview: true), initialAuthMode: .signUp), "signup-code-success.png")
    try write(CheckMenuView(store: signupCodeStore(preview: false), initialAuthMode: .signUp), "signup-code-fail.png")

    // 가입(팀 만들기 모드).
    try write(CheckMenuView(store: createTeamStore(), initialAuthMode: .signUp), "signup-create-team.png")

    // 가입 성공 직후 참여코드 공유 카드.
    try write(CheckMenuView(store: createdCodeStore(), initialAuthMode: .signUp), "created-code-card.png")

    // 무소속 패널: 코드 참여 / 새 팀 만들기.
    try write(CheckMenuView(store: teamlessStore(createMode: false)), "teamless-join.png")
    try write(CheckMenuView(store: teamlessStore(createMode: true)), "teamless-create.png")

    // owner 팀 카드에서 참여코드 인라인 노출.
    try write(CheckMenuView(store: ownerCodeStore(now: now), previewOwnerCodeRevealed: true), "owner-code-revealed.png")

    // 메인: 0명 / 2명 / 3명(presence) / 5명 / 10명(스크롤 상한).
    // 창 높이는 이제 팀원 수에 비례(2<5<7)해 자라고 7행에서 상한. 10명은 previewClipsOverflowList로
    // 보이는 첫 7행을 클립해 그린다(앱은 ScrollView지만 ImageRenderer는 NSScrollView 내용을 못 그리므로).
    try write(CheckMenuView(store: makeTeamStore(members: [], now: now)), "main-empty.png")
    try write(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 2), now: now)), "main-two.png")
    try write(CheckMenuView(store: makeTeamStore(members: presenceMembers(now: now), now: now)), "main-three.png")
    try write(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 5), now: now)), "main-five.png")
    try write(
        CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 10), now: now), previewClipsOverflowList: true),
        "main-ten-scroll.png"
    )

    // 팀별 이번 주 페이지: 3팀(총시간 내림차순), 우리 팀 2번째에 "우리 팀" 칩.
    try write(CheckMenuView(store: makeLeaderboardStore()), "leaderboard-three.png")
}

// MARK: - E3: 다운스케일 순수 함수

@Test
func downscaledPixelSizeShrinksLargeImagesToMaxDimension() {
    // 최장변이 256을 넘으면 종횡비를 유지해 최장변 256으로 축소한다.
    #expect(CheckAvatarView.downscaledPixelSize(for: CGSize(width: 1_024, height: 768)) == CGSize(width: 256, height: 192))
    #expect(CheckAvatarView.downscaledPixelSize(for: CGSize(width: 512, height: 512)) == CGSize(width: 256, height: 256))
    #expect(CheckAvatarView.downscaledPixelSize(for: CGSize(width: 400, height: 1_000)) == CGSize(width: 102, height: 256))
}

@Test
func downscaledPixelSizeKeepsSmallImagesUnchanged() {
    // 최장변이 256 이하이면 확대하지 않고 원본 크기를 그대로 유지한다.
    #expect(CheckAvatarView.downscaledPixelSize(for: CGSize(width: 120, height: 90)) == CGSize(width: 120, height: 90))
    #expect(CheckAvatarView.downscaledPixelSize(for: CGSize(width: 256, height: 256)) == CGSize(width: 256, height: 256))
    #expect(CheckAvatarView.downscaledPixelSize(for: CGSize(width: 64, height: 200)) == CGSize(width: 64, height: 200))
}

// MARK: - Helpers

@MainActor
private func makeSignedInStore() -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "sudo 박수"
    store.teamMembers = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .working,
            updatedAt: nil,
            currentSessionStartedAt: Date(timeIntervalSinceNow: -3_600),
            weeklyDurationSeconds: 14_400
        )
    ]
    return store
}

/// 로그인된 스토어에 임의의 팀원 목록/기준시각을 주입한다. 창 고정 높이 invariant·스냅샷 공용.
@MainActor
private func makeTeamStore(members: [TeamMemberStatus], now: Date = Date()) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.teamMembers = members
    // 팀이 확정된 상태(무소속 아님) + 헤더 이름을 "팀" 플레이스홀더가 아닌 실제 이름으로 확정한다.
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "sudo 박수"
    return store
}

/// active(라이브)·stale(연결 끊김·보조줄)·off 세 상태가 섞인 3인 팀원 표본.
@MainActor
private func presenceMembers(now: Date) -> [TeamMemberStatus] {
    [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .working,
            updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3_661),
            weeklyDurationSeconds: 14_400,
            avatarURL: CheckMascotAssets.url(for: .neutral)
        ),
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000003",
            name: "민수",
            status: .working,
            updatedAt: now.addingTimeInterval(-420),
            currentSessionStartedAt: now.addingTimeInterval(-7_620),
            weeklyDurationSeconds: 28_800,
            lastSeenAt: now.addingTimeInterval(-420)
        ),
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000001",
            name: "yesung",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 7_200
        )
    ]
}

/// active/stale/off가 섞인 N인 팀원 표본. count가 창 고정 높이를 넘으면 리스트가 스크롤돼야 한다.
@MainActor
private func manyMembers(now: Date, count: Int = 8) -> [TeamMemberStatus] {
    let names = ["영식", "민수", "지현", "서준", "하윤", "도현", "예린", "yesung", "태우", "보라"]
    return Array(names.prefix(count)).enumerated().map { index, name in
        let isOff = index % 3 == 2
        let isStale = index % 3 == 1
        return TeamMemberStatus(
            id: "00000000-0000-0000-0000-00000000000\(index)",
            name: name,
            status: isOff ? .offWork : .working,
            updatedAt: isStale ? now.addingTimeInterval(-420) : nil,
            currentSessionStartedAt: isOff ? nil : now.addingTimeInterval(-3_600 - Double(index) * 600),
            weeklyDurationSeconds: 7_200 + index * 3_600,
            avatarURL: index == 0 ? CheckMascotAssets.url(for: .neutral) : nil,
            lastSeenAt: isStale ? now.addingTimeInterval(-420) : nil
        )
    }
}

/// 팀별 이번 주 스텁 표본. member_count 로 평균 역전을 심었다 — 총합 순서(오목교>sudo>코드)와
/// 1인당 평균 순서(코드 36000 > sudo 24000 > 오목교 15000)가 반대다. 평균 정렬 후 우리 팀(stubTeamID)이 2번째.
private let sampleLeaderboard: [TeamLeaderboardEntry] = [
    TeamLeaderboardEntry(id: "20000000-0000-0000-0000-000000000002", name: "오목교 브라더스", weeklyGoalHours: 60, totalSeconds: 90_000, workingCount: 1, memberCount: 6),
    TeamLeaderboardEntry(id: URLProtocolStub.stubTeamID, name: "sudo 박수", weeklyGoalHours: 40, totalSeconds: 72_000, workingCount: 3, memberCount: 3),
    TeamLeaderboardEntry(id: "30000000-0000-0000-0000-000000000003", name: "코드 크래프터", weeklyGoalHours: 50, totalSeconds: 36_000, workingCount: 0, memberCount: 1)
]

/// 팀별 이번 주 페이지가 열린 로그인 스토어. 우리 팀(currentTeamID=stubTeamID)에 칩이 뜨도록 세팅한다.
@MainActor
private func makeLeaderboardStore() -> WorkTimerStore {
    let store = makeTeamStore(members: [], now: Date())
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.leaderboard = sampleLeaderboard
    store.isLeaderboardVisible = true
    return store
}

/// 가입(코드 모드) 스토어. preview=true 면 미리보기 성공(브라보 팀), false 면 실패 안내를 세팅한다.
@MainActor
private func signupCodeStore(preview: Bool) -> WorkTimerStore {
    let store = makeLoginStore(syncMessage: "로그인 필요")
    store.displayName = "영식"
    store.isCreateTeamMode = false
    if preview {
        store.signupTeamCode = "BRAVO123"
        store.joinPreview = TeamJoinPreview(teamID: URLProtocolStub.stubTeamID, name: "브라보", weeklyGoalHours: 60, memberCount: 3)
        store.joinPreviewMessage = ""
    } else {
        store.signupTeamCode = "ZZZZ99"
        store.joinPreview = nil
        store.joinPreviewMessage = "팀 코드를 확인해 주세요"
    }
    return store
}

/// 가입(팀 만들기 모드) 스토어. 팀명 + 주간 목표 폼이 채워진 상태.
@MainActor
private func createTeamStore() -> WorkTimerStore {
    let store = makeLoginStore(syncMessage: "로그인 필요")
    store.displayName = "영식"
    store.isCreateTeamMode = true
    store.createTeamName = "새벽 러너스"
    store.createTeamGoalHours = 72
    return store
}

/// 가입 성공 직후 참여코드 공유 카드가 뜬 스토어.
@MainActor
private func createdCodeStore() -> WorkTimerStore {
    let store = makeLoginStore(syncMessage: "동기화됨")
    store.isCreateTeamMode = true
    store.createTeamName = "새벽 러너스"
    store.createdTeamCode = "BRAVO123"
    return store
}

/// 무소속(로그인됨·팀 없음) 스토어. createMode=true 면 새 팀 만들기 폼, false 면 코드 참여 폼.
@MainActor
private func teamlessStore(createMode: Bool) -> WorkTimerStore {
    let store = makeSignedInStore()
    // 무소속으로 강제(currentTeamID=nil) → isTeamless == true.
    store.currentTeamID = nil
    store.teamMembers = []
    store.syncMessage = "동기화됨"
    store.isCreateTeamMode = createMode
    if createMode {
        store.createTeamName = "새벽 러너스"
        store.createTeamGoalHours = 60
    } else {
        store.signupTeamCode = "BRAVO123"
        store.joinPreview = TeamJoinPreview(teamID: URLProtocolStub.stubTeamID, name: "브라보", weeklyGoalHours: 60, memberCount: 3)
    }
    return store
}

/// owner 팀 카드(참여코드 인라인 노출)용 스토어. 3인 팀 + 초대코드 보유(→ isTeamOwner true).
@MainActor
private func ownerCodeStore(now: Date) -> WorkTimerStore {
    let store = makeTeamStore(members: presenceMembers(now: now), now: now)
    store.myTeamInviteCode = "BRAVO123"
    return store
}

/// 뷰를 지정 폭 고정으로 렌더해 PNG Data를 돌려준다. 스냅샷/카운트 확인 공용.
@MainActor
private func renderPNG(_ view: some View, width: CGFloat = 340) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw RenderError.failed
    }
    return pngData
}

private enum RenderError: Error {
    case failed
}

/// 평균 내림차순 N팀 리더보드 표본(스크롤 상한 검증용). 우리 팀(stubTeamID)은 포함하지 않는다.
/// member_count 1 이라 평균 = 총합이라 순서/상한 검증에 영향 없다.
private func manyLeaderboardEntries(count: Int) -> [TeamLeaderboardEntry] {
    (0..<count).map { i in
        TeamLeaderboardEntry(id: "bbbbbbbb-0000-0000-0000-\(String(format: "%012d", i))", name: "팀\(i)", weeklyGoalHours: 60, totalSeconds: (count - i) * 3_600, workingCount: i % 3, memberCount: 1)
    }
}

/// 헤더(주간 게이지·근무중 카운트) 높이가 팀원 수와 무관하게 일정하도록 만든 N인 표본.
/// 전원 근무종료 + 작은 고정 주간(1h)이라 목표(60h) 미달·근무중 0명으로 헤더가 불변 →
/// 창 높이 차이가 오직 멤버 리스트(행 수 비례/스크롤 상한)에서만 나오게 해 높이 비교를 정확하게 한다.
@MainActor
private func steadyMembers(count: Int) -> [TeamMemberStatus] {
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
private func makeLoginStore(syncMessage: String) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults()
    )
    store.email = "member@example.com"
    store.password = "team-password"
    store.syncMessage = syncMessage
    return store
}

/// 뷰를 340pt 폭 고정으로 렌더한 뒤 PNG 픽셀 높이를 돌려준다. 높이 동일성 비교 전용.
@MainActor
private func renderedPixelHeight(_ view: some View) -> Int? {
    let renderer = ImageRenderer(content: view.frame(width: 340).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return nil
    }
    return bitmap.pixelsHigh
}

private func isolatedRenderDefaults() -> UserDefaults {
    let suiteName = "check-render-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
