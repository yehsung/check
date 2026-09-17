import CheckMobileShared
import Foundation
import SwiftUI
import Testing
@testable import CheckMobileKit

/// 라우터(SPEC-ios §3 딥링크 · SPEC-ios-build §1-7): URL ↔ 라우트 왕복, 데모 라우트 표기, 잘못된 링크 거절, 탭 열기·꺼내기.
@MainActor
@Suite struct BaseRouterTests {
    static let allRoutes: [AingRoute] = [
        .now, .messages, .message(peerID: "3f2a9c1e-0000-4000-8000-00000000abcd"),
        .rankings(.league), .rankings(.tokens), .rankings(.minigame),
        .games, .miniGame(.timing), .miniGame(.flappy),
        .gomokuLobby, .gomokuInvite(matchID: "m-1"), .gomokuMatch(matchID: "m-2"), .gomokuMatch(matchID: nil),
        .me, .shop, .feedback(reportID: "42"), .feedback(reportID: nil), .settings,
    ]

    @Test("모든 라우트가 정규 URL 로 갔다가 같은 값으로 돌아온다")
    func urlRoundTrip() {
        for route in Self.allRoutes {
            #expect(route.url.scheme == "aingcheck")
            #expect(AingRoute(url: route.url) == route, "왕복 실패: \(route) → \(route.url)")
        }
    }

    @Test("SPEC-ios 의 딥링크 다섯 개를 글자 그대로 읽는다")
    func specDeepLinks() {
        #expect(AingRoute(url: URL(string: "aingcheck://message/abc-123")!) == .message(peerID: "abc-123"))
        #expect(AingRoute(url: URL(string: "aingcheck://gomoku/invite/m9")!) == .gomokuInvite(matchID: "m9"))
        #expect(AingRoute(url: URL(string: "aingcheck://gomoku/match/m9")!) == .gomokuMatch(matchID: "m9"))
        #expect(AingRoute(url: URL(string: "aingcheck://feedback/77")!) == .feedback(reportID: "77"))
        #expect(AingRoute(url: URL(string: "aingcheck://now")!) == .now)
    }

    @Test("데모 라우트 표기(-AingCheckDemoRoute) 전부가 라우트로 읽힌다 — login·update 는 세션 장면이라 라우트가 아니다")
    func demoRouteStrings() {
        let expected: [(String, AingRoute)] = [
            ("now", .now), ("messages", .messages), ("messages/peer-1", .message(peerID: "peer-1")),
            ("rankings/league", .rankings(.league)), ("rankings/tokens", .rankings(.tokens)), ("rankings/minigame", .rankings(.minigame)),
            ("games", .games), ("games/timing", .miniGame(.timing)), ("games/flappy", .miniGame(.flappy)),
            ("games/gomoku/lobby", .gomokuLobby), ("games/gomoku/match", .gomokuMatch(matchID: nil)),
            ("me", .me), ("me/shop", .shop), ("me/feedback", .feedback(reportID: nil)), ("me/settings", .settings),
        ]
        for (text, route) in expected {
            #expect(AingRoute(path: text) == route, "\(text)")
        }
        #expect(AingRoute(path: "login") == nil)
        #expect(AingRoute(path: "update") == nil)
    }

    @Test("모르는 모양·다른 스킴·위험한 id 는 nil(조용히 지금 탭으로 접지 않는다)")
    func rejectsBadLinks() {
        #expect(AingRoute(url: URL(string: "https://message/abc")!) == nil)
        #expect(AingRoute(url: URL(string: "aingcheck://unknown")!) == nil)
        #expect(AingRoute(url: URL(string: "aingcheck://message")!) == nil)
        #expect(AingRoute(url: URL(string: "aingcheck://message/a/b")!) == nil)
        #expect(AingRoute(url: URL(string: "aingcheck://message/..")!) == nil)
        #expect(AingRoute(url: URL(string: "aingcheck://message/a%20b")!) == nil)
        #expect(AingRoute(url: URL(string: "aingcheck://rankings/weekly")!) == nil)
        #expect(AingRoute(url: URL(string: "aingcheck://message/" + String(repeating: "a", count: 65))!) == nil)
        #expect(AingRoute(path: "") == nil)
    }

    @Test("open: 탭을 고르고 그 탭 경로를 비우고 링크를 남긴다 — 꺼내면 한 번만 나온다")
    func openSelectsTabAndLeavesPendingRoute() {
        let router = MobileRouter()
        router.push("쌓인 화면", on: .messages)
        #expect(router.path(for: .messages).count == 1)
        let serial = router.routeSerial

        router.open(.message(peerID: "p1"))
        #expect(router.selectedTab == .messages)
        #expect(router.path(for: .messages).isEmpty)
        #expect(router.routeSerial == serial + 1)
        #expect(router.lastOpenedRoute == .message(peerID: "p1"))
        #expect(router.consumePendingRoute(for: .games) == nil, "다른 탭에는 남기지 않는다")
        #expect(router.consumePendingRoute(for: .messages) == .message(peerID: "p1"))
        #expect(router.consumePendingRoute(for: .messages) == nil)

        #expect(router.open(url: URL(string: "aingcheck://gomoku/invite/m1")!))
        #expect(router.selectedTab == .games)
        #expect(!router.open(url: URL(string: "aingcheck://nope")!))
        #expect(router.selectedTab == .games, "모르는 URL 은 아무것도 바꾸지 않는다")
    }

    @Test("reset: 지금 탭 · 경로 · 남은 링크 · 보이는 대화를 비운다")
    func resetClearsEverything() {
        let router = MobileRouter()
        router.open(.settings)
        router.push(1, on: .me)
        router.visibleConversationPeerID = "p"
        router.reset()
        #expect(router.selectedTab == .now)
        #expect(router.path(for: .me).isEmpty)
        #expect(router.consumePendingRoute(for: .me) == nil)
        #expect(router.visibleConversationPeerID == nil)
    }

    @Test("탭 배지 합성: 메시지·게임만, 0 은 배지 없음, 앱 배지는 합")
    func badges() {
        let badges = MobileBadges(messages: 3, games: 0)
        #expect(badges.badge(for: .messages) == 3)
        #expect(badges.badge(for: .games) == nil)
        #expect(badges.badge(for: .now) == nil)
        #expect(MobileBadges(messages: 2, games: 1).appBadgeTotal == 3)
        #expect(MobileBadges(messages: -1, games: 2).appBadgeTotal == 2)
        #expect(AingTab.allCases.map(\.title) == ["지금", "메시지", "순위", "게임", "나"])
    }
}
