import CheckCore
import CoreGraphics
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 1:1 테트리스 **관전 절**(폰 · 0.3.65) — 남의 진행 중인 판을 **읽기 전용**으로 본다.
// 본은 폰 체스 관전(`GamesChessWatch.swift`)이고, 테트리스에서 달라지는 자리만 바꿨다.
//
// ── 자리 계약(부르는 쪽이 지킨다) ──
// 이 절은 **로비 스크롤 안의 한 절**이다. 새 라우트도, 새 화면도 아니다: 자식 화면을 push 하면 테트리스 화면의
// `onDisappear` → `tetrisScreenDidDisappear()` 로 스토어 폴링이 죽어(`shouldPollWatch` 가 창을 본다) 판이
// 갱신되지 않는다. 로비 화면(`GamesTetrisDuelScreen.liveMatches`)은 "지금 대결 중" 자리를 이 패널로 **갈아
// 끼우기만** 한다 — [관전]을 누른 자리가 그대로 판이 되므로 화면이 튀지 않는다.
// 그래서 이 절은 **제 스크롤도, 떠 있는 아래 막대도 만들지 않는다**(둘 다 로비 스크롤과 싸운다).
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesTetrisWatchPlan` · `GamesTetrisWatchStatus` · `GamesTetrisWatchBudget`)은 `#if os(iOS)`
// **밖**이다. 폰 뷰는 맥 스위트가 한 줄도 못 보므로(저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 판정을 뷰에
// 묻어 두면 게이트를 되돌려도 전부 초록이 된다 — 오목에서 실제로 613건이 그랬다.
//
// ── 입력이 하나도 없다 ──
// 탭·끌기·버튼·기권이 전부 없다. 판은 순수 그림이고 손가락 상자(`GamesTetrisDuelTouch`)를 **만들지 않는다**.
// 값으로 떼어 둔 까닭은 재기 위해서다(`GamesTetrisWatchPlan.boardTapHandler` 등) — 뷰 안에 nil 을 적어 두면
// 누가 거기에 처리기를 끼워도 맥 스위트가 모른다.
//
// ── 승자는 서버가 말한 것만 ──
// `tetris_watch` 는 읽기 전용이라 상한(480초)이 지난 판도 닫지 않는다. "시간이 다 됐으니 누가 이겼겠지" 로
// 결과를 만들지 않는다(체스 0.3.41 이 데인 자리 · 코어 `TetrisDuelStoreWatch.swift` 머리말).
// 끝난 판의 승자는 **서버가 실은 `match.winner`(uuid)** 한 곳에서만 온다 — 코어가 그 uuid 가 어느 자리의
// 사람인지만 보고 `aWon`·`bWon` 을 세운다. ★ `result`('challenger_win'…)로 역산하지 마라: 관전 봉투에는
// 누가 challenger 인지가 없고 a/b 는 **uuid 오름차순 자리**일 뿐이다.
// ★ **둘 다 거짓인 정상 상태가 있다**(무승부 · 진행 중 · 승자 칸을 모르는 옛 서버 · 그 자리의 사람을 아직
// 못 받은 틱). 그때는 승자를 말하지 않는다.
// 그리고 승자를 말할 때도 **3인칭**이다("밥 승리") — 관전자에게는 둘 다 남이라 "이겼어요" 는 누구 이야기인지
// 알 수 없다(`TetrisPhoneText.watchEndReason` 머리말이 적어 둔 그 함정과 같은 태도).
// 탑아웃한 쪽은 `side.toppedOut` 이 **직접** 말하므로 그 자리를 흐리게 그린다.

/// 관전 입구·관전 판의 **순수 판정**(맥에서 돈다). 색·글꼴은 고르지 않는다.
@MainActor
enum GamesTetrisWatchPlan {
    /// 로비 "지금 대결 중" 한 행의 오른쪽 끝에 서는 것(체스 `GamesChessWatchPlan.Entry` 와 같은 표).
    enum Entry: Equatable, Sendable {
        /// 아무것도 두지 않는다(주 스위치가 꺼진 배선).
        case absent
        /// 내 판 — 캡션만(관전에 못 들어간다).
        case myMatch
        /// 서버에 `tetris_watch` 가 아직 없다 — 캡션만.
        case soon
        /// [관전] 칩.
        case chip
    }

