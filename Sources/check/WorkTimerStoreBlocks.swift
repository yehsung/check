import Foundation
import CheckCore

// MARK: - 차단 · 신고 (v0.3.34 — 맥, 2026-09-20)
//
// 사용자 요청(2026-09-20): "신고같은거 모바일에 추가되었잖아. 그럼 맥에도 추가되어야 하는거 아니야? 신고, 차단 이런거"
//
// 폰(1.0)에 차단·신고가 들어갔고 서버가 차단을 강제한다(마이그레이션 20260918180000 — send_message · poke_user ·
// ultra_poke_user · app_user_directory · message_history · gomoku_challenge/respond/lobby 에 게이트). 그래서 폰에서 차단하면
// 맥에서도 막히는데, **맥만 쓰는 사람은 차단·신고를 걸 방법이 없었다.** 맥에도 1:1 메시지와 오목 대국 채팅이 있다.
// 서버는 건드리지 않는다 — RPC 넷(`block_user` · `unblock_user` · `list_blocks` · `report_content`)과 코어 클라 함수가 이미 있다.
//
// ── 이 파일이 지키는 것(폰 `MessagesBlockStore` 와 같은 규칙) ──
// ① **확인 없이는 차단하지 않는다.** 차단 왕복(`blockPeer`)은 `private` 이고, 부르는 문은 확인 시트의 [차단하기]
//    (`confirmBlockFromSheet`) 하나다. 메뉴·우클릭은 시트를 **열기만** 한다. 차단은 상대에게 알리지 않는 조용한 동작이라
//    잘못 눌러도 사용자가 알아챌 신호가 없다.
// ② **사유 없이는 신고하지 않는다.** 화면이 버튼을 잠그고(`BlockReportRules.canSubmitReport`) 스토어가 같은 조건을 **다시** 본다 —
//    비활성만 두면 왜 막혔는지 말할 기회가 없다. 자유 입력은 200자(코드포인트 — 서버 `char_length` 와 같은 눈금).
// ③ **차단 직후 화면은 서버를 기다리지 않는다.** 확인 시트를 지나면 그 상대를 곧바로 걷어낸다(`blockHiddenPeerIDs`) —
//    콕 찌르기 목록 · 안 읽음 점 · 받은 메시지 줄 · 열린 대화 · 오목 로비 · 받은 신청 · 배너. 실패하면 되돌리고 이유를 말한다.
// ④ **서버가 아직 없는 창**(앱이 db push 보다 먼저 나간 창)에서는 "고장"이 아니라 "아직"이라고 말한다(`BlockReportText.serverNotReady`).
// ⑤ 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정의 숨김·목록·문구를 건드리지 않는다.
// ⑥ **신고 본문은 사람이 쓴 문장이다.** 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라(메시지 파일 공통 규약).
//
// 비동기 관용구는 메시지·제보 절과 같다: 세션 가드 → 세대 캡처 → `withSessionRetry` → 세대 가드.

/// 신고·차단 시트가 서는 자리. 시트와 결과 한 줄은 **연 자리에만** 선다 — 팝오버와 오목 창은 동시에 떠 있을 수 있어서,
/// 자리를 안 가르면 오목 창에서 연 신고가 팝오버 대화에도 그려진다.
enum BlockReportSurface: Equatable, Sendable {
    /// 팝오버의 1:1 대화 패널(과 그 뒤의 콕 찌르기 목록).
    case message
    /// 오목 창의 대국 채팅.
    case gomoku
}

/// 신고·차단 대상. 사람 하나 · 또는 그 사람이 보낸 **1:1 메시지** 한 건(오목 채팅 줄은 다른 표라 id 를 싣지 않는다).
struct BlockReportTarget: Equatable, Sendable {
    let peerID: String
    let peerName: String
    /// 메시지 한 건을 신고할 때 그 메시지 id(`report_content(p_message_id)`). nil 이면 사람 신고.
    var messageID: String? = nil
    /// 신고하는 메시지 본문(시트에 한 번 보여 준다 — 무엇을 신고하는지 눈으로 확인하게). 서버에는 id 만 간다.
    var messageBody: String? = nil
    /// 오목 채팅에서 연 시트가 묶인 **판 id**(서버에는 안 간다 — 대국 채팅 줄은 신고 표와 다른 표다). 그 판이 내려가면
    /// (다음 판 · 로비) 시트는 서지 않는다(`blockReportSheet(on:)` — v0.3.34 수리: 앞 판의 시트가 다음 판을 덮었다).
    var matchID: String? = nil
}

