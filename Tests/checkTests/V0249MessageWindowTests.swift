import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
@testable import check

// 메시지 — 순수 경계(길이·묶음·구분선·정렬) · 스토어 왕복 · 쿨타임 부재의 소스 계약 · 렌더 스냅샷.
//
// 사용자 요청(2026-09-10): "메시지 보낼 때 그 순간에 못 보면 내용을 못 보잖아. …
//   시간과 함께 주고받은 순서대로. 12시간 지나면 순차적으로 사라지게. 메시지랑 찌르기는 아예 분리야.
//   찌르기만 60초 쿨타임 있고 메시지는 쿨타임 없이 갈 거야. 진짜 메신저 앱처럼. 3글자 제한도 없애줘."
//
// **v0.2.50 에 표면이 바뀌었다**(파일 이름은 이력이라 그대로 둔다 — 옮기면 이 스위트의 과거가 끊긴다):
//   "각 사람의 메시지 버튼을 누르면 해당 창 안에서 그 사람과의 1대1 메시지 화면으로만 넘어가고 …
//    지금처럼 별도 창에서 나랑 대화하던 사람들이 왼쪽에 다 뜨는 방식이 아니라."
// 확인 질문의 답이 **"팝오버 안에서 전환"**(창이 하나도 안 뜨는 쪽)이라, 별도 창과 왼쪽 대화 목록이
// 함께 사라졌다. 그래서 이 파일의 창 계약 테스트는 **패널 계약**으로 갈아 끼웠고(맨 아래),
// 렌더 스냅샷은 패널 하나가 아니라 **팝오버 통째로** 그린다(창 높이 상한 700pt 가 이 작업의 최악 결함이다).
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
func clockStampsAreFixedTo24HourForm() {
    // 지역 설정이 "오후 2:05"를 만들면 말풍선 폭이 사람마다 달라진다 — 이 화면은 그 폭을 예산으로 쓴다.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let afternoon = Date(timeIntervalSince1970: 1_789_000_000)   // KST 어느 오후
    let text = MessageThreadBuilder.clockText(afternoon, calendar: calendar)
    #expect(text.count == 5 && text.contains(":"))
    #expect(!text.contains("오후") && !text.contains("PM"))

    // ★ 여기 있던 `listStampText`/`previewText` 단언은 v0.2.50 에 **그 함수들과 함께 걷었다.**
    //   둘 다 왼쪽 대화 목록의 한 행만을 위한 계산이었고, 그 목록이 사라지면서 부르는 곳이 없어졌다
    //   (사용자 지시 1). 아무도 안 쓰는 함수를 지키는 테스트는 다음 사람에게 "이건 살아 있는 규칙"이라고
    //   거짓말한다. `clockText`(위)와 `dayLabel`(아래)은 말풍선·날짜 구분선이 계속 쓰므로 그대로 남는다.
}

// MARK: - 스토어: 패널 열고 닫기 · 선택 · 읽음

@MainActor
@Test
func openingThePanelSelectsTheRequestedPeerAndMarksItRead() async {
    let store = mwStore(host: "mw-open-peer")
    store.messageHistory = [
        mwEntry(id: "a", peer: "u1", name: "영식", body: "안녕", minutesAgo: 30),
        mwEntry(id: "b", peer: "u2", name: "민수", body: "점심?", minutesAgo: 5)
    ]
    // 열기 전에는 둘 다 안 읽음이다(도장이 없다).
    #expect(store.unreadMessagePeerIDs == ["u1", "u2"])
    store.isPokePanelVisible = true

    store.openMessagePanel(peer: "u1")

    #expect(store.isMessagePanelVisible)
    #expect(store.selectedMessagePeerID == "u1")
    // 고른 대화만 읽음이 된다 — 화면을 열었다고 남의 대화까지 읽은 것으로 치면 점이 아무 뜻도 없어진다.
    #expect(store.unreadMessagePeerIDs == ["u2"])
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["a"])
    // ★ 콕찌르기 목록은 **내려간다**(같은 자리를 쓰는 하위 패널이라 상호 배타다).
    #expect(!store.isPokePanelVisible, "대화 뒤에 콕찌르기 목록이 살아 남았다")
    // 그리고 [뒤로]가 돌아갈 곳으로 그 목록을 기억한다.
    #expect(store.messagePanelOrigin == .poke)
}

@MainActor
@Test
func goingBackReturnsToTheListYouCameFromAndNowhereElse() {
    // 울트라 패널의 `ultraPanelOrigin` 과 **같은 규약**이다: 들어온 문이 [뒤로]를 정한다.
    let fromPoke = mwStore(host: "mw-back-poke")
    fromPoke.openMessagePanel(peer: "u1")
    fromPoke.closeMessagePanel()
    #expect(!fromPoke.isMessagePanelVisible)
    #expect(fromPoke.isPokePanelVisible, "콕찌르기에서 들어왔는데 [뒤로]가 그 목록으로 안 갔다")

    // 캐릭터 말풍선에서 들어온 경우는 홈이다 — 콕찌르기로 보내면 **가 본 적 없는 화면**으로 '돌아가게' 된다.
    let fromOverlay = mwStore(host: "mw-back-overlay")
    fromOverlay.openMessagePanel(peer: "u1", from: .overlay)
    fromOverlay.closeMessagePanel()
    #expect(!fromOverlay.isMessagePanelVisible)
    #expect(!fromOverlay.isPokePanelVisible, "말풍선에서 들어왔는데 [뒤로]가 콕찌르기를 열었다")
    // 맥락은 기본값으로 되돌아간다(다음에 열린 대화가 앞 맥락을 물려받으면 안 된다).
    #expect(fromOverlay.messagePanelOrigin == .poke)
}

