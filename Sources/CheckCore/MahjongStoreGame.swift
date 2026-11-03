import Foundation

// 아잉 마작 스토어 — 판 state 적용 · 내 차례 동작 · 깨우기·폴링 걸음(SPEC §4.5).
//
// ── 늦은 응답 가드(MCL:103) ──
//  (a) 접은 판 (b) 끝난 판 뒤 진행 응답 (c) 같은 판은 `hand_index` → `seq` → 요청 표 순 (d) 다른 판은 표
//  (e) 울기 답 응답이 왔는데 state 의 내 `my_decision.window_id` 가 다르면 프롬프트를 조용히 내린다(`window_closed` 도 같다)
//  (f) **결정 키가 바뀌거나 `my_decision == nil` 이 되는 순간** 2단 입력을 모두 접는다(CC-03)
//  (g) 서버 경로 응답은 연습 칸을 건드리지 않는다 (h) 울기 답은 한 창 안에서 단조(CC-26) (i) ⓓ·ⓔ.
//  C1 은 (a)(b)(c)(e)(f)(g)(h)·ⓔ 를 `applyState` 에 두었다. 요청 표(c 끝·d)·ⓓ(writeRevision)는 C2 가 요청 경로와 함께 채운다.

extension MahjongStore {
    /// `applyState` 결과(체스·리버시와 같다). `needsFull` = 사건 꼬리에 구멍 — 부르는 쪽이 `p_since 0` 으로 다시 읽는다.
    package enum StateApplyOutcome: Equatable { case applied, needsFull, ignored }

    /// 사건 꼬리 보관 상한(서버 `events` 최대 80 과 같다).
    nonisolated static let eventTailLimit = 80

    /// 서버 state 하나를 넣는다. **서버 전용** — 연습 칸(`practice`)을 안 건드린다(가드 (g)).
    /// - Parameter requestedSince: 요청에 실은 `p_since_seq`(쓰기 RPC 응답은 0 — 사건 꼬리 전체).
    @discardableResult
    package func applyState(_ payload: MahjongStatePayload, requestedSince: Int = 0) -> StateApplyOutcome {
        applyState(payload, requestedSince: requestedSince, ticket: nil, predatesWrite: false)
    }

    /// 요청 경로의 깔때기. `ticket` = 그 요청을 **보낼 때** 뗀 표(nil 이면 지금 떼어 가장 새것으로 친다).
    /// `predatesWrite` = 이 응답은 그 뒤에 받은 쓰기 응답보다 먼저 나갔다(ⓓ — 잔액을 덮지 않는다).
    @discardableResult
    func applyState(
        _ payload: MahjongStatePayload, requestedSince: Int, ticket rawTicket: Int?, predatesWrite: Bool
    ) -> StateApplyOutcome {
        guard let incoming = payload.match, !incoming.isPractice else { return .ignored }
        // (a) 접은 판.
        if dismissedMatchIDs.contains(incoming.id) { return .ignored }
        let ticket = rawTicket ?? issueTicket()

        var next = payload
        if let current = match?.match, current.id == incoming.id {
            let held = current.matchStatus
            let arriving = incoming.matchStatus
            // (b) 끝난 판 뒤의 진행 응답.
            if held.isTerminal, !arriving.isTerminal { return .ignored }
            // ⓔ 판으로 든 id 에 늦게 온 방 단계 응답(forming·cancelled·expired).
            if held == .active || held == .finished,
               arriving == .forming || arriving == .cancelled || arriving == .expired {
                return .ignored
            }
            // (c) 같은 판은 hand_index → seq 순.
            let heldHand = current.handIndex ?? -1
            let arrivingHand = incoming.handIndex ?? -1
            if arrivingHand < heldHand { return .ignored }
            if arrivingHand == heldHand, (incoming.seq ?? 0) < (current.seq ?? 0) { return .ignored }
            // (c) 끝 — 같은 국·같은 seq 면 요청 표(forming 방은 seq 가 안 오른다).
            if arrivingHand == heldHand, (incoming.seq ?? 0) == (current.seq ?? 0), ticket < appliedTicket {
                return .ignored
            }
            // 사건 꼬리 이어 붙이기 — 요청 seq 다음부터 와야 한다(아니면 구멍).
            if requestedSince > 0 {
                if let first = payload.events?.first?.seq, first > requestedSince + 1 { return .needsFull }
                next.events = Self.mergedEvents(held: match?.events ?? [], arriving: payload.events ?? [])
            }
        } else {
            // (d) 다른 판은 요청 표 — 방을 옮긴 뒤 늦게 온 옛 방의 응답.
            if match?.match != nil, ticket < appliedTicket { return .ignored }
            // 다른 판의 일부 꼬리만 받았다 — 전체로 다시.
            if requestedSince > 0 { return .needsFull }
        }
        noteServerClock(payload.serverNowMs)

        // 닫힌 방(취소·만료) — 들고 있던 방이면 내리고 한 줄.
        if incoming.matchStatus == .cancelled || incoming.matchStatus == .expired {
            appliedTicket = max(appliedTicket, ticket)
            if match?.match?.id == incoming.id {
                leaveHeldRoom(incoming.id)
                setNotice(MahjongNoticeText.roomClosed)
            } else {
                dropOwnership(incoming.id)
            }
            if activeMatchID == incoming.id { activeMatchID = nil }
            return .applied
        }
        // 내 자리가 아닌 state(초대만 받은 방 · 빠진 방)는 들지 않는다.
        if let me = myUserID, !Self.isParticipant(payload, userID: me) {
            if match?.match?.id == incoming.id {
                appliedTicket = max(appliedTicket, ticket)
                // 시작 검사에서 빠진 멤버(state 'dropped')면 까닭을 짐작하지 않는 중립 문구(SPEC v1.0.3 §4.5).
                let droppedHere = incoming.matchStatus == .forming
                    && (payload.members?.contains { $0.user?.id?.lowercased() == me && $0.state == "dropped" } ?? false)
                leaveHeldRoom(incoming.id)
                setNotice(droppedHere ? MahjongNoticeText.droppedAtStart : MahjongNoticeText.roomClosed)
            }
            return .ignored
        }

        // (h) 울기 답 단조: 답한 창의 `answered == nil` 은 프롬프트를 되살리지 않는다.
        if case .call(var call)? = next.myDecision, call.answered == nil,
           answeredWindowIDs.contains(Self.windowKey(matchID: incoming.id, windowID: call.windowId)) {
            if case .call(let held)? = match?.myDecision, held.windowId == call.windowId, let answer = held.answered {
                call.answered = answer
                next.myDecision = .call(call)
            } else {
                call.answered = answeredWindowAnswers[Self.windowKey(matchID: incoming.id, windowID: call.windowId)]
                    ?? MahjongClaimAnswer.pass.rawValue
                next.myDecision = .call(call)
            }
        }

        appliedTicket = max(appliedTicket, ticket)
        let previous = match
        // 방 단계 응답(state·참가·만들기)은 서버가 내 `last_seen_at` 을 갱신한 증거다 — 방 확인 30초를 여기서 다시 센다.
        if incoming.matchStatus == .forming { lastRoomCheckAt = clock() }
        noteTimeouts(previous: previous, next: next)
        noteMotion(previous: previous, next: next)
        if previous != next { match = next }
        // ⓓ 쓰기 응답보다 먼저 나간 state 는 잔액을 덮지 않는다(V2-06).
        if !predatesWrite { applyRuby(next.rubyBalance) }
        afterMatchApplied(previous: previous)
        return .applied
    }

