import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.55 — 주간 누적 근무 보상(맥).
//
// 서버 정본은 `supabase/migrations/20261016120000_weekly_work_reward.sql` 이고 지급은 서버만 한다. 여기서 재는 것은
//  ① 전선 — 응답 디코드가 키 하나 때문에 죽지 않는다(옛/새 서버 어긋남) · 서비스가 `{}` 로 POST 한다,
//  ② 문구·진행 산식 — 0시간 · 19:59 · 20시간 · 59시간 · 60시간+ · 다음 단계 고르기 · 규칙 툴팁(숫자는 응답 표에서),
//  ③ 스토어 — 박자(지갑 sync 와 같이 · 1분에 한 번 넘게 안 묻는다 · 근무 종료 직후 · 빚) · 잔량을 새 값 위에 덮지 않는다 ·
//     "방금 받았다"는 granted_now 와 같은 주의 claimed 전이로만,
//  ④ 화면 — 울트라 화면에 줄이 그려진다 · 받은 단계가 그려진다 · 팝오버 높이 상한(≤700pt),
//  ⑤ 캐릭터 말풍선 — `.rubyReward` 가 랩 보상과 같은 규칙으로 재생되고 숫자만 다르다.
// 실네트워크는 없다(호스트별 스텁 `GomokuStubProtocol`). 창은 띄우지 않는다(ImageRenderer 만).

// MARK: - 픽스처

enum V0355WeeklyStub {
    /// 계약 모양 그대로의 응답(스네이크 키). `claimed` 는 20·40·60 순서.
    static func json(worked: Int,
                     claimed: [Bool] = [false, false, false],
                     granted: [(hours: Int, ruby: Int, weekStart: String?)] = [],
                     ruby: Int? = 1057,
                     weekStart: String = "2026-10-12",
                     nextWeekStart: String = "2026-10-19") -> String {
        let table = [(20, 20), (40, 50), (60, 200)]
        let tiers = zip(table, claimed).map { tier, isClaimed in
            #"{"hours":"# + "\(tier.0)" + #","ruby":"# + "\(tier.1)" + #","claimed":"# + (isClaimed ? "true" : "false") + "}"
        }
        let grants = granted.map { grant in
            #"{"hours":"# + "\(grant.hours)" + #","ruby":"# + "\(grant.ruby)"
                + (grant.weekStart.map { #","week_start":""# + $0 + #"""# } ?? "") + "}"
        }
        return #"{"week_start":""# + weekStart + #"","next_week_start":""# + nextWeekStart + #"","worked_seconds":"# + "\(worked)"
            + #","tiers":["# + tiers.joined(separator: ",") + #"],"granted_now":["# + grants.joined(separator: ",") + "]"
            + (ruby.map { #","ruby_balance":"# + "\($0)" } ?? "") + #","server_now_ms":1781234567890}"#
    }

    /// 서비스와 같은 디코더(스네이크 → 카멜).
    static func decode(_ json: String) throws -> WeeklyWorkStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WeeklyWorkStatus.self, from: Data(json.utf8))
    }

    /// 표 그대로의 상태(값으로 바로 만든다 — 문구·산식 테스트용).
    static func status(worked: Int?, claimed: [Bool] = [false, false, false],
                       granted: [WeeklyWorkStatus.Grant] = [], ruby: Int? = nil,
                       weekStart: String? = "2026-10-12") -> WeeklyWorkStatus {
        let table = [(20, 20), (40, 50), (60, 200)]
        return WeeklyWorkStatus(
            weekStart: weekStart, nextWeekStart: "2026-10-19", workedSeconds: worked,
            tiers: zip(table, claimed).map { WeeklyWorkStatus.Tier(hours: $0.0.0, ruby: $0.0.1, claimed: $0.1) },
            grantedNow: granted, rubyBalance: ruby
        )
    }

    static let hour = 3_600
}

/// 바꿀 수 있는 시계(스토어의 `clock` 에 꽂는다).
@MainActor
final class V0355Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

// MARK: - ① 전선(디코드 · 서비스)

@Suite struct V0355WeeklyDecodeTests {
    @Test("계약 응답 전체 — 칸마다 그대로 옮긴다(스네이크 → 카멜)")
    func decodesTheFullContract() throws {
        let status = try V0355WeeklyStub.decode(V0355WeeklyStub.json(
            worked: 83_456, claimed: [true, false, false], granted: [(20, 20, nil)], ruby: 1057))
        #expect(status.weekStart == "2026-10-12" && status.nextWeekStart == "2026-10-19")
        #expect(status.workedSeconds == 83_456)
        #expect(status.tiers == [
            .init(hours: 20, ruby: 20, claimed: true), .init(hours: 40, ruby: 50, claimed: false), .init(hours: 60, ruby: 200, claimed: false),
        ])
        #expect(status.grantedNow == [.init(hours: 20, ruby: 20, weekStart: nil)])
        #expect(status.rubyBalance == 1057)
        #expect(status.serverNowMs == 1_781_234_567_890)
        #expect(status.isUsable)
    }

