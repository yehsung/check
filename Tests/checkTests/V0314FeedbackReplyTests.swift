import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// 제보 답장을 "보내는 것"으로 만든 변경(v0.3.14) — 계약 둘을 못 박는다.
//
// 사용자 요구(원문):
//   "제보에 답변 쓸때도 단순히 입력이 아니라. 보내는 버튼 까지 있어서 제보에 답장을 하고 보내기까지 해야
//    전달이 되게끔 하자. 지금은 입력하고. 이제 뭐 제대로 입력이 된건지 확인하기가 어려워."
//
// 고친 결함은 **한 덩어리 둘**이다:
//  ① 답장이 전달된 적이 없다. 서버는 `admin_note` 를 제보자에게 내려주는데(`feedback_list`) 화면이
//     한 번도 그리지 않았다 — `adminNote` 는 v0.3.13 까지 `CheckFeedbackView.swift` 에 한 글자도 없었다.
//  ② 보내기 버튼이 없다. 메모는 상태 칩을 눌러야만 저장됐고, 관리자는 자기가 쓴 게 갔는지 알 수 없었다.
//     ①을 고치는 순간 "메모 전용 저장 버튼이 없는 이유"(= 메모만 달린 제보는 화면 어디에도 안 보인다)가
//     거짓이 되므로 둘은 같이 고쳐야 했다.
//
// ★ **이 파일이 지키는 가장 중요한 한 줄: 낙관 반영이 없다.** 이 화면의 목적이 "정말 갔는지 눈으로 확인"
//   이라, 왕복 전에 목록을 고치면 실패한 답장도 '보낸 답장'으로 그려진다 — 그러면 이 버튼은 예전의
//   조용한 메모 칸과 완전히 같은 것이 된다. 실패 갈래에서 목록이 **한 글자도 안 바뀌는지**를 잰다.
//
// ★ 픽스처 본문·답장은 전부 합성 문자열이다. 실제 제보나 실제 답장을 여기 옮기지 마라.
//
// 네트워크는 V0248 의 `FeedbackURLProtocol`(테스트별 고유 호스트 + 경로별 상태코드)을 그대로 쓴다.

private let rpUserID = "00000000-0000-0000-0000-000000000002"
private let rpOtherID = "00000000-0000-0000-0000-000000000003"
private let rpReplyPath = "/rest/v1/rpc/reply_feedback"
private let rpStatusPath = "/rest/v1/rpc/set_feedback_status"
private let rpListPath = "/rest/v1/rpc/feedback_list"
private let rpLatestPath = "/rest/v1/rpc/feedback_reply_latest"

/// 서버가 답장에 찍어 주는 시각(고정). 값 자체에 뜻은 없고 **클라가 지어낸 값이 아니라는 사실**만 쓴다 —
/// 그래서 테스트 실행 시각과 한참 떨어진 값을 고른다(우연히 `Date()` 와 같아 초록이 되는 일이 없게).
private let rpServerAt = "2026-09-12T03:04:05.123456+00:00"

@MainActor
private func rpDefaults() -> UserDefaults {
    let suite = "v0314-reply-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func rpStore(host: String, signedIn: Bool = true, admin: Bool = true) -> WorkTimerStore {
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: rpDefaults()
    )
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: rpUserID)
    }
    store.ultraUnlimited = admin
    store.appVersionProvider = { AppVersionReport(build: 58, version: "0.3.14") }
    store.osVersionProvider = { "15.6" }
    return store
}

/// 200×5ms 폴링(≈1초 상한) — 비동기 스토어 반영 대기(V0248 관용구).
@MainActor
private func rpWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 합성 제보 한 건. 기본은 **남의 제보**(관리자 받은함의 평범한 행)다.
private func rpReport(
    id: String,
    status: FeedbackStatus = .open,
    owner: String? = rpOtherID,
    body: String = "샘플 본문",
    reply: String? = nil,
    replyAt: Date? = nil
) -> FeedbackReport {
    FeedbackReport(
        id: id,
        userID: owner,
        kind: .bug,
        body: body,
        status: status,
        adminNote: reply,
        adminNoteAt: replyAt,
        appVersion: "0.3.14 (58)",
        osVersion: "15.6",
        createdAt: Date(timeIntervalSince1970: 1_789_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_789_000_000),
        authorName: owner == rpUserID ? "나야" : "동료",
        authorAvatarURL: nil
    )
}

/// 펼쳐 둔 행 하나짜리 받은함. 답장 보내기의 전제(초안은 **펼친 행의 것**)를 화면과 같은 순서로 만든다.
@MainActor
private func rpExpandedStore(host: String, saved: String? = nil, draft: String) -> WorkTimerStore {
    let store = rpStore(host: host)
    store.feedbackList = [rpReport(id: "r1", reply: saved)]
    store.feedbackLoaded = true
    store.toggleFeedbackExpansion("r1")
    store.feedbackNoteDraft = draft
    return store
}

// MARK: - 순수: 보낼 수 있는가

