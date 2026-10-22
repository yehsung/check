import Foundation

// 테트리스 스토어의 **관전** 갈래(v0.3.64) — 남의 진행 중인 판을 읽기 전용으로 본다.
// 본은 `ChessStoreWatch.swift` 다. **같은 규약을 그대로 베끼고** 테트리스에서 달라지는 자리만 바꿨다.
//
// ── 관전은 두 판뿐이다 ──
// 서버 `tetris_watch` 는 판돈·두 사람·두 판(200글자)·지운 줄·대기 방해 줄·탑아웃만 준다. `me`/`opponent`·`seed`·
// `ruby_balance`·`state` 중복 봉투가 **없다**. 이 파일은 `tetris_state` 를 **절대 부르지 않는다** — 참가자 게이트에
// 걸려 관전자는 not_found 만 받는다. 관전 응답을 `applyState` 로도 넣지 않는다(판 구동기가 남의 시드로 서 버린다) —
// 적용 경로는 아래 `applyWatch` 하나다.
//
// ── 관전자는 판을 닫지 않는다 ──
// `tetris_watch` 는 읽기 전용이라 상한(480초)이 지난 판도 닫지 않는다. 그래서 **"시간이 다 됐는데 아직 active"** 인
// 판을 볼 수 있다 — 화면은 0 에서 멈춰 보여 주면 되고, 그 판은 대국자의 다음 조회나 매분 cron(`tetris_settle_expired`)이
// 닫는다. 여기서 "시간이 다 됐으니 누가 이겼겠지" 로 결과를 지어내지 마라(체스 0.3.41 이 데인 자리다).
//
// ── a/b 는 색이 아니라 자리다 ──
// 로비 카드도 관전 응답도 **uuid 오름차순**이다. challenger/opponent 가 어느 쪽인지는 관전 봉투에 없으므로
// `match.result`("challenger_win"…)로 승자 자리를 **역산하지 마라**(둘일 때 맞는 식이 셋째 경우에 거짓말한다).
// 탑아웃한 쪽은 `side.toppedOut` 이 직접 말한다.
//
// ── 깃발 둘은 겸업하지 않는다 ──
//  · `watchUnavailable`          — 서버에 `tetris_watch` 가 **없다**(PGRST202). 관전 **입구를 잠근다**.
//  · `spectatorCountUnavailable` — 서버에 `tetris_watch_live` 만 없다. **관전자 수 한 칸만** 접는다(수는 0,
//    화면은 그 칸을 안 그린다). 관전 자체는 멀쩡하므로 **입구를 잠그면 안 된다** — 한 깃발로 겸업시키면
//    "관전자 수가 없다" 는 이유로 관전이 통째로 잠긴다(체스가 `rankingUnavailable` 겸업으로 데인 자리다).
//  · 둘 다 테트리스 전체 스위치 `availability` 와도 따로다 — `noteServerMissing()` 을 부르면 관전 함수 하나가
//    없다는 이유로 1:1 테트리스 전체가 "곧 열려요" 로 잠긴다.
//
// ── 세대 ──
// `watchRuntime.watchGeneration` 이 관전 세대다. 진입(판 전환)·나가기·로그아웃·내 판이 서서 관전이 내려갈 때
// 오르고, 요청을 띄울 때 잡은 세대와 응답이 왔을 때의 세대가 다르면 버린다. `resetGeneration` 만 보면 창을 닫은 뒤
// 늦게 온 응답이 관전을 되살리고, A 판을 나가 B 판을 보는 사이 A 의 늦은 응답이 B 판을 한 틱 덮는다.
// 세대가 같아도 응답의 `match.id` 가 다르면 버린다(이중 자물쇠).

