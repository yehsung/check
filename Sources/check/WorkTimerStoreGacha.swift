import CheckCore
import Foundation

// MARK: - 캐릭터 뽑기 — 맥 배선 (v0.3.54)
//
// 판정(뽑을 수 있나 · 교환할 수 있나 · 결과 분류)·문구·요청 id 수명은 전부 코어 `Gacha.swift`(폰과 한 벌)에 있다. 맥이 더하는 것은
// 세 가지뿐이다:
//  ① 문 — 상점 '소모품' 구획의 [캐릭터 뽑기] 카드 · 캐릭터 격자의 황금(무지개) 아잉이 카드가 뽑기 패널(확률 · 조각 교환)을 열고,
//     그 패널의 [뽑기 · 50] 과 캐릭터 고르기의 잠긴 금 · 무지개 카드가 **뽑기 창**(캡슐 기계 — `CheckGachaWindow.swift`)을 연다(0.3.54).
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

/// 뽑기 한 번의 표(동기 반쪽이 끊고 왕복 반쪽이 쓴다). 떠날 때의 세대 · 능력 번호를 쥔다 — 왕복 중 로그아웃하면 결과를 버린다.
struct GachaPullTicket: Equatable, Sendable {
    let requestID: UUID
    let generation: Int
    let protocolVersion: Int
}

/// 뽑기 왕복이 어떻게 끝났는가. 창의 기계는 `.answered(.pulled)` 일 때만 공개하고 나머지는 한 줄로 말한다.
enum GachaPullAttempt: Equatable, Sendable {
    /// 서버가 답했다(또는 함수가 없다는 것이 확실하다) — 요청 id 는 버렸다.
    case answered(GachaPullOutcome)
    /// 결과를 모른다(오프라인 · 5xx · 응답 해석 실패) — 요청 id 를 쥔 채 남겼다.
    case connection
    /// 취소됐거나 그 사이 로그아웃·계정 전환이 있었다 — 결과를 화면에 옮기지 않았다.
    case dropped
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

    /// 캐릭터 고르기에서 **잠긴** 카드를 눌렀을 때: 상점을 연다. 루비로 살 수 없는 캐릭터(황금 · 무지개 아잉이)는 뽑기가 그 캐릭터를
    /// 내고 있으면 **뽑기 창**을 바로 연다(0.3.54 — 예전엔 상점 안 뽑기 패널) — 상점 격자에서 그 카드를 찾아 다시 누르게 하지 않는다.
    /// 뽑기가 없거나 그 캐릭터를 안 내면(옛 서버 · 무지개 db push 전) 상점을 열고 얻는 길만 말한다.
    func openShopForLockedCharacter(_ id: String) {
        if CharacterCatalog.isGachaOnlyBuiltIn(id), gachaOffers(id) {
            openGachaWindow()
            return
        }
        if !isShopPanelVisible { toggleShopPanel() }
        guard isShopPanelVisible else { return }
        // 생일 선물 전용(케이크 아잉이 — v0.3.66): 상점을 열고 얻는 길(생일 선물)을 말한다 — 뽑기 창도 [구매하기]도 그 캐릭터에는 거짓이다.
        if CharacterCatalog.isGiftOnlyBuiltIn(id) {
            shopNotice = CakeGiftText.lockedHint
            return
        }
        guard CharacterCatalog.isGachaOnlyBuiltIn(id) else { return }
        shopNotice = GachaText.gachaOnlyHint
    }

    /// 뽑기가 지금 이 캐릭터를 **내는가** — 뽑기가 열려 있고(값 · 완전한 확률표) 그 id 가 확률표나 교환표에 있다.
    /// 희귀 둘의 "얻을 길이 보인다"는 뽑기가 열린 것만으로는 모자라다: 무지개(v0.3.59)는 서버가 능력 번호 3 미만이거나 db push 전이면
    /// 확률표 · 교환표에서 빠진다 — 그때 잠긴 무지개 카드를 세우면 누른 사람은 무지개가 없는 뽑기 창을 본다.
    func gachaOffers(_ id: String) -> Bool {
        Self.gachaOffers(id, info: gachaInfo)
    }

    /// 위 판정의 순수 본체.
    nonisolated static func gachaOffers(_ id: String, info: GachaInfo?) -> Bool {
        guard let info, info.isUsable else { return false }
        return info.odds?.contains { $0.characterID == id } == true || info.shardCosts?[id] != nil
    }

    // MARK: 뽑기 창(캡슐 기계 · 0.3.54)

