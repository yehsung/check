// 원본: Sources/CheckMobileKit/Components/MobileComponentsGallery.swift @ 862be0f (부품 진열장 — 같은 구실)
//
// 디자인 시스템 진열장 두 장: ① 테마(M3 뼈대: 탭 막대·스위치·단추·체크·라디오·슬라이더·진행 표시·대화상자·시트 + 글자·뜻 색)
// ② 브랜드 부품(초상·무대·루비·잔디·글자 칠).
// 스냅숏 골든(ui/snapshots/{theme,components}/…)이 이 두 장을 밝음·어두움 × 폰(Android)·데스크톱 배율 2 로 찍는다.
// 그림은 부르는 쪽이 넘긴다(시험은 저장소 원본을 직접 읽고, 앱은 CharacterArt 로 읽는다) — 진열장은 불러오기를 하지 않는다.
// 글자는 전부 Pretendard 범위(한글·라틴·숫자·기본 문장부호) 안이다 — 대체 글꼴이 끼면 플랫폼마다 픽셀이 갈린다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTextPaint
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 진열장 그림 묶음(없으면 null — 빈 자리로 그린다). */
@Immutable
data class GalleryArt(
    val portraitNeutral: ImageBitmap?,
    val portraitNegative: ImageBitmap?,
    val stage: ImageBitmap?,
    val ruby: ImageBitmap?,
)

/** 진열장 내용 바꾸개(스냅숏 음성 대조용 — 같은 크기에 한 군데만 다른 장면). */
@Immutable
data class GalleryVariant(val rubyCount: Int = 30, val switchOn: Boolean = true, val grassSeed: Int = 0)

/** 진열장 폭(dp): 폰 360 · 데스크톱 플라이아웃 380(D§4). */
object GalleryFrame {
    val phoneWidth: Dp = 360.dp
    val desktopWidth: Dp = 380.dp
    // 테마 장은 체크·라디오·슬라이더·진행 표시 줄(G §8-15)이 들어와 60dp 늘었다.
    val themeHeight: Dp = 880.dp
    val componentsHeight: Dp = 820.dp
}

private val tabs = listOf(
    "지금" to AppIcon.ScheduleFill,
    "메시지" to AppIcon.ForumFill,
    "순위" to AppIcon.TrophyFill,
    "게임" to AppIcon.SportsEsportsFill,
)

