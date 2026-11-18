import AppKit
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 미션 [모두 받기](제보 11-17 — 서울 "미션 루비 모두 수령 기능 좀 추가해주세요" · 대표 "모두 받기는 고치기", 다음 맥 판).
//
// 여기서 잰다:
//  A 규칙 — 받을 것 0 · 1 이면 버튼 없음, 2 이상이면 "N개 모두 받기" · 수는 그 버튼이 실제로 받는 수(누적은 캐릭터 보상 제외 ·
//    계열로 접기 전) · 낱말 하나('모두 받기') · 맥락이 묶음마다 맞는 받기를 부른다 · 떠 있으면 흐려진다.
//  B 스토어 길 — 미션 화면의 맥락으로 누르면 그 묶음만 키 없이 한 번(`{"p_key":null}`) · 다른 묶음 받기는 0건 · 말풍선은 합계로 한 번 ·
//    연출은 줄(계열)마다 하나 · 떠 있는 동안 두 번째는 0건 · 줄 [받기]도 흐려진다 · 실패는 받을 줄 전부 · 자정을 넘기면 받기 0건.
//  C 그림 — 머리 20pt · 292pt 안(일일 머리 안내와 같이) · 버튼은 제목 · 안내 글자를 안 밀고 머리 밖으로 안 나간다 · 하나뿐이면 버튼 없음 ·
//    팝오버 창 높이 그대로(≤ 700pt) · PNG 는 `FEATURE_SHOTS_DIR` 에.
//  D 소스 계약(주석 제외) — 배선 · 새 네트워크 없음 · 주간 머리엔 없다.
// 실네트워크 없음(호스트별 스텁) · 창 없음(ImageRenderer 만) · 이름 · 숫자는 전부 지어낸 것이다.

// MARK: - 픽스처

enum MCAFixture {
    /// 누적: 폰 로그인 50 · 팀 3 200 · 콕 10 5 · 콕 50 20 받을 것 = **4개**(콕은 한 줄에 접힌다 — 보이는 [받기]는 셋).
    static var cumulativeSeveral: [V0358Fixture.Row] {
        let poke10 = V0358Fixture.with("poke10", claimed: false)
        return V0358Fixture.with(poke10, "poke50", achieved: true)
    }

    /// 누적: 폰 로그인 하나만 받을 것.
    static var cumulativeSingle: [V0358Fixture.Row] { V0358Fixture.with("team3", progress: 2, achieved: false) }

    /// 일일: 타이밍 바 · 오목 · 체스 받을 것 = **3개**(플래피는 받음).
    static var dailySeveral: [V0364Fixture.Daily] { V0364Fixture.with("daily_chess", achieved: true) }

    /// 일일: 타이밍 바 하나만 받을 것.
    static var dailySingle: [V0364Fixture.Daily] { V0364Fixture.with("daily_gomoku", achieved: false) }

    /// 개발 아잉이 캐릭터 보상 줄(받을 수 있음 · 받음).
    static var characterClaimable: [String: Any] { characterObject(claimed: false) }
    static var characterClaimed: [String: Any] { characterObject(claimed: true) }

    static func characterObject(claimed: Bool) -> [String: Any] {
        let row = V0381MissionFixture.characterRow(progress: 100, achieved: true, claimed: claimed, claimable: !claimed)
        return (try! JSONSerialization.jsonObject(with: Data(row.utf8))) as! [String: Any]
    }

    /// `achievements_status()` · 받기 응답(누적 표 + 선택 일일 + 선택 캐릭터 줄 + `claimed_now`).
    static func json(_ rows: [V0358Fixture.Row] = cumulativeSeveral,
                     daily: [V0364Fixture.Daily]? = nil,
                     resetAt: Int = V0364Fixture.t + 4 * 3_600_000,
                     character: [String: Any]? = nil,
                     claimedNow: [(key: String, title: String, reward: Int)] = [],
                     ruby: Int? = 1234) -> String {
        let base = daily.map {
            V0364Fixture.json(daily: V0364Fixture.dailyObject($0, resetAt: resetAt), achievements: rows, claimedNow: claimedNow, ruby: ruby)
        }
            ?? V0358Fixture.json(rows, claimedNow: claimedNow, ruby: ruby)
        var root = (try! JSONSerialization.jsonObject(with: Data(base.utf8))) as! [String: Any]
        if let character { root["character_missions"] = [character] }
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// 디코드한 상태. 리셋은 먼 미래(2100-01-01) — 렌더 스토어는 응답을 직접 꽂아 시계 차가 0 이라 어느 날 돌려도 날이 안 넘어가게
    /// (`V0364Fixture.resetFar` 와 같은 이유).
    static func status(_ rows: [V0358Fixture.Row] = cumulativeSeveral, daily: [V0364Fixture.Daily]? = nil,
                       character: [String: Any]? = nil) -> AchievementStatus {
        try! V0358Fixture.decode(json(rows, daily: daily, resetAt: V0364Fixture.resetFar, character: character))
    }

    /// 누적 키 없는 받기의 응답 — 받을 루비 미션 전부를 받은 뒤의 표 + `claimed_now`(그 전부). 캐릭터 줄은 **그대로**(이 요청이 안 준다).
    static func claimAllCumulativeJSON(_ rows: [V0358Fixture.Row], character: [String: Any]? = nil, ruby: Int = 1509) -> String {
        let claimable = rows.filter { $0.achieved && !$0.claimed }
        let after = claimable.reduce(rows) { V0358Fixture.with($0, $1.key, claimed: true) }
        return json(after, character: character, claimedNow: claimable.map { ($0.key, $0.title, $0.reward) }, ruby: ruby)
    }

    /// 일일 키 없는 받기의 응답 — 오늘 받을 일일 전부를 받은 뒤의 표 + `claimed_now`(일일 전부). 누적은 그대로.
    static func claimAllDailyJSON(_ daily: [V0364Fixture.Daily], rows: [V0358Fixture.Row] = cumulativeSeveral, ruby: Int = 1249) -> String {
        let claimable = daily.filter { $0.achieved && !$0.claimed }
        let after = claimable.reduce(daily) { V0364Fixture.with($0, $1.key, claimed: true) }
        return json(rows, daily: after, claimedNow: claimable.map { ($0.key, $0.title, $0.reward) }, ruby: ruby)
    }
}

// MARK: - 공용 도우미

private enum MCAError: Error { case renderFailed }

@MainActor
private func mcaBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw MCAError.renderFailed }
    return bitmap
}

