import CheckCore
import CheckMobileShared
import Foundation

/// 제보: 쓰기(`submit_feedback` — 앱 버전 "iOS 0.1.0 (1)" · OS 버전, **진단 줄 없음**) · 내 제보 목록과 답장(`feedback_list`) ·
/// 답장 배지(`feedback_reply_latest` vs 이 계정이 본 시각).
///
/// 문구는 코어 `FeedbackText` 를 그대로 쓴다(맥과 같은 문장). 초안은 전송 **성공**에서만 비운다(스키마 부재 문구의 "쓰신 글은 그대로 둘게요" 약속).
/// ★ 제보 본문은 사용자가 쓴 글이다 — 로그·print 금지.
extension MeStore {
    package var canSendFeedback: Bool {
        !isSendingFeedback && context.session.isSignedIn && FeedbackComposer.isSendable(feedbackDraft)
    }

    package var feedbackAutoAttachNotice: String {
        MeText.feedbackAutoAttach(appVersion: context.appInfo.feedbackAppVersion, osVersion: context.appInfo.osVersion)
    }

    package func sendFeedback() async {
        guard context.session.isSignedIn, !isSendingFeedback else { return }
        let body = FeedbackComposer.normalized(feedbackDraft)
        guard FeedbackComposer.isSendable(body) else { return }
        let kind = feedbackKind
        let appVersion = context.appInfo.feedbackAppVersion
        let osVersion = context.appInfo.osVersion
        let generation = context.generation
        isSendingFeedback = true
        feedbackNotice = nil
        defer { if generation == context.generation { isSendingFeedback = false } }
        let service = context.service
        do {
            _ = try await context.withMobileSessionRetry { session in
                try await service.submitFeedback(accessToken: session.accessToken, kind: kind, body: body, appVersion: appVersion, osVersion: osVersion)
            }
            guard generation == context.generation else { return }
            feedbackDraft = ""
            feedbackNotice = FeedbackText.sendSuccess
            await loadFeedback()
        } catch {
            guard generation == context.generation else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            feedbackNotice = MeText.feedbackFailure(error, fallback: FeedbackText.sendFailed, schemaMissing: FeedbackText.sendSchemaMissing)
        }
    }

    /// 내 제보 목록. 관리자 계정은 서버가 전부를 주므로 **내 것만** 거른다(이 화면은 "내가 보낸 제보"다 — 받은 제보함은 맥에만 있다).
    package func loadFeedback() async {
        guard context.session.isSignedIn, let me = context.session.userID else { return }
        let serial = nextSerial("feedback")
        let generation = context.generation
        feedbackState.isLoading = true
        feedbackState.hasFailed = false
        defer { if isCurrent("feedback", serial) { feedbackState.isLoading = false } }
        let service = context.service
        let limit = Self.feedbackListLimit
        do {
            let reports = try await context.withMobileSessionRetry { session in
                try await service.fetchFeedbackList(accessToken: session.accessToken, status: nil, limit: limit)
            }
            guard generation == context.generation, isCurrent("feedback", serial) else { return }
            let mine = MeText.sortedFeedback(reports.filter { $0.userID == me })
            if feedbackList != mine { feedbackList = mine }
            feedbackState.hasLoaded = true
            feedbackState.loadedAt = context.clock.now()
            if let latest = mine.compactMap(\.adminNoteAt).max(), latest > (feedbackReplyLatestAt ?? .distantPast) {
                feedbackReplyLatestAt = latest
            }
            if isFeedbackVisible { markFeedbackRepliesSeen() }
        } catch {
            guard generation == context.generation, isCurrent("feedback", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 표가 아직 없다 — 실패가 아니라 "아직 없음"(맥 performLoadFeedback 관례).
                feedbackState.hasLoaded = true
                feedbackState.loadedAt = context.clock.now()
            } else {
                feedbackState.hasFailed = true
            }
        }
    }