@Test
func anEmptyOrUnchangedReplyIsNeverSendable() {
    // 빈 답장은 서버가 FEEDBACK_EMPTY_REPLY 로 거절한다(상태 RPC 와 갈리는 지점 — 거기선 빈 문자열이
    // '메모 삭제'다). 클라 게이트가 서버와 같은 자리에 서 있어야 "버튼은 살아 있는데 거절당하는" 조합이 없다.
    #expect(!FeedbackComposer.isSendableReply(draft: "", savedNote: nil))
    #expect(!FeedbackComposer.isSendableReply(draft: "   \n\t ", savedNote: nil), "공백만 친 답장을 보낼 수 있다")
    #expect(FeedbackComposer.isSendableReply(draft: "고쳤어요", savedNote: nil))
    // ★ **저장된 답장과 같으면 못 보낸다.** 서버 트리거가 `is distinct from` 으로 시각을 안 찍으므로,
    //   같은 글을 다시 보내면 왕복만 나가고 화면에는 아무 변화가 없다 — 관리자는 자기가 뭘 잘못했는지 모른다.
    #expect(!FeedbackComposer.isSendableReply(draft: "고쳤어요", savedNote: "고쳤어요"))
    #expect(!FeedbackComposer.isSendableReply(draft: "  고쳤어요  ", savedNote: "고쳤어요"), "앞뒤 공백 차이를 '다른 글'로 셌다")
    #expect(FeedbackComposer.isSendableReply(draft: "고쳤어요!", savedNote: "고쳤어요"))
    // 500자로 자른 값과 서버에 남는 값이 같아야 위 판정이 왕복 뒤에도 성립한다(안 그러면 보내고도 버튼이 산다).
    let long = String(repeating: "가", count: 600)
    let clamped = FeedbackComposer.normalizedNote(long) ?? ""
    #expect(clamped.count == 500)
    #expect(!FeedbackComposer.isSendableReply(draft: long, savedNote: clamped), "잘라 보낸 뒤에도 버튼이 살아 있다")
}

@Test
func aBlankAdminNoteIsNotAReply() {
    // 공백만 남은 메모에 답장 판을 세우면 제보자는 **답장이 온 줄 안다.** v0.3.14 이전에 저장된 행에는
    // 그런 값이 남아 있을 수 있다(그때는 상태 칩이 메모를 같이 실어 날랐다).
    #expect(rpReport(id: "x", reply: nil).reply == nil)
    #expect(rpReport(id: "x", reply: "   ").reply == nil, "공백뿐인 메모가 답장으로 그려진다")
    #expect(rpReport(id: "x", reply: " 고쳤어요 ").reply == "고쳤어요")
}

// MARK: - 스토어: 버튼 잠금 세 갈래

@MainActor
@Test
func theReplyButtonIsLockedWhenThereIsNothingNewToSendOrSomethingIsInFlight() {
    let store = rpExpandedStore(host: "v0314-gate", saved: "앞선 답장", draft: "")
    // ① 빈 초안.
    #expect(!store.canSendFeedbackReply, "빈 초안인데 답장 보내기가 열려 있다")
    // ② 저장된 답장과 같다.
    store.feedbackNoteDraft = "앞선 답장"
    #expect(!store.canSendFeedbackReply, "같은 답장을 다시 보낼 수 있다 — 눌러도 화면이 안 바뀐다")
    // 달라지면 열린다.
    store.feedbackNoteDraft = "앞선 답장 + 한 줄"
    #expect(store.canSendFeedbackReply)
    // ③ 보내는 중.
    store.feedbackReplySending = true
    #expect(!store.canSendFeedbackReply, "보내는 중인데 버튼이 살아 있다 — 연타가 같은 답장을 두 번 보낸다")
    store.feedbackReplySending = false
    // ④ 펼친 행이 없다 = 이 초안은 아무에게도 안 속한다(접은 행에 엉뚱한 답장이 붙는 것을 막는다).
    store.expandedFeedbackID = nil
    #expect(!store.canSendFeedbackReply, "펼친 행이 없는데 답장 보내기가 열려 있다")
}

// MARK: - 스토어: 성공 — 왕복이 끝나야 반영한다

