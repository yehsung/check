import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.51 — 상태메시지(맥 · 코어). 사장님 결정: 40자(코드포인트) · 한 줄 · 만료 없음 · 비우면 지움 · 쿨타임 없음.
//
// 이 스위트가 재는 것:
//  ① 코어 정규화·판정이 서버(`set_status_message`)와 같은 눈금이다(NFC · 줄바꿈 접기 · 앞뒤 공백 · 코드포인트 40 · 투명 → 지우기).
//  ② 디코더: 칸이 없는 옛 서버에서도 명부가 깨지지 않고, 칸이 있으면 값이 실린다(커스텀 디코더 함정).
//  ③ 전선: 저장은 `{"p_text": …}` 를 **언제나** 싣고(null 포함), 내 값은 **따로 GET** 이며, PGRST202 는 "준비 중"이다.
//  ④ 맥 스토어: 연타 = 요청 하나 · 결과 문구 · 서버 정규화 값으로 미러 · 로그아웃 리셋 · 옛 서버 GET 실패는 '모름'.
//  ⑤ 콕 목록: 상태가 있는 행만 62pt · 없는 행은 48pt 그대로 · 이름/배지 띠는 한 픽셀도 안 움직인다 · 목록 상한은 점 예산(700pt·푸터).
//  ⑥ 1:1 대화 머리: 상태 줄이 머리를 키우지 않는다(최악 크롬 여유 12pt) · 가장 키 큰 조합도 700pt 안.
//  ⑦ 설정 행: 결과 문구가 바뀌어도 행 높이가 같다(창 높이 계약) · 저장 전에 한글 조합을 확정한다(소스 계약).
// 네트워크는 `MessageReadStubProtocol`(V0330 — 호스트별 스크립트 · 요청 기록). 상태 문장은 전부 합성 문자열이다.

// MARK: - ① 코어 정규화·판정

@Suite struct V0351StatusMessageCoreTests {
    @Test func 정규화는_서버와_같은_세_단계다() {
        // NFC — 파인더에서 붙여넣은 자모 분해 한글이 2자로 세어진다.
        let nfd = "한글".decomposedStringWithCanonicalMapping
        #expect(nfd.unicodeScalars.count == 6)
        #expect(StatusMessage.sanitized(nfd) == "한글")
        #expect(StatusMessage.length(nfd) == 2)
        // 줄바꿈류가 든 공백 묶음 → 공백 하나, 줄바꿈 없는 두 칸은 그대로.
        #expect(StatusMessage.sanitized("오늘은 \n재택") == "오늘은 재택")
        #expect(StatusMessage.sanitized("a\u{2028}b\u{2029}c\u{85}d\u{0B}e\u{0C}f") == "a b c d e f")
        #expect(StatusMessage.sanitized("a\t\tb") == "a b")
        #expect(StatusMessage.sanitized("점심  먹자") == "점심  먹자")
        // 앞뒤 제거 집합(서버 btrim 과 같다): 공백 · NBSP · ZWSP · BOM · 전각 공백.
        #expect(StatusMessage.sanitized("\u{3000}\u{00A0}\u{200B}\u{FEFF} 안녕 \u{3000}") == "안녕")
        // 서버 집합에 없는 폭 있는 공백(U+2002)은 지우지 않는다 — Foundation 의 whitespaces 로 지우면 카운터가 서버와 한 칸 갈린다.
        #expect(StatusMessage.length("\u{2002}a") == 2)
    }

    @Test func 길이는_코드포인트로_세고_40까지_된다() {
        #expect(StatusMessage.maxLength == 40)
        #expect(StatusMessage.validate(String(repeating: "가", count: 40)) == .ok(String(repeating: "가", count: 40)))
        #expect(StatusMessage.validate(String(repeating: "가", count: 41)) == .tooLong(maxLength: 40))
        // 가족 이모지는 자소 1 · 코드포인트 7 — 5개(35)는 되고 6개(42)는 안 된다(서버 프로브 ④ 와 같은 표본).
        let family = "👨‍👩‍👧‍👦"
        #expect(family.count == 1 && family.unicodeScalars.count == 7)
        #expect(StatusMessage.validate(String(repeating: family, count: 5)) == .ok(String(repeating: family, count: 5)))
        #expect(StatusMessage.validate(String(repeating: family, count: 6)) == .tooLong(maxLength: 40))
        #expect(StatusMessage.counterText("👍 좋아요") == "5/40")
    }

    @Test func 비었거나_보이는_글자가_없으면_지우기다() {
        for raw in ["", "   ", " \n\t \r\n ", "\u{3000}\u{00A0}", "\u{3164}", "\u{3164}\u{3164}", "\u{200B}"] {
            #expect(StatusMessage.validate(raw) == .empty, "\(raw.unicodeScalars.map { String($0.value, radix: 16) }) 가 지우기가 아니다")
            #expect(StatusMessage.display(raw) == nil)
        }
        #expect(StatusMessage.display(nil) == nil)
        #expect(StatusMessage.display("  회의 중 🙏 ") == "회의 중 🙏")
    }

