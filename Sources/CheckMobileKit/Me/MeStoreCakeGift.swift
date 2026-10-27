import CheckCore
import CheckMobileShared
import Foundation

// MARK: - 생일 선물 — 케이크 아잉이 (맥 0.3.66 · 폰 1.0.14)
//
// 서버 · 전선 · 결과 분류 · 문구는 코어 한 벌이다(`CheckCore/CharacterGift.swift` — 맥과 같은 함수 · 같은 글자). 이 파일은 폰의 **언제 묻고
// 언제 띄우는가**와 시트의 상태만 쥔다. 뷰(`MeCakeGiftViews.swift`)는 `#if os(iOS)` 라 맥 스위트가 못 보므로 판정은 전부 여기 있다.
//
// 규칙(조정자 결정 — 설계서 §6)
// - 묻는 때: 앱이 앞으로 올 때(로그인 직후도 같은 길 — `MobileAppModel.activateStores` → `appDidBecomeActive`) · **10분에 한 번 이하**.
//   새 타이머 · 새 폴링은 없다.
// - 열린 선물이 있으면 **실행당 한 번**(선물 id 마다) 스스로 띄운다. 한 번은 **실제로 화면에 선 때**로 센다(`cakeGiftSheetDidAppear`) —
//   스토어가 시트를 세웠어도 화면에 못 섰으면(다른 시트가 떠 있다) 쓴 것이 아니다. 계정을 바꿔도 같은 실행에서 같은 선물을 두 번 띄우지 않는다.
// - **대국·관전 중에는 스스로 띄우지 않는다**(오목·체스·테트리스 화면 — `GamesStore.isAnyMatchScreenVisible`): 30초 수·15초 침묵이
//   걸린 판을 시트가 덮으면 진다. 그동안은 나 탭 '다시 열기' 줄만 서고, 다음 기회(앞으로 올 때 · 탭을 옮길 때)에 띄운다.
// - 고르지 않고 닫으면 나 탭에 '다시 열기' 줄(`CakeGiftText.reopenTitle` · `reopenButton`)이 **수령할 때까지** 남는다. [고르기]는
//   스로틀을 건너뛰고 서버에 다시 물은 뒤 연다(다른 기기에서 이미 받았으면 줄이 걷히고 시트는 안 뜬다).
// - 선택지는 **보유와 맞춰 거른다**(`unownedCakeGift`): 이미 가진 케이크를 고르는 길이 없다. 상점 상태가 새 보유를 말하면 거르고,
//   남는 게 없으면 선물 · 다시 열기 줄을 거두고, 보유가 움직였으면 서버에 다시 묻는다(다른 기기 수령 — `reconcileCakeGiftWithOwnership`).
// - 받은 뒤 `shop_state` 를 다시 읽어 보유를 맞추고, [지금 입기]는 기존 착용 경로(`chooseCharacter`)를 탄다.

/// 축하 시트 한 장의 상태. 시트는 선물 id 로 선다(`Identifiable`) — 단계가 바뀌어도 같은 시트다.
package struct MeCakeGiftSheet: Equatable, Identifiable, Sendable {
    package enum Phase: Equatable, Sendable {
        /// 둘 중 하나를 고르는 중(확인 단추는 고른 뒤에만 켜진다).
        case choosing
        /// 수령 요청이 떠 있다(단추 잠금 · 시트를 끌어 닫지 못한다).
        case claiming
        /// 받았다 — "○○를 받았어요!" + [지금 입기] [닫기].
        case received(characterID: String)
        /// 선물이 끝났는데 받은 것을 모른다(내 선물이 아님 · 받은 id 를 안 실은 `already_claimed`) — 안내와 [닫기]만.
        case closed
    }

    package let gift: CharacterGiftOffer
    package var selection: String?
    package var phase: Phase
    /// 실패 · 거절 한 줄(코어 `CakeGiftText.notice(for:name:)` · `claimFailed`). nil 이면 없음.
    package var notice: String?

    package init(gift: CharacterGiftOffer, selection: String? = nil, phase: Phase = .choosing, notice: String? = nil) {
        self.gift = gift
        self.selection = selection
        self.phase = phase
        self.notice = notice
    }

    package var id: String { gift.id }

    /// [이걸로 받을게요]를 누를 수 있는가 — 고르는 중이고, 고른 것이 이 선물의 선택지다.
    package var canConfirm: Bool {
        guard phase == .choosing, let selection else { return false }
        return gift.options.contains(selection)
    }

    /// 받은 캐릭터(받은 뒤 화면일 때만).
    package var receivedID: String? {
        if case .received(let id) = phase { return id }
        return nil
    }
}

