@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 차단·신고(앱스토어 심사 지침 1.2 — SPEC-block-report 작업 P)의 순수 규칙.
@Suite struct MessagesBlockRulesTests {
    @Test("신고 사유는 넷 · rawValue 가 서버 CHECK 값이다 · 글자는 시트에 뜨는 그대로")
    func reasons() {
        #expect(ContentReportReason.allCases.map(\.rawValue) == ["spam", "harassment", "inappropriate", "other"])
        #expect(ContentReportReason.allCases.map(\.label) == ["스팸", "욕설·괴롭힘", "부적절한 내용", "기타"])
        // id 는 rawValue 다(ForEach 가 같은 값을 두 줄로 그리지 않게).
        #expect(Set(ContentReportReason.allCases.map(\.id)).count == 4)
    }

    @Test("자유 입력은 200 코드포인트 · 정규화는 메시지 본문과 같은 눈금 · 비면 전선에 null")
    func detailLimit() {
        #expect(ContentReportDetail.maxLength == 200)
        let full = String(repeating: "가", count: 200)
        #expect(ContentReportDetail.isWithinLimit(full))
        #expect(!ContentReportDetail.isWithinLimit(full + "가"))
        // NFD 로 들어온 한글도 정규화 뒤 세므로 서버(char_length)와 같은 답이 나온다.
        let decomposed = full.decomposedStringWithCanonicalMapping
        #expect(decomposed.unicodeScalars.count > 200)
        #expect(ContentReportDetail.length(decomposed) == 200)
        #expect(ContentReportDetail.isWithinLimit(decomposed))
        // 눈에 보이는 글자가 없으면 '적지 않은 것'이다.
        #expect(ContentReportDetail.payload("   \n ") == nil)
        #expect(ContentReportDetail.payload("  괴롭혀요 ") == "괴롭혀요")
    }

    @Test("[신고 보내기]는 사유를 고르고 · 상한 안이고 · 도는 중이 아닐 때만")
    func submitGate() {
        #expect(!MessagesBlockRules.canSubmitReport(reason: nil, detail: "", isSending: false), "사유 없이 보낼 수 있다")
        #expect(MessagesBlockRules.canSubmitReport(reason: .spam, detail: "", isSending: false))
        #expect(!MessagesBlockRules.canSubmitReport(reason: .spam, detail: "", isSending: true))
        let tooLong = String(repeating: "가", count: 201)
        #expect(!MessagesBlockRules.canSubmitReport(reason: .spam, detail: tooLong, isSending: false))
        // 카운터는 상한 가까이에서만 선다.
        #expect(MessagesBlockRules.detailCounterText("짧다") == nil)
        #expect(MessagesBlockRules.detailCounterText(String(repeating: "가", count: 180)) == "180/200")
        #expect(MessagesBlockRules.isDetailOverflowing(tooLong))
    }

    @Test("실패 갈래: 함수 없음은 '아직' · 5xx·네트워크는 연결 확인 · 4xx 거절은 다시 시도 · 취소는 말하지 않는다")
    func failureNotices() {
        #expect(MessagesBlockRules.classify(SupabaseWorkServiceError.databaseSchemaMissing) == .serverNotReady)
        #expect(MessagesBlockRules.classify(SupabaseWorkServiceError.invalidResponse(404)) == .serverNotReady)
        #expect(MessagesBlockRules.classify(SupabaseWorkServiceError.invalidResponse(500)) == .network)
        #expect(MessagesBlockRules.classify(SupabaseWorkServiceError.invalidResponse(400)) == .rejected)
        #expect(MessagesBlockRules.classify(SupabaseWorkServiceError.authMessage("self")) == .rejected)
        #expect(MessagesBlockRules.classify(URLError(.notConnectedToInternet)) == .network)
        #expect(MessagesBlockRules.classify(CancellationError()) == .cancelled)

        #expect(MessagesBlockRules.notice(for: .cancelled, action: .block) == nil)
        #expect(MessagesBlockRules.notice(for: .serverNotReady, action: .block) == MessagesBlockText.serverNotReady)
        #expect(MessagesBlockText.serverNotReady.contains("아직") && MessagesBlockText.serverNotReady.contains("제보"))
        for action in [MessagesBlockAction.block, .unblock, .report] {
            let network = MessagesBlockRules.notice(for: .network, action: action)
            let rejected = MessagesBlockRules.notice(for: .rejected, action: action)
            #expect(network?.contains("못했어요") == true, "실패 문구가 무엇이 안 됐는지 말하지 않는다: \(network ?? "nil")")
            #expect(network?.contains(MobileLoadText.checkConnection) == true)
            #expect(rejected?.contains("다시 시도") == true)
        }
    }

