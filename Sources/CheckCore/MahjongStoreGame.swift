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
        guard let incoming = payload.match, !incoming.isPractice else { return .ignored }
        // (a) 접은 판.
        if dismissedMatchIDs.contains(incoming.id) { return .ignored }
        noteServerClock(payload.serverNowMs)

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
            // 사건 꼬리 이어 붙이기 — 요청 seq 다음부터 와야 한다(아니면 구멍).
            if requestedSince > 0 {
                if let first = payload.events?.first?.seq, first > requestedSince + 1 { return .needsFull }
                next.events = Self.mergedEvents(held: match?.events ?? [], arriving: payload.events ?? [])
            }
        } else if requestedSince > 0 {
            // 다른 판의 일부 꼬리만 받았다 — 전체로 다시.
            return .needsFull
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

        match = next
        if let balance = next.rubyBalance {
            // C2: ⓓ predatesWrite 면 덮지 않는다.
            rubyBalance = balance
        }
        return .applied
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
            practice = nil
            showsPractice = false
            notice = MahjongNoticeText.practiceClosed
        }

        // 끝난 판을 처음 본 순간 한 번 — 장부에서 걷고, 무효 판이 아니면 판 끝 콜백.
        if let current, current.matchStatus.isTerminal, !(sameMatch && previous?.matchStatus.isTerminal == true) {
            dropOwnership(current.id)
            if current.matchStatus == .finished, !current.isVoid { onMatchFinished?() }
            // C2: 로비·순위 다시 읽기(⑯).
        }

        recomputePhase()
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

    // MARK: 폴링 걸음 · 깨우기(시험이 직접 밟는다 — 큐브 V0369RummyStoreTests 틀)

    /// 폴링 한 걸음(③ — 창이 탁자를 보일 때만, ⓑ 취소 밖 조회, ⓒ 걸음 사이 가드).
    package func pollTick(at now: Date) async {
        // C2: 로비 30초 · 방 10초 · 판 5초(구독)/1.5초(미구독) · 순위 60초.
        _ = now
    }

    /// 깨우기 판정(§3.7 (d) v1.0 표) — 결정 주인 `deadline+grace+100` · 박자 자리 `wake_at` · 나머지 `backup_at`.
    /// 창이 안 보여도 돈다 — 단 `ownsMatch` 판에서만.
    package func checkWake(at now: Date) {
        // C2: 깨우기 시각 계산 · 같은 seq 재시도 2회 상한.
        _ = now
    }

    // MARK: 내 차례 동작(act)

    /// 패를 버린다. 리치 무장이면 리치 선언 버림, 자리 비움이면 `comeBack()`(손패를 한 번 누르면 복귀 — 카드 ⑨).
    package func discard(_ tile: MahjongTile) async {
        // C2: 자리 비움 → comeBack · 무장 → 'riichi' · 아니면 'discard'(선택지 안에서만) · 장부 note · 요청 마감.
        _ = tile
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
        // C2: act 'tsumo'.
    }

    package func declareKyuushu() async {
        // C2: act 'kyuushu'.
    }

    /// 암깡(4장 id 묶음).
    package func ankan(_ tiles: [MahjongTile]) async {
        // C2: act 'ankan'.
        _ = tiles
    }

    /// 가깡(더할 패 id).
    package func kakan(_ tile: MahjongTile) async {
        // C2: act 'kakan'.
        _ = tile
    }

    /// 판 중 [나가기] = 자리 비움(카드 ⑨ 답 — 기권 아님).
    package func leaveTable() async {
        // C2: mahjong_leave(active) → state.
    }

    /// [돌아왔어요].
    package func comeBack() async {
        // C2: mahjong_back · too_fast → MahjongNoticeText.backTooFast.
    }

    /// 반응(⑬ — 2초 쿨다운 too_fast 는 조용히 버린다).
    package func sendReaction(_ key: String) async {
        // C2: mahjong_react.
        _ = key
    }
}
