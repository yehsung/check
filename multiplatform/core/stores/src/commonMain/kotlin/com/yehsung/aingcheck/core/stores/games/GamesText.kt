// 원본: Sources/CheckMobileKit/Games/GamesText.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameBoard
import kotlin.math.ceil

// 게임 탭 문구(SPEC-ios §3.5). **맥과 같은 뜻이면 같은 문장이다** — 출처를 줄마다 적는다.
//  · 미니게임 허브 문구는 맥 `MiniGamePanel` · `WorkTimerStoreMiniGame` 에서 옮겼다.
//  · 폰에서 새로 생긴 문장(탭 조작·앱을 나감·같은 칸 두 번)만 여기서 처음 쓴다.

/** 게임 탭 첫 화면·미니게임 화면 문구. */
object GamesText {
    const val tabTitle: String = "게임"

    // MARK: 첫 화면 카드

    /**
     * 카드의 오늘 한 줄(최고·순위). 순위 밖이면 최고만.
     * 내 줄이 없을 때 "오늘 기록 없음"은 **순위표를 알 때만**이다(`board.knowsPlayerCount`). 불러오지 못했으면 실패 문구,
     * 아직 모르면 불러오는 중 — 오프라인에서 "오늘 기록 없음"이라 말하던 결함(통합 검증 E-games).
     */
    fun todayLine(best: Long?, rank: Int?, board: GamesMiniGameBoard): String {
        if (best == null) {
            return when (board.placeholder) {
                MobileLoadKnowledge.Placeholder.rows, MobileLoadKnowledge.Placeholder.empty -> GamesMiniGameText.noRankToday
                MobileLoadKnowledge.Placeholder.failed -> recordLoadFailed
                MobileLoadKnowledge.Placeholder.loading -> GamesMiniGameText.loadingCaption
            }
        }
        // 자리수 구분("1,000")을 붙이지 않는다(맥 게임 표기와 같다).
        if (rank != null) return "오늘 최고 " + best.toString() + "점 · " + rank.toString() + "위"
        return "오늘 최고 " + best.toString() + "점"
    }

    /** 허브 카드: 오늘 순위표를 불러오지 못했다(폰). */
    const val recordLoadFailed: String = "기록을 불러오지 못했어요"

    /** 허브 오목 카드: 받은함을 불러오지 못했다(폰). */
    const val inboxLoadFailed: String = "받은 신청을 불러오지 못했어요"

    const val gomokuCardSubtitle: String = GomokuPhoneText.subtitle

    /**
     * 허브 오목 카드가 '대국 중'을 앞세울 것인가. **AI 판은 사람의 신청을 가리지 않는다**(2026-09-20 검증 low).
     * AI 판 중에도 받은함은 계속 받고 수락도 되므로, 받은 신청이 있으면 그쪽을 먼저 말한다. 사람 대국은 예전처럼 늘 먼저다.
     */
    fun hubShowsActiveMatch(active: Boolean, isAIMatch: Boolean, incoming: Int): Boolean = active && !(isAIMatch && incoming > 0)

    /**
     * 오목 카드의 한 줄. 진행 중인 대국이 먼저다(차례 시간이 흐르고 있다).
     * 받은 신청이 0건인데 받은함을 **못 불러왔으면** "상대를 골라…"(= 받은 게 없다는 뜻)로 접지 않고 실패를 말한다.
     */
    fun gomokuLine(incoming: Int, hasActiveMatch: Boolean, hasOutgoing: Boolean, inboxFailed: Boolean = false): String = when {
        hasActiveMatch -> "진행 중인 대국이 있어요"
        incoming > 0 -> "받은 신청 ${incoming}건"
        inboxFailed -> inboxLoadFailed
        hasOutgoing -> "보낸 신청을 기다리고 있어요"
        else -> "상대를 골라 대결을 신청해요"
    }

    const val openGame: String = "하기"

    // MARK: w15 재디자인(시안 B 07) — 폰에서 새로 쓴 줄

    /** 오른쪽 위 루비 알약을 누르면(보이스오버 힌트). */
    const val rubyPillHint: String = "상점을 열어요"
    const val todayRankTitle: String = "오늘 내 순위"
    const val seeAllRankings: String = "순위 탭에서 전체 보기"

