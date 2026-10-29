// 원본: 없음 — W3-b 화면 스냅숏 장면(시험 도구). 스토어를 데모 픽스처로 돌려 채운 뒤 공용 화면을 그린다.
//
// 장면마다 "한 군데만 다른" 짝(음성 기준선 — 기억 comparison-baseline-must-differ)을 같이 낸다: 같은 크기 · 같은 스토어 · 한 값만 다르다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.me.AILimitFetchedRow
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.loadFeedback
import com.yehsung.aingcheck.core.stores.me.loadSettings
import com.yehsung.aingcheck.core.stores.me.loadStatusMessage
import com.yehsung.aingcheck.core.stores.messages.loadBlocks
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterStageMetrics
import com.yehsung.aingcheck.ui.components.RubyGlyph
import com.yehsung.aingcheck.ui.screens.me.MeAILimitsScenes
import com.yehsung.aingcheck.ui.screens.me.MeAILimitsTable
import com.yehsung.aingcheck.ui.screens.me.MeHomeScreen
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.screens.rankings.RankingsScreen
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest

/** 저장소 원본 그림을 **동기로** 읽는 그림 창구(플랫폼 시험 소스셋이 PNG 디코더를 넘긴다). */
class RepoScreenArt(private val density: Float, private val load: (String) -> ImageBitmap) : ScreenArt {
    private val cache = HashMap<String, ImageBitmap>()
    private fun image(path: String): ImageBitmap = cache.getOrPut(path) { load(path) }

    fun portraitPath(id: String, expression: CharacterExpression): String =
        if (id.startsWith("aing")) "Sources/check/Resources/$id-${expression.fileSuffix}.png"
        else "Sources/check/Characters/$id/portrait-${expression.fileSuffix}.png"

    @Composable
    override fun portrait(characterId: String, mood: CharacterMood?): ImageBitmap? = image(portraitPath(characterId, ScreenArt.expressionOf(mood)))

    @Composable
    override fun stage(characterId: String, mood: CharacterMood?, size: Dp): ImageBitmap? {
        val expression = ScreenArt.expressionOf(mood)
        return if (CharacterStageMetrics.prefersStageArt(characterId, expression, size.value, density)) image("Sources/CheckMobileKit/Resources/Art/stage-$characterId-neutral.png")
        else image(portraitPath(characterId, expression))
    }

    @Composable
    override fun ruby(pointSize: Float): ImageBitmap? = image("Sources/CheckMobileKit/Resources/Art/${RubyGlyph.assetName(pointSize, density)}.png")
}

/** 알림 절 고정 모델(스냅숏 — 플랫폼 읽기 없음). */
class FixedNotificationSettings(
    override val permission: NotificationPermission,
    override val prefs: PushPrefs?,
    override val blockedChannels: Set<String>,
) : NotificationSettingsModel {
    override val isSavingPrefs: Boolean = false
    override val isRequestingPermission: Boolean = false
    override val prefsNotice: String? = null
    override fun setEnabled(kind: NotificationKind, enabled: Boolean) {}
    override fun requestPermission() {}
    override fun openSystemSettings() {}
    override fun openChannelSettings(kind: NotificationKind) {}
}

object NoSettingsActions : SettingsActions {
    override fun openBlockedPeople() {}
    override fun openAccountDeletion() {}
    override fun confirmSignOut() {}
    override fun openUrl(url: String) {}
    override fun share(text: String) {}
}

/** 스냅숏 장면 묶음. 스토어 준비는 runTest 안에서 끝내고(가상 시간 — 데모 시각), 그리기는 그 뒤 값으로만 한다. */
@OptIn(ExperimentalCoroutinesApi::class)
object ScreenScenes {
    /** 순위 장면: 데모 픽스처로 판 하나를 채운 스토어. */
    fun rankings(board: RankingsBoard, miniGame: MiniGameKind = MiniGameKind.timingBar, oneMinuteMore: Boolean = false): RankingsStore {
        lateinit var store: RankingsStore
        runTest {
            val scenario = when (board) {
                RankingsBoard.league -> null
                RankingsBoard.tokens -> "rankings-tokens"
                RankingsBoard.minigame -> "rankings-minigame"
            }
            val h = ScreenHarness(this, DemoFixtures(DemoFixtures.rankings), scenario)
            // 음성 기준선: 1위 팀 합계에 60초만 더한다(행 하나의 숫자 한 칸만 바뀐다 — "25시간 07분" → "25시간 08분").
            if (oneMinuteMore) h.override = { r ->
                if (r.rpcName == "team_weekly_leaderboard") DemoFixture("rankings/rpc.team_weekly_leaderboard.json").read().replace("452100", "452400") else null
            }
            h.signIn()
            advanceUntilIdle()
            store = RankingsStore(h.context, h.storeScope, ScreenTestCollation)
            store.tabDidAppear()
            advanceUntilIdle()
            if (board != RankingsBoard.league) {
                store.select(board)
                advanceUntilIdle()
            }
            if (miniGame != MiniGameKind.timingBar) {
                store.select(miniGame)
                advanceUntilIdle()
            }
        }
        return store
    }

