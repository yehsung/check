import AppKit
import Foundation

// MARK: - 메시지 (v0.2.49) — 창 열고 닫기 · 12시간 이력 · 보내기
//
// 사용자 요청(2026-09-10, 네 번에 걸쳐 정정된 최종본):
//   "메시지 보낼 때 그 순간에 못 보면 내용을 못 보잖아. 메시지 버튼 눌렀을 때 메시지 창이 뜨고
//    거기서 이전 메시지들도 실제 메신저앱들처럼 시간과 함께 뜨게 해줘. 시간과 함께 주고받은 순서대로.
//    12시간 지나면 순차적으로 사라지게. 메시지랑 찌르기는 아예 분리야. 찌르기만 60초 쿨타임 있고
//    메시지는 쿨타임 없이 갈 거야. 진짜 메신저 앱처럼. 3글자 제한도 없애줘."
//
// ── 이 파일이 지키는 다섯 가지 ──
//
// ① **메시지에 쿨타임은 없다.** 서버 `send_message` 는 `cooldown` status 를 영원히 내지 않는다
//    (찌르기 `poke_user` 에는 남아 있다 — 두 규칙을 한 덩어리로 보지 마라). 그래서 이 파일 어디에도
//    쿨타임 미러·카운트다운·그것 때문에 잠기는 버튼이 없다. 되살리면 그게 곧 요구의 정반대다.
//
// ② **수신 거부 수단은 `target_focused` 하나뿐이다.** 쿨타임이 사라진 자리를 그것이 대신한다.
//    `.invalid` 로 접지 마라 — 접는 순간 "왜 안 가는지"를 말할 수 있는 유일한 문장이 사라진다.
//
// ③ **`flood` 를 속도 제한 UI 로 그리지 마라.** 1분 60건은 사람이 못 내는 속도라 실사용에서 안 걸린다.
//    걸리면 조용한 일반 안내로 접는다 — 거기에 카운트다운을 만들면 그건 다시 쿨타임이다.
//
// ④ **폴링을 새로 만들지 않는다.** 이력은 창 열기 · [새로고침] · 전송 성공 · **수신 폴링이 새 메시지를
//    물어왔을 때**만 받는다. 마지막 것이 "창을 열어 둔 채로 오면 그 자리에서 나타난다"의 근거이고,
//    이미 도는 15초 폴링에 얹혀 있다(`WorkTimerStorePoke.enqueueReceivedMessages`).
//
// ⑤ **이 화면이 나르는 것은 사람이 쓴 문장이다.** 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라.
//    실패 문구도 본문이나 서버 예외 원문을 담지 않는다.
//
// 비동기 관용구는 `performLoadMiniGameBoard`/`WorkTimerStoreFeedback` 을 그대로 따른다:
// 세션 가드 → 세대 캡처 → `withSessionRetry` → 세대 가드, 스키마 부재는 조용히 접기.
// 세대 가드가 없으면 로그아웃 뒤 도착한 응답이 다음 계정 화면에 **앞 사람의 대화**를 그린다.

@MainActor
extension WorkTimerStore {
    // MARK: 상수

    /// 이력 조회 창(시간). 서버가 1~24 로 접고, 화면의 "12시간이 지난 메시지는 사라져요" 한 줄이 이 값에서 나온다.
    /// 숫자를 문구에 직접 쓰지 마라 — 그러면 값을 바꾼 날 안내만 옛 숫자로 남는다.
    nonisolated static let messageHistoryHours = 12
    /// 한 번에 받아 올 이력 건수. 서버가 1~500 으로 접는다. 26명 규모에서 12시간 대화가 이 수를 넘기 어렵고,
    /// 넘으면 **오래된 쪽이 빠진다**(서버가 최신부터 자른다) — 그게 사라지는 규칙과 같은 방향이라 어색하지 않다.
    nonisolated static let messageHistoryLimit = 200