    /// 내 제보에 달린 가장 최근 답장 시각. 실패는 조용히(서 있던 배지는 내리지 않는다 — 못 물어봤다는 것이 "답장 없음"은 아니다).
    package func loadFeedbackReplyLatest() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("replyLatest")
        let generation = context.generation
        let service = context.service
        guard case .success(let latest) = await attempt({ session in
            try await service.fetchFeedbackReplyLatest(accessToken: session.accessToken)
        }) else { return }
        guard generation == context.generation, isCurrent("replyLatest", serial) else { return }
        feedbackReplyLatestAt = latest
        loadFeedbackReplySeenStamp()
        if isFeedbackVisible { markFeedbackRepliesSeen() }
    }

    /// 안 본 답장이 있는가: 서버의 마지막 답장 시각 > 이 계정이 본 시각.
    package var hasUnseenFeedbackReply: Bool {
        guard let latest = feedbackReplyLatestAt else { return false }
        guard let seen = feedbackReplySeenAt else { return true }
        return latest > seen
    }

    /// 이 답장이 새 것인가(행의 "새 답장" 점).
    package func isUnseenReply(_ report: FeedbackReport) -> Bool {
        guard report.reply != nil, let at = report.adminNoteAt else { return false }
        // 이 폰에서 한 번도 본 적 없으면(새 설치) 가장 최근 답장만 새 것으로 친다 — 몇 주 전 답장까지 "새 답장"이면 거짓말이다.
        guard let seen = feedbackReplySeenAt else { return at >= (feedbackReplyLatestAt ?? at) }
        return at > seen
    }

    package func feedbackDidAppear() {
        isFeedbackVisible = true
        guard context.session.isSignedIn else { return }
        launch { [weak self] in await self?.loadFeedback() }
        launch { [weak self] in await self?.loadFeedbackReplyLatest() }
    }

    package func feedbackDidDisappear() {
        isFeedbackVisible = false
        focusedReportID = nil
        if feedbackNotice == FeedbackText.sendSuccess { feedbackNotice = nil }
        // 떠나는 순간 본 것으로 적는다(행의 "새 답장" 점은 화면에 머무는 동안 남아 있어야 읽고 나서 사라진다).
        markFeedbackRepliesSeen(updatesDisplayedStamp: true)
    }

    /// 본 것으로 적는다. **적는 값은 서버가 준 마지막 답장 시각**이다(맥과 같다 — 기기 시계를 적으면 시계가 앞선 만큼 새 답장을 못 본다).
    /// 화면에 머무는 동안은 저장만 하고 행의 점은 그대로 둔다(`updatesDisplayedStamp` false).
    func markFeedbackRepliesSeen(updatesDisplayedStamp: Bool = false) {
        guard let latest = feedbackReplyLatestAt, let key = feedbackReplySeenKey else { return }
        let stored = context.storage.defaults.object(forKey: key) as? Double
        if stored.map({ latest.timeIntervalSince1970 > $0 }) ?? true {
            context.storage.defaults.set(latest.timeIntervalSince1970, forKey: key)
        }
        if updatesDisplayedStamp { feedbackReplySeenAt = latest }
    }

    func loadFeedbackReplySeenStamp() {
        guard let key = feedbackReplySeenKey else { return }
        guard !isFeedbackVisible else { return }
        let stored = context.storage.defaults.object(forKey: key) as? Double
        feedbackReplySeenAt = stored.map { Date(timeIntervalSince1970: $0) }
    }

    /// 계정별 키(같은 폰에서 계정을 바꿔도 앞 계정의 '봤음'을 물려받지 않게 — 맥 retroBannerShownWeekKeyForCurrentUser 와 같은 이유).
    var feedbackReplySeenKey: String? {
        context.session.userID.map { "aing.me.feedbackReplySeenAt.\($0)" }
    }

    /// 목록이 가리킬 제보(딥링크) — 목록에 없으면 nil.
    package var focusedReport: FeedbackReport? {
        focusedReportID.flatMap { id in feedbackList.first { $0.id == id } }
    }
}
