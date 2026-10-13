import CheckCore
import Foundation

// MARK: - 확성기(📢) — 맥 배선 (v0.3.51)
//
// 판정·문구·요청 id·세대 가드는 전부 코어 `MegaphoneStore` 에 있다(폰과 한 벌 — Sources/CheckCore/Megaphone.swift 머리말).
// 맥이 더하는 것은 **문 하나**뿐이다: 상점 패널의 '📢 확성기' 카드가 작성기를 열고 닫는다. 작성기는 캐릭터 격자와 구매 바 자리를
// 빌려 그려서(CheckShopPanel) 팝오버 700pt 예산을 새로 쓰지 않는다.
//
// 루비 잔량은 호스트 미러(`rubyBalance`)를 코어 스토어가 직접 고친다 — 상점 제목 줄의 큰 루비 칩이 같은 값을 읽는다.

@MainActor
extension WorkTimerStore {
    /// 상점의 '📢 확성기' 카드. 열려 있으면 접고, 아니면 고른 상품을 풀고 작성기를 연다(작성기가 하단 바 자리를 쓴다 —
    /// 고른 상품이 남아 있으면 작성기를 접는 순간 하단 바가 엉뚱한 것을 말한다).
    func toggleMegaphoneComposer() {
        if megaphone.isComposerOpen {
            megaphone.close()
            return
        }
        // 구매 왕복 중에는 열지 않는다(그 결과 한 줄이 곧 도착한다 — 카드들이 잠겨 있는 것과 같은 규약).
        guard purchasingID == nil else { return }
        shopSelection = nil
        shopNotice = nil
        megaphone.open()
    }
}
