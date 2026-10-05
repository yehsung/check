import AppKit
import Observation
import SwiftUI
import CheckCore

// MARK: - 1:1 체스 창 (v0.3.44)
//
// `CheckGomokuWindow.swift` 의 **형제**다. 그 파일의 규약을 전부 그대로 베꼈고(지연 생성 · 멱등 열기 ·
// 닫아도 파괴 안 함 · 고유 자동저장 이름 · 고착 감시자 + 재생성 상한 · 테스트 알파 0 · 키를 잃어도 대국은
// 계속 · 최소화는 '안 보임' · 닫기와 최소화를 **다른 통지**로), 체스에서 달라지는 것은 **숫자**뿐이다.
//
//   · **닫기 통지(`windowDidClose`)는 `windowWillClose`·`close()` 에서만 부른다.** `notifyVisibility` 안에
//     넣거나 `windowDidMiniaturize` 에 더하면 **최소화만 해도 남의 판 관전이 로비로 떨어진다** — 오목이
//     그 구별로 사고를 냈고(0.3.42) 그 수리가 이 파일의 출발점이다.
//   · **창이 키를 잃거나 닫혀도 대국은 끝나지 않는다.** 체스는 시간 소진이 곧 패배(B4)이고 그 판정은 **서버**가
//     한다 — 다른 앱을 잠깐 봤다고 판을 끊으면 루비가 걸린 판을 사용자 실수 한 번에 잃는다. 그래서 이 컨트롤러는
//     판 중단 신호를 **아예 모른다**(`windowDidResignKey` 가 없는 것이 계약이다).
//   · ★ **`MiniGameSpaceKey.standaloneWindowIDs` 에 이 창의 자동저장 이름이 들어 있어야 한다.** 그 목록이
//     아는 독립 창이 "오목·설정 둘뿐"이던 동안, 미니게임 창을 띄워 둔 채 오목 채팅을 치면 스페이스가 통째로
//     삼켜졌다(2026-09-17 실사용 제보). 체스 창의 입력도 같은 전역 모니터를 지나므로 등록을 빼면 같은 사고가
//     그대로 재현된다 — 등록 자체를 `MiniGamePanel.swift` 가, 그 사실을 `V0344ChessWindowTests` 가 지킨다.

/// 체스 창의 **고정** 레이아웃. 순수 상수 — 창 크기를 두 곳에 적지 않는다.
///
/// 화면은 전부 **두 열**이다(로비만 세 열):
///   · 대국 = [판 608 | 오른쪽 열 572]. 오른쪽 열은 위에서부터 상대 카드 · 내 카드 · 판돈과 상태줄 ·
///     **기보 카드** · [기권]·[무승부] 한 줄. 기보는 오목에 없던 칸이라 세로 예산을 다시 계산했다(아래 산식).
///   · 결과 = [판 | 결과 카드 · 기보 카드].
///   · 관전 = 대국과 같은 두 열(`phase` 는 `.lobby` 그대로, `spectating` 이 있으면 로비 자리에 선다).
///   · 로비 = [상대 420 | 순위 340 | 오른쪽 400] — 오른쪽 열은 위에서부터 내 전적 · 지금 대결 중 · 받은/보낸 신청.
///
/// ── 숫자의 근거(각 줄이 왜 그 값인가) ──
///  · `contentSize 1240×700` — **오목 창과 같은 크기다**. 두 창은 같은 사람이 같은 자리에서 번갈아 쓰는
///    형제 창이고, 13" 맥(1440×900 에서 메뉴바·독을 뺀 작업 영역)에 들어가는 상한이 1240 이라는 실측이
///    오목 창에 이미 적혀 있다("창을 넓히지 않는다: 13" 맥에 안 들어간다"). 체스가 더 넓어야 할 이유는 없다 —
///    기보는 세로로 자라는 목록이라 **오른쪽 열 안**에 들어간다(세 번째 열을 만들면 1400 이 되어 13" 를 넘는다).
///  · `bodyHeight 608` = 660 − 머리글 40 − 간격 12. 여기까지는 오목과 같은 산식이다.
///  · `boardSide 608` → **칸 76pt 정확**(608 = 8 × 76). 체스에서 이 값을 고른 이유가 오목과 다르다:
///    8×8 은 608 을 **나머지 없이** 나누므로 64칸이 전부 같은 크기이고 격자에 반 픽셀 이음선이 생기지 않는다
///    (오목의 608 은 14 간격이라 칸이 38.14… 로 떨어졌다). 76pt 는 마우스로 말을 집기에 넉넉하고(오목 칸 38pt 의 두 배),
///    말 벡터가 같은 칸 안에서 폰과 킹을 구분할 만큼 크다.
///  · `sideColumnWidth 572` = 1200 − 20 − 608. 두 사람 카드(초상 60 + 이름 + **시계 96**)가 한 줄에 서고
///    기보 두 열(백·흑 SAN)이 접히지 않는 폭이다.
///  · `moveListHeight 322` = 608 − 카드 84×2 − 판돈줄 44 − 동작줄 34 − 간격 10×4. 오목의 채팅 자리에
///    기보가 들어간 것이라 **같은 산식에 같은 값**이 나온다(두 창의 오른쪽 열이 같은 리듬으로 선다).
///  · `moveVisibleRows 11` = (262 + 2) / (22 + 2) — 262 = 322 − 카드 여백 32 − 제목 20 − 간격 8.
///    11 × 24 − 2 = 262 이라 **스크롤 없이 정확히 11줄**(= 22수)이 보이고 12번째부터 스크롤이다.
enum ChessWindowLayout {
    /// 창 콘텐츠 크기(고정). 컨트롤러의 min/max 도 이 값 하나를 쓴다.
    static let contentSize = CGSize(width: 1240, height: 700)
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12

