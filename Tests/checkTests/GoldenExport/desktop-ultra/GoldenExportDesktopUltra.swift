// 원본: 없음(W2-g4 골든 생성기 — Sources/check/WorkTimerStorePoke.swift 지갑·집중 · Sources/CheckCore/SupabaseWorkModels.swift ·
//       Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 를 잰다). Kotlin 소비: feature/desktop/src/desktopTest/…/ultra/DesktopUltraGoldenTest.kt
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

// W2-g4 데스크톱 울트라·집중(Windows 이식 2차).
//
//   · desktop-ultra/wallet-apply   지갑 응답 원문(snake) → 디코드(실패 여부) → applyUltraWallet 뒤 잔량·상한·무제한·실패 깃발·미션 줄·스트릭·안내·연출 횟수
//   · desktop-ultra/focus-stage    FocusStagePolicy.stage/isExpired 표 · 화면 칸(focusStageFace) · 기록 키(소문자) · 상수
//   · desktop-ultra/requests       ultra_wallet_sync · buy_ultra · profiles PATCH(focus_mode) 요청(방법·경로·쿼리·Prefer·본문 바이트) ·
//                                  buy_ultra 응답 디코드 · 모자란 루비 문구

@Suite("GoldenExport desktop-ultra — 지갑·구매·집중")
struct GoldenExportDesktopUltra {
    static let userID = "00000000-0000-0000-0000-0000000000AB"
    static let now = Date(timeIntervalSince1970: 1_793_000_000)

    static func s(_ value: String?) -> GoldenJSON { value.map(GoldenJSON.string) ?? .null }
    static func i(_ value: Int?) -> GoldenJSON { value.map(GoldenJSON.int) ?? .null }
    static func b(_ value: Bool?) -> GoldenJSON { value.map(GoldenJSON.bool) ?? .null }
    static func d(_ value: Date?) -> GoldenJSON { value.map { .bits($0.timeIntervalSince1970) } ?? .null }

    final class Counter { var charged = 0 }

