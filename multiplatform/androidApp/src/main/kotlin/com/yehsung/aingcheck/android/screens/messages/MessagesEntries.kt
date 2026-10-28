// 원본: Sources/CheckMobileKit/Messages/MessagesTab.swift @ 3bd04bd (MessagesTab — 경로 push · consumeRoute → MessagesListRules.destinations · 시트 둘)
//
// 메시지 탭 진입 함수(조립 K11 이 NavGraph 의 자리표시 줄을 이것으로 바꾼다 — assembly.md). 화면 본문은 ui/screens/messages(공용 한 벌, §8-4).
// 목적지 값(Dest.*)은 셸(W1-g)의 것을 쓴다 — 이 파일은 라우트 상수(신고 대상 글자 · 라우트 → 메시지 탭 경로)와 진입 함수만 둔다.
package com.yehsung.aingcheck.android.screens.messages

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.core.stores.messages.MessagesConversationHeader
import com.yehsung.aingcheck.core.stores.messages.MessagesDestination
import com.yehsung.aingcheck.core.stores.messages.MessagesListRules
import com.yehsung.aingcheck.core.stores.messages.MessagesRouteTarget
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.ui.screens.messages.ConversationScreen
import com.yehsung.aingcheck.ui.screens.messages.MessagesBlockConfirmSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesListScreen
import com.yehsung.aingcheck.ui.screens.messages.MessagesMegaphoneSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesNewConversationSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesReportSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesReportTarget

/**
 * 셸 라우트(AingRoute — androidApp)를 메시지 탭 경로로 옮긴다(6차 int-h 이월 "MessagesListRules.destinations 를 AingRoute 에 잇기").
 * 스토어 층은 AingRoute 를 볼 수 없어(의존 방향) 메시지 탭 몫([MessagesRouteTarget])으로 옮겨 코어 규칙에 묻는다 — 경로를 정하는 자리는
 * 코어 `MessagesListRules.destinations` 하나다. 빠짐없는 when(라우트를 더하면 여기가 컴파일로 막는다 — E§3 규약, else 금지).
 */
object MessagesRouting {
    fun target(route: AingRoute): MessagesRouteTarget? = when (route) {
        AingRoute.Messages -> MessagesRouteTarget.list
        is AingRoute.Message -> MessagesRouteTarget.conversation(route.peerId)
        AingRoute.Now, is AingRoute.Rankings, AingRoute.Games, is AingRoute.MiniGame,
        AingRoute.GomokuLobby, is AingRoute.GomokuInvite, is AingRoute.GomokuMatch,
        AingRoute.ChessLobby, is AingRoute.ChessInvite, is AingRoute.ChessMatch,
        AingRoute.Me, AingRoute.Shop, is AingRoute.Feedback, AingRoute.Settings -> null
    }

    /** 메시지 탭 경로 원소 → 셸 목적지. */
    fun dest(destination: MessagesDestination): Any = when (destination) {
        is MessagesDestination.conversation -> Dest.Conversation(destination.peerID)
    }

    /** 라우트 → 메시지 탭 뿌리(목록) 위에 쌓을 목적지들. 메시지 탭 라우트가 아니면 null(목록 = 빈 목록). */
    fun children(route: AingRoute): List<Any>? = MessagesListRules.destinations(target(route))?.map(::dest)
}

/**
 * 신고 대상 글자(Dest.ReportSheet(subjectId) 의 값). 사람: `p:<peer>` · 메시지 한 건: `m:<peer>:<message>`.
 * id 는 uuid(영문·숫자·-)라 `:` 가 끼지 않는다 — 그 밖의 모양은 null(시트를 열지 않는다).
 */
object ReportSubject {
    fun person(peerID: String): String = "p:$peerID"

    fun message(peerID: String, messageID: String): String = "m:$peerID:$messageID"

    data class Decoded(val peerID: String, val messageID: String?)

    fun decode(subject: String): Decoded? {
        val parts = subject.split(':')
        return when {
            parts.size == 2 && parts[0] == "p" && parts[1].isNotEmpty() -> Decoded(parts[1], null)
            parts.size == 3 && parts[0] == "m" && parts[1].isNotEmpty() && parts[2].isNotEmpty() -> Decoded(parts[1], parts[2])
            else -> null
        }
    }

