// 원본: Sources/CheckMobileKit/Me/MeGachaViews.swift @ 3bd04bd (MeGachaCard · MeGachaLastResultRow)
//
// 상점 맨 위 뽑기 카드: 제목 + 1회 값 · 마지막 결과 한 줄 · **"확률 보기" 줄 → [뽑기 · 50]** · 막힌 이유 · [조각 N개 · 교환].
//
// Android 차이(설계 E §9.4 · G §2-3 W4-c ②): iOS 는 [확률 보기]가 [뽑기] **아래** 회색 단추 둘 중 하나다. Android 는 Play 정책(확률형 아이템은
// 사기 전에, 가까이 — "in advance of, and in close and timely proximity to") 대로 **"확률 보기" 줄을 [뽑기] 바로 위**에 둔다. 그 줄에는
// 서버가 준 희귀 확률 요약(황금 · 무지개 — 서버 순서 · 서버 숫자)을 함께 적는다. 이 화면 코드에 확률 숫자는 하나도 없다(서버 shop_state.gacha.odds).
//
// 카드 자체는 확률표 합이 100% 일 때만 선다(W2-c `showsGacha` — 공개 못 한 확률로 루비를 받지 않는다). 판정·문구는 코어(GachaRules · GachaText)
// 와 스토어(MeStoreGacha)가 쥐고 이 파일은 그리기만 한다. [뽑기] 는 **틴트**다(화면당 채운 단추 하나 — 아래 구매 막대).
package com.yehsung.aingcheck.ui.gacha

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.gacha.GachaOddsRow
import com.yehsung.aingcheck.core.rules.gacha.GachaPullResult
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.canPullGacha
import com.yehsung.aingcheck.core.stores.me.gachaDetail
import com.yehsung.aingcheck.core.stores.me.gachaName
import com.yehsung.aingcheck.core.stores.me.gachaOddsRows
import com.yehsung.aingcheck.core.stores.me.gachaShards
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.RubyPriceRule
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.shop.MeButtonFrame
import com.yehsung.aingcheck.ui.shop.MeButtonKind
import com.yehsung.aingcheck.ui.shop.MeButtonSize
import com.yehsung.aingcheck.ui.shop.MeCard
import com.yehsung.aingcheck.ui.shop.MeCharacterArt
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.shop.MeType.digits
import com.yehsung.aingcheck.ui.shop.rememberRuby
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 시험이 자리를 재는 꼬리표(확률 보기 줄 · 뽑기 단추 · 카드). */
object GachaCardTags {
    const val CARD = "gacha.card"
    const val ODDS_ROW = "gacha.oddsRow"
    const val PULL = "gacha.pull"
    const val EXCHANGE = "gacha.exchange"
}

@Composable
fun MeGachaCard(store: MeStore, onPull: () -> Unit, onOdds: () -> Unit, onExchange: () -> Unit, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    val price = store.gachaInfo?.price ?: 0L
    MeCard(modifier.testTag(GachaCardTags.CARD)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            Text(GachaText.title, style = MeType.headline, color = c.label, modifier = Modifier.weight(1f).semantics { heading() })
            val balance = store.rubyBalance
            RubyPrice(price.toInt(), RubyPriceRule.isShort(price.toInt(), balance?.toInt()), rememberRuby(17f), gemSize = 17.dp, fontSize = 15f)
        }
        Text(MeText.gachaLede(price), style = MeType.footnote, color = c.label2)
        store.lastGachaResult?.let { MeGachaLastResultRow(it, store.gachaName(it.characterID)) }
        MeGachaOddsRow(store.gachaOddsRows, onOdds)
        PullButton(store, price, onPull)
        store.gachaDetail?.let { detail ->
            Text(detail, style = MeType.footnote, color = if (store.isGachaNoticeError) c.danger else c.label2)
        }
        MeButtonFrame(
            Modifier.testTag(GachaCardTags.EXCHANGE), MeButtonKind.Gray, MeButtonSize.Md, fillsWidth = true, enabled = true, onClick = onExchange,
        ) { fg ->
            AingIcon(AppIcon.Extension, contentDescription = null, size = 18.dp, tint = fg)
            Text(MeText.gachaExchangeEntry(store.gachaShards), style = MeType.callout.copy(fontWeight = FontWeight.SemiBold), color = fg)
        }
    }
}

