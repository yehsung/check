// 원본: Sources/CheckMobileKit/Games/GamesComponents.swift @ 3bd04bd
//
// 오목·체스 화면이 같이 쓰는 조각(Swift `GamesComponents.swift` 의 화면 몫 — 관전자 수 칸 · 판돈 줄 · 나 · 내비 머리 대신 쓰는 머리 줄)과
// iOS 공용 부품(InsetGroup · GroupRow · SectionHeader · AingButton · PersonAvatar · InlineNotice · LoadFailureRow · LoadingRow ·
// AingConfirmSheet)의 **이 갈래 몫 Compose 판**. 공용 부품 갈래(W3)가 같은 것을 내면 통합 때 그쪽으로 접는다(보고 미해결).
//
// 규약:
//  · 판정은 여기서 하지 않는다 — 스토어·순수 표(core/stores)가 한다(K8, E§3 끝). 여기는 배치와 색 토큰만.
//  · 색은 AingTheme.colors 토큰(화면 갈래 규약 · D5 의 뜻) — 판(나무·말)처럼 '물건'인 그림만 자기 상수를 든다(판 파일들).
//  · 초 단위로 바뀌는 글자는 잎 컴포저블만 시계를 읽는다(Swift `TimelineView` 잎 규약 — [rememberTicker]).
//  · 시트·확인은 **화면 안 덮개**로 그린다(새 창·새 목적지가 아니다) — 오목·체스는 "한 화면 안 탭"이라 자식 목적지를 밀면 화면이
//    사라져 폴링이 죽는다(E§4.4 · Swift GamesChessScreen 머리말). 덮개가 떠 있어도 화면은 그대로 컴포지션에 남는다.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.games.GamesWatcherCount
import com.yehsung.aingcheck.ui.components.ModalPresenceMark
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.components.PortraitBadge
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberPortraitArt
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import com.yehsung.aingcheck.ui.screens.session.kit.AvatarFace
import com.yehsung.aingcheck.ui.screens.messages.LocalBlockReportPlatform
import com.yehsung.aingcheck.core.wire.models.AppUserAvatar
import com.yehsung.aingcheck.core.wire.SwiftURL

// MARK: - 나 · 그림 · 시계

/**
 * 게임 화면이 그리는 '나'(Swift `GamesMeIdentity`) — 착용 캐릭터 · 표정 · 이름. **새 서버 호출 없이** 조립 지점이 다른 탭 스토어가 이미 아는
 * 값으로 만든다(나 탭 착용 · 지금 탭 내 카드 · 위젯 스냅숏). [name] 이 null 이면 화면이 "나"로 접는다.
 */
data class BoardGameMe(val name: String?, val characterID: String?, val mood: CharacterMood) {
    companion object {
        val unknown: BoardGameMe = BoardGameMe(null, null, CharacterMood.Plain)
    }
}

/**
 * 그림 출처(초상 · 루비). 앱은 Compose 리소스에서 비동기로 읽고([Live]), 스냅숏 시험은 저장소 원본을 동기로 넣는다(같은 장면을 세 번 그려
 * 픽셀이 같아야 한다 — 비동기 적재는 그 판정을 흔든다).
 */
class BoardGameArt(
    val portrait: @Composable (id: String, expression: CharacterExpression) -> ImageBitmap?,
    val ruby: @Composable (pointSize: Float) -> ImageBitmap?,
) {
    companion object {
        val Live: BoardGameArt = BoardGameArt(
            portrait = { id, expression -> rememberPortraitArt(id, expression) },
            ruby = { size -> rememberRubyArt(size) },
        )
    }
}

val LocalBoardGameArt = staticCompositionLocalOf { BoardGameArt.Live }

/** 초상 id 가 없으면 아잉으로 접는다(Swift `CharacterPortrait(id: nil)` 의 폴백). */
const val FALLBACK_CHARACTER_ID: String = "aing"

