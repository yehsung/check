@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **데모 라우트 꼬리**의 못 — `-AingCheckDemoRoute games/chess/…` 가 **실제로 다른 화면을 띄우는가.**
//
// ── 무엇을 재는가(그리고 무엇을 재지 않는가) ──
// "꼬리를 파싱했다" 는 재지 않는다. 라우트 글자 하나를 넣고 **데모 픽스처가 답하는 실제 스토어 상태**
// (단계 · 열린 판 id · 걸린 관전 id · 로비 시작 절)를 값으로 받아, 라우트마다 그 값이 **서로 다른지** 본다.
//
// ── 이 파일이 생긴 까닭(결함 D6) ──
// `openDemoRouteIfNeeded` 가 `games/chess/…` 를 보면 **꼬리를 버리고** Bool 깃발 하나만 세웠다. 그래서
// 라우트 일곱을 주어도 전부 같은 로비가 떴고 — 스크린샷 레인이 md5 동일로 잡았다(여섯 장이 **바이트 동일**) —
// 아무도 순위·관전·대국 화면을 눈으로 보지 못했다. 픽스처 19장은 그 전에 이미 다 있었다.
// 교훈: **"라우트가 있다" 는 "화면이 뜬다" 를 뜻하지 않는다.** 그래서 이 스위트는 라우트 → 화면을 재고,
// 꼬리를 되돌리면(값을 버리면) 빨개진다.
//
// ── 왜 맥에서 재나 ──
// 체스 화면은 전부 `#if os(iOS)` 안이라 맥 스위트가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
// 그래서 라우트 → 화면 판정을 플랫폼 분기 없는 두 자리(`MobileDemoChessRoute` · `GamesStore`)에 두고,
// 뷰가 그 값을 실제로 쓰는지만 **소스 글자로** 되묻는다(§3 — `GamesChessWiringTests` 와 같은 관례).
@MainActor
@Suite(.serialized) struct GamesChessDemoRouteTests {
    /// 라우트 한 건이 세워야 하는 값들. `scene` 은 스텁이 고르는 장면 폴더 이름(`MobileDemo`: `/` → `-`).
    private struct Expectation {
        let route: String
        let focus: String?
        let watch: String?
        let section: MobileDemoChessRoute.Section
        /// 끝까지 돌렸을 때 서야 하는 코어 단계.
        let phase: ChessPhase
        /// 끝까지 돌렸을 때 `chess.match?.id`(nil = 판이 없어야 한다).
        let matchID: String?
        /// 끝까지 돌렸을 때 `chess.spectating?.id`.
        let watchingID: String?
    }

    /// ★ 라우트 일곱 — 인수인계 표 그대로. 셋(`match/<id>`·`ranking…`·`watch/<id>`)이 **고치기 전에는 전부 로비**였다.
    private static let table: [Expectation] = [
        .init(route: "games/chess", focus: nil, watch: nil, section: .top,
              phase: .lobby, matchID: nil, watchingID: nil),
        .init(route: "games/chess/lobby", focus: nil, watch: nil, section: .top,
              phase: .lobby, matchID: nil, watchingID: nil),
        .init(route: "games/chess/lobby/invites", focus: nil, watch: nil, section: .top,
              phase: .lobby, matchID: nil, watchingID: nil),
        // 꼬리 없는 `match` 는 **장면 폴더**가 판을 정한다(`_games-chess-match` 의 `me.active_match_id`).
        .init(route: "games/chess/match", focus: nil, watch: nil, section: .top,
              phase: .playing, matchID: "demo-chess-my-turn", watchingID: nil),
        // 꼬리가 붙으면 장면 폴더가 없다 → 바깥 층 로비(진행 판 없음)라 **꼬리를 코어 문에 넣어야** 열린다.
        .init(route: "games/chess/match/demo-chess-flagdraw", focus: "demo-chess-flagdraw", watch: nil, section: .top,
              phase: .result, matchID: "demo-chess-flagdraw", watchingID: nil),
        .init(route: "games/chess/match/demo-chess-mate-win", focus: "demo-chess-mate-win", watch: nil, section: .top,
              phase: .result, matchID: "demo-chess-mate-win", watchingID: nil),
        .init(route: "games/chess/match/demo-chess-incheck", focus: "demo-chess-incheck", watch: nil, section: .top,
              phase: .playing, matchID: "demo-chess-incheck", watchingID: nil),
        // 순위는 **로비 안 절**이라 화면이 아니라 스크롤 닻이 바뀐다(절은 로비 맨 아래).
        .init(route: "games/chess/ranking", focus: nil, watch: nil, section: .bottom,
              phase: .lobby, matchID: nil, watchingID: nil),
        .init(route: "games/chess/ranking/unlisted", focus: nil, watch: nil, section: .bottom,
              phase: .lobby, matchID: nil, watchingID: nil),
        // 관전도 로비 안 절이고, 데모엔 합성 탭이 없어 꼬리의 id 로 `startWatching` 을 직접 건다.
        .init(route: "games/chess/watch/demo-chess-live", focus: nil, watch: "demo-chess-live", section: .bottom,
              phase: .lobby, matchID: nil, watchingID: "demo-chess-live"),
    ]