    /// 이 state 에 내가 앉아 있는가 — forming 은 joined 멤버(또는 방장), active·finished 는 내 자리.
    nonisolated static func isParticipant(_ payload: MahjongStatePayload, userID me: String) -> Bool {
        guard let match = payload.match else { return false }
        switch match.matchStatus {
        case .forming:
            if match.host?.id?.lowercased() == me { return true }
            return payload.members?.contains { $0.user?.id?.lowercased() == me && $0.state == "joined" } ?? false
        case .active, .finished:
            return payload.mySeat != nil
        default:
            return true
        }
    }

    /// `match` 가 바뀐 뒤 한 곳(didSet). 단계 · 결정 키 접기(f) · 판 끝 · 연습판 버림.
    func matchDidChange(from old: MahjongStatePayload?) {
        // (f) 결정 키가 바뀌거나 결정이 없어지면 2단 입력을 접고 비행 잠금을 푼다(CC-03 · CC-06). 연습 탁자를 보이는 동안은
        // 단추가 연습판 결정을 그리므로 서버 쪽 키 변화로 접지 않는다.
        if !showsPractice {
            let oldKey = MahjongDecisionKey.of(old)
            let newKey = MahjongDecisionKey.of(match)
            if oldKey != newKey || newKey == nil {
                foldTwoStageInputs()
                if oldKey != newKey {
                    if isWorking { isWorking = false }
                    if isAnsweringCall { isAnsweringCall = false }
                }
            }
        }

        let previous = old?.match
        let current = match?.match
        let sameMatch = previous?.id != nil && previous?.id == current?.id

        // 루비 판이 서면 연습판을 버린다(리버시 ChessStore:658 과 같다).
        if let current, current.matchStatus == .active, !(sameMatch && previous?.matchStatus == .active), practice != nil {
            discardPracticeGame()   // 봇·걸음·시계 작업까지 거둔다
            showsPractice = false
            notice = MahjongNoticeText.practiceClosed
        }
        // 연습 중 서버 방에 넷째가 앉았다/빠졌다 — 방장이면 연습을 멈추거나 푼다(CC-02).
        syncPracticeRoomHold(old: old)

        // 끝난 판을 처음 본 순간 한 번 — 장부에서 걷고, 무효 판이 아니면 판 끝 콜백.
        if let current, current.matchStatus.isTerminal, !(sameMatch && previous?.matchStatus.isTerminal == true) {
            dropOwnership(current.id)
            if current.matchStatus == .finished, !current.isVoid { onMatchFinished?() }
            // ⑯ 정산을 처음 본 순간 로비(잔액·전적)·순위 다시 읽기.
            if host?.session != nil {
                Task { @MainActor [weak self] in
                    await self?.refreshLobby()
                    await self?.refreshRanking()
                }
            }
        }
        // 판이 선 순간(판돈 차감) 로비 다시 읽기.
        if let current, current.matchStatus == .active, !(sameMatch && previous?.matchStatus == .active),
           host?.session != nil {
            Task { @MainActor [weak self] in await self?.refreshLobby() }
        }
        // 넷째가 앉은 순간(같은 방에서 3 → 4).
        if let current, current.matchStatus == .forming, sameMatch, previous?.matchStatus == .forming,
           Self.joinedCount(old) < 4, Self.joinedCount(match) == 4 {
            setNotice(MahjongNoticeText.fourGathered)
        }

        recomputePhase()
        scheduleWake()
        syncHoldingActivity()
    }