    @Test("키가 빠져도 통째로 죽지 않는다 — 빈 객체 · 표 없음 · claimed 없음 · granted_now 없음")
    func missingKeysNeverFailTheDecode() throws {
        let empty = try V0355WeeklyStub.decode("{}")
        #expect(empty.workedSeconds == nil && empty.tiers.isEmpty && empty.grantedNow.isEmpty && empty.rubyBalance == nil)
        #expect(!empty.isUsable, "아무것도 모르는 응답으로 줄을 그리면 '이번 주 0분'이라는 거짓말이 된다")

        let noTiers = try V0355WeeklyStub.decode(#"{"worked_seconds":7200,"ruby_balance":5}"#)
        #expect(noTiers.workedSeconds == 7_200 && noTiers.rubyBalance == 5 && !noTiers.isUsable)

        // claimed 가 없으면 **안 받은 것**이다(받았다고 그리면 안 준 루비를 준 것처럼 말한다).
        let noClaimed = try V0355WeeklyStub.decode(#"{"worked_seconds":10,"tiers":[{"hours":20,"ruby":20}]}"#)
        #expect(noClaimed.tiers == [.init(hours: 20, ruby: 20, claimed: false)])
        #expect(noClaimed.grantedNow.isEmpty && noClaimed.isUsable)
    }

    @Test("모르는 키가 더 와도 산다(최상위 · 단계 행 · 지급 행)")
    func extraKeysAreIgnored() throws {
        let json = #"{"status":"ok","week_start":"2026-10-12","worked_seconds":1,"future_flag":{"a":[1,2]},"#
            + #""tiers":[{"hours":20,"ruby":20,"claimed":false,"label":"첫 단계","tier_id":7}],"#
            + #""granted_now":[{"hours":20,"ruby":20,"ledger_id":99,"kst_day":"2026-10-16"}],"ruby_balance":3}"#
        let status = try V0355WeeklyStub.decode(json)
        #expect(status.tiers.count == 1 && status.grantedNow == [.init(hours: 20, ruby: 20)])
        #expect(status.rubyBalance == 3 && status.isUsable)
    }

    @Test("모양이 틀린 칸은 그 칸만 버린다 — 깨진 단계 행 · 문자열 숫자 · 소수 초 · 배열 아닌 표")
    func wrongShapesDropOnlyThatCell() throws {
        let json = #"{"worked_seconds":83456.7,"ruby_balance":"lots","server_now_ms":null,"#
            + #""tiers":[null,5,{"hours":"x","ruby":1},{"hours":40,"ruby":50,"claimed":"yes"},{"hours":20,"ruby":20,"claimed":true}],"#
            + #""granted_now":"nope"}"#
        let status = try V0355WeeklyStub.decode(json)
        #expect(status.workedSeconds == 83_456, "소수 초 하나에 줄이 사라지면 안 된다")
        #expect(status.rubyBalance == nil && status.serverNowMs == nil)
        // 깨진 셋은 버리고 둘은 산다 — 그리고 시간 오름차순으로 정렬된다(서버 순서에 기대지 않는다).
        #expect(status.tiers == [.init(hours: 20, ruby: 20, claimed: true), .init(hours: 40, ruby: 50, claimed: false)])
        #expect(status.grantedNow.isEmpty)
        // 대조군: 표가 배열이 아니면 비고, 줄은 안 그린다.
        let notList = try V0355WeeklyStub.decode(#"{"worked_seconds":1,"tiers":{"hours":20}}"#)
        #expect(notList.tiers.isEmpty && !notList.isUsable)
    }

    @Test("최상위가 객체가 아니면 응답이 아니다 — throw(스토어는 알던 값을 지키고 넘어간다)")
    func nonObjectThrows() {
        #expect(throws: (any Error).self) { try V0355WeeklyStub.decode("[]") }
        #expect(throws: (any Error).self) { try V0355WeeklyStub.decode("null") }
    }
}

// MARK: - ② 게이지(코어 · 맥·폰 한 벌) · 문구
//
// 사장님 늦은 변경(2026-10-16 12:4x): 게이지는 **지금 퀘스트 하나** — 누적초가 못 넘은 첫 단계가 기준이고(20 → 40 → 60),
// 채움은 이번 주 누적 ÷ 퀘스트 시간(구간이 아니다), 60시간을 넘으면 완료. 기대값은 손으로 적은 숫자다.

@Suite struct V0355WeeklyGaugeTests {
    let h = V0355WeeklyStub.hour
    /// 표 그대로(시간 오름차순) — `claimed` 는 20·40·60 순서.
    func gauge(_ worked: Int, _ claimed: [Bool] = [false, false, false]) throws -> WeeklyWorkGauge {
        try #require(V0355WeeklyStub.status(worked: worked, claimed: claimed).gauge)
    }

    @Test("0시간 — 20시간 퀘스트 · 채움 0 · 보상 20")
    func zero() throws {
        let g = try gauge(0)
        #expect(g == WeeklyWorkGauge(questHours: 20, fill: 0, isComplete: false, reward: 20, claimedTotal: 0))
    }

    @Test("19:59:59 — 아직 20시간 퀘스트(문턱 1초 전) · 채움 71999/72000")
    func oneSecondBeforeTwenty() throws {
        let g = try gauge(20 * h - 1)
        #expect(g.questHours == 20 && !g.isComplete && g.reward == 20)
        #expect(g.fill == 71_999.0 / 72_000.0)
    }

    @Test("20:00:00 — 40시간 퀘스트로 넘어가고 게이지는 이미 절반(구간이 아니라 누적) · 장부가 아직이어도 같다")
    func exactlyTwenty() throws {
        let paid = try gauge(20 * h, [true, false, false])
        #expect(paid == WeeklyWorkGauge(questHours: 40, fill: 0.5, isComplete: false, reward: 50, claimedTotal: 20))
        // cron 이 아직(claimed 거짓) — 퀘스트는 누적초로 고른다. claimed 로 고르면 1분 동안 "20시간 달성하기"가 남는다.
        let pending = try gauge(20 * h)
        #expect(pending.questHours == 40 && pending.fill == 0.5 && pending.claimedTotal == 0)
    }

    @Test("30시간 — 40시간 퀘스트 · 채움 0.75")
    func thirty() throws {
        let g = try gauge(30 * h, [true, false, false])
        #expect(g.questHours == 40 && g.fill == 0.75 && g.reward == 50)
    }

    @Test("40:00:00 — 60시간 퀘스트 · 채움 2/3 · 보상 200")
    func exactlyForty() throws {
        let g = try gauge(40 * h, [true, true, false])
        #expect(g.questHours == 60 && !g.isComplete && g.reward == 200 && g.claimedTotal == 70)
        #expect(abs(g.fill - 2.0 / 3.0) < 1e-12)
    }

    @Test("45시간 — 60시간 게이지 75%(사장님 예시)")
    func fortyFive() throws {
        #expect(try gauge(45 * h, [true, true, false]).fill == 0.75)
    }

    @Test("59:59:59 — 아직 60시간 퀘스트 · 완료 아님")
    func oneSecondBeforeSixty() throws {
        let g = try gauge(60 * h - 1, [true, true, false])
        #expect(g.questHours == 60 && !g.isComplete)
        #expect(g.fill == 215_999.0 / 216_000.0)
    }

    @Test("60:00:00 — 완료 · 가득 · 받은 합 270")
    func exactlySixty() throws {
        let g = try gauge(60 * h, [true, true, true])
        #expect(g.isComplete && g.fill == 1 && g.claimedTotal == 270)
    }

    @Test("80시간 — 완료 · 채움 1 에서 멈춘다")
    func eighty() throws {
        let g = try gauge(80 * h, [true, true, true])
        #expect(g.isComplete && g.fill == 1 && g.claimedTotal == 270)
    }

    @Test("완료인데 장부가 늦다 — 완료로 그리되 받은 합은 장부만큼(70) · 아무것도 안 들어왔으면 0")
    func completeButClaimsLagging() throws {
        let lagging = try gauge(61 * h, [true, true, false])
        #expect(lagging.isComplete && lagging.fill == 1 && lagging.claimedTotal == 70)
        #expect(try gauge(61 * h).claimedTotal == 0)
    }

    @Test("표 순서를 섞어 보내도 · 같은 단계가 두 번 와도 같은 답 · 빈 표는 게이지 없음 · 모르는 누적초도 없음")
    func normalizationAndUnknowns() throws {
        let shuffled = WeeklyWorkGauge.make(workedSeconds: 30 * h, tiers: [
            .init(hours: 60, ruby: 200, claimed: false), .init(hours: 20, ruby: 20, claimed: true),
            .init(hours: 40, ruby: 50, claimed: false), .init(hours: 20, ruby: 999, claimed: true),
        ])
        #expect(shuffled == WeeklyWorkGauge(questHours: 40, fill: 0.75, isComplete: false, reward: 50, claimedTotal: 20))
        #expect(WeeklyWorkGauge.make(workedSeconds: 30 * h, tiers: []) == nil)
        #expect(WeeklyWorkStatus(workedSeconds: 30 * h).gauge == nil, "표 없는 응답으로 게이지를 만들었다")
        #expect(V0355WeeklyStub.status(worked: nil).gauge == nil, "모르는 누적초를 0 으로 그렸다")
        // 넘긴 단계 표시: 진행 중이면 퀘스트 아래 단계만, 완료면 전부.
        let g = try gauge(45 * h, [true, false, false])
        #expect(V0355WeeklyStub.status(worked: 45 * h).tiers.filter { g.hasPassed($0) }.map(\.hours) == [20, 40])
        let done = try gauge(60 * h, [true, true, true])
        #expect(V0355WeeklyStub.status(worked: 60 * h).tiers.filter { done.hasPassed($0) }.map(\.hours) == [20, 40, 60])
    }
}

@Suite struct V0355WeeklyCopyTests {
    let h = V0355WeeklyStub.hour
    func copy(_ worked: Int, _ claimed: [Bool] = [false, false, false]) throws -> (title: String, chip: String?, detail: String) {
        let status = V0355WeeklyStub.status(worked: worked, claimed: claimed)
        let gauge = try #require(status.gauge)
        return (WeeklyWorkCopy.title(gauge), WeeklyWorkCopy.chip(gauge), WeeklyWorkCopy.detail(status, gauge: gauge))
    }

    @Test("0시간 — '이번 주 근무 · 20시간 달성하기' · '💎 +20' · '0분 / 20시간'")
    func zeroHours() throws {
        let c = try copy(0)
        #expect(c.title == "이번 주 근무 · 20시간 달성하기" && c.chip == "💎 +20" && c.detail == "0분 / 20시간")
    }

    @Test("19:59:59 — 아직 20시간 퀘스트(분은 내림)")
    func oneSecondBeforeTheFirstTier() throws {
        let c = try copy(20 * h - 1)
        #expect(c.title == "이번 주 근무 · 20시간 달성하기" && c.detail == "19시간 59분 / 20시간")
    }

    @Test("23시간 12분 — 설계서 예시 그대로('이번 주 근무 · 40시간 달성하기' · '23시간 12분 / 40시간' · '💎 +50')")
    func specExampleLine() throws {
        let c = try copy(23 * h + 12 * 60 + 5, [true, false, false])
        #expect(c.title == "이번 주 근무 · 40시간 달성하기")
        #expect(c.detail == "23시간 12분 / 40시간")
        #expect(c.chip == "💎 +50")
    }

    @Test("40시간 · 59시간 — 60시간 퀘스트 · '💎 +200'")
    func sixtyQuest() throws {
        #expect(try copy(40 * h, [true, true, false]).title == "이번 주 근무 · 60시간 달성하기")
        let c = try copy(59 * h, [true, true, false])
        #expect(c.detail == "59시간 / 60시간" && c.chip == "💎 +200")
    }

    @Test("60시간+ — '이번 주 근무 완료' · '💎 +270 받았어요'(장부 합) · 다음 목표 없음")
    func complete() throws {
        let c = try copy(71 * h, [true, true, true])
        #expect(c.title == "이번 주 근무 완료" && c.chip == "💎 +270 받았어요" && c.detail == "71시간")
        #expect(!c.detail.contains("/"), "완료인데 다음 목표를 말한다")
    }

    @Test("완료인데 장부가 늦다 — 받은 만큼만(+70) · 하나도 없으면 칩 없음(안 준 루비를 받았다고 말하지 않는다)")
    func completeButLagging() throws {
        #expect(try copy(61 * h, [true, true, false]).chip == "💎 +70 받았어요")
        let none = try copy(61 * h)
        #expect(none.title == "이번 주 근무 완료" && none.chip == nil)
    }

    @Test("숫자는 응답 표에서 온다 — 표가 바뀌면 문구도 바뀐다(기준선이 다른 대조군)")
    func copyFollowsTheServerTable() throws {
        let other = try V0355WeeklyStub.decode(#"{"worked_seconds":3600,"tiers":[{"hours":10,"ruby":7,"claimed":false},{"hours":30,"ruby":11,"claimed":false}]}"#)
        let gauge = try #require(other.gauge)
        #expect(WeeklyWorkCopy.title(gauge) == "이번 주 근무 · 10시간 달성하기")
        #expect(WeeklyWorkCopy.chip(gauge) == "💎 +7" && WeeklyWorkCopy.detail(other, gauge: gauge) == "1시간 / 10시간")
        #expect(WeeklyWorkCopy.rule(other) == "월요일 0시에 새로 세요 · 10시간 7 · 30시간 11")
        #expect(other.totalRuby == 18)
    }

    @Test("규칙 툴팁 한 줄 — '월요일 0시에 새로 세요 · 20시간 20 · 40시간 50 · 60시간 200'")
    func ruleTooltip() {
        #expect(WeeklyWorkCopy.rule(V0355WeeklyStub.status(worked: 0))
                == "월요일 0시에 새로 세요 · 20시간 20 · 40시간 50 · 60시간 200")
        #expect(WeeklyWorkCopy.tierMark(.init(hours: 40, ruby: 50, claimed: false)) == "40")
    }

    @Test("받은 알림 문구 — 하나 · 여럿(가장 높은 단계 + 합계) · 지난주 소급뿐 · 빈 목록")
    func grantNotice() {
        #expect(WeeklyWorkCopy.grantNotice([.init(hours: 20, ruby: 20)]) == "이번 주 20시간 채웠어요 — 루비 +20")
        #expect(WeeklyWorkCopy.grantNotice([.init(hours: 20, ruby: 20), .init(hours: 40, ruby: 50)])
                == "이번 주 40시간 채웠어요 — 루비 +70")
        #expect(WeeklyWorkCopy.grantNotice([.init(hours: 60, ruby: 200, weekStart: "2026-10-05")])
                == "지난주 60시간 채웠어요 — 루비 +200")
        // 지난주 소급과 이번 주가 함께 오면 "이번 주" 로 말하고 합계는 둘 다 센다.
        #expect(WeeklyWorkCopy.grantNotice([.init(hours: 60, ruby: 200, weekStart: "2026-10-05"), .init(hours: 20, ruby: 20)])
                == "이번 주 20시간 채웠어요 — 루비 +220")
        #expect(WeeklyWorkCopy.grantNotice([]) == nil)
    }
}

