import Foundation
import CheckCore

// MARK: - 이전 대화 더 보기 (2026-11-11 — 메시지 30일 보관 · `message_page`)
//
// 대표 결정(#d_IKem7qxZXc5b): "메시지 30일로 늘리기" — 앱에 '이전 대화 더 보기' 추가.
// 서버 최종 목록 §1: 옛 함수·안 읽음 요약·읽음 처리·푸시 만료는 **24시간 그대로**, 새 앱만 `message_page` 로 30일 안을 쪽으로 넘긴다.
// 전선 이름·키·행 모양은 코어 `MessageHistoryPaging.swift` 한 곳이다.
//
// ── 이 파일이 지키는 다섯 가지 ──
//
// ① **24시간 머리(`messageHistory`)는 한 글자도 안 바뀐다.** 지난 쪽은 `messageOlderPages` 에 **따로** 든다 — 머리에 섞이면
//    읽음 경계 판정이 서버 순서표에 없는 옛 줄을 "마지막 받은 말"로 고르고(점이 영영 안 꺼진다), 24시간 너머의 받은 말이
//    메뉴바 점을 켠다. 그래서 지난 쪽은 점 · 읽음 처리 · 모두 읽음 · 확성기 판정 보류 · 말풍선 필터 어디에도 안 들어간다.
// ② **서버를 부르는 자리는 버튼 하나다**(`loadOlderMessages`). 패널 열기 · 폴링 · 전송 · 도착 어디에서도 부르지 않는다 —
//    기존 요청 수가 그대로이고, 함수가 없는 서버에 매번 헛조회를 내지 않는다.
// ③ **쓸 수 있는가는 세 갈래다**(nil 모름 · false 없음 · true 있음). 문(min_build)은 없다 — 404/PGRST202 면 숨긴다. 숨김은
//    **영구히 들지 않는다** — 다음 패널 열기에서 모름으로 되돌린다(db push 는 앱이 떠 있는 동안 끝난다 — `fetchMessageHistoryPreferringReads`
//    와 같은 판단). 한 번이라도 성공했으면 입력칸 안내가 30일 문장이 된다.
// ④ **세대 · 순번 · 상대 가드.** 로그아웃 · 닫기 · 상대 바꾸기 뒤에 도착한 응답은 버린다(남의 30일 대화가 다른 사람 화면에 붙으면
//    그게 이 기능의 가장 나쁜 사고다). 응답 경로는 **선택을 읽기만 한다**(V0251MessagePeerTests 의 소스 계약 — 상대를 바꾸지 않는다).
// ⑤ 본문은 사람이 쓴 문장이다 — 이 파일에 `print`/`Logger` 를 붙이지 마라.
//
// ── 커서 ──
// 머리 줄은 µs 시각이 없다(옛 함수는 초 단위). 그래서 **첫 누름은 커서 없이** 30일 안의 최신부터 받고, 머리에 있는 id 는 버린다(머리가 이긴다).
// 꽉 찬 쪽이 전부 머리와 겹쳤으면 같은 누름 안에서 이어 묻는다(`MessageNoticeText.olderCatchUpRequests` 번까지) — 옛 줄 하나라도
// 붙거나 서버가 상한보다 적게 주면 멈춘다. 다음 커서는 지금까지 **서버가 준 가장 오래된 줄**(버린 확성기 줄 포함)의 (µs, id)다.

/// 지난 쪽을 붙인 직후 대화가 제자리를 지키게 하는 표(뷰가 이 메시지를 위에 맞춘다).
/// `serial` 이 바뀔 때만 뷰가 움직인다 — 같은 id 로 두 번 붙여도 다시 맞춘다.
struct MessageOlderScrollAnchor: Equatable, Sendable {
    let serial: Int
    let messageID: String
}

/// 대화 맨 위 줄의 모양(순수 — 결정적 검증 지점). nil = 줄을 아예 안 그린다(함수 없는 서버 · 상대 없음 · 로그인 전).
enum MessageOlderRowState: Equatable, Sendable {
    /// [이전 대화 더 보기]
    case button
    /// 받는 중(눌리지 않는다).
    case loading
    /// 실패 — 다시 누르면 다시 받는다.
    case failed
    /// 서버가 "더 없다"고 했다(30일 끝 · 그 전 말 없음).
    case end

    var title: String {
        switch self {
        case .button: return MessageNoticeText.olderButtonTitle
        case .loading: return MessageNoticeText.olderLoading
        case .failed: return MessageNoticeText.olderFailed
        case .end: return MessageNoticeText.olderEnd
        }
    }

