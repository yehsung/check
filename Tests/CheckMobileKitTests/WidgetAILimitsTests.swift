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

    /// ★ 리밋 타임라인은 **지평 밖 칸**을 깐다(v0.3.45 P1).
    ///
    /// 열화(30분 넘으면 하한 + "이상", 리셋 뒤 0%)는 **엔트리 시각이 흘러야만** 일어난다. 15분 지평만 깔면
    /// 재적재가 끊긴 날 마지막 칸이 그대로 남아 두 시간이 지나도 `27%` 를 **등호로** 그린다(헤더의 "N분 전"도
    /// 같이 얼어 낡음을 알릴 수단마저 멈춘다). 그래서 마지막 칸 하나로 **규칙이 스스로 하한으로 떨어지는지**를 잰다.
    @Test("타임라인: 리밋만 지평 밖 칸을 깐다 → 재적재가 없어도 마지막 칸에서 하한이 된다(다른 세 위젯은 그대로)")
    func limitsTimelineDecaysPastTheHorizon() throws {
        let near = AingWidgetTimelinePlan.entryDates(now: Self.now)
        let dates = AingWidgetLimitsTimelinePlan.entryDates(now: Self.now)
        // 지평 안쪽은 다른 위젯과 **똑같다**(분 단위 16칸) — 그 뒤에 꼬리가 붙는다.
        #expect(Array(dates.prefix(near.count)) == near)
        #expect(dates.count == near.count + AingWidgetLimitsTimelinePlan.farEntryOffsets.count)
        #expect(dates.allSatisfy { $0 >= Self.now }, "과거 칸을 깔았다")
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $1 > $0 }, "칸이 시간순이 아니다")
        // 꼬리는 신선도 경계를 **넘어간다**(여기서 숫자가 하한이 된다) · 마지막 칸은 하루를 넘는다.
        let last = try #require(dates.last)
        #expect(last.timeIntervalSince(Self.now) > AILimitFreshnessRule.recentWithin)
        #expect(last.timeIntervalSince(Self.now) > AILimitFreshnessRule.staleWithin)
        // 재적재 요청 시각은 다른 위젯과 같다(꼬리는 보험이지 새 주기가 아니다).
        #expect(AingWidgetLimitsTimelinePlan.nextReload(now: Self.now) == AingWidgetTimelinePlan.nextReload(now: Self.now))

        // ★ 같은 스냅샷을 **첫 칸**과 **마지막 칸**에서 그린다: 등호 → 하한으로 갈라져야 한다.
        let snapshot = Self.snapshot(Self.panel())
        func claude(at date: Date) throws -> AILimitDisplay {
            guard case .limits(let limits) = AingWidgetLimitsState(snapshot: snapshot, at: date) else {
                throw TestFailure.notLimits
            }
            return try #require(limits.rows.first { $0.provider == .claude }?.fiveHour)
        }
        func claudeWeekly(at date: Date) throws -> AILimitDisplay {
            guard case .limits(let limits) = AingWidgetLimitsState(snapshot: snapshot, at: date) else {
                throw TestFailure.notLimits
            }
            return try #require(limits.rows.first { $0.provider == .claude }?.weekly)
        }
        let first = try claude(at: try #require(dates.first))
        #expect(first.valueText == "27%" && first.floorOnly == false, "전제: 첫 칸은 등호다")
        let aged = try claude(at: try #require(near.last))
        #expect(aged.floorOnly == false, "전제: 15분 지평 안에서는 아직 등호다 — 그래서 꼬리가 필요하다")
        // 첫 꼬리 칸(+30분 = `recentWithin`)에서 숫자가 **하한**이 된다.
        let decayed = try claude(at: Self.now.addingTimeInterval(AingWidgetLimitsTimelinePlan.farEntryOffsets[0]))
        #expect(decayed.valueText == "27% 이상", "꼬리 칸에서도 등호다 — 지평이 짧아 열화가 멈췄다")
        #expect(decayed.floorOnly, "하한 깃발이 안 섰다 — 바가 등호처럼 진하게 남는다")
        #expect(decayed.freshness == .stale)
        // 마지막 칸: 5시간 창은 리셋(+9,000초)을 한참 지났으므로 **0% · 확인 못 함**이 되고,
        // 주간 창은 아직 리셋이 멀어 하루 넘은 **하한**으로 남는다(두 갈래가 다 꼬리에서만 드러난다).
        let farFive = try claude(at: last)
        #expect(farFive.valueText == "0%" && farFive.captionText == "초기화됨 · 확인 못 함",
                "리셋이 하루 전에 지났는데 \(farFive.valueText) · \(farFive.captionText) 다")
        let farWeekly = try claudeWeekly(at: last)
        #expect(farWeekly.valueText == "60% 이상" && farWeekly.freshness == .ancient)
        // 헤더의 나이 글자도 같이 늙는다(낡음을 알릴 수단이 멈추지 않는다).
        #expect(AingWidgetFormat.ago(from: snapshot.generatedAt, now: last) != AingWidgetFormat.ago(from: snapshot.generatedAt, now: Self.now))

        // ★ 다른 세 위젯의 정책은 **그대로**다(공급자가 둘로 갈렸다는 소스 계약 포함).
        #expect(near.count == 16 && near.last == Self.now.addingTimeInterval(900))
        let widgets = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgets.swift")
        #expect(widgets.contains("AingWidgetTimelinePlan.entryDates(now: now)"), "다른 세 위젯의 칸이 바뀌었다")
        #expect(!widgets.contains("AingWidgetLimitsTimelinePlan"), "리밋 계획이 다른 세 위젯에 번졌다")
        let limits = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingLimitsWidget.swift")
        #expect(limits.contains("AingWidgetLimitsTimelinePlan.entryDates(now: now)"),
                "리밋 위젯이 지평 밖 칸을 쓰지 않는다 — 계획만 만들고 안 물렸다")
        #expect(limits.contains("provider: AingLimitsTimelineProvider()"), "리밋 위젯이 공용 공급자로 돌아갔다")
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

    // MARK: - 유령 행 · 머리 나이 · 하한 바 (v0.3.45 P2 — 세 화면이 다른 말을 하던 자리)

    /// ★ 위젯도 **자기 칸 시각으로** 유령 게이트를 지난다.
    ///
    /// 폰은 서버 응답을 받는 순간 이 문턱을 적용한다(`AILimitsStore.bundle`). 그런데 패널은 **앱이 열릴 때만**
    /// 다시 써지고 위젯은 그 파일을 몇 시간·며칠 뒤 칸 시각으로 그린다(리밋 위젯은 지평 밖 칸까지 깐다).
    /// 그래서 "쓸 때는 안 유령이었지만 그릴 때는 유령"인 창이 열렸고, 그 창에서 위젯은 맥에서 로그아웃한
    /// 제공자를 `0% · 초기화됨` 으로 그렸다 — 쓰지도 않는 도구가 "한도를 하나도 안 썼다"로 보인다.
    /// 문턱의 **양쪽**을 잰다(한쪽만 재면 `>=` 를 `>` 로 바꿔도, 문턱을 10배로 늘려도 초록이다).
    @Test("유령 행: 위젯이 칸 시각으로 다시 잰다(양쪽 경계) · 문턱은 폰과 **같은 상수 하나**")
    func widgetHidesGhostRowsAtEntryTime() throws {
        let cutoff = AILimitGhostRow.maxObservationAge
        // ★ 두 모듈이 한 상수를 쓴다(위젯은 폰 모듈을 링크하지 않는다 — 두 벌로 적으면 언젠가 갈린다).
        #expect(cutoff == AILimitsStore.ghostRowAge, "폰과 위젯이 다른 문턱을 쓴다 — 한쪽만 숨긴다")
        #expect(cutoff > 86_400, "문턱이 하루보다 짧다 — 주말에 맥을 끈 사람의 하한까지 사라진다")

        func panel(observedAgo age: TimeInterval) -> WidgetSnapshot.AILimitPanel {
            .init(providers: [.init(provider: "claude", fiveHourPercent: 27,
                                    fiveHourResetsAt: Self.now.addingTimeInterval(-age + 600),
                                    observedAt: Self.now.addingTimeInterval(-age))])
        }
        func shown(_ panel: WidgetSnapshot.AILimitPanel, at date: Date) -> [AILimitProvider] {
            guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: date) else { return [] }
            return limits.rows.map(\.provider)
        }
        // 문턱 **직전**(1초 모자란다)은 남고, 문턱 **정확히**는 숨는다.
        #expect(shown(panel(observedAgo: cutoff - 1), at: Self.now) == [.claude],
                "아직 문턱에 닿지 않은 줄을 숨겼다 — 맥을 며칠 끈 사람의 하한까지 사라진다")
        #expect(shown(panel(observedAgo: cutoff), at: Self.now).isEmpty,
                "문턱에 닿은 유령 줄이 남았다 — `0% · 초기화됨` 으로 굳는다")
        #expect(shown(panel(observedAgo: cutoff * 10), at: Self.now).isEmpty)

        // ★ 재검증자가 잰 노출 창: **같은 파일**이 쓸 때는 2.5일(안 유령)인데 칸 시각이 하루 더 흐르면 3.5일이다.
        let written = panel(observedAgo: 2.5 * 86_400)
        #expect(shown(written, at: Self.now) == [.claude], "전제: 파일을 쓸 때는 유령이 아니었다")
        let later = Self.now.addingTimeInterval(86_400)
        #expect(shown(written, at: later).isEmpty, "위젯이 나이 검사를 안 해 지평 밖 칸에서 유령 줄을 그린다")
        // 숫자를 지어내지 않고 **안내**로 떨어진다.
        #expect(AingWidgetLimitsState(snapshot: Self.snapshot(written), at: later) == .noProviders)

        // 산 줄과 유령이 섞이면 **산 줄만** 남는다(목록이 통째로 비지 않는다).
        let mixed = WidgetSnapshot.AILimitPanel(providers: [
            .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: Self.now.addingTimeInterval(9_000),
                  observedAt: Self.now.addingTimeInterval(-300)),
            .init(provider: "codex", fiveHourPercent: 56, observedAt: Self.now.addingTimeInterval(-cutoff - 60)),
        ])
        #expect(shown(mixed, at: Self.now) == [.claude])
        // 미래 관측(기기 시계가 어긋난 맥)은 여기서 **버리지 않는다** — 그 판정은 코어 규칙이 한다(`unknown`).
        #expect(shown(panel(observedAgo: -7_200), at: Self.now) == [.claude])
    }

    /// ★ 머리의 나이 글자는 **리밋 관측 나이**다 — 폰이 파일을 쓴 시각이 아니다.
    ///
    /// `snapshot.generatedAt` 은 `NowStore.touchWidgetSnapshot` 이 **값이 안 바뀌어도** 60초마다 '지금'으로
    /// 옮긴다. 그래서 맥이 세 시간 자고 있어도 머리는 `방금` 이라고 적었다. 리밋 위젯이 지평 밖 칸을 깐 근거가
    /// "헤더의 N분 전도 얼어 낡음을 알릴 수단이 멈춘다" 였는데 **그 수단은 애초에 리밋의 나이를 말한 적이 없었다.**
    @Test("머리 나이: 가장 낡은 보이는 줄의 **관측** 나이다(generatedAt 이 '방금'이어도 '3시간 전')")
    func headerAgeSpeaksOfTheObservationNotTheFileWrite() throws {
        let panel = WidgetSnapshot.AILimitPanel(providers: [
            .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: Self.now.addingTimeInterval(3_600),
                  observedAt: Self.now.addingTimeInterval(-10_800)),
            .init(provider: "codex", fiveHourPercent: 56, fiveHourResetsAt: Self.now.addingTimeInterval(1_800),
                  observedAt: Self.now.addingTimeInterval(-600)),
        ])
        var snapshot = Self.snapshot(panel)
        snapshot.generatedAt = Self.now     // 쓰기 창구가 방금 '지금'으로 옮겼다
        #expect(AingWidgetFormat.ago(from: snapshot.generatedAt, now: Self.now) == "방금", "전제: 파일 시각은 방금이다")
        guard case .limits(let limits) = AingWidgetLimitsState(snapshot: snapshot, at: Self.now) else {
            throw TestFailure.notLimits
        }
        #expect(limits.observationAgeText(now: Self.now) == "3시간 전",
                "머리가 리밋의 나이를 말하지 않는다: \(limits.observationAgeText(now: Self.now) ?? "없음")")
        // **가장 낡은** 기여자가 말한다 — 켜져 있는 맥 하나(10분 전)가 다른 줄의 낡음을 가리지 않는다.
        #expect(limits.oldestObservedAt == Self.now.addingTimeInterval(-10_800))
        // 칸 시각이 흐르면 같이 늙는다(재적재가 끊긴 날에도 낡음이 드러난다).
        #expect(limits.observationAgeText(now: Self.now.addingTimeInterval(3_600)) == "4시간 전")
        // 관측 시각을 모르는 줄만 있으면 글자를 **안 적는다**(파일 시각으로 대신하지 않는다).
        #expect(AingWidgetLimits(panel: .init(providers: []), at: Self.now).observationAgeText(now: Self.now) == nil)

        // 머리 글자의 경계는 코어 규칙의 나이 문구와 **같다**(화면마다 '방금'이 갈리지 않게).
        for age in [0, 59, 60, 61, 3_599, 3_600, 86_399, 86_400, 200_000] as [TimeInterval] {
            let then = Self.now.addingTimeInterval(-age)
            #expect(AingWidgetFormat.ago(from: then, now: Self.now) == FeedbackText.ageText(then, now: Self.now),
                    "\(age)초에서 위젯 머리와 코어 규칙의 나이 문구가 갈린다")
        }

        // 소스 계약: 리밋 위젯 머리는 파일 시각을 **안 읽고**, 다른 세 위젯의 머리는 그대로다.
        let code = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingLimitsWidget.swift")
        #expect(code.contains("limits.observationAgeText(now: entry.date)"), "리밋 머리가 관측 나이를 안 쓴다")
        #expect(!code.contains("ago(from: snapshot.generatedAt"), "리밋 머리가 파일 시각으로 돌아갔다")
        let others = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgets.swift")
        #expect(others.contains("AingWidgetFormat.ago(from: snapshot.generatedAt"), "다른 세 위젯의 머리를 건드렸다")
        #expect(!others.contains("observationAgeText"), "리밋 머리 규칙이 다른 세 위젯에 번졌다")
    }

    /// ★ 하한("27% 이상")인 값은 폰·위젯 바에서도 채움이 **흐려야** 한다.
    ///
    /// 맥 `AILimitBar` 만 그렇게 그렸다(주석이 이유를 적었다 — 같은 길이의 바가 등호와 하한에서 똑같이 보이면
    /// 글자의 "이상"을 읽지 못한 사람에게 바가 거짓말을 한다). 폰 `ProgressBar` 와 위젯 `AingWidgetBar` 에는
    /// 그 입력이 **아예 없어서**, 값이 세 화면 다 `27% 이상` 인데 바는 맥만 흐렸다.
    ///
    /// ★ 수단은 **색이 아니라 불투명도**다 — 틴트·투명 모드는 색을 통째로 버리고 알파만 남긴다.
    @Test("하한 바: 폰·위젯도 채움을 흐리게 그린다(색이 아니라 불투명도 · 모든 리밋 막대가 깃발을 받는다)")
    func floorOnlyDimsTheFillOnPhoneAndWidget() throws {
        #expect(AILimitFloorFill.opacity(floorOnly: true) == AILimitFloorFill.floorOpacity)
        #expect(AILimitFloorFill.opacity(floorOnly: false) == 1)
        #expect(AILimitFloorFill.floorOpacity > 0 && AILimitFloorFill.floorOpacity < 1,
                "하한 불투명도가 \(AILimitFloorFill.floorOpacity) 다 — 1 이면 신호가 없고 0 이면 바가 사라진다")

        // 깃발이 실제로 서는 데이터(한 시간 전 관측 = 30분 창을 넘겼다) · 기준선은 방금 받은 값이다.
        func row(observedAgo age: TimeInterval) throws -> AingWidgetLimitRow {
            let panel = WidgetSnapshot.AILimitPanel(providers: [
                .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: Self.now.addingTimeInterval(3_600),
                      weeklyPercent: 60, weeklyResetsAt: Self.now.addingTimeInterval(450_000),
                      observedAt: Self.now.addingTimeInterval(-age)),
            ])
            guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) else {
                throw TestFailure.notLimits
            }
            return try #require(limits.rows.first)
        }
        let stale = try row(observedAgo: 3_600)
        #expect(stale.fiveHour?.valueText == "27% 이상" && stale.fiveHour?.floorOnly == true)
        #expect(stale.weekly?.floorOnly == true, "얇은 주간 줄만 등호로 남았다")
        let fresh = try row(observedAgo: 30)
        #expect(fresh.fiveHour?.floorOnly == false, "기준선이 같은 입력이면 이 테스트는 영원히 초록이다")

        // 바가 그 깃발을 **받는다**. 뷰는 `#if os(iOS)` 라 맥 스위트가 한 픽셀도 그리지 못하므로 소스로 잰다.
        let bar = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgetParts.swift")
        #expect(bar.contains("var floorOnly: Bool = false"), "위젯 막대에 하한 입력이 없다")
        #expect(bar.contains("AILimitFloorFill.opacity(floorOnly: floorOnly)"),
                "위젯 막대가 하한을 불투명도로 말하지 않는다(색으로 말하면 틴트에서 사라진다)")
        let widget = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingLimitsWidget.swift")
        let widgetBars = widget.components(separatedBy: "AingWidgetBar(").count - 1
        #expect(widgetBars == 3, "리밋 위젯의 막대가 \(widgetBars)개다 — 아래 대조가 헐거워졌다")
        #expect(widget.components(separatedBy: "floorOnly:").count - 1 == widgetBars,
                "리밋 막대 가운데 하한을 안 받는 것이 있다 — 그 칸의 바는 등호처럼 진하다")
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        let phoneBars = card.components(separatedBy: "ProgressBar(").count - 1
        #expect(phoneBars == 2, "폰 카드의 막대가 \(phoneBars)개다")
        #expect(card.components(separatedBy: "floorOnly:").count - 1 == phoneBars, "폰 막대가 하한을 안 받는다")
        let progress = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/InsetGroup.swift")
        #expect(progress.contains("AILimitFloorFill.opacity(floorOnly: floorOnly)"),
                "폰 ProgressBar 가 하한을 흐림으로 말하지 않는다")

        // ★ 맥 바는 **같은 상수를 쓸 수 없다**: 맥 앱 타깃은 `CheckMobileShared` 를 링크하지 않고(Package.swift)
        //   셋이 공통으로 보는 모듈은 `CheckCore` 뿐이다. 그래서 숫자가 갈리지 않는지를 소스로 되묻는다 —
        //   한쪽만 고치는 날 여기서 빨개진다(세 화면이 같은 뜻을 다른 세기로 그리지 않게).
        let mac = try IntegrationContractTests.code("Sources/check/CheckAILimitsRow.swift")
        #expect(mac.contains("floorOnly ? \(AILimitFloorFill.floorOpacity) : 1"),
                "맥 바의 하한 불투명도가 폰·위젯(\(AILimitFloorFill.floorOpacity))과 갈렸다")
    }

    enum TestFailure: Error { case notLimits }
}
