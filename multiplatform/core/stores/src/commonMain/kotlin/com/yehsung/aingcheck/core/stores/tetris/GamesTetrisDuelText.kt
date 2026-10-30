// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelText.swift @ 1b8260d
@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.time.Instant

/**
 * 폰 1:1 테트리스(1.0.11) 문구 표.
 *
 * ── 어디까지가 이 표의 몫인가 ──
 * **안내·결과 사유는 코어가 쥔다**([TetrisDuelNoticeText] — 신청·취소·수락·기권 응답과 결과 카드의 사유 한 줄). 맥과 폰이 같은 서버 응답을
 * 같은 말로 옮겨야 하므로 그 표를 **다시 쓰지 마라.** 이 표는 **화면에 붙는 글자**(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다.
 *
 * ── 맥 `TetrisDuelText` 와 갈리는 곳은 셋이다 ──
 * ① **조작**: 맥은 키 표, 폰은 제스처 + 버튼 셋이다(솔로 폰 테트리스와 같은 조작).
 * ② **판을 떠나는 일의 뜻이 반대다.** 맥은 "창을 가리거나 내려도 판은 계속 흘러가요" 가 **안심**이고(D10), 폰은 앱을 나가면 판 루프가 멎어
 *    15초 침묵으로 **진다**(서버 D5). 그래서 같은 자리의 문장이 **경고**다 — [leaveWarning] 이 그 자리를 대신한다.
 * ③ 입구가 카드다(게임 탭) — 칩·보조 줄·보이스오버 힌트가 체스 카드와 같은 꼴로 더 있다.
 */
object TetrisPhoneText {
    // MARK: - 공용

    const val title: String = "1:1 테트리스"

    /** 게임 탭 카드 부제 · 로비 머리글 부제(맥과 같은 한 줄 — 승부 방식을 먼저 말한다). */
    const val subtitle: String = "공격형 · 먼저 꼭대기까지 쌓이면 져요"
    const val cardSubtitle: String = subtitle

    /** 게임 탭 카드의 보이스오버 힌트(막히지 않았을 때). */
    const val cardOpenHint: String = "1:1 테트리스 대결 화면을 열어요"
    const val close: String = "닫기"

    /** 판돈 줄. 이기면 **순이익**(`DuelFee.winnerNet` — v0.3.64 부터 수수료 0 이라 +판돈) — 결과 카드의 루비 변화와 같은 숫자다. */
    fun stakeLine(stake: Int): String = "$stake · 이기면 +${DuelFee.winnerNet(stake)}"
    fun challengeWithStake(stake: Int): String = "$stake 걸고 신청하기"
    fun stakePromptTitle(name: String): String = "${name}님에게 신청"
    const val stakePromptCaption: String = "판돈을 고르세요"

    fun record(wins: Int, losses: Int, draws: Int): String = "${wins}승 ${losses}패 ${draws}무"

    fun record(record: TetrisDuelRecord?): String =
        if (record == null) record(0, 0, 0) else record(record.wins, record.losses, record.draws)

    fun points(value: Int): String = "승점 ${if (value >= 0) "+" else ""}$value"

    /** 남은 초(신청 TTL · 준비 대기). 음수는 0 으로. */
    fun remainingSeconds(seconds: Int): String = "${maxOf(0, seconds)}초 남음"

