#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 상점

/// 상점(캐릭터만 · 시안 B 11). 카드를 누르면 **고르기만** 하고, 아래 막대의 [보석 30 사기] → 확인 대화상자 → `confirmPurchase()` 로만 산다.
/// 잔량은 오른쪽 위 알약 하나 · 가격은 맨 보석 + 숫자(모자라면 흐림 — 자물쇠·진홍 없음) · 고른 캐릭터의 두 표정 미리 보기 · 탭 막대 숨김.
/// 보유 · 착용 표시는 고르기 화면과 같은 타일 부품(`MeCharacterTile`)이 그린다.
struct MeShopView: View {
    let store: MeStore
    @State private var confirming = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                Text(MeText.shopLede)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                if store.shopState.hasFailed, !store.shopState.hasLoaded {
                    AingCard {
                        LoadFailureRow(MeText.shopFailed, isRetrying: store.shopState.isLoading) {
                            Task { await store.loadShop() }
                        }
                    }
                }
                let ids = tileIDs
                SectionHeader(MeText.charactersTitle, trailing: .text(MeText.ownedCount(owned: ids.filter(store.isOwned).count, total: ids.count)))
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    .padding(.top, MobileTheme.space1)
                LazyVGrid(columns: MeCharacterTile.columns(dynamicTypeSize), spacing: 10) {
                    ForEach(ids, id: \.self) { id in
                        shopTile(id)
                    }
                }
                if let previewID {
                    MeCharacterPreviewCard(id: previewID)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable { await store.loadShop() }
        .background(MobileTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
        .navigationTitle(MeText.shopTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { balancePill }
        }
        .hidesTabBar(for: .shop)
        .onAppear {
            store.charactersDidAppear()
            if let id = MeDemoHooks.shopSelection(), store.shopSelection == nil { store.selectShopItem(id) }
        }
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

    /// 아잉(기본 보유) + 서버 목록 — 고르기 화면과 같은 순서 규칙(`MeCharacterTile.ordered`).
    private var tileIDs: [String] {
        var ids = [MeCharacterCards.aingID]
        for row in store.shopRows where !ids.contains(row.id) { ids.append(row.id) }
        return MeCharacterTile.ordered(ids, isOwned: store.isOwned)
    }

    /// 미리 볼 캐릭터: 고른 것 → 없으면 지금 입은 것(착용값을 알 때).
    private var previewID: String? {
        store.shopSelection ?? (store.equippedLoaded ? store.equippedCharacterID : nil)
    }

    /// 오른쪽 위 잔량 — 게임 탭 오른쪽 위와 **같은 공용 부품**(`RubyBalanceChip(.toolbar)`, 통합 때 승격).
    /// iOS 26 도구 막대가 유리를 스스로 두르는 것(이중 겹침)은 그 부품이 안다. 상점 안이라 누를 곳은 없다.
    private var balancePill: some View {
        RubyBalanceChip(store.rubyBalance, style: .toolbar)
    }

    private var confirmTitle: String {
        MeText.purchaseConfirmTitle(name: store.shopSelection.map(MeCharacterCards.displayName(for:)) ?? "")
    }

    private func shopTile(_ id: String) -> some View {
        let owned = store.isOwned(id)
        let picked = store.shopSelection == id
        let equipped = store.equippedLoaded && store.equippedCharacterID == id
        let name = MeCharacterCards.displayName(for: id)
        let status: MeCharacterTile.Status
        if store.purchasingID == id {
            status = .busy
        } else if equipped {
            status = .equipped
        } else if owned {
            status = .owned
        } else if let price = store.price(of: id) {
            status = .price(price, balance: store.rubyBalance)
        } else {
            status = .unknownPrice
        }
        return Button {
            store.selectShopItem(id)
        } label: {
            MeCharacterTile(id: id, name: name, status: status, isSelected: picked, isLocked: false)
        }
        .buttonStyle(.plain)
        .disabled(store.purchasingID != nil)
        .accessibilityLabel(Text(MeCharacterTile.accessibilityText(name: name, status: status)))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    private var purchaseBar: some View {
        let selection = store.shopSelection
        return VStack(spacing: 0) {
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(height: MobileTheme.hairline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MobileTheme.space3) {
                    barLead(selection: selection)
                    Spacer(minLength: MobileTheme.space2)
                    buyButton(selection: selection)
                }
                VStack(alignment: .leading, spacing: 10) {
                    barLead(selection: selection)
                    buyButton(selection: selection)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, 10)
        }
        .background(MobileTheme.surface.ignoresSafeArea(edges: .bottom))
    }

    private func barLead(selection: String?) -> some View {
        HStack(spacing: 10) {
            if let selection {
                CharacterPortrait(id: selection, mood: .plain, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.map(MeCharacterCards.displayName(for:)) ?? MeText.pickSomething)
                    .font(.headline)
                    .foregroundStyle(selection == nil ? MobileTheme.label2 : MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = barDetail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(detailColor(detail))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 안내·모자람(스토어) → 살 수 있으면 "사고 나면 루비 N개 남아요".
    private var barDetail: String? {
        if let detail = store.shopBarDetail { return detail }
        guard store.shopSelection != nil, let price = store.shopSelectionPrice, let balance = store.rubyBalance, balance >= price else { return nil }
        return MeText.remainingAfterPurchase(price: price, balance: balance)
    }

    private func detailColor(_ detail: String) -> Color {
        if detail == MeText.bought { return MobileTheme.working }
        if detail == MeText.buyFailed { return MobileTheme.danger }
        return MobileTheme.label2
    }

    private func buyButton(selection: String?) -> some View {
        Button {
            confirming = true
        } label: {
            HStack(spacing: 5) {
                if store.purchasingID != nil {
                    ProgressView().tint(MobileTheme.onAccentFill)
                } else {
                    if let price = store.shopSelectionPrice {
                        RubyIcon(size: 20)
                        Text("\(price) \(MeText.buyShort)").monospacedDigit()
                    } else {
                        Text(MeText.buyShort)
                    }
                }
            }
        }
        .buttonStyle(AingButtonStyle(.filled, size: .lg))
        .disabled(!store.canConfirmPurchase)
    }
}

/// 고른 캐릭터의 두 표정(근무 중 웃음 · 근무 안 함 시무룩) — 사면 무엇이 바뀌는지 보여 빈 가운데를 채운다(시안 B 11).
struct MeCharacterPreviewCard: View {
    let id: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let name = MeCharacterCards.displayName(for: id)
        AingCard {
            // 설명 글은 줄바꿈하며 남은 폭을 쓰고 두 얼굴은 오른쪽에 제 크기로(시안 B) — 접근성 글자 크기에서만 얼굴을 아래 줄로.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    caption(name: name)
                    faces
                }
            } else {
                HStack(spacing: MobileTheme.space3) {
                    caption(name: name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    faces
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(name: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(MeText.previewTitle(name))
                .font(.headline)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(MeText.previewCaption)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var faces: some View {
        HStack(alignment: .top, spacing: MobileTheme.space2) {
            face(mood: .working, label: MeText.previewWorking)
            face(mood: .off, label: MeText.previewOff)
        }
    }

    private func face(mood: CharacterMood, label: String) -> some View {
        VStack(spacing: 6) {
            CharacterPortrait(id: id, mood: mood, size: 52)
                .padding(4)
            Text(label)
                .font(.caption2)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize()
        }
    }
}

// MARK: - 고르기

/// 캐릭터 고르기: 위에 지금 입은 캐릭터를 크게(무엇이 바뀌는지) · 아래 상점과 같은 타일(착용 = 파랑 테두리 + 체크 · 보유 · 가격).
struct MeCharacterPickerView: View {
    let store: MeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                hero
                if let notice = store.characterNotice {
                    InlineNotice(text: notice, kind: store.isCharacterNoticeError ? .warning : .info)
                }
                let ids = MeCharacterTile.ordered(store.pickerIDs, isOwned: store.isOwned)
                SectionHeader(MeText.charactersTitle, trailing: .text(MeText.ownedCount(owned: ids.filter(store.isOwned).count, total: ids.count)))
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    .padding(.top, MobileTheme.space1)
                LazyVGrid(columns: MeCharacterTile.columns(dynamicTypeSize), spacing: 10) {
                    ForEach(ids, id: \.self) { id in
                        pickerTile(id)
                    }
                }
                AingButton(MeText.goToShop, systemImage: "bag", kind: .tinted, size: .md, fillsWidth: true) {
                    store.context.router.push(MeDestination.shop, on: .me)
                }
                .padding(.top, MobileTheme.space1)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(MeText.pickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.charactersDidAppear() }
    }

    /// 지금 입은 캐릭터 크게 + 이 캐릭터가 어디에 나오는지.
    private var hero: some View {
        let id = store.equippedCharacterID
        return AingCard {
            // 설명 글은 줄바꿈하며 남은 폭을 쓴다 — 접근성 글자 크기에서만 그림을 위로.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MobileTheme.space2) {
                    heroArt(id: id)
                    heroText(id: id)
                }
            } else {
                HStack(spacing: MobileTheme.space3) {
                    heroArt(id: id)
                    heroText(id: id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func heroArt(id: String) -> some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [MobileTheme.accent.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 46))
                .frame(width: 92, height: 20)
            MeCharacterArt(id: id, size: 92)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 5)
                .padding(.bottom, 8)
        }
        .frame(width: 100, height: 104)
        .accessibilityHidden(true)
    }

    private func heroText(id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MeCharacterCards.displayName(for: id))
                .font(MobileTheme.title(.title3))
                .foregroundStyle(MobileTheme.label)
            Text(store.equippedLoaded ? MeText.equipped : (store.equippedLoadFailed ? MeText.equippedLoadFailed : MeText.loading))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(store.equippedLoaded ? MobileTheme.accent : (store.equippedLoadFailed ? MobileTheme.pending : MobileTheme.label2))
                .fixedSize(horizontal: false, vertical: true)
            Text(MeText.pickerCaption)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func pickerTile(_ id: String) -> some View {
        let isOn = store.equippedLoaded && id == store.equippedCharacterID
        let unlocked = store.isUnlocked(id)
        let name = MeCharacterCards.displayName(for: id)
        let status: MeCharacterTile.Status
        if store.savingCharacterID == id {
            status = .busy
        } else if isOn {
            status = .equipped
        } else if store.isOwned(id) {
            status = .owned
        } else if let price = store.price(of: id) {
            status = .price(price, balance: store.rubyBalance)
        } else {
            status = unlocked ? .none : .unknownPrice
        }
        return Button {
            store.chooseCharacter(id)
        } label: {
            MeCharacterTile(id: id, name: name, status: status, isSelected: isOn, isLocked: !unlocked)
        }
        .buttonStyle(.plain)
        .disabled(store.savingCharacterID != nil)
        .accessibilityLabel(Text(unlocked ? MeCharacterTile.accessibilityText(name: name, status: status) : "\(name), 잠김 — 상점에서 사기"))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 타일(상점 · 고르기 공용)

/// 캐릭터 타일: 받침(surface2) 위 그림 · 이름 · 상태 한 줄(착용 중 파랑 · 보유 회색 · 가격 `RubyPrice`). 선택 = 파랑 테두리 + 체크.
/// 잠김(고르기에서 안 가진 것)은 그림만 같은 정도로 흐리게(채도를 덜고 반투명 — 흰 유령이 바탕에 녹아 사라지지 않을 만큼, w14 비평 27).
struct MeCharacterTile: View {
    enum Status: Equatable {
        case equipped
        case owned
        case price(Int, balance: Int?)
        case unknownPrice
        case busy
        case none
    }

    let id: String
    let name: String
    let status: Status
    let isSelected: Bool
    let isLocked: Bool

    /// 두 화면 같은 순서: 가진 것 먼저(아잉 → 나머지는 받은 순서), 그다음 안 가진 것(받은 순서). 안정 정렬.
    static func ordered(_ ids: [String], isOwned: (String) -> Bool) -> [String] {
        ids.filter(isOwned) + ids.filter { !isOwned($0) }
    }

    static func columns(_ typeSize: DynamicTypeSize) -> [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : (typeSize >= .xxLarge ? 2 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
    }

    static func accessibilityText(name: String, status: Status) -> String {
        switch status {
        case .equipped: return "\(name), \(MeText.equipped)"
        case .owned: return "\(name), \(MeText.owned)"
        case .price(let price, let balance): return "\(name), \(RubyPriceRule.accessibilityText(price: price, isShort: RubyPriceRule.isShort(price: price, balance: balance)))"
        case .unknownPrice: return "\(name), 가격 모름"
        case .busy: return "\(name), \(MeText.loading)"
        case .none: return name
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            MeCharacterArt(id: id, size: 76)
                .saturation(isLocked ? 0.35 : 1)
                .opacity(isLocked ? 0.7 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(MobileTheme.surface2))
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            statusLine
                .frame(minHeight: 20)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous).fill(MobileTheme.surface))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
                    .strokeBorder(MobileTheme.accent, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MobileTheme.onAccentFill)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(MobileTheme.accentFill))
                    .overlay(Circle().strokeBorder(MobileTheme.surface, lineWidth: 2))
                    .offset(x: -4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .equipped:
            Text(MeText.equipped)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MobileTheme.accent)
        case .owned:
            Text(MeText.owned)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
        case .price(let price, let balance):
            RubyPrice(price, balance: balance, gemSize: 17, style: .subheadline)
        case .unknownPrice:
            Text("—")
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
        case .busy:
            ProgressView().controlSize(.small)
        case .none:
            Text(" ").font(.footnote)
        }
    }
}

/// 캐릭터 그림: 이 빌드가 아는 캐릭터는 공용 초상 원본(`CharacterPortrait` 전신 — 무대·위젯과 같은 그림), 모르는 id 는 박힌 카드 그림 →
/// 그것도 없으면 자리표시(아잉으로 **지어내지 않는다** — 서버가 새 캐릭터를 주면 이름은 id, 그림은 물음표).
struct MeCharacterArt: View {
    let id: String
    var size: CGFloat = 76

    var body: some View {
        if AingCharacterArt.knownIDs.contains(id) {
            CharacterPortrait(id: id, mood: .plain, size: size, framed: false)
        } else if let image = MeCharacterCards.image(id: id) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(MeCharacterCards.card(id: id)?.pixelArt == true ? .none : .high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .resizable()
                .scaledToFit()
                .foregroundStyle(MobileTheme.label2)
                .padding(size * 0.15)
                .frame(width: size, height: size)
        }
    }
}
#endif