    /// [뽑기 · 50] — 뽑기 창을 띄운다(이미 떠 있으면 앞으로 · 최소화돼 있으면 되살린다). **여기서는 뽑지 않는다** —
    /// 실제 뽑기는 창 안 기계의 손잡이가 한 바퀴를 다 돈 순간 `pullGachaForReveal()` 한 번이다.
    ///
    /// 뽑기가 없으면(옛 서버 · 정보를 아직 모름) 창을 띄우지 않는다 — 공개하지 못한 확률로 루비를 받지 않는다(`isGachaAvailable`).
    /// 열 때 상점을 한 번 다시 읽는다(다른 기기에서 바뀐 잔량·조각) — 그 사이 뽑기가 끝나도 `loadShopState` 의 변이 순번이 되돌림을 막는다.
    /// 팝오버 안의 버튼이 부르므로 **창 먼저, 팝오버 나중**에 닫는다(미니게임 창과 같은 순서 — `openMiniGameWindow` 주석).
    func openGachaWindow() {
        guard isGachaAvailable else {
            gachaNotice = GachaText.unavailable
            gachaNoticeIsError = true
            return
        }
        loadShopState()
        gachaWindowHooks.show()
        WindowTopAnchor.dismissMenuPopover()
    }

    /// 뽑기 창 기계가 손잡이를 막는 이유(nil = 막지 않는다). 루비 모자람은 기계가 스스로 말한다(잔액·값으로) — 여기선 그 밖의 것만.
    var gachaWindowBlockedReason: String? {
        Self.gachaWindowBlockedReason(signedIn: isSignedIn, availability: gachaPullAvailability)
    }

    /// 위 판정의 순수 본체.
    nonisolated static func gachaWindowBlockedReason(signedIn: Bool, availability: GachaPullAvailability) -> String? {
        guard signedIn else { return GachaText.notSignedIn }
        switch availability {
        case .ready, .short: return nil
        case .unknownBalance: return ShopText.entryHelp(nil)
        case .unavailable: return GachaText.unavailable
        }
    }

    /// 확률표 줄(서버 순서 그대로). 상점 패널 [확률 보기] 와 뽑기 창 "확률 보기" 가 **같은 줄**을 그린다.
    func gachaOddsLines(catalog: CharacterCatalog = CheckCharacter3DScene.catalog) -> [GachaOddsLine] {
        guard let info = gachaInfo else { return [] }
        return GachaRules.oddsRows(info: info, shopRows: shopCharacters) { catalog.manifest(id: $0)?.displayName }
            .map(GachaOddsLine.init)
    }

    // MARK: 황금 · 무지개 아잉이를 세우는 자리 — 캐릭터 고르기 · 상점 자리표시 격자

    /// 이 캐릭터를 캐릭터 고르기·상점 자리표시 격자에 **세우는가**. 루비로 안 파는 캐릭터(황금 · 무지개 아잉이)는 얻을 길이 보일 때만 선다 —
    /// 뽑기가 그 캐릭터를 내거나(`gachaOffers`) · 이미 가졌거나 · 서버 상점이 그 캐릭터를 말했다. 상점을 아직 못 읽었으면 막지 않는다
    /// (로드 전 관용 — `isCharacterUnlocked`; 그 창에서 고른 것은 서버가 거절하면 `pushCharacter` 가 아잉으로 되돌린다).
    ///
    /// 이 문이 없으면 뽑기 없는 서버(뽑기 마이그레이션 전 · 옛 서버)에서 잠긴 금 카드가 서고, 누르면 뽑기 카드도 금 칸도 없는 상점이
    /// "뽑기나 조각 교환으로 얻을 수 있어요"라고 말한다 — 막다른 길이다. 무지개(v0.3.59)는 뽑기가 열려 있어도 무지개를 안 내는 서버
    /// (db push 전)가 같은 막다른 길이라 "뽑기가 열렸다"가 아니라 "뽑기가 **그 캐릭터를** 낸다"를 묻는다. 폰 `MeStoreCharacters.pickerIDs` 와
    /// 같은 결의 규칙이다.
    func isCharacterListed(_ id: String) -> Bool {
        Self.isCharacterListed(id, shopLoaded: shopLoaded, gachaAvailable: gachaOffers(id),
                               owned: ownedCharacterIDs, rows: shopCharacters, wearing: localEquippedCharacterID)
    }

