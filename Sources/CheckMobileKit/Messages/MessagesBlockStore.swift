import CheckCore
import Foundation

/// 차단·신고 동작(SPEC-block-report 작업 P). 상태는 `MessagesStore` 본체에, 문구·규칙은 코어 `BlockReportRules`(맥과 한 벌)에 있다.
///
/// ── 이 확장이 지키는 것 ──
/// ① **차단 직후 화면은 서버를 기다리지 않는다.** 확인 시트를 지나면 그 상대를 곧바로 숨기고(`hiddenBlockedPeerIDs`)
///    대화·목록·배지·사람 찾기에서 사라진다. 실패하면 숨김을 되돌리고 목록 위에 이유 한 줄을 세운다 — **대화는 그대로 돌아온다.**
/// ② **확인 없이는 차단하지 않는다.** `blockPeer` 를 부르는 곳은 확인 시트 하나다(소스 계약 테스트가 센다).
/// ③ **서버가 아직 없는 창**(앱이 db push 보다 먼저 나갔다)에서는 "고장"이 아니라 "아직"이라고 말한다
///    (`BlockReportText.serverNotReady` — 계정 삭제의 `serverNotReady` 와 같은 규약).
/// ④ 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정의 숨김·목록·문구를 건드리지 않는다.
///
/// ★ 신고 본문은 사람이 쓴 문장이다 — 이 파일에도 `print`/`Logger` 를 붙이지 마라.
extension MessagesStore {
    // MARK: - 차단