    static var innerSize: CGSize {
        CGSize(width: contentSize.width - contentPadding * 2, height: contentSize.height - contentPadding * 2)
    }
    static var bodyHeight: CGFloat { innerSize.height - headerHeight - headerSpacing }

    /// 판 한 변 = 본문 높이(정사각). **8 로 나누어떨어진다**(608 = 8 × 76) — 위 산식 참고.
    static var boardSide: CGFloat { bodyHeight }
    /// 칸 한 변. 이 값이 정수가 아니게 되는 변경은 격자에 이음선을 만든다(창 테스트가 되묻는다).
    static var cellSide: CGFloat { boardSide / 8 }
    /// 대국·결과·관전 화면의 오른쪽 열 = 판을 뺀 나머지.
    static var sideColumnWidth: CGFloat { innerSize.width - columnSpacing - boardSide }

    // MARK: 카드 크롬

    /// 체스 창 카드의 기본 안쪽 여백. 기보 행수 산식이 이 값을 두 번 뺀다 — 뷰와 산식이 같은 숫자를 봐야 한다.
    static let cardPadding: CGFloat = 16

    // MARK: 대국 오른쪽 열의 세로 예산

    /// 위아래 칸 사이 간격(카드 · 판돈 줄 · 기보 · 동작 줄).
    static let matchSideSpacing: CGFloat = 10
    /// 두 사람 카드의 **고정** 높이(초상 60 + 안쪽 여백 4×2 = 68, 카드 위아래 여백 8×2 → 84).
    /// 시계가 흐르며 글자 폭이 바뀌어도 열이 한 픽셀도 안 흔들리게 못 박는다.
    static let playerCardHeight: CGFloat = 84
    /// 카드 안 초상 한 변.
    static let portraitSide: CGFloat = 60
    /// 카드 안 이름 칸 폭(고정 — 긴 별명이 시계를 밀지 않는다).
    static let nameColumnWidth: CGFloat = 140
    /// 카드 좌우 여백. 시계 자리를 테스트가 이 값으로 계산한다.
    static let cardInsetX: CGFloat = 12
    /// 시계 칸 폭. "5:00"(가산 +3 표시까지) 가 monospacedDigit 로 들어가는 값이다.
    static let clockWidth: CGFloat = 96
    /// 시계 칸 높이(카드 84 안에서 위아래 20 씩 남는다).
    static let clockHeight: CGFloat = 44
    /// 판돈 칩 | 상태 상자 줄의 최소 높이.
    static let stakeStatusMinHeight: CGFloat = 44
    /// [기권]·[무승부] 한 줄 높이.
    static let actionRowHeight: CGFloat = 34