/**
 * 잎 시계 펌프(Swift `TimelineView(.periodic(by:))` 자리). 돌려주는 값을 **읽는 컴포저블만** [periodMillis] 마다 다시 그린다.
 * 값 자체는 뜻이 없다 — 시각은 언제나 **스토어 시계**(`store.clock()`)로 읽는다(Swift 잎 뷰 규약: `context.date` 를 쓰지 않는다).
 * [running] 이 거짓이면 한 번도 깨지 않는다(멈춘 시계 · 끝난 판 — 배터리).
 */
@Composable
fun rememberTicker(running: Boolean = true, periodMillis: Long = 1_000L): Int {
    var tick by remember { mutableIntStateOf(0) }
    if (running) {
        LaunchedEffect(periodMillis) {
            while (true) {
                delay(periodMillis)
                tick += 1
            }
        }
    }
    return tick
}

// MARK: - 글자 모양(iOS 스타일 → M3 역할 · AingTypography 표)

object BoardText {
    /** iOS rowTitle(callout 16 semibold). */
    @Composable fun rowTitle(): TextStyle = MaterialTheme.typography.titleSmall
    /** iOS rowSubtitle · footnote(13). */
    @Composable fun rowSubtitle(): TextStyle = MaterialTheme.typography.bodySmall
    /** iOS subheadline(15). */
    @Composable fun subheadline(): TextStyle = MaterialTheme.typography.bodyMedium
    /** iOS headline(17 semibold). */
    @Composable fun headline(): TextStyle = MaterialTheme.typography.titleMedium
    /** iOS caption(12). */
    @Composable fun caption(): TextStyle = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal)
    /** iOS title2(22 bold). */
    @Composable fun title2(): TextStyle = MaterialTheme.typography.headlineSmall
    /** iOS title3(20 bold) — 절 머리. */
    @Composable fun title3(): TextStyle = MaterialTheme.typography.titleLarge
    /** 고정폭 숫자(Swift `.monospacedDigit()`). */
    fun digits(style: TextStyle): TextStyle = style.copy(fontFeatureSettings = "tnum")
}

// MARK: - 묶음 · 줄 · 머리

/** 인셋 그룹 카드(Swift `InsetGroup`). */
@Composable
fun BoardGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val colors = AingTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(AingDimens.groupRadius)),
        content = content,
    )
}

/** 그룹 안 한 줄(Swift `GroupRow`). [divider] 가 있으면 아래에 머리카락 선을 [dividerInset] 만큼 들여 긋는다. */
@Composable
fun BoardRow(
    modifier: Modifier = Modifier,
    divider: Boolean = false,
    dividerInset: Dp = AingDimens.cardPadding,
    minHeight: Dp = AingDimens.rowHeight,
    highlighted: Boolean = false,
    padding: PaddingValues = PaddingValues(horizontal = AingDimens.cardPadding, vertical = 10.dp),
    content: @Composable RowScope.() -> Unit,
) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxWidth().let { if (highlighted) it.background(colors.accentTint) else it }) {
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = minHeight).padding(padding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
            content = content,
        )
        if (divider) {
            Box(Modifier.padding(start = dividerInset).fillMaxWidth().height(AingDimens.hairline).background(colors.separator))
        }
    }
}

/** 절 머리(Swift `SectionHeader(padded: true)`): 제목 + 오른쪽 회색 글 또는 글자 단추. [actionHint] 는 글자 단추의 보이스오버 힌트(누름 이름표). */
@Composable
fun BoardSectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    trailing: String? = null,
    action: Pair<String, () -> Unit>? = null,
    actionHint: String? = null,
    actionTag: String? = null,
) {
    val colors = AingTheme.colors
    Row(
        modifier.fillMaxWidth().padding(start = AingDimens.titleMargin - AingDimens.sideMargin, end = 4.dp, top = 22.dp, bottom = 8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Text(title, style = BoardText.title3(), color = colors.label, modifier = Modifier.weight(1f).semantics { heading() })
        if (trailing != null) {
            Text(trailing, style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2, maxLines = 1)
        }
        if (action != null) {
            Text(
                action.first,
                style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold),
                color = colors.accent,
                modifier = Modifier.clickable(onClickLabel = actionHint, onClick = action.second).padding(horizontal = 4.dp, vertical = 4.dp)
                    .let { if (actionTag != null) it.testTag(actionTag) else it },
            )
        }
    }
}

