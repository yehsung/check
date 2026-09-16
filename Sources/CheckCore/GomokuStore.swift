import Foundation
import Observation
import OSLog

// 1:1 오목 대결 스토어(v0.3.27) — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출.
//
// ── 이 파일이 지키는 규칙 ──
//  ① **서버가 권위다.** 대국 판·차례·마감·결과·루비는 전부 RPC 응답으로만 바뀐다. 낙관적 착수·낙관적 차감은 없다
//     — 두 곳에서 바꾸면 실패한 수가 화면에서만 놓이고, 실패한 수락이 화면에서만 루비를 뺀다.
//  ② **시각은 서버 시계로 보정한다.** 마감·신청 만료는 서버 epoch 밀리초로 오고, 같은 응답의 server_now_ms 와의
//     차이로 기기 시계 어긋남을 지운다(`serverClockOffset`). 기기 시계가 5초 빠른 맥이 "25초 남음"을 보면 안 된다.
//  ③ **폴링은 창이 보일 때만 돈다**(무료 플랜 예산). 창이 안 보이면 받은 신청은 팝오버 열기(60초 스로틀)·실시간
//     'gomoku' 신호·조인 직후 따라잡기·근무 시작·깨어남에서만 본다. v0.3.30 부터 이 계기들은 **근무 여부를 보지 않는다** —
//     서버가 신청·수락의 근무 조건을 지웠고, 소켓은 로그인 중이면 붙어 있다(WorkTimerStoreRealtime).
//  ④ **늦게 온 응답은 버린다.** 로그아웃·계정 전환(host.sessionGeneration)과 이 스토어의 reset(resetGeneration)
//     두 세대를 모두 대조한다 — 하나만 보면 로그아웃 직후 도착한 앞 계정의 판이 새 계정 화면에 뜬다.
//     채팅에는 세대가 하나 더 있다(chatGeneration) — 음소거 토글 전에 나간 조회의 응답은 값도 줄도 앞 판정이다.
//  ⑤ **사용자 문구는 GomokuNoticeText 한 곳에만 있다.** status 이름·서버·동기화 같은 진단 어휘는 화면에 싣지 않는다.
//  ⑥ **초 단위 값은 창의 잎 뷰만 읽는다.** remainingSeconds(now:) 는 잎 뷰 TimelineView 가 now 를 넘겨 부르는
//     순수 계산이고, 이 스토어는 매초 아무것도 대입하지 않는다(팝오버 V0238 무효화 계약).

// MARK: - 화면 값 타입 (설계서 §6.3 선언 그대로 — ui 트랙이 이 선언만 믿고 짠다)

package nonisolated enum GomokuStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

package nonisolated struct GomokuUser: Identifiable, Equatable, Sendable {
    package let id: String                 // user uuid 소문자 문자열
    package let displayName: String
    package let avatarURL: String?
    package let characterID: String?
    package let isWorking: Bool
    package let isCapable: Bool            // 상대 앱이 오목을 아는 버전
    package let inMatch: Bool
    /// 0.3.29 — 소속 센터의 **화면 글자**("서울"/"부산"). 서버 어휘가 아니다: 경계 둘(`peerUser` · `user(from:)`)에서
    /// `CenterLabel.display` 를 **한 번만** 지나 들어온다(변환이 두 벌이 되면 한쪽이 언젠가 틀린다 — CenterLabel 머리말).
    /// 모르는 값·안 싣는 옛 서버는 nil = 배지 없음이다.
    /// **기본값이 있는 채로 맨 끝에 둔다** — 멤버와이즈 초기화를 쓰는 렌더·스토어 테스트가 그대로 컴파일돼야 한다.
    package var center: String? = nil
}

package nonisolated struct GomokuRecord: Equatable, Sendable { package let wins: Int; package let losses: Int; package let draws: Int }

package nonisolated struct GomokuInvite: Identifiable, Equatable, Sendable {
    package let id: String                 // match id
    package let peer: GomokuUser           // 받은 신청이면 신청자, 보낸 신청이면 상대
    package let stake: Int
    package let expiresAt: Date            // 기기 시계로 보정된 시각
}

package nonisolated enum GomokuEndReason: String, Sendable {
    case five
    /// **옛 어휘**(0.3.27: 시간 초과 = 즉시 패배). 새 서버는 이 사유로 판을 끝내지 않지만 **옛 판 기록에 남아 있고**
    /// 배포 중간 창의 옛 서버가 아직 보낸다 — 지우지 마라.
    case timeout
    case resign
    case boardFull = "board_full"

    /// 0.3.28 — 자동 착수가 **연속 3번** 놓여 끝난 판(자리 비움 패배). 문구는 `GomokuNoticeText.abandoned(outcome:)`.
    ///
    /// 이 케이스와 `GomokuText.endReason(_:outcome:)` 의 두 줄은 **같은 커밋에서** 갔다 — 그 함수가 default
    /// 없는 전수 스위치라, 케이스만 넣으면 컴파일이 깨진다(코어가 이 자리를 비워 두고 UI 트랙에 넘긴 이유).
    case abandoned
}

package nonisolated enum GomokuOutcome: Equatable, Sendable { case won, lost, draw }

package nonisolated struct GomokuMatchState: Identifiable, Equatable, Sendable {
    package let id: String
    package var stake: Int
    package var myColor: GomokuColor
    package var opponent: GomokuUser
    package var board: GomokuBoard
    package var lastMove: GomokuPoint?
    package var moveCount: Int
    package var turn: GomokuColor?         // 끝나면 nil
    package var deadline: Date?            // 차례 마감(기기 시계로 보정), 끝나면 nil
    package var isFinished: Bool
    package var outcome: GomokuOutcome?
    package var endReason: GomokuEndReason?
    package var rubyDelta: Int?            // 이 판으로 내 루비가 변한 양(승 +stake, 패 -stake, 무 0)
    package var blackPassed: Bool          // 직전에 흑 자동 패스가 있었다
    /// 0.3.28 — 시간이 지나 **서버가 대신 놓은** 자리들(뷰가 작은 회색 점으로 구분해 그린다).
    /// **기본값이 있는 채로 맨 끝에 둔다** — 멤버와이즈 초기화를 쓰는 렌더·창 테스트가 그대로 컴파일돼야 한다.
    package var autoPoints: Set<GomokuPoint> = []
    /// 마지막 수가 자동으로 놓인 것인가(상태줄·툴팁이 "시간이 지나 자동으로 놓인 수"를 말할 근거).
    package var lastMoveWasAuto: Bool = false
    /// 자동 착수가 연속 3번 놓여 끝난 판인가. **저장 칸이 아니라 `endReason` 에서 파생된다**(0.3.28) —
    /// 열거값 `.abandoned` 가 들어오면서 사실의 출처가 하나로 합쳐졌고, 같은 사실을 두 칸에 들고 있으면
    /// 언젠가 둘이 갈린다. 부르는 쪽(결과 화면·코어 테스트)은 그대로 이 이름을 쓴다.
    package var endedByAbandon: Bool { endReason == .abandoned }
}

/// 로비 "지금 대결 중" 한 건. **판 내용을 들고 있지 않다** — 누구와 누가, 얼마를 걸고, 언제 시작했는지뿐이다.
/// 경과(m:ss)는 뷰의 잎(TimelineView)이 `startedAt` 으로 잰다 — 이 스토어는 초를 세지 않는다(팝오버 무효화 계약).
package nonisolated struct GomokuLiveMatch: Identifiable, Equatable, Sendable {
    package let id: String
    /// 서버가 uuid 로 고정한 좌우 순서 그대로다(조회마다 자리가 바뀌면 같은 판이 다른 판으로 보인다).
    package let a: GomokuUser
    package let b: GomokuUser
    package let stake: GomokuStake
    /// 기기 시계로 보정된 시작 시각(서버 `started_ms` = accepted_at).
    package let startedAt: Date
}

package nonisolated enum GomokuPhase: Equatable, Sendable { case lobby, playing, result }

/// 창이 안 보이는 사람에게 "지금 둘 차례"를 알리는 한 건(캐릭터 말풍선으로 간다 — CheckApp 배선).
/// 같은 (판 id, move_count) 에는 한 번만 만든다.
package nonisolated struct GomokuAttention: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        /// 판이 막 시작됐고 내가 먼저 둔다(흑).
        case matchStarted
        /// 상대가 뒀고 이제 내 차례다.
        case myTurn
    }

    package let kind: Kind
    package let matchID: String
    package let opponentName: String
    /// 이 알림을 만든 순간의 기록 수. 말풍선을 띄우기 직전 판이 이미 넘어갔는지 대조한다.
    package let moveCount: Int
}

// MARK: - 대국 채팅 (v0.3.28)

/// 빠른 문구 여덟. **코드는 서버와 나누고 한국어 문구는 앱만 갖는다** — 서버 `gomoku_chat_quick_codes()` 는
/// 같은 여덟 코드만 검사하고 표에 저장되는 것도 코드다. 그래서 문구를 다듬는 날 서버를 배포할 필요가 없다.
/// 반대로 서버가 코드를 넓히는 날 옛 앱은 그 코드를 모르는데, 그때 말이 사라지지 않게 받는 쪽에서
/// `GomokuNoticeText.chatUnknownQuick` 한 줄로 접는다(소실은 오배달보다 나쁘다).
package nonisolated enum GomokuQuickPhrase: String, CaseIterable, Sendable {
    case hi, gg, nice, hurry, sorry, think, oops, rematch

    package var text: String {
        switch self {
        case .hi: return "안녕하세요"
        case .gg: return "잘 뒀어요"
        case .nice: return "좋은 수네요"
        case .hurry: return "한 수 부탁해요"
        case .sorry: return "미안해요"
        case .think: return "생각 중이에요"
        case .oops: return "실수했어요"
        case .rematch: return "한 판 더 할까요?"
        }
    }
}

/// 대국 채팅 한 줄(화면 값). `seq` 가 곧 id 다 — 서버가 판마다 1부터 매기는 번호라 한 판 안에서 유일하고,
/// 판이 바뀌면 대화를 통째로 비우므로 판을 가로질러 겹칠 일이 없다.
package nonisolated struct GomokuChatMessage: Identifiable, Equatable, Sendable {
    package let seq: Int
    /// 서버가 판정한다(앱이 sender 를 내 id 와 대조하지 않는다 — 두 판정이 갈리면 내 말이 남의 말이 된다).
    package let isMine: Bool
    /// 기기 시계로 보정된 시각.
    package let sentAt: Date
    /// 빠른 문구면 그 코드, 자유 입력이면 nil.
    package let quick: GomokuQuickPhrase?
    /// 화면에 그대로 그리는 글(빠른 문구면 `quick.text`).
    package let body: String

    package var id: Int { seq }
}

// MARK: - 화면이 본 판 (v0.3.31 진단)

/// 판을 누른 **그 순간 화면이 그리고 있던** 판의 요약. 착수 판정은 언제나 스토어 값으로 하고, 이 값은 **로그에만** 쓴다.
///
/// 생긴 까닭(2026-09-17 재발): 사용자는 "화면은 내 차례였고 다른 칸엔 미리보기가 떴는데 한 영역만 안 놓였다"고 했고,
/// 같은 순간 스토어는 그 클릭을 `not-your-turn` 으로 거절했으며 서버도 상대 차례였다. 화면이 옛 판을 그렸는지(어긋남)
/// 차례를 잘못 읽었는지(착각) 가를 값이 없었다 — 탭마다 둘을 나란히 적어 다음 재발에서 가른다(`tap diverged`).
/// 화면에는 아무것도 띄우지 않는다(사용자 결정: 로그만).
package nonisolated struct GomokuSeenTurn: Equatable, Sendable {
    package let matchID: String
    package let moveCount: Int
    package let turn: GomokuColor?

    package init(_ match: GomokuMatchState) {
        matchID = match.id
        moveCount = match.moveCount
        turn = match.turn
    }

    /// 스토어 판과 다른가. 스토어에 판이 없으면 다르다.
    package func differs(from match: GomokuMatchState?) -> Bool {
        guard let match else { return true }
        return matchID != match.id || moveCount != match.moveCount || turn != match.turn
    }
}

// MARK: - 탭 거절 사유 (v0.3.28)

/// 판을 눌렀는데 돌이 안 놓인 **이유**. 여기서 갈라 두 곳으로 나간다: 사용자에게는 `GomokuNoticeText.tapRefusal(_:)`
/// 한 줄, 진단에는 `Logger` 한 줄(`tap refused reason=…`).
///
/// 이 열거값이 생긴 까닭: 0.3.27 까지 네 가지 거절(내 차례 아님 · 왕복 중이라 잠김 · 이미 돌이 있음 · 판이 끝남)이
/// 뷰와 스토어의 `guard` 한 줄씩에 뭉쳐 **전부 무음**이었다. 운영에서 사용자가 돌을 못 놓아 판돈을 잃었는데 앱이
/// 거부 사유를 하나도 말해 주지 않아 원인 규명이 며칠치 조사로 번졌다. 이제 이 한 줄이 갈래를 갈라 준다.
///
/// rawValue 는 **로그 어휘**다 — 사람 이름·판 내용과 무관한 고정 문자열이라 그대로 공개(.public)로 찍어도 된다.
package nonisolated enum GomokuTapRefusal: String, CaseIterable, Sendable {
    /// 상대 차례다.
    case notYourTurn = "not-your-turn"
    /// 앞 착수·기권이 아직 왕복 중이라 잠겨 있다(`isBusy`).
    case busy
    /// 이미 돌이 있는 자리다.
    case occupied
    /// 판이 끝났다.
    case finished
    /// 로그인이 풀렸다.
    case signedOut = "signed-out"
    /// 들고 있는 판이 없다. **말하지 않는다** — 판이 없으면 볼 화면도 없다(로그만 남는다).
    case noMatch = "no-match"
    /// 흑 금수다. 사유는 따로 싣는다.
    case forbidden
}

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라)

