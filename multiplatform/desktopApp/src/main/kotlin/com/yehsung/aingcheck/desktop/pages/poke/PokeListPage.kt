// 원본: Sources/check/CheckMenuView.swift 3547-3820(PokePanel — 제목 행·안내줄·목록) · 3896-4120(PokeDirectoryRowView·찌르기 단추)
//       · 4122-(PokeChargeButton 짧게=일반 · 3초 꾹=울트라) · WorkTimerStorePoke.swift 60-99(디렉터리 로드·쿨타임 정리) @ 35649bee
// W3-c3 콕 목록 페이지(FlyoutRoute.PokeList). 발신은 feature DesktopPokeSender(W2-g2) — 이 페이지는 단추 판정(쿨타임·나·차단·근무)과 그리기만.
package com.yehsung.aingcheck.desktop.pages.poke

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.TooltipArea
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.fetchPokeDirectory
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.core.wire.models.sortedForPokeDisplay
import com.yehsung.aingcheck.core.wire.models.toPokeDirectoryEntries
import com.yehsung.aingcheck.desktop.pages.focus.FocusModeButton
import com.yehsung.aingcheck.desktop.pages.focus.FocusModeModel
import com.yehsung.aingcheck.desktop.shellapi.Entry
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeSender
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletStore
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * app_user_directory 읽기(Swift performLoadPokeDirectory). 저장 순서는 근무중 → 이름(안 읽음은 화면이 입힌다).
 * 성공하면 [hasLoaded] — '아직 아무도 없음'과 로드 전·실패를 가른다. 실패·취소는 조용히(다음 박자·재진입이 다시 묻는다).
 * 날아가는 동안 또 부르면 0건(겹친 박자가 요청을 두 번 내지 않는다).
 */
class PokeDirectoryLoader(
    private val host: SessionHost,
    private val scope: CoroutineScope,
    private val text: WireTextRules = RulesWireTextRules,
    private val collation: Collation = NaturalKoNameCollation,
    /** 성공마다(Swift: 지난 쿨타임 정리). */
    private val onLoaded: () -> Unit = {},
) {
    private val _entries = MutableStateFlow<List<PokeDirectoryEntry>>(emptyList())
    val entries: StateFlow<List<PokeDirectoryEntry>> = _entries.asStateFlow()
    private val _hasLoaded = MutableStateFlow(false)
    val hasLoaded: StateFlow<Boolean> = _hasLoaded.asStateFlow()
    private var inFlight: Job? = null

    fun load(): Job? {
        if (host.session == null) return null
        if (inFlight?.isActive == true) return null
        val generation = host.sessionGeneration
        return scope.launch {
            val rows = try {
                host.withSessionRetry { s -> host.service.fetchPokeDirectory(s.accessToken) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) return@launch
                return@launch
            }
            if (generation != host.sessionGeneration) return@launch
            val sorted = rows.toPokeDirectoryEntries(text).sortedForPokeDisplay(emptySet(), workKnown = true, collation = collation)
            if (_entries.value != sorted) _entries.value = sorted
            if (!_hasLoaded.value) _hasLoaded.value = true
            onLoaded()
        }.also { inFlight = it }
    }

    /** 로그아웃·계정 전환. */
    fun reset() {
        inFlight?.cancel()
        _entries.value = emptyList()
        _hasLoaded.value = false
    }
}

/** 콕 목록이 읽는 것 — 조립(SocialWiring·MessagesStore)이 채운다. poke=false 면 [sender] 가 null(발신 0). */
class PokeListDeps(
    val host: SessionHost,
    val config: DesktopAppConfig,
    /** SocialWiring.sender(poke=false → null). */
    val sender: DesktopPokeSender?,
    /** SocialWiring.wallet — 화면 열기 PanelOpen sync · 잔량 배지. */
    val wallet: UltraWalletStore?,
    val focus: FocusModeModel?,
    /** UI 디스패처 스코프(디렉터리 읽기). */
    val scope: CoroutineScope,
    val clock: () -> SwiftDate,
    /** Swift `startedAt != nil`(발신자의 선게이트와 같은 값 — PokeFactsSource.localSessionOpen). */
    val localSessionOpen: () -> Boolean,
    /** MessagesStore.hiddenBlockedPeerIDs(차단 직후 숨김). */
    val hiddenBlockedPeerIDs: () -> Set<String> = { emptySet() },
    val unreadMessagePeerIDs: () -> Set<String> = { emptySet() },
    val unreadPokePeerIDs: () -> Set<String> = { emptySet() },
    /** 메시지 쪽 안내(맥 messageNotice). */
    val messageNotice: () -> String? = { null },
    /** 찌르기 수신 링이 유예를 넘겨 끊겼나(맥 PokeConnectionNotice.shouldWarn). */
    val isPokeDisconnected: () -> Boolean = { false },
    val collation: Collation = NaturalKoNameCollation,
    val text: WireTextRules = RulesWireTextRules,
)