/** 회색 캡션 한 줄(절 아래 · 머리 여백에 맞춘다). */
@Composable
fun BoardCaption(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = BoardText.rowSubtitle(),
        color = AingTheme.colors.label2,
        modifier = modifier.fillMaxWidth().padding(start = AingDimens.titleMargin - AingDimens.sideMargin, top = AingDimens.space2),
    )
}

/** 안내 한 줄(Swift `InlineNotice`) — 글자는 label, 뜻은 기호·바탕이 낸다(틴트 위 틴트 글자는 대비가 떨어진다). */
@Composable
fun BoardNotice(text: String, modifier: Modifier = Modifier, warning: Boolean = true) {
    val colors = AingTheme.colors
    val tint = if (warning) colors.pending else colors.accent
    Row(
        modifier
            .fillMaxWidth()
            .background(tint.copy(alpha = 0.12f), RoundedCornerShape(AingDimens.innerRadius))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        AingIcon(if (warning) AppIcon.WarningFill else AppIcon.InfoFill, contentDescription = null, size = 18.dp, tint = tint)
        Text(text, style = BoardText.rowSubtitle(), color = colors.label, modifier = Modifier.weight(1f))
    }
}

/** 불러오기 실패 한 줄 + [다시 시도](Swift `LoadFailureRow`). [onRetry] 가 null 이면 단추 없이 한 줄만. */
@Composable
fun BoardLoadFailure(text: String, onRetry: (() -> Unit)?) {
    val colors = AingTheme.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = BoardText.subheadline(), color = colors.label2, modifier = Modifier.weight(1f))
        if (onRetry != null) {
            BoardButton("다시 시도", kind = BoardButtonKind.Plain, onClick = onRetry)
        }
    }
}

/** 불러오는 중 한 줄(Swift `LoadingRow`). 회전자는 두지 않는다 — 스냅숏이 흔들리지 않게(글자로 말한다). */
@Composable
fun BoardLoading(text: String) {
    Text(text, style = BoardText.subheadline(), color = AingTheme.colors.label2)
}

// MARK: - 단추

enum class BoardButtonKind { Filled, Tinted, Gray, Destructive, Plain }

/**
 * 단추(Swift `AingButton`). 채운 단추는 화면당 하나라는 iOS 규약을 따른다(수락·신청·다시 신청). 누름 영역은 44 이상([AingDimens.minimumTarget]).
 * [hint] 는 Swift `.accessibilityHint` 자리 — Android 에서는 누름 동작의 이름표(TalkBack "두 번 탭하여 ○○")로 싣는다. 바깥 semantics 가 안쪽
 * clickable 의 이름 없는 누름을 덮는다(같은 노드의 같은 열쇠는 바깥이 이긴다 — 시험 `…HintsReachTheClickLabel` 이 잰다).
 */
