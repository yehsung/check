import AppKit
import SwiftUI
import Testing
@testable import check

@MainActor
@Test
func checkMenuViewRendersSnapshot() throws {
    let store = WorkTimerStore(environment: [
        "CHECK_SUPABASE_ANON_KEY": "local-test-key"
    ], defaults: isolatedRenderDefaults(), tokenUsage: inertTokenStore())
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다(티커 미발사).
    store.isMenuPresented = true
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
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
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
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다(티커 미발사).
    store.isMenuPresented = true
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
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
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
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
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
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
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
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
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
        let view = MenuBarStatusLabel(snapshot: snapshot, title: MenuBarStatusFormatter.title(for: snapshot))
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
        // 새 버전 안내 배너가 최상단에 얹힌 상태(HeaderCard 위) — 배너 포함해도 상한(≤700pt) 안에 머문다.
        try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewUpdateBanner: true))),
        // 헤더 주간 목표 편집 행이 펼쳐진 상태(스테퍼 + 저장 버튼) — 편집은 헤더 아래로 자라므로 대형 팀에선
        // 상한을 넘을 수 있는 일시 상태다. 상시 노출 상태만 상한을 보장하고, 편집은 보통 팀 규모(3명)로 검증한다.
        try #require(renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: manyMembers(now: now, count: 3), now: now), previewGoalEditing: true))),
        try #require(renderedPixelHeight(CheckMenuView(store: makeLeaderboardStore()))),
        try #require(renderedPixelHeight(CheckMenuView(store: cappedLeaderboardStore)))
    ]

    for pixelHeight in allHeights {
        // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
        #expect(Double(pixelHeight) / 2.0 <= 700.0)
    }
}

// MARK: - ACD-F4: 렌더 결정성(onAppear 가 고정 now 를 덮거나 티커를 발사하지 않음)

