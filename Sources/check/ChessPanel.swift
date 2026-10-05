import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 체스 창 화면 (v0.3.44)
//
// `CheckChessWindowController` 가 담는 화면이다: 로비(상대 고르기·지금 대결 중·순위·내 전적) → 대국(8×8 판 ·
// 시계 둘 · 기보 · 판돈 · 기권/무승부) → 결과, 그리고 남의 판 관전. 상태·동작은 전부 `ChessStore`(CheckCore)에
// 있고 여기는 **그리기와 탭 전달**만 한다.
//
// 이 파일이 지키는 약속(오목 화면에서 피 흘려 얻은 것 + 체스에서 새로 생긴 것):
//   · **Picker/Menu/TextField 를 쓰지 않는다.** 고르기·수락·기권·승격은 전부 Button + Shape/Canvas 다.
//     이유가 둘인데 뜻이 다르다: `TextField`·분절 `Picker` 는 ImageRenderer 가 **노란 상자**(255,204,0)로
//     그려 그 자리 픽셀 검증이 눈이 멀고, `Menu`·기본 `Picker` 는 **아무것도 안 그린다**(픽셀 커버리지 0 —
//     2026-10-05 실측). 뒤쪽이 더 나쁘다: 노란 상자는 보이지만 0 커버리지는 "렌더가 초록인데 화면이 비어 있다".
//   · **입력 2단의 상태는 스토어가 든다**(`store.selection`·`store.promotion`). 뷰 `@State` 에 두면 늦게 온
//     판 갱신과 어긋나 "선택은 e2 인데 판은 이미 다음 수" 가 된다 — 이 파일에 `@State` 로 둔 것은 호버와
//     기권 확인처럼 **화면에서 태어나 화면에서 죽는** 것뿐이다.
//   · **"둘 수 있는 칸" 은 내가 계산하지 않는다.** 1:1 판은 서버 `legal_moves`, AI 판은 로컬 `ChessRules` 가
//     이미 `match.legalMoves` 에 들어 있고 뷰는 `store.selection.targets` 만 그린다(ChessStore 머리말 ⑦).
//   · **초 단위 값(시계 둘)은 잎 뷰 TimelineView 안에서만 읽는다**(`ChessClockLeaf`). 창 루트가 시계를 읽으면
//     5Hz 로 창 전체가 다시 그려진다. 잎은 창이 안 보이면 멈춘다(`isWindowVisible`).
//   · 말은 **벡터로 그린다**(`ChessPieceArt`). 유니코드 체스 글리프(♔♕♘…)는 설치된 폰트에 따라 모양·굵기·
//     세로 정렬이 갈리고 어떤 폰트에는 흑백 한쪽만 있다 — 판에서 폰과 비숍을 못 가리는 그림은 버그다.
//   · 문구는 `ChessText`(화면 글자)와 `ChessNoticeText`(안내·거절, 코어) 두 표에만 있다.

// MARK: - 나(플레이어 얼굴)

/// 카드에 그릴 사람 한 명의 얼굴. 스토어는 **상대만** 들고 있어서 나는 앱 배선이 `WorkTimerStore` 에서 읽어 넘긴다.
struct ChessPlayerFace: Equatable {
    let name: String
    let avatarURL: URL?
    let characterID: String
    /// 소속 센터의 **화면 글자**("서울"/"부산"). nil 이면 배지가 없다. **기본값이 있는 채로 맨 끝.**
    var center: String? = nil

    static let fallbackCharacterID = "aing"
    static let fallback = ChessPlayerFace(name: "나", avatarURL: nil, characterID: fallbackCharacterID)

    /// 로그인한 나. 이름·아바타는 팀 목록의 내 행에서, 캐릭터는 이 맥에서 고른 캐릭터에서 읽는다.
    @MainActor
    static func me(from store: WorkTimerStore) -> ChessPlayerFace {
        let myID = store.session?.userID
        let mine = store.teamMembers.first { $0.id == myID }
        let character = CheckCharacter3DScene.selectedCharacter(defaults: .standard).id
        return ChessPlayerFace(name: mine?.name ?? "나", avatarURL: mine?.avatarURL, characterID: character,
                               center: CenterLabel.display(store.myCenter))
    }

    static func of(_ user: ChessUser) -> ChessPlayerFace {
        ChessPlayerFace(
            name: user.displayName,
            avatarURL: user.avatarURL.flatMap(URL.init(string:)),
            characterID: user.characterID ?? fallbackCharacterID,
            // 이미 화면 글자다(스토어 경계에서 한 번 변환했다) — 여기서 또 바꾸지 마라.
            center: user.center
        )
    }
}

// MARK: - 아이콘 한 출처

/// 체스를 가리키는 **아이콘 한 출처**. 창 머리글 · 미니게임 창 입구 · 팝오버가 같은 기호를 써야
/// 사용자가 "같은 것"으로 읽는다(오목이 `circle.grid.3x3.fill` 하나로 그렇게 하고 있다).
///
/// 심볼 이름을 고른 근거: macOS 14 가 최소 버전이라 SF Symbols 5 까지만 믿을 수 있고, 이름이 없으면
/// `Image(systemName:)` 는 **아무것도 안 그린다**(두부도 안 뜬다 — 자리만 비어 조용히 고장난다).
/// 그래서 이름이 이 맥에서 실제로 풀리는지를 테스트가 `NSImage(systemSymbolName:)` 로 되묻는다.
enum ChessEntryIcon {
    static let symbol = "checkerboard.rectangle"
    /// 그 이름이 없는 맥에서 쓸 대체 기호(아주 오래된 이름이라 반드시 있다).
    static let fallbackSymbol = "squareshape.split.3x3"

    /// 지금 이 맥에서 실제로 그릴 수 있는 이름.
    @MainActor
    static var resolved: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallbackSymbol
    }
}

// MARK: - 문구

/// 체스 화면의 사용자 문구(순수 — 값으로 검증한다). 진단 어휘를 쓰지 않는다.
enum ChessText {
    static let title = "1:1 체스"
    static let rulesButton = "규칙"
    static let rulesTitle = "체스 규칙"
    static let close = "닫기"

    /// 머리글 캡션. 시간 수치는 **서버가 말한 값**에서 만든다(상수를 베끼지 않는다 — A3 의 5분+3초가 서버에 있다).
    static func subtitle(initialMs: Int, incrementMs: Int) -> String {
        let minutes = max(1, initialMs / 60_000)
        let increment = max(0, incrementMs / 1_000)
        return "FIDE 규칙 · 백 선공 · \(minutes)분 + 한 수 \(increment)초"
    }

    static let lobbyTitle = "상대 고르기"
    static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    static let loadingUsers = "상대 목록을 불러오고 있어요"
    static let usersLoadFailed = ChessNoticeText.checkConnection
    static let reloadUsers = "다시 불러오기"
    static let challenge = "도전"
    static let needsUpdate = "앱 업데이트 필요"
    static let inMatch = "대결 중"
    static let working = "근무 중"