    /**
     * 규칙 보기. 공격 표 · 가속 · 침묵 · 판돈은 **설계서 결정 그대로**다(D2 · D5 · D7 · D4).
     * INV-GamesTetrisDuelText-11d25ef1 이식: "연결" 항목이 맥과 다르다(머리말 ②) — 폰은 앱을 나가면 진다("앱을 나가면" 항목).
     */
    const val rulesTitle: String = "1:1 테트리스 규칙"
    val rules: List<Pair<String, String>>
        get() = listOf(
            "공격" to ("2줄을 한 번에 지우면 상대에게 방해 줄 1줄, 3줄은 2줄, 4줄은 4줄을 보내요. " +
                "들어올 방해 줄이 있으면 내가 보낼 줄이 먼저 그것을 지워요."),
            "방해 줄" to "줄을 지우지 못한 채 조각이 굳으면 아래에서 회색 줄이 올라와요. 판 왼쪽 빨간 막대가 들어올 줄이에요.",
            "승부" to "먼저 꼭대기까지 쌓이는 쪽이 져요. 2분이 지나면 떨어지는 속도가 점점 빨라져요.",
            "조작" to ("판을 좌우로 끌어 옮기고, 아래로 끌어 내려요. 판을 톡 누르면 회전해요. " +
                "아래 버튼으로 $holdButton · $rotateCounterButton 회전 · ${hardDropButton}를 해요."),
            "앱을 나가면" to "판 중에 앱을 나가면 판이 멈춰서 15초 뒤에 져요. 대결이 끝날 때까지 앱을 켜 두세요.",
            // v0.3.64: 판돈 수수료를 없앴다(사용자 결정 2026-10-22) — 맥 `TetrisDuelText` 규칙 줄과 같은 문장.
            "판돈" to ("수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, " +
                "무승부면 돌려받아요. 30초 안에 둘 다 들어오지 않아도 돌려받아요."),
        )

    // MARK: - 로비

    const val usersTab: String = "상대 고르기"
    const val rankTab: String = "순위"
    const val lobbyCaption: String = "근무 중이 아니어도 신청하고 받을 수 있어요"
    const val emptyUsers: String = "지금 대결할 수 있는 사람이 없어요"
    const val loadingUsers: String = "상대 목록을 불러오고 있어요"

    // INV-GamesTetrisDuelText-0e0b2986 이식: **불러오기 실패 문구·[다시 시도] 버튼을 이 표에 두지 마라.** 폰은 공용 부품 한 벌이 쥔다
    //   (`MobileLoadText.retry`·`.checkConnection` — games/MobileLoadKnowledge.kt). 같은 리터럴을 여기 또 적으면 두 벌이 된다.
    /**
     * 상대 목록을 불러오지 못했다(한 번도 못 받았을 때만 그린다 — `MobileLoadKnowledge`).
     * INV-GamesTetrisDuelText-0faa6833 이식: 값이 **맥 표와 다르다**: 맥은 공용 연결 안내를 그대로 쓰는데, 폰에서 그 문장은 공용 부품 한 벌이
     * 쥔다. [다시 시도] 글자도 여기 없다 — 공용 실패 행이 공용 글자로 그린다.
     */
    const val usersLoadFailed: String = "상대 목록을 불러오지 못했어요"
    const val challenge: String = "신청"
    const val needsUpdate: String = "앱 업데이트 필요"
    const val inMatch: String = "대결 중"
    const val working: String = "근무 중"
    const val focused: String = "집중 모드"

    const val stakeTitle: String = "판돈"
    const val incomingTitle: String = "받은 신청"
    const val incomingChip: String = "받은 신청"
    fun incomingMore(count: Int): String = "외 ${count}건"
    const val outgoingTitle: String = "보낸 신청"
    const val outgoingLine: String = "보낸 신청의 답을 기다리고 있어요"
    const val noIncoming: String = "받은 신청이 없어요"
    const val accept: String = "수락"
    const val decline: String = "거절"
    const val cancel: String = "취소"

    /** 칩도 보조 줄도 없을 때의 카드 한 줄(= 할 일을 말한다). */
    const val idleLine: String = "사람을 골라 대결을 신청해 보세요"

    const val recordTitle: String = "내 전적"
    const val liveTitle: String = "지금 대결 중"
    const val noLive: String = "지금 진행 중인 대결이 없어요"
    const val myMatch: String = "내 판"

    const val rankLoading: String = "순위를 불러오고 있어요"
    const val rankEmpty: String = "아직 순위가 없어요"
    const val rankSoon: String = "순위는 곧 열려요"
    const val rankHelp: String = "승점 = 승 − 패"