@MainActor
@Test
func renderingMenuKeepsFixedDisplayNowAndDoesNotStartTicker() {
    // 재현: ImageRenderer 가 onAppear 를 실행하면 setMenuPresented(true) 가 호출되어, 고정 displayNow 가
    // Date() 로 덮이고 스토어당 티커가 시작·영구 잔존했다. 헬퍼가 isMenuPresented 를 미리 true 로 둬
    // 세터의 != 가드로 onAppear 가 no-op 이 되면 고정 now 가 보존되고 티커도 발사되지 않아야 한다.
    let fixed = Date(timeIntervalSince1970: 1_000_000)
    let store = makeTeamStore(members: steadyMembers(count: 2), now: fixed)
    #expect(store.isMenuPresented)
    #expect(store.tickerTask == nil)

    _ = renderedPixelHeight(CheckMenuView(store: store))

    // onAppear 가 no-op → 고정 displayNow 가 Date() 로 덮이지 않는다.
    #expect(store.displayNow == fixed)
    // onAppear 가 no-op → stopTimerIfIdle/startTimer 경로를 타지 않아 티커가 시작되지 않는다.
    #expect(store.tickerTask == nil)
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

// MARK: - 목표 UI 재배치: 헤더 퍼센트 계산 + 팀원 행 목표 바 노출

@Test
func headerGoalPercentComputesActualRatioWithCap() {
    // (a) 헤더 목표 퍼센트는 실제 비율 기반이라 100%를 넘을 수 있다(상한 999%). 0%/43%/100%/초과를 검증한다.
    #expect(GoalPercentFormatter.percent(workedSeconds: 0, goalSeconds: 60 * 3600) == 0)
    #expect(GoalPercentFormatter.percent(workedSeconds: 43, goalSeconds: 100) == 43)
    #expect(GoalPercentFormatter.percent(workedSeconds: 60 * 3600, goalSeconds: 60 * 3600) == 100)
    #expect(GoalPercentFormatter.percent(workedSeconds: 120 * 3600, goalSeconds: 60 * 3600) == 200)
    // 상한: 목표의 100배를 넘어도 999% 로 클램프한다.
    #expect(GoalPercentFormatter.percent(workedSeconds: 10_000 * 3600, goalSeconds: 60 * 3600) == 999)
}

@Test
func shortfallPercentNeverReadsAsFullyMetWhileStillShort() {
    // 회귀 지점: 지난주 회고 목표선이 반올림 퍼센트와 부족분을 한 문장에 붙여 쓰면서
    // "목표 60시간 00분 중 100% · 0시간 18분 부족" 이라는 자기모순 문구를 냈다.
    // 목표 60시간 / 지난주 59시간 42분 — 반올림하면 100 이지만 metGoal 은 엄격 비교(>=)라 여전히 미달이다.
    #expect(GoalPercentFormatter.percent(workedSeconds: 214_920, goalSeconds: 216_000) == 100)
    #expect(214_920 < 216_000)  // 실제로는 미달(1,080초 부족).
    // 미달 문맥 전용 퍼센트는 99 로 묶여 문장이 스스로를 부정하지 않는다.
    #expect(GoalPercentFormatter.shortfallPercent(workedSeconds: 214_920, goalSeconds: 216_000) == 99)
    // 목표 40시간(39시간 48분)에서도 같은 구간이 존재한다.
    #expect(GoalPercentFormatter.shortfallPercent(workedSeconds: 143_280, goalSeconds: 144_000) == 99)
    // 미달이 아닌 값은 손대지 않는다(달성 분기는 이 함수를 타지 않지만 계산 자체가 왜곡되면 안 된다).
    #expect(GoalPercentFormatter.shortfallPercent(workedSeconds: 108_000, goalSeconds: 216_000) == 50)
    #expect(GoalPercentFormatter.shortfallPercent(workedSeconds: 0, goalSeconds: 216_000) == 0)
}

@MainActor
@Test
func teamMemberRowDrawsGoalBarOnlyWhenFractionPresent() throws {
    // (b) goalFraction 이 nil 이면 바를 그리지 않고(행이 낮음), non-nil 이면 바+캡션만큼 행이 높아진다.
    // 두 행을 같은 폭으로 렌더해 픽셀 높이를 실측 비교한다(뷰 계층이 아니라 실제 렌더 결과로 검증).
    let withBar = TeamMemberRow(name: "영식", presence: .offWork, primaryDetail: "주 12시간 30분", goalFraction: 0.5)
    let noBar = TeamMemberRow(name: "영식", presence: .offWork, primaryDetail: "주 12시간 30분")
    let withBarHeight = try #require(renderedPixelHeight(withBar))
    let noBarHeight = try #require(renderedPixelHeight(noBar))
    #expect(withBarHeight > noBarHeight)
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

// MARK: - B1: 리그 0시간 팀 숨김 렌더

@MainActor
@Test
func checkMenuViewRendersFilteredLeaderboardSnapshot() throws {
    // 0시간 타팀은 리그에서 숨고, 0시간이어도 내 팀(우리 팀 칩)은 유지된다. 표시 필터는 뷰 호출부에서만 적용하고
    // 스토어 원본 leaderboard 는 보존한다. 숨김/유지가 340pt 폭 안에서 잘림·겹침 없이 그려지는지 확인한다.
    let store = makeTeamStore(members: [], now: Date())
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.leaderboard = [
        // 우리 팀 — 0시간이어도 유지(우리 팀 칩).
        TeamLeaderboardEntry(id: URLProtocolStub.stubTeamID, name: "아잉팀", weeklyGoalHours: 40, totalSeconds: 0, workingCount: 0, memberCount: 3),
        // 0시간 타팀 — 숨겨져야 한다.
        TeamLeaderboardEntry(id: "20000000-0000-0000-0000-000000000002", name: "잠든 팀", weeklyGoalHours: 60, totalSeconds: 0, workingCount: 0, memberCount: 2),
        // 근무한 팀들 — 표시.
        TeamLeaderboardEntry(id: "30000000-0000-0000-0000-000000000003", name: "코드 크래프터", weeklyGoalHours: 50, totalSeconds: 36000, workingCount: 1, memberCount: 1),
        TeamLeaderboardEntry(id: "40000000-0000-0000-0000-000000000004", name: "오목교 브라더스", weeklyGoalHours: 60, totalSeconds: 90000, workingCount: 2, memberCount: 3)
    ]
    store.isLeaderboardVisible = true

    // 렌더 결과의 필터링을 눈으로 확인하되, 필터 규약 자체는 모델 단위 테스트가 보장한다.
    #expect(store.leaderboard.filteredForDisplay(myTeamID: store.currentTeamID).map(\.name) == ["코드 크래프터", "오목교 브라더스", "아잉팀"])

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_FILTERED_LEADERBOARD_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// FIX: 리그 빈-필터 문구 — 원본에 팀이 있으나 이번 주 아무도 근무 안 해 필터로 전부 숨겨지면 중립 문구를 쓰고,
// 로드 전/실패(원본 0)면 fallbackStatus(동기화 상태)를 쓴다. '동기화됨'이 본문에 뜨는 어색함을 없앤다.
@MainActor
@Test
func leaderboardEmptyFilterUsesNeutralMessageDistinctFromFallback() throws {
    // 순수 판정 지점: 원본 팀 있음(>0)+표시 비면 중립 문구, 원본 없음(0)이면 fallbackStatus 그대로.
    #expect(LeaderboardEmptyMessage.text(unfilteredCount: 2, fallbackStatus: "동기화됨") == "아직 이번 주 근무한 팀이 없어요")
    #expect(LeaderboardEmptyMessage.text(unfilteredCount: 0, fallbackStatus: "동기화됨") == "동기화됨")
    #expect(LeaderboardEmptyMessage.text(unfilteredCount: 0, fallbackStatus: "로그인 필요") == "로그인 필요")

    // 렌더 경로 실증: 내 팀은 목록에 없고 타팀은 전부 0시간 → 필터 후 표시 목록이 비지만 원본은 2팀(중립 문구 경로).
    let store = makeTeamStore(members: [], now: Date())
    store.syncMessage = "동기화됨"
    store.leaderboard = [
        TeamLeaderboardEntry(id: "20000000-0000-0000-0000-000000000002", name: "잠든 팀", weeklyGoalHours: 60, totalSeconds: 0, workingCount: 0, memberCount: 2),
        TeamLeaderboardEntry(id: "30000000-0000-0000-0000-000000000003", name: "쉬는 팀", weeklyGoalHours: 50, totalSeconds: 0, workingCount: 0, memberCount: 1)
    ]
    store.isLeaderboardVisible = true
    #expect(store.leaderboard.filteredForDisplay(myTeamID: store.currentTeamID).isEmpty) // 표시 목록은 빔
    #expect(store.leaderboard.count == 2)                                                 // 원본은 2팀

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
}

// MARK: - B2: 참여코드 팀원 공개 렌더

@MainActor
@Test
func checkMenuViewRendersMemberInviteCodeSnapshot() throws {
    // member 역할이어도 참여코드가 로드되면 키 버튼/인라인 행이 노출된다(owner 전용 아님).
    let store = makeTeamStore(members: presenceMembers(now: Date()), now: Date())
    store.teamRole = "member"
    store.myTeamInviteCode = "BRAVO123"

    let png = try renderPNG(CheckMenuView(store: store, previewOwnerCodeRevealed: true))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_MEMBER_CODE_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - 업데이트 배너 렌더 (새 버전 안내 + 원클릭/명령 복사)

@MainActor
@Test
func checkMenuViewRendersUpdateBannerSnapshot() throws {
    // 팝오버 최상단 새 버전 안내 배너([지금 업데이트]+[명령 복사])가 340pt 폭 안에서 잘림·겹침 없이
    // 그려지는지 육안 확인용. previewUpdateBanner 로 강제 노출한다(앱에선 감지 시에만).
    let store = makeSignedInStore()
    let png = try renderPNG(CheckMenuView(store: store, previewUpdateBanner: true))
    #expect(png.count > 0)
    // 지정 경로에 항상 저장해 육안 확인(존재하지 않는 디렉터리면 조용히 스킵). env 로 재정의 가능.
    let path = ProcessInfo.processInfo.environment["CHECK_UPDATE_BANNER_SNAPSHOT_PATH"]
        ?? "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/update-banner.png"
    try? png.write(to: URL(fileURLWithPath: path))
}

// MARK: - B3: 헤더 주간 목표 편집 행 렌더

@MainActor
@Test
func checkMenuViewRendersGoalEditingSnapshot() throws {
    // 캡션 % 옆 연필로 여는 목표 편집 행(스테퍼 + 저장 버튼)이 헤더 아래로 펼쳐진 상태.
    // 편집 행이 340pt 폭 안에서 잘림·겹침 없이 수납되는지 확인한다.
    let store = makeSignedInStore()
    store.teamGoalSeconds = 42 * 3600

    let png = try renderPNG(CheckMenuView(store: store, previewGoalEditing: true))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_GOAL_EDITING_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

/// 목표 UI 재배치 육안 확인용 스냅샷 2종을 CHECK_PERPERSON_SNAPSHOT_DIR 로 덤프한다(지정 시에만).
///  - my-team-card.png: 헤더 내 목표 바("이번 주 12시간 30분 / 60시간 · 21%") + 팀원 행마다 목표 바.
///    달성(✓·100%)/미달/스테일(보조줄+바 동시) 혼합 4명이 담긴다.
///  - leaderboard.png: 3팀(평균 역전, 우리 팀 2번째) 팀별 이번 주 페이지.
@MainActor
@Test
func dumpPerPersonGoalSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_PERPERSON_SNAPSHOT_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let now = Date()

    // 내 팀 카드: 목표 60시간(1인당). 내 행(userID ...002) 주간 12시간 30분 → 헤더 내 진행률 ≈ 21%.
    // "성실"만 주간 61시간(≥60h)이라 ✓ + 바 100%, 나머지는 미달. "민수"는 스테일(보조줄+바 동시 케이스).
    let myID = "00000000-0000-0000-0000-000000000002"
    let members = [
        // 내 행(off) — 12시간 30분/60시간 ≈ 21% 미달. 헤더 바와 별개로 행 밑에도 21% 바.
        TeamMemberStatus(
            id: myID, name: "영식", status: .offWork, updatedAt: nil,
            currentSessionStartedAt: nil, weeklyDurationSeconds: 12 * 3600 + 30 * 60,
            avatarURL: CheckMascotAssets.url(for: .neutral)
        ),
        // 달성(active) — 61시간(≥60h) → ✓ + 바 100%(working 채움).
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000001", name: "성실", status: .working, updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3_600), weeklyDurationSeconds: 61 * 3600
        ),
        // 스테일(연결 끊김) — "마지막 확인 N분 전" 보조줄 + 목표 바가 한 행에 함께 수납되는지 확인. ~53% 미달.
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000003", name: "민수", status: .working,
            updatedAt: now.addingTimeInterval(-420),
            currentSessionStartedAt: now.addingTimeInterval(-7_620), weeklyDurationSeconds: 30 * 3600,
            lastSeenAt: now.addingTimeInterval(-420)
        ),
        // 미달(off) — 48시간/60시간 → 80% 바.
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000004", name: "지현", status: .offWork, updatedAt: nil,
            currentSessionStartedAt: nil, weeklyDurationSeconds: 48 * 3600
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
    // 형제 뷰로 올라가며 높이가 콘텐츠 자연 높이가 됐으므로(고정 88 폐기) 폭만 고정해 그린다.
    let banner = LongSessionBanner(onConfirm: {}, onStopNow: {})
    let png = try renderPNG(banner, width: 316)
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_LONG_SESSION_BANNER_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func checkMenuViewRendersLongSessionBannerContextSnapshot() throws {
    // 배너가 헤더 카드 "위쪽 형제"로 놓인 실제 배치를 확인한다(previewLongSessionBanner로 강제).
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
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다(고정 displayNow 보존·티커 미발사).
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
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
private func makeTeamStore(
    members: [TeamMemberStatus],
    now: Date = Date(),
    tokenUsage: TokenUsageStore? = nil
) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedRenderDefaults(),
        tokenUsage: tokenUsage ?? inertTokenStore()
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다(고정 displayNow 보존·티커 미발사).
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.teamMembers = members
    // 팀이 확정된 상태(무소속 아님) + 헤더 이름을 "팀" 플레이스홀더가 아닌 실제 이름으로 확정한다.
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
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

/// 팀별 이번 주 스텁 표본. member_count 로 평균 역전을 심었다 — 총합 순서(오목교>아잉>코드)와
/// 1인당 평균 순서(코드 36000 > 아잉 24000 > 오목교 15000)가 반대다. 평균 정렬 후 우리 팀(stubTeamID)이 2번째.
private let sampleLeaderboard: [TeamLeaderboardEntry] = [
    TeamLeaderboardEntry(id: "20000000-0000-0000-0000-000000000002", name: "오목교 브라더스", weeklyGoalHours: 60, totalSeconds: 90_000, workingCount: 1, memberCount: 6),
    TeamLeaderboardEntry(id: URLProtocolStub.stubTeamID, name: "아잉팀", weeklyGoalHours: 40, totalSeconds: 72_000, workingCount: 3, memberCount: 3),
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
        defaults: isolatedRenderDefaults(),
        tokenUsage: inertTokenStore()
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다(티커 미발사).
    store.isMenuPresented = true
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

/// 렌더 테스트용 격리 토큰 스토어. 실홈 대신 빈 임시 홈 + 격리 defaults 를 준다 — CheckMenuView 의 .task 갱신 루프가
/// ImageRenderer 렌더 중에 돌더라도(ImageRenderer 는 .task 를 실행한다) 실홈 스캔이나 테스트 러너 .standard 오염이
/// 일어나지 않는다. 빈 홈이라 집계는 0 → 팝오버에서는 숫자 없는 순위판 진입 행(boardEntryRow)이,
/// 콜백 없이 단독으로 쓰면 EmptyView 가 결정적으로 그려진다.
@MainActor
private func inertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: isolatedRenderDefaults(),
        homeDirectory: tmp.appendingPathComponent("check-render-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-render-token-cache-\(id).json", isDirectory: false)
    )
}

/// 토큰 소모량 행이 실제로 그려지는 상태의 토큰 스토어. 스캔 없이 영속 스냅샷 복원 경로(init)로
/// currentMonthUsage 를 채운다 — month 가 현재 KST 월이어야 복원되므로 TokenUsageMonthKey.current() 를 쓴다.
@MainActor
private func seededTokenStore() -> TokenUsageStore {
    let defaults = isolatedRenderDefaults()
    let usage = TokenUsageMonthly(
        month: TokenUsageMonthKey.current(),
        claudeInput: 8_460_869, claudeOutput: 35_849_782,
        claudeCacheRead: 4_165_692_507, claudeCacheCreation: 200_802_730,
        codexInput: 145_068_307, codexOutput: 623_160
    )
    if let data = try? JSONEncoder().encode(usage) {
        defaults.set(data, forKey: TokenUsageStore.snapshotKey)
    }
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: defaults,
        homeDirectory: tmp.appendingPathComponent("check-render-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-render-token-cache-\(id).json", isDirectory: false)
    )
}

/// 토큰 소모량 행(악센트 미광 박스)이 헤더와 팀 카드 "사이"에 놓인 배치 렌더 — 위치·강조 스타일 회귀 지점.
@MainActor
@Test
func checkMenuViewRendersTokenRowBetweenHeaderAndTeamSnapshot() throws {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = makeTeamStore(members: presenceMembers(now: now), now: now, tokenUsage: seededTokenStore())

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    if let path = ProcessInfo.processInfo.environment["CHECK_TOKEN_ROW_SNAPSHOT_PATH"] {
        try png.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
@Test
func tokenUsageRowKeepsBoardEntryWhenMonthlyUsageIsZero() throws {
    // 회귀 지점: 토큰 순위판으로 가는 유일한 버튼(person.2)이 '이번 달 내 소모량 > 0' 행 안에만 있어서,
    // AI CLI 를 아직 쓰지 않는 팀원(디자이너·PM)·신규 설치는 팝오버 어디에서도 순위판에 들어갈 수 없었다.
    // 순위판은 앱 사용자 전체 공개 보드인 데다, 월 이동(‹ ›)과 내 사용량 공개/비공개 토글은 **그 안에만**
    // 있어서 README 가 조건 없이 안내하는 기능 두 개가 통째로 도달 불가였다.
    let empty = inertTokenStore()
    #expect((empty.currentMonthUsage?.total ?? 0) == 0)

    // 소모량이 0이어도 순위판 진입 행이 그려진다(높이 > 0).
    let entryHeight = try #require(renderedPixelHeight(CheckTokenUsageRow(store: empty, onOpenBoard: {})))
    #expect(entryHeight > 0)
    // 높이는 소모량 행과 같다 — 창 높이 예산(CheckMenuView.tokenUsageRowHeight)이 두 경우 모두 그대로 맞는다.
    let usageHeight = try #require(renderedPixelHeight(CheckTokenUsageRow(store: seededTokenStore(), onOpenBoard: {})))
    #expect(entryHeight == usageHeight)

    // 콜백이 없는 단독 사용(순위판이 없는 문맥)에서는 예전처럼 아무것도 그리지 않는다.
    #expect(CheckTokenUsageRow(store: empty).onOpenBoard == nil)

    // 팝오버 홈에도 실제로 얹힌다(육안 확인 PNG). 이 자리를 눌러야 순위판 → 월 이동/공개 토글로 갈 수 있다.
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let home = makeTeamStore(members: presenceMembers(now: now), now: now, tokenUsage: inertTokenStore())
    let png = try renderPNG(CheckMenuView(store: home))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "token-board-entry-no-usage")

    // 진입 행이 늘 그려지므로 창 높이 상한(≤700pt)도 함께 고정한다(목록이 큰 팀 조합).
    let bigTeam = makeTeamStore(members: steadyMembers(count: 10), now: now, tokenUsage: inertTokenStore())
    let pixelHeight = try #require(renderedPixelHeight(CheckMenuView(store: bigTeam)))
    #expect(Double(pixelHeight) / 2.0 <= 700.0)
}

// MARK: - D2: 이번 달 AI 토큰 보드 렌더 (전체 공개)

/// 토큰 보드 페이지가 열린 로그인 스토어. 전체 공개라 행이 자체 완결(이름/아바타)이고 팀 무관이다 —
/// 타팀 사용자 이름도 섞어 6~8명을 채운다. 내 행("나" 칩)이 뜨도록 session.userID 를 한 엔트리와 맞춘다.
@MainActor
private func makeTokenBoardStore(memberCount: Int = 7) -> WorkTimerStore {
    let store = makeTeamStore(members: [], now: Date())
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
    // 축약 없는 전체 숫자 표기(콤마)와 정렬 순서(등수 배지 없음)·"나" 칩을 함께 보이도록 큰 값/0 과 타팀 이름을 섞는다.
    // 이름은 팀을 넘나든다(전체 공개) — 같은 팀/타팀 구분 없이 이번 달 소모량 순위로 한데 모인다.
    // 오늘분: 대부분 오늘 키(today)로 "오늘 +N" 이 뜨고, 한 명(u4)은 스테일 날짜(어제)라 "오늘 +0"으로 균일 표시된다.
    let today = TokenUsageDayKey.current()
    let stale = "2020-01-01"  // 오늘이 아닌 날짜 — "오늘 +0 토큰"으로 균일하게 표시되는지 확인.
    let pool: [TokenBoardEntry] = [
        TokenBoardEntry(userID: "u1", name: "영식", avatarURL: nil, total: 4_564_338_243, claudeInput: 4_000_000_000, claudeOutput: 500_000_000, claudeCacheRead: 60_000_000, claudeCacheCreation: 4_338_243, codexInput: 0, codexOutput: 0, todayTotal: 123_456_789, todayDate: today),
        TokenBoardEntry(userID: "u2", name: "타팀 김서연", avatarURL: nil, total: 2_100_000_000, claudeInput: 1_800_000_000, claudeOutput: 250_000_000, claudeCacheRead: 50_000_000, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, todayTotal: 42_000_000, todayDate: today),
        TokenBoardEntry(userID: "u-me", name: "yesung", avatarURL: nil, total: 1_234_567_890, claudeInput: 1_000_000_000, claudeOutput: 200_000_000, claudeCacheRead: 34_000_000, claudeCacheCreation: 567_890, codexInput: 0, codexOutput: 0, todayTotal: 7_654_321, todayDate: today),
        TokenBoardEntry(userID: "u4", name: "타팀 박도윤", avatarURL: nil, total: 640_000_000, claudeInput: 600_000_000, claudeOutput: 40_000_000, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, todayTotal: 5_000_000, todayDate: stale),
        TokenBoardEntry(userID: "u5", name: "민수", avatarURL: nil, total: 89_000, claudeInput: 80_000, claudeOutput: 9_000, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, todayTotal: 1_234, todayDate: today),
        TokenBoardEntry(userID: "u6", name: "타팀 이하은", avatarURL: nil, total: 12_345, claudeInput: 12_345, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, todayTotal: 0, todayDate: today),
        TokenBoardEntry(userID: "u7", name: "지현", avatarURL: nil, total: 0, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, todayTotal: 0, todayDate: today),
        TokenBoardEntry(userID: "u8", name: "타팀 최시우", avatarURL: nil, total: 0, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, todayTotal: 0, todayDate: today)
    ]
    store.tokenBoard = Array(pool.prefix(memberCount))
    store.tokenBoardLoaded = true
    store.isTokenBoardVisible = true
    return store
}

@MainActor
@Test
func checkMenuViewRendersTokenBoardSnapshot() throws {
    // 카드 리디자인 시나리오: 타팀 이름 포함 6명(maxVisibleRows=6 정확히 채운 상한), 내 카드(u-me·"나" 칩) 포함.
    // 각 카드에 "이번 달 총량 + 오늘 +N 토큰" 2줄이 보인다. 육안 확인 PNG 저장.
    let png = try renderPNG(CheckMenuView(store: makeTokenBoardStore(memberCount: 6)))
    #expect(png.count > 0)
    // 육안 확인용 아티팩트를 스크래치 디렉터리에 저장한다(디렉터리 없으면 만들고, 실패는 무시).
    let dir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("token-board-cards.png"))
}

@MainActor
@Test
func checkMenuViewRendersTokenBoardTodaySnapshot() throws {
    // "오늘 +N" 표시 육안 확인 전용: 오늘 값이 담긴 6명(u4 는 스테일 날짜라 "오늘 +0"). 지정 경로에 PNG 저장 후 직접 Read 확인.
    let png = try renderPNG(CheckMenuView(store: makeTokenBoardStore(memberCount: 6)))
    #expect(png.count > 0)
    let dir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("token-board-today.png"))
}

@MainActor
@Test
func checkMenuViewRendersTokenBoardScrollCapSnapshot() throws {
    // 스크롤 상한 케이스: 8명(maxVisibleRows=6 초과)을 클립 모드로 그려(ImageRenderer 는 ScrollView 미지원) 상한 클립을 보인다.
    let store = makeTokenBoardStore(memberCount: 8)
    let png = try renderPNG(CheckMenuView(store: store, previewClipsOverflowList: true))
    #expect(png.count > 0)
    let dir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("token-board-cards-scroll.png"))
}

@MainActor
@Test
func tokenBoardWindowHeightWithinCap() throws {
    // 토큰 보드 페이지도 창 높이 상한(≤700pt) 안에 머문다. 스크롤 상한(maxVisibleRows 초과)까지 채운 최악을 검증한다.
    let store = makeTeamStore(members: [], now: Date())
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
    store.tokenBoard = (0..<12).map { i in
        TokenBoardEntry(userID: "u\(i)", name: "멤버\(i)", avatarURL: nil, total: (12 - i) * 1_000_000, claudeInput: (12 - i) * 1_000_000, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    }
    store.tokenBoardLoaded = true
    store.isTokenBoardVisible = true

    let pixelHeight = try #require(renderedPixelHeight(CheckMenuView(store: store)))
    // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
    #expect(Double(pixelHeight) / 2.0 <= 700.0)
}

// MARK: - U: 콕찌르기 패널 + 토큰 공개/비공개 토글 렌더

/// 콕찌르기 패널이 열린 로그인 스토어. 앱 사용자 전체 목록(본인 제외)이라 팀 무관 — 근무중/자리비움, 아바타 nil 섞기.
/// myselfWorking 으로 내 근무 상태를(찌르기 가능/안내줄) 시드하고, 한 명(u2)은 쿨타임 중(now+37)으로 비활성(흐린 아이콘) 상태를 재현한다.
/// 자리비움(isWorking==false) 엔트리는 대상 게이트로 찌르기 버튼이 비활성(흐린 아이콘)으로 그려진다.
@MainActor
private func makePokePanelStore(memberCount: Int = 5, myselfWorking: Bool = true, now: Date = Date()) -> WorkTimerStore {
    let store = makeTeamStore(members: [], now: now)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
    // 내 근무 상태 — snapshot.isWorking 으로 PokePanel 의 isMyselfWorking(안내줄/버튼 활성)을 시드한다.
    store.snapshot = WorkStatusSnapshot(status: myselfWorking ? .working : .offWork, elapsedSeconds: myselfWorking ? 3_600 : 0)
    let avatar = CheckMascotAssets.url(for: .neutral)
    // 근무중 2(영식·민수) + 자리비움 다수, 아바타는 첫 명만 이미지·나머지 이니셜. 이름은 팀을 넘나든다(전체 공개).
    let pool: [PokeDirectoryEntry] = [
        PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: avatar, isWorking: true),
        PokeDirectoryEntry(userID: "u2", name: "민수", avatarURL: nil, isWorking: true),
        PokeDirectoryEntry(userID: "u3", name: "지현", avatarURL: nil, isWorking: false),
        PokeDirectoryEntry(userID: "u4", name: "타팀 김서연", avatarURL: nil, isWorking: false),
        PokeDirectoryEntry(userID: "u5", name: "서준", avatarURL: nil, isWorking: false),
        PokeDirectoryEntry(userID: "u6", name: "하윤", avatarURL: nil, isWorking: true),
        PokeDirectoryEntry(userID: "u7", name: "타팀 박도윤", avatarURL: nil, isWorking: false),
        PokeDirectoryEntry(userID: "u8", name: "도현", avatarURL: nil, isWorking: false),
        PokeDirectoryEntry(userID: "u9", name: "예린", avatarURL: nil, isWorking: true),
        PokeDirectoryEntry(userID: "u10", name: "타팀 최시우", avatarURL: nil, isWorking: false)
    ]
    store.pokeDirectory = Array(pool.prefix(memberCount))
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    // 한 명(u2)은 쿨타임 중 — now+37 → 숫자 없이 흐린 비활성 아이콘으로 그려진다(잔여 초 미표시).
    store.pokeCooldownUntil = ["u2": now.addingTimeInterval(37)]
    return store
}

/// 콕찌르기/토큰 토글 육안 확인 PNG 를 스크래치 디렉터리에 poke-ui-<이름>.png 로 저장한다(실행은 통합 단계가 한다).
@MainActor
private func savePokeUISnapshot(_ png: Data, _ name: String) {
    let dir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("\(name).png"))
}

