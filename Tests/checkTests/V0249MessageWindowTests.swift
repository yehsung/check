import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.49 메시지 창 — 순수 경계(길이·묶음·구분선·정렬) · 스토어 왕복 · 쿨타임 부재의 소스 계약 · 렌더 스냅샷.
//
// 사용자 요청(2026-09-10): "메시지 보낼 때 그 순간에 못 보면 내용을 못 보잖아. …
//   시간과 함께 주고받은 순서대로. 12시간 지나면 순차적으로 사라지게. 메시지랑 찌르기는 아예 분리야.
//   찌르기만 60초 쿨타임 있고 메시지는 쿨타임 없이 갈 거야. 진짜 메신저 앱처럼. 3글자 제한도 없애줘."
//
// ★ 이 파일의 픽스처 본문은 전부 **합성 문자열**이다. 실제 대화를 픽스처로 옮겨 오지 마라 —
//   테스트 파일은 퍼블릭 저장소에 남고, 두 사람이 주고받은 문장은 남에게 보여 주려고 쓴 것이 아니다.
//
// 네트워크는 `FeedbackURLProtocol`(테스트별 고유 호스트, 경로별 상태코드)로 격리한다 — 스키마 부재(404)를
// 심어야 해서 공용 `URLProtocolStub` 으로는 부족하다. 스텁을 또 만들지 않고 그것을 재사용한다.

private let mwUserID = "00000000-0000-0000-0000-0000000000a1"
private let mwHistoryPath = "/rest/v1/rpc/message_history"
private let mwSendPath = "/rest/v1/rpc/send_message"

// MARK: - 헬퍼

@MainActor
private func mwDefaults() -> UserDefaults {
    let suite = "v0249-message-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 스텁 네트워크에 물린 스토어. 시계는 **얼려서** 꽂는다 — 읽음 도장·정렬 단언이 벽시계에 흔들리면
/// 부하 큰 병렬 실행에서 무음으로 뒤집힌다(이 저장소의 실측 회귀).
@MainActor
private func mwStore(host: String, signedIn: Bool = true, working: Bool = true) -> WorkTimerStore {
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: mwDefaults()
    )
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: mwUserID)
    }
    store.clock = { mwNow }
    if working { store.startedAt = mwNow.addingTimeInterval(-3_600) }
    return store
}

/// 얼린 기준 시각(2026-09-10 화요일 14:30 UTC 부근). 값 자체에 뜻은 없고 **변하지 않는다는 사실**만 쓴다.
private let mwNow = Date(timeIntervalSince1970: 1_789_000_000)

@MainActor
private func mwWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<300 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 이력 픽스처 한 건. `minutesAgo` 로 시각을 잡아 정렬·구분선 단언이 벽시계와 무관하게 고정된다.
private func mwEntry(
    id: String,
    peer: String,
    name: String? = nil,
    body: String,
    minutesAgo: Double,
    isMine: Bool = false,
    avatar: URL? = nil
) -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id,
        peerUserID: peer,
        peerName: name ?? "상대\(peer)",
        peerAvatarURL: avatar,
        body: body,
        createdAt: mwNow.addingTimeInterval(-minutesAgo * 60),
        isMine: isMine
    )
}

/// `message_history` 응답 JSON 한 줄.
private func mwRowJSON(id: String, peer: String, name: String, body: String, epoch: Int, isMine: Bool) -> String {
    """
    {"id":"\(id)","from_user":"\(isMine ? mwUserID : peer)","to_user":"\(isMine ? peer : mwUserID)",
     "body":"\(body)","created_at":null,"is_mine":\(isMine),"peer_user_id":"\(peer)",
     "peer_display_name":"\(name)","peer_avatar_url":null,"created_epoch":\(epoch)}
    """
}

// MARK: - 순수: 길이 경계 (코드포인트)

@Test
func messageLengthBoundariesAreCountedInCodePoints() {
    // 0 / 1 / 200 / 201 — **서버와 같은 눈금**(unicodeScalars)으로 잰다.
    #expect(MessageBody.validate("") == .empty)
    #expect(MessageBody.length("가") == 1)
    let full = String(repeating: "가", count: 200)
    #expect(MessageBody.validate(full) == .ok(full))
    #expect(MessageBody.validate(full + "가") == .tooLong(maxLength: 200))

    // ★ 이모지가 이 눈금의 존재 이유다. 자소로 세면 아래 셋이 전부 "1"이라, 화면은 여유가 있다고 말하는데
    //   서버만 too_long 으로 거절한다 — 사용자가 원인을 알 수 없는 종류의 버그.
    #expect("👨‍👩‍👧‍👦".count == 1 && MessageBody.length("👨‍👩‍👧‍👦") == 7)
    #expect("🇰🇷".count == 1 && MessageBody.length("🇰🇷") == 2)
    // 👍🏻 = 👍(U+1F44D) + 스킨톤(U+1F3FB) 두 코드포인트(자소로는 1).
    #expect("👍🏻".count == 1 && MessageBody.length("👍🏻") == 2)

    // 가족 이모지 28개 = 196 코드포인트(통과) / 29개 = 203(초과). 자소로 셌다면 둘 다 통과했을 자리다.
    let family = String(repeating: "👨‍👩‍👧‍👦", count: 28)
    #expect(MessageBody.length(family) == 196)
    #expect(MessageBody.validate(family) == .ok(family))
    #expect(MessageBody.validate(family + "👨‍👩‍👧‍👦") == .tooLong(maxLength: 200))
}

// MARK: - 순수: 대화 상대 묶음

