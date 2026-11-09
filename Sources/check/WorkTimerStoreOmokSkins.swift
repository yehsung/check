import CheckCore
import Foundation

// MARK: - 오목알 스킨 — 맥 상점 배선(v0.3.81)
//
// 대표 결정: 받는 방식 #d_UVBJ8vJua1jD "상점 루비 (스킨마다 100)" · 보이는 범위 #d_RR2dyBIHDMW5 "상대에게도 보임" ·
// 3차 #d_TFKnfZL40Ax6 "2, 4, 5, 7, 6 채택"(네온 · 주사위 · 고양이 · 흑백 아잉이 · 다이아 컷 + 픽셀).
// 서버 정본 20261111130000_omok_skins.sql: omok_skins_state(p_protocol) · buy_omok_skin(p_skin, p_protocol) · set_omok_skin(p_skin).
//
//  ① 상점 '오목알' 탭(`ShopTab.omokSkins`) — 첫 칸 '일반 돌' + 스킨 6칸. 안 가진 칸을 누르면 하단 바에 [구매하기 💎100](캐릭터와 같은
//     `confirmShopPurchase` 한 길 — 카드 탭으로는 사지 않는다). 가진 칸을 누르면 바로 낀다(서버 `set_omok_skin`). 사면 서버가 바로 끼운다.
//  ② 낀 스킨은 서버 대국 · 관전 응답(match.black_skin · white_skin)으로 상대 · 관전자 화면에도 그려진다 — 이 파일은 상점만 한다.
//     AI 판만 로컬이라 낀 스킨을 `gomoku.aiStoneSkin` 에 맞춘다(사람 쪽 돌에만).
//  ③ 잔량은 캐릭터 사기와 같은 규약 — 쓰기 응답의 서버 값을 옮기고 상점 변이로 적는다(`noteShopMutation`).
extension WorkTimerStore {
    /// 스킨 상태를 읽는다. 함수가 없는 서버면 탭을 감춘다. 겹친 호출은 둘 다 나가도 마지막 값이 이긴다(읽기뿐이다).
    @discardableResult
    func loadOmokSkins() -> Task<Void, Never>? {
        guard session != nil else { return nil }
        let generation = sessionGeneration
        return Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await self.withSessionRetry { activeSession in
                    try await self.service.omokSkinsState(accessToken: activeSession.accessToken)
                }
                guard generation == self.sessionGeneration else { return }
                guard state.isOK else { return }
                self.applyOmokSkins(state)
            } catch {
                guard generation == self.sessionGeneration else { return }
                if case .cancelled = self.classifyAuthError(error) { return }
                if let known = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(known) {
                    if !self.omokSkinsUnavailable { self.omokSkinsUnavailable = true }
                    if self.shopTab == .omokSkins { self.shopTab = .characters }
                }
            }
        }
    }

    /// 상태 반영(순수 전이 — 네트워크 없음). AI 판의 내 돌도 같이 맞춘다.
    func applyOmokSkins(_ state: OmokSkinsState) {
        if omokSkinsUnavailable { omokSkinsUnavailable = false }
        if omokSkins != state { omokSkins = state }
        if gomoku.aiStoneSkin != state.equipped { gomoku.aiStoneSkin = state.equipped }
    }

    /// 스킨 값(루비). 서버 줄이 말한 값만 — 모르면 nil(값을 지어내지 않는다).
    func omokSkinPrice(_ skin: OmokStoneSkin) -> Int? {
        omokSkins?.rows.first { $0.skin == skin }?.price
    }

    /// 카드 탭. nil = '일반 돌' 칸. 가진 스킨 · 일반 돌은 바로 낀다(이미 낀 것이면 그렇다고 말한다). 안 가진 스킨은 하단 바에 담는다
    /// (사는 것은 [구매하기] 하나뿐 — `confirmShopPurchase`).
    func selectOmokSkin(_ skin: OmokStoneSkin?) {
        guard purchasingID == nil else { return }
        if megaphone.isComposerOpen { megaphone.close() }
        if isGachaPanelOpen { closeGachaPanel() }
        let owned = skin.map { s in omokSkins?.rows.first { $0.skin == s }?.owned == true } ?? true
        guard owned else {
            shopSelection = skin.map { .omokSkin($0) }
            shopNotice = nil
            return
        }
        shopSelection = nil
        if omokSkins?.equipped == skin {
            shopNotice = OmokSkinShopText.alreadyEquipped(skin)
            return
        }
        equipOmokSkin(skin)
    }

    /// 낀다(서버 `set_omok_skin`). 떠 있으면 요청 0건.
    @discardableResult
    func equipOmokSkin(_ skin: OmokStoneSkin?) -> Task<Void, Never>? {
        guard session != nil, !omokSkinEquipInFlight else { return nil }
        omokSkinEquipInFlight = true
        let generation = sessionGeneration
        return Task { [weak self] in
            guard let self else { return }
            defer { if generation == self.sessionGeneration { self.omokSkinEquipInFlight = false } }
            do {
                let response = try await self.withSessionRetry { activeSession in
                    try await self.service.setOmokSkin(accessToken: activeSession.accessToken, skin: skin)
                }
                guard generation == self.sessionGeneration else { return }
                switch response.status {
                case "ok":
                    let equipped = OmokStoneSkin(wireValue: response.equipped)
                    if let state = self.omokSkins { self.applyOmokSkins(state.applying(equipped: equipped)) }
                    self.shopNotice = OmokSkinShopText.equipped(equipped)
                case "not_owned":
                    // 다른 기기와 어긋났다 — 사실을 다시 읽는다.
                    self.shopNotice = OmokSkinShopText.notOwned
                    self.loadOmokSkins()
                default:
                    self.shopNotice = OmokSkinShopText.equipFailed
                }
            } catch {
                guard generation == self.sessionGeneration else { return }
                if case .cancelled = self.classifyAuthError(error) { return }
                self.shopNotice = OmokSkinShopText.equipFailed
            }
        }
    }

    /// 산다(서버 `buy_omok_skin` — 사면 바로 낀다). `confirmShopPurchase` 만 부른다.
    func buyOmokSkin(_ skin: OmokStoneSkin) {
        guard purchasingID == nil else { return }
        purchasingID = OmokSkinShopText.purchaseID(skin)
        shopNotice = nil
        let generation = sessionGeneration
        Task { [weak self] in
            guard let self else { return }
            defer { self.purchasingID = nil }
            do {
                let response = try await self.withSessionRetry { activeSession in
                    try await self.service.buyOmokSkin(accessToken: activeSession.accessToken, skin: skin)
                }
                guard generation == self.sessionGeneration else { return }
                self.noteShopMutation()
                if let ruby = response.rubyBalance { self.rubyBalance = ruby }
                switch response.status {
                case "ok":
                    let equipped = OmokStoneSkin(wireValue: response.equipped) ?? skin
                    if let state = self.omokSkins {
                        self.applyOmokSkins(state.applying(owned: skin, equipped: equipped, rubyBalance: response.rubyBalance))
                    }
                    self.shopSelection = nil
                    self.shopNotice = OmokSkinShopText.bought(skin)
                case "already_owned":
                    self.shopSelection = nil
                    self.shopNotice = Self.alreadyOwnedNotice
                    self.loadOmokSkins()
                case "insufficient":
                    self.shopNotice = Self.shortfallNotice(need: response.need, have: response.have)
                case "needs_update":
                    self.shopNotice = Self.needsUpdateNotice
                default:
                    self.shopNotice = "구매 실패"
                }
            } catch {
                guard generation == self.sessionGeneration else { return }
                if case .cancelled = self.classifyAuthError(error) { return }
                self.shopNotice = "구매 실패"
            }
        }
    }
}