private func mcaCount(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
                      _ match: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData else { return 0 }
    let spp = bitmap.samplesPerPixel
    var count = 0
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(bitmap.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    for py in y0...y1 {
        let row = data + py * bitmap.bytesPerRow
        for px in x0...x1 {
            let o = px * spp
            if match(Int(row[o]), Int(row[o + 1]), Int(row[o + 2])) { count += 1 }
        }
    }
    return count
}

/// 받기 버튼 그라데이션 가운데 섞인 색(V0358 · V0364 와 같은 자 — 초록:파랑 비 0.8~1.15 인 밝은 픽셀).
private func mcaGradientPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    mcaCount(bitmap, x: x, y: y) { r, g, b in
        guard r > 60, r < 120, g > 150, b > 0 else { return false }
        let ratio = Double(g) / Double(b)
        return ratio >= 0.8 && ratio <= 1.15
    }
}

/// 두 그림이 갈리는 픽셀의 경계(pt, 채널 차 > 8). 같으면 nil. 크기가 다르면 전체.
private func mcaDiffBox(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, maxX limitX: CGFloat = .infinity) -> CGRect? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
          let pa = a.bitmapData, let pb = b.bitmapData else {
        return CGRect(x: 0, y: 0, width: CGFloat(max(a.pixelsWide, b.pixelsWide)) / 2, height: CGFloat(max(a.pixelsHigh, b.pixelsHigh)) / 2)
    }
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    let spp = a.samplesPerPixel
    for y in 0..<a.pixelsHigh {
        let ra = pa + y * a.bytesPerRow, rb = pb + y * b.bytesPerRow
        for x in 0..<min(a.pixelsWide, limitX.isFinite ? Int(limitX * 2) : a.pixelsWide) {
            let o = x * spp
            var delta = 0
            for c in 0..<min(4, spp) { delta = max(delta, abs(Int(ra[o + c]) - Int(rb[o + c]))) }
            if delta > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2, width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
}

private func mcaChild(_ label: String, of value: Any) -> Any? {
    Mirror(reflecting: value).children.first { $0.label == label }?.value
}

/// PNG 를 `FEATURE_SHOTS_DIR`(있으면)에 굽는다. 없으면 이 실행의 임시 폴더.
private func mcaSave(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["FEATURE_SHOTS_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-claim-all", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}

/// 렌더용 메인 화면 스토어(V0364 `v0364RenderStore` 와 같은 두 겹 — 답하지 않는 스텁). 네트워크가 이 맥 밖으로 안 나간다.
@MainActor
private func mcaRenderStore(achievements: AchievementStatus?,
                            missions: [MissionProgress] = [V0356Fixture.lap],
                            weekly: WeeklyWorkStatus? = nil,
                            function: String = #function, line: Int = #line) -> WorkTimerStore {
    let tag = "mca-render-L\(line)"
    let home = CheckTestScratch.directory("token-\(tag)", function: function)
    let tokens = TokenUsageStore(
        defaults: CheckTestScratch.defaults("token-\(tag)", function: function),
        homeDirectory: home.appendingPathComponent("home", isDirectory: true),
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
    )
    let host = "mca-silent-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { _, _, _ in .init(body: "[]", delay: 600) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service,
                               environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: CheckTestScratch.defaults(tag, function: function),
                               tokenUsage: tokens)
    store.isMenuPresented = true
    store.hasActivatedStoredSession = true
    store.membershipConfirmed = true
    store.lastTeamStatusAt = Date()
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = Date(timeIntervalSince1970: 1_781_000_000)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600, pendingSync: false)
    store.ultraBalance = 3
    store.rubyBalance = 1234
    store.missions = missions
    store.missionsLoaded = true
    store.streakDays = 9
    store.weeklyWork = weekly
    store.achievements = achievements
    store.isMissionPanelVisible = true
    return store
}

/// 스텁 호스트에 붙은 스토어(V0355 스토어 — 세션 · 팀 · 고정 시계). rpc 마다 응답을 고른다(호출 순번 0부터).
@MainActor
private func mcaStore(_ label: String,
                      clock: V0355Clock = V0355Clock(V0355WeeklyStoreTests.t0),
                      status: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(body: MCAFixture.json()) },
                      achievementClaim: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(status: 500, body: "{}") },
                      dailyClaim: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(status: 500, body: "{}") },
                      function: String = #function) -> (WorkTimerStore, String) {
    let host = V0355WeeklyStoreTests.host("mca-\(label)")
    GomokuStubProtocol.register(host: host) { rpc, _, index in
        switch rpc {
        case "achievements_status": return status(index)
        case "achievement_claim": return achievementClaim(index)
        case "daily_mission_claim": return dailyClaim(index)
        default: return nil
        }
    }
    let store = V0355WeeklyStoreTests.store(host: host, label: "mca-\(label)", clock: clock, function: function)
    store.isMenuPresented = true
    store.isMissionPanelVisible = true
    return (store, host)
}

/// 미션 화면이 실제로 받은 받기 맥락(팝오버 뷰 트리에서 꺼낸다 — 앱이 쓰는 배선 그대로).
@MainActor
private func mcaPanelContext(_ store: WorkTimerStore) throws -> MissionClaimContext {
    let panel = try V0356ReviewFixTests.panelNode("MissionPanel", in: store)
    return try #require(mcaChild("claim", of: panel) as? MissionClaimContext, "미션 화면에 받기 맥락이 안 넘어갔다")
}

private func mcaCalls(_ host: String, _ rpc: String) -> [GomokuStubProtocol.Call] { GomokuStubProtocol.calls(host: host, rpc: rpc) }

// MARK: - A 규칙

