import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

@Suite("나 탭 문구·순수 규칙(rankme)")
struct MeTextTests {
    @Test("별명 정규화·길이·쿨타임 해제일(KST 자정)·문구")
    func displayNameRules() throws {
        #expect(MeText.normalizedDisplayName("  새벽\u{200B}   별 \n") == "새벽 별")
        #expect(MeText.normalizedDisplayName("👨\u{200D}👩\u{200D}👧") == "👨\u{200D}👩\u{200D}👧", "ZWJ 는 남긴다")
        #expect(MeText.displayNameLength("가나다") == 3)
        let changed = try #require(ISO8601DateFormatter().date(from: "2026-09-10T20:00:00Z")) // 9/11 05:00 KST
        let unlock = MeText.displayNameUnlockDate(changedAt: changed)
        #expect(ISO8601DateFormatter().string(from: unlock) == "2026-09-17T15:00:00Z", "9/18 00:00 KST")
        #expect(MeText.displayNameCooldownMessage(availableAt: unlock) == "일주일에 한 번만 바꿀 수 있어요 · 9월 18일부터")
        #expect(MeText.displayNameTooLong(12) == "별명은 12자까지 쓸 수 있어요")
    }

    @Test("조사: 받침 있으면 을/은, 없으면 를/는, 한글이 아니면 받침 없는 쪽")
    func particles() {
        #expect(MeText.purchaseConfirmTitle(name: "유령") == "유령을 살까요?")
        #expect(MeText.purchaseConfirmTitle(name: "여우") == "여우를 살까요?")
        #expect(MeText.lockedCharacter("다람쥐") == "다람쥐는 아직 없어요 — 상점에서 살 수 있어요")
        #expect(MeText.purchaseConfirmTitle(name: "dragon") == "dragon를 살까요?")
    }

    /// KST 날짜·시각(9월) 세션 행. 코어 행 타입은 모듈 밖 생성자가 없어 JSON 으로 만든다(서버 모양 그대로).
    static func sessions(_ spans: [(day: Int, startHour: Int, minutes: Int)], month: Int = 9) throws -> [WorkSessionRow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TeamWeeklyGoal.koreanTimeZone
        let formatter = ISO8601DateFormatter()
        let rows = try spans.enumerated().map { index, span -> String in
            let start = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: span.day, hour: span.startHour)))
            let end = start.addingTimeInterval(TimeInterval(span.minutes * 60))
            return #"{"id":"s\#(index)","user_id":"u","started_at":"\#(formatter.string(from: start))","ended_at":"\#(formatter.string(from: end))","duration_seconds":\#(span.minutes * 60)}"#
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([WorkSessionRow].self, from: Data("[\(rows.joined(separator: ","))]".utf8))
    }

    @Test("회고 문구: 달성 · 미달(99% 묶기) · 전주 대비 · 세부 · 자리 문구 갈림")
    func retroLines() throws {
        let now = MobileClock.demoInstant // 9/17(목) — 지난주 = 9/7~9/13, 그 전주 = 8/31~9/6
        let metRows = try Self.sessions([(7, 9, 480), (8, 9, 480), (9, 9, 540), (10, 9, 480), (11, 9, 420)])
            + Self.sessions([(31, 9, 360)], month: 8) + Self.sessions([(1, 9, 360), (2, 9, 360), (3, 9, 360), (4, 9, 360)])
        let met = try #require(WeeklyRetro.build(sessions: metRows, now: now, goalSeconds: 40 * 3600))
        #expect(met.totalSeconds == 40 * 3600)
        #expect(MeText.retroGoalLine(met) == "목표 40시간 00분 달성 — 잘하셨어요")
        #expect(MeText.retroDeltaLine(met) == "전주 대비 +10시간 00분")
        #expect(MeText.retroDetailLine(met) == "세션 5회 · 가장 많이 일한 날 수요일 9시간 00분")
        let almostRows = try Self.sessions([(7, 9, 480), (8, 9, 480), (9, 9, 480), (10, 9, 480), (11, 9, 479)])
        let almost = try #require(WeeklyRetro.build(sessions: almostRows, now: now, goalSeconds: 40 * 3600))
        #expect(MeText.retroGoalLine(almost) == "목표 40시간 00분 중 99% · 0시간 01분 부족")
        #expect(MeText.retroDeltaLine(almost) == nil)
        #expect(MeText.recordsPlaceholder(hasLoaded: false, hasFailed: false, totalSeconds: 0, hasTokenGrass: false) == "불러오는 중…")
        #expect(MeText.recordsPlaceholder(hasLoaded: false, hasFailed: true, totalSeconds: 0, hasTokenGrass: false) == "기록을 불러오지 못했어요")
        #expect(MeText.recordsPlaceholder(hasLoaded: true, hasFailed: false, totalSeconds: 0, hasTokenGrass: false) == "지난주 근무 기록이 없어요")
        #expect(MeText.recordsPlaceholder(hasLoaded: true, hasFailed: false, totalSeconds: 0, hasTokenGrass: true) == nil, "토큰만 쓰는 사람의 잔디를 덮지 않는다")
    }

    @Test("격자: 단계(올림 나눗셈)·불투명도·월 라벨·히트맵 농도")
    func gridRules() throws {
        #expect(MeText.gridLevel(value: 0, denominator: 100) == 0)
        #expect(MeText.gridLevel(value: 1, denominator: 100) == 1)
        #expect(MeText.gridLevel(value: 26, denominator: 100) == 2)
        #expect(MeText.gridLevel(value: 1_000, denominator: 100) == 4)
        #expect(MeText.gridOpacity(level: 0) == 0)
        #expect(MeText.gridOpacity(level: 4) == 1.0)
        #expect(MeText.heatmapIntensity(seconds: 1_800) == 0.5)
        let start = try #require(WorkDailyGrid.windowStart(now: MobileClock.demoInstant))
        let labels = MeText.monthLabels(weekStart: start, weeks: 13)
        #expect(labels.count == 13)
        // 창 = 6/22(월)~. 첫 열의 일요일(6/28)은 앞 열(6/21)과 같은 6월이라 라벨이 없고, 달이 바뀐 열에만 붙는다.
        #expect(labels.compactMap { $0 } == [7, 8, 9], "\(labels)")
        #expect(labels.first == .some(nil))
    }

    @Test("제보: 실패 문구 갈림(레이트리밋·권한·스키마 부재·원문 숨김) · 자동 첨부 안내")
    func feedbackRules() {
        #expect(MeText.feedbackFailure(SupabaseWorkServiceError.authMessage("FEEDBACK_RATE_LIMIT"), fallback: "x") == FeedbackText.rateLimited)
        #expect(MeText.feedbackFailure(SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil), fallback: "x") == FeedbackText.rateLimited)
        #expect(MeText.feedbackFailure(SupabaseWorkServiceError.authMessage("FEEDBACK_FORBIDDEN"), fallback: "x") == FeedbackText.forbidden)
        #expect(MeText.feedbackFailure(SupabaseWorkServiceError.authMessage("SOMETHING_INTERNAL"), fallback: "x") == "x")
        #expect(MeText.feedbackFailure(SupabaseWorkServiceError.databaseSchemaMissing, fallback: "x", schemaMissing: "y") == "y")
        #expect(MeText.feedbackAutoAttach(appVersion: "iOS 0.1.0 (1)", osVersion: "iOS 18.2") == "iOS 0.1.0 (1) · iOS 18.2 정보가 함께 전송돼요")
    }

    @Test("알림 권한 문구 · 버전 줄 · 카드 가격")
    func miscTexts() {
        #expect(MePushAuthorization.denied.detail?.contains("설정 앱") == true)
        #expect(!MePushAuthorization.notDetermined.allowsDelivery && MePushAuthorization.provisional.allowsDelivery)
        #expect(MeText.versionLine(version: "0.1.0", build: 1) == "aing-check iOS 0.1.0 (1)")
        #expect(MeText.cardPrice(owned: true, price: 30) == "보유")
        #expect(MeText.cardPrice(owned: false, price: nil) == "—")
        #expect(MeText.cardPrice(owned: false, price: 80) == "80")
    }
}

