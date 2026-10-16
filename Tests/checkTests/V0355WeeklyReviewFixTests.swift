import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.55 — 주간 누적 근무 보상(맥) 검토 지적(2026-10-16) 재현 · 고정.
//  ① 잔량: cron 이 먼저 지급해 granted_now 가 빈 흔한 경우에도, 주간 응답이 옮긴 잔량을 그 전에 떠난 상점 조회가 되돌리지 않는다.
//  ② 주 넘김: 월요일 0시(KST)를 넘긴 뒤 첫 조회는 1분 창에 막히지 않는다 · 박자가 없어도 폴링 tick 이 한 번 묻는다 ·
//     경계 뒤 한 번 물었으면(실패해도) 다시 창을 따른다.
//  ③ 그림: 완료 막대는 근무색(진행 중 강조색과 다르다) · 넘긴 단계 표시 · 아이콘 색이 **각각** 그림에 나타난다 —
//     팝오버 전체 그림은 다른 줄의 같은 색에 섞여 하나를 걷어내도 초록이었으므로 이 줄 하나만 그려 색 픽셀을 센다.
// 실네트워크 없음(호스트별 스텁) · 창 없음(ImageRenderer 만).

// MARK: - ① 잔량 — 늦은 상점 조회가 cron 지급분을 되돌리지 않는다

@MainActor
@Suite(.serialized) struct V0355WeeklyRubyRaceTests {
    /// 상점 조회 하나를 먼저 띄우고(서버는 cron 지급 **전** 100 을 읽고 늦게 도착), 그 사이 주간 응답이 150 을 옮긴다.
    /// 두 경우는 granted_now 하나만 다르다(기준선이 다른 대조군).
    static func run(label: String, granted: [(hours: Int, ruby: Int, weekStart: String?)]) async throws -> Int? {
        let host = V0355WeeklyStoreTests.host(label)
        GomokuStubProtocol.register(host: host) { rpc, _, index in
            switch rpc {
            case "shop_state":
                let ruby = index == 0 ? 100 : 150
                return GomokuStubProtocol.Reply(
                    body: #"{"ruby_balance":"# + "\(ruby)" + #","ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":[]}"#,
                    delay: index == 0 ? 0.5 : 0)
            case "weekly_work_status":
                return GomokuStubProtocol.Reply(body: V0355WeeklyStub.json(worked: 41 * 3_600, claimed: [true, true, false],
                                                                          granted: granted, ruby: 150))
            default:
                return nil
            }
        }
        let store = V0355WeeklyStoreTests.store(host: host, label: label, clock: V0355Clock(V0355WeeklyStoreTests.t0))
        store.rubyBalance = 100
        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") == 1 })
        await store.refreshWeeklyWork(reason: .walletCadence)?.value
        #expect(store.rubyBalance == 150, "주간 응답이 잔량을 안 옮겼다")
        // 늦은 상점 조회(0.5초)가 도착하고, 버려졌으면 다시 읽기까지 끝날 때를 기다린다.
        try? await Task.sleep(for: .milliseconds(700))
        _ = await V0354CoreStub.waitUntil { !store.shopLoading }
        return store.rubyBalance
    }

    @Test("대조군: 이 호출이 지급(granted_now 있음) → 늦은 상점 조회는 버려지고 다시 읽어 150")
    func grantedNowControl() async throws {
        #expect(try await Self.run(label: "race-granted", granted: [(40, 50, nil)]) == 150)
    }

    @Test("cron 이 지급(granted_now 빈 배열 — 흔한 경우) → 늦은 상점 조회(cron 전 100)가 150 을 되돌리지 않는다")
    func cronPaidLateShopReadDoesNotRevert() async throws {
        let final = try await Self.run(label: "race-cron", granted: [])
        #expect(final == 150, "늦게 온 상점 조회(cron 지급 전 100)가 주간 응답의 새 잔량(150)을 덮었다 → \(String(describing: final))")
    }
}

// MARK: - ② 주 넘김(월요일 0시 KST)