    /// 한 사람을 차단한다(확인 시트가 부르는 유일한 문). 낙관적으로 숨기고 왕복을 띄운다.
    ///
    /// 화면은 이 함수가 돌아오는 즉시 목록으로 빠져나온다 — 성공을 기다리지 않는다. 실패는 목록 위 한 줄로 돌아온다.
    package func blockPeer(_ peerID: String) {
        guard isSignedIn, !peerID.isEmpty, peerID != context.session.userID else { return }
        guard blockingPeerID == nil else { return }
        let generation = context.generation
        blockNotice = nil
        blockNoticeIsError = false
        blockingPeerID = peerID
        // 숨기는 즉시 묶음·배지·점·사람 찾기에서 사라진다(`visibleHistory` 한 곳이 거른다). 읽음 표시도 더 올라가지 않는다.
        hiddenBlockedPeerIDs.insert(peerID)
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.context.withMobileSessionRetry { session in
                    try await service.blockUser(accessToken: session.accessToken, userID: peerID)
                }
                guard generation == self.context.generation else { return }
                self.blockingPeerID = nil
                // 차단 목록 화면은 다음에 설 때 서버에서 다시 받는다(여기서 지어내 넣지 않는다 — 별명·시각을 모른다).
                self.blocksLoaded = false
            } catch {
                guard generation == self.context.generation else { return }
                self.blockingPeerID = nil
                let failure = BlockReportRules.classify(error)
                // 되돌리기: 숨긴 대화가 그대로 돌아온다.
                self.hiddenBlockedPeerIDs.remove(peerID)
                if let notice = BlockReportRules.notice(for: failure, action: .block) {
                    self.blockNotice = notice
                    self.blockNoticeIsError = true
                }
            }
        }
    }

    /// 차단 목록의 [차단 해제]. 성공하면 목록에서 그 줄을 빼고 숨김도 푼다.
    package func unblock(_ userID: String) {
        guard isSignedIn, !userID.isEmpty, !unblockingUserIDs.contains(userID) else { return }
        let generation = context.generation
        blockedListNotice = nil
        unblockingUserIDs.insert(userID)
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.context.withMobileSessionRetry { session in
                    try await service.unblockUser(accessToken: session.accessToken, userID: userID)
                }
                guard generation == self.context.generation else { return }
                self.unblockingUserIDs.remove(userID)
                self.blockedPeople.removeAll { $0.userID == userID }
                // 숨김을 푼다 — 서버가 다시 내려 주는 이력에 그 사람의 대화가 있으면 목록에 돌아온다.
                self.hiddenBlockedPeerIDs.remove(userID)
                // 그 사람의 대화·사람 목록을 다시 받는다(차단 동안 서버가 빼고 있었다).
                self.requestActivityRefresh(includeHistory: true)
                self.loadDirectory(force: true)
            } catch {
                guard generation == self.context.generation else { return }
                self.unblockingUserIDs.remove(userID)
                let failure = BlockReportRules.classify(error)
                if let notice = BlockReportRules.notice(for: failure, action: .unblock) {
                    self.blockedListNotice = notice
                }
            }
        }
    }

    /// 차단 목록 조회(`list_blocks`). 화면이 설 때 · 당겨서 새로고침이 부른다.
    /// 서버가 함수를 모르면 **빈 목록 + "아직 준비되지 않았어요"** 다(실패가 아니라 아직이다).
    package func loadBlocks(force: Bool = false) {
        guard isSignedIn, !blocksLoading else { return }
        if !force, blocksLoaded { return }
        let generation = context.generation
        blocksLoading = true
        blocksFailed = false
        let service = context.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rows = try await self.context.withMobileSessionRetry { session in
                    try await service.fetchBlocks(accessToken: session.accessToken)
                }
                guard generation == self.context.generation else { return }
                self.blocksLoading = false
                self.blockedPeople = rows
                self.blocksLoaded = true
                self.blocksFailed = false
                self.blocksServerNotReady = false
            } catch {
                guard generation == self.context.generation else { return }
                self.blocksLoading = false
                switch BlockReportRules.classify(error) {
                case .cancelled:
                    return
                case .serverNotReady:
                    // 아직 없는 서버 — 빈 목록으로 조용히 접고 화면이 "아직"이라고 말한다.
                    self.blockedPeople = []
                    self.blocksLoaded = true
                    self.blocksServerNotReady = true
                case .network, .rejected:
                    self.blocksFailed = true
                }
            }
        }
    }

    /// 차단 목록 화면이 섰다(스로틀 없음 — 사람이 직접 연 화면이다).
    package func blockedListDidAppear() {
        blockedListNotice = nil
        loadBlocks(force: true)
    }

    // MARK: - 신고

    /// 신고 한 건(+ `alsoBlock` 이면 서버가 같은 트랜잭션에서 차단까지). 보냈으면 true — 화면은 그때만 시트를 닫는다.
    ///
    /// 실패하면 시트를 **열어 둔 채** 이유 한 줄을 세운다(사용자가 쓴 글이 사라지지 않게 — 제보 화면과 같은 규약).
    @discardableResult
    package func submitReport(
        peerID: String,
        reason: ContentReportReason?,
        detail: String,
        messageID: String?,
        alsoBlock: Bool
    ) async -> Bool {
        guard isSignedIn, !peerID.isEmpty, !isSendingReport else { return false }
        guard let reason else {
            reportNotice = BlockReportText.reportReasonRequired
            return false
        }
        guard ContentReportDetail.isWithinLimit(detail) else {
            reportNotice = BlockReportText.reportDetailOverflow(ContentReportDetail.maxLength)
            return false
        }
        let generation = context.generation
        isSendingReport = true
        reportNotice = nil
        let service = context.service
        do {
            try await context.withMobileSessionRetry { session in
                try await service.reportContent(
                    accessToken: session.accessToken,
                    targetUserID: peerID,
                    reason: reason,
                    detail: ContentReportDetail.payload(detail),
                    messageID: messageID,
                    alsoBlock: alsoBlock
                )
            }
            guard generation == context.generation else { return false }
            isSendingReport = false
            if alsoBlock {
                // 서버가 이미 차단했다 — 화면도 같은 순간에 걷어낸다(되돌릴 실패가 없다).
                hiddenBlockedPeerIDs.insert(peerID)
                blocksLoaded = false
            }
            blockNotice = BlockReportText.reportSentNotice
            blockNoticeIsError = false
            return true
        } catch {
            guard generation == context.generation else { return false }
            isSendingReport = false
            let failure = BlockReportRules.classify(error)
            if let notice = BlockReportRules.notice(for: failure, action: .report) {
                reportNotice = notice
            }
            return false
        }
    }

    /// 신고 시트가 닫혔다 — 실패 문구를 비운다(다음에 열 때 앞 실패가 남지 않게).
    package func reportSheetDidDisappear() {
        reportNotice = nil
    }
}
