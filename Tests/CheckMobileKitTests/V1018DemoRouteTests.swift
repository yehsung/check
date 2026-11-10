import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 데모 라우트(`games/mahjong…` · `games/alkkagi…`) — 시뮬레이터 화면을 손으로 누르지 않고 연습 판을 캡처하는 길.
// 값이 서는가 · 남의 라우트를 가로채지 않는가 · 파일 통째가 DEBUG 전용인가.
@MainActor
@Suite struct V1018DemoRouteTests {
    typealias S = MobileDemoPhone1018Route.Scene

    @Test("네 장면이 선다 · 쌓을 화면 · 연습 꼬리")
    func scenes() throws {
        let rows: [(String, S, GamesDestination, Bool, Bool)] = [
            ("games/mahjong", .mahjongLobby, .mahjong, false, false),
            ("games/mahjong/practice", .mahjongPractice, .mahjong, true, false),
            ("games/alkkagi", .alkkagiLobby, .alkkagi, false, false),
            ("games/alkkagi/practice", .alkkagiPractice, .alkkagi, false, true),
        ]
        for (raw, scene, destination, mahjongPractice, alkkagiPractice) in rows {
            let route = try #require(MobileDemoPhone1018Route(demoRoute: raw), "\(raw): 값이 안 선다")
            #expect(route.scene == scene && route.scene.destination == destination)
            #expect(route.opensMahjongPractice == mahjongPractice && route.opensAlkkagiPractice == alkkagiPractice, "\(raw)")
        }
        #expect(MobileDemoPhone1018Route(demoRoute: " /Games/Mahjong/PRACTICE/ ")?.scene == .mahjongPractice, "글자 다듬기")
        #expect(S.allCases.count == rows.count, "표에 없는 장면이 있다")
    }

    @Test("남의 데모 라우트는 nil")
    func ignoresOthers() {
        for raw in ["games", "games/reversi", "games/rummy/lobby", "games/tetris", "games/crossy", "games/mahjongx", "games/alkkagi/match", "now"] {
            #expect(MobileDemoPhone1018Route(demoRoute: raw) == nil, "\(raw) 를 가로챘다")
        }
    }

    @Test("파일 통째가 DEBUG 전용 · 스토어 깃발은 DEBUG 밖 Bool 한 칸")
    func debugOnly() throws {
        let file = try IntegrationContractTests.code("Sources/CheckMobileKit/Demo/MobileDemoPhone1018Route.swift")
        let lines = file.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.first == "#if DEBUG" && lines.last == "#endif")
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesStore.swift")
        #expect(store.contains("package var pendingDemoPhone1018Screen = false"))
        #expect(store.contains("#if DEBUG\n    package var demoPhone1018Route: MobileDemoPhone1018Route?\n    #endif"))
    }
}