    /** 허브 오목 칩: 진행 중인 판. */
    const val activeMatchChip: String = "대국 중"
    fun incomingChip(count: Int): String = "받은 신청 ${count}건"

    /** "오늘 내 순위" 행 부제 — 1등 한 줄과 참여 수("1위 민트별 962점 · 8명 참여"). 순위표를 모르면 불러오는 중·실패를 말한다. */
    fun hubRankSubtitle(board: GamesMiniGameBoard): String = when (board.placeholder) {
        MobileLoadKnowledge.Placeholder.rows -> {
            val leader = board.entries.firstOrNull()
            if (leader == null) GamesMiniGameText.noRankToday
            else "1위 " + leader.name + " " + GamesMiniGameText.score(leader.bestScore) + " · ${board.entries.size}명 참여"
        }
        MobileLoadKnowledge.Placeholder.empty -> "오늘은 아직 아무도 안 했어요"
        MobileLoadKnowledge.Placeholder.failed -> GamesMiniGameText.failedCaption
        MobileLoadKnowledge.Placeholder.loading -> GamesMiniGameText.loadingCaption
    }
}

/** 미니게임 허브 문구(맥 `MiniGamePanel` · `WorkTimerStoreMiniGame` 과 같은 말). */
object GamesMiniGameText {
    const val rankTitle: String = "오늘 순위"

    /**
     * 자정 상품(루비). 서버 `ruby_prize_amounts()` 와 짝인 상수(맥 `MiniGamePanel.rubyPrizes` · 같은 탭 `RankingsText.rubyPrizes`).
     * 2026-10-22(맥 0.3.64 · 서버 20261023131000) 사용자 결정("일반 미니게임 3종 상금루비 올려야할듯 20 10 5 로 다시 해줘")으로 20·10·5.
     * 서버는 금액을 내려 주지 않으므로 바꿀 땐 세 곳을 함께.
     */
    val rubyPrizes: List<Int> = listOf(20, 10, 5)

    /** 상품 정족수. 서버 `minigame_prize_quorum()` 과 짝인 상수(맥 `MiniGamePanel.prizeQuorum`). */
    const val prizeQuorum: Int = 5
    val prizeCaption: String get() = "자정에 1·2·3등에게 루비 ${rubyPrizes[0]}·${rubyPrizes[1]}·${rubyPrizes[2]}"
    const val emptyBoard: String = "아직 기록이 없어요 — 첫 기록의 주인공이 되세요"
    const val loadingCaption: String = "불러오는 중…"
    const val failedCaption: String = "순위를 불러오지 못했어요"
    const val retry: String = MobileLoadText.retry
    val awardedChip: String get() = "루비 +${rubyPrizes[0]} 받음"
    const val yesterdayChampion: String = "어제 1등"
    const val noRankToday: String = "오늘 기록 없음"

    /** 제출 실패(토큰 없음·네트워크) — 맥 `recordMiniGameScore` 와 같은 문장. */
    const val submitFailedConnection: String = "점수를 못 올렸어요 — 연결을 확인하고 다시 해 주세요"

    /** 서버 거절 — 맥 `performSubmitMiniGameScore` 와 같은 문장. status 이름·need_seconds 는 화면에 싣지 않는다. */
    const val submitRefused: String = "점수를 못 올렸어요"

    /**
     * 아직 하한을 못 넘겼다(`too_fast`) — **토큰은 살아 있고 곧 다시 보낸다.**
     * [submitRefused]("못 올렸어요")와 **일부러 가른다**: 이 응답은 거절이 아니라 아직 이르다는 뜻이다.
     * status 이름·`need_seconds`·`elapsed_seconds` 는 여기에도 싣지 않는다(위조 보조).
     */
    const val submitRetrying: String = "점수를 올리는 중이에요 — 잠깐만요"

    /**
     * 토큰이 죽어 **그 판은 영영 못 올리는** 거절(`no_token`·`token_expired`).
     * [submitFailedConnection] 과 **일부러 문장을 가른다**: "다시 해 주세요"는 복구된다는 뜻인데 토큰이 죽었으면 이번 판은 안 올라간다.
     */
    const val submitTokenDead: String = "이번 판은 순위에 못 올렸어요 — 다음 판부터 다시 올라가요"

