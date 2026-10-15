import CheckCore
import CheckMobileShared
import Foundation

/// 캐릭터 뽑기(v0.3.54 맥 · 폰 1.0.8) — `gacha_pull` · `gacha_exchange`. 판정·문구·요청 id 수명은 코어(`Gacha.swift`)가 맥과 한 벌로
/// 들고 있고, 이 파일은 **부르고 옮기기만** 한다.
///
/// - 뽑기를 여는 문은 `shop_state.gacha`(`gachaInfo`)다. 서버가 안 주면 화면은 통째로 숨는다(`showsGacha`).
/// - 사용자 동작 한 번 = request_id 하나(`GachaRequestIDs`). 결과를 모르는 실패(오프라인 · 5xx · 해석 실패)는 id 를 **쥔 채** 두고,
///   다시 누르면 같은 id 로 묻는다 — 서버가 이미 처리했으면 처음 결과가 `replayed` 로 오고 두 번 깎이지 않는다.
/// - 루비·조각·보유는 **서버가 준 값**으로만 바꾼다. 루비는 오목 호스트의 미러(`context.gomokuHost.rubyBalance`)에 쓴다 —
///   게임 탭·확성기·상점 알약이 한 값을 본다.
/// - 응답 적용은 **보낸 세대**일 때만(`applyPurchaseResponse` 와 같은 로그아웃 경합 가드).
/// - 이 파일은 `#if os(iOS)` 밖이라 맥 `swift test` 가 진짜 경로를 돌린다(`MeGachaStoreTests`).
extension MeStore {
    // MARK: 표시값

    /// 뽑기 카드를 세울 만큼 아는가: 서버가 `gacha` 를 줬고 · 값과 완전한 확률표가 있다(공개 못 한 확률로 루비를 받지 않는다).
    package var showsGacha: Bool {
        gachaInfo?.isUsable == true
    }

    /// 지금 뽑을 수 있는가(버튼 잠금 + 이유). 판정의 권위는 서버다 — 이건 헛왕복을 줄이는 문이다.
    package var gachaPullAvailability: GachaPullAvailability {
        GachaRules.pullAvailability(info: gachaInfo, rubyBalance: rubyBalance)
    }

    /// [뽑기] 를 누를 수 있는가: 떠 있는 요청이 없고 판정이 ready.
    package var canPullGacha: Bool {
        !isPulling && gachaPullAvailability.canPull
    }

    /// 버튼 아래 이유 한 줄(모자람 · 닫힘). 안내(실패·거절)가 있으면 그게 먼저다.
    package var gachaDetail: String? {
        if let gachaNotice { return gachaNotice }
        return GachaText.blockedReason(gachaPullAvailability)
    }

    /// 내 조각 수(서버 값 · 모르면 nil).
    package var gachaShards: Int? {
        gachaInfo?.shards
    }

    /// 확률표(서버 순서 그대로 · 이름은 이 빌드의 카드 이름 — 맥 카탈로그와 같은 글자).
    package var gachaOddsRows: [GachaOddsRow] {
        guard let gachaInfo else { return [] }
        return GachaRules.oddsRows(info: gachaInfo, shopRows: shopCharacters, displayName: Self.gachaDisplayName)
    }

    /// 조각 교환 목록(확률표 순서 — 서버가 황금 아잉이를 맨 앞에 둔다 · 교환값은 서버 `shard_costs` 그대로).
    package var gachaExchangeRows: [GachaExchangeRow] {
        guard let gachaInfo else { return [] }
        var owned = ownedCharacterIDs
        owned.insert(MeCharacterCards.aingID)
        return GachaRules.exchangeRows(info: gachaInfo, ownedIDs: owned, displayName: Self.gachaDisplayName)
    }

    /// 이 캐릭터의 조각 교환값(서버 `shard_costs` · 없으면 nil). 문구가 값을 박지 않게 여기서 읽는다.
    package func gachaShardCost(of id: String) -> Int? {
        guard let cost = gachaInfo?.shardCosts?[id], cost > 0 else { return nil }
        return cost
    }

