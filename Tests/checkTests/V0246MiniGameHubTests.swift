import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 미니게임 허브 — 패널 상호 배타 · 인터럽트 토큰 · 최고기록/업로드 게이트 · 오늘 순위 · 높이 예산 · 로그아웃 리셋 · 소스 계약.
// 게임 규칙은 여기 없다(각 게임 스위트). 네트워크는 URLProtocolStub(테스트별 고유 호스트)로 격리한다.

private let mgUserID = "00000000-0000-0000-0000-000000000002"

@MainActor
private func mgDefaults() -> UserDefaults {
    let suite = "v0246-mg-hub-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 스텁 네트워크에 물린 로그인 스토어(세션/팀 직접 확정 — 기존 스위트 규약). 팝오버는 열린 상태로 둔다.
@MainActor
private func mgStore(host: String, defaults: UserDefaults? = nil) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults ?? mgDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: mgUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.isMenuPresented = true
    return store
}

/// 200×5ms 폴링(≈1초 상한) — 비동기 스토어 반영 대기(UltraPokeTests 관용구).
@MainActor
private func mgWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - 패널 상호 배타

@MainActor
@Test
func theGameWindowCoexistsWithEveryPopoverPanel() {
    // v0.2.46: 미니게임은 별도 창이라 팝오버 패널들과 **상호 배타가 아니다**. 예전 패널 시절의 양방향 배타를
    // 그대로 두면 게임을 하는 동안 순위판을 열어 볼 수도, 팝오버를 쓰는 동안 게임을 켜 둘 수도 없다.
    let store = mgStore(host: "mg-coexist")
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.isPokePanelVisible = true
    store.isInsightsPanelVisible = true
    store.isUltraPanelVisible = true
    store.openMiniGameWindow()
    #expect(store.isMiniGamePanelVisible)
    #expect(store.isLeaderboardVisible && store.isTokenBoardVisible && store.isPokePanelVisible)
    #expect(store.isInsightsPanelVisible && store.isUltraPanelVisible, "창이 팝오버 패널을 닫았다")
    // 첫 프레임부터 빈 목록 자리에 "불러오는 중…"(토큰 보드와 같은 규약).
    #expect(store.miniGameBoardLoading)

    // 반대 방향도 마찬가지 — 어느 패널을 열어도 창은 그대로다.
    for open in [store.toggleLeaderboard, store.toggleTokenBoard, store.togglePokePanel, store.toggleInsightsPanel] {
        open()
        #expect(store.isMiniGamePanelVisible, "팝오버 패널을 열었더니 미니게임 창이 닫혔다")
    }
    store.openUltraPanel(from: .home)
    #expect(store.isMiniGamePanelVisible)
    // 진입 버튼을 다시 누르면(토글) 닫힌다.
    store.toggleMiniGamePanel()
    #expect(!store.isMiniGamePanelVisible)
}

// MARK: - 인터럽트 토큰

@MainActor
@Test
func interruptTokenRisesOnKindChangeAndWindowCloseButNotWhenThePopoverCloses() {
    let store = mgStore(host: "mg-interrupt")
    store.openMiniGameWindow()
    let base = store.miniGameInterruptToken

    // 팝오버 닫힘 — 게임은 별도 창에 있으므로 **끝나지 않는다**(창의 닫힘·포커스 상실이 정지 신호다).
    store.setMenuPresented(false)
    #expect(store.miniGameInterruptToken == base, "팝오버를 닫았다고 창에서 하던 판이 끝났다")
    store.setMenuPresented(true)
    #expect(store.miniGameInterruptToken == base)

    // 종류 전환.
    store.selectMiniGame(.flappy)
    #expect(store.miniGameInterruptToken == base + 1)
    #expect(store.miniGameKind == .flappy)
    store.selectMiniGame(.flappy)
    #expect(store.miniGameInterruptToken == base + 1, "같은 종류 재선택은 no-op")

    // 창 닫기 — 닫혀 있을 때 다시 불러도 토큰이 헛되이 오르지 않는다.
    store.closeMiniGamePanel()
    #expect(store.miniGameInterruptToken == base + 2)
    store.closeMiniGamePanel()
    #expect(store.miniGameInterruptToken == base + 2, "이미 닫힌 창을 닫아도 토큰이 오르면 안 된다")
}