    /// 관전 입구 판정.
    ///
    /// ★ **주 스위치가 꺼진 배선에서는 칩 자체를 두지 않는다.** `startWatching` 이 `spectatorFeaturesEnabled` 를
    ///   먼저 보고 조용히 돌아서므로 눌러도 아무 일이 없는 버튼이 된다(오목·체스와 같은 게이트).
    ///
    /// ★ **잠금은 `watchUnavailable` 하나로 판정한다.** `rankingUnavailable`(순위표가 없다)·
    ///   `spectatorCountUnavailable`(관전자 수만 없다)과 **겸업시키지 마라** — 뒤엣것으로 잠그면 "관전자 수가
    ///   없다" 는 이유로 멀쩡한 관전이 통째로 막힌다(체스가 `rankingUnavailable` 겸업으로 데인 자리).
    ///   [[client-gates-come-in-pairs]]
    static func entry(_ store: TetrisDuelStore, isMine: Bool) -> Entry {
        guard store.spectatorFeaturesEnabled else { return .absent }
        if isMine { return .myMatch }
        if store.watchUnavailable { return .soon }
        return .chip
    }

    // MARK: 관전 판에 넘기는 값 — 입력이 0건인 자리

    /// 판의 탭 처리기. ★ **늘 nil 이다** — 관전자는 조각을 못 움직인다.
    static let boardTapHandler: (() -> Void)? = nil
    /// 판 위 끌기 처리기. ★ 늘 nil.
    static let boardDragHandler: ((CGSize) -> Void)? = nil
    /// 조작 버튼(홀드·회전·바로 내리기). ★ 늘 비어 있다.
    static let controls: [String] = []
    /// [기권] 을 그리는가. ★ 늘 거짓 — 관전자에게는 걸린 판돈이 없다.
    static let showsResign = false

    /// 이 자리를 흐리게 그리는가 — **탑아웃은 서버가 말한 사실**이다(`tetris_players.topped_out`).
    /// 시간·결과로 역산하지 않는다.
    static func dims(_ side: TetrisSpectateSide) -> Bool { side.toppedOut }

    /// 로비 줄의 **오른쪽 끝 슬롯이 무엇이든 그리는가** — 입구(위) 또는 관전자 수.
    ///
    /// ★ 줄의 폭 재보기(`ViewThatFits`)와 슬롯 내용이 **이 하나**를 본다. 조건을 두 곳에 적으면 한쪽만
    ///   고쳐져 "빈 슬롯 때문에 줄을 접는" 꼴이 되고, 그 상태가 초록으로 남는다(체스 줄의 그 당부와 같다).
    ///
    /// ★ 관전자 수는 **주 스위치와 무관**하다: 로비 응답이 실어 온 사실이고, 관전에 들어갈 수 있는가와는
    ///   다른 축이다(스위치가 꺼진 배선에서도 수는 보인다).
    static func hasTrailingContent(_ store: TetrisDuelStore, live: TetrisDuelLiveMatch) -> Bool {
        entry(store, isMine: store.isMine(live)) != .absent || GamesWatcherCount.shows(live.watchers)
    }

    // MARK: 탭 — "안 보이는데 ping 한다" 를 0 으로

    /// 관전 판이 **그려지는** 탭인가. 관전 판은 로비 "지금 대결 중" 자리를 갈아 끼우는 절이고(파일 머리
    /// '자리 계약'), 그 자리는 [상대] 탭에만 있다.
    ///
    /// 탭이 늘어나면 이 한 줄이 먼저 막는다 — 새 탭을 그냥 더하면 아래 `tabDidChange` 가 저절로 "안 보이는
    /// 탭" 으로 센다(관전이 유령이 되는 쪽으로 기울지 않는다).
    static func showsWatch(on tab: GamesTetrisLobbyTab) -> Bool { tab == .opponents }