/// 관전 갈래의 관찰 대상이 아닌 장부(스토어 본문에 한 줄로 붙는다 — 저장 프로퍼티는 확장에 못 둔다).
///
/// 이름이 `reset` 이 아니라 `clear` 인 까닭(오목·체스가 데인 자리): 소스 계약 테스트가 한 파일에서 `func reset()` 의
/// **첫 등장**을 스토어 것으로 잡는다 — 같은 이름을 앞에 두면 그 테스트가 이 몸통을 읽고 빨개진다.
@MainActor
package final class TetrisWatchRuntime {
    package var lastWatchRequestAt: Date = .distantPast
    package var watchInFlight = false
    /// 조회 중에 또 조회할 이유가 생겼다 — 끝나면 한 번 더 돈다(`*_live` 접힘 재시도도 이 문을 쓴다).
    package var watchAgain = false
    package private(set) var watchGeneration = 0
    /// 연속 실패 횟수(throw 경로 — 5xx·오프라인 — 과 모르는 status). 문턱을 넘으면 관전을 내리고 안내 한 줄을 남긴다.
    /// 빈 판 "관전 중" 화면이 2초 폴링을 영영 도는 상태를 만들지 않기 위한 장부다.
    package var watchFailureStreak = 0
    /// `watchUnavailable` 을 세운 시각. 로비 주기(30초)마다 한 번 풀어 주는 타이머다 —
    /// 잠금은 자기가 자기를 못 열기 때문에(`startWatching` 을 문 앞에서 막는다) 이 장부가 없으면 로그아웃까지 잠긴다.
    package var watchLockedAt: Date = .distantPast

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
        watchFailureStreak = 0
        watchLockedAt = .distantPast
        bumpWatchGeneration()
    }
}

/// 관전 중인 판의 한 자리(a 또는 b). **판 글자는 가공하지 않는다.**
package nonisolated struct TetrisSpectateSide: Equatable, Sendable {
    package var user: TetrisDuelUser?
    /// 서버 `tetris_players.board` 200글자 **그대로**. 아직 보고가 없으면 nil 이고, 길이·글자 집합이 어긋난
    /// 응답도 nil 이다(그 자리만 접는다 — 반대쪽과 숫자들은 산다).
    package var board: String?
    /// `board` 를 읽은 20행 × 10칸. 그리는 쪽이 `TetrisBoardPainter.drawMiniBoard` 에 그대로 넘긴다.
    /// `board` 가 nil 이면 nil 이다(둘은 언제나 같이 선다).
    package var cells: [[TetrisDuelCell]]?
    package var lines: Int = 0
    /// 아직 이 판에 안 들어간 대기 방해 줄.
    package var pending: Int = 0
    /// 이 사람이 보낸 공격 누계.
    package var attackSent: Int = 0
    package var toppedOut: Bool = false
    package var lastSeenAt: Date?

    package init(user: TetrisDuelUser? = nil, board: String? = nil, cells: [[TetrisDuelCell]]? = nil,
                 lines: Int = 0, pending: Int = 0, attackSent: Int = 0, toppedOut: Bool = false,
                 lastSeenAt: Date? = nil) {
        self.user = user
        self.board = board
        self.cells = cells
        self.lines = lines
        self.pending = pending
        self.attackSent = attackSent
        self.toppedOut = toppedOut
        self.lastSeenAt = lastSeenAt
    }

    package static let empty = TetrisSpectateSide()
}

/// 관전 중인 남의 판 하나. `phase` 는 `.lobby` 그대로이고 **이 값이 nil 이 아닌 것**이 관전 중이다.
///
/// 끝난 응답을 한 번 받으면 `isFinished` 가 서고 폴링은 멈추지만 이 값은 [나가기] 전까지 남아 결과를 보여 준다.
package nonisolated struct TetrisSpectateState: Identifiable, Equatable, Sendable {
    package let id: String                       // match id 소문자
    /// 로비 카드에서 빌린 두 얼굴(a·b 순서 = uuid 오름차순). 씨앗을 못 찾았으면 비어 있다.
    package var faces: [TetrisDuelUser] = []
    /// 판돈. 씨앗이 없으면 nil 이고 응답의 `match.stake` 가 채운다.
    package var stake: Int?
    package var a: TetrisSpectateSide = .empty
    package var b: TetrisSpectateSide = .empty
    package var startedAt: Date?
    package var isFinished = false
    /// 서버가 말한 결과 글자 그대로('challenger_win' | 'opponent_win' | 'draw'). **진행 중이면 nil 이고,
    /// 시간이 다 돼 보여도 여기에 값을 지어 넣지 않는다.**
    package var result: String?
    /// 이긴 사람의 uuid(소문자). 무승부·진행 중이면 nil.
    ///
    /// ★ **`result` 로 역산하지 마라.** 'challenger_win' 은 "challenger 가 이겼다" 인데 관전 봉투에는 누가
    /// challenger 인지가 없다(a·b 는 uuid 오름차순 **자리**일 뿐 색도 역할도 아니다). 서버가 `match.winner` 를
    /// 직접 싣는 까닭이 그것이고, 아래 `aWon`·`bWon` 은 그 uuid 가 어느 자리의 사람인지만 본다.
    package var winnerUserID: String?
    package var endReason: TetrisDuelEndReason?
    package var finishedAt: Date?
    /// 서버 응답을 한 번이라도 반영했는가. 그 전에는 로딩 화면이다.
    package var hasServerState = false

    /// a 자리가 이겼는가. 승자를 모르거나(진행 중·무승부·구버전 서버) 그 자리의 사람을 아직 못 받았으면 **거짓**이다 —
    /// "둘 다 거짓" 은 정상 상태이고, 화면은 그때 승자를 말하지 않아야 한다.
    package var aWon: Bool { winnerUserID != nil && a.user?.id == winnerUserID }
    /// b 자리가 이겼는가. 규약은 `aWon` 과 같다.
    package var bWon: Bool { winnerUserID != nil && b.user?.id == winnerUserID }

    package init(id: String, faces: [TetrisDuelUser] = [], stake: Int? = nil) {
        self.id = id
        self.faces = faces
        self.stake = stake
    }
}

