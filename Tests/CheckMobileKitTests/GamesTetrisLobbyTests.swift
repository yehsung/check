@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **1:1 테트리스 로비·입구·순위**(1.0.11 레인 B)의 못. 폰 뷰는 맥 스위트가 한 줄도 못 보므로
// (저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 셋으로 증명한다 — ① 값·스토어 결과, ② 소스 계약 글자,
// ③ `ios/scripts/build-sim.sh` 컴파일(여기서는 못 잰다).
//
// 재는 것 여덟 — **전부 결과**다(함수를 불렀는지가 아니다):
//  ① 판돈을 **안 고르면 신청이 없다**(요청이 나가는 마지막 문이 nil 이고, 뷰는 그 nil 에서 돌아선다).
//  ② **구버전 상대는 신청이 꺼진다**(서버 `capable` 이 nil 로 와도 꺼진다 — 모르는 상대는 불가다).
//  ③ **차단한 사람이 목록에서 빠진다**(차단 시트가 약속한 세 줄 중 한 줄이 눈앞에서 거짓이 되지 않게).
//  ④ **막힌 입구가 두 줄을 낸다**(왜 + 언제 풀리는지). 한 줄만 그리면 사용자가 기다릴 끝을 모른다.
//  ⑤ **카드 칩이 우선순위대로** 바뀐다(차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본).
//  ⑥ **순위 조회가 로비에서만** 나간다(판 중에 긁지 않고, 상대 고르기 탭에서도 안 긁는다).
//  ⑦ **데모 라우트 아홉이 각자 장면을 연다**(라우트가 있다 ≠ 화면이 뜬다 — 체스 결함 D6 의 교훈).
//  ⑧ `games/tetris` **한 토막은 솔로** 미니게임으로 간다(1:1 쪽이 가로채면 솔로 데모가 조용히 사라진다).
//
// 하네스는 **남의 것을 쓴다**: 소켓 붙은 로그인 앱 모델 `TetrisWireHarness`(레인 A ·
// `GamesTetrisDuelWiringTests.swift`)와 데모 픽스처 `MobileDemoFixtures`(레인 D). 고치지 않았다.
@MainActor
@Suite(.serialized) struct GamesTetrisLobbyTests {
    private let waits = GamesWaitBudget()

    private nonisolated static let mine = TetrisWireHarness.userID
    private nonisolated static let rival = TetrisWireHarness.rival

    // MARK: - 도우미

    /// 테트리스 화면·옆 게임이 부르는 조회를 스텁에 걸어 둔다(레인 A 의 `serve` 와 같은 모양 · 남의 파일이라 베꼈다).
    private func serve(_ harness: TetrisWireHarness, incoming: [String] = [], outgoing: String? = nil,
                       users: [String]? = nil) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("tetris_lobby", json: TetrisWireJSON.lobby(
            nowMs: nowMs, incoming: incoming, outgoing: outgoing, users: users))
        harness.server.setDefault("tetris_state", json: TetrisWireJSON.stateEnvelope(nowMs: nowMs))
        harness.server.setDefault("tetris_ranking", json: TetrisWireJSON.ranking(nowMs: nowMs))
        harness.server.setDefault("tetris_report", json: TetrisWireJSON.stateEnvelope(nowMs: nowMs, meReady: true))
        harness.server.setDefault("chess_lobby", json: #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"initial_ms":600000,"increment_ms":3000,"grace_ms":2000,"invite_ttl_seconds":60,"ruby_balance":100,"me":{"ruby_balance":100,"wins":0,"losses":0,"draws":0,"active_match_id":null,"outgoing_match_id":null,"incoming_match_id":null},"users":[],"matches":[]}"#)
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
    }

    private nonisolated static func user(_ id: String, capable: Bool = true, inMatch: Bool = false,
                                         focused: Bool = false, working: Bool = true) -> TetrisDuelUser {
        TetrisDuelUser(id: id, displayName: "이름-\(id)", avatarURL: nil, characterID: nil,
                       isWorking: working, isCapable: capable, inMatch: inMatch, isFocused: focused)
    }

    private nonisolated static func invite(_ id: String, stake: Int = 5) -> TetrisDuelInvite {
        TetrisDuelInvite(id: id, peer: user(rival), stake: stake,
                         expiresAt: Date(timeIntervalSince1970: 4_000_000_000))
    }

    private nonisolated static func tetrisMatch(finished: Bool = false) -> TetrisDuelMatchState {
        TetrisDuelMatchState(
            id: "m-lobby-1", stake: 5, seed: 7, opponent: user(rival), acceptedAt: nil, readyDeadline: nil,
            startAt: nil, maxEnd: nil, meReady: false, opponentBoard: .empty, isFinished: finished,
            outcome: finished ? .won : nil, endReason: finished ? .topout : nil, rubyDelta: finished ? 4 : nil,
            finishedAt: nil)
    }

    private nonisolated static func gomokuMatch() -> GomokuMatchState {
        GomokuMatchState(
            id: "g-lobby-1", stake: 5, myColor: .black,
            opponent: GomokuUser(id: "p-gomoku", displayName: "구름빵", avatarURL: nil, characterID: nil,
                                 isWorking: true, isCapable: true, inMatch: true),
            board: GomokuBoard(), lastMove: nil, moveCount: 0, turn: .black, deadline: nil,
            isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false)
    }

    // MARK: - 1. ★ 판돈을 안 고르면 신청이 없다

