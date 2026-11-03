import Foundation

// 아잉 마작 스토어 — 울기 답(SPEC §4.5). 울기 답은 seq·사건·초인종을 만들지 않으므로(§8) 한 창 안에서 단조여야 한다
// (가드 (h) — `answeredWindowIDs`, CC-26). `window_closed` 는 문구 없이 프롬프트를 내린다(가드 (e)).
// 비행 잠금은 `isAnsweringCall` 하나 — `isWorking` 과 따로라 패스가 막히지 않는다(MCL:126).

extension MahjongStore {
    /// 울기(론·퐁·대명깡·치). `tiles` 는 손에서 낼 패 id(론은 []).
    package func call(_ kind: MahjongClaimKind, tiles: [MahjongTile]) async {
        // C2: guard 지금 창의 선택지 · noteOwnsMatch · noteCallAnswered · mahjong_call · 요청 마감.
        _ = (kind, tiles)
    }

    /// 넘기기.
    package func passCall() async {
        // C2: mahjong_call 'pass'.
    }

    /// 이 창에 답했다고 적는다(요청 직전). 늦게 온 `answered == nil` 조회가 프롬프트를 되살리지 않게 한다(가드 (h)).
    func noteCallAnswered(matchID: String, windowID: Int, answer: String) {
        let key = Self.windowKey(matchID: matchID, windowID: windowID)
        answeredWindowIDs.insert(key)
        answeredWindowAnswers[key] = answer
    }
}