@MainActor
@Test
func checkMenuViewRendersPokePanelSnapshot() throws {
    // 콕찌르기 패널: 근무중 2·자리비움 3(내가 근무중이라 안내줄 없음), 한 명(민수)은 쿨타임 중(흐린 비활성 아이콘).
    // 자리비움 3인(지현·타팀 김서연·서준)은 대상 게이트로 찌르기 버튼이 흐린 비활성으로 그려진다(근무중 영식만 accent 활성).
    // 아바타(이미지 1 + 이니셜) · 상태 칩(근무중/자리비움) · 찌르기 버튼(accent 손가락 원형 / 흐린 비활성)이 함께 보인다.
    let now = Date()
    let png = try renderPNG(CheckMenuView(store: makePokePanelStore(memberCount: 5, myselfWorking: true, now: now)))
    #expect(png.count > 0)
    savePokeUISnapshot(png, "poke-ui-panel")
}

@MainActor
@Test
func checkMenuViewRendersPokePanelOffWorkSnapshot() throws {
    // 내가 비근무 — "근무 중일 때만 콕 찌를 수 있어요" 안내줄이 뜨고 모든 찌르기 버튼이 흐린 비활성 손가락 아이콘으로 보인다.
    let png = try renderPNG(CheckMenuView(store: makePokePanelStore(memberCount: 5, myselfWorking: false)))
    #expect(png.count > 0)
    savePokeUISnapshot(png, "poke-ui-offwork")
}

@MainActor
@Test
func checkMenuViewRendersTokenBoardPrivateSnapshot() throws {
    // 토큰 보드 비공개 상태: 헤더 눈 버튼이 eye.slash(비공개)로 바뀌고, 내 행(yesung·"나" 칩) 옆에 회색 "비공개" 칩이 붙는다.
    let store = makeTokenBoardStore(memberCount: 6)
    store.tokenUsagePublic = false
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    savePokeUISnapshot(png, "poke-ui-token-private")
}

@MainActor
@Test
func pokePanelWindowHeightWithinCap() throws {
    // 콕찌르기 패널도 창 높이 상한(≤700pt) 안에 머문다. 스크롤 상한(maxVisibleRows=7 초과)까지 채운 10인을 검증한다.
    let store = makePokePanelStore(memberCount: 10)
    let pixelHeight = try #require(renderedPixelHeight(CheckMenuView(store: store)))
    // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
    #expect(Double(pixelHeight) / 2.0 <= 700.0)
}

// MARK: - v0.2.11 U: 개인 기록 패널 · 토큰 월 이동 · 배너 재배치/배선

/// v0.2.11 육안 확인 PNG 를 스크래치 디렉터리에 v0211-<이름>.png 로 저장한다(실행은 통합 단계가 한다).
@MainActor
private func saveV0211Snapshot(_ png: Data, _ name: String) {
    let dir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("v0211-\(name).png"))
}

/// 히트맵 픽스처(결정적) — **지난주 한 주** 분량이라 어떤 칸도 3600초(한 시간)를 넘지 않는다.
/// 평일 10~18시는 시간을 꽉 채워 가장 진하고, 출근/점심 무렵은 반 칸, 저녁과 주말 낮은 얕게 깔린다 —
/// 농도 대비(0/얕음/반 칸/꽉 참)와 peakSlot 문구가 한눈에 확인되도록 만든다.
private func sampleWorkRhythmHeatmap() -> WorkRhythmHeatmap {
    var buckets = Array(
        repeating: Array(repeating: 0, count: WorkRhythmHeatmap.hourCount),
        count: WorkRhythmHeatmap.dayCount
    )
    for day in 0..<WorkRhythmHeatmap.dayCount {
        let isWeekday = day < 5
        for hour in 0..<WorkRhythmHeatmap.hourCount {
            if isWeekday, hour == 9 || hour == 12 || hour == 16 {
                buckets[day][hour] = 1_800             // 출근/점심/퇴근 무렵 — 반 칸
            } else if isWeekday, (10...11).contains(hour) || (13...15).contains(hour) {
                buckets[day][hour] = 3_600             // 꽉 채운 한 시간 — 가장 진한 칸
            } else if isWeekday, hour == 19 {
                buckets[day][hour] = 900 - day * 150   // 저녁에 잠깐 — 요일마다 옅기가 다르다
            } else if day == 5, (13...15).contains(hour) {
                buckets[day][hour] = 900               // 토요일 낮만 얕게
            } else if day == 6, (14...15).contains(hour) {
                buckets[day][hour] = 600               // 일요일은 더 얕게
            }
        }
    }
    let total = buckets.reduce(0) { $0 + $1.reduce(0, +) }
    return WorkRhythmHeatmap(buckets: buckets, totalSeconds: total)   // 34시간 25분
}