/// 오목 안내 한 줄의 **유일한 출처**. status → 문구 변환이 여러 곳에 흩어지면 같은 거절이 화면마다 다른 말을 한다.
/// 진단 어휘(서버·상태·동기화·토큰 등)는 쓰지 않는다 — 사용자가 할 수 있는 일을 말한다.
package nonisolated enum GomokuNoticeText {
    package static let tryAgain = "잠시 후 다시 시도해 주세요"
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    package static let updateMine = "앱을 업데이트해야 대결할 수 있어요"
    package static let signInAgain = "다시 로그인해 주세요"
    package static let notYourTurn = "상대 차례예요"
    package static let inviteTimedOut = "상대가 응답하지 않았어요"
    /// 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대국을 시작함 — 사용자에게는 모두 같은 뜻이다).
    package static let inviteDeclined = "상대가 신청을 받지 않았어요"
    /// 착수·기권을 눌렀는데 그 전에 시간이 넘어 판이 이미 끝났다.
    package static let timedOut = "시간이 지나 대국이 끝났어요"
    package static let finishedInvite = "이미 끝난 신청이에요"
    package static let finishedMatch = "이미 끝난 대국이에요"
    package static let cannotPlace = "둘 수 없는 자리예요"
    /// 앞 착수·기권이 아직 왕복 중이라 잠긴 동안 또 눌렀다. "기다려라"가 아니라 **지금 무슨 일이 일어나는지**를 말한다.
    package static let sending = "보내는 중이에요"
    /// 이미 돌이 있는 교차점을 눌렀다(내 돌이든 상대 돌이든 같은 말이다 — 사용자가 할 일은 다른 자리를 고르는 것뿐).
    package static let occupied = "이미 돌이 놓인 자리예요"
    package static let busy = "이미 진행 중인 대국이 있어요"
    package static let targetBusy = "상대가 다른 대국 중이에요"

    // 채팅(v0.3.28). 아래 셋은 **안내가 아니라 상태 표시**다 — 한 번 뜨고 마는 것이 아니라 그 조건이 참인 동안 서 있다.
    /// 내가 상대 말을 껐다(대화 자리에 선다).
    package static let chatMutedByMe = "상대 말을 껐어요"
    /// 상대가 껐다. **입력창 위에 계속 뜬다** — 사용자 요구가 "끄면 상대에게 티가 나게"였다.
    package static let chatMutedByOpponent = "상대가 채팅을 껐어요"
    /// 상대가 옛 버전이라 못 받는다. **조용히 삼키지 않는다** — 안 그러면 혼잣말을 대화로 착각한다.
    package static let chatOpponentOutdated = "상대는 옛 버전이라 채팅을 못 받아요"
    /// 앱이 모르는 빠른 문구 코드(서버가 표를 넓힌 날). 그 줄을 지우는 대신 이렇게 남긴다.
    package static let chatUnknownQuick = "앱을 업데이트하면 볼 수 있는 문구예요"
    /// 보낼 수 없는 글(못 쓰는 문자)과 도배를 **한 문장으로** 접는다. 숫자도 카운트다운도 두지 않는다.
    package static let chatBlocked = "지금은 채팅을 보낼 수 없어요. 잠시 후 다시 시도해 주세요"

    /// 길이 초과. 숫자는 **서버가 알려 준 상한이 있으면 그것**을 쓴다(둘이 갈리는 날 진실은 거절하는 쪽에 있다).
    package static func chatTooLong(_ maxLength: Int) -> String { "채팅은 \(maxLength)자까지예요" }

    // 자동 착수(v0.3.28). 시간이 지나면 **지는 게 아니라 서버가 대신 놓는다** — 그래서 문구도 '졌다'가 아니라 '놓였다'다.
    /// 내 차례가 시간 초과로 지나가 서버가 대신 놓았다(gomoku_move 의 auto_placed).
    package static let autoPlaced = "시간이 지나 자동으로 놓였어요"
    /// 판 위 회색 점 하나의 설명(툴팁·보이스오버).
    package static let autoPlacedStone = "시간이 지나 자동으로 놓인 수"

    /// 자동 착수 연속 경고. **한 번 남았을 때만** 말한다 — 첫 번째부터 겁을 주면 매 판 뜨고, 그러면 아무도 안 읽는다.
    /// 판을 잃는 횟수에서 파생시킨다: 리터럴을 따로 쓰면 값을 바꾼 날 문구만 옛 숫자로 남는다.
    ///
    /// `lossStreak` 의 기본값은 **폴백 상수**다. 서버가 로비로 말해 준 값을 따르려면 스토어의
    /// `autoStreakWarning`(인자 없는 계산 프로퍼티)을 읽어라 — 그쪽이 `autoAbandonStreak` 를 넘긴다.
    /// 기본값을 둔 이유는 한 인자로 부르는 자리(화면·렌더 테스트)가 그대로 컴파일되게 하기 위해서다.
    package static func autoStreakWarning(_ streak: Int, lossStreak: Int = GomokuStore.autoPlaceLossStreak) -> String? {
        guard streak == lossStreak - 1 else { return nil }
        return "한 번 더 놓치면 집니다"
    }

    /// 자리 비움으로 끝난 판의 결과 한 줄(연속 자동 착수). 이긴 쪽과 진 쪽이 다른 문장을 본다.
    package static func abandoned(outcome: GomokuOutcome?) -> String {
        outcome == .won ? "상대가 자리를 비웠어요" : "자리를 비워 졌어요"
    }

    /// 금수 사유별 문구. 상태줄과 호버 이유가 같은 말을 한다.
    package static func forbidden(_ reason: GomokuForbiddenReason) -> String {
        switch reason {
        case .doubleThree: return "3-3 금수라 둘 수 없어요"
        case .doubleFour: return "4-4 금수라 둘 수 없어요"
        case .overline: return "장목 금수라 둘 수 없어요"
        case .budget: return "판정할 수 없는 자리예요"
        }
    }

    /// 탭 거절 한 줄(v0.3.28). `nil` 이면 **말할 것이 없다** — `noMatch` 는 판이 없다는 뜻이라 볼 화면도 없다.
    /// 나머지는 전부 이미 있는 문구를 **다시 쓴다**: 같은 사실이 화면마다 다른 말을 하면 그게 곧 다음 조사거리다.
    package static func tapRefusal(_ refusal: GomokuTapRefusal, reason: GomokuForbiddenReason? = nil) -> String? {
        switch refusal {
        case .notYourTurn: return notYourTurn
        case .busy: return sending
        case .occupied: return occupied
        case .finished: return finishedMatch
        case .signedOut: return signInAgain
        case .noMatch: return nil
        case .forbidden: return reason.map(forbidden) ?? cannotPlace
        }
    }

    /// 신청(gomoku_challenge) 결과.
    ///
    /// v0.3.30 부터 서버는 `not_working`·`target_not_working` 을 **내지 않는다**(신청·수락의 근무 조건 삭제). 두 문구는
    /// db push 가 앱보다 늦은 창의 옛 서버가 그 status 를 줄 때만 쓰인다 — 클라가 먼저 근무를 보고 막는 선게이트로 되살리지 마라.
    package static func challenge(_ status: GomokuRPCStatus, need: Int? = nil, have: Int? = nil) -> String {
        switch status {
        case .ok: return "신청을 보냈어요"
        case .invalid: return "신청할 수 없는 상대예요"
        case .blackout: return "지금은 조용한 기간이라 신청할 수 없어요"
        case .notWorking: return "근무 중일 때만 신청할 수 있어요"
        case .targetNotWorking: return "상대가 근무 중이 아니에요"
        case .targetFocused: return "상대가 집중 모드라 신청할 수 없어요"
        case .targetOutdated: return "상대가 앱을 업데이트해야 해요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .alreadyPending: return "이미 보낸 신청이 있어요"
        case .insufficient: return CheckCoreShared.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    /// 신청 취소(gomoku_cancel) 결과.
    package static func cancel(_ status: GomokuRPCStatus) -> String {
        switch status {
        case .ok: return "신청을 취소했어요"
        case .notFound, .notPending, .expired: return finishedInvite
        default: return common(status)
        }
    }

    /// 수락·거절(gomoku_respond) 결과. 수락 성공은 판이 곧바로 열리므로 말하지 않는다(nil).
    package static func respond(
        accept: Bool, _ status: GomokuRPCStatus, side: String? = nil, need: Int? = nil, have: Int? = nil
    ) -> String? {
        switch status {
        case .ok: return accept ? nil : "신청을 거절했어요"
        case .notFound, .notPending: return finishedInvite
        case .expired: return "신청 시간이 지났어요"
        case .notWorking: return "근무 중일 때만 수락할 수 있어요"
        case .targetNotWorking: return "상대가 근무를 끝냈어요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .insufficient:
            if side == "challenger" { return "상대의 루비가 모자라요" }
            return CheckCoreShared.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    /// 착수(gomoku_move) 결과. 성공·판이 바뀐 경우(stale — 곧바로 다시 불러온다)는 말하지 않는다(nil).
    package static func move(_ status: GomokuRPCStatus, reason: String? = nil) -> String? {
        switch status {
        case .ok, .stale: return nil
        // 내 차례가 지나 서버가 대신 놓았다. 판은 함께 온 state 가 말하고, 이 줄은 **왜** 그렇게 됐는지를 말한다.
        case .autoPlaced: return autoPlaced
        case .forbidden:
            return GomokuForbiddenReason(serverReason: reason).map(forbidden) ?? cannotPlace
        case .timeout: return timedOut
        case .notYourTurn: return notYourTurn
        case .notActive, .notFound: return finishedMatch
        case .invalid: return cannotPlace
        default: return common(status)
        }
    }

    /// 기권(gomoku_resign) 결과. 성공은 결과 화면이 말한다(nil).
    /// 서버는 기권보다 시간 초과를 먼저 정산해 `timeout` + 끝난 판을 돌려준다 — 착수와 같은 말을 한다.
    package static func resign(_ status: GomokuRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .timeout: return timedOut
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 채팅 전송(gomoku_chat_send) 결과. **성공은 말하지 않는다**(nil) — 글이 그 자리에 뜨는 것이 곧 답이고,
    /// "보냈어요"를 띄우면 한 판에 스무 번 뜬다.
    ///
    /// `flood` 를 `invalid` 와 같은 줄로 접는 것이 계약이다: 남은 초를 세거나 버튼을 잠그면 그건 이름만 다른
    /// 쿨타임이고, 메시지에서 없앤 바로 그것이다.
    package static func chat(_ status: GomokuRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .invalid, .flood: return chatBlocked
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 음소거 전환(gomoku_chat_mute) 결과. 성공은 토글과 대화 자리의 한 줄이 이미 말한다(nil).
    package static func chatMute(_ status: GomokuRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .notFound, .notActive: return finishedMatch
        default: return common(status)
        }
    }

    private static func common(_ status: GomokuRPCStatus) -> String {
        switch status {
        case .unsupportedClient: return updateMine
        case .unauthorized: return signInAgain
        default: return tryAgain
        }
    }
}

// MARK: - 스토어

@MainActor
@Observable
package final class GomokuStore {
    /// 상대 차례의 대국 상태 안전망 조회 주기(초) — 실시간 구독 중.
    package nonisolated static let statePollSecondsWhileSubscribed: TimeInterval = 3
    /// 같은 조회 — 미구독(킬스위치·재연결 중). 신호가 없으니 더 촘촘하다.
    package nonisolated static let statePollSecondsUnsubscribed: TimeInterval = 1.5
    /// 내 대기 신청이 있을 때 받은 쪽의 응답을 보는 주기(초).
    package nonisolated static let outgoingInboxPollSeconds: TimeInterval = 5
    /// 로비 목록 재조회 주기(초). 창을 열 때 한 번 + 로비를 보고 있는 동안 이 주기.
    package nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 팝오버를 열 때 받은 신청을 보는 스로틀(초). 팀 메타 재조회와 같은 눈금이다.
    package nonisolated static let menuInboxThrottleSeconds: TimeInterval = 60
    /// 연속 자동 착수 몇 번에 판을 잃는가의 **폴백**. 서버가 로비 응답 `auto_abandon_streak` 로 말해 주면
    /// 인스턴스의 `autoAbandonStreak` 가 그 값을 든다 — 규칙의 주인은 서버이고, 바뀌는 날 앱이 따라가야 한다.
    /// 이 상수는 아직 로비를 못 받은 창에서 쓰는 기본값이자 문구의 기본 임계값이다.
    package nonisolated static let autoPlaceLossStreak = 3
    /// 서버가 턴 제한에 더하는 네트워크 유예(초). 서버 `gomoku_turn_grace_seconds()` 와 같은 값 — 표시 마감이 이만큼
    /// 지나도 결과가 안 왔으면 내 차례여도 한 번 물어본다(서버는 누가 부르든 시간 초과를 먼저 정산한다).
    package nonisolated static let turnGraceSeconds: TimeInterval = 2
    /// 창 열기(openWindow)와 창 표시(windowDidShow)가 같은 조회를 두 번 쏘지 않게 하는 간격(초).
    package nonisolated static let reloadDedupeSeconds: TimeInterval = 1
    /// 서버 시계 오프셋을 다시 재는 문턱(초). 응답마다 왕복 지연이 몇 ms 씩 달라지는데, 그때마다 오프셋을 갈면
    /// 같은 신청의 만료·같은 차례의 마감이 응답마다 다른 값이 되어 팝오버·창 루트가 헛되이 다시 그려진다.
    package nonisolated static let serverClockToleranceSeconds: TimeInterval = 0.25
    /// 같은 신청(id·판돈·상대가 같음)을 다시 읽었을 때 만료 시각이 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    package nonisolated static let inviteExpiryToleranceSeconds: TimeInterval = 1
    /// 같은 차례(기록 수·차례가 같음)를 다시 읽었을 때 마감이 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    package nonisolated static let deadlineToleranceSeconds: TimeInterval = 0.5

    package nonisolated static let logger = Logger(subsystem: "kingcheck", category: "gomoku")

    /// 네트워크·세션·루비 미러를 빌리는 곳. **약참조다** — WorkTimerStore 가 이 스토어를 소유한다.
    /// nil 이면 미리보기·렌더 테스트용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any GomokuStoreHost)?

    package init(host: (any GomokuStoreHost)? = nil) {
        self.host = host
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다(저장 프로퍼티를 다 채우기 전에는 self 를 넘길 수 없다).
    package func attach(host: any GomokuStoreHost) {
        self.host = host
    }

    // MARK: 화면 상태 — 전부 internal set(렌더 테스트가 직접 채운다)

    package var phase: GomokuPhase = .lobby
    package var users: [GomokuUser] = []
    package var record: GomokuRecord?
    package var selectedStake: GomokuStake = .three
    package var incoming: [GomokuInvite] = []
    package var outgoing: GomokuInvite?
    package var match: GomokuMatchState? {
        // 수·차례·끝남이 바뀔 때만 한 줄 남긴다(v0.3.31 진단 — `GomokuSeenTurn` 주석). 같은 값을 다시 넣는 되맞춤은 조용하다.
        didSet {
            if let line = Self.matchTransitionLine(from: oldValue, to: match) { Self.logger.notice("\(line, privacy: .public)") }
        }
    }
    /// 탭 순간 화면이 본 판과 스토어 판이 달랐던 횟수(진단·테스트 지점). 화면을 다시 그리게 하지 않도록 관찰에서 뺀다.
    @ObservationIgnored package private(set) var tapDivergenceCount = 0
    /// 사용자 어휘 안내 한 줄.
    package var notice: String?
    package var isBusy = false
    package var isWindowVisible = false
    package var isRulesVisible = false
    /// 서버 응답으로만 갱신(host 에도 반영).
    package var rubyBalance: Int?
    /// 한 수 제한(초). 서버 로비 응답이 말해 주면 그 값, 아니면 설계값 30.
    package var turnSeconds = 30
    /// 마지막 상대 목록 조회가 실패했다. 빈 목록을 "상대가 없다"로 보여 주지 않기 위한 값이다.
    package var lobbyLoadFailed = false
    /// 이번 로그인에서 상대 목록을 한 번이라도 받았다.
    package var hasLoadedLobby = false

    /// 로비 "지금 대결 중" 목록(0.3.28). **서버 순서를 그대로 쓴다**(accepted_at desc) — 클라가 다시 정렬하면
    /// 스토어 정렬과 뷰 정렬이 갈리고, 그때 같은 목록이 화면마다 다른 순서로 보인다(users 가 겪은 그것).
    /// 옛 서버(키 없음)면 빈 배열이고 화면은 "지금 대결 중인 사람이 없어요"로 접힌다.
    package var liveMatches: [GomokuLiveMatch] = []

    // MARK: 자동 착수 (v0.3.28) — 시간 초과는 패배가 아니라 **무작위 대리 착수**다

    /// 내가 **연속으로** 자동 착수당한 횟수. 직접 한 수라도 두면 0으로 돌아간다.
    /// `autoPlaceLossStreak` 에 닿으면 그 판을 잃는다(서버가 `abandoned` 로 끝낸다).
    package var myAutoStreak = 0
    package var opponentAutoStreak = 0
    /// 판을 잃는 연속 횟수. **서버가 말한 값**(로비 `auto_abandon_streak`)이고, 아직 못 받았으면 폴백이다.
    package var autoAbandonStreak = GomokuStore.autoPlaceLossStreak

    /// 지금 내 연속 횟수에 대한 경고 한 줄(없으면 nil). **서버가 말한 임계값으로 판정한다** —
    /// 화면이 이 값을 읽으면 서버가 규칙을 바꾸는 날 따라가고, 문구 표를 직접 부르면 폴백 숫자에 묶인다.
    package var autoStreakWarning: String? {
        GomokuNoticeText.autoStreakWarning(myAutoStreak, lossStreak: autoAbandonStreak)
    }

    // MARK: 채팅 상태 (v0.3.28) — **`isBusy` 를 쓰지 않는다**

    /// 지금 판의 대화(오래된 것 → 최신). 판이 바뀌면 비운다.
    package var chat: [GomokuChatMessage] = []
    /// 판의 채팅 발급 번호 = **다음 요청의 since**. 서버가 말한 값이고 역행하지 않는다.
    /// 마지막 줄의 seq 가 아닌 이유: 내가 음소거하면 상대 줄이 빠져 둘이 갈리고, 줄 번호로 물으면
    /// 가려진 구간을 영원히 다시 묻는다.
    package var chatSeq = 0
    /// **내가** 이 판 채팅을 껐다. 서버가 아는 판 상태다(내 화면 설정이 아니다) — 그래야 상대에게 티가 난다.
    package var isMuted = false
    /// **상대가** 껐다. 티내기의 근거 — 이 값이 참인 동안 입력창 위에 한 줄이 서 있다.
    package var isOpponentMuted = false
    /// 상대 앱이 채팅을 받을 수 있는 버전인가(서버 `chat_capable`).
    /// **모르면 받을 수 있다고 본다** — 아직 안 물어본 판에서 "상대는 옛 버전"이라 말하면 그건 거짓말이다.
    package var opponentChatCapable = true
    /// 입력칸의 글. 비우는 자리는 **전송 성공**과 판이 바뀔 때 둘뿐이다(실패해도 남는다 — 쓴 말은 사용자 것이다).
    package var chatDraft = ""
    /// 채팅 전용 안내 한 줄(실패만). 성공은 글이 뜨는 것으로 답한다.
    package var chatNotice: String?
    /// **`isBusy` 와 별개다.** 채팅 왕복이 착수·기권 버튼을 잠그면 한 수 30초짜리 판에서 그건 곧 패배다.
    package var isSendingChat = false
    /// 한 줄 상한. 서버가 `chat_max_len` 을 말해 주면 그 값으로 간다.
    package var chatMaxLength = GomokuChatBody.maxLength

    /// 지금 입력칸에 있는 글의 길이(코드포인트 — 서버 `char_length` 와 같은 눈금).
    package var chatDraftLength: Int { GomokuChatBody.length(chatDraft) }

    /// 지금 채팅을 보낼 수 있는가.
    ///
    /// **시계를 읽지 않는다.** 끝난 판의 인사 유예(120초)는 서버가 재고, 여기서 `Date()` 를 읽으면 입력칸이
    /// 초마다 다시 그려진다(`bannerInvite` 가 세운 규약 그대로다). 유예가 지난 판의 전송은 서버가
    /// `not_active` 로 답하고 그 문구가 사정을 말한다.
    /// 음소거·상대 버전도 여기서 잠그지 않는다 — 껐어도 내 말은 가고(상대 화면에 안 보일 뿐),
    /// 옛 버전 상대에게도 **왜 안 보이는지를 말해 주는 것**이 잠그는 것보다 낫다.
    package var canSendChatNow: Bool {
        guard !isSendingChat, match != nil else { return false }
        if case .ok = GomokuChatBody.validate(chatDraft, maxLength: chatMaxLength) { return true }
        return false
    }

    /// 만료되지 않은 받은 신청 전부(만료가 이른 것부터, v0.3.30 — M2 의 근무 밖 신청 배너·메뉴바 점이 읽는다).
    ///
    /// **시계를 읽지 않는다**(`bannerInvite` 와 같은 규약) — 만료된 신청은 스토어가 **만료 시각에 타이머로**
    /// `incoming` 에서 걷어낸다(`scheduleInviteExpiry` → `pruneExpiredInvites`). 관찰 갱신은 시간 흐름만으로는 일어나지 않으므로,
    /// 여기서 `Date()` 로 거르면 값은 맞아도 그 값을 그린 메뉴바 점은 다음 무관한 갱신까지 켜진 채로 남는다.
    package var pendingIncomingInvites: [GomokuInvite] {
        incoming.sorted { lhs, rhs in
            lhs.expiresAt != rhs.expiresAt ? lhs.expiresAt < rhs.expiresAt : lhs.id < rhs.id
        }
    }

    /// 팝오버 배너·말풍선이 쓰는 대표 신청(만료 안 된 받은 신청 중 가장 오래된 것).
    /// **시계를 읽지 않는다** — 만료된 신청은 스토어가 만료 시각에 `incoming` 에서 걷어낸다(pruneExpiredInvites).
    /// 여기서 Date() 를 읽으면 배너 body 가 시각 판정을 하게 되어 팝오버 전체가 시계에 묶인다.
    package var bannerInvite: GomokuInvite? {
        incoming.reduce(nil) { best, invite in
            guard let best else { return invite }
            return invite.expiresAt < best.expiresAt ? invite : best
        }
    }

    // MARK: UI 트랙이 CheckApp 에서 물리는 문

    /// 창 띄우기(컨트롤러 show).
    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    /// 새 받은 신청(처음 본 id 한 번).
    @ObservationIgnored package var onInviteArrived: (@MainActor (GomokuInvite) -> Void)?
    /// 창 닫기(컨트롤러 close). reset() 이 부른다 — 로그아웃한 뒤 앞 계정의 판이 떠 있으면 안 된다.
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    /// 판이 막 시작됐다 — 앱이 앞에 없으면 사용자의 주의를 끈다(CheckApp 이 NSApp.requestUserAttention 으로 잇는다).
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    /// 창이 안 보이는 동안 차례가 나에게 왔다(같은 판 id·기록 수에 한 번). CheckApp 이 캐릭터 말풍선으로 잇는다.
    @ObservationIgnored package var onAttention: (@MainActor (GomokuAttention) -> Void)?

    // MARK: 내부 장부 (관찰 대상 아님)

    /// 이 스토어의 '지금'. 테스트가 갈아 끼운다.
    @ObservationIgnored package var clock: () -> Date = { Date() }
    /// 폴링 루프의 한 걸음(초). 주기 판정은 pollTick 이 하고, 이 값은 그 판정을 얼마나 자주 묻는지다.
    @ObservationIgnored package var pollStepSeconds: TimeInterval = 0.5
    /// 서버 시계 − 기기 시계(초). server_now_ms 가 올 때마다 갱신한다.
    @ObservationIgnored package private(set) var serverClockOffset: TimeInterval = 0
    /// 오프셋을 한 번이라도 쟀는가(처음 잰 값은 문턱과 무관하게 받는다).
    @ObservationIgnored private var hasServerClockOffset = false
    @ObservationIgnored package private(set) var resetGeneration = 0
    /// 창이 다른 창에 완전히 가려졌거나 다른 Space·잠금 화면에 있다(창 컨트롤러의 가림 통지).
    /// **폴링만** 이 값을 본다 — 시계 잎 뷰·말풍선 판정은 `isWindowVisible` 그대로다(가림 통지가 틀려도 보이는 창의 시계는 돈다).
    @ObservationIgnored package private(set) var isWindowOccluded = false
    /// 지금 조회 중인 판 id 와, 그 사이 다른 판으로 들어온 조회 요청(마지막 것 하나).
    @ObservationIgnored package private(set) var stateInFlightID: String?
    @ObservationIgnored private var pendingStateID: String?
    /// 마지막으로 "내 차례가 왔다"를 본 (판 id#기록 수). 같은 차례에 말풍선이 두 번 뜨지 않게 한다.
    @ObservationIgnored private var attentionKey: String?
    /// 결과 화면을 한 번이라도 세운 끝난 판(받은함 last_finished 로 같은 결과를 다시 세우지 않는다).
    @ObservationIgnored package private(set) var shownResultIDs: Set<String> = []
    /// 보낸 신청을 이 기기에서 새로 세울 때마다 오른다. 그보다 **먼저** 나간 받은함 응답이 방금 보낸 신청을 지우지 않게 한다.
    @ObservationIgnored private var outgoingRevision = 0
    @ObservationIgnored private var inboxRequestOutgoingRevision = 0
    /// 서버가 말한 내 진행 중 대국 id(로비·인박스·상태 응답).
    @ObservationIgnored package private(set) var activeMatchID: String?
    /// onInviteArrived 를 이미 부른 받은 신청 id.
    @ObservationIgnored package private(set) var seenInviteIDs: Set<String> = []
    /// [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태 응답이 사용자를 결과 화면으로 끌고 가지 않게 한다.
    @ObservationIgnored package private(set) var dismissedMatchIDs: Set<String> = []
    /// 이 기기에서 이미 "나갔다"고 서버에 말한 판. 멱등이지만 **판마다 한 번만** 부르기 위한 장부다.
    @ObservationIgnored package private(set) var leftMatchIDs: Set<String> = []
    @ObservationIgnored package private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollToken = 0
    @ObservationIgnored package private(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncPendingTrailing = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var stateInFlight = false
    @ObservationIgnored private var stateAgain = false
    @ObservationIgnored private var inboxInFlight = false
    @ObservationIgnored private var inboxAgain = false
    @ObservationIgnored private var lobbyInFlight = false
    @ObservationIgnored package var lastStateRequestAt: Date = .distantPast
    @ObservationIgnored package var lastInboxRequestAt: Date = .distantPast
    @ObservationIgnored package var lastLobbyRequestAt: Date = .distantPast
    @ObservationIgnored private var lastMenuInboxAt: Date = .distantPast
    @ObservationIgnored private var inviteTTLSeconds: TimeInterval = 60
    /// 지금 들고 있는 대화가 **어느 판의 것인가**. 다른 판의 상태가 오면 이 값이 달라 대화를 비운다.
    @ObservationIgnored package private(set) var chatMatchID: String?
    /// 채팅을 **처음부터 다시 받아야 한다**: 기록에 구멍이 났다 · 음소거가 뒤집혔다(가려지는 줄의 집합이 달라진다).
    /// 다음 조회 한 번을 `since_chat_seq = 0` 으로 띄운다(착수 needsFull 과 같은 규칙). 내리는 것은 **그 전체를
    /// 실어 온 응답**이다 — 요청을 띄울 때 내리면 실패하거나 버린 응답에 표시가 사라져 구멍이 그대로 남는다.
    @ObservationIgnored private var chatWantsFull = false
    /// 음소거 토글마다 오른다. 토글 **전에** 나간 조회의 응답을 통째로 버리기 위한 세대다
    /// (`resetGeneration`·`outgoingRevision` 과 같은 결의 방어).
    ///
    /// 기준선(`chatSeq`)을 0 으로 내려 막으려 들면 안 된다: 0 밑으로는 어떤 옛 스냅숏도 역행이 아니라
    /// (`serverSeq >= 0`) 늦은 응답이 방금 누른 값을 되감고, 줄은 한 줄도 안 담긴 채 번호만 서버 값으로 되올라
    /// 다음 회차가 그 뒤만 물어 가려졌던 줄이 그 판 내내 안 돌아온다.
    @ObservationIgnored package private(set) var chatGeneration = 0
    @ObservationIgnored private var lastOpponent: GomokuUser?
    @ObservationIgnored private var lastStake: Int?

    // MARK: - 창

    /// 상태 로드 시작 + presentWindow?().
    ///
    /// `focusMatchID` 는 말풍선·배너에서 온 경로의 대상이다. 받은 신청이면 로비의 받은 신청 카드가 그것을 보여 주고,
    /// 대국이면 그 판을 불러온다.
    package func openWindow(focusMatchID: String?) {
        if host?.session != nil {
            let focus = focusMatchID?.lowercased()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다(Task 는 아직 안 돌았다).
            let now = clock()
            lastLobbyRequestAt = now
            lastInboxRequestAt = now
            Task { [weak self] in await self?.refreshLobby() }
            Task { [weak self] in
                guard let self else { return }
                await self.loadInbox()
                if let focus, focus != self.match?.id, !self.incoming.contains(where: { $0.id == focus }) {
                    await self.refreshMatch(id: focus)
                } else if let current = self.match, !current.isFinished {
                    await self.refreshMatch(id: current.id)
                }
            }
        }
        presentWindow?()
    }

    /// 창이 실제로 보이기 시작했다(컨트롤러가 부른다). 폴링 시작·로비/인박스 재조회.
    package func windowDidShow() {
        if !isWindowVisible { isWindowVisible = true }
        // 막 앞으로 올라온 창이다. 숨기기 전의 가림 기록이 남아 폴링을 영영 막지 않게 지운다(가려지면 통지가 다시 온다).
        isWindowOccluded = false
        startPolling()
        guard host?.session != nil else { return }
        let now = clock()
        if now.timeIntervalSince(lastLobbyRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.refreshLobby() }
        }
        if now.timeIntervalSince(lastInboxRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.loadInbox() }
        }
    }

    /// 창이 가려졌다·닫혔다. 폴링만 멈춘다 — **대국은 계속된다**(시간은 서버에서 흐른다).
    package func windowDidHide() {
        if isWindowVisible { isWindowVisible = false }
        isWindowOccluded = false
        stopPolling()
        // 결과 화면인 채로 창을 닫았다 = 그 판에서 나간 것이다. **진행 중이면 부르지 않는다**(창을 닫아도 대국은
        // 계속된다). 가려짐은 나간 게 아니므로 `windowOcclusionDidChange` 는 이 문을 지나지 않는다.
        if let current = match, current.isFinished { leaveMatch(current.id) }
    }

    /// 창의 가림 상태가 바뀌었다(다른 창 뒤·다른 Space·잠금 화면). **폴링만** 멈추고 되살린다.
    /// `isWindowVisible` 은 건드리지 않는다 — 가림 통지가 틀려도 보이는 창의 시계가 멈추면 안 된다.
    /// 실시간 신호(handleSignal)는 이 값과 무관하게 계속 받는다.
    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible {
            startPolling()
        } else {
            stopPolling()
        }
    }

    // MARK: - 조회

    package func refreshLobby() async {
        guard host?.session != nil, !lobbyInFlight else { return }
        lobbyInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { lobbyInFlight = false } }
        lastLobbyRequestAt = clock()
        guard let result = await perform({ try await $0.gomokuLobby(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            applyLobby(response)
        case .failure:
            Self.logger.notice("lobby request failed")
            // 빈 목록을 "대결할 사람이 없다"로 믿게 하지 않는다 — 화면이 연결 안내와 [다시 불러오기]를 그린다.
            if !lobbyLoadFailed { lobbyLoadFailed = true }
        }
    }

    package func applyLobby(_ response: GomokuLobbyResponse) {
        guard response.status == .ok else {
            Self.logger.notice("lobby refused status=\(response.status.rawValue, privacy: .public)")
            if response.status == .unsupportedClient { setNotice(GomokuNoticeText.updateMine) }
            return
        }
        noteServerNow(response.serverNowMs)
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if !hasLoadedLobby { hasLoadedLobby = true }
        if let seconds = response.turnSeconds, seconds > 0, turnSeconds != seconds { turnSeconds = seconds }
        // 1 이하는 받지 않는다 — 임계값이 1이면 경고 조건(streak == 0)이 판 시작부터 참이 되어 매 판 뜬다.
        if let streak = response.autoAbandonStreak, streak > 1, autoAbandonStreak != streak {
            autoAbandonStreak = streak
        }
        if let ttl = response.inviteTtlSeconds, ttl > 0 { inviteTTLSeconds = TimeInterval(ttl) }
        if let me = response.me {
            applyRuby(me.rubyBalance)
            let newRecord = GomokuRecord(wins: me.wins ?? 0, losses: me.losses ?? 0, draws: me.draws ?? 0)
            if record != newRecord { record = newRecord }
            activeMatchID = me.activeMatchId?.lowercased()
        }
        if let rows = response.users {
            let mapped = Self.sortedForLobby(rows.compactMap(Self.user(from:)))
            if users != mapped { users = mapped }
        }
        // **서버 순서 그대로**(accepted_at desc) — 여기서 다시 정렬하지 마라. 키가 아예 없으면(옛 서버)
        // 들고 있던 목록을 지우지 않는다: 조회 실패와 같은 규약이다(빈 목록을 사실로 보여 주지 않는다).
        if let rows = response.matches {
            let live = rows.compactMap(liveMatch(from:))
            if liveMatches != live { liveMatches = live }
        }
        if let active = activeMatchID, match?.id != active {
            Task { [weak self] in await self?.refreshMatch(id: active) }
        }
    }

    /// 받은·보낸 신청과 진행 중 대국 id 를 읽는다. 도는 중에 또 불리면 **뒤따르는 한 번으로 합친다** —
    /// 버리면 조회가 나간 뒤 도착한 신호(신청·수락)가 다음 계기까지 화면에 안 온다.
    package func loadInbox() async {
        guard host?.session != nil else { return }
        if inboxInFlight {
            inboxAgain = true
            return
        }
        inboxInFlight = true
        let generation = resetGeneration
        repeat {
            inboxAgain = false
            lastInboxRequestAt = clock()
            inboxRequestOutgoingRevision = outgoingRevision
            let result = await perform({ try await $0.gomokuInbox(accessToken: $1) })
            guard generation == resetGeneration else { return }
            switch result {
            case .success(let response)?:
                await applyInbox(response)
                guard generation == resetGeneration else { return }
            case .failure?:
                Self.logger.notice("inbox request failed")
            case nil:
                break
            }
        } while inboxAgain
        inboxInFlight = false
    }

    package func applyInbox(_ response: GomokuInboxResponse) async {
        guard response.status == .ok else {
            Self.logger.notice("inbox refused status=\(response.status.rawValue, privacy: .public)")
            if response.status == .unsupportedClient { setNotice(GomokuNoticeText.updateMine) }
            return
        }
        noteServerNow(response.serverNowMs)
        applyRuby(response.rubyBalance)
        let now = clock()
        let previousIncoming = incoming
        let received = (response.incoming ?? [])
            .compactMap { row in invite(from: row, peerRow: row.challenger, fallbackPeer: nil) }
            .filter { $0.expiresAt > now }
            .map { fresh in Self.steadyInvite(fresh, previous: previousIncoming.first { $0.id == fresh.id }) }
        if incoming != received { incoming = received }
        let previousOutgoing = outgoing
        let active = response.activeMatchId?.lowercased()
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        let predatesOutgoing = inboxRequestOutgoingRevision < outgoingRevision
        var sent = response.outgoing
            .flatMap { row in
                invite(from: row, peerRow: row.opponent,
                       fallbackPeer: outgoing?.id == row.matchId?.lowercased() ? outgoing?.peer : nil)
            }
            .flatMap { $0.expiresAt > now ? $0 : nil }
            .map { fresh in Self.steadyInvite(fresh, previous: previousOutgoing) }
        if sent == nil, predatesOutgoing { sent = previousOutgoing }
        if outgoing != sent { outgoing = sent }
        // 진행 중 대국이 있으면 거절 안내를 하지 않는다 — 내가 다른 신청을 수락해 서버가 보낸 신청을 거둔 것이지 상대가 거절한 게 아니다
        // (수락 전에 나간 받은함이 옛 보낸 신청을 되살렸다가 다음 받은함에서 사라지는 경로 포함).
        let inMatch = active != nil || match.map { !$0.isFinished } == true
        if let gone = previousOutgoing, sent?.id != gone.id, gone.id != active, !predatesOutgoing, !inMatch {
            // 보낸 신청이 받은함에서 사라졌고 판으로 이어지지도 않았다 = 거절·취소(상대가 다른 대국을 시작해 서버가
            // 거둔 경우 포함). 만료 시각이 지났으면 만료 안내와 같은 말을 한다(두 안내가 겹치지 않게).
            setNotice(gone.expiresAt > now ? GomokuNoticeText.inviteDeclined : GomokuNoticeText.inviteTimedOut)
        }
        announceNewInvites()
        scheduleInviteExpiry()

        activeMatchID = active
        if let active {
            if match?.id != active || match?.isFinished == true {
                await refreshMatch(id: active)
            }
        } else if let current = match, !current.isFinished {
            // 로컬은 진행 중인데 서버엔 진행 중 대국이 없다 = 그 사이 끝났다. 결과를 받아 온다.
            await refreshMatch(id: current.id)
        } else if match == nil, phase == .lobby,
                  let finished = response.lastFinished?.matchId?.lowercased(), !finished.isEmpty,
                  !dismissedMatchIDs.contains(finished), !shownResultIDs.contains(finished) {
            // 앱을 다시 켜는 사이 끝난 판(최근 10분)의 결과를 한 번 세운다. 창이 안 보이면 다음에 열 때 보인다.
            shownResultIDs.insert(finished)
            await refreshMatch(id: finished)
        }
    }

    /// 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 깨우지 않게).
    package nonisolated static func steadyInvite(_ fresh: GomokuInvite, previous: GomokuInvite?) -> GomokuInvite {
        guard let previous, previous.id == fresh.id, previous.stake == fresh.stake, previous.peer == fresh.peer,
              abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) < inviteExpiryToleranceSeconds
        else { return fresh }
        return previous
    }

    /// 지금 대국(없으면 서버가 말한 진행 중 대국)을 다시 읽는다.
    package func refreshMatch() async {
        await refreshMatch(id: match?.id ?? activeMatchID)
    }

    /// 한 판의 상태를 읽는다. 같은 판을 들고 있으면 `since_seq` 로 **새 수만** 받고, 기록이 이어지지 않으면
    /// 처음부터 한 번 더 받는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다(loadInbox 와 같은 이유).
    ///
    /// 도는 중에 **다른 판** id 가 들어오면 합치지 않고 기억했다가 지금 판이 끝난 뒤 그 판을 한 번 읽는다 —
    /// 합치면 뒤따르는 반복이 앞 판만 다시 읽어, 막 수락된 판이 다음 계기까지 화면에 안 온다.
    package func refreshMatch(id rawID: String?) async {
        guard let requested = rawID?.lowercased(), !requested.isEmpty, host?.session != nil else { return }
        if stateInFlight {
            if requested == stateInFlightID {
                stateAgain = true
            } else {
                pendingStateID = requested
            }
            return
        }
        stateInFlight = true
        let generation = resetGeneration
        var nextID: String? = requested
        while let id = nextID {
            nextID = nil
            stateInFlightID = id
            var forceFull = false
            var forceChatFull = false
            repeat {
                stateAgain = false
                let since = (!forceFull && match?.id == id) ? (match?.moveCount ?? 0) : 0
                // 전체 재요청 표시는 **요청을 띄울 때 본다**(내리는 것은 그것을 실어 온 응답이다). 음소거 토글·
                // 다른 기기의 변경이 세운 표시가 이 요청에 실려야 가려졌던 줄이 이번 회차에 돌아온다.
                let wantsChatFull = forceChatFull || chatWantsFull
                let sinceChat = (!wantsChatFull && chatMatchID == id) ? chatSeq : 0
                let requestChatGeneration = chatGeneration
                lastStateRequestAt = clock()
                let result = await perform({
                    try await $0.gomokuState(accessToken: $1, matchID: id, sinceSeq: since, sinceChatSeq: sinceChat)
                })
                guard generation == resetGeneration else { return }
                forceFull = false
                forceChatFull = false
                guard case .success(let response)? = result else { continue }
                switch response.status {
                case .ok:
                    let outcome = applyState(
                        response.state, requestedSince: since, requestedSinceChat: sinceChat,
                        chatGeneration: requestChatGeneration
                    )
                    if outcome == .needsFull, since > 0 {
                        forceFull = true
                        stateAgain = true
                    }
                    // 채팅 구멍·음소거 뒤집힘은 착수와 **따로** 센다. 하나로 묶으면 수가 한 건도 없는 판(since 0)에서
                    // 재요청이 아예 안 걸리고, 반대로 대화만 이가 빠진 응답에 판 전체를 다시 받는다.
                    // 표시는 전체를 실어 온 응답이 내린다 — 그래서 되묻기가 고리를 만들지 않는다(재요청은 since 0 이다).
                    if chatWantsFull, sinceChat > 0 {
                        forceChatFull = true
                        stateAgain = true
                    }
                case .notFound:
                    if match?.id == id { clearMatch() }
                    if activeMatchID == id { activeMatchID = nil }
                case .unsupportedClient:
                    setNotice(GomokuNoticeText.updateMine)
                default:
                    Self.logger.notice("state refused status=\(response.status.rawValue, privacy: .public)")
                }
            } while stateAgain
            if let pending = pendingStateID {
                pendingStateID = nil
                nextID = pending
            }
        }
        stateInFlightID = nil
        stateInFlight = false
    }

    package enum StateApplyOutcome: Equatable { case applied, needsFull, ignored }

    /// 서버 상태 묶음을 화면 상태로 옮긴다.
    ///
    /// 판은 수 기록에서 다시 쌓는다(서버가 board 문자열을 실어 주면 그것이 권위다). 기록이 이어지지 않으면
    /// (`seq` 가 비었거나 서버 move_count 와 안 맞으면) `.needsFull` 을 돌려 처음부터 다시 받게 한다 —
    /// 구멍 난 판을 그리면 이미 돌이 있는 자리를 비어 있다고 보여 준다. 처음부터 받은 응답(`requestedSince == 0`)도
    /// 안 맞으면 그 판은 있는 그대로 반영한다(차례·결과는 서버 행이 말하므로 결과 화면이 막히지 않는다).
    @discardableResult
    package func applyState(
        _ payload: GomokuStatePayload, requestedSince: Int = 0, requestedSinceChat: Int = 0,
        chatGeneration: Int? = nil, blackPassedHint: Bool? = nil
    ) -> StateApplyOutcome {
        guard let row = payload.match, let id = row.id?.lowercased(), !id.isEmpty else { return .ignored }
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)
        let status = row.status ?? ""
        guard status == "active" || status == "finished" else {
            // 아직 시작 전(pending)이거나 시작하지 못하고 끝난 신청(declined·cancelled·expired)이다 — 판이 아니다.
            if match?.id == id { clearMatch() }
            if activeMatchID == id { activeMatchID = nil }
            return .applied
        }
        let isFinished = status == "finished"
        if isFinished, dismissedMatchIDs.contains(id), match?.id != id { return .ignored }

        let myID = host?.session?.userID.lowercased()
        var myColor = GomokuColor(rawValue: payload.myColor ?? "")
        if myColor == nil, let myID {
            if row.black?.lowercased() == myID { myColor = .black }
            else if row.white?.lowercased() == myID { myColor = .white }
        }
        guard let myColor else { return .ignored }

        let base = match?.id == id ? match : nil
        // 같은 판을 진행 중으로 들고 있는데 기록 수가 **줄어든** 응답은 착수보다 먼저 읽힌 옛 스냅숏이 늦게 온 것이다
        // (조회 → 착수 → 착수 응답 → 조회 응답 순서). 그대로 옮기면 방금 둔 돌이 사라지고 차례·마감이 한 수 전으로 돌아간다.
        // 판을 끝낸 응답은 예외다 — 끝남은 되돌릴 수 없는 사실이라 순서와 무관하게 받는다.
        if let base, !base.isFinished, !isFinished, let serverCount = row.moveCount, serverCount < base.moveCount {
            return .ignored
        }
        let tolerateGaps = requestedSince == 0
        // `auto` 가 없는 응답(옛 서버)은 **사람이 둔 수**로 읽는다 — 모른다고 회색 점을 찍으면 판 전체가 거짓말이 된다.
        let records: [(seq: Int, color: GomokuColor, point: GomokuPoint?, auto: Bool)] = (payload.moves ?? [])
            .compactMap { move in
                guard let seq = move.seq, let color = GomokuColor(rawValue: move.color ?? "") else { return nil }
                let auto = move.auto ?? false
                if move.kind == "pass" || move.x == nil || move.y == nil { return (seq, color, nil, auto) }
                guard let point = GomokuPoint(x: move.x ?? -1, y: move.y ?? -1) else { return nil }
                return (seq, color, point, auto)
            }
            .sorted { $0.seq < $1.seq }

        var board: GomokuBoard
        var lastMove: GomokuPoint?
        var appliedCount: Int
        var lastRecordIsBlackPass: Bool?
        var autoPoints: Set<GomokuPoint>
        var lastMoveWasAuto: Bool
        let rebuild = base == nil || records.first?.seq == 1
        if rebuild {
            board = GomokuBoard()
            lastMove = nil
            appliedCount = 0
            autoPoints = []
            lastMoveWasAuto = false
        } else {
            board = base?.board ?? GomokuBoard()
            lastMove = base?.lastMove
            appliedCount = base?.moveCount ?? 0
            autoPoints = base?.autoPoints ?? []
            lastMoveWasAuto = base?.lastMoveWasAuto ?? false
        }
        for record in records where record.seq > appliedCount {
            if record.seq != appliedCount + 1, !tolerateGaps { return .needsFull }
            if let point = record.point {
                board[point] = record.color
                lastMove = point
                lastRecordIsBlackPass = false
                // 같은 자리를 두 번 쓰는 길은 없지만, 다시 받은 기록이 사람 수라고 말하면 그 말을 따른다.
                if record.auto { autoPoints.insert(point) } else { autoPoints.remove(point) }
            } else {
                lastRecordIsBlackPass = record.color == .black
            }
            lastMoveWasAuto = record.auto
            appliedCount = record.seq
        }
        if let serverBoard = row.board.flatMap(GomokuBoard.init(serverString:)) {
            board = serverBoard
            if let serverCount = row.moveCount { appliedCount = serverCount }
        } else if let serverCount = row.moveCount, serverCount != appliedCount {
            if !tolerateGaps { return .needsFull }
            appliedCount = serverCount
        }

        let blackPassed: Bool
        if blackPassedHint == true {
            blackPassed = true
        } else if let lastRecordIsBlackPass {
            blackPassed = lastRecordIsBlackPass
        } else {
            blackPassed = base?.blackPassed ?? false
        }

        let turn = isFinished ? nil : GomokuColor(rawValue: row.turn ?? "")
        var deadline = isFinished ? nil : deviceDate(serverMs: row.deadlineMs)
        if let base, let kept = base.deadline, let fresh = deadline, base.moveCount == appliedCount, base.turn == turn,
           abs(fresh.timeIntervalSince(kept)) < Self.deadlineToleranceSeconds {
            // 같은 차례를 다시 읽었다 — 보정 오차만큼 다른 마감으로 갈면 창 루트가 조회마다 다시 그려진다.
            deadline = kept
        }
        let outcome: GomokuOutcome?
        switch row.result {
        case "draw": outcome = .draw
        case "black_win": outcome = myColor == .black ? .won : .lost
        case "white_win": outcome = myColor == .white ? .won : .lost
        default: outcome = nil
        }
        let stake = row.stake ?? base?.stake ?? 0
        let rubyDelta = outcome.map { result -> Int in
            switch result {
            case .won: return stake
            case .lost: return -stake
            case .draw: return 0
            }
        }
        let opponentID = (myColor == .black ? row.white : row.black)?.lowercased()
        let opponent = peerUser(payload.opponent, working: true, capable: true, inMatch: !isFinished)
            ?? base?.opponent
            ?? users.first { $0.id == opponentID }
            ?? GomokuUser(id: opponentID ?? "", displayName: "", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: !isFinished)

        let next = GomokuMatchState(
            id: id, stake: stake, myColor: myColor, opponent: opponent, board: board, lastMove: lastMove,
            moveCount: appliedCount, turn: turn, deadline: deadline, isFinished: isFinished, outcome: outcome,
            endReason: row.endReason.flatMap(GomokuEndReason.init(rawValue:)), rubyDelta: rubyDelta,
            blackPassed: blackPassed, autoPoints: autoPoints, lastMoveWasAuto: lastMoveWasAuto
        )
        let justFinished = isFinished && base?.isFinished == false
        let previous = match
        let windowWasVisible = isWindowVisible
        if match != next { match = next }
        let nextPhase: GomokuPhase = isFinished ? .result : .playing
        if phase != nextPhase { phase = nextPhase }
        // 채팅은 판을 옮긴 **뒤에** 옮긴다 — 순서가 바뀌면 방금 비운 대화 위에 옛 판의 줄이 다시 붙는다.
        // 끝난 판에서도 계속 받는다(결과 화면의 인사 120초).
        applyChat(payload, matchID: id, requestedSince: requestedSinceChat, generation: chatGeneration)
        // 연속 횟수는 **서버가 센다**(직접 두면 0으로 되돌리는 것도 서버다). 키가 없는 응답이면 들고 있던 값을 둔다.
        if let streak = payload.myAutoStreak, myAutoStreak != streak { myAutoStreak = streak }
        if let streak = payload.opponentAutoStreak, opponentAutoStreak != streak { opponentAutoStreak = streak }
        activeMatchID = isFinished ? nil : id
        if !isFinished {
            // 내 신청이 수락됐거나 내가 수락한 판이다 — 대기 카드를 걷는다.
            if outgoing?.id == id { outgoing = nil }
            if incoming.contains(where: { $0.id == id }) { incoming.removeAll { $0.id == id } }
        } else {
            shownResultIDs.insert(id)
        }
        lastOpponent = opponent
        lastStake = stake
        if !isFinished {
            // 새 판이 열렸다 — 로비에서 남긴 안내("신청을 보냈어요" 따위)는 대국 상태줄에서 "내 차례예요"를 가린다(v0.3.30).
            if previous?.id != id || previous?.isFinished == true { setNotice(nil) }
            noteMatchProgress(previous: previous, next: next, windowWasVisible: windowWasVisible)
        }
        if justFinished {
            // 전적은 로비 응답에만 있다. 판이 끝난 순간 한 번 다시 읽어 결과 화면 뒤 로비가 옛 전적을 보이지 않게 한다.
            Task { [weak self] in await self?.refreshLobby() }
        }
        return .applied
    }

    // MARK: - 동작

    package func challenge(userID: String) async {
        await challenge(userID: userID, peerHint: nil)
    }

    private func challenge(userID: String, peerHint: GomokuUser?) async {
        guard !isBusy, host?.session != nil else { return }
        let target = userID.lowercased()
        let stake = selectedStake.rawValue
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.gomokuChallenge(accessToken: $1, opponentID: target, stake: stake)
        }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.challenge(response.status, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("challenge refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                guard let id = response.matchId?.lowercased() else { break }
                let peer = users.first { $0.id == target }
                    ?? peerHint
                    ?? GomokuUser(id: target, displayName: "", avatarURL: nil, characterID: nil,
                                  isWorking: true, isCapable: true, inMatch: false)
                let expiresAt = deviceDate(serverMs: response.inviteExpiresMs)
                    ?? clock().addingTimeInterval(inviteTTLSeconds)
                outgoingRevision &+= 1
                outgoing = GomokuInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
                scheduleInviteExpiry()
            case .alreadyPending, .busy:
                await loadInbox()
            case .targetNotWorking, .targetBusy, .targetOutdated:
                // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다.
                await refreshLobby()
            default:
                break
            }
        }
    }

    package func cancelChallenge() async {
        guard !isBusy, let invite = outgoing, host?.session != nil else { return }
        let id = invite.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.gomokuCancel(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.cancel(response.status))
            switch response.status {
            case .ok, .notFound, .notPending, .expired:
                if outgoing?.id == id {
                    outgoing = nil
                    scheduleInviteExpiry()
                }
                // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                if response.status == .notPending { await loadInbox() }
            default:
                break
            }
        }
    }

    package func respond(inviteID: String, accept: Bool) async {
        guard !isBusy, host?.session != nil else { return }
        let id = inviteID.lowercased()
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        // 채팅 세대 캡처는 조회 경로(refreshMatch)와 **같은 시점**이다 — 요청을 띄우기 직전.
        // 이 응답이 싣고 오는 state 묶음의 채팅 부분도, 그 사이 음소거를 토글했으면 앞 판정이라 버려야 한다.
        let requestChatGeneration = chatGeneration
        guard let result = await perform({
            try await $0.gomokuRespond(accessToken: $1, matchID: id, accept: accept)
        }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.respond(
                accept: accept, response.status, side: response.side, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("respond refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                removeIncoming(id)
                guard accept else { break }
                // 수락하는 순간 서버가 두 참가자의 **다른 대기 신청을 전부 취소한다**(보낸 것·받은 것). 로컬 카드를 그대로 두면
                // 다음 받은함에서 '상대가 신청을 받지 않았어요'가 뜨고, 남은 보낸 신청 카드는 60초 뒤 '응답하지 않았어요'를 띄운다.
                if outgoing != nil { outgoing = nil }
                if !incoming.isEmpty { incoming = [] }
                if let state = response.state {
                    applyState(state, chatGeneration: requestChatGeneration)
                } else {
                    await refreshMatch(id: id)
                }
                // 판이 열리면 applyState 가 창을 띄운다(판 시작은 경로와 무관하게 한 곳에서 알린다).
                // 판을 못 받아 온 경우에만 여기서 창을 띄워 받은 신청이 어떻게 됐는지 보게 한다.
                if match?.id != id, !isWindowVisible { presentWindow?() }
            case .notFound, .notPending, .expired:
                removeIncoming(id)
            default:
                break
            }
        }
    }

    package func place(_ point: GomokuPoint, seen: GomokuSeenTurn? = nil) async {
        // 화면이 본 판과 다르면 먼저 적는다 — 판정은 아래 가드가 **스토어 값으로** 한다(진단만, 동작 무변경).
        if let seen, seen.differs(from: match) { noteTapDivergence(seen, at: point) }
        // **거절은 전부 이유를 남긴다**(v0.3.28 — 전에는 이 중 넷이 통째로 무음이었다). 보는 순서는 0.3.27 그대로다:
        // 같은 상황에서 같은 말을 해야 하고, 순서를 바꾸면 조용하던 갈래가 다른 문구로 바뀐다.
        guard !isBusy else { refuseTap(.busy, at: point); return }
        guard let current = match else { refuseTap(.noMatch, at: point); return }
        guard !current.isFinished else { refuseTap(.finished, at: point); return }
        guard current.turn == current.myColor else { refuseTap(.notYourTurn, at: point); return }
        guard current.board[point] == nil else { refuseTap(.occupied, at: point); return }
        // 흑 금수는 서버에 보내기 전에 막는다(헛왕복 절감). 판정은 서버 gomoku_judge 와 같은 규범·같은 예산이다.
        if current.myColor == .black,
           case .forbidden(let reason) = GomokuRules.judge(board: current.board, point: point, color: .black) {
            refuseTap(.forbidden, at: point, reason: reason)
            return
        }
        guard host?.session != nil else { refuseTap(.signedOut, at: point); return }
        let id = current.id
        let expected = current.moveCount
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        // 세대 캡처는 조회 경로와 **같은 시점**이다(요청 직전). "껐는데 곧바로 돌을 둔다"는 흔한 순서에서
        // 이 착수의 응답이 옛 my_muted 를 싣고 뒤늦게 도착한다 — 채팅은 버리고 착수 결과는 받아야 한다.
        let requestChatGeneration = chatGeneration
        guard let result = await perform({
            try await $0.gomokuMove(accessToken: $1, matchID: id, expectedSeq: expected, x: point.x, y: point.y)
        }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.move(response.status, reason: response.reason))
            if response.status != .ok {
                Self.logger.notice("move refused status=\(response.status.rawValue, privacy: .public)")
            }
            if response.status == .notFound {
                if match?.id == id { clearMatch() }
                return
            }
            // 판이 바뀌었거나(stale) 내 판단이 서버와 갈린 경우는 **언제나** 다시 읽는다.
            var needsRefresh: Bool
            switch response.status {
            case .stale, .notYourTurn, .notActive, .invalid: needsRefresh = true
            default: needsRefresh = false
            }
            if let state = response.state {
                // 세대는 **채팅 부분만** 거른다 — 판·기록 수·차례는 세대와 무관하게 받는다(applyChat 이 갈라 놓았다).
                let outcome = applyState(
                    state, requestedSince: expected, chatGeneration: requestChatGeneration,
                    blackPassedHint: response.blackPassed
                )
                if outcome == .needsFull { needsRefresh = true }
            } else if response.status == .ok || response.status == .timeout || response.status == .autoPlaced {
                // 상태를 안 실어 준 성공·시간 경과는 판을 다시 읽어야 한다(자동 착수는 내 수 말고 **남의 수까지** 바꾼다).
                needsRefresh = true
            }
            if needsRefresh { await refreshMatch(id: id) }
        }
    }

    package func resign() async {
        guard !isBusy, let current = match, !current.isFinished, host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        // 세대 캡처는 조회 경로와 **같은 시점**이다(요청 직전).
        let requestChatGeneration = chatGeneration
        guard let result = await perform({ try await $0.gomokuResign(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.resign(response.status))
            if let state = response.state { applyState(state, chatGeneration: requestChatGeneration) }
            if response.status != .ok || response.state == nil { await refreshMatch(id: id) }
        }
    }

    /// 결과 화면에서 로비로. **진행 중인 판에서는 아무것도 하지 않는다**(빠져나가는 길은 기권뿐이다).
    package func backToLobby() {
        if let current = match {
            guard current.isFinished else { return }
            dismissedMatchIDs.insert(current.id)
            // 결과 화면을 떠났다 = 그 판에서 나간 것이다. 둘 다 나가면 서버가 그 판 채팅을 즉시 지운다.
            leaveMatch(current.id)
            lastOpponent = current.opponent
            lastStake = current.stake
            match = nil
        }
        if phase != .lobby { phase = .lobby }
        // 로비로 나가면 그 판의 대화는 끝이다(서버도 하루 뒤 지운다). 초안까지 함께 내린다.
        clearMatchScopedState()
        setNotice(nil)
        guard host?.session != nil else { return }
        Task { [weak self] in
            await self?.refreshLobby()
            await self?.loadInbox()
        }
    }

    /// 같은 상대·같은 판돈으로 다시 신청.
    package func rematch() async {
        if let current = match, !current.isFinished { return }
        guard let opponent = match?.opponent ?? lastOpponent else { return }
        if let stake = GomokuStake(rawValue: match?.stake ?? lastStake ?? selectedStake.rawValue),
           selectedStake != stake {
            selectedStake = stake
        }
        if let current = match {
            dismissedMatchIDs.insert(current.id)
            match = nil
        }
        if phase != .lobby { phase = .lobby }
        clearMatchScopedState()
        await challenge(userID: opponent.id, peerHint: opponent)
    }

    // MARK: - 신호 · 계기

    /// 실시간 'gomoku' 신호. 직렬화된 재조회 — 도는 중이면 뒤따르는 한 번으로 합친다.
    package func handleSignal() {
        requestSync()
    }

    package func requestSync() {
        guard host?.session != nil else { return }
        guard syncTask == nil else {
            syncPendingTrailing = true
            return
        }
        let generation = resetGeneration
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다(requestDrain 과 같은 규약).
                self.syncPendingTrailing = false
                await self.syncOnce()
            } while self.syncPendingTrailing && generation == self.resetGeneration
            if generation == self.resetGeneration { self.syncTask = nil }
        }
    }

    /// 신호 한 번의 조회: 진행 중 판이 있으면 그 판(since_seq), 아니면 인박스.
    package func syncOnce() async {
        if let current = match, !current.isFinished {
            await refreshMatch(id: current.id)
        } else {
            await loadInbox()
        }
    }

    /// 조인 직후·깨어남의 따라잡기: 인박스 한 번 + 진행 중 판이면 그 판의 놓친 수.
    package func catchUp() async {
        await loadInbox()
        if let current = match, !current.isFinished {
            await refreshMatch(id: current.id)
        }
    }

    /// 실시간 조인 성공 직후(WorkTimerStoreRealtime 의 `.catchUp`).
    package func realtimeDidJoin() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 깨어남(결합 게이트가 열린 뒤).
    package func systemDidWake() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 근무 시작. v0.3.27 에는 "신청은 근무 중인 사람에게만 온다"가 근거였고, v0.3.30 에 서버가 그 조건을 지운 뒤로는
    /// 신선도 보강이다(주 경로는 소켓 신호·팝오버 열기).
    package func workDidStart() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.loadInbox() }
    }

    /// 팝오버 열림(60초 스로틀). `WorkTimerStore.setMenuPresented(true)` 가 부른다.
    ///
    /// v0.3.30 부터 **근무 밖에서도** 신청이 온다(서버 gomoku_challenge 의 근무 조건 삭제) — 캐릭터가 없는 비근무 사용자에게
    /// 팝오버 배너·메뉴바 점(`pendingIncomingInvites`)의 신선도가 이 계기와 소켓 신호에 달려 있다.
    package func refreshInboxIfStale() {
        guard host?.session != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuInboxAt) >= Self.menuInboxThrottleSeconds else { return }
        lastMenuInboxAt = now
        Task { [weak self] in await self?.loadInbox() }
    }

    // MARK: - 폴링 (창이 보일 때만)

    package func startPolling() {
        guard pollTask == nil, isWindowVisible, !isWindowOccluded else { return }
        pollToken &+= 1
        let token = pollToken
        pollTask = Task { @MainActor [weak self] in
            while true {
                let step = self?.pollStepSeconds ?? 0.5
                try? await Task.sleep(for: .seconds(step))
                guard let self else { return }
                guard !Task.isCancelled, token == self.pollToken, self.isWindowVisible, !self.isWindowOccluded else {
                    if token == self.pollToken { self.pollTask = nil }
                    return
                }
                await self.pollTick(at: self.clock())
            }
        }
    }

    package func stopPolling() {
        pollToken &+= 1
        pollTask?.cancel()
        pollTask = nil
    }

    /// 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다.**
    ///  · 진행 중 판이 상대 차례면(또는 표시 마감 + 유예가 지났으면) 구독 중 3초 / 미구독 1.5초마다 상태.
    ///  · 내 대기 신청이 있으면 5초마다 인박스(수락·거절·만료를 본다).
    ///  · 로비를 보고 있으면 30초마다 목록.
    package func pollTick(at now: Date) async {
        guard isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if let current = match, !current.isFinished {
            let waiting = current.turn != current.myColor
            let overdue = current.deadline.map { now.timeIntervalSince($0) > Self.turnGraceSeconds } ?? false
            if waiting || overdue {
                let subscribed = host?.realtimeState.isSubscribed ?? false
                let interval = subscribed ? Self.statePollSecondsWhileSubscribed : Self.statePollSecondsUnsubscribed
                if now.timeIntervalSince(lastStateRequestAt) >= interval {
                    await refreshMatch(id: current.id)
                }
            }
        }
        guard isWindowVisible else { return }
        if outgoing != nil, now.timeIntervalSince(lastInboxRequestAt) >= Self.outgoingInboxPollSeconds {
            await loadInbox()
        }
        guard isWindowVisible else { return }
        if phase == .lobby, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await refreshLobby()
        }
    }

    // MARK: - 초 단위 값 (잎 뷰 전용)

    /// 대국 창의 남은 시간(초, 0 이상). 잎 뷰 TimelineView 가 now 를 넘겨 부른다.
    package func remainingSeconds(now: Date) -> Double? {
        guard let current = match, !current.isFinished, let deadline = current.deadline else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }

    // MARK: - 리셋

    /// 로그아웃·계정 전환. 창을 닫고 오목 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다.
    package func reset() {
        // 나가기는 **세대를 올리기 전에** 쏜다(응답은 어차피 버려도 된다 — 요청이 나가는 것이 전부다).
        // 다만 로그아웃 경로에서는 이미 session 이 nil 이라 아무것도 안 나간다(실측: WorkTimerStore 의
        // clearPersistedSession 이 session 을 먼저 지우고 이 reset 을 부른다). 그래서 **best-effort** 다 —
        // 못 나간 판은 서버 백스톱이 하루 뒤 지운다. 여기서 세션을 붙잡아 두려 들지 마라.
        if let current = match, current.isFinished { leaveMatch(current.id) }
        resetGeneration &+= 1
        stopPolling()
        syncTask?.cancel()
        syncTask = nil
        syncPendingTrailing = false
        expiryTask?.cancel()
        expiryTask = nil
        stateInFlight = false
        stateAgain = false
        inboxInFlight = false
        inboxAgain = false
        lobbyInFlight = false
        if phase != .lobby { phase = .lobby }
        if !users.isEmpty { users = [] }
        if record != nil { record = nil }
        if selectedStake != .three { selectedStake = .three }
        if !incoming.isEmpty { incoming = [] }
        if outgoing != nil { outgoing = nil }
        if match != nil { match = nil }
        if notice != nil { notice = nil }
        if isBusy { isBusy = false }
        if isSendingChat { isSendingChat = false }
        clearMatchScopedState()
        if isWindowVisible { isWindowVisible = false }
        if isRulesVisible { isRulesVisible = false }
        if rubyBalance != nil { rubyBalance = nil }
        if turnSeconds != 30 { turnSeconds = 30 }
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if hasLoadedLobby { hasLoadedLobby = false }
        if !liveMatches.isEmpty { liveMatches = [] }
        if autoAbandonStreak != GomokuStore.autoPlaceLossStreak {
            autoAbandonStreak = GomokuStore.autoPlaceLossStreak
        }
        serverClockOffset = 0
        hasServerClockOffset = false
        isWindowOccluded = false
        stateInFlightID = nil
        pendingStateID = nil
        attentionKey = nil
        shownResultIDs = []
        outgoingRevision = 0
        inboxRequestOutgoingRevision = 0
        activeMatchID = nil
        seenInviteIDs = []
        dismissedMatchIDs = []
        leftMatchIDs = []
        lastStateRequestAt = .distantPast
        lastInboxRequestAt = .distantPast
        lastLobbyRequestAt = .distantPast
        lastMenuInboxAt = .distantPast
        inviteTTLSeconds = 60
        lastOpponent = nil
        lastStake = nil
        dismissWindow?()
    }

    // MARK: - 채팅 동작

    /// 입력칸의 글을 보낸다(보내기 버튼 · ↩ · ⌘↩ 세 경로가 전부 여기로 온다).
    ///
    /// 판정은 `canSendChatNow` 와 같은 한 벌이고 여기서 다시 세지 않는다 — 다만 길이 초과만은 **여기서 말한다**
    /// (버튼은 잠겨 있어도 ↩ 로 들어오는 길이 있고, 그때 아무 말도 없으면 사용자는 앱이 먹었다고 읽는다).
    package func sendChatDraft() {
        guard !isSendingChat, let current = match else { return }
        switch GomokuChatBody.validate(chatDraft, maxLength: chatMaxLength) {
        case .empty:
            // 빈 입력은 말없이 무시한다. 여기서 안내를 띄우면 ↩ 를 한 번 헛친 사람이 혼난다.
            return
        case .tooLong(let limit):
            setChatNotice(GomokuNoticeText.chatTooLong(limit))
        case .ok(let body):
            // 보내는 것은 **정규화된 값**이다 — NFD 로 들어온 한글은 Swift 가 2자로 세고 서버가 6자로 센다.
            sendChat(kind: .text, body: body, matchID: current.id, clearsDraft: true)
        }
    }

    /// 빠른 문구 한 건. 서버로 가는 것은 **코드**이고, 쓰다 만 초안은 건드리지 않는다.
    package func sendQuick(_ phrase: GomokuQuickPhrase) {
        guard !isSendingChat, let current = match else { return }
        sendChat(kind: .quick, body: phrase.rawValue, matchID: current.id, clearsDraft: false)
    }

    /// 이 판 채팅 끄기·켜기. 음소거는 내 화면 설정이 아니라 **서버가 아는 판 상태**라 상대 화면에도 뜬다
    /// (사용자 요구: "끄면 상대에게 티가 나게").
    package func setChatMuted(_ muted: Bool) {
        guard !isSendingChat, let current = match, host?.session != nil else { return }
        let id = current.id
        isSendingChat = true
        setChatNotice(nil)
        let generation = resetGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == self.resetGeneration { self.isSendingChat = false } }
            guard let result = await self.perform({
                try await $0.gomokuChatMute(accessToken: $1, matchID: id, muted: muted)
            }) else { return }
            switch result {
            case .failure:
                self.setChatNotice(GomokuNoticeText.checkConnection)
            case .success(let response):
                self.noteServerNow(response.serverNowMs)
                self.setChatNotice(GomokuNoticeText.chatMute(response.status))
                guard response.status == .ok else {
                    Self.logger.notice("chat mute refused status=\(response.status.rawValue, privacy: .public)")
                    return
                }
                // 요청한 값이 아니라 **서버가 적용했다고 말한 값**을 쓴다.
                let applied = response.muted ?? muted
                if self.isMuted != applied { self.isMuted = applied }
                // 가려짐은 서버가 정한다: 껐으면 상대 줄이 `chat[]` 에서 통째로 빠지고, 켜면 가려졌던 줄이 돌아온다.
                // 로컬에서 걸러 내면 두 판정이 갈리므로 대화를 비우고 그 판 채팅을 처음부터 다시 받는다.
                //
                // **기준선(`chatSeq`)은 내리지 않는다.** 0 으로 내리면 토글 직전에 나간 조회의 늦은 응답이 역행
                // 방어에 안 걸려(어떤 옛 스냅숏도 `serverSeq >= 0`) 방금 누른 값을 되감고 번호만 서버 값으로
                // 되올린다 — 줄은 한 줄도 안 담긴 채로. 대신 **세대를 올려** 그 응답을 통째로 버리고,
                // 전체 재요청은 표시로 건다(그 판 조회가 이미 돌고 있으면 그것이 뒤이어 한 번 더 돈다).
                self.chatGeneration &+= 1
                self.chatWantsFull = true
                if !self.chat.isEmpty { self.chat = [] }
                await self.refreshMatch(id: id)
            }
        }
    }

    /// 채팅 한 줄 보내기의 공통 몸통. **`isBusy` 를 세우지 않는다**(착수·기권을 잠그지 않는다).
    private func sendChat(kind: GomokuChatKind, body: String, matchID id: String, clearsDraft: Bool) {
        guard host?.session != nil else { return }
        isSendingChat = true
        setChatNotice(nil)
        let generation = resetGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == self.resetGeneration { self.isSendingChat = false } }
            guard let result = await self.perform({
                try await $0.gomokuChatSend(accessToken: $1, matchID: id, kind: kind, body: body)
            }) else { return }
            switch result {
            case .failure:
                self.setChatNotice(GomokuNoticeText.checkConnection)
            case .success(let response):
                self.noteServerNow(response.serverNowMs)
                if let limit = response.chatMaxLen, limit > 0, self.chatMaxLength != limit {
                    self.chatMaxLength = limit
                }
                // 보낸 사람이 **여기서** 안다: 상대가 껐다 / 상대가 못 받는 버전이다. 조용히 삼키지 않는다.
                if let muted = response.opponentMuted, self.isOpponentMuted != muted { self.isOpponentMuted = muted }
                if let capable = response.chatCapable, self.opponentChatCapable != capable {
                    self.opponentChatCapable = capable
                }
                self.setChatNotice(GomokuNoticeText.chat(response.status))
                guard response.status == .ok else {
                    // **자동 재전송은 없고 초안도 비우지 않는다.** 실패한 말은 사용자가 다시 누를 때만 나간다.
                    Self.logger.notice("chat refused status=\(response.status.rawValue, privacy: .public)")
                    return
                }
                if clearsDraft, self.match?.id == id { self.chatDraft = "" }
                // 낙관 삽입을 하지 않는다: 서버가 본문을 정규화하고 번호·시각을 정한다. 내가 지어낸 줄과
                // 다음 응답의 진짜 줄이 다르면 같은 말이 두 줄로 보이거나 순서가 튄다(메시지와 같은 판단).
                await self.refreshMatch(id: id)
            }
        }
    }

    // MARK: - 내부

    /// 상태 응답의 채팅 부분을 옮긴다. 늦게 온 응답 방어를 착수와 **같은 겹으로** 얹는다:
    ///  · 판이 바뀌면 비운다(다른 판의 말이 섞이면 그건 사고다),
    ///  · 음소거 토글 **뒤에** 도착한 응답은 세대가 달라 통째로 버린다(값도 줄도 앞 판정이다),
    ///  · 서버 발급 번호가 **역행하면 통째로 버린다**(옛 스냅숏이 방금 켠 음소거를 되돌리지 못하게 값보다 먼저 본다),
    ///  · 음소거가 뒤집혀 오면(다른 기기에서 눌렀다) 대화를 비우고 전체 재요청을 표시한다,
    ///  · 기록에 구멍이 나면 다음 한 번을 처음부터 받게 표시한다.
    private func applyChat(
        _ payload: GomokuStatePayload, matchID id: String, requestedSince: Int, generation: Int?
    ) {
        if chatMatchID != id { clearMatchScopedState(for: id) }
        // 이 요청이 나간 **뒤에** 음소거를 토글했다. 그 응답의 my_muted 는 방금 누른 값을 되감고 그 chat_seq 는
        // 줄 없이 기준선만 올린다 — 값을 하나씩 고르지 말고 통째로 버린다. 버리는 것은 **채팅 부분뿐**이라
        // 부르는 쪽의 판·착수 결과는 그대로 반영된다(조회·수락·착수·기권 네 경로가 모두 세대를 넘긴다).
        // (nil = 세대를 안 넘긴 자리 — 테스트의 직접 주입뿐이다.)
        if let generation, generation != chatGeneration { return }
        if let serverSeq = payload.chatSeq, serverSeq < chatSeq { return }
        // 상한·상대 상태는 **두 방어(세대·역행)를 지난 뒤에만** 받는다 — 늦은 옛 응답이 서버가 올린 상한을
        // 되돌리면 화면은 여유가 있다는데 서버만 거절한다.
        if let limit = payload.chatMaxLen, limit > 0, chatMaxLength != limit { chatMaxLength = limit }
        if let capable = payload.chatCapable, opponentChatCapable != capable { opponentChatCapable = capable }
        // 음소거가 **뒤집혀 오면**(두 번째 맥에서 눌렀다) 서버가 보여 주는 줄의 집합이 통째로 달라진다.
        // 들고 있는 줄은 앞 판정으로 걸러진 것이라 비우고, 이 응답이 전체가 아니면 다음 한 번을 처음부터 받는다 —
        // 안 그러면 켠 뒤에도 가려졌던 줄이 그 판 내내 안 돌아온다(경합 없이도 열리는 같은 구멍이다).
        var mutedFlipped = false
        if let muted = payload.myMuted, isMuted != muted {
            isMuted = muted
            mutedFlipped = true
        }
        if let muted = payload.opponentMuted, isOpponentMuted != muted { isOpponentMuted = muted }
        if mutedFlipped {
            if !chat.isEmpty { chat = [] }
            if requestedSince > 0 || payload.chat == nil { chatWantsFull = true }
        }
        // 채팅 키가 아예 없는 응답(채팅을 모르는 서버·쓰기 RPC 가 싣는 state 묶음)은 **지우지 않고 그냥 둔다**.
        guard let rows = payload.chat else { return }
        // 표시는 **전체를 실어 온 응답**이 내린다(요청을 띄울 때 내리면 실패하거나 버린 응답에 구멍이 그대로 남는다).
        if requestedSince == 0 { chatWantsFull = false }
        var lastSeq = chat.last?.seq ?? 0
        var appended: [GomokuChatMessage] = []
        for message in rows.compactMap(chatMessage(from:)).sorted(by: { $0.seq < $1.seq }) where message.seq > lastSeq {
            // 내가 껐으면 상대 줄이 서버에서 빠져 번호가 건너뛴다 — 그건 구멍이 아니라 음소거의 모습이다.
            if message.seq != lastSeq + 1, requestedSince > 0, !isMuted {
                chatWantsFull = true
                return
            }
            appended.append(message)
            lastSeq = message.seq
        }
        if !appended.isEmpty { chat.append(contentsOf: appended) }
        let nextSeq = max(payload.chatSeq ?? 0, lastSeq)
        if nextSeq > chatSeq { chatSeq = nextSeq }
    }

    /// 서버 채팅 행 → 화면 값. 빠른 문구는 코드를 문구로 편다.
    private func chatMessage(from row: GomokuChatRow) -> GomokuChatMessage? {
        guard let seq = row.seq, seq >= 1 else { return nil }
        let isQuick = row.kind == GomokuChatKind.quick.rawValue
        let quick = isQuick ? GomokuQuickPhrase(rawValue: row.body ?? "") : nil
        // 앱이 모르는 코드(서버가 표를 넓힌 날)는 줄을 **지우지 않고** 한 문장으로 접는다 — 소실은 오배달보다 나쁘다.
        let body = isQuick ? (quick?.text ?? GomokuNoticeText.chatUnknownQuick) : (row.body ?? "")
        guard !body.isEmpty else { return nil }
        return GomokuChatMessage(
            seq: seq,
            isMine: row.mine ?? false,
            sentAt: deviceDate(serverMs: row.createdMs) ?? clock(),
            quick: quick,
            body: body
        )
    }

    /// **한 판에만 속하는 것**을 전부 비운다(판이 바뀌었다 · 로비로 나갔다 · 로그아웃했다):
    /// 대화 · 초안 · 음소거 표시 · 자동 착수 연속 횟수.
    ///
    /// 초안까지 내리는 이유는 앞 판에 쓰던 말이 다음 판 입력칸에 남아 나가면 그게 곧 사고이기 때문이고
    /// (메시지의 '상대 바꾸기'가 세운 규약), 연속 횟수를 내리는 이유는 그것이 **판마다 따로 세는 값**이라
    /// 남겨 두면 새 판 첫 수부터 "한 번 더 놓치면 집니다"가 뜨기 때문이다.
    private func clearMatchScopedState(for id: String? = nil) {
        chatMatchID = id
        chatWantsFull = false
        if !chat.isEmpty { chat = [] }
        if chatSeq != 0 { chatSeq = 0 }
        if isMuted { isMuted = false }
        if isOpponentMuted { isOpponentMuted = false }
        if !opponentChatCapable { opponentChatCapable = true }
        if !chatDraft.isEmpty { chatDraft = "" }
        if chatNotice != nil { chatNotice = nil }
        if chatMaxLength != GomokuChatBody.maxLength { chatMaxLength = GomokuChatBody.maxLength }
        if myAutoStreak != 0 { myAutoStreak = 0 }
        if opponentAutoStreak != 0 { opponentAutoStreak = 0 }
    }

    private func setChatNotice(_ text: String?) {
        if chatNotice != text { chatNotice = text }
    }

    /// 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
    /// nil = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 nil 이면 **아무것도 바꾸지 않는다.**
    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (SupabaseWorkService, String) async throws -> T
    ) async -> Result<T, any Error>? {
        guard let host, host.session != nil else { return nil }
        let sessionGeneration = host.sessionGeneration
        let generation = resetGeneration
        let service = host.service
        do {
            let value = try await host.withSessionRetry { session in
                try await operation(service, session.accessToken)
            }
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return nil }
            return .success(value)
        } catch {
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return nil }
            if case .cancelled = host.classifyAuthError(error) { return nil }
            return .failure(error)
        }
    }

    /// **끝난 판에서 나간다**(결과 화면을 떠났다 · 결과 화면인 채로 창을 닫았다 · 로그아웃했다).
    ///
    /// 둘 다 나간 순간 서버가 그 판 채팅을 지운다 — 즉 이 호출의 뜻은 "이 대화는 끝났다"이고 **화면을 바꾸는 일과는
    /// 아무 상관이 없다.** 그래서 실패해도 안내하지 않고 화면 전환도 막지 않는다: 사용자가 할 수 있는 일이 없고,
    /// 못 나간 판은 서버 백스톱이 하루 뒤 지운다.
    ///
    /// **진행 중인 판에서는 절대 부르지 않는다**(부르는 쪽 셋이 전부 `isFinished` 를 먼저 본다) — 창을 닫아도
    /// 대국은 계속되기 때문이다. 서버도 `not_finished` 로 막지만, 확정으로 거절당할 요청을 내보내지 않는 것이
    /// 부르는 쪽 몫이다(무료 플랜).
    ///
    /// 멱등이지만 **판마다 한 번만** 부른다. 폴링·재진입마다 부르면 왕복이 판 수만큼 늘어난다.
    private func leaveMatch(_ rawID: String) {
        let id = rawID.lowercased()
        guard !id.isEmpty, !leftMatchIDs.contains(id), host?.session != nil else { return }
        leftMatchIDs.insert(id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard case .success(let response)? = await self.perform({
                try await $0.gomokuLeave(accessToken: $1, matchID: id)
            }) else { return }
            self.noteServerNow(response.serverNowMs)
            if response.status == .ok {
                if response.bothLeft == true { Self.logger.notice("left match, chat purged") }
            } else {
                Self.logger.notice("leave refused status=\(response.status.rawValue, privacy: .public)")
            }
        }
    }

    private func setNotice(_ text: String?) {
        if notice != text { notice = text }
    }

    /// 착수 거절 하나를 **두 곳**에 남긴다: 오른쪽 상태줄 한 줄(`notice`)과 진단 한 줄(`Logger`).
    ///
    /// 상태줄은 호버 이유(금수)를 1순위로 보여 주는 기존 규칙 그대로다 — 여기서는 `notice` 경로로만 흘려보낸다.
    ///
    /// 진단 줄에는 **좌표와 사유만** 싣는다. 닉네임·판 내용·판 id·토큰은 넣지 않는다(로그는 사용자 기기에 남고
    /// 제보에 실려 나간다). 싣는 넷은 전부 고정 어휘라 그대로 공개로 찍는다:
    /// `tap refused reason=occupied point=D10 turn=white mine=white busy=false`.
    /// 다음에 "눌렀는데 아무 반응이 없다"가 오면 이 한 줄이 갈래를 갈라 준다.
    private func refuseTap(_ refusal: GomokuTapRefusal, at point: GomokuPoint,
                           reason: GomokuForbiddenReason? = nil) {
        if let text = GomokuNoticeText.tapRefusal(refusal, reason: reason) { setNotice(text) }
        Self.logger.notice("""
            tap refused reason=\(refusal.rawValue, privacy: .public) \
            point=\(point.notation, privacy: .public) \
            turn=\(self.match?.turn?.rawValue ?? "none", privacy: .public) \
            mine=\(self.match?.myColor.rawValue ?? "none", privacy: .public) \
            busy=\(self.isBusy ? "true" : "false", privacy: .public)
            """)
    }

    /// 탭 순간 화면과 스토어가 다른 판을 보고 있었다 — 한 줄(`tap refused` 와 같은 공개 어휘 규약, 이름·판 내용 없음).
    private func noteTapDivergence(_ seen: GomokuSeenTurn, at point: GomokuPoint) {
        tapDivergenceCount += 1
        Self.logger.notice("""
            tap diverged point=\(point.notation, privacy: .public) \
            sameMatch=\(seen.matchID == self.match?.id ? "true" : "false", privacy: .public) \
            view=(moves=\(seen.moveCount, privacy: .public) turn=\(seen.turn?.rawValue ?? "none", privacy: .public)) \
            store=(moves=\(self.match?.moveCount ?? -1, privacy: .public) turn=\(self.match?.turn?.rawValue ?? "none", privacy: .public))
            """)
    }

    /// 판 상태 변화 한 줄(없으면 nil). 수·차례·끝남·판 교체만 본다 — 시계·채팅·루비는 이 줄을 만들지 않는다.
    package nonisolated static func matchTransitionLine(from old: GomokuMatchState?, to new: GomokuMatchState?) -> String? {
        func turn(_ m: GomokuMatchState?) -> String { m?.turn?.rawValue ?? "none" }
        func moves(_ m: GomokuMatchState?) -> String { m.map { String($0.moveCount) } ?? "-" }
        func finished(_ m: GomokuMatchState?) -> Bool { m?.isFinished ?? false }
        let sameMatch = old?.id == new?.id
        guard !sameMatch || moves(old) != moves(new) || turn(old) != turn(new) || finished(old) != finished(new) else { return nil }
        return "state moves=\(moves(old))→\(moves(new)) turn=\(turn(old))→\(turn(new)) "
            + "finished=\(finished(new)) sameMatch=\(sameMatch)"
    }

    private func applyRuby(_ value: Int?) {
        guard let value else { return }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    private func clearMatch() {
        if match != nil { match = nil }
        if phase != .lobby { phase = .lobby }
        clearMatchScopedState()
    }

    private func removeIncoming(_ id: String) {
        if incoming.contains(where: { $0.id == id }) { incoming.removeAll { $0.id == id } }
    }

    /// 판 진행을 사람에게 알린다(applyState 가 진행 중 판을 옮긴 직후).
    ///  · 판이 없거나 끝난 판에서 **진행 중 판으로 처음 넘어가면** 창을 띄우고 주의를 끈다 — 신청자는 상대가 수락한
    ///    순간을 모르면 흑 30초를 흘려 판돈을 잃는다. 내가 수락해 연 판도 같은 문을 지난다(경로마다 따로 두지 않는다).
    ///  · 창이 안 보이는 동안 차례가 나에게 오면 말풍선 문(onAttention)을 연다. 같은 (판 id, 기록 수)에는 한 번뿐이다.
    private func noteMatchProgress(previous: GomokuMatchState?, next: GomokuMatchState, windowWasVisible: Bool) {
        let started = previous == nil || previous?.isFinished == true || previous?.id != next.id
        if started {
            presentWindow?()
            requestAttention?()
        }
        guard next.turn == next.myColor else { return }
        let arrived = started || previous?.turn != next.myColor || previous?.moveCount != next.moveCount
        let key = "\(next.id)#\(next.moveCount)"
        guard arrived, attentionKey != key else { return }
        attentionKey = key
        guard !windowWasVisible else { return }
        onAttention?(GomokuAttention(
            kind: started ? .matchStarted : .myTurn, matchID: next.id,
            opponentName: next.opponent.displayName, moveCount: next.moveCount))
    }

    /// server_now_ms 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로 받고, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만 간다 —
    /// 왕복 지연 몇 ms 마다 오프셋을 갈면 같은 신청·같은 마감이 응답마다 다른 값이 된다.
    package func noteServerNow(_ milliseconds: Double?) {
        guard let milliseconds, milliseconds > 0 else { return }
        let measured = milliseconds / 1000 - clock().timeIntervalSince1970
        guard !hasServerClockOffset || abs(measured - serverClockOffset) >= Self.serverClockToleranceSeconds else { return }
        serverClockOffset = measured
        hasServerClockOffset = true
    }

    /// 서버 epoch 밀리초 → 기기 시계의 같은 순간.
    package func deviceDate(serverMs milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000 - serverClockOffset)
    }

    private func invite(from row: GomokuInviteRow, peerRow: GomokuUserRow?, fallbackPeer: GomokuUser?) -> GomokuInvite? {
        guard let id = row.matchId?.lowercased(), !id.isEmpty, let stake = row.stake,
              let expiresAt = deviceDate(serverMs: row.inviteExpiresMs),
              let peer = peerUser(peerRow, working: true, capable: true, inMatch: false) ?? fallbackPeer
        else { return nil }
        return GomokuInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
    }

    /// 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다** —
    /// 이름도 판돈도 모르는 카드는 사용자에게 아무것도 알려 주지 않는다.
    private func liveMatch(from row: GomokuLobbyMatchRow) -> GomokuLiveMatch? {
        guard let id = row.matchId?.lowercased(), !id.isEmpty,
              let a = peerUser(row.a, working: true, capable: true, inMatch: true),
              let b = peerUser(row.b, working: true, capable: true, inMatch: true),
              // 판돈은 서버 CHECK 가 3·5·10 으로 묶어 둔 값이다. 서버가 그 표를 넓히는 날 이 줄이 먼저 막는다.
              let stake = row.stake.flatMap(GomokuStake.init(rawValue:)),
              let startedAt = deviceDate(serverMs: row.startedMs)
        else { return nil }
        return GomokuLiveMatch(id: id, a: a, b: b, stake: stake, startedAt: startedAt)
    }

    /// 사람 행 → GomokuUser. 행에 없는 칸(근무·가능·대국 중)은 로비 목록에서 빌리고, 거기에도 없으면 문맥 기본값이다.
    private func peerUser(_ row: GomokuUserRow?, working: Bool, capable: Bool, inMatch: Bool) -> GomokuUser? {
        guard let row, let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
        let known = users.first { $0.id == id }
        return GomokuUser(
            id: id,
            displayName: row.displayName ?? known?.displayName ?? "",
            avatarURL: row.avatarUrl ?? known?.avatarURL,
            characterID: row.character ?? known?.characterID,
            isWorking: row.isWorking ?? known?.isWorking ?? working,
            isCapable: row.capable ?? known?.isCapable ?? capable,
            inMatch: row.inMatch ?? inMatch,
            // 서버 어휘 → 화면 글자는 **이 줄과 아래 `user(from:)` 두 곳뿐**이다(CenterLabel 규약).
            // 키를 안 싣는 옛 서버면 로비 목록에서 빌린다 — 이름·아바타와 같은 규칙이다.
            center: CenterLabel.display(row.center) ?? known?.center
        )
    }

    private func announceNewInvites() {
        for invite in incoming.sorted(by: { $0.expiresAt < $1.expiresAt }) where !seenInviteIDs.contains(invite.id) {
            seenInviteIDs.insert(invite.id)
            onInviteArrived?(invite)
        }
    }

    /// 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치).
    package func scheduleInviteExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        let dates = incoming.map(\.expiresAt) + (outgoing.map { [$0.expiresAt] } ?? [])
        guard let earliest = dates.min() else { return }
        let delay = max(0, earliest.timeIntervalSince(clock())) + 0.25
        let generation = resetGeneration
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == self.resetGeneration else { return }
            self.expiryTask = nil
            self.pruneExpiredInvites(now: self.clock())
        }
    }

    package func pruneExpiredInvites(now: Date) {
        let alive = incoming.filter { $0.expiresAt > now }
        if alive != incoming { incoming = alive }
        if let sent = outgoing, sent.expiresAt <= now {
            outgoing = nil
            setNotice(GomokuNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /// 서버 사람 행 → GomokuUser(로비). `capable` 이 nil 이면 **불가**다.
    package nonisolated static func user(from row: GomokuUserRow) -> GomokuUser? {
        guard let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
        return GomokuUser(
            id: id,
            displayName: row.displayName ?? "",
            avatarURL: row.avatarUrl,
            characterID: row.character,
            isWorking: row.isWorking ?? false,
            isCapable: row.capable ?? false,
            inMatch: row.inMatch ?? false,
            center: CenterLabel.display(row.center)
        )
    }

    /// 로비 정렬: 도전할 수 있는 사람(근무 중·가능·대국 아님) → 근무 중·가능(대국 중) → 근무 중 → 나머지, 그 안은 이름순.
    package nonisolated static func sortedForLobby(_ users: [GomokuUser]) -> [GomokuUser] {
        func rank(_ user: GomokuUser) -> Int {
            if user.isWorking && user.isCapable && !user.inMatch { return 0 }
            if user.isWorking && user.isCapable { return 1 }
            if user.isWorking { return 2 }
            return 3
        }
        return users.enumerated().sorted { lhs, rhs in
            let (l, r) = (rank(lhs.element), rank(rhs.element))
            if l != r { return l < r }
            let order = lhs.element.displayName.localizedStandardCompare(rhs.element.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
