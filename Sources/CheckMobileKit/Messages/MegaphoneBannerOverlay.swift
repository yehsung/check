#if os(iOS)
import CheckCore
import SwiftUI
import UIKit

/// 확성기 배너(폰) — 앱을 보고 있으면 어느 탭이든 위에서 내려오는 카드(계약 docs/plan/megaphone-banner-contract.md — 폰 배너).
///
/// - 자리: `MobileTabsView` 의 `TabView` 에 `.overlay(alignment: .top)` 로 붙는다. 세이프에어리어 아래에 놓인다 — 이 화면은
///   `ignoresSafeArea` 를 쓰지 않는다(상태바·다이내믹 아일랜드를 덮지 않는다). 좌우 여백 `MobileTheme.sideMargin`.
/// - 손: **카드만** 손을 받는다. 바깥은 빈 자리라 터치가 그대로 아래 화면(게임 캔버스 포함)으로 간다 — 화면 가득한 틀·바탕을 두지 마라.
///   누르고 있는 동안 보여 주는 시간(코어 `MegaphoneBannerRules.displaySeconds` — 5초) 타이머가 멈추고(`pauseTimer`),
///   놓으면 다시 센다(`resumeTimer`). 위로 쓸거나 [닫기]를 누르면 닫힌다. 아무것도 안 하면 그 시간 뒤 스스로 올라간다.
///   ★ 보이스오버가 켜져 있으면 저절로 올리지 않는다(코어 `holdsAutoDismiss` — 5초 안에 본문을 다 못 듣는다). [닫기] 동작으로만 닫힌다.
///   켬·끔은 `voiceOverStatusDidChangeNotification` 으로 다시 판단한다.
/// - 단추: [닫기] 하나뿐이다(2026-10-30 사용자 결정 — [답장]을 걷었다).
/// - 움직임: 위에서 미끄러져 내려오고 올라가며 나간다(이동만 — 불투명도는 이징하지 않는다). 동작 줄이기면 페이드만.
/// - 미룸: 시트·풀스크린 커버 · 대결 화면 · 미니게임 판(`MobileAppModel.isMegaphoneBannerDeferred`). 시트는 SwiftUI 가 알려 주지 않으므로
///   떠 있거나 기다리는 배너가 있을 때만 1초마다 다시 본다.
struct MegaphoneBannerOverlay: View {
    let model: MobileAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardHeight: CGFloat = MegaphoneBannerPhoneRules.assumedCardHeight

    private var store: MegaphoneBannerStore { model.megaphoneBanner }

    var body: some View {
        let pollKey = MegaphoneBannerPhoneRules.deferralPollKey(currentID: store.current?.id, queueCount: store.queue.count)
        ZStack(alignment: .top) {
            if let banner = store.current {
                MegaphoneBannerInteractiveCard(
                    banner: banner,
                    store: store,
                    onClose: { store.dismissCurrent() }
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MegaphoneBannerPhoneRules.topGap)
                .transition(transition)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.25), value: store.current?.id)
        .onAppear { store.holdsAutoDismiss = { UIAccessibility.isVoiceOverRunning } }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            store.autoDismissHoldChanged()
        }
        .onChange(of: model.games.isAnyMatchScreenVisible) { _, _ in
            model.syncMegaphoneBannerDeferral()
        }
        .task(id: pollKey) {
            guard pollKey != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(MegaphoneBannerPhoneRules.deferralPollSeconds))
                guard !Task.isCancelled else { return }
                model.syncMegaphoneBannerDeferral()
            }
        }
    }

    /// 들어올 때 0.25초 내려오고, 나갈 때 0.2초 올라간다. 동작 줄이기면 페이드만.
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let hidden = MegaphoneBannerPhoneRules.slideOutOffset(cardHeight: cardHeight)
        return .asymmetric(
            insertion: .offset(y: hidden).animation(.easeOut(duration: 0.25)),
            removal: .offset(y: hidden).animation(.easeIn(duration: 0.2))
        )
    }
}

/// 카드 한 장 + 손짓(누르고 있기 · 위로 쓸기). 끌림 상태는 카드마다 따로 쥔다(다음 장은 0 에서 시작).
private struct MegaphoneBannerInteractiveCard: View {
    let banner: MegaphoneBanner
    let store: MegaphoneBannerStore
    let onClose: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var isPressing = false

    var body: some View {
        MegaphoneBannerCard(banner: banner, onClose: onClose)
            .contentShape(RoundedRectangle(cornerRadius: MegaphoneBannerPhoneRules.cornerRadius, style: .continuous))
            .simultaneousGesture(pressAndSwipe)
            .offset(y: dragOffset)
            .accessibilityAction(named: Text(MegaphoneBannerPhoneText.close)) { onClose() }
    }

    /// 손가락이 닿는 순간 멈추고, 놓을 때 위로 쓸었으면 닫고 아니면 제자리로 돌아가 다시 센다.
    /// 전역 좌표로 잰다 — 카드가 손을 따라 움직여도 끌린 양이 흔들리지 않는다. 안의 버튼 탭과 함께 산다(`simultaneousGesture`).
    private var pressAndSwipe: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    store.pauseTimer()
                }
                dragOffset = MegaphoneBannerPhoneRules.dragOffset(translation: value.translation.height)
            }
            .onEnded { value in
                isPressing = false
                if MegaphoneBannerPhoneRules.swipeDismisses(
                    translation: value.translation.height,
                    predictedEnd: value.predictedEndTranslation.height
                ) {
                    store.dismissCurrent()
                } else {
                    withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
                    store.resumeTimer()
                }
            }
    }
}

/// 카드 모양: 유리 둥근 카드 · 아바타 · 닉네임 · 📢 · 본문(최대 4줄) · [닫기].
private struct MegaphoneBannerCard: View {
    let banner: MegaphoneBanner
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PersonAvatar(name: banner.senderName, url: banner.senderAvatarURL, userID: banner.senderID, size: 36)
                Text(banner.senderName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(1)
                Text(MegaphoneText.icon)
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            Text(banner.body)
                .font(.body.weight(.semibold))
                .foregroundStyle(MobileTheme.label)
                .lineLimit(MegaphoneBannerPhoneRules.bodyLineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                AingButton(MegaphoneBannerPhoneText.close, kind: .gray, size: .md) { onClose() }
            }
        }
        .padding(16)
        .background(GlassBackground(shape: RoundedRectangle(cornerRadius: MegaphoneBannerPhoneRules.cornerRadius, style: .continuous)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(MegaphoneBannerPhoneText.accessibilityLabel(name: banner.senderName, body: banner.body)))
        .accessibilityHint(Text(MegaphoneBannerPhoneText.accessibilityHint))
    }
}
#endif
