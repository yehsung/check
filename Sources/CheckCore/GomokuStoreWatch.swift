import Foundation

// 오목 스토어의 **관전** 갈래(0.3.41) — 남의 진행 중인 판을 읽기 전용으로 본다.
//
// ── 관전은 판만이다 ──
// 서버 `gomoku_watch` 는 판·수순·남은 시간·두 사람·판돈만 준다(채팅 키 자체가 없다). 이 파일은 `gomoku_state` 를 **절대 부르지 않는다** —
// 참가자 게이트에 걸려 관전자는 not_found 만 받고, 참가자가 부른다 해도 응답에 대국자 채팅이 실려 온다. 관전 응답을 `applyState` 로도
// 넣지 않는다(my_color 부재로 .ignored 거나 대국 화면이 서 버린다) — 적용 경로는 아래 `applyWatch` 하나다.
//
// ── 주 스위치(C11) ──
// `spectatorFeaturesEnabled` 가 꺼져 있으면 진입·조회·폴링이 한 번도 안 돈다. 이 스토어는 폰(MobileAppModel)과 공용이라 기본이 꺼짐이고
// 맥 배선(CheckApp.wireGomoku)만 켠다.
//
// ── 세대(C13) ──
// `watchRuntime.watchGeneration` 이 관전 세대다. 진입(판 전환)·나가기·로그아웃·내 판이 서서 관전이 내려갈 때 오르고, 요청을 띄울 때 잡은
// 세대와 응답이 왔을 때의 세대가 다르면 버린다. `resetGeneration` 만 보면 창을 닫은 뒤 늦게 온 응답이 관전을 되살리고, A 판을 나가 B 판을
// 보는 사이 A 의 늦은 응답이 B 판을 한 틱 덮는다. 세대가 같아도 응답의 `match.id` 가 다르면 버린다(이중 자물쇠).
//
// ── 창이 안 보이면 요청이 없다(C14) ──
// **진행 중인** 관전 상태는 창을 닫거나 최소화해도 남고 **폴링만** 멈춘다 — `windowDidHide` 는 진행 중인 관전을 지우지 않는다(최소화에서도
// 오는 통지다). 다시 보이면 즉시 한 번 당긴다. **끝난 판**은 창을 닫으면 내려간다(내 판 결과 화면을 닫는 것 = 나가기와 같은 결 — 그대로 두면
// 재조회가 없어 다음에 창을 열 때 로비 대신 낡은 남의 판이 선다, 2026-09-30 반증). 관전이 내려가는 길은 넷이다: [나가기](`leaveWatch`) ·
// 로그아웃(`reset`) · 내 판이 섬(`match` 대입) · 끝난 판인 채 창 닫기(`windowDidHide`).
//
// ── 흑·백은 서버만 안다(C15) ──
// 로비 카드의 a/b 는 uuid 순서라 색이 아니다. 씨앗은 `faces` 두 얼굴뿐이고 `black`/`white` 는 첫 ok 응답의 black_user/white_user 로만 선다.
// 목록에서 이미 빠진 판(씨앗 없음)도 얼굴이 없을 뿐 같은 로딩 상태다.
//
// ── 실패 경로(C17) ──
// status 로 오는 실패(not_found·unsupported_client)와 throw 로 오는 실패(PGRST202·5xx·오프라인)를 다 정의한다. PGRST202 는 서버 미배포
// 창이라 관전을 내리고 "곧 열려요"; 그 밖은 연속 `watchFailureLimit` 회까지 씨앗 화면을 유지하다 넘으면 내리고 연결 안내를 남긴다.
// 빈 판 "관전 중"이 2초 폴링을 영영 도는 상태는 이 규칙으로 없다.
//
// ── 끝난 판 ──
// finished 응답을 한 번 받으면 폴링이 멈추고(`pollSpectatorFeatures` 가 `isFinished` 를 본다) 결과는 [나가기] 전까지 남는다.
// 서버는 끝난 지 3분까지만 ok 를 주고 그 뒤는 not_found 라 — 멈추는 것이 화면을 지키는 장치다.

extension GomokuStore {
    // MARK: 상수

