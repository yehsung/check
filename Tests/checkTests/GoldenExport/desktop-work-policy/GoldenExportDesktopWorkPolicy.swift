// 원본: 없음(W2-g6 골든 생성기 — Sources/check/CheckWorkNudge.swift NudgeScheduler · Sources/check/WorkTimerStore.swift 정책 상수 ·
//       ultraLapKey · PendingSleepClose · Sources/CheckCore/MilestoneTracker.swift dayKey 를 잰다)
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

// Windows 근무 정책(wp) 골든. Kotlin 은 feature/desktop/…/work/{policy,nudge,lap} 이 같은 입력으로 같은 출력을 내야 한다.
//
//   · desktop-work-policy/constants   잠자기 유예 · 12시간 · 30분 · away 스로틀 · 재개 창 · 방치 임계 · 마일스톤 · 넛지 상수 · 영속 키
//   · desktop-work-policy/nudge       NudgeScheduler 를 각본(시각 · idle · 자격 · 세션 · 깨어남)으로 몰아 tick 마다 누적 발동·적립·쿨다운·공백 신호
//   · desktop-work-policy/laps        ultraLapKey(랩마다 다른 키 ㉕) · MilestoneTracker.dayKey(KST 자정 경계) · PendingSleepClose JSON(정렬 키)
// UserDefaults·창·네트워크를 쓰지 않는다(GoldenEmit 규칙) — 스토어 시나리오(잠자기·12h·away·종료 3초)는 Kotlin 시험이 Swift 시험
// (AwayCloseTests · V0236StoreTests · CheckNudgeTests · NudgeAutoStartContractTests)을 본떠 잰다.

@MainActor
@Suite("GoldenExport desktop-work-policy — 근무 정책 상수 · 넛지 각본 · 랩 키")
struct GoldenExportDesktopWorkPolicy {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 (KST 오후)

    static func secs(_ value: TimeInterval) -> GoldenJSON { .int(Int(value)) }

    @Test("constants — 정책 상수 · 영속 키")
    func constants() {
        let values: [(String, GoldenJSON)] = [
            ("sleepGraceSeconds", Self.secs(WorkTimerStore.sleepGraceSeconds)),
            ("heartbeatIntervalSeconds", Self.secs(WorkTimerStore.heartbeatIntervalSeconds)),
            ("adoptedReclaimStaleSeconds", Self.secs(WorkTimerStore.adoptedReclaimStaleSeconds)),
            ("longSessionThresholdSeconds", Self.secs(WorkTimerStore.longSessionThresholdSeconds)),
            ("longSessionResponseWindowSeconds", Self.secs(WorkTimerStore.longSessionResponseWindowSeconds)),
            ("recentAutoCloseResumeWindowSeconds", Self.secs(WorkTimerStore.recentAutoCloseResumeWindowSeconds)),
            ("awaySyncIdleThrottleSeconds", Self.secs(WorkTimerStore.awaySyncIdleThrottleSeconds)),
            ("milestoneHourOneSeconds", .int(WorkTimerStore.milestoneHourOneSeconds)),
            ("milestoneHourFourSeconds", .int(WorkTimerStore.milestoneHourFourSeconds)),
            ("missionWorkSecondsHint", .int(WorkTimerStore.missionWorkSecondsHint)),
            ("nudgeCheckInterval", Self.secs(NudgeScheduler.checkInterval)),
            ("nudgeActiveIdleThreshold", Self.secs(NudgeScheduler.activeIdleThreshold)),
            ("nudgeRequiredActiveMinutes", .int(NudgeScheduler.requiredActiveMinutes)),
            ("nudgeActiveWindowSeconds", Self.secs(NudgeScheduler.activeWindowSeconds)),
            ("nudgeCooldownSeconds", Self.secs(NudgeScheduler.cooldownSeconds)),
            ("nudgeRearmGapSeconds", Self.secs(NudgeScheduler.rearmGapSeconds)),
            ("pendingSleepCloseKey", .string(WorkTimerStore.pendingSleepCloseKey)),
            ("autoStartSuppressedKey", .string(WorkTimerStore.autoStartSuppressedKey)),
            ("nudgeLastAliveAtKey", .string(WorkTimerStore.nudgeLastAliveAtKey)),
            ("milestoneHourOneKey", .string(MilestoneTracker.hourOneKey)),
            ("milestoneHourFourKey", .string(MilestoneTracker.hourFourKey)),
            ("milestoneHourThreeKey", .string(MilestoneTracker.hourThreeKey)),
            ("milestoneTeamGoalKey", .string(MilestoneTracker.teamGoalKey)),
            ("milestoneFirstArrivalKey", .string(MilestoneTracker.firstArrivalKey)),
        ]
        let cases: [GoldenJSON] = values.map { .object(["id": .string($0.0), "value": $0.1]) }
        goldenEmit(GoldenFile(
            golden: "desktop-work-policy/constants",
            equivalence: .bit,
            swiftSources: ["Sources/check/WorkTimerStore.swift", "Sources/check/CheckWorkNudge.swift", "Sources/CheckCore/MilestoneTracker.swift"],
            spec: [
                "units": "초는 정수 초(Swift TimeInterval 을 Int 로 — 전부 정수다). 키는 영속 키 글자 그대로.",
                "rules": "⑲ 잠자기 유예 초과만 마감 · ㉑ 12h + 30분 · 30분 재개 창 · away 비근무 스로틀 120초 · 방치 자가 마감 = 유예 + 4 하트비트",
            ],
            cases: cases
        ))
    }

