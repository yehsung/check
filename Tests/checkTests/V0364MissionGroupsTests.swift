import AppKit
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.64 — 미션 세 묶음 · 일일 미션 6종 · 미니게임 상금 20/10/5 · 1:1 수수료 0 · 루비 아이콘 통일 · 맥 쪽.
//
// 사용자 결정(2026-10-22, 원문):
//  ① "지금 미션을 일일미션, 주간미션, 누적미션 이렇게 3개로 나눠서 표시하는게 좋을듯. 이렇게 하고 일일미션에 미션들을 몇개 추가할려고 해.
//     미니게임 일반이랑 멀티 총 합쳐서 6개 있잖아. 그거 각각 하나마다 미션 넣어줘. 하루 1회 플레이 달성하면 루비 5개 주는걸로."
//     — 묻고 정한 것: 자정(KST)까지 [받기]를 안 누르면 사라진다 · "근무 3시간마다" 줄은 일일 미션 맨 위(자동 지급 그대로).
//  ② "일반 미니게임 3종 상금루비 올려야할듯 20 10 5 로 다시 해줘."
//  ③ "멀티 미니게임 수수료 다시 제거해줘"
//  ④ "루비 아이콘좀 통일해줘. 실제 루비는 핑크색인데 지금 미션에 있는 루비 아이콘은 달라."
//
// 여기서 잰다:
//  A 전선 — `daily` 디코드(있음 · 없음 · null · 깨짐 · 줄 하나 깨짐 · 게임 칸 없음) · 받기 본문 · 서버 글자와 앱 이름의 짝.
//  B 순수 — 날짜 넘김(서버 시각) · 받을 것 · 같은 날 안에서만 받음이 굳는다(`merged`).
//  C 스토어 — 받기 성공(상태 · 잔량 · 연출 · 말풍선) · 같은 키 한 번에 하나 · 전부 받기 · 실패는 그 줄 · 날짜 넘김이면 요청 0건 ·
//    같은 날 늦은 응답은 받음을 못 되돌리고 새 날 응답은 받음을 안 물려받는다 · 배지 합.
//  D 박자 — 미니게임 제출 성공 · 1:1 판 끝남(처음 본 순간 한 번) 뒤 한 번 묻는다 · 거절 · 같은 판 재수신은 안 묻는다.
//  E 그림 — 일일 줄 세 상태 · 게임마다 다른 아이콘 · 분홍 루비 칩 · 세 묶음 순서 · 창 높이 예산 · 빈 띠 없음 · 일일 없으면 6줄만 숨김.
//  F 상금 상수 · 💎 0(소스 계약 — 주석을 걷어내고 잰다) · 버전/체인지로그.
// 실네트워크 없음(호스트별 스텁) · 창 없음(ImageRenderer 만).

// MARK: - 픽스처

enum V0364Fixture {
    struct Daily {
        var key: String
        var game: String
        var title: String
        var reward: Int = 5
        var achieved: Bool
        var claimed: Bool
        var sort: Int
    }

    static let t = V0358Fixture.t
    /// 렌더 스토어는 진짜 시계를 쓴다(응답을 직접 꽂아 시계 차가 0) — 리셋을 먼 미래(2100-01-01)로 두어 어느 날 돌려도 날이 안 넘어가게.
    static let resetFar = 4_102_444_800_000

    /// 서버 정의표(20261023130000 `daily_mission_defs`) 그대로의 여섯 줄 — 섞인 상태:
    /// 타이밍 바 **받기** · 플래피 받음 · 테트리스 0/1 · 오목 **받기** · 체스 0/1 · 1:1 테트리스 0/1. 받을 것 = 2개 · 10.
    static let base: [Daily] = [
        Daily(key: "daily_timing_bar", game: "timing_bar", title: "타이밍 바 한 판 하기", achieved: true, claimed: false, sort: 10),
        Daily(key: "daily_flappy", game: "flappy", title: "플래피 아잉 한 판 하기", achieved: true, claimed: true, sort: 20),
        Daily(key: "daily_tetris", game: "tetris", title: "테트리스 한 판 하기", achieved: false, claimed: false, sort: 30),
        Daily(key: "daily_gomoku", game: "gomoku", title: "1:1 오목 한 판 두기", achieved: true, claimed: false, sort: 40),
        Daily(key: "daily_chess", game: "chess", title: "1:1 체스 한 판 두기", achieved: false, claimed: false, sort: 50),
        Daily(key: "daily_tetris_duel", game: "tetris_duel", title: "1:1 테트리스 한 판 하기", achieved: false, claimed: false, sort: 60),
    ]

    static var fresh: [Daily] { base.map { var d = $0; d.achieved = false; d.claimed = false; return d } }

    static func with(_ key: String, achieved: Bool? = nil, claimed: Bool? = nil) -> [Daily] {
        with(base, key, achieved: achieved, claimed: claimed)
    }

    static func with(_ rows: [Daily], _ key: String, achieved: Bool? = nil, claimed: Bool? = nil) -> [Daily] {
        rows.map { row in
            guard row.key == key else { return row }
            var d = row
            if let achieved { d.achieved = achieved }
            if let claimed { d.claimed = claimed; if claimed { d.achieved = true } }
            return d
        }
    }

    /// 계약 모양의 `daily` 객체(스네이크 키).
    static func dailyObject(_ rows: [Daily] = base, day: String = "2026-06-12", resetAt: Int = t + 4 * 3_600_000) -> [String: Any] {
        let claimable = rows.filter { $0.achieved && !$0.claimed }
        return [
            "kst_day": day,
            "reset_at_ms": resetAt,
            "missions": rows.map { r -> [String: Any] in
                ["key": r.key, "game": r.game, "title": r.title, "detail": "", "reward": r.reward, "target": 1,
                 "progress": r.achieved ? 1 : 0, "achieved": r.achieved, "claimed": r.claimed,
                 "claimed_at_ms": r.claimed ? (t - 1_000) as Any : NSNull() as Any, "sort": r.sort]
            },
            "claimable_count": claimable.count,
            "claimable_ruby": claimable.reduce(0) { $0 + $1.reward },
        ]
    }

    /// `achievements_status()` 응답(누적 13개 + `daily`). `daily: nil` 이면 칸 자체가 없다(옛 서버).
    static func json(daily: Any? = dailyObject(), achievements: [V0358Fixture.Row] = V0358Fixture.base,
                     claimedNow: [(key: String, title: String, reward: Int)] = [], ruby: Int? = 1234, serverNow: Int = t) -> String {
        let base = V0358Fixture.json(achievements, claimedNow: claimedNow, ruby: ruby, serverNow: serverNow)
        var root = (try! JSONSerialization.jsonObject(with: Data(base.utf8))) as! [String: Any]
        if let daily { root["daily"] = daily }
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// `daily_mission_claim(p_key)` 응답 — 그 키를 받은 뒤의 표 + `claimed_now`(일일 지급만).
    static func claimJSON(_ rows: [Daily] = base, key: String, ruby: Int? = 1239, resetAt: Int = t + 4 * 3_600_000) -> String {
        let after = with(rows, key, claimed: true)
        let row = rows.first { $0.key == key }!
        return json(daily: dailyObject(after, resetAt: resetAt), claimedNow: [(key, row.title, row.reward)], ruby: ruby)
    }

    static func status(_ rows: [Daily] = base, resetAt: Int = resetFar, achievements: [V0358Fixture.Row] = V0358Fixture.base) -> AchievementStatus {
        try! V0358Fixture.decode(json(daily: dailyObject(rows, resetAt: resetAt), achievements: achievements))
    }
}

// MARK: - 공용 도우미

private enum V0364Error: Error { case renderFailed }

@MainActor
private func v0364Bitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw V0364Error.renderFailed }
    return bitmap
}

private func v0364Count(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
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

/// 분홍(루비 그림 `ruby.png` 의 자홍 — 실측 224,64~160,224) 픽셀. 강조색(파랑) · 근무색(초록) · 흰 · 회색 글자 · 파란 💎 와 갈린다.
private func v0364PinkPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0364Count(bitmap, x: x, y: y) { r, g, b in r > 170 && b > 140 && r - g > 50 }
}

/// 근무색(초록) 픽셀 — "✓ 받음".
private func v0364GreenPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0364Count(bitmap, x: x, y: y) { r, g, b in g > 120 && g - r > 60 && g - b > 25 }
}

/// 받기 버튼 그라데이션 가운데 섞인 색(V0358 과 같은 자).
private func v0364GradientPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0364Count(bitmap, x: x, y: y) { r, g, b in
        guard r > 60, r < 120, g > 150, b > 0 else { return false }
        let ratio = Double(g) / Double(b)
        return ratio >= 0.8 && ratio <= 1.15
    }
}

/// 주황(받기 실패 문장).
private func v0364AmberPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0364Count(bitmap, x: x, y: y) { r, g, b in r > 170 && r - b > 70 && g > 100 && r - g > 25 }
}

