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
// ④ **폴링을 새로 만들지 않는다.** 이력은 패널 열기 · 전송 성공 · **수신 폴링이 새 메시지를
//    물어왔을 때**만 받는다. 마지막 것이 "화면을 열어 둔 채로 오면 그 자리에서 나타난다"의 근거이고,
//    이미 도는 15초 폴링에 얹혀 있다(`WorkTimerStorePoke.enqueueReceivedMessages`).
//
// ⑤ **이 화면이 나르는 것은 사람이 쓴 문장이다.** 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라.
//    실패 문구도 본문이나 서버 예외 원문을 담지 않는다.
//
// 비동기 관용구는 `performLoadMiniGameBoard`/`WorkTimerStoreFeedback` 을 그대로 따른다:
// 세션 가드 → 세대 캡처 → `withSessionRetry` → 세대 가드, 스키마 부재는 조용히 접기.
// 세대 가드가 없으면 로그아웃 뒤 도착한 응답이 다음 계정 화면에 **앞 사람의 대화**를 그린다.
//
// ── v0.3.30 에서 바뀐 것 (모바일 1차 — 사용자 결정 2026-09-16) ──
//  · **근무 밖에서도 주고받는다.** 서버 send_message 가 not_working/target_not_working 을 지웠다. 그래서 보내기의
//    클라 선게이트(startedAt)도 걷었다 — 서버만 풀고 스토어가 막으면 초록인 채로 아무것도 안 바뀐다(두 겹 게이트).
//    ④의 "폴링을 새로 만들지 않는다"는 그대로다: 근무 밖 수신은 소켓 신호가 **요약 조회**로 받는다(take_pokes 아님).
//  · **보관 24시간.** 창 상단 안내는 상수에서 파생된다(messageHistoryHours).
//  · **읽음은 서버가 판정한다.** 이력은 `message_history_with_reads` 로 받고(없는 서버면 옛 `message_history` 로 접는다),
//    안 읽음 점은 서버 판정(이력·요약 중 더 나중에 띄운 쪽) − 낙관 읽음이다. 규칙은 순수 함수 `MessageUnreadRules` 한 곳.
//    읽음 처리는 **팝오버가 떠 있고 대화 패널이 보이고 그 상대가 골라져 있을 때만** 올린다 — 캐릭터 말풍선으로
//    본 것은 읽음이 아니다(말풍선을 눌러 대화가 열리면 그때 읽음).

@MainActor
extension WorkTimerStore {
    // MARK: 상수

    /// 이력 조회 창(시간). 서버가 1~24 로 접고, 화면의 "24시간이 지난 메시지는 사라져요" 한 줄이 이 값에서 나온다.
    /// 숫자를 문구에 직접 쓰지 마라 — 그러면 값을 바꾼 날 안내만 옛 숫자로 남는다.
    /// v0.3.30: 12 → 24(서버 message_retention_hours() 도 24 — 사용자 결정 2026-09-16). 서버 상한과 같은 값이라
    /// 이보다 키우면 서버가 조용히 24로 접고 안내만 거짓이 된다.
    nonisolated static let messageHistoryHours = 24
    /// 한 번에 받아 올 이력 건수. 서버가 1~500 으로 접는다. 26명 규모에서 하루 대화가 이 수를 넘기 어렵고,
    /// 넘으면 **오래된 쪽이 빠진다**(서버가 최신부터 자른다) — 그게 사라지는 규칙과 같은 방향이라 어색하지 않다.
    nonisolated static let messageHistoryLimit = 200
    /// 팝오버를 열 때 요약·이력을 다시 받는 최소 간격(초, v0.3.30). 여닫이마다 두 요청을 내면 무료 플랜 예산을 태운다 —
    /// 그 사이의 변화는 소켓 신호(초인종·읽음)가 메운다. 오목 받은 신청의 60초(GomokuStore.menuInboxThrottleSeconds)와 같은 눈금이다.
    nonisolated static let messageMenuRefreshThrottleSeconds: TimeInterval = 60
    /// 읽음 신호('message_read')와 읽음 처리 성공 뒤의 새로고침을 **한 번으로 모으는 창**(초, v0.3.30 m-fix2 · 부록 B-2).
    ///
    /// 서버는 경계가 커지면 보낸 사람 채널과 **읽은 사람 자신의 채널**에 신호를 보낸다(B-1). 그래서 폰에서 대화 몇 개를 연달아
    /// 읽으면 이 맥에 신호가 몰려 오고, 이 맥이 스스로 읽으면 성공 뒤 새로고침과 **자기 신호의 메아리**가 겹친다 — 창 하나에 모아
    /// 요약(과 보이는 대화의 이력) 한 번으로 갚는다. 1초인 이유: 점이 꺼지는 데 "몇 초 안"이면 충분하고, 메아리는 대개 그 안에 온다.
    ///
    /// ★ m-fix 의 **점이 켜져 있을 때 10초 스로틀**(`messageMenuRefreshUnreadThrottleSeconds`)은 m-fix2 에서 걷었다. 그 예외는
    ///   "다른 기기에서 읽어도 이 맥엔 신호가 없다"를 팝오버 열기로 메우던 것인데, 이제 그 신호가 온다. 남기면 안 읽은 말을 일부러
    ///   남겨 둔 사람이 팝오버를 열 때마다(10초 넘게 벌어지면) 요약·이력 두 건을 내고, 소켓이 끊겨 있던 틈은 조인 직후 따라잡기가
    ///   이미 요약을 받는다. 되살리려는 사람은 V0330MessageReadStoreTests 의 60초 테스트를 먼저 읽어라.
    nonisolated static let messageReadSignalCoalesceSeconds: TimeInterval = 1

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
    /// 같은 초 안의 말은 **서버 순서**로 깬다(m-fix F7) — 이력이 읽음 칸을 실어 왔을 때만 그 순서를 안다.
    var messageThreads: [MessageThread] {
        MessageThreadBuilder.threads(from: messageHistory, serverOrder: messageHistoryReadSnapshot?.serverOrder)
    }

    /// 지금 고른 대화(아무도 안 골랐거나 그 사람과의 대화가 사라졌으면 nil).
    var selectedMessageThread: MessageThread? {
        guard let selectedMessagePeerID else { return nil }
        return messageThreads.first { $0.peerUserID == selectedMessagePeerID }
    }

    /// 안 읽은 것이 있는 상대들(v0.3.30 — M2 의 목록 점·레일 점·메뉴바 점이 이것 하나를 읽는다).
    ///
    /// 서버가 읽음을 알면 **서버 판정**이다: 이력(`isUnread`)과 요약(`message_unread_summary`) 중 **더 나중에 띄운 요청**의
    /// 결과를 쓰고, 그 요청이 모르는 낙관 읽음을 뺀다. 그래서 폰에서 읽으면(요약 total 0) 맥의 점도 사라진다.
    /// 서버가 읽음을 모르면(옛 서버) 옛 규칙 — **받은 것의 마지막 시각 > 내가 그 대화를 마지막으로 연 시각** — 이다.
    /// 내가 보낸 것은 어느 쪽에서도 세지 않는다 — 내 말에 점이 붙으면 그건 아무 정보도 아니다.
    var unreadMessagePeerIDs: Set<String> {
        MessageUnreadRules.unreadPeerIDs(
            history: messageHistory,
            historySnapshot: messageHistoryReadSnapshot,
            summary: messageUnreadSummary,
            optimistic: messageOptimisticReads,
            legacyStamps: messageReadStamps
        )
    }

    /// 안 읽은 메시지가 하나라도 있는가(메뉴바 점·레일 점의 스위치).
    var hasUnreadMessages: Bool { !unreadMessagePeerIDs.isEmpty }

    /// 화면 머리에 쓸 상대 이름. **세 곳을 차례로 본다** — 한 번도 대화한 적 없는 사람을 콕찌르기 목록에서
    /// 처음 누른 경우가 그 셋이 다 필요한 이유다(그때는 이력에 그 사람 행이 한 줄도 없다).
    ///   ① 이력(이 사람과 주고받은 것이 있으면 그 이름이 가장 최신이다 — 별명을 바꿔도 따라간다)
    ///   ② 콕찌르기 목록(말풍선 버튼을 누른 그 행. 이 화면의 유일한 진입문이라 거의 언제나 있다)
    ///   ③ 수신 큐/마지막 표시분(캐릭터 말풍선을 눌러 들어온 경우 — 그때는 목록을 안 지나왔을 수 있다)
    /// 새 저장 프로퍼티를 만들지 않는 것이 요점이다: 이름을 따로 들면 그 값과 서버 이름이 언젠가 갈린다.
    var selectedMessagePeerName: String? {
        guard let id = selectedMessagePeerID else { return nil }
        if let thread = messageThreads.first(where: { $0.peerUserID == id }) { return thread.peerName }
        if let entry = pokeDirectory.first(where: { $0.userID == id }) { return entry.name }
        if let last = lastShownMessage, last.fromUserID == id { return last.fromName }
        return receivedMessages.first { $0.fromUserID == id }?.fromName
    }

    /// 같은 세 곳에서 오는 아바타(없으면 nil — 그때는 이니셜 원이 그려진다).
    var selectedMessagePeerAvatarURL: URL? {
        guard let id = selectedMessagePeerID else { return nil }
        if let thread = messageThreads.first(where: { $0.peerUserID == id }), let url = thread.peerAvatarURL {
            return url
        }
        return pokeDirectory.first { $0.userID == id }?.avatarURL
    }

    /// 지금 입력칸에 있는 글의 길이(코드포인트 — 서버와 같은 눈금).
    var messageDraftLength: Int { MessageBody.length(messageDraft) }