    // MARK: 안내 문구 (서버 status 아홉 개의 사람 말 번역)
    //
    // **전송 결과를 쓰는 곳은 `messageNotice` 하나뿐**이므로 문구도 여기 산다 — 뷰가 자기 표를 따로 들면
    // 그중 한 벌은 반드시 낡는다(ultraSpentNotice 를 상수에서 파생시킨 것과 같은 규약).

    nonisolated static let messageSentNotice = "메시지를 보냈어요"
    nonisolated static let messageNotWorkingNotice = "근무 중일 때만 메시지를 보낼 수 있어요"
    /// 대상이 자리비움일 때. 찌르기의 인라인 문구("자리비움 상태에는 찌를 수 없어요")와 **같은 문장에 동사만 바꿨다** —
    /// 사정이 같으므로 설명도 같아야 하고(두 기능이 같은 일을 다르게 설명하면 사용자는 다른 일로 읽는다),
    /// 동사가 다른 이유는 그쪽 문장을 그대로 쓰면 메시지를 보내려던 사람에게 엉뚱한 동작을 안내하기 때문이다.
    nonisolated static let messageTargetNotWorkingNotice = "자리비움 상태에는 보낼 수 없어요"
    /// 대상이 집중 모드일 때. **쿨타임이 폐지된 지금 이것이 유일한 수신 거부 수단이다**(v0.2.49) —
    /// `.invalid` 로 접으면 "왜 안 가는지"를 말할 수 있는 문장이 앱에서 사라진다.
    /// 찌르기의 `targetFocusedNotice`("지금 집중 중이에요. 나중에 찔러 주세요")와 **동사만 다르다**.
    nonisolated static let messageTargetFocusedNotice = "지금 집중 중이에요. 나중에 보내 주세요"
    /// 서버가 텍스트 난간에 걸었을 때. **길이 문구와 합치면 안 된다** — 못 보내는 이유가 길이라고 읽으면
    /// 사용자는 글자를 줄이고, 줄여도 계속 막힌다(3글자 시절 이모지 안내가 갈라져 있던 것과 같은 근거).
    nonisolated static let messageNotTextNotice = "보낼 수 없는 글자가 섞여 있어요"
    /// 서버가 메시지 기능을 통째로 내려 둔 구간(점검·사고 대응). "다시 시도"를 말하지 않는다 —
    /// 우리가 올릴 때까지 안 풀리는 상태라, 재시도를 권하면 같은 실패를 반복하게 만든다(제보의 스키마 부재와 같은 판단).
    nonisolated static let messageBlackoutNotice = "지금은 메시지를 주고받을 수 없어요"
    /// 우리가 모르는 실패. **`flood` 도 여기로 접힌다**(위 머리 주석 ③) — 숫자도 카운트다운도 없는 한 문장이다.
    nonisolated static let messageInvalidNotice = "지금은 메시지를 보낼 수 없어요. 잠시 후 다시 시도해 주세요"

    /// 길이 초과 안내. 숫자는 **서버가 알려 준 값이 있으면 그것**을, 없으면 클라 상수를 쓴다 —
    /// 둘이 갈리는 날 사용자가 보는 숫자는 실제로 거절한 쪽의 것이어야 한다.
    /// 리터럴을 다시 쓰지 마라(상한을 바꿀 때 문구만 옛 숫자로 남는다).
    nonisolated static func messageTooLongNotice(maxLength: Int? = nil) -> String {
        "메시지는 \(maxLength ?? MessageBody.maxLength)자까지예요. 줄여서 보내 주세요"
    }

    /// 창 상단 한 줄. **사라지는 규칙을 모르면 사용자는 그것을 버그로 읽는다.**
    nonisolated static var messageExpiryNotice: String {
        "\(messageHistoryHours)시간이 지난 메시지는 사라져요"
    }

    // MARK: 파생값(창이 읽는 것)

    /// 대화 상대별로 묶은 목록(최근 대화순). **왕복을 늘리지 않는다** — `message_history` 한 번으로 받은 것을
    /// 클라에서 나눈다. 상대마다 조회하면 26명 규모에서 요청이 26배가 된다(무료 플랜).
    var messageThreads: [MessageThread] { MessageThreadBuilder.threads(from: messageHistory) }