    /// throw 실패(5xx·오프라인)가 이만큼 연속되면 관전을 내리고 연결 안내를 남긴다(2초 주기라 약 6초).
    /// 1회에 내리면 잠깐의 흔들림에 판이 사라지고, 무한이면 빈 판이 영영 돈다 — 그 사이 값이다.
    package nonisolated static let watchFailureLimit = 3

    // MARK: 읽기

    /// 내 user id(소문자). 세션이 없으면 nil.
    package var myUserID: String? { host?.session?.userID.lowercased() }

    /// 로비 "지금 대결 중" 카드가 내 판인가([관전] 칩 대신 "내 판" 캡션 — 로비에 잠깐 보이는 틈만 해당).
    package func isMine(_ live: GomokuLiveMatch) -> Bool {
        guard let mine = myUserID else { return false }
        return live.a.id == mine || live.b.id == mine
    }

    /// 지금 관전 폴링이 돌아야 하는가: 관전 중 + 안 끝남 + 로비 화면 + 주 스위치·창·세션.
    package var shouldPollWatch: Bool {
        guard let watch = spectating, !watch.isFinished else { return false }
        return phase == .lobby && canPollSpectatorFeatures
    }

    // MARK: 진입 · 이탈

    /// [관전] — 로비 카드의 두 얼굴을 씨앗으로 관전 상태를 세우고, 창이 보이면 곧바로 한 번 읽는다.
    /// 내 판이 진행 중(1:1·AI)이거나 결과 화면이면 아무것도 하지 않는다(rematch 와 같은 문장) — 관전 화면은 로비 자리에 선다.
    package func startWatching(matchID rawID: String) {
        let id = rawID.lowercased()
        guard spectatorFeaturesEnabled, !id.isEmpty, !GomokuAIGame.isAIMatchID(id), host?.session != nil else { return }
        if let current = match, !current.isFinished { return }
        guard phase == .lobby else { return }
        if spectating?.id == id { return }
        // ★ **문 앞에서 막는다.** 404 뒤 `stopWatching()` 이 `spectating` 을 비우므로 위 재진입 가드가 다시 통과한다 —
        //   화면의 칩만 잠그면 스토어를 직접 부르는 길(딥링크·다른 호출부)이 404 를 무한히 낸다. 잠금은 폴링 주기가
        //   한 번씩 풀어 주므로(`pollSpectatorFeatures`) 서버가 올라오면 저절로 열린다.
        guard !watchUnavailable else {
            setNotice(GomokuNoticeText.watchUnavailable)
            return
        }
        let seed: GomokuSpectateState
        if let live = liveMatches.first(where: { $0.id == id }) {
            seed = GomokuSpectateState(id: id, faces: [live.a, live.b], stake: live.stake.rawValue)
        } else {
            // 로비 30초 사이 목록에서 빠진 판을 눌렀다 — 얼굴 없는 같은 로딩 상태로 들어가고 응답이 채운다(못 보는 판이면 not_found 가 내린다).
            seed = GomokuSpectateState(id: id)
        }
        resetWatchRuntime()
        clearWatchNotice()
        spectating = seed
        if canPollSpectatorFeatures {
            Task { [weak self] in await self?.refreshWatch() }
        }
    }