@MainActor
@Test
func openingWithAnEmptyPeerIDOpensNothing() {
    // ★ 규칙이 두 번 바뀌었다. 창 시절에는 상대를 안 주면 최근 대화를 스스로 골랐고(왼쪽 목록이 있었다),
    //   v0.2.50 에는 "아무도 고르지 않고 '고르세요' 화면을 띄운다"였다. 2026-09-11 사용자 지적
    //   ("애초에 대화상대를 고르지 않고 대화창에 진입할 수가 없어야되잖아") 이후로는 **상대 없이는 들어오지
    //   못한다**: `openMessagePanel(peer:)` 이 `String` 이라 nil 은 컴파일되지 않고, 남은 구멍인 빈 문자열은
    //   아무 상태도 건드리지 않고 돌아간다. 시그니처가 다시 넓혀지지 않는지는 V0251MessagePeerTests 가 소스로 잰다.
    let store = mwStore(host: "mw-open-default")
    store.messageHistory = [
        mwEntry(id: "a", peer: "u1", body: "옛말", minutesAgo: 300),
        mwEntry(id: "b", peer: "u2", body: "새말", minutesAgo: 5)
    ]

    store.openMessagePanel(peer: "")

    #expect(!store.isMessagePanelVisible, "빈 id 로 대화 화면이 열렸다 — '대화 상대를 고르지 않았어요'가 뜬다")
    #expect(store.selectedMessagePeerID == nil, "아무도 안 눌렀는데 임의의 상대를 골랐다")
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
func closingThePanelKeepsTheDraft() {
    // 화면을 잘못 바꿨다고 쓰던 말이 사라지면 사용자는 그 말을 다시 못 쓴다(제보 화면과 같은 규약).
    let store = mwStore(host: "mw-close-draft")
    store.isMessagePanelVisible = true
    store.messageDraft = "쓰다 만 말"

    store.closeMessagePanel()

    #expect(!store.isMessagePanelVisible)
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
func arrivingMessagesRefreshHistoryOnlyWhileThePanelIsOnScreen() async {
    // ★ **"화면을 열어 둔 채로 오면 그 자리에서 나타난다"의 근거다.** 새 타이머를 만들지 않고 이미 도는
    //   수신 폴링(15초)에 얹었다 — 그리고 볼 사람이 없으면 왕복을 내지 않는다(무료 플랜).
    //
    // v0.2.50 의 게이트는 **둘**이다: 패널 깃발 + 팝오버가 떠 있는가. 깃발은 팝오버를 닫아도 안 내려가므로
    // (마지막으로 본 화면을 다음 오픈에 그대로 보여 주는 규약) 깃발만 보면 닫힌 팝오버에도 조회가 붙는다.
    let host = "mw-arrival-refresh"
    let store = mwStore(host: host)
    FeedbackURLProtocol.set(.init(body: "[]"), host: host, path: mwHistoryPath)

    // 화면이 닫혀 있는 동안 도착 → 요청 0건.
    store.enqueueReceivedMessages([
        ReceivedMessage(id: "m1", fromName: "영식", body: "안녕", createdAt: mwNow, fromUserID: "u1")
    ])
    try? await Task.sleep(for: .milliseconds(40))
    #expect(FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 0)

    // 깃발만 서고 팝오버는 닫힌 상태 → 여전히 0건이다(이 줄이 없으면 닫힌 팝오버가 15초마다 조회한다).
    store.isMessagePanelVisible = true
    store.enqueueReceivedMessages([
        ReceivedMessage(id: "m9", fromName: "민수", body: "안녕", createdAt: mwNow, fromUserID: "u9")
    ])
    try? await Task.sleep(for: .milliseconds(40))
    #expect(
        FeedbackURLProtocol.count(host: host, path: mwHistoryPath) == 0,
        "팝오버가 닫혀 있는데 이력 조회가 나갔다 — 아무도 안 보는 갱신에 무료 플랜의 왕복을 쓴다"
    )

    // 팝오버를 연다(여기서 1회) → 그 뒤 도착분마다 1회씩 는다.
    store.isMenuPresented = true
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
    store.isMessagePanelVisible = true
    store.messagePanelOrigin = .overlay
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

    #expect(!store.isMessagePanelVisible)
    #expect(store.messagePanelOrigin == .poke, "진입 맥락이 남으면 다음 계정의 [뒤로]가 앞 사람 화면으로 간다")
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

// MARK: - 렌더 스냅샷 (panels-)
//
// v0.2.50 부터 대화는 **팝오버 하위 패널**이다. 그래서 스냅샷도 패널 하나가 아니라 **팝오버 통째로** 그린다 —
// 이 작업에서 가장 값비싼 결함이 "창 높이 회귀"이기 때문이다: 패널만 따로 그리면 배너·헤더 카드·푸터가
// 함께 서는 실제 높이를 영영 못 잰다(그리고 푸터가 잘리는 순간 사용자는 로그아웃할 방법을 잃는다).

/// 스냅샷 저장 위치. 기본은 이 실행의 임시 디렉터리이고 `CHECK_SNAPSHOT_DIR` 로 덮어쓴다 —
/// 세션 전용 절대 경로를 소스에 박아 두면 퍼블릭 저장소에 개인 머신 경로가 남는다(제보 스위트와 같은 규약).
enum MessagePanelSnapshots {
    static func save(_ bitmap: NSBitmapImageRep, name: String) {
        let base = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-snapshots", isDirectory: true)
        let dir = base.appendingPathComponent("panels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }
}

private enum MWRenderError: Error { case failed }

/// 팝오버 높이 상한(pt). 넘으면 푸터(로그아웃/앱 종료)가 화면 밖으로 잘린다.
private let mwPopoverHeightCap: Double = 700

/// 대화 패널이 열린 **메인 화면** 스토어. 팀이 확정된 로그인 상태여야 팝오버가 헤더 카드·레일·푸터를 그린다.
@MainActor
private func mwMenuStore(_ store: WorkTimerStore) -> WorkTimerStore {
    store.isMenuPresented = true
    store.displayNow = mwNow
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    return store
}

/// 팝오버가 얹을 수 있는 **가장 큰 크롬**의 재료. 새 버전 배너는 패치노트 줄 수만큼 자라고 그 수는
/// `UpdateCheckStore.maxNotes`(4)로 묶여 있으므로, 노트 4줄짜리 배너(81 + 8 + 4×15 = 149pt)가 배너의 상한이다.
/// 거기에 주간 목표 편집 인라인 행(92pt)을 겹치면 **241pt** — 이것이 하위 패널이 감당해야 할 최악의 크롬이다.
/// (토큰 소모량 행은 하위 패널이 열리면 감춰지므로 여기 없다. 12시간 확인 배너는 92pt 라 새 버전 배너보다 낮다.)
private let mwWorstNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

/// ★ `previewClipsOverflowList: true` · `previewPlainTextEditors: true` — `ImageRenderer` 는 ScrollView
///   안쪽과 `TextEditor` 를 못 그린다. 이 인자들이 없으면 아래 스냅샷은 대화 자리가 비고 입력칸 자리가
///   **노란 상자**인 그림이라, 사람이 확인할 수 있는 것이 사라진다. **앱은 언제나 진짜 위젯을 쓴다.**
@MainActor
private func mwBitmap(_ store: WorkTimerStore, worstChrome: Bool = false) throws -> NSBitmapImageRep {
    let view = CheckMenuView(
        store: store,
        previewClipsOverflowList: true,
        previewGoalEditing: worstChrome,
        previewUpdateBanner: worstChrome,
        previewUpdateNotes: worstChrome ? mwWorstNotes : [],
        previewPlainTextEditors: true
    )
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MWRenderError.failed }
    return bitmap
}

/// 내용 없이 배경만 그린 같은 크기의 비트맵. 배경이 **그라디언트**라 "한 픽셀을 배경색으로 삼는" 잉크 탐지는
/// 통째로 거짓말한다 — 그래서 기준을 그림 하나로 둔다(제보 스위트와 같은 근거).
@MainActor
private func mwBlankBitmap(matching bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
    let view = Color.clear
        .frame(width: CGFloat(bitmap.pixelsWide) / 2, height: CGFloat(bitmap.pixelsHigh) / 2)
        .background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let blank = NSBitmapImageRep(data: tiff)
    else { throw MWRenderError.failed }
    return blank
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

/// 대화가 채워진 스토어(합성 문자열만 쓴다). **한 사람과의 대화 하나**만 화면에 뜬다 —
/// 다른 사람들의 이력도 함께 넣어 두는 이유는 "그 사람 것만 골라 그린다"를 재기 위해서다.
@MainActor
private func mwThreadStore(host: String, extra: [MessageHistoryEntry] = [], peer: String = "u1") -> WorkTimerStore {
    let store = mwMenuStore(mwStore(host: host))
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
    store.pokeDirectory = [
        PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true),
        PokeDirectoryEntry(userID: "u2", name: "김서연", avatarURL: nil, isWorking: true),
        PokeDirectoryEntry(userID: "u3", name: "박도윤", avatarURL: nil, isWorking: false)
    ]
    store.pokeDirectoryLoaded = true
    store.openMessagePanel(peer: peer)
    return store
}

@MainActor
@Test
func theConversationDrawsOnePersonOnlyAndStaysInsideThePopover() throws {
    let store = mwThreadStore(host: "mw-render-thread")
    store.messageDraft = "곧 올릴게요"
    let bitmap = try mwBitmap(store)
    MessagePanelSnapshots.save(bitmap, name: "panels-msg-thread.png")

    // 팝오버 폭은 본문 316 + 간격 10 + 레일 64 + 바깥 padding 24 = 414pt 고정이다.
    #expect(bitmap.pixelsWide == 414 * 2, "대화 패널이 팝오버 폭을 밀어냈다")
    #expect(Double(bitmap.pixelsHigh) / 2.0 <= mwPopoverHeightCap,
            "대화 화면이 700pt 상한을 넘었다: \(Double(bitmap.pixelsHigh) / 2.0)pt")

    let blank = try mwBlankBitmap(matching: bitmap)
    let ink = try #require(mwDiffBounds(bitmap, blank), "대화 화면이 통째로 비었다")
    #expect(ink.maxX <= CGFloat(bitmap.pixelsWide) - 2, "내용이 오른쪽으로 넘쳤다")
    #expect(ink.minX >= 4, "내용이 왼쪽 밖에서 시작한다")
    // **푸터가 살아 있다**: 잉크가 그림 맨 아래까지 닿는다(로그아웃/앱 종료 버튼 줄).
    #expect(ink.maxY > CGFloat(bitmap.pixelsHigh) - 60, "팝오버 아래쪽이 비었다 — 푸터가 안 그려졌다")

    // ★ **왼쪽 대화 목록이 없다**(사용자 지시 1). 다른 사람을 골라 그리면 그림이 달라야 한다 —
    //   같으면 두 대화가 같은 화면이라는 뜻이고, 그건 곧 목록형 화면이 살아 있다는 신호다.
    let other = mwThreadStore(host: "mw-render-thread-other", peer: "u2")
    let otherBitmap = try mwBitmap(other)
    #expect(mwDiffBounds(bitmap, otherBitmap) != nil, "상대를 바꿨는데 화면이 그대로다 — 한 사람짜리 화면이 아니다")
}

@MainActor
@Test
func emptyStatesAreDifferentForNoPeerAndNoMessages() throws {
    // ① 상대를 못 정했다 — 할 일은 '고르기'다(이 화면에는 사람 목록이 없으므로 어디로 갈지 말해 준다).
    //    ⚠️ 이 상태는 **진입점으로는 도달할 수 없다**(2026-09-11 — `openMessagePanel(peer:)` 이 `String` 이다).
    //    뷰에 남은 방어 가지가 여전히 다른 그림을 내는지만 보려고 깃발을 **직접** 세운다. 이 줄을
    //    `openMessagePanel` 호출로 되돌리려면 옵셔널을 되살려야 하는데, 그건 사용자가 없애라고 한 바로 그 길이다.
    let noPeer = mwMenuStore(mwStore(host: "mw-render-nopeer"))
    noPeer.messageHistoryLoaded = true
    noPeer.isMessagePanelVisible = true
    let noPeerBitmap = try mwBitmap(noPeer)
    MessagePanelSnapshots.save(noPeerBitmap, name: "panels-msg-nopeer.png")
    #expect(mwDiffBounds(noPeerBitmap, try mwBlankBitmap(matching: noPeerBitmap)) != nil, "빈 상태가 아무것도 안 그렸다")

    // ② 상대는 정했는데 주고받은 것이 없다 — 할 일은 '시작하기'다. **두 화면은 달라야 한다.**
    let noMessages = mwMenuStore(mwStore(host: "mw-render-empty"))
    noMessages.messageHistoryLoaded = true
    noMessages.pokeDirectory = [PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true)]
    noMessages.pokeDirectoryLoaded = true
    noMessages.openMessagePanel(peer: "u1")
    let emptyBitmap = try mwBitmap(noMessages)
    MessagePanelSnapshots.save(emptyBitmap, name: "panels-msg-empty.png")
    #expect(Double(emptyBitmap.pixelsHigh) / 2.0 <= mwPopoverHeightCap)
    #expect(
        mwDiffBounds(noPeerBitmap, emptyBitmap) != nil,
        "두 빈 상태가 같은 그림이다 — 사용자가 할 일이 다른데 같은 말을 하고 있다"
    )
    // 상대를 아는 화면은 **이름을 그린다**(콕찌르기 목록에서 온 이름이다 — 이력이 비어도 안다).
    #expect(noMessages.selectedMessagePeerName == "영식", "한 번도 대화한 적 없는 사람의 이름을 못 찾았다")

    // ③ 못 불러왔다 — 위 둘과 또 다른 문장 + [다시 시도].
    let failed = mwMenuStore(mwStore(host: "mw-render-failed"))
    failed.messageHistoryFailed = true
    failed.pokeDirectory = [PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true)]
    failed.openMessagePanel(peer: "u1")
    failed.messageHistoryLoaded = false
    failed.messageHistoryFailed = true
    let failedBitmap = try mwBitmap(failed)
    MessagePanelSnapshots.save(failedBitmap, name: "panels-msg-failed.png")
    #expect(mwDiffBounds(failedBitmap, emptyBitmap) != nil, "못 불러온 화면이 '아직 없어요'와 똑같이 그려졌다")
}

