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
    // MARK: 능력 번호

    /// 상점 RPC 에 싣는 능력 번호(v0.3.43 로봇 1 · v0.3.54 금 2 · v0.3.59 무지개 3 · v0.3.66 케이크 **4**). 파생 자리는 여기 하나다 —
    /// 목록과 구매가 **같은 번호**로 가야 한다(목록만 가리고 구매를 열어 두면 게이트가 장식이다 — B12). 재료와
    /// "숫자를 박지 않는" 근거는 `MeStore.drawableCharacterIDs` 주석에 있다. 번호가 3 이상이어야 서버가 무지개 행을, 4 여야 케이크 행과
    /// 생일 선물을 보낸다(`MeRainbowProtocolTests` · `MeCakeGiftTests` 가 번들 ⟺ 번호를 양방향으로 잰다).
    package var shopProtocolVersion: Int {
        ShopWire.protocolVersion(drawableCharacterIDs: drawableCharacterIDs)
    }

    // MARK: 읽기

    package func loadShop() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("shop")
        let generation = context.generation
        // 루비 미러에 쓴 횟수를 **떠날 때** 찍는다 — 도착했을 때 그 사이 누가 썼으면(받기 · 뽑기 · 구매 · 오목 정산 · 지갑)
        // 이 조회는 그 쓰기보다 **옛 서버**를 말한다(`applyShopRubyBalance`). 순번 가드(`isCurrent`)는 상점 조회끼리만 세므로
        // 다른 갈래의 쓰기는 못 본다.
        let rubyWriteAtDeparture = context.gomokuHost.rubyWriteSerial
        shopState.isLoading = true
        shopState.hasFailed = false
        defer { if isCurrent("shop", serial) { shopState.isLoading = false } }
        let service = context.service
        let protocolVersion = shopProtocolVersion
        do {
            let state = try await context.withMobileSessionRetry { session in
                try await service.fetchShopState(accessToken: session.accessToken,
                                                 protocolVersion: protocolVersion)
            }
            guard generation == context.generation, isCurrent("shop", serial) else { return }
            applyShopRubyBalance(state.rubyBalance, writeSerialAtDeparture: rubyWriteAtDeparture)
            applyShopState(state)
            shopState.hasLoaded = true
            shopState.loadedAt = context.clock.now()
        } catch {
            guard generation == context.generation, isCurrent("shop", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            shopState.hasFailed = true
        }
    }

    /// 상점 조회가 실어 온 잔량을 루비 미러에 옮긴다 — **떠난 뒤 미러에 쓴 적이 없을 때만**(폰 1.0.9).
    ///
    /// ★ 미러(`context.gomokuHost.rubyBalance`)는 상점 · 뽑기 · 받기 · 오목 · 체스가 다 쓰는 한 칸이다. 나 탭이 뜨면 상점과
    ///   주간 · 도전 미션 조회가 **함께** 떠나므로, 받기를 누른 뒤에 **받기 전에 떠난** `shop_state` 가 도착하는 창이 흔하다.
    ///   도장 없이 덮던 시절엔 그때 잔량이 받기 전으로 되돌아갔다(1055 → 1000 — 받은 루비가 눈앞에서 사라진다).
    ///   그래서 주간 보상과 **같은 규약**으로 묻는다: 떠난 뒤 미러에 쓴 횟수가 0 일 때만 쓴다(`WeeklyWorkRules.shouldApplyRuby` —
    ///   값이 아니라 횟수로 묻는 이유는 그 주석의 ABA 를 보라). 못 쓴 잔량은 다음 조회가 맞추고, 받기 갈래는 그 자리에서
    ///   상점을 다시 읽어 맞춘다(`applyWeeklyWorkStatus` · `applyAchievementStatus` 의 else 가지 — 이 함수가 그 재조회의 끝이다).
    ///
    /// 구매·뽑기·교환 **응답**의 잔량은 이 문을 지나지 않는다(`applyPurchaseResponse` · `applyGachaPullResponse`) — 그건 누른
    /// 사람 자신의 결과이고 가장 새 값이라 언제나 쓴다.
    func applyShopRubyBalance(_ server: Int?, writeSerialAtDeparture: Int) {
        guard WeeklyWorkRules.shouldApplyRuby(server: server, writeSerialAtDeparture: writeSerialAtDeparture,
                                              currentWriteSerial: context.gomokuHost.rubyWriteSerial),
              let ruby = server else { return }
        context.gomokuHost.rubyBalance = ruby
    }

    /// 서버가 말한 상점 상태를 옮긴다. **nil 은 건너뛴다** — 모르는 것을 0 으로 적지 않는다(맥 applyShopState).
    /// 울트라 잔량·가격 칸은 읽지 않는다(폰에 울트라 가지가 없다).
    ///
    /// **잔량은 여기서 쓰지 않는다** — 늦게 도착한 조회가 받은 루비를 되돌리지 않게 부르는 자리가 도장과 함께
    /// `applyShopRubyBalance` 로 옮긴다(위 ★). 새로 이 함수를 부르는 자리를 만들거든 잔량도 그 짝으로 같이 옮겨라.
    ///
    /// 뽑기(v0.3.54)는 예외로 **없음도 사실이다**: 서버는 `p_protocol >= 2` 일 때만 `gacha` 를 싣고, 없으면 뽑기를 닫았다는 뜻이다
    /// (옛 서버 · db push 전 · 404 로 옛 모양에 되물은 응답). 그래서 받은 그대로 옮긴다 — 지난 값을 남기면 서버가 닫은 뽑기가 열려 있다.
    func applyShopState(_ state: ShopStateResponse) {
        gachaInfo = state.gacha
        guard let rows = state.characters else { return }
        shopCharacters = rows
        var owned: Set<String> = [MeCharacterCards.aingID]
        for row in rows where row.owned == true { owned.insert(row.id) }
        ownedCharacterIDs = owned
        // 생일 선물(v0.3.66): 새 보유와 선택지를 맞춘다 — 다른 기기에서 받은 케이크가 폰 선물 · '다시 열기' 줄에 남지 않게.
        reconcileCakeGiftWithOwnership()
    }

    /// 착용값 읽기. `set_character` 가 **끝날 때** 이 순번을 올리므로, 저장 전·저장 중에 나간 GET 은 저장이 끝난 뒤 도착해도 버려진다
    /// (방금 입은 캐릭터를 옛 값으로 되돌리지 않는다 — rankme-verify 낮음 1). 저장 중에 도착한 GET 은 저장 중 깃발이 막는다.
    package func loadEquippedCharacter() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("equipped")
        let generation = context.generation
        let service = context.service
        equippedLoadFailed = false
        do {
            let serverID = try await context.withMobileSessionRetry { session in
                try await service.fetchEquippedCharacter(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, isCurrent("equipped", serial), savingCharacterID == nil else { return }
            equippedServerID = CharacterSyncDecision.normalized(serverID)
            equippedLoaded = true
            // 캐릭터 한 표의 내 칸도 같은 값으로 — 사람 아바타 자리의 나와 '나' 자리(지금·순위·탭 막대)가 다른 캐릭터로 서지 않게.
            context.characters.noteMyEquipped(equippedServerID)
        } catch {
            // 행 없음·옛 서버·네트워크: 값은 모르는 채로 둔다(아잉으로 단정하지 않는다 — 맥 performEquippedCharacterSync 와 같은 관용).
            // 다만 실패였다는 사실은 남긴다 — 요약이 '불러오는 중…'에 끝없이 머물지 않게.
            guard generation == context.generation, isCurrent("equipped", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            equippedLoadFailed = true
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
    ///
    /// 뽑기 전용(황금 · 무지개 아잉이)은 **서버 상점이 그 캐릭터를 말했거나 내가 가졌을 때만** 선다 — 뽑기가 아직 없는 서버(db push 전 ·
    /// 옛 서버)에서 얻을 길이 없는 "뽑기 전용" 타일이 서지 않게. 상점을 아직 못 읽었으면 막지 않는다(다른 캐릭터와 같은 관용).
    ///
    /// 생일 선물 전용(케이크 아잉이 둘 — v0.3.66)은 **가진 사람에게만** 선다(조정자 결정 · 맥 `WorkTimerStore.isCharacterListed` 와 같은 규칙).
    /// 안 가진 사람의 '생일 선물 전용' 잠긴 칸은 상점 격자에만 선다. 상점을 아직 못 읽어도 관용이 없다 — 지금 입고 있으면(착용값을 안다)
    /// 가진 것이므로 그때는 선다(상점보다 착용 조회가 먼저 도착한 창에서 입은 캐릭터가 목록에 없지 않게).
    package var pickerIDs: [String] {
        var ids = MeCharacterCards.knownIDs.filter { id in
            if isGiftOnly(id) { return isOwned(id) || isWearing(id) }
            return !shopState.hasLoaded || !isGachaOnly(id) || isOwned(id) || shopCharacters.contains { $0.id == id }
        }
        for row in shopCharacters where !ids.contains(row.id) {
            if row.isGiftOnly, !(isOwned(row.id) || isWearing(row.id)) { continue }
            ids.append(row.id)
        }
        return ids
    }

    /// 지금 입고 있는가(착용값을 알 때만).
    package func isWearing(_ id: String) -> Bool {
        equippedLoaded && equippedCharacterID == id
    }

    /// 생일 선물로만 얻는 캐릭터인가(케이크 아잉이 둘 — **내장 id 는 표식과 무관하게 언제나**, 그 밖은 서버 `gift_only` 표식).
    /// 판정은 코어 한 곳(`CharacterCatalog.isGiftOnlyBuiltIn` · `ShopCharacterRow.isGiftOnly`)에서 가져온다.
    package func isGiftOnly(_ id: String) -> Bool {
        CharacterCatalog.isGiftOnlyBuiltIn(id) || shopCharacters.first { $0.id == id }?.isGiftOnly == true
    }

    package func isOwned(_ id: String) -> Bool {
        id == MeCharacterCards.aingID || ownedCharacterIDs.contains(id)
    }

    /// 고를 수 있는가. 상점을 아직 못 읽었으면 막지 않는다(서버가 `not_owned` 로 거절한다 — 맥 isCharacterUnlocked).
    package func isUnlocked(_ id: String) -> Bool {
        !shopState.hasLoaded || isOwned(id)
    }

    /// 상점가. **살 수 있는 줄만** 값이 있다 — 뽑기 전용(황금 · 무지개 아잉이)의 `price` 는 서버가 싣는 명목값(1000)이라 화면·구매에 쓰면
    /// [1000 사기] 가 켜지고 서버가 `not_for_sale` 로 거절한다(`ShopCharacterRow.isPurchasable`).
    package func price(of id: String) -> Int? {
        guard let row = shopCharacters.first(where: { $0.id == id }), row.isPurchasable else { return nil }
        return row.price
    }

    /// 뽑기·조각 교환으로만 얻는 캐릭터인가(서버 표식 · **내장 뽑기 전용**은 표식과 무관하게 언제나).
    ///
    /// 내장 뽑기 전용은 둘이다 — 황금 아잉이(v0.3.54)와 무지개 아잉이(v0.3.59). 판정은 코어 한 곳
    /// (`CharacterCatalog.isGachaOnlyBuiltIn`)에서 가져온다: 확률표 · 교환표 · 희귀 연출을 만드는 코어 `GachaRules` 도
    /// 같은 함수로 간다(`Gacha.swift` — `gachaOnly == true || isGachaOnlyBuiltIn(id)`). 금만 세던 시절의 모양으로 되돌리면
    /// 무지개 타일이 **사는 줄**로 서서 명목가 1000 짜리 [사기] 가 켜지고, 서버가 `not_for_sale` 로 거절한다.
    ///
    /// 서버 표식(`gacha_only`)을 같이 보는 이유는 그대로다: 앞으로 서버가 다른 캐릭터를 뽑기 전용으로 돌려도 앱 업데이트 없이 따라간다.
    package func isGachaOnly(_ id: String) -> Bool {
        // 케이크(v0.3.66 생일 선물 전용)는 서버가 `gacha_only = true` 를 함께 실어도 뽑기 전용이 아니다(`ShopCharacterRow.isGachaOnly`).
        guard !CharacterCatalog.isGiftOnlyBuiltIn(id) else { return false }
        return CharacterCatalog.isGachaOnlyBuiltIn(id) || shopCharacters.first { $0.id == id }?.isGachaOnly == true
    }

    // MARK: 상점

    /// 카드를 눌렀을 때. **고르기만 한다.** 이미 가진 것은 고르지 않고 그 사실을 말한다. 같은 것을 다시 누르면 선택을 푼다.
    package func selectShopItem(_ id: String) {
        guard purchasingID == nil else { return }
        shopGachaHintID = nil
        shopGiftHintID = nil
        if isOwned(id) {
            shopSelection = nil
            shopNotice = MeText.alreadyOwned
            return
        }
        // 생일 선물 전용(케이크 아잉이)은 사는 줄도 뽑는 줄도 아니다 — 고르지 않고 얻는 길을 말한다(잠긴 칸 안내).
        // 아래 막대는 이 칸의 이름과 안내만 세우고 사기 단추를 세우지 않는다(`shopGiftHintID` — 흐린 '사기'가 남지 않게).
        // 다시 눌러도 풀지 않는다(살 것을 고른 것이 아니라 안내를 연 것이다 — 화면 onAppear 가 두 번 불러도 같다).
        if isGiftOnly(id) {
            shopSelection = nil
            shopNotice = CakeGiftText.lockedHint
            shopGiftHintID = id
            return
        }
        // 뽑기 전용은 사는 줄이 아니다 — 고르지 않고 얻는 길(뽑기 · 조각 교환)을 말한다. 화면은 이 안내와 함께 뽑기 카드로 올라간다.
        if isGachaOnly(id) {
            shopSelection = nil
            shopNotice = nil
            shopGachaHintID = id
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
        if let id = shopGachaHintID {
            return MeText.gachaOnlyNotice(MeCharacterCards.displayName(for: id), shardCost: gachaShardCost(of: id))
        }
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
        let protocolVersion = shopProtocolVersion
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.purchasingID = nil } }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.buyCharacter(accessToken: session.accessToken, id: id,
                                                   protocolVersion: protocolVersion)
                }
                await self.applyPurchaseResponse(response, id: id, generation: generation)
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.shopNotice = MeText.buyFailed
            }
        }
    }

    /// 구매 응답을 화면에 옮긴다. **보낼 때의 세대가 아니면 아무것도 안 한다** — 응답이 도착한 뒤 메인 액터 차례를 기다리는 사이
    /// 로그아웃(reset)이 먼저 돌면, 취소가 이미 끝난 요청에는 닿지 않아 앞 계정의 루비·보유·안내가 다음 계정 화면에 선다.
    /// (그 창은 실제 요청으로는 결정적으로 못 만든다 — 이 함수로 떼어 직접 시험한다.)
    ///
    /// 잔량은 **도장 없이 언제나 쓴다**(조회와 다르다 — `applyShopRubyBalance`): 이건 누른 사람 자신이 방금 만든 결과라
    /// 서버가 아는 가장 새 값이다. 여기에 "떠난 뒤 쓰기가 없었나"를 끼우면 구매와 겹친 다른 응답 하나가 산 값을 지운다.
    func applyPurchaseResponse(_ response: BuyCharacterResponse, id: String, generation: Int) async {
        guard generation == context.generation else { return }
        if let ruby = response.rubyBalance { context.gomokuHost.rubyBalance = ruby }
        switch response.status {
        case "ok", "already_owned":
            ownedCharacterIDs.insert(id)
            shopSelection = nil
            shopNotice = response.status == "ok" ? MeText.bought : MeText.alreadyOwned
            await loadShop()
        case "insufficient":
            shopNotice = CheckCoreShared.shortfallNotice(need: response.need, have: response.have)
        default:
            shopNotice = MeText.buyFailed
        }
    }

    // MARK: 고르기

    /// 캐릭터를 입는다(`set_character` — 아잉은 nil 로 기본값 되돌리기). 안 가진 캐릭터는 서버에 묻기 전에 막고 상점을 가리킨다.
    package func chooseCharacter(_ id: String) {
        guard savingCharacterID == nil, context.session.isSignedIn else { return }
        guard isUnlocked(id) else {
            // 뽑기 전용(황금 · 무지개 아잉이)에게 "상점에서 살 수 있어요"는 거짓이다 — 얻는 길을 그대로 말한다.
            // 생일 선물 전용(케이크)에게는 둘 다 거짓이다 — 잠긴 칸 안내 그대로.
            let name = MeCharacterCards.displayName(for: id)
            if isGiftOnly(id) {
                characterNotice = CakeGiftText.lockedHint
            } else {
                characterNotice = isGachaOnly(id)
                    ? MeText.lockedGachaCharacter(name, shardCost: gachaShardCost(of: id))
                    : MeText.lockedCharacter(name)
            }
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
            var needsReread = false
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.setCharacter(accessToken: session.accessToken, id: target)
                }
                guard generation == self.context.generation else { return }
                // 저장 전·저장 중에 나간 착용 GET 은 서버가 저장 전에 읽었을 수 있다 — 끝나는 순간 순번을 올려, 늦게 도착해도 버린다
                // (저장 중에 도착한 것은 `savingCharacterID` 가드가 막는다 — 시작 때 따로 올릴 필요가 없다: 변이 MF4 로 확인).
                _ = self.nextSerial("equipped")
                self.savingCharacterID = nil
                switch response.status {
                case "ok":
                    self.equippedServerID = CharacterSyncDecision.normalized(response.character) ?? target
                    self.equippedLoaded = true
                    self.equippedLoadFailed = false
                    // 내 칸은 즉시(다음 표 조회를 기다리지 않는다 — 표를 갈아 끼울 때도 이 값을 다시 얹는다).
                    self.context.characters.noteMyEquipped(self.equippedServerID)
                    self.characterNotice = MeText.characterSaved
                case "not_owned":
                    // 다른 기기에서 환불·운영자 정리 등으로 소유가 사라졌다 — 상점 상태를 다시 읽어 화면을 사실에 맞춘다.
                    self.ownedCharacterIDs.remove(id)
                    self.characterNotice = self.isGiftOnly(id) ? CakeGiftText.lockedHint
                        : (self.isGachaOnly(id) ? MeText.gachaCharacterNotOwned : MeText.characterNotOwned)
                    self.isCharacterNoticeError = true
                    needsReread = !self.equippedLoaded
                    await self.loadShop()
                default:
                    self.characterNotice = MeText.characterSaveFailed
                    self.isCharacterNoticeError = true
                    needsReread = !self.equippedLoaded
                }
            } catch {
                guard generation == self.context.generation else { return }
                _ = self.nextSerial("equipped")
                self.savingCharacterID = nil
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.characterNotice = MeText.characterSaveFailed
                self.isCharacterNoticeError = true
                needsReread = !self.equippedLoaded
            }
            // 버린 GET 이 착용값을 처음 알려 줄 참이었다면(아직 모름) 저장이 실패한 지금 다시 묻는다.
            if needsReread, generation == self.context.generation { await self.loadEquippedCharacter() }
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
        shopGachaHintID = nil
        shopGiftHintID = nil
        if purchasingID == nil { shopSelection = nil }
        gachaDidDisappear()
    }
}