/// 두 그림이 갈리는 픽셀의 경계(pt, 채널 차 > 8). 같으면 nil. 크기가 다르면 전체.
private func v0364DiffBox(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, maxX limitX: CGFloat = .infinity) -> CGRect? {
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

/// 본문 열 왼쪽 안쪽 세로 한 줄을 위→아래로 훑어 카드 구간(pt)을 낸다(V0358 `v0358CardRuns` 와 같은 자).
private func v0364CardRuns(_ bitmap: NSBitmapImageRep) -> [(top: CGFloat, bottom: CGFloat)] {
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

private func v0364Child(_ label: String, of value: Any) -> Any? {
    Mirror(reflecting: value).children.first { $0.label == label }?.value
}

/// 렌더용 메인 화면 스토어(V0358 `v0358RenderStore` 와 같은 두 겹 — 답하지 않는 스텁). 네트워크가 이 맥 밖으로 안 나간다.
@MainActor
private func v0364RenderStore(achievements: AchievementStatus? = nil,
                              unavailable: Bool = false,
                              missions: [MissionProgress] = [V0356Fixture.lap],
                              weekly: WeeklyWorkStatus? = nil,
                              notice: String? = nil,
                              ruby: Int? = 1234,
                              function: String = #function, line: Int = #line) -> WorkTimerStore {
    let tag = "v0364-render-L\(line)"
    let home = CheckTestScratch.directory("token-\(tag)", function: function)
    let tokens = TokenUsageStore(
        defaults: CheckTestScratch.defaults("token-\(tag)", function: function),
        homeDirectory: home.appendingPathComponent("home", isDirectory: true),
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
    )
    let host = "v0364-silent-\(UUID().uuidString.prefix(8))".lowercased()
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
    store.rubyBalance = ruby
    store.missions = missions
    store.missionsLoaded = true
    store.streakDays = 9
    store.weeklyWork = weekly
    store.missionNotice = notice
    store.achievements = achievements
    store.achievementsUnavailable = unavailable
    store.isMissionPanelVisible = true
    return store
}

/// 스텁 호스트에 붙은 스토어(V0355 스토어 — 세션 · 팀 · 고정 시계). rpc 마다 응답을 고른다(호출 순번 0부터).
@MainActor
private func v0364Store(_ label: String,
                        clock: V0355Clock = V0355Clock(V0355WeeklyStoreTests.t0),
                        achievements: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(body: V0364Fixture.json()) },
                        claim: @escaping @Sendable (String, Int) -> GomokuStubProtocol.Reply = { body, _ in
                            let key = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_key"] as? String
                            return .init(body: V0364Fixture.claimJSON(key: key ?? "daily_timing_bar"))
                        },
                        extra: (@Sendable (String, String, Int) -> GomokuStubProtocol.Reply?)? = nil,
                        function: String = #function) -> (WorkTimerStore, String) {
    let host = V0355WeeklyStoreTests.host("v0364-\(label)")
    GomokuStubProtocol.register(host: host) { rpc, body, index in
        switch rpc {
        case "achievements_status": return achievements(index)
        case "daily_mission_claim": return claim(body, index)
        default: return extra?(rpc, body, index)
        }
    }
    let store = V0355WeeklyStoreTests.store(host: host, label: "v0364-\(label)", clock: clock, function: function)
    return (store, host)
}

private func v0364Calls(_ host: String, _ rpc: String = "achievements_status") -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

// MARK: - A 전선

@Suite struct V0364DecodeTests {
    @Test("daily 있음 — 여섯 줄을 sort 순으로 · 칸마다 옮긴다 · 기존 최상위 칸(누적 13개 · claimable_count)은 그대로 누적만 말한다")
    func decodesDaily() throws {
        let status = try V0358Fixture.decode(V0364Fixture.json())
        let daily = try #require(status.daily, "daily 를 못 읽었다")
        #expect(daily.kstDay == "2026-06-12" && daily.resetAtMs == V0364Fixture.t + 4 * 3_600_000)
        #expect(daily.missions.map(\.key) == V0364Fixture.base.map(\.key))
        #expect(daily.missions.map(\.game) == ["timing_bar", "flappy", "tetris", "gomoku", "chess", "tetris_duel"])
        let timing = try #require(daily.mission("daily_timing_bar"))
        #expect(timing.row.title == "타이밍 바 한 판 하기" && timing.row.reward == 5 && timing.row.target == 1 && timing.row.progress == 1)
        #expect(timing.row.state == .claimable)
        #expect(daily.mission("daily_flappy")?.row.state == .claimed && daily.mission("daily_flappy")?.row.claimedAtMs == V0364Fixture.t - 1_000)
        #expect(daily.mission("daily_chess")?.row.state == .inProgress)
        #expect(daily.reportedClaimableCount == 2 && daily.reportedClaimableRuby == 10)
        // 기존 칸은 한 글자도 안 바뀐다 — 누적 13개 · 받을 것 2개(폰 50 + 팀3 200)는 누적만 센다.
        #expect(status.missions.count == 13 && status.claimableCount == 2 && status.reportedClaimableCount == 2)
        // 서버 순서가 섞여 와도 sort 순.
        var shuffled = V0364Fixture.base
        shuffled.reverse()
        let reordered = try #require(try V0358Fixture.decode(V0364Fixture.json(daily: V0364Fixture.dailyObject(shuffled))).daily)
        #expect(reordered.missions.map(\.key) == V0364Fixture.base.map(\.key))
    }

    @Test("daily 없음 · null · 객체 아님 → nil(일일 6줄만 감춘다) · 누적은 그대로 산다")
    func missingOrBrokenDailyIsNil() throws {
        let old = try V0358Fixture.decode(V0364Fixture.json(daily: nil))
        #expect(old.daily == nil && old.missions.count == 13)
        for broken in [NSNull() as Any, "oops" as Any, [1, 2, 3] as Any, 7 as Any] {
            let status = try V0358Fixture.decode(V0364Fixture.json(daily: broken))
            #expect(status.daily == nil, "\(broken) 를 일일로 읽었다")
            #expect(status.missions.count == 13 && status.rubyBalance == 1234, "일일 칸 하나 때문에 누적이 죽었다(\(broken))")
        }
    }

    @Test("줄 하나가 깨져도 통째로 안 죽는다 — 키 · 제목 없는 줄만 버린다 · 칸 기본값 · 게임 칸 없으면 키에서 · 같은 키는 앞의 것 · 받음이면 채움")
    func lossyRows() throws {
        var object = V0364Fixture.dailyObject()
        var missions: [Any] = object["missions"] as! [[String: Any]]
        func edit(_ index: Int, _ change: (inout [String: Any]) -> Void) {
            var row = missions[index] as! [String: Any]
            change(&row)
            missions[index] = row
        }
        edit(0) { $0["key"] = NSNull() }                               // 키 없음 → 버린다
        edit(1) { $0["title"] = "   " }                                // 빈 제목 → 버린다
        edit(2) { $0.removeValue(forKey: "game"); $0["reward"] = "5" }  // 게임 없음 → 키에서(tetris) · 문자열 숫자
        edit(3) { $0["achieved"] = "yes" }                             // 모양 틀림 → 시각 없음 → 아니다
        edit(4) { $0["claimed"] = true; $0["achieved"] = false }       // 받음 → 채움도 참
        missions.append(["key": "daily_tetris", "title": "중복", "sort": 1] as [String: Any])   // 같은 키 → 앞의 것만
        missions.append(42)                                            // 객체 아님 → 건너뛴다
        object["missions"] = missions
        object["reset_at_ms"] = "\(V0364Fixture.t + 10)"                   // 문자열 bigint
        let daily = try #require(try V0358Fixture.decode(V0364Fixture.json(daily: object)).daily)
        #expect(daily.missions.map(\.key) == ["daily_tetris", "daily_gomoku", "daily_chess", "daily_tetris_duel"])
        #expect(daily.mission("daily_tetris")?.game == "tetris" && daily.mission("daily_tetris")?.row.reward == 5
                && daily.mission("daily_tetris")?.row.title == "테트리스 한 판 하기")
        #expect(daily.mission("daily_gomoku")?.row.achieved == false, "모양이 틀린 achieved 를 참으로 읽었다")
        #expect(daily.mission("daily_chess")?.row.achieved == true && daily.mission("daily_chess")?.row.state == .claimed)
        #expect(daily.resetAtMs == V0364Fixture.t + 10)
        // 빈 객체도 산다(줄 0 — 화면은 6줄을 감춘다).
        let empty = try #require(try V0358Fixture.decode(V0364Fixture.json(daily: [String: Any]())).daily)
        #expect(empty.missions.isEmpty && empty.kstDay == nil && empty.resetAtMs == nil)
    }

    @Test("받기 본문 — 키를 언제나 싣는다: {\"p_key\":\"daily_gomoku\"} · 전부 받기 {\"p_key\":null} · 경로 daily_mission_claim")
    func claimBody() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        #expect(String(decoding: try encoder.encode(AchievementClaimRequest(key: "daily_gomoku")), as: UTF8.self) == #"{"p_key":"daily_gomoku"}"#)
        #expect(String(decoding: try encoder.encode(AchievementClaimRequest(key: nil)), as: UTF8.self) == #"{"p_key":null}"#)
        #expect(SupabaseWorkService.dailyMissionClaimPath == "/rest/v1/rpc/daily_mission_claim")
    }

    @Test("서버 글자 · 게임 칸이 앱 이름과 짝이다 — 미니게임 칩 이름(MiniGameKind.title) · 1:1 입구 이름 · MiniGameKind 원시값")
    @MainActor
    func titlesMatchTheAppNames() {
        let names: [String: String] = [
            "timing_bar": MiniGameKind.timingBar.title, "flappy": MiniGameKind.flappy.title, "tetris": MiniGameKind.tetris.title,
            "gomoku": MiniGameGomokuEntryButton.title, "chess": MiniGameChessEntryButton.title, "tetris_duel": MiniGameTetrisDuelEntryButton.title,
        ]
        for row in V0364Fixture.base {
            let name = names[row.game]
            #expect(name != nil && row.title.hasPrefix(name! + " "), "'\(row.title)' 가 앱 이름 '\(name ?? "?")' 로 시작하지 않는다")
        }
        #expect(Set(MiniGameKind.allCases.map(\.rawValue)) == ["timing_bar", "flappy", "tetris"])
    }
}

// MARK: - B 순수

@Suite struct V0364PureTests {
    @Test("날짜 넘김 — 리셋 시각(서버) 전에는 그대로 · 닿으면 새 날의 모양(진행 0 · [받기] 없음 · 받음 없음) · 모르면 넘기지 않는다")
    func rollover() throws {
        let reset = V0364Fixture.t + 60_000
        let daily = try #require(V0364Fixture.status(resetAt: reset).daily)
        #expect(!daily.hasRolledOver(serverNowMs: reset - 1))
        #expect(daily.claimableCount(serverNowMs: reset - 1) == 2 && daily.claimableRuby(serverNowMs: reset - 1) == 10)
        #expect(daily.hasRolledOver(serverNowMs: reset))
        let next = daily.rows(serverNowMs: reset)
        #expect(next.count == 6 && next.allSatisfy { $0.row.state == .inProgress && $0.row.progress == 0 && $0.row.claimedAtMs == nil })
        #expect(next.map(\.key) == daily.missions.map(\.key) && next.map(\.row.title) == daily.missions.map(\.row.title))
        #expect(daily.claimableCount(serverNowMs: reset) == 0 && daily.claimable(serverNowMs: reset + 999_999).isEmpty)
        #expect(!daily.hasRolledOver(serverNowMs: nil) && !DailyMissionStatus(missions: daily.missions).hasRolledOver(serverNowMs: .max))
    }

    @Test("받음은 같은 kst_day 안에서만 굳는다 — 같은 날 늦게 온 옛 응답은 받은 줄을 못 되돌리고, 새 날 응답은 어제 받음을 안 물려받는다")
    func mergeIsScopedToTheDay() throws {
        let claimed = try #require(V0364Fixture.status(V0364Fixture.with("daily_timing_bar", claimed: true)).daily)
        let staleSameDay = try #require(V0364Fixture.status().daily)
        let merged = staleSameDay.merged(over: claimed)
        #expect(merged.mission("daily_timing_bar")?.row.state == .claimed, "같은 날 옛 응답이 받은 줄을 [받기]로 되돌렸다")
        #expect(merged.mission("daily_gomoku")?.row.state == .claimable, "받지 않은 줄까지 받음이 됐다")
        // 새 날: 같은 키가 다시 채워져(오늘 또 했다) [받기] — 어제 받음이 덮으면 오늘 받을 수 없다.
        var nextObject = V0364Fixture.dailyObject(V0364Fixture.base, day: "2026-06-13", resetAt: V0364Fixture.resetFar)
        nextObject["kst_day"] = "2026-06-13"
        let nextDay = try #require(try V0358Fixture.decode(V0364Fixture.json(daily: nextObject)).daily)
        #expect(nextDay.merged(over: claimed).mission("daily_timing_bar")?.row.state == .claimable, "어제 받음이 오늘 줄을 덮었다")
        // 날을 모르면 이어 붙이지 않는다.
        var unknown = staleSameDay
        unknown.kstDay = nil
        #expect(unknown.merged(over: claimed).mission("daily_timing_bar")?.row.state == .claimable)
        // 누적 미션 병합(`AchievementStatus.merged`)이 일일도 같은 규칙으로 옮긴다 — 누적에 받은 것이 없어도.
        let fresh = V0364Fixture.status(achievements: V0358Fixture.fresh)
        let freshClaimed = V0364Fixture.status(V0364Fixture.with("daily_timing_bar", claimed: true), achievements: V0358Fixture.fresh)
        #expect(fresh.merged(over: freshClaimed).daily?.mission("daily_timing_bar")?.row.state == .claimed)
    }