    @Test("차단 확인 시트는 막히는 것 세 줄 + 안 막히는 것 한 줄 + 되돌릴 수 있다는 한 줄")
    func confirmCopy() {
        #expect(MessagesBlockText.blockConfirmItems.count == 3)
        #expect(MessagesBlockText.blockConfirmItems.joined().contains("메시지"))
        #expect(MessagesBlockText.blockConfirmItems.joined().contains("오목"))
        #expect(MessagesBlockText.blockConfirmScopeNote.contains("순위판"), "차단해도 남는 것(팀 통계)을 말하지 않는다")
        #expect(MessagesBlockText.blockConfirmUndoNote.contains("차단한 사람"), "푸는 자리를 말하지 않는다")
        #expect(MessagesBlockText.blockConfirmTitle("소라").contains("소라"))
        // 애플이 요구하는 '시의적절한 대응'의 약속 — 신고 시트와 지원 페이지가 같은 24시간을 말한다.
        #expect(MessagesBlockText.reviewPromise.contains("24시간"))
        #expect(MessagesBlockText.reportSentNotice.contains("24시간"))
    }

    @Test("요약도 차단한 상대를 뺀다 — 합까지 줄인다(이력만 걸렀을 때 배지에만 옛 숫자가 남던 결함)")
    func summaryExcludesBlocked() {
        let summary = MessagesRulesTests.summary(
            #"{"status":"ok","total":5,"peers":[{"peer_user_id":"a","count":2,"last_epoch_ms":1},{"peer_user_id":"b","count":3,"last_epoch_ms":1}]}"#
        )
        #expect(summary.total == 5)
        let filtered = summary.excluding(["a"])
        #expect(filtered.peers.map(\.peerUserID) == ["b"])
        #expect(filtered.total == 3, "합을 줄이지 않으면 배지가 차단한 사람 몫을 계속 센다")
        // 걸러 낼 것이 없으면 같은 값 그대로(사본을 만들지 않는다).
        #expect(summary.excluding([]) == summary)
        #expect(summary.excluding(["zzz"]) == summary)
    }

    @Test("차단한 시각 줄은 상대 시각 + '차단'(시각을 모르면 화면이 줄을 그리지 않는다)")
    func blockedAtLine() {
        let now = MobileClock.demoInstant
        #expect(MessagesBlockText.blockedAtLine(now.addingTimeInterval(-30), now: now) == "방금 차단")
        #expect(MessagesBlockText.blockedAtLine(now.addingTimeInterval(-7200), now: now).hasSuffix(" 차단"))
    }

    @Test("가입 화면 한 줄에 이용약관·처리방침 링크 둘 — 처리방침 주소는 설정 화면과 같다")
    func signUpTermsLine() {
        #expect(MobileSignUpText.termsAgreement.contains("이용약관"))
        #expect(MobileSignUpText.termsAgreement.contains("개인정보 처리방침"))
        #expect(MobileSignUpText.termsURL.absoluteString == "https://yehsung.github.io/check/terms")
        #expect(MobileSignUpText.privacyURL == MeText.privacyPolicyURL, "가입 화면과 설정의 처리방침 주소가 갈렸다")
        let attributed = MobileSignUpText.termsAgreementAttributed
        let links = attributed.runs.compactMap(\.link)
        #expect(Set(links) == [MobileSignUpText.termsURL, MobileSignUpText.privacyURL], "한 줄 안의 링크가 둘이 아니다: \(links)")
    }
}

/// 차단·신고 시나리오(앱 모델 전체를 스텁 서버 위에 세워 **경로로** 잰다).
@MainActor
@Suite(.serialized) struct MessagesBlockStoreTests {
    typealias Row = MessagesStubServer.Row
    static let peerA = "peer-a"
    static let peerB = "peer-b"