    /** 나 탭 장면: 루트 새로고침을 끝낸 스토어(머리 · 상점 · 착용 · 기록 · 리밋 · 주간 · 미션). */
    /**
     * @param todayShorter 음성 기준선: 오늘(9/17) 근무 한 건을 2시간 30분 → 2시간으로(잔디 칸 하나의 단계 · 막대 글자만 바뀐다).
     * @param statusGlyph 상태메시지 픽스처의 그림 글자(📝)를 이 글자로(서버값 · 초안이 같이 바뀐다) — 데스크톱 프로필 스냅숏은 "" 로 OS 그림 글자
     *   의존을 뺀다(ScreenSnapshotDesktopTest.profileLight 머리말).
     */
    fun me(
        rubyOverride: Long? = null, settings: Boolean = false, subScreens: Boolean = false, todayShorter: Boolean = false, statusGlyph: String? = null,
    ): MeStore {
        lateinit var store: MeStore
        runTest {
            val h = ScreenHarness(this, DemoFixtures(DemoFixtures.me), scenario = "me")
            h.override = { r ->
                when {
                    r.rpcName == "register_device_fcm" -> REGISTER_OK
                    // 장면 폴더(_me-settings)의 공개 설정 — 이 조립은 장면 하나(me)만 고르므로 바늘로 직접 집는다.
                    r.path == "/rest/v1/profiles" && r.query.any { it.second.contains("minigame_public") } ->
                        DemoFixture("me/_me-settings/rest.profiles.get@select=minigame_public.json").read()
                    // 데모 리밋 픽스처에는 device_id 가 없다(0.3.47 전 모양) — 기기 신원을 지어내지 않는 스토어가 줄을 다 버린다.
                    // 카드 줄이 서는 모양을 보려고 맥 한 대의 이름·id 를 덧붙인다(값은 픽스처 그대로).
                    statusGlyph != null && r.path == "/rest/v1/profiles" && r.query.any { it.second.contains("status_message") } ->
                        DemoFixture("me/rest.profiles.get@select=status_message.json").read()
                            .also { check(it.contains("📝")) { "상태메시지 그림 글자를 못 찾았다 — 픽스처가 바뀌었다" } }
                            .replace("📝", statusGlyph)
                    // 줄 끝을 LF 로 접고 바꾼다: Windows 러너의 체크아웃은 core.autocrlf 로 픽스처가 CRLF 라 "\n" 을 낀 바늘이 빗나간다
                    // (7차 CI — 바꾸기 실패 → 이 응답이 던져져 잔디가 통째로 비어 음성 기준선이 화면 절반 이상 달랐다).
                    todayShorter && r.path == "/rest/v1/work_sessions" && r.query.any { it.first == "limit" } ->
                        DemoFixture("me/rest.work_sessions.get@limit=5000.json").read().replace("\r\n", "\n")
                            .replace("\"ended_at\": \"2026-09-17T03:30:00+00:00\",\n  \"duration_seconds\": 9000", "\"ended_at\": \"2026-09-17T03:00:00+00:00\",\n  \"duration_seconds\": 7200")
                            .also { check(it.contains("2026-09-17T03:00:00")) { "오늘 근무 줄을 못 찾았다 — 픽스처가 바뀌었다" } }
                    r.path == "/rest/v1/ai_limits" -> DemoFixture("me/rest.ai_limits.get.json").read()
                        .replace("\"provider\":", "\"device_id\": \"mac-a-1111\", \"device_label\": \"예성의 MacBook Pro\", \"provider\":")
                    else -> null
                }
            }
            h.signIn()
            advanceUntilIdle()
            store = h.meStore()
            store.refreshRoot()
            advanceUntilIdle()
            if (settings) {
                store.loadSettings()
                advanceUntilIdle()
            }
            // 하위 화면(제보 · 프로필) 장면: 화면이 설 때 부르는 조회를 미리 끝낸다(그리기 때는 스토어 범위가 이미 닫혀 있다).
            if (subScreens) {
                store.loadFeedback()
                store.loadStatusMessage()
                advanceUntilIdle()
            }
            if (rubyOverride != null) h.ruby.rubyBalance = rubyOverride
        }
        return store
    }

