import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// v0.3.45 AI 리밋 — **위젯 쪽**: 스냅샷의 새 칸(생 JSON 왕복 · 옛 파일 호환) · 투영(절대 시각 → 남은 시간) ·
/// 모르는 제공자 버리기 · 소속 없음 센티널 보존 · 두 빈 상태 가르기.
///
/// 생 JSON 으로 재는 까닭(이 스위트의 존재 이유): 멤버와이즈로 만든 값을 왕복시키는 테스트만 두면
/// `WidgetSnapshot.init(from:)` 의 **디코드 줄이 빠져도 초록**이다(인코드는 합성이라 파일에는 값이 들어가고,
/// 비교 대상이 같은 코드 경로를 지난다). 그 결함의 증상은 "위젯에 아무것도 안 뜬다" 하나뿐이다.
@MainActor
@Suite("위젯 AI 리밋(v0.3.45)")
struct WidgetAILimitsTests {
    nonisolated static let now = MobileClock.demoInstant   // 2026-09-17 14:05 KST(목)

    nonisolated static func panel(at now: Date = WidgetAILimitsTests.now) -> WidgetSnapshot.AILimitPanel {
        WidgetSnapshot.AILimitPanel(
            providers: [
                .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: now.addingTimeInterval(9_000),
                      weeklyPercent: 60, weeklyResetsAt: now.addingTimeInterval(450_000), observedAt: now.addingTimeInterval(-30)),
                .init(provider: "codex", fiveHourPercent: 56, fiveHourResetsAt: now.addingTimeInterval(1_800),
                      weeklyPercent: 31, weeklyResetsAt: now.addingTimeInterval(200_000), observedAt: now.addingTimeInterval(-30)),
            ],
            todayTokens: 12_345_678,
            recentTokens: 19_658_964_272
        )
    }

    nonisolated static func snapshot(_ panel: WidgetSnapshot.AILimitPanel?) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-30),
            me: .init(working: true, sessionStartedAt: now.addingTimeInterval(-3_600), todaySeconds: 3_600, weekSeconds: 7_200, goalHours: 40, status: .working),
            aiLimits: panel
        )
    }

    // MARK: - 스냅샷 칸

    @Test("왕복: 새 칸이 파일에 실리고 그대로 돌아온다 · 판(version)은 그대로 1 · 날짜는 epoch ms")
    func roundTrip() throws {
        let snapshot = Self.snapshot(Self.panel())
        let data = try WidgetSnapshotCodec.encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""aiLimits""#) && text.contains(#""provider":"claude""#))
        #expect(text.contains(#""todayTokens":12345678"#))
        // ★ 판을 올리면 `BaseWidgetSnapshotTests` 두 곳이 리터럴 "version":1 로 빨개지고, 쓰기 창구가 매번
        //   currentVersion 으로 덮으므로 얻는 것도 없다. 더하기만 한 칸이다.
        #expect(text.contains(#""version":1"#))
        #expect(!text.contains(#""remaining"#), "남은 초를 실었다 — 매초 바뀌는 값은 쓰기 창구의 중복 제거를 무력화한다")
        let decoded = try #require(WidgetSnapshotCodec.decode(data))
        #expect(decoded == snapshot)
        #expect(decoded.aiLimits?.providers.count == 2)
        #expect(decoded.aiLimits?.providers.first?.fiveHourResetsAt == Self.now.addingTimeInterval(9_000))
    }

    @Test("생 JSON: 손으로 쓴 파일이 그대로 읽힌다(디코드 줄이 빠지면 여기서만 빨갛다)")
    func rawJSONDecodes() throws {
        // 1789621500000 = demoInstant. 리셋은 +9,000초(1789630500000) · 관측은 −30초(1789621470000).
        let json = #"""
        {"version":1,"generatedAt":1789621500000,
         "aiLimits":{"providers":[
            {"provider":"claude","fiveHourPercent":27,"fiveHourResetsAt":1789630500000,
             "weeklyPercent":60,"weeklyResetsAt":1789836500000,"observedAt":1789621470000},
            {"provider":"codex","weeklyPercent":56,"observedAt":1789621470000}],
          "todayTokens":12345678,"recentTokens":99,"unknownField":"무시"}}
        """#
        let decoded = try #require(WidgetSnapshotCodec.decode(Data(json.utf8)))
        let panel = try #require(decoded.aiLimits, "새 칸을 읽지 못했다 — init(from:) 에 디코드 줄이 없다")
        #expect(panel.providers.map(\.provider) == ["claude", "codex"])
        #expect(panel.providers[0].fiveHourPercent == 27)
        #expect(panel.providers[0].fiveHourResetsAt == Date(timeIntervalSince1970: 1_789_630_500))
        #expect(panel.providers[1].fiveHourPercent == nil, "없는 창을 0 으로 지어냈다")
        #expect(panel.providers[1].weeklyPercent == 56)
        #expect(panel.todayTokens == 12_345_678 && panel.recentTokens == 99)
    }

    @Test("옛 스냅샷 호환: 칸이 없으면 nil · 깨진 원소 하나는 건너뛴다 · 음수 토큰은 0 · 옛 디코더는 새 파일을 그대로 읽는다")
    func compatibility() throws {
        let old = #"{"version":1,"generatedAt":1789621500000,"me":{"working":true,"todaySeconds":10,"weekSeconds":20,"goalHours":40}}"#
        let decodedOld = try #require(WidgetSnapshotCodec.decode(Data(old.utf8)))
        #expect(decodedOld.aiLimits == nil)
        #expect(decodedOld.me?.resolvedStatus == .working, "새 칸이 없어서 다른 칸까지 버렸다")

        let broken = #"""
        {"version":1,"generatedAt":1789621500000,
         "aiLimits":{"providers":[{"observedAt":1789621470000},{"provider":"codex","weeklyPercent":5,"observedAt":1789621470000},42],
          "todayTokens":-5}}
        """#
        let panel = try #require(WidgetSnapshotCodec.decode(Data(broken.utf8))?.aiLimits)
        #expect(panel.providers.map(\.provider) == ["codex"], "원소 하나가 깨져서 목록을 통째로 버렸다")
        #expect(panel.todayTokens == 0, "음수 토큰이 그대로 들어왔다")

        let wrongShape = #"{"version":1,"generatedAt":1789621500000,"aiLimits":42}"#
        let survived = try #require(WidgetSnapshotCodec.decode(Data(wrongShape.utf8)), "새 칸의 타입이 어긋나 스냅샷 전체를 버렸다")
        #expect(survived.aiLimits == nil)

        // 옛 읽기 모양(새 칸을 모르는 디코더)이 새 파일을 그대로 읽는가.
        struct LegacySnapshot: Decodable { let version: Int; let generatedAt: Date; let me: LegacyMe? }
        struct LegacyMe: Decodable { let working: Bool; let goalHours: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let legacy = try decoder.decode(LegacySnapshot.self, from: try WidgetSnapshotCodec.encode(Self.snapshot(Self.panel())))
        #expect(legacy.version == 1 && legacy.me?.working == true && legacy.me?.goalHours == 40)
    }

    @Test("소속 없음 센티널: 리밋 칸은 me 와 **다른 칸**이라 '팀에 참여하면' 판정을 흔들지 않는다")
    func noTeamSentinelSurvives() throws {
        // NowStore 는 `snapshot.me == widgetNoTeamMe`(모든 칸 0 인 Me)로 소속 없음을 판정한다 — 리밋이 Me 안에
        // 있었다면 이 단언이 깨지고, 소속 없는 사용자에게 "맥 앱에서 팀에 참여하면 보여요"가 샌다.
        var snapshot = Self.snapshot(Self.panel())
        snapshot.me = NowStore.widgetNoTeamMe
        #expect(snapshot.me == NowStore.widgetNoTeamMe, "리밋을 실었더니 소속 없음 센티널이 깨졌다")
        #expect(AingWidgetMyTodayState(snapshot: snapshot, at: Self.now) == .noTeam)
        // 파일을 한 바퀴 돌려도 같다(코덱이 Me 에 칸을 섞지 않는다).
        let decoded = try #require(WidgetSnapshotCodec.decode(try WidgetSnapshotCodec.encode(snapshot)))
        #expect(decoded.me == NowStore.widgetNoTeamMe)
        #expect(AingWidgetMyTodayState(snapshot: decoded, at: Self.now) == .noTeam)
        #expect(decoded.aiLimits?.providers.count == 2, "대조: 리밋은 그대로 살아 있다")
    }

    // MARK: - 투영

    @Test("투영: 스냅샷은 절대 시각만 들고 남은 시간은 **칸 시각**이 만든다(같은 파일, 다른 칸 → 다른 글자)")
    func projectsAbsoluteResetToRemaining() throws {
        let snapshot = Self.snapshot(Self.panel())
        func resetText(at offset: TimeInterval) throws -> String? {
            let date = Self.now.addingTimeInterval(offset)
            guard case .limits(let limits) = AingWidgetLimitsState(snapshot: snapshot, at: date) else {
                throw TestFailure.notLimits
            }
            let row = try #require(limits.rows.first { $0.provider == .claude })
            return AingWidgetLimitFormat.resetIn(row.fiveHour?.resetsAt, now: date)
        }
        #expect(try resetText(at: 0) == "2시간 뒤 초기화")       // 9,000초 남음
        #expect(try resetText(at: 5_400) == "1시간 뒤 초기화")   // 3,600초 남음
        #expect(try resetText(at: 8_700) == "5분 뒤 초기화")     // 300초 남음
        #expect(try resetText(at: 9_100) == nil, "리셋이 지났는데 '뒤 초기화'를 말한다")
        // 남은 시간 글자 자체의 경계(내림 · 0 없음 · 일 단위).
        #expect(AingWidgetLimitFormat.remainingText(1) == "1분" && AingWidgetLimitFormat.remainingText(59) == "1분")
        #expect(AingWidgetLimitFormat.remainingText(3_599) == "59분" && AingWidgetLimitFormat.remainingText(3_600) == "1시간")
        #expect(AingWidgetLimitFormat.remainingText(86_399) == "23시간" && AingWidgetLimitFormat.remainingText(200_000) == "2일")
        #expect(AingWidgetLimitFormat.resetIn(nil, now: Self.now) == nil)
    }

    @Test("투영: 값·캡션·'이상' 접미사는 전부 코어 규칙이 만든다 — 낡으면 하한, 리셋을 지나면 0%")
    func valuesComeFromCoreRule() throws {
        let panel = WidgetSnapshot.AILimitPanel(providers: [
            // 한 시간 전 관측(30분 창을 넘겼다) · 리셋은 아직 안 지났다 → 숫자가 **하한**이 되어 "72% 이상".
            // 리셋 시각은 그 관측에서 5시간 안이어야 한다 — 더 멀면 규칙이 "그 창의 리셋이 아니다"로 보고 `—` 를 준다.
            .init(provider: "claude", fiveHourPercent: 72, fiveHourResetsAt: Self.now.addingTimeInterval(3_600),
                  observedAt: Self.now.addingTimeInterval(-3_600)),
            // 리셋을 (유예 120초 넘겨) 지났다 → "0%" · "초기화됨".
            .init(provider: "codex", fiveHourPercent: 94, fiveHourResetsAt: Self.now.addingTimeInterval(-600),
                  observedAt: Self.now.addingTimeInterval(-1_200)),
        ])
        guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) else {
            throw TestFailure.notLimits
        }
        let claude = try #require(limits.rows.first { $0.provider == .claude }?.fiveHour)
        #expect(claude.valueText == "72% 이상" && claude.floorOnly)
        let codex = try #require(limits.rows.first { $0.provider == .codex }?.fiveHour)
        #expect(codex.valueText == "0%" && codex.captionText == "초기화됨")
        #expect(codex.percent == 0)
    }

    @Test("0% 행은 리셋을 주장하지 않는다(Codex 가짜 reset_at 함정) — 맥이 nil 로 접어 올리므로 캡션도 나이다")
    func zeroPercentDoesNotClaimReset() throws {
        let panel = WidgetSnapshot.AILimitPanel(providers: [
            .init(provider: "codex", fiveHourPercent: 0, fiveHourResetsAt: nil,
                  weeklyPercent: 56, weeklyResetsAt: Self.now.addingTimeInterval(200_000),
                  observedAt: Self.now.addingTimeInterval(-300)),
        ])
        guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) else {
            throw TestFailure.notLimits
        }
        let five = try #require(limits.rows.first?.fiveHour)
        #expect(five.valueText == "0%" && !five.freshness.isResetClaim, "0% 를 '초기화됨'으로 단정했다")
        #expect(five.captionText == "5분 전")
        #expect(AingWidgetLimitFormat.resetIn(five.resetsAt, now: Self.now) == nil, "리셋 시각이 없는데 뭔가를 말한다")
    }

    // MARK: - 고르기 · 빈 상태

    @Test("모르는 제공자는 버린다 · 창이 하나도 없는 행도 버린다 · 순서는 고정(Claude → Codex → AG)")
    func dropsUnknownAndEmpty() throws {
        let panel = WidgetSnapshot.AILimitPanel(providers: [
            .init(provider: "antigravity", weeklyPercent: 8, weeklyResetsAt: Self.now.addingTimeInterval(500_000), observedAt: Self.now),
            .init(provider: "future-provider", fiveHourPercent: 99, observedAt: Self.now),
            .init(provider: "claude", fiveHourPercent: 27, observedAt: Self.now),
            // 퍼센트가 둘 다 없다 — 올릴 말이 없던 행이다.
            .init(provider: "codex", observedAt: Self.now),
        ])
        guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) else {
            throw TestFailure.notLimits
        }
        #expect(limits.rows.map(\.provider) == [.claude, .antigravity], "모르는 제공자·빈 행이 살아남거나 순서가 흔들렸다")
        #expect(limits.shown(limit: AingWidgetLayout.limitRowsMedium).count == 2)
        #expect(limits.shown(limit: 1).map(\.provider) == [.claude])
    }

    @Test("S 가 세우는 하나 = 5시간 사용률이 가장 높은 줄(모르는 줄은 끼어들지 않는다 · 동률은 고정 순서)")
    func mostUrgentPicksHighest() throws {
        func most(_ rows: [WidgetSnapshot.AILimitRow]) throws -> AILimitProvider? {
            guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(.init(providers: rows)), at: Self.now) else {
                throw TestFailure.notLimits
            }
            return limits.mostUrgent?.provider
        }
        #expect(try most([
            .init(provider: "claude", fiveHourPercent: 27, observedAt: Self.now),
            .init(provider: "codex", fiveHourPercent: 94, observedAt: Self.now),
        ]) == .codex)
        // 동률이면 고정 순서가 가른다(칸마다 다른 줄이 서면 위젯을 믿지 못한다).
        #expect(try most([
            .init(provider: "codex", fiveHourPercent: 40, observedAt: Self.now),
            .init(provider: "claude", fiveHourPercent: 40, observedAt: Self.now),
        ]) == .claude)
        // 주간만 있는 줄(5시간 모름 urgency −1)은 0% 인 줄에도 밀린다 — '모른다'는 0 이 아니다.
        #expect(try most([
            .init(provider: "antigravity", weeklyPercent: 99, weeklyResetsAt: Self.now.addingTimeInterval(500_000), observedAt: Self.now),
            .init(provider: "claude", fiveHourPercent: 0, observedAt: Self.now),
        ]) == .claude)
    }

    @Test("대표 창은 라벨과 한 묶음이다 — 5시간이 없으면 주간이 서고 라벨도 '주간'으로 바뀐다(둘이 같은 창으로 읽히지 않게)")
    func primaryWindowCarriesItsLabel() throws {
        let panel = WidgetSnapshot.AILimitPanel(providers: [
            .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: Self.now.addingTimeInterval(9_000),
                  weeklyPercent: 60, weeklyResetsAt: Self.now.addingTimeInterval(450_000), observedAt: Self.now),
            // 5시간 창이 아예 없는 요금제(안티그래비티 실측) — 주간이 대표로 선다.
            .init(provider: "antigravity", weeklyPercent: 8, weeklyResetsAt: Self.now.addingTimeInterval(500_000), observedAt: Self.now),
        ])
        guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) else {
            throw TestFailure.notLimits
        }
        let claude = try #require(limits.rows.first { $0.provider == .claude })
        let claudePrimary = try #require(claude.primaryWindow)
        #expect(claudePrimary.label == AingWidgetText.limitsFiveHour && claudePrimary.display.valueText == "27%")
        #expect(claude.secondaryWeekly?.valueText == "60%", "두 창이 다 있으면 주간이 따로 한 줄 더 선다")

        let ag = try #require(limits.rows.first { $0.provider == .antigravity })
        let agPrimary = try #require(ag.primaryWindow)
        #expect(agPrimary.label == AingWidgetText.limitsWeekly, "주간 값에 '5시간' 라벨이 붙었다 — 27% 옆에서 같은 창으로 읽힌다")
        #expect(agPrimary.display.valueText == "8%")
        #expect(ag.secondaryWeekly == nil, "대표로 이미 선 주간을 아래에 한 번 더 그린다")
        #expect(AingWidgetText.limitsFiveHour != AingWidgetText.limitsWeekly)
    }

    @Test("빈 상태 둘은 뜻이 다르다: 칸 없음 = '앱을 열면', 받았는데 0건 = '맥 앱에서 로그인하면'")
    func twoEmptyStatesAreDistinct() {
        #expect(AingWidgetLimitsState(snapshot: Self.snapshot(nil), at: Self.now) == .noData)
        #expect(AingWidgetLimitsState(snapshot: Self.snapshot(.init(providers: [])), at: Self.now) == .noProviders)
        // 모르는 제공자만 왔을 때도 '연동 없음'이다(그 줄은 그릴 수 없다).
        let unknownOnly = WidgetSnapshot.AILimitPanel(providers: [.init(provider: "future-provider", fiveHourPercent: 50, observedAt: Self.now)])
        #expect(AingWidgetLimitsState(snapshot: Self.snapshot(unknownOnly), at: Self.now) == .noProviders)
        #expect(AingWidgetText.limitsNoData != AingWidgetText.limitsNoProviders)
    }

    @Test("토큰 축은 리밋과 나란히 · 모르면 줄을 만들지 않는다 · 축약은 앱과 같은 함수")
    func tokenAxisIsSeparate() throws {
        guard case .limits(let withTokens) = AingWidgetLimitsState(snapshot: Self.snapshot(Self.panel()), at: Self.now),
              case .limits(let without) = AingWidgetLimitsState(
                  snapshot: Self.snapshot(.init(providers: Self.panel().providers)), at: Self.now
              )
        else { throw TestFailure.notLimits }
        #expect(withTokens.hasTokens && withTokens.todayTokens == 12_345_678)
        #expect(!without.hasTokens && without.todayTokens == nil, "모르는 토큰을 0 으로 지어냈다")
        #expect(AingWidgetLimitFormat.tokens(12_345_678) == TokenNumberFormatter.compactKorean(12_345_678))
        #expect(AingWidgetLimitFormat.tokens(19_658_964_272) == "196.6억")
    }

    @Test("갤러리 예시에 리밋이 들어 있다(세 제공자가 서로 다른 모양) · 코덱 왕복도 지난다")
    func gallerySampleCarriesLimits() throws {
        let sample = AingWidgetSamples.snapshot(now: Self.now)
        let panel = try #require(sample.aiLimits)
        #expect(panel.providers.map(\.provider) == ["claude", "codex", "antigravity"])
        #expect(panel.providers[1].fiveHourResetsAt == nil, "Codex 0% 행에 가짜 리셋 시각을 넣었다")
        #expect(panel.providers[2].fiveHourPercent == nil, "안티그래비티 예시에 없는 5시간 창을 지어냈다")
        let decoded = try #require(WidgetSnapshotCodec.decode(try WidgetSnapshotCodec.encode(sample)))
        #expect(decoded.aiLimits == panel)
        guard case .limits(let limits) = AingWidgetLimitsState(snapshot: sample, at: Self.now) else { throw TestFailure.notLimits }
        #expect(limits.rows.count == 3 && limits.hasTokens)
    }

    @Test("위젯 종류: kind 는 넷이고 새 kind 는 갤러리 이름·설명을 가진다")
    func kindsAndGallery() {
        #expect(AingWidgetKind.all.count == 4 && Set(AingWidgetKind.all).count == 4)
        #expect(AingWidgetKind.all.contains(AingWidgetKind.aiLimits))
        #expect(!AingWidgetText.limitsGalleryName.isEmpty && !AingWidgetText.limitsGalleryDescription.isEmpty)
        #expect(AingWidgetLayout.limitRowsMedium == 3 && AingWidgetLayout.limitRowsLarge == 3 && AingWidgetLayout.limitRowsSmall == 1)
    }

    @Test("번들에 새 위젯이 한 줄 올라갔다(ios/Widgets — 패키지만 고치면 홈 화면에 안 뜬다)")
    func bundleListsNewWidget() throws {
        let bundle = try String(
            contentsOf: IntegrationContractTests.root.appendingPathComponent("ios/Widgets/AingCheckWidgetsBundle.swift"),
            encoding: .utf8
        )
        #expect(bundle.contains("AingAILimitsWidget()"), "위젯 번들에 리밋 위젯이 없다 — 갤러리에 나타나지 않는다")
    }

    enum TestFailure: Error { case notLimits }
}