extension MeStore {
    /// 선물 조회 간격(초) — **10분에 한 번 이하**(조정자 결정). 시도 시각으로 잰다(실패해도 10분 안에 다시 묻지 않는다).
    package nonisolated static let cakeGiftCheckInterval: TimeInterval = 600

    /// 수령 결과를 **옮긴** 횟수. 조회가 떠날 때 찍고, 도착했을 때 달라졌으면 그 조회는 수령 **전**의 서버를 말한다 —
    /// 그대로 옮기면 방금 받은 선물이 다시 열린 것으로 서서 '다시 열기' 줄이 되살아난다. 그때는 응답을 버린다.
    nonisolated static let cakeGiftClaimWriteKey = "write.cakeGiftClaim"

    // MARK: 묻기

    /// 앱이 앞으로 올 때(`appDidBecomeActive`): 마지막 시도에서 10분이 지났으면 묻는다.
    package func refreshCakeGiftIfStale() {
        guard context.session.isSignedIn, !cakeGiftLoading else { return }
        if let last = cakeGiftCheckedAt, context.clock.now().timeIntervalSince(last) < Self.cakeGiftCheckInterval { return }
        launch { [weak self] in await self?.loadCakeGift() }
    }

    /// `character_gift_pending(p_protocol)` 한 번. 이 빌드가 케이크를 다 그리지 못하면(번호 < 4) 묻지 않는다 — 서버도 gift 를 싣지 않는다.
    ///
    /// - 성공(선물 있음 · 없음 · 옛 서버 404 → 없음): 선물을 옮긴다(`applyCakeGiftOffer`).
    /// - 실패(오프라인 · 5xx): 지금 아는 선물을 그대로 둔다(모르는 것을 "선물 없음"으로 단정하지 않는다).
    package func loadCakeGift() async {
        guard context.session.isSignedIn else { return }
        let protocolVersion = shopProtocolVersion
        guard ShopWire.supportsCakeGift(protocolVersion: protocolVersion) else { return }
        let serial = nextSerial("cakeGift")
        let generation = context.generation
        let claimStamp = writeStamp(Self.cakeGiftClaimWriteKey)
        cakeGiftCheckedAt = context.clock.now()
        cakeGiftLoading = true
        defer { if isCurrent("cakeGift", serial) { cakeGiftLoading = false } }
        let service = context.service
        do {
            let offer = try await context.withMobileSessionRetry { session in
                try await service.fetchCharacterGiftPending(accessToken: session.accessToken, protocolVersion: protocolVersion)
            }
            guard generation == context.generation, isCurrent("cakeGift", serial),
                  writeStamp(Self.cakeGiftClaimWriteKey) == claimStamp else { return }
            applyCakeGiftOffer(offer)
        } catch {
            // 지난 값을 둔다(위 주석). 취소도 같다.
        }
    }

