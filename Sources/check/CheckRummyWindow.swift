import AppKit
import SwiftUI
import CheckCore

// 자리표시 — U1 갈래가 채운다.
//
// 아잉 큐브 창. 계약은 설계서 §5: 테트리스 창(CheckTetrisDuelWindow.swift) 계약 그대로 — 지연 생성 · 멱등 show ·
// 닫아도 파괴 안 함 · 고정 크기 1240×700 · .darkAqua · `CheckPanelVisibility.panelAlpha` · 고착 감시 · 닫기/가림 통지 분리.
// 루트는 `RummyPanel(store:me:safety:)` + `.checkTooltipLayer().appUserAvatarCharacters(from: safety)`.
// 뼈대(K)는 배선 자리(`configure`)와 진입점(`show`)만 둔다 — 창 생성은 다음 갈래.

/// 아잉 큐브 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다.**
@MainActor
final class CheckRummyWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckRummyWindowController()

    /// 창 제목(§1). CGWindowList 로 밖에서 창을 셀 때의 표식이다.
    static let windowTitle = "아잉 큐브"

    /// 창 위치를 기억하는 키 = 창 식별자(§1). **다른 창과 겹치면 안 된다.**
    static let frameAutosaveName = "check.rummy.window"

    private var store: RummyStore?
    private var me: @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback }
    private weak var safety: WorkTimerStore?

    override init() {
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. `me` 는 내 이름·캐릭터를 읽는 문이다(테트리스와 같은 타입). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(
        store: RummyStore,
        me: @escaping @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback },
        safety: WorkTimerStore? = nil
    ) {
        self.store = store
        self.me = me
        self.safety = safety
    }

    // MARK: - 창

    /// 창을 띄운다(멱등). 자리표시 — 창 생성은 U1 갈래 몫.
    func show() {}
}