    /// 위 판정의 순수 본체(값으로 검증한다). `gachaAvailable` = 뽑기가 **이 캐릭터를** 낸다(앱은 `gachaOffers(id)` 를 넣는다).
    /// `wearing` = 지금 입은 캐릭터(앱은 이 맥의 착용 `localEquippedCharacterID` 를 넣는다 — 모르면 nil).
    nonisolated static func isCharacterListed(_ id: String, shopLoaded: Bool, gachaAvailable: Bool,
                                              owned: Set<String>, rows: [ShopCharacterRow], wearing: String? = nil) -> Bool {
        // 케이크 아잉이(v0.3.66 생일 선물 전용)는 **가진 사람에게만** 선다 — 코어 내장(`CharacterCatalog.builtIns`)에 둘이 붙으며
        // 모든 사람의 고르기에 잠긴 카드 둘이 늘어 격자가 높이 예산(4행)을 넘던 자리다. 안 가진 사람의 잠긴 칸('생일 선물 전용')은
        // 상점(서버 목록 — `shopGridRows` 는 서버 목록이 있으면 그것을 그대로 쓴다)에서 보인다. 고르기에도 잠긴 칸을 세울지는 화면 단계가 정한다.
        // **입고 있으면 가진 것이다**(서버 `set_character` 는 안 가진 캐릭터를 거절한다) — 상점을 아직 못 읽었거나(시작 직후 · 오프라인)
        // 다른 기기에서 받아 입은 뒤 이 맥의 보유가 낡았어도, 지금 입은 케이크 카드는 선다(금 · 무지개의 '로드 전 관용'과 같은 결).
        if CharacterCatalog.isGiftOnlyBuiltIn(id) { return owned.contains(id) || id == wearing }
        guard isGachaOnly(id, rows: rows) else { return true }
        return !shopLoaded || gachaAvailable || owned.contains(id) || rows.contains { $0.id == id }
    }

    /// 캐릭터 고르기에 서는 id(번들 순서 · 아잉 먼저). `CheckCharacterPanel` 이 같은 판정(`isListed:`)으로 거른다.
    var characterPickerIDs: [String] {
        CheckCharacter3DScene.catalog.allIDs.filter { isCharacterListed($0) }
    }

    /// 상점 격자의 줄. 서버 목록이 유일한 출처다 — 아직 못 읽었거나 비었으면 **번들 목록으로 자리만**(가격 없음) 그리되,
    /// 금 · 무지개는 고르기와 같은 규칙으로 거른다(`isCharacterListed`).
    func shopGridRows(catalog: CharacterCatalog) -> [ShopCharacterRow] {
        guard shopCharacters.isEmpty else { return Self.giftOnlyInDisplayOrder(shopCharacters) }
        // 착용 관용(`wearing` — 입은 케이크)은 고르기 몫이다: 자리표시 줄은 `owned: false` 라 입은 케이크를 세우면 잠긴 칸('생일 선물 전용')으로 선다.
        return catalog.allIDs
            .filter { $0 != CharacterCatalog.builtInAingID
                && Self.isCharacterListed($0, shopLoaded: shopLoaded, gachaAvailable: gachaOffers($0),
                                          owned: ownedCharacterIDs, rows: shopCharacters) }
            .map { ShopCharacterRow(id: $0, price: nil, owned: false) }
    }

    /// 서버 목록의 순서를 지키되 **케이크 둘끼리만** 표시 순서(딸기 → 초코 — `CharacterCatalog.giftOnlyBuiltInIDs`)로 바로 세운다(순수).
    /// 서버는 값 · id 순이라 같은 값(2000)의 두 케이크가 초코 → 딸기로 온다(설계서 §1 은 딸기 먼저). 다른 줄의 자리는 한 칸도 안 옮긴다.
    nonisolated static func giftOnlyInDisplayOrder(_ rows: [ShopCharacterRow]) -> [ShopCharacterRow] {
        let order = CharacterCatalog.giftOnlyBuiltInIDs
        let slots = rows.indices.filter { order.contains(rows[$0].id) }
        guard slots.count > 1 else { return rows }
        let sorted = slots.map { rows[$0] }.sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
        var out = rows
        for (slot, row) in zip(slots, sorted) { out[slot] = row }
        return out
    }

    // MARK: 뽑기

    /// 뽑기 한 번 — 결과를 **기다리지 않는** 문. 앱 화면은 더 부르지 않는다(0.3.54 부터 뽑기는 창 기계의 `pullGachaForReveal()`);
    /// 스토어 시험이 이 문으로 왕복 규칙(연타 · 결과 모름 id · 서버 값 거울)을 잰다. 둘은 같은 두 조각(`startGachaPull` →
    /// `finishGachaPull`)을 지난다 — 판정 · 요청 id · 세대 가드 · 서버 값 거울이 한 벌이라 시험이 재는 것이 곧 창이 타는 길이다.
    func pullGacha() {
        guard let ticket = startGachaPull() else { return }
        Task { [weak self] in
            _ = await self?.finishGachaPull(ticket)
        }
    }

