import CheckCore
import Foundation

// 1:1 체스 **폰 화면 문구**(인수인계 `chess-robot-mobile-handoff.md` §7). 오목 짝은 `GamesText.swift` 의
// `GomokuPhoneText` 이고 이 파일은 그 규약을 그대로 따른다.
//
//  · **맥과 같은 뜻이면 같은 문장이다** — 출처는 맥 `ChessText`(Sources/check/ChessPanel.swift "MARK: - 문구").
//    폰에서 처음 쓴 줄만 `// 폰` 으로 적는다.
//  · 거절·실패 한 줄은 **코어 `ChessNoticeText` 를 그대로 부른다**(status → 문구 변환을 두 벌로 만들지 않는다).
//    이 파일에 status 분기를 새로 만들면 같은 거절이 화면마다 다른 말을 한다.
//  · 진단 어휘(서버·상태·동기화·프로토콜·사유값)는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.
//
// ── 이 파일이 `#if os(iOS)` 밖에 있는 까닭 ──
// 뷰가 아니고 SwiftUI 를 쓰지 않는다. 폰 뷰는 맥 스위트가 못 보므로(저장소 메모 '폰 뷰는 맥 스위트가 못 본다')
// **문구만이라도 값으로 잴 수 있는 쪽**에 둔다. `Tests/CheckMobileKitTests/GamesChessTextTests.swift` 가 그 못이다.
//
// ── 돈이 갈리는 자리 넷(여기서 틀리면 루비가 틀리게 움직인 것처럼 보인다) ──
//  ① **FIDE 6.9** — 깃발이 떨어졌는데 남은 쪽에 메이트할 기물이 없으면 **무승부**다(2배 승리가 아니다).
//     서버 사유값이 `timeout`(패) 과 `timeout_insufficient`(무승부)로 **갈려 있고**, 두 문구가 섞이면
//     사용자는 돌려받은 루비를 잃은 것으로 읽는다. 폰은 다시 계산하지 않고 **문구만** 그 경우를 말한다.
//  ② **신청만 한 상태에서는 0원도 안 움직인다** — 빠지는 순간은 **수락**이고, 60초 뒤 만료는 루비를
//     건드리지 않는다. "신청하면 빠져요" 는 거짓이다(`stakeNotHeldYet` 과 그 테스트가 그 길을 막는다).
//  ③ **한 사람 한 판** — 체스 중인 사람은 오목을 신청·수락하지 못하고 **그 반대도 같다**. 폰은 두 입구를
//     같이 띄우므로 **양방향 모두** 막힌 상태를 말해야 한다(한 방향만 막으면 체스 판돈을 시간패로 잃는다).
//  ④ **로봇 판은 로그인을 안 본다** — `ChessStoreAI` 는 서버를 한 번도 안 탄다. 입구를 로그인 뒤로 숨기면
//     비로그인 사용자의 길이 막힌다(`robotEntryBlock` 이 그 판단의 한 자리다).