/// 회고 픽스처: 목표 40시간(미달) · 전주 대비 +3시간 12분 · 가장 많이 일한 날 월요일 6시간 45분.
/// 총 근무시간은 **히트맵 픽스처의 칸 합과 같은 값**을 쓴다 — 이제 둘이 같은 주를 말하므로, 한 화면에
/// 서로 다른 합이 나란히 놓이면(회고 32시간 · 히트맵 52시간) 그 자체가 결함으로 보인다.
private func sampleWeeklyRetro(totalSeconds: Int = sampleWorkRhythmHeatmap().totalSeconds) -> WeeklyRetro {
    WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_784_000_000),
        totalSeconds: totalSeconds,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: totalSeconds - (3 * 3_600 + 12 * 60),
        sessionCount: 12,
        busiestDayIndex: 0,
        busiestDaySeconds: 6 * 3_600 + 45 * 60
    )
}

/// 개인 기록 패널이 열린 로그인 스토어. withData=false 면 로드는 끝났지만 기록이 0인 빈 상태,
/// loaded=false 면 아직 로딩 중("불러오는 중…") 상태를 재현한다.
@MainActor
private func makeInsightsStore(withData: Bool = true, loaded: Bool = true) -> WorkTimerStore {
    let store = makeTeamStore(members: [], now: Date())
    store.teamGoalSeconds = 40 * 3_600
    store.heatmap = withData ? sampleWorkRhythmHeatmap() : .empty
    store.retro = withData ? sampleWeeklyRetro() : nil
    store.insightsLoaded = loaded
    store.isInsightsPanelVisible = true
    return store
}

@MainActor
@Test
func checkMenuViewRendersInsightsPanelSnapshot() throws {
    // 개인 기록 패널(데이터 있음): 회고 카드(지난주 34시간 25분 · 목표 40시간 미달 · 전주 대비 +3시간 12분 ·
    // 세션 12회 · 가장 많이 일한 날 월요일) + 지난주 요일×시간대 히트맵(월~일 7행 × 0/6/12/18 라벨) +
    // "가장 활발한 시간". 340pt 폭 안에서 24열 격자가 잘림 없이 수납되는지, 그리고 회고 카드의 총합과
    // 히트맵 칸 합이 같은 주를 말하는지 육안 확인한다.
    let store = makeInsightsStore()
    #expect(store.retro?.totalSeconds == store.heatmap.totalSeconds)
    // 문구 규약(순수 판정)도 함께 고정한다 — 데이터가 있으면 자리 문구가 아니라 본문을 그린다.
    #expect(InsightsEmptyMessage.text(hasLoaded: true, totalSeconds: store.heatmap.totalSeconds) == nil)
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "insights-panel")
}

@MainActor
@Test
func checkMenuViewRendersInsightsEmptySnapshot() throws {
    // 개인 기록 빈 상태: 로드는 끝났지만 지난주 누적이 0 → "지난주 근무 기록이 없어요"(syncMessage 재사용 금지).
    let store = makeInsightsStore(withData: false, loaded: true)
    store.syncMessage = "동기화됨"
    #expect(InsightsEmptyMessage.text(hasLoaded: true, totalSeconds: 0) == InsightsEmptyMessage.noData)
    // 본문(회고 카드 + 히트맵)이 둘 다 지난주 기준이 된 뒤로, 자리 문구도 지난주를 말해야 한다 —
    // 이번 주에만 근무한 사용자(가입 첫 주)에게 "아직 기록이 쌓이지 않았어요"는 거짓이다(헤더는 이번 주를 센다).
    #expect(InsightsEmptyMessage.noData == InsightsEmptyMessage.noRetro)
    // 로드 전에는 동기화 문구가 아니라 "불러오는 중…" 이어야 한다(전면 감사 지적 반영).
    #expect(InsightsEmptyMessage.text(hasLoaded: false, totalSeconds: 0) == InsightsEmptyMessage.loading)

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "insights-empty")

    // 로딩 중 상태도 같은 자리에 그려지는지 확인한다.
    let loadingPNG = try renderPNG(CheckMenuView(store: makeInsightsStore(withData: false, loaded: false)))
    #expect(loadingPNG.count > 0)
    saveV0211Snapshot(loadingPNG, "insights-loading")
}

@MainActor
@Test
func checkMenuViewRendersInsightsRunningSessionThatCrossedTheWeekSnapshot() throws {
    // 서버 조회는 완료 세션만 준다(ended_at not null). 주 경계를 넘겨 아직 끝나지 않은 근무(일요일 밤 시작)의
    // 지난주 몫이 통째로 사라지지 않도록 진행 세션도 함께 집계한다 — 이번 주로 넘어간 뒷부분은 잘린다.
    let now = Date(timeIntervalSince1970: 1_784_000_000)   // 고정 시각(렌더 결정성)
    let window = try #require(WorkInsightsWeekWindow.lastWeek(now: now))
    let computed = WorkInsightsComputation.build(
        rows: [], now: now, goalSeconds: 40 * 3_600,
        ongoingStart: window.end.addingTimeInterval(-2 * 3_600)   // 지난주 일요일 22:00 출근 → 지난주 몫 2시간
    )
    #expect(computed.heatmap.totalSeconds == 2 * 3_600)
    // 회고와 히트맵이 같은 주라 합도 같다.
    #expect(computed.retro?.totalSeconds == computed.heatmap.totalSeconds)
    // 자리 문구가 아니라 본문(회고 카드 + 히트맵)을 그린다.
    #expect(InsightsEmptyMessage.text(hasLoaded: true, totalSeconds: computed.heatmap.totalSeconds) == nil)

    let store = makeInsightsStore(withData: false, loaded: true)
    store.heatmap = computed.heatmap
    store.retro = computed.retro
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "insights-running-across-week")
}

@MainActor
@Test
func checkMenuViewRendersInsightsFailureSnapshot() throws {
    // 회귀 지점: 조회 실패에 상태가 없어 "불러오는 중…"이 팝오버를 닫을 때까지 남았다(진행중과 실패가 같은 문구).
    // 이제 실패는 실패 문구 + [다시 시도] 로 갈라진다 — 토큰 보드(isLoading)와 같은 대칭.
    #expect(InsightsEmptyMessage.text(hasLoaded: false, hasFailed: false, totalSeconds: 0) == InsightsEmptyMessage.loading)
    #expect(InsightsEmptyMessage.text(hasLoaded: false, hasFailed: true, totalSeconds: 0) == InsightsEmptyMessage.loadFailed)
    // 회귀 지점: (로드 완료 + 실패 + 누적 0) 조합에서 "아직 기록이 쌓이지 않았어요"를 사실처럼 단정하고
    // 그 옆에 [다시 시도]까지 붙어 모순된 화면이 됐다. insightsLoaded 는 성공 후 false 로 돌아가지 않으므로
    // 이 조합은 실제로 성립한다 — 가입 첫날 0건으로 성공 로드해 둔 뒤(스냅샷 유지) 며칠 뒤 조회가 실패한 경우다.
    // 서버에는 한 주치 기록이 있는데 "기록 없음"으로 단정하면 안 된다 → 실패 문구로 갈라진다.
    #expect(InsightsEmptyMessage.text(hasLoaded: true, hasFailed: true, totalSeconds: 0) == InsightsEmptyMessage.loadFailed)
    // 실패하지 않은 로드 완료 + 0 은 그대로 "기록 없음"이다(정확한 단정).
    #expect(InsightsEmptyMessage.text(hasLoaded: true, hasFailed: false, totalSeconds: 0) == InsightsEmptyMessage.noData)
    // 보여 줄 기록이 남아 있으면 실패해도 자리 문구로 덮지 않는다(직전 스냅샷을 계속 보여 준다).
    #expect(InsightsEmptyMessage.text(hasLoaded: true, hasFailed: true, totalSeconds: 3_600) == nil)

    let store = makeInsightsStore(withData: false, loaded: false)
    store.insightsFailed = true
    store.syncMessage = "동기화됨"
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "insights-failed")

    // 실패 자리 문구 + 재시도 버튼이 붙어도 창 높이 상한(≤700pt)은 지킨다.
    let pixelHeight = try #require(renderedPixelHeight(CheckMenuView(store: store)))
    #expect(Double(pixelHeight) / 2.0 <= 700.0)

    // 첫 로드는 성공했지만(0건) 이후 조회가 실패한 상태 — 화면도 실패 문구여야 한다("기록 없음" 단정 금지).
    let staleStore = makeInsightsStore(withData: false, loaded: true)
    staleStore.insightsFailed = true
    let stalePNG = try renderPNG(CheckMenuView(store: staleStore))
    #expect(stalePNG.count > 0)
    saveV0211Snapshot(stalePNG, "insights-loaded-then-failed")
    // 같은 (loaded, 0건) 인데 실패 표시가 붙었으므로 성공 빈 상태와는 다른 그림이다(문구가 갈렸다는 증거).
    let emptyPNG = try renderPNG(CheckMenuView(store: makeInsightsStore(withData: false, loaded: true)))
    #expect(stalePNG != emptyPNG)
}

/// 푸터 동기화 문구 폭 예산(순수 계산) 회귀 고정.
/// v0.2.11 초안이 푸터에 다섯 번째 버튼을 세워 문구 슬롯이 125→90pt 로 줄었고,
/// "자리 비움으로 자동 근무종료됨"(121pt)이 잘려 핵심어 '근무종료됨'을 잃었다.
/// 4버튼으로 되돌렸고, 그래도 넘치는 긴 문구는 축소로 담는다.
@MainActor
@Test
func footerSyncMessageFitsWithinButtonBudget() {
    // 실측(NSFont .caption2 = 10pt) 폭. 렌더 환경과 무관하게 상수로 못 박아 회귀를 잡는다.
    let autoCloseMessage: CGFloat = 121  // "자리 비움으로 자동 근무종료됨"

    // 5버튼(v0.2.11 초안)에서는 축소 없이는 들어가지 않았다 — 결함의 원인.
    #expect(FooterWidthBudget.messageWidth(iconButtonCount: 5) < autoCloseMessage)

    // 4버튼(현재)에서는 축소 없이 온전히 들어간다.
    #expect(FooterWidthBudget.messageWidth(iconButtonCount: 4) >= autoCloseMessage)

    // 실제로 쓰는 가장 긴 문구(무소속 안내 175.9pt)까지 축소 범위 안에서 말줄임 없이 담긴다.
    #expect(FooterWidthBudget.fittingMessageWidth(iconButtonCount: 4) >= FooterWidthBudget.longestMessageWidth)
    // 버튼을 하나 더 세우면 그 보장이 곧바로 깨진다(이 테스트가 다섯 번째 버튼을 막는 장치다).
    #expect(FooterWidthBudget.fittingMessageWidth(iconButtonCount: 5) < FooterWidthBudget.longestMessageWidth)
}

@MainActor
@Test
func checkMenuViewRendersInsightsRetroBannerSnapshot() throws {
    // 회고 배너: 팝오버 최상단(UpdateBanner 아래)에 "지난주 근무 기록이 준비됐어요" + [보기] + 닫기(X).
    let store = makeTeamStore(members: presenceMembers(now: Date()), now: Date())
    store.retro = sampleWeeklyRetro()
    store.showsRetroBanner = true

    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "retro-banner")
}