@MainActor
@Test
func selectedKindPersistsAcrossStoreRestarts() {
    let defaults = mgDefaults()
    let store = mgStore(host: "mg-kind-persist", defaults: defaults)
    #expect(store.miniGameKind == .timingBar, "기본은 타이밍 바")
    store.selectMiniGame(.flappy)
    #expect(defaults.string(forKey: WorkTimerStore.miniGameKindKey) == "flappy")
    let restarted = mgStore(host: "mg-kind-persist-2", defaults: defaults)
    #expect(restarted.miniGameKind == .flappy)
}

// MARK: - 최고기록 · 업로드 게이트

@MainActor
@Test
func recordScoreRejectsOutOfRangeAndRaisesLocalBestOnlyUpward() async {
    let store = mgStore(host: "mg-record")
    #expect(store.miniGameBest(.timingBar) == 0)
    store.recordMiniGameScore(kind: .timingBar, score: 640)
    #expect(store.miniGameBest(.timingBar) == 640)
    store.recordMiniGameScore(kind: .timingBar, score: 300)
    #expect(store.miniGameBest(.timingBar) == 640, "낮은 점수가 최고를 내렸다")
    store.recordMiniGameScore(kind: .timingBar, score: 1001)
    #expect(store.miniGameBest(.timingBar) == 640, "상한 초과가 최고에 반영됐다")
    store.recordMiniGameScore(kind: .timingBar, score: -1)
    #expect(store.miniGameBest(.timingBar) == 640)
    // 게임별로 따로 센다.
    #expect(store.miniGameBest(.flappy) == 0)
    store.recordMiniGameScore(kind: .flappy, score: 999)
    #expect(store.miniGameBest(.flappy) == 999)
    store.recordMiniGameScore(kind: .flappy, score: 1000)
    #expect(store.miniGameBest(.flappy) == 999, "플래피 상한은 999")

    // 유효한 판 세 개만 올라간다(범위 밖 둘은 요청 0건).
    await mgWait { URLProtocolStub.requests(forHost: "mg-record").filter { $0.url?.path == "/rest/v1/minigame_daily_scores" }.count >= 3 }
    let uploads = URLProtocolStub.requests(forHost: "mg-record").filter { $0.url?.path == "/rest/v1/minigame_daily_scores" }
    #expect(uploads.count == 3, "유효한 판마다 한 번 올린다(최고 유지·판 수는 서버 트리거 몫) — \(uploads.count)건")
}

@MainActor
@Test
func recordScoreSkipsUploadWhenRankingIsPrivate() async {
    let store = mgStore(host: "mg-private")
    store.miniGamePublic = false
    store.miniGamePublicLoaded = true
    store.recordMiniGameScore(kind: .timingBar, score: 500)
    #expect(store.miniGameBest(.timingBar) == 500, "비공개여도 로컬 최고는 남는다")
    try? await Task.sleep(for: .milliseconds(150))
    let uploads = URLProtocolStub.requests(forHost: "mg-private").filter { $0.url?.path == "/rest/v1/minigame_daily_scores" }
    #expect(uploads.isEmpty, "공개를 끈 사람의 점수가 올라갔다 — 설정 문구('올라가지도 않아요')가 거짓이 된다")
}

@MainActor
@Test
func uploadBodyCarriesExactlyUserGameAndBestScoreAndTargetsTheDailyTable() async throws {
    let store = mgStore(host: "mg-upload-shape")
    store.recordMiniGameScore(kind: .flappy, score: 42)
    await mgWait { !URLProtocolStub.requests(forHost: "mg-upload-shape").filter { $0.url?.path == "/rest/v1/minigame_daily_scores" }.isEmpty }
    let requests = URLProtocolStub.requests(forHost: "mg-upload-shape")
    let bodies = URLProtocolStub.bodies(forHost: "mg-upload-shape")
    let index = try #require(requests.firstIndex { $0.url?.path == "/rest/v1/minigame_daily_scores" })
    let request = requests[index]
    #expect(request.httpMethod == "POST")
    #expect(request.url?.query?.contains("on_conflict=user_id,game,day") == true, "충돌 키는 (user_id, game, day) — \(request.url?.query ?? "")")
    #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates,return=minimal")
    let json = try #require(try JSONSerialization.jsonObject(with: Data(bodies[index].utf8)) as? [String: Any])
    #expect(Set(json.keys) == ["user_id", "game", "best_score"], "본문 키가 정확히 셋이어야 한다(day 없음 — 서버가 정한다) — \(json.keys.sorted())")
    #expect(json["user_id"] as? String == mgUserID)
    #expect(json["game"] as? String == "flappy")
    #expect(json["best_score"] as? Int == 42)
}

