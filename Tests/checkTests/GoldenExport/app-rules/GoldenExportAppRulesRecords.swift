// 원본: 없음(W1-c 골든 생성기 · 주간 · 날짜 · 기록 · 토큰 · 숫자 · AI 리밋 — Sources/CheckCore/{WeeklyWorkReward,CheckWorkInsights,MilestoneTracker,CheckTokenRowDisplay,CodexEffectiveRule,MenuBarStatusFormatter,AILimits,AILimitFreshnessRule}.swift 를 잰다)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-c 앱 규칙 — 기록 · 주간 보상 · 날짜 · 숫자 · 토큰 표시 · AI 리밋 골든(C§5.1 E11 · C§4 #30·#31·#32 · B-2 · B-6).
// Kotlin 은 core/rules/…/{weekly,insights,format,token,ailimit}.
//
//   · weekly/status        주간 누적 근무 보상: 관대한 디코드 · 게이지(지금 퀘스트) · 받기(v0.3.58) · 주 끝 · 새로 들어온 지급
//   · dates/parse          서버 시각 파서(소수초 · 시간대 · 내림) · KST 날짜 키(lenient 달력) · 주/일 시작 · 요일 인덱스
//   · dates/durations      시:분 표기 셋 · 메뉴바 제목 · 나이 문구(방금 · N분/시간/일 전)
//   · insights/computation E11: 히트맵 · 회고 · 일별 잔디 — 세션 행 + now → 결과(정수 초)
//   · insights/token       토큰 잔디 · 서버 일별 합치기 · Codex 유효 규칙 · 공유 비율 · 순위판 월/주 이동
//   · text/number-format   토큰 숫자(콤마 · 억/만 축약)
//   · dates/ailimit        AI 리밋: 창 길이 판정 · 제공자 어휘 · 신선도 등급 · 값/캡션 · 기기 접기 · 메인 맥
// Date 는 1970 기준 초 Double 비트로 싣는다(C§2.5 — Kotlin 도 Double 초로 1:1).

@Suite("GoldenExport app-rules — 기록 · 주간 · 날짜 · 숫자 · 토큰 · 리밋")
struct GoldenExportAppRulesRecords {
    static func n(_ value: Int?) -> GoldenJSON {
        guard let value else { return .null }
        if value >= -GoldenJSON.maxSafeInteger && value <= GoldenJSON.maxSafeInteger { return .int(value) }
        return .string("int:\(value)")
    }
    static func b(_ value: Bool?) -> GoldenJSON { value.map(GoldenJSON.bool) ?? .null }
    static func s(_ value: String?) -> GoldenJSON { value.map(GoldenJSON.string) ?? .null }
    static func d(_ value: Date?) -> GoldenJSON { value.map { .bits($0.timeIntervalSince1970) } ?? .null }
    static func f(_ value: Double?) -> GoldenJSON { value.map(GoldenJSON.bits) ?? .null }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func fixture(_ path: String) -> String {
        (try? String(contentsOf: GoldenRepo.url(path), encoding: .utf8)) ?? ""
    }

    static let kst = TeamWeeklyGoal.kstCalendar

    static func kstDate(_ y: Int, _ mo: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0, _ sec: Int = 0) -> Date {
        kst.date(from: DateComponents(year: y, month: mo, day: day, hour: h, minute: mi, second: sec))!
    }

    /// 기준 시각들 — 주 경계(월 0시 ±1초) · 하루 경계 · 월 경계 · 해 경계 · 데모 시계 · 소수초.
    static var nows: [Date] {
        [
            kstDate(2026, 10, 26, 0, 0, 0), kstDate(2026, 10, 25, 23, 59, 59), kstDate(2026, 10, 26, 0, 0, 1),
            kstDate(2026, 10, 28, 10, 30, 0), kstDate(2026, 11, 1, 0, 0, 0), kstDate(2026, 12, 31, 23, 59, 59),
            kstDate(2027, 1, 1, 0, 0, 0), kstDate(2027, 1, 4, 9, 0, 0), Date(timeIntervalSince1970: 1_789_621_500),
            Date(timeIntervalSince1970: 1_789_621_500.75), kstDate(2026, 10, 29, 8, 59, 59), kstDate(2026, 3, 2, 0, 0, 0),
            kstDate(2024, 2, 29, 12, 0, 0), kstDate(2026, 10, 3, 1, 0, 0),
        ]
    }

    // MARK: weekly/status

    static func tierJSON(_ tier: WeeklyWorkStatus.Tier) -> GoldenJSON {
        ["hours": n(tier.hours), "ruby": n(tier.ruby), "claimed": .bool(tier.claimed), "achieved": b(tier.achieved),
         "claimable": b(tier.claimable), "thresholdSeconds": n(tier.thresholdSeconds)]
    }

    static func grantJSON(_ grant: WeeklyWorkStatus.Grant) -> GoldenJSON {
        ["hours": n(grant.hours), "ruby": n(grant.ruby), "weekStart": s(grant.weekStart)]
    }

    static func gaugeJSON(_ gauge: WeeklyWorkGauge?, tiers: [WeeklyWorkStatus.Tier]) -> GoldenJSON {
        guard let gauge else { return .null }
        return ["questHours": n(gauge.questHours), "fillBits": .bits(gauge.fill), "isComplete": .bool(gauge.isComplete),
                "reward": n(gauge.reward), "claimedTotal": n(gauge.claimedTotal),
                "hasPassed": .array(tiers.map { .bool(gauge.hasPassed($0)) })]
    }

    static func weeklyJSON(_ status: WeeklyWorkStatus) -> GoldenJSON {
        let end = status.nextWeekStartDate
        return [
            "weekStart": s(status.weekStart), "nextWeekStart": s(status.nextWeekStart), "workedSeconds": n(status.workedSeconds),
            "tiers": .array(status.tiers.map(tierJSON)), "grantedNow": .array(status.grantedNow.map(grantJSON)),
            "rubyBalance": n(status.rubyBalance), "serverNowMs": n(status.serverNowMs),
            "pending": status.pending.map { .array($0.map { ["weekStart": .string($0.weekStart), "hours": n($0.hours), "ruby": n($0.ruby)] }) } ?? .null,
            "claimableRuby": n(status.claimableRuby), "claimedNow": .array(status.claimedNow.map(grantJSON)),
            "isUsable": .bool(status.isUsable), "displayWorkedSeconds": n(status.displayWorkedSeconds), "totalRuby": n(status.totalRuby),
            "supportsClaim": .bool(status.supportsClaim), "pendingRuby": n(status.pendingRuby), "pendingCount": n(status.pendingCount),
            "hasClaimable": .bool(status.hasClaimable), "claimedNowRuby": n(status.claimedNowRuby),
            "nextWeekStartDate": d(end),
            "hasEnded": .array([end.map { $0.addingTimeInterval(-1) }, end, end.map { $0.addingTimeInterval(1) }].map { now in
                now.map { .bool(status.hasEnded(at: $0)) } ?? .null
            }),
            "gauge": gaugeJSON(status.gauge, tiers: status.tiers),
        ]
    }

    static let weeklyFixtures = ["_me/rpc.weekly_work_status.json", "_me/rpc.weekly_work_status@demo-week-done.json",
                                 "_me/rpc.weekly_work_status@demo-week-legacy.json", "_me/rpc.weekly_work_claim.json",
                                 "_me-/rpc.weekly_work_status.json"]

