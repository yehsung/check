import CheckCore
import CheckMobileShared
import Foundation

/// 캐릭터: 상점(`shop_state` · `buy_character`) · 고르기(`set_character`) · 착용값 읽기(`profiles.character`).
///
/// 맥 상점(`WorkTimerStoreAuth` 상점 절)과 같은 규칙이되 **캐릭터 가지만** 있다 — 울트라 구매·지갑 동기화는 폰에 없다.
/// - 카드를 누르면 **고르기만** 한다. 사는 문은 `confirmPurchase()` 하나(맥 2026-09-14 "실수로 전부 사 버렸다" 신고의 교훈).
/// - 잔량·보유는 **서버가 준 값**으로만 바꾼다(클라가 스스로 빼지 않는다). 잔량은 오목 호스트의 루비 미러에도 쓴다(게임 탭과 공유).
/// - 착용값의 진실은 서버다(맥 0.3.30 부터 서버 기준) — 폰은 로컬 선택을 따로 들지 않는다.
extension MeStore {
    // MARK: 읽기

    package func loadShop() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("shop")
        let generation = context.generation
        shopState.isLoading = true
        shopState.hasFailed = false
        defer { if isCurrent("shop", serial) { shopState.isLoading = false } }
        let service = context.service
        do {
            let state = try await context.withMobileSessionRetry { session in
                try await service.fetchShopState(accessToken: session.accessToken)
            }
            guard generation == context.generation, isCurrent("shop", serial) else { return }
            applyShopState(state)
            shopState.hasLoaded = true
            shopState.loadedAt = context.clock.now()
        } catch {
            guard generation == context.generation, isCurrent("shop", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            shopState.hasFailed = true
        }
    }

    /// 서버가 말한 상점 상태를 옮긴다. **nil 은 건너뛴다** — 모르는 것을 0 으로 적지 않는다(맥 applyShopState).
    /// 울트라 잔량·가격 칸은 읽지 않는다(폰에 울트라 가지가 없다).
    func applyShopState(_ state: ShopStateResponse) {
        if let ruby = state.rubyBalance { context.gomokuHost.rubyBalance = ruby }
        guard let rows = state.characters else { return }
        shopCharacters = rows
        var owned: Set<String> = [MeCharacterCards.aingID]
        for row in rows where row.owned == true { owned.insert(row.id) }
        ownedCharacterIDs = owned
    }

