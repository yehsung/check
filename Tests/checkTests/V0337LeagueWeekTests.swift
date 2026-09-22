import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.37 — 팀 리그 **지난 주 보기**(6주 전까지). 서버 계약은 supabase/migrations/20260921213000_team_weekly_history.sql.
//
// 이 파일이 지키는 것 다섯:
//  ① 네비게이터 순수 계약 — 0~6 클램프 · 현재 주 판정 · 라벨 · **주 롤오버**.
//  ② 스토어 — 주를 바꾸면 요청 본문에 p_week_offset 이 실린다 · 주별 캐시 · 실패/취소 · **옛 서버 폴백**.
//  ③ **리그를 여는 모든 길이 이번 주로 되돌린다** — 레일 토글 · 뒤로 · **팝오버 재오픈** · **주 롤오버**.
//     (재오픈과 롤오버가 비어 있던 것이 v0.3.37 배포 차단 A-1 이었다: 월요일이 지나면 기본 화면이 지난주로
//      굳고, 굳은 화면이 **주 경계 전에 받은 이번 주 숫자**를 과거 주 문구로 적었다.)
//  ④ 화면 문구(2026-09-22 맥·폰 합의) — 과거 주는 '근무 중' 조각을 **아예 빼고** "N명 중 M명 참여"로 말한다 ·
//     보조 줄은 정확히 "인원은 그 주 기준이에요" 하나 · 실패엔 [다시 시도] · 창 높이 예산(≤700pt).
//  ⑤ 이번 주 화면의 불변 — 문구가 **리터럴로** 그대로고, 주를 오갔다 돌아와도 **픽셀이 같다**(잔여 상태가 없다).

// MARK: - 도구

/// 격리 defaults. 이름을 테스트 신원에서 뽑아 `CheckTestScratch.root`($TMPDIR)에 둔다 —
/// UUID 이름은 실행마다 ~/Library/Preferences 에 plist 를 하나씩 영구히 남긴다(그 파일 주석의 2026-09-22 사고).
/// 한 테스트가 스토어를 둘 이상 만들면 `label` 로 갈라라(안 갈면 뒤에 만든 쪽이 앞선 쪽을 비운다).
private func v0337Defaults(_ label: String = "", function: String = #function) -> UserDefaults {
    CheckTestScratch.defaults(label, function: function)
}

@MainActor
private func v0337TokenStore(_ label: String = "", function: String = #function) -> TokenUsageStore {
    // 스토어의 defaults 와 **다른** 스위트다 — 같은 이름이면 나중에 만든 쪽이 앞선 쪽을 비운다.
    let scratch = CheckTestScratch.directory(label + "-token", function: function)
    return TokenUsageStore(
        defaults: v0337Defaults(label + "-token", function: function),
        homeDirectory: scratch.appendingPathComponent("home", isDirectory: true),
        cacheURL: scratch.appendingPathComponent("cache.json", isDirectory: false)
    )
}