@MainActor
@Suite struct MissionClaimAllRuleTests {
    @Test("버튼은 받을 것이 둘 이상일 때만 — 0 · 1 은 없음, 2 · 3 · 12 는 'N개 모두 받기' · 낱말 하나 · 상수에서 센다")
    func mcaVisibilityRule() {
        #expect(MissionClaimAllOffer.minimumCount == 2)
        for count in [-1, 0, 1] {
            #expect(MissionClaimAllOffer.make(group: .daily, count: count) == nil, "받을 것 \(count)개인데 [모두 받기]가 섰다")
            #expect(MissionClaimAllOffer.make(group: .achievement, count: count) == nil)
        }
        for count in [2, 3, 12] {
            #expect(MissionClaimAllOffer.make(group: .daily, count: count) == MissionClaimAllOffer(group: .daily, count: count))
            #expect(MissionClaimAllOffer.make(group: .achievement, count: count)?.count == count)
        }
        // 낱말은 '모두 받기' 하나(제보 "모두 수령" — 폰은 '전부 받기'). 수는 버튼 글자 앞에 선다.
        #expect(MissionClaimAllText.action == "모두 받기")
        #expect(MissionClaimAllText.button(3) == "3개 모두 받기" && MissionClaimAllText.button(12) == "12개 모두 받기")
        #expect(MissionClaimAllText.accessibility(3) == "받을 보상 3개 모두 받기")
        #expect(MissionClaimAllText.button(MissionClaimAllOffer.minimumCount).hasPrefix("\(MissionClaimAllOffer.minimumCount)개"))
    }

    @Test("일일 — 그리는 일일 줄의 받을 것에서 센다(머리 '받을 보상 N개'와 같은 수) · 하루가 끝난 줄은 안 센다 · 일일이 없으면 없음")
    func mcaDailyCount() throws {
        let several = try #require(MCAFixture.status(daily: MCAFixture.dailySeveral).daily)
        let rows = several.rows(serverNowMs: V0364Fixture.t)
        #expect(MissionClaimAllOffer.daily(rows) == MissionClaimAllOffer(group: .daily, count: 3))
        #expect(MissionClaimAllOffer.daily(rows)?.count == several.claimable(serverNowMs: V0364Fixture.t).count,
                "버튼 수가 키 없는 일일 받기가 받는 줄 수와 다르다")
        let single = try #require(MCAFixture.status(daily: MCAFixture.dailySingle).daily)
        #expect(MissionClaimAllOffer.daily(single.rows(serverNowMs: V0364Fixture.t)) == nil, "하나뿐인데 [모두 받기]가 섰다")
        #expect(MissionClaimAllOffer.daily(nil) == nil && MissionClaimAllOffer.daily([]) == nil)
        // 하루가 끝난 응답의 줄(새 날의 모양)은 [받기]가 없다 — 버튼도 없다.
        let afterReset = several.rows(serverNowMs: (several.resetAtMs ?? 0) + 1)
        #expect(MissionClaimAllOffer.daily(afterReset) == nil, "자정을 넘긴 어제 줄로 [모두 받기]가 섰다")
    }

    @Test("누적 — 수는 키 없는 받기가 실제로 받는 수: 계열로 접기 전(콕 10 · 50 = 2) · 캐릭터 보상 제외 · 머리 '받을 보상'은 캐릭터까지 센다")
    func mcaCumulativeCountExcludesCharacter() {
        func state(_ status: AchievementStatus) -> AchievementSectionState {
            AchievementSectionState.make(status: status, unavailable: false, failed: false)
        }
        // 콕 10 · 50 을 둘 다 채웠다 — 줄은 하나(콕 10 의 [받기])지만 키 없는 받기는 둘 다 받는다.
        let several = MCAFixture.status()
        #expect(several.seriesRows.filter(\.isClaimable).count == 3 && several.claimable.count == 4, "전제: 보이는 [받기] 3 · 받을 것 4")
        #expect(state(several).claimAllCount == 4 && MissionClaimAllOffer.achievement(state(several))?.count == 4)
        // 캐릭터 보상 하나가 더 받을 수 있어도 버튼 수는 그대로다(그 줄은 제 [받기]로 받는다).
        let withCharacter = MCAFixture.status(character: MCAFixture.characterClaimable)
        #expect(withCharacter.claimableCount == 5 && withCharacter.characterClaimable.count == 1)
        #expect(state(withCharacter).claimAllCount == 4, "캐릭터 보상을 [모두 받기] 수에 셌다 — 그 요청은 캐릭터를 안 준다")
        // 루비 하나 + 캐릭터 하나 = 받을 것 2 지만 키 없는 받기가 받는 것은 1 — 버튼 없음(그 줄의 [받기]와 같은 일이다).
        let rubyPlusCharacter = MCAFixture.status(MCAFixture.cumulativeSingle, character: MCAFixture.characterClaimable)
        #expect(rubyPlusCharacter.claimableCount == 2)
        #expect(state(rubyPlusCharacter).claimAllCount == 1 && MissionClaimAllOffer.achievement(state(rubyPlusCharacter)) == nil,
                "루비 하나 · 캐릭터 하나인데 [모두 받기]가 섰다")
        // 어떤 표든 버튼 수 == 스토어가 키 없는 받기로 받는 집합(`claimable` — 루비 미션만, 접기 전)의 크기.
        let matrix: [AchievementStatus] = [
            V0358Fixture.status(), V0358Fixture.status(V0358Fixture.fresh), several, withCharacter, rubyPlusCharacter,
            MCAFixture.status(character: MCAFixture.characterClaimed),
            MCAFixture.status(V0358Fixture.base.map { var r = $0; r.achieved = true; r.claimed = false; r.progress = r.target; return r }),
        ]
        for status in matrix {
            #expect(state(status).claimAllCount == status.claimable.count,
                    "버튼 수 \(state(status).claimAllCount) ≠ 받는 집합 \(status.claimable.map(\.key))")
        }
        // 절이 줄을 모르면 0.
        #expect(AchievementSectionState.hidden.claimAllCount == 0 && AchievementSectionState.loading.claimAllCount == 0
                && AchievementSectionState.failed.claimAllCount == 0)
    }

    @Test("맥락 — 묶음마다 맞는 키 없는 받기를 부른다(다른 묶음은 0건) · 그 묶음에 떠 있는 받기가 있으면 흐려진다 · 모두 받기가 떠 있으면 줄도")
    func mcaContextRoutesByGroup() {
        var achievementAll = 0, dailyAll = 0, singles: [String] = []
        let context = MissionClaimContext(claimAchievement: { singles.append($0) }, claimDaily: { singles.append($0) },
                                          claimAllAchievements: { achievementAll += 1 }, claimAllDaily: { dailyAll += 1 })
        context.claimAll(.daily)
        #expect(dailyAll == 1 && achievementAll == 0 && singles.isEmpty, "일일 [모두 받기]가 누적 · 낱개를 불렀다")
        context.claimAll(.achievement)
        #expect(dailyAll == 1 && achievementAll == 1 && singles.isEmpty, "누적 [모두 받기]가 일일 · 낱개를 불렀다")
        // 떠 있음 — 비어 있으면 안 흐려진다 · 낱개 하나라도 떠 있으면 그 묶음만 흐려진다.
        #expect(!MissionClaimContext().isClaimAllBusy(.daily) && !MissionClaimContext().isClaimAllBusy(.achievement))
        let single = MissionClaimContext(inFlightKeys: ["team3"])
        #expect(single.isClaimAllBusy(.achievement) && !single.isClaimAllBusy(.daily))
        let dailySingle = MissionClaimContext(dailyInFlightKeys: ["daily_gomoku"])
        #expect(dailySingle.isClaimAllBusy(.daily) && !dailySingle.isClaimAllBusy(.achievement))
        // 모두 받기가 떠 있으면 그 묶음의 줄 [받기]도 흐려진다(기존 자리 `*`) — 다른 묶음 줄은 그대로.
        let slot = WorkTimerStore.achievementClaimAllSlot
        let allAchievements = MissionClaimContext(inFlightKeys: [slot])
        #expect(allAchievements.isClaimAllBusy(.achievement))
        #expect(allAchievements.isInFlight("phone_login", group: .achievement) && allAchievements.isInFlight("work100", group: .achievement))
        #expect(!allAchievements.isInFlight("daily_gomoku", group: .daily(game: "gomoku")))
        let allDaily = MissionClaimContext(dailyInFlightKeys: [slot])
        #expect(allDaily.isClaimAllBusy(.daily) && allDaily.isInFlight("daily_gomoku", group: .daily(game: "gomoku")))
        #expect(!allDaily.isInFlight("phone_login", group: .achievement) && !allDaily.isClaimAllBusy(.achievement))
    }
}

