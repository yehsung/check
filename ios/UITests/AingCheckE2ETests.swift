import XCTest

// aing-check iOS 실서버 e2e(w5/e2e) — 운영 서버의 **숨김 심사 계정 A·B** 로만 돈다.
//
// 실행(헤드리스 시뮬레이터, GUI 없이):
//   1) ios/scripts/sync-local-config.sh <.env.local>  → xcodegen generate
//   2) xcodebuild build-for-testing -scheme AingCheck -destination 'generic/platform=iOS Simulator' \
//        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=   (애드혹 서명 — 키체인 그룹·App Group 엔타이틀먼트)
//   3) TEST_RUNNER_AING_E2E_{SUPABASE_URL,ANON_KEY,A_EMAIL,A_PASSWORD,A_ID,A_NAME,A_TOKEN,B_EMAIL,B_PASSWORD,B_ID,B_NAME,B_TOKEN}=… \
//      xcodebuild test-without-building -only-testing:AingCheckUITests/AingCheckE2ETests/<단계>
//      선택: TEST_RUNNER_AING_E2E_NONCE(메시지·할 일 꼬리표 고정) · TEST_RUNNER_AING_E2E_KEEP_TODO(test04 가 남긴 "e2e 남김 <nonce>" — test10 이 B 화면에 안 보이는지 본다)
// 단계는 이름 순서대로 돈다(하나씩 부르면 단계 사이에 호스트가 서버 조회·simctl 을 끼울 수 있다). 환경변수가 없으면 전부 skip.
// B 는 앱이 아니라 REST(B 의 사용자 JWT)로 흉내 낸다. 서버 쓰기는 두 계정의 정상 앱 동작(RPC)뿐이다.
// 남는 것: test04 의 "e2e 남김" 할 일(test10 확인용 — 끝나면 A 토큰 todo_sync 톰스톤으로 지운다) · test06 의 끝난 오목 판 · 루비 ±3.
// 계정 칸(이메일)이 보이는 설정 화면 아래쪽과 로그인 화면은 스크린샷·트리 덤프를 남기지 않는다. xcresult 활동 기록에는 입력 문자열 앞부분이 남으니 결과 묶음은 공유하지 않는다.
final class AingCheckE2ETests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func loadEnv() throws -> (E2EEnv, E2EServer) {
        let env = try E2EEnv.load()
        return (env, E2EServer(env: env))
    }

    // MARK: a — 로그인 · 지금 탭(숨김 격리)

    @MainActor
    func test01_LoginA_NowTab() async throws {
        let (env, _) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        let viaForm = E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        log("signIn viaForm=\(viaForm)")
        let primer = E2EUI.handlePushPrimer(app, allow: true, test: self)
        log("primer=\(primer)")
        E2EUI.tab(app, "지금")
        let team = app.staticTexts["앱 심사 팀"]
        XCTAssertTrue(team.waitForExistence(timeout: 20), "팀 이름 '앱 심사 팀' 이 안 보인다")
        let goal = E2EUI.anyElement(app, labelContains: "목표 40시간")
        XCTAssertTrue(goal.waitForExistence(timeout: 10), "주간 목표 40시간 줄이 안 보인다")
        log("weekLine=\(goal.exists ? goal.label : "-")")
        shot("a1-now-top")
        dumpTree(app, "a-now")
        app.swipeUp()
        app.swipeUp()
        let workingHeader = E2EUI.anyElement(app, labelContains: "지금 근무 중")
        _ = workingHeader.waitForExistence(timeout: 10)
        log("workingHeader=\(workingHeader.exists ? workingHeader.label : "-")")
        log("otherTeamsLabel=\(app.staticTexts["다른 팀"].exists)")
        shot("a2-now-working")
        dumpTree(app, "a-now-working")
    }

    // MARK: b — 재실행 뒤 로그인 유지

    @MainActor
    func test02_RelaunchKeepsSession() async throws {
        _ = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        let tabBar = app.tabBars.firstMatch
        let loginButton = app.buttons["로그인"]
        _ = waitUntil(timeout: 25) { tabBar.exists || loginButton.exists }
        log("relaunch tabBar=\(tabBar.exists) loginButton=\(loginButton.exists)")
        XCTAssertTrue(tabBar.exists, "재실행 뒤 로그인 화면으로 떨어졌다(키체인 복원 실패)")
        XCTAssertFalse(loginButton.exists)
        let primer = E2EUI.handlePushPrimer(app, allow: true, test: self)
        log("primer=\(primer)")
        shot("b1-relaunch")
        dumpTree(app, "b-relaunch")
    }

    // MARK: c — 메시지(실시간 · 안 읽음 · 읽음 · 답장 · 1)

    /// B 의 with_reads 이력에서 본문이 같은 행.
    @MainActor
    private func bHistoryRow(_ server: E2EServer, body: String) async throws -> [String: Any]? {
        let rows = try await server.rpc("message_history_with_reads", as: .b, ["p_hours": 24, "p_limit": 200]) as? [[String: Any]] ?? []
        return rows.last(where: { ($0["body"] as? String) == body })
    }

    @MainActor
    private func openConversation(_ app: XCUIApplication, peerName: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", peerName)).firstMatch
        if row.waitForExistence(timeout: 8) {
            row.tap()
        } else {
            app.buttons["새 대화"].firstMatch.tap()
            let person = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", peerName)).firstMatch
            XCTAssertTrue(person.waitForExistence(timeout: 15), "새 대화 목록에 \(peerName) 이 없다")
            person.tap()
        }
        XCTAssertTrue(app.textViews["메시지 입력"].waitForExistence(timeout: 15), "대화 화면 입력칸이 안 뜬다")
    }

    @MainActor
    func test03_Messages() async throws {
        let (env, server) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        E2EUI.tab(app, "메시지")
        sleep(2)
        shot("c0-list-before")
        openConversation(app, peerName: env.bName)
        sleep(2)

        // c1: 대화가 열린 채 B → A. 실시간으로 새 줄이 떠야 한다.
        let msg1 = "실시간 확인 \(env.nonce)-1"
        let sent1At = Date()
        let r1 = try await server.rpc("send_message", as: .b, ["p_to": env.aID, "p_body": msg1])
        log("c1 send_message(B→A) response=\(r1)")
        let bubble1 = E2EUI.anyElement(app, labelContains: msg1)
        let appear1 = waitUntil(timeout: 30, poll: 0.2) { bubble1.exists }
        log("c1 realtime bubble appeared after=\(appear1.map { String(format: "%.2fs", $0 + 0) } ?? "TIMEOUT") (since send start \(String(format: "%.2fs", Date().timeIntervalSince(sent1At))))")
        XCTAssertNotNil(appear1, "열린 대화에 B 의 새 메시지가 30초 안에 안 떴다")
        shot("c1-open-conversation-realtime")
        // 대화가 보이고 앱이 active → 읽음 처리 → B 쪽 read_by_peer = true
        let read1 = try await eventually(timeout: 20) {
            (try await self.bHistoryRow(server, body: msg1)?["read_by_peer"] as? Bool) == true
        }
        log("c1 B.with_reads read_by_peer(msg1)=true after=\(read1.map { String(format: "%.2fs", $0) } ?? "TIMEOUT")")
        XCTAssertNotNil(read1, "열린 대화에서 받은 메시지가 읽음 처리되지 않았다")

        // c2: 목록으로 나가 B → A. 목록 안 읽음 점 · 탭 배지.
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        let msg2 = "안읽음 확인 \(env.nonce)-2"
        _ = try await server.rpc("send_message", as: .b, ["p_to": env.aID, "p_body": msg2])
        let unreadRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "안 읽은 메시지 있음", msg2)).firstMatch
        let appear2 = waitUntil(timeout: 30, poll: 0.25) { unreadRow.exists }
        log("c2 list unread row after=\(appear2.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") label=\(unreadRow.exists ? unreadRow.label : "-")")
        XCTAssertNotNil(appear2, "목록에 안 읽음 줄이 안 떴다")
        let tabButton = app.tabBars.buttons["메시지"]
        let badgeShown = waitUntil(timeout: 10) { (tabButton.value as? String).map { !$0.isEmpty && $0 != "0" } ?? false }
        log("c2 tab badge value=\(String(describing: tabButton.value)) shown=\(badgeShown != nil)")
        XCTAssertNotNil(badgeShown, "메시지 탭 배지가 안 떴다")
        shot("c2-list-unread-badge")
        let bRowBefore = try await bHistoryRow(server, body: msg2)
        log("c2 B.with_reads read_by_peer(msg2) before open=\(String(describing: bRowBefore?["read_by_peer"]))")
        XCTAssertEqual(bRowBefore?["read_by_peer"] as? Bool, false, "대화를 열기 전인데 이미 읽음이다")

        // c3: 대화를 열면 mark → B 쪽 read_by_peer = true
        unreadRow.tap()
        XCTAssertTrue(app.textViews["메시지 입력"].waitForExistence(timeout: 15))
        let read2 = try await eventually(timeout: 20) {
            (try await self.bHistoryRow(server, body: msg2)?["read_by_peer"] as? Bool) == true
        }
        log("c3 B.with_reads read_by_peer(msg2)=true after open=\(read2.map { String(format: "%.2fs", $0) } ?? "TIMEOUT")")
        XCTAssertNotNil(read2, "대화를 열었는데 읽음 처리가 안 됐다")
        shot("c3-conversation-opened")

        // c4: A 가 UI 로 답장 → B 이력에 보임 · A 쪽 내 말풍선 옆 1
        let reply = "e2e reply \(env.nonce)"
        let input = app.textViews["메시지 입력"]
        input.tap()
        input.typeText(reply)
        app.buttons["보내기"].tap()
        let mineUnread = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", reply, "안 읽음")).firstMatch
        let appear4 = waitUntil(timeout: 20, poll: 0.25) { mineUnread.exists }
        log("c4 my bubble with 1 after=\(appear4.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") label=\(mineUnread.exists ? mineUnread.label : "-")")
        XCTAssertNotNil(appear4, "내 답장 말풍선 옆 1(안 읽음)이 안 보인다")
        shot("c4-reply-with-one")
        var replyRow: [String: Any]?
        let seen4 = try await eventually(timeout: 15) {
            replyRow = try await self.bHistoryRow(server, body: reply)
            return replyRow != nil
        }
        log("c4 B history has reply after=\(seen4.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") is_mine(B)=\(String(describing: replyRow?["is_mine"])) unread(B)=\(String(describing: replyRow?["unread"]))")
        XCTAssertNotNil(replyRow, "B 이력에 A 의 답장이 없다")

        // c5: B 가 읽으면 A 쪽 1 이 사라진다(실시간 message_read)
        if let id = replyRow?["id"] as? String {
            let markedAt = Date()
            let mark = try await server.rpc("mark_messages_read", as: .b, ["p_peer": env.aID, "p_through": id])
            log("c5 B mark_messages_read response=\(mark)")
            let cleared = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", reply, "안 읽음")).firstMatch
            let gone = waitUntil(timeout: 30, poll: 0.25) { cleared.exists && !mineUnread.exists }
            log("c5 one cleared after=\(gone.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") (since mark \(String(format: "%.2fs", Date().timeIntervalSince(markedAt))))")
            XCTAssertNotNil(gone, "B 가 읽었는데 A 말풍선 옆 1 이 30초 안에 안 사라졌다")
            shot("c5-one-cleared")
        }
        dumpTree(app, "c-conversation")

        // 목록으로 돌아가 배지가 사라졌는지
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let badgeGone = waitUntil(timeout: 15) { (tabButton.value as? String).map { $0.isEmpty || $0 == "0" } ?? true }
        log("c6 tab badge after read value=\(String(describing: tabButton.value)) cleared=\(badgeGone != nil)")
        shot("c6-list-after")
    }

    // MARK: d — 할 일(앱 → 서버 · 서버 → 앱)

    /// A 토큰으로 todo_sync(보낼 것 없음, 전체) → 제목이 같은 서버 행.
    @MainActor
    private func serverTodo(_ server: E2EServer, title: String) async throws -> [String: Any]? {
        let response = try await server.rpc("todo_sync", as: .a, ["p_changes": [Any](), "p_since_ms": NSNull()]) as? [String: Any]
        let items = response?["items"] as? [[String: Any]] ?? []
        return items.last(where: { ($0["title"] as? String) == title })
    }

    private static func isNull(_ value: Any?) -> Bool { value == nil || value is NSNull }

    private static func kstDayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    /// 할 일 제목 요소(제목 글자는 "눌러서 수정" 버튼 특성이라 종류를 가리지 않고 label 로 찾는다).
    @MainActor
    private func todoTitle(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// 키보드 내리기: 목록을 아래로 끌어 키보드에 닿게 한다(scrollDismissesKeyboard(.interactively)).
    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
        _ = waitUntil(timeout: 3) { !app.keyboards.firstMatch.exists }
    }

    /// 당겨서 새로고침(목록 맨 위에서).
    @MainActor
    private func pullToRefresh(_ app: XCUIApplication) {
        dismissKeyboard(app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.8)
    }

    @MainActor
    private func swipeDelete(_ app: XCUIApplication, title: String) {
        dismissKeyboard(app)
        let row = todoTitle(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "지울 할 일 줄이 없다: \(title)")
        row.swipeLeft()
        let delete = app.buttons["삭제"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "밀어서 삭제 버튼이 안 뜬다")
        delete.tap()
    }

    @MainActor
    func test04_Todos() async throws {
        let (env, server) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        E2EUI.tab(app, "지금")
        let field = app.textFields["할 일 추가"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "할 일 입력칸이 없다")

        // d1: 추가 → 서버 행
        let title = "e2e 할일 \(env.nonce)"
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(todoTitle(app, title).waitForExistence(timeout: 5), "추가한 할 일이 목록에 없다")
        dismissKeyboard(app)
        var row: [String: Any]?
        let t1 = try await eventually(timeout: 20) {
            row = try await self.serverTodo(server, title: title)
            return row != nil
        }
        log("d1 add → server row after=\(t1.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") completed=\(String(describing: row?["completed_at_ms"])) deleted=\(String(describing: row?["deleted_at_ms"]))")
        XCTAssertNotNil(row, "추가한 할 일이 서버에 안 올라갔다")
        shot("d1-added")

        // d2: 체크 → completed_at_ms
        let check = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", "완료로 표시", title)).firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5), "체크 버튼을 못 찾았다")
        check.tap()
        let t2 = try await eventually(timeout: 20) {
            row = try await self.serverTodo(server, title: title)
            return !Self.isNull(row?["completed_at_ms"])
        }
        log("d2 toggle → server completed after=\(t2.map { String(format: "%.2fs", $0) } ?? "TIMEOUT")")
        XCTAssertNotNil(t2, "체크가 서버에 반영되지 않았다")
        shot("d2-checked")

        // d3: 밀어서 삭제 → 되돌리기 → 서버는 삭제 아님
        swipeDelete(app, title: title)
        let undo = app.buttons["되돌리기"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "되돌리기 토스트가 안 뜬다")
        shot("d3-undo-toast")
        undo.tap()
        XCTAssertTrue(todoTitle(app, title).waitForExistence(timeout: 5), "되돌린 할 일이 목록에 다시 없다")
        sleep(4)
        row = try await serverTodo(server, title: title)
        log("d3 undo → server deleted=\(String(describing: row?["deleted_at_ms"])) completed=\(String(describing: row?["completed_at_ms"]))")
        XCTAssertTrue(Self.isNull(row?["deleted_at_ms"]), "되돌렸는데 서버에서 삭제 상태다")

        // d4: 다시 삭제(되돌리지 않음) → deleted_at_ms
        swipeDelete(app, title: title)
        let t4 = try await eventually(timeout: 25) {
            row = try await self.serverTodo(server, title: title)
            return !Self.isNull(row?["deleted_at_ms"])
        }
        log("d4 delete → server deleted after=\(t4.map { String(format: "%.2fs", $0) } ?? "TIMEOUT")")
        XCTAssertNotNil(t4, "삭제가 서버에 반영되지 않았다")
        XCTAssertFalse(todoTitle(app, title).exists, "삭제한 할 일이 목록에 남았다")
        shot("d4-deleted")

        // d5: 서버 쪽 변경(A 토큰 todo_sync) → 앱 새로고침 뒤 반영
        let serverTitle = "e2e 서버추가 \(env.nonce)"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let item: [String: Any] = [
            "id": UUID().uuidString.lowercased(), "title": serverTitle,
            "created_at_ms": nowMs, "updated_at_ms": nowMs,
            "completed_at_ms": NSNull(), "deleted_at_ms": NSNull(),
            "origin_day_key": Self.kstDayKey(Date()),
        ]
        let push = try await server.rpc("todo_sync", as: .a, ["p_changes": [item], "p_since_ms": NSNull()]) as? [String: Any]
        log("d5 server todo_sync(add) status=\(String(describing: push?["status"])) rejected=\(String(describing: push?["rejected"]))")
        sleep(1)
        let beforeRefresh = todoTitle(app, serverTitle).exists
        pullToRefresh(app)
        let t5 = waitUntil(timeout: 20) { self.todoTitle(app, serverTitle).exists }
        log("d5 app shows server todo after pull-to-refresh=\(t5.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") (visibleBefore=\(beforeRefresh))")
        XCTAssertNotNil(t5, "서버에서 더한 할 일이 새로고침 뒤에도 안 보인다")
        shot("d5-server-change-visible")

        // d6: 서버에서 더한 것을 앱에서 삭제(정리) → 서버 삭제
        swipeDelete(app, title: serverTitle)
        let t6 = try await eventually(timeout: 25) {
            let r = try await self.serverTodo(server, title: serverTitle)
            return !Self.isNull(r?["deleted_at_ms"])
        }
        log("d6 cleanup delete → server deleted after=\(t6.map { String(format: "%.2fs", $0) } ?? "TIMEOUT")")

        // j 단계용: 하나 남긴다(B 로 로그인했을 때 A 의 할 일이 안 보여야 한다). 정리는 j 뒤 REST 로.
        let keep = "e2e 남김 \(env.nonce)"
        field.tap()
        field.typeText(keep + "\n")
        dismissKeyboard(app)
        let t7 = try await eventually(timeout: 20) { try await self.serverTodo(server, title: keep) != nil }
        log("d7 keep todo on server after=\(t7.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") title=\(keep)")
        shot("d7-keep")
    }

    // MARK: e — 주간 목표

    @MainActor
    private func serverGoal(_ server: E2EServer) async throws -> Int? {
        let rows = try await server.get("memberships?select=teams(weekly_goal_hours)", as: .a) as? [[String: Any]] ?? []
        return (rows.first?["teams"] as? [String: Any])?["weekly_goal_hours"] as? Int
    }

    @MainActor
    private func changeGoal(_ app: XCUIApplication, increment: Bool) {
        app.buttons["주간 목표 수정"].firstMatch.tap()
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "목표 시트 스테퍼가 없다")
        stepper.buttons.element(boundBy: increment ? 1 : 0).tap()
        shot(increment ? "e-sheet-41" : "e-sheet-40")
        app.buttons["목표 저장"].tap()
        _ = waitUntil(timeout: 10) { !stepper.exists }
    }

    @MainActor
    func test05_WeeklyGoal() async throws {
        let (env, server) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        E2EUI.tab(app, "지금")
        let before = try await serverGoal(server)
        log("e0 server goal before=\(String(describing: before))")
        XCTAssertTrue(E2EUI.anyElement(app, labelContains: "목표 40시간").waitForExistence(timeout: 15))

        changeGoal(app, increment: true)
        let ui41 = waitUntil(timeout: 10) { E2EUI.anyElement(app, labelContains: "목표 41시간").exists }
        let s41 = try await eventually(timeout: 10) { try await self.serverGoal(server) == 41 }
        log("e1 goal 41 ui=\(ui41 != nil) server=\(s41 != nil)")
        XCTAssertNotNil(ui41)
        XCTAssertNotNil(s41, "set_team_weekly_goal 이 서버에 41 을 반영하지 않았다")
        shot("e1-goal-41")

        changeGoal(app, increment: false)
        let ui40 = waitUntil(timeout: 10) { E2EUI.anyElement(app, labelContains: "목표 40시간").exists }
        let s40 = try await eventually(timeout: 10) { try await self.serverGoal(server) == 40 }
        log("e2 goal back to 40 ui=\(ui40 != nil) server=\(s40 != nil)")
        XCTAssertNotNil(s40, "목표를 40 으로 되돌리지 못했다")
        shot("e2-goal-40")
    }

    // MARK: f — 오목(B 신청 → A 수락 · 착수 · 기권 · 루비)

    private static let gomokuProtocol = 2

    @MainActor
    private func lobbyRuby(_ server: E2EServer, _ who: E2EWho) async throws -> Int? {
        let lobby = try await server.rpc("gomoku_lobby", as: who, ["p_protocol": Self.gomokuProtocol]) as? [String: Any]
        return (lobby?["me"] as? [String: Any])?["ruby_balance"] as? Int
    }

    /// B 시점 판 상태의 match 객체.
    @MainActor
    private func bMatch(_ server: E2EServer, matchID: String) async throws -> [String: Any]? {
        let response = try await server.rpc("gomoku_state", as: .b, [
            "p_protocol": Self.gomokuProtocol, "p_match_id": matchID, "p_since_seq": 0, "p_since_chat_seq": 0,
        ]) as? [String: Any]
        if let match = response?["match"] as? [String: Any] { return match }
        return (response?["state"] as? [String: Any])?["match"] as? [String: Any]
    }

    /// 판 요소 안 교차점(x, y — y 는 아래가 0)을 누를 좌표. 판 기하는 앱 `GomokuPhoneBoardGeometry`(여백 6%, 15줄).
    @MainActor
    private func boardPoint(_ board: XCUIElement, x: Int, y: Int) -> XCUICoordinate {
        let step = 0.88 / 14.0
        return board.coordinate(withNormalizedOffset: CGVector(dx: 0.06 + Double(x) * step, dy: 0.06 + Double(14 - y) * step))
    }

    @MainActor
    func test06_Gomoku() async throws {
        let (env, server) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        E2EUI.tab(app, "지금")

        let rubyA0 = try await lobbyRuby(server, .a)
        let rubyB0 = try await lobbyRuby(server, .b)
        log("f0 ruby before A=\(String(describing: rubyA0)) B=\(String(describing: rubyB0))")

        // f1: B → A 신청(판돈 3)
        let challenge = try await server.rpc("gomoku_challenge", as: .b, [
            "p_protocol": Self.gomokuProtocol, "p_opponent": env.aID, "p_stake": 3,
        ]) as? [String: Any]
        log("f1 B gomoku_challenge status=\(String(describing: challenge?["status"])) match_id=\(String(describing: challenge?["match_id"]))")
        guard let matchID = challenge?["match_id"] as? String else {
            XCTFail("신청이 만들어지지 않았다: \(String(describing: challenge))")
            return
        }
        let gamesTab = app.tabBars.buttons["게임"]
        let badge = waitUntil(timeout: 30) { (gamesTab.value as? String).map { !$0.isEmpty && $0 != "0" } ?? false }
        log("f1 games tab badge value=\(String(describing: gamesTab.value)) after=\(badge.map { String(format: "%.2fs", $0) } ?? "TIMEOUT")")
        XCTAssertNotNil(badge, "게임 탭 배지가 안 떴다")
        E2EUI.tab(app, "게임")
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1:1 오목")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        log("f1 gomoku card label=\(card.label)")
        shot("f1-games-badge")
        card.tap()

        // f2: 받은 신청 → 수락
        let invite = E2EUI.anyElement(app, labelContains: "\(env.bName)님의 신청")
        XCTAssertTrue(invite.waitForExistence(timeout: 15), "받은 신청 카드가 없다")
        shot("f2-incoming-invite")
        let accept = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "수락")).firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.tap()

        // f3: 대국 화면
        let board = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "오목판")).firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 20), "대국 판이 안 뜬다")
        sleep(1)
        shot("f3-match-start")
        guard var match = try await bMatch(server, matchID: matchID) else {
            XCTFail("B 시점 판 상태를 못 읽었다")
            return
        }
        let aColor = (match["black"] as? String)?.lowercased() == env.aID ? "black" : "white"
        log("f3 match status=\(String(describing: match["status"])) A color=\(aColor) turn=\(String(describing: match["turn"])) board.label=\(board.label)")

        let aCells = [(7, 7), (9, 7)]
        let bCells = [(0, 0), (0, 2)]
        var aPlaced = 0
        var bPlaced = 0
        var previewShot = false
        while aPlaced < 2 || bPlaced < 2 {
            match = try await bMatch(server, matchID: matchID) ?? match
            let moveCount = match["move_count"] as? Int ?? 0
            let turn = match["turn"] as? String ?? ""
            if turn == aColor {
                guard aPlaced < 2 else { break }
                let (x, y) = aCells[aPlaced]
                let target = boardPoint(board, x: x, y: y)
                target.tap()
                sleep(1)
                if !previewShot {
                    shot("f4-preview-stone")
                    previewShot = true
                }
                let unchanged = try await bMatch(server, matchID: matchID)?["move_count"] as? Int
                log("f4 A preview tap (\(x),\(y)) server move_count still=\(String(describing: unchanged)) (before \(moveCount))")
                XCTAssertEqual(unchanged, moveCount, "첫 탭(미리보기)에서 착수가 나갔다")
                target.tap()
                let placed = try await eventually(timeout: 15, poll: 0.5) {
                    (try await self.bMatch(server, matchID: matchID)?["move_count"] as? Int ?? 0) > moveCount
                }
                log("f4 A second tap → server move_count+1 after=\(placed.map { String(format: "%.2fs", $0) } ?? "TIMEOUT")")
                XCTAssertNotNil(placed, "같은 칸 재탭으로 착수가 안 됐다")
                aPlaced += 1
            } else {
                guard bPlaced < 2 else { break }
                let (x, y) = bCells[bPlaced]
                let movedAt = Date()
                let moved = try await server.rpc("gomoku_move", as: .b, [
                    "p_protocol": Self.gomokuProtocol, "p_match_id": matchID, "p_expected_seq": moveCount, "p_x": x, "p_y": y,
                ]) as? [String: Any]
                log("f4 B gomoku_move (\(x),\(y)) status=\(String(describing: moved?["status"])) verdict=\(String(describing: moved?["verdict"]))")
                bPlaced += 1
                // A 화면이 신호로 B 의 수를 받아 차례가 A 로 넘어오는지
                let myTurn = waitUntil(timeout: 20, poll: 0.25) { board.label.contains("내 차례예요") }
                log("f4 A board shows my turn after B move=\(myTurn.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") (since move \(String(format: "%.2fs", Date().timeIntervalSince(movedAt)))) label=\(board.label)")
            }
        }
        shot("f5-after-moves")

        // f6: A 기권 → 결과 화면
        let resign = app.buttons.matching(NSPredicate(format: "label == %@", "기권")).firstMatch
        XCTAssertTrue(resign.waitForExistence(timeout: 5), "기권 버튼이 없다")
        resign.tap()
        let confirm = app.buttons["기권하기"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "기권 확인 창이 없다")
        shot("f6-resign-confirm")
        confirm.tap()
        let lost = E2EUI.anyElement(app, labelContains: "졌어요")
        XCTAssertTrue(lost.waitForExistence(timeout: 15), "결과 화면(졌어요)이 안 뜬다")
        sleep(1)
        let rubyLabel = E2EUI.anyElement(app, labelContains: "루비 ")
        log("f6 result label=\(lost.label) ruby=\(rubyLabel.exists ? rubyLabel.label : "-")")
        shot("f6-result")

        let final = try await bMatch(server, matchID: matchID)
        let rubyA1 = try await lobbyRuby(server, .a)
        let rubyB1 = try await lobbyRuby(server, .b)
        log("f7 server status=\(String(describing: final?["status"])) result=\(String(describing: final?["result"])) end_reason=\(String(describing: final?["end_reason"])) winner_is_B=\((final?["winner"] as? String)?.lowercased() == env.bID) ruby after A=\(String(describing: rubyA1)) B=\(String(describing: rubyB1))")
        if let a0 = rubyA0, let a1 = rubyA1 { XCTAssertEqual(a1, a0 - 3, "A 루비가 판돈만큼 줄지 않았다") }
        if let b0 = rubyB0, let b1 = rubyB1 { XCTAssertEqual(b1, b0 + 3, "B 루비가 판돈만큼 늘지 않았다") }

        let lobbyButton = app.buttons["로비로"]
        if lobbyButton.waitForExistence(timeout: 5) {
            lobbyButton.tap()
            sleep(2)
            shot("f8-back-to-lobby")
        }
        // B 도 끝난 판에서 나간다(정상 앱 동작 — 둘 다 나가면 판 채팅이 지워진다).
        let leave = try await server.rpc("gomoku_leave", as: .b, ["p_protocol": Self.gomokuProtocol, "p_match_id": matchID]) as? [String: Any]
        log("f8 B gomoku_leave status=\(String(describing: leave?["status"]))")
    }

    // MARK: g — 미니게임(타이밍 바 한 판 · 점수 제출)

    @MainActor
    private func boardEntries(_ server: E2EServer, as who: E2EWho, game: String) async throws -> [[String: Any]] {
        try await server.rpc("minigame_board", as: who, ["p_game": game]) as? [[String: Any]] ?? []
    }

    @MainActor
    func test07_TimingBar() async throws {
        let (env, server) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        let before = try await boardEntries(server, as: .a, game: "timing_bar")
        log("g0 board(A view) before rows=\(before.count) mine=\(String(describing: before.first(where: { ($0["user_id"] as? String)?.lowercased() == env.aID })))")

        E2EUI.tab(app, "게임")
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "타이밍 바")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let canvas = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "타이밍 바 게임 화면")).firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "타이밍 바 캔버스가 없다")
        sleep(2) // 라운드 토큰을 미리 받을 틈
        shot("g1-ready")
        let startedAt = Date()
        canvas.tap() // 시작
        for round in 1...10 {
            Thread.sleep(forTimeInterval: 0.95)
            canvas.tap() // 멈춤
            if round == 3 { shot("g2-playing") }
        }
        let finished = waitUntil(timeout: 10) { (canvas.value as? String)?.hasPrefix("총점") ?? false }
        log("g3 finished=\(finished != nil) value=\(String(describing: canvas.value)) elapsed=\(String(format: "%.1fs", Date().timeIntervalSince(startedAt)))")
        XCTAssertNotNil(finished, "10라운드를 끝내지 못했다")
        let total = Int((canvas.value as? String)?.replacingOccurrences(of: "총점 ", with: "") ?? "")
        sleep(4)
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "점수를 못 올렸어요")).firstMatch
        log("g3 submit notice shown=\(notice.exists)")
        XCTAssertFalse(notice.exists, "점수 제출 실패 문구가 떴다")
        shot("g3-finished")

        var mine: [String: Any]?
        let seen = try await eventually(timeout: 15) {
            mine = try await self.boardEntries(server, as: .a, game: "timing_bar").first(where: { ($0["user_id"] as? String)?.lowercased() == env.aID })
            return mine != nil
        }
        log("g4 minigame_board(A view) has A after=\(seen.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") entry=\(String(describing: mine)) localTotal=\(String(describing: total))")
        XCTAssertNotNil(mine, "minigame_board 에 A 기록이 없다")
        let bView = try await boardEntries(server, as: .b, game: "timing_bar")
        log("g4 minigame_board(B view) rows=\(bView.count) userIDs=\(bView.compactMap { ($0["user_id"] as? String)?.prefix(8) })")
        app.swipeUp()
        sleep(1)
        shot("g5-board")
    }

    // MARK: h — 나 탭(별명 · 공개 설정 · 상점 · 제보)

    @MainActor
    func test08_MeTab() async throws {
        let (env, _) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        E2EUI.tab(app, "나")
        let name = E2EUI.anyElement(app, labelContains: env.aName)
        XCTAssertTrue(name.waitForExistence(timeout: 15), "나 탭 머리에 별명이 없다")
        sleep(2)
        log("h1 header label=\(name.label)")
        shot("h1-me")
        dumpTree(app, "h-me")

        // 설정: 공개 설정 두 토글 읽기(쓰지 않는다)
        let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "설정")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let tokenToggle = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "AI 토큰 사용량 공개")).firstMatch
        let miniToggle = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "미니게임 순위 공개")).firstMatch
        XCTAssertTrue(tokenToggle.waitForExistence(timeout: 10), "토큰 공개 토글이 없다")
        sleep(2)
        log("h2 toggles token=\(String(describing: tokenToggle.value)) minigame=\(String(describing: miniToggle.exists ? miniToggle.value : "-")) switches=\(app.switches.allElementsBoundByIndex.map { "\($0.label)=\(String(describing: $0.value))" })")
        // 설정 화면 아래 계정 칸에는 이메일이 보인다 — 그 부분은 찍지도(스크린샷) 덤프하지도 않는다.
        shot("h2-settings")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        // 상점
        let shop = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "상점")).firstMatch
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        shop.tap()
        sleep(3)
        log("h3 shop texts=\(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))")
        shot("h3-shop")
        dumpTree(app, "h-shop")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        // 제보
        let feedback = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "제보")).firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        feedback.tap()
        sleep(3)
        log("h4 feedback texts=\(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))")
        shot("h4-feedback")
        dumpTree(app, "h-feedback")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        // 프로필(별명 칸 읽기)
        let profile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "프로필")).firstMatch
        if profile.waitForExistence(timeout: 5) {
            profile.tap()
            sleep(2)
            log("h5 profile fields=\(app.textFields.allElementsBoundByIndex.map { String(describing: $0.value) }) texts=\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))")
            shot("h5-profile")
        }
    }

    // MARK: i — 푸시 포그라운드 표시 정책(지금 보는 대화면 배너 숨김 · 아니면 배너)

    @MainActor
    private func bannerSeen(_ text: String, within timeout: TimeInterval) -> TimeInterval? {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        return waitUntil(timeout: timeout, poll: 0.3) { banner.exists }
    }

    @MainActor
    func test09_PushForegroundPolicy() async throws {
        let (env, server) = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        E2EUI.tab(app, "메시지")
        sleep(2)

        // i1: 그 대화를 보고 있을 때 → 배너 없음(새 줄은 뜬다)
        openConversation(app, peerName: env.bName)
        sleep(2)
        let inConversation = "푸시 대화중 \(env.nonce)"
        _ = try await server.rpc("send_message", as: .b, ["p_to": env.aID, "p_body": inConversation])
        let bubble = E2EUI.anyElement(app, labelContains: inConversation)
        let bubbleAt = waitUntil(timeout: 20) { bubble.exists }
        let banner1 = bannerSeen(inConversation, within: 8)
        log("i1 viewing conversation: bubble=\(bubbleAt.map { String(format: "%.2fs", $0) } ?? "TIMEOUT") banner=\(banner1.map { String(format: "SHOWN after %.2fs", $0) } ?? "not shown in 8s")")
        shot("i1-in-conversation")
        XCTAssertNil(banner1, "지금 보고 있는 대화의 메시지인데 배너가 떴다")

        // i2: 목록(다른 화면)일 때 → 배너
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        sleep(2)
        let inList = "푸시 목록중 \(env.nonce)"
        _ = try await server.rpc("send_message", as: .b, ["p_to": env.aID, "p_body": inList])
        let banner2 = bannerSeen(inList, within: 12)
        log("i2 on list: banner=\(banner2.map { String(format: "SHOWN after %.2fs", $0) } ?? "not shown in 12s")")
        shot("i2-on-list-banner")
        XCTAssertNotNil(banner2, "대화 밖에서는 배너가 떠야 한다")
        // 읽음 처리해 두기(다음 단계 배지 기준을 깨끗하게)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", env.bName)).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
            sleep(2)
            app.navigationBars.firstMatch.buttons.firstMatch.tap()
        }
    }

    // MARK: j — 로그아웃 → 기기 행 삭제 · 다른 계정(B) 로그인 뒤 A 데이터가 안 남음

    @MainActor
    private func signOutFromSettings(_ app: XCUIApplication) {
        E2EUI.tab(app, "나")
        let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "설정")).firstMatch
        if !settings.waitForExistence(timeout: 10) {
            E2EUI.tab(app, "나")
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "나 탭의 설정 줄이 없다")
        settings.tap()
        // 계정 칸(이메일이 보인다)까지 내려가므로 이 구간은 스크린샷을 찍지 않는다.
        let signOut = app.buttons.matching(NSPredicate(format: "label == %@", "로그아웃")).firstMatch
        for _ in 0..<6 where !(signOut.exists && signOut.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "로그아웃 버튼이 없다")
        signOut.tap()
        let confirm = app.sheets.buttons["로그아웃"].firstMatch.exists
            ? app.sheets.buttons["로그아웃"].firstMatch
            : app.buttons.matching(NSPredicate(format: "label == %@", "로그아웃")).element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "로그아웃 확인 창이 없다")
        confirm.tap()
        XCTAssertTrue(app.buttons["로그인"].waitForExistence(timeout: 20), "로그아웃 뒤 로그인 화면이 안 뜬다")
    }

    @MainActor
    func test10_LogoutA_LoginB() async throws {
        let (env, _) = try loadEnv()
        let keepTodo = ProcessInfo.processInfo.environment["AING_E2E_KEEP_TODO"] ?? ""
        let app = XCUIApplication()
        app.launch()
        E2EUI.signInIfNeeded(app, email: env.aEmail, password: env.aPassword, test: self)
        _ = E2EUI.handlePushPrimer(app, allow: true, test: self)
        signOutFromSettings(app)
        log("j1 signed out (login screen shown)")
        sleep(3)

        E2EUI.signInIfNeeded(app, email: env.bEmail, password: env.bPassword, test: self)
        let primer = E2EUI.handlePushPrimer(app, allow: true, test: self)
        log("j2 signed in as B primer=\(primer)")
        E2EUI.tab(app, "지금")
        XCTAssertTrue(app.staticTexts["앱 심사 팀"].waitForExistence(timeout: 20))
        let emptyTodos = app.staticTexts["오늘 할 일이 비어 있어요"]
        let empty = waitUntil(timeout: 10) { emptyTodos.exists }
        sleep(3)
        let leaked = keepTodo.isEmpty ? false : todoTitle(app, keepTodo).exists
        log("j3 B now tab: todos empty=\(empty != nil) A keep-todo visible=\(leaked) (keep='\(keepTodo)')")
        XCTAssertFalse(leaked, "B 로 로그인했는데 A 의 할 일이 보인다")
        shot("j3-b-now")

        E2EUI.tab(app, "나")
        let bHeader = E2EUI.anyElement(app, labelContains: env.bName)
        XCTAssertTrue(bHeader.waitForExistence(timeout: 15), "나 탭 머리가 B 가 아니다")
        sleep(2)
        let aHeader = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", env.aName + ",")).firstMatch
        log("j4 B me header=\(bHeader.label) A header visible=\(aHeader.exists)")
        XCTAssertFalse(aHeader.exists, "나 탭에 A 머리가 남았다")
        shot("j4-b-me")

        E2EUI.tab(app, "메시지")
        sleep(3)
        let threadWithA = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", env.aName)).firstMatch
        let threadWithB = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", env.bName)).firstMatch
        _ = threadWithA.waitForExistence(timeout: 10)
        log("j5 B messages: thread with A=\(threadWithA.exists) thread named B(=A 의 목록 잔재)=\(threadWithB.exists)")
        XCTAssertFalse(threadWithB.exists, "B 의 메시지 목록에 A 시점의 대화(상대=B)가 남았다")
        shot("j5-b-messages")
    }

    @MainActor
    func test11_LogoutB() async throws {
        _ = try loadEnv()
        let app = XCUIApplication()
        app.launch()
        let tabBar = app.tabBars.firstMatch
        let loginButton = app.buttons["로그인"]
        _ = waitUntil(timeout: 25) { tabBar.exists || loginButton.exists }
        if tabBar.exists {
            _ = E2EUI.handlePushPrimer(app, allow: false, test: self)
            signOutFromSettings(app)
        }
        log("k signed out: loginButton=\(app.buttons["로그인"].exists)")
    }

    // MARK: 진단 — 실행 중인 앱의 로그인 화면 상태(자격 증명은 값 대신 일치 여부만 적는다)

    @MainActor
    func test12_ProbeLoginScreen() async throws {
        let env = try E2EEnv.load()
        let app = XCUIApplication()
        app.activate()
        sleep(2)
        let secrets = [env.aEmail, env.bEmail, env.aPassword, env.bPassword]
        let emailValue = app.textFields.firstMatch.exists ? (app.textFields.firstMatch.value as? String ?? "") : "<no field>"
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { label in !secrets.contains(where: { label.contains($0) }) }
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map(\.label).filter { label in !secrets.contains(where: { label.contains($0) }) }
        log("probe buttons=\(buttons)")
        log("probe tabBar=\(app.tabBars.firstMatch.exists) loginButton=\(app.buttons["로그인"].exists) signingIn=\(app.buttons["로그인 중"].exists) emailField==A=\(emailValue == env.aEmail) ==B=\(emailValue == env.bEmail) len=\(emailValue.count) texts=\(texts)")
    }
}
