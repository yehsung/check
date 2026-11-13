import CheckCore
import Foundation

// MARK: - 오목알 스킨 — 폰 상점(1.0.18 · 맥 0.3.81 `WorkTimerStoreOmokSkins` 와 같은 규약)
//
// 대표 결정: 받는 방식 #d_UVBJ8vJua1jD "상점 루비 (스킨마다 100)" · 보이는 범위 #d_RR2dyBIHDMW5 "상대에게도 보임" ·
// 대표 11-10 "네온 흑백 다이아 이렇게 3개 빼." → 주사위 · 고양이 · 픽셀(운영 11-10 15:03).
// 서버: omok_skins_state(p_protocol) · buy_omok_skin(p_skin, p_protocol) · set_omok_skin(p_skin). 폰도 스킨 능력 1(`OmokStoneSkin.protocolVersion`).
//  ① 상점 '오목알' 절: '일반 돌' + 서버가 말한 스킨 칸. 안 가진 칸을 누르면 확인 뒤 산다(사면 서버가 바로 끼운다). 가진 칸을 누르면 낀다.
//  ② 낀 스킨은 서버 대국 · 관전 응답(match.black_skin · white_skin)으로 상대 · 관전자 판에 그려진다. AI 판만 로컬이라 `gomoku.aiStoneSkin` 에 맞춘다.
//  ③ 잔량은 캐릭터 사기와 같은 규약 — 쓰기 응답의 서버 값을 루비 미러에 옮긴다.
extension MeStore {
    /// 세션에 한 번(값이 없을 때만) 읽는다 — 앱이 앞에 올 때 · 상점이 뜰 때.
    package func refreshOmokSkinsIfNeeded() {
        guard context.session.isSignedIn, omokSkins == nil, !omokSkinsUnavailable, !omokSkinsLoading else { return }
        launch { [weak self] in await self?.loadOmokSkins() }
    }

    package func loadOmokSkins() async {
        guard context.session.isSignedIn else { return }
        omokSkinsLoading = true
        defer { omokSkinsLoading = false }
        let generation = context.generation
        let service = context.service
        do {
            let state = try await context.withMobileSessionRetry { session in
                try await service.omokSkinsState(accessToken: session.accessToken)
            }
            guard generation == context.generation, state.isOK else { return }
            applyOmokSkins(state)
        } catch {
            guard generation == context.generation else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            if MobileDeviceRPC.isMissingFunction(error) { omokSkinsUnavailable = true }
        }
    }

    func applyOmokSkins(_ state: OmokSkinsState) {
        if omokSkinsUnavailable { omokSkinsUnavailable = false }
        if omokSkins != state { omokSkins = state }
        if context.gomoku.aiStoneSkin != state.equipped { context.gomoku.aiStoneSkin = state.equipped }
    }

    /// 상점에 '오목알' 절을 세우는가(서버가 스킨 줄을 하나라도 말했을 때).
    package var showsOmokSkins: Bool { !omokSkinsUnavailable && !(omokSkins?.rows.isEmpty ?? true) }
    package var equippedOmokSkin: OmokStoneSkin? { omokSkins?.equipped }
    package func isOmokSkinOwned(_ skin: OmokStoneSkin) -> Bool { omokSkins?.rows.first { $0.skin == skin }?.owned == true }
    package func omokSkinPrice(_ skin: OmokStoneSkin) -> Int? { omokSkins?.rows.first { $0.skin == skin }?.price }

