import Foundation

// 테트리스 대결 스토어의 **판 표시 프레임 갈래**(본문 머리말 ⑪) — 명세 docs/plan/tetris-broadcast/SPEC.md §4·§5·§6·§8·§9·§10.
// 저장 프로퍼티는 본문(TetrisDuelStore.swift)에 있고 여기는 로직만 둔다. 판정은 전부 순수 장부(`TetrisFrameLink`)가 하고,
// 이 파일은 그 판정을 스토어의 사실(응답 · 판 루프 · 소켓 사건)에 잇고 시키는 일만 한다.
//
//   응답(applyState) ─ noteServerFrames: state.frames · 관전자 수 · 실패 streak → 장부 → 소켓 열기·닫기
//                    ─ mergedOpponentBoard: DB 판에 프레임을 겹친다(되감지 않게)        · 끝난 판 → finishFrames(곧바로 닫기)
//   판 루프(tick)     ─ considerFrame: ① 소켓 명령 ② 토큰 갱신 밀어 넣기 ③ 프레임 보내기 ④ ring 유실 힌트(풀릴 때까지 tetris_state 1회)
//   보고(considerReport) ─ frameReportInterval: 조건 7개가 모두 참이면 3초 · 아니면 1초
//   소켓 사건         ─ handleFrameChannelEvent: join · 닫힘(사유별 재시도) · 상대 프레임 → applyFrame(상대 판만)
//                      (상대 연결 시각은 장부의 단조 수신 시각 — `opponentSilenceSeconds` 가 DB 침묵과 작은 쪽을 쓴다)
//   판을 내림 · 물러남 · 로그아웃(discardDuel) ─ discardFrames: 닫고 장부를 버린다
//
// ★ 프레임은 **표시 전용**이다. 이 파일에는 `heldOpponentSeq` · `opponentAttackTotal` · 공격 대기열 · 승패 · 루비를 바꾸는 줄이 없다
//   (§3 불변식 · §4 ★ · D4). 공격 누계는 힌트 판정에 **읽기만** 한다.

extension TetrisDuelStore {

    // MARK: - 능력

    /// 이 기기가 판 표시 프레임을 실제로 열 수 있는가 — 배선 스위치(`framesEnabled`) + 리얼타임 킬스위치 + 테스트 프로세스 아님
    /// (= 소켓이 만들어진다) + 키가 있다. 참이어야 `tetris_report` 가 `p_protocol` 2 를 싣는다(§11 — 못 여는 기기가 2를 보내면
    /// 상대가 헛되이 소켓을 연다).
    package var framesCapable: Bool {
        guard framesEnabled, let host, host.service.anonKey != nil else { return false }
        return resolvedFrameChannel() != nil
    }

    /// 프레임 소켓을 처음 필요할 때 **한 번만** 만든다(리얼타임 킬스위치도 그때 한 번 읽는다 — 실행 중에 뒤집히지 않게).
    @discardableResult
    func resolvedFrameChannel() -> (any TetrisFrameChannel)? {
        if !frameChannelResolved {
            frameChannelResolved = true
            let channel = makeFrameChannel(defaults ?? .standard)
            channel?.onEvent = { [weak self] event in self?.handleFrameChannelEvent(event) }
            frameChannel = channel
        }
        return frameChannel
    }

    // MARK: - 응답에서