/** ① 테마 진열장. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThemeGallery(art: GalleryArt, modifier: Modifier = Modifier, variant: GalleryVariant = GalleryVariant()) {
    val colors = AingTheme.colors
    val type = MaterialTheme.typography
    Column(modifier.background(colors.background)) {
        Column(Modifier.padding(horizontal = AingTheme.dimens.sideMargin, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("아잉체크 테마", style = type.headlineSmall, color = colors.label)
            GalleryCard {
                Text("섹션 제목 20 bold", style = type.titleLarge, color = colors.label)
                Text("행 이름 16 semibold · 부제 13", style = type.titleSmall, color = colors.label)
                Text("보조 글자 label2 — 오늘 3시간 12분 근무", style = type.bodySmall, color = colors.label2)
                Text("3단 글자 label3Text — 끝난 할 일", style = type.bodySmall, color = colors.label3Text)
                Text("01:23:45", style = type.displaySmall, color = colors.label)
            }
            GalleryCard {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    MeaningDot("근무 중", colors.working, colors.workingDot)
                    MeaningDot("대기", colors.pending, colors.pendingDot)
                    MeaningDot("퇴근", colors.offWork, colors.offWorkDot)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    // 주요색(iOS 파랑 = primary)과 AI 토큰 보라를 나란히 — 둘이 구분되는지 골든에서 눈으로도 본다(G §8-15).
                    MeaningDot("선택", colors.accent, colors.accentFill)
                    MeaningDot("AI 토큰", colors.aiToken, colors.aiToken)
                    MeaningDot("위험", colors.danger, colors.danger)
                }
            }
            GalleryCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("자동 시작", style = type.titleSmall, color = colors.label, modifier = Modifier.weight(1f))
                    Switch(checked = variant.switchOn, onCheckedChange = null)
                    Switch(checked = !variant.switchOn, onCheckedChange = null)
                }
                // M3 단추 셋은 주요색(파랑). 글자는 주요 동작 예시 — '뽑기'는 브랜드 자리(보라)라 M3 단추 예시로 쓰지 않는다(G §8-15).
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {}) { Text("보내기") }
                    FilledTonalButton(onClick = {}) { Text("상점") }
                    TextButton(onClick = {}) { Text("닫기") }
                }
                // 체크·라디오·슬라이더·진행 표시도 M3 뼈대라 파랑(G §8-15): 켠 칸·고른 원·채운 트랙 = primary, 빈 트랙 = secondaryContainer(파랑 받침).
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Checkbox(checked = true, onCheckedChange = null)
                    Checkbox(checked = false, onCheckedChange = null)
                    RadioButton(selected = true, onClick = null)
                    RadioButton(selected = false, onClick = null)
                    Slider(value = 0.6f, onValueChange = {}, modifier = Modifier.weight(1f))
                }
                LinearProgressIndicator(progress = { 0.4f }, modifier = Modifier.fillMaxWidth())
            }
            // 대화상자(M3 AlertDialog 의 면·모양·글자 역할을 창 없이 같은 자리로 — 실제 대화상자는 창이라 스냅숏에 안 잡힌다).
            Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("대결을 신청할까요?", style = type.headlineSmall, color = MaterialTheme.colorScheme.onSurface)
                    Text("판돈 루비 5개를 걸어요. 지면 돌려받지 못해요.", style = type.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        TextButton(onClick = {}) { Text("취소") }
                        TextButton(onClick = {}) { Text("신청") }
                    }
                }
            }
            // 시트(M3 ModalBottomSheet 의 면·끌개 — 위 모서리만 둥글다).
            Surface(
                shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    BottomSheetDefaults.DragHandle()
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        for (icon in listOf(AppIcon.NotificationsFill, AppIcon.Settings, AppIcon.SendFill, AppIcon.Delete, AppIcon.Block, AppIcon.Edit, AppIcon.Close)) {
                            AingIcon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
            }
        }
        Spacer(Modifier.weight(1f))
        // 탭 막대(M3). '나' 탭은 착용 캐릭터 초상(틴트 없음 — CharacterTabIcon).
        NavigationBar {
            tabs.forEachIndexed { i, (label, icon) ->
                NavigationBarItem(
                    selected = i == 0,
                    onClick = {},
                    icon = { AingIcon(icon, contentDescription = null) },
                    label = { Text(label) },
                )
            }
            NavigationBarItem(
                selected = false,
                onClick = {},
                icon = { CharacterTabIcon(art.portraitNeutral, CharacterMood.Working) },
                label = { Text("나") },
                colors = NavigationBarItemDefaults.colors(),
            )
        }
    }
}

/** ② 브랜드 부품 진열장. */
@Composable
fun ComponentsGallery(art: GalleryArt, modifier: Modifier = Modifier, variant: GalleryVariant = GalleryVariant()) {
    val colors = AingTheme.colors
    val type = MaterialTheme.typography
    Column(
        modifier.background(colors.background).padding(horizontal = AingTheme.dimens.sideMargin, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("브랜드 부품", style = type.headlineSmall, color = colors.label)
        GalleryCard {
            Text("초상 · 근무 상태", style = type.titleSmall, color = colors.label)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                CharacterPortrait(art.portraitNeutral, CharacterMood.Working, 52.dp)
                CharacterPortrait(art.portraitNeutral, CharacterMood.Lost, 52.dp)
                CharacterPortrait(art.portraitNegative, CharacterMood.Off, 52.dp)
                CharacterPortrait(art.portraitNeutral, CharacterMood.Plain, 52.dp)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                CharacterPortrait(art.portraitNeutral, CharacterMood.Working, 40.dp, badge = PortraitBadge.Symbol(AppIcon.BrushFill))
                CharacterPortrait(art.portraitNeutral, CharacterMood.Plain, 32.dp, badge = PortraitBadge.Stone(isBlack = true))
                CharacterPortrait(art.portraitNeutral, CharacterMood.Plain, 32.dp, badge = PortraitBadge.Stone(isBlack = false))
                CharacterTabIcon(art.portraitNegative, CharacterMood.Off)
            }
        }
        GalleryCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CharacterStage(art.stage, CharacterMood.Working, artSize = 120.dp)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("여우", style = type.headlineMedium, color = colors.label)
                    Text("아잉 팀 · 센터", style = type.bodyMedium, color = colors.label2)
                    RubyBalanceChip(variant.rubyCount, art.ruby, style = RubyChipStyle.Large)
                    Text("근무 중 · 여우 착용 중", style = type.bodySmall, color = colors.working)
                }
            }
        }
        GalleryCard {
            Text("루비", style = type.titleSmall, color = colors.label)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                RubyBalanceChip(variant.rubyCount, art.ruby)
                RubyBalanceChip(null, art.ruby)
                RubyBalanceChip(1250, art.ruby, style = RubyChipStyle.Glass)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                RubyPrice(50, isShort = false, art = art.ruby)
                RubyPrice(200, isShort = true, art = art.ruby)
                RubyGain(10, art.ruby)
                RubyGain(3, art.ruby, suffix = "받음", style = RubyGainStyle.Chip)
            }
        }
        GalleryCard {
            Text("최근 12주", style = type.titleSmall, color = colors.label)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("근무", style = type.bodySmall, color = colors.label2)
                    ContributionGridCanvas(galleryLevels(variant.grassSeed), ContributionAxis.Work)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("AI 토큰", style = type.bodySmall, color = colors.label2)
                    ContributionGridCanvas(galleryLevels(variant.grassSeed + 3), ContributionAxis.Token)
                }
            }
        }
        GalleryCard {
            Text("글자 칠 — 긴 이름만 그라데이션", style = type.titleSmall, color = colors.label)
            val stops = AingTextPaint.rainbowStops(colors.isDark)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                PaintedText("무지개 아잉이", stops, type.titleMedium)
                PaintedText("2%", stops, type.titleMedium)
                AingIcon(AppIcon.AutoAwesome, null, tint = AingTextPaint.sparkle(stops, colors.aiToken))
            }
        }
    }
}

