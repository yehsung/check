import Foundation

// 아잉 마작(내부 이름 mahjong) 규칙 — 패·표기·도라. 4인 리치 마작.
// 직접 작성, 외부 판정 코드 없음 — 정본 rules.md MJ-01~MJ-56, 대조 reference.py · cases.json(설계 mj/SPEC.md §2 · §4.1).
//
// ── 쌍둥이 ──
// 서버(plpgsql `mahjong_*`)·이 파일들(MahjongTiles·Hand·Scoring·Rules·Clock)·reference.py 가 같은 판정을 따로 한다.
// 이름 대응은 SPEC §2.1 표가 정본이다. 공개 표면(이름·서명)은 다른 갈래(판 진행·봇·스토어·화면)와의 계약이다 —
// 바꾸려면 SPEC 부터 고친다(시험 MahjongContractTests 가 서명을 컴파일로 잰다).
//
// ── 표기(MJ-03) ──
// 패 한 장 = 물리 패 번호 id 정수 0~135(id = kind*4 + c). 적5 = c 0 인 5만·5통·5삭 = id 16·52·88.
// 종류 kind = id / 4 (0~33: 만 0~8 · 통 9~17 · 삭 18~26 · 동남서북백발중 27~33).
// **id 와 종류를 섞지 않는다**(SPEC §2.2): 손패·강·부로는 id(`MahjongTile`), 대기·후리텐·쿠이카에·도라는 종류(`Int`).
// 적5 와 보통 5 는 종류로 같다(MJ-02). 목록은 오름차순.
// 문자열(`123m406p…`)은 코퍼스·시험·진단에만 쓴다.

/// 패 한 장 — 물리 패 번호(0~135). Codable = id 정수 하나(와이어 그대로).
package nonisolated struct MahjongTile: Hashable, Comparable, Sendable, Codable {
    /// 0...135.
    package let id: Int

    /// 범위 밖(−1·136…)은 nil.
    package init?(id: Int) {
        guard (0...135).contains(id) else { return nil }
        self.id = id
    }

    /// 종류 0~33 = id / 4.
    package var kind: Int { id / 4 }

    /// 적5 — id ∈ {16, 52, 88}(MJ-02).
    package var isRed: Bool { id == 16 || id == 52 || id == 88 }

    package var suit: MahjongSuit { MahjongSuit.of(kind: kind) }

    /// 수패 숫자 1~9. 자패는 nil.
    package var number: Int? { kind < 27 ? kind % 9 + 1 : nil }

    /// "5m"·"0m"(적5)·"7z" — 진단·시험용.
    package var token: String {
        if isRed { return "0" + String(MahjongTiles.suitLetter(kind: kind)) }
        return MahjongTiles.token(kind: kind)
    }

    package static func < (lhs: MahjongTile, rhs: MahjongTile) -> Bool { lhs.id < rhs.id }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        guard let tile = MahjongTile(id: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "패 id 범위 밖(0~135)")
        }
        self = tile
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// 색. 만·통·삭·자패.
package nonisolated enum MahjongSuit: Int, Sendable {
    case man, pin, sou, honor

    /// 종류 → 색. 0~8 만 · 9~17 통 · 18~26 삭 · 27~33 자패.
    static func of(kind: Int) -> MahjongSuit {
        kind < 27 ? (MahjongSuit(rawValue: kind / 9) ?? .honor) : .honor
    }
}

/// 바람. 와이어·코퍼스 값 'E'·'S'·'W'·'N'(= 1z~4z).
package nonisolated enum MahjongWind: String, Codable, Sendable, CaseIterable {
    case east = "E", south = "S", west = "W", north = "N"
}