    /// 진행 중이고 **이 기기가 두는** 판의 응답마다(`applyState` 의 plays 가지): 서버 켬/끔 · 관전자 수 · 실패 streak 를 장부에 넣고,
    /// 켜졌으면 소켓을 열고 꺼졌으면 닫는다(판 루프 걸음을 기다리지 않는다).
    func noteServerFrames(_ frames: TetrisFramesRow?, matchID: String, opponentID: String, watchers: Int,
                          at now: TimeInterval) {
        guard framesCapable else {
            if frameLink != nil { discardFrames() }
            return
        }
        if frameLink == nil || frameLinkMatchID != matchID {
            guard let me = host?.session?.userID, !me.isEmpty, !opponentID.isEmpty else { return }
            discardFrames()
            // 프레임 번호의 시작 = 지금 벽시계 ms(§4 순서 판정 — 다시 연 프로세스·다시 만든 장부의 첫 장이 옛 장보다 크다).
            let wallMs = clock().timeIntervalSince1970 * 1000
            frameLink = TetrisFrameLink(me: me, opponent: opponentID,
                                        frameBase: wallMs.isFinite && wallMs > 0 ? Int(wallMs.rounded(.down)) : 0)
            frameLinkMatchID = matchID
        }
        let wasOn = frameLink?.topic != nil
        let streak = reportFailureStreak
        withFrameLink {
            $0.noteServerFrames(frames)
            $0.noteWatchers(watchers)
            $0.noteReportFailureStreak(streak)
        }
        let isOn = frameLink?.topic != nil
        if wasOn != isOn { Self.logger.notice("frames \(isOn ? "on" : "off", privacy: .public) by server") }
        driveFrameSocket(at: now)
    }

    /// 서버가 판을 닫았다(끝난 판 가지). 소켓을 **곧바로** 닫고 장부는 남긴다 — 결과 화면의 상대 판·줄이 마지막으로 받은 프레임을
    /// 쓰고(§4 끝난 판 규칙), 끝난 뒤 닿은 프레임은 장부가 버린다.
    func finishFrames() {
        guard frameLink != nil else { return }
        let command = withFrameLink { $0.finish() }
        if command == .disconnect || frameSocketOpen {
            closeFrameSocket()
            Self.logger.notice("frames closed — match finished")
        }
    }

    /// 구동기를 버릴 때(`discardDuel` — 판을 내림 · 물러남 · 로그아웃 · 다른 판): 닫고 장부를 버린다.
    func discardFrames() {
        closeFrameSocket()
        frameLink = nil
        frameLinkMatchID = nil
        frameSocketToken = nil
        loggedReportInterval = nil
    }

    /// 보고 실패 streak 가 바뀐 세 자리(멎음 버림 · 실패 · 성공)에서 부른다 — 조건 5.
    func noteFrameReportStreak() {
        let streak = reportFailureStreak
        withFrameLink { $0.noteReportFailureStreak(streak) }
    }

    /// 지금 하트비트 간격. 이 판의 장부가 없으면 1초(지금과 같다). 1초 ↔ 3초가 바뀔 때만 로그 한 줄.
    func frameReportInterval(at now: TimeInterval, matchID: String) -> TimeInterval {
        guard let link = frameLink, frameLinkMatchID == matchID else { return TetrisDuelSession.heartbeatSeconds }
        let interval = link.reportInterval(at: now)
        if loggedReportInterval != interval {
            loggedReportInterval = interval
            let c = link.conditions(at: now)
            Self.logger.notice("""
                report interval \(Int(interval), privacy: .public)s server=\(c.serverOn, privacy: .public) \
                joined=\(c.joined, privacy: .public) heard=\(c.heardRecently, privacy: .public) \
                hears=\(c.opponentHearsMe, privacy: .public) healthy=\(c.reportsHealthy, privacy: .public) \
                watchers0=\(c.noWatchers, privacy: .public) steady=\(c.steady, privacy: .public)
                """)
        }
        return interval
    }

    // MARK: - 판 루프에서