    /// 지금 [보내기]를 누를 수 있는가.
    ///
    /// **쿨타임은 여기 없다**(위 머리 주석 ①). 판정은 셋뿐이다: 왕복 중이 아니고 · 상대를 골랐고 ·
    /// 본문이 서버 경계 안이다. 근무중 여부는 **여기서 보지 않는다** — v0.3.30 부터 서버도 보지 않는다
    /// (옛 서버가 `not_working` 으로 답하면 전송 시 안내가 말한다).
    var canSendMessageNow: Bool {
        guard !isSendingMessage, selectedMessagePeerID != nil else { return false }
        if case .ok = MessageBody.validate(messageDraft) { return true }
        return false
    }

    // MARK: 패널 열고 닫기

    /// **이 기능의 공개 진입점.** 콕찌르기 목록의 말풍선 버튼과 캐릭터의 도착 말풍선이 부르는 단 하나의 문이다.
    ///
    /// - Parameters:
    ///   - peer: 이 화면의 상대. **옵셔널이 아니다**(2026-09-11 지적 — "애초에 대화상대를 고르지 않고
    ///     대화창에 진입할 수가 없어야되잖아"). 이 화면의 계약은 **상대는 들어올 때 정해지고 나갈 때까지
    ///     바뀌지 않는다** 하나이고, 그 "들어올 때"가 이 인자다. `String?` 이던 v0.2.50 까지는 nil 로 들어와
    ///     "대화 상대를 고르지 않았어요" 화면이 뜰 수 있었다.
    ///     **`String?` 으로 되돌리지 마라** — `String` 은 `String?` 로 암묵 승격되므로 넓혀도 호출부가 전부
    ///     그대로 컴파일돼 아무도 눈치채지 못한다(그래서 V0251MessagePeerTests 가 이 시그니처를 소스로 못 박는다).
    ///     빈 문자열은 **조용히 무시한다**. `assertionFailure` 로 막으면 디버그에선 멈추고 릴리스에선 지나가
    ///     두 빌드가 다르게 동작한다 — 상대 없는 요청은 크래시로 갚을 일이 아니라 그냥 안 여는 일이다.
    ///   - origin: [뒤로]가 돌아갈 곳. 기본은 콕찌르기 목록이다.
    ///
    /// ★ **팝오버를 닫지 않는다**(v0.2.50 에서 바뀐 지점). 창이던 시절에는 `WindowTopAnchor.dismissMenuPopover()`
    ///   가 여기 있었다 — 팝오버 위에 창을 띄우는 동작이었으니까. 지금은 팝오버 **안에서 화면이 바뀌는 것**이라,
    ///   닫으면 사용자가 방금 연 화면이 그 자리에서 사라진다. 미니게임·설정은 여전히 별도 창이므로 그쪽 호출은
    ///   그대로 남아 있다(이 파일에서 지운 것이 그쪽까지 지운 것으로 읽히면 안 된다).
    ///
    /// 다른 하위 패널과 **상호 배타**다(리그·토큰 보드·콕찌르기·내 기록·울트라·제보). 순서가 뜻이다:
    /// `closeUltraPanel()` 은 origin 이 .poke 면 콕찌르기 목록을 되살리므로, 목록을 내리는 줄이 그 뒤에 온다.
    func openMessagePanel(peer: String, from origin: MessagePanelOrigin = .poke) {
        // 빈 id 는 **아무 상태도 세우기 전에** 돌려보낸다. 이 가드를 아래로 내리지 마라 — origin 이나 패널 깃발을
        // 먼저 세우고 나가면 그 상태가 곧 "상대 없는 대화 화면"이다.
        guard !peer.isEmpty else { return }
        messagePanelOrigin = origin
        isMessagePanelVisible = true
        isLeaderboardVisible = false
        closeTokenBoard()
        closeUltraPanel()
        closeFeedbackPanel()
        closeCharacterPanel()
        closeShopPanel()
        isInsightsPanelVisible = false
        // ★ `closePokePanel()` 이 아니라 깃발 한 줄이다(울트라 배지 탭이 세운 규약 — blocker UI-2).
        //   그 함수는 `lastShownMessage` 를 죽이는데, 말풍선 버튼을 누른 것은 '그 알림을 봤다'가 아니다.
        //   take_pokes 는 서버 원자 소비라 그렇게 지운 글자는 복구할 길이 없다.
        isPokePanelVisible = false
        // 상대를 정하는 자리는 **앱 전체에서 이 한 줄뿐이다.** 이후 어떤 응답·수신 폴링·전송 성공도 이 값을
        // 바꾸지 않는다(performLoadMessageHistory 의 "다시 넣지 마라" 주석, V0251MessagePeerTests 의 소스 계약).
        selectMessagePeer(peer)
        // 첫 프레임부터 빈 자리에 "불러오는 중…"이 뜨게 한다(제보 목록과 같은 규약).
        // **세션이 있을 때만** 세운다 — 로그인 전이면 아래 로드가 세션 가드에서 조용히 되돌아가는데,
        // 그때 이 깃발을 세워 두면 아무도 내려 주지 않아 화면이 영영 "불러오는 중…"에 갇힌다.
        if session != nil, !messageHistoryLoaded { messageHistoryLoading = true }
        loadMessageHistory()
    }

    /// 캐릭터 머리 위 도착 말풍선이 나르는 **보낸이 id**(모르면 nil). CheckApp 의 말풍선 배선이 읽는다.
    ///
    /// 표시 직후 그 한 건은 큐에서 `lastShownMessage` 로 옮겨지므로 그쪽을 먼저 보고, 아직 안 옮겨졌으면
    /// 큐의 맨 앞(`currentMessage`)을 본다 — v0.2.50 배선이 쓰던 순서 그대로다(이번에 바꾼 것은 nil 의 행방뿐이다).
    /// **nil 이 나오는 길이 실제로 있다**: 보낸이 id 를 안 싣던 옛 행(`ReceivedMessage.fromUserID` 는 하위호환으로
    /// 옵셔널이다), 그리고 말풍선이 떠 있는 사이 `lastShownMessage` 가 소비·만료되고 큐도 빈 경우.
    /// 빈 문자열도 nil 로 접는다 — 그대로 넘기면 `openMessagePanel` 이 조용히 무시해 말풍선이 "눌러도 아무 일 없음"이 된다.
    var arrivalBubbleSenderID: String? {
        guard let peer = lastShownMessage?.fromUserID ?? currentMessage?.fromUserID, !peer.isEmpty else {
            return nil
        }
        return peer
    }

    /// 보낸이를 모르는 도착 말풍선을 눌렀을 때의 갈음 — 대화 패널 대신 **콕찌르기 목록**을 연다(2026-09-11 지적).
    ///
    /// 대화 패널은 상대 없이 열 수 없으므로 사용자가 목록에서 그 사람 행의 말풍선을 눌러 들어가게 한다.
    /// **토글이 아니다** — 이미 목록이 떠 있는데 `togglePokePanel()` 을 그대로 부르면 목록이 닫히고,
    /// 그 길의 `closePokePanel()` 이 방금 뜬 `lastShownMessage` 를 소비한다(take_pokes 는 서버 원자 소비라
    /// 그 글자는 복구할 길이 없다). 이 가드를 지우면 말풍선 두 번 탭이 목록을 닫고 메시지를 버린다.
    func openPokeListToPickAPeer() {
        guard !isPokePanelVisible else { return }
        togglePokePanel()
    }

