import Foundation

// 아잉 뒤집기 관전 — 스토어 확장과 값 타입. 계약은 설계서 FLIP/SPEC.md §3.4(reversi_watch · reversi_watch_live) · §3.6 · §4.4.
// 틀은 체스 `ChessStoreWatch`: 관전 2초 폴링 · 관전 세대 · watch_live 가 없으면 watch 로 한 번 접기
// (`spectatorCountUnavailable`) · watch 도 없으면 `watchUnavailable`(관전 잠금은 이 깃발 하나로만).
// 관전은 phase 가 아니라 로비 안의 `spectating != nil` 로 갈린다. 내 판이 서면 관전은 내려간다.
// 이 파일은 **C1 뼈대**다 — 조회 몸통은 C2 가 채운다.

/// 지금 보고 있는 남의 판. 첫 ok 응답 전에는 로비 카드에서 빌린 얼굴·판돈만 있다.
package nonisolated struct ReversiSpectating: Identifiable, Equatable, Sendable {
    /// match id 소문자.
    package let id: String
    /// 로비 카드에서 빌린 두 얼굴(a·b 순서, **색 모름**). 씨앗을 못 찾았으면 비어 있다.
    package var faces: [ReversiUser]
    /// 판돈. 씨앗이 없으면 nil 이고 응답의 `match.stake` 가 채운다.
    package var stake: Int?
    /// 서버가 말한 흑·백. **첫 ok 응답 전에는 nil** — 이 둘이 서기 전에는 색 배지를 그리지 않는다.
    package var blackUser: ReversiUser?
    package var whiteUser: ReversiUser?
    package var board: ReversiBoard
    package var moveCount: Int
    /// 내가 반영한 마지막 수 번호. 다음 요청의 `p_since_seq` 다.
    package var appliedSeq: Int
    package var plies: [ReversiPly]
    package var lastStoneIdx: Int?
    package var autoStones: Set<Int>
    /// 끝나면 nil.
    package var turn: ReversiColor?
    package var turnStartedAt: Date?
    /// 표시 마감(차례 시작 + 30초). 끝났으면 nil.
    package var deadline: Date?
    package var counts: ReversiCounts
    package var score: ReversiScore?
    package var result: ReversiResult?
    package var endReason: ReversiEndReason?
    /// 이긴 색. 끝났는데 nil 이면 무승부다.
    package var winner: ReversiColor?
    package var blackAutoStreak: Int
    package var whiteAutoStreak: Int
    package var startedAt: Date?
    package var isFinished: Bool
    /// 관전자 수(watch_live 만 채운다).
    package var watchers: Int

    package init(
        id: String, faces: [ReversiUser] = [], stake: Int? = nil, blackUser: ReversiUser? = nil,
        whiteUser: ReversiUser? = nil, board: ReversiBoard = .start, moveCount: Int = 0, appliedSeq: Int = 0,
        plies: [ReversiPly] = [], lastStoneIdx: Int? = nil, autoStones: Set<Int> = [], turn: ReversiColor? = nil,
        turnStartedAt: Date? = nil, deadline: Date? = nil, counts: ReversiCounts? = nil, score: ReversiScore? = nil,
        result: ReversiResult? = nil, endReason: ReversiEndReason? = nil, winner: ReversiColor? = nil,
        blackAutoStreak: Int = 0, whiteAutoStreak: Int = 0, startedAt: Date? = nil, isFinished: Bool = false,
        watchers: Int = 0
    ) {
        self.id = id
        self.faces = faces
        self.stake = stake
        self.blackUser = blackUser
        self.whiteUser = whiteUser
        self.board = board
        self.moveCount = moveCount
        self.appliedSeq = appliedSeq
        self.plies = plies
        self.lastStoneIdx = lastStoneIdx
        self.autoStones = autoStones
        self.turn = turn
        self.turnStartedAt = turnStartedAt
        self.deadline = deadline
        self.counts = counts ?? board.counts
        self.score = score
        self.result = result
        self.endReason = endReason
        self.winner = winner
        self.blackAutoStreak = blackAutoStreak
        self.whiteAutoStreak = whiteAutoStreak
        self.startedAt = startedAt
        self.isFinished = isFinished
        self.watchers = watchers
    }
}

extension ReversiStore {
    /// 로비 "지금 대결 중" 줄의 [관전]. — C2 가 채운다.
    package func startWatching(matchID: String) {}
    /// 관전 화면의 [나가기](로비로). — C2 가 채운다.
    package func leaveWatch() {}
    /// 창 닫기·초기화로 관전을 조용히 내린다(문구 없음). — C2 가 채운다.
    package func stopWatching() {}
}