    /// 누르면 받는가.
    var isTappable: Bool { self == .button || self == .failed }
}

@MainActor
extension WorkTimerStore {
    // MARK: 파생값(창이 읽는 것)

    /// 열린 대화에 그릴 메시지 — 지난 쪽 + 24시간 머리(`selectedMessageThread`). **다시 정렬하지 않고 잇는다**
    /// (`MessageOlderHistoryRules.merged` — 머리에 있는 id 는 지난 쪽에서 뺀다). 머리 쪽은 예전 그대로 확성기 줄을 뺀 판이고,
    /// 지난 쪽은 코어가 확성기 줄(`is_megaphone`)을 이미 버렸다(판정 보류는 지난 쪽에 걸지 않는다 — 확인 조회는 머리만 한다).
    var selectedConversationMessages: [MessageHistoryEntry] {
        let head = selectedMessageThread?.messages ?? []
        guard let peer = selectedMessagePeerID, !blockHiddenPeerIDs.contains(peer),
              let older = messageOlderPages[peer], !older.isEmpty
        else { return head }
        return MessageOlderHistoryRules.merged(older: older, head: head)
    }

    /// 대화 맨 위 줄의 모양. 함수가 없는 서버면 nil(줄이 없다) — **뷰는 이것 하나만 본다**(게이트 짝: `loadOlderMessages` 가드와 같은 조건).
    var messageOlderRowState: MessageOlderRowState? {
        guard session != nil, let peer = selectedMessagePeerID, messageOlderAvailable != false else { return nil }
        if messageOlderLoading { return .loading }
        if messageOlderFailed { return .failed }
        if messageOlderHasMore[peer] == false { return .end }
        return .button
    }

    /// 입력칸 옆 보관 안내. `message_page` 가 **한 번이라도 성공한 뒤에만** 30일 문장이다 — 모르거나 없는 서버는 예전 24시간 문장
    /// (서버 1단계 전 · 옛 서버). 숫자는 상수에서 나온다(`MessageNoticeText.storeDays` · `historyHours`).
    var messageExpiryNoticeNow: String {
        messageOlderAvailable == true ? MessageNoticeText.storeExpiry : Self.messageExpiryNotice
    }

    // MARK: 버튼 (서버를 부르는 유일한 자리 — 머리 ②)

    /// [이전 대화 더 보기]. 함수가 없거나 · 받는 중이거나 · 서버가 "더 없다"고 했으면 아무것도 안 한다.
    func loadOlderMessages() {
        guard canLoadOlderMessages else { return }
        Task { @MainActor in await performLoadOlderMessages() }
    }

    private var canLoadOlderMessages: Bool {
        guard session != nil, let peer = selectedMessagePeerID else { return false }
        return !messageOlderLoading && messageOlderAvailable != false && messageOlderHasMore[peer] != false
    }

    /// 지금 이 응답이 아직 이 화면의 것인가(세대 · 순번 · 상대 — 머리 ④). 상대는 **읽기만** 한다.
    private func isCurrentOlderRequest(generation: Int, token: Int, peer: String) -> Bool {
        generation == sessionGeneration && token == messageOlderRequestToken && selectedMessagePeerID == peer
    }

