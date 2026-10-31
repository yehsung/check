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

    /// 상대별 안 읽은 메시지 수(목록 줄 오른쪽 개수 배지 — 시안 B 03 "점이 아니라 개수"). `unreadCount` 와 **같은 갈래 · 같은 재료**다:
    /// 값의 합 = `unreadCount`, 키 ⊆ `MessageUnreadRules.unreadPeerIDs`(`MessagesRulesTests` 가 같은 표로 잰다). 0 인 상대는 넣지 않는다 —
    /// 요약이 개수 0 인 상대 행을 보내도 점 집합에는 들어가므로, 화면은 "점 집합에 있으면 최소 1"로 그린다(`MessagesListRules.countBadge`).
    package static func unreadCountsByPeer(
        history: [MessageHistoryEntry],
        historySnapshot: MessageHistoryReadSnapshot?,
        summary: MessageUnreadSummarySnapshot?,
        optimistic: [String: MessageOptimisticRead],
        legacyStamps: [String: Date]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        let useHistory: Bool
        switch (historySnapshot, summary) {
        case (nil, nil):
            for peer in MessageUnreadRules.legacyUnreadPeerIDs(history: history, stamps: legacyStamps) {
                let stamp = legacyStamps[peer]
                let count = history.filter { entry in
                    guard entry.peerUserID == peer, !entry.isMine else { return false }
                    guard let stamp else { return true }
                    return entry.createdAt > stamp
                }.count
                if count > 0 { counts[peer] = count }
            }
            return counts
        case (.some, nil): useHistory = true
        case (nil, .some): useHistory = false
        case (.some(let h), .some(let s)): useHistory = h.serial > s.serial
        }
        if useHistory, let snapshot = historySnapshot {
            let order = MessageUnreadRules.effectiveOrder(history: history, serverOrder: snapshot.serverOrder)
            for entry in history where !entry.isMine && entry.isUnread == true {
                if let record = optimistic[entry.peerUserID], !record.isKnown(bySnapshotSerial: snapshot.serial),
                   MessageUnreadRules.isCovered(entry, by: record, order: order) {
                    continue
                }
                counts[entry.peerUserID, default: 0] += 1
            }
            return counts
        }
        guard let summary else { return [:] }
        for peer in summary.summary.peers where peer.count > 0 {
            if let record = optimistic[peer.peerUserID], !record.isKnown(bySnapshotSerial: summary.serial) { continue }
            counts[peer.peerUserID, default: 0] += peer.count
        }
        return counts
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

    /// 응답 유실 재시도(한 번)를 걸 만한 URL 실패 — 서버의 답을 못 받아 **말이 저장됐는지 모르는** 것들.
    /// 연결 전 실패(오프라인·호스트 못 찾음)도 넣는다: 같은 키로 한 번 더 보내는 값이 1.5초 기다림 하나뿐이고,
    /// 서버가 키로 거르는 판에서만 재시도하므로(스토어 `serverKnowsSendKey`) 두 통이 될 길이 없다.
    /// 취소(`.cancelled`)는 넣지 않는다 — 누군가 멈추라고 한 왕복을 되살리지 않는다.
    package static let ambiguousURLErrorCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
        .cannotFindHost, .dnsLookupFailed, .badServerResponse,
    ]

    /// 전송 왕복이 "모호하게" 실패했는가(서버 레인 안정화 2026-10-30 — 10-29 18:54 PGRST003·504·57014).
    /// 위 URL 실패와 HTTP 5xx(`SupabaseWorkHTTP.serviceError` 가 상태코드 게이트로 `.invalidResponse(5xx)` 에 접는다)다.
    /// 4xx·429 는 서버가 **답을 준** 것이라 넣지 않는다(429 를 되치면 장애 때 요청만 는다).
    package static func isAmbiguousFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return ambiguousURLErrorCodes.contains(urlError.code)
        }
        if case SupabaseWorkServiceError.invalidResponse(let code) = error {
            return (500...599).contains(code)
        }
        return false
    }
}

