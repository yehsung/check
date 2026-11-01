// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 3bd04bd (NowTab · NowStatusSection · NowWorkControlRow · NowStatusCard · NowWorkingSection · NowWorkingRow)
// 원본: Sources/CheckMobileKit/Components/InsetGroup.swift @ 3bd04bd (ProgressBar — 막대)
// 원본: Sources/CheckMobileKit/Now/NowTab.swift:426 @ 1ca907fa (timerLine) · :568 (NowStreakChip — 연속 근무 칩)
// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 23b91326 (NowSectionHeader · NowTeamRosterLink · NowWorkingSection · NowWorkingGroup — [전체 보기] 입구)
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
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
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
import com.yehsung.aingcheck.core.rules.achievements.HeaderStreakCopy
import com.yehsung.aingcheck.core.session.signup.SignUpText
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
import com.yehsung.aingcheck.ui.screens.session.CreatedTeamCard
import com.yehsung.aingcheck.ui.screens.session.kit.rememberPortrait
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonSize
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
import com.yehsung.aingcheck.ui.components.ModalPresenceMark
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
    const val STREAK_CHIP = "now-streak-chip"
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
    const val TEAM_ROSTER_ENTRY = "now-team-roster-entry"
    const val CREATED_TEAM_CARD = "now-created-team"
    const val CREATED_TEAM_CONFIRM = "now-created-team-confirm"
    const val GOAL_SHEET = "now-goal-sheet"
    const val GOAL_SAVE = "now-goal-save"
    const val UPDATE_NOTICE = "now-update-notice"
    const val UPDATE_OPEN = "now-update-open"
    const val UPDATE_DISMISS = "now-update-dismiss"
}

/**
 * 지금 탭 화면. [work] 는 폰 근무 문(없으면 버튼 줄 없음). [characterID] 는 내 착용 캐릭터(나 탭이 아는 값 — 모르면 아잉).
 * [onTalk] 는 다른 팀 사람에게 말 걸기(메시지 탭 대화 열기 — 조립이 AingRoute.Message 로 연다). [onEditGoal] 은 주간 목표 시트를 연다.
 * [onOpenUpdate] 는 새 버전 안내의 [업데이트] — Play 상세(조립이 AppLinks 의 주소로 연다).
 */
@Composable
fun NowScreen(
    store: NowStore,
    work: NowWorkActions?,
    characterID: String?,
    onTalk: (String) -> Unit,
    onEditGoal: () -> Unit,
    onOpenUpdate: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenTeamRoster: () -> Unit = {},
) {
    val colors = AingTheme.colors
    LaunchedEffect(store) { store.tabDidAppear() }
    // 최신 빌드는 실행 때 한 번 오는 Flow 값이라 구독해 둔다 — 그 한 번에 이 줄이 다시 판정된다.
    val latestBuild by store.context.sessionStore.latestBuildFlow.collectAsState()
    val now = rememberNow(store.context.clock, everySeconds = 1)
    Box(modifier.fillMaxSize().background(colors.background).testTag(NowTags.SCREEN), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = READABLE_WIDTH).fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = AingDimens.space8)) {
            Column(Modifier.padding(start = AingDimens.titleMargin, end = AingDimens.titleMargin, top = 8.dp, bottom = 4.dp)) {
                Text(NowText.title, style = MaterialTheme.typography.headlineLarge, color = colors.label, modifier = Modifier.semantics { heading() })
                Text(NowText.expandedSubtitle(NowFormat.longDate(now), store.membership?.teamName), style = MaterialTheme.typography.bodyMedium, color = colors.label2)
            }
            if (latestBuild != null && store.showsUpdateNotice) {
                NowUpdateNoticeRow(onOpenUpdate, store::dismissUpdateNotice, Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp))
            }
            store.notice?.let { InlineNotice(it, NoticeKind.Warning, Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp)) }
            store.createdTeamCode?.let { code -> CreatedTeamSection(code, onConfirm = store::dismissCreatedTeamCode) }
            StatusSection(store, work, characterID, now, onEditGoal)
            NowTodoSection(store)
            WorkingSection(store, work != null, now, onTalk, onOpenTeamRoster)
        }
        NowUndoToast(store, Modifier.align(Alignment.BottomCenter))
    }
}

// ---------------------------------------------------------------- 팀 만든 직후

/**
 * 원본: Sources/check/CheckComponents.swift:1413(CreatedTeamCodeCard). 방금 만든 팀의 참여코드 한 장 — 설정까지 찾아가지 않게 지금 탭 맨 위에 세운다(맥은 패널을 통째로 갈지만 폰은 탭 위에 얹는다).
 * 코드 칸은 가입 화면과 같은 한 벌([CreatedTeamCard] — 큰 글자 · 안내 · 복사). [확인]을 누를 때까지 남는다.
 */