/// 네트워크가 붙은 스토어(스텁 호스트). host 로 서버 성질(새 서버·옛 서버)을 고른다.
@MainActor
private func v0337NetworkStore(host: String, label: String = "",
                               function: String = #function) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: v0337Defaults(label, function: function),
        tokenUsage: v0337TokenStore(label, function: function)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

/// 렌더용 스토어. 기본은 값을 직접 심는 용도(조회를 한 번도 안 부른다)이고, `host` 를 주면 스텁 네트워크가 붙는다.
///
/// ★ `host` 를 **반드시** 줘야 하는 경우가 하나 있다: `stepLeagueWeek` 를 부르는 테스트다. 그 함수는 주를 옮긴 뒤
///   `loadLeaderboard()` 로 Task 를 발사하는데, 스텁이 없으면 그 Task 가 **운영 서버로 실제 요청을 보낸다**
///   (그리고 실패 문구가 화면에 남아 픽셀 비교가 흔들린다).
@MainActor
private func v0337RenderStore(now: Date, host: String? = nil, label: String = "",
                              function: String = #function) -> WorkTimerStore {
    let service = host.map {
        SupabaseWorkService(
            projectURL: URL(string: "http://\($0)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
    } ?? SupabaseWorkService()
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: v0337Defaults(label, function: function),
        tokenUsage: v0337TokenStore(label, function: function)
    )
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.isLeaderboardVisible = true
    // 보고 있는 주도 **픽스처 시계**로 맞춘다. 스토어 기본값은 실제 '지금'이라, 이 파일을 다음 주에 돌리면
    // 제목이 "이번 주" 대신 날짜가 되어 렌더 단언이 통째로 흔들린다(시각 의존 테스트를 만들지 않는다).
    store.leagueWeekKey = TeamLeagueWeekNavigator.currentKey(now)
    store.leagueWeekAnchor = store.leagueWeekKey
    return store
}

/// **폭을 밖에서 강제하지 않는다**(2026-09-10 규약). CheckMenuView 는 자기 폭을 스스로 정한다 —
/// 메인 화면 414(본문 316 + 오른쪽 레일 64), 로그인·무소속 340. `.frame(width: 340)` 을 씌우면 414 짜리 내용이
/// 340 안에 가운데 정렬로 넘쳐 그림의 x=0 이 콘텐츠 x=-37pt 가 되고, 픽셀을 읽는 단언이 통째로 헛것을 본다.
@MainActor
private func v0337RenderPNG<Content: View>(_ content: Content, scale: CGFloat = 2) throws -> Data {
    let renderer = ImageRenderer(content: content.fixedSize())
    renderer.scale = scale
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

/// 픽셀 비교는 **해시로** 한다(CheckMenuRenderTests 와 같은 이유 — 실패할 때 차분 계산으로 스위트가 멎는다).
private func v0337Digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// 투명하지 않은 픽셀 수. "둘 다 비어 있지 않다"를 먼저 보지 않으면 빈 이미지끼리의 비교가 언제나 통과한다
/// (ImageRenderer 가 어떤 뷰를 통째로 못 그린 사례가 이 저장소에 있다 — Menu 를 노란 상자로 그린 건).
private func v0337Ink(_ png: Data) throws -> Int {
    let bitmap = try #require(NSBitmapImageRep(data: png))
    let pointer = try #require(bitmap.bitmapData)
    guard bitmap.samplesPerPixel == 4 else { return bitmap.pixelsWide * bitmap.pixelsHigh }
    var ink = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide where pointer[y * bitmap.bytesPerRow + x * 4 + 3] > 12 {
            ink += 1
        }
    }
    return ink
}

@MainActor
private func v0337Save(_ png: Data, name: String) {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_V0337_SHOT_DIR"] else { return }
    let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
    try? png.write(to: url)
    print("[v0337] \(url.path)")
}

/// 픽스처 주(KST 월요일 기준 고정 시각). 2026-09-21 은 월요일이라 그 주의 키가 곧 2026-09-21 이다.
private let v0337Now = Date(timeIntervalSince1970: 1_790_038_800)   // 2026-09-22(화) 10:00 KST — 그 주 월요일은 2026-09-21

// MARK: - ① 네비게이터 순수 계약

@Test
func v0337_주_네비게이터는_0에서_6으로_접는다() {
    let current = TeamLeagueWeekNavigator.currentKey(v0337Now)

    // 현재 주 = 오프셋 0, ▸ 비활성 · ◂ 활성.
    #expect(TeamLeagueWeekNavigator.offset(forKey: current, now: v0337Now) == 0)
    #expect(TeamLeagueWeekNavigator.isCurrentWeek(current, now: v0337Now))
    #expect(!TeamLeagueWeekNavigator.canStepForward(from: current, now: v0337Now))
    #expect(TeamLeagueWeekNavigator.canStepBack(from: current, now: v0337Now))

    // ◂ 를 여섯 번 누르면 6주 전에 닿고, **일곱 번째는 값이 안 바뀐다**(서버 상한과 같은 눈금).
    var key = current
    for step in 1...6 {
        key = TeamLeagueWeekNavigator.step(key, by: -1, now: v0337Now)
        #expect(TeamLeagueWeekNavigator.offset(forKey: key, now: v0337Now) == step)
    }
    #expect(!TeamLeagueWeekNavigator.canStepBack(from: key, now: v0337Now))
    #expect(TeamLeagueWeekNavigator.step(key, by: -1, now: v0337Now) == key, "6주 상한 너머로 갔다")

    // ▸ 로 되짚어 오면 정확히 이번 주로 돌아오고, 한 번 더 눌러도 미래로 못 간다.
    for _ in 1...6 { key = TeamLeagueWeekNavigator.step(key, by: 1, now: v0337Now) }
    #expect(key == current)
    #expect(TeamLeagueWeekNavigator.step(key, by: 1, now: v0337Now) == current, "이번 주 너머(미래)로 갔다")

    // 오프셋 직접 지정도 같은 눈금으로 접는다(서버가 접는 것과 값이 어긋나면 제목이 거짓말을 한다).
    #expect(TeamLeagueWeekNavigator.clamp(99) == 6)
    #expect(TeamLeagueWeekNavigator.clamp(-3) == 0)
    #expect(TeamLeagueWeekNavigator.key(offset: 99, now: v0337Now) == TeamLeagueWeekNavigator.key(offset: 6, now: v0337Now))
    #expect(TeamLeagueWeekNavigator.key(offset: -3, now: v0337Now) == current)

    // 못 읽는 키는 이번 주로 접는다(화면이 빈 채로 굳지 않게).
    #expect(TeamLeagueWeekNavigator.offset(forKey: "쓰레기", now: v0337Now) == 0)
    #expect(TeamLeagueWeekNavigator.isCurrentWeek("", now: v0337Now))
}

@Test
func v0337_주_키는_월요일이고_라벨은_그_날짜로_말한다() {
    let current = TeamLeagueWeekNavigator.currentKey(v0337Now)
    let start = try! #require(TeamLeagueWeekNavigator.date(forKey: current))
    // KST 월요일(주 시작)이어야 한다 — 서버 week_start 와 같은 경계.
    #expect(TeamWeeklyGoal.kstCalendar.component(.weekday, from: start) == 2, "주 키가 월요일이 아니다: \(current)")
    #expect(current == "2026-09-21")

    // 이번 주 라벨은 **"이번 주"** 그대로다 — 제목 "팀별 이번 주" 가 한 글자도 안 바뀐다(회귀 금지).
    #expect(TeamLeagueWeekNavigator.displayTitle(current, now: v0337Now) == "이번 주")

    // 과거 주는 그 주 월요일 날짜로 말한다.
    #expect(TeamLeagueWeekNavigator.displayTitle(TeamLeagueWeekNavigator.key(offset: 1, now: v0337Now), now: v0337Now) == "9월 14일 주")
    #expect(TeamLeagueWeekNavigator.displayTitle(TeamLeagueWeekNavigator.key(offset: 6, now: v0337Now), now: v0337Now) == "8월 10일 주")

    // 해가 다르면 연도를 붙인다(토큰 순위판 displayTitle 과 같은 규칙).
    #expect(TeamLeagueWeekNavigator.displayTitle("2025-12-29", now: v0337Now) == "2025년 12월 29일 주")
}

@Test
func v0337_주가_넘어가면_같은_키가_한_칸_뒤로_밀린다_그래서_오프셋을_들지_않는다() {
    // 이 테스트가 곧 **오프셋 대신 절대 주 키를 드는 이유**다.
    let lastWeekKey = TeamLeagueWeekNavigator.key(offset: 1, now: v0337Now)
    #expect(TeamLeagueWeekNavigator.offset(forKey: lastWeekKey, now: v0337Now) == 1)

    // 일주일 뒤(월요일 0시를 넘긴 뒤)에 **같은 키**를 물으면 2주 전이 된다 — 보던 주가 그대로 남는다는 뜻이다.
    let nextWeek = v0337Now.addingTimeInterval(7 * 24 * 3600)
    #expect(TeamLeagueWeekNavigator.offset(forKey: lastWeekKey, now: nextWeek) == 2)
    #expect(TeamLeagueWeekNavigator.displayTitle(lastWeekKey, now: v0337Now) == TeamLeagueWeekNavigator.displayTitle(lastWeekKey, now: nextWeek))

    // 오프셋을 들었다면 같은 1 이 **다른 주**를 가리켰을 것이다(대조군 — 기준선이 실제로 다르다).
    #expect(TeamLeagueWeekNavigator.key(offset: 1, now: v0337Now) != TeamLeagueWeekNavigator.key(offset: 1, now: nextWeek))
}

// MARK: - ① 표시 재료(코어) — 내 팀이 그 주에 없었다

@Test
func v0337_과거_주에_내_팀이_없으면_코어가_그_사실을_낸다() {
    let mine = "my-team"
    let rows = [
        TeamLeaderboardEntry(id: "a", name: "가팀", weeklyGoalHours: 40, totalSeconds: 3600, workingCount: 0, memberCount: 2),
        TeamLeaderboardEntry(id: "b", name: "나팀", weeklyGoalHours: 40, totalSeconds: 0, workingCount: 0, memberCount: 2)
    ]

    // 내 팀 행이 아예 없는 과거 주 — 표시 목록에는 0시간 '나팀'이 빠지고, myTeamMissing 이 선다.
    let past = rows.leagueDisplay(myTeamID: mine)
    #expect(past.entries.map(\.id) == ["a"])
    #expect(past.unfilteredCount == 2)
    #expect(past.myTeamMissing)

    // 내 팀이 있으면 0시간이어도 남고 myTeamMissing 은 안 선다(기존 규칙 그대로).
    let withMine = (rows + [TeamLeaderboardEntry(id: mine, name: "우리", weeklyGoalHours: 40, totalSeconds: 0, workingCount: 0, memberCount: 3)])
        .leagueDisplay(myTeamID: mine)
    #expect(withMine.entries.map(\.id) == ["a", mine])
    #expect(!withMine.myTeamMissing)

    // ★ 원본이 비면(로드 전·실패) myTeamMissing 은 false 여야 한다 — 통신 실패가 과거 사실로 둔갑하면 안 된다.
    #expect(![TeamLeaderboardEntry]().leagueDisplay(myTeamID: mine).myTeamMissing)
    // 무소속(myTeamID == nil)도 마찬가지.
    #expect(!rows.leagueDisplay(myTeamID: nil).myTeamMissing)
}

// MARK: - ② 스토어 — 주 전환·캐시·실패·옛 서버 폴백

@MainActor
@Test
func v0337_주를_바꾸면_요청_본문에_p_week_offset_이_실린다() async {
    let host = "v0337-step-\(UUID().uuidString)"
    let store = v0337NetworkStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

    // 이번 주 — 오프셋 0 을 싣는다(무인자가 아니다. 무인자면 서버 default 때문에 조용히 이번 주만 보이게 된다).
    await store.performLoadLeaderboard()
    let first = URLProtocolStub.bodies(forHost: host)
    #expect(first.last == #"{"p_week_offset":0}"#, "이번 주 본문: \(first.last ?? "없음")")
    #expect(store.leaderboard.count == 3)

    // ◂ — 주 키가 한 칸 과거로 가고, 그 오프셋이 그대로 나간다.
    store.stepLeagueWeek(by: -1)
    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.step(TeamLeagueWeekNavigator.currentKey(), by: -1))
    await store.performLoadLeaderboard()
    #expect(URLProtocolStub.bodies(forHost: host).last == #"{"p_week_offset":1}"#)

    // 과거 주 응답은 **그 주 값**이다: 내 팀이 빠지고, week_start·participant_count 가 실린다.
    #expect(store.leaderboard.count == 2)
    #expect(!store.leaderboard.contains { $0.id == URLProtocolStub.stubTeamID })
    let row = try! #require(store.leaderboard.first)
    #expect(row.weekStart == store.leagueWeekKey)
    #expect(row.participantCount != nil)
    #expect(row.workingCount == 0, "과거 주 working_count 는 0 이어야 한다(서버 계약)")

    // 6주 전까지 가고, 그 너머로는 요청 자체가 안 나간다.
    for _ in 1...5 { store.stepLeagueWeek(by: -1); await store.performLoadLeaderboard() }
    #expect(URLProtocolStub.bodies(forHost: host).last == #"{"p_week_offset":6}"#)
    // ★ `stepLeagueWeek` 는 조회를 **Task 로 발사**한다. 그 Task 들이 전선을 떠나기 전에 세면, 늦게 기록된 옛 요청이
    //   아래에서 "상한 너머에서 요청이 나갔다"로 읽힌다(계측이 늦는 것뿐인데 테스트가 붉어진다 — 스위트를 병렬로
    //   돌릴 때만 터지는 모양이라 더 나쁘다). 세기 전에 한 번 가라앉힌다.
    try? await Task.sleep(nanoseconds: 80_000_000)
    let countBefore = URLProtocolStub.requests(forHost: host).count
    store.stepLeagueWeek(by: -1)
    try? await Task.sleep(nanoseconds: 80_000_000)
    #expect(URLProtocolStub.requests(forHost: host).count == countBefore, "6주 상한 너머에서 요청이 나갔다")
}

@MainActor
@Test
func v0337_본_주는_캐시에_남아_되돌아올_때_빈_목록을_거치지_않는다() async {
    let host = "v0337-cache-\(UUID().uuidString)"
    let store = v0337NetworkStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

    await store.performLoadLeaderboard()                 // 이번 주
    let thisWeek = store.leaderboard
    store.stepLeagueWeek(by: -1)
    // 처음 보는 주라 비우고 "불러오는 중…"으로 시작한다.
    #expect(store.leaderboard.isEmpty)
    #expect(store.leagueLoading)
    await store.performLoadLeaderboard()
    let lastWeek = store.leaderboard
    #expect(!store.leagueLoading)
    #expect(lastWeek != thisWeek, "주를 바꿨는데 같은 표가 왔다 — 픽스처가 주를 안 가른다(기준선이 같다)")

    // ▸ 로 이번 주로 돌아오면 **캐시가 곧바로 그린다**(빈 목록을 거치지 않는다).
    store.stepLeagueWeek(by: 1)
    #expect(store.leaderboard == thisWeek)
    #expect(!store.leagueLoading)

    // 다시 ◂ 로 지난주 — 여기도 캐시가 있다.
    store.stepLeagueWeek(by: -1)
    #expect(store.leaderboard == lastWeek)
    #expect(!store.leagueLoading)
}

@MainActor
@Test
func v0337_과거_주_조회_실패는_빈_표가_아니라_실패로_말한다() async {
    // "그 주엔 아무도 안 일했다"와 "못 받았다"는 화면에서 똑같이 빈 표다 — 갈라 주지 않으면 실패가 과거 사실이 된다.
    let store = v0337NetworkStore(host: "v0337-league-fails-\(UUID().uuidString)")
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.stepLeagueWeek(by: -1)
    await store.performLoadLeaderboard()
    #expect(store.leagueFailed)
    #expect(!store.leagueLoading)
    #expect(LeaderboardEmptyMessage.text(
        isPastWeek: true,
        unfilteredCount: 0,
        isLoading: store.leagueLoading,
        hasFailed: store.leagueFailed,
        fallbackStatus: store.syncMessage
    ) == LeaderboardEmptyMessage.loadFailed)
}