/// 지금 떠 있는 시트.
struct BlockReportSheet: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// 차단 확인(막히는 것 · 안 막히는 것 · 푸는 자리 → [차단하기]).
        case blockConfirm
        /// 신고(사유 넷 · 자세히 200자 · 신고하면서 차단 · 24시간 약속 → [신고 보내기]).
        case report
    }

    let kind: Kind
    let target: BlockReportTarget
    let surface: BlockReportSurface
}

/// 결과 한 줄(차단 되돌림 실패 · 신고 접수). 성공만 초록이고 나머지는 경고색이다(메시지·제보 결과 줄과 같은 규약).
struct BlockReportNotice: Equatable, Sendable {
    let text: String
    let isError: Bool
    let surface: BlockReportSurface
}

/// ··· 메뉴의 항목(순수 — 결정적 검증 지점). 두 입구(대화 머리 · 오목 채팅 머리)가 **같은 표**를 읽는다.
enum BlockReportMenuItem: CaseIterable, Equatable, Sendable {
    case report
    case block

    var title: String {
        switch self {
        case .report: return BlockReportText.reportAction
        case .block: return BlockReportText.blockAction
        }
    }

    var systemImage: String {
        switch self {
        case .report: return "exclamationmark.bubble"
        case .block: return "nosign"
        }
    }
}

/// 말풍선 우클릭 메뉴의 규칙(순수). **받은 말풍선에만** [이 메시지 신고하기]가 선다 — 내 말을 내가 신고할 일은 없다.
enum MessageBubbleReportRule {
    static func offersReport(for entry: MessageHistoryEntry) -> Bool {
        !entry.isMine && !entry.id.isEmpty && !entry.peerUserID.isEmpty
    }

    /// 그 말풍선을 신고할 대상(받은 말풍선이 아니면 nil).
    static func target(for entry: MessageHistoryEntry) -> BlockReportTarget? {
        guard offersReport(for: entry) else { return nil }
        return BlockReportTarget(
            peerID: entry.peerUserID,
            peerName: entry.peerName,
            messageID: entry.id,
            messageBody: entry.body
        )
    }
}

/// 오목 채팅의 ··· 가 서는가(순수). **사람과 두는 판**이고 상대 id 를 알 때만 — AI 연습 판에는 신고할 사람이 없다.
enum GomokuChatSafetyRule {
    @MainActor
    static func target(for store: GomokuStore) -> BlockReportTarget? {
        guard let match = store.match, !GomokuAIGame.isAIMatchID(match.id) else { return nil }
        let opponent = match.opponent
        guard !opponent.id.isEmpty else { return nil }
        return BlockReportTarget(
            peerID: opponent.id,
            peerName: opponent.displayName.isEmpty ? "상대" : opponent.displayName,
            matchID: match.id
        )
    }
}

@MainActor
extension WorkTimerStore {
    /// 설정 창·팝오버가 쓰는 플랫폼 갈래(길 안내 문구 — "설정 → 차단한 사람").
    nonisolated static let blockReportPlatform: BlockReportPlatform = .mac

    // MARK: 파생값(화면이 읽는 것)

    /// 콕 찌르기 목록(화면용) — 차단으로 걷어낸 사람을 뺀다. **목록 자체(`pokeDirectory`)는 서버가 답한 그대로** 둔다:
    /// 차단이 실패하면 숨김만 풀면 그 사람이 그대로 돌아온다(다시 묻지 않아도 된다).
    var visiblePokeDirectory: [PokeDirectoryEntry] {
        blockHiddenPeerIDs.isEmpty ? pokeDirectory : pokeDirectory.filter { !blockHiddenPeerIDs.contains($0.userID) }
    }

