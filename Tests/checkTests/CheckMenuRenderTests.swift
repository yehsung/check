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
        // 같은 배너에 패치노트 4줄(파서 상한)까지 얹힌 상태 — 노트가 붙어도 상한 안이다.
        try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))),
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

/// 이번 버전 패치노트가 얹힌 배너(제목 → 노트 3줄 → [지금 업데이트]/[명령 복사]). 340pt 폭에서 노트 줄이
/// 겹치거나 버튼을 밀어내지 않는지 육안 확인용.
@MainActor
@Test
func checkMenuViewRendersUpdateBannerWithNotesSnapshot() throws {
    let store = makeSignedInStore()
    let png = try renderPNG(CheckMenuView(store: store, previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))
    #expect(png.count > 0)
    let path = ProcessInfo.processInfo.environment["CHECK_UPDATE_NOTES_SNAPSHOT_PATH"]
        ?? "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/update-banner-notes.png"
    try? png.write(to: URL(fileURLWithPath: path))
}

/// 배너 높이 예산 규약: 노트가 없으면 예전 높이 그대로(회귀 금지), 있으면 줄 수에 비례해서만 자란다.
/// 이 델타가 CheckMenuView 의 예산 상수(updateNoteBlockPadding + 줄수 × updateNoteLineHeight)와 어긋나면
/// 목록 행수 예산이 틀어져 창이 700pt 상한을 넘게 되므로 여기서 실측으로 묶어 둔다.
@MainActor
@Test
func updateBannerGrowsOnlyByNoteLinesAndStaysUnchangedWithoutNotes() throws {
    let plain = try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewUpdateBanner: true)))
    // 빈 노트 배열은 노트 블록 자체를 그리지 않는다 — 옛 릴리스/파싱 실패에서 예전과 픽셀 단위로 같은 배너.
    let emptyNotes = try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewUpdateBanner: true, previewUpdateNotes: [])))
    #expect(emptyNotes == plain)

    for count in 1...CheckUpdateStoreNoteCap {
        let notes = Array(sampleUpdateNotes.prefix(count))
        let withNotes = try #require(renderedPixelHeight(CheckMenuView(store: makeSignedInStore(), previewUpdateBanner: true, previewUpdateNotes: notes)))
        let deltaPt = Double(withNotes - plain) / 2.0
        let budget = Double(CheckMenuView.updateNoteBlockPadding + CGFloat(count) * CheckMenuView.updateNoteLineHeight)
        #expect(deltaPt > 0, "노트 \(count)줄이 배너를 전혀 늘리지 않았습니다(노트가 안 그려졌을 수 있음).")
        // 예산은 실측보다 모자라면 안 된다(모자라면 목록이 한 행 더 남아 상한을 넘는다). 과대 추정은 안전측.
        #expect(budget >= deltaPt, "노트 \(count)줄 실측 \(deltaPt)pt 가 예산 \(budget)pt 를 넘었습니다.")
        #expect(budget - deltaPt <= 8.0, "노트 \(count)줄 예산이 실측보다 과하게 큽니다(\(budget)pt vs \(deltaPt)pt).")
    }
}

/// 배너에 보여 줄 수 있는 최대 노트 줄 수(파서 상한과 같은 값이어야 한다).
private let CheckUpdateStoreNoteCap = UpdateCheckStore.maxNotes

/// 실제 CHANGELOG 톤의 표본 노트(4줄 — 파서 상한과 같은 최악 줄 수). 마지막 줄은 일부러 길게 두어
/// 폭을 넘는 문구가 줄바꿈으로 배너를 부풀리지 않고 한 줄로 잘리는지(lineLimit 1)까지 같이 잡는다.
private let sampleUpdateNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

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
    try measure("home+banners", CheckMenuView(store: home, previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))

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
    try measure("tokenBoard+banners", CheckMenuView(store: board, previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))

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
    try measure("poke+banners", CheckMenuView(store: poke, previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))

    // (e) 리그 패널(12팀) + 배너.
    let league = teamStore()
    addRetroBanner(league)
    addUndoBanner(league)
    league.leaderboard = manyLeaderboardEntries(count: 12)
    league.isLeaderboardVisible = true
    try measure("league+banners", CheckMenuView(store: league, previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))

    // (f) 개인 기록 패널(회고 카드 + 7×24 히트맵) + 되돌리기/새 버전 배너.
    let insights = teamStore()
    insights.teamGoalSeconds = 40 * 3_600
    insights.heatmap = sampleWorkRhythmHeatmap()
    insights.retro = sampleWeeklyRetro()
    insights.insightsLoaded = true
    insights.isInsightsPanelVisible = true
    addUndoBanner(insights)
    try measure("insights+banners", CheckMenuView(store: insights, previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))

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
    _ = try measure("insights+goalEditor+updateBanner", CheckMenuView(store: update, previewGoalEditing: true, previewUpdateBanner: true, previewUpdateNotes: sampleUpdateNotes))

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

// MARK: - 설정으로 가는 길(기어) · 할 일 스위치의 집(설정 창)
//
// 배경: 할 일 on/off 스위치는 처음엔 푸터 전원 버튼 메뉴에, 다음엔 캐릭터 버튼 메뉴에, 그다음엔 이 캡션
// 행에 있었다. 앞의 둘은 Menu 의 보조 화살표(hover 전엔 보이지도 않는다) 뒤라 "투두 온오프 버튼 대체
// 어디있어?"라는 실사용 신고가 그대로 남았다. 지금 스위치의 집은 설정 창(CheckSettingsView) 하나이고,
// 팝오버에 남은 것은 그 창으로 가는 **기어 버튼** 하나다.
//
// 판정 기준은 예전 그대로 "픽셀에 보이는가"다. ImageRenderer 는 Menu 를 못 그린다(자리에 노란 경고
// 상자가 박힌다) — 무엇을 Menu 안에 넣든 그 순간 렌더 회귀 테스트의 사각지대가 되기 때문이다.

@MainActor
@Test
func settingsEntryIsDrawnInTheCaptionRowAndIsNotAMenu() throws {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let bitmap = try renderBitmap(CheckMenuView(store: makeTeamStore(members: presenceMembers(now: now), now: now)))

    // (0) 팝오버 높이가 이사 전과 같다(517pt). 할 일 버튼이 나가고 기어가 그 자리를 이어받았으므로
    //     캡션 행 버튼 수는 3개 그대로다 — 창 높이 예산(700pt 상한)이 1pt 도 움직이면 안 된다.
    #expect(bitmap.pixelsHigh == 517 * 2)

    // (1) 캡션 행은 상수로 박지 않고 **진행 바에서 파생해** 찾는다(헤더 글자가 바뀌어도 같은 띠를 가리킨다).
    let band = try #require(goalCaptionBand(bitmap), "진행 바 아래 캡션 행을 찾지 못했다 — 헤더 구조가 바뀌었다")
    // 캡션 행 높이 = 소형 아이콘 버튼 18pt. 여기에 표준 IconButton(27pt)을 잘못 세우면 이 줄이 먼저 빨개진다.
    #expect(band.bottom - band.top + 1 == 18 * 2, "캡션 행 높이가 \(Double(band.bottom - band.top + 1) / 2)pt 다")

    // (2) 그 행의 오른쪽 끝에 18pt 버튼이 **정확히 셋**이다: [설정][내 기록][목표 수정].
    //     하나가 사라지거나 넷이 되면 여기서 잡힌다.
    let runs = inkColumnRuns(bitmap, top: band.top, bottom: band.bottom, left: 25 * 2, right: bitmap.pixelsWide - 25 * 2)
    #expect(runs.count >= 4, "캡션 행에 왼쪽 문구도 함께 그려져야 한다(덩어리 \(runs.count)개)")
    // 18pt 폭 덩어리가 정확히 셋이다 — 하나가 빠지면 여기가 먼저, 가장 알아보기 쉽게 빨개진다.
    let iconWidthRuns = runs.filter { abs(($0.end - $0.start + 1) - 18 * 2) <= 2 }
    #expect(
        iconWidthRuns.count == 3,
        "캡션 행의 18pt 아이콘 버튼이 \(iconWidthRuns.count)개다 — [설정][내 기록][목표 수정] 셋이어야 한다"
    )
    let buttons = Array(runs.suffix(3))
    for button in buttons {
        // 18pt 소형 버튼. ±2px 는 원 가장자리 안티에일리어싱 몫이다(표준 27pt 버튼이면 18px 이나 벌어진다).
        #expect(abs((button.end - button.start + 1) - 18 * 2) <= 2, "버튼 폭이 \(Double(button.end - button.start + 1) / 2)pt 다")
    }
    // 셋이 4pt 간격으로 붙어 서므로 전체 폭은 3*18 + 2*4 = 62pt 다(간격이 벌어지면 여기서 걸린다).
    #expect(abs((buttons[2].end - buttons[0].start + 1) - 62 * 2) <= 2)
    // 맨 오른쪽 버튼은 카드 콘텐츠 오른끝(316pt)에서 끝난다.
    #expect(abs(buttons[2].end - (316 * 2 - 1)) <= 2)

    // (3) 셋 다 **아이콘이 칠해져 있다.** 원 배경(white 0.06 ≈ 56,58,73)만 남고 심볼이 빠지는 경우
    //     (SF Symbol 이름 오타 등)를 여기서 가른다 — 아이콘은 secondaryText(≈191,192,197)라 밝기로 갈린다.
    for button in buttons {
        let glyph = brightPixelCount(bitmap, top: band.top, bottom: band.bottom, left: button.start, right: button.end)
        #expect(glyph >= 20, "버튼 원만 그려지고 아이콘이 빠졌다(x \(button.start)…\(button.end), 밝은 픽셀 \(glyph)개)")
    }

    // (4) 캡션 행에 '못 그림' 노란 상자가 없다 = 이 행에 Menu 가 없다. 여기에 Menu 를 세우는 순간
    //     그 버튼은 픽셀 커버리지 0 이 되고 (2)(3)의 셈도 무너진다.
    #expect(unavailablePlaceholderBounds(bitmap, top: band.top, bottom: band.bottom) == nil)

    // (5) 셋 중 **맨 왼쪽이 설정**이라는 건 픽셀로 못 가른다(아이콘 모양 비교는 스냅샷 고정이 된다).
    //     소스 순서로 못 박는다 — 오른쪽 끝부터 세는 손버릇(끝=연필, 끝에서 둘째=내 기록)을 지키는 계약이다.
    //     이게 깨지면 목표를 고치려다 설정 창이 열리는 오클릭이 생긴다.
    let source = try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8)
    let section = try #require(swiftStructBody(source, name: "HeaderGoalSection"))
    let gear = try #require(section.range(of: "\"gearshape.fill\""), "캡션 행이 기어 아이콘을 그려야 한다")
    let chart = try #require(section.range(of: "\"chart.xyaxis.line\""))
    let pencil = try #require(section.range(of: "\"pencil\""))
    #expect(gear.lowerBound < chart.lowerBound)
    #expect(chart.lowerBound < pencil.lowerBound)
    // 기어가 실제로 설정 창을 연다(그리기만 하고 아무 데도 안 가는 버튼 방지).
    #expect(section.contains("CheckSettingsWindowController.shared.show()"))
    #expect(!section.contains("Menu {"))
    #expect(!section.contains("Menu("))
}

@MainActor
@Test
func todoSwitchLeftThePopoverAndNowMovesOnlyTheSettingsScreen() throws {
    // 예전 계약("누르면 팝오버 그림이 바뀐다")은 스위치가 팝오버에 있던 시절의 이야기다. 이사가 끝났다면
    // **두 방향이 동시에** 참이어야 한다 — 팝오버는 상태를 뒤집어도 꿈쩍 않고, 설정 화면은 바뀐다.
    // 한쪽만 보면 놓친다: 팝오버만 보면 "집이 없다"(어디서도 못 바꾼다)를, 설정만 보면 "집이 둘"
    // (예전 자리에 남은 유령 스위치)을 못 잡는다.
    let now = Date(timeIntervalSince1970: 1_784_000_000)

    func popover(_ todo: Bool) throws -> NSBitmapImageRep {
        let store = makeTeamStore(members: presenceMembers(now: now), now: now)
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
        store.setTodoEnabled(todo)
        return try renderBitmap(CheckMenuView(store: store))
    }
    #expect(
        bitmapDiffBounds(try popover(true), try popover(false)) == nil,
        "팝오버에 할 일 스위치의 흔적이 남아 있다 — 집은 설정 창 하나여야 한다"
    )

    func settings(_ todo: Bool) throws -> NSBitmapImageRep {
        let store = makeTeamStore(members: [], now: now)
        store.setTodoEnabled(todo)
        // launchAtLoginSeed 를 반드시 준다 — 안 주면 렌더가 실제 로그인 항목(SMAppService)을 읽어
        // 테스트가 이 맥의 시스템 상태에 의존하게 된다.
        return try renderBitmap(
            CheckSettingsView(store: store, launchAtLoginSeed: false),
            width: CheckSettingsView.preferredWidth
        )
    }
    let flip = try #require(
        bitmapDiffBounds(try settings(true), try settings(false)),
        "설정 화면에서도 그림이 안 바뀌면 이 스위치는 어디에도 없다(먹통 스위치)"
    )
    // 바뀐 자리는 스위치 하나 크기다(실측 138x102px). 화면 전체가 흔들리면 레이아웃이 밀린 것이다.
    #expect(flip.maxX - flip.minX <= 180)
    #expect(flip.maxY - flip.minY <= 120)
}