    /// 지금 고른 대화(아무도 안 골랐거나 그 사람과의 대화가 사라졌으면 nil).
    var selectedMessageThread: MessageThread? {
        guard let selectedMessagePeerID else { return nil }
        return messageThreads.first { $0.peerUserID == selectedMessagePeerID }
    }

    /// 안 읽은 것이 있는 상대들. 기준은 **받은 것의 마지막 시각 > 내가 그 대화를 마지막으로 연 시각**이다.
    /// 내가 보낸 것은 세지 않는다 — 내 말에 점이 붙으면 그건 아무 정보도 아니다.
    var unreadMessagePeerIDs: Set<String> {
        var unread: Set<String> = []
        for thread in messageThreads {
            guard let lastIncoming = thread.messages.last(where: { !$0.isMine }) else { continue }
            let stamp = messageReadStamps[thread.peerUserID]
            if stamp == nil || lastIncoming.createdAt > stamp! { unread.insert(thread.peerUserID) }
        }
        return unread
    }

    /// 지금 입력칸에 있는 글의 길이(코드포인트 — 서버와 같은 눈금).
    var messageDraftLength: Int { MessageBody.length(messageDraft) }

    /// 지금 [보내기]를 누를 수 있는가.
    ///
    /// **쿨타임은 여기 없다**(위 머리 주석 ①). 판정은 셋뿐이다: 왕복 중이 아니고 · 상대를 골랐고 ·
    /// 본문이 서버 경계 안이다. 근무중 여부는 **여기서 보지 않는다** — 그건 서버가 `not_working` 으로
    /// 답하는 사정이고, 클라가 미리 잠그면 "왜 회색인지" 말할 자리가 없어진다(전송 시 안내가 말한다).
    var canSendMessageNow: Bool {
        guard !isSendingMessage, selectedMessagePeerID != nil else { return false }
        if case .ok = MessageBody.validate(messageDraft) { return true }
        return false
    }

    // MARK: 창 열고 닫기

    /// **이 기능의 공개 진입점.** 콕찌르기 패널의 말풍선 버튼·팝오버의 수신 줄·캐릭터의 도착 말풍선이
    /// 부르는 단 하나의 문이다(제보 창의 `openFeedbackWindow()` 와 같은 모양).
    ///
    /// - Parameter peer: 열자마자 고를 대화 상대. nil 이면 마지막 선택을 지키거나, 없으면 최근 대화를 고른다.
    ///
    /// **보내는 곳은 이 창 하나다**(v0.2.49). 옛 인라인 작성기(팝오버 안 3글자 칸)를 걷어낸 이유가 그것이다 —
    /// 보내는 곳이 둘이면 이력도 둘로 갈리고, 200자를 292pt 폭에서 쓰는 것은 애초에 무리다.
    ///
    /// 순서가 **창 먼저, 팝오버 나중**인 이유는 제보·게임 창과 같다: 이 메서드는 팝오버 안의 버튼이 부르므로
    /// 먼저 닫으면 자기를 그린 뷰 계층을 액션 도중에 걷어내고, 창이 먼저 키를 가져간 뒤 닫아야 포커스가 남는다.
    func openMessageWindow(peer: String? = nil) {
        if !isMessageWindowVisible { isMessageWindowVisible = true }
        if let peer, !peer.isEmpty {
            selectMessagePeer(peer)
        } else if selectedMessagePeerID == nil {
            // 아무도 안 골랐으면 최근 대화를 연다 — 빈 오른쪽 판으로 시작하면 사용자가 할 일이 한 번 더 는다.
            selectMessagePeer(messageThreads.first?.peerUserID)
        }
        // 첫 프레임부터 빈 자리에 "불러오는 중…"이 뜨게 한다(제보 목록과 같은 규약).
        // **세션이 있을 때만** 세운다 — 로그인 전이면 아래 로드가 세션 가드에서 조용히 되돌아가는데,
        // 그때 이 깃발을 세워 두면 아무도 내려 주지 않아 창이 영영 "불러오는 중…"에 갇힌다.
        if session != nil, !messageHistoryLoaded { messageHistoryLoading = true }
        loadMessageHistory()
        CheckMessageWindowController.shared.show()
        WindowTopAnchor.dismissMenuPopover()
    }

