import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 패 표기(MJ-03) — id 배정·종류·적5·토큰·도라 감김(MJ-10). 서버(smallint 0~135, kind = id/4)와 reference
// `parse`+`physical_ids` 와 같은 배정이어야 코퍼스 문자열이 세 구현에서 같은 패가 된다.

@Suite("아잉 마작 패 — parse/id 배정 = reference · kind · isRed · token · 도라 감김")
struct MahjongTilesTests {
    // 없으면: id → 종류·색·숫자·적5 가 한 칸이라도 서버 규약(MJ-03)과 갈려 대기·후리텐·도라가 조용히 틀린다.
    @Test("136장 전부 — kind = id/4 · suit · number · isRed 는 16·52·88 만 · token 왕복")
    func allTiles() throws {
        var reds: [Int] = []
        for id in 0...135 {
            let t = try #require(MahjongTile(id: id))
            #expect(t.kind == id / 4)
            let expectedSuit: MahjongSuit = id < 36 ? .man : id < 72 ? .pin : id < 108 ? .sou : .honor
            #expect(t.suit == expectedSuit, "\(id)")
            #expect(t.number == (id < 108 ? (id / 4) % 9 + 1 : nil), "\(id)")
            if t.isRed { reds.append(id) }
            // token 을 다시 parse 하면 같은 종류·같은 적 여부(c 는 앞에서부터 배정되므로 id 는 c 최소)
            let back = try #require(MahjongTiles.parse(t.token)?.first, "\(t.token)")
            #expect(back.kind == t.kind && back.isRed == t.isRed, "\(t.token)")
        }
        #expect(reds == [16, 52, 88])
        #expect(MahjongTile(id: 52)!.token == "0p" && MahjongTile(id: 88)!.token == "0s" && MahjongTile(id: 53)!.token == "5p")
    }

    // 없으면: 같은 종류 여러 장·적5 가 섞인 문자열의 id 가 reference physical_ids 와 갈려 대조 손 시험이 엉뚱한 패를 쓴다.
    @Test("id 배정 — 같은 종류는 c 작은 것부터 · 적5 는 c0 · 보통 5 는 c1~3 · 한 문자열 안에서 이어 배정")
    func physicalIDs() {
        #expect(MahjongTiles.parse("1111m")?.map(\.id) == [0, 1, 2, 3])
        #expect(MahjongTiles.parse("505m")?.map(\.id) == [17, 16, 18], "적5 는 순서와 무관하게 c0")
        #expect(MahjongTiles.parse("0p0s")?.map(\.id) == [52, 88])
        #expect(MahjongTiles.parse("55p5p")?.map(\.id) == [53, 54, 55], "색 글자로 끊겨도 같은 산")
        #expect(MahjongTiles.parse("00m") == nil, "적5 는 색마다 한 장")
        #expect(MahjongTiles.parse("1234567z")?.map(\.id) == [108, 112, 116, 120, 124, 128, 132])
        #expect(MahjongTiles.parse("12 3m")?.map(\.id) == [0, 4, 8], "공백은 건너뛴다")
        // 기준선: 보통 5 는 넷째가 없다(적5 자리) — 같은 글자라도 5 가 아니면 넷째를 받는다.
        #expect(MahjongTiles.parse("5555s") == nil && MahjongTiles.parse("4444s") != nil)
    }

    // 없으면: 도라 감김(9→1 · 북→동 · 중→백, MJ-10)이 서버 mahjong_dora_kind 와 갈려 도라 판수가 틀린다.
    @Test("도라 감김 — 수패 9→1 · 동남서북 돌기 · 백발중 돌기 · 적5 표시패는 6")
    func doraWrap() {
        let map = (0..<34).map { MahjongTiles.doraKind(ofIndicator: $0) }
        for s in 0..<3 {
            for n in 0..<8 { #expect(map[s * 9 + n] == s * 9 + n + 1) }
            #expect(map[s * 9 + 8] == s * 9, "9→1")
        }
        #expect(Array(map[27...30]) == [28, 29, 30, 27], "동→남→서→북→동")
        #expect(Array(map[31...33]) == [32, 33, 31], "백→발→중→백")
        #expect(MahjongTiles.doraKind(ofIndicator: MahjongTile(id: 16)!.kind) == 5, "적5 표시패의 도라는 6만")
        #expect(MahjongTiles.doraKind(ofIndicator: 34) == 34 && MahjongTiles.doraKind(ofIndicator: -1) == -1, "범위 밖은 그대로")
        #expect(Set(map).count == 34, "기준선: 감김은 34종의 순열")
    }

    // 없으면: 진단 글자(text)가 reference tiles_str 과 갈려 코퍼스의 대기·금지 글자 비교가 엉뚱하게 빨갛거나 초록이다.
    @Test("text(kinds:) = reference tiles_str — 정렬 · 색 순 m p s z · 적 정보 없음")
    func textForm() {
        #expect(MahjongTiles.text(kinds: []) == "")
        #expect(MahjongTiles.text(kinds: [33, 27, 26, 18, 17, 9, 8, 0, 4, 4]) == "1559m19p19s17z")
        #expect(MahjongTiles.text(kinds: (MahjongTiles.parse("0m0p0s") ?? []).map(\.kind)) == "5m5p5s")
        #expect(MahjongTiles.counts34(MahjongTiles.parse("0m5m5m") ?? []).enumerated().filter { $0.element > 0 }.map(\.offset) == [4])
    }
}
