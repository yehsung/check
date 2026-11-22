import CheckCore
import Foundation

// MARK: - 이전 대화 더 보기(폰 1.0.19 — 메시지 30일 보관 · `message_page`)
//
// 대표 #d_xygj8oZRFlfH 4번 메시지 묶음(맥 0.3.86 #d_IKem7qxZXc5b "메시지 30일로 늘리기"). 전선은 코어 `MessageHistoryPaging.swift` 한 곳,
// 규칙(머리가 이긴다 · 앞에 붙이기 · 머리 미끄러짐 · 읽음 따라가기)은 코어 `MessageOlderHistoryRules` 한 곳이다. 이 파일은 맥
// `WorkTimerStoreMessageOlder` 의 폰 짝으로 같은 다섯 가지를 지킨다:
//  ① 24시간 머리(`history`)는 그대로 — 지난 쪽은 `olderPages` 에 따로 든다(점 · 읽음 처리 · 모두 읽음에 안 들어간다).
//  ② 서버를 부르는 자리는 버튼 하나(`loadOlderMessages`) — 대화 열기 · 폴링 · 전송 · 도착에서 부르지 않는다.
//  ③ 쓸 수 있는가는 세 갈래(nil · false · true). 404/PGRST202 면 숨기고, 다음 대화 열기에서 모름으로 되돌린다.
//  ④ 세대 · 순번 · 상대 가드 — 로그아웃 · 닫기 · 상대 바꾸기 뒤 응답은 버린다.
//  ⑤ 본문은 사람이 쓴 문장 — 로그 금지.

/// 지난 쪽을 붙인 직후 대화가 제자리를 지키게 하는 표(맥 `MessageOlderScrollAnchor` 와 같다).
package struct MessagesOlderScrollAnchor: Equatable, Sendable {
    package let serial: Int
    package let messageID: String
}

/// 대화 맨 위 줄의 모양(순수). nil = 줄이 없다(함수 없는 서버 · 로그인 전).
package enum MessagesOlderRowState: Equatable, Sendable {
    case button, loading, failed, end

    package var title: String {
        switch self {
        case .button: return MessageNoticeText.olderButtonTitle
        case .loading: return MessageNoticeText.olderLoading
        case .failed: return MessageNoticeText.olderFailed
        case .end: return MessageNoticeText.olderEnd
        }
    }

    package var isTappable: Bool { self == .button || self == .failed }
}

@MainActor
extension MessagesStore {
    /// 대화에 그릴 메시지 — 지난 쪽 + 24시간 머리(다시 정렬하지 않고 잇는다 · 머리에 있는 id 는 지난 쪽에서 뺀다 · 내 말 읽음은 머리를 따른다).
    package func conversationMessages(for peerID: String) -> [MessageHistoryEntry] {
        let head = thread(for: peerID)?.messages ?? []
        guard !hiddenBlockedPeerIDs.contains(peerID), let older = olderPages[peerID], !older.isEmpty else {
            return photoDisplayed(head, peer: peerID)
        }
        return photoDisplayed(MessageOlderHistoryRules.merged(older: older, head: head), peer: peerID)
    }

    /// 대화 맨 위 줄. 함수가 없는 서버면 nil — 뷰는 이것 하나만 본다(게이트 짝: `loadOlderMessages` 가드와 같은 조건).
    package func olderRowState(for peerID: String) -> MessagesOlderRowState? {
        guard isSignedIn, !peerID.isEmpty, olderAvailable != false else { return nil }
        if olderLoading { return .loading }
        if olderFailed { return .failed }
        if olderHasMore[peerID] == false { return .end }
        return .button
    }

    /// 대화 위 보관 안내 — `message_page` 가 한 번이라도 성공한 뒤에만 30일 문장(모르거나 없는 서버는 예전 24시간 문장).
    package var expiryNotice: String {
        olderAvailable == true ? MessageNoticeText.storeExpiry : MessageNoticeText.expiry
    }

    /// [이전 대화 더 보기]. 함수가 없거나 · 받는 중이거나 · 서버가 "더 없다"고 했으면 아무것도 안 한다.
    package func loadOlderMessages(peerID: String) {
        guard canLoadOlderMessages(peerID: peerID) else { return }
        Task { @MainActor [weak self] in await self?.performLoadOlderMessages(peerID: peerID) }
    }

    private func canLoadOlderMessages(peerID: String) -> Bool {
        guard isSignedIn, !peerID.isEmpty else { return false }
        return !olderLoading && olderAvailable != false && olderHasMore[peerID] != false
    }