@MainActor
@Test
func aSentReplyLandsInTheListOnlyAfterTheRoundTripAndKeepsTheDraft() async {
    let host = "v0314-reply-ok"
    let store = rpExpandedStore(host: host, draft: "  고쳤어요. 확인해 주세요  ")
    FeedbackURLProtocol.set(.init(status: 200, body: "\"\(rpServerAt)\""), host: host, path: rpReplyPath)

    #expect(store.feedbackList[0].adminNote == nil)
    store.sendFeedbackReply(id: "r1")
    // 낙관 반영이 **없다**: 발사 직후 목록은 아직 그대로다.
    #expect(store.feedbackList[0].adminNote == nil, "왕복 전에 목록을 고쳤다 — 실패해도 '보냈다'고 그려진다")

    await rpWait { store.feedbackNotice != nil }

    // (a) 본문은 앞뒤 공백을 걷어 보낸다. 키는 서버 시그니처 그대로 둘이다.
    let sent = FeedbackURLProtocol.sentBodies(host: host, path: rpReplyPath).first ?? ""
    let payload = ((try? JSONSerialization.jsonObject(with: Data(sent.utf8))) as? [String: Any]) ?? [:]
    #expect(Set(payload.keys) == ["p_id", "p_note"], "본문 키가 서버 시그니처와 다르다 — \(payload.keys.sorted())")
    #expect(payload["p_id"] as? String == "r1")
    #expect(payload["p_note"] as? String == "고쳤어요. 확인해 주세요", "답장 앞뒤 공백을 안 걷었다")

    // (b) 목록에 답장과 **서버가 찍은 시각**이 반영된다. 시각을 클라가 지어내면 8일 전 답장이 '방금'이 된다.
    #expect(store.feedbackList[0].adminNote == "고쳤어요. 확인해 주세요")
    let expected = ISO8601DateFormatter()
    expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let serverDate = expected.date(from: rpServerAt)
    #expect(serverDate != nil, "전제가 깨졌다 — 고정 시각 문자열을 테스트가 못 읽는다")
    #expect(store.feedbackList[0].adminNoteAt == serverDate, "서버가 준 시각이 아니라 다른 값이 들어갔다")

    // (c) 초안은 **그대로 남는다** — 보낸 글이 칸에 남아 있어야 행에 그려진 답장과 눈으로 맞춰 볼 수 있다.
    #expect(store.feedbackNoteDraft == "  고쳤어요. 확인해 주세요  ", "보내고 나서 초안을 지웠다")
    // 그리고 같은 글이 됐으므로 버튼은 **저절로** 잠긴다(두 번 보내는 길이 막힌다).
    #expect(!store.canSendFeedbackReply, "보낸 뒤에도 같은 답장을 또 보낼 수 있다")

    #expect(store.feedbackNotice == FeedbackText.replySent)
    #expect(!store.feedbackReplySending, "전송 깃발이 안 내려갔다 — 버튼이 영영 잠긴다")
    // 왕복은 **한 번**이고, 목록을 다시 받지 않는다(답장은 상태도 정렬도 안 건드린다 — 무료 플랜).
    #expect(FeedbackURLProtocol.count(host: host, path: rpReplyPath) == 1)
    #expect(FeedbackURLProtocol.count(host: host, path: rpListPath) == 0, "답장 하나에 목록 조회를 얹었다")
}

// MARK: - 스토어: 실패 — 목록이 안 바뀐다(낙관 반영이 없다는 계약)

