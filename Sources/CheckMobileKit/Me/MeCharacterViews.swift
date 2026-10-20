import CheckCore
import CheckMobileShared

// MARK: - 캐릭터 이름 · 타일 상태(플랫폼 무관 — macOS `swift test` 가 값으로 잰다)

/// 타일 · 구매 막대 · 고르기 머리에 설 캐릭터 이름. 카드 표 → **코어 내장 이름**(아잉 · 황금 아잉이 · 무지개 아잉이) → id 차례다.
///
/// 왜 카드 표(`MeCharacterCards`)의 이름을 그대로 쓰지 않나: 그건 표에 없으면 **id 글자**를 돌려준다. 폰 카드 표에 무지개
/// 아잉이가 아직 없으면 상점 타일·막대에 "aing_rainbow" 가 그려진다(실측 — 카드 그림은 다른 레인에서 온다).
/// 서버가 준 **모르는** 캐릭터는 여전히 id 로 선다(`GachaRules.name` 의 마지막 갈래 — 이름을 지어내지 않는다는 관례 그대로).
package enum MeCharacterName {
    package static func display(_ id: String) -> String {
        GachaRules.name(for: id, displayName: MeStore.gachaDisplayName)
    }
}

/// 타일 상태 줄이 말하는 것. 뷰(`MeCharacterTile`)는 `MeCharacterTile.Status` 라는 이름으로 이 타입을 쓴다.
///
/// 왜 `#if os(iOS)` 바깥인가: 타일은 폰 뷰라 macOS 스위트가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
/// "뽑기 전용 카드가 루비 값을 말하지 않는다" 는 **값으로** 잡혀야 하므로 상태 → 내용 판정을 여기 두고 뷰는 `content` 로만 가른다.
package enum MeCharacterTileStatus: Equatable, Sendable {
    case equipped
    case owned
    case price(Int, balance: Int?)
    /// 뽑기·조각 교환으로만 얻는다(황금 · 무지개 아잉이) — 가격 대신 얻는 길("뽑기 · 조각 20"). 교환값은 서버 값(모르면 nil).
    case gachaOnly(shardCost: Int?)
    case unknownPrice
    case busy
    case none

    /// 상태 줄이 실제로 그리는 것.
    package enum Content: Equatable, Sendable {
        /// 보석 + 숫자(`RubyPrice`) — **루비로 사는 줄만** 이 값이다.
        case ruby(price: Int, balance: Int?)
        /// 글자 한 줄(`emphasized` = 착용 중 — 파랑 semibold).
        case text(String, emphasized: Bool)
        /// 반짝임 + 얻는 길("뽑기 · 조각 20") — 반짝임은 희귀 마감 빛깔(금빛 · 일곱 빛)이다.
        case acquire(String)
        case spinner
    }

    /// **뽑기 전용은 `.acquire` 다 — `.ruby` 가 아니다**: 서버가 금·무지개 행에 싣는 명목 가격(1000)은 사는 값이 아니라서
    /// 화면이 말하면 거짓이 된다(`ShopCharacterRow.isPurchasable` 과 같은 규칙의 화면 쪽 짝).
    package var content: Content {
        switch self {
        case .equipped: return .text(MeText.equipped, emphasized: true)
        case .owned: return .text(MeText.owned, emphasized: false)
        case .price(let price, let balance): return .ruby(price: price, balance: balance)
        case .gachaOnly(let shardCost): return .acquire(MeText.gachaTileStatus(shardCost: shardCost))
        case .unknownPrice: return .text("—", emphasized: false)
        case .busy: return .spinner
        case .none: return .text(" ", emphasized: false)
        }
    }
}

#if os(iOS)
import SwiftUI

// MARK: - 상점

/// 상점(캐릭터만 · 시안 B 11). 카드를 누르면 **고르기만** 하고, 아래 막대의 [보석 30 사기] → 확인 대화상자 → `confirmPurchase()` 로만 산다.
/// 잔량은 오른쪽 위 알약 하나 · 가격은 맨 보석 + 숫자(모자라면 흐림 — 자물쇠·진홍 없음) · 고른 캐릭터의 두 표정 미리 보기 · 탭 막대 숨김.
/// 보유 · 착용 표시는 고르기 화면과 같은 타일 부품(`MeCharacterTile`)이 그린다.
///
/// v0.3.54(폰 1.0.8): 캐릭터 머리 **위**에 뽑기 카드(`MeGachaCard`)가 선다 — 서버가 `shop_state.gacha` 를 줄 때만. 확률표·조각 교환
/// 시트와 캡슐 뽑기 기계 덮개는 이 화면(루트)이 띄운다. [뽑기] 와 뽑기 전용 타일(황금 · 무지개 아잉이)이 기계를 연다(타일은 사지 않고
/// 얻는 길도 아래 막대에 말한다).
struct MeShopView: View {
    let store: MeStore
    @State private var confirming = false
    @State private var showsGachaOdds = false
    @State private var showsGachaExchange = false
    @State private var showsGachaMachine = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 뽑기 카드의 스크롤 앵커(데모 `-AingCheckDemoMeScroll gacha` 가 내려갈 자리).
    private static let gachaAnchor = "gacha"

