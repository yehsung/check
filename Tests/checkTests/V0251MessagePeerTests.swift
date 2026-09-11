import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.51 — **고른 대화 상대는 서버 응답이 뭐라 하든 놓지 않는다.**
//
// 사용자 지적(2026-09-11):
//   "왜 메세지창에서 특정 사람의 프로필에 있는 대화 버튼을 눌러서 진입하는건데 대화 상대를 고르지
//    않았다고 떠? 애초에 대화상대를 고르지 않고 대화창에 진입할 수가 없어야되잖아."
//
// 원인은 `performLoadMessageHistory()` 가 응답에 그 사람 행이 없으면 선택을 지우던 줄이었다.
// **한 번도 대화한 적 없는 사람**에게는 이력에 행이 한 줄도 없으므로 그 조건이 언제나 참이고,
// 진입 직후 첫 왕복이 끝나는 순간 화면이 "대화 상대를 고르지 않았어요"로 바뀐다 —
// 사용자가 보기엔 "눌렀는데 엉뚱한 화면"이다.
//
// 이 스위트가 지키는 것은 하나다: **상대는 들어올 때 정해지고, 나갈 때까지 바뀌지 않는다.**
// 그래서 응답의 네 얼굴(빈 이력 · 만료 · 실패 · 늦게 온 앞 계정 응답)과 전송 성공을 각각 재고,
// 마지막으로 "그 화면이 무슨 문장을 내는가"까지 판정 함수로 확인한다(뷰 파일은 읽기만 한다).
//
// 사용자 재확인(2026-09-11): "만약에 다른사람한테 보내고 싶으면 나와서 그 다른사람 옆에 있는 대화창을
// 눌러서 진입하면 되는거야" — 그래서 **들어오는 문도** 좁혔다. `openMessagePanel(peer:)` 은 `String` 이고
// (nil 은 컴파일되지 않는다), 빈 문자열은 아무것도 안 하며, 보낸이를 모르는 캐릭터 말풍선은 대화 패널 대신
// 콕찌르기 목록을 연다. "상대 없이 들어오는 길이 없다"는 런타임으로 증명할 수 없으므로(없는 코드는 신호를
// 안 낸다) 소스 계약 테스트가 시그니처와 두 호출부 배선을 못 박는다.
//
// ★ 픽스처 본문은 전부 **합성 문자열**이다. 실제 대화를 테스트 파일로 옮겨 오지 마라 —
//   이 저장소는 퍼블릭이고, 두 사람이 주고받은 문장은 남에게 보여 주려고 쓴 것이 아니다.

private let mpUserID = "00000000-0000-0000-0000-0000000000b1"
private let mpHistoryPath = "/rest/v1/rpc/message_history"
private let mpSendPath = "/rest/v1/rpc/send_message"

/// 얼린 기준 시각. 값 자체에 뜻은 없고 **변하지 않는다는 사실**만 쓴다(벽시계 단언은 이 파일에 없다).
private let mpNow = Date(timeIntervalSince1970: 1_789_000_000)

