import Foundation

// 아잉 뒤집기 AI 연습 판(로컬) — 스토어 확장. 계약은 설계서 FLIP/SPEC.md §4.4 · DEC:20.
//
// 루비·기록 없음 · 단일 난이도 · 생각 상한 1.5초 · 서버 변경 없음(`"ai-"` id 머리말이 서버 경로를 막는다 —
// refreshMatch·syncOnce·pollTick·onMatchFinished). 사람 차례 30초 뒤 무작위 자동 착수 · 연속 3회 패 ·
// 창이 안 보이면 사람 시계를 멈춘다. 사람이 둘 곳이 없어 AI 차례가 연달아 오는 것이 정상 경로다.
//
// 이 파일은 **C1 뼈대**다 — 오목 `GomokuStoreAI` 함수 목록(start·restart·handleAIClock·place·resign·pause·resume·discard·
// commit·scheduleAITurnIfNeeded·applyAIMove·scheduleAIClock)을 C2 가 이름만 바꿔 채운다.

extension ReversiStore {
    /// AI 가 지금 생각 중인가(AI 판 · 안 끝남 · AI 차례). 선수 카드가 "생각 중"을 그린다.
    package var isAIThinking: Bool {
        guard let match, match.isAI, !match.isFinished, let turn = match.turn else { return false }
        return turn == match.myColor.opponent
    }

    /// 로비에서 AI 대국을 시작할 수 있는가. 1:1 판이 열려 있거나 보낸 신청이 떠 있으면 안 된다 —
    /// 신청이 수락되는 순간 1:1 이 AI 판을 이기므로 두던 판이 사라진다.
    package var canStartAIMatch: Bool {
        phase == .lobby && match == nil && outgoing == nil && !isBusy
    }

    /// AI 판을 연다. `humanColor` nil = 무작위. — C2 가 채운다.
    package func startAIMatch(humanColor: ReversiColor?) {}

    /// 같은 색으로 새 AI 판(결과 카드 [다시 두기]). — C2 가 채운다.
    package func restartAIMatch() {}
}