@MainActor
@Test
func updateBannerAppearsOnTheNextPopoverAfterTheRetroBannerWasShownOnce() throws {
    // 회귀 지점: 회고 배너가 소비되지 않아 팝오버를 열 때마다 되살아났고, '배너는 한 번에 하나(retro > update)'
    // 규칙 때문에 새 버전 안내 배너가 그 주 내내 한 번도 그려지지 않았다(앱 안에서 업데이트로 가는 유일한 경로).
    let now = Date()
    let store = makeTeamStore(members: steadyMembers(count: 4), now: now, tokenUsage: seededTokenStore())
    store.retro = sampleWeeklyRetro()
    store.showsRetroBanner = true

    // 1) 첫 팝오버: 새 버전이 있어도 회고가 이긴다(높이는 회고 배너 하나만큼).
    let withRetro = try #require(renderedPixelHeight(CheckMenuView(store: store, previewUpdateBanner: true)))

    // 뷰가 배너를 그리며 이번 주 몫을 소비하고(onAppear), 사용자가 아무것도 누르지 않은 채 팝오버를 닫는다.
    store.markRetroBannerDisplayed()
    store.setMenuPresented(false)
    #expect(!store.showsRetroBanner)

    // 2) 다음 팝오버 오픈의 배너 판정 — 회고는 이번 주 몫을 이미 썼으므로 올라오지 않는다.
    store.isMenuPresented = true
    store.evaluateRetroBanner()
    #expect(!store.showsRetroBanner)

    // 그 자리를 새 버전 안내 배너가 쓴다(회고 배너 54pt 보다 높은 81pt 배너라 창이 더 자란다).
    let withUpdate = try #require(renderedPixelHeight(CheckMenuView(store: store, previewUpdateBanner: true)))
    #expect(withUpdate > withRetro)
}

@MainActor
@Test
func insightsPanelWindowHeightWithinCap() throws {
    // 개인 기록 패널도 창 높이 상한(≤700pt) 안에 머문다. 회고 카드 + 7×24 히트맵이 모두 찬 최대 상태를 검증한다.
    let pixelHeight = try #require(renderedPixelHeight(CheckMenuView(store: makeInsightsStore())))
    // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
    #expect(Double(pixelHeight) / 2.0 <= 700.0)
}

@MainActor
@Test
func checkMenuViewRendersTokenBoardPastMonthSnapshot() throws {
    // 토큰 순위판 과거 달: 제목이 "N월 AI 토큰 소모량"으로 바뀌고 › 는 비활성(미래 불가), ‹ 는 계속 가능.
    let now = Date()
    let currentMonth = TokenUsageMonthKey.current(now)
    let pastMonth = TokenBoardMonthNavigator.step(currentMonth, by: -2, now: now)
    #expect(pastMonth < currentMonth)
    // 과거 달이면 앞으로 갈 수 있고(› 활성), 현재 달이면 갈 수 없다(› 비활성).
    #expect(TokenBoardMonthNavigator.canStepForward(from: pastMonth, now: now))
    #expect(!TokenBoardMonthNavigator.canStepForward(from: currentMonth, now: now))

    let store = makeTokenBoardStore(memberCount: 5)
    store.tokenBoardMonth = pastMonth
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "token-board-past-month")

    // 현재 달(› 비활성) 상태도 같은 헤더 배치로 그려지는지 나란히 확인한다.
    let currentStore = makeTokenBoardStore(memberCount: 5)
    let currentPNG = try renderPNG(CheckMenuView(store: currentStore))
    #expect(currentPNG.count > 0)
    saveV0211Snapshot(currentPNG, "token-board-current-month")
}

@MainActor
@Test
func checkMenuViewRendersTokenBoardPastMonthEmptySnapshot() throws {
    // 과거 달에 기록이 없으면 '아직 아무도 안 올림'이 아니라 "이 달에는 기록이 없어요".
    #expect(TokenBoardEmptyMessage.text(hasLoaded: true, fallbackStatus: "동기화됨", isCurrentMonth: false) == TokenBoardEmptyMessage.noPastRecords)
    #expect(TokenBoardEmptyMessage.text(hasLoaded: true, fallbackStatus: "동기화됨", isCurrentMonth: true) == TokenBoardEmptyMessage.noUploads)
    // 로드 전/실패면 월과 무관하게 동기화 상태 문구를 그대로 쓴다(기존 규약 유지).
    #expect(TokenBoardEmptyMessage.text(hasLoaded: false, fallbackStatus: "로그인 필요", isCurrentMonth: false) == "로그인 필요")

    let store = makeTokenBoardStore(memberCount: 5)
    store.tokenBoard = []
    store.tokenBoardLoaded = true
    store.tokenBoardMonth = TokenBoardMonthNavigator.step(TokenUsageMonthKey.current(), by: -3)
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "token-board-past-empty")
}

@MainActor
@Test
func longSessionBannerSitsAboveHeaderWithoutCoveringStopButton() throws {
    // 결함3 회귀 지점: 배너가 헤더 카드 overlay 였을 때는 카드 높이가 그대로라 '근무 종료' 버튼이 가려졌다.
    // 형제 뷰로 올라간 지금은 배너만큼 창이 높아져야 한다(= 헤더를 덮지 않는다는 실측 증거).
    let base = try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore())))
    let withBanner = try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewLongSessionBanner: true)))
    #expect(withBanner > base)
    // 배너가 얹혀도 창 높이 상한(≤700pt)은 지킨다.
    #expect(Double(withBanner) / 2.0 <= 700.0)

    let png = try renderPNG(CheckMenuView(store: makeSignedInStore(), previewLongSessionBanner: true))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "long-session-above-header")
}

@MainActor
@Test
func checkMenuViewRendersRecoveryBannersSnapshot() throws {
    // 결함4 배선: 자리 비움 자동 마감 [되돌리기] 배너가 헤더 아래에 인라인으로 뜬다.
    let now = Date()

    // 자동 마감 직후 — 비근무 + 유예(10분) 안이라 [되돌리기] 가 뜬다.
    let undoStore = makeTeamStore(members: presenceMembers(now: now), now: now)
    undoStore.lastAutoClosedSessionID = "11111111-2222-3333-4444-555555555555"
    undoStore.lastAutoClosedStartedAt = now.addingTimeInterval(-7_200)
    undoStore.lastAutoClosedAt = now.addingTimeInterval(-30)
    undoStore.syncMessage = "자리 비움으로 자동 근무종료됨"
    #expect(undoStore.canUndoAutoClose(now: now))
    // 뷰는 매초 판정하지 않고 스토어가 밀어 넣은 배너 상태만 읽는다(앱에서는 자동 마감/티커가 세운다).
    undoStore.refreshTimedBanner(now: now)
    #expect(undoStore.timedBanner == .undoAutoClose)

    let undoPNG = try renderPNG(CheckMenuView(store: undoStore))
    #expect(undoPNG.count > 0)
    saveV0211Snapshot(undoPNG, "recovery-banners")

    // 근무를 시작하면 되돌리기 대상이 끊겨 배너가 함께 사라진다(유예형 배너는 비근무 전용).
    let workingStore = makeTeamStore(members: presenceMembers(now: now), now: now)
    workingStore.startedAt = now.addingTimeInterval(-10)
    workingStore.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
    #expect(!workingStore.canUndoAutoClose(now: now))
    workingStore.refreshTimedBanner(now: now)
    #expect(workingStore.timedBanner == nil)

    // 배너는 헤더 아래로 자란다 — 배선 전(배너 0건) 대비 창이 높아지는지 실측한다.
    let plain = try #require(renderedPixelHeight(CheckMenuView(store: makeTeamStore(members: presenceMembers(now: now), now: now))))
    let withBanner = try #require(renderedPixelHeight(CheckMenuView(store: undoStore)))
    #expect(withBanner > plain)
    #expect(Double(withBanner) / 2.0 <= 700.0)
}

/// 히트맵 그리드는 View 라 타입 자체가 MainActor 로 추론된다 — 정적 상수(셀 크기/요일 라벨) 접근을 위해 @MainActor 로 둔다.
@MainActor
@Test
func heatmapCellColorScalesWithBucketDensity() {
    // 히트맵 칸 농도 규약(순수 판정): 분모는 **3600초 고정**이다. 지난주 한 주만 집계하므로 한 칸의 최대가
    // 정확히 한 시간이고, 그래서 진하기가 곧 "그 시간대를 얼마나 채웠는지"다.
    // 회귀 지점: 예전엔 자기 최대 칸(maxBucketSeconds) 대비 상대 농도라 8주 합산에서 다른 주 기여가 얹혀
    // "하루 종일 일한 일요일인데 시간대마다 색이 다르다"가 됐고, 기준도 사람마다·주마다 흔들렸다.
    #expect(WorkRhythmHeatmapGrid.fullCellSeconds == 3_600)
    #expect(WorkRhythmHeatmapGrid.intensity(seconds: 0) == 0)
    #expect(WorkRhythmHeatmapGrid.intensity(seconds: 1_800) == 0.5)
    #expect(WorkRhythmHeatmapGrid.intensity(seconds: 3_600) == 1)
    // 1초라도 일했으면 0 칸과 구분돼야 한다(색은 최소 0.20 농도로 시작한다).
    #expect(WorkRhythmHeatmapGrid.intensity(seconds: 1) > 0)
    // 3600 을 넘는 이상값이 들어와도 1로 클램프한다.
    #expect(WorkRhythmHeatmapGrid.intensity(seconds: 90_000) == 1)
    // 색: 0초 칸만 fieldFill 이고, 근무가 있는 칸은 accent 농도로 갈린다(반 칸 ≠ 꽉 찬 칸).
    #expect(WorkRhythmHeatmapGrid.color(seconds: 0) == CheckTheme.fieldFill)
    #expect(WorkRhythmHeatmapGrid.color(seconds: 1_800) != CheckTheme.fieldFill)
    #expect(WorkRhythmHeatmapGrid.color(seconds: 1_800) != WorkRhythmHeatmapGrid.color(seconds: 3_600))
    // 클램프가 색에서도 성립한다 — 3600 초과 입력은 꽉 찬 칸과 같은 색이다(1.0 을 넘지 않는다).
    #expect(WorkRhythmHeatmapGrid.color(seconds: 7_200) == WorkRhythmHeatmapGrid.color(seconds: 3_600))
    // 요일 라벨은 0=월 규약을 따른다(회고 busiestDayIndex 와 같은 인덱스).
    #expect(WorkRhythmHeatmapGrid.dayLabels.first == "월")
    #expect(WorkRhythmHeatmapGrid.dayLabels.last == "일")
    // 격자 총 폭(요일 라벨 + 24열 + 간격)이 패널 콘텐츠 폭(340 - 12*2 - 12*2 = 292pt) 안에 들어간다.
    let gridWidth = WorkRhythmHeatmapGrid.labelWidth
        + WorkRhythmHeatmapGrid.cellGap
        + CGFloat(WorkRhythmHeatmap.hourCount) * WorkRhythmHeatmapGrid.cellSize
        + CGFloat(WorkRhythmHeatmap.hourCount - 1) * WorkRhythmHeatmapGrid.cellGap
    #expect(gridWidth <= 292)
}

// MARK: - 창 높이 상한(≤700pt) — 배너·토큰 행·패널이 겹치는 최악 조합

