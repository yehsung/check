import Foundation

// 아잉 마작 스토어 — 로비 · 방(forming) · 초인종 · 순위(SPEC §4.5).
// 초인종 합치기(⑥ — 큐브 `RummyStoreLobby.swift:9-37` 꼴, V2-02): 도는 중에 온 신호는 끝난 뒤 정확히 한 번 더.
// 서버 `match`(방 포함)가 있으면 그 판 state(`p_since_seq = 내 seq`), 없으면 로비 — **연습 여부와 무관**(CC-02).

extension MahjongStore {
    // MARK: 로비 적용

    /// 로비 응답 하나를 넣는다. `unsupported_client` 는 Availability 만 바꾼다(PGRST202 `.serverMissing` 은 호출 경로 몫).
    package func applyLobby(_ response: MahjongLobbyResponse) {
        noteServerClock(response.serverNowMs)
        switch response.status {
        case .ok:
            if availability != .available { availability = .available }
        case .unsupportedClient:
            if availability != .updateRequired { availability = .updateRequired }
            return
        default:
            return
        }
        users = response.users ?? []
        publicRooms = response.publicRooms ?? []
        let arriving = response.invites ?? []
        invites = arriving
        if let me = response.me {
            // C2: ⓓ predatesWrite 면 잔액·active_match_id 를 덮지 않는다(판이 됐다는 판정에는 쓴다, VR-01).
            if let record = me.record { self.record = record }
            if let balance = me.rubyBalance { rubyBalance = balance }
            lobbyRoom = me.room
            activeMatchID = me.activeMatchId
        }
        // 처음 본 초대만 알린다(받은 초대는 장부와 무관 — 모든 기기).
        for room in visibleInvites where seenInviteIDs.insert(room.id).inserted {
            onInviteArrived?(room)
        }
        recomputePhase()
    }

    // MARK: 방 동작

    /// 방 만들기(`selectedStake` · `selectedPublic` · `selectedFormat`). ok 면 장부에 적는다.
    package func createRoom() async {
        // C2: mahjong_create → noteOwnsMatch · applyState.
    }

    /// 방에 초대(방장만).
    package func invite(userID: UUID) async {
        // C2: mahjong_invite → notice MahjongNoticeText.invited.
        _ = userID
    }

    /// 초대·공개 방 참가. ok 면 장부에 적는다.
    package func join(roomID: UUID) async {
        // C2: mahjong_join → noteOwnsMatch · applyState.
        _ = roomID
    }

    package func decline(roomID: UUID) async {
        // C2: mahjong_decline.
        _ = roomID
    }

    /// 방에서 나가기(방장이면 방 닫기). 판 중 [나가기]는 `leaveTable()`.
    package func leaveRoom() async {
        // C2: mahjong_leave(forming) → dropOwnership.
    }

    /// 방장 [시작](넷이 모였을 때). `seats_dropped` 는 빠진 까닭 문구, 내가 빠졌으면 장부에서 걷는다.
    package func start() async {
        // C2: mahjong_start → noteOwnsMatch · applyState.
    }

    // MARK: 계기(초인종 · 실시간 · 깨어남 · 메뉴)

    /// 실시간 초인종 `'mahjong'`(내용 없음 — `{v, m, s}`).
    package func handleSignal() {
        // C2: 합치기 → match 있으면 그 판 state, 없으면 로비.
    }

    /// 실시간 채널이 (다시) 붙었다 — 놓친 초인종을 메우려 한 번 읽는다.
    package func realtimeDidJoin() {
        // C2.
    }

    /// 맥이 깨어났다 — 판·방·로비를 한 번 읽는다.
    package func systemDidWake() {
        // C2.
    }

    /// 메뉴·팝오버가 열렸다 — 로비가 오래됐으면 읽는다(초대 점·배너의 신선도).
    package func refreshLobbyIfStale() {
        // C2.
    }

    /// 순위(`rankingEnabled` 일 때만 — 60초 폴링 ③).
    package func refreshRanking() async {
        // C2: mahjong_ranking → ranking · rankingUnavailable.
    }
}
