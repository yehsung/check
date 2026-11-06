import Foundation

// 1:1 길건너 판 표시 프레임 전용 **둘째 소켓**(SPEC v1.3 §8.4 · B1). **`TetrisFrameChannel.swift` 를 베꼈다**(설계 결정) —
// 그 파일은 `TetrisFrame` 타입 · `tetris:` 접두사에 묶여 있어 일반화가 크고, 맥 0.3.74 로 나간 테트리스 코드를 건드리지 않으려고.
// 바꾼 것은 타입 이름 · 프레임 타입(`CrossyDuelFrame`) · 토픽 접두사(`crossy_duel:` — `CrossyDuelFramesRow.topicPrefix`)뿐이다.
//
// ── 이 파일의 세 층 ──
//   · `CrossyDuelFrameChannel`       — 스토어가 보는 유일한 추상화(시험은 스텁을 끼운다). 결과는 `onEvent` 로만 온다.
//   · `CrossyDuelFrameWire`          — 들어온 텍스트 한 건 → 사건(순수). 라이브 소켓과 시험 스텁이 같은 해석을 쓴다.
//   · `LiveCrossyDuelFrameChannel`   — 진짜 소켓. **테스트 프로세스에서는 nil.**
//
// ── 지키는 것 ──
//  ① 조인은 언제나 `private:true` · `broadcast.self:false` · `broadcast.ack:false`(`RealtimeFrame.join` 그대로).
//  ② **`poke:` 토픽에 싣지 않는다** — `crossy_duel:` 로 시작하지 않는 토픽은 열지 않는다(B1).
//  ③ REST 전송은 없다.
//  ④ 언제 열고 닫고 다시 여는지는 이 파일이 정하지 않는다 — 순수 장부 `CrossyDuelFrameLink` 가 정하고 스토어가 시킨다.

/// 프레임 소켓에서 올라오는 사건.
package enum CrossyDuelFrameChannelEvent: Equatable, Sendable {
    /// 소켓·채널 사건(열림 · join · 거절 · 닫힘 · 하트비트). 링크의 `apply(_:at:jitter:)` 에 그대로 넣는다.
    case transport(RealtimeTransportEvent)
    /// 모양을 통과한 상대 프레임 한 장(누가 보냈는지 · 순서는 링크의 `receive` 가 본다).
    case frame(CrossyDuelFrame)
    /// 우리 토픽의 `frame` 이었지만 모양이 깨졌다(로그용 — 아무것도 바꾸지 않는다).
    case rejected(CrossyDuelFrameRejection)
}

/// 판 표시 프레임 소켓의 **유일한** 추상화. 모든 메서드가 "부수효과를 명령한다"이고 반환이 없다(`RealtimeTransport` 와 같은 규칙).
@MainActor
package protocol CrossyDuelFrameChannel: AnyObject {
    var onEvent: ((CrossyDuelFrameChannelEvent) -> Void)? { get set }
    /// 이 토픽으로 private join 을 연다(이미 열려 있으면 닫고 새로 연다 — 세대가 바뀐다).
    /// - Parameter topic: 접두사 없는 토픽(`state.frames.topic` 글자 그대로). `crossy_duel:` 로 시작하지 않으면 열지 않고 `.closed` 를 낸다.
    func connect(url: URL, apiKey: String, accessToken: String, topic: String)
    /// join 된 채널에 broadcast 한 건. 열려 있지 않으면 버린다(`ack:false` — 성공 여부는 보내는 쪽이 모른다).
    func send(event: String, payload: [String: Any])
    /// 열린 채널에 새 토큰을 밀어 넣는다(판 중 세션 토큰이 바뀌었다 — 안 보내면 만료 때 채널이 닫힌다, §10).
    func pushAccessToken(_ token: String)
    func disconnect()
}

// MARK: - 해석 (순수)

/// 들어온 텍스트 한 건 → 사건. 라이브 소켓과 시험 스텁이 함께 쓴다 — 보내는 봉투(`RealtimeFrame.broadcast`)와 받는 해석이 한 짝인지를
/// 시험이 이 함수로 잰다.
package enum CrossyDuelFrameWire {
    /// - Parameters:
    ///   - topic: 접두사 없는 우리 토픽. 다른 토픽의 프레임은 nil.
    ///   - joinRef: 우리가 보낸 phx_join 의 ref(조인 응답을 다른 phx_reply 와 가른다).
    /// - Returns: 우리 토픽의 `frame` → `.frame`/`.rejected`, 그 밖의 broadcast → nil(이 소켓엔 다른 이름이 오지 않는다),
    ///   조인 응답 · 오류 · 닫힘 · 하트비트 응답 → `.transport`.
    package static func event(text: String, topic: String, joinRef: String?) -> CrossyDuelFrameChannelEvent? {
        if let broadcast = RealtimeFrame.decodeBroadcastPayload(text: text, channel: topic) {
            guard broadcast.event == CrossyDuelFrame.event else { return nil }
            switch CrossyDuelFrame.decode(payload: broadcast.payload) {
            case .success(let frame): return .frame(frame)
            case .failure(let rejection): return .rejected(rejection)
            }
        }
        guard let event = RealtimeFrame.decode(text: text, channel: topic, joinRef: joinRef) else { return nil }
        // 토픽 없는 broadcast(누구 판인지 모른다)는 `decodeBroadcastPayload` 가 이미 걸렀다 — 이름만 남은 사건은 버린다.
        if case .broadcast = event { return nil }
        return .transport(event)
    }

    /// 열어도 되는 토픽인가 — `crossy_duel:` 로 시작하고 그 뒤가 비지 않았다(`CrossyDuelFramesRow.activeTopic` 과 같은 판정).
    package static func isFrameTopic(_ topic: String) -> Bool {
        topic.hasPrefix(CrossyDuelFramesRow.topicPrefix) && topic.count > CrossyDuelFramesRow.topicPrefix.count
    }
}

