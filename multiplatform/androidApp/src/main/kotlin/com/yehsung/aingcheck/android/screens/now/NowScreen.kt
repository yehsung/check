// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 3bd04bd (NowTab · NowStatusSection · NowWorkControlRow · NowStatusCard · NowWorkingSection · NowWorkingRow)
// 원본: Sources/CheckMobileKit/Components/InsetGroup.swift @ 3bd04bd (ProgressBar — 막대)
//
// 지금 탭(SPEC-ios §3.2 · 재디자인 B 01·02): 큰 제목 + 부제(날짜 · 팀) · 내 상태 카드(착용 캐릭터 초상 · 큰 타이머 · 이번 주 막대) ·
// [근무 시작/종료] · 오늘 할 일 · 지금 근무 중(우리 팀 경과 / 다른 팀 말 걸기). 무소속이면 팀 합류 카드가 그 자리에 선다.
//
// 근무 시작·종료·생존 신호는 폰 근무 갈래(W2-f NowStorePhoneWork) 몫이다 — 이 화면은 [NowWorkActions] 문으로만 부른다. 그 문이 없는
// 조립(W2-f 병합 전)에서는 버튼 줄을 그리지 않고 "근무 시작과 종료는 맥 앱에서 해요" 를 말한다(서버에 폰 근무 함수가 없을 때와 같은 모양).
// 시각은 스토어 시계에서만 읽는다(1초 · 1분 다시 그리기는 rememberNow).
package com.yehsung.aingcheck.android.screens.now

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.messages.MobileRelativeTime
import com.yehsung.aingcheck.core.stores.messages.PresenceStatus
import com.yehsung.aingcheck.core.stores.now.NowFormat
import com.yehsung.aingcheck.core.stores.now.NowLoadState
import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.stores.now.NowWorkOrigin
import com.yehsung.aingcheck.core.stores.now.NowWorkingPerson
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.screens.session.kit.rememberPortrait
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.screens.session.kit.LoadingRow
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.PersonName
import com.yehsung.aingcheck.ui.screens.session.kit.READABLE_WIDTH
import com.yehsung.aingcheck.ui.screens.session.kit.SectionHeader
import com.yehsung.aingcheck.ui.screens.session.kit.rememberNow
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/**
 * 폰 근무 시작·종료 문(W2-f `NowStorePhoneWork` 가 구현 — Swift `NowStorePhoneWork.swift` 의 화면 값과 두 동작).
 * 조립이 넘긴다. 이 화면은 판정을 다시 적지 않는다(버튼을 그릴지 · 근무 중인지 · 출처는 저쪽 계산).
 */
interface NowWorkActions {
    /** 버튼 줄을 그릴지(소속 · 팀 상태 · 서버 함수). */
    val showsWorkControl: Boolean

    /** 무소속이라 꺼진 버튼 + 이유를 그릴지(서버에 함수가 있을 때만). */
    val showsDisabledWorkControlForNoTeam: Boolean

    /** 지금 근무 중인가(카드와 같은 값). */
    val isMyWorkOpen: Boolean

    /** 내 열린 근무의 출처(버튼 아래 안내 · 종료 확인 문구). */
    val myWorkOrigin: NowWorkOrigin

    /** 알림 권한이 거절됐다(폰이 연 근무면 "확인 알림 없이 끝날 수 있어요" 경고). 알림 문은 W2-f · 셸 몫. */
    val isPushDenied: Boolean

    suspend fun clockIn()

    suspend fun clockOut()
}

/** 지금 탭 시험 표식. */
object NowTags {
    const val SCREEN = "now-screen"
    const val STATUS_CARD = "now-status-card"
    const val TIMER = "now-timer"
    const val WORK_START = "now-work-start"
    const val WORK_STOP = "now-work-stop"
    const val EDIT_GOAL = "now-edit-goal"
    const val TODO_FIELD = "now-todo-field"
    const val TODO_ADD = "now-todo-add"
    fun todoRow(id: String): String = "now-todo-$id"
    fun todoCheck(id: String): String = "now-todo-check-$id"
    const val TODO_UNDO = "now-todo-undo"
    fun workingRow(id: String): String = "now-working-$id"
    fun talk(id: String): String = "now-talk-$id"
    const val TEAM_JOIN = "now-team-join"
    const val GOAL_SHEET = "now-goal-sheet"
    const val GOAL_SAVE = "now-goal-save"
}

/**
 * 지금 탭 화면. [work] 는 폰 근무 문(없으면 버튼 줄 없음). [characterID] 는 내 착용 캐릭터(나 탭이 아는 값 — 모르면 아잉).
 * [onTalk] 는 다른 팀 사람에게 말 걸기(메시지 탭 대화 열기 — 조립이 AingRoute.Message 로 연다). [onEditGoal] 은 주간 목표 시트를 연다.
 */