@MainActor
@Test
func historyGroupsIntoThreadsSortedByRecency() {
    // 서버는 오래된 것부터 주지만 **묶음은 최근 대화순**이어야 한다(메신저의 왼쪽 목록이 그렇다).
    let entries = [
        mwEntry(id: "a1", peer: "u1", name: "영식", body: "안녕", minutesAgo: 300),
        mwEntry(id: "b1", peer: "u2", name: "민수", body: "점심?", minutesAgo: 200),
        mwEntry(id: "a2", peer: "u1", name: "영식", body: "응", minutesAgo: 100, isMine: true),
        mwEntry(id: "c1", peer: "u3", name: "지현", body: "회의 자료 보냈어요", minutesAgo: 500)
    ]

    let threads = MessageThreadBuilder.threads(from: entries)

    // u1 의 마지막이 100분 전으로 가장 새롭다 → 맨 위.
    #expect(threads.map(\.peerUserID) == ["u1", "u2", "u3"])
    // 각 대화 안은 **시간순**(오래된 것 → 최신)이다.
    #expect(threads[0].messages.map(\.id) == ["a1", "a2"])
    #expect(threads[0].lastMessage?.id == "a2")
    #expect(threads[0].peerName == "영식")
    // 한 사람의 말이 두 묶음으로 갈리지 않는다(묶음 키는 peerUserID 하나다).
    #expect(threads.map(\.messages.count) == [2, 1, 1])
}

@MainActor
@Test
func threadNameFollowsTheMostRecentRowSoRenamesDoNotSplitPeople() {
    // 별명을 바꾼 사람의 옛 행이 목록에 옛 이름을 남기면 사용자는 같은 사람을 두 사람으로 읽는다.
    let entries = [
        mwEntry(id: "old", peer: "u1", name: "옛이름", body: "안녕", minutesAgo: 300),
        mwEntry(id: "new", peer: "u1", name: "새이름", body: "반가워", minutesAgo: 10)
    ]

    let threads = MessageThreadBuilder.threads(from: entries)

    #expect(threads.count == 1)
    #expect(threads[0].peerName == "새이름")
}

@MainActor
@Test
func threadOrderIsDeterministicWhenTimesTie() {
    // 동점을 id 로 깨지 않으면 새로고침마다 목록 순서가 흔들린다(사용자는 그걸 버그로 읽는다).
    let entries = [
        mwEntry(id: "z", peer: "z-peer", body: "안녕", minutesAgo: 5),
        mwEntry(id: "a", peer: "a-peer", body: "안녕", minutesAgo: 5)
    ]

    #expect(MessageThreadBuilder.threads(from: entries).map(\.peerUserID) == ["a-peer", "z-peer"])
    #expect(MessageThreadBuilder.threads(from: entries.reversed()).map(\.peerUserID) == ["a-peer", "z-peer"])
}

// MARK: - 순수: 시간순 정렬 · 날짜 구분선

@MainActor
@Test
func historyIsAlwaysReorderedByTimeRegardlessOfServerOrder() {
    // 순서가 곧 사용자가 읽는 순서다 — 뒤집히면 대화가 거꾸로 재생된다.
    let entries = [
        mwEntry(id: "c", peer: "u1", body: "셋", minutesAgo: 1),
        mwEntry(id: "a", peer: "u1", body: "하나", minutesAgo: 30),
        mwEntry(id: "b", peer: "u1", body: "둘", minutesAgo: 10)
    ]

    #expect(entries.sortedForMessageHistory().map(\.id) == ["a", "b", "c"])
}

