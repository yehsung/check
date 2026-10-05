import Foundation

// 체스 스토어의 **관전** 갈래 — 남의 진행 중인 판을 읽기 전용으로 본다.
//
// ── 관전은 판만이다 ──
// 서버 `chess_watch` 는 판(FEN)·수순·남은 시간·두 사람·판돈만 준다. `my_color`·`legal_moves`·`ruby_balance`·
// `opponent`·`state` 중복 봉투가 **없다**. 이 파일은 `chess_state` 를 **절대 부르지 않는다** — 참가자 게이트에 걸려
// 관전자는 not_found 만 받는다. 관전 응답을 `applyState` 로도 넣지 않는다(my_color 부재로 조용히 무시되거나
// 대국 화면이 서 버린다) — 적용 경로는 아래 `applyWatch` 하나다.
//
// ── 관전자는 깃발을 떨어뜨리지 않는다 ──
// `chess_watch` 는 읽기 전용이라 시간이 다 된 판을 닫지 않는다. 그래서 **"남은 시간이 0 인데 아직 진행 중"** 인
// 판을 볼 수 있다 — 화면은 0 에서 멈춰 보여 주면 되고, 그 판은 대국자의 다음 조회나 매분 cron 이 닫는다.
// 여기서 "0 이니 졌겠지" 로 결과를 지어내지 마라(관전자에게 거짓말하는 자리다 — 0.3.41 에서 한 번 데였다).
//
// ── 주 스위치 ──
// `spectatorFeaturesEnabled` 가 꺼져 있으면 진입·조회·폴링이 한 번도 안 돈다(폰이 그리지도 않는 순위를 당기지 않게).
//
// ── 세대 ──
// `watchRuntime.watchGeneration` 이 관전 세대다. 진입(판 전환)·나가기·로그아웃·내 판이 서서 관전이 내려갈 때
// 오르고, 요청을 띄울 때 잡은 세대와 응답이 왔을 때의 세대가 다르면 버린다. `resetGeneration` 만 보면 창을 닫은
// 뒤 늦게 온 응답이 관전을 되살리고, A 판을 나가 B 판을 보는 사이 A 의 늦은 응답이 B 판을 한 틱 덮는다.
// 세대가 같아도 응답의 `match.id` 가 다르면 버린다(이중 자물쇠).
//
// ── 흑·백은 서버만 안다 ──
// 로비 카드의 a/b 는 uuid 오름차순이라 색이 아니다. 씨앗은 `faces` 두 얼굴뿐이고 `black`/`white` 는 첫 ok 응답의
// black_user/white_user 로만 선다. 목록에서 이미 빠진 판(씨앗 없음)도 얼굴이 없을 뿐 같은 로딩 상태다.

/// 관전·순위 갈래의 관찰 대상이 아닌 장부(스토어 본문에 한 줄로 붙는다 — 저장 프로퍼티는 확장에 못 둔다).
///
/// 이름이 `reset` 이 아니라 `clear` 인 까닭(오목이 데인 자리): 소스 계약 테스트가 한 파일에서 `func reset()` 의
/// **첫 등장**을 스토어 것으로 잡는다 — 같은 이름을 앞에 두면 그 테스트가 이 몸통을 읽고 빨개진다.
@MainActor
package final class ChessWatchRuntime {
    package var lastWatchRequestAt: Date = .distantPast
    package var watchInFlight = false
    /// 조회 중에 또 조회할 이유가 생겼다 — 끝나면 한 번 더 돈다.
    package var watchAgain = false
    /// 다음 조회 한 번을 `p_since_seq = 0` 으로 띄운다(수 번호에 구멍이 났다).
    /// 내리는 것은 **그 전체를 실어 온 응답**이다 — 요청을 띄울 때 내리면 실패하거나 버린 응답에 표시가 사라져 구멍이 그대로 남는다.
    package var watchWantsFull = false
    package private(set) var watchGeneration = 0
    /// 연속 실패 횟수(throw 경로 — 5xx·오프라인). 문턱을 넘으면 관전을 내리고 안내 한 줄을 남긴다 —
    /// 빈 판 "관전 중" 화면이 2초 폴링을 영영 도는 상태를 만들지 않기 위한 장부다.
    package var watchFailureStreak = 0
    package var lastRankingRequestAt: Date = .distantPast
    package var rankingInFlight = false

    package init() {}

    @discardableResult
    package func bumpWatchGeneration() -> Int {
        watchGeneration &+= 1
        return watchGeneration
    }

    /// 전부 초기값 + 세대 한 번 올림(로그아웃·계정 전환 — 앞 계정의 늦은 응답을 버린다).
    package func clear() {
        lastWatchRequestAt = .distantPast
        watchInFlight = false
        watchAgain = false
        watchWantsFull = false
        watchFailureStreak = 0
        lastRankingRequestAt = .distantPast
        rankingInFlight = false
        bumpWatchGeneration()
    }
}

