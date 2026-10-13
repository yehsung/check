@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 체스 **순위표·관전 절(폰)** 의 판정과 문구.
//
// ── 왜 이 파일이 재는 것이 '모양'이 아닌가 ──
// 폰 뷰는 전부 `#if os(iOS)` 안이라 맥 스위트가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
// 오목에서 그 탓에 소스 글자만 재고 있었고, **관전 게이트를 되돌렸는데도 613건이 전부 초록**이었다.
// 그래서 체스는 두 절의 **판정을 뷰에서 떼어** `#if` 밖에 뒀다(`GamesChessRankingPlan` ·
// `GamesChessWatchPlan` · `GamesChessWatchStatus` · `GamesChessWatchBudget`). 이 파일은
// **부르는 자리와 결과**를 값으로 잰다:
//  · 게이트: 깃발을 세운 스토어를 넘겨 결론(`Entry`)을 받는다 — `watchUnavailable` 을 `rankingUnavailable` 로
//    바꾸면 **이 파일이 빨개진다**(두 깃발을 반대로 세운 스토어를 쓴다 — 기준선이 갈려 있다).
//  · 행: 0판 섞인 목록을 넣어 **남은 행**을 센다. 일곱 칸은 보이스오버 라벨의 **글자**로 되묻는다.
//  · 입력: 판에 넘어가는 값(`boardTapHandler` 등)을 그대로 읽는다.
// 뷰가 그 판정을 **안 지나는 길**(깃발을 다시 읽거나 nil 을 손으로 적는 길)만 소스 계약으로 막는다 —
// 주석은 걷어낸다(안 걷으면 설명을 지워야만 초록이 된다).

@MainActor
@Suite(.serialized) struct GamesChessSpectateTests {

    // MARK: - 픽스처

    private nonisolated static let mine = "u-mine"

    private static func user(_ id: String, _ name: String, character: String? = "aing") -> ChessUser {
        ChessUser(id: id, displayName: name, avatarURL: nil, characterID: character,
                  isWorking: false, isCapable: true, inMatch: false, center: "seoul")
    }

    private static func entry(_ id: String, _ name: String, rank: Int, wins: Int, losses: Int, draws: Int) -> ChessRankEntry {
        ChessRankEntry(id: id, rank: rank, user: user(id, name), wins: wins, losses: losses, draws: draws,
                       points: wins - losses)
    }

    /// 순위를 들고 있는 스토어. `me` 를 주면 머리글 내 순위까지 선다.
    private static func store(entries: [ChessRankEntry], me: ChessMyRank? = nil,
                              recordSince: Date? = nil, hasLoaded: Bool = true) -> ChessStore {
        let store = ChessStore()
        store.ranking = ChessRankingBoard(entries: entries, me: me, recordSince: recordSince)
        store.hasLoadedRanking = hasLoaded
        return store
    }

    private static func live(_ id: String = "m-1") -> ChessLiveMatch {
        ChessLiveMatch(id: id, a: user("u-a", "민트별"), b: user("u-b", "달토끼"), stake: .ten,
                       startedAt: Date(timeIntervalSince1970: 1_789_621_400))
    }

    /// 끝난 관전 판 하나(흑 승 · 기권).
    private static func finishedWatch() -> ChessSpectateState {
        var watch = ChessSpectateState(id: "m-1", faces: [user("u-a", "민트별"), user("u-b", "달토끼")], stake: 10)
        watch.black = user("u-a", "민트별")
        watch.white = user("u-b", "달토끼")
        watch.isFinished = true
        watch.winner = .black
        watch.endReason = .resign
        watch.plyCount = 24
        return watch
    }

    // MARK: - 1. 관전 입구 게이트 (★ 짝 맞추기)

    @Test("관전 입구는 **관전 전용 깃발**을 본다 — 순위 깃발로 잠그면 관전이 없는데 칩이 열린다")
    func theWatchEntryLocksOnTheWatchFlagNotTheRankingFlag() {
        // 없으면: `rankingUnavailable` 로 관전 입구를 잠그던 자리가 **우연히만** 맞는다. 코어가 겸업을 풀어
        // "순위를 한 번이라도 받았으면 순위 깃발은 세우지 않는다"로 좁혀 둔 탓에(`ChessStoreWatch.swift:320`),
        // 순위 행을 들고 있는 사용자에게는 그 게이트가 **영영 열려** 칩이 활성인 채 404 를 무한히 낸다
        // (오목에서 5번 눌러 5요청 실측). [[client-gates-come-in-pairs]]
        //
        // ★ 기준선이 갈려 있어야 이 단언이 산다 — 두 깃발을 **반대로** 세운 스토어를 쓴다.
        let locked = ChessStore()
        locked.spectatorFeaturesEnabled = true
        locked.watchUnavailable = true
        locked.rankingUnavailable = false
        #expect(GamesChessWatchPlan.entry(locked, isMine: false) == .soon,
                "관전이 없는데 입구가 열렸다 — 누를 때마다 404 가 나간다")

