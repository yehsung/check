import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.56 — 맥 [미션] 화면 분리 · 울트라 화면은 보유 수량만 · 연속 근무는 헤더로.
//
// 사장님 지시(2026-10-16) 원문: "울트라 게이지에서는 울트라 보유수량만 표현하고. 나머지는 전부 미션 페이지로 빼내자.
// 메인페이지 오른쪽에 주요 버튼들 있는곳으로 빼고 미션 클릭하면 볼 수 있게끔. 매일 첫 근무 설명은 빼버리고,
// 연속 근무일수는 [헤더 카드] 여기에 뜨게끔 밖으로 빼줘. 연속 0일 근무! 이런식으로."
//
// 여기서 잰다:
//  ① 레일 — [상점] 바로 아래 [미션] 칸이 있고, 그 칸의 동작이 스토어 문(toggleMissionPanel)이다 · 열리면 그 칸만 강조색.
//  ② 스토어 — 다른 하위 패널 **전부와 양방향 배타**(콕찌르기 배지로 들어온 울트라 포함) · 로그아웃이 내린다 ·
//     여는 순간 지갑 sync + 주간 조회 · 안내줄은 미션 화면의 것(울트라를 닫아도 안 지워진다).
//  ③ 화면 — 미션 화면은 3시간 줄 · 주간 줄 · 안내줄을 그리고 "매일 첫 근무" · "연속 출근" 줄은 안 그린다 ·
//     울트라 화면은 그 어느 것도 안 그리고 잔량 카드만 그린다.
//  ④ 헤더 — "연속 N일 근무!" 칩(0일 · 3일) · 지갑이 답하기 전에는 안 그린다 · 최악 폭(동기화 대기 · 999일 · 긴 주간 캡션)에서
//     윗줄(상태 · 타이머 · 알약)과 캡션의 주간 글자 · 퍼센트 · 연필을 1px 도 안 건드린다 · 높이 0pt.
//  ⑤ 높이 — 레일 바닥(432pt)이 창의 최소 높이이고 그때 푸터가 바닥에 붙는다 · 본문 카드가 푸터 바로 위까지 닿는다(빈 띠 없음) ·
//     최악 조합 ≤ 700pt.
//  ⑦ 검토 수리 — 팝오버가 넘긴 [뒤로] · [다시 시도] 클로저를 실제로 불러 본다 · 배지 울트라에서 어느 문을 눌러도 깃발 하나 ·
//     지갑 화면을 연 채 팝오버를 다시 열면 지갑 sync · 칩 바탕 캡슐 · 배지 툴팁이 '충전 방법'을 약속하지 않는다.
// 실네트워크 없음(호스트별 스텁) · 창 없음(ImageRenderer 만 — 화면에 아무것도 안 뜬다).

// MARK: - 공용 도우미

/// `//` · `/* */` 주석을 걷어낸다(문자열 리터럴 안은 남긴다) — 설명을 지워야만 초록이 되는 계약을 만들지 않는다.
private func v0356Code(_ name: String) throws -> String {
    V0317ShopTests.stripped(try V0317ShopTests.source(name))
}

/// 선언 머리(`private struct X: View {`)부터 중괄호 균형이 닫히는 곳까지(주석 걷은 코드 기준).
private func v0356Body(_ code: String, header: String) throws -> String {
    let head = try #require(code.range(of: header), "\(header) 선언을 못 찾았다")
    var depth = 0
    var index = head.lowerBound
    var opened = false
    while index < code.endIndex {
        let c = code[index]
        if c == "{" { depth += 1; opened = true }
        if c == "}" {
            depth -= 1
            if opened && depth == 0 { return String(code[head.lowerBound...index]) }
        }
        index = code.index(after: index)
    }
    throw V0356Error.unbalanced
}

private enum V0356Error: Error { case unbalanced, renderFailed }

/// 뷰 값 트리(Mirror)에서 이름이 `names` 에 든 노드를 **순서대로** 모은다(클래스로는 안 내려간다 — 스토어 순환).
private func v0356Collect(_ names: Set<String>, in value: Any, into out: inout [(name: String, value: Any)], budget: inout Int) {
    guard budget > 0 else { return }
    budget -= 1
    let mirror = Mirror(reflecting: value)
    let typeName = String(describing: mirror.subjectType)
    if names.contains(typeName) { out.append((typeName, value)); return }
    guard mirror.displayStyle != .class else { return }
    for child in mirror.children { v0356Collect(names, in: child.value, into: &out, budget: &budget) }
}

private func v0356Child(_ label: String, of value: Any) -> Any? {
    Mirror(reflecting: value).children.first { $0.label == label }?.value
}

/// 팝오버를 **자연 폭**으로 굳을 때까지 굽는다(ImageRenderer 의 첫 두 장 함정 — CheckRenderSettle 머리 주석).
@MainActor
private func v0356Bitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw V0356Error.renderFailed }
    return bitmap
}

@MainActor
private func v0356PNG(_ view: some View) throws -> Data {
    try #require(try v0356Bitmap(view).representation(using: .png, properties: [:]))
}

