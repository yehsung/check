import Foundation

// 1:1 길건너 스토어의 **판 표시 프레임 갈래**(SPEC v1.3 §8.4 · §3.4 — `TetrisDuelStoreFrames` 틀).
// 저장 프로퍼티는 본문(CrossyDuelStore.swift)에 있고 여기는 로직만 둔다. 판정은 순수 장부(`CrossyDuelFrameLink`)가 하고,
// 이 파일은 그 판정을 스토어의 사실(응답 · 판 루프 · 소켓 사건)에 잇는다.
//
//   응답(applyState) ─ noteServerFrames → 장부(frames · report_ms · checkpoint_ms · 실패 streak) → 소켓 열기·닫기
//                    · 끝난 판 → finishFrames(곧바로 닫기)
//   판 루프(tick)     ─ considerFrame: ① 소켓 명령 ② 토큰 밀어 넣기 ③ 프레임 보내기(phase `.playing` 이고 join 됐을 때만)
//   보고              ─ frameChangeReportsSuppressed(확인됨 = 체크포인트 · 변화 보고 0) → `CrossyDuelSession.reportDue` 인자
//   소켓 사건         ─ handleFrameChannelEvent → 장부 apply · receive(상대 점수 표시는 스냅숏이 장부에서 `max` 로 읽는다)
//   판을 내림 · 물러남 · 로그아웃(discardDuel) ─ discardFrames: 닫고 장부를 버린다
//
// ★ 프레임은 **표시 전용**이다 — 승패 · 루비 · 판정 · 재개 · `heldOpponentSeq` · `match` 를 바꾸는 줄이 이 파일에 없다(B0 불변식).
// ★ 서버가 `frames` 키를 안 주면(1차 서버 · 스위치 꺼짐 · 다른 세션 기기) 장부의 조건 ① 이 거짓이라 언제나 대체 길(DB `report_ms`)이다.

extension CrossyDuelStore {
    /// 기본 소켓 문. **리얼타임 킬스위치가 꺼진 기기는 라이브 생성기를 부르지도 않는다**(테트리스 `defaultFrameChannel` 과 같다).
    /// 테스트 프로세스의 라이브 소켓은 언제나 nil 이다.
    package static func defaultFrameChannel(
        defaults: UserDefaults,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        live: @MainActor () -> (any CrossyDuelFrameChannel)? = { LiveCrossyDuelFrameChannel() }
    ) -> (any CrossyDuelFrameChannel)? {
        RealtimeFeature.isEnabled(defaults: defaults, environment: environment) ? live() : nil
    }

    /// 이 기기가 프레임을 실제로 열 수 있는가 — 소켓이 만들어지고(킬스위치 · 테스트 프로세스 아님) 키가 있다.
    package var framesCapable: Bool {
        guard let host, host.service.anonKey != nil else { return false }
        return resolvedFrameChannel() != nil
    }

    /// 프레임 소켓을 처음 필요할 때 **한 번만** 만든다(킬스위치도 그때 한 번 읽는다 — 실행 중에 뒤집히지 않게).
    @discardableResult
    func resolvedFrameChannel() -> (any CrossyDuelFrameChannel)? {
        if !frameChannelResolved {
            frameChannelResolved = true
            let channel = makeFrameChannel(deviceLedger.defaults ?? .standard)
            channel?.onEvent = { [weak self] event in self?.handleFrameChannelEvent(event) }
            frameChannel = channel
        }
        return frameChannel
    }

    /// 지금 보고 간격(초) — 장부가 있으면 그 판정(확인됨 = 체크포인트), 없으면 판의 `report_ms`(대체 길).
    package func frameReportInterval(at now: TimeInterval) -> TimeInterval {
        if let frameLink, frameLinkMatchID == nil || frameLinkMatchID == match?.id { return frameLink.reportInterval(at: now) }
        return TimeInterval(match?.reportMs ?? CrossyDuelFrameLink.defaultReportMs) / 1000
    }

    /// 프레임이 확인돼 점수·죽음 변화 보고를 내지 않는가(B4). 장부가 없으면 false(대체 길). 바뀔 때만 로그 한 줄.
    package func frameChangeReportsSuppressed(at now: TimeInterval) -> Bool {
        guard let link = frameLink, frameLinkMatchID == nil || frameLinkMatchID == match?.id else { return false }
        let confirmed = link.changeReportsSuppressed(at: now)
        if loggedFramesConfirmed != confirmed {
            loggedFramesConfirmed = confirmed
            let c = link.conditions(at: now)
            Self.logger.notice("""
                frames confirmed=\(confirmed, privacy: .public) server=\(c.serverOn, privacy: .public) \
                joined=\(c.joined, privacy: .public) heard=\(c.heardRecently, privacy: .public) \
                hears=\(c.opponentHearsMe, privacy: .public) healthy=\(c.reportsHealthy, privacy: .public) \
                steady=\(c.steady, privacy: .public)
                """)
        }
        return confirmed
    }

    // MARK: - 응답에서