        let open = ChessStore()
        open.spectatorFeaturesEnabled = true
        open.watchUnavailable = false
        open.rankingUnavailable = true          // 순위만 없는 창(= 겸업으로 되돌리면 여기가 빨개진다)
        #expect(GamesChessWatchPlan.entry(open, isMine: false) == .chip,
                "순위 깃발로 관전 입구를 잠갔다 — 순위와 관전은 같이 없어지지 않는다")

        // 내 판은 어느 깃발과도 무관하게 칩이 아니다(스토어가 문 앞에서 막는다 — `startWatching`).
        #expect(GamesChessWatchPlan.entry(open, isMine: true) == .myMatch)
    }

    @Test("주 스위치가 꺼진 배선에서는 입구를 **두지 않는다** — 눌러도 아무 일이 없는 칩을 만들지 않는다")
    func theWatchEntryIsAbsentWhenSpectatorFeaturesAreOff() {
        // 없으면: `spectatorFeaturesEnabled` 가 false 인 배선(기본값이다)에서 칩이 서고, `startWatching` 이
        // 조용히 돌아서므로(`ChessStoreWatch.swift:134`) 눌러도 아무 일이 안 난다.
        let off = ChessStore()
        off.spectatorFeaturesEnabled = false
        #expect(GamesChessWatchPlan.entry(off, isMine: false) == .absent, "스위치가 꺼졌는데 입구가 섰다")
        // 켠 것만으로 모양이 바뀌는지 — 기준선.
        off.spectatorFeaturesEnabled = true
        #expect(GamesChessWatchPlan.entry(off, isMine: false) == .chip, "스위치를 켜도 입구가 안 선다 — 위 단언이 공허하다")
        // 꺼진 배선에서는 **내 판 캡션·곧 열려요 캡션도 없다**(슬롯 자체가 비어야 줄을 접지 않는다).
        off.spectatorFeaturesEnabled = false
        off.watchUnavailable = true
        #expect(GamesChessWatchPlan.entry(off, isMine: true) == .absent)
        #expect(GamesChessWatchPlan.entry(off, isMine: false) == .absent)
    }

    @Test("소스 계약: 관전 입구를 그리는 자리는 판정을 **지나서만** 깃발을 읽는다")
    func theWatchEntryViewRoutesThroughThePlan() throws {
        // 없으면: 판정은 멀쩡한데 뷰가 `store.rankingUnavailable` 을 **다시** 읽어 같은 사고가 돌아온다
        // (위 값 테스트는 뷰를 못 본다 — iOS 전용이다).
        let code = try Self.body(of: "private var entry", in: Self.watchSource(), length: 1_600)
        #expect(code.contains("GamesChessWatchPlan.entry(store, isMine: store.isMine(live))"),
                "관전 입구가 판정을 지나지 않는다")
        #expect(!code.contains("rankingUnavailable"), "관전 입구가 순위 깃발을 다시 본다(겸업 복귀)")
        #expect(!code.contains("watchUnavailable"), "관전 입구가 깃발을 직접 읽는다 — 판정이 두 벌이 된다")
        #expect(!code.contains("spectatorFeaturesEnabled"), "주 스위치도 판정 한 곳에서만 본다")
        // 폭을 재보는 갈래도 같은 판정 하나를 본다(조건을 두 곳에 적으면 빈 슬롯 때문에 줄을 접는 꼴이 된다).
        let has = try Self.body(of: "private var hasEntry", in: Self.watchSource(), length: 200)
        #expect(has.contains("GamesChessWatchPlan.entry(store, isMine: store.isMine(live))"))
        #expect(has.contains("!= .absent"))
    }

    // MARK: - 2. 관전 판에 입력이 0건인가

    @Test("관전 판에는 입력이 **하나도** 없다 — 탭 처리기 nil · 선택 없음 · 도착 점 없음 · 백이 아래")
    func theSpectatorBoardTakesNoInput() {
        // 없으면: 관전자가 판을 눌러 선택이 서고, 그 선택이 "내 차례·내 색" 을 전제한 길로 들어간다.
        #expect(GamesChessWatchPlan.boardTapHandler == nil, "관전 판에 탭 처리기가 붙었다")
        #expect(GamesChessWatchPlan.boardSelection == nil, "관전 판에 선택 표시가 있다")
        #expect(GamesChessWatchPlan.boardLegalTargets.isEmpty, "관전 판에 도착 점이 있다")
        // ★ 관전자에게는 내 색이 없다 — 체스 관례가 백 아래다(맥 `ChessPanel.swift:1041`).
        #expect(GamesChessWatchPlan.boardWhiteAtBottom, "관전 판이 백을 아래에 두지 않는다")
    }

    /// 선택·도착 점과 달리 **체크는 관전에도 그린다** — "내 차례·내 색" 에 매이지 않은 판의 사실이고,
    /// 체스에서 그건 글자로만 말해서는 안 되는 정보다(맥 관전도 같은 덮개를 그린다).
    ///
    /// ★ 깃발은 **응답이 준 값**이다(`chess_watch` 의 `in_check`) — 관전 화면은 합법 수를 만들지 않는다(§6 ④).
    ///   이 시험이 재는 것은 그 깃발 + 배치에서 읽은 왕 칸이고, 끝난 판에서는 nil 이다.
    @Test("관전 판도 체크 칸을 그린다 — 응답의 in_check + 배치에서 읽은 왕 칸, 끝난 판은 nil")
    func theSpectatorBoardStillMarksTheCheckedKing() throws {
        // 없으면: 관전자는 "흑 차례" 만 읽고 흑 왕이 지금 맞고 있다는 것을 판에서 못 본다.
        var watch = ChessSpectateState(id: "m-1")
        watch.position = ChessPosition(fen: "r1bqk1nr/pppp1ppp/2n5/4N3/2B1P3/8/PPPP1bPP/RNBQK2R w KQkq - 0 5")
        watch.turn = .white
        watch.isInCheck = true
        #expect(GamesChessWatchPlan.boardCheckSquare(for: watch)?.notation == "e1",
                "체크인 관전 판이 왕 칸을 못 집었다(\(GamesChessWatchPlan.boardCheckSquare(for: watch)?.notation ?? "없음"))")
        // 체크가 아니면 없다(기준선이 갈린다 — 같으면 위 한 줄은 아무것도 안 잰다).
        var quiet = watch
        quiet.isInCheck = false
        #expect(GamesChessWatchPlan.boardCheckSquare(for: quiet) == nil, "체크가 아닌데 덮개 칸이 선다")
        // 끝난 판에는 없다 — 결과를 보는 화면에 빨간 칸이 남으면 아직 두는 중처럼 읽힌다.
        var ended = watch
        ended.isFinished = true
        #expect(GamesChessWatchPlan.boardCheckSquare(for: ended) == nil, "끝난 관전 판에 체크 덮개가 남는다")
        // 첫 응답 전(배치를 모른다)에도 조용하다.
        var cold = ChessSpectateState(id: "m-2")
        cold.isInCheck = true
        cold.turn = .white
        #expect(GamesChessWatchPlan.boardCheckSquare(for: cold) == nil, "판을 모르는데 덮개 칸이 선다")
    }

    @Test("소스 계약: 판 호출이 그 값들을 그대로 넘기고, 관전 절에 제스처가 한 줄도 없다")
    func theSpectatorBoardCallSiteUsesThePlanValues() throws {
        // 없으면: 판정은 nil 인데 호출부가 자기 손으로 처리기를 끼워 넣는 길이 남는다.
        let code = try Self.body(of: "GamesChessBoard(", in: Self.watchSource(), length: 700)
        #expect(code.contains("onTapSquare: GamesChessWatchPlan.boardTapHandler"), "탭 처리기를 판정에서 받지 않는다")
        #expect(code.contains("selection: GamesChessWatchPlan.boardSelection"))
        #expect(code.contains("legalTargets: GamesChessWatchPlan.boardLegalTargets"))
        #expect(code.contains("whiteAtBottom: GamesChessWatchPlan.boardWhiteAtBottom"))
        // 체크 덮개는 **판정에서 받는다**(nil 을 박아 두면 관전자는 왕이 어디서 맞고 있는지 못 본다).
        #expect(code.contains("checkSquare: GamesChessWatchPlan.boardCheckSquare(for: watch)"),
                "관전 판이 체크 칸을 판정에서 받지 않는다")
        // 못 읽은 FEN·첫 응답 전에는 **빈 판**이다(판 부품의 `position` 은 옵셔널이 아니다) — `.standard` 를
        // 넘기면 아무도 안 둔 초기 배치를 "지금 판"으로 그려 거짓말이 된다.
        #expect(code.contains("position: watch.position ?? .empty"), "못 읽은 판을 다른 배치로 메운다")
        // 절 전체에 입력 문법이 없다. [관전]·[나가기] 버튼은 `AingButton` 이라 이 목록에 걸리지 않는다.
        let whole = Self.stripComments(try Self.watchSource())
        for forbidden in ["onTapGesture", "onLongPressGesture", "DragGesture", "onHover", "simultaneousGesture"] {
            #expect(!whole.contains(forbidden), "관전 절에 입력(\(forbidden))이 들어왔다")
        }
    }

    // MARK: - 3. 관전 문구 — "이기면 +N" 금지

    @Test("관전 문구는 판돈을 \"이기면 +N\" 으로 말하지 않는다 — 관전자는 한 푼도 받지 않는다")
    func theSpectatorNeverPromisesWinnings() throws {
        // 없으면: 오목 관전이 0.3.41 에 "판돈 10 · 이기면 +10" 이라고 썼던 그 자리가 체스에서 되살아난다
        // (보이스오버도 같은 말을 읽었다). 접미사를 붙이는 자리는 내비 부제·신청 카드·대국 화면 — **전부 내 판**이다.
        //
        // ① 값: 이 절이 말할 수 있는 모든 문장에 '이기면'·'받아요'가 없다.
        let watch = Self.finishedWatch()
        var spoken: [String] = [
            GamesChessText.stakeUnknown, GamesChessText.watchCaption,
            GamesChessText.watchTailCaption, GamesChessText.watchTitle,
            GamesChessText.watchLoading, GamesChessText.playersUnknown,
            GamesChessText.watch, GamesChessText.watchChipHint,
            GamesChessText.myMatch, GamesChessText.watchSoonCaption,
            GamesChessText.liveTitle, GamesChessText.noLiveMatches,
            GamesChessText.boardAccessibility(watch), GamesChessText.watchPly(24),
            GamesChessWatchStatus.headline(for: watch)
        ]
        spoken.append(GamesChessWatchStatus.detail(for: watch) ?? "")
        for reason in ChessEndReason.allCases {
            spoken.append(GamesChessText.watchEndReason(reason, winner: .black))
            spoken.append(GamesChessText.watchEndReason(reason, winner: nil))
        }
        for line in spoken {
            #expect(!line.contains("이기면"), "관전 문구가 이김을 약속한다: \(line)")
            #expect(!line.contains("+\(watch.stake ?? 0)"), "관전 문구가 판돈 획득을 말한다: \(line)")
        }

        // ② 소스: 판돈 줄에 접미사를 끼울 길이 없다. `GamesStakeLine` 의 `suffix:` 가 그 길이고
        //    (기본값 nil — 안 주면 액수만 그린다), 공용 접미사 표(`stakeGainSuffix`)도 부르지 않는다.
        //    ★ 한글 문자열을 **바이너리**로 세는 검사로는 이걸 못 잡는다(Swift 가 UTF-8 15바이트 이하 literal 을
        //    인라인 저장해 0건이 '없다'를 증명하지 않는다 — 저장소 메모). 그래서 소스를 글자로 본다.
        let code = Self.stripComments(try Self.watchSource())
        #expect(code.contains("GamesStakeLine(stake: stake)"), "판돈 줄의 모양이 바뀌었다 — 아래 단언이 공허하다")
        #expect(!code.contains("suffix:"), "판돈 줄에 접미사를 넘긴다")
        #expect(!code.contains("stakeGainSuffix"), "공용 '이기면 +N' 표를 부른다")
        #expect(!code.contains("이기면"), "관전 절 코드에 '이기면' 문구가 있다")
    }

    @Test("끝난 판 사유는 **3인칭**이다 — 관전자가 패자의 1인칭 문장을 읽으면 머리글과 어긋난다")
    func theEndReasonSpeaksInThirdPerson() {
        // 없으면: '내 기준' 표(`endReason(_:outcome:)` 꼴)를 가져다 쓰고 `outcome` 이 없어 **언제나 패자 쪽
        // 문장**이 나온다 — 같은 상자가 "흑 승리 / 기권했어요" 라는 자기모순을 말한다(오목 0ba552d).
        let watch = Self.finishedWatch()                    // 흑 승 · 기권
        #expect(GamesChessWatchStatus.headline(for: watch) == "흑 승리")
        let detail = GamesChessWatchStatus.detail(for: watch)
        #expect(detail == "백이 기권했어요", "진 쪽을 주어로 말하지 않는다: \(detail ?? "nil")")
        #expect(GamesChessText.watchEndReason(.timeout, winner: .white) == "흑의 시간이 다 됐어요")
        // ★ FIDE 6.9 — 깃발이 떨어졌는데 메이트 재료가 없으면 무승부다. **문구가** 그 경우를 말해야 한다.
        #expect(GamesChessText.watchEndReason(.timeoutInsufficient, winner: nil)
                == "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요")
        // 승자를 모르면 승패를 가르는 주어를 쓰지 않는다(지어내면 거짓말이다).
        #expect(GamesChessText.watchEndReason(.checkmate, winner: nil) == "체크메이트")
        // 열 갈래를 빠짐없이 말한다 — `default:` 로 접으면 `abandoned` 가 왜 끝났는지 못 말한다.
        for reason in ChessEndReason.allCases {
            #expect(!GamesChessText.watchEndReason(reason, winner: .black).isEmpty, "\(reason) 가 빈 문장이다")
        }
    }

    @Test("진행 중인 판에는 결과를 지어내지 않는다 — 남은 시간이 0 이어도 '그 사람 차례'다")
    func anOverdueClockIsNotAResult() {
        // 없으면: `chess_watch` 가 읽기 전용이라 시간이 다 된 판을 닫지 않는데(`ChessStoreWatch.swift` 머리말)
        // 화면이 "0 이니 졌겠지"로 결과를 지어낸다 — 관전자에게 거짓말하는 자리다.
        var watch = ChessSpectateState(id: "m-1")
        watch.black = Self.user("u-a", "민트별")
        watch.white = Self.user("u-b", "달토끼")
        watch.turn = .white
        watch.clock = ChessServerClock(whiteMsLeft: 0, blackMsLeft: 60_000, incrementMs: 3_000,
                                       turnStartedAt: Date(timeIntervalSince1970: 1_789_621_000), running: .white)
        #expect(GamesChessWatchStatus.kind(for: watch) == .turn(.white))
        #expect(GamesChessWatchStatus.headline(for: watch) == "관전 중 · 백 차례")
        #expect(GamesChessWatchStatus.detail(for: watch) == nil, "진행 중인 판에 결과 줄이 붙었다")
        // 첫 응답 전에는 색조차 모른다 — 돌 배지·차례를 말하지 않는다(로비 카드의 a/b 는 uuid 순서다).
        let cold = ChessSpectateState(id: "m-2")
        #expect(GamesChessWatchStatus.kind(for: cold) == .loading)
        #expect(GamesChessWatchStatus.headline(for: cold) == GamesChessText.watchLoading)
    }

    @Test("끝난 판에는 3분 꼬리를 말하고, 로딩을 말하지 않는다")
    func theFinishedWatchTellsTheThreeMinuteTail() throws {
        // 없으면: 3분이 지나 서버가 `not_found` 를 주는 순간 화면이 사라지는데 이유를 아무도 모른다.
        // 그리고 끝난 판에 진행형을 쓰면 한 화면이 "아직 안 불러왔다"와 "이미 끝났다"를 동시에 주장한다.
        #expect(GamesChessText.watchTailCaption.contains("3분"), "3분 꼬리를 말하지 않는다")
        let code = Self.stripComments(try Self.watchSource())
        let caption = try Self.body(of: "private var caption", in: code, length: 500)
        #expect(caption.contains("watch.isFinished"), "꼬리 문구가 끝난 판에만 서지 않는다")
        #expect(caption.contains("GamesChessText.watchTailCaption"))
        // 끝난 판의 두 사람 자리는 `LoadingRow` 가 아니다.
        let players = try Self.body(of: "private var players", in: code, length: 1_400)
        #expect(players.contains("if watch.isFinished"), "끝난 판 갈래가 없다")
        #expect(players.contains("GamesChessText.playersUnknown"))
    }

    // MARK: - 4. 세로 예산

    @Test("판은 **높이 예산**으로 정한다 — 너비만 보면 아래가 잘린다")
    func theBoardSizeComesFromTheHeightBudget() throws {
        // 없으면: iPhone SE 에서 기본 글자로도 백 카드가 잘리고 상태 상자가 통째로 화면 밖이다(오목 실측).
        // 상수의 산수를 여기서 검산한다 — 폰 화면은 맥이 그림을 그릴 수 없다.
        let blocks = GamesChessWatchBudget.blocksAroundBoard()
        let expected: CGFloat = (54 + 60 + 60 + 60) + 8 * 4
        #expect(blocks == expected, "블록 합이 바뀌었다: \(blocks)")

        // iPhone SE 375×667 → 뷰포트 554. 예산 288 이 폭 상한(343)보다 작아 **높이가 이긴다**.
        let se = try #require(GamesChessWatchBudget.boardCap(viewportHeight: 554))
        #expect(se == 554 - blocks)
        #expect(se < 343, "SE 에서 높이 상한이 폭보다 크다 — 예산이 아무것도 줄이지 않는다")
        // iPhone 15 393×852 → 뷰포트 739. 상한 472 는 폭 361 보다 크다 → **폭이 이긴다**(판을 괜히 줄이지 않는다).
        let fifteen = try #require(GamesChessWatchBudget.boardCap(viewportHeight: 739))
        #expect(fifteen == 472, "8의 배수로 안 내렸다: \(fifteen)")
        #expect(fifteen > 361)
        // 뷰포트를 아직 모르는 한 틱은 상한이 **없다**(그 한 틱에 판을 세로로 늘이지 않는다).
        #expect(GamesChessWatchBudget.boardCap(viewportHeight: 0) == nil)
        #expect(GamesChessWatchBudget.boardCap(viewportHeight: .infinity) == nil)
        // 터무니없이 좁은 자리에서도 음수·0 을 내지 않는다(칸이 0 이면 판이 빈 그림이 된다).
        let tiny = try #require(GamesChessWatchBudget.boardCap(viewportHeight: 100))
        #expect(tiny == GamesChessBoardMetrics.minimumSide)

        // 그리고 **그 상한을 판에 건다** — 뷰가 자기 손으로 한 변을 고르지 않는다.
        let code = Self.stripComments(try Self.watchSource())
        #expect(code.contains("GamesChessWatchBudget.boardCap(viewportHeight: viewportHeight)"),
                "판이 높이 예산을 안 쓴다")
        // 뷰포트는 **스크롤의 보이는 높이**다. `GeometryReader` 로 읽으면 제안 높이를 그대로 받아 뜻을 잃는다.
        #expect(code.contains("proxy.bounds(of: .scrollView)?.height"), "뷰포트를 스크롤에서 읽지 않는다")
        // `GeometryReader` 는 시계 띠(잎 뷰)에만 있고 **판 패널에는 없다** — 패널 블록만 좁혀 본다
        //  (파일 전체로 재면 시계 띠 때문에 영원히 빨갛다).
        let panel = try Self.body(of: "private struct GamesChessWatchPanel", in: code, length: 1_200)
        #expect(!panel.contains("GeometryReader"), "절이 스크롤 안에서 GeometryReader 로 높이를 읽는다")
    }

    @Test("관전 절은 로비 스크롤 **안의 절**이다 — 제 스크롤도, 떠 있는 아래 막대도 두지 않는다")
    func theWatchPanelIsASectionNotAScreen() throws {
        // 없으면: 로비 화면이 이 절을 자기 `ScrollView` 안에 그대로 넣으므로(다른 레인의 호출부가 그렇다)
        // 스크롤이 겹쳐 안쪽이 안 움직이고, `safeAreaInset` 막대가 로비 바닥에 눌러앉는다.
        let code = Self.stripComments(try Self.watchSource())
        #expect(!code.contains("ScrollView"), "절이 제 스크롤을 만든다")
        #expect(!code.contains("safeAreaInset"), "절이 떠 있는 막대를 만든다")
        // [나가기]는 **하나**이고 절 머리에 있다(스크롤 끝의 버튼은 거둘 길이 못 된다는 오목의 교훈을 머리로 지킨다).
        #expect(code.contains(".action(GamesChessText.leaveWatch) { store.leaveWatch() }"))
        #expect(code.components(separatedBy: "store.leaveWatch()").count - 1 == 1, "[나가기] 문이 두 벌이다")
    }

    // MARK: - 5. 순위 행 — 일곱 칸 · 0판 제외 · 목록 밖 내 순위

    @Test("순위 행은 **일곱 칸 전부**를 그린다 — 승점만 띄우면 안 된다(사용자 지시)")
    func theRankRowDrawsAllSevenCells() throws {
        // 없으면: 승점만 남고 전적이 사라진다. 오목에서 사용자가 직접 금지한 모양이고, 큰 글자에서는
        // 가로 고정 둘이 한 HStack 에 있다가 카드가 전적을 **잘라** 그 화면이 되살아났다.
        let row = Self.entry("u-x", "솜사탕", rank: 3, wins: 6, losses: 2, draws: 1)
        let label = GamesChessText.rankRowAccessibility(row, isMe: false)
        for cell in ["3위", "솜사탕", "승점 +4", "6승 2패 1무"] {
            #expect(label.contains(cell), "행이 \(cell) 를 말하지 않는다: \(label)")
        }
        #expect(GamesChessText.record(wins: 6, losses: 2, draws: 1) == "6승 2패 1무")
        // 승점은 부호를 보인다(색으로 말하지 않는다 — 폰 토큰 규약에서 초록·앰버는 근무의 뜻이다).
        #expect(GamesChessText.signedPoints(4) == "+4")
        #expect(GamesChessText.signedPoints(-2) == "−2")
        #expect(GamesChessText.signedPoints(0) == "0")
        // 내 행은 '나'를 먼저 읽는다(순위 원은 `accessibilityHidden` 이라 묶으면 순위가 안 읽힌다).
        #expect(GamesChessText.rankRowAccessibility(row, isMe: true).contains("나"))

        // 눈으로 보는 화면도 둘을 **같이** 그린다 — 세 갈래(큰 글자·한 줄·접힌 줄) 전부에서.
        let code = Self.stripComments(try Self.rankingSource())
        for name in ["private var inline", "private var stacked"] {
            let body = try Self.block(of: name, in: code)
            #expect(body.contains("pointsText"), "\(name) 에 승점이 없다")
            #expect(body.contains("recordText"), "\(name) 에 전적이 없다 — '승점만' 화면이다")
        }
        // 큰 글자 갈래는 쌓는다(`HStack` + 조각마다 `.fixedSize()` 는 카드가 오른쪽을 자른다).
        let stacked = try Self.block(of: "private var stacked", in: code)
        #expect(stacked.contains("VStack(alignment: .leading, spacing: 4)"))
        #expect(stacked.contains("fixedSize(horizontal: false, vertical: true)"))
        // 320pt 좁은 기기는 `ViewThatFits` 로 덮는다.
        #expect(code.contains("ViewThatFits(in: .horizontal)"), "좁은 폭 갈래가 없다")
        // 아바타는 공용 규칙 + **`characterHint`** 로 그린다(빠뜨리면 표가 안 온 세션에서 전원 이니셜).
        let face = try Self.body(of: "private var face", in: code, length: 400)
        #expect(face.contains("characterHint: entry.user.characterID"), "characterHint 를 빠뜨렸다")
        #expect(face.contains("userID: entry.user.id"))
    }

    @Test("0판인 사람은 순위 목록에 안 낀다 — 전원이 0판이면 '행이 있다'고 말하지도 않는다")
    func zeroGamePlayersAreNotListed() {
        // 없으면: 0승 0패 0무 줄이 순위표에 끼어 "이 사람은 왜 여기 있지?" 가 되고, 전적 컷 직후에는 그런
        // 줄이 사용자 수만큼 생긴다. 서버가 이미 걸러 주지만 그 약속을 화면이 다시 지킨다.
        let store = Self.store(entries: [
            Self.entry("u-a", "라이벌", rank: 1, wins: 5, losses: 1, draws: 0),
            Self.entry("u-z", "0판", rank: 2, wins: 0, losses: 0, draws: 0),
            Self.entry("u-b", "무승부만", rank: 3, wins: 0, losses: 0, draws: 2)   // 둔 판은 있다 — 남는다
        ])
        let held = GamesChessRankingPlan.held(store)
        #expect(held.map(\.user.displayName) == ["라이벌", "무승부만"], "0판 줄이 실렸다: \(held.map(\.user.displayName))")
        #expect(GamesChessRankingPlan.total(store) == 2)
        // 서버 순서는 그대로다(재정렬 금지) — 일부러 서버 규칙과 어긋난 입력으로 되묻는다.
        let unsorted = Self.store(entries: [
            Self.entry("u-a", "라이벌", rank: 3, wins: 1, losses: 1, draws: 0),
            Self.entry("u-b", "나", rank: 1, wins: 5, losses: 1, draws: 0)
        ])
        #expect(!ChessRankingOrder.isSorted(unsorted.ranking?.entries ?? []),
                "픽스처가 이미 서버 순서대로다 — 재정렬을 잡을 수 없다")
        #expect(GamesChessRankingPlan.held(unsorted).map(\.rank) == [3, 1], "화면이 행을 재정렬했다")

        // 동률 한 쌍(3위·3위 → 다음은 5위)도 **서버 숫자 그대로**다 — 화면이 순위를 다시 세면 4위가 생긴다.
        let ties = Self.store(entries: [
            Self.entry("u-1", "일위", rank: 1, wins: 9, losses: 1, draws: 0),
            Self.entry("u-2", "셋째A", rank: 3, wins: 4, losses: 2, draws: 0),
            Self.entry("u-3", "셋째B", rank: 3, wins: 4, losses: 2, draws: 0),
            Self.entry("u-4", "다섯째", rank: 5, wins: 1, losses: 2, draws: 0)
        ])
        #expect(GamesChessRankingPlan.held(ties).map(\.rank) == [1, 3, 3, 5], "동률 숫자를 다시 셌다")

        // 전원 0판이면 `.rows` 가 아니다(빈 카드를 그리지 않고 "아직 전적이 없어요"를 말한다).
        let allZero = Self.store(entries: [Self.entry("u-z", "0판", rank: 1, wins: 0, losses: 0, draws: 0)])
        #expect(GamesChessRankingPlan.content(allZero) == .empty, "0판만 있는 목록을 행으로 그린다")
    }

    @Test("내 순위는 **목록 밖이어도** 보인다 — 접힌 다섯 줄에 내가 없을 때 그 줄이 정보를 맡는다")
    func myRankShowsEvenWhenOutsideTheVisibleRows() throws {
        // 없으면: 12위인 사람은 자기 순위를 볼 길이 없다([전체 보기]를 눌러 열두 줄을 세어야 한다).
        let entries = (1...7).map { Self.entry("u-\($0)", "사람\($0)", rank: $0, wins: 8 - $0, losses: 1, draws: 0) }
        let store = Self.store(entries: entries, me: ChessMyRank(rank: 12, wins: 3, losses: 2, draws: 1, points: 1))
        let visible = GamesChessRankingPlan.visible(store, isExpanded: false)
        #expect(visible.count == 5, "접힌 줄 수가 다섯이 아니다: \(visible.count)")
        #expect(!visible.contains { $0.id == Self.mine }, "픽스처에 내 행이 들어 있다 — '목록 밖'을 못 잰다")
        let mine = try #require(GamesChessRankingPlan.myRank(store), "목록 밖 내 순위가 사라졌다")
        #expect(mine.rank == 12)
        #expect(GamesChessText.myRankLine(mine) == "12위 · 승점 +1 · 3승 2패 1무")
        // 0판이면 순위가 없다(서버가 `me.rank` 를 null 로 준다) — 0 으로 꾸미지 않는다.
        let zero = ChessMyRank(rank: nil, wins: 0, losses: 0, draws: 0, points: 0)
        #expect(GamesChessText.myRankLine(zero) == "순위 밖 · 0승 0패 0무")
        // 펼치면 전부 보이고 [전체 보기] 줄이 선다.
        #expect(GamesChessRankingPlan.visible(store, isExpanded: true).count == 7)
        #expect(GamesChessRankingPlan.showsToggle(store))
        #expect(GamesChessText.rankSeeAll(total: 7) == "전체 보기 · 7명")

        // 전적이 어긋나면(한쪽이 늦었다) 그 줄을 그리지 않는다 — "8승 3패 · 승점 +4" 같은 자기모순을 막는다.
        store.record = ChessRecord(wins: 9, losses: 9, draws: 9)
        #expect(GamesChessRankingPlan.myRank(store) == nil, "순위 응답과 로비 전적을 섞었다")
    }

    @Test("분기 순서: 행을 들고 있으면 \"곧 열려요\"보다 **행**이 먼저다")
    func heldRowsWinOverTheUnavailableFlag() {
        // 없으면: 순위 조회는 성공해 행을 들고 있는데 `chess_watch` 만 PGRST202 인 창에서 코어가 순위 깃발을
        // 세우고(`ChessStoreWatch.swift:320`), 화면이 **받아 둔 행을 통째로 버리고** "순위는 곧 열려요"를 말한다.
        // 오목에서 이 순서가 뒤집혀 있어 수리했다.
        let store = Self.store(entries: [Self.entry("u-a", "라이벌", rank: 1, wins: 5, losses: 1, draws: 0)])
        store.rankingUnavailable = true
        #expect(GamesChessRankingPlan.content(store) == .rows, "행이 있는데 '곧 열려요'가 떴다")

        // 거꾸로, 한 번도 못 받은 창은 "곧 열려요" 다 — 코어가 그 창을 '받은 것'으로 세기 때문에
        // `placeholder` 는 `.failed` 가 아니라 `.empty` 로 떨어진다(이 확인을 뒤로 미루면 "아직 전적이 없어요").
        let cold = ChessStore()
        cold.rankingUnavailable = true
        cold.hasLoadedRanking = true
        cold.rankingLoadFailed = false
        #expect(GamesChessRankingPlan.content(cold) == .soon, "준비 중인데 '아직 전적이 없어요'가 떴다")

        // 받았고 비었다 / 한 번도 못 받고 실패했다 / 아직 모른다.
        let empty = ChessStore()
        empty.hasLoadedRanking = true
        #expect(GamesChessRankingPlan.content(empty) == .empty)
        let failed = ChessStore()
        failed.rankingLoadFailed = true
        #expect(GamesChessRankingPlan.content(failed) == .failed)
        #expect(GamesChessRankingPlan.content(ChessStore()) == .loading)
        // 실패해도 **들고 있던 목록은 지우지 않는다**(폰 공용 규칙).
        let holding = Self.store(entries: [Self.entry("u-a", "라이벌", rank: 1, wins: 5, losses: 1, draws: 0)])
        holding.rankingLoadFailed = true
        #expect(GamesChessRankingPlan.content(holding) == .rows)
    }

    @Test("머리 오른쪽 캡션은 **한 번도 못 받았으면 아무것도 말하지 않는다**")
    func theHeaderCaptionStaysSilentUntilItKnowsTheCut() {
        // 없으면: 컷을 모르는데 "전체 기간"이라고 단정한다(거짓이다).
        #expect(GamesChessRankingPlan.sinceCaption(ChessStore()) == nil)
        let whole = Self.store(entries: [], recordSince: nil)
        #expect(GamesChessRankingPlan.sinceCaption(whole) == GamesChessText.rankWholePeriod)
        // 컷은 **KST 달력 값**이다 — 기기 시간대로 조립하면 비KST 기기에서 하루 밀린다(오목에서 고친 자리).
        // 2026-10-01 00:00 KST = 2026-09-30 15:00 UTC.
        let cut = Self.store(entries: [], recordSince: Date(timeIntervalSince1970: 1_790_780_400))
        #expect(GamesChessRankingPlan.sinceCaption(cut) == "10월 1일부터",
                "컷 캡션이 KST 가 아니다: \(GamesChessRankingPlan.sinceCaption(cut) ?? "nil")")
    }

    // MARK: - 6. 제자리 절 계약

    @Test("두 절은 **제자리**다 — 새 화면을 밀지 않는다(폴링이 죽는다)")
    func bothSectionsStayInPlace() throws {
        // 없으면: 자식 화면을 push 하는 순간 체스 화면의 `onDisappear` → `windowDidHide()` 로 폴링이 죽어
        // (`shouldPollWatch` 가 창을 본다) 순위·판이 영영 갱신되지 않는다. 오목에서 실증됐다.
        for source in [try Self.rankingSource(), try Self.watchSource()] {
            let code = Self.stripComments(source)
            for pushed in ["NavigationLink", "navigationDestination", ".sheet(", "fullScreenCover"] {
                #expect(!code.contains(pushed), "절이 새 화면을 민다(\(pushed))")
            }
        }
        // 공개 자리 이름(다른 레인이 그대로 부른다).
        #expect(Self.stripComments(try Self.rankingSource()).contains("struct GamesChessRankingSection: View"))
        #expect(Self.stripComments(try Self.watchSource()).contains("struct GamesChessWatchSection: View"))
    }

    // MARK: - 소스 읽기 (주석을 걷어낸다)

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func rankingSource() throws -> String {
        try source("Sources/CheckMobileKit/Games/GamesChessRanking.swift")
    }

    private static func watchSource() throws -> String {
        try source("Sources/CheckMobileKit/Games/GamesChessWatch.swift")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 줄 주석을 걷어낸다 — 안 걷으면 **설명문을 지워야만 초록**이 되는 테스트가 된다(하우스 규칙).
    static func stripComments(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// 선언 머리부터 **중괄호가 닫히는 곳까지**. 글자 수로 자르는 `body(of:in:length:)` 와 달리 다음 블록으로
    /// 새지 않는다 — 그 새는 창 때문에 "행에서 전적 지우기" 뮤테이션이 한 번 살아남았다(바로 아래 블록에
    /// 같은 이름이 있어 창이 그걸 읽었다). 블록 안을 재는 단언은 **이것만** 쓴다.
    static func block(of marker: String, in source: String) throws -> String {
        let stripped = source.contains("//") ? stripComments(source) : source
        let hit = try #require(stripped.range(of: marker), "대조: '\(marker)' 를 못 찾았다(이름이 바뀌었나)")
        var depth = 0
        var started = false
        var out = ""
        for character in stripped[hit.upperBound...] {
            if character == "{" {
                depth += 1
                started = true
            } else if character == "}" {
                depth -= 1
            }
            out.append(character)
            if started, depth == 0 { return out }
        }
        return out
    }

    /// 선언 머리부터 앞쪽 `length` 글자(주석은 이미 걷힌 소스를 넘겨도 되고, 안 걷힌 것을 넘기면 여기서 걷는다).
    static func body(of marker: String, in source: String, length: Int) throws -> String {
        let stripped = source.contains("//") ? stripComments(source) : source
        let hit = try #require(stripped.range(of: marker), "대조: '\(marker)' 를 못 찾았다(이름이 바뀌었나)")
        return String(stripped[hit.upperBound...].prefix(length))
    }
}