@Composable
private fun CreatedTeamSection(code: String, onConfirm: () -> Unit) {
    val colors = AingTheme.colors
    Column(Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 8.dp).testTag(NowTags.CREATED_TEAM_CARD), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AingIcon(sf("party.popper.fill", AppIcon.CelebrationFill), null, size = 22.dp, tint = colors.working)
            Text(SignUpText.createdTitle, style = MaterialTheme.typography.titleMedium, color = colors.label, modifier = Modifier.semantics { heading() })
        }
        CreatedTeamCard(code)
        AingButton(NowText.createdTeamConfirm, onConfirm, Modifier.testTag(NowTags.CREATED_TEAM_CONFIRM), fillsWidth = true)
    }
}

// ---------------------------------------------------------------- 새 버전 안내

/** 새 버전 안내 줄의 배치 규칙. 이 글꼴 배율부터 [업데이트] 를 제목 아래로 내린다(iOS `isAccessibilitySize` ≈ 시스템 글자 크기 최대 단계 이상 — 나 탭 `MeAILimitRowLayout` 과 같은 값). */
object NowUpdateNoticeLayout {
    const val STACK_FONT_SCALE: Float = 1.5f
}

/**
 * 카드 한 줄(원본: Sources/CheckMobileKit/Now/NowTab.swift:147 NowUpdateNoticeRow @ 1a5eeca6): 글자 · [업데이트](틴트 — 채운 단추는 화면당 하나) · 닫기(X, 누름 영역 44dp).
 * 세 요소를 합치지 않아 톡백이 두 단추에 따로 닿는다. 큰 글자에서는 [업데이트] 를 제목 아래로 내린다 — 한 줄에 두면 단추가 폭을 먼저 차지해 제목이 "새 / 버전…" 으로 잘린다.
 */
