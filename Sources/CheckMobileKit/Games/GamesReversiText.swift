import CheckCore
import Foundation

/// 폰 아잉 뒤집기(1.0.17 · 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)") 문구 표.
///
/// ── 어디까지가 이 표의 몫인가 ───────────────────────────────────────────────────────────────
/// **안내·결과 사유는 코어가 쥔다**(`ReversiNoticeText` — 신청·취소·수락·착수·기권 응답 · 패스 · 자동 착수 · 관전 · 배포 창).
/// 맥과 폰이 같은 서버 응답을 같은 말로 옮겨야 하므로 그 표를 **다시 쓰지 마라.** 게임 이름 글자도 그 표 한 곳이다(`gameName`).
/// 이 표는 **화면에 붙는 글자**(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다. 맥 `ReversiText`(Sources/check — 폰 빌드에 안 들어간다)는
/// 배치·낱말 참고로만 쓴다 — 맥 표를 코어로 옮기면 맥 시험이 흔들린다(조사 impl_notes).
///
/// ── 상표 ──
/// 게임 이름은 '아잉 뒤집기'뿐이다. '리버시'는 **규칙 설명**으로만 쓴다(맥 `ReversiText.subtitle` 과 같은 자리). 다른 상표 낱말은
/// 저장소 어디에도 쓰지 않는다(`V03xxReversiTrademarkTests` 가 저장소 전역을 훑는다).
///
/// 레인 규약: 키를 더할 때는 **자기 절 끝**에만 더한다(화면 갈래들이 같은 줄을 고치지 않게).
/// 이 파일에 `#if os(iOS)` 를 두지 마라 — 맥 스위트가 값으로 재는 자리라야 폰 화면의 글자가 검증된다.
package enum ReversiPhoneText {

    // MARK: - 공용 · 게임 탭 카드 (배선 갈래 1/4)

    package static let title = ReversiNoticeText.gameName
    /// 게임 탭 카드 부제 · 로비 머리글 부제(맥 `ReversiText.subtitle` 과 같은 한 줄 — 규칙 · 선공 · 한 수 시간).
    package static let subtitle = "리버시 규칙 · 흑 선공 · 한 수 30초"
    package static let cardSubtitle = subtitle
    /// 게임 탭 카드의 보이스오버 힌트(막히지 않았을 때).
    package static let cardOpenHint = "\(ReversiNoticeText.gameName) 대결 화면을 열어요"
    /// 카드 칩: 받은 신청이 있다(몇 건인지는 칩이 말한다 — 탭 배지와 같은 수).
    package static func incomingChip(_ count: Int) -> String { "받은 신청 \(count)건" }
    /// 카드 보조 줄: 보낸 신청의 답을 기다린다.
    package static let outgoingLine = "보낸 신청의 답을 기다리고 있어요"
    /// 칩도 보조 줄 재료도 없을 때의 카드 한 줄(= 할 일을 말한다). AI 연습이 있다는 것도 함께 말한다(체스 카드 부제와 같은 자리).
    package static let idleLine = "사람을 골라 신청하거나 로봇과 연습해 보세요"

    package static let recordTitle = "내 전적"
    package static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }

    package static func record(_ record: ReversiRecord?) -> String {
        guard let record else { return self.record(wins: 0, losses: 0, draws: 0) }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    // MARK: - 판 · 결과 · 로봇 연습 (판 갈래 2/4)
    //
    // 맥 `ReversiText` 의 대국·결과·AI 절과 **같은 사실을 같은 말로** 옮겼다. 폰에서 달라진 자리는 셋이다:
    //  · 연습 상대 이름이 '로봇'이다 — 코어 `ReversiUser.reversiAI`(이름 "로봇" · 캐릭터 robot)와 게임 탭 카드 한 줄
    //    ("…로봇과 연습해 보세요")이 이미 그 이름을 쓴다. 맥은 같은 자리에 'AI'를 그린다(맥 화면 표의 몫).
    //  · 끝난 까닭의 '상대'는 로봇 판에서 '로봇'이다(한 함수가 주어만 바꾼다 — 두 벌을 두면 한쪽만 고쳐진다).
    //  · 호버 툴팁이 없으므로 시계 규칙을 판 밑 한 줄로 말한다(1:1 은 서버 시계 · 로봇 판은 화면을 떠나면 멈춘다).

    package static let me = "나"
    /// 별명을 모르는 상대(탈퇴·익명화·옛 응답).
    package static let opponentFallbackName = "상대"
    package static let myTurn = "내 차례예요"
    package static let opponentTurn = "상대 차례예요"
    /// 1:1 판의 내 마감 + 서버 유예가 지났다 — 서버가 합법 수 가운데 하나를 대신 두는 중이다(폰이 정한 것이 아니다).
    package static let mySettling = "시간이 지나 자동으로 놓이는 중이에요"
    package static let opponentSettling = "상대 시간이 지나 자동으로 놓이는 중이에요"

    package static func stoneName(_ color: ReversiColor) -> String { color == .black ? "흑" : "백" }
    /// 카드의 돌 수 줄 "흑 · 12개".
    package static func discLine(_ color: ReversiColor, count: Int) -> String { "\(stoneName(color)) · \(count)개" }
    /// 판 위 돌 수 한 줄 "흑 2 · 백 2 · 빈칸 60".
    package static func counts(_ counts: ReversiCounts) -> String {
        "흑 \(counts.black) · 백 \(counts.white) · 빈칸 \(counts.empty)"
    }
    /// 연달아 자동으로 놓인 횟수(카드 꼬리). 0 이면 말하지 않는다.
    package static func autoStreak(_ streak: Int, limit: Int) -> String? {
        streak > 0 ? "자동 \(streak)/\(limit)" : nil
    }
    /// 한 번 더 놓치면 지는 순간(빨강 한 줄). 맥 `ReversiText.autoStreakWarning` 과 같은 말.
    package static func autoStreakWarning(_ streak: Int, limit: Int) -> String? {
        guard limit > 1, streak == limit - 1 else { return nil }
        return "한 번 더 시간이 지나면 져요"
    }
    /// 판 위 회색 점이 말하는 것을 글자로도(폰엔 툴팁이 없다).
    package static func autoPlacedCount(_ count: Int) -> String { "시간이 지나 자동으로 놓인 돌 \(count)개 · 회색 점" }

    /// 판 밑 시계 규칙 한 줄. **숫자는 서버가 말한 값**(로비 `turn_seconds` · 판의 `auto_abandon_streak`)에서 만든다.
    /// 1:1 은 앱을 나가도 서버 시계가 흐르고, 로봇 판은 화면을 떠나면 사람 시계가 멈춘다(**정반대 사실** — 한 줄이 둘을 가른다).
    package static func clockLine(isAI: Bool, turnSeconds: Int, lossStreak: Int) -> String {
        let rule = "한 수 \(turnSeconds)초가 지나면 자동으로 놓이고 \(lossStreak)번 이어지면 져요"
        return (isAI ? "화면을 떠나거나 앱을 나가면 내 시계가 멈춰요" : "앱을 나가도 차례 시간은 흘러요") + " · " + rule
    }

    /// 남은 초("12초").
    package static func remaining(_ seconds: Double) -> String { "\(Int(max(0, seconds).rounded(.up)))초" }
    package static func clockAccessibility(_ seconds: Double) -> String { "남은 시간 \(remaining(seconds))" }

    package static let movesTitle = "수 기록"
    package static let noMoves = "아직 둔 수가 없어요"
    /// 수 기록의 패스 칸.
    package static let pass = "넘김"
    /// 칸 표기("d3"). 범위 밖이면 "—".
    package static func coordinate(_ idx: Int?) -> String {
        guard let idx, let point = ReversiPoint(idx: idx) else { return "—" }
        return point.coord
    }
    /// 수 한 칸 글자: 돌이면 "d3"(자동이면 "d3 · 자동"), 패스면 "넘김".
    package static func plyText(_ ply: ReversiPly) -> String {
        switch ply.kind {
        case .pass: return pass
        case .stone: return ply.auto ? "\(coordinate(ply.idx)) · 자동" : coordinate(ply.idx)
        }
    }

    package static let resign = "기권"
    package static let resignConfirmTitle = "기권하면 건 루비를 잃어요"
    package static let resignConfirmMessage = "지금 기권하면 이 판은 상대가 이겨요."
    package static let resignNow = "기권하기"
    package static let keepPlaying = "계속 두기"
    package static let backToLobby = "로비로"

    // 결과.
    package static func outcomeTitle(_ outcome: ReversiMatchOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대국이 끝났어요"
        }
    }

    /// 끝난 까닭 한 줄(**내 기준**). 끝 사유 여섯 갈래를 빠짐없이 말한다(`default:` 로 접지 않는다 — 돈이 갈리는 문장이다).
    /// `opponent` 는 주어 낱말이다(1:1 '상대' · 로봇 판 '로봇'). `lossStreak` 는 그 판의 서버 값(자동 착수 연속 패 횟수).
    package static func endReason(
        _ reason: ReversiEndReason?, outcome: ReversiMatchOutcome?, opponent: String, lossStreak: Int
    ) -> String {
        guard let reason else { return "" }
        switch reason {
        case .wipeout: return outcome == .lost ? "내 돌이 모두 뒤집혔어요" : "\(opponent) 돌을 모두 뒤집었어요"
        case .boardFull: return "판이 가득 찼어요"
        case .noMoves: return "둘 다 둘 곳이 없어요"
        case .resign: return outcome == .won ? "\(opponent)\(subjectParticle(opponent)) 기권했어요" : "기권했어요"
        case .abandoned:
            return outcome == .won ? "\(opponent) 시간이 \(lossStreak)번 이어서 지났어요"
                                   : "시간이 \(lossStreak)번 이어서 지나 졌어요"
        case .unknown: return "대국이 끝났어요"
        }
    }

    /// 자연 종료 점수 줄 — **흑 : 백 고정**(내 색 먼저가 아니다). 빈칸이 있으면 판 위 돌 수를 괄호로 함께(빈칸은 이긴 쪽 점수다).
    package static func scoreLine(_ score: ReversiScore, counts: ReversiCounts) -> String {
        let main = "흑 : 백  \(score.black) : \(score.white)"
        guard counts.empty > 0 else { return main }
        return "\(main) (판 위 \(counts.black) : \(counts.white))"
    }
    /// 기권·자리 비움 판(점수 없음) — 점수 줄 대신 판 위 돌 수만.
    package static func boardOnlyLine(_ counts: ReversiCounts) -> String { "판 위 흑 \(counts.black) : 백 \(counts.white)" }

    /// 루비 변화(+5 / −5 / ±0).
    package static func rubyDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "±0"
    }
    package static func rubyDeltaAccessibility(_ text: String) -> String { "루비 \(text)" }
    /// 무승부 판의 루비 — 건 판돈이 그대로 돌아왔다.
    package static func drawRefund(stake: Int) -> String { "판돈 \(stake) 루비를 돌려받았어요" }
    /// " · 이기면 +5"(내비 부제 판돈 줄 꼬리 — 순이익).
    package static func stakeGainSuffix(_ stake: Int) -> String { " · 이기면 +\(DuelFee.winnerNet(stake: stake))" }

    /// 판 전체 보이스오버 한 줄(돌 수 · 차례 · 둘 수 있는 칸 수).
    package static func boardAccessibility(counts: ReversiCounts, turn: ReversiColor?, legalCount: Int) -> String {
        var text = "\(title) 판, \(self.counts(counts))"
        if let turn { text += ", \(stoneName(turn)) 차례" }
        if legalCount > 0 { text += ", 둘 수 있는 칸 \(legalCount)곳" }
        return text
    }

    /// 칸 하나의 보이스오버("d3, 흑 돌, 마지막 수" · "c4, 빈칸, 둘 수 있어요"). 칸 이름이 먼저다 — 판을 훑는 사람은 이름으로 찾는다.
    package static func cellAccessibility(
        idx: Int, stone: ReversiColor?, isLegal: Bool, isLast: Bool, isAuto: Bool
    ) -> String {
        var parts = [coordinate(idx)]
        if let stone {
            parts.append("\(stoneName(stone)) 돌")
            if isLast { parts.append("마지막 수") }
            if isAuto { parts.append("자동으로 놓임") }
        } else {
            parts.append("빈칸")
            if isLegal { parts.append("둘 수 있어요") }
        }
        return parts.joined(separator: ", ")
    }

    // 로봇 연습(맥 'AI와 두기' 와 같은 단계: 돌 색 고르기 → 곧바로 판 → 결과에서 같은 색으로 다시).
    package static let aiName = ReversiUser.reversiAI.displayName
    package static let aiButton = "로봇과 연습하기"
    package static let aiButtonHelp = "루비·전적 없이 로봇과 둬요"
    package static let aiPromptTitle = "어느 돌로 둘까요"
    package static let aiPromptCaption = "고르면 바로 시작해요"
    package static let aiPlayBlack = "흑 · 먼저 둬요"
    package static let aiPlayWhite = "백 · 나중에 둬요"
    package static let aiPlayRandom = "무작위"
    package static let aiNoRecord = "로봇과 둔 판은 루비·전적·순위에 남지 않아요"
    package static let aiStakeChip = "로봇과 연습 · 기록 없음"
    package static let aiThinking = "로봇이 생각 중이에요"
    package static let aiThinkingShort = "생각 중"
    package static let aiResignConfirmTitle = "기권하면 이 판은 로봇이 이겨요"
    package static let aiRematch = "같은 색으로 다시 두기"
    package static let aiOpponentLine = "상대 · 로봇"
    package static func opponentLine(_ name: String) -> String { "상대 · \(name)" }

    /// 로봇 연습 입구가 닫힌 까닭(맥은 버튼만 흐린다 — 폰엔 툴팁이 없어 **언제 풀리는지**를 글자로 말한다).
    package enum AIBlock: Equatable, Sendable, CaseIterable {
        /// 1:1 판이 서 있다(같은 계정 다른 기기의 판 포함).
        case playing
        /// 보낸 신청이 떠 있다 — 수락되는 순간 1:1 이 연습 판을 이긴다.
        case outgoingInvite
        /// 요청이 오가는 중.
        case busy
    }

    package static func aiBlock(_ reason: AIBlock) -> String {
        switch reason {
        case .playing: return "두고 있는 판이 끝나면 연습할 수 있어요"
        case .outgoingInvite: return "보낸 신청을 취소하면 연습할 수 있어요"
        case .busy: return "잠시 후 다시 눌러 주세요"
        }
    }

    /// 받침 고르기(이/가). 끝 글자에 받침이 있으면 "이", 없으면 "가"(한글이 아니면 "가").
    private static func subjectParticle(_ word: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "가" }
        return (last.value - 0xAC00) % 28 == 0 ? "가" : "이"
    }

    // MARK: - 로비 · 신청 · 받기 · 관전 · 순위 · 규칙 (로비 갈래 3/4)
    //
    // 맥 `ReversiText` 의 로비·관전·순위 절과 폰 체스·1:1 테트리스 로비 표(`ChessPhoneText` · `TetrisPhoneText`)를 본으로 **같은 사실을 같은 말로**
    // 옮겼다. 앱 안 1:1 낱말(판돈 · 도전 · 수락 · 거절)은 다른 1:1 화면과 같다 — 그 낱말은 앱 안에서 심사를 지났고, 스토어 글·심사 메모에는
    // 쓰지 않는다(docs/appstore.md 관례 — 이 표는 앱 화면 글자만 쥔다).
    // 숫자(한 수 초 · 신청 유효 초 · 연속 자동 패 횟수)는 **로비 응답 값**을 받는다 — 상수를 베끼면 서버가 바꾼 날 화면만 옛 숫자를 말한다.
    // 폰엔 호버 툴팁이 없다 — 막힌 버튼은 **왜**를, 아래 한 줄은 **언제 풀리는지**를 글자로 말한다(맥은 자물쇠 칩 + 툴팁).

    /// 로비 머리 한 줄. 한 수 시간은 서버가 말한 값(`ReversiStore.turnSeconds` — 응답 전에는 30)이다. 30초면 카드 부제(`subtitle`)와 같은 글자다.
    package static func lobbySubtitle(turnSeconds: Int) -> String { "리버시 규칙 · 흑 선공 · 한 수 \(max(1, turnSeconds))초" }

    package static let lobbyTitle = "상대 고르기"
    package static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    package static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    package static let loadingUsers = "상대 목록을 불러오고 있어요"
    package static func peopleCount(_ count: Int) -> String { "\(count)명" }
    package static let myRubyTitle = "내 루비"
    /// 값을 아직 모르는 숫자 칸(루비 잔액 미러가 비었다). 관전 이름 자리의 `watchUnknownName`(em dash)과 **다른 글리프**다.
    package static let unknownNumber = "–"
    /// 한 줄 안에서 토막을 잇는 머리("· 루비가 모자라요").
    package static let bulletPrefix = "· "
    /// 고른 칸의 접근성 값.
    package static let selected = "선택됨"
    /// 머리 두 칸 왼쪽(내 전적)의 보이스오버 — 제목과 값이 한 요소로 합쳐지므로 무슨 전적인지 말한다.
    package static func myRecordAccessibility(_ record: ReversiRecord?) -> String { "내 \(title) 전적 \(self.record(record))" }

    // 상대 한 줄.
    package static let challenge = "도전"
    package static let working = "근무 중"
    package static let notWorking = "근무 안 함"
    /// 막힌 [도전] 자리 글자 — **짧게**(알약 안에서 꺾이면 줄 높이가 는다). 뜻은 아래 `lockLegend` 한 줄이 풀어 말한다.
    package static let needsUpdateButton = "업데이트 필요"
    /// 상대가 지금 1:1 판을 두는 중(서버 `game__busy_users` — 어느 게임인지는 말하지 않는다. 지어내면 틀린 이름을 말한다).
    package static let inMatchButton = "대결 중"
    package static let focusButton = "집중 모드"
    /// [도전] 의 보이스오버 힌트 — 누르면 **바로 신청이 나가지 않는다**(판돈 시트가 먼저다).
    package static func challengeHint(name: String) -> String { "\(name)님에게 판돈을 골라 신청해요" }

    /// 상대를 지금 신청할 수 없는 까닭. **서열**: 옛 버전(상대가 앱을 올릴 때까지 가장 오래 간다) > 대결 중 > 집중.
    package enum Lock: Equatable, Sendable, CaseIterable {
        /// 상대 앱이 아잉 뒤집기를 모른다(서버 `reversi_capable` 거짓 · **모르면 거짓** — 코어 `user(from:)`).
        case outdated
        /// 상대가 1:1 판을 두는 중(서버 `game__busy_users`).
        case inMatch
        /// 상대가 집중 모드(서버 `target_focused`).
        case focus
    }

    /// 그 사람에게 걸린 까닭 전부(서열 순). 비었으면 신청할 수 있는 상대다.
    package static func locks(for user: ReversiUser) -> [Lock] {
        var locks: [Lock] = []
        if !user.isCapable { locks.append(.outdated) }
        if user.inMatch { locks.append(.inMatch) }
        if user.focusMode { locks.append(.focus) }
        return locks
    }

    /// 상대 한 줄이 쓰는 **두 자리** — 이름 아래 회색 부제와 오른쪽 버튼 글자.
    package struct OpponentRow: Equatable, Sendable {
        package let subtitle: String
        package let buttonTitle: String
    }

    /// 상대 한 줄의 두 자리를 **한 함수**가 고른다(체스·테트리스 표와 같은 까닭 — 자리마다 고르면 한 줄에 같은 말이 두 번 나오고 근무 축이 덮인다).
    /// 부제는 늘 **근무 축**으로 시작하고, 버튼은 서열 첫 까닭을 말한다. 버튼이 못 말한 까닭은 부제 꼬리로 보낸다(축 하나가 사라지지 않게).
    package static func opponentRow(for user: ReversiUser) -> OpponentRow {
        let work = user.isWorking ? working : notWorking
        let locks = locks(for: user)
        guard let first = locks.first else { return OpponentRow(subtitle: work, buttonTitle: challenge) }
        let tail = locks.dropFirst().map(lockButton)
        return OpponentRow(subtitle: ([work] + tail).joined(separator: " · "), buttonTitle: lockButton(first))
    }

    package static func lockButton(_ lock: Lock) -> String {
        switch lock {
        case .outdated: return needsUpdateButton
        case .inMatch: return inMatchButton
        case .focus: return focusButton
        }
    }

    /// 목록 아래 풀이 한 줄(그 까닭이 목록에 **있을 때만** 선다). 버튼 글자 + 왜 · 언제 풀리는지. 옛 버전 문장은 코어 거절 문구와 같다.
    package static func lockLegend(_ lock: Lock) -> String {
        switch lock {
        case .outdated: return "\(needsUpdateButton) · \(ReversiNoticeText.targetOutdated) — 상대가 앱을 올리면 신청할 수 있어요"
        case .inMatch: return "\(inMatchButton) · 다른 1:1 판을 두는 중이에요 — 판이 끝나면 신청할 수 있어요"
        case .focus: return "\(focusButton) · 상대가 집중 중이에요 — 집중이 끝나면 신청할 수 있어요"
        }
    }

    /// 지금 목록에 있는 까닭의 풀이 줄(서열 순 · 중복 없음).
    package static func lockLegends(users: [ReversiUser]) -> [String] {
        let present = Set(users.flatMap(locks(for:)))
        return Lock.allCases.filter(present.contains).map(lockLegend)
    }

    // 판돈(★ 빠지는 순간은 **수락**이다 — 신청만으로는 0원도 안 움직인다).
    package static let stakeTitle = "판돈"
    /// "5 · 이기면 +5" — 꼬리 숫자는 **순이익**(`DuelFee.winnerNet` — 결과 카드의 루비 변화와 같은 숫자).
    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    /// 판돈 칸 아래 줄 "이기면 +5"(꼬리 `stakeGainSuffix` 와 달리 앞 가운뎃점이 없다).
    package static func stakeGain(_ stake: Int) -> String { "이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    package static let stakePromptCaption = "판돈을 고르세요"
    package static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stakeLine(stake))" }
    package static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    /// 루비가 모자라 못 고르는 판돈의 까닭 — 앱의 다른 화면과 **같은 말**(한 곳).
    package static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)
    /// 판돈이 **언제** 빠지는지 — 오목·체스·테트리스와 같은 문장(주어가 '수락').
    package static let stakeCaption = GomokuPhoneText.stakeCaption
    /// 신청만 한 상태를 말하는 줄 — 체스와 같은 문장 한 곳("신청하면 빠져요" 는 거짓이다). 초는 로비 응답 값.
    package static func stakeNotHeldYet(ttlSeconds: Int) -> String { ChessPhoneText.stakeNotHeldYet(ttlSeconds: ttlSeconds) }
    package static func stakeOptionAccessibility(_ stake: Int) -> String { "판돈 루비 \(stake)" }

    // 받은 신청 · 보낸 신청(60초 — 로비 응답 `invite_ttl_seconds`).
    package static let incomingTitle = "받은 신청"
    package static let outgoingTitle = "보낸 신청"
    package static func incomingTitle(name: String) -> String { "\(name)님의 신청" }
    package static func outgoingTitle(name: String) -> String { "\(name)님에게 신청했어요" }
    package static let accept = "수락"
    package static let decline = "거절"
    package static let cancel = "취소"
    /// 받은 신청 절 머리 오른쪽 — 초는 로비 응답 값.
    package static func inviteTtlHint(ttlSeconds: Int) -> String { "\(ttlSeconds)초 안에 응답하세요" }
    /// "42초 남음"(받은·보낸 신청 부제 — 잎 뷰만 부른다).
    package static func remainingPhrase(_ seconds: Double) -> String { "\(remaining(seconds)) 남음" }

    /// 받은 신청 [수락] 이 두던 **로봇 판을 끝낸다** — 먼저 묻는다(체스와 같은 확인 · 같은 문장 한 곳).
    package static let acceptEndsRobotTitle = ChessPhoneText.acceptEndsRobotTitle
    package static let acceptEndsRobotMessage = ChessPhoneText.acceptEndsRobotMessage
    package static let acceptEndsRobotConfirm = ChessPhoneText.acceptEndsRobotConfirm
    package static let acceptEndsRobotCancel = ChessPhoneText.acceptEndsRobotCancel

    /// 판(로봇 연습 · 끝난 판) 화면 위 받은 신청 띠 — 로비가 가려진 동안에도 60초 신청을 놓치지 않게.
    package static func bannerTitle(name: String) -> String { "\(name)님이 \(title) 대결을 신청했어요" }
    /// 띠에 다 못 실은 나머지 신청 수.
    package static func incomingMore(_ count: Int) -> String { "외 \(count)건" }

    // 지금 대결 중 · 관전.
    package static let liveTitle = "지금 대결 중"
    package static let noLive = "지금 대결 중인 판이 없어요"
    package static func liveCount(_ count: Int) -> String { "\(count)판" }
    /// "민트별 · 달토끼" — a/b 는 uuid 순서다(색이 아니다 — 색은 관전 응답이 말한다).
    package static func livePair(_ live: ReversiLiveMatch) -> String { live.a.displayName + " · " + live.b.displayName }
    /// "1분 35초째"(체스와 같은 말 한 곳).
    package static func elapsedPhrase(_ seconds: Double) -> String { GamesChessText.elapsedPhrase(seconds) }
    package static let watch = "관전"
    package static let watchChipHint = "이 판을 지켜봐요"
    package static let myMatch = "내 판"
    /// 서버에 관전이 아직 없다(PGRST202) — 칩 대신 글자(보이스오버는 코어 문장 `ReversiNoticeText.unavailable`).
    package static let watchSoonCaption = "곧 열려요"
    package static let watchTitle = "관전 중"
    package static let leaveWatch = "나가기"
    package static let leaveWatchHint = "로비로 돌아가요"
    package static let watchLoading = "판을 불러오고 있어요"
    /// 끝난 판인데 대국자를 하나도 모른다(진행형으로 말하면 거짓말이다 — 폴링이 이미 멈췄다).
    package static let playersUnknown = "대국자를 불러오지 못했어요"
    /// 이름을 모르는 자리(코어 경계가 nil 이 아니라 빈 문자열을 넣는다 — `??` 로는 못 접는다).
    package static let watchUnknownName = "—"
    package static let stakeUnknown = "\(stakeTitle) —"
    package static func watchingTurn(_ turn: ReversiColor) -> String { "\(watchTitle) · \(stoneName(turn)) 차례" }
    /// 끝난 관전 판 머리 — **3인칭**("구름빵(흑) 승리"). 이름을 모르면 색만("흑 승리").
    package static func watchEndedWin(_ winner: ReversiColor, name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "\(stoneName(winner)) 승리" : "\(trimmed)(\(stoneName(winner))) 승리"
    }
    package static let watchEndedDraw = "무승부로 끝났어요"

    /// **관전** 끝난 까닭 — 3인칭(주어가 '흑'·'백'). 내 기준 `endReason` 을 남의 판에 쓰면 "흑 승리 / 기권했어요" 같은 자기모순이 된다
    /// (맥 `ReversiText.watchEndReason` 과 같은 표 · 자리 비움 횟수는 판의 서버 값).
    package static func watchEndReason(_ reason: ReversiEndReason?, winner: ReversiColor?, lossStreak: Int) -> String {
        guard let reason else { return "" }
        let loser = winner.map { stoneName($0.opponent) }
        switch reason {
        case .wipeout: return loser.map { "\($0) 돌이 모두 뒤집혔어요" } ?? "한쪽 돌이 모두 뒤집혔어요"
        case .boardFull: return "판이 가득 찼어요"
        case .noMoves: return "둘 다 둘 곳이 없어요"
        case .resign: return loser.map { "\($0)\(subjectParticle($0)) 기권했어요" } ?? "기권으로 끝났어요"
        case .abandoned:
            return loser.map { "\($0) 시간이 \(lossStreak)번 이어서 지났어요" } ?? "시간이 \(lossStreak)번 이어서 지나 끝났어요"
        case .unknown: return "대국이 끝났어요"
        }
    }

    package static let watchCaption = "판만 보여 줘요 · 관전자는 둘 수 없어요"
    /// 서버 `reversi_watch_tail_seconds()`(180초) — 끝난 판은 그 안에서만 관전 응답이 온다.
    package static let watchTailCaption = "끝난 판은 3분 동안만 볼 수 있어요"
    package static func watchMoves(_ count: Int) -> String { "\(max(0, count))수" }

    // 순위(승점 = 승 − 패 · 서버 순서 그대로 · 0판은 안 낀다).
    package static let rankTitle = "\(title) 순위"
    package static let rankCaption = "승점 = 승 − 패"
    package static let rankZeroGamesNote = "한 판도 두지 않으면 순위에 들어가지 않아요"
    package static let myRankTitle = "내 순위"
    package static let outOfRank = "순위 밖"
    package static let noRanking = "아직 전적이 없어요"
    package static let noRankingHint = "첫 판이 끝나면 순위가 올라와요"
    /// 서버에 순위가 아직 없다(PGRST202) — 실패가 아니라 '곧'.
    package static let rankingUnavailable = "순위는 곧 열려요"
    package static let rankLoading = "순위를 불러오고 있어요"
    /// 접힌 상태의 행 수 · 펼쳤을 때 상한(서버는 100행까지 준다).
    package static let rankCollapsedRows = 5
    package static let rankRowLimit = 100
    package static func rankSeeAll(total: Int) -> String { "전체 보기 · \(peopleCount(total))" }
    package static let rankCollapse = "접기"
    /// 전적 컷이 있으면 머리 오른쪽 "10월 1일부터" — **KST 로 못 박는다**(컷은 서버의 KST 자정이다 · 체스 표와 같은 까닭).
    package static func rankSince(_ date: Date) -> String { GamesChessText.rankSince(date) }
    /// 컷이 없다(`record_since_ms` null) — 기간이 통째다.
    package static let rankWholePeriod = "전체 기간"

    /// 승점의 부호 있는 짧은 꼴("+9" · "−3" · "0").
    package static func signedPoints(_ points: Int) -> String {
        if points > 0 { return "+\(points)" }
        if points < 0 { return "−\(-points)" }
        return "0"
    }

    package static func points(_ points: Int) -> String { "승점 \(signedPoints(points))" }

    /// 목록 밖 내 순위 한 줄 — "12위 · 승점 +4 · 6승 2패 1무"(0판이면 "순위 밖 · 0승 0패 0무").
    package static func myRankLine(_ mine: ReversiMyRank) -> String {
        let record = record(wins: mine.wins, losses: mine.losses, draws: mine.draws)
        guard let rank = mine.rank else { return "\(outOfRank) · \(record)" }
        return "\(rank)위 · \(points(mine.points)) · \(record)"
    }

    /// 순위 한 행의 보이스오버 — "3위, 나, 민트별, 서울센터, 승점 +4, 6승 2패 1무"(승점만 말하지 않는다 — 사용자 지시).
    package static func rankRowAccessibility(_ entry: ReversiRankEntry, isMe: Bool) -> String {
        var parts = ["\(entry.rank)위"]
        if isMe { parts.append(me) }
        parts.append(entry.user.displayName)
        if let center = entry.user.center, !center.isEmpty { parts.append("\(center)센터") }
        parts.append(points(entry.points))
        parts.append(record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
        return parts.joined(separator: ", ")
    }

    // 규칙 시트(맥 `ReversiRulesOverlayLines` 의 여덟 줄 + 폰이 글자로 말해야 하는 두 줄 — 툴팁이 없다).
    package static let rulesTitle = "\(title) 규칙"
    package static let rulesExamplesTitle = "그림으로 보기"

    /// 규칙 줄(순서 고정). 숫자 셋은 **로비 응답 값**(한 수 초 · 연속 자동 패 · 신청 유효 초).
    /// 9번(신청)·10번(앱을 나가면)은 폰 몫이다 — 맥은 같은 사실을 창 안 툴팁·캡션으로 말한다.
    package static func rules(turnSeconds: Int, lossStreak: Int, inviteTtlSeconds: Int) -> [String] {
        [
            "흑이 먼저 둬요. 가운데 네 칸에 흑 둘·백 둘을 엇갈려 놓고 시작해요.",
            "상대 돌을 내 돌 사이에 끼우도록 두면 끼인 돌이 모두 내 색으로 뒤집혀요. 가로·세로·대각선 여러 줄이 한 번에 뒤집힐 수 있어요.",
            "하나도 못 뒤집는 칸에는 둘 수 없어요. 둘 수 있는 칸은 점으로 보여요.",
            "둘 곳이 없으면 차례가 저절로 넘어가요. 둘 곳이 있으면 넘길 수 없어요.",
            "둘 다 둘 곳이 없으면 끝나요. 돌이 많은 쪽이 이기고, 남은 빈칸은 이긴 쪽 점수에 더해요. 같으면 32 : 32 무승부예요.",
            "한 수에 \(max(1, turnSeconds))초. 넘기면 둘 수 있는 칸 가운데 하나에 저절로 놓여요. 연달아 \(max(1, lossStreak))번 저절로 놓이면 져요.",
            "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, 무승부면 건 판돈을 돌려받아요.",
            "신청은 \(max(1, inviteTtlSeconds))초 안에 답이 없으면 사라지고, 신청만으로는 루비가 빠지지 않아요.",
            "1:1 은 앱을 나가도 차례 시간이 흘러요. 로봇과 둔 판은 루비·전적·순위에 남지 않아요.",
            "리버시와 같은 규칙이에요. 리버시를 알면 따로 배울 것이 없어요."
        ]
    }
}
