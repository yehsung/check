import CheckCore
import CheckMobileShared
import Foundation

// 메시지 탭의 **순수 규칙**(SPEC-ios §3.3 · SPEC-ios-build D4). 스토어와 화면이 같은 표를 읽고, 테스트가 헤드리스로 잰다.
//
// 코어(`MessageRules.swift`)에 이미 있는 것 — 묶기·정렬·날짜 구분선·안 읽음 상대·읽음 경계·안내 문구 — 은 **그대로 부른다.**
// 여기 있는 것은 폰 화면만의 규칙이다: 탭 배지 숫자 · 보내는 중 말풍선 정리 · 입력 카운터 · 사람 찾기 · 대화 줄 모양 · 바닥 따라가기.
// 전부 Foundation 만 쓴다(macOS `swift test` 로 검증).
//
// ★ 이 파일에 `print`/`Logger` 를 붙이지 마라 — 메시지 본문은 사람이 쓴 문장이다(맥 메시지 파일 공통 규약).

// MARK: - 탭 배지 숫자

package enum MessagesBadgeRules {
    /// 안 읽은 **메시지 수**(탭 배지). 판정 재료와 선택 규칙은 `MessageUnreadRules.unreadPeerIDs` 와 **같다** —
    /// 서버 스냅샷(이력의 읽음 칸 · 요약) 중 더 나중에 띄운 쪽, 그 스냅샷이 모르는 낙관 읽음은 뺀다.
    /// 그래서 "점이 하나라도 있다 ⇔ 숫자 > 0" 이 늘 성립한다(`MessagesRulesTests` 가 표로 잰다).
    ///
    /// - 이력이 더 새것: 받은 말 중 `isUnread == true` 이고 낙관 경계에 덮이지 않은 것의 개수.
    /// - 요약이 더 새것: 요약의 상대별 개수 합(낙관 읽음으로 뺀 상대는 통째로 뺀다 — 요약은 id 를 모른다).
    /// - 둘 다 없음(읽음을 모르는 옛 서버): 옛 도장 규칙으로 안 읽은 대화의 받은 말 수.
    package static func unreadCount(
        history: [MessageHistoryEntry],
        historySnapshot: MessageHistoryReadSnapshot?,
        summary: MessageUnreadSummarySnapshot?,
        optimistic: [String: MessageOptimisticRead],
        legacyStamps: [String: Date]
    ) -> Int {
        let useHistory: Bool
        switch (historySnapshot, summary) {
        case (nil, nil):
            var count = 0
            for peer in MessageUnreadRules.legacyUnreadPeerIDs(history: history, stamps: legacyStamps) {
                let stamp = legacyStamps[peer]
                count += history.filter { entry in
                    guard entry.peerUserID == peer, !entry.isMine else { return false }
                    guard let stamp else { return true }
                    return entry.createdAt > stamp
                }.count
            }
            return count
        case (.some, nil): useHistory = true
        case (nil, .some): useHistory = false
        case (.some(let h), .some(let s)): useHistory = h.serial > s.serial
        }
        if useHistory, let snapshot = historySnapshot {
            let order = MessageUnreadRules.effectiveOrder(history: history, serverOrder: snapshot.serverOrder)
            return history.reduce(0) { count, entry in
                guard !entry.isMine, entry.isUnread == true else { return count }
                if let record = optimistic[entry.peerUserID], !record.isKnown(bySnapshotSerial: snapshot.serial),
                   MessageUnreadRules.isCovered(entry, by: record, order: order) {
                    return count
                }
                return count + 1
            }
        }
        guard let summary else { return 0 }
        return summary.summary.peers.reduce(0) { count, peer in
            if let record = optimistic[peer.peerUserID], !record.isKnown(bySnapshotSerial: summary.serial) {
                return count
            }
            return count + peer.count
        }
    }
}

// MARK: - 보내는 중 말풍선