/// 패 문자열·장수·도라(reference parse·physical_ids·counts34·dora_of_indicator·tiles_str).
package nonisolated enum MahjongTiles {
    /// MJ-03 문자열 → 패. reference `parse` + `physical_ids` 와 같은 id 배정 — 같은 종류는 c 가 작은 것부터,
    /// 적5('0') 는 c 0, 보통 5 는 c 1~3. 모르는 글자·숫자 없는 색 글자·'0z'·'8z'·'9z'·같은 패 다섯 장(보통 5 는 넷)은 nil.
    /// 빈 문자열은 빈 목록. 공백은 건너뛴다.
    package static func parse(_ text: String) -> [MahjongTile]? {
        var digits: [Int] = []
        var taken = Set<Int>()
        var out: [MahjongTile] = []
        for ch in text where ch != " " {
            if let d = ch.wholeNumberValue, ch.isASCII {
                digits.append(d)
                continue
            }
            guard let offset = suitOffset(ch), !digits.isEmpty else { return nil }
            for d in digits {
                let red = d == 0
                if ch == "z" && !(1...7).contains(d) { return nil }
                let k = offset + (red ? 5 : d) - 1
                let candidates: [Int]
                if red {
                    candidates = [k * 4]
                } else if k == 4 || k == 13 || k == 22 {
                    candidates = [k * 4 + 1, k * 4 + 2, k * 4 + 3]
                } else {
                    candidates = [k * 4, k * 4 + 1, k * 4 + 2, k * 4 + 3]
                }
                guard let id = candidates.first(where: { !taken.contains($0) }), let tile = MahjongTile(id: id) else { return nil }
                taken.insert(id)
                out.append(tile)
            }
            digits.removeAll()
        }
        return digits.isEmpty ? out : nil
    }

    /// 종류 34칸 장수(적5 는 5 로 센다).
    package static func counts34(_ tiles: [MahjongTile]) -> [Int] {
        var counts = Array(repeating: 0, count: 34)
        for tile in tiles { counts[tile.kind] += 1 }
        return counts
    }

    /// MJ-10 표시패 종류의 다음 종류. 수패 9→1, 동→남→서→북→동, 백→발→중→백. 범위 밖(0~33 아님)은 그대로 돌려준다.
    package static func doraKind(ofIndicator kind: Int) -> Int {
        guard (0...33).contains(kind) else { return kind }
        if kind < 27 { return kind % 9 == 8 ? kind - 8 : kind + 1 }
        if kind <= 30 { return kind == 30 ? 27 : kind + 1 }
        return kind == 33 ? 31 : kind + 1
    }

    /// 종류 목록 → 정렬한 "123m45p" 꼴(적5 정보 없음, 진단). reference `tiles_str`. 범위 밖 종류는 건너뛴다.
    package static func text(kinds: [Int]) -> String {
        var groups: [Character: [Int]] = [:]
        for k in kinds.sorted() where (0...33).contains(k) {
            groups[suitLetter(kind: k), default: []].append(k)
        }
        var out = ""
        for letter in ["m", "p", "s", "z"] as [Character] {
            guard let ks = groups[letter], !ks.isEmpty else { continue }
            for k in ks { out += String(digit(kind: k)) }
            out.append(letter)
        }
        return out
    }

    // MARK: - 내부 표기 도움

    static func suitOffset(_ ch: Character) -> Int? {
        switch ch {
        case "m": 0
        case "p": 9
        case "s": 18
        case "z": 27
        default: nil
        }
    }

    static func suitLetter(kind: Int) -> Character {
        kind >= 27 ? "z" : (["m", "p", "s"] as [Character])[kind / 9]
    }

    static func digit(kind: Int) -> Int {
        kind >= 27 ? kind - 26 : kind % 9 + 1
    }

    /// 종류 → 보통 패 토큰("5m"·"7z"). reference `tok_of`.
    static func token(kind: Int) -> String {
        String(digit(kind: kind)) + String(suitLetter(kind: kind))
    }

    /// 요구패(1·9·자패) 종류. reference `YAOCHU`.
    static let yaochu: [Int] = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
    /// 바람패 종류(동남서북).
    static let winds: [Int] = [27, 28, 29, 30]
}

/// 부로 종류. 와이어 MELD.type 값 그대로.
package nonisolated enum MahjongMeldType: String, Codable, Sendable {
    case chi, pon, minkan, kakan, ankan
}

/// 부로 한 묶음 = 와이어 MELD `{type, tiles, called, from_seat}`(키는 카멜 — 인코더·디코더가 스네이크로 바꾼다).
/// 와이어 **디코드**는 이 타입으로 바로 하지 않는다(모르는 type 하나에 state 가 통째로 실패) — 스토어의 원문 MahjongWireMeld 가
/// `var meld: MahjongMeld?` 로 잇는다(SPEC §4.1 끝 · §4.4, CC-07).
package nonisolated struct MahjongMeld: Equatable, Hashable, Sendable, Codable {
    package let type: MahjongMeldType
    /// 묶음의 패 id(깡은 4장).
    package let tiles: [MahjongTile]
    /// 남에게서 가져온 패. 암깡은 nil.
    package let called: MahjongTile?
    /// 가져온 자리(0~3). 암깡은 nil.
    package let fromSeat: Int?

    package init(type: MahjongMeldType, tiles: [MahjongTile], called: MahjongTile?, fromSeat: Int?) {
        self.type = type
        self.tiles = tiles
        self.called = called
        self.fromSeat = fromSeat
    }
}
