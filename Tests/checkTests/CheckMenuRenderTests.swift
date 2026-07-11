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

// MARK: - A2: 창 완전 고정 높이 — 모든 상태의 픽셀 높이가 정확히 동일해야 한다(창 튐 근절)

@MainActor
@Test
func windowHeightIsConstantAcrossAllStates() throws {
    // 로그인/가입/오류 배너/메인(팀원 0·3명, stale 포함)/12h 배너 — 어느 상태든 창(뷰) 높이가
    // windowHeight 상수로 고정돼 정확히 같은 픽셀 높이여야 한다. 이 단일 invariant가 이전
    // 높이 안정성 테스트 3종(오류 배너·모드 전환·ASCII 캡션)과 12h 배너 안정성 테스트를 대체한다.
    let now = Date()

    // 로그인 모드(별명 필드 숨김) — 별명 값이 있어도 로그인 모드 표시는 동일해야 한다.
    let loginStore = makeLoginStore(syncMessage: "로그인 필요")
    // 로그인 + 오류 배너.
    let loginErrorStore = makeLoginStore(syncMessage: "로그인 정보 오류")
    // 가입 모드(별명·팀 선택 노출). 팀 목록/선택까지 채워 실제 가입 카드 높이를 재현한다.
    let signupStore = makeLoginStore(syncMessage: "로그인 필요")
    signupStore.displayName = "영식"
    signupStore.teamDirectory = sampleTeamDirectory
    signupStore.selectedSignupTeamID = sampleTeamDirectory.first?.id

    let heights: [Int] = try [
        renderedPixelHeight(CheckMenuView(store: loginStore)),
        renderedPixelHeight(CheckMenuView(store: loginErrorStore, previewASCIIWarning: true)),
        renderedPixelHeight(CheckMenuView(store: signupStore, initialAuthMode: .signUp)),
        renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: [], now: now))),
        renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: presenceMembers(now: now), now: now))),
        // 팀원이 남는 공간을 초과(스크롤)해도 창(뷰) 높이는 절대 변하지 않아야 한다.
        renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 8), now: now))),
        renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewLongSessionBanner: true))
    ].map { try #require($0) }

    // 모든 상태의 픽셀 높이가 정확히 하나로 수렴해야 한다.
    #expect(Set(heights).count == 1)
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

    // 팀 선택 라벨(Menu는 AppKit 백킹이라 ImageRenderer가 못 그리므로 라벨만 단독 렌더로 확인).
    try write(
        TeamPickerLabel(text: "소속 팀을 선택하세요", isPlaceholder: true).padding(20).background(CheckTheme.panel),
        "team-picker-placeholder.png", width: 316
    )
    try write(
        TeamPickerLabel(text: "sudo 박수", isPlaceholder: false).padding(20).background(CheckTheme.panel),
        "team-picker-selected.png", width: 316
    )
    try write(
        TeamPickerLabel(text: "팀 목록 불러오는 중…", isPlaceholder: true).padding(20).background(CheckTheme.panel),
        "team-picker-loading.png", width: 316
    )

    // 가입 모드: 팀 선택 전(플레이스홀더) / 후(선택된 팀 이름).
    let signupBefore = makeLoginStore(syncMessage: "로그인 필요")
    signupBefore.displayName = "영식"
    signupBefore.email = "member@example.com"
    signupBefore.password = "team-password"
    signupBefore.teamDirectory = sampleTeamDirectory
    try write(CheckMenuView(store: signupBefore, initialAuthMode: .signUp), "signup-before-selection.png")

    let signupAfter = makeLoginStore(syncMessage: "로그인 필요")
    signupAfter.displayName = "영식"
    signupAfter.email = "member@example.com"
    signupAfter.password = "team-password"
    signupAfter.teamDirectory = sampleTeamDirectory
    signupAfter.selectedSignupTeamID = sampleTeamDirectory.first?.id
    try write(CheckMenuView(store: signupAfter, initialAuthMode: .signUp), "signup-after-selection.png")

    // 메인: 0명 / 3명(presence) / 5·6명(스크롤 경계) / 8명(스크롤 필요, 창 고정 유지).
    try write(CheckMenuView(store: makeTeamStore(members: [], now: now)), "main-empty.png")
    try write(CheckMenuView(store: makeTeamStore(members: presenceMembers(now: now), now: now)), "main-three.png")
    try write(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 5), now: now)), "main-five.png")
    try write(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 6), now: now)), "main-six.png")
    try write(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 8), now: now)), "main-eight-scroll.png")
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
    // 팀 카드 헤더 이름이 "팀" 플레이스홀더가 아닌 실제 이름으로 나오도록 스텁 팀명을 확정한다.
    store.teamDirectory = sampleTeamDirectory
    store.selectedSignupTeamID = sampleTeamDirectory.first?.id
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

/// 가입 화면 팀 선택 스텁 표본.
private let sampleTeamDirectory: [TeamDirectoryEntry] = [
    TeamDirectoryEntry(id: "10000000-0000-0000-0000-000000000001", name: "sudo 박수"),
    TeamDirectoryEntry(id: "10000000-0000-0000-0000-000000000002", name: "새벽 러너스"),
    TeamDirectoryEntry(id: "10000000-0000-0000-0000-000000000003", name: "코드 크래프터")
]

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