    /**
     * 앱이 background 로 가서 판을 끝냈다(폰 전용). **게임마다 말이 다르다**: 기존 두 게임은 점수를 버리고, 테트리스는 여기까지의 점수를
     * **확정해 올린다**(`GamesPlayController.endRound()`). 테트리스에 "기록하지 않았어요"를 쓰면 그건 **거짓말**이다.
     */
    fun endedInBackground(kind: MiniGameKind): String = when (kind) {
        MiniGameKind.timingBar, MiniGameKind.flappy -> "앱을 나가서 이번 판은 기록하지 않았어요"
        MiniGameKind.tetris -> "앱을 나가서 이번 판을 여기까지 기록했어요"
        // 길건너 아잉이(v0.3.67): 데스크톱은 구동, 폰은 phoneCases·라우트가 거른다 — 폰 background 출구는 이 판에 오지 않는다.
        // 폰 판이 붙으면 그 판의 `endRound` 의미론(확정인가 버림인가)에 맞춰 다시 적는다.
        MiniGameKind.crossy -> "앱을 나가서 이번 판은 기록하지 않았어요"
    }

    /** 공개를 끈 사람(맥 설정 문구 "끄면 내 최고기록이 순위표에 안 보이고 올라가지도 않아요." 와 같은 뜻). */
    const val privateNotice: String = "미니게임 순위 공개가 꺼져 있어 점수가 올라가지 않아요"

    /** 폰 조작 안내(맥 `MiniGameKind.controlHint` "클릭 또는 스페이스" 의 폰판). */
    const val controlHint: String = "화면을 탭"
    val startAction: String get() = "${controlHint}해서 시작"
    val againAction: String get() = "${controlHint}해서 다시"

    /** 한 줄 규칙(맥 `MiniGameKind.howToPlay` 에서 조작 동사만 폰에 맞췄다). */
    fun howToPlay(kind: MiniGameKind): String = when (kind) {
        MiniGameKind.timingBar -> "마커가 밝은 구간에 오면 탭 · 10라운드"
        MiniGameKind.flappy -> "탭해서 점프 · 기둥 사이를 지나갈수록 +1"
        // 테트리스만 두 줄이다. 규칙 줄은 **코어 한 벌**(`kind.howToPlay`)을 그대로 쓰고, 조작 줄만 폰 것이다.
        // INV-GamesText-6e9a61c2 이식: 조작 줄에 **"탭해서 회전"이 반드시 들어가야 한다.** 폰에서 시계 회전은 캔버스 탭이고(버튼은
        // 반시계다) 그 사실을 말하는 자리가 시작 카드뿐이라, 빼면 아무도 시계 회전을 못 찾는다(시험이 글자로 잰다).
        MiniGameKind.tetris -> kind.howToPlay + "\n끌어서 이동 · 탭해서 회전 · 버튼으로 홀드·즉시 내리기"
        MiniGameKind.crossy -> kind.howToPlay   // 데스크톱은 구동, 폰은 phoneCases·라우트가 거른다(맥 MiniGameKind.howToPlay 그대로)
    }

    // MARK: 길건너 아잉이(데스크톱 — 맥 CrossyHUD, MiniGameCrossy.swift:131-195)

    /** 시작 카드 행동 문구. 클릭 · 스페이스 · 방향키가 다 시작이다(`CrossyGame.action` · `input`). */
    const val crossyStartAction: String = "클릭 · 스페이스 · 방향키로 시작"

    /** 결과 카드 행동 문구. 다시 하기는 클릭 · 스페이스뿐이다 — 방향키는 결과 화면에서 무시한다(엔진 `input` 주석). */
    const val crossyRetryAction: String = "클릭 · 스페이스로 다시"

    /** 결과 카드 가운데 줄 — 무엇에 끝났는가 + 최고(또는 신기록). 맥 `CrossyHUD.resultSubtitle` 그대로. */
    fun crossyResultSubtitle(score: Int, best: Long, cause: CrossyGame.DeathCause?): String {
        val reason = cause?.caption
        if (score.toLong() > best) return reason?.let { "신기록! · $it" } ?: "신기록!"
        return (reason?.let { "$it · " } ?: "") + "최고 " + best.toString()
    }