    /// 사용자 [나가기]. 관전을 내리고 로비 자리로 돌아오며 목록·받은함·순위를 새로 읽는다(backToLobby 와 같은 결).
    /// 관전 중에 막아 둔 받은함의 `last_finished`(C20)도 이 조회로 뒤늦게 선다.
    package func leaveWatch() {
        stopWatching()
        guard host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshLobby()
            await self.loadInbox()
            await self.loadRanking()
        }
    }

    /// 조용히 내린다(요청 없음): 세대를 올려 나가 있던 응답을 버리고 장부를 비운다. 창 닫기는 **끝난 판일 때만** 여기를 부른다(C14 — 진행 중이면 남긴다).
    package func stopWatching() {
        resetWatchRuntime()
        if spectating != nil { spectating = nil }
    }

    /// 세대 올림 + 장부 초기값. 진입·나가기 둘 다 여기를 지난다 — 앞 판의 in-flight 깃발이 남으면 새 판의 첫 조회가 "도는 중"으로 합쳐져 영영 안 나간다.
    private func resetWatchRuntime() {
        let runtime = watchRuntime
        runtime.bumpWatchGeneration()
        runtime.watchInFlight = false
        runtime.watchAgain = false
        runtime.watchWantsFull = false
        runtime.watchFailureStreak = 0
        runtime.lastWatchRequestAt = .distantPast
    }

    /// 관전이 남긴 안내(못 보는 판·준비 중·연결)는 새 관전에 들어갈 때 걷는다.
    /// 그 밖의 안내(신청 거절·만료)는 관전 중에도 살아 있어야 하므로(C12) 건드리지 않는다.
    private func clearWatchNotice() {
        let mine: Set<String> = [GomokuNoticeText.watchGone, GomokuNoticeText.watchUnavailable, GomokuNoticeText.checkConnection]
        if let notice, mine.contains(notice) { setNotice(nil) }
    }

    // MARK: 조회

    /// 관전 판 한 번 조회. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다(loadInbox 와 같은 이유 — 버리면 구멍 재요청이 다음 계기까지 밀린다).
    /// 세대·판 id 두 자물쇠를 지난 응답만 `applyWatch` 로 간다. 창 규칙(보일 때만)은 부르는 쪽이 본다(refreshLobby 와 같은 배치).
    package func refreshWatch() async {
        guard spectatorFeaturesEnabled, host?.session != nil, let watched = spectating else { return }
        let runtime = watchRuntime
        if runtime.watchInFlight {
            runtime.watchAgain = true
            return
        }
        runtime.watchInFlight = true
        let generation = runtime.watchGeneration
        let resetMark = resetGeneration
        let id = watched.id
        repeat {
            runtime.watchAgain = false
            // 전체 재요청 표시는 **요청을 띄울 때 본다**(내리는 것은 그것을 실어 온 응답이다) — gomoku_state 와 같은 규약.
            let since = runtime.watchWantsFull ? 0 : (spectating?.appliedSeq ?? 0)
            runtime.lastWatchRequestAt = clock()
            let result = await perform({ try await $0.gomokuWatch(accessToken: $1, matchID: id, sinceSeq: since) })
            // 세대가 밀렸으면(나가기·판 전환·내 판·로그아웃) 장부는 그쪽이 이미 비웠다 — 여기서는 아무것도 건드리지 않는다.
            guard generation == runtime.watchGeneration, resetMark == resetGeneration else { return }
            switch result {
            case .success(let response)?:
                // 연속 실패는 **판을 실은 ok** 만 끊는다(applyWatch 안에서). 여기서 지우면 unauthorized·판 없는 ok 같은 status 거절이
                // 매번 0 → 1 로 되돌아가 watchFailureLimit 에 영영 못 닿는다 — 실서버 unauthorized 픽스처 3연속으로 실측(2026-09-30, W5).
                applyWatch(response, requestedSince: since)
            case .failure(let error)?:
                noteWatchFailure(error)
            case nil:
                break
            }
            // applyWatch·noteWatchFailure 가 관전을 내렸으면(not_found·미배포·연속 실패) 세대가 올랐다 — 그것으로 끝이다.
            guard generation == runtime.watchGeneration else { return }
        } while runtime.watchAgain && spectating != nil
        runtime.watchInFlight = false
    }

    /// 관전 응답을 화면 값으로 옮긴다. 관전 중이 아니거나 **다른 판** 응답이면 아무것도 바꾸지 않는다(C13 의 둘째 자물쇠).
    package func applyWatch(_ response: GomokuWatchResponse, requestedSince: Int = 0) {
        guard let current = spectating else { return }
        switch response.status {
        case .ok:
            guard let row = response.match else {
                noteWatchFailure(nil)               // ok 인데 판이 없다 — 모르는 모양은 실패로 센다(연속되면 내린다)
                return
            }
            guard row.id?.lowercased() == current.id else { return }
            noteServerNow(response.serverNowMs)
            // 관전이 실제로 왔다 — 서버에 함수가 있다. 잠겼던 칩을 여기서 연다(세우는 곳과 내리는 곳을 한 갈래씩만 둔다).
            if watchUnavailable { watchUnavailable = false }
            let status = row.status ?? ""
            guard status == "active" || status == "finished" else {
                // 서버 계약상 여기로 못 온다(pending·declined 은 not_found 다). 와도 판이 아니다 — not_found 와 같은 길.
                stopWatching()
                setNotice(GomokuNoticeText.watchGone)
                return
            }
            let inMatch = status == "active"
            // 흑·백은 **여기서만** 선다(C15). 서버 행이 없으면(프로필 삭제 등) 씨앗 얼굴·로비 목록에서 id 로 빌리고, 그래도 없으면 앞 값.
            let black = peerUser(response.blackUser, working: true, capable: true, inMatch: inMatch)
                ?? knownUser(id: row.black, in: current) ?? current.black
            let white = peerUser(response.whiteUser, working: true, capable: true, inMatch: inMatch)
                ?? knownUser(id: row.white, in: current) ?? current.white
            let deadline = inMatch ? deviceDate(serverMs: row.deadlineMs) : nil
            let startedAt = deviceDate(serverMs: row.startedMs) ?? current.startedAt
            guard let mapped = Self.spectateState(
                applying: response, to: current, requestedSince: requestedSince,
                black: black, white: white, deadline: deadline, startedAt: startedAt
            ) else { return }
            let runtime = watchRuntime
            runtime.watchFailureStreak = 0          // 판을 실은 응답 = 연결이 살아 있다(구멍 재요청도 마찬가지)
            if mapped.needsFull {
                // 수 번호에 구멍 — 판 문자열은 서버가 권위지만 마지막 수·자동 착수 점은 기록에서만 온다. 다음 한 번을 처음부터 받는다.
                runtime.watchWantsFull = true
                runtime.watchAgain = true
                return
            }
            if requestedSince == 0 { runtime.watchWantsFull = false }
            if spectating != mapped.state { spectating = mapped.state }
            // 1 이하는 받지 않는다(applyLobby 와 같은 이유 — 임계값 1이면 경고가 판 시작부터 참이다).
            if let streak = response.autoAbandonStreak, streak > 1, autoAbandonStreak != streak { autoAbandonStreak = streak }
        case .notFound:
            // 끝난 지 오래된 판·없는 판·숨김 격리 — 서버는 있다/없다를 가르지 않는다. 관전을 내리고 로비에 안내 한 줄.
            stopWatching()
            setNotice(GomokuNoticeText.watchGone)
        case .unsupportedClient:
            // 매 조회가 같은 답이라 폴링을 이어 갈 이유가 없다 — 내리고 업데이트 안내.
            stopWatching()
            setNotice(GomokuNoticeText.updateMine)
        default:
            Self.logger.notice("watch refused status=\(response.status.rawValue, privacy: .public)")
            noteWatchFailure(nil)               // unauthorized·모르는 status 도 연속이면 내린다 — 빈 판이 영영 돌지 않게
        }
    }

    /// 판의 두 사람 중 서버 행이 빠진 쪽을 id 로 찾는다: 씨앗 얼굴(로비 카드) → 로비 목록.
    private func knownUser(id rawID: String?, in current: GomokuSpectateState) -> GomokuUser? {
        guard let id = rawID?.lowercased(), !id.isEmpty else { return nil }
        return current.faces.first { $0.id == id } ?? users.first { $0.id == id }
    }

    /// 예외 실패 경로(C17). status 가 아니라 throw 로 온 실패(PGRST202·5xx·오프라인)와 모르는 응답 모양을 여기서 접는다.
    private func noteWatchFailure(_ error: (any Error)?) {
        if let known = error as? SupabaseWorkServiceError, known == .databaseSchemaMissing {
            // 서버에 gomoku_watch 가 아직 없다(앱이 db push 보다 먼저 나간 창).
            stopWatching()
            setNotice(GomokuNoticeText.watchUnavailable)
            // ★ 관전 입구를 잠그는 신호는 **조건 없이** 세운다. 아래 순위 깃발과 달리 이건 `gomoku_watch` 가 없다는 직접
            //   증거이고, 순위를 들고 있든 없든 관전은 못 한다. 이 한 줄이 없으면 [관전] 칩이 활성인 채로 남아 누를 때마다
            //   404 를 반복한다(칩 게이트는 `GomokuPanel` 의 `canWatch` 하나뿐이다 — 게이트와 신호는 짝으로 움직인다).
            if !watchUnavailable { watchUnavailable = true }
            // 순위표까지 함께 접는 것은 **순위를 한 번도 못 받았을 때만**이다. "같은 마이그레이션이라 순위표도 없다"는 추론은
            // 순위 조회가 성공한 적 없을 때만 맞다 — 순위를 이미 들고 있으면 서버에 gomoku_ranking 이 있다는 증거를 손에 든 것이라,
            // 관전 404 하나로 멀쩡한 순위표를 "곧 열려요"로 덮으면 안 된다(운영에서는 60초 폴링의 applyRanking 이 되돌리지만,
            // 폰 데모처럼 시계가 고정된 화면에서는 영구히 접힌 채 남는다). 관전을 내리고 안내를 남기는 것은 두 경우 다 한다.
            if ranking == nil {
                if !rankingUnavailable { rankingUnavailable = true }
                if !hasLoadedRanking { hasLoadedRanking = true }
            }
            return
        }
        Self.logger.notice("watch request failed")
        let runtime = watchRuntime
        runtime.watchFailureStreak += 1
        guard runtime.watchFailureStreak >= Self.watchFailureLimit else { return }
        stopWatching()
        setNotice(GomokuNoticeText.checkConnection)
    }

    // MARK: 폴링 훅 — GomokuStore.pollTick(at:) · windowDidShow() 가 부른다

    /// 안전망 한 걸음: 관전 중이면 2초마다 판, 아니면 로비에서 60초마다 순위. 창 규칙 ③(보이고 안 가려짐)·주 스위치·세션은
    /// `canPollSpectatorFeatures` 한 술어로 본다. 관전 중엔 순위를 돌리지 않는다(돌아올 때 `leaveWatch` 가 한 번 읽는다).
    package func pollSpectatorFeatures(at now: Date) async {
        guard canPollSpectatorFeatures, phase == .lobby else { return }
        if let watch = spectating {
            if !watch.isFinished, now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.watchPollSeconds {
                await refreshWatch()
            }
            return
        }
        if now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= Self.rankingPollSeconds {
            // ★ 관전 잠금을 이 주기에 **한 번 풀어 준다.** `watchUnavailable` 은 `startWatching` 을 문 앞에서 막으므로
            //   자기가 자기를 열 수 없다(내리는 곳이 성공한 관전인데, 잠겨 있으면 관전이 시작되지 않는다) — 안 풀면
            //   서버가 올라와도 로그아웃까지 잠긴 채 남는다. 풀어 두면 최악이 "60초에 404 한 번"이고, 그 사이 서버가
            //   올라오면 첫 성공이 잠금을 내린다(`applyWatch`). `rankingUnavailable` 이 폴링으로 회복하는 것과 같은 결이다.
            if watchUnavailable { watchUnavailable = false }
            await loadRanking()
        }
    }

    /// 창이 다시 보였다: 관전 중이면 즉시 한 번(C14), 로비면 순위 한 번 — 둘 다 로비 목록과 같은 1초 dedupe(열자마자 두 번 오는 통지 대비).
    package func spectatorWindowDidShow(at now: Date) {
        guard canPollSpectatorFeatures, phase == .lobby else { return }
        if let watch = spectating {
            if !watch.isFinished, now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.reloadDedupeSeconds {
                Task { [weak self] in await self?.refreshWatch() }
            }
            return
        }
        if now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.loadRanking() }
        }
    }

    // MARK: 순수 매퍼

    /// 응답 → 다음 관전 상태(순수). `black`/`white`/`deadline`/`startedAt` 은 호출부가 스토어 경계(peerUser·deviceDate)로 만들어 넘긴다.
    /// nil = 이 판 응답이 아니다. `needsFull` = 수 번호에 구멍이 있어 처음부터 다시 받아야 한다(그때 `state` 는 이전 값 그대로 —
    /// 구멍 난 판을 그리면 이미 돌이 있는 자리를 비어 있다고 보여 준다, applyState 와 같은 규약).
    package nonisolated static func spectateState(
        applying response: GomokuWatchResponse, to previous: GomokuSpectateState, requestedSince: Int,
        black: GomokuUser?, white: GomokuUser?, deadline: Date?, startedAt: Date?
    ) -> (state: GomokuSpectateState, needsFull: Bool)? {
        guard let row = response.match, row.id?.lowercased() == previous.id else { return nil }
        let status = row.status ?? ""
        guard status == "active" || status == "finished" else { return nil }
        let isFinished = status == "finished"
        let tolerateGaps = requestedSince == 0
        // `auto` 가 없는 응답(옛 서버)은 사람이 둔 수로 읽는다 — 모른다고 회색 점을 찍으면 판 전체가 거짓말이 된다.
        let records: [(seq: Int, color: GomokuColor, point: GomokuPoint?, auto: Bool)] = (response.moves ?? [])
            .compactMap { move in
                guard let seq = move.seq, let color = GomokuColor(rawValue: move.color ?? "") else { return nil }
                let auto = move.auto ?? false
                if move.kind == "pass" || move.x == nil || move.y == nil { return (seq, color, nil, auto) }
                guard let point = GomokuPoint(x: move.x ?? -1, y: move.y ?? -1) else { return nil }
                return (seq, color, point, auto)
            }
            .sorted { $0.seq < $1.seq }

        let rebuild = tolerateGaps || records.first?.seq == 1
        var board = rebuild ? GomokuBoard() : previous.board
        var lastMove = rebuild ? nil : previous.lastMove
        var applied = rebuild ? 0 : previous.appliedSeq
        var autoPoints = rebuild ? Set<GomokuPoint>() : previous.autoPoints
        var lastMoveWasAuto = rebuild ? false : previous.lastMoveWasAuto
        for record in records where record.seq > applied {
            if record.seq != applied + 1, !tolerateGaps { return (previous, true) }
            if let point = record.point {
                board[point] = record.color
                lastMove = point
                if record.auto { autoPoints.insert(point) } else { autoPoints.remove(point) }
            }
            lastMoveWasAuto = record.auto
            applied = record.seq
        }
        if let serverBoard = row.board.flatMap(GomokuBoard.init(serverString:)) {
            board = serverBoard                      // 판 문자열은 서버가 권위다
            if let serverCount = row.moveCount { applied = serverCount }
        } else if let serverCount = row.moveCount, serverCount != applied {
            if !tolerateGaps { return (previous, true) }
            applied = serverCount
        }

        var next = previous
        next.black = black
        next.white = white
        if let stake = row.stake { next.stake = stake }
        next.board = board
        next.lastMove = lastMove
        next.moveCount = row.moveCount ?? applied
        next.appliedSeq = applied
        next.autoPoints = autoPoints
        next.lastMoveWasAuto = lastMoveWasAuto
        next.turn = isFinished ? nil : GomokuColor(rawValue: row.turn ?? "")
        var nextDeadline = isFinished ? nil : deadline
        if let kept = previous.deadline, let fresh = nextDeadline, previous.moveCount == next.moveCount, previous.turn == next.turn,
           abs(fresh.timeIntervalSince(kept)) < GomokuStore.deadlineToleranceSeconds {
            // 같은 차례를 다시 읽었다 — 보정 오차만큼 다른 마감으로 갈면 창 루트가 2초마다 다시 그려진다(applyState 와 같은 이유).
            nextDeadline = kept
        }
        next.deadline = nextDeadline
        next.startedAt = startedAt
        next.isFinished = isFinished
        switch row.result {
        case "black_win": next.winner = .black
        case "white_win": next.winner = .white
        default: next.winner = nil                // 무승부 또는 아직 진행 중
        }
        next.endReason = row.endReason.flatMap(GomokuEndReason.init(rawValue:))
        if let streak = response.blackAutoStreak { next.blackAutoStreak = streak }
        if let streak = response.whiteAutoStreak { next.whiteAutoStreak = streak }
        return (next, false)
    }
}
