@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 팀 리그 **지난 6주 보기**(v0.3.37) — 주 상태 기계·늦은 응답·롤오버·옛 서버 폴백·문구·모양 계약.
///
/// 파일을 `RankingsStoreTests` 와 나눈 이유: 같은 파도에서 다른 에이전트가 그 파일을 고칠 수 있다.
/// 스텁 호스트 이름도 `rank-week-*` 로 따로 짓는다 — **호스트가 겹치면 요청 카운터를 공유해** 병렬 실행에서 서로를 깨뜨린다.
@MainActor
@Suite("팀 리그 지난 6주 보기(rank-week)")
struct RankingsLeagueWeekTests {
    // MARK: 시계

    /// 2026-09-24 14:05 KST(목). 이번 주 월요일 = 2026-09-21 → 한 주 과거가 **9월 14일 주**(확정 문구의 예시와 같은 주).
    static let thursday = ISO8601DateFormatter().date(from: "2026-09-24T05:05:00Z")!
    /// 2026-09-20 23:59 KST(일). 여기서 120초만 지나면 주가 넘어간다(월요일 0시 롤오버 창).
    static let sundayLate = ISO8601DateFormatter().date(from: "2026-09-20T14:59:00Z")!

    static func weekKey(_ offset: Int, now: Date) -> String {
        TeamLeagueWeekNavigator.key(offset: offset, now: now)
    }

    // MARK: 응답 모양

    /// 새 서버 행 두 개(내 팀 + 다른 팀). `weekStart` 가 있으면 행이 스스로 과거를 말한다.
    nonisolated static func leagueJSON(weekStart: String?, participants: Int? = 4) -> String {
        func row(_ id: String, _ name: String, _ total: Int, _ working: Int) -> String {
            var fields = [
                #""team_id":"\#(id)""#, #""team_name":"\#(name)""#, #""weekly_goal_hours":40"#,
                #""total_seconds":\#(total)"#, #""working_count":\#(working)"#, #""member_count":5"#, #""center":null"#,
            ]
            if let weekStart { fields.append(#""week_start":"\#(weekStart)""#) }
            if let participants { fields.append(#""participant_count":\#(participants)"#) }
            return "{" + fields.joined(separator: ",") + "}"
        }
        return "[\(row("t-high", "높은팀", 288_000, 2)),\(row(RankMeFixture.teamID, "테스트팀", 36_000, 0))]"
    }

    /// 요청 본문의 `p_week_offset` 을 그대로 읽어 그 주의 행을 준다(서버 시늉).
    nonisolated static func answer(_ request: MobileStubRequest, now: Date) -> MobileStubResponse {
        let offset = request.jsonBody["p_week_offset"] as? Int ?? 0
        return .json(leagueJSON(weekStart: TeamLeagueWeekNavigator.key(offset: offset, now: now)))
    }

    static func offsets(_ harness: RankMeHarness) -> [Int] {
        harness.requests(rpc: "team_weekly_leaderboard").map { $0.jsonBody["p_week_offset"] as? Int ?? -1 }
    }

    // MARK: 1. 주 이동

    @Test("rank-week-step: ◂ 가 오프셋 1→2 로 나간다 · 이번 주 ▸ 와 6주 전 ◂ 는 요청 0건 · 제목이 주를 말한다")
    func stepsWeeks() async throws {
        let now = Self.thursday
        let harness = await RankMeHarness(label: "rank-week-step", clockStart: now) { request in
            request.rpcName == "team_weekly_leaderboard" ? Self.answer(request, now: now) : nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })
        #expect(store.leagueWeekKey == Self.weekKey(0, now: now))
        #expect(store.leagueTitle == "팀별 이번 주", "이번 주 제목은 한 글자도 안 바뀐다")
        #expect(!store.isLeaguePastWeek && !store.canStepLeagueWeekForward && store.canStepLeagueWeekBack)
        #expect(Self.offsets(harness) == [0], "오프셋 0 도 본문에 실려 나간다(의도된 설계)")

        // 이번 주에서 ▸ — 값이 안 바뀌면 요청도 없다.
        store.stepLeagueWeek(by: 1)
        await harness.barrier()
        #expect(Self.offsets(harness) == [0])

        store.stepLeagueWeek(by: -1)
        #expect(store.league.isEmpty, "옮기는 순간 직전 주 행을 비운다")
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && store.leagueWeekKey == Self.weekKey(1, now: now) })
        #expect(store.leagueTitle == "팀별 9월 14일 주")
        #expect(store.leagueWeekName == "9월 14일 주")
        #expect(store.isLeaguePastWeek && store.canStepLeagueWeekForward)
        #expect(store.leagueDisplay.allSatisfy { $0.isPastWeek(now: now) }, "행이 스스로 과거를 말한다")

        store.stepLeagueWeek(by: -1)
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && store.leagueWeekKey == Self.weekKey(2, now: now) })
        #expect(Self.offsets(harness) == [0, 1, 2])