extension TetrisDuelStore {
    // MARK: 읽기

    /// 내 user id(소문자). 세션이 없으면 nil.
    package var myUserID: String? { host?.session?.userID.lowercased() }

    /// 로비 "지금 대결 중" 카드가 내 판인가([관전] 칩 대신 "내 판" 캡션).
    package func isMine(_ live: TetrisDuelLiveMatch) -> Bool {
        guard let mine = myUserID else { return false }
        return live.a.id == mine || live.b.id == mine
    }

    package var isSpectating: Bool { spectating != nil }

    /// 관전 조회가 **지금** 나가도 되는가 — 주 스위치 + 창이 보이고 안 가려짐 + 세션.
    /// 두 폴링 분기가 이 한 술어를 쓴다(창 규칙을 각자 다시 적으면 한쪽이 언젠가 빠진다).
    package var canPollSpectatorFeatures: Bool {
        spectatorFeaturesEnabled && isWindowVisible && !isWindowOccluded && host?.session != nil
    }

    /// 지금 관전 폴링이 돌아야 하는가: 관전 중 + 안 끝남 + 로비 자리 + 주 스위치·창·세션.
    package var shouldPollWatch: Bool {
        guard let watch = spectating, !watch.isFinished else { return false }
        return phase == .lobby && canPollSpectatorFeatures
    }

    // MARK: 진입 · 이탈

    /// [관전] — 로비 카드의 두 얼굴을 씨앗으로 관전 상태를 세우고, 창이 보이면 곧바로 한 번 읽는다.
    /// 내 판이 진행 중이거나 결과 화면이면 아무것도 하지 않는다 — 관전 화면은 로비 자리에 선다.
    package func startWatching(matchID rawID: String) {
        let id = rawID.lowercased()
        guard spectatorFeaturesEnabled, !id.isEmpty, host?.session != nil else { return }
        if let current = match, !current.isFinished { return }
        guard phase == .lobby else { return }
        if spectating?.id == id { return }
        // ★ **문 앞에서 막는다.** not_found 뒤 `stopWatching()` 이 `spectating` 을 비우므로 위 재진입 가드가 다시
        //   통과한다 — 화면의 칩만 잠그면 스토어를 직접 부르는 길이 404 를 무한히 낸다. 잠금은 로비 주기가
        //   한 번씩 풀어 주므로(`pollWatch`) 서버가 올라오면 저절로 열린다.
        guard !watchUnavailable else {
            setNotice(TetrisDuelNoticeText.unavailable)
            return
        }
        var seed: TetrisSpectateState
        if let live = liveMatches.first(where: { $0.id == id }) {
            seed = TetrisSpectateState(id: id, faces: [live.a, live.b], stake: live.stake.rawValue)
            seed.a.user = live.a
            seed.b.user = live.b
            seed.startedAt = live.startedAt
        } else {
            // 로비 30초 사이 목록에서 빠진 판을 눌렀다 — 얼굴 없는 같은 로딩 상태로 들어가고 응답이 채운다.
            seed = TetrisSpectateState(id: id)
        }
        resetWatchRuntime()
        clearWatchNotice()
        spectating = seed
        if spectatorCount != 0 { spectatorCount = 0 }
        if canPollSpectatorFeatures {
            Task { [weak self] in await self?.refreshWatch() }
        }
    }