    /// 콕 찌르기 목록 위 "최근 받은 메시지" 줄(화면용) — 차단한 사람이 보낸 것이면 서지 않는다.
    /// 큐(`receivedMessages`)는 **건드리지 않는다**: 말풍선이 그 맨 앞을 보여 주는 중일 수 있고, 거기서 빼면 표시가 끝났다는
    /// 신호(`consumeCurrentMessage`)가 한 번도 안 뜬 다른 사람의 말을 밀어낸다. 걸러 내는 것은 읽는 자리뿐이다.
    var visibleLatestMessage: ReceivedMessage? {
        guard let message = currentMessage else { return nil }
        guard let sender = message.fromUserID, blockHiddenPeerIDs.contains(sender) else { return message }
        return nil
    }

    /// 그 자리의 결과 한 줄(없으면 nil).
    func blockReportNotice(on surface: BlockReportSurface) -> BlockReportNotice? {
        guard let notice = blockReportNotice, notice.surface == surface else { return nil }
        return notice
    }

    /// 그 자리의 시트(없으면 nil).
    ///
    /// 오목 판에 묶인 시트(`BlockReportTarget.matchID`)는 **그 판이 서 있는 동안만** 선다. 판이 바뀌는 길(다시 두기 · 로비 · 새 신청
    /// 수락)은 여럿이고 오목 창은 닫아도 뷰가 살아 있어, 정리 문(`dismissBlockReportSheet`)이 한 번 빠지면 앞 판의 덮개가 다음 판의
    /// 판을 가린다(v0.3.34 수리). 그래서 읽는 자리에서도 판 id 를 대조한다 — 떠난 판의 시트는 어느 화면에도 안 선다.
    func blockReportSheet(on surface: BlockReportSurface) -> BlockReportSheet? {
        guard let sheet = blockReportSheet, sheet.surface == surface else { return nil }
        if let matchID = sheet.target.matchID, gomoku.match?.id != matchID { return nil }
        return sheet
    }

    /// 지금 [신고 보내기]를 누를 수 있는가(버튼 잠금). 스토어의 `sendReportFromSheet` 가 같은 조건을 다시 본다.
    var canSubmitReportNow: Bool {
        guard blockReportSheet?.kind == .report else { return false }
        return BlockReportRules.canSubmitReport(reason: reportReason, detail: reportDetailDraft, isSending: isSendingReport)
    }

    // MARK: 시트 열고 닫기 — 메뉴·우클릭은 **여기까지만** 부른다

    /// ··· → [차단하기]. 시트를 연다(왕복 없음). 차단은 시트의 [차단하기]가 보낸다(`confirmBlockFromSheet`).
    func openBlockConfirm(_ target: BlockReportTarget, surface: BlockReportSurface) {
        guard canOpenBlockReportSheet(for: target) else { return }
        blockReportSheet = BlockReportSheet(kind: .blockConfirm, target: target, surface: surface)
    }

    /// ··· → [신고하기] · 받은 말풍선 우클릭 → [이 메시지 신고하기]. 시트를 **새로** 연다 — 사유·자세히·차단 스위치를 처음 값으로
    /// 되돌린다(앞사람에 대해 쓰던 글이 다른 사람 신고에 실리면 사고다 — 메시지 초안을 상대 바꿀 때 비우는 것과 같은 규약).
    func openReport(_ target: BlockReportTarget, surface: BlockReportSurface) {
        guard canOpenBlockReportSheet(for: target) else { return }
        reportReason = nil
        reportDetailDraft = ""
        reportAlsoBlock = true
        reportNotice = nil
        blockReportSheet = BlockReportSheet(kind: .report, target: target, surface: surface)
    }

    /// 시트를 닫는다(✕ · [취소] · Esc). **보내는 중에는 닫지 않는다** — 결과가 어디로도 안 가는 신고가 된다.
    func closeBlockReportSheet() {
        guard !isSendingReport, blockReportSheet != nil else { return }
        blockReportSheet = nil
        reportNotice = nil
    }