    /** "M월 d일부터"(Swift `DateFormatter` ko_KR · 기기 시간대 — 같은 시간대를 넘겨야 같은 글자다). */
    fun rankSince(date: SwiftDate, timeZone: TimeZone = TimeZone.currentSystemDefault()): String {
        val millis = floor(date.timeIntervalSince1970 * 1000).toLong()
        val local = Instant.fromEpochMilliseconds(millis).toLocalDateTime(timeZone)
        return "${local.month.ordinal + 1}월 ${local.day}일부터"
    }

    // ── 상대 한 줄 ──

    const val notWorking: String = "근무 안 함"

    /** 상대 한 줄의 두 자리. **한 함수가 둘을 같이 고른다** — 자리마다 따로 고르면 같은 문장이 한 줄에 두 번 나오고 근무 축이 덮인다. */
    data class OpponentRow(val subtitle: String, val buttonTitle: String)

    /**
     * 부제는 **늘 근무 축**, 버튼은 **막힌 까닭 하나**다. 겹치는 갈래(옛 버전 + 대결 중 + 집중)에서 버튼이 못 말한 축을 부제 꼬리로 보낸다.
     * 서열은 **옛 버전이 먼저**다(가장 오래 가는 막힘). 서버 `capable` 이 null 로 와도 코어가 false 로 읽으므로 **모르는 상대는 불가로 그린다**.
     *
     * INV-GamesTetrisDuelText-71ff824c 이식: 버튼이 [신청]인 것과 코어의 `canBeChallenged` 가 **같은 집합**이어야 한다(시험이 16 갈래를 다 센다).
     */
    fun opponentRow(user: TetrisDuelUser): OpponentRow {
        val work = if (user.isWorking) working else notWorking
        val tail = mutableListOf<String>()
        val button: String
        if (!user.isCapable) {
            button = needsUpdate
            if (user.inMatch) tail += inMatch
            if (user.isFocused) tail += focused
        } else if (user.inMatch) {
            button = inMatch
            if (user.isFocused) tail += focused
        } else if (user.isFocused) {
            button = focused
        } else {
            button = challenge
        }
        return OpponentRow(subtitle = (listOf(work) + tail).joinToString(" · "), buttonTitle = button)
    }

    fun peopleCount(count: Int): String = "${count}명"
    fun liveCount(count: Int): String = "${count}판"

    /** [신청] 버튼의 보이스오버 힌트 — 누르면 **바로 신청이 나가지 않는다**(판돈 시트가 먼저다). */
    fun challengeHint(name: String): String = "${name}님에게 판돈을 골라 신청해요"

    /** 머리 두 칸 왼쪽(내 전적)의 보이스오버. */
    fun myRecordAccessibility(record: TetrisDuelRecord?): String = "내 1:1 테트리스 전적 ${record(record)}"

    // ── 신청 카드 ──

    fun incomingTitle(name: String): String = "${name}님의 신청"
    fun outgoingTitle(name: String): String = "${name}님에게 신청했어요"

    /**
     * 받은 신청 절 머리의 오른쪽 한 줄.
     * INV-GamesTetrisDuelText-168b051d 이식: **초를 박지 않는다** — 서버가 `invite_ttl_seconds` 로 말하고 코어가 그 값을 쥔다
     * (`TetrisDuelStore.inviteTTLSeconds`). 상수를 베끼면 서버가 TTL 을 바꾼 날 화면만 옛 숫자다.
     */
    fun inviteTtlHint(ttlSeconds: Int): String = "${ttlSeconds}초 안에 응답하세요"

    /**
     * INV-GamesTetrisDuelText-82d76964 이식: 신청만 한 상태를 말하는 줄. "신청하면 빠져요" 로 적으면 **거짓**이다 — 신청은 0원도 움직이지 않고
     * 응답이 없으면 그대로 사라진다. 빠지는 순간은 **수락**이다(서버 `tetris_respond`).
     */
    fun stakeNotHeldYet(ttlSeconds: Int): String = "신청만 해서는 루비가 빠지지 않아요 · ${ttlSeconds}초 안에 응답이 없으면 신청이 사라져요"