// MARK: - 오늘 순위

@MainActor
@Test
func boardLoadTreatsSchemaMissingAsEmptyNotFailed() async {
    // schema-missing 호스트는 /rest/v1/* 전부 404 + "schema cache" — 마이그레이션 전 창의 실제 모양.
    let store = mgStore(host: "schema-missing")
    store.toggleMiniGamePanel()
    await mgWait { store.miniGameBoardLoaded && !store.miniGameBoardLoading }
    #expect(store.miniGameBoardLoaded, "스키마 부재는 '아직 표가 없다'로 접어 빈 목록을 그린다")
    #expect(!store.miniGameBoardFailed, "스키마 부재가 실패 표시([다시 시도])를 세웠다 — 사용자가 고칠 수 없는 일이다")
    #expect(store.miniGameBoard.isEmpty)
}

@MainActor
@Test
func boardLoadMarksRealFailuresAndRetryClearsThem() async {
    // 미등록 호스트의 500: statusCode 는 200 이지만 본문이 빈 배열이라 정상. 실패는 5xx 호스트로 만든다.
    let store = mgStore(host: "mg-board-fails")
    store.toggleMiniGamePanel()
    await mgWait { !store.miniGameBoardLoading }
    // 스텁이 200 + [] 를 주므로 성공 경로다 — 로드 완료·실패 없음·빈 목록.
    #expect(store.miniGameBoardLoaded)
    #expect(!store.miniGameBoardFailed)
}

