// 원본: Sources/CheckCore/GachaMachine/GachaMachineModel.swift @ 3bd04bd
//
// 0.3.54 캡슐 뽑기 기계 — 폰 전체 화면(Android)이 띄우는 기계의 호스트 값: 결과 · 실패 · 햅틱 · 그림 · 문구.
//
// INV-GachaMachineModel-0e87c2b2 이식: 코어 스토어 결과(rules `GachaPullResult` · stores `MeGachaReveal`)와 이름을 나눈다 — 기계 쪽은 전부
//   `GachaReveal…` / `GachaMachine…` 다. 스토어 결과를 연출 값으로 옮기는 길은 [GachaRevealOutcome.of] 하나다(MeGachaReveal → 기계).
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.core.rules.gacha.GachaPullResult
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.stores.me.MeGachaReveal

// MARK: - 결과(서버가 정하고, 기계는 연출만 한다)

enum class GachaRevealKind {
    /** 처음 만난 캐릭터. */
    New,

    /** 이미 있는 캐릭터 → 조각. */
    Duplicate,

    /** 황금 아잉이(처음이든 중복이든 — 중복이면 shardsGained > 0). */
    Gold,

    /** 무지개 아잉이(v0.3.59 — 황금과 같은 희귀 연출, 빛깔만 무지개). */
    Rainbow;

    /** 희귀 공개(어두운 무대 · 모으기 · 반짝 제목)인가. */
    val isRare: Boolean get() = this == Gold || this == Rainbow
}

/** 기계가 보여 줄 결과 하나. 값은 전부 호스트가 서버 응답에서 옮겨 준다 — 기계는 숫자를 지어내지 않는다. */
data class GachaRevealOutcome(
    val characterID: String,
    /** 화면 이름("여우"). */
    val name: String,
    val kind: GachaRevealKind,
    /** 뽑은 **뒤** 조각 수. */
    val shardCount: Long = 0,
    /** 이번에 얻은 조각(중복 = 보통 1, 처음 = 0). null 이면 갈래에서 정한다. */
    private val shardsGainedOrNull: Long? = null,
) {
    val shardsGained: Long = maxOf(0L, shardsGainedOrNull ?: if (kind == GachaRevealKind.Duplicate) 1L else 0L)
    private val shardCountClamped: Long = maxOf(0L, shardCount)

    /** 칩이 연출 전에 보여 줄 조각 수. */
    val shardCountBefore: Long get() = maxOf(0L, shardCountClamped - shardsGained)
    val shardCountAfter: Long get() = shardCountClamped

    /** 희귀인데 이미 있던 것(조각만 받았다). */
    val isRareDuplicate: Boolean get() = kind.isRare && shardsGained > 0

    companion object {
        /** 스토어 공개값(W2-c [MeGachaReveal] — 서버 값)에서. 서버가 뒤 조각 수를 안 줬을 때의 셈은 스토어가 이미 했다. */
        fun of(reveal: MeGachaReveal): GachaRevealOutcome = GachaRevealOutcome(
            characterID = reveal.characterID,
            name = reveal.name,
            kind = when (reveal.kind) {
                GachaPullResult.Kind.gold -> GachaRevealKind.Gold
                GachaPullResult.Kind.rainbow -> GachaRevealKind.Rainbow
                GachaPullResult.Kind.newCharacter -> GachaRevealKind.New
                GachaPullResult.Kind.duplicate -> GachaRevealKind.Duplicate
            },
            shardCount = reveal.shardCount,
            shardsGainedOrNull = reveal.shardsGained,
        )
    }
}

/** `pull` 이 던지는 실패. [message] 가 기계 아래 한 줄로 2.4초 뜬다. 이 타입이 아닌 오류는 [GachaMachineText.pullFailed]. */
class GachaRevealFailure(override val message: String) : Exception(message)

// MARK: - 햅틱(플랫폼 몫은 인터페이스 뒤 — 데스크톱은 아무것도 안 한다)

sealed interface GachaMachineHapticEvent {
    /** 손잡이 45° 톱니. */
    data object Ratchet : GachaMachineHapticEvent

    /** 루비 부족 · 막힘 · 실패. */
    data object Refuse : GachaMachineHapticEvent

    /** 한 바퀴 완료 · 기계 쿵. */
    data object Commit : GachaMachineHapticEvent

    /** 기다리는 동안 덜컹. */
    data object Rumble : GachaMachineHapticEvent

    /** 캡슐이 배출구에 떨어짐. */
    data object Land : GachaMachineHapticEvent

    /** 캡슐 톡톡 1…3. */
    data class Tap(val count: Int) : GachaMachineHapticEvent

    /** 평범한 캡슐이 황금(무지개)으로 바뀜. */
    data object GoldFlip : GachaMachineHapticEvent

    /** 캡슐 터짐. */
    data object Reveal : GachaMachineHapticEvent

    /** 황금(무지개) 터짐. */
    data object GoldReveal : GachaMachineHapticEvent

    /** 조각이 칩에 들어감. */
    data object Shard : GachaMachineHapticEvent
}

fun interface GachaMachineHaptics {
    fun play(event: GachaMachineHapticEvent)

    companion object {
        val None: GachaMachineHaptics = GachaMachineHaptics { }
    }
}

// MARK: - 그림(없으면 벡터로 그린다)

