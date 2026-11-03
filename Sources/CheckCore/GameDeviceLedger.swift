import Foundation

// 한 계정 여러 기기 — **이 기기가 연 1:1 판** 장부(2026-11-03).
//
// 제보 원문: "아니 이거 오목이나 미니게임 화면이 맥미니에도 동시에 열리는데 맥미니 꺼는 안 꺼져요".
// 1:1 판의 초인종(`gomoku__ring` · `chess__ring`)은 그 사람의 **모든 기기**로 간다. 받은 기기마다 판 상태를 읽고
// "판이 막 시작됐다"로 보아 창을 띄우고 주의를 끌었다 — 맥북에서 신청한 판이 놀던 맥미니에서도 열리고, 그 창은
// 사람이 맥미니로 가서 닫기 전까지 남았다. 내 차례 말풍선도 두 기기에서 같이 떴다.
//
// 그래서 창 띄우기 · 주의 · 말풍선은 **이 기기가 연 판**에서만 한다. 이 기기가 그 판을 연 것으로 치는 때:
// 이 기기에서 신청을 보냈다(ok) · 수락했다(ok) · 수를 뒀다. 사람이 다른 기기에서 창을 직접 열면 판은 그대로 보이고
// 거기서 두면 그 기기도 연 기기가 된다(장부에 오른다) — 막는 것은 **저절로** 열리는 것뿐이다.
//
// 테트리스의 같은 장부(`TetrisDuelStore` 머리말 ⑩ · `ownedMatches`)와 규칙이 같다. 테트리스는 서버 `my_device` 가 먼저고
// 이 장부는 옛 서버용 대비다. 오목·체스는 서버가 기기를 가르지 않으므로 이 장부만 본다.
// 아잉 큐브는 자기 장부(`RummyStore.engagedMatchIDs` — 머리말 ⑮)를 같은 뜻으로 쓴다.
//
// 장부는 **사용자별 키**다(같은 기기에서 계정을 바꿔도 앞 사람의 판을 열지 않는다). 앱 배선이 `defaults` 를 넣어 앱을
// 다시 켜도 산다 — 판 중에 앱을 다시 켠 기기가 자기 판을 못 알아보면 창이 안 떠서 시계를 흘린다.
// nil(테스트 기본)이면 이 값 안에만 산다 — 테스트가 실행기의 `.standard` 에 키를 흘리지 않게.

package struct GameDeviceLedger {
    /// 키 접두("gomoku" · "chess"). 게임마다 따로다 — 판 id 는 게임 표마다 따로 매겨진다.
    package let game: String
    /// 이만큼(초) 지난 기록은 버린다. 판이 끝나면 지우지만, 끝을 못 본 기록(앱을 끈 채 끝났다)이 쌓이지 않게 한다.
    package let ttlSeconds: TimeInterval
    /// 기록을 이만큼만 둔다(새것부터). 한 사람은 한 판만 하지만 신청·수락이 겹치는 창을 넉넉히 둔다.
    package let limit: Int
    /// 기록을 둘 곳. **앱 배선이 넣는다**(맥 `WorkTimerStore` · 폰 `MobileAppModel`).
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