    @Test("1:1 판이 '막 끝났다' — 새로 끝난 판만 참(같은 판의 끝난 모양을 또 받으면 거짓 · 진행 중 거짓 · 없음 거짓)")
    @MainActor
    func matchJustFinished() throws {
        let won = try V0354DuelFeeTests.gomokuPayload(try V0354DuelFeeTests.fixture("gomoku-rpc", "gomoku_state__finished_since9"),
                                                      stake: 3, myColor: "black")
        let store = GomokuStore(host: nil)
        store.applyState(won)
        let finished = try #require(store.match)
        #expect(finished.isFinished)
        #expect(GomokuStore.matchJustFinished(from: nil, to: finished))
        #expect(!GomokuStore.matchJustFinished(from: finished, to: finished), "같은 판을 다시 받았는데 또 끝났다고 했다")
        #expect(!GomokuStore.matchJustFinished(from: finished, to: nil))
        var playing = finished
        playing.isFinished = false
        #expect(GomokuStore.matchJustFinished(from: playing, to: finished), "진행 중 → 끝남을 못 봤다")
        #expect(!GomokuStore.matchJustFinished(from: nil, to: playing))
    }
}

// MARK: - C 스토어

@MainActor
@Suite(.serialized) struct V0364ClaimStoreTests {
    @Test("받기 성공 — POST daily_mission_claim {p_key} · 상태 · 잔량 · 연출(일일 자리) · 말풍선 · 떠 있음 해제 · 배지 감소 · 누적 받기는 안 나간다")
    func claimSuccess() async throws {
        let (store, host) = v0364Store("claim-ok")
        var bubbles: [Int] = []
        store.onRewardTrigger = { if case .rubyReward(let amount) = $0 { bubbles.append(amount) } }
        await store.refreshAchievements(reason: .missionPanel)?.value
        #expect(store.dailyMissionRows?.count == 6 && store.missionClaimableCount == 4, "전제: 일일 2 + 누적 2")
        let task = store.claimDailyMission(key: "daily_timing_bar")
        #expect(task != nil && store.dailyMissionClaimsInFlight == ["daily_timing_bar"])
        await task?.value
        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "daily_mission_claim").first)
        #expect(call.body == #"{"p_key":"daily_timing_bar"}"#)
        #expect(store.achievements?.daily?.mission("daily_timing_bar")?.row.state == .claimed)
        #expect(store.rubyBalance == 1239)
        #expect(store.missionClaimBursts[MissionClaimBurst.dailyTarget(key: "daily_timing_bar")]?.amount == 5)
        #expect(store.missionClaimBursts.keys.allSatisfy { $0.hasPrefix("daily:") }, "일일 연출이 다른 줄 자리에 섰다")
        #expect(bubbles == [5])
        #expect(store.dailyMissionClaimsInFlight.isEmpty && store.dailyMissionClaimFailedKeys.isEmpty)
        #expect(store.missionClaimableCount == 3)
        #expect(v0364Calls(host, "achievement_claim") == 0)
    }

    @Test("같은 키 두 번 = 요청 1건 · 다른 키는 따로 · 전부 받기({p_key:null})가 떠 있으면 낱개도 기다린다 · 받을 수 없는 키는 0건")
    func inFlightAndAll() async throws {
        let (store, host) = v0364Store("claim-inflight", claim: { body, _ in
            let key = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_key"] as? String
            return .init(body: V0364Fixture.claimJSON(key: key ?? "daily_timing_bar"), delay: 0.3)
        })
        await store.refreshAchievements(reason: .missionPanel)?.value
        let first = store.claimDailyMission(key: "daily_timing_bar")
        #expect(first != nil && store.claimDailyMission(key: "daily_timing_bar") == nil, "떠 있는 같은 키를 또 보냈다")
        let other = store.claimDailyMission(key: "daily_gomoku")
        #expect(other != nil, "다른 키가 막혔다")
        // 받을 수 없는 키(진행 중 · 이미 받음 · 모르는 키)는 서버에 묻지도 않는다.
        #expect(store.claimDailyMission(key: "daily_chess") == nil && store.claimDailyMission(key: "daily_flappy") == nil
                && store.claimDailyMission(key: "nope") == nil)
        await first?.value
        await other?.value
        #expect(v0364Calls(host, "daily_mission_claim") == 2)
        // 전부 받기 — 받을 것이 다시 생긴 **다음 날** 응답으로(같은 날이면 받음이 굳어 받을 것이 없다 — `merged`).
        store.applyAchievements(try V0358Fixture.decode(V0364Fixture.json(daily: V0364Fixture.dailyObject(day: "2026-06-13"))))
        let all = store.claimDailyMission(key: nil)
        #expect(all != nil && store.claimDailyMission(key: "daily_gomoku") == nil, "전부 받기가 떠 있는데 낱개가 나갔다")
        await all?.value
        #expect(GomokuStubProtocol.calls(host: host, rpc: "daily_mission_claim").last?.body == #"{"p_key":null}"#)
        #expect(v0364Calls(host, "daily_mission_claim") == 3)
    }

    @Test("실패 — 그 줄에 실패 표시 · 버튼은 그대로(안 받음) · 떠 있음 해제 · 다시 누르면 나가고 받으면 표시가 내려간다 · 전부 받기 실패는 받을 줄 전부")
    func claimFailure() async throws {
        let (store, host) = v0364Store("claim-fail", claim: { body, index in
            index < 2 ? .init(status: 500, body: #"{"message":"boom"}"#) : .init(body: V0364Fixture.claimJSON(key: "daily_gomoku"))
        })
        await store.refreshAchievements(reason: .missionPanel)?.value
        await store.claimDailyMission(key: "daily_gomoku")?.value
        #expect(store.dailyMissionClaimFailedKeys == ["daily_gomoku"])
        #expect(store.achievements?.daily?.mission("daily_gomoku")?.row.state == .claimable, "실패했는데 받음으로 그렸다")
        #expect(store.dailyMissionClaimsInFlight.isEmpty && store.achievementClaimFailedKeys.isEmpty)
        await store.claimDailyMission(key: nil)?.value
        #expect(store.dailyMissionClaimFailedKeys == ["daily_gomoku", "daily_timing_bar"])
        await store.claimDailyMission(key: "daily_gomoku")?.value
        #expect(v0364Calls(host, "daily_mission_claim") == 3)
        #expect(store.dailyMissionClaimFailedKeys == ["daily_timing_bar"])
        store.clearMissionClaimFailures()
        #expect(store.dailyMissionClaimFailedKeys.isEmpty)
    }

    @Test("날짜 넘김 — 서버 시각으로 리셋을 넘기면 [받기]가 없고(새 날의 모양) 받기는 0건 · 배지에서 빠진다 · 이 맥 시계가 틀려도 서버 시각으로 잰다")
    func rolloverBlocksTheClaim() async throws {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        // 서버 시각 = t(이 맥 시계 t0 보다 3일 남짓 앞 — 시계가 틀린 맥) · 리셋 = t + 60초.
        let (store, host) = v0364Store("rollover", clock: clock, achievements: { _ in
            .init(body: V0364Fixture.json(daily: V0364Fixture.dailyObject(resetAt: V0364Fixture.t + 60_000)))
        })
        await store.refreshAchievements(reason: .missionPanel)?.value
        #expect(store.dailyMissionRows?.filter(\.row.isClaimable).count == 2, "리셋 전인데 [받기]가 없다 — 이 맥 시계로 쟀다")
        #expect(store.missionClaimableCount == 4)
        clock.advance(59)
        #expect(store.dailyMissionRows?.filter(\.row.isClaimable).count == 2)
        clock.advance(1)
        let rows = try #require(store.dailyMissionRows)
        #expect(rows.count == 6 && rows.allSatisfy { $0.row.state == .inProgress }, "날을 넘겼는데 어제 [받기] · 받음이 남았다")
        #expect(store.claimDailyMission(key: "daily_timing_bar") == nil && store.claimDailyMission(key: nil) == nil)
        await V0355WeeklyStoreTests.settle()
        #expect(v0364Calls(host, "daily_mission_claim") == 0, "어제 줄의 받기가 나갔다")
        #expect(store.missionClaimableCount == 2, "날을 넘긴 일일 줄을 배지가 셌다")
    }

    @Test("같은 날 늦게 온 조회는 받은 줄을 못 되돌린다 · 다음 날 응답은 어제 받음을 안 물려받는다(스토어 길)")
    func storeMergeScope() throws {
        let (store, _) = v0364Store("merge-scope")
        store.applyAchievements(try V0358Fixture.decode(V0364Fixture.json(daily: V0364Fixture.dailyObject(
            V0364Fixture.with("daily_timing_bar", claimed: true)))))
        store.applyAchievements(try V0358Fixture.decode(V0364Fixture.json()))
        #expect(store.achievements?.daily?.mission("daily_timing_bar")?.row.state == .claimed)
        store.applyAchievements(try V0358Fixture.decode(V0364Fixture.json(daily: V0364Fixture.dailyObject(day: "2026-06-13"))))
        #expect(store.achievements?.daily?.mission("daily_timing_bar")?.row.state == .claimable)
    }

    @Test("배지 = 일일 받을 것 + 누적 받을 것 + 주간 받을 것 · 서버에 없음이면 일일 · 누적 몫 0 · 일일 없는 서버는 누적 + 주간")
    func badgeSum() {
        let (store, _) = v0364Store("badge")
        store.applyAchievements(V0364Fixture.status())
        #expect(store.missionClaimableCount == 4)
        store.applyWeeklyWork(V0358Fixture.weekly())
        #expect(store.missionClaimableCount == 6)
        store.applyAchievements(V0358Fixture.status())
        // 일일이 없는 응답(옛 서버)은 일일 몫이 0 이다 — 위에서 받은 일일을 병합이 남기지 않는다.
        #expect(store.achievements?.daily == nil && store.missionClaimableCount == 4)
        store.applyAchievements(V0364Fixture.status())
        store.achievementsUnavailable = true
        #expect(store.missionClaimableCount == 2 && store.dailyMissionRows == nil)
    }

    @Test("로그아웃 · 계정 전환 — 일일 떠 있음 · 실패 · 시계 차를 내린다")
    func resetOnAccountSwitch() throws {
        let source = V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStore.swift"))
        for needle in ["dailyMissionClaimsInFlight = []", "dailyMissionClaimFailedKeys = []", "achievementsServerClockOffsetMs = 0"] {
            #expect(source.contains(needle), "계정이 바뀔 때 \(needle) 가 없다")
        }
    }
}

// MARK: - D 박자

@MainActor
@Suite(.serialized) struct V0364CadenceTests {
    @Test("미니게임 판 제출 성공(ok · token_used) 뒤 한 번 묻는다 · 거절(token_expired)은 안 묻는다")
    func afterMiniGameSubmit() async throws {
        for (status, expected) in [("ok", 1), ("token_used", 1), ("token_expired", 0)] {
            let (store, host) = v0364Store("submit-\(status)", extra: { rpc, _, _ in
                switch rpc {
                case "minigame_submit_score": return .init(body: #"{"status":"\#(status)","best_score":3,"plays":1,"improved":true}"#)
                case "minigame_start_round": return .init(body: #"{"status":"ok","token":"tok-next"}"#)
                default: return nil
                }
            })
            let entry = MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 3, token: "tok-1",
                                              tokenIssuedAt: V0355WeeklyStoreTests.t0, recordedAt: V0355WeeklyStoreTests.t0, attempts: 0)
            await store.performSubmitMiniGameScore(entry: entry)
            #expect(v0364Calls(host, "minigame_submit_score") == 1, "전제: 제출이 나갔다")
            if expected > 0 {
                #expect(await V0354CoreStub.waitUntil { v0364Calls(host) == expected && store.achievementsFetchTask == nil },
                        "\(status): 제출이 남았는데 일일 미션을 안 물었다(\(v0364Calls(host))회)")
                #expect(store.achievements?.daily != nil)
            } else {
                await V0355WeeklyStoreTests.settle()
                #expect(v0364Calls(host) == 0, "\(status): 거절된 판인데 물었다")
            }
        }
    }