@MainActor
@Test
func aRefusedReplyLeavesTheListExactlyAsItWas() async {
    let host = "v0314-reply-forbidden"
    let store = rpExpandedStore(host: host, saved: "앞선 답장", draft: "새 답장")
    let before = store.feedbackList
    FeedbackURLProtocol.set(
        .init(status: 403, body: #"{"code":"P0001","message":"FEEDBACK_FORBIDDEN","details":null,"hint":null}"#),
        host: host,
        path: rpReplyPath
    )

    store.sendFeedbackReply(id: "r1")
    await rpWait { store.feedbackNotice != nil }

    // ★ 이 한 줄이 이 파일의 이유다: 실패하면 목록은 **한 글자도** 안 바뀐다.
    #expect(store.feedbackList == before, "실패했는데 목록이 바뀌었다 — 안 간 답장이 '보낸 답장'으로 그려진다")
    #expect(store.feedbackList[0].adminNote == "앞선 답장")
    #expect(store.feedbackList[0].adminNoteAt == nil, "실패했는데 답장 시각이 찍혔다")
    // 초안도 살아 있다(쓰던 글을 잃으면 관리자는 그 답장을 다시 쓰지 않는다).
    #expect(store.feedbackNoteDraft == "새 답장")
    #expect(store.feedbackNotice == FeedbackText.forbidden)
    #expect(!(store.feedbackNotice ?? "").uppercased().contains("FORBIDDEN"), "서버 예외 이름이 화면으로 샜다")
    #expect(!store.feedbackReplySending)
    // 실패했다고 자동으로 다시 보내지 않는다.
    #expect(FeedbackURLProtocol.count(host: host, path: rpReplyPath) == 1)
}

@MainActor
@Test
func aServerWithoutTheReplyFunctionSaysItWillOpenSoonAndKeepsWhatWasWritten() async {
    // 브루 배포가 db push 보다 앞선 창. 여기는 목록 갈래와 다르다 — `feedback_list` 는 이미 있고
    // `reply_feedback` 만 없으므로 **행도 쓴 글도 눈앞에 있다.** 그래서 "쓰신 글은 그대로 둘게요"가
    // 무엇을 가리키는지 분명하고, 평범한 실패 문구와 갈라 말할 값이 있다.
    let host = "v0314-reply-schema-missing"
    let store = rpExpandedStore(host: host, draft: "곧 고칠게요")
    let before = store.feedbackList
    FeedbackURLProtocol.set(
        .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.reply_feedback(p_id, p_note) in the schema cache"}"#),
        host: host,
        path: rpReplyPath
    )

    store.sendFeedbackReply(id: "r1")
    await rpWait { store.feedbackNotice != nil }

    let notice = store.feedbackNotice ?? ""
    #expect(notice == FeedbackText.replySchemaMissing)
    #expect(notice != FeedbackText.replyFailed, "며칠 가는 상태에 '잠시 뒤 다시 시도'를 말한다")
    #expect(!notice.uppercased().contains("PGRST"), "PostgREST 코드가 화면으로 샜다: \(notice)")
    #expect(!notice.lowercased().contains("schema"), "'schema cache' 원문이 화면으로 샜다: \(notice)")
    #expect(!notice.contains("reply_feedback") && !notice.contains("_"), "코드 모양의 문자열이 화면에 떴다: \(notice)")
    #expect(notice.contains("그대로"), "쓴 글이 살아 있다는 것을 말하지 않는다: \(notice)")
    #expect(store.feedbackList == before, "서버에 함수가 없는데 목록에 답장이 그려졌다")
    #expect(store.feedbackNoteDraft == "곧 고칠게요")
}

@MainActor
@Test
func theReplyFailureVocabularyNeverReachesTheScreenAsCode() {
    // 서버가 던지는 어휘 넷을 사람 말로 옮긴다. 셋(빈 답장·길이·없는 제보)은 클라 게이트가 먼저 막아
    // 평소에는 안 닿지만, **게이트가 새는 날** 화면에 영문 상수가 뜨면 안 된다.
    let cases: [(String, String)] = [
        ("FEEDBACK_EMPTY_REPLY", FeedbackText.replyEmpty),
        ("FEEDBACK_NOTE_TOO_LONG", FeedbackText.replyTooLong),
        ("FEEDBACK_NOT_FOUND", FeedbackText.replyNotFound),
        ("FEEDBACK_FORBIDDEN", FeedbackText.forbidden)
    ]
    for (code, expected) in cases {
        let notice = FeedbackFailure.notice(
            for: SupabaseWorkServiceError.authMessage(code),
            fallback: FeedbackText.replyFailed
        )
        #expect(notice == expected, "\(code) 를 사람 말로 안 옮겼다: \(notice)")
    }
    for text in [
        FeedbackText.replyEmpty, FeedbackText.replyTooLong, FeedbackText.replyNotFound,
        FeedbackText.replyFailed, FeedbackText.replySchemaMissing, FeedbackText.replySent,
        FeedbackText.replyAction, FeedbackText.replyBlockTitle, FeedbackText.noteSave,
        FeedbackText.notePlaceholder
    ] {
        let upper = text.uppercased()
        #expect(!upper.contains("FEEDBACK"), "화면 문구에 내부 코드가 들어 있다: \(text)")
        #expect(!text.contains("_"), "화면 문구에 코드 모양의 밑줄이 있다: \(text)")
    }
    // 성공 문구만 초록이다 — 두 탭이 같은 값을 본다(한쪽만 고쳐지면 답장 성공이 경고색으로 뜬다).
    #expect(FeedbackText.isSuccessNotice(FeedbackText.replySent))
    #expect(FeedbackText.isSuccessNotice(FeedbackText.sendSuccess))
    #expect(!FeedbackText.isSuccessNotice(FeedbackText.replyFailed))
    #expect(!FeedbackText.isSuccessNotice(FeedbackText.statusFailed))
}

// MARK: - 스토어: 상태 칩은 이제 답장을 같이 보내지 않는다 (★ 바뀐 계약)

@MainActor
@Test
func theStatusChipsNoLongerCarryTheReplyAlong() async {
    // v0.3.13 까지 상태 칩은 메모 초안을 함께 실어 날랐고, 그게 메모가 저장되는 **유일한** 길이었다.
    // 이제 그 길은 막혀 있다 — 안 그러면 (가) 상태만 바꾸려던 클릭이 아직 다 쓰지도 않은 답장을
    // 제보자에게 보내고 (나) 서버 트리거가 `admin_note_at` 을 찍어 "답장 왔어요" 배너가 오발화한다.
    let host = "v0314-status-no-note"
    let store = rpExpandedStore(host: host, draft: "아직 다 안 쓴 답장")
    FeedbackURLProtocol.set(.init(status: 204, body: ""), host: host, path: rpStatusPath)

    store.applyFeedbackStatusFromEditor(id: "r1", status: .inProgress)
    // 낙관 반영은 **동기적**이라 이 시점의 목록이 곧 "칩이 무엇을 실어 날랐는가"의 증거다
    // (뒤이은 목록 재조회가 도착하기 전이라 흔들리지 않는다).
    #expect(store.feedbackList[0].status == .inProgress, "전제가 안 만들어졌다 — 상태 변경 자체가 안 일어났다")
    #expect(store.feedbackList[0].adminNote == nil, "상태만 바꿨는데 목록에 답장이 그려졌다")

    await rpWait { FeedbackURLProtocol.count(host: host, path: rpStatusPath) >= 1 }

    let sent = FeedbackURLProtocol.sentBodies(host: host, path: rpStatusPath).first ?? ""
    let payload = ((try? JSONSerialization.jsonObject(with: Data(sent.utf8))) as? [String: Any]) ?? [:]
    #expect(payload["p_note"] == nil, "상태 칩이 아직 답장을 같이 보낸다 — 다 쓰지도 않은 글이 제보자에게 나간다")
    #expect(Set(payload.keys) == ["p_id", "p_status"], "본문 키가 늘었다 — \(payload.keys.sorted())")
    #expect(!sent.contains("아직 다 안 쓴"), "요청 본문에 답장 초안이 실려 나갔다")
    // 답장 왕복은 한 번도 안 나갔다.
    #expect(FeedbackURLProtocol.count(host: host, path: rpReplyPath) == 0)
}

// MARK: - 스토어: 세션 없으면 아무 데도 안 간다

@MainActor
@Test
func withoutASessionNoReplyEverLeaves() async {
    let host = "v0314-no-session"
    let store = rpStore(host: host, signedIn: false)
    store.feedbackList = [rpReport(id: "r1")]
    store.feedbackLoaded = true
    store.toggleFeedbackExpansion("r1")
    store.feedbackNoteDraft = "고쳤어요"

    store.sendFeedbackReply(id: "r1")
    await rpWait { false }

    #expect(FeedbackURLProtocol.count(host: host, path: rpReplyPath) == 0)
    #expect(store.feedbackList[0].adminNote == nil)
    #expect(store.feedbackNoteDraft == "고쳤어요", "보내지도 않았는데 초안을 지웠다")
}

// MARK: - 서비스: 서버 계약 (디코딩 · 인자 없는 RPC)

@MainActor
@Test
func theListCarriesTheReplyTimestampAndSurvivesAServerThatDoesNotKnowItYet() async {
    // `admin_note_at` 은 v0.3.14 에 서버 반환에 더해진 컬럼이다. **없어도 목록이 죽으면 안 된다** —
    // 제보 목록이 죽으면 관리자는 신고가 0건이라고 믿는다(다른 Optional 들과 같은 이유).
    let host = "v0314-list-decode"
    let store = rpStore(host: host)
    FeedbackURLProtocol.set(
        .init(status: 200, body: """
        [
          {"id":"a","user_id":"\(rpOtherID)","kind":"bug","body":"샘플 본문 A","status":"doing",
           "admin_note":"고쳤어요","admin_note_at":"\(rpServerAt)","app_version":"0.3.14 (58)","os_version":"15.6",
           "created_at":"2026-09-11T00:00:00+00:00","updated_at":"2026-09-11T00:00:00+00:00",
           "display_name":"동료","avatar_url":null},
          {"id":"b","user_id":"\(rpOtherID)","kind":"request","body":"샘플 본문 B","status":"open",
           "admin_note":null,"app_version":null,"os_version":null,
           "created_at":"2026-09-10T00:00:00+00:00","updated_at":null,
           "display_name":"동료2","avatar_url":null}
        ]
        """),
        host: host,
        path: rpListPath
    )

    store.openFeedbackPanel()
    await rpWait { store.feedbackLoaded && store.feedbackList.count == 2 }

    let replied = store.feedbackList.first { $0.id == "a" }
    #expect(replied != nil, "답장이 달린 행이 목록에 없다")
    #expect(replied?.adminNote == "고쳤어요")
    #expect(replied?.adminNoteAt != nil, "서버가 준 답장 시각을 흘렸다 — 화면이 '언제 왔는지'를 못 말한다")
    // 컬럼을 아예 안 내려준 행(구버전 서버·답장 없음)은 nil 이고, 그 때문에 행이 사라지지 않는다.
    let quiet = store.feedbackList.first { $0.id == "b" }
    #expect(quiet != nil, "답장이 없는 행이 목록에서 사라졌다")
    #expect(quiet?.adminNoteAt == nil, "없는 시각을 지어냈다")
    #expect(store.feedbackList.count == 2, "컬럼 하나가 비었다고 행이 사라졌다")
}

@Test
func theReplyBadgeRpcAsksWithTheEmptyObjectAndTakesNullForAnAnswer() async throws {
    // 인자 없는 RPC 규약: PostgREST 는 **본문의 키 집합**으로 함수를 고르므로 `{}` 를 보내야 한다
    // (`feedback_open_count` 와 같다). 키가 하나라도 붙으면 PGRST202 로 함수를 못 찾는다.
    let host = "v0314-reply-latest"
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    FeedbackURLProtocol.set(.init(status: 200, body: "null"), host: host, path: rpLatestPath)
    let none = try await service.fetchFeedbackReplyLatest(accessToken: "access-token")
    #expect(none == nil, "답장이 하나도 없는데 시각을 지어냈다")
    #expect(FeedbackURLProtocol.sentBodies(host: host, path: rpLatestPath).first == "{}",
            "인자 없는 RPC 에 키를 실어 보냈다 — 서버가 함수를 못 찾는다")

    FeedbackURLProtocol.set(.init(status: 200, body: "\"\(rpServerAt)\""), host: host, path: rpLatestPath)
    let some = try await service.fetchFeedbackReplyLatest(accessToken: "access-token")
    #expect(some != nil, "서버가 준 시각을 못 읽었다 — 소수초가 붙은 timestamptz 를 통째로 흘린다")
}