/// 관전 중인 남의 판 하나. `phase` 는 `.lobby` 그대로이고 **이 값이 nil 이 아닌 것**이 관전 중이다.
///
/// **흑·백을 추측하지 않는다**(파일 머리말). 판은 `match.fen` 이 권위이고 `moves` 는 기보·마지막 수용이다.
/// 끝난 응답을 한 번 받으면 `isFinished` 가 서고 폴링은 멈추지만 이 값은 [나가기] 전까지 남아 결과를 보여 준다.
package nonisolated struct ChessSpectateState: Identifiable, Equatable, Sendable {
    package let id: String                       // match id 소문자
    /// 로비 카드에서 빌린 두 얼굴(a·b 순서, **색 모름**). 씨앗을 못 찾았으면 비어 있다.
    package var faces: [ChessUser] = []
    /// 판돈. 씨앗이 없으면 nil 이고 응답의 `match.stake` 가 채운다.
    package var stake: Int? = nil
    /// 서버가 말한 흑·백. **첫 ok 응답 전에는 nil** — 이 둘이 서기 전에는 색 배지를 그리지 않는다.
    package var black: ChessUser? = nil
    package var white: ChessUser? = nil
    package var fen: String = ""
    /// `fen` 을 읽은 국면. nil 이면 판을 그릴 수 없다(서버 FEN 이 파서를 통과하지 못했다).
    package var position: ChessPosition? = nil
    package var plyCount: Int = 0
    /// 내가 반영한 마지막 수 번호. 다음 요청의 `p_since_seq` 다.
    package var appliedSeq: Int = 0
    package var moves: [ChessMoveRecord] = []
    package var lastMove: ChessMove? = nil
    package var turn: ChessColor? = nil           // 끝나면 nil
    package var clock: ChessServerClock = .initial
    package var isInCheck: Bool = false
    package var startedAt: Date? = nil
    package var isFinished: Bool = false
    /// 이긴 색. 끝났는데 nil 이면 무승부다.
    package var winner: ChessColor? = nil
    package var endReason: ChessEndReason? = nil

    /// 서버 응답을 한 번이라도 반영했는가(= 흑·백이 확정됐는가). 그 전에는 로딩 화면이다.
    package var hasServerState: Bool { black != nil && white != nil }

    package init(id: String, faces: [ChessUser] = [], stake: Int? = nil) {
        self.id = id
        self.faces = faces
        self.stake = stake
    }
}

extension ChessStore {
    // MARK: 읽기

    /// 내 user id(소문자). 세션이 없으면 nil.
    package var myUserID: String? { host?.session?.userID.lowercased() }

    /// 로비 "지금 대결 중" 카드가 내 판인가([관전] 칩 대신 "내 판" 캡션).
    package func isMine(_ live: ChessLiveMatch) -> Bool {
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
    /// 내 판이 진행 중(1:1·AI)이거나 결과 화면이면 아무것도 하지 않는다 — 관전 화면은 로비 자리에 선다.
    package func startWatching(matchID rawID: String) {
        let id = rawID.lowercased()
        guard spectatorFeaturesEnabled, !id.isEmpty, !ChessAIGame.isAIMatchID(id),
              host?.session != nil else { return }
        if let current = match, !current.isFinished { return }
        guard phase == .lobby else { return }
        if spectating?.id == id { return }
        // ★ **문 앞에서 막는다.** 404 뒤 `stopWatching()` 이 `spectating` 을 비우므로 위 재진입 가드가 다시
        //   통과한다 — 화면의 칩만 잠그면 스토어를 직접 부르는 길이 404 를 무한히 낸다. 잠금은 폴링 주기가
        //   한 번씩 풀어 주므로 서버가 올라오면 저절로 열린다.
        guard !watchUnavailable else {
            setNotice(ChessNoticeText.unavailable)
            return
        }
        let seed: ChessSpectateState
        if let live = liveMatches.first(where: { $0.id == id }) {
            seed = ChessSpectateState(id: id, faces: [live.a, live.b], stake: live.stake.rawValue)
        } else {
            // 로비 30초 사이 목록에서 빠진 판을 눌렀다 — 얼굴 없는 같은 로딩 상태로 들어가고 응답이 채운다.
            seed = ChessSpectateState(id: id)
        }
        resetWatchRuntime()
        clearWatchNotice()
        spectating = seed
        if canPollSpectatorFeatures {
            Task { [weak self] in await self?.refreshWatch() }
        }
    }

    /// 사용자 [나가기]. 관전을 내리고 로비 자리로 돌아오며 목록·순위를 새로 읽는다.
    package func leaveWatch() {
        stopWatching()
        guard host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshLobby()
            await self.loadRanking()
        }
    }

