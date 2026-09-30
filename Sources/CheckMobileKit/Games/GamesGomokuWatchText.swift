import CheckCore
import Foundation

// 관전 화면(0.3.41) 문구 · 상태 판정. **맥과 같은 뜻이면 같은 문장이다** — 맥 `GomokuText` 의 관전 절
// (Sources/check/GomokuPanel.swift)을 그대로 옮겼다(`GamesText.swift` 머리 주석의 규약). 폰에서 처음 쓴 줄만 `// 폰`.
//
// 이 파일은 `#if os(iOS)` 로 감싸지 않는다 — 글자와 **순수 판정**뿐이라 맥 `swift test` 가 값으로 잴 수 있다
// (`GamesText.swift` · `GamesGomokuBoardLayout.swift` 와 같은 자리). 색은 여기서 고르지 않는다 —
// `Kind` 만 돌려주고 토큰은 뷰가 고른다(`GamesGomokuWatch.swift`).

extension GomokuPhoneText {
    // MARK: 관전 (0.3.41)

    package static let watching = "관전 중"
    /// 첫 응답 전(얼굴만 · 색 없음 — 함정 1). 씨앗조차 없는 판(로비 목록에서 이미 빠진 판을 눌렀다)도 같은 줄이다.
    package static let watchLoading = "판을 불러오고 있어요"
    package static func watchTurn(_ color: GomokuColor) -> String { "\(watching) · \(stoneShort(color)) 차례" }
    /// 마감이 지났다. **"졌다"·"시간 초과"로 쓰지 않는다**(함정 2) — 따라잡기는 대국자 조회·매분 크론 몫이고
    /// 관전자는 아무것도 쓰지 못한다. 색도 danger 가 아니라 대기색이다(뷰의 `tint`).
    package static let watchAutoPending = "\(watching) · 시간이 지나 곧 자동으로 놓여요"
    /// 자동 착수 연속이 한 번 남은 사람. 대국자 본인이 보는 `GomokuNoticeText.autoStreakWarning` 과 같은 사실을 이름으로 말한다.
    package static func watchStreakWarning(name: String) -> String { "\(name)님이 한 번 더 놓치면 져요" }
    package static let watchEndedTitle = "대국이 끝났어요"
    /// 끝난 판 한 줄. 이긴 사람이 없으면 무승부다.
    package static func watchEnded(winnerName: String?, reason: GomokuEndReason?) -> String {
        guard let winnerName else { return "무승부 · \(watchReason(reason))" }
        return "\(watchEndedTitle) · \(winnerName) 승 (\(watchReason(reason)))"
    }
    /// 끝난 이유의 짧은 이름 — 관전자는 승패 당사자가 아니라 "상대가"·"내가" 없이 사실만 말한다
    /// (같은 사유를 대국자에게 말하는 표는 `endReason(_:outcome:)`).
    package static func watchReason(_ reason: GomokuEndReason?) -> String {
        switch reason {
        case .five?: return "오목"
        case .resign?: return "기권"
        case .abandoned?: return "자리 비움"
        case .timeout?: return "시간이 다 됐어요"
        case .boardFull?: return "판이 가득 찼어요"
        case nil: return "끝"
        }
    }
    /// 관전은 판만이다 — 서버 응답에 채팅 키 자체가 없다(관전자 수도 없다).
    package static let watchNoChat = "대국자 채팅은 보이지 않아요"
    package static func watchMoves(_ count: Int) -> String { "\(count)수" }
    package static let leaveWatch = "나가기"
    /// 폰: [나가기] 보이스오버 힌트(맥 툴팁 `leaveWatchHelp` 자리 — 폰에는 호버가 없다).
    package static let leaveWatchHint = "로비로 돌아가요"
    /// 폰: 판돈을 아직 모른다(씨앗 없이 들어온 판의 첫 응답 전) — 맥 판돈 칩의 "—"와 같은 자리.
    package static let watchStakeUnknown = "\(stakeTitle) —"