@Composable
private fun NowUpdateNoticeRow(onOpen: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val stacked = LocalDensity.current.fontScale >= NowUpdateNoticeLayout.STACK_FONT_SCALE
    val card = modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius)).testTag(NowTags.UPDATE_NOTICE)
    val title: @Composable (Modifier) -> Unit = { m ->
        Text(NowText.updateNoticeTitle, style = MaterialTheme.typography.bodyMedium, color = colors.label, modifier = m)
    }
    val update: @Composable () -> Unit = {
        AingButton(NowText.updateNoticeAction, onOpen, Modifier.testTag(NowTags.UPDATE_OPEN), kind = AingButtonKind.Tinted, size = AingButtonSize.Sm)
    }
    val dismiss: @Composable () -> Unit = {
        Box(
            Modifier.size(44.dp).clickable(role = Role.Button, onClick = onDismiss)
                .semantics { contentDescription = NowText.updateNoticeDismiss }.testTag(NowTags.UPDATE_DISMISS),
            contentAlignment = Alignment.Center,
        ) {
            AingIcon(sf("xmark", AppIcon.Close), null, size = 16.dp, tint = colors.label2)
        }
    }
    if (stacked) {
        // 행의 오른쪽 여백이 0 이라(X 가 카드 끝까지 간다) 단추만 여백을 따로 둔다.
        Column(card.padding(start = 16.dp, top = 4.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Top) {
                title(Modifier.weight(1f).padding(top = 8.dp))
                dismiss()
            }
            Box(Modifier.padding(end = 16.dp)) { update() }
        }
    } else {
        Row(card.padding(start = 16.dp, top = 4.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            title(Modifier.weight(1f))
            update()
            dismiss()
        }
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
                        card != null -> StatusCard(card, characterID, store.myStreakDays, onEditGoal)
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
        ModalPresenceMark()
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
            NowWorkOrigin.windows -> listOf(NowText.pcWorkCaption)
            NowWorkOrigin.unknown -> emptyList()
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

/** 상태 카드(시안 `.b-hero`): [초상 · 상태 글자 · 부제 · 목표 연필] / 큰 타이머(옆에 연속 근무 칩) / 이번 주 줄 + 막대. [streakDays] 가 null 이면 칩이 없다(서버가 안 알려 줌). */
@Composable
private fun StatusCard(card: NowMyCard, characterID: String?, streakDays: Long?, onEditGoal: () -> Unit) {
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
        NowTimerLine(streakDays, Modifier.padding(top = 12.dp)) {
            Text(
                NowFormat.clock(card.todaySeconds),
                style = MaterialTheme.typography.displayLarge,
                color = colors.label,
                maxLines = 1,
                modifier = Modifier.testTag(NowTags.TIMER)
                    .clearAndSetSemantics { contentDescription = "${NowText.todayLabel} ${NowFormat.spokenDuration(card.todaySeconds)}" },
            )
        }
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

/**
 * 큰 타이머 줄(Swift `timerLine`). 칩은 그 오른쪽 빈자리에 선다 — 타이머(48)보다 낮아 카드 높이를 1dp 도 안 더한다. 큰 글자에서 한 줄에 안 들어가면
 * 그때만 아래로 내린다(타이머가 칩 때문에 줄어들지 않는다). 칩이 없으면 타이머 혼자다.
 */
@Composable
private fun NowTimerLine(streakDays: Long?, modifier: Modifier = Modifier, timer: @Composable () -> Unit) {
    if (streakDays == null) {
        Box(modifier) { timer() }
        return
    }
    Layout(content = { timer(); NowStreakChip(streakDays) }, modifier = modifier) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val timerPlaceable = measurables[0].measure(loose)
        val chipPlaceable = measurables[1].measure(loose)
        val rowWidth = timerPlaceable.width + NowTimerLineLayout.ROW_SPACING.roundToPx() + chipPlaceable.width
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth else rowWidth
        if (rowWidth <= width) {
            val height = maxOf(timerPlaceable.height, chipPlaceable.height)
            layout(width, height) {
                timerPlaceable.place(0, (height - timerPlaceable.height) / 2)
                chipPlaceable.place(width - chipPlaceable.width, (height - chipPlaceable.height) / 2)
            }
        } else {
            val chipTop = timerPlaceable.height + NowTimerLineLayout.STACK_SPACING.roundToPx()
            layout(width, chipTop + chipPlaceable.height) {
                timerPlaceable.place(0, 0)
                chipPlaceable.place(0, chipTop)
            }
        }
    }
}

/** 타이머 줄 간격(Swift `HStack(spacing: 8)` · `VStack(spacing: 6)`). */
private object NowTimerLineLayout {
    val ROW_SPACING: Dp = 8.dp
    val STACK_SPACING: Dp = 6.dp
}

/**
 * 연속 근무 칩(iOS `NowStreakChip`과 같은 문장 · 같은 기호). 0일도 그린다. 불꽃만 빨강이다 — 앰버(`pending`)는 같은 카드에서 '연결 끊김'을 말한다.
 * 톡백은 칩 전체를 한 문장으로 읽는다(느낌표 없이). 누르는 자리가 아니다.
 */
@Composable
private fun NowStreakChip(days: Long) {
    val colors = AingTheme.colors
    Row(
        Modifier.testTag(NowTags.STREAK_CHIP)
            .clearAndSetSemantics { contentDescription = HeaderStreakCopy.accessibilityLabel(days) }
            .heightIn(min = 22.dp)
            .background(colors.fill, CircleShape)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        AingIcon(sf(HeaderStreakCopy.icon, AppIcon.LocalFireDepartmentFill), null, size = 13.dp, tint = colors.danger)
        Text(
            HeaderStreakCopy.text(days),
            style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"),
            color = colors.label2,
            maxLines = 1,
        )
    }
}

/** 막대(빈 트랙 fill · 채움 6pt 캡슐). */
@Composable
internal fun ProgressBar(fraction: Double, fill: androidx.compose.ui.graphics.Color, height: Dp = 6.dp) {
    val clamped = fraction.coerceIn(0.0, 1.0).toFloat()
    Box(Modifier.fillMaxWidth().height(height).background(AingTheme.colors.fill, CircleShape)) {
        // 조금이라도 찼으면 점 하나는 보인다(iOS `max(height, 폭 * fraction)`).
        if (clamped > 0f) Box(Modifier.widthIn(min = height).fillMaxHeight().fillMaxWidth(clamped).background(fill, CircleShape))
    }
}

// ---------------------------------------------------------------- 지금 근무 중

@Composable
private fun WorkingSection(store: NowStore, phoneWorkWired: Boolean, now: SwiftDate, onTalk: (String) -> Unit, onOpenTeamRoster: () -> Unit) {
    val colors = AingTheme.colors
    val people = store.workingPeople(now)
    val teammates = people.filter { it.isTeammate }
    val others = people.filter { !it.isTeammate }
    val state = store.workingLoadState
    // [전체 보기]는 "우리 팀" 줄에 있다. 근무 중인 팀원이 없으면 그 줄이 없으므로 절 머리로 옮긴다 — 줄을 하나 더 세우면 첫 화면이 길어지고,
    // 머리의 사람 수는 "다른 팀" 줄(또는 "근무 중인 사람이 없어요")이 이미 말하고 있어 잃는 것이 없다.
    val showRoster: (() -> Unit)? = if (store.showsTeamRosterEntry) onOpenTeamRoster else null
    NowSectionHeader(
        title = NowText.workingTitle(null),
        trailing = if (state == NowLoadState.loaded) NowText.peopleCount(people.size) else null,
        onShowTeamRoster = if (teammates.isEmpty()) showRoster else null,
    )
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
            WorkingGroup(NowText.ourTeam, teammates, now, store, onTalk, onShowRoster = showRoster)
            WorkingGroup(NowText.otherTeams, others, now, store, onTalk)
        } else {
            // 다른 팀 묶음에는 [전체 보기]를 붙이지 않는다 — 우리 팀 명단으로 가는 입구다.
            WorkingGroup(
                if (teammates.isEmpty()) NowText.otherTeams else NowText.ourTeam, people, now, store, onTalk,
                onShowRoster = if (teammates.isEmpty()) null else showRoster,
            )
        }
        // 폰 근무 문이 이어졌고 서버에 함수가 있을 때만 "이 탭 맨 위 버튼으로" 를 말한다.
        Text(
            if (phoneWorkWired && store.phoneWorkAvailable) NowText.workingFooter else NowText.workingFooterMacOnly,
            style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = 4.dp),
        )
    }
}