/** 글자 칠 규칙을 따르는 글자: 길면 그라데이션, 짧으면 단색(AingTextPaint). */
@Composable
fun PaintedText(text: String, stops: List<Color>, style: TextStyle, modifier: Modifier = Modifier) {
    val brush = AingTextPaint.textBrushOrNull(text, stops)
    val solid = AingTextPaint.solidFor(stops, AingTheme.colors.label)
    if (brush != null) Text(text, modifier, style = AingTextPaint.withBrush(style, brush))
    else Text(text, modifier, style = style, color = solid)
}

@Composable
private fun GalleryCard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingTheme.dimens.groupRadius))
            .padding(AingTheme.dimens.cardPadding),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

@Composable
private fun MeaningDot(label: String, ink: Color, dot: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(8.dp).background(dot, CircleShape))
        Text(label, style = MaterialTheme.typography.labelMedium, color = ink)
        Spacer(Modifier.width(2.dp))
    }
}

/** 결정적인 진열장 잔디(13주 × 7, 마지막 주 뒤 3칸은 미래). [seed] 가 다르면 칸 하나 이상이 다르다. */
fun galleryLevels(seed: Int): List<List<Int?>> = List(ContributionGridLayout.DEFAULT_WEEKS) { week ->
    List(ContributionGridLayout.ROWS) { day ->
        if (week == ContributionGridLayout.DEFAULT_WEEKS - 1 && day >= 4) null
        else ((week * 7 + day) * 37 + seed * 11 + week * week) % 5
    }
}
