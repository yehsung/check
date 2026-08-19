import Foundation

// 초인종의 **소켓 계층**. 이 파일 아래로는 URLSessionWebSocketTask 가 있고, 위로는 순수 상태머신만 있다.
//
// ── 채널명 규약 (RealtimeLink.swift 머리 주석과 같은 사실) ──
// `connect(channel:)` 이 받는 것은 접두사 **없는** `poke:<uid>` 다. Phoenix wire 의 topic 필드에
// `realtime:` 을 붙이는 것은 **여기 한 곳뿐**이고, RLS 가 보는 `realtime.topic()` 은 접두사를 뗀 값이라
// 서버 `public.poke_topic(uuid)` 의 반환값과 문자 그대로 같다. 두 표현을 두 곳에서 만들면
// 한쪽만 고쳐지는 날 조인은 성공하는데 아무것도 안 오는 상태가 된다(가장 조용한 결말).

/// 리얼타임 전송의 **유일한** 추상화.
///
/// 모든 메서드가 "부수효과를 명령한다"이고 **반환이 없다** — 결과는 반드시 `onEvent` 로만 돌아온다.
/// 요청/응답 쌍으로 만들면 테스트가 async 대기에 묶여 결정성을 잃는다.
@MainActor
protocol RealtimeTransport: AnyObject {
    var onEvent: ((RealtimeTransportEvent) -> Void)? { get set }
    /// - Parameters:
    ///   - channel: 접두사 없는 채널명 `poke:<uid>`.
    ///   - isPrivate: **명시 인자다.** join payload 의 `config.private` 를 빠뜨리면 조인이 그냥 성공하고
    ///     realtime.messages RLS 가 **아예 상담되지 않는다** — 그러면 `.topicDenied` 브랜치가 죽은 코드가 되고,
    ///     서버 정책이 미배포인 채로 "붙었는데 아무것도 안 옴"이 된다.
    func connect(url: URL, apiKey: String, accessToken: String, channel: String, isPrivate: Bool)
    /// 열린 토픽에 새 토큰을 밀어 넣는다(재연결하지 않는다 — RealtimeLink 의 `.tokenRefreshed` 주석 참고).
    func pushAccessToken(_ token: String)
    func sendHeartbeat()
    func disconnect()
}

// MARK: - 킬스위치

/// 리얼타임 기능 플래그. **기본값이 켜짐이다(v0.2.34).**
///
/// 확정 ②는 "e2e 배달이 증명되기 전에는 끈 채로 낸다" 였고, 그 프로브가 **통과했다**(2026-08-19 실측):
/// realtime.messages 파티션 0→5(소켓 1회 연결로 서비스가 자동 생성), RLS 정책 생성 확인,
/// 실사용자 JWT 로 private 채널 `poke:<uid>` 구독 승인, poke_ring 이 쓴 브로드캐스트 **수신 확인**,
/// 그리고 **남의 토픽 구독은 거절**("Unauthorized: ... topic: poke:<남의 uid>"). 그래서 켜고 낸다.
///
/// 끄려면(사용자·운영자 모두):
///
///     defaults write kingcheck check.realtimeEnabled -bool NO      # 그리고 앱 재실행
///
/// `object(forKey:)` 로 읽는 이유가 여기서 값을 한다 — 위 한 줄로 **끈 사람의 의사**가
/// 기본값 변경에 덮이지 않는다. 이 판정은 실행 시작에 **한 번만** 읽는다 — 실행 중에 뒤집히면
/// 소켓과 폴링이 서로를 반쯤 재우는 조합이 생기고, 그 조합이 정확히 "완전한 침묵"이다.
enum RealtimeFeature {
    static let defaultsKey = "check.realtimeEnabled"
    /// 개발·프로브용 탈출구. 설정을 건드리지 않고 한 번 켜 본다.
    static let environmentName = "CHECK_REALTIME"

    static func isEnabled(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if let raw = environment[environmentName]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            return raw == "1" || raw.lowercased() == "true" || raw.lowercased() == "yes"
        }
        // object(forKey:) 로 읽는다. bool(forKey:) 는 "키 없음"과 "false" 를 구분하지 못해
        // 기본값이 켜짐인 지금 **사용자가 끈 사실을 덮어쓴다**(그 구분이 이 줄의 존재 이유다).
        return defaults.object(forKey: defaultsKey) as? Bool ?? true
    }
}

// MARK: - Phoenix 프레임 (순수)

/// Phoenix v1 프레임의 **조립과 해석**. 순수 함수만 있고 소켓을 모른다 —
/// 이 계층이 순수해야 "조인 페이로드에 private 이 빠졌다" 같은 결함을 소켓 없이 잡을 수 있다.
enum RealtimeFrame {
    /// Phoenix wire 의 topic. 채널명 앞에 `realtime:` 을 붙이는 **유일한 지점**.
    static func wireTopic(channel: String) -> String { "realtime:\(channel)" }