@MainActor
@Test
func v0337_옛_서버는_한_번_물러서고_주_이동을_접는다() async {
    // 앱이 db push 보다 먼저 나가는 창. 이 갈래가 없으면 리그 화면이 통째로 빈다(지난 주가 아니라 이번 주까지).
    let host = "v0337-league-old-server-\(UUID().uuidString)"
    let store = v0337NetworkStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

    // 과거 주를 보고 있는 상태에서 조회 — 서버는 p_week_offset 을 모른다.
    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 3)
    await store.performLoadLeaderboard()

    let bodies = URLProtocolStub.bodies(forHost: host)
    #expect(bodies.count == 2, "폴백이 정확히 한 번이어야 한다: \(bodies)")
    #expect(bodies.first == #"{"p_week_offset":3}"#)
    #expect(bodies.last == "{}", "폴백 본문이 빈 객체가 아니다: \(bodies.last ?? "없음")")

    // 돌아온 행은 이번 주다 → 보던 주를 되돌리고 화살표를 접는다.
    #expect(!store.leagueWeekOffsetSupported)
    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.currentKey())
    #expect(store.leaderboard.count == 3)
    #expect(!store.leagueLoading)

    // 접힌 동안에는 주 이동 자체가 막힌다(화살표를 지나쳐 불려도 이번 주를 벗어나지 않는다).
    store.stepLeagueWeek(by: -1)
    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.currentKey())

    // 대조군 — 같은 요청이 **새 서버**에서는 접히지 않는다(기준선이 같은 입력이면 위 단언은 영원히 초록이다).
    let freshHost = "v0337-fresh-\(UUID().uuidString)"
    let fresh = v0337NetworkStore(host: freshHost, label: "fresh")
    defer { fresh.tickerTask?.cancel(); fresh.refreshTask?.cancel() }
    fresh.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 3)
    await fresh.performLoadLeaderboard()
    #expect(fresh.leagueWeekOffsetSupported)
    #expect(fresh.leagueWeekKey == TeamLeagueWeekNavigator.key(offset: 3))
    #expect(URLProtocolStub.bodies(forHost: freshHost).count == 1)
}

@MainActor
@Test
func v0337_리그를_다시_열면_늘_이번_주부터_본다() async {
    let store = v0337NetworkStore(host: "v0337-reopen-\(UUID().uuidString)")
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }

    // (1) 뒤로 버튼 경로.
    store.isLeaderboardVisible = true
    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 2)
    store.leaderboard = [TeamLeaderboardEntry(id: "x", name: "옛팀", weeklyGoalHours: 40, totalSeconds: 100, workingCount: 0, memberCount: 1)]
    store.leagueWeekCache[store.leagueWeekKey] = store.leaderboard
    store.closeLeaderboard()
    #expect(!store.isLeaderboardVisible)
    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.currentKey())
    #expect(store.leaderboard.isEmpty)
    #expect(store.leagueWeekCache.isEmpty)

    // (2) 앱을 켜 둔 채 주가 넘어간 모양 — 닫기가 '이미 이번 주'라 조기 반환했던 경우.
    //     여는 경로가 같은 되돌림을 한 번 더 해야 과거 주에 갇히지 않는다(토큰 순위판과 같은 회귀 지점).
    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 4)
    store.leaderboard = [TeamLeaderboardEntry(id: "y", name: "더옛팀", weeklyGoalHours: 40, totalSeconds: 100, workingCount: 0, memberCount: 1)]
    store.isLeaderboardVisible = false
    store.toggleLeaderboard()
    #expect(store.isLeaderboardVisible)
    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.currentKey())
    #expect(store.leaderboard.isEmpty)
}