    @Test("1:1 판이 끝난 것을 처음 본 순간 한 번 묻는다(오목 · 체스) · 같은 판을 다시 받아도 또 안 묻는다")
    func afterDuelFinished() async throws {
        let (store, host) = v0364Store("duel")
        let gomoku = try V0354DuelFeeTests.gomokuPayload(
            try V0354DuelFeeTests.fixture("gomoku-rpc", "gomoku_state__finished_since9"), stake: 3, myColor: "black")
        store.gomoku.applyState(gomoku)
        #expect(await V0354CoreStub.waitUntil { v0364Calls(host) == 1 && store.achievementsFetchTask == nil },
                "오목 판이 끝났는데 일일 미션을 안 물었다(\(v0364Calls(host))회)")
        store.gomoku.applyState(gomoku)
        // 같은 끝난 판을 다시 넣는다(받은함 · 폴링이 같은 판을 또 옮기는 경우 — `applyState` 가 같은 값이면 대입을 건너뛸 수 있어
        // 직접 대입해 didSet 을 반드시 지나게 한다).
        store.gomoku.match = store.gomoku.match
        await V0355WeeklyStoreTests.settle()
        #expect(v0364Calls(host) == 1, "같은 끝난 판을 다시 받았는데 또 물었다")
        let chess = try V0354DuelFeeTests.chessPayload(
            try V0354DuelFeeTests.fixture("chess-rpc-clock10", "chess_state__ok_finished_winner"), stake: 3, myColor: "white")
        store.chess.applyState(chess)
        #expect(await V0354CoreStub.waitUntil { v0364Calls(host) == 2 && store.achievementsFetchTask == nil },
                "체스 판이 끝났는데 일일 미션을 안 물었다(\(v0364Calls(host))회)")
    }

    @Test("소스 계약 — 세 스토어가 '막 끝났다'에서만 문을 부르고(오목 · 체스는 AI 판 제외) 맥이 셋 다 잇는다 · 제출 성공 꼬리에서만 부른다(주석 제외)")
    func wiringContract() throws {
        for (file, needle) in [("GomokuStore.swift", "if Self.matchJustFinished(from: oldValue, to: match), !isAIMatch { onMatchFinished?() }"),
                               ("ChessStore.swift", "if Self.matchJustFinished(from: oldValue, to: match), !isAIMatch { onMatchFinished?() }"),
                               ("TetrisDuelStore.swift", "if Self.matchJustFinished(from: oldValue, to: match) { onMatchFinished?() }")] {
            let url = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/CheckCore/\(file)")
            let code = V0317ShopTests.stripped(try String(contentsOf: url, encoding: .utf8))
            #expect(code.contains(needle), "\(file): 판 끝남 문이 없다")
            #expect(code.components(separatedBy: "onMatchFinished?()").count - 1 == 1, "\(file): 판 끝남 문을 여러 곳에서 부른다")
            #expect(code.contains("guard let new, new.isFinished else { return false } return !(old?.id == new.id && old?.isFinished == true)"),
                    "\(file): '막 끝났다' 판정이 바뀌었다")
        }
        let store = V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStore.swift"))
        // 게임 이름 = 일일 미션 키의 꼬리(서버 정의표 · 픽스처와 같은 글자 — 다르면 '이미 채웠으면 안 묻는다' 문이 영영 안 닫힌다).
        for (field, game) in [("gomoku", "gomoku"), ("chess", "chess"), ("tetris", "tetris_duel")] {
            #expect(store.contains("\(field).onMatchFinished = { [weak self] in self?.refreshAchievementsAfterGameResult(game: \"\(game)\") }"),
                    "\(field) 판 끝남이 일일 미션 조회(\(game))에 안 이어졌다")
            #expect(V0364Fixture.base.contains { $0.key == DailyMissionStatus.key(game: game) && $0.game == game }, "\(game) 는 일일 미션 키가 아니다")
        }
        let minigame = V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStoreMiniGame.swift"))
        #expect(minigame.contains("if recorded { refreshAchievementsAfterGameResult(game: kind.rawValue) }"))
        for kind in MiniGameKind.allCases {
            #expect(V0364Fixture.base.contains { $0.key == DailyMissionStatus.key(game: kind.rawValue) }, "\(kind) 원시값이 일일 미션 키가 아니다")
        }
        #expect(minigame.components(separatedBy: "recorded = true").count - 1 == 1, "제출 성공이 아닌 갈래에서도 조회한다")
    }
}

// MARK: - E 그림

@MainActor
@Suite(.serialized) struct V0364RenderTests {
    static func row(_ mission: DailyMissionStatus.Mission, context: MissionClaimContext = MissionClaimContext()) throws -> NSBitmapImageRep {
        try v0364Bitmap(AchievementRowView(mission: mission.row, group: .daily(game: mission.game)).frame(width: 292).background(Color.black)
            .environment(\.missionClaim, context)
            .environment(\.colorScheme, .dark))
    }

    static func daily(_ key: String, _ rows: [V0364Fixture.Daily] = V0364Fixture.base) throws -> DailyMissionStatus.Mission {
        try #require(V0364Fixture.status(rows).daily?.mission(key))
    }

    static func height(_ view: CheckMenuView) throws -> CGFloat { CGFloat(try v0364Bitmap(view).pixelsHigh) / 2 }

    @Test("일일 줄 — 채움 → [받기 루비 +5](그라데이션) · 받음 → ✓ 받음(근무색) · 진행 중 → 분홍 루비 칩 + '0/1', 버튼 없음 · 높이 56")
    func rowStates() throws {
        let claimable = try Self.row(try Self.daily("daily_timing_bar"))
        let claimed = try Self.row(try Self.daily("daily_flappy"))
        let progress = try Self.row(try Self.daily("daily_chess"))
        #expect([claimable, claimed, progress].allSatisfy { $0.pixelsHigh == 112 }, "줄 높이가 56pt 가 아니다")
        let button = (x: CGFloat(196)...CGFloat(284), y: CGFloat(14)...CGFloat(42))
        #expect(v0364GradientPixels(claimable, x: button.x, y: button.y) > 1_000, "채운 일일 줄에 [받기]가 없다")
        #expect(v0364GradientPixels(claimed, x: button.x, y: button.y) < 100 && v0364GradientPixels(progress, x: button.x, y: button.y) < 100)
        let caption = (x: CGFloat(236)...CGFloat(286), y: CGFloat(36)...CGFloat(54))
        #expect(v0364GreenPixels(claimed, x: caption.x, y: caption.y) >= 40, "받은 일일 줄에 ✓ 받음이 없다")
        // 보상 칩(오른쪽 위)과 [받기] 버튼의 루비는 **분홍 그림**이다(파란 💎 글자가 아니다).
        let chip = (x: CGFloat(230)...CGFloat(290), y: CGFloat(2)...CGFloat(22))
        let pinkChip = v0364PinkPixels(progress, x: chip.x, y: chip.y)
        let pinkButton = v0364PinkPixels(claimable, x: button.x, y: button.y)
        print("[v0364] 분홍 루비 — 진행 중 칩 \(pinkChip) · 받기 버튼 \(pinkButton)")
        #expect(pinkChip >= 20, "진행 중 일일 줄의 보상 칩에 분홍 루비가 없다(\(pinkChip))")
        #expect(pinkButton >= 20, "[받기] 버튼에 분홍 루비가 없다(\(pinkButton))")
    }

    @Test("아이콘 — 게임마다 다른 그림(그 게임이 다른 화면에서 쓰는 기호) · 바뀌는 자리는 아이콘 칸뿐 · 모르는 게임은 별")
    func iconsPerGame() throws {
        #expect(DailyMissionCopy.icon(game: "timing_bar") == MiniGameKind.timingBar.icon)
        #expect(DailyMissionCopy.icon(game: "flappy") == MiniGameKind.flappy.icon)
        #expect(DailyMissionCopy.icon(game: "tetris") == MiniGameKind.tetris.icon)
        #expect(DailyMissionCopy.icon(game: "gomoku") == MiniGameGomokuEntryButton.icon)
        #expect(DailyMissionCopy.icon(game: "chess") == ChessEntryIcon.resolved)
        #expect(DailyMissionCopy.icon(game: "tetris_duel") == TetrisDuelEntryIcon.resolved)
        #expect(DailyMissionCopy.icon(game: "unknown") == AchievementCopy.fallbackIcon)
        let icons = Set(["timing_bar", "flappy", "tetris", "gomoku", "chess", "tetris_duel"].map(DailyMissionCopy.icon(game:)))
        #expect(icons.count == 6, "두 게임이 같은 아이콘이다: \(icons)")
        let mission = try Self.daily("daily_chess")
        let asChess = try Self.row(mission)
        let asGomoku = try Self.row(DailyMissionStatus.Mission(game: "gomoku", row: mission.row))
        let box = try #require(v0364DiffBox(asChess, asGomoku), "게임이 달라도 아이콘이 같다")
        #expect(box.maxX < 36, "아이콘 칸 밖이 바뀌었다: \(box)")
    }

    @Test("배선 — 일일 줄의 [받기]는 일일 받기를 부르고(누적 받기 아님) · 떠 있음 · 실패 · 연출이 일일 자리에서 읽힌다")
    func rowRoutesToDaily() throws {
        var dailyCalls: [String] = [], achievementCalls: [String] = []
        let context = MissionClaimContext(claimAchievement: { achievementCalls.append($0) }, claimDaily: { dailyCalls.append($0) })
        context.claim("daily_gomoku", group: .daily(game: "gomoku"))
        context.claim("team3", group: .achievement)
        #expect(dailyCalls == ["daily_gomoku"] && achievementCalls == ["team3"])
        let busy = MissionClaimContext(inFlightKeys: ["daily_gomoku"], failedKeys: ["daily_gomoku"],
                                       dailyInFlightKeys: ["daily_timing_bar"], dailyFailedKeys: ["daily_timing_bar"])
        #expect(busy.isInFlight("daily_timing_bar", group: .daily(game: "timing_bar")) && !busy.isInFlight("daily_gomoku", group: .daily(game: "gomoku")))
        #expect(busy.hasFailed("daily_timing_bar", group: .daily(game: "timing_bar")) && !busy.hasFailed("daily_gomoku", group: .daily(game: "gomoku")))
        let all = MissionClaimContext(dailyInFlightKeys: [WorkTimerStore.achievementClaimAllSlot])
        #expect(all.isInFlight("daily_gomoku", group: .daily(game: "gomoku")) && !all.isInFlight("team3", group: .achievement))
        // 그림 — 실패는 그 줄의 보조 문장(주황) · [받기]는 그대로.
        let timing = try Self.daily("daily_timing_bar")
        let idle = try Self.row(timing)
        let failed = try Self.row(timing, context: MissionClaimContext(dailyFailedKeys: ["daily_timing_bar"]))
        let caption = (x: CGFloat(40)...CGFloat(200), y: CGFloat(36)...CGFloat(54))
        #expect(v0364AmberPixels(idle, x: caption.x, y: caption.y) == 0)
        #expect(v0364AmberPixels(failed, x: caption.x, y: caption.y) > 60, "일일 받기가 실패한 줄에 실패 문장이 없다")
        // 누적 쪽 실패 키는 일일 줄에 안 선다(같은 이름이어도 묶음이 다르다).
        #expect(try CheckRenderDiff(idle.cgImage!, try Self.row(timing, context: MissionClaimContext(failedKeys: ["daily_timing_bar"])).cgImage!)?.looksSame == true)
    }

