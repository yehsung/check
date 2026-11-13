// 원본: Sources/CheckMobileKit/Games/GamesMahjongText.swift @ e4995a3a(폰 문구 · 화면 고르기 · 규칙 표 · 점수표 칸 · 더블론 넘김 · 폰 보조 기본값) — Android 판 8
//
// 맥 `MahjongText` 를 글자 그대로 옮긴 아이폰 문구를 다시 글자 그대로 옮긴다 — 같은 서버 · 같은 규칙을 기기마다 다르게 말하지 않게.
// 서버 응답 문구는 MahjongNoticeText 한 곳(스토어 notice). 폰에서만 다른 것은 [GamesMahjongPhoneText](손짓 · 가로 안내).
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRules
import com.yehsung.aingcheck.core.rules.mahjong.MahjongScoring
import com.yehsung.aingcheck.core.rules.mahjong.MahjongYaku
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.abs
import kotlin.math.roundToLong

object GamesMahjongText {
    const val title = MahjongNoticeText.gameName
    const val subtitle = "리치 마작 4인 대국 — 가장 널리 쓰이는 온라인 리치 마작 규칙과 같아요"
    const val rules = "규칙"
    const val yaku = "역"
    const val scoreTable = "점수표"
    const val close = "닫기"
    const val practice = "혼자 연습"
    const val usersTab = "사람"
    const val rankTab = "순위"
    const val invite = "초대"
    const val invited = "초대함"
    const val join = "참가"
    const val decline = "거절"
    const val emptyUsers = "함께할 사람이 아직 없어요"
    const val loadingUsers = "사람 목록을 불러오는 중…"
    const val inMatchChip = "대국 중"
    const val outdatedChip = "업데이트 필요"
    const val focusChip = "집중 모드"
    const val workingChip = "근무 중"
    const val invitesTitle = "받은 초대"
    const val publicRoomsTitle = "공개 방"
    const val noJoinables = "받은 초대나 열린 공개 방이 없어요"
    const val createTitle = "방 만들기"
    const val createButton = "만들기"
    const val createHint = "판돈은 시작할 때 모두에게서 걷고, 등수대로 나눠 가져요."
    const val stakeLabel = "판돈"
    const val formatLabel = "판 길이"
    const val publicLabel = "공개"
    const val publicOn = "누구나 참가"
    const val publicOff = "초대한 사람만"
    const val myRoomTitle = "내 방"
    const val start = "시작"
    const val leave = "나가기"
    const val emptySeat = "빈자리"
    const val hostTag = "방장"
    const val invitedTag = "초대 중"
    const val joinedTag = "참가"
    const val needFour = "4명이 모여야 시작해요"
    const val unseenDrop = "앱을 끈 사람은 시작할 때 빠져요"
    const val waitingHost = "방장이 시작하기를 기다리고 있어요"
    const val noRoomHint = "[초대]를 누르면 방이 열리고 바로 불러요 · 방에서 넷째를 기다리며 혼자 연습할 수 있어요"
    const val roomViewButton = "방 보기"
    const val practiceViewButton = "연습판 보기"
    const val practiceTitle = "혼자 연습"
    const val practiceTimedOff = "넉넉히"
    const val practiceTimedOn = "실전처럼 5+20"
    const val practiceTimeLabel = "생각 시간"
    const val practiceSeatNote = "내 자리는 무작위예요"
    const val practiceNoRuby = "연습판은 루비·기록이 없어요"
    const val practiceStart = "연습 시작"
    const val practiceAgain = "다시 하기"
    const val practiceEnd = "연습 끝내기"
    const val comeBack = "돌아왔어요"
    const val awayHint = "자리 비움 — 차례가 오면 저절로 버려요"
    const val autoChip = "자동"
    const val deletedChip = "탈퇴"
    const val dealerChip = "친"
    const val riichiChip = "리치"
    const val waitingOthers = "기다리는 중…"
    const val wallRemaining = "남은 패"
    const val tsumo = "쯔모"
    const val ron = "론"
    const val riichi = "리치"
    const val kan = "깡"
    const val kanMore = "깡 ▸"
    const val kyuushu = "구종구패"
    const val pon = "퐁"
    const val chi = "치"
    const val pass = "넘기기"
    const val cancel = "취소"
    const val riichiArmedHint = "리치 — 버릴 패를 고르세요(밝은 패만)"
    const val kuikaeHint = "방금 운 패와 같은 패는 이번에 못 버려요"
    const val noYakuHint = "역 없음 — 쯔모나 리치로만 화료"
    const val furitenChip = "후리텐 — 론 불가, 쯔모만"
    const val waitsTitle = "기다리는 패"
    const val reserve = "예비"
    const val toLobby = "로비로"
    const val rematch = "한 판 더"
    const val crampedNotice = "화면이 좁아 마작 판이 잘려요"
    const val updateRequired = "앱을 업데이트해 주세요"
    const val unavailable = MahjongNoticeText.unavailable
    const val aidAutoWin = "자동 화료"
    const val aidNoCalls = "울지 않기"
    const val aidTsumogiri = "쯔모기리"
    const val recordUnranked = "10판부터 순위"
    const val rankHeader = "평균 등수 순 · 10판 이상"
    const val emptyRanking = "아직 10판을 채운 사람이 없어요"
    const val gamesUntilRanked = "판 더 하면 순위에 올라요"
    const val firstTimeTitle = "처음이에요"
    const val lockedLabel = "지금은 초대할 수 없어요"
    /** 연습판 봇 자리 카드 꼬리표. */
    const val practiceBotTag = "연습 상대"