    fun remaining(seconds: Double): String = "${ceil(maxOf(0.0, seconds)).toInt()}초"

    /** "42초 남음"(받은·보낸 신청 부제 · 준비 대기). */
    fun remainingPhrase(seconds: Double): String = "${remaining(seconds)} 남음"

    /** 남은 초의 보이스오버("남은 시간 42초") — 화면 글자와 어순이 다르다. */
    fun remainingAccessibility(seconds: Double): String = "남은 시간 ${remaining(seconds)}"

    // ── 판돈 고르기 ──

    /** 고를 수 있는 판돈 셋(3 · 5 · 10). 집합의 주인은 서버(`stakes`)이고 앱 값과 갈리면 진실은 거절한 쪽에 있다. */
    val stakes: List<Int> get() = TetrisDuelStake.entries.map { it.rawValue }

    /** "이기면 +5" — 판돈 칸 아래 줄(꼬리 [stakeGainSuffix] 와 달리 앞 가운뎃점이 없다). */
    fun stakeGain(stake: Int): String = "이기면 +${DuelFee.winnerNet(stake)}"
    fun stakeGainSuffix(stake: Int): String = " · 이기면 +${DuelFee.winnerNet(stake)}"
    fun stakePromptChosen(stake: Int): String = "판돈 ${stakeLine(stake)}"

    /** 루비가 모자라 못 고르는 판돈의 이유 한 줄. 정본은 앱의 다른 화면과 **같은 말**이다. */
    val stakeShortfall: String get() = DuelShortfallText.shortfallNotice(null, null)

    /** 판돈이 **언제** 빠지는지(주어가 '수락'이다) — 오목·체스와 같은 한 문장. */
    const val stakeCaption: String = GomokuPhoneText.stakeCaption
    const val selected: String = "선택됨"
    fun stakeOptionAccessibility(stake: Int): String = "판돈 루비 $stake"

    const val myRubyTitle: String = "내 루비"

    /** 값을 아직 모르는 숫자 칸(루비 잔액 미러가 비었다). */
    const val unknownNumber: String = "–"

    /** 한 줄 안에서 토막을 잇는 머리("· 루비가 모자라요"). */
    const val bulletPrefix: String = "· "

    // ── 지금 대결 중 ──

    /** "테트라이벌 vs 구름빵" — 로비 "지금 대결 중" 한 줄. */
    fun liveRow(a: String, b: String): String = "$a vs $b"

    // ── 순위 탭 ──

    const val rankTitle: String = "테트리스 순위"

    /** 절 아래 캡션(승점의 뜻) — [rankHelp] 과 같은 한 문장이다(두 벌로 적지 않는다). */
    val rankCaption: String get() = rankHelp

    /** 0판인 사람은 순위판에 안 낀다(서버가 아예 안 준다). 빈 순위를 사고로 읽지 않게 하는 줄이다. */
    const val rankZeroGamesNote: String = "한 판도 대결하지 않으면 순위에 들어가지 않아요"
    const val rankEmptyHint: String = "첫 대결이 끝나면 순위가 올라와요"
    const val rankLoadFailed: String = "순위를 불러오지 못했어요"

    /** 실패 줄 **아래** 한 줄 — 원인이 둘(연결·구버전 거절)인데 화면이 가릴 수 없으므로 단정하지 않는다. */
    const val rankLoadFailedHint: String = "계속 안 되면 앱을 업데이트해 주세요"
    const val myRankTitle: String = "내 순위"
    const val outOfRank: String = "순위 밖"

    /** 컷이 없다(응답 `record_since_ms` 가 null) — 기간이 통째다. */
    const val rankWholePeriod: String = "전체 기간"