@Test
func aReplyThatLandedIsNeverReportedAsAFailureJustBecauseTheClockStringLooksOdd() async throws {
    // `submitFeedback` 이 반환 id 를 옵셔널로 흘리는 것과 같은 근거: 여기까지 왔다는 것은 **서버가 이미
    // 답장을 저장했다**는 뜻이다. 스칼라 모양이 조금 달라졌다고 성공을 실패로 뒤집으면 관리자는 같은
    // 답장을 다시 보내고, 그때 서버 트리거는 시각을 안 찍어 화면은 영영 "안 갔다"고 말한다.
    let host = "v0314-odd-scalar"
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    FeedbackURLProtocol.set(.init(status: 200, body: #"{"wrapped":"2026-09-12T03:04:05+00:00"}"#), host: host, path: rpReplyPath)
    let at = try await service.replyFeedback(accessToken: "access-token", id: "r1", note: "고쳤어요")
    #expect(abs(at.timeIntervalSinceNow) < 60, "모양이 낯설다고 성공한 답장을 실패로 뒤집었다")
}

// MARK: - 화면: 답장이 실제로 그려진다

/// 답장이 있는/없는 같은 화면 둘을 그려 **그림이 달라지는지** 본다. 소스 계약만으로는 "그리는 코드가
/// 있다"까지만 알고 "픽셀로 나온다"는 모른다 — 이 저장소는 그 차이 때문에 색 결함을 8일간 놓친 적이 있다.
@MainActor
private func rpPanelBitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    let view = CheckFeedbackView(
        store: store,
        // ★ `ImageRenderer` 는 `TextEditor`/`TextField` 를 **노란 상자**로 그리고 `ScrollView` 안쪽은
        //   아예 안 그린다. 두 스위치가 없으면 아래 단언은 머리만 남은 그림을 재게 된다.
        //   **앱은 언제나 false 다**(두 기본값이 false 이고 프로덕션에서 true 를 주는 자리가 없다).
        rendersPlainTextEditor: true,
        clipsOverflowInsteadOfScroll: true,
        now: Date(timeIntervalSince1970: 1_789_000_000),
        onBack: {}
    )
    .frame(width: FeedbackPanelLayout.contentWidth + 24)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw RPRenderError.failed }
    return bitmap
}