// MARK: - 격리된 네트워크
//
// `FeedbackURLProtocol` 을 그대로 쓰지 않는 이유는 **지연**이다. "늦게 온 앞 계정 응답"을 재려면
// 왕복이 떠 있는 동안 `sessionGeneration` 을 올릴 창이 필요한데, 그 스텁은 즉답만 한다.
// 그 파일은 이 작업의 소유가 아니라 손잡이를 붙일 수 없어 여기에 최소한의 것을 하나 더 만든다.
// 호스트는 테스트마다 고유하다 — 기록이 프로세스 전역이라 이름을 나눠 쓰면 병렬 실행에서 서로를 센다.
private final class MPStub: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        /// 응답을 이만큼 미룬다(초). 0이면 즉답. 창의 폭만 정하는 값이라 단언의 정확성과는 무관하다 —
        /// 진입 시점은 시간이 아니라 **요청 기록**으로 잡는다.
        let delay: TimeInterval
        init(status: Int = 200, body: String = "[]", delay: TimeInterval = 0) {
            self.status = status
            self.body = body
            self.delay = delay
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var replies: [String: [String: Reply]] = [:]
    private nonisolated(unsafe) static var counts: [String: [String: Int]] = [:]

    static func set(_ reply: Reply, host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host, default: [:]][path] = reply
    }

    static func reset(host: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host] = nil
        counts[host] = nil
    }

    static func count(host: String, path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[host]?[path] ?? 0
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MPStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var isStopped = false

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.counts[host, default: [:]][path, default: 0] += 1
        let reply = Self.replies[host]?[path] ?? Reply()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let delivery = Delivery(proto: self, response: response, data: Data(reply.body.utf8))
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() { isStopped = true }

    /// 지연 전달을 클로저 밖으로 꺼낸 상자. 지역 캡처로 하면 Swift 6 동시성 검사가 막는다.
    private final class Delivery: @unchecked Sendable {
        let proto: MPStub
        let response: HTTPURLResponse
        let data: Data

        init(proto: MPStub, response: HTTPURLResponse, data: Data) {
            self.proto = proto
            self.response = response
            self.data = data
        }

        func run() {
            guard !proto.isStopped else { return }
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }
}

// MARK: - 헬퍼

@MainActor
private func mpDefaults() -> UserDefaults {
    let suite = "v0251-message-peer-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 격리 토큰 스토어. 홈·캐시·defaults·알림센터를 전부 임시로 준다(V0240TokenScanTests 의 v0240TokenStore 와 같은 패턴).
///
/// 왜 이 파일에 필요한가 — 아래 `mpStore` 는 `session` 과 `startedAt` 을 채우는데, 그 둘이
/// `refreshTokenUsageInBackgroundIfDue` 의 게이트 전부다. 주입하지 않으면 기본값 `TokenUsageStore.shared`
/// (= **실제 홈**)가 쓰이고, 폴링 루프가 도는 순간 사용자의 `~/.claude`·`~/.codex`·`~/.gemini` 를 훑는다.
/// v0.3.12 부터는 그 순회가 sqlite 로 대화 db 를 열어 **사용자 폴더에 `-shm` 까지 남겼다**(실측 2026-09-11).
/// 스토어 쪽에도 안전망을 걸었지만(`TokenUsageStore.realHomeScanIsBlocked`) 그건 그물이고, 배선은 여기서 바로잡는다.
@MainActor
private func mpTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let tag = UUID().uuidString
    return TokenUsageStore(
        defaults: mpDefaults(),
        homeDirectory: tmp.appendingPathComponent("v0251-token-home-\(tag)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("v0251-token-cache-\(tag).json", isDirectory: false),
        clock: { mpNow },
        notificationCenter: NotificationCenter()
    )
}

/// 스텁 네트워크에 물린 근무중·로그인 스토어. 시계는 **얼려서** 꽂는다 —
/// 읽음 도장이 벽시계에 흔들리면 부하 큰 병렬 실행에서 무음으로 뒤집힌다(이 저장소의 실측 회귀).
@MainActor
private func mpStore(host: String) -> WorkTimerStore {
    MPStub.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MPStub.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: mpDefaults(),
        // ★ 토큰 스토어를 **반드시** 주입한다(위 mpTokenStore 주석) — 기본값은 실제 홈을 훑는다.
        tokenUsage: mpTokenStore()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: mpUserID)
    store.clock = { mpNow }
    store.startedAt = mpNow.addingTimeInterval(-3_600)
    return store
}

/// 완료를 기다린다(시간을 재는 것이 아니다 — 단언에는 벽시계가 섞이지 않는다).
@MainActor
private func mpWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<400 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 이력 픽스처 한 건(스토어에 직접 꽂는 값).
private func mpEntry(id: String, peer: String, body: String, minutesAgo: Double) -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id,
        peerUserID: peer,
        peerName: "상대\(peer)",
        peerAvatarURL: nil,
        body: body,
        createdAt: mpNow.addingTimeInterval(-minutesAgo * 60),
        isMine: false
    )
}

/// `message_history` 응답 JSON 한 줄.
private func mpRowJSON(id: String, peer: String, body: String, minutesAgo: Double) -> String {
    let epoch = Int(mpNow.addingTimeInterval(-minutesAgo * 60).timeIntervalSince1970)
    return """
    {"id":"\(id)","from_user":"\(peer)","to_user":"\(mpUserID)","body":"\(body)","created_at":null,
     "is_mine":false,"peer_user_id":"\(peer)","peer_display_name":"상대\(peer)",
     "peer_avatar_url":null,"created_epoch":\(epoch)}
    """
}

// MARK: - 스위트

@MainActor
@Suite struct V0251MessagePeerTests {

