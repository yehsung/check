import Foundation

// MARK: - 1:1 길건너 App Nap 붙들기 (SPEC v1.3 §9.1 · MC:129 — 설계 결정)
//
// 마작 `MahjongActivityHold`(CK/MahjongActivityHold.swift)를 베낀 새 파일이다 — 마작 파일은 고치지 않는다.
// 길건너 1:1 은 판 루프(0.05초)와 보고(변화 2초 · 정체 3초 · 프레임 확인되면 체크포인트)가 판의 박자다. 창이 가려지거나 다른
// 앱이 앞에 있을 때 macOS 가 App Nap 으로 타이머를 합쳐 늦추면 보고가 밀려 서버가 15초 침묵 패를 낸다(거짓 패배).
// `.userInitiatedAllowingIdleSystemSleep` 이라 시스템 잠자기(뚜껑 닫기·유휴 잠자기)는 막지 않는다.
// 쥐는 때: 스토어 `holdsActivity`(카운트다운 · 판 중이고 이 기기가 연 판). 놓는 때: 판 끝 · 로비 · 로그아웃·계정 전환.
// 스토어 신호(`onHoldingActivityChange`)에 잇는 배선은 통합 갈래(T)가 `CheckApp` 에서 한다(§9.5 #13).

@MainActor
final class CrossyDuelActivityHold {
    static let reason = "1:1 길건너 판 진행 중 — 점수 보고를 제때 보낸다"
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