    /// 울기 창 열쇠("판#창번호").
    nonisolated static func windowKey(matchID: String, windowID: Int) -> String { "\(matchID)#\(windowID)" }

    /// 사건 꼬리를 seq 로 이어 붙인다(겹치면 새 것, seq 순, 최근 80).
    nonisolated static func mergedEvents(held: [MahjongEvent], arriving: [MahjongEvent]) -> [MahjongEvent] {
        var bySeq: [Int: MahjongEvent] = [:]
        for event in held { bySeq[event.seq] = event }
        for event in arriving { bySeq[event.seq] = event }
        let ordered = bySeq.values.sorted { $0.seq < $1.seq }
        return Array(ordered.suffix(eventTailLimit))
    }

    // MARK: 판 조회(직렬화 · 합치기 · 꼬리 이어 받기)

    /// 한 판(방)의 state 를 읽는다. 같은 판을 들고 있으면 `p_since_seq = 내 seq` 로 **새 사건만** 받고, 구멍이 보이면 처음부터
    /// 한 번 더. 도는 중에 같은 판이 또 불리면 뒤따르는 한 번으로 합치고(`stateAgain`), **다른 판** id 는 지금 것이 끝난 뒤 한 번.
    func refreshMatch(id rawID: String?) async {
        guard let requested = rawID?.lowercased(), !requested.isEmpty,
              !requested.hasPrefix(MahjongStatePayload.practiceIDPrefix), host?.session != nil else { return }
        if stateInFlight {
            if requested == stateInFlightID { stateAgain = true } else { pendingStateID = requested }
            return
        }
        stateInFlight = true
        let generation = resetGeneration
        var nextID: String? = requested
        while let id = nextID {
            nextID = nil
            stateInFlightID = id
            var forceFull = false
            repeat {
                stateAgain = false
                let since = (!forceFull && match?.match?.id == id) ? (match?.match?.seq ?? 0) : 0
                forceFull = false
                lastStateRequestAt = clock()
                let ticket = issueTicket()
                let writes = writeRevision
                let result = await perform({
                    try await $0.mahjongState(accessToken: $1, matchID: id, sinceSeq: since)
                })
                guard generation == resetGeneration else { return }
                switch result {
                case .success(let response)?:
                    noteServerClock(response.serverNowMs)
                    switch response.status {
                    case .ok:
                        if let state = response.state,
                           applyState(state, requestedSince: since, ticket: ticket,
                                      predatesWrite: writes != writeRevision) == .needsFull, since > 0 {
                            forceFull = true
                            stateAgain = true
                        }
                    case .notFound:
                        matchNotFound(id)
                    case .unsupportedClient:
                        noteUpdateRequired()
                    case .unauthorized:
                        setNotice(MahjongNoticeText.signInAgain)
                    default:
                        if let state = response.state {
                            applyState(state, requestedSince: 0, ticket: ticket, predatesWrite: writes != writeRevision)
                        }
                    }
                case .failure(let error)?:
                    if isSchemaMissing(error) { noteServerMissing() }
                case nil:
                    break
                }
            } while stateAgain && generation == resetGeneration
            if let pending = pendingStateID {
                pendingStateID = nil
                nextID = pending
            }
        }
        stateInFlightID = nil
        stateInFlight = false
    }

    /// 판·방 조회가 `not_found` — 들고 있던 것이면 내리고 한 줄. 넷이 모인 방에서 방장이 아닌 내가 not_found 를 받았으면
    /// 시작 검사에서 빠진 것으로 본다(서버가 빠진 사람에게 까닭을 따로 주지 않는다 — 추정, 보고에 적음).
    func matchNotFound(_ id: String) {
        if activeMatchID == id { activeMatchID = nil }
        guard let held = match?.match, held.id == id else {
            dropOwnership(id)
            return
        }
        switch held.matchStatus {
        case .forming:
            let wasFull = Self.joinedCount(match) == 4 && !isHost
            setNotice(wasFull ? MahjongNoticeText.droppedAtStart : MahjongNoticeText.roomClosed)
        case .active:
            setNotice(MahjongNoticeText.finishedMatch)
        default:
            break
        }
        leaveHeldRoom(id)
    }

