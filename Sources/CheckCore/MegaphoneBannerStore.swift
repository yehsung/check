import Foundation
import Observation

// MARK: - 확성기 배너 스토어(맥·폰 한 벌 — 계약 docs/plan/megaphone-banner-contract.md C2 · C3)
//
// `MegaphoneStore` 와 같은 결: `GomokuStoreHost`(맥 WorkTimerStore · 폰 MobileGomokuHost)를 약참조로 빌려 RPC 를 부른다.
// 화면(맥 배너 패널 · 폰 위 배너)은 `current` 하나만 그린다. 이 파일이 지키는 것:
//
// ① **메시지함 필터의 근거는 `knownMessageIDs` 하나다.** `megaphone_inbox` 가 성공했을 때만 채운다. 숨김 술어 `hides(messageID:)` 는
//    `capability == .available` 일 때만 참이다 — 서버에 새 함수가 없으면(`.unavailable`) 지금처럼 메시지로 보인다(잃는 것이 없다).
// ② **본문 접두(`📢 `)는 표식이 아니다.** 접두만 있고 ID 를 모르는 줄은 `needsVerification` 이 "판정 보류"를 말하고, 부르는 쪽이
//    `refresh(verifying:)` 를 한 번 기다린 뒤 다시 거른다. 그 refresh 뒤에도 모르면(위조 DM · 연결 실패) 메시지로 보인다.
// ③ **안 읽음 요약과 필터는 함께 움직인다.** 필터가 켜져 있으면 확성기 줄을 안 세는 `message_unread_summary_v2` 를, 아니면 옛 함수를
//    쓴다. v2 가 없으면(PGRST202 · 404) 옛 함수로 내리고 **필터도 끈다** — 줄만 숨기고 옛 요약이 그 줄을 세면 배지가 영영 안 꺼진다.
// ④ **한 번에 하나 · 5초 · 쉬고 0.4초.** 타이머는 주입(`clock` · `schedule`)이라 시험이 5초를 기다리지 않는다. 지난 타이머는
//    `timerToken` 으로 버린다(취소 대신 세대).
// ⑤ **본 것 기록**: 계정별 키로 최근 100개 `megaphoneID` 를 기본값 저장소에 — 재실행해도 같은 확성기를 두 번 안 띄운다.
//    (기기 사이에는 나누지 않는다 — 맥에서 본 것이 폰에 또 뜨는 것은 허용.) `reset()` 은 메모리 캐시만 비운다(기록은 계정 키에 남는다).

/// 배너 타이머를 거는 곳. `after` 초 뒤 `fire` 를 메인 액터에서 부른다. 취소는 없다 — 스토어가 세대로 지난 것을 버린다.
package typealias MegaphoneBannerSchedule = @MainActor (_ after: TimeInterval, _ fire: @escaping @MainActor @Sendable () -> Void) -> Void