    /// 두 사람의 대화가 있는 하네스(목록이 선 상태).
    static func make(configure: @escaping (MessagesStubServer) -> Void = { _ in }) async -> MessagesHarness {
        let harness = await MessagesHarness.make { server in
            server.setRows([
                .received("a1", from: peerA, name: "소라", at: 0),
                .received("a2", from: peerA, name: "소라", at: 10),
                .received("b1", from: peerB, name: "도윤", at: 20),
            ])
            server.setSummary(MessagesStubServer.summary([(peerA, 2), (peerB, 1)]))
            server.setDirectory(#"[{"user_id":"peer-a","display_name":"소라","avatar_url":null,"is_working":true,"center":"seoul"},"#
                + #"{"user_id":"peer-b","display_name":"도윤","avatar_url":null,"is_working":false,"center":"busan"}]"#)
            configure(server)
        }
        harness.store.listDidAppear()
        await harness.settle()
        return harness
    }

    @Test("차단: 확인 시트를 지나면 대화·배지·사람 찾기에서 곧바로 사라지고(서버를 기다리지 않는다) block_user 가 그 사람 id 로 한 번 나간다")
    func blockHidesOptimistically() async {
        let h = await Self.make { server in
            server.override("block_user") { _ in .json("null") }
        }
        defer { h.tearDown() }
        h.store.loadDirectory(force: true)
        await h.settle()
        #expect(Set(h.store.threads.map(\.peerUserID)) == [Self.peerA, Self.peerB])
        #expect(h.store.badgeCount == 3)
        // 대조: 차단 전에는 묶음·사람 찾기·근무 중 줄 모두에 있다(아래 단언이 늘 참인 채로 초록이 되지 않게).
        #expect(h.store.filteredDirectory(query: "").map(\.userID).contains(Self.peerA))
        #expect(h.store.presenceBoard(now: h.model.context.clock.now()).working.map(\.id).contains(Self.peerA))

        h.store.blockPeer(Self.peerA)
        // 응답 전에 이미 사라졌다 — 묶음 · 배지 · 점 · 사람 찾기 넷 다.
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerB])
        #expect(h.store.badgeCount == 1)
        #expect(!h.store.unreadPeerIDs.contains(Self.peerA))
        #expect(h.store.filteredDirectory(query: "").map(\.userID) == [Self.peerB])
        #expect(h.store.isHiddenByBlock(Self.peerA))
        // "지금 근무 중 · 바로 말 걸기" 줄도 곧 말 거는 입구다 — 여기 남으면 얼굴을 눌러 대화가 다시 열린다.
        let board = h.store.presenceBoard(now: h.model.context.clock.now())
        #expect(!board.working.map(\.id).contains(Self.peerA))
        #expect(board.peers[Self.peerA] == nil)

