import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 데모 스크린샷 라우트 `games/tetris/…`(1:1 테트리스 · 1.0.11) 의 계약 — 설계서 §5 표를 **값으로** 못 박는다.
//
// ── 왜 이 파일이 필요한가 ──
// 테트리스 화면은 전부 `#if os(iOS)` 안이라 맥 `swift test` 가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가
// 못 본다'). 그래서 "라우트 아홉 개가 서로 다른 장면으로 간다" 를 증명할 수 있는 자리는 플랫폼 분기 없는 값
// (`MobileDemoTetrisRoute`)뿐이다. 체스에서 꼬리를 깃발 하나로 접었다가 라우트 일곱 중 넷이 **같은 로비**를
// 그렸고(스크린샷 md5 동일) 아무도 순위·대국·관전을 눈으로 못 봤다 — 그 결함(D6)이 이 파일의 까닭이다.
//
// 재는 것 다섯:
//   ① 표의 아홉 라우트가 각각 **다른** 장면으로 간다(갈림 자체를 센다).
//   ② 장면 이름이 스텁의 고르기 규칙(`/` → `-`)과 **한 식**이고, 장면 폴더가 있어야 할 것에만 있다.
//   ③ 판 장면의 `focusMatchID` 가 실제 상태 픽스처의 바늘과 같다(틀리면 404 가 화면을 내린다).
//   ④ 모르는 꼬리가 **로비 머리로 접힌다**(조용히 버리지 않는다) · 남의 데모 라우트를 테트리스로 읽지 않는다.
//   ⑤ `games/tetris` 한 토막은 **솔로 미니게임의 글자**다 — 1:1 쪽이 가로채면 안 된다.
@Suite struct GamesTetrisDemoRouteTests {

    static let index = MobileDemoFixtures.load()

    /// 설계서 §5 표. `scene` 은 기대 장면, `focus` 는 코어에 넘길 판 id, `tab` 은 로비에서 열어 둘 탭.
    struct Row {
        let route: String
        let scene: MobileDemoTetrisRoute.Scene
        let focus: String?
        let tab: MobileDemoTetrisRoute.LobbyTab
    }

    static let table: [Row] = [
        .init(route: "games/tetris/lobby", scene: .lobby, focus: nil, tab: .opponents),
        .init(route: "games/tetris/lobby/invites", scene: .lobbyInvites, focus: nil, tab: .opponents),
        .init(route: "games/tetris/ranking", scene: .ranking, focus: nil, tab: .ranking),
        .init(route: "games/tetris/match/ready", scene: .matchReady, focus: "demo-tetris-ready", tab: .opponents),
        .init(route: "games/tetris/match/countdown", scene: .matchCountdown, focus: "demo-tetris-countdown", tab: .opponents),
        .init(route: "games/tetris/match/playing", scene: .matchPlaying, focus: "demo-tetris-playing", tab: .opponents),
        .init(route: "games/tetris/match/speedup", scene: .matchSpeedup, focus: "demo-tetris-speedup", tab: .opponents),
        .init(route: "games/tetris/match/won", scene: .matchWon, focus: "demo-tetris-won", tab: .opponents),
        .init(route: "games/tetris/match/lost", scene: .matchLost, focus: "demo-tetris-lost", tab: .opponents),
    ]

    // MARK: - ① 표 그대로 풀린다