    /// 창 기계의 `pull`. 손잡이가 한 바퀴를 다 돈 순간 **한 번** 불린다(기계가 한 판에 한 번만 부르고, 스토어가 한 번 더 막는다).
    ///
    /// 서버가 ok 를 말했을 때만 결과를 돌려준다 — 그 밖(모자람 · 업데이트 필요 · 연결 실패 · 스토어가 막음)은 전부 `GachaRevealFailure`
    /// 로 던진다(기계는 공개 없이 한 줄을 2.4초 띄우고 처음으로). 결과를 모르는 실패는 요청 id 를 쥔 채 던진다 — 다음 판이 같은 id 로 묻는다.
    /// 잔량·조각·보유는 이미 서버 값으로 옮겨졌다(`applyGachaPull`) — 기계는 넘겨받은 값만 보여 준다.
    func pullGachaForReveal() async throws -> GachaRevealOutcome {
        // 연출의 조각 칩은 "뽑기 전 → 뒤" 로 올라간다. 서버가 뒤 조각 수를 안 줬을 때만 이 값에 더한다.
        let shardsBefore = gachaShards ?? 0
        // 막힌 이유는 **묻기 전에** 정한다 — `gachaNotice` 에는 앞 동작(교환 결과 등)의 한 줄이 남아 있을 수 있다.
        let refusal = gachaPullRefusal
        guard let ticket = startGachaPull() else {
            throw GachaRevealFailure(message: refusal ?? GachaText.pullFailed)
        }
        let attempt = await finishGachaPull(ticket)
        return try Self.revealOutcome(for: attempt, shardsBefore: shardsBefore) { self.gachaDisplayName($0) }
    }

    /// 왕복 결과 → 기계 연출 값(또는 던질 실패). 순수 — 값으로 검증한다.
    nonisolated static func revealOutcome(for attempt: GachaPullAttempt, shardsBefore: Int,
                                          name: (String) -> String) throws -> GachaRevealOutcome {
        switch attempt {
        case .answered(.pulled(let result)):
            return GachaRevealOutcome(result: result, name: name(result.characterID), shardsBefore: shardsBefore)
        case .answered(let other):
            throw GachaRevealFailure(message: GachaText.notice(for: other) ?? GachaText.pullFailed)
        case .connection:
            throw GachaRevealFailure(message: GachaText.connection)
        case .dropped:
            throw GachaRevealFailure(message: GachaText.pullFailed)
        }
    }

    /// 서버에 묻기 전에 막는 이유(막지 않으면 nil). 다른 왕복(뽑기 · 교환 · 구매)이 떠 있으면 일반 실패 한 줄 — 서버에 안 갔으니 깎이지 않았다.
    var gachaPullRefusal: String? {
        if isGachaBusy || purchasingID != nil { return GachaText.pullFailed }
        let availability = gachaPullAvailability
        guard !availability.canPull else { return nil }
        return GachaText.blockedReason(availability) ?? ShopText.entryHelp(rubyBalance)
    }

    /// 뽑기의 동기 반쪽: 판정 → 요청 id → 왕복 표시. 막히면 nil(이유는 `gachaNotice` 에 — 왕복 중이면 말없이).
    ///
    /// **결과를 모르는 실패 뒤라면 같은 id 가 나온다**(두 번 깎이지 않는다 — `GachaRequestIDs`). `gachaPulling` 은 여기서
    /// 동기로 선다 — 같은 틱의 두 번째 누름이 바로 막힌다(뷰의 비활성화는 장식일 수 있다 — 클라 게이트는 짝으로).
    func startGachaPull() -> GachaPullTicket? {
        guard !isGachaBusy, purchasingID == nil else { return nil }
        let availability = gachaPullAvailability
        guard availability.canPull else {
            gachaNotice = GachaText.blockedReason(availability) ?? ShopText.entryHelp(rubyBalance)
            gachaNoticeIsError = true
            if case .unknownBalance = availability { loadShopState() }
            return nil
        }
        let ticket = GachaPullTicket(requestID: gachaRequestIDs.pullID(), generation: sessionGeneration,
                                     protocolVersion: shopProtocolVersion)
        gachaPulling = true
        gachaNotice = nil
        gachaNoticeIsError = false
        return ticket
    }