    /// 보이스오버: 관전 판 전체를 한 요소로(돌 수 · 마지막 수 · 누구 차례). 금수 자리는 세지 않는다 — 관전은 입력이 없다(함정 3).
    package static func watchBoardAccessibility(_ watch: GomokuSpectateState) -> String {
        var black = 0
        var white = 0
        for y in 0..<GomokuBoard.size {
            for x in 0..<GomokuBoard.size {
                guard let point = GomokuPoint(x: x, y: y) else { continue }
                switch watch.board[point] {
                case .black?: black += 1
                case .white?: white += 1
                case nil: break
                }
            }
        }
        var parts = ["오목판", "흑 \(black)개", "백 \(white)개"]
        parts.append(watch.lastMove.map { "마지막 수 \($0.notation)" } ?? "아직 둔 돌이 없어요")
        if watch.isFinished {
            parts.append(watchEndedTitle)
        } else if let turn = watch.turn {
            parts.append(watchTurn(turn))
        } else {
            parts.append(watchLoading)
        }
        return parts.joined(separator: ", ")
    }
}

/// 관전 상태 한 줄의 판정(순수 — 맥 `GomokuWatchStatusRule` 과 같은 표). 시각은 **잎 뷰가 넘긴다**:
/// 화면 루트가 시계를 읽으면 1초마다 판까지 다시 그려지고, 스토어 값에만 기대면 마감이 지나도 문구가 영영 안 바뀐다
/// (관전자의 2초 폴은 같은 상태를 받아 "값이 바뀔 때만 대입"에 걸린다).
///
/// **마감이 지나도 "졌다"가 아니다**(함정 2). 따라잡기(자동 착수)는 대국자 조회·매분 정리가 하고 관전자는 아무것도 쓰지 못한다 —
/// 화면은 "곧 자동으로 놓여요"만 말하고 결과는 서버가 finished 를 준 뒤에만 말한다.
package enum GomokuPhoneWatchStatus {
    package enum Kind: Equatable, Sendable {
        /// 첫 응답 전(색·차례를 모른다 — 함정 1).
        case loading
        case turn(GomokuColor)
        /// 마감이 지났는데 아직 진행 중 — 자동 착수 대기.
        case overdue
        case ended
    }

    package static func kind(for watch: GomokuSpectateState, now: Date) -> Kind {
        if watch.isFinished { return .ended }
        guard watch.hasServerState, let turn = watch.turn else { return .loading }
        if let deadline = watch.deadline, deadline <= now { return .overdue }
        return .turn(turn)
    }

    package static func text(for watch: GomokuSpectateState, now: Date) -> String {
        switch kind(for: watch, now: now) {
        case .loading: return GomokuPhoneText.watchLoading
        case .turn(let color): return GomokuPhoneText.watchTurn(color)
        case .overdue: return GomokuPhoneText.watchAutoPending
        case .ended: return GomokuPhoneText.watchEnded(winnerName: winnerName(of: watch), reason: watch.endReason)
        }
    }

    /// 이긴 사람의 이름. 이긴 색은 있는데 사람 행이 없으면(프로필 삭제 등) 색 이름으로 — 무승부로 읽히면 안 된다.
    package static func winnerName(of watch: GomokuSpectateState) -> String? {
        switch watch.winner {
        case .black?: return watch.black?.displayName ?? GomokuPhoneText.stoneShort(.black)
        case .white?: return watch.white?.displayName ?? GomokuPhoneText.stoneShort(.white)
        case nil: return nil
        }
    }

    /// 자동 착수 연속이 **한 번 남은** 사람의 경고(끝난 판·첫 응답 전에는 없다). 둘 다면 흑부터 — 한 줄만 둔다.
    package static func streakWarning(for watch: GomokuSpectateState, lossStreak: Int) -> String? {
        guard !watch.isFinished, watch.hasServerState else { return nil }
        if watch.blackAutoStreak == lossStreak - 1, let name = watch.black?.displayName {
            return GomokuPhoneText.watchStreakWarning(name: name)
        }
        if watch.whiteAutoStreak == lossStreak - 1, let name = watch.white?.displayName {
            return GomokuPhoneText.watchStreakWarning(name: name)
        }
        return nil
    }
}