/// 1:1 체스 폰 화면 문구. 맥 `ChessText` 와 같은 자리.
package enum ChessPhoneText {

    // MARK: 머리

    package static let title = "1:1 체스"
    package static let rulesButton = "규칙"
    package static let rulesTitle = "체스 규칙"
    package static let close = "닫기"

    /// 머리글 캡션. 시간 수치는 **서버가 말한 값**에서 만든다 — 상수를 베끼면 서버가 시계를 바꾼 날 화면만 옛 숫자다
    /// (2026-10-05 에 5분이었고 2026-10-12 에 **10분**이 됐다. 그 사고를 피하는 자리가 이 함수다).
    /// 기본값은 로비를 읽기 전의 자리표시이고 `ChessClock` 한 곳에서 온다(맥 `ChessText.subtitle` 과 같은 꼴).
    package static func subtitle(initialMs: Int = ChessClock.initialMs,
                                 incrementMs: Int = Int(ChessClock.incrementSeconds * 1000)) -> String {
        "FIDE 규칙 · 백 선공 · \(clockPhrase(initialMs: initialMs, incrementMs: incrementMs))"
    }

    /// "10분 + 한 수 3초" — 시계 한 조각(규칙 시트와 머리글이 같이 쓴다).
    package static func clockPhrase(initialMs: Int = ChessClock.initialMs,
                                    incrementMs: Int = Int(ChessClock.incrementSeconds * 1000)) -> String {
        let minutes = max(1, initialMs / 60_000)
        let increment = max(0, incrementMs / 1_000)
        return "\(minutes)분 + 한 수 \(increment)초"
    }

    /// 서버가 신청 만료를 안 말해 줬을 때의 값(초). 서버 `chess_invite_ttl_seconds()` 와 같은 60 이고,
    /// 로비 응답의 `invite_ttl_seconds` 가 오면 **그 값을 써라**(이 상수는 폴백이다).
    package static let inviteTtlSecondsFallback = 60

    // MARK: 로비

    package static let lobbyTitle = "상대 고르기"
    package static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    package static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    package static let loadingUsers = "상대 목록을 불러오고 있어요"
    /// 폰: 맥은 연결 안내 한 문장이지만 폰은 절마다 "무엇을 못 불러왔나" + 공용 [다시 시도]로 말한다(`MobileLoadText` 규칙).
    package static let usersLoadFailed = "상대 목록을 불러오지 못했어요"
    package static let reloadUsers = MobileLoadText.retry
    package static let challenge = "도전"
    package static let needsUpdate = "앱 업데이트가 필요해요"
    package static let inMatchButton = "대국 중"
    package static let working = "근무 중"
    package static let notWorking = "근무 안 함"

    package static let recordTitle = "전적"
    package static let myRubyTitle = "내 루비"
    package static func peopleCount(_ count: Int) -> String { "\(count)명" }
    package static func liveCount(_ count: Int) -> String { "\(count)판" }

    /// 게임 탭 **카드** 부제. ★ 시간 수치를 싣지 않는다 — 카드는 로비를 아직 안 읽었을 수 있고(`subtitle` 과
    /// 다른 점이 그것이다) 10-12 에 5분 → 10분으로 늘어난 값이라 박아 두면 그 자리가 곧 거짓이 된다.
    package static let cardSubtitle = "FIDE 규칙 · 백 선공 · 로봇과도 둬요"
    /// 카드 칩 — 받은 신청. 체스 서버는 받은 신청을 **한 번에 하나만** 말해 준다(`chess_lobby.me`)라 수를 세지 않는다.
    package static let incomingChip = "받은 신청 1건"
    /// 카드 한 줄 — 보낸 신청을 기다리는 중.
    package static let outgoingLine = "보낸 신청을 기다리고 있어요"
    /// 카드 한 줄 — 아무것도 없을 때. **할 수 있는 일**을 말한다.
    package static let idleLine = "상대를 골라 대결을 신청해요"

    /// 상대 행 상태 칩. 우선순위: 대국 중 > 업데이트 필요 > 근무 중/근무 안 함(오목과 같은 서열).
    ///
    /// ★ `inMatch` 는 **어느 게임인지 말하지 않는다**(서버가 오목 판까지 보고 하나로 접어 준다 — `ChessUser.inMatch`).
    ///   그래서 "오목 중" 이라고 적지 않는다. 지어내면 체스 판을 두는 사람이 오목 중으로 보인다.
    package static func status(for user: ChessUser) -> String {
        if user.inMatch { return inMatchButton }
        if !user.isCapable { return needsUpdate }
        return user.isWorking ? working : notWorking
    }

    /// 비활성 [도전] 버튼의 글자 — **짧게** 말한다(알약 안에서 꺾이면 줄 높이가 늘어난다).
    /// 부제가 한 문장을 다시 말하지 않게, 옛 버전 축은 **이 자리**가 쥔다.
    package static let needsUpdateButton = "업데이트 필요"

    /// 상대 한 줄이 쓰는 **두 자리** — 이름 아래 회색 부제와 오른쪽 버튼 글자.
    package struct OpponentRow: Equatable, Sendable {
        package let subtitle: String
        package let buttonTitle: String
    }

    /// 상대 한 줄의 두 자리를 **한 함수**가 고른다.
    ///
    /// ★ 왜 둘을 같이 내나: 자리마다 따로 고르면 **같은 문장이 한 줄에 두 번** 나온다. 헤드리스 실측 —
    ///   솜사탕·보리차 줄의 부제가 "앱 업데이트가 필요해요"(두 줄로 꺾임)인데 오른쪽 버튼도 같은 문장이었다.
    /// ★ 게다가 옛 서열(`inMatch > capable > 근무`)이 **근무 축을 덮었다**: 솜사탕은 `is_working=true` 라
    ///   아바타에 초록 점이 켜지는데 "근무 중" 이 화면에서 사라져, 픽스처가 일부러 둔 '근무 중인데 옛 버전'
    ///   축이 안 읽혔다. 그래서 축을 **자리로 가른다** — 부제는 늘 근무 축, 버튼은 막힌 까닭.
    /// ★ 둘이 겹치는 갈래(대국 중 + 옛 버전)에서는 버튼이 못 말한 축을 부제 꼬리로 보낸다. 버튼은 하나라
    ///   말할 수 있는 까닭도 하나다 — 그때 축 하나가 사라지지 않게 하는 자리가 여기다.
    package static func opponentRow(for user: ChessUser) -> OpponentRow {
        let work = user.isWorking ? working : notWorking
        // 옛 버전이 먼저다: 상대가 앱을 올릴 때까지 신청이 서버에서 거절되는, 가장 오래 가는 막힘이다
        // (`capable` 이 nil 로 와도 false 다 — 모르는 상대는 불가로 그린다).
        if !user.isCapable {
            return OpponentRow(subtitle: user.inMatch ? "\(work) · \(inMatchButton)" : work,
                               buttonTitle: needsUpdateButton)
        }
        if user.inMatch { return OpponentRow(subtitle: work, buttonTitle: inMatchButton) }
        return OpponentRow(subtitle: work, buttonTitle: challenge)
    }

    /// 상대 행 부제(칩 대신 회색 글 — 오목 `opponentStatus` 와 같은 꼴). 대국 중이면 누구와 두는지(로비의 대결 중 목록에서 찾는다).
    package static func opponentStatus(for user: ChessUser, liveMatches: [ChessLiveMatch]) -> String {
        if user.inMatch {
            let partner = liveMatches.first { $0.a.id == user.id || $0.b.id == user.id }
                .map { $0.a.id == user.id ? $0.b.displayName : $0.a.displayName }
            return partner.map { "대국 중 · \($0)\(withParticle($0))" } ?? inMatchButton
        }
        if !user.isCapable { return needsUpdate }
        return user.isWorking ? working : notWorking
    }

    // MARK: ★ 한 사람 한 판 — 양방향 (인수인계 §6-7)

    /// 내가 지금 두고 있는 게임. **양방향으로 쓴다** — 체스 입구는 `.gomoku` 를, 오목 입구는 `.chess` 를 말한다.
    ///
    /// 왜 두 방향이 한 타입에 있는가: 서버는 `chess__busy`·`same_visibility` 로 **둘 다** 막는데, 폰은 탭 하나에
    /// 두 게임 입구를 같이 띄운다. 한 방향만 그리면 나머지 입구가 열린 것처럼 보이고, 거기서 신청을 보낸 사람은
    /// 서버 거절을 받는 동안 **진행 중인 판의 시계를 쓴다** — 맥에서 적대 검증이 P0 으로 잡은 자리다.
    /// ★ **1.0.11 부터 셋이다**(테트리스가 들어왔다). 그래서 "반대쪽 게임"(`otherGame`, 이진 뒤집기)은 **지웠다** —
    ///   셋에서는 반대쪽이 하나로 정해지지 않아, 오목을 두는 중에 막힌 테트리스 입구가 "체스를 신청할 수 있어요"
    ///   라고 **틀린 안내**를 했다(그래도 테스트는 초록이었다 — 둘만 있을 때 참이던 식이라서).
    ///   지금은 문구 함수가 **두는 판(playing)과 막힌 입구(blocked)를 둘 다** 받는다.
    package enum BusyGame: String, CaseIterable, Sendable {
        case gomoku, chess, tetris

        /// 게임 이름("오목" · "체스" · "1:1 테트리스").
        package var gameName: String {
            switch self {
            case .gomoku: return "오목"
            case .chess: return "체스"
            case .tetris: return "1:1 테트리스"
            }
        }

        /// 진행 중인 판을 가리키는 말("오목 판" · "체스 판" · "테트리스 대결"). 셋 다 받침으로 끝나므로 뒤에 "이" 를 붙인다.
        package var matchNoun: String {
            switch self {
            case .gomoku: return "오목 판"
            case .chess: return "체스 판"
            case .tetris: return "테트리스 대결"
            }
        }
    }

    /// 다른 판을 두는 중이라 입구가 막혔다 — "오목을 두는 중이에요" · "체스를 두는 중이에요" ·
    /// "1:1 테트리스 대결 중이에요"(테트리스는 '둔다'고 하지 않는다).
    package static func busyTitle(_ playing: BusyGame) -> String {
        switch playing {
        case .gomoku, .chess:
            return "\(playing.gameName)\(objectParticle(playing.gameName)) 두는 중이에요"
        case .tetris:
            return "\(playing.gameName) 대결 중이에요"
        }
    }

    /// 그 아래 한 줄 — 언제 풀리는지 말한다(막힌 이유만 말하면 사용자가 기다릴 끝을 모른다).
    ///
    /// ★ `blocked` 가 **막힌 입구**다(지어내지 않는다). 게임이 셋이 된 뒤로는 두는 판만 알고는 이 문장을 쓸 수 없다 —
    ///   오목을 두는 중에 막히는 입구가 체스·테트리스 **둘**이고, 각 카드는 자기 이름을 말해야 한다.
    package static func busyHint(playing: BusyGame, blocked: BusyGame) -> String {
        let name = blocked.gameName
        return "\(playing.matchNoun)이 끝나면 \(name)\(objectParticle(name)) 신청할 수 있어요"
    }

    /// 1:1 입구(도전·수락)를 막는 사유 한 줄. 두는 판이 없으면 nil 이다.
    ///
    /// ★ **양방향**이다: `playing` 이 `.gomoku` 면 체스 입구가, `.chess` 면 오목 입구가 막힌다.
    ///   화면은 이 함수 하나만 묻고 스스로 판단을 만들지 않는다(클라 게이트는 짝으로 있다 — 한쪽만 고치면
    ///   스토어는 풀렸는데 뷰가 막아서 초록인 채로 아무것도 안 바뀐다).
    package static func entryBlock(playing: BusyGame?) -> String? {
        playing.map(busyTitle)
    }

    /// 막힌 입구의 **둘째 줄**(언제 풀리는지). `entryBlock(playing:)` 과 **짝으로** 쓴다 — 머리만 그리면
    /// "지금은 못 눌러요" 로 끝나고 사용자가 기다릴 끝을 모른다(폰엔 호버 툴팁이 없다).
    package static func entryBlockHint(playing: BusyGame?, blocked: BusyGame) -> String? {
        playing.map { busyHint(playing: $0, blocked: blocked) }
    }

    /// 막힌 입구에 세우는 안내 **한 칸 두 줄**(제목 + 언제 풀리는지). 칩·보조 줄처럼 자리가 둘로 나뉘지 않는
    /// 자리(`InlineNotice`)가 쓴다.
    ///
    /// ★ 왜 표가 줄바꿈까지 쥐나: 뷰에서 `busyTitle + "\n" + busyHint` 를 조립하면 그 조립이 **맥 스위트가
    ///   못 보는 자리**(폰 뷰)에 남아, 한 화면만 둘째 줄을 빠뜨려도 아무도 모른다. 통합에서 실제로 그렇게
    ///   줄었다 — 안내가 `entryBlock`(제목) 한 줄로 모여 "오목 판이 끝나면 체스를 신청할 수 있어요" 가 사라졌고,
    ///   사용자는 **왜** 막혔는지만 알고 **언제** 풀리는지 모르게 됐다(폰엔 호버 툴팁이 없다).
    /// ★ **양방향이 같은 꼴이다** — `.gomoku`·`.chess` 가 같은 두 줄을 낸다(한쪽만 두 줄이면 다른 입구가 더
    ///   불친절하다).
    package static func entryBlockNotice(playing: BusyGame?, blocked: BusyGame) -> String? {
        guard let playing else { return nil }
        return busyTitle(playing) + "\n" + busyHint(playing: playing, blocked: blocked)
    }

    /// 게임 탭 체스 카드의 보이스오버 힌트(막히지 않았을 때).
    package static let cardOpenHint = "체스 대결 화면을 열어요"

    /// 로봇 판을 두는 중이라 **신청**이 막혔다(받은 신청은 막지 않고 묻는다 — 아래 `acceptEndsRobot…`).
    ///
    /// ★ 서버는 이 판을 볼 수 없다(`chess__busy` 는 `chess_matches` 만 본다 — 로봇 판은 서버에 행이 없다).
    ///   그래서 이 줄은 **클라만 할 수 있는 말**이고, 없으면 비활성 알약만 남아 "왜 안 눌리지"가 된다
    ///   (폰엔 호버 툴팁이 없다).
    package static let blockedByRobot = "로봇 판을 끝내면 1:1 대결을 신청할 수 있어요"

    /// 로봇 판을 두는 중에 받은 신청을 **수락**할 때 묻는 네 줄.
    ///
    /// ★ 막지 않고 묻는 까닭: 막으면 60초 TTL 안에 **루비가 걸린 진짜 대결**을 놓친다. 묻는 까닭: 안 물으면
    ///   1:1 판이 서는 순간 코어가 로봇 판을 버려(`discardAIGame`) **두던 판이 문구도 확인도 없이 사라진다**.
    ///   그래서 첫 줄이 "사라진다"를, 둘째 줄이 "잃는 루비는 없다"를 말한다(둘 다 사실이다).
    package static let acceptEndsRobotTitle = "로봇 판을 끝내고 수락할까요?"
    package static let acceptEndsRobotMessage = "두던 로봇 판은 저장되지 않아요. 순위·루비와 상관없는 판이라 잃는 루비는 없어요."
    package static let acceptEndsRobotConfirm = "끝내고 수락"
    package static let acceptEndsRobotCancel = "그냥 두기"

    /// 로봇과 두기 입구를 막는 사유 한 줄.
    ///
    /// ★ **로그인은 사유가 아니다**(인수인계 §6-12). `ChessStoreAI` 는 서버를 한 번도 안 타므로 비로그인
    ///   사용자도 둔다 — 입구를 `signedIn` 으로 가리면 그 길이 통째로 막힌다. 그래서 이 함수는 `signedIn`
    ///   **값을 보지 않는다**(받기만 한다: 부르는 자리가 로그인으로 가르려 할 때 여기로 오게 하려고).
    ///   막는 사유는 하나뿐이다 — 이미 두고 있는 판(화면이 하나이고, 그 판에는 시계와 루비가 걸려 있다).
    package static func robotEntryBlock(signedIn: Bool, playing: BusyGame?) -> String? {
        _ = signedIn
        return playing.map(busyTitle)
    }

    /// 로봇 입구가 막힌 **까닭**. 코어 게이트(`canStartAIMatch`)의 다섯 조건을 사용자가 **할 수 있는 일**로 묶는다.
    ///
    /// ★ 왜 가르나: 게이트 깃발 하나로 문구를 고르면 **보낸 신청만 있는 사람**에게 "체스를 두는 중이에요"
    ///   라고 말한다 — 두고 있지 않은 판을 두고 있다고 듣고, 할 일(신청 취소)을 못 찾는다(헤드리스 실측 D3).
    ///   게이트는 **그대로 둔다**(신청이 수락되는 순간 1:1 이 로봇 판을 이기므로 막는 것이 맞다) —
    ///   가르는 것은 **문구뿐**이다.
    package enum RobotBlock: String, CaseIterable, Sendable {
        /// 판이 떠 있다(1:1 이든 로봇이든). 끝나야 풀린다.
        case playing
        /// 보낸 신청이 답을 기다린다 — **판은 없다**. 취소하면 바로 풀린다.
        case outgoingInvite
        /// 요청이 오가는 중(한 틱). 곧 풀린다.
        case busy
    }

    /// 막힌 사유 한 줄(머리).
    package static func robotEntryBlock(_ reason: RobotBlock) -> String {
        switch reason {
        case .playing: return busyTitle(.chess)
        case .outgoingInvite: return "신청에 답을 기다리는 중이에요"
        case .busy: return "요청을 보내는 중이에요"
        }
    }

    /// 그 **둘째 줄** — 언제·어떻게 풀리는지. 머리만 그리면 "지금은 못 눌러요" 로 끝나고 사용자가 할 일을
    /// 모른다(폰엔 호버 툴팁이 없다 — `entryBlockHint` 와 같은 까닭의 짝이다).
    package static func robotEntryBlockHint(_ reason: RobotBlock) -> String {
        switch reason {
        case .playing: return "두던 판이 끝나면 로봇과 둘 수 있어요"
        case .outgoingInvite: return "보낸 신청을 취소하면 로봇과 둘 수 있어요"
        case .busy: return "잠시 뒤에 다시 눌러 보세요"
        }
    }

    /// 입구에 세우는 **한 칸 두 줄**(머리 + 언제 풀리는지). 자리가 하나뿐인 보조문구 칸이 쓴다 —
    /// 줄바꿈까지 표가 쥐는 까닭은 `entryBlockNotice` 와 같다(뷰에서 조립하면 맥 스위트가 못 본다).
    package static func robotEntryBlockNotice(_ reason: RobotBlock) -> String {
        robotEntryBlock(reason) + "\n" + robotEntryBlockHint(reason)
    }

    // MARK: 판돈 (★ 빠지는 순간은 수락이다)

    package static let stakeTitle = "판돈"
    /// 고를 수 있는 판돈 셋(3 · 5 · 10). 집합의 주인은 서버이고(`stakes`) 앱 값과 갈리면 진실은 거절한 쪽에 있다.
    package static let stakes = ChessStake.allCases.map(\.rawValue)
    /// "5 · 이기면 +4" — v0.3.54 부터 꼬리 숫자는 **순이익**(판돈 − 수수료 10% 반올림, `DuelFee.winnerNet`)이다.
    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    /// " · 이기면 +4"(판돈 5 의 줄 꼬리 — 순이익).
    package static func stakeGainSuffix(_ stake: Int) -> String { " · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    /// "이기면 +4" — 판돈 칸(타일) 아래 줄. 꼬리(`stakeGainSuffix`)와 달리 **앞 가운뎃점이 없다**.
    package static func stakeGain(_ stake: Int) -> String { "이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    package static let stakePromptCaption = "판돈을 고르세요"
    package static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stakeLine(stake))" }
    package static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    /// 루비가 모자라 못 고르는 판돈의 이유 한 줄. 정본은 앱의 다른 화면과 **같은 말**이다.
    package static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)
    /// 판돈이 **언제** 빠지는지. 주어가 '수락' 이다 — 오목과 같은 문장(v0.3.54 수수료 한 마디 포함).
    package static let stakeCaption = GomokuPhoneText.stakeCaption
    /// ★ 신청만 한 상태를 말하는 줄. "신청하면 빠져요" 로 적으면 **거짓**이다 — 신청은 0원도 움직이지 않고,
    /// 응답이 없으면 그대로 사라진다(루비 이동 없음). 이 문장과 그 테스트가 그 거짓말이 돌아오는 길을 막는다.
    package static func stakeNotHeldYet(ttlSeconds: Int = inviteTtlSecondsFallback) -> String {
        "신청만 해서는 루비가 빠지지 않아요 · \(ttlSeconds)초 안에 응답이 없으면 신청이 사라져요"
    }
    /// 무승부로 끝난 판의 루비. **`timeout_insufficient` 도 무승부다**(FIDE 6.9) — 그 판도 이 줄을 쓴다.
    package static let stakeRefundOnDraw = "건 루비는 돌려받아요"

    // MARK: 신청

    package static let incomingTitle = "받은 신청"
    package static let outgoingTitle = "보낸 신청"
    package static let noIncoming = "받은 신청이 없어요"
    package static let loadingIncoming = "받은 신청을 불러오고 있어요"
    /// 폰: 받은 신청을 불러오지 못했다(빈 목록을 "없어요" 로 말하지 않는다).
    package static let incomingLoadFailed = "받은 신청을 불러오지 못했어요"
    package static let accept = "수락"
    package static let decline = "거절"
    package static let cancel = "취소"
    package static func incomingTitle(name: String) -> String { "\(name)님의 신청" }
    package static func outgoingTitle(name: String) -> String { "\(name)님에게 신청했어요" }
    /// 남은 초("42초").
    /// 받은 신청 절 머리의 오른쪽 한 줄. ★ **초를 박지 않는다** — 서버가 `invite_ttl_seconds` 로 말하고
    /// 로비가 그 값을 넘긴다(상수를 베끼면 서버가 TTL 을 바꾼 날 화면만 옛 숫자다).
    package static func inviteTtlHint(ttlSeconds: Int = inviteTtlSecondsFallback) -> String {
        "\(ttlSeconds)초 안에 응답하세요"
    }

    package static func remaining(_ seconds: Double) -> String { "\(Int(max(0, seconds).rounded(.up)))초" }
    /// "42초 남음"(받은 신청 머리 · 보낸 신청 부제).
    package static func remainingPhrase(_ seconds: Double) -> String { "\(remaining(seconds)) 남음" }

    // MARK: 대국

    package static let myTurn = "내 차례예요"
    package static let opponentTurn = "상대 차례예요"
    package static let inCheck = "체크! 왕을 피하세요"
    package static let opponentInCheck = "상대가 체크예요"
    /// 폰: 서버 시계 규칙 안내 한 줄 — 앱을 나가도 차례 시간은 서버에서 흐른다(1:1 만. 로봇 판은 `robotClockPauses`).
    package static let clockRunsInBackground = "앱을 나가도 차례 시간은 흘러요"
    package static let movesTitle = "기보"
    package static let noMoves = "아직 둔 수가 없어요"
    package static let resign = "기권"
    package static let resignConfirmTitle = "기권하면 건 루비를 잃어요"
    package static let resignConfirmMessage = "지금 기권하면 이 판은 상대가 이겨요."
    package static let resignNow = "기권하기"
    package static let keepPlaying = "계속 두기"
    package static let backToLobby = "로비로"
    package static let playAgain = "다시 두기"
    package static let rematch = "같은 판돈으로 다시 신청"
    /// 폰: 나 카드의 이름(스토어는 상대만 들고 있다 — 맥 `ChessPlayerFace` 의 "나").
    package static let me = "나"
    /// 별명을 모르는 상대(탈퇴·익명화·옛 응답).
    package static let opponentFallbackName = "상대"
    package static func resultOpponent(_ name: String) -> String { "상대 · \(name)" }

    /// 상태줄 한 줄. 네 조합을 **한 자리에서** 가른다 — `isInCheck` 는 서버 어휘로 "**차례인 쪽**이 체크인가" 이므로
    /// 내 차례의 체크는 내가 피해야 하고 상대 차례의 체크는 상대가 피해야 한다. 뷰에서 조합하면 그 방향이 뒤집힌다.
    package static func statusLine(isMyTurn: Bool, isInCheck: Bool) -> String {
        if isMyTurn { return isInCheck ? inCheck : myTurn }
        return isInCheck ? opponentInCheck : opponentTurn
    }

    package static func stoneName(_ color: ChessColor) -> String { color == .white ? "백" : "흑" }
    package static func stoneShort(_ color: ChessColor) -> String { stoneName(color) }
    /// 상대 카드 부제 "흑 · 근무 중".
    package static func playerSubtitle(color: ChessColor, isWorking: Bool) -> String {
        stoneName(color) + " · " + (isWorking ? working : notWorking)
    }

    /// 시계 글자 — `mm:ss`, 10초 아래는 `s.d`(초가 소수 한 자리). 마지막 10초는 1초 단위로는 안 읽힌다(맥과 같은 꼴).
    package static func clock(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        if clamped < 10 { return String(format: "%.1f", clamped) }
        let whole = Int(clamped.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    package static func clockAccessibility(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded())
        if whole >= 60 { return "남은 시간 \(whole / 60)분 \(whole % 60)초" }
        return "남은 시간 \(whole)초"
    }

    /// 시계가 **둘** 있는 화면(1:1 대국)의 보이스오버. 색을 안 붙이면 두 카드가 같은 말을 읽어
    /// 어느 쪽 시계인지 알 수 없다 — 로봇 화면은 한 벌만 읽으므로 위 짝을 쓴다.
    package static func clockAccessibility(_ seconds: Double, color: ChessColor) -> String {
        let whole = Int(max(0, seconds).rounded())
        let side = stoneName(color)
        if whole >= 60 { return "\(side) 남은 시간 \(whole / 60)분 \(whole % 60)초" }
        return "\(side) 남은 시간 \(whole)초"
    }

    /// 수 번호 줄("24수 진행").
    package static func plyLine(_ ply: Int) -> String { "\(ply)수 진행" }

    /// 깃발이 떨어지고 **유예 예산까지** 지났다 — 서버가 정산하는 중이다(폰이 판정한 것이 아니다).
    /// 이 자리에 결과를 지어내면 서버 판정(FIDE 6.9 의 무승부일 수도 있다)과 갈려 돈이 틀리게 읽힌다.
    package static let flagSettling = "시간이 다 됐어요 · 결과를 확인하고 있어요"
    /// 서버 FEN 을 읽지 못해 판을 그릴 수 없다(서버 쪽 문제 — 결과·루비는 그대로 보여 준다).
    package static let unreadableBoard = "판을 그릴 수 없어요 · 결과는 그대로 보여요"

    /// 무승부로 끝난 판에서 **돌려받은 액수**를 말한다(서버 `grant:chess:refund:`).
    /// ±0 만 그리면 "걸었다가 그대로"인지 "잃었는지"를 사용자가 못 가른다 — 돈이 갈리는 자리라 한 줄로 말한다.
    /// 액수가 없는 자리(제안 시트·결과 캡션)는 `stakeRefundOnDraw` 가 쓴다.
    package static func drawRefund(stake: Int) -> String { "판돈 \(stake) 루비를 돌려받았어요" }

    /// 판 전체를 읽는 보이스오버 한 줄(64칸을 하나씩 읽히면 못 쓴다 — 맥과 같은 결정).
    package static func boardAccessibility(ply: Int, turn: ChessColor?, inCheck: Bool) -> String {
        var text = "체스판, \(ply)수 진행"
        if let turn { text += ", \(stoneName(turn)) 차례" }
        if inCheck { text += ", 체크" }
        return text
    }

    // MARK: 승격 (★ 2단 — 넷이 같은 칸으로 갈 때만 묻는다)

    package static let promotionTitle = "승격할 말을 고르세요"
    /// 왜 지금 묻는지 한 줄. 승격은 **입력 2단의 셋째 단**이고 고르기 전에는 수가 나가지 않는다.
    package static let promotionCaption = "폰이 맨 끝 줄에 닿았어요 · 바꿀 말을 고르면 그 수를 둬요"
    /// 승격 창을 닫는다. [취소] 가 아니라 **무엇이 되는지**를 말한다 — 고르기는 남고 다른 수를 둘 수 있다.
    package static let promotionCancel = "다른 수 두기"

    /// 말 이름. 여섯 종 전부 있다 — 승격은 넷만 묻지만 기보·보이스오버가 킹·폰도 부른다.
    package static func pieceName(_ kind: ChessPieceKind) -> String {
        switch kind {
        case .queen: return "퀸"
        case .rook: return "룩"
        case .bishop: return "비숍"
        case .knight: return "나이트"
        case .pawn: return "폰"
        case .king: return "킹"
        }
    }

    /// 고를 수 있는 넷의 이름(퀸 · 룩 · 비숍 · 나이트). 순서는 `ChessPieceKind.promotionChoices` 가 쥔다 —
    /// 여기서 다시 적으면 판의 그림 순서와 어긋난다.
    package static var promotionChoiceNames: [String] {
        ChessPieceKind.promotionChoices.map(pieceName)
    }

    // MARK: 무승부 제안·응답

    package static let offerDraw = "무승부 제안"
    /// 내가 제안했고 상대의 응답을 기다린다(코어 `ChessNoticeText.drawOffered` 와 같은 뜻의 카드 줄).
    package static let drawOfferedByMe = "무승부를 제안했어요 · 상대의 응답을 기다려요"
    package static let drawOfferedByOpponent = "상대가 무승부를 제안했어요"
    package static let acceptDraw = "무승부 수락"
    package static let declineDraw = "거절"


    // MARK: 결과 (★ 사유 열 갈래를 빠짐없이)

    package static func outcomeTitle(_ outcome: ChessMatchOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대국이 끝났어요"
        }
    }

    /// 끝난 이유 한 줄(**내 기준** 축). `ChessEndReason` 열 갈래를 `default:` 없이 모두 말한다 —
    /// 접으면 `abandoned`(상대 계정 삭제)가 "대국이 끝났어요" 가 되어 남는 사람이 왜 2배를 받았는지 모른다.
    ///
    /// ★ 무승부 여섯(`isDraw`)은 **전부 문구에 '무승부'가 있다.** 특히 `timeoutInsufficient` 는
    ///   `timeout` 과 **다른 문장**이어야 한다(FIDE 6.9 — 깃발이 떨어졌지만 무승부다). 둘을 같은 말로
    ///   접으면 돌려받은 루비를 잃은 것으로 읽는다. 그 iff 를 테스트가 양방향으로 못 박는다.
    package static func endReason(_ reason: ChessEndReason?, outcome: ChessMatchOutcome?) -> String {
        guard let reason else { return unknownEndReason(outcome) }
        switch reason {
        case .checkmate: return outcome == .won ? "체크메이트로 이겼어요" : "체크메이트를 당했어요"
        case .resign: return outcome == .won ? "상대가 기권했어요" : "기권했어요"
        case .timeout: return outcome == .won ? "상대 시간이 다 됐어요" : "시간이 다 됐어요"
        case .timeoutInsufficient: return "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요"
        case .stalemate: return "둘 수 있는 수가 없어요 · 스테일메이트 무승부"
        case .fiftyMove: return "50수 동안 잡기도 폰 이동도 없었어요 · 무승부"
        case .threefold: return "같은 국면이 세 번 나왔어요 · 무승부"
        case .insufficientMaterial: return "메이트할 기물이 없어요 · 무승부"
        case .agreement: return "무승부에 합의했어요"
        case .abandoned: return outcome == .won ? "상대가 더 둘 수 없게 됐어요" : "더 둘 수 없게 됐어요"
        }
    }

    /// 사유를 **모르는** 판의 한 줄. 서버가 어휘를 넓히면 `ChessEndReason(rawValue:)` 가 nil 로 접히는데
    /// (코어 규약 ②), 그때 빈칸을 그리면 결과 카드에 이유 줄이 사라져 "왜 끝났는지 아무 데도 없는" 화면이 된다.
    /// **절대 빈 문자열을 내지 않는다** — 무승부는 무승부라고만, 나머지는 끝났다고만 말한다(지어내지 않는다).
    package static func unknownEndReason(_ outcome: ChessMatchOutcome?) -> String {
        outcome == .draw ? "무승부로 끝났어요" : "판이 끝났어요"
    }

    /// **관전** 결과 한 줄 — 3인칭이다(주어가 '흑'·'백').
    ///
    /// 위 `endReason(_:outcome:)` 은 '내 기준' 축이라 남의 판에 쓰면 `outcome` 이 nil 이어서 **언제나 패자 쪽
    /// 문장**이 나오고, 같은 카드의 머리글은 "흑 승리" 라 관전자가 자기모순을 읽는다(오목에서 고친 자리).
    /// `winner` 가 nil(무승부·승자 모름)이면 승패를 가르는 주어를 쓰지 않는다 — 지어내면 거짓말이 된다.
    package static func watchEndReason(_ reason: ChessEndReason?, winner: ChessColor?) -> String {
        guard let reason else { return unknownEndReason(winner == nil ? .draw : nil) }
        let loser = winner?.opponent
        func side(_ color: ChessColor?) -> String? { color.map(stoneName) }
        switch reason {
        case .checkmate: return side(loser).map { "\($0)이 체크메이트를 당했어요" } ?? "체크메이트"
        case .resign: return side(loser).map { "\($0)이 기권했어요" } ?? "기권으로 끝났어요"
        case .timeout: return side(loser).map { "\($0)의 시간이 다 됐어요" } ?? "시간이 다 됐어요"
        case .timeoutInsufficient: return "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요"
        case .stalemate: return "둘 수 있는 수가 없어요 · 스테일메이트 무승부"
        case .fiftyMove: return "50수 동안 잡기도 폰 이동도 없었어요 · 무승부"
        case .threefold: return "같은 국면이 세 번 나왔어요 · 무승부"
        case .insufficientMaterial: return "메이트할 기물이 없어요 · 무승부"
        case .agreement: return "무승부에 합의했어요"
        case .abandoned: return side(loser).map { "\($0)이 더 둘 수 없게 됐어요" } ?? "더 둘 수 없게 됐어요"
        }
    }

    /// 루비 변화(+10 / −10 / ±0). 음수 기호는 앱의 다른 화면과 같은 '−'(U+2212).
    package static func rubyDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "±0"
    }

    /// 결과 카드의 루비 줄 꼬리. 무승부면 **돌려받는다**고 말한다(±0 만 띄우면 잃은 것처럼 읽힌다).
    /// 로봇 판은 판돈이 없으므로 이 줄을 쓰지 않는다(`robotNoRecord` 가 그 자리다).
    package static func rubyResultCaption(_ outcome: ChessMatchOutcome?) -> String? {
        outcome == .draw ? stakeRefundOnDraw : nil
    }

    // MARK: 로봇과 두기 (판돈 없음 · 순위 없음 · ★ 로그인 없음)

    package static let robotButton = "로봇과 두기"
    package static let robotButtonHelp = "루비·순위 없이 로봇과 연습해요"
    package static let robotPromptTitle = "어느 색으로 둘까요"
    package static let robotPromptCaption = "색을 고르면 바로 시작해요"
    package static let robotPlayWhite = "백 · 먼저 둬요"
    package static let robotPlayBlack = "흑 · 나중에 둬요"
    /// 사용자 결정 둘(루비 안 걸기 · 기록 안 남기기)을 시작 전에 한 번, 대국 중에 한 번 더 말한다(맥과 같은 두 자리).
    package static let robotNoRecord = "루비·전적·순위에 들어가지 않아요"
    /// ★ 로봇 판은 서버를 한 번도 안 탄다 — 비로그인 사용자도 둔다. 입구에 이 줄을 두면 로그인을 요구하는
    ///   화면이 돌아올 때 **글자부터** 어긋나 눈에 띈다.
    package static let robotNoSignIn = "로그인하지 않아도 둘 수 있어요"
    package static let robotOpponentLine = "상대 · 로봇"
    package static let robotName = "로봇"
    package static let robotThinking = "로봇이 생각 중이에요"
    package static let robotThinkingShort = "생각 중"
    package static let robotResignConfirmTitle = "기권하면 이 판은 로봇이 이겨요"
    package static let robotRematch = "같은 색으로 다시 두기"
    /// 폰: 1:1 의 `clockRunsInBackground` 와 **정반대 사실**이다 — 로봇 판 시계는 화면을 떠나면 멈춘다
    /// (서버가 쥐는 시계가 아니다). 그 줄을 로봇 판에 그대로 두면 거짓말이 된다(오목이 같은 자리를 갈라 뒀다).
    package static let robotClockPauses = "화면을 떠나거나 앱을 나가면 시계가 멈춰요"

    /// 로봇 판 결과 이유. 1:1 문구는 루비("건 루비는 돌려받아요")·"상대"를 말해서 로봇 판에는 쓰지 않는다.
    /// 여기도 **열 갈래 전부**다 — 로봇 판에서 안 나는 사유라도 빈칸이 되면 결과 카드가 이유를 잃는다.
    package static func robotEndReason(_ reason: ChessEndReason?, outcome: ChessMatchOutcome?) -> String {
        guard let reason else { return unknownEndReason(outcome) }
        switch reason {
        case .checkmate: return outcome == .won ? "체크메이트로 이겼어요" : "체크메이트를 당했어요"
        case .resign: return outcome == .won ? "로봇이 기권했어요" : "기권했어요"
        case .timeout: return outcome == .won ? "로봇의 시간이 다 됐어요" : "시간이 다 됐어요"
        case .timeoutInsufficient: return "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요"
        case .stalemate: return "둘 수 있는 수가 없어요 · 스테일메이트 무승부"
        case .fiftyMove: return "50수 동안 잡기도 폰 이동도 없었어요 · 무승부"
        case .threefold: return "같은 국면이 세 번 나왔어요 · 무승부"
        case .insufficientMaterial: return "메이트할 기물이 없어요 · 무승부"
        case .agreement: return "무승부에 합의했어요"
        case .abandoned: return "더 둘 수 없게 됐어요"
        }
    }

    // MARK: 관전 (채팅 없음 · 관전자 수 없음 · 3분 꼬리)

    package static let liveTitle = "지금 대결 중"
    package static let noLiveMatches = "지금 대결 중인 판이 없어요"
    /// 폰: 로비를 불러오지 못했다(대결 중 목록은 로비 응답에 실린다).
    package static let liveLoadFailed = "대결 중인 판을 불러오지 못했어요"
    package static let watch = "관전"
    package static let watchTitle = "관전 중"
    package static let watchLoading = "판을 불러오고 있어요"
    package static let leaveWatch = "나가기"
    package static let myMatch = "내 판"
    /// ★ 관전에 **없는 것**을 미리 말한다 — 대화·관전자 수를 찾는 사람이 없는 기능을 기다리지 않게.
    ///   서버도 그 둘을 아예 싣지 않는다(`chess_watch` 응답에 칸이 없다).
    package static let watchCaption = "판만 보여 줘요 · 대화는 없어요"
    /// 끝난 판이 보이는 꼬리(분). 서버가 그 뒤로는 `not_found` 를 준다.
    package static let watchTailMinutes = 3
    package static let watchTailCaption = "끝난 판은 \(watchTailMinutes)분 동안만 볼 수 있어요"
    /// 꼬리가 지나 판이 사라졌다. 코어 문구를 그대로 쓴다(같은 사실이 화면마다 다른 말을 하지 않게).
    package static let watchGone = ChessNoticeText.watchGone
    package static func watchPly(_ ply: Int) -> String { "\(ply)수" }

    /// [관전] 칩의 보이스오버 힌트(맥 툴팁 자리 — 폰에는 호버가 없다).
    package static let watchChipHint = "이 판을 지켜봐요"
    /// 서버에 관전이 아직 없으면 칩 대신 서는 캡션. **짧게** 둔 것이 핵심이다 — 칩 자리는 얼굴 둘·이름·판돈
    /// 다음의 좁은 끝이라 긴 문장을 넣으면 이름 줄이 낱글자로 꺾인다. 보이스오버는 온전한 문장을 읽는다
    /// (`ChessNoticeText.unavailable`).
    package static let watchSoonCaption = "곧 열려요"
    /// 끝난 판인데 서버가 두 사람 행을 못 채웠다. 끝난 판은 폴링이 이미 멈춰 있어 더 올 것이 없으므로
    /// 진행형(`watchLoading`)으로 말하면 거짓말이 된다(오목에서 "불러오는 중"과 "이미 끝났다"가 한 화면에 떴다).
    package static let playersUnknown = "대국자를 불러오지 못했어요"
    /// 끝난 관전 판 머리글 — 이긴 색이 있으면 "흑 승리", 없으면 아래 `endedDraw`.
    package static func endedWin(_ winner: ChessColor) -> String { "\(stoneName(winner)) 승리" }
    package static let endedDraw = "무승부로 끝났어요"
    /// 진행 중 관전 머리글 — "관전 중 · 백 차례".
    package static func watchingTurn(_ turn: ChessColor) -> String {
        "\(watchTitle) · \(stoneName(turn)) 차례"
    }
    /// 이름을 모르는 자리. 코어 경계가 이름을 모를 때 nil 이 아니라 **빈 문자열**을 넣으므로 `??` 로는 못 접는다.
    package static let unknownName = "—"
    /// 판돈을 아직 모른다(씨앗 없이 들어온 판의 첫 응답 전) — 맥 판돈 칩의 "—"와 같은 자리.
    /// ★ **액수 자리만** 비운다(관전자에게 "이기면 +N" 접미사를 붙이지 않는다 — 관전자는 한 푼도 받지 않는다).
    package static let stakeUnknown = "\(stakeTitle) —"
    /// [나가기] 보이스오버 힌트.
    package static let leaveWatchHint = "로비로 돌아가요"

    /// 판 부품이 **스스로** 내는 한 줄(감싸는 화면이 더 아는 것 — 기보 수·체크 — 을 말하려면 바깥에서 덮어쓴다).
    /// 64칸을 하나씩 읽히면 못 쓴다(맥 `ChessText.boardAccessibility` 와 같은 규약).
    package static func boardAccessibility(position: ChessPosition, whiteAtBottom: Bool) -> String {
        "체스판, \(stoneName(whiteAtBottom ? .white : .black))이 아래, \(stoneName(position.sideToMove)) 차례"
    }

    /// 관전 판 전체를 한 요소로 읽는다(말 수 · 마지막 수 · 수 번호 · 상태). 칸마다 요소를 두는 것은
    /// **두는 사람의 판뿐**이다 — 관전은 입력이 없다.
    package static func boardAccessibility(_ watch: ChessSpectateState) -> String {
        var parts = ["체스판"]
        if let position = watch.position {
            var white = 0
            var black = 0
            for index in 0..<64 {
                guard let square = ChessSquare(index: index), let piece = position[square] else { continue }
                if piece.color == .white { white += 1 } else { black += 1 }
            }
            parts.append("백 \(white)개")
            parts.append("흑 \(black)개")
        }
        if let move = watch.lastMove {
            parts.append("마지막 수 \(move.from.notation)\(move.to.notation)")
        }
        parts.append(watchPly(watch.plyCount))
        parts.append(GamesChessWatchStatus.headline(for: watch))
        return parts.joined(separator: ", ")
    }
    /// "민트별 · 달토끼".
    package static func livePair(_ live: ChessLiveMatch) -> String {
        live.a.displayName + " · " + live.b.displayName
    }

    /// 대결이 시작된 뒤 흐른 시간을 말로("35초째" · "1분 35초째" · "1시간 2분째").
    package static func elapsedPhrase(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        if total < 60 { return "\(total)초째" }
        if total < 3600 { return "\(total / 60)분 \(total % 60)초째" }
        return "\(total / 3600)시간 \((total % 3600) / 60)분째"
    }

    // MARK: 순위 (★ 행은 승점만 띄우지 않는다)

    package static let rankTitle = "체스 순위"
    /// 절 **아래** 캡션 — 승점의 뜻.
    package static let rankCaption = "승점 = 승 − 패"
    /// 0판인 사람은 순위판에 안 낀다(서버가 아예 안 준다). 빈 순위를 사고로 읽지 않게 하는 줄이다.
    package static let rankZeroGamesNote = "한 판도 두지 않으면 순위에 들어가지 않아요"
    package static let myRankTitle = "내 순위"
    package static let outOfRank = "순위 밖"
    package static let noRanking = "아직 전적이 없어요"
    package static let noRankingHint = "첫 판이 끝나면 순위가 올라와요"
    /// 서버에 체스 순위가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창). **실패가 아니라 '곧'** 이다.
    package static let rankingUnavailable = "순위는 곧 열려요"
    package static let rankingLoadFailed = "순위를 불러오지 못했어요"
    /// 실패 줄 **아래** 한 줄 — 원인이 둘(연결·구버전 거절)인데 뷰가 가릴 수 없으므로 단정하지 않는다.
    package static let rankingLoadFailedHint = "계속 안 되면 앱을 업데이트해 주세요"
    /// 접힌 상태에서 보여 주는 행 수. 폰
    package static let rankCollapsedRows = 5
    /// 펼쳤을 때의 상한(서버도 100행까지 주지만 화면이 스스로 자른다). 폰
    package static let rankRowLimit = 100
    package static func rankSeeAll(total: Int) -> String { "전체 보기 · \(peopleCount(total))" }
    package static let rankCollapse = "접기"

    /// 전적 기준시각(컷)이 있으면 머리 오른쪽 캡션 — "10월 1일부터".
    /// 시간대는 **KST 로 못 박는다** — 컷은 서버가 정한 KST 자정이라 기기 시간대로 조립하면 비KST 기기에서 하루 밀린다
    /// (오목 `GomokuPhoneText.rankSince` 가 같은 자리를 그렇게 고쳤다).
    package static func rankSince(_ date: Date) -> String {
        let parts = TeamWeeklyGoal.kstCalendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일부터"
    }

    /// 컷이 없다(응답 `record_since_ms` 가 null = `-infinity`) — 기간이 통째다. 폰
    package static let rankWholePeriod = "전체 기간"

    /// 승점의 부호 있는 짧은 꼴("+9" · "−3" · "0").
    package static func signedPoints(_ points: Int) -> String {
        if points > 0 { return "+\(points)" }
        if points < 0 { return "−\(-points)" }
        return "0"
    }

    /// "승점 +4".
    package static func points(_ points: Int) -> String { "승점 \(signedPoints(points))" }

    /// "6승 2패 1무" — ★ **승점만 띄우지 않는다**(사용자 지시). 0 도 지우지 않는다.
    package static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }

    package static func record(_ record: ChessRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    /// 목록 밖 내 순위 한 줄 — "12위 · 승점 +4 · 6승 2패 1무"(0판이면 "순위 밖 · 0승 0패 0무"). 폰
    package static func myRankLine(_ mine: ChessMyRank) -> String {
        let record = record(wins: mine.wins, losses: mine.losses, draws: mine.draws)
        guard let rank = mine.rank else { return "\(outOfRank) · \(record)" }
        return "\(rank)위 · \(points(mine.points)) · \(record)"
    }

    /// 순위 한 행의 보이스오버 — "3위, 민트별, 서울센터, 승점 +4, 6승 2패 1무".
    ///
    /// ★ 행은 `순위 · 아바타 · 이름 · 승점 · 승 · 패 · 무` 를 **다 말한다**(사용자 지시). 눈으로 보는 행에서
    ///   전적을 지우면 금지된 '승점만' 상태이고, 이 라벨에서 지우면 눈이 아닌 사람에게 그 상태가 된다.
    ///   순위 원을 `accessibilityHidden` 으로 두므로 묶기(`children: .combine`)가 아니라 조립한 라벨을 쓴다.
    package static func rankRowAccessibility(_ entry: ChessRankEntry, isMe: Bool) -> String {
        var parts = ["\(entry.rank)위"]
        if isMe { parts.append(me) }
        parts.append(entry.user.displayName)
        if let center = entry.user.center, !center.isEmpty { parts.append("\(center)센터") }
        parts.append(points(entry.points))
        parts.append(record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
        return parts.joined(separator: ", ")
    }

    // MARK: 보이스오버·토막 (★ 화면이 제 글자를 적지 않게 — 폰 뷰는 맥 스위트가 못 본다)

    /// 값을 아직 모르는 숫자 칸(루비 잔액 미러가 비었다). `unknownName`(관전자 이름, em dash)과 **다른 글리프**다.
    package static let unknownNumber = "–"
    /// 한 줄 안에서 토막을 잇는 머리("· 루비가 모자라요").
    package static let bulletPrefix = "· "
    /// 고른 칸의 접근성 값.
    package static let selected = "선택됨"
    /// 머리 두 칸 왼쪽(내 전적)의 보이스오버 — 제목과 값이 한 요소로 합쳐지므로 무슨 전적인지 말한다.
    package static func myRecordAccessibility(_ record: ChessRecord?) -> String {
        "내 체스 전적 \(Self.record(record))"
    }
    /// [도전] 버튼의 보이스오버 힌트 — 누르면 **바로 신청이 나가지 않는다**(판돈 시트가 먼저다).
    package static func challengeHint(name: String) -> String { "\(name)님에게 판돈을 골라 신청해요" }
    /// 남은 초의 보이스오버("남은 시간 42초") — 화면 글자("42초 남음")와 어순이 다르다.
    package static func remainingAccessibility(_ seconds: Double) -> String { "남은 시간 \(remaining(seconds))" }
    /// 판돈 칸의 보이스오버.
    package static func stakeOptionAccessibility(_ stake: Int) -> String { "판돈 루비 \(stake)" }
    /// 결과 카드의 루비 줄 보이스오버("루비 +5"). 글자는 부호뿐이라(`rubyDelta`) 무엇의 부호인지 말한다.
    package static func rubyDeltaAccessibility(_ text: String) -> String { "루비 \(text)" }

    // MARK: 조사

    /// 받침이 있으면 "을", 없으면(한글이 아니어도) "를" — "오목을" · "체스를".
    package static func objectParticle(_ word: String) -> String {
        guard let scalar = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return "를" }
        return (scalar.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }

    /// 받침이 있으면 "과", 없으면 "와" — "달토끼와" · "민트별과".
    package static func withParticle(_ name: String) -> String {
        guard let scalar = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return "와" }
        return (scalar.value - 0xAC00) % 28 == 0 ? "와" : "과"
    }
}