    /// 뽑기의 왕복 반쪽. **실제 뽑기 RPC 는 여기 하나뿐이다.** 서버가 잔량 확인·차감·장부·소유/조각을 한 트랜잭션에서 끝낸다.
    func finishGachaPull(_ ticket: GachaPullTicket) async -> GachaPullAttempt {
        defer { gachaPulling = false }
        do {
            let response = try await withSessionRetry { activeSession in
                try await self.service.gachaPull(accessToken: activeSession.accessToken,
                                                 protocolVersion: ticket.protocolVersion,
                                                 requestID: ticket.requestID)
            }
            guard ticket.generation == sessionGeneration else { return .dropped }
            // 서버가 답을 줬다 — 어떤 status 든 그 id 의 결과는 안다.
            gachaRequestIDs.settlePull(ticket.requestID)
            let outcome = GachaPullOutcome(response: response)
            applyGachaPull(outcome)
            return .answered(outcome)
        } catch {
            guard ticket.generation == sessionGeneration else { return .dropped }
            if let known = GachaPullOutcome(error: error) {
                // 함수가 없다(서버가 아무것도 안 했다) — id 를 버려도 된다.
                gachaRequestIDs.settlePull(ticket.requestID)
                applyGachaPull(known)
                return .answered(known)
            }
            // 취소·오프라인·5xx: 서버가 처리했는지 모른다 → id 를 쥔 채 둔다(다시 누르면 같은 id 로 묻는다).
            if case .cancelled = classifyAuthError(error) { return .dropped }
            gachaNotice = GachaText.connection
            gachaNoticeIsError = true
            return .connection
        }
    }

    /// 뽑기 결과를 화면 상태로 옮긴다. **서버 값으로만** 고친다(잔량 · 조각 · 새 보유).
    ///
    /// 서버 값을 옮기는 갈래는 먼저 `noteShopMutation()` 을 부른다 — 이 뽑기 **전에** 떠난 상점 조회(직전 뽑기 뒤의 다시 읽기)가
    /// 나중에 도착해도 이 값을 한 판 전으로 되돌리지 않는다([한 번 더] 연타 — `loadShopState` 의 ★).
    func applyGachaPull(_ outcome: GachaPullOutcome) {
        switch outcome {
        case .pulled(let result):
            noteShopMutation()
            if let ruby = result.rubyBalance { rubyBalance = ruby }
            if let shards = result.shards { gachaInfo?.shards = shards }
            if let newID = result.newlyOwnedID { ownedCharacterIDs.insert(newID) }
            gachaLastResult = result
            gachaPanelMode = .pull
            gachaNotice = nil
            gachaNoticeIsError = false
            // 보유·가격·조각을 사실과 맞춘다(다른 기기에서 바뀐 것까지).
            loadShopState()
        case .insufficient(_, let have):
            // 서버가 말한 잔량이 화면보다 정확하다(다른 기기에서 썼을 수 있다).
            if let have {
                noteShopMutation()
                rubyBalance = have
            }
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

    /// 교환 결과를 화면 상태로 옮긴다. 서버 값을 옮기는 갈래는 뽑기와 같이 `noteShopMutation()` 을 먼저 부른다.
    func applyGachaExchange(_ outcome: GachaExchangeOutcome, requestedID: String) {
        let name = gachaDisplayName(requestedID)
        switch outcome {
        case .exchanged(let characterID, let shards, _, _):
            noteShopMutation()
            ownedCharacterIDs.insert(characterID)
            if let shards { gachaInfo?.shards = shards }
            gachaNotice = GachaText.notice(for: outcome, name: gachaDisplayName(characterID))
            gachaNoticeIsError = false
            loadShopState()
        case .alreadyOwned:
            // 다른 기기에서 이미 얻었다 — 사용자가 할 일이 없다. 목록을 다시 읽으면 화면이 사실과 맞는다.
            noteShopMutation()
            ownedCharacterIDs.insert(requestedID)
            gachaNotice = GachaText.notice(for: outcome, name: name)
            gachaNoticeIsError = false
            loadShopState()
        case .insufficientShards(_, let have):
            if let have {
                noteShopMutation()
                gachaInfo?.shards = have
            }
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

    /// 로그아웃·계정 전환 — 앞 계정의 뽑기 정보·결과·요청 id 를 다음 사람이 보지도 쓰지도 않게. 뽑기 창도 내린다 — 남기면 다음 사람이
    /// 앞 사람의 잔량·조각이 박힌 기계를 본다(체스 창의 `ChessAccountWatcher` 와 같은 이유 — 여긴 스토어가 직접 닫는다).
    func resetGachaState() {
        gachaWindowHooks.close()
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