// MARK: - B 스토어 길(미션 화면의 맥락으로 누른다)

@MainActor
@Suite(.serialized) struct MissionClaimAllStoreTests {
    @Test("누적 — 화면 맥락으로 누르면 achievement_claim {p_key:null} 한 번 · 일일 받기 0건 · 말풍선은 합계로 한 번 · 연출은 계열마다 하나 · 캐릭터 줄은 그대로")
    func mcaCumulativeClaimsAllOnce() async throws {
        let rows = MCAFixture.cumulativeSeveral
        let character = MCAFixture.characterClaimable
        let statusBody = MCAFixture.json(rows, daily: V0364Fixture.base, character: character)
        let claimBody = MCAFixture.claimAllCumulativeJSON(rows, character: character)
        let (store, host) = mcaStore("cumulative-ok",
                                     status: { _ in .init(body: statusBody) },
                                     achievementClaim: { _ in .init(body: claimBody) })
        var bubbles: [Int] = []
        store.onRewardTrigger = { if case .rubyReward(let amount) = $0 { bubbles.append(amount) } }
        await store.refreshAchievements(reason: .missionPanel)?.value
        let before = AchievementSectionState.make(status: store.achievements, unavailable: false, failed: false)
        #expect(MissionClaimAllOffer.achievement(before)?.count == 4, "전제: 누적 [4개 모두 받기]")
        let context = try mcaPanelContext(store)
        context.claimAll(.achievement)
        #expect(store.achievementClaimsInFlight == [WorkTimerStore.achievementClaimAllSlot], "누른 순간 모두 받기 자리가 안 섰다")
        #expect(await V0354CoreStub.waitUntil { store.achievementClaimsInFlight.isEmpty && mcaCalls(host, "achievement_claim").count == 1 })
        #expect(mcaCalls(host, "achievement_claim").map(\.body) == [#"{"p_key":null}"#], "키 없는 받기가 아니다")
        #expect(mcaCalls(host, "daily_mission_claim").isEmpty && mcaCalls(host, "achievement_character_claim").isEmpty,
                "누적 [모두 받기]가 다른 받기를 불렀다")
        // 말풍선은 합계로 한 번(50 + 200 + 5 + 20) — 받은 줄 수만큼 겹치지 않는다.
        #expect(bubbles == [275], "말풍선이 \(bubbles) — 합계 한 번이 아니다")
        // 연출은 줄(계열)마다 하나 — 콕 10 · 50 은 한 줄이라 하나(+25).
        let bursts = store.missionClaimBursts
        #expect(bursts.count == 3 && bursts.keys.allSatisfy { $0.hasPrefix("achievement:") }, "연출 자리 \(bursts.keys.sorted())")
        #expect(bursts[MissionClaimBurst.achievementTarget(series: "poke")]?.amount == 25)
        #expect(bursts[MissionClaimBurst.achievementTarget(series: "team")]?.amount == 200)
        #expect(bursts[MissionClaimBurst.achievementTarget(series: "phone_login")]?.amount == 50)
        #expect(store.rubyBalance == 1509 && store.achievementClaimFailedKeys.isEmpty)
        // 받은 뒤 버튼은 내려가고 캐릭터 줄의 [받기]는 남는다 — 머리는 "받을 보상 1개".
        let after = AchievementSectionState.make(status: store.achievements, unavailable: false, failed: false)
        #expect(MissionClaimAllOffer.achievement(after) == nil, "다 받았는데 [모두 받기]가 남았다")
        #expect(store.achievements?.characterClaimable.map(\.key) == ["work100"], "캐릭터 보상까지 받은 것처럼 그렸다")
        if case .loaded(_, let pending) = after { #expect(pending == 1) } else { Issue.record("절이 사라졌다") }
    }