/// 목록 행수 예산(순수 계산) 규약. 위쪽에 얹힌 높이를 행 단위로 올림 환산해 그만큼 줄이고, 최소 2행은 남긴다.
@Test
func listRowBudgetShrinksVisibleRowsByStackedChromeHeight() {
    // 아무것도 얹히지 않으면 기본 상한 그대로.
    #expect(ListRowBudget.visibleRows(maxVisibleRows: 6, rowHeight: 58, rowSpacing: 10, extraChromeHeight: 0) == 6)
    // 한 행(68pt)보다 작게 먹어도 한 행은 양보한다(올림).
    #expect(ListRowBudget.visibleRows(maxVisibleRows: 6, rowHeight: 58, rowSpacing: 10, extraChromeHeight: 53) == 5)
    #expect(ListRowBudget.visibleRows(maxVisibleRows: 6, rowHeight: 58, rowSpacing: 10, extraChromeHeight: 68) == 5)
    #expect(ListRowBudget.visibleRows(maxVisibleRows: 6, rowHeight: 58, rowSpacing: 10, extraChromeHeight: 69) == 4)
    // 아무리 많이 먹어도 최소 행수는 지킨다(목록이 목록으로 보이도록).
    #expect(ListRowBudget.visibleRows(maxVisibleRows: 6, rowHeight: 58, rowSpacing: 10, extraChromeHeight: 10_000) == ListRowBudget.minVisibleRows)
}

/// 배너/토큰 행/패널이 겹치는 조합에서도 팝오버가 700pt 상한을 넘지 않는지 실측한다.
/// 회귀 지점: 예전엔 배너가 겹겹이 쌓이고(회고+되돌리기+…) 목록 상한이 고정이라 최대 883pt 까지
/// 자라 13" 맥북에서 푸터(로그아웃/앱 종료)가 화면 밖으로 나갔다. 기존 높이 테스트가 못 잡은 이유는
/// 전부 inertTokenStore(토큰 행 0pt)를 쓰고 배너·패널을 조합하지 않았기 때문이라, 여기서는 실제 토큰 행이
/// 그려지는 seededTokenStore 로 최악 조합을 만든다.
@MainActor
@Test
func popoverStaysWithinHeightCapForWorstBannerAndPanelCombinations() throws {
    let now = Date()

    func teamStore(members: Int = 8) -> WorkTimerStore {
        let store = makeTeamStore(members: steadyMembers(count: members), now: now, tokenUsage: seededTokenStore())
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
        return store
    }
    func addUndoBanner(_ store: WorkTimerStore) {
        store.lastAutoClosedSessionID = "11111111-2222-3333-4444-555555555555"
        store.lastAutoClosedStartedAt = now.addingTimeInterval(-7_200)
        store.lastAutoClosedAt = now
        // 배너 노출은 스토어가 밀어 넣는 상태값이다(뷰가 매초 판정하지 않는다).
        store.refreshTimedBanner(now: now)
    }
    func addRetroBanner(_ store: WorkTimerStore) {
        store.retro = sampleWeeklyRetro()
        store.showsRetroBanner = true
    }
    func working(_ store: WorkTimerStore) {
        store.startedAt = now.addingTimeInterval(-10)
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
        store.refreshTimedBanner(now: now)
    }

    var cases: [(String, Int)] = []
    func measure(_ label: String, _ view: some View) throws {
        let pixels = try #require(renderedPixelHeight(view))
        cases.append((label, pixels))
        #expect(Double(pixels) / 2.0 <= 700.0, "\(label) 이 700pt 상한을 넘었습니다: \(Double(pixels) / 2.0)pt")
    }

    // (a) 홈: 토큰 행 + 회고/되돌리기 배너 + 새 버전 배너(가장 많이 겹치는 상황).
    let home = teamStore()
    addRetroBanner(home)
    addUndoBanner(home)
    try measure("home+banners", CheckMenuView(store: home, previewUpdateBanner: true))

    // (b) 홈: 12시간 확인 배너 + 목표 편집 인라인 행(헤더가 가장 부푸는 조합).
    let longSession = teamStore()
    working(longSession)
    longSession.isLongSessionPromptActive = true
    try measure("home+longSession+goalEditor", CheckMenuView(store: longSession, previewGoalEditing: true))

    // (c) 토큰 순위판(스크롤 상한 초과 12행) + 배너.
    let board = teamStore()
    addRetroBanner(board)
    addUndoBanner(board)
    board.tokenBoard = (0..<12).map { i in
        TokenBoardEntry(userID: "u\(i)", name: "멤버\(i)", avatarURL: nil, total: (12 - i) * 1_000_000, claudeInput: (12 - i) * 1_000_000, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    }
    board.tokenBoardLoaded = true
    board.isTokenBoardVisible = true
    try measure("tokenBoard+banners", CheckMenuView(store: board, previewUpdateBanner: true))

    // (d) 콕찌르기 패널(10인) + 배너.
    let poke = teamStore()
    addRetroBanner(poke)
    addUndoBanner(poke)
    poke.pokeDirectory = (0..<10).map { i in
        PokeDirectoryEntry(userID: "p\(i)", name: "사람\(i)", avatarURL: nil, isWorking: i % 2 == 0)
    }
    poke.pokeDirectoryLoaded = true
    poke.isPokePanelVisible = true
    poke.pokeNotice = "자리 비움 중인 사용자는 찌를 수 없어요"
    try measure("poke+banners", CheckMenuView(store: poke, previewUpdateBanner: true))

    // (e) 리그 패널(12팀) + 배너.
    let league = teamStore()
    addRetroBanner(league)
    addUndoBanner(league)
    league.leaderboard = manyLeaderboardEntries(count: 12)
    league.isLeaderboardVisible = true
    try measure("league+banners", CheckMenuView(store: league, previewUpdateBanner: true))

    // (f) 개인 기록 패널(회고 카드 + 7×24 히트맵) + 되돌리기/새 버전 배너.
    let insights = teamStore()
    insights.teamGoalSeconds = 40 * 3_600
    insights.heatmap = sampleWorkRhythmHeatmap()
    insights.retro = sampleWeeklyRetro()
    insights.insightsLoaded = true
    insights.isInsightsPanelVisible = true
    addUndoBanner(insights)
    try measure("insights+banners", CheckMenuView(store: insights, previewUpdateBanner: true))

    // 모든 조합이 측정됐는지(렌더 실패로 조용히 건너뛰지 않았는지) 확인한다.
    #expect(cases.count == 6)
}

/// 배너는 한 번에 하나만 그린다 — 겹쳐 쌓이면 창이 상한을 넘기 때문. 회고 배너가 떠 있어도 12시간 확인
/// 배너가 있으면 그쪽이 이기고, 창 높이는 배너 하나만큼만 자란다.
@MainActor
@Test
func onlyOneBannerIsDrawnAtATime() throws {
    let now = Date()
    let base = makeTeamStore(members: steadyMembers(count: 4), now: now, tokenUsage: seededTokenStore())
    let plain = try #require(renderedPixelHeight(CheckMenuView(store: base)))

    let oneBanner = makeTeamStore(members: steadyMembers(count: 4), now: now, tokenUsage: seededTokenStore())
    oneBanner.retro = sampleWeeklyRetro()
    oneBanner.showsRetroBanner = true
    let withOne = try #require(renderedPixelHeight(CheckMenuView(store: oneBanner)))
    #expect(withOne > plain)

    // 회고 + 새 버전 + 되돌리기 세 후보가 모두 자격을 갖춰도 실제로 그려지는 건 하나뿐이라
    // 창 높이는 '가장 급한 배너 하나'만큼만 늘어난다(되돌리기가 회고/업데이트를 이긴다).
    let manyCandidates = makeTeamStore(members: steadyMembers(count: 4), now: now, tokenUsage: seededTokenStore())
    manyCandidates.retro = sampleWeeklyRetro()
    manyCandidates.showsRetroBanner = true
    manyCandidates.lastAutoClosedSessionID = "11111111-2222-3333-4444-555555555555"
    manyCandidates.lastAutoClosedStartedAt = now.addingTimeInterval(-7_200)
    manyCandidates.lastAutoClosedAt = now
    manyCandidates.refreshTimedBanner(now: now)
    let withMany = try #require(renderedPixelHeight(CheckMenuView(store: manyCandidates, previewUpdateBanner: true)))
    #expect(withMany == withOne)
}

// MARK: - 과거 달 보드에는 "오늘 +N" 줄을 그리지 않는다

@MainActor
@Test
func tokenBoardRowOmitsTodayLineOutsideCurrentMonth() throws {
    // 회귀 지점: 행이 todayValue 를 무조건 그려, 6월 보드의 전 사용자 행에 "오늘 +0 토큰"이 붙었다
    // (과거 달은 서버 today 합산이 항상 0이라 '6월을 보는데 오늘'이라는 모순만 남는다).
    func entry(todayTotal: Int) -> TokenBoardEntry {
        TokenBoardEntry(
            userID: "u1", name: "영식", avatarURL: nil, total: 1_234_567,
            claudeInput: 1_234_567, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
            codexInput: 0, codexOutput: 0, todayTotal: todayTotal, todayDate: TokenUsageDayKey.current()
        )
    }
    // 이번 달(showsToday=true)에는 오늘 값이 실제로 그려지므로 값이 달라지면 픽셀도 달라진다.
    let currentA = try renderPNG(TokenBoardRowView(entry: entry(todayTotal: 4_321), showsToday: true).frame(height: 62))
    let currentB = try renderPNG(TokenBoardRowView(entry: entry(todayTotal: 9_876), showsToday: true).frame(height: 62))
    #expect(currentA != currentB)

    // 과거 달(showsToday=false)에는 줄 자체가 없으므로 오늘 값이 무엇이든 렌더가 동일하다.
    let pastA = try renderPNG(TokenBoardRowView(entry: entry(todayTotal: 4_321), showsToday: false).frame(height: 62))
    let pastB = try renderPNG(TokenBoardRowView(entry: entry(todayTotal: 9_876), showsToday: false).frame(height: 62))
    #expect(pastA == pastB)
    // 그리고 같은 값이어도 '오늘 줄 있음'과는 다른 그림이다(줄이 빠졌다는 증거).
    #expect(pastA != currentA)
}

// MARK: - 내 행에 "비공개" 칩이 붙어도 토큰 총량은 잘리지 않는다

@MainActor
@Test
func tokenBoardRowKeepsFullNumbersWhenPrivateChipCrowdsTheRow() throws {
    // 회귀 지점: 한 행의 폭 예산(패널 292pt)에서 [악센트바][아바타][이름]["나"]["비공개"] 가 앞자리를 다 먹어
    // 우측 10자리 총량이 '4,564,338,24…' 로 말줄임됐다 — 45억이 45억2천만처럼 읽히는 자릿수 오독이고,
    // 하필 사용자가 가장 주의 깊게 보는 '내 행'에서만 나타났다(비공개 칩은 내 행에만 붙는다).
    func entry(total: Int, todayTotal: Int) -> TokenBoardEntry {
        TokenBoardEntry(
            userID: "u1", name: "타팀 김서연", avatarURL: nil, total: total,
            claudeInput: total, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
            codexInput: 0, codexOutput: 0, todayTotal: todayTotal, todayDate: TokenUsageDayKey.current()
        )
    }
    func row(total: Int, todayTotal: Int) -> some View {
        TokenBoardRowView(
            entry: entry(total: total, todayTotal: todayTotal),
            isMe: true,
            showsPrivateChip: true,
            showsToday: true
        ).frame(height: 62)
    }
    // 실제 패널 행 폭(292pt = 팝오버 안쪽 폭)으로 그린다 — 340pt 보다 좁아 잘림이 먼저 드러나는 조건이다.
    let rowWidth: CGFloat = 292
    // 끝자리만 다른 두 총량. 말줄임되면 사라지는 자리라 잘린 렌더는 완전히 동일한 그림이 된다.
    let a = try renderPNG(row(total: 4_564_338_243, todayTotal: 123_360_493), width: rowWidth)
    let b = try renderPNG(row(total: 4_564_338_247, todayTotal: 123_360_493), width: rowWidth)
    #expect(a != b)
    // 둘째 줄("오늘 +N 토큰")도 같은 이유로 단위째 잘렸다 — 오늘 증가량의 끝자리 변화도 그림에 남아야 한다.
    let c = try renderPNG(row(total: 4_564_338_243, todayTotal: 123_360_497), width: rowWidth)
    #expect(a != c)
    saveV0211Snapshot(a, "token-row-private-chip")
}

@MainActor
@Test
func checkMenuViewRendersTokenBoardMonthNavSnapshot() throws {
    // 결함5 회귀 지점(육안 확인): 헤더에 chevron.left 두 개가 4pt 간격으로 나란히 놓여 뒤로/이전 달이
    // 구분되지 않았다. 이제 뒤로(‹)와 월 이동(◂ ▸) 사이에 세로 구분선이 있고 아이콘 모양도 다르다.
    let store = makeTokenBoardStore(memberCount: 4)
    store.tokenBoardMonth = TokenBoardMonthNavigator.step(TokenUsageMonthKey.current(), by: -1)
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "token-board-month-nav")

    // 제목이 가장 길어지는 경우(작년 → "YYYY년 M월")에도 헤더 한 줄이 무너지지 않는지 함께 확인한다 —
    // 구분선 + 월 이동 버튼이 늘어난 만큼 폭 여유가 줄었기 때문.
    let lastYear = TeamWeeklyGoal.kstCalendar.component(.year, from: Date()) - 1
    let yearStore = makeTokenBoardStore(memberCount: 4)
    yearStore.tokenBoardMonth = "\(lastYear)-12"
    #expect(TokenBoardMonthNavigator.displayTitle(yearStore.tokenBoardMonth) == "\(lastYear)년 12월")
    let yearPNG = try renderPNG(CheckMenuView(store: yearStore))
    #expect(yearPNG.count > 0)
    saveV0211Snapshot(yearPNG, "token-board-year-title")
}


