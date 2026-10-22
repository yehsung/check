@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// **관전자 수**(0.3.65 / 폰 1.0.13)가 세 자리에 서는 것의 못 — 오목·체스·테트리스 공통.
//
// ── 무엇을 재는가 ──────────────────────────────────────────────────────────────────────────
//  ① 순수 판정(`GamesWatcherCount`) — **0 이면 안 그린다 · 1 이상이면 그린다 · 라벨은 "관전자 N명"**.
//     숫자만 읽히면 뜻이 없다(판돈·경과와 섞여 읽힌다)는 것이 명세 §3 의 못이다.
//  ② 전선 → 화면 값 — 로비 응답의 `matches[].watchers` 가 실제로 카드 값이 되고, 없는 서버에서는 0 이다.
//     ★ 기준선이 달라야 한다: `watchers` 를 뺀 같은 응답을 나란히 넣어 0 을 확인한다
//     (같은 입력이면 그 테스트는 영원히 초록 — [[comparison-baseline-must-differ]]).
//  ③ 세 로비 줄의 **오른쪽 끝 슬롯 게이트가 하나**인가 — 폭 재보기(`ViewThatFits`)와 슬롯 내용이 **같은
//     술어**를 본다. 조건을 두 곳에 적으면 "빈 슬롯 때문에 줄을 접는" 꼴이 되고, 그 상태가 초록으로 남는다.
//  ④ 세 화면이 **스토어 한 칸**(`spectatorCount`)을 읽는가 — 화면이 제 숫자를 들고 있으면 폴링이 깨우지
//     않는 동안 굳는다.
//
// ── 왜 ③④ 가 소스 계약인가 ───────────────────────────────────────────────────────────────
// 폰 뷰는 맥 스위트가 한 줄도 못 본다(CheckMobileKit 의 절반이 `#if os(iOS)` — 저장소 메모 '폰 뷰는 맥
// 스위트가 못 본다'). 그래서 **값으로 잴 수 있는 것은 전부 판정으로 떼어** ①②로 재고, 뷰가 그 판정을
// **안 지나는 길**만 글자로 막는다. 소스는 **주석을 걷어내고** 읽는다(안 걷으면 설명을 지워야만 초록이 된다).

@MainActor
@Suite(.serialized) struct GamesWatcherCountTests {

    // MARK: - ① 순수 판정