/// 두 그림이 갈리는 픽셀의 경계(pt). 같으면 nil. 크기가 다르면 전체.
private func v0356DiffBox(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGRect? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
          let pa = a.bitmapData, let pb = b.bitmapData else {
        return CGRect(x: 0, y: 0, width: CGFloat(max(a.pixelsWide, b.pixelsWide)) / 2, height: CGFloat(max(a.pixelsHigh, b.pixelsHigh)) / 2)
    }
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    let spp = a.samplesPerPixel
    for y in 0..<a.pixelsHigh {
        let ra = pa + y * a.bytesPerRow, rb = pb + y * b.bytesPerRow
        for x in 0..<a.pixelsWide {
            let o = x * spp
            if ra[o] != rb[o] || ra[o + 1] != rb[o + 1] || ra[o + 2] != rb[o + 2] {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                  width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
}

/// 본문 열(x 14…326pt)에서 창 배경과 다른 픽셀이 있는 마지막 줄(pt). 푸터 아래가 비었는지 재는 자다.
private func v0356BodyInkBottom(_ bitmap: NSBitmapImageRep) -> CGFloat {
    guard let data = bitmap.bitmapData else { return 0 }
    let spp = bitmap.samplesPerPixel
    // 기준 = 같은 줄의 창 왼쪽 가장자리(본문 밖 · 그라디언트 배경이라 줄마다 다시 읽는다).
    for y in stride(from: bitmap.pixelsHigh - 1, through: 0, by: -1) {
        let row = data + y * bitmap.bytesPerRow
        let bg = (Int(row[2 * spp]), Int(row[2 * spp + 1]), Int(row[2 * spp + 2]))
        for x in stride(from: 28, to: 652, by: 1) {
            let o = x * spp
            if abs(Int(row[o]) - bg.0) > 8 || abs(Int(row[o + 1]) - bg.1) > 8 || abs(Int(row[o + 2]) - bg.2) > 8 {
                return CGFloat(y + 1) / 2
            }
        }
    }
    return 0
}

/// 본문 열 왼쪽 안쪽 세로 한 줄(x = 20pt — 카드의 안쪽 padding 자리라 카드 위에서는 **언제나 카드 바탕**이다)을 위→아래로 훑어
/// 카드 구간 [top, bottom)(pt)을 낸다. 배경 판정은 `v0356BodyInkBottom` 과 같은 자(같은 줄의 창 왼쪽 가장자리 색 · 차이 > 8).
/// 카드와 카드 사이 빈 띠(본문 열 VStack 간격 10pt + 둥근 모서리 몫 ~1pt)가 구간 사이 틈으로 잡힌다.
private func v0356CardRuns(_ bitmap: NSBitmapImageRep) -> [(top: CGFloat, bottom: CGFloat)] {
    guard let data = bitmap.bitmapData else { return [] }
    let spp = bitmap.samplesPerPixel
    let o = 40 * spp
    var runs: [(top: CGFloat, bottom: CGFloat)] = []
    var start: Int?
    for y in 0..<bitmap.pixelsHigh {
        let row = data + y * bitmap.bytesPerRow
        let bg = (Int(row[2 * spp]), Int(row[2 * spp + 1]), Int(row[2 * spp + 2]))
        let ink = abs(Int(row[o]) - bg.0) > 8 || abs(Int(row[o + 1]) - bg.1) > 8 || abs(Int(row[o + 2]) - bg.2) > 8
        if ink, start == nil { start = y }
        if !ink, let s = start { runs.append((CGFloat(s) / 2, CGFloat(y) / 2)); start = nil }
    }
    if let s = start { runs.append((CGFloat(s) / 2, CGFloat(bitmap.pixelsHigh) / 2)) }
    return runs
}

/// 렌더용 메인 화면 스토어. **네트워크가 이 맥 밖으로 한 건도 안 나간다** — 두 겹이다:
///  ① 팝오버의 `.task { activateStoredSession() }` 은 ImageRenderer 에서도 **돈다**(v0.3.56 실측: 기본 서비스 스토어를 그리면
///     memberships · work_tick · ultra_wallet_sync … 가 실제 프로젝트 주소로 나갔다). 그래서 활성화를 '이미 끝났고 팀 상태도 방금
///     받았다'로 세워 그 길을 요청 0건으로 끝낸다.
///  ② 그래도 새는 요청은 호스트별 스텁으로 가고 **답하지 않는다**(10분 지연) — 렌더 도중 늦은 응답이 스토어를 바꿔 그림이
///     흔들리는 일도 없다.
@MainActor
private func v0356RenderStore(members: Int = 0,
                              working: Bool = true,
                              pendingSync: Bool = false,
                              loaded: Bool = true,
                              streak: Int = 3,
                              missions: [MissionProgress]? = nil,
                              weekly: WeeklyWorkStatus? = nil,
                              notice: String? = nil,
                              balance: Int? = 3,
                              function: String = #function, line: Int = #line) -> WorkTimerStore {
    let tag = "v0356-render-L\(line)"
    let home = CheckTestScratch.directory("token-\(tag)", function: function)
    let tokens = TokenUsageStore(
        defaults: CheckTestScratch.defaults("token-\(tag)", function: function),
        homeDirectory: home.appendingPathComponent("home", isDirectory: true),
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
    )
    let host = "v0356-silent-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { _, _, _ in .init(body: "[]", delay: 600) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service,
                               environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: CheckTestScratch.defaults(tag, function: function),
                               tokenUsage: tokens)
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다(고정 displayNow · 티커 미발사).
    store.isMenuPresented = true
    // ① 위 주석 — 활성화 빠른 길(요청 0건)로 끝나게 한다.
    store.hasActivatedStoredSession = true
    store.membershipConfirmed = true
    store.lastTeamStatusAt = Date()
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = Date(timeIntervalSince1970: 1_781_000_000)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.teamMembers = (0..<members).map { i in
        TeamMemberStatus(id: "aaaaaaaa-0000-0000-0000-\(String(format: "%012d", i))", name: "멤버\(i)",
                         status: .offWork, updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 3_600)
    }
    store.snapshot = WorkStatusSnapshot(status: working ? .working : .offWork, elapsedSeconds: 3_600, pendingSync: pendingSync)
    store.ultraBalance = balance
    store.missions = missions ?? [V0356Fixture.lap]
    store.missionsLoaded = loaded
    store.streakDays = streak
    store.weeklyWork = weekly
    store.missionNotice = notice
    // v0.3.58: 이 스위트는 **도전 미션 절이 없는** 미션 화면(v0.3.56 의 줄 예산 · 짧은 화면)을 잰다 — 서버에 도전 미션이 없는 창과
    // 같은 그림이다. 절이 붙은 화면(불러오는 중 · 9줄 · 받기)의 높이 · 빈 띠는 V0358AchievementTests 가 따로 잰다.
    store.achievementsUnavailable = true
    return store
}

enum V0356Fixture {
    static let lap = MissionProgress(kind: .todayThreeHours, progress: 0.5, claimedToday: false, cappedToday: false,
                                     detail: "다음 하나까지 1시간 30분")
    static let floor = MissionProgress(kind: .dailyFloor, progress: nil, claimedToday: true, cappedToday: false,
                                       detail: "잔량 0이면 1개로")
    static let streak = MissionProgress(kind: .arrivalStreak, progress: nil, claimedToday: true, cappedToday: false,
                                        detail: "5일 연속")
    /// 서버가 지금 보내는 그대로의 세 줄(코어 `MissionProgress.rows(from:)` 의 순서).
    static let serverRows = [lap, floor, streak]
    /// 23시간 12분 · 20 받음 → 지금 퀘스트 40시간.
    static var weekly23h: WeeklyWorkStatus {
        V0355WeeklyStub.status(worked: 23 * 3_600 + 12 * 60, claimed: [true, false, false])
    }
    /// 서버가 미션을 늘린 미래(같은 순수 타입이라 화면은 그대로 그린다) — 목록 상한을 재는 데 쓴다.
    static func future(_ index: Int) -> MissionProgress {
        MissionProgress(kind: .todayThreeHours, progress: Double(index % 3) / 3, claimedToday: false, cappedToday: false,
                        detail: "미래 미션 \(index)")
    }
    /// 지갑 응답(계약 모양 — 스네이크 키). 연속 일수를 바꿔 끼운다.
    static func walletJSON(streak: Int) -> String {
        #"{"status":"ok","balance":2,"balance_cap":3,"daily_floor":1,"day":"2026-10-16","floor_applied":false,"#
            + #""missions":[{"key":"work3h","kst_day":"2026-10-16","target_seconds":10800,"progress_seconds":900,"#
            + #""claimed":false,"granted_now":false,"capped":false,"laps_settled":0,"laps_granted":0,"worked_seconds":900}],"#
            + #""worked_seconds_closed":900,"worked_seconds_open":0,"streak_days":"# + "\(streak)"
            + #","streak_includes_today":true,"measured_at":1787098516}"#
    }
}

// MARK: - ① 레일

@MainActor
@Suite(.serialized) struct V0356MissionRailTests {
    /// 레일 body 를 값으로 열어 칸을 **위에서 아래 순서대로** 꺼낸다(라벨 · 강조 · 동작).
    static func railButtons(_ store: WorkTimerStore) throws -> [(label: String, isActive: Bool, action: (() -> Void)?)] {
        var found: [(name: String, value: Any)] = []
        var budget = 200_000
        v0356Collect(["CheckMenuRailButton", "PokeEntryIconButton"], in: CheckMenuSideRail(store: store).body,
                     into: &found, budget: &budget)
        return found.map { item in
            if item.name == "PokeEntryIconButton" { return ("콕 / 메시지", false, nil) }
            let label = v0356Child("label", of: item.value) as? String ?? "?"
            let active = v0356Child("isActive", of: item.value) as? Bool ?? false
            let action = v0356Child("action", of: item.value) as? () -> Void
            return (label, active, action)
        }
    }

    @Test("[상점] 바로 아래 [미션] — 칸 수 = 상수(8) · 그 칸의 동작이 스토어 문을 연다/닫는다 · 열리면 그 칸만 강조")
    func missionSitsRightBelowTheShopAndTogglesTheStore() throws {
        let store = V0355WeeklyStoreTests.store(host: V0355WeeklyStoreTests.host("v0356-rail"), label: "v0356-rail",
                                                clock: V0355Clock(V0355WeeklyStoreTests.t0))
        let buttons = try Self.railButtons(store)
        #expect(buttons.map(\.label) == ["미니게임", "콕 / 메시지", "상점", "미션", "팀 현황", "내 기록", "제보", "설정"])
        #expect(buttons.count == CheckMenuSideRail.itemCount, "레일 칸 수(\(buttons.count))와 높이 상수(itemCount)가 갈렸다")

        let mission = try #require(buttons.first { $0.label == "미션" })
        #expect(mission.isActive == false)
        let tap = try #require(mission.action, "[미션] 칸에 동작이 없다")
        tap()
        #expect(store.isMissionPanelVisible, "[미션] 칸을 눌러도 미션 화면이 안 열린다")
        // 열린 뒤 다시 읽은 레일 — 그 칸만 켜져 있다.
        let reopened = try Self.railButtons(store)
        #expect(reopened.filter(\.isActive).map(\.label) == ["미션"])
        // 다시 누르면 닫힌다(레일 칸은 토글로 읽힌다).
        let tapAgain = try #require(reopened.first { $0.label == "미션" }?.action)
        tapAgain()
        #expect(store.isMissionPanelVisible == false)
    }

    @Test("소스 계약 — [미션] 칸은 checklist · 토글 · isActive 가 미션 깃발 · [상점] 바로 뒤(주석 제외)")
    func railSourceContract() throws {
        let rail = try v0356Body(try v0356Code("CheckMenuView.swift"), header: "struct CheckMenuSideRail: View {")
        let shop = try #require(rail.range(of: "store.toggleShopPanel()"))
        let mission = try #require(rail.range(of: "store.toggleMissionPanel()", range: shop.upperBound..<rail.endIndex))
        let team = try #require(rail.range(of: "store.toggleLeaderboard()", range: mission.upperBound..<rail.endIndex))
        #expect(shop.upperBound <= mission.lowerBound && mission.upperBound <= team.lowerBound)
        #expect(rail.contains("icon: \"checklist\""))
        #expect(rail.contains("isActive: store.isMissionPanelVisible"))
    }
}

// MARK: - ② 스토어

@MainActor
@Suite(.serialized) struct V0356MissionStoreTests {
    static let peer = "00000000-0000-0000-0000-000000000003"

    /// 스텁 호스트에 붙은 스토어(여는 문들이 부르는 조회는 전부 이 호스트의 `[]` 로 떨어진다).
    static func store(_ label: String, function: String = #function) -> (WorkTimerStore, String) {
        let host = V0355WeeklyStoreTests.host("v0356-\(label)")
        GomokuStubProtocol.register(host: host) { _, _, _ in nil }
        let store = V0355WeeklyStoreTests.store(host: host, label: "v0356-\(label)",
                                                clock: V0355Clock(V0355WeeklyStoreTests.t0), function: function)
        return (store, host)
    }

    /// 하위 패널 깃발 전부(미션 포함). `CheckMenuView.subPanelFlagNames` 와 수가 같아야 한다 — 새 패널이 생기면 여기도 는다.
    static let allFlags: [(String, KeyPath<WorkTimerStore, Bool>)] = [
        ("리그", \.isLeaderboardVisible), ("토큰판", \.isTokenBoardVisible), ("콕찌르기", \.isPokePanelVisible),
        ("내 기록", \.isInsightsPanelVisible), ("울트라", \.isUltraPanelVisible), ("1:1 대화", \.isMessagePanelVisible),
        ("제보", \.isFeedbackPanelVisible), ("캐릭터", \.isCharacterPanelVisible), ("상점", \.isShopPanelVisible),
        ("미션", \.isMissionPanelVisible),
    ]

    /// 다른 하위 패널을 여는 문 전부(그 문이 세우는 깃발과 함께). 울트라는 두 길 — 홈 · **콕찌르기 배지**(되살림 함정).
    static let openers: [(String, @MainActor (WorkTimerStore) -> Void, KeyPath<WorkTimerStore, Bool>)] = [
        ("팀 현황", { $0.toggleLeaderboard() }, \.isLeaderboardVisible),
        ("토큰 순위판", { $0.toggleTokenBoard() }, \.isTokenBoardVisible),
        ("콕찌르기", { $0.togglePokePanel() }, \.isPokePanelVisible),
        ("내 기록", { $0.toggleInsightsPanel() }, \.isInsightsPanelVisible),
        ("울트라(홈)", { $0.openUltraPanel(from: .home) }, \.isUltraPanelVisible),
        ("울트라(콕찌르기 배지)", { $0.togglePokePanel(); $0.openUltraPanel(from: .poke) }, \.isUltraPanelVisible),
        ("제보", { $0.openFeedbackPanel() }, \.isFeedbackPanelVisible),
        ("1:1 대화", { $0.openMessagePanel(peer: V0356MissionStoreTests.peer) }, \.isMessagePanelVisible),
        ("캐릭터", { $0.toggleCharacterPanel() }, \.isCharacterPanelVisible),
        ("상점", { $0.toggleShopPanel() }, \.isShopPanelVisible),
    ]

    static func openFlags(_ store: WorkTimerStore) -> [String] {
        allFlags.filter { store[keyPath: $0.1] }.map(\.0)
    }

    @Test("깃발 목록이 게이트 목록과 같은 수다(새 패널이 이 표를 비켜 가지 못하게)")
    func flagTableMatchesTheGate() {
        #expect(Self.allFlags.count == CheckMenuView.subPanelFlagNames.count)
        #expect(CheckMenuView.subPanelFlagNames.contains("isMissionPanelVisible"))
    }

    @Test("배타 (가) — 미션을 연 채 다른 문을 열면 미션이 닫히고 그 패널 하나만 선다")
    func everyOtherDoorClosesTheMissionPanel() {
        for (index, opener) in Self.openers.enumerated() {
            let (store, _) = Self.store("a\(index)")
            store.toggleMissionPanel()
            #expect(store.isMissionPanelVisible, "\(opener.0): 준비 실패 — 미션이 안 열렸다")
            opener.1(store)
            #expect(store.isMissionPanelVisible == false, "\(opener.0) 을(를) 열었는데 미션 화면이 남았다")
            #expect(store[keyPath: opener.2], "\(opener.0) 이(가) 안 열렸다")
            #expect(Self.openFlags(store).count == 1, "\(opener.0): 동시에 선 패널 \(Self.openFlags(store))")
        }
    }

    @Test("배타 (나) — 다른 패널을 연 채 [미션]을 누르면 그 패널이 닫히고 미션 하나만 선다(콕찌르기 배지 울트라도)")
    func theMissionDoorClosesEveryOtherPanel() {
        for (index, opener) in Self.openers.enumerated() {
            let (store, _) = Self.store("b\(index)")
            opener.1(store)
            #expect(store[keyPath: opener.2], "\(opener.0): 준비 실패 — 안 열렸다")
            store.toggleMissionPanel()
            #expect(store.isMissionPanelVisible, "\(opener.0) 위에서 [미션]을 눌렀는데 미션이 안 열렸다")
            #expect(Self.openFlags(store) == ["미션"], "\(opener.0) → [미션]: 동시에 선 패널 \(Self.openFlags(store))")
        }
    }

    @Test("로그아웃은 미션 화면을 내린다 · 팝오버 닫힘은 울트라 화면과 같은 규약(그대로 둔다)")
    func signOutResetsAndPopoverCloseKeepsLikeUltra() {
        let (store, _) = Self.store("reset")
        store.toggleMissionPanel()
        store.missionNotice = "3시간 채웠어요 — 루비 +3"
        store.streakDays = 9
        store.missionsLoaded = true
        // 팝오버를 닫았다 열어도 하위 패널은 그대로다(어느 패널도 닫힘에서 리셋하지 않는다 — 울트라와 같다).
        store.isMenuPresented = true
        store.setMenuPresented(false)
        #expect(store.isMissionPanelVisible, "팝오버 닫힘이 미션 화면만 따로 리셋한다(다른 패널과 규약이 갈렸다)")
        // 대조군: 울트라 화면도 팝오버 닫힘에 그대로 남는다(같은 규약이라는 주장의 다른 반쪽).
        let (ultra, _) = Self.store("reset-ultra")
        ultra.openUltraPanel(from: .home)
        ultra.isMenuPresented = true
        ultra.setMenuPresented(false)
        #expect(ultra.isUltraPanelVisible, "대조군 실패 — 울트라 화면이 팝오버 닫힘에 리셋된다면 미션의 규약도 다시 정해야 한다")
        store.clearPersistedSession()
        #expect(store.isMissionPanelVisible == false, "로그아웃 뒤에도 미션 화면이 떠 있다 — 다음 사람이 앞 사람 화면을 연다")
        #expect(store.missionNotice == nil && store.missionsLoaded == false && store.streakDays == 0,
                "로그아웃이 미션 안내 · 응답 여부 · 연속 일수를 안 내렸다(헤더 칩이 남의 연속 일수를 말한다)")
    }

    @Test("안내줄은 미션 화면의 것 — 울트라를 닫아도 남고, 미션을 떠날 때 지운다 · 안 연 동안 온 안내는 기다린다")
    func noticeBelongsToTheMissionPanel() {
        let (store, _) = Self.store("notice")
        store.openUltraPanel(from: .home)
        store.missionNotice = "이번 주 20시간 채웠어요 — 루비 +20"
        store.closeUltraPanel()
        #expect(store.missionNotice == "이번 주 20시간 채웠어요 — 루비 +20", "울트라를 닫았더니 미션 안내가 지워졌다")
        // 미션 화면이 닫혀 있으면 닫기는 아무것도 안 한다(멱등 — 안 본 안내를 지우지 않는다).
        store.closeMissionPanel()
        #expect(store.missionNotice != nil, "미션 화면을 연 적도 없는데 안내가 지워졌다")
        store.toggleMissionPanel()
        #expect(store.missionNotice != nil, "여는 순간 안내가 지워졌다 — 기다리던 줄을 못 본다")
        store.closeMissionPanel()
        #expect(store.missionNotice == nil, "미션 화면을 떠났는데 안내가 남았다(다시 열면 방금 일처럼 읽힌다)")
    }

    @Test("여는 순간 지갑 sync 한 번 + 주간 조회 한 번 → 3시간 줄 · 주간 줄 · 연속 일수가 선다 · 닫을 때는 안 묻는다")
    func openingSyncsTheWalletAndTheWeek() async {
        let host = V0355WeeklyStoreTests.host("v0356-open")
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            switch rpc {
            case "ultra_wallet_sync": return .init(body: V0356Fixture.walletJSON(streak: 4))
            case "weekly_work_status": return .init(body: V0355WeeklyStub.json(worked: 23 * 3_600, claimed: [true, false, false]))
            default: return nil
            }
        }
        let store = V0355WeeklyStoreTests.store(host: host, label: "v0356-open", clock: V0355Clock(V0355WeeklyStoreTests.t0))
        #expect(GomokuStubProtocol.count(host: host, rpc: "ultra_wallet_sync") == 0)
        store.toggleMissionPanel()
        let arrived = await V0354CoreStub.waitUntil {
            GomokuStubProtocol.count(host: host, rpc: "ultra_wallet_sync") == 1
                && GomokuStubProtocol.count(host: host, rpc: "weekly_work_status") == 1
                && store.missionsLoaded && store.weeklyWork != nil
        }
        let wallet = GomokuStubProtocol.count(host: host, rpc: "ultra_wallet_sync")
        let week = GomokuStubProtocol.count(host: host, rpc: "weekly_work_status")
        #expect(arrived, "미션 화면을 열었는데 지갑 sync(\(wallet)) · 주간 조회(\(week))가 안 나갔다")
        #expect(store.streakDays == 4)
        #expect(store.missions.first?.kind == .todayThreeHours)
        // 닫기는 조회를 내지 않는다.
        store.toggleMissionPanel()
        await V0355WeeklyStoreTests.settle()
        #expect(GomokuStubProtocol.count(host: host, rpc: "ultra_wallet_sync") == 1, "미션을 닫는데 지갑을 또 물었다")
    }
}