@MainActor
@Test
func todoSwitchStateSurvivesReopeningThePopover() throws {
    // 팝오버를 닫았다 열어도(=스토어를 새로 만들어도) 상태가 남아야 한다 → 같은 defaults 를 공유시켜 확인한다.
    // 누르는 자리는 설정 창의 토글이고, 그 Binding 이 실제로 부르는 것이 setTodoEnabled(_:) 다.
    let defaults = isolatedRenderDefaults()
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        tokenUsage: inertTokenStore()
    )
    #expect(store.isTodoEnabled)   // 기본은 켬(새 기능을 발견하게)

    store.setTodoEnabled(false)
    #expect(store.isTodoEnabled == false)
    #expect(defaults.object(forKey: WorkTimerStore.todoEnabledKey) as? Bool == false)

    // 다시 열기 = 같은 defaults 로 스토어 재생성.
    let reopened = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        tokenUsage: inertTokenStore()
    )
    #expect(reopened.isTodoEnabled == false)

    reopened.setTodoEnabled(true)
    #expect(reopened.isTodoEnabled)
    #expect(defaults.object(forKey: WorkTimerStore.todoEnabledKey) as? Bool == true)
}

@Test
func todoSwitchWordingStillCoversBothStatesAtItsNewHome() throws {
    // 예전 이 자리는 팝오버 버튼의 문구 계약(`TodoToggleControl.help(isOn:)`)을 직접 불러 두 상태의
    // 문장을 확인했다. 스위치가 설정 창으로 가면서 문구도 따라갔고 — 그 enum 은 호출부가 0이 되어
    // v0.2.32 에 지웠다 — 토글이라 상태별 두 문장이 아니라 **한 줄이 두 상태를 다 말한다**.
    // 그래서 판정을 함수 호출에서 **설정 창 소스 읽기**로 바꿨다. 지켜야 할 것은 그대로다 —
    // 껐을 때 캐릭터가 어떻게 되는지가 문구에 있어야 하고("캐릭터를 눌러 할 일 열기"만 적혀 있던 시절엔
    // 끄면 무슨 일이 나는지 아무도 몰랐다), 내부 용어("아파하기")가 사용자 문구로 새어 나가면 안 된다.
    let source = try String(contentsOf: checkSettingsViewSourceURL(), encoding: .utf8)
    let title = try #require(source.range(of: "캐릭터를 눌러 할 일 열기"), "설정 창에 할 일 스위치가 있어야 한다")
    let detail = String(source[title.upperBound...].prefix(400))

    #expect(detail.contains("켜면"))
    #expect(detail.contains("끄면"))
    #expect(detail.contains("콕 반응만"))
    #expect(!detail.contains("아파"))

    // 이 스위치를 실제로 넘기는 자리는 앱 전체에서 설정 창 하나뿐이다(중복 집 금지).
    // 주석을 걷어내고 센다 — 이 저장소는 "왜"를 길게 적는 관례라 설명문에 호출 이름이 자주 나온다.
    #expect(swiftCodeStrippingComments(source).components(separatedBy: "setTodoEnabled(").count - 1 == 1)
    let menu = swiftCodeStrippingComments(try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8))
    #expect(!menu.contains("setTodoEnabled("))
}

@MainActor
@Test
func goalCaptionRowKeepsSlackWithThreeButtonsInIt() throws {
    // 캡션 행은 [이번 주 X / Y시간][Spacer(minLength: 4)][%][설정][내 기록][목표 수정] 한 줄이다.
    // 행이 넘치면 Spacer 가 최소값(4pt=8px)까지 짜부라지므로, 캡션 띠에 남은 **가장 긴 빈 세로줄**이
    // 여유의 척도가 된다. 실측: 버튼 3개 · 최악값 문구(주 168시간 목표를 꽉 채운 100%)로도 122px(=61pt).
    // 할 일 버튼이 설정 창으로 나가고 기어가 그 자리를 이어받았으므로 버튼 수도 이 값도 그대로다.
    // 60px(30pt) 밑으로 내려가면 다음 버튼 하나에 문구가 잘린다는 뜻이니, 그 전에 멈추라고 세워 둔 난간이다
    // (버튼을 넷째까지 세워 보면 32px 까지 떨어진다 — 그 상태가 곧 말줄임이다).
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = makeTeamStore(members: presenceMembers(now: now), now: now)
    store.teamGoalSeconds = 168 * 3_600
    store.teamMembers = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 168 * 3_600
        )
    ]

    let bitmap = try renderBitmap(CheckMenuView(store: store))
    // 예전엔 할 일 on/off 렌더 diff 로 이 띠를 찾았다 — 그 버튼이 나가면서 diff 가 사라져 테스트가
    // "띠를 못 찾음"으로 빨개졌다. 이제는 진행 바에서 파생한다(어떤 버튼이 있든 같은 띠를 가리킨다).
    let band = try #require(goalCaptionBand(bitmap), "진행 바 아래 캡션 행을 찾지 못했다 — 헤더 구조가 바뀌었다")

    let gap = longestBackgroundColumnRun(bitmap, top: band.top, bottom: band.bottom, left: 48, right: 340 * 2 - 48)
    #expect(gap > 60, "캡션 행 여유가 \(gap)px 뿐이다 — 버튼을 더 세우려면 문구부터 줄여야 한다.")
}

@MainActor
@Test
func footerButtonsAreRealButtonsNotMenus() throws {
    // 푸터 캐릭터 버튼을 Menu 로 감쌌더니 ImageRenderer 가 통째로 못 그렸다(노란 경고 상자). 즉 푸터가
    // 렌더 회귀 테스트의 사각지대가 됐다. 다시 버튼으로 되돌린 뒤에는 캐릭터 표시 on/off 가 푸터 픽셀에 드러난다.
    let now = Date(timeIntervalSince1970: 1_784_000_000)

    func render(overlay: Bool) throws -> NSBitmapImageRep {
        let store = makeTeamStore(members: presenceMembers(now: now), now: now)
        store.setOverlayEnabled(overlay)
        return try renderBitmap(CheckMenuView(store: store))
    }

    let shown = try render(overlay: true)
    let hidden = try render(overlay: false)
    let diff = try #require(bitmapDiffBounds(shown, hidden), "푸터 캐릭터 버튼이 표시 상태를 픽셀로 드러내야 한다")

    // 푸터 안이다(맨 아래 60pt 띠) — 그리고 바깥 padding(12pt=24px) 안쪽에 온전히 들어간다(잘림 없음).
    #expect(diff.minY >= shown.pixelsHigh - 60 * 2)
    #expect(diff.minX >= 24)
    #expect(diff.maxX <= 340 * 2 - 24)
    #expect(diff.maxX - diff.minX <= 60)

    // ★ 계약이 뒤집힌 자리다. 예전엔 "노란 상자가 **정확히 하나**"(맨 오른쪽 전원 버튼이 Menu 였다)를
    // 요구했고, 바로 그 상자 뒤에서 전원 버튼은 8일 동안 픽셀 커버리지가 0이었다 — 빨강이 흰색으로
    // 그려진 v0.2.17 결함이 렌더 스위트를 그대로 통과했다. 전원 버튼이 IconButton 으로 돌아온 지금
    // 푸터에 Menu 는 **하나도 없어야 한다**. 상자가 하나라도 생기면 그만큼 푸터가 다시 안 보이게 된다.
    let footerTop = shown.pixelsHigh - 60 * 2
    #expect(
        unavailablePlaceholderBounds(shown, top: footerTop, bottom: shown.pixelsHigh - 1) == nil,
        "푸터에 Menu 가 생겼다 — 그 자리는 렌더 테스트가 보지 못하는 사각지대가 된다"
    )
    #expect(unavailablePlaceholderBounds(hidden, top: footerTop, bottom: hidden.pixelsHigh - 1) == nil)
}

@MainActor
@Test
func powerButtonIsDrawnInDangerRed() throws {
    // 8일 동안 아무도 못 잡은 결함의 자리다. v0.2.17 이 '로그인 시 자동 실행' 토글을 숨기려고 이 자리를
    // Menu 로 바꿨고, AppKit 이 Menu 의 label 에 자기 틴트를 입혀 `.foregroundStyle(CheckTheme.danger)`
    // 가 무시됐다 — 위험을 알리는 빨강이 화면에서 흰색으로 그려졌다("왜 하얀색이 됐냐" 실사용 신고).
    // 렌더 스위트가 못 잡은 이유는 하나다: ImageRenderer 가 Menu 자리에 노란 상자를 박아 전원 버튼이
    // **아예 그려지지 않았다**(픽셀 커버리지 0). 그래서 여기서는 색을 직접 센다.
    //
    // scale 3 으로 그린다 — 12pt 심볼의 획이 얇아 scale 2 에서는 안티에일리어싱에 섞인 픽셀만 남는다.
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let bitmap = try renderBitmap(
        CheckMenuView(store: makeTeamStore(members: presenceMembers(now: now), now: now)),
        scale: 3
    )
    // 푸터 바닥 40pt 띠. 버튼 4개가 27pt + 8pt 간격으로 오른쪽 끝(콘텐츠 오른끝 316pt)에 붙어 선다
    // → 전원 289…316pt, 그 왼쪽 로그아웃 254…281pt.
    let top = bitmap.pixelsHigh - 40 * 3
    let bottom = bitmap.pixelsHigh - 1
    let power = (left: 289 * 3, right: 316 * 3 - 1)
    let logout = (left: 254 * 3, right: 281 * 3 - 1)

    // (1) 전원 슬롯이 danger 로 칠해져 있다(실측 352px · 도달값 255,115,117 = CheckTheme.danger 그대로).
    //     Menu 로 되돌아가면 이 자리에 노란 상자(255,204,0)가 박혀 빨강이 0 이 된다.
    let red = dangerPixelCount(bitmap, top: top, bottom: bottom, left: power.left, right: power.right)
    #expect(red >= 250, "전원 버튼이 빨강으로 그려지지 않았다(빨강 픽셀 \(red)개)")

    // (2) 그 슬롯에 **밝은 무채색 획이 하나도 없다.** 틴트를 잃으면(= 기본값 secondaryText 로 되돌아가거나
    //     AppKit 이 자기 틴트를 입히면) 정확히 여기에 흰끼 도는 회색 아이콘이 생긴다. v0.2.17 결함의 얼굴이다.
    let neutral = neutralIconPixelCount(bitmap, top: top, bottom: bottom, left: power.left, right: power.right)
    #expect(neutral == 0, "전원 버튼이 무채색으로 그려졌다(밝은 회색 픽셀 \(neutral)개) — 틴트가 먹히지 않았다")

    // (3) 대조군: 바로 왼쪽 로그아웃 슬롯은 정확히 그 반대다(빨강 0 · 무채색 아이콘 다수).
    //     이 두 줄이 없으면 위 두 판정기가 "아무거나 세는 함수"여도 초록이 된다.
    #expect(dangerPixelCount(bitmap, top: top, bottom: bottom, left: logout.left, right: logout.right) == 0)
    #expect(neutralIconPixelCount(bitmap, top: top, bottom: bottom, left: logout.left, right: logout.right) >= 100)

    // (4) 그리고 이 띠에 '못 그림' 노란 상자가 없다 = 진짜 버튼이 그렸다.
    //     이 줄이 필요한 이유는 실측으로 배웠다: 전원 버튼을 Menu 로 되감아 보면 menuStyle 에 따라
    //     ImageRenderer 가 노란 상자를 박으면서 **label 을 그 위에 함께** 그리기도 한다 — 그때는 빨강이
    //     그대로 세어져 (1)(2)만으로는 통과해 버린다. 색과 구조를 한 테스트 안에서 같이 잡는다.
    #expect(
        unavailablePlaceholderBounds(bitmap, top: top, bottom: bottom) == nil,
        "전원 버튼이 Menu 로 되감겼다 — 그 자리는 렌더러가 못 그리는 사각지대가 된다"
    )
}

@Test
func thePowerButtonIsNoLongerAMenuAndCarriesNoSettings() throws {
    // 위 픽셀 테스트의 짝. "빨갛게 그려졌다"는 결과이고, 이건 그 결과를 만드는 **구조**를 못 박는다 —
    // 전원 버튼은 클릭하면 앱이 종료되는 자리라, 여기에 무언가를 숨기면 설정을 보려는 클릭이 확인도 없이
    // 앱을 끈다. v0.2.17 의 PowerMenuButton 이 그랬고, 그래서 그 구조체는 통째로 사라졌다.
    // 주석을 걷어낸 코드로 본다 — 이 파일의 주석은 "왜 Menu 를 걷어냈는지"를 길게 설명하고 있어서,
    // 날 것으로 매칭하면 그 설명문이 그대로 걸린다(설명을 지우면 초록이 되는 테스트는 테스트가 아니다).
    let source = swiftCodeStrippingComments(try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8))

    // 구조체 자체가 없다(예전엔 이 블록을 잘라 와 "할 일이 안 들어 있는지"를 봤다 — 이제 블록이 없는 게 계약이다).
    #expect(swiftStructBody(source, name: "PowerMenuButton") == nil)
    #expect(!source.contains("PowerMenuButton"))

    let footer = try #require(swiftStructBody(source, name: "FooterBar"))
    // 푸터에 Menu 가 하나도 없다(footerButtonsAreRealButtonsNotMenus 의 픽셀 판정과 같은 사실의 소스 쪽 근거).
    #expect(!footer.contains("Menu"))
    // 푸터는 아이콘 버튼 4개가 상한이다(FooterWidthBudget) — 그 4개가 전부 IconButton 이다.
    #expect(footer.components(separatedBy: "IconButton(").count - 1 == 4)
    // 전원 버튼은 danger 틴트를 **직접** 받는다. 이 인자가 빠지면 기본값(secondaryText)으로 회색이 된다.
    #expect(footer.contains("IconButton(icon: \"power\", help: \"앱 종료\", tint: CheckTheme.danger)"))
    // 자동 실행도 할 일도 이 자리에 없다(둘 다 설정 창이 가져갔다). 스위치류가 다시 기어들면 여기서 걸린다.
    #expect(!footer.contains("Toggle"))
    #expect(!footer.contains("LoginItemRegistrar"))
    #expect(!footer.contains("Todo"))
}