@MainActor
@Test
func twoHundredCharacterBodiesWrapInsideTheBubbleInsteadOfOverflowing() throws {
    // 200자 한 덩어리. `fixedSize(horizontal:)` 을 말풍선에 붙였다면 여기서 화면 밖으로 넘친다.
    let long = mwEntry(
        id: "long",
        peer: "u1",
        name: "영식",
        body: String(repeating: "가나다라마바사아자차", count: 20),
        minutesAgo: 5
    )
    let store = mwThreadStore(host: "mw-render-long", extra: [long])
    store.messageDraft = String(repeating: "답장 초안 ", count: 12)

    let bitmap = try mwBitmap(store)
    MessagePanelSnapshots.save(bitmap, name: "panels-msg-long.png")
    #expect(bitmap.pixelsWide == 414 * 2, "긴 본문이 팝오버 폭을 밀어냈다")
    #expect(Double(bitmap.pixelsHigh) / 2.0 <= mwPopoverHeightCap,
            "200자 대화가 700pt 상한을 넘었다: \(Double(bitmap.pixelsHigh) / 2.0)pt")
    let ink = try #require(mwDiffBounds(bitmap, try mwBlankBitmap(matching: bitmap)))
    #expect(ink.maxX <= CGFloat(bitmap.pixelsWide) - 2, "긴 본문이 화면 밖으로 넘쳤다 — 말풍선이 폭 상한을 안 지킨다")
    #expect(ink.maxY > CGFloat(bitmap.pixelsHigh) - 60, "200자 대화에서 푸터가 안 그려졌다")

    // 이모지도 양쪽 말풍선 모두 그려진다(3글자 시절에는 입력 자체가 이모지를 지웠다).
    let emoji = mwThreadStore(host: "mw-render-emoji", extra: [
        mwEntry(id: "e1", peer: "u1", name: "영식", body: "축하해요 🎉🎉", minutesAgo: 20),
        mwEntry(id: "e2", peer: "u1", name: "영식", body: "고마워요 👨‍👩‍👧‍👦 🇰🇷 👍🏻", minutesAgo: 18, isMine: true)
    ])
    emoji.messageDraft = "🎉 감사합니다"
    let emojiBitmap = try mwBitmap(emoji)
    MessagePanelSnapshots.save(emojiBitmap, name: "panels-msg-emoji.png")
    #expect(mwDiffBounds(emojiBitmap, try mwBlankBitmap(matching: emojiBitmap)) != nil)
    // 카운터는 **코드포인트**를 센다("🎉 감사합니다" = 1 + 1 + 5 = 7).
    #expect(emoji.messageDraftLength == 7)
}

@MainActor
@Test
func aLongPeerNameNeverPushesTheHeaderOffScreen() throws {
    let store = mwThreadStore(host: "mw-render-longname", extra: [
        mwEntry(id: "n1", peer: "u9", name: String(repeating: "김수한무", count: 6),
                body: "안녕하세요", minutesAgo: 1)
    ], peer: "u9")
    let bitmap = try mwBitmap(store)
    MessagePanelSnapshots.save(bitmap, name: "panels-msg-long-name.png")
    #expect(bitmap.pixelsWide == 414 * 2, "긴 이름이 팝오버 폭을 밀어냈다")
    let ink = try #require(mwDiffBounds(bitmap, try mwBlankBitmap(matching: bitmap)))
    #expect(ink.maxX <= CGFloat(bitmap.pixelsWide) - 2, "긴 이름이 머리 줄을 밀어냈다")
}

@MainActor
@Test
func theMessagePanelStaysUnderTheCapWithTheTallestChromeOnTop() throws {
    // ★ **이 작업 최악의 결함이 창 높이 회귀다.** 새 버전 배너 + 패치노트 4줄(149pt) + 주간 목표 편집
    //   인라인 행(92pt) = 241pt 가 함께 선 가장 키 큰 조합까지 그려 700pt 를 안 넘고 **푸터가 살아 있는지** 본다.
    let store = mwThreadStore(host: "mw-render-tallest", extra: [
        mwEntry(id: "long", peer: "u1", name: "영식",
                body: String(repeating: "가나다라마바사아자차", count: 20), minutesAgo: 5)
    ])
    store.messageDraft = String(repeating: "답장 초안 ", count: 12)
    store.messageNotice = WorkTimerStore.messageInvalidNotice

    let bitmap = try mwBitmap(store, worstChrome: true)
    MessagePanelSnapshots.save(bitmap, name: "panels-tallest.png")
    let height = Double(bitmap.pixelsHigh) / 2.0
    #expect(height <= mwPopoverHeightCap, "가장 키 큰 대화 조합이 700pt 를 넘었다: \(height)pt")
    let ink = try #require(mwDiffBounds(bitmap, try mwBlankBitmap(matching: bitmap)))
    #expect(ink.maxY > CGFloat(bitmap.pixelsHigh) - 60, "가장 키 큰 조합에서 푸터가 안 그려졌다")
    #expect(ink.maxX <= CGFloat(bitmap.pixelsWide) - 2)
}

@MainActor
@Test
func thePokeListIsTheOnlyDoorAndItShowsWhatIsUnread() throws {
    // 스냅샷 `panels-poke-entry.png` — **진입 지점**이다. 말풍선 버튼을 누르면 그 사람과의 대화로 넘어간다.
    let store = mwMenuStore(mwStore(host: "mw-render-poke-entry"))
    store.pokeDirectory = [
        PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true),
        PokeDirectoryEntry(userID: "u2", name: "김서연", avatarURL: nil, isWorking: true),
        PokeDirectoryEntry(userID: "u3", name: "박도윤", avatarURL: nil, isWorking: false)
    ]
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    // u2 에게서 온 것은 안 읽음이다(도장이 없다) → 말풍선 버튼에 점이 붙는다.
    store.messageHistory = [mwEntry(id: "b1", peer: "u2", name: "김서연", body: "점심?", minutesAgo: 5)]
    store.messageHistoryLoaded = true
    store.receivedMessages = [
        ReceivedMessage(
            id: "m1",
            fromName: "김서연",
            body: String(repeating: "긴 본문이 행을 밀어내지 않는지 보는 줄 ", count: 6),
            createdAt: mwNow.addingTimeInterval(-120),
            fromUserID: "u2"
        )
    ]

    let bitmap = try mwBitmap(store)
    MessagePanelSnapshots.save(bitmap, name: "panels-poke-entry.png")
    #expect(Double(bitmap.pixelsHigh) / 2.0 <= mwPopoverHeightCap)

    // 안 읽음 점이 **화면을 바꾼다**(안 그러면 그 개념이 앱 어디에도 안 보인다).
    let read = mwMenuStore(mwStore(host: "mw-render-poke-entry-read"))
    read.pokeDirectory = store.pokeDirectory
    read.pokeDirectoryLoaded = true
    read.isPokePanelVisible = true
    read.messageHistory = store.messageHistory
    read.messageHistoryLoaded = true
    read.messageReadStamps = ["u2": mwNow]
    read.receivedMessages = store.receivedMessages
    #expect(read.unreadMessagePeerIDs.isEmpty && store.unreadMessagePeerIDs == ["u2"])
    let readBitmap = try mwBitmap(read)
    #expect(mwDiffBounds(bitmap, readBitmap) != nil, "안 읽은 것이 있는데 말풍선 버튼이 똑같이 그려졌다")

    // 팝오버 폭은 본문 길이에 끌려다니지 않는다 — 옛 수신 줄의 `.fixedSize()` 가 정확히 이 성질을 깼다.
    store.receivedMessages = [
        ReceivedMessage(id: "m1", fromName: "김서연", body: "밥?", createdAt: mwNow.addingTimeInterval(-120), fromUserID: "u2")
    ]
    let shortBitmap = try mwBitmap(store)
    #expect(bitmap.pixelsWide == shortBitmap.pixelsWide, "긴 본문이 팝오버 폭을 밀어냈다")
    #expect(bitmap.pixelsHigh == shortBitmap.pixelsHigh, "긴 본문이 수신 줄을 여러 줄로 키웠다")
}

// MARK: - 패널 계약 (v0.2.50 — 창이 사라졌다)

@MainActor
@Test
func theMessageWindowIsGoneAndNothingStillWiresIt() throws {
    // 사용자 지시 1의 확인 질문 답: **"팝오버 안에서 전환"**(창이 하나도 안 뜨는 쪽).
    // 창 계약을 재던 테스트는 잴 대상이 사라졌다 — 대신 "정말 사라졌는가"를 소스로 못 박는다.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for name in ["CheckMessageWindow.swift", "CheckFeedbackWindow.swift"] {
        let url = root.appendingPathComponent("Sources/check/\(name)")
        #expect(!FileManager.default.fileExists(atPath: url.path), "\(name) 이 아직 있다")
    }
    // 배선도 함께 사라졌다(남아 있으면 컴파일은 되는데 아무도 안 여는 창 컨트롤러가 앱에 산다).
    let app = mwStripComments(try String(contentsOf: root.appendingPathComponent("Sources/check/CheckApp.swift"), encoding: .utf8))
    #expect(!app.contains("CheckMessageWindowController"), "CheckApp 이 아직 메시지 창을 배선한다")
    #expect(!app.contains("CheckFeedbackWindowController"), "CheckApp 이 아직 제보 창을 배선한다")
    // 대조군: **설정·미니게임은 여전히 창이다**(함께 지웠다면 그건 요구를 넘어선 파괴다).
    #expect(app.contains("CheckSettingsWindowController"))
    #expect(app.contains("CheckMiniGameWindowController"))
}

@MainActor
@Test
func openingTheConversationClosesEveryOtherPanelAndNeverTouchesThePopover() throws {
    let store = mwStore(host: "mw-panel-exclusive")
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.isInsightsPanelVisible = true
    store.isFeedbackPanelVisible = true

    store.openMessagePanel(peer: "u1")

    #expect(store.isMessagePanelVisible)
    #expect(!store.isLeaderboardVisible && !store.isTokenBoardVisible)
    #expect(!store.isInsightsPanelVisible && !store.isFeedbackPanelVisible)
    #expect(!store.isPokePanelVisible && !store.isUltraPanelVisible, "다른 패널이 대화 뒤에 살아 남았다")

    // ★ **팝오버를 닫지 않는다.** 창이던 시절에는 진입점이 `dismissMenuPopover()` 를 불렀는데,
    //   지금 그러면 방금 연 대화가 그 자리에서 사라진다. 주석은 걷어내고 본다.
    let code = try mwSource("WorkTimerStoreMessages.swift")
    #expect(!code.contains("dismissMenuPopover"), "대화 진입점이 아직 팝오버를 닫는다 — 패널은 팝오버 안에 산다")
}