    var body: some View {
        ScrollViewReader { proxy in
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
                    if store.showsGacha {
                        MeGachaCard(store: store, onPull: { showsGachaMachine = true },
                                    onOdds: { showsGachaOdds = true }, onExchange: { showsGachaExchange = true })
                            .id(Self.gachaAnchor)
                    }
                    let ids = tileIDs
                    SectionHeader(MeText.charactersTitle, trailing: .text(MeText.ownedCount(owned: ids.filter(store.isOwned).count, total: ids.count)))
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                        .padding(.top, MobileTheme.space1)
                    LazyVGrid(columns: MeCharacterTile.columns(dynamicTypeSize), spacing: 10) {
                        ForEach(ids, id: \.self) { id in
                            shopTile(id) {
                                // 뽑기 전용(황금 · 무지개 아잉이) "뽑기 · 조각 20" → 기계를 연다(뽑기가 열린 서버일 때만 — 아니면 얻을 길이 없다).
                                guard store.showsGacha, !store.isOwned(id), store.isGachaOnly(id) else { return }
                                showsGachaMachine = true
                            }
                        }
                    }
                    if let previewID {
                        MeCharacterPreviewCard(id: previewID)
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.rowSpacing)
            }
            .onAppear {
                // 데모(DEBUG) 스크린샷: `-AingCheckDemoMeScroll <캐릭터 id>` — 그 타일까지 내린다(설정·제보 화면과 같은 관용).
                if let target = MeDemoHooks.scrollTarget() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(target, anchor: .center) }
                }
            }
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
            if store.showsGacha { openDemoGachaSheetIfAsked() }
        }
        .onDisappear { store.shopDidDisappear() }
        .onChange(of: store.showsGacha) { _, shows in
            if shows { openDemoGachaSheetIfAsked() }
        }
        .sheet(isPresented: $showsGachaOdds) { MeGachaOddsSheet(store: store) }
        .sheet(isPresented: $showsGachaExchange) { MeGachaExchangeSheet(store: store) }
        .gachaMachineCover(store: store, isPresented: $showsGachaMachine)
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
        MeText.purchaseConfirmTitle(name: store.shopSelection.map(MeCharacterName.display) ?? "")
    }

    /// 데모(DEBUG) 스크린샷: `-AingCheckDemoMeGacha odds|exchange|pull|machine` — 서버 뽑기 정보가 선 뒤 그 시트를 열거나 · 한 번
    /// 뽑거나 · 기계 덮개를 연다. **한 번만**(덮개가 닫혀 상점이 다시 뜰 때마다 또 열리지 않게).
    private func openDemoGachaSheetIfAsked() {
        switch MeDemoHooks.takeGachaAction() {
        case "odds": showsGachaOdds = true
        case "exchange": showsGachaExchange = true
        case "pull": store.pullGacha()
        case "machine": showsGachaMachine = true
        default: break
        }
    }

    private func shopTile(_ id: String, onGachaOnly: @escaping () -> Void) -> some View {
        let owned = store.isOwned(id)
        let picked = store.shopSelection == id
        let equipped = store.equippedLoaded && store.equippedCharacterID == id
        let name = MeCharacterName.display(id)
        let status: MeCharacterTile.Status
        if store.purchasingID == id {
            status = .busy
        } else if equipped {
            status = .equipped
        } else if owned {
            status = .owned
        } else if store.isGachaOnly(id) {
            // 뽑기 전용(황금 · 무지개 아잉이) — 서버가 싣는 명목 가격(1000)을 보이지 않는다. 사는 줄이 아니다.
            status = .gachaOnly(shardCost: store.gachaShardCost(of: id))
        } else if let price = store.price(of: id) {
            status = .price(price, balance: store.rubyBalance)
        } else {
            status = .unknownPrice
        }
        return Button {
            store.selectShopItem(id)
            onGachaOnly()
        } label: {
            // 상점의 표시는 '고름'(틴트 바탕)이고, 체크 + 테두리는 착용 중에만 — 두 뜻이 같은 모양이면 안 된다.
            MeCharacterTile(id: id, name: name, status: status, mark: equipped ? .equipped : (picked ? .picked : .none))
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
                // 긴 안내(예: 황금 아잉이를 얻는 길)로 두 줄 모양이 되면 왼쪽에 붙인다 — 폭을 안 채우면 가운데로 떠 보인다(시뮬레이터 실측).
                VStack(alignment: .leading, spacing: 10) {
                    barLead(selection: selection)
                    buyButton(selection: selection)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(selection.map(MeCharacterName.display) ?? MeText.pickSomething)
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
        let name = MeCharacterName.display(id)
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
    @State private var showsGachaMachine = false
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
        .gachaMachineCover(store: store, isPresented: $showsGachaMachine)
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
            Text(MeCharacterName.display(id))
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
        let name = MeCharacterName.display(id)
        let status: MeCharacterTile.Status
        if store.savingCharacterID == id {
            status = .busy
        } else if isOn {
            status = .equipped
        } else if store.isOwned(id) {
            status = .owned
        } else if store.isGachaOnly(id) {
            status = .gachaOnly(shardCost: store.gachaShardCost(of: id))
        } else if let price = store.price(of: id) {
            status = .price(price, balance: store.rubyBalance)
        } else {
            status = unlocked ? .none : .unknownPrice
        }
        let lockedLabel = store.isGachaOnly(id)
            ? "\(name), 잠김 — \(MeText.gachaAcquirePhrase(shardCost: store.gachaShardCost(of: id)))"
            : "\(name), 잠김 — 상점에서 사기"
        return Button {
            // 안 가진 뽑기 전용(황금 · 무지개 아잉이) "뽑기 · 조각 20" → 기계를 연다(뽑기가 열린 서버일 때만 — 아니면 얻는 길을 말한다).
            if store.showsGacha, !store.isOwned(id), store.isGachaOnly(id) {
                showsGachaMachine = true
            } else {
                store.chooseCharacter(id)
            }
        } label: {
            MeCharacterTile(id: id, name: name, status: status, mark: isOn ? .equipped : .none)
        }
        .buttonStyle(.plain)
        .disabled(store.savingCharacterID != nil)
        .accessibilityLabel(Text(unlocked ? MeCharacterTile.accessibilityText(name: name, status: status) : lockedLabel))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 타일(상점 · 고르기 공용)

/// 캐릭터 타일: 받침(surface2) 위 그림 · 이름 · 상태 한 줄(착용 중 파랑 · 보유 회색 · 가격 `RubyPrice`).
///
/// **표시 둘은 뜻이 다르니 모양도 다르다**(w15 검증 medium 7 — 상점의 '사려고 고른 것'과 고르기의 '착용 중'이 똑같이 파랑 테두리 +
/// 파랑 체크라 비평 26 의 뜻 겹침이 자리만 옮겨 남아 있었다):
/// - `.equipped` 지금 입은 것 — 파랑 2pt 테두리 + 파랑 체크 배지(두 화면 같다).
/// - `.picked` 상점에서 사려고 고른 것 — 파랑 틴트 바탕 + 파랑 이름(테두리·체크 없음). 아래 구매 막대가 이름·가격을 다시 말한다.
///
/// 그림은 **두 화면에서 똑같이** 원색으로 그린다. 고르기에서만 안 가진 캐릭터를 흐리게 그리던 것을 걷었다 — 같은 데이터가 화면마다
/// 다르게 보였고(비평 5), 안 가진 것은 상태 줄의 `RubyPrice`(가격)가 두 화면에서 똑같이 말한다.
struct MeCharacterTile: View {
    /// 상태는 플랫폼 무관한 자리에 있다(`MeCharacterTileStatus` — 맥 스위트가 값으로 잰다).
    typealias Status = MeCharacterTileStatus

    /// 타일에 얹는 표시. 뜻이 다르면 모양도 다르다.
    enum Mark: Equatable {
        case none
        /// 상점에서 사려고 고른 것(파랑 틴트 바탕 · 파랑 이름).
        case picked
        /// 지금 입고 있는 것(파랑 테두리 + 체크).
        case equipped
    }

    let id: String
    let name: String
    let status: Status
    let mark: Mark

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
        case .gachaOnly(let shardCost): return MeText.gachaTileAccessibility(name: name, shardCost: shardCost)
        case .unknownPrice: return "\(name), 가격 모름"
        case .busy: return "\(name), \(MeText.loading)"
        case .none: return name
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return VStack(spacing: 6) {
            MeCharacterArt(id: id, size: 76)
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(MobileTheme.surface2))
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mark == .picked ? MobileTheme.accent : MobileTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            statusLine
                .frame(minHeight: 20)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                shape.fill(MobileTheme.surface)
                if mark == .picked { shape.fill(MobileTheme.accentTint) }
            }
        }
        .overlay {
            if mark == .equipped {
                shape.strokeBorder(MobileTheme.accent, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if mark == .equipped {
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
        .contentShape(shape)
    }

    /// 상태 줄. **무엇을 말하는지는 `status.content`**(플랫폼 무관)가 정하고, 여기서는 칠하기만 한다 —
    /// 뽑기 전용(황금 · 무지개)은 반짝임이 그 캐릭터의 희귀 빛깔이다(금빛 · 일곱 빛 · 서버가 표식만 준 평범한 id 면 금빛).
    @ViewBuilder
    private var statusLine: some View {
        switch status.content {
        case .ruby(let price, let balance):
            RubyPrice(price, balance: balance, gemSize: 17, style: .subheadline)
        case .text(let text, let emphasized):
            Text(text)
                .font(emphasized ? .footnote.weight(.semibold) : .footnote)
                .foregroundStyle(emphasized ? MobileTheme.accent : MobileTheme.label2)
        case .acquire(let text):
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(MobileTheme.ink(CharacterManifest.Finish(characterID: id), otherwise: MobileTheme.goldText))
                    .accessibilityHidden(true)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        case .spinner:
            ProgressView().controlSize(.small)
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
