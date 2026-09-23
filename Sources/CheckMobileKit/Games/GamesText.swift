import CheckCore
import Foundation

// 게임 탭 문구(SPEC-ios §3.5). **맥과 같은 뜻이면 같은 문장이다** — 출처를 줄마다 적는다.
//  · 오목 문구는 맥 `GomokuText`(Sources/check/GomokuPanel.swift)를 그대로 옮겼다. 그 표는 맥 앱 타깃 안에 있어
//    폰 모듈이 부를 수 없다(코어로 옮기면 맥 파일을 고쳐야 한다 — 탭 작업 범위 밖). 안내 한 줄(거절·실패)은 코어
//    `GomokuNoticeText` 를 그대로 부른다.
//  · 미니게임 허브 문구는 맥 `MiniGamePanel`(오늘 순위·상품·정지) · `WorkTimerStoreMiniGame`(제출 실패)에서 옮겼다.
//  · 폰에서 새로 생긴 문장(탭 조작·앱을 나감·같은 칸 두 번)만 여기서 처음 쓴다.

/// 게임 탭 첫 화면·미니게임 화면 문구.
package enum GamesText {
    package static let tabTitle = "게임"

    // MARK: 첫 화면 카드

    /// 카드의 오늘 한 줄(최고·순위). 순위 밖이면 최고만.
    ///
    /// 내 줄이 없을 때 "오늘 기록 없음"은 **순위표를 알 때만**이다(`board.knowsPlayerCount` — 공용 `MobileLoadKnowledge`).
    /// 불러오지 못했으면 실패 문구, 아직 모르면 불러오는 중 — 오프라인에서 "오늘 기록 없음"이라 말하던 결함(통합 검증 E-games).
    package static func todayLine(best: Int?, rank: Int?, board: GamesMiniGameBoard) -> String {
        guard let best else {
            switch board.placeholder {
            case .rows, .empty: return GamesMiniGameText.noRankToday
            case .failed: return recordLoadFailed
            case .loading: return GamesMiniGameText.loadingCaption
            }
        }
        // String(...) — 로캘 자리수 구분("1,000")을 붙이지 않는다(맥 게임 표기와 같다).
        if let rank { return "오늘 최고 " + String(best) + "점 · " + String(rank) + "위" }
        return "오늘 최고 " + String(best) + "점"
    }

    /// 허브 카드: 오늘 순위표를 불러오지 못했다(폰).
    package static let recordLoadFailed = "기록을 불러오지 못했어요"
    /// 허브 오목 카드: 받은함을 불러오지 못했다(폰).
    package static let inboxLoadFailed = "받은 신청을 불러오지 못했어요"

    package static let gomokuCardSubtitle = GomokuPhoneText.subtitle

    /// 허브 오목 카드가 '대국 중'을 앞세울 것인가. **AI 판은 사람의 신청을 가리지 않는다**(2026-09-20 검증 low).
    /// AI 판은 기록도 판돈도 없고 화면을 떠나면 시계가 멈춰 두던 채로 며칠이고 남을 수 있다 — 그 판이 '진행 중인 대국'으로
    /// 카드를 차지하면 사람이 보낸 1:1 신청(루비가 걸린 진짜 대결)이 카드에서 안 보인다. AI 판 중에도 받은함은 계속 받고
    /// 수락도 되므로(코어 `syncOnce`·`respond`), 받은 신청이 있으면 그쪽을 먼저 말한다. 사람 대국은 예전처럼 늘 먼저다.
    package static func hubShowsActiveMatch(active: Bool, isAIMatch: Bool, incoming: Int) -> Bool {
        active && !(isAIMatch && incoming > 0)
    }

    /// 오목 카드의 한 줄. 진행 중인 대국이 먼저다(차례 시간이 흐르고 있다).
    /// 받은 신청이 0건인데 받은함을 **못 불러왔으면** "상대를 골라…"(= 받은 게 없다는 뜻)로 접지 않고 실패를 말한다.
    package static func gomokuLine(incoming: Int, hasActiveMatch: Bool, hasOutgoing: Bool, inboxFailed: Bool = false) -> String {
        if hasActiveMatch { return "진행 중인 대국이 있어요" }
        if incoming > 0 { return "받은 신청 \(incoming)건" }
        if inboxFailed { return inboxLoadFailed }
        if hasOutgoing { return "보낸 신청을 기다리고 있어요" }
        return "상대를 골라 대결을 신청해요"
    }

    package static let openGame = "하기"

    // MARK: w15 재디자인(시안 B 07) — 폰에서 새로 쓴 줄

    /// 오른쪽 위 루비 알약을 누르면(보이스오버 힌트).
    package static let rubyPillHint = "상점을 열어요"
    package static let todayRankTitle = "오늘 내 순위"
    package static let seeAllRankings = "순위 탭에서 전체 보기"
    /// 허브 오목 칩: 진행 중인 판.
    package static let activeMatchChip = "대국 중"
    package static func incomingChip(_ count: Int) -> String { "받은 신청 \(count)건" }

    /// "오늘 내 순위" 행 부제 — 1등 한 줄과 참여 수("1위 민트별 962점 · 8명 참여"). 순위표를 모르면 불러오는 중·실패를 말한다.
    package static func hubRankSubtitle(board: GamesMiniGameBoard) -> String {
        switch board.placeholder {
        case .rows:
            guard let leader = board.entries.first else { return GamesMiniGameText.noRankToday }
            return "1위 " + leader.name + " " + GamesMiniGameText.score(leader.bestScore) + " · \(board.entries.count)명 참여"
        case .empty: return "오늘은 아직 아무도 안 했어요"
        case .failed: return GamesMiniGameText.failedCaption
        case .loading: return GamesMiniGameText.loadingCaption
        }
    }
}