    @Test("설계서 §5 표의 아홉 라우트가 기대한 장면·판·탭으로 간다")
    func theTableResolvesAsWritten() throws {
        for row in Self.table {
            let parsed = try #require(MobileDemoTetrisRoute(demoRoute: row.route), "\(row.route): 값이 안 선다")
            #expect(parsed == MobileDemoTetrisRoute(scene: row.scene), "\(row.route): \(parsed.scene)")
            #expect(parsed.focusMatchID == row.focus, "\(row.route): 열 판 \(parsed.focusMatchID ?? "nil")")
            #expect(parsed.lobbyTab == row.tab, "\(row.route): 로비 탭 \(parsed.lobbyTab)")
            // 아홉 장면이 **한 화면**으로 간다(설계서 P6 — 화면 하나가 단계를 갈아 끼운다).
            #expect(parsed.destination == .tetrisDuel, "\(row.route): 게임 탭 경로")
        }
        #expect(Self.table.count == MobileDemoTetrisRoute.Scene.allCases.count,
                "표와 장면 열거의 수가 다르다 — 한쪽만 넓히면 새 장면이 조용히 로비로 접힌다")
        // 정규 라우트 글자가 열거의 rawValue 다 — 표가 두 벌이면 갈린다.
        #expect(Self.table.map(\.route) == MobileDemoTetrisRoute.Scene.allCases.map(\.rawValue))
    }

    @Test("갈림: 아홉 라우트가 서로 다른 장면이고, 판 여섯은 서로 다른 판을 연다")
    func everyRouteLandsSomewhereDifferent() {
        let scenes = Self.table.map { MobileDemoTetrisRoute(demoRoute: $0.route)?.scenario }
        #expect(Set(scenes.compactMap { $0 }).count == 9, "두 라우트가 같은 장면으로 간다: \(scenes)")
        let focuses = Self.table.compactMap { MobileDemoTetrisRoute(demoRoute: $0.route)?.focusMatchID }
        #expect(Set(focuses).count == 6, "판 장면이 같은 판을 연다: \(focuses)")
        // 순위만 다른 탭이다 — 전부 같은 탭이면 `games/tetris/ranking` 이 로비 머리와 같은 그림이 된다.
        let tabs = Self.table.map { MobileDemoTetrisRoute(demoRoute: $0.route)?.lobbyTab }
        #expect(tabs.filter { $0 == .ranking }.count == 1)
    }

    // MARK: - ② 장면 이름이 스텁과 한 식이다

    @Test("장면 이름이 스텁의 고르기 규칙과 같고, 장면 폴더가 있어야 할 것에만 있다")
    func scenarioNamesMatchTheStubRule() {
        for row in Self.table {
            // `MobileDemo.environment` 가 쓰는 바로 그 식.
            let want = row.route.replacingOccurrences(of: "/", with: "-").lowercased()
            #expect(MobileDemoTetrisRoute(demoRoute: row.route)?.scenario == want, "\(row.route) → \(want)")
        }
        // 장면 폴더가 있는 것은 **로비 변형이 필요한** 일곱이다. 로비 머리·순위는 바깥 층이 답한다
        // (폴더를 두면 같은 파일이 두 벌이 되어 어느 쪽이 답하는지가 정렬에 달린다).
        let folders = Set(Self.index.entries.compactMap(\.scenario).filter { $0.hasPrefix("games-tetris") })
        #expect(folders == [
            "games-tetris-lobby-invites",
            "games-tetris-match-ready", "games-tetris-match-countdown", "games-tetris-match-playing",
            "games-tetris-match-speedup", "games-tetris-match-won", "games-tetris-match-lost",
        ], "장면 폴더 집합: \(folders.sorted())")
        // 폴더가 하나라도 표 밖의 이름이면 그 폴더는 **조용히 안 쓰인다**(IntegrationContractTests 가 같은 것을 센다).
        let known = Set(Self.table.map { $0.route.replacingOccurrences(of: "/", with: "-") })
        #expect(folders.subtracting(known).isEmpty, "표에 없는 장면 폴더: \(folders.subtracting(known).sorted())")
    }

    // MARK: - ③ focusMatchID 가 실제 바늘이다

    @Test("판 장면의 focusMatchID 마다 상태 픽스처가 있다(틀리면 404 가 화면을 내린다)")
    func everyFocusMatchIDHasAStateFixture() throws {
        for row in Self.table {
            guard let focus = MobileDemoTetrisRoute(demoRoute: row.route)?.focusMatchID else { continue }
            let request = MobileStubRequest(
                method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/tetris_state",
                query: "", headers: [:], bodyText: #"{"p_protocol":1,"p_match_id":"\#(focus)"}"#)
            let scenario = row.route.replacingOccurrences(of: "/", with: "-")
            let entry = try #require(Self.index.entry(for: request, scenario: scenario), """
                \(row.route): 판 id \(focus) 의 상태 픽스처가 없다 — 그 id 로 refreshMatch 가 나가면
                404(PGRST202)가 noteServerMissing() 을 때려 화면이 통째로 '서버가 모른다' 로 바뀐다.
                """)
            #expect(entry.needle == focus, "\(row.route): 바늘 \(entry.needle ?? "nil") ≠ 판 id \(focus)")
            // 같은 장면의 로비도 그 판을 가리켜야 한다(두 길이 한 판을 열어야 겹쳐도 멱등이다).
            let lobbyRequest = MobileStubRequest(
                method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/tetris_lobby",
                query: "", headers: [:], bodyText: #"{"p_protocol":1}"#)
            let lobby = try #require(Self.index.entry(for: lobbyRequest, scenario: scenario))
            let object = try JSONSerialization.jsonObject(with: lobby.data) as? [String: Any]
            let mine = try #require(object?["me"] as? [String: Any], "\(row.route): 로비에 me 가 없다")
            #expect(mine["active_match_id"] as? String == focus,
                    "\(row.route): 로비의 active_match_id 가 \(focus) 를 안 가리킨다")
        }
    }

    // MARK: - ④ 모르는 꼬리 · 남의 라우트

    @Test("모르는 꼬리는 로비 머리로 접힌다(조용히 버리지 않는다) · 끝 슬래시·대문자·빈 칸을 받는다")
    func unknownTailsFoldIntoTheLobbyHead() {
        let folded = [
            "games/tetris/match",                  // 꼬리가 없다
            "games/tetris/match/demo-tetris-live", // 상태 픽스처가 없는 판 id
            "games/tetris/match/ready/extra",      // 토막이 하나 더
            "games/tetris/nope",
            "games/tetris/ranking/unlisted",       // 체스에는 있지만 테트리스에는 없는 변형
            "games/tetris/lobby/invites/extra",
        ]
        for raw in folded {
            let parsed = MobileDemoTetrisRoute(demoRoute: raw)
            #expect(parsed == MobileDemoTetrisRoute(scene: .lobby), """
                \(raw): 로비 머리로 접혀야 한다(나온 값 \(String(describing: parsed))).
                nil 로 버리면 앱 모델이 AingRoute 로 내려가 거기서도 nil 이라 데모가 기본 탭(지금)에 머문다 —
                라우트 오타를 사람이 못 가린다. 머리로 접으면 열린 화면이 테트리스라 틀린 꼬리가 **보인다**.
                """)
            #expect(parsed?.focusMatchID == nil, "\(raw): 모르는 id 를 코어에 흘리면 404 가 화면을 내린다")
        }
        // 글자 다듬기: 끝 슬래시 · 대문자 · 앞뒤 빈 칸.
        #expect(MobileDemoTetrisRoute(demoRoute: " /games/tetris/match/SPEEDUP/ ")
                == MobileDemoTetrisRoute(scene: .matchSpeedup))
        #expect(MobileDemoTetrisRoute(demoRoute: "games/tetris/lobby/")
                == MobileDemoTetrisRoute(scene: .lobby))
        // 남의 데모 라우트를 테트리스로 읽지 않는다.
        for raw in ["games", "games/flappy", "games/timing", "games/gomoku/lobby", "games/gomoku/match",
                    "games/chess/lobby", "games/chess/match/demo-chess-promo", "me/shop/odds",
                    "now", "update", "games/tetrisduel/lobby", "tetris/lobby"] {
            #expect(MobileDemoTetrisRoute(demoRoute: raw) == nil, "남의 데모 라우트를 테트리스로 읽었다: \(raw)")
            #expect(!MobileDemoTetrisRoute.isTetrisDuelRoute(raw), "되묻기가 남의 라우트에 참이다: \(raw)")
        }
        // 되묻기와 꼬리 풀기가 **한 판정**이어야 한다(두 판정이 갈리면 화면과 픽스처가 어긋난다).
        for row in Self.table {
            #expect(MobileDemoTetrisRoute.isTetrisDuelRoute(row.route))
        }
    }

    // MARK: - ⑤ `games/tetris` 한 토막은 솔로의 글자다

    @Test("games/tetris 한 토막은 혼자 하는 미니게임 테트리스다 — 1:1 쪽이 가로채지 않는다")
    func theBareGamesTetrisRouteStillBelongsToTheSoloMiniGame() {
        // 설계서 §5 표는 `games/tetris` 를 로비 머리의 별칭으로 적었지만 그 글자에는 **이미 주인이 있다**:
        // `AingRoute.MiniGame.tetris`(v0.3.38). 앱 모델은 데모 갈래를 `AingRoute` 보다 **앞**에 두므로
        // 여기서 그 한 토막을 받으면 솔로 테트리스 데모 라우트가 통째로 사라진다 — 설계서 P1 의
        // "솔로 테트리스는 한 글자도 건드리지 않는다" 를 글자가 아니라 **동작으로** 어기는 일이다.
        #expect(AingRoute(path: "games/tetris") == .miniGame(.tetris), "대조: 솔로 라우트가 이미 사라졌다")
        #expect(MobileDemoTetrisRoute(demoRoute: "games/tetris") == nil)
        #expect(MobileDemoTetrisRoute(demoRoute: "games/TETRIS") == nil)
        #expect(!MobileDemoTetrisRoute.isTetrisDuelRoute("games/tetris"))
        // 1:1 쪽의 머리는 한 토막 더 붙은 글자다. 거기에는 `AingRoute` 가 주인이 없다.
        #expect(AingRoute(path: "games/tetris/lobby") == nil)
        #expect(MobileDemoTetrisRoute(demoRoute: "games/tetris/lobby") != nil)
    }

    // MARK: - 소스 계약: 값과 배선이 전부 `#if DEBUG` 안이다

    @Test("꼬리 값과 그 이름이 나오는 줄이 전부 #if DEBUG 안이다 · #if os(iOS) 가 없다")
    func theRouteValueIsDebugOnlyAndPlatformFree() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = "Sources/CheckMobileKit/Demo/MobileDemoTetrisRoute.swift"
        let raw = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        // ★ 소스 계약은 **주석을 걷고** 읽는다(하우스 규칙). 안 걷으면 이 파일의 설명문이 자기 금지 낱말을 품고 있어
        //   (`#if os(iOS)` 를 쓰지 마라 · `openWindow(` 는 배선 레인의 몫이다) 설명을 **지워야만** 초록이 된다.
        let typeFile = stripComments(raw)
        #expect(typeFile.contains("package struct MobileDemoTetrisRoute"), "꼬리 값 타입이 그 파일에 없다 — 경로가 틀렸다")
        #expect(raw.hasPrefix("#if DEBUG"), "파일이 #if DEBUG 로 시작하지 않는다")
        #expect(raw.hasSuffix("#endif\n"), "파일이 #endif 로 끝나지 않는다")
        // `#if os(iOS)` 를 더하는 순간 맥 스위트가 이 판정을 한 줄도 못 보게 된다(위 머리말).
        #expect(!typeFile.contains("#if os("), "플랫폼 분기를 더하면 이 스위트가 통째로 사라진다")
        // 수명 호출(화면 열기·닫기)은 **배선 레인의 몫**이다 — 데모 값이 코어 창 수명을 직접 부르면 두 주인이 생긴다.
        for forbidden in ["tetrisScreenDidAppear", "tetrisScreenDidDisappear", "openWindow(", "presentTetrisScreen"]
            where typeFile.contains(forbidden) {
            Issue.record("데모 라우트 값이 화면 수명 문을 부른다(배선 레인의 소유다): \(forbidden)")
        }
        // 이 이름이 나오는 **모든 소스 줄**이 DEBUG 안이어야 한다(Release 바이너리에 이름이 남으면 출시 게이트가 막는다).
        // 테스트는 세지 않는다 — 테스트 타깃은 앱 번들에 들어가지 않고 언제나 Debug 로 돈다.
        let base = root.appendingPathComponent("Sources/CheckMobileKit")
        let enumerator = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        var sourcesSeen = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = stripComments(try String(contentsOf: url, encoding: .utf8))
            guard text.contains("MobileDemoTetrisRoute") else { continue }
            sourcesSeen += 1
            var depth = 0
            var debugDepth: Int?
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if") {
                    depth += 1
                    if trimmed.contains("DEBUG"), debugDepth == nil { debugDepth = depth }
                } else if trimmed.hasPrefix("#endif") {
                    if debugDepth == depth { debugDepth = nil }
                    depth -= 1
                }
                guard line.contains("MobileDemoTetrisRoute") else { continue }
                #expect(debugDepth != nil, """
                    \(url.lastPathComponent): 이 줄이 #if DEBUG 밖이다 — Release 바이너리에
                    `MobileDemoTetrisRoute` 가 남아 출시 게이트(check-release-app.sh 금지 문자열 MobileDemo)가 막는다.
                    \(trimmed)
                    """)
            }
        }
        #expect(sourcesSeen >= 1, "대조: 이름이 나오는 소스 파일을 하나도 못 찾았다(경로가 틀렸나)")
    }
}