data class PokeRowView(val entry: PokeDirectoryEntry, val button: PokeButtonState, val unread: PokeRowUnreadMark)

/** 화면 한 장의 값(스냅숏이 이것만 그린다). */
data class PokeListViewState(
    val rows: List<PokeRowView>,
    val hasLoaded: Boolean,
    val notice: PokeNoticeLine?,
    val ultraBalance: Long?,
    val ultraUnlimited: Boolean,
    val surfaces: SocialSurfaces,
    val fallbackStatus: String = PokeListRules.LOADING,
)

/** 단추 판정 + 발신 문. 판정은 [PokeListRules](맥 순서), 발신은 [DesktopPokeSender] 한 벌. */
class PokeListModel(private val deps: PokeListDeps) {
    val surfaces: SocialSurfaces = SocialPageFlags.surfaces(deps.config)
    val directory = PokeDirectoryLoader(deps.host, deps.scope, deps.text, deps.collation) {
        deps.sender?.pruneExpiredCooldowns(deps.clock())
    }
    private val inFlight = mutableMapOf<String, Job>()

    /** 화면에 세울 사람(나·차단 빼고, 네 무리 정렬). */
    fun rows(): List<PokeDirectoryEntry> = PokeListRules.visibleEntries(
        directory.entries.value, deps.host.session?.userID, deps.hiddenBlockedPeerIDs(),
        deps.unreadMessagePeerIDs(), deps.unreadPokePeerIDs(), deps.collation,
    )

    fun buttonState(entry: PokeDirectoryEntry, now: SwiftDate): PokeButtonState = PokeListRules.buttonState(
        remainingCooldown = deps.sender?.cooldownRemaining(entry.userID, now) ?: 0,
        isMyselfWorking = deps.localSessionOpen(),
        targetWorking = entry.isWorking,
    )

    /** 화면 열기(맥 팝오버·패널 열기): 디렉터리 1회 + 지갑 PanelOpen. */
    fun onOpen() {
        directory.load()
        deps.wallet?.sync(UltraSyncReason.PanelOpen)
    }

    /** 짧게 누름 = poke_user 1건. 목록에 없는 사람(나·차단)·가능이 아닌 단추·같은 대상 날아가는 중이면 0건. */
    fun poke(userID: String): Job? = fire(userID, ultra = false)

    /** 3초 꾹 = ultra_poke_user 1건(ultraPoke 표면일 때만). 잔량으로 막지 않는다(서버 판정 — DesktopPokeSender 주석). */
    fun ultra(userID: String): Job? = if (surfaces.ultraPoke) fire(userID, ultra = true) else null

    private fun fire(userID: String, ultra: Boolean): Job? {
        val sender = deps.sender ?: return null
        val entry = rows().firstOrNull { it.userID == userID } ?: return null
        if (buttonState(entry, deps.clock()) != PokeButtonState.READY) return null
        if (inFlight[userID]?.isActive == true) return null
        val job = (if (ultra) sender.sendUltraPoke(userID) else sender.sendPoke(userID)) ?: return null
        inFlight[userID] = job
        job.invokeOnCompletion { if (inFlight[userID] === job) inFlight.remove(userID) }
        return job
    }

    fun viewState(now: SwiftDate): PokeListViewState {
        val unreadMessages = deps.unreadMessagePeerIDs()
        val unreadPokes = deps.unreadPokePeerIDs()
        val wallet = deps.wallet?.state?.value
        val focusStage = if (surfaces.focusControl) deps.focus?.face()?.stage ?: FocusStage.OFF else FocusStage.OFF
        return PokeListViewState(
            rows = rows().map { e -> PokeRowView(e, buttonState(e, now), PokeRowUnreadMark.of(e.userID, unreadMessages, unreadPokes)) },
            hasLoaded = directory.hasLoaded.value,
            notice = PokeListRules.noticeLine(
                disconnected = deps.isPokeDisconnected(),
                messageNotice = deps.messageNotice(),
                notice = deps.sender?.notice?.value,
                isMyselfWorking = deps.localSessionOpen(),
                focusStage = focusStage,
            ),
            ultraBalance = wallet?.balance,
            ultraUnlimited = wallet?.unlimited ?: false,
            surfaces = surfaces,
        )
    }
}

