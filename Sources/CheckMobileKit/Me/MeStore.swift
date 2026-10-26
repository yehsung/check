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
    /// 설정 → 차단한 사람(앱스토어 심사 지침 1.2). 목록·해제는 메시지 스토어가 쥔다(차단은 메시지 관계다).
    case blocked
    /// 잔디 상세(칸을 탭하면 그 날 실제 값). 연관값은 **처음 색으로 볼 축** — 누른 잔디의 축으로 연다.
    /// 딥링크(`AingRoute`)는 두지 않는다 — `.characters`·`.profile`·`.blocked` 처럼 push 만 하는 화면이다(URL 로 열 이유가 없다).
    case grass(ContributionAxis)
}

/// 한 덩어리(머리·기록·상점…)의 불러오기 상태 — 순위 탭과 같은 뜻의 세 깃발 + 마지막 성공 시각.
package typealias MeLoadState = RankingsLoadState

/// 나 탭 스토어(SPEC-ios §3.6) — 프로필 머리 · 루비 · 기록(회고·잔디·리듬) · 캐릭터(상점·고르기) · 프로필(사진·별명) · 제보 · 설정.
///
/// 수명(기반 자리 API): `init(context:)` 네트워크 없음 · `appDidBecomeActive()` 탭이 보이면 낡은 것만 다시 읽고, 탭이 안 보여도
/// AI 리밋 · 주간 보상 · 도전 미션 셋은 읽는다(위젯 · 탭 막대 배지의 재료다) · `appDidEnterBackground()` ·
/// `reset()` 계정에 묶인 값 전부 비움 · `badgeCount` = 안 본 제보 답장이 있으면 1(나 탭 **안**의 제보 줄에 점으로 보인다 —
/// 탭 막대의 나 탭 배지는 이 값이 아니라 `missionClaimableCount`(받을 보상 수)다).
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

    /// AI 구독 리밋(v0.3.45 — **토큰 축과 다른 새 축**). 자기 상태·자기 가드를 가진 작은 스토어다
    /// (`MeAILimitsStore.swift` 머리말: 한 `recordsState` 를 공유하면 "토큰 조회가 실패하면 리밋도 사라진다"가 된다).
    @ObservationIgnored package let aiLimits: AILimitsStore

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

    // MARK: 기록 — 공유 Codex 계정 비율(v0.3.36)
    /// 서버 일별 **계정 버킷**을 내 몫으로 줄이는 비율. nil = 아직 한 번도 못 쟀다(= 1.0, 이 수리 전 동작).
    ///
    /// 왜 폰에 이 값이 필요한가: 폰 잔디의 Codex 칸은 서버 계정 버킷에서 나오는데, 그 버킷은 **그룹 전체의 하루
    /// 사용량**이다. 비율을 안 곱하면 공유 그룹 11명의 잔디가 '계정의 잔디'가 된다(2026-09-22 실측 오차 1.05~19.15배).
    /// 맥은 `WorkTimerStoreInsights` 가 같은 비율을 이미 곱하고 있었고, 폰에만 빠져 있었다.
    ///
    /// 실패·취소·옛 RPC 에서는 **이 값을 지키는 것**이 답이다(맥 `MyTokenRowOutcome.keep` 과 같은 규약) —
    /// 1.0 으로 되돌리면 정확히 그리던 공유 사용자의 잔디가 실패 한 번에 최대 19배로 되부푼다.
    @ObservationIgnored package internal(set) var tokenShareRatio: Double?
    /// 마지막으로 **끝난** 보드 조회 시각(300초 스로틀 — 맥 `loadMyTokenRowIfDue` 와 같은 성격). 영속하지 않는다.
    /// 보내기 **전**이 아니라 끝난 뒤에 찍는다: 겹친 새로고침에서 응답이 버려졌는데 도장만 남으면 그 사이 공유
    /// 사용자의 잔디가 300초 넘게 '계정 전체'(최대 19배)로 굳는다.
    @ObservationIgnored package internal(set) var lastTokenBoardFetchAt: Date?
    /// 보드 왕복이 떠 있는가. 난사(겹친 [당겨서 새로고침])를 막는 자리는 **도장이 아니라 이 플래그**다 —
    /// 도장은 '다음 시도까지의 간격'이고 이것은 '지금 떠 있는 요청'이라, 하나로 겸하면 둘 중 하나가 늘 틀린다.
    @ObservationIgnored package internal(set) var isFetchingTokenBoard = false

    // MARK: 캐릭터 · 상점
    package internal(set) var shopCharacters: [ShopCharacterRow] = []
    package internal(set) var ownedCharacterIDs: Set<String> = [MeCharacterCards.aingID]
    package internal(set) var shopState = MeLoadState()
    package internal(set) var shopSelection: String?
    package internal(set) var shopNotice: String?
    /// 상점에서 마지막으로 누른 뽑기 전용 타일(황금 아잉이). 안내 줄(`shopBarDetail`)이 **읽을 때** 문장을 만든다 —
    /// 누를 때 만들어 두면 상점이 아직 안 읽힌 순간의 "뽑기로만"이 교환값(조각 20)을 안 뒤에도 남는다(시뮬레이터 실측).
    package internal(set) var shopGachaHintID: String?
    /// 상점에서 마지막으로 누른 **생일 선물 전용** 잠긴 칸(케이크 아잉이 — v0.3.66). 고른 것(`shopSelection`)이 아니다 — 살 수 없다.
    /// 아래 막대가 이 값으로 그 칸 이름과 얻는 길(`CakeGiftText.lockedHint`)만 말하고 사기 단추를 세우지 않는다.
    package internal(set) var shopGiftHintID: String?
    package internal(set) var purchasingID: String?
    /// 상점 RPC(`shop_state`·`buy_character`)에 싣는 능력 번호의 **재료**: 이 번들에 초상이 있는 캐릭터 id.
    ///
    /// ★ **숫자를 적는 자리가 아니다**(B16). `fetchShopState`·`buyCharacter` 는 맥과 폰이 공유하므로(CheckCore)
    ///   폰이 1 을 보내면 서버는 "너는 robot 을 그릴 수 있다"로 읽고 카드를 내려 준다. 폰은 모르는 id 를
    ///   아잉으로 접으니 그 카드는 **아잉 그림**으로 떠 "아잉을 또 파네"가 되고, 사면 100 루비가 빠진 채
    ///   착용해도 변화가 없다(mapC §7 ③④ 실측). 그래서 `AingCharacterArt.knownIDs`(번들 초상이 있는 id)가 답이다 —
    ///   초상이 폰 번들에 들어오고 그 목록이 갱신되는 날 이 값이 저절로 1 이 된다.
    ///
    /// **왜 `var` 인가**(테스트 이음새): 번들은 지금 한 값만 가진다(robot 없음). 그 상태로는 1 쪽 분기가 한 줄도
    /// 돌지 않아 호출부가 무엇을 넘기든 스위트가 모른다 — 가짜 명단을 꽂아 `loadShop`·`confirmPurchase` 의
    /// 진짜 경로를 양쪽 분기로 돌린다. 프로덕션에서 이 값을 쓰는 곳은 없다.
    @ObservationIgnored package var drawableCharacterIDs: [String] = AingCharacterArt.knownIDs
    /// 서버 착용값(`profiles.character`, 원문). nil = 기본(아잉) 또는 아직 모름(`equippedLoaded` 로 가른다).
    package internal(set) var equippedServerID: String?
    package internal(set) var equippedLoaded = false
    /// 마지막 착용값 조회가 실패로 끝났다(오프라인·5xx·행 없음). 요약이 '불러오는 중…'에 머물지 않게 한다.
    package internal(set) var equippedLoadFailed = false
    package internal(set) var savingCharacterID: String?
    package internal(set) var characterNotice: String?
    package internal(set) var isCharacterNoticeError = false

    // MARK: 캐릭터 뽑기 (v0.3.54 · 폰 1.0.8 — MeStoreGacha.swift)
    /// 서버 `shop_state.gacha`(1회 값 · 내 조각 · 확률표 · 교환값). **nil = 서버가 안 줬다**(옛 서버 · db push 전 · 2 를 못 보내는
    /// 빌드) — 뽑기 화면을 통째로 숨긴다. 값은 서버 응답으로만 바꾼다(클라가 조각을 스스로 더하거나 빼지 않는다).
    package internal(set) var gachaInfo: GachaInfo?
    /// 뽑기 요청이 떠 있다 — 버튼이 잠기고, 두 번 눌러도 요청은 하나다.
    package internal(set) var isPulling = false
    /// 마지막 뽑기 결과(결과 연출 · 상점 화면을 떠나면 비운다).
    package internal(set) var lastGachaResult: GachaPullResult?
    /// 결과가 새로 설 때마다 오른다 — 같은 캐릭터가 연달아 나와도 화면이 연출을 다시 튼다.
    package internal(set) var gachaRevealSerial = 0
    /// 뽑기 카드의 한 줄(실패·거절). 결과는 연출이 말하므로 여기 쓰지 않는다.
    package internal(set) var gachaNotice: String?
    package internal(set) var isGachaNoticeError = false
    /// 조각 교환이 떠 있는 캐릭터(그 줄만 스피너 · 나머지 줄은 잠긴다).
    package internal(set) var exchangingID: String?
    /// 교환 시트의 한 줄(교환 완료 · 거절 · 실패).
    package internal(set) var exchangeNotice: String?
    package internal(set) var isExchangeNoticeError = false
    /// 사용자 동작 한 번 = request_id 하나(결과를 모르는 실패 뒤 다시 누르면 같은 id — 서버가 처음 결과를 `replayed` 로 돌려준다).
    @ObservationIgnored package internal(set) var gachaRequestIDs = GachaRequestIDs()

    // MARK: 생일 선물 — 케이크 아잉이 (v0.3.66 · 폰 1.0.14 — MeStoreCakeGift.swift)
    /// 서버가 말한 **열린** 생일 선물(`character_gift_pending`). nil = 없음이거나 아직 모름 — 못 읽었으면 지난 값을 둔다.
    /// 이 값이 있고 시트가 닫혀 있으면 나 탭에 '다시 열기' 줄이 선다(수령할 때까지).
    package internal(set) var cakeGift: CharacterGiftOffer?
    /// 떠 있는 축하 시트(nil = 닫힘). 탭 막대 위에서 띄운다(`MobileTabsView`).
    package internal(set) var cakeGiftSheet: MeCakeGiftSheet?
    /// 시트가 **실제로 화면에 서 있는가**(시트 뷰의 onAppear/onDisappear 가 적는다). 스토어가 시트를 세워도 다른 시트가 떠 있으면
    /// SwiftUI 가 조용히 못 띄운다 — 탭 막대가 이 값으로 그 경우를 가려 닫은 것으로 친다(`MobileTabsView`).
    package internal(set) var cakeGiftSheetOnScreen = false
    /// 마지막으로 선물을 **물으러 떠난** 시각(10분 스로틀 — `cakeGiftCheckInterval`). 계정이 바뀌면 비운다.
    @ObservationIgnored package internal(set) var cakeGiftCheckedAt: Date?
    @ObservationIgnored var cakeGiftLoading = false
    /// 이 실행에서 **실제로 화면에 선**(시트 뷰의 onAppear) 선물 id — **실행당 한 번**은 이 기록으로 센다. 스토어가 시트를 세웠어도
    /// 화면에 못 섰으면(다른 시트 · 대국 화면) 쓰지 않은 것이다. 로그아웃(`reset`)에도 비우지 않는다(같은 실행에서 같은 선물을 두 번 띄우지 않는다).
    @ObservationIgnored package internal(set) var cakeGiftAutoShownIDs: Set<String> = []
    /// '다시 열기' 줄의 [고르기]가 서버에 다시 묻는 중(단추가 돈다 · 겹쳐 누르기 막기).
    package internal(set) var cakeGiftReopening = false

    // MARK: 이번 주 근무 보상 (v0.3.55 · 폰 1.0.8(19) — MeStoreWeeklyWork.swift)
    /// 서버 `weekly_work_status()` 의 마지막 **그릴 만한** 응답(CheckCore 모델 — 맥과 한 벌). nil = 아직 모른다(못 읽었으면 지난 값을 둔다).
    package internal(set) var weeklyWork: WeeklyWorkStatus?
    package internal(set) var weeklyWorkState = MeLoadState()
    /// 서버에 함수가 있다. 없으면(404 · PGRST202 — db push 전) 카드를 접는다. 다음 조회가 다시 묻는다(스로틀 60초).
    package internal(set) var weeklyWorkAvailable = true
    /// '받았어요 +N' 한 줄. 나 탭을 본 뒤 떠나면 걷힌다(`tabDidDisappear`).
    package internal(set) var weeklyGrantNotice: WeeklyWorkGrantNotice?
    /// 새 지급을 알릴 때마다 오른다 — 카드가 이 값으로 성공 햅틱을 낸다.
    package internal(set) var weeklyGrantSerial = 0
    /// 지금 알림을 사용자가 나 탭에서 봤다(떠날 때 걷는다). 안 본 알림은 남겨 두어 다음에 열 때 보이게 한다.
    @ObservationIgnored var weeklyGrantNoticeSeen = false

    // MARK: 도전 미션 · 받기 (v0.3.58 서버 · 맥 0.3.58 — MeStoreAchievements.swift)
    /// 서버 `achievements_status()` · `achievement_claim()` 의 마지막 응답(CheckCore 모델 — 맥과 한 벌).
    /// nil = 아직 모른다(못 읽었으면 **지난 값을 그대로 둔다**). 여기에 넣는 자리는 `applyAchievementStatus` 하나이고,
    /// 거기서 `merged(over:)` 를 거친다 — **받음은 되돌아가지 않는다**.
    package internal(set) var achievements: AchievementStatus?
    package internal(set) var achievementsState = MeLoadState()
    /// 서버에 함수가 있다. 없으면(404 · PGRST202 — db push 전) 절을 접는다. 스로틀 간격 뒤 조회가 다시 묻는다(60초).
    package internal(set) var achievementsAvailable = true
    /// 떠 있는 받기(미션 키 · 전부 받기는 `MeStore.achievementClaimAllSlot`) — **같은 줄을 두 번 받지 않게** 하는 자리다.
    package internal(set) var achievementClaimsInFlight: Set<String> = []
    /// 마지막 받기가 실패한 키. 실패는 **그 줄 안**에서 말한다(`MeText.claimFailed`) — 절 위 안내줄에 띄우지 않는다
    /// (맥이 검토에서 버린 방식: 안내줄은 줄을 밀고, 아래쪽 줄을 누른 사람에겐 스크롤 밖이라 안 보였다).
    package internal(set) var achievementClaimFailedKeys: Set<String> = []
    /// 이번 주 근무 받기가 떠 있다(두 번 눌러도 요청 하나) · 마지막 주간 받기가 실패했다(주간 줄 안에서 말한다).
    package internal(set) var weeklyClaimInFlight = false
    package internal(set) var weeklyClaimFailed = false
    /// 줄 자리(`MeClaimBurst.achievementTarget(series:)` · `MeClaimBurst.weeklyTarget`) → 받기 연출.
    /// 화면이 아니라 스토어가 "방금 받았다"를 쥔다 — 줄은 계열이 다음 단계로 바뀌며 새로 그려지기 때문이다(맥과 같은 이유).
    package internal(set) var missionClaimBursts: [String: MeClaimBurst] = [:]
    /// 받기 연출이 설 때마다 오른다 — 화면이 이 값으로 성공 햅틱을 내고, 같은 줄을 또 받아도 연출을 처음부터 다시 튼다.
    package internal(set) var missionClaimBurstSerial = 0

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

    // MARK: 상태메시지 (v0.3.51 — MeStoreStatusMessage.swift)
    /// 서버값 미러(`profiles.status_message`). nil = 없음이거나 아직 모름 — `statusMessageLoaded` 가 가른다.
    package internal(set) var statusMessage: String?
    package internal(set) var statusMessageLoaded = false
    package var statusMessageDraft = ""
    package internal(set) var isUpdatingStatusMessage = false
    package internal(set) var statusMessageNotice: String?
    package internal(set) var isStatusMessageNoticeError = false

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
    /// 딥링크·알림이 제보를 가리킬 때마다 오른다(같은 id 여도). 제보 화면이 **이미 떠 있으면** 라우터의 [제보]→[]→[제보] 를 SwiftUI 가
    /// 같은 화면으로 봐 onAppear 가 없고, 목록도 같으면 onChange(목록)도 없다 — 화면은 이 값을 보고 펼치고 스크롤한다(통합 검증 A1·A4).
    package internal(set) var feedbackFocusSerial = 0
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
    /// 설정 조회 세 칸의 마지막 실패(칸마다 독립). 한 번이라도 읽었으면(…Loaded) 화면은 지난 값을 그대로 둔다.
    package internal(set) var tokenUsagePublicLoadFailed = false
    package internal(set) var miniGamePublicLoadFailed = false
    package internal(set) var inviteCodeLoadFailed = false
    package internal(set) var isLoadingSettings = false
    package internal(set) var settingsNotice: String?
    package internal(set) var isSigningOut = false

    // MARK: 계정 삭제 (설정 → 시트)
    /// 시트의 비밀번호 입력(재인증용). 시트가 닫히면 비운다 — 다음에 열 때 앞 입력이 남지 않게.
    package var accountDeletionPassword = ""
    package internal(set) var isDeletingAccount = false
    /// 시트 안 한 줄(실패 이유 — 로그인 상태는 그대로다).
    package internal(set) var accountDeletionNotice: String?

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
        aiLimits = AILimitsStore(context: context)
    }

    // MARK: - 자리 API

    package func appDidBecomeActive() {
        // AI 리밋은 **탭이 보이지 않아도** 받는다 — 이 값의 소비자에 위젯이 있어서, 나 탭을 한 번도 열지 않는
        // 사용자의 리밋 위젯이 영원히 비는 것을 막는다(GET 하나다). 로그인 직후에도 여기로 들어온다
        // (`MobileAppModel.sessionDidSignIn` → scene 이 active 면 `activateStores()`).
        aiLimits.refreshIfStale()
        // 주간 보상도 탭이 안 보여도 받는다(앞에 올 때마다 · 60초 스로틀) — 정산 결과의 루비가 게임 탭·상점 알약에도 바로 선다.
        refreshWeeklyWorkIfStale()
        // 도전 미션도 주간 보상과 **똑같이** 탭이 안 보여도 받는다(앞에 올 때마다 · 같은 60초 스로틀) — 이제 이 값이
        // **탭 막대 배지**(받을 보상 수 = `missionClaimableCount`)라서다. "이미 아는 것만 다시 읽는다"로 걸어 두면
        // `achievements` 는 메모리 값이라 **콜드 스타트엔 언제나 nil** 이고, 배지가 꼭 필요한 사람(나 탭에 아직 안 가 본
        // 사람)에게만 영영 안 선다. 받기 전에 루비가 안 움직이는 것은 여전히 사실이지만, 이제 화면 밖에서 알아 둘 값이
        // **배지 숫자**로 생겼다.
        refreshAchievementsIfStale()
        // 생일 선물(v0.3.66)도 탭과 무관하게 앞에 올 때마다 — 단 **10분에 한 번 이하**(`cakeGiftCheckInterval`). 열린 선물이면
        // 축하 시트가 실행당 한 번 스스로 뜬다(어느 탭에 있든 — 시트는 탭 막대 위에서 띄운다). 대국·관전 화면 때문에 미뤄 둔
        // 선물은 묻지 않고도 이미 안다 — 앞에 온 지금이 그 '다음 기회'다(`presentCakeGiftIfDue`).
        presentCakeGiftIfDue()
        refreshCakeGiftIfStale()
        guard isTabVisible else { return }
        refreshRootIfStale()
    }

    package func appDidEnterBackground() {}

    package func reset() {
        for task in inflight { task.cancel() }
        inflight.removeAll()
        for key in serials.keys { serials[key, default: 0] &+= 1 }
        aiLimits.reset()
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
        // 계정에 묶인 값이다 — 안 비우면 계정을 바꾼 뒤 **앞 사람의 비율로 내 잔디가 깎인다**(부풀리는 것과 달리
        // 아무 경고 없이 어두워져 더 안 보인다). defaults 키는 계정별이라 저장본은 그대로 둬도 안전하다.
        tokenShareRatio = nil
        lastTokenBoardFetchAt = nil
        shopCharacters = []
        ownedCharacterIDs = [MeCharacterCards.aingID]
        shopState = MeLoadState()
        shopSelection = nil
        shopNotice = nil
        shopGachaHintID = nil
        shopGiftHintID = nil
        purchasingID = nil
        equippedServerID = nil
        equippedLoaded = false
        equippedLoadFailed = false
        savingCharacterID = nil
        characterNotice = nil
        isCharacterNoticeError = false
        // 뽑기도 계정에 묶인다 — 안 비우면 앞 사람의 조각 수·결과 연출이 다음 계정 화면에 서고, 앞 사람의 request_id 로
        // 다음 사람이 뽑는다(서버는 (사용자, id) 로 묶으니 깎이진 않지만, 결과를 모르는 채 쥔 id 가 남는다).
        gachaInfo = nil
        isPulling = false
        lastGachaResult = nil
        gachaRevealSerial = 0
        gachaNotice = nil
        isGachaNoticeError = false
        exchangingID = nil
        exchangeNotice = nil
        isExchangeNoticeError = false
        gachaRequestIDs.reset()
        // 생일 선물도 계정에 묶인다 — 안 비우면 다음 계정 나 탭에 앞 사람의 '다시 열기' 줄이 서고, 그 시트에서 앞 사람의 선물 id 로
        // 수령을 부른다(서버는 not_found 로 막지만 화면이 거짓말을 한다). 스로틀 도장도 비워 새 계정은 곧바로 묻는다.
        // 스스로 띄운 기록(`cakeGiftAutoShownIDs`)은 **실행** 단위라 그대로 둔다.
        cakeGift = nil
        cakeGiftSheet = nil
        cakeGiftSheetOnScreen = false
        cakeGiftCheckedAt = nil
        cakeGiftLoading = false
        cakeGiftReopening = false
        // 주간 보상도 계정에 묶인다 — 안 비우면 다음 계정 카드에 앞 사람의 근무 시간·받은 칸·'받았어요'가 선다.
        // 계정별 '본 칸' 저장값(defaults)은 키가 계정별이라 그대로 둔다.
        weeklyWork = nil
        weeklyWorkState = MeLoadState()
        weeklyWorkAvailable = true
        weeklyGrantNotice = nil
        weeklyGrantSerial = 0
        weeklyGrantNoticeSeen = false
        // 도전 미션 · 받기도 계정에 묶인다 — 안 비우면 다음 계정 줄에 앞 사람의 달성과 [받기]가 서고(누르면 서버는 아무것도 안 준다),
        // 떠 있던 받기 자리가 남아 새 계정의 첫 받기가 "이미 떠 있음"으로 막힌다.
        achievements = nil
        achievementsState = MeLoadState()
        achievementsAvailable = true
        achievementClaimsInFlight.removeAll()
        achievementClaimFailedKeys.removeAll()
        weeklyClaimInFlight = false
        weeklyClaimFailed = false
        missionClaimBursts = [:]
        missionClaimBurstSerial = 0
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
        // 상태메시지도 계정에 묶인다 — 남기면 다음 계정의 편집 화면에 앞 사람의 문장이 '내 값'으로 서고 [저장]이 그걸 올린다.
        statusMessage = nil
        statusMessageLoaded = false
        statusMessageDraft = ""
        isUpdatingStatusMessage = false
        statusMessageNotice = nil
        isStatusMessageNoticeError = false
        feedbackKind = .bug
        feedbackDraft = ""
        isSendingFeedback = false
        feedbackNotice = nil
        feedbackList = []
        feedbackState = MeLoadState()
        feedbackReplyLatestAt = nil
        feedbackReplySeenAt = nil
        focusedReportID = nil
        feedbackFocusSerial = 0
        tokenUsagePublic = true
        tokenUsagePublicLoaded = false
        miniGamePublic = true
        miniGamePublicLoaded = false
        inviteCode = nil
        inviteCodeLoaded = false
        tokenUsagePublicLoadFailed = false
        miniGamePublicLoadFailed = false
        inviteCodeLoadFailed = false
        isLoadingSettings = false
        settingsNotice = nil
        isSigningOut = false
        accountDeletionPassword = ""
        isDeletingAccount = false
        accountDeletionNotice = nil
        savingPrivacyKeys.removeAll()
    }

    /// 안 본 제보 답장이 있으면 1.
    package var badgeCount: Int { hasUnseenFeedbackReply ? 1 : 0 }

    // MARK: - 화면 사건

    package func tabDidAppear() {
        isTabVisible = true
        if weeklyGrantNotice != nil { weeklyGrantNoticeSeen = true }
        refreshRootIfStale()
    }

    package func tabDidDisappear() {
        isTabVisible = false
        weeklyTabDidDisappear()
        missionsTabDidDisappear()
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
            feedbackFocusSerial &+= 1
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
        refreshWeeklyWorkIfStale()
        // 도전 미션 조회는 나 탭 루트 새로고침에 얹는다(여기 · 당겨서 새로고침 · 탭이 보이는 채로 앱이 앞에 올 때 — 셋 다 이
        // 함수를 지난다). 탭이 **안** 보일 때도 주간 보상처럼 `appDidBecomeActive()` 가 따로 한 번 부른다(그 주석) —
        // 탭 막대 배지가 이 값이다. **새 타이머는 없다** — 스로틀도 다른 덩어리와 같은 60초다.
        refreshAchievementsIfStale()
        aiLimits.refreshIfStale()
    }

    /// **로그인 직후 한 번** 착용 캐릭터만 미리 받는다(`profiles.character` GET 하나 — 상점·기록은 건드리지 않는다).
    ///
    /// 나 탭을 아직 열지 않은 상태(설치 직후 · 로그아웃 후 재로그인 — 세션 스토어가 위젯 스냅숏을 지운다)에서는 지금·순위·게임·오목이
    /// 전부 아잉으로 서서 "나 = 착용 캐릭터"(§0)가 깨졌다(w15 검증 medium 3). 이미 알고 있으면 아무것도 하지 않는다.
    package func primeEquippedCharacter() {
        guard context.session.isSignedIn, !equippedLoaded else { return }
        launch { [weak self] in await self?.loadEquippedCharacter() }
    }

    /// 당겨서 새로고침(루트): 신선도와 무관하게 전부.
    package func refreshRoot() async {
        guard context.session.isSignedIn else { return }
        async let header: Void = loadHeader()
        async let shop: Void = loadShop()
        async let equipped: Void = loadEquippedCharacter()
        async let records: Void = loadRecords()
        async let reply: Void = loadFeedbackReplyLatest()
        async let limits: Void = aiLimits.load()
        async let weekly: Void = loadWeeklyWork()
        async let missions: Void = loadAchievements()
        _ = await (header, shop, equipped, records, reply, limits, weekly, missions)
    }

    // MARK: - 머리

    package var teamName: String? { context.session.profile?.teamName }
    package var rubyBalance: Int? { context.gomokuHost.rubyBalance }
    package var myUserID: String? { context.session.userID }

    /// 이름·사진(한 GET) + 센터(코어 별도 GET). 둘은 독립 실패다.
    ///
    /// 이름·사진은 **떠날 때 찍은 쓰기 표**가 그대로일 때만 옮긴다 — 이 GET 이 떠 있는 사이 별명 저장·사진 업로드가 성공했으면 응답은
    /// 그 전 값이라 방금 바꾼 이름·사진(캐시버스터 URL)을 되돌린다(rankme-verify R3·R5). 머리 순번을 올려 통째로 버리면 센터와
    /// '불러오는 중'이 갇히므로 칸 단위로 가른다.
    package func loadHeader() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("header")
        let generation = context.generation
        let nameStamp = writeStamp(Self.displayNameWriteKey)
        let avatarStamp = writeStamp(Self.avatarWriteKey)
        headerState.isLoading = true
        headerState.hasFailed = false
        defer { if isCurrent("header", serial) { headerState.isLoading = false } }
        let service = context.service
        do {
            let card = try await context.withMobileSessionRetry { session in
                try await service.fetchMyProfileCard(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, isCurrent("header", serial) else { return }
            if writeStamp(Self.displayNameWriteKey) == nameStamp {
                let name = card?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                displayName = (name?.isEmpty == false) ? name : nil
                // 편집 화면을 먼저 열었으면(머리가 늦게 옴) 빈 입력을 지금 이름으로 채운다 — 사용자가 치기 시작했으면 건드리지 않는다.
                if isProfileVisible, displayNameDraft.isEmpty, !isUpdatingDisplayName, let displayName { displayNameDraft = displayName }
            }
            if writeStamp(Self.avatarWriteKey) == avatarStamp {
                avatarURL = card?.avatarUrl.flatMap { URL(string: $0) }
            }
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

    nonisolated static let displayNameWriteKey = "write.displayName"
    nonisolated static let statusMessageWriteKey = "write.statusMessage"
    nonisolated static let avatarWriteKey = "write.avatar"
    /// 받기 응답을 **옮긴** 횟수(v0.3.58). 조회가 떠날 때 찍고, 도착했을 때 달라졌으면 그 조회는 받기 **전**의 서버를 말한다 —
    /// 그대로 덮으면 방금 받은 줄에 [받기]가 다시 선다(누르면 서버는 아무것도 안 주는 거짓 버튼이다). 그때는 응답을 버린다:
    /// 받기 응답이 이미 더 새 상태를 줬으니 다시 묻지 않아도 된다.
    nonisolated static let achievementClaimWriteKey = "write.achievementClaim"
    nonisolated static let weeklyClaimWriteKey = "write.weeklyClaim"

    /// 사용자가 이 칸을 서버에 **써서 성공한** 횟수. 조회가 떠날 때 찍고, 도착했을 때 달라졌으면 그 응답의 이 칸은 옛 값이다.
    func writeStamp(_ key: String) -> Int {
        serials[key, default: 0]
    }

    func noteLocalWrite(_ key: String) {
        serials[key, default: 0] &+= 1
    }

    /// 공개 설정 조회를 **떠날 때** 찍는 표. 그 칸 저장이 떠 있었으면 nil — 서버가 저장 전에 읽었을 수 있어 응답을 믿지 않는다.
    func privacyReadStamp(_ key: String) -> Int? {
        isSavingPrivacy(key) ? nil : serials["privacy.\(key)", default: 0]
    }

    /// 도착한 공개 설정 값을 스위치에 옮겨도 되는가: 떠날 때 저장이 없었고 · 그 사이 사용자가 스위치를 바꾸지 않았다.
    /// (지금 저장 중이라면 떠난 뒤에 바꾼 것이므로 순번이 이미 다르다 — 따로 보지 않는다.)
    /// '저장 중'만 보면 저장이 **끝난 뒤** 도착한 옛 GET 이 방금 끈 스위치를 켠다(rankme-verify R1 — 서버는 비공개인데 화면은 공개).
    func canApplyPrivacyRead(_ key: String, stamp: Int?) -> Bool {
        guard let stamp else { return false }
        return serials["privacy.\(key)", default: 0] == stamp
    }

    func isSavingPrivacy(_ key: String) -> Bool {
        savingPrivacyKeys.contains(key)
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
