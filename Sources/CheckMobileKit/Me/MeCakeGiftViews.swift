#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 생일 선물 축하 시트 (폰 1.0.14 — 맥 0.3.66 축하 창의 짝)
//
// 상태 · 판정은 `MeStoreCakeGift.swift`(플랫폼 무관 — 맥 스위트가 값으로 잰다), 문구는 코어 `CakeGiftText`(맥과 같은 글자)다.
// 이 파일은 그리기만 한다. 띄우는 자리는 탭 막대 위(`MobileTabsView.cakeGiftSheet`) — 어느 탭에 있든 뜬다.

/// 축하 시트: 두 초상(전신 — 장식이 케이크의 핵심이라 원에 가두지 않는다) → 고르기 → [이걸로 받을게요] → 받은 뒤
/// "○○를 받았어요!" + [지금 입기] [닫기]. 실패하면 한 줄 안내를 보이고 다시 누르게 한다.
struct MeCakeGiftSheetView: View {
    let store: MeStore
    /// `.sheet(item:)` 클로저가 받은 값 — 시트가 **내려가는 동안**에도 쥐고 있는 마지막 상태다(스토어 값은 이미 nil).
    let item: MeCakeGiftSheet
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 그릴 상태: 같은 선물의 스토어 값이 있으면 그것(떠 있는 동안의 고르기 · 받는 중 · 받은 뒤), 없으면 받은 item(내려가는 중).
    /// 스토어 값만 보면 닫는 순간 nil 이 되어 내려가는 판이 텅 비었다(머리 [X] 만 남은 흰 판).
    private var sheet: MeCakeGiftSheet {
        if let live = store.cakeGiftSheet, live.id == item.id { return live }
        return item
    }

    var body: some View {
        VStack(spacing: 0) {
            // 받는 중에는 [X] 를 끈다 — 결과를 모른 채 닫히면 수령이 성공해도 받은 뒤 화면 · [지금 입기]가 안 선다
            // (스토어 `dismissCakeGiftSheet` 도 그 단계에선 닫지 않는다 — 두 겹).
            SheetHeader("", onClose: { store.dismissCakeGiftSheet() })
                .disabled(sheet.phase == .claiming)
            // 내용이 화면보다 짧으면 세로 가운데(큰 시트 아래가 텅 비지 않게 — 시뮬레이터 실측), 길면(큰 글자) 스크롤.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: MobileTheme.space4) {
                        switch sheet.phase {
                        case .choosing, .claiming:
                            choosing(sheet)
                        case .received(let id):
                            received(id)
                        case .closed:
                            closed(sheet)
                        }
                    }
                    .padding(.horizontal, MobileTheme.sideMargin)
                    .padding(.bottom, MobileTheme.space4)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            bottomBar(sheet)
        }
        .background(MobileTheme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(MobileTheme.surface)
        .presentationDragIndicator(.visible)
        // 받는 중에는 끌어 닫지 못한다(결과를 모른 채 닫히면 다시 열기 줄이 남았다가 다음 조회에서야 걷힌다).
        .interactiveDismissDisabled(sheet.phase == .claiming)
        .onAppear {
            store.cakeGiftSheetDidAppear()
            applyDemoActionIfAsked()
        }
        .onDisappear { store.cakeGiftSheetDidDisappear() }
    }

    // MARK: 고르기