    /// 진행 중이고 **이 기기가 두는** 판의 응답마다: 서버 켬/끔 · 간격 · 실패 streak 를 장부에 넣고, 켜졌으면 열고 꺼졌으면 닫는다.
    func noteServerFrames(_ frames: CrossyDuelFramesRow?, reportMs: Int, checkpointMs: Int?, matchID: String,
                          opponentID: String, at now: TimeInterval) {
        guard framesCapable else {
            if frameLink != nil { discardFrames() }
            return
        }
        if frameLink == nil || frameLinkMatchID != matchID {
            guard let me = host?.session?.userID, !me.isEmpty, !opponentID.isEmpty else { return }
            discardFrames()
            frameLink = CrossyDuelFrameLink(me: me, opponent: opponentID, frameBase: frameBaseNow())
            frameLinkMatchID = matchID
        }
        let wasOn = frameLink?.topic != nil
        let streak = reportFailureStreak
        withFrameLink {
            $0.noteServerFrames(frames, reportMs: reportMs, checkpointMs: checkpointMs)
            $0.noteReportFailureStreak(streak)
        }
        let isOn = frameLink?.topic != nil
        if wasOn != isOn { Self.logger.notice("frames \(isOn ? "on" : "off", privacy: .public) by server") }
        driveFrameSocket(at: now)
    }

    /// `f` 시작값 = 장부를 만드는 순간의 벽시계 ms(테트리스와 같은 꼴 — 다시 연 프로세스·다시 만든 장부의 첫 장이 옛 장보다 크다).
    func frameBaseNow() -> Int {
        let ms = clock().timeIntervalSince1970 * 1000
        return ms.isFinite && ms > 0 ? Int(ms.rounded(.down)) : 0
    }

    /// 서버가 판을 닫았다(끝난 판 가지). 소켓을 **곧바로** 닫고 장부는 남긴다(끝난 뒤 닿은 프레임은 장부가 버린다).
    func finishFrames() {
        guard frameLink != nil else { return }
        let command = withFrameLink { $0.finish() }
        if command == .disconnect || frameSocketOpen {
            closeFrameSocket()
            Self.logger.notice("frames closed — match finished")
        }
    }

    /// 판이 끝났거나 로비로 간다 — 채널을 닫고 장부를 버린다.
    package func discardFrames() {
        closeFrameSocket()
        frameLink = nil
        frameLinkMatchID = nil
        frameSocketToken = nil
        loggedFramesConfirmed = nil
    }

    /// 보고 실패 streak 가 바뀐 세 자리(멎음 버림 · 실패 · 성공)에서 부른다 — 조건 ⑤.
    func noteFrameReportStreak() {
        let streak = reportFailureStreak
        withFrameLink { $0.noteReportFailureStreak(streak) }
    }

    /// 판 화면이 그릴 상대 반투명 그림자 — 프레임이 켜진 판에서 최근에 받은 위치만(11-10). 표시 전용이다(B0).
    package var opponentGhost: CrossyDuelGhost? {
        guard let frameLink, let current = match, !current.isFinished, frameLinkMatchID == current.id, phase == .playing
        else { return nil }
        return frameLink.opponentGhost(at: uptime())
    }

    // MARK: - 판 루프에서

    /// 판 루프 한 걸음: ① 소켓 열기·닫기(멈춤 10초 · 재시도) ② 바뀐 세션 토큰 밀어 넣기 ③ 프레임 보내기(B3).
    /// **보고와 따로 돈다** — 나가 있는 보고가 프레임을 막지 않는다.
    func considerFrame(at now: TimeInterval) {
        guard frameLink != nil, let current = match, !current.isFinished, frameLinkMatchID == current.id,
              let duel, duelMatchID == current.id, host?.session != nil else { return }
        driveFrameSocket(at: now)
        pushFrameTokenIfChanged()
        guard frameSocketOpen, phase == .playing, let channel = frameChannel, let link = frameLink else { return }
        let score = duel.game.score
        let deaths = duel.game.deaths
        let ghost = CrossyDuelGhost(game: duel.game)
        guard link.frameDue(at: now, live: duel.isLive,
                            changed: link.changedSinceLastFrame(score: score, deaths: deaths),
                            moved: link.movedSinceLastFrame(ghost)),
              let frame = withFrameLink({ $0.makeFrame(at: now, seq: duel.seq, score: score, deaths: deaths, ghost: ghost) })
        else { return }
        channel.send(event: CrossyDuelFrame.event, payload: frame.payload)
    }

    private func driveFrameSocket(at now: TimeInterval) {
        guard frameLink != nil else { return }
        let started = duel?.startAt
        let jitter = frameJitter
        guard let command = withFrameLink({ $0.socketCommand(at: now, matchStartedAt: started, jitter: jitter) })
        else { return }
        performFrameSocket(command)
    }