// MARK: - "방금 받았다" 판정(순수)

@Suite struct V0355WeeklyNewlyGrantedTests {
    let h = V0355WeeklyStub.hour

    @Test("granted_now — 이 호출이 넣은 행(첫 조회여도)")
    func grantedNowCounts() {
        let now = V0355WeeklyStub.status(worked: 20 * h, claimed: [true, false, false], granted: [.init(hours: 20, ruby: 20)])
        #expect(now.newlyGranted(since: nil) == [.init(hours: 20, ruby: 20)])
    }

    @Test("cron 이 먼저 넣은 행 — 같은 주에서 claimed 가 거짓 → 참으로 바뀐 단계")
    func claimedTransitionCounts() {
        let before = V0355WeeklyStub.status(worked: 19 * h, claimed: [false, false, false])
        let after = V0355WeeklyStub.status(worked: 41 * h, claimed: [true, true, false])
        #expect(after.newlyGranted(since: before) == [.init(hours: 20, ruby: 20), .init(hours: 40, ruby: 50)])
        // 같은 응답을 또 받으면 새로 받은 것이 없다.
        #expect(after.newlyGranted(since: after).isEmpty)
    }

    @Test("둘이 겹치면 한 번만 센다 · 이번 주 행에 week_start 가 실려 와도 같은 뜻")
    func dedupesBothSources() {
        let before = V0355WeeklyStub.status(worked: 19 * h)
        let after = V0355WeeklyStub.status(worked: 20 * h, claimed: [true, false, false],
                                          granted: [.init(hours: 20, ruby: 20, weekStart: "2026-10-12")])
        #expect(after.newlyGranted(since: before) == [.init(hours: 20, ruby: 20, weekStart: nil)])
    }

