@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰에서 근무 시작 · 종료 · 생존 신호(0.3.51 / iOS 1.0.7 — 서버 20261014130000_phone_work.sql).
///
/// 재는 것: 요청 모양(본문에 클라 시각 없음 · 보던 세션 id) · 활성화 생존 신호와 스로틀 · 함수 없는 서버의 접힘(버튼 숨김) ·
/// 출처(폰 · 맥) 표시 · 자리비움 마감 안내 1회 · 세대 가드 · 위젯 즉시 새로고침 · 금지 호출 0(맥 쓰기는 하나도 안 풀렸다).
@MainActor
@Suite(.serialized) struct NowPhoneWorkTests {
    static let touchPhone = #"""
    {"status":"ok","session":{"id":"S1","started_at":"2026-09-17T01:20:00.123456+00:00","ended_at":null,"origin":"phone"},
     "server_now":"2026-09-17T05:05:00+00:00","check_at":"2026-09-17T07:35:00+00:00","grace_seconds":600,
     "wallet":{"status":"ok","ruby_balance":42}}
    """#
    static let touchMac = #"""
    {"status":"ok","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","ended_at":null,"origin":"mac"},
     "server_now":"2026-09-17T05:05:00+00:00"}
    """#
    static let notWorking = #"{"status":"not_working","last":null,"server_now":"2026-09-17T05:05:00+00:00"}"#

    private func touches(_ h: NowHarness) -> [MobileStubRequest] { h.requests("rpc.work_phone_touch") }

    private func activateAndTouch(_ h: NowHarness) async {
        await h.activate()
        await h.store.phoneTouchTask?.value
        await h.settle()
    }

    // MARK: - 생존 신호

    @Test("활성화마다 생존 신호(1분 스로틀) · 본문 {} · 출처 폰이면 '폰에서 근무 중' · 지갑 루비 미러 · 금지 호출 0")
    func touchOnActivation() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.touchPhone))
        await h.launch()
        await activateAndTouch(h)

        #expect(touches(h).count == 1)
        #expect(touches(h).first?.method == "POST")
        #expect(touches(h).first?.bodyText == "{}", "생존 신호에 클라 시각·세션이 실렸다")
        #expect(h.store.phoneSession == NowPhoneSession(id: "s1", origin: .phone,
                                                        checkAt: ISO8601DateFormatter().date(from: "2026-09-17T07:35:00Z")))
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(card.origin == .phone && card.stateText == NowText.workingOnPhone)
        #expect(h.store.showsWorkControl && h.store.isMyWorkOpen)
        #expect(h.model.gomokuHost.rubyBalance == 42, "지갑 정산 결과가 루비 미러에 안 실렸다")

        // 30초 뒤 다시 active — 스로틀(1분) 안이라 안 보낸다.
        h.store.appDidEnterBackground()
        h.clock.advance(30)
        await activateAndTouch(h)
        #expect(touches(h).count == 1, "1분 안에 생존 신호를 또 보냈다")
        // 61초 더 — 보낸다.
        h.store.appDidEnterBackground()
        h.clock.advance(61)
        await activateAndTouch(h)
        #expect(touches(h).count == 2)

        // 맥 근무 쓰기 경로는 하나도 안 나갔다(세션 POST/PATCH · 상태 upsert · work_tick · ultra_wallet_sync).
        #expect(h.violations.isEmpty, "\(h.violations)")
        #expect(!h.requests.contains { $0.path.contains("ultra_wallet_sync") || $0.path.contains("work_tick") })
        #expect(h.requests.filter { ["work_sessions", "work_statuses", "work_status_devices"].contains(NowStubServer.key(for: $0).components(separatedBy: ".").first ?? "") }
            .allSatisfy { $0.method == "GET" })
    }

    @Test("맥이 연 근무: '맥에서 근무 중' · 버튼 아래 맥 안내 · 종료 확인 문구가 '맥에서 연 근무도'")
    func macOrigin() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.touchMac))
        await h.launch()
        await activateAndTouch(h)
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(card.origin == .mac && card.stateText == NowText.workingOnMac)
        #expect(h.store.myWorkOrigin == .mac)
        #expect(NowText.workStopConfirmMessage(origin: .mac).contains("맥에서 연 근무도"))
        #expect(!NowText.workStopConfirmMessage(origin: .phone).contains("맥"))
    }

    @Test("출처를 모르면(신호 응답 전 · 다른 세션) '근무 중' — 지어내지 않는다")
    func unknownOrigin() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        // 신호가 알려 준 세션(s9)이 팀 상태의 열린 행(s1)과 다르다 — 그 사이 바뀌었다.
        h.server.override("rpc.work_phone_touch", .json(Self.touchPhone.replacingOccurrences(of: "\"S1\"", with: "\"s9\"")))
        await h.launch()
        await activateAndTouch(h)
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(card.origin == .unknown && card.stateText == NowText.working)
        #expect(h.requests("work_statuses").count >= 2, "카드가 모르는 근무인데 다시 읽지 않았다")
    }

    @Test("함수가 없는 서버(404 PGRST202): 버튼을 숨기고 옛 문장 · 출처는 맥 · 시작을 눌러도 요청 0")
    func missingFunctionHidesControl() async throws {
        let h = NowHarness()   // 스텁은 모르는 RPC 에 missingFunction 을 돌려준다.
        defer { h.tearDown() }
        await h.launch()
        await activateAndTouch(h)
        #expect(!h.store.phoneWorkAvailable)
        #expect(!h.store.showsWorkControl)
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(card.stateText == NowText.workingOnMac, "옛 서버의 근무는 전부 맥이 연 것이다")
        await h.store.clockIn()
        #expect(h.requests("rpc.work_phone_start").isEmpty)
        // 다음 활성화도 다시 묻지 않는다(이 세대 동안).
        h.store.appDidEnterBackground()
        h.clock.advance(120)
        await activateAndTouch(h)
        #expect(touches(h).count == 1)
        // 로그아웃·계정 전환(reset)은 다시 물을 수 있게 되돌린다.
        h.store.reset()
        #expect(h.store.phoneWorkAvailable && h.store.phoneSession == nil && h.store.workNotice == nil)
    }

    // MARK: - 시작 · 종료

    @Test("시작: 본문 {} · 성공 안내 · 팀 상태 재조회 · 위젯 즉시 새로고침 · 두 번 눌러도 한 번")
    func clockIn() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("work_statuses", .json(NowHarness.idleStatuses))
        h.server.override("rpc.work_phone_touch", .json(Self.notWorking))
        await h.launch()
        await activateAndTouch(h)
        #expect(!h.store.isMyWorkOpen && h.store.showsWorkControl)

        h.server.override("rpc.work_phone_start", .json(#"""
        {"status":"ok","session":{"id":"s9","started_at":"2026-09-17T05:05:00+00:00","ended_at":null,"origin":"phone"},
         "server_now":"2026-09-17T05:05:00+00:00","check_after_seconds":9000,"grace_seconds":600,"wallet":{"ruby_balance":7}}
        """#, delay: 0.05))
        let statusesBefore = h.requests("work_statuses").count
        let reloadsBefore = h.widgetReloadCount
        async let first: Void = h.store.clockIn()
        async let second: Void = h.store.clockIn()
        _ = await (first, second)

        let starts = h.requests("rpc.work_phone_start")
        #expect(starts.count == 1, "두 번 눌렀는데 \(starts.count)번 보냈다")
        #expect(starts.first?.bodyText == "{}", "시작 본문에 클라 시각이 실렸다")
        #expect(h.store.workNotice == NowText.workStarted)
        #expect(h.store.phoneSession?.id == "s9" && h.store.phoneSession?.origin == .phone)
        #expect(h.store.phoneSession?.checkAfterSeconds == 9000)
        #expect(!h.store.isWorkBusy)
        #expect(h.requests("work_statuses").count > statusesBefore, "시작 뒤 팀 상태를 다시 읽지 않았다")
        #expect(h.widgetReloadCount > reloadsBefore, "시작 뒤 위젯을 새로고침하지 않았다")
        #expect(h.model.gomokuHost.rubyBalance == 7)
        #expect(NowText.phoneWorkCaption(checkAfterSeconds: 9000).contains("2시간 30분"))
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    @Test("시작: 이미 맥에서 근무 중이면 새로 열지 않고 그렇게 말한다 · 무소속은 이유를 말하고 요청 0")
    func clockInEdges() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.notWorking))
        h.server.override("rpc.work_phone_start", .json(#"""
        {"status":"already_working","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","ended_at":null,"origin":"mac"},
         "server_now":"2026-09-17T05:05:00+00:00"}
        """#))
        await h.launch()
        await activateAndTouch(h)
        await h.store.clockIn()
        #expect(h.store.workNotice == NowText.alreadyWorkingOnMac)
        #expect(h.store.phoneSession?.origin == .mac)

        let lone = NowHarness()
        defer { lone.tearDown() }
        lone.server.override("memberships", .json("[]"))
        lone.server.override("rpc.work_phone_touch", .json(Self.notWorking))
        await lone.launch()
        await activateAndTouch(lone)
        #expect(lone.store.hasNoTeam && lone.store.showsDisabledWorkControlForNoTeam && !lone.store.showsWorkControl)
        await lone.store.clockIn()
        #expect(lone.store.workNotice == NowText.workNeedsTeam)
        #expect(lone.requests("rpc.work_phone_start").isEmpty, "무소속인데 시작 요청을 보냈다")
    }

    @Test("종료: 보던 세션 id 를 싣는다(맥이 연 근무도) · 시각 없음 · 끝냈어요 · mismatch · 이미 끝남 · 실패 안내")
    func clockOut() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.touchMac))
        h.server.override("rpc.work_phone_stop", .json(#"""
        {"status":"ok","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","ended_at":"2026-09-17T05:05:00+00:00","origin":"mac"},
         "server_now":"2026-09-17T05:05:00+00:00","wallet":null}
        """#))
        await h.launch()
        await activateAndTouch(h)
        let reloadsBefore = h.widgetReloadCount
        await h.store.clockOut()
        let stops = h.requests("rpc.work_phone_stop")
        #expect(stops.count == 1)
        let body = try #require(try JSONSerialization.jsonObject(with: Data((stops.first?.bodyText ?? "").utf8)) as? [String: Any])
        #expect(body.keys.sorted() == ["p_session_id"], "종료 본문에 시각이 실렸다: \(body)")
        #expect(body["p_session_id"] as? String == "s1", "보던 세션(팀 상태의 열린 행)을 싣지 않았다")
        #expect(h.store.workNotice == NowText.workStopped)
        #expect(h.store.phoneSession == nil)
        #expect(h.widgetReloadCount > reloadsBefore)

        h.server.override("rpc.work_phone_stop", .json(#"{"status":"mismatch","session":{"id":"s5"}}"#))
        await h.store.clockOut()
        #expect(h.store.workNotice == NowText.workChanged)
        h.server.override("rpc.work_phone_stop", .json(#"{"status":"not_working"}"#))
        await h.store.clockOut()
        #expect(h.store.workNotice == NowText.alreadyStopped)
        h.server.override("rpc.work_phone_stop", .json(#"{"status":"surprise"}"#))
        await h.store.clockOut()
        #expect(h.store.workNotice == NowText.stopFailed, "모르는 status 를 성공으로 접었다")
        h.server.override("rpc.work_phone_stop", .networkFailure())
        await h.store.clockOut()
        #expect(h.store.workNotice == MobileSessionText.network)
        #expect(h.requests("rpc.work_phone_stop").count == 5, "실패를 큐에 넣어 재시도했다(클라 시각 재생은 위조 경로)")
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    @Test("세대 가드: 앞 계정의 늦은 시작 응답은 새 계정 화면을 바꾸지 않는다")
    func generationGuard() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.notWorking))
        await h.launch()
        await activateAndTouch(h)
        h.server.override("rpc.work_phone_start", .json(#"{"status":"ok","session":{"id":"old","started_at":"2026-09-17T05:05:00+00:00","origin":"phone"}}"#))
        let hold = BaseHold.rpc("work_phone_start", host: h.host)
        let press = Task { await h.store.clockIn() }
        #expect(await hold.waitHeld())
        await h.model.session.signOut()
        h.store.reset()
        await h.signIn(as: "u-other")
        #expect(await hold.releaseAndWaitDelivered())
        await press.value
        #expect(h.store.phoneSession == nil, "앞 계정 응답이 새 계정의 근무 출처를 세웠다")
        #expect(h.store.workNotice == nil, "앞 계정 응답이 새 계정 화면에 안내를 띄웠다")
        #expect(!h.store.isWorkBusy)
    }

    // MARK: - 자리비움 마감 안내

    @Test("서버가 자리비움으로 끝낸 폰 근무는 다음에 앱을 열 때 한 번만 알린다(KST 시각)")
    func idleCloseNoticeOnce() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("work_statuses", .json(NowHarness.idleStatuses))
        h.server.override("rpc.work_phone_touch", .json(#"""
        {"status":"not_working","last":{"id":"S7","started_at":"2026-09-16T23:00:00+00:00","ended_at":"2026-09-17T02:00:00.5+00:00","reason":"idle"},
         "server_now":"2026-09-17T05:05:00+00:00"}
        """#))
        await h.launch()
        await activateAndTouch(h)
        #expect(h.store.workNotice == NowText.idleClosed(at: "11:00"))
        #expect(h.store.workNotice == "앱을 오래 열지 않아 11:00에 근무를 끝냈어요")
        h.store.clearWorkNotice()
        h.store.appDidEnterBackground()
        h.clock.advance(61)
        await activateAndTouch(h)
        #expect(touches(h).count == 2)
        #expect(h.store.workNotice == nil, "같은 마감을 또 알렸다")

        // 사용자가 직접 끝낸 것(manual)은 알리지 않는다.
        h.server.override("rpc.work_phone_touch", .json(#"{"status":"not_working","last":{"id":"s8","ended_at":"2026-09-17T03:00:00+00:00","reason":"manual"}}"#))
        h.store.appDidEnterBackground()
        h.clock.advance(61)
        await activateAndTouch(h)
        #expect(h.store.workNotice == nil)
    }

    // MARK: - 근무 확인 알림

    @Test("근무 확인 알림: 페이로드 → 지금 탭 · session_id 없어도 산다 · 받으면 스로틀 없이 생존 신호")
    func workCheckPush() async throws {
        let payload = try #require(PushPayload(json: PushDemo.payloadJSON(.workCheck)))
        #expect(payload.kind == .workCheck && payload.route == .now)
        #expect(payload.content == .workCheck(sessionID: PushDemo.workSessionID))
        #expect(PushPayload(userInfo: ["type": "work_check"])?.content == .workCheck(sessionID: nil))
        #expect(PushKind.workCheck.categoryIdentifier == "WORK_CHECK")
        // 끌 수 없다: 나 탭 토글 목록에 없고, 저장 본문(PushPrefs)에도 키가 없다(서버 허용 목록과 같다).
        #expect(!PushKind.configurable.contains(.workCheck))
        #expect(PushKind.workCheck.isEnabled(in: PushPrefs(message: false, gomokuInvite: false, feedbackReply: false)))
        let encoded = try JSONEncoder().encode(PushPrefs())
        #expect(!String(decoding: encoded, as: UTF8.self).contains("work"))

        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.touchPhone))
        await h.launch()
        await activateAndTouch(h)
        #expect(touches(h).count == 1)
        h.store.didReceiveWorkCheckPush()
        await h.store.phoneTouchTask?.value
        await h.settle()
        #expect(touches(h).count == 2, "근무 확인 알림을 받았는데 스로틀에 막혀 신호를 안 보냈다")
    }

    @Test("근무 확인 알림이 앱이 앞에 있을 때 오면 배너를 숨기고(이미 연 사람에게 열라고 하지 않는다) 지금 탭이 신호를 보낸다")
    func workCheckForegroundPresentation() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("work_phone_touch", .json(Self.touchPhone))
        await h.launchSignedIn()
        h.clearRequests()
        let payload = PushPayload(userInfo: ["type": "work_check", "session_id": "s1"])
        #expect(h.push.presentation(for: payload) == .hidden)
        #expect(await baseWaitUntil { !h.calls("work_phone_touch").isEmpty }, "알림을 받고도 생존 신호를 안 보냈다")
        h.model.sceneDidEnterBackground()
        #expect(h.push.presentation(for: payload) == .banner, "뒤에 있으면 그대로 보인다")
        #expect(h.forbiddenViolations.isEmpty)
    }

    // MARK: - 응답 해석(순수)

    @Test("응답 해석: 모르는 status · 세션 없는 ok 는 실패 · 칸 하나의 모양이 틀려도 나머지는 산다")
    func outcomeDecoding() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func outcome(_ json: String) throws -> PhoneWorkOutcome {
            PhoneWorkOutcome.from(try decoder.decode(PhoneWorkResponse.self, from: Data(json.utf8)))
        }
        let s = PhoneWorkSessionInfo(id: "s1", startedAt: "2026-09-17T01:20:00+00:00", endedAt: nil, origin: "phone", reason: nil)
        #expect(try outcome(#"{"status":"ok","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","origin":"phone"}}"#)
                == .working(s, alreadyWorking: false))
        #expect(try outcome(#"{"status":"already_working","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","origin":"phone"}}"#)
                == .working(s, alreadyWorking: true))
        if case .stopped(let info) = try outcome(#"{"status":"ok","session":{"id":"s1","ended_at":"2026-09-17T05:00:00+00:00"}}"#) {
            #expect(info?.endedAt == "2026-09-17T05:00:00+00:00")
        } else {
            Issue.record("종료 응답을 근무 중으로 읽었다")
        }
        #expect(try outcome(#"{"status":"not_working","last":null}"#) == .notWorking(last: nil))
        #expect(try outcome(#"{"status":"mismatch"}"#) == .mismatch)
        #expect(try outcome(#"{"status":"no_team"}"#) == .noTeam)
        #expect(try outcome(#"{"status":"unauthorized"}"#) == .unauthorized)
        #expect(try outcome(#"{"status":"ok"}"#) == .failed, "세션 없는 ok 를 근무 중으로 지어냈다")
        #expect(try outcome(#"{"status":"brand_new"}"#) == .failed)
        #expect(try outcome(#"{}"#) == .failed)
        // 칸 하나가 틀린 모양(숫자 자리에 글자)이어도 status 와 세션은 산다.
        let odd = try decoder.decode(PhoneWorkResponse.self, from: Data(#"{"status":"ok","check_after_seconds":"soon","wallet":[1],"session":{"id":"s1"}}"#.utf8))
        #expect(odd.checkAfterSeconds == nil && odd.wallet == nil && odd.session?.id == "s1")
        // 서버 timestamptz(소수초 6자리 · +00:00)를 읽는다.
        #expect(NowStore.parseServerDate("2026-09-17T01:20:00.123456+00:00") != nil)
        #expect(NowStore.parseServerDate("2026-09-17T01:20:00+00:00") == ISO8601DateFormatter().date(from: "2026-09-17T01:20:00Z"))
    }

    // MARK: - 소스 계약

    @Test("폰 근무 RPC 는 폰 전용 서비스 파일 한 곳 · 맥 전용 조각과 코어 공유 파일에는 없다 · 시각 칸을 싣는 본문이 없다")
    func sourceContract() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func code(_ relative: String) throws -> String {
            stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
        }
        let phone = try code("Sources/CheckMobileKit/Session/MobilePhoneWorkService.swift")
        for rpc in ["work_phone_start", "work_phone_stop", "work_phone_touch"] {
            #expect(phone.contains("\"/rest/v1/rpc/\(rpc)\""), "\(rpc) 경로가 폰 서비스에 없다")
        }
        for core in ["Sources/CheckCore/SupabaseWorkService.swift", "Sources/CheckCore/SupabaseWorkServiceMacOnly.swift"] {
            #expect(!(try code(core)).contains("work_phone_"), "\(core) 에 폰 근무 RPC 가 있다 — 맥 바이너리에 실린다")
        }
        let hits = try IntegrationContractTests.files(containing: ["work_phone_"], under: "Sources")
        #expect(hits == ["Sources/CheckMobileKit/Session/MobilePhoneWorkService.swift"], "폰 근무 RPC 이름이 다른 곳에도 있다: \(hits)")
        // 요청 본문 모델에 시각 칸이 없다(서버 now() 만 — 위조 경로를 폰에 열지 않는다).
        for banned in ["startedAt:", "endedAt:", "durationSeconds:", "pStartedAt", "pEndedAt", "lastInputAt"] {
            let requests = phone.components(separatedBy: "struct PhoneWorkStopRequest").last?.components(separatedBy: "extension SupabaseWorkService").first ?? ""
            #expect(!requests.contains(banned), "요청 본문 모델에 \(banned) 가 있다")
        }
        // 금지 목록은 그대로다(맥 쓰기를 풀지 않았다).
        #expect(MobileForbiddenCalls.forbiddenRPCs.isSuperset(of: ["work_tick", "ultra_wallet_sync", "close_abandoned_work_sessions", "take_pokes"]))
        #expect(MobileForbiddenCalls.readOnlyTables.isSuperset(of: ["work_sessions", "work_statuses", "work_status_devices"]))
    }
}

