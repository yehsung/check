import Foundation
import Observation
import OSLog

// 아잉 큐브(rummy) 스토어 — 화면 상태 · 서버 동기화 · 작업 상태 전송 · RPC 호출. 맥·폰 공용(코어).
// **공개 표면(이름·타입·접근자)은 설계서 §4.3 이 계약이다** — 화면(U1·U2)이 이 이름으로 짜인다. 시그니처를 바꾸지 마라.
// (화면 상태의 setter 는 `package internal(set)` 이다 — 이 파일을 셋으로 쪼갰기 때문이고, 모듈 밖(맥 타깃)에서는
//  설계서의 `private(set)` 과 똑같이 읽기 전용이다.)
//
// 파일 지도: 여기(표면 · 수명 · 창 · 신호 · 폴링 · 리셋 · 공용 관용구) · `RummyStoreLobby.swift`(로비 · 초대 · 방 동작 ·
// 순위 · 차단 거울) · `RummyStoreGame.swift`(state 깔때기 · 편집기 재구성 · 차례 동작 · 작업 상태 전송 · 마감) ·
// `RummyNoticeText.swift`(문구 한 곳).
//
// ── 베낀 규약(TetrisDuelStore · ChessStore 머리말) ──
//  ① **서버가 권위다.** 판·랙·차례·결과·루비는 RPC 응답으로만 바뀐다. 낙관적 차감·낙관적 확정은 없다.
//     합법 판정의 주인도 서버다(`rummy_play` 가 R-16 을 다시 판정한다) — 편집기 판정은 버튼·안내용이다.
//  ② **시각은 서버 시계로 보정한다**(`noteServerNow` · `deviceDate`). 차례 마감은 서버 `turn_deadline_ms` 를 기기 시계로
//     옮겨 **잎 뷰가** 보간한다(`turnRemaining(at:)` — 체스 `ChessServerClock` 과 같은 뜻: 표시용이고 응답마다 통째로 덮는다).
//  ③ **폴링은 창이 보일 때만 돈다**(로비 30초 · 방/판 5초 · 순위 60초). 창이 안 보이면 초인종(신호)과 마감 깨우기만 남는다.
//  ④ **늦게 온 응답은 버린다.** 세대 두 개(`resetGeneration` + `host.sessionGeneration`)가 로그아웃·계정 전환 뒤의 응답을,
//     서버 `seq`·`draft_seq` 가 같은 판의 옛 스냅숏을, 요청 표(`requestTicket`)가 seq 가 안 바뀌는 방(forming)의 옛 응답을 버린다.
//  ⑤ **사용자 문구는 `RummyNoticeText` 한 곳에만 있다.**
//  ⑥ **신호는 합친다**(`requestSync` — 도는 중 온 신호는 뒤따르는 한 번).
//  ⑦ **초 단위 값은 잎 뷰만 읽는다** — 스토어는 매초 대입하지 않는다(남은 초는 함수로 낸다).
//  ⑧ **2단 입력 상태(작업 판)는 스토어가 든다**(`editor`). 뷰 `@State` 에 두면 창이 가려졌다 돌아올 때 작업이 날아간다.
//
// ── 아잉 큐브에서 새로 생긴 자리 ──
//  ⑨ **작업 상태 전송**(R-19). 내 차례에 끌기가 끝날 때마다 250ms 디바운스 → `rummy_draft`. 한 번에 하나만 비행하고,
//     비행 중에 바뀐 것은 끝난 뒤 **최신 것 한 번**. 서버는 마지막 것만 두고 시간 초과 때 그 판을 판정한다 —
//     그래서 차례 중간에 편집기를 새로 세우면(앱 재실행) 서버 작업 판을 내 화면(시작 판)으로 다시 맞춘다.
//     `p_expected_seq` 는 편집기가 선 seq 가 아니라 **지금 든 판의 seq** 다(같은 차례에 남의 기권으로 seq 가 오른다).
//     같은 차례에 stale 을 받으면 새 seq 로 한 번 더 보낸다. [완료]·뽑기가 확정되지 않으면(실패·거절·stale) 걷었던
//     디바운스를 다시 건다 — 서버 작업 판이 내 화면에 머물게.
//  ⑩ **편집기 수명.** **차례**(`RummyEditorKey` = 판 · 차례 자리 · `turn_started_ms`)가 바뀌면 새 판·랙으로 다시 세우되
//     랙 배치는 면 순서로 넘긴다. 같은 차례면 **덮지 않는다**(내 작업 보존 — 내 draft 의 메아리·남의 폴링 응답, 그리고
//     남의 기권이 seq 만 올린 state 가 작업을 지우지 않게). 같은 차례인데 확정 판·내 랙이 달라졌을 때만 다시 세운다.
//     '내 차례' 알림·마감 깨우기도 같은 차례 정체성으로 가른다(`turnIdentity`).
//
// ── v2(설계서 v2 §2.4 — `RummyStoreV2.swift`) ──
//  ⑪ **배치도 작업 상태다.** 편집기가 판 배치(`points`)를 들고, 작업 상태 전송·[완료]가 `p_layout` 으로 싣는다.
//     같은 판·같은 배치면 다시 보내지 않는다(`lastSentDraft` + `lastSentLayout`).
//  ⑫ **하트비트**는 phase 가 room·playing 인 동안 10초마다(창과 무관). 서버는 90초 안 보이면 끊김 기권시킨다.
//     의도적 이탈(창 닫기·앱 종료·로그아웃)은 `leaveForExit` — 최대 2초 기다리고, 못 닿아도 이 기기에선 접는다.
//  ⑬ **반응**은 꾸밈이라 내 말풍선을 바로 띄우고(같은 반응이 state 로 돌아오면 한 번 삼킨다), 남의 것은 state 의
//     `reactions` 에서 처음 보는 것만 낸다. **뽑기**는 다음 편집기의 랙에서 새로 생긴 면을 찾아 `onTileDrawn` 으로 알린다.
//  ⑭ **받침대 자리는 판마다 로컬 저장**(`rackDefaults`, 판 id 키) — 판이 끝나거나 접히면 지운다.

