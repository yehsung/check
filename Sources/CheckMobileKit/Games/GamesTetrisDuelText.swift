import CheckCore
import Foundation

/// 폰 1:1 테트리스(1.0.11) 문구 표.
///
/// ── 어디까지가 이 표의 몫인가 ───────────────────────────────────────────────────────────────
/// **안내·결과 사유는 코어가 쥔다**(`TetrisDuelNoticeText` — 신청·취소·수락·기권 응답과 결과 카드의 사유 한 줄).
/// 맥과 폰이 같은 서버 응답을 같은 말로 옮겨야 하므로 그 표를 **다시 쓰지 마라.**
/// 이 표는 **화면에 붙는 글자**(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다.
///
/// ── 맥 `TetrisDuelText` 와 갈리는 곳은 셋이다 ──────────────────────────────────────────────
/// ① **조작**: 맥은 키 표(← → ↓ ↑ X Z C 스페이스), 폰은 제스처 + 버튼 셋이다(솔로 폰 테트리스와 같은 조작).
/// ② **판을 떠나는 일의 뜻이 반대다.** 맥은 "창을 가리거나 내려도 판은 계속 흘러가요" 가 **안심**이고(D10),
///    폰은 앱을 나가면 판 루프가 멎어 15초 침묵으로 **진다**(서버 D5). 그래서 같은 자리의 문장이 **경고**다.
///    맥 문장을 폰에 옮기면 그대로 거짓말이 된다 — `leaveWarning` 이 그 자리를 대신한다.
/// ③ 입구가 카드다(게임 탭) — 칩·보조 줄·보이스오버 힌트가 체스 카드와 같은 꼴로 더 있다.
///
/// 레인 규약: 키를 더할 때는 **자기 절 끝**에만 더한다(로비 레인·대결 레인이 같은 줄을 고치지 않게).
/// 이 파일에 `#if os(iOS)` 를 두지 마라 — 맥 스위트가 값으로 재는 자리라야 폰 화면의 글자가 검증된다.
package enum TetrisPhoneText {

    // MARK: - 공용 (두 절이 함께 쓴다)

    package static let title = "1:1 테트리스"
    /// 게임 탭 카드 부제 · 로비 머리글 부제(맥과 같은 한 줄 — 승부 방식을 먼저 말한다).
    package static let subtitle = "공격형 · 먼저 꼭대기까지 쌓이면 져요"
    package static let cardSubtitle = subtitle
    /// 게임 탭 카드의 보이스오버 힌트(막히지 않았을 때).
    package static let cardOpenHint = "1:1 테트리스 대결 화면을 열어요"
    package static let close = "닫기"

    /// 판돈 줄. 이기면 **순이익**(판돈 − 수수료, `DuelFee.winnerNet`) — 결과 카드의 루비 변화와 같은 숫자다.
    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 신청하기" }
    package static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    package static let stakePromptCaption = "판돈을 고르세요"

    package static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }

    package static func record(_ record: TetrisDuelRecord?) -> String {
        guard let record else { return self.record(wins: 0, losses: 0, draws: 0) }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    package static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    /// 남은 초(신청 TTL · 준비 대기). 음수는 0 으로.
    package static func remainingSeconds(_ seconds: Int) -> String { "\(max(0, seconds))초 남음" }

    /// 규칙 보기. 공격 표 · 가속 · 침묵 · 판돈은 **설계서 결정 그대로**다(D2 · D5 · D7 · D4).
    /// ★ "연결" 항목이 맥과 다르다(머리말 ②) — 폰은 앱을 나가면 진다.
    package static let rulesTitle = "1:1 테트리스 규칙"
    package static let rules: [(title: String, detail: String)] = [
        ("공격", "2줄을 한 번에 지우면 상대에게 방해 줄 1줄, 3줄은 2줄, 4줄은 4줄을 보내요. "
            + "들어올 방해 줄이 있으면 내가 보낼 줄이 먼저 그것을 지워요."),
        ("방해 줄", "줄을 지우지 못한 채 조각이 굳으면 아래에서 회색 줄이 올라와요. 판 왼쪽 빨간 막대가 들어올 줄이에요."),
        ("승부", "먼저 꼭대기까지 쌓이는 쪽이 져요. 2분이 지나면 떨어지는 속도가 점점 빨라져요."),
        ("조작", "판을 좌우로 끌어 옮기고, 아래로 끌어 내려요. 판을 톡 누르면 회전해요. "
            + "아래 버튼으로 홀드 · 반대로 회전 · 바로 내리기를 해요."),
        ("앱을 나가면", "판 중에 앱을 나가면 판이 멈춰서 15초 뒤에 져요. 대결이 끝날 때까지 앱을 켜 두세요."),
        ("판돈", "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고(수수료 \(DuelFee.percent)% 빼고), "
            + "무승부면 돌려받아요. 30초 안에 둘 다 들어오지 않아도 돌려받아요.")
    ]

    // MARK: - 로비 (레인 B)

    package static let usersTab = "상대 고르기"
    package static let rankTab = "순위"
    package static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    package static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    package static let loadingUsers = "상대 목록을 불러오고 있어요"
    // ★ **불러오기 실패 문구·[다시 시도] 버튼을 이 표에 두지 마라.** 폰은 공용 부품 한 벌이 쥔다
    //   (`MobileComponentRules.retry` · `.checkConnection` · `LoadFailureRow` · `EmptyStateView`) —
    //   `IntegrationFixTests.designConsistencyContracts` 가 그 리터럴이 CheckMobileKit 안에서 **한 파일에만**
    //   있는지 센다. 맥 표에는 `reloadUsers`·`usersLoadFailed` 가 있지만 폰에 옮기면 그 단언이 빨개진다.
    package static let challenge = "신청"
    package static let needsUpdate = "앱 업데이트 필요"
    package static let inMatch = "대결 중"
    package static let working = "근무 중"
    package static let focused = "집중 모드"

    package static let stakeTitle = "판돈"
    package static let incomingTitle = "받은 신청"
    package static let incomingChip = "받은 신청"
    package static func incomingMore(_ count: Int) -> String { "외 \(count)건" }
    package static let outgoingTitle = "보낸 신청"
    package static let outgoingLine = "보낸 신청의 답을 기다리고 있어요"
    package static let noIncoming = "받은 신청이 없어요"
    package static let accept = "수락"
    package static let decline = "거절"
    package static let cancel = "취소"
    /// 칩도 보조 줄도 없을 때의 카드 한 줄(= 할 일을 말한다).
    package static let idleLine = "사람을 골라 대결을 신청해 보세요"

    package static let recordTitle = "내 전적"
    package static let liveTitle = "지금 대결 중"
    package static let noLive = "지금 진행 중인 대결이 없어요"
    package static let myMatch = "내 판"

    package static let rankLoading = "순위를 불러오고 있어요"
    package static let rankEmpty = "아직 순위가 없어요"
    package static let rankSoon = "순위는 곧 열려요"
    package static let rankHelp = "승점 = 승 − 패"

    package static func rankSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일부터"
        return formatter.string(from: date)
    }

    // MARK: - 대결 (레인 C)

    package static let me = "나"
    package static let elapsedTitle = "경과"
    /// 2분이 지나 가속이 걸렸다(D7 — 레벨 바닥이 1 을 넘었다).
    package static let speedUp = "속도 올라가는 중"
    package static func speedLevel(_ level: Int) -> String { "레벨 \(level)" }
    package static let connectionTrouble = "연결 확인 중"
    package static let opponentSilent = "상대 연결 확인 중"
    package static let linesTitle = "지운 줄"
    package static let attackTitle = "보낸 공격"
    package static let incomingLinesTitle = "들어올 줄"
    package static let ready = "준비 완료"
    package static let notReady = "들어오는 중"
    package static let finishedPresence = "대결 끝"
    package static let waitingTitle = "상대를 기다리는 중"
    package static func waitingSubtitle(seconds: Int) -> String { "\(max(0, seconds))초 안에 둘 다 들어오면 시작해요" }
    /// 맥은 "창을 열어 두세요", 폰은 앱이다.
    package static let waitingAction = "앱을 켜 둔 채 기다려 주세요"
    package static let startingSoon = "곧 시작해요"
    package static let playingNow = "대결 중"
    package static let toppedOutTitle = "꼭대기에 닿았어요"
    package static let toppedOutSubtitle = "결과를 기다리는 중"

    /// ★ 판 위에 **늘 보이는 한 줄**(머리말 ②). 규칙 시트에만 두면 안 된다 — 판 중에 전화가 와서 나가는 사람은
    ///   규칙을 읽지 않는다. 판돈이 걸린 판을 조용히 잃는 길을 글자 없이 두지 않는 것이 이 줄의 일이다.
    package static let leaveWarning = "판 중에 앱을 나가면 져요"

    package static let resign = "기권"
    package static let confirmResign = "기권하기"
    package static let keepPlaying = "계속하기"
    package static let resignWarning = "기권하면 판돈을 잃어요"
    package static let backToLobby = "로비로"

    package static let controlsTitle = "조작"
    /// 조작 안내(솔로 폰과 같은 제스처·버튼). **정지는 없다** — 대결은 멈출 수 없다.
    package static let controls: [(gesture: String, action: String)] = [
        ("좌우로 끌기", "이동"), ("톡 누르기", "회전"), ("아래로 끌기", "빨리 내리기"),
        ("[홀드]", "홀드"), ("[반대로]", "반대로 회전"), ("[바로 내리기]", "바로 내리기")
    ]

    package static func outcomeTitle(_ outcome: TetrisDuelOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대결이 끝났어요"
        }
    }

    /// 판 시계 글자(`m:ss`). 음수는 0 으로.
    package static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// 루비 증감 글자(+N / −N / 0).
    package static func rubyDelta(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    // ── 대결 절 (레인 C 가 더한 자리 — 판 화면·캔버스가 읽는다) ──────────────────────────────

    /// 판 위 글자 겹. 솔로 캔버스와 **같은 말**이고(두 판이 같은 그림이어야 한다) 자리는 코어 배치 표가 정한다.
    package static let holdLabel = "홀드"
    package static let nextLabel = "다음"
    /// 값 자리는 자기설명형이다 — 폰은 8pt 캡션을 못 쓴다(iOS 캡션 하한 10pt · 캔버스 머리말 ②).
    package static func levelValue(_ level: Int) -> String { "Lv " + String(level) }
    package static func linesValue(_ lines: Int) -> String { String(lines) + "줄" }
    /// 판 밑 밴드·상대 줄의 들어올 줄(미터와 같은 빨강으로 쓴다).
    package static func incomingLines(_ lines: Int) -> String { incomingLinesTitle + " " + String(lines) }

    package static let myBoardLabel = "내 판"
    package static let opponentBoardLabel = "상대 판"

    /// 조작 버튼 세 개의 **글자**. `controls` 표의 꺾쇠 안 말과 **같아야 한다**(규칙 시트와 버튼이 갈리면
    /// 같은 버튼을 두 이름으로 부르게 된다 — 테스트가 그 둘을 묶어 둔다).
    /// ⚠️ 솔로 폰은 같은 버튼을 "반시계"·"즉시 내리기" 로 부른다(`GamesMiniGameText`). 1.0.11 은 대결 표의
    /// 말을 쓴다 — 통합 때 메인 세션이 한쪽으로 모으면 여기와 `controls` 두 줄만 고치면 된다.
    package static let holdButton = "홀드"
    package static let rotateCounterButton = "반대로"
    package static let hardDropButton = "바로 내리기"
    /// 홀드를 이미 쓴 조각(버튼의 보이스오버 값).
    package static let holdSpent = "이미 썼어요"

    /// 기권 확인 시트 제목(본문은 `resignWarning` · 버튼은 `confirmResign`/`keepPlaying`).
    package static let resignConfirmTitle = "기권할까요?"
}