    /** 차단한 사람 장면: [count] 명(1 또는 2)을 돌려주는 list_blocks 로 채운 메시지 스토어. */
    fun blocked(count: Int): com.yehsung.aingcheck.core.stores.messages.MessagesStore {
        lateinit var store: com.yehsung.aingcheck.core.stores.messages.MessagesStore
        runTest {
            val rows = listOf(
                """{"user_id":"d0000000-0000-4000-8000-0000000000b9","display_name":"민트","avatar_url":null,"created_at":"2026-09-16T03:00:00+00:00"}""",
                """{"user_id":"d0000000-0000-4000-8000-0000000000c1","display_name":"노을","avatar_url":null,"created_at":"2026-09-10T03:00:00+00:00"}""",
            ).take(count)
            val h = ScreenHarness(this, DemoFixtures(DemoFixtures.me), scenario = "me")
            h.override = { r -> if (r.path == "/rest/v1/rpc/list_blocks") rows.joinToString(",", "[", "]") else null }
            h.signIn()
            advanceUntilIdle()
            store = com.yehsung.aingcheck.core.stores.messages.MessagesStore(h.context, h.storeScope, ScreenTestCollation)
            store.loadBlocks(force = true)
            advanceUntilIdle()
        }
        return store
    }

    private const val REGISTER_OK = """{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":false}}"""

    /** 맥 두 대 · 이름 겹침 · 상한 길이 이름 겹침(Swift MeAILimitsPreviewCatalog 의 장면 — 같은 두 함수로 묶는다). */
    fun aiLimitGroups(kind: String): List<com.yehsung.aingcheck.core.stores.me.AILimitDeviceDisplayGroup> {
        val now = SwiftDate(1_789_621_500.0)
        fun rows(device: String, label: String?, ago: Double, fiveHour: Double = 27.0, weekly: Double = 60.0): List<AILimitFetchedRow> {
            val observed = SwiftDate(now.timeIntervalSince1970 - ago)
            return listOf(
                AILimitFetchedRow(device, label, "claude", fiveHour, SwiftDate(now.timeIntervalSince1970 + 9_000), weekly, SwiftDate(now.timeIntervalSince1970 + 450_000), "max", observed),
                AILimitFetchedRow(device, label, "codex", 0.0, null, 94.0, SwiftDate(now.timeIntervalSince1970 + 200_000), "plus", observed),
                AILimitFetchedRow(device, label, "antigravity", null, null, 8.0, SwiftDate(now.timeIntervalSince1970 + 500_000), null, observed),
            )
        }
        val fetched = when (kind) {
            "two-devices" -> rows("mac-a-1111", "예성의 MacBook Pro", 120.0) + rows("mac-b-2222", "사무실 iMac", 1_800.0, 91.0, 44.0).take(1)
            // 음성 기준선: 둘째 맥 5시간 91 → 41(숫자 한 칸 — 위험색이 평온색으로).
            "two-devices-alt" -> rows("mac-a-1111", "예성의 MacBook Pro", 120.0) + rows("mac-b-2222", "사무실 iMac", 1_800.0, 41.0, 44.0).take(1)
            "twin-names" -> rows("twin-aaaa-a1b2", "Mac mini", 120.0).take(2) + rows("twin-bbbb-c3d4", "Mac mini", 600.0, 91.0, 44.0).take(1) +
                rows("nameless-9f8e", null, 900.0, 12.0, 5.0).take(1)
            "twin-long-names" -> {
                val head = "거실에 둔 맥 미니 "
                val name = head + "길".repeat(64 - head.length)
                rows("twin-aaaa-a1b2", name, 120.0).take(2) + rows("twin-bbbb-c3d4", name, 600.0, 91.0, 44.0).take(1)
            }
            else -> rows("mac-a-1111", "예성의 MacBook Pro", 120.0)
        }
        return MeAILimitsScenes.fold(fetched, now)
    }
}

/** 장면 그리기 공통: 테마 + 그림 창구 + 고정 크기. */
@Composable
fun ScreenScene(dark: Boolean, art: ScreenArt, modifier: Modifier, content: @Composable (Modifier) -> Unit) {
    AingTheme(dark = dark) {
        CompositionLocalProvider(LocalScreenArt provides art) { content(modifier) }
    }
}

@Composable
fun RankingsScene(store: RankingsStore, me: RankingsMyFace, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    RankingsScreen(store, me, scope, onSelectBoard = {}, modifier = modifier, scrollable = false)
}