    /// 기보 카드 높이 = 두 카드·판돈 줄·동작 줄·간격 넷을 뺀 나머지(= 322).
    static var moveListHeight: CGFloat {
        bodyHeight - playerCardHeight * 2 - stakeStatusMinHeight - actionRowHeight - matchSideSpacing * 4
    }
    /// 기보 제목 줄 높이(프레임으로 못 박아 캡션이 길어져도 행수 산식이 안 흔들린다).
    static let moveHeaderHeight: CGFloat = 20
    static let moveHeaderSpacing: CGFloat = 8
    /// 기보 한 줄(수 번호 + 백 SAN + 흑 SAN) 높이.
    static let moveRowHeight: CGFloat = 22
    static let moveRowSpacing: CGFloat = 2
    /// 목록에 남는 높이 = 322 − 여백 32 − 제목 20 − 간격 8 = 262.
    static var moveListInnerHeight: CGFloat {
        moveListHeight - cardPadding * 2 - moveHeaderHeight - moveHeaderSpacing
    }
    /// 스크롤 없이 보이는 줄 수(= 11: 11×22 + 10×2 = 262). 12번째부터 ScrollView(스냅샷은 클립 갈래).
    static var moveVisibleRows: Int {
        Int((moveListInnerHeight + moveRowSpacing) / (moveRowHeight + moveRowSpacing))
    }
    /// 기보 행 왼쪽 수 번호 칸 폭("99." 까지).
    static let moveNumberWidth: CGFloat = 36

    // MARK: 로비 세 열

    /// 로비 왼쪽 블록(상대 목록 + 순위). 오른쪽 열을 뺀 나머지다.
    static var lobbyListWidth: CGFloat { innerSize.width - columnSpacing - lobbySideWidth }
    /// 상대 목록 폭(오목과 같은 420 — 12자 별명이 [도전] 과 한 줄에 서는 실측값).
    static let lobbyUsersWidth: CGFloat = 420
    /// 순위 열 폭 = 왼쪽 블록에서 상대 목록과 간격을 뺀 나머지(= 340). 항등식 420 + 20 + 340 = 780 을 창 테스트가 되묻는다.
    static var lobbyRankWidth: CGFloat { lobbyListWidth - columnSpacing - lobbyUsersWidth }
    /// 로비 오른쪽 열 폭.
    static let lobbySideWidth: CGFloat = 400
    static let lobbySideSpacing: CGFloat = 12
    /// 내 전적 카드 높이(전적 한 줄 + 승점·순위 한 줄 + 여백). 고정이라 순위 응답이 늦게 와도 아래 두 칸이 안 밀린다.
    static let lobbyRecordHeight: CGFloat = 72
    // MARK: 받은·보낸 신청 칸