@MainActor
@Test
func theOverlayBubbleOpensTheConversationOfWhoeverSentIt() throws {
    // 캐릭터 머리 위 도착 말풍선 클릭 배선. 창이 사라졌으니 갈 곳은 팝오버 **안**이다.
    //
    // ⚠️ **헤드리스에서 잴 수 있는 것은 여기까지다.** "정말 팝오버가 떴는가"는 창 서버를 흉내 낼 수
    //    없어서 이 프로세스로 못 잰다(닫는 문 `dismissMenuPopover` 도 v0.2.49 부터 같은 한계 안에 있고,
    //    그쪽 실측 표는 별도 재현 앱에서 CGWindowList 로 밖에서 센 것이다). 그래서 두 가지만 잰다:
    //    ① 배선이 상대를 실어 나른다 ② 여는 판정이 닫는 판정과 **같은 함수** 하나다.
    let app = mwStripComments(try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check/CheckApp.swift"),
        encoding: .utf8
    ))
    #expect(app.contains("onOpenMessages"), "말풍선 클릭 배선이 사라졌다 — 눌러도 아무 일이 없다")
    #expect(app.contains("openMessagePanel(peer:"), "말풍선이 상대를 안 실어 보낸다 — 빈 화면이 열린다")
    #expect(app.contains("from: .overlay"), "말풍선 진입이 콕찌르기에서 온 것으로 기록된다 — [뒤로]가 엉뚱한 곳으로 간다")
    #expect(app.contains("WindowTopAnchor.presentMenuPopover()"), "패널만 세우고 팝오버를 안 연다")

    // 여는 판정과 닫는 판정이 **한 함수**다(누르는 수단이 토글 하나라 두 벌로 나뉘면 언젠가 갈린다).
    let now = Date(timeIntervalSince1970: 1_789_000_000)
    #expect(
        WindowTopAnchor.menuPopoverToggleDecision(
            intent: .present, presented: false, hasStatusItem: true, lastClickAt: nil, now: now
        ) == .click
    )
    // 이미 떠 있으면 누르지 않는다 — 누르면 오히려 닫힌다.
    #expect(
        WindowTopAnchor.menuPopoverToggleDecision(
            intent: .present, presented: true, hasStatusItem: true, lastClickAt: nil, now: now
        ) == .alreadySettled
    )
    // 닫는 쪽은 정확히 반대다(같은 함수, 방향만 다르다).
    #expect(
        WindowTopAnchor.menuPopoverToggleDecision(
            intent: .dismiss, presented: true, hasStatusItem: true, lastClickAt: nil, now: now
        ) == .click
    )
    #expect(
        WindowTopAnchor.menuPopoverToggleDecision(
            intent: .dismiss, presented: false, hasStatusItem: true, lastClickAt: nil, now: now
        ) == .alreadySettled
    )
    // 디바운스는 **여닫기 공용**이다 — 방금 닫아 놓고 곧바로 열면 사용자가 보는 결과는 제자리다.
    #expect(
        WindowTopAnchor.menuPopoverToggleDecision(
            intent: .present, presented: false, hasStatusItem: true,
            lastClickAt: now.addingTimeInterval(-0.1), now: now
        ) == .debounced
    )
    // 상태 아이템이 없는 실행(헤드리스 테스트)에서는 아무 일도 안 한다.
    #expect(WindowTopAnchor.presentMenuPopover() == .noStatusItem || WindowTopAnchor.presentMenuPopover() == .debounced)
}

// MARK: - Enter 전송 (v0.2.51 — 사용자 지시 2026-09-11 ②)
//
// > "커멘드 엔터로 보내는게 아니라 엔터로 보내는게 보통 일반적인거 아니야? 메세지 입력하고 엔터로 보낼 수 있게 해줘."
//
// 판정은 `CheckEditorReturnKey.action` 한 함수다. **뷰 안에 두지 않은 이유**가 여기서 드러난다:
// 다섯 갈래 중 둘("조합 중" · "못 보내는 상태")의 정답이 **아무 일도 안 일어나는 것**이라, 뷰 안에 있으면
// 회귀가 나도 사람이 못 본다(줄이 조용히 생기거나, 쓰다 만 문장이 조용히 나간다).

@Test
func enterSendsAndShiftEnterBreaksTheLine() {
    // ① 평범한 Enter — 보낼 수 있으면 보낸다. 이 한 줄이 사용자 지시 ②다.
    #expect(CheckEditorReturnKey.action(
        sendsOnReturn: true, hasShift: false, isComposing: false, canSend: true
    ) == .send)
    // ② ⇧Enter — 언제나 줄바꿈이다(200자를 여러 줄로 쓰는 길이 사라지면 안 된다).
    #expect(CheckEditorReturnKey.action(
        sendsOnReturn: true, hasShift: true, isComposing: false, canSend: true
    ) == .newline)
    // ③ 보낼 수 없는 상태 — **줄바꿈도 아니다**. 빈 칸에서 Enter 를 눌렀는데 줄만 늘어나면
    //    사용자는 "안 보내진다"가 아니라 "칸이 이상하다"로 읽는다.
    #expect(CheckEditorReturnKey.action(
        sendsOnReturn: true, hasShift: false, isComposing: false, canSend: false
    ) == .nothing)
}

@Test
func enterWhileMarkedTextIsUpCommitsInsteadOfSending() {
    // ★ **이 스위트에서 가장 값비싼 회귀다.** 입력기가 표시 글자(marked text)를 띄워 둔 순간의 Enter 는
    //   조합을 끝내는 키이지 보내는 키가 아니다. 여기서 .send 가 나오면 조합 중인 글자가 빠진 문장이 나간다.
    //   ⚠︎ macOS 2벌식 한글은 표시 글자를 안 쓴다(2026-09-11 실측 — CheckTextEditor 머리 주석). 그 입력기에서는
    //   첫 Enter 가 완성된 문장 전체를 보내고, 이 갈래는 표시 글자를 쓰는 입력기(일본어·중국어 등)를 지킨다.
    #expect(CheckEditorReturnKey.action(
        sendsOnReturn: true, hasShift: false, isComposing: true, canSend: true
    ) == .commitComposition)
    // 보낼 수 없는 상태에서도 조합은 끝낼 수 있어야 한다(상대를 아직 안 골랐어도 글은 쓴다).
    #expect(CheckEditorReturnKey.action(
        sendsOnReturn: true, hasShift: false, isComposing: true, canSend: false
    ) == .commitComposition)
    // 조합 중 ⇧Enter 는 IME 가 확정하고 줄이 바뀐다(시스템 기본 동작 그대로).
    #expect(CheckEditorReturnKey.action(
        sendsOnReturn: true, hasShift: true, isComposing: true, canSend: true
    ) == .newline)
}

@Test
func theFeedbackEditorNeverSendsOnEnter() {
    // 버그 설명은 여러 줄로 쓰는 글이다 — Enter 전송이 첫 문장만 보내고 나머지를 버린다.
    for composing in [false, true] {
        for shift in [false, true] {
            for canSend in [false, true] {
                #expect(CheckEditorReturnKey.action(
                    sendsOnReturn: false, hasShift: shift, isComposing: composing, canSend: canSend
                ) == .newline, "제보 칸에서 Enter 가 줄바꿈이 아니다(조합=\(composing) ⇧=\(shift))")
            }
        }
    }
}

@Test
func returnKeyMeansBothTheMainAndKeypadEnter() {
    #expect(CheckEditorReturnKey.isReturn(keyCode: 36))   // ↩
    #expect(CheckEditorReturnKey.isReturn(keyCode: 76))   // 키패드 ⌤
    #expect(!CheckEditorReturnKey.isReturn(keyCode: 48))  // ⇥ — 탭 순회를 삼키면 접근성이 죽는다
    #expect(!CheckEditorReturnKey.isReturn(keyCode: 49))  // 스페이스
}

@MainActor
@Test
func theThreeWaysToSendAllGoThroughTheSameDoor() throws {
    // 버튼 · ⌘↩ · ↩ 이 서로 다른 문을 지나면 언젠가 판정이 갈리고, 갈린 쪽은 아무 화면에도 안 보인다.
    let view = try mwSource("CheckMessageView.swift")
    #expect(view.contains("keyboardShortcut(.return, modifiers: .command)"), "⌘↩ 이 사라졌다 — 손버릇을 깼다")
    #expect(view.contains("onSend: { store.sendDraftMessage() }"), "Enter 가 전송 문을 안 지난다")
    #expect(view.contains("canSendNow: { store.canSendMessageNow }"), "Enter 가 버튼과 다른 조건을 본다")
    // 메시지 칸만 Enter 로 보낸다 — 이 인자 하나가 false 가 되면 앱에서 Enter 는 영영 안 보낸다(2026-09-11 검증에서
    // 이 줄을 바꿔도 전부 초록이었다). 동작은 `theMountedMessageEditorSendsOnEnterAndBreaksTheLineOnShiftEnter` 가
    // 올린 그대로 재고, 여기서는 그 자리를 소스로 한 번 더 못 박는다.
    #expect(view.contains("sendsOnReturn: true"), "메시지 칸이 Enter 전송을 안 켰다")
    // 툴팁은 상수가 아니라 `sendHelp` 계산을 거쳐 버튼에 붙는다 — 붙이는 줄이 사라지면 ⇧↩ 를 말하는 자리가 없어진다.
    #expect(view.contains(".help(sendHelp)"), "[보내기] 버튼에 툴팁이 안 붙는다")
    // 메시지 칸만 Enter 로 보낸다. 제보 칸에 `sendsOnReturn: true` 가 생기면 그건 사고다.
    #expect(!(try mwSource("CheckFeedbackView.swift").contains("sendsOnReturn")),
            "제보 칸이 Enter 전송을 켰다 — 버그 설명이 반토막 난다")

    // 화면의 문구도 ↩ 를 말한다(옛 ⌘↩ 안내가 남아 있으면 사용자는 Enter 를 시도조차 안 한다).
    #expect(MessageDraftEditor.placeholder == "메시지를 입력하세요 · ↩ 전송")
    #expect(MessageDraftEditor.sendHelp == "보내기 (↩) · 줄바꿈은 ⇧↩")
    #expect(!MessageDraftEditor.placeholder.contains("⌘"), "placeholder 가 아직 ⌘↩ 를 말한다")
}

@MainActor
@Test
func theEditorHandlesEditingShortcutsOnlyWhileFocused() throws {
    // 앱에는 SwiftUI 가 세운 **보이지 않는 Edit 메뉴가 있다**(2026-09-11 AX 실측 — 처음 이 테스트는 "메뉴가 없다"는
    // 틀린 전제 위에 서 있었다). 그래도 이 칸은 첫 응답자일 때 편집 단축키를 직접 받는다(CheckTextEditor.swift 머리 주석).
    // 여기서는 처리기의 자리를 소스로 못 박고, 동작은 아래 합성 이벤트 테스트들이 잰다
    // (⌘V·⌘C·⌘X 는 스파이로, ⌘A·⌘Z·⇧⌘Z 는 진짜 텍스트 뷰로, 포커스 가드는 다른 입력칸과 한 창에 세워서).
    let source = try mwSource("CheckTextEditor.swift")
    #expect(source.contains("performKeyEquivalent"), "편집 단축키를 받는 자리가 사라졌다")
    #expect(source.contains("guard window?.firstResponder === self"), "포커스 없는 칸이 편집 단축키를 가로챈다")
    for call in ["paste(nil)", "selectAll(nil)", "undoManager?.undo()"] {
        #expect(source.contains(call), "표준 편집 명령이 빠졌다: \(call)")
    }
    #expect(source.contains("allowsUndo = true"), "되돌리기가 꺼져 있다")
    // 다크 화면이다. 에디터가 자기 배경을 그리면 흰 상자가 뚫린다.
    #expect(source.contains("drawsBackground = false"))
    // 조합 중 되쓰기 금지 — 이 가드가 사라지면 마지막 글자가 씹힌다(헤드리스로 못 잡는 회귀다).
    #expect(source.contains("guard !textView.hasMarkedText()"), "조합 중 되쓰기 가드가 사라졌다")
}

