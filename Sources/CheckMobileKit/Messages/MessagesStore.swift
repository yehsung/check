import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 메시지 탭 스토어(SPEC-ios §3.3 · SPEC-ios-build D4). Foundation·Observation 만 쓴다 — macOS `swift test` 로 검증한다.
///
/// 자리 API(기반이 부르는 것 — 이름·모양을 지킨다)
/// - `init(context:)` — 앱 모델이 로그인 여부와 무관하게 한 번 만든다. 네트워크를 부르지 않는다(실시간 핸들러 등록만).
/// - `appDidBecomeActive()` — 로그인 상태에서 active 가 될 때 · active 인 채로 로그인이 끝났을 때.
/// - `appDidEnterBackground()` — background 로 갈 때(보이는 대화 표시를 내리고 기다리던 창을 닫는다).
/// - `reset()` — 로그아웃·치명 만료로 세대가 바뀐 직후(계정에 묶인 값을 전부 비운다).
/// - `badgeCount` — 탭 배지 = 안 읽은 메시지 수(서버 판정 − 낙관 읽음, `MessagesBadgeRules`).
/// - `didReceiveMessagePush(peerID:)` — 푸시 코디네이터(D9)가 메시지 푸시를 받았을 때(포그라운드) 부르는 새로고침 문.
///
/// ── 이 스토어가 지키는 것(맥 `WorkTimerStoreMessages` 의 v0.3.30~0.3.31 규칙을 폰 수명으로 옮긴 것) ──
/// ① **take_pokes 를 부르지 않는다.** 새 메시지는 실시간 신호·푸시·화면 표시가 **조회**(요약 · 이력)로 갚는다. iOS 서비스에는 그 메서드가
///    컴파일되지도 않는다(`SupabaseWorkServiceMacOnly.swift`).
/// ② **읽음은 서버가 판정한다.** 안 읽음은 서버 플래그(이력 `isUnread` · 요약), 경계는 메시지 id, 선후는 요청 일련번호다 — 시각을 비교하지 않는다.
///    읽음을 올리는 자리는 `evaluateReadMarking()` 하나다: **앱이 active 이고 그 대화 화면이 떠 있을 때만**.
/// ③ **메시지 활동 새로고침은 겹치지 않는다**(`requestActivityRefresh` — 돌고 있으면 뒤따르는 한 번으로 합친다).
///    그래도 모든 이력 응답은 **띄운 순서 번호**로 거른다 — 먼저 띄운 늦은 응답이 나중 응답이 그린 새 줄을 지우지 않는다(맥 M4 원칙).
/// ④ **열린 대화는 신호 뒤 곧바로 이력을 받는다**(스로틀 없음 — 실시간 러너의 1초 합치기만). 닫힌 대화는 요약만 받고 이력은 "낡음"으로 적어
///    다음에 화면이 서는 순간 받는다.
/// ⑤ 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정의 대화·점·경계·입력칸을 건드리지 않는다.
@MainActor
@Observable
package final class MessagesStore {
    @ObservationIgnored package let context: MobileContext
    /// 확성기(📢 1.0.7) 작성 스토어 — **맥과 같은 코어 스토어**(`MegaphoneStore`)다. 호스트는 오목·체스·상점과 같은 하나
    /// (`context.gomokuHost` — 루비 미러를 한 칸으로 나눠 쓴다). 화면은 메시지 탭 위 📢 버튼의 시트(`MessagesMegaphoneSheet`).
    @ObservationIgnored package let megaphone: MegaphoneStore

    // MARK: 이력 · 읽음

    /// 이력(오래된 것 → 최신, 같은 초는 서버 순서). 모든 대화가 이 한 배열에서 묶인다(`threads`).
    package private(set) var history: [MessageHistoryEntry] = []
    /// 읽음 칸을 실어 온 마지막 이력의 사실(요청 번호 · 서버 순서). nil = 아직 없거나 서버가 읽음을 모른다.
    package private(set) var historySnapshot: MessageHistoryReadSnapshot?
    /// 서버가 읽음 기능을 아는가(`message_history_with_reads` 성공). false 면 화면은 1 을 그리지 않는다.
    package private(set) var readReceiptsAvailable = false
    package private(set) var historyLoaded = false
    package private(set) var historyLoading = false
    package private(set) var historyFailed = false
    package private(set) var summary: MessageUnreadSummarySnapshot?
    package private(set) var optimisticReads: [String: MessageOptimisticRead] = [:]
    /// 읽음을 모르는 옛 서버용 도장(대화를 본 순간). 서버가 읽음을 알면 쓰이지 않는다.
    package private(set) var legacyReadStamps: [String: Date] = [:]

    // MARK: 찌르기 기록 (1.0.13 · 서버 `message_history_with_pokes`)

    /// 창(24h) 안의 찌르기 기록 — 시간순(오래된 것 → 최신), 받은 것·보낸 것 모두. 옛 서버면 언제나 빈 배열이다.
    ///
    /// **메시지(`history`)와 섞지 않는다**: 메시지 읽음 경계·배지·말풍선 필터가 찌르기 id 를 메시지로 오인하는 길을
    /// 타입으로 닫는다(코어 `MessagePokeLog.swift` 머리 ②).
    package private(set) var pokeLog: [MessagePokeLogEntry] = []
    /// 서버가 찌르기 기록을 아는가(`message_history_with_pokes` 성공). false 면 대화 줄·정렬이 찌르기를 쓰지 않는다.
    package private(set) var pokeLogAvailable = false
    /// 행 id → 서버 시각 순위(메시지·찌르기 공통). 같은 초의 선후는 이것만 안다 — 목록 미리보기와 대화 줄이 같은 표를 읽는다.
    package private(set) var pokeChronology: [String: Int] = [:]
    /// 찌르기 기록을 실어 온 마지막 응답의 사실(요청 번호 · 서버 순서). nil = 아직 없거나 서버가 모른다.
    package private(set) var pokeSnapshot: MessageHistoryReadSnapshot?
    /// 찌르기 낙관 읽음(상대별). 메시지와 **따로** 둔다 — 서버 경계가 다른 표(`poke_reads`)이고, 한 통에 담으면
    /// 메시지 경계 id 가 찌르기 경계로 쓰이는 날이 온다.
    package private(set) var optimisticPokeReads: [String: MessageOptimisticRead] = [:]

    // MARK: 사람 찾기

    package private(set) var directory: [PokeDirectoryEntry] = []
    package private(set) var directoryLoaded = false
    package private(set) var directoryLoading = false
    package private(set) var directoryFailed = false
    /// 확성기 [답장]이 넘긴 이름·아바타(사람 id → 값). 대화 머리의 마지막 기댈 곳 — 확성기 줄이 빠져 대화가 비어 있어도 빈 칸이 아니게.
    package private(set) var replyPeerHints: [String: MegaphoneReplyPeerHint] = [:]

    // MARK: 차단 · 신고 (앱스토어 1.2 — 규칙과 문구는 코어 `BlockReportRules`(맥과 한 벌), 동작은 `MessagesBlockStore.swift`)

    /// 차단해서 **화면에서 걷어낸** 상대. 서버도 다음 조회부터 그 사람의 행을 빼지만, 화면은 응답을 기다리지 않는다
    /// (낙관적 — SPEC 작업 P 6). 실패하면 이 집합에서 빼며 대화가 그대로 되돌아온다.
    package internal(set) var hiddenBlockedPeerIDs: Set<String> = []
    /// 내가 차단한 사람들(`list_blocks`) — 나 → 설정 → 차단한 사람.
    package internal(set) var blockedPeople: [BlockedUser] = []
    package internal(set) var blocksLoaded = false
    package internal(set) var blocksLoading = false
    package internal(set) var blocksFailed = false
    /// 서버가 아직 차단 RPC 를 모른다(PGRST202). 목록 화면이 "고장"이 아니라 "아직"이라고 말한다.
    package internal(set) var blocksServerNotReady = false
    /// 차단 왕복이 떠 있는 상대(한 번에 하나 — 확인 시트를 지난 동작이다).
    package internal(set) var blockingPeerID: String?
    /// 차단 해제 왕복이 떠 있는 사람들(목록의 여러 줄을 나란히 풀 수 있다).
    package internal(set) var unblockingUserIDs: Set<String> = []
    /// 메시지 화면 한 줄(차단 되돌림 실패 · 신고 접수). 대화와 목록 중 **지금 보이는 쪽**이 그린다(둘은 동시에 서지 않는다).
    /// 다음 동작 · 당겨서 새로고침 · 로그아웃이 지운다.
    package internal(set) var blockNotice: String?
    /// 위 한 줄이 실패인가(빨강) 아니면 알림인가(파랑).
    package internal(set) var blockNoticeIsError = false
    /// 차단 목록 화면 안 한 줄(차단 해제 실패).
    package internal(set) var blockedListNotice: String?
    package internal(set) var isSendingReport = false
    /// 신고 시트 안 한 줄(실패 이유). 성공하면 시트가 닫히므로 남지 않는다.
    package internal(set) var reportNotice: String?

    // MARK: 화면 · 입력

    package private(set) var isAppActive = false
    /// 메시지 탭의 대화 목록이 떠 있는가(탭 화면이 알린다).
    package private(set) var isListVisible = false
    /// 지금 떠 있는 대화 화면의 상대(여럿이면 마지막으로 선 것). 라우터의 `visibleConversationPeerID` 는 앱이 active 일 때만 이 값이다.
    package private(set) var openConversationPeerID: String?
    /// 상대별 입력 중인 글(대화를 나갔다 와도 남는다 · 로그아웃이면 비운다).
    package private(set) var drafts: [String: String] = [:]
    /// 보내기를 누른 뒤 서버 이력이 들고 올 때까지 대화 끝에 서는 자리 말풍선.
    package private(set) var pendingOutgoing: [MessagesPendingOutgoing] = []
    /// 상대별 전송 실패 안내(입력칸 위 한 줄). 성공은 문구를 세우지 않는다.
    ///
    /// ★ 설정자는 **이 파일 안으로 닫아 둔다.** 1.0.12 통합 때 한 번 열었다가 되돌렸다 — 이모티콘 그리드가
    /// 왕복 중 안내를 세우려고 열었는데, 그리드는 **시트** 안에 있어서 입력줄의 이 한 줄이 시트에 **가려** 안
    /// 보인다. 그래서 그 안내는 시트가 자기 `@State` 로 들고(`MessagesStickerSheet`), 이 문은 다시 닫혔다.
    /// 쓰는 자리가 없는 접근 확대는 남겨 두지 않는다.
    package private(set) var sendNotices: [String: String] = [:]
    /// 전송 왕복 중인가. **한 번에 하나** — 순서가 곧 상대가 읽는 순서라 두 전송을 나란히 띄우지 않는다.
    package private(set) var isSending = false

    // MARK: 조절 값(테스트가 바꾼다)

    /// 목록이 설 때 이력을 다시 받는 최소 간격(초). 사이의 변화는 실시간 신호·푸시가 메운다. 낡음 표시가 있으면 무시한다.
    @ObservationIgnored package var listRefreshThrottleSeconds: TimeInterval = 15
    /// 사람 찾기 목록을 다시 받는 최소 간격(초).
    @ObservationIgnored package var directoryRefreshThrottleSeconds: TimeInterval = 60
    /// 읽음 처리 성공 뒤 요약을 다시 받기 전에 기다리는 창(초). 서버가 읽은 사람 채널로 되돌려 보내는 `message_read` 메아리가
    /// 그 안에 오면 그 새로고침이 이 몫을 맡는다(맥 m-fix2 · 부록 B-2). 소켓이 없으면 창이 닫힐 때 한 번 받는다.
    @ObservationIgnored package var postMarkRefreshSeconds: TimeInterval = 1.5
    /// 전송이 모호하게 실패했을 때(답을 못 받음) **같은 키로 한 번** 다시 보내기 전에 기다리는 초(`performSend`).
    @ObservationIgnored package var sendRetryDelaySeconds: TimeInterval = 1.5
    /// 답을 못 받은 전송을 기억하는 창(초). 그 안에 같은 상대·같은 본문을 다시 보내면 같은 키를 쓴다.
    /// 서버가 메시지를 24시간 두므로(키 중복 판정도 그 행이 있는 동안만 산다) 10분은 그 안쪽이다.
    @ObservationIgnored package var unconfirmedSendReuseSeconds: TimeInterval = 600
    /// 기다리기(테스트는 즉시 돌아오거나 손으로 푸는 것으로 바꾼다).
    @ObservationIgnored package var sleep: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }

    @ObservationIgnored private var runtime = MessagesRuntime()
    @ObservationIgnored private var registrations: [MobileRealtimeRegistration] = []

    package init(context: MobileContext) {
        self.context = context
        let megaphone = MegaphoneStore(host: context.gomokuHost)
        let clock = context.clock
        megaphone.clock = { clock.now() }
        self.megaphone = megaphone
        // 등록은 네트워크가 아니다. 핸들러가 스스로 로그인·active·세대를 확인한다(등록은 reset 뒤에도 살아 있다).
        registrations.append(context.onMessageActivity { [weak self] in self?.realtimeMessageActivity() })
        registrations.append(context.onMessageRead { [weak self] in self?.realtimeMessageRead() })
        // 보낸 직후 내 화면에 "이렇게 떴어요" 배너 한 번(계약 C2 — 서버 fan-out 에 나는 없으니 중복이 아니다).
        megaphone.onSent = { [weak self] body, megaphoneID in self?.presentOwnMegaphone(body: body, megaphoneID: megaphoneID) }
    }

    // MARK: - 자리 API

    package func appDidBecomeActive() {
        isAppActive = true
        syncRouterVisibility()
        guard isSignedIn else { return }
        // 확성기 배너 한 번 — 켜 둔 사이 놓친 신선한 확성기 · 메시지함 필터 id · 요약 함수(v1/v2) 판정. 요약이 이 첫 판정을 기다린다.
        startMegaphoneProbe()
        // 포그라운드 진입: 요약은 언제나, 이력은 메시지 화면이 떠 있으면 곧바로(아니면 낡음으로 적고 화면이 설 때).
        requestActivityRefresh()
        evaluateReadMarking()
    }

    package func appDidEnterBackground() {
        isAppActive = false
        syncRouterVisibility()
        runtime.postMarkWindowTask?.cancel()
        runtime.postMarkWindowTask = nil
    }

    package func reset() {
        runtime.cancelAll()
        runtime = MessagesRuntime()
        history = []
        historySnapshot = nil
        readReceiptsAvailable = false
        historyLoaded = false
        historyLoading = false
        historyFailed = false
        summary = nil
        optimisticReads = [:]
        legacyReadStamps = [:]
        pokeLog = []
        replyPeerHints = [:]
        pokeLogAvailable = false
        pokeChronology = [:]
        pokeSnapshot = nil
        optimisticPokeReads = [:]
        directory = []
        directoryLoaded = false
        directoryLoading = false
        directoryFailed = false
        hiddenBlockedPeerIDs = []
        blockedPeople = []
        blocksLoaded = false
        blocksLoading = false
        blocksFailed = false
        blocksServerNotReady = false
        blockingPeerID = nil
        unblockingUserIDs = []
        blockNotice = nil
        blockNoticeIsError = false
        blockedListNotice = nil
        isSendingReport = false
        reportNotice = nil
        isListVisible = false
        openConversationPeerID = nil
        drafts = [:]
        pendingOutgoing = []
        sendNotices = [:]
        isSending = false
        // 확성기 글·요청 id·정보도 계정에 묶인다 — 남기면 다음 사람이 앞 사람의 글을 보고 그 id 로 묻는다.
        megaphone.reset()
        context.router.visibleConversationPeerID = nil
    }

    /// 탭 배지 = 안 읽은 메시지 수.
    package var badgeCount: Int {
        MessagesBadgeRules.unreadCount(
            history: visibleHistory,
            historySnapshot: historySnapshot,
            summary: visibleSummary,
            optimistic: optimisticReads,
            legacyStamps: legacyReadStamps
        )
    }

    /// 메시지 푸시를 받았다(D9 — 포그라운드 표시 정책과 무관하게 부른다). 요약은 곧바로, 그 대화가 떠 있으면 이력도 곧바로.
    package func didReceiveMessagePush(peerID: String?) {
        guard isSignedIn else { return }
        let conversationOpen = peerID.map { $0 == openConversationPeerID } ?? false
        requestActivityRefresh(includeHistory: isAppActive && conversationOpen)
    }

    // MARK: - 파생값

    package var isSignedIn: Bool { context.session.isSignedIn }

    /// **차단해 숨긴 상대를 걷어낸 이력.** 묶음·배지·점·개수·말풍선이 전부 이 값을 읽는다 — 거르는 곳이 하나여야
    /// "목록에서는 사라졌는데 배지 숫자는 그대로"가 생기지 않는다. 숨긴 것이 없으면 이력 그대로다(사본을 뜨지 않는다).
    ///
    /// **확성기 줄도 여기 한 자리에서 뺀다**(계약 C3): 배너 스토어가 확성기로 판정한 줄(`hides` — inbox 가 말한 id, 필터가 켜졌을 때만)과
    /// 판정 보류 줄(받은 줄인데 본문이 `📢` 로 시작하고 id 를 아직 모름 — `needsVerification`). 보류 줄은 `verifyMegaphoneRows` 가
    /// refresh 한 번을 기다린 뒤 풀거나(메시지로) 숨긴다. 대화 목록·열린 대화·안 읽음 점·탭 배지·앱 아이콘 배지가 이 값을 따라온다.
    /// 배너 스토어가 없거나 서버가 배너를 모르면(`.unavailable`) 지금처럼 메시지로 보인다.
    package var visibleHistory: [MessageHistoryEntry] {
        let megaphone = megaphoneFilter
        guard !hiddenBlockedPeerIDs.isEmpty || megaphone != nil else { return history }
        return history.filter { entry in
            if hiddenBlockedPeerIDs.contains(entry.peerUserID) { return false }
            guard let megaphone else { return true }
            return !Self.holdsMegaphoneRow(entry, banner: megaphone)
        }
    }

    /// 메시지함 필터로 쓸 배너 스토어. 서버가 배너를 모르는 동안(`.unavailable`)은 nil — 거를 것도 보류할 것도 없다.
    private var megaphoneFilter: MegaphoneBannerStore? {
        guard let banner = context.links.megaphoneBanner, banner.capability != .unavailable else { return nil }
        return banner
    }

    /// 이 줄을 메시지함에서 붙드는가 — 확성기로 판정됐거나(`hides`), 받은 줄인데 판정 보류(`needsVerification`).
    /// 보낸 줄은 보류하지 않는다(서버 이력은 보낸 사람 자신의 확성기 줄을 이미 숨긴다 — 내가 📢 로 시작해 보낸 1:1 은 그냥 내 말이다).
    static func holdsMegaphoneRow(_ entry: MessageHistoryEntry, banner: MegaphoneBannerStore) -> Bool {
        if banner.hides(messageID: entry.id) { return true }
        return !entry.isMine && banner.needsVerification(messageID: entry.id, body: entry.body)
    }

    /// **차단해 숨긴 상대를 걷어낸 요약.** 이력만 거르면 부족하다 — 요약이 이력보다 새것인 창에서는 배지·점이 요약을 재료로
    /// 삼으므로, 목록에서 사라진 사람의 안 읽은 말이 탭 배지에서만 계속 세어진다(전체 스위트에서 실제로 잡힌 결함).
    package var visibleSummary: MessageUnreadSummarySnapshot? {
        guard let summary, !hiddenBlockedPeerIDs.isEmpty else { return summary }
        let filtered = summary.summary.excluding(hiddenBlockedPeerIDs)
        return filtered == summary.summary ? summary : MessageUnreadSummarySnapshot(serial: summary.serial, summary: filtered)
    }

    /// 대화 목록(최근 대화순). 같은 초는 서버 순서로 깬다.
    package var threads: [MessageThread] {
        MessageThreadBuilder.threads(from: visibleHistory, serverOrder: historySnapshot?.serverOrder)
    }

    /// **안 읽은 메시지가 있는 상대**(줄 점 · 개수 배지 · 탭 배지의 재료). 찌르기는 여기 들어오지 않는다 — 정렬용 합친
    /// 집합은 `sortUnreadPeerIDs` 다(인수인계 §6-4: 안 읽음이 찌르기뿐인 사람에게 "안 읽은 메시지"라고 말하지 않는다).
    package var unreadPeerIDs: Set<String> {
        MessageUnreadRules.unreadPeerIDs(
            history: visibleHistory,
            historySnapshot: historySnapshot,
            summary: visibleSummary,
            optimistic: optimisticReads,
            legacyStamps: legacyReadStamps
        )
    }

    /// 차단해 숨긴 상대를 걷어낸 찌르기 기록(이력·요약과 같은 관문 — 거르는 곳이 갈리면 목록에서 사라진 사람이 정렬만 올린다).
    package var visiblePokeLog: [MessagePokeLogEntry] {
        guard !hiddenBlockedPeerIDs.isEmpty else { return pokeLog }
        return pokeLog.filter { !hiddenBlockedPeerIDs.contains($0.peerUserID) }
    }

    /// 한 사람과 오간 찌르기(시간순 — 대화 화면이 메시지 사이에 끼울 재료).
    package func pokeLog(for peerID: String) -> [MessagePokeLogEntry] {
        visiblePokeLog.filter { $0.peerUserID == peerID }
    }

    /// **안 본 찌르기가 있는 상대.** 서버 플래그에서 그 스냅샷이 모르는 낙관 읽음을 뺀다(메시지와 같은 규칙).
    package var unreadPokePeerIDs: Set<String> {
        guard let pokeSnapshot else { return [] }
        return MessagePokeLogRules.unreadPeerIDs(
            log: visiblePokeLog, snapshot: pokeSnapshot, optimistic: optimisticPokeReads
        )
    }

    /// **정렬 전용** 안 읽음(메시지 ∪ 찌르기). 사용자 결정 2026-10-23 "안 본 찌르기도 안 읽음으로 친다".
    /// ★ 배지·"안 읽은 메시지 N"·줄 개수에는 쓰지 마라 — 그 수는 메시지 전용이다.
    package var sortUnreadPeerIDs: Set<String> {
        MessagesSortRules.combinedUnreadPeerIDs(messages: unreadPeerIDs, pokes: unreadPokePeerIDs)
    }

    /// 대화 목록 줄들 — **4단 정렬**(① 근무중+안읽음 → ② 근무안함+안읽음 → ③ 근무중+다읽음 → ④ 근무안함+다읽음),
    /// 같은 무리 안은 최근순. 근무 여부를 모르는 창에서는 근무 축을 쓰지 않는다(두 무리).
    /// 찌르기만 있는 사람도 한 줄이 선다(사용자 결정 (가)).
    package func threadItems(now: Date) -> [MessagesThreadItem] {
        let board = presenceBoard(now: now)
        return MessagesThreadListRules.rows(
            threads: threads,
            // ★ 차단 관문을 지난 기록만 쓴다(`visiblePokeLog`) — 날것 `pokeLog` 를 넘기면 목록에서 사라진 사람이
            //   찌르기만으로 행을 세우고 정렬까지 올라간다(`MessagesStore` 주석: "차단한 사람의 얼굴을 눌러 대화가 다시 열린다").
            pokes: visiblePokeLog,
            chronology: pokeChronology,
            messageUnreadPeerIDs: unreadPeerIDs,
            pokeUnreadPeerIDs: unreadPokePeerIDs,
            unreadCounts: unreadCountsByPeer,
            workingPeerIDs: MessagesSortRules.workingPeerIDs(board),
            workKnown: board.isKnown,
            now: now
        )
    }

    /// 상대별 안 읽은 메시지 수(목록 줄 개수 배지). 합 = `badgeCount`.
    package var unreadCountsByPeer: [String: Int] {
        MessagesBadgeRules.unreadCountsByPeer(
            history: visibleHistory,
            historySnapshot: historySnapshot,
            summary: visibleSummary,
            optimistic: optimisticReads,
            legacyStamps: legacyReadStamps
        )
    }

    /// 사람들의 근무 여부·센터(목록 줄 점 · "지금 근무 중" 줄 · 대화 머리). **서버를 부르지 않는다** — 지금 탭이 1분마다 받아 두는 팀 상태·
    /// 사람 목록과, 새 대화 시트가 받은 사람 목록을 겹쳐 읽는다(`MessagesPresenceRules.board`). 지금 탭 스토어가 관찰 대상이라 값이 바뀌면 다시 그린다.
    package func presenceBoard(now: Date) -> MessagesPresenceBoard {
        let nowStore = context.links.now
        let working = nowStore?.workingPeople(now: now) ?? []
        let teamIDs: Set<String> = nowStore.map { store in store.hasLoadedTeam ? Set(store.teamMembers.map(\.id)) : [] } ?? []
        return hidingBlocked(MessagesPresenceRules.board(
            nowWorking: working.map {
                MessagesPresenceRules.Working(id: $0.id, name: $0.name, avatarURL: $0.avatarURL, center: $0.center, isStale: $0.isStale)
            },
            teamMemberIDs: teamIDs,
            nowDirectory: nowStore.flatMap { $0.hasLoadedDirectory ? $0.directory : nil },
            messagesDirectory: directoryLoaded ? directory : nil,
            me: context.session.userID
        ))
    }

    /// 차단해 숨긴 사람을 판에서 걷어낸다. **"지금 근무 중 · 바로 말 걸기" 줄이 곧 말 거는 입구**라, 여기 남아 있으면
    /// 차단한 사람의 얼굴을 눌러 대화가 다시 열린다(판의 재료는 지금 탭·사람 목록이라 서버가 아직 빼지 못한 창이 있다).
    private func hidingBlocked(_ board: MessagesPresenceBoard) -> MessagesPresenceBoard {
        guard !hiddenBlockedPeerIDs.isEmpty, board.isKnown else { return board }
        return MessagesPresenceBoard(
            isKnown: board.isKnown,
            peers: board.peers.filter { !hiddenBlockedPeerIDs.contains($0.key) },
            working: board.working.filter { !hiddenBlockedPeerIDs.contains($0.id) },
            // 차단한 사람의 상태메시지도 같이 걷는다 — 대화 머리에 그 사람이 쓴 문장이 남지 않게.
            statuses: board.statuses.filter { !hiddenBlockedPeerIDs.contains($0.key) }
        )
    }

    package func thread(for peerID: String) -> MessageThread? {
        threads.first { $0.peerUserID == peerID }
    }

    /// 대화 머리 이름: 이력(가장 최신 이름) → **찌르기 기록**(메시지가 하나도 없는 사람) → 사람 찾기 목록 → nil.
    package func peerName(for peerID: String) -> String? {
        if let thread = thread(for: peerID) { return thread.peerName }
        if let poke = visiblePokeLog.last(where: { $0.peerUserID == peerID }) { return poke.peerName }
        return directory.first { $0.userID == peerID }?.name ?? replyPeerHints[peerID]?.name
    }

    /// 확성기 [답장]이 여는 대화의 이름·아바타를 적어 둔다(`peerName`·`peerAvatarURL` 의 마지막 기댈 곳).
    package func rememberPeerHint(peerID: String, name: String?, avatarURL: URL?) {
        guard name != nil || avatarURL != nil else { return }
        replyPeerHints[peerID] = MegaphoneReplyPeerHint(name: name, avatarURL: avatarURL)
    }

    /// 대화 머리. 이름을 모르면 가짜 이니셜 대신 일반 인물 아이콘(`MessagesConversationRules.header`).
    /// "받는 중" = 이력·사람 찾기 중 하나라도 날아가는 중이거나, 이력이 아직 한 번도 끝나지 않았다(실패도 아님).
    package func conversationHeader(for peerID: String) -> MessagesConversationHeader {
        let resolving = historyLoading || directoryLoading || (!historyLoaded && !historyFailed)
        return MessagesConversationRules.header(peerName: peerName(for: peerID), isResolving: resolving)
    }

    package func peerAvatarURL(for peerID: String) -> URL? {
        if let url = thread(for: peerID)?.peerAvatarURL { return url }
        if let url = visiblePokeLog.last(where: { $0.peerUserID == peerID })?.peerAvatarURL { return url }
        return directory.first { $0.userID == peerID }?.avatarURL ?? replyPeerHints[peerID]?.avatarURL
    }

    /// 차단해 숨긴 상대인가(대화 화면이 스스로 빠져나오는 근거 · 사람 찾기 거르기).
    package func isHiddenByBlock(_ peerID: String) -> Bool {
        hiddenBlockedPeerIDs.contains(peerID)
    }

    /// 대화 화면 줄(말풍선 · 날짜 · **찌르기 기록** · 보내는 중). 찌르기는 차단 관문을 지난 `pokeLog(for:)` 에서 온다.
    package func conversationItems(for peerID: String) -> [MessagesConversationItem] {
        MessagesConversationRules.items(
            messages: thread(for: peerID)?.messages ?? [],
            pokes: pokeLog(for: peerID),
            chronology: pokeChronology,
            pending: pendingOutgoing.filter { $0.peerUserID == peerID },
            receiptsAvailable: readReceiptsAvailable,
            now: context.clock.now()
        )
    }

    package func draft(for peerID: String) -> String {
        drafts[peerID] ?? ""
    }

    package func setDraft(_ text: String, for peerID: String) {
        guard !peerID.isEmpty else { return }
        if drafts[peerID] != text { drafts[peerID] = text }
    }

    /// 확정된 입력으로 지금 보낼 수 있는가(왕복 중 아님 · 본문이 서버 경계 안). 근무 여부는 보지 않는다(서버도 안 본다 — v0.3.30).
    package func canSend(to peerID: String) -> Bool {
        guard isSignedIn, !peerID.isEmpty, !isSending else { return false }
        if case .ok = MessageBody.validate(draft(for: peerID)) { return true }
        return false
    }

    /// 사람 찾기 목록(검색 + 차단해 숨긴 사람 제외). 서버도 서로 차단이면 목록에서 빼지만, 차단 직후의 이 화면은
    /// 아직 옛 목록을 쥐고 있다 — 방금 차단한 사람이 "새 대화"에 그대로 서 있으면 차단이 안 된 것처럼 보인다.
    package func filteredDirectory(query: String) -> [PokeDirectoryEntry] {
        let visible = hiddenBlockedPeerIDs.isEmpty ? directory : directory.filter { !hiddenBlockedPeerIDs.contains($0.userID) }
        // 정렬 입력은 **언제나 명시적으로** 넘긴다(코어 `sortedForPokeDisplay` 의 기본값에 기대지 않는다 —
        // 0.3.65 에서 기본값이 빠지고 인자가 하나 더 붙는다).
        return MessagesDirectoryRules.filter(visible, query: query, unreadPeerIDs: sortUnreadPeerIDs)
    }

    // MARK: - 화면 사건(탭 화면이 부른다)

    package func listDidAppear() {
        isListVisible = true
        guard isSignedIn else { return }
        let now = context.clock.now()
        let due = !historyLoaded || runtime.historyStale
            || now.timeIntervalSince(runtime.lastListRefreshAt) >= listRefreshThrottleSeconds
        guard due else { return }
        runtime.lastListRefreshAt = now
        requestActivityRefresh(includeHistory: true)
    }

    package func listDidDisappear() {
        isListVisible = false
    }

    /// 당겨서 새로고침(스로틀 없음 — 사람이 직접 청한 것). 끝날 때까지 기다린다.
    package func refreshNow() async {
        // 차단 한 줄은 사람이 목록을 다시 당기는 순간 지운다 — 지나간 실패·알림이 계속 머리에 남지 않게.
        blockNotice = nil
        blockNoticeIsError = false
        guard isSignedIn else { return }
        runtime.lastListRefreshAt = context.clock.now()
        await requestActivityRefresh(includeHistory: true)?.value
    }

    /// 대화 화면의 [다시 시도]. 이력을 곧바로 다시 받고, 그래도 상대 이름을 모르면 사람 찾기를 다시 받는다(스로틀 무시) —
    /// 오프라인에서 연 대화는 두 조회가 다 실패해 이력만 다시 받으면 머리가 계속 "대화"로 남는다.
    package func retryConversation(peerID: String) async {
        guard isSignedIn, !peerID.isEmpty else { return }
        await refreshNow()
        guard isSignedIn, peerName(for: peerID) == nil else { return }
        loadDirectory(force: true)
    }

    /// 대화 화면이 섰다. `token` 은 뷰 인스턴스마다 다르다 — 같은 상대의 새 화면이 옛 화면의 사라짐보다 먼저 서도 표시가 꺼지지 않게.
    package func conversationDidAppear(peerID: String, token: UUID) {
        guard !peerID.isEmpty else { return }
        runtime.shownConversations.removeAll { $0.token == token }
        runtime.shownConversations.append((token, peerID))
        openConversationPeerID = peerID
        syncRouterVisibility()
        guard isSignedIn else { return }
        legacyReadStamps[peerID] = context.clock.now()
        evaluateReadMarking()
        // 대화가 서면 언제나 최신을 받는다(스로틀 없음 — 합치기만).
        requestActivityRefresh(includeHistory: true)
        if thread(for: peerID) == nil, !directoryLoaded {
            loadDirectory()
        }
    }

    package func conversationDidDisappear(token: UUID) {
        runtime.shownConversations.removeAll { $0.token == token }
        let current = runtime.shownConversations.last?.peerID
        if openConversationPeerID != current { openConversationPeerID = current }
        syncRouterVisibility()
    }

    // MARK: - 보내기

    /// [보내기]. **조합 중이면 보내지 않는다**(`isComposing` — 화면이 조합을 확정한 뒤 다시 부른다). 보냈으면(왕복을 띄웠으면) true.
    ///
    /// 누르는 즉시 입력칸을 비우고 자리 말풍선을 세운다(메신저 감각). 서버가 거절하면 말풍선을 거두고, 그 사이 새로 친 글이 없으면
    /// 입력칸에 글을 되돌리고 문구를 세운다 — **보내지 못한 글은 사라지지 않는다**(맥: "실패해도 글은 남는다").
    ///
    /// 입력칸을 비우는 자리는 **여기 하나다**(`performSend` 가 아니다 — 이모티콘 입구는 초안을 읽지도 쓰지도 않는다).
    @discardableResult
    package func sendDraft(to peerID: String, isComposing: Bool) -> Bool {
        guard !isComposing, canSend(to: peerID) else { return false }
        guard case .ok(let body) = MessageBody.validate(draft(for: peerID)) else { return false }
        drafts[peerID] = ""
        return performSend(body: body, to: peerID, restoresDraftOnFailure: true)
    }

    /// 지금 아잉이 이모티콘을 보낼 수 있는가(1.0.12).
    ///
    /// **`canSend` 를 쓰지 않는 이유는 그 판정이 입력칸 글을 보기 때문이다**(`validate(draft) == .ok` — 빈 칸이면 거짓).
    /// 이모티콘의 본문은 상수 토큰이라 빈 칸·200자 판정이 **언제나** 통과하므로 남는 조건은 셋뿐이고, 그 셋은
    /// `canSend` 의 첫 줄과 **글자 그대로 같다**(순서까지 같게 적어 둔다). 근무 여부·집중 모드는 여기서도 보지 않는다
    /// (v0.3.30 에 서버가 그 조건을 지웠다 — `sendDraft` 주석).
    package func canSendSticker(to peerID: String) -> Bool {
        isSignedIn && !peerID.isEmpty && !isSending
    }

    /// 아잉이 이모티콘 한 장을 보낸다(1.0.12 · 맥 0.3.62 의 폰 쪽 사본).
    ///
    /// **입력칸을 거치지 않는다** — `drafts[peerID]` 를 읽지도 쓰지도 않는다. 토큰을 초안에 넣고 `sendDraft` 를
    /// 부르는 식으로 만들면 성공 분기의 `drafts[peerID] = ""` 가 사용자가 쓰던 글을 지우고, 실패 분기는 쓰던 글
    /// 대신 **토큰**을 입력칸에 꽂는다(맥에서 실제로 났던 결함 둘).
    ///
    /// 나갔는가를 돌려준다 — 그리드는 이 값으로 접을지 정한다. 못 보냈는데 접으면 화면에 남는 신호가 "그리드가
    /// 닫혔다" 하나뿐이라, 직전 전송의 안내를 보고 이모티콘도 간 줄 안다(맥 `sendSticker` 와 같은 규약).
    @discardableResult
    package func sendSticker(_ sticker: AingSticker, to peerID: String) -> Bool {
        guard canSendSticker(to: peerID) else { return false }
        return performSend(body: sticker.token, to: peerID, restoresDraftOnFailure: false)
    }

    /// 본문 하나를 보낸다 — 자리 말풍선 · 재시도 · 세대 가드 · 아홉 가지 실패 문구 · 성공 뒤 이력 재조회의 **공통 몸통**.
    /// 입구는 둘뿐이다(`sendDraft` · `sendSticker`). **새 전송 길을 뚫지 마라** — 두 벌이 갈리면 갈린 쪽은 실패한 날에만 드러난다.
    ///
    /// - Parameter restoresDraftOnFailure: 서버가 거절했을 때 본문을 입력칸으로 되돌릴지. **초안 전송 `true` · 이모티콘 `false`.**
    ///   두 값이 있는 이유는 맥에서 난 결함이다(v0.3.62): 이모티콘 전송이 입력칸을 공유하면 쓰던 글이 사라지거나
    ///   `[아잉:기쁨]` 으로 덮였다. 가르는 기준은 글자가 아니라 **의도**다 — 보낸 본문과 입력칸 글자를 비교해서
    ///   가르면, 왕복(0.2~1.5초) 중에 한 글자라도 이어 친 평범한 전송이 같이 깨진다.
    ///
    /// ── 전송 멱등 키(서버 안정화 2026-10-30 · 서버 20261101131000) ──
    /// ⓐ **자리 말풍선 id 가 곧 키다**(`clientMessageID: localID`). 두 벌로 만들면 확정할 말풍선과 서버가 거른 행이 갈린다.
    /// ⓑ 왕복이 모호하게 실패하면(`MessagesSendRules.isAmbiguousFailure` — 답을 못 받음) `sendRetryDelaySeconds` 뒤
    ///    **같은 키로 한 번만** 다시 보낸다. 단 이 실행에서 서버가 키를 안다는 증거(`serverKnowsSendKey`)를 본 뒤에만 —
    ///    키를 모르는 옛 서버면 코어가 옛 모양으로 되묻고, 그때 재시도는 **두 통**이 된다. 증거가 없으면 지금처럼 실패로 끝낸다.
    ///    증거는 마지막 ok 가 정한다 — message_id 없는 ok(되돌린 서버)를 보면 깃발을 내린다.
    /// ⓒ 답을 못 받고 끝난 전송은 (상대 · 본문 · 키 · 시각)을 기억했다가(`unconfirmedSends`) 창 안에 같은 상대에게 같은 본문을
    ///    다시 보내면 새 키 대신 그 키를 쓴다. 서버가 확정 답(ok · 거절 status)을 준 전송은 기억하지 않는다 —
    ///    같은 말을 일부러 두 번 보내는 것은 정상 사용이다.
    /// ⓓ 확정 경로는 그대로다(`.sent(settledSerial:)` + 이력 재조회가 거둔다). 응답의 `message_id` 로 말풍선을 확정하지
    ///    않는다 — `reconcile` 이 이미 "나중에 띄운 이력이 반영되면 거둔다"로 duplicate 응답까지 덮으므로, id 대조를 한 벌 더
    ///    두면 두 규칙이 갈리는 날 말풍선이 남거나 겹친다.
    @discardableResult
    private func performSend(body: String, to peerID: String, restoresDraftOnFailure: Bool) -> Bool {
        let generation = context.generation
        let now = context.clock.now()
        let localID = reusableSendKey(peerID: peerID, body: body, now: now) ?? UUID().uuidString.lowercased()
        pendingOutgoing.append(MessagesPendingOutgoing(
            id: localID, peerUserID: peerID, body: body, createdAt: now, state: .sending
        ))
        sendNotices[peerID] = nil
        isSending = true
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            var notice: String?
            var succeeded = false
            var cancelled = false
            var refreshesDirectory = false
            func roundTrip() async -> Result<PokeSendResponse, any Error> {
                do {
                    return .success(try await self.context.withMobileSessionRetry { session in
                        try await service.sendMessage(
                            accessToken: session.accessToken, to: peerID, body: body, clientMessageID: localID
                        )
                    })
                } catch {
                    return .failure(error)
                }
            }
            var result = await roundTrip()
            guard generation == self.context.generation else { return }
            if case .failure(let error) = result, self.runtime.serverKnowsSendKey,
               MessagesSendRules.isAmbiguousFailure(error) {
                // ⓑ 응답 유실 재시도 — 같은 Task · 같은 키 · 한 번. 기다리는 동안 로그아웃했으면 나가지 않는다(세대 가드).
                await self.sleep(self.sendRetryDelaySeconds)
                guard generation == self.context.generation else { return }
                result = await roundTrip()
                guard generation == self.context.generation else { return }
            }
            switch result {
            case .success(let response):
                let outcome = MessageSendOutcome(response: response)
                notice = MessagesSendRules.notice(for: outcome, maxLength: response.maxLength)
                succeeded = outcome == .ok
                refreshesDirectory = outcome == .targetNotWorking
                // 깃발은 **마지막 ok** 가 정한다 — message_id 없는 ok 는 키를 모르는 판이다(서버 되돌림 · 코어가 옛 모양으로 되물었다).
                // 한 번 선 깃발을 그대로 두면 되돌린 서버에서 재시도가 두 통을 만든다. 거절 status 는 판을 말하지 않으니 건드리지 않는다.
                if succeeded { self.runtime.serverKnowsSendKey = response.messageId != nil }
                // 확정 답 — 이 키·이 (상대, 본문)의 기억을 지운다(성공이면 다음 같은 말은 새 말이고, 거절이면 저장된 것이 없다).
                self.runtime.unconfirmedSends.removeAll {
                    $0.key == localID || ($0.peerUserID == peerID && $0.body == body)
                }
            case .failure(let error):
                if case .cancelled = AuthErrorRules.classify(error) {
                    cancelled = true
                } else {
                    notice = MessagesSendRules.connectionNotice
                }
                // ⓒ 던져진 실패는 모두 "답을 못 읽었다"로 기억한다(4xx·취소 포함). 저장되지 않았던 것이면 같은 키도 새 키와
                // 똑같이 한 통이라 잃는 것이 없고, 저장됐던 것이면 서버가 그 키로 거른다 — 넓게 잡는 쪽이 두 통을 막는다.
                self.rememberUnconfirmedSend(peerID: peerID, body: body, key: localID)
            }
            self.isSending = false
            if succeeded {
                if let index = self.pendingOutgoing.firstIndex(where: { $0.id == localID }) {
                    self.pendingOutgoing[index].state = .sent(settledSerial: self.runtime.nextSerial())
                }
                // 방금 보낸 말이 서버 행으로 서게 이력을 곧바로 받는다(자리 말풍선은 그 응답이 거둔다).
                self.requestActivityRefresh(includeHistory: true)
                return
            }
            self.pendingOutgoing.removeAll { $0.id == localID }
            // 되돌리는 쪽만 입력칸을 만진다(이모티콘은 거짓 — 위 `restoresDraftOnFailure` 주석).
            // "비어 있을 때만"은 그대로다: 왕복 중에 새로 친 글을 실패한 옛 글이 덮으면 안 된다.
            if restoresDraftOnFailure, self.draft(for: peerID).isEmpty { self.drafts[peerID] = body }
            if !cancelled, let notice { self.sendNotices[peerID] = notice }
            if refreshesDirectory { self.loadDirectory(force: true) }
        }
        return true
    }

    /// 창 안에 답을 못 받은 같은 (상대, 본문) 전송이 있으면 그 키(ⓒ). 지난 기억은 여기서 걷는다.
    ///
    /// 그 키가 떠 있는 자리 말풍선 id 와 겹치면 쓰지 않는다 — 실패 분기가 말풍선을 먼저 거두고(`removeAll { $0.id == localID }`)
    /// 전송은 한 번에 하나라 정상 경로에선 겹칠 수 없지만, 겹치면 `.sent` 확정이 엉뚱한 말풍선을 집는다.
    private func reusableSendKey(peerID: String, body: String, now: Date) -> String? {
        let window = unconfirmedSendReuseSeconds
        runtime.unconfirmedSends.removeAll { now.timeIntervalSince($0.failedAt) > window }
        guard let entry = runtime.unconfirmedSends.last(where: { $0.peerUserID == peerID && $0.body == body }),
              !pendingOutgoing.contains(where: { $0.id == entry.key }) else { return nil }
        return entry.key
    }

    /// 답을 못 받고 끝난 전송을 기억한다(같은 키·같은 (상대, 본문)의 옛 기억은 바꿔 끼운다 · 시각은 마지막 실패).
    private func rememberUnconfirmedSend(peerID: String, body: String, key: String) {
        runtime.unconfirmedSends.removeAll { $0.key == key || ($0.peerUserID == peerID && $0.body == body) }
        runtime.unconfirmedSends.append(MessagesUnconfirmedSend(
            peerUserID: peerID, body: body, key: key, failedAt: context.clock.now()
        ))
        // 끝없이 쌓이지 않게(창이 10분이라 실제로는 몇 개를 넘지 않는다) — 오래된 것부터 버린다.
        if runtime.unconfirmedSends.count > 16 { runtime.unconfirmedSends.removeFirst(runtime.unconfirmedSends.count - 16) }
    }

    // MARK: - 사람 찾기

    /// `app_user_directory`(읽기). 새 대화 시트가 설 때 · 이름을 모르는 대화가 설 때.
    package func loadDirectory(force: Bool = false) {
        guard isSignedIn, !directoryLoading else { return }
        let now = context.clock.now()
        if !force, directoryLoaded, now.timeIntervalSince(runtime.lastDirectoryLoadAt) < directoryRefreshThrottleSeconds { return }
        runtime.lastDirectoryLoadAt = now
        let generation = context.generation
        directoryLoading = true
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rows = try await self.context.withMobileSessionRetry { session in
                    try await service.fetchPokeDirectory(accessToken: session.accessToken)
                }
                guard generation == self.context.generation else { return }
                self.directoryLoading = false
                // ★ 저장 순서에는 **안 읽음 축을 넣지 않는다**(값은 명시적으로 적는다 — 기본값에 기대지 않는다).
                //   이 배열은 60초 스로틀이 걸린 사람 **캐시**이고 화면이 직접 읽는 순서가 아니다(새 대화 시트는
                //   `filteredDirectory` 를 지난다). 안 읽음은 메시지 한 통·찌르기 한 번마다 바뀌는데 이 배열은 RPC 를
                //   다시 받을 때만 다시 정렬되므로, 여기 구운 안 읽음 순서는 받는 순간부터 낡는다.
                //   진짜 정렬 자리는 `filteredDirectory` 하나이고, 거기서 **그 순간의** 합친 집합을 넘긴다.
                //   `workKnown: true` — 명부 행은 `isWorking` 을 서버에서 직접 받는다(모르는 창이 없다).
                self.directory = rows.toPokeDirectoryEntries().sortedForPokeDisplay(unreadPeerIDs: [], workKnown: true)
                self.directoryLoaded = true
                self.directoryFailed = false
            } catch {
                guard generation == self.context.generation else { return }
                self.directoryLoading = false
                if case .cancelled = AuthErrorRules.classify(error) { return }
                if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                    self.directoryLoaded = true
                } else {
                    self.directoryFailed = true
                }
            }
        }
    }

    // MARK: - 메시지 활동 새로고침

    /// 요약 1회(+ 메시지 화면이 떠 있거나 `includeHistory` 면 이력 1회 — 나란히). 돌고 있으면 뒤따르는 한 번으로 합친다.
    /// 이력을 건너뛰면 "낡음"을 적어 다음에 화면이 설 때 스로틀과 무관하게 받는다.
    @discardableResult
    package func requestActivityRefresh(includeHistory: Bool = false) -> Task<Void, Never>? {
        guard isSignedIn else { return nil }
        if includeHistory || isMessagesScreenVisible {
            runtime.activityWantsHistory = true
        } else {
            runtime.historyStale = true
        }
        if let running = runtime.activityTask {
            runtime.activityAgain = true
            return running
        }
        let generation = context.generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                // 루프 안에서 먼저 내린다 — 이번 조회가 도는 동안 온 계기를 지우지 않게.
                self.runtime.activityAgain = false
                let wantsHistory = self.runtime.activityWantsHistory
                self.runtime.activityWantsHistory = false
                if wantsHistory {
                    async let summaryDone: Void = self.performLoadSummary()
                    async let historyDone: Void = self.performLoadHistory()
                    _ = await (summaryDone, historyDone)
                } else {
                    await self.performLoadSummary()
                }
                guard generation == self.context.generation else { return }
            } while self.runtime.activityAgain
            self.runtime.activityTask = nil
        }
        runtime.activityTask = task
        return task
    }

    /// 이력 1회. 모든 이력 조회가 이 문을 지난다 — **띄운 순서 번호**가 반영 여부를 정한다.
    package func performLoadHistory() async {
        guard isSignedIn else { return }
        let generation = context.generation
        let serial = runtime.nextSerial()
        runtime.lastHistoryLaunchSerial = serial
        runtime.historyInFlight += 1
        if !historyLoading { historyLoading = true }
        defer {
            if generation == context.generation {
                runtime.historyInFlight -= 1
                if runtime.historyInFlight == 0, historyLoading { historyLoading = false }
            }
        }
        do {
            let conversation = try await context.withMobileSessionRetry { session in
                try await fetchConversationLoad(accessToken: session.accessToken)
            }
            let loaded = conversation.history
            guard generation == context.generation else { return }
            // 더 나중에 띄운 조회가 이미 반영됐다 — 이 응답은 그보다 낡은 서버 상태다(새 줄·꺼진 1 을 되돌리면 안 된다).
            guard serial > runtime.lastAppliedHistorySerial else { return }
            runtime.lastAppliedHistorySerial = serial
            if let staleSince = runtime.historyStaleSerial, serial > staleSince {
                runtime.historyStaleSerial = nil
            }
            let previousIDs = Set(history.map(\.id))
            let sorted = loaded.entries.sortedForMessageHistory(serverOrder: loaded.hasReadReceipts ? loaded.serverOrder : nil)
            if history != sorted { history = sorted }
            if loaded.hasReadReceipts {
                let snapshot = MessageHistoryReadSnapshot(serial: serial, serverOrder: loaded.serverOrder)
                if historySnapshot != snapshot { historySnapshot = snapshot }
                if !readReceiptsAvailable { readReceiptsAvailable = true }
            } else {
                if historySnapshot != nil { historySnapshot = nil }
                if readReceiptsAvailable { readReceiptsAvailable = false }
            }
            applyPokeLog(conversation, serial: serial)
            let reconciled = MessagesPendingRules.reconcile(
                pending: pendingOutgoing, previousHistoryIDs: previousIDs, applied: sorted, appliedSerial: serial
            )
            if reconciled != pendingOutgoing { pendingOutgoing = reconciled }
            if !historyLoaded { historyLoaded = true }
            if historyFailed { historyFailed = false }
            // 새 이력 — 떠 있는 대화에 서버 기준 안 읽은 말이 있으면 올린다(새로 도착한 말 포함).
            evaluateReadMarking()
            // 📢 로 시작하는데 확성기인지 아직 모르는 받은 줄 — refresh 한 번 뒤 판정(계약 C3 경합).
            verifyMegaphoneRows()
        } catch {
            guard generation == context.generation else { return }
            if case .cancelled = AuthErrorRules.classify(error) { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 세 이력 함수가 다 없는 서버 — 실패가 아니라 "받을 것이 없다". 빈 이력으로 조용히 접는다.
                if !historyLoaded { historyLoaded = true }
                if readReceiptsAvailable { readReceiptsAvailable = false }
                applyPokeLog(MessageConversationLoad(history: MessageHistoryLoad(entries: [], hasReadReceipts: false), pokes: nil), serial: serial)
                runtime.historyStaleSerial = nil
            } else {
                if !historyFailed { historyFailed = true }
            }
        }
    }

    /// 새 이력(메시지 + 찌르기 기록)을 반영한다. `pokes == nil`(옛 서버로 접음)이면 찌르기 쪽을 **전부 비운다** —
    /// 서버가 모르는 동안 옛 기록이 남아 있으면 정렬이 사라진 근거로 사람을 올리고, 대화 줄에 유령 찌르기가 남는다.
    private func applyPokeLog(_ conversation: MessageConversationLoad, serial: Int) {
        guard let pokes = conversation.pokes else {
            if !pokeLog.isEmpty { pokeLog = [] }
            if pokeLogAvailable { pokeLogAvailable = false }
            if !pokeChronology.isEmpty { pokeChronology = [:] }
            if pokeSnapshot != nil { pokeSnapshot = nil }
            return
        }
        let sorted = MessagePokeLogRules.sorted(pokes, chronology: conversation.chronology)
        if pokeLog != sorted { pokeLog = sorted }
        if pokeChronology != conversation.chronology { pokeChronology = conversation.chronology }
        // 찌르기 경계 비교는 **같은 표**(메시지·찌르기 공통 순위)로 한다 — 메시지 서버 순서에는 찌르기 id 가 없다.
        let snapshot = MessageHistoryReadSnapshot(serial: serial, serverOrder: conversation.chronology)
        if pokeSnapshot != snapshot { pokeSnapshot = snapshot }
        if !pokeLogAvailable { pokeLogAvailable = true }
    }

    /// `message_history_with_pokes` → 없는 서버(404/PGRST202)면 **지금까지의 사슬 그대로**
    /// (`message_history_with_reads` → `message_history`). 접힌 응답에는 찌르기 줄이 없을 뿐 대화는 그대로 돈다.
    /// 폴백은 캐시하지 않는다(맥과 같은 판단 — 서버가 배포되는 순간 다음 조회부터 새 길로 간다).
    private func fetchConversationLoad(accessToken: String) async throws -> MessageConversationLoad {
        do {
            let combined = try await context.service.fetchMessageHistoryWithPokes(
                accessToken: accessToken,
                hours: MessageNoticeText.historyHours,
                limit: MessageNoticeText.historyLimit
            )
            return MessageConversationLoad(
                history: MessageHistoryLoad(entries: combined.messages, hasReadReceipts: true),
                pokes: combined.pokes,
                chronology: combined.chronology
            )
        } catch let error as SupabaseWorkServiceError where Self.isMissingFunction(error) {
            return MessageConversationLoad(
                history: try await fetchHistoryPreferringReads(accessToken: accessToken), pokes: nil
            )
        }
    }

    /// `message_history_with_reads` → 없는 서버(404/PGRST202)면 옛 `message_history`(읽음 모름). 폴백은 캐시하지 않는다(맥과 같은 판단).
    private func fetchHistoryPreferringReads(accessToken: String) async throws -> MessageHistoryLoad {
        do {
            let entries = try await context.service.fetchMessageHistoryWithReads(
                accessToken: accessToken,
                hours: MessageNoticeText.historyHours,
                limit: MessageNoticeText.historyLimit
            )
            return MessageHistoryLoad(entries: entries, hasReadReceipts: true)
        } catch let error as SupabaseWorkServiceError where Self.isMissingFunction(error) {
            let entries = try await context.service.fetchMessageHistory(
                accessToken: accessToken,
                hours: MessageNoticeText.historyHours,
                limit: MessageNoticeText.historyLimit
            )
            return MessageHistoryLoad(entries: entries, hasReadReceipts: false)
        }
    }

    /// "이 서버에는 그 함수가 없다"(맥 `isMissingMessageReadFunction` 과 같은 판정). 401/403·5xx·네트워크는 넣지 않는다.
    package nonisolated static func isMissingFunction(_ error: SupabaseWorkServiceError) -> Bool {
        switch error {
        case .databaseSchemaMissing: return true
        case .invalidResponse(let status): return status == 404
        default: return false
        }
    }

    /// 요약 1회.
    package func performLoadSummary() async {
        guard isSignedIn else { return }
        let generation = context.generation
        let banner = context.links.megaphoneBanner
        // 배너 필터의 첫 판정(로그인 직후 `.unknown`)이 돌고 있으면 기다린다 — 요약 함수(v1/v2)는 필터와 짝이어야 한다
        // (필터가 켜졌는데 옛 요약을 쓰면 숨긴 확성기 줄을 세어 배지가 안 꺼진다). 판정이 끝난 뒤의 요약은 기다리지 않는다.
        if let banner, banner.capability == .unknown, let probe = runtime.megaphoneProbe {
            await probe.value
            guard generation == context.generation else { return }
        }
        let serial = runtime.nextSerial()
        runtime.lastSummaryLaunchSerial = serial
        do {
            let response: MessageUnreadSummaryResponse
            if let banner {
                // 필터가 켜져 있으면 v2(확성기 줄을 안 센다), 아니면 옛 함수. v2 가 없으면 코어가 필터를 끄고 옛 함수로 다시 부른다.
                runtime.lastSummaryFunction = banner.unreadSummaryFunction
                response = try await banner.fetchUnreadSummary()
            } else {
                response = try await context.withMobileSessionRetry { session in
                    try await context.service.fetchMessageUnreadSummary(accessToken: session.accessToken)
                }
            }
            guard generation == context.generation else { return }
            guard let value = response.summary else { return }
            // 늦게 온 옛 요약이 새 요약을 덮지 않게(이력과 같은 번호 규칙).
            guard serial > (summary?.serial ?? 0) else { return }
            let snapshot = MessageUnreadSummarySnapshot(serial: serial, summary: value)
            if summary != snapshot { summary = snapshot }
        } catch {
            // 함수 없음·장애 — 요약 없이 이력(또는 옛 도장) 기준으로 산다. 문구를 세우지 않는다(배지 재료일 뿐이다).
        }
    }

    // MARK: - 읽음

    /// **읽음을 올리는 유일한 자리.** 앱 active · 그 대화 화면이 떠 있음 · 서버 기준 안 본 것(메시지 **또는** 찌르기)이
    /// 있음 — 셋이 다 맞을 때만. 두 갈래는 한 왕복(`mark_conversation_read`)으로 같이 올린다.
    package func evaluateReadMarking() {
        guard isSignedIn, isAppActive, let peer = openConversationPeerID else { return }
        let through = historySnapshot.flatMap { snapshot in
            MessageUnreadRules.markTarget(
                peer: peer, history: visibleHistory, snapshot: snapshot, optimistic: optimisticReads[peer]
            )
        }
        // ★ 찌르기 경계는 **화면에 보인 마지막 받은 찌르기 id** 다(인수인계 §6-3). 지금 시각으로 올리지 않는다 —
        //   대화를 연 뒤 도착해 아직 안 그려진 찌르기까지 '봤다'가 되면 그 줄은 영영 안 읽음 표시를 못 받는다.
        let pokeThrough = pokeSnapshot.flatMap { snapshot in
            MessagePokeLogRules.markTarget(
                peer: peer, log: visiblePokeLog, snapshot: snapshot, optimistic: optimisticPokeReads[peer]
            )
        }
        guard through != nil || pokeThrough != nil else { return }
        markRead(peer: peer, through: through, pokeThrough: pokeThrough)
    }

    /// 읽음 처리 1회. 상대별로 겹치지 않는다(날아가는 중이면 끝난 뒤 한 번 더 판정). 응답 전에 낙관 읽음으로 점·배지를 곧바로 끈다 —
    /// 실패해도 되돌리지 않고(정산만), 그보다 나중에 띄운 서버 조회가 사실을 말한다.
    private func markRead(peer: String, through: String?, pokeThrough: String?) {
        guard !runtime.markInFlight.contains(peer) else {
            runtime.markAgain.insert(peer)
            return
        }
        runtime.markInFlight.insert(peer)
        if let through {
            let record = MessageOptimisticRead(throughID: through, recordedSerial: runtime.nextSerial())
            if optimisticReads[peer] != record { optimisticReads[peer] = record }
        }
        if let pokeThrough {
            let record = MessageOptimisticRead(throughID: pokeThrough, recordedSerial: runtime.nextSerial())
            if optimisticPokeReads[peer] != record { optimisticPokeReads[peer] = record }
        }
        let generation = context.generation
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            var succeeded = false
            do {
                // 찌르기만 올릴 때는 `p_through_message` 를 **싣지 않는다**(코어 `MessageConversationReadMarkRequest` 가
                // nil 칸의 키를 빼고 보낸다 · 인수인계 §2-2 "null 인 갈래는 움직이지 않는다"). 옛 `mark_messages_read` 와
                // 달리 이 함수는 빈 경계를 "최신까지"로 읽지 않는다.
                let response = try await self.context.withMobileSessionRetry { session in
                    try await service.markConversationRead(
                        accessToken: session.accessToken, peerUserID: peer,
                        throughMessageID: through, throughPokeID: pokeThrough
                    )
                }
                succeeded = response.isOK
            } catch let error as SupabaseWorkServiceError where Self.isMissingFunction(error) {
                // 옛 서버 — 찌르기를 모르니 메시지 갈래만 옛 함수로 접는다. 경계가 없으면 아무것도 올리지 않는다
                // (옛 `mark_messages_read` 는 p_through 가 null 이면 **그 사람의 최신까지** 올린다).
                if let through {
                    do {
                        let response = try await self.context.withMobileSessionRetry { session in
                            try await service.markMessagesRead(
                                accessToken: session.accessToken, peerUserID: peer, throughMessageID: through
                            )
                        }
                        succeeded = response.isOK
                    } catch {
                        // 아래와 같다 — "이번엔 못 올렸다".
                    }
                }
            } catch {
                // 취소·네트워크 — "이번엔 못 올렸다". 낙관 표시는 되돌리지 않는다.
            }
            guard generation == self.context.generation else { return }
            self.runtime.markInFlight.remove(peer)
            self.settleOptimisticRead(peer: peer, through: through, pokeThrough: pokeThrough, succeeded: succeeded)
            if succeeded { self.schedulePostMarkRefresh() }
            if self.runtime.markAgain.remove(peer) != nil { self.evaluateReadMarking() }
        }
    }

    private func settleOptimisticRead(peer: String, through: String?, pokeThrough: String?, succeeded: Bool) {
        if let through, var record = optimisticReads[peer], record.throughID == through, record.settledSerial == nil {
            record.settledSerial = runtime.nextSerial()
            record.failed = !succeeded
            optimisticReads[peer] = record
        }
        if let pokeThrough, var record = optimisticPokeReads[peer], record.throughID == pokeThrough, record.settledSerial == nil {
            record.settledSerial = runtime.nextSerial()
            record.failed = !succeeded
            optimisticPokeReads[peer] = record
        }
    }

    /// 읽음 성공 뒤 요약을 한 번 — 창 안에 다른 새로고침(메아리 신호 등)이 이미 떴으면 그것이 맡는다.
    private func schedulePostMarkRefresh() {
        runtime.postMarkPendingSerial = runtime.serial
        guard runtime.postMarkWindowTask == nil else { return }
        let generation = context.generation
        let seconds = postMarkRefreshSeconds
        let sleep = sleep
        runtime.postMarkWindowTask = Task { @MainActor [weak self] in
            await sleep(seconds)
            guard let self, !Task.isCancelled, generation == self.context.generation else { return }
            self.runtime.postMarkWindowTask = nil
            guard self.runtime.lastSummaryLaunchSerial <= self.runtime.postMarkPendingSerial else { return }
            self.requestActivityRefresh()
        }
    }

    // MARK: - 확성기 배너(계약 docs/plan/megaphone-banner-contract.md — 폰)

    /// 배너 스토어가 `megaphone_inbox` 를 한 번 읽는다(앞으로 올 때마다). 돌고 있으면 또 띄우지 않는다 —
    /// 코어 `refresh` 는 진행 중에 들어온 호출을 **한 번 더** 돌리므로 겹쳐 부르면 inbox 가 두 번 나간다.
    private func startMegaphoneProbe() {
        guard let banner = context.links.megaphoneBanner, !runtime.megaphoneProbeRunning else { return }
        runtime.megaphoneProbeRunning = true
        let generation = context.generation
        runtime.megaphoneProbe = Task { @MainActor [weak self] in
            await banner.refresh()
            guard let self, generation == self.context.generation else { return }
            self.runtime.megaphoneProbeRunning = false
            self.megaphoneFilterDidSettle()
        }
    }

    /// 판정 보류 줄(받은 줄 · `📢` 접두 · id 모름)을 refresh 한 번 뒤 판정한다(계약 C3 — 울림·이력이 배너 신호보다 먼저 올 수 있다).
    /// 첫 판정(probe)이 돌고 있으면 그것을 먼저 기다리고, 그래도 모르는 줄만 `refresh(verifying:)` 에 넘긴다. 그 뒤에도 모르면
    /// (위조 DM · 연결 실패) 코어가 "확인함"으로 적어 메시지로 보인다 — 접두만 보고 숨기지 않는다.
    private func verifyMegaphoneRows() {
        guard let banner = megaphoneFilter else { return }
        let pending = Set(history.lazy.filter { !$0.isMine && banner.needsVerification(messageID: $0.id, body: $0.body) }.map(\.id))
        guard !pending.isEmpty, !pending.isSubset(of: runtime.megaphoneVerifying) else { return }
        runtime.megaphoneVerifying.formUnion(pending)
        let generation = context.generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let probe = self.runtime.megaphoneProbe { await probe.value }
            guard generation == self.context.generation else { return }
            let still = Set(self.history.lazy.filter { pending.contains($0.id) && banner.needsVerification(messageID: $0.id, body: $0.body) }.map(\.id))
            if !still.isEmpty { await banner.refresh(verifying: still) }
            guard generation == self.context.generation else { return }
            self.runtime.megaphoneVerifying.subtract(pending)
            self.megaphoneFilterDidSettle()
        }
    }

    /// 배너 판정이 바뀌었을 수 있다 — 요약 함수 짝을 맞추고(옛 함수로 받은 요약 뒤에 필터가 켜졌으면 다시 받는다),
    /// 보류에서 풀린 줄이 떠 있는 대화에 있으면 읽음을 올린다.
    private func megaphoneFilterDidSettle() {
        guard isSignedIn else { return }
        if let used = runtime.lastSummaryFunction, let banner = context.links.megaphoneBanner, used != banner.unreadSummaryFunction {
            requestActivityRefresh()
        }
        evaluateReadMarking()
    }

    /// 보낸 직후 내 배너(닉네임·아바타는 나 탭이 아는 것 — 모르면 코어 기본 이름).
    private func presentOwnMegaphone(body: String, megaphoneID: String?) {
        guard isSignedIn, let banner = context.links.megaphoneBanner else { return }
        let me = context.links.me
        banner.presentOwn(body: body, senderName: me?.displayName ?? "", senderAvatarURL: me?.avatarURL, megaphoneID: megaphoneID)
    }

    // MARK: - 실시간 핸들러

    private func realtimeMessageActivity() {
        guard isSignedIn, isAppActive else { return }
        requestActivityRefresh()
    }

    private func realtimeMessageRead() {
        guard isSignedIn, isAppActive else { return }
        requestActivityRefresh()
    }

    // MARK: - 내부

    /// 메시지 화면(목록 또는 대화)이 지금 보이는가.
    private var isMessagesScreenVisible: Bool {
        isAppActive && (isListVisible || openConversationPeerID != nil)
    }

    private func syncRouterVisibility() {
        let visible = isAppActive ? openConversationPeerID : nil
        if context.router.visibleConversationPeerID != visible {
            context.router.visibleConversationPeerID = visible
        }
    }

    // MARK: - 테스트 창구

    /// 기다리는 새로고침·읽음 창(테스트가 끝날 때까지 기다린다).
    package var pendingActivityTask: Task<Void, Never>? { runtime.activityTask }
    package var pendingPostMarkTask: Task<Void, Never>? { runtime.postMarkWindowTask }
    package var isMarkingRead: Bool { !runtime.markInFlight.isEmpty }
    package var isHistoryStale: Bool { runtime.historyStale }
    package var serverKnowsSendKey: Bool { runtime.serverKnowsSendKey }
    package var unconfirmedSends: [MessagesUnconfirmedSend] { runtime.unconfirmedSends }
}