    /// 가진 칸(또는 '일반 돌')을 눌렀다 — 낀다. 이미 끼었으면 그 사실만 말한다.
    package func equipOmokSkin(_ skin: OmokStoneSkin?) {
        guard context.session.isSignedIn, omokSkinBusy == nil else { return }
        if omokSkins?.equipped == skin {
            omokSkinNotice = OmokSkinPhoneText.alreadyEquipped(skin)
            return
        }
        omokSkinBusy = "equip"
        omokSkinNotice = nil
        let generation = context.generation
        let service = context.service
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.omokSkinBusy = nil } }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.setOmokSkin(accessToken: session.accessToken, skin: skin)
                }
                guard generation == self.context.generation else { return }
                switch response.status {
                case "ok":
                    let equipped = OmokStoneSkin(wireValue: response.equipped)
                    if let state = self.omokSkins { self.applyOmokSkins(state.applying(equipped: equipped)) }
                    self.omokSkinNotice = OmokSkinPhoneText.equipped(equipped)
                case "not_owned":
                    self.omokSkinNotice = OmokSkinPhoneText.notOwned
                    await self.loadOmokSkins()
                default:
                    self.omokSkinNotice = OmokSkinPhoneText.equipFailed
                }
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.omokSkinNotice = OmokSkinPhoneText.equipFailed
            }
        }
    }

    /// 확인 대화상자의 [구매하기]에서만 부른다(칸 탭으로는 사지 않는다 — 캐릭터와 같은 규약). 사면 서버가 바로 끼운다.
    package func buyOmokSkin(_ skin: OmokStoneSkin) {
        guard context.session.isSignedIn, omokSkinBusy == nil else { return }
        omokSkinBusy = skin.rawValue
        omokSkinNotice = nil
        let generation = context.generation
        let service = context.service
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.omokSkinBusy = nil } }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.buyOmokSkin(accessToken: session.accessToken, skin: skin)
                }
                guard generation == self.context.generation else { return }
                if let ruby = response.rubyBalance { self.context.gomokuHost.rubyBalance = ruby }
                switch response.status {
                case "ok":
                    let equipped = OmokStoneSkin(wireValue: response.equipped) ?? skin
                    if let state = self.omokSkins {
                        self.applyOmokSkins(state.applying(owned: skin, equipped: equipped, rubyBalance: response.rubyBalance))
                    }
                    self.omokSkinNotice = OmokSkinPhoneText.bought(skin)
                case "already_owned":
                    self.omokSkinNotice = MeText.alreadyOwned
                    await self.loadOmokSkins()
                case "insufficient":
                    self.omokSkinNotice = CheckCoreShared.shortfallNotice(need: response.need, have: response.have)
                case "needs_update":
                    self.omokSkinNotice = OmokSkinPhoneText.needsUpdate
                default:
                    self.omokSkinNotice = MeText.buyFailed
                }
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.omokSkinNotice = MeText.buyFailed
            }
        }
    }
}

/// 오목알 절 글자 — 맥 `OmokSkinShopText` 와 같은 글자.
package enum OmokSkinPhoneText {
    package static let title = "오목알"
    package static let plainName = "일반 돌"
    package static let equippedBadge = "착용 중"
    package static let owned = "보유"
    package static let note = "내 돌은 상대 화면에도 이 스킨으로 보여요"
    package static let notOwned = "그 스킨을 갖고 있지 않아요"
    package static let equipFailed = "바꾸지 못했어요. 잠시 후 다시 시도해 주세요"
    package static let needsUpdate = "앱을 업데이트하면 살 수 있어요"
    package static func name(_ skin: OmokStoneSkin?) -> String { skin?.displayName ?? plainName }
    package static func bought(_ skin: OmokStoneSkin) -> String { "샀어요! 이제 내 돌은 \(skin.displayName)" }
    package static func equipped(_ skin: OmokStoneSkin?) -> String { "내 돌을 \(name(skin))\(ro(name(skin))) 바꿨어요" }
    package static func alreadyEquipped(_ skin: OmokStoneSkin?) -> String { "이미 \(name(skin))\(eul(name(skin))) 쓰고 있어요" }
    package static func confirmTitle(_ skin: OmokStoneSkin) -> String { "\(skin.displayName) 오목알을 살까요?" }

    static func finalConsonant(_ word: String) -> Int {
        guard let scalar = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return 0 }
        return Int((scalar.value - 0xAC00) % 28)
    }
    static func ro(_ word: String) -> String { [0, 8].contains(finalConsonant(word)) ? "로" : "으로" }
    static func eul(_ word: String) -> String { finalConsonant(word) == 0 ? "를" : "을" }
}