    static let stakeTitle = "판돈"
    static let stakeUnknown = "—"
    static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(stake)" }
    static func watchStakeLine(_ stake: Int) -> String { "\(stake)" }
    static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    static let stakePromptCaption = "판돈을 고르세요"
    static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stakeLine(stake))" }
    static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    /// 루비가 모자라 못 고르는 판돈의 이유 한 줄. 정본은 앱의 다른 화면과 **같은 말**이다.
    static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)

    static let incomingTitle = "받은 신청"
    /// 팝오버 배너 제목·부제·버튼 도움말(배너가 쓰는 네 문구는 여기 모여 있다).
    static func inviteBannerTitle(name: String) -> String { "\(name)님이 체스 대결을 신청했어요" }
    static let inviteBannerSubtitle = "1분 안에 응답하세요"
    static let acceptHelp = "수락하고 체스 창을 열어요"
    static let viewInvite = "보기"
    static let viewInviteHelp = "체스 창에서 이 신청을 봐요"
    static let outgoingTitle = "보낸 신청"
    static let noIncoming = "받은 신청이 없어요"
    static let accept = "수락"
    static let decline = "거절"
    static let cancel = "취소"

    static let recordTitle = "내 전적"
    static let liveTitle = "지금 대결 중"
    static let noLive = "지금 진행 중인 대결이 없어요"
    static let watch = "관전"
    static let myMatch = "내 판"
    static let leaveWatch = "나가기"
    static let watchTitle = "관전 중"
    static let watchLoading = "판을 불러오고 있어요"
    static let watchPaused = "창을 열어 두면 판이 계속 따라와요"

    static let rankTitle = "체스 순위"
    static let rankLoading = "순위를 불러오고 있어요"
    static let rankEmpty = "아직 순위가 없어요"
    static let rankFailed = ChessNoticeText.checkConnection
    static let rankSoon = "순위는 곧 열려요"
    static let rankHelp = "승점 = 승 − 패"
    static func rankSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일부터"
        return formatter.string(from: date)
    }

    static let myTurn = "내 차례예요"
    static let opponentTurn = "상대 차례예요"
    static let inCheck = "체크! 왕을 피하세요"
    static let opponentInCheck = "상대가 체크예요"
    static let aiThinking = "생각 중"
    static let resign = "기권"
    static let confirmResign = "기권하기"
    static let keepPlaying = "계속 두기"
    static let offerDraw = "무승부 제안"
    static let drawOfferedByMe = "무승부 제안을 보냈어요"
    static let drawOfferedByOpponent = "상대가 무승부를 제안했어요"
    static let acceptDraw = "무승부 수락"
    static let declineDraw = "거절"

    static let movesTitle = "기보"
    static let noMoves = "아직 둔 수가 없어요"
    static let promotionTitle = "승격할 말을 고르세요"

    static let aiButton = "로봇과 두기"
    static let aiButtonHelp = "기기와 한 판 둬요 (루비가 걸리지 않아요)"
    static let aiPromptTitle = "어느 색으로 둘까요"
    static let aiPlayWhite = "백(선공)"
    static let aiPlayBlack = "흑(후공)"
    static let aiInfo = "로봇과 둔 판은 순위·루비에 들어가지 않아요"
    static let playAgain = "다시 두기"
    static let backToLobby = "로비로"

    static func stoneName(_ color: ChessColor) -> String { color == .white ? "백" : "흑" }

    static func record(_ record: ChessRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    static func record(wins: Int, losses: Int, draws: Int) -> String {
        "\(wins)승 \(losses)패 \(draws)무"
    }

    static func myRank(rank: Int, points: Int) -> String {
        "\(rank)위 · 승점 \(points >= 0 ? "+" : "")\(points)"
    }

    static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    /// 시계 글자 — `mm:ss`, 10초 아래는 `s.d`(초가 소수 한 자리). 블리츠에서 마지막 10초는 1초 단위로는 안 읽힌다.
    static func clock(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        if clamped < 10 {
            return String(format: "%.1f", clamped)
        }
        let whole = Int(clamped.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func clockAccessibility(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded())
        if whole >= 60 { return "남은 시간 \(whole / 60)분 \(whole % 60)초" }
        return "남은 시간 \(whole)초"
    }

    /// 결과 한 줄(사유별). `ChessEndReason` 열 갈래를 **빠짐없이** 말한다 — `default:` 로 접으면
    /// `abandoned`(상대 계정 삭제)가 "대국이 끝났어요" 가 되어 남는 사람이 왜 이겼는지 모른다.
    static func outcomeTitle(_ outcome: ChessMatchOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대국이 끝났어요"
        }
    }

    static func endReason(_ reason: ChessEndReason?, outcome: ChessMatchOutcome?) -> String {
        guard let reason else { return "" }
        switch reason {
        case .checkmate: return outcome == .won ? "체크메이트" : "체크메이트를 당했어요"
        case .resign: return outcome == .won ? "상대가 기권했어요" : "기권했어요"
        case .timeout: return outcome == .won ? "상대 시간이 다 됐어요" : "시간이 다 됐어요"
        case .timeoutInsufficient: return "시간이 다 됐지만 메이트할 기물이 없어요"
        case .stalemate: return "스테일메이트"
        case .fiftyMove: return "50수 규칙"
        case .threefold: return "같은 국면 3회 반복"
        case .insufficientMaterial: return "메이트할 기물이 없어요"
        case .agreement: return "무승부에 합의했어요"
        case .abandoned: return "상대가 더 둘 수 없게 됐어요"
        }
    }

    /// **관전** 결과 한 줄 — 3인칭이다(주어가 '흑'·'백').
    ///
    /// 위 `endReason(_:outcome:)` 은 **'내 기준' 축**이다: `.won` 이면 "상대가 …", 아니면 "…를 당했어요".
    /// 남의 판에 그 함수를 쓰면 `outcome` 이 nil 이라 **언제나 패자 쪽 문장**이 나오고, 같은 카드의 머리글은
    /// "흑 승리" 라 관전자가 "흑 승리 / 기권했어요" 라는 자기모순을 읽는다(0ba552d 가 오목에서 고친 자리).
    /// 그래서 관전은 **이 함수만** 쓴다.
    ///
    /// `winner` 가 nil(무승부·승자 모름)이면 승패를 가르는 주어를 쓰지 않는다 — 지어내면 거짓말이 된다.
    static func watchEndReason(_ reason: ChessEndReason?, winner: ChessColor?) -> String {
        guard let reason else { return "" }
        let loser = winner?.opponent
        func side(_ color: ChessColor?) -> String? { color.map(stoneName) }
        switch reason {
        case .checkmate:
            return side(loser).map { "\($0)이 체크메이트를 당했어요" } ?? "체크메이트"
        case .resign:
            return side(loser).map { "\($0)이 기권했어요" } ?? "기권으로 끝났어요"
        case .timeout:
            return side(loser).map { "\($0)의 시간이 다 됐어요" } ?? "시간이 다 됐어요"
        case .timeoutInsufficient: return "시간이 다 됐지만 메이트할 기물이 없어요"
        case .stalemate: return "스테일메이트"
        case .fiftyMove: return "50수 규칙"
        case .threefold: return "같은 국면 3회 반복"
        case .insufficientMaterial: return "메이트할 기물이 없어요"
        case .agreement: return "무승부에 합의했어요"
        case .abandoned:
            return side(loser).map { "\($0)이 더 둘 수 없게 됐어요" } ?? "더 둘 수 없게 됐어요"
        }
    }

    /// 판 전체를 읽는 보이스오버 한 줄(교차점·칸별 요소를 만들지 않는다 — 64칸을 하나씩 읽히면 못 쓴다).
    static func boardAccessibility(ply: Int, turn: ChessColor?, inCheck: Bool) -> String {
        var text = "체스판, \(ply)수 진행"
        if let turn { text += ", \(stoneName(turn)) 차례" }
        if inCheck { text += ", 체크" }
        return text
    }
}

// MARK: - 판 좌표

/// 판 그림의 좌표계. 순수 값 — 클릭 위치 ↔ 칸 변환을 결정적으로 잰다.
///
/// 오목(`GomokuBoardGeometry`)과 **다른 점 둘**:
///  ① 좌표가 교차점이 아니라 **칸**이다. 그래서 `square(at:)` 은 "가장 가까운 점 ±0.5" 가 아니라
///     "그 칸 안쪽인가" 로 판정한다(칸 밖은 nil).
///  ② `orientation` 이 있다. 체스는 **내 색이 아래**에 와야 읽을 수 있다 — 흑으로 두는 사람에게 백을
///     아래 그리면 판이 거꾸로 보인다. 오목에는 대응물이 없다(돌 색이 자리를 안 바꾼다).
///
/// 여백이 없다: 칸이 판을 **꽉 채운다**(`cell = side / 8`). 608 은 8 로 나누어떨어져 칸이 76pt 정확이고,
/// 좌표 글자(a~h · 1~8)는 테두리가 아니라 **가장자리 칸 안**에 그린다(chess.com 과 같은 관례) —
/// 테두리를 두면 칸이 76 에서 떨어져 나와 격자에 반 픽셀 이음선이 생긴다.
struct ChessBoardGeometry: Equatable {
    /// 그림 한 변(pt).
    let side: CGFloat
    /// 아래쪽에 오는 색(= 내 색). 기본은 백.
    var orientation: ChessColor = .white

    static let files = 8
    static let ranks = 8

    var cell: CGFloat { side / CGFloat(Self.files) }

    /// 그 칸의 화면 열(0 = 왼쪽).
    func column(of square: ChessSquare) -> Int {
        orientation == .white ? square.file : Self.files - 1 - square.file
    }

    /// 그 칸의 화면 행(0 = 맨 위).
    func row(of square: ChessSquare) -> Int {
        orientation == .white ? Self.ranks - 1 - square.rank : square.rank
    }

    func rect(of square: ChessSquare) -> CGRect {
        CGRect(x: CGFloat(column(of: square)) * cell, y: CGFloat(row(of: square)) * cell,
               width: cell, height: cell)
    }

    func center(of square: ChessSquare) -> CGPoint {
        let box = rect(of: square)
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// 화면 위치가 든 칸(판 밖이면 nil). **반 칸 관용이 없다** — 칸 안이 아니면 아무 칸도 아니다.
    func square(at location: CGPoint) -> ChessSquare? {
        guard location.x >= 0, location.y >= 0, location.x < side, location.y < side else { return nil }
        let column = min(Self.files - 1, Int(location.x / cell))
        let row = min(Self.ranks - 1, Int(location.y / cell))
        let file = orientation == .white ? column : Self.files - 1 - column
        let rank = orientation == .white ? Self.ranks - 1 - row : row
        return ChessSquare(file: file, rank: rank)
    }
}

// MARK: - 말 그림(벡터)

/// 고전 체스 기물 여섯 종의 **벡터 실루엣**. 단위 사각형(0…1, y 는 위가 0) 안에 적고 칸에 맞춰 늘린다.
///
/// 왜 벡터인가: 유니코드 글리프(♔♕♖♗♘♙)는 설치된 폰트가 정한다 — 폰트마다 굵기·세로 중심·속 빈 정도가
/// 달라지고(어떤 폰트는 흑 기물만 속을 채운다) 체스 폰트가 없는 맥에서는 두부(􀀀)가 된다. 판에서 폰과
/// 비숍을 못 가리는 그림은 기능 고장이므로 모양을 우리가 쥔다.
///
/// 각 말은 **칸 가운데를 반드시 덮는다**(렌더 검증이 칸 중앙 50% 상자에서 잉크를 센다 — 폰이 작아 가운데가
/// 비면 "말이 안 그려졌다"와 구분되지 않는다).
enum ChessPieceArt {
    /// 말이 차지하는 칸 안 비율(나머지는 칸 여백). 0.86 = 76pt 칸에서 65pt 말.
    static let fillFraction: CGFloat = 0.86

    /// 칸 사각형 안에서 말이 그려지는 상자.
    static func box(in cell: CGRect) -> CGRect {
        let side = min(cell.width, cell.height) * fillFraction
        return CGRect(x: cell.midX - side / 2, y: cell.midY - side / 2, width: side, height: side)
    }