    /// 대화 패널을 닫는 **유일한** 경로(멱등). [뒤로]와 다른 패널을 여는 다섯 자리가 전부 여기를 지난다.
    ///
    /// 들어온 곳으로 되돌린다 — 콕찌르기에서 들어왔으면 그 목록으로(다른 사람과 얘기하려면 거기서 다시 고른다),
    /// 캐릭터 말풍선에서 들어왔으면 홈(팀 목록)으로. 후자를 콕찌르기로 보내면 가 본 적 없는 화면으로
    /// '돌아가게' 된다(울트라 패널의 `ultraPanelOrigin` 이 세운 규약 그대로다).
    ///
    /// **초안은 지우지 않는다** — 쓰다 만 말이 화면을 잘못 바꿨다고 사라지면 사용자는 그 말을 다시 못 쓴다.
    /// 초안이 사라지는 자리는 전송 성공과 **상대 바꾸기** 둘뿐이다(`selectMessagePeer`).
    func closeMessagePanel() {
        guard isMessagePanelVisible else {
            // 이미 닫혀 있으면 origin 도 건드리지 않는다 — 다른 패널 토글이 부를 때 진입 맥락을 지우면
            // 다음에 열린 대화의 [뒤로]가 엉뚱한 곳으로 간다(closeUltraPanel 과 같은 가드).
            return
        }
        isMessagePanelVisible = false
        // 전송 결과 문구는 이 화면의 것이다. 남기면 콕찌르기 목록 안내줄에 "메시지를 보냈어요"가 떠 있다.
        if messageNotice != nil { messageNotice = nil }
        if messagePanelOrigin == .poke {
            // `togglePokePanel()` 이 아니라 직접 세운다 — 그 토글은 열려 있으면 closePokePanel() 을 타서
            // 아직 안 본 메시지를 소비한다(closeUltraPanel 이 같은 이유로 같은 모양을 쓴다).
            isPokePanelVisible = true
            loadPokeDirectory()
        }
        messagePanelOrigin = .poke
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
            evaluateMessageReadMarking()
            return
        }
        selectedMessagePeerID = peerUserID
        messageDraft = ""
        // 앞사람에게서 받은 전송 결과 문구도 함께 내린다 — 다른 대화 위에 남으면 무엇에 대한 말인지 알 수 없다.
        if messageNotice != nil { messageNotice = nil }
        if let peerUserID { messageReadStamps[peerUserID] = clock() }
        // 서버가 읽음을 알면 여기서 서버 경계를 올린다(v0.3.30). 판정(팝오버·패널·상대·서버 기준 안 읽음)은 그 함수 하나에 있다 —
        // 위 도장은 옛 서버용이라 서버 경계와 따로 산다.
        evaluateMessageReadMarking()
    }

    // MARK: 이력

    /// 이력을 로드한다(Task 발사). **패널 열기 · 전송 성공 · 수신 도착에서만 부른다.**
    /// [새로고침] 버튼은 없다 — 최신을 보는 길은 "[뒤로] 뒤 다시 말풍선"과 수신 도착 자동 갱신 둘이다.
    func loadMessageHistory() {
        Task { @MainActor in await performLoadMessageHistory() }
    }

    /// 수신(take_pokes drain)이 새 메시지를 물어왔을 때의 갱신(`enqueueReceivedMessages`·`receiveConsumedMessages` 가 부른다).
    ///
    /// v0.3.30 m-fix(F2): **메시지 활동 새로고침**이다 — 안 읽음 요약 1회 + 대화가 팝오버에 보이면 이력 1회.
    /// 근무 중인 맥은 초인종을 take_pokes 로 소비하고 말풍선으로 띄우는데, 말풍선으로 본 것은 읽음이 아니다(M1.8).
    /// 여기서 요약을 안 받으면 서버는 "안 읽음"이라 말하는데 메뉴바·레일·목록 점이 꺼진 채다(이력만 받던 v0.2.49~ 의 틈).
    ///
    /// **이력은 여전히 볼 사람이 있을 때만** 받는다(대화 화면이 떠 있을 수 있음 — `isMessageConversationOnScreen`, 부르는 순간 판정).
    /// 패널 깃발은 팝오버를 닫아도 안 내려가므로 깃발만 보면 닫힌 팝오버에도 이력 조회가 붙는다(v0.2.50).
    /// 건너뛴 이력은 "낡음"으로 적혀 대화가 보이는 채로 팝오버를 다시 열 때 받는다(F1). 폴링이 아니다 — 도착 1건당 1회다.
    func refreshMessageHistoryOnArrival() {
        guard session != nil else { return }
        requestMessageActivityRefresh()
    }

    /// `message_history_with_reads`(없는 서버면 `message_history`)를 받아 반영한다.
    ///
    /// 서버는 오래된 것부터 준다고 약속하지만 **정렬을 다시 세운다** — 순서가 곧 사용자가 읽는 순서라
    /// 서버 정렬을 신뢰하지 않는 것이 이 저장소의 규약이다(sortedForPokeDisplay·제보 목록과 같은 근거).
    /// 다만 **서버가 준 순서는 따로 적어 둔다**(`MessageHistoryReadSnapshot.serverOrder`, v0.3.30): 화면 정렬 키인
    /// `createdAt` 은 초 단위라 같은 초 안의 선후를 모르고, "마지막으로 받은 메시지"(읽음 경계)를 고르는 판정은
    /// 그 선후를 틀리면 영영 안 꺼지는 점을 만든다.
    func performLoadMessageHistory() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        // 요청을 **띄우는 순간**의 일련번호(v0.3.30). 응답 도착 순서가 아니라 요청 순서가 서버 상태의 순서다 —
        // 늦게 도착한 옛 응답이 새 응답을 덮지 않게 하고, 요약과 어느 쪽이 더 최신인지 가르는 근거다.
        let serial = messageReadRuntime.nextHistorySerial()
        if !messageHistoryLoading { messageHistoryLoading = true }
        if messageHistoryFailed { messageHistoryFailed = false }
        defer { if generation == sessionGeneration, messageHistoryLoading { messageHistoryLoading = false } }
        do {
            let loaded = try await withSessionRetry { activeSession in
                try await fetchMessageHistoryPreferringReads(accessToken: activeSession.accessToken)
            }
            // 세대가 갈렸으면 이 응답은 앞 계정의 것이다 — 그대로 대입하면 새 계정 화면에 남의 대화가 그려진다.
            guard generation == sessionGeneration else { return }
            // 더 나중에 띄운 조회가 이미 반영됐다 — 이 응답은 그보다 낡은 서버 상태다(읽음 1 이 되살아나면 안 된다).
            guard serial > messageReadRuntime.lastAppliedHistorySerial else { return }
            messageReadRuntime.lastAppliedHistorySerial = serial
            // 이 조회가 "낡음" 표시보다 나중에 띄워졌으면 그 계기를 반영했다(F1).
            messageReadRuntime.clearHistoryStale(appliedSerial: serial)
            // 즉시 삽입(v0.3.31 M4)한 도착분 중 **이 조회보다 나중에 넣은 것**은 남긴다. 넣기 전에 띄운 조회는 그 말을 모를 수 있다 —
            // 그 응답이 판을 통째로 갈면 방금 그려진 말이 사라졌다가 다음 조회에 되살아난다(0.3.29 대조군 c4 의 "늦게 온 옛 이력").
            // 서버 값이 이기는 것은 **그 말을 아는** 조회다: 같은 id 가 응답에 있으면 서버 행이, 넣은 뒤에 띄운 조회에 없으면(보관 창 밖) 서버가 이긴다.
            let kept = messageReadRuntime.survivingLocalArrivals(
                historySerial: serial, current: messageHistory, server: loaded.entries
            )
            // 같은 초의 동률은 서버 순서로 깬다(F7). 읽음 칸이 없는 옛 서버는 id 로(예전 그대로).
            let sorted = (loaded.entries + kept).sortedForMessageHistory(serverOrder: loaded.hasReadReceipts ? loaded.serverOrder : nil)
            if messageHistory != sorted { messageHistory = sorted }
            applyMessageHistoryReadCapability(loaded, serial: serial)
            if !messageHistoryLoaded { messageHistoryLoaded = true }
            if messageHistoryFailed { messageHistoryFailed = false }
            // 새 이력이 왔다 — 지금 보이는 대화에 서버 기준 안 읽은 말이 있으면 읽음으로 올린다(새 메시지 도착 포함).
            evaluateMessageReadMarking()
            // ★★ **이 응답으로 대화 상대를 바꾸지 마라. 아래 코드를 다시 넣지 마라.** (2026-09-11 지적)
            //
            //   v0.2.50 까지 여기 이런 두 갈래가 있었다:
            //       if let selected = selectedMessagePeerID, !sorted.contains(where: { $0.peerUserID == selected }) {
            //           selectedMessagePeerID = nil                                    // ← ①
            //       } else if selectedMessagePeerID == nil {
            //           selectMessagePeer(MessageThreadBuilder.threads(from: sorted).first?.peerUserID)  // ← ②
            //       }
            //
            //   ① 이 줄이 사용자가 본 버그다: "특정 사람의 프로필에 있는 대화 버튼을 눌러서 진입하는건데
            //     대화 상대를 고르지 않았다고 떠. 애초에 대화상대를 고르지 않고 대화창에 진입할 수가
            //     없어야되잖아." — **한 번도 대화한 적 없는 사람**은 이력에 행이 한 줄도 없으므로 조건이
            //     언제나 참이고, 진입 직후 첫 왕복이 끝나는 순간 선택이 지워져 화면이
            //     "대화 상대를 고르지 않았어요"로 갈아엎힌다. 즉 **처음 말 거는 모든 사람**에게서 재현된다.
            //     원래 의도였던 '12시간 경과로 대화가 사라짐'조차 이 처리는 옳지 않다: 보던 대화가 만료되면
            //     화면을 통째로 바꿀 것이 아니라 그 자리에서 "아직 주고받은 메시지가 없어요"로 비어야 한다
            //     (뷰의 `MessagePanelEmptyMessage` 가 hasPeer=true 로 이미 그 문장을 갖고 있다 — 고칠 것이 없다).
            //
            //   ② 자동 선택도 함께 걷었다. v0.2.50 에 왼쪽 대화 목록이 사라지면서 이 화면은 **한 사람짜리**가
            //     됐는데, 이 줄이 살아 있으면 **응답이 도착하는 순간** 가장 최근 대화가 대신 열린다 — 누른 사람과
            //     화면에 뜬 사람이 다를 수 있다는 뜻이고, 그건 메시지 화면에서 가장 나쁜 종류의 버그다.
            //     2026-09-11 사용자 재확인: "대화 상대를 매번 새롭게 선택하는게 아니라. 만약에 다른사람한테
            //     보내고 싶으면 나와서 그 다른사람 옆에 있는 대화창을 눌러서 진입하면 되는거야."
            //     v0.2.51 부터 진입점 `openMessagePanel(peer:)` 의 인자가 `String` 이라 "선택이 nil 인 채로 이
            //     응답에 도착하는" 정상 경로는 없다. 그래서 ② 는 **죽은 가지라 무해해 보여 되돌아오기 쉬운 자리**다 —
            //     살아나는 순간, 그 nil 이 어디서 오든 응답이 상대를 고른다.
            //
            //   그래서 **선택을 사용자 조작 없이 바꾸는 자리는 이 앱에 하나도 없다.** 남은 것은 두 곳뿐이다:
            //   사용자가 고르는 `selectMessagePeer(_:)` 와, 계정이 갈릴 때 비우는 `clearPersistedSession()`.
            //   서버 응답(빈 이력·만료·실패·늦게 온 앞 계정 응답)과 수신 폴링 갱신, 전송 성공은 전부
            //   **선택을 읽기만 한다**. 되돌리려는 사람은 V0251MessagePeerTests 를 먼저 읽어라 — 런타임 테스트가
            //   응답의 각 얼굴을 재고, 소스 계약 테스트가 이 함수 본문에 선택 대입도 `selectMessagePeer(` 호출도
            //   없음을 본다(대입 개수만 세면 ② 처럼 문을 **부르는** 재유입은 초록으로 지나간다 — 실측).
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 마이그레이션 전 창(브루 배포가 db push 보다 앞선 경우): 실패가 아니라 '아직 함수가 없다'.
                // 빈 이력으로 조용히 접는다 — 실패 문구와 [다시 시도] 는 **사용자가 고칠 수 있는 일**에만 쓴다
                // (제보 목록이 세운 관례). 그 며칠 동안 모두가 빨간 화면을 보면 그건 우리 배포 순서의 값이다.
                if !messageHistoryLoaded { messageHistoryLoaded = true }
                // 두 함수가 다 없는 서버다 — 읽음도 모른다(1 을 그리지 않는다).
                if messageReadReceiptsAvailable { messageReadReceiptsAvailable = false }
                // 받을 이력이 없는 서버다 — 낡음 표시를 붙들고 있으면 열 때마다 헛조회한다.
                // 이것은 실패가 아니라 "받을 것이 없다"는 답이라 아래 실패 가지의 우회 소진과 다르다: 소진은 같은 계기로 한 번 더
                // 막을 뿐이고, 지우기는 표시 자체를 내린다(m-reverify R8 — 이 줄이 없으면 여닫을 때마다 헛조회 세 건).
                messageReadRuntime.clearHistoryStale(appliedSerial: serial)
            } else {
                // 5xx·네트워크 — 낡음 표시는 **남긴다**(아직 못 받았다). 대신 이 조회가 그 표시보다 나중에 띄운 것이면 그 표시로는
                // 스로틀을 다시 우회하지 않는다(m-fix2 · m-reverify R3). 안 막으면 장애 동안 여닫이마다 요약·이력 두 건이 나간다.
                // 다음 계기(새 신호)나 60초 스로틀, 화면의 [다시 시도]가 다시 받는다.
                messageReadRuntime.noteHistoryFailed(serial: serial)
                if !messageHistoryFailed { messageHistoryFailed = true }
            }
        }
    }

    /// 읽음 칸이 붙은 이력을 먼저 부르고, **그 함수가 없는 서버**(404 / PGRST202)면 옛 `message_history` 로 접는다.
    ///
    /// 폴백을 캐시하지 않는다(takePokes 의 옛 모양 재호출과 같은 판단): 메뉴바 앱은 몇 주씩 살아 있고 db push 는 그 사이
    /// 언제든 끝난다 — 한 번 옛 서버로 판정해 눌러앉으면 서버가 고쳐진 뒤에도 재시작 전까지 읽음 표시가 영영 안 뜬다.
    /// 그 대가는 옛 서버 창에서 이력 조회 1회당 요청 2건이고, 이력은 이벤트로만 부르므로 작다.
    func fetchMessageHistoryPreferringReads(accessToken: String) async throws -> MessageHistoryLoad {
        do {
            let entries = try await service.fetchMessageHistoryWithReads(
                accessToken: accessToken,
                hours: Self.messageHistoryHours,
                limit: Self.messageHistoryLimit
            )
            return MessageHistoryLoad(entries: entries, hasReadReceipts: true)
        } catch let error as SupabaseWorkServiceError where Self.isMissingMessageReadFunction(error) {
            let entries = try await service.fetchMessageHistory(
                accessToken: accessToken,
                hours: Self.messageHistoryHours,
                limit: Self.messageHistoryLimit
            )
            return MessageHistoryLoad(entries: entries, hasReadReceipts: false)
        }
    }

    /// "이 서버에는 그 함수가 없다"의 판정(v0.3.30). PostgREST 는 404 + PGRST202("… in the schema cache")를 내고 공용 매핑이
    /// `.databaseSchemaMissing` 으로 접는다. 본문이 그 문장이 아닌 404 도 같은 뜻으로 본다(프록시·게이트웨이가 본문을 바꾸는 날).
    /// **401/403·5xx·네트워크는 여기에 넣지 않는다** — 그걸 "함수 없음"으로 접으면 일시 장애 한 번에 읽음 표시가 꺼진다.
    nonisolated static func isMissingMessageReadFunction(_ error: SupabaseWorkServiceError) -> Bool {
        switch error {
        case .databaseSchemaMissing: return true
        case .invalidResponse(let status): return status == 404
        default: return false
        }
    }

    /// 이력 응답이 말해 준 읽음 기능 여부와 서버 순서를 반영한다.
    private func applyMessageHistoryReadCapability(_ loaded: MessageHistoryLoad, serial: Int) {
        guard loaded.hasReadReceipts else {
            // 옛 서버 — 읽음을 모른다. 들고 있던 스냅샷을 버린다(서버가 되돌아간 날 낡은 판정이 점을 붙들지 않게).
            if messageHistoryReadSnapshot != nil { messageHistoryReadSnapshot = nil }
            if messageReadReceiptsAvailable { messageReadReceiptsAvailable = false }
            return
        }
        let snapshot = MessageHistoryReadSnapshot(serial: serial, serverOrder: loaded.serverOrder)
        if messageHistoryReadSnapshot != snapshot { messageHistoryReadSnapshot = snapshot }
        if !messageReadReceiptsAvailable { messageReadReceiptsAvailable = true }
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
    /// **집중 모드·근무 여부는 여기서 거르지 않는다.** 서버가 판정한다(target_focused, 옛 서버는 not_working 도).
    /// 클라가 자기 미러로 한 번 더 판정하면 두 판정이 언젠가 갈리고, 그때 화면은 서버가 허락한 전송을 막거나
    /// 막을 전송을 허락한다 — 사용자가 원인을 알 수 없는 종류의 버그다. v0.2.49~v0.3.29 에는 "내가 근무중이 아닌 것만은"
    /// 선게이트로 막았는데, v0.3.30 에 서버가 그 규칙을 지워 **바로 그 버그가 되었으므로** 걷었다.
    ///
    /// 빈 본문·200자 초과도 여기서 판정하지 않는다. `service.sendMessage` 가 MessageBody 로 사전 판정해
    /// **네트워크를 타지 않고** 서버와 같은 status 를 즉답하므로, 아래 switch 하나가 로컬 거절과 서버 거절을
    /// 같은 문구로 다룬다(같은 실패를 catch 와 switch 두 곳에서 다루면 그 둘은 반드시 갈린다).
    func sendMessage(to userID: String, body: String) {
        guard session != nil else { return }
        // ★ 근무중 선게이트(`startedAt != nil`)는 **v0.3.30 에 걷었다.** 서버가 send_message 의 보낸이·받는이 근무 조건을
        //   지웠으므로 그 게이트는 서버가 허락하는 전송을 클라가 막는 자리가 된다(찌르기 sendPoke 의 게이트는 서버 규칙이
        //   그대로라 남는다). 옛 서버가 `not_working` 으로 답하면 아래 분기가 같은 문구로 말한다.
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

// MARK: - 읽음 (v0.3.30) — 서버 경계 · 요약 · 낙관 읽음
//
// 서버 계약은 SPEC-wave1 §1.1 이다. 이 절이 지키는 넷:
//  ① **읽음을 올리는 자리는 `evaluateMessageReadMarking()` 하나다.** 조건(팝오버가 떠 있음 · 대화 패널이 보임 · 그 상대가
//     골라져 있음 · 서버 기준 안 읽은 받은 메시지가 있음)을 여기저기 흩어 두면 "말풍선으로 본 것도 읽음"이 어느 한 자리로
//     새어 들어온다. 부르는 자리(패널 열기·상대 고르기·이력 도착·팝오버 열기)는 판정하지 않고 부르기만 한다.
//  ② **시각을 비교하지 않는다.** 안 읽음은 서버 플래그, 경계는 메시지 id, 선후는 서버 순서·요청 일련번호다.
//  ③ **메시지 활동 새로고침은 겹치지 않는다**(진행 중이면 뒤따르는 한 번으로 합친다 — requestDrain 과 같은 모양).
//     읽음 신호와 읽음 처리 성공 뒤는 그 앞에 **1초 합치기 창**을 더 거친다(m-fix2 · 부록 B-2 — 서버가 읽은 사람 채널에도 신호를 보내
//     몰려 오는 신호와 자기 메아리를 한 번으로 갚는다).
//  ④ 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정의 점·경계를 건드리지 않는다.

@MainActor
extension WorkTimerStore {
    /// **메시지 활동 새로고침** — 안 읽음 요약 1회(+ 대화가 팝오버에 보이거나 `includeHistory` 면 이력 1회).
    ///
    /// 부르는 자리: 소비할 수 없는 맥의 초인종·조인 직후 따라잡기(근무 여부 무관)·로그인 직후·팝오버 열기(스로틀)·
    /// **drain 이 메시지를 받았을 때**(m-fix F2)·합치기 창이 닫힐 때(읽음 신호 `message_read`·읽음 처리 성공 뒤 — m-fix2,
    /// `requestMessageActivityRefreshCoalesced`). **폴링이 아니다** — 이벤트마다 한 번이다.
    /// 도는 중에 또 불리면 새 Task 를 만들지 않고 뒤따르는 한 번을 예약한다(버리면 조회가 나간 뒤 도착한 신호가 안 보이고,
    /// 셋 다 쏘면 무료 플랜 왕복만 는다). 반환 Task 는 기다려야 하는 호출부(조인 따라잡기)와 테스트용이다.
    ///
    /// 이력을 받을지는 **부르는 순간** 정한다(m-fix F1). 그 계기를 볼 사람이 없어(팝오버 닫힘·패널 안 보임) 이력을 건너뛰면
    /// "이력 낡음"을 적는다 — 대화가 보이는 채로 팝오버를 다시 열면 스로틀과 무관하게 받는다(`refreshMessageActivityOnMenuOpen`).
    /// 안 적으면 닫힌 동안 온 읽음·새 말이 60초 안에 다시 연 대화에 안 그려진다(1 이 안 사라지고, 점은 켜졌는데 새 말은 없다).
    @discardableResult
    func requestMessageActivityRefresh(includeHistory: Bool = false) -> Task<Void, Never>? {
        guard session != nil else { return nil }
        let runtime = messageReadRuntime
        if includeHistory || isMessageConversationOnScreen {
            runtime.activityWantsHistory = true
        } else {
            runtime.markHistoryStale()
        }
        if let running = runtime.activityTask {
            runtime.activityAgain = true
            return running
        }
        let generation = sessionGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다(requestDrain 규약).
                runtime.activityAgain = false
                let wantsHistory = runtime.activityWantsHistory
                runtime.activityWantsHistory = false
                await self.performLoadMessageUnreadSummary()
                guard generation == self.sessionGeneration else { return }
                if wantsHistory {
                    await self.performLoadMessageHistory()
                    guard generation == self.sessionGeneration else { return }
                }
            } while runtime.activityAgain
            runtime.activityTask = nil
        }
        runtime.activityTask = task
        return task
    }

    /// 합치기 창을 거친 **메시지 활동 새로고침**(v0.3.30 m-fix2 · 부록 B-2). 읽음 신호(`message_read`)와 읽음 처리 성공 뒤가 부른다.
    ///
    /// 창이 없으면 열고(`messageReadSignalCoalesceSeconds` 뒤 닫힌다), 있으면 그 창에 합친다 — 신호가 몰려도, 이 맥의 읽음 처리와
    /// 서버가 읽은 사람 채널로 되돌려 보내는 메아리가 겹쳐도 새로고침은 한 번이다. **팝오버가 닫혀 있어도 요약은 받는다**
    /// (다른 기기에서 읽은 것이 메뉴바·레일·목록 점에 몇 초 안에 닿는 근거). 창이 닫힐 때 새로고침이 도는 중이면 뒤따르는 한 번으로
    /// 합쳐진다(`requestMessageActivityRefresh` 의 직렬화).
    ///
    /// 이력은 부르는 순간 대화가 안 보이면 **지금** 낡음으로 적는다 — 창이 닫히기 전에 대화를 띄운 채 팝오버를 열어도
    /// `refreshMessageActivityOnMenuOpen` 의 우회가 곧바로 받게. 대화가 보이면 창이 닫힐 때 받는다.
    func requestMessageActivityRefreshCoalesced() {
        guard session != nil else { return }
        let runtime = messageReadRuntime
        if !isMessageConversationOnScreen { runtime.markHistoryStale() }
        // 이 계기를 반영하려면 **지금 이후에 띄운** 조회여야 한다(창이 닫힐 때 이미 그런 조회가 나갔으면 다시 묻지 않는다).
        runtime.activityWindowSerial = runtime.serial
        guard runtime.activityWindowTask == nil else { return }
        let generation = sessionGeneration
        let sleep = messageReadSignalSleep
        let seconds = Self.messageReadSignalCoalesceSeconds
        runtime.activityWindowTask = Task { @MainActor [weak self] in
            await sleep(seconds)
            // 어느 가지로 나가든 창은 닫는다 — 안 닫으면 이후 신호가 전부 죽은 창에 합쳐져 영영 새로고침이 없다.
            // (로그아웃 뒤 깬 창이 닫는 것은 옛 장부의 창이다 — clearPersistedSession 이 장부를 통째로 바꾼다.)
            runtime.activityWindowTask = nil
            // 로그아웃·계정 전환 뒤 깬 창은 새 계정에 새로고침을 쏘지 않는다(취소 + 세대 가드).
            guard !Task.isCancelled, let self, generation == self.sessionGeneration else { return }
            self.closeMessageActivityWindow(pendingSerial: runtime.activityWindowSerial)
        }
    }

    /// 합치기 창이 닫혔다. 창에 모인 계기(`pendingSerial` 순간까지의 서버 변화)를 **그보다 나중에 띄운** 조회가 이미 맡았으면
    /// 다시 묻지 않는다 — 창이 열린 사이 팝오버를 열어 요약·이력을 받았으면 그게 이 계기의 답이다(신호는 커밋 뒤에 오므로
    /// 신호를 받은 뒤 띄운 조회는 그 변화를 본다).
    private func closeMessageActivityWindow(pendingSerial: Int) {
        let runtime = messageReadRuntime
        let conversationOnScreen = isMessageConversationOnScreen
        let historyTaken = runtime.lastHistoryLaunchSerial > pendingSerial
        let summaryTaken = runtime.lastSummaryLaunchSerial > pendingSerial
        if !conversationOnScreen, !historyTaken {
            // 볼 사람이 없는 이력은 낡음으로 적는다(창이 열린 사이 팝오버가 닫혔을 수 있다 — 다시 열 때 우회가 받는다).
            runtime.markHistoryStale()
        }
        // 안 보이는 대화의 이력은 위 낡음 표시가 맡는다. 보이는 대화는 창 뒤에 띄운 이력이 있어야 맡은 것이다.
        let historyCovered = historyTaken || !conversationOnScreen
        if summaryTaken, historyCovered { return }
        requestMessageActivityRefresh()
    }

    /// 팝오버를 열 때(스로틀). **대화 패널이 안 보여도 이력까지 받는다** — 안 읽음 점은 이력·요약 중 더 나중에 띄운
    /// 쪽을 기준으로 계산되고, 이력만이 "어느 메시지가" 안 읽혔는지 안다(요약은 개수뿐이다).
    ///
    /// 스로틀은 둘로 갈린다:
    ///  · 대화가 보이는데 이력이 낡았다(닫힌 동안 온 계기가 이력을 건너뛰었다) → **스로틀 없이** 받는다(m-fix F1).
    ///    **같은 낡음 표시로는 한 번만**이다(m-fix2 · m-reverify R3): 그 조회가 실패하면 표시는 남지만 우회는 다 썼다 — 안 그러면
    ///    이력 장애 동안 여닫이마다 요청 두 건이 나간다. 새 계기가 새 표시를 적으면 다시 한 번 우회한다.
    ///  · 그 밖 → 60초. 점이 켜져 있어도 같다(m-fix 의 10초 예외는 m-fix2 에서 걷었다 — 다른 기기의 읽음은 이제 신호가 온다,
    ///    `messageReadSignalCoalesceSeconds` 주석).
    func refreshMessageActivityOnMenuOpen() {
        guard session != nil else { return }
        let now = clock()
        let runtime = messageReadRuntime
        // 대화 패널 조건을 빼지 마라(m-reverify R4 · MR09): 로그인 직후·닫힌 팝오버의 거의 모든 새로고침이 낡음을 적으므로,
        // 빠지면 팝오버 열기 60초 스로틀이 사실상 사라진다.
        let staleConversationOnScreen = isMessagePanelVisible && runtime.staleHistoryMayBypassThrottle
        guard staleConversationOnScreen
            || now.timeIntervalSince(runtime.lastMenuRefreshAt) >= Self.messageMenuRefreshThrottleSeconds
        else { return }
        runtime.lastMenuRefreshAt = now
        requestMessageActivityRefresh(includeHistory: true)
    }

    /// `message_unread_summary` 를 받아 반영한다. 함수가 없는 서버·실패는 **조용히** 접고 들고 있던 요약을 지우지 않는다 —
    /// 못 물어봤다는 사실은 "안 읽은 것이 없다"는 답이 아니다(제보 답장 배너와 같은 규약).
    func performLoadMessageUnreadSummary() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        let serial = messageReadRuntime.nextSummarySerial()
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.fetchMessageUnreadSummary(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            guard let summary = response.summary else { return }
            applyMessageUnreadSummary(summary, serial: serial)
        } catch {
            // 취소·스키마 부재(옛 서버)·네트워크 — 전부 조용히. 점은 다음 계기(신호·팝오버 열기)에 다시 맞춰진다.
        }
    }

    /// 요약 반영(순수 상태 전이 — 네트워크 없음). **더 나중에 띄운 요약이 이미 있으면 버린다**(늦게 온 옛 응답).
    func applyMessageUnreadSummary(_ summary: MessageUnreadSummary, serial: Int) {
        if let current = messageUnreadSummary, current.serial > serial { return }
        let next = MessageUnreadSummarySnapshot(serial: serial, summary: summary)
        if messageUnreadSummary != next { messageUnreadSummary = next }
    }

    /// **읽음을 올리는 유일한 판정.** 조건이 전부 맞을 때만 `mark_messages_read` 를 부른다(위 머리 주석 ①):
    ///  · 로그인 · 대화가 **실제로 보인다**(`isMessageConversationSeen` — 대화 패널 · 대화 뷰/팝오버 표시, 창 서버가 "없다"고 하지 않음) · 상대가 골라져 있음
    ///  · 서버가 읽음을 앎(마지막 이력이 읽음 칸을 실어 옴)
    ///  · 그 대화에 서버 기준 안 읽은 받은 메시지가 있고, 같은 경계로 이미 올린(또는 올리는 중인) 기록이 없음
    /// 경계는 **그 대화의 마지막 받은 메시지 id**(서버 순서, 그 뒤에 즉시 삽입된 말은 그 뒤 — `effectiveOrder`)다 — 이력에 없는 말까지
    /// 읽음으로 올리지 않게.
    ///
    /// v0.3.31 M4: 옛 게이트는 `isMenuPresented` 한 칸이었다. 그 칸은 두 출처(팝오버 루트 onAppear·키 창 통지)의 마지막 쓰기라 **떠 있는
    /// 팝오버에서 false 로 남는 순서**가 있고(우리 다른 창이 활성화와 함께 키를 가져가도 팝오버는 안 닫힌다 — CheckWindowAnchor 의 실측 표),
    /// 그 동안 본 메시지가 읽음으로 안 올라가 대화를 닫으면 점이 됐다("이미 읽은 메시지에 점이 자꾸 생긴다").
    func evaluateMessageReadMarking() {
        guard session != nil, isMessageConversationSeen,
              let peer = selectedMessagePeerID,
              let snapshot = messageHistoryReadSnapshot,
              let through = MessageUnreadRules.markTarget(
                  peer: peer,
                  history: messageHistory,
                  snapshot: snapshot,
                  optimistic: messageOptimisticReads[peer]
              )
        else { return }
        markMessagesRead(peer: peer, throughMessageID: through)
    }

    /// 읽음 처리 1회. **상대별로 겹치지 않는다**(날아가는 중이면 끝난 뒤 한 번 더 판정한다).
    ///
    /// 응답 전에 낙관 읽음을 세워 점을 **곧바로** 끈다. 실패해도 되돌리지 않는다 — 그 기록은 "실패로 정산됨"이 되고,
    /// 그보다 나중에 띄운 서버 조회(다음 새로고침)가 사실을 말한다(`MessageUnreadRules`). 성공하면 요약·이력을 한 번 다시 받아
    /// 서버 판정으로 넘어간다.
    func markMessagesRead(peer: String, throughMessageID through: String) {
        guard session != nil, !peer.isEmpty, !through.isEmpty else { return }
        let runtime = messageReadRuntime
        guard !runtime.markInFlight.contains(peer) else {
            runtime.markAgain.insert(peer)
            return
        }
        runtime.markInFlight.insert(peer)
        let optimistic = MessageOptimisticRead(throughID: through, recordedSerial: runtime.nextSerial())
        if messageOptimisticReads[peer] != optimistic { messageOptimisticReads[peer] = optimistic }
        let generation = sessionGeneration
        Task { @MainActor in
            var succeeded = false
            do {
                let response = try await withSessionRetry { activeSession in
                    try await service.markMessagesRead(
                        accessToken: activeSession.accessToken,
                        peerUserID: peer,
                        throughMessageID: through
                    )
                }
                succeeded = response.isOK
            } catch {
                // 취소·네트워크·스키마 부재 — 전부 "이번엔 못 올렸다"다. 낙관 표시는 되돌리지 않는다(위 주석).
            }
            // 로그아웃·계정 전환 뒤 도착한 결과는 새 계정의 장부를 만지지 않는다(그쪽 장부는 이미 새것이다).
            guard generation == sessionGeneration else { return }
            runtime.markInFlight.remove(peer)
            settleOptimisticRead(peer: peer, through: through, succeeded: succeeded)
            // 성공 뒤 새로고침은 **합치기 창**으로 간다(m-fix2): 서버가 읽은 사람 채널(= 이 맥)로 같은 경계의 'message_read' 를
            // 되돌려 보내므로(부록 B-1) 곧바로 쏘면 메아리가 한 번 더 부른다. 점은 낙관 읽음이 이미 껐다 — 1초 늦은 서버 확인은 안 보인다.
            if succeeded { requestMessageActivityRefreshCoalesced() }
            if runtime.markAgain.remove(peer) != nil { evaluateMessageReadMarking() }
        }
    }

    /// 낙관 읽음을 정산한다(서버 왕복이 끝났다). 그 사이 같은 상대에게 더 새 경계가 세워졌으면 건드리지 않는다.
    private func settleOptimisticRead(peer: String, through: String, succeeded: Bool) {
        guard var record = messageOptimisticReads[peer], record.throughID == through, record.settledSerial == nil else {
            return
        }
        record.settledSerial = messageReadRuntime.nextSerial()
        record.failed = !succeeded
        messageOptimisticReads[peer] = record
    }

    /// 근무 시작 drain 으로 들어온 메시지를 **말풍선으로 띄우지 않을 것인가**(v0.3.30).
    /// 서버 기준 이미 읽은 것(`isUnread == false`)이나 로컬 낙관 읽음으로 덮인 것은 띄우지 않는다 — 대화 창에서 읽은 말이
    /// 근무를 시작하는 순간 캐릭터 머리 위로 다시 튀어나오면 그건 알림이 아니라 소음이다.
    /// "서버 기준"은 **서버의 최신 판정**이다(m-fix F3): 이력보다 나중에 띄운 요약이 그 상대 0건이라 말하면(다른 기기에서 읽음)
    /// 점은 꺼져 있는데 말풍선만 뜨는 어긋남이 생기므로 그것도 읽은 것으로 본다.
    func isMessageAlreadyReadForBubble(_ message: ReceivedMessage) -> Bool {
        MessageUnreadRules.isAlreadyRead(
            messageID: message.id,
            history: messageHistory,
            snapshot: messageHistoryReadSnapshot,
            optimistic: messageOptimisticReads,
            summary: messageUnreadSummary
        )
    }
}