/// 미니게임 허브 문구(맥 `MiniGamePanel` · `WorkTimerStoreMiniGame` 과 같은 말).
package enum GamesMiniGameText {
    package static let rankTitle = "오늘 순위"
    /// 자정 상품(루비). 서버 `ruby_prize_amounts()` 와 짝인 상수(맥 `MiniGamePanel.rubyPrizes`).
    package static let rubyPrizes = [20, 10, 5]
    /// 상품 정족수. 서버 `minigame_prize_quorum()` 과 짝인 상수(맥 `MiniGamePanel.prizeQuorum`).
    package static let prizeQuorum = 5
    package static let prizeCaption = "자정에 1·2·3등에게 루비 \(rubyPrizes[0])·\(rubyPrizes[1])·\(rubyPrizes[2])"
    package static let emptyBoard = "아직 기록이 없어요 — 첫 기록의 주인공이 되세요"
    package static let loadingCaption = "불러오는 중…"
    package static let failedCaption = "순위를 불러오지 못했어요"
    package static let retry = MobileLoadText.retry
    package static let awardedChip = "루비 +\(rubyPrizes[0]) 받음"
    package static let yesterdayChampion = "어제 1등"
    package static let noRankToday = "오늘 기록 없음"

    /// 제출 실패(토큰 없음·네트워크) — 맥 `recordMiniGameScore` 와 같은 문장.
    package static let submitFailedConnection = "점수를 못 올렸어요 — 연결을 확인하고 다시 해 주세요"
    /// 서버 거절 — 맥 `performSubmitMiniGameScore` 와 같은 문장. status 이름·need_seconds 는 화면에 싣지 않는다.
    package static let submitRefused = "점수를 못 올렸어요"
    /// 토큰이 죽어 **그 판은 영영 못 올리는** 거절(`no_token`·`token_expired`).
    ///
    /// `submitFailedConnection` 과 **일부러 문장을 가른다**: "다시 해 주세요"는 복구된다는 뜻인데 토큰이 죽었으면
    /// 이번 판은 어떤 재시도로도 안 올라간다. 그걸 "다시 해 주세요"로 그리면 사용자는 없는 복구를 기다린다.
    package static let submitTokenDead = "이번 판은 순위에 못 올렸어요 — 다음 판부터 다시 올라가요"

    /// 앱이 background 로 가서 판을 끝냈다(폰 전용 — SPEC-ios §3.5). **게임마다 말이 다르다**:
    /// 기존 두 게임은 점수를 버리고, 테트리스는 여기까지의 점수를 **확정해 올린다**(`GamesPlayController.endRound()`).
    /// 테트리스에 "기록하지 않았어요"를 쓰면 그건 **거짓말**이다 — 점수는 이미 나갔다.
    package static func endedInBackground(_ kind: MiniGameKind) -> String {
        switch kind {
        case .timingBar, .flappy: return "앱을 나가서 이번 판은 기록하지 않았어요"
        case .tetris: return "앱을 나가서 이번 판을 여기까지 기록했어요"
        }
    }
    /// 공개를 끈 사람(맥 설정 문구 "끄면 내 최고기록이 순위표에 안 보이고 올라가지도 않아요." 와 같은 뜻).
    package static let privateNotice = "미니게임 순위 공개가 꺼져 있어 점수가 올라가지 않아요"

    /// 폰 조작 안내(맥 `MiniGameKind.controlHint` "클릭 또는 스페이스" 의 폰판).
    package static let controlHint = "화면을 탭"
    package static var startAction: String { "\(controlHint)해서 시작" }
    package static var againAction: String { "\(controlHint)해서 다시" }

    /// 한 줄 규칙(맥 `MiniGameKind.howToPlay` 에서 조작 동사만 폰에 맞췄다).
    package static func howToPlay(_ kind: MiniGameKind) -> String {
        switch kind {
        case .timingBar: return "마커가 밝은 구간에 오면 탭 · 10라운드"
        case .flappy: return "탭해서 점프 · 기둥 사이를 지나갈수록 +1"
        // 테트리스만 두 줄이다. 규칙 줄은 **코어 한 벌**(`kind.howToPlay`)을 그대로 쓰고, 조작 줄만 폰 것이다.
        //
        // ⚠️ 조작 줄에 **"탭해서 회전"이 반드시 들어가야 한다.** 폰에서 시계 회전은 캔버스 탭이고(버튼은
        // 반시계다) 그 사실을 말하는 자리가 시작 카드뿐이라, 빼면 아무도 시계 회전을 못 찾는다.
        // 홀드·즉시 내리기는 글자가 붙은 진짜 버튼이라 여기서는 어디에 있는지만 가리킨다.
        case .tetris: return kind.howToPlay + "\n끌어서 이동 · 탭해서 회전 · 버튼으로 홀드·즉시 내리기"
        }
    }

    /// 머리 줄 "최고 N점"(맥 하단 스트립과 같은 표기 — 자리수 구분 없음).
    package static func bestLine(_ best: Int) -> String { "최고 " + String(best) + "점" }

    /// 머리 줄 "오늘 N위". 순위표 밖이면 "오늘 기록 없음" — **순위표를 알 때만**. 모르면(불러오는 중·실패) nil 이고 머리 줄에서 뺀다
    /// (실패는 아래 순위 카드가 말한다 — 머리에 "오늘 기록 없음", 아래에 "순위를 불러오지 못했어요"가 함께 뜨던 결함).
    package static func rankLine(_ rank: Int?, knowsBoard: Bool) -> String? {
        if let rank { return "오늘 \(rank)위" }
        return knowsBoard ? noRankToday : nil
    }

    /// 정족수 안내(맥 `MiniGamePanel.quorumCaption` 과 같은 문장).
    package static func quorumCaption(players: Int) -> String {
        if players >= prizeQuorum { return "오늘 \(players)명 참여 · 지급 조건 충족" }
        if players == 0 { return "오늘은 아직 아무도 안 했어요 · \(prizeQuorum)명부터 지급" }
        return "오늘 \(players)명 참여 · \(prizeQuorum)명부터 지급"
    }

    /// 순위 행 점수(자리수 구분 없음).
    package static func score(_ value: Int) -> String { String(value) + "점" }

    /// 캔버스 보이스오버. 테트리스만 조작이 다르다(탭 = 시계 회전 · 이동은 액션 · 나머지는 진짜 버튼).
    package static func canvasAccessibility(_ kind: MiniGameKind) -> String {
        switch kind {
        case .timingBar, .flappy: return "\(kind.title) 게임 화면 — 탭해서 조작"
        case .tetris: return "\(kind.title) 게임 화면 — 탭해서 회전 · 이동은 액션으로"
        }
    }

    // MARK: 테트리스 조작(폰에서 처음 쓰는 줄)

    /// 버튼 줄 — 아이콘 아래 한 줄. 회전은 **방향을 나눈다**: 캔버스 탭이 시계, 버튼이 반시계다.
    /// 버튼까지 시계면 캔버스 탭과 완전히 겹쳐 자리 하나를 버리고 반시계가 폰에서 사라진다(설계 G).
    package static let tetrisHold = "홀드"
    /// 홀드 소진(조각당 1회) — 보이스오버 값. 버튼을 비활성으로 만들지 않으므로 목록에서 사라지지 않고 이 값만 붙는다.
    package static let tetrisHoldSpent = "이미 썼어요"
    package static let tetrisRotateCounterClockwise = "반시계"
    package static let tetrisHardDrop = "즉시 내리기"

    /// 보이스오버 이동 액션. **버튼이 없는 조작만** 여기 둔다 — 홀드·반시계·즉시 내리기는 이미 진짜 버튼이라
    /// 액션으로 또 내면 같은 동작이 목록에 두 번 선다.
    package static let tetrisMoveLeft = "왼쪽 한 칸"
    package static let tetrisMoveRight = "오른쪽 한 칸"
    package static let tetrisSoftDrop = "한 칸 내리기"

    /// 이동 액션 뒤 알림. 조각 자리는 **너무 빨리 바뀌어** `accessibilityValue` 에 둘 수 없다
    /// (L1 0.355초/칸 · L15 0.00082초/칸 — 값에 넣으면 보이스오버가 자기 말을 끝없이 끊는다).
    package static func tetrisColumnAnnouncement(_ column: Int) -> String { "\(column)열" }
    package static func tetrisDropAnnouncement(moved: Bool) -> String {
        moved ? "한 칸 내려갔어요" : "더 못 내려가요"
    }

    /// 캔버스 `accessibilityValue`(테트리스) — **느린 값만**이다. 조각·열·행을 넣으면 위 알림과 같은 이유로 무너진다.
    package static func tetrisValue(score: Int, level: Int, lines: Int) -> String {
        "\(score)점, 레벨 \(level), \(lines)줄"
    }
}

