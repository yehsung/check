import Foundation

// ⚠ 임시 다리 — 가지 `fix/game-window-one-device`(62ecdf73)의 `GameDeviceLedger` 가 main 에 들어오면 **이 파일을 지우고**
// `ReversiStore.deviceLedger` 의 타입을 `GameDeviceLedger` 로 바꾼다(`FLIP/MERGE-NOTES.md` 의 교체 절차). 그 타입과 공개 모양
// (init(game:ttlSeconds:limit:) · key(userID:) · owns(_:userID:now:) · note(_:userID:now:) · drop(_:userID:now:) · defaults)과
// 저장 키(`<game>.ownedMatches.<사용자 id 소문자>`) · 값 모양([판 id 소문자: epoch 초])이 **글자 하나까지 같다** — 바꿔 끼워도
// 이미 앱 defaults 에 적힌 기록을 그대로 읽는다. 동작을 고치려면 이 파일이 아니라 그 가지의 `GameDeviceLedger` 를 고친다.
//
// 뜻(그 가지 머리말 요약): 1:1 판의 초인종은 그 사람의 **모든 기기**로 간다. 받은 기기마다 "판이 막 시작됐다"로 보아 창을 띄우면
// 한 계정의 놀던 맥에서도 창이 열리고 사람이 가서 닫기 전까지 남는다. 그래서 창 띄우기 · 주의 · 말풍선은 **이 기기가 연 판**
// (이 기기에서 신청 ok · 수락 ok · 수를 둠)에서만 한다. 장부는 사용자별 키이고, 앱 배선이 `defaults` 를 넣어 앱을 다시 켜도 산다.
// nil(시험 기본)이면 이 값 안에만 산다 — 시험이 실행기의 `.standard` 에 키를 흘리지 않게.

package struct ReversiDeviceLedgerShim {
    /// 키 접두("reversi"). 게임마다 따로다 — 판 id 는 게임 표마다 따로 매겨진다.
    package let game: String
    /// 이만큼(초) 지난 기록은 버린다. 판이 끝나면 지우지만, 끝을 못 본 기록(앱을 끈 채 끝났다)이 쌓이지 않게 한다.
    package let ttlSeconds: TimeInterval
    /// 기록을 이만큼만 둔다(새것부터).
    package let limit: Int
    /// 기록을 둘 곳. **앱 배선이 넣는다**(맥 `WorkTimerStore`).
    package var defaults: UserDefaults?
    /// `defaults` 가 없을 때의 기록(사용자 id → [판 id: 기록한 벽시계 epoch 초]).
    private var inMemory: [String: [String: Double]] = [:]

    package init(game: String, ttlSeconds: TimeInterval, limit: Int = 8) {
        self.game = game
        self.ttlSeconds = ttlSeconds
        self.limit = limit
    }

    /// 기록 키(사용자별).
    package func key(userID: String) -> String {
        "\(game).ownedMatches.\(userID.lowercased())"
    }

    /// 이 기기가 이 판을 열었는가. 로그인 전이면 언제나 아니다.
    package func owns(_ matchID: String, userID: String?, now: Date) -> Bool {
        records(userID: userID, now: now)[matchID.lowercased()] != nil
    }

    /// 이 기기가 이 판을 열었다. 이미 있으면 처음 시각을 그대로 둔다.
    package mutating func note(_ matchID: String, userID: String?, now: Date) {
        let id = matchID.lowercased()
        guard !id.isEmpty else { return }
        var owned = records(userID: userID, now: now)
        guard owned[id] == nil else { return }
        owned[id] = now.timeIntervalSince1970
        store(owned, userID: userID)
    }

    /// 이 판의 기록을 지운다(끝났다). 없으면 아무것도 쓰지 않는다.
    package mutating func drop(_ matchID: String, userID: String?, now: Date) {
        var owned = records(userID: userID, now: now)
        guard owned.removeValue(forKey: matchID.lowercased()) != nil else { return }
        store(owned, userID: userID)
    }

    /// 지금 사람의 기록(유효 기간 안의 것만). 로그인 전이면 빈 표.
    private func records(userID: String?, now: Date) -> [String: Double] {
        guard let user = userID?.lowercased(), !user.isEmpty else { return [:] }
        let raw: [String: Double]
        if let defaults {
            raw = defaults.dictionary(forKey: key(userID: user)) as? [String: Double] ?? [:]
        } else {
            raw = inMemory[user] ?? [:]
        }
        let cutoff = now.timeIntervalSince1970 - ttlSeconds
        return raw.filter { $0.value >= cutoff }
    }

    /// 기록을 쓴다 — 새것부터 `limit` 개만.
    private mutating func store(_ owned: [String: Double], userID: String?) {
        guard let user = userID?.lowercased(), !user.isEmpty else { return }
        let kept = Dictionary(uniqueKeysWithValues: owned.sorted { $0.value > $1.value }.prefix(limit)
            .map { ($0.key, $0.value) })
        if let defaults {
            let key = key(userID: user)
            if kept.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(kept, forKey: key) }
        } else {
            inMemory[user] = kept.isEmpty ? nil : kept
        }
    }
}