    /// 서버가 말한 열린 선물을 옮기고(보유와 맞춰 거른 값), 아직 화면에 띄운 적 없는 선물이면 시트를 세운다(`presentCakeGiftIfDue`).
    func applyCakeGiftOffer(_ offer: CharacterGiftOffer?) {
        cakeGift = offer.flatMap(unownedCakeGift)
        guard let gift = cakeGift else { return }
        if var sheet = cakeGiftSheet {
            // 같은 선물을 고르는 중이면 선택지만 새 값으로(다른 기기에서 하나를 가져 선택지가 줄었을 수 있다).
            if sheet.gift.id == gift.id, sheet.phase == .choosing, sheet.gift != gift {
                sheet = MeCakeGiftSheet(gift: gift, selection: sheet.selection.flatMap { gift.options.contains($0) ? $0 : nil },
                                        notice: sheet.notice)
                cakeGiftSheet = sheet
            }
            return
        }
        presentCakeGiftIfDue()
    }

    /// 열린 선물을 **스스로** 띄울 때가 됐으면 시트를 세운다 — 아는 선물이 있고 · 시트가 없고 · 이 실행에서 아직 화면에 선 적이 없고 ·
    /// 대국·관전 화면이 떠 있지 않을 때. 부르는 자리: 선물 조회가 끝났을 때 · 앞으로 올 때(`appDidBecomeActive`) · 탭을 옮길 때
    /// (`MobileAppModel.tabDidChange`). 미룬 동안은 나 탭 '다시 열기' 줄이 선다(`showsCakeGiftReopen`).
    package func presentCakeGiftIfDue() {
        guard context.session.isSignedIn, cakeGiftSheet == nil, let gift = cakeGift,
              !cakeGiftAutoShownIDs.contains(gift.id), !isGameScreenUp else { return }
        cakeGiftSheet = MeCakeGiftSheet(gift: gift)
    }

    /// 오목 · 체스 · 테트리스 화면(로비 · 대국 · 관전)이 떠 있다 — 축하 시트가 스스로 뜨지 않는 때. 로비도 넣는 까닭: 받은 신청을
    /// 수락하면 그 자리에서 판이 서므로, 로비 위에 뜬 시트가 곧 대국을 덮는다.
    var isGameScreenUp: Bool {
        context.links.games?.isAnyMatchScreenVisible ?? false
    }

    /// 선물의 선택지를 **지금 아는 보유**와 맞춰 거른다 — 이미 가진 케이크를 고르는 길이 없게. 남는 게 없으면 nil(받을 것이 없다).
    /// 서버도 읽는 시점에 거르지만(`character_gift_pending`) 그 뒤에 다른 기기에서 받으면 폰이 아는 선물은 낡는다.
    /// 보유를 아직 못 읽었으면(아잉뿐) 서버 값을 그대로 둔다.
    func unownedCakeGift(_ gift: CharacterGiftOffer) -> CharacterGiftOffer? {
        let remaining = gift.options.filter { !isOwned($0) }
        if remaining == gift.options { return gift }
        if remaining.isEmpty { return nil }
        return CharacterGiftOffer(id: gift.id, options: remaining, note: gift.note, createdAt: gift.createdAt)
    }