    /** 소수 둘째 자리(Swift `%.2f` — 반올림). */
    fun twoDecimals(v: Double): String {
        val scaled = (abs(v) * 100).roundToLong()
        val sign = if (v < 0 && scaled != 0L) "-" else ""
        return "$sign${scaled / 100}.${(scaled % 100).toString().padStart(2, '0')}"
    }

    fun record(avg: Double?, games: Int): String {
        if (games < MahjongRules.rankingMinGames || avg == null) return "${games}판 · $recordUnranked"
        return "평균 ${twoDecimals(avg)}등 · ${games}판"
    }

    fun stake(stake: Int?): String = "판돈 ${stake ?: 0}"
    fun seats(joined: Int): String = "$joined/4명"
    fun roomOf(name: String): String = "${name}님의 방"
    fun inviteFrom(name: String): String = "${name}님이 초대했어요"
    fun format(format: MahjongFormat?): String = if (format == MahjongFormat.hanchan) "반장전" else "동풍전"

    fun formatDetail(format: MahjongFormat): String = when (format) {
        MahjongFormat.tonpuu -> "동장 4국(기본)"
        MahjongFormat.hanchan -> "동장·남장 8국"
    }

    val windNames = listOf("동", "남", "서", "북")
    val windGlyphs = listOf("東", "南", "西", "北")

    fun wind(wire: String?): String = when (wire) {
        "E" -> "동"
        "S" -> "남"
        "W" -> "서"
        "N" -> "북"
        else -> "—"
    }

    /** "동 1국". */
    fun roundName(round: Int?, handNo: Int?): String = "${windNames[(round ?: 0).coerceIn(0, 3)]} ${(handNo ?: 0) + 1}국"

    fun honba(honba: Int?, kyotaku: Int?): String = "${honba ?: 0}본장 · 공탁 ${kyotaku ?: 0}"
    fun wall(count: Int?): String = "$wallRemaining ${count ?: 0}"

    /** 천 단위 쉼표(Swift `.number.grouping(.automatic)` — 한국어 지역). */
    fun grouped(value: Int): String {
        val digits = abs(value.toLong()).toString()
        val out = StringBuilder()
        digits.forEachIndexed { i, ch ->
            if (i > 0 && (digits.length - i) % 3 == 0) out.append(',')
            out.append(ch)
        }
        return if (value < 0) "-$out" else out.toString()
    }

    fun score(value: Int?): String = value?.let(::grouped) ?: "—"