    /// 칸 안쪽 간격(제목 · 받은 카드 · 보낸 줄 · 안내 줄 사이).
    static let lobbyInvitesSpacing: CGFloat = 8
    /// "받은 신청" 제목 줄 높이(프레임으로 못 박아 글꼴이 바뀌어도 예산 산식이 안 흔들린다).
    static let lobbyInvitesTitleHeight: CGFloat = 20
    /// 받은 신청 카드의 자연 높이(여백 10×2 + 첫 줄 32 + 간격 8 + 버튼 줄 30).
    static let lobbyInviteCardHeight: CGFloat = 90
    /// 보낸 신청 줄의 자연 높이.
    static let lobbyOutgoingLineHeight: CGFloat = 30
    /// 안내 줄 높이 — **두 줄**이다(`ChessNoticeLine` 이 `lineLimit(2)` 다).
    /// ★ 한 줄로 셈하면 두 줄 안내에서 둘째 줄의 절반 이상이 부모 열의 `.clipped()` 에 잘린다(2026-10-05 실측).
    static let lobbyNoticeLineHeight: CGFloat = 36
    /// 받은·보낸 신청 칸의 **높이 예산**. 체스는 받은 신청이 **한 건뿐**이라(서버가 하나만 말해 준다)
    /// 오목의 320 보다 작다.
    ///
    /// ★ 옛 값 200 은 **처음부터 모자랐다**: 근거 주석이 `chessCard` 여백 16×2 와 "받은 신청" 제목 줄 20 을
    ///   세지 않았다. 받은+보낸 신청이 함께 있는 평범한 상태(내가 A에게 신청 + B가 나에게 신청)에 안내 줄 한 줄만
    ///   더해도 칸이 3pt, 두 줄이면 9pt 넘쳤고 — VStack 이 부족한 높이를 위아래로 균등히 흘리므로 — 아래로도
    ///   같은 양이 새서 안내 줄의 마지막 글자가 잘렸다. 이제 **각 조각을 더해서** 낸다(렌더 테스트가 자연 높이와 견준다).
    static var lobbyInvitesMaxHeight: CGFloat {
        cardPadding * 2 + lobbyInvitesTitleHeight + lobbyInviteCardHeight
            + lobbyOutgoingLineHeight + lobbyNoticeLineHeight + lobbyInvitesSpacing * 3
    }
    /// "지금 대결 중" 칸의 높이 = 나머지. 카드 다섯 장은 언제나 보인다.
    static var lobbyLiveHeight: CGFloat {
        bodyHeight - lobbyRecordHeight - lobbyInvitesMaxHeight - lobbySideSpacing * 2
    }
    /// 순위 목록에 남는 높이 = 608 − 여백 32 − 제목 20 − 간격 8 = 548.
    static var rankListHeight: CGFloat { bodyHeight - cardPadding * 2 - rankHeaderHeight - rankHeaderSpacing }
    static let rankHeaderHeight: CGFloat = 20
    static let rankHeaderSpacing: CGFloat = 8
    static let rankRowHeight: CGFloat = 34
    static let rankRowSpacing: CGFloat = 5
    /// 행 오른쪽 고정 칸(위 승점 · 아래 승·패·무).
    static let rankTrailingWidth: CGFloat = 96
    /// 스크롤 없이 보이는 행수(= 14: 14×34 + 13×5 = 541 ≤ 548).
    static var rankVisibleRows: Int { Int((rankListHeight + rankRowSpacing) / (rankRowHeight + rankRowSpacing)) }
    /// "지금 대결 중" 카드 첫째 줄의 [관전] 칩 높이. **18 이어야** 첫째 줄이 얼굴 높이를 넘겨 카드가 자라지 않는다
    /// (오목에서 20 으로 두자 카드가 53 → 55 로 자라 렌더 시험 둘이 카드를 0장으로 셌다).
    static let liveWatchChipHeight: CGFloat = 18

    // MARK: 가운데 작은 창

    /// 판돈 고르기 창 폭(판돈 버튼 셋이 한 줄에 여유 있게 선다).
    static let stakePromptWidth: CGFloat = 340
    /// 승격 고르기 창 폭 — 말 넷(Q R B N)을 76pt 칸 크기로 한 줄에 세운다: 76×4 + 간격 12×3 + 여백 20×2 = 380.
    static let promotionPromptWidth: CGFloat = 380
    /// 승격 창의 말 한 칸(판의 칸과 **같은 크기**라 고른 말이 판에 어떻게 설지 눈으로 바로 맞춰진다).
    static var promotionTileSide: CGFloat { cellSide }

    // MARK: 관전 오른쪽 열

    /// [나가기] 높이(대국 화면 동작 줄과 같다).
    static let spectateLeaveHeight: CGFloat = 34
    // ★ `spectateInfoHeight` 는 **지웠다**(2026-10-05). 소스·테스트 어디서도 0회 참조인 완전 사장 상수였고,
    //   "대국과 같은 산식" 이라는 주석만 남아 다음 사람에게 "관전 기보가 그 값으로 선다" 는 거짓을 말했다 —
    //   관전 기보 카드는 대국과 똑같이 `.frame(minHeight: 0, maxHeight: .infinity)` 로 남는 공간을 흡수한다.
}

/// 체스 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다** —
/// 스토어의 `openWindow(focusMatchID:)` 가 `presentWindow` 문(CheckApp 배선)을 거쳐 여기로 온다.
@MainActor
final class CheckChessWindowController: NSObject, NSWindowDelegate {
    /// 앱이 쓰는 단 하나의 인스턴스. `init` 을 막지 않은 이유는 헤드리스 검증이다(오목·미니게임 창과 같다).
    static let shared = CheckChessWindowController()

    /// 창 제목. CGWindowList 로 밖에서 창을 셀 때의 표식이다.
    static let windowTitle = "1:1 체스"

