import Foundation

// D-base(iOS 0.1): 메시지의 **순수 규칙**을 맥 스토어 파일(`Sources/check/WorkTimerStoreMessages.swift`)에서 글자 그대로 옮긴 조각.
// 폰 메시지 탭이 맥과 같은 묶기·정렬·날짜 구분선·안 읽음 판정·안내 문구를 쓰게 하려고 코어로 뗐다 — 맥 동작은 바뀌지 않는다
// (맥 스토어는 같은 이름을 그대로 부른다 · 문구 상수는 `WorkTimerStore.message…Notice` 가 여기를 가리키는 전달로 남았다).
// 소스 계약 테스트는 두 조각을 `CheckCoreSourceLayout.joinedSplitSource("WorkTimerStoreMessages.swift")` 로 이어 읽는다.
// 맥 전용으로 남은 것: 스토어 배선 · `MessageReadRuntime`(작업 수명) · `MessageConversationVisibility`(팝오버 창 사실).

// MARK: - 안내 문구 · 창 상수 (서버 status 의 사람 말 번역)
//
// 설명은 맥 스토어의 같은 이름 상수(`WorkTimerStore.messageSentNotice` 등) 머리 주석에 있다 — 뜻을 바꾸려면 거기부터 읽어라.

package enum MessageNoticeText {
    /// 이력 조회 창(시간). 서버 message_retention_hours() 와 같은 값(24).
    package static let historyHours = 24
    /// 한 번에 받아 올 이력 건수(서버가 1~500 으로 접는다).
    package static let historyLimit = 200

    package static let sent = "메시지를 보냈어요"
    package static let notWorking = "근무 중일 때만 메시지를 보낼 수 있어요"
    package static let targetNotWorking = "자리비움 상태에는 보낼 수 없어요"
    package static let targetFocused = "지금 집중 중이에요. 나중에 보내 주세요"
    package static let notText = "보낼 수 없는 글자가 섞여 있어요"
    package static let blackout = "지금은 메시지를 주고받을 수 없어요"
    package static let invalid = "지금은 메시지를 보낼 수 없어요. 잠시 후 다시 시도해 주세요"

    /// 길이 초과 안내. 서버가 알려 준 상한이 있으면 그것, 없으면 클라 상수.
    package static func tooLong(maxLength: Int? = nil) -> String {
        "메시지는 \(maxLength ?? MessageBody.maxLength)자까지예요. 줄여서 보내 주세요"
    }

    /// 대화 상단 한 줄("24시간이 지난 메시지는 사라져요").
    package static var expiry: String {
        "\(historyHours)시간이 지난 메시지는 사라져요"
    }
}

// MARK: - 읽음 값 타입 · 규칙 (순수)

/// 이력 한 번의 결과(v0.3.30). `entries` 는 **서버 순서 그대로**다.
package struct MessageHistoryLoad: Sendable {
    package init(entries: [MessageHistoryEntry], hasReadReceipts: Bool) {
        self.entries = entries
        self.hasReadReceipts = hasReadReceipts
    }

    package let entries: [MessageHistoryEntry]
    /// 읽음 칸을 실어 온 응답인가(`message_history_with_reads` 성공).
    package let hasReadReceipts: Bool

    /// 메시지 id → 서버 응답 안의 자리(0부터, 같은 id 는 처음 자리). 스냅샷과 화면 정렬(F7)이 같은 표를 쓴다.
    package var serverOrder: [String: Int] {
        var order: [String: Int] = [:]
        for (index, entry) in entries.enumerated() where order[entry.id] == nil {
            order[entry.id] = index
        }
        return order
    }
}