    /// 그 말의 채움 경로(여러 조각이 한 Path 에 들어간다 — nonZero 로 채우면 합쳐진다).
    static func path(for kind: ChessPieceKind, in cell: CGRect) -> Path {
        let frame = box(in: cell)
        var path = Path()

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: frame.minX + x * frame.width, y: frame.minY + y * frame.height)
        }
        func addRect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, radius: CGFloat = 0) {
            let origin = point(x0, y0), far = point(x1, y1)
            let box = CGRect(x: origin.x, y: origin.y, width: far.x - origin.x, height: far.y - origin.y)
            if radius > 0 {
                let r = radius * frame.width
                path.addRoundedRect(in: box, cornerSize: CGSize(width: r, height: r), style: .continuous)
            } else {
                path.addRect(box)
            }
        }
        func addCircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            let c = point(cx, cy)
            let radius = r * frame.width
            path.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        func addPolygon(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            path.move(to: point(first.0, first.1))
            for p in points.dropFirst() { path.addLine(to: point(p.0, p.1)) }
            path.closeSubpath()
        }

        switch kind {
        case .pawn:
            addRect(0.22, 0.80, 0.78, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.30, 0.80), (0.70, 0.80), (0.60, 0.50), (0.40, 0.50)])  // 몸통
            addCircle(0.50, 0.37, 0.155)                           // 머리
        case .rook:
            addRect(0.17, 0.80, 0.83, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.25, 0.80), (0.75, 0.80), (0.69, 0.40), (0.31, 0.40)])  // 몸통
            addRect(0.21, 0.30, 0.79, 0.41)                        // 어깨 띠
            addRect(0.21, 0.15, 0.34, 0.31)                        // 성벽 셋
            addRect(0.435, 0.15, 0.565, 0.31)
            addRect(0.66, 0.15, 0.79, 0.31)
        case .knight:
            addRect(0.18, 0.80, 0.82, 0.91, radius: 0.04)          // 받침
            addPolygon([                                            // 말 머리 옆모습(오른쪽을 본다)
                (0.24, 0.80), (0.76, 0.80), (0.76, 0.70), (0.68, 0.60),
                (0.74, 0.46), (0.82, 0.34), (0.74, 0.20), (0.58, 0.12),
                (0.46, 0.14), (0.42, 0.24), (0.28, 0.32), (0.20, 0.44),
                (0.34, 0.50), (0.44, 0.44), (0.40, 0.58), (0.30, 0.70)
            ])
        case .bishop:
            addRect(0.19, 0.80, 0.81, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.28, 0.80), (0.72, 0.80), (0.62, 0.52), (0.38, 0.52)])  // 몸통
            addRect(0.33, 0.45, 0.67, 0.53, radius: 0.03)          // 목 띠
            addPolygon([                                            // 주교관(미트라)
                (0.50, 0.12), (0.64, 0.30), (0.66, 0.46), (0.34, 0.46), (0.36, 0.30)
            ])
            addCircle(0.50, 0.10, 0.055)                           // 꼭지
        case .queen:
            addRect(0.15, 0.80, 0.85, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.25, 0.80), (0.75, 0.80), (0.67, 0.47), (0.33, 0.47)])  // 몸통
            addRect(0.27, 0.40, 0.73, 0.48, radius: 0.03)          // 목 띠
            addPolygon([                                            // 다섯 뿔 왕관
                (0.21, 0.40), (0.17, 0.19), (0.31, 0.31), (0.38, 0.15),
                (0.50, 0.29), (0.62, 0.15), (0.69, 0.31), (0.83, 0.19), (0.79, 0.40)
            ])
            for tip in [(0.17, 0.17), (0.38, 0.13), (0.50, 0.27), (0.62, 0.13), (0.83, 0.17)] {
                addCircle(tip.0, tip.1, 0.05)                      // 뿔 끝 구슬
            }
        case .king:
            addRect(0.15, 0.80, 0.85, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.25, 0.80), (0.75, 0.80), (0.67, 0.45), (0.33, 0.45)])  // 몸통
            addRect(0.27, 0.38, 0.73, 0.46, radius: 0.03)          // 목 띠
            addPolygon([(0.27, 0.38), (0.31, 0.24), (0.50, 0.33), (0.69, 0.24), (0.73, 0.38)])  // 왕관
            addRect(0.455, 0.05, 0.545, 0.25)                      // 십자가 세로
            addRect(0.37, 0.10, 0.63, 0.175)                       // 십자가 가로
        }
        return path
    }
}

// MARK: - 판 그림

/// 8×8 판을 Canvas **한 장**으로 그린다. 입력을 받지 않는 순수 그림이다 — 클릭·호버는 감싸는 쪽이 한다.
///
/// 색 상수가 **렌더 테스트의 감지기**다. 규칙 하나를 지켜야 그 감지기가 산다:
/// **칸 색과 덮개(마지막 수·선택·체크·도착 점)는 전부 중간 톤**이고 **말만 극단**이다(아주 밝거나 아주 어둡다).
/// 그래서 "칸 가운데에 최대 채널 ≥ 235 이거나 최소 채널 ≤ 55 인 픽셀이 있는가" 가 곧 "말이 그려졌는가" 다.
/// 덮개 색을 극단으로 바꾸면 **빈 칸이 말로 세어져** 32개 단언이 조용히 쓸모없어진다.
struct ChessBoardView: View {
    let position: ChessPosition?
    let geometry: ChessBoardGeometry
    var lastMove: ChessMove? = nil
    /// 고른 말의 칸.
    var selected: ChessSquare? = nil
    /// 고른 말이 갈 수 있는 칸들.
    var targets: Set<ChessSquare> = []
    /// 체크를 받은 쪽 왕의 칸(빨간 덮개).
    var checkSquare: ChessSquare? = nil
    /// 마우스가 올라간 칸(옅은 덮개 — 입력이 있는 판에서만 온다).
    var hovered: ChessSquare? = nil
    var showsCoordinates: Bool = true

    // 칸 — 둘 다 중간 톤(최대 ≤ 204 · 최소 ≥ 71)이다.
    static let lightSquare = Color(red: 0.80, green: 0.72, blue: 0.60)
    static let darkSquare = Color(red: 0.44, green: 0.35, blue: 0.28)
    // 말 — **여기만 극단**이다.
    static let whitePiece = Color(white: 0.96)
    static let whitePieceEdge = Color(white: 0.10)
    static let blackPiece = Color(white: 0.10)
    static let blackPieceEdge = Color(white: 0.90)
    // 덮개 — 전부 중간 톤으로 떨어지는 불투명도를 골랐다(위 ★).
    static let lastMoveTint = CheckTheme.pending
    static let lastMoveOpacity: Double = 0.35
    static let selectedTint = CheckTheme.accent
    static let selectedOpacity: Double = 0.35
    static let targetTint = CheckTheme.accent
    static let targetOpacity: Double = 0.60
    static let checkTint = CheckTheme.danger
    static let checkOpacity: Double = 0.45
    static let hoverOpacity: Double = 0.14

    var body: some View {
        Canvas { context, _ in
            draw(in: &context)
        }
        .frame(width: geometry.side, height: geometry.side)
    }

    private func draw(in context: inout GraphicsContext) {
        let g = geometry
        // ① 칸 64개
        for index in 0..<64 {
            guard let square = ChessSquare(index: index) else { continue }
            let box = g.rect(of: square)
            context.fill(Path(box), with: .color(square.isLightSquare ? Self.lightSquare : Self.darkSquare))
        }

        // ② 덮개 — 마지막 수 → 호버 → 선택 → 체크 순(뒤가 위에 온다).
        if let lastMove {
            for square in [lastMove.from, lastMove.to] {
                context.fill(Path(g.rect(of: square)),
                             with: .color(Self.lastMoveTint.opacity(Self.lastMoveOpacity)))
            }
        }
        if let hovered, hovered != selected {
            context.fill(Path(g.rect(of: hovered)), with: .color(Color.white.opacity(Self.hoverOpacity)))
        }
        if let selected {
            context.fill(Path(g.rect(of: selected)),
                         with: .color(Self.selectedTint.opacity(Self.selectedOpacity)))
        }
        if let checkSquare {
            context.fill(Path(g.rect(of: checkSquare)),
                         with: .color(Self.checkTint.opacity(Self.checkOpacity)))
        }

        // ③ 좌표(가장자리 칸 안쪽 — 테두리를 두지 않는다)
        if showsCoordinates {
            let size = max(8, g.cell * 0.17)
            for file in 0..<8 {
                let rank = g.orientation == .white ? 0 : 7
                guard let square = ChessSquare(file: file, rank: rank) else { continue }
                let box = g.rect(of: square)
                let letter = String(UnicodeScalar(UInt8(97 + file)))
                context.draw(
                    Text(letter).font(.system(size: size, weight: .bold))
                        .foregroundStyle(square.isLightSquare ? Self.darkSquare : Self.lightSquare),
                    at: CGPoint(x: box.maxX - size * 0.55, y: box.maxY - size * 0.6), anchor: .center)
            }
            for rank in 0..<8 {
                let file = g.orientation == .white ? 0 : 7
                guard let square = ChessSquare(file: file, rank: rank) else { continue }
                let box = g.rect(of: square)
                context.draw(
                    Text("\(rank + 1)").font(.system(size: size, weight: .bold))
                        .foregroundStyle(square.isLightSquare ? Self.darkSquare : Self.lightSquare),
                    at: CGPoint(x: box.minX + size * 0.6, y: box.minY + size * 0.6), anchor: .center)
            }
        }

        // ④ 갈 수 있는 칸 — 빈 칸은 점, 잡는 칸은 고리(점을 말 위에 찍으면 무엇을 잡는지 가린다).
        for target in targets {
            let box = g.rect(of: target)
            let occupied = position?[target] != nil
            if occupied {
                let inset = g.cell * 0.07
                context.stroke(Path(ellipseIn: box.insetBy(dx: inset, dy: inset)),
                               with: .color(Self.targetTint.opacity(Self.targetOpacity)),
                               lineWidth: g.cell * 0.09)
            } else {
                let r = g.cell * 0.15
                context.fill(
                    Path(ellipseIn: CGRect(x: box.midX - r, y: box.midY - r, width: r * 2, height: r * 2)),
                    with: .color(Self.targetTint.opacity(Self.targetOpacity)))
            }
        }

        // ⑤ 말 — 맨 위에 그린다(덮개가 말을 가리면 무엇이 서 있는지 모른다).
        guard let position else { return }
        for index in 0..<64 {
            guard let square = ChessSquare(index: index), let piece = position[square] else { continue }
            let path = ChessPieceArt.path(for: piece.kind, in: g.rect(of: square))
            context.fill(path, with: .color(piece.color == .white ? Self.whitePiece : Self.blackPiece))
            context.stroke(path,
                           with: .color(piece.color == .white ? Self.whitePieceEdge : Self.blackPieceEdge),
                           lineWidth: max(0.8, g.cell * 0.035))
        }
    }
}

// MARK: - 입력이 있는 판

/// 대국 화면의 판. 탭·호버만 얹고 그림은 `ChessBoardView` 를 그대로 쓴다.
///
/// **조용히 삼키는 길은 판 밖 하나뿐**이고 나머지 거절은 전부 스토어(`tap(_:)`)가 문구+로그를 남긴다 —
/// 뭉친 무음 guard 가 오목에서 "눌렀는데 반응 없음" 의 원인이었다.
struct ChessPlayBoard: View {
    let store: ChessStore
    let match: ChessMatchState

    @State private var hovered: ChessSquare?

    private var geometry: ChessBoardGeometry {
        ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: match.myColor)
    }

    /// 체크를 받은 쪽 왕의 칸. 끝난 판은 없다.
    private var checkSquare: ChessSquare? {
        guard match.isInCheck, !match.isFinished, let turn = match.turn else { return nil }
        return match.position?.kingSquare(of: turn)
    }

    private var canTap: Bool { match.isMyTurn && !store.isBusy }

    var body: some View {
        let g = geometry
        ChessBoardView(
            position: match.position,
            geometry: g,
            lastMove: match.lastMove,
            selected: store.selection?.from,
            targets: store.selection?.targets ?? [],
            checkSquare: checkSquare,
            hovered: canTap ? hovered : nil
        )
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard canTap else { if hovered != nil { hovered = nil }; return }
            switch phase {
            case .active(let location):
                let square = g.square(at: location)
                if hovered != square { hovered = square }
            case .ended:
                if hovered != nil { hovered = nil }
            }
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                // 판 밖은 조용히 흘린다(그 자리에는 아무 칸도 없다). 그 밖의 거절은 스토어가 말한다.
                guard let square = g.square(at: value.location) else { return }
                Task { await store.tap(square) }
            }
        )
        .onChange(of: match.id) { _, _ in hovered = nil }
        .onChange(of: match.plyCount) { _, _ in hovered = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChessText.boardAccessibility(ply: match.plyCount, turn: match.turn,
                                                         inCheck: match.isInCheck))
    }
}