    @Test func 응답_status_를_결과로_옮기고_모르는_값은_실패로_접는다() {
        #expect(StatusMessageSaveOutcome(response: .init(status: "ok", statusMessage: "점심")) == .saved("점심"))
        #expect(StatusMessageSaveOutcome(response: .init(status: "ok", statusMessage: nil)) == .cleared)
        #expect(StatusMessageSaveOutcome(response: .init(status: "cleared")) == .cleared)
        #expect(StatusMessageSaveOutcome(response: .init(status: "too_long", maxLength: 40)) == .tooLong(maxLength: 40))
        #expect(StatusMessageSaveOutcome(response: .init(status: "too_long")) == .tooLong(maxLength: 40))
        #expect(StatusMessageSaveOutcome(response: .init(status: "not_text", maxLength: 40)) == .notText)
        #expect(StatusMessageSaveOutcome(response: .init(status: "unauthorized")) == .invalid)
        #expect(StatusMessageSaveOutcome(response: .init(status: "cooldown")) == .invalid)
        // 결과 문구 — 성공·지움은 오류가 아니다. 문구는 맥 설정 행에서 한 줄에 들도록 짧다.
        let saved = StatusMessageText.notice(for: .saved("x"))
        #expect(saved.text == StatusMessageText.saved && saved.isError == false)
        let cleared = StatusMessageText.notice(for: .cleared)
        #expect(cleared.text == StatusMessageText.cleared && cleared.isError == false)
        #expect(StatusMessageText.notice(for: .tooLong(maxLength: 40)).isError)
        #expect(StatusMessageText.notice(for: .serverNotReady).text == StatusMessageText.serverNotReady)
        for text in [StatusMessageText.hint, StatusMessageText.saved, StatusMessageText.cleared, StatusMessageText.notText,
                     StatusMessageText.invalid, StatusMessageText.serverNotReady, StatusMessageText.network, StatusMessageText.tooLong(40)] {
            #expect(text.count <= 28, "'\(text)' 가 너무 길다 — 설정 행 한 줄(328pt · caption2)을 넘으면 행이 자라 창 높이 계약이 깨진다")
        }
    }
}

// MARK: - ② 디코더

@Suite struct V0351StatusMessageDecoderTests {
    private func decode(_ json: String) throws -> [PokeDirectoryRow] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([PokeDirectoryRow].self, from: Data(json.utf8))
    }

    @Test func 칸이_없는_옛_서버도_명부가_깨지지_않는다() throws {
        let rows = try decode(#"[{"user_id":"u1","display_name":"소라","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"}]"#)
        #expect(rows.count == 1)
        #expect(rows[0].statusMessage == nil)
        #expect(rows.toPokeDirectoryEntries().first?.statusMessage == nil)
    }

    @Test func 칸이_있으면_값이_실리고_빈_값은_화면에_닿지_않는다() throws {
        let rows = try decode("""
        [{"user_id":"u1","display_name":"소라","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul","status_message":"점심 먹고 올게요"},
         {"user_id":"u2","display_name":"도윤","avatar_url":null,"is_working":false,"message_capable":true,"center":null,"status_message":null},
         {"user_id":"u3","display_name":"민재","avatar_url":null,"is_working":false,"message_capable":true,"center":null,"status_message":"\\u3164"}]
        """)
        #expect(rows.map(\.statusMessage) == ["점심 먹고 올게요", nil, "\u{3164}"])
        let entries = rows.toPokeDirectoryEntries()
        #expect(entries.map(\.statusMessage) == ["점심 먹고 올게요", nil, nil], "보이는 글자 없는 상태가 두 번째 줄로 그려진다")
    }
}

// MARK: - ③ 전선

@MainActor
private func smService(_ label: String, handler: @escaping MessageReadStubProtocol.Handler) -> (SupabaseWorkService, String) {
    let host = "v0351-sm-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    MessageReadStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MessageReadStubProtocol.session()
    )
    return (service, host)
}

@MainActor
@Suite(.serialized) struct V0351StatusMessageWireTests {
    @Test func 저장은_p_text_키를_언제나_싣는다_지우기는_null() async throws {
        let (service, host) = smService("body") { call, _ in
            call.rpc == "set_status_message"
                ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","status_message":"점심 먹고 올게요"}"#) : nil
        }
        let saved = try await service.setStatusMessage(accessToken: "t", text: "점심 먹고 올게요")
        #expect(saved == .saved("점심 먹고 올게요"))
        _ = try await service.setStatusMessage(accessToken: "t", text: nil)
        let calls = MessageReadStubProtocol.calls(host: host, rpc: "set_status_message")
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.method == "POST" })
        #expect(calls[0].body == #"{"p_text":"점심 먹고 올게요"}"#)
        #expect(calls[1].body == #"{"p_text":null}"#, "지우기가 키를 빼고 보낸다 — 서버 기본값에 기대게 된다: \(calls[1].body)")
    }

    @Test func 함수가_없는_옛_서버는_준비_중이다() async throws {
        let (service, _) = smService("missing") { call, _ in
            call.rpc == "set_status_message" ? MessageReadFixture.missingFunction("set_status_message") : nil
        }
        #expect(try await service.setStatusMessage(accessToken: "t", text: "x") == .serverNotReady)
    }

    @Test func 권한_오류와_서버_장애는_던진다() async {
        let (service, _) = smService("500") { call, _ in
            call.rpc == "set_status_message" ? MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#) : nil
        }
        await #expect(throws: (any Error).self) { _ = try await service.setStatusMessage(accessToken: "t", text: "x") }
    }

    @Test func 내_값은_따로_GET_으로_한_칸만_읽는다() async throws {
        let (service, host) = smService("get") { call, _ in
            call.path == "/rest/v1/profiles" ? MessageReadStubProtocol.Reply(body: #"[{"status_message":" 회의 중 "}]"#) : nil
        }
        let value = try await service.fetchMyStatusMessage(accessToken: "t", userID: "me-1")
        #expect(value == "회의 중")
        let call = try #require(MessageReadStubProtocol.calls(host: host).first { $0.path == "/rest/v1/profiles" })
        #expect(call.method == "GET")
        let items = URLComponents(url: call.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "select" }?.value == "status_message", "select 에 다른 칸이 섞였다 — 옛 서버에서 42703 으로 같이 죽는다")
        #expect(items.first { $0.name == "id" }?.value == "eq.me-1")
    }
}