/// ★ 배포 차단 A-1 — **리그를 여는 네 번째 문**: 팝오버 재오픈.
///
/// 패널을 연 채 팝오버만 닫았다 여는 것이 가장 흔한 동선인데, 그 길은 `toggleLeaderboard` 를 지나지 않는다.
/// 여기가 비어 있던 동안에는 월요일이 지난 뒤 기본 화면이 지난주로 굳었고, 굳은 화면이 **주 경계 전에 받은
/// 이번 주 숫자**를 과거 주 문구로 적었다.
@MainActor
@Test
func v0337_팝오버를_다시_여는_길도_보던_주를_되돌린다() {
    let store = v0337NetworkStore(host: "v0337-menu-reopen-\(UUID().uuidString)")
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.isLeaderboardVisible = true
    store.isMenuPresented = true

    // 과거 주를 펴 둔 채 팝오버만 닫는다(패널은 그대로 열려 있다 — 다음에 열면 이 화면이 그대로 뜬다).
    let past = TeamLeagueWeekNavigator.key(offset: 3)
    store.leagueWeekKey = past
    store.leaderboard = [TeamLeaderboardEntry(id: "x", name: "옛팀", weeklyGoalHours: 40, totalSeconds: 100, workingCount: 0, memberCount: 1)]
    store.leagueWeekCache[past] = store.leaderboard
    store.setMenuPresented(false)
    // 대조군 — **닫는 것만으로는 안 바뀐다**(닫기는 패널을 닫은 게 아니다). 이 줄이 없으면 아래 단언이
    // "원래부터 이번 주였다"로도 초록이 된다.
    #expect(store.leagueWeekKey == past, "팝오버를 닫았다고 보던 주가 바뀌면 안 된다")

    store.setMenuPresented(true)

    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.currentKey(), "재오픈이 보던 주를 안 되돌렸다")
    #expect(store.leaderboard.isEmpty, "과거 주 표가 이번 주 제목 아래 남았다")
    #expect(store.leagueWeekCache[past] == nil, "과거 주 캐시가 남아 ▸ 에서 되살아난다")
}

/// ★ 배포 차단 A-1 — **다섯 번째 문**: 주 롤오버(앱을 켜 둔 채 월요일 0시를 넘김).
///
/// 팝오버를 **연 채** 주가 넘어가는 경로는 토글도 재오픈도 지나지 않는다. 그 순간 `isCurrentWeek(leagueWeekKey)`
/// 가 거짓이 되어 30초 주기 갱신이 스스로 멈추고, 마지막으로 받은 표(이번 주 숫자)가 과거 주 문구를 달고 굳는다.
@MainActor
@Test
func v0337_주가_넘어가면_주기_갱신이_보던_주를_되돌린다() async {
    let host = "v0337-rollover-\(UUID().uuidString)"
    let store = v0337NetworkStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.isMenuPresented = true
    store.isLeaderboardVisible = true

    // 주가 넘어간 모양: 그때의 '이번 주'(= 지금 기준 지난주)를 키와 **기준선 둘 다** 들고 있다.
    // 기준선이 낡았다는 사실 자체가 "내가 고른 게 아니라 주가 옮겨 갔다"는 유일한 증거다.
    let stale = TeamLeagueWeekNavigator.key(offset: 1)
    store.leagueWeekKey = stale
    store.leagueWeekAnchor = stale
    store.leaderboard = [TeamLeaderboardEntry(id: "x", name: "굳은팀", weeklyGoalHours: 40, totalSeconds: 100, workingCount: 2, memberCount: 3)]
    store.leagueWeekCache[stale] = store.leaderboard

    await store.refreshLeaderboardIfVisible()

    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.currentKey(), "주가 넘어갔는데 화면이 지난주에 굳었다")
    #expect(store.leagueWeekAnchor == TeamLeagueWeekNavigator.currentKey())
    #expect(store.leagueWeekCache[stale] == nil, "옛 '이번 주' 표가 캐시에 남아 ▸ 에서 과거 주인 척 되살아난다")
    #expect(URLProtocolStub.bodies(forHost: host).last == #"{"p_week_offset":0}"#, "되돌린 뒤 새 이번 주를 받지 않았다")
    #expect(store.leaderboard.count == 3)

    // 대조군 — 사용자가 **일부러** 고른 과거 주는 주기 갱신이 건드리지 않는다(기준선이 현재와 같으면 롤오버가 아니다).
    // 이 줄이 없으면 "그냥 매번 이번 주로 끌어간다"도 위 단언을 통과한다.
    let chosen = TeamLeagueWeekNavigator.key(offset: 2)
    store.leagueWeekKey = chosen
    store.leagueWeekAnchor = TeamLeagueWeekNavigator.currentKey()
    let before = URLProtocolStub.requests(forHost: host).count
    await store.refreshLeaderboardIfVisible()
    #expect(store.leagueWeekKey == chosen, "보고 있던 과거 주를 주기 갱신이 이번 주로 끌어갔다")
    #expect(URLProtocolStub.requests(forHost: host).count == before, "과거 주에서 주기 갱신이 돌았다")
}

/// C-2 — 서버가 **물은 주와 다른 주**로 답하면 "불러오는 중…"이 영원히 남는다(쌍둥이 갈래 중 하나만 고쳐져 있었다).
/// 주 키를 서버가 답한 주로 바꾸는 순간 `defer` 의 가드(`weekKey == leagueWeekKey`)가 더는 맞지 않아 진행중 표시가
/// 내려가지 않는다. 옛 서버 폴백 갈래는 그 사실을 알고 직접 내렸는데, 이 갈래만 빠져 있었다.
@MainActor
@Test
func v0337_서버가_다른_주로_답해도_불러오는_중이_남지_않는다() async {
    let host = "v0337-league-week-slips-\(UUID().uuidString)"
    let store = v0337NetworkStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.leaderboard = []

    await store.performLoadLeaderboard()

    let answered = TeamLeagueWeekNavigator.key(offset: 1)
    #expect(store.leagueWeekKey == answered, "서버가 답한 주를 안 따랐다 — 제목이 거짓말을 한다")
    #expect(!store.leagueLoading, #""불러오는 중…"이 영원히 남았다"#)
    #expect(!store.leagueFailed)
    #expect(store.leaderboard.count == 1)

    // 대조군 — 서버가 **물은 주 그대로** 답하면 키가 안 움직인다(기준선이 같은 입력이면 위 단언은 아무것도 안 지킨다).
    let straight = v0337NetworkStore(host: "v0337-straight-\(UUID().uuidString)", label: "straight")
    defer { straight.tickerTask?.cancel(); straight.refreshTask?.cancel() }
    straight.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 2)
    await straight.performLoadLeaderboard()
    #expect(straight.leagueWeekKey == TeamLeagueWeekNavigator.key(offset: 2))
    #expect(!straight.leagueLoading)
}

/// C-3 — 이번 주 30초 주기 갱신은 **이미 그려진 표**를 새로 고치는 일이다. 그런데 진행중 표시를 올렸다 내리면
/// 화면 글자가 한 자도 안 바뀌는데 관찰자가 한 주기마다 두 번 무효화된다(`leagueLoading` 은 뷰가 읽는 값이다).
@MainActor
@Test
func v0337_이번_주_주기_갱신은_진행중_표시를_흔들지_않는다() async {
    let host = "v0337-league-quiet-\(UUID().uuidString)"
    let store = v0337NetworkStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.isMenuPresented = true
    store.isLeaderboardVisible = true

    // 첫 조회 — 보여 줄 표가 없으므로 진행중 표시는 **올라가야** 한다(그게 "불러오는 중…"의 존재 이유다).
    await store.performLoadLeaderboard()
    #expect(!store.leaderboard.isEmpty)
    #expect(!store.leagueLoading)

    // 두 번째부터(=주기 갱신)는 표가 이미 있으므로 이 값이 흔들리지 않는다.
    var sawLoading = false
    let probe = Task { @MainActor in
        for _ in 0..<200 {
            if store.leagueLoading { sawLoading = true; return }
            await Task.yield()
        }
    }
    await store.refreshLeaderboardIfVisible()
    probe.cancel()
    _ = await probe.value
    #expect(!sawLoading, "이미 그려진 이번 주 표를 새로 고치며 진행중 표시가 켜졌다(뷰가 공짜로 두 번 무효화된다)")
    #expect(URLProtocolStub.requests(forHost: host).count == 2, "주기 갱신이 안 돌았다 — 위 단언이 헛것이다")

    // 대조군 — 표가 **비어 있으면** 같은 함수가 진행중 표시를 켠다(조건이 실제로 갈린다).
    store.leaderboard = []
    let task = Task { @MainActor in await store.performLoadLeaderboard() }
    await Task.yield()
    #expect(store.leagueLoading, "빈 표에서도 진행중 표시가 안 떴다")
    _ = await task.value
}