// MARK: - 라이브 소켓

/// 진짜 소켓. **테스트 프로세스에서는 태어나지 못한다**(판정은 `LiveRealtimeTransport` 와 같은 `CheckPanelVisibility.isRunningTests` 하나 —
/// 두 번째 판정을 새로 심지 않는다).
///
/// `LiveRealtimeTransport` 와 다른 자리 둘: ① 하트비트를 **스스로** 25초마다 보낸다(초인종은 링의 `.tick` 이 시키지만 이 소켓을 모는
/// 링은 판 루프라 25초 시계가 없다). 다음 하트비트 때까지 답이 없으면 `.heartbeatTimedOut` 을 내고 멈춘다 — 링크가 `.lost` 로 닫고
/// 재시도 규칙을 탄다. ② 보내기(`send`)가 있다.
@MainActor
package final class LiveCrossyDuelFrameChannel: NSObject, CrossyDuelFrameChannel {
    package var onEvent: ((CrossyDuelFrameChannelEvent) -> Void)?

    private let session: URLSession
    private let heartbeatSeconds: TimeInterval
    private var task: URLSessionWebSocketTask?
    private var topic: String?
    private var joinRef: String?
    private var refCounter = 0
    /// 아직 답을 못 받은 하트비트가 있다. 다음 하트비트 때까지 남아 있으면 무응답이다.
    private var pendingHeartbeat = false
    private var heartbeatTask: Task<Void, Never>?
    /// 이 세대의 소켓만 사건을 낼 수 있다 — disconnect 뒤에도 살아 있는 receive 콜백이 다음 연결(다음 판)을 흔들지 못하게.
    private var generation = 0

    /// - Returns: 테스트 프로세스면 **nil**(fail-closed).
    package init?(session: URLSession = .shared,
                  heartbeatSeconds: TimeInterval = RealtimeLinkConstants.heartbeatIntervalSeconds,
                  environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard !CheckPanelVisibility.isRunningTests || environment["CHECK_E2E"] == "1" else { return nil }
        self.session = session
        self.heartbeatSeconds = max(1, heartbeatSeconds)
        super.init()
    }

    package func connect(url: URL, apiKey: String, accessToken: String, topic: String) {
        disconnect()
        generation &+= 1
        let currentGeneration = generation
        guard CrossyDuelFrameWire.isFrameTopic(topic),
              let socketURL = RealtimeFrame.socketURL(projectURL: url, apiKey: apiKey) else {
            emit(.transport(.closed(code: nil)), generation: currentGeneration)
            return
        }
        self.topic = topic
        refCounter = 0
        pendingHeartbeat = false
        let newTask = session.webSocketTask(with: socketURL)
        task = newTask
        newTask.resume()
        emit(.transport(.opened), generation: currentGeneration)

        let ref = nextRef()
        joinRef = ref
        send(RealtimeFrame.join(channel: topic, accessToken: accessToken, isPrivate: true, ref: ref),
             generation: currentGeneration)
        receive(generation: currentGeneration)
        startHeartbeat(generation: currentGeneration)
    }

    package func send(event: String, payload: [String: Any]) {
        guard let topic, let joinRef else { return }
        send(RealtimeFrame.broadcast(channel: topic, event: event, payload: payload, ref: nextRef(), joinRef: joinRef),
             generation: generation)
    }

    package func pushAccessToken(_ token: String) {
        guard let topic, let joinRef else { return }
        send(RealtimeFrame.accessToken(channel: topic, token: token, ref: nextRef(), joinRef: joinRef),
             generation: generation)
    }

    package func disconnect() {
        generation &+= 1
        heartbeatTask?.cancel()
        heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        topic = nil
        joinRef = nil
        pendingHeartbeat = false
    }

    // MARK: 내부

    private func nextRef() -> String {
        refCounter &+= 1
        return String(refCounter)
    }

    private func startHeartbeat(generation: Int) {
        heartbeatTask?.cancel()
        let interval = heartbeatSeconds
        heartbeatTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled, generation == self.generation, self.task != nil else { return }
                // 직전 하트비트가 답을 못 받았다 = half-open. 링크에 알리고 새로 보내지 않는다(닫기는 링크가 시킨다).
                if self.pendingHeartbeat {
                    self.emit(.transport(.heartbeatTimedOut), generation: generation)
                    return
                }
                self.pendingHeartbeat = true
                self.send(RealtimeFrame.heartbeat(ref: self.nextRef()), generation: generation)
            }
        }
    }

    private func send(_ text: String, generation: Int) {
        guard let task, generation == self.generation else { return }
        task.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.emit(.transport(.closed(code: nil)), generation: generation) }
        }
    }

    private func receive(generation: Int) {
        guard let task, generation == self.generation else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                switch result {
                case .failure:
                    self.emit(.transport(.closed(code: nil)), generation: generation)
                case .success(let message):
                    let text: String?
                    switch message {
                    case .string(let value): text = value
                    case .data(let data): text = String(data: data, encoding: .utf8)
                    @unknown default: text = nil
                    }
                    if let text, let topic = self.topic,
                       let event = CrossyDuelFrameWire.event(text: text, topic: topic, joinRef: self.joinRef) {
                        if case .transport(.heartbeatAck) = event { self.pendingHeartbeat = false }
                        self.emit(event, generation: generation)
                    }
                    self.receive(generation: generation)
                }
            }
        }
    }

    private func emit(_ event: CrossyDuelFrameChannelEvent, generation: Int) {
        guard generation == self.generation else { return }
        onEvent?(event)
    }
}