// MARK: - ④ 맥 스토어

@MainActor
private func smDrain() async {
    for _ in 0..<60 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 내 상태메시지 GET(`profiles?select=status_message`)인가.
private func smIsStatusGET(_ call: MessageReadStubProtocol.Call) -> Bool {
    call.path == "/rest/v1/profiles" && call.method == "GET" && call.url.query?.contains("status_message") == true
}

private func smStatusGETs(_ host: String) -> [MessageReadStubProtocol.Call] {
    MessageReadStubProtocol.calls(host: host).filter(smIsStatusGET)
}

@MainActor
@Suite(.serialized) struct V0351StatusMessageStoreTests {
    @Test(.gomokuDefaultsCleanup)
    func 저장은_서버가_정규화한_값으로_미러를_맞추고_연타는_요청_하나다() async {
        let gate = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("sm-save") { call, _ in
            call.rpc == "set_status_message"
                ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","status_message":"점심 먹고 올게요"}"#, gate: gate) : nil
        }
        async let first = store.updateStatusMessage("  점심 \n먹고 올게요 ")
        await messageReadWait { store.isUpdatingStatusMessage }
        // 왕복 중 두 번째 누름은 아무것도 보내지 않는다.
        #expect(await store.updateStatusMessage("다른 문장") == false)
        gate.open()
        #expect(await first == true)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "set_status_message") == 1, "연타가 두 요청을 냈다")
        #expect(MessageReadStubProtocol.calls(host: host, rpc: "set_status_message").first?.json["p_text"] as? String == "점심 먹고 올게요",
                "클라 정규화를 거치지 않은 원문을 보냈다")
        #expect(store.myStatusMessage == "점심 먹고 올게요")
        #expect(store.myStatusMessageLoaded)
        #expect(store.statusMessageNotice == StatusMessageText.saved)
        #expect(store.isStatusMessageNoticeError == false)
        #expect(store.isUpdatingStatusMessage == false)

        // 같은 값이면 왕복하지 않는다.
        #expect(await store.updateStatusMessage("점심 먹고 올게요"))
        #expect(MessageReadStubProtocol.count(host: host, rpc: "set_status_message") == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    func 비우면_null_로_지우고_보이는_글자_없는_입력도_지우기다() async {
        let (store, host) = makeMessageReadStore("sm-clear") { call, _ in
            call.rpc == "set_status_message" ? MessageReadStubProtocol.Reply(body: #"{"status":"cleared","status_message":null}"#) : nil
        }
        store.myStatusMessage = "옛 상태"
        store.myStatusMessageLoaded = true
        #expect(await store.updateStatusMessage("\u{3164}  "))
        let call = MessageReadStubProtocol.calls(host: host, rpc: "set_status_message").first
        #expect(call?.body == #"{"p_text":null}"#)
        #expect(store.myStatusMessage == nil)
        #expect(store.statusMessageNotice == StatusMessageText.cleared)
    }

    @Test(.gomokuDefaultsCleanup)
    func 마흔한_자는_보내지_않고_서버_거절과_전송_실패는_이유를_말한다() async {
        let (store, host) = makeMessageReadStore("sm-fail") { call, index in
            guard call.rpc == "set_status_message" else { return nil }
            switch index {
            case 0: return MessageReadStubProtocol.Reply(body: #"{"status":"not_text","max_length":40}"#)
            case 1: return MessageReadFixture.missingFunction("set_status_message")
            default: return MessageReadStubProtocol.Reply(status: 500, body: "{}")
            }
        }
        #expect(await store.updateStatusMessage(String(repeating: "가", count: 41)) == false)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "set_status_message") == 0, "41자를 서버로 보냈다")
        #expect(store.statusMessageNotice == StatusMessageText.tooLong(40))
        #expect(store.isStatusMessageNoticeError)

        #expect(await store.updateStatusMessage("abc\u{202E}def") == false)
        #expect(store.statusMessageNotice == StatusMessageText.notText)
        #expect(await store.updateStatusMessage("준비 전") == false)
        #expect(store.statusMessageNotice == StatusMessageText.serverNotReady)
        #expect(await store.updateStatusMessage("장애") == false)
        #expect(store.statusMessageNotice == StatusMessageText.network)
        #expect(store.isStatusMessageNoticeError)
        #expect(store.myStatusMessage == nil, "실패가 미러를 바꿨다")
        #expect(store.isUpdatingStatusMessage == false)
    }

    @Test(.gomokuDefaultsCleanup)
    func 내_값_GET_은_성공해야만_받았다고_적는다() async {
        let (store, host) = makeMessageReadStore("sm-load") { call, index in
            guard call.path == "/rest/v1/profiles", call.url.query?.contains("status_message") == true else { return nil }
            // 첫 GET 은 칸이 없는 옛 서버(42703 → 400), 두 번째는 새 서버.
            return index == 0
                ? MessageReadStubProtocol.Reply(status: 400, body: #"{"code":"42703","message":"column profiles.status_message does not exist"}"#)
                : MessageReadStubProtocol.Reply(body: #"[{"status_message":"휴가 중 🌴"}]"#)
        }
        await store.loadMyStatusMessageIfNeeded()
        #expect(store.myStatusMessageLoaded == false, "옛 서버의 실패를 '상태 없음'으로 적었다")
        #expect(store.myStatusMessage == nil)
        await store.loadMyStatusMessageIfNeeded()
        #expect(store.myStatusMessageLoaded)
        #expect(store.myStatusMessage == "휴가 중 🌴")
        // 받은 뒤에는 '모를 때만' 문이 다시 묻지 않는다(로그인 설정 체인이 다시 돌아도 왕복이 안 는다).
        // 설정 창을 열 때의 다시 받기는 이 문이 아니다 — 아래 `설정_창을_열_때마다_…` 가 잰다.
        await store.loadMyStatusMessageIfNeeded()
        #expect(smStatusGETs(host).count == 2)
    }

    // ── 폰에서 바꾼 값(검토 지적, v0.3.51) ──
    // 같은 계정이 폰 나 > 프로필에서도 상태를 고친다. 맥이 세션당 한 번만 받으면 폰에서 바꾼 값이 맥 설정 행에 영영 안 보이고,
    // 낡은 미러 때문에 [저장]이 '같은 값'으로 잠긴다. 설정 행의 onAppear 는 창 수명에 한 번뿐이라 그 자리가 못 된다 —
    // 그래서 **진짜 설정 창 컨트롤러의 show()** 를 지나 잰다(스토어 함수만 부르면 배선을 지운 회귀가 초록으로 남는다).

    @Test(.gomokuDefaultsCleanup)
    func 설정_창을_열_때마다_내_값을_다시_받는다_폰에서_바꾼_값이_보인다() async {
        let (store, host) = makeMessageReadStore("sm-reopen") { call, index in
            guard smIsStatusGET(call) else { return nil }
            // 로그인 체인의 GET 은 '회의 중'(맥에서 쓴 값), 그 뒤 GET 은 '퇴근'(폰에서 바꾼 값).
            return MessageReadStubProtocol.Reply(body: index == 0 ? #"[{"status_message":"회의 중"}]"# : #"[{"status_message":"퇴근"}]"#)
        }
        await store.loadMyStatusMessageIfNeeded()
        #expect(store.myStatusMessage == "회의 중")
        store.statusMessageNotice = StatusMessageText.saved

        let controller = CheckSettingsWindowController(stuckWindowCheckSeconds: 60)
        controller.configure(store: store, content: { _ in AnyView(EmptyView()) })
        // 여는 문이 GET 을 띄운 뒤에는 창이 필요 없다 — 알파 0 창을 화면에 오래 두지 않는다.
        controller.show()
        controller.close()
        #expect(store.statusMessageNotice == nil, "지난번 결과 한 줄('저장했어요')이 다시 연 창에 남았다 — 값이 폰에서 바뀐 뒤라 거짓말이다")
        await messageReadWait { store.myStatusMessage == "퇴근" }
        #expect(store.myStatusMessage == "퇴근", "폰에서 바꾼 상태가 맥 설정 창에 안 보인다 — 세션당 한 번만 받았다")
        #expect(store.myStatusMessageLoaded)
        #expect(smStatusGETs(host).count == 2)

        // 같은 미러로 [저장] 판정이 서므로, 다시 연 창에서는 폰이 쓴 값('퇴근')이 '같은 값'이고 맥에서 쓴 옛 값('회의 중')은 다시 올릴 수 있다.
        MessageReadStubProtocol.register(host: host) { call, _ in
            call.rpc == "set_status_message"
                ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","status_message":"회의 중"}"#) : nil
        }
        #expect(await store.updateStatusMessage("회의 중"))
        #expect(MessageReadStubProtocol.count(host: host, rpc: "set_status_message") == 1,
                "폰이 바꾼 뒤 맥에서 옛 값을 다시 올렸는데 '같은 값'으로 보고 아무것도 안 보냈다")
        #expect(store.myStatusMessage == "회의 중")
    }

    @Test(.gomokuDefaultsCleanup)
    func 로그인과_첫_열기에서_GET_이_실패해도_다음_열기가_되살린다() async {
        let (store, host) = makeMessageReadStore("sm-reopen-fail") { call, index in
            guard smIsStatusGET(call) else { return nil }
            return index < 2
                ? MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#)
                : MessageReadStubProtocol.Reply(body: #"[{"status_message":"휴가 중 🌴"}]"#)
        }
        let controller = CheckSettingsWindowController(stuckWindowCheckSeconds: 60)
        controller.configure(store: store, content: { _ in AnyView(EmptyView()) })

        await store.loadMyStatusMessageIfNeeded()          // 로그인 체인 — 실패
        controller.show(); controller.close()               // 첫 열기 — 실패
        await messageReadWait { smStatusGETs(host).count == 2 }
        await smDrain()
        #expect(store.myStatusMessageLoaded == false)
        #expect(store.myStatusMessage == nil)

        controller.show(); controller.close()               // 두 번째 열기 — 되살아난다
        await messageReadWait { store.myStatusMessageLoaded }
        #expect(store.myStatusMessageLoaded, "두 번 실패한 뒤에는 세션 내내 상태를 모른다 — [지우기]가 안 서고 칸이 빈 채다")
        #expect(store.myStatusMessage == "휴가 중 🌴")
        #expect(smStatusGETs(host).count == 3)
    }

    @Test(.gomokuDefaultsCleanup)
    func 떠_있던_GET_은_그사이_나간_저장의_값을_되돌리지_않는다() async {
        let getGate = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("sm-get-vs-save") { call, _ in
            if smIsStatusGET(call) { return MessageReadStubProtocol.Reply(body: #"[{"status_message":"옛 값"}]"#, gate: getGate) }
            return call.rpc == "set_status_message"
                ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","status_message":"새 값"}"#) : nil
        }
        async let pendingFetch: Void = store.fetchMyStatusMessageFromServer()
        await messageReadWait { smStatusGETs(host).count == 1 }
        #expect(await store.updateStatusMessage("새 값"))
        #expect(store.myStatusMessage == "새 값")
        getGate.open()
        await pendingFetch
        #expect(store.myStatusMessage == "새 값", "저장 전에 떠난 GET 이 늦게 와 방금 쓴 상태를 옛 값으로 되돌렸다")

        // 저장 왕복 중에 열면 GET 을 띄우지 않는다(돌아올 저장 결과가 더 새 값이다).
        let saveGate = MessageReadStubGate()
        MessageReadStubProtocol.register(host: host) { call, _ in
            call.rpc == "set_status_message"
                ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","status_message":"더 새 값"}"#, gate: saveGate) : nil
        }
        async let pendingSave = store.updateStatusMessage("더 새 값")
        await messageReadWait { store.isUpdatingStatusMessage }
        store.statusMessageNotice = StatusMessageText.network
        store.refreshMyStatusMessageForSettings()
        #expect(store.statusMessageNotice == StatusMessageText.network, "저장 왕복 중에 결과 자리를 접었다 — 곧 올 결과와 섞인다")
        await smDrain()
        #expect(smStatusGETs(host).isEmpty, "저장 왕복 중에 GET 을 띄웠다")
        saveGate.open()
        #expect(await pendingSave)
        #expect(store.myStatusMessage == "더 새 값")
    }

    @Test(.gomokuDefaultsCleanup)
    func 늦게_온_앞_GET_은_뒤_GET_의_값을_덮지_않는다() async {
        let firstGate = MessageReadStubGate()
        let (store, host) = makeMessageReadStore("sm-get-order") { call, index in
            guard smIsStatusGET(call) else { return nil }
            return index == 0
                ? MessageReadStubProtocol.Reply(body: #"[{"status_message":"앞 GET"}]"#, gate: firstGate)
                : MessageReadStubProtocol.Reply(body: #"[{"status_message":"뒤 GET"}]"#)
        }
        async let first: Void = store.fetchMyStatusMessageFromServer()
        await messageReadWait { smStatusGETs(host).count == 1 }
        await store.fetchMyStatusMessageFromServer()
        #expect(store.myStatusMessage == "뒤 GET")
        firstGate.open()
        await first
        #expect(store.myStatusMessage == "뒤 GET", "늦게 도착한 앞 GET 이 뒤 GET 의 값을 덮었다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 로그아웃은_상태메시지_미러와_문구를_비운다() async {
        let gate = MessageReadStubGate()
        let (store, _) = makeMessageReadStore("sm-signout") { call, _ in
            call.rpc == "set_status_message"
                ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","status_message":"앞 사람"}"#, gate: gate) : nil
        }
        store.myStatusMessage = "앞 사람 상태"
        store.myStatusMessageLoaded = true
        store.statusMessageNotice = StatusMessageText.saved
        async let pending = store.updateStatusMessage("늦게 온 응답")
        await messageReadWait { store.isUpdatingStatusMessage }
        store.signOut()
        #expect(store.myStatusMessage == nil)
        #expect(store.myStatusMessageLoaded == false)
        #expect(store.statusMessageNotice == nil)
        #expect(store.isUpdatingStatusMessage == false)
        gate.open()
        #expect(await pending == false)
        await smDrain()
        #expect(store.myStatusMessage == nil, "로그아웃 뒤 도착한 응답이 다음 계정의 미러를 채웠다")
        #expect(store.statusMessageNotice == nil)
    }

    @Test func 대화_머리의_상태는_콕_목록에서만_온다() {
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon"], defaults: CheckTestScratch.defaults("sm-peer"))
        store.pokeDirectory = [
            PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true, statusMessage: "회의 중"),
            PokeDirectoryEntry(userID: "u2", name: "서연", avatarURL: nil, isWorking: true),
        ]
        store.selectedMessagePeerID = "u1"
        #expect(store.selectedMessagePeerStatusMessage == "회의 중")
        store.selectedMessagePeerID = "u2"
        #expect(store.selectedMessagePeerStatusMessage == nil)
        store.selectedMessagePeerID = "u-unknown"
        #expect(store.selectedMessagePeerStatusMessage == nil)
    }
}

// MARK: - ⑤ 콕 목록 레이아웃

private let smPopoverCap = 700.0

@MainActor
private func smPopoverStore(_ entries: [PokeDirectoryEntry], function: String = #function, line: Int = #line) -> WorkTimerStore {
    let tag = "sm-poke-\(line)"
    let home = CheckTestScratch.directory("token-\(tag)", function: function)
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: CheckTestScratch.defaults(tag, function: function),
        tokenUsage: TokenUsageStore(
            defaults: CheckTestScratch.defaults("token-\(tag)", function: function),
            homeDirectory: home.appendingPathComponent("home", isDirectory: true),
            cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
        )
    )
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.teamMembers = []
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.pokeDirectory = entries
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    return store
}

private func smEntries(_ count: Int, statusEvery: Int?) -> [PokeDirectoryEntry] {
    (0..<count).map { index in
        PokeDirectoryEntry(
            userID: "u\(index)", name: "사람\(index)", avatarURL: nil, isWorking: index % 2 == 0,
            center: index % 3 == 0 ? "서울" : nil,
            statusMessage: statusEvery.map { index % $0 == 0 } == true
                ? String(repeating: "상태메시지가 아주 깁니다 ", count: 3) : nil
        )
    }
}

@MainActor
private func smBitmap(_ view: some View) throws -> NSBitmapImageRep {
    try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2))
}

/// 내용 없이 배경만 그린 같은 크기의 비트맵(잉크 탐지 기준 — 배경이 그라디언트라 한 픽셀을 배경으로 삼으면 거짓말한다).
@MainActor
private func smBlank(matching bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
    let view = Color.clear
        .frame(width: CGFloat(bitmap.pixelsWide) / 2, height: CGFloat(bitmap.pixelsHigh) / 2)
        .background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
}

/// 두 비트맵이 다른 픽셀 행의 범위(y, 픽셀). 같으면 nil.
private func smDiffRows(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rows: Range<Int>? = nil) -> ClosedRange<Int>? {
    let width = min(lhs.pixelsWide, rhs.pixelsWide)
    let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
    let range = rows ?? 0..<height
    var minY = Int.max, maxY = -1
    for y in range where y < height {
        for x in stride(from: 0, to: width, by: 2) {
            guard let a = lhs.colorAt(x: x, y: y), let b = rhs.colorAt(x: x, y: y) else { continue }
            let delta = abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
            if delta > 0.03 {
                minY = min(minY, y); maxY = max(maxY, y)
                break
            }
        }
    }
    return maxY >= 0 ? minY...maxY : nil
}

@MainActor
@Suite struct V0351PokeListLayoutTests {
    @Test func 상태가_있는_행만_62pt_이고_목록_상한은_점_예산이다() {
        let plain = PokeDirectoryEntry(userID: "a", name: "가", avatarURL: nil, isWorking: true)
        var withStatus = plain
        withStatus.statusMessage = "회의 중"
        #expect(PokeDirectoryRowView.rowHeight(for: plain) == 48)
        #expect(PokeDirectoryRowView.rowHeight(for: withStatus) == 62)
        // 상한은 v0.3.50 의 '접힌 7행' 높이 그대로(384pt) — 상태 행이 섞이면 그 안에 사람이 덜 들어갈 뿐이다.
        let cap = PokeDirectoryRowView.plainRowHeight * 7 + 8 * 6
        #expect(cap == 384)
        // 상태 행 7개는 482pt — 행 수로 셌다면 98pt 를 넘겨 팝오버가 700pt 를 뚫는다.
        let statusRow: CGFloat = PokeDirectoryRowView.rowHeight(for: withStatus)
        let sevenStatusRows: CGFloat = statusRow * 7 + 8 * 6
        #expect(sevenStatusRows == 482)
        #expect(sevenStatusRows > cap)
    }

    @Test func 이름과_배지_띠는_상태가_있어도_한_픽셀도_안_움직인다() throws {
        func row(_ status: String?) -> some View {
            PokeDirectoryRowView(
                entry: PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true, center: "서울", statusMessage: status),
                cooldownRemaining: { 0 }, canPoke: true, ultraBalance: 3, center: "서울",
                onPoke: {}, onUltra: {}
            )
            .frame(width: 292, height: status == nil ? 48 : 62)
            .background(CheckTheme.panel)
        }
        let plain = try smBitmap(row(nil))
        let status = try smBitmap(row("점심 먹고 올게요 — 아주 긴 상태메시지는 꼬리가 줄임표로 잘려요"))
        #expect(plain.pixelsHigh == 48 * 2)
        #expect(status.pixelsHigh == 62 * 2)
        // 위 36pt(테두리 + 띠의 대부분)는 픽셀로 같아야 한다 — 이름·센터 배지·버튼의 자리가 그대로다.
        // (아래 모서리 둥근 곡선이 시작하는 38pt 앞까지 — 48pt 카드의 아래 모서리는 거기서 꺾인다.)
        #expect(smDiffRows(plain, status, rows: 0..<72) == nil, "상태 줄이 위 띠(이름·배지·버튼)를 밀었다")
        // 그리고 상태 줄은 실제로 그려진다(아래 14pt 띠에 잉크가 있다 — 자리만 생기고 빈 칸이면 안 된다).
        let blank = try smBitmap(
            PokeDirectoryRowView(
                entry: PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true, center: "서울", statusMessage: " "),
                cooldownRemaining: { 0 }, canPoke: true, ultraBalance: 3, center: "서울", onPoke: {}, onUltra: {}
            )
            .frame(width: 292, height: 62)
            .background(CheckTheme.panel)
        )
        #expect(smDiffRows(blank, status, rows: 96..<120) != nil, "상태 줄 자리에 아무것도 안 그려졌다")
    }

    @Test func 상태_행이_섞여도_팝오버는_700pt_안이고_푸터가_살아_있다() throws {
        let plain10 = try smBitmap(CheckMenuView(store: smPopoverStore(smEntries(10, statusEvery: nil)), previewClipsOverflowList: true))
        let status10 = try smBitmap(CheckMenuView(store: smPopoverStore(smEntries(10, statusEvery: 1)), previewClipsOverflowList: true))
        let mixed10 = try smBitmap(CheckMenuView(store: smPopoverStore(smEntries(10, statusEvery: 2)), previewClipsOverflowList: true))
        for (name, bitmap) in [("plain", plain10), ("status", status10), ("mixed", mixed10)] {
            let height = Double(bitmap.pixelsHigh) / 2
            #expect(height <= smPopoverCap, "\(name) 10명 콕 목록이 \(height)pt — 700pt 상한을 넘었다")
            let ink = try #require(smDiffRows(bitmap, try smBlank(matching: bitmap)))
            #expect(ink.upperBound > bitmap.pixelsHigh - 60, "\(name) 10명 콕 목록에서 푸터가 안 그려졌다")
        }
        // 넘치는 목록은 상태 유무와 무관하게 **같은 높이**에서 스크롤한다(상한은 점 예산 하나).
        #expect(status10.pixelsHigh == plain10.pixelsHigh, "상태 행이 목록 상한을 키웠다")
        #expect(mixed10.pixelsHigh == plain10.pixelsHigh)
    }

    @Test func 넘치지_않는_목록은_상태_행_수만큼만_자란다() throws {
        // v0.3.56: 3명(430pt)은 레일 바닥(432pt — [미션] 칸으로 8칸)에 걸려 자람이 2pt 깎인다. 4명으로 본문이 레일보다 길게 시작한다
        // (상태는 여전히 u0 · u2 두 줄이다 — 재는 뜻은 그대로).
        let plain3 = try smBitmap(CheckMenuView(store: smPopoverStore(smEntries(4, statusEvery: nil))))
        let mixed3 = try smBitmap(CheckMenuView(store: smPopoverStore(smEntries(4, statusEvery: 2))))   // u0 · u2 에 상태
        #expect(mixed3.pixelsHigh - plain3.pixelsHigh == 2 * 14 * 2, "상태 행 둘이 14pt 씩 자라지 않았다: \(mixed3.pixelsHigh - plain3.pixelsHigh)px")
        // 7명 전원이 상태를 달면 점 예산을 넘어 스크롤로 간다 — 팝오버는 '상태 없는 7명'과 같은 높이다.
        let plain7 = try smBitmap(CheckMenuView(store: smPopoverStore(smEntries(7, statusEvery: nil)), previewClipsOverflowList: true))
        let status7 = try smBitmap(CheckMenuView(store: smPopoverStore(smEntries(7, statusEvery: 1)), previewClipsOverflowList: true))
        #expect(status7.pixelsHigh == plain7.pixelsHigh)
    }
}

// MARK: - ⑥ 1:1 대화 머리

private let smWorstNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

@MainActor
private func smMessageStore(status: String?, label: String, function: String = #function) -> WorkTimerStore {
    let (store, _) = makeMessageReadStore(label, function: function)
    store.isMenuPresented = true
    store.displayNow = MessageReadFixture.now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.messageHistory = [
        MessageHistoryEntry(id: "a1", peerUserID: "u1", peerName: "영식", peerAvatarURL: nil,
                            body: String(repeating: "가나다라마바사아자차", count: 20),
                            createdAt: MessageReadFixture.now.addingTimeInterval(-300), isMine: false),
        MessageHistoryEntry(id: "a2", peerUserID: "u1", peerName: "영식", peerAvatarURL: nil, body: "네 곧 올릴게요",
                            createdAt: MessageReadFixture.now.addingTimeInterval(-200), isMine: true),
    ]
    store.messageHistoryLoaded = true
    store.pokeDirectory = [PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true, statusMessage: status)]
    store.pokeDirectoryLoaded = true
    store.openMessagePanel(peer: "u1")
    store.messageDraft = String(repeating: "답장 초안 ", count: 12)
    return store
}

@MainActor
private func smMessageBitmap(_ store: WorkTimerStore, worstChrome: Bool) throws -> NSBitmapImageRep {
    let view = CheckMenuView(
        store: store,
        previewClipsOverflowList: true,
        previewGoalEditing: worstChrome,
        previewUpdateBanner: worstChrome,
        previewUpdateNotes: worstChrome ? smWorstNotes : [],
        previewPlainTextEditors: true
    )
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
}

@MainActor
@Suite(.serialized) struct V0351MessageHeaderTests {
    @Test(.gomokuDefaultsCleanup)
    func 상태_줄은_대화_머리를_키우지_않고_가장_키_큰_조합도_700pt_안이다() throws {
        let long = String(repeating: "가", count: 40)
        for worst in [false, true] {
            let without = try smMessageBitmap(smMessageStore(status: nil, label: "hdr-none-\(worst)"), worstChrome: worst)
            let with = try smMessageBitmap(smMessageStore(status: long, label: "hdr-long-\(worst)"), worstChrome: worst)
            #expect(with.pixelsHigh == without.pixelsHigh,
                    "상태 줄이 대화 패널을 \(with.pixelsHigh - without.pixelsHigh)px 키웠다(최악 크롬 \(worst)) — 여유 12pt 를 먹는다")
            let height = Double(with.pixelsHigh) / 2
            #expect(height <= smPopoverCap, "상태 줄을 단 대화(최악 크롬 \(worst))가 \(height)pt — 700pt 상한을 넘었다")
            let ink = try #require(smDiffRows(with, try smBlank(matching: with)))
            #expect(ink.upperBound > with.pixelsHigh - 60, "상태 줄을 단 대화(최악 크롬 \(worst))에서 푸터가 안 그려졌다")
            // 그리고 실제로 그려진다(같은 높이인데 같은 그림이면 줄이 안 선 것이다).
            #expect(smDiffRows(with, without) != nil, "상태 줄이 머리에 안 그려졌다")
        }
    }
}

// MARK: - ⑦ 설정 행

@MainActor
private func smSettingsRowHeight(_ configure: (WorkTimerStore) -> Void, function: String = #function, line: Int = #line) throws -> Int {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: CheckTestScratch.defaults("sm-row-\(line)", function: function)
    )
    configure(store)
    let width = CheckSettingsView.preferredWidth - 14 * 2 - 12 * 2   // 카드 안쪽 폭 328
    let renderer = ImageRenderer(content: StatusMessageSettingsRow(store: store).frame(width: width).fixedSize())
    renderer.scale = 2
    return try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))).pixelsHigh
}