// MARK: - ③ 화면 — 미션 화면 · 울트라 화면

@MainActor
@Suite(.serialized) struct V0356PanelRenderTests {
    static func mission(missions: [MissionProgress] = [V0356Fixture.lap], weekly: WeeklyWorkStatus? = nil,
                        notice: String? = nil, loaded: Bool = true, line: Int = #line) -> WorkTimerStore {
        let store = v0356RenderStore(loaded: loaded, missions: missions, weekly: weekly, notice: notice, line: line)
        store.isMissionPanelVisible = true
        return store
    }

    static func ultra(balance: Int? = 3, missions: [MissionProgress] = [], weekly: WeeklyWorkStatus? = nil,
                      notice: String? = nil, line: Int = #line) -> WorkTimerStore {
        let store = v0356RenderStore(missions: missions, weekly: weekly, notice: notice, balance: balance, line: line)
        store.isUltraPanelVisible = true
        return store
    }

    static func png(_ store: WorkTimerStore) throws -> Data {
        try v0356PNG(CheckMenuView(store: store))
    }

    @Test("미션 화면 — 3시간 줄 · 주간 줄 · 안내줄이 그려지고 '매일 첫 근무' · '연속 출근' 줄은 안 그려진다")
    func missionPanelDrawsWhatItShouldAndHidesTheRest() throws {
        let base = try Self.png(Self.mission())
        // 대조군: 같은 입력이면 바이트까지 같다(없으면 아래 부등식은 렌더 잡음과 구별되지 않는다).
        #expect(base == (try Self.png(Self.mission())))
        // ★ 서버가 지금 보내는 세 줄 그대로를 줘도 3시간 줄 하나짜리 화면과 **픽셀까지** 같다 = 두 줄이 안 그려졌다.
        #expect(try Self.png(Self.mission(missions: V0356Fixture.serverRows)) == base,
                "미션 화면에 '매일 첫 근무' 또는 '연속 출근' 줄이 그려졌다(사장님 지시: 화면에서 뺀다)")
        // 두 줄만 있으면(3시간 줄 없음) 빈 목록 문구다 — 숨긴 줄이 자리를 차지하지 않는다.
        let onlyHidden = try Self.png(Self.mission(missions: [V0356Fixture.floor, V0356Fixture.streak]))
        #expect(onlyHidden == (try Self.png(Self.mission(missions: []))), "숨긴 줄이 빈 목록 문구 대신 무언가를 그렸다")
        #expect(onlyHidden != base, "3시간 줄이 안 그려진다")
        // 주간 줄(게이지가 있을 때) · 안내줄은 실제로 그려진다.
        let weekly = try Self.png(Self.mission(weekly: V0356Fixture.weekly23h))
        #expect(weekly != base, "주간 줄이 미션 화면에 안 그려졌다")
        #expect(try Self.png(Self.mission(weekly: WeeklyWorkStatus(workedSeconds: 3_600))) == base,
                "표 없는 주간 응답으로 줄을 그렸다 — 모르는 것을 0 으로 그리는 거짓말")
        #expect(try Self.png(Self.mission(notice: "3시간 채웠어요 — 루비 +3")) != base, "안내줄이 미션 화면에 안 그려졌다")
    }

    // v0.3.64: 세 묶음(일일 → 주간 → 누적). 안내줄("3시간 채웠어요 — 루비 +3")은 그 줄을 낸 3시간 줄 **바로 아래**(일일 묶음 안)로 옮겼다 —
    // 주간 줄 아래에 두면 일일 6줄 밑으로 밀려 화면을 열 때 안 보인다(예전엔 "화면을 열면 처음부터 보인다"가 그 자리의 이유였다).
    @Test("미션 화면 — 줄 순서: 일일 머리 → 3시간 → 안내줄 → 주간 머리 → 이번 주(그림의 세로 위치 · 소스 순서)")
    func missionPanelOrder() throws {
        // 같은 크기의 두 그림에서 **한 줄만** 바꿔 그 줄의 자리를 잰다(주간 묶음을 더하면 창 높이가 바뀌어 견줄 수 없다).
        let weekly10h = V0355WeeklyStub.status(worked: 10 * 3_600, claimed: [false, false, false])
        let base = try v0356Bitmap(CheckMenuView(store: Self.mission(weekly: V0356Fixture.weekly23h, notice: "3시간 채웠어요 — 루비 +3")))
        let otherNotice = try v0356Bitmap(CheckMenuView(store: Self.mission(weekly: V0356Fixture.weekly23h, notice: "6시간 채웠어요 — 루비 +3")))
        let otherWeekly = try v0356Bitmap(CheckMenuView(store: Self.mission(weekly: weekly10h, notice: "3시간 채웠어요 — 루비 +3")))
        // 안내줄이 서는 높이(3시간 줄 아래) < 주간 줄이 서는 높이(= 주간 묶음은 안내줄 아래). 본문 열(x < 330)만 — 레일 배지는 뺀다.
        let noticeDiff = try #require(v0356DiffBox(base, otherNotice), "안내줄이 안 그려졌다")
        let weeklyDiff = try #require(v0356DiffBox(base, otherWeekly), "주간 묶음이 안 그려졌다")
        print("[v0356] 순서 — 안내줄 y \(noticeDiff.minY) · 주간 묶음 y \(weeklyDiff.minY)")
        #expect(weeklyDiff.minY > noticeDiff.minY + 12, "주간 묶음이 안내줄 아래가 아니다(안내 \(noticeDiff.minY) · 주간 \(weeklyDiff.minY))")
        // 소스로도 못 박는다 — 그림만으로는 "3시간 줄이 주간 줄 위"를 3시간 줄 내용 변화와 가를 수 없다.
        let panel = try v0356Body(try v0356Code("CheckMenuView.swift"), header: "private struct MissionPanel: View {")
        let dailyHead = try #require(panel.range(of: "MissionGroupHeader(title: DailyMissionCopy.sectionTitle"))
        let lap = try #require(panel.range(of: "ForEach(missions.prefix(1)) { MissionRowView(mission: $0) }", range: dailyHead.upperBound..<panel.endIndex))
        let daily = try #require(panel.range(of: "ForEach(daily) { AchievementRowView(mission: $0.row, group: .daily(game: $0.game)) }",
                                             range: lap.upperBound..<panel.endIndex))
        let weekHead = try #require(panel.range(of: "MissionGroupHeader(title: WeeklyMissionCopy.sectionTitle)", range: daily.upperBound..<panel.endIndex))
        let week = try #require(panel.range(of: "WeeklyWorkRowView(status: weeklyRow)", range: weekHead.upperBound..<panel.endIndex))
        let cumulative = try #require(panel.range(of: "AchievementSectionView(state: achievementSection)", range: week.upperBound..<panel.endIndex))
        #expect(lap.upperBound <= week.lowerBound && week.upperBound <= cumulative.lowerBound)
        // 거르는 자리가 뷰다(코어 rows(from:) 는 그대로 세 줄을 만든다 — 아래 단언이 그 사실을 함께 잰다).
        #expect(panel.contains("missions.filter { !Self.hiddenKinds.contains($0.kind) }"))
        #expect(MissionPanelHiddenKinds.value == [.dailyFloor, .arrivalStreak])
    }

    @Test("울트라 화면 — 미션 줄 · 주간 줄 · 안내줄을 하나도 안 그리고 잔량 카드만 그린다")
    func ultraPanelDrawsOnlyTheBalance() throws {
        let bare = try Self.png(Self.ultra())
        #expect(bare == (try Self.png(Self.ultra())), "대조군 실패 — 같은 입력에 다른 그림")
        // 미션 세 줄 + 주간 줄 + 안내줄을 다 줘도 픽셀까지 같다.
        let loaded = try Self.png(Self.ultra(missions: V0356Fixture.serverRows, weekly: V0356Fixture.weekly23h,
                                             notice: "이번 주 20시간 채웠어요 — 루비 +20"))
        #expect(loaded == bare, "울트라 화면에 미션 · 주간 · 안내 중 무언가가 그려졌다(사장님 지시: 보유 수량만)")
        // 잔량 카드는 산다 — 3개 · 0개 · 모름이 서로 다른 그림이다.
        let zero = try Self.png(Self.ultra(balance: 0))
        let unknown = try Self.png(Self.ultra(balance: nil))
        #expect(bare != zero && zero != unknown && bare != unknown, "잔량 카드가 안 그려지거나 잔량을 말하지 않는다")
        // 소스로도: 울트라 화면 선언에 미션 · 주간 · 안내의 흔적이 없다(주석 제외).
        let panel = try v0356Body(try v0356Code("CheckMenuView.swift"), header: "private struct UltraPanel: View {")
        for banned in ["MissionRowView", "WeeklyWorkRowView", "missions", "weeklyWork", "notice"] {
            #expect(!panel.contains(banned), "울트라 화면 선언에 \(banned) 이(가) 남아 있다")
        }
        #expect(panel.contains("heroCard"), "추출 범위가 너무 좁다 — 잔량 카드를 못 담았다")
    }

    @Test("울트라 화면 실패 → 잔량 카드의 [다시 시도] · 미션 화면 실패 → 제목 행의 [다시 시도] + 실패 문구")
    func retryLivesOnBothScreens() throws {
        let ultraOK = try Self.png(Self.ultra())
        let failedUltra = Self.ultra()
        failedUltra.ultraBalanceFailed = true
        #expect(try Self.png(failedUltra) != ultraOK, "울트라 화면이 실패를 말하지 않는다")

        let missionOK = try Self.png(Self.mission())
        let failedMission = Self.mission()
        failedMission.ultraBalanceFailed = true
        #expect(try Self.png(failedMission) != missionOK, "미션 화면이 실패(다시 시도)를 말하지 않는다")
        // 한 번도 못 받았는데 실패 → "미션을 불러오지 못했어요" · 불러오는 중과 다른 그림.
        let loading = try Self.png(Self.mission(missions: [], loaded: false))
        let neverLoadedFailed = Self.mission(missions: [], loaded: false)
        neverLoadedFailed.ultraBalanceFailed = true
        #expect(try Self.png(neverLoadedFailed) != loading)
        #expect(MissionPanelCopy.failedCaption == "미션을 불러오지 못했어요")
        #expect(MissionPanelCopy.loadingCaption == UltraPanelCopy.loadingCaption)
    }
}