    /// 진입 버튼을 다시 눌렀을 때(열려 있으면 닫고, 아니면 연다). 같은 버튼이 토글로 읽히기 때문에 남긴다.
    func toggleMessageWindow() {
        if isMessageWindowVisible {
            closeMessageWindow()
            return
        }
        openMessageWindow()
    }

    /// 메시지 창을 닫는다(멱등). **초안은 지우지 않는다** — 쓰다 만 말이 창을 잘못 닫았다고 사라지면
    /// 사용자는 그 말을 다시 못 쓴다. 초안이 사라지는 자리는 전송 성공 하나뿐이다(제보 창과 같은 규약).
    /// 사용자가 타이틀바 빨간 점을 눌렀을 때는 컨트롤러의 `windowWillClose` 가 같은 값을 직접 맞춘다.
    func closeMessageWindow() {
        guard isMessageWindowVisible else { return }
        isMessageWindowVisible = false
        CheckMessageWindowController.shared.close()
    }

    /// 대화 상대를 고른다(왼쪽 목록의 행 · 진입점의 인자 · 전송 성공 뒤 자리 유지).
    ///
    /// 고르는 순간 **읽음으로 친다** — 대화를 열어 놓고도 점이 남아 있으면 그 점은 아무 뜻도 없는 장식이 된다.
    /// 초안은 상대를 바꿀 때 **비운다**: 앞사람에게 쓰던 말이 뒷사람 칸에 남아 나가면 그게 곧 사고다
    /// (3글자 시절 인라인 작성기가 지키던 규약 그대로다 — 200자가 된 지금 사고의 값만 커졌다).
    func selectMessagePeer(_ peerUserID: String?) {
        guard selectedMessagePeerID != peerUserID else {
            // 같은 사람을 다시 골라도 읽음 도장은 새로 찍는다(그 사이 새 말이 왔을 수 있다).
            if let peerUserID { messageReadStamps[peerUserID] = clock() }
            return
        }
        selectedMessagePeerID = peerUserID
        messageDraft = ""
        // 앞사람에게서 받은 전송 결과 문구도 함께 내린다 — 다른 대화 위에 남으면 무엇에 대한 말인지 알 수 없다.
        if messageNotice != nil { messageNotice = nil }
        if let peerUserID { messageReadStamps[peerUserID] = clock() }
    }

    // MARK: 이력

    /// 이력을 로드한다(Task 발사). **창 열기 · [새로고침] · 전송 성공 · 수신 도착에서만 부른다.**
    func loadMessageHistory() {
        Task { @MainActor in await performLoadMessageHistory() }
    }

    /// 수신 폴링이 새 메시지를 물어왔을 때의 갱신(`enqueueReceivedMessages` 가 부른다).
    ///
    /// **창이 닫혀 있으면 아무 요청도 내지 않는다.** 볼 사람이 없는 갱신에 무료 플랜의 왕복을 쓰지 않는다 —
    /// 이력은 창을 열 때 어차피 한 번 받는다. 이 게이트가 "폴링을 새로 만들지 않는다"는 규약의 실제 내용이다.
    func refreshMessageHistoryOnArrival() {
        guard isMessageWindowVisible, session != nil else { return }
        loadMessageHistory()
    }