// MARK: - 열린 대화에 즉시 (v0.3.31 M4)
//
// 사용자 신고(2026-09-17, 0.3.29): "상대와의 채팅창에 접속해 있는 상태에서 메시지 받으면 그 메시지가 채팅창에 바로 안 뜨고 시간이 좀 지난
// 다음에 뜨거나, 아예 창 뒤로 갔다가 다시 들어와야 뜬다. 실제 메신저앱처럼 메시지마다 바로 대화창에 뜨게."
//
// 서버는 결백했다(운영 실측: 24시간 156건 전부 consumed_at − created_at p95 0.2초). 받는 맥이 받은 **뒤**에 틈이 셋 있었다 —
// 전부 헤드리스 재현(0.3.29 사본 대조군 CtlM4Tests · 수정 전 mobile-int 사본 CtlPreM4Tests, 결과는 V0331MessageArrivalTests 머리)으로 가렸다:
//  ① **보이는가의 판정이 `isMenuPresented` 한 칸이었다.** 그 칸은 팝오버 루트의 onAppear/onDisappear 와 창 키 획득/상실 통지가
//     마지막 쓰기로 겹쳐 쓴다. 우리 다른 창이 활성화와 함께 키를 가져가도 팝오버는 **안 닫힌다**(CheckWindowAnchor 의 실측 표) — 그때 키 상실이
//     false 를 쓰면 그 뒤 도착은 이력 조회를 건너뛰었고, [뒤로] 뒤 다시 들어가야(openMessagePanel 의 무조건 조회) 떴다. 신고의 두 번째 모양이다.
//     (사용자 세션에서 **어느** 순서가 실제로 일어났는지는 실행 중 앱을 재지 못해 확정하지 못했다 — 그래서 한 순서에 맞춰 고치지 않고
//     순서와 무관한 사실로 판정을 바꿨다. 모형은 V0331MessageArrivalTests.)
//  ② **도착한 내용을 대화에 넣지 않고 이력 재조회만 했다.** take_pokes 가 본문을 이미 들고 왔는데 한 왕복을 더 기다렸고, 0.3.29 는
//     겹친 조회의 늦은 옛 응답이 방금 뜬 말을 지웠다(첫 번째 모양 "시간이 좀 지난 다음에").
//  ③ **말풍선용 5분 신선도 필터가 갱신 자체를 막았다.** 맥 시계가 서버보다 5분 넘게 빠르면 도착이 비어 갱신을 안 불렀다.
//
// 그래서: 보이는가는 **대화 뷰 자신의 생명주기 + 팝오버 창의 실제 표시(창 서버)** 로 본다(①). 소비한 메시지 행은 신선도와 무관하게
// 보이는 대화에 **곧바로 넣고** 이력·읽음 재조회로 서버 값에 맞춘다(②③). 판정이 "안 보이는데 보인다"로 틀려도 값은 도착당 이력 1건이다 —
// 그쪽으로 기운다. 단 **읽음 처리**는 창 서버가 "안 떠 있다"고 답하면 올리지 않는다(못 본 말을 읽었다고 상대에게 알리면 거짓이다).