    /// 서비스 디코더와 같은 설정(SupabaseWorkService 는 actor 라 그 칸을 밖에서 못 읽는다 — SupabaseWorkService.swift 88-89).
    static func serviceDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @MainActor
    static func makeStore(_ name: String, host: String = "golden-ultra.invalid") -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
        let path = CheckTestScratch.suitePath(named: "golden-desktop-ultra-\(name)")
        let defaults = UserDefaults(suiteName: path)!
        defaults.removePersistentDomain(forName: path)
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
        return store
    }

    // MARK: - wallet-apply

    struct Prior {
        var balance: Int?
        var cap: Int?
        var unlimited: Bool
        var failed: Bool
        var target: Int?
        func json() -> GoldenJSON {
            let fields: [String: GoldenJSON] = [
                "balance": GoldenExportDesktopUltra.i(balance), "cap": GoldenExportDesktopUltra.i(cap), "unlimited": .bool(unlimited),
                "failed": .bool(failed), "missionTargetSeconds": GoldenExportDesktopUltra.i(target),
            ]
            return .object(fields)
        }
    }

    static func row(_ key: String = "work3h", day: String = "2026-10-30", target: Int = 10_800, progress: Int = 0, claimed: Bool = false,
                    granted: Bool = false, extra: String = "") -> String {
        "{\"key\":\"\(key)\",\"kst_day\":\"\(day)\",\"target_seconds\":\(target),\"progress_seconds\":\(progress),"
            + "\"claimed\":\(claimed),\"granted_now\":\(granted)\(extra)}"
    }

    static func ok(balance: String = "\"balance\":2,", day: String = "\"day\":\"2026-10-30\"", missions: [String]? = nil, extra: String = "") -> String {
        let m = missions.map { ",\"missions\":[" + $0.joined(separator: ",") + "]" } ?? ""
        return "{\"status\":\"ok\",\(balance)\(day)\(m)\(extra)}"
    }

    static let walletCorpus: [(String, Prior, String)] = {
        let none = Prior(balance: nil, cap: nil, unlimited: false, failed: false, target: nil)
        let known = Prior(balance: 4, cap: 5, unlimited: true, failed: true, target: 7_200)
        return [
            ("invalid", known, "{\"status\":\"invalid\"}"),
            ("invalid-with-junk", known, "{\"status\":\"invalid\",\"balance\":\"x\"}"),
            ("unknown-status", none, "{\"status\":\"maintenance\",\"balance\":9,\"day\":\"2026-10-30\"}"),
            ("ok-minimal", known, ok()),
            ("ok-missing-balance", known, ok(balance: "")),
            ("ok-missing-day", known, "{\"status\":\"ok\",\"balance\":2}"),
            ("ok-balance-string", known, ok(balance: "\"balance\":\"2\",")),
            ("negative-balance", none, ok(balance: "\"balance\":-3,")),
            ("cap-kept-when-absent", known, ok(missions: [row(progress: 600)])),
            ("cap-int4-max", none, ok(extra: ",\"balance_cap\":2147483647")),
            ("cap-null", known, ok(extra: ",\"balance_cap\":null")),
            ("unlimited-true", none, ok(extra: ",\"unlimited\":true")),
            ("unlimited-false", known, ok(extra: ",\"unlimited\":false")),
            ("unlimited-null", known, ok(extra: ",\"unlimited\":null")),
            ("unlimited-absent", known, ok()),
            ("today-half", none, ok(missions: [row(progress: 5_400, extra: ",\"laps_settled\":0,\"laps_granted\":0,\"worked_seconds\":5400")])),
            ("granted-lap1", none, ok(missions: [row(progress: 600, granted: true, extra: ",\"laps_settled\":1,\"laps_granted\":1,\"worked_seconds\":11400")])),
            ("granted-lap2", none, ok(missions: [row(progress: 600, granted: true, extra: ",\"laps_settled\":2,\"laps_granted\":2")])),
            ("granted-lap3-yesterday1", none, ok(missions: [
                row(progress: 60, granted: true, extra: ",\"laps_granted\":3"),
                row(day: "2026-10-29", progress: 9_000, granted: true, extra: ",\"laps_granted\":1"),
            ])),
            ("granted-yesterday-only", none, ok(missions: [
                row(progress: 60),
                row(day: "2026-10-29", progress: 9_000, granted: true, extra: ",\"laps_granted\":1"),
            ])),
            ("granted-old-server-no-laps", none, ok(missions: [row(progress: 10_800, claimed: true, granted: true)])),
            ("claimed-not-granted", none, ok(missions: [row(progress: 10_800, claimed: true)])),
            ("ruby-mission-grant-ignored", none, ok(missions: [row(progress: 600, granted: true, extra: ",\"laps_granted\":2")],
                                                   extra: ",\"ruby_mission_grant\":5,\"ruby_balance\":40")),
            ("unknown-key-granted", none, ok(missions: [row("future_mission", granted: true, extra: ",\"laps_granted\":4")])),
            ("target-zero-today", known, ok(missions: [row(target: 0, progress: 30)])),
            ("target-from-other-day", none, ok(missions: [row(day: "2026-10-29", target: 7_200, progress: 7_000)],
                                              extra: ",\"worked_seconds_closed\":3000,\"worked_seconds_open\":700")),
            ("no-missions-worked", none, ok(extra: ",\"worked_seconds_closed\":3000,\"worked_seconds_open\":700")),
            ("missions-null", known, ok(extra: ",\"missions\":null")),
            ("progress-over-target", none, ok(missions: [row(progress: 12_000, extra: ",\"laps_granted\":1")])),
            ("remaining-exact-hours", none, ok(missions: [row(progress: 3_600)])),
            ("remaining-under-minute", none, ok(missions: [row(progress: 10_741)])),
            ("pending-capped", none, ok(missions: [row(progress: 10_800, extra: ",\"capped\":true,\"pending\":true,\"laps_granted\":1")])),
            ("pending-yesterday-ignored", none, ok(missions: [row(day: "2026-10-29", progress: 10_800, extra: ",\"pending\":true")])),
            ("floor-and-streak", none, ok(extra: ",\"daily_floor\":2,\"floor_applied\":true,\"streak_days\":5,\"streak_includes_today\":true,\"measured_at\":1793000000")),
            ("row-laps-string", known, ok(missions: [row(granted: true, extra: ",\"laps_granted\":\"2\"")])),
            ("row-missing-granted", known, ok(missions: ["{\"key\":\"work3h\",\"kst_day\":\"2026-10-30\",\"target_seconds\":10800,\"progress_seconds\":0,\"claimed\":false}"])),
            ("row-worked-fallback", none, ok(missions: [row(progress: 4_000)])),
            ("streak-string", known, ok(extra: ",\"streak_days\":\"5\"")),
        ]
    }()

    static func missionJSON(_ m: MissionProgress) -> GoldenJSON {
        let progress: GoldenJSON = m.progress.map { GoldenJSON.bits($0) } ?? .null
        let fields: [String: GoldenJSON] = [
            "kind": .string(m.kind.rawValue), "progress": progress, "claimed": .bool(m.claimedToday),
            "capped": .bool(m.cappedToday), "detail": .string(m.detail), "laps": .int(m.lapsGrantedToday), "pending": .bool(m.isPending),
        ]
        return .object(fields)
    }

    @MainActor
    @Test("desktop-ultra/wallet-apply — 디코드 · applyUltraWallet 표")
    func walletApply() throws {
        var cases: [GoldenJSON] = []
        for (id, prior, text) in Self.walletCorpus {
            let store = Self.makeStore("wallet-\(id)")
            store.ultraBalance = prior.balance
            store.ultraBalanceCap = prior.cap
            store.ultraUnlimited = prior.unlimited
            store.ultraBalanceFailed = prior.failed
            store.ultraMissionTargetSeconds = prior.target
            let counter = Counter()
            store.onRewardTrigger = { kind in if kind == .ultraCharged { counter.charged += 1 } }
            var out: [String: GoldenJSON] = ["id": .string(id), "prior": prior.json(), "response": .string(text)]
            do {
                let response = try Self.serviceDecoder().decode(UltraWalletResponse.self, from: Data(text.utf8))
                out["decodeError"] = false
                store.applyUltraWallet(response)
                let after: [String: GoldenJSON] = [
                    "balance": Self.i(store.ultraBalance), "cap": Self.i(store.ultraBalanceCap), "unlimited": .bool(store.ultraUnlimited),
                    "failed": .bool(store.ultraBalanceFailed), "missionsLoaded": .bool(store.missionsLoaded),
                    "missions": .array(store.missions.map(Self.missionJSON)), "streakDays": .int(store.streakDays),
                    "streakIncludesToday": .bool(store.streakIncludesToday), "missionNotice": Self.s(store.missionNotice),
                    "charged": .int(counter.charged), "missionTargetSeconds": Self.i(store.ultraMissionTargetSeconds),
                    "isUnlimited": .bool(response.isUnlimited), "rubyMissionGrant": Self.i(response.rubyMissionGrant),
                ]
                out["after"] = .object(after)
            } catch {
                out["decodeError"] = true
            }
            cases.append(.object(out))
        }
        cases.append([
            "id": "constants",
            "throttleSecondsBits": .bits(WorkTimerStore.ultraWalletSyncThrottleSeconds),
            "defaultTargetSeconds": .int(MissionProgress.defaultTargetSeconds),
            "hoursText": .array([-5, 0, 59, 60, 3_599, 3_600, 3_660, 7_140, 7_200, 10_800, 36_000, 86_399].map { (sec: Int) -> GoldenJSON in
                .object(["seconds": .int(sec), "text": .string(MissionProgress.hoursText(sec))])
            }),
        ])
        goldenEmit(GoldenFile(
            golden: "desktop-ultra/wallet-apply",
            equivalence: .discrete,
            swiftSources: ["Sources/check/WorkTimerStorePoke.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            spec: [
                "response": "ultra_wallet_sync 응답 원문(snake). service.decoder(convertFromSnakeCase)로 디코드 — 실패면 decodeError=true(이때 앱은 잔량을 지우지 않고 failed 만 세운다, U2)",
                "prior": "applyUltraWallet 전에 store 에 넣은 값(잔량·상한·무제한·실패·3시간 목표)",
                "after": "applyUltraWallet 뒤 값. progress 는 Double 비트. charged = onRewardTrigger(.ultraCharged) 횟수(★U3 granted_now 가 유일한 트리거)",
                "rubyMissionGrant": "⚠️ Swift CodingKeys 에 ruby_mission_grant 가 없어 언제나 null — 안내 금액은 3 으로 접힌다(ruby-mission-grant-ignored)",
            ],
            cases: cases
        ))
    }

    // MARK: - focus-stage

    @MainActor
    @Test("desktop-ultra/focus-stage — FocusStagePolicy 표 · 화면 칸 · 기록 키")
    func focusStage() {
        let now = Self.now
        let records: [(String, FocusStageRecord?)] = [
            ("none", nil),
            ("timed-future", FocusStageRecord(stage: .timed, until: now.addingTimeInterval(1))),
            ("timed-now", FocusStageRecord(stage: .timed, until: now)),
            ("timed-past", FocusStageRecord(stage: .timed, until: now.addingTimeInterval(-1))),
            ("timed-100.7", FocusStageRecord(stage: .timed, until: now.addingTimeInterval(100.7))),
            ("timed-0.4", FocusStageRecord(stage: .timed, until: now.addingTimeInterval(0.4))),
            ("timed-3h", FocusStageRecord(stage: .timed, until: now.addingTimeInterval(WorkTimerStore.focusTimedDuration))),
            ("timed-nil", FocusStageRecord(stage: .timed, until: nil)),
            ("always", FocusStageRecord(stage: .always, until: nil)),
            ("always-with-past-until", FocusStageRecord(stage: .always, until: now.addingTimeInterval(-5))),
            ("off", FocusStageRecord(stage: .off, until: nil)),
        ]
        var cases: [GoldenJSON] = []
        for (id, record) in records {
            let store = Self.makeStore("focus-\(id)")
            store.writeFocusStageRecord(record, for: Self.userID)
            store.focusMode = false
            let stageWhenOff = store.focusStage(now: now)
            store.focusMode = true
            let face = store.focusStageFace(now: now)
            let stageWhenOn = store.focusStage(now: now)
            let recordJSON: GoldenJSON = record.map { r -> GoldenJSON in .object(["stage": .string(r.stage.rawValue), "until": Self.d(r.until)]) } ?? .null
            let expired: GoldenJSON = record.map { r -> GoldenJSON in .bool(FocusStagePolicy.isExpired(r, now: now)) } ?? .null
            let row: [String: GoldenJSON] = [
                "id": .string(id),
                "record": recordJSON,
                "now": Self.d(now),
                "stageServerOn": .string(FocusStagePolicy.stage(serverOn: true, record: record, now: now).rawValue),
                "stageServerOff": .string(FocusStagePolicy.stage(serverOn: false, record: record, now: now).rawValue),
                "isExpired": expired,
                "storeStageFocusOff": .string(stageWhenOff.rawValue),
                "storeStageFocusOn": .string(stageWhenOn.rawValue),
                "face": .object(["stage": .string(face.stage.rawValue), "remainingSeconds": Self.i(face.remainingSeconds)]),
            ]
            cases.append(.object(row))
        }
        let userIDs = ["00000000-0000-0000-0000-0000000000AB", "ABCDEF", "already-lower", "TITLE-I-ı-İ", "ÄÖÜ-ẞ", "ΣΑΣ"]
        cases.append([
            "id": "record-keys",
            "keys": .array(userIDs.map { (uid: String) -> GoldenJSON in
                .object(["userID": .string(uid), "key": .string(WorkTimerStore.focusStageRecordKey(userID: uid))])
            }),
        ])
        cases.append([
            "id": "constants",
            "timedDurationBits": .bits(WorkTimerStore.focusTimedDuration),
            "expiryRetryBits": .bits(WorkTimerStore.focusExpiryRetrySeconds),
            "changeFailedNotice": .string(WorkTimerStore.focusModeChangeFailedNotice),
            "stageRaw": .array([FocusStage.off, .timed, .always].map { .string($0.rawValue) }),
        ])
        goldenEmit(GoldenFile(
            golden: "desktop-ultra/focus-stage",
            equivalence: .discrete,
            swiftSources: ["Sources/check/WorkTimerStorePoke.swift"],
            spec: [
                "stageServerOn/Off": "FocusStagePolicy.stage(serverOn:record:now:) — ★F4 서버 켜짐 + 기록 없음 = always",
                "storeStageFocusOff/On": "store.focusStage(now:) — focusMode 가 거짓이면 off(★F8 부수효과 없음)",
                "face": "store.focusStageFace(now:) — timed 일 때만 남은 초(0 쪽으로 자름)",
                "record-keys": "focusStageRecordKey(userID:) — ★F3 사용자별 소문자(로캘 무관)",
            ],
            cases: cases
        ))
    }

    // MARK: - requests

    @MainActor
    @Test("desktop-ultra/requests — 지갑·구매·집중 요청 · buy 응답 · 모자란 루비")
    func requests() async throws {
        let host = "golden-ultra-requests.invalid"
        let store = Self.makeStore("requests", host: host)
        let service = store.service
        _ = try? await service.syncUltraWallet(accessToken: "access-token")
        _ = try? await service.syncUltraWallet(accessToken: "access-token", daysBack: 0)
        _ = try? await service.syncUltraWallet(accessToken: "access-token", daysBack: 7)
        _ = try? await service.buyUltra(accessToken: "access-token", count: 1)
        _ = try? await service.buyUltra(accessToken: "access-token", count: 3)
        try? await service.updateFocusMode(accessToken: "access-token", userID: Self.userID, enabled: true)
        try? await service.updateFocusMode(accessToken: "access-token", userID: Self.userID, enabled: false)
        let labels = ["wallet-default", "wallet-0", "wallet-7", "buy-1", "buy-3", "focus-on", "focus-off"]
        let requests = URLProtocolStub.requests(forHost: host)
        let bodies = URLProtocolStub.bodies(forHost: host)
        #expect(requests.count == labels.count)
        #expect(bodies.count == labels.count)
        var cases: [GoldenJSON] = []
        for (index, label) in labels.enumerated() where index < requests.count && index < bodies.count {
            let request = requests[index]
            let comps = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            let query: [GoldenJSON] = (comps?.queryItems ?? []).map { (item: URLQueryItem) -> GoldenJSON in
                GoldenJSON.array([.string(item.name), Self.s(item.value)])
            }
            cases.append([
                "id": .string(label),
                "method": Self.s(request.httpMethod),
                "path": Self.s(request.url?.path),
                "query": .array(query),
                "prefer": Self.s(request.value(forHTTPHeaderField: "Prefer")),
                "body": .string(bodies[index]),
            ])
        }
        let buyTexts: [(String, String)] = [
            ("buy-ok", "{\"status\":\"ok\",\"ultra_balance\":4,\"ruby_balance\":17,\"unit\":10,\"count\":1}"),
            ("buy-insufficient", "{\"status\":\"insufficient\",\"need\":30,\"have\":12,\"unit\":10,\"count\":3}"),
            ("buy-insufficient-bare", "{\"status\":\"insufficient\"}"),
            ("buy-invalid-max", "{\"status\":\"invalid\",\"max\":10}"),
            ("buy-null-balances", "{\"status\":\"ok\",\"ultra_balance\":null,\"ruby_balance\":null}"),
            ("buy-missing-status", "{\"ultra_balance\":4}"),
            ("buy-ruby-string", "{\"status\":\"ok\",\"ruby_balance\":\"17\"}"),
        ]
        for (id, text) in buyTexts {
            var out: [String: GoldenJSON] = ["id": .string(id), "response": .string(text)]
            if let r = try? Self.serviceDecoder().decode(BuyUltraResponse.self, from: Data(text.utf8)) {
                out["decodeError"] = false
                out["decoded"] = ["status": .string(r.status), "ultraBalance": Self.i(r.ultraBalance), "rubyBalance": Self.i(r.rubyBalance),
                                  "need": Self.i(r.need), "have": Self.i(r.have), "unit": Self.i(r.unit), "count": Self.i(r.count), "max": Self.i(r.max)]
            } else {
                out["decodeError"] = true
            }
            cases.append(.object(out))
        }
        let pairs: [(Int?, Int?)] = [(nil, nil), (30, nil), (nil, 12), (30, 12), (12, 12), (12, 30), (0, 0), (1, 0)]
        cases.append([
            "id": "shortfall",
            "rows": .array(pairs.map { (pair: (Int?, Int?)) -> GoldenJSON in
                .object(["need": Self.i(pair.0), "have": Self.i(pair.1),
                         "text": .string(WorkTimerStore.shortfallNotice(need: pair.0, have: pair.1))])
            }),
        ])
        goldenEmit(GoldenFile(
            golden: "desktop-ultra/requests",
            equivalence: .discrete,
            swiftSources: ["Sources/CheckCore/SupabaseWorkServiceMacOnly.swift", "Sources/CheckCore/SupabaseWorkModels.swift",
                           "Sources/CheckCore/CheckCoreShared.swift"],
            spec: [
                "requests": "URLProtocolStub 이 기록한 요청 — 방법 · 경로 · 쿼리 쌍 · Prefer · 본문 글자(service.encoder, convertToSnakeCase)",
                "buy-*": "buy_ultra 응답 원문 → BuyUltraResponse(합성 디코더 · convertFromSnakeCase). 실패면 decodeError",
                "shortfall": "shortfallNotice(need:have:) — 둘 다 알고 need > have 일 때만 개수",
            ],
            cases: cases
        ))
    }
}
