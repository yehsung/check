import Foundation

// 아잉 큐브 스토어 — v2 자리(설계서 v2 §2.4): 판 배치 읽기 · 묶음 위치 이동 · 하트비트 · 의도적 이탈 · 이모티콘 반응 ·
// 뽑기 사건 · 받침대 자리 로컬 저장. 규약은 RummyStore.swift 머리말 ⑪~⑭.

/// 의도적 이탈의 계기(기록용 — 서버엔 같은 `rummy_leave` 다).
package enum RummyExitReason: String, Sendable {
    case windowClosed = "window_closed"
    case appQuit = "app_quit"
    case signOut = "sign_out"
}

/// 내 랙에 새로 들어온 타일 한 장(편집기 로컬 id · 면 · 받침대 자리).
package struct RummyDrawnTile: Equatable, Hashable, Sendable {
    package let tileID: Int
    package let face: RummyFace
    package let slot: RummyRackSlot

    package init(tileID: Int, face: RummyFace, slot: RummyRackSlot) {
        self.tileID = tileID
        self.face = face
        self.slot = slot
    }
}

/// 뽑기 사건(모션 계기). `serial` 은 스토어 안에서 1 부터 오른다.
package struct RummyDrawEvent: Equatable, Sendable {
    package let serial: Int
    package let tiles: [RummyDrawnTile]
}

/// 반응 하나. `id` 는 스토어 안에서 오르는 번호(ForEach 용), `receivedAt` 은 기기 시계(말풍선 2.5초 기준).
package struct RummyReactionEvent: Equatable, Hashable, Sendable, Identifiable {
    package let id: Int
    package let seatNo: Int
    package let sticker: AingSticker
    package let isMine: Bool
    package let receivedAt: Date
}

/// `continuation` 을 한 번만 깨운다(이탈 경주 — 서버 답 vs 2초).
@MainActor
private final class RummyExitGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

extension RummyStore {
    // MARK: - 판 배치 읽기

    /// 확정 판(`match.table`)의 배치. 빈 자리는 결정적 자동 배치로 채운다(모든 기기가 같다). 판이 없으면 빈 배치.
    package var confirmedLayout: RummyTableLayout {
        guard let match else { return .empty }
        return RummyTableLayout(sets: match.table ?? [], layout: match.tableLayout)
    }

    /// 남의 차례면 그 사람 작업 판의 배치(`otherDraft` 의 짝). 없으면 nil(→ `confirmedLayout`).
    package var otherDraftLayout: RummyTableLayout? {
        guard let sets = otherDraft else { return nil }
        return RummyTableLayout(sets: sets, layout: match?.draft?.layout)
    }

    /// v2 묶음 통째 위치 이동(내 차례만 — 배치도 작업 상태라 서버로 간다). 판 좌표 왼쪽 위, 가장 가까운 빈자리로 스냅.
    package func moveSet(_ setIndex: Int, to point: RummyPoint) {
        guard var working = editor, isMyTurn, working.moveSet(setIndex, to: point), editor != working else { return }
        editor = working
        setNotice(nil)
        scheduleDraft()
    }

    // MARK: - 하트비트(머리말 ⑫)

    /// phase 가 room·playing 이면 그 판의 하트비트를 돌리고, 아니면 멈춘다. `refreshPhase` 가 늘 부른다.
    func updateHeartbeat() {
        let wanted: UUID? = heartbeatEnabled && host?.session != nil && (phase == .room || phase == .playing)
            ? match?.id : nil
        guard wanted != heartbeatMatchID else { return }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeatMatchID = wanted
        guard let matchID = wanted else { return }
        let generation = resetGeneration
        heartbeatTask = Task { @MainActor [weak self] in
            while true {
                let wait = self?.heartbeatSeconds ?? RummyStore.heartbeatDefaultSeconds
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled, generation == self.resetGeneration,
                      self.heartbeatMatchID == matchID else { return }
                await self.heartbeatTick(matchID: matchID)
            }
        }
    }

    /// 하트비트 한 번. 자리가 없어졌으면(`not_found`) 따라잡기 조회를 건다.
    package func heartbeatTick(matchID: UUID) async {
        guard host?.session != nil else { return }
        guard let result = await perform({ try await $0.rummyHeartbeat(accessToken: $1, matchID: matchID) }) else { return }
        switch result {
        case .success(let response):
            noteServerNow(response.serverNowMs)
            switch response.status {
            case .ok: break
            case .notFound: requestSync()
            case .unsupportedClient: noteUpdateRequired()
            default: Self.logger.notice("heartbeat refused status=\(response.status.rawValue, privacy: .public)")
            }
        case .failure(let error):
            if isSchemaMissing(error) { Self.logger.notice("heartbeat missing on server") }
        }
    }

    // MARK: - 의도적 이탈(머리말 ⑫)