@MainActor
extension WorkTimerStore {
    /// 대화 화면이 **떠 있을 수 있는가** — 도착 갱신(이력 조회)과 즉시 삽입의 게이트. 판정은 `MessageConversationVisibility` 하나다.
    var isMessageConversationOnScreen: Bool {
        MessageConversationVisibility.mayBeOnScreen(currentMessageConversationSignals)
    }

    /// 대화를 **실제로 보고 있는가** — 읽음 처리의 게이트(위보다 엄격: 창 서버가 "없다"고 하면 거짓).
    var isMessageConversationSeen: Bool {
        MessageConversationVisibility.isSeen(currentMessageConversationSignals)
    }

    private var currentMessageConversationSignals: MessageConversationVisibility.Signals {
        MessageConversationVisibility.Signals(
            signedIn: session != nil,
            panelVisible: isMessagePanelVisible,
            conversationViewShown: !messageConversationViewTokens.isEmpty,
            menuPresented: isMenuPresented,
            // 창 서버 질의는 로그인 + 대화 패널일 때만 한다(대화 패널이 아닌 화면에서 도착마다 창 목록을 읽지 않게).
            popoverOnScreen: (session != nil && isMessagePanelVisible) ? menuPopoverOnScreenProbe() : nil
        )
    }

    /// 대화 뷰가 화면에 섰다(`CheckMessageView.onAppear`). 표식을 넣고, 보이는 대화의 안 읽은 말을 읽음으로 올린다(멱등 — 같은 경계는 한 번).
    func messageConversationViewDidAppear(_ token: UUID) {
        messageConversationViewTokens.insert(token)
        evaluateMessageReadMarking()
    }

