import Foundation

// 1:1 알까기 관전(SPEC v1.1 §3.5 `alkkagi_watch` · `alkkagi_watch_live` · §3.7 WATCH · §4.5). 틀은 뒤집기 `ReversiStoreWatch` 꼴 —
// `watch(matchID:)` → `alkkagi_watch_live` 2초 → `watched` · 끝난 판은 꼬리(180초) 동안 결과까지 · `stopWatching()` ·
// 주 스위치 `spectatorFeaturesEnabled`. 관전자는 대화를 안 받는다(설계 결정 D10). 숨긴 배치 중에는 돌이 [] 다.
// 와이어 디코딩은 `AlkkagiOnlineWire.swift`.
// 걸음: [관전] 누름과 함께 첫 조회 한 번 → 창이 보이고 안 가려진 동안 2초(가려지면 쉰다 — 조회 0). 내 판이 서면 관전을 내린다
// (스토어 `apply`) · 진행 중인 내 판이 있으면 관전을 시작하지 않는다 · 서버에 관전 함수가 없으면(PGRST202) 내린다 ·
// 창을 닫으면 내린다(`windowDidClose`).

/// 지금 보고 있는 남의 판(WATCH 모양 그대로). 흑이 아래(화면) — 판 그림 좌표는 판 화면과 같다.
package nonisolated struct AlkkagiWatchState: Identifiable, Equatable, Sendable {
    package var id: String
    package var revision: Int
    package var phase: AlkkagiMatchPhase
    package var currentPlayer: AlkkagiGame.Player
    package var black: AlkkagiPeer
    package var white: AlkkagiPeer
    package var blackReady: Bool
    package var whiteReady: Bool
    /// 둘 다 준비 전이면 [](숨긴 배치 — 관전자는 두 사람 돌을 다 못 본다).
    package var stones: [AlkkagiGame.Stone]
    package var deadlineMs: Double?
    package var shotCount: Int
    package var result: AlkkagiMatchResult?
    package var finishReason: String?
    /// 쏘기 되살리기(판 화면과 같은 `initial_stones` · `pull` · `steps` 재생).
    package var shot: AlkkagiShot?
    package var stake: Int?
    package var blackMissedTurns: Int
    package var whiteMissedTurns: Int
    package var forfeitAfter: Int
    package var finishedAtMs: Double?
    /// 관전자 수 — `alkkagi_watch_live` 만 싣는다(nil = 모름).
    package var watchers: Int?

    package init(id: String, revision: Int = 1, phase: AlkkagiMatchPhase, currentPlayer: AlkkagiGame.Player = .black,
                 black: AlkkagiPeer, white: AlkkagiPeer, blackReady: Bool = false, whiteReady: Bool = false,
                 stones: [AlkkagiGame.Stone] = [], deadlineMs: Double? = nil, shotCount: Int = 0,
                 result: AlkkagiMatchResult? = nil, finishReason: String? = nil, shot: AlkkagiShot? = nil,
                 stake: Int? = nil, blackMissedTurns: Int = 0, whiteMissedTurns: Int = 0, forfeitAfter: Int = 3,
                 finishedAtMs: Double? = nil, watchers: Int? = nil) {
        self.id = id
        self.revision = revision
        self.phase = phase
        self.currentPlayer = currentPlayer
        self.black = black
        self.white = white
        self.blackReady = blackReady
        self.whiteReady = whiteReady
        self.stones = stones
        self.deadlineMs = deadlineMs
        self.shotCount = shotCount
        self.result = result
        self.finishReason = finishReason
        self.shot = shot
        self.stake = stake
        self.blackMissedTurns = blackMissedTurns
        self.whiteMissedTurns = whiteMissedTurns
        self.forfeitAfter = forfeitAfter
        self.finishedAtMs = finishedAtMs
        self.watchers = watchers
    }

    package var isFinished: Bool { phase == .finished }

    /// 끝난 사유(서버 글자 → 열거). 끝나지 않았으면 nil.
    package var endReason: AlkkagiEndReason? {
        finishReason.map { AlkkagiEndReason(rawValue: $0) ?? .unknown }
    }
}

extension AlkkagiOnlineStore {
    /// 관전 걸음 간격(초 — 다수 2초, §4.3).
    package nonisolated static let watchPollSeconds: Double = 2

    /// 남의 판을 본다. 스위치가 꺼졌거나 id 가 uuid 가 아니면 아무것도 안 한다. 다른 판을 보던 중이면 그 판을 내린다.
    package func watch(matchID: String) {
        guard spectatorFeaturesEnabled, let id = UUID(uuidString: matchID),
              !(state.map { $0.phase != .finished } ?? false) else { return }
        if watchMatchID != id {
            watchGeneration &+= 1
            watchTask?.cancel()
            watchTask = nil
            if watched != nil { watched = nil }
        }
        watchMatchID = id
        startWatchPolling()
    }

    /// 관전을 내린다(로비로).
    package func stopWatching() {
        watchGeneration &+= 1
        watchTask?.cancel()
        watchTask = nil
        watchMatchID = nil
        if watched != nil { watched = nil }
    }

    /// 관전 응답을 옮긴다(ok 이고 같은 판일 때만 — 늦은 응답은 세대로 버린다).
    func applyWatch(_ response: AlkkagiResponse, matchID: UUID, generation: Int) {
        guard generation == watchGeneration, watchMatchID == matchID else { return }
        switch response.status {
        case .ok:
            guard let next = response.watch, UUID(uuidString: next.id) == matchID else { return }
            if let old = watched, old.id.caseInsensitiveCompare(next.id) == .orderedSame, old.revision > next.revision { return }
            if watched != next { watched = next }
        case .notFound:
            // 꼬리(180초)가 지났거나 볼 수 없는 판 — 관전을 내린다.
            stopWatching()
        default:
            break
        }
    }

    private func startWatchPolling() {
        guard watchTask == nil, let service, let matchID = watchMatchID else { return }
        let generation = watchGeneration
        let reset = resetGeneration
        watchTask = Task { @MainActor [weak self] in
            var isFirst = true
            while !Task.isCancelled {
                if !isFirst {
                    do { try await Task.sleep(for: .seconds(Self.watchPollSeconds)) } catch { return }
                }
                guard let self, reset == self.resetGeneration, generation == self.watchGeneration,
                      self.spectatorFeaturesEnabled else { return }
                // 창이 안 보이거나 가려졌으면 조회를 쉰다(첫 조회는 [관전] 누름과 함께 오므로 막지 않는다).
                let rests = !isFirst && !(self.isWindowVisible && !self.isWindowOccluded)
                isFirst = false
                if rests { continue }
                let response: AlkkagiResponse
                do {
                    response = try await service.call(.watchLive(matchID: matchID))
                } catch AlkkagiServiceError.serverMissing {
                    // 서버에 관전 함수가 아직 없다 — 2초마다 두드리지 않고 내린다.
                    guard reset == self.resetGeneration, generation == self.watchGeneration else { return }
                    self.stopWatching()
                    return
                } catch {
                    continue
                }
                guard reset == self.resetGeneration else { return }
                self.applyWatch(response, matchID: matchID, generation: generation)
                // 끝난 판이면 걸음을 멈추고 결과를 [나가기]까지 둔다(RV2-C-4 — 뒤집기 관전 꼴). 꼬리 180초 내내 2초마다
                // 관전 신호를 쓰다가 not_found 로 결과를 말없이 걷지 않게.
                if generation == self.watchGeneration, self.watched?.isFinished == true {
                    self.watchTask = nil
                    return
                }
            }
        }
    }
}