    /// `message_history` 를 받아 반영한다.
    ///
    /// 서버는 오래된 것부터 준다고 약속하지만 **정렬을 다시 세운다** — 순서가 곧 사용자가 읽는 순서라
    /// 서버 정렬을 신뢰하지 않는 것이 이 저장소의 규약이다(sortedForPokeDisplay·제보 목록과 같은 근거).
    func performLoadMessageHistory() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        if !messageHistoryLoading { messageHistoryLoading = true }
        if messageHistoryFailed { messageHistoryFailed = false }
        defer { if generation == sessionGeneration, messageHistoryLoading { messageHistoryLoading = false } }
        do {
            let entries = try await withSessionRetry { activeSession in
                try await service.fetchMessageHistory(
                    accessToken: activeSession.accessToken,
                    hours: Self.messageHistoryHours,
                    limit: Self.messageHistoryLimit
                )
            }
            // 세대가 갈렸으면 이 응답은 앞 계정의 것이다 — 그대로 대입하면 새 계정 화면에 남의 대화가 그려진다.
            guard generation == sessionGeneration else { return }
            let sorted = entries.sortedForMessageHistory()
            if messageHistory != sorted { messageHistory = sorted }
            if !messageHistoryLoaded { messageHistoryLoaded = true }
            if messageHistoryFailed { messageHistoryFailed = false }
            // 고른 대화가 12시간 밖으로 나가 사라졌으면 선택을 놓는다 — 안 놓으면 오른쪽이 영영 빈 판이고
            // 사용자는 그것을 '대화가 지워졌다'가 아니라 '앱이 멈췄다'로 읽는다.
            if let selected = selectedMessagePeerID, !sorted.contains(where: { $0.peerUserID == selected }) {
                selectedMessagePeerID = nil
            } else if selectedMessagePeerID == nil {
                selectMessagePeer(MessageThreadBuilder.threads(from: sorted).first?.peerUserID)
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 마이그레이션 전 창(브루 배포가 db push 보다 앞선 경우): 실패가 아니라 '아직 함수가 없다'.
                // 빈 이력으로 조용히 접는다 — 실패 문구와 [다시 시도] 는 **사용자가 고칠 수 있는 일**에만 쓴다
                // (제보 목록이 세운 관례). 그 며칠 동안 모두가 빨간 화면을 보면 그건 우리 배포 순서의 값이다.
                if !messageHistoryLoaded { messageHistoryLoaded = true }
            } else if !messageHistoryFailed {
                messageHistoryFailed = true
            }
        }
    }

    // MARK: 보내기

    /// 창의 [보내기] 버튼(과 ⌘Enter)이 부르는 문. 판정은 `canSendMessageNow` 하나이고 여기서 다시 세지 않는다.
    func sendDraftMessage() {
        guard canSendMessageNow, let peer = selectedMessagePeerID else { return }
        sendMessage(to: peer, body: messageDraft)
    }

    /// 대상에게 메시지를 보낸다.
    ///
    /// **쿨타임 미러가 없다**(v0.2.49). 옛 구현은 성공할 때마다 60초 미러를 세우고 버튼을 잠갔는데,
    /// 서버가 그 규칙을 폐지했으므로 미러를 남기면 **아무도 갱신하지 않는 잠금**이 화면에 남는다.
    ///
    /// **집중 모드·근무 여부는 여기서 거르지 않는다.** 서버가 판정한다(target_focused / target_not_working).
    /// 클라가 자기 미러로 한 번 더 판정하면 두 판정이 언젠가 갈리고, 그때 화면은 서버가 허락한 전송을 막거나
    /// 막을 전송을 허락한다 — 사용자가 원인을 알 수 없는 종류의 버그다.
    /// 다만 **내가 근무중이 아닌 것만은** 선게이트로 막는다(sendPoke 와 같은 눈금 — startedAt): 확정으로
    /// 거절당할 요청을 무료 플랜에서 내보낼 이유가 없고, 그 판정의 재료는 서버가 아니라 이 앱이 갖고 있다.
    ///
    /// 빈 본문·200자 초과도 여기서 판정하지 않는다. `service.sendMessage` 가 MessageBody 로 사전 판정해
    /// **네트워크를 타지 않고** 서버와 같은 status 를 즉답하므로, 아래 switch 하나가 로컬 거절과 서버 거절을
    /// 같은 문구로 다룬다(같은 실패를 catch 와 switch 두 곳에서 다루면 그 둘은 반드시 갈린다).
    func sendMessage(to userID: String, body: String) {
        guard session != nil else { return }
        guard startedAt != nil else {
            messageNotice = Self.messageNotWorkingNotice
            return
        }
        // 왕복이 이미 떠 있으면 두 번째를 만들지 않는다. 문구도 건드리지 않는다 — 방금 누른 것의 결과가
        // 곧 도착하는데 여기서 다른 말을 쓰면 그 결과가 한 프레임 만에 덮인다.
        guard !isSendingMessage else { return }
        isSendingMessage = true
        let generation = sessionGeneration
        Task { @MainActor in
            // 세대가 바뀐 뒤(로그아웃/재로그인)의 잠금 해제는 새 세션의 잠금을 푸는 짓이 된다 —
            // 그쪽은 clearPersistedSession 이 이미 false 로 되돌려 놓았다.
            defer { if generation == sessionGeneration { isSendingMessage = false } }
            do {
                let response = try await withSessionRetry { activeSession in
                    try await service.sendMessage(accessToken: activeSession.accessToken, to: userID, body: body)
                }
                guard generation == sessionGeneration else { return }
                switch MessageSendOutcome(response: response) {
                case .ok:
                    messageNotice = Self.messageSentNotice
                    // 보낸 값을 비운다 — 남아 있으면 다음 Enter 에 같은 말이 또 나간다.
                    // **비우는 자리는 여기 하나뿐이다**: 창을 닫아도, 실패해도 글은 남는다.
                    if selectedMessagePeerID == userID { messageDraft = "" }
                    // 방금 보낸 말이 그 자리에서 대화에 나타나야 "메신저"다. 낙관 삽입 대신 이력을 다시 받는 이유는
                    // **서버가 본문을 정규화하고 시각을 정하기 때문**이다 — 내가 만든 가짜 행과 다음 갱신의 진짜 행이
                    // 다르면 말풍선이 순간 두 개로 보이거나 순서가 튄다(그 어긋남은 사용자에게 설명할 길이 없다).
                    loadMessageHistory()
                case .notWorking:
                    messageNotice = Self.messageNotWorkingNotice
                case .targetNotWorking:
                    // 대상 자리비움. 디렉토리의 '근무중' 배지가 낡았다는 뜻이므로 즉시 재조회한다 — 안 그러면
                    // 화면은 계속 "근무중"이라 말하는데 전송만 거절돼, 사용자는 왜 안 되는지 알 방법이 없다
                    // (sendPoke/sendUltraPoke 의 같은 분기와 같은 처리다).
                    messageNotice = Self.messageTargetNotWorkingNotice
                    loadPokeDirectory()
                case .targetFocused:
                    messageNotice = Self.messageTargetFocusedNotice
                case .tooLong:
                    // 서버가 숫자를 알려 줬으면 그 숫자를 말한다(클라 상수와 갈리는 날 진실은 거절한 쪽에 있다).
                    messageNotice = Self.messageTooLongNotice(maxLength: response.maxLength)
                case .notText:
                    messageNotice = Self.messageNotTextNotice
                case .blackout:
                    messageNotice = Self.messageBlackoutNotice
                case .flood, .invalid:
                    // ★ flood 를 여기 접어 두는 것이 계약이다(머리 주석 ③). 남은 초를 세거나 버튼을 잠그면
                    //   그건 이름만 다른 쿨타임이고, 사장님이 없애라고 한 바로 그것이다.
                    messageNotice = Self.messageInvalidNotice
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                // 마이그레이션 미적용 서버(404/PGRST202)도 여기로 떨어진다 — 메시지만 조용히 못 쓰고
                // 찌르기/울트라는 그대로 산다.
                messageNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
            }
        }
    }
}