@MainActor
@Test
func dateSeparatorsAreInsertedWhereTheDayChanges() {
    // 12시간 창이라 실제로 나오는 것은 "오늘"과 "어제"뿐이지만, 자정을 낀 조회에서 날짜가 바뀌는 것을
    // 사람이 읽을 수 있어야 한다.
    let calendar = Calendar.current
    let yesterday = calendar.date(byAdding: .day, value: -1, to: mwNow)!
    let entries = [
        MessageHistoryEntry(id: "y1", peerUserID: "u1", peerName: "영식", peerAvatarURL: nil,
                            body: "어제 말", createdAt: yesterday, isMine: false),
        MessageHistoryEntry(id: "y2", peerUserID: "u1", peerName: "영식", peerAvatarURL: nil,
                            body: "어제 답", createdAt: yesterday.addingTimeInterval(60), isMine: true),
        mwEntry(id: "t1", peer: "u1", name: "영식", body: "오늘 말", minutesAgo: 30)
    ]

    let items = MessageThreadBuilder.timeline(entries, now: mwNow, calendar: calendar)

    // ★ **첫 항목 앞에도 구분선이 선다.** 없으면 맨 위 말풍선이 언제 것인지 알 방법이 시각(HH:mm)뿐인데,
    //   그건 날짜를 말하지 않는다.
    #expect(items.count == 5)
    if case .day(_, let first) = items[0] { #expect(first == "어제") } else { Issue.record("첫 항목이 구분선이 아니다") }
    if case .bubble(let b) = items[1] { #expect(b.id == "y1") } else { Issue.record("두 번째가 말풍선이 아니다") }
    if case .bubble(let b) = items[2] { #expect(b.id == "y2") } else { Issue.record("같은 날인데 구분선이 또 섰다") }
    if case .day(_, let second) = items[3] { #expect(second == "오늘") } else { Issue.record("날이 바뀌었는데 구분선이 없다") }
    if case .bubble(let b) = items[4] { #expect(b.id == "t1") } else { Issue.record("마지막이 말풍선이 아니다") }

    // 구분선 id 는 날짜 키에서 나온다(같은 날이 두 번 서면 ForEach 가 id 충돌로 화면을 흔든다).
    #expect(Set(items.map(\.id)).count == items.count)

    // 같은 날만 있으면 구분선은 정확히 하나다.
    let sameDay = MessageThreadBuilder.timeline(
        [mwEntry(id: "a", peer: "u1", body: "하나", minutesAgo: 30),
         mwEntry(id: "b", peer: "u1", body: "둘", minutesAgo: 10)],
        now: mwNow, calendar: calendar
    )
    #expect(sameDay.count == 3)
}

@MainActor
@Test
func clockAndListStampsAreFixedTo24HourForm() {
    // 지역 설정이 "오후 2:05"를 만들면 말풍선·목록 폭이 사람마다 달라진다 — 이 창은 그 폭을 예산으로 쓴다.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let afternoon = Date(timeIntervalSince1970: 1_789_000_000)   // KST 어느 오후
    let text = MessageThreadBuilder.clockText(afternoon, calendar: calendar)
    #expect(text.count == 5 && text.contains(":"))
    #expect(!text.contains("오후") && !text.contains("PM"))

    // 목록 도장: 오늘 것은 시각, 그전 것은 날짜 라벨(180pt 폭에 둘을 다 적을 자리가 없다).
    #expect(MessageThreadBuilder.listStampText(afternoon, now: afternoon, calendar: calendar) == text)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: afternoon)!
    #expect(MessageThreadBuilder.listStampText(yesterday, now: afternoon, calendar: calendar) == "어제")
}

@MainActor
@Test
func listPreviewFlattensNewlinesSoTheRowNeverGrows() {
    // 여러 줄 입력을 받는 창이라, 눕히지 않으면 미리보기가 첫 줄만 남고 나머지 폭이 빈다.
    #expect(MessageThreadBuilder.previewText("첫 줄\n둘째 줄") == "첫 줄 둘째 줄")
    #expect(MessageThreadBuilder.previewText("  앞뒤 공백  ") == "앞뒤 공백")
    #expect(MessageThreadBuilder.previewText("탭\t끼움") == "탭 끼움")
}

// MARK: - 스토어: 창 열고 닫기 · 선택 · 읽음

@MainActor
@Test
func openingTheWindowSelectsTheRequestedPeerAndMarksItRead() async {
    let store = mwStore(host: "mw-open-peer")
    store.messageHistory = [
        mwEntry(id: "a", peer: "u1", name: "영식", body: "안녕", minutesAgo: 30),
        mwEntry(id: "b", peer: "u2", name: "민수", body: "점심?", minutesAgo: 5)
    ]
    // 열기 전에는 둘 다 안 읽음이다(도장이 없다).
    #expect(store.unreadMessagePeerIDs == ["u1", "u2"])

    store.openMessageWindow(peer: "u1")

    #expect(store.isMessageWindowVisible)
    #expect(store.selectedMessagePeerID == "u1")
    // 고른 대화만 읽음이 된다 — 창을 열었다고 남의 대화까지 읽은 것으로 치면 점이 아무 뜻도 없어진다.
    #expect(store.unreadMessagePeerIDs == ["u2"])
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["a"])
}

@MainActor
@Test
func openingWithoutAPeerFallsBackToTheMostRecentThread() {
    // 빈 오른쪽 판으로 시작하면 사용자가 할 일이 한 번 더 는다.
    let store = mwStore(host: "mw-open-default")
    store.messageHistory = [
        mwEntry(id: "a", peer: "u1", body: "옛말", minutesAgo: 300),
        mwEntry(id: "b", peer: "u2", body: "새말", minutesAgo: 5)
    ]

    store.openMessageWindow()

    #expect(store.selectedMessagePeerID == "u2")
}

@MainActor
@Test
func switchingPeerClearsTheDraftSoWordsNeverGoToTheWrongPerson() {
    // 앞사람에게 쓰던 말이 뒷사람 칸에 남아 나가면 그게 곧 사고다(200자가 된 지금 값만 커졌다).
    let store = mwStore(host: "mw-switch-peer")
    store.messageHistory = [
        mwEntry(id: "a", peer: "u1", body: "안녕", minutesAgo: 30),
        mwEntry(id: "b", peer: "u2", body: "안녕", minutesAgo: 20)
    ]
    store.selectMessagePeer("u1")
    store.messageDraft = "u1 에게 쓰던 말"
    store.messageNotice = WorkTimerStore.messageSentNotice

    store.selectMessagePeer("u2")

    #expect(store.messageDraft == "")
    // 앞사람에게서 받은 결과 문구도 함께 내린다 — 다른 대화 위에 남으면 무엇에 대한 말인지 알 수 없다.
    #expect(store.messageNotice == nil)
}

@MainActor
@Test
func closingTheWindowKeepsTheDraft() {
    // 창을 잘못 닫았다고 쓰던 말이 사라지면 사용자는 그 말을 다시 못 쓴다(제보 창과 같은 규약).
    let store = mwStore(host: "mw-close-draft")
    store.isMessageWindowVisible = true
    store.messageDraft = "쓰다 만 말"

    store.closeMessageWindow()

    #expect(!store.isMessageWindowVisible)
    #expect(store.messageDraft == "쓰다 만 말")
}

// MARK: - 스토어: 이력 왕복

@MainActor
@Test
func historyLoadsAndSortsAndAsksForTwelveHours() async {
    let host = "mw-history-load"
    let store = mwStore(host: host)
    let epoch = Int(mwNow.timeIntervalSince1970)
    FeedbackURLProtocol.set(
        .init(body: "[\(mwRowJSON(id: "b", peer: "u1", name: "영식", body: "둘", epoch: epoch - 60, isMine: true))," +
                    "\(mwRowJSON(id: "a", peer: "u1", name: "영식", body: "하나", epoch: epoch - 600, isMine: false))]"),
        host: host, path: mwHistoryPath
    )

    store.loadMessageHistory()
    await mwWait { store.messageHistoryLoaded }

    #expect(store.messageHistory.map(\.id) == ["a", "b"], "서버가 뒤섞어 줘도 시각으로 다시 세워야 한다")
    #expect(store.messageHistory.map(\.isMine) == [false, true])
    #expect(!store.messageHistoryFailed)
    #expect(!store.messageHistoryLoading)
    // 요청은 화면이 약속한 창(12시간)을 그대로 싣는다 — 기본값에 기대면 서버가 바꾼 날 안내가 거짓이 된다.
    let sent = FeedbackURLProtocol.sentBodies(host: host, path: mwHistoryPath).first ?? ""
    #expect(sent.contains("\"p_hours\":12"))
    #expect(sent.contains("\"p_limit\":200"))
}

@MainActor
@Test
func historyIsANoOpWithoutASession() async {
    let host = "mw-history-signed-out"
    let store = mwStore(host: host, signedIn: false)

    store.loadMessageHistory()
    try? await Task.sleep(for: .milliseconds(40))

    #expect(FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 0)
    #expect(!store.messageHistoryLoaded)
    #expect(!store.messageHistoryFailed)
}

@MainActor
@Test
func missingSchemaFoldsQuietlyInsteadOfPaintingTheWindowRed() async {
    // 브루 배포가 db push 보다 앞선 창: 실패가 아니라 '아직 함수가 없다'. 여기서 빨갛게 칠하면
    // 그 며칠 동안 모두가 "앱이 고장 났다"고 제보한다 — 제보 화면에서(제보 목록이 세운 관례).
    let host = "mw-history-schema-missing"
    let store = mwStore(host: host)
    // ★ 문구가 "in the schema cache" 로 끝나야 서비스가 `.databaseSchemaMissing` 으로 분류한다
    //   (SupabaseWorkHTTP 의 판정이 코드가 아니라 그 문장을 본다). 실제 PostgREST 응답이 이 모양이다.
    FeedbackURLProtocol.set(
        .init(
            status: 404,
            body: #"{"code":"PGRST202","message":"Could not find the function public.message_history(p_hours, p_limit) in the schema cache"}"#
        ),
        host: host, path: mwHistoryPath
    )

    store.loadMessageHistory()
    await mwWait { store.messageHistoryLoaded }

    #expect(store.messageHistory.isEmpty)
    #expect(!store.messageHistoryFailed, "스키마 부재를 실패로 칠했다")
    #expect(!store.messageHistoryLoading)
}

@MainActor
@Test
func realFailureIsMarkedSoTheWindowCanOfferRetry() async {
    let host = "mw-history-boom"
    let store = mwStore(host: host)
    FeedbackURLProtocol.set(.init(status: 500, body: #"{"message":"boom"}"#), host: host, path: mwHistoryPath)

    store.loadMessageHistory()
    await mwWait { store.messageHistoryFailed }

    #expect(store.messageHistoryFailed)
    #expect(!store.messageHistoryLoading)
}

@MainActor
@Test
func arrivingMessagesRefreshHistoryOnlyWhileTheWindowIsOpen() async {
    // ★ **"창을 열어 둔 채로 오면 그 자리에서 나타난다"의 근거다.** 새 타이머를 만들지 않고 이미 도는
    //   수신 폴링(15초)에 얹었다 — 그리고 창이 닫혀 있으면 왕복을 내지 않는다(무료 플랜).
    let host = "mw-arrival-refresh"
    let store = mwStore(host: host)
    FeedbackURLProtocol.set(.init(body: "[]"), host: host, path: mwHistoryPath)

    // 창이 닫혀 있는 동안 도착 → 요청 0건.
    store.enqueueReceivedMessages([
        ReceivedMessage(id: "m1", fromName: "영식", body: "안녕", createdAt: mwNow, fromUserID: "u1")
    ])
    try? await Task.sleep(for: .milliseconds(40))
    #expect(FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 0)

    // 창을 연다(여기서 1회) → 그 뒤 도착분마다 1회씩 는다.
    store.isMessageWindowVisible = true
    store.loadMessageHistory()
    await mwWait { FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 1 }

    store.enqueueReceivedMessages([
        ReceivedMessage(id: "m2", fromName: "민수", body: "점심?", createdAt: mwNow, fromUserID: "u2")
    ])
    await mwWait { FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 2 }
    #expect(FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 2)

    // 같은 id 가 또 와도(재발사 창) 새 왕복은 없다 — 큐가 중복을 먼저 거른다.
    store.enqueueReceivedMessages([
        ReceivedMessage(id: "m2", fromName: "민수", body: "점심?", createdAt: mwNow, fromUserID: "u2")
    ])
    try? await Task.sleep(for: .milliseconds(40))
    #expect(FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 2)
}

// MARK: - 스토어: 보내기

@MainActor
@Test
func sendingClearsTheDraftAndReloadsHistory() async {
    let host = "mw-send-ok"
    let store = mwStore(host: host)
    FeedbackURLProtocol.set(.init(body: #"{"status":"ok","body":"안녕","ring":"sent"}"#), host: host, path: mwSendPath)
    FeedbackURLProtocol.set(.init(body: "[]"), host: host, path: mwHistoryPath)
    store.selectedMessagePeerID = "u1"
    store.messageDraft = "  안녕  "

    #expect(store.canSendMessageNow)
    store.sendDraftMessage()
    await mwWait { store.messageNotice != nil }

    #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
    #expect(store.messageDraft == "", "성공했는데 초안이 남으면 다음 Enter 에 같은 말이 또 나간다")
    // 보내는 값은 **정규화된 문자열**이다(원문이 아니다).
    let sent = FeedbackURLProtocol.sentBodies(host: host, path: mwSendPath).first ?? ""
    #expect(sent.contains("\"p_body\":\"안녕\""))
    // 방금 보낸 말이 그 자리에서 대화에 나타나야 "메신저"다 → 이력을 다시 받는다.
    await mwWait { FeedbackURLProtocol.count(host: host, path: mwHistoryPath) >= 1 }
    #expect(FeedbackURLProtocol.count(host: host, path: mwHistoryPath) >= 1)
}

@MainActor
@Test
func failedSendKeepsTheDraft() async {
    let host = "mw-send-focused"
    let store = mwStore(host: host)
    FeedbackURLProtocol.set(.init(body: #"{"status":"target_focused"}"#), host: host, path: mwSendPath)
    store.selectedMessagePeerID = "u1"
    store.messageDraft = "집중 중인 사람에게"

    store.sendDraftMessage()
    await mwWait { store.messageNotice != nil }

    #expect(store.messageNotice == WorkTimerStore.messageTargetFocusedNotice)
    #expect(store.messageDraft == "집중 중인 사람에게", "실패에 초안을 지우면 사용자는 그 말을 다시 써야 한다")
}

@MainActor
@Test
func sendIsBlockedWithoutAPeerOrWithAnEmptyDraft() async {
    let host = "mw-send-gate"
    let store = mwStore(host: host)
    FeedbackURLProtocol.set(.init(body: #"{"status":"ok"}"#), host: host, path: mwSendPath)

    // 상대를 안 골랐다.
    store.messageDraft = "보낼 말"
    #expect(!store.canSendMessageNow)
    store.sendDraftMessage()

    // 골랐지만 빈 초안(공백만).
    store.selectMessagePeer("u1")
    store.messageDraft = "   "
    #expect(!store.canSendMessageNow)
    store.sendDraftMessage()

    // 골랐지만 200자를 넘겼다.
    store.messageDraft = String(repeating: "가", count: 201)
    #expect(!store.canSendMessageNow)
    store.sendDraftMessage()

    try? await Task.sleep(for: .milliseconds(40))
    #expect(FeedbackURLProtocol.count(host: host, path: mwSendPath) == 0)
}

@MainActor
@Test
func noticesNeverLeakInternalVocabularyToTheScreen() {
    // 서버 status·예외 코드가 화면에 새면 사용자는 자기가 뭘 잘못했는지 알 수 없다.
    let notices = [
        WorkTimerStore.messageSentNotice,
        WorkTimerStore.messageNotWorkingNotice,
        WorkTimerStore.messageTargetNotWorkingNotice,
        WorkTimerStore.messageTargetFocusedNotice,
        WorkTimerStore.messageNotTextNotice,
        WorkTimerStore.messageBlackoutNotice,
        WorkTimerStore.messageInvalidNotice,
        WorkTimerStore.messageTooLongNotice(),
        WorkTimerStore.messageTooLongNotice(maxLength: 140)
    ]
    let internalWords = ["not_working", "target_focused", "target_not_working", "too_long", "not_text",
                         "blackout", "flood", "MESSAGE_FLOOD", "invalid", "PGRST", "status"]
    for notice in notices {
        for word in internalWords {
            #expect(!notice.lowercased().contains(word.lowercased()), "내부 어휘가 화면 문구로 샜다: \(notice)")
        }
        #expect(!notice.isEmpty)
    }
    // 문구는 서로 달라야 한다(flood 는 invalid 와 **일부러 같은 문장**이라 그 하나만 겹친다).
    #expect(Set(notices).count == notices.count - 0)
    // 상한 문구는 서버가 알려 준 숫자를 쓴다.
    #expect(WorkTimerStore.messageTooLongNotice(maxLength: 140).contains("140"))
    #expect(WorkTimerStore.messageTooLongNotice().contains("\(MessageBody.maxLength)"))
    // 창 상단 안내도 상수에서 나온다(리터럴 "12시간"을 적어 두면 값을 바꾼 날 안내만 옛 숫자로 남는다).
    #expect(WorkTimerStore.messageExpiryNotice.contains("\(WorkTimerStore.messageHistoryHours)시간"))
}

// MARK: - 스토어: 로그아웃 리셋

@MainActor
@Test
func signOutClearsEveryTraceOfTheConversation() {
    // 이 화면이 나르는 것은 순위 숫자가 아니라 **두 사람이 주고받은 문장**이다 — 남기면 다음 사람이 그대로 읽는다.
    let store = mwStore(host: "mw-signout")
    store.isMessageWindowVisible = true
    store.messageHistory = [mwEntry(id: "a", peer: "u1", body: "사적인 말", minutesAgo: 10)]
    store.messageHistoryLoaded = true
    store.messageHistoryLoading = true
    store.messageHistoryFailed = true
    store.selectedMessagePeerID = "u1"
    store.messageDraft = "쓰다 만 말"
    store.messageReadStamps = ["u1": mwNow]
    store.messageNotice = WorkTimerStore.messageSentNotice
    store.isSendingMessage = true

    store.clearPersistedSession()

    #expect(!store.isMessageWindowVisible)
    #expect(store.messageHistory.isEmpty)
    #expect(!store.messageHistoryLoaded)
    #expect(!store.messageHistoryLoading)
    #expect(!store.messageHistoryFailed)
    #expect(store.selectedMessagePeerID == nil)
    #expect(store.messageDraft == "", "초안이 남으면 앞 사람이 쓰다 만 말이 새 계정에서 나갈 수 있다")
    #expect(store.messageReadStamps.isEmpty)
    #expect(store.messageNotice == nil)
    #expect(!store.isSendingMessage)
    #expect(store.messageThreads.isEmpty)
    #expect(store.unreadMessagePeerIDs.isEmpty)
}

// MARK: - 회귀: 메시지 경로에 쿨타임이 남아 있지 않다 (소스 계약)
//
// 런타임 계측으로는 "없다"를 증명할 수 없다 — 없는 코드는 아무 신호도 내지 않는다. 그래서 소스를 직접 센다.
// ⚠️ **주석을 먼저 걷어낸다.** 안 그러면 "왜 지웠는지"를 적어 둔 설명 자체가 이 단언을 빨갛게 만들고,
//    다음 사람은 테스트를 통과시키려 그 설명을 지운다(이 저장소가 겪은 함정).

private func mwSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)          // Tests/checkTests/V0249MessageWindowTests.swift
        .deletingLastPathComponent()                    // Tests/checkTests
        .deletingLastPathComponent()                    // Tests
        .deletingLastPathComponent()                    // (repo root)
        .appendingPathComponent("Sources/check/\(name)")
    return mwStripComments(try String(contentsOf: url, encoding: .utf8))
}

/// 줄 주석(`//`)과 블록 주석(`/* */`)을 걷어낸다. 문자열 리터럴 안의 `//` 는 남긴다(URL 이 잘리면 안 된다).
private func mwStripComments(_ source: String) -> String {
    var out = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let iterator = Array(source)
    var index = 0
    while index < iterator.count {
        let ch = iterator[index]
        let next: Character? = index + 1 < iterator.count ? iterator[index + 1] : nil
        if inLineComment {
            if ch == "\n" { inLineComment = false; out.append(ch) }
        } else if inBlockComment {
            if ch == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            out.append(ch)
            if ch == "\"", previous != "\\" { inString = false }
        } else if ch == "/", next == "/" {
            inLineComment = true
            index += 1
        } else if ch == "/", next == "*" {
            inBlockComment = true
            index += 1
        } else {
            if ch == "\"" { inString = true }
            out.append(ch)
        }
        previous = ch
        index += 1
    }
    return out
}

@Test
func noCooldownSurvivesAnywhereOnTheMessagePath() throws {
    // ★ 사장님 요구: "찌르기만 60초 쿨타임 있고 메시지는 쿨타임 없이 갈 거야."
    //   스토어만 고치고 뷰가 막으면 **초록인 채로 아무것도 안 바뀐다**(이 저장소가 겪은 함정).
    //   그래서 스토어·모델·뷰 네 파일을 전수로 센다.
    for name in ["WorkTimerStoreMessages.swift", "WorkTimerStorePoke.swift",
                 "CheckMessageView.swift", "CheckMenuView.swift", "WorkTimerStore.swift"] {
        let source = try mwSource(name)
        #expect(!source.contains("messageCooldownRemaining"), "\(name) 에 메시지 쿨타임 잔여 계산이 남아 있다")
        #expect(!source.contains("messageCooldownUntil"), "\(name) 에 메시지 쿨타임 미러가 남아 있다")
        #expect(!source.contains("messageCooldownSeconds"), "\(name) 에 메시지 쿨타임 상수가 남아 있다")
        #expect(!source.contains("messageCooldownNotice"), "\(name) 에 메시지 쿨타임 문구가 남아 있다")
    }

    // 대조군: **찌르기 쿨타임은 그대로 살아 있다.** 함께 지웠다면 그건 요구를 넘어선 파괴다.
    let poke = try mwSource("WorkTimerStorePoke.swift")
    #expect(poke.contains("pokeCooldownSeconds"))
    #expect(poke.contains("func pokeCooldownRemaining"))
    #expect(try mwSource("CheckMenuView.swift").contains("cooldownRemaining"))

    // 도메인 타입에도 죽은 가지가 없다: send_message 는 `cooldown`/`target_outdated` 를 내지 않는다.
    let models = try mwSource("SupabaseWorkModels.swift")
    let outcome = try #require(models.range(of: "enum MessageSendOutcome"))
    let outcomeBody = String(models[outcome.lowerBound...].prefix(2_000))
    #expect(!outcomeBody.contains("case cooldown"), "MessageSendOutcome 에 쿨타임 케이스가 되살아났다")
    #expect(!outcomeBody.contains("case targetOutdated"), "폐기된 최소 빌드 게이트 케이스가 되살아났다")
    #expect(outcomeBody.contains("case flood"))
    #expect(outcomeBody.contains("case blackout"))
    #expect(outcomeBody.contains("case notText"))
}

@Test
func theInlineComposerIsGoneSoThereIsExactlyOnePlaceToSend() throws {
    // 보내는 곳이 둘이면 이력도 둘로 갈린다(그리고 200자를 292pt 폭에서 쓰는 것은 애초에 무리다).
    let menu = try mwSource("CheckMenuView.swift")
    for symbol in ["PokeMessageComposer", "PokeMessageCounter", "PokeMessageInputFilter",
                   "previewMessageComposerUserID", "previewMessageDraft"] {
        #expect(!menu.contains(symbol), "걷어낸 인라인 작성기의 흔적이 남아 있다: \(symbol)")
    }
    // 팝오버가 아는 유일한 문은 창 열기다.
    #expect(menu.contains("onOpenMessages"))
    // 전송을 부르는 자리는 창 쪽 한 곳뿐이다.
    #expect(!menu.contains("store.sendMessage("))
    #expect(try mwSource("CheckMessageView.swift").contains("store.sendDraftMessage()"))
}

// MARK: - 렌더 스냅샷 (msgwin-)

/// 스냅샷 저장 위치. 기본은 이 실행의 임시 디렉터리이고 `CHECK_SNAPSHOT_DIR` 로 덮어쓴다 —
/// 세션 전용 절대 경로를 소스에 박아 두면 퍼블릭 저장소에 개인 머신 경로가 남는다(제보 스위트와 같은 규약).
enum MessageWindowSnapshots {
    static func save(_ bitmap: NSBitmapImageRep, name: String) {
        let base = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-snapshots", isDirectory: true)
        let dir = base.appendingPathComponent("msgwin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }
}

private enum MWRenderError: Error { case failed }

/// ★ `clipsOverflowInsteadOfScroll: true` · `rendersPlainTextEditor: true` — `ImageRenderer` 는 ScrollView
///   안쪽과 `TextEditor` 를 못 그린다. 이 인자들이 없으면 아래 스냅샷은 헤더만 남은 빈 화면이고,
///   사람이 아무것도 확인할 수 없다(제보 창이 겪은 함정 그대로다). **앱은 언제나 진짜 위젯을 쓴다.**
@MainActor
private func mwBitmap(
    _ store: WorkTimerStore,
    size: NSSize = CheckMessageWindowController.defaultContentSize
) throws -> NSBitmapImageRep {
    let view = CheckMessageView(
        store: store,
        rendersPlainTextEditor: true,
        clipsOverflowInsteadOfScroll: true,
        now: mwNow
    )
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MWRenderError.failed }
    return bitmap
}

/// 내용 없이 배경만 그린 같은 크기의 비트맵. 배경이 **그라디언트**라 "한 픽셀을 배경색으로 삼는" 잉크 탐지는
/// 통째로 거짓말한다 — 그래서 기준을 그림 하나로 둔다(제보 스위트와 같은 근거).
@MainActor
private func mwBlankBitmap(size: NSSize = CheckMessageWindowController.defaultContentSize) throws -> NSBitmapImageRep {
    let view = Color.clear.frame(width: size.width, height: size.height).background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MWRenderError.failed }
    return bitmap
}

/// 두 비트맵이 눈에 띄게 다른 영역의 경계(픽셀). 없으면 nil.
private func mwDiffBounds(
    _ lhs: NSBitmapImageRep,
    _ rhs: NSBitmapImageRep,
    tolerance: Double = 0.06,
    skippingTopPixels: Int = 0
) -> CGRect? {
    let width = min(lhs.pixelsWide, rhs.pixelsWide)
    let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in stride(from: skippingTopPixels, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 2) {
            guard let a = lhs.colorAt(x: x, y: y), let b = rhs.colorAt(x: x, y: y) else { continue }
            let delta = abs(a.redComponent - b.redComponent)
                + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
            if delta > tolerance {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// 대화가 채워진 스토어(합성 문자열만 쓴다).
@MainActor
private func mwThreadStore(host: String, extra: [MessageHistoryEntry] = []) -> WorkTimerStore {
    let store = mwStore(host: host)
    var entries = [
        mwEntry(id: "a1", peer: "u1", name: "영식", body: "자료 확인했어요", minutesAgo: 240),
        mwEntry(id: "a2", peer: "u1", name: "영식", body: "네 곧 올릴게요", minutesAgo: 236, isMine: true),
        mwEntry(id: "a3", peer: "u1", name: "영식", body: "고마워요 :)", minutesAgo: 100),
        mwEntry(id: "b1", peer: "u2", name: "김서연", body: "점심 같이 드실래요?", minutesAgo: 60),
        mwEntry(id: "b2", peer: "u2", name: "김서연", body: "12시에 로비에서 봐요", minutesAgo: 12, isMine: true),
        mwEntry(id: "c1", peer: "u3", name: "박도윤", body: "회의 30분 미뤄졌습니다", minutesAgo: 30)
    ]
    entries.append(contentsOf: extra)
    store.messageHistory = entries.sortedForMessageHistory()
    store.messageHistoryLoaded = true
    store.selectMessagePeer("u1")
    return store
}

@MainActor
@Test
func conversationRendersWithoutClippingOrOverlap() throws {
    let size = CheckMessageWindowController.defaultContentSize
    let expectedWidth = Int(size.width) * 2
    let expectedHeight = Int(size.height) * 2
    let blank = try mwBlankBitmap()

    let store = mwThreadStore(host: "mw-render-thread")
    store.messageDraft = "곧 올릴게요"
    let bitmap = try mwBitmap(store)
    #expect(bitmap.pixelsWide == expectedWidth && bitmap.pixelsHigh == expectedHeight)
    MessageWindowSnapshots.save(bitmap, name: "msgwin-thread.png")

    // 그린 것이 창 안에 있다(좌우로 넘치지 않는다). 헤더 띠는 뺀 본문만 잰다.
    let ink = try #require(mwDiffBounds(bitmap, blank, skippingTopPixels: 90), "대화 화면이 통째로 비었다")
    #expect(ink.maxX <= CGFloat(expectedWidth) - 2, "내용이 오른쪽으로 넘쳤다")
    // ※ 왼쪽은 재지 않는다: 대화 목록 판이 **일부러 창 왼쪽 끝까지** 칠해져 있어(2단 구분) 잉크가 x=0 에서 시작한다.
    //   제보 창에서 `minX >= 4` 를 잰 것과 다른 이유가 그것이다 — 거기는 한 단짜리 화면이었다.
    // 아래쪽까지 내용이 있다(입력줄이 잘려 나가지 않았다).
    #expect(ink.maxY > CGFloat(expectedHeight) * 0.8, "아래쪽이 비었다 — 입력줄이 안 그려졌다")

    // 최소 크기(460×420)에서도 같은 성질이 유지된다 — 좁히면 말풍선이 겹치거나 넘치는지 눈으로 본다.
    let minSize = CheckMessageWindowController.minContentSize
    let small = try mwBitmap(store, size: minSize)
    MessageWindowSnapshots.save(small, name: "msgwin-thread-min.png")
    let smallInk = try #require(
        mwDiffBounds(small, try mwBlankBitmap(size: minSize), skippingTopPixels: 90),
        "최소 크기에서 대화가 통째로 비었다"
    )
    #expect(smallInk.maxX <= CGFloat(Int(minSize.width) * 2) - 2, "최소 크기에서 내용이 오른쪽으로 넘쳤다")
}

@MainActor
@Test
func emptyStatesAreDifferentForNoThreadsAndNoSelection() throws {
    let blank = try mwBlankBitmap()

    // ① 대화가 하나도 없다 — 할 일은 '시작하기'다(이 창에는 사람 목록이 없다).
    let empty = mwStore(host: "mw-render-empty")
    empty.messageHistoryLoaded = true
    let emptyBitmap = try mwBitmap(empty)
    MessageWindowSnapshots.save(emptyBitmap, name: "msgwin-empty.png")
    #expect(mwDiffBounds(emptyBitmap, blank, skippingTopPixels: 90) != nil, "빈 상태가 아무것도 안 그렸다")

    // ② 대화는 있는데 아무도 안 골랐다 — 할 일은 '고르기'다. **두 화면은 달라야 한다.**
    let unselected = mwThreadStore(host: "mw-render-unselected")
    unselected.selectMessagePeer(nil)
    let unselectedBitmap = try mwBitmap(unselected)
    MessageWindowSnapshots.save(unselectedBitmap, name: "msgwin-empty-unselected.png")
    #expect(
        mwDiffBounds(emptyBitmap, unselectedBitmap) != nil,
        "두 빈 상태가 같은 그림이다 — 사용자가 할 일이 다른데 같은 말을 하고 있다"
    )
}

@MainActor
@Test
func longBodiesWrapInsideTheBubbleInsteadOfOverflowing() throws {
    // 200자 한 덩어리. `fixedSize(horizontal:)` 을 말풍선에 붙였다면 여기서 창 밖으로 넘친다.
    let long = mwEntry(
        id: "long",
        peer: "u1",
        name: "영식",
        body: String(repeating: "가나다라마바사아자차", count: 20),
        minutesAgo: 5
    )
    let store = mwThreadStore(host: "mw-render-long", extra: [long])
    store.selectMessagePeer("u1")
    store.messageDraft = String(repeating: "답장 초안 ", count: 12)

    let bitmap = try mwBitmap(store)
    MessageWindowSnapshots.save(bitmap, name: "msgwin-long.png")
    let ink = try #require(mwDiffBounds(bitmap, try mwBlankBitmap(), skippingTopPixels: 90))
    #expect(ink.maxX <= CGFloat(Int(CheckMessageWindowController.defaultContentSize.width) * 2) - 2,
            "긴 본문이 창 밖으로 넘쳤다 — 말풍선이 폭 상한을 안 지킨다")
}

@MainActor
@Test
func emojiBodiesRenderInBothDirections() throws {
    // 3글자 시절에는 입력 자체가 이모지를 지웠다. 이제는 정상 입력이라 **양쪽 말풍선 모두** 그려져야 한다.
    let store = mwThreadStore(host: "mw-render-emoji", extra: [
        mwEntry(id: "e1", peer: "u1", name: "영식", body: "축하해요 🎉🎉", minutesAgo: 20),
        mwEntry(id: "e2", peer: "u1", name: "영식", body: "고마워요 👨‍👩‍👧‍👦 🇰🇷 👍🏻", minutesAgo: 18, isMine: true)
    ])
    store.selectMessagePeer("u1")
    store.messageDraft = "🎉 감사합니다"

    let bitmap = try mwBitmap(store)
    MessageWindowSnapshots.save(bitmap, name: "msgwin-emoji.png")
    #expect(mwDiffBounds(bitmap, try mwBlankBitmap(), skippingTopPixels: 90) != nil)
    // 카운터는 **코드포인트**를 센다("🎉 감사합니다" = 1 + 1 + 5 = 7).
    #expect(store.messageDraftLength == 7)
}

@MainActor
@Test
func longPeerNamesNeverPushTheListRowOffScreen() throws {
    let store = mwThreadStore(host: "mw-render-longname", extra: [
        mwEntry(id: "n1", peer: "u9", name: String(repeating: "김수한무", count: 6),
                body: String(repeating: "긴 미리보기 ", count: 20), minutesAgo: 1)
    ])
    let bitmap = try mwBitmap(store)
    MessageWindowSnapshots.save(bitmap, name: "msgwin-long-name.png")
    let ink = try #require(mwDiffBounds(bitmap, try mwBlankBitmap(), skippingTopPixels: 90))
    #expect(ink.maxX <= CGFloat(Int(CheckMessageWindowController.defaultContentSize.width) * 2) - 2,
            "긴 이름·미리보기가 목록 폭을 밀어냈다")
}

@MainActor
@Test
func thePokePanelEntryPointHasNoInlineComposerLeft() throws {
    // 스냅샷 `msgwin-poke-entry.png` — **콕찌르기 패널에서 인라인 작성기가 사라진 모습**이다.
    // 말풍선 버튼은 이제 창을 여는 문일 뿐이라, 행 아래로 펼쳐지는 입력칸이 한 개도 없어야 한다.
    let store = mwStore(host: "mw-render-poke-entry")
    // 팝오버가 콕찌르기 패널을 그리려면 **팀이 확정된 로그인 상태**여야 한다 —
    // 안 그러면 "합류할 팀을 찾아요" 화면이 나와 이 스냅샷이 아무것도 증명하지 못한다(첫 판의 실측).
    store.isMenuPresented = true
    store.displayNow = mwNow
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.pokeDirectory = [
        PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true, canReceiveMessage: true),
        PokeDirectoryEntry(userID: "u2", name: "김서연", avatarURL: nil, isWorking: true, canReceiveMessage: false),
        PokeDirectoryEntry(userID: "u3", name: "박도윤", avatarURL: nil, isWorking: false, canReceiveMessage: true)
    ]
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    store.receivedMessages = [
        ReceivedMessage(
            id: "m1",
            fromName: "김서연",
            body: String(repeating: "긴 본문이 행을 밀어내지 않는지 보는 줄 ", count: 6),
            createdAt: mwNow.addingTimeInterval(-120),
            fromUserID: "u2"
        )
    ]

    let view = CheckMenuView(store: store, previewClipsOverflowList: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    let bitmap = try #require(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
    MessageWindowSnapshots.save(bitmap, name: "msgwin-poke-entry.png")

    // 팝오버 폭은 본문 길이에 끌려다니지 않는다 — 짧은 본문으로 그린 같은 화면과 폭이 **같아야** 한다
    // (옛 수신 줄의 `.fixedSize()` 가 정확히 이 성질을 깼다: 200자가 이상 폭을 요구해 행을 밀어냈다).
    store.receivedMessages = [
        ReceivedMessage(id: "m1", fromName: "김서연", body: "밥?", createdAt: mwNow.addingTimeInterval(-120), fromUserID: "u2")
    ]
    let shortRenderer = ImageRenderer(content: CheckMenuView(store: store, previewClipsOverflowList: true))
    shortRenderer.scale = 2
    let shortImage = try #require(shortRenderer.nsImage)
    let shortBitmap = try #require(shortImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
    #expect(bitmap.pixelsWide == shortBitmap.pixelsWide, "긴 본문이 팝오버 폭을 밀어냈다")
    #expect(bitmap.pixelsHigh == shortBitmap.pixelsHigh, "긴 본문이 수신 줄을 여러 줄로 키웠다")
    // 창 높이 상한(700pt)도 그대로다.
    #expect(Double(bitmap.pixelsHigh) / 2.0 <= 700.0)
}

// MARK: - 창 계약

@MainActor
@Test
func theWindowFollowsTheFeedbackWindowContract() {
    // 제보 창과 **같은 규약**이어야 한다 — 한쪽만 다르면 다음 사람이 어느 쪽이 옳은지 알 수 없다.
    let window = CheckMessageWindowController.makeWindow()

    #expect(window.title == CheckMessageWindowController.windowTitle)
    #expect(window.styleMask.contains(.titled))
    #expect(window.styleMask.contains(.closable))
    #expect(window.styleMask.contains(.resizable), "긴 대화를 보는 창이라 키울 수 있어야 한다")
    // ★ Dock 타일이 없는 앱이라 최소화한 창을 되찾을 길이 없다(설정·제보 창과 같은 근거).
    #expect(!window.styleMask.contains(.miniaturizable))
    #expect(!window.isReleasedWhenClosed, "닫힘에 딸린 해제가 끼면 다음 show() 가 해제된 창을 만진다")
    #expect(!window.hidesOnDeactivate, "옆에 켜 두는 것이 메신저의 정상 사용 형태다")
    #expect(window.appearance?.name == .darkAqua, "앱 전체가 다크다 — 시스템 외관을 따르면 흰 배경에 흰 글자가 난다")
    #expect(window.contentMinSize == CheckMessageWindowController.minContentSize)
    #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
    #expect(CheckMessageWindowController.defaultContentSize == NSSize(width: 560, height: 600))
    #expect(CheckMessageWindowController.frameAutosaveName == "check.messageWindow")

    // 배선 전에는 창을 만들지 않는다(스토어 없이 만든 창은 담을 게 없다).
    let controller = CheckMessageWindowController(stuckWindowCheckSeconds: 0.01)
    controller.show()
    #expect(!controller.hasWindow)
    #expect(!controller.isOpen)
    // 진단 문자열에 **본문이 없다** — 로그로 흘러가는 값이다.
    #expect(controller.diagnosticState.contains("window=none"))
}