    // MARK: nudge

    /// 각본 한 걸음. idleMs nil = 의미 있는 입력 관측 없음(이동만 — 무한대).
    struct Step {
        var atMs: Int
        var idleMs: Int?
        var eligible = true
        var usable = true
        var wakeBefore = false
    }

    final class Box {
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        var idle: TimeInterval = .infinity
        var eligible = true
        var usable = true
        var nudges = 0
        var gaps = 0
        var alive = 0
    }

    static func run(_ id: String, _ steps: [Step]) -> GoldenJSON {
        let box = Box()
        let scheduler = NudgeScheduler(
            idleSeconds: { box.idle },
            clock: { box.now },
            isEligible: { box.eligible },
            onNudge: { box.nudges += 1 },
            isSessionUsable: { box.usable },
            onAbsenceGap: { box.gaps += 1 },
            onAliveTick: { _ in box.alive += 1 },
            workspaceNotifications: nil
        )
        var input: [GoldenJSON] = []
        var output: [GoldenJSON] = []
        for step in steps {
            box.now = t0.addingTimeInterval(TimeInterval(step.atMs) / 1000)
            box.idle = step.idleMs.map { TimeInterval($0) / 1000 } ?? .infinity
            box.eligible = step.eligible
            box.usable = step.usable
            if step.wakeBefore { scheduler.handleWake() }
            scheduler.tick()
            input.append(.object([
                "atMs": .int(step.atMs),
                "idleMs": step.idleMs.map(GoldenJSON.int) ?? .null,
                "eligible": .bool(step.eligible),
                "usable": .bool(step.usable),
                "wakeBefore": .bool(step.wakeBefore),
            ]))
            let cooldown = scheduler.cooldownUntil == .distantPast
                ? GoldenJSON.null
                : .int(Int((scheduler.cooldownUntil.timeIntervalSince(t0) * 1000).rounded()))
            output.append(.object([
                "nudges": .int(box.nudges),
                "activeMinutes": .int(scheduler.activeMinutes),
                "cooldownUntilMs": cooldown,
                "absenceGaps": .int(box.gaps),
                "aliveTicks": .int(box.alive),
            ]))
        }
        return .object(["id": .string(id), "steps": .array(input), "expect": .array(output)])
    }

    static func minutes(_ range: ClosedRange<Int>, idleMs: Int?, eligible: Bool = true, usable: Bool = true) -> [Step] {
        range.map { Step(atMs: $0 * 60_000, idleMs: idleMs, eligible: eligible, usable: usable) }
    }

    @Test("nudge — 이동만 0 · 클릭 5분 1 · 1시간 쉼 · 설정 끔 0 · 잠금 0 · 창 밖 적립 소멸 · 깨어남 리셋 · 공백")
    func nudge() {
        var cases: [GoldenJSON] = []
        cases.append(Self.run("click-every-minute", Self.minutes(1...6, idleMs: 10_000)))
        cases.append(Self.run("move-only", Self.minutes(1...12, idleMs: nil)))
        cases.append(Self.run("cooldown-one-hour", Self.minutes(1...70, idleMs: 10_000)))
        cases.append(Self.run("setting-off", Self.minutes(1...12, idleMs: 10_000, eligible: false)))
        cases.append(Self.run("locked", Self.minutes(1...12, idleMs: 10_000, usable: false)))
        // 임계 120초는 배타 — 정확히 120.000초 idle 은 적립하지 않고(앞 6분 0), 119.999초는 적립한다(뒤 5분째 발동).
        cases.append(Self.run("idle-boundary", Self.minutes(1...6, idleMs: 120_000) + Self.minutes(7...12, idleMs: 119_999)))
        cases.append(Self.run("every-third-minute", (1...12).map { m in
            Step(atMs: m * 60_000, idleMs: m % 3 == 1 ? 5_000 : 600_000)
        }))
        cases.append(Self.run("every-other-minute", (1...12).map { m in
            Step(atMs: m * 60_000, idleMs: m % 2 == 1 ? 5_000 : 600_000)
        }))
        var wake = Self.minutes(1...4, idleMs: 10_000)
        wake.append(Step(atMs: 5 * 60_000, idleMs: 10_000, wakeBefore: true))
        wake += Self.minutes(6...10, idleMs: 10_000)
        cases.append(Self.run("wake-resets", wake))
        cases.append(Self.run("absence-gap", [
            Step(atMs: 0, idleMs: 1_000),
            Step(atMs: 3_599_999, idleMs: 1_000),
            Step(atMs: 7_199_999, idleMs: 1_000),
            Step(atMs: 7_259_999, idleMs: 3_600_000),
        ]))
        cases.append(Self.run("eligibility-flicker", Self.minutes(1...3, idleMs: 10_000)
            + [Step(atMs: 4 * 60_000, idleMs: 10_000, eligible: false)]
            + Self.minutes(5...10, idleMs: 10_000)))
        goldenEmit(GoldenFile(
            golden: "desktop-work-policy/nudge",
            equivalence: .bit,
            swiftSources: ["Sources/check/CheckWorkNudge.swift"],
            spec: [
                "drive": "t0 = 1970+1_790_000_000초. 걸음마다 시각·idle(ms, null=관측 없음=무한대)·자격·세션 사용 가능을 놓고(깨어남이면 handleWake 먼저) tick 한 번.",
                "expect": "tick 뒤 누적 발동 수 · 적립 분 · 쿨다운 끝(t0 기준 ms, null=과거) · 누적 공백 신호 · 누적 생존 스탬프",
                "rules": "㉔ 이동만이면 idle=무한대라 적립 0 · 최근 10분 창 안 5분이면 발동 · 발동 뒤 1시간 쉼 · 자격 거짓(설정 끔)·잠금이면 0",
            ],
            cases: cases
        ))
    }