    fun delta(value: Int): String = when {
        value > 0 -> "+${grouped(value)}"
        value < 0 -> "−${grouped(-value)}"
        else -> "0"
    }

    fun net(value: Int): String = when {
        value > 0 -> "+$value"
        value < 0 -> "−${-value}"
        else -> "0"
    }

    fun rank(rank: Int?): String = rank?.let { "${it}위" } ?: "—"
    fun avgRank(avg: Double?): String = avg?.let { "평균 ${twoDecimals(it)}등" } ?: "—"
    fun remaining(seconds: Int): String = "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"
    fun nextHand(seconds: Int): String = "다음 국까지 ${seconds}초"
    fun backIn(seconds: Int): String = "$comeBack · ${seconds}초"

    /** "방 3/4 · 남은 7:12". */
    fun roomBand(joined: Int, seconds: Int): String = "방 $joined/4 · 남은 ${remaining(seconds)}"
    const val roomBandReady = "4명이 모였어요"

    /** 분배 안내(`[3N, N, 0, 0]` 지급, 순수익 +2N · 0 · −N · −N). */
    fun split(stake: Int): String = "1위 +${stake * 2} · 2위 본전 · 3·4위 −$stake"

    fun handEnd(reason: String?): String = when (reason) {
        "exhaustive" -> "황패 유국"
        "kyuushu" -> "구종구패 유국"
        "suufon" -> "사풍연타 유국"
        "suukaikan" -> "사개깡 유국"
        "suucha_riichi" -> "사가 리치 유국"
        "nagashi" -> "유국만관"
        else -> "유국"
    }

    fun matchEnd(reason: String?): String = when (reason) {
        "tobi" -> "점수가 0 아래로 내려간 사람이 나와 끝났어요"
        "agari_yame", "tenpai_yame" -> "마지막 국의 친이 1위로 끝냈어요"
        "target_reached" -> "연장에서 30000점을 넘은 사람이 나와 끝났어요"
        "max_round" -> "마지막 국까지 마쳤어요"
        "void" -> "판이 무효가 되어 판돈을 돌려줬어요"
        else -> "판이 끝났어요"
    }

    fun limitName(limit: String?): String? = when (limit) {
        "mangan" -> "만관"
        "haneman" -> "하네만"
        "baiman" -> "배만"
        "sanbaiman" -> "삼배만"
        "yakuman" -> "역만"
        else -> null
    }
}

/** 폰에서만 쓰는 글자(맥에 없는 손짓 · 화면 안내). */
object GamesMahjongPhoneText {
    const val cardSubtitle = "리치 마작 4인 대국 · 방을 열어 초대하거나 혼자 연습해요"
    const val cardOpenHint = "아잉 마작 로비를 열어요"
    const val rotating = "가로로 돌리면 판이 보여요"
    const val twoTapHint = "한 번 누르면 들리고, 한 번 더 누르면 버려요"
    const val aidTwoTap = "두 번 눌러 버리기"
    const val aidCorner = "패 귀퉁이 글자"
    const val aidsTitle = "보조"
    const val leaveTitle = "판에서 나갈까요?"
    const val leaveDetail = "기권이 아니에요. 판은 끝까지 가고, 차례가 오면 저절로 버려요. 다시 들어와 손패를 누르면 돌아와요."
    const val leaveConfirm = "나가기"
    const val stay = "계속 두기"
    const val roomTitle = "내 방"
    const val roomEmpty = "방을 열고 사람을 초대하면 넷이 모일 때 시작할 수 있어요"
    const val createRoomHint = "방을 열면 초대한 사람(또는 공개면 누구나)이 들어올 수 있어요"
    const val rankingTitle = "마작 순위"
    const val lobbyCaption = "근무 중이 아니어도 초대하고 참가할 수 있어요"
    const val practiceHelp = "봇 셋과 루비 · 기록 없이 둬요"
}

/** 화면 고르기(맥 `MahjongScreen.of` 와 같은 판정). */
enum class GamesMahjongScreenRule {
    unavailable, lobby, table;