    /// 연 자리를 **떠날 때** 그 자리의 시트를 걷는다(v0.3.34 수리) — 팝오버 대화를 닫거나(레일 · [뒤로] · 다른 패널) 다른 사람의
    /// 대화로 갈 때(`WorkTimerStoreMessages`), 오목 창을 닫을 때(`CheckGomokuWindowController`)·판이 바뀔 때(`GomokuPanel`).
    ///
    /// 남겨 두면 시트가 **다음 화면을 덮는다**: 대화 패널은 시트를 대화보다 먼저 그려서, A 에 대해 연 "A 님을 차단할까요?"가
    /// B 와의 대화 자리에 섰다. 오목 창은 닫아도 `orderOut` 뿐이라 덮개가 다음 판을 가렸다.
    ///
    /// `closeBlockReportSheet`(✕ · [취소])와 달리 **보내는 중에도 걷는다** — 사용자는 이미 그 자리를 떠났다. 보내던 신고는 계속 가고,
    /// 결과(접수 · 실패)는 그 자리의 결과 한 줄로 선다(`sendReportFromSheet` — 시트 안 한 줄은 아무도 못 본다).
    func dismissBlockReportSheet(on surface: BlockReportSurface) {
        guard blockReportSheet?.surface == surface else { return }
        blockReportSheet = nil
        reportNotice = nil
    }

    /// 신고 사유를 고른다. 고르면 "사유를 골라 주세요"는 더 이상 참이 아니다.
    func selectReportReason(_ reason: ContentReportReason) {
        guard !isSendingReport else { return }
        reportReason = reason
        if reportNotice == BlockReportText.reportReasonRequired { reportNotice = nil }
    }

    private func canOpenBlockReportSheet(for target: BlockReportTarget) -> Bool {
        guard let me = session?.userID, !target.peerID.isEmpty, target.peerID != me else { return false }
        // 신고가 날아가는 중에 다른 시트로 갈아 끼우면 그 결과가 엉뚱한 화면에 떨어진다.
        return !isSendingReport
    }

    // MARK: 차단

    /// 차단 확인 시트의 [차단하기] — **차단을 부르는 유일한 문**(위 머리 주석 ①).
    /// 시트가 차단 확인이 아니면 아무 일도 안 한다(메뉴에서 곧장 여기로 오는 길을 타입이 아니라 값으로도 막는다).
    func confirmBlockFromSheet() {
        guard let sheet = blockReportSheet, sheet.kind == .blockConfirm else { return }
        blockReportSheet = nil
        blockPeer(sheet.target, surface: sheet.surface)
    }