    /** 머리 줄 "최고 N점"(맥 하단 스트립과 같은 표기 — 자리수 구분 없음). */
    fun bestLine(best: Long): String = "최고 " + best.toString() + "점"

    /**
     * 머리 줄 "오늘 N위". 순위표 밖이면 "오늘 기록 없음" — **순위표를 알 때만**. 모르면(불러오는 중·실패) null 이고 머리 줄에서 뺀다.
     */
    fun rankLine(rank: Int?, knowsBoard: Boolean): String? {
        if (rank != null) return "오늘 ${rank}위"
        return if (knowsBoard) noRankToday else null
    }

    /** 정족수 안내(맥 `MiniGamePanel.quorumCaption` 과 같은 문장). */
    fun quorumCaption(players: Int): String = when {
        players >= prizeQuorum -> "오늘 ${players}명 참여 · 지급 조건 충족"
        players == 0 -> "오늘은 아직 아무도 안 했어요 · ${prizeQuorum}명부터 지급"
        else -> "오늘 ${players}명 참여 · ${prizeQuorum}명부터 지급"
    }

    /** 순위 행 점수(자리수 구분 없음). */
    fun score(value: Long): String = value.toString() + "점"

    /** 캔버스 보이스오버. 테트리스만 조작이 다르다(탭 = 시계 회전 · 이동은 액션 · 나머지는 진짜 버튼). */
    fun canvasAccessibility(kind: MiniGameKind): String = when (kind) {
        MiniGameKind.timingBar, MiniGameKind.flappy -> "${kind.title} 게임 화면 — 탭해서 조작"
        MiniGameKind.tetris -> "${kind.title} 게임 화면 — 탭해서 회전 · 이동은 액션으로"
        MiniGameKind.crossy -> "${kind.title} 게임 화면 — 방향키로 뛰기"   // 데스크톱은 구동, 폰은 phoneCases·라우트가 거른다
    }

    // MARK: 테트리스 조작(폰에서 처음 쓰는 줄)

    /** 버튼 줄 — 회전은 **방향을 나눈다**: 캔버스 탭이 시계, 버튼이 반시계다(설계 G). */
    const val tetrisHold: String = "홀드"

    /** 홀드 소진(조각당 1회) — 보이스오버 값. */
    const val tetrisHoldSpent: String = "이미 썼어요"
    const val tetrisRotateCounterClockwise: String = "반시계"
    const val tetrisHardDrop: String = "즉시 내리기"

    /** 보이스오버 이동 액션. **버튼이 없는 조작만** 여기 둔다. */
    const val tetrisMoveLeft: String = "왼쪽 한 칸"
    const val tetrisMoveRight: String = "오른쪽 한 칸"
    const val tetrisSoftDrop: String = "한 칸 내리기"

    /** 이동 액션 뒤 알림. 조각 자리는 **너무 빨리 바뀌어** 접근성 값에 둘 수 없다. */
    fun tetrisColumnAnnouncement(column: Int): String = "${column}열"
    fun tetrisDropAnnouncement(moved: Boolean): String = if (moved) "한 칸 내려갔어요" else "더 못 내려가요"

    /** 캔버스 접근성 값(테트리스) — **느린 값만**이다. */
    fun tetrisValue(score: Int, level: Int, lines: Int): String = "${score}점, 레벨 $level, ${lines}줄"
}

/**
 * 오목 화면 문구 — 맥 `GomokuText` 를 옮긴 것(같은 문장). 폰에서 새로 쓴 줄은 `// 폰` 으로 표시했다.
 *
 * ⚠️ **옮기지 않은 것**(W2-d 스토어 타입 — `GomokuUser`·`GomokuRecord`·`GomokuLiveMatch`·`GomokuMatchState`·`GomokuNoticeText` — 에
 * 기대는 함수): `record` · `status` · `endReason` · `aiEndReason` · `livePair` · `opponentStatus` · `autoPlacedCount` · `cellAccessibility` ·
 * `boardAccessibility`. 그 타입은 W2-d(오목 스토어)가 같은 웨이브에 만든다 — 병합 때 W2-d 타입 위에서 이 파일 끝에 더한다(보고 미해결 항목).
 */