    companion object {
        /** `dismissedMatchID` = 판 결과에서 [로비로]를 누른 판(그 판이 finished 로 남아 있어도 로비를 보인다). */
        fun of(store: MahjongStore, dismissedMatchID: String?): GamesMahjongScreenRule {
            if (store.availability != MahjongAvailability.available && !store.isPractice) return unavailable
            if (store.isPractice) return table
            val match = store.match?.match
            if (match != null && store.match?.mySeat != null &&
                (match.matchStatus == MahjongMatchStatus.active || (match.matchStatus == MahjongMatchStatus.finished && match.id != dismissedMatchID))
            ) return table
            return lobby
        }
    }
}

/** 규칙 · 역 표(다른 마작 서비스 이름은 쓰지 않는다). */
object GamesMahjongRulesText {
    data class Rule(val title: String, val detail: String, val example: String)

    val rules: List<Rule> = listOf(
        Rule("목표", "4몸통(같은 패 셋 또는 이어진 셋) + 1머리(같은 패 둘)를 먼저 만들면 화료예요.", "123m456p789s11122z"),
        Rule("역이 하나는 있어야 화료", "리치 · 멘젠쯔모 · 탕야오(2~8만 쓴 손) · 역패(백·발·중 셋)가 가장 흔해요.", "234m345p456s678s55p"),
        Rule(
            "버리기 · 울기",
            "내 차례에 한 장 가져와 한 장 버려요. 남이 버린 패로 퐁(같은 패 셋)·깡(넷)·론을 할 수 있고, " +
                "치(이어진 셋)는 왼쪽 사람이 버린 패로만 돼요.",
            "",
        ),
        Rule("리치", "울지 않은 손이 텐파이(한 장만 더 오면 화료)일 때 1000점을 걸고 선언해요. 그 뒤로는 손을 바꿀 수 없어요.", ""),
        Rule("후리텐", "기다리는 패를 내가 이미 버렸다면 론으로 날 수 없어요. 쯔모로는 날 수 있어요.", ""),
        Rule("유국", "패산이 다 떨어지면 텐파이한 사람이 노텐인 사람에게서 점수를 받아요.", ""),
        Rule("판 길이", "동풍전(동장 4국, 기본) · 반장전(동·남장 8국). 마지막에 1위가 30000점 미만이면 연장해요.", ""),
        Rule("생각 시간", "한 번에 5초 + 국마다 예비 20초 · 넘기면 저절로 버리거나 넘겨요. 날 수 있으면 저절로 화료해요.", ""),
        Rule("자리 비움", "창을 닫거나 [나가기]를 눌러도 판은 끝까지 가요. 차례가 오면 저절로 버리고, 손패를 한 번 누르면 돌아와요.", ""),
        Rule("판돈", "시작할 때 넷 모두에게서 판돈을 걷고 1위 +2N · 2위 본전 · 3·4위 −N 으로 나눠요. 새로 생기는 루비는 없어요.", ""),
    )

    const val footer = "가장 널리 쓰이는 온라인 리치 마작 규칙과 같아요 · 적도라 3장 · 쿠이탕 있음 · 후리텐·쿠이카에 있음"

    data class YakuRow(val yaku: MahjongYaku, val closed: Int, val open: Int?)