    /// 로비 탭이 바뀌었다 — **관전 판이 안 보이게 되는 탭으로 가면 관전을 내린다.**
    ///
    /// ── 왜 이 길인가(두 길 중 ①) ──
    /// 고치기 전에는 [순위] 로 바꾸면 화면에서 관전 판만 사라지고 `spectating` 은 살아 있었다. 코어의
    /// `shouldPollWatch` 는 **탭을 모른다**(창·단계·주 스위치만 본다) — 그래서 아무것도 안 보이는 사람이
    /// 2초마다 `tetris_watch_live` 를 쳐서 **남의 카드에 관전자 1명으로 잡히고, 나갈 문([나가기])은 그
    /// 사라진 절 안에 있었다.**
    ///
    /// 다른 길(②: 탭과 무관하게 관전 판을 보여 준다 = 관전이 탭을 덮는다)을 고르지 않은 까닭:
    /// 체스는 탭이 없어 관전이 '제자리 절' 로 늘 붙어 있을 수 있지만, 여기는 **사람이 방금 [순위]를 눌렀다**.
    /// 그 손짓에 테트리스 판 두 장을 돌려주면 누른 것과 다른 것이 오고, 분절 컨트롤은 [순위]가 눌린 채로
    /// 남아 거짓말을 한다. 관전은 [관전] 한 번으로 언제든 다시 들어갈 수 있는 값싼 상태이므로,
    /// **눈에서 사라지는 것과 요청이 끊기는 것을 같은 순간으로 묶는 쪽**이 사람에게 정직하다.
    /// 대신 **돌아와도 관전이 되살아나지 않는다** — 그것이 이 선택의 값이다.
    ///
    /// `leaveWatch()` 가 문 하나다(`stopWatching()` 은 낡은 목록을 남긴다 — 로비로 돌아올 자리이므로
    /// 로비를 다시 읽는 쪽을 부른다). 관전 중이 아닐 때는 아무것도 하지 않는다(헛 조회를 내지 않는다).
    static func tabDidChange(_ store: TetrisDuelStore, to tab: GamesTetrisLobbyTab) {
        guard !showsWatch(on: tab), store.isSpectating else { return }
        store.leaveWatch()
    }
}

/// 관전 상태 한 줄의 판정(순수).
///
/// ★ **마감이 지나도 결과를 지어내지 않는다** — `tetris_watch` 는 읽기 전용이라 상한이 지난 판을 닫지 않으므로
/// "시간이 다 됐는데 아직 active" 인 판을 볼 수 있다. 그래서 이 판정에는 **시각이 들어오지 않는다**
/// (시각이 바꿀 문구가 없다 = 상태 상자에 타이머가 없다).
enum GamesTetrisWatchStatus {
    enum Kind: Equatable, Sendable {
        /// 첫 응답 전(두 판을 아직 모른다).
        case loading
        case live
        case ended
    }

    static func kind(for watch: TetrisSpectateState) -> Kind {
        if watch.isFinished { return .ended }
        return watch.hasServerState ? .live : .loading
    }

    /// 머리 한 줄. 끝난 판은 **이긴 사람을 3인칭으로** 부른다("밥 승리") — 자리는 서버가 실은
    /// `match.winner` 만 가른다(`aWon`/`bWon`). 승자를 모르는 정상 상태 셋(무승부 · 옛 서버 · 사람을 아직
    /// 못 받은 틱)에서는 **이름을 지어내지 않는다**(파일 머리말).
    static func headline(for watch: TetrisSpectateState) -> String {
        switch kind(for: watch) {
        case .ended:
            if let winner = winnerName(for: watch) { return TetrisPhoneText.watchEndedWin(winner) }
            return watch.result == "draw" ? TetrisPhoneText.watchEndedDraw : TetrisPhoneText.watchEnded
        case .loading:
            return TetrisPhoneText.watchLoading
        case .live:
            return TetrisPhoneText.playingNow
        }
    }

    /// 이긴 사람의 **부를 수 있는 이름**. 승자를 모르면 nil 이고, 승자는 아는데 이름이 비어 있어도 nil 이다 —
    /// "— 승리" 는 아무도 가리키지 못하면서 다 끝난 것처럼 들린다(그때는 `watchEnded` 가 더 정직하다).
    static func winnerName(for watch: TetrisSpectateState) -> String? {
        let side: TetrisSpectateSide
        if watch.aWon { side = watch.a } else if watch.bWon { side = watch.b } else { return nil }
        let name = side.user?.displayName ?? ""
        return name.isEmpty ? nil : name
    }