    // MARK: 적용 뒤 — 알림 · 보조 · 깨우기

    /// state 를 하나 넣은 뒤 한 곳: 알림(장부 판만) · 보조 자동 보내기(장부 판만) · 깨우기 다시 잡기.
    func afterMatchApplied(previous: MahjongStatePayload?) {
        announce(previous: previous)
        runAids()
        scheduleWake()
    }

    /// 알림 정책(CC-01 3 — D41). 모두 `ownsMatch` 판에서만 · 덮개 말풍선 하나(`onAttention`).
    ///  · matchStarted — 판이 처음 active 로 보인 때: 창을 띄우고, 창이 탁자를 보이지 않으면(가림 포함) 말풍선. 열쇠 `판`.
    ///  · myTurn — 국마다 첫 내 결정(차례 · 론이 든 울기)에만, 창이 탁자를 안 보일 때. 열쇠 `판#국`.
    ///  · away — 내 자리가 비움이 된 때 1회. 열쇠 `판#away#since`.
    func announce(previous: MahjongStatePayload?) {
        guard let payload = match, let current = payload.match, current.matchStatus == .active,
              ownsMatch(current.id) else { return }
        let showing = isWindowShowingTable
        let prior = previous?.match
        if !(prior?.id == current.id && prior?.matchStatus == .active),
           !deliveredAttentionKeys.contains(current.id) {
            presentWindow?()
            if showing {
                deliveredAttentionKeys.insert(current.id)
            } else {
                requestAttention?()
                deliverAttention(MahjongAttention(
                    kind: .matchStarted, matchID: current.id, handIndex: current.handIndex ?? 0, key: current.id))
            }
        }
        if let away = payload.myAway {
            deliverAttention(MahjongAttention(
                kind: .away, matchID: current.id, handIndex: current.handIndex ?? 0,
                key: "\(current.id)#away#\(Int64(away.sinceMs ?? 0))"))
        } else if !showing, let decision = payload.myDecision {
            let qualifies: Bool
            switch decision {
            case .turn: qualifies = true
            case .call(let call): qualifies = call.ron && call.answered == nil
            }
            if qualifies {
                deliverAttention(MahjongAttention(
                    kind: .myTurn, matchID: current.id, handIndex: current.handIndex ?? 0,
                    key: "\(current.id)#\(current.handIndex ?? 0)"))
            }
        }
    }

    /// 시간 초과 문구(UX:144): 내 자동 버림 표지(`priv.auto`)가 새로 왔거나, 답하지 않은 내 울기 창이 마감 + 유예 뒤에 닫혔다.
    func noteTimeouts(previous: MahjongStatePayload?, next: MahjongStatePayload) {
        guard let current = next.match, current.matchStatus == .active, next.myAway == nil,
              let held = previous?.match, held.id == current.id else { return }
        let heldSeq = held.seq ?? 0
        if let mySeat = next.mySeat,
           let auto = next.events?.last(where: { $0.seq > heldSeq && $0.isAutoDiscard && $0.seat == mySeat }),
           timeoutNoticeKeys.insert("\(current.id)#auto#\(auto.seq)").inserted {
            setNotice(MahjongNoticeText.timeoutDiscarded)
            return
        }
        if case .call(let call)? = previous?.myDecision, call.answered == nil {
            if case .call(let still)? = next.myDecision, still.windowId == call.windowId { return }
            let grace = Double(current.graceMs ?? held.graceMs ?? Int(Self.defaultGraceMs))
            if let due = localDate(serverMs: call.deadlineMs + grace), clock() >= due,
               timeoutNoticeKeys.insert("\(current.id)#window#\(call.windowId)").inserted {
                setNotice(MahjongNoticeText.timeoutPassed)
            }
        }
    }