object GomokuPhoneText {
    const val title: String = "1:1 오목"
    const val subtitle: String = "렌주룰 · 흑 선공 · 한 수 30초"
    const val rulesButton: String = "규칙"
    const val rulesTitle: String = "렌주 규칙"
    const val close: String = "닫기"

    /** 한 수 제한(초)의 설계값. 링이 몇 초에서 가득 차는지만 정한다 — 실제 값은 스토어 `turnSeconds`(서버 로비)를 먼저 쓴다. */
    const val turnSeconds: Double = 30.0

    const val lobbyTitle: String = "상대 고르기"
    const val lobbyCaption: String = "근무 중이 아니어도 신청하고 받을 수 있어요"
    const val emptyUsers: String = "지금 대결할 수 있는 사람이 없어요"
    const val loadingUsers: String = "상대 목록을 불러오고 있어요"

    /** 폰: 절마다 "무엇을 못 불러왔나" + 공용 [다시 시도]로 말한다(`MobileLoadText` 규칙). */
    const val usersLoadFailed: String = "상대 목록을 불러오지 못했어요"
    const val reloadUsers: String = MobileLoadText.retry
    const val challenge: String = "도전"
    const val stakeTitle: String = "판돈"

    /**
     * v0.3.64(2026-10-22 사용자 결정 "멀티 미니게임 수수료 다시 제거해줘"): 판돈 수수료가 없어졌다 — 이긴 사람은 2×판돈을 받는다.
     * 맥 `GomokuText.stakeCaption` 과 같은 문장이다. 화면 어디에도 "수수료" 글자를 남기지 않는다(`GamesDuelFeeCopyTests`).
     */
    const val stakeCaption: String = "수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요"
    fun stakePromptTitle(name: String): String = "${name}님에게 신청"
    const val stakePromptCaption: String = "판돈을 고르세요"
    fun stakePromptChosen(stake: Int): String = "판돈 ${stakeLine(stake)}"
    fun challengeWithStake(stake: Int): String = "$stake 걸고 도전하기"
    const val stakeShortfall: String = "루비가 모자라요"
    const val incomingTitle: String = "받은 신청"
    const val outgoingTitle: String = "보낸 신청"
    const val noIncoming: String = "받은 신청이 없어요"

    /** 폰: 받은함을 불러오지 못했다(빈 목록을 "없어요"로 말하지 않는다). */
    const val incomingLoadFailed: String = GamesText.inboxLoadFailed
    const val loadingIncoming: String = "받은 신청을 불러오고 있어요"
    const val accept: String = "수락"
    const val decline: String = "거절"
    const val cancel: String = "취소"

    const val myTurn: String = "내 차례예요"
    const val opponentTurn: String = "상대 차례예요"
    const val blackPassed: String = "흑이 둘 곳이 없어 차례가 백으로 넘어갔어요"
    const val resign: String = "기권"
    const val resignConfirm: String = "기권하면 건 루비를 잃어요"

    /** 확인 시트 본문 — 되돌릴 수 없다는 것만 한 줄로. */
    const val resignConfirmMessage: String = "지금 기권하면 이 판은 상대가 이겨요."
    const val resignNow: String = "기권하기"
    const val keepPlaying: String = "계속 두기"

    const val backToLobby: String = "로비로"
    const val rematch: String = "같은 판돈으로 다시 신청"

    /** 폰: 호버가 없어 **첫 탭은 미리보기, 같은 칸을 한 번 더 누르면 둔다**(SPEC-ios §3.5). */
    const val placeHint: String = "같은 칸을 한 번 더 누르면 둬요"

    /** 폰: 서버 시계 규칙 안내 한 줄 — 앱을 나가도 차례 시간은 서버에서 흐른다. */
    const val clockRunsInBackground: String = "앱을 나가도 차례 시간은 흘러요"

    /** 폰: 나 카드의 이름(스토어는 상대만 들고 있다 — 맥 `GomokuPlayerFace.fallback` 과 같은 "나"). */
    const val me: String = "나"

    /** 별명을 모르는 상대(탈퇴·익명화·옛 응답). 신고·차단 시트가 이름을 부를 때 쓰며, 차단 목록의 폴백("사용자")과 뜻이 같다. */
    const val opponentFallbackName: String = "상대"