/// `MissionPanel` 은 private 라 숨김 목록을 소스에서 읽어 값으로 되살린다(주석 제외) — 목록이 바뀌면 여기서 갈린다.
enum MissionPanelHiddenKinds {
    static var value: Set<MissionProgress.Kind> {
        guard let code = try? v0356Code("CheckMenuView.swift"),
              let range = code.range(of: "static let hiddenKinds: Set<MissionProgress.Kind> = [") else { return [] }
        let tail = code[range.upperBound...].prefix { $0 != "]" }
        return Set(tail.split(separator: ",").compactMap { token -> MissionProgress.Kind? in
            switch token.trimmingCharacters(in: .whitespaces) {
            case ".dailyFloor": return .dailyFloor
            case ".arrivalStreak": return .arrivalStreak
            case ".todayThreeHours": return .todayThreeHours
            default: return nil
            }
        })
    }
}

// MARK: - ④ 헤더 — 연속 근무 칩

@MainActor
@Suite(.serialized) struct V0356HeaderStreakTests {
    @Test("문구 — 0일도 말한다(사장님 예시) · 보이스오버는 느낌표 없이")
    func copy() {
        #expect(HeaderStreakCopy.text(0) == "연속 0일 근무!")
        #expect(HeaderStreakCopy.text(3) == "연속 3일 근무!")
        #expect(HeaderStreakCopy.text(-1) == "연속 0일 근무!", "음수(서버 버그)를 그대로 그렸다")
        #expect(HeaderStreakCopy.accessibilityLabel(3) == "연속 3일 근무")
        #expect(HeaderStreakCopy.accessibilityLabel(0) == "연속 0일 근무")
    }