    val yakuTable: List<YakuRow> = listOf(
        YakuRow(MahjongYaku.riichi, 1, null), YakuRow(MahjongYaku.doubleRiichi, 2, null), YakuRow(MahjongYaku.ippatsu, 1, null),
        YakuRow(MahjongYaku.menzenTsumo, 1, null), YakuRow(MahjongYaku.pinfu, 1, null), YakuRow(MahjongYaku.iipeikou, 1, null),
        YakuRow(MahjongYaku.tanyao, 1, 1), YakuRow(MahjongYaku.yakuhaiHaku, 1, 1), YakuRow(MahjongYaku.yakuhaiHatsu, 1, 1),
        YakuRow(MahjongYaku.yakuhaiChun, 1, 1), YakuRow(MahjongYaku.bakaze, 1, 1), YakuRow(MahjongYaku.jikaze, 1, 1),
        YakuRow(MahjongYaku.chankan, 1, 1), YakuRow(MahjongYaku.rinshan, 1, 1), YakuRow(MahjongYaku.haitei, 1, 1),
        YakuRow(MahjongYaku.houtei, 1, 1), YakuRow(MahjongYaku.chiitoitsu, 2, null), YakuRow(MahjongYaku.sanshoku, 2, 1),
        YakuRow(MahjongYaku.ittsu, 2, 1), YakuRow(MahjongYaku.chanta, 2, 1), YakuRow(MahjongYaku.toitoi, 2, 2),
        YakuRow(MahjongYaku.sanankou, 2, 2), YakuRow(MahjongYaku.sanshokuDoukou, 2, 2), YakuRow(MahjongYaku.sankantsu, 2, 2),
        YakuRow(MahjongYaku.honroutou, 2, 2), YakuRow(MahjongYaku.shousangen, 2, 2), YakuRow(MahjongYaku.honitsu, 3, 2),
        YakuRow(MahjongYaku.junchan, 3, 2), YakuRow(MahjongYaku.ryanpeikou, 3, null), YakuRow(MahjongYaku.chinitsu, 6, 5),
    )

    val yakumanList: List<MahjongYaku> = listOf(
        MahjongYaku.heavenly, MahjongYaku.earthly, MahjongYaku.kokushi, MahjongYaku.kokushi13, MahjongYaku.suuankou, MahjongYaku.suuankouTanki,
        MahjongYaku.daisangen, MahjongYaku.shousuushii, MahjongYaku.daisuushii, MahjongYaku.tsuuiisou, MahjongYaku.ryuuiisou,
        MahjongYaku.chinroutou, MahjongYaku.suukantsu, MahjongYaku.chuuren, MahjongYaku.junseiChuuren,
    )

    val fuRows = listOf(30, 40, 50, 60, 70)
    val hanColumns = listOf(1, 2, 3, 4)
}

/** 점수표 칸(론 점수 자 / 친 — 숫자는 규칙 점수 함수에서, 화면이 손으로 적지 않는다). */
object GamesMahjongScoreCell {
    fun text(han: Int, fu: Int): String {
        val child = MahjongScoring.scoreOf(han, fu, dealer = false, tsumo = false).total
        val dealer = MahjongScoring.scoreOf(han, fu, dealer = true, tsumo = false).total
        return "$child/$dealer"
    }

    const val caption = "칸 = 론 점수(자 / 친) · 만관 이상은 판으로만 정해져요"
}

/** 더블론 넘김(맥 `MahjongResultPaging` 과 같은 식). */
object GamesMahjongResultPaging {
    /** 서버 쉬는 시간(초) = 7 + 4 × (화료자 − 1). */
    fun restSeconds(winners: Int): Double = 7 + 4 * (maxOf(1, winners) - 1).toDouble()

    /** 지금 보일 화료자 번호. */
    fun index(winners: Int, nextHand: SwiftDate?, now: SwiftDate): Int {
        if (winners <= 1 || nextHand == null) return 0
        val rest = restSeconds(winners)
        val interval = (rest - 1.5) / winners
        val elapsed = now.timeIntervalSince(nextHand.addingTimeInterval(-rest))
        return (elapsed / interval).toInt().coerceIn(0, winners - 1)
    }
}

/** 폰 보조 기본값(두 번 눌러 버리기 — 폰은 켜짐으로 시작한다. 한 번 켜고 끈 값은 기기에 남는다). */
object GamesMahjongPhoneAids {
    const val seededKey = "check.mahjong.phone.twoTapSeeded"

    /** 처음 한 번, 폰 기본(두 번 눌러 버리기 켜짐)을 심는다. */
    fun seedIfNeeded(store: MahjongStore, defaults: KeyValueStore?) {
        defaults ?: return
        if (defaults.getBoolean(seededKey) == true) return
        defaults.putBoolean(seededKey, true)
        if (!store.aids.twoClickDiscard) store.aids = store.aids.copy(twoClickDiscard = true)
    }

    fun twoTap(store: MahjongStore): Boolean = store.aids.twoClickDiscard
}
