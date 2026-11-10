import CheckCore
import Foundation
import Observation

// 1:1 알까기 폰 판 모델(1.0.18) — 맥 `AlkkagiLocalModel`(Sources/check/AlkkagiGameView.swift)을 폰으로 옮긴 것.
// 판 진행 · 조준 · 굴림 되살리기(서버 시각 따라잡기 · 끝난 판 먼저 오면 마저 굴리기) · 멈칫 · 숨긴 배치 끌기는 **맥과 같은 식**이다 —
// 같은 서버 판을 두 기기가 다르게 그리면 안 된다. 폰에서 빠진 것: 소리(폰 앱엔 소리가 없다 — 남의 음악을 끊지 않게)와 판 중 대화
// (맥도 판 화면에서 뺐다 — D23). 진동은 `haptic` 갈래로 iOS 화면이 낸다(맥 `NSHapticFeedbackManager` 자리).
// 서버 판이면 `onlineStore` 가 있고, 없으면 한 폰에서 둘이 번갈아 두는 연습 판이다(맥 [연습하기] — 루비 · 전적에 남지 않는다).
// 이 파일은 SwiftUI 를 모른다 — 맥 스위트가 값으로 잰다(`V1018AlkkagiPhoneTests`).

/// 판 모델이 화면에 부탁하는 진동.
package enum AlkkagiPhoneHaptic: Equatable, Sendable {
    /// 쏠 돌을 잡았다.
    case select
    /// 힘이 한 칸(25%) 더 찼다.
    case power
    /// 연습 판에서 돌을 놓았다.
    case place
    /// 놓아서 날아갔다(세기 0~1).
    case launch(Double)
    /// 세게 부딪혔다(세기 0~1).
    case impact(Double)
}

package struct AlkkagiPhoneHit: Equatable, Sendable {
    package let position: AlkkagiVector
    package let strength: Double
    package let ringOut: Bool
    package var age = 0.0
}

package struct AlkkagiPhoneFall: Equatable, Sendable {
    package let position: AlkkagiVector
    package let owner: AlkkagiGame.Player
    package let outward: AlkkagiVector
    package var age = 0.0
}

package struct AlkkagiPhoneLaunch: Equatable, Sendable {
    package let stoneID: Int
    package let direction: AlkkagiVector
    package let power: Double
    package var age = 0.0
}

