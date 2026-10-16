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
//  ⑤ 높이 — 레일 바닥(432pt)이 창의 최소 높이이고 그때 푸터가 바닥에 붙는다 · 최악 조합 ≤ 700pt.
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

    @Test("미션 화면 — 줄 순서: 3시간 → 이번 주 → 안내줄(그림의 세로 위치 · 소스 순서)")
    func missionPanelOrder() throws {
        let both = try v0356Bitmap(CheckMenuView(store: Self.mission(weekly: V0356Fixture.weekly23h)))
        let lapOnly = try v0356Bitmap(CheckMenuView(store: Self.mission()))
        let withNotice = try v0356Bitmap(CheckMenuView(store: Self.mission(weekly: V0356Fixture.weekly23h,
                                                                          notice: "이번 주 20시간 채웠어요 — 루비 +20")))
        // 주간 줄을 더하면 갈리는 곳이 시작되는 높이 > 3시간 줄 자리(= 3시간 줄은 그대로 위에 있다).
        let weeklyDiff = try #require(v0356DiffBox(lapOnly, both))
        let noticeDiff = try #require(v0356DiffBox(both, withNotice))
        #expect(noticeDiff.minY > weeklyDiff.minY + 40, "안내줄이 주간 줄 아래가 아니다(주간 \(weeklyDiff.minY) · 안내 \(noticeDiff.minY))")
        // 소스로도 못 박는다 — 그림만으로는 "3시간 줄이 주간 줄 위"를 3시간 줄 내용 변화와 가를 수 없다.
        let panel = try v0356Body(try v0356Code("CheckMenuView.swift"), header: "private struct MissionPanel: View {")
        let lap = try #require(panel.range(of: "ForEach(missions.prefix(1)) { MissionRowView(mission: $0) }"))
        let week = try #require(panel.range(of: "if let weeklyRow { WeeklyWorkRowView(status: weeklyRow) }", range: lap.upperBound..<panel.endIndex))
        #expect(lap.upperBound <= week.lowerBound)
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
    /// 사이뿐**이어야 한다(윗줄 · 주간 글자 · 퍼센트 · 연필 · 높이 불변). 그리고 칩은 **제 크기**다 — 최악(999일 · 168시간 캡션)에서도
    /// 290.5 ≤ 292pt 라 줄 이유가 없다. 이 화면들은 팀원이 나 하나라 레일이 창 높이를 정한다 — 칩이 세로 몫에 맞춰 줄던 결함
    /// (`HeaderStreakChipLabel` 의 세로 고정 주석 — 실측 72 → 59pt)을 여기서 함께 잰다.
    @Test("폭(동기화 대기 + 평소 · 최악 캡션)에서 칩은 높이 0pt · 윗줄과 캡션 양끝을 1px 도 안 건드린다 · 칩은 제 크기",
          arguments: [(168, 168, 999, true), (168, 16, 999, true), (99, 60, 99, true), (34, 60, 3, true)])
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
        // 한 줄(캡션) 높이 안이다.
        #expect(box.height <= 14, "\(tag): 차이가 \(box.height)pt 높이다 — 칩이 줄을 바꾸거나 다른 줄을 밀었다")
        // 캡션 양끝: 왼쪽 주간 글자(카드 안쪽 24pt 부터 ≥ 126pt)와 오른쪽 퍼센트 · 연필은 그대로다.
        #expect(box.minX > 24 + 100, "\(tag): 칩이 주간 글자를 밀거나 잘랐다(차이 시작 x \(box.minX)pt)")
        #expect(box.maxX < 12 + 316 - 12 - 18 - 4 - 20, "\(tag): 칩이 퍼센트 · 연필을 밀었다(차이 끝 x \(box.maxX)pt)")
        let natural = CGFloat(try v0356Bitmap(HeaderStreakChipLabel(days: caseValues.days)).pixelsWide) / 2
        if caseValues.fullSize {
            #expect(box.width >= natural - 2, "\(tag): 평소 폭인데 칩이 \(box.width)pt 로 줄었다(제 크기 \(natural)pt)")
        }
        print("[v0356] 폭 \(tag) — 칩 차이 x \(box.minX)…\(box.maxX)pt(\(box.width)pt · 제 크기 \(natural)pt) · y \(box.minY)…\(box.maxY)pt")
    }

    @Test("칩 폭 실측(보고용) — 0 · 3 · 99 · 999일")
    func chipWidths() throws {
        for days in [0, 3, 99, 999] {
            let bitmap = try v0356Bitmap(HeaderStreakChipLabel(days: days))
            print("[v0356] 칩 \(days)일 = \(Double(bitmap.pixelsWide) / 2)pt × \(Double(bitmap.pixelsHigh) / 2)pt")
            #expect(Double(bitmap.pixelsWide) / 2 <= 90, "칩 \(days)일이 \(Double(bitmap.pixelsWide) / 2)pt — 캡션 줄 예산(≤ 90)을 넘는다")
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

    @Test("레일이 높이를 정하는 화면(홈 0~1인 · 울트라 · 미션 1줄)은 정확히 레일 높이 · 푸터가 바닥에 붙는다(푸터 아래가 비지 않는다)")
    func shortScreensPinTheFooter() throws {
        let home0 = v0356RenderStore(members: 0)
        let home1 = v0356RenderStore(members: 1)
        let ultra = v0356RenderStore()
        ultra.isUltraPanelVisible = true
        let mission = v0356RenderStore()
        mission.isMissionPanelVisible = true
        for (label, store) in [("홈 0인", home0), ("홈 1인", home1), ("울트라", ultra), ("미션 1줄", mission)] {
            let bitmap = try v0356Bitmap(CheckMenuView(store: store))
            let height = CGFloat(bitmap.pixelsHigh) / 2
            let ink = v0356BodyInkBottom(bitmap)
            print("[v0356] \(label): 창 \(height)pt · 본문 잉크 바닥 \(ink)pt")
            #expect(height == Self.railFloor, "\(label): 창 \(height)pt — 레일 바닥(\(Self.railFloor))보다 크다/작다")
            // 푸터(본문 열 마지막 카드)의 바닥 = 창 바닥 − 바깥 여백 12. 1pt 안쪽이면 붙은 것이다.
            #expect(abs(ink - (height - 12)) <= 1, "\(label): 푸터 바닥이 \(ink)pt — 창 바닥(\(height - 12))에서 떠 있다")
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

    @Test("미션 목록 상한 — 안내 · 배너가 없으면 5줄까지 펼치고, 넘치면 창이 안 자란다(주간 줄도 한 줄로 센다)")
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
        // 4줄 + 주간 = 5줄 → 펼친다(+1줄) · 5줄 + 주간 = 6줄 → 상한(5)이라 창이 안 자란다.
        #expect(try h(4, weekly: true) == h(4, weekly: false) + unit, "넷째 줄 다음의 주간 줄이 펼쳐지지 않았다")
        #expect(try h(5, weekly: true) == h(5, weekly: false), "상한을 넘었는데 창이 자랐다 — 주간 줄을 줄 수에 안 셌다")
    }
}

/// 미션 줄 하나의 값(56 + 간격 8).
enum MissionPanelUnit { static let value: CGFloat = 64 }

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