    @Test("실행 뒤 첫 조회에서 이미 참인 단계는 '방금'이 아니다(어제 받았을 수도 있다)")
    func firstFetchDoesNotInventGrants() {
        let first = V0355WeeklyStub.status(worked: 45 * h, claimed: [true, true, false])
        #expect(first.newlyGranted(since: nil).isEmpty)
    }

    @Test("주가 바뀌면 전이를 보지 않는다 · 지난주 소급은 granted_now 로만 온다(week_start 를 지닌 채)")
    func newWeekOnlyTrustsGrantedNow() {
        let lastWeek = V0355WeeklyStub.status(worked: 59 * h, claimed: [true, true, false], weekStart: "2026-10-05")
        let thisWeek = V0355WeeklyStub.status(worked: 600, claimed: [false, false, false],
                                             granted: [.init(hours: 60, ruby: 200, weekStart: "2026-10-05")],
                                             weekStart: "2026-10-12")
        #expect(thisWeek.newlyGranted(since: lastWeek) == [.init(hours: 60, ruby: 200, weekStart: "2026-10-05")])
        // 대조군: 지난주 표의 단계가 이번 주 표에서 참이어도(이상한 응답) 주가 다르면 전이로 세지 않는다.
        let oddThisWeek = V0355WeeklyStub.status(worked: 600, claimed: [true, false, false], weekStart: "2026-10-12")
        let oddLastWeek = V0355WeeklyStub.status(worked: 0, claimed: [false, false, false], weekStart: "2026-10-05")
        #expect(oddThisWeek.newlyGranted(since: oddLastWeek).isEmpty)
    }
}

// MARK: - ③ 스토어

@MainActor
@Suite(.serialized) struct V0355WeeklyStoreTests {
    static func host(_ label: String) -> String { "v0355-weekly-\(label)-\(UUID().uuidString.prefix(8))".lowercased() }
    static let rpc = "weekly_work_status"
    static let t0 = Date(timeIntervalSince1970: 1_781_000_000)