@Composable
fun NowScreen(
    store: NowStore,
    work: NowWorkActions?,
    characterID: String?,
    onTalk: (String) -> Unit,
    onEditGoal: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    LaunchedEffect(store) { store.tabDidAppear() }
    val now = rememberNow(store.context.clock, everySeconds = 1)
    Box(modifier.fillMaxSize().background(colors.background).testTag(NowTags.SCREEN), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = READABLE_WIDTH).fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = AingDimens.space8)) {
            Column(Modifier.padding(start = AingDimens.titleMargin, end = AingDimens.titleMargin, top = 8.dp, bottom = 4.dp)) {
                Text(NowText.title, style = MaterialTheme.typography.headlineLarge, color = colors.label, modifier = Modifier.semantics { heading() })
                Text(NowText.expandedSubtitle(NowFormat.longDate(now), store.membership?.teamName), style = MaterialTheme.typography.bodyMedium, color = colors.label2)
            }
            store.notice?.let { InlineNotice(it, NoticeKind.Warning, Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp)) }
            StatusSection(store, work, characterID, now, onEditGoal)
            NowTodoSection(store)
            WorkingSection(store, work != null, now, onTalk)
        }
        NowUndoToast(store, Modifier.align(Alignment.BottomCenter))
    }
}

// ---------------------------------------------------------------- 내 상태

@Composable
private fun StatusSection(store: NowStore, work: NowWorkActions?, characterID: String?, now: SwiftDate, onEditGoal: () -> Unit) {
    val colors = AingTheme.colors
    var confirmingStop by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Column(Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 8.dp)) {
        if (store.hasNoTeam) {
            // 무소속: 맨 위 버튼은 꺼진 채 이유를 말한다 — 아래 합류 카드가 그 이유를 푸는 자리다.
            if (work?.showsDisabledWorkControlForNoTeam == true) {
                Card { WorkControlRow(store, work, onStop = {}) }
                Spacer(Modifier.height(AingDimens.rowSpacing))
            }
            NowTeamJoinSection(store.teamJoin)
        } else {
            val showsControl = work?.showsWorkControl == true
            Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius)).testTag(NowTags.STATUS_CARD)) {
                Box(Modifier.padding(16.dp)) {
                    val card = store.myCard(now)
                    when {
                        card != null -> StatusCard(card, characterID, onEditGoal)
                        store.teamLoadState == NowLoadState.failed ->
                            LoadFailureRow(NowText.statusUnavailableTitle, store.isRefreshing, retry = { store.refresh() })
                        else -> LoadingRow()
                    }
                }
                if (showsControl && work != null) {
                    HorizontalDivider(Modifier.padding(start = AingDimens.cardPadding), thickness = AingDimens.hairline, color = colors.separator)
                    Box(Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 14.dp)) {
                        WorkControlRow(store, work, onStop = { confirmingStop = true })
                    }
                }
            }
        }
    }
    if (confirmingStop && work != null) {
        AlertDialog(
            onDismissRequest = { confirmingStop = false },
            title = { Text(NowText.workStopConfirmTitle) },
            text = { Text(NowText.workStopConfirmMessage(work.myWorkOrigin)) },
            confirmButton = {
                TextButton({ confirmingStop = false; scope.launch { work.clockOut() } }) { Text(NowText.workStop, color = colors.danger) }
            },
            dismissButton = { TextButton({ confirmingStop = false }) { Text(NowText.close) } },
            containerColor = colors.surface,
        )
    }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius)).padding(16.dp)) { content() }
}

/** 근무 시작·종료 줄: 근무 중이 아니면 [근무 시작](채움), 근무 중이면 [근무 종료](회색 — 누르면 확인). 아래 안내 줄 · 결과 · 알림 꺼짐 경고. */
@Composable
private fun WorkControlRow(store: NowStore, work: NowWorkActions, onStop: () -> Unit) {
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    val working = work.isMyWorkOpen
    val origin = work.myWorkOrigin
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (working) {
            AingButton(NowText.workStop, onStop, Modifier.testTag(NowTags.WORK_STOP), kind = AingButtonKind.Gray, fillsWidth = true,
                isBusy = store.isWorkBusy, enabled = !store.isWorkBusy, icon = sf("stop.fill", AppIcon.StopFill))
        } else {
            AingButton(NowText.workStart, { scope.launch { work.clockIn() } }, Modifier.testTag(NowTags.WORK_START), fillsWidth = true,
                isBusy = store.isWorkBusy, enabled = !store.isWorkBusy && !store.hasNoTeam, icon = sf("play.fill", AppIcon.PlayArrowFill))
        }
        for (line in NowWorkLines.lines(store.hasNoTeam, working, origin, store.phoneSession?.checkAfterSeconds)) {
            Text(line, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        }
        store.workNotice?.let { InlineNotice(it, NoticeKind.Info) }
        if (working && origin == NowWorkOrigin.phone && work.isPushDenied) InlineNotice(NowText.pushOffWarning, NoticeKind.Warning)
    }
}