    @Test("헤더에 칩이 그려진다(0일 · 3일) · 지갑이 답하기 전에는 연속 일수 값과 무관하게 안 그린다")
    func chipShowsAfterTheFirstAnswerOnly() throws {
        func png(loaded: Bool, streak: Int, line: Int = #line) throws -> Data {
            try v0356PNG(CheckMenuView(store: v0356RenderStore(members: 2, loaded: loaded, streak: streak, line: line)))
        }
        let hidden0 = try png(loaded: false, streak: 0)
        #expect(hidden0 == (try png(loaded: false, streak: 0)), "대조군 실패")
        // 답 전에는 값이 무엇이든 같은 그림(칩이 없다) — "연속 0일"을 만들어 내지 않는다.
        #expect(try png(loaded: false, streak: 7) == hidden0, "지갑이 답하기 전에 연속 일수를 그렸다")
        let zero = try png(loaded: true, streak: 0)
        let three = try png(loaded: true, streak: 3)
        #expect(zero != hidden0, "연속 0일이 헤더에 안 그려졌다(사장님 예시가 0일이다)")
        #expect(three != zero, "연속 3일이 0일과 같은 그림이다 — 숫자가 안 그려졌다")
    }

    @Test("소스 계약 — 칩은 응답 여부 · 연속 일수만 읽고(시계 없음) 문구 · 보이스오버를 코어에서 받는다 · 캡션 줄에 선다")
    func chipSourceContract() throws {
        let code = try v0356Code("CheckMenuView.swift")
        let chip = try v0356Body(code, header: "struct HeaderStreakChip: View {")
        #expect(chip.contains("if store.missionsLoaded"))
        #expect(chip.contains("HeaderStreakChipLabel(days: store.streakDays)"))
        for clock in ["displayNow", "menuClockNow", "todayDuration", "myLiveWeeklySeconds", "leagueClockNow"] {
            #expect(!chip.contains(clock), "칩이 시계(\(clock))를 읽는다 — 매초 무효화")
        }
        let label = try v0356Body(code, header: "struct HeaderStreakChipLabel: View {")
        #expect(label.contains("Text(HeaderStreakCopy.text(days))"))
        #expect(label.contains(".accessibilityLabel(HeaderStreakCopy.accessibilityLabel(days))"))
        #expect(label.contains(".font(.caption2.weight(.semibold))"))
        #expect(label.contains("Image(systemName: HeaderStreakCopy.icon)"))
        #expect(HeaderStreakCopy.icon == "flame.fill")
        let goal = try v0356Body(code, header: "private struct HeaderGoalSection: View {")
        #expect(goal.contains("HeaderStreakChip(store: store)"))
    }

    /// 폭 시험: 상태 "동기화 대기"(가장 긴 상태)와 함께, 칩이 있을 때와 없을 때 그림이 갈리는 곳은 **캡션 줄의 주간 글자와 퍼센트
    /// 사이뿐**이어야 한다(윗줄 · 주간 글자 · 퍼센트 · 연필 · 높이 불변). 평소 폭(≤ 99시간 · ≤ 99일)에서 칩은 **제 크기**다.
    /// 칩에 바탕 캡슐(가로 여백 12pt)이 붙은 뒤로(v0.3.56 검토 수리) 168시간 주 + 999일 같은 극단에서는 칩 글자가 줄어든다 —
    /// 그래도 0.8배 아래로는 안 줄고, 주간 글자 · 퍼센트 · 연필은 1px 도 안 밀린다(우선순위 사다리). 이 화면들은 팀원이 나 하나라
    /// 레일이 창 높이를 정한다 — 칩이 세로 몫에 맞춰 줄던 결함(`HeaderStreakChipLabel` 의 세로 고정 주석 — 실측 72 → 59pt)을
    /// 여기서 함께 잰다.
    @Test("폭(동기화 대기 + 평소 · 최악 캡션)에서 칩은 높이 0pt · 윗줄과 캡션 양끝을 1px 도 안 건드린다 · 평소엔 제 크기 · 극단에도 0.8배 이상",
          arguments: [(168, 168, 999, false), (168, 16, 999, false), (99, 60, 99, true), (34, 60, 3, true)])
    func widthTouchesNothingElse(caseValues: (worked: Int, goal: Int, days: Int, fullSize: Bool)) throws {
        func store(loaded: Bool, line: Int = #line) -> WorkTimerStore {
            let s = v0356RenderStore(members: 0, pendingSync: true, loaded: loaded, streak: caseValues.days,
                                     line: line * 10_000 + caseValues.goal * 10 + caseValues.days % 7)
            s.teamMembers = [TeamMemberStatus(id: "00000000-0000-0000-0000-000000000002", name: "나", status: .offWork,
                                              updatedAt: nil, currentSessionStartedAt: nil,
                                              weeklyDurationSeconds: caseValues.worked * 3_600 + (caseValues.worked == 99 ? 59 * 60 : 0))]
            s.teamGoalSeconds = caseValues.goal * 3_600
            return s
        }
        let without = try v0356Bitmap(CheckMenuView(store: store(loaded: false)))
        let with = try v0356Bitmap(CheckMenuView(store: store(loaded: true)))
        let tag = "\(caseValues.worked)h/\(caseValues.goal)h · \(caseValues.days)일"
        #expect(with.pixelsHigh == without.pixelsHigh, "\(tag): 칩이 헤더를 \(Double(with.pixelsHigh - without.pixelsHigh) / 2)pt 키웠다")
        let box = try #require(v0356DiffBox(without, with), "\(tag): 칩이 안 그려졌다")
        // 윗줄(마스코트 · 상태 · 타이머 · 알약)은 헤더 카드 위 12 + 안쪽 12 + 46 = 70pt 안이다 — 차이는 그 아래에서만.
        #expect(box.minY >= 70, "\(tag): 칩이 윗줄(상태 · 타이머 · 알약)을 건드렸다(차이 시작 \(box.minY)pt)")
        // 한 줄(캡션 — 연필 18pt) 높이 안이다. 칩 캡슐은 13 + 4 = 17pt.
        #expect(box.height <= 18, "\(tag): 차이가 \(box.height)pt 높이다 — 칩이 줄을 바꾸거나 다른 줄을 밀었다")
        // 캡션 양끝: 왼쪽 주간 글자(카드 안쪽 24pt 부터 ≥ 126pt)와 오른쪽 퍼센트 · 연필은 그대로다.
        #expect(box.minX > 24 + 100, "\(tag): 칩이 주간 글자를 밀거나 잘랐다(차이 시작 x \(box.minX)pt)")
        #expect(box.maxX < 12 + 316 - 12 - 18 - 4 - 20, "\(tag): 칩이 퍼센트 · 연필을 밀었다(차이 끝 x \(box.maxX)pt)")
        let natural = CGFloat(try v0356Bitmap(HeaderStreakChipLabel(days: caseValues.days)).pixelsWide) / 2
        if caseValues.fullSize {
            #expect(box.width >= natural - 2, "\(tag): 평소 폭인데 칩이 \(box.width)pt 로 줄었다(제 크기 \(natural)pt)")
        } else {
            // 극단에서도 0.8배(minimumScaleFactor) 아래로는 안 준다 — 그 아래면 글자가 말줄임으로 잘린 것이다.
            #expect(box.width >= natural * 0.8 - 2, "\(tag): 칩이 \(box.width)pt — 0.8배(\(natural * 0.8)pt)보다 줄었다(잘렸다)")
        }
        print("[v0356] 폭 \(tag) — 칩 차이 x \(box.minX)…\(box.maxX)pt(\(box.width)pt · 제 크기 \(natural)pt) · y \(box.minY)…\(box.maxY)pt")
    }