    private func performFrameSocket(_ command: CrossyDuelFrameSocketCommand) {
        switch command {
        case .none:
            return
        case .disconnect:
            closeFrameSocket()
            Self.logger.notice("frames closed socket=\(String(describing: self.frameLink?.socket), privacy: .public)")
        case .connect(let topic, let refreshToken):
            openFrameSocket(topic: topic, refreshToken: refreshToken)
        }
    }

    /// 연다. 토큰이 만료돼 거절된 뒤의 한 번(`refreshToken`)이면 판 상태를 한 번 읽어 토큰을 새로 받는다(세션 재시도가 갱신한다).
    /// 읽은 뒤에도 토큰이 거절된 그대로면 다시 붙지 않는다(테트리스 11-03 검토 F4 와 같은 규칙).
    private func openFrameSocket(topic: String, refreshToken: Bool) {
        guard CrossyDuelFrameWire.isFrameTopic(topic), let host, let session = host.session, host.service.anonKey != nil,
              resolvedFrameChannel() != nil, let matchID = frameLinkMatchID else {
            let now = uptime()
            let jitter = frameJitter
            withFrameLink { _ = $0.apply(.closed(code: nil), at: now, jitter: jitter) }
            return
        }
        guard refreshToken, session.accessToken == frameSocketToken else {
            connectFrameChannel(topic: topic)
            return
        }
        frameConnectTicket &+= 1
        let ticket = frameConnectTicket
        let generation = duelGeneration
        let rejectedToken = session.accessToken
        let merged = stateInFlight
        Self.logger.notice("frames token expired — refreshing session before the one retry merged=\(merged)")
        Task { @MainActor [weak self] in
            await self?.refreshMatch(id: matchID)
            guard let self, ticket == self.frameConnectTicket, generation == self.duelGeneration,
                  self.frameLink?.socket == .connecting else { return }
            guard let fresh = self.host?.session?.accessToken, fresh != rejectedToken else {
                let now = self.uptime()
                let jitter = self.frameJitter
                let event: RealtimeTransportEvent = merged ? .closed(code: nil) : .joinRejected(.expiredToken)
                if let command = self.withFrameLink({ $0.apply(event, at: now, jitter: jitter) }) {
                    self.performFrameSocket(command)
                }
                return
            }
            self.connectFrameChannel(topic: topic)
        }
    }

    private func connectFrameChannel(topic: String) {
        guard let host, let session = host.session, let apiKey = host.service.anonKey,
              let channel = resolvedFrameChannel() else { return }
        frameConnectTicket &+= 1
        frameSocketOpen = true
        frameSocketTopic = topic
        frameSocketToken = session.accessToken
        Self.logger.notice("frames connect retries=\(self.frameLink?.retriesUsed ?? 0)")
        channel.connect(url: host.service.projectURL, apiKey: apiKey, accessToken: session.accessToken, topic: topic)
    }

    /// 닫는다(열려 있을 때만 소켓에 시킨다 — 몇 번을 불러도 같다).
    func closeFrameSocket() {
        frameConnectTicket &+= 1
        if frameSocketOpen { frameChannel?.disconnect() }
        frameSocketOpen = false
        frameSocketTopic = nil
    }

    /// 판 중 세션 토큰이 바뀌었으면 열린 채널에 밀어 넣는다(안 보내면 만료 때 채널이 닫힌다). join 된 뒤에만.
    private func pushFrameTokenIfChanged() {
        guard frameSocketOpen, frameLink?.socket == .joined, let token = host?.session?.accessToken,
              let used = frameSocketToken, token != used else { return }
        frameSocketToken = token
        frameChannel?.pushAccessToken(token)
    }

    // MARK: - 소켓 사건

    /// 소켓 사건 하나. 닫힌 소켓(이 스토어가 이미 disconnect 를 시켰다)의 늦은 사건은 버린다.
    /// 받아들인 상대 프레임은 장부에만 남는다 — 트랙의 상대 점수는 `raceSnapshot` 이 `max(프레임 sc, DB)` 로 읽는다(표시 전용).
    package func handleFrameChannelEvent(_ event: CrossyDuelFrameChannelEvent) {
        guard frameSocketOpen, frameLink != nil else { return }
        let now = uptime()
        switch event {
        case .transport(let transport):
            let jitter = frameJitter
            let command = withFrameLink { $0.apply(transport, at: now, jitter: jitter) } ?? .none
            if transport == .joined, frameLink?.socket == .joined { Self.logger.notice("frames joined") }
            if command == .disconnect {
                closeFrameSocket()
                Self.logger.notice("""
                    frames closed by \(String(describing: transport), privacy: .public) \
                    socket=\(String(describing: self.frameLink?.socket), privacy: .public)
                    """)
            }
        case .frame(let frame):
            withFrameLink { _ = $0.receive(frame, at: now) }
        case .rejected:
            break
        }
    }

    // MARK: - 내부

    @discardableResult
    private func withFrameLink<R>(_ body: (inout CrossyDuelFrameLink) -> R) -> R? {
        guard frameLink != nil else { return nil }
        return body(&frameLink!)
    }
}