/// C-4 — 과거 주 조회가 **취소**로 끝나면 화면에는 빈 표만 남는데, 과거 주에서 빈 표는
/// "그 주엔 근무한 팀이 없었어요"라는 **사실 주장**으로 읽힌다. 취소도 사용자에겐 못 받은 것이다.
@MainActor
@Test
func v0337_과거_주_조회가_취소로_끝나면_빈_표를_사실로_말하지_않는다() async {
    // "delayed-" 접두어는 스텁이 0.15초 뒤에 답하게 한다 — 그 사이에 취소해야 실제 취소 경로를 밟는다.
    let store = v0337NetworkStore(host: "delayed-v0337-cancel-\(UUID().uuidString)")
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 2)
    store.leaderboard = []

    let task = Task { @MainActor in await store.performLoadLeaderboard() }
    try? await Task.sleep(nanoseconds: 30_000_000)
    task.cancel()
    _ = await task.value

    #expect(store.leaderboard.isEmpty)
    #expect(store.leagueFailed, "취소가 빈 표를 '그 주엔 근무한 팀이 없었어요'라는 사실로 만들었다")
    #expect(LeaderboardEmptyMessage.text(
        isPastWeek: true,
        unfilteredCount: 0,
        isLoading: store.leagueLoading,
        hasFailed: store.leagueFailed,
        fallbackStatus: store.syncMessage
    ) == LeaderboardEmptyMessage.loadFailed)

    // 대조군 — **보여 줄 표가 있는** 채로 취소되면 화면을 흔들지 않는다(취소는 여전히 실패 문구가 아니다).
    let held = v0337NetworkStore(host: "delayed-v0337-cancel-held-\(UUID().uuidString)", label: "held")
    defer { held.tickerTask?.cancel(); held.refreshTask?.cancel() }
    held.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 2)
    held.leaderboard = [TeamLeaderboardEntry(id: "x", name: "이미 있는 팀", weeklyGoalHours: 40, totalSeconds: 100, workingCount: 0, memberCount: 1)]
    let holdTask = Task { @MainActor in await held.performLoadLeaderboard() }
    try? await Task.sleep(nanoseconds: 30_000_000)
    holdTask.cancel()
    _ = await holdTask.value
    #expect(!held.leagueFailed, "표가 있는데도 취소가 실패 문구를 남겼다")
    #expect(held.leaderboard.count == 1)
}

/// B — "그 주엔 아직 우리 팀이 없었어요"라고 **단정해도 되는 근거**의 실증(검토 지적: "알 수 없는 원인을 단정한다").
///
/// 서버는 그 주에 존재했던 팀을 **근무 0이어도 전부** 돌려준다(teams 가 드라이버 + 전부 left join). 그러니
/// 과거 주 표에 내 팀 행이 없다는 것은 "그 주엔 그 팀이 아직 없었다" 하나로 좁혀진다 —
/// "0시간이라 빠졌다"와 섞일 자리가 없다는 것을 코어에서 못박는다.
// LeaderboardRow 는 앱 타깃의 SwiftUI 뷰라 MainActor 격리다 — 격리 밖에서 부르면 실행기 단언으로 프로세스가 죽는다.
@MainActor
@Test
func v0337_0시간_우리팀도_그_주_표에_남는다_그래서_없음을_단정할_수_있다() {
    let mine = "my-team"
    let weekStart = TeamLeagueWeekNavigator.key(offset: 2, now: v0337Now)
    func row(_ id: String, _ name: String, seconds: Int, participants: Int) -> TeamLeaderboardEntry {
        TeamLeaderboardEntry(
            id: id, name: name, weeklyGoalHours: 40, totalSeconds: seconds, workingCount: 0, memberCount: 3,
            center: nil, weekStart: weekStart, participantCount: participants
        )
    }

    // ① 그 주에 **한 명도 일하지 않은** 우리 팀 — 행은 온다. 표시 목록에도 남고(내 팀 예외), 없음을 말하지 않는다.
    let idle = [row("a", "가팀", seconds: 3600, participants: 1), row(mine, "우리", seconds: 0, participants: 0)]
        .leagueDisplay(myTeamID: mine)
    #expect(idle.entries.map(\.id) == ["a", mine], "0시간 내 팀이 표시 목록에서 사라졌다")
    #expect(!idle.myTeamMissing, "0시간을 '그 주엔 팀이 없었다'로 읽었다 — 두 사실이 섞였다")
    #expect(LeagueWeekNote.text(isPastWeek: true, myTeamMissing: idle.myTeamMissing) == LeagueWeekNote.pastWeek)
    #expect(LeaderboardRow.caption(row(mine, "우리", seconds: 0, participants: 0), now: v0337Now)
            == "각자 목표 40시간 · 총 0시간 00분 · 3명 중 0명 참여")

    // ② 행이 **아예 없을** 때만 단정한다(서버의 유령 팀 제외 — 그 주엔 팀이 만들어지지도 않았다).
    let absent = [row("a", "가팀", seconds: 3600, participants: 1)].leagueDisplay(myTeamID: mine)
    #expect(absent.myTeamMissing)
    #expect(LeagueWeekNote.text(isPastWeek: true, myTeamMissing: absent.myTeamMissing) == LeagueWeekNote.myTeamMissing)
}

@MainActor
@Test
func v0337_과거_주에는_30초_주기_갱신이_돌지_않는다() async {
    // 과거 주는 **종료된 세션만** 세므로 주기 갱신이 같은 표를 다시 받아오는 낭비다(서버 계약).
    let host = "v0337-refresh-\(UUID().uuidString)"
    let store = v0337NetworkStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.isMenuPresented = true
    store.isLeaderboardVisible = true

    await store.refreshLeaderboardIfVisible()
    let afterCurrent = URLProtocolStub.requests(forHost: host).count
    #expect(afterCurrent == 1, "이번 주에는 주기 갱신이 돌아야 한다")

    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 2)
    await store.refreshLeaderboardIfVisible()
    #expect(URLProtocolStub.requests(forHost: host).count == afterCurrent, "과거 주에서 주기 갱신이 돌았다")
}

@MainActor
@Test
func v0337_로그아웃은_보던_주와_주별_캐시를_함께_비운다() {
    let store = v0337NetworkStore(host: "v0337-signout-\(UUID().uuidString)")
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 5)
    store.leagueWeekCache["아무키"] = []
    store.leagueLoading = true
    store.leagueFailed = true
    store.leagueWeekOffsetSupported = false

    store.signOut()

    #expect(store.leagueWeekKey == TeamLeagueWeekNavigator.currentKey())
    #expect(store.leagueWeekCache.isEmpty)
    #expect(!store.leagueLoading)
    #expect(!store.leagueFailed)
    #expect(store.leagueWeekOffsetSupported, "접힌 채로 물려주면 db push 가 끝난 뒤에도 화살표가 안 보인다")
}

// MARK: - ③ 문구 — 과거 주는 '근무중'을 말하지 않는다