@Composable
fun MeHomeScene(store: MeStore, presence: MeStageMood?, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    MeHomeScreen(store, presence, open = {}, scope = scope, modifier = modifier, scrollable = false)
}

@Composable
fun SettingsScene(store: MeStore, mode: AingAppearanceMode, notifications: NotificationSettingsModel, modifier: Modifier) {
    val appearance = remember(mode) { AppearanceStore(ScreenMemoryPrefs().apply { putString(AingAppearanceMode.STORAGE_KEY, mode.storedValue) }) }
    SettingsScreen(store, appearance, NoSettingsActions, modifier, notifications = { NotificationSettingsSection(notifications) }, scrollable = false)
}

@Composable
fun AccountDeletionScene(store: MeStore, modifier: Modifier) {
    AccountDeletionScreen(store, onDelete = {}, onClose = {}, modifier = modifier)
}

/** 「AI 리밋」 카드 한 장(Swift MeAILimitsPreviewCatalog.card — 제목 · 표 · 캡션). */
@Composable
fun AILimitsTableScene(kind: String, modifier: Modifier) {
    val groups = remember(kind) { ScreenScenes.aiLimitGroups(kind) }
    val colors = AingTheme.colors
    androidx.compose.foundation.layout.Box(modifier.background(colors.background).padding(horizontal = 16.dp, vertical = 12.dp)) {
        androidx.compose.foundation.layout.Column(
            Modifier.background(colors.surface, androidx.compose.foundation.shape.RoundedCornerShape(22.dp)).padding(16.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
        ) {
            com.yehsung.aingcheck.ui.screens.me.MeAILimitsTitle(null)
            MeAILimitsTable(groups, showsDeviceNames = kind != "one-device")
            androidx.compose.material3.Text(
                com.yehsung.aingcheck.core.stores.me.MeAILimitsText.aiLimitsCaption,
                style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                color = colors.label2,
            )
        }
    }
}

@Composable
fun GrassDetailScene(store: MeStore, axis: com.yehsung.aingcheck.core.stores.me.MeGrassAxis, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    com.yehsung.aingcheck.ui.screens.me.GrassDetailScreen(store, axis, scope, modifier)
}

@Composable
fun CharacterPickerScene(store: MeStore, modifier: Modifier) {
    com.yehsung.aingcheck.ui.screens.me.CharacterPickerScreen(store, openShop = {}, openGachaMachine = {}, modifier = modifier, scrollable = false)
}

@Composable
fun ProfileScene(store: MeStore, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    com.yehsung.aingcheck.ui.screens.me.ProfileScreen(store, scope, onPickPhoto = {}, openCharacters = {}, modifier = modifier, scrollable = false)
}

@Composable
fun FeedbackScene(store: MeStore, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    com.yehsung.aingcheck.ui.screens.me.FeedbackScreen(store, scope, modifier)
}

@Composable
fun BlockedPeopleScene(store: com.yehsung.aingcheck.core.stores.messages.MessagesStore, modifier: Modifier) {
    BlockedPeopleScreen(store, modifier, scrollable = false)
}

/** 설명 시트 장면 내용(시험 픽스처 — iOS PushText · PushKind 와 같은 글자. 화면 상수는 조립이 W2-f 에서 넘긴다). */
object PrimerFixture {
    fun content(withChess: Boolean = true) = NotificationPrimerContent(
        title = "알림을 켜 둘까요?",
        body = "앱을 닫아 두어도 이런 소식을 바로 알려 드려요.",
        macNote = "맥에서 근무 중이고 방금 입력이 있었다면 메시지·오목 신청 알림은 폰에 보내지 않아요.",
        settingsNote = "종류별로 끄는 것은 나 탭 설정에서 할 수 있어요.",
        allow = "알림 켜기",
        later = "나중에",
        kinds = listOfNotNull(
            NotificationPrimerContent.Kind("message", "메시지", "누가 나에게 메시지를 보내면"),
            NotificationPrimerContent.Kind("gomoku_invite", "오목 신청", "누가 오목 대결을 신청하면"),
            if (withChess) NotificationPrimerContent.Kind("chess_invite", "체스 신청", "누가 체스 대결을 신청하면") else null,
            NotificationPrimerContent.Kind("feedback_reply", "제보 답장", "보낸 제보에 답장이 오면"),
            NotificationPrimerContent.Kind("work_check", "근무 확인", "폰으로 연 근무를 오래 확인하지 않으면"),
        ),
    )
}

@Composable
fun NotificationPrimerScene(content: NotificationPrimerContent, requesting: Boolean, modifier: Modifier) {
    NotificationPrimerSheet(content, isRequesting = requesting, onAllow = {}, onLater = {}, modifier = modifier)
}