/// 파일 이름(`GamesChessText.swift`)으로 부르는 쪽도 컴파일되게 둔 별칭. 인수인계 §7 이 화면 짝을
/// `GamesChessText` 로 적어 두었고 오목 짝의 타입 이름은 `GomokuPhoneText` 다 — 두 관례가 갈리는 자리라
/// **양쪽 이름이 같은 표를 가리킨다**(다른 화면이 어느 이름으로 불러도 같은 문구가 나온다).
package typealias GamesChessText = ChessPhoneText

/// 규칙 보기 시트의 한 줄. 맥 `ChessRulesOverlay.lines`(FIDE 요약)를 옮긴 것이고, 폰은 거기에 **시계·판돈** 두 줄을
/// 더한다 — 맥은 그 둘을 머리글 캡션과 판돈 창이 말하지만 폰 시트는 혼자 열리기 때문이다.
package struct ChessPhoneRuleLine: Identifiable, Equatable, Sendable {
    package let title: String
    package let detail: String

    package var id: String { title }

    package init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    /// 규칙 줄 전부. 시간 수치는 **서버가 말한 값**에서 만든다(상수를 베끼지 않는다 — `ChessPhoneText.subtitle` 과 같은 규약).
    ///
    /// ★ 마지막 둘이 돈이 갈리는 자리다: "시간" 줄은 **FIDE 6.9 예외**(메이트할 기물이 없으면 무승부)를 말하고,
    ///   "판돈" 줄은 루비가 빠지는 순간이 **수락**이라고 말한다. 둘 중 하나가 빠지면 사용자는 돌려받은 루비를
    ///   잃은 것으로 읽거나, 신청만으로 루비가 빠졌다고 믿는다.
    package static func all(initialMs: Int = ChessClock.initialMs,
                            incrementMs: Int = Int(ChessClock.incrementSeconds * 1000),
                            inviteTtlSeconds: Int = ChessPhoneText.inviteTtlSecondsFallback) -> [ChessPhoneRuleLine] {
        [
            ChessPhoneRuleLine(
                title: "기본",
                detail: "백이 먼저 둬요. 왕을 잡히지 않게 두면서 상대 왕을 피할 수 없게 만들면(체크메이트) 이겨요."),
            ChessPhoneRuleLine(
                title: "캐슬링",
                detail: "왕과 룩이 한 번도 움직이지 않았고 사이가 비어 있으면 왕을 두 칸 옮겨 룩과 자리를 바꿔요."),
            ChessPhoneRuleLine(
                title: "앙파상",
                detail: "상대 폰이 두 칸 전진해 내 폰 옆에 섰다면, 바로 다음 수에 한 칸 지나간 자리로 잡을 수 있어요."),
            ChessPhoneRuleLine(
                title: "승격",
                detail: "폰이 맨 끝 줄에 닿으면 퀸·룩·비숍·나이트 중 하나로 바꿔요."),
            ChessPhoneRuleLine(
                title: "무승부",
                detail: "둘 곳이 없는데 체크가 아니면(스테일메이트), 50수 동안 잡기·폰 이동이 없으면, 같은 국면이 세 번 나오면, "
                      + "메이트할 기물이 없으면, 또는 두 사람이 합의하면 무승부예요."),
            ChessPhoneRuleLine(
                title: "시간",
                detail: "\(ChessPhoneText.clockPhrase(initialMs: initialMs, incrementMs: incrementMs))예요. "
                      + "시간을 다 쓰면 지는데, 상대에게 메이트할 기물이 없으면 무승부예요."),
            ChessPhoneRuleLine(
                title: "판돈",
                detail: "\(ChessPhoneText.stakeCaption). "
                      + "\(ChessPhoneText.stakeNotHeldYet(ttlSeconds: inviteTtlSeconds))."),
            ChessPhoneRuleLine(
                title: "한 사람 한 판",
                // ★ 게임이 셋이다(1.0.11 — 1:1 테트리스). 셋을 다 말해야 한다: 이름이 빠진 게임은
                //   사용자가 "그건 되겠지" 하고 눌렀다가 서버 거절을 받는 동안 **두던 판의 시계를 쓴다**.
                detail: "체스·오목·1:1 테트리스는 한 번에 한 판만 할 수 있어요. "
                      + "한 판을 하는 중에는 다른 쪽을 신청하거나 수락할 수 없어요.")
        ]
    }
}