// LeaderboardRow 는 앱 타깃의 SwiftUI 뷰라 MainActor 격리다 — 격리 밖에서 부르면 실행기 단언으로 프로세스가 죽는다.
@MainActor
@Test
func v0337_과거_주_캡션은_근무_중_조각을_아예_뺀다() {
    // 과거 판정은 **행이 스스로** 한다(스토어 오프셋을 인자로 들고 다니지 않는다 — 2026-09-22 확정 API).
    let thisWeek = TeamLeaderboardEntry(
        id: "t", name: "팀", weeklyGoalHours: 40, totalSeconds: 72_000, workingCount: 0, memberCount: 3,
        center: nil, weekStart: TeamLeagueWeekNavigator.currentKey(v0337Now), participantCount: 2
    )
    let past = TeamLeaderboardEntry(
        id: "t", name: "팀", weeklyGoalHours: 40, totalSeconds: 72_000, workingCount: 0, memberCount: 3,
        center: nil, weekStart: "2026-09-14", participantCount: 2
    )
    #expect(!thisWeek.isPastWeek(now: v0337Now))
    #expect(past.isPastWeek(now: v0337Now))

    // 이번 주 문장은 **한 글자도 안 바뀌었다**(회귀 금지 — 이 리터럴이 기존 화면의 계약이다).
    #expect(LeaderboardRow.caption(thisWeek, now: v0337Now) == "각자 목표 40시간 · 총 20시간 00분 · 3명 · 0명 근무중")

    // 과거 주(2026-09-22 확정): '근무 중' 조각이 **통째로** 사라지고 "N명 중 M명 참여"가 대신 선다.
    // 목표 라벨은 **바뀌지 않는다** — 목표가 현재값이라는 사실은 화면에서 빼고 주석에만 남긴다는 확정 때문이다.
    let pastCaption = LeaderboardRow.caption(past, now: v0337Now)
    #expect(pastCaption == "각자 목표 40시간 · 총 20시간 00분 · 3명 중 2명 참여")
    #expect(!pastCaption.contains("근무"), "과거 주 캡션에 '근무' 류가 남았다: \(pastCaption)")
    #expect(!pastCaption.contains("그때"), "머리글 한 줄이 이미 할 말을 행이 또 한다: \(pastCaption)")
    #expect(!pastCaption.contains("지금 목표"), "목표가 현재값이라는 고백이 화면에 남았다: \(pastCaption)")

    // participant_count 가 없는 응답(옛 서버)에서도 workingCount(7)를 대신 적지 않는다 — 0/거짓을 적느니 모른다고 적는다.
    let noCount = TeamLeaderboardEntry(
        id: "t", name: "팀", weeklyGoalHours: 40, totalSeconds: 72_000, workingCount: 7, memberCount: 3,
        center: nil, weekStart: "2026-09-14", participantCount: nil
    )
    let unknown = LeaderboardRow.caption(noCount, now: v0337Now)
    #expect(unknown == "각자 목표 40시간 · 총 20시간 00분 · 3명 중 참여 인원 모름", "캡션: \(unknown)")
    #expect(!unknown.contains("7명"), "과거 주에 '지금 근무 중' 숫자가 새어 나왔다: \(unknown)")

    // weekStart 를 모르는 행(주 칸 자체가 없는 구버전 RPC)은 **이번 주**다 — 가장 흔한 화면이 거짓말하지 않게.
    let legacy = TeamLeaderboardEntry(id: "t", name: "팀", weeklyGoalHours: 40, totalSeconds: 72_000, workingCount: 7, memberCount: 3)
    #expect(!legacy.isPastWeek(now: v0337Now))
    #expect(LeaderboardRow.caption(legacy, now: v0337Now) == "각자 목표 40시간 · 총 20시간 00분 · 3명 · 7명 근무중")
}

@Test
func v0337_빈_목록_문구와_머리글_한_줄은_주에_따라_갈린다() {
    // 이번 주 판정은 예전 함수에 그대로 위임된다(문구 회귀 금지).
    #expect(LeaderboardEmptyMessage.text(isPastWeek: false, unfilteredCount: 2, fallbackStatus: "동기화됨") == "아직 이번 주 근무한 팀이 없어요")
    #expect(LeaderboardEmptyMessage.text(isPastWeek: false, unfilteredCount: 0, fallbackStatus: "동기화됨") == "동기화됨")

    // 과거 주: '아직'도 '이번 주'도 쓰지 않는다. 진행중·실패가 빈 표와 구분된다.
    #expect(LeaderboardEmptyMessage.text(isPastWeek: true, unfilteredCount: 2, fallbackStatus: "동기화됨") == "그 주엔 근무한 팀이 없었어요")
    #expect(LeaderboardEmptyMessage.text(isPastWeek: true, unfilteredCount: 0, fallbackStatus: "동기화됨") == "그 주엔 근무한 팀이 없었어요")
    #expect(LeaderboardEmptyMessage.text(isPastWeek: true, unfilteredCount: 0, isLoading: true, fallbackStatus: "동기화됨") == "불러오는 중…")
    #expect(LeaderboardEmptyMessage.text(isPastWeek: true, unfilteredCount: 0, hasFailed: true, fallbackStatus: "동기화됨") == "순위를 불러오지 못했어요")
    for weeks in [1, 6] {
        let text = LeaderboardEmptyMessage.text(isPastWeek: true, unfilteredCount: weeks, fallbackStatus: "동기화됨")
        #expect(!text.contains("이번 주"), "과거 주 빈 목록 문구에 '이번 주'가 남았다: \(text)")
    }

    // 머리글 한 줄: 이번 주엔 아예 없고(예산 그대로), 과거 주엔 딱 한 줄이다.
    // 2026-09-22 확정 — 과거 주 보조 줄은 **정확히 이 문장 하나**이고, 목표·팀 이름·센터의 현재값 고백은 화면에서 뺐다.
    #expect(LeagueWeekNote.text(isPastWeek: false, myTeamMissing: true) == nil)
    #expect(LeagueWeekNote.text(isPastWeek: true, myTeamMissing: false) == "인원은 그 주 기준이에요")
    #expect(LeagueWeekNote.text(isPastWeek: true, myTeamMissing: true) == "그 주엔 아직 우리 팀이 없었어요")
    // 머리글 한 줄과 행 캡션이 **서로 다른 말을 하지 않는다**(A-2 회귀 지점): 한 줄은 인원이 그 주 기준이라 하고,
    // 행은 "N명 중 M명 참여"로 그 인원을 분모로 쓴다. '지금 값'·'그때'가 어느 쪽에도 남으면 안 된다.
    #expect(!LeagueWeekNote.pastWeek.contains("지금"), "머리글이 인원을 '지금 값'이라고 말한다")
    #expect(!LeagueWeekNote.pastWeek.contains("목표"), "목표의 현재값 고백이 화면에 남았다")
    // 폭 292pt 에서 caption2 한 줄은 한글 22자 남짓이다 — 두 문장을 잇지 않는 근거(둘 다 22자 이내).
    #expect(LeagueWeekNote.pastWeek.count <= 22)
    #expect(LeagueWeekNote.myTeamMissing.count <= 22)
}

// MARK: - ④ 렌더

@MainActor
@Test
func v0337_이번_주_화면은_주를_오갔다_돌아와도_픽셀이_같다() async throws {
    // "이번 주 화면 불변"의 실증. 두 스토어가 **다른 길로** 같은 자리(이번 주)에 도착한다:
    //  · 기준선 — 갓 열어 한 번 조회한 스토어.
    //  · 비교군 — 6주 전까지 ◂ 로 내려갔다가 ▸ 로 되짚어 올라온 스토어.
    // (같은 입력을 두 번 그리는 비교는 영원히 초록이라 아무것도 증명하지 않는다 — 여기선 중간 상태가 다르다.)
    let baseline = v0337RenderStore(now: v0337Now, host: "v0337-render-base-\(UUID().uuidString)")
    defer { baseline.tickerTask?.cancel(); baseline.refreshTask?.cancel() }
    await baseline.performLoadLeaderboard()
    let basePNG = try v0337RenderPNG(CheckMenuView(store: baseline))
    #expect(try v0337Ink(basePNG) > 1000, "기준선이 비어 있다 — ImageRenderer 가 화면을 못 그렸다")
    v0337Save(basePNG, name: "v0337-week-current.png")

    let roundTrip = v0337RenderStore(now: v0337Now, host: "v0337-render-trip-\(UUID().uuidString)", label: "roundTrip")
    defer { roundTrip.tickerTask?.cancel(); roundTrip.refreshTask?.cancel() }
    for _ in 1...6 {
        roundTrip.stepLeagueWeek(by: -1)
        await roundTrip.performLoadLeaderboard()
    }
    #expect(roundTrip.leagueWeekKey == TeamLeagueWeekNavigator.key(offset: 6, now: v0337Now))
    #expect(roundTrip.leaderboard != baseline.leaderboard, "6주 전 표가 이번 주와 같다 — 픽스처가 주를 안 가른다")
    for _ in 1...6 {
        roundTrip.stepLeagueWeek(by: 1)
        await roundTrip.performLoadLeaderboard()
    }
    #expect(roundTrip.leagueWeekKey == TeamLeagueWeekNavigator.currentKey())
    #expect(roundTrip.leaderboard == baseline.leaderboard)

    let roundPNG = try v0337RenderPNG(CheckMenuView(store: roundTrip))
    #expect(v0337Digest(roundPNG) == v0337Digest(basePNG), "이번 주로 돌아온 화면에 과거 주 잔여물이 남았다")
}