    @Test("칩 폭 실측(보고용) — 0 · 3 · 99 · 999일")
    func chipWidths() throws {
        for days in [0, 3, 99, 999] {
            let bitmap = try v0356Bitmap(HeaderStreakChipLabel(days: days))
            print("[v0356] 칩 \(days)일 = \(Double(bitmap.pixelsWide) / 2)pt × \(Double(bitmap.pixelsHigh) / 2)pt")
            // 캡슐 여백(12pt) 포함 예산. 평소 캡션("이번 주 99시간 59분 / 60시간" + "166%")과 함께 292pt 줄에 제 크기로 든다
            // (폭 시험의 99시간 · 99일 경우가 화면에서 잰다).
            #expect(Double(bitmap.pixelsWide) / 2 <= 100, "칩 \(days)일이 \(Double(bitmap.pixelsWide) / 2)pt — 캡션 줄 예산(≤ 100)을 넘는다")
        }
    }
}

// MARK: - ⑤ 높이 — 레일 바닥 · 푸터 · 상한

@MainActor
@Suite(.serialized) struct V0356HeightTests {
    static let railFloor = CheckMenuSideRail.contentHeight + 12 * 2

    static func height(_ view: CheckMenuView) throws -> CGFloat {
        CGFloat(try v0356Bitmap(view).pixelsHigh) / 2
    }

    @Test("레일 실측 = 상수(8칸 · Spacer 간격 포함 432pt) — 레일이 정하는 화면의 창 높이가 정확히 그 값")
    func railFloorIsMeasuredExactly() throws {
        #expect(CheckMenuSideRail.itemCount == 8)
        #expect(Self.railFloor == 432)
        // 빈 순위판(본문 ~330pt)은 레일이 높이를 정한다.
        let store = v0356RenderStore()
        store.isLeaderboardVisible = true
        let measured = try Self.height(CheckMenuView(store: store))
        print("[v0356] 레일 상수 \(Self.railFloor)pt · 빈 순위판 창 \(measured)pt")
        #expect(measured == Self.railFloor, "레일 실측 \(measured)pt ≠ 상수 \(Self.railFloor)pt — contentHeight 산식이 레일을 잘못 안다")
    }

    /// ★ 검토 지적(P1, v0.3.56 리뷰): 푸터만 바닥에 붙이면 남는 자리가 **카드와 푸터 사이**에 빈 띠로 남았다 — 울트라 99pt ·
    ///   미션(불러오는 중 · 1줄) 115pt · 1인 홈 60pt. 본문 카드가 그 자리를 받아 푸터 바로 위(간격 10pt)까지 닿아야 한다.
    @Test("레일이 높이를 정하는 화면(홈 0~1인 · 울트라 · 미션 · 빈 순위판 · 빈 토큰판)은 정확히 레일 높이 · 푸터가 바닥에 붙고 본문 카드가 푸터 바로 위까지 닿는다(빈 띠 없음)")
    func shortScreensPinTheFooter() throws {
        let home0 = v0356RenderStore(members: 0)
        let home1 = v0356RenderStore(members: 1)
        let ultra = v0356RenderStore()
        ultra.isUltraPanelVisible = true
        let mission = v0356RenderStore()
        mission.isMissionPanelVisible = true
        let missionLoading = v0356RenderStore(loaded: false, missions: [])
        missionLoading.isMissionPanelVisible = true
        let missionTwo = v0356RenderStore(weekly: V0356Fixture.weekly23h)
        missionTwo.isMissionPanelVisible = true
        let league = v0356RenderStore()
        league.isLeaderboardVisible = true
        let tokens = v0356RenderStore()
        tokens.isTokenBoardVisible = true
        // v0.3.64: "미션 2줄(3시간 + 주간)"은 묶음 머리 둘(일일 · 주간 — 28pt 씩)이 붙어 본문이 레일보다 길어졌다 — 그 화면은 아래
        // `contentScreens` 에서 "본문이 정한다 · 빈 띠 없음"만 잰다.
        let screens = [("홈 0인", home0), ("홈 1인", home1), ("울트라", ultra), ("미션 1줄", mission),
                       ("미션 불러오는 중", missionLoading),
                       ("빈 순위판", league), ("빈 토큰판", tokens)]
        for (label, store) in screens {
            let bitmap = try v0356Bitmap(CheckMenuView(store: store))
            let height = CGFloat(bitmap.pixelsHigh) / 2
            let ink = v0356BodyInkBottom(bitmap)
            let runs = v0356CardRuns(bitmap)
            let gap = runs.count >= 2 ? runs[runs.count - 1].top - runs[runs.count - 2].bottom : -1
            print("[v0356] \(label): 창 \(height)pt · 본문 잉크 바닥 \(ink)pt · 카드 \(runs.map { "\($0.top)…\($0.bottom)" }) · 푸터 위 틈 \(gap)pt")
            #expect(height == Self.railFloor, "\(label): 창 \(height)pt — 레일 바닥(\(Self.railFloor))보다 크다/작다")
            // 푸터(본문 열 마지막 카드)의 바닥 = 창 바닥 − 바깥 여백 12. 1pt 안쪽이면 붙은 것이다.
            #expect(abs(ink - (height - 12)) <= 1, "\(label): 푸터 바닥이 \(ink)pt — 창 바닥(\(height - 12))에서 떠 있다")
            // 카드가 셋 이상(헤더 · 본문 · 푸터)이어야 틈을 잰 것이다 — 아니면 자가 무언가를 못 본다.
            #expect(runs.count >= 3, "\(label): 카드 구간 \(runs.count)개 — 자가 카드를 못 가른다")
            // 본문 카드 ↔ 푸터 틈 = VStack 간격 10 + 둥근 모서리 몫. 12 를 넘으면 빈 띠가 다시 생긴 것이다.
            #expect(gap >= 9 && gap <= 12, "\(label): 본문 카드와 푸터 사이 \(gap)pt — 남는 자리가 빈 띠로 남았다(카드가 받아야 한다)")
        }
        for (label, store) in [("미션 2줄(3시간 + 주간)", missionTwo)] {
            let bitmap = try v0356Bitmap(CheckMenuView(store: store))
            let height = CGFloat(bitmap.pixelsHigh) / 2
            let runs = v0356CardRuns(bitmap)
            let gap = runs.count >= 2 ? runs[runs.count - 1].top - runs[runs.count - 2].bottom : -1
            print("[v0356] \(label): 창 \(height)pt(본문이 정한다) · 푸터 위 틈 \(gap)pt")
            #expect(height > Self.railFloor && abs(v0356BodyInkBottom(bitmap) - (height - 12)) <= 1, "\(label): 푸터가 바닥에 안 붙었다")
            #expect(gap >= 9 && gap <= 12, "\(label): 본문 카드와 푸터 사이 \(gap)pt — 빈 띠")
        }
        // 레일보다 긴 화면은 예전 그대로 본문이 정한다(팀원 수 비례 성장이 산다).
        let two = try Self.height(CheckMenuView(store: v0356RenderStore(members: 2)))
        let five = try Self.height(CheckMenuView(store: v0356RenderStore(members: 5)))
        #expect(two > Self.railFloor && two < five, "2인(\(two)) · 5인(\(five)) — 레일 위에서의 비례 성장이 죽었다")
    }