    /// 자리의 표시 이름. 사람을 모르거나 **이름이 빈 문자열**이면 "—"(코어 경계가 이름을 모를 때 nil 이 아니라
    /// 빈 문자열을 넣는다 — `??` 로는 못 접는다). 뷰와 위 승자 판정이 같은 규칙을 쓴다.
    static func displayName(_ side: TetrisSpectateSide) -> String {
        let name = side.user?.displayName ?? ""
        return name.isEmpty ? TetrisPhoneText.watchUnknownName : name
    }

    /// 둘째 줄. **끝난 판에만 있다**(진행 중에는 머리 한 줄로 끝 — 지어낼 말이 없다). 사유는 **3인칭**이다.
    static func detail(for watch: TetrisSpectateState) -> String? {
        guard watch.isFinished else { return nil }
        let reason = TetrisPhoneText.watchEndReason(watch.endReason)
        return reason.isEmpty ? nil : reason
    }
}

/// 두 판을 나란히 세울 때의 **칸 변(pt) 예산**(순수 — 맥에서 산수만 잰다).
///
/// ★ **폭만 보면 아래가 잘린다**: 테트리스 판은 세로가 가로의 두 배다(10×20). 폭으로만 칸을 정하면
/// iPhone SE(375×667)에서 판 높이가 300pt 를 넘어 상태 상자·캡션이 통째로 화면 밖으로 밀린다
/// (체스 관전이 같은 자리에서 높이 예산으로 고쳤다). 그래서 **폭과 높이 둘 다** 보고 작은 쪽을 쓴다.
///
/// 상수마다 어디서 나온 숫자인지 적는다(폰 전용 화면이라 맥 `swift test` 가 그림을 그릴 수 없다 —
/// 다음 사람이 손으로 검산할 수 있어야 한다).
enum GamesTetrisWatchBudget {
    /// 두 판 사이 틈 — `MobileTheme.space3`(12). 그 토큰은 iOS 전용이라 숫자를 옮겨 적는다.
    static let columnGap: CGFloat = 12
    /// 칸 변 하한. 이보다 작으면 방해 줄 회색과 조각 색이 구분되지 않는다(대결 화면 미니 판이 5pt 다 —
    /// 관전은 그보다 작아질 이유가 없다).
    static let minimumCell: CGFloat = 5
    /// 칸 변 상한. 큰 화면에서 판 두 장이 화면을 통째로 먹지 않게 — 12pt 면 한 판이 124×244 다.
    static let maximumCell: CGFloat = 12

    /// 절 머리(`SectionHeader(padded: true)` + 오른쪽 [나가기]): 위 22 + title3 24 + 아래 8 = 54.
    static let sectionHeader: CGFloat = 22 + 24 + 8
    /// 판 아래 이름·숫자 카드: 이름 줄 21 + 숫자 세 줄(16×3) + 위아래 8씩 = 85.
    /// ★ "위아래 8" 은 **8×2** 다(이 파일의 `sectionHeader` 만 위 22·아래 8 로 비대칭이고 나머지는 전부 N×2 다 —
    ///   체스 `GamesChessWatchBudget.playerCard` 도 `44 + 8*2` 다). 손 검산을 77 로 적어 둔 적이 있는데, 폰 전용
    ///   화면이라 맥 스위트가 그림을 못 그려 **이 주석이 유일한 검산표**다 — 8pt 틀린 예산을 전제로 다음 사람이
    ///   상태 상자에 줄을 더하면 접근성 글자에서 판이 하한으로 쪼그라드는 경계가 어긋난 채 잡힌다.
    static let playerCard: CGFloat = 21 + 16 * 3 + 8 * 2
    /// 상태 상자: subheadline 두 줄(20×2) + 위아래 10 = 60(끝난 판이 두 줄이다).
    static let statusBox: CGFloat = 20 * 2 + 10 * 2
    /// 판돈 줄 한 칸(`InsetGroup` + `GroupRow`): 부제 18 + 위아래 10 = 38.
    static let stakeRow: CGFloat = 18 + 10 * 2
    /// `VStack(spacing: MobileTheme.space2)` — 8.
    static let gap: CGFloat = 8

