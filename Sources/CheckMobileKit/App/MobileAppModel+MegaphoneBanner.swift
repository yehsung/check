import CheckCore
import CheckMobileShared
import Foundation

// 확성기 배너 · 폰 앱 모델 배선(계약 docs/plan/megaphone-banner-contract.md — 폰 배너).
// 뷰(`MegaphoneBannerOverlay`)는 그리기·손짓만 하고, 미룸 판정은 여기서 한다(맥 스위트가 잰다). 단추는 [닫기]뿐 — 스토어를 바로 부른다.

extension MobileAppModel {
    /// 지금 배너를 미뤄야 하는가 — 시트·풀스크린 커버 · 오목·체스·테트리스 화면 · 미니게임 판 진행 중.
    /// 스토어의 `isBannerDeferred` 가 이 값을 본다(앱 모델 init 이 건다).
    package var isMegaphoneBannerDeferred: Bool {
        MegaphoneBannerPhoneRules.isDeferred(
            modalPresented: megaphoneModalProbe(),
            matchScreenVisible: games.isAnyMatchScreenVisible,
            miniGameRoundPlaying: games.miniGames.controller?.isPlaying ?? false
        )
    }

    /// 미룸이 바뀌었으면 스토어에 알린다(배너 오버레이가 대결 화면 변화 · 1초 다시 보기에서 부른다).
    package func syncMegaphoneBannerDeferral() {
        let store = megaphoneBanner
        guard MegaphoneBannerPhoneRules.needsDeferralSync(
            isDeferred: isMegaphoneBannerDeferred,
            hasCurrent: store.current != nil,
            hasQueue: !store.queue.isEmpty
        ) else { return }
        store.deferralChanged()
    }
}