// MARK: - placeholder 와 실제 글자의 자리 (v0.2.51 — 사용자 지시 2026-09-11 ③)
//
// > "메세지 입력하는 텍스트 있는곳이랑 실제 텍스트 입력하는곳이랑 높이가 안맞아. 수정해줘.
// >  이건 제보 창에서도 똑같이 발생해."
//
// ★ **`ImageRenderer` 로는 이걸 못 잰다.** AppKit 을 감싼 뷰를 못 그려서, 재려는 그 글자가 그림에 없다.
//   그래서 여기서만 `NSHostingView` + `cacheDisplay(in:to:)` 로 **AppKit 이 직접 그린 픽셀**을 받는다 —
//   진짜 `NSTextView` 가 그린 글자를 재야 이 측정이 의미가 있다.
//
// 재는 법: 같은 칸을 세 번 그린다.
//   ① 빈 칸(placeholder 만 보인다)  ② 공백 한 칸(placeholder 도 글자도 없다 = 기준판)  ③ 글자 하나
// ①−② 가 placeholder 첫 글자의 잉크, ③−② 가 실제 글자의 잉크다. 두 잉크의 **좌상단**을 비교한다.
// placeholder 와 같은 글자를 넣는 이유는 자간·글자 모양이 달라 생기는 차이를 빼기 위해서다.

private enum MWEditorInk {
    /// 그림의 배율. **2x 로 그린다** — 1pt 를 재는 자에 눈금이 1pt 밖에 없으면 1pt 어긋남과 0pt 를
    /// 구별할 수 없다(그리고 사용자가 실제로 보는 화면이 Retina 다).
    static let scale: CGFloat = 2

    /// AppKit 이 실제로 그린 픽셀. `ImageRenderer` 와 달리 `NSTextView` 가 그려진다.
    @MainActor
    static func bitmap<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: AnyView(
            view.frame(width: width, height: height).background(CheckTheme.background)
        ))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        // 창에 붙여야 NSTextView 가 레이아웃을 끝낸다(문서 뷰는 스크롤 뷰의 크기를 창에서 받는다).
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // 텍스트 뷰가 자기 글자를 배치할 시간을 준다(레이아웃 매니저는 게으르다).
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        // 헤드리스 실행에는 화면이 없어서 `bitmapImageRepForCachingDisplay` 가 1x 를 돌려준다.
        // 배율을 그림에 못 박기 위해 픽셀 수를 직접 잡고 그 안에 그린다.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw MWRenderError.failed }
        rep.size = NSSize(width: width, height: height)   // pt 크기 < 픽셀 수 = 2x
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw MWRenderError.failed }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        host.displayIgnoringOpacity(host.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 기준판과 달라진 픽셀의 경계. 좌상단이 곧 첫 글자의 자리다.
    static func bounds(_ bitmap: NSBitmapImageRep, base: NSBitmapImageRep, tolerance: Double = 0.05) -> CGRect? {
        let width = min(bitmap.pixelsWide, base.pixelsWide)
        let height = min(bitmap.pixelsHigh, base.pixelsHigh)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                guard let a = bitmap.colorAt(x: x, y: y), let b = base.colorAt(x: x, y: y) else { continue }
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
}

@MainActor
@Test
func thePlaceholderAndTheTypedLetterSitInTheSamePlace() throws {
    let width = MessagePanelLayout.contentWidth
    let height = MessagePanelLayout.editorHeight
    // 기준판: 공백 한 칸 — placeholder 는 숨고(비어 있지 않다) 글자는 잉크를 안 남긴다.
    let base = try MWEditorInk.bitmap(
        MessageDraftEditor(text: .constant(" "), height: height), width: width, height: height
    )
    let empty = try MWEditorInk.bitmap(
        MessageDraftEditor(text: .constant(""), height: height), width: width, height: height
    )
    // placeholder 의 첫 글자와 **같은 글자**를 넣는다(글자 모양 차이를 빼기 위해서다).
    let first = String(MessageDraftEditor.placeholder.prefix(1))
    let typed = try MWEditorInk.bitmap(
        MessageDraftEditor(text: .constant(first), height: height), width: width, height: height
    )
    MessagePanelSnapshots.save(empty, name: "editor-msg-empty.png")
    MessagePanelSnapshots.save(typed, name: "editor-msg-one-letter.png")

    let scale = Double(empty.pixelsWide) / Double(width)   // 1x 인지 2x 인지 그림이 말한다
    let placeholderInk = try #require(MWEditorInk.bounds(empty, base: base), "placeholder 가 안 그려졌다")
    let typedInk = try #require(MWEditorInk.bounds(typed, base: base), "실제 글자가 안 그려졌다 — NSTextView 가 안 그려진다")

    // 2026-09-11 실측(2x, 픽셀):
    //   고치기 전 — placeholder (19, 15) / 글자 (22, 11) → **가로 1.5pt · 세로 2.0pt 어긋남**
    //   고친 뒤   — placeholder (19, 15) / 글자 (20, 15) → 가로 0.5pt · 세로 0pt
    // 세로 2pt 는 옛 `TextEditor` 의 `.padding(.vertical, 4)` 와 placeholder 7 의 차이가,
    // 가로 1.5pt 는 `lineFragmentPadding` 5 + padding 6 = 11 과 placeholder 10 의 차이가 만든 것이다.
    let dx = abs(placeholderInk.minX - typedInk.minX) / scale
    let dy = abs(placeholderInk.minY - typedInk.minY) / scale
    #expect(dx <= 1.0, "가로가 \(dx)pt 어긋났다 (placeholder \(placeholderInk.minX)px / 글자 \(typedInk.minX)px, \(scale)x)")
    #expect(dy <= 1.0, "세로가 \(dy)pt 어긋났다 (placeholder \(placeholderInk.minY)px / 글자 \(typedInk.minY)px, \(scale)x)")
}

@MainActor
@Test
func theFeedbackEditorLinesUpTheSameWay() throws {
    let width = FeedbackPanelLayout.contentWidth
    let height = FeedbackPanelLayout.editorHeight
    let base = try MWEditorInk.bitmap(
        FeedbackBodyEditor(text: .constant(" "), height: height), width: width, height: height
    )
    let empty = try MWEditorInk.bitmap(
        FeedbackBodyEditor(text: .constant(""), height: height), width: width, height: height
    )
    let first = String(FeedbackText.placeholder.prefix(1))
    let typed = try MWEditorInk.bitmap(
        FeedbackBodyEditor(text: .constant(first), height: height), width: width, height: height
    )
    MessagePanelSnapshots.save(empty, name: "editor-feedback-empty.png")
    MessagePanelSnapshots.save(typed, name: "editor-feedback-one-letter.png")

    let scale = Double(empty.pixelsWide) / Double(width)
    let placeholderInk = try #require(MWEditorInk.bounds(empty, base: base), "제보 placeholder 가 안 그려졌다")
    let typedInk = try #require(MWEditorInk.bounds(typed, base: base), "제보 칸의 실제 글자가 안 그려졌다")
    // 2026-09-11 실측(2x, 픽셀):
    //   고치기 전 — placeholder (20, 17) / 글자 (22, 11) → **가로 1.0pt · 세로 3.0pt 어긋남**
    //     (제보 칸이 더 벌어져 있었다: placeholder 세로 8 vs `TextEditor` 4 — 사용자가 "제보 창에서도
    //      똑같이 발생해"라고 말한 그 차이다.)
    //   고친 뒤   — placeholder (20, 15) / 글자 (20, 15) → 가로 0pt · 세로 0pt
    let dx = abs(placeholderInk.minX - typedInk.minX) / scale
    let dy = abs(placeholderInk.minY - typedInk.minY) / scale
    #expect(dx <= 1.0, "제보 칸 가로가 \(dx)pt 어긋났다")
    #expect(dy <= 1.0, "제보 칸 세로가 \(dy)pt 어긋났다")
}

@MainActor
@Test
func theComposerDrawsItsFourStatesWithTheRealTextView() throws {
    // 스펙이 요구하는 네 장: 빈 칸 · 한 글자 · 여러 줄 · 초과(빨간 테두리).
    // **진짜 NSTextView 로 그린다** — 대체 경로가 아니라 사용자가 보는 그림이다.
    let width = MessagePanelLayout.contentWidth
    let height = MessagePanelLayout.editorHeight
    let cases: [(String, String, Bool)] = [
        ("editor-state-empty.png", "", false),
        ("editor-state-one.png", "가", false),
        ("editor-state-multiline.png", "첫 줄입니다\n둘째 줄입니다\n셋째 줄입니다", false),
        ("editor-state-overflow.png", String(repeating: "가나다라마바사아자차", count: 21), true)
    ]
    var previous: NSBitmapImageRep?
    for (name, text, overflowing) in cases {
        let bitmap = try MWEditorInk.bitmap(
            MessageDraftEditor(text: .constant(text), height: height, isOverflowing: overflowing),
            width: width, height: height
        )
        MessagePanelSnapshots.save(bitmap, name: name)
        let scale = Double(bitmap.pixelsWide) / Double(width)
        #expect(Double(bitmap.pixelsHigh) / scale == Double(height),
                "\(name) 이 칸 높이를 벗어났다 — 에디터가 패널을 삼킨다")
        if let previous { #expect(MWEditorInk.bounds(bitmap, base: previous) != nil, "\(name) 이 앞 상태와 똑같이 그려졌다") }
        previous = bitmap
    }
    // 세 줄은 54pt 안에 다 보인다(`CheckEditorMetrics.inset` 세로 7 의 근거).
    #expect(height - 2 * CheckEditorMetrics.inset.height >= 13 * 3)
}

@MainActor
@Test
func theAdminNoteFallbackSitsWhereTheRealFieldDoes() throws {
    // 관리자 메모 칸은 `TextField` 라 placeholder 를 **자기가** 그린다 — 그래서 실물에서는 placeholder 와
    // 글자가 애초에 같은 자리다(사용자 지시 ③의 결함이 없는 칸이다). 여기서 재는 것은 다른 것이다:
    // **스냅샷 대체 경로가 실물과 같은 자리에 그리는가.** 두 자리가 다르면 렌더 테스트가 "괜찮다"고
    // 말하는 화면과 사용자가 보는 화면이 갈린다(이 저장소가 `Menu` 노란 상자에서 8일간 겪은 그 눈가리개다).
    let width = FeedbackPanelLayout.contentWidth
    let height: CGFloat = 30
    let base = try MWEditorInk.bitmap(
        FeedbackNoteField(text: .constant(" ")), width: width, height: height
    )
    let real = try MWEditorInk.bitmap(
        FeedbackNoteField(text: .constant("어")), width: width, height: height
    )
    let plain = try MWEditorInk.bitmap(
        FeedbackNoteField(text: .constant("어"), rendersPlainText: true), width: width, height: height
    )
    MessagePanelSnapshots.save(real, name: "editor-note-real.png")
    MessagePanelSnapshots.save(plain, name: "editor-note-plain.png")

    let scale = MWEditorInk.scale
    let realInk = try #require(MWEditorInk.bounds(real, base: base), "진짜 메모 칸의 글자가 안 그려졌다")
    let plainInk = try #require(MWEditorInk.bounds(plain, base: base), "대체 경로의 글자가 안 그려졌다")
    let dx = abs(realInk.minX - plainInk.minX) / scale
    let dy = abs(realInk.minY - plainInk.minY) / scale
    #expect(dx <= 1.0, "메모 칸 가로가 \(dx)pt 어긋났다 (실물 \(realInk.minX)px / 대체 \(plainInk.minX)px)")
    #expect(dy <= 1.0, "메모 칸 세로가 \(dy)pt 어긋났다 (실물 \(realInk.minY)px / 대체 \(plainInk.minY)px)")
}

// MARK: - 진짜 텍스트 뷰의 키 처리 (합성 NSEvent)
//
// 순수 판정만 재면 "판정은 맞는데 뷰가 그 판정을 안 따른다"를 못 잡는다. 그래서 진짜 `CheckEditorTextView` 에
// 합성 키 이벤트를 넣고 **글자와 전송 횟수**를 본다.
// ⚠︎ 실제 입력기는 이 프로세스에서 돌지 않는다 — 표시 글자는 `setMarkedText` 로 직접 심는다. 실제 입력기로
//   친 결과(2벌식 한글은 표시 글자를 안 쓴다)는 CheckTextEditor 머리 주석에 적힌 하네스 실측이다.
// ⚠︎ 진짜 ⌘V·⌘C·⌘X 는 부르지 않는다 — `NSPasteboard.general` 을 건드리면 테스트가 사용자 클립보드를 덮어쓴다.
//   그 셋은 명령을 가로채 기록만 하는 스파이(`MWEditingSpyTextView`, 파일 끝)로 "어느 명령에 닿는가"만 잰다.

@MainActor
private final class MWSendCounter {
    var count = 0
}

@MainActor
private func mwEditorTextView(
    _ text: String, sendsOnReturn: Bool, canSend: Bool
) -> (CheckEditorTextView, NSWindow, MWSendCounter) {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 292, height: 54), styleMask: [.borderless], backing: .buffered, defer: false
    )
    let textView = CheckEditorTextView(frame: NSRect(x: 0, y: 0, width: 292, height: 54))
    window.contentView = textView
    window.makeFirstResponder(textView)
    textView.string = text
    textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    textView.sendsOnReturn = sendsOnReturn
    textView.canSendNow = { canSend }
    let counter = MWSendCounter()
    textView.onSend = { counter.count += 1 }
    return (textView, window, counter)
}