    /** 접힌 상태에서 보여 주는 행 수 · 펼쳤을 때의 상한(서버도 100행까지 준다 — D11). */
    const val rankCollapsedRows: Int = 5
    const val rankRowLimit: Int = 100
    fun rankSeeAll(total: Int): String = "전체 보기 · ${peopleCount(total)}"
    const val rankCollapse: String = "접기"

    /** 목록 밖 내 순위 한 줄 — "12위 · 승점 +4 · 6승 2패 1무"(0판이면 "순위 밖 · 0승 0패 0무"). */
    fun myRankLine(mine: TetrisDuelMyRank): String {
        val line = record(mine.wins, mine.losses, mine.draws)
        val rank = mine.rank ?: return "$outOfRank · $line"
        return "${rank}위 · ${points(mine.points)} · $line"
    }

    /**
     * 순위 한 행의 보이스오버 — "3위, 나, 민트별, 승점 +4, 6승 2패 1무".
     * INV-GamesTetrisDuelText-5cc79af4 이식: 행은 **순위 · 이름 · 승점 · 승 · 패 · 무를 다 말한다**(체스·오목과 같은 사용자 지시).
     */
    fun rankRowAccessibility(entry: TetrisDuelRankEntry, isMe: Boolean): String {
        val parts = mutableListOf("${entry.rank}위")
        if (isMe) parts += me
        parts += entry.user.displayName
        parts += points(entry.points)
        parts += record(entry.wins, entry.losses, entry.draws)
        return parts.joinToString(", ")
    }

    // MARK: - 대결

    const val me: String = "나"
    const val elapsedTitle: String = "경과"

    /** 2분이 지나 가속이 걸렸다(D7 — 레벨 바닥이 1 을 넘었다). */
    const val speedUp: String = "속도 올라가는 중"
    fun speedLevel(level: Int): String = "레벨 $level"
    const val connectionTrouble: String = "연결 확인 중"
    const val opponentSilent: String = "상대 연결 확인 중"
    const val linesTitle: String = "지운 줄"
    const val attackTitle: String = "보낸 공격"
    const val incomingLinesTitle: String = "들어올 줄"
    const val ready: String = "준비 완료"
    const val notReady: String = "들어오는 중"
    const val finishedPresence: String = "대결 끝"
    const val waitingTitle: String = "상대를 기다리는 중"
    fun waitingSubtitle(seconds: Int): String = "${maxOf(0, seconds)}초 안에 둘 다 들어오면 시작해요"

    /** 맥은 "창을 열어 두세요", 폰은 앱이다. */
    const val waitingAction: String = "앱을 켜 둔 채 기다려 주세요"
    const val startingSoon: String = "곧 시작해요"
    const val playingNow: String = "대결 중"
    const val toppedOutTitle: String = "꼭대기에 닿았어요"
    const val toppedOutSubtitle: String = "결과를 기다리는 중"

    /**
     * INV-GamesTetrisDuelText-b3421f3f 이식: 판 위에 **늘 보이는 한 줄**(머리말 ②). 규칙 시트에만 두면 안 된다 — 판 중에 전화가 와서 나가는
     * 사람은 규칙을 읽지 않는다. 판돈이 걸린 판을 조용히 잃는 길을 글자 없이 두지 않는 것이 이 줄의 일이다.
     */
    const val leaveWarning: String = "판 중에 앱을 나가면 져요"

    const val resign: String = "기권"
    const val confirmResign: String = "기권하기"
    const val keepPlaying: String = "계속하기"
    const val resignWarning: String = "기권하면 판돈을 잃어요"
    const val backToLobby: String = "로비로"

    const val controlsTitle: String = "조작"

    /** 조작 안내(솔로 폰과 같은 제스처·버튼). **정지는 없다** — 대결은 멈출 수 없다. */
    val controls: List<Pair<String, String>>
        get() = listOf(
            "좌우로 끌기" to "이동", "톡 누르기" to "회전", "아래로 끌기" to "빨리 내리기",
            "[$holdButton]" to holdButton,
            "[$rotateCounterButton]" to "$rotateCounterButton 회전",
            "[$hardDropButton]" to hardDropButton,
        )