@Composable
fun BoardButton(
    text: String,
    modifier: Modifier = Modifier,
    kind: BoardButtonKind = BoardButtonKind.Tinted,
    enabled: Boolean = true,
    fillsWidth: Boolean = false,
    small: Boolean = false,
    icon: AppIcon? = null,
    testTag: String? = null,
    hint: String? = null,
    onClick: () -> Unit,
) {
    val colors = AingTheme.colors
    val (container, content) = when (kind) {
        BoardButtonKind.Filled -> colors.accentFill to colors.onAccentFill
        BoardButtonKind.Tinted -> colors.accentTint to colors.accent
        BoardButtonKind.Gray -> colors.fill to colors.label
        BoardButtonKind.Destructive -> colors.dangerTint to colors.danger
        BoardButtonKind.Plain -> Color.Transparent to colors.accent
    }
    val base = modifier
        .heightIn(min = AingDimens.minimumTarget)
        .let { if (fillsWidth) it.fillMaxWidth() else it }
        .let { if (testTag != null) it.testTag(testTag) else it }
        .let { if (hint != null && enabled) it.semantics { onClick(label = hint) { onClick(); true } } else it }
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = base,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = container,
            contentColor = content,
            disabledContainerColor = if (kind == BoardButtonKind.Plain) Color.Transparent else colors.fill2,
            disabledContentColor = colors.label3Text,
        ),
        contentPadding = if (small) PaddingValues(horizontal = 14.dp, vertical = 4.dp) else PaddingValues(horizontal = 18.dp, vertical = 10.dp),
        elevation = null,
    ) {
        if (icon != null) {
            AingIcon(icon, contentDescription = null, size = 18.dp)
            Spacer(Modifier.width(6.dp))
        }
        Text(
            text,
            style = if (small) BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold) else MaterialTheme.typography.labelLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// MARK: - 사람

/**
 * 사람 아바타(Swift `PersonAvatar(name:colorSeed:status:url:userID:size:)` — 로비 GamesGomokuScreen.swift:398·443·528): 사진 → 착용 캐릭터 →
 * 이니셜 원 + 근무 중 점. 착용 캐릭터는 조립이 흘린 표([LocalAppUserCharacters])를 [seed](= 사용자 id — 모든 호출부가 user.id 를 넘긴다)로 찾는다.
 * 표가 이 사람을 모를 때만 이니셜(8c 04: 메시지 화면에선 캐릭터인 사람이 로비에선 이니셜로 보였다).
 */
@Composable
fun BoardAvatar(name: String, seed: String, size: Dp, modifier: Modifier = Modifier, working: Boolean = false, url: String? = null) {
    val colors = AingTheme.colors
    val avatar = LocalAppUserCharacters.current.avatar(seed, url?.let { SwiftURL.parse(it) })
    Box(modifier.size(size).semantics(mergeDescendants = true) { contentDescription = name }) {
        if (avatar is AppUserAvatar.Initials) {
            val (ink, tint) = colors.avatar(seed)
            val initial = name.trim().firstOrNull()?.toString() ?: "?"
            Box(Modifier.fillMaxSize().background(tint, CircleShape), contentAlignment = Alignment.Center) {
                Text(initial, color = ink, fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            }
        } else {
            AvatarFace(avatar, name, size, colorSeed = seed)
        }
        if (working) {
            val dot = (size.value * 0.28f).coerceIn(8f, 12f).dp
            Box(
                Modifier.align(Alignment.BottomEnd).size(dot)
                    .border(2.dp, colors.surface, CircleShape)
                    .background(colors.workingDot, CircleShape),
            )
        }
    }
}

/** 이름 + 센터 배지 + '나' 칩(Swift `PersonName`). [center] 는 **화면 글자**("서울") — 코어 경계가 한 번만 옮겼다. */
@Composable
fun BoardPersonName(name: String, modifier: Modifier = Modifier, center: String? = null, isMe: Boolean = false) {
    val colors = AingTheme.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(name.ifEmpty { "—" }, style = BoardText.rowTitle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false))
        if (!center.isNullOrEmpty()) BoardChip(center)
        if (isMe) BoardChip("나", accent = true)
    }
}

@Composable
fun BoardChip(text: String, accent: Boolean = false) {
    val colors = AingTheme.colors
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = if (accent) colors.accent else colors.label2,
        modifier = Modifier.background(if (accent) colors.accentTint else colors.fill, CircleShape).padding(horizontal = 6.dp, vertical = 2.dp),
        maxLines = 1,
    )
}

/** 캐릭터 초상 + 돌 배지(Swift `CharacterPortrait(id:mood:size:badge: .stone)`). [stoneIsBlack] 이 null 이면 배지 없음(색을 모른다). */
@Composable
fun BoardPortrait(characterID: String?, mood: CharacterMood, size: Dp, stoneIsBlack: Boolean?, modifier: Modifier = Modifier) {
    val art = LocalBoardGameArt.current.portrait(characterID ?: FALLBACK_CHARACTER_ID, mood.expression)
    CharacterPortrait(art, mood, size, modifier, badge = stoneIsBlack?.let { PortraitBadge.Stone(it) } ?: PortraitBadge.None)
}

// MARK: - 루비 · 판돈 · 관전자 수

