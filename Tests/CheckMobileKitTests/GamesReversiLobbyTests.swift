@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **아잉 뒤집기 로비·신청·받기·관전·순위·규칙**(로비 갈래 3/4 · 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)")의 못.
// 뷰는 `#if os(iOS)` 안이라 맥 스위트가 못 본다 — 뷰가 부르는 판정·문(`GamesReversiLobbyPlan` · `GamesReversiRespond` · `GamesReversiInviteBanner` ·
// `GamesReversiStakeSend.send` · `GamesReversiWatchPlan`/`Status`/`Budget` · `GamesReversiRankingPlan` · `ReversiPhoneText` 로비 절 · 규칙 예시)을
// **요청 건수와 값**으로 잰다. 결과 단언마다 값 하나만 바꾼 기준선을 둔다(같은 입력이면 영원히 초록이다).

@MainActor
@Suite(.serialized) struct GamesReversiLobbyTests {
    private let waits = GamesWaitBudget()

    private nonisolated static func gomokuMatch() -> GomokuMatchState {
        GomokuMatchState(
            id: "g-lobby", stake: 5, myColor: .black,
            opponent: GomokuUser(id: "p-1", displayName: "구름빵", avatarURL: nil, characterID: nil,
                                 isWorking: true, isCapable: true, inMatch: true),
            board: GomokuBoard(), lastMove: nil, moveCount: 0, turn: .black, deadline: nil,
            isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false)
    }

    /// 요청 본문 한 칸(JSON) — 글자 모양(공백·순서)에 기대지 않는다.
    private static func bodyValue(_ request: MobileStubRequest, _ key: String) -> Any? {
        guard let data = request.bodyText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object[key]
    }

    private static func challengeOK(nowMs: Int) -> String {
        #"{"status":"ok","match_id":"a0000000-0000-4000-8000-0000000000d9","invite_expires_ms":\#(nowMs + 60_000),"ruby_balance":100,"server_now_ms":\#(nowMs)}"#
    }

    /// 수락 응답 — 받은 신청의 판이 진행 중으로 실려 온다(코어 `respond` 가 그 판을 세운다).
    private static func respondAccepted(nowMs: Int) -> String {
        ReversiWireJSON.state(nowMs: nowMs, id: ReversiWireHarness.inviteID, status: "active")
            .replacingOccurrences(of: #"{"status":"ok","#, with: #"{"status":"ok","accepted":true,"#)
    }

    /// 관전 응답(끝난 판). `winnerIsWhite` 하나만 바꿔 기준선을 만든다.
    private static func finishedWatch(nowMs: Int, winnerIsWhite: Bool) -> String {
        let a = ReversiWireHarness.rival, b = ReversiWireHarness.thirdID
        let result = winnerIsWhite ? "white_win" : "black_win"
        let winner = winnerIsWhite ? b : a
        let match = #"{"id":"\#(ReversiWireHarness.watchedID)","status":"finished","stake":5,"challenger":"\#(a)","opponent":"\#(b)","black":"\#(a)","white":"\#(b)","move_count":9,"turn":null,"turn_started_ms":null,"deadline_ms":null,"started_ms":\#(nowMs - 90_000),"finished_ms":\#(nowMs - 1_000),"result":"\#(result)","end_reason":"resign","winner":"\#(winner)","board":"\#(ReversiWireJSON.startBoard)","discs":{"black":2,"white":2,"empty":60},"score":null}"#
        return #"{"status":"ok","state":{"match":\#(match),"moves":[],"black_user":\#(ReversiWireJSON.player(a, "뒤집기라이벌")),"white_user":\#(ReversiWireJSON.player(b, "구경거리")),"opponent":null,"my_color":null,"legal_moves":[],"black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":null,"opponent_auto_streak":null,"auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":null,"watchers":2,"server_now_ms":\#(nowMs)}}"#
    }

    // MARK: - 문구 표: 상대 한 줄 · 풀이 줄 · 머리 한 줄

    @Test("상대 한 줄: 부제는 늘 근무 축 · 버튼은 서열 첫 까닭(옛 버전 > 대결 중 > 집중) · 버튼이 못 말한 까닭은 부제 꼬리 · 막힘이 없으면 '도전'")
    func opponentRowLines() {
        let ok = ReversiUser(id: "u1", displayName: "구름빵", isWorking: true)
        #expect(ReversiPhoneText.opponentRow(for: ok) == .init(subtitle: "근무 중", buttonTitle: "도전"), "기준선")
        var off = ok; off.isWorking = false
        #expect(ReversiPhoneText.opponentRow(for: off).subtitle == "근무 안 함")
        var old = ok; old.isCapable = false
        #expect(ReversiPhoneText.opponentRow(for: old) == .init(subtitle: "근무 중", buttonTitle: "업데이트 필요"))
        var oldBusy = old; oldBusy.inMatch = true
        #expect(ReversiPhoneText.opponentRow(for: oldBusy) == .init(subtitle: "근무 중 · 대결 중", buttonTitle: "업데이트 필요"),
                "옛 버전 + 대결 중: 버튼이 못 말한 '대결 중'이 사라졌다")
        var busyFocus = ok; busyFocus.inMatch = true; busyFocus.focusMode = true
        #expect(ReversiPhoneText.opponentRow(for: busyFocus) == .init(subtitle: "근무 중 · 집중 모드", buttonTitle: "대결 중"))
        var focus = ok; focus.focusMode = true
        #expect(ReversiPhoneText.opponentRow(for: focus) == .init(subtitle: "근무 중", buttonTitle: "집중 모드"))
        // 막힘 판정과 글자가 같은 축을 본다 — 글자가 '도전'이면 상대 쪽 게이트도 열려 있어야 한다.
        for user in [ok, old, oldBusy, busyFocus, focus] {
            #expect(ReversiPhoneText.locks(for: user).isEmpty == (ReversiPhoneText.opponentRow(for: user).buttonTitle == "도전"))
        }
    }

