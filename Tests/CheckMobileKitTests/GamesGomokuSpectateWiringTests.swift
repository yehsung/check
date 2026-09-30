@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 오목 **순위표·관전(0.3.41)의 폰 배선** 못 + 순위표 매퍼의 순수 판정.
//
// ── 왜 이 파일이 따로 있는가 ──
// 순위·관전 화면은 전부 `#if os(iOS)` 안이라 **맥 스위트가 한 줄도 못 본다**(저장소 메모 '폰 뷰는 맥 스위트가 못 본다' —
// `ios/scripts/build-sim.sh` 가 유일한 그물이다). 그런데 그 화면 넷을 통째로 죽이는 원인은 뷰가 아니라 배선 한 줄이다:
// `GomokuStore.spectatorFeaturesEnabled` 가 기본 false 라서, 꺼져 있으면 `loadRanking`·`startWatching`·`refreshWatch` 와
// `pollTick`·`windowDidShow` 의 두 분기가 전부 그 값을 먼저 보고 **요청을 한 번도 내지 않는다**(GomokuStore.swift:645).
// 그래서 이 한 줄만은 `#if` **밖**에서 지킨다 — 이 파일은 통째로 맥에서 돈다(하네스가 세우는 `MobileAppModel` 도, 순수 매퍼도
// 맥 전용 코드가 아니다).
//
// ── 기준선이 달라야 한다 ──
// "스위치가 켜져 있다"만 재면 켠 것이 **효과가 있는지**는 모른다. 그래서 두 번째 테스트는 같은 손짓을 스위치만 되돌린 하네스에도
// 걸어 요청이 0건인 것을 나란히 잰다(저장소 메모 '비교 기준선이 달라야 한다').
//
// 관례는 같은 폴더 `GamesStoreScenarioTests`·`GamesStoreHardeningTests` 그대로다: `GamesHarness`(스텁 서버·조작 시계·임시
// 저장소) · 테스트 하나 몫의 대기 예산 · 끝에서 폰 금지 호출 0건.

@MainActor
@Suite(.serialized) struct GamesGomokuSpectateWiringTests {
    /// 이 테스트 하나 몫의 대기 예산(까닭은 `GamesWaitBudget`).
    private let waits = GamesWaitBudget()

    // MARK: - 픽스처

    private nonisolated static let mine = GamesHarness.userID
    private nonisolated static let rival = "p-rival"
    private nonisolated static let third = "p-third"

    /// 순위표 한 줄(서버 모양). `id` 를 nil 로 주면 `user_id` 가 null 인 행, `rank` 를 nil 로 주면 순위가 없는 행이다 —
    /// 둘 다 매퍼가 **버려야 하는** 행이다.
    private nonisolated static func row(_ id: String?, _ name: String, rank: Int?, wins: Int, losses: Int, draws: Int) -> String {
        let idValue = id.map { "\"\($0)\"" } ?? "null"
        let rankValue = rank.map(String.init) ?? "null"
        return #"{"rank":\#(rankValue),"user_id":\#(idValue),"display_name":"\#(name)","avatar_url":null,"character":"aing","center":"seoul","wins":\#(wins),"losses":\#(losses),"draws":\#(draws),"points":\#(wins - losses)}"#
    }

    /// 내 순위 한 벌. `rank` 를 nil 로 주면 0판(순위 밖)이다 — 전적은 그래도 온다.
    private nonisolated static func meRow(rank: Int?, wins: Int, losses: Int, draws: Int) -> String {
        let rankValue = rank.map(String.init) ?? "null"
        return #"{"rank":\#(rankValue),"wins":\#(wins),"losses":\#(losses),"draws":\#(draws),"points":\#(wins - losses)}"#
    }

    /// 기본 픽스처: 라이벌 1위 · 나 2위. 내 전적은 로비 픽스처(`GamesGomokuJSON.lobby` — 2승 1패 0무)와 **같게** 맞춰 뒀다.
    /// 다르면 `myRankConsistentWithRecord` 가 (제대로) nil 을 내주고, 아래 C16 단언이 깃발과 무관하게 빨개진다.
    private nonisolated static let defaultRows: [String] = [
        row(rival, "라이벌", rank: 1, wins: 5, losses: 1, draws: 0),
        row(mine, "나", rank: 2, wins: 2, losses: 1, draws: 0)
    ]
    private nonisolated static let defaultMe: String = meRow(rank: 2, wins: 2, losses: 1, draws: 0)