    /// 사용자 [나가기]. 관전을 내리고 로비 자리로 돌아오며 목록을 새로 읽는다.
    package func leaveWatch() {
        stopWatching()
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.refreshLobby() }
    }

    /// 조용히 내린다(요청 없음): 세대를 올려 나가 있던 응답을 버리고 장부를 비운다.
    /// 창 닫기는 **끝난 판일 때만** 여기를 부른다(진행 중이면 남긴다 — 최소화에서도 오는 통지다).
    package func stopWatching() {
        resetWatchRuntime()
        if spectating != nil { spectating = nil }
        if spectatorCount != 0 { spectatorCount = 0 }
    }

    /// 관전 값만 내린다(요청·장부 없음). `match` didSet 이 "내 판이 섰다" 로 부르는 문이다.
    func dropSpectating() {
        watchRuntime.bumpWatchGeneration()
        if spectating != nil { spectating = nil }
        if spectatorCount != 0 { spectatorCount = 0 }
    }

    /// 세대 올림 + 장부 초기값. 진입·나가기 둘 다 여기를 지난다 — 앞 판의 in-flight 깃발이 남으면
    /// 새 판의 첫 조회가 "도는 중" 으로 합쳐져 영영 안 나간다.
    private func resetWatchRuntime() {
        let runtime = watchRuntime
        runtime.bumpWatchGeneration()
        runtime.watchInFlight = false
        runtime.watchAgain = false
        runtime.watchFailureStreak = 0
        runtime.lastWatchRequestAt = .distantPast
    }

    /// 관전이 남긴 안내(못 보는 판·준비 중·연결)는 새 관전에 들어갈 때 걷는다.
    /// 그 밖의 안내(신청 거절·만료)는 관전 중에도 살아 있어야 하므로 건드리지 않는다.
    private func clearWatchNotice() {
        let mine: Set<String> = [TetrisDuelNoticeText.watchGone, TetrisDuelNoticeText.unavailable,
                                 TetrisDuelNoticeText.checkConnection]
        if let notice, mine.contains(notice) { setNotice(nil) }
    }

    // MARK: 조회

    /// 관전 판 한 번 조회. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다.
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
            // 접힌 길이면 `tetris_watch`, 아니면 `tetris_watch_live`. 요청 본문은 둘 다 { p_protocol, p_match_id } 다.
            let live = !spectatorCountUnavailable
            runtime.lastWatchRequestAt = clock()
            let result = live
                ? await perform({ try await $0.tetrisWatchLive(accessToken: $1, matchID: id) })
                : await perform({ try await $0.tetrisWatch(accessToken: $1, matchID: id) })
            // 세대가 밀렸으면(나가기·판 전환·내 판·로그아웃) 장부는 그쪽이 이미 비웠다 — 여기서는 아무것도 건드리지 않는다.
            guard generation == runtime.watchGeneration, resetMark == resetGeneration else { return }
            switch result {
            case .success(let response)?:
                applyWatch(response, countsWatchers: live)
            case .failure(let error)?:
                if live, isSchemaMissing(error) {
                    // 서버에 `tetris_watch_live` 만 없다(앱이 db push 보다 먼저 나간 창).
                    // **관전자 수 한 칸만 접고** 옛 길로 곧바로 한 번 더 간다 — 관전 입구는 잠그지 않는다.
                    if !spectatorCountUnavailable { spectatorCountUnavailable = true }
                    if spectatorCount != 0 { spectatorCount = 0 }
                    runtime.watchAgain = true
                } else {
                    noteWatchFailure(error)
                }
            case nil:
                break
            }
            guard generation == runtime.watchGeneration else { return }
        } while runtime.watchAgain && spectating != nil
        runtime.watchInFlight = false
    }

    /// 관전 응답을 화면 값으로 옮긴다. 관전 중이 아니거나 **다른 판** 응답이면 아무것도 바꾸지 않는다(둘째 자물쇠).
    ///
    /// - Parameter countsWatchers: 이 응답이 `tetris_watch_live` 의 것인가. 접힌 길(`tetris_watch`)이면 false 이고
    ///   그때 `spectatorCount` 는 0 이다(없는 수를 0 으로 "아는 척" 하지 않도록 화면은 `spectatorCountUnavailable` 을 본다).
    package func applyWatch(_ response: TetrisWatchResponse, countsWatchers: Bool = true) {
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
                setNotice(TetrisDuelNoticeText.watchGone)
                return
            }
            let next = Self.spectateState(
                applying: response, to: current,
                a: watchUser(response.a?.user), b: watchUser(response.b?.user),
                aLastSeenAt: deviceDate(serverMs: response.a?.lastSeenMs),
                bLastSeenAt: deviceDate(serverMs: response.b?.lastSeenMs),
                startedAt: deviceDate(serverMs: row.startedMs) ?? current.startedAt,
                finishedAt: deviceDate(serverMs: row.finishedMs) ?? current.finishedAt)
            guard let next else { return }
            watchRuntime.watchFailureStreak = 0   // 판을 실은 응답 = 연결이 살아 있다
            if spectating != next { spectating = next }
            let count = countsWatchers ? max(0, response.watchers ?? 0) : 0
            if spectatorCount != count { spectatorCount = count }
        case .notFound:
            // 끝난 지 오래된 판(꼬리 3분 밖)·없는 판·숨김 격리 — 서버는 있다/없다를 가르지 않는다.
            stopWatching()
            setNotice(TetrisDuelNoticeText.watchGone)
        case .unsupportedClient:
            // 매 조회가 같은 답이라 폴링을 이어 갈 이유가 없다.
            stopWatching()
            setNotice(TetrisDuelNoticeText.updateMine)
        default:
            Self.logger.notice("watch refused status=\(response.status.rawValue, privacy: .public)")
            noteWatchFailure(nil)            // not_signed_in·모르는 status 도 연속이면 내린다
        }
    }

    /// 관전 봉투의 사람 한 칸 → 화면 값. 행에 없는 칸은 로비 목록에서 빌린다.
    private func watchUser(_ row: TetrisWatchUserRow?) -> TetrisDuelUser? {
        peerUser(id: row?.id, displayName: row?.displayName, avatarURL: row?.avatarUrl,
                 character: row?.character, inMatch: true)
    }

    /// 예외 실패 경로. status 가 아니라 **throw 로 온** 실패(PGRST202·5xx·오프라인)와 모르는 응답 모양을 접는다.
    private func noteWatchFailure(_ error: (any Error)?) {
        if let error, isSchemaMissing(error) {
            // 서버에 `tetris_watch` 자체가 아직 없다. **관전 입구만** 잠근다 —
            // `noteServerMissing()` 을 부르면 관전 함수 하나 때문에 1:1 테트리스 전체가 잠긴다.
            stopWatching()
            setNotice(TetrisDuelNoticeText.unavailable)
            watchRuntime.watchLockedAt = clock()      // `stopWatching` 이 장부를 비운 **뒤**에 적는다
            if !watchUnavailable { watchUnavailable = true }
            return
        }
        Self.logger.notice("watch request failed")
        let runtime = watchRuntime
        runtime.watchFailureStreak += 1
        guard runtime.watchFailureStreak >= Self.watchFailureLimit else { return }
        stopWatching()
        setNotice(TetrisDuelNoticeText.checkConnection)
    }

    // MARK: 폴링 훅 — TetrisDuelStore.pollTick(at:) · windowDidShow() 가 부른다

    /// 안전망 한 걸음: 관전 중이면 2초마다 판. 관전 중이 아니면 잠겼던 입구를 로비 주기에 한 번 풀어 준다.
    /// `true` 를 돌려주면 "관전이 이 걸음을 가져갔다" 는 뜻이고 부르는 쪽은 순위를 돌리지 않는다.
    @discardableResult
    package func pollWatch(at now: Date) async -> Bool {
        guard spectatorFeaturesEnabled, phase == .lobby else { return false }
        guard spectating != nil else {
            // ★ 관전 잠금을 로비 주기(30초)에 **한 번 풀어 준다.** `watchUnavailable` 은 `startWatching` 을 문 앞에서
            //   막으므로 자기가 자기를 열 수 없다 — 안 풀면 서버가 올라와도 로그아웃까지 잠긴 채 남는다.
            //   풀어 두면 최악이 "30초에 404 한 번" 이고, 그사이 서버가 올라오면 첫 성공이 잠금을 내린다.
            if watchUnavailable,
               now.timeIntervalSince(watchRuntime.watchLockedAt) >= Self.lobbyPollSeconds {
                watchUnavailable = false
            }
            return false
        }
        if shouldPollWatch, now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.watchPollSeconds {
            await refreshWatch()
        }
        return true
    }

    /// 창이 다시 보였다: 관전 중이면 즉시 한 번(로비 목록과 같은 1초 dedupe).
    package func spectatorWindowDidShow(at now: Date) {
        guard shouldPollWatch,
              now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.reloadDedupeSeconds else { return }
        Task { [weak self] in await self?.refreshWatch() }
    }

    // MARK: 순수 매퍼

    /// 응답 → 다음 관전 상태(순수). 사람 둘·시각 셋은 호출부가 스토어 경계(`peerUser`·`deviceDate`)로 만들어 넘긴다.
    /// nil = 이 판 응답이 아니다(둘째 자물쇠).
    ///
    /// ★ **결과를 지어내지 않는다**: `result`·`endReason`·`finishedAt` 은 `status == "finished"` 일 때만 찬다.
    package nonisolated static func spectateState(
        applying response: TetrisWatchResponse, to previous: TetrisSpectateState,
        a: TetrisDuelUser?, b: TetrisDuelUser?, aLastSeenAt: Date?, bLastSeenAt: Date?,
        startedAt: Date?, finishedAt: Date?
    ) -> TetrisSpectateState? {
        guard let row = response.match, row.id?.lowercased() == previous.id else { return nil }
        let status = row.status ?? ""
        guard status == "active" || status == "finished" else { return nil }
        let isFinished = status == "finished"

        var next = previous
        if let stake = row.stake { next.stake = stake }
        next.a = spectateSide(from: response.a, user: a ?? previous.a.user,
                              lastSeenAt: aLastSeenAt, previous: previous.a)
        next.b = spectateSide(from: response.b, user: b ?? previous.b.user,
                              lastSeenAt: bLastSeenAt, previous: previous.b)
        next.startedAt = startedAt
        next.isFinished = isFinished
        // 진행 중이면 결과 칸은 **비운 채로 둔다**. 서버가 판을 닫기 전까지 승패는 없다.
        next.result = isFinished ? row.result : nil
        // 승자도 같은 규약이다. 무승부면 서버가 null 을 싣고, 옛 서버는 이 칸 자체가 없어 nil 이 된다 —
        // 둘 다 "승자를 모른다" 로 떨어져 화면이 승자를 말하지 않는다(지어내는 것보다 낫다).
        next.winnerUserID = isFinished ? row.winner?.lowercased() : nil
        next.endReason = isFinished ? row.reason.flatMap(TetrisDuelEndReason.init(rawValue:)) : nil
        next.finishedAt = isFinished ? finishedAt : nil
        next.hasServerState = true
        return next
    }

    /// 한 자리의 값(순수). **판 글자는 손대지 않는다** — 길이 200·글자 집합 `. I J L O S T Z G` 를 통과하면 그대로 싣고,
    /// 어긋나면 **그 자리의 판만** nil 로 접는다(반대쪽과 이 자리의 숫자들은 산다 — 앱이 터지면 안 된다).
    package nonisolated static func spectateSide(
        from row: TetrisWatchSideRow?, user: TetrisDuelUser?, lastSeenAt: Date?, previous: TetrisSpectateSide
    ) -> TetrisSpectateSide {
        let cells = row?.board.flatMap(TetrisDuelBoard.decode)
        return TetrisSpectateSide(
            user: user ?? previous.user,
            board: cells == nil ? nil : row?.board,
            cells: cells,
            lines: row?.lines ?? previous.lines,
            pending: row?.pending ?? previous.pending,
            attackSent: row?.garbageSent ?? previous.attackSent,
            toppedOut: row?.toppedOut ?? previous.toppedOut,
            lastSeenAt: lastSeenAt ?? previous.lastSeenAt)
    }
}