    /// 누름 한 번. 옛 줄 하나라도 붙거나, 서버가 끝이라고 하거나, 이어 묻기 상한에 닿을 때까지 쪽을 받는다(맥과 같은 고리).
    package func performLoadOlderMessages(peerID peer: String) async {
        guard canLoadOlderMessages(peerID: peer), let me = context.gomokuHost.session?.userID else { return }
        let generation = context.generation
        let token = olderRequestToken
        let peerName = peerName(for: peer)
        let peerAvatarURL = peerAvatarURL(for: peer)
        let service = context.service
        olderLoading = true
        if olderFailed { olderFailed = false }
        defer {
            if generation == context.generation, token == olderRequestToken, olderLoading { olderLoading = false }
        }
        func isCurrent() -> Bool { generation == context.generation && token == olderRequestToken }
        do {
            for _ in 0..<MessageNoticeText.olderCatchUpRequests {
                let cursor = olderCursors[peer]
                let page = try await context.withMobileSessionRetry { session in
                    try await service.fetchMessagePage(accessToken: session.accessToken, peer: peer, me: me, before: cursor,
                                                       peerName: peerName, peerAvatarURL: peerAvatarURL)
                }
                guard isCurrent() else { return }
                if olderAvailable != true { olderAvailable = true }
                // 사진 칸도 배운다: 이 쪽이 머리와 겹친 줄(머리가 이겨 지난 쪽에서 빠진다)의 사진도 그려지게(맥과 같다).
                absorbPhotoMeta(page.entries, peer: peer)
                // 붙인 뒤 위에 맞출 줄 — 붙이기 **직전** 화면 맨 위의 메시지.
                let anchorID = conversationMessages(for: peer).first?.id
                let older = olderPages[peer] ?? []
                let next = MessageOlderHistoryRules.prepending(page.entries, to: older, head: history.filter { $0.peerUserID == peer })
                let added = next.count - older.count
                if added > 0 { olderPages[peer] = next }
                // 커서는 뒤로만 간다 — 서버가 커서를 무시해 같은 쪽을 다시 줘도 끝없이 묻지 않는다.
                var advanced = false
                if let oldest = page.oldestCursor, cursor.map({ oldest.isOlder(than: $0) }) ?? true {
                    olderCursors[peer] = oldest
                    advanced = true
                }
                let more = page.hasMore && advanced
                olderHasMore[peer] = more
                if added > 0 {
                    if let anchorID {
                        olderScrollAnchor = MessagesOlderScrollAnchor(serial: (olderScrollAnchor?.serial ?? 0) + 1, messageID: anchorID)
                    }
                    return
                }
                if !more { return }
            }
        } catch {
            guard isCurrent() else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            if let serviceError = error as? SupabaseWorkServiceError, Self.isMissingFunction(serviceError) {
                // 함수가 없는 서버 — 버튼을 내린다(다음 대화 열기에서 다시 세운다). 실패([다시 시도])로 그리지 않는다.
                olderAvailable = false
            } else {
                olderFailed = true
            }
        }
    }

    /// 지난 쪽을 비운다(대화 닫기 · 상대 바꾸기 · 로그아웃). 날아가던 응답은 순번으로 버린다. 쓸 수 있는가는 건드리지 않는다.
    package func clearOlderMessages() {
        olderRequestToken += 1
        if !olderPages.isEmpty { olderPages = [:] }
        if !olderCursors.isEmpty { olderCursors = [:] }
        if !olderHasMore.isEmpty { olderHasMore = [:] }
        if olderLoading { olderLoading = false }
        if olderFailed { olderFailed = false }
        if olderScrollAnchor != nil { olderScrollAnchor = nil }
    }

    /// 대화를 열 때 숨김(함수 없음)을 모름으로 되돌린다. 서버는 안 부른다.
    package func rearmOlderMessagesAvailability() {
        if olderAvailable == false { olderAvailable = nil }
    }

    /// 24시간 머리가 미끄러졌다(이력을 새로 세우기 직전). 쪽을 한 번이라도 받은 상대만 빠진 옛 줄을 지난 쪽 끝으로 옮긴다(코어 규칙 한 곳).
    func carryOlderMessagesAcrossHeadSlide(previousHead: [MessageHistoryEntry], nextHead: [MessageHistoryEntry]) {
        let paged = Set(olderPages.keys).union(olderCursors.keys)
        guard !paged.isEmpty else { return }
        let now = context.clock.now()
        for peer in paged {
            let older = olderPages[peer] ?? []
            let carried = MessageOlderHistoryRules.carriedAcrossHeadSlide(peer: peer, previousHead: previousHead, nextHead: nextHead,
                                                                          older: older, now: now)
            if carried != older { olderPages[peer] = carried }
        }
    }
}
