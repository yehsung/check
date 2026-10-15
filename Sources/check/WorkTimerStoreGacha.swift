import CheckCore
import Foundation

// MARK: - 캐릭터 뽑기 — 맥 배선 (v0.3.54)
//
// 판정(뽑을 수 있나 · 교환할 수 있나 · 결과 분류)·문구·요청 id 수명은 전부 코어 `Gacha.swift`(폰과 한 벌)에 있다. 맥이 더하는 것은
// 세 가지뿐이다:
//  ① 문 — 상점 '소모품' 구획의 [캐릭터 뽑기] 카드 · 캐릭터 격자의 황금 아잉이 카드 · 캐릭터 고르기의 잠긴 금 카드가 뽑기 패널을 연다.
//  ② 왕복 — `gacha_pull` · `gacha_exchange` 를 상점 구매(`buyCharacter`)와 같은 모양으로 부른다(세대 가드 · 세션 재시도 · 취소 무시).
//  ③ 거울 — **서버가 말한 값으로만** 잔량·조각·보유를 고친다(클라가 50 을 빼거나 조각을 더하지 않는다).
//
// 두 번 깎이지 않는 이유(설계서 Wire contract 3): 누를 때마다 요청 id 를 하나 만들고(`GachaRequestIDs`), 결과를 모르는 실패(오프라인 ·
// 5xx · 응답 해석 실패)에서는 그 id 를 **쥔 채** 남긴다 — 다시 누르면 같은 id 로 묻고, 서버가 이미 처리했으면 `replayed` 로 처음
// 결과가 온다. 버튼은 왕복 중 잠기고(`isGachaBusy`), 스토어도 한 번 더 막는다(뷰의 비활성화는 장식일 수 있다 — 클라 게이트는 짝으로).

/// 뽑기 패널의 보기. 패널 높이가 고정이라(`GachaPanel.height`) 한 번에 하나만 보인다.
enum GachaPanelMode: Equatable, Sendable, CaseIterable {
    /// [뽑기] — 큰 버튼 + 결과 연출.
    case pull
    /// [확률 보기] — 일곱 줄(이름 · 상점가 또는 뽑기 전용 · 확률).
    case odds
    /// [조각 교환] — 내 조각 + 교환 목록.
    case exchange
}

@MainActor
extension WorkTimerStore {
    /// 지금 뽑을 수 있는가(값 · 확률표 · 잔량). 판정의 권위는 서버다 — 이건 버튼을 잠그고 이유를 말하는 문이다.
    var gachaPullAvailability: GachaPullAvailability {
        GachaRules.pullAvailability(info: gachaInfo, rubyBalance: rubyBalance)
    }

    /// 상점에 뽑기를 **보여도 되는가**. 서버가 `gacha` 를 안 줬거나(옛 서버 · 능력 번호 2 미만) 값·확률표를 모르면 숨긴다 —
    /// 공개하지 못한 확률로 루비를 받지 않는다.
    var isGachaAvailable: Bool {
        gachaInfo?.isUsable == true
    }

    /// 뽑기·교환 왕복이 떠 있는가. 떠 있으면 두 버튼 모두 잠긴다(동시에 둘이 뜨면 잔량·조각 응답이 뒤섞인다).
    var isGachaBusy: Bool {
        gachaPulling || gachaExchangingID != nil
    }

    /// 내 조각 수(모르면 nil).
    var gachaShards: Int? { gachaInfo?.shards }