    @Test("머리 — 일일 '자정에 초기화 · 안 받으면 사라져요'가 한 줄(머리 20pt) · '받을 보상 N개'와 같이 서도 292pt 안 · 세 묶음 이름")
    func headerFitsOneLine() throws {
        #expect(DailyMissionCopy.sectionTitle == "일일 미션" && WeeklyMissionCopy.sectionTitle == "주간 미션" && AchievementCopy.sectionTitle == "누적 미션")
        let header = MissionGroupHeader(title: DailyMissionCopy.sectionTitle, note: DailyMissionCopy.resetNote, pendingCount: 6)
        let bitmap = try v0364Bitmap(header.frame(width: 292))
        #expect(bitmap.pixelsHigh == 40, "머리가 한 줄(20pt)이 아니다: \(CGFloat(bitmap.pixelsHigh) / 2)pt")
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let caption = NSFont.preferredFont(forTextStyle: .caption1)
        let bold = NSFontManager.shared.convert(caption, toHaveTrait: .boldFontMask)
        let caption2 = NSFont.preferredFont(forTextStyle: .caption2)
        let bold2 = NSFontManager.shared.convert(caption2, toHaveTrait: .boldFontMask)
        let total = width(DailyMissionCopy.sectionTitle, bold) + 6 + width(DailyMissionCopy.resetNote, caption2) + 4
            + width(AchievementCopy.pendingHint(6)!, bold2)
        print("[v0364] 일일 머리 폭 \(total)pt / 292pt")
        #expect(total <= 292, "일일 머리가 한 줄에 안 들어간다(\(total)pt) — 안내를 줄여라")
        #expect(DailyMissionCopy.resetNote.contains("자정") && DailyMissionCopy.resetNote.contains("사라"))
        // 미션 화면이 그 안내를 실제로 일일 머리에 단다(문구만 있고 화면이 안 쓰면 위 단언은 공허하다 — 주석 제외).
        let menu = V0317ShopTests.stripped(try V0317ShopTests.source("CheckMenuView.swift"))
        #expect(menu.contains("MissionGroupHeader(title: DailyMissionCopy.sectionTitle, note: DailyMissionCopy.resetNote,"),
                "미션 화면의 일일 머리에 '자정에 초기화' 안내가 없다")
        // 그림으로도: 안내가 있는 머리와 없는 머리는 다르다(안내가 실제로 그려진다).
        let bare = try v0364Bitmap(MissionGroupHeader(title: DailyMissionCopy.sectionTitle, pendingCount: 6).frame(width: 292))
        #expect(try CheckRenderDiff(bitmap.cgImage!, bare.cgImage!)?.looksDifferent == true, "머리 안내가 그림에 안 나타난다")
    }

    @Test("미션 화면 — 일일 줄은 3시간 줄 아래 · 일일 머리는 3시간 줄 위 · 일일이 없으면(옛 서버 · 빈 목록) 6줄만 숨고 3시간 줄은 남는다")
    func panelShowsDailyUnderTheLap() throws {
        func bitmap(_ achievements: AchievementStatus?, lap: MissionProgress = V0356Fixture.lap, line: Int = #line) throws -> NSBitmapImageRep {
            try v0364Bitmap(CheckMenuView(store: v0364RenderStore(achievements: achievements, missions: [lap], line: line),
                                          previewClipsOverflowList: true))
        }
        // 누적 줄은 전부 진행 중(받기 없음) — 3시간 줄 아래의 [받기]가 일일 줄의 것뿐이게(대조군이 누적 [받기]에 흐려지지 않게).
        let withDaily = try bitmap(V0364Fixture.status(achievements: V0358Fixture.fresh))
        let oldServer = try bitmap(V0358Fixture.status(V0358Fixture.fresh))
        let emptyDaily = try bitmap(try V0358Fixture.decode(V0364Fixture.json(daily: V0364Fixture.dailyObject([]),
                                                                               achievements: V0358Fixture.fresh)))
        let lapMoved = try bitmap(V0358Fixture.status(V0358Fixture.fresh),
                                  lap: MissionProgress(kind: .todayThreeHours, progress: 0.9, claimedToday: false,
                                                       cappedToday: false, detail: "다음 하나까지 18분"))
        #expect(try CheckRenderDiff(oldServer.cgImage!, emptyDaily.cgImage!)?.looksSame == true, "빈 일일 목록이 무언가를 그렸다")
        let lap = try #require(v0364DiffBox(oldServer, lapMoved, maxX: 330), "대조군 실패 — 3시간 줄이 안 그려졌다")
        let daily = try #require(v0364DiffBox(oldServer, withDaily, maxX: 330), "일일 줄이 미션 화면에 안 그려졌다")
        print("[v0364] 3시간 줄 y \(lap.minY)…\(lap.maxY) · 일일 차이 y \(daily.minY)…\(daily.maxY)")
        #expect(lap.minY > 40, "3시간 줄 위에 일일 머리 자리가 없다(\(lap.minY))")
        // 일일 줄을 더하면 갈리기 시작하는 곳: 머리의 "받을 보상 2개"(3시간 줄 위) — 그 아래 줄들은 3시간 줄 **아래**에서 갈린다.
        #expect(daily.minY < lap.minY, "일일 머리(받을 보상 N개)가 3시간 줄 위에 안 섰다")
        let belowLap = v0364GradientPixels(withDaily, x: 200...330, y: (lap.maxY + 4)...(lap.maxY + 80))
        #expect(belowLap > 1_000, "3시간 줄 바로 아래 첫 일일 줄(타이밍 바)의 [받기]가 안 보인다(\(belowLap))")
        #expect(v0364GradientPixels(oldServer, x: 200...330, y: (lap.maxY + 4)...(lap.maxY + 80)) < 100,
                "대조군 실패 — 일일이 없는데 3시간 줄 아래에 [받기]가 있다")
    }

    @Test("세 묶음 순서(통째로 펼친 스틸) — 일일 머리 → 3시간 → 일일 6줄 → 주간 머리 → 이번 주 → 누적 머리 → 누적 줄")
    func groupOrderInFullContent() throws {
        func full(_ daily: [V0364Fixture.Daily]? = V0364Fixture.base, achievements: [V0358Fixture.Row] = V0358Fixture.base,
                  weekly: WeeklyWorkStatus = V0358Fixture.weekly(), lap: MissionProgress = V0356Fixture.lap,
                  line: Int = #line) throws -> NSBitmapImageRep {
            let status = daily.map { V0364Fixture.status($0, achievements: achievements) } ?? V0358Fixture.status(achievements)
            return try v0364Bitmap(CheckMenuView(store: v0364RenderStore(achievements: status, missions: [lap], weekly: weekly, line: line),
                                                 previewFullMissionList: true))
        }
        let all = try full()
        // 줄 하나씩만 바꿔 그 줄의 자리를 잰다(본문 열 x < 330 — 레일 배지는 뺀다).
        let lap = try #require(v0364DiffBox(all, try full(lap: MissionProgress(kind: .todayThreeHours, progress: 0.9, claimedToday: false,
                                                                              cappedToday: false, detail: "다음 하나까지 18분")), maxX: 330))
        let flappy = try #require(v0364DiffBox(all, try full(V0364Fixture.with("daily_flappy", achieved: false, claimed: false)), maxX: 330))
        let weekly = try #require(v0364DiffBox(all, try full(weekly: V0358Fixture.weekly(V0358Fixture.weeklyClaimedJSON())), maxX: 330))
        let cumulative = try #require(v0364DiffBox(all, try full(achievements: V0358Fixture.fresh), maxX: 330))
        let noDaily = try full(nil)
        print("[v0364] 통째 — 창 \(CGFloat(all.pixelsHigh) / 2)pt · 3시간 y \(lap.minY) · 플래피(일일 둘째) y \(flappy.minY) · 이번 주 y \(weekly.minY) · 누적 y \(cumulative.minY)")
        #expect(lap.minY > 20, "3시간 줄 위에 일일 머리 자리가 없다")
        #expect(flappy.minY > lap.maxY + 64 - 4 && flappy.maxY < lap.maxY + 2 * 64 + 4, "일일 둘째 줄이 3시간 줄 아래 둘째 자리가 아니다")
        // 일일 둘째(플래피) 아래로 일일 넷(셋째~여섯째) + 주간 머리가 더 선 뒤에야 이번 주 줄이다. 실측(2026-10-22): 플래피 356.5 · 이번 주 696.5.
        #expect(weekly.minY > flappy.minY + 4 * 64 + 20, "이번 주 줄이 일일 6줄 · 주간 머리 아래가 아니다")
        #expect(cumulative.minY > weekly.maxY, "누적 절이 주간 묶음 아래가 아니다(누적 \(cumulative.minY) · 주간 \(weekly.maxY))")
        #expect(noDaily.pixelsHigh < all.pixelsHigh && CGFloat(all.pixelsHigh - noDaily.pixelsHigh) / 2 == 6 * 64,
                "일일 6줄의 높이가 6 × 64pt 가 아니다")
    }

    @Test("팝오버 높이 — 일일 · 주간 · 누적이 다 붙어도 스크롤 창은 v0.3.56 의 줄 상한 그대로(창이 안 자란다) · 일일 없는 서버와 같다 · 최악 ≤ 700pt · 첫 열기와 같다")
    func heightBudget() throws {
        let fiveRows = [V0356Fixture.lap] + (1...4).map(V0356Fixture.future)
        let capped = try Self.height(CheckMenuView(store: v0364RenderStore(missions: fiveRows + [V0356Fixture.future(5)])))
        let all = try Self.height(CheckMenuView(store: v0364RenderStore(achievements: V0364Fixture.status(), weekly: V0358Fixture.weekly())))
        let oldServer = try Self.height(CheckMenuView(store: v0364RenderStore(achievements: V0358Fixture.status(), weekly: V0358Fixture.weekly())))
        let loading = try Self.height(CheckMenuView(store: v0364RenderStore(weekly: V0358Fixture.weekly())))
        print("[v0364] 창 높이 — 세 묶음 \(all) · 일일 없는 서버 \(oldServer) · 불러오는 중 \(loading) · v0.3.56 상한 \(capped)pt")
        #expect(all == capped && oldServer == capped && loading == capped, "세 묶음 화면이 v0.3.56 상한(\(capped))과 다르다")
        for (banner, editing) in [(false, false), (true, false), (true, true), (false, true)] {
            let store = v0364RenderStore(achievements: V0364Fixture.status(), weekly: V0358Fixture.weekly(), notice: V0358Fixture.lapNotice)
            let clip = try Self.height(CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: editing,
                                                     previewUpdateBanner: banner, previewUpdateNotes: banner ? ["a", "b", "c", "d"] : []))
            let scroll = try Self.height(CheckMenuView(store: store, previewGoalEditing: editing,
                                                       previewUpdateBanner: banner, previewUpdateNotes: banner ? ["a", "b", "c", "d"] : []))
            print("[v0364] 최악(배너 \(banner) · 편집 \(editing)) = 클립 \(clip) · 스크롤 \(scroll)pt")
            #expect(clip <= 700 && scroll <= 700, "세 묶음 미션 화면 \(clip)/\(scroll)pt — 상한을 넘어 푸터가 잘린다")
            #expect(clip == scroll, "클립(스냅샷) 그림과 실제(스크롤) 높이가 갈렸다")
        }
    }

    @Test("빈 띠 없음 — 세 묶음 · 일일만(서버에 누적 줄 없음) · 서버에 없음(일일 머리 + 3시간)에서 본문 카드가 푸터 바로 위까지 닿는다")
    func noEmptyBand() throws {
        for (label, store) in [("세 묶음", v0364RenderStore(achievements: V0364Fixture.status(), weekly: V0358Fixture.weekly())),
                               ("일일만", v0364RenderStore(achievements: V0364Fixture.status(achievements: []))),
                               ("서버에 없음", v0364RenderStore(unavailable: true))] {
            let bitmap = try v0364Bitmap(CheckMenuView(store: store, previewClipsOverflowList: true))
            let runs = v0364CardRuns(bitmap)
            let gap = runs.count >= 2 ? runs[runs.count - 1].top - runs[runs.count - 2].bottom : -1
            print("[v0364] \(label): 창 \(CGFloat(bitmap.pixelsHigh) / 2)pt · 카드 \(runs.map { "\($0.top)…\($0.bottom)" }) · 푸터 위 틈 \(gap)pt")
            #expect(runs.count >= 3, "\(label): 카드 구간 \(runs.count)개")
            #expect(gap >= 9 && gap <= 12, "\(label): 본문 카드와 푸터 사이 \(gap)pt — 빈 띠")
        }
    }

    @Test("배선 — 미션 화면이 스토어의 일일 줄 · 일일 받기 · 떠 있음 · 실패를 그대로 받는다")
    func panelWiring() async throws {
        let (store, host) = v0364Store("wire")
        store.isMenuPresented = true
        store.toggleMissionPanel()
        await V0355WeeklyStoreTests.settle()
        store.applyAchievements(V0364Fixture.status(resetAt: V0364Fixture.t + 3_600_000))
        store.dailyMissionClaimsInFlight = ["daily_gomoku"]
        store.dailyMissionClaimFailedKeys = ["daily_timing_bar"]
        let panel = try V0356ReviewFixTests.panelNode("MissionPanel", in: store)
        let rows = try #require(v0364Child("dailyMissions", of: panel) as? [DailyMissionStatus.Mission], "미션 화면에 일일 줄이 안 넘어갔다")
        #expect(rows == store.dailyMissionRows && rows.count == 6)
        let context = try #require(v0364Child("claim", of: panel) as? MissionClaimContext)
        #expect(context.dailyInFlightKeys == ["daily_gomoku"] && context.dailyFailedKeys == ["daily_timing_bar"])
        store.dailyMissionClaimsInFlight = []
        context.claimDaily("daily_timing_bar")
        #expect(await V0354CoreStub.waitUntil { v0364Calls(host, "daily_mission_claim") == 1 }, "일일 [받기]가 일일 받기를 안 부른다")
        #expect(v0364Calls(host, "achievement_claim") == 0)
    }
}