// MARK: - 정렬

extension Array where Element == MessageHistoryEntry {
    /// 서버 정렬을 신뢰하지 않고 다시 세운다: **오래된 것 → 최신**, 같은 시각이면 id.
    /// 같은 시각 동점을 id 로 깨는 이유는 결정성이다 — 안 깨면 새로고침마다 두 말풍선의 순서가 뒤바뀐다.
    func sortedForMessageHistory() -> [MessageHistoryEntry] {
        sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - 대화 묶음 (순수)

/// 한 사람과의 대화. `message_history` 한 번으로 받은 것을 클라에서 묶은 결과다(왕복을 늘리지 않는다).
struct MessageThread: Identifiable, Equatable {
    let peerUserID: String
    let peerName: String
    let peerAvatarURL: URL?
    /// **시간순**(오래된 것 → 최신). 화면이 그대로 위에서 아래로 쌓는다.
    let messages: [MessageHistoryEntry]

    var id: String { peerUserID }
    /// 목록의 미리보기·정렬 기준이 되는 마지막 한 건.
    var lastMessage: MessageHistoryEntry? { messages.last }
}

/// 대화 화면 한 줄. 날짜 구분선이 **말풍선과 같은 배열에 사는 것**이 요점이다 —
/// 뷰가 그리는 도중에 "앞 항목과 날짜가 다른가"를 판정하면 그 판정은 테스트로 잴 수 없고,
/// 스크롤 재사용이 끼는 순간 구분선이 엉뚱한 자리에 남는다.
enum MessageTimelineItem: Identifiable, Equatable {
    /// 날짜 구분선("오늘" / "어제" / "9월 8일").
    case day(key: String, label: String)
    case bubble(MessageHistoryEntry)

    var id: String {
        switch self {
        case .day(let key, _): return "day-\(key)"
        case .bubble(let entry): return entry.id
        }
    }
}

/// 이력 → 화면 구조(순수). **스토어도 뷰도 자기 판을 만들지 않는다** — 묶기·정렬·구분선은 여기 한 곳이고,
/// 그래서 이 규칙 전부를 헤드리스로 잴 수 있다.
enum MessageThreadBuilder {
    /// 상대별로 묶는다. 각 대화는 시간순, 대화 목록은 **최근 대화순**(마지막 메시지가 새로운 쪽이 위).
    ///
    /// 상대 이름·아바타는 **가장 최근 행의 것**을 쓴다 — 별명을 바꾼 사람의 옛 행이 목록에 옛 이름을 남기면
    /// 사용자는 같은 사람을 두 사람으로 읽는다(서버가 행마다 그때의 표시명을 실어 줄 수 있다).
    static func threads(from entries: [MessageHistoryEntry]) -> [MessageThread] {
        var order: [String] = []
        var grouped: [String: [MessageHistoryEntry]] = [:]
        for entry in entries.sortedForMessageHistory() {
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
    static func timeline(
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
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// 구분선 문구. 12시간 창이라 실제로 나오는 것은 "오늘"과 "어제"뿐이지만, 자정을 낀 조회에서
    /// 날짜가 바뀌는 것을 사람이 읽을 수 있어야 해서 셋을 다 만든다(달력을 넘긴 값도 안전하게 떨어진다).
    static func dayLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
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
    static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 왼쪽 목록의 "마지막 시각" — 오늘 것은 시각(HH:mm), 그전 것은 날짜 라벨.
    /// 목록은 폭이 180pt 라 둘을 다 적을 자리가 없다. 12시간 창에서 갈리는 것은 자정뿐이다.
    static func listStampText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? clockText(date, calendar: calendar)
            : dayLabel(date, now: now, calendar: calendar)
    }

    /// 왼쪽 목록의 한 줄 미리보기. 줄바꿈을 공백으로 눕히고 앞뒤를 다듬는다 —
    /// **여러 줄 입력을 받는 창이라** 그대로 두면 미리보기가 첫 줄만 남고 나머지 폭이 빈다.
    static func previewText(_ body: String) -> String {
        body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