    /// 창 위치를 기억하는 키. **다른 창과 겹치면 안 된다** — 같은 이름이 이미 등록돼 있으면
    /// `setFrameAutosaveName` 이 false 를 돌려주고 자리 저장이 조용히 죽는다(`frameAutosaveActive` 로 잰다).
    /// 이 문자열은 `MiniGameSpaceKey.standaloneWindowIDs` 가 읽는 **창 식별자**이기도 하다(머리 주석 ★).
    static let frameAutosaveName = "check.chess.window"

    /// 콘텐츠 크기 — 고정. 숫자는 `ChessWindowLayout.contentSize` 한 곳에서 온다.
    static let fixedContentSize = NSSize(
        width: ChessWindowLayout.contentSize.width,
        height: ChessWindowLayout.contentSize.height
    )

    /// 창을 물릴 재료. 스토어와 콘텐츠를 **함께** 묶는다(따로 두면 콘텐츠만 플레이스홀더인 조합이 생긴다).
    struct Wiring {
        let store: ChessStore
        let content: @MainActor (ChessStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 사람 아바타의 캐릭터 한 표(`.appUserAvatarCharacters(from:)`)를 읽는 곳. 약참조다(스토어 수명은 앱이 쥔다).
    ///
    /// 오목 창은 여기에 **신고·차단 시트 거두기**도 달려 있지만 체스 창에는 없다 — 체스에는 채팅이 없어
    /// (사용자 결정: 체스는 기보가 그 자리를 쓴다) 시트를 여는 ··· 메뉴 자체가 이 창에 존재하지 않는다.
    /// 없는 시트를 닫는 호출을 베껴 두면 "거두고 있다"는 거짓 안심만 남는다.
    private weak var safety: WorkTimerStore?
    /// 지연 생성된 창. 닫아도 파괴하지 않는다 — 옮겨 둔 자리가 매번 초기화되는 게 더 나쁘다.
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). `isVisible` 은 이 저장소에서 거짓말한 적이 있어 '의도'와 '사실'을 나눈다.
    private(set) var isOpen = false
    /// 창을 이미 만들었는가(`window` 를 읽으면 그 순간 만들어지므로 이 문으로만 묻는다).
    var hasWindow: Bool { windowStorage != nil }
    /// 지금 쥐고 있는 창(읽기 전용 — 만들지 않는다).
    var currentWindow: NSWindow? { windowStorage }
    /// 의도와 사실이 **둘 다** 참일 때만 떠 있다고 본다.
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    /// 지금 창이 실제로 자리를 저장하고 있는가(헤드리스 검증 지점).
    private(set) var frameAutosaveActive = false
    /// 스토어에 마지막으로 알린 표시 상태(true = windowDidShow, false = windowDidHide).
    private(set) var lastVisibilityNotice: Bool?
    /// 스토어에 마지막으로 알린 가림 상태(true = 보임, false = 가려짐).
    private(set) var lastOcclusionNotice: Bool?