@MainActor
@Observable
package final class GamesAlkkagiBoardModel {
    package var game = AlkkagiGame()
    package var selectedID: Int?
    package var pull = AlkkagiVector(x: 0, y: 0)
    package var placementID: Int? = 0
    package var dragPlacementID: Int?
    package var placementPoint: AlkkagiVector?
    package var notice: String?
    package private(set) var hits: [AlkkagiPhoneHit] = []
    package private(set) var falls: [AlkkagiPhoneFall] = []
    package private(set) var launch: AlkkagiPhoneLaunch?
    package private(set) var time = 0.0
    package private(set) var jolt = 0.0
    /// 서버 판(없으면 연습 판).
    package private(set) var onlineStore: AlkkagiOnlineStore?
    /// 화면이 단다(iOS 진동). 시험은 엿듣는다.
    @ObservationIgnored package var haptic: ((AlkkagiPhoneHaptic) -> Void)?
    @ObservationIgnored package var hitStopEnabled = true

    @ObservationIgnored private var lastTime: TimeInterval?
    @ObservationIgnored private var clockTime = 0.0
    @ObservationIgnored private var powerBand = 0
    @ObservationIgnored private var gestureIsActive = false
    @ObservationIgnored private var ignoresCurrentGesture = false
    @ObservationIgnored private var onlineRevision = -1
    @ObservationIgnored private var onlineMatchID: String?
    @ObservationIgnored private var onlineReplayElapsed = 0.0
    /// 온라인 굴림 재생: 이 판에서 **화면 시계로** 되살리는 쏘기 id(맥 `replayShotID` 와 같은 뜻 — 제보 #9 '버벅임' 고침 그대로).
    @ObservationIgnored private var replayShotID: String?
    /// 굴림이 끝나기 전에 온 '굴림 뒤' 판(revision) — 남은 굴림을 마저 굴린 뒤 받는다.
    @ObservationIgnored private var deferredRevision: Int?
    @ObservationIgnored private var hitStop = 0.0
    @ObservationIgnored private var hitStopSpent = 0.0

    package static let maxHitStopPerShot = 0.16
    package static let maxReplayLag = 0.6
    package static let replayCatchUpRate = 0.5
    package static let replayDrainRate = 1.0
    package static let maxReplayDrain = 1.2

    package init() {}

    // MARK: 읽는 값

    package var isOnline: Bool { onlineStore != nil }
    package var myColor: AlkkagiGame.Player { onlineStore?.state?.myColor ?? .black }
    package var canInteract: Bool { onlineStore.map { $0.canPlace || $0.canShoot } ?? true }
    package var selectedStone: AlkkagiGame.Stone? { game.stones.first { $0.id == selectedID && $0.isPlaced && !$0.isOut } }
    package var power: Double { min(1, pull.length / AlkkagiGame.maxPull) }
    package var remainingSeconds: Double {
        if let onlineStore { return onlineStore.remainingSeconds }
        return game.phase == .placing ? game.placementRemaining : game.turnRemaining
    }
    package var launchRecoil: AlkkagiVector {
        guard let launch else { return AlkkagiVector(x: 0, y: 0) }
        return launch.direction * (-sin(launch.age * 38) * exp(-launch.age * 17) * launch.power * 6)
    }

    /// 상태 한 줄(맥 `status` 와 같은 서열 — 폰 손짓 글자만 다르다).
    package var status: String {
        if let onlineStore, let state = onlineStore.state {
            if onlineStore.isBusy { return AlkkagiPhoneText.waitBusy }
            if state.phase == .finished { return AlkkagiPhoneText.outcomeTitle(onlineStore.outcome) }
            if state.phase == .rolling { return AlkkagiPhoneText.rolling }
            if state.phase == .placing {
                return state.myReady ? AlkkagiPhoneText.placingReadyWaiting : AlkkagiPhoneText.placingMine(state.myColor)
            }
            if !onlineStore.isMyTurn {
                let peer = state.currentPlayer == .black ? state.black : state.white
                return AlkkagiPhoneText.opponentTurn(name: peer.displayName)
            }
        }
        switch game.phase {
        case .placing: return AlkkagiPhoneText.placingPractice(game.currentPlayer)
        case .aiming: return selectedID == nil ? AlkkagiPhoneText.aimHint(game.currentPlayer) : AlkkagiPhoneText.aimRelease
        case .rolling: return AlkkagiPhoneText.rolling
        case .finished: return AlkkagiPhoneText.practiceResult(game.result)
        }
    }

    // MARK: 손짓(판 좌표 — 화면이 pt 를 판 600 칸으로 바꿔 넘긴다)

    package func aim(start: AlkkagiVector, translation: AlkkagiVector) {
        gestureIsActive = true
        guard !ignoresCurrentGesture, canInteract else { return }
        if game.phase == .placing {
            if dragPlacementID == nil {
                dragPlacementID = game.stones.first {
                    $0.owner == game.currentPlayer && $0.isPlaced && !$0.isOut && ($0.position - start).length < AlkkagiGame.stoneRadius * 1.4
                }?.id ?? placementID ?? game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
            }
            guard dragPlacementID != nil else { return }
            placementPoint = start + translation
            notice = nil
            return
        }
        guard game.phase == .aiming else { return }
        if selectedID == nil {
            // 손가락은 마우스보다 굵다 — 잡는 반경을 맥(1.5배)보다 조금 넓힌다(1.9배 = 판 600 칸에서 38).
            selectedID = game.stones.filter {
                $0.isPlaced && !$0.isOut && $0.owner == game.currentPlayer && ($0.position - start).length < AlkkagiGame.stoneRadius * 1.9
            }.min { ($0.position - start).length < ($1.position - start).length }?.id
            if selectedID != nil { haptic?(.select) }
        }
        guard selectedID != nil else { return }
        pull = translation.length > AlkkagiGame.maxPull ? translation * (AlkkagiGame.maxPull / translation.length) : translation
        let band = Int(power * 4)
        if band > powerBand { haptic?(.power) }
        powerBand = band
    }

    package func release() {
        defer { finishGesture() }
        guard !ignoresCurrentGesture, canInteract else { return }
        if game.phase == .placing {
            guard let id = dragPlacementID, let at = placementPoint else { return }
            if let onlineStore {
                guard game.canPlace(stoneID: id, at: at) else {
                    notice = AlkkagiPhoneText.placementInvalid
                    return
                }
                Task { [weak self] in await onlineStore.place(stoneID: id, at: at); self?.synchronizeOnline(force: true) }
                return
            }
            if game.placeStone(stoneID: id, at: at) {
                placementID = game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
                notice = nil
                haptic?(.place)
            } else {
                notice = AlkkagiPhoneText.placementInvalid
            }
            return
        }
        guard let id = selectedID, selectedStone != nil else { return }
        let shotPull = pull
        let shotPower = power
        let actionID = UUID()
        if game.shoot(stoneID: id, pull: pull) {
            launch = AlkkagiPhoneLaunch(stoneID: id, direction: pull * (-1 / pull.length), power: shotPower)
            hitStop = 0; hitStopSpent = 0
            haptic?(.launch(0.3 + shotPower * 0.6))
            if let onlineStore {
                replayShotID = actionID.uuidString
                deferredRevision = nil
                onlineReplayElapsed = 0
                Task { [weak self] in
                    await onlineStore.shoot(stoneID: id, pull: shotPull, actionID: actionID)
                    self?.synchronizeOnline(force: true)
                }
            }
        }
    }

    package func cancelAim() {
        if gestureIsActive { ignoresCurrentGesture = true }
        selectedID = nil; pull = AlkkagiVector(x: 0, y: 0); powerBand = 0
        dragPlacementID = nil; placementPoint = nil
    }

    package func finishGesture() {
        cancelAim()
        gestureIsActive = false
        ignoresCurrentGesture = false
    }

    package func confirmPlacement() {
        if let onlineStore {
            Task { [weak self] in await onlineStore.confirmPlacement(); self?.synchronizeOnline(force: true) }
            return
        }
        let old = game
        if game.confirmPlacement() { changed(from: old) }
    }

    /// 연습 판 새로 시작(서버 판에서는 쓰지 않는다 — 끝난 서버 판은 [로비로]).
    package func restartPractice() {
        guard onlineStore == nil else { return }
        let physics = game.physics
        game.reset(); game.physics = physics; cancelAim(); placementID = 0; notice = nil
        hits = []; falls = []; launch = nil; jolt = 0; lastTime = nil; clockTime = 0
    }

    private func changed(from old: AlkkagiGame) {
        guard !isOnline else { return }
        guard old.phase != game.phase || old.currentPlayer != game.currentPlayer else { return }
        cancelAim(); notice = nil; clockTime = 0
        if old.phase == .placing {
            placementID = game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
        }
    }

    // MARK: 걸음(화면 주사율 — TimelineView 가 부른다)

    package func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        defer { lastTime = now }
        guard let lastTime else { return }
        let elapsed = max(0, now - lastTime)
        let dt = min(1.0 / 20, elapsed)
        var rollDt = dt
        let frozen = hitStop > 0
        if frozen {
            let used = min(hitStop, dt)
            hitStop -= used
            rollDt = dt - used
        }
        var impacts: [AlkkagiGame.Impact] = []
        let old = game
        if let onlineStore {
            synchronizeOnline()
            if game.phase == .rolling, replayShotID != nil {
                var step = rollDt
                if !frozen {
                    if let behind = replayLag(onlineStore) {
                        if behind > Self.maxReplayLag {
                            // 신호를 놓쳐 아주 늦게 안 판 — 넘는 만큼만 효과 없이 건너뛴다.
                            _ = advanceReplay(by: behind - Self.maxReplayLag)
                        }
                        if behind > 0.001 { step += min(behind, dt * Self.replayCatchUpRate) }
                    } else if deferredRevision != nil {
                        step += dt * Self.replayDrainRate
                    }
                }
                if step > 0 { impacts = advanceReplay(by: step) }
                if game.phase != .rolling, deferredRevision != nil {
                    deferredRevision = nil
                    synchronizeOnline(force: true)
                }
            }
        } else if game.phase == .placing || game.phase == .aiming {
            // 초 단위 글자는 5Hz 로만 갱신한다(맥과 같다). 화면 밖을 눌러도 제한 시간은 흐른다.
            clockTime += elapsed
            if clockTime >= 0.2 {
                let deadlineExpired = clockTime + 1e-9 >= remainingSeconds
                impacts = game.advance(dt: clockTime)
                clockTime = 0
                if deadlineExpired { cancelAim() }
            }
        } else if game.phase == .rolling, rollDt > 0 {
            impacts = game.advance(dt: rollDt)
        }
        changed(from: old)
        guard !hits.isEmpty || !falls.isEmpty || launch != nil || !impacts.isEmpty || jolt > 0 else { return }
        time += dt
        let ageDt = frozen ? 0 : dt
        if var released = launch { released.age += ageDt; launch = released.age < 0.3 ? released : nil }
        hits = hits.compactMap { var h = $0; h.age += ageDt; return h.age < 0.32 ? h : nil }
        falls = falls.compactMap { var f = $0; f.age += ageDt; return f.age < 0.9 ? f : nil }
        jolt = max(0, jolt - dt * 9)
        for impact in impacts where impact.strength > 0.08 {
            hits.append(AlkkagiPhoneHit(position: impact.position, strength: impact.strength, ringOut: impact.isRingOut))
        }
        for stone in game.stones where stone.isOut && old.stones.first(where: { $0.id == stone.id })?.isOut == false {
            let p = stone.position
            let outward = AlkkagiVector(x: p.x < 0 ? -1 : (p.x > AlkkagiGame.boardSize ? 1 : 0),
                                        y: p.y < 0 ? -1 : (p.y > AlkkagiGame.boardSize ? 1 : 0))
            let edge = AlkkagiVector(x: min(AlkkagiGame.boardSize, max(0, p.x)), y: min(AlkkagiGame.boardSize, max(0, p.y)))
            falls.append(AlkkagiPhoneFall(position: edge, owner: stone.owner, outward: outward))
        }
        if let impact = impacts.max(by: { $0.strength < $1.strength }), impact.strength > 0.12 {
            jolt = max(jolt, pow(impact.strength, 1.3))
            if hitStopEnabled, !impact.isRingOut, impact.strength > 0.3, hitStopSpent < Self.maxHitStopPerShot {
                let stop = min(Self.maxHitStopPerShot - hitStopSpent, 0.03 + 0.05 * min(1, impact.strength))
                hitStop = max(hitStop, stop)
                hitStopSpent += stop
            }
            if impact.strength > 0.35 { haptic?(.impact(min(1, impact.strength))) }
        }
    }

    // MARK: 서버 판 맞추기(맥과 같은 식)

    /// 서버 굴림 시각보다 내 화면 굴림이 뒤처진 초(앞서면 음수). 서버가 같은 쏘기를 굴리는 중일 때만 — 아니면 nil.
    private func replayLag(_ store: AlkkagiOnlineStore) -> Double? {
        guard let state = store.state, state.phase == .rolling, let shot = state.shot,
              replayShotID?.caseInsensitiveCompare(shot.id) == .orderedSame, shot.startedAtMs.isFinite else { return nil }
        let serverElapsed = min(shot.duration, max(0, (store.estimatedServerNowMs - shot.startedAtMs) / 1_000))
        let lag = serverElapsed - onlineReplayElapsed
        return lag.isFinite ? lag : nil
    }

    private func advanceReplay(by seconds: Double) -> [AlkkagiGame.Impact] {
        var impacts: [AlkkagiGame.Impact] = []
        var remaining = seconds
        while remaining > 1e-9 && game.phase == .rolling {
            let slice = min(0.25, remaining)
            impacts += game.advance(dt: slice)
            remaining -= slice
            onlineReplayElapsed += slice
        }
        return impacts
    }

    package func attachOnline(_ store: AlkkagiOnlineStore?) {
        guard let store else { return }
        onlineStore = store
        synchronizeOnline(force: true)
    }

    package func synchronizeOnline(force: Bool = false) {
        guard let onlineStore, let state = onlineStore.state else { return }
        guard force || onlineMatchID != state.id || onlineRevision != state.revision else { return }
        // 굴림 뒤 판이 내 굴림보다 먼저 왔다 — 같은 쏘기를 마저 굴린 뒤 받는다(남은 굴림이 길면 바로 받는다).
        if state.phase != .rolling, onlineMatchID == state.id, game.phase == .rolling, replayShotID != nil,
           game.shotCount == state.shotCount {
            if deferredRevision == state.revision { return }
            var probe = game
            var left = Self.maxReplayDrain
            while probe.phase == .rolling && left > 0 { _ = probe.advance(dt: 0.25); left -= 0.25 }
            if probe.phase != .rolling {
                deferredRevision = state.revision
                return
            }
        }
        deferredRevision = nil
        // 상대의 숨긴 배치가 내 끌기를 끊지 않게.
        if !force, onlineMatchID == state.id, state.phase == .placing, !state.myReady,
           game.phase == .placing, game.currentPlayer == state.myColor, game.stones == state.stones {
            onlineRevision = state.revision
            return
        }
        cancelAim()
        notice = nil
        let keepsReplay = state.phase == .rolling
            && replayShotID?.caseInsensitiveCompare(state.shot?.id ?? "") == .orderedSame
            && game.shotCount == state.shotCount
        if state.phase == .rolling, !keepsReplay, let replay = state.shotReplayGame {
            game = replay
            replayShotID = state.shot?.id
            onlineReplayElapsed = 0
        } else if !keepsReplay, let canonical = state.canonicalGame(serverNowMs: onlineStore.estimatedServerNowMs) {
            game = canonical
            if state.phase != .rolling { replayShotID = nil }
            onlineReplayElapsed = 0
        }
        onlineMatchID = state.id
        onlineRevision = state.revision
        placementID = game.stones.first { $0.owner == state.myColor && !$0.isPlaced }?.id
    }
}
