#if DEBUG
import Foundation

/// 데모 스크린샷 라우트 `now/team…` 한 건을 **값으로 푼 것**(DEBUG 전용) — 우리 팀 전체 명단.
///
/// `MobileDemoMissionsRoute` 와 같은 꼴이다(DEBUG 전용인 까닭 · 장면 폴더 대신 바늘을 쓰는 까닭은 그 파일 머리말에 있다).
/// 기존 장면 `now` 의 **보이는 값**은 바꾸지 않는다 — 앱스토어 스크린샷 장면이다. 명단용 팀 상태는 바늘 변형으로 따로 둔다.
/// 다만 주간 세션 파일(`_now/rest.work_sessions.get@…not.is.null`)은 한 벌을 나눠 쓴다: 그 키는 쿼리를 바늘로 쥐고 있어 변형을 또 둘 수 없다.
/// 더한 행은 명단에만 있는 사람(106 · 108 · 109)의 것이라 `now` 의 다섯 줄 합계에 닿지 않는다.
///
/// | 라우트                 | scene        | needle            | 보이는 것                                 |
/// | ---------------------- | ------------ | ----------------- | ----------------------------------------- |
/// | `now/team`             | now          | demo-team-roster  | 명단: 근무 넷(끊김 하나) · 쉬는 다섯(이름 없음 · 사람 목록에 없는 사람 · 목표 달성 포함) |
/// | `now/team/empty`       | now          | demo-team-empty   | 명단: 빈 상태                             |
/// | `now/team/failed`      | now          | demo-team-failed  | 명단: 불러오지 못함 + [다시 시도]         |
/// | `now/team/loading`     | now          | demo-team-roster  | 명단: 불러오는 중(팀 상태 응답을 붙잡는다) |
/// | `now/team/noteam`      | now-teamless | nil               | 명단: 팀 없음                             |
/// | `now/team/entry-off`   | now          | demo-team-all-off | **지금 탭 그대로**: 우리 팀 근무 0명 — 절 머리의 [우리 팀 전체 보기] |
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute now/team -AingCheckDemoAppearance light
/// ```
package struct MobileDemoTeamRosterRoute: Hashable, Sendable {
    /// 실제로 여는 탭 라우트(`AingRoute(path:)` 가 아는 글자).
    package var openRoute: String { "now" }
    package var scene: String
    package var needle: String?
    /// 지금 탭 위에 명단 화면을 쌓는가.
    package var opensRoster: Bool
    /// 팀 상태 응답을 붙잡아 '불러오는 중'에 세운다.
    package var holdsTeamStatus: Bool

    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        // `now/teamless` 는 다른 장면이다 — 접두를 "now/team/" 까지 봐야 걸리지 않는다.
        guard path == "now/team" || path.hasPrefix("now/team/") else { return nil }
        scene = "now"
        needle = "demo-team-roster"
        opensRoster = true
        holdsTeamStatus = false
        switch path.split(separator: "/").dropFirst(2).first.map(String.init) {
        case "empty": needle = "demo-team-empty"
        case "failed": needle = "demo-team-failed"
        case "loading": holdsTeamStatus = true
        case "noteam":
            scene = "now-teamless"
            needle = nil
        case "entry-off":
            needle = "demo-team-all-off"
            opensRoster = false
        default: break
        }
    }

    /// 바늘을 요청 본문 꼬리에 붙인 사본(`MobileDemoMissionsRoute.rewrite` 와 같은 길 — 기록은 원본으로 남는다).
    package func rewrite(_ request: MobileStubRequest) -> MobileStubRequest {
        guard let needle else { return request }
        return MobileStubRequest(
            method: request.method,
            host: request.host,
            path: request.path,
            query: request.query,
            headers: request.headers,
            bodyText: request.bodyText + " __demoFixture=" + needle
        )
    }

    /// 이 요청의 응답을 늦출 초. 스크린샷을 찍는 동안만 붙잡으면 되므로 요청 시간 제한보다 짧으면 충분하다.
    package func responseDelay(for request: MobileStubRequest) -> TimeInterval {
        holdsTeamStatus && request.path.hasSuffix("/work_statuses") ? 50 : 0
    }
}
#endif