    static func register(host: String, weekly: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply) {
        GomokuStubProtocol.register(host: host) { rpc, _, index in
            rpc == "weekly_work_status" ? weekly(index) : nil
        }
    }

    static func store(host: String, label: String, clock: V0355Clock, function: String = #function) -> WorkTimerStore {
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!,
                                          anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let store = WorkTimerStore(service: service,
                                   environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: CheckTestScratch.defaults("v0355-weekly-" + label, function: function))
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
        store.membershipConfirmed = true
        store.characterDefaults = CheckTestScratch.defaults("v0355-char-" + label, function: function)
        store.clock = { clock.now }
        V0354CoreStub.retain(store)
        return store
    }

    static func count(_ host: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

    /// 스텁이 마저 답할 틈(요청이 **안** 나갔음을 잴 때 — 나갔다면 이 사이에 기록된다).
    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(60))
    }

    @Test("서비스 — POST /rest/v1/rpc/weekly_work_status, 본문 {} · 응답이 그대로 스토어에 선다")
    func serviceShapeAndApply() async throws {
        let host = Self.host("wire")
        Self.register(host: host) { _ in .init(body: V0355WeeklyStub.json(worked: 83_456, claimed: [true, false, false])) }
        let clock = V0355Clock(Self.t0)
        let store = Self.store(host: host, label: "wire", clock: clock)
        let task = try #require(store.refreshWeeklyWork(reason: .walletCadence))
        await task.value
        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: Self.rpc).first)
        #expect(call.body == "{}")
        #expect(SupabaseWorkService.weeklyWorkStatusPath == "/rest/v1/rpc/weekly_work_status")
        #expect(store.weeklyWork?.workedSeconds == 83_456)
        #expect(store.weeklyWork?.gauge?.questHours == 40)
        #expect(store.rubyBalance == 1057)
    }

    @Test("박자 — 지갑 sync 가 부르면 함께 묻고, 1분 안의 다음 박자는 요청 0건 · 1분이 지나면 다시")
    func rideTheWalletCadenceAtMostOncePerMinute() async throws {
        let host = Self.host("cadence")
        Self.register(host: host) { _ in .init(body: V0355WeeklyStub.json(worked: 3_600)) }
        let clock = V0355Clock(Self.t0)
        let store = Self.store(host: host, label: "cadence", clock: clock)

        store.syncUltraWallet(reason: .panelOpen)
        #expect(await V0354CoreStub.waitUntil { Self.count(host) == 1 && store.weeklyWork != nil })
        store.syncUltraWallet(reason: .panelOpen)
        clock.advance(59)
        store.syncUltraWallet(reason: .periodic)
        store.syncUltraWallet(reason: .missionCandidate)
        await Self.settle()
        #expect(Self.count(host) == 1, "1분 안에 \(Self.count(host))번 물었다")
        #expect(!store.weeklyWorkFetchOwed, "지갑 박자는 빚을 남기지 않는다(1분 안의 값이 이미 있다)")

        clock.advance(1)
        store.syncUltraWallet(reason: .periodic)
        #expect(await V0354CoreStub.waitUntil { Self.count(host) == 2 })
    }

    @Test("근무 종료 직후의 조회가 1분 창에 막히면 빚으로 남고, 폴링 tick 이 1분이 지나 한 번 갚는다")
    func workEndedIsOwedAndRepaidByTheTick() async throws {
        let host = Self.host("owed")
        Self.register(host: host) { _ in .init(body: V0355WeeklyStub.json(worked: 3_600)) }
        let clock = V0355Clock(Self.t0)
        let store = Self.store(host: host, label: "owed", clock: clock)

        await store.refreshWeeklyWork(reason: .walletCadence)?.value
        #expect(Self.count(host) == 1)
        clock.advance(10)
        #expect(store.refreshWeeklyWork(reason: .workEnded) == nil)
        #expect(store.weeklyWorkFetchOwed)
        // tick 이 일러도 안 나간다.
        clock.advance(40)
        await store.localExpiryTick()
        await Self.settle()
        #expect(Self.count(host) == 1 && store.weeklyWorkFetchOwed)
        // 1분이 지난 tick — 정확히 한 번 갚는다.
        clock.advance(11)
        await store.localExpiryTick()
        #expect(await V0354CoreStub.waitUntil { Self.count(host) == 2 })
        #expect(!store.weeklyWorkFetchOwed)
        clock.advance(120)
        await store.localExpiryTick()
        await Self.settle()
        #expect(Self.count(host) == 2, "빚이 없는 비근무 tick 이 주간 조회를 냈다(요청 0건이 기본값이다)")
    }

    @Test("근무 종료(stop) → 종료 기록이 큐를 지난 **뒤에** 주간 조회가 한 번 나간다")
    func stopFetchesAfterTheStopWrite() async throws {
        let host = Self.host("stop")
        Self.register(host: host) { _ in .init(body: V0355WeeklyStub.json(worked: 7_200)) }
        let clock = V0355Clock(Self.t0)
        let store = Self.store(host: host, label: "stop", clock: clock)
        store.start(now: Self.t0.addingTimeInterval(-3_600))
        await store.syncTask?.value
        let before = GomokuStubProtocol.calls(host: host).count
        #expect(Self.count(host) == 0)

        store.stop(now: Self.t0)
        #expect(await V0354CoreStub.waitUntil { Self.count(host) == 1 })
        let calls = GomokuStubProtocol.calls(host: host).dropFirst(before).map(\.rpc)
        let weeklyIndex = try #require(calls.firstIndex(of: Self.rpc))
        let lastSessionWrite = try #require(calls.lastIndex(of: "/rest/v1/work_sessions"), "종료 기록이 안 나갔다: \(calls)")
        #expect(lastSessionWrite < weeklyIndex, "주간 조회가 종료 기록보다 먼저 나갔다: \(calls)")
    }

    @Test("세션이 없으면 요청 0건")
    func noSessionNoRequest() async {
        let host = Self.host("nosession")
        Self.register(host: host) { _ in .init(body: V0355WeeklyStub.json(worked: 1)) }
        let store = Self.store(host: host, label: "nosession", clock: V0355Clock(Self.t0))
        store.session = nil
        #expect(store.refreshWeeklyWork(reason: .walletCadence) == nil)
        await Self.settle()
        #expect(Self.count(host) == 0)
    }

    @Test("이 호출이 지급했다 — 잔량은 서버 값 · 상점 변이로 적는다 · 안내줄 + 말풍선 '루비 +20'")
    func grantedNowIsAcknowledged() async throws {
        let host = Self.host("granted")
        Self.register(host: host) { _ in
            .init(body: V0355WeeklyStub.json(worked: 20 * 3_600 + 30, claimed: [true, false, false], granted: [(20, 20, nil)], ruby: 1057))
        }
        let store = Self.store(host: host, label: "granted", clock: V0355Clock(Self.t0))
        store.rubyBalance = 1037
        var fired: [ReactionKind] = []
        store.onRewardTrigger = { fired.append($0) }
        let serial = store.shopMutationSerial
        await store.refreshWeeklyWork(reason: .walletCadence)?.value
        #expect(store.rubyBalance == 1057)
        #expect(store.shopMutationSerial == serial + 1, "지급한 응답이 상점 변이로 안 적혔다 — 늦게 온 상점 조회가 잔량을 되돌린다")
        #expect(store.missionNotice == "이번 주 20시간 채웠어요 — 루비 +20")
        #expect(fired == [.rubyReward(amount: 20)])
    }

    @Test("잔량은 새 값 위에 덮지 않는다 — 떠난 뒤 다른 쓰기(뽑기 등)가 있었으면 버리고, 없었으면 옮긴다")
    func rubyBalanceIsNotRegressed() async throws {
        // 기준선: 사이에 쓰기가 없으면 서버 값이 선다.
        let plainHost = Self.host("ruby-plain")
        Self.register(host: plainHost) { _ in .init(body: V0355WeeklyStub.json(worked: 1, ruby: 500), delay: 0.2) }
        let plain = Self.store(host: plainHost, label: "ruby-plain", clock: V0355Clock(Self.t0))
        plain.rubyBalance = 480
        await plain.refreshWeeklyWork(reason: .walletCadence)?.value
        #expect(plain.rubyBalance == 500)

        // 떠난 뒤 뽑기 응답이 999 를 썼다 — 늦게 온 500 이 덮으면 잔량이 한 판 전으로 돌아간다.
        let host = Self.host("ruby-race")
        Self.register(host: host) { _ in .init(body: V0355WeeklyStub.json(worked: 1, ruby: 500), delay: 0.2) }
        let store = Self.store(host: host, label: "ruby-race", clock: V0355Clock(Self.t0))
        store.rubyBalance = 480
        let task = try #require(store.refreshWeeklyWork(reason: .walletCadence))
        #expect(await V0354CoreStub.waitUntil { Self.count(host) == 1 })
        store.rubyBalance = 999
        await task.value
        #expect(store.rubyBalance == 999, "늦게 온 주간 응답이 새 잔량을 덮었다")
        #expect(store.weeklyWork?.workedSeconds == 1, "잔량만 버리고 줄은 옮겨야 한다")
    }

    @Test("버린 응답이 지급을 실었으면 상점을 다시 읽는다(옛 잔량이 화면에 남지 않게)")
    func discardedGrantRereadsTheShop() {
        let host = Self.host("reread")
        GomokuStubProtocol.register(host: host, handler: V0354CoreStub.shopHandler)
        let store = Self.store(host: host, label: "reread", clock: V0355Clock(Self.t0))
        store.rubyBalance = 10
        let departed = store.rubyBalanceWriteSerial
        store.rubyBalance = 11   // 그 사이 다른 쓰기
        store.applyWeeklyWork(V0355WeeklyStub.status(worked: 20 * 3_600, claimed: [true, false, false],
                                                     granted: [.init(hours: 20, ruby: 20)], ruby: 31),
                              rubyWriteSerialAtDeparture: departed)
        #expect(store.rubyBalance == 11)
        #expect(store.shopLoading, "지급을 버렸는데 사실을 다시 읽지 않는다")
    }

    @Test("cron 이 먼저 넣은 단계도 알린다 — 같은 주 전이 한 번, 같은 응답이 또 와도 다시 안 알린다 · 첫 조회는 안 알린다")
    func claimedTransitionIsAcknowledgedOnce() {
        let store = Self.store(host: Self.host("transition"), label: "transition", clock: V0355Clock(Self.t0))
        var fired: [ReactionKind] = []
        store.onRewardTrigger = { fired.append($0) }

        // 실행 뒤 첫 조회 — 이미 받은 단계가 있어도 '방금'이 아니다.
        store.applyWeeklyWork(V0355WeeklyStub.status(worked: 39 * 3_600, claimed: [true, false, false]))
        #expect(fired.isEmpty && store.missionNotice == nil)
        // cron 이 40시간을 넣었다(granted_now 는 비어 있다).
        let crossed = V0355WeeklyStub.status(worked: 40 * 3_600 + 60, claimed: [true, true, false])
        store.applyWeeklyWork(crossed)
        #expect(fired == [.rubyReward(amount: 50)])
        #expect(store.missionNotice == "이번 주 40시간 채웠어요 — 루비 +50")
        store.applyWeeklyWork(crossed)
        #expect(fired.count == 1, "같은 단계를 두 번 알렸다")
    }

    @Test("줄을 그릴 만큼 모르는 응답은 알던 값을 덮지 않는다 · 실패(함수 없음 404)도 지우지 않는다")
    func unusableOrFailedKeepsTheLastKnownRow() async throws {
        let host = Self.host("keep")
        Self.register(host: host) { index in
            index == 0
                ? .init(body: V0355WeeklyStub.json(worked: 3_600))
                : .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.weekly_work_status without parameters in the schema cache"}"#)
        }
        let clock = V0355Clock(Self.t0)
        let store = Self.store(host: host, label: "keep", clock: clock)
        await store.refreshWeeklyWork(reason: .walletCadence)?.value
        let known = try #require(store.weeklyWork)
        store.applyWeeklyWork(WeeklyWorkStatus(workedSeconds: 7_200))   // 표가 없다
        #expect(store.weeklyWork == known)
        clock.advance(61)
        await store.refreshWeeklyWork(reason: .walletCadence)?.value
        #expect(Self.count(host) == 2)
        #expect(store.weeklyWork == known, "실패가 알던 줄을 지웠다")
    }

    @Test("로그아웃은 주간 상태를 비운다(남의 이번 주를 그리지 않는다)")
    func signOutClears() {
        let store = Self.store(host: Self.host("signout"), label: "signout", clock: V0355Clock(Self.t0))
        store.applyWeeklyWork(V0355WeeklyStub.status(worked: 3_600))
        store.lastWeeklyWorkFetchAt = Self.t0
        store.weeklyWorkFetchOwed = true
        #expect(store.weeklyWork != nil)
        store.clearPersistedSession()
        #expect(store.weeklyWork == nil && store.lastWeeklyWorkFetchAt == nil && !store.weeklyWorkFetchOwed)
    }
}