private enum RPRenderError: Error { case failed }

/// 두 비트맵이 눈에 띄게 다른 픽셀 수.
private func rpDiffCount(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, tolerance: Double = 0.06) -> Int {
    let width = min(lhs.pixelsWide, rhs.pixelsWide)
    let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
    var count = 0
    for y in stride(from: 0, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 2) {
            guard let a = lhs.colorAt(x: x, y: y), let b = rhs.colorAt(x: x, y: y) else { continue }
            let delta = abs(a.redComponent - b.redComponent)
                + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
            if delta > tolerance { count += 1 }
        }
    }
    return count
}

@MainActor
@Test
func theReplyShowsUpOnTheRowForBothTheAdminAndThePersonWhoReportedIt() throws {
    let replyAt = Date(timeIntervalSince1970: 1_789_000_000 - 600)   // "10분 전"
    let reply = "확인했어요. 다음 버전에서 고칠게요."

    // ① 받은 제보(관리자) — 답장이 있는 행과 없는 행의 그림이 달라야 한다.
    func inbox(host: String, withReply: Bool) -> WorkTimerStore {
        let store = rpStore(host: host)
        store.feedbackShowsInbox = true
        store.feedbackLoaded = true
        store.feedbackList = [rpReport(id: "r1", reply: withReply ? reply : nil, replyAt: withReply ? replyAt : nil)]
        return store
    }
    let inboxWith = try rpPanelBitmap(inbox(host: "v0314-render-inbox-reply", withReply: true))
    let inboxWithout = try rpPanelBitmap(inbox(host: "v0314-render-inbox-plain", withReply: false))
    FeedbackSnapshots.save(inboxWith, name: "panels-feedback-reply-inbox.png")
    #expect(rpDiffCount(inboxWith, inboxWithout) > 50,
            "관리자 행에 답장이 안 그려졌다 — 자기가 답장한 제보에 또 답장하게 된다")
    #expect(inboxWith.pixelsHigh > inboxWithout.pixelsHigh, "답장 판이 행에 자리를 안 만들었다")

    // ② 보내기 탭(제보자) — **여기가 유일한 수신 경로다.** 이게 안 그려지면 v0.3.13 상태로 되돌아간다.
    func mine(host: String, withReply: Bool) -> WorkTimerStore {
        let store = rpStore(host: host, admin: false)
        store.feedbackLoaded = true
        store.feedbackList = [
            rpReport(id: "m1", owner: rpUserID, reply: withReply ? reply : nil, replyAt: withReply ? replyAt : nil)
        ]
        return store
    }
    let mineWith = try rpPanelBitmap(mine(host: "v0314-render-mine-reply", withReply: true))
    let mineWithout = try rpPanelBitmap(mine(host: "v0314-render-mine-plain", withReply: false))
    FeedbackSnapshots.save(mineWith, name: "panels-feedback-reply-mine.png")
    #expect(rpDiffCount(mineWith, mineWithout) > 50,
            "제보자 행에 답장이 안 그려졌다 — 답장은 여전히 아무도 못 본다(v0.3.13 의 결함 그대로다)")
    #expect(mineWith.pixelsHigh > mineWithout.pixelsHigh, "답장 판이 내 제보 행에 자리를 안 만들었다")

    // ③ 펼친 행에 [답장 보내기] 줄이 선다 — 그 줄이 없으면 답장은 영영 못 나간다.
    let expandedWith = rpExpandedStore(host: "v0314-render-expanded", draft: "고쳤어요")
    expandedWith.feedbackShowsInbox = true
    let collapsed = rpStore(host: "v0314-render-collapsed")
    collapsed.feedbackShowsInbox = true
    collapsed.feedbackLoaded = true
    collapsed.feedbackList = [rpReport(id: "r1")]
    let expandedBitmap = try rpPanelBitmap(expandedWith)
    let collapsedBitmap = try rpPanelBitmap(collapsed)
    FeedbackSnapshots.save(expandedBitmap, name: "panels-feedback-reply-editor.png")
    #expect(expandedBitmap.pixelsHigh > collapsedBitmap.pixelsHigh, "펼쳐도 편집 도구가 안 나왔다")
    #expect(rpDiffCount(expandedBitmap, collapsedBitmap) > 200)
}

