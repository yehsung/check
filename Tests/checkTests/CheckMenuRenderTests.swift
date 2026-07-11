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

private func isolatedRenderDefaults() -> UserDefaults {
    let suiteName = "check-render-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