// MARK: - 할 일 토글 육안 확인 덤프(스크래치패드)

@MainActor
@Test
func dumpTodoToggleSnapshots() throws {
    let now = Date(timeIntervalSince1970: 1_784_000_000)

    func store(working: Bool, todo: Bool, overlay: Bool = true) -> WorkTimerStore {
        let s = makeTeamStore(members: presenceMembers(now: now), now: now)
        s.snapshot = WorkStatusSnapshot(status: working ? .working : .offWork, elapsedSeconds: working ? 3_600 : 0)
        s.setTodoEnabled(todo)
        s.setOverlayEnabled(overlay)
        return s
    }

    try dumpTodoSnapshot(CheckMenuView(store: store(working: true, todo: true)), "todo-a-working-on")
    try dumpTodoSnapshot(CheckMenuView(store: store(working: true, todo: false)), "todo-b-working-off")
    try dumpTodoSnapshot(CheckMenuView(store: store(working: false, todo: true)), "todo-c-offwork")
    try dumpTodoSnapshot(CheckMenuView(store: store(working: true, todo: true, overlay: false)), "todo-d-character-hidden")
}

// MARK: - 비밀번호 재설정(OTP) 화면

@Test
func passwordResetResendStaysLockedUntilCooldownEnds() {
    // 재발송 잠금은 순수 판정이라 화면 없이 단언한다. 쿨다운이 남아 있으면 잠기고, 남은 초가 글자에 보여야 한다.
    let cooling = passwordResetModel(phase: .enterCode, resendSeconds: 47)
    #expect(cooling.isResendEnabled == false)
    #expect(cooling.resendTitle == "다시 받기 (47초)")

    let ready = passwordResetModel(phase: .enterCode, resendSeconds: 0)
    #expect(ready.isResendEnabled)
    #expect(ready.resendTitle == "다시 받기")

    // 왕복 중(verifying)이면 쿨다운이 끝나 있어도 잠근다 — 검증과 재발송이 겹치면 코드가 갈아엎힌다.
    #expect(passwordResetModel(phase: .verifying, resendSeconds: 0).isResendEnabled == false)

    // 재발송은 **코드 화면에만** 산다. 3단계에서는 코드가 이미 소모돼 다시 받아 봐야 쓸 곳이 없다.
    #expect(passwordResetModel(phase: .enterCode, resendSeconds: 0).showsResend)
    #expect(passwordResetModel(phase: .verifying, resendSeconds: 0).showsResend)
    #expect(passwordResetModel(phase: .enterNewPassword, resendSeconds: 0).showsResend == false)
    #expect(passwordResetModel(phase: .submitting, resendSeconds: 0).showsResend == false)
    #expect(passwordResetModel(phase: .enterEmail, resendSeconds: 0).showsResend == false)
}

@Test
func passwordResetKeepsThreeScreensAcrossSevenPhases() {
    // 단계는 7가지지만 화면은 3개다. 왕복 중인 단계는 **직전 입력 화면에 머물러야** 한다 —
    // 여기서 화면이 바뀌면 진행 문구가 뜨는 동안 방금 친 값이 눈앞에서 사라진다.
    #expect(passwordResetModel(phase: .enterEmail).step == .email)
    #expect(passwordResetModel(phase: .sending).step == .email)
    #expect(passwordResetModel(phase: .enterCode).step == .code)
    #expect(passwordResetModel(phase: .verifying).step == .code)
    #expect(passwordResetModel(phase: .enterNewPassword).step == .newPassword)
    #expect(passwordResetModel(phase: .submitting).step == .newPassword)

    // 3단계 머리글은 "재설정"이 아니라 **이미 통과했다**를 알려야 한다. 2단계와 같은 부제면
    // 사용자가 "왜 또 입력하지?"로 읽는다.
    #expect(passwordResetModel(phase: .enterEmail).headerSubtitle == "비밀번호 재설정")
    #expect(passwordResetModel(phase: .enterCode).headerSubtitle == "비밀번호 재설정")
    #expect(passwordResetModel(phase: .enterNewPassword).headerSubtitle == "코드 확인 완료")

    // 왕복 문구는 단계마다 다르다 — 셋이 같으면 "지금 뭘 기다리는지"를 화면이 못 말해 준다.
    #expect(passwordResetModel(phase: .sending).noticeText == "코드 보내는 중")
    #expect(passwordResetModel(phase: .verifying).noticeText == "코드 확인 중")
    #expect(passwordResetModel(phase: .submitting).noticeText == "비밀번호 바꾸는 중")
    #expect(passwordResetModel(phase: .verifying).noticeKind == .progress)
}

@Test
func passwordResetMovesFocusToTheFieldOfEachStep() throws {
    // 화면이 넘어갔는데 커서가 그대로면 사용자가 클릭부터 해야 한다. FocusState 는 오프스크린 렌더로
    // 관측할 수 없으므로 "어디로 옮기는가"를 순수 값으로 빼서 단언하고, 배선은 소스로 못 박는다.
    #expect(PasswordResetStep.email.focusField == .resetEmail)
    #expect(PasswordResetStep.code.focusField == .resetCode)
    #expect(PasswordResetStep.newPassword.focusField == .resetNewPassword)

    let source = try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8)
    let panel = try #require(swiftStructBody(source, name: "PasswordResetPanel"))
    // 단계가 바뀔 때(onChange)와 화면에 처음 들어올 때(onAppear) 둘 다 옮겨야 한다 —
    // onChange 만 있으면 1단계 진입 시 커서가 없고, onAppear 만 있으면 2·3단계 전환에서 멈춘다.
    #expect(panel.contains("onChange(of: model.step)"))
    #expect(panel.contains("focus = step.focusField"))
    #expect(panel.contains("onAppear { focus = model.step.focusField }"))
}

// 스토어 문구 상수(WorkTimerStore.passwordReset*Message)는 @MainActor 타입의 멤버라 이 격리가 필요하다.
@MainActor
@Test
func passwordResetPrimaryButtonCarriesWhatWasTyped() {
    // 버튼 action 은 오프스크린에서 누를 수 없으므로, "눌리면 무슨 값이 나가는가"를 값으로 단언한다.
    let step1 = passwordResetModel(phase: .enterEmail, email: "  member@example.com ")
    #expect(step1.primaryTitle == "코드 받기")
    // 앞뒤 공백을 뗀 주소가 나가야 한다(메일 앱에서 복사하면 공백이 붙어 온다).
    #expect(step1.primaryAction == .requestCode(email: "member@example.com"))
    #expect(step1.isPrimaryEnabled)

    // 2단계는 **코드만** 싣는다. 비밀번호를 같이 보내면 서버가 무엇을 거절했는지 화면이 구분할 수 없다.
    let step2 = passwordResetModel(phase: .enterCode, code: "482913", newPassword: "new-secret")
    #expect(step2.primaryTitle == "코드 확인")
    #expect(step2.primaryAction == .verifyCode(code: "482913"))
    #expect(step2.isPrimaryEnabled)

    // 3단계는 **새 비밀번호만** 싣는다(코드는 이미 소모됐다).
    let step3 = passwordResetModel(phase: .enterNewPassword, code: "482913", newPassword: "new-secret")
    #expect(step3.primaryTitle == "비밀번호 바꾸기")
    #expect(step3.primaryAction == .submitNewPassword(newPassword: "new-secret"))
    #expect(step3.isPrimaryEnabled)

    // 2단계 열림 조건은 코드 6자리뿐이다 — 비밀번호가 비어 있어도 확인 버튼은 눌려야 한다.
    #expect(passwordResetModel(phase: .enterCode, code: "482913", newPassword: "").isPrimaryEnabled)
    #expect(passwordResetModel(phase: .enterCode, code: "4829", newPassword: "new-secret").isPrimaryEnabled == false)
    // 3단계 열림 조건은 비밀번호 길이뿐이다 — 코드 칸이 없으므로 코드가 비어도 상관없다.
    #expect(passwordResetModel(phase: .enterNewPassword, code: "", newPassword: "new-secret").isPrimaryEnabled)
    #expect(passwordResetModel(phase: .enterNewPassword, newPassword: "abc").isPrimaryEnabled == false)
    // 왕복 중에는 기본 버튼도 잠긴다(중복 제출 금지) + 문구가 비어도 진행 표시가 뜬다.
    let sending = passwordResetModel(phase: .sending, email: "member@example.com")
    #expect(sending.isPrimaryEnabled == false)
    #expect(sending.noticeText == "코드 보내는 중")
    #expect(sending.noticeKind == .progress)
    // 안내(회색/주황)는 스토어의 **발송 관련 상수 세 개뿐**이고 나머지는 전부 오류(빨강)다.
    // 거절 문구가 안내로 새면 사용자가 "고쳐야 한다"는 신호를 못 받는다 — 실제로 비밀번호 규칙 거절이
    // 봉투 아이콘 달린 주황 안내로 그려지던 것을 이 방향으로 뒤집어 막았다.
    #expect(passwordResetModel(phase: .enterCode, message: WorkTimerStore.passwordResetSentMessage).noticeKind == .info)
    #expect(passwordResetModel(phase: .enterCode, message: WorkTimerStore.passwordResetAlreadySentMessage).noticeKind == .info)
    #expect(passwordResetModel(phase: .enterCode, message: WorkTimerStore.passwordResetCooldownMessage).noticeKind == .info)
    #expect(passwordResetModel(phase: .enterCode, message: WorkTimerStore.passwordResetCodeRejectedMessage).noticeKind == .error)
    #expect(passwordResetModel(phase: .enterCode, message: WorkTimerStore.passwordResetInvalidCodeMessage).noticeKind == .error)
    // 3단계 거절은 전부 비밀번호 문제다(코드는 이미 통과했다) — 반드시 빨강이어야 한다.
    #expect(passwordResetModel(phase: .enterNewPassword, message: WorkTimerStore.passwordResetShortPasswordMessage).noticeKind == .error)
    #expect(passwordResetModel(phase: .enterNewPassword, message: WorkTimerStore.passwordResetRejectedPasswordMessage).noticeKind == .error)
    #expect(passwordResetModel(phase: .enterNewPassword, message: WorkTimerStore.passwordResetUpdateFailedMessage).noticeKind == .error)
}

@MainActor
@Test
func passwordResetEntryLinkHandsTheTypedEmailToTheStore() {
    // 진입점의 존재 이유는 "지금 입력해 둔 이메일을 그대로 넘기는 것"이다 — 다시 타이핑시키면 안 된다.
    // 버튼을 누를 수는 없으므로(SwiftUI 뷰다) 그 버튼이 부르는 스토어 함수를 직접 부른다.
    final class Box: @unchecked Sendable { var received: [String] = [] }
    let box = Box()
    let link = PasswordResetEntryLink(email: "  member@example.com\n") { box.received.append($0) }
    link.press()
    #expect(box.received == ["member@example.com"])
    #expect(PasswordResetEntryLink.title == "비밀번호를 잊으셨나요?")
}

@MainActor
@Test
func loginFormShowsThePasswordResetEntryPointAboveTheLoginButton() throws {
    // 로그인 폼에 진입점이 실제로 **그려지는지**를 픽셀로 본다. [로그인] 버튼(초록 그라디언트 전체폭)을
    // 기준선으로 잡고, 그 바로 위 띠에 글자 픽셀이 있는지 확인한다 — 진입점이 사라지면 그 띠는 통짜 배경이 된다.
    let bitmap = try renderBitmap(CheckMenuView(store: makeLoginStore(syncMessage: "로그인 필요")))
    let buttonTop = try #require(
        firstFullWidthGradientRow(bitmap),
        "[로그인] 버튼(초록 그라디언트)을 못 찾으면 이 검사가 헛돌고 있다는 뜻이다"
    )
    // 버튼 위 [-54, -10]px 띠 = 비밀번호 필드의 ASCII 안내 슬롯 아래 ~ 버튼 사이. 진입점 링크가 사는 자리다.
    // 링크는 accent(파랑) 글자다 — 그 색 픽셀이 이 띠에 얼마나 있는지로 "링크가 그려졌다"를 단언한다.
    // 진입점이 빠지면 이 띠는 통짜 패널 배경이라 accent 픽셀이 0 이 된다.
    let accent = accentPixelCount(bitmap, top: buttonTop - 54, bottom: buttonTop - 10)
    #expect(accent > 100, "[로그인] 버튼 바로 위에 accent 색 링크 글자가 있어야 한다 (실측 \(accent)px)")

    // 픽셀만으론 "그 글자가 재설정 진입점"이라는 것까지는 못 박지 못한다 — 로그인 폼이 이 컨트롤을
    // 쓰고 있다는 구조를 소스로 고정한다(powerAndFooterMenus… 선례와 같은 이유).
    let source = try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8)
    let loginPanel = try #require(swiftStructBody(source, name: "LoginPanel"))
    #expect(loginPanel.contains("PasswordResetEntryLink"))
    #expect(loginPanel.contains("store.beginPasswordReset(email:"))
}

@MainActor
@Test
func passwordResetPutsExactlyOneInputBoxOnEveryScreen() throws {
    // 이번 변경의 **핵심**: 코드와 새 비밀번호가 한 화면에 같이 있으면 안 된다.
    // ImageRenderer 는 TextField/SecureField 를 못 그려 샛노란 상자를 박는다 — 그 상자 개수가 곧
    // "이 화면에 입력칸이 몇 개인가"다. 화면마다 정확히 하나여야 한다.
    func boxes(_ phase: PasswordResetPhase) throws -> Int {
        let bitmap = try renderBitmap(passwordResetPanel(phase: phase, resendSeconds: 0))
        return unavailablePlaceholderRowRuns(bitmap, top: 0, bottom: bitmap.pixelsHigh - 1).count
    }
    #expect(try boxes(.enterEmail) == 1, "1단계엔 이메일 칸 하나만 있어야 한다")
    #expect(try boxes(.enterCode) == 1, "2단계엔 코드 칸 하나만 있어야 한다 — 새 비밀번호 칸이 남아 있으면 2다")
    #expect(try boxes(.enterNewPassword) == 1, "3단계엔 새 비밀번호 칸 하나만 있어야 한다 — 코드 칸이 되살아나면 2다")
    // 왕복 중에도 화면은 그대로다(입력칸이 사라지면 방금 친 값이 눈앞에서 없어진다).
    #expect(try boxes(.verifying) == 1)
    #expect(try boxes(.submitting) == 1)
}