// MARK: - 호스트

/// 아잉 큐브 스토어가 네트워크·세션·루비 미러를 빌리는 곳 — 오목·체스·테트리스와 **같은 프로토콜**이다.
package typealias RummyStoreHost = GomokuStoreHost

// MARK: - 스토어

@MainActor
@Observable
package final class RummyStore {
    package enum Phase: Equatable { case lobby, room, playing, finished }
    package enum Availability: Equatable { case available, updateRequired, serverMissing }

    // MARK: 주기 상수

    /// 로비 목록 재조회 주기(초) — 테트리스와 같다.
    package nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 방(forming)·판(active)에 있을 때 그 state 를 다시 읽는 주기(초). 창이 보일 때만.
    package nonisolated static let matchPollSeconds: TimeInterval = 5
    /// 팝오버를 열 때 로비를 다시 읽는 스로틀(초).
    package nonisolated static let menuLobbyThrottleSeconds: TimeInterval = 30
    /// 로비를 보고 있는 동안 순위표 재조회 주기(초).
    package nonisolated static let rankingPollSeconds: TimeInterval = 60
    /// 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초).
    package nonisolated static let reloadDedupeSeconds: TimeInterval = 1
    /// 서버 시계 오프셋을 다시 재는 문턱(초).
    package nonisolated static let serverClockToleranceSeconds: TimeInterval = 0.25
    /// 작업 상태 전송 디바운스(초, 설계서 §2 R-19).
    package nonisolated static let draftDebounceDefaultSeconds: TimeInterval = 0.25
    /// 응답이 유예를 안 실어 준 드문 경우의 기본값(초, 서버 `rummy_grace_seconds()`).
    package nonisolated static let defaultGraceSeconds: TimeInterval = 2
    /// 마감 + 유예가 지난 뒤 다시 읽기 전 여유(초) — 기기·서버 시계 잔차를 흡수한다.
    package nonisolated static let deadlineSlackSeconds: TimeInterval = 0.5
    /// 마감 뒤에도 같은 차례면 다시 읽는 간격(초)과 상한(서버 크론이 1분 안에 따라잡는다).
    package nonisolated static let deadlineRetrySeconds: TimeInterval = 3
    package nonisolated static let deadlineRetryLimit = 3
    /// 작업 상태 전송이 실패했을 때 다시 보내는 간격(초)과 상한.
    package nonisolated static let draftRetrySeconds: TimeInterval = 1
    package nonisolated static let draftRetryLimit = 3
    /// v2 하트비트 주기(초, 설계서 v2 §2.4). 서버 끊김 기준은 90초(`rummy_disconnect_seconds()`).
    package nonisolated static let heartbeatDefaultSeconds: TimeInterval = 10
    /// v2 의도적 이탈(`leaveForExit`)이 서버 답을 기다리는 상한(초).
    package nonisolated static let exitLeaveLimitSeconds: TimeInterval = 2
    /// v2 반응 쿨다운(초) — 서버도 같은 사람 2초(`too_fast`).
    package nonisolated static let reactionCooldownSeconds: TimeInterval = 2
    /// v2 `reactionFeed` 상한.
    package nonisolated static let reactionFeedLimit = 12
    /// v2 내 반응의 메아리를 기다리는 창(초) — 서버 state 는 최근 10초만 싣는다.
    package nonisolated static let reactionEchoSeconds: TimeInterval = 10

    package nonisolated static let logger = Logger(subsystem: "kingcheck", category: "rummy")

    /// 네트워크·세션·루비 미러를 빌리는 곳(약참조). nil 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any RummyStoreHost)?

    // MARK: 화면 상태

    package internal(set) var phase: Phase = .lobby
    package internal(set) var availability: Availability = .available
    /// 와이어 모델(§3.5) — **차단 거울을 거친 것**이다(차단한 사람·그 사람이 낀 방·그 사람의 초대는 빠진다).
    package internal(set) var lobby: RummyLobby?
    /// 내가 앉은 방/판의 최신 state(§3.7).
    package internal(set) var match: RummyMatchState?
    /// 판이 active 이고 내가 playing 일 때. 내 차례가 아니면 랙 정렬만 쓰인다.
    package internal(set) var editor: RummyTurnEditor?
    package var isMyTurn: Bool { Self.isMyTurn(match, me: myUserID) }
    /// 남의 차례면 그 사람 작업 판(없으면 nil → `match.table`).
    package var otherDraft: [[RummyFace]]? {
        guard let match, match.status == .active, !isMyTurn else { return nil }
        return match.draft?.table
    }
    /// 사용자 문구(`RummyNoticeText` 한 곳).
    package internal(set) var notice: String?
    /// 요청 비행 중(버튼 잠금). 작업 상태 전송·폴링은 세우지 않는다 — 사용자가 누른 동작만.
    package internal(set) var isWorking: Bool = false
    package internal(set) var ranking: RummyRanking?
    package var selectedStake: Int = 3
    package var createPublic: Bool = false
    package var rulesShown: Bool = false
    /// **순위 적재의 주 스위치. 기본 false**(배선 값 — `reset` 이 건드리지 않는다).
    package var rankingEnabled: Bool = false

    // MARK: 시간 — 잎 뷰가 TimelineView 로 읽는다

    /// 지금 차례의 남은 초(0 아래로 안 간다). 판이 active 가 아니거나 마감을 모르면 nil.
    package func turnRemaining(at date: Date) -> TimeInterval? {
        guard let match, match.status == .active, let deadline = deviceDate(serverMs: match.turnDeadlineMs)
        else { return nil }
        return max(0, deadline.timeIntervalSince(date))
    }

    /// 방(forming)이 닫히기까지 남은 초. 방이 아니면 nil.
    package func roomRemaining(at date: Date) -> TimeInterval? {
        guard let match, match.status == .forming, let expires = deviceDate(serverMs: match.expiresAtMs)
        else { return nil }
        return max(0, expires.timeIntervalSince(date))
    }

    // MARK: 문(맥이 꽂는다)

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    /// 새 초대(방 id 마다 한 번, 차단한 방장 제외).
    @ObservationIgnored package var onInviteArrived: (@MainActor (RummyRoom) -> Void)?
    /// 독 주의(판 시작 · 창이 안 보일 때 내 차례).
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    /// 캐릭터 말풍선 한 줄(`RummyNoticeText` 의 문구). 창이 안 보일 때만 부른다.
    @ObservationIgnored package var onAttention: (@MainActor (String) -> Void)?
    /// 내 판이 끝난 것을 **처음 본** 순간 한 번(판 id 마다). 맥은 여기서 일일 미션 진행을 묻는다.
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?
    /// v2: 내 랙에 새 타일이 들어왔다(뽑기 · 시간 초과 뽑기 · 벌칙). 편집기를 새로 세운 **뒤에** 부른다 — `tileID` 로 바로 찾을 수 있다.
    @ObservationIgnored package var onTileDrawn: (@MainActor (RummyDrawEvent) -> Void)?
    /// v2: 이모티콘 반응 하나(내 것은 보내는 즉시, 남의 것은 state 에서 처음 볼 때).
    @ObservationIgnored package var onReaction: (@MainActor (RummyReactionEvent) -> Void)?

    // MARK: v2 화면 상태(RummyStoreV2.swift)

    /// 최근 반응(오래된 것이 앞, 최대 `reactionFeedLimit`). 화면은 `receivedAt` 에서 2.5초 동안 말풍선을 그린다.
    package internal(set) var reactionFeed: [RummyReactionEvent] = []
    /// 마지막 뽑기 사건(모션 계기). `serial` 이 바뀔 때마다 새 사건이다.
    package internal(set) var lastDraw: RummyDrawEvent?

    // MARK: v2 배선 · 장부

    /// 하트비트 주 스위치(시험은 끄고 `heartbeatTick(matchID:)` 를 직접 밟는다).
    @ObservationIgnored package var heartbeatEnabled = true
    /// 하트비트 주기(초).
    @ObservationIgnored package var heartbeatSeconds: TimeInterval = RummyStore.heartbeatDefaultSeconds
    /// 받침대 자리 저장소. **nil 이면 저장하지 않는다**(기본 — 시험이 Preferences 를 더럽히지 않게). 맥 배선이 `.standard` 를 꽂는다.
    @ObservationIgnored package var rackDefaults: UserDefaults?
    @ObservationIgnored package internal(set) var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored package internal(set) var heartbeatMatchID: UUID?
    /// 서버가 들고 있다고 믿는 작업 판 배치(`lastSentDraft` 의 짝).
    @ObservationIgnored package internal(set) var lastSentLayout: RummyLayout?
    @ObservationIgnored var lastReactionSentAt: Date = .distantPast
    /// 내가 보내고 이미 띄운 반응(키 · 보낸 시각) — state 로 돌아온 메아리를 한 번 삼킨다.
    @ObservationIgnored var pendingOwnReactions: [(key: String, at: Date)] = []
    @ObservationIgnored var seenReactionKeys: Set<String> = []
    @ObservationIgnored var reactionSerial = 0
    @ObservationIgnored var drawSerial = 0

    // MARK: 내부 장부 (관찰 대상 아님)

    /// 벽시계 '지금'(서버 시각 보정·마감). 시험이 갈아 끼운다.
    @ObservationIgnored package var clock: () -> Date = { Date() }
    /// 폴링 루프의 한 걸음(초). 시험은 3,600 으로 재우고 `pollTick(at:)` 을 직접 밟는다.
    @ObservationIgnored package var pollStepSeconds: TimeInterval = 0.5
    /// 작업 상태 전송 디바운스(초).
    @ObservationIgnored package var draftDebounceSeconds: TimeInterval = RummyStore.draftDebounceDefaultSeconds
    /// 마감 깨우기(창이 안 보여도 마감 + 유예 뒤 state 를 한 번 다시 읽는다). 시험은 끄고 `checkDeadline(at:)` 을 밟는다.
    @ObservationIgnored package var deadlineWakeEnabled = true

    @ObservationIgnored package internal(set) var serverClockOffset: TimeInterval = 0
    @ObservationIgnored var hasServerClockOffset = false
    @ObservationIgnored package internal(set) var resetGeneration = 0
    @ObservationIgnored package internal(set) var isWindowVisible = false
    /// 창이 완전히 가려졌다. **폴링만** 이 값을 본다.
    @ObservationIgnored package internal(set) var isWindowOccluded = false

    /// 요청 표 — state 를 돌려줄 수 있는 요청마다 보낼 때 하나씩 오른다(머리말 ④).
    @ObservationIgnored package internal(set) var requestTicket = 0
    /// 지금 `match` 를 만든 응답의 표.
    @ObservationIgnored package internal(set) var appliedTicket = 0

    // 조회 직렬화.
    @ObservationIgnored package internal(set) var stateInFlightID: UUID?
    @ObservationIgnored var pendingStateID: UUID?
    @ObservationIgnored var stateInFlight = false
    @ObservationIgnored var stateAgain = false
    @ObservationIgnored var lobbyInFlight = false
    /// 로비 조회가 도는 중에 또 불렸다 — 끝난 뒤 **한 번 더** 읽는다(그 사이 온 초인종을 버리지 않게).
    @ObservationIgnored var lobbyAgain = false
    @ObservationIgnored var rankingInFlight = false

    /// 차단 거울을 거치기 전의 로비 응답.
    @ObservationIgnored package internal(set) var rawLobby: RummyLobby?
    /// 차단으로 걷어낸 사람(소유자가 채운다).
    @ObservationIgnored package internal(set) var hiddenPeerIDs: Set<UUID> = []
    /// 서버가 말한 내 방·판 id(로비 `me.active_match_id` ?? `me.room.id`).
    @ObservationIgnored package internal(set) var activeMatchID: UUID?
    /// 이 기기가 방·판을 새로 세우거나 떠날 때마다 오른다. 그보다 **먼저** 나간 로비 응답이 "방 없음" 을 말해도 믿지 않는다.
    @ObservationIgnored var matchRevision = 0
    @ObservationIgnored package internal(set) var seenInviteIDs: Set<UUID> = []
    @ObservationIgnored package internal(set) var startAnnouncedIDs: Set<UUID> = []
    @ObservationIgnored package internal(set) var turnAnnouncedKeys: Set<String> = []
    @ObservationIgnored package internal(set) var finishAnnouncedIDs: Set<UUID> = []
    /// [로비로]·나가기로 접은 판. 늦게 온 그 판의 state 가 사용자를 다시 끌고 가지 않게 한다.
    @ObservationIgnored package internal(set) var dismissedMatchIDs: Set<UUID> = []

    // 편집기 · 작업 상태 전송(RummyStoreGame.swift).
    /// 지금 편집기가 선 차례(판 · 차례 자리 · 차례 시작 시각). 차례가 바뀌면 편집기를 다시 세운다.
    @ObservationIgnored package internal(set) var editorKey: RummyEditorKey?
    /// 편집기가 마지막으로 맞춘 판 seq(같은 차례에 남의 기권으로 오를 수 있다).
    @ObservationIgnored package internal(set) var editorSeq: Int?
    /// 서버가 들고 있다고 믿는 작업 판(마지막으로 보낸 것, 새 차례면 시작 판). 같으면 다시 보내지 않는다.
    @ObservationIgnored package internal(set) var lastSentDraft: [[RummyFace]]?
    @ObservationIgnored package internal(set) var draftDebounceTask: Task<Void, Never>?
    /// 지금 나가 있는 작업 상태 전송(한 번에 하나). 시험이 `await draftFlushTask?.value` 로 기다린다.
    @ObservationIgnored package internal(set) var draftFlushTask: Task<Void, Never>?
    @ObservationIgnored package internal(set) var draftInFlight = false
    @ObservationIgnored var draftDirty = false
    @ObservationIgnored var draftRetryCount = 0

    // 마감.
    @ObservationIgnored package internal(set) var deadlineTask: Task<Void, Never>?
    @ObservationIgnored var deadlineWakeKey: String?
    @ObservationIgnored package internal(set) var deadlineFetchKey: String?
    @ObservationIgnored var deadlineFetchCount = 0
    @ObservationIgnored var lastDeadlineFetchAt: Date = .distantPast

    // 동작 · 폴링 · 신호.
    /// 사용자가 누른 동작(한 번에 하나). 시험이 `await actionTask?.value` 로 기다린다.
    @ObservationIgnored package internal(set) var actionTask: Task<Void, Never>?
    @ObservationIgnored package internal(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored var pollToken = 0
    @ObservationIgnored package internal(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored var syncPendingTrailing = false
    @ObservationIgnored package var lastStateRequestAt: Date = .distantPast
    @ObservationIgnored package var lastLobbyRequestAt: Date = .distantPast
    @ObservationIgnored package var lastMenuLobbyAt: Date = .distantPast
    @ObservationIgnored package var lastRankingRequestAt: Date = .distantPast

    // MARK: 수명

    package init() {}

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다.
    package func attach(host: any RummyStoreHost) {
        self.host = host
    }

    /// 로그인한 내 id(소문자). 호스트가 없으면(미리보기) nil — 그때는 `my_seat_no` 로 나를 찾는다.
    var myUserID: String? { host?.session?.userID.lowercased() }

    // MARK: - 창

    /// 창을 띄우고 로비(와 가리킨 방·판)를 읽는다. `focusMatchID` 는 배너·말풍선에서 온 경로의 대상이다.
    package func openWindow(focusMatchID: UUID?) {
        if host?.session != nil {
            // 곧 이어질 setWindowVisible(true) 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            lastLobbyRequestAt = clock()
            Task { [weak self] in
                guard let self else { return }
                await self.refreshLobby()
                if let focusMatchID, focusMatchID != self.match?.id,
                   !(self.lobby?.invites ?? []).contains(where: { $0.id == focusMatchID }) {
                    await self.refreshMatch(id: focusMatchID)
                }
            }
        }
        presentWindow?()
    }

    /// 창이 보이기 시작했다(true) · 숨었거나 닫혔다(false). 폴링만 켜고 끈다 — 방·판은 창과 무관하게 서버에 있다.
    package func setWindowVisible(_ visible: Bool) {
        guard visible else {
            if isWindowVisible { isWindowVisible = false }
            isWindowOccluded = false
            stopPolling()
            return
        }
        isWindowVisible = true
        isWindowOccluded = false
        startPolling()
        guard host?.session != nil else { return }
        let now = clock()
        if now.timeIntervalSince(lastLobbyRequestAt) >= Self.reloadDedupeSeconds {
            lastLobbyRequestAt = now
            Task { [weak self] in await self?.refreshLobby() }
        }
        if let match, Self.isUnsettled(match.status),
           now.timeIntervalSince(lastStateRequestAt) >= Self.reloadDedupeSeconds {
            lastStateRequestAt = now
            let id = match.id
            Task { [weak self] in await self?.refreshMatch(id: id) }
        }
        if rankingEnabled, phase == .lobby, now.timeIntervalSince(lastRankingRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.loadRanking() }
        }
    }

    /// 창의 가림 상태가 바뀌었다. **폴링만** 멈추고 되살린다.
    package func setWindowOccluded(_ occluded: Bool) {
        isWindowOccluded = occluded
        if occluded { stopPolling() } else { startPolling() }
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 길)

    /// 실시간 'rummy' 초인종(`{v, m, s}` — 내용 없음). 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다.
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
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다.
                self.syncPendingTrailing = false
                await self.syncOnce()
            } while self.syncPendingTrailing && generation == self.resetGeneration
            if generation == self.resetGeneration { self.syncTask = nil }
        }
    }

    /// 신호 한 번의 조회: 방·판에 있으면 그 state(참가·시작·차례·작업 판·정산), 아니면 로비(초대 · 내 방·판 id).
    package func syncOnce() async {
        if let match, Self.isUnsettled(match.status) {
            await refreshMatch(id: match.id)
        } else {
            await refreshLobby()
        }
    }

    /// 조인 직후·깨어남의 따라잡기: 들고 있는 방·판(끝나지 않은 것)을 먼저 다시 읽고, 로비 한 번(+ 그 응답이 가리키는 다른 방·판).
    /// 로비는 들고 있는 것과 **같은 id** 면 다시 읽지 않으므로(`applyLobby`), 잠든 사이 방이 판으로 시작된 것은 여기서 안다.
    package func catchUp() async {
        if let match, Self.isUnsettled(match.status) {
            await refreshMatch(id: match.id)
        }
        await refreshLobby()
    }

    /// 아직 끝나지 않은 판 status(끝남·취소·만료가 아님) — 신호·폴링·따라잡기가 그 판을 다시 읽는 조건.
    /// 모르는 값(`unknown` — 서버가 나중에 늘릴 값)도 다시 읽는다. 들고만 있고 안 읽으면 그 판에 굳는다.
    package nonisolated static func isUnsettled(_ status: RummyMatchStatus?) -> Bool {
        status != .finished && status != .cancelled && status != .expired
    }

    /// 실시간 조인 성공 직후.
    package func realtimeDidJoin() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 깨어남(뚜껑을 열었다). 소켓이 끊겼던 사이에 온 초대·차례를 한 번 따라잡는다.
    package func systemDidWake() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 팝오버 열림(30초 스로틀). 메뉴바 점·배너(`incomingInvites`)의 신선도가 이 계기와 신호에 달려 있다.
    package func refreshLobbyIfStale() {
        guard host?.session != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuLobbyAt) >= Self.menuLobbyThrottleSeconds else { return }
        lastMenuLobbyAt = now
        Task { [weak self] in await self?.refreshLobby() }
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
    ///  · 방·판에 있으면 5초마다 그 state(참가·시작·작업 판·시간 초과를 한 조회가 다 말한다) · 마감이 지났으면 다시
    ///  · 로비·방 화면이면 30초마다 로비(사람 목록·초대) · 순위는 60초(주 스위치)
    package func pollTick(at now: Date) async {
        guard isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if let match, Self.isUnsettled(match.status),
           now.timeIntervalSince(lastStateRequestAt) >= Self.matchPollSeconds {
            await refreshMatch(id: match.id)
        }
        guard isWindowVisible else { return }
        await checkDeadline(at: now)
        guard isWindowVisible else { return }
        if phase == .lobby || phase == .room, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await refreshLobby()
        }
        guard isWindowVisible else { return }
        if rankingEnabled, phase == .lobby, now.timeIntervalSince(lastRankingRequestAt) >= Self.rankingPollSeconds {
            await loadRanking()
        }
    }

    // MARK: - 리셋

    /// 로그아웃·계정 전환. 창을 닫고 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 방·판·랙·초대를 본다.
    /// **배선 값**(`rankingEnabled` · 시계 · 주기 · 문)은 건드리지 않는다.
    package func reset() {
        resetGeneration &+= 1
        stopPolling()
        syncTask?.cancel()
        syncTask = nil
        syncPendingTrailing = false
        actionTask = nil
        stateInFlight = false
        stateAgain = false
        stateInFlightID = nil
        pendingStateID = nil
        lobbyInFlight = false
        lobbyAgain = false
        rankingInFlight = false
        cancelDraft()
        draftFlushTask = nil
        draftInFlight = false
        deadlineTask?.cancel()
        deadlineTask = nil
        deadlineWakeKey = nil
        deadlineFetchKey = nil
        deadlineFetchCount = 0
        lastDeadlineFetchAt = .distantPast
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeatMatchID = nil
        lastSentLayout = nil
        lastReactionSentAt = .distantPast
        pendingOwnReactions = []
        seenReactionKeys = []
        if !reactionFeed.isEmpty { reactionFeed = [] }
        if lastDraw != nil { lastDraw = nil }
        if phase != .lobby { phase = .lobby }
        if availability != .available { availability = .available }
        if lobby != nil { lobby = nil }
        if match != nil { match = nil }
        if editor != nil { editor = nil }
        if notice != nil { notice = nil }
        if isWorking { isWorking = false }
        if ranking != nil { ranking = nil }
        if selectedStake != 3 { selectedStake = 3 }
        if createPublic { createPublic = false }
        if rulesShown { rulesShown = false }
        rawLobby = nil
        hiddenPeerIDs = []
        activeMatchID = nil
        matchRevision = 0
        seenInviteIDs = []
        startAnnouncedIDs = []
        turnAnnouncedKeys = []
        finishAnnouncedIDs = []
        dismissedMatchIDs = []
        editorKey = nil
        editorSeq = nil
        lastSentDraft = nil
        requestTicket = 0
        appliedTicket = 0
        serverClockOffset = 0
        hasServerClockOffset = false
        isWindowVisible = false
        isWindowOccluded = false
        lastStateRequestAt = .distantPast
        lastLobbyRequestAt = .distantPast
        lastMenuLobbyAt = .distantPast
        lastRankingRequestAt = .distantPast
        dismissWindow?()
    }

    // MARK: - 공용 관용구

    /// 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
    /// nil = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 nil 이면 **아무것도 바꾸지 않는다.**
    /// 왕복마다 notice 한 줄(부른 함수 이름 · 결과 · 밀리초)을 남긴다 — 현장에서 "응답이 왔는데 화면이 안 바뀌었나,
    /// 응답이 안 왔나" 를 `/usr/bin/log show --predicate 'subsystem == "kingcheck" AND category == "rummy"'` 로 가린다.
    /// 토큰·본문은 싣지 않는다.
    package func perform<T: Sendable>(
        _ operation: @escaping @Sendable (SupabaseWorkService, String) async throws -> T,
        label: String = #function
    ) async -> Result<T, any Error>? {
        guard let host, host.session != nil else { return nil }
        let sessionGeneration = host.sessionGeneration
        let generation = resetGeneration
        let service = host.service
        let started = Date()
        func trace(_ outcome: String) {
            let ms = Int((Date().timeIntervalSince(started) * 1000).rounded())
            Self.logger.notice("rpc \(label, privacy: .public) \(outcome, privacy: .public) \(ms, privacy: .public)ms")
        }
        do {
            let value = try await host.withSessionRetry { session in
                try await operation(service, session.accessToken)
            }
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else {
                trace("discarded")
                return nil
            }
            trace("ok")
            return .success(value)
        } catch {
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else {
                trace("discarded")
                return nil
            }
            if case .cancelled = host.classifyAuthError(error) {
                trace("cancelled")
                return nil
            }
            trace("failed")
            return .failure(error)
        }
    }

    /// 사용자가 누른 동작 하나를 돌린다(`isWorking` 을 세우고 내린다). 이미 도는 동작이 있으면 무시한다.
    func runAction(_ body: @escaping @MainActor (RummyStore) async -> Void) {
        guard !isWorking, host?.session != nil else { return }
        isWorking = true
        let generation = resetGeneration
        actionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await body(self)
            if generation == self.resetGeneration, self.isWorking { self.isWorking = false }
        }
    }

    /// 요청 표 하나를 뗀다(state 를 돌려줄 수 있는 요청을 **보내기 직전에**).
    func issueTicket() -> Int {
        requestTicket &+= 1
        return requestTicket
    }

    /// 서버에 아잉 큐브 RPC 가 아직 없다(PGRST202).
    package nonisolated func isSchemaMissing(_ error: any Error) -> Bool {
        (error as? SupabaseWorkServiceError) == .databaseSchemaMissing
    }

    /// 쓰기 동작이 throw 로 실패했다(5xx·오프라인·PGRST202).
    func noteActionFailure(_ error: any Error) {
        if isSchemaMissing(error) {
            noteServerMissing()
        } else {
            setNotice(RummyNoticeText.checkConnection)
        }
    }

    func noteServerMissing() {
        if availability != .serverMissing { availability = .serverMissing }
        setNotice(RummyNoticeText.unavailable)
    }

    func noteUpdateRequired() {
        if availability != .updateRequired { availability = .updateRequired }
        setNotice(RummyNoticeText.updateRequired)
    }

    /// 안내줄 한 문.
    package func setNotice(_ text: String?) {
        if notice != text { notice = text }
    }

    func applyRuby(_ value: Int?) {
        guard let value, let host, host.rubyBalance != value else { return }
        host.rubyBalance = value
    }

    /// `server_now_ms` 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만.
    package func noteServerNow(_ milliseconds: Double?) {
        guard let milliseconds, milliseconds > 0 else { return }
        let measured = milliseconds / 1000 - clock().timeIntervalSince1970
        guard !hasServerClockOffset || abs(measured - serverClockOffset) >= Self.serverClockToleranceSeconds
        else { return }
        serverClockOffset = measured
        hasServerClockOffset = true
    }

    /// 서버 epoch 밀리초 → 기기 시계의 같은 순간.
    package func deviceDate(serverMs milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000 - serverClockOffset)
    }

    /// 화면 phase 를 `match` 에서 다시 정한다.
    func refreshPhase() {
        let next: Phase
        switch match?.status {
        case .forming?: next = .room
        case .active?: next = .playing
        case .finished?: next = .finished
        default: next = .lobby
        }
        defer { updateHeartbeat() }
        guard phase != next else { return }
        // 화면 전환 한 줄(판 id 앞 8자만 — 사람 정보 없음).
        let shortID = match.map { String($0.id.uuidString.lowercased().prefix(8)) } ?? "-"
        Self.logger.notice(
            "phase \(String(describing: self.phase), privacy: .public)→\(String(describing: next), privacy: .public) match=\(shortID, privacy: .public)")
        phase = next
    }
}