    /// `gomoku_ranking` 응답 한 벌. `me` 를 nil 로 주면 키가 null, `recordSinceMs` 를 nil 로 주면 컷이 없는 것(-infinity)이다.
    private nonisolated static func rankingJSON(
        nowMs: Int,
        rows: [String] = defaultRows,
        me: String? = defaultMe,
        recordSinceMs: Int? = nil,
        status: String = "ok"
    ) -> String {
        let meValue = me ?? "null"
        let sinceValue = recordSinceMs.map(String.init) ?? "null"
        return #"{"status":"\#(status)","server_now_ms":\#(nowMs),"record_since_ms":\#(sinceValue),"me":\#(meValue),"rows":[\#(rows.joined(separator: ","))]}"#
    }

    /// 서비스와 같은 snake_case 디코더로 응답 하나(디코더는 `.convertFromSnakeCase` — 프로퍼티는 camelCase 다).
    private nonisolated static func decode(_ json: String) throws -> GomokuRankingResponse {
        try JSONDecoder.gamesSnake.decode(GomokuRankingResponse.self, from: Data(json.utf8))
    }

    /// 오목 화면이 실제로 부르는 조회들을 스텁에 걸어 둔다(로비·받은함·순위).
    private func serveLobby(_ harness: GamesHarness, ranking: String? = nil) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
        harness.server.setDefault("gomoku_ranking", json: ranking ?? Self.rankingJSON(nowMs: nowMs))
    }

    // MARK: - 1. 배선 한 줄

    @Test("폰 배선이 순위·관전 주 스위치를 켠다 — 이 한 줄이 빠지면 순위·관전 요청이 한 번도 나가지 않는다")
    func phoneWiringEnablesSpectatorFeatures() async {
        // 없으면: 폰의 순위 절은 영영 로딩 문구이고 [관전] 은 눌러도 관전 상태조차 서지 않는다. 화면 파일은 `#if os(iOS)` 안이라
        // 맥 스위트가 못 보므로, 되돌려도 **빨개지는 테스트가 이것 말고는 없다**.
        let harness = GamesHarness(label: "gomoku-switch")
        #expect(harness.model.gomoku.spectatorFeaturesEnabled,
                "폰 배선(MobileAppModel.init)이 spectatorFeaturesEnabled 를 안 켰다 — 순위·관전이 통째로 죽는다")
        // 화면이 읽는 자리도 같은 스토어여야 한다. 탭 스토어는 `context.gomoku` 로만 닿으므로, 다른 인스턴스를 켜면
        // 깃발은 참인데 화면 쪽은 그대로 꺼져 있다.
        #expect(harness.model.context.gomoku === harness.model.gomoku, "탭 스토어가 보는 오목 스토어가 딴 인스턴스다")
        #expect(harness.model.context.gomoku.spectatorFeaturesEnabled)
        // 스위치는 배선 값이라 로그아웃 reset 이 건드리지 않는다(맥 쪽 같은 단언과 짝) — 재로그인 뒤에도 순위가 살아야 한다.
        harness.model.gomoku.reset()
        #expect(harness.model.gomoku.spectatorFeaturesEnabled, "reset 이 배선 값을 껐다 — 재로그인하면 순위가 안 열린다")
        await harness.tearDown()
    }

    // MARK: - 2. 켠 것이 실제로 닿는가 (기준선 대비)

    @Test("오목 화면이 뜨면 순위를 실제로 읽어 화면 값에 옮긴다 — 스위치만 되돌린 하네스는 같은 손짓에 0건이다")
    func openingTheScreenLoadsRanking() async {
        // 없으면: 깃발만 참이고 조회가 안 나가는 상태(창 게이트·세션 게이트가 어긋난 배선)가 위 테스트만으로는 초록이다.
        let harness = GamesHarness(label: "gomoku-rank-on")
        serveLobby(harness)
        await harness.signIn()
        harness.games.gomokuScreenDidAppear()
        #expect(await waits.wait { harness.server.requests("gomoku_ranking").count >= 1 },
                "오목 화면이 떴는데 순위 조회가 나가지 않았다")
        #expect(await waits.wait { harness.gomoku.ranking != nil }, "순위 응답이 화면 값으로 안 옮겨졌다")
        #expect(harness.gomoku.ranking?.entries.count == 2)
        #expect(harness.gomoku.hasLoadedRanking)
        #expect(!harness.gomoku.rankingUnavailable && !harness.gomoku.rankingLoadFailed)
        // 머리글 캡슐의 내 순위는 로비 전적과 같을 때만 선다(C16). 픽스처는 둘을 2승 1패 0무로 맞춰 뒀다.
        #expect(await waits.wait { harness.gomoku.hasLoadedLobby })
        #expect(harness.gomoku.myRankConsistentWithRecord?.rank == 2, "순위·전적이 한 출처로 안 맞는다")
        #expect(harness.gomoku.notice == nil, "순위 갈래가 대국 상태줄을 가로챘다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // 기준선이 달라야 이 테스트가 산다: 같은 손짓에서 **스위치만** 되돌리면 순위 조회가 0건이다.
        // (이 대비가 없으면 위 초록이 스위치 덕인지 딴 경로 덕인지 구조적으로 알 수 없다.)
        let off = GamesHarness(label: "gomoku-rank-off")
        serveLobby(off)
        off.gomoku.spectatorFeaturesEnabled = false        // = 배선 한 줄을 지운 것
        await off.signIn()
        off.games.gomokuScreenDidAppear()
        #expect(await waits.wait { off.gomoku.hasLoadedLobby }, "로비 조회는 스위치와 무관하다 — 손짓 자체가 안 닿았다")
        await off.barrier()
        await baseYield(turns: 8)
        await off.barrier()
        #expect(off.server.requests("gomoku_ranking").isEmpty,
                "스위치가 꺼졌는데 순위 조회가 나갔다: \(off.server.requests("gomoku_ranking").count)건")
        #expect(off.gomoku.ranking == nil)
        await off.tearDown()
    }

    // MARK: - 3. 순수 매퍼 (맥에서 돈다)

    @Test("순수 매퍼: 행 순서는 입력 그대로다 — 정렬은 서버가 한다(재정렬 금지)")
    func rankingBoardKeepsServerOrder() throws {
        // 없으면: 누가 `rankingBoard` 나 `applyRanking` 에 `.sorted` 한 줄을 넣어도(둘 다 "친절"로 보인다) 같은 목록이
        // 화면마다 다른 순서가 된다. ⚠️ 픽스처를 **일부러 서버 규칙과 어긋나게** 세운다 — 이미 정렬된 입력을 넣으면
        // 이 테스트는 재정렬을 영영 못 본다(기준선이 같은 입력이면 그 테스트는 영원히 초록).
        let response = try Self.decode(Self.rankingJSON(nowMs: 1_789_621_500_000, rows: [
            Self.row(Self.rival, "라이벌", rank: 3, wins: 1, losses: 1, draws: 0),   // 승점 0 인데 맨 앞
            Self.row(Self.mine, "나", rank: 1, wins: 5, losses: 1, draws: 0),        // 승점 +4
            Self.row(Self.third, "셋째", rank: 2, wins: 3, losses: 1, draws: 2)      // 승점 +2
        ], recordSinceMs: 1_789_513_200_000))
        let board = GomokuStore.rankingBoard(from: response)
        #expect(!GomokuRankingOrder.isSorted(response.rows ?? []),
                "픽스처가 이미 서버 순서대로다 — 이 테스트로는 재정렬을 잡을 수 없다")
        #expect(board.entries.map(\.user.displayName) == ["라이벌", "나", "셋째"], "매퍼가 행을 재정렬했다")
        #expect(board.entries.map(\.rank) == [3, 1, 2], "서버가 매긴 순위 숫자를 바꿨다")
        #expect(board.entries.map(\.points) == [0, 4, 2], "승점은 서버 값 그대로다")
        #expect(board.entries.map(\.id) == [Self.rival, Self.mine, Self.third].map { $0.lowercased() })
        // 매퍼가 서버의 착용값을 떨어뜨리지 않는다. **이제 소비자가 있다** — 순위 행이
        // `characterHint: entry.user.characterID` 로 넘기고(`GamesGomokuRanking.swift`), 판정은
        // `AppUserCharacterDirectory.avatar(for:photoURL:characterHint:)`(CheckCore) 한 곳이다.
        // 표가 아직 안 온 세션에서 순위표 전원이 이니셜이 되던 것을 그 경로가 막는다.
        #expect(board.entries.first?.user.characterID == "aing",
                "매퍼가 서버 착용값을 떨어뜨렸다 — 소비자가 붙는 날 그 자리가 이니셜이 된다")
        // 컷은 기기 시계 보정 없이 서버 순간 그대로("M월 d일부터" 캡션의 달력 값이다).
        #expect(board.recordSince == Date(timeIntervalSince1970: 1_789_513_200))
    }

    @Test("순수 매퍼: user_id 나 rank 가 빠진 행은 버린다 — 순위 없는 줄은 순위표에 아무 정보도 안 준다")
    func rankingBoardDropsRowsWithoutIdentityOrRank() throws {
        // 없으면: 이름만 있고 순위가 없는 빈 줄이 순위표 사이에 끼어 "이 사람은 몇 위지?"가 되고, user_id 없는 행은
        // 아바타·내 행 판정이 전부 어긋난 유령 줄이 된다.
        let response = try Self.decode(Self.rankingJSON(nowMs: 1_789_621_500_000, rows: [
            Self.row(Self.rival, "라이벌", rank: 1, wins: 5, losses: 1, draws: 0),   // 남는 유일한 행
            Self.row(nil, "id 없음", rank: 2, wins: 4, losses: 1, draws: 0),         // user_id null
            Self.row("", "빈 id", rank: 3, wins: 3, losses: 1, draws: 0),            // user_id 빈 문자열
            Self.row(Self.third, "순위 없음", rank: nil, wins: 2, losses: 1, draws: 0)  // rank null
        ]))
        let board = GomokuStore.rankingBoard(from: response)
        #expect(response.rows?.count == 4, "픽스처가 네 줄이어야 '버렸다'를 말할 수 있다")
        #expect(board.entries.count == 1, "버려야 하는 행이 실렸다: \(board.entries.map(\.user.displayName))")
        #expect(board.entries.first?.id == Self.rival)
        #expect(board.entries.first?.rank == 1)
    }

    @Test("순수 매퍼: 0판이면 me.rank 가 nil(순위 밖) 그대로 온다 — 전적 0,0,0 은 그래도 싣는다")
    func rankingBoardKeepsNilMyRank() throws {
        // 없으면: nil 을 0 이나 "순위 없음"으로 접는 순간 화면이 "0위"를 그리거나 내 줄을 통째로 빠뜨린다.
        // 전적 초기화 직후(2026-10-01 컷)에는 **모든 사용자가 이 상태**라 첫 화면이 곧 이 갈래다.
        let response = try Self.decode(Self.rankingJSON(
            nowMs: 1_789_621_500_000, rows: [], me: Self.meRow(rank: nil, wins: 0, losses: 0, draws: 0)
        ))
        let board = GomokuStore.rankingBoard(from: response)
        let mine = try #require(board.me, "me 가 통째로 빠졌다 — 0판도 '순위 밖'으로 그려야 한다")
        #expect(mine.rank == nil, "0판의 nil 순위를 숫자로 접었다")
        #expect(mine.wins == 0)
        #expect(mine.losses == 0)
        #expect(mine.draws == 0)
        #expect(mine.points == 0)
        #expect(board.entries.isEmpty, "0판인 사람은 rows 에 없다 — 빈 목록이 사실이다")
        // 컷이 -infinity(전체 기간)면 `record_since_ms` 가 null 이고, 그때 화면은 "언제부터" 캡션을 안 단다.
        #expect(board.recordSince == nil)

        // me 키 자체가 null 인 옛 응답도 nil 로 내려앉는다(화면은 내 줄을 그리지 않는다 — 0 으로 꾸미지 않는다).
        let without = GomokuStore.rankingBoard(from: try Self.decode(Self.rankingJSON(nowMs: 1_789_621_500_000, rows: [], me: nil)))
        #expect(without.me == nil)
    }
}