// MARK: - ④ 화면(울트라 화면의 주간 줄)

@MainActor
@Suite(.serialized) struct V0355WeeklyRenderTests {
    static func store(weekly: WeeklyWorkStatus?, missionCount: Int = 3, notice: String? = nil,
                      function: String = #function, line: Int = #line) -> WorkTimerStore {
        let tag = "v0355-render-L\(line)"
        let home = CheckTestScratch.directory("token-\(tag)", function: function)
        let tokens = TokenUsageStore(
            defaults: CheckTestScratch.defaults("token-\(tag)", function: function),
            homeDirectory: home.appendingPathComponent("home", isDirectory: true),
            cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
        )
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
                                   defaults: CheckTestScratch.defaults(tag, function: function),
                                   tokenUsage: tokens)
        store.isMenuPresented = true
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
        store.displayNow = Date(timeIntervalSince1970: 1_781_000_000)
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.teamName = "아잉팀"
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
        store.ultraBalance = 3
        store.missionNotice = notice
        let all = [
            MissionProgress(kind: .todayThreeHours, progress: 0.5, claimedToday: false, cappedToday: false, detail: "다음 하나까지 1시간 30분"),
            MissionProgress(kind: .dailyFloor, progress: nil, claimedToday: true, cappedToday: false, detail: "잔량 0이면 1개로"),
            MissionProgress(kind: .arrivalStreak, progress: nil, claimedToday: true, cappedToday: false, detail: "5일 연속"),
        ]
        store.missions = Array(all.prefix(missionCount))
        store.missionsLoaded = true
        store.weeklyWork = weekly
        store.isUltraPanelVisible = true
        return store
    }

    /// `clips` — 넘치는 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안쪽을 못 그린다 — 미리보기 전용).
    static func bitmap(_ store: WorkTimerStore, banner: Bool = false, clips: Bool = false) throws -> NSBitmapImageRep {
        let view = CheckMenuView(store: store, previewClipsOverflowList: clips, previewUpdateBanner: banner)
        return try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2))
    }

    static func png(_ store: WorkTimerStore, clips: Bool = false) throws -> Data {
        try #require(try bitmap(store, clips: clips).representation(using: .png, properties: [:]))
    }

    @Test("줄이 그려진다 · 그릴 만큼 모르면(표 없음) 안 그린다 · 받은 단계가 그림으로 갈린다")
    func rowDrawsAndClaimedStateIsVisible() throws {
        let h = V0355WeeklyStub.hour
        let none = try Self.png(Self.store(weekly: nil))
        // 대조군: 같은 입력이면 바이트까지 같다.
        #expect(none == (try Self.png(Self.store(weekly: nil))))
        let row = try Self.png(Self.store(weekly: V0355WeeklyStub.status(worked: 10 * h)))
        #expect(row != none, "주간 줄이 안 그려졌다")
        #expect(try Self.png(Self.store(weekly: WeeklyWorkStatus(workedSeconds: 10 * h))) == none,
                "표 없는 응답으로 줄을 그렸다 — 모르는 것을 0 으로 그리는 거짓말")
        // 23시간 — 20 을 받음 vs 장부가 아직(cron ≤ 1분). 퀘스트(40) · 게이지 · 문구는 **같고**(누적초로 고른다) 넘긴 단계 표시
        // (체크 + 근무색 vs 흐림)와 아이콘 색만 다르다.
        let worked = 23 * h + 12 * 60
        let pending = V0355WeeklyStub.status(worked: worked)
        let paid = V0355WeeklyStub.status(worked: worked, claimed: [true, false, false])
        let pendingGauge = try #require(pending.gauge)
        let paidGauge = try #require(paid.gauge)
        #expect(WeeklyWorkCopy.title(pendingGauge) == WeeklyWorkCopy.title(paidGauge))
        #expect(WeeklyWorkCopy.detail(pending, gauge: pendingGauge) == WeeklyWorkCopy.detail(paid, gauge: paidGauge))
        #expect(pendingGauge.fill == paidGauge.fill)
        let pendingPNG = try Self.png(Self.store(weekly: pending))
        #expect(pendingPNG == (try Self.png(Self.store(weekly: pending))), "같은 입력인데 그림이 다르다(대조군)")
        #expect(try Self.png(Self.store(weekly: paid)) != pendingPNG, "받은 단계가 그림에 안 나타난다")
        // 완료(60시간+)는 진행 중(59:59:59)과 다른 그림이다(제목 · 칩 · 근무색 게이지).
        let almost = try Self.png(Self.store(weekly: V0355WeeklyStub.status(worked: 60 * h - 1, claimed: [true, true, false])))
        let done = try Self.png(Self.store(weekly: V0355WeeklyStub.status(worked: 60 * h, claimed: [true, true, true])))
        #expect(done != almost)
    }

    @Test("팝오버 높이 상한 — 미션 셋 + 주간 줄 + 안내줄 + 새 버전 배너에서도 ≤ 700pt · 줄이 없는 창보다 작지 않다")
    func heightBudget() throws {
        let h = V0355WeeklyStub.hour
        let worst = Self.store(weekly: V0355WeeklyStub.status(worked: 71 * h, claimed: [true, true, true]),
                               notice: "이번 주 60시간 채웠어요 — 루비 +270")
        let height = Double(try Self.bitmap(worst, banner: true).pixelsHigh) / 2
        #expect(height <= 700, "팝오버 높이 \(height)pt")
        let without = Double(try Self.bitmap(Self.store(weekly: nil, notice: "이번 주 60시간 채웠어요 — 루비 +270"), banner: true).pixelsHigh) / 2
        #expect(height >= without)
        // 미션이 아직 없는 화면(불러오는 중)에서도 주간 줄이 서고 상한 안이다.
        let loading = Self.store(weekly: V0355WeeklyStub.status(worked: h), missionCount: 0)
        #expect(Double(try Self.bitmap(loading, banner: true).pixelsHigh) / 2 <= 700)
    }

    /// 미리보기 PNG — 환경변수 `CHECK_V0355_MAC_PREVIEW_DIR` 가 있을 때만 떨군다(없으면 아무것도 안 한다). 창은 띄우지 않는다.
    @Test("미리보기(환경변수가 있을 때만) — 0시간 · 23시간 12분 · 40시간(60 퀘스트) · 완료 · 완료인데 장부가 늦음")
    func previewStills() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_V0355_MAC_PREVIEW_DIR"] else { return }
        let h = V0355WeeklyStub.hour
        let cases: [(String, WeeklyWorkStatus, String?)] = [
            ("mac-weekly-0h", V0355WeeklyStub.status(worked: 0), nil),
            ("mac-weekly-23h", V0355WeeklyStub.status(worked: 23 * h + 12 * 60, claimed: [true, false, false]),
             "이번 주 20시간 채웠어요 — 루비 +20"),
            ("mac-weekly-reached", V0355WeeklyStub.status(worked: 40 * h + 30, claimed: [true, false, false]), nil),
            ("mac-weekly-all", V0355WeeklyStub.status(worked: 61 * h, claimed: [true, true, true]), nil),
            ("mac-weekly-lagging", V0355WeeklyStub.status(worked: 60 * h + 20, claimed: [true, true, false]), nil),
        ]
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, status, notice) in cases {
            try Self.png(Self.store(weekly: status, notice: notice), clips: true)
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    @Test("주간 줄은 3시간 줄 바로 아래에 선다(소스 순서 — 주석 제외)")
    func rowSitsUnderTheLapRow() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check/CheckMenuView.swift")
        let code = v0355StripComments(try String(contentsOf: url, encoding: .utf8))
        let lap = try #require(code.range(of: "ForEach(missions.prefix(1)) { MissionRowView(mission: $0) }"))
        let weekly = try #require(code.range(of: "if let weeklyRow { WeeklyWorkRowView(status: weeklyRow) }", range: lap.upperBound..<code.endIndex))
        let rest = try #require(code.range(of: "ForEach(missions.dropFirst()) { MissionRowView(mission: $0) }", range: weekly.upperBound..<code.endIndex))
        #expect(lap.upperBound <= weekly.lowerBound && weekly.upperBound <= rest.lowerBound)
        #expect(code.contains(".checkTooltip(WeeklyWorkCopy.rule(status))"), "규칙 툴팁이 줄에 없다")
    }
}