@MainActor
@Test
func v0337_과거_주_화면은_이번_주와_다르고_창_높이_예산_안에_있다() throws {
    let current = v0337RenderStore(now: v0337Now)
    current.leaderboard = v0337ThisWeekRows
    let currentPNG = try v0337RenderPNG(CheckMenuView(store: current))

    let past = v0337RenderStore(now: v0337Now, label: "past")
    past.leaderboard = v0337PastWeekRows
    past.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 6, now: v0337Now)
    let pastPNG = try v0337RenderPNG(CheckMenuView(store: past))
    v0337Save(pastPNG, name: "v0337-week-6-ago.png")

    #expect(try v0337Ink(pastPNG) > 1000, "과거 주 화면이 비어 있다")
    #expect(v0337Digest(pastPNG) != v0337Digest(currentPNG), "주를 바꿨는데 화면이 그대로다 — 제목·캡션이 주를 안 읽는다")

    // 최악 — 목록이 스크롤 상한을 넘길 만큼 많은 과거 주. 머리글 한 줄이 목록 행수 예산에서 빠지지 않으면
    // 여기서 창이 700pt 를 넘는다(그 한 줄이 공짜가 아니라는 증거다).
    let crowded = v0337RenderStore(now: v0337Now, label: "crowded")
    crowded.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 3, now: v0337Now)
    crowded.leaderboard = (0..<10).map { index in
        TeamLeaderboardEntry(
            id: "cccccccc-0000-0000-0000-\(String(format: "%012d", index))",
            name: "팀\(index)", weeklyGoalHours: 60, totalSeconds: (10 - index) * 3_600,
            workingCount: 0, memberCount: 2,
            center: nil, weekStart: TeamLeagueWeekNavigator.key(offset: 3, now: v0337Now), participantCount: 2
        )
    }
    // ScrollView 는 ImageRenderer 가 **통째로 못 그린다** — 그대로 두면 목록 자리가 빈 채로 높이 단언만 초록이 된다.
    // 스냅샷 전용 클립 경로로 그려 실제 행을 눈에 보이게 한다(다른 렌더 테스트와 같은 관례).
    let crowdedPNG = try v0337RenderPNG(CheckMenuView(store: crowded, previewClipsOverflowList: true))
    v0337Save(crowdedPNG, name: "v0337-week-crowded.png")
    #expect(try v0337Ink(crowdedPNG) > 1000, "스크롤 상한을 넘긴 과거 주 목록이 통째로 안 그려졌다")

    // 창 높이 상한(≤700pt). scale 2 렌더 → 포인트 높이 = 픽셀/2. 과거 주 한 줄이 붙어도 예산 안이어야 한다.
    for png in [currentPNG, pastPNG, crowdedPNG] {
        let bitmap = try #require(NSBitmapImageRep(data: png))
        #expect(Double(bitmap.pixelsHigh) / 2.0 <= 700.0, "창 높이 상한을 넘었다: \(bitmap.pixelsHigh / 2)pt")
        // 폭은 메인 화면의 자연 폭 414pt(본문 316 + 레일 64) — 패널 안쪽 본문은 292pt 다
        // (414 − 레일 64 − 레일 간격 10 − 바깥 12×2 − 패널 12×2). 머리글에 화살표 둘과 구분선이 붙어도
        // 창이 한 픽셀도 넓어지면 안 된다(넓어지면 폭이 모자라 제목이 줄어든 것이다).
        #expect(bitmap.pixelsWide == Int(CheckMenuView.mainWindowWidth * 2), "창 폭이 \(CheckMenuView.mainWindowWidth)pt 를 벗어났다: \(bitmap.pixelsWide / 2)pt")
    }
}

@MainActor
@Test
func v0337_내_팀이_없던_주는_화면이_그_사실을_말한다() throws {
    let store = v0337RenderStore(now: v0337Now)
    // 그 주엔 우리 팀이 아직 없었다 — 서버가 유령 팀을 빼 주므로 내 팀 행이 아예 없다.
    store.leaderboard = v0337PastWeekRows
    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 6, now: v0337Now)
    let display = store.leaderboard.leagueDisplay(myTeamID: store.currentTeamID)
    #expect(display.myTeamMissing)
    #expect(LeagueWeekNote.text(isPastWeek: true, myTeamMissing: display.myTeamMissing) == LeagueWeekNote.myTeamMissing)

    let png = try v0337RenderPNG(CheckMenuView(store: store))
    v0337Save(png, name: "v0337-week-no-my-team.png")
    #expect(try v0337Ink(png) > 1000)
    let bitmap = try #require(NSBitmapImageRep(data: png))
    #expect(Double(bitmap.pixelsHigh) / 2.0 <= 700.0)
}

@MainActor
@Test
func v0337_옛_서버에서는_주_이동_화살표가_아예_안_그려진다() throws {
    // 화살표를 남겨 두면 눌러도 이번 주 표가 과거 주 제목을 달고 뜬다 — 그게 가장 나쁜 실패 모양이다.
    let folded = v0337RenderStore(now: v0337Now)
    folded.leaderboard = v0337ThisWeekRows
    folded.leagueWeekOffsetSupported = false
    let foldedPNG = try v0337RenderPNG(CheckMenuView(store: folded))
    v0337Save(foldedPNG, name: "v0337-week-old-server.png")

    let normal = v0337RenderStore(now: v0337Now, label: "normal")
    normal.leaderboard = v0337ThisWeekRows
    let normalPNG = try v0337RenderPNG(CheckMenuView(store: normal))

    #expect(try v0337Ink(foldedPNG) > 1000)
    #expect(v0337Digest(foldedPNG) != v0337Digest(normalPNG), "화살표를 접었는데 화면이 같다 — showsWeekNavigation 이 안 읽힌다")
}

