import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// iOS 1.0.12 — 아잉이 이모티콘의 **폰 쪽 배선·규칙**(레인 A).
//
// 맥 0.3.63(`e8bc9ee`)이 규약과 그림을 끝냈고 `CheckCore` 는 한 줄도 안 고친다. 폰이 더하는 것은 전송 입구 하나
// (`sendSticker`)와 목록 미리보기 한 줄이다. 그래서 이 스위트가 지키는 것은 넷이다.
//
//  ① **전선 계약의 폰 쪽 사본.** 토큰 여섯 문자열을 글자 그대로 못 박는다. 코드에서 조립해 오면 이 테스트는
//     자기 자신을 재게 되고, `label` 을 다듬는 커밋이 전선을 조용히 바꾼다 — 그 순간부터 먼저 올린 사람과
//     나중 올린 사람이 서로의 그림을 글자로 본다(맥 `V0362AingStickerTests` 와 같은 근거).
//  ② **서버 경계를 통과한다.** 토큰이 `MessageBody.validate` 에서 `.ok` 이고, 정규화가 **글자를 안 바꾼다**.
//     바꾸면 보내는 쪽과 받는 쪽의 비교 대상이 달라져 그림이 글자가 된다.
//  ③ **그림 여섯 장이 번들에 진짜 실렸다.** 파일을 빠뜨린 배포본은 버전·공증 검사를 전부 통과한다
//     (폰은 앱 번들·위젯 appex 둘 다에 실린다 — 여기서는 테스트 호스트가 찾는지만 잰다).
//  ④ **입력칸과 이모티콘이 서로를 망치지 않는다.** 맥에서 실제로 났던 결함 둘을 폰에서 재현 불가로 만든다:
//     이모티콘을 보내면 입력칸 글이 사라졌고(성공 분기의 `drafts[peerID] = ""`), 실패하면 쓰던 글 대신
//     `[아잉:기쁨]` 이 입력칸에 꽂혔다(실패 분기의 복원). 두 입구가 공통 몸통을 지나면서도 그 한 인자
//     (`restoresDraftOnFailure`)만 다른 것이 설계의 전부이고, 아래 ⑤~⑦ 이 그 차이를 **값으로** 잰다.
//
// ⚠️ **픽셀 색·여백은 재지 않는다**(그림을 고치는 커밋이 빨개진다). 재는 것은 그림이 바뀌어도 그대로 참인 둘뿐이다 —
//    파일이 번들에 있는가 · 판정이 그림 길로 가는가.
//
// 단언은 전부 **결과**다: 나간 요청 건수와 그 본문, 그리고 입력칸·초안의 값이 어떻게 됐는지.

/// 전선 토큰 여섯 개 — **글자 그대로**(코드에서 조립하지 않는다).
private let v1012StickerTokens: [AingSticker: String] = [
    .joy: "[아잉:기쁨]",
    .heart: "[아잉:하트]",
    .sad: "[아잉:슬픔]",
    .angry: "[아잉:화남]",
    .sleepy: "[아잉:졸림]",
    .surprised: "[아잉:놀람]",
]

/// 그리드가 보여 줄 차례 — `AingSticker.allCases` 순서를 **글자로** 적어 둔다(case 를 재배열한 커밋이 여기서 걸린다).
private let v1012StickerOrder: [String] = [
    "[아잉:기쁨]", "[아잉:하트]", "[아잉:슬픔]", "[아잉:화남]", "[아잉:졸림]", "[아잉:놀람]",
]

/// 나간 `send_message` 요청의 `p_body` 목록(JSON 을 풀어 **값으로** 센다 — `contains` 는 다른 키에 섞인 글자도 참이 된다).
@MainActor
private func v1012SentBodies(_ h: MessagesHarness) -> [String] {
    h.bodies("send_message").map { text in
        let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        return (object?["p_body"] as? String) ?? "<본문 없음: \(text)>"
    }
}

@MainActor
@Suite(.serialized) struct V1012StickerMobileTests {
    static let peerA = "peer-a"

    // MARK: ① 전선 계약(폰 쪽 사본)