    fun reasonLabel(reason: GomokuForbiddenReason): String = when (reason) {
        GomokuForbiddenReason.doubleThree -> "3-3 금수"
        GomokuForbiddenReason.doubleFour -> "4-4 금수"
        GomokuForbiddenReason.overline -> "장목 금수"
        GomokuForbiddenReason.budget -> "판정할 수 없는 자리"
    }

    /** 상태줄(금수 자리를 눌렀을 때). */
    fun forbiddenStatus(reason: GomokuForbiddenReason): String =
        if (reason == GomokuForbiddenReason.budget) "판정할 수 없는 자리예요" else "${reasonLabel(reason)}라 둘 수 없어요"

    /** "5 · 이기면 +5" — 꼬리 숫자는 **순이익**(`DuelFee.winnerNet` — v0.3.64 부터 수수료 0 이라 +판돈)이다. 결과 카드의 +N 과 같은 눈금. */
    fun stakeLine(stake: Int): String = "$stake · 이기면 +${DuelFee.winnerNet(stake)}"

    fun stoneName(color: GomokuColor): String = if (color == GomokuColor.black) "흑 · 먼저 둬요" else "백"

    fun remaining(seconds: Double): String = "${ceil(maxOf(0.0, seconds)).toInt()}초"

    fun clockAccessibility(seconds: Double): String = "남은 시간 ${remaining(seconds)}"

    fun outcomeTitle(outcome: GomokuOutcome?): String = when (outcome) {
        GomokuOutcome.won -> "이겼어요!"
        GomokuOutcome.lost -> "졌어요"
        GomokuOutcome.draw -> "무승부"
        null -> "대국이 끝났어요"
    }

    /** 루비 변화(+10 / −10 / ±0). */
    fun rubyDelta(delta: Int): String = when {
        delta > 0 -> "+$delta"
        delta < 0 -> "−${-delta}"
        else -> "±0"
    }

    fun incomingTitle(name: String): String = "${name}님의 신청"
    fun outgoingTitle(name: String): String = "${name}님에게 신청했어요"

    const val chatTitle: String = "대화"
    const val chatMute: String = "끄기"
    const val chatUnmute: String = "켜기"
    const val chatEmpty: String = "아직 나눈 말이 없어요"

    /** 폰: ↩ 로 보내는 안내는 키보드의 보내기 키가 말한다. */
    const val chatPlaceholder: String = "메시지 입력"
    const val chatSend: String = "보내기"

    /** 글자 수는 상한 근처에서만(맥 `GomokuChatComposer.counterFromRatio` 0.8 — 100자 중 80자부터). */
    const val chatCounterFromRatio: Double = 0.8

    // MARK: w15 재디자인(시안 B 08·09) — 폰에서 새로 쓴 줄

    const val recordTitle: String = "전적"
    const val myRubyTitle: String = "내 루비"
    fun peopleCount(count: Int): String = "${count}명"
    fun liveCount(count: Int): String = "${count}판"
    const val inMatchButton: String = "대국 중"
    const val needsUpdate: String = "앱 업데이트가 필요해요"

    /** " · 이기면 +5"(판돈 5 의 줄 꼬리 — 순이익, `DuelFee.winnerNet`). */
    fun stakeGainSuffix(stake: Int): String = " · 이기면 +${DuelFee.winnerNet(stake)}"

    /** "이기면 +5" — 판돈 시트의 칸 아래 줄(앞 가운뎃점 없음 · 순이익). 체스 `ChessPhoneText.stakeGain` 과 같은 말. */
    fun stakeGain(stake: Int): String = "이기면 +${DuelFee.winnerNet(stake)}"

    /** "42초 남음"(받은 신청 머리 · 보낸 신청 부제). */
    fun remainingPhrase(seconds: Double): String = "${remaining(seconds)} 남음"

    /** 대결이 시작된 뒤 흐른 시간을 말로("35초째" · "1분 35초째" · "1시간 2분째"). */
    fun elapsedPhrase(seconds: Double): String {
        val total = maxOf(0.0, seconds).toInt()
        if (total < 60) return "${total}초째"
        if (total < 3600) return "${total / 60}분 ${total % 60}초째"
        return "${total / 3600}시간 ${(total % 3600) / 60}분째"
    }

