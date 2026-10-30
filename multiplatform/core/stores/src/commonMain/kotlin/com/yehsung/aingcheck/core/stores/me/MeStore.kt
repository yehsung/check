// 원본: Sources/CheckMobileKit/Me/MeStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchMyCenter
import com.yehsung.aingcheck.core.net.fetchMyProfileCard
import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.gacha.GachaInfo
import com.yehsung.aingcheck.core.rules.gacha.GachaPullResult
import com.yehsung.aingcheck.core.rules.gacha.GachaRequestIDs
import com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WeeklyRetro
import com.yehsung.aingcheck.core.rules.insights.WorkDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkStatus
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer
import com.yehsung.aingcheck.core.wire.models.FeedbackKind
import com.yehsung.aingcheck.core.wire.models.FeedbackReport
import com.yehsung.aingcheck.core.wire.models.ShopCharacterRow
import com.yehsung.aingcheck.core.rules.text.TextScalars
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlin.coroutines.CoroutineContext
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * 나 탭 스토어(SPEC-ios §3.6) — 프로필 머리 · 루비 · 기록(회고·잔디·리듬) · 캐릭터(상점·고르기·뽑기) · 생일 선물 · 이번 주 근무 ·
 * 일일·누적 미션 · 프로필(사진·별명·상태메시지) · 제보 · 설정 · AI 리밋(따로 [AILimitsStore]).
 *
 * 수명(기반 자리 API): 생성 네트워크 없음 · [appDidBecomeActive] 탭이 보이면 낡은 것만 다시 읽고, 탭이 안 보여도 AI 리밋 · 주간 보상 ·
 * 도전 미션 · 생일 선물은 읽는다(위젯 · 탭 막대 배지의 재료) · [reset] 계정에 묶인 값 전부 비움 · [badgeCount] = 안 본 제보 답장이면 1
 * (탭 막대의 나 탭 배지는 이 값이 아니라 `missionClaimableCount` — 받을 보상 수).
 *
 * 폰이 **하지 않는 것**(코드로 막혀 있다): 울트라 구매 · 지갑 동기화 · 집중 모드 PATCH(공개 설정 GET 의 focus_mode 는 읽고 버린다) ·
 * 앱 빌드 PATCH · 팀 상태 반영(진행 중 세션 시각만 읽는다) · 제보 진단 줄 · AI 리밋 쓰기.
 *
 * 늦은 응답 가드: 세대(로그아웃) · 덩어리별 요청 순번 · 쓰기 표(`write.*`) · 루비 미러 쓰기 횟수 · (기록) 주가 바뀌면 옛 계산 버림.
 *
 * 실행 규약(Swift `@MainActor` 자리): 공개 함수는 한 디스패처(앱 = 메인, 시험 = runTest)에서 부른다. 띄우는 일은 [parentScope] 를 따르는
 * SupervisorJob 위에서 돌고 [reset] 이 한꺼번에 끊는다. 띄운 일은 Swift `Task` 처럼 **다음 차례**에 돈다 — 즉시(immediate) 디스패처를 주지 마라
 * ('떠 있음' 을 띄우는 자리에서 먼저 적는 규약이 그 차례에 기댄다).
 */