@MainActor
@Test
func passwordResetCodeFieldKeepsTheASCIIGuard() throws {
    // 이메일/코드/새 비밀번호는 영문 입력원에서만 쳐야 한다(한글 조합 문자가 섞이면 서버가 무조건 거절한다).
    // ASCII 강제(enforcesASCII)를 건 필드만 아래에 "영어 문자만…" 안내 슬롯을 상시 확보하므로,
    // 입력 상자 아래끝과 [코드 확인] 버튼 윗줄 사이 간격으로 그 슬롯의 존재를 잰다.
    // (이제 화면당 상자가 하나뿐이라 예전처럼 상자 사이 간격으로는 못 잰다.)
    let bitmap = try renderBitmap(passwordResetPanel(phase: .enterCode, resendSeconds: 0))
    let boxes = unavailablePlaceholderRowRuns(bitmap, top: 0, bottom: bitmap.pixelsHigh - 1)
    let boxEnd = try #require(boxes.first?.end)
    let buttonTop = try #require(firstFullWidthGradientRow(bitmap, from: boxEnd))
    let gap = buttonTop - boxEnd
    // 실측(scale 2): ASCII 강제를 걸면 상자와 버튼 사이가 캡션 슬롯 때문에 벌어진다. 강제를 풀면
    // 슬롯이 통째로 사라져 VStack 간격(8pt=16px) + 패널 간격만 남는다. 그 사이인 45px 을 문턱으로 둔다.
    #expect(gap >= 45, "코드 필드 아래 ASCII 안내 슬롯이 자리를 잡고 있어야 한다 (실측 \(gap)px)")

    // 세 필드 전부 같은 강제를 받는다 — 각각 다른 화면에 있어 한 렌더로는 못 재므로 소스로 못 박는다.
    let source = try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8)
    let panel = try #require(swiftStructBody(source, name: "PasswordResetPanel"))
    #expect(panel.components(separatedBy: "enforcesASCII: true").count - 1 == 3)
}

@MainActor
@Test
func passwordResetShowsTheResendLinkOnlyOnTheCodeScreen() throws {
    // 링크 글자는 accent(파랑)뿐이다. 그 색이 이루는 **행 구간 수** = 화면에 깔린 링크 줄 수다.
    // 2단계는 [다시 받기] + [로그인으로 돌아가기] 로 두 줄, 1·3단계는 되돌아가기 한 줄이어야 한다.
    func linkRows(_ phase: PasswordResetPhase) throws -> Int {
        let bitmap = try renderBitmap(passwordResetPanel(phase: phase, resendSeconds: 0))
        return accentRowRuns(bitmap, top: 0, bottom: bitmap.pixelsHigh - 1).count
    }
    #expect(try linkRows(.enterCode) == 2, "2단계엔 재전송 링크와 취소 링크가 함께 있어야 한다")
    #expect(try linkRows(.enterNewPassword) == 1, "3단계엔 재전송 링크가 없어야 한다 — 코드는 이미 소모됐다")
    #expect(try linkRows(.enterEmail) == 1, "1단계는 아직 보낸 코드가 없으니 재전송이 없다")

    // 취소(로그인으로 돌아가기)는 **세 단계 전부**에 있어야 한다. 이게 빠지면 재설정 화면이 로그인 폼을
    // 대체하고 있으므로 앱을 껐다 켜는 것 말고는 빠져나갈 길이 없다.
    let source = try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8)
    let panel = try #require(swiftStructBody(source, name: "PasswordResetPanel"))
    let links = try #require(panel.range(of: "private var links:").map { String(panel[$0.lowerBound...]) })
    // 취소 링크는 단계 분기(if) 바깥에 있어야 조건 없이 항상 그려진다.
    #expect(links.contains("AuthLinkButton(prompt: \"\", action: \"로그인으로 돌아가기\")"))
    #expect(links.components(separatedBy: "perform(.cancel)").count - 1 == 1)
}

@MainActor
@Test
func passwordResetSuccessNoticeLandsOnTheLoginScreenAsSuccess() throws {
    // 성공하면 스토어가 idle 로 돌리고 안내를 **로그인 화면의 상태줄(syncMessage)** 로 옮겨 싣는다.
    // 그 문구가 AuthMessageKind 표에 없으면 default 로 떨어져 성공을 빨간 경고로 그린다 — 그걸 막는다.
    #expect(AuthMessageKind(WorkTimerStore.passwordResetChangedSignInMessage) == .success)
    #expect(AuthMessageKind("로그인 실패") == .error)

    // 실제로 로그인 화면에 **보이는지**를 픽셀로 본다. 상태줄은 "로그인 필요"일 때만 투명하므로,
    // 성공 문구를 세우면 초록(CheckTheme.working) 배너가 [로그인] 버튼 아래 띠에 나타나야 한다.
    // [로그인] 버튼도 같은 계열의 초록 그라디언트라, 그 버튼이 끝나는 행 **아래**만 본다.
    func statusBandGreenPixels(_ store: WorkTimerStore) throws -> Int {
        let bitmap = try renderBitmap(CheckMenuView(store: store))
        let button = try #require(fullWidthGradientRowRun(bitmap))
        return successTintPixelCount(
            bitmap,
            top: button.end + 1,
            bottom: min(button.end + 120, bitmap.pixelsHigh - 1)
        )
    }
    let store = makeLoginStore(syncMessage: WorkTimerStore.passwordResetChangedSignInMessage)
    // 스토어는 이메일을 프리필하고 비밀번호는 비운다(남아 있는 건 방금 **바뀌기 전** 값이다).
    store.password = ""
    let successPixels = try statusBandGreenPixels(store)
    #expect(successPixels > 60, "로그인 화면 상태줄에 초록 성공 안내가 보여야 한다 (실측 \(successPixels)px)")

    // 같은 자리에 오류 문구를 세우면 초록이 없어야 한다 — 위 측정이 배경을 세고 있는 게 아니라는 대조군.
    let failingGreen = try statusBandGreenPixels(makeLoginStore(syncMessage: "로그인 실패"))
    #expect(failingGreen == 0, "오류 배너 자리에 초록이 섞이면 이 측정은 성공을 증명하지 못한다 (실측 \(failingGreen)px)")
}

@MainActor
@Test
func passwordResetScreensStayWithinPopoverHeightBudget() throws {
    // 재설정 화면 7종이 팝오버 높이 상한(700pt)과 폭(340pt) 안에 잘림 없이 들어가는지 실측한다.
    // 재설정은 로그인 폼을 **대체**하므로, 로그인 화면과 비슷한 키를 유지해야 창이 튀지 않는다.
    func height(_ name: String, _ phase: PasswordResetPhase, _ message: String? = nil, _ seconds: Int = 0) throws -> (String, Int) {
        let store = passwordResetStore(phase: phase, message: message, resendSeconds: seconds)
        return (name, try #require(renderedPixelHeight(CheckMenuView(store: store))))
    }
    let heights: [(String, Int)] = try [
        height("enterEmail", .enterEmail),
        height("sending", .sending, nil, 0),
        height("enterCode-cooldown", .enterCode, "메일을 보냈어요 · 오지 않으면 주소를 확인해주세요", 47),
        height("enterCode-ready", .enterCode, nil, 0),
        height("verifying", .verifying, nil, 0),
        height("enterNewPassword", .enterNewPassword),
        height("submitting", .submitting),
        height("error", .enterCode, "코드가 맞지 않거나 만료됐어요 · 다시 받기를 눌러주세요", 12),
        ("signed-out-success", try #require(renderedPixelHeight(CheckMenuView(
            store: makeLoginStore(syncMessage: WorkTimerStore.passwordResetChangedSignInMessage)
        ))))
    ]
    for (name, pixelHeight) in heights {
        // scale 2 렌더 → 포인트 높이 = 픽셀/2.
        #expect(Double(pixelHeight) / 2.0 <= 700.0, "\(name) 화면이 팝오버 높이 예산을 넘었다 (실측 \(Double(pixelHeight) / 2.0)pt)")
    }
    // 실측값을 보고서에 옮기기 위한 기록(실패해도 판정에는 안 쓴다).
    for (name, pixelHeight) in heights {
        print("[reset-height] \(name) = \(Double(pixelHeight) / 2.0)pt")
    }
}

// MARK: - 비밀번호 재설정 육안 확인 덤프(스크래치패드)

@MainActor
@Test
func dumpPasswordResetSnapshots() throws {
    let dir = URL(
        fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/reset-split-ui",
        isDirectory: true
    )
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // 덤프는 육안 확인용이지 판정 근거가 아니다 — 쓰기 실패는 무시한다(dumpTodoSnapshots 관례).
    func dump(_ view: some View, _ name: String) throws {
        let png = try renderPNG(view)
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
    try dump(CheckMenuView(store: makeLoginStore(syncMessage: "로그인 필요")), "reset-0-login-entry")
    try dump(CheckMenuView(store: passwordResetStore(phase: .enterEmail)), "reset-1-enter-email")
    try dump(CheckMenuView(store: passwordResetStore(phase: .sending)), "reset-2-sending")
    // 첫 발송 뒤엔 5초, 재전송 뒤엔 60초라 같은 화면에서 숫자만 달라진다(판단은 스토어가 한다).
    try dump(
        CheckMenuView(store: passwordResetStore(
            phase: .enterCode,
            message: WorkTimerStore.passwordResetSentMessage,
            resendSeconds: 4
        )),
        "reset-3-enter-code-cooldown"
    )
    try dump(CheckMenuView(store: passwordResetStore(phase: .enterCode, resendSeconds: 0)), "reset-4-enter-code-ready")
    try dump(CheckMenuView(store: passwordResetStore(phase: .verifying, resendSeconds: 57)), "reset-5-verifying")
    try dump(CheckMenuView(store: passwordResetStore(phase: .enterNewPassword)), "reset-6-enter-new-password")
    try dump(CheckMenuView(store: passwordResetStore(phase: .submitting)), "reset-7-submitting")
    try dump(
        CheckMenuView(store: passwordResetStore(
            phase: .enterCode,
            message: WorkTimerStore.passwordResetCodeRejectedMessage,
            resendSeconds: 12
        )),
        "reset-8-code-error"
    )
    try dump(
        CheckMenuView(store: passwordResetStore(
            phase: .enterNewPassword,
            message: WorkTimerStore.passwordResetRejectedPasswordMessage
        )),
        "reset-9-password-error"
    )
    // 성공 직후: 재설정 화면이 사라지고 로그인 화면에 이메일 프리필 + 초록 안내가 선다.
    let done = makeLoginStore(syncMessage: WorkTimerStore.passwordResetChangedSignInMessage)
    done.password = ""
    try dump(CheckMenuView(store: done), "reset-10-signed-out-success")
    try dump(
        CheckMenuView(store: passwordResetStore(phase: .enterCode, resendSeconds: 0), previewASCIIWarning: true),
        "reset-11-ascii-warning"
    )
}

// MARK: - 재설정 화면 테스트 도우미

private func passwordResetModel(
    phase: PasswordResetPhase,
    email: String = "member@example.com",
    code: String = "",
    newPassword: String = "",
    resendSeconds: Int = 0,
    message: String? = nil
) -> PasswordResetFormModel {
    PasswordResetFormModel(
        phase: phase,
        email: email,
        code: code,
        newPassword: newPassword,
        resendSeconds: resendSeconds,
        message: message
    )
}

/// 스토어 없이 재설정 패널만 그리는 표본(값 + 클로저 주입 패널이라 가능하다).
@MainActor
private func passwordResetPanel(
    phase: PasswordResetPhase,
    message: String? = nil,
    resendSeconds: Int,
    previewASCIIWarning: Bool = false
) -> PasswordResetPanel {
    PasswordResetPanel(
        phase: phase,
        message: message,
        sentToEmail: "member@example.com",
        resendSeconds: resendSeconds,
        previewASCIIWarning: previewASCIIWarning,
        perform: { _ in }
    )
}

/// 재설정 단계를 강제로 세운 로그인 화면 스토어(팝오버 전체를 그리기 위한 것).
@MainActor
private func passwordResetStore(
    phase: PasswordResetPhase,
    message: String? = nil,
    email: String = "member@example.com",
    resendSeconds: Int = 0
) -> WorkTimerStore {
    let store = makeLoginStore(syncMessage: "로그인 필요")
    store.passwordResetPhase = phase
    store.passwordResetMessage = message
    store.passwordResetEmail = email
    store.passwordResetResendSeconds = resendSeconds
    return store
}

// MARK: - 픽셀 비교 도우미

/// 뷰를 지정 폭 고정으로 렌더한 비트맵. 픽셀 단위 비교(잘림/자리 검증)용.
@MainActor
private func renderBitmap(_ view: some View, width: CGFloat = 340, scale: CGFloat = 2) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw RenderError.failed }
    return bitmap
}

/// 두 렌더에서 서로 다른 픽셀이 이루는 사각형(픽셀 좌표, 원점 좌상단). 완전히 같으면 nil.
private func bitmapDiffBounds(
    _ a: NSBitmapImageRep,
    _ b: NSBitmapImageRep
) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
          let pa = a.bitmapData, let pb = b.bitmapData
    else { return nil }
    let bpr = a.bytesPerRow
    let spp = a.samplesPerPixel
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide {
            let offset = y * bpr + x * spp
            var sample = 0
            var differs = false
            while sample < spp {
                if pa[offset + sample] != pb[offset + sample] { differs = true; break }
                sample += 1
            }
            guard differs else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return (minX, minY, maxX, maxY)
}

