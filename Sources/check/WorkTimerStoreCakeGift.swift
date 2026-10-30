import CheckCore
import Foundation

// MARK: - 생일 선물 — 케이크 아잉이 맥 배선 (v0.3.66)
//
// 전선 모양 · 결과 분류 · 문구는 전부 코어 `CharacterGift.swift`(폰과 한 벌)에 있다. 맥이 더하는 것은 세 가지다:
//  ① 박자 — 열린 선물을 **이 자리에서만** 묻는다(설계서 §5 · 조정자 결정 — 이 이상 자주 부르지 마라):
//     앱 시작(저장 세션 활성화) · 로그인 직후 · 가입 직후 · 상점 진입 · 기존 15초 폴링에 얹되 **10분에 1번 이하**(`cakeGiftPeriodicSeconds`).
//     이 빌드가 케이크를 못 그리면(능력 번호 < 4) 묻지 않는다 — 서버도 gift 를 싣지 않는다(`ShopWire.supportsCakeGift`).
//  ② 축하 창 — 열린 선물이 있으면 **실행당 한 번** 스스로 띄운다(`cakeGiftAutoShownIDs`). 고르지 않고 닫으면 메뉴 팝오버의 '다시 열기' 카드
//     (`CheckMenuView.TopBanner.cakeGift`)가 수령할 때까지 남는다(`cakeGiftOffer` 가 있는 동안).
//  ③ 수령 — `claim_character_gift` 를 상점 구매와 같은 모양으로 부른다(세대 가드 · 세션 재시도 · 취소 무시). 받으면 보유를 서버 값으로 다시 읽고
//     (`loadShopState`), [지금 입기]는 **기존 착용 경로**(`CheckCharacterPicker.choose` → `pushSelectedCharacter`)를 탄다 — 서버 수령은 착용을
//     움직이지 않는다(설계서 §2-4).
//  ④ 결론은 서버가 낸다(검토 수리) — 축하 창은 **자기가 그리는 선물**로 확인한다(조회가 그 선물을 내려도 `replayed` · `already_claimed` 가
//     받은 뒤 화면으로 데려간다). 결론이 난 선물 id(`cakeGiftSettledIDs`)를 말하는 낡은 조회는 버리고, 상점 보유를 읽으면 열린 선물의
//     선택지를 보유와 맞춘다(`reconcileCakeGiftWithOwnership` — 다른 기기에서 받은 선물).

/// 축하 창을 띄우고 내리는 문. 스토어가 쥔다(`WorkTimerStore.cakeGiftWindowHooks`) — 테스트가 갈아 끼워 "창이 열렸는가"를 센다.
struct CakeGiftWindowHooks {
    /// 창을 띄운다. 인자 = **앱을 앞으로 데려와 키를 잡는가**(`activating`). 사용자가 누른 [고르기]는 참, 스스로 띄우기는 거짓이다 —
    /// 선물 조회는 박자(시작 · 15초 폴링)에 얹혀 아무 때나 끝나므로, 키를 잡으면 1:1 대결 창(테트리스 하드드롭 = 스페이스)이나 다른 앱에서
    /// 치던 키를 이 창이 가로챈다. 거짓이면 창은 맨 앞에 서되 키는 그대로다(누르면 그때 잡는다).
    var show: @MainActor (_ activating: Bool) -> Void
    var close: @MainActor () -> Void
    /// 창이 지금 떠 있는가(자동 띄우기가 이미 뜬 창을 다시 앞으로 끌지 않게).
    var isOpen: @MainActor () -> Bool
    /// 사용자가 닫은 창에서 메뉴 팝오버로 돌아간다(v0.3.69 — `WindowTopAnchor.returnToMenuPopover`). 시험이 갈아 끼운다(실제 문은 앱을
    /// 활성화하고 상태바 버튼을 누른다). 기본값을 두지 않는다 — 대역이 빠뜨리면 시험이 실제 문을 누른다.
    var returnToPopover: @MainActor () -> Void

    @MainActor static var live: CakeGiftWindowHooks {
        CakeGiftWindowHooks(show: { CheckCakeGiftWindowController.shared.show(activating: $0) },
                            close: { CheckCakeGiftWindowController.shared.close() },
                            isOpen: { CheckCakeGiftWindowController.shared.isOpen },
                            returnToPopover: { _ = WindowTopAnchor.returnToMenuPopover() })
    }
}