    private func choosing(_ sheet: MeCakeGiftSheet) -> some View {
        VStack(spacing: MobileTheme.space4) {
            heading(title: CakeGiftText.title, body: CakeGiftText.body)
            if let note = sheet.gift.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: MobileTheme.space3))
                : AnyLayout(HStackLayout(alignment: .top, spacing: MobileTheme.space3))
            layout {
                ForEach(sheet.gift.options, id: \.self) { id in
                    optionCard(id, isSelected: sheet.selection == id, isLocked: sheet.phase != .choosing)
                }
            }
            if let notice = sheet.notice {
                InlineNotice(text: notice, kind: .warning)
            }
        }
    }

    private func optionCard(_ id: String, isSelected: Bool, isLocked: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        let name = MeCharacterName.display(id)
        return Button {
            store.selectCakeGiftOption(id)
        } label: {
            VStack(spacing: MobileTheme.space2) {
                CharacterPortrait(id: id, mood: .plain, size: 132, framed: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MobileTheme.space2)
                    .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(MobileTheme.surface2))
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? MobileTheme.accent : MobileTheme.label)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MobileTheme.space2)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    shape.fill(MobileTheme.surface)
                    if isSelected { shape.fill(MobileTheme.accentTint) }
                }
            }
            .overlay { shape.strokeBorder(isSelected ? MobileTheme.accent : MobileTheme.separator, lineWidth: isSelected ? 2 : 1) }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MobileTheme.onAccentFill)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(MobileTheme.accentFill))
                        .offset(x: -6, y: 6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 받은 뒤 · 끝난 선물

    private func received(_ id: String) -> some View {
        VStack(spacing: MobileTheme.space4) {
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(RadialGradient(colors: [MobileTheme.accent.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 80))
                    .frame(width: 150, height: 28)
                // 초상 원본은 192px 다 — 너무 키우면 흐리다(168pt 실측). 나 탭 무대(132)와 비슷한 크기로.
                CharacterPortrait(id: id, mood: .plain, size: 144, framed: false)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
                    .padding(.bottom, 10)
            }
            .padding(.top, MobileTheme.space4)
            .accessibilityHidden(true)
            heading(title: CakeGiftText.received(name: MeCharacterName.display(id)), body: nil)
        }
    }

    private func closed(_ sheet: MeCakeGiftSheet) -> some View {
        VStack(spacing: MobileTheme.space4) {
            heading(title: CakeGiftText.title, body: nil)
            if let notice = sheet.notice {
                InlineNotice(text: notice, kind: .info)
            }
        }
    }

    private func heading(title: String, body: String?) -> some View {
        VStack(spacing: MobileTheme.space2) {
            Text(title)
                .font(MobileTheme.title(.title2))
                .foregroundStyle(MobileTheme.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let body {
                Text(body)
                    .font(.body)
                    .foregroundStyle(MobileTheme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 아래 단추

    @ViewBuilder
    private func bottomBar(_ sheet: MeCakeGiftSheet) -> some View {
        VStack(spacing: MobileTheme.space2) {
            switch sheet.phase {
            case .choosing, .claiming:
                AingButton(CakeGiftText.confirmButton, kind: .filled, size: .lg, fillsWidth: true,
                           isBusy: sheet.phase == .claiming) {
                    store.confirmCakeGift()
                }
                .disabled(!sheet.canConfirm && sheet.phase != .claiming)
            case .received:
                AingButton(CakeGiftText.wearNowButton, kind: .filled, size: .lg, fillsWidth: true) {
                    store.wearReceivedCakeGift()
                }
                AingButton(CakeGiftText.closeButton, kind: .tinted, size: .lg, fillsWidth: true) {
                    store.dismissCakeGiftSheet()
                }
            case .closed:
                AingButton(CakeGiftText.closeButton, kind: .tinted, size: .lg, fillsWidth: true) {
                    store.dismissCakeGiftSheet()
                }
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space2)
        .padding(.bottom, MobileTheme.space3)
    }

    /// 데모(DEBUG) 스크린샷: `me/gift/picked` 는 첫 선택지를 골라 두고, `me/gift/received` 는 골라서 받는다(픽스처 응답 — 서버에 닿지 않는다).
    private func applyDemoActionIfAsked() {
        guard let action = MeDemoHooks.takeCakeGiftAction(), let first = sheet.gift.options.first else { return }
        switch action {
        case "picked":
            store.selectCakeGiftOption(first)
        case "received":
            store.selectCakeGiftOption(first)
            store.confirmCakeGift()
        default:
            break
        }
    }
}

// MARK: - 나 탭 '다시 열기' 줄

/// 고르지 않고 닫은 열린 선물 — 나 탭 무대 카드 바로 아래에 **수령할 때까지** 선다("생일 선물이 도착했어요" [고르기]).
struct MeCakeGiftReopenRow: View {
    let store: MeStore

    var body: some View {
        if store.showsCakeGiftReopen {
            AingCard {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MobileTheme.space3) {
                        icon
                        title.lineLimit(1)
                        Spacer(minLength: MobileTheme.space2)
                        button
                    }
                    VStack(alignment: .leading, spacing: MobileTheme.space2) {
                        HStack(spacing: MobileTheme.space3) {
                            icon
                            title.fixedSize(horizontal: false, vertical: true)
                        }
                        button
                    }
                }
            }
        }
    }

    private var icon: some View {
        Text("🎂")
            .font(.system(size: 22))
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MobileTheme.accentTint))
            .accessibilityHidden(true)
    }

    private var title: some View {
        Text(CakeGiftText.reopenTitle)
            .font(.body.weight(.semibold))
            .foregroundStyle(MobileTheme.label)
    }

    private var button: some View {
        // 틴트 — 나 탭에는 이미 채운 버튼(주간 [받기])이 있다(채운 버튼은 화면당 하나 — 버튼 3단 규칙).
        // [고르기]는 서버에 다시 묻고 연다(`reopenCakeGift`) — 묻는 동안 단추가 돈다(겹쳐 누르기 막기).
        AingButton(CakeGiftText.reopenButton, kind: .tinted, size: .md, isBusy: store.cakeGiftReopening) {
            store.reopenCakeGift()
        }
    }
}
#endif