/** 보석 하나(공용 [RubyIcon] + 그림 출처). */
@Composable
fun BoardRuby(size: Dp, modifier: Modifier = Modifier) {
    RubyIcon(LocalBoardGameArt.current.ruby(size.value), size, modifier)
}

/**
 * 판돈 한 줄 "판돈 [보석]5 · 이기면 +5"(Swift `GamesStakeLine`). [suffix] 는 **내 판에만** 붙인다 — 남의 판(관전 · 지금 대결 중 줄)은 액수만
 * (관전자는 그 판에서 한 푼도 얻지 못한다).
 */
@Composable
fun BoardStakeLine(stake: Long, modifier: Modifier = Modifier, prefix: String? = "판돈", suffix: String? = null, gemSize: Dp = 14.dp, style: TextStyle? = null, color: Color? = null) {
    val textStyle = BoardText.digits(style ?: BoardText.rowSubtitle())
    val ink = color ?: AingTheme.colors.label2
    Row(
        modifier.clearAndSetSemantics { contentDescription = "${prefix ?: ""} 루비 $stake${suffix ?: ""}".trim() },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (prefix != null) Text("$prefix ", style = textStyle, color = ink, maxLines = 1)
        BoardRuby(gemSize)
        Text("$stake${suffix ?: ""}", style = textStyle, color = ink, maxLines = 1)
    }
}

/**
 * 관전자 수 한 칸(눈 + 수 — Swift `GamesWatcherBadge`). **판정은 [GamesWatcherCount] 하나**이고 이 컴포저블은 배치만 한다.
 * INV-GamesComponents-a97937fd 이식: 그리는가를 **부르는 쪽이 또 묻지 않게** 이 칸이 스스로 접는다(`shows` 가 거짓이면 아무것도 안 그린다) —
 *   부르는 쪽이 같은 술어를 볼 때도 그 술어는 같은 한 함수([GamesWatcherCount.shows])다.
 * 애니메이션 금지(2초 폴링마다 숫자가 튀면 거슬린다 — 값만 갈린다). 접근성은 "관전자 N명" 한 덩이.
 */
@Composable
fun WatcherBadge(count: Long, modifier: Modifier = Modifier, style: TextStyle? = null, tint: Color? = null) {
    val value = count.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
    if (!GamesWatcherCount.shows(value)) return
    val ink = tint ?: AingTheme.colors.label2
    val textStyle = BoardText.digits(style ?: BoardText.rowSubtitle())
    Row(
        modifier.clearAndSetSemantics { contentDescription = GamesWatcherCount.accessibilityLabel(value) }.testTag("watcher-badge"),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AingIcon(AppIcon.VisibilityFill, contentDescription = null, size = (textStyle.fontSize.value + 1).dp, tint = ink)
        Text(GamesWatcherCount.text(value), style = textStyle, color = ink, maxLines = 1)
    }
}

/** 결과 루비 변화 — 이기면 초록 +N, 지면 빨강 −N(보석 50%), 비기면 ±0. 글자는 순수 표가 만든다([text]). */
@Composable
fun BoardRubyDelta(delta: Long, text: String, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(
        modifier.clearAndSetSemantics { contentDescription = "루비 $text" }.testTag("ruby-delta"),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BoardRuby(24.dp, Modifier.alpha(if (delta < 0) 0.5f else 1f))
        Text(
            text,
            style = BoardText.digits(BoardText.title2()),
            color = when {
                delta > 0 -> colors.working
                delta < 0 -> colors.danger
                else -> colors.label
            },
        )
    }
}

/** 요약 두 칸(전적 · 내 루비 — Swift 로비 `summary`). */
@Composable
fun BoardSummary(leftTitle: String, leftValue: String, rightTitle: String, rubyBalance: Long?, leftDescription: String? = null) {
    val colors = AingTheme.colors
    BoardGroup {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Column(
                Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp)
                    .let { m -> if (leftDescription != null) m.clearAndSetSemantics { contentDescription = leftDescription } else m },
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(leftTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                Text(leftValue, style = BoardText.digits(BoardText.headline()), color = colors.label)
            }
            Box(Modifier.width(AingDimens.hairline).fillMaxHeight().background(colors.separator))
            Column(
                Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(rightTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                if (rubyBalance != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                        BoardRuby(20.dp)
                        Text("$rubyBalance", style = BoardText.digits(BoardText.headline()), color = colors.label)
                    }
                } else {
                    Text("–", style = BoardText.headline(), color = colors.label)
                }
            }
        }
    }
}