    /// 소켓 URL. Supabase Realtime v1 엔드포인트.
    static func socketURL(projectURL: URL, apiKey: String) -> URL? {
        guard var components = URLComponents(url: projectURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = (components.scheme == "http") ? "ws" : "wss"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "vsn", value: "1.0.0")
        ]
        return components.url
    }

    /// phx_join. **`config.private = true` 가 이 페이로드의 존재 이유다.**
    static func join(channel: String, accessToken: String, isPrivate: Bool, ref: String) -> String {
        let payload: [String: Any] = [
            "config": [
                "broadcast": ["self": false, "ack": false],
                "presence": ["key": ""],
                "postgres_changes": [],
                "private": isPrivate
            ],
            "access_token": accessToken
        ]
        return encode(topic: wireTopic(channel: channel), event: "phx_join", payload: payload, ref: ref, joinRef: ref)
    }

    static func heartbeat(ref: String) -> String {
        encode(topic: "phoenix", event: "heartbeat", payload: [:], ref: ref, joinRef: nil)
    }

    static func accessToken(channel: String, token: String, ref: String, joinRef: String) -> String {
        encode(
            topic: wireTopic(channel: channel),
            event: "access_token",
            payload: ["access_token": token],
            ref: ref,
            joinRef: joinRef
        )
    }

    private static func encode(
        topic: String,
        event: String,
        payload: [String: Any],
        ref: String,
        joinRef: String?
    ) -> String {
        var object: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": ref]
        if let joinRef { object["join_ref"] = joinRef }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /// 들어온 텍스트 프레임 1건 → 전송자 이벤트. 우리가 모르는 프레임은 nil(무시).
    ///
    /// - Parameters:
    ///   - channel: 접두사 없는 채널명. 남의 토픽 프레임을 우리 것으로 오인하지 않게 대조한다.
    ///   - joinRef: 우리가 보낸 phx_join 의 ref. 조인 응답을 다른 phx_reply 와 가른다.
    static func decode(text: String, channel: String, joinRef: String?) -> RealtimeTransportEvent? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String
        else { return nil }
        let topic = object["topic"] as? String
        let payload = object["payload"] as? [String: Any] ?? [:]

        // 하트비트 응답은 topic "phoenix" 로 온다. **좀비 소켓 판정의 유일한 양성 증거**라 먼저 본다.
        if topic == "phoenix", event == "phx_reply" {
            return .heartbeatAck
        }

        guard topic == wireTopic(channel: channel) || topic == nil else { return nil }

        switch event {
        case "phx_reply":
            let ref = object["ref"] as? String
            guard joinRef == nil || ref == joinRef else { return nil }
            let status = payload["status"] as? String
            if status == "ok" { return .joined }
            let response = payload["response"] as? [String: Any] ?? [:]
            let reason = (response["reason"] as? String) ?? (response["error"] as? String) ?? status ?? ""
            return .joinRejected(classifyJoinError(reason: reason))
        case "broadcast":
            // Supabase 는 브로드캐스트 이름을 payload.event 에 싣는다(우리는 'ring' 하나만 쓴다).
            return .broadcast(event: (payload["event"] as? String) ?? "")
        case "phx_error", "phx_close":
            return .closed(code: nil)
        case "system":
            // 시스템 통지. status=error 면 대개 토큰 문제이고, 그 밖은 정보성이라 무시한다.
            guard (payload["status"] as? String) == "error" else { return nil }
            let message = (payload["message"] as? String) ?? ""
            return .joinRejected(classifyJoinError(reason: message))
        default:
            return nil
        }
    }

    /// 거절 사유 문자열 → 두 종류. **순서가 계약이다**: 만료를 먼저 본다.
    /// RLS 거절 문구에도 "not authorized" 같은 말이 들어가는데, 만료는 강제 갱신 1회로 나을 수 있고
    /// RLS 거절은 재시도로 절대 안 낫는다 — 뒤집히면 만료된 사용자가 "서버 설정 문제" 문구를 본다.
    static func classifyJoinError(reason: String) -> RealtimeJoinRejection {
        let lowered = reason.lowercased()
        if lowered.contains("expired") || lowered.contains("invalidjwt") || lowered.contains("invalid jwt") {
            return .expiredToken
        }
        if lowered.contains("unauthorized") || lowered.contains("permission") || lowered.contains("not authorized")
            || lowered.contains("forbidden") || lowered.contains("rls") {
            return .unauthorized
        }
        return .unknown(reason)
    }
}

// MARK: - 라이브 전송자