    fun outcomeTitle(outcome: TetrisDuelOutcome?): String = when (outcome) {
        TetrisDuelOutcome.won -> "이겼어요"
        TetrisDuelOutcome.lost -> "졌어요"
        TetrisDuelOutcome.draw -> "무승부예요"
        null -> "대결이 끝났어요"
    }

    /** 판 시계 글자(`m:ss`). 음수는 0 으로. */
    fun clock(seconds: Double): String {
        val whole = floor(maxOf(0.0, seconds)).toInt()
        return "${whole / 60}:${(whole % 60).toString().padStart(2, '0')}"
    }

    /** 루비 증감 글자(+N / −N / 0). */
    fun rubyDelta(value: Int): String = if (value > 0) "+$value" else "$value"

    // ── 대결 절 (판 화면·캔버스가 읽는다) ──

    /** 판 위 글자 겹. 솔로 캔버스와 **같은 말**이고 자리는 코어 배치 표가 정한다. */
    const val holdLabel: String = "홀드"
    const val nextLabel: String = "다음"

    /** 값 자리는 자기설명형이다 — 폰은 8pt 캡션을 못 쓴다. */
    fun levelValue(level: Int): String = "Lv $level"
    fun linesValue(lines: Int): String = "${lines}줄"

    /** 판 밑 밴드·상대 줄의 들어올 줄(미터와 같은 빨강으로 쓴다). */
    fun incomingLines(lines: Int): String = "$incomingLinesTitle $lines"

    const val myBoardLabel: String = "내 판"
    const val opponentBoardLabel: String = "상대 판"

    /**
     * 조작 버튼 세 개의 **글자**. [controls] 표의 꺾쇠 안 말과 **같아야 한다**.
     * INV-GamesTetrisDuelText-8afe2c57 이식: **솔로 표를 가리킨다**(글자를 베끼지 않는다). 같은 기기의 같은 버튼이 화면에 따라 두 이름으로
     *   불리면, 솔로로 배운 사람이 대결에서 버튼을 다시 찾는다. 가리키면 나중에 솔로 말이 바뀌어도 둘이 갈라지지 않는다.
     */
    const val holdButton: String = GamesMiniGameText.tetrisHold
    const val rotateCounterButton: String = GamesMiniGameText.tetrisRotateCounterClockwise
    const val hardDropButton: String = GamesMiniGameText.tetrisHardDrop

    /** 홀드를 이미 쓴 조각(버튼의 보이스오버 값). */
    const val holdSpent: String = "이미 썼어요"

    /** 기권 확인 시트 제목(본문은 [resignWarning] · 버튼은 [confirmResign]/[keepPlaying]). */
    const val resignConfirmTitle: String = "기권할까요?"

    /**
     * 한 판 한 기기(0.3.69) — 같은 계정의 다른 기기가 두는 판의 덮개 카드(제목은 코어 [TetrisDuelNoticeText.otherDevice]).
     * 맥 `TetrisDuelText` 의 같은 자리와 **같은 말**이다. 기다리라는 말([waitingAction])을 여기에 두지 않는다 — 이 폰이
     * 기다릴 것이 없다.
     */
    const val otherDeviceSubtitle: String = "신청하거나 수락한 기기에서만 둘 수 있어요"
    const val otherDeviceAction: String = "그 기기에서 이어 가세요"

    // MARK: - 관전 (0.3.65)

    /** 로비 "지금 대결 중" 행의 [관전] 알약. 낱말은 오목·체스와 **같다**. */
    const val watchChip: String = "관전"
    const val watchChipHint: String = "이 판을 지켜봐요"

    /** 서버에 `tetris_watch` 가 아직 없을 때 칩 대신 서는 캡션. **짧게** 둔 것이 핵심이다. */
    const val watchSoonCaption: String = "곧 열려요"