    @Test("최악 조합 ≤ 700pt — 미션 화면(미래 미션 6줄 + 주간 + 안내 + 업데이트 배너 + 목표 편집) · 울트라 화면(배너 + 편집)")
    func worstCombosStayUnderTheCap() throws {
        let many = [V0356Fixture.lap] + (1...5).map(V0356Fixture.future)
        for (banner, editing, notice) in [(false, false, false), (true, false, true), (true, true, true), (false, true, true)] {
            let store = v0356RenderStore(missions: many, weekly: V0356Fixture.weekly23h,
                                         notice: notice ? "이번 주 60시간 채웠어요 — 루비 +270" : nil)
            store.isMissionPanelVisible = true
            let h = try Self.height(CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: editing,
                                                  previewUpdateBanner: banner, previewUpdateNotes: banner ? ["a", "b", "c", "d"] : []))
            print("[v0356] 미션 최악(배너 \(banner) · 편집 \(editing) · 안내 \(notice)) = \(h)pt")
            #expect(h <= 700, "미션 화면 \(h)pt — 상한을 넘어 푸터가 잘린다")
        }
        let ultra = v0356RenderStore()
        ultra.isUltraPanelVisible = true
        let uh = try Self.height(CheckMenuView(store: ultra, previewGoalEditing: true, previewUpdateBanner: true,
                                               previewUpdateNotes: ["a", "b", "c", "d"]))
        print("[v0356] 울트라 최악 = \(uh)pt")
        #expect(uh <= 700)
    }

    // v0.3.64: 스크롤 창 상한은 그대로(5줄 = 312pt)이고, 묶음 머리(20 + 간격 8)가 **내용**에 더해진다 — 일일 머리는 언제나, 주간 머리는
    // 주간 줄이 있을 때만. 그래서 "주간 = 한 줄"이 아니라 "주간 묶음 = 머리 28 + 줄 64 = 92pt"다.
    @Test("미션 목록 상한 — 안내 · 배너가 없으면 상한(5줄 312pt)까지 펼치고, 넘치면 창이 안 자란다(묶음 머리 · 주간 묶음도 센다)")
    func missionListBudget() throws {
        func h(_ missions: Int, weekly: Bool, line: Int = #line) throws -> CGFloat {
            let store = v0356RenderStore(missions: [V0356Fixture.lap] + (0..<max(0, missions - 1)).map(V0356Fixture.future),
                                         weekly: weekly ? V0356Fixture.weekly23h : nil,
                                         line: line * 100 + missions * 2 + (weekly ? 1 : 0))
            store.isMissionPanelVisible = true
            return try Self.height(CheckMenuView(store: store, previewClipsOverflowList: true))
        }
        let unit = try h(4, weekly: false) - h(3, weekly: false)
        #expect(unit == MissionPanelUnit.value, "한 줄 값이 \(unit)pt")
        // 일일 머리 + 3줄(212) + 주간 묶음(92) = 304 ≤ 312 → 펼친다(+92) · 일일 머리 + 4줄(276) + 주간 묶음 = 368 → 상한이라 +36 에서 멈춘다.
        #expect(try h(3, weekly: true) == h(3, weekly: false) + 92, "주간 묶음(머리 + 줄)이 펼쳐지지 않았다")
        #expect(try h(4, weekly: true) == h(4, weekly: false) + 36, "상한을 넘었는데 창이 자랐다 — 주간 묶음을 셈에 안 넣었다")
        #expect(try h(5, weekly: true) == h(5, weekly: false), "상한을 넘었는데 창이 자랐다")
        #expect(try h(5, weekly: false) == h(6, weekly: false), "상한(5줄) 위에서 창이 자랐다")
    }
}

/// 미션 줄 하나의 값(56 + 간격 8).
enum MissionPanelUnit { static let value: CGFloat = 64 }

// MARK: - ⑦ 검토 수리(v0.3.56 리뷰) — 배선 · 배지 울트라에서 건너가기 · 재오픈 sync · 칩 테두리 · 배지 툴팁

@MainActor
@Suite(.serialized) struct V0356ReviewFixTests {
    /// 실제 `CheckMenuView` 가 패널에 넘긴 값 트리에서 이름이 정확히 `name` 인 노드(패널이 private 라 이름으로 잡는다).
    static func panelNode(_ name: String, in store: WorkTimerStore) throws -> Any {
        var found: [(name: String, value: Any)] = []
        var budget = 400_000
        v0356Collect([name], in: CheckMenuView(store: store).body, into: &found, budget: &budget)
        return try #require(found.first?.value, "\(name) 을(를) 팝오버 뷰 트리에서 못 찾았다 — 디스패치 갈래가 빠졌다")
    }

    /// 패널이 받은 인자 없는 클로저(옵셔널이어도 풀어서). **인자 없는** 것만 부른다 — 인자 있는 클로저를 미러로 꺼내 부르면
    /// 재추상화 썽크가 쓰레기를 넘긴다(UltraPokeTests `spentPanelKeepsSpentDisplay…` 주석).
    static func action(_ label: String, of node: Any) throws -> () -> Void {
        let value = try #require(v0356Child(label, of: node), "패널에 \(label) 이(가) 없다")
        return try #require(value as? () -> Void, "\(label) 이(가) 인자 없는 클로저가 아니거나 nil 이다")
    }