// MARK: - 덮개(시트 · 확인)

/**
 * 판 시트(Swift `.sheet` 자리). 바깥(검정 막 [BoardSheetScrim])을 누르면 [onDismiss]. Android 앱은 창 전체에 띄운다(상태 바 · 탭 막대까지 덮는다 —
 * [BoardSheetHost]). **새 목적지가 아니다** — 아래 화면은 컴포지션에 그대로 남는다(오목·체스 한 화면 규약 · 폴링이 살아 있다).
 */
@Composable
fun BoxScope.BoardSheetOverlay(
    title: String,
    onDismiss: (() -> Unit)?,
    subtitle: String? = null,
    testTag: String = "board-sheet",
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = AingTheme.colors
    BoardSheetHost(onDismiss, colors.background, testTag) { Column(Modifier.fillMaxWidth().padding(bottom = AingDimens.space3)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (onDismiss != null) {
                Box(
                    Modifier.size(AingDimens.minimumTarget).clickable(onClick = onDismiss).semantics { contentDescription = "닫기" },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(32.dp).background(colors.fill, CircleShape), contentAlignment = Alignment.Center) {
                        AingIcon(AppIcon.Close, contentDescription = null, size = 18.dp, tint = colors.label)
                    }
                }
            }
            Column(Modifier.weight(1f).padding(horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(title, style = BoardText.headline(), color = colors.label, modifier = Modifier.semantics { heading() })
                if (subtitle != null) Text(subtitle, style = BoardText.rowSubtitle(), color = colors.label2, maxLines = 2)
            }
            if (onDismiss != null) Spacer(Modifier.size(AingDimens.minimumTarget))
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(AingDimens.space4), content = content)
    } }
}

/**
 * 확인 덮개(Swift `AingConfirmSheet`) — 불투명 카드라 뒤 색을 빨아들이지 않는다(iOS 알림창 대비 1.9:1 의 교훈). [확인]은 위험 색, [취소]는 회색.
 * 판 시트([BoardSheetHost])와 같은 자리 규칙: Android 앱은 따로 뜬 창(막이 상태 바 · 탭 막대까지), 데스크톱 · 판 스냅숏은 화면 안 덮개.
 * 뒤로 가기 · 카드 바깥 누름은 어느 쪽이든 [onCancel].
 */
@Composable
fun BoxScope.BoardConfirmOverlay(
    title: String,
    message: String,
    confirmTitle: String,
    cancelTitle: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    testTag: String = "board-confirm",
) {
    val card: @Composable (Modifier) -> Unit = { modifier ->
        BoardConfirmCard(title, message, confirmTitle, cancelTitle, onConfirm, onCancel, testTag, modifier)
    }
    if (LocalBoardSheetsInWindow.current) {
        ModalPresenceMark()
        BoardConfirmWindow(onCancel) {
            // 창은 카드 높이만큼이다 — 카드 둘레 여백도 막 누름과 같게 닫는다(창 바깥 누름은 대화상자가 onCancel 로 준다).
            Box(
                Modifier.fillMaxWidth().clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onCancel() },
                contentAlignment = Alignment.Center,
            ) { card(Modifier) }
        }
        return
    }
    Box(
        Modifier.matchParentSize().background(BoardSheetScrim)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onCancel() },
    )
    card(Modifier.align(Alignment.Center))
}

@Composable
private fun BoardConfirmCard(
    title: String,
    message: String,
    confirmTitle: String,
    cancelTitle: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    testTag: String,
    modifier: Modifier,
) {
    val colors = AingTheme.colors
    Column(
        modifier.padding(AingDimens.space6).widthIn(max = 420.dp).fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(28.dp))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .padding(AingDimens.space6)
            .testTag(testTag),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space3),
    ) {
        Text(title, style = BoardText.headline(), color = colors.label, modifier = Modifier.semantics { heading() })
        Text(message, style = BoardText.subheadline(), color = colors.label2)
        Spacer(Modifier.height(4.dp))
        BoardButton(confirmTitle, kind = BoardButtonKind.Destructive, fillsWidth = true, testTag = "$testTag-confirm", onClick = onConfirm)
        BoardButton(cancelTitle, kind = BoardButtonKind.Gray, fillsWidth = true, testTag = "$testTag-cancel", onClick = onCancel)
    }
}