    @Test("일일 — 화면 맥락으로 누르면 daily_mission_claim {p_key:null} 한 번 · 누적 받기 0건 · 말풍선 합계 한 번 · 연출은 받은 일일 줄마다")
    func mcaDailyClaimsAllOnce() async throws {
        let daily = MCAFixture.dailySeveral
        let (store, host) = mcaStore("daily-ok",
                                     status: { _ in .init(body: MCAFixture.json(daily: daily)) },
                                     dailyClaim: { _ in .init(body: MCAFixture.claimAllDailyJSON(daily)) })
        var bubbles: [Int] = []
        store.onRewardTrigger = { if case .rubyReward(let amount) = $0 { bubbles.append(amount) } }
        await store.refreshAchievements(reason: .missionPanel)?.value
        #expect(MissionClaimAllOffer.daily(store.dailyMissionRows)?.count == 3, "전제: 일일 [3개 모두 받기]")
        let context = try mcaPanelContext(store)
        let panel = try V0356ReviewFixTests.panelNode("MissionPanel", in: store)
        let shown = try #require(mcaChild("dailyMissions", of: panel) as? [DailyMissionStatus.Mission], "미션 화면에 일일 줄이 안 넘어갔다")
        #expect(MissionClaimAllOffer.daily(shown)?.count == 3, "미션 화면이 받은 일일 줄로 센 수가 스토어와 다르다")
        context.claimAll(.daily)
        #expect(store.dailyMissionClaimsInFlight == [WorkTimerStore.achievementClaimAllSlot])
        #expect(await V0354CoreStub.waitUntil { store.dailyMissionClaimsInFlight.isEmpty && mcaCalls(host, "daily_mission_claim").count == 1 })
        #expect(mcaCalls(host, "daily_mission_claim").map(\.body) == [#"{"p_key":null}"#])
        #expect(mcaCalls(host, "achievement_claim").isEmpty, "일일 [모두 받기]가 누적 받기를 불렀다")
        #expect(bubbles == [15], "말풍선이 \(bubbles) — 합계 한 번(5 × 3)이 아니다")
        let bursts = store.missionClaimBursts
        #expect(Set(bursts.keys) == Set(["daily_timing_bar", "daily_gomoku", "daily_chess"].map(MissionClaimBurst.dailyTarget(key:))))
        #expect(bursts.values.allSatisfy { $0.amount == 5 })
        #expect(MissionClaimAllOffer.daily(store.dailyMissionRows) == nil && store.rubyBalance == 1249)
        // 누적 쪽 버튼은 그대로다(다른 묶음을 건드리지 않았다).
        #expect(MissionClaimAllOffer.achievement(.make(status: store.achievements, unavailable: false, failed: false))?.count == 4)
    }

    @Test("떠 있음 — 모두 받기가 떠 있으면 두 번째 누름 · 그 묶음 낱개는 0건 · 화면 맥락이 버튼 · 줄을 흐린다 · 다른 묶음은 그대로 · 끝나면 풀린다")
    func mcaInFlightLock() async throws {
        let rows = MCAFixture.cumulativeSeveral, daily = MCAFixture.dailySeveral
        let (store, host) = mcaStore("inflight",
                                     status: { _ in .init(body: MCAFixture.json(rows, daily: daily)) },
                                     achievementClaim: { _ in .init(body: MCAFixture.claimAllCumulativeJSON(rows), delay: 0.3) },
                                     dailyClaim: { _ in .init(body: MCAFixture.claimAllDailyJSON(daily), delay: 0.3) })
        await store.refreshAchievements(reason: .missionPanel)?.value
        try mcaPanelContext(store).claimAll(.achievement)
        var busy = try mcaPanelContext(store)
        #expect(busy.isClaimAllBusy(.achievement), "누적 모두 받기가 떠 있는데 버튼이 안 흐려졌다")
        for key in ["phone_login", "team3", "poke10"] {
            #expect(busy.isInFlight(key, group: .achievement), "모두 받기가 떠 있는데 \(key) 줄 [받기]가 안 흐려졌다")
        }
        #expect(!busy.isClaimAllBusy(.daily) && !busy.isInFlight("daily_gomoku", group: .daily(game: "gomoku")), "다른 묶음까지 흐렸다")
        busy.claimAll(.achievement)
        #expect(store.claimAchievement(key: nil) == nil && store.claimAchievement(key: "team3") == nil, "떠 있는 모두 받기 옆으로 또 보냈다")
        // 일일은 따로 — 같은 순간 눌러도 나간다 · 그 뒤 일일 쪽만 잠긴다.
        busy.claimAll(.daily)
        busy = try mcaPanelContext(store)
        #expect(busy.isClaimAllBusy(.daily) && busy.isInFlight("daily_gomoku", group: .daily(game: "gomoku")))
        #expect(store.claimDailyMission(key: nil) == nil && store.claimDailyMission(key: "daily_chess") == nil)
        #expect(await V0354CoreStub.waitUntil { store.achievementClaimsInFlight.isEmpty && store.dailyMissionClaimsInFlight.isEmpty })
        #expect(mcaCalls(host, "achievement_claim").count == 1 && mcaCalls(host, "daily_mission_claim").count == 1, "두 번 누름이 요청 둘이 됐다")
        let idle = try mcaPanelContext(store)
        #expect(!idle.isClaimAllBusy(.achievement) && !idle.isClaimAllBusy(.daily), "끝났는데 버튼이 흐린 채다")
        // 낱개가 떠 있는 동안에도 그 묶음 [모두 받기]는 흐려진다(같은 줄을 두 요청이 함께 잡지 않게).
        store.achievementClaimsInFlight = ["team3"]
        #expect(try mcaPanelContext(store).isClaimAllBusy(.achievement))
        store.achievementClaimsInFlight = []
    }