    /// 한 캐릭터의 교환 가능성(보유 · 값 · 조각).
    package func gachaExchangeAvailability(_ id: String) -> GachaExchangeAvailability {
        GachaRules.exchangeAvailability(characterID: id, isOwned: isOwned(id), shards: gachaInfo?.shards,
                                        shardCosts: gachaInfo?.shardCosts)
    }

    /// 사람이 읽는 이름(카드 → 코어 내장 → id). 확률표·결과·교환이 같은 이름을 쓴다.
    package func gachaName(_ id: String) -> String {
        GachaRules.name(for: id, displayName: Self.gachaDisplayName)
    }

    /// 이 빌드의 카드 이름(모르는 id 는 nil — 코어가 내장 이름 · id 로 채운다).
    nonisolated static func gachaDisplayName(_ id: String) -> String? {
        MeCharacterCards.isKnown(id) ? MeCharacterCards.displayName(for: id) : nil
    }

    // MARK: 뽑기

    /// [뽑기 · 50] 한 번. 떠 있는 요청이 있으면 아무것도 안 한다(연타 = 요청 하나).
    package func pullGacha() {
        guard !isPulling, context.session.isSignedIn else { return }
        let availability = gachaPullAvailability
        guard availability.canPull else {
            switch availability {
            case .unknownBalance:
                // 잔량을 모르면 깎지 않는다 — 상점을 다시 읽어 잔량을 안 뒤에 다시 누르게 한다(구매와 같은 관용).
                launch { [weak self] in await self?.loadShop() }
            default:
                gachaNotice = GachaText.blockedReason(availability)
                isGachaNoticeError = false
            }
            return
        }
        let requestID = gachaRequestIDs.pullID()
        isPulling = true
        gachaNotice = nil
        isGachaNoticeError = false
        let generation = context.generation
        let service = context.service
        let protocolVersion = shopProtocolVersion
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.isPulling = false } }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.gachaPull(accessToken: session.accessToken, protocolVersion: protocolVersion,
                                                requestID: requestID)
                }
                await self.applyGachaPullResponse(response, requestID: requestID, generation: generation)
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                if let known = GachaPullOutcome(error: error) {
                    // 함수가 없다(서버에서 아무것도 안 돌았다) — id 를 버려도 된다.
                    self.gachaRequestIDs.settlePull(requestID)
                    self.gachaNotice = GachaText.notice(for: known)
                } else {
                    // 결과를 모른다 — id 를 **쥔 채** 둔다(다시 누르면 같은 id 로 묻는다).
                    self.gachaNotice = GachaText.connection
                }
                self.isGachaNoticeError = true
            }
        }
    }

    /// 뽑기 응답을 화면에 옮긴다. **보낼 때의 세대가 아니면 아무것도 안 한다**(로그아웃 경합 — `applyPurchaseResponse` 주석).
    func applyGachaPullResponse(_ response: GachaPullResponse, requestID: UUID, generation: Int) async {
        guard generation == context.generation else { return }
        // 서버가 답을 줬다(어떤 status 든) — 이 id 의 일은 끝났다. 다음 누름은 새 동작이다.
        gachaRequestIDs.settlePull(requestID)
        // 잔량·조각은 실린 것만(서버 값) — 모르는 칸을 0 으로 적지 않는다.
        if let ruby = response.rubyBalance { context.gomokuHost.rubyBalance = ruby }
        if let shards = response.shards { gachaInfo?.shards = shards }
        let outcome = GachaPullOutcome(response: response)
        switch outcome {
        case .pulled(let result):
            if let id = result.newlyOwnedID { ownedCharacterIDs.insert(id) }
            lastGachaResult = result
            gachaRevealSerial &+= 1
            gachaNotice = nil
            isGachaNoticeError = false
            // 보유·조각·확률표를 서버 값으로 다시 맞춘다(다른 기기에서 바뀐 것까지).
            await loadShop()
        case .insufficient(_, let have):
            // 응답이 잔량을 따로 안 실었으면 서버가 말한 '가진 양'이 지금 잔량이다.
            if response.rubyBalance == nil, let have { context.gomokuHost.rubyBalance = have }
            gachaNotice = GachaText.notice(for: outcome)
            isGachaNoticeError = true
        case .failed:
            // ok 인데 결과 id 가 빠졌거나 모르는 status — 잔량이 바뀌었을 수 있어 상점을 다시 읽는다.
            gachaNotice = GachaText.notice(for: outcome)
            isGachaNoticeError = true
            await loadShop()
        default:
            gachaNotice = GachaText.notice(for: outcome)
            isGachaNoticeError = true
        }
    }

    // MARK: 조각 교환

    /// 조각으로 캐릭터를 교환한다(확인 대화상자의 [교환하기]만 부른다). 떠 있는 교환이 있으면 아무것도 안 한다.
    package func exchangeShards(for id: String) {
        guard exchangingID == nil, context.session.isSignedIn else { return }
        let name = gachaName(id)
        let availability = gachaExchangeAvailability(id)
        guard availability.canExchange else {
            exchangeNotice = MeText.exchangeBlocked(availability)
            isExchangeNoticeError = false
            return
        }
        let requestID = gachaRequestIDs.exchangeID(for: id)
        exchangingID = id
        exchangeNotice = nil
        isExchangeNoticeError = false
        let generation = context.generation
        let service = context.service
        let protocolVersion = shopProtocolVersion
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.exchangingID = nil } }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.gachaExchange(accessToken: session.accessToken, characterID: id,
                                                    protocolVersion: protocolVersion, requestID: requestID)
                }
                await self.applyGachaExchangeResponse(response, id: id, requestID: requestID, generation: generation)
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                if let known = GachaExchangeOutcome(error: error) {
                    self.gachaRequestIDs.settleExchange(requestID, for: id)
                    self.exchangeNotice = GachaText.notice(for: known, name: name)
                } else {
                    self.exchangeNotice = GachaText.connection
                }
                self.isExchangeNoticeError = true
            }
        }
    }

    /// 교환 응답을 화면에 옮긴다(세대 가드 · 서버 값만).
    func applyGachaExchangeResponse(_ response: GachaExchangeResponse, id: String, requestID: UUID, generation: Int) async {
        guard generation == context.generation else { return }
        gachaRequestIDs.settleExchange(requestID, for: id)
        if let shards = response.shards { gachaInfo?.shards = shards }
        let outcome = GachaExchangeOutcome(response: response, requestedID: id)
        switch outcome {
        case .exchanged(let characterID, _, _, _):
            ownedCharacterIDs.insert(characterID)
            exchangeNotice = GachaText.notice(for: outcome, name: gachaName(characterID))
            isExchangeNoticeError = false
            await loadShop()
        case .alreadyOwned:
            // 다른 기기에서 이미 얻었다 — 보유로 맞추고 서버 값을 다시 읽는다(조각은 안 깎였다).
            ownedCharacterIDs.insert(id)
            exchangeNotice = GachaText.notice(for: outcome, name: gachaName(id))
            isExchangeNoticeError = false
            await loadShop()
        case .insufficientShards(_, let have):
            if response.shards == nil, let have { gachaInfo?.shards = have }
            exchangeNotice = GachaText.notice(for: outcome, name: gachaName(id))
            isExchangeNoticeError = true
        default:
            exchangeNotice = GachaText.notice(for: outcome, name: gachaName(id))
            isExchangeNoticeError = true
        }
    }

    // MARK: 화면 사건

    /// 결과 연출을 닫는다(다음 뽑기 전 · 화면을 떠날 때).
    package func dismissGachaResult() {
        lastGachaResult = nil
    }

    /// 교환 시트가 닫힐 때 — 시트 안 안내는 시트와 함께 사라진다.
    package func exchangeSheetDidDisappear() {
        exchangeNotice = nil
        isExchangeNoticeError = false
    }

    /// 상점을 떠날 때: 결과 연출·안내를 걷는다. 요청 id 는 **남긴다**(결과를 모르는 채 떠났다면 돌아와 다시 누를 때 같은 id 로 묻는다).
    func gachaDidDisappear() {
        lastGachaResult = nil
        gachaNotice = nil
        isGachaNoticeError = false
        exchangeNotice = nil
        isExchangeNoticeError = false
    }
}