        // 6주 전까지 내려가면 ◂ 가 막힌다(서버가 접는 값과 같은 눈금).
        for _ in 0..<4 {
            store.stepLeagueWeek(by: -1)
            #expect(await baseWaitUntil { store.leagueState.hasLoaded })
        }
        #expect(store.leagueWeekKey == Self.weekKey(6, now: now))
        #expect(!store.canStepLeagueWeekBack)
        let atFloor = Self.offsets(harness)
        store.stepLeagueWeek(by: -1)
        await harness.barrier()
        #expect(Self.offsets(harness) == atFloor, "6주 전에서 ◂ 가 또 물었다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: 2. 늦은 응답

    @Test("rank-week-late: 과거 주 응답이 늦게 와도 이번 주로 돌아온 화면을 덮지 않는다 · '불러오는 중'이 안 남는다")
    func lateWeekResponseIsDropped() async throws {
        let now = Self.thursday
        let harness = await RankMeHarness(label: "rank-week-late", clockStart: now) { request in
            request.rpcName == "team_weekly_leaderboard" ? Self.answer(request, now: now) : nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        let current = Self.weekKey(0, now: now)

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })

        let held = BaseHold.rpc("team_weekly_leaderboard", host: harness.host)
        store.stepLeagueWeek(by: -1)
        #expect(await held.waitHeld())
        // 기다리는 사이 ▸ 로 이번 주 복귀 — 이 조회는 붙잡히지 않는다(limit 1).
        store.stepLeagueWeek(by: 1)
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && store.leagueWeekKey == current })
        #expect(await held.releaseAndWaitDelivered())
        await harness.barrier()

        #expect(store.leagueWeekKey == current)
        #expect(store.league.first?.weekStart == current, "늦게 온 과거 주 행이 이번 주 화면을 덮었다")
        #expect(!store.isLeaguePastWeek)
        #expect(!store.leagueState.isLoading, "'불러오는 중'이 남았다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: 3. 주 롤오버

    @Test("rank-week-roll: 열어 둔 채 월요일 0시를 넘기면 이번 주로 스냅한다 · 두 번 스냅하지 않는다")
    func rollsToCurrentWeek() async throws {
        let start = Self.sundayLate
        let clockBox = BaseLockedBox(start)
        let harness = await RankMeHarness(label: "rank-week-roll", clockStart: start) { request in
            request.rpcName == "team_weekly_leaderboard" ? Self.answer(request, now: clockBox.get()) : nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })
        store.stepLeagueWeek(by: -1)
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && store.isLeaguePastWeek })
        let beforeRoll = Self.offsets(harness)
        #expect(beforeRoll == [0, 1])

        // 월요일 0시를 넘긴다(23:59 → 00:01).
        harness.clock.advance(120)
        clockBox.mutate { $0 = start.addingTimeInterval(120) }
        let newCurrent = Self.weekKey(0, now: clockBox.get())
        #expect(newCurrent != Self.weekKey(0, now: start), "시계가 주를 안 넘겼다 — 이 테스트가 무의미해진다")

        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && store.leagueWeekKey == newCurrent })
        #expect(!store.isLeaguePastWeek)
        #expect(Self.offsets(harness) == [0, 1, 0], "스냅 뒤 이번 주(오프셋 0)를 물어야 한다")

        // 앵커가 다시 맞춰졌으니 두 번째 복귀는 스냅도 요청도 내지 않는다.
        store.appDidBecomeActive()
        await harness.barrier()
        #expect(Self.offsets(harness) == [0, 1, 0], "앵커를 못 맞춰 두 번 스냅했다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: 4. 문(door) 넷

    @Test("rank-week-doors: 탭 재진입 · 보드 전환 · 딥링크는 이번 주로 떨어진다 · 이번 주 재진입은 행을 안 비운다")
    func doorsFallToCurrentWeek() async throws {
        let now = Self.thursday
        let harness = await RankMeHarness(label: "rank-week-doors", clockStart: now) { request in
            request.rpcName == "team_weekly_leaderboard" ? Self.answer(request, now: now) : nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        let current = Self.weekKey(0, now: now)

        func goPast() async {
            store.stepLeagueWeek(by: -1)
            #expect(await baseWaitUntil { store.leagueState.hasLoaded && store.isLeaguePastWeek })
        }

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })

        // ① 탭 재진입
        await goPast()
        store.tabDidDisappear()
        store.tabDidAppear()
        #expect(store.leagueWeekKey == current, "탭을 다시 열었는데 과거 주가 따라왔다")
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })

        // ② 보드 전환(리그 → 토큰 → 리그)
        await goPast()
        store.select(board: .tokens)
        store.select(board: .league)
        #expect(store.leagueWeekKey == current, "보드를 갈아탔는데 과거 주가 살아 있다")
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })

        // ③ 딥링크(이미 리그인 채로 다시 열기도 명시적 '리그를 열어라')
        await goPast()
        store.open(.rankings(.league))
        #expect(store.leagueWeekKey == current, "딥링크가 과거 주를 그대로 뒀다")
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && !store.league.isEmpty })

        // ④ 이번 주에서 다시 열면 행이 비지 않는다(깜빡임 회귀).
        let before = Self.offsets(harness).count
        store.tabDidDisappear()
        store.tabDidAppear()
        #expect(!store.league.isEmpty, "이번 주 재진입이 행을 비웠다 — 목록이 한 번 깜빡인다")
        await harness.barrier()
        #expect(Self.offsets(harness).count == before, "신선한 이번 주를 다시 물었다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: 5. 옛 서버

    @Test("rank-week-legacy: PGRST202 → {} 폴백은 이번 주 표를 살린다 · 능력 깃발을 기억하지 않는다")
    func legacyServerFallback() async throws {
        let now = Self.thursday
        let legacy = BaseLockedBox(true)
        let harness = await RankMeHarness(label: "rank-week-legacy", clockStart: now) { request in
            guard request.rpcName == "team_weekly_leaderboard" else { return nil }
            let hasOffset = request.bodyText.contains("p_week_offset")
            if legacy.get() {
                // 옛 서버: 인자를 아는 함수가 없다. 폴백(`{}`)에는 week_start·participant_count 자체가 없다.
                if hasOffset { return .missingFunction("team_weekly_leaderboard") }
                return .json(Self.leagueJSON(weekStart: nil, participants: nil))
            }
            return Self.answer(request, now: now)
        }
        defer { harness.tearDown() }
        let store = harness.rankings

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })
        #expect(!store.leagueWeekOffsetSupported)
        #expect(!store.showsLeagueWeekNavigation, "옛 서버에서는 주 이동 알약을 그리지 않는다")
        #expect(store.leagueWeekKey == Self.weekKey(0, now: now))
        #expect(!store.league.isEmpty, "폴백으로 받은 이번 주 표를 버렸다")
        #expect(!store.isLeaguePastWeek)
        #expect(harness.requests(rpc: "team_weekly_leaderboard").count == 2, "404 한 번 + {} 한 번, 그 이상은 내지 않는다")

        // 알약이 접힌 동안에는 주 이동 자체가 막힌다.
        store.stepLeagueWeek(by: -1)
        await harness.barrier()
        #expect(harness.requests(rpc: "team_weekly_leaderboard").count == 2)

        // db push 가 끝났다 — 다음 조회에서 **다시** 판정한다(기억하지 않는다).
        legacy.mutate { $0 = false }
        await store.loadLeague()
        #expect(store.leagueWeekOffsetSupported && store.showsLeagueWeekNavigation)
        #expect(harness.requests(rpc: "team_weekly_leaderboard").count == 3)
        harness.expectNoForbiddenCalls()
    }

    // MARK: 6. 과거 주는 조용하다

    @Test("rank-week-quiet: 과거 주는 주기 갱신을 돌리지 않는다 · 단 실패한 과거 주는 다시 읽는다(MU5)")
    func pastWeekDoesNotPoll() async throws {
        let now = Self.thursday
        let fail = BaseLockedBox(false)
        let harness = await RankMeHarness(label: "rank-week-quiet", clockStart: now) { request in
            guard request.rpcName == "team_weekly_leaderboard" else { return nil }
            if fail.get() { return .json(#"{"message":"boom"}"#, status: 500) }
            return Self.answer(request, now: now)
        }
        defer { harness.tearDown() }
        let store = harness.rankings

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })
        store.stepLeagueWeek(by: -1)
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && store.isLeaguePastWeek })
        let quiet = Self.offsets(harness).count

        harness.clock.advance(RankingsStore.staleSeconds + 1)
        store.appDidBecomeActive()
        await harness.barrier()
        #expect(Self.offsets(harness).count == quiet, "끝난 주를 30초마다 다시 물었다")

        // 그 과거 주 조회가 실패했다면 '안 변한다'로 접으면 안 된다(빈 표가 과거 사실로 읽힌다).
        fail.mutate { $0 = true }
        await store.refresh()
        #expect(store.leagueState.hasFailed)
        let afterFail = Self.offsets(harness).count
        fail.mutate { $0 = false }
        harness.clock.advance(RankingsStore.staleSeconds + 1)
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { Self.offsets(harness).count == afterFail + 1 }, "실패한 과거 주를 다시 읽지 않았다")
        #expect(await baseWaitUntil { !store.leagueState.hasFailed && store.isLeaguePastWeek })
        harness.expectNoForbiddenCalls()
    }

    // MARK: 7. 서버가 답한 주를 따른다

    @Test("rank-week-server-says: 서버가 다른 week_start 를 주면 제목이 그 주로 옮겨가고 '불러오는 중'이 안 남는다")
    func adoptsServerWeek() async throws {
        let now = Self.thursday
        let served = Self.weekKey(2, now: now)
        let harness = await RankMeHarness(label: "rank-week-says", clockStart: now) { request in
            request.rpcName == "team_weekly_leaderboard" ? .json(Self.leagueJSON(weekStart: served)) : nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })
        await harness.barrier()
        #expect(store.leagueWeekKey == served, "서버가 답한 주를 안 따랐다 — 제목이 거짓말을 한다")
        #expect(store.leagueTitle == "팀별 \(TeamLeagueWeekNavigator.displayTitle(served, now: now))")
        #expect(store.isLeaguePastWeek)
        #expect(!store.leagueState.isLoading, "'불러오는 중'이 남았다(defer 에 주 키를 넣으면 이 단언이 깨진다)")
        harness.expectNoForbiddenCalls()
    }

    // MARK: 8. 순수 문구

    static func team(
        id: String = "t",
        total: Int = 51 * 3600 + 12 * 60,   // 총 51시간 12분(맥 캡션 예시와 같은 숫자)
        members: Int = 5,
        working: Int = 3,
        weekStart: String? = nil,
        participants: Int? = 4
    ) -> TeamLeaderboardEntry {
        TeamLeaderboardEntry(
            id: id, name: "팀", weeklyGoalHours: 40, totalSeconds: total, workingCount: working,
            memberCount: members, center: nil, weekStart: weekStart, participantCount: participants
        )
    }

    @Test("문구: 참여 인원 · 보조 줄 우선순위 · 과거 주 빈 목록 네 갈림 · 캡션/부제에서 '근무중' 조각이 사라진다")
    func pastWeekTexts() {
        let now = Self.thursday
        let past = Self.weekKey(1, now: now)

        // 참여 인원(맥 CheckComponents.swift:404-405 와 글자 동일).
        #expect(RankingsText.leagueParticipation(Self.team(weekStart: past)) == "5명 중 4명 참여")
        #expect(RankingsText.leagueParticipation(Self.team(weekStart: past, participants: nil)) == "5명 중 참여 인원 모름")

        // 보조 줄: 이번 주는 없고, 과거 주는 한 줄만. 내 팀이 없으면 그 답이 먼저다.
        #expect(RankingsText.leagueWeekNote(isPastWeek: false, myTeamMissing: false) == nil)
        #expect(RankingsText.leagueWeekNote(isPastWeek: false, myTeamMissing: true) == nil)
        #expect(RankingsText.leagueWeekNote(isPastWeek: true, myTeamMissing: false) == "인원은 그 주 기준이에요")
        #expect(RankingsText.leagueWeekNote(isPastWeek: true, myTeamMissing: true) == "그 주엔 아직 우리 팀이 없었어요")

        // 빈 목록 — 과거 주의 '사실 주장' 문장은 hasLoaded 일 때만.
        #expect(RankingsText.leagueEmpty(hasLoaded: false, isLoading: true, hasFailed: false, unfilteredCount: 0, isPastWeek: true) == "불러오는 중…")
        #expect(RankingsText.leagueEmpty(hasLoaded: false, isLoading: false, hasFailed: true, unfilteredCount: 0, isPastWeek: true) == "순위를 불러오지 못했어요")
        #expect(RankingsText.leagueEmpty(hasLoaded: false, isLoading: false, hasFailed: false, unfilteredCount: 0, isPastWeek: true) == "불러오는 중…",
                "취소된 조회가 '그 주엔 근무한 팀이 없었어요'로 둔갑했다")
        #expect(RankingsText.leagueEmpty(hasLoaded: true, isLoading: false, hasFailed: false, unfilteredCount: 0, isPastWeek: true) == "그 주엔 근무한 팀이 없었어요")
        // 이번 주 갈림은 한 글자도 안 바뀐다.
        #expect(RankingsText.leagueEmpty(hasLoaded: true, isLoading: false, hasFailed: false, unfilteredCount: 3) == "아직 이번 주 근무한 팀이 없어요")
        #expect(RankingsText.leagueEmpty(hasLoaded: false, isLoading: false, hasFailed: true, unfilteredCount: 0) == "리그를 불러오지 못했어요")
        #expect(RankingsText.leagueFailedText(isPastWeek: true) == "순위를 불러오지 못했어요")
        #expect(RankingsText.leagueFailedText(isPastWeek: false) == "리그를 불러오지 못했어요")

        // 캡션·부제 — 과거 주에서 '근무중' 조각이 통째로 빠진다.
        let pastTeam = Self.team(weekStart: past)
        #expect(RankingsText.leagueCaption(pastTeam, now: now) == "각자 목표 40시간 · 총 51시간 12분 · 5명 중 4명 참여")
        #expect(RankingsText.leagueSubtitle(pastTeam, now: now) == "5명 중 4명 참여 · 목표 40시간")
        let pieces = RankingsText.leagueSubtitle(pastTeam, now: now).components(separatedBy: " · ")
        #expect(pieces.count == 2, "과거 주 부제 조각은 둘이다")
        #expect(!RankingsText.leagueSubtitle(pastTeam, now: now).contains("근무"), "과거 주에 '근무 중' 조각이 되살아났다")
        #expect(!RankingsText.leagueCaption(pastTeam, now: now).contains("근무중"))
        // 값이 0 인지가 아니라 **주 판정으로** 끊는다 — workingCount 가 새어 들어와도 조각이 살아나면 안 된다.
        #expect(!RankingsText.leagueSubtitle(Self.team(weekStart: past, participants: nil), now: now).contains("근무"))
        #expect(RankingsText.leagueRowAccessibility(rank: 2, entry: pastTeam, isMyTeam: false, now: now).contains("5명 중 4명 참여"))
        #expect(!RankingsText.leagueRowAccessibility(rank: 2, entry: pastTeam, isMyTeam: false, now: now).contains("주"),
                "행 라벨에 주 이름이 들어갔다 — 6행이 같은 말을 여섯 번 한다")

        // 이번 주 행(weekStart 가 이번 주이거나 nil)은 예전 문장 그대로.
        let thisWeek = Self.team(weekStart: Self.weekKey(0, now: now))
        #expect(RankingsText.leagueSubtitle(thisWeek, now: now) == "5명 · 3명 근무 중 · 목표 40시간")
        #expect(RankingsText.leagueCaption(Self.team(weekStart: nil), now: now) == "각자 목표 40시간 · 총 51시간 12분 · 5명 · 3명 근무중",
                "구버전 RPC(week_start 없음)는 이번 주로 읽는다")

        // 제목.
        #expect(RankingsText.leagueTitle(week: Self.weekKey(0, now: now), now: now) == "팀별 이번 주")
        #expect(RankingsText.leagueTitle(week: past, now: now) == "팀별 9월 14일 주")
        #expect(RankingsText.leagueWeekName(week: past, now: now) == "9월 14일 주")
        #expect(RankingsText.leagueAverageHint == "1인당 평균")
        #expect(RankingsText.previousWeek == "이전 주" && RankingsText.nextWeek == "다음 주")
        #expect(RankingsText.noEarlierWeek == "6주 전까지만 볼 수 있어요")
        #expect(RankingsText.noLaterWeek == "이번 주가 가장 최근이에요")
        #expect(RankingsText.noLaterMonth == "이번 달이 가장 최근이에요")
        // 보드 머리 부제는 과거 주에도 그대로다(토큰 판이 지난 달을 보면서도 "이번 달 · 1일에…"를 유지하는 관례).
        #expect(RankingsText.boardSubtitle(.league) == "이번 주 · 월요일 0시에 새로 시작해요")
    }

    @Test("표시 목록: 0시간 타팀만 숨기고 내 팀은 남긴다 · myTeamMissing 은 필터 전 원본에서만 센다")
    func displayPageFacts() {
        let past = Self.weekKey(1, now: Self.thursday)
        let rows = [
            Self.team(id: "t-high", total: 288_000, weekStart: past),
            Self.team(id: "mine", total: 0, weekStart: past),
            Self.team(id: "t-zero", total: 0, weekStart: past),
        ]
        let page = rows.leagueDisplay(myTeamID: "mine")
        #expect(page.entries.map(\.id) == ["t-high", "mine"])
        #expect(page.unfilteredCount == 3)
        #expect(!page.myTeamMissing)
        #expect(rows.leagueDisplay(myTeamID: "gone").myTeamMissing, "그 주엔 아직 우리 팀이 없었다")
        #expect(![TeamLeaderboardEntry]().leagueDisplay(myTeamID: "mine").myTeamMissing,
                "로드 전/실패(원본 0건)를 '그 주엔 팀이 없었다'로 읽으면 안 된다")
    }

    // MARK: 9. 모양 계약 (폰 뷰는 macOS 에서 컴파일되지 않아 소스 글자로 잰다)

    @Test("모양 계약: 머리 오른쪽은 주 이동 알약 · 힌트는 메타 줄 · 달 호출부 무변경 · 막힌 사유와 값 변화 알림")
    func viewContracts() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift")

        // ① 리그 머리 trailing = 주 이동 알약, "1인당 평균" 힌트는 머리 밖(메타 줄).
        #expect(code.contains("RankingsSectionHeader(title: store.leagueTitle)"))
        #expect(code.contains("RankingsPeriodStepper(\n                        unit: .week,"))
        let headerStart = try #require(code.range(of: "RankingsSectionHeader(title: store.leagueTitle)"))
        let metaStart = try #require(code.range(of: "metaLine(note:"))
        let hint = try #require(code.range(of: "RankingsText.leagueAverageHint"))
        #expect(hint.lowerBound > metaStart.lowerBound && metaStart.lowerBound > headerStart.lowerBound,
                "힌트가 머리 안에 남아 알약을 밀어낸다")

        // ② 달 넘기기 호출부는 예전 글자 그대로(토큰 판 손맛을 건드리지 않는다).
        let monthCall = [
            "RankingsMonthStepper(",
            "                    canStepForward: !isCurrent,",
            "                    previous: { store.stepTokenMonth(by: -1) },",
            "                    next: { store.stepTokenMonth(by: 1) }",
            "                )",
        ].joined(separator: "\n")
        #expect(code.contains(monthCall), "토큰 판 달 넘기기 호출부가 바뀌었다")

        // ③ 부제의 2단 ViewThatFits 를 늘리지 않았다(조각이 셋 → 둘로 줄어 그려지는 문장은 오히려 짧아진다).
        #expect(code.components(separatedBy: "ViewThatFits(in: .horizontal)").count - 1 == 4)

        // ④ 비활성 화살표가 막힌 이유를 값으로 읽는다.
        #expect(code.contains(".accessibilityValue(Text(enabled ? \"\" : disabledValue))"))
        #expect(code.contains("RankingsText.noEarlierWeek") && code.contains("RankingsText.noLaterWeek"))

        // ⑤ 값 변화 알림은 **한 번만**(공용 부품 한 자리). 여러 곳에 흩으면 한 번 누를 때 두 번 읽는다.
        #expect(code.components(separatedBy: "AccessibilityNotification.Announcement").count - 1 == 1)

        // ⑥ 옛 서버에서는 알약 자체를 그리지 않는다.
        #expect(code.contains("if store.showsLeagueWeekNavigation {"))

        // ⑦ 행은 섹션이 잰 '지금' 한 벌을 받고, 과거 판정은 행이 스스로 한다.
        #expect(code.contains("now: now,"))
        #expect(code.contains("if entry.isPastWeek(now: now) { return Text(RankingsText.leagueParticipation(entry)) }"))
    }

    /// 늦은 응답 **그물**은 오늘 순번 가드에 가려 실행으로는 못 잰다(주 키를 쓰는 자리가 전부 순번을 올리므로).
    /// 그래서 불변식 자체를 글자로 못 박는다 — 이 테스트가 없으면 "쓸모없어 보이는 가드"라며 지워도 아무도 모른다.
    /// (실제로 그 가드를 지우는 변형을 넣어 봤더니 모든 테스트가 초록이었다 — 이 계약이 그 구멍을 메운다.)
    @Test("스토어 계약: 주 키를 쓰는 자리는 전부 순번을 올린다 · 늦은 응답 그물 · defer 에는 주 키를 넣지 않는다")
    func storeInvariants() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsStore.swift")

        /// `marker` 로 시작해 다음 `package func`/`private func` 전까지의 토막.
        func body(after marker: String) throws -> String {
            let start = try #require(code.range(of: marker)).upperBound
            let rest = code[start...]
            let end = rest.range(of: "\n    package func") ?? rest.range(of: "\n    private func")
            return String(rest[..<(end?.lowerBound ?? rest.endIndex)])
        }

        // ① 주 키를 바꾸는 자리는 **바꾸기 전에** 순번을 올린다(떠 있는 응답을 여기서 버린다).
        for site in ["private func syncLeagueWeekToCurrent()", "package func stepLeagueWeek(by delta: Int)"] {
            let slice = try body(after: site)
            let bump = try #require(slice.range(of: "leagueSerial &+= 1"), "\(site) 가 순번을 안 올린다")
            let write = try #require(slice.range(of: "leagueWeekKey ="), "\(site) 가 주 키를 안 쓴다")
            #expect(bump.lowerBound < write.lowerBound, "\(site): 순번을 올리기 전에 주 키를 바꿨다")
        }
        // reset 도 키·앵커를 되돌리면서 순번을 올린다(계정이 바뀌는 자리).
        let reset = try body(after: "package func reset()")
        #expect(reset.contains("leagueSerial &+= 1") && reset.contains("leagueWeekKey = TeamLeagueWeekNavigator.currentKey"))
        #expect(reset.contains("leagueWeekOffsetSupported = true"), "접힌 알약을 다음 계정에 물려주면 db push 뒤에도 화살표가 안 돌아온다")

        // ② 늦은 응답 그물 두 겹(성공·실패 갈래 모두 주 키를 다시 본다).
        let load = try body(after: "package func loadLeague() async")
        #expect(load.contains("guard weekKey == leagueWeekKey else { return }"),
                "늦은 응답 그물이 사라졌다 — 순번을 못 올리는 갈래(서버 주 채택)가 생기면 과거 주 표가 이번 주에 꽂힌다")
        #expect(load.contains("serial == leagueSerial, weekKey == leagueWeekKey else { return }"),
                "실패 갈래가 주 키를 안 본다 — 옮겨 간 주에 옛 주의 실패가 찍힌다")

        // ③ defer 는 **순번만** 본다. 주 키를 넣으면 '서버 주 채택' 갈래에서 "불러오는 중"이 영영 남는다(맥이 두 번 고친 결함).
        #expect(load.contains("defer { if serial == leagueSerial { leagueState.isLoading = false } }"))
        #expect(!load.contains("defer { if serial == leagueSerial, weekKey == leagueWeekKey"))

        // ④ 과거 주는 주기 갱신을 돌리지 않되 **실패한 과거 주는 예외**(MU5 구멍 방지).
        let stale = try body(after: "package func refreshIfStale()")
        #expect(stale.contains("|| leagueState.hasFailed else { return }"))
        let roll = try #require(stale.range(of: "rollLeagueWeekIfNeeded()"))
        let guardRange = try #require(stale.range(of: "TeamLeagueWeekNavigator.isCurrentWeek(leagueWeekKey"))
        #expect(roll.lowerBound < guardRange.lowerBound, "롤오버보다 가드가 앞서면 갱신이 영영 막힌다")
    }
}