    /// 대화 뷰가 화면에서 내려갔다(`CheckMessageView.onDisappear`). **자기 표식만** 뺀다 — 다른 뷰의 나타남이 먼저 왔어도 남는다.
    func messageConversationViewDidDisappear(_ token: UUID) {
        messageConversationViewTokens.remove(token)
    }

    /// take_pokes 가 **소비한** 행에서 메시지를 받아들인다(drain 이 부르는 유일한 문, v0.3.31 M4).
    ///
    /// 순서가 뜻이다:
    ///  1. 보이는 대화의 상대가 보낸 행을 **곧바로** 그 대화에 넣는다(`insertConsumedMessagesIntoVisibleConversation`) — 신선도와 무관.
    ///  2. 말풍선 큐에는 예전 그대로 **신선한 것 중 이미 읽지 않은 것만** 올린다(5분 규칙 · 읽은 것 필터).
    ///     1 에서 **보고 있는 대화에 들어가 읽음으로 올라간 말**은 이 필터가 거른다 — 대화창에 방금 뜬 말을 캐릭터 머리 위로 한 번 더
    ///     띄우지 않는다(메신저가 열린 대화의 알림을 안 띄우는 것과 같다). 창 서버가 "안 떠 있다"고 하면 읽음이 안 올라가 말풍선은 그대로 뜬다.
    ///  3. 소비한 메시지 행이 **하나라도** 있으면 도착 새로고침 1회(요약 + 보이면 이력). 말풍선 큐가 비었어도 부른다 — 0.3.29 는 신선도가
    ///     큐를 비우면 갱신까지 건너뛰었다(③).
    func receiveConsumedMessages(rows: [TakenPokeRow], now: Date) {
        let consumed = Self.consumedMessageEntries(rows: rows, receiptsKnown: messageReadReceiptsAvailable)
        insertConsumedMessagesIntoVisibleConversation(consumed)
        appendToMessageBubbleQueue(
            Self.freshReceivedMessages(rows: rows, now: now).filter { !isMessageAlreadyReadForBubble($0) }
        )
        guard !consumed.isEmpty else { return }
        refreshMessageHistoryOnArrival()
    }