private func smStripSwiftComments(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "//") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

@MainActor
@Suite struct V0351SettingsRowTests {
    @Test func 결과_문구가_바뀌어도_행_높이가_같다() throws {
        let base = try smSettingsRowHeight { _ in }
        #expect(base > 0)
        let variants: [(String, (WorkTimerStore) -> Void)] = [
            ("저장됨 + 지우기 버튼", { $0.myStatusMessage = "회의 중"; $0.myStatusMessageLoaded = true; $0.statusMessageNotice = StatusMessageText.saved }),
            ("서버 준비 중(가장 긴 문구)", { $0.statusMessageNotice = StatusMessageText.serverNotReady; $0.isStatusMessageNoticeError = true }),
            ("연결 실패", { $0.statusMessageNotice = StatusMessageText.network; $0.isStatusMessageNoticeError = true }),
            ("40자 초과", { $0.statusMessageNotice = StatusMessageText.tooLong(40); $0.isStatusMessageNoticeError = true }),
            ("저장 중", { $0.isUpdatingStatusMessage = true }),
        ]
        for (name, configure) in variants {
            #expect(try smSettingsRowHeight(configure) == base, "\(name) 상태에서 행 높이가 바뀌었다 — 설정 창 높이 계약이 흔들린다")
        }
    }