    // MARK: laps · day keys · marker

    @Test("laps — ultraLapKey · KST dayKey · PendingSleepClose JSON")
    func laps() throws {
        var cases: [GoldenJSON] = []
        for lap in [-1, 0, 1, 2, 3, 4, 10] {
            cases.append(.object(["id": .string("lap-key/\(lap)"), "lap": .int(lap), "key": .string(MilestoneTracker.ultraLapKey(lap))]))
        }
        // KST 자정 = UTC 15:00. 1_790_000_000 = 2026-09-21T14:13:20Z → 자정 1분 전후 · 정확히 자정 · 윤년 2월 말 · 연말.
        let instants: [Int] = [1_790_000_000, 1_790_002_740, 1_790_002_799, 1_790_002_800, 1_790_002_801, 1_709_218_799, 1_709_218_800, 1_798_729_199, 1_798_729_200, 0]
        for t in instants {
            cases.append(.object([
                "id": .string("day-key/\(t)"),
                "epochSeconds": .int(t),
                "key": .string(MilestoneTracker.dayKey(Date(timeIntervalSince1970: TimeInterval(t)))),
            ]))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let markers: [(String, PendingSleepClose)] = [
            ("marker/with-input", PendingSleepClose(
                sessionID: "6f1c2a9e-0000-4000-8000-00000000abcd",
                sessionStartedAt: Self.t0,
                sleepBeganAt: Self.t0.addingTimeInterval(3_600),
                lastInputAt: Self.t0.addingTimeInterval(3_000)
            )),
            ("marker/no-input", PendingSleepClose(
                sessionID: "6f1c2a9e-0000-4000-8000-00000000abcd",
                sessionStartedAt: Self.t0,
                sleepBeganAt: Self.t0.addingTimeInterval(7_200),
                lastInputAt: nil
            )),
        ]
        for (id, marker) in markers {
            let text = String(decoding: try encoder.encode(marker), as: UTF8.self)
            cases.append(.object([
                "id": .string(id),
                "json": .string(text),
                "sessionStartedAtMs": .int(Int((marker.sessionStartedAt.timeIntervalSince(Self.t0) * 1000).rounded())),
                "sleepBeganAtMs": .int(Int((marker.sleepBeganAt.timeIntervalSince(Self.t0) * 1000).rounded())),
                "lastInputAtMs": marker.lastInputAt.map { .int(Int(($0.timeIntervalSince(Self.t0) * 1000).rounded())) } ?? .null,
            ]))
        }
        goldenEmit(GoldenFile(
            golden: "desktop-work-policy/laps",
            equivalence: .bit,
            swiftSources: ["Sources/check/WorkTimerStore.swift", "Sources/CheckCore/MilestoneTracker.swift"],
            spec: [
                "lap-key": "㉕ 랩 1 이하 = hour3(옛 키 연속성), 2부터 hour3.lap<n> — 랩마다 다른 키",
                "day-key": "MilestoneTracker.dayKey — KST yyyyMMdd",
                "marker": "PendingSleepClose JSONEncoder(sortedKeys) — Date 는 기준일(2001) 초 Double, lastInputAt 은 nil 이면 키가 없다. 시각은 t0 기준 ms 로도 적는다",
            ],
            cases: cases
        ))
    }
}