    /// 이 인스턴스의 고착 확인 지연(초). 프로덕션은 언제나 `Self.stuckWindowCheckSeconds`.
    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckChessWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 기본 화면(`ChessPanel`)을 물린다. `me` 는 내 이름·캐릭터를 읽는 문이다 —
    /// `ChessStore` 는 상대만 들고 있어서 나는 앱 배선이 `WorkTimerStore` 에서 읽어 넘긴다.
    func configure(
        store: ChessStore,
        me: @escaping @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback },
        safety: WorkTimerStore? = nil
    ) {
        self.safety = safety
        configure(store: store, content: { chess in
            // 뷰는 고정 크기를 채운다. 배경을 창 쪽에서 채우지 않으면 화면 배율이 바뀌는 순간 시스템 회색 판이 드러난다.
            AnyView(
                ChessPanel(store: chess, me: me, safety: safety)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(CheckTheme.background)
            )
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(store: ChessStore, content: @escaping @MainActor (ChessStore) -> AnyView) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    /// 창(첫 `show()` 에 생성). 배선 전이면 nil 이다.
    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        // 복원은 `setFrameUsingName`, 저장은 `setFrameAutosaveName`.
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        if created.frame.size != created.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size {
            created.setContentSize(Self.fixedContentSize)
        }
        // 반환값을 버리지 않는다 — 이름 충돌이면 false 이고 자리 저장이 조용히 죽는다.
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 체스 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 은 없다(고정 — 판 좌표계가 창 크기에 딸려 흔들리면 안 된다).
            // `.miniaturizable` 은 넣는다 — 상대 차례에 치워 뒀다 다시 꺼내는 표면이다.
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        // ★ 이 식별자가 `MiniGameSpaceKey.yieldsToOtherWindow` 의 판정 재료다(머리 주석 ★).
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        // 우리가 창을 붙들고 재사용한다 — 닫힘에 해제가 끼면 다음 show() 가 해제된 창을 만진다.
        window.isReleasedWhenClosed = false
        // 다른 앱을 클릭해도 창은 남는다(대국은 계속된다 — 시간은 서버가 잰다).
        window.hidesOnDeactivate = false
        // 앱 전체가 다크다(`CheckTheme`).
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0. 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 체스 창을 연다(멱등 — 최소화돼 있으면 되살린다). 열 때마다 스토어에 '보임'을 알린다 —
    /// `orderOut` 된 창은 뷰가 살아 있어 `onAppear` 가 다시 오지 않으므로, 재조회의 문은 여기다.
    func show() {
        guard let window else { return }
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        let fixedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
        if window.frame.size != fixedFrame { window.setContentSize(Self.fixedContentSize) }
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        notifyVisibility(true)
        armStuckWindowWatchdog()
    }

    /// 체스 창을 내린다(멱등). 창과 그 안의 상태는 남는다. **대국은 끝나지 않는다.**
    /// 로그아웃·계정 전환에서도 이 문을 부른다(`ChessAccountWatcher`) — 깃발만 내리면 내용이 빈 창이 남는다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
        notifyVisibility(false)
        // 프로그램 닫기(로그아웃·계정 전환)도 닫기다 — `orderOut` 은 `windowWillClose` 를 안 보낸다.
        notifyClosed()
    }

    /// 사용자가 빨간 점을 눌렀다. 의도를 맞추고 '안 보임'과 **'닫혔다'**를 알린다 — 기권이 아니다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        notifyVisibility(false)
        notifyClosed()
    }

    /// 스토어에 **닫혔다**고 알린다 — `notifyVisibility(false)` 와 갈라 둔다.
    ///
    /// ★ **이 문을 `notifyVisibility` 안에 넣지 마라.** '안 보임'은 `windowDidMiniaturize` 도 부르므로, 합치면
    ///   최소화만 해도 관전이 내려가 남의 판을 보다 최소화했다 되살리면 로비로 떨어진다. 닫기는 "그만 본다",
    ///   최소화는 "잠깐 치운다" — 두 뜻을 한 통지로 합쳐 둔 것이 오목에서 관전이 닫기 뒤에도 남아 있던 원인이다.
    private func notifyClosed() {
        wiring?.store.windowDidClose()
    }

    /// 최소화 — 화면에서 사라졌으니 폴링을 멈추게 한다(대국은 계속).
    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        notifyVisibility(false)
    }