    @Test("실패 — 받을 수 있던 줄 전부(캐릭터 줄 제외)에 실패 표시 · 버튼은 그대로(다시 누르는 것이 재시도) · 연출 · 말풍선 없음 · 다시 받으면 내려간다")
    func mcaFailureKeepsTheButton() async throws {
        let rows = MCAFixture.cumulativeSeveral
        let character = MCAFixture.characterClaimable
        let statusBody = MCAFixture.json(rows, character: character)
        let claimBody = MCAFixture.claimAllCumulativeJSON(rows, character: character)
        let (store, host) = mcaStore("fail",
                                     status: { _ in .init(body: statusBody) },
                                     achievementClaim: { index in
                                         index == 0 ? .init(status: 500, body: #"{"message":"boom"}"#) : .init(body: claimBody)
                                     })
        var bubbles: [Int] = []
        store.onRewardTrigger = { if case .rubyReward(let amount) = $0 { bubbles.append(amount) } }
        await store.refreshAchievements(reason: .missionPanel)?.value
        try mcaPanelContext(store).claimAll(.achievement)
        #expect(await V0354CoreStub.waitUntil { store.achievementClaimsInFlight.isEmpty && mcaCalls(host, "achievement_claim").count == 1 })
        #expect(store.achievementClaimFailedKeys == ["phone_login", "team3", "poke10", "poke50"], "실패 표시 \(store.achievementClaimFailedKeys.sorted())")
        #expect(!store.achievementClaimFailedKeys.contains("work100"), "캐릭터 줄에 실패를 적었다 — 그 요청은 캐릭터를 안 받는다")
        #expect(bubbles.isEmpty && store.missionClaimBursts.isEmpty && store.missionNotice == nil)
        #expect(MissionClaimAllOffer.achievement(.make(status: store.achievements, unavailable: false, failed: false))?.count == 4,
                "실패했는데 버튼이 사라졌다 — 다시 누를 자리가 없다")
        try mcaPanelContext(store).claimAll(.achievement)
        #expect(await V0354CoreStub.waitUntil { store.achievementClaimsInFlight.isEmpty && mcaCalls(host, "achievement_claim").count == 2 })
        #expect(store.achievementClaimFailedKeys.isEmpty && bubbles == [275])
    }

    @Test("자정 — 서버 시각으로 리셋을 넘기면 일일 버튼이 내려가고 · 남은 버튼을 눌러도 받기 0건(넘김을 적고 조회 한 번 — 반응 없는 버튼 금지)")
    func mcaDailyRollover() async throws {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        let daily = MCAFixture.dailySeveral
        let (store, host) = mcaStore("rollover", clock: clock, status: { _ in
            .init(body: V0364Fixture.json(daily: V0364Fixture.dailyObject(daily, resetAt: V0364Fixture.t + 60_000),
                                          achievements: MCAFixture.cumulativeSeveral))
        }, dailyClaim: { _ in .init(body: MCAFixture.claimAllDailyJSON(daily)) })
        await store.refreshAchievements(reason: .missionPanel)?.value
        let context = try mcaPanelContext(store)
        #expect(MissionClaimAllOffer.daily(store.dailyMissionRows)?.count == 3, "리셋 전인데 일일 버튼이 없다")
        clock.advance(60)
        #expect(MissionClaimAllOffer.daily(store.dailyMissionRows) == nil, "날을 넘겼는데 어제 [모두 받기]가 남았다")
        let fetches = mcaCalls(host, "achievements_status").count
        context.claimAll(.daily)     // 화면에 남아 있던 버튼을 누른 순간
        #expect(await V0354CoreStub.waitUntil { mcaCalls(host, "achievements_status").count == fetches + 1 }, "막힌 뒤 새 날을 묻지 않았다")
        await V0355WeeklyStoreTests.settle()
        #expect(mcaCalls(host, "daily_mission_claim").isEmpty, "어제 줄의 모두 받기가 나갔다")
        #expect(store.dailyMissionRolloverNoted == V0364Fixture.t + 60_000, "넘김을 적지 않았다 — 버튼이 그 자리에 남는다")
        // 누적 쪽은 날짜와 무관하다.
        #expect(MissionClaimAllOffer.achievement(.make(status: store.achievements, unavailable: false, failed: false))?.count == 4)
    }
}

// MARK: - C 그림

@MainActor
@Suite(.serialized) struct MissionClaimAllRenderTests {
    static func height(_ view: CheckMenuView) throws -> CGFloat { CGFloat(try mcaBitmap(view).pixelsHigh) / 2 }

    static func header(_ claimAll: MissionClaimAllOffer?, pending: Int, note: String? = DailyMissionCopy.resetNote,
                       context: MissionClaimContext = MissionClaimContext()) throws -> NSBitmapImageRep {
        try mcaBitmap(MissionGroupHeader(title: DailyMissionCopy.sectionTitle, note: note, pendingCount: pending, claimAll: claimAll)
            .frame(width: 292)
            .background(Color.black)
            .environment(\.missionClaim, context)
            .environment(\.colorScheme, .dark))
    }