/**
 * 바깥 부품(메시지 탭의 신고·차단 시트 — 조립이 넣는다)을 **화면 안 덮개**로 띄우는 틀: 어두운 막 + 아래쪽 카드. 머리(✕)는 들어오는 시트가 제 것을 든다.
 * 목적지(Dest.ReportSheet 등)로 밀지 않는 까닭은 [BoardSheetOverlay] 와 같다 — 대국 화면이 컴포지션에서 빠지면 폴링·관전이 죽는다(E§4.4 · G ②).
 * [onDismiss] 가 null 이면 막을 눌러도 닫지 않는다(보내는 중인 신고를 막 누름 하나로 버리지 않게 — 닫기는 시트의 ✕ 하나).
 */
@Composable
fun BoxScope.BoardSheetFrame(onDismiss: (() -> Unit)?, testTag: String, content: @Composable () -> Unit) {
    BoardSheetHost(onDismiss, AingTheme.colors.surface, testTag, content)
}

/**
 * 차단 확인(Swift `MessagesBlockConfirmSheet` — 메시지 탭과 **같은 문구**): 무엇이 막히는지 세 줄 → 무엇이 안 막히는지 한 줄 → 되돌릴 수 있다는 한 줄 → [차단하기].
 * 문구는 한 벌(`BlockReportText` · 판은 [LocalBlockReportPlatform] — 기본 폰, Windows 는 맥)에서만 온다. 차단을 부르는 곳은 이 확인의 [onConfirm] 하나다 — 확인 없는 차단은 만들지 않는다(차단은 상대에게
 * 알리지 않는 조용한 동작이라 잘못 눌러도 알아챌 신호가 없다). 메시지 탭 시트(W3-a `MessagesBlockConfirmSheet`)가 서면 조립이
 * [BoardGameSafety.blockConfirmSheet] 로 그것을 넣는다 — 이것은 그 자리의 기본값이다(assembly.md).
 */
@Composable
fun BoardBlockConfirmSheet(peerName: String, onConfirm: () -> Unit, onClose: () -> Unit) {
    val colors = AingTheme.colors
    val items = BlockReportText.blockConfirmItems(LocalBlockReportPlatform.current)
    Column(Modifier.fillMaxWidth().padding(bottom = AingDimens.space3)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(AingDimens.minimumTarget).clickable(onClick = onClose).semantics { contentDescription = "닫기" },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(32.dp).background(colors.fill, CircleShape), contentAlignment = Alignment.Center) {
                    AingIcon(AppIcon.Close, contentDescription = null, size = 18.dp, tint = colors.label)
                }
            }
            Text(BlockReportText.blockAction, style = BoardText.headline(), color = colors.label, textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).semantics { heading() })
            Spacer(Modifier.size(AingDimens.minimumTarget))
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing)) {
            Text(BlockReportText.blockConfirmTitle(peerName), style = BoardText.headline(), color = colors.label,
                modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).semantics { heading() })
            BoardGroup(Modifier.background(colors.background, RoundedCornerShape(AingDimens.groupRadius)).semantics(mergeDescendants = true) {
                contentDescription = "차단하면: " + items.joinToString(", ")
            }) {
                items.forEachIndexed { index, item ->
                    BoardRow(divider = index != items.size - 1, dividerInset = AingDimens.cardPadding + 24.dp + AingDimens.space3) {
                        AingIcon(AppIcon.Block, contentDescription = null, size = 22.dp, tint = colors.danger)
                        Text(item, style = BoardText.subheadline(), color = colors.label, modifier = Modifier.weight(1f))
                    }
                }
            }
            Text(BlockReportText.blockConfirmScopeNote, style = BoardText.rowSubtitle(), color = colors.label2,
                modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin))
            Text(BlockReportText.blockConfirmUndoNote(LocalBlockReportPlatform.current), style = BoardText.rowSubtitle(), color = colors.label2,
                modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin))
            BoardButton(BlockReportText.blockConfirm, Modifier.padding(top = 4.dp), kind = BoardButtonKind.Destructive, fillsWidth = true,
                testTag = BoardSafetyTags.blockConfirm, onClick = onConfirm)
        }
    }
}

