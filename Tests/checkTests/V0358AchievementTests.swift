import AppKit
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.58 — 도전 미션(일회성 업적) + **받기 버튼**(주간 근무 단계도 받기로) · 맥 쪽.
//
// 사장님 확정(2026-10-19 — 값은 최종): 폰 로그인 50 · 할 일 3개 20 · 오목 10 · 체스 10 · 미니게임 3종 10 · 팀 2명 50 / 3명 200 ·
// 콕 10회 5 / 50회 20 / 100회 50 · 울트라 5회 50 · 연속 근무 14일 30 / 30일 200. 남용 방지 조건 없음("빼기").
// 같은 날 받기로 바꿨다(원문): "미션에서 바로 받는게 아니라. 달성하면 받는 버튼이 생기고 그거 누르면 받아지게끔 해줘. 그래야 루비를
// 받는 재미가 더 올라갈거 같아. 기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고. 3시간마다 루비 3개씩 주는것만 따로
// 버튼 없이 자동으로 지급되는걸로 냅두면 돼"
//
// 여기서 잰다:
//  ① 전선 — 계약 응답 13개 · 칸이 빠지거나 틀려도 안 죽음 · 모르는 키도 그림 · 받기 본문(키를 언제나 싣는다) · 주간 새 칸 / 옛 칸.
//  ② 계열 접기 — [받기]가 있는 가장 낮은 단계 → 안 받은 가장 낮은 단계 → 다 받았으면 가장 높은 단계 · 순서는 sort · 받음은 안 되돌아간다.
//  ③ 받기 — 성공이 상태 · 잔량 · 연출 · 말풍선을 옮긴다 · 같은 키 두 번 = 요청 1건 · 넣은 것이 없으면 조용 · 실패는 안내줄 + 버튼 남음 ·
//     받기 전에 떠난 조회는 버린다 · 늦은 응답은 잔량을 못 내린다 · 주간 받기(옛 서버엔 없음 · 자동 지급 알림이 다시 안 뜸).
//  ④ 배지 — 받을 도전 미션 수 + 받을 주간 단계 수 · 레일 칸이 그 수를 그린다.
//  ⑤ 박자 — 미션 화면 열기 · [다시 시도] · 연 채 재오픈 · 5분 주기 sync 에만 얹힌다 · 새 타이머가 없다.
//  ⑥ 404 / PGRST202 → 절을 조용히 감춘다 · 5xx 는 실패.
//  ⑦ 움직임 — 1초 미만 · 불투명도는 위치가 거의 다 온 뒤에야 깎인다 · 동작 줄이기는 제자리 페이드 · 애니메이션 nil.
//  ⑧ 그림 — 줄(받기 · ✓ 받음 · 진행 숫자) · 주간 받기(옛 서버면 없음) · 절 높이 · 팝오버 높이 예산(≤ 700pt · 빈 띠 없음).
// 실네트워크 없음(호스트별 스텁) · 창 없음(ImageRenderer 만 — 화면에 아무것도 안 뜬다).

// MARK: - 픽스처

enum V0358Fixture {
    struct Row {
        var key: String
        var series: String
        var tier: Int
        var title: String
        var detail: String = ""
        var reward: Int
        var target: Int
        var progress: Int
        var achieved: Bool
        var claimed: Bool
        var sort: Int
    }

    static let t = 1_781_234_567_890

    /// 계약 표 13개(설계서 표 그대로의 값) — 섞인 상태(스틸 · 기본 단언용):
    /// 폰 로그인 **받기** · 할 일 받음 · 오목 0/1 · 체스 0/1 · 미니게임 2/3 · 팀 2 받음 + 팀 3 **받기** · 콕 10 받음 · 콕 23/50 ·
    /// 울트라 1/5 · 연속 9/14. 받을 것 = 폰 50 + 팀 3 200 = 2개 · 250.
    static let base: [Row] = [
        Row(key: "phone_login", series: "phone_login", tier: 1, title: "폰 앱에서 로그인하기", detail: "아이폰 앱에 같은 계정으로 로그인",
            reward: 50, target: 1, progress: 1, achieved: true, claimed: false, sort: 10),
        Row(key: "todo3", series: "todo", tier: 1, title: "할 일 3개 이상 등록하기", reward: 20, target: 3, progress: 3,
            achieved: true, claimed: true, sort: 20),
        Row(key: "gomoku1", series: "gomoku", tier: 1, title: "오목 한 판 두기", reward: 10, target: 1, progress: 0,
            achieved: false, claimed: false, sort: 30),
        Row(key: "chess1", series: "chess", tier: 1, title: "체스 한 판 두기", reward: 10, target: 1, progress: 0,
            achieved: false, claimed: false, sort: 40),
        Row(key: "minigame3", series: "minigame", tier: 1, title: "미니게임 3종 한 판씩 해보기", detail: "타이밍 바 · 플래피 아잉 · 테트리스",
            reward: 10, target: 3, progress: 2, achieved: false, claimed: false, sort: 50),
        Row(key: "team2", series: "team", tier: 1, title: "팀 2명 채우기", reward: 50, target: 2, progress: 2,
            achieved: true, claimed: true, sort: 60),
        Row(key: "team3", series: "team", tier: 2, title: "팀 3명 채우기", reward: 200, target: 3, progress: 3,
            achieved: true, claimed: false, sort: 61),
        Row(key: "poke10", series: "poke", tier: 1, title: "콕 찌르기 10회", reward: 5, target: 10, progress: 10,
            achieved: true, claimed: true, sort: 69),
        Row(key: "poke50", series: "poke", tier: 2, title: "콕 찌르기 50회", reward: 20, target: 50, progress: 23,
            achieved: false, claimed: false, sort: 70),
        Row(key: "poke100", series: "poke", tier: 3, title: "콕 찌르기 100회", reward: 50, target: 100, progress: 23,
            achieved: false, claimed: false, sort: 71),
        Row(key: "ultra5", series: "ultra", tier: 1, title: "울트라 찌르기 5회", reward: 50, target: 5, progress: 1,
            achieved: false, claimed: false, sort: 80),
        Row(key: "streak14", series: "streak", tier: 1, title: "14일 연속 근무", reward: 30, target: 14, progress: 9,
            achieved: false, claimed: false, sort: 90),
        Row(key: "streak30", series: "streak", tier: 2, title: "30일 연속 근무", reward: 200, target: 30, progress: 9,
            achieved: false, claimed: false, sort: 91),
    ]

    /// 아무것도 안 채운 사람(진행 0).
    static var fresh: [Row] {
        base.map { var r = $0; r.progress = 0; r.achieved = false; r.claimed = false; return r }
    }

    /// 키 하나를 바꾼 표(기본 표에서).
    static func with(_ key: String, progress: Int? = nil, achieved: Bool? = nil, claimed: Bool? = nil) -> [Row] {
        with(base, key, progress: progress, achieved: achieved, claimed: claimed)
    }

    /// 키 하나를 바꾼 표.
    static func with(_ rows: [Row], _ key: String, progress: Int? = nil, achieved: Bool? = nil, claimed: Bool? = nil) -> [Row] {
        rows.map { row in
            guard row.key == key else { return row }
            var r = row
            if let achieved { r.achieved = achieved }
            if let claimed { r.claimed = claimed; if claimed { r.achieved = true } }
            if let progress { r.progress = progress } else if r.achieved { r.progress = r.target }
            return r
        }
    }

    /// 계약 모양 그대로의 응답(스네이크 키). `claimedNow` 는 받기 응답에만.
    static func json(_ rows: [Row] = base, claimedNow: [(key: String, title: String, reward: Int)] = [],
                     ruby: Int? = 1234, serverNow: Int = t) -> String {
        let claimable = rows.filter { $0.achieved && !$0.claimed }
        var root: [String: Any] = [
            "launch_at_ms": t - 3_600_000,
            "missions": rows.map { r -> [String: Any] in
                ["key": r.key, "series": r.series, "tier": r.tier, "title": r.title, "detail": r.detail, "reward": r.reward,
                 "target": r.target, "progress": r.progress, "achieved": r.achieved, "claimed": r.claimed,
                 "achieved_at_ms": r.achieved ? (t - 60_000) as Any : NSNull() as Any,
                 "claimed_at_ms": r.claimed ? t as Any : NSNull() as Any, "sort": r.sort]
            },
            "claimable_count": claimable.count,
            "claimable_ruby": claimable.reduce(0) { $0 + $1.reward },
            "server_now_ms": serverNow,
        ]
        if !claimedNow.isEmpty {
            root["claimed_now"] = claimedNow.map { ["key": $0.key, "title": $0.title, "reward": $0.reward] }
        }
        if let ruby { root["ruby_balance"] = ruby }
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// 받기 응답 — `key` 를 받은 뒤의 표 + `claimed_now`(그 키 한 건).
    static func claimJSON(_ rows: [Row] = base, key: String, ruby: Int?) -> String {
        let after = with(rows, key, claimed: true)
        let row = rows.first { $0.key == key }!
        return json(after, claimedNow: [(key, row.title, row.reward)], ruby: ruby)
    }

    /// 서비스와 같은 디코더(스네이크 → 카멜).
    static func decode(_ json: String) throws -> AchievementStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AchievementStatus.self, from: Data(json.utf8))
    }

    static func status(_ rows: [Row] = base, claimedNow: [(key: String, title: String, reward: Int)] = [],
                       ruby: Int? = 1234) -> AchievementStatus {
        try! decode(json(rows, claimedNow: claimedNow, ruby: ruby))
    }

    /// 함수가 없는 서버(PostgREST 404 · PGRST202 — 실제 모양).
    static let missingFunctionBody =
        #"{"code":"PGRST202","details":"Searched for the function public.achievements_status without parameters or with a single unnamed json/jsonb parameter, but no matches were found in the schema cache.","hint":null,"message":"Could not find the function public.achievements_status without parameters in the schema cache"}"#

    // ── 주간(받기 서버) ──

    /// 받기 서버의 주간 응답. 기본값 = 45시간 · 20 · 40 채움(안 받음) · 받을 것 70(스틸의 "받기 +70").
    static func weeklyJSON(worked: Int = 45 * 3_600,
                           tiers: [(hours: Int, ruby: Int, claimed: Bool, achieved: Bool)] =
                               [(20, 20, false, true), (40, 50, false, true), (60, 200, false, false)],
                           pending: [(week: String, hours: Int, ruby: Int)]? = [("2026-10-12", 20, 20), ("2026-10-12", 40, 50)],
                           claimableRuby: Int?? = .some(nil),
                           claimedNow: [(week: String, hours: Int, ruby: Int)] = [],
                           ruby: Int? = 1057) -> String {
        var root: [String: Any] = [
            "week_start": "2026-10-12", "next_week_start": "2026-10-19", "worked_seconds": worked,
            "tiers": tiers.map { ["hours": $0.hours, "ruby": $0.ruby, "claimed": $0.claimed, "achieved": $0.achieved,
                                  "claimable": $0.achieved && !$0.claimed] },
            "granted_now": [] as [Any], "server_now_ms": t,
        ]
        if let pending {
            root["pending"] = pending.map { ["week_start": $0.week, "hours": $0.hours, "ruby": $0.ruby] }
            // 합은 기본값이면 pending 에서 센다(.some(nil)) · 명시하면 그 값 · .none 이면 칸을 뺀다.
            switch claimableRuby {
            case .some(.some(let value)): root["claimable_ruby"] = value
            case .some(.none): root["claimable_ruby"] = pending.reduce(0) { $0 + $1.ruby }
            case .none: break
            }
        }
        if !claimedNow.isEmpty {
            root["claimed_now"] = claimedNow.map { ["week_start": $0.week, "hours": $0.hours, "ruby": $0.ruby] }
        }
        if let ruby { root["ruby_balance"] = ruby }
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func weekly(_ json: String = weeklyJSON()) -> WeeklyWorkStatus {
        try! V0355WeeklyStub.decode(json)
    }

    /// 받은 뒤의 주간 응답(20 · 40 받음 · 받을 것 없음).
    static func weeklyClaimedJSON(ruby: Int? = 1127) -> String {
        weeklyJSON(tiers: [(20, 20, true, true), (40, 50, true, true), (60, 200, false, false)], pending: [],
                   claimedNow: [("2026-10-12", 20, 20), ("2026-10-12", 40, 50)], ruby: ruby)
    }

    /// 3시간 랩 안내줄(받기와 무관한 안내 — 높이 예산 셈에 쓴다). 받기 실패는 v0.3.58 검토 뒤 안내줄이 아니다.
    static let lapNotice = "3시간 채웠어요 — 루비 +3"

    /// 상점 조회 응답(`shop_state` — V0355 잔량 경합 스텁과 같은 모양).
    static func shopJSON(ruby: Int) -> String {
        #"{"ruby_balance":"# + "\(ruby)" + #","ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":[]}"#
    }
}

// MARK: - 공용 도우미

private func v0358Code(_ name: String) throws -> String {
    V0317ShopTests.stripped(try V0317ShopTests.source(name))
}

private enum V0358Error: Error { case renderFailed }

@MainActor
private func v0358Bitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw V0358Error.renderFailed }
    return bitmap
}

@MainActor
private func v0358PNG(_ view: some View) throws -> Data {
    try #require(try v0358Bitmap(view).representation(using: .png, properties: [:]))
}

private func v0358Diff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) throws -> CheckRenderDiff {
    let ca = try #require(a.cgImage), cb = try #require(b.cgImage)
    return try #require(CheckRenderDiff(ca, cb), "두 그림을 견줄 판을 못 만들었다")
}

/// 근무색(초록 `CheckTheme.working` ≈ 89,224,161) 픽셀 수 — 강조색(파랑) · 회색 글자와 갈린다. 영역은 pt.
private func v0358GreenPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0358Count(bitmap, x: x, y: y) { r, g, b in g > 120 && g - r > 60 && g - b > 25 }
}

/// 받기 버튼의 흰 글자 픽셀 수(세 채널 모두 밝다) — 줄의 다른 글자는 회색(0.68)·흰(0.94)이라 **바탕이 그라데이션인 자리**에서만 센다.
private func v0358WhitePixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0358Count(bitmap, x: x, y: y) { r, g, b in r > 225 && g > 225 && b > 225 }
}

/// 주황(`CheckTheme.pending` ≈ 255,184,84 — 받기 실패 문장) 픽셀 수. 근무색 · 강조색 · 흰 · 회색 글자와 갈린다.
private func v0358AmberPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0358Count(bitmap, x: x, y: y) { r, g, b in r > 170 && r - b > 70 && g > 100 && r - g > 25 }
}