    @Test("풀이 줄: 목록에 있는 까닭만 · 서열 순 · 중복 없음 · 옛 버전 줄은 코어 거절 문장을 싣는다 · 막힘이 없으면 0줄")
    func lockLegends() {
        let ok = ReversiUser(id: "u1", displayName: "a")
        var old = ok; old.isCapable = false
        var busy = ok; busy.inMatch = true
        var focus = ok; focus.focusMode = true
        #expect(ReversiPhoneText.lockLegends(users: [ok, ok]).isEmpty, "막힌 사람이 없는데 풀이 줄이 선다")
        #expect(ReversiPhoneText.lockLegends(users: [focus, old, busy, old]) ==
                [ReversiPhoneText.lockLegend(.outdated), ReversiPhoneText.lockLegend(.inMatch), ReversiPhoneText.lockLegend(.focus)])
        #expect(ReversiPhoneText.lockLegends(users: [busy]) == [ReversiPhoneText.lockLegend(.inMatch)])
        #expect(ReversiPhoneText.lockLegend(.outdated).contains(ReversiNoticeText.targetOutdated))
        // 세 줄이 서로 다르고, 각 줄이 버튼 글자로 시작한다(눈이 버튼에서 풀이로 건너간다).
        #expect(Set(ReversiPhoneText.Lock.allCases.map(ReversiPhoneText.lockLegend)).count == 3)
        for lock in ReversiPhoneText.Lock.allCases {
            #expect(ReversiPhoneText.lockLegend(lock).hasPrefix(ReversiPhoneText.lockButton(lock)))
            #expect(ReversiPhoneText.lockLegend(lock).contains("신청할 수 있어요"), "언제 풀리는지를 말하지 않는다: \(lock)")
        }
    }

    @Test("로비 머리 한 줄: 서버 한 수 시간을 싣는다(30이면 카드 부제와 같은 글자 · 45면 다른 글자)")
    func lobbySubtitle() {
        #expect(ReversiPhoneText.lobbySubtitle(turnSeconds: 30) == ReversiPhoneText.subtitle)
        #expect(ReversiPhoneText.lobbySubtitle(turnSeconds: 45).contains("한 수 45초"))
        #expect(ReversiPhoneText.lobbySubtitle(turnSeconds: 45) != ReversiPhoneText.subtitle)
        #expect(ReversiPhoneText.stakeLine(5) == "5 · 이기면 +5" && ReversiPhoneText.stakeLine(10) == "10 · 이기면 +10",
                "순이익이 결과 카드와 다르다(수수료 0)")
        #expect(ReversiPhoneText.stakeNotHeldYet(ttlSeconds: 90).contains("90초"))
        #expect(ReversiPhoneText.stakeNotHeldYet(ttlSeconds: 60).contains("빠지지 않아요"), "신청만으로 루비가 빠진다는 거짓말")
    }

    // MARK: - 상대 고르기 절

    @Test("상대 절: 로비 전 로딩 · 받으면 행 · 받았는데 비면 '없어요'(로딩과 갈린다) · 할 수 없는 서버면 사람 절을 접는다 · 풀이 줄은 실제 목록에서")
    func usersSection() async {
        let harness = ReversiWireHarness(label: "reversi-lobby-users")
        harness.serve()
        let games = harness.games
        // 로그인이 곧 로비를 한 번 읽는다(실시간 따라잡기) — '받기 전'은 그 앞에서만 잴 수 있다.
        #expect(GamesReversiLobbyPlan.users(games) == .loading, "로비를 받기 전인데 '없어요'를 말한다")
        await harness.signIn()
        games.reversiScreenDidAppear()
        #expect(await waits.wait { GamesReversiLobbyPlan.users(games) == .rows }, "로비가 왔는데 행이 안 선다")
        // 로비의 '구버전'(capable null) 한 사람 → 옛 버전 풀이 한 줄만.
        #expect(GamesReversiLobbyPlan.lockLegends(games) == [ReversiPhoneText.lockLegend(.outdated)])
        let old = games.reversiLobbyUsers.first { $0.id == ReversiWireHarness.thirdID }
        #expect(old.map { ReversiPhoneText.opponentRow(for: $0).buttonTitle } == "업데이트 필요")
        #expect(GamesReversiLobbyPlan.showsPeopleSections(harness.reversi))

        // 같은 로비에서 사람만 뺀다 — 이제 '받았고 비었다'.
        let users = [ReversiWireJSON.user(ReversiWireHarness.rival, "뒤집기라이벌"),
                     ReversiWireJSON.user(ReversiWireHarness.thirdID, "구버전", capable: nil)].joined(separator: ",")
        let empty = ReversiWireJSON.lobby(nowMs: harness.nowMs).replacingOccurrences(of: users, with: "")
        #expect(empty != ReversiWireJSON.lobby(nowMs: harness.nowMs), "시험 픽스처가 사람을 못 뺐다")
        harness.server.setDefault("reversi_lobby", json: empty)
        await harness.reversi.refreshLobby()
        #expect(GamesReversiLobbyPlan.users(games) == .empty)
        #expect(GamesReversiLobbyPlan.lockLegends(games).isEmpty)

        harness.reversi.availability = .updateRequired
        #expect(!GamesReversiLobbyPlan.showsPeopleSections(harness.reversi), "업데이트가 필요한데 신청 절이 선다")
        await harness.tearDown()
    }

    // MARK: - 판돈 시트 → 신청 (요청이 나가는 유일한 문)

    @Test("판돈 시트 [도전하기]: 고른 판돈이 그대로 실린다(10 · 3 기준선) · 안 골랐으면 요청 0건 · 다른 게임 판이면 0건")
    func stakeSheetSends() async {
        for (stake, label) in [(ReversiStake.ten, "ten"), (.three, "three")] {
            let harness = ReversiWireHarness(label: "reversi-lobby-send-\(label)")
            harness.serve()
            harness.server.setDefault("reversi_challenge", json: Self.challengeOK(nowMs: harness.nowMs))
            await harness.signIn()
            harness.games.reversiScreenDidAppear()
            #expect(await waits.wait { harness.reversi.record != nil })

            #expect(await GamesReversiStakeSend.send(nil, to: ReversiWireHarness.rival, games: harness.games) == false)
            #expect(harness.count("reversi_challenge") == 0, "판돈을 안 골랐는데 신청이 나갔다")

            harness.model.gomoku.match = Self.gomokuMatch()
            #expect(await GamesReversiStakeSend.send(stake, to: ReversiWireHarness.rival, games: harness.games) == false)
            #expect(harness.count("reversi_challenge") == 0, "오목 판이 흐르는데 리버시 신청이 나갔다(한 사람 한 판)")
            harness.model.gomoku.match = nil

            #expect(await GamesReversiStakeSend.send(stake, to: ReversiWireHarness.rival, games: harness.games))
            let sent = harness.server.requests("reversi_challenge")
            #expect(sent.count == 1)
            #expect((sent.first.flatMap { Self.bodyValue($0, "p_stake") } as? Int) == stake.rawValue, "고른 것과 다른 판돈이 나갔다")
            #expect((sent.first.flatMap { Self.bodyValue($0, "p_opponent") } as? String) == ReversiWireHarness.rival)
            #expect(harness.reversi.selectedStake == stake)
            #expect(harness.reversi.outgoing?.stake == stake.rawValue, "보낸 신청 줄이 고른 판돈을 말하지 않는다")
            // 보낸 신청이 서면 같은 시트를 다시 눌러도 두 번째 신청은 없다(마지막 문).
            #expect(await GamesReversiStakeSend.send(stake, to: ReversiWireHarness.rival, games: harness.games) == false)
            #expect(harness.count("reversi_challenge") == 1)
            await harness.tearDown()
        }
        #expect(GamesReversiStakeSend.toggled(current: nil, tapped: .five) == .five)
        #expect(GamesReversiStakeSend.toggled(current: .five, tapped: .five) == nil, "같은 판돈을 다시 눌러도 해제가 안 된다")
        #expect(GamesReversiStakeSend.toggled(current: .five, tapped: .ten) == .ten)
    }

    // MARK: - 받기: 수락 길 · 로봇 판 확인 · 판 위 띠

    @Test("수락 길: 평소 곧바로 · 로봇 판 중이면 먼저 묻는다 · 다른 게임 판·요청 중이면 막힘(요청 0건) · 거절은 다른 게임 판이어도 나간다")
    func acceptRoutes() async {
        let harness = ReversiWireHarness(label: "reversi-lobby-accept-route")
        harness.serve(incoming: true)
        harness.server.setDefault("reversi_respond", json: Self.respondAccepted(nowMs: harness.nowMs))
        await harness.signIn()
        let games = harness.games
        games.reversiScreenDidAppear()
        #expect(await waits.wait { games.reversi.visibleIncomingInvites.count == 1 })
        #expect(GamesReversiRespond.acceptRoute(games) == .send, "기준선")

        games.reversi.isBusy = true
        #expect(GamesReversiRespond.acceptRoute(games) == .blocked)
        #expect(!GamesReversiRespond.canDecline(games))
        games.reversi.isBusy = false

        harness.model.gomoku.match = Self.gomokuMatch()
        #expect(GamesReversiRespond.acceptRoute(games) == .blocked, "오목 판이 흐르는데 수락이 열렸다")
        #expect(await GamesReversiRespond.accept(games, inviteID: ReversiWireHarness.inviteID) == false)
        #expect(harness.count("reversi_respond") == 0, "막힌 수락이 요청을 냈다")
        #expect(GamesReversiRespond.canDecline(games), "거절은 판돈이 안 움직인다 — 다른 게임 판이 막을 까닭이 없다")
        harness.model.gomoku.match = nil

        games.reversi.startAIMatch(humanColor: .black)
        #expect(games.hasLiveReversiAIGame)
        #expect(GamesReversiRespond.acceptRoute(games) == .confirmRobot, "로봇 판 중인데 묻지 않고 수락한다 — 두던 판이 말없이 사라진다")
        await harness.tearDown()
    }

    @Test("로봇 판 중 받은 신청: 판 위 띠가 선다 · [끝내고 수락] 한 번에 요청 한 건 → 1:1 판이 서고 로봇 판은 버려진다")
    func acceptDuringRobotGame() async {
        let harness = ReversiWireHarness(label: "reversi-lobby-accept-robot")
        harness.serve(incoming: true)
        harness.server.setDefault("reversi_respond", json: Self.respondAccepted(nowMs: harness.nowMs))
        await harness.signIn()
        let games = harness.games
        let reversi = harness.reversi
        games.reversiScreenDidAppear()
        #expect(await waits.wait { reversi.visibleIncomingInvites.count == 1 })
        // 로비에서는 띠가 없다(로비 카드가 그 자리다) — 기준선.
        #expect(GamesReversiInviteBanner.invite(reversi) == nil)

        reversi.startAIMatch(humanColor: .black)
        #expect(reversi.match?.isAI == true)
        #expect(GamesReversiInviteBanner.invite(reversi)?.id == ReversiWireHarness.inviteID, "로봇 판이 로비를 덮었는데 신청이 화면에 없다")
        #expect(GamesReversiInviteBanner.moreCount(reversi) == 0)

        #expect(await GamesReversiRespond.accept(games, inviteID: ReversiWireHarness.inviteID))
        let sent = harness.server.requests("reversi_respond")
        #expect(sent.count == 1)
        #expect((sent.first.flatMap { Self.bodyValue($0, "p_accept") } as? Bool) == true)
        #expect(reversi.match?.id == ReversiWireHarness.inviteID && reversi.match?.isAI == false, "수락했는데 1:1 판이 안 섰다")
        #expect(reversi.aiGame == nil, "1:1 판이 섰는데 로봇 판이 남았다")
        #expect(GamesReversiInviteBanner.invite(reversi) == nil, "두는 1:1 판 위에 받은 신청 띠가 남았다")
        await harness.tearDown()
    }

    @Test("판 위 띠: 로봇 판 · 끝난 1:1 판 위에만 선다 · 두는 1:1 판 위에는 안 선다(서버가 busy 로 거절한다)")
    func bannerOnlyOverRobotOrFinished() async {
        let live = ReversiWireHarness(label: "reversi-lobby-banner-live")
        live.serve(incoming: true)
        await live.signIn()
        live.games.reversiScreenDidAppear()
        #expect(await waits.wait { live.reversi.visibleIncomingInvites.count == 1 })
        await live.loadMatch(status: "active", owned: true)
        #expect(live.reversi.match?.isFinished == false)
        #expect(GamesReversiInviteBanner.invite(live.reversi) == nil, "두는 1:1 판 위에 받은 신청 띠가 선다")
        await live.tearDown()

        let done = ReversiWireHarness(label: "reversi-lobby-banner-done")
        done.serve(incoming: true)
        await done.signIn()
        done.games.reversiScreenDidAppear()
        #expect(await waits.wait { done.reversi.visibleIncomingInvites.count == 1 })
        await done.loadMatch(status: "finished", owned: true)
        #expect(done.reversi.match?.isFinished == true)
        #expect(GamesReversiInviteBanner.invite(done.reversi)?.id == ReversiWireHarness.inviteID,
                "끝난 판 결과 화면이 로비를 덮었는데 신청이 화면에 없다")
        #expect(GamesReversiRespond.acceptRoute(done.games) == .send, "끝난 판은 로봇 판이 아니다 — 묻지 않는다")
        await done.tearDown()
    }

    // MARK: - 관전

    @Test("관전 입구: 스위치 꺼짐 → 없음 · 내 판 → 캡션 · 관전 함수 없음 → 곧 · 순위·관전자 수 깃발은 입구를 잠그지 않는다")
    func watchEntry() async {
        let harness = ReversiWireHarness(label: "reversi-lobby-watch-entry")
        harness.serve(matches: true)
        await harness.signIn()
        let reversi = harness.reversi
        harness.games.reversiScreenDidAppear()
        #expect(await waits.wait { !reversi.liveMatches.isEmpty })
        let live = reversi.liveMatches[0]
        #expect(GamesReversiWatchPlan.entry(reversi, isMine: false) == .chip, "기준선")
        #expect(GamesReversiWatchPlan.entry(reversi, isMine: true) == .myMatch)
        #expect(!reversi.isMine(live))
        reversi.rankingUnavailable = true
        reversi.spectatorCountUnavailable = true
        #expect(GamesReversiWatchPlan.entry(reversi, isMine: false) == .chip, "순위·관전자 수 깃발이 관전을 잠갔다(깃발 겸업)")
        reversi.watchUnavailable = true
        #expect(GamesReversiWatchPlan.entry(reversi, isMine: false) == .soon)
        reversi.spectatorFeaturesEnabled = false
        #expect(GamesReversiWatchPlan.entry(reversi, isMine: false) == .absent)
        #expect(!GamesReversiWatchPlan.hasTrailingContent(reversi, live: live), "입구도 수도 없는데 슬롯을 잰다")
        var watched = live; watched.watchers = 3
        #expect(GamesReversiWatchPlan.hasTrailingContent(reversi, live: watched), "관전자 수는 스위치와 무관하게 선다")
        // 관전 판에는 입력이 없다.
        #expect(GamesReversiWatchPlan.boardTapHandler == nil && GamesReversiWatchPlan.boardLegalTargets.isEmpty)
        #expect(!GamesReversiWatchPlan.showsResign)
        await harness.tearDown()
    }

    @Test("관전 결과: 승자는 서버 판 행이 말한 색의 사람(백 승 ↔ 흑 승 기준선) · 3인칭 사유 · 관전자 수 · 진행 중엔 승자를 말하지 않는다")
    func watchStatusThroughServer() async {
        var headlines: [Bool: String] = [:]
        for whiteWins in [true, false] {
            let harness = ReversiWireHarness(label: "reversi-lobby-watch-\(whiteWins)")
            harness.serve(matches: true)
            harness.server.setDefault("reversi_watch_live", json: Self.finishedWatch(nowMs: harness.nowMs, winnerIsWhite: whiteWins))
            await harness.signIn()
            let reversi = harness.reversi
            harness.games.reversiScreenDidAppear()
            #expect(await waits.wait { !reversi.liveMatches.isEmpty })
            reversi.startWatching(matchID: ReversiWireHarness.watchedID)
            #expect(await waits.wait { reversi.spectating?.isFinished == true }, "끝난 판 관전 응답이 화면 값으로 안 옮겨졌다")
            guard let watch = reversi.spectating else { await harness.tearDown(); continue }
            #expect(GamesReversiWatchStatus.kind(for: watch) == .ended)
            let headline = GamesReversiWatchStatus.headline(for: watch)
            headlines[whiteWins] = headline
            #expect(headline == (whiteWins ? "구경거리(백) 승리" : "뒤집기라이벌(흑) 승리"))
            #expect(GamesReversiWatchStatus.detail(for: watch, lossStreak: 3) == (whiteWins ? "흑이 기권했어요" : "백이 기권했어요"),
                    "관전 사유가 3인칭이 아니다")
            #expect(reversi.spectatorCount == 2, "관전자 수가 화면 값으로 안 옮겨졌다")
            await harness.tearDown()
        }
        #expect(headlines[true] != headlines[false])

        // 진행 중 판에 승자 칸이 섞여 와도(있을 수 없지만) 승자를 말하지 않는다 · 색을 모르면 차례도 말하지 않는다.
        let black = ReversiUser(id: "b", displayName: "흑돌이"), white = ReversiUser(id: "w", displayName: "백돌이")
        var playing = ReversiSpectating(id: "m", blackUser: black, whiteUser: white, turn: .white, winner: .black)
        #expect(GamesReversiWatchStatus.headline(for: playing) == "관전 중 · 백 차례")
        #expect(GamesReversiWatchStatus.winnerColor(for: playing) == nil && GamesReversiWatchStatus.detail(for: playing, lossStreak: 3) == nil)
        playing.blackUser = nil
        #expect(GamesReversiWatchStatus.kind(for: playing) == .loading, "흑 사람을 모르는데 차례를 말한다")
        let draw = ReversiSpectating(id: "m", blackUser: black, whiteUser: white, result: .draw, endReason: .boardFull,
                                     isFinished: true)
        #expect(GamesReversiWatchStatus.headline(for: draw) == ReversiPhoneText.watchEndedDraw)
        // 이름이 빈 승자 — 색만 말한다(지어내지 않는다).
        let nameless = ReversiSpectating(id: "m", blackUser: ReversiUser(id: "b", displayName: " "), whiteUser: white,
                                         endReason: .abandoned, winner: .black, isFinished: true)
        #expect(GamesReversiWatchStatus.headline(for: nameless) == "흑 승리")
        #expect(GamesReversiWatchStatus.detail(for: nameless, lossStreak: 3) == "백 시간이 3번 이어서 지났어요")
        #expect(GamesReversiWatchStatus.displayName(nil) == "—")
    }

    @Test("관전 판 한 변: SE 는 높이가 이긴다(288) · 큰 화면은 폭(360) · 뷰포트 모름은 폭만 · 좁은 열은 열 폭 · 시계 0초는 주황(빨강 아님)")
    func watchBudgetAndClock() {
        #expect(GamesReversiWatchBudget.blocksAroundBoard() == 266)
        #expect(GamesReversiWatchBudget.side(column: 343, viewportHeight: 554) == 288)
        #expect(GamesReversiWatchBudget.side(column: 361, viewportHeight: 739) == 360)
        #expect(GamesReversiWatchBudget.side(column: 361, viewportHeight: 0) == 360)
        #expect(GamesReversiWatchBudget.side(column: 150, viewportHeight: 300) == 144, "열보다 넓은 판 — 카드가 오른쪽으로 넘친다")
        #expect(GamesReversiWatchBudget.side(column: 0, viewportHeight: 500) == GamesReversiBoardLayout.minimumSide)
        #expect(GamesReversiWatchStatus.clockTint(remaining: 0) == .warn, "0초가 빨강이다 — 관전자에게 결과를 지어낸다")
        #expect(GamesReversiWatchStatus.clockTint(remaining: 3) == .bad)
        #expect(GamesReversiWatchStatus.clockTint(remaining: 8) == .warn)
        #expect(GamesReversiWatchStatus.clockTint(remaining: 20) == .good)
    }

    // MARK: - 순위

    @Test("순위 절: 받기 전 로딩 · 행 → 행(준비 중 깃발이 있어도) · 0판 행만이면 '아직 없어요' · 서버 없음이면 '곧' · 머리 캡션 · 내 순위는 전적이 맞을 때만")
    func rankingPlan() async {
        let harness = ReversiWireHarness(label: "reversi-lobby-ranking")
        harness.serve()
        await harness.signIn()
        let reversi = harness.reversi
        #expect(GamesReversiRankingPlan.content(reversi) == .loading)
        #expect(GamesReversiRankingPlan.sinceCaption(reversi) == nil, "컷을 모르는데 기간을 말한다")
        harness.games.reversiScreenDidAppear()
        #expect(await waits.wait { reversi.ranking != nil })
        #expect(GamesReversiRankingPlan.content(reversi) == .rows)
        #expect(GamesReversiRankingPlan.sinceCaption(reversi) == ReversiPhoneText.rankWholePeriod)
        #expect(await waits.wait { reversi.record != nil })
        #expect(GamesReversiRankingPlan.myRank(reversi)?.rank == 1, "로비 전적(2-1-0)과 순위 전적이 같은데 내 순위가 없다")
        reversi.rankingUnavailable = true
        #expect(GamesReversiRankingPlan.content(reversi) == .rows, "받아 둔 행을 버리고 '곧 열려요'를 말한다")

        let me = ReversiUser(id: ReversiWireHarness.userID, displayName: "나")
        let zero = ReversiRankEntry(id: "z", rank: 2, user: ReversiUser(id: "z", displayName: "영판"), wins: 0, losses: 0, draws: 0, points: 0)
        reversi.ranking = ReversiRanking(entries: [zero], me: nil,
                                         recordSince: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(GamesReversiRankingPlan.content(reversi) == .soon)
        reversi.rankingUnavailable = false
        #expect(GamesReversiRankingPlan.content(reversi) == .empty, "0판 행이 순위에 낀다")
        #expect(GamesReversiRankingPlan.sinceCaption(reversi)?.hasSuffix("일부터") == true)
        #expect(GamesReversiRankingPlan.myRank(reversi) == nil)

        let many = (1...7).map {
            ReversiRankEntry(id: "u\($0)", rank: $0, user: $0 == 1 ? me : ReversiUser(id: "u\($0)", displayName: "사람\($0)"),
                             wins: 8 - $0, losses: 1, draws: 0, points: 7 - $0)
        }
        reversi.ranking = ReversiRanking(entries: many + [zero], me: nil, recordSince: nil)
        #expect(GamesReversiRankingPlan.visible(reversi, isExpanded: false).count == 5)
        #expect(GamesReversiRankingPlan.visible(reversi, isExpanded: true).count == 7)
        #expect(GamesReversiRankingPlan.visible(reversi, isExpanded: true).map(\.rank) == Array(1...7), "서버 순서를 바꿨다")
        #expect(GamesReversiRankingPlan.showsToggle(reversi) && GamesReversiRankingPlan.total(reversi) == 7)
        // 로비 전적과 순위 전적이 어긋나면 내 순위 줄을 안 세운다(자기모순 문장 방지 — 코어 판정).
        reversi.ranking = ReversiRanking(entries: many, me: ReversiMyRank(rank: 3, wins: 9, losses: 9, draws: 9, points: 0), recordSince: nil)
        #expect(GamesReversiRankingPlan.myRank(reversi) == nil)
        await harness.tearDown()
    }

    @Test("순위 글자: 승점 부호 · 내 순위 줄(순위 밖 포함) · 행 보이스오버는 일곱 칸을 다 말한다")
    func rankingText() {
        #expect(ReversiPhoneText.points(4) == "승점 +4" && ReversiPhoneText.points(-2) == "승점 −2" && ReversiPhoneText.points(0) == "승점 0")
        #expect(ReversiPhoneText.myRankLine(ReversiMyRank(rank: 12, wins: 6, losses: 2, draws: 1, points: 4)) == "12위 · 승점 +4 · 6승 2패 1무")
        #expect(ReversiPhoneText.myRankLine(ReversiMyRank(rank: nil, wins: 0, losses: 0, draws: 0, points: 0)) == "순위 밖 · 0승 0패 0무")
        let entry = ReversiRankEntry(id: "u", rank: 3, user: ReversiUser(id: "u", displayName: "민트별", center: "서울"),
                                     wins: 6, losses: 2, draws: 1, points: 4)
        #expect(ReversiPhoneText.rankRowAccessibility(entry, isMe: true) == "3위, 나, 민트별, 서울센터, 승점 +4, 6승 2패 1무")
        #expect(ReversiPhoneText.rankRowAccessibility(entry, isMe: false) == "3위, 민트별, 서울센터, 승점 +4, 6승 2패 1무")
    }

    // MARK: - 규칙 시트

    @Test("규칙 시트: 열 줄 · 숫자 셋은 로비 값(45·4·90 ↔ 30·3·60 기준선) · 예시 넷은 규칙 코어로 계산된다")
    func rules() {
        let custom = ReversiPhoneText.rules(turnSeconds: 45, lossStreak: 4, inviteTtlSeconds: 90)
        let base = ReversiPhoneText.rules(turnSeconds: 30, lossStreak: 3, inviteTtlSeconds: 60)
        #expect(custom.count == 10 && base.count == 10)
        #expect(custom[5].contains("45초") && custom[5].contains("4번"))
        #expect(custom[7].contains("90초"))
        #expect(base[5].contains("30초") && base[5].contains("3번") && base[7].contains("60초"))
        #expect(custom != base)
        // 상표: 게임 이름이 아니라 설명으로만 — 마지막 줄 하나.
        #expect(custom.filter { $0.contains("리버시") }.count == 1)

        let examples = GamesReversiRuleExample.all
        #expect(examples.map(\.id) == ["start", "lines", "pass", "end"], "예시 판이 빠졌다(코어 계산이 실패하면 조용히 빠진다)")
        #expect(examples[0].dots == [19, 26, 37, 44], "시작 판 흑의 둘 수 있는 칸이 d3·c4·f5·e6 가 아니다")
        #expect(examples[1].lastStone == 18 && examples[1].flipped.count >= 3, "여러 줄 예시가 세 방향을 못 뒤집는다")
        #expect(examples[1].board[18] == .black)
        #expect(!examples[2].dots.isEmpty && ReversiRules.legalMoves(examples[2].board, color: .black).isEmpty,
                "넘김 예시에서 흑이 둘 곳이 있다")
        #expect(examples[3].detail.contains("63 : 1"), "끝과 점수 예시의 빈칸 몫이 틀렸다")
    }

    @Test("규칙 시트는 새 판이 서면 접는다(검토 지적 — 로비에서 읽던 사람이 시트 아래서 30초를 흘리지 않게) · 판 중에 연 시트 · 로비로 돌아갈 때는 그대로")
    func rulesSheetClosesOnNewMatch() throws {
        // 새 판: 로비(nil) → 판 · 판 → 다른 판(로봇 판 중 수락).
        #expect(GamesReversiRulesSheetRule.closesOnMatchChange(from: nil, to: "m-1"))
        #expect(GamesReversiRulesSheetRule.closesOnMatchChange(from: "ai-1", to: "m-2"))
        // 기준선: 같은 판(판 중에 책 버튼) · 로비로 돌아감은 접지 않는다.
        #expect(!GamesReversiRulesSheetRule.closesOnMatchChange(from: "m-1", to: "m-1"))
        #expect(!GamesReversiRulesSheetRule.closesOnMatchChange(from: "m-1", to: nil))
        #expect(!GamesReversiRulesSheetRule.closesOnMatchChange(from: nil, to: nil))
        // 화면 배선(주석 걷은 소스): 판 id 바뀜 블록이 이 규칙으로 규칙 시트를 내린다. 뷰는 `#if os(iOS)` 라 맥 스위트가 컴파일하지 않는다.
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesReversiScreen.swift")
        let hit = try #require(code.range(of: ".onChange(of: reversi.match?.id) { old, new in"), "판 id 바뀜 블록이 old/new 를 안 받는다")
        let block = String(code[hit.upperBound...].prefix(600))
        #expect(block.contains("if GamesReversiRulesSheetRule.closesOnMatchChange(from: old, to: new) { reversi.isRulesVisible = false }"),
                "새 판이 서도 규칙 시트가 판을 가린다")
        #expect(block.contains("stakeTarget = nil") && block.contains("showsAIColorSheet = false"), "다른 시트 접기가 빠졌다")
    }
}
