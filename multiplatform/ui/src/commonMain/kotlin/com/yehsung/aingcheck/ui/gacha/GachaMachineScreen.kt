// 원본: Sources/CheckMobileKit/Me/MeGachaViews.swift @ 3bd04bd (MeGachaMachineScreen — 기계를 폰 전체 화면에)
//
// 캡슐 뽑기 기계를 전체 화면에 띄운다(코어 GachaMachineView — 맥 뽑기 창과 같은 기계 · 같은 그림).
//  - 뽑기: 손잡이 한 바퀴 = `store.pullGachaForMachine()` 한 번(요청 id · 세대 가드 · 루비 미러 · 다시 읽기는 카드와 같은 몸통 — W2-c).
//    기계는 잔액 · 조각을 스스로 안 바꾼다 — 넘기는 값은 전부 스토어의 서버 값이다.
//  - isActive: 앱이 앞이고(호스트가 [isAppActive] 로 넘긴다 — Android ON_RESUME) · 확률 시트가 기계를 가리지 않을 때만.
//  - 손잡이 잠금: 로그인 · 뽑기 닫힘 · 잔량 모름 · **이 기계가 모르는 앞 뽑기**만 막는다(`gachaMachineBlockedReason`).
//  - 덮개를 공개 전에 닫아도 요청은 끊기지 않는다(스토어의 일) — 결과는 상점 카드의 마지막 결과 줄에 선다.
package com.yehsung.aingcheck.ui.gacha

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.stores.me.MeGachaRevealFailure
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.gachaMachineBlockedReason
import com.yehsung.aingcheck.core.stores.me.gachaMachineDidAppear
import com.yehsung.aingcheck.core.stores.me.gachaShards
import com.yehsung.aingcheck.core.stores.me.pullGachaForMachine
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.gacha.machine.GLayout
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineHaptics
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineTheme
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineView
import com.yehsung.aingcheck.ui.gacha.machine.GachaRevealFailure
import com.yehsung.aingcheck.ui.gacha.machine.GachaRevealOutcome
import com.yehsung.aingcheck.ui.gacha.machine.GachaRevealPortrait
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.shop.LocalMeArt
import com.yehsung.aingcheck.ui.shop.MeArtPaths
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.shop.rememberMachineArt
import com.yehsung.aingcheck.ui.shop.rememberRuby
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.min

/**
 * 기계 둘레 단추 꼴(공용 패치 12).
 *  - [Sheet]: 지금 모양 — 왼쪽 위 ✕ · 오른쪽 위 [확률 보기] 알약(폰 전체 화면 · 시트 머리 관례).
 *  - [Window]: 데스크톱 뽑기 창(맥 CheckGachaWindowView) — ✕ 없음(창 테두리가 닫는다) · 아래 띠 오른쪽의 작은 [확률 보기] 링크(맥 oddsLink).
 *    420×552 창에서 위쪽 알약이 기계 위 안내 알약(조각·잔액)을 가리던 것을 피한다(W4-f).
 */
enum class GachaMachineChrome { Sheet, Window }

/**
 * @param isAppActive 앱이 앞에 있는가(Android 껍데기가 수명 RESUMED 로 넘긴다).
 * @param oddsSheet 확률 시트를 띄우는 그릇 — 보이는 동안 기계를 멈춘다(isActive=false). 기본은 [MeGachaOddsSheetHost](ModalBottomSheet).
 * @param onUnrevealedChanged 루비를 낸 판의 결과를 아직 못 봤는가가 바뀔 때(GachaMachineDirector.hasUnrevealedTurn — 맥 GachaMachineLink).
 *   데스크톱 뽑기 창이 다시 열 때 기계를 새로 세울지 가르는 데 쓴다. 기본 {} — Android 는 안 쓴다.
 * @param chrome 기계 둘레 단추 꼴. 기본 [GachaMachineChrome.Sheet](지금 모양) — 데스크톱 창은 [GachaMachineChrome.Window].
 */