    package func loadEquippedCharacter() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("equipped")
        let generation = context.generation
        let service = context.service
        do {
            let serverID = try await context.withMobileSessionRetry { session in
                try await service.fetchEquippedCharacter(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, isCurrent("equipped", serial), savingCharacterID == nil else { return }
            equippedServerID = CharacterSyncDecision.normalized(serverID)
            equippedLoaded = true
        } catch {
            // 행 없음·옛 서버·네트워크: 모르는 채로 둔다(아잉으로 단정하지 않는다 — 맥 performEquippedCharacterSync 와 같은 관용).
        }
    }

    // MARK: 표시값

    /// 지금 서 있는 캐릭터(모르면 아잉).
    package var equippedCharacterID: String {
        MeCharacterCards.equippedID(fromServer: equippedServerID)
    }

    /// 상점 목록(서버 순서). 서버를 아직 못 읽었으면 이 빌드가 아는 캐릭터를 가격 모름으로(맥 상점과 같은 자리표시).
    package var shopRows: [ShopCharacterRow] {
        if !shopCharacters.isEmpty { return shopCharacters }
        return MeCharacterCards.knownIDs.filter { $0 != MeCharacterCards.aingID }.map { ShopCharacterRow(id: $0) }
    }

    /// 고르기 목록: 아잉 + 이 빌드가 아는 캐릭터 + 서버가 준 모르는 캐릭터(이름은 id).
    package var pickerIDs: [String] {
        var ids = MeCharacterCards.knownIDs
        for row in shopCharacters where !ids.contains(row.id) { ids.append(row.id) }
        return ids
    }

    package func isOwned(_ id: String) -> Bool {
        id == MeCharacterCards.aingID || ownedCharacterIDs.contains(id)
    }

    /// 고를 수 있는가. 상점을 아직 못 읽었으면 막지 않는다(서버가 `not_owned` 로 거절한다 — 맥 isCharacterUnlocked).
    package func isUnlocked(_ id: String) -> Bool {
        !shopState.hasLoaded || isOwned(id)
    }

    package func price(of id: String) -> Int? {
        shopCharacters.first { $0.id == id }?.price
    }

    // MARK: 상점

    /// 카드를 눌렀을 때. **고르기만 한다.** 이미 가진 것은 고르지 않고 그 사실을 말한다. 같은 것을 다시 누르면 선택을 푼다.
    package func selectShopItem(_ id: String) {
        guard purchasingID == nil else { return }
        if isOwned(id) {
            shopSelection = nil
            shopNotice = MeText.alreadyOwned
            return
        }
        shopSelection = (shopSelection == id) ? nil : id
        shopNotice = nil
    }

    package var shopSelectionPrice: Int? {
        shopSelection.flatMap { price(of: $0) }
    }

    /// 지금 고른 것을 살 수 있는가. 잔량이나 값을 **모르면 false**(모르면서 사지 않는다).
    package var canConfirmPurchase: Bool {
        guard purchasingID == nil, shopSelection != nil else { return false }
        guard let have = rubyBalance, let price = shopSelectionPrice else { return false }
        return have >= price
    }

    /// 하단 바 두 번째 줄(맥 `ShopText.barDetail`): 안내가 있으면 안내, 모자라면 모자란 만큼.
    package var shopBarDetail: String? {
        if let shopNotice { return shopNotice }
        guard shopSelection != nil, let price = shopSelectionPrice, let have = rubyBalance, have < price else { return nil }
        return CheckCoreShared.shortfallNotice(need: price, have: have)
    }

    /// ★ **실제 구매는 여기 하나뿐이다**(확인 대화상자의 [구매하기]만 부른다).
    package func confirmPurchase() {
        guard let id = shopSelection, purchasingID == nil, context.session.isSignedIn else { return }
        guard let have = rubyBalance, let price = shopSelectionPrice else {
            launch { [weak self] in await self?.loadShop() }
            return
        }
        guard have >= price else {
            shopNotice = CheckCoreShared.shortfallNotice(need: price, have: have)
            return
        }
        purchasingID = id
        shopNotice = nil
        let generation = context.generation
        let service = context.service
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.purchasingID = nil } }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.buyCharacter(accessToken: session.accessToken, id: id)
                }
                guard generation == self.context.generation else { return }
                if let ruby = response.rubyBalance { self.context.gomokuHost.rubyBalance = ruby }
                switch response.status {
                case "ok", "already_owned":
                    self.ownedCharacterIDs.insert(id)
                    self.shopSelection = nil
                    self.shopNotice = response.status == "ok" ? MeText.bought : MeText.alreadyOwned
                    await self.loadShop()
                case "insufficient":
                    self.shopNotice = CheckCoreShared.shortfallNotice(need: response.need, have: response.have)
                default:
                    self.shopNotice = MeText.buyFailed
                }
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.shopNotice = MeText.buyFailed
            }
        }
    }

    // MARK: 고르기

    /// 캐릭터를 입는다(`set_character` — 아잉은 nil 로 기본값 되돌리기). 안 가진 캐릭터는 서버에 묻기 전에 막고 상점을 가리킨다.
    package func chooseCharacter(_ id: String) {
        guard savingCharacterID == nil, context.session.isSignedIn else { return }
        guard isUnlocked(id) else {
            characterNotice = MeText.lockedCharacter(MeCharacterCards.displayName(for: id))
            isCharacterNoticeError = false
            return
        }
        guard id != equippedCharacterID || !equippedLoaded else { return }
        savingCharacterID = id
        characterNotice = nil
        isCharacterNoticeError = false
        let generation = context.generation
        let service = context.service
        let target: String? = id == MeCharacterCards.aingID ? nil : id
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.savingCharacterID = nil } }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.setCharacter(accessToken: session.accessToken, id: target)
                }
                guard generation == self.context.generation else { return }
                switch response.status {
                case "ok":
                    self.equippedServerID = CharacterSyncDecision.normalized(response.character) ?? target
                    self.equippedLoaded = true
                    self.characterNotice = MeText.characterSaved
                case "not_owned":
                    // 다른 기기에서 환불·운영자 정리 등으로 소유가 사라졌다 — 상점 상태를 다시 읽어 화면을 사실에 맞춘다.
                    self.ownedCharacterIDs.remove(id)
                    self.characterNotice = MeText.characterNotOwned
                    self.isCharacterNoticeError = true
                    await self.loadShop()
                default:
                    self.characterNotice = MeText.characterSaveFailed
                    self.isCharacterNoticeError = true
                }
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.characterNotice = MeText.characterSaveFailed
                self.isCharacterNoticeError = true
            }
        }
    }

    /// 상점·고르기 화면이 열릴 때: 로컬 캐시를 믿지 않고 다시 읽는다(가격·보유는 다른 기기에서 바뀐다).
    package func charactersDidAppear() {
        guard context.session.isSignedIn else { return }
        if !shopState.isLoading { launch { [weak self] in await self?.loadShop() } }
        launch { [weak self] in await self?.loadEquippedCharacter() }
    }

    package func shopDidDisappear() {
        shopNotice = nil
        if purchasingID == nil { shopSelection = nil }
    }
}
