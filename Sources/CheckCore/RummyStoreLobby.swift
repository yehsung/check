import Foundation

// 아잉 큐브 스토어 — 로비 · 초대 · 방 동작(만들기·초대·참가·거절·나가기·시작) · 순위 · 차단 거울.
// 규약은 RummyStore.swift 머리말 ①~⑩.

extension RummyStore {
    // MARK: - 로비

    /// 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 **한 번 더** 읽는다(합치기 — `refreshMatch` 의 `stateAgain` 과 같은 꼴).
    /// 앞 조회는 그 뒤에 생긴 초대를 모르므로, 그 사이 온 초인종을 버리면 배너·말풍선이 다음 계기까지 안 뜬다.
    package func refreshLobby() async {
        guard host?.session != nil else { return }
        if lobbyInFlight {
            lobbyAgain = true
            return
        }
        lobbyInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { lobbyInFlight = false } }
        repeat {
            lobbyAgain = false
            lastLobbyRequestAt = clock()
            let revision = matchRevision
            guard let result = await perform({ try await $0.rummyLobby(accessToken: $1) }) else { return }
            switch result {
            case .success(let response):
                await applyLobby(response, revision: revision)
            case .failure(let error):
                if isSchemaMissing(error) {
                    Self.logger.notice("lobby unavailable — rummy functions missing on server")
                    noteServerMissing()
                } else {
                    Self.logger.notice("lobby request failed")
                }
            }
        } while lobbyAgain && generation == resetGeneration
    }

    /// 로비 응답을 옮긴다. `revision` 은 그 요청을 낼 때의 `matchRevision` 이다(nil = 지금 것).
    package func applyLobby(_ response: RummyLobby, revision: Int? = nil) async {
        guard response.status == .ok else {
            Self.logger.notice("lobby refused status=\(response.status.rawValue, privacy: .public)")
            switch response.status {
            case .unsupportedClient: noteUpdateRequired()
            case .unauthorized: setNotice(RummyNoticeText.signInAgain)
            default: break
            }
            return
        }
        noteServerNow(response.serverNowMs)
        if availability != .available { availability = .available }
        rawLobby = response
        publishLobby()
        applyRuby(response.me?.rubyBalance)
        if let stakes = response.stakes, let first = stakes.first, !stakes.contains(selectedStake) {
            selectedStake = first
        }
        // 새 초대 — 방 id 마다 **한 번**. 차단한 방장의 초대는 알리지 않는다(본 것으로는 적는다).
        for room in response.invites ?? [] where !seenInviteIDs.contains(room.id) {
            seenInviteIDs.insert(room.id)
            guard !isHidden(room) else { continue }
            onInviteArrived?(room)
        }
        // 내 방·판.
        let mine = response.me?.activeMatchId ?? response.me?.room?.id
        activeMatchID = mine
        if let mine {
            guard !dismissedMatchIDs.contains(mine) else { return }
            // 같은 id 면 신호·폴링·따라잡기가 이미 그 판을 읽는다 — 단, 모르는 status 로 든 판은 여기서도 다시 읽는다.
            if match?.id != mine || match?.status == .finished || match?.status == .unknown {
                await refreshMatch(id: mine)
            }
        } else if let current = match, Self.isUnsettled(current.status),
                  (revision ?? matchRevision) == matchRevision {
            // 서버는 내 방·판이 없다고 한다 — 그 판을 직접 읽어 사정(닫힘·끝남·기권)을 안다. 지우지 않는다.
            await refreshMatch(id: current.id)
        }
    }

    /// 차단 거울을 거친 로비를 낸다(관찰자를 헛되게 깨우지 않게 같으면 대입하지 않는다).
    func publishLobby() {
        guard var shown = rawLobby else {
            if lobby != nil { lobby = nil }
            return
        }
        if !hiddenPeerIDs.isEmpty {
            shown.users = shown.users?.filter { !hiddenPeerIDs.contains($0.id) }
            shown.invites = shown.invites?.filter { !isHidden($0) }
            shown.publicRooms = shown.publicRooms?.filter { !isHidden($0) }
        }
        if lobby != shown { lobby = shown }
    }

    /// 차단한 사람이 방장이거나 자리에 낀 방인가.
    func isHidden(_ room: RummyRoom) -> Bool {
        guard !hiddenPeerIDs.isEmpty else { return false }
        if let host = room.host?.id, hiddenPeerIDs.contains(host) { return true }
        return room.seats?.contains { hiddenPeerIDs.contains($0.userId) } ?? false
    }

    // MARK: - 초대

    /// 메뉴바 점·배너.
    package var hasIncomingInvite: Bool { !incomingInvites.isEmpty }

    /// 받은 초대(최근 순, 서버 순서 그대로). 차단한 방장의 초대·지금 앉은 방은 뺀다.
    package var incomingInvites: [RummyRoom] {
        let rooms = lobby?.invites ?? []
        guard let current = match?.id else { return rooms }
        return rooms.filter { $0.id != current }
    }

    // MARK: - 방 동작

    /// `selectedStake`·`createPublic` 으로 방을 만든다.
    package func createRoom() {
        let stake = selectedStake
        let isPublic = createPublic
        runAction { store in
            let ticket = store.issueTicket()
            guard let result = await store.perform({
                try await $0.rummyCreate(accessToken: $1, stake: stake, isPublic: isPublic)
            }) else { return }
            switch result {
            case .success(let response):
                store.noteServerNow(response.serverNowMs)
                guard response.status == .ok, let id = response.matchId ?? response.state?.id else {
                    store.noteRefusal(response, action: .create)
                    return
                }
                store.setNotice(nil)
                store.matchRevision &+= 1
                store.activeMatchID = id
                store.dismissedMatchIDs.remove(id)
                if let state = response.state {
                    store.applyState(state, ticket: ticket)
                } else {
                    await store.refreshMatch(id: id)
                }
            case .failure(let error):
                store.noteActionFailure(error)
            }
        }
    }

    /// 방장이 사람을 골라 초대한다. 성공이면 방 state 를 다시 읽는다(초대 자리가 보인다).
    package func invite(_ userID: UUID) {
        guard let room = match, room.status == .forming else { return }
        let roomID = room.id
        runAction { store in
            let ticket = store.issueTicket()
            guard let result = await store.perform({
                try await $0.rummyInvite(accessToken: $1, matchID: roomID, userID: userID)
            }) else { return }
            switch result {
            case .success(let response):
                store.noteServerNow(response.serverNowMs)
                guard response.status == .ok else {
                    store.noteRefusal(response, action: .invite)
                    return
                }
                store.setNotice(RummyNoticeText.invited)
                if let state = response.state {
                    store.applyState(state, ticket: ticket)
                } else {
                    await store.refreshMatch(id: roomID)
                }
            case .failure(let error):
                store.noteActionFailure(error)
            }
        }
    }

    /// 초대 수락 또는 공개 방 참가.
    package func join(_ roomID: UUID) {
        runAction { store in
            let ticket = store.issueTicket()
            guard let result = await store.perform({ try await $0.rummyJoin(accessToken: $1, matchID: roomID) })
            else { return }
            switch result {
            case .success(let response):
                store.noteServerNow(response.serverNowMs)
                guard response.status == .ok else {
                    store.noteRefusal(response, action: .join)
                    // 닫혔거나 초대가 없어진 방 — 로비를 다시 읽어 그 카드를 걷는다.
                    if response.status == .roomClosed || response.status == .notInvited
                        || response.status == .roomFull || response.status == .notFound {
                        await store.refreshLobby()
                    }
                    return
                }
                store.setNotice(nil)
                store.matchRevision &+= 1
                store.activeMatchID = roomID
                store.dismissedMatchIDs.remove(roomID)
                if let state = response.state {
                    store.applyState(state, ticket: ticket)
                } else {
                    await store.refreshMatch(id: roomID)
                }
            case .failure(let error):
                store.noteActionFailure(error)
            }
        }
    }

    /// 받은 초대를 거절한다. 성공이면 그 카드를 곧바로 걷는다(다음 로비가 확인한다).
    package func decline(_ roomID: UUID) {
        runAction { store in
            guard let result = await store.perform({ try await $0.rummyDecline(accessToken: $1, matchID: roomID) })
            else { return }
            switch result {
            case .success(let response):
                store.noteServerNow(response.serverNowMs)
                if response.status == .ok {
                    store.setNotice(nil)
                    store.dropInvite(roomID)
                } else {
                    store.noteRefusal(response, action: .decline)
                    await store.refreshLobby()
                }
            case .failure(let error):
                store.noteActionFailure(error)
            }
        }
    }

    /// 방 나가기(방장이면 방이 닫힌다) / 판 기권. 끝난 판이면 결과 접기와 같다.
    package func leave() {
        guard let current = match else { return }
        if current.status == .finished {
            dismissResult()
            return
        }
        let matchID = current.id
        runAction { store in
            let ticket = store.issueTicket()
            guard let result = await store.perform({ try await $0.rummyLeave(accessToken: $1, matchID: matchID) })
            else { return }
            switch result {
            case .success(let response):
                store.noteServerNow(response.serverNowMs)
                guard response.status == .ok else {
                    store.noteRefusal(response, action: .leave)
                    if let state = response.state { store.applyState(state, ticket: ticket) }
                    return
                }
                store.setNotice(nil)
                store.dismissedMatchIDs.insert(matchID)
                store.matchRevision &+= 1
                if store.activeMatchID == matchID { store.activeMatchID = nil }
                if store.match?.id == matchID { store.clearMatch() }
                await store.refreshLobby()
            case .failure(let error):
                store.noteActionFailure(error)
            }
        }
    }

    /// 방장이 판을 시작한다. 빠진 자리가 있으면 시작하지 않고 방 state 를 다시 읽는다.
    package func startGame() {
        guard let room = match, room.status == .forming else { return }
        let roomID = room.id
        runAction { store in
            let ticket = store.issueTicket()
            guard let result = await store.perform({ try await $0.rummyStart(accessToken: $1, matchID: roomID) })
            else { return }
            switch result {
            case .success(let response):
                store.noteServerNow(response.serverNowMs)
                if response.status == .ok {
                    store.setNotice(nil)
                    if let state = response.state {
                        store.applyState(state, ticket: ticket)
                    } else {
                        await store.refreshMatch(id: roomID)
                    }
                    return
                }
                store.noteRefusal(response, action: .start)
                if let state = response.state {
                    store.applyState(state, ticket: ticket)
                } else if response.status == .seatsDropped {
                    await store.refreshMatch(id: roomID)
                }
            case .failure(let error):
                store.noteActionFailure(error)
            }
        }
    }

    /// 결과 화면 [로비로]. 그 판은 다시 끌려오지 않는다.
    package func dismissResult() {
        guard let current = match else { return }
        dismissedMatchIDs.insert(current.id)
        if activeMatchID == current.id { activeMatchID = nil }
        clearMatch()
        setNotice(nil)
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.refreshLobby() }
    }

    // MARK: - 순위

    package func refreshRanking() {
        guard rankingEnabled, host?.session != nil else { return }
        Task { [weak self] in await self?.loadRanking() }
    }

    package func loadRanking() async {
        guard rankingEnabled, host?.session != nil, !rankingInFlight else { return }
        rankingInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { rankingInFlight = false } }
        lastRankingRequestAt = clock()
        guard let result = await perform({ try await $0.rummyRanking(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            noteServerNow(response.serverNowMs)
            switch response.status {
            case .ok: if ranking != response { ranking = response }
            case .unsupportedClient: noteUpdateRequired()
            default: Self.logger.notice("ranking refused status=\(response.status.rawValue, privacy: .public)")
            }
        case .failure(let error):
            if isSchemaMissing(error) { noteServerMissing() }
        }
    }

    // MARK: - 차단 거울

    package func setHiddenPeers(_ ids: Set<UUID>) {
        guard hiddenPeerIDs != ids else { return }
        hiddenPeerIDs = ids
        publishLobby()
    }

    // MARK: - 내부

    /// 거절 응답 한 줄(문구는 `RummyNoticeText` 표). 버전 거절은 화면 전체를 '업데이트 필요' 로 바꾼다.
    func noteRefusal(_ response: RummyActionResponse, action: RummyNoticeText.Action) {
        Self.logger.notice(
            "\(action.rawValue, privacy: .public) refused status=\(response.status.rawValue, privacy: .public)")
        if response.status == .unsupportedClient {
            noteUpdateRequired()
            return
        }
        setNotice(RummyNoticeText.status(response.status, for: action))
    }

    /// 받은 초대 카드 하나를 걷는다(원본과 거울 둘 다).
    func dropInvite(_ roomID: UUID) {
        guard var raw = rawLobby, raw.invites?.contains(where: { $0.id == roomID }) == true else { return }
        raw.invites?.removeAll { $0.id == roomID }
        rawLobby = raw
        publishLobby()
    }

    /// 방·판을 내린다(편집기·작업 전송·마감 깨우기까지).
    package func clearMatch() {
        if match != nil { match = nil }
        if editor != nil { editor = nil }
        editorKey = nil
        editorSeq = nil
        lastSentDraft = nil
        cancelDraft()
        deadlineTask?.cancel()
        deadlineTask = nil
        deadlineWakeKey = nil
        refreshPhase()
    }
}
