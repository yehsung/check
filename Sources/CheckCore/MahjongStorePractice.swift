import Foundation

// 아잉 마작 스토어 — 혼자 연습판(혼자 + 봇 셋, SPEC §4.5 '연습판' · CC-02 · D40). 표면만(C1) — 몸통은 갈래 C3
// (E 엔진 · B 봇이 선 뒤). 리버시 `ReversiStoreAI.swift` 함수 목록을 이름만 바꿔 채운다.
//
// 약속(C3 가 지킨다):
//  · `practice` 칸 안에서만 돈다 — 서버 `match` 를 안 건드리고, 화면은 `table` 한 길로 그린다.
//  · 봇 결정은 `Task.detached(priority: .userInitiated)` 에서 `MahjongBot.decide` — 입력은 메인에서 만든 payload 사본,
//    결과는 세대·판·seq 확인 뒤 메인에서 적용(CC-09). 봇 사이 정지 0.5~1.0초.
//  · 창이 탁자를 보이지 않으면(숨김·가림 둘 다) 판 전체가 멈춘다(봇도) — `isWindowShowingTable` 하나만 읽는다.
//  · 시간 제한은 `practiceTimed` 일 때만. '넉넉히'에서 론 아닌 울기 프롬프트는 5초 뒤 안내 한 줄, 30초 뒤 저절로 넘김.
//  · 루비·기록·미션·네트워크 0. 루비 판이 서면 버린다(`matchDidChange`).

extension MahjongStore {
    /// '넉넉히' 연습판에서 론 아닌 울기 프롬프트를 저절로 넘기기까지(초, CC-28 설계 상수).
    nonisolated static let practiceIdleCallPassSeconds: TimeInterval = 30
    /// '넉넉히' 연습판에서 울기 안내 한 줄을 띄우기까지(초).
    nonisolated static let practiceIdleCallHintSeconds: TimeInterval = 5

    /// 연습판을 연다(연습 세대만 올리고 서버 표를 건드리지 않는다).
    package func startPractice(format: MahjongFormat, timed: Bool) {
        // C3: 엔진 deal · practice = MahjongPracticeSession(…) · showsPractice = true · 봇 차례 예약.
        _ = (format, timed)
    }

    /// 같은 설정으로 새 연습판.
    package func restartPractice() {
        guard let current = practice else { return }
        startPractice(format: current.format, timed: current.timed)
    }

    /// 연습판을 닫는다. 서버 방이 있으면 방이 선다.
    package func endPractice() {
        // C3: 봇 작업 취소 · 세대 올림.
        practice = nil
        if showsPractice { showsPractice = false }
        recomputePhase()
    }

    /// 띠의 [방 보기] — 연습은 그대로 두고 방을 본다.
    package func showRoom() {
        if showsPractice { showsPractice = false }
        // C3: 연습 일시정지.
        recomputePhase()
    }

    /// 연습으로 돌아가기.
    package func showPractice() {
        guard practice != nil else { return }
        if !showsPractice { showsPractice = true }
        recomputePhase()
    }
}