    /// ★ **이 버그의 재현이자 이 스위트의 이유.** 한 번도 대화한 적 없는 사람의 말풍선 버튼을 누른다.
    /// 서버 이력에는 그 사람 행이 한 줄도 없다 — 그래도 **그 사람이 선택으로 남아 있어야 한다.**
    /// 지우면 사용자는 자기가 방금 누른 사람 대신 "대화 상대를 고르지 않았어요"를 본다.
    @Test func openingAConversationWithSomeoneNewKeepsThemSelectedAfterTheRoundTrip() async {
        let host = "mp-first-ever"
        let store = mpStore(host: host)
        // 이력에는 **다른 사람**과의 대화만 있다(빈 배열이면 '서버가 아무것도 모른다'와 구별되지 않는다).
        MPStub.set(
            .init(body: "[\(mpRowJSON(id: "a", peer: "u-other", body: "안녕", minutesAgo: 30))]"),
            host: host,
            path: mpHistoryPath
        )
        store.isPokePanelVisible = true

        store.openMessagePanel(peer: "u-new")
        #expect(store.selectedMessagePeerID == "u-new", "진입 인자를 선택으로 세우지도 못했다")

        await mpWait { store.messageHistoryLoaded }

        #expect(store.isMessagePanelVisible)
        #expect(
            store.selectedMessagePeerID == "u-new",
            "이력에 없는 사람이라고 선택을 놓았다 — 처음 말 거는 모든 사람에게서 재현되는 그 버그다"
        )
        // 이력에 없으니 대화는 비어 있다. 그게 '상대가 없다'가 아니라 '아직 주고받은 말이 없다'다.
        #expect(store.selectedMessageThread == nil)
        // 뷰가 그 상태에 낼 문장까지 확인한다(뷰 파일은 고치지 않고 판정 함수만 부른다).
        let state = MessagePanelEmptyMessage.state(
            hasPeer: store.selectedMessagePeerID != nil,
            loaded: store.messageHistoryLoaded,
            failed: store.messageHistoryFailed
        )
        #expect(state.title == "아직 주고받은 메시지가 없어요", "고른 상대가 있는데 '고르지 않았어요'가 떴다")
        #expect(state.hint == "아래에 먼저 한마디 남겨 보세요")
        #expect(!state.showsRetry)
    }

    /// 보고 있던 대화가 12시간을 넘겨 이력에서 사라진 응답. **화면을 통째로 바꾸지 않는다** —
    /// 그 자리에서 비는 것이 사용자가 겪기에 낫다(원래 저 줄의 의도였지만 처리가 옳지 않았다).
    @Test func anExpiredConversationEmptiesInPlaceInsteadOfSwappingTheScreen() async {
        let host = "mp-expired"
        let store = mpStore(host: host)
        MPStub.set(.init(body: "[]"), host: host, path: mpHistoryPath)
        store.messageHistory = [mpEntry(id: "a", peer: "u1", body: "어제 한 말", minutesAgo: 700)]
        store.selectMessagePeer("u1")

        store.loadMessageHistory()
        await mpWait { store.messageHistoryLoaded }

        #expect(store.messageHistory.isEmpty, "서버가 준 빈 이력이 반영되지 않았다")
        #expect(store.selectedMessagePeerID == "u1", "대화가 만료됐다고 상대까지 놓았다")
        let state = MessagePanelEmptyMessage.state(hasPeer: true, loaded: true, failed: false)
        #expect(state.title == "아직 주고받은 메시지가 없어요")
    }

    /// 로드 **실패**. 실패는 "상대가 없다"는 뜻이 아니다 — [다시 시도]를 눌러야 할 사람이
    /// 그 사이 콕찌르기 목록으로 튕겨 나가면 무엇을 다시 시도해야 하는지 알 수 없다.
    @Test func aFailedHistoryLoadKeepsTheChosenPeer() async {
        let host = "mp-failed"
        let store = mpStore(host: host)
        MPStub.set(.init(status: 500, body: #"{"message":"boom"}"#), host: host, path: mpHistoryPath)
        store.selectMessagePeer("u1")

        store.loadMessageHistory()
        await mpWait { store.messageHistoryFailed }

        #expect(store.messageHistoryFailed)
        #expect(store.selectedMessagePeerID == "u1", "실패했다고 상대를 놓았다")
        let state = MessagePanelEmptyMessage.state(hasPeer: true, loaded: false, failed: true)
        #expect(state.title == "대화를 불러오지 못했어요")
        #expect(state.showsRetry, "다시 시도할 길이 사라졌다")
    }

    /// 로그아웃 뒤 **늦게 도착한 앞 계정 응답**은 아무것도 안 바꾼다(기존 세대 가드 회귀 방지).
    /// 이 가드가 없으면 새 계정 화면에 앞 사람의 대화가 그려진다 — 이 앱에서 가장 사적인 사고다.
    @Test func aLateResponseFromThePreviousAccountChangesNothing() async {
        let host = "mp-generation"
        let store = mpStore(host: host)
        MPStub.set(
            .init(body: "[\(mpRowJSON(id: "old", peer: "u-old", body: "앞 계정의 말", minutesAgo: 5))]", delay: 0.25),
            host: host,
            path: mpHistoryPath
        )
        store.selectMessagePeer("u1")

        store.loadMessageHistory()
        // 요청이 **나간 것을 보고** 세대를 올린다(시간을 재서 맞히지 않는다).
        await mpWait { MPStub.count(host: host, path: mpHistoryPath) >= 1 }
        store.sessionGeneration += 1

        // 지연 창이 닫히고도 남을 만큼 기다린다. 여기서만 '아무 일도 안 일어남'을 기다리므로
        // 조건이 아니라 완료 여부를 본다(응답이 새면 messageHistory 가 채워진다).
        await mpWait { !store.messageHistory.isEmpty }

        #expect(store.messageHistory.isEmpty, "앞 계정 응답이 새 세대 화면에 그려졌다")
        #expect(!store.messageHistoryLoaded, "앞 계정 응답이 로드 완료로 기록됐다")
        #expect(store.selectedMessagePeerID == "u1")
    }

    /// 전송 성공은 **초안만** 비운다. 성공 뒤 이력 재조회가 따라붙는데(방금 보낸 말을 그 자리에 그리려고),
    /// 그 응답이 선택을 흔들면 사용자는 보낸 직후 대화에서 튕겨 나간다.
    @Test func sendingSuccessfullyClearsOnlyTheDraft() async {
        let host = "mp-send-keeps-peer"
        let store = mpStore(host: host)
        MPStub.set(.init(body: #"{"status":"ok","body":"안녕","ring":"sent"}"#), host: host, path: mpSendPath)
        // 서버가 방금 보낸 말을 아직 안 돌려주는 구간(복제 지연·정규화)을 일부러 재현한다 — 그때도 선택은 산다.
        MPStub.set(.init(body: "[]"), host: host, path: mpHistoryPath)
        store.selectMessagePeer("u1")
        store.messageDraft = "안녕"

        #expect(store.canSendMessageNow)
        store.sendDraftMessage()
        await mpWait { store.messageNotice != nil }
        await mpWait { store.messageHistoryLoaded }

        #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
        #expect(store.messageDraft == "", "성공했는데 초안이 남으면 다음 Enter 에 같은 말이 또 나간다")
        #expect(store.selectedMessagePeerID == "u1", "보내자마자 대화에서 튕겨 나갔다")
    }

    /// 수신 폴링이 물어온 갱신도 선택을 흔들지 않는다(`refreshMessageHistoryOnArrival` → 같은 로드 경로).
    /// 화면을 열어 둔 채 새 말이 오는 것이 이 기능의 자랑인데, 그때마다 상대가 바뀌면 자랑이 아니라 사고다.
    @Test func anArrivingMessageRefreshNeverSwapsThePeer() async {
        let host = "mp-arrival"
        let store = mpStore(host: host)
        // 갱신 응답에는 **다른 사람**의 대화만 들어 있다. 옛 코드 ①(응답에 그 사람 행이 없으면 선택을 지우던 줄)이
        // 살아 있으면 여기서 nil 로 떨어진다. ⚠️ 옛 코드 ②(선택이 nil 일 때 첫 대화를 고르던 가지)는 이 테스트로
        // **발화하지 않는다** — 선택이 이미 "u1" 이라 ② 의 조건이 거짓이다. ② 는 소스 계약 테스트
        // `nothingButSignOutDropsTheSelectedPeer` 가 응답 경로의 `selectMessagePeer(` 호출로 잡는다.
        MPStub.set(
            .init(body: "[\(mpRowJSON(id: "b", peer: "u-other", body: "다른 대화", minutesAgo: 1))]"),
            host: host,
            path: mpHistoryPath
        )
        store.isMenuPresented = true
        store.isMessagePanelVisible = true
        store.selectMessagePeer("u1")

        store.refreshMessageHistoryOnArrival()
        await mpWait { store.messageHistoryLoaded }

        #expect(MPStub.count(host: host, path: mpHistoryPath) == 1)
        #expect(store.selectedMessagePeerID == "u1", "폴링 갱신이 상대를 남의 대화로 바꿔치기했다")
    }

    /// ★ **상대 없이 대화 화면에 들어오는 길이 타입 수준에서 없다**(2026-09-11 사용자 재확인).
    ///
    /// 이 자리에 있던 옛 테스트(`nobodyIsAutoSelectedWhenTheUserChoseNoOne`)는 `openMessagePanel(peer: nil)` 을
    /// 불러 "아무도 안 골랐으면 '고르지 않았어요' 화면이 뜬다"를 **초록으로 고정**하고 있었다 — 사용자가 없애라고
    /// 한 바로 그 화면의 도달 가능성을 지킨 셈이다. 지금은 그 호출이 컴파일되지 않으므로, 여기서는 **그 사실이
    /// 되돌아가지 않는지**를 소스로 잰다.
    ///
    /// 왜 컴파일러에 맡기지 않나: `String` 은 `String?` 로 암묵 승격된다. 시그니처를 `String?` 로 넓혀도 지금의
    /// 호출부(콕찌르기 행 · 말풍선 배선 · 테스트)는 **전부 그대로 컴파일된다** — nil 이 들어올 문이 아무 신호 없이
    /// 다시 열린다. 그래서 시그니처 자체를 문자열로 본다.
    @Test func thereIsNoWayIntoTheConversationWithoutAPeer() throws {
        let messages = try mpStrippedSource("WorkTimerStoreMessages.swift")
        #expect(
            messages.contains("func openMessagePanel(peer: String, from origin: MessagePanelOrigin"),
            "진입점의 상대가 옵셔널로 넓혀졌다 — nil 로 들어와 '대화 상대를 고르지 않았어요'가 다시 뜬다"
        )
        // 빈 id 는 **아무 상태도 세우기 전에** 돌려보낸다. 가드가 깃발 아래로 내려가면 그게 곧 상대 없는 화면이다.
        let open = try #require(mpFunctionBody(messages, signature: "func openMessagePanel(peer:"))
        let emptyGuard = try #require(open.range(of: "guard !peer.isEmpty else { return }"), "빈 id 를 거르는 가드가 없다")
        let firstWrite = try #require(open.range(of: "messagePanelOrigin = origin"), "진입 맥락을 세우는 줄을 못 찾았다")
        #expect(emptyGuard.upperBound <= firstWrite.lowerBound, "빈 id 가드가 상태를 세운 뒤에 있다 — 상대 없는 화면이 한 프레임 선다")

        // 두 호출부가 들고 오는 것도 옵셔널이 아니다(파일 전체 부정 단언은 오탐의 온상이라 선언 자체를 본다).
        let menu = try mpStrippedSource("CheckMenuView.swift")
        #expect(menu.contains("var onOpenMessages: (String) -> Void"), "콕찌르기 목록의 대화 문이 옵셔널 인자로 넓혀졌다")
        #expect(menu.contains("var onOpen: ((String) -> Void)?"), "'최근 받은 메시지' 줄의 대화 문이 옵셔널 인자로 넓혀졌다")

        // 캐릭터 말풍선: 보낸이를 모르면 대화 패널이 아니라 콕찌르기 목록이다(판정·갈음은 아래 런타임 테스트가 잰다).
        let app = try mpStrippedSource("CheckApp.swift")
        #expect(app.contains("if let peer = store.arrivalBubbleSenderID"), "말풍선 배선이 보낸이 판정을 거치지 않는다")
        #expect(
            app.contains("store.openPokeListToPickAPeer()"),
            "보낸이를 모르는 말풍선이 갈 곳이 없다 — 옛 배선은 nil 로 '대화 상대를 고르지 않았어요'를 열었다"
        )
    }

    /// 남은 구멍인 **빈 문자열**은 조용히 아무것도 안 한다 — 보던 화면도, 진입 맥락도, 로딩 깃발도 그대로다.
    /// assertionFailure 로 막지 않는 이유: 디버그에선 멈추고 릴리스에선 지나가 두 빌드가 다르게 동작한다.
    @Test func anEmptyPeerIDOpensNothingAtAll() {
        let store = mpStore(host: "mp-empty-peer")
        store.isPokePanelVisible = true

        store.openMessagePanel(peer: "", from: .overlay)

        #expect(!store.isMessagePanelVisible, "빈 id 로 대화 화면이 열렸다 — 그게 '대화 상대를 고르지 않았어요' 화면이다")
        #expect(store.selectedMessagePeerID == nil)
        #expect(store.isPokePanelVisible, "열지도 않을 화면 때문에 보던 목록을 내렸다")
        #expect(store.messagePanelOrigin == .poke, "열지 않은 화면의 진입 맥락이 남았다 — 다음 대화의 [뒤로]가 엉뚱한 곳으로 간다")
        // 세션이 있고 미로드면 열기는 이 깃발을 **동기로** 세운다 — 그래서 벽시계 없이 "로드를 안 띄웠다"를 잰다.
        #expect(!store.messageHistoryLoading, "열지도 않은 화면의 이력을 불러오기 시작했다")
    }

    /// 캐릭터 도착 말풍선의 두 갈래(2026-09-11 지적). 보낸이를 알면 **그 사람**과의 대화, 모르면 대화 패널이
    /// 아니라 **콕찌르기 목록**이다 — 옛 배선은 nil 을 그대로 넘겨 '대화 상대를 고르지 않았어요'를 열었다.
    /// (배선 클로저는 AppDelegate 안이라 헤드리스로 못 부른다. 그래서 판정과 갈음을 스토어로 빼 여기서 잰다.)
    @Test func theArrivalBubbleOpensItsSenderOrElseThePokeList() {
        let store = mpStore(host: "mp-arrival-bubble")

        // ① 이미 뜬 한 건이 먼저다(표시 직후 큐에서 옮겨진 자리).
        store.lastShownMessage = ReceivedMessage(id: "m1", fromName: "상대1", body: "합성1", createdAt: mpNow, fromUserID: "u-shown")
        store.receivedMessages = [ReceivedMessage(id: "m2", fromName: "상대2", body: "합성2", createdAt: mpNow, fromUserID: "u-queued")]
        #expect(store.arrivalBubbleSenderID == "u-shown")
        // ② 뜬 한 건이 없으면 큐의 맨 앞.
        store.lastShownMessage = nil
        #expect(store.arrivalBubbleSenderID == "u-queued")
        // ③ 보낸이 id 를 모르는 옛 행 · 빈 id · 아무것도 없음 → nil(대화 패널로 보내지 않는다).
        store.receivedMessages = [ReceivedMessage(id: "m3", fromName: "상대3", body: "합성3", createdAt: mpNow)]
        #expect(store.arrivalBubbleSenderID == nil, "보낸이를 모르는데 상대가 있다고 답했다")
        store.receivedMessages = [ReceivedMessage(id: "m4", fromName: "상대4", body: "합성4", createdAt: mpNow, fromUserID: "")]
        #expect(store.arrivalBubbleSenderID == nil, "빈 id 를 상대로 넘기면 말풍선이 눌러도 아무 일 없는 버튼이 된다")
        store.receivedMessages = []
        #expect(store.arrivalBubbleSenderID == nil)

        // 갈음: 홈에서 누르면 콕찌르기 목록이 열리고, 대화 패널은 열리지 않는다.
        store.lastShownMessage = ReceivedMessage(id: "m5", fromName: "상대5", body: "합성5", createdAt: mpNow)
        store.openPokeListToPickAPeer()
        #expect(store.isPokePanelVisible)
        #expect(!store.isMessagePanelVisible, "보낸이를 모르는데 대화 패널이 열렸다")
        #expect(store.selectedMessagePeerID == nil)
        // **토글이 아니다**: 목록이 떠 있을 때 또 눌러도 닫히지 않고, 방금 뜬 메시지도 소비하지 않는다.
        store.openPokeListToPickAPeer()
        #expect(store.isPokePanelVisible, "두 번째 말풍선 탭이 목록을 닫았다 — 토글로 구현됐다")
        #expect(store.lastShownMessage?.id == "m5", "목록을 닫는 길을 타서 방금 뜬 메시지를 소비했다 — 서버는 이미 원자 소비했다")
    }

    /// ★ **사용자가 본 그림을 그대로 재현하고, 고쳐진 그림을 남긴다.**
    ///
    /// 위 단언들은 전부 `selectedMessagePeerID` 라는 **값**을 본다. 사용자가 스크린샷으로 지적한 것은
    /// 값이 아니라 **그림**이었고, V0249 의 빈 상태 스냅샷이 이 결함을 8일 동안 못 잡은 이유가 바로
    /// 그 테스트가 **왕복이 끝나기 전**의 화면을 찍었기 때문이다(openMessagePanel 직후 동기 렌더).
    /// 그래서 여기서는 **로드가 끝난 뒤에** 찍는다 — 그 자리가 결함이 살던 자리다.
    ///
    /// PNG 두 장을 남긴다(`CHECK_SNAPSHOT_DIR/panels/`): 사람이 열어 보고 문장을 읽으라고.
    @Test func theScreenAfterTheRoundTripSaysThereAreNoMessagesYetNotThatNobodyWasChosen() async throws {
        // ① 고친 뒤의 화면: 한 번도 대화한 적 없는 사람을 눌렀고, 이력 왕복이 **끝났다**.
        let host = "mp-render-after"
        let store = mpMenuStore(mpStore(host: host))
        MPStub.set(.init(body: "[]"), host: host, path: mpHistoryPath)
        store.pokeDirectory = [PokeDirectoryEntry(userID: "u-new", name: "영식", avatarURL: nil, isWorking: true)]
        store.pokeDirectoryLoaded = true

        store.openMessagePanel(peer: "u-new")
        await mpWait { store.messageHistoryLoaded }
        #expect(store.selectedMessagePeerID == "u-new")
        // 이력이 비어도 이름은 콕찌르기 목록에서 온다 — 머리에 사람 이름이 서 있어야 '그 사람과의 대화'다.
        #expect(store.selectedMessagePeerName == "영식")

        let fixed = try mpBitmap(store)
        MessagePanelSnapshots.save(fixed, name: "v0251-msg-first-ever-after-load.png")

        // ② 대조군: 옛 버그가 왕복 끝에 만들던 화면. **진입점으로는 더 이상 만들 수 없다** — 상대가 `String` 이라
        //    nil 로 들어올 수 없고, 응답도 선택을 지우지 않는다. 그래서 옛 버그가 남기던 상태(대화 패널은 떠 있고
        //    선택만 비었다)를 **깃발을 직접 세워** 흉내 낸다. 이 그림은 "그 화면이 아직 도달 가능하다"는 증거가
        //    아니라 **고친 그림이 그것과 다르다**는 대조용이다(뷰의 방어 가지는 다른 담당 파일에 관례대로 남아 있다).
        let oldBug = mpMenuStore(mpStore(host: "mp-render-old-bug"))
        oldBug.messageHistoryLoaded = true
        oldBug.isMessagePanelVisible = true
        #expect(oldBug.selectedMessagePeerID == nil)

        let bugPicture = try mpBitmap(oldBug)
        MessagePanelSnapshots.save(bugPicture, name: "v0251-msg-old-bug-forced-state.png")

        #expect(
            mpDiffers(fixed, bugPicture),
            "고친 화면이 옛 버그 화면('대화 상대를 고르지 않았어요')과 같은 그림이다 — 사용자가 본 그 버그다"
        )
        // 팝오버 높이 상한(푸터가 잘리는 선)도 이 화면에서 지켜져야 한다.
        #expect(Double(fixed.pixelsHigh) / 2.0 <= 700)
    }

    /// 선택을 **사용자 조작 없이** 지우는 자리는 로그아웃 하나뿐이다 — 소스로 못 박는다.
    /// (런타임으로는 "다른 곳엔 없다"를 증명할 수 없다. 없는 코드는 아무 신호도 내지 않는다.)
    /// ⚠️ 주석을 먼저 걷어낸다. 안 그러면 "왜 지웠는지"를 적어 둔 설명 자체가 이 단언을 빨갛게 만들고,
    ///    다음 사람은 테스트를 통과시키려 그 설명을 지운다(이 저장소가 겪은 함정).
    @Test func nothingButSignOutDropsTheSelectedPeer() throws {
        // 단언에 소스 전체를 넣지 않는다 — 실패 로그가 파일 하나를 통째로 토해 내면 아무도 안 읽는다.
        let messages = try mpStrippedSource("WorkTimerStoreMessages.swift")
        // 대입은 `selectMessagePeer` 안의 한 줄뿐이다(진입점 인자와 목록 선택이 전부 그 문을 지난다).
        let assignments = messages.components(separatedBy: "selectedMessagePeerID = ").count - 1
        #expect(assignments == 1, "메시지 파일에서 선택을 대입하는 자리가 \(assignments)곳이다 — 문은 하나여야 한다")
        let clearsInResponsePath = messages.contains("selectedMessagePeerID = nil")
        #expect(!clearsInResponsePath, "응답 경로가 선택을 다시 지우고 있다")

        // ⚠️ 대입 개수만 세면 **②(자동 선택)의 재유입을 못 잡는다** — 그 가지는 대입을 직접 쓰지 않고
        //    문(`selectMessagePeer`)을 **불렀으므로**, 되살려도 대입 자리는 여전히 그 함수 안의 1곳이다
        //    (2026-09-11 검토 실측: ② 만 되살린 뮤테이션에서 위 두 단언은 초록이었다). 그래서 문을 부르는 자리도 센다.
        //    상대를 정하는 호출은 **앱 전체에서** 진입점 `openMessagePanel(peer:)` 안의 한 줄뿐이어야 한다.
        var callSites: [String] = []
        for (name, code) in try mpStrippedSources(containing: "selectMessagePeer(") {
            let calls = code.components(separatedBy: "selectMessagePeer(").count - 1
                - (code.components(separatedBy: "func selectMessagePeer(").count - 1)
            if calls > 0 { callSites.append("\(name)×\(calls)") }
        }
        #expect(
            callSites == ["WorkTimerStoreMessages.swift×1"],
            "상대를 정하는 호출이 진입점 밖에도 있다: \(callSites) — 응답·폴링·화면이 상대를 고르면 누른 사람과 뜬 사람이 갈린다"
        )
        let open = try #require(mpFunctionBody(messages, signature: "func openMessagePanel(peer:"))
        #expect(open.contains("selectMessagePeer(peer)"), "진입점이 상대를 세우지 않는다")
        // 응답 경로 본문을 직접 본다 — 개수가 우연히 맞아도(진입점 호출이 빠지고 응답 쪽에 하나 생기면) 여기서 걸린다.
        let responsePath = try #require(mpFunctionBody(messages, signature: "func performLoadMessageHistory()"))
        #expect(!responsePath.contains("selectMessagePeer("), "이력 응답이 상대를 고르고 있다 — 누른 사람과 화면의 사람이 갈린다")
        #expect(!responsePath.contains("selectedMessagePeerID = "), "이력 응답이 선택에 직접 대입한다")

        // 로그아웃은 그 하나를 **반드시** 갖고 있어야 한다(사적인 표면이라 남기면 다음 사람이 읽는다).
        let signOutClears = try mpStrippedSource("WorkTimerStore.swift").contains("selectedMessagePeerID = nil")
        #expect(signOutClears, "로그아웃이 대화 상대를 안 비운다")
    }
}