/** 콕 목록 페이지. 뒤로 = FlyoutRoutes.backOf(PokeList) = 홈. 대화 단추 = 그 사람 대화(Entry.MESSAGES). 배지 = 울트라 화면. */
class PokeListPage(private val deps: PokeListDeps) : FlyoutPageHost {
    val model = PokeListModel(deps)

    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        val visible by nav.visible.collectAsState()
        val entries by model.directory.entries.collectAsState()
        val loaded by model.directory.hasLoaded.collectAsState()
        val notice by (deps.sender?.notice ?: NO_NOTICE).collectAsState()
        val cooldowns by (deps.sender?.cooldownUntil ?: NO_COOLDOWN).collectAsState()
        val wallet = deps.wallet?.state?.collectAsState()
        val focusOn = deps.focus?.focusMode?.collectAsState()
        val focusRev = deps.focus?.revision?.collectAsState()
        val tick = remember { mutableIntStateOf(0) }
        LaunchedEffect(visible) {
            if (!visible) return@LaunchedEffect
            model.onOpen()
            while (true) {
                delay((PokeListRules.DIRECTORY_REFRESH_SECONDS * 1000).toLong())
                model.directory.load()
            }
        }
        // 쿨타임이 남은 동안만 1초 박자(만료 순간 단추가 살아난다). 없으면 박자 0.
        LaunchedEffect(cooldowns) {
            while (cooldowns.values.any { it > deps.clock() }) {
                delay(1_000)
                tick.intValue += 1
            }
            tick.intValue += 1
        }
        val state = remember(entries, loaded, notice, cooldowns, wallet?.value, focusOn?.value, focusRev?.value, tick.intValue) { model.viewState(deps.clock()) }
        PokeListContent(
            state = state,
            onBack = { nav.back() },
            onPoke = { model.poke(it) },
            onUltra = { model.ultra(it) },
            onOpenConversation = { nav.navigate(FlyoutRoute.Conversation(it, Entry.MESSAGES)) },
            onOpenUltra = { nav.navigate(FlyoutRoute.Ultra) },
            focusButton = deps.focus?.takeIf { model.surfaces.focusControl }?.let { f -> { FocusModeButton(f) } },
            modifier = Modifier.width(widthDip.dp).fillMaxHeight(),
        )
    }

    private companion object {
        val NO_NOTICE: StateFlow<String?> = MutableStateFlow(null)
        val NO_COOLDOWN: StateFlow<Map<String, SwiftDate>> = MutableStateFlow(emptyMap())
    }
}

/** 값 → 픽셀(스냅숏·페이지 공용). */
@Composable
fun PokeListContent(
    state: PokeListViewState,
    onBack: () -> Unit,
    onPoke: (String) -> Unit,
    onUltra: (String) -> Unit,
    onOpenConversation: (String) -> Unit,
    onOpenUltra: () -> Unit,
    focusButton: (@Composable () -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val c = AingTheme.colors
    Column(modifier.background(c.background).padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth().height(27.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(27.dp).clickable(onClick = onBack).semantics { contentDescription = "뒤로" }, contentAlignment = Alignment.Center) {
                AingIcon(AppIcon.ChevronLeft, contentDescription = null, size = 16.dp, tint = c.label2)
            }
            Text(PokeListRules.TITLE, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = c.label, maxLines = 1)
            focusButton?.invoke()
            Spacer(Modifier.weight(1f))
            if (state.surfaces.walletBalance) {
                UltraBalanceBadge(state.ultraBalance, state.ultraUnlimited, onClick = if (state.surfaces.ultraPage) onOpenUltra else null)
                val dim = !(state.ultraUnlimited || (state.ultraBalance ?: 1) > 0)
                Text(
                    UltraBalanceText.hint(state.ultraBalance, state.ultraUnlimited),
                    style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal,
                    color = if (dim) c.label3Text else c.label2, maxLines = 1,
                )
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(c.separator))
        state.notice?.let { line ->
            Text(line.text, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal, color = if (line.isWarning) c.pending else c.label2, maxLines = 2)
        }
        Column(Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (state.rows.isEmpty()) {
                Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.CenterStart) {
                    Text(PokeListRules.emptyText(state.hasLoaded, state.fallbackStatus), style = MaterialTheme.typography.bodySmall, color = c.label2)
                }
            } else {
                for (row in state.rows) {
                    PokeRow(row, state, onPoke = { onPoke(row.entry.userID) }, onUltra = { onUltra(row.entry.userID) }, onOpenConversation = { onOpenConversation(row.entry.userID) })
                }
            }
        }
    }
}

