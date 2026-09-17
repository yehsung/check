import CheckMobileShared
import Foundation
import Observation
import SwiftUI

/// 탭 선택 · 탭별 내비게이션 경로 · 딥링크 열기(SPEC-ios §3 · SPEC-ios-build §1-7).
///
/// 확장 지점(탭 작업자)
/// - 각 탭 화면은 `NavigationStack(path: router.pathBinding(for: .<탭>))` 으로 자기 경로를 쥐고, 자기 폴더 안의 Hashable 값을
///   `router.push(_:on:)` 로 쌓는다(경로 원소 타입은 탭이 정한다 — 라우터는 모른다).
/// - 딥링크는 `open(_:)` 이 **탭을 고르고 그 탭 경로를 비운 뒤** `pendingRoute[탭]` 에 남긴다. 탭 화면(또는 스토어)은
///   `.onChange(of: router.routeSerial)` 등으로 `consumePendingRoute(for:)` 를 불러 자기 방식(경로 push · 시트 · 세그먼트)으로 연다.
///   한 번 꺼내면 비워진다 — 같은 링크를 두 번 여는 일이 없다.
/// - 지금 화면에 보이는 대화 상대는 `visibleConversationPeerID` 에 적는다(메시지 탭이 쓰고, 푸시 코디네이터가 포그라운드 배너를 숨길 때 읽는다).
@MainActor
@Observable
package final class MobileRouter {
    package var selectedTab: AingTab = .now
    package private(set) var paths: [AingTab: NavigationPath] = [:]
    package private(set) var pendingRoute: [AingTab: AingRoute] = [:]
    /// `open` 이 불릴 때마다 +1. 같은 탭에 같은 링크가 다시 와도 관찰자가 깨어나게 한다.
    package private(set) var routeSerial = 0
    /// 마지막으로 연 딥링크(진단·테스트).
    package private(set) var lastOpenedRoute: AingRoute?
    /// 지금 화면에 떠 있는 대화의 상대(메시지 탭이 대화 화면 표시·숨김에 맞춰 적는다). 앱이 background 면 nil 로 본다.
    package var visibleConversationPeerID: String?

    package init() {}

    /// 딥링크 열기. 탭을 고르고, 그 탭의 쌓인 화면을 비우고, 탭이 꺼내 갈 라우트를 남긴다.
    package func open(_ route: AingRoute) {
        let tab = route.tab
        selectedTab = tab
        paths[tab] = NavigationPath()
        pendingRoute[tab] = route
        lastOpenedRoute = route
        routeSerial &+= 1
    }

    /// URL 로 열기(`onOpenURL` · 위젯 링크). 모르는 URL 이면 false(아무것도 안 바뀐다).
    @discardableResult
    package func open(url: URL) -> Bool {
        guard let route = AingRoute(url: url) else { return false }
        open(route)
        return true
    }

    /// 이 탭에 남겨진 라우트를 꺼낸다(꺼내면 비운다). 탭 목록 자체를 가리키는 라우트(`.now`·`.messages`·`.games`·`.me`)도
    /// 그대로 돌려준다 — 탭이 "맨 위로" 같은 동작을 할 수 있게.
    package func consumePendingRoute(for tab: AingTab) -> AingRoute? {
        pendingRoute.removeValue(forKey: tab)
    }

    // MARK: - 경로

    package func path(for tab: AingTab) -> NavigationPath {
        paths[tab] ?? NavigationPath()
    }

    package func pathBinding(for tab: AingTab) -> Binding<NavigationPath> {
        Binding(
            get: { [weak self] in self?.paths[tab] ?? NavigationPath() },
            set: { [weak self] in self?.paths[tab] = $0 }
        )
    }

    package func push<Value: Hashable>(_ value: Value, on tab: AingTab) {
        var path = paths[tab] ?? NavigationPath()
        path.append(value)
        paths[tab] = path
    }

    package func popToRoot(_ tab: AingTab) {
        paths[tab] = NavigationPath()
    }

    /// 로그아웃(세대 교체). 선택 탭은 "지금"으로, 경로·남은 링크·보이는 대화는 비운다.
    package func reset() {
        selectedTab = .now
        paths = [:]
        pendingRoute = [:]
        visibleConversationPeerID = nil
    }
}

/// 탭 배지 합성(SPEC-ios §3: 메시지 = 안 읽은 수, 게임 = 받은 오목 신청 수). 값은 각 탭 스토어의 `badgeCount` 다.
/// 앱 아이콘 배지(= 메시지 + 게임)는 푸시 코디네이터가 `appBadgeTotal` 을 읽어 `setBadgeCount` 한다.
package struct MobileBadges: Equatable, Sendable {
    package var messages: Int
    package var games: Int

    package init(messages: Int, games: Int) {
        self.messages = max(0, messages)
        self.games = max(0, games)
    }

    /// 탭 막대에 그릴 숫자. 0 이면 nil(배지 없음). 다른 탭은 배지가 없다.
    package func badge(for tab: AingTab) -> Int? {
        switch tab {
        case .messages: return messages > 0 ? messages : nil
        case .games: return games > 0 ? games : nil
        case .now, .rankings, .me: return nil
        }
    }

    package var appBadgeTotal: Int { messages + games }
}
