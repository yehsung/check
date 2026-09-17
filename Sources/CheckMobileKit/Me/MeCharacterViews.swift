#if os(iOS)
import CheckCore
import SwiftUI

// MARK: - 상점

/// 상점(캐릭터만). 카드를 누르면 **고르기만** 하고, 아래 막대의 [구매하기] → 확인 대화상자 → `confirmPurchase()` 로만 산다.
struct MeShopView: View {
    let store: MeStore
    @State private var confirming = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                AingCard {
                    HStack(alignment: .center) {
                        Text("내 루비")
                            .font(.headline)
                            .foregroundStyle(MobileTheme.primaryText)
                        Spacer(minLength: 8)
                        RubyLabel(store.rubyBalance, style: .title3)
                    }
                    Text("루비는 미니게임 순위 상품과 근무 미션으로 모여요. 산 캐릭터는 계속 가져요.")
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.shopState.hasFailed, !store.shopState.hasLoaded {
                    AingCard {
                        LoadFailureRow(MeText.shopFailed, isRetrying: store.shopState.isLoading) {
                            Task { await store.loadShop() }
                        }
                    }
                }
                SectionHeader(MeText.charactersTitle)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.shopRows) { row in
                        shopCard(row)
                    }
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable { await store.loadShop() }
        .background(MobileTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { purchaseBar }
        .navigationTitle(MeText.shopTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.charactersDidAppear() }
        .onDisappear { store.shopDidDisappear() }
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(MeText.buyAction) { store.confirmPurchase() }
            Button("취소", role: .cancel) {}
        } message: {
            if let price = store.shopSelectionPrice, let balance = store.rubyBalance {
                Text(MeText.purchaseConfirmMessage(price: price, balance: balance))
            }
        }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : (dynamicTypeSize >= .xxLarge ? 2 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
    }

    private var confirmTitle: String {
        MeText.purchaseConfirmTitle(name: store.shopSelection.map(MeCharacterCards.displayName(for:)) ?? "")
    }

    private func shopCard(_ row: ShopCharacterRow) -> some View {
        let owned = store.isOwned(row.id)
        let picked = store.shopSelection == row.id
        let affordable = (store.rubyBalance).flatMap { have in row.price.map { have >= $0 } } ?? false
        let name = MeCharacterCards.displayName(for: row.id)
        let busy = store.purchasingID == row.id
        return Button {
            store.selectShopItem(row.id)
        } label: {
            VStack(spacing: 6) {
                MeCharacterArt(id: row.id)
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    // 못 사는 카드는 그림만 흐리게 — 이름·가격 글자는 대비를 지킨다.
                    .opacity(owned || affordable || row.price == nil || store.rubyBalance == nil ? 1 : 0.5)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    if !owned {
                        Image(systemName: "diamond.fill")
                            .imageScale(.small)
                            .foregroundStyle(MobileTheme.ruby)
                    }
                    Text(busy ? "…" : MeText.cardPrice(owned: owned, price: row.price))
                        .font(MobileTheme.number(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(owned ? MobileTheme.secondaryText : MobileTheme.primaryText)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(picked ? MobileTheme.accent.opacity(0.12) : MobileTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(picked ? MobileTheme.accent : (owned ? MobileTheme.accent.opacity(0.45) : MobileTheme.separator), lineWidth: picked ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if picked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(MobileTheme.accent)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(store.purchasingID != nil)
        .accessibilityLabel(Text(owned ? "\(name), \(MeText.owned)" : "\(name), 루비 \(row.price.map(String.init) ?? "가격 모름")개"))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    private var purchaseBar: some View {
        let selection = store.shopSelection
        return VStack(spacing: 0) {
            Divider().overlay(MobileTheme.separator)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    barText(selection: selection)
                    Spacer(minLength: 8)
                    buyButton(selection: selection)
                }
                VStack(alignment: .leading, spacing: 10) {
                    barText(selection: selection)
                    buyButton(selection: selection)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private func barText(selection: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selection.map(MeCharacterCards.displayName(for:)) ?? MeText.pickSomething)
                .font(.headline)
                .foregroundStyle(selection == nil ? MobileTheme.secondaryText : MobileTheme.primaryText)
            if let detail = store.shopBarDetail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(detail == MeText.bought ? MobileTheme.working : MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func buyButton(selection: String?) -> some View {
        Button {
            confirming = true
        } label: {
            HStack(spacing: 6) {
                if store.purchasingID != nil {
                    ProgressView().tint(MobileTheme.onAccent)
                } else {
                    if let price = store.shopSelectionPrice {
                        Image(systemName: "diamond.fill").imageScale(.small)
                        Text("\(price)").monospacedDigit()
                    }
                    Text(MeText.buyAction)
                }
            }
        }
        .buttonStyle(AingPrimaryButtonStyle(fillsWidth: false))
        .disabled(!store.canConfirmPurchase)
    }
}

// MARK: - 고르기

struct MeCharacterPickerView: View {
    let store: MeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                Text(MeText.pickerCaption)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let notice = store.characterNotice {
                    InlineNotice(text: notice, kind: store.isCharacterNoticeError ? .warning : .info)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.pickerIDs, id: \.self) { id in
                        pickerCard(id)
                    }
                }
                NavigationLink(value: MeDestination.shop) {
                    Label(MeText.goToShop, systemImage: "bag.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AingPrimaryButtonStyle())
                .padding(.top, 4)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(MeText.pickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.charactersDidAppear() }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : (dynamicTypeSize >= .xxLarge ? 2 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
    }

    private func pickerCard(_ id: String) -> some View {
        let isOn = store.equippedLoaded && id == store.equippedCharacterID
        let unlocked = store.isUnlocked(id)
        let saving = store.savingCharacterID == id
        let name = MeCharacterCards.displayName(for: id)
        return Button {
            store.chooseCharacter(id)
        } label: {
            VStack(spacing: 6) {
                MeCharacterArt(id: id)
                    .frame(maxWidth: .infinity)
                    .frame(height: 84)
                    .opacity(unlocked ? 1 : 0.45)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? MobileTheme.primaryText : MobileTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if saving {
                    ProgressView()
                } else if isOn {
                    Text(MeText.equipped)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MobileTheme.accent)
                } else if !unlocked {
                    Label(store.price(of: id).map { "\($0)" } ?? "잠김", systemImage: "lock.fill")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.secondaryText)
                } else {
                    Text(" ").font(.caption)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? MobileTheme.accent.opacity(0.12) : MobileTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? MobileTheme.accent : MobileTheme.separator, lineWidth: isOn ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.savingCharacterID != nil)
        .accessibilityLabel(Text(unlocked ? name : "\(name), 잠김 — 상점에서 사기"))
        .accessibilityValue(Text(isOn ? MeText.equipped : ""))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