/// 읽음 칸을 실어 온 이력 한 번의 사실: 그 요청의 일련번호와 서버가 준 순서.
package struct MessageHistoryReadSnapshot: Equatable, Sendable {
    package init(serial: Int, serverOrder: [String: Int]) {
        self.serial = serial
        self.serverOrder = serverOrder
    }

    /// 요청을 띄운 순간의 일련번호(`MessageReadRuntime.nextSerial`). 요약·낙관 읽음과 선후를 가르는 근거다.
    package let serial: Int
    /// 메시지 id → 서버 응답 안의 자리(0부터). 같은 초 안의 선후는 이것만 안다(`created_epoch` 은 초 단위다).
    package let serverOrder: [String: Int]
}

/// 안 읽음 요약 한 번의 사실.
package struct MessageUnreadSummarySnapshot: Equatable, Sendable {
    package init(serial: Int, summary: MessageUnreadSummary) {
        self.serial = serial
        self.summary = summary
    }

    package let serial: Int
    package let summary: MessageUnreadSummary
}

/// 상대 하나에 대한 낙관 읽음 — "이 id 까지 읽었다고 서버에 말했다(또는 말하는 중이다)".
package struct MessageOptimisticRead: Equatable, Sendable {
    package init(throughID: String, recordedSerial: Int, settledSerial: Int? = nil, failed: Bool = false) {
        self.throughID = throughID
        self.recordedSerial = recordedSerial
        self.settledSerial = settledSerial
        self.failed = failed
    }

    package let throughID: String
    /// 기록을 세운 순간의 일련번호.
    package let recordedSerial: Int
    /// 서버 왕복이 끝난(성공·실패 모두) 순간의 일련번호. nil = 아직 날아가는 중.
    package var settledSerial: Int? = nil
    /// 왕복이 실패로 끝났는가. 실패한 기록은 같은 경계로 다시 올릴 수 있다(markTarget).
    package var failed = false

    /// 일련번호 `serial` 로 띄운 서버 조회가 **이 기록을 이미 반영한 서버 상태**를 봤는가.
    /// 정산 뒤에 띄운 조회만 그렇다 — 그 전에 띄운 조회(날아가는 중 포함)는 서버가 아직 모를 수 있다.
    package func isKnown(bySnapshotSerial serial: Int) -> Bool {
        guard let settledSerial else { return false }
        return serial > settledSerial
    }
}

