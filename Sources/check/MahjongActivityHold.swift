import Foundation

// MARK: - 아잉 마작 App Nap 붙들기 (SPEC §5.1 · MCL:113)
//
// 큐브 `RummyActivityHold`(`CK/RummyExitFlow.swift:329-357`)를 베낀 새 파일이다 — 큐브 파일은 고치지 않는다.
// 마작은 5초 시계의 **깨우기**(결정 주인은 자기 마감, 박자 기기는 고정 5초 걸음, 나머지는 백업 시각)가 판의 박자라,
// 창이 가려지거나 다른 앱이 앞에 있을 때 macOS 가 App Nap 으로 타이머를 합쳐 늦추면 시간 초과가 몰리고 남의 차례가 늘어진다.
// `.userInitiatedAllowingIdleSystemSleep` 이라 시스템 잠자기(뚜껑 닫기·유휴 잠자기)는 막지 않는다.
// 쥐는 때: **이 기기가 연 판**(장부 `ownsMatch`)이 방·판 단계이거나 연습판이 도는 동안. 놓는 때: 판 끝 · 로그아웃·계정 전환(`reset`).
// 스토어 신호에 잇는 배선은 통합 갈래(T)가 `CheckApp` 에서 한다.

@MainActor
final class MahjongActivityHold {
    static let reason = "아잉 마작 판 진행 중 — 차례 마감·깨우기를 제때 보낸다"
    private let begin: @MainActor (String) -> NSObjectProtocol
    private let end: @MainActor (NSObjectProtocol) -> Void
    private(set) var token: NSObjectProtocol?

    init(
        begin: @escaping @MainActor (String) -> NSObjectProtocol = { reason in
            ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: reason)
        },
        end: @escaping @MainActor (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }
    ) {
        self.begin = begin
        self.end = end
    }

    var isHolding: Bool { token != nil }

    /// 같은 값이 두 번 와도 활동은 하나만 쥔다.
    func set(_ holding: Bool) {
        if holding {
            guard token == nil else { return }
            token = begin(Self.reason)
        } else if let held = token {
            token = nil
            end(held)
        }
    }
}