// MARK: - 렌더 보조
//
// V0249 의 같은 헬퍼들은 그 파일에 `private` 이라 여기서 못 쓴다(그 파일은 이 작업의 소유가 아니라
// 접근 수준을 열 수 없다). 필요한 최소한만 다시 세운다 — 배경 대조 대신 **두 화면끼리** 비교하므로
// 그라디언트 배경을 다루는 기준 그림(mwBlankBitmap)은 필요 없다.

private enum MPRenderError: Error { case failed }

/// 팝오버가 헤더 카드·레일·푸터까지 그리도록 팀이 확정된 로그인 상태로 만든다.
@MainActor
private func mpMenuStore(_ store: WorkTimerStore) -> WorkTimerStore {
    store.isMenuPresented = true
    store.displayNow = mpNow
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    return store
}

/// ★ `previewClipsOverflowList` · `previewPlainTextEditors` 가 없으면 `ImageRenderer` 는 ScrollView 안쪽과
///   `TextEditor` 를 못 그려, 대화 자리가 비고 입력칸이 **노란 상자**인 그림이 나온다 —
///   즉 사람이 확인할 것이 하나도 없는 PNG 가 된다. **앱은 언제나 진짜 위젯을 쓴다.**
@MainActor
private func mpBitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    let view = CheckMenuView(store: store, previewClipsOverflowList: true, previewPlainTextEditors: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MPRenderError.failed }
    return bitmap
}