    /// 한 사람을 차단한다. 낙관적으로 걷어내고 왕복을 띄운다 — 화면은 성공을 기다리지 않는다.
    private func blockPeer(_ target: BlockReportTarget, surface: BlockReportSurface) {
        let peerID = target.peerID
        guard let me = session?.userID, !peerID.isEmpty, peerID != me else { return }
        guard blockingPeerID == nil else { return }
        let generation = sessionGeneration
        blockReportNotice = nil
        blockingPeerID = peerID
        hideBlockedPeer(peerID, from: surface)
        Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.blockUser(accessToken: activeSession.accessToken, userID: peerID)
                }
                guard generation == sessionGeneration else { return }
                blockingPeerID = nil
                // 차단 목록은 다음에 설 때 서버에서 다시 받는다(여기서 지어내 넣지 않는다 — 별명·시각을 모른다).
                blocksLoaded = false
            } catch {
                guard generation == sessionGeneration else { return }
                blockingPeerID = nil
                // 되돌리기: 걷어낸 사람이 그대로 돌아온다(목록·점·오목 로비 — 전부 읽는 자리에서만 걸렀으므로).
                blockHiddenPeerIDs.remove(peerID)
                if let text = BlockReportRules.notice(for: BlockReportRules.classify(error), action: .block) {
                    blockReportNotice = BlockReportNotice(text: text, isError: true, surface: surface)
                }
            }
        }
    }

    /// 걷어내기 — 숨김에 넣고, 그 사람과의 열린 대화에서 나오고, 그 사람과의 판 채팅을 끈다.
    ///
    /// · 대화: 걷어낸 사람과의 대화 화면이 떠 있으면 나온다(폰: 대화에서 목록으로 빠져나온다). 팝오버에서 건 차단이면
    ///   **콕 찌르기 목록에 선다** — 맥에서 사람을 고르는 목록이 거기라 그 사람이 사라진 것이 눈에 보이고, 실패하면 이유 한 줄도
    ///   거기 선다(말풍선에서 들어와 [뒤로]가 홈이어도 목록으로 간다 — 결과를 볼 자리가 있어야 한다).
    /// · 판 채팅: 그 사람과 두는 판이 있으면 채팅을 끈다(`setChatMuted(true)` — 서버가 아는 판 상태). **판 자체는 건드리지 않는다** —
    ///   판돈이 걸려 있고, 기권은 사용자가 고를 일이다. 차단이 실패해도 끈 채팅은 켜 두지 않는다(보호 쪽으로 틀린다 · 폰과 같다).
    private func hideBlockedPeer(_ peerID: String, from surface: BlockReportSurface) {
        blockHiddenPeerIDs.insert(peerID)
        if isMessagePanelVisible, selectedMessagePeerID == peerID {
            closeMessagePanel()
            if surface == .message, !isPokePanelVisible { togglePokePanel() }
        }
        if let match = gomoku.match, match.opponent.id == peerID, !GomokuAIGame.isAIMatchID(match.id), !gomoku.isMuted {
            gomoku.setChatMuted(true)
        }
    }

    // MARK: 신고

    /// 신고 시트의 [신고 보내기]. **조합 확정은 뷰가 먼저 한다**(`CheckEditorSend.commitThenSend` — 이 함수를 그 안에서 부른다):
    /// 확정은 동기라 이 함수의 첫 줄이 읽는 `reportDetailDraft` 는 화면에 보이던 글 전체다. 값은 **부르는 순간** 붙잡는다 —
    /// 왕복 사이 초안이 바뀌어도 보낸 것은 누른 순간의 글이다.
    ///
    /// 성공하면 시트를 닫고 결과 한 줄을 세운다. "신고하면서 차단"이면 서버가 같은 트랜잭션에서 차단했으므로 화면도 곧바로 걷어낸다.
    /// 실패하면 시트를 **열어 둔 채** 이유 한 줄을 세운다(쓴 글이 사라지지 않게 — 제보 화면과 같은 규약).
    /// 반환 Task 는 테스트가 기다리는 손잡이다(앱은 버린다). 보내지 않았으면 nil.
    @discardableResult
    func sendReportFromSheet() -> Task<Bool, Never>? {
        guard session != nil, let sheet = blockReportSheet, sheet.kind == .report, !isSendingReport else { return nil }
        guard let reason = reportReason else {
            reportNotice = BlockReportText.reportReasonRequired
            return nil
        }
        guard ContentReportDetail.isWithinLimit(reportDetailDraft) else {
            reportNotice = BlockReportText.reportDetailOverflow(ContentReportDetail.maxLength)
            return nil
        }
        let target = sheet.target
        let detail = ContentReportDetail.payload(reportDetailDraft)
        let alsoBlock = reportAlsoBlock
        let generation = sessionGeneration
        isSendingReport = true
        reportNotice = nil
        blockReportNotice = nil
        return Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.reportContent(
                        accessToken: activeSession.accessToken,
                        targetUserID: target.peerID,
                        reason: reason,
                        detail: detail,
                        messageID: target.messageID,
                        alsoBlock: alsoBlock
                    )
                }
                guard generation == sessionGeneration else { return false }
                isSendingReport = false
                if blockReportSheet == sheet { blockReportSheet = nil }
                reportDetailDraft = ""
                reportReason = nil
                if alsoBlock {
                    // 서버가 이미 차단했다 — 화면도 같은 순간에 걷어낸다(되돌릴 실패가 없다).
                    hideBlockedPeer(target.peerID, from: sheet.surface)
                    blocksLoaded = false
                }
                blockReportNotice = BlockReportNotice(text: BlockReportText.reportSentNotice, isError: false, surface: sheet.surface)
                return true
            } catch {
                guard generation == sessionGeneration else { return false }
                isSendingReport = false
                if let text = BlockReportRules.notice(for: BlockReportRules.classify(error), action: .report) {
                    if blockReportSheet(on: sheet.surface) == sheet {
                        reportNotice = text
                    } else {
                        // 보내는 사이 사용자가 그 자리를 떠났다(`dismissBlockReportSheet` · 판이 바뀜). 시트 안 한 줄은 아무도 못 본다 —
                        // 그 자리의 결과 한 줄로 세운다. 안 그러면 "보내는 중…"을 보고 떠난 사람은 접수된 줄 안다.
                        if blockReportSheet == sheet { blockReportSheet = nil }
                        blockReportNotice = BlockReportNotice(text: text, isError: true, surface: sheet.surface)
                    }
                }
                return false
            }
        }
    }

    // MARK: 차단 목록(설정 → 차단한 사람)

    /// 차단 목록 조회(`list_blocks`). 설정의 [차단한 사람]이 설 때 부른다.
    /// 서버가 함수를 모르면 **빈 목록 + "아직 준비되지 않았어요"** 다(실패가 아니라 아직이다).
    func loadBlocks(force: Bool = false) {
        guard session != nil, !blocksLoading else { return }
        if !force, blocksLoaded { return }
        let generation = sessionGeneration
        blocksLoading = true
        blocksFailed = false
        Task { @MainActor in
            do {
                let rows = try await withSessionRetry { activeSession in
                    try await service.fetchBlocks(accessToken: activeSession.accessToken)
                }
                guard generation == sessionGeneration else { return }
                blocksLoading = false
                blockedPeople = rows
                blocksLoaded = true
                blocksFailed = false
                blocksServerNotReady = false
            } catch {
                guard generation == sessionGeneration else { return }
                blocksLoading = false
                switch BlockReportRules.classify(error) {
                case .cancelled:
                    return
                case .serverNotReady:
                    // 아직 없는 서버 — 빈 목록으로 조용히 접고 화면이 "아직"이라고 말한다.
                    blockedPeople = []
                    blocksLoaded = true
                    blocksServerNotReady = true
                case .network, .rejected:
                    blocksFailed = true
                }
            }
        }
    }

    /// 설정 → [차단한 사람]을 연다(스로틀 없음 — 사람이 직접 연 화면이다).
    func openBlockedPeopleSettings() {
        guard session != nil else { return }
        showsBlockedPeopleInSettings = true
        blockedListNotice = nil
        loadBlocks(force: true)
    }

    /// 설정 본문으로 돌아간다(설정 창이 닫힐 때도 부른다 — 다시 열면 설정 본문부터 보인다).
    func closeBlockedPeopleSettings() {
        if showsBlockedPeopleInSettings { showsBlockedPeopleInSettings = false }
        if blockedListNotice != nil { blockedListNotice = nil }
    }

    /// 차단 목록의 [차단 해제](행 안의 확인을 지난 뒤). 성공하면 그 줄을 빼고 숨김도 푼다.
    func unblock(_ userID: String) {
        guard session != nil, !userID.isEmpty, !unblockingUserIDs.contains(userID) else { return }
        let generation = sessionGeneration
        blockedListNotice = nil
        unblockingUserIDs.insert(userID)
        Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.unblockUser(accessToken: activeSession.accessToken, userID: userID)
                }
                guard generation == sessionGeneration else { return }
                unblockingUserIDs.remove(userID)
                blockedPeople.removeAll { $0.userID == userID }
                blockHiddenPeerIDs.remove(userID)
                // 그 사람의 목록·대화를 다시 받는다(차단 동안 서버가 빼고 있었다). 오목 로비는 창이 설 때 스스로 다시 묻는다.
                loadPokeDirectory()
                requestMessageActivityRefresh(includeHistory: true)
            } catch {
                guard generation == sessionGeneration else { return }
                unblockingUserIDs.remove(userID)
                if let text = BlockReportRules.notice(for: BlockReportRules.classify(error), action: .unblock) {
                    blockedListNotice = text
                }
            }
        }
    }

    // MARK: 정리

    /// 그 자리의 결과 한 줄을 내린다(다른 자리의 줄은 건드리지 않는다).
    func clearBlockReportNotice(on surface: BlockReportSurface) {
        if blockReportNotice?.surface == surface { blockReportNotice = nil }
    }

    /// 로그아웃·계정 전환(`clearPersistedSession`). 전부 계정에 묶인 상태다.
    func clearBlockReportState() {
        blockReportSheet = nil
        reportReason = nil
        reportDetailDraft = ""
        reportAlsoBlock = true
        isSendingReport = false
        reportNotice = nil
        blockHiddenPeerIDs = []
        blockingPeerID = nil
        blockReportNotice = nil
        blockedPeople = []
        blocksLoaded = false
        blocksLoading = false
        blocksFailed = false
        blocksServerNotReady = false
        unblockingUserIDs = []
        blockedListNotice = nil
        showsBlockedPeopleInSettings = false
    }
}