/// [top, bottom] 띠에서 ImageRenderer 의 "못 그림" 표식(샛노란 경고 상자)이 차지한 사각형. 없으면 nil.
/// Menu 처럼 ImageRenderer 가 그릴 수 없는 컨트롤이 어디에 몇 개 있는지를 재는 유일한 픽셀 근거다.
/// 실측한 그 상자의 채움색은 (255, 204, 0) 이다. 파랑 성분이 0 인 게 결정적이라 — 동기화 상태 점의
/// 주황(255, 184, 84)이나 그 가장자리 혼색은 파랑이 남아 걸리지 않는다.
private func unavailablePlaceholderBounds(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int
) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return nil }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in max(0, top)...min(bitmap.pixelsHigh - 1, bottom) {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            guard data[offset] >= 240, data[offset + 1] >= 195, data[offset + 2] <= 40 else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return (minX, minY, maxX, maxY)
}

/// [top, bottom] 띠에서 "못 그림" 표식(샛노란 상자)이 차지한 **행 구간들**(위에서 아래 순).
/// unavailablePlaceholderBounds 는 합집합 사각형 하나만 주므로 상자가 몇 개인지·서로 얼마나 떨어졌는지를
/// 못 잰다. 입력 필드가 몇 개 있고 그 사이 간격(= 캡션 슬롯 유무)이 얼마인지를 보려고 따로 둔다.
private func unavailablePlaceholderRowRuns(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int
) -> [(start: Int, end: Int)] {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return [] }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    var runs: [(start: Int, end: Int)] = []
    var current: (start: Int, end: Int)?
    for y in max(0, top)...min(bitmap.pixelsHigh - 1, bottom) {
        var hasYellow = false
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            // unavailablePlaceholderBounds 와 같은 색 판정(255, 204, 0 — 파랑 성분이 0 인 게 결정적).
            if data[offset] >= 240, data[offset + 1] >= 195, data[offset + 2] <= 40 { hasYellow = true; break }
        }
        if hasYellow {
            if var run = current { run.end = y; current = run } else { current = (start: y, end: y) }
        } else if let run = current {
            runs.append(run)
            current = nil
        }
    }
    if let run = current { runs.append(run) }
    return runs
}

/// [top, bottom] 띠에서 링크 글자색(CheckTheme.accent = 84,171,255)에 가까운 픽셀 수.
/// 이 팝오버에서 파랑이 이만큼 진하게 나오는 것은 accent 뿐이라(패널 43,46,61 · 필드 채움은 더 어둡다)
/// "그 자리에 링크 글자가 그려졌다"의 픽셀 근거로 쓴다.
private func accentPixelCount(_ bitmap: NSBitmapImageRep, top: Int, bottom: Int) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    var count = 0
    for y in max(0, top)...min(bitmap.pixelsHigh - 1, bottom) {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            if b >= 190, b > r + 80, g > r + 40, g < b { count += 1 }
        }
    }
    return count
}

/// [top, bottom] 띠에서 링크 글자색(accent)이 차지한 **행 구간들**. accentPixelCount 는 합계만 주므로
/// "링크가 몇 줄인가"를 못 센다 — 재발송 링크가 어느 화면에 있고 어느 화면에 없는지를 이걸로 가른다.
/// 한 행에 3px 미만이면 안티에일리어싱 부스러기로 보고 버린다(글자 한 줄은 수십~수백 px 이다).
private func accentRowRuns(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int
) -> [(start: Int, end: Int)] {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return [] }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    var runs: [(start: Int, end: Int)] = []
    var current: (start: Int, end: Int)?
    for y in max(0, top)...min(bitmap.pixelsHigh - 1, bottom) {
        var accent = 0
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            if b >= 190, b > r + 80, g > r + 40, g < b { accent += 1 }
        }
        if accent >= 3 {
            if var run = current { run.end = y; current = run } else { current = (start: y, end: y) }
        } else if let run = current {
            runs.append(run)
            current = nil
        }
    }
    if let run = current { runs.append(run) }
    return runs
}

/// [top, bottom] 띠에서 성공 톤(CheckTheme.working = 89,224,161)에 가까운 픽셀 수.
/// [로그인] 버튼의 startGradient(최대 g=217)보다 **초록이 더 진한** 쪽만 세지만 그 차이는 얇으므로,
/// 이 함수를 쓰는 쪽이 버튼 행을 띠에서 빼 주어야 한다(fullWidthGradientRowRun 참고).
private func successTintPixelCount(_ bitmap: NSBitmapImageRep, top: Int, bottom: Int) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    var count = 0
    for y in max(0, top)...min(bitmap.pixelsHigh - 1, bottom) {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            if g >= 200, r <= 140, b >= 120, g > b + 40 { count += 1 }
        }
    }
    return count
}

/// 전체폭 prominent 버튼(AuthButton)의 첫 행. 그 버튼의 초록 그라디언트(startGradient)만 한 행에서
/// 400px 넘게 이어진다 — 같은 그라디언트를 쓰는 BrandHeader 아이콘은 38pt(76px)라 걸리지 않는다.
private func firstFullWidthGradientRow(_ bitmap: NSBitmapImageRep, from: Int = 0) -> Int? {
    fullWidthGradientRowRun(bitmap, from: from)?.start
}

/// 전체폭 그라디언트 버튼이 차지한 첫 **행 구간**(시작·끝). 버튼 아래 띠만 보고 싶을 때 쓴다 —
/// 버튼 초록과 성공 배너 초록이 색으로는 거의 안 갈려서, 자리로 갈라야 한다.
private func fullWidthGradientRowRun(
    _ bitmap: NSBitmapImageRep,
    from: Int = 0
) -> (start: Int, end: Int)? {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return nil }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    var start: Int?
    for y in max(0, from)..<bitmap.pixelsHigh {
        var green = 0
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            // startGradient 양끝: (82,217,148) ~ (46,173,158). 초록이 빨강보다 크게 앞서고 파랑보다 낮지 않다.
            // **비활성 버튼도 잡아야 한다**: 재설정 화면의 기본 버튼은 입력이 덜 찼을 때 흐려져 실측 (50,86,84)
            // 까지 내려간다 — 옛 문턱(g>=150)에 안 걸려 "버튼이 아예 없다"로 읽혔다.
            // 패널 배경(43,46,61)은 g 가 70 에 못 미쳐 여기서 먼저 탈락한다.
            if g >= 70, g > r + 25, g + 10 >= b { green += 1 }
        }
        if green >= 400 {
            if start == nil { start = y }
        } else if let first = start {
            return (start: first, end: y - 1)
        }
    }
    return start.map { (start: $0, end: bitmap.pixelsHigh - 1) }
}

/// [top, bottom] 띠에서 "전부 배경색"인 세로줄이 연속으로 가장 길게 이어진 길이(px).
/// 배경색은 그 띠에서 가장 흔한 픽셀로 잡는다 — 카드 채움색을 상수로 박지 않기 위해서다(panelStyle 은 단색).
private func longestBackgroundColumnRun(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int
) -> Int {
    guard let data = bitmap.bitmapData else { return 0 }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    let y0 = max(0, top), y1 = min(bitmap.pixelsHigh - 1, bottom)
    let x0 = max(0, left), x1 = min(bitmap.pixelsWide - 1, right)
    guard y0 <= y1, x0 <= x1 else { return 0 }

    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        let offset = y * bpr + x * spp
        return (0..<spp).map { data[offset + $0] }
    }

    // 최빈 픽셀 = 카드 배경.
    var histogram: [[UInt8]: Int] = [:]
    for y in y0...y1 {
        for x in x0...x1 { histogram[pixel(x, y), default: 0] += 1 }
    }
    guard let background = histogram.max(by: { $0.value < $1.value })?.key else { return 0 }

    var best = 0, run = 0
    for x in x0...x1 {
        var empty = true
        for y in y0...y1 where pixel(x, y) != background { empty = false; break }
        if empty { run += 1; best = max(best, run) } else { run = 0 }
    }
    return best
}

/// 비트맵의 [top,bottom]x[left,right] 사각형에서 가장 흔한 픽셀. 카드가 화면을 덮는 이 팝오버에서는
/// 그 값이 곧 **카드 채움색**이다(색을 상수로 박지 않기 위한 관례 — longestBackgroundColumnRun 과 같다).
private func dominantPixel(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int
) -> [UInt8]? {
    guard let data = bitmap.bitmapData else { return nil }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    let y0 = max(0, top), y1 = min(bitmap.pixelsHigh - 1, bottom)
    let x0 = max(0, left), x1 = min(bitmap.pixelsWide - 1, right)
    guard y0 <= y1, x0 <= x1 else { return nil }
    var histogram: [[UInt8]: Int] = [:]
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            histogram[(0..<spp).map { data[offset + $0] }, default: 0] += 1
        }
    }
    return histogram.max(by: { $0.value < $1.value })?.key
}

/// 헤더 '주간 목표' 캡션 행([이번 주 X / Y시간][%][설정][내 기록][목표 수정])의 세로 구간(픽셀).
///
/// 상수로 박지 않는다 — 헤더 위쪽(타이머 글자·아바타·배너)이 조금만 바뀌어도 엉뚱한 띠를 재게 된다.
/// 예전엔 할 일 버튼의 on/off 렌더 diff 로 찾았는데, 그 버튼이 설정 창으로 이사하면서 diff 가 사라졌다.
/// 그래서 **진행 바에서 파생**한다: 카드 안에서 콘텐츠 폭을 통째로 덮는 가로 띠는 그 5pt 캡슐 하나뿐이고,
/// 캡션 행은 그 바로 아래(4pt 간격) 첫 콘텐츠 띠다. 카드 사이 여백(8pt 이상)은 두께로 걸러 낸다.
private func goalCaptionBand(_ bitmap: NSBitmapImageRep, scale: Int = 2) -> (top: Int, bottom: Int)? {
    guard let data = bitmap.bitmapData else { return nil }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    // 바깥 padding 12 + 카드 padding 12 = 24pt. 모서리 라운딩을 피해 1pt 더 안쪽부터 본다.
    let left = 25 * scale, right = bitmap.pixelsWide - 25 * scale
    guard left < right, let panel = dominantPixel(bitmap, top: 0, bottom: bitmap.pixelsHigh - 1, left: left, right: right)
    else { return nil }

    func isPanel(_ x: Int, _ y: Int) -> Bool {
        let offset = y * bpr + x * spp
        for sample in 0..<min(spp, 3) where abs(Int(data[offset + sample]) - Int(panel[sample])) > 3 { return false }
        return true
    }
    func panelRatio(_ y: Int) -> Double {
        var same = 0
        for x in left..<right where isPanel(x, y) { same += 1 }
        return Double(same) / Double(right - left)
    }

    // (1) 카드 안으로 들어간다 = 폭이 통째로 카드 채움색인 첫 행(카드 위쪽 안쪽 여백).
    //     그 위(팝오버 바깥 여백)는 배경 그라디언트라 "카드 아님"이 100%다 — 여기서 걸러진다.
    var y = 0
    while y < bitmap.pixelsHigh, panelRatio(y) < 0.95 { y += 1 }
    guard y < bitmap.pixelsHigh else { return nil }

    // (2) 그 아래에서 폭을 통째로 덮은 첫 가로 띠 중 **두께가 5pt 근처인 것** = 진행 바.
    var barEnd: Int?
    while y < bitmap.pixelsHigh {
        guard panelRatio(y) < 0.10 else { y += 1; continue }
        var end = y
        while end + 1 < bitmap.pixelsHigh, panelRatio(end + 1) < 0.10 { end += 1 }
        if (end - y + 1) >= 4 * scale, (end - y + 1) <= 7 * scale { barEnd = end; break }
        y = end + 1
    }
    guard let bar = barEnd else { return nil }

    // (3) 바 아래 여백(4pt)을 건너뛴 첫 콘텐츠 띠가 캡션 행이다.
    var top = bar + 1
    while top < bitmap.pixelsHigh, panelRatio(top) >= 1.0 { top += 1 }
    guard top < bitmap.pixelsHigh else { return nil }
    var bottom = top
    while bottom + 1 < bitmap.pixelsHigh, panelRatio(bottom + 1) < 1.0 { bottom += 1 }
    return (top, bottom)
}

/// [top,bottom] 띠에서 카드 채움색이 아닌 픽셀을 **하나라도** 가진 칼럼들의 연속 구간(왼→오른쪽).
/// 한 줄에 나란히 선 요소(글자 덩어리 · 버튼 원)를 왼쪽부터 세는 데 쓴다.
private func inkColumnRuns(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int
) -> [(start: Int, end: Int)] {
    guard let data = bitmap.bitmapData,
          let panel = dominantPixel(bitmap, top: top, bottom: bottom, left: left, right: right)
    else { return [] }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    let y0 = max(0, top), y1 = min(bitmap.pixelsHigh - 1, bottom)
    let x0 = max(0, left), x1 = min(bitmap.pixelsWide - 1, right)
    guard y0 <= y1, x0 <= x1 else { return [] }

    func isPanel(_ x: Int, _ y: Int) -> Bool {
        let offset = y * bpr + x * spp
        for sample in 0..<min(spp, 3) where abs(Int(data[offset + sample]) - Int(panel[sample])) > 3 { return false }
        return true
    }

    var runs: [(start: Int, end: Int)] = []
    var current: (start: Int, end: Int)?
    for x in x0...x1 {
        var ink = false
        for y in y0...y1 where !isPanel(x, y) { ink = true; break }
        if ink {
            if var run = current { run.end = x; current = run } else { current = (start: x, end: x) }
        } else if let run = current {
            runs.append(run)
            current = nil
        }
    }
    if let run = current { runs.append(run) }
    return runs
}

