// 원본: Sources/check/WorkTimerStore.swift(start·stop·closeOwnedSessionLocally·소유 3699-3850) ·
// Sources/check/WorkTimerStoreSync.swift(applyRemoteOwnStatus 1969 · releaseOwnershipIfAnotherDeviceClaims · yieldsToClaim 2415) @ a90d8623.
// Kotlin 대조: multiplatform/feature/desktop/src/desktopTest/…/work/state/DesktopWorkStateGoldenTest.kt (W2-g5 · xplat-w1/briefs/work.md §5 ws).
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 데스크톱 근무 상태 코어 골든 — SessionOwnershipTests · AdoptedSessionStoreTests · V0236SyncTests 의 장면을 덤프로 굳힌다.
// 장면마다 스토어를 새로 세우고(스텁 URLSession — 바깥 요청 0) 동기 단계만 밟는다(await 0 — 동기화 Task 가 끼어들 틈이 없다).
// 덤프는 결정적인 값만: 시각은 T0 기준 초 오프셋, start() 가 만든 무작위 세션 id 는 "$start"(소문자 여부는 따로 bool).
@MainActor
@Suite("GoldenExport desktop-work-state — 시작·종료·소유·흡수·서버 마감 (a)/(b)·늦은 응답·'win:' 반납")
struct GoldenExportDesktopWorkState {
    static let t0 = Date(timeIntervalSince1970: 1_789_621_500) // 2026-09-17 14:05 KST
    static let me = "00000000-0000-0000-0000-000000000002"
    static let sessionS = "a0000000-0000-4000-8000-000000000001"
    static let sessionX = "b0000000-0000-4000-8000-000000000002"
    static let macDevice = "3F2A9C1E-0000-4000-8000-0000000000AA"
    static let winDevice = "win:7b1e0c2a-0000-4000-8000-0000000000bb"