/// 보내기 버튼을 누른 순간부터 서버 이력이 그 말을 들고 올 때까지 대화 끝에 서는 **자리 말풍선**.
///
/// 맥은 전송 성공 뒤 이력만 다시 받는다(서버가 본문을 정규화하고 시각을 정하므로 가짜 행을 판에 넣지 않는다). 폰도 **판에는 넣지 않는다** —
/// 이 값은 이력(`history`)과 따로 살고 화면만 끝에 붙여 그린다. 그래서 읽음 경계·안 읽음 계산·정렬은 이 값을 모른다.
package struct MessagesPendingOutgoing: Identifiable, Equatable, Sendable {
    package enum State: Equatable, Sendable {
        /// 서버 왕복 중.
        case sending
        /// 서버가 받았다(`ok`). 번호는 응답을 받은 순간의 일련번호 — 그보다 **나중에 띄운** 이력이 반영되면 사라진다.
        case sent(settledSerial: Int)
    }

    package let id: String
    package let peerUserID: String
    /// 정규화한 본문(`MessageBody.validate` 의 `.ok` 값 — 서버로 보낸 그 글자).
    package let body: String
    package let createdAt: Date
    package var state: State

    package init(id: String, peerUserID: String, body: String, createdAt: Date, state: State) {
        self.id = id
        self.peerUserID = peerUserID
        self.body = body
        self.createdAt = createdAt
        self.state = state
    }
}

package enum MessagesPendingRules {
    /// 본문이 같은 새 서버 행을 "그 자리 말풍선의 진짜 행"으로 볼 시각 창(초). 기기 시계와 서버 시계가 어긋나도 잡히게 넉넉히 둔다 —
    /// 이 창 밖의 같은 본문(아침에 보낸 "ㅇㅇ")은 새로 보낸 말로 착각하지 않는다.
    package static let bodyMatchWindowSeconds: TimeInterval = 600

    /// 이력 응답(`appliedSerial` 로 띄운 것)을 반영한 뒤 남길 자리 말풍선.
    ///  1. 응답을 받은 뒤(`sent`)에 띄운 이력이 반영됐으면 → 서버가 그 말을 안다(들고 왔거나, 보관 창 밖이라 없다). 지운다.
    ///  2. 이번 응답에 **처음 나타난** 내 말(같은 상대 · 같은 본문 · 시각 창 안)이 있으면 → 그 행이 진짜다. 하나씩 짝지어 지운다
    ///     (전송 응답보다 먼저 띄운 이력이 행을 들고 오는 경합 — 안 지우면 같은 말이 두 번 보인다).
    ///  3. 나머지는 남긴다(아직 날아가는 중이거나, 이 응답이 그 말을 모를 수 있다).
    package static func reconcile(
        pending: [MessagesPendingOutgoing],
        previousHistoryIDs: Set<String>,
        applied: [MessageHistoryEntry],
        appliedSerial: Int
    ) -> [MessagesPendingOutgoing] {
        guard !pending.isEmpty else { return [] }
        var claimed: Set<String> = []
        var kept: [MessagesPendingOutgoing] = []
        for item in pending {
            if case .sent(let settled) = item.state, appliedSerial > settled {
                continue
            }
            let match = applied.first { entry in
                entry.isMine && entry.peerUserID == item.peerUserID && entry.body == item.body
                    && !previousHistoryIDs.contains(entry.id) && !claimed.contains(entry.id)
                    && abs(entry.createdAt.timeIntervalSince(item.createdAt)) <= bodyMatchWindowSeconds
            }
            if let match {
                claimed.insert(match.id)
                continue
            }
            kept.append(item)
        }
        return kept
    }
}

// MARK: - 보내기 결과 문구

package enum MessagesSendRules {
    /// 네트워크·서버 장애·함수 없음. 맥 `WorkTimerStore.sendMessage` 의 catch 문장과 **같은 글자**다.
    package static let connectionNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"

    /// 서버 status → 입력칸 위 한 줄. 성공은 nil(방금 보낸 말풍선이 곧 확인이다 — 문구를 겹쳐 세우지 않는다).
    /// 문장은 코어 `MessageNoticeText`(맥과 같은 문장)이고, `flood` 는 맥처럼 조용한 일반 안내로 접는다(카운트다운 금지).
    package static func notice(for outcome: MessageSendOutcome, maxLength: Int?) -> String? {
        switch outcome {
        case .ok: return nil
        case .notWorking: return MessageNoticeText.notWorking
        case .targetNotWorking: return MessageNoticeText.targetNotWorking
        case .targetFocused: return MessageNoticeText.targetFocused
        case .tooLong: return MessageNoticeText.tooLong(maxLength: maxLength)
        case .notText: return MessageNoticeText.notText
        case .blackout: return MessageNoticeText.blackout
        case .flood, .invalid: return MessageNoticeText.invalid
        }
    }
}

