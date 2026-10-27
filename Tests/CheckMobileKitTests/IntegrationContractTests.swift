import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 탭 다섯 갈래를 합친 뒤(w4/int) **탭 사이 계약**을 한 곳에서 지킨다. 푸시 → 탭 스토어 문은 `PushMergeContractTests` 가 요청까지 잰다.
///
/// 소스 계약은 주석을 걷어내고 본다(하우스 규칙 — 설명문에 이름이 들어 있어도 계약이 흔들리지 않게).
@MainActor
@Suite(.serialized) struct IntegrationContractTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    // MARK: - 주인이 하나인 것들(소스 계약)

    @Test("위젯 스냅샷 쓰기 주체는 지금 탭 하나 · 위젯 확장은 체크 표시 패치(같은 갈래의 인텐트)만")
    func widgetSnapshotHasSingleWriter() throws {
        let writers = try Self.files(containing: ["widgetSnapshots.update", "WidgetSnapshotCodec.write("], under: "Sources/CheckMobileKit")
        #expect(!writers.isEmpty, "대조: 쓰는 곳을 하나도 못 찾았다(이름이 바뀌었나)")
        let outsiders = writers.filter { !$0.hasPrefix("Sources/CheckMobileKit/Now/") && $0 != "Sources/CheckMobileKit/App/WidgetSnapshotWriter.swift" }
        #expect(outsiders.isEmpty, "지금 탭 밖에서 위젯 스냅샷을 쓴다 — 서로 덮는다: \(outsiders)")
        // 위젯 인텐트(`ToggleTodoIntent` → `WidgetTodoToggle.patchSnapshot`)는 누른 줄의 체크 표시만 고친다 — 지금 탭+위젯 갈래(D3+D8)가
        // 함께 설계한 예외다. 그 밖의 위젯 코드는 읽기만 한다.
        let widget = try Self.files(containing: ["WidgetSnapshotCodec.write(", "widgetSnapshots.update"], under: "Sources/CheckWidgetsKit")
        #expect(widget == ["Sources/CheckWidgetsKit/WidgetTodoToggle.swift"], "위젯 확장의 스냅샷 쓰기가 인텐트 패치 밖으로 늘었다: \(widget)")
        let toggle = try Self.code("Sources/CheckWidgetsKit/WidgetTodoToggle.swift")
        #expect(toggle.components(separatedBy: "WidgetSnapshotCodec.write(").count == 2, "인텐트의 스냅샷 쓰기는 체크 패치 한 곳이어야 한다")
    }

    @Test("알림 설정 저장은 푸시 코디네이터 하나(나 탭은 공개 API 만) · 오목 창 열기 문과 화면 꺼짐 방지는 게임 탭만")
    func singleOwners() throws {
        // 저장 경로는 세 층이다 — 코디네이터(`savePushPrefs` 호출) → 세션(`savePushPrefs` 정의 · `setPushPrefs` 호출) → 서비스
        // (`setPushPrefs` 정의 · RPC 경로). 층마다 **이름이 나오는 파일 집합**을 못 박는다: 세션 메서드 이름만 보면 서비스
        // `setPushPrefs` 나 RPC 경로를 직접 부르는 두 번째 구현이 초록으로 지나갔다(int-verify M7).
        let layers: [(needles: [String], owners: Set<String>)] = [
            (["savePushPrefs("], ["Sources/CheckMobileKit/Push/PushCoordinator.swift", "Sources/CheckMobileKit/Session/MobileSessionStore.swift"]),
            (["setPushPrefs("], ["Sources/CheckMobileKit/Session/MobileSessionStore.swift", "Sources/CheckMobileKit/Session/MobileDeviceService.swift"]),
            (["set_push_prefs", "SetPushPrefsRequest("], ["Sources/CheckMobileKit/Session/MobileDeviceService.swift"]),
        ]
        for layer in layers {
            let hits = try Self.files(containing: layer.needles, under: "Sources/CheckMobileKit")
            #expect(Set(hits) == layer.owners, "알림 설정 저장 구현이 두 벌이다(\(layer.needles)): \(hits)")
        }
        // 나 탭은 **폴더 전체**에서 저장·권한 읽기를 코디네이터 공개 API 로만 한다(뷰뿐 아니라 스토어 확장 파일도).
        let meFolder = try Self.files(
            containing: ["savePushPrefs(", "setPushPrefs(", "set_push_prefs", "PushPrefs(", "UNUserNotificationCenter", "requestAuthorization("],
            under: "Sources/CheckMobileKit/Me"
        )
        #expect(meFolder.isEmpty, "나 탭이 알림 설정을 코디네이터 밖에서 만들거나 저장한다: \(meFolder)")
        let meSettings = try Self.code("Sources/CheckMobileKit/Me/MeSettingsView.swift")
        for api in ["push.setPreference(", "push.enableNotifications()", "push.refreshAuthorization()", "push.openSystemSettings()", "push.knowsPrefs"] {
            #expect(meSettings.contains(api), "나 탭 설정 화면이 코디네이터 \(api) 를 쓰지 않는다")
        }
        #expect(!meSettings.contains("UNUserNotificationCenter"), "나 탭이 권한을 따로 읽는다")

        let windowOpeners = try Self.files(containing: ["presentWindow ="], under: "Sources/CheckMobileKit")
        #expect(windowOpeners == ["Sources/CheckMobileKit/Games/GamesStore.swift"], "오목 창 열기 문을 게임 탭 밖에서 덮는다: \(windowOpeners)")
        let idle = try Self.files(containing: ["isIdleTimerDisabled"], under: "Sources/CheckMobileKit")
        #expect(!idle.isEmpty && idle.allSatisfy { $0.hasPrefix("Sources/CheckMobileKit/Games/") }, "화면 꺼짐 방지를 게임 탭 밖에서 쓴다: \(idle)")
    }

    @Test("위젯 확장은 자기 번들의 CheckConfig.plist 를 읽는다(앱 번들 거슬러 읽기 없음) · 두 타깃 모두 생성 단계가 있다")
    func widgetBundleCarriesConfig() throws {
        let model = try Self.code("Sources/CheckWidgetsKit/AingWidgetModel.swift")
        #expect(model.contains("enum AingWidgetConfig"), "대조: 설정 타입을 못 찾았다")
        #expect(!model.contains("deletingLastPathComponent"), "위젯이 여전히 앱 번들을 거슬러 읽는다")
        let project = try String(contentsOf: Self.root.appendingPathComponent("ios/project.yml"), encoding: .utf8)
        let widgetTarget = try #require(project.range(of: "\n  AingCheckWidgets:\n"))
        let appPart = project[project.startIndex..<widgetTarget.lowerBound]
        let widgetPart = project[widgetTarget.upperBound...]
        #expect(appPart.contains("name: CheckConfig.plist"), "앱 타깃 생성 단계가 없다")
        #expect(widgetPart.contains("name: CheckConfig.plist"), "위젯 타깃 생성 단계가 없다")
        #expect(widgetPart.contains("Config/AingCheck.xcconfig"), "위젯 타깃이 키 원천(xcconfig)을 읽지 않는다")
    }

    // MARK: - 루비 미러(나 ↔ 게임)

    @Test("루비 미러: 오목 정산은 나 탭에, 나 탭 상점은 게임 탭에 곧바로 보인다(둘 다 context.gomokuHost.rubyBalance)")
    func rubyMirrorIsShared() async {
        let harness = await RankMeHarness(label: "int-ruby") { request in
            if request.rpcName == "shop_state" { return .json(#"{"ruby_balance":40,"characters":[{"id":"fox","price":30,"owned":true}]}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let model = harness.model
        #expect(model.me.rubyBalance == nil && model.games.rubyBalance == nil)

        harness.enqueue("gomoku_inbox", .json(#"{"status":"ok","incoming":[],"outgoing":null,"active_match_id":null,"ruby_balance":100,"server_now_ms":1789621500000}"#))
        await model.gomoku.loadInbox()
        #expect(model.gomoku.rubyBalance == 100, "대조: 오목 받은함이 잔액을 적지 않았다")
        #expect(model.me.rubyBalance == 100, "오목 정산이 나 탭 잔액에 오지 않았다")
        #expect(model.games.rubyBalance == 100)

        await model.me.loadShop()
        #expect(model.me.rubyBalance == 40)
        #expect(model.gomoku.rubyBalance == 100, "대조: 상점은 코어 오목 값을 적지 않는다(미러만)")
        #expect(model.games.rubyBalance == 40, "나 탭 상점 잔액이 게임 탭에 안 보인다(코어 값을 먼저 읽는다)")
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 데모 픽스처(합친 뒤)

    /// 데모 라우트(`MobileDemo` 머리 주석 · SPEC-ios-build §1-8)와 탭 작업자가 더한 결과 장면.
    static let demoRoutes = [
        "now",
        // 서버 상태 장면(`update` 와 같은 갈래 — 탭 라우트가 아니다): 소속이 빈 배열이라 지금 탭이 무소속 합류 카드로 선다.
        "now/teamless",
        "messages", "rankings/league", "rankings/tokens", "rankings/minigame", "games", "games/timing", "games/flappy",
        "games/gomoku/lobby", "games/gomoku/match", "me", "me/shop", "me/feedback", "me/settings", "login", "update",
        // 체스(0.3.50 — 화면보다 **데모 데이터를 먼저** 둔 순서다): 로비·순위는 장면 없는 바깥 층이 답하고, 변형 셋만
        // 장면이다. 대국·관전 변형은 장면이 아니라 **바늘**(본문의 `p_match_id`)로 갈린다 —
        // `games/chess/match/demo-chess-flagdraw` 처럼 라우트 꼬리가 그대로 match id 다(`GamesChessFixtureContractTests`).
        "games/chess/lobby", "games/chess/lobby/invites", "games/chess/match",
        "games/chess/ranking", "games/chess/ranking/unlisted",
        // 1:1 테트리스(1.0.11 — 라우트 표는 `MobileDemoTetrisRoute` 머리말, 픽스처 계약은 `GamesTetrisFixtureContractTests`).
        // 로비 머리·순위는 장면 없는 바깥 층이 답하고, 신청 변형과 판 여섯 장면만 장면 폴더다.
        // ★ **`games/tetris` 한 토막은 여기 없다** — 그 글자는 혼자 하는 미니게임 테트리스(`AingRoute.MiniGame.tetris`,
        //   v0.3.38)의 것이고 1:1 쪽은 `games/tetris/lobby` 로 연다(그 까닭은 `MobileDemoTetrisRoute` 머리말 3).
        "games/tetris/lobby", "games/tetris/lobby/invites", "games/tetris/ranking",
        "games/tetris/match/ready", "games/tetris/match/countdown", "games/tetris/match/playing",
        "games/tetris/match/speedup", "games/tetris/match/won", "games/tetris/match/lost",
        // 나 탭 기록 없는 계정(w15 E): 라우트는 `me` 와 같게 열리고(끝 `/` 는 버려진다) 장면만 `_me-`.
        "me/",
        // 상점 뽑기 시트(폰 1.0.10 색 시안): 라우트는 `me/shop` 으로 열리고 장면도 `_me-shop` 이다 —
        // 시트 이름만 따로 간다(`MobileDemoShopSheetRoute`). 새 장면 폴더가 없으므로 아래 장면 대조에는 걸리지 않는다.
        "me/shop/odds", "me/shop/exchange",
        // 로그인 **아래** 화면(w16): 탭 라우트가 아니라 `MobileAuthRoute` 다. 가입 인증코드 장면(`_signup-confirm`)만
        // 픽스처를 덮어쓴다 — 그 장면의 가입 응답은 세션이 없다(설정을 켠 서버).
        "signup", "signup/create", "signup/confirm", "reset",
    ]

    @Test("데모 픽스처: 합친 뒤 키 유일 · 모든 장면 폴더가 실제 데모 라우트의 장면이다(오타 장면은 조용히 안 쓰인다)")
    func demoFixtureScenesMatchRoutes() {
        let fixtures = MobileDemoFixtures.load()
        #expect(fixtures.duplicateKeys.isEmpty, "\(fixtures.duplicateKeys)")
        let scenes = Set(fixtures.entries.compactMap(\.scenario))
        #expect(!scenes.isEmpty)
        for scene in scenes {
            var candidates = Self.demoRoutes
            if scene.hasPrefix("messages-") { candidates.append("messages/" + scene.dropFirst("messages-".count)) }
            if scene.hasPrefix("games-gomoku-match-") { candidates.append("games/gomoku/match/" + scene.dropFirst("games-gomoku-match-".count)) }
            let route = candidates.first { $0.replacingOccurrences(of: "/", with: "-").lowercased() == scene }
            #expect(route != nil, "장면 폴더 _\(scene) 에 맞는 데모 라우트가 없다")
            // 탭 라우트만 `AingRoute` 로 열린다. 로그인 화면·업데이트 화면·로그인 아래 화면(가입·재설정)은 저쪽 길이고,
            // `now/teamless` 는 **서버 상태 장면**이라(소속이 빈 배열) 열 라우트가 없다 — 기본 탭(지금)에 그대로 선다.
            // 체스는 **아직 화면이 없어서**(데모 데이터를 먼저 두는 순서였다) `AingRoute` 에 케이스가 없다 —
            // 그 예외는 아래 ★ 단언이 **스스로 만료시킨다**.
            let chessHasNoRouteYet = route?.hasPrefix("games/chess/") == true
            // 테트리스 1:1 도 같은 갈래다: `AingRoute` 에 가지가 없고(가지를 더하면 `games/tetris` 가 **이미** 솔로
            // 미니게임이라 두 기능이 한 글자를 다툰다 — `MobileDemoTetrisRoute` 머리말 3) 앱 모델의 데모 갈래가 연다.
            // 아래 ★ 단언이 이 예외를 스스로 만료시킨다.
            let tetrisHasNoRouteYet = route?.hasPrefix("games/tetris/") == true
            if let route, !["login", "update", "now/teamless"].contains(route), !chessHasNoRouteYet,
               !tetrisHasNoRouteYet, MobileAuthRoute.demo(route) == nil {
                #expect(AingRoute(path: route) != nil, "장면 _\(scene) 의 라우트 \(route) 를 앱이 열지 못한다")
            }
        }
        // ★ 자기 만료 예외. 체스 화면 작업자가 `AingRoute` 에 chess 케이스를 더하는 날 이 줄이 빨개진다 —
        // 그때 위 `chessHasNoRouteYet` 갈래를 **지우고** 체스 장면도 다른 탭처럼 열리는지 재라.
        // (예외를 조용히 남겨 두면 "장면 폴더가 실제 라우트다" 가 체스에서만 빈말이 된다.)
        #expect(AingRoute(path: "games/chess/lobby") == nil,
                "체스 라우트가 생겼다 — 위 games/chess 예외 갈래를 지워라")
        #expect(AingRoute(path: "games/tetris/lobby") == nil,
                "1:1 테트리스 라우트가 생겼다 — 위 games/tetris 예외 갈래를 지워라")
        // ★ 그리고 **`games/tetris` 한 토막은 여전히 솔로 미니게임이어야 한다.** 1:1 쪽이 이 글자를 가로채는 날
        // (데모 갈래가 `AingRoute` 보다 앞이므로 가로채는 것은 한 줄이다) 솔로 테트리스 데모 라우트가 조용히 사라진다 —
        // 설계서 P1 의 "솔로는 한 글자도 건드리지 않는다" 를 동작으로 어기는 자리다.
        #expect(AingRoute(path: "games/tetris") == .miniGame(.tetris),
                "games/tetris 는 혼자 하는 미니게임 테트리스다 — 1:1 쪽이 가로채면 솔로 데모 라우트가 사라진다")
        #expect(MobileDemoTetrisRoute(demoRoute: "games/tetris") == nil,
                "1:1 테트리스 값이 games/tetris 한 토막을 가로챘다(솔로 미니게임의 글자다)")
        // 라우트마다 그 탭의 첫 화면 픽스처가 적어도 하나는 닿는다(장면 또는 바깥 층).
        let firstScreenKeys: [String: [String]] = [
            // rpc.work_phone_touch(0.3.51): 지금 탭이 active 마다 보내는 생존 신호 — 없으면 404 로 접혀 데모에서 근무 버튼이 숨는다.
            "now": ["rest.work_statuses.get", "rpc.todo_sync", "rpc.work_phone_touch"],
            "now/teamless": ["rpc.work_phone_touch"],
            "messages": ["rpc.message_history_with_reads", "rpc.message_unread_summary"],
            "rankings/league": ["rpc.team_weekly_leaderboard"],
            "rankings/tokens": ["rpc.token_usage_board"],
            "rankings/minigame": ["rpc.minigame_board", "rpc.minigame_yesterday_winner"],
            "games": ["rpc.minigame_board", "rpc.gomoku_inbox"],
            "games/timing": ["rpc.minigame_board", "rpc.minigame_start_round"],
            "games/flappy": ["rpc.minigame_board", "rpc.minigame_start_round"],
            "games/gomoku/lobby": ["rpc.gomoku_lobby", "rpc.gomoku_inbox"],
            "games/gomoku/match": ["rpc.gomoku_state", "rpc.gomoku_lobby"],
            "games/chess/lobby": ["rpc.chess_lobby"],
            "games/chess/match": ["rpc.chess_state", "rpc.chess_lobby"],
            "games/chess/ranking": ["rpc.chess_ranking"],
            // 1:1 테트리스. 판 장면이 `rpc.tetris_report` 를 함께 요구하는 것이 핵심이다 — 판 중에는 1초마다 보고가
            // 나가고, 그 키가 404 면 `noteServerMissing()` 이 1초 뒤 판 화면을 통째로 내린다(빈 화면 스틸의 정체).
            "games/tetris/lobby": ["rpc.tetris_lobby"],
            "games/tetris/lobby/invites": ["rpc.tetris_lobby", "rpc.tetris_state"],
            "games/tetris/ranking": ["rpc.tetris_ranking"],
            "games/tetris/match/playing": ["rpc.tetris_lobby", "rpc.tetris_state", "rpc.tetris_report"],
            "games/tetris/match/won": ["rpc.tetris_lobby", "rpc.tetris_state"],
            "me": ["rpc.shop_state", "rest.work_sessions.get"],
            "me/shop": ["rpc.shop_state"],
            "me/feedback": ["rpc.feedback_list"],
            "me/settings": ["rpc.my_team_invite_code"],
        ]
        for (route, keys) in firstScreenKeys {
            let scene = route.replacingOccurrences(of: "/", with: "-")
            for key in keys {
                let reachable = fixtures.entries.contains { $0.key == key && ($0.scenario == nil || $0.scenario == scene) }
                #expect(reachable, "데모 라우트 \(route) 에서 \(key) 픽스처가 닿지 않는다(404 로 빈 화면)")
            }
        }
    }

    // MARK: - 도우미

    static func code(_ relative: String) throws -> String {
        stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    /// `under` 아래 .swift 중 주석을 걷어낸 코드에 needles 가운데 하나라도 든 파일(저장소 상대 경로, 정렬).
    static func files(containing needles: [String], under relative: String) throws -> [String] {
        let base = root.appendingPathComponent(relative)
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var hits: [String] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let code = stripComments(try String(contentsOf: url, encoding: .utf8))
            if needles.contains(where: { code.contains($0) }) {
                hits.append(String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1)))
            }
        }
        return hits.sorted()
    }
}