// MARK: - F 상금 · 💎 · 버전

@Suite struct V0364ConstantsTests {
    @Test("미니게임 자정 상금 20·10·5 — 상수 · 창 안내 · 어제 1등 칩이 같은 숫자를 말한다(마이그레이션과의 짝은 V0351 이 잰다)")
    @MainActor
    func prizes() {
        #expect(CheckMiniGameWindowView.rubyPrizes == [20, 10, 5])
        #expect(CheckMiniGameWindowView.prizeCaption == "자정에 1·2·3등에게 루비 20·10·5")
        #expect(CheckMiniGameWindowView.awardedChip == "루비 +20 받음")
    }

    @Test("💎 0 — Sources/** 전부(맥 · CheckCore · CheckMobileKit · CheckMobileShared · 위젯, 주석 걷음)에 💎 가 한 글자도 없다 · 보상 문구도 루비 그림 + 숫자 · 신청 말풍선은 '루비 N'")
    @MainActor
    func noBlueDiamond() throws {
        // 명세 §2-3 추가 3: 맥만이 아니라 Sources 아래 모든 Swift(폰 · 코어가 다시 💎 를 들여와도 잡는다 — 검토 지적 2026-10-22:
        // 예전 뿌리는 Sources/check 하나라 CheckCore 에 심은 💎 뮤턴트가 살아남았다).
        let sources = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources", isDirectory: true)
        let modules = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
        #expect(Set(["check", "CheckCore", "CheckMobileKit", "CheckMobileShared"]).isSubset(of: Set(modules)),
                "Sources 아래 모듈을 못 찾았다(\(modules)) — 뿌리가 틀렸다")
        var scannedPerModule: [String: Int] = [:]
        var offenders: [String] = []
        for module in modules.sorted() {
            let root = sources.appendingPathComponent(module, isDirectory: true)
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                scannedPerModule[module, default: 0] += 1
                let code = V0317ShopTests.stripped(try String(contentsOf: file, encoding: .utf8))
                if code.contains("💎") { offenders.append("\(module)/\(file.lastPathComponent)") }
            }
        }
        let scanned = scannedPerModule.values.reduce(0, +)
        print("[v0364] 💎 검사 — 모듈별 Swift 파일 \(scannedPerModule.sorted { $0.key < $1.key })")
        // 폴더마다 적어도 한 파일(한 폴더가 비어 헛도는 것을 막는다) · 합은 오늘 실측(맥 78 · 코어 102 · 폰 149 · 공유 9 · 위젯 9)의 하한.
        for module in modules { #expect((scannedPerModule[module] ?? 0) >= 1, "\(module) 에서 Swift 를 하나도 못 읽었다 — 이 검사가 헛돈다") }
        #expect((scannedPerModule["check"] ?? 0) > 50 && (scannedPerModule["CheckCore"] ?? 0) > 50 && (scannedPerModule["CheckMobileKit"] ?? 0) > 100,
                "모듈별 Swift 수가 너무 적다: \(scannedPerModule)")
        #expect(scanned > 300, "Swift 소스를 \(scanned)개밖에 못 읽었다 — 이 검사가 헛돈다")
        #expect(offenders.isEmpty, "주석 밖 💎 가 남은 파일: \(offenders)")
        // 기준선: 걷어내기가 주석 안 💎 는 지우고 문자열 안 💎 는 남긴다(둘이 같게 나오면 이 검사는 영원히 초록이다).
        #expect(!V0317ShopTests.stripped("let a = 1 // 💎 +3").contains("💎"))
        #expect(V0317ShopTests.stripped(#"let a = "💎 +3""#).contains("💎"))
        // 문구 — 숫자만 말하고 루비는 그림이 말한다.
        #expect(MissionCopy.chip(V0356Fixture.lap) == .ruby(3))
        let mission = try #require(V0364Fixture.status().daily?.mission("daily_chess")?.row)
        #expect(AchievementCopy.reward(mission) == "+5")
        for (name, text) in [("오목", CheckOverlayController.gomokuInviteBubbleText(name: "민수", stake: 5)),
                             ("체스", CheckOverlayController.chessInviteBubbleText(name: "민수", stake: 5)),
                             ("테트리스", CheckOverlayController.tetrisInviteBubbleText(name: "민수", stake: 5))] {
            #expect(text.hasSuffix("루비 5") && !text.contains("💎") && text.contains(name), "\(name) 신청 말풍선: \(text)")
            #expect(OverlayMessageBubble.fitsCapsule(text), "\(name) 신청 말풍선이 두 줄 캡슐을 넘는다: \(text)")
        }
    }

    @Test("레일 [미션] 툴팁이 세 묶음 이름을 말한다")
    func railHelp() {
        #expect(MissionRailBadge.plainHelp == "미션 — 일일 · 주간 · 누적")
    }
}

// MARK: - 릴리스 게이트 (v0.3.64)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(0.3.60 → … → 0.3.63 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.64 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
@Test("버전 0.3.64 / 117 · CHANGELOG 0.3.64 는 맨 위 네 줄(사용자 말투 · 배너 폭 안)")
func v0364VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.64</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>117</string>"))

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.64\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 4, "항목 \(items)")
    // 배너는 한 줄씩 말줄임이다(본문 폭 316 − 글머리표 · 간격 ≈ 306pt, caption2). 실측 폭으로 잰다.
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0364] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    // 네 줄이 각자 **다른 변화**를 말하는지 — 한 줄이 조용히 빠지면 그 기능은 배너에도 릴리스 노트에도 안 뜬다.
    // "관전" 은 같은 판에 들어간 테트리스 관전·관전자 수 묶음의 증표다(0.3.64 로 합쳐 내면서 한 줄로 묶었다).
    #expect(section.contains("일일") && section.contains("20·10·5") && section.contains("수수료")
            && section.contains("관전"))
    #expect(changelog.range(of: "## 0.3.64")!.lowerBound < changelog.range(of: "## 0.3.63")!.lowerBound,
            "0.3.64 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

// MARK: - 미리보기(환경변수가 있을 때만 — 창은 띄우지 않는다)

@MainActor
@Suite(.serialized) struct V0364StillsTests {
    @Test("미리보기 PNG(CHECK_V0364_STILLS_DIR) — 미션 화면(스크롤 창 · 통째) · 일일 줄 세 상태 · 대결 결과 · 판돈 고르기, 어둡게/밝게")
    func stills() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_V0364_STILLS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func save(_ name: String, _ view: some View, scheme: ColorScheme) throws {
            let bitmap = try v0364Bitmap(view.environment(\.colorScheme, scheme))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
        let status = V0364Fixture.status()
        let weekly = V0358Fixture.weekly()
        for scheme in [ColorScheme.dark, .light] {
            let offset = scheme == .dark ? 0 : 1
            let panel = v0364RenderStore(achievements: status, weekly: weekly, notice: V0358Fixture.lapNotice, line: 900 + offset)
            try save("1-mission-panel-viewport", CheckMenuView(store: panel, previewClipsOverflowList: true), scheme: scheme)
            try save("2-mission-panel-full", CheckMenuView(store: panel, previewFullMissionList: true), scheme: scheme)
            let rows = try #require(status.daily?.missions)
            try save("3-daily-rows", VStack(spacing: 8) {
                ForEach(rows) { AchievementRowView(mission: $0.row, group: .daily(game: $0.game)) }
            }.frame(width: 292).padding(12).background(CheckTheme.panel), scheme: scheme)
            let oldServer = v0364RenderStore(achievements: V0358Fixture.status(), weekly: weekly, line: 910 + offset)
            try save("4-mission-panel-old-server", CheckMenuView(store: oldServer, previewFullMissionList: true), scheme: scheme)
            // 루비 대체 그림(에셋을 못 읽을 때) — 왼쪽부터 RubyIcon 대체 · 뽑기 rubyImage 대체 · 에셋. 바깥 강조색을 일부러 건다.
            try save("5-ruby-fallback", HStack(spacing: 10) {
                RubyIcon(size: 26, simulatesMissingAsset: true)
                CheckGachaWindowView.rubyImage(asset: nil).resizable().interpolation(.high).frame(width: 26, height: 26)
                RubyIcon(size: 26)
            }.foregroundStyle(CheckTheme.accent).padding(10).background(CheckTheme.panel), scheme: scheme)
        }
    }
}