// MARK: - 입력칸

package enum MessagesComposerRules {
    /// 카운터를 보이기 시작하는 길이(코드포인트). SPEC-ios §3.3: 180자부터.
    package static let counterThreshold = 180

    /// "185/200" — 180 미만이면 nil(자리를 먹지 않는다). 눈금은 `MessageBody.length`(서버 char_length 와 같은 코드포인트)다.
    package static func counterText(for draft: String) -> String? {
        let length = MessageBody.length(draft)
        guard length >= counterThreshold else { return nil }
        return "\(length)/\(MessageBody.maxLength)"
    }

    package static func isOverflowing(_ draft: String) -> Bool {
        MessageBody.length(draft) > MessageBody.maxLength
    }

    /// [보내기]를 눌렀을 때 화면이 할 일. **한글 조합 중에는 보내지 않는다** — 조합 중인 마지막 글자는 아직 입력칸 값에 확정되지 않았다
    /// (맥 v0.3.11 "뒤에 한 글자가 사라져요"). 화면은 조합을 먼저 확정하고(`commitThenSend`), 확정된 값으로 다시 판정해 보낸다.
    package enum SendAction: Equatable, Sendable {
        case none
        case commitThenSend
        case send
    }

    package static func sendAction(isComposing: Bool, canSendCommittedDraft: Bool) -> SendAction {
        if isComposing { return .commitThenSend }
        return canSendCommittedDraft ? .send : .none
    }
}

// MARK: - 사람 찾기

