import Foundation

// 아잉 마작 스토어 — 울기 답(SPEC §4.5). 울기 답은 seq·사건·초인종을 만들지 않으므로(§8) 한 창 안에서 단조여야 한다
// (가드 (h) — `answeredWindowIDs`, CC-26). `window_closed` 는 문구 없이 프롬프트를 내린다(가드 (e) — 실린 state 가 말한다).
// 비행 잠금은 `isAnsweringCall` 하나 — `isWorking` 과 따로라 패스가 막히지 않는다(MCL:126).

extension MahjongStore {
    /// 울기(론·퐁·대명깡·치). `tiles` 는 손에서 낼 패 id(론은 []).
    /// `tiles` 가 비었고 그 종류의 조합이 둘 이상이면(치 조합·적5 고르기) 보내지 않고 고르기 줄을 펼친다(`chiChoicesOpen`),
    /// 하나뿐이면 그 조합을 보낸다.
    package func call(_ kind: MahjongClaimKind, tiles: [MahjongTile]) async {
        if showsPractice {   // 연습판 — 엔진에 바로
            practiceCall(kind, tiles: tiles)
            return
        }
        guard let (current, call) = openServerCall, let chosen = chooseCallTiles(kind, tiles: tiles, call: call) else { return }
        await sendCall(kind.rawValue, tiles: chosen, call: call, matchID: current.id)
    }

    /// 울기 조합 고르기(서버·연습 같은 규칙) — 고를 것이 둘 이상이면 고르기 줄을 펼치고 nil.
    func chooseCallTiles(_ kind: MahjongClaimKind, tiles: [MahjongTile], call: MahjongDecision.Call) -> [MahjongTile]? {
        var chosen = tiles.sorted()
        switch kind {
        case .ron:
            guard call.ron else { return nil }
            chosen = []
        case .pon, .minkan, .chi:
            let options = Self.options(of: kind, in: call).map { $0.sorted() }
            if chosen.isEmpty {
                if options.count > 1 {
                    if riichiArmed { riichiArmed = false }
                    if !chiChoicesOpen { chiChoicesOpen = true }
                    return nil
                }
                guard let only = options.first else { return nil }
                chosen = only
            }
            guard options.contains(chosen) else { return nil }
        }
        return chosen
    }

    /// 넘기기.
    package func passCall() async {
        if showsPractice {
            if case .call(let call)? = practice?.payload.myDecision, call.answered == nil {
                if chiChoicesOpen { chiChoicesOpen = false }
                practiceAnswer(.pass)
            }
            return
        }
        guard let (current, call) = openServerCall else { return }
        await sendCall(MahjongClaimAnswer.pass.rawValue, tiles: [], call: call, matchID: current.id)
    }

    /// 지금 답할 수 있는 서버 울기 창(아직 안 답했고, 이 기기에서 답을 보내지 않은 창).
    var openServerCall: (MahjongStateMatch, MahjongDecision.Call)? {
        guard !isAnsweringCall, let payload = match, let current = payload.match, current.matchStatus == .active,
              case .call(let call)? = payload.myDecision, call.answered == nil,
              !answeredWindowIDs.contains(Self.windowKey(matchID: current.id, windowID: call.windowId)) else { return nil }
        return (current, call)
    }

    /// 종류별 조합 목록(서버가 준 것 그대로).
    nonisolated static func options(of kind: MahjongClaimKind, in call: MahjongDecision.Call) -> [[MahjongTile]] {
        switch kind {
        case .ron: return call.ron ? [[]] : []
        case .pon: return call.pon
        case .minkan: return call.minkan
        case .chi: return call.chi
        }
    }

    /// call 한 번 — 장부(보낼 때) · 답 적기(요청 직전, 가드 (h)) · `isAnsweringCall` · 요청 마감 · 응답 처리.
    func sendCall(_ answer: String, tiles: [MahjongTile], call: MahjongDecision.Call, matchID: String) async {
        guard host?.session != nil else { return }
        noteOwnsMatch(matchID)
        noteCallAnswered(matchID: matchID, windowID: call.windowId, answer: answer)
        if chiChoicesOpen { chiChoicesOpen = false }
        callToken &+= 1
        let token = callToken
        isAnsweringCall = true
        let generation = resetGeneration
        defer { if generation == resetGeneration, token == callToken, isAnsweringCall { isAnsweringCall = false } }
        let ticket = issueTicket()
        let windowID = call.windowId
        let result = await performWithin(requestDeadlineSeconds(deadlineMs: call.deadlineMs), {
            try await $0.mahjongCallAnswer(
                accessToken: $1, matchID: matchID, windowID: windowID, action: answer, tiles: tiles)
        })
        await handleDecisionResponse(result, action: .call, ticket: ticket, matchID: matchID)
    }

    /// 이 창에 답했다고 적는다(요청 직전). 늦게 온 `answered == nil` 조회가 프롬프트를 되살리지 않게 한다(가드 (h)).
    func noteCallAnswered(matchID: String, windowID: Int, answer: String) {
        let key = Self.windowKey(matchID: matchID, windowID: windowID)
        answeredWindowIDs.insert(key)
        answeredWindowAnswers[key] = answer
    }
}