    /// 상점 상태(`applyShopState`)가 보유를 새로 말한 뒤: 아는 선물과 고르는 중인 시트의 선택지를 보유와 맞춘다.
    ///
    /// - 선물: 거른 값으로. 남는 게 없으면 거둔다 — 나 탭 '다시 열기' 줄이 사라진다.
    /// - 고르는 중인 시트: 선택지를 거르고, 고른 것이 가진 것이면 고름을 푼다. 남는 게 없으면 '이미 받은 선물이에요' + [닫기].
    /// - 둘 중 하나라도 움직였으면 **서버에 다시 묻는다**(스로틀 무시): 선택지가 하나 남아도 다른 기기에서 받은 것이면 서버는 선물을
    ///   이미 닫았다 — 묻지 않으면 그 하나가 '다시 열기' 줄로 10분까지 남는다.
    /// 받는 중 · 받은 뒤 · 끝난 시트는 건드리지 않는다(내 수령 결과가 그 화면을 쥔다).
    func reconcileCakeGiftWithOwnership() {
        var moved = false
        if let gift = cakeGift {
            let kept = unownedCakeGift(gift)
            if kept != gift {
                cakeGift = kept
                moved = true
            }
        }
        if let sheet = cakeGiftSheet, sheet.phase == .choosing {
            let remaining = sheet.gift.options.filter { !isOwned($0) }
            if remaining != sheet.gift.options {
                moved = true
                if remaining.isEmpty {
                    cakeGiftSheet = MeCakeGiftSheet(gift: sheet.gift, phase: .closed, notice: CakeGiftText.alreadyClaimed)
                } else {
                    let gift = CharacterGiftOffer(id: sheet.gift.id, options: remaining, note: sheet.gift.note,
                                                  createdAt: sheet.gift.createdAt)
                    cakeGiftSheet = MeCakeGiftSheet(gift: gift, selection: sheet.selection.flatMap { remaining.contains($0) ? $0 : nil },
                                                    notice: sheet.notice)
                }
            }
        }
        if moved { launch { [weak self] in await self?.loadCakeGift() } }
    }

    // MARK: 화면 사건

    /// 나 탭에 서는 '다시 열기' 줄의 조건 — 열린 선물이 있고 시트가 떠 있지 않다.
    package var showsCakeGiftReopen: Bool {
        cakeGift != nil && cakeGiftSheet == nil
    }

    /// '다시 열기' 줄의 [고르기] — **스로틀을 건너뛰고 서버에 다시 묻고** 연다. 다른 기기에서 이미 받았으면 서버가 선물 없음을 말해
    /// 줄이 걷히고 시트는 안 뜬다(받은 선물을 다시 고르게 하지 않는다). 묻기가 실패하면(오프라인) 아는 선물(보유와 거른 값)로 연다 —
    /// 수령이 서버에서 다시 판정된다(`already_claimed` · `invalid_choice`).
    package func reopenCakeGift() {
        guard cakeGift != nil, cakeGiftSheet == nil, !cakeGiftReopening, context.session.isSignedIn else { return }
        cakeGiftReopening = true
        let generation = context.generation
        launch { [weak self] in
            guard let self else { return }
            await self.loadCakeGift()
            guard generation == self.context.generation else { return }
            self.cakeGiftReopening = false
            // 묻는 사이 스스로 섰을 수 있다(아직 화면에 띄운 적 없는 선물 — `presentCakeGiftIfDue`).
            guard self.cakeGiftSheet == nil, let gift = self.cakeGift.flatMap(self.unownedCakeGift) else { return }
            self.cakeGiftSheet = MeCakeGiftSheet(gift: gift)
        }
    }

    package func selectCakeGiftOption(_ id: String) {
        guard var sheet = cakeGiftSheet, sheet.phase == .choosing, sheet.gift.options.contains(id) else { return }
        sheet.selection = id
        sheet.notice = nil
        cakeGiftSheet = sheet
    }

    /// 시트를 닫는다(고르지 않고 · 받은 뒤 [닫기] · 끌어 내림 · 못 띄운 시트 거두기). 선물이 아직 열려 있으면 '다시 열기' 줄이 남는다.
    /// **받는 중(`.claiming`)에는 닫지 않는다** — 결과를 모른 채 닫히면 수령이 성공해도 받은 뒤 화면 · [지금 입기]가 서지 않는다
    /// (머리 [X] 도 그동안 꺼져 있다 · 끌어 닫기는 `interactiveDismissDisabled`).
    package func dismissCakeGiftSheet() {
        guard cakeGiftSheet?.phase != .claiming else { return }
        cakeGiftSheet = nil
    }

    /// 시트 뷰가 화면에 섰다 · 내려갔다(뷰의 onAppear · onDisappear). 섰을 때 그 선물을 **띄운 것으로 센다**(실행당 한 번).
    package func cakeGiftSheetDidAppear() {
        cakeGiftSheetOnScreen = true
        if let id = cakeGiftSheet?.gift.id { cakeGiftAutoShownIDs.insert(id) }
    }