    /// 조용히 내린다(요청 없음): 세대를 올려 나가 있던 응답을 버리고 장부를 비운다.
    /// 창 닫기는 **끝난 판일 때만** 여기를 부른다(진행 중이면 남긴다 — 최소화에서도 오는 통지다).
    package func stopWatching() {
        resetWatchRuntime()
        if spectating != nil { spectating = nil }
        clearFlight()
    }

    /// 세대 올림 + 장부 초기값. 진입·나가기 둘 다 여기를 지난다 — 앞 판의 in-flight 깃발이 남으면
    /// 새 판의 첫 조회가 "도는 중" 으로 합쳐져 영영 안 나간다.
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
    /// 그 밖의 안내(신청 거절·만료)는 관전 중에도 살아 있어야 하므로 건드리지 않는다.
    private func clearWatchNotice() {
        let mine: Set<String> = [ChessNoticeText.watchGone, ChessNoticeText.unavailable,
                                 ChessNoticeText.checkConnection]
        if let notice, mine.contains(notice) { setNotice(nil) }
    }

    // MARK: 조회

    /// 관전 판 한 번 조회. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다(버리면 구멍 재요청이 다음 계기까지 밀린다).
    /// 세대·판 id 두 자물쇠를 지난 응답만 `applyWatch` 로 간다. 창 규칙(보일 때만)은 **부르는 쪽**이 본다.
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
            // 전체 재요청 표시는 **요청을 띄울 때 본다**(내리는 것은 그것을 실어 온 응답이다).
            let since = runtime.watchWantsFull ? 0 : (spectating?.appliedSeq ?? 0)
            runtime.lastWatchRequestAt = clock()
            let result = await perform({ try await $0.chessWatch(accessToken: $1, matchID: id, sinceSeq: since) })
            // 세대가 밀렸으면(나가기·판 전환·내 판·로그아웃) 장부는 그쪽이 이미 비웠다 — 여기서는 아무것도 건드리지 않는다.
            guard generation == runtime.watchGeneration, resetMark == resetGeneration else { return }
            switch result {
            case .success(let response)?:
                // 연속 실패는 **판을 실은 ok** 만 끊는다(`applyWatch` 안에서). 여기서 지우면 unauthorized·판 없는 ok
                // 같은 status 거절이 매번 0 → 1 로 되돌아가 문턱에 영영 못 닿는다(오목 실측).
                applyWatch(response, requestedSince: since)
            case .failure(let error)?:
                noteWatchFailure(error)
            case nil:
                break
            }
            guard generation == runtime.watchGeneration else { return }
        } while runtime.watchAgain && spectating != nil
        runtime.watchInFlight = false
    }

    /// 관전 응답을 화면 값으로 옮긴다. 관전 중이 아니거나 **다른 판** 응답이면 아무것도 바꾸지 않는다(둘째 자물쇠).
    package func applyWatch(_ response: ChessWatchResponse, requestedSince: Int = 0) {
        guard let current = spectating else { return }
        switch response.status {
        case .ok:
            guard let row = response.match else {
                noteWatchFailure(nil)        // ok 인데 판이 없다 — 모르는 모양은 실패로 센다(연속되면 내린다)
                return
            }
            guard row.id?.lowercased() == current.id else { return }
            noteServerNow(response.serverNowMs)
            // 관전이 실제로 왔다 — 서버에 함수가 있다. 잠겼던 칩을 여기서 연다(세우는 곳·내리는 곳 한 갈래씩).
            if watchUnavailable { watchUnavailable = false }
            let status = row.status ?? ""
            guard status == "active" || status == "finished" else {
                // 서버 계약상 여기로 못 온다(pending 은 not_found 다). 와도 판이 아니다 — not_found 와 같은 길.
                stopWatching()
                setNotice(ChessNoticeText.watchGone)
                return
            }
            let inMatch = status == "active"
            // 흑·백은 **여기서만** 선다. 서버 행이 없으면(프로필 삭제 등) 씨앗 얼굴·로비 목록에서 id 로 빌리고,
            // 그래도 없으면 앞 값이다.
            let black = peerUser(response.blackUser, inMatch: inMatch)
                ?? knownUser(id: row.black, in: current) ?? current.black
            let white = peerUser(response.whiteUser, inMatch: inMatch)
                ?? knownUser(id: row.white, in: current) ?? current.white
            let turnStartedAt = deviceDate(serverMs: row.turnStartedMs)
            let startedAt = deviceDate(serverMs: row.startedMs) ?? current.startedAt
            guard let mapped = Self.spectateState(
                applying: response, to: current, requestedSince: requestedSince,
                black: black, white: white, turnStartedAt: turnStartedAt, startedAt: startedAt
            ) else { return }
            let runtime = watchRuntime
            runtime.watchFailureStreak = 0   // 판을 실은 응답 = 연결이 살아 있다
            if mapped.needsFull {
                // 수 번호에 구멍 — 판은 `fen` 이 권위라 멀쩡하지만 **기보**가 구멍 난 채로는 그리지 않는다.
                runtime.watchWantsFull = true
                runtime.watchAgain = true
                return
            }
            if requestedSince == 0 { runtime.watchWantsFull = false }
            if spectating != mapped.state { spectating = mapped.state }
            // 관전도 같은 문으로 미끄러진다(세 깔때기 중 하나 — `beginFlight` 머리말).
            // 진입 직후의 첫 응답은 씨앗의 `position` 이 nil 이라 거절 ④에서 떨어진다 — 로비 카드에는 판
            // 내용이 없으므로(`ChessLiveMatch`) 들어간 순간 밀린 수 전부를 한 장으로 미끄러뜨릴 재료가 없다.
            beginFlight(matchID: mapped.state.id, previousMatchID: current.id,
                        previousPly: current.plyCount, previousPosition: current.position,
                        nextPly: mapped.state.plyCount, nextPosition: mapped.state.position,
                        move: mapped.state.lastMove)
        case .notFound:
            // 끝난 지 오래된 판·없는 판·숨김 격리 — 서버는 있다/없다를 가르지 않는다.
            stopWatching()
            setNotice(ChessNoticeText.watchGone)
        case .unsupportedClient:
            // 매 조회가 같은 답이라 폴링을 이어 갈 이유가 없다.
            stopWatching()
            setNotice(ChessNoticeText.updateMine)
        default:
            Self.logger.notice("watch refused status=\(response.status.rawValue, privacy: .public)")
            noteWatchFailure(nil)            // unauthorized·모르는 status 도 연속이면 내린다
        }
    }

    /// 판의 두 사람 중 서버 행이 빠진 쪽을 id 로 찾는다: 씨앗 얼굴(로비 카드) → 로비 목록.
    private func knownUser(id rawID: String?, in current: ChessSpectateState) -> ChessUser? {
        guard let id = rawID?.lowercased(), !id.isEmpty else { return nil }
        return current.faces.first { $0.id == id } ?? users.first { $0.id == id }
    }

    /// 예외 실패 경로. status 가 아니라 **throw 로 온** 실패(PGRST202·5xx·오프라인)와 모르는 응답 모양을 접는다.
    private func noteWatchFailure(_ error: (any Error)?) {
        if let error, isSchemaMissing(error) {
            // 서버에 chess_watch 가 아직 없다(앱이 db push 보다 먼저 나간 창).
            stopWatching()
            setNotice(ChessNoticeText.unavailable)
            // ★ 관전 입구를 잠그는 신호는 **조건 없이** 세운다. 이건 `chess_watch` 가 없다는 직접 증거이고,
            //   순위를 들고 있든 없든 관전은 못 한다. 이 한 줄이 없으면 [관전] 칩이 활성인 채로 남아 누를 때마다
            //   404 를 반복한다 — 게이트와 신호는 짝으로 움직인다.
            if !watchUnavailable { watchUnavailable = true }
            // 순위표까지 함께 접는 것은 **순위를 한 번도 못 받았을 때만**이다. 순위를 이미 들고 있으면 서버에
            // chess_ranking 이 있다는 증거를 손에 든 것이라, 관전 404 하나로 멀쩡한 순위표를 덮으면 안 된다.
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
        setNotice(ChessNoticeText.checkConnection)
    }

    // MARK: 폴링 훅 — ChessStore.pollTick(at:) · windowDidShow() 가 부른다

    /// 안전망 한 걸음: 관전 중이면 2초마다 판, 아니면 로비에서 60초마다 순위. 창 규칙(보이고 안 가려짐)·
    /// 주 스위치·세션은 `canPollSpectatorFeatures` 한 술어로 본다.
    /// 관전 중엔 순위를 돌리지 않는다(돌아올 때 `leaveWatch` 가 한 번 읽는다).
    package func pollSpectatorFeatures(at now: Date) async {
        guard canPollSpectatorFeatures, phase == .lobby else { return }
        // ★ 같은 사실을 두 곳에 적지 않는다. 옛 코드는 여기에 "관전 중 + 안 끝남" 을 **다시** 써서
        //   `shouldPollWatch` 를 아무도 안 쓰는 죽은 게이트로 만들었고(소스·테스트 전체 참조 0건),
        //   그래서 그 프로퍼티에서 `!watch.isFinished` 를 지워도 전부 초록이었다(2026-10-05 뮤테이션 M12).
        if spectating != nil {
            if shouldPollWatch,
               now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.watchPollSeconds {
                await refreshWatch()
            }
            return
        }
        if now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= Self.rankingPollSeconds {
            // ★ 관전 잠금을 이 주기에 **한 번 풀어 준다.** `watchUnavailable` 은 `startWatching` 을 문 앞에서
            //   막으므로 자기가 자기를 열 수 없다 — 안 풀면 서버가 올라와도 로그아웃까지 잠긴 채 남는다.
            //   풀어 두면 최악이 "60초에 404 한 번" 이고, 그 사이 서버가 올라오면 첫 성공이 잠금을 내린다.
            if watchUnavailable { watchUnavailable = false }
            await loadRanking()
        }
    }

    /// 창이 다시 보였다: 관전 중이면 즉시 한 번, 로비면 순위 한 번 — 둘 다 로비 목록과 같은 1초 dedupe.
    package func spectatorWindowDidShow(at now: Date) {
        guard canPollSpectatorFeatures, phase == .lobby else { return }
        if spectating != nil {
            if shouldPollWatch,
               now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.reloadDedupeSeconds {
                Task { [weak self] in await self?.refreshWatch() }
            }
            return
        }
        if now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.loadRanking() }
        }
    }

    // MARK: 순수 매퍼

    /// 응답 → 다음 관전 상태(순수). `black`/`white`/시각 둘은 호출부가 스토어 경계(peerUser·deviceDate)로 만들어 넘긴다.
    /// nil = 이 판 응답이 아니다. `needsFull` = 수 번호에 구멍이 있어 처음부터 다시 받아야 한다(그때 `state` 는
    /// 이전 값 그대로 — 구멍 난 기보를 그리면 기보가 거짓말을 한다).
    package nonisolated static func spectateState(
        applying response: ChessWatchResponse, to previous: ChessSpectateState, requestedSince: Int,
        black: ChessUser?, white: ChessUser?, turnStartedAt: Date?, startedAt: Date?
    ) -> (state: ChessSpectateState, needsFull: Bool)? {
        guard let row = response.match, row.id?.lowercased() == previous.id else { return nil }
        let status = row.status ?? ""
        guard status == "active" || status == "finished" else { return nil }
        let isFinished = status == "finished"
        let rebuild = requestedSince == 0 || response.moves?.first?.seq == 1

        var merged = rebuild ? [] : previous.moves
        var applied = rebuild ? 0 : previous.appliedSeq
        for record in moveRecords(from: response.moves) where record.seq > applied {
            if record.seq != applied + 1, !rebuild { return (previous, true) }
            merged.append(record)
            applied = record.seq
        }
        let serverPly = row.plyCount ?? applied
        if serverPly != applied, !rebuild { return (previous, true) }

        var next = previous
        next.black = black
        next.white = white
        if let stake = row.stake { next.stake = stake }
        next.fen = row.fen ?? previous.fen
        next.position = ChessPosition(fen: next.fen)
        next.plyCount = serverPly
        next.appliedSeq = applied
        next.moves = merged
        next.lastMove = merged.last?.move
        next.turn = isFinished ? nil : ChessColor(rawValue: row.turn ?? "")
        next.clock = ChessServerClock(
            whiteMsLeft: row.whiteMsLeft ?? previous.clock.whiteMsLeft,
            blackMsLeft: row.blackMsLeft ?? previous.clock.blackMsLeft,
            incrementMs: row.incrementMs ?? previous.clock.incrementMs,
            turnStartedAt: isFinished ? nil : turnStartedAt,
            running: next.turn)
        next.isInCheck = response.inCheck ?? false
        next.startedAt = startedAt
        next.isFinished = isFinished
        switch row.result {
        case "white_win": next.winner = .white
        case "black_win": next.winner = .black
        default: next.winner = nil                // 무승부 또는 아직 진행 중
        }
        next.endReason = row.endReason.flatMap(ChessEndReason.init(rawValue:))
        return (next, false)
    }
}