    static let weeklyVariants: [(String, String)] = [
        ("empty", #"{}"#),
        ("lossy", #"{"week_start":"2026-10-26","next_week_start":"2026-11-02","worked_seconds":83456.9,"tiers":[{"hours":40,"ruby":50,"claimed":true},{"hours":20,"ruby":20,"claimed":"yes"},{"hours":0,"ruby":5},{"hours":60},{"hours":60,"ruby":200},{"hours":40,"ruby":99},7,null],"granted_now":[{"hours":20,"ruby":20},{"hours":"40","ruby":50},{"ruby":3}],"ruby_balance":"12","server_now_ms":1792681200000.0}"#),
        ("claim-server", #"{"week_start":"2026-10-26","next_week_start":"2026-11-02","worked_seconds":150000,"tiers":[{"hours":20,"ruby":20,"claimed":false,"achieved":true,"claimable":true},{"hours":40,"ruby":50,"claimed":false,"achieved":true,"claimable":true},{"hours":60,"ruby":200,"claimed":false,"achieved":false,"claimable":false}],"granted_now":[],"pending":[{"week_start":"2026-10-19","hours":60,"ruby":200},{"week_start":"2026-10-26","hours":20,"ruby":20},{"hours":40,"ruby":50},{"hours":0,"ruby":9},{"week_start":"2026-10-26","ruby":3}],"claimable_ruby":270}"#),
        ("claim-sum-only", #"{"worked_seconds":10,"tiers":[{"hours":20,"ruby":20}],"claimable_ruby":-5}"#),
        ("claim-sum-no-list", #"{"worked_seconds":10,"tiers":[{"hours":20,"ruby":20}],"claimable_ruby":70}"#),
        ("pending-empty", #"{"worked_seconds":10,"tiers":[{"hours":20,"ruby":20}],"pending":[]}"#),
        ("claimed-now", #"{"worked_seconds":72000,"tiers":[{"hours":20,"ruby":20,"claimed":true}],"claimed_now":[{"week_start":"2026-10-19","hours":20,"ruby":20},{"hours":40,"ruby":-9},{"hours":60}],"pending":[]}"#),
        ("complete", #"{"week_start":"2026-10-26","next_week_start":"2026-11-02","worked_seconds":216000,"tiers":[{"hours":60,"ruby":200,"claimed":false},{"hours":20,"ruby":20,"claimed":true},{"hours":40,"ruby":50,"claimed":true}]}"#),
        ("negative-worked", #"{"worked_seconds":-100,"tiers":[{"hours":20,"ruby":-20,"claimed":true}]}"#),
        ("lenient-days", #"{"week_start":"2026-10-x-26","next_week_start":"2026-13-01","worked_seconds":1,"tiers":[{"hours":20,"ruby":20}]}"#),
        ("bad-days", #"{"week_start":"2026/10/26","next_week_start":"2026-11","worked_seconds":1,"tiers":[{"hours":20,"ruby":20}]}"#),
        ("tiers-not-array", #"{"worked_seconds":1,"tiers":{"hours":20}}"#),
        ("not-object", #"[1]"#),
    ]

    @Test("weekly/status — 주간 보상 디코드 · 게이지 · 받기 · 주 끝 · 새 지급")
    func weeklyStatus() throws {
        let decoder = Self.decoder()
        var cases: [GoldenJSON] = []
        var decoded: [String: WeeklyWorkStatus] = [:]
        let inputs = Self.weeklyFixtures.map { ("fixture-" + $0, Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/" + $0)) } + Self.weeklyVariants
        for (id, text) in inputs {
            do {
                let status = try decoder.decode(WeeklyWorkStatus.self, from: Data(text.utf8))
                decoded[id] = status
                cases.append(["id": .string(id), "json": .string(text), "status": Self.weeklyJSON(status)])
            } catch {
                cases.append(["id": .string(id), "json": .string(text), "throws": true])
            }
        }
        // 게이지 표(누적초 × 단계 표).
        let tables: [[WeeklyWorkStatus.Tier]] = [
            [.init(hours: 20, ruby: 20, claimed: false), .init(hours: 40, ruby: 50, claimed: false), .init(hours: 60, ruby: 200, claimed: false)],
            [.init(hours: 40, ruby: 50, claimed: true), .init(hours: 20, ruby: 20, claimed: true), .init(hours: 60, ruby: -1, claimed: true), .init(hours: 20, ruby: 1, claimed: false)],
            [.init(hours: 0, ruby: 5, claimed: true), .init(hours: -3, ruby: 5, claimed: true)],
            [],
        ]
        var gauges: [GoldenJSON] = []
        for (index, table) in tables.enumerated() {
            for worked in [-5, 0, 1, 71_999, 72_000, 72_001, 100_000, 143_999, 144_000, 215_999, 216_000, 999_999] {
                gauges.append(["table": .int(index), "workedSeconds": .int(worked),
                               "gauge": Self.gaugeJSON(WeeklyWorkGauge.make(workedSeconds: worked, tiers: table), tiers: table)])
            }
        }
        cases.append(["id": "gauge-table", "tables": .array(tables.map { .array($0.map(Self.tierJSON)) }), "rows": .array(gauges)])
        // 주 경계 건너뛰기(weekEnded) — fixture 첫 응답 기준.
        if let status = decoded["fixture-_me/rpc.weekly_work_status.json"], let end = status.nextWeekStartDate {
            let points: [Date] = [end.addingTimeInterval(-60), end.addingTimeInterval(-1), end, end.addingTimeInterval(1), end.addingTimeInterval(60)]
            var rows: [GoldenJSON] = []
            for last in points {
                for now in points {
                    rows.append(["lastBits": .bits(last.timeIntervalSince1970), "nowBits": .bits(now.timeIntervalSince1970),
                                 "weekEnded": .bool(status.weekEnded(after: last, by: now))])
                }
            }
            cases.append(["id": "week-ended", "status": "fixture-_me/rpc.weekly_work_status.json", "rows": .array(rows)])
        }
        // 새로 들어온 지급(지난 조회 → 이번 조회).
        let pairs: [(String, String, String)] = [
            ("cron-flip", #"{"week_start":"2026-10-26","worked_seconds":72100,"tiers":[{"hours":20,"ruby":20,"claimed":false},{"hours":40,"ruby":50,"claimed":false}]}"#,
             #"{"week_start":"2026-10-26","worked_seconds":72200,"tiers":[{"hours":20,"ruby":20,"claimed":true},{"hours":40,"ruby":50,"claimed":false}],"granted_now":[{"hours":20,"ruby":20,"week_start":"2026-10-26"},{"hours":60,"ruby":200,"week_start":"2026-10-19"},{"hours":60,"ruby":200,"week_start":"2026-10-19"},{"hours":10,"ruby":0}]}"#),
            ("week-changed", #"{"week_start":"2026-10-19","tiers":[{"hours":20,"ruby":20,"claimed":false}]}"#,
             #"{"week_start":"2026-10-26","tiers":[{"hours":20,"ruby":20,"claimed":true}]}"#),
            ("claim-server", #"{"week_start":"2026-10-26","tiers":[{"hours":20,"ruby":20,"claimed":false}],"pending":[]}"#,
             #"{"week_start":"2026-10-26","tiers":[{"hours":20,"ruby":20,"claimed":true}],"pending":[]}"#),
            ("no-previous-week", #"{"tiers":[{"hours":20,"ruby":20,"claimed":false}]}"#, #"{"tiers":[{"hours":20,"ruby":20,"claimed":true}]}"#),
        ]
        for (name, previousText, currentText) in pairs {
            let previous = try decoder.decode(WeeklyWorkStatus.self, from: Data(previousText.utf8))
            let current = try decoder.decode(WeeklyWorkStatus.self, from: Data(currentText.utf8))
            cases.append(["id": .string("newly-\(name)"), "previousJSON": .string(previousText), "currentJSON": .string(currentText),
                          "sincePrevious": .array(current.newlyGranted(since: previous).map(Self.grantJSON)),
                          "sinceNil": .array(current.newlyGranted(since: nil).map(Self.grantJSON))])
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        cases.append(["id": "requests",
                      "all": .string(String(data: try encoder.encode(WeeklyWorkClaimRequest(weekStart: nil, hours: nil)), encoding: .utf8)!),
                      "one": .string(String(data: try encoder.encode(WeeklyWorkClaimRequest(weekStart: "2026-10-19", hours: 40)), encoding: .utf8)!)])
        goldenEmit(GoldenFile(
            golden: "weekly/status",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/WeeklyWorkReward.swift"],
            platformSensitive: true,
            spec: [
                "decode": "관대한 디코드 — 최상위가 객체가 아닐 때만 throw. 숫자 칸은 정수 또는 소수(0 쪽 버림, |v| < 9e15) — 글자 숫자는 받지 않는다(미션과 다르다). 깨진 단계 · 지급 행만 버린다. 단계는 시간 오름차순(같은 시간은 앞의 것)",
                "claim": "v0.3.58 — pending 이나 claimable_ruby 가 있으면 받기 서버. pendingRuby = claimable_ruby(음수 → 0) 또는 pending 합, pendingCount = pending 수(없고 합만 양수면 1)",
                "gauge": "지금 퀘스트 = 누적초가 아직 못 넘은 첫 단계(시간 > 0 만, 오름차순·중복 제거). fill = 누적 ÷ 퀘스트 초(0…1). 마지막을 넘으면 완료. claimedTotal = 받은 단계 루비 합(음수 0)",
                "weekEnd": "nextWeekStart → KST 0시(lenient 달력 — 숫자 아닌 조각은 버리고 셋이면 날짜). hasEnded = now ≥ 끝, weekEnded(last, now) = last < 끝 ≤ now",
                "newlyGranted": "granted_now(이번 주 행은 weekStart 를 비운다) ∪ (받기 서버가 아니고 같은 주면) claimed 거짓→참 단계. (주, 시간)당 한 번, 루비 > 0 만",
                "platformSensitive": "true — KST 달력(tzdata)이 날짜를 정한다",
            ],
            cases: cases
        ))
    }

    // MARK: dates/parse

    static let timestamps: [String] = [
        "2026-09-17T01:00:00+00:00", "2026-09-17T01:00:00Z", "2026-09-17T10:00:00+09:00", "2026-09-17T01:00:00.123Z",
        "2026-09-17T01:00:00.123456+00:00", "2026-09-17T01:00:00.999999Z", "2026-09-17T01:00:00.5", "2026-09-17T01:00:00.123456",
        "2026-09-17T01:00:00", "2026-09-17 01:00:00+00:00", "2026-09-17t01:00:00z", "2026-09-17T01:00:00+0000",
        "2026-09-17T01:00:00+09", "2026-09-17T24:00:00Z", "2026-02-29T01:00:00Z", "2024-02-29T23:59:59Z", "2026-13-01T00:00:00Z",
        "2026-09-31T00:00:00Z", "2026-09-17T01:60:00Z", "2026-09-17T01:00:60Z", "1970-01-01T00:00:00Z", "1969-12-31T23:59:59.9Z",
        "2026-09-17", "", "garbage", "2026-09-17T01:00:00.Z", "2026-09-17T01:00:00.12x3Z", "2026-09-17T01:00:00.1-05:00",
        "2026-09-17T01:00:00.000+05:30", "0001-01-01T00:00:00Z", "9999-12-31T23:59:59Z", "2026-09-17T01:00:00.١٢Z",
        "2026-09-17T01:00:00.12١Z", "+2026-09-17T01:00:00Z", "2026-9-17T01:00:00Z", "2026-09-17T1:00:00Z",
        // ── ASCII 밖 숫자(Nd) — ICU 파서는 모든 문자의 10진 숫자를 받는다(섞여도). No(²)·Nl(Ⅷ 〇)·Lo(二)는 아니다. 시간대 숫자는 ASCII 만.
        //    ART(ICU) 의 정규식 `\d` 와 JDK 의 `\d` 가 달라 Kotlin 은 정규식 없이 번들 표로 잰다(2026-10-28 맥 실측).
        "٢٠٢٦-09-17T01:00:00Z", "2026-٠٩-17T01:00:00Z", "2026-09-١٧T01:00:00Z", "2026-09-17T٠١:00:00Z",
        "2026-09-17T01:٠٠:00Z", "2026-09-17T01:00:٠٠Z", "2026-09-17T01:00:00+٠٩:00", "2026-09-17T01:00:00+09:٠٠",
        "۲۰۲۶-09-17T01:00:00Z", "２０２６-09-17T01:00:00Z", "2026-09-17T01:00:0０Z", "2026-09-17T01:00:00+0९:00",
        "2026-09-17T01:00:00+০9", "٢٠٢٦-09-17T01:00:00.123Z", "2026-09-١٧T01:00:00.5Z", "2026-09-17T01:00:00.123+٠٩:٠٠",
        "2٠26-09-17T01:00:00Z", "2026-٠٠٩-17T01:00:00Z", "𝟐𝟎𝟐𝟔-09-17T01:00:00Z", "2026-09-17T0𝟏:00:00Z",
        "2026-09-17T01:00:𞥐𞥕Z", "2026-09-17T01:00:𐒠𐒥Z", "2026-09-17T01:00:๐๕Z", "2026-09-17T01:00:߀߅Z",
        "⁲⁰⁲⁶-09-17T01:00:00Z", "2026-09-17T01:00:0²Z", "2026-09-17T01:00:0①Z", "2026-09-17T01:00:0ⅧZ",
        "2026-09-17T01:00:0〇Z", "2026-09-17T01:00:0二Z", "2026-09-17T01:00:00٠Z", "2026-09-17T01:00:0٠٠Z",
        // ── 숫자 칸 자릿수 · 부호 · 범위(욕심껏 읽는다 · ASCII `-` 하나 · 달 1…12 · 날 1…31 · 시 0…24 · 분/초 0…59 · 해는 검사 없음)
        "202-09-17T01:00:00Z", "20266-09-17T01:00:00Z", "2026-009-17T01:00:00Z", "2026-09-017T01:00:00Z",
        "2026-09-17T001:00:00Z", "2026-09-17T01:000:00Z", "2026-09-17T01:00:000Z", "2026-09-17T01:0:00Z",
        "2026-09-17T01:00:0Z", "0000-01-01T00:00:00Z", "00000-01-01T00:00:00Z", "02026-09-17T01:00:00Z",
        "26-09-17T01:00:00Z", "6-09-17T01:00:00Z", "-2026-09-17T01:00:00Z", "-0001-01-01T00:00:00Z",
        "-1-01-01T00:00:00Z", "1-01-01T00:00:00Z", "2026--09-17T01:00:00Z", "2026-+09-17T01:00:00Z",
        "2026-09-17T+01:00:00Z", "2026-09-17T01:-0:00Z", "2026-09-17T01:-1:00Z", "2026-09-17T-0:00:00Z",
        "2026-09-17T01:00:-0Z", "2026-0-17T01:00:00Z", "2026-00-17T01:00:00Z", "2026-09-00T01:00:00Z",
        "2026-09-32T01:00:00Z", "2026-02-31T01:00:00Z", "2026-09-17T24:30:00Z", "2026-09-17T25:00:00Z",
        "2026-12-31T24:00:00Z", "2026-09-17T24:00:01Z", "99999-12-31T23:59:59Z", "999999-12-31T23:59:59Z",
        "2026-1-1T0:0:0Z", "2026-09-17T01:00", "2026-09-17T01:00Z", "2026-09-17TZ",
        "T01:00:00Z", "2026-09-17T01:00:00x", "2026-09-17T01:00:00-", "2026-09-17T01:00:00+",
        // ── 시간대 ISO(ICU parseAsciiOffsetFields · 기본형과 긴 쪽 · 23 넘는 시는 한 자리 · 한 자리 시 뒤 `:` 건너뜀) · 뒤 글자는 안 본다
        "2026-09-17T01:00:00Zx", "2026-09-17T01:00:00Z0", "2026-09-17T01:00:00Z+09:00", "2026-09-17T01:00:00ZZ",
        "2026-09-17T01:00:00+09:00x", "2026-09-17T01:00:00+0900", "2026-09-17T01:00:00+9", "2026-09-17T01:00:00+0",
        "2026-09-17T01:00:00+1", "2026-09-17T01:00:00-0", "2026-09-17T01:00:00+2", "2026-09-17T01:00:00+23",
        "2026-09-17T01:00:00+24", "2026-09-17T01:00:00+9:00", "2026-09-17T01:00:00+09:0", "2026-09-17T01:00:00+09:000",
        "2026-09-17T01:00:00+090", "2026-09-17T01:00:00+093", "2026-09-17T01:00:00+0930", "2026-09-17T01:00:00+09:30",
        "2026-09-17T01:00:00+130", "2026-09-17T01:00:00+1300", "2026-09-17T01:00:00+1:30", "2026-09-17T01:00:00+1:3",
        "2026-09-17T01:00:00+0:30", "2026-09-17T01:00:00+24:00", "2026-09-17T01:00:00+25:00", "2026-09-17T01:00:00+99:99",
        "2026-09-17T01:00:00+12:60", "2026-09-17T01:00:00+00:60", "2026-09-17T01:00:00+00:59", "2026-09-17T01:00:00+00:5",
        "2026-09-17T01:00:00+23:59", "2026-09-17T01:00:00-23:59", "2026-09-17T01:00:00-24:00", "2026-09-17T01:00:00+18:00",
        "2026-09-17T01:00:00+19:00", "2026-09-17T01:00:00+14:00x", "2026-09-17T01:00:00+09:00:30", "2026-09-17T01:00:00+090030",
        "2026-09-17T01:00:00+09:00:3", "2026-09-17T01:00:00+09:00:60", "2026-09-17T01:00:00+09:0030", "2026-09-17T01:00:00+0900:30",
        "2026-09-17T01:00:00+09:", "2026-09-17T01:00:00+09.00", "2026-09-17T01:00:00+09_00", "2026-09-17T01:00:00+-09:00",
        "2026-09-17T01:00:00++09:00", "2026-09-17T01:00:00−09:00", "2026-09-17T01:00:00＋09:00", "2026-09-17T01:00:00+０９:00",
        "2026-09-17T01:00:00+09:5٥", "2026-09-17T01:00:00+09:00Z", "2026-09-17T01:00:00-05", "2026-09-17T01:00:00-0500",
        "2026-09-17T01:00:00-05:00", "2026-09-17T01:00:00+00", "2026-09-17T01:00:00+0000x", "2026-09-17T01:00:00+09:00\u{0000}",
        // ── 지역화 GMT(GMT{0} · +H:mm(:ss) · 기본 GMT/UTC/UT + 구분자/붙은 꼴 · 지역화 숫자 = Nd) · 이름(KST)은 안 받는다
        "2026-09-17T01:00:00GMT", "2026-09-17T01:00:00gmt", "2026-09-17T01:00:00Gmt", "2026-09-17T01:00:00UTC",
        "2026-09-17T01:00:00utc", "2026-09-17T01:00:00UT", "2026-09-17T01:00:00ut", "2026-09-17T01:00:00uT",
        "2026-09-17T01:00:00UTx", "2026-09-17T01:00:00UTCx", "2026-09-17T01:00:00UTCC", "2026-09-17T01:00:00UTCGMT",
        "2026-09-17T01:00:00GMTx", "2026-09-17T01:00:00GMTZ", "2026-09-17T01:00:00G", "2026-09-17T01:00:00U",
        "2026-09-17T01:00:00GM", "2026-09-17T01:00:00U T", "2026-09-17T01:00:00KST", "2026-09-17T01:00:00PST",
        "2026-09-17T01:00:00Asia/Seoul", "2026-09-17T01:00:00GMT+09:00", "2026-09-17T01:00:00GMT+9", "2026-09-17T01:00:00GMT+0900",
        "2026-09-17T01:00:00GMT+0930", "2026-09-17T01:00:00GMT+930", "2026-09-17T01:00:00GMT+9:30", "2026-09-17T01:00:00GMT+9:3",
        "2026-09-17T01:00:00GMT+9:300", "2026-09-17T01:00:00GMT+09:", "2026-09-17T01:00:00GMT+09:0", "2026-09-17T01:00:00GMT+09:30:15",
        "2026-09-17T01:00:00GMT+09:30:1", "2026-09-17T01:00:00GMT+09:00:6", "2026-09-17T01:00:00GMT+09:00:60", "2026-09-17T01:00:00GMT+23:59:59",
        "2026-09-17T01:00:00GMT+1:30", "2026-09-17T01:00:00GMT+12:60", "2026-09-17T01:00:00GMT+24", "2026-09-17T01:00:00GMT+24:00",
        "2026-09-17T01:00:00GMT+99", "2026-09-17T01:00:00GMT+٠٩:00", "2026-09-17T01:00:00GMT+09:٠٠", "2026-09-17T01:00:00GMT+٩",
        "2026-09-17T01:00:00GMT-٩:٣٠", "2026-09-17T01:00:00GMT+𝟗", "2026-09-17T01:00:00GMT+٠", "2026-09-17T01:00:00GMT+²",
        "2026-09-17T01:00:00GMT+", "2026-09-17T01:00:00GMT-", "2026-09-17T01:00:00GMT ", "2026-09-17T01:00:00GMT9",
        "2026-09-17T01:00:00GMT 9", "2026-09-17T01:00:00GMT +9", "2026-09-17T01:00:00GMT+ 9", "2026-09-17T01:00:00GMT-9",
        "2026-09-17T01:00:00GMT-09:30", "2026-09-17T01:00:00GMT+00:00", "2026-09-17T01:00:00GMT+0", "2026-09-17T01:00:00GMT+00",
        "2026-09-17T01:00:00GMT+000", "2026-09-17T01:00:00GMT+09:00x", "2026-09-17T01:00:00UTC+09:00", "2026-09-17T01:00:00UTC-05:00",
        "2026-09-17T01:00:00UTC+0930", "2026-09-17T01:00:00UTC+٠٩٣٠", "2026-09-17T01:00:00UTC+09:30x", "2026-09-17T01:00:00UTC+",
        "2026-09-17T01:00:00UTC+x", "2026-09-17T01:00:00UTC−09:00", "2026-09-17T01:00:00UT+9", "2026-09-17T01:00:00GMT+09:00:30",
        "2026-09-17T01:00:00gmt+0930", "2026-09-17T01:00:00Utc+0930",
        // ── 소수초(Nd · `-` · ms 맞춤 int32) · 도려내기 길(Character.isNumber — 글자 단위 · 첫 스칼라)
        "2026-09-17T01:00:00.١Z", "2026-09-17T01:00:00.1١Z", "2026-09-17T01:00:00.５Z", "2026-09-17T01:00:00.5𝟏Z",
        "2026-09-17T01:00:00.𝟏Z", "2026-09-17T01:00:00.५Z", "2026-09-17T01:00:00.5٠Z", "2026-09-17T01:00:00.-5Z",
        "2026-09-17T01:00:00.-0Z", "2026-09-17T01:00:00.-500Z", "2026-09-17T01:00:00.-1Z", "2026-09-17T01:00:00.-Z",
        "2026-09-17T01:00:00.5+09:00x", "2026-09-17T01:00:00.5Zx", "2026-09-17T01:00:00.5GMT", "2026-09-17T01:00:00.5+9",
        "2026-09-17T01:00:00.5+1:30", "2026-09-17T01:00:00.123456789+05:30x", "2026-09-17T01:00:00.١٢٣+09:00", "2026-09-17T01:00:00.123+0९:00",
        "2026-09-17T01:00:00.123+09:٠٠", "2026-09-17T01:00:00.123Z٠", "2026-09-17T01:00:00..5Z", "2026-09-17T01:00:00.5.5Z",
        "2026-09-17T01:00:00,5Z", "2026-09-17T01:00:00.Zx", "2026-09-17T01:00:00.²Z", "2026-09-17T01:00:00.〇Z",
        "2026-09-17T01:00:00.5²Z", "2026-09-17T01:00:00.²𝟏Z", "2026-09-17T01:00:00.Ⅷ5Z", "2026-09-17T01:00:00.²",
        "2026-09-17T01:00:00.5", "2026-09-17T01:00:00.", "2026-09-17T01:00:00.²+09:00", "2026-09-17T01:00:00.3000000000Z",
        "2026-09-17T01:00:00.9999999999Z", "2026-09-17T01:00:00.123456789012Z", "2026-09-17T01:00:00.1234567890Z", "2026-09-17T01:00:00.999999999Z",
        "2026-09-17T01:00:00.0000000001Z", "2026-09-17T01:00:00.5\u{301}Z", "2026-09-17T01:00:00.\u{301}5Z", "2026-09-17T01:00:00.5\u{301}",
    ]

    static let dayStrings: [String] = [
        "2026-10-19", "2026-10-26", "2026-01-01", "2026-13-01", "2026-02-30", "2026-00-10", "2026-10-00", "2026-10-x-19",
        "2026--10-19", "-2026-10-19", "2026-10", "2026-10-19-01", "", "abc", " 2026-10-19", "2026-10-19 ", "+2026-10-19", "2026-010-019",
        "0-1-1", "2026-1-5", "99999-01-01", "2026-12-32",
        // ASCII 밖 Nd 숫자 조각(Swift `Int(String)` 은 ASCII 만 — 조각을 버려 셋이 안 되면 nil). Kotlin `toIntOrNull` 은 유니코드 숫자를 받는다.
        "٢٠٢٦-10-19", "2026-١٠-19", "2026-10-١٩", "２０２６-10-19", "2026-10-1٩", "۲۰۲۶-۱۰-۱۹",
    ]

    @Test("dates/parse — 서버 시각 파서 · KST 날짜 키 · 주/일 시작 · 요일 · 시 시작")
    func datesParse() {
        var cases: [GoldenJSON] = []
        cases.append(["id": "timestamps", "rows": .array(Self.timestamps.map { text in
            ["text": .string(text), "parsed": Self.d(WorkInsightsDate.parse(text))]
        })])
        cases.append(["id": "day-strings", "rows": .array(Self.dayStrings.map { text in
            ["text": .string(text), "kstMidnight": Self.d(WeeklyWorkCalendar.kstMidnight(text)),
             "tokenGridDate": Self.d(TokenDailyGrid.date(fromDay: text)), "leagueDate": Self.d(TeamLeagueWeekNavigator.date(forKey: text))]
        })])
        var instants: [Date] = Self.nows
        // 1950~2040 사이 표본(서머타임 해 1987·1988 포함) — 주/일 시작이 tzdata 와 같은지.
        for (y, mo, day, h) in [(1987, 5, 10, 3), (1987, 10, 11, 2), (1988, 5, 8, 1), (1988, 10, 9, 2), (1960, 6, 1, 12),
                                (2000, 1, 1, 0), (2038, 1, 19, 12), (2040, 12, 31, 23)] {
            instants.append(Self.kstDate(y, mo, day, h))
        }
        instants.append(Date(timeIntervalSince1970: -1.5))
        instants.append(Date(timeIntervalSince1970: 0))
        cases.append(["id": "instants", "rows": .array(instants.map { now in
            ["now": Self.d(now), "weekStart": Self.d(TeamWeeklyGoal.koreanWeekStart(for: now)),
             "dayStart": Self.d(TeamWeeklyGoal.koreanDayStart(for: now)),
             "weekdayIndex": .int(WorkInsightsCalendar.weekdayIndex(for: now)), "hourStart": Self.d(WorkInsightsCalendar.hourStart(for: now)),
             "milestoneDayKey": .string(MilestoneTracker.dayKey(now)), "tokenDayString": .string(TokenDailyGrid.dayString(now)),
             "monthKey": .string(TokenUsageMonthKey.current(now)), "dayKey": .string(TokenUsageDayKey.current(now)),
             "retroWeekKey": .string(RetroWeekKey.current(now)), "leagueCurrentKey": .string(TeamLeagueWeekNavigator.currentKey(now)),
             "lastWeek": WorkInsightsWeekWindow.lastWeek(now: now).map { ["start": Self.d($0.start), "end": Self.d($0.end), "previousStart": Self.d($0.previousStart)] } ?? .null,
             "todoDayKey": .string(TodoRules.dayKey(now))]
        })])
        goldenEmit(GoldenFile(
            golden: "dates/parse",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckWorkInsights.swift", "Sources/CheckCore/WeeklyWorkReward.swift",
                           "Sources/CheckCore/MilestoneTracker.swift", "Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/CheckTodoModel.swift"],
            platformSensitive: true,
            spec: [
                "timestamps": "WorkInsightsDate.parse — ISO8601(인터넷 날짜·시간) → 소수초 판 → 소수부를 도려내고(숫자가 끝나는 자리까지, 시간대가 없으면 Z) 다시. 결과는 초 내림(1970 기준 초 Double 비트). 실패면 null",
                "days": "'YYYY-MM-DD' → KST 0시: '-' 로 나눠 정수가 아닌 조각은 버리고, 셋이면 lenient 그레고리력(달 13 → 다음 해, 날 0 → 전달 말일)",
                "instants": "KST(Asia/Seoul tzdata — 1987·1988 서머타임 포함) 주 시작(월 0시) · 일 시작 · 요일(0=월) · 시 시작 · 날짜 키들 · 지난주 창",
                "platformSensitive": "true — tzdata(Android API 마다 판이 다르다)",
            ],
            cases: cases
        ))
    }

    // MARK: dates/durations

    @Test("dates/durations — 시:분 표기 · 메뉴바 제목 · 나이 문구")
    func datesDurations() {
        let seconds = [-5, 0, 1, 59, 60, 61, 299, 300, 3_599, 3_600, 3_661, 4_980, 35_999, 36_000, 86_399, 86_400, 359_999, 360_000, 3_600_000]
        var cases: [GoldenJSON] = [["id": "durations", "rows": .array(seconds.map { value in
            ["seconds": .int(value), "titleDuration": .string(MenuBarStatusFormatter.titleDuration(value)),
             "duration": .string(MenuBarStatusFormatter.duration(value)), "hoursMinutes": .string(MenuBarStatusFormatter.hoursMinutes(value)),
             "workGridTooltip": .string(WorkDailyGrid.tooltipValueText(value))]
        })]]
        var titles: [GoldenJSON] = []
        for status in [WorkStatus.working, .offWork] {
            for pending in [false, true] {
                for elapsed in [0, 300, 4_980] {
                    let snapshot = WorkStatusSnapshot(status: status, elapsedSeconds: elapsed, pendingSync: pending)
                    titles.append(["status": .string(status == .working ? "working" : "offWork"), "pendingSync": .bool(pending), "elapsed": .int(elapsed),
                                   "title": .string(MenuBarStatusFormatter.title(for: snapshot)), "symbol": .string(MenuBarStatusFormatter.symbolName(for: snapshot)),
                                   "localizedStatus": .string(snapshot.localizedStatus), "statusText": .string(status.localizedStatus),
                                   "isWorking": .bool(snapshot.isWorking)])
                }
            }
        }
        cases.append(["id": "titles", "maxLabelWidthBits": .bits(Double(MenuBarStatusFormatter.maxLabelWidth)), "rows": .array(titles)])
        let reference = Date(timeIntervalSince1970: 1_789_621_500)
        let ages: [Double] = [-30, 0, 0.5, 59, 59.9, 60, 119, 3_599, 3_600, 7_199, 86_399, 86_400, 172_800, 864_000]
        cases.append(["id": "ages", "referenceBits": .bits(reference.timeIntervalSince1970), "rows": .array(ages.map { age in
            ["ageBits": .bits(age), "caption": .string(AILimitFreshnessRule.captionText(freshness: .recent, reference: reference,
                                                                                         now: reference.addingTimeInterval(age)))]
        })])
        goldenEmit(GoldenFile(
            golden: "dates/durations",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/MenuBarStatusFormatter.swift", "Sources/CheckCore/SupabaseWorkModels.swift",
                           "Sources/CheckCore/CheckWorkInsights.swift", "Sources/CheckCore/AILimitFreshnessRule.swift"],
            platformSensitive: false,
            spec: [
                "durations": "titleDuration = 언제나 HH:MM(초 내림) · duration = 1시간 미만 MM:SS 아니면 HH:MM · hoursMinutes = 'H시간 MM분' · 음수는 0",
                "titles": "메뉴바 제목 — 동기화 대기가 먼저('대기'), 근무 중 HH:MM, 끝 '오프'. Windows 트레이 툴팁도 같은 글자(G §8-13)",
                "ages": "나이 문구(FeedbackText.ageText): 60초 미만 '방금' · 분 · 시간 · 일(정수 초 내림, 음수 0)",
            ],
            cases: cases
        ))
    }

    // MARK: insights/computation

    static func sessionRowsJSON(_ rows: [(String, String?)]) -> String {
        "[" + rows.enumerated().map { index, row in
            let ended = row.1.map { "\"\($0)\"" } ?? "null"
            return #"{"id":"s\#(index)","user_id":"u1","started_at":"\#(row.0)","ended_at":\#(ended),"duration_seconds":null}"#
        }.joined(separator: ",") + "]"
    }

    static let sessionSets: [(String, [(String, String?)])] = [
        ("cross-boundaries", [
            ("2026-10-18T14:30:00Z", "2026-10-18T16:10:00Z"),          // 일 23:30 KST → 월 01:10 KST(주 경계)
            ("2026-10-20T00:15:30.5+00:00", "2026-10-20T03:45:10.999999+00:00"),
            ("2026-10-21T23:00:00+09:00", "2026-10-22T09:00:00+09:00"),
            ("2026-10-24T05:00:00Z", "2026-10-24T05:00:00Z"),          // 길이 0 → 버림
            ("2026-10-24T06:00:00Z", "2026-10-24T05:00:00Z"),          // 거꾸로 → 버림
            ("2026-10-25T13:00:00Z", nil),                              // 진행 중(서버는 안 준다)
            ("2026-10-12T01:00:00Z", "2026-10-12T05:00:00Z"),          // 그 전주
            ("2026-10-05T01:00:00Z", "2026-10-05T05:00:00Z"),          // 전전주 → 회고 밖
            ("garbage", "2026-10-20T01:00:00Z"),
            ("2026-10-25T14:59:59Z", "2026-10-25T15:00:01Z"),          // 일→월 2초
        ]),
        ("one-week-heavy", (0..<20).map { index in
            let day = 19 + index % 7
            let hour = (index * 5) % 24
            return (String(format: "2026-10-%02dT%02d:07:00Z", day, hour), String(format: "2026-10-%02dT%02d:52:31Z", day, (hour + 3) % 24 < hour ? 23 : (hour + 3) % 24))
        }),
        ("empty", []),
    ]

    static func heatmapJSON(_ heatmap: WorkRhythmHeatmap) -> GoldenJSON {
        ["buckets": .array(heatmap.buckets.map { .array($0.map(Self.n)) }), "totalSeconds": n(heatmap.totalSeconds),
         "maxBucketSeconds": n(heatmap.maxBucketSeconds),
         "peakSlot": heatmap.peakSlot.map { ["day": .int($0.day), "hour": .int($0.hour)] } ?? .null]
    }

    static func retroJSON(_ retro: WeeklyRetro?) -> GoldenJSON {
        guard let retro else { return .null }
        return ["weekStart": d(retro.weekStart), "totalSeconds": n(retro.totalSeconds), "goalSeconds": n(retro.goalSeconds),
                "previousWeekSeconds": n(retro.previousWeekSeconds), "sessionCount": n(retro.sessionCount),
                "busiestDayIndex": n(retro.busiestDayIndex), "busiestDaySeconds": n(retro.busiestDaySeconds),
                "metGoal": .bool(retro.metGoal), "deltaSeconds": n(retro.deltaSeconds), "withGoal0MetGoal": .bool(retro.withGoal(0).metGoal)]
    }

    static func gridJSON(_ grid: WorkDailyGrid) -> GoldenJSON {
        ["weekStart": d(grid.weeks == 0 ? nil : grid.weekStart), "weeks": .int(grid.weeks), "days": .int(grid.days),
         "seconds": .array(grid.seconds.map { .array($0.map(Self.n)) }), "totalSeconds": n(grid.totalSeconds),
         "futureFlags": .string((0..<max(grid.weeks, 1)).map { week in (0..<7).map { grid.isFuture(week: week, weekday: $0) ? "1" : "0" }.joined() }.joined(separator: ",")),
         "dateOfLastCell": d(grid.weeks == 0 ? nil : grid.date(week: grid.weeks - 1, weekday: 6))]
    }

    @Test("insights/computation — E11: 히트맵 · 회고 · 일별 잔디(세션 행 + now → 정수 초)")
    func insightsComputation() throws {
        let decoder = Self.decoder()
        var cases: [GoldenJSON] = []
        var sets = Self.sessionSets.map { ($0.0, Self.sessionRowsJSON($0.1)) }
        sets.append(("fixture-limit5000", Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/rest.work_sessions.get@limit=5000.json")))
        sets.append(("fixture-me-", Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/_me-/rest.work_sessions.get.json")))
        let nows: [Date] = [Self.kstDate(2026, 10, 26, 0, 0, 0), Self.kstDate(2026, 10, 26, 0, 0, 1), Self.kstDate(2026, 10, 28, 10, 30, 0),
                            Self.kstDate(2026, 10, 25, 23, 59, 59), Date(timeIntervalSince1970: 1_789_621_500.75),
                            Self.kstDate(2026, 9, 21, 9, 0, 0)]
        for (name, json) in sets {
            let rows = try decoder.decode([WorkSessionRow].self, from: Data(json.utf8))
            let parsed = WorkInsightsDate.parseSessions(rows)
            var perNow: [GoldenJSON] = []
            for now in nows {
                for ongoing in [nil, now.addingTimeInterval(-5_400.5), now.addingTimeInterval(60)] as [Date?] {
                    let computation = WorkInsightsComputation.build(rows: rows, now: now, goalSeconds: 40 * 3_600, ongoingStart: ongoing)
                    perNow.append(["now": Self.d(now), "ongoingStart": Self.d(ongoing),
                                   "heatmap": Self.heatmapJSON(computation.heatmap), "retro": Self.retroJSON(computation.retro),
                                   "grid": Self.gridJSON(computation.dailyGrid)])
                }
                let narrow = WorkDailyGrid.build(parsed: parsed, now: now, ongoingStart: nil, weeks: 2)
                perNow.append(["now": Self.d(now), "weeks2": Self.gridJSON(narrow)])
            }
            cases.append(["id": .string("sessions-\(name)"), "json": .string(json),
                          "parsed": .array(parsed.map { [Self.d($0.start), Self.d($0.end)] }), "results": .array(perNow)])
        }
        goldenEmit(GoldenFile(
            golden: "insights/computation",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckWorkInsights.swift", "Sources/CheckCore/SupabaseWorkModels.swift",
                           "Sources/CheckCore/MenuBarStatusFormatter.swift"],
            platformSensitive: true,
            spec: [
                "sessions": "완료 행만(시작 < 끝, 둘 다 파싱) · 진행 중 세션은 ongoingStart < now 일 때 now 까지",
                "heatmap": "지난주 창[지난 월 0시, 이번 월 0시)만 · KST 정시 경계로 쪼개 (요일 0=월, 시) 칸에 Int(초 차) — 칸 최대 3600",
                "retro": "지난주 하루 경계로 쪼갠 합 · 세션 수(지난주에 걸친 것) · 그 전주 합(같은 클리핑) · 최다 요일(동률은 앞 요일) · 합이 0 이면 null",
                "grid": "13주(또는 weeks) 창 · 하루 경계 클리핑 · 미래 칸 = 0 · 진행 세션은 잔디가 스스로 얹는다(이중 계상 없음)",
                "platformSensitive": "true — KST 달력(tzdata)",
            ],
            cases: cases
        ))
    }

    // MARK: insights/token

    static let tokenRowsJSON = #"[{"day":"2026-10-20","device_id":"a","claude_total":100,"codex_total":50,"codex_utc_total":40,"codex_account":300},{"day":"2026-10-20","device_id":"b","claude_total":-5,"codex_total":30,"codex_account":250},{"day":"2026-10-21","device_id":"a","claude_total":10,"codex_total":500,"codex_utc_total":null,"codex_account":20},{"day":"2026-10-22","device_id":"a","claude_total":0,"codex_total":70,"codex_account":null},{"day":"2026-10-23","device_id":"b","claude_total":7,"codex_total":0,"codex_account":null},{"day":"2026-09-30","device_id":"a","claude_total":1,"codex_total":0,"codex_account":999}]"#

    @Test("insights/token — 토큰 잔디 · 서버 일별 합치기 · Codex 유효 · 공유 비율 · 순위판 이동")
    func insightsToken() throws {
        let decoder = Self.decoder()
        var cases: [GoldenJSON] = []
        let rowSets: [(String, String)] = [("synthetic", Self.tokenRowsJSON),
                                           ("fixture", Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/rest.token_usage_device_daily.get.json"))]
        for (name, json) in rowSets {
            let rows = try decoder.decode([TokenUsageDailyRow].self, from: Data(json.utf8))
            var totals: [GoldenJSON] = []
            for ratio in [1.0, 0.5, 0.27, 0.0, 1.5] {
                let map = TokenDailyMerge.serverTotals(rows, accountShareRatio: ratio)
                totals.append(["ratioBits": .bits(ratio), "totals": .object(map.mapValues(Self.n))])
            }
            let months = ["2026-10", "2026-09", "2026-08"]
            cases.append(["id": .string("server-\(name)"), "json": .string(json), "totals": .array(totals),
                          "accountBucketSum": .object(Dictionary(uniqueKeysWithValues: months.map { ($0, Self.n(TokenDailyMerge.accountBucketSum(rows, month: $0))) }))])
        }
        let server: [String: Int] = ["2026-10-20": 100, "2026-10-21": 5, "2026-10-22": 0]
        let local: [String: Int] = ["2026-10-21": 50, "2026-10-22": 7, "2026-10-28": 9, "2026-10-29": -3]
        cases.append(["id": "merged", "server": .object(server.mapValues(Self.n)), "local": .object(local.mapValues(Self.n)),
                      "merged": .object(TokenDailyMerge.merged(server: server, local: local).mapValues(Self.n))])
        let daily: [String: Int] = ["2026-10-20": 1_000, "2026-10-26": 50_000_000, "2026-10-28": 7, "2026-10-29": 9, "2026-07-01": 3,
                                    "2026-07-27": 11, "bad": 5, "2026-10-x-27": 13, "2026-10-21": -4, "2026-08-03": 0]
        var grids: [GoldenJSON] = []
        for now in [Self.kstDate(2026, 10, 28, 10, 30), Self.kstDate(2026, 10, 26, 0, 0, 0), Self.kstDate(2026, 10, 25, 23, 59, 59)] {
            for weeks in [13, 1, 0] {
                let grid = TokenDailyGrid.build(daily: daily, now: now, weeks: weeks)
                let other = TokenDailyGrid.build(daily: ["2026-10-28": 100, "2026-10-29": 999, "2026-10-20": 1], now: now.addingTimeInterval(86_400), weeks: weeks)
                let same = TokenDailyGrid.build(daily: ["2026-10-28": 100, "2026-10-20": 2_000], now: now, weeks: weeks)
                grids.append(["now": Self.d(now), "weeks": .int(weeks),
                              "grid": ["weekStart": Self.d(grid.weeks == 0 ? nil : grid.weekStart), "weeks": .int(grid.weeks), "days": .int(grid.days),
                                       "tokens": .array(grid.tokens.map { .array($0.map(Self.n)) }), "totalTokens": Self.n(grid.totalTokens)],
                              "overlaySame": .array(grid.overlaying(same).tokens.map { .array($0.map(Self.n)) }),
                              "overlayOther": .array(grid.overlaying(other).tokens.map { .array($0.map(Self.n)) })])
            }
        }
        cases.append(["id": "token-grid", "daily": .object(daily.mapValues(Self.n)), "rows": .array(grids),
                      "tooltips": .array([0, -1, 1, 1_234_567].map { ["tokens": .int($0), "text": .string(TokenDailyGrid.tooltipValueText($0))] })])
        // Codex 유효 규칙.
        var monthRows: [GoldenJSON] = []
        let localDaily: [String: Int] = ["2026-10-01": 10, "2026-10-05": 40, "2026-10-06": 7, "2026-10-07": -3, "2026-09-30": 1_000]
        for accountMonth in [nil, 0, 500, -20] as [Int?] {
            for lastDay in [nil, "2026-10-05", "2026-10-07", "2026-09-29"] as [String?] {
                for bucket in [nil, 0, 30, 60] as [Int?] {
                    monthRows.append(["localMonth": .int(57), "accountMonth": Self.n(accountMonth), "accountLastDay": Self.s(lastDay),
                                      "accountBucketOnLastDay": Self.n(bucket),
                                      "effective": Self.n(CodexEffectiveRule.month(localMonth: 57, localDaily: localDaily, accountMonth: accountMonth,
                                                                                  accountLastDay: lastDay, accountBucketOnLastDay: bucket))])
                }
            }
        }
        var dayRows: [GoldenJSON] = []
        for day in ["2026-10-04", "2026-10-05", "2026-10-06"] {
            for localValue in [-1, 0, 25] {
                for bucket in [nil, 0, 10, 40] as [Int?] {
                    for lastDay in [nil, "2026-10-05"] as [String?] {
                        dayRows.append(["day": .string(day), "local": .int(localValue), "accountBucket": Self.n(bucket), "accountLastDay": Self.s(lastDay),
                                        "effective": Self.n(CodexEffectiveRule.day(day, local: localValue, accountBucket: bucket, accountLastDay: lastDay))])
                    }
                }
            }
        }
        let exceeds: [(Int, Int?)] = [(100, nil), (100, 0), (121, 100), (120, 100), (0, 1), (-5, 3), (1_000_000_001, 833_333_334)]
        cases.append(["id": "codex-effective", "localDaily": .object(localDaily.mapValues(Self.n)), "month": .array(monthRows), "day": .array(dayRows),
                      "overcountRatioBits": .bits(CodexEffectiveRule.overcountRatio),
                      "exceeds": .array(exceeds.map { ["local": Self.n($0.0), "account": Self.n($0.1), "exceeds": .bool(CodexEffectiveRule.localExceedsAccount(local: $0.0, account: $0.1))] })])
        // 공유 비율 · 축소 · 월초 유예.
        let shares: [(Int?, Int)] = [(nil, 100), (0, 100), (50, 100), (150, 100), (50, 0), (50, -3), (-10, 100), (1, 3), (2, 3)]
        let scaled: [(Int, Double)] = [(100, 1.0), (100, 1.5), (100, 0.5), (3, 0.5), (5, 0.5), (7, 0.5), (1_000_000_001, 0.27), (999, 0.0), (10, 0.25), (-10, 0.25)]
        let youngNows = [Self.kstDate(2026, 11, 1, 0, 0, 0), Self.kstDate(2026, 11, 3, 23, 59, 59), Self.kstDate(2026, 11, 4, 0, 0, 0), Self.kstDate(2026, 10, 31, 23, 59, 59)]
        cases.append(["id": "share-ratio",
                      "ratios": .array(shares.map { ["share": Self.n($0.0), "bucketSum": .int($0.1), "ratioBits": .bits(TokenRowDisplayRule.accountShareRatio(share: $0.0, bucketSum: $0.1))] }),
                      "scaled": .array(scaled.map { ["value": Self.n($0.0), "ratioBits": .bits($0.1), "scaled": Self.n(TokenRowDisplayRule.scaledAccountBucket($0.0, ratio: $0.1))] }),
                      "young": .array(youngNows.map { ["now": Self.d($0), "young": .bool(TokenRowDisplayRule.shareRatioMonthIsYoung($0))] }),
                      "graceDays": .int(TokenRowDisplayRule.shareRatioGraceDays)])
        // 순위판 월 이동 · 팀 리그 주 이동.
        var navigators: [GoldenJSON] = []
        for now in [Self.kstDate(2026, 10, 28, 10, 30), Self.kstDate(2027, 1, 1, 0, 0, 0), Self.kstDate(2026, 10, 26, 0, 0, 0)] {
            var months: [GoldenJSON] = []
            for key in ["2026-10", "2026-09", "2026-01", "2025-12", "2027-01", "2026-13", "bad", "2026-10-01", "2026-1"] {
                for delta in [-13, -1, 0, 1, 2] {
                    months.append(["key": .string(key), "delta": .int(delta), "step": .string(TokenBoardMonthNavigator.step(key, by: delta, now: now))])
                }
                months.append(["key": .string(key), "canStepForward": .bool(TokenBoardMonthNavigator.canStepForward(from: key, now: now)),
                               "displayTitle": .string(TokenBoardMonthNavigator.displayTitle(key, now: now))])
            }
            var weeks: [GoldenJSON] = []
            for offset in [-1, 0, 1, 6, 7, 30] {
                weeks.append(["offset": .int(offset), "key": .string(TeamLeagueWeekNavigator.key(offset: offset, now: now))])
            }
            for key in ["2026-10-26", "2026-10-19", "2026-09-14", "2026-08-03", "2026-11-02", "2026-10-28", "bad", "2025-12-29", "2026-10-25"] {
                weeks.append(["key": .string(key), "offset": .int(TeamLeagueWeekNavigator.offset(forKey: key, now: now)),
                              "stepBack": .string(TeamLeagueWeekNavigator.step(key, by: -1, now: now)), "stepForward": .string(TeamLeagueWeekNavigator.step(key, by: 1, now: now)),
                              "canStepForward": .bool(TeamLeagueWeekNavigator.canStepForward(from: key, now: now)),
                              "canStepBack": .bool(TeamLeagueWeekNavigator.canStepBack(from: key, now: now)),
                              "isCurrentWeek": .bool(TeamLeagueWeekNavigator.isCurrentWeek(key, now: now)),
                              "displayTitle": .string(TeamLeagueWeekNavigator.displayTitle(key, now: now))])
            }
            navigators.append(["now": Self.d(now), "months": .array(months), "weeks": .array(weeks),
                               "clamps": .array([-3, 0, 3, 6, 9].map { .int(TeamLeagueWeekNavigator.clamp($0)) })])
        }
        cases.append(["id": "navigators", "maxWeeksBack": .int(TeamLeagueWeekNavigator.maxWeeksBack), "rows": .array(navigators)])
        goldenEmit(GoldenFile(
            golden: "insights/token",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckWorkInsights.swift", "Sources/CheckCore/CodexEffectiveRule.swift",
                           "Sources/CheckCore/CheckTokenRowDisplay.swift", "Sources/CheckCore/CheckTokenUsage.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: true,
            spec: [
                "serverTotals": "서버 일별 행 → 날짜별 유효 토큰: claude(음수 0) 기기 합 + Codex 유효(day 규칙 — 로컬은 codex_utc_total, 없으면 codex_total, 기기 합 · 계정 버킷은 기기 간 max · 마지막 버킷 날은 축소 전 키로). 계정 버킷에만 비율(반올림 .5 → 0 에서 먼 쪽)",
                "grid": "TokenDailyGrid — 근무 잔디와 같은 창 · 미래 · 창 밖 · 못 읽는 날 버림 · 0 이하 버림. overlaying = 같은 창일 때만 칸별 max(미래 칸 제외)",
                "codex": "CodexEffectiveRule — 계정 우선 + 마지막 버킷 날 max + 그 뒤는 로컬",
                "share": "accountShareRatio(share, bucketSum) = clamp(share/bucketSum, 0, 1), share 없음 · 분모 ≤ 0 → 1. scaledAccountBucket = 비율 < 1 일 때 Int((v × r).rounded())",
                "navigators": "월 이동(현재 월 위로 못 감 · 못 읽으면 현재 월) · 주 이동(서버 오프셋 0…6 접기 · 부호 규약 둘)",
                "platformSensitive": "true — KST 달력(tzdata)",
            ],
            cases: cases
        ))
    }

    // MARK: text/number-format

    @Test("text/number-format — 토큰 숫자 콤마 · 억/만 축약")
    func numberFormat() {
        let values = [-5, 0, 1, 9, 999, 1_000, 9_999, 10_000, 14_999, 15_000, 99_994_999, 99_995_000, 99_999_999, 100_000_000, 104_999_999,
                      105_000_000, 19_658_964_272, 20_000_000_000, 99_949_999_999, 99_950_000_000, 99_999_999_999, 100_000_000_000,
                      123_456_789_012, 4_564_338_243, 2_543_110, Int.max]
        goldenEmit(GoldenFile(
            golden: "text/number-format",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckTokenUsage.swift"],
            platformSensitive: false,
            spec: [
                "grouped": "콤마 천 단위 전체 숫자(축약 없음, 음수 0) — 로캘 무관 수동 조립(C§4 #32)",
                "compactKorean": "1억 이상 억 단위(1000억 미만 소수 첫째 반올림 · .0 떼기, 이상은 정수 반올림 + 콤마) · 1만 이상 만 단위 반올림(1억에 닿으면 '1억') · 그 미만 grouped · 0 이하 '0'. 정수 연산만",
            ],
            cases: values.map { value in
                ["id": .string("v\(value)"), "value": Self.n(value), "grouped": .string(TokenNumberFormatter.grouped(value)),
                 "compactKorean": .string(value == Int.max ? "" : TokenNumberFormatter.compactKorean(value))]
            }
        ))
    }

    // MARK: dates/ailimit

    static func snapshotJSON(_ s: AILimitWindowSnapshot) -> GoldenJSON {
        ["window": .string(s.window.rawValue), "usedPercentBits": .bits(s.usedPercent), "resetsAt": Self.d(s.resetsAt),
         "observedAt": Self.d(s.observedAt), "source": .string(s.source.rawValue)]
    }

    static func displayJSON(_ v: AILimitDisplay) -> GoldenJSON {
        ["isVisible": .bool(v.isVisible), "valueText": .string(v.valueText), "captionText": .string(v.captionText),
         "percentBits": Self.f(v.percent), "floorOnly": .bool(v.floorOnly), "freshness": .string(v.freshness.rawValue),
         "claimAgeBits": Self.f(v.claimAge), "provider": Self.s(v.provider?.rawValue), "window": Self.s(v.window?.rawValue),
         "source": Self.s(v.source?.rawValue), "resetsAt": Self.d(v.resetsAt)]
    }

    @Test("dates/ailimit — 창 판정 · 신선도 · 값 · 기기 접기 · 메인 맥")
    func aiLimit() {
        var cases: [GoldenJSON] = []
        let lengths: [Double?] = [nil, 0, -5, 1, 9_000, 9_001, 18_000, 36_000, 36_001, 100_000, 302_400, 302_399, 604_800, 1_209_600, 1_209_601, 5e9]
        cases.append(["id": "matching", "rows": .array(lengths.map { length in
            ["lengthBits": Self.f(length), "window": Self.s(AILimitWindow.matching(lengthSeconds: length)?.rawValue)]
        })])
        let names = ["five_hour", "fiveHour", "5h", "primary", "primary_window", "weekly", "seven_day", "sevenDay", "7d", "secondary",
                     "secondary_window", "seven_day_sonnet", "FIVE_HOUR", "", "monthly"]
        cases.append(["id": "window-names", "rows": .array(names.map { ["name": .string($0), "window": Self.s(AILimitWindow(providerWindowName: $0)?.rawValue)] }),
                      "windows": .array(AILimitWindow.allCases.map { ["raw": .string($0.rawValue), "lengthBits": .bits($0.lengthSeconds),
                                                                      "displayName": .string($0.displayName), "sortOrder": .int($0.sortOrder)] }),
                      "providers": .array(AILimitProvider.allCases.map { ["raw": .string($0.rawValue), "displayName": .string($0.displayName),
                                                                          "compactName": .string($0.compactName), "sortOrder": .int($0.sortOrder)] })])
        let fractions: [Double] = [1, 0, 0.28, 0.5, 1.0001, -0.1, .nan, .infinity, 0.123456789]
        cases.append(["id": "scale", "rows": .array(fractions.map { ["fractionBits": .bits($0), "usedBits": .bits(AILimitScale.usedPercent(remainingFraction: $0))] })])
        let base = Date(timeIntervalSince1970: 1_792_000_000)
        // 스냅샷 표본: 사용률 · 리셋 · 관측 · 창 조합.
        var samples: [AILimitWindowSnapshot] = []
        for window in AILimitWindow.allCases {
            for used in [0.0, 0.4, 26, 99.5, 100, 101, -3, .nan] {
                for resetOffset in [nil, -10, 3_600, window.lengthSeconds, window.lengthSeconds + 600, window.lengthSeconds + 601] as [Double?] {
                    samples.append(AILimitWindowSnapshot(window: window, usedPercent: used, resetsAt: resetOffset.map { base.addingTimeInterval($0) },
                                                         observedAt: base, source: used > 50 ? .server : .local))
                }
            }
        }
        let ages: [Double] = [-200, -121, -120, 0, 59, 60, 61, 1_800, 1_801, 86_400, 86_401, 3_600 + 120, 3_600 + 119, 18_000 + 1_800 + 120, 18_000 + 1_801 + 120]
        var displays: [GoldenJSON] = []
        for (index, snapshot) in samples.enumerated() {
            displays.append(["sample": .int(index), "snapshot": Self.snapshotJSON(snapshot), "byAge": .array(ages.map { age in
                Self.displayJSON(AILimitFreshnessRule.display(snapshot, now: base.addingTimeInterval(age)))
            })])
        }
        cases.append(["id": "display", "baseBits": .bits(base.timeIntervalSince1970), "agesBits": .array(ages.map(GoldenJSON.bits)), "rows": .array(displays)])
        cases.append(["id": "display-nil", "display": Self.displayJSON(AILimitFreshnessRule.display(nil, now: base))])
        // 제공자 묶음 · combine.
        let claude = AILimitProviderSnapshot(provider: .claude, windows: [samples[2], samples[50]], planLabel: "max20", accountFingerprint: nil)
        let codexEmpty = AILimitProviderSnapshot(provider: .codex, windows: [])
        let ag = AILimitProviderSnapshot(provider: .antigravity, windows: [samples[60], samples[3]])
        var providerRows: [GoldenJSON] = []
        for snapshot in [claude, codexEmpty, ag] {
            providerRows.append([
                "provider": .string(snapshot.provider.rawValue), "isLinked": .bool(snapshot.isLinked), "source": Self.s(snapshot.source?.rawValue),
                "latestObservedAt": Self.d(snapshot.latestObservedAt), "orderedWindows": .array(snapshot.orderedWindows.map(Self.snapshotJSON)),
                "displays": .array(ages.prefix(6).map { age in .array(AILimitFreshnessRule.displays(provider: snapshot, now: base.addingTimeInterval(age)).map(Self.displayJSON)) }),
                "fiveHour": Self.displayJSON(AILimitFreshnessRule.display(provider: snapshot, window: .fiveHour, now: base.addingTimeInterval(30))),
                "weekly": Self.displayJSON(AILimitFreshnessRule.display(provider: snapshot, window: .weekly, now: base.addingTimeInterval(30))),
            ])
        }
        let bundle = AILimitSnapshotBundle(providers: [ag, codexEmpty, claude])
        cases.append(["id": "providers", "samples": .array([2, 50, 60, 3].map { Self.snapshotJSON(samples[$0]) }), "rows": .array(providerRows),
                      "visibleProviders": .array(bundle.visibleProviders.map { .string($0.provider.rawValue) }),
                      "providerNil": Self.displayJSON(AILimitFreshnessRule.display(provider: nil, window: .weekly, now: base))])
        var combos: [GoldenJSON] = []
        let comboSets: [[Int]] = [[], [0], [2, 8], [2, 50], [50, 60], [3, 4], [9, 10, 11], [100, 200, 300], [1, 2, 3, 4, 5, 6, 7]]
        for set in comboSets {
            for age in [0.0, 1_801, 90_000] {
                let parts = set.map { AILimitFreshnessRule.display(samples[$0 % samples.count], now: base.addingTimeInterval(age)) }
                combos.append(["set": .array(set.map(GoldenJSON.int)), "ageBits": .bits(age), "combined": Self.displayJSON(AILimitFreshnessRule.combine(parts))])
            }
        }
        cases.append(["id": "combine", "rows": .array(combos)])
        let percents: [Double] = [-1, 0, 0.1, 0.49, 0.5, 0.51, 1.5, 2.5, 26, 98.5, 99.4, 99.5, 99.9, 100, 101, .nan, .infinity]
        cases.append(["id": "values", "rows": .array(percents.map { p in
            ["percentBits": .bits(p), "whole": .int(AILimitFreshnessRule.wholePercent(p)), "clampedBits": .bits(AILimitFreshnessRule.clampedPercent(p)),
             "fresh": .string(AILimitFreshnessRule.valueText(percent: p, freshness: .fresh)), "stale": .string(AILimitFreshnessRule.valueText(percent: p, freshness: .stale)),
             "reset": .string(AILimitFreshnessRule.valueText(percent: p, freshness: .reset)), "unknown": .string(AILimitFreshnessRule.valueText(percent: p, freshness: .unknown))]
        }), "grades": .array([0.0, 60, 61, 1_800, 1_801, 86_400, 86_401].flatMap { age in
            [false, true].map { reset in ["ageBits": .bits(age), "resetClaimed": .bool(reset), "grade": .string(AILimitFreshnessRule.grade(age: age, resetClaimed: reset).rawValue)] }
        }), "constants": ["clockSkewTolerance": .bits(AILimitFreshnessRule.clockSkewTolerance), "freshWithin": .bits(AILimitFreshnessRule.freshWithin),
                          "recentWithin": .bits(AILimitFreshnessRule.recentWithin), "staleWithin": .bits(AILimitFreshnessRule.staleWithin),
                          "sameWindowTolerance": .bits(AILimitFreshnessRule.sameWindowTolerance)]])
        // worstPerWindow.
        let worst = AILimitWindowSnapshot.worstPerWindow([samples[2], samples[5], samples[3], samples[50], samples[51], samples[52], samples[4]])
        cases.append(["id": "worst", "result": .array(worst.map(Self.snapshotJSON))])
        // 기기 축.
        let labels: [String?] = [nil, "", "  ", " Mac mini ", "예성의 MacBook Pro", String(repeating: "가", count: 70),
                                 String(repeating: "👨‍👩‍👧‍👦", count: 10) + "끝", "\u{200B}", "a\u{301}" + String(repeating: "b", count: 63)]
        cases.append(["id": "device-labels", "rows": .array(labels.map { ["label": Self.s($0), "normalized": Self.s(AILimitDeviceLabelContract.normalized($0))] }),
                      "maxScalars": .int(AILimitDeviceLabelContract.maxScalars)])
        let observations: [AILimitDeviceObservation] = [
            .init(deviceID: "dev-a1b2", label: "Mac mini", observedAt: base),
            .init(deviceID: "dev-c3d4", label: "Mac mini", observedAt: base.addingTimeInterval(60)),
            .init(deviceID: "dev-a1b2", label: nil, observedAt: base.addingTimeInterval(120)),
            .init(deviceID: " dev-e5f6 ", label: "  ", observedAt: nil),
            .init(deviceID: "", label: "빈 id", observedAt: base),
            .init(deviceID: "dev-g7h8", label: "옛 이름", observedAt: base.addingTimeInterval(-60)),
            .init(deviceID: "dev-g7h8", label: "새 이름", observedAt: base.addingTimeInterval(-30)),
            .init(deviceID: "dev-g7h8", label: "시각 없는 이름", observedAt: nil),
            .init(deviceID: "dev-zz", label: nil, observedAt: nil),
        ]
        let devices = AILimitDeviceRoster.fold(observations)
        let parts = AILimitDeviceRoster.displayNameParts(devices)
        let combined = AILimitDeviceRoster.displayNames(devices)
        cases.append(["id": "devices",
                      "observations": .array(observations.map { ["deviceID": .string($0.deviceID), "label": Self.s($0.label), "observedAt": Self.d($0.observedAt)] }),
                      "fold": .array(devices.map { ["deviceID": .string($0.deviceID), "label": Self.s($0.label), "lastObservedAt": Self.d($0.lastObservedAt),
                                                     "baseName": .string($0.baseName)] }),
                      "parts": .object(parts.mapValues { ["base": .string($0.base), "tail": Self.s($0.tail), "combined": .string($0.combined)] }),
                      "combined": .object(combined.mapValues(GoldenJSON.string)),
                      "shortTails": .array(["dev-a1b2", "ab", "", "x-ffff"].map { .string(AILimitDevice.shortTail($0)) }),
                      "main": .array(([nil, "dev-c3d4", "missing", "dev-zz"] as [String?]).map { chosen in
                          ["chosen": Self.s(chosen), "resolved": Self.s(AILimitMainDeviceRule.resolve(devices: devices, chosen: chosen)?.deviceID),
                           "resolvedReversed": Self.s(AILimitMainDeviceRule.resolve(devices: devices.reversed(), chosen: chosen)?.deviceID)]
                      }),
                      "mainEmpty": Self.s(AILimitMainDeviceRule.resolve(devices: [], chosen: "x")?.deviceID),
                      // 같은 id · 같은 시각이 둘(호출부가 접지 않은 배열) — Swift max(by:) 는 앞의 것을 둔다. 라벨로 어느 쪽인지 잰다.
                      "mainTies": .array([
                          [AILimitDevice(deviceID: "dev-x", label: "첫째", lastObservedAt: base), AILimitDevice(deviceID: "dev-x", label: "둘째", lastObservedAt: base),
                           AILimitDevice(deviceID: "dev-a", label: "가", lastObservedAt: base.addingTimeInterval(-10))],
                          [AILimitDevice(deviceID: "dev-n", label: "첫째", lastObservedAt: nil), AILimitDevice(deviceID: "dev-n", label: "둘째", lastObservedAt: nil)],
                          [AILimitDevice(deviceID: "dev-b", label: "옛", lastObservedAt: base), AILimitDevice(deviceID: "dev-a", label: "가", lastObservedAt: base),
                           AILimitDevice(deviceID: "dev-a", label: "나", lastObservedAt: base)],
                      ].map { list in
                          ["devices": .array(list.map { ["deviceID": .string($0.deviceID), "label": Self.s($0.label), "lastObservedAt": Self.d($0.lastObservedAt)] }),
                           "resolvedLabel": Self.s(AILimitMainDeviceRule.resolve(devices: list, chosen: nil)?.label),
                           "chosenLabel": Self.s(AILimitMainDeviceRule.resolve(devices: list, chosen: list[0].deviceID)?.label)]
                      })])
        let fingerprints: [String?] = [nil, "", "  ", "someone@example.com", " someone@example.com\n", "acct-123", "한글 계정"]
        cases.append(["id": "fingerprints", "rows": .array(fingerprints.map { ["raw": Self.s($0), "fingerprint": Self.s(AILimitFingerprint.make($0))] })])
        goldenEmit(GoldenFile(
            golden: "dates/ailimit",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/AILimits.swift", "Sources/CheckCore/AILimitFreshnessRule.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: false,
            spec: [
                "matching": "AILimitWindow.matching — 두 창 길이와의 비(max/min) ≤ 2 인 것 중 가장 가까운 것, 아니면 null(이름보다 먼저 — 2026-10-23 실측)",
                "display": "AILimitFreshnessRule.display — 시계 앞섬 > 120초 · 리셋이 관측 앞 · 리셋이 창 길이 + 600 초과 → 알 수 없음. 리셋 주장(사용 > 0 이고 now ≥ 리셋 + 120) → 0% · 나이는 리셋부터. 등급 fresh ≤60 · recent ≤1800 · stale ≤86400 · ancient. stale·ancient 는 '이상'",
                "values": "wholePercent = clamp 후 .rounded()(0.5 → 0 에서 먼 쪽), 0 초과면 최소 1, 100 미만이면 최대 99",
                "devices": "기기 접기 — 최근 순(관측 없음은 뒤, 동률은 id), 이름은 라벨 있는 가장 최근 행. 이름이 겹치면 꼬리(id 끝 4자 대문자)",
                "fingerprint": "SHA-256 앞 16 hex(앞뒤 공백 trim, 비면 null) — 서버로 가지 않는다",
            ],
            cases: cases
        ))
    }
}