/// 그라데이션 캡슐(`gaugeGradient` — 근무색 → 강조색)의 **가운데 섞인 색** 픽셀 수. 양 끝 색 자체는 줄의 다른 것(근무색 바 · ✓ 받음 ·
/// 강조색 바)도 쓰므로 세지 않는다 — 초록:파랑 비가 0.8~1.15 인 밝은 픽셀은 두 색이 섞인 그라데이션 가운데뿐이다(근무색 1.39 · 강조색 0.67).
private func v0358GradientPixels(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Int {
    v0358Count(bitmap, x: x, y: y) { r, g, b in
        guard r > 60, r < 120, g > 150, b > 0 else { return false }
        let ratio = Double(g) / Double(b)
        return ratio >= 0.8 && ratio <= 1.15
    }
}

private func v0358Count(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
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

/// 본문 열 왼쪽 안쪽 세로 한 줄을 위→아래로 훑어 카드 구간(pt)을 낸다(V0356 `v0356CardRuns` 와 같은 자).
private func v0358CardRuns(_ bitmap: NSBitmapImageRep) -> [(top: CGFloat, bottom: CGFloat)] {
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

/// 두 그림이 갈리는 픽셀의 경계(pt, 채널 차 > 8 만 센다 — 디더 Δ≤2 를 차이로 세지 않는다). 같으면 nil. 크기가 다르면 전체.
private func v0358DiffBox(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, maxX limitX: CGFloat = .infinity) -> CGRect? {
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
    return CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                  width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
}

/// 뷰 값 트리(Mirror)에서 이름이 `names` 에 든 노드를 순서대로 모은다(V0356 `v0356Collect` 와 같은 자 — 클래스로는 안 내려간다).
private func v0358Collect(_ names: Set<String>, in value: Any, into out: inout [(name: String, value: Any)], budget: inout Int) {
    guard budget > 0 else { return }
    budget -= 1
    let mirror = Mirror(reflecting: value)
    let typeName = String(describing: mirror.subjectType)
    if names.contains(typeName) { out.append((typeName, value)); return }
    guard mirror.displayStyle != .class else { return }
    for child in mirror.children { v0358Collect(names, in: child.value, into: &out, budget: &budget) }
}

private func v0358Child(_ label: String, of value: Any) -> Any? {
    Mirror(reflecting: value).children.first { $0.label == label }?.value
}

/// 렌더용 메인 화면 스토어(V0356 `v0356RenderStore` 와 같은 두 겹 — 활성화 빠른 길 + 답하지 않는 스텁). 네트워크가 이 맥 밖으로 안 나간다.
@MainActor
private func v0358RenderStore(achievements: AchievementStatus? = nil,
                              unavailable: Bool = false,
                              failed: Bool = false,
                              missions: [MissionProgress] = [V0356Fixture.lap],
                              weekly: WeeklyWorkStatus? = nil,
                              notice: String? = nil,
                              ruby: Int? = 1234,
                              mission: Bool = true,
                              claimsFail: Bool = false,
                              function: String = #function, line: Int = #line) -> WorkTimerStore {
    let tag = "v0358-render-L\(line)"
    let home = CheckTestScratch.directory("token-\(tag)", function: function)
    let tokens = TokenUsageStore(
        defaults: CheckTestScratch.defaults("token-\(tag)", function: function),
        homeDirectory: home.appendingPathComponent("home", isDirectory: true),
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
    )
    let host = "v0358-silent-\(UUID().uuidString.prefix(8))".lowercased()
    // `claimsFail` — 받기 둘(도전 미션 · 주간)만 곧바로 500 으로 답한다(실패한 받기를 **스토어 길 그대로** 그리려고). 나머지는 답하지 않는다.
    GomokuStubProtocol.register(host: host) { rpc, _, _ in
        if claimsFail, rpc == "achievement_claim" || rpc == "weekly_work_claim" {
            return .init(status: 500, body: #"{"message":"boom"}"#)
        }
        return .init(body: "[]", delay: 600)
    }
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
    store.achievementsFailed = failed
    store.isMissionPanelVisible = mission
    return store
}

/// 스텁 호스트에 붙은 스토어(세션 · 팀 · 고정 시계 — V0355 스토어). rpc 마다 응답을 고른다(호출 순번 0부터).
@MainActor
private func v0358Store(_ label: String,
                        clock: V0355Clock = V0355Clock(V0355WeeklyStoreTests.t0),
                        achievements: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(body: V0358Fixture.json()) },
                        claim: @escaping @Sendable (String, Int) -> GomokuStubProtocol.Reply = { body, _ in
                            let key = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_key"] as? String
                            return .init(body: V0358Fixture.claimJSON(key: key ?? "phone_login", ruby: 1284))
                        },
                        weekly: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(body: V0358Fixture.weeklyJSON()) },
                        weeklyClaim: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in
                            .init(body: V0358Fixture.weeklyClaimedJSON())
                        },
                        shop: (@Sendable (Int) -> GomokuStubProtocol.Reply)? = nil,
                        function: String = #function) -> (WorkTimerStore, String) {
    let host = V0355WeeklyStoreTests.host("v0358-\(label)")
    GomokuStubProtocol.register(host: host) { rpc, body, index in
        switch rpc {
        case "achievements_status": return achievements(index)
        case "achievement_claim": return claim(body, index)
        case "weekly_work_status": return weekly(index)
        case "weekly_work_claim": return weeklyClaim(index)
        case "ultra_wallet_sync": return .init(body: V0356Fixture.walletJSON(streak: 2))
        case "shop_state": return shop?(index)
        default: return nil
        }
    }
    let store = V0355WeeklyStoreTests.store(host: host, label: "v0358-\(label)", clock: clock, function: function)
    return (store, host)
}

private func v0358Calls(_ host: String, _ rpc: String = "achievements_status") -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

// MARK: - ① 전선

@Suite struct V0358DecodeTests {
    @Test("계약 응답 13개 — 칸마다 그대로 옮긴다(스네이크 → 카멜) · 받을 것 · claimed_now · 잔량 · 서버 시각")
    func decodesTheFullContract() throws {
        let status = try V0358Fixture.decode(V0358Fixture.json(claimedNow: [("team2", "팀 2명 채우기", 50)]))
        #expect(status.missions.count == 13)
        #expect(status.missions.map(\.key) == V0358Fixture.base.map(\.key))
        let poke50 = try #require(status.missions.first { $0.key == "poke50" })
        #expect(poke50 == AchievementStatus.Mission(key: "poke50", series: "poke", tier: 2, title: "콕 찌르기 50회", detail: "",
                                                    reward: 20, target: 50, progress: 23, achieved: false, claimed: false,
                                                    achievedAtMs: nil, claimedAtMs: nil, sort: 70))
        #expect(poke50.state == .inProgress && poke50.fraction == 23.0 / 50.0)
        let phone = try #require(status.missions.first)
        #expect(phone.achieved && !phone.claimed && phone.isClaimable && phone.state == .claimable)
        #expect(phone.achievedAtMs == V0358Fixture.t - 60_000 && phone.claimedAtMs == nil)
        #expect(phone.detail == "아이폰 앱에 같은 계정으로 로그인")
        let todo = try #require(status.missions.first { $0.key == "todo3" })
        #expect(todo.state == .claimed && todo.claimedAtMs == V0358Fixture.t)
        #expect(status.claimedNow == [.init(key: "team2", title: "팀 2명 채우기", reward: 50)])
        #expect(status.claimedNowRuby == 50)
        #expect(status.claimableCount == 2 && status.claimableRuby == 250)
        #expect(status.reportedClaimableCount == 2 && status.reportedClaimableRuby == 250)
        #expect(status.rubyBalance == 1234)
        #expect(status.serverNowMs == V0358Fixture.t)
        #expect(status.launchAtMs == V0358Fixture.t - 3_600_000)
        // 상태 조회에는 claimed_now 가 없다 → 빈 배열.
        #expect(V0358Fixture.status().claimedNow.isEmpty)
    }

    @Test("칸이 빠져도 통째로 죽지 않는다 — 빈 객체 · 기본값 · 키/제목 없는 행만 버린다 · 시각으로 판단 · 받음은 채움 · 모르는 키")
    func missingAndUnknownFieldsNeverFailTheDecode() throws {
        let empty = try V0358Fixture.decode("{}")
        #expect(empty.missions.isEmpty && empty.claimedNow.isEmpty && empty.rubyBalance == nil && empty.serverNowMs == nil)
        #expect(empty.seriesRows.isEmpty && empty.claimableCount == 0)

        let json = #"""
        {"missions":[
           {"key":"bare","title":"이름만 있는 미션"},
           {"title":"키 없음","reward":5},
           {"key":"notitle","reward":5},
           {"key":"blank","title":"   "},
           17,
           {"key":"stringy","title":"문자열 숫자","reward":"30","target":"14","progress":"9","sort":"5","tier":"2","series":"s"},
           {"key":"timed","title":"칸 없음 · 시각만","achieved_at_ms":1781234000000,"achieved":"yes"},
           {"key":"paid","title":"받음만 참","claimed":true},
           {"key":"paidtime","title":"받은 시각만","claimed_at_ms":1781234000001},
           {"key":"clamp","title":"넘친 진행","target":3,"progress":99,"reward":-4},
           {"key":"bare","title":"같은 키 둘째"},
           {"key":"future_quest","title":"서버가 더한 새 미션","detail":"앱은 몰라도 그린다","reward":15,"target":2,"progress":1,
            "sort":999,"brand_new_field":{"x":1},"icon":"sparkles"}
         ],
         "claimed_now":[{"key":"bare"},{"reward":3},"junk"],
         "ruby_balance":"77","new_top_level":true}
        """#
        let status = try V0358Fixture.decode(json)
        #expect(status.missions.map(\.key) == ["bare", "stringy", "timed", "paid", "paidtime", "clamp", "future_quest"],
                "키 · 제목이 없거나 빈 행만 버리고, 깨진 원소는 건너뛰고, 같은 키는 앞의 것만 남긴다")
        let bare = try #require(status.missions.first)
        #expect(bare == AchievementStatus.Mission(key: "bare", series: "bare", tier: 1, title: "이름만 있는 미션", detail: "",
                                                  reward: 0, target: 1, progress: 0, achieved: false, claimed: false, sort: Int.max),
                "빠진 칸의 기본값: 계열 = 키 · 단계 1 · 목표 1 · 진행 0 · 안 채움 · 안 받음 · 맨 뒤")
        let stringy = status.missions[1]
        #expect(stringy.reward == 30 && stringy.target == 14 && stringy.progress == 9 && stringy.sort == 5 && stringy.tier == 2
                && stringy.series == "s")
        #expect(status.missions[2].state == .claimable, "achieved 가 깨졌으면 달성 시각으로 판단한다")
        #expect(status.missions[3].state == .claimed && status.missions[3].achieved, "받은 것은 채운 것이다(achieved 칸이 없어도)")
        #expect(status.missions[4].state == .claimed, "claimed 칸이 없으면 받은 시각으로 판단한다")
        let clamp = status.missions[5]
        #expect(clamp.progress == 3 && clamp.reward == 0, "진행은 목표로 자르고 음수 보상은 0")
        #expect(status.claimedNow == [.init(key: "bare", title: "", reward: 0)], "키 없는 지급 · 깨진 원소는 버린다")
        #expect(status.rubyBalance == 77)
        // 모르는 키(future_quest)도 한 줄로 선다 — 서버가 미션을 더하는 날 앱을 다시 낼 필요가 없다.
        #expect(status.seriesRows.map(\.key).contains("future_quest"))
        #expect(AchievementCopy.icon("future_quest") == AchievementCopy.fallbackIcon)
        // 최상위가 객체가 아니면(응답이 아니다) 그때만 throw.
        #expect(throws: (any Error).self) { try V0358Fixture.decode("[]") }
    }

    @Test("받기 본문 — 키를 언제나 싣는다: {\"p_key\":\"poke10\"} · 전부 받기 {\"p_key\":null} · 주간 {\"p_week_start\":null,\"p_hours\":null}")
    func claimBodiesAlwaysCarryTheirKeys() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        func text(_ value: some Encodable) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        #expect(try text(AchievementClaimRequest(key: "poke10")) == #"{"p_key":"poke10"}"#)
        #expect(try text(AchievementClaimRequest(key: nil)) == #"{"p_key":null}"#)
        #expect(try text(WeeklyWorkClaimRequest(weekStart: nil, hours: nil)) == #"{"p_hours":null,"p_week_start":null}"#)
        #expect(try text(WeeklyWorkClaimRequest(weekStart: "2026-10-12", hours: 40)) == #"{"p_hours":40,"p_week_start":"2026-10-12"}"#)
        #expect(SupabaseWorkService.achievementClaimPath == "/rest/v1/rpc/achievement_claim")
        #expect(SupabaseWorkService.weeklyWorkClaimPath == "/rest/v1/rpc/weekly_work_claim")
    }

    @Test("주간 — 받기 서버의 새 칸(achieved · claimable · pending · claimable_ruby · claimed_now)을 옮기고, 옛 응답은 예전 그대로(버튼 없음)")
    func weeklyClaimFields() throws {
        let fresh = V0358Fixture.weekly()
        #expect(fresh.supportsClaim && fresh.hasClaimable && fresh.pendingRuby == 70 && fresh.pendingCount == 2)
        #expect(fresh.pending == [.init(weekStart: "2026-10-12", hours: 20, ruby: 20), .init(weekStart: "2026-10-12", hours: 40, ruby: 50)])
        #expect(fresh.tiers.map(\.achieved) == [true, true, false] && fresh.tiers.map(\.claimable) == [true, true, false])
        #expect(fresh.grantedNow.isEmpty && fresh.claimedNow.isEmpty)
        let claimed = V0358Fixture.weekly(V0358Fixture.weeklyClaimedJSON())
        #expect(claimed.supportsClaim && !claimed.hasClaimable && claimed.pendingCount == 0 && claimed.claimedNowRuby == 70)
        // 합만 있고 목록이 없어도 "받을 것이 있다"는 말한다(한 번 누르면 받는다).
        let sumOnly = try V0355WeeklyStub.decode(#"{"worked_seconds":1,"tiers":[{"hours":20,"ruby":20}],"claimable_ruby":200}"#)
        #expect(sumOnly.supportsClaim && sumOnly.pendingRuby == 200 && sumOnly.pendingCount == 1)
        // 지난주 것만 남아도 받을 것이다(달성은 사라지지 않는다).
        let lastWeek = V0358Fixture.weekly(V0358Fixture.weeklyJSON(worked: 0, tiers: [(20, 20, false, false), (40, 50, false, false),
                                                                                       (60, 200, false, false)],
                                                                 pending: [("2026-10-05", 60, 200)]))
        #expect(lastWeek.hasClaimable && lastWeek.pendingRuby == 200)

        // ★ 옛 응답(0.3.55 계약 — 새 칸 없음): 키 · 타입이 그대로 읽히고, 받기가 없다(버튼 없음 · 배지 0).
        let old = try V0355WeeklyStub.decode(V0355WeeklyStub.json(worked: 45 * 3_600, claimed: [true, true, false]))
        #expect(!old.supportsClaim && !old.hasClaimable && old.pendingRuby == 0 && old.pendingCount == 0)
        #expect(old.pending == nil && old.claimableRuby == nil && old.claimedNow.isEmpty)
        #expect(old.tiers == [.init(hours: 20, ruby: 20, claimed: true), .init(hours: 40, ruby: 50, claimed: true),
                              .init(hours: 60, ruby: 200, claimed: false)], "옛 단계 행이 예전 값과 같지 않다(새 칸이 nil 이 아니다)")
    }

    @Test("주간 — 받기 서버에서는 claimed 가 거짓 → 참으로 바뀌어도 '채웠어요'를 또 말하지 않는다 · 옛 서버는 예전 그대로 말한다")
    func weeklyAutoGrantNoticeIsSilencedOnClaimServer() throws {
        let before = V0358Fixture.weekly()
        let after = V0358Fixture.weekly(V0358Fixture.weeklyClaimedJSON())
        #expect(after.newlyGranted(since: before).isEmpty, "받기 서버의 받음 전이를 자동 지급으로 다시 알렸다(받기 연출과 겹친다)")
        // 대조군: 옛 서버(새 칸 없음)는 같은 전이를 지급으로 말한다(0.3.55 규약 — cron 이 먼저 넣은 행).
        let oldBefore = try V0355WeeklyStub.decode(V0355WeeklyStub.json(worked: 45 * 3_600, claimed: [false, false, false]))
        let oldAfter = try V0355WeeklyStub.decode(V0355WeeklyStub.json(worked: 45 * 3_600, claimed: [true, true, false]))
        #expect(oldAfter.newlyGranted(since: oldBefore).map(\.hours) == [20, 40])
    }
}

// MARK: - ② 계열 접기 · 병합

@Suite struct V0358SeriesTests {
    @Test("계열마다 한 줄 — [받기] 단계 → 안 받은 가장 낮은 단계 → 다 받았으면 가장 높은 단계(받음) · 순서는 sort — 9줄")
    func collapsesTiers() {
        let rows = V0358Fixture.status().seriesRows
        #expect(rows.map(\.key) == ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "team3", "poke50", "ultra5", "streak14"])
        #expect(rows.map(\.state) == [.claimable, .claimed, .inProgress, .inProgress, .inProgress, .claimable, .inProgress,
                                      .inProgress, .inProgress])
        // 다 받은 계열 — 가장 높은 단계를 받은 것으로.
        var all = V0358Fixture.with("poke50", claimed: true)
        all = V0358Fixture.with(all, "poke100", claimed: true)
        all = V0358Fixture.with(all, "streak14", claimed: true)
        all = V0358Fixture.with(all, "streak30", progress: 3, claimed: true)
        let done = V0358Fixture.status(all).seriesRows
        #expect(done.first { $0.series == "poke" }?.key == "poke100")
        #expect(done.first { $0.series == "poke" }?.state == .claimed)
        #expect(done.first { $0.series == "streak" }?.key == "streak30")
        #expect(done.first { $0.series == "streak" }?.fraction == 1, "받은 줄은 지금 연속(3일)이 낮아도 가득 그린다")
    }

    @Test("받을 수 있는 낮은 단계를 위 단계가 가리지 않는다 — 콕 10 · 50 을 둘 다 채우고 안 받았으면 10 의 [받기], 받으면 50 의 [받기]")
    func claimableLowerTierIsNeverHidden() {
        var rows = V0358Fixture.with(V0358Fixture.fresh, "poke10", achieved: true)
        rows = V0358Fixture.with(rows, "poke50", achieved: true)
        rows = V0358Fixture.with(rows, "streak14", achieved: true)
        rows = V0358Fixture.with(rows, "streak30", achieved: true)
        let status = V0358Fixture.status(rows)
        let poke = status.seriesRows.first { $0.series == "poke" }
        #expect(poke?.key == "poke10" && poke?.state == .claimable, "콕 10 의 [받기]가 안 보인다: \(String(describing: poke?.key))")
        #expect(status.seriesRows.first { $0.series == "streak" }?.key == "streak14")
        #expect(status.claimableCount == 4, "배지는 접기 전에 센다(콕 2 + 연속 2)")
        // 콕 10 을 받으면 같은 줄이 50 의 [받기]가 된다(아직 안 받은 100 이 아니다).
        let next = V0358Fixture.status(V0358Fixture.with(rows, "poke10", claimed: true)).seriesRows.first { $0.series == "poke" }
        #expect(next?.key == "poke50" && next?.state == .claimable)
        // 이상한 표(낮은 단계 미달성 · 위 단계만 채움)도 [받기]가 이긴다 — 받을 수 있는 것이 화면에서 사라지지 않는다.
        let odd = V0358Fixture.status(V0358Fixture.with(V0358Fixture.fresh, "poke50", achieved: true)).seriesRows
        #expect(odd.first { $0.series == "poke" }?.key == "poke50")
    }

    @Test("줄 순서는 계열의 가장 작은 sort — 단계가 올라도 줄이 자리를 옮기지 않는다 · 서버 순서와 무관")
    func orderIsStableAcrossTiers() {
        let reversed = AchievementStatus(missions: V0358Fixture.status().missions.reversed()).seriesRows.map(\.series)
        #expect(reversed == V0358Fixture.status().seriesRows.map(\.series))
        var rows = V0358Fixture.base
        rows.append(.init(key: "zz_new", series: "zz", tier: 1, title: "새 미션", reward: 1, target: 1, progress: 0,
                          achieved: false, claimed: false, sort: 70))
        rows = V0358Fixture.with(rows, "poke50", claimed: true)
        let series = V0358Fixture.status(rows).seriesRows
        #expect(series.first { $0.series == "poke" }?.key == "poke100", "전제: 콕은 마지막 단계(sort 71)를 보인다")
        let names = series.map(\.series)
        let poke = names.firstIndex(of: "poke"), zz = names.firstIndex(of: "zz")
        #expect(poke != nil && zz != nil && poke! < zz!, "콕(가장 작은 sort 69)이 새 미션(70) 뒤로 밀렸다: \(names)")
    }

    @Test("절 상태 — 서버에 없음 → 감춤 · 받기 전 → 불러오는 중 · 실패 → 실패 · 받은 뒤 실패 → 알던 줄 · 빈 목록 → 감춤 · 받을 수는 접기 전")
    func sectionState() {
        let status = V0358Fixture.status()
        #expect(AchievementSectionState.make(status: nil, unavailable: true, failed: false) == .hidden)
        #expect(AchievementSectionState.make(status: status, unavailable: true, failed: false) == .hidden)
        #expect(AchievementSectionState.make(status: nil, unavailable: false, failed: false) == .loading)
        #expect(AchievementSectionState.make(status: nil, unavailable: false, failed: true) == .failed)
        #expect(AchievementSectionState.make(status: status, unavailable: false, failed: true)
                == .loaded(rows: status.seriesRows, claimableCount: 2))
        #expect(AchievementSectionState.make(status: AchievementStatus(), unavailable: false, failed: false) == .hidden)
        #expect(AchievementCopy.pendingHint(2) == "받을 보상 2개" && AchievementCopy.pendingHint(0) == nil)
    }

    @Test("받음은 되돌아가지 않는다 — 늦게 온 옛 응답(받음 = 거짓)을 얹어도 받은 줄은 받은 채 · 새 받음 · 진행은 새 값")
    func mergeNeverUnclaims() {
        let claimedTeam3 = V0358Fixture.status(V0358Fixture.with("team3", claimed: true))
        // 겹친 받기 둘의 답이 뒤바뀌어 왔다: 나중 도착한 답은 team3 를 아직 안 받은 것으로, phone 을 받은 것으로 적었다.
        let late = V0358Fixture.status(V0358Fixture.with(V0358Fixture.with("phone_login", claimed: true), "poke50", progress: 30))
        let merged = late.merged(over: claimedTeam3)
        #expect(merged.missions.first { $0.key == "team3" }?.state == .claimed, "방금 받은 team3 에 [받기]가 다시 섰다")
        #expect(merged.missions.first { $0.key == "phone_login" }?.state == .claimed)
        #expect(merged.missions.first { $0.key == "poke50" }?.progress == 30, "진행은 새 응답의 값이다")
        #expect(merged.claimableCount == 0)
        #expect(late.merged(over: nil) == late)
    }
}

// MARK: - ③ 받기(스토어)

@MainActor
@Suite(.serialized) struct V0358ClaimStoreTests {
    @Test("받기 성공 — POST achievement_claim {p_key} · 상태 · 잔량 · 연출(계열 자리) · 말풍선(합) · 떠 있음 해제 · 배지 감소")
    func claimSuccessAppliesEverything() async throws {
        let (store, host) = v0358Store("claim-ok")
        var rewards: [Int] = []
        store.onRewardTrigger = { kind in if case .rubyReward(let amount) = kind { rewards.append(amount) } }
        store.applyAchievements(V0358Fixture.status(ruby: 1234))
        #expect(store.missionClaimableCount == 2)
        let task = try #require(store.claimAchievement(key: "phone_login"))
        #expect(store.achievementClaimsInFlight == ["phone_login"], "떠 있는 동안 버튼을 흐릴 표시가 없다")
        await task.value
        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "achievement_claim").first)
        #expect(call.body == #"{"p_key":"phone_login"}"#)
        #expect(store.achievements?.missions.first?.state == .claimed)
        #expect(store.rubyBalance == 1284)
        #expect(store.missionClaimBursts[MissionClaimBurst.achievementTarget(series: "phone_login")]?.amount == 50)
        #expect(rewards == [50])
        #expect(store.achievementClaimsInFlight.isEmpty)
        #expect(store.missionClaimableCount == 1)
        #expect(store.missionNotice == nil, "성공했는데 안내줄을 띄웠다(절이 아래로 밀려 연출 중에 줄이 뛴다)")
        // 같은 줄을 또 받으면(다음 단계) 새 순번 → 뷰가 처음부터 다시 그린다.
        let first = try #require(store.missionClaimBursts.values.first?.serial)
        await store.claimAchievement(key: "phone_login")?.value
        #expect((store.missionClaimBursts.values.first?.serial ?? 0) > first)
    }

    @Test("같은 키 두 번(더블 클릭) = 요청 1건 · 다른 키는 따로 나간다 · 전부 받기가 떠 있으면 낱개도 기다린다")
    func inFlightGuard() async throws {
        let (store, host) = v0358Store("claim-guard", claim: { body, _ in
            let key = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_key"] as? String
            return .init(body: V0358Fixture.claimJSON(key: key ?? "phone_login", ruby: 1284), delay: 0.3)
        })
        store.applyAchievements(V0358Fixture.status())
        let first = store.claimAchievement(key: "phone_login")
        let second = store.claimAchievement(key: "phone_login")
        #expect(first != nil && second == nil, "떠 있는 받기가 있는데 또 발사했다")
        let other = store.claimAchievement(key: "team3")
        #expect(other != nil, "다른 줄의 받기까지 막았다")
        await first?.value
        await other?.value
        #expect(v0358Calls(host, "achievement_claim") == 2)
        #expect(store.achievementClaimsInFlight.isEmpty)
        // 전부 받기가 떠 있으면 낱개는 0건.
        let all = store.claimAchievement(key: nil)
        #expect(store.claimAchievement(key: "poke50") == nil)
        await all?.value
        #expect(v0358Calls(host, "achievement_claim") == 3)
        #expect(GomokuStubProtocol.calls(host: host, rpc: "achievement_claim").last?.body == #"{"p_key":null}"#)
    }

    @Test("넣은 것이 없으면(이미 받음 · 미달성 · 모르는 키) 조용하다 — 연출 · 말풍선 없음, 상태만 옮긴다")
    func noOpClaimIsSilent() async {
        let (store, _) = v0358Store("claim-noop", claim: { _, _ in .init(body: V0358Fixture.json(V0358Fixture.with("phone_login", claimed: true))) })
        var rewards: [Int] = []
        store.onRewardTrigger = { kind in if case .rubyReward(let amount) = kind { rewards.append(amount) } }
        store.applyAchievements(V0358Fixture.status())
        await store.claimAchievement(key: "phone_login")?.value
        #expect(store.missionClaimBursts.isEmpty && rewards.isEmpty)
        #expect(store.achievements?.missions.first?.state == .claimed, "서버가 말한 받음을 옮기지 않았다(버튼이 남는다)")
    }

    @Test("실패 — 그 줄에 실패 표시(안내줄은 안 쓴다) · 버튼은 그대로(안 받음) · 떠 있음 해제 · 다시 누르면 나가고 받으면 표시가 내려간다")
    func failureLeavesTheButton() async {
        let (store, host) = v0358Store("claim-fail", claim: { body, index in
            let key = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_key"] as? String
            return index == 0 || index == 2 ? .init(status: 500, body: #"{"message":"boom"}"#)
                : .init(body: V0358Fixture.claimJSON(key: key ?? "phone_login", ruby: 1284))
        })
        store.applyAchievements(V0358Fixture.status())
        await store.claimAchievement(key: "phone_login")?.value
        // ★ 검토 지적(2026-10-19): 안내줄은 절 위에 끼어 줄을 26pt 밀고, 넷째 줄부터는 누른 사람의 스크롤 밖이었다.
        #expect(store.missionNotice == nil, "받기 실패를 안내줄로 띄웠다 — 절이 밀리고 아래 줄을 누른 사람에겐 안 보인다")
        #expect(store.achievementClaimFailedKeys == ["phone_login"], "실패한 줄에 실패 표시가 없다")
        #expect(AchievementNoticeText.claimFailedRow == "받지 못했어요 · 다시 눌러 주세요")
        #expect(store.achievements?.missions.first?.state == .claimable && store.achievementClaimsInFlight.isEmpty)
        #expect(store.missionClaimBursts.isEmpty)
        await store.claimAchievement(key: "phone_login")?.value
        #expect(v0358Calls(host, "achievement_claim") == 2 && store.achievements?.missions.first?.state == .claimed)
        #expect(store.achievementClaimFailedKeys.isEmpty, "다시 눌러 받았는데 실패 표시가 남았다")
        // 다른 줄의 실패는 그 줄에만 선다 · 다른 안내(3시간 랩)는 받기가 건드리지 않는다.
        store.missionNotice = V0358Fixture.lapNotice
        await store.claimAchievement(key: "team3")?.value
        #expect(store.achievementClaimFailedKeys == ["team3"] && store.missionNotice == V0358Fixture.lapNotice)
        // 미션 화면을 닫으면 실패 표시도 내린다(다시 열면 화면이 새로 묻는다).
        store.isMenuPresented = true
        store.toggleMissionPanel()
        store.closeMissionPanel()
        #expect(store.achievementClaimFailedKeys.isEmpty, "미션 화면을 닫아도 실패 표시가 남았다")
    }

    @Test("전부 받기가 실패하면 받을 수 있던 줄 전부에 표시 · 낱개 성공은 그 줄만 · 전부 받기 성공은 모두 내린다")
    func claimAllFailureMarksEveryClaimableRow() async {
        let (store, _) = v0358Store("claim-all-fail", claim: { body, index in
            let key = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_key"] as? String
            return index == 0 ? .init(status: 500, body: #"{"message":"boom"}"#)
                : .init(body: V0358Fixture.claimJSON(key: key ?? "phone_login", ruby: 1284))
        })
        store.applyAchievements(V0358Fixture.status())
        await store.claimAchievement(key: nil)?.value
        #expect(store.achievementClaimFailedKeys == ["phone_login", "team3"])
        await store.claimAchievement(key: "phone_login")?.value
        #expect(store.achievementClaimFailedKeys == ["team3"])
        await store.claimAchievement(key: nil)?.value
        #expect(store.achievementClaimFailedKeys.isEmpty)
    }

    @Test("받기 함수가 없는 서버(404) → 절을 감춘다(실패 문구 없음) · 감춘 동안은 받기가 안 나간다")
    func claimOnMissingFunctionHides() async {
        let (store, host) = v0358Store("claim-404", claim: { _, _ in .init(status: 404, body: V0358Fixture.missingFunctionBody) })
        store.applyAchievements(V0358Fixture.status())
        await store.claimAchievement(key: "phone_login")?.value
        #expect(store.achievementsUnavailable && store.achievements == nil && store.missionNotice == nil)
        #expect(store.claimAchievement(key: "phone_login") == nil)
        #expect(v0358Calls(host, "achievement_claim") == 1)
    }

    @Test("받기 전에 떠난 조회가 받기 뒤에 도착하면 버린다 — 방금 받은 줄 · 받기가 정산해 새로 채운 줄이 되돌아가지 않는다 · 잔량도 안 내려간다")
    func staleFetchAfterClaimIsDropped() async {
        // 받기는 서버가 먼저 정산한다 — 그 사이 오목 한 판이 끝나 gomoku1 이 새로 채워졌다(받기 응답엔 있고, 먼저 떠난 조회엔 없다).
        let settled = V0358Fixture.with("gomoku1", achieved: true)
        let (store, host) = v0358Store("claim-stale", achievements: { _ in .init(body: V0358Fixture.json(ruby: 1234), delay: 0.4) },
                                       claim: { _, _ in .init(body: V0358Fixture.claimJSON(settled, key: "phone_login", ruby: 1284)) })
        store.applyAchievements(V0358Fixture.status(ruby: 1234))
        let fetch = store.refreshAchievements(reason: .missionPanel)
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host) == 1 }, "전제: 조회가 떠났다")
        await store.claimAchievement(key: "phone_login")?.value
        #expect(store.rubyBalance == 1284 && store.achievements?.missions.first?.state == .claimed)
        #expect(store.achievements?.missions.first { $0.key == "gomoku1" }?.state == .claimable)
        await fetch?.value
        #expect(store.achievements?.missions.first?.state == .claimed, "받기 전에 떠난 조회가 받은 줄을 [받기]로 되돌렸다")
        #expect(store.achievements?.missions.first { $0.key == "gomoku1" }?.state == .claimable,
                "받기 전에 떠난 조회가 받기가 정산한 새 달성(오목)을 지웠다 — [받기]가 다음 박자까지 사라진다")
        #expect(store.rubyBalance == 1284, "늦게 온 조회가 잔량을 받기 전 값(1234)으로 내렸다")
    }

    @Test("늦은 응답은 잔량을 못 내린다 — 떠난 뒤 다른 쓰기(뽑기 · 다른 받기)가 있었으면 응답의 잔량을 버리고, 받은 루비가 있으면 다시 읽는다")
    func staleResponseCannotLowerTheBalance() async {
        let (store, _) = v0358Store("ruby-order")
        store.applyAchievements(V0358Fixture.status(ruby: 1234), rubyWriteSerialAtDeparture: store.rubyBalanceWriteSerial)
        #expect(store.rubyBalance == 1234)
        let departed = store.rubyBalanceWriteSerial
        store.rubyBalance = 2000   // 그 사이 다른 받기 · 대국 정산이 새 잔량을 썼다
        store.applyAchievements(V0358Fixture.status(ruby: 1234), rubyWriteSerialAtDeparture: departed)
        #expect(store.rubyBalance == 2000, "떠난 뒤 들어온 잔량을 옛 응답이 덮었다")
        // 받기 응답(루비가 늘었다)의 잔량을 버렸으면 사실을 다시 읽는다 — 상점 조회가 나간다.
        #expect(!store.shopLoading)
        store.applyAchievements(V0358Fixture.status(V0358Fixture.with("phone_login", claimed: true),
                                                     claimedNow: [("phone_login", "폰 앱에서 로그인하기", 50)], ruby: 1284),
                                rubyWriteSerialAtDeparture: departed)
        #expect(store.rubyBalance == 2000 && store.shopLoading, "버린 받기 잔량을 다시 읽지 않았다(옛 잔량이 남는다)")
        // 잔량을 안 실은 응답은 건드리지 않는다.
        store.applyAchievements(V0358Fixture.status(ruby: nil))
        #expect(store.rubyBalance == 2000)
    }

    @Test("받기가 옮긴 잔량을 그 전에 떠난 상점 조회가 되돌리지 않는다 — 늦은 상점 조회(받기 전 1234)는 버려지고 한 번 다시 읽어 1284")
    func claimBalanceSurvivesALateShopRead() async throws {
        // 검토 지적(2026-10-19): `applyAchievements` 의 상점 변이 표시(noteShopMutation)를 지워도 모든 시험이 초록이었다.
        // 그러면 받기 전에 떠난 상점 조회가 받기 뒤에 도착해 잔량을 받기 전으로 되돌린다(2026-10-16 주간 보상 때와 같은 결함).
        let (store, host) = v0358Store("claim-shop-race", shop: { index in
            .init(body: V0358Fixture.shopJSON(ruby: index == 0 ? 1234 : 1284), delay: index == 0 ? 0.5 : 0)
        })
        store.applyAchievements(V0358Fixture.status(ruby: 1234))
        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") == 1 }, "전제: 상점 조회가 떠났다")
        await store.claimAchievement(key: "phone_login")?.value
        #expect(store.rubyBalance == 1284, "받기 응답이 잔량을 안 옮겼다")
        // 늦은 상점 조회(0.5초)가 도착하고, 버려졌으면 다시 읽기까지 끝날 때를 기다린다.
        try? await Task.sleep(for: .milliseconds(700))
        _ = await V0354CoreStub.waitUntil { !store.shopLoading }
        #expect(store.rubyBalance == 1284, "받기 전에 떠난 상점 조회가 받은 잔량(1284)을 1234 로 되돌렸다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "shop_state") == 2, "버려진 상점 조회를 한 번 다시 읽지 않았다")
    }

    @Test("주간 받기가 떠 있는 사이 다른 쓰기가 잔량을 바꿨으면 받기 응답의 잔량은 버리고, 루비가 늘었으니 사실을 다시 읽는다")
    func weeklyClaimRereadsWhenTheBalanceMovedMeanwhile() async throws {
        // 검토 지적(2026-10-19): `applyWeeklyWork` 의 다시 읽기 조건에서 `claimedNowRuby > 0` 을 지워도 초록이었다 — 받기 서버의
        // 주간 응답엔 granted_now 가 없어, 그 조건이 없으면 받은 +70 을 다시 읽지 않고 받기 전 숫자가 남는다.
        let (store, host) = v0358Store("weekly-claim-reread",
                                       weeklyClaim: { _ in .init(body: V0358Fixture.weeklyClaimedJSON(ruby: 1127), delay: 0.3) },
                                       shop: { _ in .init(body: V0358Fixture.shopJSON(ruby: 1500)) })
        store.applyWeeklyWork(V0358Fixture.weekly())
        #expect(store.rubyBalance == 1057)
        let task = try #require(store.claimWeeklyWork())
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host, "weekly_work_claim") == 1 }, "전제: 주간 받기가 떠났다")
        store.rubyBalance = 1430   // 그 사이 뽑기 · 대국 정산이 새 잔량을 썼다
        await task.value
        #expect(store.rubyBalance != 1127, "떠난 뒤 들어온 잔량(1430)을 받기 응답(1127)이 덮었다")
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") == 1 && !store.shopLoading },
                "버린 받기 잔량을 다시 읽지 않았다 — 제목 행 숫자가 받기 전 값에 머문다")
        #expect(store.rubyBalance == 1500)
    }

    @Test("겹친 받기 둘의 답이 뒤바뀌어 와도 받은 줄은 받은 채(스토어 병합)")
    func reversedClaimResponsesKeepBothClaimed() {
        let (store, _) = v0358Store("claim-reorder")
        store.applyAchievements(V0358Fixture.status())
        // B(team3) 의 답(먼저 도착) — 둘 다 받음.
        store.applyAchievements(V0358Fixture.status(V0358Fixture.with(V0358Fixture.with("phone_login", claimed: true), "team3", claimed: true)))
        // A(phone) 의 답(나중 도착) — A 만 받음(B 는 아직이었다).
        store.applyAchievements(V0358Fixture.status(V0358Fixture.with("phone_login", claimed: true)))
        #expect(store.achievements?.missions.first { $0.key == "team3" }?.state == .claimed)
        #expect(store.missionClaimableCount == 0)
    }

    @Test("주간 받기 — POST weekly_work_claim {null,null} · 상태 · 잔량 · 연출 · 말풍선 · 두 번 = 1건 · '채웠어요' 안내 없음")
    func weeklyClaim() async throws {
        let (store, host) = v0358Store("weekly-claim", weeklyClaim: { _ in .init(body: V0358Fixture.weeklyClaimedJSON(), delay: 0.2) })
        var rewards: [Int] = []
        store.onRewardTrigger = { kind in if case .rubyReward(let amount) = kind { rewards.append(amount) } }
        store.applyWeeklyWork(V0358Fixture.weekly())
        #expect(store.missionClaimableCount == 2)
        let task = try #require(store.claimWeeklyWork())
        #expect(store.weeklyClaimInFlight && store.claimWeeklyWork() == nil, "떠 있는 주간 받기가 있는데 또 발사했다")
        await task.value
        #expect(v0358Calls(host, "weekly_work_claim") == 1)
        let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "weekly_work_claim").first?.json)
        #expect(Set(body.keys) == ["p_week_start", "p_hours"] && body.values.allSatisfy { $0 is NSNull },
                "주간 전부 받기 본문이 키 둘을 null 로 싣지 않는다: \(body)")
        #expect(store.weeklyWork?.hasClaimable == false && store.weeklyWork?.tiers.prefix(2).allSatisfy(\.claimed) == true)
        #expect(store.rubyBalance == 1127)
        #expect(store.missionClaimBursts[MissionClaimBurst.weeklyTarget]?.amount == 70)
        #expect(rewards == [70])
        #expect(store.missionNotice == nil, "받기 연출과 별개로 '이번 주 40시간 채웠어요' 자동 지급 안내가 떴다")
        #expect(!store.weeklyClaimInFlight && store.missionClaimableCount == 0)
        // 받을 것이 없으면 나가지 않는다.
        #expect(store.claimWeeklyWork() == nil)
    }

    @Test("주간 받기 — 옛 서버(새 칸 없음)는 받을 것이 없다: 요청 0건 · 배지 0")
    func weeklyClaimNeverFiresOnOldServer() async {
        let (store, host) = v0358Store("weekly-old")
        store.applyWeeklyWork(try! V0355WeeklyStub.decode(V0355WeeklyStub.json(worked: 45 * 3_600, claimed: [true, true, false])))
        #expect(store.claimWeeklyWork() == nil && store.missionClaimableCount == 0)
        await V0355WeeklyStoreTests.settle()
        #expect(v0358Calls(host, "weekly_work_claim") == 0)
    }

    @Test("주간 — 받기 전에 떠난 주간 조회가 받기 뒤에 도착하면 버린다 · 실패는 주간 줄의 표시 + 버튼 남음(안내줄 없음)")
    func weeklyStaleFetchAndFailure() async {
        let (store, host) = v0358Store("weekly-stale", weekly: { _ in .init(body: V0358Fixture.weeklyJSON(), delay: 0.4) },
                                       weeklyClaim: { index in
                                           index == 1 ? .init(status: 503, body: "{}")
                                               : .init(body: V0358Fixture.weeklyClaimedJSON())
                                       })
        store.applyWeeklyWork(V0358Fixture.weekly())
        let fetch = store.refreshWeeklyWork(reason: .walletCadence)
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host, "weekly_work_status") == 1 })
        await store.claimWeeklyWork()?.value
        await fetch?.value
        #expect(store.weeklyWork?.hasClaimable == false, "받기 전에 떠난 주간 조회가 [받기]를 되살렸다")
        // 실패 — 버튼은 남고 주간 줄에 실패 표시(안내줄은 절을 민다 — 검토 지적 2026-10-19) · 다시 눌러 받으면 표시가 내려간다.
        store.applyWeeklyWork(V0358Fixture.weekly())
        await store.claimWeeklyWork()?.value
        #expect(store.weeklyClaimFailed && store.weeklyWork?.hasClaimable == true)
        #expect(store.missionNotice == nil, "주간 받기 실패를 안내줄로 띄웠다 — 아래 도전 미션 절이 26pt 밀린다")
        #expect(!store.weeklyClaimInFlight)
        await store.claimWeeklyWork()?.value
        #expect(!store.weeklyClaimFailed && store.weeklyWork?.hasClaimable == false, "다시 눌러 받았는데 실패 표시가 남았다")
        // 팝오버를 닫으면 실패 표시도 내린다.
        store.weeklyClaimFailed = true
        store.isMenuPresented = true
        store.setMenuPresented(false)
        #expect(!store.weeklyClaimFailed, "팝오버를 닫아도 주간 실패 표시가 남았다")
    }

    @Test("연출은 그 순간의 것 — 미션 화면을 닫거나 팝오버를 닫으면 비운다 · 로그아웃은 받기 상태를 모두 내린다")
    func burstsAndClaimStateAreCleared() async {
        let (store, _) = v0358Store("claim-clear")
        store.isMenuPresented = true
        store.toggleMissionPanel()
        store.applyAchievements(V0358Fixture.status())
        await store.claimAchievement(key: "phone_login")?.value
        #expect(!store.missionClaimBursts.isEmpty)
        store.setMenuPresented(false)
        #expect(store.missionClaimBursts.isEmpty, "팝오버를 닫아도 연출이 남아 다시 열면 '+50'이 또 뜬다")
        store.setMenuPresented(true)
        await store.claimAchievement(key: "team3")?.value
        store.closeMissionPanel()
        #expect(store.missionClaimBursts.isEmpty, "미션 화면을 닫아도 연출이 남았다")
        store.achievementClaimsInFlight = ["x"]
        store.weeklyClaimInFlight = true
        store.clearPersistedSession()
        #expect(store.achievements == nil && store.achievementClaimsInFlight.isEmpty && !store.weeklyClaimInFlight)
        #expect(store.missionClaimableCount == 0)
    }
}

// MARK: - ④ 배지

@MainActor
@Suite(.serialized) struct V0358BadgeTests {
    @Test("숫자 = 받을 도전 미션(접기 전) + 받을 주간 단계(어느 주든) · 서버에 없음이면 도전 미션 몫 0 · 문구")
    func countAndCopy() {
        let (store, _) = v0358Store("badge-count")
        #expect(store.missionClaimableCount == 0)
        store.applyAchievements(V0358Fixture.status())
        #expect(store.missionClaimableCount == 2)
        store.applyWeeklyWork(V0358Fixture.weekly())
        #expect(store.missionClaimableCount == 4)
        store.achievementsUnavailable = true
        #expect(store.missionClaimableCount == 2)
        #expect(MissionRailBadge.text(count: 0) == nil && MissionRailBadge.text(count: 3) == "3" && MissionRailBadge.text(count: 12) == "9+")
        #expect(MissionRailBadge.tooltipText(count: 3) == "미션 — 받을 보상 3개" && MissionRailBadge.tooltipText(count: 0) == MissionRailBadge.plainHelp)
    }

    @Test("레일 — [미션] 칸의 배지가 스토어 수를 따른다(값 트리) · 배지가 칸 오른쪽 위에 그려진다")
    func railBadge() throws {
        func missionButton(_ store: WorkTimerStore) throws -> Any {
            var found: [(name: String, value: Any)] = []
            var budget = 200_000
            v0358Collect(["CheckMenuRailButton"], in: CheckMenuSideRail(store: store).body, into: &found, budget: &budget)
            return try #require(found.first { v0358Child("label", of: $0.value) as? String == "미션" }?.value)
        }
        let off = v0358RenderStore(achievements: V0358Fixture.status(V0358Fixture.fresh), mission: false)
        let on = v0358RenderStore(achievements: V0358Fixture.status(), weekly: V0358Fixture.weekly(), mission: false)
        // 옵셔널 칸은 Any 에서 꺼낼 때 풀린다 — nil 이면 String 으로 안 꺼내진다.
        let offBadge = v0358Child("badge", of: try missionButton(off)) as? String
        let onBadge = v0358Child("badge", of: try missionButton(on)) as? String
        #expect(offBadge == nil, "받을 것이 없는데 배지가 섰다: \(String(describing: offBadge))")
        #expect(onBadge == "4", "배지가 받을 수(4)를 말하지 않는다: \(String(describing: onBadge))")
        #expect(v0358Child("help", of: try missionButton(on)) as? String == "미션 — 받을 보상 4개")
        let a = try v0358Bitmap(CheckMenuSideRail(store: off).environment(\.colorScheme, .dark))
        let b = try v0358Bitmap(CheckMenuSideRail(store: on).environment(\.colorScheme, .dark))
        let box = try #require(v0358DiffBox(a, b), "배지가 그려지지 않았다")
        // [미션] 칸은 넷째 칸(위에서 3 × (45 + 6) = 153pt 부터 45pt) — 배지는 그 칸 오른쪽 위 모서리에 걸친다.
        print("[v0358] 레일 배지 차이 \(box) · 레일 \(CGFloat(a.pixelsWide) / 2)×\(CGFloat(a.pixelsHigh) / 2)pt")
        #expect(box.minY >= 153 - 8 && box.maxY <= 153 + 14, "배지가 [미션] 칸 위쪽 모서리가 아니다: \(box)")
        #expect(box.minX >= CGFloat(a.pixelsWide) / 2 - 20, "배지가 칸 오른쪽이 아니다: \(box)")
    }

    @Test("소스 계약 — 레일 [미션] 칸이 배지 · 툴팁을 스토어 수 하나에서 받는다(주석 제외)")
    func railSourceContract() throws {
        let code = try v0358Code("CheckMenuView.swift")
        #expect(code.contains("let missionClaimable = store.missionClaimableCount"))
        #expect(code.contains("help: MissionRailBadge.tooltipText(count: missionClaimable)"))
        #expect(code.contains("badge: MissionRailBadge.text(count: missionClaimable)"))
    }
}

// MARK: - ⑤ 박자

@MainActor
@Suite(.serialized) struct V0358CadenceTests {
    @Test("미션 화면을 여는 순간 · 팝오버가 넘긴 [다시 시도] · 연 채 팝오버 재오픈 — 각각 한 번씩 묻는다(근무 밖이어도)")
    func panelOpenRetryAndReopen() async throws {
        let (store, host) = v0358Store("panel")
        #expect(store.startedAt == nil, "전제: 근무 밖(주기 sync 가 안 도는 사람)")
        store.isMenuPresented = true
        store.toggleMissionPanel()
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host) == 1 && store.achievements != nil && store.achievementsFetchTask == nil },
                "미션 화면을 열었는데 도전 미션을 안 물었다(\(v0358Calls(host))회)")
        let panel = try V0356ReviewFixTests.panelNode("MissionPanel", in: store)
        try V0356ReviewFixTests.action("onRetry", of: panel)()
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host) == 2 && store.achievementsFetchTask == nil },
                "미션 화면 [다시 시도]가 도전 미션을 다시 묻지 않는다(\(v0358Calls(host))회)")
        store.setMenuPresented(false)
        store.setMenuPresented(true)
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host) == 3 && store.achievementsFetchTask == nil },
                "미션 화면을 연 채 팝오버를 다시 열었는데 안 물었다(\(v0358Calls(host))회)")
        store.toggleMissionPanel()
        await V0355WeeklyStoreTests.settle()
        #expect(v0358Calls(host) == 3, "미션 화면을 닫는데 물었다")
    }

    @Test("미션 화면이 아닌 지갑 박자는 묻지 않는다 — 콕찌르기 · 울트라 열기 · 울트라 연 채 재오픈 · 홈 재오픈 · 랩 임계")
    func otherWalletCadencesDoNotAsk() async {
        let (store, host) = v0358Store("others")
        store.isMenuPresented = true
        store.togglePokePanel()
        store.openUltraPanel(from: .poke)
        store.setMenuPresented(false)
        store.setMenuPresented(true)
        store.closeUltraPanel()
        store.closePokePanel()
        store.setMenuPresented(false)
        store.setMenuPresented(true)
        store.syncUltraWallet(reason: .missionCandidate)
        await V0355WeeklyStoreTests.settle()
        #expect(GomokuStubProtocol.count(host: host, rpc: "ultra_wallet_sync") >= 3, "전제: 지갑 sync 는 나갔다")
        #expect(v0358Calls(host) == 0, "미션 화면이 아닌데 도전 미션을 \(v0358Calls(host))번 물었다")
    }

    @Test("로그인 지갑 sync 에 한 번 얹힌다 — 패널을 안 열고 근무도 안 해도 레일 배지가 소급 달성을 말한다 · 받기는 안 나간다")
    func signInPiggyback() async {
        // 검토 지적(2026-10-19): 이 박자가 없으면 근무 안 하는 사람의 배지는 소급 달성을 영영 말하지 않았다(배지가 [받기]를 찾는 길).
        let (store, host) = v0358Store("sign-in")
        #expect(store.startedAt == nil && !store.isMissionPanelVisible, "전제: 근무 밖 · 미션 화면 닫힘")
        store.syncUltraWallet(reason: .signIn)
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host) == 1 && store.achievementsFetchTask == nil },
                "로그인 sync 에 도전 미션이 안 얹혔다(\(v0358Calls(host))회)")
        #expect(store.missionClaimableCount >= 2, "로그인 박자로 받은 소급 달성이 레일 배지를 켜지 않았다")
        #expect(store.achievementsReason(forWallet: .signIn) == .signIn)
        #expect(store.achievementsReason(forWallet: .missionCandidate) == nil)
        await V0355WeeklyStoreTests.settle()
        #expect(v0358Calls(host) == 1, "로그인 한 번에 두 번 물었다")
        #expect(v0358Calls(host, "achievement_claim") == 0 && v0358Calls(host, "weekly_work_claim") == 0,
                "사람이 안 눌렀는데 받기가 나갔다(자동 지급이 되살아났다)")
    }

    @Test("5분 주기 지갑 sync 에 얹힌다 — 근무 중 · 스로틀이 열렸을 때만(5분 안 0건) · 근무 밖이면 0건 · 받기는 박자가 없다")
    func periodicPiggyback() async {
        let clock = V0355Clock(V0355WeeklyStoreTests.t0)
        let (store, host) = v0358Store("periodic", clock: clock)
        store.startedAt = clock.now.addingTimeInterval(-600)
        store.syncUltraWalletIfDue(now: clock.now)
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host) == 1 && store.achievementsFetchTask == nil },
                "근무 중 주기 sync 에 도전 미션이 안 얹혔다 — 패널을 안 여는 사람의 레일 배지가 영영 안 켜진다")
        #expect(store.missionClaimableCount >= 2, "주기 박자로 받은 소급 달성이 배지를 켜지 않았다")
        clock.advance(299)
        store.syncUltraWalletIfDue(now: clock.now)
        await V0355WeeklyStoreTests.settle()
        #expect(v0358Calls(host) == 1, "5분 안에 또 물었다")
        clock.advance(1)
        store.syncUltraWalletIfDue(now: clock.now)
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host) == 2 })
        store.startedAt = nil
        clock.advance(600)
        store.syncUltraWalletIfDue(now: clock.now)
        await V0355WeeklyStoreTests.settle()
        #expect(v0358Calls(host) == 2)
        #expect(v0358Calls(host, "achievement_claim") == 0 && v0358Calls(host, "weekly_work_claim") == 0,
                "사람이 안 눌렀는데 받기가 나갔다(자동 지급이 되살아났다)")
    }

    @Test("겹친 박자는 떠 있는 조회 하나를 같이 기다린다(요청 1건)")
    func inFlightCoalesces() async {
        let (store, host) = v0358Store("coalesce", achievements: { _ in .init(body: V0358Fixture.json(), delay: 0.3) })
        let first = store.refreshAchievements(reason: .missionPanel)
        let second = store.refreshAchievements(reason: .periodic)
        #expect(first != nil && second == nil, "떠 있는 조회가 있는데 또 발사했다")
        await first?.value
        #expect(v0358Calls(host) == 1)
        #expect(store.achievementsFetchTask == nil, "끝난 조회가 자리를 비우지 않아 다음 박자가 영영 막힌다")
        #expect(store.refreshAchievements(reason: .periodic) != nil)
    }

    @Test("소스 계약 — 새 타이머가 없다: 배선 파일에 sleep · Timer · asyncAfter · 루프가 없고, 조회를 부르는 자리는 지갑 sync 하나 · 받기는 화면만 부른다(주석 제외)")
    func noNewTimer() throws {
        let wiring = try v0358Code("WorkTimerStoreAchievements.swift")
        for banned in ["Task.sleep", "Timer(", "Timer.scheduled", "Timer.publish", "asyncAfter", "DispatchSource", "while ", "repeat {"] {
            #expect(!wiring.contains(banned), "도전 미션 배선에 \(banned) 이(가) 있다 — 새 타이머")
        }
        let files = ["WorkTimerStore.swift", "WorkTimerStorePoke.swift", "WorkTimerStoreWeeklyWork.swift", "CheckMenuView.swift",
                     "WorkTimerStoreAuth.swift", "CheckAchievementRows.swift", "WorkTimerStoreAchievements.swift",
                     "WorkTimerStoreMiniGame.swift"]
        let callers = try files.map { try v0358Code($0) }
        func count(_ needle: String) -> Int { callers.map { $0.components(separatedBy: needle).count - 1 }.reduce(0, +) }
        // v0.3.64: 박자가 하나 더 있다 — 게임 한 판이 서버에 남은 직후(`refreshAchievementsAfterGameResult` → `.gameResult`). 그 문은
        // 이벤트 둘(미니게임 제출 성공 1 · 1:1 판 끝남 3 = 오목 · 체스 · 테트리스)에서만 열린다. 타이머는 여전히 없다.
        // 검토 지적(2026-10-22) 뒤로 이벤트에 딸린 자리가 둘 더 있다 — 떠 있던 조회가 끝난 뒤의 '뒤따르는 한 번'(게임 결과 깃발) ·
        // 자정을 넘겨 막힌 일일 [받기](사람이 누른 순간). 둘 다 사건 하나에 많아야 1건이다.
        #expect(count("refreshAchievements(") == 5,
                "refreshAchievements 를 부르는 자리가 정의 1 + 지갑 sync · 게임 결과 · 뒤따르는 한 번 · 막힌 일일 받기 가 아니다")
        #expect(count("refreshAchievements(reason: .gameResult)") == 2 && count("refreshAchievements(reason: .missionPanel)") == 1,
                "게임 결과 박자(문 1 + 뒤따르는 한 번 1) · 막힌 일일 받기(1) 자리가 바뀌었다")
        #expect(count("refreshAchievementsAfterGameResult(game:") == 5,
                "게임 결과 박자를 부르는 자리가 정의 1 + 미니게임 제출 1 + 1:1 판 끝남 3 이 아니다")
        // 받기를 부르는 자리는 미션 화면의 맥락 하나뿐이다(스토어 어디서도 스스로 받지 않는다 — 자동 지급 금지).
        #expect(count("claimAchievement(key: $0)") == 1 && count("claimWeeklyWork()") == 2,
                "받기를 부르는 자리가 화면 말고도 있다 — 정의 1 + 호출 1 이어야 한다")
        // 일일 받기(v0.3.64)도 같다 — 화면의 맥락 하나뿐(자동 지급 금지).
        #expect(count("claimDailyMission(key: $0)") == 1 && count("claimDailyMission(key:") == 2,
                "일일 받기를 부르는 자리가 화면 말고도 있다 — 정의 1 + 호출 1 이어야 한다")
        let poke = try v0358Code("WorkTimerStorePoke.swift")
        let sync = try #require(poke.range(of: "func syncUltraWallet(reason: UltraSyncReason) {"))
        #expect(poke[sync.upperBound...].prefix(600).contains("refreshAchievements(reason: achievementsReason)"),
                "지갑 sync 본문에 도전 미션 박자가 없다")
    }
}

// MARK: - ⑥ 404 · 실패

@MainActor
@Suite(.serialized) struct V0358UnavailableTests {
    @Test("404 PGRST202 · 본문 없는 404 → 절을 조용히 감춘다(실패 아님) · 서버가 올라오면 다음 박자에 선다")
    func missingFunctionHidesTheSection() async throws {
        for (index, body) in [V0358Fixture.missingFunctionBody, ""].enumerated() {
            let (store, host) = v0358Store("404-\(index)", achievements: { call in
                call == 0 ? .init(status: 404, body: body) : .init(body: V0358Fixture.json())
            })
            await store.refreshAchievements(reason: .missionPanel)?.value
            #expect(v0358Calls(host) == 1)
            #expect(store.achievementsUnavailable, "함수 없는 서버(\(index))를 '없음'으로 안 접었다")
            #expect(!store.achievementsFailed, "함수 없는 서버(\(index))를 실패로 셌다 — 실패 문구 + [다시 시도]가 뜬다")
            #expect(AchievementSectionState.make(status: store.achievements, unavailable: store.achievementsUnavailable,
                                                 failed: store.achievementsFailed) == .hidden)
            await store.refreshAchievements(reason: .missionPanel)?.value
            #expect(!store.achievementsUnavailable && store.achievements?.missions.count == 13, "서버가 올라왔는데 절이 안 선다")
        }
    }

    @Test("5xx · 해석 실패 → 실패(감추지 않는다) · 받아 둔 값은 지우지 않는다")
    func otherFailuresAreFailures() async {
        let (store, _) = v0358Store("500", achievements: { call in
            switch call {
            case 0: return .init(status: 500, body: #"{"message":"boom"}"#)
            case 1: return .init(body: V0358Fixture.json())
            default: return .init(body: "not json")
            }
        })
        await store.refreshAchievements(reason: .missionPanel)?.value
        #expect(store.achievementsFailed && !store.achievementsUnavailable)
        #expect(AchievementSectionState.make(status: store.achievements, unavailable: store.achievementsUnavailable,
                                             failed: store.achievementsFailed) == .failed)
        await store.refreshAchievements(reason: .missionPanel)?.value
        #expect(!store.achievementsFailed && store.achievements != nil)
        await store.refreshAchievements(reason: .missionPanel)?.value
        #expect(store.achievementsFailed && store.achievements?.missions.count == 13, "실패가 알던 줄을 지웠다")
    }

    @Test("그림 — 서버에 없음은 절 없는 화면과 같고, 불러오는 중 · 실패 · 받은 줄과는 다르다")
    func hiddenRendersLikeNoSection() throws {
        func bitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
            try v0358Bitmap(CheckMenuView(store: store, previewClipsOverflowList: true))
        }
        let unavailable = try bitmap(v0358RenderStore(unavailable: true))
        let empty = try bitmap(v0358RenderStore(achievements: AchievementStatus()))
        let loading = try bitmap(v0358RenderStore())
        let failed = try bitmap(v0358RenderStore(failed: true))
        let loaded = try bitmap(v0358RenderStore(achievements: V0358Fixture.status()))
        #expect(try v0358Diff(unavailable, empty).looksSame, "서버에 없는데 절의 무언가(소제목 · 문구)를 그렸다")
        #expect(try v0358Diff(unavailable, loading).looksDifferent && v0358Diff(loading, failed).looksDifferent
                && v0358Diff(failed, loaded).looksDifferent, "절의 네 상태가 그림으로 갈리지 않는다")
    }
}

// MARK: - ⑦ 움직임

@Suite struct V0358MotionTests {
    @Test("받기 연출 곡선 — 1초 미만 · 처음엔 작게 톡 커졌다 · 끝엔 22pt 위로 작아져 사라진다 · 불투명도는 위치가 다 온 뒤에야 직선으로 깎인다")
    func burstCurve() {
        typealias C = MissionClaimBurstCurve
        #expect(C.duration < 1)
        let start = C.frame(at: 0, reduceMotion: false)
        #expect(start.offsetY == 0 && start.scale == C.popFrom && start.opacity == 1)
        let peak = C.frame(at: C.popPeakAt, reduceMotion: false)
        #expect(abs(peak.scale - C.popPeak) < 0.001 && peak.scale > 1.1, "톡 커지는 순간이 없다")
        #expect(C.frame(at: C.popSettleAt, reduceMotion: false).scale == 1)
        #expect(C.frame(at: C.shrinkStart, reduceMotion: false).scale == 1)
        let end = C.frame(at: 1, reduceMotion: false)
        #expect(end.offsetY == -C.rise && end.opacity == 0 && abs(end.scale - C.shrinkTo) < 0.0001)
        // 반투명한 큰 알약이 머물지 않는다 — 흐려지기 시작할 땐 이미 작아지는 중이고, 절반 흐릴 땐 크기가 0.6 아래다
        // (받은 줄의 "💎 +50" 칩 위에서 두 "+50"이 겹쳐 비치지 않게 — 0.75 장면 실측).
        #expect(C.shrinkStart < C.fadeStart)
        let halfFaded = C.frame(at: (C.fadeStart + 1) / 2, reduceMotion: false)
        #expect(abs(halfFaded.opacity - 0.5) < 0.0001 && halfFaded.scale < 0.6, "절반 흐린 알약이 아직 크다(\(halfFaded.scale))")
        // ★ 메모리 '이징으로 불투명도를 깎지 마라' — 위치와 같은 easeOut 으로 깎으면 절반 지점에서 이미 12% 만 남는다.
        let half = C.frame(at: C.fadeStart, reduceMotion: false)
        #expect(half.opacity == 1, "위치가 다 오기 전에 흐려지기 시작했다(\(half.opacity))")
        #expect(C.riseFraction(C.fadeStart, reduceMotion: false) >= 0.85, "흐려지기 시작할 때 위치가 아직 덜 왔다")
        // 위치가 90% 온 시점에도 거의 그대로 보인다.
        let ninety = 1 - pow(0.1, 1.0 / 3.0)   // easeOutCubic 이 0.9 가 되는 t ≈ 0.536
        #expect(C.frame(at: ninety, reduceMotion: false).opacity >= 0.9)
        // 흐려짐은 직선이다(남은 구간의 4분의 1 지점에서 정확히 0.75).
        #expect(abs(C.frame(at: C.fadeStart + (1 - C.fadeStart) / 4, reduceMotion: false).opacity - 0.75) < 0.0001)
        // 시간 밖은 자른다.
        #expect(C.frame(at: -1, reduceMotion: false) == start && C.frame(at: 2, reduceMotion: false) == end)
    }

    @Test("동작 줄이기 — 위치 · 크기 변화 없이 제자리에서 흐려지기만 한다 · 줄 · 숫자 애니메이션은 nil(바로 바뀐다)")
    func reduceMotion() {
        typealias C = MissionClaimBurstCurve
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            let frame = C.frame(at: t, reduceMotion: true)
            #expect(frame.offsetY == 0 && frame.scale == 1, "동작 줄이기인데 움직였다(t=\(t))")
            #expect(frame.opacity == C.frame(at: t, reduceMotion: false).opacity)
        }
        #expect(C.riseFraction(0.7, reduceMotion: true) == 0)
        #expect(MissionClaimMotion.rowSettle(reduceMotion: true) == nil && MissionClaimMotion.balanceTick(reduceMotion: true) == nil)
        #expect(MissionClaimMotion.rowSettle(reduceMotion: false) != nil && MissionClaimMotion.balanceTick(reduceMotion: false) != nil)
    }

    @Test("그림 — 중간 장면은 위로 올라가 있고(동작 줄이기면 제자리) · 끝 장면은 비어 있다")
    @MainActor
    func burstFrames() throws {
        func frame(_ t: Double, reduce: Bool) throws -> NSBitmapImageRep {
            try v0358Bitmap(ZStack { Color.black; MissionClaimBurstFace(amount: 50, progress: t, reduceMotion: reduce) }
                .frame(width: 120, height: 80))
        }
        func inkRows(_ bitmap: NSBitmapImageRep) -> ClosedRange<Int>? {
            let rows = (0..<80).filter { y in v0358Count(bitmap, x: 0...119, y: CGFloat(y)...CGFloat(y)) { r, g, b in g > 90 } > 4 }
            guard let lo = rows.min(), let hi = rows.max() else { return nil }
            return lo...hi
        }
        let mid = try #require(inkRows(try frame(0.45, reduce: false)), "중간 장면에 알약이 없다")
        let still = try #require(inkRows(try frame(0.45, reduce: true)), "동작 줄이기 중간 장면에 알약이 없다")
        print("[v0358] 연출 중간 장면 y \(mid) · 동작 줄이기 \(still)")
        #expect(mid.lowerBound < still.lowerBound - 12, "중간 장면이 위로 떠오르지 않았다(\(mid) vs \(still))")
        #expect(inkRows(try frame(1, reduce: false)) == nil, "끝 장면에 무언가 남았다(흐려지지 않았다)")
    }
}

// MARK: - ⑧ 그림 — 줄 · 절 · 팝오버 높이

@MainActor
@Suite(.serialized) struct V0358RenderTests {
    static func row(_ mission: AchievementStatus.Mission, inFlight: Bool = false) throws -> NSBitmapImageRep {
        try v0358Bitmap(AchievementRowView(mission: mission).frame(width: 292).background(Color.black)
            .environment(\.missionClaim, MissionClaimContext(inFlightKeys: inFlight ? [mission.key] : []))
            .environment(\.colorScheme, .dark))
    }

    static func mission(_ key: String, _ rows: [V0358Fixture.Row] = V0358Fixture.base) throws -> AchievementStatus.Mission {
        try #require(V0358Fixture.status(rows).missions.first { $0.key == key })
    }

    @Test("줄 — 채웠고 안 받음 → 오른쪽 [받기 +N](그라데이션 · 흰 글자) · 받음 → ✓ 받음(근무색) · 진행 중 → 숫자, 버튼 없음")
    func rowStates() throws {
        let claimable = try Self.row(try Self.mission("phone_login"))
        let claimed = try Self.row(try Self.mission("todo3"))
        let progress = try Self.row(try Self.mission("poke50"))
        #expect(claimable.pixelsHigh == 112 && claimed.pixelsHigh == 112 && progress.pixelsHigh == 112, "줄 높이가 56pt 가 아니다")
        let right = (x: CGFloat(196)...CGFloat(284), y: CGFloat(14)...CGFloat(42))
        let gradient = v0358GradientPixels(claimable, x: right.x, y: right.y)
        let white = v0358WhitePixels(claimable, x: right.x, y: right.y)
        print("[v0358] 받기 버튼 — 그라데이션 \(gradient) · 흰 글자 \(white) · 받음 줄 그라데이션 \(v0358GradientPixels(claimed, x: right.x, y: right.y))")
        // 버튼은 칠한 캡슐(약 87×26pt)이라 섞인 색 픽셀이 천 단위고, 버튼이 없는 줄엔 그 색이 없다.
        #expect(gradient > 1_000 && white > 60, "채운 줄에 [받기] 버튼이 안 그려졌다(\(gradient) · \(white))")
        #expect(v0358GradientPixels(claimed, x: right.x, y: right.y) < 100 && v0358GradientPixels(progress, x: right.x, y: right.y) < 100,
                "받았거나 진행 중인 줄에 버튼이 있다")
        // 받음 — 셋째 줄 오른쪽 ✓ 받음(근무색) · 진행 중은 회색 숫자.
        let caption = (x: CGFloat(236)...CGFloat(286), y: CGFloat(36)...CGFloat(54))
        #expect(v0358GreenPixels(claimed, x: caption.x, y: caption.y) >= 40, "받은 줄에 ✓ 받음이 없다")
        #expect(v0358GreenPixels(progress, x: caption.x, y: caption.y) == 0)
        // 진행 숫자가 그려진다 — 진행만 0 으로 바꾸면 그 자리가 갈린다.
        let zero = try Self.row(try Self.mission("poke50", V0358Fixture.with("poke50", progress: 0)))
        let box = try #require(v0358DiffBox(progress, zero), "진행 숫자가 안 그려진다")
        #expect(box.maxX >= 250, "진행 숫자(오른쪽 셋째 줄)가 안 갈렸다: \(box)")
        let poke50 = try Self.mission("poke50")
        // v0.3.64: 칩 글자는 "+20" — 앞의 루비는 분홍 그림(`RubyIcon`)이다(파란 💎 글자를 버렸다).
        #expect(AchievementCopy.reward(poke50) == "+20" && AchievementCopy.count(poke50) == "23/50")
    }

    @Test("받는 중(떠 있음) — 버튼이 흐려진다(같은 자리 · 그라데이션이 옅다)")
    func inFlightDimsTheButton() throws {
        let mission = try Self.mission("phone_login")
        let idle = try Self.row(mission)
        let busy = try Self.row(mission, inFlight: true)
        let right = (x: CGFloat(196)...CGFloat(284), y: CGFloat(14)...CGFloat(42))
        let idleWhite = v0358WhitePixels(idle, x: right.x, y: right.y)
        let busyWhite = v0358WhitePixels(busy, x: right.x, y: right.y)
        print("[v0358] 떠 있음 — 흰 글자 \(idleWhite) → \(busyWhite)")
        #expect(busyWhite < idleWhite / 3, "떠 있는 동안 버튼이 흐려지지 않는다(두 번 누를 수 있어 보인다)")
        #expect(try v0358Diff(idle, busy).looksDifferent)
    }

    @Test("주간 줄 — 받기 서버가 받을 것이 있다고 하면 [받기 +70] · 받은 뒤엔 없음 · 옛 서버(새 칸 없음)는 예전 그림 그대로")
    func weeklyRowClaimButton() throws {
        func bitmap(_ status: WeeklyWorkStatus) throws -> NSBitmapImageRep {
            try v0358Bitmap(WeeklyWorkRowView(status: status).frame(width: 292).background(Color.black).environment(\.colorScheme, .dark))
        }
        let right = (x: CGFloat(196)...CGFloat(284), y: CGFloat(14)...CGFloat(42))
        let claimable = try bitmap(V0358Fixture.weekly())
        let claimed = try bitmap(V0358Fixture.weekly(V0358Fixture.weeklyClaimedJSON()))
        print("[v0358] 주간 받기 — 그라데이션 \(v0358GradientPixels(claimable, x: right.x, y: right.y)) · 받은 뒤 \(v0358GradientPixels(claimed, x: right.x, y: right.y))")
        #expect(v0358GradientPixels(claimable, x: right.x, y: right.y) > 1_000, "주간 줄에 [받기]가 없다")
        #expect(v0358GradientPixels(claimed, x: right.x, y: right.y) < 100, "받은 뒤에도 [받기]가 남았다")
        // ★ 옛 서버: 새 칸만 뺀 같은 응답 = 0.3.57 그림(버튼 없음). 새 칸이 빈 받기 서버(받을 것 없음)도 같은 그림이다.
        let oldJSON = V0355WeeklyStub.json(worked: 45 * 3_600, claimed: [false, false, false])
        let old = try bitmap(try V0355WeeklyStub.decode(oldJSON))
        let noPending = try bitmap(V0358Fixture.weekly(V0358Fixture.weeklyJSON(tiers: [(20, 20, false, true), (40, 50, false, true),
                                                                                        (60, 200, false, false)], pending: [])))
        #expect(v0358GradientPixels(old, x: right.x, y: right.y) < 100, "옛 서버 응답에 [받기]가 섰다")
        #expect(try v0358Diff(old, noPending).looksSame, "받을 것이 없는 받기 서버의 줄이 옛 줄과 다르다")
    }

    @Test("절 — 받은 상태면 소제목 + 9줄(높이 = 규약) · 불러오는 중/실패는 한 줄 · 감춤은 0 · 머리에 '받을 보상 N개'")
    func sectionHeightMatchesTheLayout() throws {
        let status = V0358Fixture.status()
        let state = AchievementSectionState.make(status: status, unavailable: false, failed: false)
        func height(_ state: AchievementSectionState) throws -> CGFloat {
            CGFloat(try v0358Bitmap(AchievementSectionView(state: state).frame(width: 292)).pixelsHigh) / 2
        }
        let loaded = try height(state)
        print("[v0358] 절 높이 — 9줄 \(loaded)pt")
        #expect(loaded == AchievementSectionLayout.height(state) - AchievementSectionLayout.rowSpacing,
                "절 그림 높이(\(loaded))가 스크롤 판정의 셈과 다르다 — 창이 자라거나 빈 띠가 생긴다")
        let nineRows: CGFloat = 20 + 8 + 9 * 56 + 8 * 8
        let oneRow: CGFloat = 20 + 8 + 56
        #expect(loaded == nineRows)
        let loading = try height(.loading)
        let failed = try height(.failed)
        #expect(loading == oneRow && failed == oneRow)
        #expect(AchievementSectionLayout.height(.hidden) == 0)
        // 머리 오른쪽 "받을 보상 2개" — 받을 것이 없는 같은 절과 머리 줄(위 20pt)에서만 갈린다.
        let none = AchievementSectionState.loaded(rows: status.seriesRows, claimableCount: 0)
        let a = try v0358Bitmap(AchievementSectionView(state: state).frame(width: 292))
        let b = try v0358Bitmap(AchievementSectionView(state: none).frame(width: 292))
        let box = try #require(v0358DiffBox(a, b), "절 머리에 받을 수가 안 그려졌다")
        #expect(box.maxY <= 20 && box.minX > 150, "받을 수가 머리 오른쪽이 아니다: \(box)")
    }

    static func windowHeight(_ view: CheckMenuView) throws -> CGFloat {
        CGFloat(try v0358Bitmap(view).pixelsHigh) / 2
    }

    @Test("팝오버 높이 — 절 · 받기 · 제목 행 루비가 붙어도 스크롤 창은 v0.3.56 의 줄 상한 그대로(창이 안 자란다) · 최악 조합 ≤ 700pt")
    func heightBudget() throws {
        let achievements = V0358Fixture.status()
        let fiveRows = [V0356Fixture.lap] + (1...4).map(V0356Fixture.future)
        let capped = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(missions: fiveRows + [V0356Fixture.future(5)])))
        let withSection = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(achievements: achievements)))
        let withSectionWeekly = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(achievements: achievements,
                                                                                         weekly: V0358Fixture.weekly())))
        let without = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(unavailable: true)))
        let noRuby = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(unavailable: true, ruby: nil)))
        print("[v0358] 창 높이 — 절 없음 \(without) · 절(3시간 줄) \(withSection) · 절 + 주간 받기 \(withSectionWeekly) · v0.3.56 상한(6줄) \(capped)pt")
        #expect(withSection == capped && withSectionWeekly == capped, "절이 붙은 화면(\(withSection))이 v0.3.56 상한(\(capped))과 다르다")
        #expect(withSection > without, "절이 안 그려졌거나 스크롤 창이 줄었다")
        #expect(noRuby == without, "제목 행 루비 칩이 제목 행 높이를 바꿨다")
        let withNotice = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(achievements: achievements,
                                                                                  notice: V0358Fixture.lapNotice)))
        let cappedNotice = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(missions: fiveRows + [V0356Fixture.future(5)],
                                                                                    notice: V0358Fixture.lapNotice)))
        print("[v0358] 안내줄 — 절 \(withNotice) · v0.3.56 상한 \(cappedNotice)pt")
        #expect(withNotice == cappedNotice)
        for (banner, editing) in [(false, false), (true, false), (true, true), (false, true)] {
            let store = v0358RenderStore(achievements: achievements, weekly: V0358Fixture.weekly(), notice: V0358Fixture.lapNotice)
            let h = try Self.windowHeight(CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: editing,
                                                        previewUpdateBanner: banner, previewUpdateNotes: banner ? ["a", "b", "c", "d"] : []))
            let hs = try Self.windowHeight(CheckMenuView(store: store, previewGoalEditing: editing,
                                                         previewUpdateBanner: banner, previewUpdateNotes: banner ? ["a", "b", "c", "d"] : []))
            print("[v0358] 최악(배너 \(banner) · 편집 \(editing)) = 클립 \(h) · 스크롤 \(hs)pt")
            #expect(h <= 700 && hs <= 700, "절이 붙은 미션 화면 \(h)/\(hs)pt — 상한을 넘어 푸터가 잘린다")
            #expect(h == hs, "클립(스냅샷) 그림과 실제(스크롤) 높이가 갈렸다 — 스냅샷이 화면을 말하지 않는다")
        }
    }

    @Test("빈 띠 없음 — 절이 붙은 미션 화면에서 본문 카드가 푸터 바로 위까지 닿는다(틈 = 간격 10pt)")
    func noEmptyBand() throws {
        for (label, store) in [("절", v0358RenderStore(achievements: V0358Fixture.status())),
                               ("절 불러오는 중", v0358RenderStore()),
                               ("절 + 주간 받기 + 안내", v0358RenderStore(achievements: V0358Fixture.status(), weekly: V0358Fixture.weekly(),
                                                                    notice: V0358Fixture.lapNotice))] {
            let bitmap = try v0358Bitmap(CheckMenuView(store: store, previewClipsOverflowList: true))
            let runs = v0358CardRuns(bitmap)
            let gap = runs.count >= 2 ? runs[runs.count - 1].top - runs[runs.count - 2].bottom : -1
            print("[v0358] \(label): 창 \(CGFloat(bitmap.pixelsHigh) / 2)pt · 카드 \(runs.map { "\($0.top)…\($0.bottom)" }) · 푸터 위 틈 \(gap)pt")
            #expect(runs.count >= 3, "\(label): 카드 구간 \(runs.count)개 — 자가 카드를 못 가른다")
            #expect(gap >= 9 && gap <= 12, "\(label): 본문 카드와 푸터 사이 \(gap)pt — 빈 띠")
        }
    }

    @Test("미션 화면 — 절이 기존 줄(3시간) 아래에 선다 · 첫 줄(폰 로그인)의 [받기]가 보인다 · 제목 행에 루비 잔량")
    func panelShowsTheSection() throws {
        func bitmap(_ status: AchievementStatus, lap: MissionProgress = V0356Fixture.lap, ruby: Int? = 1234,
                    line: Int = #line) throws -> NSBitmapImageRep {
            try v0358Bitmap(CheckMenuView(store: v0358RenderStore(achievements: status, missions: [lap], ruby: ruby, line: line),
                                          previewClipsOverflowList: true))
        }
        let fresh = try bitmap(V0358Fixture.status(V0358Fixture.fresh))
        let mixed = try bitmap(V0358Fixture.status())
        let lapMoved = try bitmap(V0358Fixture.status(V0358Fixture.fresh),
                                  lap: MissionProgress(kind: .todayThreeHours, progress: 0.9, claimedToday: false, cappedToday: false,
                                                       detail: "다음 하나까지 18분"))
        #expect(fresh.pixelsHigh == mixed.pixelsHigh, "전제: 둘 다 스크롤 상한 높이")
        // 본문 열(x < 330pt)만 견준다 — 받을 것이 생기면 레일 [미션] 칸 배지도 함께 바뀐다(그건 배지 스위트가 잰다).
        let section = try #require(v0358DiffBox(fresh, mixed, maxX: 330), "절의 줄이 미션 화면에 안 그려졌다")
        let lap = try #require(v0358DiffBox(fresh, lapMoved, maxX: 330), "대조군 실패 — 3시간 줄이 안 그려졌다")
        print("[v0358] 3시간 줄 차이 y \(lap.minY)…\(lap.maxY) · 절 차이 y \(section.minY)…\(section.maxY)pt")
        #expect(section.minY > lap.maxY, "절이 기존 줄(3시간) 위에 섰다")
        #expect(v0358GradientPixels(mixed, x: 200...330, y: section.minY...(section.minY + 90)) > 1_000,
                "절 첫 줄(폰 로그인)의 [받기]가 화면에서 안 보인다")
        // 제목 행 루비 — 잔량만 바꾸면 제목 행(위쪽 패널 머리)에서만 갈린다.
        let ruby = try #require(v0358DiffBox(mixed, try bitmap(V0358Fixture.status(), ruby: 9)), "제목 행에 루비 잔량이 없다")
        #expect(ruby.maxY < lap.minY && ruby.minX > 200, "루비 잔량이 제목 행 오른쪽이 아니다: \(ruby)")
    }

    @Test("배선 — 미션 화면이 받은 맥락의 동작이 스토어 받기를 부른다(도전 미션 키 · 주간 전부) · 떠 있음 · 연출이 그대로 내려간다")
    func panelClaimContextIsWired() async throws {
        let (store, host) = v0358Store("wire-claim")
        store.isMenuPresented = true
        store.toggleMissionPanel()
        store.applyAchievements(V0358Fixture.status())
        store.applyWeeklyWork(V0358Fixture.weekly())
        store.achievementClaimsInFlight = ["team3"]
        store.missionClaimBursts = [MissionClaimBurst.weeklyTarget: .init(serial: 7, target: MissionClaimBurst.weeklyTarget, amount: 70)]
        let panel = try V0356ReviewFixTests.panelNode("MissionPanel", in: store)
        let context = try #require(v0358Child("claim", of: panel) as? MissionClaimContext, "미션 화면에 받기 맥락이 안 넘어갔다")
        #expect(context.inFlightKeys == ["team3"] && context.isInFlight("team3") && !context.isInFlight("phone_login"))
        #expect(context.bursts[MissionClaimBurst.weeklyTarget]?.serial == 7)
        #expect(v0358Child("rubyBalance", of: panel) as? Int == store.rubyBalance && store.rubyBalance != nil)
        store.achievementClaimsInFlight = []
        context.claimAchievement("phone_login")
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host, "achievement_claim") == 1 }, "[받기]가 받기를 안 부른다")
        #expect(GomokuStubProtocol.calls(host: host, rpc: "achievement_claim").first?.body == #"{"p_key":"phone_login"}"#)
        context.claimWeekly()
        #expect(await V0354CoreStub.waitUntil { v0358Calls(host, "weekly_work_claim") == 1 }, "주간 [받기]가 주간 받기를 안 부른다")
        // 실패 표시도 그대로 내려간다(그 줄이 실패를 그리는 유일한 길이다).
        store.achievementClaimFailedKeys = ["team3"]
        store.weeklyClaimFailed = true
        let failed = try #require(v0358Child("claim", of: try V0356ReviewFixTests.panelNode("MissionPanel", in: store)) as? MissionClaimContext)
        #expect(failed.hasFailed("team3") && !failed.hasFailed("phone_login") && failed.weeklyFailed)
    }

    // ── 받기 실패는 그 줄 안에서(검토 지적 2026-10-19) ──

    @Test("줄 — 받기가 실패하면 보조 문장 자리가 주황 실패 문장으로 바뀌고 [받기]는 그대로 · 받은 줄엔 실패 표시가 서지 않는다")
    func failedClaimShowsInTheRow() throws {
        func row(_ mission: AchievementStatus.Mission, failed: Set<String>) throws -> NSBitmapImageRep {
            try v0358Bitmap(AchievementRowView(mission: mission).frame(width: 292).background(Color.black)
                .environment(\.missionClaim, MissionClaimContext(failedKeys: failed))
                .environment(\.colorScheme, .dark))
        }
        let phone = try Self.mission("phone_login")
        let idle = try row(phone, failed: [])
        let failed = try row(phone, failed: ["phone_login"])
        let caption = (x: CGFloat(40)...CGFloat(200), y: CGFloat(36)...CGFloat(54))
        let button = (x: CGFloat(196)...CGFloat(284), y: CGFloat(14)...CGFloat(42))
        print("[v0358] 실패 줄 — 주황 \(v0358AmberPixels(idle, x: caption.x, y: caption.y)) → \(v0358AmberPixels(failed, x: caption.x, y: caption.y)) · 버튼 \(v0358GradientPixels(failed, x: button.x, y: button.y))")
        #expect(v0358AmberPixels(idle, x: caption.x, y: caption.y) == 0)
        #expect(v0358AmberPixels(failed, x: caption.x, y: caption.y) > 60, "받기가 실패한 줄에 실패 문장이 없다")
        #expect(v0358GradientPixels(failed, x: button.x, y: button.y) > 1_000, "실패한 줄에서 [받기]가 사라졌다(다시 누를 수 없다)")
        // 바뀌는 것은 셋째 줄(보조 문장)뿐이다 — 줄 높이 · 제목 · 바 · 버튼은 그대로.
        let box = try #require(v0358DiffBox(idle, failed), "실패 표시가 안 그려졌다")
        #expect(failed.pixelsHigh == idle.pixelsHigh && box.minY >= 34 && box.maxX < 200, "실패 표시가 보조 문장 자리 밖을 바꿨다: \(box)")
        // 받은 줄(또는 진행 중)에 남은 실패 표시는 그리지 않는다(그 사이 다른 기기에서 받았을 수 있다).
        let todo = try Self.mission("todo3")
        #expect(try v0358Diff(try row(todo, failed: []), try row(todo, failed: ["todo3"])).looksSame)
    }

    @Test("주간 줄 — 받기가 실패하면 보조 문장 자리가 주황 실패 문장으로 바뀌고 [받기 +70]은 그대로")
    func failedWeeklyClaimShowsInTheRow() throws {
        func row(failed: Bool) throws -> NSBitmapImageRep {
            try v0358Bitmap(WeeklyWorkRowView(status: V0358Fixture.weekly()).frame(width: 292).background(Color.black)
                .environment(\.missionClaim, MissionClaimContext(weeklyFailed: failed))
                .environment(\.colorScheme, .dark))
        }
        let idle = try row(failed: false)
        let failed = try row(failed: true)
        let caption = (x: CGFloat(40)...CGFloat(200), y: CGFloat(36)...CGFloat(54))
        let button = (x: CGFloat(196)...CGFloat(284), y: CGFloat(14)...CGFloat(42))
        print("[v0358] 주간 실패 줄 — 주황 \(v0358AmberPixels(failed, x: caption.x, y: caption.y)) · 버튼 \(v0358GradientPixels(failed, x: button.x, y: button.y))")
        #expect(v0358AmberPixels(idle, x: caption.x, y: caption.y) == 0)
        #expect(v0358AmberPixels(failed, x: caption.x, y: caption.y) > 60, "주간 받기가 실패한 줄에 실패 문장이 없다")
        #expect(v0358GradientPixels(failed, x: button.x, y: button.y) > 1_000, "실패한 주간 줄에서 [받기]가 사라졌다")
        let box = try #require(v0358DiffBox(idle, failed))
        #expect(failed.pixelsHigh == idle.pixelsHigh && box.minY >= 34, "실패 표시가 보조 문장 자리 밖을 바꿨다: \(box)")
    }

    @Test("미션 화면 — 받기가 실패해도(스토어 길 그대로) 창 높이 · 절의 줄 자리가 그대로고, 바뀌는 것은 실패한 그 줄의 보조 문장뿐이다")
    func failedClaimDoesNotShiftTheSection() async throws {
        // 검토 지적(2026-10-19) 재현: 예전엔 실패가 안내줄(26pt)로 절 위에 끼어 절의 줄이 모두 26pt 밀리고 창이 38pt 줄었다.
        func bitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
            try v0358Bitmap(CheckMenuView(store: store, previewClipsOverflowList: true))
        }
        let status = V0358Fixture.status()
        let weekly = V0358Fixture.weekly()
        let plain = try bitmap(v0358RenderStore(achievements: status, weekly: weekly))
        let phoneFails = v0358RenderStore(achievements: status, weekly: weekly, claimsFail: true)
        await phoneFails.claimAchievement(key: "phone_login")?.value
        let weeklyFails = v0358RenderStore(achievements: status, weekly: weekly, claimsFail: true)
        await weeklyFails.claimWeeklyWork()?.value
        #expect(phoneFails.missionNotice == nil && weeklyFails.missionNotice == nil, "받기 실패가 안내줄을 띄웠다")
        for (label, store) in [("도전 미션", phoneFails), ("주간", weeklyFails)] {
            let failed = try bitmap(store)
            let box = try #require(v0358DiffBox(plain, failed, maxX: 330), "\(label): 실패가 화면에 안 나타났다")
            let amber = v0358AmberPixels(failed, x: box.minX...box.maxX, y: box.minY...box.maxY)
            print("[v0358] \(label) 받기 실패 — 창 \(CGFloat(plain.pixelsHigh) / 2) → \(CGFloat(failed.pixelsHigh) / 2)pt · 차이 \(box) · 주황 \(amber)")
            #expect(failed.pixelsHigh == plain.pixelsHigh, "\(label): 받기 실패가 창 높이를 바꿨다")
            #expect(box.height <= 18, "\(label): 받기 실패가 한 줄의 보조 문장보다 넓게 바꿨다(줄이 밀렸다): \(box)")
            #expect(amber > 60, "\(label): 바뀐 자리에 실패 문장이 없다")
        }
    }

    // ── 동작 줄이기가 줄까지 내려간다(검토 지적 2026-10-19 — 곡선만 시험하고 배선은 안 쟀다) ──

    @Test("동작 줄이기 배선 — 줄이 그린 연출이 동작 줄이기면 제 크기 · 제자리, 아니면 작게(0.7) 시작해 위로 떠오른다 · 도전 미션 줄 · 주간 줄 둘 다")
    func reduceMotionReachesTheRows() throws {
        // ImageRenderer 는 onAppear 의 애니메이션을 끝값(불투명도 0)으로 굽는다 — 장면을 멈춰(`frozenBurstProgress`) 줄의 배선을 그대로 거친다.
        let claimedAchievement = try Self.mission("todo3")
        let achievementTarget = MissionClaimBurst.achievementTarget(series: claimedAchievement.series)
        let claimedWeekly = V0358Fixture.weekly(V0358Fixture.weeklyClaimedJSON())
        func render(_ row: some View, target: String?, reduce: Bool, at t: Double) throws -> NSBitmapImageRep {
            let bursts = target.map { [$0: MissionClaimBurst(serial: 1, target: $0, amount: 50)] } ?? [:]
            return try v0358Bitmap(row.frame(width: 292).background(Color.black)
                .environment(\.missionClaim, MissionClaimContext(bursts: bursts, reduceMotion: reduce, frozenBurstProgress: t))
                .environment(\.colorScheme, .dark))
        }
        for (label, target) in [("도전 미션", achievementTarget), ("주간", MissionClaimBurst.weeklyTarget)] {
            func row(_ burst: Bool, reduce: Bool, at t: Double = 0) throws -> NSBitmapImageRep {
                if label == "주간" {
                    return try render(WeeklyWorkRowView(status: claimedWeekly), target: burst ? target : nil, reduce: reduce, at: t)
                }
                return try render(AchievementRowView(mission: claimedAchievement), target: burst ? target : nil, reduce: reduce, at: t)
            }
            let plain = try row(false, reduce: false)
            // 첫 장면(진행 0): 보통은 0.7 배에서 톡 커지고, 동작 줄이기는 제 크기로 선다 — 폭이 약 30% 갈린다.
            let moving = try #require(v0358DiffBox(plain, try row(true, reduce: false)), "\(label): 연출 첫 장면이 안 그려졌다")
            let still = try #require(v0358DiffBox(plain, try row(true, reduce: true)), "\(label): 동작 줄이기 연출 첫 장면이 안 그려졌다")
            // 중간 장면(0.45): 보통은 위로 18pt 남짓 떠 있고, 동작 줄이기는 제자리다.
            let risen = try #require(v0358DiffBox(plain, try row(true, reduce: false, at: 0.45)), "\(label): 연출 중간 장면이 안 그려졌다")
            let stays = try #require(v0358DiffBox(plain, try row(true, reduce: true, at: 0.45)), "\(label): 동작 줄이기 중간 장면이 안 그려졌다")
            print("[v0358] \(label) 연출 — 첫 장면 폭 보통 \(moving.width) · 동작 줄이기 \(still.width)pt · 중간 장면 위 끝 보통 \(risen.minY) · 동작 줄이기 \(stays.minY)pt")
            #expect(moving.width < still.width * 0.85, "\(label): 줄이 동작 줄이기를 연출에 안 넘긴다(첫 장면 크기가 같다)")
            #expect(abs(moving.width - still.width * MissionClaimBurstCurve.popFrom) < 6,
                    "\(label): 보통 첫 장면이 0.7 배가 아니다(\(moving.width) vs \(still.width))")
            #expect(risen.minY < stays.minY - 12, "\(label): 줄이 동작 줄이기를 연출에 안 넘긴다(중간 장면 자리가 같다)")
        }
    }

    @Test("소스 계약 — 두 줄 모두 줄 자리잡기 · 연출에 동작 줄이기 값을 넘긴다(글자 그대로의 참/거짓이 없다 · 주석 제외)")
    func rowsPassReduceMotionThrough() throws {
        func body(_ file: String, _ start: String) throws -> String {
            let code = try v0358Code(file)
            let head = try #require(code.range(of: start), "\(file): \(start) 를 못 찾았다")
            // 걷어낸 소스는 공백이 한 칸으로 접힌다 — 다음 형 선언(struct · enum · extension)까지가 이 줄의 본문이다.
            let rest = code[head.upperBound...]
            let end = [" struct ", " enum ", " extension "].compactMap { rest.range(of: $0)?.lowerBound }.min() ?? rest.endIndex
            return String(rest[..<end])
        }
        for (file, start) in [("CheckAchievementRows.swift", "struct AchievementRowView: View {"),
                              ("CheckMenuView.swift", "struct WeeklyWorkRowView: View {")] {
            let row = try body(file, start)
            #expect(row.contains("let reduces = claim.reduceMotion ?? systemReduceMotion"), "\(start): 동작 줄이기를 고르는 자리가 없다")
            #expect(row.contains("MissionClaimMotion.rowSettle(reduceMotion: reduces)"), "\(start): 자리잡기가 동작 줄이기를 안 따른다")
            #expect(row.contains("MissionClaimBurstView(amount: burst.amount, reduceMotion: reduces)"), "\(start): 연출이 동작 줄이기를 안 따른다")
            for literal in ["reduceMotion: false", "reduceMotion: true"] {
                #expect(!row.contains(literal), "\(start): 동작 줄이기 자리에 글자 그대로의 \(literal)")
            }
        }
    }

    // ── 첫 열기 높이(검토 지적 2026-10-19) ──

    @Test("첫 열기 — 도전 미션이 오기 전(불러오는 중) · 한 번도 못 받은 실패 · 받은 뒤의 창 높이가 같다 · 서버에 없음만 접힌다")
    func loadingReservesTheLoadedHeight() throws {
        for weekly in [nil, V0358Fixture.weekly()] as [WeeklyWorkStatus?] {
            let label = weekly == nil ? "주간 없음" : "주간 있음"
            let loading = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(weekly: weekly)))
            let failed = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(failed: true, weekly: weekly)))
            let loaded = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(achievements: V0358Fixture.status(), weekly: weekly)))
            let hidden = try Self.windowHeight(CheckMenuView(store: v0358RenderStore(unavailable: true, weekly: weekly)))
            print("[v0358] \(label) 창 높이 — 불러오는 중 \(loading) · 실패 \(failed) · 받음 \(loaded) · 서버에 없음 \(hidden)pt")
            #expect(loading == loaded, "\(label): 첫 열기 \(loading)pt 가 답이 오면 \(loaded)pt 로 바뀐다(팝오버가 자란다)")
            #expect(failed == loaded, "\(label): 실패 \(failed)pt ↔ 다시 묻는 중 · 받음 \(loaded)pt 사이에 팝오버가 흔들린다")
            #expect(hidden < loaded, "\(label): 서버에 없음(\(hidden))이 절 자리를 비우지 않았다")
        }
        #expect(AchievementSectionState.loading.reservesViewport && AchievementSectionState.failed.reservesViewport)
        #expect(!AchievementSectionState.hidden.reservesViewport
                && !AchievementSectionState.loaded(rows: [], claimableCount: 0).reservesViewport)
    }
}

// MARK: - 미리보기(환경변수가 있을 때만 — 창은 띄우지 않는다)

@MainActor
@Suite(.serialized) struct V0358StillsTests {
    @Test("미리보기 PNG(CHECK_V0358_STILLS_DIR) — 미션 화면(섞인 상태 · 주간 받기 +70) · 받기 연출 중간 장면 · 절 전체 · 레일 배지, 어둡게/밝게")
    func stills() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_V0358_STILLS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func save(_ name: String, _ view: some View, scheme: ColorScheme) throws {
            try v0358PNG(view.environment(\.colorScheme, scheme))
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
        let status = V0358Fixture.status()
        let weekly = V0358Fixture.weekly()
        for scheme in [ColorScheme.dark, .light] {
            let offset = scheme == .dark ? 0 : 1
            let panel = v0358RenderStore(achievements: status, weekly: weekly, line: 900 + offset)
            try save("1-mission-panel", CheckMenuView(store: panel, previewClipsOverflowList: true), scheme: scheme)
            try save("2-section-all-rows",
                     AchievementSectionView(state: .make(status: status, unavailable: false, failed: false))
                        .frame(width: 292).padding(12).background(CheckTheme.panel), scheme: scheme)
            // 받기 연출 — 폰 로그인을 막 받았다(줄은 ✓ 받음으로 자리 잡았고 "+50" 알약이 떠오르는 중). 0.15 · 0.45 · 0.75 · 0.9 네 장면.
            let after = V0358Fixture.status(V0358Fixture.with("phone_login", claimed: true))
            let afterRow = try #require(after.missions.first)
            for t in [0.15, 0.45, 0.75, 0.9] {
                let scene = ZStack(alignment: .trailing) {
                    AchievementRowView(mission: afterRow)
                    MissionClaimBurstFace(amount: 50, progress: t).padding(.trailing, 12)
                }
                .frame(width: 292).padding(12).background(CheckTheme.panel)
                try save("3-claim-moment-t\(Int(t * 100))", scene, scheme: scheme)
            }
            let before = try #require(status.missions.first)
            try save("3-claim-moment-before", AchievementRowView(mission: before).frame(width: 292).padding(12).background(CheckTheme.panel),
                     scheme: scheme)
            try save("4-weekly-row-claim", VStack(spacing: 8) {
                WeeklyWorkRowView(status: weekly)
                WeeklyWorkRowView(status: V0358Fixture.weekly(V0358Fixture.weeklyClaimedJSON()))
            }.frame(width: 292).padding(12).background(CheckTheme.panel), scheme: scheme)
            let home = v0358RenderStore(achievements: status, weekly: weekly, mission: false, line: 920 + offset)
            try save("5-home-rail-badge", CheckMenuView(store: home, previewClipsOverflowList: true), scheme: scheme)
            // 받기 실패 — 그 줄의 보조 문장 자리(검토 지적 2026-10-19 뒤 · 안내줄 없음).
            try save("6-claim-failed-rows", VStack(spacing: 8) {
                WeeklyWorkRowView(status: weekly)
                AchievementRowView(mission: before)
            }
            .environment(\.missionClaim, MissionClaimContext(failedKeys: [before.key], weeklyFailed: true))
            .frame(width: 292).padding(12).background(CheckTheme.panel), scheme: scheme)
        }
    }
}