@MainActor
@Suite(.serialized) struct V0355WeeklyRolloverTests {
    /// 일요일 2026-10-18 23:59:30 KST.
    static let sunday = Date(timeIntervalSince1970: 1_792_335_570)

    nonisolated static func lastWeek() -> GomokuStubProtocol.Reply {
        .init(body: V0355WeeklyStub.json(worked: 61 * 3_600, claimed: [true, true, true]))
    }

    nonisolated static func newWeek() -> GomokuStubProtocol.Reply {
        .init(body: V0355WeeklyStub.json(worked: 10, weekStart: "2026-10-19", nextWeekStart: "2026-10-26"))
    }

    @Test("기준 시각이 정말 일요일 23:59:30 KST 다(아래 테스트의 전제)")
    func fixtureIsSundayBeforeMidnight() throws {
        let monday = try #require(WeeklyWorkCalendar.kstMidnight("2026-10-19"))
        #expect(monday.timeIntervalSince(Self.sunday) == 30)
    }

    @Test("월요일 00:00:10 에 패널을 열면 1분 창 안이어도 다시 묻는다 — 지난주 '완료 · +270' 줄을 새 주에 남기지 않는다")
    func panelOpenAfterMidnightBypassesTheGate() async throws {
        let host = V0355WeeklyStoreTests.host("roll-panel")
        V0355WeeklyStoreTests.register(host: host) { $0 == 0 ? Self.lastWeek() : Self.newWeek() }
        let clock = V0355Clock(Self.sunday)
        let store = V0355WeeklyStoreTests.store(host: host, label: "roll-panel", clock: clock)
        await store.refreshWeeklyWork(reason: .walletCadence)?.value
        #expect(store.weeklyWork?.weekStart == "2026-10-12")

        // 대조군: 같은 주 안(일요일 23:59:50)이면 1분 창이 막는다.
        clock.advance(20)
        #expect(store.refreshWeeklyWork(reason: .walletCadence) == nil)

        clock.advance(20)   // 월요일 00:00:10 KST
        store.syncUltraWallet(reason: .panelOpen)
        #expect(await V0354CoreStub.waitUntil { V0355WeeklyStoreTests.count(host) == 2 && store.weeklyWork?.weekStart == "2026-10-19" },
                "월요일인데 지난주 줄을 그린다(요청 \(V0355WeeklyStoreTests.count(host))건 · 주 \(store.weeklyWork?.weekStart ?? "-"))")
        // 경계 뒤에 한 번 물었으니 다시 창을 따른다.
        clock.advance(5)
        #expect(store.refreshWeeklyWork(reason: .walletCadence) == nil)
    }

    @Test("박자가 없어도(패널만 열어 둔 비근무) 폴링 tick 이 경계 뒤 한 번 묻는다 · 그 조회가 실패해도 매 tick 두드리지 않는다")
    func tickRefetchesOnceAfterMidnight() async throws {
        let host = V0355WeeklyStoreTests.host("roll-tick")
        V0355WeeklyStoreTests.register(host: host) { index in
            switch index {
            case 0: return Self.lastWeek()
            case 1: return .init(status: 503, body: #"{"message":"down"}"#)
            default: return Self.newWeek()
            }
        }
        let clock = V0355Clock(Self.sunday)
        let store = V0355WeeklyStoreTests.store(host: host, label: "roll-tick", clock: clock)
        await store.refreshWeeklyWork(reason: .walletCadence)?.value

        // 같은 주의 tick 은 요청 0건(빚도 없다).
        clock.advance(10)
        await store.localExpiryTick()
        await V0355WeeklyStoreTests.settle()
        #expect(V0355WeeklyStoreTests.count(host) == 1)

        clock.advance(30)   // 월요일 00:00:10 KST — 마지막 조회(일요일 23:59:30)에서 40초, 창 안
        await store.localExpiryTick()
        #expect(await V0354CoreStub.waitUntil { V0355WeeklyStoreTests.count(host) == 2 }, "월요일 첫 tick 이 묻지 않았다")
        await V0355WeeklyStoreTests.settle()
        #expect(store.weeklyWork?.weekStart == "2026-10-12", "실패한 조회가 알던 줄을 지웠다")

        // 실패했어도 경계 뒤에 물었으니 다음 tick 들은 창을 따른다(서버가 죽은 동안 매 tick 두드리지 않는다).
        for _ in 0..<3 {
            clock.advance(5)
            await store.localExpiryTick()
        }
        await V0355WeeklyStoreTests.settle()
        #expect(V0355WeeklyStoreTests.count(host) == 2, "실패 뒤 매 tick 다시 물었다(\(V0355WeeklyStoreTests.count(host))건)")

        // 1분이 지난 박자는 다시 묻고 새 주가 선다.
        clock.advance(60)
        store.syncUltraWallet(reason: .panelOpen)
        #expect(await V0354CoreStub.waitUntil { store.weeklyWork?.weekStart == "2026-10-19" })
    }

    @Test("경계 판정(코어): 경계가 마지막 조회 뒤 · 지금 이전일 때만 참 — 모르는 주 · 경계 전 · 경계 뒤 조회는 거짓")
    func weekEndedPredicate() throws {
        let status = V0355WeeklyStub.status(worked: 0)   // next_week_start 2026-10-19
        let boundary = try #require(status.nextWeekStartDate)
        #expect(status.weekEnded(after: boundary.addingTimeInterval(-30), by: boundary))
        #expect(status.weekEnded(after: boundary.addingTimeInterval(-30), by: boundary.addingTimeInterval(10)))
        #expect(!status.weekEnded(after: boundary.addingTimeInterval(-30), by: boundary.addingTimeInterval(-1)))
        #expect(!status.weekEnded(after: boundary, by: boundary.addingTimeInterval(10)), "경계 뒤에 물었는데 또 건너뛴다")
        #expect(status.hasEnded(at: boundary) && !status.hasEnded(at: boundary.addingTimeInterval(-1)))
        #expect(!WeeklyWorkStatus(workedSeconds: 1).weekEnded(after: .distantPast, by: .distantFuture), "주를 모르는데 넘었다고 한다")
    }
}