    @Test("판돈을 **안 고르면** 신청을 낼 수 없다 · 고른 뒤에도 잔액·다른 판·보낸 신청·차단이 각각 막는다")
    func theChallengeNeedsAChosenStake() {
        // 없으면: 시트가 열린 그 순간 [신청]이 눌려 **아무 판돈으로** 요청이 나간다(어느 값이 나갈지 화면이
        // 모른다). 그래서 이 문이 nil 인 것을 **판돈 셋 전부**에서 잰다 — 버튼 비활성이 아니라 그 값이다.
        let store = TetrisDuelStore()
        #expect(GamesTetrisDuelStakeSend.sendable(nil, store: store, balance: 100, blockedBy: nil) == nil,
                "★ 아무것도 안 골랐는데 신청을 낼 수 있다 — 골라야 [신청]이 생긴다는 결정이 깨졌다")
        for stake in TetrisDuelStake.allCases {
            #expect(GamesTetrisDuelStakeSend.sendable(stake, store: store, balance: 100, blockedBy: nil) == stake,
                    "고른 판돈을 못 낸다: \(stake.rawValue)")
        }
        // 기준선이 달라야 한다 — 막는 축마다 **같은 입력에서** 답이 뒤집힌다.
        #expect(GamesTetrisDuelStakeSend.sendable(.ten, store: store, balance: 9, blockedBy: nil) == nil,
                "루비가 모자란데 신청을 낸다")
        #expect(GamesTetrisDuelStakeSend.sendable(.ten, store: store, balance: nil, blockedBy: nil) == .ten,
                "잔액을 **모르는데** 막았다 — 서버가 거절하면 그때 안내한다(0.3.29 규칙)")
        #expect(GamesTetrisDuelStakeSend.sendable(.three, store: store, balance: 100, blockedBy: .gomoku) == nil,
                "오목 판이 흐르는데 테트리스 신청을 낸다 — 그 판이 15초 침묵으로 진다")
        store.isBusy = true
        #expect(GamesTetrisDuelStakeSend.sendable(.three, store: store, balance: 100, blockedBy: nil) == nil,
                "요청이 도는 중인데 또 낸다")
        store.isBusy = false
        store.outgoing = Self.invite("i-1")
        #expect(GamesTetrisDuelStakeSend.sendable(.three, store: store, balance: 100, blockedBy: nil) == nil,
                "보낸 신청이 있는데 또 낸다(서버 `already_pending`)")
        store.outgoing = nil
        store.match = Self.tetrisMatch()
        #expect(GamesTetrisDuelStakeSend.sendable(.three, store: store, balance: 100, blockedBy: nil) == nil,
                "내 판이 흐르는데 신청을 낸다")
        store.match = nil

        // 고르기 규약: 다시 누르면 해제(= 아무것도 안 골라진 상태로 돌아간다 → 신청이 사라진다).
        #expect(GamesTetrisStakeSelection.toggled(current: nil, tapped: .five) == .five)
        #expect(GamesTetrisStakeSelection.toggled(current: .five, tapped: .five) == nil)
        #expect(GamesTetrisStakeSelection.toggled(current: .five, tapped: .ten) == .ten)
        // 판돈 표의 주인은 서버다(3·5·10) — 앱 값이 갈리면 거절이 진실이다.
        #expect(TetrisPhoneText.stakes == [3, 5, 10])
    }

    // MARK: - 2. ★ 구버전·대결 중·집중 상대는 신청이 꺼진다

    @Test("상대 한 줄: 신청 가능 집합이 코어 `canBeChallenged` 와 **같고**, 부제는 늘 근무 축을 말한다(16 갈래 전수)")
    func theOpponentRowMatchesTheCoreGate() {
        // 없으면: 두 자리가 따로 고르던 체스 결함이 되살아난다 — 한 줄이 같은 문장을 두 번 말하고(버튼·부제)
        // 초록 점이 켜진 사람의 "근무 중" 이 사라진다(헤드리스 실측 D4). 그리고 버튼이 눌리는 집합이
        // 서버 판정과 갈리면 눌린 신청이 전부 거절된다.
        var buttons: Set<String> = []
        for capable in [true, false] {
            for inMatch in [true, false] {
                for focused in [true, false] {
                    for working in [true, false] {
                        let user = Self.user("u", capable: capable, inMatch: inMatch, focused: focused,
                                             working: working)
                        let row = TetrisPhoneText.opponentRow(for: user)
                        buttons.insert(row.buttonTitle)
                        #expect((row.buttonTitle == TetrisPhoneText.challenge) == user.canBeChallenged,
                                "버튼과 코어 게이트가 갈렸다(capable=\(capable) inMatch=\(inMatch) focus=\(focused)): \(row)")
                        // 부제는 **늘 근무 축으로 시작한다** — 막힌 까닭이 그 축을 덮으면 초록 점과 글자가 어긋난다.
                        let work = working ? TetrisPhoneText.working : TetrisPhoneText.notWorking
                        #expect(row.subtitle.hasPrefix(work), "부제가 근무 축을 안 말한다: \(row.subtitle)")
                        // 한 줄에서 **같은 문장을 두 번** 말하지 않는다.
                        #expect(!row.subtitle.hasSuffix(row.buttonTitle) || row.subtitle == work,
                                "부제와 버튼이 같은 말을 한다: \(row)")
                    }
                }
            }
        }
        // 서열이 **버튼 넷 전부**를 실제로 낸다(하나라도 안 나오면 그 갈래가 글자 없이 회색 알약이 된다).
        #expect(buttons == [TetrisPhoneText.challenge, TetrisPhoneText.needsUpdate,
                            TetrisPhoneText.inMatch, TetrisPhoneText.focused], "\(buttons.sorted())")
        // 겹치는 갈래: 버튼이 못 말한 축이 부제 꼬리로 간다(축 하나가 사라지지 않게).
        let both = TetrisPhoneText.opponentRow(for: Self.user("u", capable: false, inMatch: true))
        #expect(both.buttonTitle == TetrisPhoneText.needsUpdate)
        #expect(both.subtitle.contains(TetrisPhoneText.inMatch), "대결 중이 통째로 사라졌다: \(both.subtitle)")
    }

    @Test("로비 목록은 **서버 픽스처 그대로** 그리고, 구버전 상대의 [신청]은 꺼진다 — 차단한 사람은 목록에서 빠진다")
    func theLobbyListFiltersBlocksAndGatesOldClients() async {
        let harness = TetrisWireHarness(label: "tetris-lobby-list")
        serve(harness, users: [
            TetrisWireJSON.user(Self.rival, "테트라이벌"),
            TetrisWireJSON.user("p-old", "구버전", capable: false),
            TetrisWireJSON.user("p-unknown", "모르는사람", capable: nil),
            TetrisWireJSON.user("p-busy", "대결중", inMatch: true),
            TetrisWireJSON.user("p-focus", "집중중", focused: true),
            TetrisWireJSON.user("p-blocked", "차단한사람")
        ])
        await harness.signIn()
        harness.games.tetrisScreenDidAppear()
        #expect(await waits.wait { harness.games.tetrisLobbyUsers.count == 6 }, "로비 응답이 안 왔다")

        let gate = { (id: String) -> Bool in
            guard let user = harness.games.tetrisLobbyUsers.first(where: { $0.id == id }) else { return false }
            return GamesTetrisDuelChallengeGate.isEnabled(user: user, store: harness.tetris,
                                                          blockedBy: harness.games.tetrisEntryBlock)
        }
        #expect(gate(Self.rival), "신청할 수 있는 상대인데 버튼이 꺼졌다")
        #expect(!gate("p-old"), "★ 구버전 상대에게 신청이 나간다 — 서버가 `target_outdated` 로 거절한다")
        #expect(!gate("p-unknown"),
                "★ `capable` 이 **nil** 로 온 상대에게 신청이 나간다 — 모르는 상대는 불가로 그려야 한다")
        #expect(!gate("p-busy"), "대결 중인 상대에게 신청이 나간다(`target_busy`)")
        #expect(!gate("p-focus"), "집중 모드인 상대에게 신청이 나간다(`target_focused`)")

        // 차단: 화면이 읽는 자리만 거른다(코어 목록은 서버 답 그대로 — 차단이 실패하면 그대로 돌아온다).
        let order = harness.tetris.users.map(\.id)
        harness.model.messages.hiddenBlockedPeerIDs = ["p-blocked"]
        #expect(harness.games.tetrisLobbyUsers.count == 5, "★ 차단한 사람이 [신청] 버튼과 함께 그대로 서 있다")
        #expect(!harness.games.tetrisLobbyUsers.contains { $0.id == "p-blocked" })
        #expect(harness.tetris.users.count == 6, "코어 목록까지 지웠다 — 차단이 실패했을 때 돌아올 자리가 없다")
        // ★ **정렬하지 않는다**: 코어가 서버와 같은 규칙으로 이미 맞췄다(화면이 다시 정렬하면 두 규칙이 갈린다).
        #expect(harness.games.tetrisLobbyUsers.map(\.id) == order.filter { $0 != "p-blocked" },
                "화면 목록이 코어 순서를 바꿨다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 3. ★ 카드 서열과 막힌 입구 두 줄

    @Test("게임 탭 카드의 칩·보조 줄이 **서열대로** 바뀐다: 차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본")
    func theCardLineFollowsThePriority() async {
        // 없으면: 삼항 둘이 서열을 두 벌로 들고 있어 한쪽만 고쳐지고 그 상태가 **초록인 채로** 남는다
        // (체스 카드가 그 꼴이라 맥 스위트가 서열을 못 쟀다). 그래서 서열을 열거 한 값으로 잰다.
        let harness = TetrisWireHarness(label: "tetris-card-line")
        serve(harness)
        await harness.signIn()
        let games = harness.games
        let tetris = harness.tetris
        // 로그인 직후 로비 조회가 한 번 나가므로 그 응답이 전적을 채우기 전에 기준을 잡는다.
        #expect(await waits.wait { tetris.hasLoadedLobby }, "로비 응답이 안 왔다")
        tetris.record = nil
        tetris.incoming = []
        tetris.outgoing = nil

        // ⑥ 기본: 칩도 보조 줄 재료도 없다 → **할 일**을 말한다.
        #expect(GamesTetrisDuelCard.line(games) == .idle)
        #expect(GamesTetrisDuelCard.chip(games) == nil)
        #expect(GamesTetrisDuelCard.detail(games) == TetrisPhoneText.idleLine)

        // ⑤ 전적을 알면 전적.
        tetris.record = TetrisDuelRecord(wins: 3, losses: 1, draws: 0)
        #expect(GamesTetrisDuelCard.line(games) == .record)
        #expect(GamesTetrisDuelCard.chip(games) == nil)
        #expect(GamesTetrisDuelCard.detail(games) == TetrisPhoneText.recordTitle + " 3승 1패 0무")

        // ④ 보낸 신청이 전적을 **이긴다**(시간이 흐르는 것이 먼저다).
        tetris.outgoing = Self.invite("i-out")
        #expect(GamesTetrisDuelCard.line(games) == .outgoing)
        #expect(GamesTetrisDuelCard.detail(games) == TetrisPhoneText.outgoingLine)

        // ③ 받은 신청이 보낸 신청을 이긴다 — 칩이 생긴다(폰엔 배너도 배지도 없으니 이 칩이 알리는 유일한 자리다).
        tetris.incoming = [Self.invite("i-in")]
        #expect(GamesTetrisDuelCard.line(games) == .incoming)
        #expect(GamesTetrisDuelCard.chip(games) == TetrisPhoneText.incomingChip)
        #expect(GamesTetrisDuelCard.detail(games) == TetrisPhoneText.recordTitle + " 3승 1패 0무")

        // ② 내 판이 받은 신청을 이긴다(판돈이 걸려 있다). 끝난 판은 판이 아니다.
        tetris.match = Self.tetrisMatch(finished: true)
        #expect(GamesTetrisDuelCard.line(games) == .incoming, "끝난 판이 '대결 중' 칩을 세웠다")
        tetris.match = Self.tetrisMatch()
        #expect(GamesTetrisDuelCard.line(games) == .activeMatch)
        #expect(GamesTetrisDuelCard.chip(games) == GamesText.activeMatchChip)

        // ① 차단이 전부를 이긴다 — 그리고 **두 자리를 다 그린다**(왜 + 언제 풀리는지).
        harness.model.gomoku.match = Self.gomokuMatch()
        #expect(games.tetrisEntryBlock == .gomoku, "삼각 차단이 안 걸렸다 — 이 테스트의 전제가 깨졌다")
        #expect(GamesTetrisDuelCard.line(games) == .blocked)
        let chip = GamesTetrisDuelCard.chip(games)
        let detail = GamesTetrisDuelCard.detail(games)
        #expect(chip == ChessPhoneText.busyTitle(.gomoku), "막힌 칩이 두는 판을 말하지 않는다: \(chip ?? "nil")")
        #expect(detail == ChessPhoneText.busyHint(playing: .gomoku, blocked: .tetris),
                "★ 막힌 카드가 **언제 풀리는지**를 안 말한다: \(detail ?? "nil")")
        #expect(detail?.contains("1:1 테트리스") == true, "막힌 입구가 **자기 이름**을 말하지 않는다: \(detail ?? "nil")")
        // 로비 안내도 같은 짝이다 — 한 칸 **두 줄**.
        let notice = ChessPhoneText.entryBlockNotice(playing: .gomoku, blocked: .tetris)
        #expect(notice?.components(separatedBy: "\n").count == 2, "로비 안내가 두 줄이 아니다: \(notice ?? "nil")")

        // 서열 열거의 **여섯 갈래가 다 닿는다**(닿지 않는 갈래가 있으면 그 자리는 글자 없이 빈다).
        #expect(GamesTetrisDuelCard.Line.allCases.count == 6)
        harness.model.gomoku.match = nil
        tetris.match = nil
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 4. ★ 순위 조회는 로비에서만

    @Test("순위 조회는 **순위 탭 · 로비 단계**에서만 나간다 — 상대 고르기 탭·판 중에는 0건이다")
    func theRankingQueryOnlyLeavesFromTheLobbyTab() async {
        // 없으면: ① 판이 흐르는 동안 순위를 긁어 판 보고와 연결을 다투고(코어 폴링은 `phase == .lobby` 에서만
        // 긁으므로 두 자리가 갈린다), ② 상대 고르기 탭에서 1분마다 **안 보는 표**를 당긴다.
        let harness = TetrisWireHarness(label: "tetris-rank-tab")
        serve(harness)
        await harness.signIn()
        harness.games.tetrisScreenDidAppear()
        #expect(await waits.wait { harness.count("tetris_ranking") >= 1 }, "화면이 떴는데 순위가 안 나갔다")
        let base = harness.count("tetris_ranking")

        // 상대 고르기 탭: 스로틀을 풀어도 **0건**이다(탭을 안 봤으니 당길 까닭이 없다).
        harness.tetris.lastRankingRequestAt = .distantPast
        #expect(!GamesTetrisDuelRankingPlan.shouldRefresh(harness.tetris, tab: .opponents))
        GamesTetrisDuelRankingPlan.refreshIfNeeded(harness.tetris, tab: .opponents)
        await harness.barrier()
        await baseYield(turns: 10)
        await harness.barrier()
        #expect(harness.count("tetris_ranking") == base,
                "상대 고르기 탭에서 순위 조회가 \(harness.count("tetris_ranking") - base)건 나갔다")

        // 순위 탭 + 로비: 한 건 나간다(기준선이 갈린다).
        #expect(GamesTetrisDuelRankingPlan.shouldRefresh(harness.tetris, tab: .ranking))
        GamesTetrisDuelRankingPlan.refreshIfNeeded(harness.tetris, tab: .ranking)
        #expect(await waits.wait { harness.count("tetris_ranking") == base + 1 },
                "순위 탭을 골랐는데 조회가 안 나갔다")
        let afterTab = harness.count("tetris_ranking")

        // 60초 스로틀: 곧바로 또 고르면 **안 나간다**(코어가 쥔 그 가드를 뷰가 우회하지 않는다).
        GamesTetrisDuelRankingPlan.refreshIfNeeded(harness.tetris, tab: .ranking)
        await harness.barrier()
        await baseYield(turns: 10)
        await harness.barrier()
        #expect(harness.count("tetris_ranking") == afterTab, "스로틀을 우회했다")

        // 판 중: 같은 손짓에 **0건**이다.
        let text = TetrisWireJSON.stateEnvelope(nowMs: harness.serverNowMs, startAtMs: harness.serverNowMs - 1_000,
                                                meReady: true)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try? decoder.decode(TetrisActionResponse.self, from: Data(text.utf8))
        #expect(harness.tetris.applyState(try! #require(payload?.state)) == .applied, "판을 못 세웠다")
        #expect(harness.tetris.phase != .lobby, "판 단계가 아니면 이 단언이 공허하다")
        harness.tetris.lastRankingRequestAt = .distantPast
        #expect(!GamesTetrisDuelRankingPlan.shouldRefresh(harness.tetris, tab: .ranking),
                "★ 판이 흐르는데 순위 조회를 허락한다")
        GamesTetrisDuelRankingPlan.refreshIfNeeded(harness.tetris, tab: .ranking)
        await harness.barrier()
        await baseYield(turns: 10)
        await harness.barrier()
        #expect(harness.count("tetris_ranking") == afterTab,
                "판 중에 순위 조회가 \(harness.count("tetris_ranking") - afterTab)건 나갔다")

        // 주 스위치가 꺼지면(옛 기기 겹) 로비 단계에서도 0건이다.
        harness.tetris.rankingEnabled = false
        #expect(!GamesTetrisDuelRankingPlan.shouldRefresh(harness.tetris, tab: .ranking))
        harness.tetris.rankingEnabled = true
        await harness.tearDown()
    }

    @Test("순위 판정: 0판은 빠지고 · 행을 들고 있으면 '곧 열려요'로 덮지 않고 · 전적이 어긋난 내 줄은 안 그린다")
    func theRankingPlanKeepsWhatItHolds() {
        let store = TetrisDuelStore()
        store.rankingEnabled = true
        // 아직 모른다 → 탭이 통째로 비면 안 되므로 로딩이다(체스 절처럼 접지 않는다 — 탭 하나가 이 뷰다).
        #expect(GamesTetrisDuelRankingPlan.content(store) == .loading)
        store.rankingLoadFailed = true
        #expect(GamesTetrisDuelRankingPlan.content(store) == .failed)
        store.rankingLoadFailed = false
        store.hasLoadedRanking = true
        #expect(GamesTetrisDuelRankingPlan.content(store) == .empty)

        // 0판인 사람만 왔다 → 여전히 "없다"다(D11 — 서버가 걸러 주지만 화면이 다시 지킨다).
        let zero = TetrisDuelRankEntry(id: "z", rank: 1, user: Self.user("z"), wins: 0, losses: 0, draws: 0, points: 0)
        let real = TetrisDuelRankEntry(id: Self.mine, rank: 2, user: Self.user(Self.mine),
                                       wins: 6, losses: 4, draws: 1, points: 2)
        store.ranking = TetrisDuelRankingBoard(entries: [zero], me: nil, recordSince: nil)
        #expect(GamesTetrisDuelRankingPlan.held(store).isEmpty, "★ 0판 줄이 순위표에 끼었다")
        #expect(GamesTetrisDuelRankingPlan.content(store) == .empty)

        // ★ 행을 들고 있으면 `rankingUnavailable` 깃발이 남아 있어도 **덮지 않는다**(지난 값을 지우지 않는다).
        store.ranking = TetrisDuelRankingBoard(entries: [real, zero], me: nil, recordSince: nil)
        store.rankingUnavailable = true
        #expect(GamesTetrisDuelRankingPlan.content(store) == .rows, "★ 받아 둔 행을 버리고 '곧 열려요'를 말한다")
        #expect(GamesTetrisDuelRankingPlan.held(store).map(\.id) == [Self.mine], "순서를 바꾸거나 0판을 남겼다")
        // 행이 없을 때는 준비 중이 `empty` 보다 먼저다(코어가 PGRST202 창을 '받은 것'으로 센다).
        store.ranking = TetrisDuelRankingBoard(entries: [], me: nil, recordSince: nil)
        #expect(GamesTetrisDuelRankingPlan.content(store) == .soon)
        store.rankingUnavailable = false

        // 내 줄: 순위 응답과 로비 전적이 **어긋나면 안 그린다**(섞으면 자기모순 문장이 뜬다).
        let me = TetrisDuelMyRank(rank: 4, wins: 6, losses: 4, draws: 1, points: 2)
        store.ranking = TetrisDuelRankingBoard(entries: [real], me: me, recordSince: nil)
        store.record = nil
        #expect(GamesTetrisDuelRankingPlan.myRank(store)?.rank == 4, "전적을 모를 때는 막지 않는다")
        store.record = TetrisDuelRecord(wins: 6, losses: 4, draws: 1)
        #expect(GamesTetrisDuelRankingPlan.myRank(store)?.rank == 4)
        store.record = TetrisDuelRecord(wins: 7, losses: 4, draws: 1)
        #expect(GamesTetrisDuelRankingPlan.myRank(store) == nil,
                "★ 전적이 어긋난 내 줄을 그렸다 — \"7승 4패 · 승점 +2\" 같은 자기모순이 뜬다")

        // 접힘·상한은 문구 표 한 출처에서 온다.
        #expect(GamesTetrisDuelRankingPlan.collapsedRows == 5 && GamesTetrisDuelRankingPlan.rowLimit == 100)
        let many = (1...7).map {
            TetrisDuelRankEntry(id: "u\($0)", rank: $0, user: Self.user("u\($0)"), wins: 1, losses: 0, draws: 0, points: 1)
        }
        store.ranking = TetrisDuelRankingBoard(entries: many, me: nil, recordSince: nil)
        #expect(GamesTetrisDuelRankingPlan.visible(store, isExpanded: false).count == 5)
        #expect(GamesTetrisDuelRankingPlan.visible(store, isExpanded: true).count == 7)
        #expect(GamesTetrisDuelRankingPlan.showsToggle(store))
        // 캡션: 컷을 **모르면 아무 말도 안 한다**(모르는데 "전체 기간"은 거짓이다).
        store.ranking = nil
        #expect(GamesTetrisDuelRankingPlan.sinceCaption(store) == nil)
        store.ranking = TetrisDuelRankingBoard(entries: [real], me: nil, recordSince: nil)
        #expect(GamesTetrisDuelRankingPlan.sinceCaption(store) == TetrisPhoneText.rankWholePeriod)
        #expect(TetrisPhoneText.myRankLine(me) == "4위 · 승점 +2 · 6승 4패 1무")
        #expect(TetrisPhoneText.myRankLine(TetrisDuelMyRank(rank: nil, wins: 0, losses: 0, draws: 0, points: 0))
                == TetrisPhoneText.outOfRank + " · 0승 0패 0무")
    }

    // MARK: - 5. ★ 데모 라우트 아홉이 각자 장면을 연다

    /// 라우트 한 건이 세워야 하는 값. `match` 는 `tetris.match?.id`(nil = 판이 없어야 한다).
    private struct Row {
        let route: String
        let match: String?
        let tab: GamesTetrisLobbyTab
        let incoming: Int
        let outgoing: Bool
        /// 끝까지 돌렸을 때의 단계 가족(판 여섯은 `.lobby` 가 **아니어야** 한다).
        let finished: Bool
    }

    private static let table: [Row] = [
        .init(route: "games/tetris/lobby", match: nil, tab: .opponents, incoming: 0, outgoing: false, finished: false),
        .init(route: "games/tetris/lobby/invites", match: nil, tab: .opponents, incoming: 2, outgoing: true, finished: false),
        .init(route: "games/tetris/ranking", match: nil, tab: .ranking, incoming: 0, outgoing: false, finished: false),
        .init(route: "games/tetris/match/ready", match: "demo-tetris-ready", tab: .opponents, incoming: 0, outgoing: false, finished: false),
        .init(route: "games/tetris/match/countdown", match: "demo-tetris-countdown", tab: .opponents, incoming: 0, outgoing: false, finished: false),
        .init(route: "games/tetris/match/playing", match: "demo-tetris-playing", tab: .opponents, incoming: 0, outgoing: false, finished: false),
        .init(route: "games/tetris/match/speedup", match: "demo-tetris-speedup", tab: .opponents, incoming: 0, outgoing: false, finished: false),
        .init(route: "games/tetris/match/won", match: "demo-tetris-won", tab: .opponents, incoming: 0, outgoing: false, finished: true),
        .init(route: "games/tetris/match/lost", match: "demo-tetris-lost", tab: .opponents, incoming: 0, outgoing: false, finished: true),
    ]

    @Test("데모 라우트 아홉이 **서로 다른 장면**을 연다(픽스처 실물로) — 꼬리를 버리면 아홉이 한 가지가 된다")
    func theNineDemoRoutesOpenTheirScenes() async {
        // ★ "라우트가 있다" 는 "화면이 뜬다" 를 뜻하지 않는다. 체스에서 꼬리를 깃발 하나로 접었을 때 라우트
        //   일곱 중 넷이 **스크린샷 md5 동일**이었다(결함 D6) — 픽스처는 그 전에 이미 다 있었다.
        //   그래서 라우트 글자 하나를 넣고 **스토어가 실제로 세운 값**을 지문으로 받아 가짓수를 센다.
        let index = MobileDemoFixtures.load()
        var prints: [String: String] = [:]
        for row in Self.table {
            let host = BaseStub.makeHost("tetris-demo-route")
            let scenario = row.route.replacingOccurrences(of: "/", with: "-").lowercased()
            MobileStubURLProtocol.register(host: host) { request in index.response(for: request, scenario: scenario) }
            let storage = BaseStub.makeStorage()
            let vault = InMemoryTokenVault()
            vault.write(MobileDemo.accessToken, key: AingKeychain.accessTokenKey)
            vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
            storage.defaults.set(MobileDemo.userID, forKey: AingSharedKeys.userID)
            let model = MobileAppModel(environment: MobileEnvironment(
                service: BaseStub.makeService(host: host), vault: vault, storage: storage, appInfo: BaseStub.appInfo,
                clock: .fixed(MobileClock.demoInstant), installationID: MobileDemo.installationID,
                realtimeTransport: nil, runsTimers: false, reloadWidgetTimelines: {}, demoRoute: row.route))
            model.session.clientReleaseTimeoutSeconds = 0
            model.start()
            #expect(await baseWaitUntil { model.session.isSignedIn }, "\(row.route)")
            model.sceneDidBecomeActive()

            // ① 앱 모델이 게임 탭을 열고 꼬리를 넘겼는가.
            #expect(await baseWaitUntil { model.router.lastOpenedRoute == .games }, "\(row.route): 게임 탭이 안 열렸다")
            #expect(model.games.pendingDemoTetrisScreen, "\(row.route): 테트리스를 쌓으라는 깃발이 안 섰다")
            #expect(model.games.demoTetrisRoute?.focusMatchID == row.match, "\(row.route): 열 판 id")
            #expect(GamesTetrisLobbyTab(demo: model.games.demoTetrisRoute?.lobbyTab ?? .opponents) == row.tab,
                    "\(row.route): 로비 탭")

            // ② 게임 탭이 하는 일(`GamesTab.applyDemoTetrisRoute`) → 화면이 나타난다(`GamesStore` 가 꼬리를 코어 문에 넣는다).
            #expect(model.games.consumePendingDemoTetrisScreen(), "\(row.route)")
            #expect(!model.games.consumePendingDemoTetrisScreen(), "\(row.route): 깃발이 남아 화면을 두 번 쌓는다")
            model.games.tetrisScreenDidAppear()

            let tetris = model.tetris
            if let want = row.match {
                #expect(await baseWaitUntil { tetris.match?.id == want }, "\(row.route): 그 판이 안 열렸다(판=\(tetris.match?.id ?? "-"))")
                #expect(tetris.phase != .lobby, "\(row.route): 판을 들고 있는데 단계가 로비다")
                #expect((tetris.phase == .finished) == row.finished,
                        "\(row.route): 끝난 판 여부가 어긋났다(단계=\(tetris.phase))")
            } else {
                #expect(await baseWaitUntil { tetris.hasLoadedLobby }, "\(row.route): 로비 응답이 안 왔다")
                #expect(tetris.match == nil, "\(row.route): 열 판이 없는데 판이 섰다")
                #expect(tetris.phase == .lobby, "\(row.route)")
            }
            // 신청 둘은 로비 응답에 **그대로 실려 온다**(테트리스는 체스처럼 둘째 왕복이 없다 — `invite` 통째가 온다).
            #expect(await baseWaitUntil { tetris.visibleIncomingInvites.count == row.incoming },
                    "\(row.route): 받은 신청 \(tetris.visibleIncomingInvites.count)건")
            #expect((tetris.outgoing != nil) == row.outgoing, "\(row.route): 보낸 신청")
            if row.route == "games/tetris/ranking" {
                #expect(await baseWaitUntil { tetris.ranking != nil }, "\(row.route): 순위 응답이 안 왔다")
                #expect(tetris.ranking?.me?.rank == 4, "\(row.route): 내 순위 \(String(describing: tetris.ranking?.me?.rank))")
            }

            prints[row.route] = [
                "phase=\(tetris.phase)", "match=\(tetris.match?.id ?? "-")",
                "tab=\(model.games.demoTetrisRoute?.lobbyTab.rawValue ?? "-")",
                "in=\(tetris.visibleIncomingInvites.count)", "out=\(tetris.outgoing?.id ?? "-")"
            ].joined(separator: " ")

            await baseBarrier(model.context.service)
            #expect(MobileForbiddenCalls.violations(in: baseRequests(host: host)).isEmpty, "\(row.route)")
            model.games.tetrisScreenDidDisappear()
            model.sceneDidEnterBackground()
            model.tetris.reset()
            BaseStub.tearDown(host: host, storage: storage)
        }

        // ★ **지문이 몇 가지인가** — 스크린샷 md5 비교와 같은 질문. 꼬리를 버리면 **한 가지**가 된다.
        #expect(prints.count == Self.table.count)
        #expect(Set(prints.values).count == Self.table.count,
                "라우트 아홉이 \(Set(prints.values).count) 가지 화면만 만든다 — 꼬리가 버려지고 있다: \(prints)")
    }

    @Test("`games/tetris` 한 토막은 **솔로** 미니게임으로 간다 — 1:1 쪽이 가로채면 솔로 데모가 조용히 사라진다")
    func thePlainGamesTetrisStaysWithTheSoloGame() async {
        // ★ 그 글자는 **이미 주인이 있다**: `AingRoute.parse` 의 `("games", 1)` 가지가 `.miniGame(.tetris)` 로
        //   읽는다(v0.3.38 에 나간 링크). 1:1 갈래가 `AingRoute` **앞**에 있으므로 여기서 받으면 솔로 테트리스
        //   데모 라우트가 통째로 사라진다 — 설계서 P1 을 글자가 아니라 **동작으로** 어기는 일이다.
        #expect(MobileDemoTetrisRoute(demoRoute: "games/tetris") == nil, "값이 한 토막을 받았다(레인 D 의 계약)")
        #expect(AingRoute(path: "games/tetris") == .miniGame(.tetris), "솔로 딥링크가 안 풀린다")

        let host = BaseStub.makeHost("tetris-solo-route")
        let index = MobileDemoFixtures.load()
        MobileStubURLProtocol.register(host: host) { request in index.response(for: request, scenario: "games-tetris") }
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        vault.write(MobileDemo.accessToken, key: AingKeychain.accessTokenKey)
        vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
        storage.defaults.set(MobileDemo.userID, forKey: AingSharedKeys.userID)
        let model = MobileAppModel(environment: MobileEnvironment(
            service: BaseStub.makeService(host: host), vault: vault, storage: storage, appInfo: BaseStub.appInfo,
            clock: .fixed(MobileClock.demoInstant), installationID: MobileDemo.installationID,
            realtimeTransport: nil, runsTimers: false, reloadWidgetTimelines: {}, demoRoute: "games/tetris"))
        model.session.clientReleaseTimeoutSeconds = 0
        model.start()
        #expect(await baseWaitUntil { model.session.isSignedIn })
        model.sceneDidBecomeActive()
        #expect(await baseWaitUntil { model.router.lastOpenedRoute != nil }, "라우트가 통째로 버려졌다")
        // ★ **솔로**로 갔다: 1:1 깃발·꼬리가 서지 않고 열린 라우트가 미니게임이다.
        #expect(model.router.lastOpenedRoute == .miniGame(.tetris),
                "★ 1:1 갈래가 솔로 딥링크를 가로챘다: \(String(describing: model.router.lastOpenedRoute))")
        #expect(!model.games.pendingDemoTetrisScreen, "★ 솔로 라우트가 1:1 화면을 쌓으라고 했다")
        #expect(model.games.demoTetrisRoute == nil, "솔로 라우트가 1:1 꼬리를 세웠다")
        model.sceneDidEnterBackground()
        BaseStub.tearDown(host: host, storage: storage)
    }

    // MARK: - 6. 소스 계약 (뷰가 그 자리를 실제로 부르는가 — 맥 스위트가 폰 뷰를 못 보므로 글자로 잰다)

    @Test("화면 수명은 **배선의 두 문만** 부른다 — 코어 창 문을 직접 부르면 순서가 두 벌이 된다")
    func theScreenOnlyCallsTheLifecycleHooks() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        #expect(screen.contains("store.tetrisScreenDidAppear()"), "화면이 나타남 훅을 안 부른다 — 로비·준비 보고가 안 나간다")
        #expect(screen.contains("store.tetrisScreenDidDisappear()"), "화면이 사라짐 훅을 안 부른다")
        // ★ 코어 창 문을 **직접 부르지 않는다**(그 넷의 순서와 끝난 판 접기는 배선이 쥔다).
        for door in ["tetris.openWindow(", "tetris.windowDidShow(", "tetris.windowDidHide(",
                     "tetris.windowDidClose(", "tetris.windowOcclusionDidChange("] {
            #expect(!screen.contains(door), "화면이 코어 창 문을 직접 부른다(\(door)) — 수명 순서가 두 벌이 된다")
        }
        // 기권은 이 레인이 내지 않는다(레인 C 가 확인을 받은 뒤에만 낸다).
        #expect(!screen.contains("tetris.resign("), "로비 화면이 기권을 낸다")

        // 신청은 **게이트를 지난 값으로만** 나간다. 요청이 나가는 자리가 하나이고 그 앞에 그 문이 있다.
        let callers = try IntegrationContractTests.files(containing: ["tetris.challenge("], under: "Sources/CheckMobileKit")
        #expect(callers == [Self.screenPath], "신청을 내는 자리가 둘이다(게이트를 우회하는 길이 생겼다): \(callers)")
        #expect(screen.contains("guard let stake = sendable else { return }"),
                "★ 신청이 게이트를 안 지난다 — 판돈을 안 골라도 요청이 나간다")
        #expect(screen.contains("tetris.challenge(userID: target.id, stake: stake)"),
                "게이트가 고른 판돈이 아닌 값으로 신청을 낸다")

        // 순위 조회를 거는 자리는 **판정 함수를 지난다**(뷰가 단계·스로틀을 다시 적지 않는다).
        let ranking = try IntegrationContractTests.code(Self.rankingPath)
        for file in [screen, ranking] {
            #expect(!file.contains("store.loadRanking()") || file.contains("GamesTetrisDuelRankingPlan"),
                    "순위 조회를 판정 밖에서 부른다")
        }
        #expect(screen.contains("GamesTetrisDuelRankingPlan.refreshIfNeeded(tetris, tab: value)"),
                "순위 탭을 골라도 조회가 안 나간다")

        // 공용 실패 부품을 쓴다(재시도 문구가 내 파일에 흩어지지 않는다 — `IntegrationFixTests` 가 센다).
        #expect(screen.contains("LoadFailureRow(") && ranking.contains("LoadFailureRow("))
        for forbidden in ["\"다시 시도\"", "\"다시 불러오기\"", "연결을 확인하고 다시 시도해 주세요", "네트워크를 확인하고"] {
            for (name, file) in [("화면", screen), ("순위", ranking), ("문구 표", try IntegrationContractTests.code(Self.textPath))] {
                #expect(!file.contains(forbidden), "\(name) 파일에 공용 문구가 또 적혔다: \(forbidden)")
            }
        }
    }

    @Test("데모 꼬리를 쓰는 줄이 **전부 `#if DEBUG` 안**이다 — Release 바이너리에 그 이름이 남으면 출시 게이트가 막는다")
    func theDemoTailLinesAreDebugOnly() throws {
        // 1.0.6 build 16 실측: 금지 문자열 `MobileDemo` 가 리플렉션 메타데이터의 **타입 이름**을 물어 아카이브가
        // 막혔다. 그래서 쓰는 자리 전부가 DEBUG 안이어야 한다(체스가 같은 못을 박았다).
        var checked = 0
        for path in ["Sources/CheckMobileKit/App/MobileAppModel.swift",
                     "Sources/CheckMobileKit/Games/GamesStore.swift",
                     "Sources/CheckMobileKit/Games/GamesTab.swift",
                     Self.screenPath] {
            for row in GamesChessDemoRouteTests.debugScopedLines(try IntegrationContractTests.code(path)) {
                guard row.line.contains("MobileDemoTetrisRoute") || row.line.contains("demoTetrisRoute") else { continue }
                checked += 1
                #expect(row.isDebugOnly, """
                    \(path): 이 줄이 #if DEBUG 밖이다 — Release 바이너리에 `MobileDemoTetrisRoute` 가 남아 \
                    출시 게이트(ios/scripts/check-release-app.sh)가 막는다: \(row.line.trimmingCharacters(in: .whitespaces))
                    """)
            }
        }
        #expect(checked >= 5, "훑은 자리가 \(checked)곳뿐이다 — 경로·이름이 틀렸다(공허한 초록 방지)")

        // 깃발(Bool)은 DEBUG **밖**이라야 맥 스위트가 값으로 잰다 — 타입 이름이 아니므로 게이트와 무관하다.
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesStore.swift")
        #expect(store.contains("package var pendingDemoTetrisScreen = false"))
        #expect(store.contains("tetris.openWindow(focusMatchID: demoTetrisRoute?.focusMatchID)"),
                "화면이 꼬리의 판 id 를 코어 문에 안 넣는다 — `match/<장면>` 이 로비로 떨어진다")
        #expect(store.contains("demoTetrisRoute = nil"), "로그아웃 reset 이 데모 꼬리를 안 거둔다")
        // 게임 탭은 **두 계기**에서 꺼낸다 — 탭이 먼저 마운트되면 onAppear 는 깃발 전에 끝난다.
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesTab.swift")
        #expect(tab.components(separatedBy: "applyDemoTetrisRoute()").count - 1 >= 3,
                "데모 테트리스 라우트를 한 계기에서만 꺼낸다 — 탭 마운트 순서에 따라 화면이 안 열린다")
        #expect(tab.contains("GamesTetrisDuelScreen(store: store)"), "테트리스 목적지가 화면으로 이어지지 않는다")
        #expect(tab.contains("GamesDestination.tetrisDuel"), "테트리스 입구가 게임 탭에 없다")
    }

    @Test("로비 탭 짝: 데모 값 둘이 화면 탭 둘과 **일대일**이다(한쪽만 넓히면 순위 라우트가 상대 고르기로 떨어진다)")
    func theLobbyTabsPairWithTheDemoValues() {
        // 데모 열거는 `CaseIterable` 이 아니다(남의 파일 — 전수를 못 돈다). 그래서 **값 둘을 글자로** 짝 짓고,
        // 화면 탭이 둘뿐인 것을 따로 센다. 데모 쪽에 값이 늘면 아래 `switch` 가 **컴파일로** 막는다.
        #expect(GamesTetrisLobbyTab.allCases.count == 2, "화면 탭이 둘이 아니다 — 데모 짝을 다시 봐라")
        for (demo, want) in [(MobileDemoTetrisRoute.LobbyTab.opponents, GamesTetrisLobbyTab.opponents),
                             (.ranking, .ranking)] {
            #expect(GamesTetrisLobbyTab(demo: demo) == want, "\(demo.rawValue) 짝이 어긋났다")
            #expect(demo.rawValue == want.rawValue, "두 열거의 글자가 갈렸다: \(demo.rawValue) ↔ \(want.rawValue)")
        }
        #expect(GamesTetrisLobbyTab.opponents.title == TetrisPhoneText.usersTab)
        #expect(GamesTetrisLobbyTab.ranking.title == TetrisPhoneText.rankTab)
        // 기본 탭은 상대 고르기다(판 장면도 로비 머리로 돌아온다 — 레인 D 표).
        #expect(MobileDemoTetrisRoute(scene: .matchPlaying).lobbyTab == .opponents)
        #expect(MobileDemoTetrisRoute(scene: .ranking).lobbyTab == .ranking)
    }

    @Test("못 쓰는 기기·서버는 **코어 문구**로 말한다(맥과 같은 말) — 로비를 그려 신청 버튼을 세우지 않는다")
    func theUnavailableNoticeComesFromTheCore() {
        #expect(GamesTetrisDuelUnavailable.title(.available) == nil, "쓸 수 있는데 안내가 섰다")
        #expect(GamesTetrisDuelUnavailable.title(.updateRequired) == TetrisDuelNoticeText.updateMine)
        #expect(GamesTetrisDuelUnavailable.title(.serverMissing) == TetrisDuelNoticeText.unavailable)
        // 두 갈래가 **다른 말**이다(한 벌로 접으면 업데이트가 필요한 사람에게 "곧 열려요"가 뜬다).
        #expect(GamesTetrisDuelUnavailable.title(.updateRequired) != GamesTetrisDuelUnavailable.title(.serverMissing))
        #expect(GamesTetrisDuelUnavailable.icon(.updateRequired) != GamesTetrisDuelUnavailable.icon(.serverMissing))
    }

    // MARK: - 도우미 경로

    private static let screenPath = "Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift"
    private static let rankingPath = "Sources/CheckMobileKit/Games/GamesTetrisDuelRanking.swift"
    private static let textPath = "Sources/CheckMobileKit/Games/GamesTetrisDuelText.swift"
}