/// C-5 — **가장 흔한 과거 주 화면**(내 팀이 있고 여러 팀이 있는 보통의 지난주)이 렌더 픽스처에 없었다.
/// 있던 셋은 전부 변두리다: 내 팀이 없던 주 · 스크롤을 넘긴 주 · 옛 서버. 사람들이 실제로 보게 될 화면이
/// 한 번도 안 그려진 채로 나가는 것이 이 기능의 가장 큰 사각이었다.
@MainActor
@Test
func v0337_보통의_지난주_화면이_렌더_픽스처에_있다() throws {
    let store = v0337RenderStore(now: v0337Now)
    store.leaderboard = v0337OrdinaryLastWeekRows
    store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 1, now: v0337Now)

    let display = store.leaderboard.leagueDisplay(myTeamID: store.currentTeamID)
    #expect(!display.myTeamMissing, "가장 흔한 화면인데 내 팀이 빠졌다 — 그 화면은 다른 픽스처가 이미 본다")
    #expect(display.entries.count == 4)
    // 머리글 한 줄은 **인원 한 문장**이고(목표·팀 이름·센터 고백 없음), 행은 전부 '참여'로 말한다.
    #expect(LeagueWeekNote.text(isPastWeek: true, myTeamMissing: display.myTeamMissing) == LeagueWeekNote.pastWeek)
    for entry in display.entries {
        let caption = LeaderboardRow.caption(entry, now: v0337Now)
        #expect(caption.contains("명 참여"), "과거 주 행이 참여로 말하지 않는다: \(caption)")
        #expect(!caption.contains("근무"), "과거 주 행에 '근무' 류가 남았다: \(caption)")
        #expect(!caption.contains("그때"), "머리글이 이미 하는 말을 행이 또 한다: \(caption)")
    }

    let png = try v0337RenderPNG(CheckMenuView(store: store))
    v0337Save(png, name: "v0337-week-last-ordinary.png")
    #expect(try v0337Ink(png) > 1000, "보통의 지난주 화면이 비어 있다")
    let bitmap = try #require(NSBitmapImageRep(data: png))
    #expect(Double(bitmap.pixelsHigh) / 2.0 <= 700.0, "창 높이 상한을 넘었다: \(bitmap.pixelsHigh / 2)pt")
    #expect(bitmap.pixelsWide == Int(CheckMenuView.mainWindowWidth * 2))

    // 대조군 — 같은 표를 **이번 주로** 보면 화면이 달라야 한다(제목·머리글 한 줄·캡션이 전부 갈린다).
    let asThisWeek = v0337RenderStore(now: v0337Now, label: "asThisWeek")
    asThisWeek.leaderboard = v0337ThisWeekRows
    #expect(v0337Digest(try v0337RenderPNG(CheckMenuView(store: asThisWeek))) != v0337Digest(png))
}

/// C-1 — 과거 주 조회 **실패**에는 [다시 시도]가 없었다. 이번 주는 30초 주기 갱신이 스스로 다시 시도하지만
/// 과거 주는 주기 갱신에서 빠져 있어(종료된 세션만 세므로), 버튼이 없으면 패널을 닫았다 여는 것 말고는 길이 없다.
@MainActor
@Test
func v0337_과거_주_실패_화면에는_다시_시도가_있다() throws {
    func shot(loading: Bool, failed: Bool) throws -> Data {
        let store = v0337RenderStore(now: v0337Now)
        store.leagueWeekKey = TeamLeagueWeekNavigator.key(offset: 2, now: v0337Now)
        store.leaderboard = []
        store.leagueLoading = loading
        store.leagueFailed = failed
        return try v0337RenderPNG(CheckMenuView(store: store))
    }

    let failedPNG = try shot(loading: false, failed: true)
    let loadingPNG = try shot(loading: true, failed: false)
    v0337Save(failedPNG, name: "v0337-week-failed-retry.png")

    #expect(try v0337Ink(failedPNG) > 1000, "실패 화면이 비어 있다")
    #expect(v0337Digest(failedPNG) != v0337Digest(loadingPNG), "실패 화면과 진행중 화면이 같다")

    // ★ 불투명 픽셀 수(`v0337Ink`)로는 못 본다 — 패널 배경이 불투명이라 두 화면의 값이 **정확히 같다**(실측 630,936).
    //   두 화면에서 **accent(파랑) 픽셀이 달라질 수 있는 것은 이 버튼 하나뿐**이다: 빈 목록 문구는 둘 다
    //   secondaryText(회색)라 파랑을 한 픽셀도 안 낸다. 그래서 차이가 곧 버튼이다.
    //   실측(2026-09-22, scale 2): 실패 1838 · 진행중 1302 — 차이 536 이 [다시 시도] 라벨·아이콘이다
    //   (테두리·배경은 불투명도가 낮아 이 엄격한 판정식에 안 걸린다). 문턱은 그 절반 남짓으로 둔다.
    let failedAccent = try v0337AccentPixels(failedPNG)
    let loadingAccent = try v0337AccentPixels(loadingPNG)
    #expect(failedAccent > loadingAccent + 300,
            "[다시 시도] 버튼이 안 그려졌다(실패 파랑 \(failedAccent) · 진행중 파랑 \(loadingAccent))")
}

/// accent(파랑) 픽셀 수. `CheckMenuRenderTests.accentPixelCount` 와 같은 판정식이다 —
/// 그쪽은 private 이라 이 파일에 한 벌 더 둔다(수치가 갈리지 않게 식은 그대로 옮긴다).
private func v0337AccentPixels(_ png: Data) throws -> Int {
    let bitmap = try #require(NSBitmapImageRep(data: png))
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow
    let spp = bitmap.samplesPerPixel
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            if b >= 190, b > r + 80, g > r + 40, g < b { count += 1 }
        }
    }
    return count
}

// MARK: - 픽스처

/// 이번 주 표본(기존 렌더 테스트와 같은 3팀 — 내 팀 포함).
@MainActor
private let v0337ThisWeekRows: [TeamLeaderboardEntry] = [
    TeamLeaderboardEntry(id: "20000000-0000-0000-0000-000000000002", name: "오목교 브라더스", weeklyGoalHours: 60, totalSeconds: 90_000, workingCount: 1, memberCount: 6),
    TeamLeaderboardEntry(id: URLProtocolStub.stubTeamID, name: "아잉팀", weeklyGoalHours: 40, totalSeconds: 72_000, workingCount: 3, memberCount: 3),
    TeamLeaderboardEntry(id: "30000000-0000-0000-0000-000000000003", name: "코드 크래프터", weeklyGoalHours: 50, totalSeconds: 36_000, workingCount: 0, memberCount: 1)
]

/// 6주 전 표본. 내 팀이 **없고**(그때 없던 팀), working_count 는 0, week_start·participant_count 가 실려 있다.
@MainActor
private let v0337PastWeekRows: [TeamLeaderboardEntry] = [
    TeamLeaderboardEntry(
        id: "20000000-0000-0000-0000-000000000002", name: "오목교 브라더스", weeklyGoalHours: 60,
        totalSeconds: 287_839, workingCount: 0, memberCount: 2,
        center: nil, weekStart: TeamLeagueWeekNavigator.key(offset: 6, now: v0337Now), participantCount: 2
    ),
    TeamLeaderboardEntry(
        id: "30000000-0000-0000-0000-000000000003", name: "코드 크래프터", weeklyGoalHours: 50,
        totalSeconds: 36_000, workingCount: 0, memberCount: 1,
        center: nil, weekStart: TeamLeagueWeekNavigator.key(offset: 6, now: v0337Now), participantCount: 1
    )
]

/// **가장 흔한 과거 주** 표본(C-5): 보통의 지난주 — 내 팀이 **있고**, 팀이 여럿이고, 전부 그 주에 실제로 일했다.
/// working_count 는 서버가 0 으로 내리고(계약), week_start·participant_count 가 실린다.
@MainActor
private let v0337OrdinaryLastWeekRows: [TeamLeaderboardEntry] = {
    let weekStart = TeamLeagueWeekNavigator.key(offset: 1, now: v0337Now)
    return [
        TeamLeaderboardEntry(
            id: "20000000-0000-0000-0000-000000000002", name: "오목교 브라더스", weeklyGoalHours: 60,
            totalSeconds: 421_200, workingCount: 0, memberCount: 6,
            center: nil, weekStart: weekStart, participantCount: 5
        ),
        TeamLeaderboardEntry(
            id: URLProtocolStub.stubTeamID, name: "아잉팀", weeklyGoalHours: 40,
            totalSeconds: 388_800, workingCount: 0, memberCount: 3,
            center: nil, weekStart: weekStart, participantCount: 3
        ),
        TeamLeaderboardEntry(
            id: "30000000-0000-0000-0000-000000000003", name: "코드 크래프터", weeklyGoalHours: 50,
            totalSeconds: 126_000, workingCount: 0, memberCount: 2,
            center: nil, weekStart: weekStart, participantCount: 2
        ),
        TeamLeaderboardEntry(
            id: "40000000-0000-0000-0000-000000000004", name: "낭만러너", weeklyGoalHours: 40,
            totalSeconds: 54_000, workingCount: 0, memberCount: 4,
            center: nil, weekStart: weekStart, participantCount: 1
        )
    ]
}()