@MainActor
private func mwKeyEvent(
    _ window: NSWindow, keyCode: UInt16, characters: String, ignoring: String, flags: NSEvent.ModifierFlags = []
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: ignoring,
        isARepeat: false, keyCode: keyCode
    )!
}

@MainActor
@Test
func theRealTextViewSendsOnEnterAndBreaksTheLineOnShiftEnter() {
    let (sendView, sendWindow, sent) = mwEditorTextView("안녕하세요", sendsOnReturn: true, canSend: true)
    sendView.keyDown(with: mwKeyEvent(sendWindow, keyCode: 36, characters: "\r", ignoring: "\r"))
    #expect(sent.count == 1, "Enter 가 전송을 안 불렀다")
    // 보내는 Enter 는 줄을 넣지 않는다(넣으면 스토어가 칸을 비우기 전 한 박자 동안 빈 줄이 카운터를 흔든다).
    #expect(sendView.string == "안녕하세요", "Enter 가 전송과 함께 줄바꿈까지 넣었다: \(sendView.string.debugDescription)")

    // 대조군: 같은 칸, 같은 글, ⇧ 만 다르다 — 그림이 달라야 이 두 단언이 의미가 있다.
    let (lineView, lineWindow, lineSent) = mwEditorTextView("안녕하세요", sendsOnReturn: true, canSend: true)
    lineView.keyDown(with: mwKeyEvent(lineWindow, keyCode: 36, characters: "\r", ignoring: "\r", flags: [.shift]))
    #expect(lineSent.count == 0, "⇧Enter 가 전송했다")
    #expect(lineView.string == "안녕하세요\n", "⇧Enter 가 줄을 안 바꿨다: \(lineView.string.debugDescription)")
}

@MainActor
@Test
func theRealTextViewDoesNothingOnEnterWhenItCannotSend() {
    let (view, window, sent) = mwEditorTextView("", sendsOnReturn: true, canSend: false)
    view.keyDown(with: mwKeyEvent(window, keyCode: 36, characters: "\r", ignoring: "\r"))
    #expect(sent.count == 0)
    #expect(view.string.isEmpty, "못 보내는 상태에서 Enter 가 줄을 넣었다: \(view.string.debugDescription)")
}

@MainActor
@Test
func theRealFeedbackTextViewBreaksTheLineOnEnter() {
    let (view, window, sent) = mwEditorTextView("재현 순서", sendsOnReturn: false, canSend: true)
    view.keyDown(with: mwKeyEvent(window, keyCode: 36, characters: "\r", ignoring: "\r"))
    #expect(sent.count == 0, "제보 칸이 Enter 로 전송했다 — 버그 설명이 반토막 난다")
    #expect(view.string == "재현 순서\n", "제보 칸 Enter 가 줄을 안 바꿨다: \(view.string.debugDescription)")
}

@MainActor
@Test
func theRealTextViewNeverSendsOrAddsALineWhileMarkedTextIsUp() {
    let (view, window, sent) = mwEditorTextView("안녕하세", sendsOnReturn: true, canSend: true)
    view.setMarkedText(
        "요", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    // 심기에 실패하면 아래 두 단언은 아무것도 안 잰다(그리고 영원히 초록이다).
    #expect(view.hasMarkedText(), "표시 글자를 못 심었다 — 이 테스트가 재는 것이 없다")
    view.keyDown(with: mwKeyEvent(window, keyCode: 36, characters: "\r", ignoring: "\r"))
    #expect(sent.count == 0, "표시 글자가 떠 있는데 Enter 가 전송했다 — 조합 중인 글자가 빠진 문장이 나간다")
    #expect(!view.string.contains("\n"), "조합 확정 Enter 가 줄을 넣었다: \(view.string.debugDescription)")
}

@Test
func editingShortcutsSurviveTheKoreanKeyboard() {
    // 2026-09-11 실측(2벌식 한글, ⌘V): characters "v" · charactersIgnoringModifiers "ㅍ".
    #expect(CheckEditorTextView.editingKey(characters: "v", ignoringModifiers: "ㅍ") == "v")
    // 반대 조합(⌘, 모니터가 겪은 쪽)도 영문 쪽을 고른다.
    #expect(CheckEditorTextView.editingKey(characters: "ㅍ", ignoringModifiers: "v") == "v")
    #expect(CheckEditorTextView.editingKey(characters: "Z", ignoringModifiers: "Z") == "z")
    // 영문이 하나도 없으면 아무 명령도 아니다 — 엉뚱한 편집 명령으로 접지 않는다.
    #expect(CheckEditorTextView.editingKey(characters: "ㅍ", ignoringModifiers: "ㅍ") == "")
    #expect(CheckEditorTextView.editingKey(characters: nil, ignoringModifiers: nil) == "")
}

@MainActor
@Test
func commandAOnTheKoreanKeyboardSelectsEverything() {
    let body = "전체 선택"
    let (view, window, _) = mwEditorTextView(body, sendsOnReturn: true, canSend: true)
    let event = mwKeyEvent(window, keyCode: 0, characters: "a", ignoring: "ㅁ", flags: [.command])
    #expect(view.performKeyEquivalent(with: event), "한글 자판의 ⌘A 를 안 받았다")
    #expect(view.selectedRange() == NSRange(location: 0, length: (body as NSString).length), "⌘A 가 전체를 안 골랐다")
    // 대조군: ⌘ 없는 'a' 는 편집 명령이 아니다(가로채면 입력이 죽는다).
    let plain = mwKeyEvent(window, keyCode: 0, characters: "a", ignoring: "a")
    #expect(!view.performKeyEquivalent(with: plain), "수식키 없는 글자를 편집 명령으로 가로챘다")
}

// MARK: - 올린 그대로의 배선 · 되돌리기 · 넘침 테두리 · 포커스 (2026-09-11 검증 지적 보완)
//
// 위 키 테스트는 `CheckEditorTextView` 를 직접 만들어 속성을 손으로 넣는다 — 그래서 `MessageDraftEditor` →
// `CheckTextEditor` → 텍스트 뷰로 이어지는 **배선**을 한 번도 안 지난다. 검증에서 `sendsOnReturn: true` 를 false 로,
// `textView.onSend = onSend` 를 `{}` 로 바꿔도 전부 초록이었다(앱에서는 Enter 가 영영 안 보내는 상태다).
// 여기서는 **SwiftUI 에 올린 그대로** 두고 안의 진짜 텍스트 뷰를 꺼내 잰다.

/// 스토어처럼 **관찰되는** 초안. 바깥에서 값을 바꾸면 SwiftUI 가 `updateNSView` 로 텍스트 뷰에 내려보낸다 —
/// 전송 성공 · 대화 상대 전환 · 제보 전송 성공에서 스토어가 초안을 비우는 바로 그 경로다.
@MainActor
@Observable
private final class MWDraftModel {
    var text: String
    init(_ text: String = "") { self.text = text }
}

private struct MWMountedMessageEditor: View {
    @Bindable var model: MWDraftModel
    let canSend: Bool
    let counter: MWSendCounter

    var body: some View {
        MessageDraftEditor(
            text: $model.text,
            height: MessagePanelLayout.editorHeight,
            canSendNow: { canSend },
            onSend: { counter.count += 1 }
        )
    }
}

private struct MWMountedFeedbackEditor: View {
    @Bindable var model: MWDraftModel

    var body: some View {
        FeedbackBodyEditor(text: $model.text, height: FeedbackPanelLayout.editorHeight)
    }
}

@MainActor
private func mwFirstSubview<T: NSView>(of root: NSView, _ type: T.Type) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = mwFirstSubview(of: child, type) { return match }
    }
    return nil
}