/// 선물을 묻는 까닭(= 호출 지점의 목록). 이 밖에서 묻지 않는다.
enum CakeGiftCheckReason: String, Equatable, Sendable {
    /// 저장 세션 활성화(앱 시작).
    case launch
    /// 로그인 마무리 직후.
    case signIn
    /// 가입 마무리 직후(가입으로 세션을 손에 쥔 순간 — 로그인과 같은 첫 조회다. 없으면 이 실행의 10분 주기가 영영 안 돈다).
    case signUp
    /// 상점 진입(`toggleShopPanel` 이 여는 순간).
    case shop
    /// 15초 폴링(`localExpiryTick`) — 10분 문을 지날 때만.
    case periodic
}

@MainActor
extension WorkTimerStore {
    /// 주기 새로고침이 선물을 다시 묻는 최소 간격(초) — 10분(조정자 결정). 시작 · 로그인 · 상점은 이 문을 안 지난다(그 자리가 곧 묻는 자리다).
    nonisolated static let cakeGiftPeriodicSeconds: TimeInterval = 600

    /// 이 빌드가 생일 선물을 받을 수 있는가(능력 번호 4 — 케이크 둘을 다 그린다). 아니면 묻지도 띄우지도 않는다.
    var supportsCakeGift: Bool {
        ShopWire.supportsCakeGift(protocolVersion: shopProtocolVersion)
    }

    /// 메뉴 팝오버 '다시 열기' 카드를 세우는가 — 열린 선물이 있다(받으면 내려간다).
    var showsCakeGiftCard: Bool {
        cakeGiftOffer != nil
    }

    // MARK: 박자

    /// 폴링 tick 전용 — 앞선 조회(시작 · 로그인 · 상점 · 주기)로부터 10분이 지났을 때만 묻는다. **한 번도 안 물었으면 묻지 않는다** —
    /// 첫 조회는 시작 · 로그인 자리의 몫이다(세션을 손에 쥔 순간). 요청 0건이 기본값이다.
    func refreshCakeGiftIfDue(now: Date) {
        guard let last = cakeGiftLastCheckAt, Self.cakeGiftCheckIsDue(last: last, now: now) else { return }
        refreshCakeGift(reason: .periodic)
    }