/// 두 그림이 눈에 띄게 다른가. 크기가 다르면 그것만으로 다르다(빈 상태 문구의 줄 수가 높이를 바꾼다).
private func mpDiffers(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, tolerance: Double = 0.06) -> Bool {
    if lhs.pixelsWide != rhs.pixelsWide || lhs.pixelsHigh != rhs.pixelsHigh { return true }
    for y in stride(from: 0, to: lhs.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: lhs.pixelsWide, by: 2) {
            guard let a = lhs.colorAt(x: x, y: y), let b = rhs.colorAt(x: x, y: y) else { continue }
            let delta = abs(a.redComponent - b.redComponent)
                + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
            if delta > tolerance { return true }
        }
    }
    return false
}

// MARK: - 소스 계약 보조

private func mpSourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)                    // Tests/checkTests/V0251MessagePeerTests.swift
        .deletingLastPathComponent()                    // Tests/checkTests
        .deletingLastPathComponent()                    // Tests
        .deletingLastPathComponent()                    // 저장소 루트
        .appendingPathComponent("Sources/check", isDirectory: true)
}

private func mpStrippedSource(_ name: String) throws -> String {
    mpStripComments(try String(contentsOf: mpSourcesDirectory().appendingPathComponent(name), encoding: .utf8))
}