    /** 신고 대상 값(이름은 스토어가 아는 것 — 모르면 대화 머리 폴백, 메시지 본문은 이력에서). */
    fun target(store: MessagesStore, subject: String): MessagesReportTarget? {
        val decoded = decode(subject) ?: return null
        val name = store.peerName(decoded.peerID) ?: MessagesConversationHeader.fallbackTitle
        val body = decoded.messageID?.let { id -> store.history.firstOrNull { it.id == id }?.body }
        return MessagesReportTarget(decoded.peerID, name, decoded.messageID, body)
    }
}

/** 메시지 탭 뿌리(Dest.MessagesList). [open] 은 목적지를 쌓는다(NavGraph 의 open). */
@Composable
fun MessagesListEntry(store: MessagesStore, open: (Any) -> Unit, modifier: Modifier = Modifier) {
    MessagesListScreen(
        store = store,
        onOpen = { peer -> open(Dest.Conversation(peer)) },
        onNewConversation = { open(Dest.NewConversationSheet) },
        onMegaphone = { open(Dest.MegaphoneSheet) },
        modifier = modifier,
    )
}

/**
 * 대화(Dest.Conversation). [back] 은 한 칸 뒤로, [leaveToList] 는 차단·"신고하면서 차단" 뒤 목록으로 빠져나온다(그 대화는 이미 숨었다).
 * 신고·차단 시트는 이 화면이 직접 띄운다(ModalBottomSheet — 세 입구 중 ①②).
 */
@Composable
fun ConversationEntry(store: MessagesStore, peerId: String, back: () -> Unit, leaveToList: () -> Unit, modifier: Modifier = Modifier) {
    ConversationScreen(store, peerId, onBack = back, onLeave = leaveToList, modifier = modifier)
}

/** 새 대화 시트(Dest.NewConversationSheet). 사람을 고르면 시트를 닫고 그 대화를 연다. */
@Composable
fun NewConversationSheetEntry(store: MessagesStore, open: (Any) -> Unit, dismiss: () -> Unit) {
    MessagesNewConversationSheet(store, onSelect = { peer ->
        dismiss()
        open(Dest.Conversation(peer))
    }, onClose = dismiss)
}

/** 확성기 시트(Dest.MegaphoneSheet). [rubyBalance] 는 오목·체스·상점과 같은 미러(W2-c RubyBalanceMirror — 조립이 넘긴다). */
@Composable
fun MegaphoneSheetEntry(store: MessagesStore, rubyBalance: Long?, dismiss: () -> Unit) {
    MessagesMegaphoneSheet(store, rubyBalance, onClose = dismiss)
}

/**
 * 신고 시트(Dest.ReportSheet(subjectId)) — 바깥 입구(오목 채팅 서랍 ⋮ · W4-a)가 목적지로 열 때. 대상 글자는 [ReportSubject].
 * 모양이 틀린 글자면 아무것도 그리지 않고 닫는다.
 */
@Composable
fun ReportSheetEntry(store: MessagesStore, subjectId: String, dismiss: () -> Unit, leaveToList: () -> Unit) {
    val target = ReportSubject.target(store, subjectId)
    if (target == null) {
        androidx.compose.runtime.LaunchedEffect(subjectId) { dismiss() }
        return
    }
    MessagesReportSheet(store, target, onSent = { blocked ->
        dismiss()
        if (blocked) leaveToList()
    }, onClose = dismiss)
}

/** 차단 확인(Dest.BlockConfirm(peerId)). **차단을 부르는 곳은 이 확인 하나다.** */
@Composable
fun BlockConfirmEntry(store: MessagesStore, peerId: String, dismiss: () -> Unit, leaveToList: () -> Unit) {
    MessagesBlockConfirmSheet(
        peerName = store.peerName(peerId) ?: MessagesConversationHeader.fallbackTitle,
        onConfirm = {
            dismiss()
            store.blockPeer(peerId)
            leaveToList()
        },
        onClose = dismiss,
    )
}
