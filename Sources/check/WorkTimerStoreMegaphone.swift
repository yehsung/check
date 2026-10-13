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

    /// 상점을 여는 순간(`toggleShopPanel`) 확성기 값을 **미리** 읽는다 — 카드가 처음부터 "📢 확성기 · 💎50" 으로 서게
    /// (작성기를 한 번 열어야만 가격이 보이면 비용을 확인 질문에서야 처음 알게 된다). 가격은 여전히 서버 값뿐이다.
    /// 잔량 미러는 건드리지 않는다 — 같이 나간 `shop_state` 가 말하고, 늦게 도착한 이 응답이 그 사이의 구매 결과를 옛 잔량으로
    /// 덮으면 안 된다(`MegaphoneStore.loadInfo(mirrorsRubyBalance:)`).
    func prefetchMegaphoneInfo() {
        megaphone.loadInfo(mirrorsRubyBalance: false)
    }
}