/// 런루프를 돌린다. 되돌리기 관리자는 **이벤트 한 바퀴** 단위로 묶음을 닫고, SwiftUI 는 관찰 변화를 다음 바퀴에
/// 내려보낸다 — 실제 앱에서 사람 손이 만드는 그 간격을 흉내 낸다(안 돌리면 한 묶음 안에서 되돌리기를 부르게 된다).
@MainActor
private func mwSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func mwSpin(until condition: () -> Bool) {
    var remaining = 100
    while !condition(), remaining > 0 {
        mwSpin(0.01)
        remaining -= 1
    }
}

/// SwiftUI 에 올린 입력칸 안의 **진짜** 텍스트 뷰를 꺼내 첫 응답자로 세운다(창이 입력칸을 붙들고 있다).
@MainActor
private func mwMount<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> (NSWindow, CheckEditorTextView) {
    let host = NSHostingView(rootView: view.frame(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    mwSpin()
    let textView = try #require(mwFirstSubview(of: host, CheckEditorTextView.self), "올린 입력칸 안에 진짜 텍스트 뷰가 없다")
    window.makeFirstResponder(textView)
    return (window, textView)
}

/// 사람이 치듯 한 글자씩 넣는다(입력기가 부르는 것과 같은 `insertText(_:replacementRange:)` — 되돌리기에 기록된다).
@MainActor
private func mwType(_ text: String, into textView: NSTextView) {
    for character in text {
        textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        mwSpin(0.01)
    }
    mwSpin()
}

@MainActor
@Test
func theMountedMessageEditorSendsOnEnterAndBreaksTheLineOnShiftEnter() throws {
    let model = MWDraftModel("안녕하세요")
    let counter = MWSendCounter()
    let (window, textView) = try mwMount(
        MWMountedMessageEditor(model: model, canSend: true, counter: counter),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    #expect(textView.string == "안녕하세요", "초안이 텍스트 뷰에 안 내려왔다")
    textView.setSelectedRange(NSRange(location: ("안녕하세요" as NSString).length, length: 0))

    textView.keyDown(with: mwKeyEvent(window, keyCode: 36, characters: "\r", ignoring: "\r"))
    #expect(counter.count == 1,
            "올린 그대로의 메시지 칸에서 Enter 가 전송을 안 불렀다 — MessageDraftEditor → CheckTextEditor → 텍스트 뷰 배선이 끊겼다")
    #expect(textView.string == "안녕하세요", "보내는 Enter 가 줄까지 넣었다: \(textView.string.debugDescription)")

    // 대조군: ⇧Enter 는 줄을 바꾸고, 그 줄이 **초안(바인딩)까지** 흘러야 한다(카운터·보내기 판정이 그 값을 본다).
    textView.keyDown(with: mwKeyEvent(window, keyCode: 36, characters: "\r", ignoring: "\r", flags: [.shift]))
    #expect(counter.count == 1, "⇧Enter 가 전송했다")
    #expect(textView.string == "안녕하세요\n", "⇧Enter 가 줄을 안 바꿨다: \(textView.string.debugDescription)")
    #expect(model.text == "안녕하세요\n", "줄바꿈이 초안으로 안 흘렀다: \(model.text.debugDescription)")
}

@MainActor
@Test
func theMountedMessageEditorIgnoresEnterWhenTheStoreCannotSend() throws {
    let model = MWDraftModel("")
    let counter = MWSendCounter()
    let (window, textView) = try mwMount(
        MWMountedMessageEditor(model: model, canSend: false, counter: counter),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    textView.keyDown(with: mwKeyEvent(window, keyCode: 36, characters: "\r", ignoring: "\r"))
    #expect(counter.count == 0, "보낼 수 없다는데 Enter 가 전송을 불렀다 — canSendNow 를 안 본다")
    #expect(textView.string.isEmpty && model.text.isEmpty, "못 보내는 상태의 Enter 가 줄을 넣었다: \(textView.string.debugDescription)")
}

@MainActor
@Test
func theMountedFeedbackEditorBreaksTheLineOnEnter() throws {
    let model = MWDraftModel("재현 순서")
    let (window, textView) = try mwMount(
        MWMountedFeedbackEditor(model: model),
        width: FeedbackPanelLayout.contentWidth, height: FeedbackPanelLayout.editorHeight
    )
    textView.setSelectedRange(NSRange(location: ("재현 순서" as NSString).length, length: 0))
    textView.keyDown(with: mwKeyEvent(window, keyCode: 36, characters: "\r", ignoring: "\r"))
    #expect(textView.string == "재현 순서\n", "올린 그대로의 제보 칸에서 Enter 가 줄을 안 바꿨다: \(textView.string.debugDescription)")
    #expect(model.text == "재현 순서\n", "제보 칸 줄바꿈이 초안으로 안 흘렀다: \(model.text.debugDescription)")
    #expect(!textView.sendsOnReturn, "제보 칸이 Enter 전송을 켰다 — 버그 설명이 반토막 난다")
}

@MainActor
@Test
func undoStillWorksAfterTheStoreClearsTheDraft() throws {
    // 2026-09-11 검증 재현(NSPopover 번들 앱 · 실제 키 이벤트): hello → Enter → 스토어가 초안을 비움 → ⌘Z 가 안에서
    // 멈추고(WillUndo 만 오고 DidUndo 없음) 되돌리기 묶음이 level 1 로 굳어, 그 창에서는 ⌘Z 가 **다시는** 안 됐다.
    let model = MWDraftModel("")
    let (window, textView) = try mwMount(
        MWMountedMessageEditor(model: model, canSend: true, counter: MWSendCounter()),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    let undoManager = try #require(textView.undoManager, "텍스트 뷰에 되돌리기 관리자가 없다")
    mwType("hello", into: textView)
    #expect(model.text == "hello", "타이핑이 초안으로 안 흘렀다: \(model.text.debugDescription)")
    // 전제: 타이핑이 기록돼야 아래가 뭔가를 잰다(기록이 애초에 없으면 이 테스트는 영원히 초록이다).
    try #require(undoManager.canUndo, "타이핑이 되돌리기에 안 쌓인다 — 이 테스트가 재는 것이 없다")

    // 스토어가 초안을 비운다(전송 성공 · 대화 상대 전환 · 제보 전송 성공).
    model.text = ""
    mwSpin(until: { textView.string.isEmpty })
    try #require(textView.string.isEmpty, "스토어가 비운 초안이 텍스트 뷰에 안 내려왔다 — updateNSView 배선이 끊겼다")

    // ★ 옛 타이핑 기록이 남아 있으면 다음 ⌘Z 는 없는 범위를 되돌리다 NSRangeException 으로 **테스트 프로세스째**
    //   죽는다(검증 헤드리스 재현). 그래서 누르기 전에 먼저 묻고, 남아 있으면 누르지 않고 실패로 끝낸다.
    guard !undoManager.canUndo else {
        Issue.record("바깥이 초안을 비운 뒤에도 옛 타이핑 기록이 남았다 — 다음 ⌘Z 가 예외로 멈추고 그 창의 되돌리기가 굳는다")
        return
    }
    let commandZ = mwKeyEvent(window, keyCode: 6, characters: "z", ignoring: "z", flags: [.command])
    #expect(textView.performKeyEquivalent(with: commandZ), "⌘Z 를 안 받았다")
    mwSpin()
    #expect(textView.string.isEmpty)
    #expect(undoManager.groupingLevel == 0, "⌘Z 뒤 되돌리기 묶음이 열린 채 굳었다 — 이 창의 ⌘Z 가 다시는 안 된다")

    // "기록을 지웠다"가 "되돌리기를 껐다"가 되면 안 된다 — 비운 뒤 새로 친 글자는 여전히 되돌려진다.
    mwType("abc", into: textView)
    #expect(textView.string == "abc")
    #expect(textView.performKeyEquivalent(with: commandZ), "⌘Z 를 안 받았다")
    mwSpin()
    #expect(textView.string.isEmpty, "비운 뒤 새로 친 글자를 ⌘Z 가 못 되돌렸다: \(textView.string.debugDescription)")
    #expect(model.text.isEmpty, "되돌린 결과가 초안으로 안 흘렀다: \(model.text.debugDescription)")
    let commandShiftZ = mwKeyEvent(window, keyCode: 6, characters: "Z", ignoring: "Z", flags: [.command, .shift])
    #expect(textView.performKeyEquivalent(with: commandShiftZ), "⇧⌘Z 를 안 받았다")
    mwSpin()
    #expect(textView.string == "abc", "⇧⌘Z 가 다시 하기를 안 했다: \(textView.string.debugDescription)")
}

/// 편집 명령을 **부르는 대신 기록만** 하는 텍스트 뷰. 진짜 ⌘V·⌘C·⌘X 는 사용자 클립보드를 읽고 덮어쓴다.
@MainActor
private final class MWEditingSpyTextView: CheckEditorTextView {
    var calls: [String] = []
    override func paste(_ sender: Any?) { calls.append("paste") }
    override func copy(_ sender: Any?) { calls.append("copy") }
    override func cut(_ sender: Any?) { calls.append("cut") }
    override func selectAll(_ sender: Any?) { calls.append("selectAll") }
}

@MainActor
@Test
func editingShortcutsReachTheirCommandsWithoutTouchingTheClipboard() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 292, height: 54), styleMask: [.borderless], backing: .buffered, defer: false
    )
    let spy = MWEditingSpyTextView(frame: NSRect(x: 0, y: 0, width: 292, height: 54))
    window.contentView = spy
    window.makeFirstResponder(spy)
    spy.string = "편집 대상"
    // (키 코드, 영문, 2벌식 한글 자판의 charactersIgnoringModifiers, 닿아야 할 명령)
    let shortcuts: [(UInt16, String, String, String)] = [
        (9, "v", "ㅍ", "paste"), (8, "c", "ㅊ", "copy"), (7, "x", "ㅌ", "cut"), (0, "a", "ㅁ", "selectAll")
    ]
    for (keyCode, latin, hangul, command) in shortcuts {
        let upper = latin.uppercased()
        spy.calls = []
        #expect(spy.performKeyEquivalent(
            with: mwKeyEvent(window, keyCode: keyCode, characters: latin, ignoring: hangul, flags: [.command])
        ), "한글 자판의 ⌘\(upper) 를 안 받았다")
        #expect(spy.calls == [command], "⌘\(upper) 가 \(command) 대신 \(spy.calls) 에 닿았다")
        // ⇧ 가 붙으면 이 넷에 들지 않는다 — 흘려보내야 한다(가로채면 ⇧⌘V 같은 다른 명령이 죽는다).
        spy.calls = []
        #expect(!spy.performKeyEquivalent(
            with: mwKeyEvent(window, keyCode: keyCode, characters: upper, ignoring: upper, flags: [.command, .shift])
        ), "⇧⌘\(upper) 를 가로챘다")
        #expect(spy.calls.isEmpty, "⇧⌘\(upper) 가 \(spy.calls) 에 닿았다")
    }
}