    /// 소비한 메시지 행 → 대화 한 줄(순수). 옮김 규칙은 이력 행과 같다(본문 정규화 · 보이는 글자 없음 버림 · 보낸이 없음 버림 · 이름 폴백).
    /// 받은 말이므로 `isUnread` 는 서버가 읽음을 알면 true(방금 왔다), 모르면 nil(옛 서버 — 도장 규칙이 판정한다).
    nonisolated static func consumedMessageEntries(rows: [TakenPokeRow], receiptsKnown: Bool) -> [MessageHistoryEntry] {
        rows.compactMap { row -> MessageHistoryEntry? in
            guard PokeKind(rawServerValue: row.kind) == .message, !row.id.isEmpty, !row.fromUser.isEmpty else { return nil }
            let body = MessageBody.sanitized(row.body ?? "")
            guard MessageBody.hasVisibleContent(body) else { return nil }
            return MessageHistoryEntry(
                id: row.id,
                peerUserID: row.fromUser,
                peerName: row.fromDisplayName.isEmpty ? "사용자" : row.fromDisplayName,
                peerAvatarURL: row.fromAvatarUrl.flatMap { URL(string: $0) },
                body: body,
                createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdEpoch)),
                isMine: false,
                readByPeer: nil,
                isUnread: receiptsKnown ? true : nil
            )
        }
    }

    /// 보이는 대화의 상대가 보낸 것만 **지금** 이력에 넣는다. 반환값은 넣은 개수.
    ///
    /// · 다른 사람의 말·닫힌 대화는 넣지 않는다 — 그쪽은 도착 새로고침이 요약(점)으로 알리고, 이력은 볼 때 받는다(서버 판이 정본).
    /// · 이미 있는 id 는 건드리지 않는다(서버 행이 이긴다 — 중복도 없다).
    /// · 정렬은 이력 응답과 **같은 규칙**(`sortedForMessageHistory`, 서버 순서를 모르는 새 id 는 같은 초 안에서 뒤)이다.
    /// · 넣은 id 는 장부에 "넣은 순간의 일련번호"로 적는다 — 그보다 먼저 띄운 이력 응답이 이 말을 지우지 않게(`survivingLocalArrivals`).
    /// · 넣은 뒤 곧바로 읽음 판정을 돈다(보고 있는 대화의 말이다 — 기존 규칙 그대로 `evaluateMessageReadMarking`).
    @discardableResult
    func insertConsumedMessagesIntoVisibleConversation(_ entries: [MessageHistoryEntry]) -> Int {
        guard !entries.isEmpty, isMessageConversationOnScreen, let peer = selectedMessagePeerID else { return 0 }
        var known = Set(messageHistory.map(\.id))
        var additions: [MessageHistoryEntry] = []
        for entry in entries where entry.peerUserID == peer && !known.contains(entry.id) {
            known.insert(entry.id)
            additions.append(entry)
        }
        guard !additions.isEmpty else { return 0 }
        let serial = messageReadRuntime.nextSerial()
        for entry in additions { messageReadRuntime.localArrivalSerials[entry.id] = serial }
        let merged = (messageHistory + additions).sortedForMessageHistory(serverOrder: messageHistoryReadSnapshot?.serverOrder)
        if messageHistory != merged { messageHistory = merged }
        evaluateMessageReadMarking()
        return additions.count
    }
}

/// 대화 화면이 보이는가의 **순수 판정**(v0.3.31 M4). 입력은 사실들, 출력은 두 질문의 답이다.
///
/// 사실은 셋이고 각자 틀리는 방향이 다르다:
///  · `menuPresented`(`isMenuPresented`) — 두 출처의 마지막 쓰기. **떠 있는데 false** 로 남는 순서가 있다(키 상실만 오고 팝오버는 그대로).
///  · `conversationViewShown`(대화 뷰의 onAppear/onDisappear 표식 집합) — 순서에 강하다. 다만 앱 비활성으로 팝오버가 화면에서만 사라지고
///    SwiftUI 가 모르는 경로에서는 **안 보이는데 true** 로 남을 수 있다.
///  · `popoverOnScreen`(창 서버 질의) — 이 저장소가 믿는 사실(`NSWindow.isVisible` 이 거짓말한 전례). 창을 못 잡으면 nil.
enum MessageConversationVisibility {
    /// 상대(`selectedMessagePeerID`)는 여기서 보지 않는다 — 대화 패널은 상대 없이 열리지 않고(`openMessagePanel(peer:)`),
    /// 상대가 필요한 두 자리(즉시 삽입·읽음 처리)는 각자 그 상대를 꺼내며 확인한다.
    struct Signals: Equatable, Sendable {
        var signedIn: Bool
        var panelVisible: Bool
        var conversationViewShown: Bool
        var menuPresented: Bool
        var popoverOnScreen: Bool?
    }

    /// 떠 있을 수 있는가(도착 갱신 · 즉시 삽입). **긍정 신호 하나면 참**이다 — 틀려도 값은 도착당 이력 1건이고, 거짓으로 틀리면 신고 그대로
    /// "다시 들어가야 뜬다"가 된다. 대화 패널·로그인은 필수(닫힌 대화에 조회를 붙이지 않는다).
    static func mayBeOnScreen(_ s: Signals) -> Bool {
        guard s.signedIn, s.panelVisible else { return false }
        return s.conversationViewShown || s.menuPresented || s.popoverOnScreen == true
    }

    /// 실제로 보고 있는가(읽음 처리). 위가 참이고 **창 서버가 "안 떠 있다"고 하지 않을 때**만 참이다 — 못 본 말을 읽었다고 올리면
    /// 상대 화면의 1 이 지워지고 이 맥의 점도 안 뜬다(되돌릴 길이 없다). 창 서버가 모르면(nil) 생명주기 신호를 믿는다.
    static func isSeen(_ s: Signals) -> Bool {
        mayBeOnScreen(s) && s.popoverOnScreen != false
    }
}

// MARK: - 읽음 값 타입 · 규칙 (순수)

/// 이력 한 번의 결과(v0.3.30). `entries` 는 **서버 순서 그대로**다.
struct MessageHistoryLoad: Sendable {
    let entries: [MessageHistoryEntry]
    /// 읽음 칸을 실어 온 응답인가(`message_history_with_reads` 성공).
    let hasReadReceipts: Bool

    /// 메시지 id → 서버 응답 안의 자리(0부터, 같은 id 는 처음 자리). 스냅샷과 화면 정렬(F7)이 같은 표를 쓴다.
    var serverOrder: [String: Int] {
        var order: [String: Int] = [:]
        for (index, entry) in entries.enumerated() where order[entry.id] == nil {
            order[entry.id] = index
        }
        return order
    }
}

/// 읽음 칸을 실어 온 이력 한 번의 사실: 그 요청의 일련번호와 서버가 준 순서.
struct MessageHistoryReadSnapshot: Equatable, Sendable {
    /// 요청을 띄운 순간의 일련번호(`MessageReadRuntime.nextSerial`). 요약·낙관 읽음과 선후를 가르는 근거다.
    let serial: Int
    /// 메시지 id → 서버 응답 안의 자리(0부터). 같은 초 안의 선후는 이것만 안다(`created_epoch` 은 초 단위다).
    let serverOrder: [String: Int]
}

/// 안 읽음 요약 한 번의 사실.
struct MessageUnreadSummarySnapshot: Equatable, Sendable {
    let serial: Int
    let summary: MessageUnreadSummary
}

/// 상대 하나에 대한 낙관 읽음 — "이 id 까지 읽었다고 서버에 말했다(또는 말하는 중이다)".
struct MessageOptimisticRead: Equatable, Sendable {
    let throughID: String
    /// 기록을 세운 순간의 일련번호.
    let recordedSerial: Int
    /// 서버 왕복이 끝난(성공·실패 모두) 순간의 일련번호. nil = 아직 날아가는 중.
    var settledSerial: Int? = nil
    /// 왕복이 실패로 끝났는가. 실패한 기록은 같은 경계로 다시 올릴 수 있다(markTarget).
    var failed = false

    /// 일련번호 `serial` 로 띄운 서버 조회가 **이 기록을 이미 반영한 서버 상태**를 봤는가.
    /// 정산 뒤에 띄운 조회만 그렇다 — 그 전에 띄운 조회(날아가는 중 포함)는 서버가 아직 모를 수 있다.
    func isKnown(bySnapshotSerial serial: Int) -> Bool {
        guard let settledSerial else { return false }
        return serial > settledSerial
    }
}