/// 안 읽음·읽음 경계·말풍선 필터의 **순수 규칙.** 스토어와 테스트가 같은 표를 읽는다.
package enum MessageUnreadRules {
    /// 안 읽은 것이 있는 상대들.
    ///  1. 서버 스냅샷(이력의 읽음 칸 · 요약) 중 **더 나중에 띄운 쪽**을 쓴다. 둘 다 없으면 옛 규칙(도장 시각)이다.
    ///  2. 그 스냅샷이 모르는 낙관 읽음(정산 전이거나 정산보다 먼저 띄운 조회)은 뺀다.
    ///     이력은 id 로 덮였는지 본다(경계 뒤에 온 새 말은 남는다). 요약은 id 를 모르므로 그 상대를 통째로 뺀다 —
    ///     읽음 처리 성공 뒤의 새로고침(정산 뒤에 띄운 조회)이 곧 사실로 되돌린다.
    package static func unreadPeerIDs(
        history: [MessageHistoryEntry],
        historySnapshot: MessageHistoryReadSnapshot?,
        summary: MessageUnreadSummarySnapshot?,
        optimistic: [String: MessageOptimisticRead],
        legacyStamps: [String: Date]
    ) -> Set<String> {
        let useHistory: Bool
        switch (historySnapshot, summary) {
        case (nil, nil): return legacyUnreadPeerIDs(history: history, stamps: legacyStamps)
        case (.some, nil): useHistory = true
        case (nil, .some): useHistory = false
        case (.some(let h), .some(let s)): useHistory = h.serial > s.serial
        }
        if useHistory, let snapshot = historySnapshot {
            let order = effectiveOrder(history: history, serverOrder: snapshot.serverOrder)
            var peers: Set<String> = []
            for entry in history where !entry.isMine && entry.isUnread == true {
                if let record = optimistic[entry.peerUserID], !record.isKnown(bySnapshotSerial: snapshot.serial),
                   isCovered(entry, by: record, order: order) {
                    continue
                }
                peers.insert(entry.peerUserID)
            }
            return peers
        }
        guard let summary else { return [] }
        var peers = summary.summary.unreadPeerIDs
        for (peer, record) in optimistic where !record.isKnown(bySnapshotSerial: summary.serial) {
            peers.remove(peer)
        }
        return peers
    }

    /// 읽음 기능을 모르는 서버의 옛 규칙: **받은 것의 마지막 시각 > 내가 그 대화를 마지막으로 연 시각**(도장 없음 = 안 읽음).
    package static func legacyUnreadPeerIDs(history: [MessageHistoryEntry], stamps: [String: Date]) -> Set<String> {
        var unread: Set<String> = []
        for thread in MessageThreadBuilder.threads(from: history) {
            guard let lastIncoming = thread.messages.last(where: { !$0.isMine }) else { continue }
            if let stamp = stamps[thread.peerUserID], lastIncoming.createdAt <= stamp { continue }
            unread.insert(thread.peerUserID)
        }
        return unread
    }

    /// 읽음을 올릴 경계(그 대화의 **마지막 받은 메시지 id**, 서버 순서 기준). 올릴 것이 없으면 nil.
    ///  · 서버 기준 안 읽은 받은 메시지가 하나도 없으면 nil.
    ///  · 같은 경계로 이미 올렸거나 올리는 중이면 nil — 실패로 정산된 기록만 다시 올린다(이력이 올 때마다 최대 한 번).
    package static func markTarget(
        peer: String,
        history: [MessageHistoryEntry],
        snapshot: MessageHistoryReadSnapshot,
        optimistic: MessageOptimisticRead?
    ) -> String? {
        let received = history.enumerated().filter { $0.element.peerUserID == peer && !$0.element.isMine }
        guard received.contains(where: { $0.element.isUnread == true }) else { return nil }
        // 서버 순서가 정본이고, 그 뒤에 즉시 삽입된 말(v0.3.31 M4)은 서버 순서 **뒤**다(`effectiveOrder`).
        // 둘 다 모르면(테스트가 손으로 만든 이력 등) 화면 정렬 자리로 가른다.
        let order = effectiveOrder(history: history, serverOrder: snapshot.serverOrder)
        guard let last = received.max(by: { lhs, rhs in
            let l = order[lhs.element.id] ?? -1
            let r = order[rhs.element.id] ?? -1
            return l != r ? l < r : lhs.offset < rhs.offset
        })?.element else { return nil }
        if let optimistic, optimistic.throughID == last.id, !optimistic.failed { return nil }
        return last.id
    }

    /// 말풍선으로 띄우지 않을 받은 메시지인가(서버 기준 읽음 · 낙관 읽음으로 덮임). 읽음 기능을 모르면 언제나 false(옛 동작).
    ///
    /// 서버 기준은 **최신 판정**이다(m-fix F3): 이력보다 나중에 띄운 요약이 그 상대를 안 읽음 목록에 안 두면, 이력에 이미 있던
    /// 이 말은 그 사이 읽혔다(다른 기기) — 요약은 그 요청 순간 보관 창 안의 안 읽은 말을 전부 센다. 이력에 없는 말(이력 뒤에 도착)은
    /// 요약 요청보다 늦었을 수 있으므로 판정하지 않는다(띄운다).
    package static func isAlreadyRead(
        messageID: String,
        history: [MessageHistoryEntry],
        snapshot: MessageHistoryReadSnapshot?,
        optimistic: [String: MessageOptimisticRead],
        summary: MessageUnreadSummarySnapshot? = nil
    ) -> Bool {
        guard let snapshot, let entry = history.first(where: { $0.id == messageID }), !entry.isMine else { return false }
        if entry.isUnread == false { return true }
        if let record = optimistic[entry.peerUserID],
           isCovered(entry, by: record, order: effectiveOrder(history: history, serverOrder: snapshot.serverOrder)) {
            return true
        }
        if let summary, summary.serial > snapshot.serial, !summary.summary.unreadPeerIDs.contains(entry.peerUserID) {
            return true
        }
        return false
    }

    /// 선후 판정에 쓰는 순서표(v0.3.31 M4): 서버 순서 + **이력에 있지만 서버 순서가 모르는 id**(즉시 삽입한 도착분)를 그 뒤에 이력 자리 순으로.
    ///
    /// 즉시 삽입한 말은 마지막으로 반영된 이력 응답보다 나중에 도착했다(그 응답이 알았다면 서버 행이 이미 있다) — 그래서 서버 순서 **뒤**다.
    /// 이력 자리 순서를 따르는 이유: 스토어는 이력을 세울 때마다 같은 초의 즉시 삽입분을 **도착 순서**로 정렬해 둔다(m4-fix — 삽입·이력 반영 둘 다
    /// `arrivalOrder` 를 넘긴다). 그래서 자리 순서가 곧 화면 순서이고, 초가 다른 말도 화면과 같은 선후로 읽힌다.
    /// 이력에 아예 없는 id(만료로 사라진 경계 등)는 여전히 표에 없다 — `isCovered` 의 "경계를 못 찾으면 덮이지 않음"이 그대로 산다.
    /// 모르는 id 가 없으면 서버 순서를 그대로 돌려준다(뷰가 자주 읽는 점 계산에서 복사를 만들지 않게).
    package static func effectiveOrder(history: [MessageHistoryEntry], serverOrder: [String: Int]) -> [String: Int] {
        guard history.contains(where: { serverOrder[$0.id] == nil }) else { return serverOrder }
        var order = serverOrder
        var next = (serverOrder.values.max() ?? -1) + 1
        for entry in history where order[entry.id] == nil {
            order[entry.id] = next
            next += 1
        }
        return order
    }

    /// 받은 메시지가 낙관 읽음 경계 **안쪽**(경계 자신 포함)인가. 서버 순서로만 판정한다 — 경계나 그 메시지를 순서표에서
    /// 못 찾으면 덮이지 않은 것으로 본다(경계가 만료돼 사라졌다면 남은 말은 그보다 새것이다).
    package static func isCovered(_ entry: MessageHistoryEntry, by record: MessageOptimisticRead, order: [String: Int]) -> Bool {
        if entry.id == record.throughID { return true }
        guard let through = order[record.throughID], let index = order[entry.id] else { return false }
        return index <= through
    }
}