// MARK: - 이관 마이그레이션이 v0.2.10 클라를 깨지 않는지(하위호환 · 데이터 소실 금지)

@Test
func tokenUsageDeviceMigrationKeepsLegacyLedgerIntact() throws {
    // 회귀 지점: 초안은 옛 표 token_usage_monthly 의 PK 를 (user_id, month, device_id) 로 바꾸고 legacy 행을
    // 전량 삭제했다. 그러면 아직 업데이트하지 않은 v0.2.10 클라의 `on_conflict=user_id,month` 업로드가
    // 42P10 으로 100% 실패하는데 그들의 이번 달 행은 이미 지워진 뒤라, 순위가 수일~수주간 어긋난다.
    // 수정된 설계: 옛 표는 손대지 않고 기기별 표를 새로 만들며, 보드 RPC 가 기기별 행이 없는 사용자만 옛 표로 폴백한다.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // checkTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let sql = try String(
        contentsOf: root.appendingPathComponent("supabase/migrations/20260726010000_token_usage_device.sql"),
        encoding: .utf8
    )

    // (1) 기기별 표를 새로 만든다 — 키는 (user_id, month, device_id).
    #expect(sql.contains("create table if not exists public.token_usage_device_monthly"))
    #expect(sql.contains("primary key (user_id, month, device_id)"))

    // (2) 옛 표는 한 줄도 건드리지 않는다(alter/delete/drop 금지) — v0.2.10 이 계속 정상 upsert 해야 한다.
    #expect(!sql.contains("alter table public.token_usage_monthly"))
    #expect(!sql.contains("delete from public.token_usage_monthly"))
    #expect(!sql.contains("drop table public.token_usage_monthly"))

    // (3) 과도기 손실 방지 + 이중 계상 금지: 두 출처를 사용자별로 짝지어 **큰 쪽 한 줄**만 쓴다.
    //     회귀 지점: 초안은 "기기별 행이 하나라도 있으면 옛 표 행을 통째로 버린다"(not exists) 였다. 그러면
    //     맥 A=v0.2.10(주력, 옛 표에만 씀) / 맥 B=v0.2.11(보조, 새 표에만 씀) 과도기에 B 가 한 번 올리는 순간
    //     A 의 사용량이 순위에서 영구 누락된다(A 를 아무리 더 써도 보드는 B 값에 고정).
    //     이제 옛 표는 사용자 전원에 대해 읽고(제외 조건 없음), 더하지 않고 총량이 큰 쪽을 고른다 —
    //     업그레이드 직후 같은 누적치가 두 표에 겹쳐 있어도 두 번 세지 않는다.
    // ("create table if not exists" 와 겹치지 않게 배제 서브쿼리 형태로만 본다.)
    #expect(!sql.contains("not exists ("))
    #expect(!sql.contains("union all"))  // 합치면 업그레이드 직후 이중 계상이 된다.
    #expect(sql.contains("from public.token_usage_device_monthly d"))
    #expect(sql.contains("from public.token_usage_monthly l"))
    #expect(sql.contains("full outer join legacy_totals g on g.uid = d.uid"))
    #expect(sql.contains("(d.uid is not null and coalesce(d.total, 0) >= coalesce(g.total, 0)) as prefer_device"))
    // 월 누적 필드는 두 출처에서 뒤섞이지 않게 전부 같은 prefer_device 로 고른다.
    for column in ["claude_input", "claude_output", "claude_cache_read", "claude_cache_creation",
                   "codex_input", "codex_output", "total"] {
        #expect(sql.contains("case when prefer_device then d_\(column) else g_\(column) end"))
    }

    // (3-1) '오늘 증가분'만은 행 단위 선택에서 떼어 두 출처의 큰 쪽을 쓴다.
    //     회귀 지점: today_total 까지 prefer_device(=월 총량 비교 결과)를 따라가면, 옛 표 총량이 훨씬 큰
    //     과도기(맥 A=v0.2.10 주력이지만 요즘 안 켬 / 맥 B=v0.2.11 오늘 종일 사용)에 옛 행이 선택되고
    //     그 행의 today_date 가 과거라 today 가 0 으로 떨어진다 → 사용자는 '오늘 +0 토큰'을 수일간 본다.
    //     두 출처 모두 서버 KST 오늘 필터를 이미 통과한 값이라 각각 참 오늘 총량 이하 → greatest 로도
    //     과다계상이 구조적으로 불가능하다.
    #expect(sql.contains("greatest(coalesce(d_today_total, 0), coalesce(g_today_total, 0))"))
    #expect(!sql.contains("case when prefer_device then d_today_total else g_today_total end"))

    // (4) 새 표에도 본인 행 select 정책이 있어야 PostgREST merge-duplicates upsert 가 403 나지 않는다.
    #expect(sql.contains("users read own device token usage"))

    // (5) 화석 제외는 **조회 중인 달에 기기 행이 있을 때만** 건다.
    //     회귀 지점: 제외 조건이 `(f.first_at is null or l.updated_at > f.first_at)` 뿐이었다. first_at 은
    //     달 무관 최솟값(= v0.2.11 로 올라온 시각)인데 앱은 **이번 달 기기 행만** 올리므로 지난달에는 기기 행이
    //     영원히 안 생긴다 → 지난달 옛 행은 updated_at 이 언제나 first_at 보다 과거라 전원 탈락하고, ‹ 로
    //     지난달을 보면 업그레이드한 사용자가 **본인 포함** 순위판에서 통째로 사라졌다(대체할 기기 합산이 없어
    //     merged 에 행 자체가 없으니 `or m.uid = auth.uid()` 자기 노출 보장도 무력). PostgreSQL 15 실측:
    //     6월 보드가 U1(6월 5억) 없이 U2 한 줄만 반환 → 수정 후 세 사용자 모두 반환, 7월 화석(9억) 제외는 유지.
    #expect(sql.contains("left join device_totals dm on dm.uid = l.user_id"))
    #expect(sql.contains("dm.uid is null"))
    #expect(sql.contains("or l.updated_at > f.first_at"))

    // (6) 화석 제외는 **이번 달에만**, 그리고 **첫 기기 행 이후 7일 유예를 지나서만** 건다.
    //     회귀 지점: 제외 조건이 `(dm.uid is null or f.first_at is null or l.updated_at > f.first_at)` 뿐이었다.
    //     판정식이 '옛 행이 first_at 이후로 갱신됐는가'인데, v0.2.11 클라는 옛 행이 자기 값보다 크면 옛 표를
    //     아예 쓰지 않으므로(WorkTimerStoreSync 의 mayWriteLegacy 게이트) 보조 맥의 첫 업로드 순간에는 항상
    //     l.updated_at < f.first_at 이 된다 → 아직 v0.2.10 인 주력 맥의 옛 행이 화석으로 오판돼 탈락하고,
    //     보드 총량이 보조 맥 값으로 폭락한다(200M → 2M). 이 마이그레이션이 '큰 쪽' 규칙으로 지키겠다고
    //     명시한 과도기 그 자체가 깨지는 것이다. 게다가 그 달이 지나면 옛 행은 다시 갱신될 일이 없어
    //     ‹ 로 지난달을 볼 때 손실이 영구화됐다(dm.uid 가 not null 이라 과거달 예외에도 안 걸린다).
    //     PostgreSQL 15 실측(수정 전 → 후): 이번 달 U1 2,000,000 → 200,000,000, 2026-06 U2 2,000,000 →
    //     200,000,000, 화석 대조군(U3, 유예 지난 갱신 끊긴 9억)은 3,000,000 그대로 유지.
    #expect(sql.contains("or now() - f.first_at <= interval '7 days'"))

    // (7) 지난 달 예외는 '살아 있는 구버전 맥이 있을 때'로 좁힌다 — 무조건 살리면 화석 정정이 영구 무발화다.
    //     회귀 지점: 조건이 `or p_month <> 이번 달` 이었다. 그러면 (6) 의 7일 유예 창과 월말에 이어 붙어
    //     화석 판정식 `l.updated_at > f.first_at` 이 평가되는 순간이 **영원히 없다** — 7/27 에 v0.2.11 로
    //     올라오면 유예가 8/3 까지 가고, 유예가 끝나는 순간 7월은 이미 '지난 달'이라 다시 통과한다.
    //     v0.2.11 클라는 옛 행이 자기 값보다 크면 쓰지 않으므로(mayWriteLegacy) 클라 자가정정도 없어,
    //     v0.2.9 의 과다계상(+수십억)이 그 달 순위판 1위에 영구히 박혔다(프로덕션 v0.2.10 대비 회귀 —
    //     v0.2.10 은 게이트 없이 옛 행을 덮어써 업그레이드 첫 업로드에 스스로 정정됐다).
    //     이제는 달로 가르지 않고 "그 계정에 기기 합산을 넘는 옛 행을 아직도 쓰는 맥이 있는가"로 가른다.
    //     PostgreSQL 15 실측(수정 전 → 후, 유예 지난 6월 보드): 화석 U1 3,000,000,000 → 100,000,000(기기 합산),
    //     과도기 U2(맥 A=v0.2.10 이 7월에도 계속 씀)는 200,000,000 그대로 보존, 그 달 기기 행이 없는 U3 의
    //     5월 폴백 500,000,000 과 유예 중 U4 의 900,000,000 도 그대로.
    #expect(!sql.contains("p_month <> to_char"))
    #expect(sql.contains("or lv.uid is not null"))
    #expect(sql.contains("left join legacy_live lv on lv.uid = l.user_id"))
    //     증거 요건 (b): 그 달 기기 합산보다 큰 옛 행일 것. 이게 없으면 v0.2.11 이 **자기가** 다음 달 옛 행을
    //     쓰는 순간(그 달엔 옛 행이 없어 게이트가 열린다) 스스로 증거를 만들어 자기 화석을 되살린다 —
    //     PostgreSQL 15 실측: 이 조건만 뺀 판본에서 위 6월 보드의 U1 이 다시 3,000,000,000 으로 부활했다.
    #expect(sql.contains("where l2.updated_at > f2.first_at"))
    #expect(sql.contains("and l2.total > coalesce(t2.total, 0)"))

    // (8) touch 트리거는 실사용 쓰기를 전부 now() 로 스탬프하되, **명시적으로 과거 시각을 실은 쓰기**만 보존한다.
    //     회귀 지점: 무조건 `new.updated_at := now()` 였다. 그러면 '기기 행보다 먼저 쓰이고 그 뒤로 갱신이 끊긴
    //     옛 행'(= 화석)을 service_role 로도 만들 수 없어, 위 (6)(7) 의 화석 정정 규칙이 라이브 E2E(s09h)에서
    //     **영원히 검증 불가**가 된다 — 실제로 s09h 의 화석 단언은 옛 행을 심는 순간 updated_at 이 now() 로
    //     덮여 항상 '살아 있는 구버전 맥' 취급을 받아 구조적으로 통과할 수 없었고, 마이그레이션 push 직후
    //     릴리스 게이트가 100% 실패했다. PostgreSQL 15 실측(고치기 전 → 후): 화석 시나리오 보드 total
    //     5,000,000(화석 그대로) → 7,000(정정된 기기 값). 앱은 이 컬럼을 요청 본문에 담지 않으므로
    //     (TokenUsageLegacyUpsertRequest 에 필드가 없다) 실사용 경로의 동작은 완전히 같다.
    #expect(sql.contains("new.updated_at := now();"))
    //     insert 는 컬럼 기본값 now() 로 들어오고, PostgREST merge-duplicates update 는 old 값 그대로 들어온다 —
    //     둘 다 여전히 실제 쓰기 시각으로 갱신돼야 판정('그 뒤로 갱신됐는가')의 전제가 유지된다.
    #expect(sql.contains("or new.updated_at >= now()"))
    #expect(sql.contains("or (tg_op = 'UPDATE' and new.updated_at is not distinct from old.updated_at)"))
    //     미래 시각으로 갱신 시각을 앞당겨 화석 판정을 무한정 회피하는 길은 막혀 있어야 한다(>= now() 로 클램프).
    #expect(!sql.contains("new.updated_at > now()"))
}

