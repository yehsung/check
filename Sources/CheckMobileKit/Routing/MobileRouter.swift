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
///
/// 떠나는 문(`departureGuard`): **사람이 지금 화면을 떠나는 세 길**(탭 막대 · `open` · 시스템 뒤로·탭 재선택)이 한 곳에 묻는다.
/// 지금 묻는 쪽은 아잉 큐브 방 하나다(`GamesStore.rummyDepartureAllowed`). `onDisappear` 로 가르지 않는 까닭: 그 신호는 목적지가 다시 세워질 때도 온다(`GamesTab` 주석) — 그때 손님을 내보내면 안 된다.
/// `popToRoot`·`push`·`reset` 은 묻지 않는다: 부르는 쪽이 이미 판단을 지났다(`open` 뒤의 `consumeRoute` · 화면의 [나가기] · 로그아웃).
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
    /// 떠나도 되는지 묻는 문. true = 지금 간다. false = 확인을 띄웠다 — 수락하면 받은 `resume` 이 원래 가려던 곳으로 간다.
    @ObservationIgnored package var departureGuard: (@MainActor (_ resume: @escaping @MainActor () -> Void) -> Bool)?
    /// 문이 탭 막대를 막은 횟수. 탭 막대가 읽어 **다시 그린다** — 안 그리면 막대만 눌린 탭으로 옮겨 가고 내용은 그대로일 수 있다.
    package private(set) var tabRefusalSerial = 0
    /// 뒤로·탭 재선택을 막았을 때 화면을 되세우기까지(내려가는 애니메이션이 끝난 뒤에 쌓아야 경로와 화면이 갈리지 않는다).
    @ObservationIgnored package var pathRestoreSeconds: Double = 0.45

    package init() {}

    /// 탭 막대가 쥐는 선택. 눌린 탭은 문을 지나야 `selectedTab` 이 된다.
    package var tabBarSelection: AingTab {
        get { selectedTab }
        set { selectTab(newValue) }
    }

    /// 사람이 탭을 골랐다. 같은 탭이면 떠나는 것이 아니다(재선택의 뒤로는 경로 쪽에서 온다).
    package func selectTab(_ tab: AingTab) {
        guard tab != selectedTab else { return }
        guard departureAllowed({ [weak self] in self?.selectedTab = tab }) else {
            tabRefusalSerial &+= 1
            return
        }
        selectedTab = tab
    }

    private func departureAllowed(_ resume: @escaping @MainActor () -> Void) -> Bool {
        departureGuard?(resume) ?? true
    }

    /// 딥링크 열기. 탭을 고르고, 그 탭의 쌓인 화면을 비우고, 탭이 꺼내 갈 라우트를 남긴다.
    package func open(_ route: AingRoute) {
        guard departureAllowed({ [weak self] in self?.open(route) }) else { return }
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
            set: { [weak self] in self?.pathChangedByView($0, on: tab) }
        )
    }

    /// 화면(시스템 뒤로·탭 재선택)이 경로를 바꿨다. 줄어드는 쪽만 떠나는 길이다.
    /// 막으면 화면은 **이미 내려갔다** — 값만 안 바꾸면 경로와 화면이 갈려 다음 진입이 두 겹으로 쌓인다. 그래서 사실대로 적고, 내려간 뒤에 다시 쌓는다.
    private func pathChangedByView(_ path: NavigationPath, on tab: AingTab) {
        let current = paths[tab] ?? NavigationPath()
        guard path.count < current.count,
              !departureAllowed({ [weak self] in self?.paths[tab] = path }) else {
            paths[tab] = path
            return
        }
        paths[tab] = path
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.pathRestoreSeconds))
            if self.paths[tab]?.count == path.count { self.paths[tab] = current }
        }
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

/// 탭 배지 합성(SPEC-ios §3: 메시지 = 안 읽은 수, 게임 = 받은 오목 신청 수, 나 = 받을 보상 수). 값은 각 탭 스토어가 센다.
/// 앱 아이콘 배지(= 메시지 + 게임)는 푸시 코디네이터가 `appBadgeTotal` 을 읽어 `setBadgeCount` 한다.
package struct MobileBadges: Equatable, Sendable {
    package var messages: Int
    package var games: Int
    /// 나 탭 — 지금 받을 수 있는 보상 수(도전 미션 + 이번 주 근무 단계 · `MeStore.missionClaimableCount`).
    /// 기본값이 0 인 이유: 이 값이 없던 때의 호출부(테스트 포함)가 그대로 컴파일되게.
    package var missions: Int

    package init(messages: Int, games: Int, missions: Int = 0) {
        self.messages = max(0, messages)
        self.games = max(0, games)
        self.missions = max(0, missions)
    }

    /// 탭 막대에 그릴 숫자. 0 이면 nil(배지 없음). 지금 · 순위는 배지가 없다.
    package func badge(for tab: AingTab) -> Int? {
        switch tab {
        case .messages: return messages > 0 ? messages : nil
        case .games: return games > 0 ? games : nil
        case .me: return missions > 0 ? missions : nil
        case .now, .rankings: return nil
        }
    }

    /// 앱 아이콘(홈 화면)의 빨간 숫자. **미션은 더하지 않는다**(v0.3.58) — 받을 보상은 사람을 홈 화면에서 부를 일이 아니고,
    /// 더하면 앱을 안 열어도 아이콘에 숫자가 붙은 채로 남는다. 미션은 **탭 막대 배지**로만 말한다.
    package var appBadgeTotal: Int { messages + games }
}