    // MARK: - 1. 라우트 글자 → 값

    @Test("라우트 꼬리가 **값으로** 풀린다 — 열 판 · 걸 관전 · 로비 시작 절(꼬리를 버리면 셋이 다 nil·top 이다)")
    func theRouteTailBecomesAValue() {
        for row in Self.table {
            let parsed = MobileAppModel.demoChessRoute(row.route)
            let want = MobileDemoChessRoute(focusMatchID: row.focus, watchMatchID: row.watch, section: row.section)
            #expect(parsed == want, "\(row.route): \(String(describing: parsed)) ≠ \(want)")
            #expect(MobileAppModel.isDemoChessRoute(row.route), "\(row.route)")
        }
        // 앞뒤 공백·슬래시는 흘려 보낸다(인자 따옴표 실수) — 꼬리까지 그대로 살아야 한다.
        #expect(MobileAppModel.demoChessRoute(" /games/chess/match/demo-chess-promo/ ")
                == MobileDemoChessRoute(focusMatchID: "demo-chess-promo"))
        // 대문자 꼬리도 같은 판을 가리킨다(코어가 소문자로 비교한다).
        #expect(MobileAppModel.demoChessRoute("games/chess/watch/DEMO-CHESS-OVER")
                == MobileDemoChessRoute(watchMatchID: "demo-chess-over", section: .bottom))
        // 모르는 꼬리는 **로비 머리**로 접는다(조용히 버리는 것이 아니라 열리기는 한다).
        #expect(MobileAppModel.demoChessRoute("games/chess/nope") == MobileDemoChessRoute())
        // 남의 데모 라우트는 걸리지 않는다 — 걸리면 그 장면이 체스 화면으로 오배달된다.
        for raw in ["games", "games/tetris", "games/gomoku/ai", "gomoku/lobby", "games/chessboard", "me/shop"] {
            #expect(MobileAppModel.demoChessRoute(raw) == nil, "남의 데모 라우트를 체스로 읽었다: \(raw)")
        }

        // ★ **값이 서로 달라야 한다** — 스크린샷 md5 비교의 값판. 꼬리를 버리면 열하나가 한 값으로 뭉친다.
        let fingerprints = Set(Self.table.map { row in
            "\(row.route.replacingOccurrences(of: "/", with: "-"))|\(String(describing: MobileAppModel.demoChessRoute(row.route)!))"
        })
        #expect(fingerprints.count == Self.table.count)
        let tails = Set(Self.table.map { MobileAppModel.demoChessRoute($0.route)! })
        #expect(tails.count == 6, "꼬리가 만드는 서로 다른 값이 \(tails.count) 가지다 — 꼬리를 버리면 1 이다")
    }

    // MARK: - 2. 데모 픽스처로 끝까지 — 라우트가 **다른 화면**을 띄우는가

    @Test("데모 라우트 열이 서로 다른 화면을 세운다: 대국 셋 · 로비 셋 · 순위 절 둘 · 관전 하나(픽스처 실물로)")
    func theRoutesReachDifferentScreens() async {
        let index = MobileDemoFixtures.load()
        // 라우트별 지문(단계·판·관전·절). 끝에서 **몇 가지가 나왔는지**를 센다.
        var prints: [String: String] = [:]
        for row in Self.table {
            let host = BaseStub.makeHost("chess-demo-route")
            let scenario = row.route.replacingOccurrences(of: "/", with: "-").lowercased()
            MobileStubURLProtocol.register(host: host) { request in index.response(for: request, scenario: scenario) }
            let storage = BaseStub.makeStorage()
            let vault = InMemoryTokenVault()
            vault.write(MobileDemo.accessToken, key: AingKeychain.accessTokenKey)
            vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
            storage.defaults.set(MobileDemo.userID, forKey: AingSharedKeys.userID)
            let model = MobileAppModel(environment: MobileEnvironment(
                service: BaseStub.makeService(host: host), vault: vault, storage: storage, appInfo: BaseStub.appInfo,
                clock: .fixed(MobileClock.demoInstant), installationID: MobileDemo.installationID,
                realtimeTransport: nil, runsTimers: false, reloadWidgetTimelines: {}, demoRoute: row.route))
            model.session.clientReleaseTimeoutSeconds = 0
            model.start()
            #expect(await baseWaitUntil { model.session.isSignedIn }, "\(row.route)")
            model.sceneDidBecomeActive()

            // 앱 모델이 **게임 탭을 열고 꼬리를 넘겼는가**(라우트 여는 자리의 계약).
            #expect(await baseWaitUntil { model.router.lastOpenedRoute == .games }, "\(row.route): 게임 탭이 안 열렸다")
            #expect(model.games.pendingDemoChessScreen, "\(row.route): 체스를 쌓으라는 깃발이 안 섰다")
            #expect(model.games.demoChessRoute?.focusMatchID == row.focus, "\(row.route): 열 판 id")
            #expect(model.games.demoChessRoute?.watchMatchID == row.watch, "\(row.route): 걸 관전 id")
            #expect(model.games.demoChessRoute?.section == row.section, "\(row.route): 로비 시작 절")

            // 게임 탭이 하는 일(`GamesTab.applyDemoChessRoute`) → 체스 화면이 나타난다.
            #expect(model.games.consumePendingDemoChessScreen(), "\(row.route)")
            model.games.chessScreenDidAppear()

            let chess = model.chess
            if let want = row.matchID {
                #expect(await baseWaitUntil { chess.match?.id == want && chess.phase == row.phase },
                        "\(row.route): 그 판이 안 열렸다(판=\(chess.match?.id ?? "-") 단계=\(chess.phase))")
            } else {
                // 로비로 떨어져야 하는 라우트: 판이 **서면 안 된다**(바깥 층 로비는 진행 판이 없다).
                #expect(await baseWaitUntil { chess.hasLoadedLobby }, "\(row.route): 로비 응답이 안 왔다")
                #expect(chess.match == nil, "\(row.route): 열 판이 없는데 판이 섰다")
                #expect(chess.phase == .lobby, "\(row.route)")
            }
            if let want = row.watchingID {
                #expect(await baseWaitUntil { chess.spectating?.id == want }, "\(row.route): 관전이 안 걸렸다")
                // 씨앗이 로비 카드의 **두 얼굴**로 찼는가(안 기다리면 스크린샷에 빈 상태가 찍힌다).
                #expect(await baseWaitUntil { chess.spectating?.faces.count == 2 }, "\(row.route): 관전 얼굴이 비었다")
                // ★ **판까지 왔는가** — 여기까지 재지 않으면 '관전을 걸었다'가 빈 판·"불러오고 있어요" 로 끝난다.
                #expect(await baseWaitUntil { chess.spectating?.hasServerState == true },
                        "\(row.route): 관전 응답이 안 왔다(빈 판)")
                #expect(chess.spectating?.position != nil && chess.spectating?.appliedSeq == 14,
                        "\(row.route): 관전 판이 비었다(수=\(chess.spectating?.appliedSeq ?? -1))")
            } else {
                #expect(chess.spectating == nil, "\(row.route): 안 건 관전이 걸렸다")
            }
            // 순위는 두 라우트 모두 **같은 절**이고 픽스처만 갈린다(목록 안 3위 ↔ 목록 밖 11위).
            if row.route.hasPrefix("games/chess/ranking") {
                #expect(await baseWaitUntil { chess.ranking != nil }, "\(row.route): 순위 응답이 안 왔다")
                let wantRank = row.route.hasSuffix("unlisted") ? 11 : 3
                #expect(chess.ranking?.me?.rank == wantRank, "\(row.route): 내 순위 \(String(describing: chess.ranking?.me?.rank))")
            }

            // 지문에 **순위 숫자를 넣지 않는다**: 순위 조회는 모든 로비 라우트에서 나가므로 도착 시점이
            // 라우트와 무관하게 흔들린다(그걸 지문에 넣으면 경합이 '화면이 갈렸다'로 둔갑한다 —
            // 순위 두 변형은 위에서 `me.rank` 로 따로 잰다).
            prints[row.route] = [
                "phase=\(chess.phase)", "match=\(chess.match?.id ?? "-")",
                "watch=\(chess.spectating?.id ?? "-")", "section=\(model.games.demoChessRoute?.section.rawValue ?? "-")",
                "in=\(chess.incoming?.id ?? "-")", "out=\(chess.outgoing?.id ?? "-")"
            ].joined(separator: " ")

            await baseBarrier(model.context.service)
            #expect(MobileForbiddenCalls.violations(in: baseRequests(host: host)).isEmpty, "\(row.route)")
            model.games.chessScreenDidDisappear()
            model.sceneDidEnterBackground()
            BaseStub.tearDown(host: host, storage: storage)
        }

        // ★ **지문이 몇 가지인가** — 스크린샷 md5 비교와 같은 질문. 꼬리를 버리면 **한 가지**가 된다(결함 D6 의 모습).
        //   같은 지문을 뜻하는 짝은 둘뿐이고 **둘 다 일부러**다:
        //   ① `games/chess` ≡ `games/chess/lobby` — 같은 로비가 맞다(꼬리 없음).
        //   ② `games/chess/ranking` ≡ `…/ranking/unlisted` — 상태가 같고 **순위 픽스처만** 갈린다(위에서 `me.rank` 로 쟀다).
        #expect(prints.count == Self.table.count)
        #expect(Set(prints.values).count == 8,
                "라우트 열이 \(Set(prints.values).count) 가지 화면만 만든다 — 꼬리가 버려지고 있다: \(prints)")
    }

    // MARK: - 3. 소스 계약 (뷰·스토어가 그 값을 **실제로 쓰는가** — 맥 스위트가 폰 뷰를 못 보므로 글자로 잰다)

    @Test("꼬리를 쓰는 자리 셋이 소스에 있다 — 코어 문 · 관전 직접 걸기 · 스크롤 닻")
    func theTailIsActuallyWiredIntoTheScreens() throws {
        let store = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesStore.swift")
        // ① 판 열기: 꼬리를 **코어가 이미 가진 문**으로 넣는다(오목 `pendingGomokuFocusID` 와 같은 선례).
        #expect(store.contains("chess.openWindow(focusMatchID: demoChessRoute?.focusMatchID)"),
                "체스 화면이 꼬리의 판 id 를 코어 문에 안 넣는다 — `match/<id>` 가 로비로 떨어진다")
        // ② 관전: 칩과 **같은 자리**를 부른다(게이트를 우회하지 않는다).
        #expect(store.contains("startWatching(matchID: id)"),
                "데모가 관전을 거는 길이 없다 — 합성 탭이 금지라 `watch/<id>` 에 닿을 길이 사라진다")
        #expect(store.contains("demoChessRoute = nil"), "로그아웃 reset 이 데모 꼬리를 안 거둔다")

        let tab = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesTab.swift")
        let screen = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesChessScreen.swift")
        // ③ 절: 화면을 밀어 올리지 않고 **닻**만 옮긴다(순위·관전은 로비 안 절이다).
        #expect(screen.contains("gamesDemoChessSectionAnchor(store.demoChessRoute?.section,"),
                "체스 로비에 데모 절 닻이 없다 — `ranking` 이 로비 머리에서 시작해 순위가 화면 밖이다")
        #expect(tab.contains("defaultScrollAnchor(section == .bottom && !isWatching ? .bottom : nil)"),
                "절 닻이 스크롤을 안 옮긴다")
        // ★ 그 닻은 **관전이 선 뒤에는 놓는다**. 안 놓으면 바닥(순위 절)을 계속 붙잡아 관전 판이 접힘 위로
        //   밀려 올라간다(실측: `watch/demo-chess-live` 에 파일 글자 한 줄만 남았다 · 402·390 둘 다).
        #expect(screen.contains("isWatching: chess.spectating != nil"),
                "절 닻이 관전을 보지 않는다 — 관전 판이 접힘 위로 밀려 화면에 안 보인다")
        // ★★ 그리고 그 값을 **`navigationDestination` 자리에서 읽지 않는다**: 거기서 읽으면 관전이 서는 순간
        //    목적지가 다시 세워져 화면이 헐리고 `chessScreenDidDisappear()` → `stopWatching()` 이 관전을
        //    내린다(되풀이 — 실측에서 관전 화면이 **영영 안 떴다**).
        #expect(!tab.contains("store.chess.spectating"),
                "게임 탭의 목적지 클로저가 관전 상태를 읽는다 — 관전이 설 때마다 체스 화면이 헐린다")
        // 갈래로 적지 않는다(갈래가 뒤집히면 그 아래 나무가 헐린다 — 위와 같은 함정의 작은 판).
        #expect(!tab.contains("if section == .bottom, !isWatching {"),
                "닻을 `if/else` 로 갈랐다 — 값이 뒤집히는 순간 로비 스크롤이 헐리고 다시 선다")
        // 순위·관전을 **자식 화면으로 밀지 않았다**(밀면 onDisappear → windowDidHide 로 폴링이 죽는다).
        #expect(!tab.contains("GamesChessRankingScreen") && !tab.contains("GamesChessWatchScreen"),
                "순위·관전을 별도 화면으로 밀었다 — 스토어가 phase == .lobby 를 요구한다")

        // ④ 관전 절을 **화면 위로 올리는 쪽**(닻을 놓는 것만으로는 로비 머리에서 시작해 판이 한참 아래다).
        //   되풀이가 계약이다 — 로비·관전 응답이 차례로 오며 위쪽 절이 자라 한 번 올린 것은 다시 밀려난다.
        #expect(tab.contains("proxy.scrollTo(id, anchor: .top)"), "데모 닻이 관전 절을 올리지 않는다")
        #expect(tab.contains("for _ in 0..<12 {"), "한 번만 올린다 — 위쪽 절이 자라면 다시 밀려난다")
        #expect(screen.contains(".id(Self.watchSectionAnchorID)"),
                "관전 절에 닻 id 가 없다 — `scrollTo` 가 올릴 자리를 못 찾아 조용히 아무 일도 안 한다")
        #expect(screen.contains("gamesDemoChessWatchAnchor(isDemo: store.context.isDemo, watchID: chess.spectating?.id,"),
                "로비가 데모 관전 닻을 안 단다")
        // 올리는 자리와 id 를 **한 곳**에서 읽는다(글자를 두 벌 적으면 한쪽만 고쳐져 조용히 멈춘다).
        #expect(screen.components(separatedBy: "Self.watchSectionAnchorID").count == 3,
                "닻 id 를 말하는 자리가 둘(절의 `.id` · 닻 호출)이 아니다")

        let model = try Self.strippedSource("Sources/CheckMobileKit/App/MobileAppModel.swift")
        #expect(model.contains("games.demoChessRoute = chess"), "앱 모델이 꼬리를 스토어에 안 넘긴다")
    }

    /// 저장소 파일 한 벌을 **주석을 걷어내고** 돌려준다. 안 걷으면 설명을 지워야만 초록이 되는 테스트가 된다
    /// (저장소 메모 '소스 계약 테스트는 주석을 걷어내야 한다').
    static func strippedSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }
}