/** 대국 채팅 신고·차단 덮개의 표지(시험·조립이 잡는다). */
object BoardSafetyTags {
    const val menu = "gomoku-chat-safety"
    const val menuReport = "gomoku-chat-report"
    const val menuBlock = "gomoku-chat-block"
    const val blockSheet = "board-block-sheet"
    const val blockConfirm = "board-block-confirm"
    const val reportSheet = "board-report-sheet"
}

/**
 * 같은 게임 화면이 **겹쳐 조성되는** 동안의 셈(Android 몫 — iOS 는 내비 스택이 같은 화면을 둘 세우지 않는다).
 * 알림·딥링크로 같은 목적지가 한 번 더 쌓이면 새 화면이 나타난 **뒤에** 옛 화면이 내려간다(내비 전환은 둘을 함께 조성했다가 옛것을 뺀다).
 * 화면 수명 훅(`gomokuScreenDidAppear`·`DidDisappear`)은 불리언이라 옛 화면의 내려감이 새 화면의 창 표시·폴링을 끈다 — 그래서 **마지막 하나가
 * 내려갈 때만** 내려감 훅과 탭 막대 되돌림을 부른다. 열쇠는 게임 탭 스토어(조립에 한 벌) + 게임 이름. 조성 효과는 메인 스레드 하나에서만 돈다.
 */
internal object BoardScreenPresence {
    private val counts = HashMap<Pair<Any, String>, Int>()

    /** 하나 늘린다. */
    fun enter(owner: Any, game: String) {
        val key = owner to game
        counts[key] = (counts[key] ?: 0) + 1
    }

    /** 하나 줄인다. 마지막 하나였으면 true(내려감 훅을 불러야 한다). */
    fun leave(owner: Any, game: String): Boolean {
        val key = owner to game
        val left = (counts[key] ?: 0) - 1
        return if (left <= 0) { counts.remove(key); true } else { counts[key] = left; false }
    }
}

/**
 * 햅틱 계기(Swift `.sensoryFeedback(_, trigger:)` 의 Android 판). Swift 는 **값이 바뀔 때만** 울린다(나타날 때는 안 울린다) — 같은 규칙으로
 * 처음 본 값은 변화로 세지 않는다.
 *  - [moved]: 같은 판에서 수 번호가 바뀌었다(오목 판 캔버스 `trigger: match.moveCount` — 대국 단계에서만).
 *  - [ended]: 같은 판이 '안 끝남 → 끝남'으로 바뀌었다(체스 대국 `trigger: match.isFinished`). 오목 결과는 Swift 가 `trigger: match.id` 라 결과 화면이 선
 *    순간에는 울리지 않는다 — Android 는 체스와 같은 '보는 동안 끝났다' 한 계기로 맞춘다(이김 = 확인 · 그 밖 = 거절 — Swift `.success`·`.warning`).
 */
internal class BoardMatchFeedback {
    private var moveMatchID: String? = null
    private var lastMoveCount: Int? = null
    private var endMatchID: String? = null
    private var lastFinished: Boolean? = null

    fun moved(matchID: String?, moveCount: Int?, playing: Boolean): Boolean {
        val changed = playing && matchID != null && matchID == moveMatchID && lastMoveCount != null && moveCount != lastMoveCount
        moveMatchID = matchID
        lastMoveCount = moveCount
        return changed
    }

    fun ended(matchID: String?, isFinished: Boolean?): Boolean {
        val changed = matchID != null && matchID == endMatchID && lastFinished == false && isFinished == true
        endMatchID = matchID
        lastFinished = isFinished
        return changed
    }
}