/// 진짜 소켓. **테스트 프로세스에서는 태어나지 못한다.**
@MainActor
final class LiveRealtimeTransport: NSObject, RealtimeTransport {
    var onEvent: ((RealtimeTransportEvent) -> Void)?

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var channel: String?
    private var joinRef: String?
    private var refCounter = 0
    /// 아직 답을 못 받은 하트비트 ref. 다음 하트비트를 보낼 때까지 남아 있으면 무응답이다.
    private var pendingHeartbeat = false
    /// 이 세대의 소켓만 이벤트를 낼 수 있다. disconnect 후에도 살아 있는 receive 콜백이
    /// **다음 연결의 상태를 흔드는 것**이 이 계층에서 가장 흔한 결함이다.
    private var generation = 0

    /// - Returns: 테스트 프로세스면 **nil**(fail-closed).
    ///
    /// ★ blocker(리얼타임 #4): 설계 원안의 `XCTestConfigurationFilePath` / `SWIFT_TESTING` 판정은
    ///   이 저장소에서 **실측으로 이미 탈락했다**(CheckOverlayWindow.swift:33-52 가 같은 머신 `swift test`
    ///   실측을 기록한다 — 둘 다 비어 있고 `NSClassFromString("XCTestCase")` 도 nil). 살아남은 판정은
    ///   dyld 이미지에서 `.xctest/` 를 찾는 `CheckPanelVisibility.isRunningTests` 하나이고,
    ///   그 주석이 "판정은 여기 한 곳뿐이다"라고 못 박았다. **새로 만들지 않고 그것을 재사용한다** —
    ///   여기에 두 번째 판정을 심으면 3겹 잠금 중 2겹이 no-op 인 상태가 되고, 조립 실수 한 번에
    ///   실소켓이 테스트 프로세스에서 열려 188초짜리 플레이키가 재발한다.
    init?(session: URLSession = .shared, environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard !CheckPanelVisibility.isRunningTests || environment["CHECK_E2E"] == "1" else { return nil }
        self.session = session
        super.init()
    }

    func connect(url: URL, apiKey: String, accessToken: String, channel: String, isPrivate: Bool) {
        disconnect()
        generation &+= 1
        let currentGeneration = generation
        guard let socketURL = RealtimeFrame.socketURL(projectURL: url, apiKey: apiKey) else {
            emit(.closed(code: nil), generation: currentGeneration)
            return
        }
        self.channel = channel
        refCounter = 0
        pendingHeartbeat = false
        let newTask = session.webSocketTask(with: socketURL)
        task = newTask
        newTask.resume()
        emit(.opened, generation: currentGeneration)

        let ref = nextRef()
        joinRef = ref
        send(RealtimeFrame.join(channel: channel, accessToken: accessToken, isPrivate: isPrivate, ref: ref),
             generation: currentGeneration)
        receive(generation: currentGeneration)
    }

    func pushAccessToken(_ token: String) {
        guard let channel, let joinRef else { return }
        send(RealtimeFrame.accessToken(channel: channel, token: token, ref: nextRef(), joinRef: joinRef),
             generation: generation)
    }

    func sendHeartbeat() {
        guard task != nil else { return }
        // 직전 하트비트가 아직 답을 못 받았다 = 소켓이 half-open 이다. 링에게 알리고 새로 보내지 않는다
        // (링의 `.tick` 판정과 이중 안전망이다 — 둘 중 하나만 살아도 좀비에서 빠져나온다).
        if pendingHeartbeat {
            emit(.heartbeatTimedOut, generation: generation)
            return
        }
        pendingHeartbeat = true
        send(RealtimeFrame.heartbeat(ref: nextRef()), generation: generation)
    }

    func disconnect() {
        generation &+= 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        channel = nil
        joinRef = nil
        pendingHeartbeat = false
    }

    // MARK: 내부

    private func nextRef() -> String {
        refCounter &+= 1
        return String(refCounter)
    }

    private func send(_ text: String, generation: Int) {
        guard let task, generation == self.generation else { return }
        task.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.emit(.closed(code: nil), generation: generation) }
        }
    }

    private func receive(generation: Int) {
        guard let task, generation == self.generation else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                switch result {
                case .failure:
                    self.emit(.closed(code: nil), generation: generation)
                case .success(let message):
                    let text: String?
                    switch message {
                    case .string(let value): text = value
                    case .data(let data): text = String(data: data, encoding: .utf8)
                    @unknown default: text = nil
                    }
                    if let text, let channel = self.channel,
                       let event = RealtimeFrame.decode(text: text, channel: channel, joinRef: self.joinRef) {
                        if case .heartbeatAck = event { self.pendingHeartbeat = false }
                        self.emit(event, generation: generation)
                    }
                    self.receive(generation: generation)
                }
            }
        }
    }

    private func emit(_ event: RealtimeTransportEvent, generation: Int) {
        guard generation == self.generation else { return }
        onEvent?(event)
    }
}
