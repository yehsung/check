import SwiftUI
import CheckCore

// 자리표시 — U1 갈래가 채운다.
//
// 아잉 큐브 창의 루트 화면(설계서 §5: 로비 · 판 · 결과 · 규칙). init 모양은 테트리스 `TetrisDuelPanel(store:me:safety:)` 와 같다.

struct RummyPanel: View {
    let store: RummyStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다 — 체스·테트리스와 같은 얼굴 값).
    var me: @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback }
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳. nil 이면 이니셜로 떨어진다.
    var safety: WorkTimerStore? = nil

    var body: some View {
        Text("아잉 큐브")
    }
}