@OptIn(ExperimentalUuidApi::class)
class MeStore(
    val context: MeContext,
    parentScope: CoroutineScope,
    /** K9 — 번들에 초상이 실린 캐릭터(상점 능력 번호의 재료). 조립(K11)은 ui `CharacterArt.drawableCharacterSource` 를 넘긴다. */
    drawableCharacters: DrawableCharacterSource,
    /** 기록 계산을 메인 밖에서 돌릴 자리(Swift `Task.detached`). 시험은 시험 디스패처를 넘긴다. */
    internal val computeContext: CoroutineContext = Dispatchers.Default,
    /** 뽑기·교환 request_id 재료(Swift `UUID()`). 시험이 고정한다 — 서버에는 소문자로 나간다. */
    internal val newRequestID: () -> String = { Uuid.random().toString() },
) {
    private val work: Job = SupervisorJob(parentScope.coroutineContext[Job])
    internal val scope: CoroutineScope = CoroutineScope(parentScope.coroutineContext + work)

    /** AI 구독 리밋(v0.3.45 — 토큰 축과 다른 새 축). 자기 상태·자기 가드를 가진 작은 스토어다(한 recordsState 를 공유하지 않는다). */
    val aiLimits: AILimitsStore = AILimitsStore(context, parentScope) { this }

    var isTabVisible by mutableStateOf(false)
        private set

    // MARK: 머리
    var displayName by mutableStateOf<String?>(null)
        internal set
    var avatarURL by mutableStateOf<SwiftURL?>(null)
        internal set

    /** 센터 **서버값**("seoul"). 화면은 센터 배지가 글자로 접는다. */
    var centerServerValue by mutableStateOf<String?>(null)
        internal set
    val headerState = MeLoadState()

    // MARK: 기록
    var heatmap by mutableStateOf(WorkRhythmHeatmap.empty)
        internal set
    var retro by mutableStateOf<WeeklyRetro?>(null)
        internal set
    var dailyGrid by mutableStateOf(WorkDailyGrid.empty)
        internal set
    var tokenGrid by mutableStateOf(TokenDailyGrid.empty)
        internal set

    /** 토큰 수집을 켠 사람만 토큰 잔디를 본다(맥 `tokenUsageCollect` 게이트). */
    var showsTokenGrid by mutableStateOf(true)
        internal set
    val recordsState = MeLoadState()
    internal var recordsWeekKey: String? = null

    /**
     * 지난주 회고 안내 배너를 지금 띄우는가(맥 `showsRetroBanner`, WorkTimerStore.swift 1130 @ db93317f — 주당 1회). 판정·소비는
     * MeStoreRetroBanner.kt(맥 WorkTimerStoreInsights.swift 207-261 이식)만 쓴다. **데스크톱 홈 전용** — 폰은 이 칸을 읽지 않는다.
     */
    var showsRetroBanner by mutableStateOf(false)
        internal set

    // MARK: 기록 — 공유 Codex 계정 비율(v0.3.36)
    /**
     * 서버 일별 **계정 버킷**을 내 몫으로 줄이는 비율. null = 아직 한 번도 못 쟀다(= 1.0).
     * 실패·취소·옛 RPC 에서는 **이 값을 지키는 것**이 답이다(1.0 으로 되돌리면 공유 사용자의 잔디가 최대 19배로 되부푼다).
     */
    internal var tokenShareRatio: Double? = null

    /** 마지막으로 **끝난** 보드 조회 시각(300초 스로틀). 보내기 전이 아니라 끝난 뒤에 찍는다. */
    internal var lastTokenBoardFetchAt: SwiftDate? = null

    /** 보드 왕복이 떠 있는가 — 난사를 막는 자리는 도장이 아니라 이 깃발이다. */
    internal var isFetchingTokenBoard = false

    // MARK: 캐릭터 · 상점
    var shopCharacters by mutableStateOf<List<ShopCharacterRow>>(emptyList())
        internal set
    var ownedCharacterIDs by mutableStateOf(setOf(MeCharacterCards.aingID))
        internal set
    val shopState = MeLoadState()
    var shopSelection by mutableStateOf<String?>(null)
        internal set
    var shopNotice by mutableStateOf<String?>(null)
        internal set

    /** 상점에서 마지막으로 누른 뽑기 전용 타일 — 안내 줄이 **읽을 때** 문장을 만든다(누를 때 만들면 교환값을 안 뒤에도 옛 문장이 남는다). */
    var shopGachaHintID by mutableStateOf<String?>(null)
        internal set

    /** 상점에서 마지막으로 누른 **생일 선물 전용** 잠긴 칸(케이크 아잉이 — 살 수 없다, 사기 단추를 세우지 않는다). */
    var shopGiftHintID by mutableStateOf<String?>(null)
        internal set
    var purchasingID by mutableStateOf<String?>(null)
        internal set

    /**
     * 상점 RPC(`shop_state`·`buy_character`·뽑기·선물)에 싣는 능력 번호의 **재료**: 이 번들에 초상이 있는 캐릭터 id.
     *
     * INV-MeStore-fe0bb349 이식: **숫자를 적는 자리가 아니다**(B16). 1 을 보내면 서버는 "너는 robot 을 그릴 수 있다"로 읽고 카드를
     *   내려 준다 — 그림이 없는 빌드는 모르는 id 를 아잉으로 접어 "아잉을 또 파네"가 되고, 사면 루비만 빠진다. 그래서 번들에 실제로
     *   실린 초상([DrawableCharacterSource] — Android 는 APK 초상 파일 목록)이 답이다. 초상이 들어오는 날 번호가 저절로 오른다.
     *
     * 시험 이음새: 가짜 명단을 꽂아 `loadShop`·`confirmPurchase` 의 진짜 경로를 양쪽 분기로 돌린다. 한 번 읽으면 실행 동안 같다(번들은 바뀌지 않는다)
     * — 빈 집합(읽기 실패)만은 쥐지 않고 다음 호출에서 다시 읽는다([drawableCharacterIDs]).
     */
    var drawableCharacters: DrawableCharacterSource = drawableCharacters
        set(value) {
            field = value
            resolvedDrawable = null
        }
    internal var resolvedDrawable: Set<String>? = null

    /** 서버 착용값(`profiles.character`, 원문). null = 기본(아잉) 또는 아직 모름([equippedLoaded] 로 가른다). */
    var equippedServerID by mutableStateOf<String?>(null)
        internal set
    var equippedLoaded by mutableStateOf(false)
        internal set

    /** 마지막 착용값 조회가 실패로 끝났다(요약이 '불러오는 중…'에 머물지 않게). */
    var equippedLoadFailed by mutableStateOf(false)
        internal set
    var savingCharacterID by mutableStateOf<String?>(null)
        internal set
    var characterNotice by mutableStateOf<String?>(null)
        internal set
    var isCharacterNoticeError by mutableStateOf(false)
        internal set

    // MARK: 캐릭터 뽑기 (v0.3.54 · 폰 1.0.8 — MeStoreGacha)
    /**
     * 서버 `shop_state.gacha`. **null = 서버가 안 줬다**(옛 서버 · db push 전 · 2 를 못 보내는 빌드) — 뽑기 화면을 통째로 숨긴다.
     * 값은 서버 응답으로만 바꾼다(클라가 조각을 스스로 더하거나 빼지 않는다).
     */
    var gachaInfo by mutableStateOf<GachaInfo?>(null)
        internal set

    /**
     * 서버 `shop_state.ultra_price`(울트라 1개 값 — Swift `ultraPrice`, WorkTimerStoreAuth.swift 624). null = 아직 모른다(지어내지 않는다 —
     * 울트라 구매 화면은 모르면 사지 않고 [loadShop] 을 다시 부른다). Compose 상태라 화면이 읽으면 값이 오는 순간 다시 그린다.
     * 계정에 묶인 값이 아니라 로그아웃에도 비우지 않는다(맥 signOut 도 그대로 둔다).
     */
    var ultraPrice by mutableStateOf<Long?>(null)
        internal set

    /** 뽑기 요청이 떠 있다 — 버튼이 잠기고, 두 번 눌러도 요청은 하나다. */
    var isPulling by mutableStateOf(false)
        internal set
    var lastGachaResult by mutableStateOf<GachaPullResult?>(null)
        internal set

    /** 결과가 새로 설 때마다 오른다(같은 캐릭터가 연달아 나와도 연출을 다시 튼다). */
    var gachaRevealSerial by mutableStateOf(0)
        internal set
    var gachaNotice by mutableStateOf<String?>(null)
        internal set
    var isGachaNoticeError by mutableStateOf(false)
        internal set
    var exchangingID by mutableStateOf<String?>(null)
        internal set
    var exchangeNotice by mutableStateOf<String?>(null)
        internal set
    var isExchangeNoticeError by mutableStateOf(false)
        internal set

    /** 사용자 동작 한 번 = request_id 하나(결과를 모르는 실패 뒤 다시 누르면 같은 id — 서버가 처음 결과를 `replayed` 로 준다). */
    internal val gachaRequestIDs = GachaRequestIDs()

    // MARK: 생일 선물 — 케이크 아잉이 (v0.3.66 · 폰 1.0.14 — MeStoreCakeGift)
    /** 서버가 말한 **열린** 생일 선물. null = 없음이거나 아직 모름 — 못 읽었으면 지난 값을 둔다. */
    var cakeGift by mutableStateOf<CharacterGiftOffer?>(null)
        internal set

    /** 떠 있는 축하 시트(null = 닫힘). */
    var cakeGiftSheet by mutableStateOf<MeCakeGiftSheet?>(null)
        internal set

    /** 시트가 **실제로 화면에 서 있는가**(시트 화면이 적는다). */
    var cakeGiftSheetOnScreen by mutableStateOf(false)
        internal set

    /** 마지막으로 선물을 **물으러 떠난** 시각(10분 스로틀). 계정이 바뀌면 비운다. */
    internal var cakeGiftCheckedAt: SwiftDate? = null
    internal var cakeGiftLoading = false

    /** 이 실행에서 **실제로 화면에 선** 선물 id — 실행당 한 번. 로그아웃에도 비우지 않는다. */
    internal var cakeGiftAutoShownIDs: Set<String> = emptySet()

    /** '다시 열기' 줄의 [고르기]가 서버에 다시 묻는 중. */
    var cakeGiftReopening by mutableStateOf(false)
        internal set

    // MARK: 이번 주 근무 보상 (v0.3.55 — MeStoreWeeklyWork)
    /** 서버 `weekly_work_status()` 의 마지막 **그릴 만한** 응답. null = 아직 모른다(못 읽었으면 지난 값을 둔다). */
    var weeklyWork by mutableStateOf<WeeklyWorkStatus?>(null)
        internal set
    val weeklyWorkState = MeLoadState()

    /** 서버에 함수가 있다. 없으면(404 · PGRST202) 카드를 접는다. 다음 조회가 다시 묻는다(스로틀 60초). */
    var weeklyWorkAvailable by mutableStateOf(true)
        internal set
    var weeklyGrantNotice by mutableStateOf<WeeklyWorkGrantNotice?>(null)
        internal set
    var weeklyGrantSerial by mutableStateOf(0)
        internal set
    internal var weeklyGrantNoticeSeen = false

    // MARK: 도전 미션 · 받기 (v0.3.58 — MeStoreAchievements)
    /**
     * 서버 `achievements_status()` · `achievement_claim()` 의 마지막 응답. null = 아직 모른다(못 읽었으면 **지난 값을 그대로 둔다**).
     * 넣는 자리는 `applyAchievementStatus` 하나이고, 거기서 `merged(previous)` 를 거친다 — **받음은 되돌아가지 않는다**.
     */
    var achievements by mutableStateOf<AchievementStatus?>(null)
        internal set
    val achievementsState = MeLoadState()
    var achievementsAvailable by mutableStateOf(true)
        internal set

    /** 떠 있는 받기(미션 키 · 전부 받기는 [ACHIEVEMENT_CLAIM_ALL_SLOT]) — 같은 줄을 두 번 받지 않게. */
    var achievementClaimsInFlight by mutableStateOf<Set<String>>(emptySet())
        internal set

    /** 마지막 받기가 실패한 키(실패는 **그 줄 안**에서 말한다). */
    var achievementClaimFailedKeys by mutableStateOf<Set<String>>(emptySet())
        internal set
    var weeklyClaimInFlight by mutableStateOf(false)
        internal set
    var weeklyClaimFailed by mutableStateOf(false)
        internal set

    // MARK: 일일 미션 (v0.3.64 — MeStoreAchievements)
    /** 서버에 일일 미션 **받기**가 있다. 404 · PGRST202 면 false — **일일 절만** 접는다. */
    var dailyMissionsAvailable by mutableStateOf(true)
        internal set

    /** 떠 있는 **일일** 받기. 누적과 **따로 센다**. */
    var dailyMissionClaimsInFlight by mutableStateOf<Set<String>>(emptySet())
        internal set

    /** 마지막 **일일** 받기가 실패한 키. 누적과 따로 둔다. */
    var dailyMissionClaimFailedKeys by mutableStateOf<Set<String>>(emptySet())
        internal set

    /** 하루가 끝난 것을 적어 둔 리셋 시각(응답의 `daily.reset_at_ms`). 이 **관찰 값**이 줄 · 배지를 다시 그린다. */
    var dailyMissionRolloverNoted by mutableStateOf<Long?>(null)
        internal set

    /** 서버 시계 − 이 폰 시계(밀리초). 일일 줄의 날짜 넘김 판정에만 쓴다(관찰 밖). */
    internal var achievementsServerClockOffsetMs: Long = 0

    /** 판이 끝났는데 그때 미션 조회가 떠 있었다 — 끝난 뒤 한 번 더 묻는다(깃발 하나라 +1건). */
    internal var achievementsRefetchAfterGame = false

    /** 줄 자리 → 받기 연출. 화면이 아니라 스토어가 "방금 받았다"를 쥔다. */
    var missionClaimBursts by mutableStateOf<Map<String, MeClaimBurst>>(emptyMap())
        internal set
    var missionClaimBurstSerial by mutableStateOf(0)
        internal set

    // MARK: 프로필 편집
    var displayNameDraft by mutableStateOf("")
    var isProfileVisible by mutableStateOf(false)
        internal set
    var displayNameNotice by mutableStateOf<String?>(null)
        internal set
    var isDisplayNameNoticeError by mutableStateOf(false)
        internal set
    var isUpdatingDisplayName by mutableStateOf(false)
        internal set
    var displayNameChangedAt by mutableStateOf<SwiftDate?>(null)
        internal set
    var displayNameAvailableAt by mutableStateOf<SwiftDate?>(null)
        internal set
    var isUploadingAvatar by mutableStateOf(false)
        internal set
    var avatarNotice by mutableStateOf<String?>(null)
        internal set
    var isAvatarNoticeError by mutableStateOf(false)
        internal set

    // MARK: 상태메시지 (v0.3.51 — MeStoreStatusMessage)
    var statusMessage by mutableStateOf<String?>(null)
        internal set
    var statusMessageLoaded by mutableStateOf(false)
        internal set
    var statusMessageDraft by mutableStateOf("")
    var isUpdatingStatusMessage by mutableStateOf(false)
        internal set
    var statusMessageNotice by mutableStateOf<String?>(null)
        internal set
    var isStatusMessageNoticeError by mutableStateOf(false)
        internal set

    // MARK: 제보
    var feedbackKind by mutableStateOf(FeedbackKind.bug)
    var feedbackDraft by mutableStateOf("")
    var isSendingFeedback by mutableStateOf(false)
        internal set
    var feedbackNotice by mutableStateOf<String?>(null)
        internal set
    var feedbackList by mutableStateOf<List<FeedbackReport>>(emptyList())
        internal set
    val feedbackState = MeLoadState()
    var feedbackReplyLatestAt by mutableStateOf<SwiftDate?>(null)
        internal set

    /** 딥링크·알림이 가리킨 제보 — 목록에서 펼치고 강조한다. */
    var focusedReportID by mutableStateOf<String?>(null)
        internal set

    /** 딥링크·알림이 제보를 가리킬 때마다 오른다(같은 id 여도 — 이미 떠 있는 화면이 이 값을 보고 펼친다). */
    var feedbackFocusSerial by mutableStateOf(0)
        internal set
    var isFeedbackVisible by mutableStateOf(false)
        internal set

    /** 이 계정이 '봤다'고 적어 둔 마지막 답장 시각(계정별 키). */
    var feedbackReplySeenAt by mutableStateOf<SwiftDate?>(null)
        internal set

    // MARK: 설정
    var tokenUsagePublic by mutableStateOf(true)
        internal set
    var tokenUsagePublicLoaded by mutableStateOf(false)
        internal set
    var miniGamePublic by mutableStateOf(true)
        internal set
    var miniGamePublicLoaded by mutableStateOf(false)
        internal set
    var inviteCode by mutableStateOf<String?>(null)
        internal set
    var inviteCodeLoaded by mutableStateOf(false)
        internal set
    var tokenUsagePublicLoadFailed by mutableStateOf(false)
        internal set
    var miniGamePublicLoadFailed by mutableStateOf(false)
        internal set
    var inviteCodeLoadFailed by mutableStateOf(false)
        internal set
    var isLoadingSettings by mutableStateOf(false)
        internal set
    var settingsNotice by mutableStateOf<String?>(null)
        internal set
    var isSigningOut by mutableStateOf(false)
        internal set

    // MARK: 계정 삭제 (설정 → 시트)
    var accountDeletionPassword by mutableStateOf("")
    var isDeletingAccount by mutableStateOf(false)
        internal set
    var accountDeletionNotice by mutableStateOf<String?>(null)
        internal set

    internal val serials = HashMap<String, Int>()

    /** 공개 설정 저장이 떠 있는 칸("token" · "minigame") — 늦게 온 GET 이 방금 바꾼 스위치를 되돌리지 않게. */
    internal val savingPrivacyKeys = HashSet<String>()

    // ------------------------------------------------------------------ 자리 API

    fun appDidBecomeActive() {
        // AI 리밋은 **탭이 보이지 않아도** 받는다 — 위젯이 소비자라 나 탭을 한 번도 열지 않는 사람의 리밋 위젯이 영원히 비지 않게.
        aiLimits.refreshIfStale()
        // 주간 보상도 탭이 안 보여도 받는다(앞에 올 때마다 · 60초 스로틀) — 정산 결과의 루비가 게임 탭·상점 알약에도 바로 선다.
        refreshWeeklyWorkIfStale()
        // 도전 미션도 같다 — 이 값이 **탭 막대 배지**다. 콜드 스타트엔 언제나 null 이라 "아는 것만 다시 읽기"로 걸면 배지가 영영 안 선다.
        // v0.3.64 일일 미션: 폰은 백그라운드에서 0시를 넘겨 돌아오는 것이 기본이다 — 돌아온 이 자리에서 넘김을 판정한다.
        refreshAchievementsIfDayRolledOver()
        refreshAchievementsIfStale()
        // 생일 선물(v0.3.66)도 탭과 무관하게 앞에 올 때마다 — 단 10분에 한 번 이하. 미뤄 둔 선물은 지금이 '다음 기회'다.
        presentCakeGiftIfDue()
        refreshCakeGiftIfStale()
        if (!isTabVisible) return
        refreshRootIfStale()
    }

    fun appDidEnterBackground() {}

    fun reset() {
        work.cancelChildren()
        for (key in serials.keys.toList()) serials[key] = (serials[key] ?: 0) + 1
        aiLimits.reset()
        displayName = null
        avatarURL = null
        centerServerValue = null
        headerState.reset()
        heatmap = WorkRhythmHeatmap.empty
        retro = null
        dailyGrid = WorkDailyGrid.empty
        tokenGrid = TokenDailyGrid.empty
        showsTokenGrid = true
        recordsState.reset()
        recordsWeekKey = null
        // 회고 배너도 계정의 것이다(맥 signOut WorkTimerStore.swift 4245 @ db93317f). '봤음' 저장 키는 계정별이라 지우지 않는다.
        showsRetroBanner = false
        // 계정에 묶인 값이다 — 안 비우면 계정을 바꾼 뒤 앞 사람의 비율로 내 잔디가 깎인다. 저장본은 계정별 키라 그대로 둔다.
        tokenShareRatio = null
        lastTokenBoardFetchAt = null
        shopCharacters = emptyList()
        ownedCharacterIDs = setOf(MeCharacterCards.aingID)
        shopState.reset()
        shopSelection = null
        shopNotice = null
        shopGachaHintID = null
        shopGiftHintID = null
        purchasingID = null
        equippedServerID = null
        equippedLoaded = false
        equippedLoadFailed = false
        savingCharacterID = null
        characterNotice = null
        isCharacterNoticeError = false
        // 뽑기도 계정에 묶인다 — 안 비우면 앞 사람의 request_id 로 다음 사람이 뽑는다(결과를 모르는 채 쥔 id 가 남는다).
        gachaInfo = null
        isPulling = false
        lastGachaResult = null
        gachaRevealSerial = 0
        gachaNotice = null
        isGachaNoticeError = false
        exchangingID = null
        exchangeNotice = null
        isExchangeNoticeError = false
        gachaRequestIDs.reset()
        // 생일 선물도 계정에 묶인다. 스스로 띄운 기록(cakeGiftAutoShownIDs)은 **실행** 단위라 그대로 둔다.
        cakeGift = null
        cakeGiftSheet = null
        cakeGiftSheetOnScreen = false
        cakeGiftCheckedAt = null
        cakeGiftLoading = false
        cakeGiftReopening = false
        weeklyWork = null
        weeklyWorkState.reset()
        weeklyWorkAvailable = true
        weeklyGrantNotice = null
        weeklyGrantSerial = 0
        weeklyGrantNoticeSeen = false
        // 도전 미션 · 받기도 계정에 묶인다 — 떠 있던 받기 자리가 남으면 새 계정의 첫 받기가 "이미 떠 있음"으로 막힌다.
        achievements = null
        achievementsState.reset()
        achievementsAvailable = true
        achievementClaimsInFlight = emptySet()
        achievementClaimFailedKeys = emptySet()
        weeklyClaimInFlight = false
        weeklyClaimFailed = false
        dailyMissionsAvailable = true
        dailyMissionClaimsInFlight = emptySet()
        dailyMissionClaimFailedKeys = emptySet()
        dailyMissionRolloverNoted = null
        achievementsServerClockOffsetMs = 0
        achievementsRefetchAfterGame = false
        missionClaimBursts = emptyMap()
        missionClaimBurstSerial = 0
        displayNameDraft = ""
        isProfileVisible = false
        displayNameNotice = null
        isDisplayNameNoticeError = false
        isUpdatingDisplayName = false
        displayNameChangedAt = null
        displayNameAvailableAt = null
        isUploadingAvatar = false
        avatarNotice = null
        isAvatarNoticeError = false
        // 상태메시지도 계정에 묶인다 — 남기면 다음 계정 편집 화면에 앞 사람의 문장이 '내 값'으로 선다.
        statusMessage = null
        statusMessageLoaded = false
        statusMessageDraft = ""
        isUpdatingStatusMessage = false
        statusMessageNotice = null
        isStatusMessageNoticeError = false
        feedbackKind = FeedbackKind.bug
        feedbackDraft = ""
        isSendingFeedback = false
        feedbackNotice = null
        feedbackList = emptyList()
        feedbackState.reset()
        feedbackReplyLatestAt = null
        feedbackReplySeenAt = null
        focusedReportID = null
        feedbackFocusSerial = 0
        tokenUsagePublic = true
        tokenUsagePublicLoaded = false
        miniGamePublic = true
        miniGamePublicLoaded = false
        inviteCode = null
        inviteCodeLoaded = false
        tokenUsagePublicLoadFailed = false
        miniGamePublicLoadFailed = false
        inviteCodeLoadFailed = false
        isLoadingSettings = false
        settingsNotice = null
        isSigningOut = false
        accountDeletionPassword = ""
        isDeletingAccount = false
        accountDeletionNotice = null
        savingPrivacyKeys.clear()
    }

    /** 안 본 제보 답장이 있으면 1. */
    val badgeCount: Int get() = if (hasUnseenFeedbackReply) 1 else 0

    // ------------------------------------------------------------------ 화면 사건

    fun tabDidAppear() {
        isTabVisible = true
        if (weeklyGrantNotice != null) weeklyGrantNoticeSeen = true
        refreshRootIfStale()
    }

    fun tabDidDisappear() {
        isTabVisible = false
        weeklyTabDidDisappear()
        missionsTabDidDisappear()
    }

    /** 딥링크(`aingcheck://me` · `me/shop` · `me/settings` · `feedback[/<id>]`). 라우터가 이미 경로를 비웠다 — 하위 화면을 한 칸 쌓는다. */
    fun open(route: MeRoute) {
        when (route) {
            MeRoute.Me -> context.meLinks.popMeToRoot()
            MeRoute.Shop -> context.meLinks.pushMe(MeDestination.Shop)
            MeRoute.Settings -> context.meLinks.pushMe(MeDestination.Settings)
            is MeRoute.Feedback -> {
                focusedReportID = route.reportID
                feedbackFocusSerial += 1
                context.meLinks.pushMe(MeDestination.Feedback)
            }
        }
    }

    /** 루트(머리·루비·착용 캐릭터·기록·답장 배지)가 낡았으면 다시 읽는다. */
    fun refreshRootIfStale() {
        if (!context.sessionStore.isSignedIn) return
        loadFeedbackReplySeenStamp()
        if (isStale(headerState)) launch { loadHeader() }
        if (isStale(shopState)) launch { loadShop() }
        if (!equippedLoaded || isStale(shopState)) launch { loadEquippedCharacter() }
        if (isStale(recordsState)) launch { loadRecords() }
        launch { loadFeedbackReplyLatest() }
        refreshWeeklyWorkIfStale()
        // 도전 미션 조회는 루트 새로고침에 얹는다(새 타이머 없음 — 스로틀도 다른 덩어리와 같은 60초). 일일 날 넘김도 여기서 판정한다.
        refreshAchievementsIfDayRolledOver()
        refreshAchievementsIfStale()
        aiLimits.refreshIfStale()
    }

    /** **로그인 직후 한 번** 착용 캐릭터만 미리 받는다(이미 알면 아무것도 안 한다). */
    fun primeEquippedCharacter() {
        if (!context.sessionStore.isSignedIn || equippedLoaded) return
        launch { loadEquippedCharacter() }
    }

    /** 당겨서 새로고침(루트): 신선도와 무관하게 전부. */
    suspend fun refreshRoot() {
        if (!context.sessionStore.isSignedIn) return
        coroutineScope {
            launch { loadHeader() }
            launch { loadShop() }
            launch { loadEquippedCharacter() }
            launch { loadRecords() }
            launch { loadFeedbackReplyLatest() }
            launch { aiLimits.load() }
            launch { loadWeeklyWork() }
            launch { loadAchievements() }
        }
    }

    // ------------------------------------------------------------------ 머리

    val teamName: String? get() = context.sessionStore.profile?.teamName
    val rubyBalance: Long? get() = context.ruby.rubyBalance
    val myUserID: String? get() = context.sessionStore.userID

    /**
     * 이름·사진(한 GET) + 센터(별도 GET). 둘은 독립 실패다. 이름·사진은 **떠날 때 찍은 쓰기 표**가 그대로일 때만 옮긴다 — 이 GET 이
     * 떠 있는 사이 별명 저장·사진 업로드가 성공했으면 응답은 그 전 값이다(rankme-verify R3·R5).
     */
    suspend fun loadHeader() {
        if (!context.sessionStore.isSignedIn) return
        val serial = nextSerial("header")
        val generation = context.generation
        val nameStamp = writeStamp(DISPLAY_NAME_WRITE_KEY)
        val avatarStamp = writeStamp(AVATAR_WRITE_KEY)
        headerState.isLoading = true
        headerState.hasFailed = false
        try {
            val service = context.service
            val card = try {
                context.withSessionRetry { s -> service.fetchMyProfileCard(s.accessToken, s.userID) }
            } catch (e: Throwable) {
                if (generation != context.generation || !isCurrent("header", serial)) return
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
                headerState.hasFailed = true
                return
            }
            if (generation != context.generation || !isCurrent("header", serial)) return
            if (writeStamp(DISPLAY_NAME_WRITE_KEY) == nameStamp) {
                val name = card?.displayName?.let(TextScalars::trimmingWhitespacesAndNewlines)
                displayName = if (name.isNullOrEmpty()) null else name
                // 편집 화면을 먼저 열었으면 빈 입력을 지금 이름으로 채운다 — 사용자가 치기 시작했으면 건드리지 않는다.
                val current = displayName
                if (isProfileVisible && displayNameDraft.isEmpty() && !isUpdatingDisplayName && current != null) displayNameDraft = current
            }
            if (writeStamp(AVATAR_WRITE_KEY) == avatarStamp) {
                avatarURL = SwiftURL.parse(card?.avatarUrl)
            }
            // 센터는 독립 실패 — 못 읽으면 지난 값을 둔다(모르는 것을 "미지정"으로 단정하지 않는다).
            val center = attempt { s -> service.fetchMyCenter(s.accessToken, s.userID) }
            if (generation != context.generation || !isCurrent("header", serial)) return
            center.onSuccess { centerServerValue = it }
            headerState.hasLoaded = true
            headerState.loadedAt = context.clock.now()
        } finally {
            if (isCurrent("header", serial)) headerState.isLoading = false
        }
    }

    // ------------------------------------------------------------------ 내부 도우미(확장 파일이 같이 쓴다)

    internal fun isStale(state: MeLoadState): Boolean {
        if (state.isLoading) return false
        val loadedAt = state.loadedAt
        if (loadedAt == null || state.hasFailed) return true
        return context.clock.now().timeIntervalSince(loadedAt) >= STALE_SECONDS
    }

    internal fun nextSerial(key: String): Int {
        val next = (serials[key] ?: 0) + 1
        serials[key] = next
        return next
    }

    internal fun isCurrent(key: String, serial: Int): Boolean = (serials[key] ?: 0) == serial

    /** 사용자가 이 칸을 서버에 **써서 성공한** 횟수. 조회가 떠날 때 찍고, 도착했을 때 달라졌으면 그 응답의 이 칸은 옛 값이다. */
    internal fun writeStamp(key: String): Int = serials[key] ?: 0

    internal fun noteLocalWrite(key: String) {
        serials[key] = (serials[key] ?: 0) + 1
    }

    /** 공개 설정 조회를 **떠날 때** 찍는 표. 그 칸 저장이 떠 있었으면 null — 서버가 저장 전에 읽었을 수 있어 응답을 믿지 않는다. */
    internal fun privacyReadStamp(key: String): Int? = if (isSavingPrivacy(key)) null else serials["privacy.$key"] ?: 0

    /** 도착한 공개 설정 값을 스위치에 옮겨도 되는가: 떠날 때 저장이 없었고 · 그 사이 사용자가 스위치를 바꾸지 않았다(rankme-verify R1). */
    internal fun canApplyPrivacyRead(key: String, stamp: Int?): Boolean {
        if (stamp == null) return false
        return (serials["privacy.$key"] ?: 0) == stamp
    }

    internal fun isSavingPrivacy(key: String): Boolean = key in savingPrivacyKeys

    /** 401 재시도를 지난 호출을 [Result] 로(서버가 null 이라고 한 것과 실패를 가른다). */
    internal suspend fun <T> attempt(operation: suspend (SupabaseSession) -> T): Result<T> = try {
        Result.success(context.withSessionRetry(operation))
    } catch (e: Throwable) {
        Result.failure(e)
    }

    /** 스토어의 일로 띄운다(Swift `launch` — `reset()` 이 끊는다). */
    internal fun launch(body: suspend () -> Unit): Job = scope.launch { body() }

    /**
     * 상점 능력 번호(K9 — [drawableCharacters] 에서 파생). 읽은 집합은 실행 동안 같다(번들은 바뀌지 않는다) — 단 **빈 집합은 쥐지 않는다**.
     * Android 는 APK 안 초상 목록 파일을 읽는데, 그 읽기가 한 번 실패하면 빈 집합(번호 0 — 뽑기·케이크 선물이 숨는다)이 온다. Swift 는 번들
     * 목록이 정적이라 이런 실패가 없으니, 일시적 실패를 실행 내내 굳히지 않게 다음 호출에서 다시 읽는다(초상이 하나도 없는 번들은 없다).
     */
    internal suspend fun drawableCharacterIDs(): Set<String> {
        resolvedDrawable?.let { return it }
        val ids = drawableCharacters.drawableCharacterIDs()
        if (ids.isNotEmpty()) resolvedDrawable = ids
        return ids
    }

    companion object {
        /** 루트 화면이 낡았다고 보는 초. */
        const val STALE_SECONDS: Double = 60.0

        /** 내 제보 목록 상한(맥 `feedbackListLimit` 과 같은 규모). */
        const val FEEDBACK_LIST_LIMIT: Long = 50

        internal const val DISPLAY_NAME_WRITE_KEY = "write.displayName"
        internal const val STATUS_MESSAGE_WRITE_KEY = "write.statusMessage"
        internal const val AVATAR_WRITE_KEY = "write.avatar"

        /**
         * 받기 응답을 **옮긴** 횟수(v0.3.58). 조회가 떠날 때 찍고, 도착했을 때 달라졌으면 그 조회는 받기 **전**의 서버를 말한다 —
         * 그대로 덮으면 방금 받은 줄에 [받기]가 다시 선다. 그때는 응답을 버린다(받기 응답이 이미 더 새 상태를 줬다).
         */
        internal const val ACHIEVEMENT_CLAIM_WRITE_KEY = "write.achievementClaim"
        internal const val WEEKLY_CLAIM_WRITE_KEY = "write.weeklyClaim"

        /** 수령 결과를 **옮긴** 횟수(생일 선물). 수령 전에 떠난 조회가 '다시 열기' 줄을 되살리지 않게. */
        internal const val CAKE_GIFT_CLAIM_WRITE_KEY = "write.cakeGiftClaim"

        /** 전부 받기(`achievement_claim(null)`)가 떠 있음을 적는 자리. 미션 키가 아니다(서버 키에 `*` 는 없다). */
        const val ACHIEVEMENT_CLAIM_ALL_SLOT = "*"

        /** 선물 조회 간격(초) — 10분에 한 번 이하. 시도 시각으로 잰다. */
        const val CAKE_GIFT_CHECK_INTERVAL: Double = 600.0
    }
}