    /// 최소화에서 되살아났다 — 다시 '보임'.
    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        if isOpen { notifyVisibility(true) }
    }

    /// 가림 상태가 바뀌었다 — 다른 창에 완전히 가려짐 · 다른 Space · 화면 잠금. 스토어에 **폴링만** 멈추라고 알린다
    /// (`isWindowVisible` 과 시계 잎 뷰는 그대로다 — 가림 통지가 틀려도 보이는 창의 시계가 멈추면 안 된다).
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 스토어로 옮긴다(헤드리스 검증 문 — 알파 0 테스트 창의 occlusionState 는 화면 사정에 따라 달라서 값을 주입한다).
    /// 닫힌 창의 통지는 무시한다(닫기는 이미 '안 보임'을 알렸다).
    func applyOcclusion(visible: Bool) {
        guard isOpen else { return }
        lastOcclusionNotice = visible
        wiring?.store.windowOcclusionDidChange(visible: visible)
    }

    /// 창이 앞으로 왔다. 의도를 맞춘다(다른 경로로 창이 올라온 경우에도 `isOpen` 이 사실과 갈리지 않게).
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        isOpen = true
    }

    /// 크기 고정의 마지막 문.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
    }

    /// 확대 거부(버튼은 비활성이지만 ⌥클릭·접근성 경로가 남아 있다).
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    /// 스토어에 표시 상태를 알린다. '보임'은 열 때마다(재조회의 문), '안 보임'은 보이던 때만 한 번.
    private func notifyVisibility(_ visible: Bool) {
        if !visible, lastVisibilityNotice != true { return }
        lastVisibilityNotice = visible
        guard let store = wiring?.store else { return }
        if visible {
            store.windowDidShow()
        } else {
            store.windowDidHide()
        }
    }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구

    static let stuckWindowCheckSeconds: Double = 0.5
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    private(set) var stuckWindowRebuilds = 0

    /// `makeKeyAndOrderFront` 도 조용히 실패할 수 있다(v0.2.27 실측). 통한 복구는 창을 버리고 새로 만드는 것뿐이었다.
    private func armStuckWindowWatchdog() {
        stuckWindowWatchdog?.cancel()
        let delay = stuckWindowCheckSeconds
        stuckWindowWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isOpen,
                  let stuck = self.windowStorage, Self.isOnScreen(stuck) == false
            else { return }
            self.rebuildStuckWindow()
        }
    }

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 대국 상태는 스토어에 있으므로 잃는 것이 없다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        // 델리게이트를 먼저 뗀다 — close() 의 windowWillClose 가 우리에게 오면 새 창을 세우는 도중 의도가 뒤집힌다.
        old.delegate = nil
        old.contentView = nil
        // ★ 자동저장 이름을 반드시 놓아준다(안 풀면 재생성된 창이 자리를 영영 저장하지 못한다).
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
        show()
    }

    /// 이 창이 지금 **실제로** 화면에 올라가 있는가를 창 서버에 직접 묻는다(판정은 한 벌만 둔다).
    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    /// 지금 창의 상태를 한 줄로(진단·사후 분석용).
    var diagnosticState: String {
        guard let windowStorage else { return "window=none isOpen=\(isOpen) rebuilds=\(stuckWindowRebuilds)" }
        let onScreen = Self.isOnScreen(windowStorage).map(String.init(describing:)) ?? "unknown"
        let f = windowStorage.frame
        return "window=\(windowStorage.windowNumber) isOpen=\(isOpen) isVisible=\(windowStorage.isVisible)"
            + " onScreen=\(onScreen) alpha=\(windowStorage.alphaValue) autosave=\(frameAutosaveActive)"
            + " frame=\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))"
            + " rebuilds=\(stuckWindowRebuilds)"
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다. 한 프로세스에서 컨트롤러를 여럿 만들면
    /// 먼저 만든 창이 이름을 쥐고 있어 다음 창의 `frameAutosaveActive` 가 거짓이 된다.
    func discardWindowForTesting() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        guard let old = windowStorage else { return }
        old.delegate = nil
        old.contentView = nil
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
    }
    #endif
}

// MARK: - 로그아웃·계정 전환 감시

/// 로그인한 사용자 id 가 **바뀌는 순간**(로그아웃 = nil, 계정 전환 = 다른 id)만 지켜보다가 체스 창을 닫는다.
///
/// 왜 필요한가: 체스 상태 리셋은 core 가 `WorkTimerStore` 로그아웃 경로에서 `chess.reset()` 으로 하지만,
/// 창은 ui 쪽 수명이다. 깃발만 비우면 **내용이 빈 창이 화면에 남고**, 다음 사람이 앞 계정의 판을 본다.
/// 수법은 `GomokuAccountWatcher` 와 같다(스토어에 콜백 구멍을 뚫지 않고 `@Observable` 값 하나를 추적).
@MainActor
final class ChessAccountWatcher {
    private let userID: @MainActor () -> String?
    private let onChange: @MainActor () -> Void
    private var lastUserID: String?

    init(userID: @escaping @MainActor () -> String?, onChange: @escaping @MainActor () -> Void) {
        self.userID = userID
        self.onChange = onChange
        lastUserID = userID()
    }

    /// 감시를 건다. 등록된 onChange 가 자신을 강하게 붙들기 때문에 호출자가 수명을 들 필요가 없다.
    func start() { arm() }

    private func arm() {
        withObservationTracking {
            _ = userID()
        } onChange: { [self] in
            // onChange 는 값이 바뀌기 **직전**(willSet)에 온다 — 한 틱 뒤 메인 액터에서 새 값을 읽는다.
            Task { @MainActor in self.applyThenRearm() }
        }
    }

    private func applyThenRearm() {
        let current = userID()
        if current != lastUserID {
            lastUserID = current
            onChange()
        }
        arm()
    }
}