    @Test("0 이면 안 그린다 · 1 이상이면 그린다 · 보이스오버는 \"관전자 N명\"")
    func theCountDrawsOnlyWhenSomeoneIsWatching() {
        // 없으면: "0명이 보고 있어요" 가 모든 카드마다 서서, 아무도 안 보는 판이 화면의 절반을 먹는다.
        #expect(!GamesWatcherCount.shows(0), "0 인데 그린다")
        #expect(!GamesWatcherCount.shows(-3), "서버가 흔들려 음수가 와도 그리지 않는다")
        #expect(GamesWatcherCount.shows(1))
        #expect(GamesWatcherCount.shows(27))

        #expect(GamesWatcherCount.text(3) == "3")
        #expect(GamesWatcherCount.text(-3) == "0", "음수를 그대로 그린다")

        // ★ 라벨이 숫자만이면 보이스오버가 "3" 만 읽는다 — 판돈·경과와 구별되지 않는다.
        #expect(GamesWatcherCount.accessibilityLabel(3) == "관전자 3명")
        #expect(GamesWatcherCount.accessibilityLabel(1) == "관전자 1명")
        #expect(GamesWatcherCount.accessibilityLabel(0) == "관전자 0명", "라벨 식은 수를 접지 않는다(그릴지는 `shows` 가 가른다)")
        #expect(GamesWatcherCount.accessibilityLabel(5) != GamesWatcherCount.text(5),
                "라벨이 숫자와 같다 — 뜻을 말하는 낱말이 없다")
        #expect(GamesWatcherCount.watchingPhrase(2) == "2명이 보고 있어요")
        // 눈 기호는 **한 벌**이다(자리마다 다른 기호를 고르면 같은 값이 다른 것으로 읽힌다).
        #expect(GamesWatcherCount.symbol == "eye.fill")
    }

    // MARK: - ② 전선 → 카드 값 (기준선 대비)

    @Test("로비 응답의 `matches[].watchers` 가 세 게임 카드 값이 된다 — 그 칸이 없는 서버에서는 0 이다")
    func theLobbyPayloadCarriesTheCountIntoTheCards() throws {
        // 없으면: 서버가 수를 싣는데 화면이 늘 0 을 보거나(매핑 누락), 옛 서버에서 디코딩이 터진다.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // 오목
        let gomoku = try decoder.decode(GomokuLobbyResponse.self, from: Data(Self.gomokuLobby(watchers: "4").utf8))
        #expect(gomoku.matches?.first?.watchers == 4)
        let gomokuOld = try decoder.decode(GomokuLobbyResponse.self, from: Data(Self.gomokuLobby(watchers: nil).utf8))
        #expect(gomokuOld.matches?.first?.watchers == nil, "기준선: 옛 서버 응답에 그 칸이 있다 — 대비가 성립하지 않는다")
        #expect(max(0, gomokuOld.matches?.first?.watchers ?? 0) == 0)

        // 체스
        let chess = try decoder.decode(ChessLobbyResponse.self, from: Data(Self.chessLobby(watchers: "7").utf8))
        #expect(chess.matches?.first?.watchers == 7)
        let chessOld = try decoder.decode(ChessLobbyResponse.self, from: Data(Self.chessLobby(watchers: nil).utf8))
        #expect(chessOld.matches?.first?.watchers == nil)

        // 테트리스
        let tetris = try decoder.decode(TetrisLobbyResponse.self, from: Data(Self.tetrisLobby(watchers: "2").utf8))
        #expect(tetris.matches?.first?.watchers == 2)
        let tetrisOld = try decoder.decode(TetrisLobbyResponse.self, from: Data(Self.tetrisLobby(watchers: nil).utf8))
        #expect(tetrisOld.matches?.first?.watchers == nil)

        // 그리고 그 값이 **화면 판정**으로 이어진다(수가 있으면 그린다 · 없으면 안 그린다).
        #expect(GamesWatcherCount.shows(max(0, tetris.matches?.first?.watchers ?? 0)))
        #expect(!GamesWatcherCount.shows(max(0, tetrisOld.matches?.first?.watchers ?? 0)))
    }

    @Test("카드 값은 **음수를 그대로 들지 않는다** — 음수를 실은 로비 JSON 을 세 코어 매핑에 **통과시켜** 잰다")
    func theCardValueNeverGoesNegative() throws {
        // 없으면: 서버가 흔들려 음수를 실으면 "눈 −3" 이 카드에 선다.
        //
        // ★ **값을 손으로 넣어 재면 안 된다.** 전에는 `GomokuLiveMatch(…, watchers: 0)` 을 세워 0 인지 보았는데,
        //   그건 생성자가 받은 그 값을 돌려주는 것을 본 것뿐이라 코어의 `max(0, row.watchers ?? 0)` 을
        //   **걷어내도 초록**이었다(걷어내고 실제로 돌려 확인했다). 그래서 여기는 **전선 JSON → 디코더 →
        //   `liveMatch(from:)`** 으로 클램프 그 줄을 지난다. 접는 자리를 지우면 −3 이 그대로 나와 빨개진다.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        func gomokuCard(_ raw: String?) throws -> Int {
            let row = try #require(try decoder.decode(GomokuLobbyResponse.self,
                                                      from: Data(Self.gomokuLobby(watchers: raw).utf8)).matches?.first)
            return try #require(GomokuStore().liveMatch(from: row), "오목 카드가 아예 안 섰다").watchers
        }
        func chessCard(_ raw: String?) throws -> Int {
            let row = try #require(try decoder.decode(ChessLobbyResponse.self,
                                                      from: Data(Self.chessLobby(watchers: raw).utf8)).matches?.first)
            return try #require(ChessStore().liveMatch(from: row), "체스 카드가 아예 안 섰다").watchers
        }
        func tetrisCard(_ raw: String?) throws -> Int {
            let row = try #require(try decoder.decode(TetrisLobbyResponse.self,
                                                      from: Data(Self.tetrisLobby(watchers: raw).utf8)).matches?.first)
            return try #require(TetrisDuelStore().liveMatch(from: row), "테트리스 카드가 아예 안 섰다").watchers
        }

        // 전제: 전선이 음수를 **그대로** 싣는다(디코더가 먼저 접으면 아래가 클램프를 안 지난다).
        let wire = try #require(try decoder.decode(GomokuLobbyResponse.self,
                                                   from: Data(Self.gomokuLobby(watchers: "-3").utf8)).matches?.first)
        #expect(wire.watchers == -3, "전선이 음수를 미리 접었다 — 이 아래로는 클램프를 잴 수 없다")

        for (name, card) in [("오목", gomokuCard), ("체스", chessCard), ("테트리스", tetrisCard)]
            as [(String, (String?) throws -> Int)] {
            #expect(try card("-3") == 0, "\(name) 매핑이 음수를 안 접는다")
            // 기준선 둘: 멀쩡한 수는 **그대로** 지나고(0 으로 뭉개는 매핑이면 빨갛다), 칸이 없으면 0 이다.
            #expect(try card("4") == 4, "\(name) 매핑이 멀쩡한 수까지 뭉갠다 — 대비가 성립하지 않는다")
            #expect(try card(nil) == 0, "\(name) 은 그 칸이 없는 서버에서 쓰레기를 싣는다")
        }

        // 생성자 **기본값**도 0 이다(이 칸을 모르는 호출부가 쓰레기를 싣지 않게 — 위 매핑과 다른 축이다).
        #expect(GomokuLiveMatch(id: "m", a: Self.gomokuUser("a"), b: Self.gomokuUser("b"),
                                stake: .three, startedAt: .distantPast).watchers == 0)
        #expect(ChessLiveMatch(id: "m", a: Self.chessUser("a"), b: Self.chessUser("b"),
                               stake: .three, startedAt: .distantPast).watchers == 0)
        #expect(TetrisDuelLiveMatch(id: "m", a: Self.tetrisUser("a"), b: Self.tetrisUser("b"),
                                    stake: .three, startedAt: .distantPast).watchers == 0)
        // 그리는가는 **한 함수**가 가른다 — 음수는 어디서 와도 안 그린다.
        #expect(!GamesWatcherCount.shows(-1))
    }

    // MARK: - ③ 로비 줄: 오른쪽 끝 슬롯 게이트가 **하나**

    @Test("★ 세 로비 줄에서 폭 재보기와 슬롯 내용이 **같은 술어**를 본다 — 두 벌이면 빈 슬롯 때문에 줄을 접는다")
    func theTrailingSlotGateIsASinglePredicate() throws {
        // 없으면: 관전자 수가 붙으면서 조건이 두 곳에 적히고, 한쪽만 고쳐져 **아무것도 없는 슬롯 때문에**
        // 줄이 세로로 접힌다(오목이 320pt 실측으로 고친 그 자리의 반대 방향 사고다).
        let chess = try Self.code("Sources/CheckMobileKit/Games/GamesChessWatch.swift")
        #expect(chess.contains("} else if hasEntry {"), "체스 줄의 폭 재보기가 그 술어를 안 본다")
        #expect(chess.contains("private var entry: some View {\n        if hasEntry {"),
                "체스 줄의 슬롯이 같은 술어로 열리지 않는다")
        #expect(Self.block(of: "private var hasEntry: Bool", in: chess).contains("GamesWatcherCount.shows(live.watchers)"),
                "체스 술어가 관전자 수를 안 본다 — 입구가 없는 행에서 수가 사라진다")
        #expect(Self.block(of: "private var hasEntry: Bool", in: chess).contains("GamesChessWatchPlan.entry"),
                "체스 술어가 관전 입구 판정을 안 지난다")

        let shared = try Self.code("Sources/CheckMobileKit/Games/GamesComponents.swift")
        #expect(shared.contains("} else if hasTrailing {"), "오목·허브 줄의 폭 재보기가 그 술어를 안 본다")
        #expect(Self.block(of: "private var hasTrailing: Bool", in: shared).contains("GamesWatcherCount.shows(live.watchers)"))
        #expect(Self.block(of: "private var hasTrailing: Bool", in: shared).contains("hasWatchEntry"))

        let tetris = try Self.code("Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift")
        #expect(tetris.contains("} else if hasEntry {"), "테트리스 줄의 폭 재보기가 그 술어를 안 본다")
        #expect(Self.block(of: "private var hasEntry: Bool", in: tetris).contains("GamesTetrisWatchPlan.hasTrailingContent"))
    }

    // MARK: - ④ 세 자리가 **스토어 한 칸**을 읽는가

    @Test("관전 화면·대국자 본인 화면이 `spectatorCount` 한 칸을 읽는다 — 화면이 제 숫자를 들면 값이 굳는다")
    func everyScreenReadsTheStoreCount() throws {
        // 없으면: 어느 한 화면만 옛 값을 보여 주거나(값으로 받아 굳은 숫자), 자리가 통째로 빠진다 —
        // 그리고 그 사실을 알려 줄 테스트가 없다(폰 뷰는 맥 스위트가 못 본다).
        for (name, path, source) in [
            ("체스 관전", "Sources/CheckMobileKit/Games/GamesChessWatch.swift", "store.spectatorCount"),
            ("체스 대국", "Sources/CheckMobileKit/Games/GamesChessMatch.swift", "store.spectatorCount"),
            ("오목 관전", "Sources/CheckMobileKit/Games/GamesGomokuWatch.swift", "gomoku.spectatorCount"),
            ("오목 대국", "Sources/CheckMobileKit/Games/GamesGomokuMatch.swift", "gomoku.spectatorCount"),
            ("테트리스 관전", "Sources/CheckMobileKit/Games/GamesTetrisWatch.swift", "store.spectatorCount"),
            ("테트리스 대국", "Sources/CheckMobileKit/Games/GamesTetrisDuelMatch.swift", "tetris.spectatorCount")
        ] {
            let code = try Self.code(path)
            #expect(code.contains("GamesWatcherBadge(count: \(source)"), "\(name) 화면이 관전자 수를 안 그린다")
        }
        // 로비 줄 셋은 **카드 값**을 읽는다(그 판의 수이지 내가 보는 판의 수가 아니다).
        for (name, path) in [("체스 로비", "Sources/CheckMobileKit/Games/GamesChessWatch.swift"),
                             ("오목·허브 로비", "Sources/CheckMobileKit/Games/GamesComponents.swift"),
                             ("테트리스 로비", "Sources/CheckMobileKit/Games/GamesTetrisWatch.swift")] {
            #expect(try Self.code(path).contains("GamesWatcherBadge(count: live.watchers)"),
                    "\(name) 줄이 카드의 수를 안 그린다")
        }
        // 그리고 **애니메이션을 걸지 않는다**(2초 폴링마다 숫자가 튀면 눈에 거슬린다 — 명세 §3).
        let badge = Self.block(of: "struct GamesWatcherBadge: View",
                               in: try Self.code("Sources/CheckMobileKit/Games/GamesComponents.swift"))
        for banned in ["withAnimation", ".animation(", "contentTransition"] where badge.contains(banned) {
            Issue.record("관전자 수 칸에 애니메이션이 붙었다: \(banned)")
        }
    }

    // MARK: - 픽스처

    private nonisolated static func gomokuLobby(watchers: String?) -> String {
        let extra = watchers.map { ",\"watchers\":\($0)" } ?? ""
        return #"{"status":"ok","server_now_ms":1,"stakes":[3],"me":{"ruby_balance":1},"users":[],"matches":[{"match_id":"m1","a":{"user_id":"a","display_name":"가"},"b":{"user_id":"b","display_name":"나"},"stake":3,"started_ms":1\#(extra)}]}"#
    }

    private nonisolated static func chessLobby(watchers: String?) -> String {
        let extra = watchers.map { ",\"watchers\":\($0)" } ?? ""
        return #"{"status":"ok","server_now_ms":1,"stakes":[3],"initial_ms":600000,"increment_ms":3000,"grace_ms":2000,"me":{"ruby_balance":1},"users":[],"matches":[{"match_id":"m1","a":{"user_id":"a","display_name":"가"},"b":{"user_id":"b","display_name":"나"},"stake":3,"started_ms":1\#(extra)}]}"#
    }

    private nonisolated static func tetrisLobby(watchers: String?) -> String {
        let extra = watchers.map { ",\"watchers\":\($0)" } ?? ""
        return #"{"status":"ok","server_now_ms":1,"stakes":[3],"me":{"ruby_balance":1},"users":[],"matches":[{"id":"m1","a":{"id":"a","display_name":"가"},"b":{"id":"b","display_name":"나"},"stake":3,"started_at_ms":1\#(extra)}]}"#
    }

    private nonisolated static func gomokuUser(_ id: String) -> GomokuUser {
        GomokuUser(id: id, displayName: id, avatarURL: nil, characterID: nil,
                   isWorking: false, isCapable: true, inMatch: false)
    }

    private nonisolated static func chessUser(_ id: String) -> ChessUser {
        ChessUser(id: id, displayName: id, avatarURL: nil, characterID: nil,
                  isWorking: false, isCapable: true, inMatch: false, center: nil)
    }

    private nonisolated static func tetrisUser(_ id: String) -> TetrisDuelUser {
        TetrisDuelUser(id: id, displayName: id, avatarURL: nil, characterID: nil,
                       isWorking: false, isCapable: true, inMatch: false)
    }

    // MARK: - 소스 읽기 (주석을 걷어낸다 — 하우스 규칙)

    private nonisolated static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    nonisolated static func code(_ relative: String) throws -> String {
        stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    /// 줄 주석을 걷어낸다 — 안 걷으면 **설명문을 지워야만 초록**이 되는 테스트가 된다.
    nonisolated static func stripComments(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// 선언 머리부터 **중괄호가 닫히는 곳까지**(글자 수로 자르면 다음 블록으로 샌다).
    nonisolated static func block(of marker: String, in source: String) -> String {
        guard let hit = source.range(of: marker) else { return "" }
        var depth = 0
        var started = false
        var out = ""
        for character in source[hit.upperBound...] {
            if character == "{" {
                depth += 1
                started = true
            } else if character == "}" {
                depth -= 1
            }
            out.append(character)
            if started, depth == 0 { return out }
        }
        return out
    }
}