/** 버튼 아래 안내 줄(Swift `NowWorkControlRow.lines`). 순수 — 시험이 잰다. */
object NowWorkLines {
    fun lines(hasNoTeam: Boolean, working: Boolean, origin: NowWorkOrigin, checkAfterSeconds: Int?): List<String> {
        if (hasNoTeam) return listOf(NowText.workNeedsTeam)
        if (!working) return emptyList()
        return when (origin) {
            NowWorkOrigin.phone -> listOf(NowText.phoneWorkCaption(checkAfterSeconds))
            NowWorkOrigin.mac -> listOf(NowText.macWorkCaption)
            // int-j(W2-f 패치 0003 의 windows 갈래): iOS 에는 짝이 없고 문구도 정하지 않았다 — 상태 글자('PC에서 근무 중')만 보이고
            //   안내 줄은 비운다(맥 문구로 접지 않는다). Windows 앱은 보류(§8-16)라 지금 서버가 이 값을 싣는 일은 없다.
            NowWorkOrigin.windows, NowWorkOrigin.unknown -> emptyList()
        }
    }

    /** 상태 카드 초상 기분(근무 중 · 끊김 · 안 함). */
    fun mood(card: NowMyCard): CharacterMood = if (card.isWorking) (if (card.isStale) CharacterMood.Lost else CharacterMood.Working) else CharacterMood.Off

    /** 상태 글자 아래 부제. */
    fun subtitle(card: NowMyCard): String = when {
        card.isStale -> NowText.staleSubtitle
        card.isWorking && card.sessionStartedAt != null -> NowText.sessionSince(NowFormat.clockTime(card.sessionStartedAt!!))
        else -> NowText.offSubtitle
    }
}

/** 상태 카드(시안 `.b-hero`): [초상 · 상태 글자 · 부제 · 목표 연필] / 큰 타이머 / 이번 주 줄 + 막대. */
@Composable
private fun StatusCard(card: NowMyCard, characterID: String?, onEditGoal: () -> Unit) {
    val colors = AingTheme.colors
    val mood = NowWorkLines.mood(card)
    val art = rememberPortrait(characterID ?: DEFAULT_CHARACTER, mood.expression)
    val stateColor = when {
        !card.isWorking -> colors.offWork
        card.isStale -> colors.pending
        else -> colors.working
    }
    Column {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            CharacterPortrait(art, mood, 54.dp)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                Text(card.stateText, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = stateColor)
                Text(NowWorkLines.subtitle(card), style = MaterialTheme.typography.bodySmall, color = if (card.isStale) colors.pending else colors.label2)
            }
            Box(
                Modifier.size(44.dp).clickable(role = Role.Button, onClick = onEditGoal)
                    .semantics { contentDescription = NowText.goalEdit }.testTag(NowTags.EDIT_GOAL),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(34.dp).background(colors.fill, CircleShape), contentAlignment = Alignment.Center) {
                    AingIcon(sf("pencil", AppIcon.Edit), null, size = 18.dp, tint = colors.label2)
                }
            }
        }
        Text(
            NowFormat.clock(card.todaySeconds),
            style = MaterialTheme.typography.displayLarge,
            color = colors.label,
            maxLines = 1,
            modifier = Modifier.padding(top = 12.dp).testTag(NowTags.TIMER)
                .clearAndSetSemantics { contentDescription = "${NowText.todayLabel} ${NowFormat.spokenDuration(card.todaySeconds)}" },
        )
        Column(Modifier.padding(top = 10.dp).clearAndSetSemantics { contentDescription = card.weekLine }, verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${NowText.weekPrefix} ${NowFormat.hoursMinutesText(card.weekSeconds)} ${NowText.goalSuffix(card.goalHours)}",
                    style = MaterialTheme.typography.bodyMedium, color = colors.label2, modifier = Modifier.weight(1f))
                Text("${card.percent}%", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = if (card.isGoalComplete) colors.working else colors.label)
            }
            ProgressBar(card.progress, if (card.isGoalComplete) colors.working else colors.accentFill)
        }
    }
}

/** 막대(빈 트랙 fill · 채움 6pt 캡슐). */
@Composable
internal fun ProgressBar(fraction: Double, fill: androidx.compose.ui.graphics.Color, height: Dp = 6.dp) {
    val clamped = fraction.coerceIn(0.0, 1.0).toFloat()
    Box(Modifier.fillMaxWidth().height(height).background(AingTheme.colors.fill, CircleShape)) {
        if (clamped > 0f) Box(Modifier.fillMaxHeight().fillMaxWidth(clamped).background(fill, CircleShape))
    }
}