/// 오목 화면 문구 — 맥 `GomokuText` 를 옮긴 것(같은 문장). 폰에서 새로 쓴 줄은 `// 폰` 으로 표시했다.
package enum GomokuPhoneText {
    package static let title = "1:1 오목"
    package static let subtitle = "렌주룰 · 흑 선공 · 한 수 30초"
    package static let rulesButton = "규칙"
    package static let rulesTitle = "렌주 규칙"
    package static let close = "닫기"

    /// 한 수 제한(초)의 설계값. 링이 몇 초에서 가득 차는지만 정한다 — 실제 값은 스토어 `turnSeconds`(서버 로비)를 먼저 쓴다.
    package static let turnSeconds: Double = 30

    package static let lobbyTitle = "상대 고르기"
    package static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    package static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    package static let loadingUsers = "상대 목록을 불러오고 있어요"
    /// 폰: 맥은 연결 안내 한 문장(`GomokuNoticeText.checkConnection`)이지만, 폰은 절마다 "무엇을 못 불러왔나" + 공용 [다시 시도]로 말한다
    /// (`MobileLoadText` 규칙 — 탭마다 갈리던 실패 모양을 맞췄다).
    package static let usersLoadFailed = "상대 목록을 불러오지 못했어요"
    package static let reloadUsers = MobileLoadText.retry
    package static let challenge = "도전"
    package static let stakeTitle = "판돈"
    package static let stakeCaption = "수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요"
    package static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    package static let stakePromptCaption = "판돈을 고르세요"
    package static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stakeLine(stake))" }
    package static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    package static let stakeShortfall = "루비가 모자라요"
    package static let incomingTitle = "받은 신청"
    package static let outgoingTitle = "보낸 신청"
    package static let noIncoming = "받은 신청이 없어요"
    /// 폰: 받은함을 불러오지 못했다(빈 목록을 "없어요"로 말하지 않는다).
    package static let incomingLoadFailed = GamesText.inboxLoadFailed
    package static let loadingIncoming = "받은 신청을 불러오고 있어요"
    package static let accept = "수락"
    package static let decline = "거절"
    package static let cancel = "취소"

    package static let myTurn = "내 차례예요"
    package static let opponentTurn = "상대 차례예요"
    package static let blackPassed = "흑이 둘 곳이 없어 차례가 백으로 넘어갔어요"
    package static let resign = "기권"
    package static let resignConfirm = "기권하면 건 루비를 잃어요"
    /// 확인 시트 본문 — 되돌릴 수 없다는 것만 한 줄로.
    package static let resignConfirmMessage = "지금 기권하면 이 판은 상대가 이겨요."
    package static let resignNow = "기권하기"
    package static let keepPlaying = "계속 두기"

    package static let backToLobby = "로비로"
    package static let rematch = "같은 판돈으로 다시 신청"

    /// 폰: 호버가 없어 **첫 탭은 미리보기, 같은 칸을 한 번 더 누르면 둔다**(SPEC-ios §3.5).
    package static let placeHint = "같은 칸을 한 번 더 누르면 둬요"
    /// 폰: 서버 시계 규칙 안내 한 줄 — 앱을 나가도 차례 시간은 서버에서 흐른다.
    package static let clockRunsInBackground = "앱을 나가도 차례 시간은 흘러요"
    /// 폰: 나 카드의 이름(스토어는 상대만 들고 있다 — 맥 `GomokuPlayerFace.fallback` 과 같은 "나").
    package static let me = "나"
    /// 별명을 모르는 상대(탈퇴·익명화·옛 응답). 신고·차단 시트가 이름을 부를 때 쓰며, 차단 목록의 폴백("사용자")과 뜻이 같다.
    package static let opponentFallbackName = "상대"

    package static func record(_ record: GomokuRecord?) -> String {
        guard let record else { return "전적 —" }
        return "\(record.wins)승 \(record.losses)패 \(record.draws)무"
    }

    /// 상대 행 상태 칩. 우선순위: 대국 중 > 업데이트 필요 > 근무 중/근무 안 함.
    package static func status(for user: GomokuUser) -> String {
        if user.inMatch { return "대국 중" }
        if !user.isCapable { return "업데이트 필요" }
        return user.isWorking ? "근무 중" : "근무 안 함"
    }

    package static func reasonLabel(_ reason: GomokuForbiddenReason) -> String {
        switch reason {
        case .doubleThree: return "3-3 금수"
        case .doubleFour: return "4-4 금수"
        case .overline: return "장목 금수"
        case .budget: return "판정할 수 없는 자리"
        }
    }

    /// 상태줄(금수 자리를 눌렀을 때).
    package static func forbiddenStatus(_ reason: GomokuForbiddenReason) -> String {
        reason == .budget ? "판정할 수 없는 자리예요" : "\(reasonLabel(reason))라 둘 수 없어요"
    }

    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(stake)" }

    package static func stoneName(_ color: GomokuColor) -> String { color == .black ? "흑 · 먼저 둬요" : "백" }

    package static func remaining(_ seconds: Double) -> String { "\(Int(max(0, seconds).rounded(.up)))초" }

    package static func clockAccessibility(_ seconds: Double) -> String { "남은 시간 \(remaining(seconds))" }

    package static func outcomeTitle(_ outcome: GomokuOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요!"
        case .lost?: return "졌어요"
        case .draw?: return "무승부"
        case nil: return "대국이 끝났어요"
        }
    }

    package static func endReason(_ reason: GomokuEndReason?, outcome: GomokuOutcome?) -> String {
        switch (reason, outcome) {
        case (.five?, .won?): return "5목을 완성했어요"
        case (.five?, _): return "상대가 5목을 완성했어요"
        case (.timeout?, .won?): return "상대의 시간이 다 됐어요"
        case (.timeout?, _): return "시간이 다 됐어요"
        case (.resign?, .won?): return "상대가 기권했어요"
        case (.resign?, _): return "기권했어요"
        case (.boardFull?, _): return "판이 가득 찼어요 · 건 루비는 돌려받아요"
        case (.abandoned?, _): return GomokuNoticeText.abandoned(outcome: outcome)
        case (nil, _): return ""
        }
    }

    /// 루비 변화(+10 / −10 / ±0).
    package static func rubyDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "±0"
    }

    package static func incomingTitle(name: String) -> String { "\(name)님의 신청" }
    package static func outgoingTitle(name: String) -> String { "\(name)님에게 신청했어요" }

    package static let chatTitle = "대화"
    package static let chatMute = "끄기"
    package static let chatUnmute = "켜기"
    package static let chatEmpty = "아직 나눈 말이 없어요"
    /// 폰: ↩ 로 보내는 안내는 키보드의 보내기 키가 말한다.
    package static let chatPlaceholder = "메시지 입력"
    package static let chatSend = "보내기"
    /// 글자 수는 상한 근처에서만(맥 `GomokuChatComposer.counterFromRatio` 0.8 — 100자 중 80자부터).
    package static let chatCounterFromRatio = 0.8

    // MARK: w15 재디자인(시안 B 08·09) — 폰에서 새로 쓴 줄

    package static let recordTitle = "전적"
    package static let myRubyTitle = "내 루비"
    package static func peopleCount(_ count: Int) -> String { "\(count)명" }
    package static func liveCount(_ count: Int) -> String { "\(count)판" }
    package static let inMatchButton = "대국 중"
    package static let needsUpdate = "앱 업데이트가 필요해요"
    /// " · 이기면 +5"(판돈 줄 꼬리).
    package static func stakeGainSuffix(_ stake: Int) -> String { " · 이기면 +\(stake)" }
    /// "42초 남음"(받은 신청 머리 · 보낸 신청 부제).
    package static func remainingPhrase(_ seconds: Double) -> String { "\(remaining(seconds)) 남음" }
    /// "민트별 · 달토끼".
    package static func livePair(_ live: GomokuLiveMatch) -> String { live.a.displayName + " · " + live.b.displayName }

    /// 대결이 시작된 뒤 흐른 시간을 말로("35초째" · "1분 35초째" · "1시간 2분째").
    package static func elapsedPhrase(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        if total < 60 { return "\(total)초째" }
        if total < 3600 { return "\(total / 60)분 \(total % 60)초째" }
        return "\(total / 3600)시간 \((total % 3600) / 60)분째"
    }

    /// 상대 행 부제(칩 대신 회색 글 — 시안 B 08). 대국 중이면 누구와 두는지(로비의 대결 중 목록에서 찾는다).
    package static func opponentStatus(for user: GomokuUser, liveMatches: [GomokuLiveMatch]) -> String {
        if user.inMatch {
            let partner = liveMatches.first { $0.a.id == user.id || $0.b.id == user.id }
                .map { $0.a.id == user.id ? $0.b.displayName : $0.a.displayName }
            return partner.map { "대국 중 · \($0)\(withParticle($0))" } ?? "대국 중"
        }
        if !user.isCapable { return needsUpdate }
        return user.isWorking ? "근무 중" : "근무 안 함"
    }

    /// 받침이 있으면 "과", 없으면(한글이 아니어도) "와" — "달토끼와" · "민트별과".
    package static func withParticle(_ name: String) -> String {
        guard let scalar = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return "와" }
        return (scalar.value - 0xAC00) % 28 == 0 ? "와" : "과"
    }

    package static func stoneShort(_ color: GomokuColor) -> String { color == .black ? "흑" : "백" }
    /// 상대 카드 부제 "백 · 근무 중".
    package static func playerSubtitle(color: GomokuColor, isWorking: Bool) -> String {
        stoneShort(color) + " · " + (isWorking ? "근무 중" : "근무 안 함")
    }
    /// 내 차례 부제 꼬리 — 미리보기 돌이 섰으면 그 칸("I8 한 번 더 누르면 둬요"), 아니면 규칙 한 줄.
    package static func myTurnHint(preview: GomokuPoint?) -> String {
        guard let preview else { return placeHint }
        return "\(preview.notation) 한 번 더 누르면 둬요"
    }
    /// 내 카드 부제(상대 차례) "흑 · 상대 차례예요".
    package static func myWaitingLine(color: GomokuColor) -> String { stoneShort(color) + " · " + opponentTurn }

    /// 대화 음소거 — 무엇을 끄는지 말한다(비평: '끄기'만으로는 소리인지 알림인지 모른다).
    package static let chatMuteAction = "대화 끄기"
    package static let chatUnmuteAction = "대화 켜기"
    package static let chatOpen = "대화 펼치기"
    package static let chatClose = "대화 접기"
    package static let chatWrite = "메시지 쓰기"
    package static let moreMenu = "더보기"
    package static func resultOpponent(_ name: String) -> String { "상대 · \(name)" }

    package static let liveTitle = "지금 대결 중"
    package static let noLiveMatches = "지금 대결 중인 사람이 없어요"
    /// 폰: 로비를 불러오지 못했다(대결 중 목록은 로비 응답에 실린다 — [다시 시도]는 바로 위 상대 고르기 절에 있다).
    package static let liveLoadFailed = "대결 중인 판을 불러오지 못했어요"

    /// 대결이 시작된 뒤 흐른 시간(m:ss).
    package static func elapsed(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    package static func autoPlacedCount(_ count: Int) -> String { "\(GomokuNoticeText.autoPlacedStone) \(count)개" }

    package static func more(_ count: Int) -> String { "외 \(count)건" }

    /// 칸 보이스오버(SPEC-ios §3.5 "H8, 비어 있음"). 사실만 말한다 — 둘 수 있는지는 금수·차례 줄이 말한다.
    package static func cellAccessibility(
        _ point: GomokuPoint, stone: GomokuColor?, isLastMove: Bool, isAuto: Bool,
        forbidden: GomokuForbiddenReason?, isPreview: Bool
    ) -> String {
        var parts = [point.notation]
        switch stone {
        case .black?: parts.append("흑돌")
        case .white?: parts.append("백돌")
        case nil:
            if isPreview {
                parts.append("미리보기 돌 · 한 번 더 누르면 둬요")
            } else if let forbidden {
                parts.append(reasonLabel(forbidden))
            } else {
                parts.append("비어 있음")
            }
        }
        if stone != nil, isLastMove { parts.append("마지막 수") }
        if stone != nil, isAuto { parts.append(GomokuNoticeText.autoPlacedStone) }
        return parts.joined(separator: ", ")
    }

    // MARK: AI 대국(1.0.1) — 맥 `GomokuText` 의 AI 절(docs/plan/gomoku-ai.md §5)을 그대로 옮겼다. 폰에서 새로 쓴 줄은 `// 폰`.

    package static let aiButton = "AI와 두기"
    package static let aiButtonHelp = "루비·전적 없이 AI와 연습해요"
    package static let aiPromptTitle = "AI와 두기"
    package static let aiPromptCaption = "돌 색을 고르면 바로 시작해요"
    /// 사용자 결정 둘(루비 안 걸기 · 기록 안 남기기)을 시작 전에 한 번, 대국 중에 한 번 더 말한다(맥과 같은 두 자리).
    package static let aiNoRecord = "루비·전적·순위에 남지 않아요"
    package static let aiPlayBlack = "흑 · 먼저 둬요"
    package static let aiPlayWhite = "백 · 나중에 둬요"
    package static let aiThinking = "AI가 생각 중이에요"
    package static let aiThinkingShort = "생각 중"
    package static let aiStakeChip = "AI 대국 · 기록 없음"
    package static let aiResignConfirm = "기권하면 이 판은 AI가 이겨요"
    package static let aiRematch = "같은 색으로 다시 두기"
    package static let aiRematchHelp = "같은 돌 색으로 AI와 새 판을 시작해요"
    package static let aiOpponentLine = "상대 · AI"
    /// 폰: 맥 `aiInfoClock`("창을 닫거나 가리면 …")의 폰판 — 폰에는 창이 없고, 사람 시계가 멈추는 계기는 **화면을 떠남 · 앱을 나감**이다
    /// (`GamesStore` 가 둘을 코어의 창 숨김·가림으로 옮긴다). 1:1 의 `clockRunsInBackground`("앱을 나가도 차례 시간은 흘러요")와
    /// 정반대 사실이라 AI 판에서 그 줄을 그대로 두면 거짓말이 된다.
    package static let aiClockPauses = "화면을 떠나거나 앱을 나가면 내 시계가 멈춰요 · 한 수 30초가 지나면 자동으로 놓여요"

    /// AI 판 결과 이유. 1:1 문구는 루비("건 루비는 돌려받아요")·"상대"를 말해서 AI 판에는 쓰지 않는다(맥 `aiEndReason` 과 같은 표).
    package static func aiEndReason(_ reason: GomokuEndReason?, outcome: GomokuOutcome?) -> String {
        switch (reason, outcome) {
        case (.five?, .won?): return "5목을 완성했어요"
        case (.five?, _): return "AI가 5목을 완성했어요"
        case (.resign?, _): return "기권했어요"
        case (.boardFull?, _): return "판이 가득 찼어요"
        case (.abandoned?, _): return GomokuNoticeText.abandoned(outcome: outcome)
        case (.timeout?, _): return "시간이 다 됐어요"
        case (nil, _): return ""
        }
    }

    /// 판 전체 요약(보이스오버 머리).
    package static func boardAccessibility(_ match: GomokuMatchState, forbiddenCount: Int) -> String {
        var black = 0
        var white = 0
        for y in 0..<GomokuBoard.size {
            for x in 0..<GomokuBoard.size {
                guard let point = GomokuPoint(x: x, y: y) else { continue }
                switch match.board[point] {
                case .black?: black += 1
                case .white?: white += 1
                case nil: break
                }
            }
        }
        var parts = ["오목판", "흑 \(black)개", "백 \(white)개"]
        parts.append(match.lastMove.map { "마지막 수 \($0.notation)" } ?? "아직 둔 돌이 없어요")
        if match.isFinished {
            parts.append("대국이 끝났어요")
        } else {
            parts.append(match.turn == match.myColor ? myTurn : opponentTurn)
        }
        if forbiddenCount > 0 { parts.append("금수 자리 \(forbiddenCount)곳") }
        return parts.joined(separator: ", ")
    }
}
