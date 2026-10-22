#if DEBUG
import Foundation

/// 데모 스크린샷 라우트 `me/missions…` · `me/weekly…` 한 건을 **값으로 푼 것**(DEBUG 전용) — 도전 미션 · 주간 근무 받기.
///
/// ── 왜 `Demo/` 안이고 파일 통째가 `#if DEBUG` 인가 ──
/// Release 바이너리에서 **이름이 사라져야** 한다. 1.0.6(build 16) 아카이브에서 `MobileDemoChessRoute` 가 구성 분기 없이
/// 선언돼 있어 Swift 가 타입 이름(nominal type descriptor)을 Release 바이너리에 넣었고, 출시 게이트
/// `ios/scripts/check-release-app.sh` 의 금지 심볼 `MobileDemo` 가 그것을 물어 아카이브가 막혔다(SPEC-ios §0-2 —
/// "0 이 아니면 올리지 않는다"). 테스트 281건과 코드 검토는 그 결함을 한 건도 보지 못했다 — `swift test` 는 Debug 다.
/// 그래서 데모 기계는 전부 이 폴더 안 `#if DEBUG` 이라는 것이 관례이고(`MobileDemo` · `MobileDemoChessRoute` ·
/// `MobileDemoGomokuAI` · `MobileStubURLProtocol`), `Package.swift` 의 리소스 주석도 그것을 불변식으로 적어 뒀다.
/// 되돌리면(구성 분기를 빼면) `MeAchievementsFixtureContractTests` 의 §6 이 `swift test` 에서 빨개진다 — 아카이브까지
/// 가지 않는다. **`#if os(iOS)` 는 더하면 안 된다**: 그걸 더하는 순간 맥 스위트가 이 판정을 한 줄도 못 보게 되고
/// (저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 라우트 → 픽스처 그물이 통째로 사라진다.
///
/// ── 왜 장면 폴더가 아니라 **바늘**인가(중요) ──
/// 스텁은 라우트 글자의 `/` 를 `-` 로 바꾼 것을 장면 폴더 이름으로 쓴다(`MobileDemo.environment`). 그러니 상태 변형마다
/// `_me-missions-claimed` 같은 폴더를 두는 것이 자연스러워 보이는데, **그 길은 막혀 있다**:
/// `IntegrationContractTests.demoFixtureScenesMatchRoutes` 가 "장면 폴더는 모두 실제 데모 라우트의 장면이다"를 단언하고
/// 그 라우트 목록은 그 파일(다른 레인 소유)에 있다 — 폴더를 더하면 그 테스트가 빨개진다(오타 장면을 잡는 그물이라 맞는 단언이다).
/// 그리고 `achievements_status()` · `weekly_work_status()` 는 **인자가 없다**(본문 `{}`) — 변형을 고를 바늘이 본문에 없다.
/// 그래서 이 값이 ① 기존 장면(`me` · `me-`)을 고르고 ② 픽스처 바늘을 **요청 본문 꼬리에 붙여**(`rewrite`) 변형을 고르게 한다.
/// 바늘 변형은 같은 장면 폴더 안에 둔다 — 고르기 순위가 "장면 먼저, 그 안에서 바늘 긴 것 먼저"라서 바깥 층에 두면
/// 장면의 기본 파일이 언제나 이긴다(변형이 영영 안 쓰인다).
///
/// ── 꼬리가 정하는 것 둘 ──
/// (1.0.13 부터 이 줄들이 보이는 곳은 나 탭 루트가 아니라 **미션 화면**이다 — 주간 카드 · 도전 미션 절이 루트에서 나갔고
/// 루트에는 [미션] 줄만 남았다. 아래 라우트는 그 화면을 **열어** 준다: `MeDemoHooks.initialDestination()` 이
/// `opensMissionsPage(route:)` 로 판정해 `MeDestination.missions` 를 쌓는다.)
/// | 라우트                     | scene | needle            | 미션 화면에 보이는 것                                |
/// | -------------------------- | ----- | ----------------- | ---------------------------------------------------- |
/// | `me/missions`              | me    | nil               | 받을 것 넷(75루비) · 주간 [받기](70루비)             |
/// | `me/missions/claimable`    | me    | nil               | 같다(이름만 또렷한 별칭)                             |
/// | `me/missions/progress`     | me    | demo-progress     | 중간 진행 — 받을 것 0(배지가 서면 안 된다)           |
/// | `me/missions/claimed`      | me    | demo-all-claimed  | 열셋 전부 받음(계열 줄은 가장 높은 단계)             |
/// | `me/missions/fresh`        | me-   | nil               | 갓 가입 — 달성 0 · 주간 0초                          |
/// | `me/weekly`                | me    | nil               | `me/missions` 와 같은 장면(주간 카드를 보러 가는 이름) |
/// | `me/weekly/done`           | me    | demo-week-done    | 주간 완료(62시간) · 세 단계 전부 받음                |
/// | `me/weekly/legacy`         | me    | demo-week-legacy  | 옛 서버(0.3.55~57) — 받기 칸이 없다 · granted_now 로 알린다 |
///
/// 라우트 글자가 `AingRoute` 에 없으므로(`me/missions` 는 nil 이다) **열 라우트는 `me` 로 바꿔 넘긴다**(`openRoute`) —
/// 안 바꾸면 `MobileAppModel.openDemoRouteIfNeeded` 가 돌아서서 기본 탭(지금)에 머물고, 나 탭이 아예 안 열린다.
/// 그 바꿔치기는 `MobileDemo.environment` 한 곳에서 한다. 탭을 연 **뒤** 그 위에 미션 화면을 쌓는 것은 나 탭의 데모 훅이다
/// (1.0.13 — `MeDemoHooks.initialDestination()` · `opensMissionsPage(route:)`).
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute me/missions
/// ```
package struct MobileDemoMissionsRoute: Hashable, Sendable {
    /// 이 라우트들이 **실제로 여는** 탭 라우트(`AingRoute(path:)` 가 아는 글자). 여는 탭은 나 탭이고, 미션 화면은
    /// 1.0.13 부터 **그 위에 쌓인다**(`opensMissionsPage(route:)` → `MeDestination.missions`) — 이 값은 그대로다.
    package static let openRoute = "me"

    /// 스텁이 고를 장면 폴더 이름(`_me` → "me"). **기존 장면만** 쓴다(위 머리말 참고).
    package var scene: String
    /// 픽스처 변형 바늘(`rpc.achievements_status@demo-progress.json` → "demo-progress"). nil 이면 장면의 기본 파일.
    package var needle: String?

    package init(scene: String, needle: String? = nil) {
        self.scene = scene
        self.needle = needle
    }

    package var openRoute: String { Self.openRoute }

    /// 데모 라우트 글자 → 값. 미션 · 주간 라우트가 아니면 nil(그러면 데모는 평소대로 라우트에서 장면을 뽑는다).
    /// 모르는 꼬리는 **받을 것 여럿** 장면으로 접는다 — 라우트를 조용히 버리지 않는다(버리면 기본 탭이 떠서 아무도 못 본다).
    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard path == "me/missions" || path.hasPrefix("me/missions/")
                || path == "me/weekly" || path.hasPrefix("me/weekly/")
        else { return nil }
        let tail = path.split(separator: "/").dropFirst(2).map(String.init)
        switch tail.first {
        case "fresh":
            self.init(scene: "me-")
        case "progress":
            self.init(scene: "me", needle: "demo-progress")
        case "claimed":
            self.init(scene: "me", needle: "demo-all-claimed")
        case "done":
            self.init(scene: "me", needle: "demo-week-done")
        case "legacy":
            self.init(scene: "me", needle: "demo-week-legacy")
        default:
            self.init(scene: "me")
        }
    }

    /// 이 라우트 글자가 **미션 화면**을 여는가(1.0.13 — 주간 카드·도전 미션 절이 루트에서 나갔다).
    /// `MeDemoHooks.initialDestination()` 한 곳이 이 판정을 쓴다 — 깃발(`-AingCheckDemoMeScreen missions`)과
    /// 라우트 글자를 손으로 맞추지 않으려고 여기 둔다(상점 시트 라우트와 같은 관용구).
    package static func opensMissionsPage(route: String) -> Bool {
        let path = route.hasPrefix("/") ? String(route.dropFirst()) : route
        return path == "me/missions" || path.hasPrefix("me/missions/")
            || path == "me/weekly" || path.hasPrefix("me/weekly/")
    }

    /// 바늘을 **요청 본문 꼬리에 붙인** 사본. 픽스처 고르기는 본문+쿼리 글자에서 바늘을 찾으므로(`MobileDemoFixtures.entry`)
    /// 이것이 인자 없는 RPC(`{}`)에서 변형을 고르는 유일한 길이다.
    ///
    /// 기록(`MobileStubURLProtocol.requests(host:)`)은 **건드리지 않는다** — 기록은 프로토콜이 응답기를 부르기 **전에**
    /// 원본으로 남긴다. 그래서 금지 호출 단언·요청 인자 단언은 이 덧붙임을 보지 않는다.
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
}
#endif