    @Test("머리 — 버튼이 서도 한 줄 20pt · 292pt 안(일일 안내 + 가장 긴 '12개 모두 받기') · 제목 · 안내 글자는 그대로 · 버튼은 머리 밖으로 안 나간다")
    func mcaHeaderFitsWidthAndHeight() throws {
        let caption = NSFont.preferredFont(forTextStyle: .caption1)
        let bold = NSFontManager.shared.convert(caption, toHaveTrait: .boldFontMask)
        let caption2 = NSFont.preferredFont(forTextStyle: .caption2)
        func width(_ text: String, _ font: NSFont) -> CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
        let widest = MissionClaimAllOffer(group: .daily, count: 12)
        let button = try mcaBitmap(MissionClaimAllButton(offer: widest, action: {}))
        let buttonWidth = CGFloat(button.pixelsWide) / 2
        #expect(CGFloat(button.pixelsHigh) / 2 == MissionClaimAllButton.height && MissionClaimAllButton.height <= MissionGroupLayout.headerHeight)
        let noteEnd = width(DailyMissionCopy.sectionTitle, bold) + 6 + width(DailyMissionCopy.resetNote, caption2)
        let total = noteEnd + 4 + buttonWidth
        print("[mca] 일일 머리 폭 — 제목+안내 \(noteEnd) + 버튼 \(buttonWidth) = \(total)pt / 292pt")
        #expect(total <= 292, "일일 머리가 한 줄에 안 들어간다(\(total)pt)")
        for count in [2, 6, 12] {
            let offer = MissionClaimAllOffer(group: .daily, count: count)
            let with = try Self.header(offer, pending: count)
            let without = try Self.header(nil, pending: 0)
            #expect(with.pixelsHigh == 40, "버튼이 선 머리가 20pt 가 아니다: \(CGFloat(with.pixelsHigh) / 2)pt")
            mcaSave(with, name: "claim-all-header-daily-\(count).png")
            let box = try #require(mcaDiffBox(with, without), "버튼이 머리에 안 그려졌다")
            print("[mca] 머리(\(count)개) 버튼 자리 \(box)")
            // 버튼이 있든 없든 제목 · 안내 글자는 같은 자리 · 같은 크기다(안내가 줄어들거나 밀리지 않았다).
            #expect(box.minX >= noteEnd, "버튼이 제목 · 안내 글자를 건드렸다(갈림 x \(box.minX) < 안내 끝 \(noteEnd))")
            #expect(box.minY >= 2 && box.maxY <= MissionGroupLayout.headerHeight, "버튼이 머리 20pt 밖으로 나갔다: \(box)")
            #expect(box.maxX <= 292)
            #expect(mcaGradientPixels(with, x: box.minX...box.maxX, y: 0...20) > 150, "머리 버튼이 [받기]와 같은 그라데이션이 아니다")
        }
        // 흐린 버튼(떠 있음)은 다른 그림이다 — 같은 자리 · 같은 크기.
        let offer = MissionClaimAllOffer(group: .daily, count: 3)
        let idle = try Self.header(offer, pending: 3)
        let busy = try Self.header(offer, pending: 3, context: MissionClaimContext(dailyInFlightKeys: [WorkTimerStore.achievementClaimAllSlot]))
        let busyBox = try #require(mcaDiffBox(idle, busy), "떠 있는데 버튼이 안 흐려졌다")
        #expect(busyBox.minX >= noteEnd && busyBox.maxY <= 20)
        #expect(mcaGradientPixels(busy, x: 200...292, y: 0...20) < mcaGradientPixels(idle, x: 200...292, y: 0...20))
        mcaSave(busy, name: "claim-all-header-daily-busy.png")
    }

    @Test("누적 절 — 받을 것 여럿이면 머리에 버튼(머리 20pt 안 · 오른쪽) · 하나뿐 · 루비 하나 + 캐릭터 하나면 버튼 없이 '받을 보상 N개' · 절 높이 그대로")
    func mcaCumulativeSectionHeader() throws {
        func section(_ status: AchievementStatus, name: String) throws -> (NSBitmapImageRep, AchievementSectionState) {
            let state = AchievementSectionState.make(status: status, unavailable: false, failed: false)
            let bitmap = try mcaBitmap(AchievementSectionView(state: state).frame(width: 292).background(Color.black)
                .environment(\.colorScheme, .dark))
            mcaSave(bitmap, name: name)
            return (bitmap, state)
        }
        let (several, severalState) = try section(MCAFixture.status(), name: "claim-all-section-cumulative-several.png")
        let (single, _) = try section(MCAFixture.status(MCAFixture.cumulativeSingle), name: "claim-all-section-cumulative-single.png")
        let (mixed, _) = try section(MCAFixture.status(MCAFixture.cumulativeSingle, character: MCAFixture.characterClaimable),
                                     name: "claim-all-section-cumulative-ruby1-character1.png")
        let headerBand = (x: CGFloat(150)...CGFloat(292), y: CGFloat(0)...CGFloat(20))
        let g = (several: mcaGradientPixels(several, x: headerBand.x, y: headerBand.y),
                 single: mcaGradientPixels(single, x: headerBand.x, y: headerBand.y),
                 mixed: mcaGradientPixels(mixed, x: headerBand.x, y: headerBand.y))
        print("[mca] 누적 머리 그라데이션 — 여럿 \(g.several) · 하나 \(g.single) · 루비1+캐릭터1 \(g.mixed)")
        #expect(g.several > 150, "받을 것 넷인데 누적 머리에 [모두 받기]가 없다")
        #expect(g.single == 0 && g.mixed == 0, "하나뿐(또는 루비 하나 + 캐릭터 하나)인데 머리에 버튼이 섰다")
        // 절 높이는 버튼과 무관하다(스크롤 판정의 셈 그대로).
        #expect(CGFloat(several.pixelsHigh) / 2 == AchievementSectionLayout.height(severalState) - AchievementSectionLayout.rowSpacing)
        // 버튼은 머리 줄 안에서만 갈린다(받을 것이 없는 같은 줄들과 견준다).
        guard case .loaded(let rows, _) = severalState else { Issue.record("절이 줄을 안 그렸다"); return }
        let none = try mcaBitmap(AchievementSectionView(state: .loaded(rows: rows, claimableCount: 0)).frame(width: 292)
            .background(Color.black).environment(\.colorScheme, .dark))
        let box = try #require(mcaDiffBox(several, none))
        print("[mca] 누적 절 — 버튼 있음 ↔ 없음 갈림 \(box)")
        #expect(box.maxY <= 20 && box.minX > 150, "버튼이 머리 오른쪽 20pt 밖까지 그렸다: \(box)")
    }