    @Test("토큰 여섯 개가 글자 그대로이고 그리드 차례도 그대로다 — 화면 문구(label)와 따로다")
    func tokensAreLiteral() {
        #expect(AingSticker.allCases.count == 6, "표정 수가 바뀌었다: \(AingSticker.allCases.count)")
        for sticker in AingSticker.allCases {
            #expect(sticker.token == v1012StickerTokens[sticker], "전선 토큰이 바뀌었다: \(sticker) → \(sticker.token)")
        }
        // 순서까지 못 박는다 — case 순서가 사용자가 보는 그리드 차례다(`AingSticker` 머리말).
        #expect(AingSticker.allCases.map(\.token) == v1012StickerOrder)
        // 토큰과 화면 문구는 **따로**다. 둘이 같은 글자면 문구를 다듬는 커밋이 전선을 바꾼다.
        #expect(AingSticker.allCases.map(\.label) == ["기쁨", "하트", "슬픔", "화남", "졸림", "놀람"])
        for sticker in AingSticker.allCases {
            #expect(sticker.token != sticker.label)
        }
    }

    @Test("여섯 토큰이 서버 경계를 통과하고, 정규화가 글자를 한 자도 안 바꾼다")
    func tokensPassServerBoundary() {
        for sticker in AingSticker.allCases {
            guard case .ok(let normalized) = MessageBody.validate(sticker.token) else {
                Issue.record("토큰이 서버 경계에서 거절됐다: \(sticker.token) → \(MessageBody.validate(sticker.token))")
                continue
            }
            // ★ 정규화가 글자를 바꾸면 보낸 쪽은 그림, 받은 쪽은 글자가 된다(비교 대상이 달라진다).
            #expect(normalized == sticker.token, "정규화가 토큰을 바꿨다: \(sticker.token) → \(normalized)")
            #expect(MessageBody.length(sticker.token) == 7, "토큰 길이가 바뀌었다(200자 상한과 무관해야 한다)")
        }
    }

    // MARK: ③ 그림이 번들에 실렸다

    @Test("그림 여섯 장이 번들에 실려 있고(PNG · 비어 있지 않다), 판정은 여섯 다 그림 길로 간다")
    func sixArtworksAreInTheBundle() throws {
        for sticker in AingSticker.allCases {
            let url = try #require(AingStickerArt.url(sticker), "번들에 그림이 없다: \(sticker.resourceName).png")
            let data = try Data(contentsOf: url)
            // 색은 재지 않는다. "진짜 PNG 가 비어 있지 않게 실렸는가"만 잰다(빈 파일·플레이스홀더를 잡는 그물).
            #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]), "PNG 가 아니다: \(url.lastPathComponent)")
            #expect(data.count > 10_000, "그림이 너무 작다(\(data.count)바이트): \(url.lastPathComponent)")

            let drawable = try #require(AingStickerArt.drawable(for: sticker.token), "판정이 그림 길로 안 갔다: \(sticker.token)")
            #expect(drawable.sticker == sticker, "다른 표정으로 읽혔다: \(sticker.token) → \(drawable.sticker)")
        }
        // 대조: 평범한 본문은 그림이 아니다(판정이 전부 참이면 위 단언이 공허하다).
        #expect(AingStickerArt.drawable(for: "안녕하세요") == nil)
        #expect(AingStickerArt.drawable(for: "[아잉:기쁨] 좋아요") == nil, "앞뒤에 글자가 붙었는데 그림으로 읽혔다")
    }

    // MARK: ④ 보내기 — 나간 본문을 센다

