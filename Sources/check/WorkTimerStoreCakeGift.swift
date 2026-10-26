import CheckCore
import Foundation

// MARK: - 생일 선물 — 케이크 아잉이 맥 배선 (v0.3.66)
//
// 전선 모양 · 결과 분류 · 문구는 전부 코어 `CharacterGift.swift`(폰과 한 벌)에 있다. 맥이 더하는 것은 세 가지다:
//  ① 박자 — 열린 선물을 **이 자리에서만** 묻는다(설계서 §5 · 조정자 결정 — 이 이상 자주 부르지 마라):
//     앱 시작(저장 세션 활성화) · 로그인 직후 · 상점 진입 · 기존 15초 폴링에 얹되 **10분에 1번 이하**(`cakeGiftPeriodicSeconds`).
//     이 빌드가 케이크를 못 그리면(능력 번호 < 4) 묻지 않는다 — 서버도 gift 를 싣지 않는다(`ShopWire.supportsCakeGift`).
//  ② 축하 창 — 열린 선물이 있으면 **실행당 한 번** 스스로 띄운다(`cakeGiftAutoShownIDs`). 고르지 않고 닫으면 메뉴 팝오버의 '다시 열기' 카드
//     (`CheckMenuView.TopBanner.cakeGift`)가 수령할 때까지 남는다(`cakeGiftOffer` 가 있는 동안).
//  ③ 수령 — `claim_character_gift` 를 상점 구매와 같은 모양으로 부른다(세대 가드 · 세션 재시도 · 취소 무시). 받으면 보유를 서버 값으로 다시 읽고
//     (`loadShopState`), [지금 입기]는 **기존 착용 경로**(`CheckCharacterPicker.choose` → `pushSelectedCharacter`)를 탄다 — 서버 수령은 착용을
//     움직이지 않는다(설계서 §2-4).

/// 축하 창을 띄우고 내리는 문. 스토어가 쥔다(`WorkTimerStore.cakeGiftWindowHooks`) — 테스트가 갈아 끼워 "창이 열렸는가"를 센다.
struct CakeGiftWindowHooks {
    /// 창을 띄운다. 인자 = **앱을 앞으로 데려와 키를 잡는가**(`activating`). 사용자가 누른 [고르기]는 참, 스스로 띄우기는 거짓이다 —
    /// 선물 조회는 박자(시작 · 15초 폴링)에 얹혀 아무 때나 끝나므로, 키를 잡으면 1:1 대결 창(테트리스 하드드롭 = 스페이스)이나 다른 앱에서
    /// 치던 키를 이 창이 가로챈다. 거짓이면 창은 맨 앞에 서되 키는 그대로다(누르면 그때 잡는다).
    var show: @MainActor (_ activating: Bool) -> Void
    var close: @MainActor () -> Void
    /// 창이 지금 떠 있는가(자동 띄우기가 이미 뜬 창을 다시 앞으로 끌지 않게).
    var isOpen: @MainActor () -> Bool

    @MainActor static var live: CakeGiftWindowHooks {
        CakeGiftWindowHooks(show: { CheckCakeGiftWindowController.shared.show(activating: $0) },
                            close: { CheckCakeGiftWindowController.shared.close() },
                            isOpen: { CheckCakeGiftWindowController.shared.isOpen })
    }
}

/// 선물을 묻는 까닭(= 호출 지점의 목록). 이 밖에서 묻지 않는다.
enum CakeGiftCheckReason: String, Equatable, Sendable {
    /// 저장 세션 활성화(앱 시작).
    case launch
    /// 로그인 마무리 직후.
    case signIn
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
        cakeGiftOffer = offer
        guard let offer else { return }
        guard !cakeGiftAutoShownIDs.contains(offer.id) else { return }
        cakeGiftAutoShownIDs.insert(offer.id)
        // 이미 떠 있으면(다시 열기로 연 창) 끌어오지 않는다.
        guard !cakeGiftWindowHooks.isOpen() else { return }
        // 스스로 띄울 때는 키를 잡지 않는다(`CakeGiftWindowHooks.show` 주석 — 대결 · 다른 앱의 키를 가로채지 않게).
        presentCakeGiftWindow(offer, activating: false)
    }

    // MARK: 축하 창

    /// '다시 열기' 카드의 [고르기]. 열린 선물이 없으면 아무것도 안 한다. 팝오버 안의 버튼이 부르므로 **창 먼저, 팝오버 나중**에 닫는다
    /// (뽑기 창과 같은 순서 — `openGachaWindow` 주석).
    func openCakeGiftWindow() {
        guard let offer = cakeGiftOffer else { return }
        presentCakeGiftWindow(offer, activating: true)
        WindowTopAnchor.dismissMenuPopover()
    }

    /// 창 상태를 이 선물의 고르기 화면으로 세우고 창을 띄운다. 선택지가 하나뿐이면(하나는 이미 가졌다) 미리 골라 둔다.
    private func presentCakeGiftWindow(_ offer: CharacterGiftOffer, activating: Bool) {
        if cakeGiftPresented?.id != offer.id || cakeGiftReceivedID != nil {
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

    /// 확인 단추를 누를 수 있는가. 창이 그리는 선물이 **아직 열려 있어야** 한다 — 받지 못한 채 끝난 선물(`not_found` · 받은 것을 모르는
    /// `already_claimed`)이나 조회가 '없음'으로 내린 선물에 다시 눌러 봐야 같은 실패 문구만 되풀이된다.
    var canConfirmCakeGift: Bool {
        !cakeGiftClaiming && cakeGiftReceivedID == nil && cakeGiftChoice != nil
            && cakeGiftPresented != nil && cakeGiftOffer?.id == cakeGiftPresented?.id
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
            if cakeGiftOffer?.id == giftID { cakeGiftOffer = nil }
            loadShopState()
        }
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

    /// 창의 [닫기] · 빨간 점. 고르지 않고 닫아도 선물은 남는다(`cakeGiftOffer` — '다시 열기' 카드).
    func closeCakeGiftWindow() {
        cakeGiftWindowHooks.close()
        cakeGiftDidClose()
    }

    /// 창이 닫혔다(사용자가 빨간 점을 눌렀든 우리가 닫았든). 받은 뒤 화면이었으면 다음에 열 때 고르기 화면부터다.
    func cakeGiftDidClose() {
        cakeGiftNotice = nil
        if cakeGiftReceivedID != nil {
            cakeGiftReceivedID = nil
            cakeGiftPresented = nil
            cakeGiftChoice = nil
        }
    }

    /// 로그아웃 · 계정 전환 — 앞 계정의 선물을 다음 사람이 보지도 받지도 않게. 창도 내린다. 실행당 한 번 기록은 남긴다(실행 단위).
    func resetCakeGiftState() {
        cakeGiftWindowHooks.close()
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