// MARK: - G 서버 짝(마이그레이션을 읽는다 — `supabase/` 는 git 밖이라 워크트리엔 없을 수 있다: 조상을 훑고 `CHECK_MIGRATIONS_DIR` 로 덮는다)

private func v0364MigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue { return candidate }
        directory = directory.deletingLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

/// `--` 줄 주석을 걷어낸 원문.
private func v0364SQL(_ name: String) throws -> String {
    let raw = try String(contentsOf: try v0364MigrationsDirectory().appendingPathComponent(name), encoding: .utf8)
    return raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

@Suite struct V0364DailyMissionMigrationTests {
    static let file = "20261023130000_daily_missions.sql"

    @Test("서버 정의표(daily_mission_defs) = 이 시험의 픽스처 — 여섯 키 · 게임 · 제목 · 보상 5 · 목표 1 · 순서, 제목은 앱 이름으로 시작한다")
    @MainActor
    func defsMatchTheFixtureAndTheAppNames() throws {
        let sql = try v0364SQL(Self.file)
        let regex = try NSRegularExpression(pattern: #"\(\s*'(daily_[a-z_]+)'\s*,\s*'([a-z_]+)'\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*\)"#)
        let rows = regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)).map { match in
            (1..<match.numberOfRanges).map { String(sql[Range(match.range(at: $0), in: sql)!]) }
        }
        #expect(rows.count == 6, "정의표 줄을 \(rows.count)개 읽었다(기대 6 — 모양이 바뀌었으면 이 파서를 고쳐라)")
        #expect(rows.map { $0[0] } == V0364Fixture.base.map(\.key))
        #expect(rows.map { $0[1] } == V0364Fixture.base.map(\.game))
        #expect(rows.map { $0[2] } == V0364Fixture.base.map(\.title), "서버 제목과 픽스처 제목이 다르다: \(rows.map { $0[2] })")
        #expect(rows.allSatisfy { $0[3].isEmpty && $0[4] == "5" && $0[5] == "1" }, "detail · 보상 · 목표가 명세('' · 5 · 1)와 다르다")
        #expect(rows.map { Int($0[6]) ?? -1 } == [10, 20, 30, 40, 50, 60])
        let names: [String: String] = [
            "timing_bar": MiniGameKind.timingBar.title, "flappy": MiniGameKind.flappy.title, "tetris": MiniGameKind.tetris.title,
            "gomoku": MiniGameGomokuEntryButton.title, "chess": MiniGameChessEntryButton.title, "tetris_duel": MiniGameTetrisDuelEntryButton.title,
        ]
        for row in rows {
            #expect(row[2].hasPrefix((names[row[1]] ?? "?") + " "), "서버 제목 '\(row[2])' 가 앱 이름 '\(names[row[1]] ?? "?")' 로 시작하지 않는다")
            #expect(DailyMissionCopy.icon(game: row[1]) != AchievementCopy.fallbackIcon, "\(row[1]) 의 아이콘을 앱이 모른다")
        }
    }

    @Test("서버가 내는 daily 칸 이름 = 앱 디코더가 읽는 칸 이름 · 받기 함수는 p_key 하나(기본 null) · 상태 두 함수가 daily 를 싣는다")
    func wireKeysMatchTheDecoder() throws {
        let sql = try v0364SQL(Self.file)
        for key in ["'kst_day'", "'reset_at_ms'", "'missions'", "'claimable_count'", "'claimable_ruby'",
                    "'key'", "'game'", "'title'", "'detail'", "'reward'", "'target'", "'progress'", "'achieved'", "'claimed'",
                    "'claimed_at_ms'", "'sort'", "'daily'", "'claimed_now'"] {
            #expect(sql.contains(key), "서버 파일에 \(key) 칸이 없다 — 앱 디코더가 읽는 이름과 갈렸다")
        }
        // 디코더(스네이크 → 카멜)가 읽는 이름과 짝(코어 `DailyMissionStatus.CodingKeys`).
        #expect(Set(["kstDay", "resetAtMs", "missions", "claimableCount", "claimableRuby"])
                == Set([DailyMissionStatus.CodingKeys.kstDay, .resetAtMs, .missions, .claimableCount, .claimableRuby].map(\.stringValue)))
        let flat = sql.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(flat.contains("create or replace function public.daily_mission_claim(p_key text default null)"),
                "받기 함수 서명이 (p_key text default null) 가 아니다 — 앱은 본문에 p_key 하나를 언제나 싣는다")
        #expect(flat.contains("'daily', public.daily_missions__status(p_uid)"), "상태 응답에 daily 를 싣지 않는다")
    }
}

// MARK: - H 검토 지적 수리(2026-10-22)
//
//  ① 자정을 넘겨도 관찰 무효화가 없어 열린 화면에 어제 [받기] · 배지가 남고, 눌러도 요청 0건이었다 → 넘김을 관찰 값에 적는다
//     (깨우개 · 팝오버 다시 열기 · 막힌 [받기]) + 막힌 [받기]는 조회 1건.
//  ② 판 전에 떠난 조회에 게임 결과 조회가 합류해 달성이 다음 박자까지 안 보였다 → 그 조회가 끝난 뒤 정확히 한 번 더.
//  ③ 오늘 이미 채운 게임은 판마다 묻지 않는다(하루 첫 판만).
//  ④ 루비 대체 기호(에셋을 못 읽을 때)가 파란 강조색이었다 → 분홍으로 구운 그림.

/// 관찰 무효화가 일어났는가.
final class V0364ObservationFlag: @unchecked Sendable { var hit = false }

/// 일일 줄 · 레일 배지(화면이 읽는 두 값)의 관찰을 건다.
@MainActor
private func v0364Track(_ store: WorkTimerStore) -> V0364ObservationFlag {
    let flag = V0364ObservationFlag()
    withObservationTracking {
        _ = store.dailyMissionRows
        _ = store.missionClaimableCount
    } onChange: { flag.hit = true }
    return flag
}

/// 뷰 값 트리에서 타입 이름이 같은 첫 노드(클래스 · 클로저 안은 못 들어간다 — V0356 `v0356Collect` 와 같은 자).
private func v0364Find(_ name: String, in value: Any, budget: inout Int) -> Any? {
    guard budget > 0 else { return nil }
    budget -= 1
    let mirror = Mirror(reflecting: value)
    if String(describing: mirror.subjectType) == name { return value }
    guard mirror.displayStyle != .class else { return nil }
    for child in mirror.children {
        if let hit = v0364Find(name, in: child.value, budget: &budget) { return hit }
    }
    return nil
}

/// 강조색(파랑 84,171,255) 픽셀 — 예전 루비 대체 기호의 색.
private func v0364AccentPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0364Count(bitmap, x: x, y: y) { r, g, b in b > 200 && b - r > 100 && b - g > 40 }
}

@MainActor
@Suite(.serialized) struct V0364ReviewFixTests {
    /// 리셋 = 서버 t + 60초 · 서버 시각 t · 이 맥 시계 t0(시계가 틀린 맥). `next` 가 있으면 둘째 조회부터 그 응답(새 날).
    static func rolloverStore(_ label: String, clock: V0355Clock, next: String? = nil,
                              function: String = #function) -> (WorkTimerStore, String) {
        v0364Store(label, clock: clock, achievements: { index in
            if index > 0, let next { return .init(body: next) }
            return .init(body: V0364Fixture.json(daily: V0364Fixture.dailyObject(resetAt: V0364Fixture.t + 60_000)))
        }, function: function)
    }

    /// 새 날(2026-06-13)의 응답 — 여섯 줄 다 0/1 · 서버 시각 t + 61초 · 리셋은 그 다음 자정.
    static let nextDayJSON = V0364Fixture.json(daily: V0364Fixture.dailyObject(V0364Fixture.fresh, day: "2026-06-13",
                                                                              resetAt: V0364Fixture.t + 60_000 + 86_400_000),
                                               serverNow: V0364Fixture.t + 61_000)