// MARK: - 화면: 높이 예산 (답장이 행을 높인다)

/// 제보 패널이 열린 **메인 화면** 스토어(V0248 의 `fbMenuStore` 와 같은 재료). 팀이 확정된 로그인
/// 상태여야 팝오버가 헤더 카드·레일·푸터를 그린다 — 안 그러면 이 스냅샷이 아무것도 증명하지 못한다.
@MainActor
private func rpMenuStore(_ store: WorkTimerStore) -> WorkTimerStore {
    let now = Date(timeIntervalSince1970: 1_789_000_000)
    store.isMenuPresented = true
    store.displayNow = now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.startedAt = now.addingTimeInterval(-3_600)
    store.isFeedbackPanelVisible = true
    return store
}

/// 팝오버가 얹을 수 있는 **가장 큰 크롬**(새 버전 배너 + 패치노트 4줄 149pt + 주간 목표 편집 92pt = 241pt).
private let rpWorstNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

@MainActor
private func rpMenuBitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    let view = CheckMenuView(
        store: store,
        previewClipsOverflowList: true,
        previewGoalEditing: true,
        previewUpdateBanner: true,
        previewUpdateNotes: rpWorstNotes,
        previewPlainTextEditors: true
    )
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw RPRenderError.failed }
    return bitmap
}

/// 팝오버 높이 상한(pt). 창은 위 모서리가 메뉴바 아래에 고정되고 아래로만 자라므로, 이걸 넘으면
/// 푸터(로그아웃/앱 종료)가 화면 밖으로 잘린다 — 그 순간 사용자는 로그아웃할 방법을 잃는다.
private let rpPopoverHeightCap: Double = 700

@MainActor
@Test
func aFiveHundredCharacterReplyNeverPushesTheFooterOffTheScreen() throws {
    // ★ **답장은 말줄임을 안 한다**(제보자에게 유일한 수신 경로라 뒤를 자르면 답장을 반만 받는다).
    //   그 말은 500자짜리 답장이 정말로 행을 한 뼘 늘린다는 뜻이고, 그 몫이 스크롤 판정
    //   (`FeedbackPanelLayout.replyBlockHeight`)에 안 들어가면 목록이 프레임을 넘어 잘린다.
    //   V0248 의 렌더 픽스처는 짧은 메모("샘플 메모") 하나뿐이라 이 갈래를 못 본다.
    let longReply = "확인했어요. " + String(repeating: "가나다라마바사아자차 ", count: 45)
    #expect(longReply.count >= 450, "전제가 안 만들어졌다 — 답장이 충분히 길지 않다")
    let repliedAt = Date(timeIntervalSince1970: 1_789_000_000 - 3600)

    for (label, showsInbox) in [("inbox", true), ("mine", false)] {
        let store = rpStore(host: "v0314-cap-\(label)", admin: showsInbox)
        store.feedbackShowsInbox = showsInbox
        store.feedbackLoaded = true
        store.feedbackNotice = FeedbackText.replySent
        store.feedbackDraft = String(repeating: "가나다라마바사아자차 ", count: 8)
        // 행 여럿이 전부 긴 답장을 달고 있는, 이 화면이 만날 수 있는 가장 키 큰 목록.
        store.feedbackList = (0..<6).map {
            rpReport(
                id: "row-\($0)",
                owner: showsInbox ? rpOtherID : rpUserID,
                reply: longReply,
                replyAt: repliedAt
            )
        }
        if showsInbox {
            store.toggleFeedbackExpansion("row-0")
            store.feedbackNoteDraft = longReply + " 그리고 한 줄 더"
        }
        let bitmap = try rpMenuBitmap(rpMenuStore(store))
        FeedbackSnapshots.save(bitmap, name: "panels-feedback-reply-tallest-\(label).png")
        let height = Double(bitmap.pixelsHigh) / 2.0
        #expect(height <= rpPopoverHeightCap, "\(label) 긴 답장 + 최악 크롬이 700pt 를 넘었다: \(height)pt")
        #expect(bitmap.pixelsWide == 414 * 2, "\(label) 답장 판이 본문 열을 밀어냈다")
    }
}