@MainActor
@Test
func editingShortcutsStayWithWhicheverFieldHasFocus() throws {
    // 2026-09-11 검증 지적: `performKeyEquivalent` 는 창의 뷰 계층 **전체**를 돈다. 첫 응답자 가드가 없으면
    // 같은 창의 다른 입력칸(목표 편집 등)에 포커스가 있어도 이 칸이 ⌘A·⌘V·⌘X 를 가로챈다.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 292, height: 120), styleMask: [.titled], backing: .buffered, defer: false
    )
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 292, height: 120))
    let field = NSTextField(frame: NSRect(x: 0, y: 90, width: 292, height: 24))
    field.stringValue = "목표 편집"
    let spy = MWEditingSpyTextView(frame: NSRect(x: 0, y: 0, width: 292, height: 54))
    spy.string = "메시지 초안"
    container.addSubview(field)
    container.addSubview(spy)
    window.contentView = container
    window.makeFirstResponder(field)
    try #require(window.firstResponder !== spy, "다른 칸에 포커스를 못 줬다 — 이 테스트가 재는 것이 없다")

    for (keyCode, latin) in [(UInt16(0), "a"), (9, "v"), (7, "x")] {
        #expect(!spy.performKeyEquivalent(
            with: mwKeyEvent(window, keyCode: keyCode, characters: latin, ignoring: latin, flags: [.command])
        ), "포커스가 없는 칸이 ⌘\(latin.uppercased()) 를 가로챘다 — 다른 입력칸의 편집 단축키가 이 칸으로 샌다")
    }
    #expect(spy.calls.isEmpty, "포커스가 없는 칸이 \(spy.calls) 를 불렀다")

    // 대조군: 같은 칸이 포커스를 받으면 받는다(가드가 "언제나 거절"로 굳은 게 아니다).
    window.makeFirstResponder(spy)
    #expect(spy.performKeyEquivalent(
        with: mwKeyEvent(window, keyCode: 0, characters: "a", ignoring: "a", flags: [.command])
    ), "포커스를 받은 칸이 ⌘A 를 안 받았다")
    #expect(spy.calls == ["selectAll"])
}

@MainActor
@Test
func theSendButtonTooltipTeachesEnterWhenItCanSend() {
    // 상수(`MessageDraftEditor.sendHelp`)만 재면, 버튼에 실제로 붙는 계산이 옛 "보내기 (⌘↩)" 를 돌려줘도 초록이다
    // (2026-09-11 검증에서 그 뮤테이션이 살아남았다). 그래서 [보내기] 버튼이 `.help` 로 받는 **그 계산**을 되묻는다.
    let store = mwStore(host: "mw-send-help-tooltip")
    store.selectedMessagePeerID = "u1"
    store.messageDraft = "안녕"
    let help = MessageComposerView(store: store).sendHelp
    #expect(help == MessageDraftEditor.sendHelp, "보낼 수 있는 상태의 [보내기] 툴팁이 ↩ · ⇧↩ 안내가 아니다: \(help)")
    // 대조군: 같은 계산이 상태를 실제로 본다 — 못 보내는 사유가 있으면 그 사유를 말한다.
    store.messageDraft = ""
    #expect(MessageComposerView(store: store).sendHelp == "보낼 말을 입력해 주세요")
}

/// 같은 칸을 실물(진짜 텍스트 뷰)과 스냅샷 대체 경로로 그려, **글자 좌상단의 차이(pt)** 를 잰다.
@MainActor
private func mwFallbackOffset(
    width: CGFloat, height: CGFloat, name: String, _ make: (String, Bool) -> AnyView
) throws -> (dx: Double, dy: Double, real: CGRect, plain: CGRect) {
    let base = try MWEditorInk.bitmap(make(" ", false), width: width, height: height)
    let real = try MWEditorInk.bitmap(make("가", false), width: width, height: height)
    let plain = try MWEditorInk.bitmap(make("가", true), width: width, height: height)
    MessagePanelSnapshots.save(real, name: "editor-\(name)-real.png")
    MessagePanelSnapshots.save(plain, name: "editor-\(name)-plain.png")
    let scale = Double(real.pixelsWide) / Double(width)
    let realInk = try #require(MWEditorInk.bounds(real, base: base), "\(name) 실물 글자가 안 그려졌다")
    let plainInk = try #require(MWEditorInk.bounds(plain, base: base), "\(name) 대체 경로 글자가 안 그려졌다")
    return (abs(realInk.minX - plainInk.minX) / scale, abs(realInk.minY - plainInk.minY) / scale, realInk, plainInk)
}

@MainActor
@Test
func theEditorFallbacksDrawTheLetterWhereTheRealTextViewDoes() throws {
    // 대체 경로(`rendersPlainText`)는 렌더 스냅샷이 쓰는 그림이다. 자리가 실물과 다르면 스냅샷이 "괜찮다"고 말하는 화면과
    // 사용자가 보는 화면이 갈린다(메모 칸 테스트와 같은 이유). 2026-09-11 검증에서 두 칸의 대체 경로 padding 을
    // (10,7) → (5,3) 으로 바꿔도 초록이었다.
    let message = try mwFallbackOffset(
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight, name: "msg-fallback"
    ) { text, plain in
        AnyView(MessageDraftEditor(text: .constant(text), height: MessagePanelLayout.editorHeight, rendersPlainText: plain))
    }
    #expect(message.dx <= 1.0 && message.dy <= 1.0,
            "메시지 칸 대체 경로가 실물과 (\(message.dx), \(message.dy))pt 어긋났다 (실물 \(message.real.origin) / 대체 \(message.plain.origin) px)")

    let feedback = try mwFallbackOffset(
        width: FeedbackPanelLayout.contentWidth, height: FeedbackPanelLayout.editorHeight, name: "feedback-fallback"
    ) { text, plain in
        AnyView(FeedbackBodyEditor(text: .constant(text), height: FeedbackPanelLayout.editorHeight, rendersPlainText: plain))
    }
    #expect(feedback.dx <= 1.0 && feedback.dy <= 1.0,
            "제보 칸 대체 경로가 실물과 (\(feedback.dx), \(feedback.dy))pt 어긋났다 (실물 \(feedback.real.origin) / 대체 \(feedback.plain.origin) px)")
}

/// 기준판과 달라진 픽셀 수 — 주어진 픽셀 줄 안에서만 센다.
private func mwChangedPixels(
    _ bitmap: NSBitmapImageRep, base: NSBitmapImageRep, rows: Range<Int>, tolerance: Double = 0.05
) -> Int {
    var count = 0
    for y in rows {
        for x in 0..<min(bitmap.pixelsWide, base.pixelsWide) {
            guard let a = bitmap.colorAt(x: x, y: y), let b = base.colorAt(x: x, y: y) else { continue }
            let delta = abs(a.redComponent - b.redComponent)
                + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
            if delta > tolerance { count += 1 }
        }
    }
    return count
}

@MainActor
@Test
func overflowingTextStaysInsideTheBorder() throws {
    // 2026-09-11 검증 지적: 스크롤 뷰가 둥근 사각형을 꽉 채워, 넘친 글의 걸친 줄이 **아래 테두리 선 위로** 그려졌다
    // (2x · 맨 아래 두 픽셀 줄의 글자 픽셀 227/206 — 옛 `TextEditor` 는 0/0). 넘침은 빨간 테두리로 알리는 상태라,
    // 그 테두리가 글자에 먹히면 경고가 경고로 안 읽힌다. 제보 칸도 같은 입력칸을 쓰므로 함께 잰다.
    let long = String(repeating: "가나다라마바사아자차", count: 21)
    let cases: [(String, CGFloat, CGFloat, (String) -> AnyView)] = [
        ("msg", MessagePanelLayout.contentWidth, MessagePanelLayout.editorHeight, {
            AnyView(MessageDraftEditor(text: .constant($0), height: MessagePanelLayout.editorHeight, isOverflowing: true))
        }),
        ("feedback", FeedbackPanelLayout.contentWidth, FeedbackPanelLayout.editorHeight, {
            AnyView(FeedbackBodyEditor(text: .constant($0), height: FeedbackPanelLayout.editorHeight))
        })
    ]
    for (name, width, height, make) in cases {
        let base = try MWEditorInk.bitmap(make(" "), width: width, height: height)
        let full = try MWEditorInk.bitmap(make(long), width: width, height: height)
        MessagePanelSnapshots.save(full, name: "editor-overflow-\(name).png")
        let scale = Double(full.pixelsWide) / Double(width)
        let ink = try #require(MWEditorInk.bounds(full, base: base), "\(name) 넘친 글이 안 그려졌다")
        // 전제: 글이 칸 아래쪽까지 차 있어야(넘쳐야) 테두리를 덮을 기회가 있다. 안 차면 아래 단언은 아무것도 안 잰다.
        #expect(Double(ink.maxY) >= Double(height - CheckEditorMetrics.inset.height) * scale,
                "\(name) 글이 칸 아래까지 안 찼다(잉크 maxY \(ink.maxY)px) — 이 테스트가 재는 것이 없다")
        // 맨 아래 1pt(테두리 선이 앉는 줄)는 글이 있든 없든 **똑같이** 그려져야 한다.
        let borderRows = (full.pixelsHigh - Int(scale))..<full.pixelsHigh
        let painted = mwChangedPixels(full, base: base, rows: borderRows)
        #expect(painted == 0, "\(name) 넘친 글이 아래 테두리 줄(맨 아래 1pt)에 \(painted)px 그려졌다 — 스크롤 뷰가 테두리 안쪽으로 안 물러났다")
    }
}