    /// 움직임(응답이 온 **뒤** 시작 — 같은 판·같은 국의 새 사건만). 꼬리가 여럿이면 한 장 길이를 줄여 1.5초 안에 따라잡는다.
    func noteMotion(previous: MahjongStatePayload?, next: MahjongStatePayload) {
        guard let held = previous?.match, let current = next.match, held.id == current.id,
              held.handIndex == current.handIndex, let mySeat = next.mySeat else { return }
        let heldSeq = held.seq ?? 0
        let moving = (next.events ?? []).filter {
            $0.seq > heldSeq && ($0.kind == "discard" || $0.kind == "call" || $0.kind == "kan") && $0.seat != nil
        }
        guard let last = moving.last, let seat = last.seat else { return }
        let me = MahjongSeatCompass.of(seat: seat, mySeat: mySeat)
        let kind: MahjongMotion.Kind
        let from: MahjongMotion.Place
        let to: MahjongMotion.Place
        switch last.kind {
        case "discard":
            kind = .discard
            from = .init(compass: me, area: .hand)
            to = .init(compass: me, area: .river)
        case "call":
            kind = .call
            let giver = MahjongSeatCompass.of(seat: last.fromSeat ?? seat, mySeat: mySeat)
            from = .init(compass: giver, area: .river)
            to = .init(compass: me, area: .melds)
        default:
            kind = .kan
            from = .init(compass: me, area: .hand)
            to = .init(compass: me, area: .melds)
        }
        motion = MahjongMotion(
            matchID: current.id, handIndex: current.handIndex ?? 0, seq: last.seq, kind: kind, from: from, to: to,
            startedAt: clock(), duration: MahjongMotion.duration(forTailCount: moving.count))
    }

    // MARK: 보조(aids) — 이 기기가 연 판에서만 자동으로 보낸다

    /// 보조 쯔모기리를 보낼 때 — 리치 중이면 `not_before_ms`(유예 없이), 아니면 결정 시작 + 0.5~1.0초(CC-19 — 서버 멈춤과 같은 꼴).
    func tsumogiriAidDate(_ turn: MahjongDecision.Turn) -> Date? {
        if let notBefore = turn.notBeforeMs { return localDate(serverMs: notBefore) }
        return localDate(serverMs: turn.startedMs)?.addingTimeInterval(aidJitter())
    }