/// 서버의 확정 답을 못 받은 전송 하나(스토어 `MessagesRuntime.unconfirmedSends`). 같은 상대·같은 본문을
/// `MessagesStore.unconfirmedSendReuseSeconds` 안에 다시 보내면 새 키 대신 이 키를 쓴다 — 앞의 것이 실은 저장됐으면
/// 서버가 `duplicate` 로 걸러 한 통으로 남는다.
package struct MessagesUnconfirmedSend: Equatable, Sendable {
    package let peerUserID: String
    /// 정규화한 본문(자리 말풍선 `body` 와 같은 값 — 서버로 보낸 그 글자).
    package let body: String
    /// 전송 멱등 키 = 그때 자리 말풍선의 id(소문자 uuid).
    package let key: String
    /// 마지막으로 모호하게 실패한 시각(`context.clock`).
    package let failedAt: Date

    package init(peerUserID: String, body: String, key: String, failedAt: Date) {
        self.peerUserID = peerUserID
        self.body = body
        self.key = key
        self.failedAt = failedAt
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

    /// 입력칸 자리표시(시안 B 04 — 짧게).
    package static let placeholder = "메시지 입력"

    /// 손가락으로 누르는 자리의 최소 변(pt · HIG 44). 보내기 원 · "새 메시지 ↓" 버튼이 이 값 아래로 내려가지 않는다
    /// (messages-verify 실측: 보내기 40×40 · 새 메시지 버튼 높이 31.7).
    package static let minimumTouchTarget: Double = 44
    /// 보내기 원 지름의 상한(pt). 원은 본문 글자 크기(`@ScaledMetric`)를 따라 44 에서 여기까지 자란다 — 입력칸 폭을 너무 먹지 않게.
    package static let sendButtonMaxDiameter: Double = 52
    /// 화살표 글리프 크기 = 원 지름 × 이 비율. **글리프는 글자 크기를 직접 따르지 않는다** — `.body` 를 따르면 손쉬운 사용 큰 글자(AX3)에서
    /// 화살촉이 고정 원 밖으로 빠져 원이 두 조각처럼 보이고 화살표 모양이 사라졌다(messages-verify 스크린샷).
    package static let sendGlyphRatio: Double = 0.4

    /// 보이는 원 = 누르는 자리 × 이 비율(시안 B 04: 입력칸 안 오른쪽 30pt 원). 누르는 자리는 44pt 그대로 둔다.
    package static let sendVisibleRatio: Double = 0.73

    package struct SendButtonMetrics: Equatable, Sendable {
        /// 누르는 자리의 변(pt · 44 이상).
        package let diameter: Double
        /// 화살표 글리프 글꼴 크기(pt).
        package let glyphSize: Double

        /// 입력칸 안에 그리는 원 지름(pt). 글리프(`glyphSize`)는 SF 화살표라 글꼴 크기의 약 0.75 배 높이로 그려진다 — 이 원 안에 든다.
        package var visibleDiameter: Double { (diameter * MessagesComposerRules.sendVisibleRatio).rounded() }
        /// 보이는 원 안 화살표 글꼴 크기(pt) — 원 지름의 절반 이하(시안 30pt 원 · 16pt 화살표).
        package var visibleGlyphSize: Double { min((glyphSize * 0.85).rounded(), (visibleDiameter * 0.5).rounded()) }
    }

    /// 보내기 버튼 치수. `scaledDiameter` = 44 를 본문 글자 크기로 키운 값(`@ScaledMetric(relativeTo: .body)`).
    package static func sendButtonMetrics(scaledDiameter: Double) -> SendButtonMetrics {
        let scaled = scaledDiameter.isFinite ? scaledDiameter : minimumTouchTarget
        let diameter = min(max(scaled, minimumTouchTarget), sendButtonMaxDiameter)
        let glyph = (diameter * sendGlyphRatio).rounded()
        return SendButtonMetrics(diameter: diameter, glyphSize: glyph)
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

    /// 이름 검색. 빈 검색어면 전부(**안 읽음 먼저 → 근무 중 먼저 → 이름순** — 코어 `sortedForPokeDisplay`).
    /// - 보통 검색: 대소문자·발음 구별 없이 이름에 들어 있으면.
    /// - 초성 검색: 검색어가 한글 자음(ㄱ~ㅎ)만이면 이름의 초성열에 들어 있으면("ㅎㄱ" → "한결").
    ///
    /// `unreadPeerIDs` 는 **메시지 안 읽음 ∪ 안 본 찌르기**다(사용자 결정 2026-10-23 "찌르기도 친다" — 합치는 자리는
    /// 스토어다: `MessagesStore.sortUnreadPeerIDs`). 명부 엔트리는 자기 `isWorking` 을 서버에서 들고 오므로 근무 축은
    /// 언제나 '안다'(`workKnown: true`) — 대화 목록과 달리 여기서는 축을 접지 않는다.
    ///
    /// ★ **기본값을 달지 마라.** 코어 `sortedForPokeDisplay` 가 0.3.65 에서 기본값을 걷어낸 까닭이 이것이다 —
    ///   한 겹 위에서 `= []` 로 되살리면 "안 읽음을 안 넘긴 호출"이 다시 조용히 생긴다(이 건의 출발점).
    package static func filter(
        _ entries: [PokeDirectoryEntry],
        query: String,
        unreadPeerIDs: Set<String>
    ) -> [PokeDirectoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = entries.sortedForPokeDisplay(unreadPeerIDs: unreadPeerIDs, workKnown: true)
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

// MARK: - 콕/메시지 4단 정렬 · 찌르기가 낀 대화 목록 (1.0.13)

// 사용자 결정(2026-10-23 원문): "콕/메세지 창에서 메세지 안읽은 사람들이 제일 상단에 떴으면 좋겠어. 상단 정렬 순위가
// 1. 근무중이면서 메세지 아직 안읽은 사람, 2. 근무중 아니면서 메세지 아직 안읽은 사람, 3. 근무중이면서 메세지 다 읽거나 없는사람,
// 4. 근무중 아니면서 메세지 다 읽거나 없는 사람." · 물어서 정한 것: "안 본 찌르기도 '안 읽음'으로 친다".
//
// 맥(0.3.65)과 **같은 규칙**이다. 맥 명부는 코어 `sortedForPokeDisplay` 하나로 끝나지만, 폰에는 목록이 둘이다:
//  · 대화 목록(스레드) — 같은 무리 안은 **최근순**(폰 스레드의 원래 축).
//  · 사람 찾기 명부 — 같은 무리 안은 **이름순**(`MessagesDirectoryRules.filter` → 코어 `sortedForPokeDisplay`).
//
// ★ 줄을 세우는 규칙은 **여기 한 벌뿐**이다(`MessagesThreadListRules.rows`). 화면은 `MessagesStore.threadItems(now:)` 를
//   부르고 값을 그대로 그린다 — 뷰가 안 읽음·배지·시각을 다시 세면 "찌르기뿐인 행에 안 읽은 메시지 숫자"가 되살아난다.

/// 대화 목록 한 줄(1.0.13). 코어 대화(`MessageThread`) + 그 사람과 오간 찌르기 + **다 정해진 표시값**.
///
/// ★ **찌르기만 있는 사람도 한 줄이 선다**(조정자 결정 2026-10-23 (가)) — 그때 `thread.messages` 는 비어 있다.
///   행이 없으면 안 읽은 찌르기가 폰에서 영영 안 보이고, 정렬이 그 사람을 올릴 자리도 없다.
package struct MessagesThreadItem: Identifiable, Equatable {
    /// 메시지 묶음. 찌르기만 있는 사람은 `messages` 가 빈 배열이다.
    package let thread: MessageThread
    /// 그 사람과 오간 찌르기(시간순 — 받은 것·보낸 것 모두).
    package let pokes: [MessagePokeLogEntry]
    /// 목록 정렬·오른쪽 위 시각의 기준 = **찌르기를 포함한 마지막 활동**.
    package let lastActivityAt: Date
    /// 한 줄 미리보기. 마지막 활동이 메시지면 접은 본문, 찌르기면 "○○님이 콕 찔렀어요".
    package let previewText: String
    /// 마지막 활동이 내 것인가(바닥 따라가기·보이스오버).
    package let lastIsMine: Bool
    /// 미리보기가 **찌르기 문구**인가. 그 문구는 주어("내가" · "○○님이")를 이미 말하므로 보이스오버에 "나: "를 덧붙이지 않는다.
    package let previewIsPoke: Bool
    /// 줄 오른쪽 위 시각("13:58" · "어제").
    package let timeText: String
    /// 굵게 · 위로 올리는 기준 = 안 읽은 메시지 ∪ 안 본 찌르기.
    package let isUnread: Bool
    /// 개수 배지. **메시지** 안 읽음에만 선다(찌르기뿐이면 nil — 인수인계 §6-4).
    package let countBadge: String?
    /// 정렬 무리(근무를 알면 0…3, 모르면 0…1).
    package let group: Int

    package init(
        thread: MessageThread, pokes: [MessagePokeLogEntry], lastActivityAt: Date, previewText: String,
        lastIsMine: Bool, previewIsPoke: Bool, timeText: String, isUnread: Bool, countBadge: String?, group: Int
    ) {
        self.thread = thread
        self.pokes = pokes
        self.lastActivityAt = lastActivityAt
        self.previewText = previewText
        self.lastIsMine = lastIsMine
        self.previewIsPoke = previewIsPoke
        self.timeText = timeText
        self.isUnread = isUnread
        self.countBadge = countBadge
        self.group = group
    }

    /// 보이스오버에서 미리보기 앞에 "나: " 를 붙이는가(**메시지일 때만**).
    package var previewNeedsMinePrefix: Bool { lastIsMine && !previewIsPoke }

    package var id: String { thread.peerUserID }
    package var peerUserID: String { thread.peerUserID }
    package var peerName: String { thread.peerName }
    package var peerAvatarURL: URL? { thread.peerAvatarURL }
}

package enum MessagesThreadListRules {
    /// 보이스오버에서 개수 배지 자리에 들어가는 말(안 읽음이 **찌르기뿐**일 때).
    package static let unseenPokeAccessibilityLabel = "안 본 찌르기"

    /// 대화 목록 줄 전체 — 재료 모으기(스레드 ∪ 찌르기) → 표시값 → 4단 정렬. **화면이 지나는 유일한 자리**다.
    ///
    /// - `messageUnreadPeerIDs`: 안 읽은 **메시지**가 있는 상대(숫자 배지의 근거 — `MessagesStore.unreadPeerIDs`).
    /// - `pokeUnreadPeerIDs`: 안 **본** 찌르기가 있는 상대(코어 `MessagePokeLogRules.unreadPeerIDs` — 낙관 읽음을 뺀 값).
    /// - `chronology`: 서버 시각 순위(같은 초의 메시지·찌르기 선후). 대화 화면과 **같은 표**를 쓴다.
    package static func rows(
        threads: [MessageThread],
        pokes: [MessagePokeLogEntry],
        chronology: [String: Int],
        messageUnreadPeerIDs: Set<String>,
        pokeUnreadPeerIDs: Set<String>,
        unreadCounts: [String: Int],
        workingPeerIDs: Set<String>,
        workKnown: Bool,
        now: Date,
        calendar: Calendar = MobileRelativeTime.kst
    ) -> [MessagesThreadItem] {
        let unread = MessagesSortRules.combinedUnreadPeerIDs(messages: messageUnreadPeerIDs, pokes: pokeUnreadPeerIDs)
        let assembled = items(threads: threads, pokes: pokes, chronology: chronology, calendar: calendar)
        let decorated = assembled.map { item in
            let peer = item.peerUserID
            let isUnread = unread.contains(peer)
            return MessagesThreadItem(
                thread: item.thread,
                pokes: item.pokes,
                lastActivityAt: item.lastActivityAt,
                previewText: item.previewText,
                lastIsMine: item.lastIsMine,
                previewIsPoke: item.previewIsPoke,
                timeText: MessagesListRules.timeText(item.lastActivityAt, now: now, calendar: calendar),
                isUnread: isUnread,
                // ★ 숫자는 **메시지** 안 읽음에만(인수인계 §6-4 · 문서 §1 — 배지는 메시지만 센다).
                countBadge: messageUnreadPeerIDs.contains(peer)
                    ? MessagesListRules.countBadge(isUnread: true, count: unreadCounts[peer])
                    : nil,
                group: MessagesSortRules.rank(
                    isUnread: isUnread, isWorking: workingPeerIDs.contains(peer), workKnown: workKnown
                )
            )
        }
        return MessagesSortRules.sortedThreads(decorated)
    }

    /// 코어 대화 + 찌르기 기록 → 목록 줄 재료(표시값·정렬 전). `rows` 가 부른다 — 바깥에서는 쓰지 마라.
    ///
    /// 들어온 찌르기 배열의 순서를 믿지 않는다: 코어 `MessagePokeLogRules.sorted` 를 지나게 한다
    /// (묶음의 `last` 가 그 대화의 마지막 찌르기여야 미리보기·최근 시각이 맞는다).
    static func items(
        threads: [MessageThread],
        pokes: [MessagePokeLogEntry],
        chronology: [String: Int],
        calendar: Calendar
    ) -> [MessagesThreadItem] {
        func plain(_ thread: MessageThread) -> MessagesThreadItem {
            let last = thread.lastMessage
            return draft(
                thread: thread, pokes: [],
                lastActivityAt: last?.createdAt ?? .distantPast,
                previewText: last.map { MessagesListRules.preview($0.body) } ?? "",
                lastIsMine: last?.isMine ?? false
            )
        }
        guard !pokes.isEmpty else { return threads.map(plain) }
        let ordered = MessagePokeLogRules.sorted(pokes, chronology: chronology)
        var byPeer: [String: [MessagePokeLogEntry]] = [:]
        var pokeOnlyOrder: [String] = []
        for poke in ordered {
            byPeer[poke.peerUserID, default: []].append(poke)
        }
        var items = threads.map { thread in
            item(thread: thread, pokes: byPeer[thread.peerUserID] ?? [], chronology: chronology, calendar: calendar)
        }
        let known = Set(threads.map(\.peerUserID))
        for poke in ordered where !known.contains(poke.peerUserID) {
            if !pokeOnlyOrder.contains(poke.peerUserID) { pokeOnlyOrder.append(poke.peerUserID) }
        }
        for peer in pokeOnlyOrder {
            let own = byPeer[peer] ?? []
            // 이름·아바타는 **가장 최근 행의 것**이다(코어 `MessageThreadBuilder.threads` 와 같은 규약 — 별명을 바꾼
            // 사람의 옛 행이 목록에 옛 이름을 남기면 같은 사람이 두 사람으로 읽힌다).
            guard let latest = own.last else { continue }
            let thread = MessageThread(
                peerUserID: peer, peerName: latest.peerName, peerAvatarURL: latest.peerAvatarURL, messages: []
            )
            items.append(item(thread: thread, pokes: own, chronology: chronology, calendar: calendar))
        }
        return items
    }

    private static func item(
        thread: MessageThread, pokes: [MessagePokeLogEntry], chronology: [String: Int], calendar: Calendar
    ) -> MessagesThreadItem {
        let lastMessage = thread.lastMessage
        let lastPoke = pokes.last
        guard let anchor = lastMessage?.createdAt ?? lastPoke?.createdAt else {
            return draft(thread: thread, pokes: pokes, lastActivityAt: .distantPast, previewText: "", lastIsMine: false)
        }
        // ★ "둘 중 어느 쪽이 더 최근인가"를 **코어 병합 규칙에 물어본다**(두 줄짜리 타임라인을 세워 마지막 줄을 본다).
        //   같은 초의 선후 규칙(서버 순위 → 모르면 메시지가 먼저)을 여기서 다시 적으면 대화 화면과 갈리는 날이 온다.
        let lines = MessageConversationTimeline.lines(
            messages: [lastMessage].compactMap { $0 },
            pokes: [lastPoke].compactMap { $0 },
            chronology: chronology,
            now: anchor,
            calendar: calendar
        )
        switch lines.last {
        case .poke(let entry):
            return draft(
                thread: thread, pokes: pokes, lastActivityAt: entry.createdAt,
                previewText: MessagesSortRules.pokePreview(entry, calendar: calendar),
                lastIsMine: entry.isMine, previewIsPoke: true
            )
        case .bubble(let entry):
            return draft(
                thread: thread, pokes: pokes, lastActivityAt: entry.createdAt,
                previewText: MessagesListRules.preview(entry.body), lastIsMine: entry.isMine, previewIsPoke: false
            )
        default:
            return draft(thread: thread, pokes: pokes, lastActivityAt: anchor, previewText: "", lastIsMine: false)
        }
    }

    /// 표시값이 아직 안 정해진 줄(정렬·배지는 `rows` 가 채운다).
    private static func draft(
        thread: MessageThread, pokes: [MessagePokeLogEntry], lastActivityAt: Date, previewText: String,
        lastIsMine: Bool, previewIsPoke: Bool = false
    ) -> MessagesThreadItem {
        MessagesThreadItem(
            thread: thread, pokes: pokes, lastActivityAt: lastActivityAt, previewText: previewText,
            lastIsMine: lastIsMine, previewIsPoke: previewIsPoke,
            timeText: "", isUnread: false, countBadge: nil, group: 0
        )
    }

    /// 목록 줄 보이스오버. 안 읽음이 **찌르기뿐**이면 "안 읽은 메시지"라고 말하지 않는다(인수인계 §6-4).
    package static func accessibilityText(row: MessagesThreadItem, presenceLine: String?) -> String {
        var parts = [row.peerName]
        if let presenceLine { parts.append(presenceLine) }
        if let countBadge = row.countBadge {
            parts.append("안 읽은 메시지 \(countBadge)개")
        } else if row.isUnread {
            parts.append(unseenPokeAccessibilityLabel)
        }
        parts.append((row.previewNeedsMinePrefix ? "나: " : "") + row.previewText)
        parts.append(row.timeText)
        return parts.joined(separator: ", ")
    }
}

package enum MessagesSortRules {
    /// 정렬이 쓰는 안 읽음 = **안 읽은 메시지 ∪ 안 본 찌르기**.
    ///
    /// ★ 이 집합을 "안 읽은 메시지 N" 한 줄(`MessagesListRules.subtitle`)·탭 배지·줄 개수 배지에 **먹이지 마라.**
    ///   그 수는 메시지 전용이다(`message_unread_summary`). 안 읽음이 찌르기뿐인 사람에게 "안 읽은 메시지 1"이라고
    ///   말하면 거짓말이다(인수인계 §6-4).
    package static func combinedUnreadPeerIDs(messages: Set<String>, pokes: Set<String>) -> Set<String> {
        pokes.isEmpty ? messages : messages.union(pokes)
    }

    /// 근무 중으로 치는 상태. **`.pending`(앰버 점 · 연결 끊김)도 근무중이다** — 두 세션 합의(인수인계 §1).
    package static func isWorking(_ presence: MessagesPeerPresence?) -> Bool {
        switch presence?.status {
        case .working, .pending: return true
        case .off, nil: return false
        }
    }

    /// 판에서 근무 중인 사람들.
    package static func workingPeerIDs(_ board: MessagesPresenceBoard) -> Set<String> {
        guard board.isKnown else { return [] }
        var ids: Set<String> = []
        for (id, presence) in board.peers where isWorking(presence) { ids.insert(id) }
        return ids
    }

    /// 무리 번호(작을수록 위). 근무 여부를 **모르는 동안**(`workKnown == false` — 팀·사람 목록을 한 번도 못 받은 창)에는
    /// 근무 축을 아예 쓰지 않는다: 안 읽음만으로 두 무리다. 모르면서 "근무 안 함"으로 접으면 근무 중인 사람이
    /// 아래로 내려갔다가 목록이 도착하는 순간 위로 튄다.
    package static func rank(isUnread: Bool, isWorking: Bool, workKnown: Bool) -> Int {
        guard workKnown else { return isUnread ? 0 : 2 }
        if isUnread { return isWorking ? 0 : 1 }
        return isWorking ? 2 : 3
    }

    /// 대화 목록 4단 정렬. 무리(`item.group` — `rank` 가 정한 값)가 먼저, 같은 무리 안은 **최근순**(찌르기를 포함한
    /// 마지막 활동), 동점은 id 로 깬다(결정성 — `sorted` 는 안정 정렬이 아니라서 안 깨면 새로고침마다 두 줄이 자리를 바꾼다).
    package static func sortedThreads(_ items: [MessagesThreadItem]) -> [MessagesThreadItem] {
        items.sorted { lhs, rhs in
            if lhs.group != rhs.group { return lhs.group < rhs.group }
            if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt > rhs.lastActivityAt }
            return lhs.peerUserID < rhs.peerUserID
        }
    }

    /// 목록 미리보기용 찌르기 한 줄 — 대화 줄과 **같은 문구**에서 시각 꼬리만 뗀다(목록은 시각을 오른쪽 위에 따로 그린다).
    /// 코어에 시각 없는 문구가 없어 `MessagePokeLogText.line` 에서 `clockText` 꼬리를 떼는 것으로 한 벌을 지킨다 —
    /// "콕 찔렀어요"를 여기 다시 적으면 맥이 말을 바꾸는 날 폰만 옛말을 한다.
    package static func pokePreview(_ entry: MessagePokeLogEntry, calendar: Calendar = MobileRelativeTime.kst) -> String {
        let full = MessagePokeLogText.line(for: entry, calendar: calendar)
        let tail = " · " + MessageThreadBuilder.clockText(entry.createdAt, calendar: calendar)
        return full.hasSuffix(tail) ? String(full.dropLast(tail.count)) : full
    }
}

// MARK: - 목록 · 라우트

/// 메시지 탭 내비게이션 경로의 원소(탭이 정한다 — 라우터는 모른다).
package enum MessagesDestination: Hashable, Sendable {
    case conversation(peerID: String)
}

package enum MessagesListRules {
    /// 목록 한 줄 미리보기: 줄바꿈·연속 공백을 한 칸으로 접는다(한 줄에 첫 줄만 남으면 "안녕\n…" 이 "안녕" 으로 읽힌다).
    ///
    /// 아잉이 이모티콘(1.0.12)을 **먼저** 거친다 — 목록은 그림을 그릴 수 없는 자리라 `[아잉:기쁨]` 이 날것으로
    /// 나오면 "깨진 메시지"로 읽힌다(`AingStickerText.preview` 머리말). 이모티콘이 아니면 그 함수가 원문을
    /// 그대로 돌려주므로 아래 접기는 **지금과 한 글자도 다르지 않다**.
    ///
    /// ⚠️ **순서가 거꾸로면 안 된다.** 판정(`AingSticker.parse`)은 `MessageBody.sanitized` 를 거친 **원문**을
    ///    봐야 한다 — 접힌 글자를 넘기면 공백·줄바꿈이 섞인 본문이 판정 앞에서 이미 달라져 있다. 토큰 안에는
    ///    공백이 없어 지금은 값이 같지만, 값이 같다는 사실로 순서를 정하면 다음 토큰이 그 사실을 깬다.
    package static func preview(_ body: String) -> String {
        AingStickerText.preview(for: body)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// 목록 줄 오른쪽 위 시각(시안 B 03): 오늘이면 "13:58"(24시간제 — 대화 말풍선 곁 시각과 같은 글자), 아니면 "어제"·"9월 8일".
    /// 상대 시각("6분 전")을 쓰지 않는 이유: 대화 화면의 시각과 같은 눈금이어야 줄과 말풍선을 맞춰 읽는다. 보관 창이 24시간이라 "어제"까지만 나온다.
    package static func timeText(_ date: Date, now: Date, calendar: Calendar = MobileRelativeTime.kst) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return MessageThreadBuilder.clockText(date, calendar: calendar)
        }
        return MessageThreadBuilder.dayLabel(date, now: now, calendar: calendar)
    }

    /// 큰 제목 아래 한 줄("안 읽은 메시지 3"). 0 이면 nil(한 줄을 비운다 — "0" 을 세우지 않는다).
    package static func subtitle(unreadCount: Int) -> String? {
        unreadCount > 0 ? "안 읽은 메시지 \(unreadCount)" : nil
    }

    /// 목록 줄 개수 배지. 점 집합(`unreadPeerIDs`)에 있으면 최소 1(요약이 개수 0 행을 보낸 경우) · 없으면 nil · 100 부터 "99+".
    package static func countBadge(isUnread: Bool, count: Int?) -> String? {
        guard isUnread else { return nil }
        let value = max(count ?? 0, 1)
        return value > 99 ? "99+" : "\(value)"
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

/// 대화 화면 한 줄(코어 `MessageConversationTimeline.lines` 위에 폰의 모양 결정을 얹은 것 — 뷰가 조건을 다시 세지 않는다).
package enum MessagesConversationItem: Identifiable, Equatable {
    case day(key: String, label: String)
    case bubble(MessagesBubbleLine)
    /// 찌르기 기록 줄(1.0.13) — **말풍선이 아니다.** 답장·읽음 표시·복사·신고 대상이 아니다.
    case poke(MessagesPokeLogLine)
    case pending(MessagesPendingOutgoing)

    package var id: String {
        switch self {
        case .day(let key, _): return "day-\(key)"
        case .bubble(let line): return line.entry.id
        case .poke(let line): return line.id
        case .pending(let item): return "pending-\(item.id)"
        }
    }

    /// 바닥 따라가기의 "마지막 줄이 내 것인가"(자리 말풍선은 언제나 내 것).
    package var isMine: Bool {
        switch self {
        case .day: return false
        case .bubble(let line): return line.entry.isMine
        case .poke(let line): return line.entry.isMine
        case .pending: return true
        }
    }
}

/// 대화창 찌르기 줄 하나(그릴 값만 — 뷰는 조건을 다시 세지 않는다). 모양은 `MessagesPokeLogRow`(iOS)다.
///
/// 글자·아이콘은 전부 코어(`MessagePokeLogText`)가 쥐고 있다 — 맥과 한 벌이다.
package struct MessagesPokeLogLine: Identifiable, Equatable {
    package let entry: MessagePokeLogEntry
    /// 줄 글자 전체("한결님이 콕 찔렀어요 · 15:12") — 코어 `MessagePokeLogText.line`.
    package let text: String
    /// 아이콘(콕 손가락 · 울트라 번개) — 코어 `MessagePokeLogText.symbol`.
    package let symbol: String

    package init(entry: MessagePokeLogEntry, text: String, symbol: String) {
        self.entry = entry
        self.text = text
        self.symbol = symbol
    }

    /// 말풍선 id 와 겹치면 `ForEach` 가 두 줄을 한 줄로 묶는다.
    package var id: String { "poke-\(entry.id)" }
}

package struct MessagesBubbleLine: Equatable {
    package let entry: MessageHistoryEntry
    /// "14:05"(KST 24시간제).
    package let clockText: String
    /// 시각을 이 말풍선 옆에 찍는가 — 같은 쪽·같은 분의 다음 말풍선이 이어지면 마지막 것에만 찍는다.
    package let showsTime: Bool
    /// 말한 쪽이 바뀐 첫 말풍선(앞 줄이 **다른 쪽 말풍선**) — 화면은 그 위를 조금 더 띄운다(시안 B 04 `.b-gap`).
    /// 날짜 구분선 바로 뒤·대화 첫 줄은 false(구분선·안내가 이미 띄운다).
    /// 폰 1:1 대화는 받은 말풍선 옆에 상대 아바타를 두지 않는다 — 머리가 이미 상대를 말한다(시안 B 04).
    package let startsGroup: Bool
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

    /// 찌르기 줄 한 줄(글자·아이콘은 코어). 달력을 **반드시 넘긴다** — 코어 기본값은 `.current` 인데 폰 메시지 화면의
    /// 눈금은 KST(`MobileRelativeTime.kst`)다. 안 넘기면 기기 표준시가 다른 사람에게만 날짜 줄·시각이 말풍선과 갈린다.
    package static func pokeLine(
        for entry: MessagePokeLogEntry, calendar: Calendar = MobileRelativeTime.kst
    ) -> MessagesPokeLogLine {
        MessagesPokeLogLine(
            entry: entry,
            text: MessagePokeLogText.line(for: entry, calendar: calendar),
            symbol: MessagePokeLogText.symbol(entry.kind)
        )
    }

    /// 시간순 이력(한 사람) + 그 사람과 오간 **찌르기** + 보내는 중 자리 말풍선 → 화면 줄.
    ///
    /// 끼워 넣기·날짜 줄은 코어(`MessageConversationTimeline.lines`)가 한다. 그 병합은 두 수열이 **이미 시간순**이라고
    /// 전제하는 안정 병합이라 찌르기를 `MessagePokeLogRules.sorted` 에 먼저 통과시킨다.
    /// 찌르기가 없으면 결과는 `MessageThreadBuilder.timeline` 을 쓰던 예전과 줄 단위로 같다.
    package static func items(
        messages: [MessageHistoryEntry],
        pokes: [MessagePokeLogEntry],
        chronology: [String: Int],
        pending: [MessagesPendingOutgoing],
        receiptsAvailable: Bool,
        now: Date,
        calendar: Calendar = MobileRelativeTime.kst
    ) -> [MessagesConversationItem] {
        let timeline = MessageConversationTimeline.lines(
            messages: messages,
            pokes: MessagePokeLogRules.sorted(pokes, chronology: chronology),
            chronology: chronology,
            now: now,
            calendar: calendar
        )
        func bubbleEntry(_ line: MessageConversationLine) -> MessageHistoryEntry? {
            if case .bubble(let entry) = line { return entry }
            return nil
        }
        var items: [MessagesConversationItem] = []
        for (index, item) in timeline.enumerated() {
            switch item {
            case .day(let key, let label):
                items.append(.day(key: key, label: label))
            case .poke(let entry):
                items.append(.poke(pokeLine(for: entry, calendar: calendar)))
            case .bubble(let entry):
                let clock = MessageThreadBuilder.clockText(entry.createdAt, calendar: calendar)
                // 앞뒤로 **말풍선이 아닌 줄**(날짜 · 찌르기)이 끼면 묶음이 끊긴다 — 찌르기 줄이 사이에 서면
                // 같은 분의 앞 말풍선에도 시각이 찍히고, 찌르기 뒤 첫 말풍선은 추가 틈을 두지 않는다(줄이 이미 띄운다).
                let previous: MessageHistoryEntry? = index > 0 ? bubbleEntry(timeline[index - 1]) : nil
                let next: MessageHistoryEntry? = index + 1 < timeline.count ? bubbleEntry(timeline[index + 1]) : nil
                let continuesToNext = next.map {
                    $0.isMine == entry.isMine && MessageThreadBuilder.clockText($0.createdAt, calendar: calendar) == clock
                } ?? false
                items.append(.bubble(MessagesBubbleLine(
                    entry: entry,
                    clockText: clock,
                    showsTime: !continuesToNext,
                    startsGroup: previous.map { $0.isMine != entry.isMine } ?? false,
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
            return MessagesEmptyState(symbol: "exclamationmark.triangle", title: "대화를 불러오지 못했어요", hint: MobileLoadText.checkConnection, showsRetry: true)
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

extension MessagesConversationRules {
    /// 대화 머리(제목 · 아바타 · 보이스오버). **이름을 모르면 사람처럼 꾸미지 않는다** — 예전에는 "대화"라는 글자를 이름 자리에 넣어
    /// "대" 이니셜 원 + "대화"가 사람처럼 섰다(오프라인에서 푸시·딥링크로 대화를 열어 이력·사람 찾기가 모두 실패한 경우 · messages-verify).
    ///
    /// - 이름을 안다: 제목 = 이름, 이니셜 아바타, 보이스오버 = 이름.
    /// - 모른다: 제목 "대화", 아바타 대신 일반 인물 아이콘(`avatarName == nil`), 보이스오버는 아직 받는 중인지 · 못 받았는지를 말한다.
    package static func header(peerName: String?, isResolving: Bool) -> MessagesConversationHeader {
        if let name = peerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return MessagesConversationHeader(title: name, avatarName: name, accessibilityLabel: name)
        }
        return MessagesConversationHeader(
            title: MessagesConversationHeader.fallbackTitle,
            avatarName: nil,
            accessibilityLabel: isResolving
                ? MessagesConversationHeader.resolvingAccessibilityLabel
                : MessagesConversationHeader.unknownAccessibilityLabel
        )
    }
}

package struct MessagesConversationHeader: Equatable, Sendable {
    package static let fallbackTitle = "대화"
    package static let resolvingAccessibilityLabel = "대화 상대를 불러오는 중"
    package static let unknownAccessibilityLabel = "이름을 불러오지 못한 대화"
    /// 일반 인물 아이콘(SF Symbol) — 이름을 모를 때 이니셜 원 대신.
    package static let unknownAvatarSymbol = "person.crop.circle"

    package let title: String
    /// 이니셜 아바타에 넘길 이름. nil = 이름을 모른다 → 일반 인물 아이콘(가짜 이니셜 금지).
    package let avatarName: String?
    package let accessibilityLabel: String
}

// MARK: - 사람들의 근무 여부 · 센터

/// 한 사람의 근무 여부와 센터(목록 줄 아바타 점 · 이름 뒤 센터 배지 · 대화 머리 한 줄).
package struct MessagesPeerPresence: Equatable, Sendable {
    /// `.working` 초록 점 · `.pending` 앰버 점(연결 끊김 — 우리 팀만 안다) · `.off` 점 없음.
    package let status: PresenceStatus
    /// 센터 **서버값**("seoul") — 글자로 바꾸는 곳은 `CenterBadge`/`CenterLabel` 하나다.
    package let center: String?

    package init(status: PresenceStatus, center: String?) {
        self.status = status
        self.center = center
    }
}

/// "지금 근무 중 · 바로 말 걸기" 줄의 한 사람.
package struct MessagesWorkingPerson: Identifiable, Equatable, Sendable {
    package let id: String
    package let name: String
    package let avatarURL: URL?
    /// `.working` 또는 `.pending`.
    package let status: PresenceStatus
    package let center: String?

    package init(id: String, name: String, avatarURL: URL?, status: PresenceStatus, center: String?) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.status = status
        self.center = center
    }
}

/// 메시지 탭이 그리는 사람들의 근무 판.
package struct MessagesPresenceBoard: Equatable, Sendable {
    package static let unknown = MessagesPresenceBoard(isKnown: false, peers: [:], working: [])

    /// 근무 여부를 한 번이라도 받았는가. false 면 점·"지금 근무 중" 줄을 그리지 않는다(모르면서 "아무도 없어요"라고 하지 않는다).
    package let isKnown: Bool
    package let peers: [String: MessagesPeerPresence]
    /// 근무 중(나 제외) — 우리 팀(오래 일한 순) 먼저, 그다음 이름순.
    package let working: [MessagesWorkingPerson]
    /// 사람별 상태메시지(v0.3.51 · 이미 `StatusMessage.display` 를 지난 값, 없는 사람은 키가 없다).
    ///
    /// **`peers` 와 따로 둔 이유**: `board()` 는 근무 판정을 네 자리에서 다시 만든다(목록 → 지금 탭 목록 → 우리 팀 → 지금 근무 중).
    /// 상태를 `MessagesPeerPresence` 에 넣으면 그 네 자리를 하나라도 빠뜨리는 순간 그 경로의 사람만 상태가 조용히 사라진다.
    /// 상태의 출처는 사람 목록 둘(`app_user_directory`)뿐이라 여기서 한 번만 겹친다.
    package let statuses: [String: String]

    package init(isKnown: Bool, peers: [String: MessagesPeerPresence], working: [MessagesWorkingPerson], statuses: [String: String] = [:]) {
        self.isKnown = isKnown
        self.peers = peers
        self.working = working
        self.statuses = statuses
    }
}

package enum MessagesPresenceRules {
    /// 지금 탭이 가른 근무 중 한 사람(`NowStore.workingPeople(now:)` 의 필요한 칸만 — 메시지 규칙이 지금 탭 모델에 묶이지 않게).
    package struct Working: Equatable, Sendable {
        package let id: String
        package let name: String
        package let avatarURL: URL?
        package let center: String?
        package let isStale: Bool

        package init(id: String, name: String, avatarURL: URL?, center: String?, isStale: Bool) {
            self.id = id
            self.name = name
            self.avatarURL = avatarURL
            self.center = center
            self.isStale = isStale
        }
    }

    /// 판 만들기. **새 서버 호출이 없다** — 이미 받아 둔 값만 겹친다(뒤가 앞을 덮는다):
    ///  1. `messagesDirectory` — 새 대화 시트가 받은 사람 목록(센터는 화면 글자라 서버값으로 되돌린다). nil = 못 받음.
    ///  2. `nowDirectory` — 지금 탭이 1분마다 받는 같은 목록(서버값 그대로). nil = 못 받음.
    ///  3. `teamMemberIDs` + `nowWorking` — 지금 탭이 받은 **우리 팀 상태**(가장 정확 · 연결 끊김까지 안다). 우리 팀원은 이 판정이 목록을 이긴다
    ///     (지금 탭 "지금 근무 중"과 같은 사람이 초록이게). 팀 상태를 아직 못 받았으면 `teamMemberIDs` 는 빈 집합.
    /// 나(`me`)는 판에 넣지 않는다.
    package static func board(
        nowWorking: [Working],
        teamMemberIDs: Set<String>,
        nowDirectory: [PokeDirectoryRow]?,
        messagesDirectory: [PokeDirectoryEntry]?,
        me: String?
    ) -> MessagesPresenceBoard {
        let isKnown = nowDirectory != nil || messagesDirectory != nil || !teamMemberIDs.isEmpty
        guard isKnown else { return .unknown }
        var peers: [String: MessagesPeerPresence] = [:]
        var names: [String: (name: String, avatarURL: URL?)] = [:]
        for entry in messagesDirectory ?? [] where entry.userID != me {
            peers[entry.userID] = MessagesPeerPresence(
                status: entry.isWorking ? .working : .off,
                center: CenterLabel.serverValue(forDisplay: entry.center)
            )
            names[entry.userID] = (entry.name, entry.avatarURL)
        }
        for row in nowDirectory ?? [] where row.userId != me {
            peers[row.userId] = MessagesPeerPresence(status: row.isWorking ? .working : .off, center: row.center ?? peers[row.userId]?.center)
            names[row.userId] = (row.displayName, row.avatarUrl.flatMap(URL.init(string:)) ?? names[row.userId]?.avatarURL)
        }
        for id in teamMemberIDs where id != me {
            if let current = peers[id] {
                peers[id] = MessagesPeerPresence(status: .off, center: current.center)
            }
        }
        var working: [MessagesWorkingPerson] = []
        var seen: Set<String> = []
        for person in nowWorking where person.id != me && seen.insert(person.id).inserted {
            let status: PresenceStatus = person.isStale ? .pending : .working
            let center = person.center ?? peers[person.id]?.center
            peers[person.id] = MessagesPeerPresence(status: status, center: center)
            working.append(MessagesWorkingPerson(
                id: person.id, name: person.name, avatarURL: person.avatarURL ?? names[person.id]?.avatarURL,
                status: status, center: center
            ))
        }
        let others = peers
            .filter { id, presence in presence.status == .working && !seen.contains(id) }
            .map { id, presence in
                MessagesWorkingPerson(id: id, name: names[id]?.name ?? "", avatarURL: names[id]?.avatarURL, status: .working, center: presence.center)
            }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
        return MessagesPresenceBoard(isKnown: true, peers: peers, working: working + others,
                                     statuses: statuses(nowDirectory: nowDirectory, messagesDirectory: messagesDirectory, me: me))
    }

    /// 상태메시지 겹치기 — 판과 같은 순서(뒤가 앞을 덮는다): 새 대화 시트 목록 → 지금 탭 목록(1분마다 받는 더 새 값).
    /// **목록에 있는 사람은 그 목록의 값이 답이다**: 뒤 목록에 그 사람이 있고 상태가 없으면 앞 목록의 옛 상태를 지운다(방금 지운 상태가
    /// 남아 보이지 않게). 나(`me`)는 넣지 않는다.
    package static func statuses(
        nowDirectory: [PokeDirectoryRow]?,
        messagesDirectory: [PokeDirectoryEntry]?,
        me: String?
    ) -> [String: String] {
        var result: [String: String] = [:]
        for entry in messagesDirectory ?? [] where entry.userID != me {
            result[entry.userID] = entry.statusMessage
        }
        for row in nowDirectory ?? [] where row.userId != me {
            result[row.userId] = StatusMessage.display(row.statusMessage)
        }
        return result
    }

    /// 대화 머리 이름 아래 한 줄("근무 중 · 서울" · "연결 끊김" · "근무 안 함 · 부산"). 근무 여부를 모르면 nil(센터만 있어도 세우지 않는다 — 머리는 이름만).
    package static func headerLine(_ presence: MessagesPeerPresence?) -> String? {
        guard let presence else { return nil }
        let state: String
        switch presence.status {
        case .working: state = "근무 중"
        case .pending: state = "연결 끊김"
        case .off: state = "근무 안 함"
        }
        guard let center = CenterLabel.display(presence.center) else { return state }
        return "\(state) · \(center)"
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
    /// "새 메시지 ↓" 캡슐의 최소 높이(누르는 자리).
    package static let newMessageButtonMinHeight: Double = MessagesComposerRules.minimumTouchTarget

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