    @Test func 저장은_한글_조합을_먼저_확정하고_행은_별명_바로_아래에_선다() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check/CheckSettingsView.swift")
        let source = smStripSwiftComments(try String(contentsOf: url, encoding: .utf8))
        let rowStart = try #require(source.range(of: "struct StatusMessageSettingsRow: View {"))
        let rowEnd = try #require(source.range(of: "// MARK:", range: rowStart.upperBound..<source.endIndex)
            ?? source.range(of: "struct AvatarRemovalSettingsRow", range: rowStart.upperBound..<source.endIndex))
        let row = String(source[rowStart.lowerBound..<rowEnd.lowerBound])
        #expect(row.contains(".background(FeedbackReplyWindowAnchor(slot: .settingsStatusMessage)"), "칸이 자기 창을 조합 확정 문에 안 알린다")
        let save = try #require(row.range(of: "private func save() {"))
        let commit = try #require(row.range(of: "FeedbackReplySend.commitActiveComposition(slot: .settingsStatusMessage)", range: save.upperBound..<row.endIndex))
        let guardCanSave = try #require(row.range(of: "guard canSave else { return }", range: save.upperBound..<row.endIndex))
        #expect(commit.lowerBound < guardCanSave.lowerBound, "조합 확정이 canSave 판정보다 뒤다 — 마지막 한글 음절이 사라진다")
        // '내 정보' 절에서 별명 바로 아래.
        let section = try #require(source.range(of: "section(\"내 정보\") {"))
        let name = try #require(source.range(of: "DisplayNameSettingsRow(store: store)", range: section.upperBound..<source.endIndex))
        let status = try #require(source.range(of: "StatusMessageSettingsRow(store: store)", range: name.upperBound..<source.endIndex))
        let between = source[name.upperBound..<status.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(between == "PanelDivider()", "상태메시지 행이 별명 바로 아래가 아니다: \(between)")
    }
}