    /// 누름 한 번. 옛 줄 하나라도 붙거나, 서버가 끝이라고 하거나, 이어 묻기 상한에 닿을 때까지 쪽을 받는다(파일 머리 "커서").
    func performLoadOlderMessages() async {
        guard canLoadOlderMessages, let peer = selectedMessagePeerID, let me = session?.userID else { return }
        let generation = sessionGeneration
        let token = messageOlderRequestToken
        let peerName = selectedMessagePeerName
        let peerAvatarURL = selectedMessagePeerAvatarURL
        messageOlderLoading = true
        if messageOlderFailed { messageOlderFailed = false }
        defer {
            if generation == sessionGeneration, token == messageOlderRequestToken, messageOlderLoading {
                messageOlderLoading = false
            }
        }
        do {
            for _ in 0..<MessageNoticeText.olderCatchUpRequests {
                let cursor = messageOlderCursors[peer]
                let page = try await withSessionRetry { activeSession in
                    try await service.fetchMessagePage(
                        accessToken: activeSession.accessToken,
                        peer: peer,
                        me: me,
                        before: cursor,
                        peerName: peerName,
                        peerAvatarURL: peerAvatarURL
                    )
                }
                guard isCurrentOlderRequest(generation: generation, token: token, peer: peer) else { return }
                if messageOlderAvailable != true { messageOlderAvailable = true }
                // 붙인 뒤 위에 맞출 줄 — 붙이기 **직전** 화면 맨 위의 메시지(그 사이 머리가 바뀌었을 수 있다).
                let anchorID = selectedConversationMessages.first?.id
                let older = messageOlderPages[peer] ?? []
                let next = MessageOlderHistoryRules.prepending(
                    page.entries, to: older, head: messageHistory.filter { $0.peerUserID == peer }
                )
                let added = next.count - older.count
                if added > 0 { messageOlderPages[peer] = next }
                // 커서는 뒤로만 간다 — 서버가 커서를 무시해 같은 쪽을 다시 줘도 끝없이 묻지 않는다.
                var advanced = false
                if let oldest = page.oldestCursor, cursor.map({ oldest.isOlder(than: $0) }) ?? true {
                    messageOlderCursors[peer] = oldest
                    advanced = true
                }
                let more = page.hasMore && advanced
                messageOlderHasMore[peer] = more
                if added > 0 {
                    if let anchorID {
                        messageOlderScrollAnchor = MessageOlderScrollAnchor(
                            serial: (messageOlderScrollAnchor?.serial ?? 0) + 1, messageID: anchorID
                        )
                    }
                    return
                }
                if !more { return }
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard isCurrentOlderRequest(generation: generation, token: token, peer: peer) else { return }
            if let serviceError = error as? SupabaseWorkServiceError, Self.isMissingMessageReadFunction(serviceError) {
                // 함수가 없는 서버 — 버튼을 내린다(다음 패널 열기에서 다시 세운다). 실패([다시 시도])로 그리지 않는다.
                messageOlderAvailable = false
            } else {
                messageOlderFailed = true
            }
        }
    }

    // MARK: 비우기 · 다시 세우기

    /// 지난 쪽을 비운다(패널 닫기 · 상대 바꾸기 · 차단 · 로그아웃). 날아가던 응답은 순번으로 버린다. **쓸 수 있는가는 건드리지 않는다**
    /// (숨김을 되돌리는 자리는 패널 열기 하나 — `rearmOlderMessagesAvailability`). 커서도 비운다 — 다음 누름은 다시 최신부터다.
    func clearOlderMessages() {
        messageOlderRequestToken += 1
        if !messageOlderPages.isEmpty { messageOlderPages = [:] }
        if !messageOlderCursors.isEmpty { messageOlderCursors = [:] }
        if !messageOlderHasMore.isEmpty { messageOlderHasMore = [:] }
        if messageOlderLoading { messageOlderLoading = false }
        if messageOlderFailed { messageOlderFailed = false }
        if messageOlderScrollAnchor != nil { messageOlderScrollAnchor = nil }
    }

    /// 패널을 열 때 숨김(함수 없음)을 "모름"으로 되돌린다(머리 ③). 있음은 그대로 둔다(그 답은 성공에서 배웠다). 서버는 안 부른다.
    func rearmOlderMessagesAvailability() {
        if messageOlderAvailable == false { messageOlderAvailable = nil }
    }

    /// 24시간 머리가 미끄러졌다(`performLoadMessageHistory` 가 새 머리를 세우기 직전에 부른다). 쪽을 한 번이라도 받은 상대만
    /// (지난 쪽이나 커서가 있다), 앞 머리에서 빠진 옛 줄을 지난 쪽 끝으로 옮긴다 — 규칙은 `MessageOlderHistoryRules.carriedAcrossHeadSlide`
    /// 한 곳이다. 커서만 있고 지난 쪽이 빈 상대(첫 누름이 전부 머리와 겹쳤다)도 옮긴다 — 다음 쪽은 그 커서보다 오래된 것만 주므로,
    /// 머리에서 빠진 줄을 안 옮기면 다시 받을 길이 없다.
    func carryOlderMessagesAcrossHeadSlide(previousHead: [MessageHistoryEntry], nextHead: [MessageHistoryEntry]) {
        let paged = Set(messageOlderPages.keys).union(messageOlderCursors.keys)
        guard !paged.isEmpty else { return }
        for peer in paged {
            let older = messageOlderPages[peer] ?? []
            let carried = MessageOlderHistoryRules.carriedAcrossHeadSlide(
                peer: peer, previousHead: previousHead, nextHead: nextHead, older: older
            )
            if carried != older { messageOlderPages[peer] = carried }
        }
    }
}
