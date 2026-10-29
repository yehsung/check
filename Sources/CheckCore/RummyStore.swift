import Foundation
import Observation

// 자리표시 — C 갈래가 채운다.
//
// 아잉 큐브(rummy) 스토어 — 화면 상태 · 서버 동기화 · 작업 상태 전송 · RPC 호출. 맥·폰 공용(코어).
// **공개 표면(이름·타입·접근자)은 설계서 §4.3 이 계약이다** — 화면(U1·U2)이 이 이름으로 짜인다. C 는 시그니처를 바꾸지
// 않는다(바꿔야 하면 보고서에 적는다). 뼈대(K)는 표면만 두고 본문은 기본값·빈 함수다.
//
// 규약은 `TetrisDuelStore`/`ChessStore` 머리말 ①~⑨ 를 따른다: 서버 권위 · 서버 시계 보정 · 창 보일 때만 폴링 ·
// 늦은 응답 버리기 · 문구 한 곳(`RummyNoticeText`) · 신호 합치기 · 초 단위 값은 잎 뷰만 · 2단 입력 상태는 스토어.
//
// 문(closure)들은 테트리스처럼 `@MainActor` 를 붙였다 — 맥 창 컨트롤러(@MainActor)가 꽂는 클로저를 격리 손실 없이 받는다.

// MARK: - 호스트

/// 아잉 큐브 스토어가 네트워크·세션·루비 미러를 빌리는 곳 — 오목·체스·테트리스와 **같은 프로토콜**이다.
package typealias RummyStoreHost = GomokuStoreHost

// MARK: - 스토어

@MainActor
@Observable
package final class RummyStore {
    package enum Phase: Equatable { case lobby, room, playing, finished }
    package enum Availability: Equatable { case available, updateRequired, serverMissing }

    /// 네트워크·세션·루비 미러를 빌리는 곳(약참조). nil 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any RummyStoreHost)?

    // MARK: 화면 상태

    package private(set) var phase: Phase = .lobby
    package private(set) var availability: Availability = .available
    /// 와이어 모델(§3.5).
    package private(set) var lobby: RummyLobby?
    /// 내가 앉은 방/판의 최신 state(§3.7).
    package private(set) var match: RummyMatchState?
    /// 판이 active 이고 내가 playing 일 때. 내 차례가 아니면 랙 정렬만 쓰인다.
    package private(set) var editor: RummyTurnEditor?
    package var isMyTurn: Bool { false }
    /// 남의 차례면 그 사람 작업 판(없으면 nil → `match.table`).
    package var otherDraft: [[RummyFace]]? { nil }
    /// 사용자 문구(`RummyNoticeText` 한 곳).
    package private(set) var notice: String?
    /// 요청 비행 중(버튼 잠금).
    package private(set) var isWorking: Bool = false
    package private(set) var ranking: RummyRanking?
    package var selectedStake: Int = 3
    package var createPublic: Bool = false
    package var rulesShown: Bool = false
    package var rankingEnabled: Bool = false

    // MARK: 시간 — 잎 뷰가 TimelineView 로 읽는다

    package func turnRemaining(at date: Date) -> TimeInterval? { nil }
    package func roomRemaining(at date: Date) -> TimeInterval? { nil }

    // MARK: 문(맥이 꽂는다)

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (RummyRoom) -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    @ObservationIgnored package var onAttention: (@MainActor (String) -> Void)?
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?

    // MARK: 수명

    package init() {}

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다.
    package func attach(host: any RummyStoreHost) {
        self.host = host
    }

    package func reset() {}
    package func openWindow(focusMatchID: UUID?) {}
    package func setWindowVisible(_ visible: Bool) {}
    package func setWindowOccluded(_ occluded: Bool) {}
    package func handleSignal() {}
    package func realtimeDidJoin() {}
    package func systemDidWake() {}
    package func refreshLobbyIfStale() {}

    // MARK: 초대

    /// 메뉴바 점·배너.
    package var hasIncomingInvite: Bool { false }
    package var incomingInvites: [RummyRoom] { [] }

    // MARK: 동작

    /// `selectedStake`·`createPublic` 으로 방을 만든다.
    package func createRoom() {}
    package func invite(_ userID: UUID) {}
    package func join(_ roomID: UUID) {}
    package func decline(_ roomID: UUID) {}
    /// 방 나가기 / 판 기권(뷰가 확인 대화상자를 띄운 뒤 부른다).
    package func leave() {}
    package func startGame() {}
    package func moveTile(_ tileID: Int, to target: RummyDropTarget) {}
    package func resetTurn() {}
    package func sortRack(_ mode: RummyRackSort) {}
    package func submitTurn() {}
    package func drawTile() {}
    package func dismissResult() {}
    package func refreshRanking() {}
    /// 차단 거울.
    package func setHiddenPeers(_ ids: Set<UUID>) {}
}