    @Test("팝오버 높이 — 두 묶음에 버튼이 서도 창 높이는 그대로(v0.3.56 상한) · 버튼 없는 같은 표와 같다 · 최악 ≤ 700pt")
    func mcaPanelHeightBudget() throws {
        let fiveRows = [V0356Fixture.lap] + (1...4).map(V0356Fixture.future)
        let capped = try Self.height(CheckMenuView(store: mcaRenderStore(achievements: nil, missions: fiveRows + [V0356Fixture.future(5)])))
        let withButtons = try Self.height(CheckMenuView(store: mcaRenderStore(
            achievements: MCAFixture.status(daily: MCAFixture.dailySeveral), weekly: V0358Fixture.weekly())))
        let without = try Self.height(CheckMenuView(store: mcaRenderStore(
            achievements: MCAFixture.status(MCAFixture.cumulativeSingle, daily: MCAFixture.dailySingle), weekly: V0358Fixture.weekly())))
        print("[mca] 창 높이 — 버튼 둘 \(withButtons) · 버튼 없음 \(without) · 상한 \(capped)pt")
        #expect(withButtons == capped && without == capped, "[모두 받기]가 창 높이를 바꿨다")
        for (banner, editing) in [(true, true), (false, false)] {
            let store = mcaRenderStore(achievements: MCAFixture.status(daily: MCAFixture.dailySeveral), weekly: V0358Fixture.weekly())
            store.missionNotice = V0358Fixture.lapNotice
            let clip = try Self.height(CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: editing,
                                                     previewUpdateBanner: banner, previewUpdateNotes: banner ? ["a", "b", "c", "d"] : []))
            #expect(clip <= 700, "버튼 선 미션 화면 \(clip)pt — 상한을 넘어 푸터가 잘린다")
        }
    }

    @Test("미션 화면 스틸(PNG) — 일일 여럿 · 누적 여럿이면 두 머리에 버튼 · 하나뿐이면 버튼 없음 · 떠 있으면 흐림")
    func mcaPanelShots() throws {
        func full(_ status: AchievementStatus, inFlight: Set<String> = [], line: Int = #line) throws -> NSBitmapImageRep {
            let store = mcaRenderStore(achievements: status, weekly: V0358Fixture.weekly(), line: line)
            store.dailyMissionClaimsInFlight = inFlight
            return try mcaBitmap(CheckMenuView(store: store, previewFullMissionList: true))
        }
        func visible(_ status: AchievementStatus, line: Int = #line) throws -> NSBitmapImageRep {
            try mcaBitmap(CheckMenuView(store: mcaRenderStore(achievements: status, weekly: V0358Fixture.weekly(), line: line),
                                        previewClipsOverflowList: true))
        }
        let several = try full(MCAFixture.status(daily: MCAFixture.dailySeveral))
        let single = try full(MCAFixture.status(MCAFixture.cumulativeSingle, daily: MCAFixture.dailySingle))
        let busy = try full(MCAFixture.status(daily: MCAFixture.dailySeveral), inFlight: [WorkTimerStore.achievementClaimAllSlot])
        mcaSave(several, name: "claim-all-panel-several-full.png")
        mcaSave(single, name: "claim-all-panel-single-full.png")
        mcaSave(busy, name: "claim-all-panel-daily-busy-full.png")
        mcaSave(try visible(MCAFixture.status(daily: MCAFixture.dailySeveral)), name: "claim-all-panel-several-visible.png")
        mcaSave(try visible(MCAFixture.status(MCAFixture.cumulativeSingle, daily: MCAFixture.dailySingle)), name: "claim-all-panel-single-visible.png")
        #expect(several.pixelsHigh == single.pixelsHigh, "같은 줄 수인데 스틸 높이가 다르다")
        // 일일 머리 자리 — 같은 표에서 일일 버튼만 다른 그림(떠 있음)과 견주면 위쪽 첫 갈림이 일일 머리다.
        let dailyHead = try #require(mcaDiffBox(several, busy, maxX: 330), "떠 있는데 일일 버튼 · 줄이 안 흐려졌다")
        let headBand = (x: CGFloat(200)...CGFloat(330), y: dailyHead.minY...(dailyHead.minY + 18))
        let g = (several: mcaGradientPixels(several, x: headBand.x, y: headBand.y),
                 single: mcaGradientPixels(single, x: headBand.x, y: headBand.y))
        print("[mca] 스틸 — 일일 머리 y \(dailyHead.minY) · 그라데이션 여럿 \(g.several) · 하나 \(g.single) · 높이 \(CGFloat(several.pixelsHigh) / 2)pt")
        #expect(g.several > 150, "일일 받을 것 셋인데 일일 머리에 [모두 받기]가 없다")
        #expect(g.single == 0, "일일 받을 것 하나인데 일일 머리에 버튼이 섰다")
        // 누적 머리(통째 스틸의 아래쪽) — 여럿과 하나의 그림이 그 머리 줄에서 갈린다(버튼 ↔ "받을 보상 1개").
        let lower = try #require(mcaDiffBox(several, single, maxX: 330))
        #expect(lower.maxY > dailyHead.minY + 600, "누적 묶음까지 그림이 안 갈렸다(\(lower))")
    }
}

// MARK: - D 소스 계약(주석 제외)

@Suite struct MissionClaimAllSourceTests {
    @Test("배선 — 화면 맥락이 키 없는 받기 둘을 잇고 · 두 머리(일일 · 누적)만 버튼을 받고 · 주간 머리는 그대로 · 이 기능 파일엔 네트워크 · 타이머가 없다")
    func mcaWiringContract() throws {
        let menu = V0317ShopTests.stripped(try V0317ShopTests.source("CheckMenuView.swift"))
        let rows = V0317ShopTests.stripped(try V0317ShopTests.source("CheckAchievementRows.swift"))
        let feature = V0317ShopTests.stripped(try V0317ShopTests.source("MissionClaimAll.swift"))
        func count(_ haystack: String, _ needle: String) -> Int { haystack.components(separatedBy: needle).count - 1 }
        #expect(count(menu, "claimAllAchievements: { store.claimAchievement(key: nil) }") == 1)
        #expect(count(menu, "claimAllDaily: { store.claimDailyMission(key: nil) }") == 1)
        #expect(count(menu, "claimAll: MissionClaimAllOffer.daily(dailyMissions)") == 1, "일일 머리가 버튼을 안 받는다")
        #expect(count(rows, "claimAll: MissionClaimAllOffer.achievement(state)") == 1, "누적 머리가 버튼을 안 받는다")
        #expect(menu.contains("MissionGroupHeader(title: WeeklyMissionCopy.sectionTitle)"), "주간 머리에 무언가 붙었다(주간은 원래 한 버튼)")
        #expect(rows.contains("claim.claimAll(offer.group)") && rows.contains("busy: claim.isClaimAllBusy(offer.group)"),
                "머리 버튼이 맥락의 받기 · 떠 있음을 안 쓴다")
        for banned in ["service.", "refreshAchievements(", "Task", "Timer", "asyncAfter", "URLSession", "claimCharacterMission"] {
            #expect(!feature.contains(banned), "[모두 받기] 파일에 \(banned) — 받기 말고 새 요청 · 타이머 · 캐릭터 받기")
        }
    }
}