    /// 10분 문(순수 — 값으로 검증한다).
    nonisolated static func cakeGiftCheckIsDue(last: Date?, now: Date) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last) >= cakeGiftPeriodicSeconds
    }

    /// 열린 선물을 한 번 묻는다. 결과를 기다리지 않는 문 — 반환 Task 는 테스트가 완료를 기다리는 손잡이다.
    @discardableResult
    func refreshCakeGift(reason: CakeGiftCheckReason) -> Task<Void, Never>? {
        guard session != nil, supportsCakeGift, !cakeGiftChecking else { return nil }
        cakeGiftChecking = true
        // 스탬프는 **발사 시점**에 찍는다(지갑 sync 와 같은 규약) — 서버가 죽어 있는 동안 15초마다 두드리지 않게.
        cakeGiftLastCheckAt = clock()
        let generation = sessionGeneration
        let protocolVersion = shopProtocolVersion
        return Task { @MainActor [weak self] in
            guard let self else { return }
            // 세대가 바뀌었으면(로그아웃 · 계정 전환) 깃발은 `resetCakeGiftState` 가 이미 내렸고, 그 뒤 새 계정의 조회가 다시 들었을 수 있다 —
            // 옛 조회가 그 깃발을 내리면 겹쳐 쏜다. 내 세대일 때만 내린다.
            defer { if generation == self.sessionGeneration { self.cakeGiftChecking = false } }
            do {
                let offer = try await self.withSessionRetry { activeSession in
                    try await self.service.fetchCharacterGiftPending(accessToken: activeSession.accessToken,
                                                                     protocolVersion: protocolVersion)
                }
                guard generation == self.sessionGeneration else { return }
                self.applyCakeGiftPending(offer)
            } catch {
                // 네트워크 · 5xx · 세션 만료 · 취소: 지금 아는 선물을 그대로 둔다(다음 박자에 다시 묻는다).
                return
            }
        }
    }

    /// 조회 결과를 화면 상태로 옮긴다. 선물이 있으면 이 실행에서 처음 본 선물일 때 **한 번** 축하 창을 스스로 띄운다.
    func applyCakeGiftPending(_ offer: CharacterGiftOffer?) {
        // 받는 중에는 손대지 않는다 — 수령 응답이 곧 사실을 말한다(그 사이 조회가 "없음"을 말해 카드가 깜빡이지 않게).
        guard !cakeGiftClaiming else { return }
        // 결론이 난 선물을 말하는 응답은 수령 **전에** 떠난 낡은 조회다 — 받았는데 '다시 열기' 카드가 되살아나지 않게 '없음'으로 읽는다.
        // 보유로 이미 다 가진 선택지는 거른다(다른 기기에서 받은 뒤 아직 서버 조회가 그 사실을 모를 때 — `reconcileCakeGiftWithOwnership`).
        let fresh = offer.flatMap { cakeGiftSettledIDs.contains($0.id) ? nil : cakeGiftFilteredByOwnership($0) }
        let vanished = cakeGiftOffer.map { $0.id != fresh?.id } ?? false
        cakeGiftOffer = fresh
        // 알던 선물이 조회에서 사라졌다 — 응답을 잃은 수령이 서버엔 커밋됐거나 다른 기기에서 먼저 받았다. 보유를 서버 값으로 다시 읽는다
        // (축하 창은 그리던 선물 그대로 확인할 수 있다 — 서버가 `replayed` · `already_claimed` 로 결론을 준다).
        if vanished { loadShopState() }
        guard let offer = fresh else { return }
        guard !cakeGiftAutoShownIDs.contains(offer.id) else { return }
        cakeGiftAutoShownIDs.insert(offer.id)
        // 이미 떠 있으면(다시 열기로 연 창) 끌어오지 않는다.
        guard !cakeGiftWindowHooks.isOpen() else { return }
        // 스스로 띄울 때는 키를 잡지 않는다(`CakeGiftWindowHooks.show` 주석 — 대결 · 다른 앱의 키를 가로채지 않게).
        // 팝오버에서 온 것이 아니므로 닫아도 팝오버로 돌아가지 않는다.
        cakeGiftReturnsToPopover = false
        presentCakeGiftWindow(offer, activating: false)
    }

    // MARK: 축하 창

    /// '다시 열기' 카드의 [고르기]. 열린 선물이 없으면 아무것도 안 한다. 팝오버 안의 버튼이 부르므로 **창 먼저, 팝오버 나중**에 닫는다
    /// (뽑기 창과 같은 순서 — `openGachaWindow` 주석).
    /// 닫으면 팝오버로 돌아간다(`cakeGiftReturnsToPopover` — v0.3.69, 뽑기 창과 같은 이유).
    func openCakeGiftWindow() {
        guard let offer = cakeGiftOffer else { return }
        presentCakeGiftWindow(offer, activating: true)
        cakeGiftReturnsToPopover = true
        WindowTopAnchor.dismissMenuPopover()
    }

    /// 창 상태를 이 선물의 고르기 화면으로 세우고 창을 띄운다. 선택지가 하나뿐이면(하나는 이미 가졌다) 미리 골라 둔다.
    /// 같은 선물이라도 선택지가 바뀌었으면(보유로 걸렀다 — `reconcileCakeGiftWithOwnership`) 고르기를 새로 세운다.
    private func presentCakeGiftWindow(_ offer: CharacterGiftOffer, activating: Bool) {
        if cakeGiftPresented != offer || cakeGiftReceivedID != nil {
            cakeGiftChoice = offer.options.count == 1 ? offer.options.first : nil
            cakeGiftReceivedID = nil
        }
        cakeGiftPresented = offer
        cakeGiftNotice = nil
        cakeGiftWindowHooks.show(activating)
    }

    /// 축하 창에서 하나를 고른다(받지 않는다 — 확인 단추가 받는다). 선택지 밖 id · 받는 중 · 받은 뒤는 무시한다.
    func chooseCakeGift(_ id: String) {
        guard !cakeGiftClaiming, cakeGiftReceivedID == nil,
              cakeGiftPresented?.options.contains(id) == true else { return }
        cakeGiftChoice = id
        cakeGiftNotice = nil
    }

    /// 확인 단추를 누를 수 있는가. 창은 **자기가 그리는 선물**(`cakeGiftPresented`)로 확인한다 — 조회가 그 선물을 내렸어도(응답을 잃은
    /// 수령이 서버엔 커밋됐다 · 창이 떠 있는 동안 폰에서 먼저 받았다) 누르면 서버가 결론을 준다(같은 선택 = `replayed`, 다른 선택 =
    /// `already_claimed` → 둘 다 받은 뒤 화면). 잠그는 것은 서버가 **이미 결론을 준** 선물뿐이다(`cakeGiftSettledIDs` — 받지 못한 채 끝난
    /// `not_found` · 받은 것을 모르는 `already_claimed`): 다시 눌러 봐야 같은 결론만 되풀이된다.
    var canConfirmCakeGift: Bool {
        guard let presented = cakeGiftPresented else { return false }
        return !cakeGiftClaiming && cakeGiftReceivedID == nil && cakeGiftChoice != nil
            && !cakeGiftSettledIDs.contains(presented.id)
    }

    /// 확인 단추(`CakeGiftText.confirmButton`) — 고른 캐릭터로 선물을 받는다. **수령 RPC 는 여기 하나뿐이다.**
    /// 반환 Task 는 테스트가 완료를 기다리는 손잡이다.
    @discardableResult
    func claimCakeGift() -> Task<Void, Never>? {
        guard canConfirmCakeGift, let offer = cakeGiftPresented, let choice = cakeGiftChoice else { return nil }
        cakeGiftClaiming = true
        cakeGiftNotice = nil
        let generation = sessionGeneration
        let protocolVersion = shopProtocolVersion
        return Task { @MainActor [weak self] in
            guard let self else { return }
            // 조회와 같은 이유로 내 세대일 때만 내린다(로그아웃이 이미 내렸다).
            defer { if generation == self.sessionGeneration { self.cakeGiftClaiming = false } }
            do {
                let response = try await self.withSessionRetry { activeSession in
                    try await self.service.claimCharacterGift(accessToken: activeSession.accessToken, giftID: offer.id,
                                                              characterID: choice, protocolVersion: protocolVersion)
                }
                guard generation == self.sessionGeneration else { return }
                self.applyCakeGiftClaim(CharacterGiftClaimOutcome(response: response, requestedID: choice), giftID: offer.id)
            } catch {
                guard generation == self.sessionGeneration else { return }
                if let known = CharacterGiftClaimOutcome(error: error) {
                    self.applyCakeGiftClaim(known, giftID: offer.id)
                    return
                }
                // 결과를 모른다(오프라인 · 5xx · 응답 해석 실패) — 같은 선택으로 다시 눌러도 안전하다(같은 캐릭터면 `replayed`).
                if case .cancelled = self.classifyAuthError(error) { return }
                self.cakeGiftNotice = CakeGiftText.claimFailed
            }
        }
    }

    /// 수령 결과를 화면 상태로 옮긴다. 받았으면(이미 받았던 것 포함) 보유에 넣고 상점을 다시 읽는다 — 보유의 권위는 서버다.
    func applyCakeGiftClaim(_ outcome: CharacterGiftClaimOutcome, giftID: String) {
        switch outcome {
        case .received(let id, _), .alreadyClaimed(.some(let id)):
            // 이미 다른 캐릭터로 받았다(다른 기기) — 사용자는 그 케이크를 가졌다. 받은 뒤 화면을 그 캐릭터로 보인다
            // (`CakeGiftText.notice` 도 "○○를 받았어요!" 로 말한다).
            noteShopMutation()
            ownedCharacterIDs.insert(id)
            cakeGiftReceivedID = id
            cakeGiftNotice = nil
        default:
            cakeGiftNotice = CakeGiftText.notice(for: outcome) { self.gachaDisplayName($0) }
        }
        if outcome.settlesGift {
            cakeGiftSettledIDs.insert(giftID)
            if cakeGiftOffer?.id == giftID { cakeGiftOffer = nil }
            loadShopState()
        }
    }

    // MARK: 보유와 맞추기

    /// 이 선물에서 **이미 가진** 선택지를 뺀다(남는 게 없으면 nil — 고를 것이 없는 선물이다). 보유를 모르면(상점 미로드) 그대로다 —
    /// `ownedCharacterIDs` 는 그때 아잉뿐이라 아무것도 안 빠진다. 서버 조회는 읽는 시점에 이미 거르므로 이 거름은 **우리가 더 최근에 안**
    /// 보유(다른 기기에서 받은 뒤 다시 읽은 상점)만 반영한다. 보유는 줄지 않으므로 거르는 쪽이 늘 안전하다.
    func cakeGiftFilteredByOwnership(_ offer: CharacterGiftOffer) -> CharacterGiftOffer? {
        let left = offer.options.filter { !ownedCharacterIDs.contains($0) }
        guard !left.isEmpty else { return nil }
        guard left.count != offer.options.count else { return offer }
        return CharacterGiftOffer(id: offer.id, options: left, note: offer.note, createdAt: offer.createdAt)
    }

    /// 상점 상태(보유)를 읽은 뒤 — 열린 선물의 선택지를 보유와 맞추고, 남는 게 없으면 선물 · '다시 열기' 카드를 거둔다(다른 기기에서 받았다).
    /// 축하 창이 그리는 선물(`cakeGiftPresented`)은 건드리지 않는다 — 창은 그 선물로 확인하고 서버가 결론을 준다(`canConfirmCakeGift`).
    /// `applyShopState` 가 보유를 옮긴 직후에 부른다.
    func reconcileCakeGiftWithOwnership() {
        guard let offer = cakeGiftOffer else { return }
        let kept = cakeGiftFilteredByOwnership(offer)
        if kept != offer { cakeGiftOffer = kept }
    }

    /// 받은 뒤 화면의 [지금 입기] — **기존 착용 경로**를 탄다(고르기 패널과 같다: 로컬 저장 → 방송 → 서버 `set_character`). 창을 닫는다.
    func wearCakeGift() {
        guard let id = cakeGiftReceivedID else { return }
        let selection = CharacterSelection(defaults: characterDefaults, catalog: CheckCharacter3DScene.catalog)
        if CheckCharacterPicker.choose(id, selection: selection, broadcast: characterSync.broadcast) {
            pushSelectedCharacter(announcesFailure: true)
        }
        closeCakeGiftWindow()
    }

    /// 창의 [닫기] · [지금 입기]. 고르지 않고 닫아도 선물은 남는다(`cakeGiftOffer` — '다시 열기' 카드).
    func closeCakeGiftWindow() {
        cakeGiftWindowHooks.close()
        cakeGiftDidClose()
    }

    /// 사용자가 창을 닫았다([닫기] · [지금 입기] → `closeCakeGiftWindow`, 빨간 점 → 컨트롤러의 `windowWillClose`). 받은 뒤 화면이었으면
    /// 다음에 열 때 고르기 화면부터다. 팝오버의 [고르기] 로 연 창이면 팝오버로 돌아간다(v0.3.69) — **한 번만**: 돌아가는 문은 디바운스를
    /// 안 보므로 두 번 부르면 방금 연 팝오버가 도로 닫힌다. 로그아웃(`resetCakeGiftState`)은 이 길을 안 지난다(팝오버가 튀어나오지 않게).
    func cakeGiftDidClose() {
        cakeGiftNotice = nil
        if cakeGiftReceivedID != nil {
            cakeGiftReceivedID = nil
            cakeGiftPresented = nil
            cakeGiftChoice = nil
        }
        if cakeGiftReturnsToPopover {
            cakeGiftReturnsToPopover = false
            cakeGiftWindowHooks.returnToPopover()
        }
    }

    /// 로그아웃 · 계정 전환 — 앞 계정의 선물을 다음 사람이 보지도 받지도 않게. 창도 내린다. 실행당 한 번 기록은 남긴다(실행 단위).
    func resetCakeGiftState() {
        cakeGiftWindowHooks.close()
        cakeGiftReturnsToPopover = false
        cakeGiftOffer = nil
        cakeGiftPresented = nil
        cakeGiftChoice = nil
        cakeGiftClaiming = false
        cakeGiftReceivedID = nil
        cakeGiftNotice = nil
        cakeGiftLastCheckAt = nil
        cakeGiftChecking = false
    }
}