    @Test("이모티콘을 고르면 토큰 본문이 send_message 로 정확히 한 건 나간다")
    func sendStickerPutsTokenOnTheWire() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        #expect(h.store.canSendSticker(to: Self.peerA))
        #expect(h.store.sendSticker(.joy, to: Self.peerA))
        // 자리 말풍선도 토큰 본문으로 선다(말풍선이 그림 길로 가는 근거 — 레인 B 가 이 본문을 읽는다).
        #expect(h.store.pendingOutgoing.map(\.body) == ["[아잉:기쁨]"])
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.count("send_message") == 1, "요청이 \(h.count("send_message"))건 나갔다")
        #expect(v1012SentBodies(h) == ["[아잉:기쁨]"])
        let raw = h.bodies("send_message").first ?? ""
        #expect(raw.contains(#""p_to":"peer-a""#), "받는이가 다르다: \(raw)")
        #expect(h.store.sendNotices[Self.peerA] == nil, "성공했는데 문구가 섰다")
        h.expectNoForbiddenCalls()
    }

    @Test("쓰던 글은 성공해도 실패해도 그대로다 — 이모티콘은 입력칸을 읽지도 쓰지도 않는다")
    func stickerNeverTouchesTheDraft() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        h.store.setDraft("쓰던 글", for: Self.peerA)

        // 성공 경로: 맥에서 났던 결함 — 성공 분기가 입력칸을 비웠다.
        #expect(h.store.sendSticker(.surprised, to: Self.peerA))
        #expect(h.store.draft(for: Self.peerA) == "쓰던 글", "누르는 순간 입력칸이 달라졌다")
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.draft(for: Self.peerA) == "쓰던 글", "이모티콘이 쓰던 글을 지웠다")
        #expect(v1012SentBodies(h) == ["[아잉:놀람]"])

        // 실패 경로: 맥에서 났던 결함 둘째 — 실패 분기가 쓰던 글을 토큰으로 덮었다.
        h.server.setSend(.json(#"{"status":"target_focused"}"#))
        #expect(h.store.sendSticker(.sad, to: Self.peerA))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.draft(for: Self.peerA) == "쓰던 글", "실패가 쓰던 글을 \(h.store.draft(for: Self.peerA)) 로 덮었다")
        #expect(h.store.sendNotices[Self.peerA] == "지금 집중 중이에요. 나중에 보내 주세요", "실패 문구는 그대로 선다")
        #expect(v1012SentBodies(h) == ["[아잉:놀람]", "[아잉:슬픔]"])
        h.expectNoForbiddenCalls()
    }

    @Test("실패해도 토큰이 입력칸으로 복원되지 않는다 — 같은 실패에서 초안 전송은 글을 되돌린다(그 차이를 잰다)")
    func failureRestoresDraftOnlyForDraftSends() async {
        let h = await MessagesHarness.make { server in
            server.setSend(.json(#"{"status":"target_focused"}"#))
        }
        defer { h.tearDown() }
        // 입력칸이 비어 있어야 복원 분기("비어 있을 때만 되돌린다")가 실제로 열린다 — 안 그러면 이 시험이 공허하다.
        #expect(h.store.draft(for: Self.peerA).isEmpty)
        #expect(h.store.sendSticker(.heart, to: Self.peerA))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.draft(for: Self.peerA).isEmpty, "실패한 이모티콘이 입력칸에 \(h.store.draft(for: Self.peerA)) 를 꽂았다")
        #expect(h.store.pendingOutgoing.isEmpty, "실패했는데 자리 말풍선이 남았다")

        // 대조군: **같은 실패**에서 초안 전송은 글을 되돌린다(복원 규칙을 같이 죽이지 않았다).
        h.store.setDraft("초안으로 보낸 글", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(h.store.draft(for: Self.peerA).isEmpty, "누르는 즉시 비우는 동작이 사라졌다")
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.draft(for: Self.peerA) == "초안으로 보낸 글", "실패한 초안이 안 돌아왔다")
        #expect(v1012SentBodies(h) == ["[아잉:하트]", "초안으로 보낸 글"])
        h.expectNoForbiddenCalls()
    }

    @Test("왕복 중에는 못 보낸다: canSendSticker 가 거짓이고 두 번째 요청이 0건")
    func stickerIsBlockedWhileSending() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        // 붙잡은 요청은 놓아줄 때 스텁에 기록되므로, "나갔는가"는 붙잡기의 도착 수(`held`)로 센다.
        let hold = BaseHold.rpc("send_message", host: h.host, limit: 2)
        #expect(h.store.sendSticker(.joy, to: Self.peerA))
        #expect(await hold.waitHeld(), "첫 요청이 떠나지 않았다")
        #expect(h.store.isSending, "왕복이 이미 끝나 아래 단언이 공허하다")

        #expect(!h.store.canSendSticker(to: Self.peerA))
        #expect(!h.store.sendSticker(.angry, to: Self.peerA), "왕복 중인데 나갔다고 한다")
        #expect(hold.held == 1, "왕복 중에 두 번째 요청이 나갔다: \(hold.held)건")
        #expect(h.store.pendingOutgoing.map(\.body) == ["[아잉:기쁨]"], "자리 말풍선이 둘 섰다")

        #expect(await hold.releaseAndWaitDelivered())
        await h.barrier()
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(v1012SentBodies(h) == ["[아잉:기쁨]"], "왕복이 끝난 뒤에 보니 \(v1012SentBodies(h))")
        // 왕복이 끝나면 다시 열린다(게이트가 영구 잠금이 아니다).
        #expect(h.store.canSendSticker(to: Self.peerA))
        h.expectNoForbiddenCalls()
    }

    @Test("로그인·상대 조건: 상대가 빈 문자열이면 못 보내고 요청이 0건")
    func stickerNeedsAPeer() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        #expect(!h.store.canSendSticker(to: ""))
        #expect(!h.store.sendSticker(.joy, to: ""))
        await h.settle()
        #expect(h.count("send_message") == 0)
        #expect(h.store.pendingOutgoing.isEmpty)
        h.expectNoForbiddenCalls()
    }

    // MARK: ② 목록 미리보기

    @Test("목록 미리보기: 이모티콘은 '아잉이 기쁨' · 평범한 본문의 접기는 지금과 똑같다")
    func listPreviewReadsStickersAloud() {
        #expect(MessagesListRules.preview("[아잉:기쁨]") == "아잉이 기쁨")
        for sticker in AingSticker.allCases {
            #expect(MessagesListRules.preview(sticker.token) == "아잉이 \(sticker.label)")
        }
        // 회귀 방지: 접기 동작이 한 글자도 안 달라졌다(이모티콘이 아니면 원문을 그대로 접는다).
        #expect(MessagesListRules.preview("두  줄\n글") == "두 줄 글")
        #expect(MessagesListRules.preview("안녕\n\n  잘 지내?\t응") == "안녕 잘 지내? 응")
        #expect(MessagesListRules.preview("") == "")
        #expect(MessagesListRules.preview("   ") == "")
        // 앞뒤에 글자가 붙은 토큰은 그냥 글자다 — 접기만 거친다(부분 치환이 들어오면 여기서 걸린다).
        #expect(MessagesListRules.preview("[아잉:기쁨] 좋아요") == "[아잉:기쁨] 좋아요")
        #expect(MessagesListRules.preview("📢 [아잉:기쁨]") == "📢 [아잉:기쁨]", "확성기 본문이 그림 문구로 바뀌었다")
    }

    // MARK: ⑤ 초안 전송의 기존 계약(안 변했다)

    @Test("초안 전송 계약 그대로: 성공하면 초안이 비고 서버로 그 글이 나간다 · 실패하면 되돌아온다")
    func draftSendContractUnchanged() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        h.store.setDraft("  안녕하세요\n반가워요  ", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(h.store.draft(for: Self.peerA).isEmpty, "누르는 즉시 비우지 않았다")
        #expect(h.store.pendingOutgoing.map(\.body) == ["안녕하세요\n반가워요"], "자리 말풍선 본문이 정규화 전 값이다")
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.draft(for: Self.peerA).isEmpty, "성공했는데 초안이 남으면 다음 Enter 에 같은 말이 또 나간다")
        #expect(v1012SentBodies(h) == ["안녕하세요\n반가워요"])

        h.server.setSend(.networkFailure())
        h.store.setDraft("못 나갈 글", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.draft(for: Self.peerA) == "못 나갈 글", "실패한 글이 사라졌다")
        #expect(h.store.sendNotices[Self.peerA] == MessagesSendRules.connectionNotice)
        h.expectNoForbiddenCalls()
    }
}