/// 앱 소스 중 `needle` 을 **코드로**(주석이 아니라) 담은 파일들의 주석 제거본. 원문에서 먼저 거른 뒤에만
/// 주석을 걷는다 — 파일 수십 개를 한 글자씩 도는 비용을 해당 파일에만 치르려고.
/// 경로를 잘못 짚으면 빈 배열이 나오고, 그러면 호출부의 "정확히 이 목록" 단언이 **빨갛게** 떨어진다(조용히 초록이 되지 않는다).
private func mpStrippedSources(containing needle: String) throws -> [(name: String, code: String)] {
    let root = mpSourcesDirectory()
    guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
    var found: [(name: String, code: String)] = []
    for case let relative as String in walker where relative.hasSuffix(".swift") {
        let raw = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        guard raw.contains(needle) else { continue }
        let code = mpStripComments(raw)
        if code.contains(needle) { found.append((name: relative, code: code)) }
    }
    return found.sorted { $0.name < $1.name }
}

/// 주석을 걷어낸 소스에서 `signature` 로 시작하는 함수의 **본문**(바깥 중괄호 안쪽)을 꺼낸다.
/// 파일 전체 `contains` 는 이름이 같은 다른 경로가 섞여 오탐이 나므로, 단언의 범위를 함수 하나로 좁히려고 쓴다.
/// 문자열 리터럴 안의 중괄호는 세지 않는다.
private func mpFunctionBody(_ source: String, signature: String) -> String? {
    guard let start = source.range(of: signature),
          let open = source[start.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var previous: Character?
    var index = open
    while index < source.endIndex {
        let character = source[index]
        if inString {
            if character == "\"", previous != "\\" { inString = false }
        } else if character == "\"" {
            inString = true
        } else if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[source.index(after: open)..<index]) }
        }
        previous = character
        index = source.index(after: index)
    }
    return nil
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다. 문자열 리터럴 안의 `//` 는 남긴다(URL 이 잘리면
/// 남은 코드가 이상해져 단언이 엉뚱한 이유로 흔들린다).
private func mpStripComments(_ source: String) -> String {
    var output = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character?
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if character == "\n" { inLineComment = false; output.append(character) }
            index += 1
            continue
        }
        if inBlockComment {
            if character == "*", next == "/" { inBlockComment = false; index += 2; continue }
            if character == "\n" { output.append(character) }
            index += 1
            continue
        }
        if inString {
            output.append(character)
            if character == "\"", previous != "\\" { inString = false }
            previous = character
            index += 1
            continue
        }
        if character == "\"" { inString = true; output.append(character); previous = character; index += 1; continue }
        if character == "/", next == "/" { inLineComment = true; index += 2; continue }
        if character == "/", next == "*" { inBlockComment = true; index += 2; continue }
        output.append(character)
        previous = character
        index += 1
    }
    return output
}
