import Foundation

// 아잉 마작 스토어 — 로비 · 방(forming) · 초인종 · 순위(SPEC §4.5).
// 초인종 합치기(⑥ — 큐브 `RummyStoreLobby.swift:9-37` 꼴, V2-02): 도는 중에 온 신호는 끝난 뒤 정확히 한 번 더.
// 서버 `match`(방 포함)가 있으면 그 판 state(`p_since_seq = 내 seq`), 없으면 로비 — **연습 여부와 무관**(CC-02).
// ⓓ `writeRevision`: 쓰기 응답보다 먼저 나간 로비는 잔액·`active_match_id` 를 덮지 않는다 — 단 '방이 판이 됐다'는 판정에는 쓴다(VR-01).

extension MahjongStore {
    // MARK: 로비 조회

    /// 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 **한 번 더** 읽는다(`lobbyAgain`).
    /// 로비가 내 진행 판·방을 말하는데 들고 있지 않으면 그 판을 읽어 세운다.
    func refreshLobby() async {
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
            let writes = writeRevision
            guard let result = await perform({ try await $0.mahjongLobby(accessToken: $1) }) else { return }
            switch result {
            case .success(let response):
                applyLobby(response, predatesWrite: writes != writeRevision)
                guard response.status == .ok else { break }
                // 쓰기보다 먼저 나간 응답이라 `activeMatchID` 를 안 덮었어도, 그 순간 판이 서 있었다는 사실은 쓴다(VR-01).
                let active = response.me?.activeMatchId?.lowercased()
                let held = match?.match
                if let active, held?.id != active || held?.matchStatus != .active {
                    // 검증 V3-03 · V2-01: 서버가 '지금 앉아 있는 진행 판'이라 말하는 id 는 접은 기록(가드 (a))을 걷는다 — 다른 맥에서
                    //   나갔다 다시 들어가 선 판 · [나가기]와 [시작]이 겹쳐 not_found 로 접은 판. 접는 것은 방(forming)과 끝난 판뿐이라
                    //   진행 판을 걷어도 늦은 방 응답은 가드 ⓔ 가 버린다.
                    dismissedMatchIDs.remove(active)
                    await refreshMatch(id: active)
                } else if active == nil, held == nil || held?.matchStatus.isTerminal == true,
                          let room = response.me?.room?.id.uuidString.lowercased(), held?.id != room {
                    // 다른 기기에서 만든·참가한 방 — 그 방을 세운다(장부엔 안 적는다).
                    await refreshMatch(id: room)
                }
            case .failure(let error):
                if isSchemaMissing(error) { noteServerMissing() }
            }
        } while lobbyAgain && generation == resetGeneration
    }

    /// 로비 응답 하나를 넣는다(픽스처 문 — 쓰기 뒤 판정 없이 지금 것으로 친다).
    package func applyLobby(_ response: MahjongLobbyResponse) {
        applyLobby(response, predatesWrite: false)
    }

    /// `predatesWrite` — 이 응답은 그 뒤에 받은 쓰기 응답보다 **먼저** 나갔다(ⓓ). 잔액·진행 판 id 는 덮지 않는다.
    func applyLobby(_ response: MahjongLobbyResponse, predatesWrite: Bool) {
        noteServerClock(response.serverNowMs)
        switch response.status {
        case .ok:
            if availability != .available { availability = .available }
        case .unsupportedClient:
            noteUpdateRequired()
            return
        case .unauthorized:
            setNotice(MahjongNoticeText.signInAgain)
            return
        default:
            return
        }
        if users != (response.users ?? []) { users = response.users ?? [] }
        if publicRooms != (response.publicRooms ?? []) { publicRooms = response.publicRooms ?? [] }
        let arriving = response.invites ?? []
        if invites != arriving { invites = arriving }
        if let stakes = response.stakes, let first = stakes.first, !stakes.contains(selectedStake.rawValue) {
            selectedStake = MahjongStake(rawValue: first) ?? selectedStake
        }
        if let me = response.me {
            if let record = me.record, self.record != record { self.record = record }
            lobbyRoom = me.room
            if !predatesWrite {
                applyRuby(me.rubyBalance)
                activeMatchID = me.activeMatchId?.lowercased()
            }
        }
        // 처음 본 초대만 알린다(받은 초대는 장부와 무관 — 모든 기기). 차단한 방장의 초대는 본 것으로만 적는다.
        for room in invites where seenInviteIDs.insert(room.id).inserted {
            if visibleInvites.contains(where: { $0.id == room.id }) { onInviteArrived?(room) }
        }
        recomputePhase()
    }

    // MARK: 방 동작

    /// 방 만들기(`selectedStake` · `selectedPublic` · `selectedFormat`). ok 면 장부에 적는다.
    package func createRoom() async {
        guard !isWorking, host?.session != nil else { return }
        let stake = selectedStake.rawValue, isPublic = selectedPublic, format = selectedFormat.rawValue
        await runRoomAction(.create) { try await $0.mahjongCreate(accessToken: $1, stake: stake, isPublic: isPublic, format: format) }
    }

    /// 방에 초대(방장만).
    package func invite(userID: UUID) async {
        guard !isWorking, let room = match?.match, room.matchStatus == .forming else { return }
        let roomID = room.id, target = userID.uuidString.lowercased()
        await runRoomAction(.invite) { try await $0.mahjongInvite(accessToken: $1, matchID: roomID, userID: target) }
    }

    /// 초대·공개 방 참가. ok 면 장부에 적는다.
    package func join(roomID: UUID) async {
        guard !isWorking else { return }
        let id = roomID.uuidString.lowercased()
        await runRoomAction(.join) { try await $0.mahjongJoin(accessToken: $1, matchID: id) }
    }

    package func decline(roomID: UUID) async {
        guard !isWorking else { return }
        let id = roomID.uuidString.lowercased()
        // 이 기기에서 답했다 — 카드를 걷는다(응답이 늦어도 다시 안 뜬다).
        invites.removeAll { $0.id == roomID }
        await runRoomAction(.decline) { try await $0.mahjongDecline(accessToken: $1, matchID: id) }
    }

    /// 방에서 나가기(방장이면 방 닫기). 판 중 [나가기]는 `leaveTable()`.
    package func leaveRoom() async {
        guard !isWorking, let room = match?.match, room.matchStatus == .forming else { return }
        let id = room.id
        await runRoomAction(.leave) { try await $0.mahjongLeave(accessToken: $1, matchID: id) }
    }

    /// 방장 [시작](넷이 모였을 때). `seats_dropped` 는 빠진 까닭 문구, 내가 빠졌으면 장부에서 걷는다.
    package func start() async {
        guard !isWorking, canStart, let room = match?.match else { return }
        let id = room.id
        await runRoomAction(.start) { try await $0.mahjongStart(accessToken: $1, matchID: id) }
    }

    /// 방 동작 하나 — 잠금(`isWorking`) · 요청 표 · ⓓ · 장부(만들기·참가·시작 ok) · 문구 · 실린 state 적용.
    func runRoomAction(
        _ action: MahjongNoticeText.Action,
        _ operation: @escaping @Sendable (SupabaseWorkService, String) async throws -> MahjongActionResponse
    ) async {
        guard host?.session != nil else { return }
        actionToken &+= 1
        let token = actionToken
        isWorking = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration, token == actionToken, isWorking { isWorking = false } }
        let ticket = issueTicket()
        guard let result = await perform(operation) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            writeRevision &+= 1             // 이 응답보다 먼저 나간 로비·state 는 잔액·진행 판 id 를 덮지 않는다
            noteServerClock(response.serverNowMs)
            handleRoomResponse(response, action: action, ticket: ticket)
        }
    }

    func handleRoomResponse(_ response: MahjongActionResponse, action: MahjongNoticeText.Action, ticket: Int) {
        switch response.status {
        case .unsupportedClient:
            noteUpdateRequired()
            return
        case .seatsDropped:
            let me = myUserID
            if response.reasons?.keys.contains(where: { $0.lowercased() == me }) == true
                || response.dropped?.contains(where: { $0.lowercased() == me }) == true {
                setNotice(MahjongNoticeText.droppedAtStart)
                if let id = match?.match?.id { leaveHeldRoom(id) }
                return
            }
            setNotice(MahjongNoticeText.droppedOthers(reasons: response.reasons.map { Array($0.values) } ?? []))
        case .ok:
            setNotice(action == .invite ? MahjongNoticeText.invited : nil)
        default:
            setNotice(MahjongNoticeText.status(response.status, for: action, need: response.need, have: response.have))
        }
        let state = response.state
        let id = state?.match?.id ?? response.matchId?.lowercased()
        if response.status == .ok, let id {
            switch action {
            case .create, .join, .start: noteOwnsMatch(id)
            case .leave:
                if state?.match?.matchStatus != .active { dropOwnership(id) }
            default: break
            }
        }
        // 나갔던 방에 다시 참가했다 — 그 방의 접은 기록을 지운다(안 지우면 새 참가 응답까지 가드 (a)가 버린다).
        if response.status == .ok, action == .create || action == .join, let id { dismissedMatchIDs.remove(id) }
        if let state {
            applyState(state, requestedSince: 0, ticket: ticket, predatesWrite: false)
            if response.status == .ok, action == .leave, state.match?.matchStatus != .active, let id {
                leaveHeldRoom(id)
            }
        } else if response.status == .ok, action == .leave, let id = match?.match?.id {
            leaveHeldRoom(id)
        } else if response.status == .roomClosed || response.status == .notFound, action != .invite,
                  let held = match?.match, held.matchStatus == .forming, action != .create {
            leaveHeldRoom(held.id)
        }
        if response.status == .ok, action == .create || action == .join || action == .leave || action == .decline {
            Task { @MainActor [weak self] in await self?.refreshLobby() }
        } else if action == .leave, response.status == .notFound || response.status == .roomClosed {
            // 검증 V2-01: 방 [나가기]가 방장 [시작]과 겹치면 옛 서버는 not_found(state 없음)로 답했다 — 그 사이 판이 섰을 수 있으니
            //   로비로 진행 판을 한 번 묻는다(있으면 위 refreshLobby 가 접은 기록을 걷고 든다).
            Task { @MainActor [weak self] in await self?.refreshLobby() }
        }
    }

    /// 들고 있던 방을 내린다(나가기 ok · 닫힌 방). 그 방의 늦은 응답은 버린다(가드 (a)).
    func leaveHeldRoom(_ id: String) {
        dismissedMatchIDs.insert(id)
        dropOwnership(id)
        if match?.match?.id == id { match = nil }
        if lobbyRoom?.id.uuidString.lowercased() == id { lobbyRoom = nil }
        recomputePhase()
    }

    // MARK: 계기(초인종 · 실시간 · 깨어남 · 메뉴)

    /// 실시간 초인종 `'mahjong'`(내용 없음 — `{v, m, s}`).
    package func handleSignal() {
        requestSync()
    }

    /// 실시간 채널이 (다시) 붙었다 — 놓친 초인종을 메우려 한 번 읽는다.
    package func realtimeDidJoin() {
        requestSync()
    }

    /// 맥이 깨어났다 — 판·방·로비를 한 번 읽는다.
    package func systemDidWake() {
        guard host?.session != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncOnce()
            if self.match != nil { await self.refreshLobby() }
        }
    }

    /// 메뉴·팝오버가 열렸다 — 로비가 오래됐으면 읽는다(초대 점·배너의 신선도, 30초 스로틀).
    package func refreshLobbyIfStale() {
        guard host?.session != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuLobbyAt) >= Self.menuLobbyThrottleSeconds else { return }
        lastMenuLobbyAt = now
        Task { @MainActor [weak self] in await self?.refreshLobby() }
    }

    /// 순위(`rankingEnabled` 일 때만 — 60초 폴링 ③). 10판 미만이면 `me.rank` 는 null(서버 것 그대로).
    package func refreshRanking() async {
        guard rankingEnabled, host?.session != nil else { return }
        lastRankingRequestAt = clock()
        guard let result = await perform({ try await $0.mahjongRanking(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            noteServerClock(response.serverNowMs)
            if response.status == .ok {
                if ranking != response { ranking = response }
                if rankingUnavailable { rankingUnavailable = false }
            } else {
                if response.status == .unsupportedClient { noteUpdateRequired() }
                if !rankingUnavailable { rankingUnavailable = true }
            }
        case .failure(let error):
            if isSchemaMissing(error) { noteServerMissing() }
            if !rankingUnavailable { rankingUnavailable = true }
        }
    }
}