/// 편집기가 선 **차례**(판 · 차례 자리 · 차례 시작 시각). `turn_started_ms` 는 차례가 넘어갈 때(advance)마다 바뀌고
/// 남의 기권(seq+1)에는 안 바뀐다 — seq 로 가르면 남이 기권할 때마다 내 차례 작업이 지워진다.
package struct RummyEditorKey: Equatable, Hashable, Sendable {
    package let matchID: UUID
    package let turnSeatNo: Int?
    package let turnStartedMs: Double?
    /// `turn_started_ms` 가 없는 옛 모양·미리보기에서만 seq 로 차례를 가른다(있으면 nil).
    package let fallbackSeq: Int?

    package init(matchID: UUID, turnSeatNo: Int?, turnStartedMs: Double?, seq: Int?) {
        self.matchID = matchID
        self.turnSeatNo = turnSeatNo
        self.turnStartedMs = turnStartedMs
        fallbackSeq = turnStartedMs == nil ? (seq ?? 0) : nil
    }

    package init(_ state: RummyMatchState) {
        self.init(matchID: state.id, turnSeatNo: state.turnSeatNo, turnStartedMs: state.turnStartedMs, seq: state.seq)
    }

    /// 알림·마감 깨우기 키에 쓰는 글자("<판>#<차례 자리>#<차례 시작>").
    package var text: String {
        let started = turnStartedMs.map { String(Int64($0)) } ?? "s\(fallbackSeq ?? 0)"
        return "\(matchID.uuidString.lowercased())#\(turnSeatNo.map(String.init) ?? "-")#\(started)"
    }
}