@MainActor
@Observable
package final class MegaphoneBannerStore {
    /// 서버가 배너 RPC 를 아는가.
    package enum Capability: Equatable, Sendable {
        /// 아직 안 물어봤다(로그인 직후) — 필터 꺼짐 · 접두 줄은 판정 보류.
        case unknown
        /// `megaphone_inbox` 가 성공했다 — 필터 켜짐 · 안 읽음 요약은 v2.
        case available
        /// inbox 또는 v2 가 없다(옛 서버) — 필터 꺼짐 · 지금처럼 메시지로.
        case unavailable
    }

    /// 옛 안 읽음 요약(확성기 줄도 센다 — V0333 관문 함수, 옛 앱이 쓴다).
    package nonisolated static let unreadSummaryV1 = "message_unread_summary"
    /// 새 안 읽음 요약(확성기 줄을 안 센다).
    package nonisolated static let unreadSummaryV2 = "message_unread_summary_v2"

    // MARK: 주입

    /// 네트워크·세션을 빌리는 곳. 약참조 — 소유자가 이 스토어를 쥔다.
    @ObservationIgnored package private(set) weak var host: (any GomokuStoreHost)?
    /// 본 것 기록을 두는 곳(시험은 격리 스위트).
    @ObservationIgnored private let defaults: UserDefaults
    /// 시각(신선도 · 남은 표시 시간).
    @ObservationIgnored package var clock: () -> Date
    /// 타이머(5초 · 0.4초 · 멈춤 뒤 다시 세기).
    @ObservationIgnored package var schedule: MegaphoneBannerSchedule
    /// 지금 배너를 미뤄야 하는가(맥: 실시간 대결·미니게임 판 · 폰: 시트·대결 화면·미니게임 판). 바뀌면 `deferralChanged()` 를 부른다.
    @ObservationIgnored package var isBannerDeferred: () -> Bool = { false }
    /// 필터가 켜지거나 꺼질 때(`capability` 가 바뀔 때) 부른다 — 소유자가 안 읽음 요약 함수 짝(v1/v2)을 다시 맞춘다.
    /// refresh 를 **어느 길로** 불렀든(첫 판정 · 실시간 · 푸시 · 판정 보류) 한 곳에서 잡는다. 없으면 첫 판정이 네트워크로 실패한 뒤
    /// 실시간·푸시의 refresh 가 필터를 켜도 옛 요약이 숨긴 확성기 줄을 세어 배지가 남는다(2026-10-30 안드로이드 이식 검증에서 발견).
    @ObservationIgnored package var onCapabilityChange: (@MainActor () -> Void)?

    // MARK: 상태(화면이 읽는다)

    package private(set) var capability: Capability = .unknown {
        didSet { if capability != oldValue { onCapabilityChange?() } }
    }
    /// 메시지함에서 뺄 줄의 id — `megaphone_inbox` 가 돌려준 것만(한 세션 동안 늘기만 한다).
    package private(set) var knownMessageIDs: Set<String> = []
    /// 지금 떠 있는 배너. nil = 없음.
    package private(set) var current: MegaphoneBanner?
    /// 기다리는 배너(앞에서부터 뜬다).
    package private(set) var queue: [MegaphoneBanner] = []
    /// 호버·누르고 있기로 타이머가 멈춰 있는가.
    package private(set) var isTimerPaused = false
    /// v2 안 읽음 요약이 없는 서버였다(이 세션 동안 필터를 끈 채 둔다 — 머리말 ③).
    package private(set) var unreadSummaryV2Missing = false
    /// 마지막 refresh 가 연결 문제로 실패했다(함수 없음은 여기가 아니라 `capability`).
    package private(set) var lastRefreshFailed = false
    /// refresh 한 번을 지났는데도 inbox 에 없던 접두 줄(위조 DM · 연결 실패) — 더는 판정을 미루지 않는다.
    package private(set) var checkedMessageIDs: Set<String> = []

    // MARK: 내부

    @ObservationIgnored private var fromPushIDs: Set<String> = []
    @ObservationIgnored private var currentFromPush = false
    @ObservationIgnored private var verifyQueue: Set<String> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var timerToken = 0
    @ObservationIgnored private var currentDeadline: Date?
    @ObservationIgnored private var pausedRemaining: TimeInterval = 0
    @ObservationIgnored private var inGap = false
    @ObservationIgnored private var resetGeneration = 0
    @ObservationIgnored private var seenCache: (userID: String, ids: [String])?
    /// 세션이 없을 때(이론상) 쓰는 기록 — 저장하지 않는다.
    @ObservationIgnored private var memorySeen: [String] = []

    /// 실제 시계로 재우는 기본 타이머.
    package static let sleepSchedule: MegaphoneBannerSchedule = { after, fire in
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, after) * 1_000_000_000))
            fire()
        }
    }

    package init(host: (any GomokuStoreHost)? = nil, defaults: UserDefaults = .standard,
                 clock: @escaping () -> Date = { Date() }, schedule: MegaphoneBannerSchedule? = nil) {
        self.host = host
        self.defaults = defaults
        self.clock = clock
        self.schedule = schedule ?? Self.sleepSchedule
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다(맥 WorkTimerStore — `MegaphoneStore.attach` 와 같은 이유).
    package func attach(host: any GomokuStoreHost) {
        self.host = host
    }

    // MARK: 메시지함 필터(C3 — 한 술어, 모든 자리)

    /// 이 줄을 메시지함·배지·말풍선에서 뺄 것인가. **필터가 켜져 있고(.available) inbox 가 그 id 를 말했을 때만** 참.
    package func hides(messageID: String) -> Bool {
        capability == .available && knownMessageIDs.contains(messageID)
    }

    /// 이 줄의 판정을 미룰 것인가 — 본문이 `📢` 로 시작하는데 id 를 아직 모르고, 필터가 꺼진 서버가 아니며, refresh 를 한 번 지나지 않았다.
    /// 참이면 부르는 쪽은 그 줄을 잠시 붙들고 `refresh(verifying: [id])` 를 기다린 뒤 다시 거른다(접두만 보고 숨기지 않는다).
    package func needsVerification(messageID: String, body: String) -> Bool {
        guard capability != .unavailable, MegaphoneBanner.hasMegaphonePrefix(body) else { return false }
        return !knownMessageIDs.contains(messageID) && !checkedMessageIDs.contains(messageID)
    }

    /// 지금 쓸 안 읽음 요약 함수 이름. 필터가 켜져 있으면 v2, 아니면 옛 함수(머리말 ③).
    package var unreadSummaryFunction: String {
        capability == .available && !unreadSummaryV2Missing ? Self.unreadSummaryV2 : Self.unreadSummaryV1
    }

    /// 요약 호출이 실패했을 때 알려 준다. v2 가 없는 서버면 필터를 끄고 **true**(옛 함수로 다시 부를 것) — 그 밖은 false.
    @discardableResult
    package func noteUnreadSummaryFailure(function: String, error: Error) -> Bool {
        guard function == Self.unreadSummaryV2, Self.isMissingFunction(error) else { return false }
        unreadSummaryV2Missing = true
        if capability != .unavailable { capability = .unavailable }
        return true
    }

    /// 안 읽음 요약을 받는다 — `unreadSummaryFunction` 으로 부르고, v2 가 없으면 필터를 끈 뒤 옛 함수로 한 번 더 부른다.
    /// 맥 `fetchMessageUnreadSummary` · 폰 `performLoadSummary` 가 서비스 대신 이것을 부르면 ③이 저절로 지켜진다.
    package func fetchUnreadSummary() async throws -> MessageUnreadSummaryResponse {
        guard let host else { throw CancellationError() }
        let service = host.service
        let generation = resetGeneration
        let function = unreadSummaryFunction
        do {
            return try await host.withSessionRetry { session in
                try await service.fetchMessageUnreadSummary(accessToken: session.accessToken, function: function)
            }
        } catch {
            guard generation == resetGeneration, noteUnreadSummaryFailure(function: function, error: error) else { throw error }
            let fallback = Self.unreadSummaryV1
            return try await host.withSessionRetry { session in
                try await service.fetchMessageUnreadSummary(accessToken: session.accessToken, function: fallback)
            }
        }
    }

    // MARK: 받아 오기

    /// `megaphone_inbox` 를 불러 `knownMessageIDs` 를 늘리고, 새로 본 신선한 항목을 줄 세운다.
    /// 겹친 호출은 하나로 모이되, 진행 중에 들어온 요청은 **한 번 더** 돈다(그 사이 도착한 확성기를 놓치지 않게).
    /// `verifying` 의 id 는 이 refresh 가 끝난 뒤 판정이 확정된다: inbox 에 있으면 숨김, 없으면(연결 실패 포함) 메시지.
    package func refresh(verifying messageIDs: Set<String> = []) async {
        verifyQueue.formUnion(messageIDs)
        if let running = refreshTask {
            rerunRequested = true
            await running.value
            return
        }
        let generation = resetGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.rerunRequested = false
                let batch = self.verifyQueue
                self.verifyQueue = []
                await self.performRefresh()
                guard generation == self.resetGeneration else { return }
                let unresolved = batch.subtracting(self.knownMessageIDs)
                if !unresolved.isSubset(of: self.checkedMessageIDs) { self.checkedMessageIDs.formUnion(unresolved) }
            } while self.rerunRequested
            self.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard let host, host.session != nil else { return }
        let sessionGeneration = host.sessionGeneration
        let generation = resetGeneration
        let service = host.service
        do {
            let banners = try await host.withSessionRetry { session in
                try await service.fetchMegaphoneInbox(accessToken: session.accessToken)
            }
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return }
            if lastRefreshFailed { lastRefreshFailed = false }
            applyInbox(banners)
        } catch {
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return }
            if case .cancelled = host.classifyAuthError(error) { return }
            if Self.isMissingFunction(error) {
                // 서버가 아직 안 올라간 창 — 필터를 끄고 지금처럼 메시지로 보이게 한다.
                if capability != .unavailable { capability = .unavailable }
                if !knownMessageIDs.isEmpty { knownMessageIDs = [] }
                return
            }
            lastRefreshFailed = true
        }
    }

    /// inbox 한 벌을 반영한다(네트워크 없음).
    private func applyInbox(_ banners: [MegaphoneBanner]) {
        let ids = Set(banners.compactMap(\.messageID))
        if !ids.isSubset(of: knownMessageIDs) { knownMessageIDs.formUnion(ids) }
        let next: Capability = unreadSummaryV2Missing ? .unavailable : .available
        if capability != next { capability = next }
        let now = clock()
        for banner in banners.sorted(by: { $0.createdAt < $1.createdAt }) {
            offer(banner, fromPush: false, atFront: false, now: now)
        }
        pump()
    }

    // MARK: 띄우기

    /// 푸시로 안 확성기를 띄운다(앱이 앞에 있을 때 받은 푸시 · 푸시를 눌러 들어옴). **24시간 안이면 신선도를 무시**하고 줄 맨 앞에 선다.
    /// 이미 본 확성기는 다시 안 띄운다. 띄운 뒤 `refresh()` 로 id·아바타를 맞춘다(필터도 그때 켜진다).
    package func presentFromPush(megaphoneID: String, senderName: String?, body: String, senderID: String? = nil,
                                 messageID: String? = nil, createdAt: Date? = nil) {
        let now = clock()
        guard !megaphoneID.isEmpty, let text = MegaphoneBanner.displayBody(body) else { return }
        let created = createdAt ?? now
        guard MegaphoneBannerRules.isPresentable(createdAt: created, now: now, fromPush: true) else { return }
        let name = (senderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let banner = MegaphoneBanner(
            messageID: messageID, megaphoneID: megaphoneID, senderID: senderID,
            senderName: name.isEmpty ? MegaphoneBanner.fallbackSenderName : name,
            senderAvatarURL: nil, body: text, createdAt: created
        )
        offer(banner, fromPush: true, atFront: true, now: now)
        pump()
        if host?.session != nil {
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    /// 보낸 직후 내 화면에 "이렇게 떴어요" 배너를 한 번 띄운다(서버 fan-out 에 나는 없으니 중복이 아니다). 줄 맨 앞에 선다.
    /// `megaphoneID` 를 주면(전송 응답의 id) 본 것으로 기록한다.
    package func presentOwn(body: String, senderName: String, senderAvatarURL: URL? = nil, megaphoneID: String? = nil) {
        guard let text = MegaphoneBanner.displayBody(body) else { return }
        let now = clock()
        let id = megaphoneID.flatMap { $0.isEmpty ? nil : $0 } ?? Self.localIDPrefix + UUID().uuidString.lowercased()
        let banner = MegaphoneBanner(
            messageID: nil, megaphoneID: id, senderID: host?.session?.userID,
            senderName: senderName.isEmpty ? MegaphoneBanner.fallbackSenderName : senderName,
            senderAvatarURL: senderAvatarURL, body: text, createdAt: now, isOwn: true
        )
        offer(banner, fromPush: false, atFront: true, now: now)
        pump()
    }

    /// 지금 배너를 닫는다([닫기] · 위로 쓸기 · 5초). 다음 장은 0.4초 뒤.
    package func dismissCurrent() {
        guard current != nil else { return }
        current = nil
        if isTimerPaused { isTimerPaused = false }
        currentFromPush = false
        currentDeadline = nil
        timerToken += 1
        inGap = true
        let token = timerToken
        schedule(MegaphoneBannerRules.gap) { [weak self] in
            guard let self, self.timerToken == token else { return }
            self.inGap = false
            self.pump()
        }
    }

    /// 타이머를 멈춘다(맥: 마우스를 올림 · 폰: 누르고 있음).
    package func pauseTimer() {
        guard current != nil, !isTimerPaused else { return }
        isTimerPaused = true
        pausedRemaining = max(0, (currentDeadline ?? clock()).timeIntervalSince(clock()))
        timerToken += 1
    }

    /// 다시 센다 — 남은 시간과 3초 중 긴 쪽.
    package func resumeTimer() {
        guard current != nil, isTimerPaused else { return }
        isTimerPaused = false
        startTimer(after: max(pausedRemaining, MegaphoneBannerRules.resumeMinimum))
    }

    /// `isBannerDeferred` 가 바뀌었다. 미루기 시작이면 떠 있던 배너를 줄 맨 앞으로 되돌리고, 풀렸으면 **신선한 것만** 띄운다.
    package func deferralChanged() {
        if isBannerDeferred() {
            guard let showing = current else { return }
            timerToken += 1
            current = nil
            if isTimerPaused { isTimerPaused = false }
            currentDeadline = nil
            queue.insert(showing, at: 0)
            if currentFromPush { fromPushIDs.insert(showing.megaphoneID) }
            currentFromPush = false
        } else {
            pump()
        }
    }

    /// 로그아웃·계정 전환. 줄·id·필터·기록 캐시를 비우고, 나가 있던 응답과 타이머는 세대로 버린다.
    /// 본 것 기록 자체는 계정 키에 남는다(다음 계정은 자기 키를 읽는다).
    package func reset() {
        resetGeneration += 1
        timerToken += 1
        capability = .unknown
        knownMessageIDs = []
        checkedMessageIDs = []
        current = nil
        queue = []
        isTimerPaused = false
        unreadSummaryV2Missing = false
        lastRefreshFailed = false
        fromPushIDs = []
        currentFromPush = false
        verifyQueue = []
        refreshTask = nil
        rerunRequested = false
        currentDeadline = nil
        pausedRemaining = 0
        inGap = false
        seenCache = nil
        memorySeen = []
    }

    // MARK: 본 것 기록

    /// 이 계정의 본 것 기록(오래된 것 → 최근, 최대 100).
    package var seenMegaphoneIDs: [String] { seenIDs() }

    package func hasSeen(megaphoneID: String) -> Bool { seenIDs().contains(megaphoneID) }

    private func seenIDs() -> [String] {
        guard let userID = host?.session?.userID, !userID.isEmpty else { return memorySeen }
        if let seenCache, seenCache.userID == userID { return seenCache.ids }
        let ids = defaults.stringArray(forKey: MegaphoneBannerRules.seenKey(userID: userID)) ?? []
        seenCache = (userID, ids)
        return ids
    }

    private func recordSeen(_ megaphoneID: String) {
        guard !megaphoneID.hasPrefix(Self.localIDPrefix) else { return }
        var ids = seenIDs()
        ids.removeAll { $0 == megaphoneID }
        ids.append(megaphoneID)
        if ids.count > MegaphoneBannerRules.seenLimit { ids.removeFirst(ids.count - MegaphoneBannerRules.seenLimit) }
        if let userID = host?.session?.userID, !userID.isEmpty {
            seenCache = (userID, ids)
            defaults.set(ids, forKey: MegaphoneBannerRules.seenKey(userID: userID))
        } else {
            memorySeen = ids
        }
    }

    // MARK: 줄 · 타이머

    private static let localIDPrefix = "local-"

    /// 한 건을 줄에 넣는다. 같은 확성기가 떠 있거나 줄에 있으면 정보만 얹는다 · 이미 봤거나 묵었으면 버린다.
    private func offer(_ banner: MegaphoneBanner, fromPush: Bool, atFront: Bool, now: Date) {
        if let showing = current, showing.megaphoneID == banner.megaphoneID {
            let merged = showing.merged(with: banner)
            if merged != showing { current = merged }
            return
        }
        if let index = queue.firstIndex(where: { $0.megaphoneID == banner.megaphoneID }) {
            let merged = queue[index].merged(with: banner)
            if merged != queue[index] { queue[index] = merged }
            if fromPush { fromPushIDs.insert(banner.megaphoneID) }
            return
        }
        guard !hasSeen(megaphoneID: banner.megaphoneID),
              MegaphoneBannerRules.isPresentable(createdAt: banner.createdAt, now: now, fromPush: fromPush) else { return }
        if fromPush { fromPushIDs.insert(banner.megaphoneID) }
        if atFront {
            queue.insert(banner, at: 0)
        } else {
            let index = queue.firstIndex(where: { $0.createdAt > banner.createdAt }) ?? queue.endIndex
            queue.insert(banner, at: index)
        }
    }

    /// 띄울 수 있으면 줄 맨 앞을 띄운다. 묵은 것(신선도 밖)은 이때 버린다 — 미룸이 풀린 뒤에도 신선한 것만 뜬다.
    private func pump() {
        guard current == nil, !inGap, !isBannerDeferred() else { return }
        let now = clock()
        let before = queue.count
        let kept = queue.filter { banner in
            MegaphoneBannerRules.isPresentable(createdAt: banner.createdAt, now: now,
                                               fromPush: fromPushIDs.contains(banner.megaphoneID))
        }
        if kept.count != before {
            queue = kept
            fromPushIDs.formIntersection(kept.map(\.megaphoneID))
        }
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        currentFromPush = fromPushIDs.remove(next.megaphoneID) != nil
        current = next
        if isTimerPaused { isTimerPaused = false }
        recordSeen(next.megaphoneID)
        startTimer(after: MegaphoneBannerRules.displaySeconds)
    }

    private func startTimer(after delay: TimeInterval) {
        timerToken += 1
        let token = timerToken
        currentDeadline = clock().addingTimeInterval(delay)
        schedule(delay) { [weak self] in
            guard let self, self.timerToken == token, self.current != nil, !self.isTimerPaused else { return }
            self.dismissCurrent()
        }
    }

    private nonisolated static func isMissingFunction(_ error: Error) -> Bool {
        guard let known = error as? SupabaseWorkServiceError else { return false }
        return BlockReportRules.isMissingFunction(known)
    }
}