    /** 관전 절 머리. */
    const val watchTitle: String = "관전 중"
    const val leaveWatch: String = "나가기"
    const val leaveWatchHint: String = "로비로 돌아가요"

    /**
     * 첫 응답 전(상태 상자 머리).
     * INV-GamesTetrisDuelText-7b56be10 이식: **끝난 판에는 이 말을 쓰지 않는다** — 폴링이 이미 멈춰 더 올 것이 없는데 진행형으로 말하면 거짓말이
     * 된다(체스가 데인 자리). 끝난 판의 머리는 [watchEnded]·[watchEndedDraw] 다.
     */
    const val watchLoading: String = "판을 불러오고 있어요"

    /** 판돈을 아직 모른다(씨앗 없이 들어온 첫 틱). */
    const val watchStakeUnknown: String = "$stakeTitle —"

    /** 이름을 모르는 자리(em dash). */
    const val watchUnknownName: String = "—"

    /** 카드 밑 작은 줄 — 입력이 하나도 없다는 사실. */
    const val watchCaption: String = "판만 보여 줘요 · 조작은 할 수 없어요"
    const val watchTailMinutes: Int = 3
    const val watchTailCaption: String = "끝난 판은 ${watchTailMinutes}분 동안만 볼 수 있어요"

    /** 끝난 판의 머리 한 줄 — **승자를 아는 판에는 쓰지 않는다**(그때는 [watchEndedWin]). */
    const val watchEnded: String = "대결이 끝났어요"
    const val watchEndedDraw: String = "무승부예요"

    /**
     * 끝난 판에서 **이긴 사람**을 가리키는 머리 한 줄.
     * INV-GamesTetrisDuelText-d5547441 이식: **3인칭이다.** 관전자에게는 둘 다 남이라 "이겼어요"·"졌어요" 로는 누구 이야기인지 알 수 없다 —
     *   그래서 **이름을 부른다**.
     * INV-GamesTetrisDuelText-ca288a4c 이식: 어느 자리가 이겼는지는 서버가 실은 `match.winner`(uuid)로만 가른다 — `result`('challenger_win'…)로
     *   역산하지 마라. 관전 봉투에는 누가 challenger 인지가 없고 a/b 는 **uuid 오름차순 자리**일 뿐이다.
     */
    fun watchEndedWin(name: String): String = "$name 승리"

    /**
     * 끝난 사유 한 줄 — **3인칭**이다. 내 기준 표([TetrisDuelNoticeText.endReason])를 쓰면 `outcome` 이 없어 언제나 패자 쪽 문장이 나오고,
     * 관전자가 "상대가 기권했어요" 를 읽는다(누구의 상대인가). 사유를 모르면 빈 문자열이고 그때 둘째 줄은 서지 않는다.
     */
    fun watchEndReason(reason: TetrisDuelEndReason?): String = when (reason) {
        null -> ""
        TetrisDuelEndReason.topout -> "꼭대기까지 쌓여서 끝났어요"
        TetrisDuelEndReason.resign -> "한쪽이 기권했어요"
        TetrisDuelEndReason.disconnect -> "연결이 끊겨서 끝났어요"
        TetrisDuelEndReason.timeCap -> "시간이 다 돼서 끝났어요"
        TetrisDuelEndReason.noShow -> "대결이 시작되지 않았어요"
        TetrisDuelEndReason.abandoned -> "대결이 중단됐어요"
    }

    /**
     * 관전 판 한 장을 가리키는 말.
     * INV-GamesTetrisDuelText-69b1e341 이식: **대국용 [opponentBoardLabel]("상대 판")을 쓰지 마라** — 관전자에게는 둘 다 '상대'가 아니다.
     */
    const val watchBoardLabel: String = "판"

    /** 관전 판 한 장의 보이스오버. **느린 값만**(지운 줄 · 들어올 줄). 이름이 앞에 선다. */
    fun watchBoardAccessibility(name: String, lines: Int, pending: Int): String =
        "$name $watchBoardLabel, $linesTitle $lines, $incomingLinesTitle $pending"
}