/**
 * "확률 보기" 줄 — [뽑기] **바로 위**. 왼쪽 기호 + 글자, 오른쪽에 서버가 준 희귀(황금 · 무지개) 확률 요약 + ›. 누르면 확률표(서버 순서 그대로).
 * 요약 숫자는 서버 값이 코어 `GachaText.percent` 를 지난 글자다(이 파일에 숫자를 적지 않는다).
 */
@Composable
fun MeGachaOddsRow(rows: List<GachaOddsRow>, onOdds: () -> Unit, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    val summary = GachaOddsSummary.text(rows)
    Row(
        modifier
            .testTag(GachaCardTags.ODDS_ROW)
            .fillMaxWidth()
            .heightIn(min = AingDimens.minimumTarget)
            .clip(RoundedCornerShape(AingDimens.innerRadius))
            .background(c.surface2)
            .clickable(role = Role.Button, onClick = onOdds)
            .clearAndSetSemantics {
                role = Role.Button
                contentDescription = listOfNotNull(GachaText.oddsButton, summary).joinToString(", ")
            }
            .padding(horizontal = AingDimens.space3, vertical = AingDimens.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        AingIcon(AppIcon.Percent, contentDescription = null, size = 18.dp, tint = c.accent)
        Text(GachaText.oddsButton, style = MeType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.accent)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            if (summary != null) Text(summary, style = MeType.footnote.digits(), color = c.label2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 16.dp, tint = c.label3)
    }
}

/** 확률 보기 줄의 요약(희귀 줄만 — "황금 아잉이 3% · 무지개 아잉이 2%"). 희귀 줄이 없으면 null. */
object GachaOddsSummary {
    fun text(rows: List<GachaOddsRow>): String? =
        rows.filter { it.finish.isRare }.takeIf { it.isNotEmpty() }?.joinToString(" · ") { "${it.name} ${it.percentText}" }
}

@Composable
private fun PullButton(store: MeStore, price: Long, onPull: () -> Unit) {
    MeButtonFrame(
        Modifier.testTag(GachaCardTags.PULL), MeButtonKind.Tinted, MeButtonSize.Lg, fillsWidth = true, enabled = store.canPullGacha,
        contentDescription = "${GachaText.pullButton}, 루비 ${price}개", onClick = onPull,
    ) { fg ->
        if (store.isPulling) {
            CircularProgressIndicator(Modifier.size(16.dp), color = AingTheme.colors.accent, strokeWidth = 2.dp)
        } else {
            AingIcon(AppIcon.AutoAwesome, contentDescription = null, size = 20.dp, tint = fg)
        }
        Text(GachaText.pullButton(price), style = MeType.body.copy(fontWeight = FontWeight.SemiBold).digits(), color = fg)
    }
}

/**
 * 마지막 뽑기 결과 한 줄(움직임 없음 — 연출은 기계 몫). 희귀 둘은 그 빛깔 받침 + 테두리 + 머리말. 머리말 **글자**는 희귀여도 label 이다
 * (받침 위 글자까지 같은 빛으로 칠하면 라이트에서 4.2:1 로 내려간다).
 */
@Composable
fun MeGachaLastResultRow(result: GachaPullResult, name: String) {
    val c = AingTheme.colors
    val (headline, detail, finish) = MeText.gachaResultLines(result, name)
    val shape = RoundedCornerShape(AingDimens.innerRadius)
    val tint = GachaPaint.rareTint(finish)
    val stroke = GachaPaint.rareStroke(finish)
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (tint != null) Modifier.background(tint, shape) else Modifier.background(c.surface2, shape))
            .then(if (stroke != null) Modifier.border(1.dp, stroke, shape) else Modifier)
            .clearAndSetSemantics { contentDescription = listOfNotNull(MeText.gachaLastResult, headline, detail).joinToString(", ") }
            .padding(AingDimens.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
    ) {
        Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { MeCharacterArt(result.characterID, 40.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(headline, style = MeType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.label)
            if (detail != null) Text(detail, style = MeType.footnote, color = c.label2)
        }
    }
}