/// 맥과 "같은 문장"이라고 적은 문구가 맥 소스에 **아직 그대로** 있는가(한쪽만 바뀌면 빨개진다). 주석은 걷어 내고 읽는다.
@Suite("나·순위 탭 문구 맥 일치(rankme)")
struct MeTextParityTests {
    static let macSources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check")

    static func macCode() throws -> String {
        let files = try FileManager.default.contentsOfDirectory(atPath: macSources.path).filter { $0.hasSuffix(".swift") }.sorted()
        return try files.map { name -> String in
            let text = try String(contentsOf: macSources.appendingPathComponent(name), encoding: .utf8)
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    let trimmed = line.drop { $0 == " " || $0 == "\t" }
                    return trimmed.hasPrefix("//") ? "" : line
                }
                .joined(separator: "\n")
        }.joined(separator: "\n")
    }

    @Test("맥 코드에 같은 문장이 있다")
    func sentencesExistInMacCode() throws {
        let code = try Self.macCode()
        let sentences = [
            MeText.noRetro, MeText.recordsFailed, MeText.retroTitle, MeText.heatmapTitle, MeText.workGrassTitle, MeText.tokenGrassTitle,
            "전주와 같아요", "목표 달성", MeText.alreadyOwned, MeText.pickSomething, "샀어요!", MeText.buyFailed,
            MeText.displayNameEmpty, MeText.displayNameTaken, MeText.displayNameInvalid, MeText.displayNameNetwork,
            MeText.avatarSaved, MeText.avatarFailed, MeText.displayNameHelp,
            MeText.tokenPublicTitle, MeText.tokenPublicDetail, MeText.miniGamePublicTitle, MeText.miniGamePublicDetail,
            "일주일에 한 번만 바꿀 수 있어요 · ",
            RankingsText.leagueFilteredOut, RankingsText.tokenNoUploads, RankingsText.tokenNoPastRecords, RankingsText.tokenFailed,
            RankingsText.miniGameEmpty, RankingsText.miniGameFailed, "어제 1등", "우리 팀", " AI 토큰 소모량", "오늘 순위",
            "자정에 1·2·3등에게 루비 ", "명부터 지급", "지급 조건 충족", "각자 목표 ", "명 근무중",
        ]
        for sentence in sentences {
            #expect(code.contains(sentence), "맥 코드에 없는 문장: \(sentence)")
        }
        #expect(code.contains("static let rubyPrizes = [20, 10, 5]") && code.contains("static let prizeQuorum = 5"), "상품·정족수 상수가 바뀌었다")
        #expect(code.contains("displayNameCooldownSeconds: TimeInterval = 7 * 24 * 3600"))
    }
}