/// 사각형 안의 "밝은 글자" 픽셀 수(세 채널 모두 120 이상). 소형 아이콘 버튼의 원 채움
/// (white 0.06 → ≈56,58,73)과 그 안의 심볼(secondaryText → ≈191,192,197)을 밝기로 가른다.
private func brightPixelCount(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int
) -> Int {
    pixelCount(bitmap, top: top, bottom: bottom, left: left, right: right) { r, g, b in
        r >= 120 && g >= 120 && b >= 120
    }
}

/// 사각형 안에서 CheckTheme.danger(도달값 255,115,117)로 칠해진 픽셀 수.
/// 빨강이 다른 두 채널을 크게 앞서면서 **초록과 파랑이 서로 비슷한** 것이 danger 의 지문이다 —
/// 동기화 상태 점의 주황(255,184,84)은 초록이 파랑보다 100 이나 높아 여기 걸리지 않는다.
private func dangerPixelCount(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int
) -> Int {
    pixelCount(bitmap, top: top, bottom: bottom, left: left, right: right) { r, g, b in
        r >= 200 && r > g + 60 && r > b + 60 && abs(g - b) <= 24
    }
}

/// 사각형 안에서 "밝은 무채색"(세 채널이 서로 16 이내 · 150 이상)인 픽셀 수.
/// 아이콘이 기본 틴트(secondaryText → ≈191,192,197)나 AppKit 이 입힌 흰색으로 그려졌음을 가리킨다.
private func neutralIconPixelCount(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int
) -> Int {
    pixelCount(bitmap, top: top, bottom: bottom, left: left, right: right) { r, g, b in
        min(r, min(g, b)) >= 150 && max(r, max(g, b)) - min(r, min(g, b)) <= 16
    }
}

private func pixelCount(
    _ bitmap: NSBitmapImageRep,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int,
    where predicate: (Int, Int, Int) -> Bool
) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    let y0 = max(0, top), y1 = min(bitmap.pixelsHigh - 1, bottom)
    let x0 = max(0, left), x1 = min(bitmap.pixelsWide - 1, right)
    guard y0 <= y1, x0 <= x1 else { return 0 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            if predicate(Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2])) { count += 1 }
        }
    }
    return count
}

/// `Sources/check/CheckMenuView.swift` 경로. 테스트 파일 위치(#filePath)에서 상대로 찾는다.
private func checkMenuViewSourceURL() -> URL {
    checkSourceURL("CheckMenuView.swift")
}

/// `Sources/check/CheckSettingsView.swift` 경로. 할 일 스위치·별명·토큰 공개의 새 거처다.
private func checkSettingsViewSourceURL() -> URL {
    checkSourceURL("CheckSettingsView.swift")
}

private func checkSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/CheckMenuRenderTests.swift
        .deletingLastPathComponent()          // Tests/checkTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // (repo root)
        .appendingPathComponent("Sources/check/\(name)")
}

/// 소스에서 주석(`//` 줄 주석 · `/* */` 블록 주석)을 걷어낸 코드만 남긴다.
///
/// 이 저장소는 "왜 그렇게 했는지"를 주석에 길게 적는 관례라, 소스 구조를 문자열 매칭으로 못 박으려 하면
/// **설명문이 자꾸 걸린다**.
/// (실제로 겪은 예: 푸터가 Menu 를 벗은 경위를 적은 주석에 `Menu` 도 `자동 실행` 도 그대로 들어 있고,
///  할 일 스위치가 설정 창의 `store.setTodoEnabled(_:)` 로 이사한 사연을 CheckMenuView 에 남긴 주석에
///  그 호출 이름이 그대로 들어 있다 — 지운 코드의 묘비명일수록 지운 심볼 이름을 적게 된다.)
/// 그 상태로 "호출부가 없다"를 단언하면 **설명을 지우면 초록이 되는** 테스트가 된다.
/// (문자열 리터럴 속 `//` 는 이 파일들에 없다 — URL 은 SupabaseConfig 에 산다.)
private func swiftCodeStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}

/// 소스에서 `struct <name>` 선언의 중괄호 본문만 잘라 낸다(중괄호 균형으로 끝을 찾는다).
private func swiftStructBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "struct \(name):"),
          let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex)
    else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open.upperBound..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

@MainActor
private func dumpTodoSnapshot(_ view: some View, _ name: String) throws {
    let dir = URL(
        fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad",
        isDirectory: true
    )
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view.frame(width: 340).fixedSize())
    renderer.scale = 3
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]),
          let cgImage = bitmap.cgImage
    else { throw RenderError.failed }
    // 파일 쓰기는 실패해도 넘어간다(saveV0211Snapshot 관례) — 덤프는 육안 확인용이지 판정 근거가 아니다.
    // 판정은 위 guard(렌더 자체가 되는가)와 아래 픽셀 검사 테스트들이 한다.
    try? png.write(to: dir.appendingPathComponent("\(name).png"))
    // 헤더 확대(위 130pt) / 푸터 확대(아래 130pt) — 아이콘 배치·정렬·잘림을 눈으로 본다.
    for (suffix, rect) in [
        ("header", CGRect(x: 0, y: 0, width: cgImage.width, height: min(cgImage.height, 390))),
        ("footer", CGRect(x: 0, y: cgImage.height - min(cgImage.height, 390), width: cgImage.width, height: min(cgImage.height, 390)))
    ] {
        guard let cropped = cgImage.cropping(to: rect) else { continue }
        let rep = NSBitmapImageRep(cgImage: cropped)
        if let croppedPNG = rep.representation(using: .png, properties: [:]) {
            try? croppedPNG.write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}

// MARK: - 3글자 메시지 UI (보내기 인라인 펼침 · 입력 필터 · 받은 메시지 표시)

/// 메시지 UI 육안 확인 PNG 를 스크래치 하위 msg-ui/ 에 저장한다(판정 근거는 아래 픽셀/값 테스트가 낸다).
@MainActor
private func saveMessageSnapshot(_ png: Data, _ name: String) {
    let dir = URL(
        fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/msg-ui",
        isDirectory: true
    )
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("\(name).png"))
}

/// 콕찌르기 패널이 열린 스토어(메시지 상태 주입 가능). 26명까지 늘릴 수 있게 이름을 생성한다 —
/// 실제 팀 규모(26명)에서 목록이 스크롤로 넘어간 상태의 창 높이를 재는 것이 이 픽스처의 목적이다.
@MainActor
private func makeMessagePanelStore(
    memberCount: Int = 5,
    myselfWorking: Bool = true,
    now: Date = Date(),
    // 3글자 메시지를 못 받는(구버전 앱) 대상들. 서버가 대상의 app_build 로 판정해 내려 주는 값을
    // 그대로 흉내 낸다 — **적지 않으면 true**(모르면 허용)라는 모델 규약을 픽스처도 따른다.
    outdatedUserIDs: Set<String> = []
) -> WorkTimerStore {
    let store = makeTeamStore(members: [], now: now)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
    store.snapshot = WorkStatusSnapshot(status: myselfWorking ? .working : .offWork, elapsedSeconds: myselfWorking ? 3_600 : 0)
    let names = ["영식", "민수", "지현", "서준", "하윤", "도현", "예린", "태우", "보라", "시우",
                 "김서연", "박도윤", "최지우", "정하준", "강예은", "조민준", "윤서아", "장우진", "임채원", "한지호",
                 "오세훈", "신유나", "권도경", "황시윤", "배수아", "문지훈"]
    store.pokeDirectory = (0..<memberCount).map { index in
        let userID = "u\(index + 1)"
        return PokeDirectoryEntry(
            userID: userID,
            name: names[index % names.count],
            avatarURL: index == 0 ? CheckMascotAssets.url(for: .neutral) : nil,
            // 근무중이 앞에 오도록 3의 배수만 자리비움으로 둔다(대상 게이트 흐림도 함께 보이게).
            isWorking: index % 3 != 2,
            canReceiveMessage: !outdatedUserIDs.contains(userID)
        )
    }
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    return store
}

// MARK: 입력 필터 — 글자·숫자만 통과(이모지·기호 차단), 한글 자모는 반드시 통과

@Test
func messageInputFilterKeepsKoreanIncludingBareJamo() {
    // 이 한 줄이 이 기능의 절반이다 — ㅇ(U+3147)·ㅋ 은 낱자모지만 실측상 otherLetter 라 통과해야 한다.
    // 막히면 "ㅇㅋ"·"ㅠㅠ" 같은 3글자 말이 통째로 죽는다.
    #expect(PokeMessageInputFilter.filtered("ㅇㅋ") == "ㅇㅋ")
    #expect(PokeMessageInputFilter.filtered("ㅠㅠ") == "ㅠㅠ")
    #expect(PokeMessageInputFilter.filtered("수고") == "수고")
    #expect(PokeMessageInputFilter.filtered("고고1") == "고고1")
    #expect(PokeMessageInputFilter.filtered("ok") == "ok")
    // ★ 분해형(초성+중성+종성)은 **입력 필터를 통과해야 한다**. 파인더·한글 IME 에서 온 글자가 이 꼴이라,
    // 여기서 지우면 "한"을 붙여넣었을 때 빈 칸이 된다. 합치는 일은 전송 직전 MessageBody.sanitized(NFC)가 한다.
    #expect(PokeMessageInputFilter.filtered("\u{1112}\u{1161}\u{11AB}") == "\u{1112}\u{1161}\u{11AB}")
    #expect(MessageBody.sanitized(PokeMessageInputFilter.filtered("\u{1112}\u{1161}\u{11AB}")) == "한")
}

@Test
func messageInputFilterFollowsTheModelsAllowedSet() {
    // 허용 집합의 권위는 MessageBody 다(뷰가 자기 표를 만들지 않는다) — 서버 정규식과 1:1인 그 표를
    // 입력 필터가 그대로 따르는지 확인한다. 표가 넓어지면(예: `^^`) 이 테스트는 저절로 따라온다.
    #expect(PokeMessageInputFilter.filtered("밥?") == "밥?")
    #expect(PokeMessageInputFilter.filtered("굿!") == "굿!")
    #expect(PokeMessageInputFilter.filtered("아~") == "아~")
    #expect(PokeMessageInputFilter.filtered("가 나") == "가 나")   // 공백은 한글 IME 확정 키라 열려 있다
    // 필터를 통과한 결과는 **반드시** 모델의 텍스트 전용 게이트를 통과한다(정규화 후 기준).
    // 두 표가 갈라지면 "쳐지는데 전송만 거부" 또는 그 반대가 생기고, 이 등식이 그걸 먼저 잡는다.
    for raw in ["밥?", "가,나", "1+1", "가-나", "굿👍", "ㅇㅋ", "★가", "가\n나"] {
        let filtered = PokeMessageInputFilter.filtered(raw)
        #expect(MessageBody.isTextOnly(MessageBody.sanitized(filtered)), "필터 통과분이 모델 게이트에 걸렸다: \(raw)")
    }
}

@Test
func messageInputFilterRemovesEmojiAndSymbols() {
    // 서비스 계층 실측: Swift 는 👨‍👩‍👧‍👦 를 1글자로 세지만 Postgres char_length 는 7로 센다.
    // 애초에 입력이 안 되면 그 어긋남 자체가 존재하지 않는다.
    #expect(PokeMessageInputFilter.filtered("굿👍") == "굿")
    #expect(PokeMessageInputFilter.filtered("👨‍👩‍👧‍👦") == "")       // ZWJ(Cf)·이모지(So) 전부 제거
    #expect(PokeMessageInputFilter.filtered("🇰🇷") == "")            // 지역표시자(So)
    #expect(PokeMessageInputFilter.filtered("👍🏻") == "")            // 스킨톤(Sk)
    #expect(PokeMessageInputFilter.filtered("❤★→") == "")
    #expect(PokeMessageInputFilter.filtered("가\n나\t다") == "가나다")   // 개행·탭(Cc)
}

@Test
func messageInputFilterMakesSwiftAndPostgresCountsAgree() {
    // 이 기능의 핵심 성질: **통과한 입력은 정규화 뒤 자소 수 == 코드포인트 수**다.
    // Postgres char_length() 는 코드포인트를 세므로, 이 등식이 곧 "화면 글자수 == 서버 글자수"의 증명이다.
    // (이모지를 열었다면 👍🏻 이 1 vs 2 로 갈려 화면만 통과시키는 상태가 생긴다.)
    let inputs = ["ㅇㅋ", "수고", "가나다", "밥?", "아~", "ok1", "\u{1112}\u{1161}\u{11AB}", "漢字", " 굿 "]
    for raw in inputs {
        let normalized = MessageBody.sanitized(PokeMessageInputFilter.filtered(raw))
        #expect(normalized.count == normalized.unicodeScalars.count, "불일치: \(raw)")
    }
}

@Test
func messageCounterSpeaksRemainingCharacters() {
    #expect(PokeMessageCounter.text("") == "3자 남음")
    #expect(PokeMessageCounter.text("수") == "2자 남음")
    #expect(PokeMessageCounter.text("수고") == "1자 남음")
    #expect(PokeMessageCounter.text("수고했") == "꽉 참")
    #expect(PokeMessageCounter.text("수고했어") == "1자 초과")
    // 길이 판정은 MessageBody 가 낸다(앞뒤 공백은 세지 않는다 — 전송값과 같은 눈금).
    #expect(PokeMessageCounter.text(" 수고 ") == "1자 남음")
    #expect(PokeMessageCounter.isSendable("수고했"))
    #expect(!PokeMessageCounter.isSendable("수고했어"))
    #expect(!PokeMessageCounter.isSendable("   "))
}