// MARK: - 화면: 소스 계약 (그리는 코드가 실제로 그 자리에 있는가)

private func rpSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/\(name)")
    return rpStrippingComments(try String(contentsOf: url, encoding: .utf8))
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(문자열 리터럴 안의 `//` 는 남긴다).
/// **반드시 이걸 통과시킨다** — 안 그러면 "왜 이렇게 했는지"를 적은 주석이 단언에 걸려, 다음 사람이
/// 설명을 지워야만 초록이 된다(이 저장소가 실제로 겪은 함정이다).
private func rpStrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let c = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

@Test
func theReplyButtonSitsOnItsOwnLineAndTheOldExcuseIsGone() throws {
    let view = try rpSource("CheckFeedbackView.swift")
    // ① 답장 판이 두 행 모두에 있다(관리자 · 제보자).
    #expect(view.components(separatedBy: "FeedbackReplyBlock(note:").count - 1 == 2,
            "답장 판이 두 행(받은 제보 · 내가 보낸 제보) 모두에 서 있지 않다")
    // ② [답장 보내기]가 상태 칩 줄과 **다른 HStack** 에 있다. 292pt 에 칩이 이미 넷이라,
    //    같은 줄에 넣으면 v0.2.48 의 말줄임 사고가 그대로 재현된다.
    let chipLine = "ForEach(FeedbackStatus.transitions, id: \\.self)"
    let buttonMarker = "label: isReplySending ? FeedbackText.replySending : FeedbackText.replyAction"
    let chipIndex = try #require(view.range(of: chipLine)?.lowerBound, "상태 칩 줄을 못 찾았다")
    let buttonIndex = try #require(view.range(of: buttonMarker)?.lowerBound, "[답장 보내기] 버튼을 못 찾았다")
    #expect(buttonIndex < chipIndex, "보내기 버튼이 상태 칩 뒤에 있다 — 동선이 '쓴다 → 보낸다 → 분류한다'가 아니다")
    let between = String(view[buttonIndex..<chipIndex])
    #expect(between.contains("HStack(spacing: 5)"),
            "[답장 보내기]가 상태 칩과 같은 줄에 섰다 — 292pt 에서 칩 넷과 겹쳐 말줄임이 난다")

    // ③ 스토어가 판정을 **혼자** 한다(행이 다시 세면 버튼과 스토어가 갈린다).
    #expect(view.contains("canSendReply: store.canSendFeedbackReply"))
    #expect(view.contains("store.sendFeedbackReply(id: report.id)"))

    // ④ 낙관 반영 금지가 **구조로** 지켜진다: 목록을 고치는 줄이 `try await` **뒤에만** 있다.
    //    행동 쪽 증거는 위 `aRefusedReplyLeavesTheListExactlyAsItWas` 가 대고, 여기서는 그 성질이
    //    나중에 "빨리 보이게" 위로 옮겨지는 것을 막는다(그 순간 이 기능의 목적이 사라진다).
    let store = try rpSource("WorkTimerStoreFeedback.swift")
    let replyBody = String(store[try #require(store.range(of: "func performSendFeedbackReply")).lowerBound...])
    let awaited = try #require(replyBody.range(of: "try await withSessionRetry"), "왕복이 없다").lowerBound
    let mutation = try #require(replyBody.range(of: "feedbackList[index].adminNote = note"), "목록을 안 고친다").lowerBound
    #expect(awaited < mutation, "왕복 전에 목록을 고친다 — 실패한 답장도 '보낸 답장'으로 그려진다")
    #expect(replyBody.components(separatedBy: "feedbackList[index]").count - 1 == 2,
            "답장이 목록을 두 줄보다 많은 자리에서 고친다 — 그중 하나는 왕복 전일 수 있다")

    // ⑤ 상태 칩 경로에서 메모가 사라졌다(바뀐 계약의 소스 쪽 짝).
    #expect(!store.contains("changeFeedbackStatus(id: id, to: status, note: FeedbackComposer.normalizedNote"),
            "상태 칩이 아직 메모 초안을 실어 나른다")
    #expect(store.contains("changeFeedbackStatus(id: id, to: status, note: nil)"))
}