    /// 이 캐릭터의 조각 교환값(서버 `shard_costs` — 클라에 숫자를 두지 않는다). 모르면 nil.
    func gachaShardCost(of id: String) -> Int? {
        gachaInfo?.shardCosts?[id].flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: 문

    /// 상점의 [캐릭터 뽑기] 카드. 열려 있으면 접고, 아니면 고른 상품과 확성기 작성기를 접고 연다(같은 자리를 빌린다).
    func toggleGachaPanel() {
        if isGachaPanelOpen {
            closeGachaPanel()
            return
        }
        openGachaPanel()
    }

    /// 뽑기 패널을 연다(이미 열려 있으면 보기만 바꾼다). 구매 왕복 중에는 열지 않는다 — 그 결과 한 줄이 곧 하단 바에 도착한다.
    func openGachaPanel(mode: GachaPanelMode = .pull) {
        guard purchasingID == nil else { return }
        if megaphone.isComposerOpen { megaphone.close() }
        shopSelection = nil
        shopNotice = nil
        if !isGachaPanelOpen {
            gachaNotice = nil
            gachaNoticeIsError = false
        }
        gachaPanelMode = mode
        isGachaPanelOpen = true
    }

    /// 뽑기 패널을 닫는다(멱등). 결과(`gachaLastResult`)는 남긴다 — 다시 열면 방금 무엇이 나왔는지 보인다.
    func closeGachaPanel() {
        isGachaPanelOpen = false
        gachaNotice = nil
        gachaNoticeIsError = false
    }

    /// 뽑기 패널 안의 보기 전환(뽑기 · 확률 · 교환).
    func setGachaPanelMode(_ mode: GachaPanelMode) {
        gachaPanelMode = mode
        gachaNotice = nil
        gachaNoticeIsError = false
    }

    /// 캐릭터 고르기에서 **잠긴** 카드를 눌렀을 때: 상점을 연다. 루비로 살 수 없는 캐릭터(황금 아잉이)면 뽑기 패널까지 연다 —
    /// 상점 격자에서 그 카드를 찾아 다시 누르게 하지 않는다.
    func openShopForLockedCharacter(_ id: String) {
        if !isShopPanelVisible { toggleShopPanel() }
        guard isShopPanelVisible, CharacterCatalog.isGoldAing(id) else { return }
        if isGachaAvailable {
            openGachaPanel()
        } else {
            shopNotice = GachaText.gachaOnlyHint
        }
    }

    // MARK: 뽑기

    /// [뽑기 · 50]. **실제 뽑기는 여기 하나뿐이다.** 서버가 잔량 확인·차감·장부·소유/조각을 한 트랜잭션에서 끝낸다.
    func pullGacha() {
        guard !isGachaBusy, purchasingID == nil else { return }
        let availability = gachaPullAvailability
        guard availability.canPull else {
            gachaNotice = GachaText.blockedReason(availability) ?? ShopText.entryHelp(rubyBalance)
            gachaNoticeIsError = true
            if case .unknownBalance = availability { loadShopState() }
            return
        }
        // 결과를 모르는 실패 뒤라면 **같은 id** 가 나온다(두 번 깎이지 않는다). 아니면 새 id.
        let requestID = gachaRequestIDs.pullID()
        gachaPulling = true
        gachaNotice = nil
        gachaNoticeIsError = false
        let generation = sessionGeneration
        let protocolVersion = shopProtocolVersion
        Task { [weak self] in
            guard let self else { return }
            defer { self.gachaPulling = false }
            do {
                let response = try await withSessionRetry { activeSession in
                    try await self.service.gachaPull(accessToken: activeSession.accessToken,
                                                     protocolVersion: protocolVersion,
                                                     requestID: requestID)
                }
                guard generation == self.sessionGeneration else { return }
                // 서버가 답을 줬다 — 어떤 status 든 그 id 의 결과는 안다.
                self.gachaRequestIDs.settlePull(requestID)
                self.applyGachaPull(GachaPullOutcome(response: response))
            } catch {
                guard generation == self.sessionGeneration else { return }
                if let known = GachaPullOutcome(error: error) {
                    // 함수가 없다(서버가 아무것도 안 했다) — id 를 버려도 된다.
                    self.gachaRequestIDs.settlePull(requestID)
                    self.applyGachaPull(known)
                    return
                }
                // 취소·오프라인·5xx: 서버가 처리했는지 모른다 → id 를 쥔 채 둔다(다시 누르면 같은 id 로 묻는다).
                if case .cancelled = self.classifyAuthError(error) { return }
                self.gachaNotice = GachaText.connection
                self.gachaNoticeIsError = true
            }
        }
    }

    /// 뽑기 결과를 화면 상태로 옮긴다. **서버 값으로만** 고친다(잔량 · 조각 · 새 보유).
    func applyGachaPull(_ outcome: GachaPullOutcome) {
        switch outcome {
        case .pulled(let result):
            if let ruby = result.rubyBalance { rubyBalance = ruby }
            if let shards = result.shards { gachaInfo?.shards = shards }
            if let newID = result.newlyOwnedID { ownedCharacterIDs.insert(newID) }
            gachaLastResult = result
            gachaRevealSerial += 1
            gachaPanelMode = .pull
            gachaNotice = nil
            gachaNoticeIsError = false
            // 보유·가격·조각을 사실과 맞춘다(다른 기기에서 바뀐 것까지).
            loadShopState()
        case .insufficient(_, let have):
            // 서버가 말한 잔량이 화면보다 정확하다(다른 기기에서 썼을 수 있다).
            if let have { rubyBalance = have }
            gachaNotice = GachaText.notice(for: outcome)
            gachaNoticeIsError = true
        default:
            gachaNotice = GachaText.notice(for: outcome)
            gachaNoticeIsError = true
        }
    }

    // MARK: 조각 교환

    /// 교환 목록의 [교환]. 조각만 쓰고 루비는 움직이지 않는다(서버도 루비 장부를 안 쓴다).
    func exchangeGacha(_ characterID: String) {
        guard !isGachaBusy, purchasingID == nil else { return }
        let availability = GachaRules.exchangeAvailability(characterID: characterID,
                                                           isOwned: ownedCharacterIDs.contains(characterID),
                                                           shards: gachaInfo?.shards,
                                                           shardCosts: gachaInfo?.shardCosts)
        guard availability.canExchange else {
            gachaNotice = Self.gachaExchangeBlockedNotice(availability)
            gachaNoticeIsError = true
            return
        }
        let requestID = gachaRequestIDs.exchangeID(for: characterID)
        gachaExchangingID = characterID
        gachaNotice = nil
        gachaNoticeIsError = false
        let generation = sessionGeneration
        let protocolVersion = shopProtocolVersion
        Task { [weak self] in
            guard let self else { return }
            defer { self.gachaExchangingID = nil }
            do {
                let response = try await withSessionRetry { activeSession in
                    try await self.service.gachaExchange(accessToken: activeSession.accessToken,
                                                         characterID: characterID,
                                                         protocolVersion: protocolVersion,
                                                         requestID: requestID)
                }
                guard generation == self.sessionGeneration else { return }
                self.gachaRequestIDs.settleExchange(requestID, for: characterID)
                self.applyGachaExchange(GachaExchangeOutcome(response: response, requestedID: characterID),
                                        requestedID: characterID)
            } catch {
                guard generation == self.sessionGeneration else { return }
                if let known = GachaExchangeOutcome(error: error) {
                    self.gachaRequestIDs.settleExchange(requestID, for: characterID)
                    self.applyGachaExchange(known, requestedID: characterID)
                    return
                }
                if case .cancelled = self.classifyAuthError(error) { return }
                self.gachaNotice = GachaText.connection
                self.gachaNoticeIsError = true
            }
        }
    }

    /// 교환 결과를 화면 상태로 옮긴다.
    func applyGachaExchange(_ outcome: GachaExchangeOutcome, requestedID: String) {
        let name = gachaDisplayName(requestedID)
        switch outcome {
        case .exchanged(let characterID, let shards, _, _):
            ownedCharacterIDs.insert(characterID)
            if let shards { gachaInfo?.shards = shards }
            gachaNotice = GachaText.notice(for: outcome, name: gachaDisplayName(characterID))
            gachaNoticeIsError = false
            loadShopState()
        case .alreadyOwned:
            // 다른 기기에서 이미 얻었다 — 사용자가 할 일이 없다. 목록을 다시 읽으면 화면이 사실과 맞는다.
            ownedCharacterIDs.insert(requestedID)
            gachaNotice = GachaText.notice(for: outcome, name: name)
            gachaNoticeIsError = false
            loadShopState()
        case .insufficientShards(_, let have):
            if let have { gachaInfo?.shards = have }
            gachaNotice = GachaText.notice(for: outcome, name: name)
            gachaNoticeIsError = true
        default:
            gachaNotice = GachaText.notice(for: outcome, name: name)
            gachaNoticeIsError = true
        }
    }

    /// 교환을 막은 이유 한 줄(버튼이 잠겨 있어 보통은 안 온다 — 스토어의 두 번째 문).
    nonisolated static func gachaExchangeBlockedNotice(_ availability: GachaExchangeAvailability) -> String {
        switch availability {
        case .available: return ""
        case .owned: return GachaText.alreadyOwned
        case .short(_, let missing): return GachaText.shardShortfall(missing: missing)
        case .unknownShards: return GachaText.exchangeFailed
        case .notExchangeable: return GachaText.notExchangeable
        }
    }

    /// 뽑기 화면의 캐릭터 이름(카탈로그 → 내장 → id). 확률표·교환 목록·결과 연출이 같은 이름을 쓴다.
    func gachaDisplayName(_ id: String) -> String {
        GachaRules.name(for: id) { CheckCharacter3DScene.catalog.manifest(id: $0)?.displayName }
    }

    /// 로그아웃·계정 전환 — 앞 계정의 뽑기 정보·결과·요청 id 를 다음 사람이 보지도 쓰지도 않게.
    func resetGachaState() {
        gachaInfo = nil
        isGachaPanelOpen = false
        gachaPanelMode = .pull
        gachaPulling = false
        gachaExchangingID = nil
        gachaLastResult = nil
        gachaNotice = nil
        gachaNoticeIsError = false
        gachaRequestIDs.reset()
    }
}