    /// 판 위·아래에서 자리를 먹는 블록의 합(간격 포함). 캡션은 세지 않는다 — 스크롤로 닿으면 되는 것이다.
    static func blocksAroundBoards() -> CGFloat {
        let blocks: [CGFloat] = [sectionHeader, playerCard, statusBox, stakeRow]
        return blocks.reduce(0, +) + gap * CGFloat(blocks.count)
    }

    /// 한 칸 변(pt).
    ///
    /// - Parameters:
    ///   - availableWidth: 절이 쓸 수 있는 가로(양옆 여백을 이미 뺀 값).
    ///   - viewportHeight: 로비 스크롤의 **보이는 높이**(0 이면 아직 모른다 → 폭만 본다).
    ///
    /// 검산(블록 합 = 54+77+60+38 + 8×4 = 261):
    /// - iPhone SE 375 → 가로 343, 한 열 (343−12)/2 = 165.5 → 폭 칸 (165.5−4)/10 = 16.15.
    ///   뷰포트 ≈ 667 − 64 − 49 = 554 → 예산 293 → 높이 칸 (293−4)/20 = 14.45. **상한 12 가 이긴다.**
    /// - 접근성 글자로 블록이 커져 예산이 204 아래로 내려가면 높이 칸이 10pt 아래가 되어 그쪽이 이긴다.
    /// - 아주 좁은 화면(320 Display Zoom): 한 열 (288−12)/2 = 138 → 폭 칸 13.4 → 여전히 상한 12.
    ///   즉 **보통은 상한**이고, 예산이 모자랄 때만 줄어든다(그 자리가 이 식의 존재 이유다).
    static func cell(availableWidth: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let inset = TetrisMiniBoardLayout.inset
        let column = max(0, (availableWidth - columnGap) / 2)
        var cell = (column - inset * 2) / CGFloat(TetrisGame.columns)
        if viewportHeight.isFinite, viewportHeight > 0 {
            let budget = viewportHeight - blocksAroundBoards()
            cell = min(cell, (budget - inset * 2) / CGFloat(TetrisGame.visibleRows))
        }
        return min(maximumCell, max(minimumCell, cell))
    }
}

#if os(iOS)

// MARK: - 관전 판 (로비 "지금 대결 중" 자리)

/// 테트리스 관전 판 — "지금 대결 중" 절이 **그 자리에서** 이 모양으로 바뀐다(파일 머리 '자리 계약').
/// 그래서 **제 스크롤도 떠 있는 아래 막대도 두지 않는다**.
///
/// 위에서부터: 절 머리(+오른쪽 [나가기]) · 두 판 나란히(+ 각 판 아래 이름·숫자) · 상태 상자 · 판돈·관전자 수 · 캡션.
/// **입력이 하나도 없다**.
struct GamesTetrisWatchPanel: View {
    let store: TetrisDuelStore
    let watch: TetrisSpectateState