        _ = await baseWaitUntil { h.store.blockingPeerID == nil }
        await h.settle()
        #expect(h.count("block_user") == 1)
        #expect(h.bodies("block_user") == [#"{"p_user":"peer-a"}"#], "차단 요청 본문이 계약과 다르다")
        #expect(h.store.blockNotice == nil, "성공했는데 문구가 섰다")
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerB])
        h.expectNoForbiddenCalls()
    }

    @Test("차단 실패: 숨긴 대화가 그대로 돌아오고 목록 위에 이유 한 줄 — 당겨서 새로고침하면 지워진다")
    func blockFailureRestores() async {
        let h = await Self.make { server in
            server.override("block_user") { _ in .json(#"{"message":"boom"}"#, status: 500) }
        }
        defer { h.tearDown() }
        h.store.blockPeer(Self.peerA)
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerB])

        _ = await baseWaitUntil { h.store.blockingPeerID == nil }
        #expect(!h.store.isHiddenByBlock(Self.peerA), "실패했는데 대화가 사라진 채다")
        #expect(h.store.threads.count == 2)
        #expect(h.store.badgeCount == 3)
        #expect(h.store.blockNotice?.contains(MobileLoadText.checkConnection) == true)
        #expect(h.store.blockNoticeIsError)

        await h.store.refreshNow()
        #expect(h.store.blockNotice == nil)
        h.expectNoForbiddenCalls()
    }

    @Test("서버가 아직 없는 창: 차단은 '아직 준비되지 않았어요' 로 되돌아오고, 차단 목록도 고장이 아니라 '아직' 이라고 말한다")
    func serverNotReady() async {
        // 기본 스텁은 모르는 RPC 에 PGRST202 를 낸다 — 앱이 db push 보다 먼저 나간 바로 그 상황이다.
        let h = await Self.make()
        defer { h.tearDown() }
        h.store.blockPeer(Self.peerA)
        _ = await baseWaitUntil { h.store.blockingPeerID == nil }
        #expect(!h.store.isHiddenByBlock(Self.peerA))
        #expect(h.store.blockNotice == MessagesBlockText.serverNotReady)

        h.store.blockedListDidAppear()
        _ = await baseWaitUntil { h.store.blocksLoaded }
        #expect(h.store.blocksServerNotReady)
        #expect(!h.store.blocksFailed, "'아직' 을 '고장' 으로 말한다")
        #expect(h.store.blockedPeople.isEmpty)
        h.expectNoForbiddenCalls()
    }

    @Test("신고: 사유가 없으면 서버를 부르지 않고 · 200자를 넘으면 부르지 않고 · 보내면 다섯 인자를 그대로 싣는다(차단까지 켜면 화면도 걷어낸다)")
    func reportGuardsAndPayload() async {
        let h = await Self.make { server in
            server.override("report_content") { _ in .json("null") }
        }
        defer { h.tearDown() }
        // ① 사유 미선택 — 왕복 0.
        var sent = await h.store.submitReport(peerID: Self.peerA, reason: nil, detail: "", messageID: nil, alsoBlock: true)
        #expect(!sent)
        #expect(h.store.reportNotice == MessagesBlockText.reportReasonRequired)
        #expect(h.count("report_content") == 0)

        // ② 200자 초과 — 왕복 0.
        sent = await h.store.submitReport(
            peerID: Self.peerA, reason: .harassment, detail: String(repeating: "가", count: 201), messageID: nil, alsoBlock: true
        )
        #expect(!sent)
        #expect(h.store.reportNotice?.contains("200자") == true)
        #expect(h.count("report_content") == 0)

        // ③ 메시지 한 건 신고 + 같이 차단.
        sent = await h.store.submitReport(
            peerID: Self.peerA, reason: .harassment, detail: "  욕을 했어요 ", messageID: "a2", alsoBlock: true
        )
        #expect(sent)
        #expect(h.count("report_content") == 1)
        let body = h.bodies("report_content").first ?? ""
        for piece in [#""p_target":"peer-a""#, #""p_reason":"harassment""#, #""p_detail":"욕을 했어요""#, #""p_message_id":"a2""#, #""p_block":true"#] {
            #expect(body.contains(piece), "신고 본문에 \(piece) 가 없다: \(body)")
        }
        #expect(h.store.isHiddenByBlock(Self.peerA), "차단까지 켜고 보냈는데 화면에 남아 있다")
        #expect(h.store.blockNotice == MessagesBlockText.reportSentNotice)
        #expect(!h.store.blockNoticeIsError)
        h.expectNoForbiddenCalls()
    }

    @Test("가장 흔한 신고(사유만 고름): 다섯 키를 그대로 싣는다 — 값이 없으면 키를 빼는 게 아니라 null 이다")
    func reportSendsNullKeysNotMissingOnes() async {
        let h = await Self.make { server in
            server.override("report_content") { _ in .json("null") }
        }
        defer { h.tearDown() }
        // 자유 입력 없음 · 메시지 아님 · 차단도 끔 — 세 자리가 모두 '값 없음' 인 경로다.
        let sent = await h.store.submitReport(peerID: Self.peerA, reason: .spam, detail: "   ", messageID: nil, alsoBlock: false)
        #expect(sent)
        #expect(h.count("report_content") == 1)
        let body = h.bodies("report_content").first ?? ""
        // PostgREST 는 **본문의 키 집합으로 함수를 고른다** — 키가 빠지면 PGRST202 가 나고 화면에는
        // "아직 서버에 준비되지 않았어요" 가 뜬다(모든 사람 신고가 통째로 죽는다).
        for piece in [#""p_target":"peer-a""#, #""p_reason":"spam""#, #""p_detail":null"#, #""p_message_id":null"#, #""p_block":false"#] {
            #expect(body.contains(piece), "신고 본문에 \(piece) 가 없다: \(body)")
        }
        #expect(!h.store.isHiddenByBlock(Self.peerA), "차단을 끄고 신고했는데 대화가 사라졌다")
        h.expectNoForbiddenCalls()
    }

    @Test("배지: 읽음을 모르는 서버(요약만 아는 창)에서도 차단한 사람 몫이 빠진다 — 목록과 탭 배지가 갈리지 않는다")
    func badgeDropsBlockedWhenOnlySummaryIsKnown() async {
        let h = await Self.make { server in
            // 읽음 RPC 가 없는 서버 → 이력에는 읽음 칸이 없고(`historySnapshot` = nil) 배지의 재료는 **요약뿐**이다.
            server.setWithReadsMissing(true)
            server.override("block_user") { _ in .json("null") }
        }
        defer { h.tearDown() }
        #expect(!h.store.readReceiptsAvailable, "대조가 무너졌다 — 읽음을 아는 서버라 배지가 요약이 아니라 이력을 센다")
        #expect(h.store.badgeCount == 3, "대조: 요약이 배지를 세지 않는다")

        h.store.blockPeer(Self.peerA)
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerB])
        #expect(h.store.badgeCount == 1, "목록에서는 사라졌는데 탭 배지에만 옛 숫자가 남는다(요약을 안 거른 결함)")
        #expect(h.store.unreadCountsByPeer[Self.peerA] == nil)
        #expect(!h.store.unreadPeerIDs.contains(Self.peerA))

        _ = await baseWaitUntil { h.store.blockingPeerID == nil }
        h.expectNoForbiddenCalls()
    }

    @Test("오목 로비: 차단한 사람은 상대 고르기 목록에서 곧바로 사라진다(확인 시트가 '오목 신청에서 서로 보이지 않아요' 라고 약속한다)")
    func gomokuLobbyHidesBlocked() async {
        let h = await Self.make { server in
            server.override("block_user") { _ in .json("null") }
        }
        defer { h.tearDown() }
        h.model.gomoku.users = [
            GomokuUser(id: Self.peerA, displayName: "소라", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: false),
            GomokuUser(id: Self.peerB, displayName: "도윤", avatarURL: nil, characterID: nil, isWorking: false, isCapable: true, inMatch: false),
        ]
        #expect(h.model.games.gomokuLobbyUsers.map(\.id) == [Self.peerA, Self.peerB], "대조: 거르기 전에는 둘 다 선다")

        h.store.blockPeer(Self.peerA)
        #expect(h.model.games.gomokuLobbyUsers.map(\.id) == [Self.peerB], "차단했는데 오목 로비에 [도전] 버튼과 함께 그대로 서 있다")
        // 거르는 곳은 화면이 읽는 자리 하나다 — 코어 목록은 서버가 답한 그대로 둔다(차단이 실패하면 그대로 돌아온다).
        #expect(h.model.gomoku.users.count == 2)

        _ = await baseWaitUntil { h.store.blockingPeerID == nil }
        h.expectNoForbiddenCalls()
    }

    @Test("신고 실패: 시트는 쓴 글을 쥔 채 이유 한 줄 · 차단은 일어나지 않는다")
    func reportFailureKeepsSheet() async {
        let h = await Self.make { server in
            server.override("report_content") { _ in .networkFailure() }
        }
        defer { h.tearDown() }
        let sent = await h.store.submitReport(peerID: Self.peerA, reason: .spam, detail: "광고예요", messageID: nil, alsoBlock: true)
        #expect(!sent, "실패했는데 시트를 닫으라고 했다")
        #expect(h.store.reportNotice?.contains(MobileLoadText.checkConnection) == true)
        #expect(!h.store.isHiddenByBlock(Self.peerA))
        #expect(!h.store.isSendingReport)
        h.expectNoForbiddenCalls()
    }

    @Test("차단 목록: list_blocks 를 그려 주고, 해제하면 그 줄이 사라지고 숨김도 풀려 대화가 돌아온다")
    func blockedListAndUnblock() async {
        let h = await Self.make { server in
            server.override("block_user") { _ in .json("null") }
            server.override("unblock_user") { _ in .json("null") }
            server.override("list_blocks") { _ in
                .json(#"[{"user_id":"peer-a","display_name":"소라","avatar_url":null,"created_epoch":1789621000}]"#)
            }
        }
        defer { h.tearDown() }
        h.store.blockPeer(Self.peerA)
        _ = await baseWaitUntil { h.store.blockingPeerID == nil }

        h.store.blockedListDidAppear()
        _ = await baseWaitUntil { h.store.blocksLoaded }
        #expect(h.store.blockedPeople.map(\.userID) == [Self.peerA])
        #expect(h.store.blockedPeople.first?.name == "소라")
        #expect(h.store.blockedPeople.first?.blockedAt != nil)
        #expect(!h.store.blocksServerNotReady)

        h.store.unblock(Self.peerA)
        _ = await baseWaitUntil { h.store.unblockingUserIDs.isEmpty }
        await h.settle()
        #expect(h.count("unblock_user") == 1)
        #expect(h.bodies("unblock_user") == [#"{"p_user":"peer-a"}"#])
        #expect(h.store.blockedPeople.isEmpty)
        #expect(!h.store.isHiddenByBlock(Self.peerA), "차단을 풀었는데 대화가 계속 숨어 있다")
        #expect(h.store.threads.count == 2, "차단을 풀었는데 대화가 돌아오지 않았다")
        h.expectNoForbiddenCalls()
    }

    @Test("로그아웃: 숨김·차단 목록·문구가 다음 계정으로 새지 않는다")
    func resetClearsBlockState() async {
        let h = await Self.make { server in
            server.override("block_user") { _ in .json("null") }
            server.override("list_blocks") { _ in .json(#"[{"user_id":"peer-a","display_name":"소라"}]"#) }
        }
        defer { h.tearDown() }
        h.store.blockPeer(Self.peerA)
        _ = await baseWaitUntil { h.store.blockingPeerID == nil }
        h.store.blockedListDidAppear()
        _ = await baseWaitUntil { h.store.blocksLoaded }
        #expect(!h.store.blockedPeople.isEmpty)

        await h.switchAccount()
        #expect(h.store.hiddenBlockedPeerIDs.isEmpty)
        #expect(h.store.blockedPeople.isEmpty)
        #expect(!h.store.blocksLoaded)
        #expect(h.store.blockNotice == nil)
        h.expectNoForbiddenCalls()
    }
}

/// 소스 계약(주석은 걷어내고 본다) + 심사에 걸리는 문서 계약.
@MainActor
@Suite(.serialized) struct MessagesBlockContractTests {
    @Test("소스 계약: 대화 화면에 ··· 메뉴가 있고 · 차단을 부르는 곳은 확인 시트 하나 · 신고는 시트가 보낸다 · 내 말풍선엔 신고가 없다")
    func conversationSourceContract() throws {
        let conversation = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift")
        #expect(conversation.contains("Menu {"), "대화 화면 오른쪽 위 ··· 메뉴가 없다")
        #expect(conversation.contains("MessagesBlockText.blockAction") && conversation.contains("MessagesBlockText.reportAction"))
        #expect(conversation.contains("MessagesBlockConfirmSheet("), "차단이 확인 시트를 지나지 않는다")
        #expect(conversation.contains("MessagesReportSheet("))
        #expect(conversation.contains("line.entry.isMine ? nil :"), "내 말풍선에도 신고 메뉴가 붙는다")

        // 차단을 부르는 파일은 **확인 시트를 지나는 두 UGC 면**뿐이다(스토어 정의 파일 제외):
        // 1:1 대화 화면과 오목 채팅 서랍. 확인 없는 차단은 여전히 없다(둘 다 `MessagesBlockConfirmSheet` 가 유일한 입구다).
        let callers = try IntegrationContractTests.files(containing: ["blockPeer("], under: "Sources/CheckMobileKit")
        #expect(callers == [
            "Sources/CheckMobileKit/Games/GamesGomokuChat.swift",
            "Sources/CheckMobileKit/Messages/MessagesBlockStore.swift",
            "Sources/CheckMobileKit/Messages/MessagesConversationView.swift",
        ], "차단을 부르는 파일이 늘었다: \(callers)")
        #expect(conversation.components(separatedBy: "store.blockPeer(").count - 1 == 1, "차단을 부르는 자리가 한 곳이 아니다")

        // 신고를 **보내는** 곳은 시트 하나다(입구가 늘어도 보내는 문은 하나여야 한다).
        let reporters = try IntegrationContractTests.files(containing: ["submitReport("], under: "Sources/CheckMobileKit")
        #expect(reporters == [
            "Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift",
            "Sources/CheckMobileKit/Messages/MessagesBlockStore.swift",
        ], "신고를 보내는 파일이 늘었다: \(reporters)")

        let sheets = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift")
        #expect(sheets.contains("kind: .destructive") && sheets.contains("role: .destructive"), "차단 확인이 파괴적 버튼이 아니다")
        #expect(!sheets.contains(".alert("), "확인이 시스템 알림창이다(재질 대비 — AingConfirmSheet 주석)")
        #expect(sheets.contains("MessagesBlockText.reviewPromise"), "신고 시트에 24시간 약속이 없다")
        #expect(sheets.contains("@State private var alsoBlock = true"), "'신고하면서 차단' 이 기본 켬이 아니다")
        #expect(sheets.contains("presentationBackground(MobileTheme.surface)"), "시트가 불투명하지 않다(색 토큰 밖 재질)")

        // 재디자인 B 토큰만 쓴다 — 시스템 색·시스템 목록 모양을 섞지 않는다.
        let blocked = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeBlockedPeopleView.swift")
        for code in [sheets, blocked] {
            #expect(!code.contains("Color.red") && !code.contains(".foregroundStyle(.red)"), "시스템 빨강은 토큰 밖이다")
            #expect(code.contains("InsetGroup {"), "재디자인 B 그룹 대신 다른 목록을 쓴다")
        }
        #expect(blocked.contains("AingConfirmSheet("), "차단 해제가 확인 없이 일어난다")
        #expect(blocked.contains("PersonAvatar("), "사람 줄이 공용 부품이 아니다")
    }

    @Test("소스 계약: 설정에 [차단한 사람]이 있고 · 가입 화면에 약관 한 줄이 있고 · 코어 RPC 는 로그인 토큰 필수다")
    func settingsAndSignUpContract() throws {
        let settings = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeSettingsView.swift")
        #expect(settings.contains("MessagesBlockText.blockedListTitle"), "설정에 차단한 사람 행이 없다")
        #expect(settings.contains("MeDestination.blocked"), "차단 목록으로 가는 길이 없다")

        let signUp = try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSignUpView.swift")
        #expect(signUp.contains("MobileSignUpText.termsAgreementAttributed"), "가입 화면에 약관 동의 한 줄이 없다")
        #expect(signUp.contains("store.stage == .account"), "약관 줄이 계정 만드는 단계 밖에도 선다")

        let core = try IntegrationContractTests.code("Sources/CheckCore/SupabaseWorkServiceBlocks.swift")
        for signature in [
            "package func blockUser(accessToken: String, userID: String) async throws",
            "package func unblockUser(accessToken: String, userID: String) async throws",
            "package func fetchBlocks(accessToken: String) async throws -> [BlockedUser]",
        ] {
            #expect(core.contains(signature), "코어 서명이 바뀌었다(토큰이 옵셔널이면 anon 호출 문이 열린다): \(signature)")
        }
        for path in ["/rest/v1/rpc/block_user", "/rest/v1/rpc/unblock_user", "/rest/v1/rpc/list_blocks", "/rest/v1/rpc/report_content"] {
            #expect(core.contains("\"\(path)\""))
        }
        let macOnly = try IntegrationContractTests.code("Sources/CheckCore/SupabaseWorkServiceMacOnly.swift")
        #expect(!macOnly.contains("block_user"), "차단이 맥 전용 조각에 있다(폰이 못 부른다)")
        // 신고 본문은 사람이 쓴 문장이다 — 로그로 새지 않는다.
        for code in [core, try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesBlockStore.swift")] {
            #expect(!code.contains("print(") && !code.contains("Logger("), "신고·차단 경로에 로그가 붙었다")
        }
    }

    @Test("소스 계약: 오목 채팅에도 신고·차단 입구가 있다 — 애플 1.2 가 세는 UGC 면은 둘이다(1:1 메시지 · 오목 채팅)")
    func gomokuChatSourceContract() throws {
        let chat = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuChat.swift")
        #expect(chat.contains("MessagesBlockText.reportAction"), "오목 채팅에서 신고에 닿을 수 없다(화면을 나가 사람 찾기로 돌아가야 한다)")
        #expect(chat.contains("MessagesBlockText.blockAction"), "오목 채팅에서 차단에 닿을 수 없다")
        #expect(chat.contains("MessagesBlockConfirmSheet("), "오목 채팅의 차단이 확인 시트를 지나지 않는다")
        #expect(chat.contains("MessagesReportSheet("), "오목 채팅이 메시지 탭과 다른 신고 시트를 쓴다(문구·사유가 두 벌이 된다)")
        // 사람이 아닌 상대(AI 연습 판)에게는 입구가 서지 않는다 — 신고할 사람이 없다.
        #expect(chat.contains("GomokuAIGame.isAIMatchID("), "AI 연습 판에도 신고·차단이 선다")

        // 대국 화면·결과 화면 둘 다 서랍에 상대를 넘긴다(결과 화면에서도 신고할 수 있어야 한다 — 욕은 대개 진 뒤에 온다).
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift")
        #expect(match.components(separatedBy: "GamesGomokuChatDrawer(").count - 1 == 2, "서랍을 세우는 자리가 둘이 아니다")
        #expect(!match.contains("GamesGomokuChatDrawer(store: gomoku, isExpanded:"), "서랍이 상대를 모른 채 선다(신고할 대상이 없다)")
    }

    @Test("앱 이름은 한 벌이다 — 홈 화면 · 앱 안 문구 · 약관 · 지원 페이지가 같은 이름을 말한다")
    func appDisplayNameIsOne() throws {
        let name = CheckMobileIdentifiers.appDisplayName
        #expect(name == "아잉체크", "사용자가 정한 앱 이름이 바뀌었다: \(name)")
        let root = IntegrationContractTests.root

        // 홈 화면·설정 앱이 읽는 이름(두 타깃 모두). XcodeGen 명세와 생성된 plist 가 갈리면 빌드가 옛 이름을 싣는다.
        let project = try String(contentsOf: root.appendingPathComponent("ios/project.yml"), encoding: .utf8)
        let displayNames = project.split(separator: "\n").filter { $0.contains("CFBundleDisplayName:") }
        #expect(displayNames.count == 2, "표시 이름을 적는 타깃이 둘이 아니다: \(displayNames)")
        #expect(displayNames.allSatisfy { $0.contains(name) }, "홈 화면 이름이 \(name) 가 아니다: \(displayNames)")
        for plist in ["ios/App/Info.plist", "ios/Widgets/Info.plist"] {
            let text = try String(contentsOf: root.appendingPathComponent(plist), encoding: .utf8)
                .replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\t", with: "")
            #expect(text.contains("<key>CFBundleDisplayName</key><string>\(name)</string>"), "\(plist) 의 표시 이름이 project.yml 과 갈렸다")
        }

        // 앱 안에서 이름을 말하는 자리는 같은 상수를 읽는다 — 특히 알림 안내는 **설정 앱에 실제로 뜨는 이름**을 가리켜야 한다.
        #expect(MeText.versionLine(version: "0.1.0", build: 1).hasPrefix(name))
        #expect(PushAuthorizationStatus.denied.meDetail?.contains("설정 앱 › \(name)") == true,
                "알림 안내가 홈 화면 이름과 다른 경로를 가리킨다: \(PushAuthorizationStatus.denied.meDetail ?? "nil")")

        // 심사원이 함께 읽는 세 자리(홈 화면 · 약관 · 지원 페이지)가 같은 서비스명을 쓴다.
        for relative in ["docs/terms.md", "docs/index.md", "docs/_config.yml"] {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            #expect(text.contains(name), "\(relative) 가 앱 이름을 말하지 않는다")
        }
    }

    @Test("제출 위험 등록부가 앱 사실을 따라온다 — 신고·차단이 붙었는데 '앱에 없다' 로 남아 있으면 심사 노트가 거짓이 된다")
    func appStoreRegisterKnowsBlockAndReport() throws {
        // 대조: 앱에 실제로 신고·차단 입구가 있다(이 계약의 전제).
        let entrances = try IntegrationContractTests.files(containing: ["MessagesBlockText.reportAction"], under: "Sources/CheckMobileKit")
        #expect(entrances.count >= 2, "대조: 신고 입구가 한 면뿐이다 — 등록부가 아니라 앱을 먼저 고쳐라: \(entrances)")

        let doc = try AppStoreDocContractTests.document("docs/appstore.md")
        let risks = try AppStoreDocContractTests.section(of: doc, heading: "## 7. 남은 위험 목록과 완화책")
        let row = try AppStoreDocContractTests.row(in: risks, containing: "사용자 생성 콘텐츠 요건")
        #expect(!row[1].contains("신고·차단이 앱에 없다"), "등록부가 낡았다 — 이미 붙은 기능을 '없다' 고 적어 두었다: \(row[1])")
        #expect(!row[4].contains("제보 창이 신고 통로"), "이미 붙은 신고 화면 대신 없는 사실을 심사 노트에 적으라고 한다: \(row[4])")
        // 남은 것(서버 게이트)을 적어야 등록부가 다시 쓸모 있다.
        #expect(row[4].contains("서버"), "차단이 실제로 막으려면 서버 마이그레이션이 필요하다는 사실이 빠졌다: \(row[4])")

        // 제출 폼에 그대로 옮기는 값 — 표시 이름 행도 같은 이름이어야 한다.
        let facts = try AppStoreDocContractTests.section(of: doc, heading: "## 0. 앱 사실 요약")
        let display = try AppStoreDocContractTests.row(in: facts, containing: "표시 이름")
        #expect(display[1].contains(CheckMobileIdentifiers.appDisplayName), "제출 자료의 표시 이름이 앱과 다르다: \(display[1])")
    }

    @Test("문서 계약: 이용약관 페이지가 나가고(무관용 · 24시간 · 신고/차단 사용법 · 처리방침 링크) 지원 페이지가 그 자리를 알린다")
    func termsDocument() throws {
        let root = IntegrationContractTests.root
        let terms = try String(contentsOf: root.appendingPathComponent("docs/terms.md"), encoding: .utf8)
        #expect(terms.contains("permalink: /terms"), "가입 화면 링크(/terms)와 페이지 주소가 갈렸다")
        #expect(terms.contains("아잉체크"), "약관이 앱 이름을 말하지 않는다")
        for word in ["괴롭힘", "혐오", "음란물", "스팸"] {
            #expect(terms.contains(word), "무관용 목록에 \(word) 가 없다")
        }
        #expect(terms.contains("무관용"))
        #expect(terms.contains("정지"), "위반 계정을 어떻게 하는지 적지 않았다")
        #expect(terms.contains("24시간 안에 확인합니다"), "신고 처리 약속이 앱 문구와 갈렸다")
        #expect(terms.contains("(privacy)"), "처리방침 링크가 없다")
        #expect(terms.contains("github.com/yehsung/check/issues"), "문의처가 없다")
        // 앱 안 문구와 같은 말을 한다 — 두 벌이 갈리면 심사에서 어느 쪽이 사실인지 묻는다.
        #expect(terms.contains("나 → 설정 → 차단한 사람"))

        let index = try String(contentsOf: root.appendingPathComponent("docs/index.md"), encoding: .utf8)
        #expect(index.contains("(terms)"), "지원 페이지에 약관 링크가 없다")
        #expect(index.contains("24시간 안에 확인합니다"))
        #expect(index.contains("신고"), "지원 페이지가 신고 창구를 알리지 않는다")

        // Jekyll 이 약관을 빼 버리면 링크가 404 가 된다(가입 화면에서 바로 닿는 주소다).
        let config = try String(contentsOf: root.appendingPathComponent("docs/_config.yml"), encoding: .utf8)
        #expect(!config.contains("- terms.md"), "약관이 exclude 에 들어 있다")
    }
}