    package func cakeGiftSheetDidDisappear() {
        cakeGiftSheetOnScreen = false
    }

    /// [이걸로 받을게요] — `claim_character_gift`. 같은 선택으로 다시 불러도 안전하다(서버가 `replayed` 로 같은 답을 준다).
    package func confirmCakeGift() {
        guard var sheet = cakeGiftSheet, sheet.canConfirm, let choice = sheet.selection, context.session.isSignedIn else { return }
        let giftID = sheet.gift.id
        sheet.phase = .claiming
        sheet.notice = nil
        cakeGiftSheet = sheet
        let generation = context.generation
        let service = context.service
        let protocolVersion = shopProtocolVersion
        launch { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.claimCharacterGift(accessToken: session.accessToken, giftID: giftID,
                                                         characterID: choice, protocolVersion: protocolVersion)
                }
                await self.applyCakeGiftClaim(CharacterGiftClaimOutcome(response: response, requestedID: choice),
                                              giftID: giftID, generation: generation)
            } catch {
                guard generation == self.context.generation else { return }
                if let outcome = CharacterGiftClaimOutcome(error: error) {
                    await self.applyCakeGiftClaim(outcome, giftID: giftID, generation: generation)
                    return
                }
                // 결과를 모른다(오프라인 · 5xx · 취소) — 고르는 화면으로 돌려 다시 누르게 한다(같은 선택이면 replayed).
                guard var current = self.cakeGiftSheet, current.gift.id == giftID, current.phase == .claiming else { return }
                current.phase = .choosing
                current.notice = AuthErrorRules.classify(error) == .cancelled ? nil : CakeGiftText.claimFailed
                self.cakeGiftSheet = current
            }
        }
    }

    /// 수령 결과를 옮긴다. **보낼 때의 세대가 아니면 아무것도 안 한다**(로그아웃 뒤 앞 계정의 결과가 다음 계정에 서지 않게).
    ///
    /// - 받았다(`received` · 받은 id 를 아는 `already_claimed`): 보유에 넣고, 받은 뒤 화면으로, 상점을 다시 읽는다(서버 보유가 진실).
    /// - 선물이 끝났다(`settlesGift`): 열린 선물을 거둔다 — '다시 열기' 줄이 사라진다.
    /// - 그 밖(업데이트 필요 · 고를 수 없음 · 서버 미배포 · 모르는 status): 고르는 화면에 한 줄 안내, 선물은 그대로 열려 있다.
    func applyCakeGiftClaim(_ outcome: CharacterGiftClaimOutcome, giftID: String, generation: Int) async {
        guard generation == context.generation else { return }
        var received: String?
        switch outcome {
        case .received(let id, _), .alreadyClaimed(.some(let id)):
            received = id
        default:
            received = nil
        }
        if outcome.settlesGift {
            noteLocalWrite(Self.cakeGiftClaimWriteKey)
            if cakeGift?.id == giftID { cakeGift = nil }
        }
        if let received { ownedCharacterIDs.insert(received) }
        if var sheet = cakeGiftSheet, sheet.gift.id == giftID {
            if let received {
                sheet.phase = .received(characterID: received)
                sheet.notice = nil
            } else {
                sheet.phase = outcome.settlesGift ? .closed : .choosing
                sheet.notice = CakeGiftText.notice(for: outcome, name: MeCharacterName.display)
            }
            cakeGiftSheet = sheet
        }
        if received != nil { await loadShop() }
    }

    /// 받은 뒤 [지금 입기] — 시트를 닫고 **기존 착용 경로**(`chooseCharacter` → `set_character`)를 탄다.
    package func wearReceivedCakeGift() {
        guard let id = cakeGiftSheet?.receivedID else { return }
        cakeGiftSheet = nil
        chooseCharacter(id)
    }
}
