// 원본: Sources/CheckMobileKit/Messages/MegaphoneBannerOverlay.swift @ a6791165(57810a8e) — 확성기 배너 · 위에서 내려오는 카드
// 계약: docs/plan/megaphone-banner-contract.md — 폰 배너
//
// - 자리: 셸(SignedInTabs)의 탭 화면 위 한 곳. **상태바 아래**(statusBarsPadding — 상태바·카메라 구멍을 덮지 않는다) · 좌우 16dp.
// - 모양: 둥근 카드(아바타 · 닉네임 · 📢 · 본문 4줄 · [답장] [닫기]). 내 배너는 [답장] 이 없다.
// - 손: **카드에만** 손짓을 단다 — 카드 밖 터치는 그대로 아래 화면으로 지나간다(게임 캔버스 제스처를 먹지 않는다).
//   누르고 있는 동안 멈춘다(pauseTimer) · 위로 쓸면 닫힌다(판정은 MegaphoneBannerPhoneRules) · 아니면 다시 센다(resumeTimer).
// - 동작: 0.25초 내려오기 / 0.2초 올라가기(이동만 — 불투명도는 건드리지 않는다). 시스템 '애니메이션 삭제'면 Compose 가 길이를 0 으로 접는다.
// 판정(미룸 · [답장] 라우트 · 쓸기 문턱)은 feature/phone 에 있다 — 이 파일은 그리기와 손짓만 한다.
package com.yehsung.aingcheck.android.shell

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.text.MegaphoneBanner
import com.yehsung.aingcheck.core.rules.text.MegaphoneText
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.feature.phone.messages.MegaphoneBannerPhoneRules
import com.yehsung.aingcheck.feature.phone.messages.MegaphoneBannerPhoneText
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.roundToInt

/** 시험이 찾는 이름표. */
object MegaphoneBannerTags {
    const val CARD = "megaphoneBanner.card"
    const val REPLY = "megaphoneBanner.reply"
    const val CLOSE = "megaphoneBanner.close"
}

/** 좌우 여백(iOS MobileTheme.sideMargin 과 같은 16). */
private val SIDE_MARGIN = 16.dp

/** 확성기 배너 한 장 — [store] 의 current 를 그린다. [onReply] 는 조립의 replyToMegaphoneBanner(대화 열기 + 닫기). */
@Composable
fun MegaphoneBannerOverlay(store: MegaphoneBannerStore, onReply: (MegaphoneBanner) -> Unit, modifier: Modifier = Modifier) {
    val banner = store.current
    // 나가는 동안에도 그 카드를 그린다(current 는 이미 null).
    var shown by remember { mutableStateOf<MegaphoneBanner?>(null) }
    if (banner != null && banner != shown) shown = banner
    val clearance = with(LocalDensity.current) { MegaphoneBannerPhoneRules.topClearance.dp.roundToPx() }
    AnimatedVisibility(
        visible = banner != null,
        modifier = modifier.statusBarsPadding().padding(top = MegaphoneBannerPhoneRules.topGap.dp, start = SIDE_MARGIN, end = SIDE_MARGIN),
        enter = slideInVertically(tween(250)) { height -> -(height + clearance) },
        exit = slideOutVertically(tween(200)) { height -> -(height + clearance) },
    ) {
        shown?.let { BannerCard(it, store, onReply) }
    }
}

@Composable
private fun BannerCard(banner: MegaphoneBanner, store: MegaphoneBannerStore, onReply: (MegaphoneBanner) -> Unit) {
    val density = LocalDensity.current
    var drag by remember(banner.megaphoneID) { mutableFloatStateOf(0f) }
    val colors = AingTheme.colors
    Surface(
        shape = RoundedCornerShape(MegaphoneBannerPhoneRules.cornerRadius.dp),
        color = colors.surface,
        shadowElevation = 8.dp,
        modifier = Modifier
            .fillMaxWidth()
            .offset { IntOffset(0, with(density) { MegaphoneBannerPhoneRules.dragOffset(drag).dp.roundToPx() }) }
            .testTag(MegaphoneBannerTags.CARD)
            .semantics {
                contentDescription = MegaphoneBannerPhoneText.accessibilityLabel(banner.senderName, banner.body) + ". " +
                    MegaphoneBannerPhoneText.accessibilityHint
            }
            // 누르고 있는 동안 멈춘다(놓으면 다시 센다). 버튼 탭은 버튼이 먼저 받는다.
            .pointerInput(banner.megaphoneID) {
                detectTapGestures(onPress = {
                    store.pauseTimer()
                    tryAwaitRelease()
                    store.resumeTimer()
                })
            }
            // 위로 쓸면 닫는다 — 끌린 거리(dp)와 놓는 순간 속도로 본 예측 끝점(속도 × 0.25초)으로 판정한다.
            .pointerInput(banner.megaphoneID) {
                var velocity = 0f
                var lastTime = 0L
                detectVerticalDragGestures(
                    onDragStart = {
                        store.pauseTimer()
                        drag = 0f
                        velocity = 0f
                        lastTime = 0L
                    },
                    onVerticalDrag = { change, amount ->
                        change.consume()
                        val dy = with(density) { amount.toDp().value }
                        drag += dy
                        val now = change.uptimeMillis
                        if (lastTime != 0L && now > lastTime) velocity = dy / ((now - lastTime) / 1000f)
                        lastTime = now
                    },
                    onDragEnd = {
                        val translation = drag
                        drag = 0f
                        if (MegaphoneBannerPhoneRules.swipeDismisses(translation, translation + velocity * 0.25f)) {
                            store.dismissCurrent()
                        } else {
                            store.resumeTimer()
                        }
                    },
                    onDragCancel = {
                        drag = 0f
                        store.resumeTimer()
                    },
                )
            },
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PersonAvatar(name = banner.senderName, userID = banner.senderID, url = banner.senderAvatarURL, size = 32.dp)
                Spacer(Modifier.width(10.dp))
                Text(
                    banner.senderName,
                    color = colors.label,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Spacer(Modifier.width(6.dp))
                Text(MegaphoneText.icon, fontSize = 15.sp)
            }
            Spacer(Modifier.padding(top = 8.dp))
            Text(
                banner.body,
                color = colors.label,
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
                maxLines = MegaphoneBannerPhoneRules.bodyLineLimit,
                overflow = TextOverflow.Ellipsis,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                if (banner.canReply) {
                    TextButton(onClick = { onReply(banner) }, modifier = Modifier.testTag(MegaphoneBannerTags.REPLY)) {
                        Text(MegaphoneBannerPhoneText.reply, color = colors.accent)
                    }
                }
                TextButton(onClick = { store.dismissCurrent() }, modifier = Modifier.testTag(MegaphoneBannerTags.CLOSE)) {
                    Text(MegaphoneBannerPhoneText.close, color = colors.label2)
                }
            }
        }
    }
}