@Composable
private fun UltraBalanceBadge(balance: Long?, unlimited: Boolean, onClick: (() -> Unit)?) {
    val c = AingTheme.colors
    val charged = unlimited || (balance ?: 0) > 0
    Row(
        Modifier
            .height(20.dp)
            .background(if (charged) c.accentTint else c.fill, CircleShape)
            .border(1.dp, if (charged) c.accentLine else c.separator, CircleShape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 7.dp)
            .semantics { contentDescription = "울트라 ${UltraBalanceText.badge(balance, unlimited)}개" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        AingIcon(AppIcon.BoltFill, contentDescription = null, size = 11.dp, tint = if (charged) c.accent else c.label2)
        Text(UltraBalanceText.badge(balance, unlimited), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = if (charged) c.accent else c.label2)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PokeRow(row: PokeRowView, state: PokeListViewState, onPoke: () -> Unit, onUltra: () -> Unit, onOpenConversation: () -> Unit) {
    val c = AingTheme.colors
    val e = row.entry
    Row(
        Modifier.fillMaxWidth().height(PokeListRules.rowHeightDp(e).dp).background(c.surface, RoundedCornerShape(10.dp)).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(30.dp).background(c.fill2, CircleShape), contentAlignment = Alignment.Center) {
            Text(e.name.take(1), style = MaterialTheme.typography.labelMedium, color = c.label)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(e.name, style = MaterialTheme.typography.labelLarge, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                StatusChip(e.isWorking)
                e.center?.let { Text(it, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal, color = c.label2, maxLines = 1) }
            }
            e.statusMessage?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal, color = c.label2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        TooltipArea(tooltip = { Tip(row.unread.tooltip(e.name)) }) {
            Box(Modifier.size(30.dp).clickable(onClick = onOpenConversation).semantics { contentDescription = row.unread.tooltip(e.name) }, contentAlignment = Alignment.Center) {
                Box(Modifier.size(30.dp).background(c.accentTint, CircleShape), contentAlignment = Alignment.Center) {
                    AingIcon(AppIcon.ChatBubbleFill, contentDescription = null, size = 14.dp, tint = c.accent)
                }
                if (row.unread.showsDot) Box(Modifier.align(Alignment.TopEnd).size(8.dp).background(c.badge, CircleShape))
            }
        }
        val tip = row.button.tooltip ?: UltraBalanceText.rowTooltip(state.ultraBalance, state.ultraUnlimited, state.surfaces.ultraPoke)
        TooltipArea(tooltip = { Tip(tip) }) {
            if (row.button == PokeButtonState.READY) {
                PokeChargeButton(onPoke, if (state.surfaces.ultraPoke) onUltra else null, tip)
            } else {
                Box(Modifier.size(30.dp).background(c.fill, CircleShape).semantics { contentDescription = tip }, contentAlignment = Alignment.Center) {
                    AingIcon(AppIcon.PanToolAltFill, contentDescription = null, size = 14.dp, tint = c.label3Text)
                }
            }
        }
    }
}

@Composable
private fun StatusChip(working: Boolean) {
    val c = AingTheme.colors
    Row(
        Modifier.background(if (working) c.workingTint else c.fill, CircleShape).padding(horizontal = 6.dp, vertical = 1.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Box(Modifier.size(5.dp).background(if (working) c.workingDot else c.offWorkDot, CircleShape))
        Text(if (working) PokeListRules.WORKING_CHIP else PokeListRules.AWAY_CHIP, style = MaterialTheme.typography.labelSmall, color = if (working) c.working else c.offWork, maxLines = 1)
    }
}

@Composable
private fun Tip(text: String) {
    val c = AingTheme.colors
    Box(Modifier.background(c.surface2, RoundedCornerShape(6.dp)).border(1.dp, c.separator, RoundedCornerShape(6.dp)).padding(6.dp)) {
        Text(text, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal, color = c.label)
    }
}

/** 짧게 = 일반, [UltraBalanceText.HOLD_SECONDS] 꾹 = 울트라(누르는 중 그 순간 발사 — 놓은 뒤 일반은 나가지 않는다). [onUltra] 가 null 이면 짧게만. */
@Composable
private fun PokeChargeButton(onPoke: () -> Unit, onUltra: (() -> Unit)?, description: String) {
    val c = AingTheme.colors
    val poke by rememberUpdatedState(onPoke)
    val ultra by rememberUpdatedState(onUltra)
    Box(
        Modifier
            .size(30.dp)
            .background(c.accentFill, CircleShape)
            .semantics { contentDescription = description }
            .pointerInput(Unit) {
                detectTapGestures(onPress = {
                    val fireUltra = ultra
                    if (fireUltra == null) {
                        if (tryAwaitRelease()) poke()
                        return@detectTapGestures
                    }
                    var fired = false
                    coroutineScope {
                        val hold = launch {
                            delay((UltraBalanceText.HOLD_SECONDS * 1000).toLong())
                            fired = true
                            fireUltra()
                        }
                        val released = tryAwaitRelease()
                        hold.cancel()
                        if (!fired && released) poke()
                    }
                })
            },
        contentAlignment = Alignment.Center,
    ) {
        AingIcon(AppIcon.PanToolAltFill, contentDescription = null, size = 14.dp, tint = c.onAccentFill)
    }
}