    /// 판 루프 한 걸음(`tick` · 하드드롭): ① 소켓 열기·닫기(멈춤 10초 · 재시도) ② 바뀐 세션 토큰 밀어 넣기 ③ 프레임 보내기(1초 +
    /// 공격 즉시 · 초당 4장) ④ ring 유실 힌트. **보고와 따로 돈다** — 나가 있는 보고(`reportInFlight`)가 프레임을 막지 않는다.
    func considerFrame(at now: TimeInterval) {
        guard frameLink != nil, let current = match, !current.isFinished, frameLinkMatchID == current.id,
              let duel, duelMatchID == current.id, host?.session != nil else { return }
        driveFrameSocket(at: now)
        pushFrameTokenIfChanged()
        if frameSocketOpen, let channel = frameChannel,
           frameLink?.frameDue(at: now, live: duel.isLive, attackSent: duel.game.attackSentTotal) == true,
           let frame = withFrameLink({
               $0.makeFrame(at: now, seq: duel.seq, board: TetrisDuelBoard.encode(duel.game), lines: duel.game.lines,
                            attackSent: duel.game.attackSentTotal, pending: duel.game.pendingGarbageLines)
           }) {
            channel.send(event: TetrisFrame.event, payload: frame.payload)
        }
        let attackTotal = opponentAttackTotal
        if withFrameLink({ $0.shouldHintSync(at: now, opponentAttackTotal: attackTotal) }) == true {
            // ring 이 사라졌다 — 상대 프레임의 공격 누계가 DB 보다 큰 채로 1초. 그 값에 **한 번만** 판 상태를 읽는다(§6).
            Self.logger.notice("frames hint — opponent attack ahead of server total, syncing once")
            requestSync()
        }
    }

    /// 장부가 소켓에게 시킬 일을 묻고 시킨다.
    private func driveFrameSocket(at now: TimeInterval) {
        guard frameLink != nil else { return }
        let started = duel?.startAt
        let jitter = frameJitter
        guard let command = withFrameLink({ $0.socketCommand(at: now, matchStartedAt: started, jitter: jitter) })
        else { return }
        performFrameSocket(command)
    }