    static func makeStore(_ host: String) -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
        let suiteName = CheckTestScratch.uniqueSuitePath()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"], defaults: defaults)
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.clock = { t0 }
        return store
    }

    static func off(_ date: Date?) -> GoldenJSON {
        guard let date else { return .null }
        return .int(Int(date.timeIntervalSince(t0)))
    }

    static func str(_ value: String?, start: String?) -> GoldenJSON {
        guard let value else { return .null }
        if let start, value == start { return .string("$start") }
        return .string(value)
    }

    static func working(_ sessionID: String, startedAt: Date, lastSeenAt: Date, claims: [StatusDeviceClaim] = []) -> TeamMemberStatus {
        TeamMemberStatus(
            id: me, name: "나", status: .working, updatedAt: lastSeenAt, currentSessionStartedAt: startedAt,
            weeklyDurationSeconds: 0, todayDurationSeconds: 0, avatarURL: nil, lastSeenAt: lastSeenAt,
            activeSessionID: sessionID, deviceClaims: claims,
            openSession: OpenSessionFact(id: sessionID.lowercased(), startedAt: startedAt)
        )
    }

    static func offWork(today: Int, lastSeenAt: Date) -> TeamMemberStatus {
        TeamMemberStatus(
            id: me, name: "나", status: .offWork, updatedAt: lastSeenAt, currentSessionStartedAt: nil,
            weeklyDurationSeconds: 0, todayDurationSeconds: today, avatarURL: nil, lastSeenAt: lastSeenAt,
            activeSessionID: nil, deviceClaims: [], openSession: nil
        )
    }

    /// 상태 덤프(Kotlin DesktopWorkStore 의 같은 이름 값과 1:1).
    static func dump(_ store: WorkTimerStore, gen0: Int, start: String?) -> GoldenJSON {
        let items: [GoldenJSON] = store.pendingItems.map { item in
            var o: [String: GoldenJSON] = [
                "sessionID": str(item.sessionID, start: start),
                "sessionStartedAt": off(item.sessionStartedAt),
                "endedAt": off(item.endedAt),
                "owner": item.ownerUserID.map(GoldenJSON.string) ?? .null,
                "reason": item.autoCloseReason.map { .string($0.rawValue) } ?? .null,
            ]
            switch item.operation {
            case .start:
                o["op"] = .string("start")
                o["duration"] = .null
            case .stop(let duration):
                o["op"] = .string("stop")
                o["duration"] = .int(duration)
            }
            return .object(o)
        }
        let defaults = store.defaults
        var lastAuto: GoldenJSON = .null
        if let reason = store.lastAutoClosedReason {
            lastAuto = .object([
                "reason": .string(reason.rawValue),
                "endedAt": off(store.lastAutoClosedEndedAt),
                "seconds": .int(store.lastAutoClosedSeconds),
            ])
        }
        return .object([
            "working": .bool(store.startedAt != nil),
            "startedAt": off(store.startedAt),
            "sessionID": str(WorkTimerStore.canonicalSessionID(store.currentSessionID), start: start),
            "sessionIDIsLowercase": .bool(store.currentSessionID.map { $0 == $0.lowercased() } ?? true),
            "confirmedSessionID": str(store.confirmedSessionID, start: start),
            "adopted": .bool(store.adoptedRemoteSession),
            "ownsStrongly": .bool(store.ownsCurrentSessionStrongly),
            "ownedIDStored": str(defaults.string(forKey: WorkTimerStore.ownedWorkSessionIDKey), start: start),
            "ownedStrengthStored": defaults.string(forKey: WorkTimerStore.ownedWorkSessionStrengthKey).map(GoldenJSON.string) ?? .null,
            "generationDelta": .int(store.workStateWriteGeneration - gen0),
            "items": .array(items),
            "lastAutoClose": lastAuto,
        ])
    }

    /// 장면 하나 = 이름 + 단계(스토어를 받아 무작위 start id 를 돌려준다).
    static func scene(_ id: String, _ steps: (WorkTimerStore) -> String?) -> GoldenJSON {
        let store = makeStore("golden-desktop-work-state-\(id)")
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
            store.syncTask?.cancel()
        }
        let gen0 = store.workStateWriteGeneration
        let start = steps(store)
        return .object(["id": .string(id), "dump": dump(store, gen0: gen0, start: start)])
    }

    /// 반납 장면: [device] 기기가 S 를 [ownStrength] 로 들고, 남의 기기 행 [claimDevice](opened=[claimOpened])가 두 번 전진한다.
    static func yieldScene(_ id: String, device: String, ownStrength: WorkTimerStore.SessionClaimStrength,
                           claimDevice: String, claimOpened: Bool) -> GoldenJSON {
        scene(id) { store in
            store.deviceID = device
            store.setOwnedWorkSessionID(sessionS, strength: ownStrength)
            for (i, seen) in [t0.addingTimeInterval(-20), t0.addingTimeInterval(-20), t0.addingTimeInterval(10)].enumerated() {
                let claims = i == 0 ? [] : [StatusDeviceClaim(deviceID: claimDevice, sessionID: sessionS, lastSeenAt: seen, openedSession: claimOpened)]
                store.teamMembers = [working(sessionS, startedAt: t0.addingTimeInterval(-3_600), lastSeenAt: t0.addingTimeInterval(-10), claims: claims)]
                store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            }
            return nil
        }
    }

    @Test
    func ownership() {
        Self.emitOwnership()
    }

    static func emitOwnership() {
        var cases: [GoldenJSON] = []
        cases.append(scene("start") { store in
            store.start(now: t0)
            return store.currentSessionID
        })
        cases.append(scene("start-stop") { store in
            store.start(now: t0)
            let id = store.currentSessionID
            store.pendingItems = []
            store.stop(now: t0.addingTimeInterval(5_400))
            return id
        })
        cases.append(scene("restart-uppercase-rescue") { store in
            store.defaults.set(sessionS.uppercased(), forKey: WorkTimerStore.ownedWorkSessionIDKey)
            store.defaults.set("strong", forKey: WorkTimerStore.ownedWorkSessionStrengthKey)
            store.teamMembers = [working(sessionS, startedAt: t0.addingTimeInterval(-3 * 3_600), lastSeenAt: t0.addingTimeInterval(-20))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            return nil
        })
        cases.append(scene("adopt-foreign") { store in
            store.teamMembers = [working(sessionX, startedAt: t0.addingTimeInterval(-600), lastSeenAt: t0.addingTimeInterval(-15))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            return nil
        })
        cases.append(scene("late-response-dropped") { store in
            let stale = store.workStateWriteGeneration
            store.start(now: t0)
            let id = store.currentSessionID
            store.pendingItems = []
            store.teamMembers = [offWork(today: 0, lastSeenAt: t0.addingTimeInterval(-30))]
            store.applyRemoteOwnStatus(writeGeneration: stale)
            return id
        })
        cases.append(scene("server-closed-a-live") { store in
            store.start(now: t0)
            let id = store.currentSessionID
            store.pendingItems = []
            store.persistPendingSleepClose(PendingSleepClose(
                sessionID: id!, sessionStartedAt: t0, sleepBeganAt: t0.addingTimeInterval(3_600), lastInputAt: t0.addingTimeInterval(3_000)))
            let later = t0.addingTimeInterval(7_200)
            store.clock = { later }
            store.teamMembers = [offWork(today: 0, lastSeenAt: t0.addingTimeInterval(3_600))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            return id
        })
        cases.append(scene("server-closed-b-relaunch") { store in
            store.setOwnedWorkSessionID(sessionS, strength: .strong)
            store.persistPendingSleepClose(PendingSleepClose(
                sessionID: sessionS, sessionStartedAt: t0.addingTimeInterval(-7_200), sleepBeganAt: t0.addingTimeInterval(-3_600), lastInputAt: nil))
            store.teamMembers = [offWork(today: 0, lastSeenAt: t0.addingTimeInterval(-3_600))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            return nil
        })
        cases.append(scene("remote-abandoned") { store in
            store.start(now: t0)
            let id = store.currentSessionID
            store.pendingItems = []
            let later = t0.addingTimeInterval(3_600)
            store.clock = { later }
            store.teamMembers = [offWork(today: 2_900, lastSeenAt: t0.addingTimeInterval(2_900))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            return id
        })
        cases.append(scene("remote-ended-elsewhere") { store in
            store.start(now: t0)
            let id = store.currentSessionID
            store.pendingItems = []
            let later = t0.addingTimeInterval(3_600)
            store.clock = { later }
            store.teamMembers = [offWork(today: 3_500, lastSeenAt: t0.addingTimeInterval(3_500))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            return id
        })
        cases.append(scene("stamp-c-then-adopt") { store in
            store.start(now: t0)
            let id = store.currentSessionID
            store.pendingItems = []
            store.confirmedServerSessionID = id
            store.teamMembers = [working(sessionX, startedAt: t0.addingTimeInterval(60), lastSeenAt: t0.addingTimeInterval(90))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            return id
        })
        cases.append(scene("auto-close-sleep") { store in
            store.start(now: t0)
            let id = store.currentSessionID
            store.pendingItems = []
            store.closeOwnedSessionLocally(endedAt: t0.addingTimeInterval(1_800), message: "잠자기로 자동 근무종료됨", reason: .sleep)
            return id
        })
        cases.append(scene("auto-close-adopted-noop") { store in
            store.teamMembers = [working(sessionX, startedAt: t0.addingTimeInterval(-600), lastSeenAt: t0.addingTimeInterval(-15))]
            store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
            store.closeOwnedSessionLocally(endedAt: t0, message: "잠자기로 자동 근무종료됨", reason: .sleep)
            return nil
        })
        // ⑯ 'win:' 대 맥 대문자 id — 둘 다 약하면 Windows 만 물러난다(정확히 한쪽).
        cases.append(yieldScene("yield-weak-win-vs-weak-mac", device: winDevice, ownStrength: .weak, claimDevice: macDevice, claimOpened: false))
        cases.append(yieldScene("yield-weak-mac-vs-weak-win", device: macDevice, ownStrength: .weak, claimDevice: winDevice, claimOpened: false))
        cases.append(yieldScene("yield-strong-win-vs-weak-mac", device: winDevice, ownStrength: .strong, claimDevice: macDevice, claimOpened: false))
        cases.append(yieldScene("yield-weak-win-vs-strong-mac", device: winDevice, ownStrength: .weak, claimDevice: macDevice, claimOpened: true))
        cases.append(yieldScene("yield-strong-mac-vs-strong-win", device: macDevice, ownStrength: .strong, claimDevice: winDevice, claimOpened: true))

        goldenEmit(GoldenFile(
            golden: "desktop-work-state/ownership",
            equivalence: .bit,
            swiftSources: ["Sources/check/WorkTimerStore.swift", "Sources/check/WorkTimerStoreSync.swift"],
            spec: [
                "clock": "T0 = 1789621500(1970 기준 초, 2026-09-17 14:05 KST). 시각은 T0 기준 초 오프셋(Int 절삭)",
                "session-id": "start() 가 만든 무작위 id 는 \"$start\" — 소문자 여부는 sessionIDIsLowercase",
                "dump": "working · startedAt · sessionID(정규화) · confirmedSessionID · adopted · ownsStrongly · ownedIDStored(원문) · ownedStrengthStored · generationDelta · items(큐) · lastAutoClose",
                "yield-*": "기기 [device] 가 S 를 강도 [own] 으로 소유 · 남의 기기 행이 빈 관측 → 첫 관측 → 전진. ⑯ 동급이면 claim < mine 일 때 물러난다",
            ],
            cases: cases
        ))
    }
}