    /** 받침이 있으면 "과", 없으면(한글이 아니어도) "와" — "달토끼와" · "민트별과". */
    fun withParticle(name: String): String {
        // 마지막 스칼라가 보조 평면이면 마지막 UTF-16 단위가 하위 대리(0xDC00…)라 한글 범위 밖 — Swift 와 같은 "와".
        if (name.isEmpty()) return "와"
        val scalar = name.last().code
        if (scalar !in 0xAC00..0xD7A3) return "와"
        return if ((scalar - 0xAC00) % 28 == 0) "와" else "과"
    }

    fun stoneShort(color: GomokuColor): String = if (color == GomokuColor.black) "흑" else "백"

    /** 상대 카드 부제 "백 · 근무 중". */
    fun playerSubtitle(color: GomokuColor, isWorking: Boolean): String = stoneShort(color) + " · " + (if (isWorking) "근무 중" else "근무 안 함")

    /** 내 차례 부제 꼬리 — 미리보기 돌이 섰으면 그 칸("I8 한 번 더 누르면 둬요"), 아니면 규칙 한 줄. */
    fun myTurnHint(preview: GomokuPoint?): String = if (preview == null) placeHint else "${preview.notation} 한 번 더 누르면 둬요"

    /** 내 카드 부제(상대 차례) "흑 · 상대 차례예요". */
    fun myWaitingLine(color: GomokuColor): String = stoneShort(color) + " · " + opponentTurn

    /** 대화 음소거 — 무엇을 끄는지 말한다(비평: '끄기'만으로는 소리인지 알림인지 모른다). */
    const val chatMuteAction: String = "대화 끄기"
    const val chatUnmuteAction: String = "대화 켜기"
    const val chatOpen: String = "대화 펼치기"
    const val chatClose: String = "대화 접기"
    const val chatWrite: String = "메시지 쓰기"
    const val moreMenu: String = "더보기"
    fun resultOpponent(name: String): String = "상대 · $name"

    const val liveTitle: String = "지금 대결 중"
    const val noLiveMatches: String = "지금 대결 중인 사람이 없어요"

    /** 폰: 로비를 불러오지 못했다(대결 중 목록은 로비 응답에 실린다). */
    const val liveLoadFailed: String = "대결 중인 판을 불러오지 못했어요"

    /** 대결이 시작된 뒤 흐른 시간(m:ss). */
    fun elapsed(seconds: Double): String {
        val total = maxOf(0.0, seconds).toInt()
        return "${total / 60}:${(total % 60).toString().padStart(2, '0')}"
    }

    fun more(count: Int): String = "외 ${count}건"

    // MARK: AI 대국(1.0.1) — 맥 `GomokuText` 의 AI 절을 그대로 옮겼다. 폰에서 새로 쓴 줄은 `// 폰`.

    const val aiButton: String = "AI와 두기"
    const val aiButtonHelp: String = "루비·전적 없이 AI와 연습해요"
    const val aiPromptTitle: String = "AI와 두기"
    const val aiPromptCaption: String = "돌 색을 고르면 바로 시작해요"

    /** 사용자 결정 둘(루비 안 걸기 · 기록 안 남기기)을 시작 전에 한 번, 대국 중에 한 번 더 말한다(맥과 같은 두 자리). */
    const val aiNoRecord: String = "루비·전적·순위에 남지 않아요"
    const val aiPlayBlack: String = "흑 · 먼저 둬요"
    const val aiPlayWhite: String = "백 · 나중에 둬요"
    const val aiThinking: String = "AI가 생각 중이에요"
    const val aiThinkingShort: String = "생각 중"
    const val aiStakeChip: String = "AI 대국 · 기록 없음"
    const val aiResignConfirm: String = "기권하면 이 판은 AI가 이겨요"
    const val aiRematch: String = "같은 색으로 다시 두기"
    const val aiRematchHelp: String = "같은 돌 색으로 AI와 새 판을 시작해요"
    const val aiOpponentLine: String = "상대 · AI"

    /** 폰: 사람 시계가 멈추는 계기는 **화면을 떠남 · 앱을 나감**이다. 1:1 의 [clockRunsInBackground] 와 정반대 사실이다. */
    const val aiClockPauses: String = "화면을 떠나거나 앱을 나가면 내 시계가 멈춰요 · 한 수 30초가 지나면 자동으로 놓여요"
}
