// 원본: Sources/CheckMobileKit/Me/MeOmokSkinViews.swift @ 928d5562(폰 1.0.18 — 상점 '오목알' 절 · 미리보기 판)
//
// 상점 '오목알' 절(판 8). '일반 돌' + 서버가 말한 스킨 칸(주사위 · 고양이 · 픽셀 — 루비 100). 안 가진 칸은 확인 뒤 산다(사면 서버가 바로 끼운다),
// 가진 칸을 누르면 낀다. 낀 돌은 상대 · 관전자 화면에도 그 스킨으로 보인다(대표 #d_RR2dyBIHDMW5 "상대에게도 보임").
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.achievements.OmokSkinPhoneText
import com.yehsung.aingcheck.core.rules.achievements.OmokStoneSkin
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.buyOmokSkin
import com.yehsung.aingcheck.core.stores.me.equipOmokSkin
import com.yehsung.aingcheck.core.stores.me.equippedOmokSkin
import com.yehsung.aingcheck.core.stores.me.isOmokSkinOwned
import com.yehsung.aingcheck.core.stores.me.omokSkinPrice
import com.yehsung.aingcheck.ui.components.ModalPresenceMark
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.RubyPriceRule
import com.yehsung.aingcheck.ui.games.gomoku.GomokuBoardInk
import com.yehsung.aingcheck.ui.games.gomoku.drawStone
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

object OmokSkinTags {
    fun tile(id: String) = "shop.omok.$id"
}

/** 상점 '오목알' 절 — 서버가 스킨 줄을 말할 때만 세운다(`MeStore.showsOmokSkins`). */
@Composable
fun MeOmokSkinSection(store: MeStore) {
    val c = AingTheme.colors
    var buying by remember { mutableStateOf<OmokStoneSkin?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MeSectionHeader(
            OmokSkinPhoneText.title, OmokSkinPhoneText.note,
            Modifier.padding(start = AingDimens.titleMargin - AingDimens.sideMargin, end = AingDimens.titleMargin - AingDimens.sideMargin, top = AingDimens.space1),
        )
        val keys = listOf("plain") + (store.omokSkins?.rows ?: emptyList()).map { it.id }
        TileGrid(keys) { key -> OmokSkinTile(store, OmokStoneSkin.fromWire(key)) { buying = it } }
        store.omokSkinNotice?.let { notice ->
            Text(notice, style = MeType.footnote, color = c.label2, modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin))
        }
    }
    val skin = buying
    if (skin != null) {
        val price = store.omokSkinPrice(skin)
        val balance = store.rubyBalance
        ModalPresenceMark()
        AlertDialog(
            onDismissRequest = { buying = null },
            title = { Text(OmokSkinPhoneText.confirmTitle(skin)) },
            text = { if (price != null && balance != null) Text(MeText.purchaseConfirmMessage(price, balance)) },
            confirmButton = { TextButton(onClick = { buying = null; store.buyOmokSkin(skin) }) { Text(MeText.buyAction) } },
            dismissButton = { TextButton(onClick = { buying = null }) { Text("취소") } },
        )
    }
}

@Composable
private fun OmokSkinTile(store: MeStore, skin: OmokStoneSkin?, onBuy: (OmokStoneSkin) -> Unit) {
    val c = AingTheme.colors
    val owned = skin?.let(store::isOmokSkinOwned) ?: true
    val equipped = store.omokSkins != null && store.equippedOmokSkin == skin
    val shape = RoundedCornerShape(AingDimens.tileRadius)
    val name = OmokSkinPhoneText.name(skin)
    Column(
        Modifier
            .fillMaxWidth()
            .testTag(OmokSkinTags.tile(skin?.wireValue ?: "plain"))
            .background(if (equipped) c.accentTint else c.surface, shape)
            .border(1.5.dp, if (equipped) c.accent else c.accent.copy(alpha = 0f), shape)
            .clickable(enabled = store.omokSkinBusy == null, role = Role.Button) {
                if (owned) store.equipOmokSkin(skin) else if (skin != null) onBuy(skin)
            }
            .clearAndSetSemantics {
                contentDescription = accessibility(store, skin, owned, equipped)
                role = Role.Button
                selected = equipped
            }
            .padding(vertical = 12.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OmokSkinPreview(skin)
        Text(name, style = MeType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        when {
            equipped -> Text(OmokSkinPhoneText.equippedBadge, style = MeType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.accent)
            owned -> Text(OmokSkinPhoneText.owned, style = MeType.caption, color = c.label2)
            else -> {
                val price = skin?.let(store::omokSkinPrice)
                if (price != null) RubyPrice(price, RubyPriceRule.isShort(price, store.rubyBalance), rememberRuby(14f), gemSize = 14.dp, fontSize = 12f)
                else Text("—", style = MeType.caption, color = c.label2)
            }
        }
    }
}

/** 미리보기 — 나뭇결 위에 흑 · 백 한 알씩(폰 MeOmokSkinPreview 와 같은 배치). */
@Composable
private fun OmokSkinPreview(skin: OmokStoneSkin?) {
    Canvas(Modifier.fillMaxWidth().height(44.dp)) {
        val inset = 2.dp.toPx()
        drawRoundRect(GomokuBoardInk.woodLight, topLeft = Offset(inset, inset), size = Size(size.width - inset * 2, size.height - inset * 2), cornerRadius = CornerRadius(8.dp.toPx()))
        val r = minOf(size.height * 0.36f, size.width * 0.2f)
        val y = size.height / 2
        drawStone(Offset(size.width / 2 - r * 1.15f, y), r, GomokuColor.black, 1f, skin, 1)
        drawStone(Offset(size.width / 2 + r * 1.15f, y), r, GomokuColor.white, 1f, skin, 2)
    }
}

private fun accessibility(store: MeStore, skin: OmokStoneSkin?, owned: Boolean, equipped: Boolean): String {
    val name = OmokSkinPhoneText.name(skin)
    if (equipped) return "$name 오목알, ${OmokSkinPhoneText.equippedBadge}"
    if (owned) return "$name 오목알, ${OmokSkinPhoneText.owned}"
    val price = skin?.let(store::omokSkinPrice)
    return if (price != null) "$name 오목알, 루비 ${price}개" else "$name 오목알"
}