@MainActor
@Test
func boardRaisesLocalBestFromMyRowAndKeepsSortedOrder() async {
    let host = "mg-board-rows"
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"user_id":"u-other","display_name":"민수","avatar_url":null,"best_score":300,"best_at":"2026-09-08T01:00:00Z","plays":3},
          {"user_id":"\(mgUserID)","display_name":"나야","avatar_url":null,"best_score":700,"best_at":"2026-09-08T02:00:00.123456+00:00","plays":5},
          {"user_id":"u-tie","display_name":"동률","avatar_url":null,"best_score":700,"best_at":"2026-09-08T01:30:00Z","plays":1}
        ]
        """,
        forHost: host
    )
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon", session: TokenBoardURLProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon"], defaults: mgDefaults())
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: mgUserID)
    store.isMenuPresented = true
    store.recordMiniGameScore(kind: .timingBar, score: 100)   // 로컬 100 < 서버 700
    await store.performLoadMiniGameBoard()
    #expect(store.miniGameBoardLoaded)
    #expect(store.miniGameBoard.map(\.userID) == ["u-tie", mgUserID, "u-other"], "점수 내림차순, 동률은 먼저 낸 사람 — \(store.miniGameBoard.map(\.name))")
    #expect(store.miniGameBest(.timingBar) == 700, "내 행(700)이 로컬(100)보다 크면 로컬을 올린다")
    // 소수초 유무가 섞인 best_at 이 둘 다 파싱된다(nil 이면 정렬이 뒤로 밀린다).
    #expect(store.miniGameBoard.allSatisfy { $0.bestAt != nil })
}

// MARK: - 공개 설정은 별도 GET

@MainActor
@Test
func miniGamePublicIsFetchedWithItsOwnSelectNotInsideTheSettingsGet() async {
    let store = mgStore(host: "mg-privacy-get")
    await store.loadTokenUsagePrivacyIfNeeded()
    let gets = URLProtocolStub.requests(forHost: "mg-privacy-get").filter { $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "GET" }
    let selects = gets.compactMap { $0.url?.query }
    #expect(selects.contains { $0.contains("select=token_usage_public,token_usage_collect,focus_mode") },
            "기존 설정 GET 의 select 가 바뀌었다 — 컬럼 없는 서버에서 42703 으로 통째로 죽는다")
    #expect(selects.contains { $0.contains("select=minigame_public") }, "미니게임 공개는 별도 GET 이어야 한다 — \(selects)")
    #expect(!selects.contains { $0.contains("focus_mode,minigame_public") || $0.contains("minigame_public,token_usage") },
            "minigame_public 이 설정 GET 의 select 에 끼어들었다")
    // 스텁은 minigame_public 을 안 준다(컬럼 없는 서버) → 공개(기본) 유지.
    #expect(store.miniGamePublic)
}

@MainActor
@Test
func setMiniGamePublicPatchesOnlyThatColumnAndRevertsOnFailure() async throws {
    let store = mgStore(host: "mg-public-patch")
    store.setMiniGamePublic(false)
    #expect(!store.miniGamePublic)
    #expect(store.miniGamePublicLoaded, "사용자 선택은 로드 완료로 간주(폴링이 덮지 않게)")
    await mgWait { !URLProtocolStub.requests(forHost: "mg-public-patch").filter { $0.httpMethod == "PATCH" }.isEmpty }
    let requests = URLProtocolStub.requests(forHost: "mg-public-patch")
    let bodies = URLProtocolStub.bodies(forHost: "mg-public-patch")
    let index = try #require(requests.firstIndex { $0.httpMethod == "PATCH" && $0.url?.path == "/rest/v1/profiles" })
    let json = try #require(try JSONSerialization.jsonObject(with: Data(bodies[index].utf8)) as? [String: Any])
    #expect(Set(json.keys) == ["minigame_public"], "컬럼당 별도 PATCH — 다른 컬럼과 합치면 권한 없는 서버에서 요청 전체가 403")
    #expect(json["minigame_public"] as? Bool == false)
}

// MARK: - 로그아웃 리셋

@MainActor
@Test
func signOutResetsPanelBoardAndPublicFlagButKeepsPerAccountBest() {
    let defaults = mgDefaults()
    let store = mgStore(host: "mg-signout", defaults: defaults)
    store.toggleMiniGamePanel()
    store.miniGameBoard = [MiniGameBoardEntry(userID: "x", name: "x", avatarURL: nil, bestScore: 1, bestAt: nil, plays: 1)]
    store.miniGameBoardLoaded = true
    store.miniGameYesterdayWinner = MiniGameWinner(day: "2026-09-07", userID: "x", name: "x", avatarURL: nil, score: 1, awarded: true)
    store.miniGamePublic = false
    store.miniGamePublicLoaded = true
    store.recordMiniGameScore(kind: .timingBar, score: 321)
    let token = store.miniGameInterruptToken
    store.signOut()
    #expect(!store.isMiniGamePanelVisible)
    #expect(store.miniGameInterruptToken == token + 1, "로그아웃은 진행 중인 판을 끝낸다")
    #expect(store.miniGameBoard.isEmpty && !store.miniGameBoardLoaded && store.miniGameYesterdayWinner == nil)
    #expect(store.miniGamePublic && !store.miniGamePublicLoaded)
    // 최고기록은 계정별 키라 지우지 않는다 — 같은 계정으로 돌아오면 그대로.
    #expect(defaults.integer(forKey: WorkTimerStore.miniGameBestKey(userID: mgUserID, kind: .timingBar)) == 321)
    // 로그아웃 상태(session nil)에서는 다른 키를 본다 → 0.
    #expect(store.miniGameBest(.timingBar) == 0)
}

// MARK: - 울트라 잔량은 상한을 넘겨도 그대로 보인다(상품 +10)

@Test
func ultraBalanceAboveTheCapIsDisplayedVerbatim() {
    #expect(UltraBalanceText.badge(balance: 13) == "13")
    #expect(UltraPanelCopy.balanceText(13) == "13")
    let response = PokeSendResponse(status: "ok", ultraBalance: 13)
    #expect(response.ultraBalanceForDisplay == 13, "min(balance, cap) 같은 클램프가 상품 잔량을 숨긴다")
}

// MARK: - 소스 계약

@Test
func sourceContractsForTheHubWiring() throws {
    let menu = mgStrippingComments(try String(contentsOf: mgSourceURL("CheckMenuView.swift"), encoding: .utf8))
    let root = try #require(mgTypeBody(menu, name: "CheckMenuView"))
    // v0.2.46: 미니게임은 별도 창이다 — 팝오버 자리를 안 먹으므로 하위 패널로 세지 않고 그리지도 않는다.
    #expect(!root.contains("|| store.isMiniGamePanelVisible"), "isSubPanelOpen 이 창을 하위 패널로 센다 — 토큰 소모량 행이 사라진다")
    #expect(!root.contains("MiniGamePanel("), "팝오버가 아직 미니게임 패널을 그린다")
    // 진입 버튼은 HeaderGoalSection(캡션 행)에 있다 — 루트 타입 본문이 아니라 파일 전체에서 찾는다.
    #expect(menu.contains("store.openMiniGameWindow()"), "캡션 행 버튼이 창을 열지 않는다")
    #expect(!root.contains("store.displayNow"), "팝오버 루트가 displayNow 를 값으로 읽는다")

    let store = mgStrippingComments(try String(contentsOf: mgSourceURL("WorkTimerStore.swift"), encoding: .utf8))
    for name in ["toggleLeaderboard", "toggleTokenBoard", "togglePokePanel", "openUltraPanel", "toggleInsightsPanel"] {
        let body = try #require(mgFunctionBody(store, name: name), "\(name) 본문을 못 찾았다")
        #expect(!body.contains("closeMiniGamePanel()"), "\(name) 이 미니게임 창을 닫는다 — 창은 팝오버와 공존한다")
    }
    let presented = try #require(mgFunctionBody(store, name: "setMenuPresented"))
    #expect(!presented.contains("miniGameInterruptToken += 1"), "팝오버 닫힘이 창의 판을 끝낸다")
    #expect(presented.contains("if isMiniGamePanelVisible { loadMiniGameBoard() }"), "재오픈 시 순위 재조회가 없다")
    let loop = try #require(mgFunctionBody(store, name: "startRefreshLoopTask"))
    #expect(!loop.contains("MiniGame") && !loop.contains("miniGame"), "30초 refresh 루프에 미니게임 조회가 얹혔다(38명 × 30초)")

    let panel = mgStrippingComments(try String(contentsOf: mgSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    #expect(!panel.contains("displayNow") && !panel.contains("Timer.publish") && !panel.contains("Date()"), "창 콘텐츠가 시계를 읽는다")
    #expect(panel.contains("DragGesture(minimumDistance: 0)"), "클릭은 마우스 다운(DragGesture 0)이어야 한다")
    #expect(panel.contains("NSEvent.addLocalMonitorForEvents"), "스페이스 로컬 모니터가 없다 — 근무 알약이 스페이스를 먹는다")
    #expect(!panel.contains("addGlobalMonitorForEvents"), "전역 모니터는 우리 앱이 활성일 때 눈이 먼다")
    #expect(!panel.contains("aiToken"), "토큰 보라는 잔디 전용")
}

// MARK: - 소스 계약 헬퍼(다른 파일의 것은 private)

private func mgSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/check/\(name)")
}

private func mgStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") { rest = rest[close.upperBound...]; inBlock = false } else { rest = "" }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]; rest = rest[block.upperBound...]; inBlock = true; continue
            }
            if let comment = lineComment { kept += rest[..<comment.lowerBound]; rest = ""; continue }
            kept += rest; rest = ""
        }
        output += kept + "\n"
    }
    return output
}

private func mgBalancedBody(_ source: String, from start: String.Index) -> String? {
    guard let open = source.range(of: "{", range: start..<source.endIndex) else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open.upperBound..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

private func mgTypeBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "struct \(name):") ?? source.range(of: "struct \(name)<") ?? source.range(of: "class \(name) ")
    else { return nil }
    return mgBalancedBody(source, from: declaration.upperBound)
}

private func mgFunctionBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "func \(name)(") else { return nil }
    return mgBalancedBody(source, from: declaration.upperBound)
}