// MARK: - 팀 카드 헤더 폭 예산(아이콘 버튼이 늘면 팀 이름이 먼저 잘린다)

@MainActor
@Test
func teamHeaderLeavesRoomForKoreanTeamName() throws {
    // 회귀 지점: v0.2.11 초안이 팀 헤더에 네 번째 아이콘 버튼('내 기록')을 세워 "아잉체크 개발팀"이
    // "아잉…"으로 잘렸다. 개인 화면 버튼은 헤더 카드(내 근무 박스)로 옮기고 장식 아이콘도 걷어냈다.
    // 실제 헤더 구성은 버튼 3개(참여코드 / 콕찌르기 / 팀별 현황)다.
    let budget3 = TeamHeaderWidthBudget.nameWidth(iconButtonCount: 3)
    let budget4 = TeamHeaderWidthBudget.nameWidth(iconButtonCount: 4)
    // 버튼 하나가 27 + 간격 8 = 35pt 를 통째로 이름에서 빼앗는다.
    #expect(abs((budget3 - budget4) - 35) < 0.001)
    // 3버튼이면 한글 8자(“아잉체크 개발팀”)가 말줄임 없이 들어간다. 4버튼이면 절반도 못 넣는다.
    #expect(TeamHeaderWidthBudget.fittingKoreanGlyphs(iconButtonCount: 3) >= 8)
    #expect(TeamHeaderWidthBudget.fittingKoreanGlyphs(iconButtonCount: 4) < 8)

    // 육안 확인: 긴 팀 이름 + 근무중 인원이 많은(칩이 넓은) 최악 조합.
    let now = Date()
    let store = makeTeamStore(members: presenceMembers(now: now), now: now)
    store.teamName = "아잉체크 개발팀"
    store.myTeamInviteCode = "ABCD1234"  // 키 버튼까지 뜬 3버튼 상태(팀원 누구나 보이는 기본 상태).
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "team-header-long-name")
}

// MARK: - 개인 기록 패널이 배너/목표 편집 행과 겹쳐도 창 상한을 지키는지

@MainActor
@Test
func insightsPanelWindowHeightWithinCapWithChrome() throws {
    // 회귀 지점: 개인 기록 패널만 extraChromeHeight 배선에서 빠져 있었고, 회고 카드 + 7×24 히트맵이 전부
    // 고정 높이라 줄일 수단도 없었다 — 목표 편집 행(92) + 12시간 배너(92)가 겹치면 761pt 로 상한을 넘겨
    // 푸터(로그아웃/앱 종료)와 히트맵 하단이 화면 밖으로 잘렸다.
    func measure(_ label: String, _ view: some View) throws -> Double {
        let pixels = try #require(renderedPixelHeight(view))
        let points = Double(pixels) / 2.0
        #expect(points <= 700.0, "\(label) 이 700pt 상한을 넘었습니다: \(points)pt")
        return points
    }

    // 예산 계산 자체를 못 박는다: 목표 편집 행(92) + 12시간 배너(92) = 184pt 는 여유(118)를 66pt 넘기므로
    // 본문을 그만큼 깎아 스크롤로 넘긴다. 배너 하나만으로는 여유 안이라 아무것도 깎지 않는다.
    let worstChrome = CheckMenuView.goalEditorHeight + CheckMenuView.longSessionBannerHeight
    #expect(
        InsightsPanelChromeBudget.capHeight(extraChromeHeight: worstChrome)
            == InsightsPanelChromeBudget.contentNaturalHeight - (worstChrome - InsightsPanelChromeBudget.chromeSlack)
    )
    #expect(InsightsPanelChromeBudget.capHeight(extraChromeHeight: CheckMenuView.longSessionBannerHeight) == nil)

    // (a) 목표 편집 행 + 12시간 확인 배너(가장 부푸는 조합).
    let longSession = makeInsightsStore()
    longSession.startedAt = Date().addingTimeInterval(-10)
    longSession.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
    longSession.isLongSessionPromptActive = true
    _ = try measure("insights+goalEditor+longSession", CheckMenuView(store: longSession, previewGoalEditing: true))

    // (b) 목표 편집 행 + 새 버전 배너.
    let update = makeInsightsStore()
    _ = try measure("insights+goalEditor+updateBanner", CheckMenuView(store: update, previewGoalEditing: true, previewUpdateBanner: true))

    // (c) 목표 편집 행만(여유 안이라 본문을 깎지 않는다 — 불필요한 스크롤을 만들지 않는다).
    let goalOnly = try measure("insights+goalEditor", CheckMenuView(store: makeInsightsStore(), previewGoalEditing: true))
    #expect(InsightsPanelChromeBudget.capHeight(extraChromeHeight: CheckMenuView.goalEditorHeight) == nil)

    // (d) 크롬이 없으면 기본 상태 그대로(스크롤 없음).
    let plain = try measure("insights", CheckMenuView(store: makeInsightsStore()))
    #expect(goalOnly > plain)  // 목표 편집 행만큼만 자란다(본문은 그대로).
}

@MainActor
@Test
func checkMenuViewRendersInsightsPanelCappedContentSnapshot() throws {
    // 육안 확인: 목표 편집 행 + 12시간 배너가 겹친 최악 조합에서 본문(회고 카드 + 히트맵)이 잘려 스크롤로
    // 넘어가는 모습. 앱은 ScrollView 지만 ImageRenderer 가 그리지 못하므로 클립 모드로 같은 높이를 그린다.
    let store = makeInsightsStore()
    store.startedAt = Date().addingTimeInterval(-10)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
    store.isLongSessionPromptActive = true
    let png = try renderPNG(CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: true))
    #expect(png.count > 0)
    saveV0211Snapshot(png, "insights-capped-content")
}

// MARK: - 초단위(displayNow) 의존은 잎 뷰에만 — 팝오버 body 는 매초 무효화되지 않는다

/// withObservationTracking 의 onChange(@Sendable)에서 결과를 받아 두는 상자. 통지는 값을 바꾼 그 스레드에서
/// 동기로 오므로(여기선 메인) 락 없이 안전하다.
private final class ObservationFlag: @unchecked Sendable {
    var value = false
}

@MainActor
@Test
func menuBodyDoesNotObserveDisplayNowOnHomeScreen() {
    // 회귀 지점: topBanner 가 canUndoAutoClose(now: store.displayNow) 를 직접 불러, 배너가 하나도 없는
    // 평소 홈 화면에서도 body 가 displayNow 를 관찰 등록했다. 티커는 근무중이면
    // 항상(비근무여도 근무중 팀원이 있고 팝오버가 열려 있으면) 매초 displayNow 를 갱신하므로, 팝오버 전체
    // 서브트리(HeaderCard/TeamPanel/FooterBar/패널)가 매초 재구성됐다. 초단위 의존은 잎 뷰에만 있어야 한다.
    let now = Date()
    let store = makeTeamStore(members: presenceMembers(now: now), now: now)
    let view = CheckMenuView(store: store)

    // onChange 는 @Sendable 클로저라 지역 var 를 직접 못 건드린다(변경 통지는 이 스레드에서 동기로 온다).
    let invalidated = ObservationFlag()
    withObservationTracking {
        _ = view.body
    } onChange: {
        invalidated.value = true
    }

    // 티커 한 틱과 같은 변화 — 잎 뷰(TodayTimerText/TeamMemberLiveRow 등)만 무효화돼야 한다.
    store.displayNow = now.addingTimeInterval(1)
    #expect(!invalidated.value)

    // 반대로 배너 상태가 실제로 바뀌면(유예형 배너 등장) body 는 반드시 다시 그려져야 한다 —
    // 위에서 추적이 소진되지 않았기에 이 변화가 관찰 등록됐음을 확인할 수 있다.
    store.timedBanner = .undoAutoClose
    #expect(invalidated.value)
}

// MARK: - 토큰 순위판: 실패는 동기화 문구가 아니라 실패 문구 + [다시 시도]

@MainActor
@Test
func checkMenuViewRendersTokenBoardLoadFailureSnapshot() throws {
    // 회귀 지점: 월 이동 중 조회가 실패하면 본문 자리에 "동기화됨"("근무 재개됨" 등)이 그대로 떴다.
    #expect(
        TokenBoardEmptyMessage.text(hasLoaded: false, isLoading: false, hasFailed: true, fallbackStatus: "동기화됨")
            == TokenBoardEmptyMessage.loadFailed
    )
    // 진행중이 실패보다 우선한다(재시도 중에는 다시 "불러오는 중…").
    #expect(
        TokenBoardEmptyMessage.text(hasLoaded: false, isLoading: true, hasFailed: true, fallbackStatus: "동기화됨")
            == TokenBoardEmptyMessage.loading
    )
    // 조회가 시작조차 안 된 상태는 기존대로 상태 문구(계약 불변).
    #expect(
        TokenBoardEmptyMessage.text(hasLoaded: false, isLoading: false, hasFailed: false, fallbackStatus: "로그인 필요")
            == "로그인 필요"
    )

    let store = makeTokenBoardStore(memberCount: 5)
    store.syncMessage = "동기화됨"
    store.tokenBoardMonth = TokenBoardMonthNavigator.step(TokenUsageMonthKey.current(), by: -1)
    store.tokenBoard = []
    store.tokenBoardLoaded = false
    store.tokenBoardLoading = false
    store.tokenBoardFailed = true

    let failedPNG = try renderPNG(CheckMenuView(store: store))
    #expect(failedPNG.count > 0)
    saveV0211Snapshot(failedPNG, "token-board-load-failed")

    // 실패 문구 + [다시 시도] 버튼이 실제로 그림에 반영된다(같은 빈 목록이라도 로딩 상태와 다른 그림).
    store.tokenBoardFailed = false
    store.tokenBoardLoading = true
    let loadingPNG = try renderPNG(CheckMenuView(store: store))
    #expect(loadingPNG != failedPNG)
}