    /// 지갑 sync 에 답하는 스텁 호스트 위의 스토어(V0355 스토어 — 세션 · 팀 · 고정 시계).
    static func walletStore(_ label: String, function: String = #function) -> (WorkTimerStore, String) {
        let host = V0355WeeklyStoreTests.host("v0356-\(label)")
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            rpc == "ultra_wallet_sync" ? .init(body: V0356Fixture.walletJSON(streak: 2)) : nil
        }
        let store = V0355WeeklyStoreTests.store(host: host, label: "v0356-\(label)",
                                                clock: V0355Clock(V0355WeeklyStoreTests.t0), function: function)
        return (store, host)
    }

    static func walletCalls(_ host: String) -> Int { GomokuStubProtocol.count(host: host, rpc: "ultra_wallet_sync") }

    // ── P2 ① 미션 화면 [뒤로] · [다시 시도] 배선 ─────────────────────────────────────────────
    // 리뷰 실측: 호출부를 `onBack: { store.closeUltraPanel() }` · `onRetry: { }` 로 바꾼 뮤턴트가 276건 전부 초록이었다 —
    // [뒤로]가 죽은 미션 화면이 초록으로 나갈 수 있었다. 그래서 **실제 팝오버가 넘긴 클로저**를 꺼내 불러 본다.

    @Test("미션 화면 — 팝오버가 넘긴 [다시 시도]는 지갑을 한 번 더 묻고, [뒤로]는 미션을 닫아 홈으로 간다")
    func missionPanelBackAndRetryAreWired() async throws {
        let (store, host) = Self.walletStore("wire-mission")
        store.toggleMissionPanel()
        let opened = await V0354CoreStub.waitUntil { Self.walletCalls(host) == 1 && store.missionsLoaded }
        #expect(opened, "준비 실패 — 여는 sync 가 안 왔다")
        let panel = try Self.panelNode("MissionPanel", in: store)
        try Self.action("onRetry", of: panel)()
        let retried = await V0354CoreStub.waitUntil { Self.walletCalls(host) == 2 }
        #expect(retried, "미션 화면 [다시 시도]가 지갑을 다시 묻지 않는다(\(Self.walletCalls(host))회) — 실패한 사람이 다시 밀 길이 없다")
        try Self.action("onBack", of: panel)()
        #expect(store.isMissionPanelVisible == false, "미션 화면 [뒤로]가 미션을 닫지 않는다 — 레일을 다시 누를 때까지 갇힌다")
        #expect(V0356MissionStoreTests.openFlags(store).isEmpty, "[뒤로] 뒤에 다른 패널이 섰다: \(V0356MissionStoreTests.openFlags(store))")
    }

    @Test("울트라 화면 — 팝오버가 넘긴 [다시 시도]는 지갑을 한 번 더 묻고, [뒤로]는 울트라를 닫는다(홈 진입)")
    func ultraPanelBackAndRetryAreWired() async throws {
        let (store, host) = Self.walletStore("wire-ultra")
        store.openUltraPanel(from: .home)
        let opened = await V0354CoreStub.waitUntil { Self.walletCalls(host) == 1 }
        #expect(opened, "준비 실패 — 여는 sync 가 안 왔다")
        let panel = try Self.panelNode("UltraPanel", in: store)
        try Self.action("onRetry", of: panel)()
        let retried = await V0354CoreStub.waitUntil { Self.walletCalls(host) == 2 }
        #expect(retried, "울트라 화면 [다시 시도]가 지갑을 다시 묻지 않는다")
        try Self.action("onBack", of: panel)()
        #expect(store.isUltraPanelVisible == false, "울트라 화면 [뒤로]가 울트라를 닫지 않는다")
        #expect(V0356MissionStoreTests.openFlags(store).isEmpty)
    }

    // ── P2 ② 콕찌르기 배지로 들어온 울트라에서 다른 문 ─────────────────────────────────────────
    // 리뷰 실측(0.3.55 부터 있던 결함): 팀 현황 → [리그, 콕찌르기] · 토큰 → [토큰판, 콕찌르기] · 내 기록 / 캐릭터 / 상점 →
    // [콕찌르기, X] — 그 셋은 콕찌르기가 디스패치에서 이겨 **누른 화면이 안 보였다**. 울트라 화면이 잔량만 말하게 되면서
    // (캡션 "상점에서 루비로 사요") 다음 손이 [상점]이라 더 자주 밟힌다.

    @Test("콕찌르기 배지로 들어온 울트라에서 어느 문을 눌러도 그 화면 하나만 선다 · 울트라 [뒤로]는 여전히 콕찌르기로 돌아간다")
    func everyDoorFromTheBadgeUltraShowsOnlyThatScreen() {
        let mission: (String, @MainActor (WorkTimerStore) -> Void, KeyPath<WorkTimerStore, Bool>) =
            ("미션", { $0.toggleMissionPanel() }, \.isMissionPanelVisible)
        let doors = V0356MissionStoreTests.openers + [mission]
        for (index, door) in doors.enumerated() {
            let (store, _) = V0356MissionStoreTests.store("u\(index)")
            store.togglePokePanel()
            store.openUltraPanel(from: .poke)
            #expect(V0356MissionStoreTests.openFlags(store) == ["울트라"], "\(door.0): 준비 실패 — \(V0356MissionStoreTests.openFlags(store))")
            door.1(store)
            let expected = V0356MissionStoreTests.allFlags.first { $0.1 == door.2 }?.0 ?? "?"
            #expect(V0356MissionStoreTests.openFlags(store) == [expected],
                    "배지 울트라 → \(door.0): 동시에 선 패널 \(V0356MissionStoreTests.openFlags(store)) — 콕찌르기가 되살아났다")
        }
        // 대조군: [뒤로]의 규약은 그대로다 — 배지로 들어왔으면 콕찌르기로 돌아간다.
        let (back, _) = V0356MissionStoreTests.store("u-back")
        back.togglePokePanel()
        back.openUltraPanel(from: .poke)
        back.closeUltraPanel()
        #expect(V0356MissionStoreTests.openFlags(back) == ["콕찌르기"], "울트라 [뒤로]가 콕찌르기로 안 돌아간다(수리가 [뒤로]까지 바꿨다)")
    }

    // ── P2 ③ 팝오버를 다시 열면 지갑 화면이 다시 묻는다 ────────────────────────────────────────
    // 리뷰 실측: 미션 화면을 연 채 팝오버를 닫았다 열면 sync 가 1회 그대로 — 리그 · 토큰판 · 콕찌르기 · 미니게임은 다시 받는다.
    // 주기 sync 는 근무 중에만 돌아(`syncUltraWalletIfDue` 의 startedAt 게이트) 근무 밖 사람은 낡은 줄을 계속 봤다.

    @Test("미션 · 울트라 화면을 연 채 팝오버를 닫았다 열면 지갑을 한 번 더 묻는다(근무 밖이어도) · 지갑 화면이 아니면 안 묻는다")
    func reopeningThePopoverResyncsWalletScreens() async {
        let screens: [(String, @MainActor (WorkTimerStore) -> Void)] = [
            ("미션", { $0.toggleMissionPanel() }),
            ("울트라", { $0.openUltraPanel(from: .home) }),
        ]
        for (index, screen) in screens.enumerated() {
            let (store, host) = Self.walletStore("reopen-\(index)")
            #expect(store.startedAt == nil, "전제: 근무 밖(주기 sync 가 안 도는 사람)")
            store.isMenuPresented = true
            screen.1(store)
            let opened = await V0354CoreStub.waitUntil { Self.walletCalls(host) == 1 }
            #expect(opened, "\(screen.0): 준비 실패 — 여는 sync 가 안 왔다")
            store.setMenuPresented(false)
            store.setMenuPresented(true)
            let resynced = await V0354CoreStub.waitUntil { Self.walletCalls(host) == 2 }
            #expect(resynced, "\(screen.0) 화면을 연 채 팝오버를 다시 열었는데 지갑을 안 물었다(\(Self.walletCalls(host))회) — 낡은 줄을 그린다")
        }
        // 대조군: 홈(지갑 화면이 아님)에서 다시 열면 지갑을 묻지 않는다 — 팝오버를 열 때마다 왕복을 늘리지 않는다.
        let (home, host) = Self.walletStore("reopen-home")
        home.isMenuPresented = true
        home.setMenuPresented(false)
        home.setMenuPresented(true)
        await V0355WeeklyStoreTests.settle()
        #expect(Self.walletCalls(host) == 0, "홈 화면 재오픈이 지갑을 물었다(\(Self.walletCalls(host))회)")
    }

    // ── P2 ⑤ 연속 근무 칩은 주간 문장과 갈라 보이는 **칩**이다 ──────────────────────────────────
    // 리뷰 실측: 칩이 "60시간"에서 5pt(낱말 간격 하나) 뒤에 테두리 없이 서서 "…/ 60시간 🔥 연속 3일 근무!" 한 문장으로 읽혔다.

    @Test("칩에는 바탕(캡슐)이 있다 — 가운데 줄이 낱말 사이까지 채워진다(맨 글자는 낱말 사이가 비어 있다)")
    func streakChipHasAContainer() throws {
        let bitmap = try v0356Bitmap(HeaderStreakChipLabel(days: 3))
        let data = try #require(bitmap.bitmapData)
        let spp = bitmap.samplesPerPixel
        #expect(bitmap.hasAlpha && spp == 4, "자가 알파를 못 읽는다(spp \(spp))")
        let y = bitmap.pixelsHigh / 2
        let row = data + y * bitmap.bytesPerRow
        // 둥근 끝(캡슐 반지름)은 빼고 잰다 — 가운데 줄은 반지름 안쪽부터 끝까지 바탕이 깔려야 한다.
        let inset = bitmap.pixelsHigh / 2
        let span = inset..<(bitmap.pixelsWide - inset)
        let filled = span.filter { row[$0 * spp + 3] > 8 }.count
        let ratio = Double(filled) / Double(span.count)
        print("[v0356] 칩 가운데 줄 채움 \(filled)/\(span.count) = \(ratio) · 칩 \(Double(bitmap.pixelsWide) / 2)×\(Double(bitmap.pixelsHigh) / 2)pt")
        #expect(ratio >= 0.98, "칩 가운데 줄이 \(Int(ratio * 100))% 만 채워졌다 — 바탕이 없어 주간 문장에 붙어 읽힌다")
        // 높이는 캡션 줄(연필 18pt) 안이다 — 칩이 헤더를 키우지 않는다(폭 시험의 '높이 0pt' 가 화면 쪽 대조).
        #expect(Double(bitmap.pixelsHigh) / 2 <= 18, "칩 높이 \(Double(bitmap.pixelsHigh) / 2)pt — 캡션 줄(18pt)을 넘는다")
    }

    // ── P2 ⑥ 콕찌르기 제목의 잔량 배지 툴팁 ────────────────────────────────────────────────
    // 울트라 화면이 잔량만 그리게 되면서 "눌러서 충전 방법 보기"는 거짓이 됐다(잔량 > 0 이면 캡션은 "3초 꾹 누르면 한 개 써요").

    @Test("잔량 배지 툴팁 — 숫자를 말하고 '충전 방법'을 약속하지 않는다(무제한 · 모름과 같은 '눌러서 보기')")
    func badgeTooltipNoLongerPromisesChargeSteps() {
        #expect(UltraBalanceText.badgeHelp(balance: 3) == "울트라 3개 — 눌러서 보기")
        #expect(UltraBalanceText.badgeHelp(balance: 0) == "울트라 0개 — 눌러서 보기")
        for balance in [nil, 0, 1, 3] as [Int?] {
            for unlimited in [false, true] {
                let text = UltraBalanceText.badgeHelp(balance: balance, unlimited: unlimited)
                #expect(!text.contains("충전"), "\"\(text)\" 가 울트라 화면에 없는 충전 방법을 약속한다")
                #expect(text.hasSuffix("눌러서 보기"), "\"\(text)\" — 세 갈래가 같은 동사로 끝나야 한다")
            }
        }
    }
}

// MARK: - ⑥ 미리보기(환경변수가 있을 때만 — 창은 띄우지 않는다)

@MainActor
@Suite(.serialized) struct V0356StillsTests {
    @Test("미리보기 PNG(CHECK_V0356_STILLS_DIR) — 홈 칩 · 미션 화면 · 울트라 화면 · 헤더 최악 폭, 어둡게/밝게")
    func stills() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_V0356_STILLS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func save(_ name: String, _ store: WorkTimerStore, scheme: ColorScheme) throws {
            let view = CheckMenuView(store: store, previewClipsOverflowList: true).environment(\.colorScheme, scheme)
            try v0356PNG(view).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
        for scheme in [ColorScheme.dark, .light] {
            // (1) 홈 — 근무중 · 연속 3일 · 레일에 [미션].
            let home = v0356RenderStore(members: 3, streak: 3, line: 900 + (scheme == .dark ? 0 : 1))
            home.teamMembers = [TeamMemberStatus(id: "00000000-0000-0000-0000-000000000002", name: "나", status: .working,
                                                 updatedAt: nil, currentSessionStartedAt: home.displayNow.addingTimeInterval(-32_040),
                                                 weeklyDurationSeconds: 34 * 3_600)] + home.teamMembers
            home.teamGoalSeconds = 60 * 3_600
            home.startedAt = home.displayNow.addingTimeInterval(-32_040)   // 큰 타이머 08:54(사장님 스크린샷과 같은 자리)
            try save("1-home-streak3", home, scheme: scheme)
            // (2) 미션 화면 — 3시간 줄 + 23h/40h 주간 줄 + 안내.
            let mission = v0356RenderStore(missions: V0356Fixture.serverRows, weekly: V0356Fixture.weekly23h,
                                           notice: "이번 주 20시간 채웠어요 — 루비 +20", line: 910 + (scheme == .dark ? 0 : 1))
            mission.isMissionPanelVisible = true
            mission.startedAt = mission.displayNow.addingTimeInterval(-32_040)
            try save("2-mission-panel", mission, scheme: scheme)
            // (3) 울트라 화면 — 보유 수량만.
            let ultra = v0356RenderStore(missions: V0356Fixture.serverRows, weekly: V0356Fixture.weekly23h,
                                         notice: "이번 주 20시간 채웠어요 — 루비 +20", line: 920 + (scheme == .dark ? 0 : 1))
            ultra.isUltraPanelVisible = true
            try save("3-ultra-balance-only", ultra, scheme: scheme)
            // (4) 헤더 최악 폭 — 동기화 대기 · 999일 · 168h/168h.
            let worst = v0356RenderStore(members: 0, pendingSync: true, streak: 999, line: 930 + (scheme == .dark ? 0 : 1))
            worst.teamMembers = [TeamMemberStatus(id: "00000000-0000-0000-0000-000000000002", name: "나", status: .offWork,
                                                  updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 168 * 3_600)]
            worst.teamGoalSeconds = 168 * 3_600
            try save("4-header-worst-999", worst, scheme: scheme)
        }
    }
}