    /// 로비 스크롤의 **보이는 높이**와 이 절이 쓸 수 있는 **가로**. 둘이 칸 변을 정한다(0 이면 아직 모른다).
    /// 절이 스크롤 **안**에 있어 세로는 `GeometryReader` 로 못 읽는다 — `bounds(of: .scrollView)` 가 유일한 길이다.
    /// 가로는 제 `size.width` 로 충분하다(스크롤 안에서도 가로는 제안값이 곧 실제다).
    @State private var viewportHeight: CGFloat = 0
    @State private var sectionWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            header
            boards
            statusBox
            info
            caption
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            CGSize(width: proxy.size.width, height: proxy.bounds(of: .scrollView)?.height ?? 0)
        } action: { measured in
            if measured.height != viewportHeight { viewportHeight = measured.height }
            if measured.width != sectionWidth { sectionWidth = measured.width }
        }
    }

    /// 절 머리 + 오른쪽 [나가기]. 문은 **하나**다 — `leaveWatch()` 가 관전을 내리고 로비를 다시 읽는다
    /// (`stopWatching()` 을 부르면 낡은 목록으로 돌아온다).
    private var header: some View {
        SectionHeader(TetrisPhoneText.watchTitle,
                      trailing: .action(TetrisPhoneText.leaveWatch) { store.leaveWatch() },
                      padded: true)
            .accessibilityHint(TetrisPhoneText.leaveWatchHint)
    }

    // MARK: 두 판

    /// 두 사람 판을 **나란히**(a · b — uuid 오름차순이고 색이 아니다). 칸 변은 예산 표 한 곳이 정한다.
    ///
    /// ★ `GeometryReader` 를 쓰지 않는다 — 스크롤 안에서는 제안 높이를 그대로 먹어 절이 세로로 늘어진다.
    ///   가로는 바깥에서 `onGeometryChange` 로 재 두었고, 판 한 장은 제 크기를 스스로 안다(`frame(width:height:)`).
    private var boards: some View {
        let cell = GamesTetrisWatchBudget.cell(availableWidth: sectionWidth, viewportHeight: viewportHeight)
        return HStack(alignment: .top, spacing: GamesTetrisWatchBudget.columnGap) {
            side(watch.a, cell: cell)
            side(watch.b, cell: cell)
        }
        .frame(maxWidth: .infinity)
    }

    /// 한 자리: 판 · 이름 · 숫자 셋. 탑아웃한 쪽은 흐리게(서버가 말한 사실 — `GamesTetrisWatchPlan.dims`).
    private func side(_ value: TetrisSpectateSide, cell: CGFloat) -> some View {
        let dimmed = GamesTetrisWatchPlan.dims(value)
        // 이름은 **판정 겹 한 곳**이 고른다 — 머리 한 줄의 "밥 승리" 와 판 라벨이 다른 이름을 부르면
        // 같은 사람이 둘로 읽힌다(그리고 맥 스위트는 뷰 안의 식을 못 본다).
        let name = GamesTetrisWatchStatus.displayName(value)
        return VStack(alignment: .leading, spacing: MobileTheme.space2) {
            ZStack {
                GamesTetrisWatchBoard(cells: value.cells, cell: cell)
                if dimmed {
                    Text(TetrisPhoneText.toppedOutTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MobileTheme.danger)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .fixedSize()
                        .allowsHitTesting(false)
                }
            }
            .opacity(dimmed ? 0.55 : 1)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TetrisPhoneText.watchBoardAccessibility(
                name: name, lines: value.lines, pending: value.pending))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    CharacterPortrait(id: value.user?.characterID, mood: .plain, size: 22)
                    Text(name)
                        .font(MobileTheme.rowTitle)
                        .foregroundStyle(MobileTheme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                stat(TetrisPhoneText.linesTitle, value.lines, tint: MobileTheme.label)
                stat(TetrisPhoneText.attackTitle, value.attackSent, tint: MobileTheme.working)
                stat(TetrisPhoneText.incomingLinesTitle, value.pending,
                     tint: value.pending > 0 ? MobileTheme.danger : MobileTheme.label2)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func stat(_ title: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(MobileTheme.label2)
            Spacer(minLength: 2)
            Text(String(value))
                .font(MobileTheme.roundedNumber(.subheadline, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 상태 · 판돈 · 관전자 수

    private var statusBox: some View {
        let kind = GamesTetrisWatchStatus.kind(for: watch)
        let tint = Self.tint(kind)
        // 글자는 `label` 이고 뜻은 기호·바탕이 낸다(공용 `InlineNotice` 와 같은 문법).
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(kind))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(GamesTetrisWatchStatus.headline(for: watch))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let detail = GamesTetrisWatchStatus.detail(for: watch) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    /// 진행 중은 초록 · 끝은 청회색 · 모름은 회색. **빨강은 쓰지 않는다** — 관전자에게 결과를 지어내는 색이다.
    private static func tint(_ kind: GamesTetrisWatchStatus.Kind) -> Color {
        switch kind {
        case .loading: return MobileTheme.label2
        case .live: return MobileTheme.working
        case .ended: return MobileTheme.offWork
        }
    }

    private static func symbol(_ kind: GamesTetrisWatchStatus.Kind) -> String {
        switch kind {
        case .loading: return "hourglass"
        case .live: return "eye"
        case .ended: return "flag.checkered"
        }
    }

    /// 판돈 **액수만**(관전자는 이 판에서 한 푼도 얻지 못한다 — 접미사를 붙이지 않는다) + 관전자 수.
    private var info: some View {
        InsetGroup {
            GroupRow(divider: .none) {
                if let stake = watch.stake {
                    GamesStakeLine(stake: stake, prefix: TetrisPhoneText.stakeTitle)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                } else {
                    Text(TetrisPhoneText.watchStakeUnknown)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                }
                Spacer(minLength: MobileTheme.space2)
                GamesWatcherBadge(count: store.spectatorCount)
            }
        }
    }

    /// 카드 밑 작은 줄: 입력이 없다는 사실 + 끝난 판의 3분 꼬리.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TetrisPhoneText.watchCaption)
                .fixedSize(horizontal: false, vertical: true)
            if watch.isFinished {
                Text(TetrisPhoneText.watchTailCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 관전 판 한 장

/// 관전 판 한 장. 그림은 **코어 painter 한 벌**(`TetrisBoardPainter.drawMiniBoard`)이고 여기서 칸을 새로 칠하지
/// 않는다 — 방해 줄 회색이 화면마다 달라지면 맥과 폰의 같은 판이 다르게 보인다.
///
/// `cells` 가 nil 이면 **빈 우물**을 그린다(아직 보고가 없거나 글자가 어긋나 코어가 그 자리만 접은 판).
/// 망가진 판 때문에 화면이 서지 않는 것이 이 자리의 계약이다.
private struct GamesTetrisWatchBoard: View {
    let cells: [[TetrisDuelCell]]?
    let cell: CGFloat

    private var size: CGSize { TetrisMiniBoardLayout.boardSize(cell: cell) }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var canvas = context
            TetrisBoardPainter.drawMiniBoard(cells ?? [], into: &canvas, size: size, cell: cell)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - 로비 행의 관전 입구

/// 로비 "지금 대결 중" 한 줄의 오른쪽 끝: **관전자 수** + [관전] 입구.
///
/// 판정은 `GamesTetrisWatchPlan.entry` **하나**다(뷰가 깃발을 다시 읽지 않는다 — 그래야 맥 스위트가 게이트를
/// 잴 수 있고, `watchUnavailable` 을 다른 깃발로 바꾸면 빨개진다).
struct GamesTetrisWatchEntry: View {
    let store: TetrisDuelStore
    let live: TetrisDuelLiveMatch

    var body: some View {
        if GamesTetrisWatchPlan.hasTrailingContent(store, live: live) {
            HStack(spacing: 6) {
                GamesWatcherBadge(count: live.watchers)
                control
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch GamesTetrisWatchPlan.entry(store, isMine: store.isMine(live)) {
        case .absent:
            EmptyView()
        case .myMatch:
            // 수락 직후·로비 주기 사이에 내 판이 잠깐 목록에 보이는 틈이 있어, 비워 두면 "왜 내 판만 칩이
            // 없나"로 읽힌다.
            caption(TetrisPhoneText.myMatch, voiceOver: nil)
        case .soon:
            // 서버에 **관전이** 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창). 또렷한 칩을 흐려만 두면
            // 눈으로 보는 사용자는 이유를 알 길이 없다(폰엔 호버 툴팁이 없다) — 그래서 칩을 빼고 이유를 글자로.
            caption(TetrisPhoneText.watchSoonCaption, voiceOver: TetrisDuelNoticeText.unavailable)
        case .chip:
            AingButton(TetrisPhoneText.watchChip, kind: .tinted, size: .sm) {
                store.startWatching(matchID: live.id)
            }
            .fixedSize()
            .accessibilityHint(TetrisPhoneText.watchChipHint)
        }
    }

    private func caption(_ text: String, voiceOver: String?) -> some View {
        Text(text)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize()
            // 짧게 자른 것은 눈으로 보는 폭 때문이지 뜻을 줄인 게 아니다.
            .accessibilityLabel(Text(voiceOver ?? text))
    }
}

#endif