// MARK: - ③ 그림 — 주간 줄 하나만 그려 색을 센다

@MainActor
@Suite(.serialized) struct V0355WeeklyRowColorTests {
    struct Tally: Equatable {
        var working = 0
        var accent = 0
    }

    /// 줄 하나(팝오버 본문 열 폭 292)를 굳혀 그린다. 창은 띄우지 않는다.
    static func bitmap(_ status: WeeklyWorkStatus) throws -> NSBitmapImageRep {
        try #require(CheckRenderSettle.bitmap(WeeklyWorkRowView(status: status).frame(width: 292).fixedSize(), scale: 2))
    }

    /// 색 하나를 같은 렌더러로 칠한 견본의 가운데 픽셀(RGB 바이트) — 줄 그림과 같은 색 공간 · 같은 반올림으로 비교하려고.
    static func reference(_ color: Color) throws -> [Int] {
        let rep = try #require(CheckRenderSettle.bitmap(Rectangle().fill(color).frame(width: 12, height: 12), scale: 2))
        var pixel = [Int](repeating: 0, count: max(4, rep.samplesPerPixel))
        rep.getPixel(&pixel, atX: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)
        return Array(pixel.prefix(3))
    }

    /// 근무색 · 강조색 **그 색 그대로**(채널마다 ±6)인 픽셀 수. 막대 · 아이콘 · 체크 · 칩 글자의 속처럼 그 색으로 칠한 것만 센다 —
    /// 옅은 칩 바탕(색 16%) · 회색 글자 · 💎 그림 문자(파랗지만 강조색이 아니다)는 세지 않는다.
    static func tally(_ rep: NSBitmapImageRep) throws -> Tally {
        let working = try reference(CheckTheme.working)
        let accent = try reference(CheckTheme.accent)
        func near(_ p: [Int], _ ref: [Int]) -> Bool { zip(p, ref).allSatisfy { abs($0 - $1) <= 6 } }
        var result = Tally()
        var pixel = [Int](repeating: 0, count: max(4, rep.samplesPerPixel))
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                rep.getPixel(&pixel, atX: x, y: y)
                let rgb = Array(pixel.prefix(3))
                if near(rgb, working) { result.working += 1 }
                if near(rgb, accent) { result.accent += 1 }
            }
        }
        return result
    }

    static func status(_ worked: Int, _ claimed: [Bool]) -> WeeklyWorkStatus {
        V0355WeeklyStub.status(worked: worked, claimed: claimed)
    }

    @Test("완료(60시간+) 막대는 근무색 — 완료 줄엔 강조색이 거의 없고 근무색 막대가 선다 · 59:59:59 줄은 강조색 막대(대조군)")
    func completedBarUsesTheDoneColour() throws {
        let h = V0355WeeklyStub.hour
        let done = try Self.tally(try Self.bitmap(Self.status(60 * h, [true, true, true])))
        let almost = try Self.tally(try Self.bitmap(Self.status(60 * h - 1, [true, true, false])))
        // 실측(2x): 완료 근무색 5222 · 강조색 2(💎 가장자리) / 59:59:59 근무색 612 · 강조색 4060 — 막대 하나가 약 3500 픽셀이다.
        #expect(almost.accent > 2_000, "대조군: 진행 중 막대(강조색)가 안 잡힌다 — 세는 법이 헛돈다(\(almost))")
        #expect(done.accent < 50, "완료 줄에 강조색이 \(done.accent)픽셀 — 완료 막대가 진행 중 색이다")
        #expect(done.working > almost.working + 2_000,
                "완료 줄의 근무색이 \(done.working)픽셀(진행 중 \(almost.working)) — 가득 찬 근무색 막대가 없다")
    }

    @Test("넘긴 단계 표시가 그림에 나타난다 — 45시간에서 40 을 받음 vs 장부 아직(아이콘 · 제목 · 막대 · 칩은 같다)")
    func passedTierMarksAreDrawn() throws {
        let h = V0355WeeklyStub.hour
        let pending = try Self.bitmap(Self.status(45 * h, [true, false, false]))
        let paid = try Self.bitmap(Self.status(45 * h, [true, true, false]))
        // 같은 퀘스트(60) · 같은 막대 · 같은 칩 — 다른 것은 "40" 표시뿐이다.
        #expect(WeeklyWorkCopy.title(try #require(Self.status(45 * h, [true, false, false]).gauge))
                == WeeklyWorkCopy.title(try #require(Self.status(45 * h, [true, true, false]).gauge)))
        #expect(pending.representation(using: .png, properties: [:]) != paid.representation(using: .png, properties: [:]),
                "받은 40 과 장부가 아직인 40 이 같은 그림이다 — 넘긴 단계 표시가 없다")
        let a = try Self.tally(pending), b = try Self.tally(paid)
        #expect(b.working > a.working, "받은 40 표시(체크 + 근무색)가 근무색 픽셀을 늘리지 않는다(\(a) → \(b))")
        #expect(a.accent == b.accent, "단계 표시 말고 다른 것(막대 · 칩)이 바뀌었다(\(a) → \(b))")
    }

    @Test("아이콘 색이 그림에 나타난다 — 넘긴 단계가 없는 10시간에서 받은 단계 유무만 다르면 아이콘만 근무색 ↔ 강조색")
    func iconTintIsDrawn() throws {
        let h = V0355WeeklyStub.hour
        // 10시간이면 넘긴 단계가 없어 표시가 하나도 없다 — 아이콘만 갈린다(장부엔 20 이 있어도: 자리비움 소급 마감 뒤의 모양).
        let pending = try Self.tally(try Self.bitmap(Self.status(10 * h, [false, false, false])))
        let paid = try Self.tally(try Self.bitmap(Self.status(10 * h, [true, false, false])))
        #expect(paid.working > pending.working, "받은 단계가 있는데 아이콘이 근무색이 아니다(\(pending) → \(paid))")
        #expect(pending.accent > paid.accent, "받은 단계가 없는데 아이콘이 강조색이 아니다(\(pending) → \(paid))")
    }
}