    /// 결정 키마다 한 번: 자동 화료 · 울지 않음(국마다 꺼짐) · 쯔모기리.
    func runAids() {
        guard !showsPractice, let payload = match, let current = payload.match, current.matchStatus == .active,
              payload.myAway == nil, payload.mySeatRow?.away != true, ownsMatch(current.id) else { return }
        let handKey = "\(current.id)#\(current.handIndex ?? 0)"
        if aids.noCalls {
            if let marked = noCallsHandKey, marked != handKey {
                noCallsHandKey = nil
                aids.noCalls = false
            } else if noCallsHandKey == nil {
                noCallsHandKey = handKey
            }
        }
        guard let key = MahjongDecisionKey.of(payload), !aidHandledKeys.contains(key),
              let decision = payload.myDecision else { return }
        switch decision {
        case .turn(let turn):
            if aids.autoWin, turn.tsumo {
                aidHandledKeys.insert(key)
                Task { @MainActor [weak self] in await self?.declareTsumo() }
                return
            }
            guard aids.tsumogiri, !turn.tsumo, turn.ankan.isEmpty, turn.kakan.isEmpty, turn.riichi.isEmpty,
                  let drawn = payload.myDrawn, turn.discard.contains(drawn), let due = tsumogiriAidDate(turn) else { return }
            aidHandledKeys.insert(key)
            let id = current.id
            let expected = current.seq ?? turn.seq
            let generation = resetGeneration
            aidTask?.cancel()
            aidTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let delay = due.timeIntervalSince(self.clock())
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, generation == self.resetGeneration, self.decisionKey == key else { return }
                await self.sendAct("discard", tiles: [drawn], turn: turn, matchID: id, expectedSeq: expected)
            }
        case .call(let call):
            guard call.answered == nil else { return }
            if aids.autoWin, call.ron {
                aidHandledKeys.insert(key)
                Task { @MainActor [weak self] in await self?.call(.ron, tiles: []) }
            } else if aids.noCalls, !call.ron {
                aidHandledKeys.insert(key)
                Task { @MainActor [weak self] in await self?.passCall() }
            }
        }
    }

    // MARK: 깨우기(§3.7 (d) v1.0 표 — 창과 무관, 장부 판에서만)

    /// 다음 깨우기 하나.
    struct WakeTarget: Equatable {
        enum Kind: String { case decision, beat, backup, room }
        let kind: Kind
        let at: Date
        let key: String
        let matchID: String
    }

    /// 지금 판에서 다음으로 깨울 때. ① 내 결정 → 마감 + 유예 + 100ms(리치 중 `not_before` 전이면 그때, 유예 없이)
    /// ② `wake_seat == my_seat` → `wake_at_ms` ③ 그 밖 `backup_at_ms` · 방(내가 joined 인 forming) → 마지막 확인 + 30초.
    /// 같은 열쇠로 이미 쏘았으면 1초 뒤 재시도, 2번까지(그 뒤는 백업·백스톱 몫).
    func wakeTarget(now: Date) -> WakeTarget? {
        guard let payload = match, let current = payload.match, ownsMatch(current.id) else { return nil }
        let target: WakeTarget
        switch current.matchStatus {
        case .forming:
            guard let me = myUserID, Self.isParticipant(payload, userID: me) else { return nil }
            return WakeTarget(
                kind: .room, at: lastRoomCheckAt.addingTimeInterval(Self.roomCheckSeconds),
                key: "room#\(current.id)#\(lastRoomCheckAt.timeIntervalSince1970)", matchID: current.id)
        case .active:
            let signature = "\(current.id)#\(current.seq ?? 0)#\(current.phase ?? "")#\(Int64(current.wakeAtMs ?? -1))"
            let grace = Double(current.graceMs ?? Int(Self.defaultGraceMs))
            if let decision = payload.myDecision {
                var atMs: Double
                switch decision {
                case .turn(let turn):
                    atMs = turn.deadlineMs + grace + Self.wakeSlackMs
                    if let notBefore = turn.notBeforeMs, let nb = localDate(serverMs: notBefore), now < nb {
                        atMs = notBefore
                    }
                case .call(let call):
                    atMs = call.deadlineMs + grace + Self.wakeSlackMs
                }
                guard let at = localDate(serverMs: atMs) else { return nil }
                target = WakeTarget(kind: .decision, at: at, key: "decision#\(signature)#\(Int64(atMs))", matchID: current.id)
            } else if let wakeSeat = current.wakeSeat, wakeSeat == payload.mySeat, let wakeAt = current.wakeAtMs,
                      let at = localDate(serverMs: wakeAt) {
                target = WakeTarget(kind: .beat, at: at, key: "beat#\(signature)", matchID: current.id)
            } else if let backup = current.backupAtMs, let at = localDate(serverMs: backup) {
                target = WakeTarget(kind: .backup, at: at, key: "backup#\(signature)#\(Int64(backup))", matchID: current.id)
            } else {
                return nil
            }
        default:
            return nil
        }
        guard target.key == wakeFiredKey else { return target }
        guard wakeFiredCount <= Self.wakeRetryLimit else { return nil }
        let retry = max(target.at, wakeFiredAt.addingTimeInterval(Self.wakeRetrySeconds))
        return WakeTarget(kind: target.kind, at: retry, key: target.key, matchID: target.matchID)
    }

    /// 깨우기 판정(시험이 직접 밟는다). 때가 됐으면 그 판 state 를 한 번 읽는다 — 응답이 새 깨우기를 다시 잡는다.
    package func checkWake(at now: Date) {
        guard let target = wakeTarget(now: now) else { return }
        guard now >= target.at else {
            scheduleWake()
            return
        }
        if target.key == wakeFiredKey {
            wakeFiredCount += 1
        } else {
            wakeFiredKey = target.key
            wakeFiredCount = 1
        }
        wakeFiredAt = now
        if target.kind == .room { lastRoomCheckAt = now }
        let id = target.matchID
        Task { @MainActor [weak self] in await self?.refreshMatch(id: id) }
    }

    /// 실제 타이머로 다음 깨우기를 잡는다(같은 깨우기 시각이면 한 번만). 박자 기기는 0~150ms 흔들어 동시 호출을 흩는다.
    func scheduleWake() {
        guard timersEnabled, host?.session != nil, let target = wakeTarget(now: clock()) else {
            if wakeTask != nil {
                wakeTask?.cancel()
                wakeTask = nil
            }
            wakeScheduledKey = nil
            return
        }
        let scheduled = "\(target.key)@\(target.at.timeIntervalSince1970)"
        guard scheduled != wakeScheduledKey else { return }
        wakeScheduledKey = scheduled
        wakeTask?.cancel()
        var delay = max(0, target.at.timeIntervalSince(clock()))
        if target.kind == .beat { delay += Double.random(in: 0...(Self.beatJitterMs / 1_000)) }
        let generation = resetGeneration
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == self.resetGeneration else { return }
            self.wakeTask = nil
            self.wakeScheduledKey = nil
            self.checkWake(at: self.clock())
        }
    }

    // MARK: 폴링 걸음

    /// 안전망 한 걸음(③ — **창이 탁자를 보일 때만**, ⓑ 조회는 취소 밖, ⓒ 걸음 사이마다 가드).
    ///  · 방(forming) 10초 · 판 구독 중 5초 / 미구독 1.5초 · 판이 없으면(연습 탁자가 아닐 때) 로비 30초 · 순위 60초.
    package func pollTick(at now: Date) async {
        guard isWindowShowingTable, host?.session != nil else { return }
        if let current = match?.match, !current.matchStatus.isTerminal {
            let interval = current.matchStatus == .forming
                ? Self.roomPollSeconds
                : Self.statePollSeconds(subscribed: host?.realtimeState.isSubscribed ?? false)
            if now.timeIntervalSince(lastStateRequestAt) >= interval {
                let id = current.id
                await outsidePolling { await $0.refreshMatch(id: id) }
            }
        } else if !showsPractice, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await outsidePolling { await $0.refreshLobby() }
        }
        guard isWindowShowingTable, !Task.isCancelled else { return }
        if rankingEnabled, match?.match.map({ $0.matchStatus.isTerminal }) ?? true,
           now.timeIntervalSince(lastRankingRequestAt) >= Self.rankingPollSeconds {
            await outsidePolling { await $0.refreshRanking() }
        }
    }

    // MARK: 내 차례 동작(act)

    /// 지금 내 차례 결정(서버 판 — 연습판은 C3).
    var serverTurn: (payload: MahjongStatePayload, match: MahjongStateMatch, turn: MahjongDecision.Turn)? {
        guard !showsPractice, let payload = match, let current = payload.match, current.matchStatus == .active,
              case .turn(let turn)? = payload.myDecision else { return nil }
        return (payload, current, turn)
    }

    /// 내 자리가 비움인가(서버 판).
    var isAwayHere: Bool {
        guard let payload = match, payload.match?.matchStatus == .active else { return false }
        return payload.myAway != nil || payload.mySeatRow?.away == true
    }

    /// 패를 버린다. 리치 무장이면 리치 선언 버림, 자리 비움이면 `comeBack()`(손패를 한 번 누르면 복귀 — 카드 ⑨).
    package func discard(_ tile: MahjongTile) async {
        if showsPractice {   // 연습판 — 엔진에 바로(서버 왕복 없음)
            practiceDiscard(tile)
            return
        }
        if isAwayHere {
            await comeBack()
            return
        }
        guard !isWorking, let (_, current, turn) = serverTurn else { return }
        let action: String
        if riichiArmed {
            // 무장 뒤에는 서버가 준 `riichi` id 만(로컬 판정을 몰래 쓰지 않는다 — MCL:468 ③).
            guard turn.riichi.contains(tile) else { return }
            action = "riichi"
        } else {
            guard turn.discard.contains(tile) else { return }
            action = "discard"
        }
        await sendAct(action, tiles: [tile], turn: turn, matchID: current.id, expectedSeq: current.seq ?? turn.seq)
    }

    /// 리치 무장 — 이 결정의 `riichi` 선택지가 있을 때만. 무장 뒤에는 `my_decision.riichi` 의 id 만 고를 수 있다.
    package func armRiichi() {
        guard case .turn(let turn)? = myDecision, !turn.riichi.isEmpty else { return }
        if chiChoicesOpen { chiChoicesOpen = false }
        if kanChoicesOpen { kanChoicesOpen = false }
        if !riichiArmed { riichiArmed = true }
    }

    package func cancelRiichi() {
        if riichiArmed { riichiArmed = false }
    }

    package func declareTsumo() async {
        if showsPractice {
            if let turn = practiceTurn, turn.tsumo { practiceAct(.tsumo) }
            return
        }
        guard !isWorking, let (_, current, turn) = serverTurn, turn.tsumo else { return }
        await sendAct("tsumo", tiles: [], turn: turn, matchID: current.id, expectedSeq: current.seq ?? turn.seq)
    }

    package func declareKyuushu() async {
        if showsPractice {
            if let turn = practiceTurn, turn.kyuushu { practiceAct(.kyuushu) }
            return
        }
        guard !isWorking, let (_, current, turn) = serverTurn, turn.kyuushu else { return }
        await sendAct("kyuushu", tiles: [], turn: turn, matchID: current.id, expectedSeq: current.seq ?? turn.seq)
    }

    /// 암깡(4장 id 묶음). 빈 배열이면: 후보가 하나뿐이면 그것을, 깡 후보(암깡 + 가깡)가 둘 이상이면 고르기를 펼친다.
    package func ankan(_ tiles: [MahjongTile]) async {
        if showsPractice {
            if let turn = practiceTurn, let chosen = chooseAnkan(tiles, turn: turn) {
                practiceAct(.ankan(turn.ankan.first { $0.sorted() == chosen } ?? chosen))
            }
            return
        }
        guard !isWorking, let (_, current, turn) = serverTurn, let chosen = chooseAnkan(tiles, turn: turn) else { return }
        await sendAct("ankan", tiles: chosen, turn: turn, matchID: current.id, expectedSeq: current.seq ?? turn.seq)
    }

    /// 암깡 묶음 고르기(서버·연습 같은 규칙) — 고를 것이 둘 이상이면 고르기를 펼치고 nil.
    func chooseAnkan(_ tiles: [MahjongTile], turn: MahjongDecision.Turn) -> [MahjongTile]? {
        var chosen = tiles.sorted()
        if chosen.isEmpty {
            if turn.ankan.count + turn.kakan.count > 1 {
                if riichiArmed { riichiArmed = false }
                if !kanChoicesOpen { kanChoicesOpen = true }
                return nil
            }
            guard turn.ankan.count == 1, let only = turn.ankan.first else { return nil }
            chosen = only.sorted()
        }
        guard turn.ankan.contains(where: { $0.sorted() == chosen }) else { return nil }
        return chosen
    }

    /// 연습판의 지금 내 차례 결정(엔진).
    var practiceTurn: MahjongDecision.Turn? {
        guard showsPractice, case .turn(let turn)? = practice?.payload.myDecision else { return nil }
        return turn
    }

    /// 가깡(더할 패 id).
    package func kakan(_ tile: MahjongTile) async {
        if showsPractice {
            if kanChoicesOpen { kanChoicesOpen = false }
            if let turn = practiceTurn, turn.kakan.contains(tile) { practiceAct(.kakan(tile)) }
            return
        }
        guard !isWorking, let (_, current, turn) = serverTurn, turn.kakan.contains(tile) else { return }
        await sendAct("kakan", tiles: [tile], turn: turn, matchID: current.id, expectedSeq: current.seq ?? turn.seq)
    }

    /// act 한 번 — 장부(보낼 때) · 잠금 · 요청 표 · 요청 마감 · 응답 처리.
    func sendAct(
        _ action: String, tiles: [MahjongTile], turn: MahjongDecision.Turn, matchID: String, expectedSeq: Int
    ) async {
        guard host?.session != nil else { return }
        noteOwnsMatch(matchID)
        actionToken &+= 1
        let token = actionToken
        isWorking = true
        if kanChoicesOpen { kanChoicesOpen = false }
        let generation = resetGeneration
        defer { if generation == resetGeneration, token == actionToken, isWorking { isWorking = false } }
        let ticket = issueTicket()
        let seconds = requestDeadlineSeconds(deadlineMs: turn.deadlineMs)
        let result = await performWithin(seconds, {
            try await $0.mahjongAct(
                accessToken: $1, matchID: matchID, expectedSeq: expectedSeq, action: action, tiles: tiles)
        })
        await handleDecisionResponse(result, action: .act, ticket: ticket, matchID: matchID)
    }

    /// 결정 동작(act·call·back) 응답 한 곳. nil(마감·취소)이면 아무것도 바꾸지 않는다 — 다음 state 가 진실이다.
    func handleDecisionResponse(
        _ result: Result<MahjongActionResponse, any Error>?, action: MahjongNoticeText.Action, ticket: Int, matchID: String
    ) async {
        guard let result else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            writeRevision &+= 1             // 이 응답보다 먼저 나간 로비·state 는 잔액·진행 판 id 를 덮지 않는다
            noteServerClock(response.serverNowMs)
            if response.status == .unsupportedClient {
                noteUpdateRequired()
                return
            }
            setNotice(MahjongNoticeText.status(response.status, for: action, need: response.need, have: response.have))
            if response.status == .notFound {
                matchNotFound(matchID)
                return
            }
            if let state = response.state {
                if applyState(state, requestedSince: 0, ticket: ticket, predatesWrite: false) == .needsFull {
                    await refreshMatch(id: matchID)
                }
            } else if response.status != .ok {
                await refreshMatch(id: matchID)
            }
        }
    }

    /// 판 중 [나가기] = 자리 비움(카드 ⑨ 답 — 기권 아님). 판은 자동으로 끝까지, 장부는 그대로 둔다.
    package func leaveTable() async {
        guard !showsPractice, let current = match?.match, current.matchStatus == .active, !isAwayHere else { return }
        let id = current.id
        await runRoomAction(.leave) { try await $0.mahjongLeave(accessToken: $1, matchID: id) }
    }

    /// [돌아왔어요]. 나가기 뒤 10초 안이면 `too_fast` → "잠시 뒤에 다시 눌러 주세요".
    package func comeBack() async {
        if showsPractice {
            practiceComeBack()
            return
        }
        guard !isWorking, host?.session != nil, let payload = match, let current = payload.match,
              current.matchStatus == .active else { return }
        let id = current.id
        noteOwnsMatch(id)
        actionToken &+= 1
        let token = actionToken
        isWorking = true
        let generation = resetGeneration
        defer { if generation == resetGeneration, token == actionToken, isWorking { isWorking = false } }
        let ticket = issueTicket()
        let deadline: Double? = {
            switch payload.myDecision {
            case .turn(let turn)?: return turn.deadlineMs
            case .call(let call)?: return call.deadlineMs
            case nil: return nil
            }
        }()
        let result = await performWithin(requestDeadlineSeconds(deadlineMs: deadline), {
            try await $0.mahjongBack(accessToken: $1, matchID: id)
        })
        await handleDecisionResponse(result, action: .back, ticket: ticket, matchID: id)
    }

    /// 반응(⑬ — 2초 쿨다운 too_fast 는 조용히 버린다).
    package func sendReaction(_ key: String) async {
        guard !showsPractice, host?.session != nil, let current = match?.match, current.matchStatus == .active else { return }
        let id = current.id
        noteOwnsMatch(id)
        let ticket = issueTicket()
        guard let result = await perform({ try await $0.mahjongReact(accessToken: $1, matchID: id, key: key) }),
              case .success(let response) = result else { return }
        noteServerClock(response.serverNowMs)
        if let state = response.state { applyState(state, requestedSince: 0, ticket: ticket, predatesWrite: false) }
    }
}