/// 비관찰 장부. 로그아웃이 통째로 새것으로 바꾼다(옛 작업이 새 장부를 만지지 않게 — 세대 가드와 함께).
@MainActor
private final class MessagesRuntime {
    private(set) var serial = 0
    var lastAppliedHistorySerial = 0
    var lastHistoryLaunchSerial = 0
    var lastSummaryLaunchSerial = 0
    var historyInFlight = 0
    var activityTask: Task<Void, Never>?
    var activityAgain = false
    var activityWantsHistory = false
    /// 이력을 건너뛴 계기의 순간(그보다 나중에 띄운 이력이 반영되면 내린다). nil = 낡지 않음.
    var historyStaleSerial: Int?
    var lastListRefreshAt: Date = .distantPast
    var lastDirectoryLoadAt: Date = .distantPast
    var markInFlight: Set<String> = []
    var markAgain: Set<String> = []
    var postMarkWindowTask: Task<Void, Never>?
    var postMarkPendingSerial = 0
    var shownConversations: [(token: UUID, peerID: String)] = []
    /// 이 실행에서 서버가 전송 멱등 키를 안다는 증거를 봤는가 — **마지막** `ok` 응답에 `message_id` 가 실렸으면 참
    /// (그 뒤 message_id 없는 ok 를 보면 다시 거짓 — 서버를 되돌린 판). 응답 유실 재시도(`performSend` ⓑ)의 문이다.
    /// 로그아웃이 장부째 바꾸므로 다음 계정은 거짓에서 시작한다.
    var serverKnowsSendKey = false
    /// 답을 못 받고 끝난 전송들(`performSend` ⓒ · 오래된 것 → 최신).
    var unconfirmedSends: [MessagesUnconfirmedSend] = []
    /// 확성기 배너 첫 판정(앞으로 올 때마다 한 번 — `startMegaphoneProbe`). 요약이 `.unknown` 동안 이것을 기다린다.
    var megaphoneProbe: Task<Void, Never>?
    var megaphoneProbeRunning = false
    /// 판정 보류 줄 중 refresh 를 기다리는 id(같은 줄로 refresh 를 겹쳐 띄우지 않게).
    var megaphoneVerifying: Set<String> = []
    /// 마지막 요약을 받은 함수 이름(v1/v2) — 필터가 바뀌면 다시 받을지 가른다.
    var lastSummaryFunction: String?

    nonisolated init() {}

    var historyStale: Bool {
        get { historyStaleSerial != nil }
        set { historyStaleSerial = newValue ? serial : nil }
    }

    func nextSerial() -> Int {
        serial += 1
        return serial
    }

    func cancelAll() {
        activityTask?.cancel()
        activityTask = nil
        megaphoneProbe?.cancel()
        megaphoneProbe = nil
        postMarkWindowTask?.cancel()
        postMarkWindowTask = nil
    }
}