/** 절 머리. [onShowTeamRoster] 가 있으면 오른쪽 글자 대신 [우리 팀 전체 보기] 링크를 둔다. 큰 글자에서 한 줄에 안 들어가면 링크가 아래 줄로 내려간다(제목이 꺾이지 않게). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun NowSectionHeader(title: String, trailing: String?, onShowTeamRoster: (() -> Unit)?) {
    if (onShowTeamRoster == null) {
        SectionHeader(title, trailing)
    } else {
        FlowRow(
            Modifier.fillMaxWidth().padding(start = AingDimens.titleMargin, end = AingDimens.titleMargin, top = 16.dp, bottom = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            itemVerticalAlignment = Alignment.Bottom,
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge, color = AingTheme.colors.label, maxLines = 1, modifier = Modifier.semantics { heading() })
            NowTeamRosterLink(NowText.teamRosterSeeAllInHeader, onShowTeamRoster)
        }
    }
}

/**
 * [전체 보기] 링크. 누르는 칸은 44 이지만 **자리는 글자 높이만큼만 차지한다** — 지금 탭 첫 화면 길이를 늘리지 않는 것이 이 링크의 조건이다(iOS 음수 여백 -14).
 * 큰 글자에서는 겹침을 풀어 준다 — 글자가 44 를 넘으면 위아래 줄과 겹친다. 톡백은 어느 자리에서든 "우리 팀 전체 보기"로 읽는다.
 */
@Composable
private fun NowTeamRosterLink(title: String, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val overlap = if (LocalDensity.current.fontScale >= TeamRosterLayout.STACK_FONT_SCALE) 0.dp else 14.dp
    Row(
        Modifier
            .testTag(NowTags.TEAM_ROSTER_ENTRY)
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                val inset = overlap.roundToPx()
                layout(placeable.width, (placeable.height - inset * 2).coerceAtLeast(0)) { placeable.place(0, -inset) }
            }
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = NowText.teamRosterSeeAllInHeader }
            .heightIn(min = 44.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(title, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.accent, maxLines = 1)
        AingIcon(sf("chevron.right", AppIcon.ChevronRight), null, size = 12.dp, tint = colors.accent)
    }
}

/** [onShowRoster] 는 우리 팀 묶음만. 그때 사람 수는 이름 옆으로 오고 오른쪽 끝이 [전체 보기]다(큰 글자에서 한 줄에 안 들어가면 링크가 아래 줄로). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WorkingGroup(label: String, people: List<NowWorkingPerson>, now: SwiftDate, store: NowStore, onTalk: (String) -> Unit, onShowRoster: (() -> Unit)? = null) {
    val colors = AingTheme.colors
    val headerStyle = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold)
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius))) {
        if (onShowRoster != null) {
            FlowRow(
                Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalArrangement = Arrangement.spacedBy(8.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(label, style = headerStyle, color = colors.label2, modifier = Modifier.semantics { heading() })
                    Text(NowText.peopleCount(people.size), style = headerStyle, color = colors.label2)
                }
                NowTeamRosterLink(NowText.teamRosterSeeAll, onShowRoster)
            }
        } else {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp)) {
                Text(label, style = headerStyle, color = colors.label2, modifier = Modifier.weight(1f).semantics { heading() })
                Text(NowText.peopleCount(people.size), style = headerStyle, color = colors.label2)
            }
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