// MARK: - ⑤ 캐릭터 말풍선(.rubyReward)

@MainActor
@Suite struct V0355RubyRewardReactionTests {
    @Test("숫자만 다르고 나머지는 랩 보상과 한 벌 — 순위 · 길이 · 말풍선 '루비 +N!'")
    func sameRulesDifferentNumber() {
        #expect(ReactionKind.rubyReward(amount: 20).priority == ReactionKind.ultraCharged.priority)
        #expect(ReactionKind.rubyReward(amount: 20).duration == ReactionKind.ultraCharged.duration)
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 92_500) })
        #expect(engine.request(.rubyReward(amount: 200)))
        #expect(engine.greetingText == "루비 +200!")
        // 대조군: 랩 보상은 여전히 +3 이다.
        let lap = ReactionEngine(clock: { Date(timeIntervalSince1970: 92_600) })
        #expect(lap.request(.ultraCharged))
        #expect(lap.greetingText == "루비 +3!")
    }

    @Test("찌름에는 양보하고 인사·마일스톤에는 안 밀린다 · 자는 중에도 깨워서 알린다")
    func yieldsLikeTheLapReward() {
        let reward = ReactionKind.rubyReward(amount: 50)
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 93_500) })
        #expect(engine.request(reward))
        #expect(engine.request(.greeting(name: "영희")) == false)
        #expect(engine.request(.milestone) == false)
        #expect(engine.state == .playing(reward))
        #expect(engine.request(.poked(bubbleText: "콕!")))
        #expect(engine.state == .playing(.poked(bubbleText: "콕!")))

        let sleeper = ReactionEngine(clock: { Date(timeIntervalSince1970: 95_500) })
        #expect(sleeper.request(.drowsy))
        #expect(sleeper.request(reward))
        #expect(sleeper.state == .playing(reward))
        sleeper.stopSleeping()
    }

    @Test("장면이 붙기 전에 온 보상도 붙는 순간 모션을 재생한다")
    func attachReplays() throws {
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 99_500) })
        #expect(engine.request(.rubyReward(amount: 20)))
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
        let root = scene.rootNode
        let wrapper = try #require(root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
        engine.attach(node: wrapper, sceneRoot: root, view: SCNView())
        #expect(wrapper.action(forKey: "check.reaction") != nil)
    }
}

/// `//` · `/* */` 주석을 걷어낸다(문자열 리터럴 안의 `//` 는 남긴다) — 설명문에 같은 글자가 있어도 계약이 흔들리지 않게.
private func v0355StripComments(_ source: String) -> String {
    var out = ""
    var inString = false, inLine = false, inBlock = false, escaped = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; i += 1 }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; i += 1
        } else if c == "/", next == "*" {
            inBlock = true; i += 1
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        i += 1
    }
    return out
}