/// 스킨 상점 문구(순수 — 값으로 검증한다).
enum OmokSkinShopText {
    static let tabCharacters = "캐릭터"
    static let tabSkins = "오목알"
    static let plainName = "일반 돌"
    static let equippedBadge = "착용 중"
    static let owned = "보유"
    static let notOwned = "그 스킨을 갖고 있지 않아요"
    static let equipFailed = "바꾸지 못했어요. 잠시 후 다시 시도해 주세요"
    /// 탭 아래 한 줄 — 상대에게도 보인다는 것과 흑백이 그대로라는 것.
    static let tabNote = "내 돌은 상대 화면에도 이 스킨으로 보여요"
    static func purchaseID(_ skin: OmokStoneSkin) -> String { "omok:\(skin.rawValue)" }
    static func name(_ skin: OmokStoneSkin?) -> String { skin?.displayName ?? plainName }
    static func bought(_ skin: OmokStoneSkin) -> String { "샀어요! 이제 내 돌은 \(skin.displayName)" }
    static func equipped(_ skin: OmokStoneSkin?) -> String { "내 돌을 \(name(skin))\(ro(name(skin))) 바꿨어요" }
    static func alreadyEquipped(_ skin: OmokStoneSkin?) -> String { "이미 \(name(skin))\(eul(name(skin))) 쓰고 있어요" }

    /// 마지막 글자의 받침 번호(한글 음절이 아니면 0 — 받침 없음으로 읽는다). ㄹ = 8.
    static func finalConsonant(_ word: String) -> Int {
        guard let scalar = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return 0 }
        return Int((scalar.value - 0xAC00) % 28)
    }
    /// '(으)로' — 받침 없음 · ㄹ 받침이면 '로', 그 밖은 '으로'.
    static func ro(_ word: String) -> String { [0, 8].contains(finalConsonant(word)) ? "로" : "으로" }
    /// '을/를'.
    static func eul(_ word: String) -> String { finalConsonant(word) == 0 ? "를" : "을" }
}