    @Test("자정 ① — 리셋 전엔 적지 않는다(무효화 0) · 넘기면 한 번 적어 일일 줄 · 배지의 관찰이 무효화된다 · 두 번째는 0 · 적은 넘김은 시계가 뒤로 흔들려도 안 되돌아간다")
    func rolloverNoteInvalidates() async throws {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        let (store, _) = Self.rolloverStore("note", clock: clock)
        await store.refreshAchievements(reason: .missionPanel)?.value
        #expect(store.dailyMissionRows?.filter(\.row.isClaimable).count == 2 && store.missionClaimableCount == 4, "전제")
        clock.advance(59)
        let early = v0364Track(store)
        #expect(store.noteDailyMissionRollover() == false && !early.hit, "리셋 전인데 넘김을 적었다")
        clock.advance(2)
        let flag = v0364Track(store)
        #expect(store.noteDailyMissionRollover(), "리셋을 넘겼는데 안 적었다")
        #expect(flag.hit, "넘김을 적었는데 일일 줄 · 배지의 관찰이 무효화되지 않았다 — 열린 화면에 어제 [받기] · 배지가 남는다")
        #expect(store.dailyMissionRows?.allSatisfy { $0.row.state == .inProgress } == true && store.missionClaimableCount == 2)
        let again = v0364Track(store)
        #expect(store.noteDailyMissionRollover() == false && !again.hit, "같은 넘김을 또 적었다(헛무효화)")
        clock.advance(-30)
        #expect(store.dailyMissionRows?.allSatisfy { $0.row.state == .inProgress } == true && store.missionClaimableCount == 2,
                "적은 넘김이 시계가 뒤로 흔들리자 어제 [받기]를 되살렸다")
    }

    @Test("자정 ① — 깨우는 시각 = 리셋 − 시계 차(이 맥 시계) · 그 1ms 전엔 안 넘고 그 순간 넘는다 · 적으면 일정이 사라진다 · 깨우개 일정은 리셋 · +1초 · +5초")
    func rolloverWakeDate() async throws {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        let (store, _) = Self.rolloverStore("wake-date", clock: clock)
        #expect(store.dailyMissionRolloverDate == nil, "모르는데 깨울 시각이 있다")
        await store.refreshAchievements(reason: .missionPanel)?.value
        let date = try #require(store.dailyMissionRolloverDate)
        // 서버 시각 t 를 이 맥 시계 t0 에 받았으니 리셋(t + 60초)은 이 맥 시계로 t0 + 60초다.
        #expect(abs(date.timeIntervalSince(V0355WeeklyStoreTests.t0) - 60) < 0.002, "깨울 시각이 틀렸다: \(date)")
        clock.now = date.addingTimeInterval(-0.002)
        #expect(store.noteDailyMissionRollover() == false, "깨울 시각 전인데 넘었다")
        clock.now = date
        #expect(store.noteDailyMissionRollover(), "깨울 시각에 안 넘었다 — 깨우개가 헛깬다")
        #expect(store.dailyMissionRolloverDate == nil, "적었는데 깨울 시각이 남았다(헛깸)")
        #expect(DailyMissionRolloverWake.wakeDates(rollover: nil).isEmpty)
        #expect(DailyMissionRolloverWake.wakeDates(rollover: date) == [date, date.addingTimeInterval(1), date.addingTimeInterval(5)])
    }

    @Test("자정 ① — 깨우개가 레일 [미션] 칸 뒤에 이 스토어로 붙어 있다 · 레일은 팝오버에 있다")
    func wakeIsWiredIntoTheRail() throws {
        let (store, _) = v0364Store("wake-wire")
        var budget = 200_000
        let wake = try #require(v0364Find("DailyMissionRolloverWake", in: CheckMenuSideRail(store: store).body, budget: &budget),
                                "레일에 깨우개가 없다 — 열린 화면이 자정을 모른다")
        #expect((v0364Child("store", of: wake) as? WorkTimerStore) === store)
        budget = 400_000
        #expect(v0364Find("CheckMenuSideRail", in: CheckMenuView(store: store).body, budget: &budget) != nil, "팝오버에 레일이 없다")
    }

    @Test("자정 ① — 닫힌 동안 자정을 넘기고 팝오버를 다시 열면 넘김을 적는다(요청 0건)")
    func reopenNotesRollover() async throws {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        let (store, host) = Self.rolloverStore("reopen", clock: clock)
        await store.refreshAchievements(reason: .missionPanel)?.value
        let before = v0364Calls(host)
        clock.advance(61)
        let flag = v0364Track(store)
        store.setMenuPresented(true)
        #expect(store.dailyMissionRolloverNoted == V0364Fixture.t + 60_000, "다시 열었는데 넘김을 안 적었다")
        #expect(flag.hit, "다시 연 화면의 일일 줄 · 배지가 다시 그려지지 않는다")
        await V0355WeeklyStoreTests.settle()
        #expect(v0364Calls(host) == before, "다시 열기가 도전 미션을 물었다(미션 화면이 안 떠 있다)")
    }

    @Test("자정 ① — 화면에 남은 [받기]를 눌렀는데 리셋을 넘겼다 → 받기 0건 · 조회 1건 · 그 자리에서 무효화 · 새 날 응답이 오면 새 날 줄")
    func blockedClaimRefreshes() async throws {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        let (store, host) = Self.rolloverStore("blocked", clock: clock, next: Self.nextDayJSON)
        await store.refreshAchievements(reason: .missionPanel)?.value
        let before = v0364Calls(host)
        clock.advance(61)
        let flag = v0364Track(store)
        #expect(store.claimDailyMission(key: "daily_timing_bar") == nil, "어제 줄의 받기가 나갔다")
        #expect(flag.hit, "눌렀는데 무효화 0 — 버튼이 계속 선다")
        #expect(await V0354CoreStub.waitUntil { v0364Calls(host) == before + 1 && store.achievementsFetchTask == nil },
                "막힌 [받기]가 새 날을 묻지 않았다(\(v0364Calls(host) - before)회) — 반응 없는 버튼")
        #expect(v0364Calls(host, "daily_mission_claim") == 0)
        #expect(store.achievements?.daily?.kstDay == "2026-06-13")
        #expect(store.dailyMissionRows?.allSatisfy { $0.row.state == .inProgress } == true && store.missionClaimableCount == 2)
        // 받을 수 없던 줄(진행 중 · 이미 받음)을 누른 것은 날짜 넘김이 아니다 — 묻지 않는다.
        let settled = v0364Calls(host)
        #expect(store.claimDailyMission(key: "daily_chess") == nil && store.claimDailyMission(key: nil) == nil)
        await V0355WeeklyStoreTests.settle()
        #expect(v0364Calls(host) == settled, "받을 것이 없는 새 날에 [받기] 갈래가 조회를 냈다")
    }

    @Test("겹침 ② — 판 전에 떠난 조회가 떠 있으면 그 조회가 끝난 뒤 정확히 한 번 더 묻는다(판이 둘 끝나도 +1건) · 달성이 바로 보인다")
    func gameResultRefetchesAfterInFlight() async throws {
        let (store, host) = v0364Store("refetch", achievements: { index in
            let rows = index == 0 ? V0364Fixture.with("daily_timing_bar", achieved: false) : V0364Fixture.base
            return .init(body: V0364Fixture.json(daily: V0364Fixture.dailyObject(rows, resetAt: V0364Fixture.resetFar)), delay: 0.5)
        }, extra: { rpc, _, _ in
            switch rpc {
            case "minigame_submit_score": return .init(body: #"{"status":"ok","best_score":3,"plays":1,"improved":true}"#)
            case "minigame_start_round": return .init(body: #"{"status":"ok","token":"tok-next"}"#)
            default: return nil
            }
        })
        let periodic = store.refreshAchievements(reason: .periodic)
        #expect(periodic != nil, "전제: 5분 박자 조회가 떠났다")
        for round in 0..<2 {
            let entry = MiniGamePendingSubmit(id: UUID(), kind: .timingBar, score: 3 + round, token: "tok-\(round)",
                                              tokenIssuedAt: V0355WeeklyStoreTests.t0, recordedAt: V0355WeeklyStoreTests.t0, attempts: 0)
            await store.performSubmitMiniGameScore(entry: entry)
        }
        #expect(v0364Calls(host, "minigame_submit_score") == 2, "전제: 제출 둘 다 성공")
        #expect(v0364Calls(host) == 1, "떠 있는 조회가 있는데 또 발사했다(겹침)")
        await periodic?.value
        #expect(await V0354CoreStub.waitUntil { v0364Calls(host) == 2 && store.achievementsFetchTask == nil },
                "판 전 조회에 합류만 하고 다시 안 물었다(\(v0364Calls(host))회)")
        await V0355WeeklyStoreTests.settle()
        #expect(v0364Calls(host) == 2, "뒤따르는 조회가 한 번이 아니다(\(v0364Calls(host))회)")
        #expect(store.achievements?.daily?.mission("daily_timing_bar")?.row.state == .claimable, "서버는 달성인데 줄이 미달성으로 남았다")
        #expect(store.achievementsRefetchAfterInFlight == false)
        // 지갑 박자끼리 겹친 것은 예전처럼 같이 기다린다(깃발 없음 — 뒤따르는 조회 0).
        let a = store.refreshAchievements(reason: .periodic)
        #expect(a != nil && store.refreshAchievements(reason: .missionPanel) == nil)
        await a?.value
        await V0355WeeklyStoreTests.settle()
        #expect(v0364Calls(host) == 3, "게임 결과가 아닌 겹침에 뒤따르는 조회가 붙었다")
    }

    @Test("하루 첫 판 ③ — 오늘 그 게임 줄을 채웠으면(받음 · 받기 대기) 판마다 묻지 않는다 · 다른 게임 · 모름 · 하루가 넘어간 줄은 묻는다")
    func gameResultSkipsAchievedToday() async throws {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        let (store, host) = v0364Store("first-round", clock: clock, achievements: { _ in
            .init(body: V0364Fixture.json(daily: V0364Fixture.dailyObject(V0364Fixture.with("daily_timing_bar", claimed: true),
                                                                          resetAt: V0364Fixture.t + 3_600_000)))
        }, extra: { rpc, _, _ in
            switch rpc {
            case "minigame_submit_score": return .init(body: #"{"status":"ok","best_score":3,"plays":1,"improved":true}"#)
            case "minigame_start_round": return .init(body: #"{"status":"ok","token":"tok-next"}"#)
            default: return nil
            }
        })
        func play(_ kind: MiniGameKind, _ round: Int) async {
            let entry = MiniGamePendingSubmit(id: UUID(), kind: kind, score: 3 + round, token: "tok-\(kind.rawValue)-\(round)",
                                              tokenIssuedAt: V0355WeeklyStoreTests.t0, recordedAt: V0355WeeklyStoreTests.t0, attempts: 0)
            await store.performSubmitMiniGameScore(entry: entry)
            _ = await V0354CoreStub.waitUntil { store.achievementsFetchTask == nil }
        }
        await store.refreshAchievements(reason: .missionPanel)?.value
        // 타이밍 바 = 받음 · 플래피 = 받음 · 오목 = 받기 대기(채움) · 테트리스 · 체스 = 0/1.
        var before = v0364Calls(host)
        for round in 0..<5 { await play(.timingBar, round) }
        await play(.flappy, 0)
        #expect(v0364Calls(host, "minigame_submit_score") == 6)
        #expect(v0364Calls(host) == before, "이미 채운 게임인데 판마다 물었다(\(v0364Calls(host) - before)회)")
        #expect(store.refreshAchievementsAfterGameResult(game: "gomoku") == nil, "받기 대기(채움)인 오목에 또 물었다")
        await V0355WeeklyStoreTests.settle()
        #expect(v0364Calls(host) == before)
        await play(.tetris, 0)
        #expect(v0364Calls(host) == before + 1, "아직 안 채운 테트리스를 안 물었다")
        #expect(store.refreshAchievementsAfterGameResult(game: "chess") != nil, "아직 안 채운 체스를 안 물었다")
        _ = await V0354CoreStub.waitUntil { store.achievementsFetchTask == nil }
        // 하루가 넘어간 응답의 '채움'은 어제 것이다 — 오늘 첫 판은 묻는다.
        clock.advance(3_700)
        before = v0364Calls(host)
        await play(.timingBar, 9)
        #expect(v0364Calls(host) == before + 1, "날이 바뀌었는데 어제 채움을 믿고 안 물었다")
    }

    @Test("루비 ④ — 에셋을 못 읽어도 분홍(바깥 강조색이 못 덮는다) · 뽑기 창 그림도 같다 · 옛 대체 기호는 파랬다(기준선) · 에셋 갈래도 분홍")
    func rubyFallbackIsPink() throws {
        let box: ClosedRange<CGFloat> = 0...34
        func render(_ view: some View) throws -> NSBitmapImageRep {
            try v0364Bitmap(view.padding(4).background(Color.black).environment(\.colorScheme, .dark))
        }
        #expect(RubyAsset.fallbackImage != nil, "대체 그림을 못 구웠다")
        let icon = try render(RubyIcon(size: 26, simulatesMissingAsset: true).foregroundStyle(CheckTheme.accent))
        let gacha = try render(CheckGachaWindowView.rubyImage(asset: nil).resizable().interpolation(.high)
            .frame(width: 26, height: 26).foregroundStyle(CheckTheme.accent))
        let asset = try render(RubyIcon(size: 26).foregroundStyle(CheckTheme.accent))
        // 기준선 — 예전 대체 갈래 그대로(강조색 기호). 이 자가 파랑을 잡고 분홍을 안 잡아야 위 단언이 뜻이 있다.
        let old = try render(Image(systemName: "diamond.fill").font(.system(size: 26 * 0.8, weight: .bold))
            .foregroundStyle(CheckTheme.accent).frame(width: 26, height: 26))
        let counts = [("RubyIcon 대체", icon), ("뽑기 rubyImage 대체", gacha), ("RubyIcon 에셋", asset), ("옛 대체(기준선)", old)].map {
            ($0.0, v0364PinkPixels($0.1, x: box, y: box), v0364AccentPixels($0.1, x: box, y: box))
        }
        print("[v0364] 루비 대체 그림 — (이름, 분홍, 파랑) \(counts)")
        #expect(counts[3].1 == 0 && counts[3].2 > 300, "기준선이 파란 기호를 못 잡는다 — 이 자는 헛잰다: \(counts[3])")
        for (name, pink, blue) in counts.prefix(3) {
            #expect(pink > 300, "\(name): 분홍이 \(pink)px 뿐이다")
            #expect(blue == 0, "\(name): 파란 픽셀 \(blue)px — 바깥 강조색이 루비를 덮었다")
        }
    }
}