/// 읽음 절의 비관찰 장부. 스토어의 `messageReadRuntime` 하나로 들고, 로그아웃이 통째로 새것으로 바꾼다.
@MainActor
final class MessageReadRuntime {
    /// 요청·정산 순서의 단조 증가 번호. 응답 도착 순서가 아니라 **띄운 순서**가 서버 상태의 순서다.
    private(set) var serial = 0
    /// 마지막으로 반영한 이력 요청의 번호(늦게 온 옛 이력이 새 이력을 덮지 않게).
    var lastAppliedHistorySerial = 0
    var activityTask: Task<Void, Never>?
    var activityAgain = false
    var activityWantsHistory = false
    var lastMenuRefreshAt: Date = .distantPast
    var markInFlight: Set<String> = []
    var markAgain: Set<String> = []
    /// 새로고침이 **이력을 건너뛴** 마지막 순간의 일련번호(m-fix F1). nil = 그 뒤에 띄운 이력이 반영됐다(낡지 않았다).
    /// 볼 사람이 없어 건너뛴 계기(닫힌 팝오버에 온 읽음·새 말)를, 대화가 보이는 채로 팝오버를 다시 열 때 스로틀과 무관하게 받는 근거다.
    private(set) var historyStaleSerial: Int?
    /// 스로틀 우회를 **다 쓴** 낡음 표시(m-fix2 · m-reverify R3). 그 표시보다 나중에 띄운 이력 조회가 실패로 끝났을 때 적힌다 —
    /// 같은 표시로는 다시 우회하지 않는다. 새 계기는 더 큰 번호로 표시를 옮기므로 다시 한 번 우회한다.
    private(set) var staleBypassSpentSerial: Int?
    /// 합치기 창(m-fix2 · 부록 B-2). nil = 열린 창 없음.
    var activityWindowTask: Task<Void, Never>?
    /// 창에 모인 **마지막 계기**의 순간(그때의 `serial`). 이보다 나중에 띄운 조회만 그 계기를 반영한다.
    var activityWindowSerial = 0
    /// 마지막으로 **띄운**(응답 여부와 무관) 요약·이력 요청의 번호. 창이 닫힐 때 "이미 맡은 조회가 있나"의 근거다.
    private(set) var lastSummaryLaunchSerial = 0
    private(set) var lastHistoryLaunchSerial = 0
    /// 보이는 대화에 **즉시 삽입한** 도착분(v0.3.31 M4): 메시지 id → 넣은 순간의 일련번호.
    /// 그보다 **먼저 띄운** 이력 응답은 그 말을 모를 수 있으므로 판을 갈 때 이 말을 남기고, **나중에 띄운** 응답이 오면 서버가 이긴다.
    var localArrivalSerials: [String: Int] = [:]

    nonisolated init() {}

    /// 일련번호 `historySerial` 로 띄운 이력 응답(`server`)을 반영할 때 **남겨야 할 즉시 삽입분**을 고르고 장부를 정리한다.
    ///  · 응답에 같은 id 가 있으면 → 서버 행이 이긴다(장부에서 뺀다).
    ///  · 응답이 삽입보다 **나중에** 띄운 것인데 없으면 → 서버가 답했다(보관 창 밖 등). 장부에서 빼고 남기지 않는다.
    ///  · 응답이 삽입보다 **먼저** 띄운 것이면 → 그 조회는 이 말을 모를 수 있다. 지금 이력에 있는 그 줄을 남긴다.
    func survivingLocalArrivals(
        historySerial: Int,
        current: [MessageHistoryEntry],
        server: [MessageHistoryEntry]
    ) -> [MessageHistoryEntry] {
        guard !localArrivalSerials.isEmpty else { return [] }
        let serverIDs = Set(server.map(\.id))
        var keepIDs: Set<String> = []
        for (id, inserted) in localArrivalSerials {
            if serverIDs.contains(id) || historySerial > inserted {
                localArrivalSerials[id] = nil
            } else {
                keepIDs.insert(id)
            }
        }
        guard !keepIDs.isEmpty else { return [] }
        var seen: Set<String> = []
        return current.filter { keepIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    func nextSerial() -> Int {
        serial += 1
        return serial
    }

    /// 요약 요청을 띄운다(번호를 받고 "띄움"을 적는다).
    func nextSummarySerial() -> Int {
        let next = nextSerial()
        lastSummaryLaunchSerial = next
        return next
    }

    /// 이력 요청을 띄운다(번호를 받고 "띄움"을 적는다).
    func nextHistorySerial() -> Int {
        let next = nextSerial()
        lastHistoryLaunchSerial = next
        return next
    }

    /// 이번 계기가 이력을 건너뛰었다. 지금까지의 번호로 적는다 — 이보다 **나중에 띄운** 이력만 이 표시를 지운다.
    func markHistoryStale() {
        historyStaleSerial = serial
    }

    /// 일련번호 `appliedSerial` 로 띄운 이력이 반영됐다. 낡음 표시보다 나중에 띄운 것이면 지운다(먼저 띄운 늦은 응답은 못 지운다).
    func clearHistoryStale(appliedSerial: Int) {
        guard let stale = historyStaleSerial, appliedSerial > stale else { return }
        historyStaleSerial = nil
    }

    /// 일련번호 `failedSerial` 로 띄운 이력이 실패로 끝났다(5xx·네트워크). 낡음 표시보다 나중에 띄운 것이면 그 표시의 우회를 다 썼다
    /// (먼저 띄운 조회의 실패는 이 표시를 맡은 적이 없으니 우회를 빼앗지 않는다 — `clearHistoryStale` 과 같은 비교).
    func noteHistoryFailed(serial failedSerial: Int) {
        guard let stale = historyStaleSerial, failedSerial > stale else { return }
        staleBypassSpentSerial = stale
    }

    /// 팝오버 열기가 이 낡음 표시로 60초 스로틀을 건너뛸 수 있는가(표시가 있고, 그 표시의 우회를 아직 안 썼다).
    var staleHistoryMayBypassThrottle: Bool {
        guard let stale = historyStaleSerial else { return false }
        return stale != staleBypassSpentSerial
    }

    /// 로그아웃에서 부른다. 도는 새로고침과 열린 합치기 창은 끊는다(세대 가드가 결과를 버리지만 왕복 자체를 줄인다).
    func cancelAll() {
        activityTask?.cancel()
        activityTask = nil
        activityWindowTask?.cancel()
        activityWindowTask = nil
    }
}

/// 안 읽음·읽음 경계·말풍선 필터의 **순수 규칙.** 스토어와 테스트가 같은 표를 읽는다.
enum MessageUnreadRules {
    /// 안 읽은 것이 있는 상대들.
    ///  1. 서버 스냅샷(이력의 읽음 칸 · 요약) 중 **더 나중에 띄운 쪽**을 쓴다. 둘 다 없으면 옛 규칙(도장 시각)이다.
    ///  2. 그 스냅샷이 모르는 낙관 읽음(정산 전이거나 정산보다 먼저 띄운 조회)은 뺀다.
    ///     이력은 id 로 덮였는지 본다(경계 뒤에 온 새 말은 남는다). 요약은 id 를 모르므로 그 상대를 통째로 뺀다 —
    ///     읽음 처리 성공 뒤의 새로고침(정산 뒤에 띄운 조회)이 곧 사실로 되돌린다.
    static func unreadPeerIDs(
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
    static func legacyUnreadPeerIDs(history: [MessageHistoryEntry], stamps: [String: Date]) -> Set<String> {
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
    static func markTarget(
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
    static func isAlreadyRead(
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
    /// 이력에 아예 없는 id(만료로 사라진 경계 등)는 여전히 표에 없다 — `isCovered` 의 "경계를 못 찾으면 덮이지 않음"이 그대로 산다.
    /// 모르는 id 가 없으면 서버 순서를 그대로 돌려준다(뷰가 자주 읽는 점 계산에서 복사를 만들지 않게).
    static func effectiveOrder(history: [MessageHistoryEntry], serverOrder: [String: Int]) -> [String: Int] {
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
    static func isCovered(_ entry: MessageHistoryEntry, by record: MessageOptimisticRead, order: [String: Int]) -> Bool {
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
    func sortedForMessageHistory(serverOrder: [String: Int]? = nil) -> [MessageHistoryEntry] {
        sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            if let serverOrder {
                let l = serverOrder[lhs.id] ?? Int.max
                let r = serverOrder[rhs.id] ?? Int.max
                if l != r { return l < r }
            }
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
    /// `serverOrder` 는 같은 초 동률을 깨는 서버 순서다(`sortedForMessageHistory` — 모르면 nil, 옛 규칙 id).
    static func threads(from entries: [MessageHistoryEntry], serverOrder: [String: Int]? = nil) -> [MessageThread] {
        var order: [String] = []
        var grouped: [String: [MessageHistoryEntry]] = [:]
        for entry in entries.sortedForMessageHistory(serverOrder: serverOrder) {
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

    /// 구분선 문구. 24시간 창이라 실제로 나오는 것은 "오늘"과 "어제"뿐이지만, 자정을 낀 조회에서
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

    // ★ `listStampText` 와 `previewText` 는 v0.2.50 에 **왼쪽 대화 목록과 함께 사라졌다.**
    //   둘 다 그 목록의 한 행(마지막 시각 · 한 줄 미리보기)만을 위한 계산이었고, 화면이 한 사람짜리가
    //   되면서 부르는 곳이 한 곳도 남지 않았다. 테스트만 남겨 두면 **아무도 안 쓰는 함수를 지키는 테스트**가
    //   되므로 그쪽도 함께 걷었다(이 저장소는 죽은 가지를 남기지 않는다).
    //   되살려야 할 날이 오면 `dayLabel`/`clockText` 위에 다시 세우면 된다 — 그 둘은 살아 있다.
}