@Composable
fun MeGachaMachineScreen(
    store: MeStore,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    isAppActive: Boolean = true,
    haptics: GachaMachineHaptics = GachaMachineHaptics.None,
    reduceMotion: Boolean = false,
    teaseChance: Double = 0.3,
    onUnrevealedChanged: (Boolean) -> Unit = {},
    chrome: GachaMachineChrome = GachaMachineChrome.Sheet,
) {
    var ownsPull by remember { mutableStateOf(false) }
    var showsOdds by remember { mutableStateOf(false) }
    LaunchedEffect(store) { store.gachaMachineDidAppear() }
    // 공개에 나올 초상을 미리 풀어 둔다(결과가 오는 순간 그림이 이미 있게 — Swift prewarmLayer 의 자리).
    val art = LocalMeArt.current
    LaunchedEffect(art) { CharacterArt.portraitIds.forEach { art.load(MeArtPaths.portrait(it)) } }
    val portrait = remember(art) { GachaRevealPortrait { id -> art.peek(MeArtPaths.portrait(id)) } }

    Box(modifier.fillMaxSize()) {
        GachaMachineView(
            balance = store.rubyBalance ?: 0L,
            cost = store.gachaInfo?.price ?: 0L,
            shards = store.gachaShards ?: 0L,
            art = rememberMachineArt(),
            portrait = portrait,
            ruby = rememberRuby(24f),
            pull = {
                ownsPull = true
                try {
                    GachaRevealOutcome.of(store.pullGachaForMachine())
                } catch (e: MeGachaRevealFailure) {
                    throw GachaRevealFailure(e.message)
                } finally {
                    ownsPull = false
                }
            },
            onClose = onClose,
            haptics = haptics,
            isActive = isAppActive && !showsOdds,
            blockedReason = store.gachaMachineBlockedReason(ownsPull),
            againEnabled = !store.isPulling,
            reduceMotion = reduceMotion,
            teaseChance = teaseChance,
            onUnrevealedChanged = onUnrevealedChanged,
        )
        when (chrome) {
            GachaMachineChrome.Sheet -> MachineChrome(onClose = onClose, onOdds = { showsOdds = true })
            GachaMachineChrome.Window -> WindowOddsLink(onOdds = { showsOdds = true })
        }
    }
    if (showsOdds) MeGachaOddsSheetHost(store) { showsOdds = false }
}

/** 왼쪽 위 ✕(시트 머리 관례) · 오른쪽 위 [확률 보기](사기 전에 확률을 볼 수 있는 자리 — 카드와 같은 시트). */
@Composable
private fun MachineChrome(onClose: () -> Unit, onOdds: () -> Unit) {
    val c = AingTheme.colors
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(AingDimens.minimumTarget)
                .clip(CircleShape)
                .background(c.glass, CircleShape)
                .border(0.5.dp, c.glassLine, CircleShape)
                .clickable(role = Role.Button, onClick = onClose)
                .semantics { contentDescription = "닫기" },
            contentAlignment = Alignment.Center,
        ) { AingIcon(AppIcon.Close, contentDescription = null, size = 20.dp, tint = c.label) }
        Spacer(Modifier.weight(1f))
        Row(
            Modifier
                .heightIn(min = AingDimens.minimumTarget)
                .clip(CircleShape)
                .background(c.glass, CircleShape)
                .border(0.5.dp, c.glassLine, CircleShape)
                .clickable(role = Role.Button, onClick = onOdds)
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            AingIcon(AppIcon.Percent, contentDescription = null, size = 16.dp, tint = c.label)
            Text(GachaText.oddsButton, style = MeType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.label)
        }
    }
}

/**
 * 창 꼴의 [확률 보기] — 맥 CheckGachaWindowView.oddsLink 자리: 기계 무대(380×460)를 비율대로 맞춘 뒤 남는 **아래 띠** 오른쪽(무대 y≈445 의 안내 알약과
 * 겹치지 않는다). info 10 · 글자 11 semibold · 가로 12 · 높이 = 띠 높이(띠가 없으면 [WINDOW_LINK_MIN_HEIGHT]). 색은 기계 잉크(맥 palette.ink 와 같은 보라).
 */
@Composable
private fun BoxScope.WindowOddsLink(onOdds: () -> Unit) {
    val ink = GachaMachineTheme.of(AingTheme.colors.isDark).ink
    BoxWithConstraints(Modifier.matchParentSize()) {
        val s = min(maxWidth.value / GLayout.size.width, maxHeight.value / GLayout.size.height)
        val band = ((maxHeight.value - GLayout.size.height * s) / 2f).coerceAtLeast(WINDOW_LINK_MIN_HEIGHT)
        Row(
            Modifier
                .align(Alignment.BottomEnd)
                .height(band.dp)
                .clickable(role = Role.Button, onClick = onOdds)
                .semantics { contentDescription = GachaText.oddsTitle }
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            AingIcon(AppIcon.Info, contentDescription = null, size = 10.dp, tint = ink)
            Text(GachaText.oddsButton, style = MeType.caption2.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold), color = ink)
        }
    }
}

/** 띠가 거의 없는 비율의 창에서도 링크가 눌릴 높이(dp). */
private const val WINDOW_LINK_MIN_HEIGHT = 20f
