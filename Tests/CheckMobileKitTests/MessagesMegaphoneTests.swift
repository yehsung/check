import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 확성기(📢 1.0.7) — 폰 배선. 코어 `MegaphoneStore` 가 폰 호스트(`MobileGomokuHost` — 오목·체스·상점과 같은 루비 미러)를 빌려
/// 맥과 **같은 판정**으로 도는지, 메시지 탭 시트가 그 스토어에 닿는지, 데모 픽스처가 진짜 디코드를 지나는지 잰다.
/// (판정·문구 자체의 값 검증은 맥 스위트 `V0351MegaphoneCoreTests` 가 한다 — 같은 코드다.)
@MainActor
@Suite(.serialized) struct MessagesMegaphoneTests {
    nonisolated static func info(recipients: Int = 9, ruby: Int? = nil, cooldown: Int = 0) -> String {
        var text = #"{"status":"ok","enabled":true,"price":50,"cooldown_seconds":600,"cooldown_remaining_seconds":\#(cooldown),"#
            + #""recipients":\#(recipients),"max_length":198"#
        if let ruby { text += #","ruby_balance":\#(ruby)"# }
        return text + "}"
    }

    @Test("시트 흐름: 정보 → 잔량 미러 · 첫 [보내기] 는 요청 0 · 확인 연타 = 요청 1 · 결과 · 미러 = 서버 값 · 금지 호출 0")
    func sendFlow() async throws {
        let wallet = MegaWallet(130)
        let harness = await MessagesHarness.make { server in
            server.override("megaphone_info") { _ in .json(Self.info(recipients: 9, ruby: wallet.value)) }
            server.override("send_megaphone") { _ in
                let left = wallet.spend(50)
                return .json(#"{"status":"ok","duplicate":false,"megaphone_id":"m1","recipients":9,"price":50,"ruby_balance":\#(left)}"#)
            }
        }
        defer { harness.tearDown() }
        let mega = harness.store.megaphone
        #expect(mega.host != nil, "확성기 스토어에 호스트가 없다 — 세션·루비 미러를 못 빌린다")
        mega.open()
        _ = await baseWaitUntil { mega.info != nil }
        #expect(harness.model.context.gomokuHost.rubyBalance == 130, "정보 응답의 잔량이 공유 미러에 안 들어갔다")
        #expect(mega.infoLine(now: harness.model.context.clock.now()) == "지금 보내면 9명의 화면에 떠요")
        mega.setDraft("오늘 3시 라운지에서 간식 나눠요")
        mega.requestSend()
        #expect(mega.isConfirming && harness.count("send_megaphone") == 0, "첫 [보내기] 가 요청을 냈다")
        #expect(mega.confirmQuestion == "루비 50개로 9명에게 보낼까요?")
        #expect(mega.confirmSend())
        #expect(!mega.confirmSend(), "확인 연타가 두 번째 요청을 띄웠다")
        _ = await baseWaitUntil { !mega.isSending && !mega.infoLoading }
        await harness.barrier()
        #expect(harness.count("send_megaphone") == 1)
        let body = try #require(harness.bodies("send_megaphone").first)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(Set(json.keys) == ["p_body", "p_request_id"])
        #expect(json["p_body"] as? String == "오늘 3시 라운지에서 간식 나눠요")
        #expect(mega.notice == "보냈어요 · 9명에게" && !mega.noticeIsError)
        #expect(harness.model.context.gomokuHost.rubyBalance == 80, "보낸 뒤 미러가 서버 값이 아니다")
        #expect(mega.draft.isEmpty && mega.pendingRequestID == nil)
        harness.expectNoForbiddenCalls()
    }

    @Test("연결 오류 뒤 다시 확인하면 같은 요청 id 로 묻는다")
    func retryReusesTheRequestID() async throws {
        let calls = MegaWallet(0)
        let harness = await MessagesHarness.make { server in
            server.override("megaphone_info") { _ in .json(Self.info()) }
            server.override("send_megaphone") { _ in
                calls.spend(-1) == 1 ? .networkFailure(.networkConnectionLost)
                    : .json(#"{"status":"ok","duplicate":true,"recipients":9,"ruby_balance":10}"#)
            }
        }
        defer { harness.tearDown() }
        let mega = harness.store.megaphone
        mega.open()
        _ = await baseWaitUntil { mega.info != nil }
        mega.setDraft("다시 보내기 시험")
        mega.requestSend()
        mega.confirmSend()
        _ = await baseWaitUntil { !mega.isSending && mega.notice != nil }
        #expect(mega.notice == MegaphoneText.connection)
        let held = try #require(mega.pendingRequestID)
        mega.confirmSend()
        _ = await baseWaitUntil { !mega.isSending && mega.notice != MegaphoneText.connection }
        await harness.barrier()
        let ids = harness.bodies("send_megaphone").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["p_request_id"] as? String
        }
        #expect(ids == [held, held], "재시도의 id 가 다르다: \(ids)")
        #expect(mega.notice == "이미 보냈어요 · 9명에게")
    }

    @Test("함수가 없는 서버(PGRST202)는 '지금은 보낼 수 없어요'로 접고 버튼을 잠근다")
    func missingServerFunction() async throws {
        let harness = await MessagesHarness.make { _ in }   // 기본 응답 = 404 PGRST202
        defer { harness.tearDown() }
        let mega = harness.store.megaphone
        mega.open()
        _ = await baseWaitUntil { mega.serverUnavailable || mega.infoFailed }
        #expect(mega.serverUnavailable)
        #expect(mega.infoLine(now: harness.model.context.clock.now()) == "지금은 보낼 수 없어요")
        mega.setDraft("보낼 수 있나")
        #expect(!mega.canRequestSend)
        mega.requestSend()
        #expect(!mega.isConfirming && harness.count("send_megaphone") == 0)
    }

    @Test("로그아웃·계정 전환은 확성기 글·정보를 비운다(메시지 스토어 reset 이 함께 부른다)")
    func resetOnAccountSwitch() async throws {
        let harness = await MessagesHarness.make { server in
            server.override("megaphone_info") { _ in .json(Self.info(ruby: 99)) }
        }
        defer { harness.tearDown() }
        let mega = harness.store.megaphone
        mega.open()
        _ = await baseWaitUntil { mega.info != nil }
        mega.setDraft("앞 계정의 글")
        await harness.switchAccount()
        #expect(mega.draft.isEmpty, "다음 계정이 앞 계정의 확성기 글을 본다")
        #expect(mega.info == nil && mega.pendingRequestID == nil && !mega.isComposerOpen)
    }

    @Test("데모 픽스처: 정보·전송이 진짜 디코드를 지난다 · 잔량 키가 없어 공유 미러를 덮지 않는다 · 금지 호출 0")
    func demoFixtures() async throws {
        let demo = await MessagesDemoFixtureTests.make(route: "messages")
        defer { demo.tearDown() }
        let mega = demo.store.megaphone
        let before = demo.model.context.gomokuHost.rubyBalance
        mega.open()
        _ = await baseWaitUntil { mega.info != nil || mega.serverUnavailable || mega.infoFailed }
        #expect(mega.info?.recipients == 12 && mega.info?.price == 50, "데모 megaphone_info 픽스처가 안 읽혔다")
        #expect(demo.model.context.gomokuHost.rubyBalance == before, "데모 정보가 공유 루비 미러를 덮었다 — 탭마다 다른 잔량이 보인다")
        demo.model.context.gomokuHost.rubyBalance = nil   // 잔량을 모르면 서버(픽스처)가 판정한다
        mega.setDraft("데모 방송")
        mega.requestSend()
        mega.confirmSend()
        _ = await baseWaitUntil { !mega.isSending }
        #expect(mega.notice == "보냈어요 · 12명에게", "데모 send_megaphone 픽스처가 안 읽혔다: \(String(describing: mega.notice))")
        let violations = MobileForbiddenCalls.violations(in: demo.requests)
        #expect(violations.isEmpty, "금지 호출: \(violations)")
        #expect(!MobileForbiddenCalls.forbiddenRPCs.contains("send_megaphone"), "폰도 확성기를 보낸다(사장님 결정) — 금지 목록에 넣지 마라")
    }

    @Test("소스 계약(폰 뷰는 맥 스위트가 컴파일하지 않는다): 📢 버튼 → 시트 · 요청은 확인 단계 한 곳 · 조합 확정 뒤")
    func sourceContracts() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesTab.swift")
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesMegaphoneSheet.swift")
        #expect(tab.contains("MessagesMegaphoneToolbarButton { showsMegaphone = true }"), "메시지 탭에 📢 버튼이 없다")
        #expect(tab.contains(".sheet(isPresented: $showsMegaphone)") && tab.contains("MessagesMegaphoneSheet(store: store)"))
        #expect(tab.contains("showsMegaphone = false"), "딥링크가 확성기 시트를 안 닫는다")
        #expect(sheet.components(separatedBy: "mega.confirmSend()").count - 1 == 1, "confirmSend 를 부르는 자리가 하나가 아니다")
        #expect(sheet.contains("commitThen { mega.confirmSend() }") && sheet.contains("commitThen { mega.requestSend() }"),
                "버튼이 한글 조합 확정을 안 거친다")
        #expect(sheet.contains("MessagesComposerTextView("), "입력칸이 UITextView(조합을 아는 칸)가 아니다")
        #expect(sheet.contains(".onAppear { mega.open() }") && sheet.contains(".onDisappear { mega.close() }"))
        #expect(sheet.contains("RubyBalanceChip(store.context.gomokuHost.rubyBalance"), "시트가 공유 루비 미러를 안 보여 준다")
        #expect(sheet.contains(".sheetCloseButton {"), "시트 머리: 왼쪽 위 유리 ✕ 하나")
        for code in [tab, sheet] {
            #expect(!code.contains("sendMegaphone("), "뷰가 서비스를 직접 부른다")
        }
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesStore.swift")
        #expect(store.contains("MegaphoneStore(host: context.gomokuHost)"), "확성기 호스트가 공유 루비 미러가 아니다")
        #expect(store.contains("megaphone.reset()"), "로그아웃이 확성기 글을 안 비운다")
    }
}

/// 스텁 응답기의 잠금 지갑·카운터(`spend(-1)` = 하나 올리고 그 값을 돌려준다).
final class MegaWallet: @unchecked Sendable {
    private let lock = NSLock()
    private var balance: Int
    init(_ balance: Int) { self.balance = balance }
    var value: Int { lock.lock(); defer { lock.unlock() }; return balance }
    @discardableResult
    func spend(_ amount: Int) -> Int { lock.lock(); defer { lock.unlock() }; balance -= amount; return balance }
}