package enum MessagesDirectoryRules {
    private static let choseong: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// 이름 검색. 빈 검색어면 전부(근무 중 먼저 · 이름순 — 코어 `sortedForPokeDisplay`).
    /// - 보통 검색: 대소문자·발음 구별 없이 이름에 들어 있으면.
    /// - 초성 검색: 검색어가 한글 자음(ㄱ~ㅎ)만이면 이름의 초성열에 들어 있으면("ㅎㄱ" → "한결").
    package static func filter(_ entries: [PokeDirectoryEntry], query: String) -> [PokeDirectoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = entries.sortedForPokeDisplay()
        guard !trimmed.isEmpty else { return sorted }
        let compact = trimmed.filter { !$0.isWhitespace }
        if !compact.isEmpty, compact.allSatisfy({ choseong.contains($0) }) {
            return sorted.filter { initials(of: $0.name).contains(compact) }
        }
        return sorted.filter { $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// 이름의 초성열(한글 음절만 초성으로 바꾸고, 나머지 글자는 그대로 · 공백은 뺀다).
    package static func initials(of name: String) -> String {
        var result = ""
        for scalar in name.unicodeScalars where !scalar.properties.isWhitespace {
            if (0xAC00...0xD7A3).contains(scalar.value) {
                result.append(choseong[Int((scalar.value - 0xAC00) / 588)])
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

// MARK: - 목록 · 라우트

/// 메시지 탭 내비게이션 경로의 원소(탭이 정한다 — 라우터는 모른다).
package enum MessagesDestination: Hashable, Sendable {
    case conversation(peerID: String)
}

package enum MessagesListRules {
    /// 목록 한 줄 미리보기: 줄바꿈·연속 공백을 한 칸으로 접는다(한 줄에 첫 줄만 남으면 "안녕\n…" 이 "안녕" 으로 읽힌다).
    package static func preview(_ body: String) -> String {
        body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// 딥링크 → 메시지 탭 경로. 메시지 탭 라우트가 아니면 nil. `.messages` 는 빈 경로(목록 맨 위).
    package static func destinations(for route: AingRoute) -> [MessagesDestination]? {
        switch route {
        case .messages: return []
        case .message(let peerID): return [.conversation(peerID: peerID)]
        default: return nil
        }
    }
}

// MARK: - 대화 줄

/// 대화 화면 한 줄(코어 `MessageThreadBuilder.timeline` 위에 폰의 모양 결정을 얹은 것 — 뷰가 조건을 다시 세지 않는다).
package enum MessagesConversationItem: Identifiable, Equatable {
    case day(key: String, label: String)
    case bubble(MessagesBubbleLine)
    case pending(MessagesPendingOutgoing)

    package var id: String {
        switch self {
        case .day(let key, _): return "day-\(key)"
        case .bubble(let line): return line.entry.id
        case .pending(let item): return "pending-\(item.id)"
        }
    }
}

package struct MessagesBubbleLine: Equatable {
    package let entry: MessageHistoryEntry
    /// "14:05"(KST 24시간제).
    package let clockText: String
    /// 시각을 이 말풍선 옆에 찍는가 — 같은 쪽·같은 분의 다음 말풍선이 이어지면 마지막 것에만 찍는다.
    package let showsTime: Bool
    /// 받은 말 묶음의 첫 말풍선에만 아바타·이름.
    package let showsAvatar: Bool
    /// 내 말풍선 옆 **1**(서버가 읽음을 알고 · 내 말이고 · `readByPeer == false`). 맥 `MessageReadReceiptMark` 와 같은 조건.
    package let showsUnreadOne: Bool
}

package enum MessagesConversationRules {
    /// 말풍선 옆 1(카톡과 같은 글자)과 보이스오버 문구.
    package static let unreadOneText = "1"
    package static let unreadOneAccessibilityLabel = "안 읽음"

    package static func showsUnreadOne(for entry: MessageHistoryEntry, receiptsAvailable: Bool) -> Bool {
        receiptsAvailable && entry.isMine && entry.readByPeer == false
    }

    /// 시간순 이력(한 사람) + 그 사람에게 보내는 중인 자리 말풍선 → 화면 줄.
    package static func items(
        messages: [MessageHistoryEntry],
        pending: [MessagesPendingOutgoing],
        receiptsAvailable: Bool,
        now: Date,
        calendar: Calendar = MobileRelativeTime.kst
    ) -> [MessagesConversationItem] {
        let timeline = MessageThreadBuilder.timeline(messages, now: now, calendar: calendar)
        var items: [MessagesConversationItem] = []
        for (index, item) in timeline.enumerated() {
            switch item {
            case .day(let key, let label):
                items.append(.day(key: key, label: label))
            case .bubble(let entry):
                let clock = MessageThreadBuilder.clockText(entry.createdAt, calendar: calendar)
                let previous: MessageHistoryEntry? = index > 0 ? timeline[index - 1].bubbleEntry : nil
                let next: MessageHistoryEntry? = index + 1 < timeline.count ? timeline[index + 1].bubbleEntry : nil
                let continuesToNext = next.map {
                    $0.isMine == entry.isMine && MessageThreadBuilder.clockText($0.createdAt, calendar: calendar) == clock
                } ?? false
                let startsRun = previous.map { $0.isMine != entry.isMine } ?? true
                items.append(.bubble(MessagesBubbleLine(
                    entry: entry,
                    clockText: clock,
                    showsTime: !continuesToNext,
                    showsAvatar: !entry.isMine && startsRun,
                    showsUnreadOne: showsUnreadOne(for: entry, receiptsAvailable: receiptsAvailable)
                )))
            }
        }
        if !pending.isEmpty {
            // 자리 말풍선은 "지금" 보냈다 — 마지막 날짜가 오늘이 아니면 오늘 구분선을 먼저 세운다.
            let todayKey = MessageThreadBuilder.dayKey(now, calendar: calendar)
            var lastDayKey: String?
            for item in items.reversed() {
                if case .day(let key, _) = item {
                    lastDayKey = key
                    break
                }
            }
            if lastDayKey != todayKey {
                items.append(.day(key: todayKey, label: MessageThreadBuilder.dayLabel(now, now: now, calendar: calendar)))
            }
            items.append(contentsOf: pending.map { .pending($0) })
        }
        return items
    }

    /// 빈 자리 문구(맥 `MessagePanelEmptyMessage` 와 같은 갈래·같은 문장 — 상대는 폰에서 늘 정해져 있다).
    package static func emptyState(loaded: Bool, failed: Bool) -> MessagesEmptyState {
        if failed, !loaded {
            return MessagesEmptyState(symbol: "exclamationmark.triangle", title: "대화를 불러오지 못했어요", hint: nil, showsRetry: true)
        }
        if !loaded {
            return MessagesEmptyState(symbol: "hourglass", title: "불러오는 중…", hint: nil, showsRetry: false)
        }
        return MessagesEmptyState(
            symbol: "bubble.left.and.bubble.right",
            title: "아직 주고받은 메시지가 없어요",
            hint: "아래에 먼저 한마디 남겨 보세요",
            showsRetry: false
        )
    }
}

package struct MessagesEmptyState: Equatable, Sendable {
    package let symbol: String
    package let title: String
    package let hint: String?
    package let showsRetry: Bool
}

private extension MessageTimelineItem {
    var bubbleEntry: MessageHistoryEntry? {
        if case .bubble(let entry) = self { return entry }
        return nil
    }
}

// MARK: - 바닥 따라가기

/// 대화 스크롤의 **바닥 따라가기**(맥 v0.3.31 M4 `MessageScrollFollow` 와 같은 규칙 — 그 타입은 맥 타깃에 있어 폰이 못 부른다).
///  · 바닥 근처(`nearBottomThreshold` 안)에서 보고 있으면 새 말이 오는 대로 따라 내려간다.
///  · 위로 올려 옛 말을 읽는 중이면 끌어내리지 않는다 — "새 메시지 ↓" 버튼을 세우고, 누르거나 스스로 바닥에 닿으면 내린다.
///  · 내가 보낸 말은 어디서 보냈든 따라간다.
///  · **내용이 자라서 멀어진 것은 "위로 올렸다"가 아니다**(레이아웃 측정이 따라가기 판정보다 먼저 올 수 있다).
package struct MessagesScrollFollow: Equatable, Sendable {
    package static let nearBottomThreshold: Double = 60
    package static let newMessageButtonTitle = "새 메시지 ↓"

    package private(set) var isNearBottom = true
    package private(set) var showsNewMessageButton = false
    private var lastContentHeight: Double?

    package init() {}

    /// 스크롤 측정. `distanceToBottom` = 내용 바닥 − 보이는 영역 바닥(0 이하 = 바닥에 닿음).
    /// `viewportChanged` = 보이는 틀이 바뀌었다(키보드 · 입력칸이 자람 · 안내 줄). **틀이 줄어 바닥이 멀어진 것도 "올림"이 아니다** —
    /// 그걸 올림으로 읽으면 키보드를 올리는 순간 따라가기가 꺼져 마지막 말이 입력칸 뒤에 숨는다(AX3 데모 스크린샷 실측).
    package mutating func measured(contentHeight: Double, distanceToBottom: Double, viewportChanged: Bool = false) {
        guard contentHeight > 0 else { return }
        let grew = lastContentHeight.map { abs($0 - contentHeight) > 0.5 } ?? true
        lastContentHeight = contentHeight
        if distanceToBottom <= Self.nearBottomThreshold {
            isNearBottom = true
            showsNewMessageButton = false
        } else if !grew, !viewportChanged {
            isNearBottom = false
        }
    }

    /// 마지막 줄이 바뀌었다. 바닥으로 따라가야 하면 true, 못 따라가면 버튼을 세운다.
    package mutating func lastItemChanged(isMine: Bool) -> Bool {
        if isNearBottom || isMine {
            isNearBottom = true
            showsNewMessageButton = false
            return true
        }
        showsNewMessageButton = true
        return false
    }

    package mutating func jumpedToBottom() {
        isNearBottom = true
        showsNewMessageButton = false
    }
}