// MARK: - 창 루트

struct ChessPanel: View {
    let store: ChessStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다).
    var me: @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback }
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용: 판돈 창을 이 상대에게 띄운 채로 그린다. 앱은 언제나 nil.
    var previewStakeTarget: ChessUser? = nil
    /// 스냅샷 전용: 판돈 창에서 이 판돈을 고른 상태로 그린다. 앱은 nil.
    var previewStakeSelection: ChessStake? = nil
    /// 스냅샷 전용: [기권] 자리를 확인 상태로 그린다. 앱은 false.
    var previewConfirmResign: Bool = false
    /// 스냅샷 전용: 로봇 색 고르기 창을 띄운 채로 그린다. 앱은 false.
    var previewAIPrompt: Bool = false
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳(앱 배선이 `WorkTimerStore` 를 넘긴다). nil 이면 이니셜로 떨어진다.
    var safety: WorkTimerStore? = nil

    @State private var confirmResign = false
    /// [도전]을 누른 상대 — 판돈 창이 이 값으로 열린다. nil 이면 닫혀 있다.
    @State private var stakeTarget: ChessUser?
    /// 머리글 [로봇과 두기] 를 눌렀다 — 색 고르기 창이 뜬다.
    @State private var aiPromptVisible = false

    private var activeStakeTarget: ChessUser? { stakeTarget ?? previewStakeTarget }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: ChessWindowLayout.headerSpacing) {
                ChessHeader(store: store, onAIMatch: { aiPromptVisible = true })
                    .frame(height: ChessWindowLayout.headerHeight)
                content
                    .frame(width: ChessWindowLayout.innerSize.width, height: ChessWindowLayout.bodyHeight,
                           alignment: .topLeading)
            }
            .padding(ChessWindowLayout.contentPadding)
            // 덮개는 **한 번에 하나**다. 승격이 맨 앞이다 — 승격을 묻는 동안에는 다른 덮개를 열 길이 없고
            // (판·머리글이 덮여 있다) 그 단계를 미뤄 두면 수가 영영 안 나간다.
            if let prompt = store.promotion {
                ChessPromotionSheet(store: store, prompt: prompt, myColor: store.match?.myColor ?? .white)
            } else if store.isRulesVisible {
                ChessRulesOverlay(store: store, onClose: { store.isRulesVisible = false })
            } else if let target = activeStakeTarget {
                ChessStakePrompt(store: store, target: target, initialSelection: previewStakeSelection,
                                 onClose: { stakeTarget = nil })
            } else if aiPromptVisible || previewAIPrompt {
                ChessAIPrompt(store: store, onClose: { aiPromptVisible = false })
            }
        }
        .frame(width: ChessWindowLayout.contentSize.width, height: ChessWindowLayout.contentSize.height,
               alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        // 툴팁 말풍선 레이어 — 창 루트 하나(새 창 루트에는 이 한 줄이 반드시 있어야 말풍선이 뜬다).
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표. nil 이면 빈 표 = 모르는 사람은 착용값·그마저 없으면 이니셜.
        .appUserAvatarCharacters(from: safety)
        .onChange(of: store.match?.id) { _, _ in
            confirmResign = false
            // 판이 시작되면 로비가 사라진다 — 열려 있던 판돈 창을 들고 있으면 로비로 돌아올 때 되살아난다.
            stakeTarget = nil
            aiPromptVisible = false
        }
        // 기권 확인은 **그 판 그 화면에서 연 것**만 산다. 화면이 바뀌거나 창이 내려갔다 다시 뜨면 접는다.
        .onChange(of: store.phase) { _, _ in confirmResign = false }
        .onChange(of: store.isWindowVisible) { _, _ in confirmResign = false }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .playing:
            if let match = store.match { playing(match) } else { lobby }
        case .result:
            if let match = store.match { result(match) } else { lobby }
        case .lobby:
            // 관전은 로비 자리에 선다 — `phase` 는 `.lobby` 그대로이고 `spectating` 하나가 화면을 가른다.
            if let watch = store.spectating { spectate(watch) } else { lobby }
        }
    }

    // MARK: 로비

    /// 로비는 **세 열**이다: 상대 목록 420 · 순위 340 · 오른쪽 400.
    private var lobby: some View {
        HStack(alignment: .top, spacing: ChessWindowLayout.columnSpacing) {
            ChessOpponentList(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                              onChallenge: { stakeTarget = $0 })
                .frame(width: ChessWindowLayout.lobbyUsersWidth, height: ChessWindowLayout.bodyHeight, alignment: .top)
                .clipped()
            ChessRankColumn(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ChessWindowLayout.lobbyRankWidth, height: ChessWindowLayout.bodyHeight, alignment: .top)
                .clipped()
            ChessLobbySide(store: store, me: me(), clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ChessWindowLayout.lobbySideWidth, height: ChessWindowLayout.bodyHeight, alignment: .top)
                .clipped()
        }
    }

    // MARK: 관전

    /// 관전은 대국과 같은 **두 열**이다. 판은 입력이 없다(탭·호버·선택·도착 점이 하나도 없다 — 관전자는
    /// 아무것도 쓰지 못한다). 판 방향은 **흑이 아래가 아니다** — 관전자에게는 백이 아래가 관례다.
    private func spectate(_ watch: ChessSpectateState) -> some View {
        HStack(alignment: .top, spacing: ChessWindowLayout.columnSpacing) {
            ChessBoardView(
                position: watch.position,
                geometry: ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .white),
                lastMove: watch.lastMove,
                checkSquare: watch.isInCheck && !watch.isFinished
                    ? watch.turn.flatMap { watch.position?.kingSquare(of: $0) } : nil
            )
            .frame(width: ChessWindowLayout.boardSide, height: ChessWindowLayout.boardSide)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ChessText.boardAccessibility(ply: watch.plyCount, turn: watch.turn,
                                                             inCheck: watch.isInCheck))
            ChessSpectateSide(store: store, watch: watch,
                              clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ChessWindowLayout.sideColumnWidth, height: ChessWindowLayout.bodyHeight, alignment: .top)
                .clipped()
        }
    }

    // MARK: 대국

    private func playing(_ match: ChessMatchState) -> some View {
        HStack(alignment: .top, spacing: ChessWindowLayout.columnSpacing) {
            ChessPlayBoard(store: store, match: match)
                .frame(width: ChessWindowLayout.boardSide, height: ChessWindowLayout.boardSide)
            ChessMatchSide(
                store: store, match: match, me: me(),
                confirmResign: $confirmResign,
                showsConfirmPreview: previewConfirmResign,
                clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll
            )
            .frame(width: ChessWindowLayout.sideColumnWidth, height: ChessWindowLayout.bodyHeight, alignment: .top)
            .clipped()
        }
    }

    // MARK: 결과

    private func result(_ match: ChessMatchState) -> some View {
        HStack(alignment: .top, spacing: ChessWindowLayout.columnSpacing) {
            ChessBoardView(
                position: match.position,
                geometry: ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: match.myColor),
                lastMove: match.lastMove
            )
            .frame(width: ChessWindowLayout.boardSide, height: ChessWindowLayout.boardSide)
            VStack(alignment: .leading, spacing: ChessWindowLayout.matchSideSpacing) {
                ChessResultCard(store: store, match: match)
                    .fixedSize(horizontal: false, vertical: true)
                ChessMoveListCard(moves: match.moves, highlightSeq: match.moves.last?.seq,
                                  clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            .frame(width: ChessWindowLayout.sideColumnWidth, height: ChessWindowLayout.bodyHeight, alignment: .top)
            .clipped()
        }
    }
}

// MARK: - 머리글

private struct ChessHeader: View {
    let store: ChessStore
    var onAIMatch: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(0.18))
                Image(systemName: ChessEntryIcon.resolved)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(ChessText.title).font(.title3.weight(.bold))
                Text(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                Text(recordLine).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            .checkTooltip(ChessText.rankHelp)
            RubyBalanceChip(balance: store.rubyBalance, large: true)
                .checkTooltip("내 루비")
            // 로비에서만 선다 — 판 중에 새 판을 열 길을 두지 않는다. 관전 중에도 숨긴다(로봇 판이 서면
            // 관전이 내려가는데, 보고 있던 판을 버튼 하나로 잃게 두지 않는다).
            if store.phase == .lobby, store.spectating == nil {
                ChessActionButton(title: ChessText.aiButton, icon: "cpu", style: .outline, height: 30,
                                  isEnabled: store.canStartAIMatch, action: onAIMatch)
                    .checkTooltip(ChessText.aiButtonHelp)
            }
            ChessActionButton(title: ChessText.rulesButton, icon: "book.fill", style: .outline, height: 30) {
                store.isRulesVisible = true
            }
            .checkTooltip("체스 규칙을 봐요")
        }
    }

    /// 전적 캡슐 글자 — **한 출처**. 순위 응답의 `me` 가 로비 전적과 같을 때만 전적·순위·승점을 전부 그 값으로
    /// 그린다(두 출처를 섞으면 "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다).
    private var recordLine: String {
        guard let mine = store.myRankConsistentWithRecord else { return ChessText.record(store.record) }
        let record = ChessText.record(wins: mine.wins, losses: mine.losses, draws: mine.draws)
        guard let rank = mine.rank else { return record }
        return "\(record) · \(ChessText.myRank(rank: rank, points: mine.points))"
    }
}

// MARK: - 로비: 상대 목록

private struct ChessOpponentList: View {
    let store: ChessStore
    let clipsOverflowInsteadOfScroll: Bool
    /// [도전]을 누른 상대를 창 루트로 올린다 — 판돈 창은 **창 가운데**에 서야 해서 행이 직접 못 띄운다.
    let onChallenge: (ChessUser) -> Void

    static let rowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 6