    private func performFrameSocket(_ command: TetrisFrameSocketCommand) {
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

    /// 연다. 토큰이 만료돼 거절된 뒤의 한 번(`refreshToken`)이면 판 상태를 한 번 읽어 토큰을 새로 받는다 — 세션 재시도
    /// (`withSessionRetry`)가 만료 응답에서 갱신한다. 이미 새 토큰이면 곧바로 연다.
    /// ★ 읽은 뒤에도 토큰이 **거절된 그대로**면 다시 붙지 않는다(인가 검사만 헛쓴다 — 11-03 검토 F4).
    ///   · 읽기가 이미 도는 조회와 합쳐졌다(`refreshMatch` 가 곧바로 돌아온다 — 그 조회가 끝나야 토큰이 바뀐다): 일반 재시도 한 번으로 미룬다.
    ///   · 우리 읽기가 돌았는데도 그대로다(REST 는 아직 유효하다 — 기기 시계 차 등): 두 번째 만료와 같은 결론으로 이 판은 멈춘다.
    private func openFrameSocket(topic: String, refreshToken: Bool) {
        guard TetrisFrameWire.isFrameTopic(topic), let host, let session = host.session, host.service.anonKey != nil,
              resolvedFrameChannel() != nil, let matchID = frameLinkMatchID else {
            // 열 수 없다 — 닫힘으로 알린다(재시도 규칙 → 판당 3회 뒤 그 판은 1초).
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
                Self.logger.notice("frames token unchanged after refresh — \(merged ? "retry later" : "stop", privacy: .public)")
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

    /// 판 중 세션 토큰이 바뀌었으면 열린 채널에 밀어 넣는다(안 보내면 만료 때 채널이 닫힌다 — §10). join 된 뒤에만.
    private func pushFrameTokenIfChanged() {
        guard frameSocketOpen, frameLink?.socket == .joined, let token = host?.session?.accessToken,
              let used = frameSocketToken, token != used else { return }
        frameSocketToken = token
        frameChannel?.pushAccessToken(token)
    }

    // MARK: - 소켓 사건

    /// 프레임 소켓의 사건 하나. 닫힌 소켓(이 스토어가 이미 disconnect 를 시켰다)의 늦은 사건은 버린다.
    func handleFrameChannelEvent(_ event: TetrisFrameChannelEvent) {
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
            // 장부가 버린 프레임(남의 것 · 순서에서 짐 · 끝난 판)은 아무것도 바꾸지 않는다. 받은 프레임의 단조 수신 시각
            // (`lastFrameAt`)이 "상대 연결 확인 중"(5초)의 재료가 된다 — `opponentSilenceSeconds` 가 DB 침묵과 작은 쪽을 쓴다.
            guard frameLink != nil, frameLink!.receive(frame, at: now) == nil else { return }
            applyFrame()
        case .rejected:
            // 우리 토픽에 온 깨진 프레임 — 아무것도 바꾸지 않는다.
            break
        }
    }

    /// 받아들인 프레임을 화면에 — **`match.opponentBoard` 만** 바꾸고 값이 바뀔 때만 대입한다(관찰자를 헛되게 깨우지 않게).
    /// 기준 DB seq 는 들고 있는 DB 최댓값(`heldOpponentSeq`)이다 — 그보다 옛 보고 뒤의 프레임이면 DB 판이 더 새것이다.
    private func applyFrame() {
        guard let current = match, current.id == frameLinkMatchID, !current.isFinished else { return }
        let merged = Self.mergedOpponentBoard(db: current.opponentBoard, dbSeq: heldOpponentSeq, frames: frameLink,
                                              settledAttack: nil)
        if merged != current.opponentBoard { match?.opponentBoard = merged }
    }

    // MARK: - 표시 병합(§4, 순수)

    /// DB 판(`db` — 응답의 상대 행을 옮긴 값)에 마지막으로 받은 프레임을 겹친다. 마지막 프레임의 `s` 가 DB seq 이상이면 판·줄·대기 줄은
    /// 프레임, 보낸 공격(표시용)은 두 값의 max. DB seq 가 더 크면 DB. **준비·탑아웃은 언제나 DB** 다. 끝난 판도 판·줄은 같은 규칙이다.
    /// - Parameter settledAttack: 끝난 판 응답의 상대 행 `garbage_sent`(진행 중이면 nil). 있으면 보낸 공격 수는 **그 값 그대로**다 —
    ///   정산의 정본이고, 판 중에 프레임이 올려 둔 표시값(`db` 는 이전 표시와 max 한 값이다)이나 위조 `g` 가 결과 화면에 남지 않게
    ///   (11-03 검토 F5).
    package nonisolated static func mergedOpponentBoard(
        db: TetrisDuelOpponentBoard, dbSeq: Int, frames link: TetrisFrameLink?, settledAttack: Int?
    ) -> TetrisDuelOpponentBoard {
        var cells = db.cells
        var lines = db.lines
        var pending = db.pending
        var attack = db.attackSent
        var framed = false
        if let link, let frame = link.lastFrame, frame.seq >= dbSeq, let decoded = TetrisDuelBoard.decode(frame.board) {
            let shown = link.mergedDisplay(dbSeq: dbSeq, db: TetrisOpponentDisplay(
                board: nil, lines: db.lines, pending: db.pending, attackSent: db.attackSent))
            cells = decoded
            lines = shown.lines
            pending = shown.pending
            attack = shown.attackSent
            framed = true
        }
        if let settledAttack { attack = settledAttack }
        guard framed || attack != db.attackSent else { return db }
        return TetrisDuelOpponentBoard(cells: cells, hasBoard: framed || db.hasBoard, lines: lines, attackSent: attack,
                                       pending: pending, toppedOut: db.toppedOut, ready: db.ready)
    }

    // MARK: - 내부

    /// 장부가 있으면 그 자리에서 바꾼다(없으면 nil).
    @discardableResult
    private func withFrameLink<R>(_ body: (inout TetrisFrameLink) -> R) -> R? {
        guard frameLink != nil else { return nil }
        return body(&frameLink!)
    }
}