// ---------------------------------------------------------------- 지금 근무 중

@Composable
private fun WorkingSection(store: NowStore, phoneWorkWired: Boolean, now: SwiftDate, onTalk: (String) -> Unit) {
    val colors = AingTheme.colors
    val people = store.workingPeople(now)
    val teammates = people.filter { it.isTeammate }
    val others = people.filter { !it.isTeammate }
    val state = store.workingLoadState
    SectionHeader(NowText.workingTitle(null), if (state == NowLoadState.loaded) NowText.peopleCount(people.size) else null)
    Column(Modifier.padding(horizontal = AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (state != NowLoadState.loaded || people.isEmpty()) {
            Card {
                when (state) {
                    NowLoadState.loading -> LoadingRow()
                    // 모르는데 "근무 중인 사람이 없어요"나 스피너를 보이지 않는다.
                    NowLoadState.failed -> LoadFailureRow(NowText.workingUnavailable, retry = null)
                    NowLoadState.loaded -> Text(NowText.workingEmpty, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                }
            }
        } else if (teammates.isNotEmpty() && others.isNotEmpty()) {
            WorkingGroup(NowText.ourTeam, teammates, now, store, onTalk)
            WorkingGroup(NowText.otherTeams, others, now, store, onTalk)
        } else {
            WorkingGroup(if (teammates.isEmpty()) NowText.otherTeams else NowText.ourTeam, people, now, store, onTalk)
        }
        // 폰 근무 문이 이어졌고 서버에 함수가 있을 때만 "이 탭 맨 위 버튼으로" 를 말한다.
        Text(
            if (phoneWorkWired && store.phoneWorkAvailable) NowText.workingFooter else NowText.workingFooterMacOnly,
            style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = 4.dp),
        )
    }
}

@Composable
private fun WorkingGroup(label: String, people: List<NowWorkingPerson>, now: SwiftDate, store: NowStore, onTalk: (String) -> Unit) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius))) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp)) {
            Text(label, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.label2,
                modifier = Modifier.weight(1f).semantics { heading() })
            Text(NowText.peopleCount(people.size), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.label2)
        }
        people.forEachIndexed { index, person ->
            WorkingRow(person, now) { onTalk(person.id) }
            if (index < people.size - 1) HorizontalDivider(Modifier.padding(start = 64.dp), thickness = AingDimens.hairline, color = colors.separator)
        }
        Spacer(Modifier.height(6.dp))
    }
}

@Composable
private fun WorkingRow(person: NowWorkingPerson, now: SwiftDate, onTalk: () -> Unit) {
    val colors = AingTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp, vertical = 6.dp).testTag(NowTags.workingRow(person.id)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PersonAvatar(person.name, person.id, person.avatarURL?.absoluteString, 36.dp, status = if (person.isStale) PresenceStatus.pending else PresenceStatus.working)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            PersonName(person.name, person.center)
            person.statusMessage?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.semantics { contentDescription = "상태메시지 $it" })
            }
            if (person.isStale) {
                Text(NowText.staleLastSeen(person.lastSeenAt?.let { MobileRelativeTime.text(it, now) }),
                    style = MaterialTheme.typography.bodySmall, color = colors.pending)
            }
        }
        if (person.isTeammate) {
            // 경과(분 단위). 신호가 끊긴 사람은 스토어가 멈춘 값을 준다.
            val seconds = NowWorkingElapsed.seconds(person, now)
            Text(NowFormat.hoursMinutesText(seconds), style = MaterialTheme.typography.bodyMedium, color = colors.label2,
                modifier = Modifier.semantics { contentDescription = "근무 ${NowFormat.spokenDuration(seconds)}째" })
        } else {
            Box(
                Modifier.size(44.dp).clickable(role = Role.Button, onClick = onTalk)
                    .semantics { contentDescription = NowText.talkTo(person.name) }.testTag(NowTags.talk(person.id)),
                contentAlignment = Alignment.Center,
            ) { AingIcon(sf("bubble.left", AppIcon.ChatBubble), null, size = 22.dp, tint = colors.accent) }
        }
    }
}

/** 우리 팀 경과(Swift `NowWorkingRow.elapsed`): 끊겼으면 멈춘 값, 아니면 시작 시각부터 지금까지. */
object NowWorkingElapsed {
    fun seconds(person: NowWorkingPerson, now: SwiftDate): Int {
        if (person.isStale) return person.elapsedSeconds ?: 0
        val started = person.startedAt ?: return person.elapsedSeconds ?: 0
        return maxOf(0, now.timeIntervalSince(started).toInt())
    }
}

private const val DEFAULT_CHARACTER = "aing"