// MARK: - 정렬

extension Array where Element == MessageHistoryEntry {
    /// 서버 정렬을 신뢰하지 않고 다시 세운다: **오래된 것 → 최신**, 같은 시각이면 서버 순서, 그것도 모르면 id.
    /// 같은 시각 동점을 깨는 이유는 결정성이다 — 안 깨면 새로고침마다 두 말풍선의 순서가 뒤바뀐다.
    ///
    /// ★ 서버 순서(m-fix F7): `createdAt` 은 `created_epoch`(초, 반올림)이라 같은 초 안에서 오간 말이 동률이다. 동률을 id 사전순으로
    ///   깨면 실제 출력으로 답장이 질문보다 위에 그려졌다(X1). 서버는 created_at(마이크로초) 순서로 주므로 `serverOrder`(응답 안의 자리)가
    ///   그 선후다. 반올림은 단조라 초가 다른 두 말의 순서를 서버 순서와 거꾸로 만들지 않는다 — 초가 1차 키여도 어긋나지 않는다.
    ///   순서표에 없는 id 는 맨 뒤(`Int.max`)로 보내 비교가 언제나 전순서가 되게 한다(섞인 입력에서 정렬이 흔들리지 않게).
    ///
    /// ★ 도착 순서(m4-fix): 서버 순서가 모르는 **즉시 삽입분**(M4 — take_pokes 가 들고 온 말)끼리의 같은 초 동률은 id 가 아니라
    ///   `arrivalOrder`(메시지 id → 삽입 번호, take_pokes 행 순서)로 깬다. take_pokes 도 created_at 순서로 주므로 그 순서가 곧 서버 선후다 —
    ///   id 로 깨면 서버가 첫째→둘째로 준 두 말이 둘째→첫째로 그려지고, 읽음 경계를 앞 말로 올렸다(검증 P1). 도착분은 같은 초의 다른 말
    ///   **뒤**다(표에 없으면 -1) — 서버가 아는 말보다 늦게 왔다. 키는 (초, 서버 자리, 도착 번호, id) 사전식이라 여전히 전순서다.
    package func sortedForMessageHistory(serverOrder: [String: Int]? = nil, arrivalOrder: [String: Int] = [:]) -> [MessageHistoryEntry] {
        sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            if let serverOrder {
                let l = serverOrder[lhs.id] ?? Int.max
                let r = serverOrder[rhs.id] ?? Int.max
                if l != r { return l < r }
            }
            let la = arrivalOrder[lhs.id] ?? -1
            let ra = arrivalOrder[rhs.id] ?? -1
            if la != ra { return la < ra }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - 대화 묶음 (순수)

/// 한 사람과의 대화. `message_history` 한 번으로 받은 것을 클라에서 묶은 결과다(왕복을 늘리지 않는다).
package struct MessageThread: Identifiable, Equatable {
    package init(peerUserID: String, peerName: String, peerAvatarURL: URL?, messages: [MessageHistoryEntry]) {
        self.peerUserID = peerUserID
        self.peerName = peerName
        self.peerAvatarURL = peerAvatarURL
        self.messages = messages
    }

    package let peerUserID: String
    package let peerName: String
    package let peerAvatarURL: URL?
    /// **시간순**(오래된 것 → 최신). 화면이 그대로 위에서 아래로 쌓는다.
    package let messages: [MessageHistoryEntry]

    package var id: String { peerUserID }
    /// 목록의 미리보기·정렬 기준이 되는 마지막 한 건.
    package var lastMessage: MessageHistoryEntry? { messages.last }
}

/// 대화 화면 한 줄. 날짜 구분선이 **말풍선과 같은 배열에 사는 것**이 요점이다 —
/// 뷰가 그리는 도중에 "앞 항목과 날짜가 다른가"를 판정하면 그 판정은 테스트로 잴 수 없고,
/// 스크롤 재사용이 끼는 순간 구분선이 엉뚱한 자리에 남는다.
package enum MessageTimelineItem: Identifiable, Equatable {
    /// 날짜 구분선("오늘" / "어제" / "9월 8일").
    case day(key: String, label: String)
    case bubble(MessageHistoryEntry)

    package var id: String {
        switch self {
        case .day(let key, _): return "day-\(key)"
        case .bubble(let entry): return entry.id
        }
    }
}

/// 이력 → 화면 구조(순수). **스토어도 뷰도 자기 판을 만들지 않는다** — 묶기·정렬·구분선은 여기 한 곳이고,
/// 그래서 이 규칙 전부를 헤드리스로 잴 수 있다.
package enum MessageThreadBuilder {
    /// 상대별로 묶는다. 각 대화는 시간순, 대화 목록은 **최근 대화순**(마지막 메시지가 새로운 쪽이 위).
    ///
    /// 상대 이름·아바타는 **가장 최근 행의 것**을 쓴다 — 별명을 바꾼 사람의 옛 행이 목록에 옛 이름을 남기면
    /// 사용자는 같은 사람을 두 사람으로 읽는다(서버가 행마다 그때의 표시명을 실어 줄 수 있다).
    /// `serverOrder` 는 같은 초 동률을 깨는 서버 순서다(`sortedForMessageHistory` — 모르면 nil, 옛 규칙 id).
    /// `arrivalOrder` 는 서버가 아직 모르는 즉시 삽입분의 도착 순서다(m4-fix — 없으면 빈 표).
    package static func threads(
        from entries: [MessageHistoryEntry],
        serverOrder: [String: Int]? = nil,
        arrivalOrder: [String: Int] = [:]
    ) -> [MessageThread] {
        var order: [String] = []
        var grouped: [String: [MessageHistoryEntry]] = [:]
        for entry in entries.sortedForMessageHistory(serverOrder: serverOrder, arrivalOrder: arrivalOrder) {
            if grouped[entry.peerUserID] == nil { order.append(entry.peerUserID) }
            grouped[entry.peerUserID, default: []].append(entry)
        }
        let threads: [MessageThread] = order.compactMap { peer in
            guard let messages = grouped[peer], let latest = messages.last else { return nil }
            return MessageThread(
                peerUserID: peer,
                peerName: latest.peerName,
                peerAvatarURL: latest.peerAvatarURL,
                messages: messages
            )
        }
        return threads.sorted { lhs, rhs in
            let l = lhs.lastMessage?.createdAt ?? .distantPast
            let r = rhs.lastMessage?.createdAt ?? .distantPast
            if l != r { return l > r }
            // 동점은 id 로 깬다(결정성 — 안 깨면 새로고침마다 목록 순서가 흔들린다).
            return lhs.peerUserID < rhs.peerUserID
        }
    }

    /// 시간순 말풍선 사이에 날짜 구분선을 끼운다. **첫 항목 앞에도 반드시 하나 선다** —
    /// 없으면 맨 위 말풍선이 언제 것인지 알 방법이 시각(HH:mm)뿐이고, 그건 날짜를 말하지 않는다.
    package static func timeline(
        _ messages: [MessageHistoryEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> [MessageTimelineItem] {
        var items: [MessageTimelineItem] = []
        var lastKey: String?
        for entry in messages {
            let key = dayKey(entry.createdAt, calendar: calendar)
            if key != lastKey {
                items.append(.day(key: key, label: dayLabel(entry.createdAt, now: now, calendar: calendar)))
                lastKey = key
            }
            items.append(.bubble(entry))
        }
        return items
    }

    /// 날짜 구분선의 동일성 키(달력 기준 하루). 문자열인 이유는 구분선 id 로 그대로 쓰기 위해서다.
    package static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// 구분선 문구. 24시간 창이라 실제로 나오는 것은 "오늘"과 "어제"뿐이지만, 자정을 낀 조회에서
    /// 날짜가 바뀌는 것을 사람이 읽을 수 있어야 해서 셋을 다 만든다(달력을 넘긴 값도 안전하게 떨어진다).
    package static func dayLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "오늘" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "어제"
        }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
    }

    /// 말풍선 옆 시각("14:05"). **24시간제로 못 박는다** — 지역 설정에 따라 "오후 2:05"가 되면
    /// 말풍선 폭이 사람마다 달라지고, 이 창은 그 폭을 예산으로 쓰는 자리가 여럿이다.
    package static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    // ★ `listStampText` 와 `previewText` 는 v0.2.50 에 **왼쪽 대화 목록과 함께 사라졌다.**
    //   둘 다 그 목록의 한 행(마지막 시각 · 한 줄 미리보기)만을 위한 계산이었고, 화면이 한 사람짜리가
    //   되면서 부르는 곳이 한 곳도 남지 않았다. 테스트만 남겨 두면 **아무도 안 쓰는 함수를 지키는 테스트**가
    //   되므로 그쪽도 함께 걷었다(이 저장소는 죽은 가지를 남기지 않는다).
    //   되살려야 할 날이 오면 `dayLabel`/`clockText` 위에 다시 세우면 된다 — 그 둘은 살아 있다.
}