/**
 * 기계·캡슐 래스터 레이어. 하나라도 null 이면 그 부분은 벡터 도형으로 그린다. 유리 돔은 늘 벡터다.
 * 그림 원본은 `Sources/CheckCore/Resources/GachaMachine` 의 PNG 다섯 장 — Android 에는 ui 의 Gradle Sync 가 `files/gacha/` 로 싣는다
 * (git 사본 0 — 조정자 패치). 그 패치 전 빌드는 다섯 칸이 비어 벡터로 그린다.
 */
data class GachaMachineArt(
    /** 몸통(유리 돔·손잡이 제외, 배출구·덮개 포함). */
    val body: ImageBitmap? = null,
    /** 손잡이(정면, 중심 기준으로 돌린다). */
    val knob: ImageBitmap? = null,
    /** 흰 캡슐 한 알(위·아래 반쪽을 잘라 물들인다). */
    val capsule: ImageBitmap? = null,
    /** 황금 캡슐 한 알. */
    val goldCapsule: ImageBitmap? = null,
    /** 돔 뚜껑. */
    val cap: ImageBitmap? = null,
) {
    /** 다섯 장 다 있는가(배포본은 참이어야 한다 — 벡터는 그림이 빠졌을 때의 안전망). */
    val isComplete: Boolean get() = body != null && knob != null && capsule != null && goldCapsule != null && cap != null

    companion object {
        val Vector = GachaMachineArt()

        /** Compose 리소스 자리(ui 패치가 싣는 곳) — 이름은 Swift `GachaMachineArtBundle.resourceNames` 와 같다. */
        const val RESOURCE_DIR = "files/gacha"
        val resourceNames: List<String> = listOf("gacha_body", "gacha_knob", "gacha_capsule", "gacha_capsule_gold", "gacha_cap")

        /** 맥 원본 폴더(저장소 뿌리 기준). */
        const val SOURCE_DIR = "Sources/CheckCore/Resources/GachaMachine"

        fun resourcePath(name: String): String = "$RESOURCE_DIR/$name.png"
    }
}

// MARK: - 문구(해요체 · 짧게 · GachaText 와 같은 말투)

object GachaMachineText {
    const val idleHint = "손잡이를 돌려서 뽑기 ·"
    const val shortHead = "루비가 모자라요 ·"
    fun shortTail(cost: Long): String = "${cost}개부터 뽑을 수 있어요"
    const val waiting = "두근두근"
    const val tapFirst = "톡톡 눌러서 열기"
    const val tapSecond = "조금 더!"
    const val tapLast = "마지막 한 번!"
    const val skip = "건너뛰기"
    const val again = "한 번 더 ·"
    const val againShort = "루비가 모자라요"
    const val againBlocked = "한 번 더"
    const val close = "닫기"
    const val shardPlus = "조각"

    /** 이 타입이 아닌 실패의 한 줄 — 루비가 깎였는지 모르므로 "그대로"라고 말하지 않는다. */
    val pullFailed: String get() = GachaText.pullFailed

    fun badge(outcome: GachaRevealOutcome): String? = when (outcome.kind) {
        GachaRevealKind.New -> "새 캐릭터!"
        GachaRevealKind.Duplicate -> "이미 있는 친구예요"
        GachaRevealKind.Gold, GachaRevealKind.Rainbow -> null
    }

    /** 희귀 결과의 머리말("황금 아잉이!" · "무지개 아잉이!"). 희귀가 아니면 null. */
    fun rareHeadline(kind: GachaRevealKind): String? = when (kind) {
        GachaRevealKind.Gold -> GachaText.goldHeadline
        GachaRevealKind.Rainbow -> GachaText.rainbowHeadline
        GachaRevealKind.New, GachaRevealKind.Duplicate -> null
    }

    fun title(outcome: GachaRevealOutcome): String = rareHeadline(outcome.kind) ?: outcome.name

    /** 중복의 둘째 이름("다람쥐 조각"). */
    fun shardLine(outcome: GachaRevealOutcome): String = "${outcome.name} 조각"
    fun shardGain(outcome: GachaRevealOutcome): String = "+${maxOf(1L, outcome.shardsGained)}"

    /** 희귀(황금 · 무지개) 결과의 부제 — 둘이 같은 말이다. */
    fun goldSubtitle(outcome: GachaRevealOutcome): String =
        if (outcome.isRareDuplicate) "이미 있는 친구예요 · 조각 +${outcome.shardsGained}" else "아주 드문 친구를 만났어요"

    fun chipGain(outcome: GachaRevealOutcome): String = "+${maxOf(1L, outcome.shardsGained)} 조각"

    /** 공개가 끝났을 때 읽어 줄 한 문장(톡백 · 결과 요소의 이름). 정상 연출과 동작 줄이기가 같다. */
    fun announcement(outcome: GachaRevealOutcome): String = when (outcome.kind) {
        GachaRevealKind.New -> "새 캐릭터! ${outcome.name}"
        GachaRevealKind.Duplicate -> "이미 있는 친구예요. ${outcome.name} 조각 ${shardGain(outcome)}"
        GachaRevealKind.Gold, GachaRevealKind.Rainbow -> "${title(outcome)} ${goldSubtitle(outcome)}"
    }

    const val handleLabel = "뽑기 손잡이"
    fun handleHint(cost: Long): String = "두 번 탭하면 루비 ${cost}개로 한 번 뽑아요"
    fun rubyLabel(balance: Long): String = "루비 ${balance}개"
    fun shardLabel(count: Long): String = "조각 ${count}개"
    const val openCapsule = "캡슐 열기"
    fun againLabel(cost: Long): String = "한 번 더 뽑기 · 루비 ${cost}개"
}