@Test
func messageReceiptAgeReadsInPlainKorean() {
    let now = Date()
    #expect(PokeMessageReceiptStrip.ageText(receivedAt: now.addingTimeInterval(-5), now: now) == "방금")
    #expect(PokeMessageReceiptStrip.ageText(receivedAt: now.addingTimeInterval(-181), now: now) == "3분 전")
    #expect(PokeMessageReceiptStrip.ageText(receivedAt: now.addingTimeInterval(-7_200), now: now) == "2시간 전")
}

// MARK: 렌더 — 접힘/펼침/꽉 참/초과/쿨타임/결과 문구/받은 메시지

@MainActor
@Test
func messageComposerRendersCollapsedAndExpanded() throws {
    let now = Date()
    // ImageRenderer 는 TextField 를 못 그려 **샛노란 상자**를 박는다. 그래서 상자 수 = 입력칸 수다.
    //
    // 예전엔 마지막 상자 하나를 dropLast() 로 버렸다 — 푸터 전원 버튼이 Menu 였고 그 자리에도 상자가
    // 박혀 "맨 아래 상자는 어느 화면에나 있는 상수"였기 때문이다. 전원 버튼이 다시 IconButton 이 되면서
    // 그 상수는 사라졌고, 이제 세는 상자는 **전부 입력칸**이다. dropLast() 를 그대로 두면 진짜 입력칸
    // 하나를 매번 버려, 작성기가 통째로 사라져도 초록으로 통과한다.
    //
    // 접힘: 행마다 [말풍선][손가락] 두 버튼만 있고 입력칸은 없다.
    let collapsed = try renderBitmap(CheckMenuView(store: makeMessagePanelStore(memberCount: 5, now: now)))
    let collapsedRuns = unavailablePlaceholderRowRuns(collapsed, top: 0, bottom: collapsed.pixelsHigh - 1)
    #expect(collapsedRuns.isEmpty)
    saveMessageSnapshot(try #require(collapsed.representation(using: .png, properties: [:])), "msg-collapsed")

    // 펼침: 그 행 아래로 작성기가 열린다 — 입력칸은 **정확히 1개**다(한 번에 한 행 규칙의 픽셀 근거).
    let expanded = try renderBitmap(
        CheckMenuView(store: makeMessagePanelStore(memberCount: 5, now: now), previewMessageComposerUserID: "u1")
    )
    let expandedRuns = unavailablePlaceholderRowRuns(expanded, top: 0, bottom: expanded.pixelsHigh - 1)
    #expect(expandedRuns.count == 1)
    // 그 입력칸은 목록 안, 푸터(맨 아래 60pt) **위**에 생겼다. 예전엔 "푸터 상자보다 위"로 봤는데
    // 그 기준점이 사라졌으므로 푸터 자리를 직접 잰다.
    #expect(expandedRuns.first!.end < expanded.pixelsHigh - 60 * 2)
    saveMessageSnapshot(try #require(expanded.representation(using: .png, properties: [:])), "msg-expanded")
}

@MainActor
@Test
func messageComposerRendersLengthStates() throws {
    let now = Date()
    for (draft, name) in [("", "empty"), ("수고", "partial"), ("수고했", "full"), ("수고했어", "over")] {
        let png = try renderPNG(
            CheckMenuView(
                store: makeMessagePanelStore(memberCount: 5, now: now),
                previewMessageComposerUserID: "u1",
                previewMessageDraft: draft
            )
        )
        #expect(png.count > 0)
        saveMessageSnapshot(png, "msg-len-\(name)")
    }
}

@MainActor
@Test
func messageComposerShowsCooldownWhileExpanded() throws {
    // 방금 보낸 상대를 다시 펼치면 **왜 안 되는지**(남은 초)가 펼친 자리에서 보여야 한다.
    let now = Date()
    let store = makeMessagePanelStore(memberCount: 5, now: now)
    store.messageCooldownUntil = ["u1": now.addingTimeInterval(42)]
    store.messageNotice = WorkTimerStore.messageCooldownNotice(seconds: 42)
    #expect(store.messageCooldownRemaining(for: "u1", now: now) == 42)
    let png = try renderPNG(CheckMenuView(store: store, previewMessageComposerUserID: "u1"))
    #expect(png.count > 0)
    saveMessageSnapshot(png, "msg-cooldown")
}

@MainActor
@Test
func messagePanelRendersAllSixOutcomeNotices() throws {
    // 서버 status 6종 → 안내 문구 6종. 문구의 권위는 스토어이고(여기서 리터럴을 다시 쓰지 않는다),
    // 이 테스트는 여섯이 서로 다르고 화면에 실제로 그려진다는 것만 픽셀로 확인한다.
    let now = Date()
    let notices: [(String, String)] = [
        ("ok", WorkTimerStore.messageSentNotice),
        ("not_working", WorkTimerStore.messageNotWorkingNotice),
        ("target_focused", WorkTimerStore.messageTargetFocusedNotice),
        ("too_long", WorkTimerStore.messageTooLongNotice),
        ("invalid", WorkTimerStore.messageInvalidNotice),
        ("cooldown", WorkTimerStore.messageCooldownNotice(seconds: 47))
    ]
    #expect(Set(notices.map(\.1)).count == 6)
    for (name, text) in notices {
        let store = makeMessagePanelStore(memberCount: 4, now: now)
        store.messageNotice = text
        let png = try renderPNG(CheckMenuView(store: store, previewMessageComposerUserID: "u1"))
        #expect(png.count > 0)
        saveMessageSnapshot(png, "msg-notice-\(name)")
    }
}

@MainActor
@Test
func messageNoticeOutranksPokeNoticeInTheSharedLine() throws {
    // 두 문구가 같은 줄을 쓰지만 상태는 스토어에서 나뉘어 있다 — 메시지 결과가 먼저다(사용자가 방금 한 일).
    let now = Date()
    let store = makeMessagePanelStore(memberCount: 4, now: now)
    store.pokeNotice = "지금은 찌를 수 없어요"
    store.messageNotice = WorkTimerStore.messageSentNotice
    let withBoth = try renderBitmap(CheckMenuView(store: store))
    let onlyPoke = makeMessagePanelStore(memberCount: 4, now: now)
    onlyPoke.pokeNotice = "지금은 찌를 수 없어요"
    let pokeOnly = try renderBitmap(CheckMenuView(store: onlyPoke))
    // 같은 자리에 다른 글자가 그려졌다(줄 자체가 사라지거나 겹치지 않았다).
    #expect(bitmapDiffBounds(withBoth, pokeOnly) != nil)
    saveMessageSnapshot(try #require(withBoth.representation(using: .png, properties: [:])), "msg-notice-priority")
}

@MainActor
@Test
func messageReceiptStripRendersInsidePopover() throws {
    let now = Date()
    let store = makeMessagePanelStore(memberCount: 5, now: now)
    store.receivedMessages = [
        ReceivedMessage(id: "m1", fromName: "김서연", body: "밥?", createdAt: now.addingTimeInterval(-180)),
        ReceivedMessage(id: "m2", fromName: "박도윤", body: "ㅇㅋ", createdAt: now.addingTimeInterval(-60))
    ]
    #expect(store.currentMessage?.body == "밥?")
    #expect(store.waitingMessageCount == 1)
    let png = try renderPNG(CheckMenuView(store: store))
    #expect(png.count > 0)
    saveMessageSnapshot(png, "msg-received")
}

// MARK: 창 높이 예산 — 26명 목록에서 펼쳐도 상한(700pt)을 넘지 않는다

@MainActor
@Test
func messageComposerNeverGrowsWindowBeyondCap() throws {
    let now = Date()
    // 26명(실제 팀 규모) — 목록이 이미 스크롤 상한에 걸려 있다.
    let collapsedHeight = try #require(renderedPixelHeight(CheckMenuView(store: makeMessagePanelStore(memberCount: 26, now: now))))
    let expandedHeight = try #require(
        renderedPixelHeight(
            CheckMenuView(store: makeMessagePanelStore(memberCount: 26, now: now), previewMessageComposerUserID: "u1")
        )
    )
    #expect(Double(collapsedHeight) / 2.0 <= 700.0)
    #expect(Double(expandedHeight) / 2.0 <= 700.0)
    // **펼쳐도 창이 자라지 않는다** — 펼침은 리스트 안에서 일어나고 리스트 상한은 펼침과 무관하다.
    #expect(expandedHeight == collapsedHeight)
}

@MainActor
@Test
func messageComposerStaysWithinCapAtTheNoScrollBoundary() throws {
    // 무스크롤 상한(7행)에서 펼치면 리스트가 상한을 넘어 스크롤로 전환된다 — 창 높이는 그대로여야 한다.
    let now = Date()
    let base = try #require(renderedPixelHeight(CheckMenuView(store: makeMessagePanelStore(memberCount: 7, now: now))))
    let expanded = try #require(
        renderedPixelHeight(
            CheckMenuView(store: makeMessagePanelStore(memberCount: 7, now: now), previewMessageComposerUserID: "u1")
        )
    )
    #expect(Double(base) / 2.0 <= 700.0)
    #expect(Double(expanded) / 2.0 <= 700.0)
    #expect(expanded == base)
}

@MainActor
@Test
func messagePanelStaysWithinCapWithBannerAndReceipt() throws {
    // 최악 조합: 26명 + 최상단 배너 + 받은 메시지 줄 + 펼친 작성기.
    let now = Date()
    let store = makeMessagePanelStore(memberCount: 26, now: now)
    store.receivedMessages = [ReceivedMessage(id: "m1", fromName: "김서연", body: "밥?", createdAt: now)]
    let height = try #require(
        renderedPixelHeight(
            CheckMenuView(
                store: store,
                previewLongSessionBanner: true,
                previewMessageComposerUserID: "u1"
            )
        )
    )
    #expect(Double(height) / 2.0 <= 700.0)
}

@MainActor
@Test
func messageComposerHeightMatchesItsDeclaredConstant() throws {
    // 목록 높이 예산이 이 상수를 그대로 쓰므로, 실제 렌더 높이와 어긋나면 예산 계산이 근거를 잃는다.
    let holder = MessageDraftHolder()
    let composer = PokeMessageComposer(
        targetName: "영식",
        text: Binding(get: { holder.text }, set: { holder.text = $0 }),
        onSend: { _ in },
        onCancel: {}
    )
    let height = try #require(renderedPixelHeight(composer))
    #expect(Double(height) / 2.0 == Double(PokeMessageComposer.height))
}

@Observable
@MainActor
final class MessageDraftHolder {
    var text: String = ""
}

@MainActor
@Test
func messagePanelHeightMeasurementDump() throws {
    // 26명(실제 팀 규모) 목록의 육안 확인 PNG + 창 상한 재확인. 스크롤 대신 클립으로 그린다
    // (ImageRenderer 는 ScrollView 내용을 못 그린다). 실측: 세 경우 모두 654pt — 상한 700pt 안.
    let now = Date()
    // 26명은 이름순 정렬이라 u1(영식)이 화면 밖으로 밀린다 — 클립 스냅샷에서 작성기를 보려면
    // 첫 화면에 남는 대상(u23 권도경)을 펼친다. 앱에서는 ScrollViewReader 가 펼친 자리로 끌어올린다.
    for (count, target) in [(26, nil), (26, "u23"), (7, "u1")] as [(Int, String?)] {
        let expanded = target != nil
        let store = makeMessagePanelStore(memberCount: count, now: now)
        let view = CheckMenuView(
            store: store,
            previewClipsOverflowList: true,
            previewMessageComposerUserID: target
        )
        let height = try #require(renderedPixelHeight(view))
        #expect(Double(height) / 2.0 <= 700.0)
        saveMessageSnapshot(try renderPNG(view), "msg-\(count)명-\(expanded ? "펼침" : "접힘")")
    }
}

@MainActor
@Test
func messageComposerWarnsWhenTheInputFilterRemovesSomething() throws {
    // 붙여넣은 이모지가 그냥 사라지면 앱이 고장 난 것으로 읽힌다 — 사라진 이유를 머리줄이 2.5초간 말한다.
    // (서비스 계층이 .unsupportedCharacters 를 invalid 로 접으며 이 설명을 입력 단계에 맡겼다.)
    let holder = MessageDraftHolder()
    holder.text = "굿"
    let warned = PokeMessageComposer(
        targetName: "영식",
        text: Binding(get: { holder.text }, set: { holder.text = $0 }),
        previewFilterWarning: true,
        onSend: { _ in },
        onCancel: {}
    )
    let png = try renderPNG(warned)
    #expect(png.count > 0)
    saveMessageSnapshot(png, "msg-filter-warning")
    // 안내가 떠도 펼침 높이는 그대로다(높이가 흔들리면 목록 예산이 근거를 잃는다).
    #expect(Double(try #require(renderedPixelHeight(warned))) / 2.0 == Double(PokeMessageComposer.height))
    // 사유별로 다른 문구를 쓴다 — 이모지에 대고 "3글자까지"라고 하면 사용자는 줄이다가 계속 막힌다.
    #expect(PokeMessageComposer.filterWarningText != WorkTimerStore.messageTooLongNotice)
}