    /// 근무 중·가능한 사람 먼저(서버 순서는 그 안에서 유지). 차단해 걷어낸 사람은 곧바로 빠진다.
    private var sortedUsers: [ChessUser] {
        store.visibleUsers.enumerated().sorted { lhs, rhs in
            let a = Self.rank(lhs.element), b = Self.rank(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }

    static func rank(_ user: ChessUser) -> Int {
        if user.isCapable && user.isWorking && !user.inMatch { return 0 }
        if user.inMatch { return 1 }
        if user.isCapable { return 2 }
        return 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(ChessText.lobbyTitle).font(.headline)
                Spacer()
                Text(ChessText.lobbyCaption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            if store.visibleUsers.isEmpty {
                Text(failedOrEmptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.lobbyLoadFailed {
                    ChessActionButton(title: ChessText.reloadUsers, icon: "arrow.clockwise",
                                      style: .outline, height: 30, fullWidth: true) {
                        Task { await store.refreshLobby() }
                    }
                }
            } else {
                ChessScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(sortedUsers) { user in
                            ChessOpponentRow(user: user, isBusy: store.isBusy,
                                             onChallenge: { onChallenge(user) })
                                .frame(height: Self.rowHeight)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }

    private var failedOrEmptyText: String {
        if store.lobbyLoadFailed { return ChessText.usersLoadFailed }
        return store.hasLoadedLobby ? ChessText.emptyUsers : ChessText.loadingUsers
    }
}

private struct ChessOpponentRow: View {
    let user: ChessUser
    let isBusy: Bool
    let onChallenge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: user.displayName, userID: user.id,
                            avatarURL: user.avatarURL.flatMap(URL.init(string:)), size: 34,
                            center: user.center, characterHint: user.characterID)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ChessActionButton(title: ChessText.challenge, height: 28, isEnabled: canChallenge, action: onChallenge)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    private var canChallenge: Bool { user.isCapable && !user.inMatch && !isBusy }

    private var statusLine: String {
        if !user.isCapable { return ChessText.needsUpdate }
        if user.inMatch { return ChessText.inMatch }
        return user.isWorking ? ChessText.working : "—"
    }
}

// MARK: - 로비: 순위 열

private struct ChessRankColumn: View {
    let store: ChessStore
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ChessWindowLayout.rankHeaderSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(ChessText.rankTitle).font(.headline)
                Spacer(minLength: 4)
                if let since = store.ranking?.recordSince {
                    Text(ChessText.rankSince(since))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(height: ChessWindowLayout.rankHeaderHeight)
            if let board = store.ranking, !board.entries.isEmpty {
                ChessScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: ChessWindowLayout.rankRowSpacing) {
                        ForEach(board.entries) { entry in
                            ChessRankRow(entry: entry, isMe: entry.user.id == store.myUserID)
                                .frame(height: ChessWindowLayout.rankRowHeight)
                        }
                    }
                }
                .frame(height: ChessWindowLayout.rankListHeight, alignment: .top)
            } else {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }

    private var emptyText: String {
        if store.rankingUnavailable { return ChessText.rankSoon }
        if store.rankingLoadFailed, !store.hasLoadedRanking { return ChessText.rankFailed }
        if !store.hasLoadedRanking { return ChessText.rankLoading }
        return ChessText.rankEmpty
    }
}

private struct ChessRankRow: View {
    let entry: ChessRankEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(entry.rank <= 3 ? CheckTheme.pending : CheckTheme.secondaryText)
            CheckAvatarView(name: entry.user.displayName, userID: entry.user.id,
                            avatarURL: entry.user.avatarURL.flatMap(URL.init(string:)), size: 22,
                            center: entry.user.center, characterHint: entry.user.characterID)
            Text(entry.user.displayName)
                .font(.caption.weight(isMe ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(ChessText.points(entry.points))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Text(ChessText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
            }
            .frame(width: ChessWindowLayout.rankTrailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isMe ? CheckTheme.accent.opacity(0.14) : Color.white.opacity(0.03))
        )
    }
}

// MARK: - 로비: 오른쪽 열

private struct ChessLobbySide: View {
    let store: ChessStore
    let me: ChessPlayerFace
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ChessWindowLayout.lobbySideSpacing) {
            ChessRecordCard(store: store, me: me)
                .frame(height: ChessWindowLayout.lobbyRecordHeight)
            liveBox
                .frame(height: ChessWindowLayout.lobbyLiveHeight)
            // ★ 예산을 **넘기면 잘린다**(부모 열이 `.clipped()` 다). VStack 은 부족한 높이를 위아래로 균등히
            //   흘리므로 위로 넘친 만큼 아래로도 새고, 그 아래쪽이 안내 줄의 마지막 글자다.
            ChessLobbyInvitesBox(store: store)
                .frame(maxHeight: ChessWindowLayout.lobbyInvitesMaxHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ChessText.liveTitle).font(.headline)
            if store.liveMatches.isEmpty {
                Text(ChessText.noLive)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ChessScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: 6) {
                        ForEach(store.liveMatches) { live in
                            ChessLiveRow(
                                live: live,
                                isMine: store.isMine(live),
                                // ★ 관전 입구의 잠금은 `watchUnavailable` **하나**로만 판정한다.
                                //   `rankingUnavailable` 을 같이 보면 깃발 겸업 사고가 그대로 재현된다.
                                canWatch: !store.watchUnavailable,
                                onWatch: { store.startWatching(matchID: live.id) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }

}

/// 로비 오른쪽 열 맨 아래 — 받은 신청 1장 + 보낸 신청 줄 + 안내 줄.
///
/// **내부 타입이다**(private 아님). 세로 예산(`lobbyInvitesMaxHeight`)이 이 칸의 **실제** 자연 높이를 덮는지는
/// 상수끼리의 산수로는 알 수 없다 — 테스트가 이 뷰를 예산 안에서 한 번, 자연 높이로 한 번 그려 잉크를 견준다.
struct ChessLobbyInvitesBox: View {
    let store: ChessStore

    var body: some View {
        VStack(alignment: .leading, spacing: ChessWindowLayout.lobbyInvitesSpacing) {
            Text(ChessText.incomingTitle).font(.headline)
                .frame(height: ChessWindowLayout.lobbyInvitesTitleHeight)
            if let invite = store.visibleIncoming {
                ChessInviteCard(store: store, invite: invite)
            } else {
                Text(ChessText.noIncoming)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            if let outgoing = store.outgoing {
                ChessOutgoingLine(store: store, invite: outgoing)
            }
            if let notice = store.notice {
                ChessNoticeLine(text: notice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .chessCard()
    }
}

/// 내 전적 카드(로비 오른쪽 맨 위). 순위 응답과 **같은 출처**를 쓴다(머리글 캡슐과 같은 규칙).
private struct ChessRecordCard: View {
    let store: ChessStore
    let me: ChessPlayerFace

    var body: some View {
        HStack(spacing: 10) {
            CharacterPortrait(characterID: me.characterID)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(ChessText.recordTitle)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(ChessText.record(store.record))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if let mine = store.myRankConsistentWithRecord {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ChessText.points(mine.points))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                    if let rank = mine.rank {
                        Text("\(rank)위")
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .chessCard(padding: 12)
    }
}

private struct ChessLiveRow: View {
    let live: ChessLiveMatch
    let isMine: Bool
    let canWatch: Bool
    let onWatch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CheckAvatarView(name: live.a.displayName, userID: live.a.id,
                            avatarURL: live.a.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.a.characterID)
            Text(live.a.displayName).font(.caption2).lineLimit(1)
            Text("vs").font(.caption2).foregroundStyle(CheckTheme.secondaryText)
            CheckAvatarView(name: live.b.displayName, userID: live.b.id,
                            avatarURL: live.b.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.b.characterID)
            Text(live.b.displayName).font(.caption2).lineLimit(1)
            Spacer(minLength: 4)
            if isMine {
                Text(ChessText.myMatch)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(height: ChessWindowLayout.liveWatchChipHeight)
            } else {
                Button(action: onWatch) {
                    Text(ChessText.watch)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .padding(.horizontal, 8)
                        .frame(height: ChessWindowLayout.liveWatchChipHeight)
                        .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canWatch)
                .opacity(canWatch ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

private struct ChessInviteCard: View {
    let store: ChessStore
    let invite: ChessInvite

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CheckAvatarView(name: invite.peer.displayName, userID: invite.peer.id,
                                avatarURL: invite.peer.avatarURL.flatMap(URL.init(string:)), size: 28,
                                center: invite.peer.center, characterHint: invite.peer.characterID)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(invite.peer.displayName)님의 신청")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(ChessText.stakeLine(invite.stake))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                ChessCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible)
            }
            HStack(spacing: 8) {
                ChessActionButton(title: ChessText.accept, height: 30, fullWidth: true,
                                  isEnabled: !store.isBusy) {
                    Task { await store.respond(inviteID: invite.id, accept: true) }
                }
                ChessActionButton(title: ChessText.decline, tint: CheckTheme.offWork, style: .outline,
                                  height: 30, fullWidth: true, isEnabled: !store.isBusy) {
                    Task { await store.respond(inviteID: invite.id, accept: false) }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CheckTheme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CheckTheme.accent.opacity(0.4), lineWidth: 1))
    }
}

private struct ChessOutgoingLine: View {
    let store: ChessStore
    let invite: ChessInvite

    var body: some View {
        HStack(spacing: 8) {
            Text("\(ChessText.outgoingTitle) · \(invite.peer.displayName)")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            ChessCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible)
            Spacer(minLength: 4)
            ChessActionButton(title: ChessText.cancel, tint: CheckTheme.offWork, style: .outline,
                              height: 26, isEnabled: !store.isBusy) {
                Task { await store.cancelChallenge() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }
}

// MARK: - 대국 오른쪽 열

private struct ChessMatchSide: View {
    let store: ChessStore
    let match: ChessMatchState
    let me: ChessPlayerFace
    @Binding var confirmResign: Bool
    let showsConfirmPreview: Bool
    let clipsOverflowInsteadOfScroll: Bool

    private var showsConfirm: Bool { confirmResign || showsConfirmPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: ChessWindowLayout.matchSideSpacing) {
            // 위가 **상대**, 아래가 **나**다(판에서 내 색이 아래인 것과 같은 방향 — 눈이 한 번만 배운다).
            ChessPlayerCard(store: store, face: ChessPlayerFace.of(match.opponent),
                            color: match.myColor.opponent, isTurn: match.turn == match.myColor.opponent,
                            isMe: false, isAI: match.opponent.isChessAI,
                            isThinking: store.isAIThinking)
                .frame(height: ChessWindowLayout.playerCardHeight)
            ChessPlayerCard(store: store, face: me, color: match.myColor,
                            isTurn: match.turn == match.myColor, isMe: true, isAI: false, isThinking: false)
                .frame(height: ChessWindowLayout.playerCardHeight)
            HStack(spacing: ChessWindowLayout.matchSideSpacing) {
                ChessStakeChip(stake: store.isAIMatch ? nil : match.stake)
                ChessStatusBox(store: store, match: match)
            }
            .frame(minHeight: ChessWindowLayout.stakeStatusMinHeight)
            ChessMoveListCard(moves: match.moves, highlightSeq: match.moves.last?.seq,
                              clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            actionRow
                .frame(height: ChessWindowLayout.actionRowHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var actionRow: some View {
        if match.isFinished {
            ChessActionButton(title: ChessText.backToLobby, icon: "chevron.left", style: .outline,
                              height: ChessWindowLayout.actionRowHeight, fullWidth: true) {
                store.backToLobby()
            }
        } else if match.drawOfferedByOpponent {
            HStack(spacing: 8) {
                ChessActionButton(title: ChessText.acceptDraw, height: ChessWindowLayout.actionRowHeight,
                                  fullWidth: true, isEnabled: !store.isBusy) {
                    Task { await store.respondDraw(accept: true) }
                }
                ChessActionButton(title: ChessText.declineDraw, tint: CheckTheme.offWork, style: .outline,
                                  height: ChessWindowLayout.actionRowHeight, fullWidth: true,
                                  isEnabled: !store.isBusy) {
                    Task { await store.respondDraw(accept: false) }
                }
            }
        } else if showsConfirm {
            HStack(spacing: 8) {
                ChessActionButton(title: ChessText.confirmResign, tint: CheckTheme.danger,
                                  height: ChessWindowLayout.actionRowHeight, fullWidth: true,
                                  isEnabled: !store.isBusy) {
                    confirmResign = false
                    Task { await store.resign() }
                }
                ChessActionButton(title: ChessText.keepPlaying, tint: CheckTheme.offWork, style: .outline,
                                  height: ChessWindowLayout.actionRowHeight, fullWidth: true) {
                    confirmResign = false
                }
            }
        } else {
            HStack(spacing: 8) {
                ChessActionButton(title: ChessText.resign, icon: "flag.fill", tint: CheckTheme.danger,
                                  style: .outline, height: ChessWindowLayout.actionRowHeight, fullWidth: true) {
                    confirmResign = true
                }
                // 로봇 판에는 무승부 제안이 없다(합의할 상대가 없다 — 서버 왕복이 아예 안 나간다).
                if !store.isAIMatch {
                    ChessActionButton(title: match.drawOfferedByMe ? ChessText.drawOfferedByMe : ChessText.offerDraw,
                                      icon: "equal.circle", tint: CheckTheme.offWork, style: .outline,
                                      height: ChessWindowLayout.actionRowHeight, fullWidth: true,
                                      isEnabled: !store.isBusy && !match.drawOfferedByMe) {
                        Task { await store.offerDraw() }
                    }
                }
            }
        }
    }
}

/// 상태 상자(판돈 줄 오른쪽). 지금 무슨 일이 일어나는지 **글자로** 말한다 — 툴팁은 픽셀을 안 만들어
/// 렌더 검증이 못 보고, 색만으로는 색을 못 보는 사람에게 아무 말도 하지 않는다.
private struct ChessStatusBox: View {
    let store: ChessStore
    let match: ChessMatchState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: ChessWindowLayout.stakeStatusMinHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    private var headline: String {
        if match.isFinished { return ChessText.outcomeTitle(match.outcome) }
        if match.isInCheck { return match.isMyTurn ? ChessText.inCheck : ChessText.opponentInCheck }
        if store.isAIThinking { return ChessText.aiThinking }
        return match.isMyTurn ? ChessText.myTurn : ChessText.opponentTurn
    }

    private var tint: Color {
        if match.isFinished {
            switch match.outcome {
            case .won?: return CheckTheme.working
            case .lost?: return CheckTheme.danger
            default: return CheckTheme.offWork
            }
        }
        if match.isInCheck { return CheckTheme.danger }
        return match.isMyTurn ? CheckTheme.working : CheckTheme.secondaryText
    }

    private var detail: String? {
        if match.isFinished { return ChessText.endReason(match.endReason, outcome: match.outcome) }
        if let notice = store.notice { return notice }
        if match.drawOfferedByOpponent { return ChessText.drawOfferedByOpponent }
        if match.drawOfferedByMe { return ChessText.drawOfferedByMe }
        return nil
    }
}

/// 두 사람 카드 한 장. **시계가 여기 있다** — 카드가 둘이므로 시계도 둘이고, 각자 자기 색의 남은 시간을 읽는다.
private struct ChessPlayerCard: View {
    let store: ChessStore
    let face: ChessPlayerFace
    let color: ChessColor
    let isTurn: Bool
    let isMe: Bool
    let isAI: Bool
    let isThinking: Bool

    var body: some View {
        HStack(spacing: 12) {
            CharacterPortrait(characterID: face.characterID)
                .frame(width: ChessWindowLayout.portraitSide, height: ChessWindowLayout.portraitSide)
                .overlay(alignment: .bottomTrailing) {
                    if let center = face.center {
                        CenterCornerBadge(label: center, avatarSize: ChessWindowLayout.portraitSide)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(face.name)
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isMe {
                        Text("나")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.accent)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                    }
                }
                HStack(spacing: 6) {
                    ChessColorDot(color: color, size: 14)
                    Text(ChessText.stoneName(color))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                    if isAI, isThinking {
                        Text(ChessText.aiThinking)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.pending)
                    }
                }
            }
            .frame(width: ChessWindowLayout.nameColumnWidth, alignment: .leading)
            Spacer(minLength: 4)
            ChessClockLeaf(store: store, color: color, isTurn: isTurn)
                .frame(width: ChessWindowLayout.clockWidth, height: ChessWindowLayout.clockHeight)
        }
        .padding(.horizontal, ChessWindowLayout.cardInsetX)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTurn ? CheckTheme.accent.opacity(0.12) : CheckTheme.panel.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTurn ? CheckTheme.accent.opacity(0.6) : CheckTheme.border, lineWidth: isTurn ? 1.5 : 1)
        )
    }
}

/// 한쪽 시계 — **잎 뷰**다. 초를 읽는 것은 이 뷰의 TimelineView 뿐이고(규약 ⑥) 창이 안 보이면 멈춘다.
/// 시계가 **둘** 있다는 것이 오목과 가장 다른 점이다 — 둘이 같은 값을 보이면 한쪽이 안 그려진 것이다.
struct ChessClockLeaf: View {
    let store: ChessStore
    let color: ChessColor
    let isTurn: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible)) { context in
            let remaining = store.remainingSeconds(color, now: context.date) ?? 0
            ChessClockFace(remaining: remaining, isTurn: isTurn, total: Double(store.initialMs) / 1000)
        }
    }
}

/// 관전 한쪽 시계 — 대국의 `ChessClockLeaf` 와 **같은 규약**의 잎 뷰다. 읽는 곳만 `spectating` 이다.
///
/// 관전 시계가 스스로 흘러야 하는 까닭은 서버가 거짓말을 하기 때문이 아니라 **폴링이 아무것도 안 말해 주기**
/// 때문이다: `chess_watch` 는 `white_ms_left`·`black_ms_left` 를 저장된 값 그대로 싣고 `turn_started_ms` 도
/// 수를 둘 때까지 안 바뀌므로(duel.sql §chess_watch), 상대가 생각하는 동안 폴링 응답은 **매번 같다** —
/// 관찰자가 안 깨어나고 시계는 마지막 수 시각에 굳는다. 보간은 여기서만 살아난다.
struct ChessWatchClockLeaf: View {
    let store: ChessStore
    let color: ChessColor
    let isTurn: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible)) { context in
            // **스토어에서 다시 읽는다** — 값으로 받아 두면 폴링이 깨우지 않는 동안 그 값이 굳는다.
            let remaining = store.spectating?.clock.remainingSeconds(color, now: context.date) ?? 0
            ChessClockFace(remaining: remaining, isTurn: isTurn, total: Double(store.initialMs) / 1000)
        }
    }
}

/// 시계 한 장(남은 초 → 글자 + 띠 + 보이스오버). 대국·관전이 **같은 그림**을 쓴다.
struct ChessClockFace: View {
    let remaining: Double
    let isTurn: Bool
    let total: Double

    var body: some View {
        let fraction = total > 0 ? min(1, max(0, remaining / total)) : 0
        let tint: Color = remaining <= 10 ? CheckTheme.danger
            : (remaining <= 30 ? CheckTheme.pending : (isTurn ? CheckTheme.working : CheckTheme.secondaryText))
        VStack(spacing: 4) {
            Text(ChessText.clock(remaining))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(tint).frame(width: max(1, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isTurn ? Color.white.opacity(0.08) : Color.black.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChessText.clockAccessibility(remaining))
    }
}

/// 색 점(흑·백). 판의 말 색과 **같은 두 색**을 쓴다.
struct ChessColorDot: View {
    let color: ChessColor
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(color == .white ? ChessBoardView.whitePiece : ChessBoardView.blackPiece)
            .overlay(Circle().stroke(color == .white ? ChessBoardView.whitePieceEdge : ChessBoardView.blackPieceEdge,
                                     lineWidth: 1))
            .frame(width: size, height: size)
    }
}

/// 판돈 칩(대국·관전 공용). 판돈을 모르면(관전 첫 응답 전 · 로봇 판) "—".
struct ChessStakeChip: View {
    let stake: Int?
    /// 접미사를 붙이는가. **관전만 false** — 관전자는 이겨도 한 푼도 얻지 못해 그 문장에 주어가 없다.
    var showsReward: Bool = true

    /// 칩이 그릴 글자(순수). 뷰에서 떼어 두어야 테스트가 값으로 되묻는다.
    static func text(stake: Int?, showsReward: Bool) -> String {
        guard let stake else { return ChessText.stakeUnknown }
        return showsReward ? ChessText.stakeLine(stake) : ChessText.watchStakeLine(stake)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(ChessText.stakeTitle).foregroundStyle(CheckTheme.secondaryText)
            RubyIcon(size: 16)
            Text(Self.text(stake: stake, showsReward: showsReward))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(width: 190, alignment: .leading)
        .frame(minHeight: ChessWindowLayout.stakeStatusMinHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

// MARK: - 기보

/// 기보 한 줄(수 번호 · 백 SAN · 흑 SAN). **순수 값** — 짝 짓기를 뷰에서 하면 테스트가 못 잰다.
struct ChessMoveRow: Identifiable, Equatable {
    let number: Int
    var white: ChessMoveRecord?
    var black: ChessMoveRecord?

    var id: Int { number }
}

enum ChessMoveLog {
    /// 수 기록을 화면 줄로 짝 짓는다. **색으로** 짝을 짓는다 — 짝수/홀수 번째로 자르면 흑이 먼저 둔 국면
    /// (서버가 중간 FEN 에서 판을 세운 경우 · 로봇에게 백을 준 판은 아니지만 관전은 그럴 수 있다)에서
    /// 백·흑 칸이 통째로 한 칸씩 밀린다.
    static func rows(_ moves: [ChessMoveRecord]) -> [ChessMoveRow] {
        var rows: [ChessMoveRow] = []
        for record in moves {
            switch record.color {
            case .white:
                rows.append(ChessMoveRow(number: rows.count + 1, white: record, black: nil))
            case .black:
                if var last = rows.last, last.black == nil, last.white != nil {
                    last.black = record
                    rows[rows.count - 1] = last
                } else {
                    rows.append(ChessMoveRow(number: rows.count + 1, white: nil, black: record))
                }
            }
        }
        return rows
    }
}

private struct ChessMoveListCard: View {
    let moves: [ChessMoveRecord]
    let highlightSeq: Int?
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ChessWindowLayout.moveHeaderSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(ChessText.movesTitle).font(.headline)
                Spacer(minLength: 4)
                Text("\(moves.count)수")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
            }
            .frame(height: ChessWindowLayout.moveHeaderHeight)
            if moves.isEmpty {
                Text(ChessText.noMoves)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ChessScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: ChessWindowLayout.moveRowSpacing) {
                        ForEach(ChessMoveLog.rows(moves)) { row in
                            ChessMoveLine(row: row, highlightSeq: highlightSeq)
                                .frame(height: ChessWindowLayout.moveRowHeight)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }
}

private struct ChessMoveLine: View {
    let row: ChessMoveRow
    let highlightSeq: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text("\(row.number).")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: ChessWindowLayout.moveNumberWidth, alignment: .trailing)
            cell(row.white)
            cell(row.black)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ record: ChessMoveRecord?) -> some View {
        let isLast = record != nil && record?.seq == highlightSeq
        Text(record?.san ?? "")
            .font(.caption.weight(isLast ? .bold : .regular))
            .foregroundStyle(isLast ? CheckTheme.accent : CheckTheme.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(width: 76, height: ChessWindowLayout.moveRowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isLast ? CheckTheme.accent.opacity(0.16) : Color.clear)
            )
    }
}

// MARK: - 결과 카드

private struct ChessResultCard: View {
    let store: ChessStore
    let match: ChessMatchState

    private var isAI: Bool { store.isAIMatch }

    private var delta: Int {
        if let rubyDelta = match.rubyDelta { return rubyDelta }
        switch match.outcome {
        case .won?: return match.stake
        case .lost?: return -match.stake
        default: return 0
        }
    }

    private var tint: Color {
        switch match.outcome {
        case .won?: return CheckTheme.working
        case .lost?: return CheckTheme.danger
        default: return CheckTheme.offWork
        }
    }

    private var icon: String {
        switch match.outcome {
        case .won?: return "trophy.fill"
        case .lost?: return "xmark.circle.fill"
        default: return "equal.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChessText.outcomeTitle(match.outcome))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(tint)
                    Text(ChessText.endReason(match.endReason, outcome: match.outcome))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if !isAI {
                    HStack(spacing: 4) {
                        RubyIcon(size: 18)
                        Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(delta > 0 ? CheckTheme.working : (delta < 0 ? CheckTheme.danger : CheckTheme.secondaryText))
                    }
                }
            }
            if isAI {
                Text(ChessText.aiInfo)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            HStack(spacing: 8) {
                if isAI {
                    ChessActionButton(title: ChessText.playAgain, icon: "arrow.clockwise", height: 32,
                                      fullWidth: true) { store.restartAIMatch() }
                }
                ChessActionButton(title: ChessText.backToLobby, icon: "chevron.left", style: .outline,
                                  height: 32, fullWidth: true) { store.backToLobby() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chessCard()
    }
}

// MARK: - 관전 오른쪽 열

private struct ChessSpectateSide: View {
    let store: ChessStore
    let watch: ChessSpectateState
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ChessWindowLayout.matchSideSpacing) {
            // 색은 **서버 응답으로만** 확정한다(추론 금지 — 로비 카드의 a/b 는 uuid 순서이고 색이 아니다).
            // ★ 시계는 **값으로 넘기지 않는다.** 여기서 `watch.clock.remainingSeconds(_, now: Date())` 를 계산해
            //   상수로 주면 관전 시계는 `spectating` 이 갈릴 때만 다시 그려져 2초 폴링 눈금으로 튀고,
            //   `canPollSpectatorFeatures` 가 거짓이 되는 순간(가림 통지·세션·주 스위치·연속 실패) 창이 보이는데도
            //   통째로 멈춘다 — `CheckChessWindow` 가 적어 둔 불변식("보이는 창의 시계가 멈추면 안 된다")을 깬다.
            //   대국 화면처럼 **잎 뷰**(`ChessWatchClockLeaf`)가 자기 TimelineView 로 읽는다.
            ChessWatchPlayerCard(store: store, user: watch.black, color: .black, isTurn: watch.turn == .black)
                .frame(height: ChessWindowLayout.playerCardHeight)
            ChessWatchPlayerCard(store: store, user: watch.white, color: .white, isTurn: watch.turn == .white)
                .frame(height: ChessWindowLayout.playerCardHeight)
            HStack(spacing: ChessWindowLayout.matchSideSpacing) {
                ChessStakeChip(stake: watch.stake, showsReward: false)
                ChessWatchStatusBox(store: store, watch: watch)
            }
            .frame(minHeight: ChessWindowLayout.stakeStatusMinHeight)
            ChessMoveListCard(moves: watch.moves, highlightSeq: watch.moves.last?.seq,
                              clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            ChessActionButton(title: ChessText.leaveWatch, icon: "xmark", tint: CheckTheme.offWork,
                              style: .outline, height: ChessWindowLayout.spectateLeaveHeight, fullWidth: true) {
                store.leaveWatch()
            }
            .frame(height: ChessWindowLayout.spectateLeaveHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ChessWatchPlayerCard: View {
    let store: ChessStore
    let user: ChessUser?
    let color: ChessColor
    let isTurn: Bool

    var body: some View {
        HStack(spacing: 12) {
            CharacterPortrait(characterID: user?.characterID ?? ChessPlayerFace.fallbackCharacterID)
                .frame(width: ChessWindowLayout.portraitSide, height: ChessWindowLayout.portraitSide)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                Text(user?.displayName ?? "—")
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    ChessColorDot(color: color, size: 14)
                    Text(ChessText.stoneName(color))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
            .frame(width: ChessWindowLayout.nameColumnWidth, alignment: .leading)
            Spacer(minLength: 4)
            ChessWatchClockLeaf(store: store, color: color, isTurn: isTurn)
                .frame(width: ChessWindowLayout.clockWidth, height: ChessWindowLayout.clockHeight)
        }
        .padding(.horizontal, ChessWindowLayout.cardInsetX)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTurn ? CheckTheme.accent.opacity(0.12) : CheckTheme.panel.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTurn ? CheckTheme.accent.opacity(0.6) : CheckTheme.border, lineWidth: isTurn ? 1.5 : 1)
        )
    }
}

private struct ChessWatchStatusBox: View {
    let store: ChessStore
    let watch: ChessSpectateState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: ChessWindowLayout.stakeStatusMinHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    private var headline: String { ChessWatchStatusText.headline(watch) }

    private var tint: Color {
        watch.isFinished ? CheckTheme.offWork : CheckTheme.accent
    }

    private var detail: String { ChessWatchStatusText.detail(watch, notice: store.notice) }
}

/// 관전 상태 상자가 그리는 **두 줄**(순수 값). 뷰에서 떼어 두어야 테스트가 "관전자가 읽는 글자" 를 되묻는다 —
/// 뷰 안에 두면 "흑 승리 / 기권했어요" 같은 자기모순을 잡는 그물을 걸 자리가 없다(2026-10-05 뮤테이션 실측:
/// 그 자리를 `outcome: .won` 으로 고쳐도 체스 테스트 126건이 전부 초록이었다).
enum ChessWatchStatusText {
    static func headline(_ watch: ChessSpectateState) -> String {
        if watch.isFinished {
            guard let winner = watch.winner else { return "무승부로 끝났어요" }
            return "\(ChessText.stoneName(winner)) 승리"
        }
        if !watch.hasServerState { return ChessText.watchLoading }
        guard let turn = watch.turn else { return ChessText.watchTitle }
        return "\(ChessText.stoneName(turn)) 차례"
    }

    /// 끝난 판은 **3인칭** 사유다(`watchEndReason`). `endReason(_:outcome: nil)` 을 쓰면 관전자가
    /// 패자의 1인칭 문장을 읽는다 — 머리글과 정면으로 어긋난다.
    static func detail(_ watch: ChessSpectateState, notice: String?) -> String {
        if watch.isFinished { return ChessText.watchEndReason(watch.endReason, winner: watch.winner) }
        if let notice { return notice }
        return ChessText.watchPaused
    }
}

// MARK: - 가운데 작은 창들

/// 승격 고르기. **판 탭으로도 취소되지만**(스토어 `tap` 이 접는다) 여기에도 [취소] 를 둔다 —
/// 덮개가 판을 덮고 있어 그 탭으로 가는 길이 사용자에게는 안 보인다.
private struct ChessPromotionSheet: View {
    let store: ChessStore
    let prompt: ChessPromotionPrompt
    let myColor: ChessColor

    var body: some View {
        ChessOverlayScrim {
            VStack(spacing: 14) {
                Text(ChessText.promotionTitle).font(.headline)
                HStack(spacing: 12) {
                    ForEach(prompt.choices, id: \.rawValue) { kind in
                        Button {
                            Task { await store.choosePromotion(kind) }
                        } label: {
                            ChessPieceTile(kind: kind, color: myColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ChessPieceTile.name(kind))
                        .checkTooltip(ChessPieceTile.name(kind))
                    }
                }
                ChessActionButton(title: ChessText.cancel, tint: CheckTheme.offWork, style: .outline,
                                  height: 30, fullWidth: true) { store.cancelPromotion() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: ChessWindowLayout.promotionPromptWidth)
            .chessCard(padding: 0)
        }
    }
}

/// 승격 창의 말 한 칸. 판과 **같은 벡터·같은 칸 색**을 써서 고른 말이 판에 어떻게 설지 눈으로 맞춰진다.
struct ChessPieceTile: View {
    let kind: ChessPieceKind
    let color: ChessColor

    static func name(_ kind: ChessPieceKind) -> String {
        switch kind {
        case .queen: return "퀸"
        case .rook: return "룩"
        case .bishop: return "비숍"
        case .knight: return "나이트"
        case .pawn: return "폰"
        case .king: return "킹"
        }
    }

    var body: some View {
        let side = ChessWindowLayout.promotionTileSide
        return Canvas { context, size in
            let box = CGRect(origin: .zero, size: size)
            context.fill(Path(box), with: .color(ChessBoardView.lightSquare))
            let path = ChessPieceArt.path(for: kind, in: box)
            context.fill(path, with: .color(color == .white ? ChessBoardView.whitePiece : ChessBoardView.blackPiece))
            context.stroke(path,
                           with: .color(color == .white ? ChessBoardView.whitePieceEdge : ChessBoardView.blackPieceEdge),
                           lineWidth: max(0.8, size.width * 0.035))
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 판돈 고르기 창. **고르기와 신청이 갈려 있다** — 판돈 버튼은 고르기만 하고 신청은 [도전하기] 한 곳에서만 나간다.
private struct ChessStakePrompt: View {
    let store: ChessStore
    let target: ChessUser
    let initialSelection: ChessStake?
    let onClose: () -> Void

    @State private var selection: ChessStake?

    private var chosen: ChessStake? { selection ?? initialSelection }

    var body: some View {
        ChessOverlayScrim {
            VStack(spacing: 12) {
                Text(ChessText.stakePromptTitle(name: target.displayName)).font(.headline)
                Text(chosen.map { ChessText.stakePromptChosen($0.rawValue) } ?? ChessText.stakePromptCaption)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(height: 20)
                HStack(spacing: 10) {
                    ForEach(ChessStake.allCases, id: \.rawValue) { stake in
                        ChessStakeButton(stake: stake, isSelected: chosen == stake,
                                         isEnabled: affordable(stake)) {
                            selection = (chosen == stake) ? nil : stake
                        }
                    }
                }
                if let chosen, !affordable(chosen) {
                    Text(ChessText.stakeShortfall)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.danger)
                }
                if let chosen, affordable(chosen) {
                    ChessActionButton(title: ChessText.challengeWithStake(chosen.rawValue), icon: "paperplane.fill",
                                      height: 34, fullWidth: true, isEnabled: !store.isBusy) {
                        store.selectedStake = chosen
                        onClose()
                        Task { await store.challenge(userID: target.id) }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    ChessActionButton(title: ChessText.cancel, tint: CheckTheme.offWork, style: .outline,
                                      height: 34, fullWidth: true, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: ChessWindowLayout.stakePromptWidth)
            .chessCard(padding: 0)
            // Esc 는 고른 뒤에도 언제나 닫는다(위 [취소]가 사라지는 갈래가 있으므로 창에 한 번 더 건다).
            .overlay(
                Button(action: onClose) { Color.clear.frame(width: 0, height: 0) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            )
        }
    }

    private func affordable(_ stake: ChessStake) -> Bool {
        guard let balance = store.rubyBalance else { return true }
        return balance >= stake.rawValue
    }
}

private struct ChessStakeButton: View {
    let stake: ChessStake
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                RubyIcon(size: 18)
                Text("\(stake.rawValue)")
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : CheckTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? CheckTheme.accent : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.clear : CheckTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// 로봇과 둘 색 고르기.
private struct ChessAIPrompt: View {
    let store: ChessStore
    let onClose: () -> Void

    var body: some View {
        ChessOverlayScrim {
            VStack(spacing: 12) {
                Text(ChessText.aiPromptTitle).font(.headline)
                Text(ChessText.aiInfo)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                HStack(spacing: 10) {
                    ForEach(ChessColor.allCases, id: \.rawValue) { color in
                        Button {
                            onClose()
                            store.startAIMatch(humanColor: color)
                        } label: {
                            VStack(spacing: 6) {
                                ChessColorDot(color: color, size: 26)
                                Text(color == .white ? ChessText.aiPlayWhite : ChessText.aiPlayBlack)
                                    .font(.caption.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 76)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(CheckTheme.border, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                ChessActionButton(title: ChessText.cancel, tint: CheckTheme.offWork, style: .outline,
                                  height: 30, fullWidth: true, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: ChessWindowLayout.stakePromptWidth)
            .chessCard(padding: 0)
        }
    }
}

/// 규칙 보기. FIDE 표준(A2)을 **사용자 어휘**로 줄여 적는다 — 진단·규격 번호는 싣지 않는다.
private struct ChessRulesOverlay: View {
    let store: ChessStore
    let onClose: () -> Void

    static let lines: [(title: String, detail: String)] = [
        ("기본", "백이 먼저 둡니다. 왕을 잡히지 않게 두면서 상대 왕을 피할 수 없게 만들면(체크메이트) 이깁니다."),
        ("캐슬링", "왕과 룩이 한 번도 움직이지 않았고 사이가 비어 있으면 왕을 두 칸 옮겨 룩과 자리를 바꿉니다."),
        ("앙파상", "상대 폰이 두 칸 전진해 내 폰 옆에 섰다면, 바로 다음 수에 한 칸 지나간 자리로 잡을 수 있습니다."),
        ("승격", "폰이 맨 끝 줄에 닿으면 퀸·룩·비숍·나이트 중 하나로 바꿉니다."),
        ("무승부", "둘 곳이 없는데 체크가 아니면(스테일메이트), 50수 동안 잡기·폰 이동이 없으면, 같은 국면이 세 번 나오면, 메이트할 기물이 없으면, 또는 두 사람이 합의하면 무승부입니다."),
        ("시간", "시간을 다 쓰면 집니다. 다만 상대에게 메이트할 기물이 없으면 무승부입니다.")
    ]

    var body: some View {
        ChessOverlayScrim {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(ChessText.rulesTitle).font(.headline)
                    Spacer()
                    Text(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
                ForEach(Self.lines, id: \.title) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title).font(.caption.weight(.bold)).foregroundStyle(CheckTheme.accent)
                        Text(line.detail)
                            .font(.caption)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ChessActionButton(title: ChessText.close, style: .outline, height: 32, fullWidth: true,
                                  action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: 520, alignment: .leading)
            .chessCard(padding: 0)
        }
    }
}

/// 가운데 작은 창의 공통 바닥 — 뒤를 어둡게 덮고 가운데에 내용을 세운다.
private struct ChessOverlayScrim<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            CheckTheme.panelElevated.opacity(0.93)
            content
        }
        .frame(width: ChessWindowLayout.contentSize.width, height: ChessWindowLayout.contentSize.height)
    }
}

// MARK: - 공용 조각

/// 신청 만료까지 남은 초 — **잎 뷰**. 창이 안 보이면 멈춘다.
struct ChessCountdownText: View {
    let expiresAt: Date
    let isLive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isLive)) { context in
            Text(ChessText.clock(expiresAt.timeIntervalSince(context.date)))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.pending)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(CheckTheme.pending.opacity(0.14)))
        }
    }
}

/// 팝오버 배너의 남은 초 — **잎**이다(오목 `GomokuInviteBannerCountdown` 과 같은 규약).
/// 팝오버가 닫혀 창이 비활성이면 멈추고, 다시 열려 키를 얻으면 이 환경값이 바뀌어 곧바로 다시 돈다.
struct ChessInviteBannerCountdown: View {
    let invite: ChessInvite
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ChessCountdownText(expiresAt: invite.expiresAt, isLive: controlActiveState != .inactive)
    }
}

/// 팝오버의 **받은 체스 신청 배너**(v0.3.44). 오목 배너(`GomokuInviteBanner`)의 형제이고 모양·높이가 같다.
///
/// ★ 이 배너가 없으면 체스 신청을 받은 사람이 팝오버에서 볼 곳이 없다. 체스 창을 여는 길은 미니게임 머리글
///   하나뿐이고 그 입구는 판이 도는 중에는 숨으므로, 배너가 빠지면 "창을 안 연 사람" 에게 신청을 보여 줄
///   표면이 캐릭터 말풍선 하나로 줄고 — 캐릭터를 꺼 둔 사람에게는 0 이 된다.
struct ChessInviteBanner: View {
    let invite: ChessInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    /// [보기] — 체스 창을 열어 이 신청을 보여 준다.
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: ChessEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChessText.inviteBannerTitle(name: invite.peer.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text(ChessText.stakeTitle)
                        RubyIcon(size: 11)
                        Text("\(invite.stake) · \(ChessText.inviteBannerSubtitle)")
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                ChessInviteBannerCountdown(invite: invite)
            }
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text(ChessText.accept)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.accent))
                }
                .buttonStyle(.plain)
                .checkTooltip(ChessText.acceptHelp)
                Button(action: onDecline) {
                    Text(ChessText.decline)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(CheckTheme.accent.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                if let onOpen {
                    Button(action: onOpen) {
                        Text(ChessText.viewInvite)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(CheckTheme.accent.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .checkTooltip(ChessText.viewInviteHelp)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

private struct ChessNoticeLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(CheckTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 캡슐 대신 둥근 사각 버튼(채움/외곽선). Menu·Picker 대신 쓰는 **유일한** 버튼 모양이다.
struct ChessActionButton: View {
    enum Style { case filled, outline }

    let title: String
    var icon: String? = nil
    var tint: Color = CheckTheme.accent
    var style: Style = .filled
    var height: CGFloat = 30
    var fullWidth: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: max(10, height * 0.34), weight: .bold))
                }
                Text(title)
                    .font(height >= 38 ? .callout.weight(.bold) : .caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(style == .filled ? Color.white : tint)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .fill(style == .filled ? tint : tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(tint.opacity(style == .filled ? 0 : 0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 스크롤 칸. 스냅샷에서는 **클립 갈래**로 그린다 — ImageRenderer 는 ScrollView 안을 못 그린다.
private struct ChessScrollBox<Content: View>: View {
    let clips: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if clips {
            // ★ 클립 갈래도 **위 정렬**이다 — 스냅샷이 앱과 다른 자리에 그리면 사람이 눈으로 보는 그림이
            //   거짓이 된다(아래 ScrollView 는 언제나 위에서 시작한다).
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension View {
    /// 체스 창 카드 크롬. 기본 여백은 `ChessWindowLayout.cardPadding` — 기보·순위 행수 산식이 같은 값을 뺀다.
    func chessCard(padding: CGFloat = ChessWindowLayout.cardPadding) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}
