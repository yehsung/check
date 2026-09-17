import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 나 탭이 쌓는 하위 화면(`router.push(_:on: .me)` 의 값).
package enum MeDestination: Hashable, Sendable {
    case shop
    case characters
    case profile
    case feedback
    case settings
}

/// 한 덩어리(머리·기록·상점…)의 불러오기 상태 — 순위 탭과 같은 뜻의 세 깃발 + 마지막 성공 시각.
package typealias MeLoadState = RankingsLoadState

/// 나 탭 스토어(SPEC-ios §3.6) — 프로필 머리 · 루비 · 기록(회고·잔디·리듬) · 캐릭터(상점·고르기) · 프로필(사진·별명) · 제보 · 설정.
///
/// 수명(기반 자리 API): `init(context:)` 네트워크 없음 · `appDidBecomeActive()` 탭이 보이면 낡은 것만 다시 읽는다 ·
/// `appDidEnterBackground()` · `reset()` 계정에 묶인 값 전부 비움 · `badgeCount` = 안 본 제보 답장이 있으면 1(탭 막대는 기반이 아직
/// 나 탭 배지를 그리지 않는다 — 나 탭 안의 제보 줄에 점으로 보인다).
///
/// 폰이 **하지 않는 것**(코드로 막혀 있다): 울트라 구매(상점은 캐릭터 가지만 — `buy_ultra` 경로 없음) · 지갑 동기화(`ultra_wallet_sync`) ·
/// 집중 모드 PATCH(공개 설정 GET 에 딸려 오는 focus_mode 는 읽고 버린다) · 앱 빌드 PATCH · 팀 상태 반영(`applyFetchedTeamStatuses` 계열 —
/// 진행 중 세션 시각만 읽는다) · 제보 진단 줄.
///
/// 늦은 응답 가드: 세대(로그아웃) · 덩어리별 요청 순번 · (기록) 주가 바뀌면 옛 계산 버림.
@MainActor
@Observable
package final class MeStore {
    @ObservationIgnored package let context: MobileContext

    package private(set) var isTabVisible = false

    // MARK: 머리
    package internal(set) var displayName: String?
    package internal(set) var avatarURL: URL?
    /// 센터 **서버값**("seoul"). 화면은 `CenterBadge` 가 글자로 접는다.
    package internal(set) var centerServerValue: String?
    package internal(set) var headerState = MeLoadState()

    // MARK: 기록
    package internal(set) var heatmap: WorkRhythmHeatmap = .empty
    package internal(set) var retro: WeeklyRetro?
    package internal(set) var dailyGrid: WorkDailyGrid = .empty
    package internal(set) var tokenGrid: TokenDailyGrid = .empty
    /// 토큰 수집을 켠 사람만 토큰 잔디를 본다(맥 `tokenUsageCollect` 게이트).
    package internal(set) var showsTokenGrid = true
    package internal(set) var recordsState = MeLoadState()
    @ObservationIgnored package internal(set) var recordsWeekKey: String?

    // MARK: 캐릭터 · 상점
    package internal(set) var shopCharacters: [ShopCharacterRow] = []
    package internal(set) var ownedCharacterIDs: Set<String> = [MeCharacterCards.aingID]
    package internal(set) var shopState = MeLoadState()
    package internal(set) var shopSelection: String?
    package internal(set) var shopNotice: String?
    package internal(set) var purchasingID: String?
    /// 서버 착용값(`profiles.character`, 원문). nil = 기본(아잉) 또는 아직 모름(`equippedLoaded` 로 가른다).
    package internal(set) var equippedServerID: String?
    package internal(set) var equippedLoaded = false
    package internal(set) var savingCharacterID: String?
    package internal(set) var characterNotice: String?
    package internal(set) var isCharacterNoticeError = false

    // MARK: 프로필 편집
    package var displayNameDraft = ""
    /// 편집 화면이 떠 있는가(머리가 늦게 오면 그때 입력을 채운다).
    package internal(set) var isProfileVisible = false
    package internal(set) var displayNameNotice: String?
    package internal(set) var isDisplayNameNoticeError = false
    package internal(set) var isUpdatingDisplayName = false
    package internal(set) var displayNameChangedAt: Date?
    package internal(set) var displayNameAvailableAt: Date?
    package internal(set) var isUploadingAvatar = false
    package internal(set) var avatarNotice: String?
    package internal(set) var isAvatarNoticeError = false

    // MARK: 제보
    package var feedbackKind: FeedbackKind = .bug
    package var feedbackDraft = ""
    package internal(set) var isSendingFeedback = false
    package internal(set) var feedbackNotice: String?
    package internal(set) var feedbackList: [FeedbackReport] = []
    package internal(set) var feedbackState = MeLoadState()
    package internal(set) var feedbackReplyLatestAt: Date?
    /// 딥링크(`aingcheck://feedback/<id>`)나 알림이 가리킨 제보 — 목록에서 펼치고 강조한다.
    package internal(set) var focusedReportID: String?
    package internal(set) var isFeedbackVisible = false
    /// 이 계정이 '봤다'고 적어 둔 마지막 답장 시각(공용 suite, 계정별 키).
    package internal(set) var feedbackReplySeenAt: Date?

    // MARK: 설정
    package internal(set) var tokenUsagePublic = true
    package internal(set) var tokenUsagePublicLoaded = false
    package internal(set) var miniGamePublic = true
    package internal(set) var miniGamePublicLoaded = false
    package internal(set) var inviteCode: String?
    package internal(set) var inviteCodeLoaded = false
    package internal(set) var settingsNotice: String?
    package internal(set) var pushAuthorization: MePushAuthorization = .unknown
    /// 저장 중인 알림 종류 값(낙관 표시). nil 이면 세션이 아는 서버값을 그린다.
    package internal(set) var pushPrefsPending: PushPrefs?
    package internal(set) var pushPrefsNotice: String?
    package internal(set) var isSigningOut = false

    /// 루트 화면이 낡았다고 보는 초.
    package nonisolated static let staleSeconds: TimeInterval = 60
    /// 내 제보 목록 상한(맥 `feedbackListLimit` 과 같은 규모).
    package nonisolated static let feedbackListLimit = 50

    @ObservationIgnored var serials: [String: Int] = [:]
    @ObservationIgnored var inflight: [Task<Void, Never>] = []
    /// 공개 설정 저장이 떠 있는 칸("token" · "minigame") — 늦게 온 GET 이 방금 바꾼 스위치를 되돌리지 않게.
    @ObservationIgnored var savingPrivacyKeys: Set<String> = []

    package init(context: MobileContext) {
        self.context = context
    }

    // MARK: - 자리 API

    package func appDidBecomeActive() {
        guard isTabVisible else { return }
        refreshRootIfStale()
    }

    package func appDidEnterBackground() {}

    package func reset() {
        for task in inflight { task.cancel() }
        inflight.removeAll()
        for key in serials.keys { serials[key, default: 0] &+= 1 }
        displayName = nil
        avatarURL = nil
        centerServerValue = nil
        headerState = MeLoadState()
        heatmap = .empty
        retro = nil
        dailyGrid = .empty
        tokenGrid = .empty
        showsTokenGrid = true
        recordsState = MeLoadState()
        recordsWeekKey = nil
        shopCharacters = []
        ownedCharacterIDs = [MeCharacterCards.aingID]
        shopState = MeLoadState()
        shopSelection = nil
        shopNotice = nil
        purchasingID = nil
        equippedServerID = nil
        equippedLoaded = false
        savingCharacterID = nil
        characterNotice = nil
        isCharacterNoticeError = false
        displayNameDraft = ""
        isProfileVisible = false
        displayNameNotice = nil
        isDisplayNameNoticeError = false
        isUpdatingDisplayName = false
        displayNameChangedAt = nil
        displayNameAvailableAt = nil
        isUploadingAvatar = false
        avatarNotice = nil
        isAvatarNoticeError = false
        feedbackKind = .bug
        feedbackDraft = ""
        isSendingFeedback = false
        feedbackNotice = nil
        feedbackList = []
        feedbackState = MeLoadState()
        feedbackReplyLatestAt = nil
        feedbackReplySeenAt = nil
        focusedReportID = nil
        tokenUsagePublic = true
        tokenUsagePublicLoaded = false
        miniGamePublic = true
        miniGamePublicLoaded = false
        inviteCode = nil
        inviteCodeLoaded = false
        settingsNotice = nil
        pushPrefsPending = nil
        pushPrefsNotice = nil
        isSigningOut = false
        savingPrivacyKeys.removeAll()
    }

    /// 안 본 제보 답장이 있으면 1.
    package var badgeCount: Int { hasUnseenFeedbackReply ? 1 : 0 }

    // MARK: - 화면 사건

    package func tabDidAppear() {
        isTabVisible = true
        refreshRootIfStale()
    }

    package func tabDidDisappear() {
        isTabVisible = false
    }

    /// 딥링크(`aingcheck://me` · `me/shop` · `me/settings` · `feedback[/<id>]`). 라우터가 이미 경로를 비웠다 — 하위 화면을 한 칸 쌓는다.
    package func open(_ route: AingRoute) {
        switch route {
        case .me:
            context.router.popToRoot(.me)
        case .shop:
            context.router.push(MeDestination.shop, on: .me)
        case .settings:
            context.router.push(MeDestination.settings, on: .me)
        case .feedback(let reportID):
            focusedReportID = reportID
            context.router.push(MeDestination.feedback, on: .me)
        default:
            break
        }
    }

    /// 루트(머리·루비·착용 캐릭터·기록·답장 배지)가 낡았으면 다시 읽는다.
    package func refreshRootIfStale() {
        guard context.session.isSignedIn else { return }
        loadFeedbackReplySeenStamp()
        if isStale(headerState) { launch { [weak self] in await self?.loadHeader() } }
        if isStale(shopState) { launch { [weak self] in await self?.loadShop() } }
        if !equippedLoaded || isStale(shopState) { launch { [weak self] in await self?.loadEquippedCharacter() } }
        if isStale(recordsState) { launch { [weak self] in await self?.loadRecords() } }
        launch { [weak self] in await self?.loadFeedbackReplyLatest() }
    }

    /// 당겨서 새로고침(루트): 신선도와 무관하게 전부.
    package func refreshRoot() async {
        guard context.session.isSignedIn else { return }
        async let header: Void = loadHeader()
        async let shop: Void = loadShop()
        async let equipped: Void = loadEquippedCharacter()
        async let records: Void = loadRecords()
        async let reply: Void = loadFeedbackReplyLatest()
        _ = await (header, shop, equipped, records, reply)
    }

    // MARK: - 머리

    package var teamName: String? { context.session.profile?.teamName }
    package var rubyBalance: Int? { context.gomokuHost.rubyBalance }
    package var myUserID: String? { context.session.userID }

    /// 이름·사진(한 GET) + 센터(코어 별도 GET). 둘은 독립 실패다.
    package func loadHeader() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("header")
        let generation = context.generation
        headerState.isLoading = true
        headerState.hasFailed = false
        defer { if isCurrent("header", serial) { headerState.isLoading = false } }
        let service = context.service
        do {
            let card = try await context.withMobileSessionRetry { session in
                try await service.fetchMyProfileCard(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, isCurrent("header", serial) else { return }
            let name = card?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = (name?.isEmpty == false) ? name : nil
            // 편집 화면을 먼저 열었으면(머리가 늦게 옴) 빈 입력을 지금 이름으로 채운다 — 사용자가 치기 시작했으면 건드리지 않는다.
            if isProfileVisible, displayNameDraft.isEmpty, !isUpdatingDisplayName, let displayName { displayNameDraft = displayName }
            avatarURL = card?.avatarUrl.flatMap { URL(string: $0) }
            // 센터는 독립 실패 — 못 읽으면 지난 값을 둔다(모르는 것을 "미지정"으로 단정하지 않는다).
            let center = await attempt { session in
                try await service.fetchMyCenter(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, isCurrent("header", serial) else { return }
            if case .success(let value) = center { centerServerValue = value }
            headerState.hasLoaded = true
            headerState.loadedAt = context.clock.now()
        } catch {
            guard generation == context.generation, isCurrent("header", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            headerState.hasFailed = true
        }
    }

    // MARK: - 내부 도우미(확장 파일이 같이 쓴다)

    func isStale(_ state: MeLoadState) -> Bool {
        guard !state.isLoading else { return false }
        guard let loadedAt = state.loadedAt, !state.hasFailed else { return true }
        return context.clock.now().timeIntervalSince(loadedAt) >= Self.staleSeconds
    }

    func nextSerial(_ key: String) -> Int {
        serials[key, default: 0] &+= 1
        return serials[key, default: 0]
    }

    func isCurrent(_ key: String, _ serial: Int) -> Bool {
        serials[key, default: 0] == serial
    }

    /// 401 재시도를 지난 호출을 `Result` 로(`try?` 는 옵셔널 결과를 납작하게 접어 "서버가 nil 이라고 했다"와 "실패했다"를 못 가른다).
    func attempt<T>(_ operation: (SupabaseSession) async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await context.withMobileSessionRetry(operation))
        } catch {
            return .failure(error)
        }
    }

    func launch(_ body: @escaping @MainActor () async -> Void) {
        inflight.removeAll { $0.isCancelled }
        let task = Task { @MainActor in await body() }
        inflight.append(task)
        if inflight.count > 24 { inflight.removeFirst(inflight.count - 24) }
    }
}