    /// 창 닫기·앱 종료·로그아웃. 방(forming)이면 방 나가기(방장이면 방 닫기), 판(active)이면 **즉시 기권**(`rummy_leave`).
    /// 서버 답을 최대 `exitLeaveLimitSeconds`(2초) 기다린다. 답과 무관하게 이 기기에선 판을 접는다(하트비트도 멈춘다) —
    /// 서버에 못 닿았으면 90초 끊김 기권이 마무리한다. 반환: 서버가 나감을 확인했는가(끝난 판·판 없음은 true).
    /// `isWorking` 과 무관하게 돈다(다른 동작이 비행 중이어도 나간다).
    @discardableResult
    package func leaveForExit(reason: RummyExitReason) async -> Bool {
        guard let current = match, Self.isUnsettled(current.status), host?.session != nil else { return true }
        let matchID = current.id
        let limit = Self.exitLeaveLimitSeconds
        Self.logger.notice("exit leave reason=\(reason.rawValue, privacy: .public)")
        let confirmed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = RummyExitGate(continuation)
            Task { @MainActor [weak self] in
                guard let self,
                      let result = await self.perform({ try await $0.rummyLeave(accessToken: $1, matchID: matchID) })
                else { gate.resume(false); return }
                guard case .success(let response) = result else { gate.resume(false); return }
                self.noteServerNow(response.serverNowMs)
                // not_found = 이미 자리가 없다(나간 것과 같다).
                gate.resume(response.status == .ok || response.status == .notFound)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(limit))
                gate.resume(false)
            }
        }
        dismissedMatchIDs.insert(matchID)
        matchRevision &+= 1
        if activeMatchID == matchID { activeMatchID = nil }
        if match?.id == matchID { clearMatch() }
        return confirmed
    }

    /// 방 손님의 **묻지 않는** 이탈(창 닫기 — `RummyCloseDecision.leaveRoom`). 들고 있는 것은 방(forming)이어도 그새 방장이
    /// 시작했으면(시작 신호가 이 기기에 닿기 전) `rummy_leave` 는 **판 기권**이다 — 묻지도 않고 판돈을 잃게 된다.
    /// 그래서 먼저 그 방 state 를 한 번 읽는다(상한 `exitLeaveLimitSeconds`). 판이 시작돼 내 자리가 playing 이면 나가지 않고
    /// 그 state 를 든다(판 시작 알림이 창을 다시 띄우고, 거기서 닫으면 기권 확인이 뜬다). 아직 방이거나 못 읽었으면 나간다.
    /// 반환: 나갔으면 `leaveForExit` 의 답, 시작된 판을 들고 남았으면 false.
    @discardableResult
    package func leaveRoomForExit(reason: RummyExitReason) async -> Bool {
        guard let current = match, current.status == .forming, host?.session != nil else {
            return await leaveForExit(reason: reason)
        }
        let roomID = current.id
        let ticket = issueTicket()
        let limit = Self.exitLeaveLimitSeconds
        let fetched = await withCheckedContinuation { (continuation: CheckedContinuation<RummyMatchState?, Never>) in
            let gate = RummyExitGate(continuation)
            Task { @MainActor [weak self] in
                guard let self,
                      let result = await self.perform({ try await $0.rummyState(accessToken: $1, matchID: roomID) }),
                      case .success(let response) = result, response.status == .ok
                else { gate.resume(nil); return }
                self.noteServerNow(response.serverNowMs)
                gate.resume(response.state)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(limit))
                gate.resume(nil)
            }
        }
        if let state = fetched, state.id == roomID, state.status == .active, match?.id == roomID,
           mySeat(in: state)?.state == .playing {
            Self.logger.notice("exit leave skipped: room already started")
            applyState(state, ticket: ticket)
            return false
        }
        return await leaveForExit(reason: reason)
    }

    // MARK: - 이모티콘 반응(머리말 ⑬)

    /// 지금 반응을 보낼 수 있는가(판·방이 있고 쿨다운이 지났다). 버튼 흐리기용.
    package func canReact(at date: Date) -> Bool {
        match != nil && date.timeIntervalSince(lastReactionSentAt) >= Self.reactionCooldownSeconds
    }

    /// 반응 보내기. 쿨다운(2초) 안이거나 판이 없으면 false(아무것도 안 한다). 내 말풍선은 바로 낸다.
    @discardableResult
    package func sendReaction(_ sticker: AingSticker) -> Bool {
        guard let current = match, host?.session != nil else { return false }
        let now = clock()
        guard canReact(at: now) else { return false }
        lastReactionSentAt = now
        let matchID = current.id
        let key = sticker.rawValue
        if let seat = Self.mySeat(in: current, me: myUserID)?.seatNo ?? current.mySeatNo {
            pendingOwnReactions.append((key, now))
            emitReaction(seatNo: seat, sticker: sticker, isMine: true)
        }
        Task { [weak self] in
            guard let self,
                  let result = await self.perform({ try await $0.rummyReact(accessToken: $1, matchID: matchID, key: key) })
            else { return }
            guard case .success(let response) = result else { return }
            self.noteServerNow(response.serverNowMs)
            if response.status != .ok {
                // 메아리가 안 온다 — 기다리던 것을 걷는다.
                if let index = self.pendingOwnReactions.firstIndex(where: { $0.key == key }) {
                    self.pendingOwnReactions.remove(at: index)
                }
                Self.logger.notice("react refused status=\(response.status.rawValue, privacy: .public)")
            }
        }
        return true
    }

    /// state 의 `reactions` 에서 처음 보는 것만 낸다(오래된 것부터). 모르는 키는 버린다. 내 것의 메아리는 한 번 삼킨다.
    func noteReactions(in state: RummyMatchState) {
        let now = clock()
        pendingOwnReactions.removeAll { now.timeIntervalSince($0.at) > Self.reactionEchoSeconds }
        guard let reactions = state.reactions, !reactions.isEmpty else { return }
        let mine = Self.mySeat(in: state, me: myUserID)?.seatNo ?? state.mySeatNo
        let prefix = state.id.uuidString.lowercased()
        for reaction in reactions.reversed() {
            guard let seat = reaction.seatNo, let sticker = reaction.sticker else { continue }
            let key = "\(prefix)#\(seat)#\(sticker.rawValue)#\(Int64(reaction.atMs ?? 0))"
            guard seenReactionKeys.insert(key).inserted else { continue }
            if seat == mine, let index = pendingOwnReactions.firstIndex(where: { $0.key == sticker.rawValue }) {
                pendingOwnReactions.remove(at: index)
                continue
            }
            emitReaction(seatNo: seat, sticker: sticker, isMine: seat == mine)
        }
    }

    func emitReaction(seatNo: Int, sticker: AingSticker, isMine: Bool) {
        reactionSerial &+= 1
        let event = RummyReactionEvent(id: reactionSerial, seatNo: seatNo, sticker: sticker, isMine: isMine, receivedAt: clock())
        var feed = reactionFeed
        feed.append(event)
        if feed.count > Self.reactionFeedLimit { feed.removeFirst(feed.count - Self.reactionFeedLimit) }
        reactionFeed = feed
        onReaction?(event)
    }

    // MARK: - 뽑기 사건(머리말 ⑬)

    /// 같은 판의 앞 편집기와 새 편집기를 대어 새로 들어온 면(다중집합 차)을 찾고, 그 타일(앞 자리 목록에 없던 자리)을 알린다.
    func noteDrawn(previous: RummyTurnEditor, fresh: RummyTurnEditor, entries: [RummyRackEntry]) {
        var gained: [RummyFace: Int] = [:]
        for face in fresh.startRackFaces { gained[face, default: 0] += 1 }
        for face in previous.startRackFaces { gained[face, default: 0] -= 1 }
        guard gained.values.contains(where: { $0 > 0 }) else { return }
        let known = Set(entries)
        var tiles: [RummyDrawnTile] = []
        // 새 타일은 마지막 빈자리로 갔다 — 뒤에서부터 고른다(같은 면이 둘이면 앞 자리 목록에 없는 쪽).
        for tile in fresh.rack.reversed() {
            guard (gained[tile.face] ?? 0) > 0, let slot = fresh.rackLayout.slot(of: tile.id),
                  !known.contains(RummyRackEntry(face: tile.face, slot: slot)) else { continue }
            gained[tile.face, default: 0] -= 1
            tiles.insert(RummyDrawnTile(tileID: tile.id, face: tile.face, slot: slot), at: 0)
        }
        guard !tiles.isEmpty else { return }
        drawSerial &+= 1
        let event = RummyDrawEvent(serial: drawSerial, tiles: tiles)
        lastDraw = event
        onTileDrawn?(event)
    }

    // MARK: - 받침대 자리 로컬 저장(머리말 ⑭)

    package nonisolated static func rackDefaultsKey(matchID: UUID) -> String {
        "rummy.rack.v2.\(matchID.uuidString.lowercased())"
    }

    /// 지금 편집기의 받침대 자리(판에 나간 타일은 나간 자리로 돌린 모양)를 판 id 키로 저장한다.
    func saveRack() {
        guard let defaults = rackDefaults, let editor, let matchID = editorKey?.matchID,
              let data = try? JSONEncoder().encode(editor.restoredRackEntries) else { return }
        defaults.set(data, forKey: Self.rackDefaultsKey(matchID: matchID))
    }

    func loadRackEntries(matchID: UUID) -> [RummyRackEntry]? {
        guard let data = rackDefaults?.data(forKey: Self.rackDefaultsKey(matchID: matchID)) else { return nil }
        return try? JSONDecoder().decode([RummyRackEntry].self, from: data)
    }

    func forgetRack(matchID: UUID) {
        rackDefaults?.removeObject(forKey: Self.rackDefaultsKey(matchID: matchID))
    }
}
