@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 아잉 큐브 **로비·방·순위**(1.0.16 · 설계서 §5)의 판정. 폰 뷰는 맥 스위트가 한 줄도 못 보므로 재는 것은 뷰가 받아 그리는 값과 **나간 요청 건수**다.
@MainActor
@Suite(.serialized) struct V1016RummyLobbyTests {
    private let waits = GamesWaitBudget()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "a0000000-0000-4000-8000-%012d", n))! }

    private func room(_ n: Int, stake: Int = 5, joined: Int = 1, maxSeats: Int = 4) -> RummyRoom {
        let seats = (0..<joined).map { #"{"user_id":"\#(Self.id(100 + $0).uuidString)","state":"joined","seat_no":\#($0)}"# }
        let json = #"{"id":"\#(Self.id(n).uuidString)","stake":\#(stake),"max_seats":\#(maxSeats),"seats":[\#(seats.joined(separator: ","))]}"#
        return try! Self.decoder.decode(RummyRoom.self, from: Data(json.utf8))
    }

    private func user(_ n: Int, capable: Bool? = true, inMatch: Bool = false, focus: Bool = false, working: Bool = false) -> RummyLobbyUser {
        let capableText = capable.map(String.init) ?? "null"
        let json = #"{"id":"\#(Self.id(n).uuidString)","display_name":"사람\#(n)","capable":\#(capableText),"in_match":\#(inMatch),"focus_mode":\#(focus),"is_working":\#(working)}"#
        return try! Self.decoder.decode(RummyLobbyUser.self, from: Data(json.utf8))
    }

    private func lobby(invites: [RummyRoom] = [], rooms: [RummyRoom] = [], users: [RummyLobbyUser] = []) -> RummyLobby {
        var lobby = try! Self.decoder.decode(RummyLobby.self, from: Data(#"{"status":"ok"}"#.utf8))
        lobby.invites = invites
        lobby.publicRooms = rooms
        lobby.users = users
        return lobby
    }

    // MARK: - 받은 초대 + 공개 방

    @Test("참가 목록: 초대 먼저 · 서버 순서 · 같은 방은 한 번(초대로) · 앉은 방은 뺀다")
    func joinablesOrder() {
        let items = GamesRummyLobbyPlan.joinables(
            lobby: lobby(invites: [room(2), room(1), room(9)], rooms: [room(3), room(1), room(9)]), myRoomID: Self.id(9))
        #expect(items.map(\.id) == [Self.id(2), Self.id(1), Self.id(3)])
        #expect(items.map(\.isInvite) == [true, true, false])
        #expect(GamesRummyLobbyPlan.joinables(lobby: nil, myRoomID: nil).isEmpty)
    }

    @Test("참가 줄 글자: 초대는 인원 · 공개 방은 빈자리 · 기본 4자리")
    func joinableText() {
        let invite = GamesRummyJoinable(room: room(1, joined: 2), isInvite: true)
        let open = GamesRummyJoinable(room: room(2, joined: 3), isInvite: false)
        #expect(invite.seatsText == "2/4명")
        #expect(open.seatsText == "빈자리 1")
    }

    @Test("[참가] 막기 표: 다른 게임 > 방 있음 > 비행 중 > 가득 > 모자람 · 잔액 모르면 안 막는다")
    func joinBlockTable() {
        typealias P = GamesRummyLobbyPlan
        let open = GamesRummyJoinable(room: room(1, stake: 5, joined: 1), isInvite: false)
        let full = GamesRummyJoinable(room: room(1, stake: 5, joined: 4), isInvite: false)
        #expect(P.joinBlock(open, balance: 5, hasRoom: false, isWorking: false, blockedBy: nil) == nil, "딱 맞는 잔액을 막았다")
        #expect(P.joinBlock(open, balance: nil, hasRoom: false, isWorking: false, blockedBy: nil) == nil, "잔액을 모르는데 막았다")
        #expect(P.joinBlock(open, balance: 4, hasRoom: false, isWorking: false, blockedBy: nil) == .short)
        #expect(P.joinBlock(full, balance: 4, hasRoom: false, isWorking: false, blockedBy: nil) == .full)
        #expect(P.joinBlock(full, balance: 9, hasRoom: false, isWorking: true, blockedBy: nil) == .working)
        #expect(P.joinBlock(open, balance: 9, hasRoom: true, isWorking: true, blockedBy: nil) == .hasRoom)
        #expect(P.joinBlock(open, balance: 9, hasRoom: true, isWorking: true, blockedBy: .chess) == .otherGame)
        #expect(P.joinBlockText(.short) == GamesRummyText.stakeShortfall)
        #expect(P.joinBlockText(.full) == GamesRummyText.roomFullShort)
        #expect(P.joinBlockText(.otherGame) == nil, "다른 게임은 로비 위 두 줄 안내가 말한다")
    }

    // MARK: - 새 탁자

    @Test("[탁자 열기] 막기 표: 다른 게임 > 판 있음 > 비행 중 > 모자람 · 잔액 모르면 안 막는다")
    func tableBlockTable() {
        typealias P = GamesRummyLobbyPlan
        #expect(P.tableBlock(stake: 3, balance: 3, hasMatch: false, isWorking: false, blockedBy: nil) == nil)
        #expect(P.tableBlock(stake: 3, balance: nil, hasMatch: false, isWorking: false, blockedBy: nil) == nil)
        #expect(P.tableBlock(stake: 10, balance: 9, hasMatch: false, isWorking: false, blockedBy: nil) == .short)
        #expect(P.tableBlock(stake: 10, balance: 9, hasMatch: false, isWorking: true, blockedBy: nil) == .working)
        #expect(P.tableBlock(stake: 10, balance: 9, hasMatch: true, isWorking: true, blockedBy: nil) == .hasMatch)
        #expect(P.tableBlock(stake: 10, balance: 9, hasMatch: true, isWorking: true, blockedBy: .gomoku) == .otherGame)
    }

    @Test("판돈 표: 서버 값 우선 · 비면 기본 · 표 밖 값은 안 적는다")
    func stakes() {
        typealias P = GamesRummyLobbyPlan
        #expect(P.stakes(nil) == [3, 5, 10])
        var custom = lobby()
        custom.stakes = [5, 20]
        #expect(P.stakes(custom) == [5, 20])
        custom.stakes = []
        #expect(P.stakes(custom) == [3, 5, 10])
        #expect(P.selecting(10, current: 3, stakes: [3, 5, 10]) == 10)
        #expect(P.selecting(7, current: 3, stakes: [3, 5, 10]) == 3)
    }

    // MARK: - 사람

    @Test("사람 셋으로 나누기: 서버 순서 유지 · capable nil 은 불가 · 부제 서열")
    func peopleSplit() {
        typealias P = GamesRummyLobbyPlan
        let users = [user(1), user(2, inMatch: true), user(3, capable: false), user(4, focus: true), user(5, capable: nil), user(6, working: true)]
        let people = P.people(users)
        #expect(people.ready.map(\.id) == [Self.id(1), Self.id(6)])
        #expect(people.busy.map(\.id) == [Self.id(2), Self.id(4)])
        #expect(people.outdated.map(\.id) == [Self.id(3), Self.id(5)])
        #expect(P.statusText(user(1, capable: false, inMatch: true)) == GamesRummyText.statusOutdated)
        #expect(P.statusText(user(1, inMatch: true, focus: true, working: true)) == GamesRummyText.statusInMatch)
        #expect(P.statusText(user(1, focus: true, working: true)) == GamesRummyText.statusFocus)
        #expect(P.statusText(user(1, working: true)) == GamesRummyText.statusWorking)
        #expect(P.statusText(user(1)) == GamesRummyText.statusIdle)
    }

    @Test("사람 행 동작 표: 방 없음 · 방장 · 손님 · 줄 선 사람 · 자리 있는 사람 · 가득 찬 방 · 다른 게임")
    func personActionTable() throws {
        typealias P = GamesRummyLobbyPlan
        func act(_ user: RummyLobbyUser, room: RummyRoom? = nil, host: Bool = false, working: Bool = false, calling: [UUID] = [],
                 other: GamesBusyGame? = nil) -> P.PersonAction {
            P.personAction(user: user, room: room, amHost: host, isWorking: working, calling: calling, blockedBy: other)
        }
        // 방 없음 — 탁자 열고 부르기.
        #expect(act(user(1)) == .invite(enabled: true))
        #expect(act(user(1), working: true) == .invite(enabled: false))
        #expect(act(user(1, inMatch: true)) == .invite(enabled: false))
        #expect(act(user(1, focus: true)) == .invite(enabled: false))
        #expect(act(user(1, capable: false)) == .hidden, "구버전은 서버가 어차피 거절한다")
        #expect(act(user(1), other: .tetris) == .invite(enabled: false), "다른 게임 중에 초대가 나간다")
        #expect(act(user(1), calling: [Self.id(1)]) == .tag(GamesRummyText.calling))
        // 손님 — 아무것도 없다.
        let room4 = room(50, joined: 2)
        #expect(act(user(1), room: room4, host: false) == .hidden)
        // 방장 — 자리 있는 사람은 글자.
        let json = #"{"id":"\#(Self.id(50).uuidString)","max_seats":4,"seats":[{"user_id":"\#(Self.id(1).uuidString)","state":"joined","seat_no":0},{"user_id":"\#(Self.id(2).uuidString)","state":"invited"},{"user_id":"\#(Self.id(3).uuidString)","state":"declined"}]}"#
        let seated = try Self.decoder.decode(RummyRoom.self, from: Data(json.utf8))
        #expect(act(user(1), room: seated, host: true) == .tag(GamesRummyText.joined))
        #expect(act(user(2), room: seated, host: true) == .tag(GamesRummyText.invited))
        #expect(act(user(3), room: seated, host: true) == .invite(enabled: true), "거절한 사람은 다시 부를 수 있다")
        #expect(act(user(4), room: seated, host: true) == .invite(enabled: true))
        #expect(act(user(4, capable: false), room: seated, host: true) == .hidden)
        #expect(act(user(4), room: room(50, joined: 4), host: true) == .invite(enabled: false), "가득 찬 방에 초대가 나간다")
    }

    @Test("사람 자리: 모름 → 로딩 · 못 받음 → 실패 · 받고 빈 것 → 없음 · 줄 들고 실패 → 줄")
    func peoplePlaceholders() {
        typealias P = GamesRummyLobbyPlan
        #expect(P.peoplePlaceholder(lobby: nil, failed: false) == .loading)
        #expect(P.peoplePlaceholder(lobby: nil, failed: true) == .failed)
        #expect(P.peoplePlaceholder(lobby: lobby(), failed: false) == .empty)
        #expect(P.peoplePlaceholder(lobby: lobby(), failed: true) == .failed, "받은 뒤 실패하면 '없어요'가 거짓이다")
        #expect(P.peoplePlaceholder(lobby: lobby(users: [user(1)]), failed: true) == .rows, "들고 있는 줄을 실패로 지웠다")
        #expect(!P.showsJoinEmpty(lobby: nil, failed: false, count: 0))
        #expect(!P.showsJoinEmpty(lobby: lobby(), failed: true, count: 0))
        #expect(!P.showsJoinEmpty(lobby: lobby(), failed: false, count: 1))
        #expect(P.showsJoinEmpty(lobby: lobby(), failed: false, count: 0))
    }

    @Test("탭 글자: 받은 초대가 있으면 [사람] 탭이 말한다 · 순위 탭은 그대로")
    func tabTitles() {
        typealias P = GamesRummyLobbyPlan
        #expect(P.tabTitle(.people, inviteCount: 0) == GamesRummyText.usersTab)
        #expect(P.tabTitle(.people, inviteCount: 2) == "사람 · 초대 2")
        #expect(P.tabTitle(.ranking, inviteCount: 2) == GamesRummyText.rankTab)
    }

    @Test("머리 칸 전적: 로비를 못 받았으면 0판이라고 지어내지 않는다")
    func recordText() throws {
        typealias P = GamesRummyLobbyPlan
        #expect(P.recordText(nil) == GamesRummyText.unknownNumber)
        let me = try Self.decoder.decode(RummyLobbyMe.self, from: Data(#"{"games":12,"wins":5}"#.utf8))
        #expect(P.recordText(me) == "판 수 12 · 1등 5")
    }

    // MARK: - 방

    @Test("[시작]: 2명↑ · 비행 중 아님 · 다른 게임 아님 · 판돈 있음. 글자는 1명이면 '시작'")
    func startGate() {
        typealias P = GamesRummyRoomPlan
        #expect(P.canStart(joined: 2, stake: 5, balance: 5, isWorking: false, blockedBy: nil))
        #expect(P.canStart(joined: 2, stake: 5, balance: nil, isWorking: false, blockedBy: nil), "잔액을 모르는데 막았다")
        #expect(!P.canStart(joined: 1, stake: 5, balance: 5, isWorking: false, blockedBy: nil))
        #expect(!P.canStart(joined: 2, stake: 5, balance: 4, isWorking: false, blockedBy: nil))
        #expect(!P.canStart(joined: 2, stake: 5, balance: 5, isWorking: true, blockedBy: nil))
        #expect(!P.canStart(joined: 2, stake: 5, balance: 5, isWorking: false, blockedBy: .gomoku))
        #expect(P.startTitle(joined: 1) == GamesRummyText.start)
        #expect(P.startTitle(joined: 3) == "3명으로 시작")
        #expect(P.players(joined: 1) == 2 && P.players(joined: 4) == 4)
    }

    @Test("방 안내 서열: 모자람 > 손님 기다림 > 방장 혼자 > 없음 · 남은 초는 올림 · 60초 이하 급함")
    func roomHints() {
        typealias P = GamesRummyRoomPlan
        #expect(P.hint(amHost: true, joined: 3, stake: 5, balance: 1) == GamesRummyText.startBlockedShort)
        #expect(P.hint(amHost: false, joined: 3, stake: 5, balance: 9) == GamesRummyText.startHintGuest)
        #expect(P.hint(amHost: true, joined: 1, stake: 5, balance: 9) == GamesRummyText.startHintHost)
        #expect(P.hint(amHost: true, joined: 2, stake: 5, balance: 9) == nil)
        #expect(P.remainingSeconds(nil) == nil)
        #expect(P.remainingSeconds(59.2) == 60)
        #expect(P.remainingSeconds(0) == 0)
        #expect(P.isUrgent(seconds: 60) && !P.isUrgent(seconds: 61))
    }

    @Test("등수 분배 글자: 순수익이고 판돈 × 자리 안에서 합이 0 이다(2·3·4명)")
    func splitIsNet() {
        #expect(GamesRummyText.splitLines(players: 2, stake: 5) == ["1등 +5", "2등 −5"])
        #expect(GamesRummyText.splitLines(players: 3, stake: 5) == ["1등 +5", "2등 0", "3등 −5"])
        #expect(GamesRummyText.splitLines(players: 4, stake: 5) == ["1등 +10", "2등 0", "3·4등 −5"], "4명 3·4등이 합쳐지지 않았다")
        #expect(GamesRummyText.potTotal(stake: 5, players: 3) == "15")
        #expect(GamesRummyText.potFormula(stake: 5, players: 3) == "판돈 5 × 3명")
    }

    @Test("탁자 칸: 320 · 393 · 430pt 에서 의자끼리 · 의자와 가운데가 안 겹치고 판 안에 든다 · 의자가 탁자에 걸친다")
    func stageLayoutFits() {
        for screen in [CGFloat(320), 393, 430] {
            let layout = GamesRummyRoomStageLayout(width: screen - 32)   // 폰 좌우 여백 16
            let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
            let chairs = (0..<4).map(layout.chair)
            for (index, chair) in chairs.enumerated() {
                #expect(bounds.contains(chair), "\(screen): 의자 \(index) 가 판 밖")
                #expect(!chair.intersects(layout.center), "\(screen): 의자 \(index) 가 가운데 글자를 가린다")
                #expect(chair.intersects(layout.table), "\(screen): 의자 \(index) 가 탁자에서 떨어졌다")
                for other in chairs[(index + 1)...] { #expect(!chair.intersects(other), "\(screen): 의자 겹침") }
            }
            #expect(layout.table.contains(layout.center))
            #expect(layout.center.width >= 100, "\(screen): 상금 글자가 안 들어간다 \(layout.center.width)")
        }
        // 코어 순서 [아래, 왼, 위, 오른] — 나는 아래다.
        let layout = GamesRummyRoomStageLayout(width: 361)
        #expect(layout.chair(0).minY > layout.chair(2).minY && layout.chair(1).minX < layout.chair(3).minX)
    }

    @Test("의자 글자: 나·방장 · 앉음 · 답 기다림 — 세션 id 로 나를 고른다")
    func chairTags() throws {
        let me = Self.id(1), host = Self.id(2), other = Self.id(3), invited = Self.id(4)
        let json = #"{"id":"\#(Self.id(50).uuidString)","host":{"id":"\#(host.uuidString)"},"seats":[{"user_id":"\#(host.uuidString)","display_name":"방장님","state":"joined","seat_no":0},{"user_id":"\#(me.uuidString)","display_name":"나님","state":"joined","seat_no":1},{"user_id":"\#(other.uuidString)","display_name":"셋째","state":"joined","seat_no":2},{"user_id":"\#(invited.uuidString)","display_name":"넷째","state":"invited"}]}"#
        let room = try Self.decoder.decode(RummyRoom.self, from: Data(json.utf8))
        let chairs = GamesRummySeating.chairs(room: room, myUserID: me, myName: "무시", myAvatarURL: nil, myCharacter: nil)
        #expect(chairs.map(\.name) == ["나님", "셋째", "방장님", "넷째"], "내 다음 자리부터 시계 방향이 아니다")
        #expect(chairs.map(\.tag) == [GamesRummyText.me, GamesRummyText.seated, GamesRummyText.hostTag, GamesRummyText.waitingAnswer])
        #expect(chairs[3].dimmed)
    }

    // MARK: - 순위

    private func ranking(_ rows: [(games: Int, wins: Int)], me: (Int, Int, Int?)? = nil) throws -> RummyRanking {
        let rowsText = rows.enumerated().map { #"{"id":"\#(Self.id($0.offset + 1).uuidString)","games":\#($0.element.games),"wins":\#($0.element.wins),"rank":\#($0.offset + 1)}"# }
        let meText = me.map { #"{"games":\#($0.0),"wins":\#($0.1),"rank":\#($0.2.map(String.init) ?? "null")}"# } ?? "null"
        return try Self.decoder.decode(RummyRanking.self, from: Data(#"{"status":"ok","rows":[\#(rowsText.joined(separator: ","))],"me":\#(meText)}"#.utf8))
    }

    @Test("순위 자리: 줄 > 없음 > 실패 > 로딩 · 받고 실패하면 실패 · 줄 들고 실패면 줄 · 0판 제외 · 재정렬 금지")
    func rankingContent() throws {
        typealias P = GamesRummyRankingPlan
        #expect(P.content(ranking: nil, failed: false) == .loading)
        #expect(P.content(ranking: nil, failed: true) == .failed)
        #expect(P.content(ranking: try ranking([]), failed: false) == .empty)
        #expect(P.content(ranking: try ranking([(0, 0)]), failed: false) == .empty, "0판인 사람이 순위에 꼈다")
        #expect(P.content(ranking: try ranking([(1, 0)]), failed: true) == .rows, "들고 있는 줄을 실패로 지웠다")
        let held = try ranking([(9, 5), (0, 0), (3, 1)])
        #expect(P.held(held).map(\.id) == [Self.id(1), Self.id(3)])
    }

    @Test("순위 접기: 5줄 · 6줄부터 토글 · 100줄 상한")
    func rankingCollapse() throws {
        typealias P = GamesRummyRankingPlan
        let five = try ranking(Array(repeating: (1, 0), count: 5))
        #expect(!P.showsToggle(five))
        let many = try ranking(Array(repeating: (1, 0), count: 101))
        #expect(P.showsToggle(many))
        #expect(P.visible(many, isExpanded: false).count == 5)
        #expect(P.visible(many, isExpanded: true).count == 100)
    }

    @Test("내 순위: 로비 전적과 어긋나면 안 그린다 · 0판 안 그린다 · 로비 모르면 그린다")
    func rankingMine() throws {
        typealias P = GamesRummyRankingPlan
        let held = try ranking([(9, 5)], me: (12, 5, 2))
        func me(_ games: Int?, _ wins: Int?) throws -> RummyLobbyMe {
            let text = #"{"games":\#(games.map(String.init) ?? "null"),"wins":\#(wins.map(String.init) ?? "null")}"#
            return try Self.decoder.decode(RummyLobbyMe.self, from: Data(text.utf8))
        }
        #expect(P.myRank(ranking: held, lobbyMe: try me(12, 5))?.rank == 2)
        #expect(P.myRank(ranking: held, lobbyMe: nil)?.rank == 2)
        #expect(P.myRank(ranking: held, lobbyMe: try me(nil, nil))?.rank == 2)
        #expect(P.myRank(ranking: held, lobbyMe: try me(13, 5)) == nil, "한쪽이 늦었는데 섞어 그렸다")
        #expect(P.myRank(ranking: try ranking([], me: (0, 0, nil)), lobbyMe: nil) == nil)
        #expect(P.myRank(ranking: nil, lobbyMe: nil) == nil)
    }

    @Test("순위 조회 건수: 사람 탭 0건 · 순위 탭 값 없으면 1건 · 값 있으면 0건(주기에 맡긴다) · 방 단계 0건")
    func rankingRequests() async {
        let harness = RummyWireHarness(label: "v1016-rank-tab")
        harness.serveLobby()
        await harness.signIn()
        #expect(harness.count("rummy_ranking") == 0)
        GamesRummyRankingPlan.refreshIfNeeded(harness.rummy, tab: .people)
        await harness.barrier()
        #expect(harness.count("rummy_ranking") == 0, "사람 탭에서 안 보는 표를 긁었다")
        GamesRummyRankingPlan.refreshIfNeeded(harness.rummy, tab: .ranking)
        #expect(await waits.wait { harness.count("rummy_ranking") == 1 }, "순위 탭을 골랐는데 조회가 안 나갔다")
        #expect(await waits.wait { harness.rummy.ranking != nil })
        GamesRummyRankingPlan.refreshIfNeeded(harness.rummy, tab: .ranking)
        await harness.barrier()
        #expect(harness.count("rummy_ranking") == 1, "값을 들고 있는데 또 긁었다")
        await harness.tearDown()
    }

    @Test("조회 실패 깃발: 로비·순위 5xx 면 서고 다음 성공에 내려간다 · 안내줄로 안 샌다 · 리셋이 지운다")
    func loadFailureFlags() async {
        let harness = RummyWireHarness(label: "v1016-load-failed")
        harness.serveLobby()
        harness.server.setDefault("rummy_lobby", json: #"{"message":"boom"}"#, status: 500)
        harness.server.setDefault("rummy_ranking", json: #"{"message":"boom"}"#, status: 500)
        await harness.signIn()
        await harness.rummy.refreshLobby()
        await harness.rummy.loadRanking()
        #expect(harness.rummy.lobbyLoadFailed && harness.rummy.rankingLoadFailed)
        #expect(harness.rummy.lobby == nil && harness.rummy.ranking == nil)
        #expect(harness.rummy.availability == .available, "일시 실패가 '곧 열려요'가 됐다")
        #expect(harness.rummy.notice == nil, "순위·로비 조회 실패가 안내줄로 샜다")
        #expect(GamesRummyLobbyPlan.peoplePlaceholder(lobby: harness.rummy.lobby, failed: harness.rummy.lobbyLoadFailed) == .failed)

        harness.serveLobby()
        await harness.rummy.refreshLobby()
        await harness.rummy.loadRanking()
        #expect(!harness.rummy.lobbyLoadFailed && !harness.rummy.rankingLoadFailed, "성공했는데 실패 깃발이 남았다")

        harness.server.setDefault("rummy_lobby", json: #"{"message":"boom"}"#, status: 500)
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.lobbyLoadFailed)
        #expect(harness.rummy.lobby != nil, "실패가 들고 있던 로비를 지웠다")
        harness.rummy.reset()
        #expect(!harness.rummy.lobbyLoadFailed && !harness.rummy.rankingLoadFailed, "리셋이 깃발을 남겼다")
        await harness.tearDown()
    }

    @Test("거절 응답: 업데이트 필요는 availability 로 가고 실패 깃발을 안 세운다 · 그 밖의 거절은 실패 깃발")
    func refusedLobby() async {
        let harness = RummyWireHarness(label: "v1016-load-refused")
        harness.serveLobby()
        harness.server.setDefault("rummy_lobby", json: #"{"status":"unsupported_client"}"#)
        await harness.signIn()
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.availability == .updateRequired)
        #expect(!harness.rummy.lobbyLoadFailed)
        #expect(GamesRummyUnavailable.title(harness.rummy.availability) == RummyNoticeText.updateRequired)
        harness.server.setDefault("rummy_lobby", json: #"{"status":"rejected"}"#)
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.lobbyLoadFailed)
        await harness.tearDown()
    }

    @Test("서버에 함수가 없다(PGRST202): 실패 깃발이 아니라 availability · 데모 장면 본문이 실제 판정을 지난다")
    func missingServer() async {
        let harness = RummyWireHarness(label: "v1016-load-missing")
        harness.serveLobby()
        let fixture = MobileDemoFixtures.load().response(
            for: MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/rummy_lobby", query: "", headers: [:], bodyText: "{}"),
            scenario: MobileDemoRummyRoute.Scene.lobbyMissing.scenario)
        harness.server.setDefault("rummy_lobby", json: String(decoding: fixture.body, as: UTF8.self), status: fixture.status)
        await harness.signIn()
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.availability == .serverMissing, "데모 장면이 '곧 열려요'를 못 세운다")
        #expect(!harness.rummy.lobbyLoadFailed)
        #expect(GamesRummyUnavailable.title(harness.rummy.availability) == RummyNoticeText.unavailable)
        await harness.tearDown()
    }

    // MARK: - 초대 줄이 실제로 내는 요청

    @Test("방 없이 [초대]: 고른 판돈·공개 여부로 방을 만들고 그 사람을 부른다(요청 본문)")
    func inviteWithoutRoomCreatesThenInvites() async throws {
        let harness = RummyWireHarness(label: "v1016-invite-queue")
        harness.serveLobby()
        let nowMs = harness.nowMs
        let state = #"{"status":"ok","server_now_ms":\#(nowMs),"match_id":"\#(RummyWireHarness.matchID)","state":\#(RummyWireJSON.state(nowMs: nowMs, status: "forming", mySeatState: "joined", turnSeat: 0))}"#
        harness.server.setDefault("rummy_create", json: state)
        harness.server.setDefault("rummy_invite", json: state)
        await harness.signIn()
        await harness.rummy.refreshLobby()
        let queue = RummyInviteQueue()
        harness.rummy.selectedStake = 10
        harness.rummy.createPublic = true
        queue.invite(Self.id(77), store: harness.rummy)
        #expect(await waits.wait { harness.count("rummy_create") == 1 }, "방이 안 만들어졌다")
        let body = try #require(harness.server.requests("rummy_create").first?.bodyText)
        #expect(body.contains(#""p_stake":10"#), "고른 판돈이 안 실렸다: \(body)")
        #expect(body.contains(#""p_public":true"#), "공개 여부가 안 실렸다: \(body)")
        #expect(await waits.wait { !harness.rummy.isWorking && harness.rummy.match != nil })
        queue.pump(harness.rummy)
        #expect(await waits.wait { harness.count("rummy_invite") == 1 }, "방이 섰는데 부르지 않았다")
        #expect(harness.server.requests("rummy_invite").first?.bodyText.lowercased().contains(Self.id(77).uuidString.lowercased()) == true)
        #expect(queue.pending.isEmpty)
        await harness.tearDown()
    }

    @Test("방 만들기가 거절되면(모자람) 줄을 버리고 초대 0건 · 안내줄이 말한다")
    func refusedCreateDropsQueue() async {
        let harness = RummyWireHarness(label: "v1016-invite-refused")
        harness.serveLobby()
        harness.server.setDefault("rummy_create", json: #"{"status":"insufficient","need":10,"have":2,"ruby_balance":2}"#)
        await harness.signIn()
        await harness.rummy.refreshLobby()
        let queue = RummyInviteQueue()
        harness.rummy.selectedStake = 10
        queue.invite(Self.id(77), store: harness.rummy)
        #expect(await waits.wait { harness.count("rummy_create") == 1 })
        #expect(await waits.wait { !harness.rummy.isWorking && harness.rummy.notice != nil })
        queue.pump(harness.rummy)
        #expect(queue.pending.isEmpty, "거절됐는데 줄이 남았다")
        #expect(harness.count("rummy_invite") == 0)
        #expect(harness.rummy.notice == RummyNoticeText.status(.insufficient, for: .create))
        await harness.tearDown()
    }

    // MARK: - 데모 장면

    @Test("데모 장면: 새 장면이 코어로 서는 값이 표대로다(빈 로비 · 실패 · 모자람 · 손님 방 · 업데이트 · 서버 없음)")
    func demoScenes() async {
        typealias S = MobileDemoRummyRoute.Scene
        let index = MobileDemoFixtures.load()
        func response(_ rpc: String, _ scene: S, id: UUID? = nil) -> MobileStubResponse {
            var body = #""p_protocol":1"#
            if let id { body += #","p_match_id":"\#(id.uuidString.lowercased())""# }
            let request = MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)", query: "",
                                            headers: [:], bodyText: "{\(body)}")
            return index.response(for: request, scenario: scene.scenario)
        }
        func lobby(_ scene: S) -> RummyLobby? { try? Self.decoder.decode(RummyLobby.self, from: response("rummy_lobby", scene).body) }

        #expect(lobby(.lobbyEmpty)?.users?.isEmpty == true && lobby(.lobbyEmpty)?.invites?.isEmpty == true)
        #expect(lobby(.lobbyShort)?.me?.rubyBalance == 2)
        #expect(lobby(.lobbyPeople)?.users?.count == 8 && lobby(.lobbyPeople)?.publicRooms?.isEmpty == true)
        let busy = GamesRummyLobbyPlan.people(lobby(.lobbyBusy)?.users ?? [])
        #expect(busy.ready.isEmpty && busy.busy.count == 2 && busy.outdated.count == 2)
        #expect(response("rummy_lobby", .lobbyFailed).status == 500)
        #expect(response("rummy_ranking", .rankingFailed).status == 500)
        #expect(lobby(.lobbyUpdate)?.status == .unsupportedClient)
        #expect(response("rummy_lobby", .lobbyMissing).status == 404)
        // 손님 방: 내가 방장이 아니고 me.room 과 state 가 같은 방이다.
        let room = lobby(.roomGuest)?.me?.room
        #expect(room?.id == S.guestRoomID)
        let action = try? Self.decoder.decode(RummyActionResponse.self, from: response("rummy_state", .roomGuest, id: S.guestRoomID).body)
        #expect(action?.state?.id == S.guestRoomID && action?.state?.status == .forming)
        #expect(action?.state?.hostId?.uuidString.lowercased() != MobileDemo.userID)
        #expect(action?.state?.mySeatNo == 1)
        #expect(MobileDemoRummyRoute(demoRoute: "games/rummy/ranking/failed")?.lobbyTab == .ranking)
        #expect(S.roomGuest.engages && !S.lobbyEmpty.engages)
    }
}