@MainActor
@Test
func messageEntryPointCoversExactlyThePokeTargets() throws {
    // 메시지 진입점은 찌르기와 **같은 목록·같은 게이트**를 쓴다. 내가 비근무면 두 버튼이 함께 흐려지고,
    // 근무중이면 함께 살아난다 — 한쪽만 살아 있는 화면이 있으면 사용자가 규칙을 설명할 수 없다.
    let now = Date()
    let working = try renderBitmap(CheckMenuView(store: makeMessagePanelStore(memberCount: 4, myselfWorking: true, now: now)))
    let offWork = try renderBitmap(CheckMenuView(store: makeMessagePanelStore(memberCount: 4, myselfWorking: false, now: now)))
    // 목록 영역(패널 아래쪽 절반)에서 accent 픽셀이 크게 줄어든다 = 두 버튼이 함께 죽었다.
    let band = (top: working.pixelsHigh / 2, bottom: working.pixelsHigh - 1)
    let live = accentPixelCount(working, top: band.top, bottom: band.bottom)
    let dead = accentPixelCount(offWork, top: band.top, bottom: band.bottom)
    #expect(live > dead * 3)
    saveMessageSnapshot(try #require(offWork.representation(using: .png, properties: [:])), "msg-offwork")
}

// MARK: - 구버전 상대 게이트 — 메시지만 잠그고 찌르기는 건드리지 않는다
//
// 실사용 신고: 구버전(≤0.2.27) 상대에게 메시지를 보내면 상대 화면에는 **그냥 콕 찔린 것**으로 뜬다.
// 구버전 클라가 모르는 kind 를 normal 로 접고, take_pokes 는 서버 원자 소비라 그 3글자는 영영 사라진다.
// 서버·스토어는 이미 막지만(구버전에겐 안 주고 서버에 남긴다), 화면 몫은 **보내기 전에 알게 하는 것**이다.

/// 버전 게이트 육안 확인 PNG. 판정 근거는 아래 픽셀 테스트가 내고, 이 파일들은 눈으로 보기 위한 것이다.
@MainActor
private func saveVersionGateSnapshot(_ png: Data, _ name: String) {
    let dir = URL(
        fileURLWithPath: "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/version-gate-ui",
        isDirectory: true
    )
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("\(name).png"))
}

@MainActor
@Test
func outdatedTargetLosesOnlyTheMessageButtonNeverThePokeButton() throws {
    // 세 렌더는 **한 사람(u4 서준)만** 다르다: 기준 / 구버전 / 찌르기 쿨타임.
    let now = Date()
    let base = try renderBitmap(CheckMenuView(store: makeMessagePanelStore(memberCount: 5, now: now)))
    let outdated = try renderBitmap(
        CheckMenuView(store: makeMessagePanelStore(memberCount: 5, now: now, outdatedUserIDs: ["u4"]))
    )
    let coolingStore = makeMessagePanelStore(memberCount: 5, now: now)
    coolingStore.pokeCooldownUntil = ["u4": now.addingTimeInterval(45)]
    // 메시지 쿨타임은 **다른 사람(u2)** 에게 걸어 둔다. 이 줄이 있어도 아래 diff 사각형이 u4 의 찌르기 버튼
    // 하나로 남는다는 것이 곧 "메시지 쿨타임은 행에서 아무것도 바꾸지 않는다"의 증거다 —
    // 그건 의도된 설계다(쿨타임 중에도 펼칠 수 있어야 작성기가 남은 초를 말해 줄 수 있다).
    coolingStore.messageCooldownUntil = ["u2": now.addingTimeInterval(45)]
    #expect(coolingStore.pokeCooldownRemaining(for: "u4", now: now) > 0)
    #expect(coolingStore.messageCooldownRemaining(for: "u2", now: now) > 0)
    let cooling = try renderBitmap(CheckMenuView(store: coolingStore))
    saveVersionGateSnapshot(try #require(cooling.representation(using: .png, properties: [:])), "gate-cooldown")

    // 찌르기 버튼의 x 자리를 **렌더로 알아낸다**(좌표 상수를 손으로 적으면 행 배치가 바뀌는 날 조용히 거짓말한다).
    // 쿨타임은 그 행에서 찌르기 버튼 하나만 흐리게 만드므로, 그 diff 사각형이 곧 찌르기 버튼의 자리다.
    let pokeBox = try #require(bitmapDiffBounds(base, cooling), "쿨타임이 찌르기 버튼을 흐리게 바꿔야 한다")
    let messageBox = try #require(
        bitmapDiffBounds(base, outdated),
        "구버전 상대의 메시지 버튼이 꺼져야 한다 — 픽셀이 그대로면 화면에 게이트가 없는 것이다"
    )
    // ★ 이 한 줄이 계약 전체다: 바뀐 자리가 찌르기 버튼보다 **왼쪽에서 끝난다** =
    // 메시지 버튼만 죽었고 찌르기 버튼은 한 픽셀도 건드리지 않았다(구버전도 찔림은 그대로 받는다).
    #expect(messageBox.maxX < pokeBox.minX)
    // 두 사각형이 같은 행에서 나왔다는 확인 — 다른 사람 행을 재고 있으면 위 비교는 아무 뜻이 없다.
    #expect(messageBox.minY < pokeBox.maxY && pokeBox.minY < messageBox.maxY)
}

@MainActor
@Test
func threeDisabledKindsStayApartOnScreen() throws {
    // 정상 / 구버전 / 자리비움 세 행이 한 화면에 함께 그려진다(u4 서준만 구버전, u3 지현은 자리비움).
    // 자리비움은 **두 버튼이 함께** 죽고 구버전은 메시지만 죽으므로, 찌르기 버튼(accent 원형)이
    // 남아 있는 행의 개수가 곧 두 상태를 가르는 픽셀 근거다.
    let now = Date()
    let base = try renderBitmap(CheckMenuView(store: makeMessagePanelStore(memberCount: 5, now: now)))
    let mixed = try renderBitmap(
        CheckMenuView(store: makeMessagePanelStore(memberCount: 5, now: now, outdatedUserIDs: ["u4"]))
    )
    // accent 가 있는 행 구간의 **개수**는 그대로다 = 구버전 행에도 살아 있는 찌르기 버튼이 남았다.
    // (찌르기까지 같이 껐다면 그 행에서 accent 가 통째로 사라져 구간이 하나 줄고, 자리비움 행과 같은 모양이 된다.)
    let baseRuns = accentRowRuns(base, top: 0, bottom: base.pixelsHigh - 1)
    let mixedRuns = accentRowRuns(mixed, top: 0, bottom: mixed.pixelsHigh - 1)
    #expect(mixedRuns.count == baseRuns.count)
    // 그래도 화면은 달라졌다(메시지 버튼이 흐려졌다) — 개수만 같고 내용은 같지 않다.
    #expect(bitmapDiffBounds(base, mixed) != nil)
    saveVersionGateSnapshot(try #require(mixed.representation(using: .png, properties: [:])), "gate-three-states")
    saveVersionGateSnapshot(try #require(base.representation(using: .png, properties: [:])), "gate-baseline")
}

@MainActor
@Test
func expandedComposerStaysOpenAndOnlyLocksWhenTheTargetTurnsOutOfDate() throws {
    // 폴링이 펼쳐 둔 사람의 canReceiveMessage 를 false 로 뒤집는 순간. **접지 않는다** —
    // 접으면 치던 글자가 이유 없이 사라지고, 폴링이 사용자의 화면을 여닫는 규칙이 새로 생긴다.
    let now = Date()
    let open = try renderBitmap(
        CheckMenuView(
            store: makeMessagePanelStore(memberCount: 5, now: now),
            previewMessageComposerUserID: "u4",
            previewMessageDraft: "수고"
        )
    )
    let locked = try renderBitmap(
        CheckMenuView(
            store: makeMessagePanelStore(memberCount: 5, now: now, outdatedUserIDs: ["u4"]),
            previewMessageComposerUserID: "u4",
            previewMessageDraft: "수고"
        )
    )
    // 입력칸(ImageRenderer 의 '못 그림' 노란 상자)은 여전히 목록 안에 정확히 1개 — 작성기가 살아 있다.
    // 예전엔 마지막 상자 하나(푸터 Menu 자리)를 dropLast() 로 버렸다. 전원 버튼이 Menu 를 벗으면서
    // 그 상수는 사라졌고, 지금 세는 상자는 전부 입력칸이다 — 버리면 작성기가 접혀도 초록이 된다.
    let openBoxes = unavailablePlaceholderRowRuns(open, top: 0, bottom: open.pixelsHigh - 1)
    let lockedBoxes = unavailablePlaceholderRowRuns(locked, top: 0, bottom: locked.pixelsHigh - 1)
    #expect(openBoxes.count == 1)
    #expect(lockedBoxes.count == 1)
    // 창 높이도 그대로다 — 접혔다면 펼침 덩어리만큼 줄어든다.
    #expect(locked.pixelsHigh == open.pixelsHigh)
    // 대신 **보내기는 잠겼다**: 머리줄이 사유를 말하고 [보내기] 캡슐의 accent 가 빠진다(행의 메시지 버튼도 함께).
    #expect(bitmapDiffBounds(open, locked) != nil)
    #expect(
        accentPixelCount(locked, top: 0, bottom: locked.pixelsHigh - 1)
            < accentPixelCount(open, top: 0, bottom: open.pixelsHigh - 1)
    )
    saveVersionGateSnapshot(try #require(locked.representation(using: .png, properties: [:])), "gate-composer-locked")
    saveVersionGateSnapshot(try #require(open.representation(using: .png, properties: [:])), "gate-composer-open")
}

// MARK: - 근무 시작/종료 알약의 키보드 포커스 링
//
// 실사용 신고: 팝오버를 열 때마다 근무 시작/종료 버튼 둘레에 파란 테두리가 생긴다 — 팝오버가 열리면서
// 그 버튼이 첫 포커스를 받아 macOS 가 그리는 키보드 포커스 링이다.
//
// ⚠️ **이 링은 렌더로 검증할 수 없다.** ImageRenderer 는 키 윈도우도 first responder 도 없는 오프스크린
// 그리기라 포커스 링을 애초에 그리지 않는다(고쳐도 안 고쳐도 픽셀이 같다). 그래서 판정 근거를
// **소스 구조**로 세운다 — 어느 자리에 수식어가 붙었는지가 이 수정의 전부이기 때문이다.
// 아래 렌더 테스트는 "그 수식어가 레이아웃을 흔들지 않았다"만 본다(그건 픽셀로 볼 수 있다).

@Test
func focusEffectsAreDisabledOnTheWorkTogglePillAndNowhereElse() throws {
    let source = try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8)
    // ★ 이 화면 전체에서 딱 **한 번**만 나온다. 두 번째가 생기는 순간 문제는 "어디에 걸렸는가"가 된다 —
    // 이 수식어는 걸린 자리의 **하위 전체**를 덮으므로, 입력칸을 품은 컨테이너에 걸리면
    // 로그인·재설정 코드·할 일·3글자 메시지의 커서 표시가 통째로 죽는다.
    #expect(source.components(separatedBy: ".focusEffectDisabled()").count - 1 == 1)
    // 그 한 번은 헤더 카드 안, 근무 시작/종료 알약 **뒤**에 붙어 있다(= 그 버튼 하나만 덮는다).
    let header = try #require(swiftStructBody(source, name: "HeaderCard"))
    let pill = try #require(header.range(of: "WorkTogglePill("), "헤더 카드가 근무 시작/종료 알약을 그린다")
    let modifier = try #require(header.range(of: ".focusEffectDisabled()"), "링을 끄는 자리는 이 알약이다")
    #expect(pill.upperBound < modifier.lowerBound)
    // 입력칸이 사는 화면들은 이 수식어를 **받지 않는다**. 위 '한 번' 단언을 이름으로 못 박아,
    // 나중에 루트로 올리는 수정이 들어와도 여기서 먼저 걸리게 한다.
    for name in ["CheckMenuView", "PokeMessageComposer"] {
        let body = try #require(swiftStructBody(source, name: name))
        #expect(!body.contains("focusEffectDisabled"), "\(name) 가 포커스 표시를 끄면 지금 어디에 타이핑되는지 알 수 없어진다")
    }
    // .focusable(false) 로 도달 자체를 막지 않았다 — 그건 키보드만 쓰는 사람에게서 근무 시작/종료를 빼앗는다.
    #expect(!header.contains(".focusable(false)"))
}

@MainActor
@Test
func theWorkTogglePillKeepsBothFacesAndItsLayoutAfterDisablingFocusEffects() throws {
    // 같은 버튼의 두 얼굴(초록 [근무 시작] / 주황 [근무 종료])이 그대로 그려지는지 육안 + 픽셀 확인.
    // 포커스 링 자체는 여기 안 나오지만(위 MARK 참고), **레이아웃이 흔들리지 않았다**는 것은 볼 수 있다.
    let now = Date()
    func headerStore(working: Bool) -> WorkTimerStore {
        let store = makeTeamStore(members: [], now: now)
        store.snapshot = WorkStatusSnapshot(status: working ? .working : .offWork, elapsedSeconds: working ? 3_600 : 0)
        return store
    }
    let offWork = try renderBitmap(CheckMenuView(store: headerStore(working: false)))
    let working = try renderBitmap(CheckMenuView(store: headerStore(working: true)))
    // 두 얼굴은 서로 다르게 그려진다(같은 자리·같은 크기, 색과 글자만 바뀐다).
    #expect(working.pixelsHigh == offWork.pixelsHigh)
    let diff = try #require(bitmapDiffBounds(offWork, working))
    // 알약은 헤더 카드 안이므로 그 차이는 화면 위쪽에서 시작한다(버튼이 사라지거나 밀려나지 않았다).
    #expect(diff.minY < working.pixelsHigh / 3)
    saveVersionGateSnapshot(try #require(offWork.representation(using: .png, properties: [:])), "focus-pill-offwork")
    saveVersionGateSnapshot(try #require(working.representation(using: .png, properties: [:])), "focus-pill-working")
}

@Test
func theOutdatedTooltipQuotesTheStoreNoticeInsteadOfInventingItsOwnWording() throws {
    // 보내기 전(툴팁)과 보낸 뒤(안내줄)가 **같은 말**을 해야 한다. 리터럴을 베껴 두면 한쪽만 고쳐지는 날이 온다.
    let source = try String(contentsOf: checkMenuViewSourceURL(), encoding: .utf8)
    let body = try #require(swiftStructBody(source, name: "PokeDirectoryRowView"))
    #expect(body.contains("WorkTimerStore.messageTargetOutdatedNotice"))
    #expect(!body.contains(WorkTimerStore.messageTargetOutdatedNotice), "같은 문장을 리터럴로 다시 적어 두면 안 된다")
}
