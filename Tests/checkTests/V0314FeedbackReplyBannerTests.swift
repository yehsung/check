import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check

// 제보 답장 **알림 배너**(v0.3.14, 갈래 C) — 사용자 요구(원문):
//   "본인이 보낸 제보에 답장이 오면, 예시로 지난주 근무기록 알림으로 보여주는것처럼.
//    위에 알림으로 알려줄 수 있으면 좋을듯"
//
// 그래서 이 배너는 회고 배너(`showsRetroBanner`)를 **그대로 베낀 것**이고, 이 파일이 재는 것도 그 베낌이
// 어긋나지 않았는가다. 지키는 계약 넷:
//
//  ① **저장값보다 새로운 답장에만 배너를 세운다.** 기준은 서버가 준 `feedback_reply_latest()` 시각이고,
//     '봤음' 기록은 **계정별 UserDefaults 키**에 ISO8601 로 적는다. 전역 키 하나면 한 맥을 나눠 쓰는 두
//     계정 중 한쪽이 답장 알림을 통째로 잃는다(회고가 실제로 겪고 고친 결함).
//  ② **적는 값은 서버 시각이지 `Date()` 가 아니다.** 지금 시각을 적으면 이 맥 시계가 서버보다 앞선 만큼
//     '미래까지 봤다'고 선언하는 셈이라 그 사이에 온 답장이 영영 안 뜬다.
//  ③ **여는 순간 1회, 폴링 금지.** 무료 플랜에 40명이 상시로 물으면 그 자체가 요금제를 넘는다
//     (`refreshFeedbackOpenCount` 주석이 못 박은 규약).
//  ④ **배너는 동시에 하나.** 우선순위 longSession > retro > feedbackReply > update 이고, 창은 700pt 상한 안이다.
//
// ★ 그리고 이 화면의 대표 회귀 하나: `topBanner` 가 시각 의존 판정을 직접 부르면 팝오버 전체 서브트리가
//   매초 무효화된다. 스토어가 **판정 결과만** 밀어 넣는 구조인지를 `withObservationTracking` 으로 실측한다.
//
// 네트워크는 V0248 의 `FeedbackURLProtocol`(호스트×경로별 상태코드·본문 + 보낸 본문 기록)을 그대로 쓴다.

private let frbUserID = "00000000-0000-0000-0000-000000000002"
private let frbOtherUserID = "00000000-0000-0000-0000-000000000009"
private let frbLatestPath = "/rest/v1/rpc/feedback_reply_latest"

/// 서버가 준 답장 시각(고정). 실행 시각과 한참 떨어뜨려 둔다 — 클라가 `Date()` 를 지어내 적어도
/// 우연히 초록이 되는 일이 없게 하기 위해서다(계약 ②를 재는 자가 이 거리다).
private let frbServerAt = "2026-09-12T03:04:05.123456+00:00"
private let frbServerAtNewer = "2026-09-12T03:04:05.987654+00:00"

private func frbDate(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: text) else {
        fatalError("픽스처가 깨졌다 — 고정 시각 문자열을 못 읽는다: \(text)")
    }
    return date
}

@MainActor
private func frbDefaults() -> UserDefaults {
    let suite = "v0314-reply-banner-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 토큰 스캔이 실홈을 훑지 않게 격리한 토큰 스토어(렌더 테스트의 inertTokenStore 와 같은 규약).
@MainActor
private func frbInertTokenStore(defaults: UserDefaults) -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: defaults,
        homeDirectory: tmp.appendingPathComponent("v0314-banner-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("v0314-banner-cache-\(id).json", isDirectory: false)
    )
}

/// 로그인 + 소속 팀 확정 상태의 스토어(= 메인 화면). 배너 판정의 전제를 화면과 같은 순서로 세운다.
@MainActor
private func frbStore(
    host: String,
    defaults: UserDefaults? = nil,
    userID: String = frbUserID,
    now: Date = Date()
) -> WorkTimerStore {
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults ?? frbDefaults(),
        tokenUsage: frbInertTokenStore(defaults: defaults ?? frbDefaults())
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되게 선세팅한다(티커 미발사).
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    store.displayNow = now
    store.currentTeamID = "10000000-0000-0000-0000-000000000001"
    store.teamName = "아잉팀"
    store.teamMembers = (0..<4).map { i in
        TeamMemberStatus(
            id: "aaaaaaaa-0000-0000-0000-\(String(format: "%012d", i))",
            name: "멤버\(i)",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 3_600
        )
    }
    return store
}

/// 200×5ms 폴링(≈1초 상한) — 비동기 스토어 반영 대기(V0248/V0314 관용구).
@MainActor
private func frbWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 팝오버를 자연 크기로 그려 픽셀 높이를 돌려준다. 폭을 밖에서 강제하지 않는 이유는
/// `CheckMenuRenderTests.renderNaturalBitmap` 주석에 있다(414pt 화면을 340 에 가두면 좌표가 통째로 어긋난다).
@MainActor
private func frbRenderedHeight(_ view: CheckMenuView) -> Int? {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.pixelsHigh
}

/// 팝오버를 자연 크기로 그린 그림의 **짧은 지문**(SHA-256 앞 16자리). 높이가 **같은** 배너 둘
/// (회고·답장 모두 InlineActionBanner 54pt) 중 어느 쪽이 그려졌는지는 높이로는 절대 못 가른다 —
/// 기준선이 같은 입력이면 그 비교는 영원히 초록이다. 그래서 그 갈래만 픽셀로 본다.
///
/// ⚠️ **Data 를 그대로 비교하지 마라.** 실측: 이 파일을 그렇게 썼다가 뮤테이션으로 빨개진 순간
/// 러너가 100KB 짜리 Data 두 개를 실패 메시지로 풀어쓰느라 10분을 100% CPU 로 돌고도 안 끝났다
/// (테스트가 무는지 확인할 길이 통째로 막힌다). 지문이면 실패 메시지도 한 줄이다.
@MainActor
private func frbRenderedFingerprint(_ view: CheckMenuView) throws -> String {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { throw FRBRenderError.failed }
    return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

private enum FRBRenderError: Error { case failed }

/// `withObservationTracking` 의 onChange(@Sendable)에서 결과를 받아 두는 상자.
/// 통지는 값을 바꾼 그 스레드에서 동기로 오므로(여기선 메인) 락 없이 안전하다.
private final class FRBObservationFlag: @unchecked Sendable {
    var value = false
}

// MARK: - ① 저장값보다 새로운 답장에만 배너를 세운다

@MainActor
@Test
func theReplyBannerStandsOnlyForAReplyNewerThanWhatThisAccountAlreadySaw() {
    let store = frbStore(host: "v0314-banner-gate")

    // (a) 답장을 모른다 = 세울 것이 없다. 여기서 배너를 세우면 제보를 한 번도 안 한 사람에게도 뜬다.
    store.evaluateFeedbackReplyBanner()
    #expect(!store.showsFeedbackReplyBanner, "아는 답장이 없는데 배너를 세웠다")

    // (b) 처음 받은 답장 — 저장된 '봤음'이 없으므로 무조건 새 답장이다.
    store.feedbackReplyLatestAt = frbDate(frbServerAt)
    store.evaluateFeedbackReplyBanner()
    #expect(store.showsFeedbackReplyBanner, "첫 답장인데 배너가 안 섰다")

    // (c) 봤다고 표시하면 내려가고, 같은 값으로 다시 판정해도 다시 서지 않는다.
    store.markFeedbackReplyBannerSeen()
    #expect(!store.showsFeedbackReplyBanner)
    store.evaluateFeedbackReplyBanner()
    #expect(!store.showsFeedbackReplyBanner, "이미 본 답장에 배너가 다시 섰다 — 팝오버를 열 때마다 뜬다")

    // (d) **더 새로운** 답장이 오면 다시 선다. 소수초까지 비교하지 않으면 여기서 안 뜬다
    //     (서버 admin_note_at 은 clock_timestamp() 라 같은 초 안에 두 답장이 들어올 수 있다).
    store.feedbackReplyLatestAt = frbDate(frbServerAtNewer)
    store.evaluateFeedbackReplyBanner()
    #expect(store.showsFeedbackReplyBanner, "새 답장이 왔는데 배너가 안 섰다 — 소수초를 버리고 비교한다")

    // (e) 답장이 되레 사라지면(서버가 null) 서 있던 배너도 내린다 — 화면에 선 안내가 거짓이 되지 않게.
    store.feedbackReplyLatestAt = nil
    store.evaluateFeedbackReplyBanner()
    #expect(!store.showsFeedbackReplyBanner)
}

// MARK: - ② 적는 값은 서버 시각이지 이 맥의 시계가 아니다

@MainActor
@Test
func theSeenMarkRecordsTheServerClockUnderThisAccountsOwnKey() {
    let defaults = frbDefaults()
    let store = frbStore(host: "v0314-banner-key", defaults: defaults)
    let latest = frbDate(frbServerAt)
    store.feedbackReplyLatestAt = latest

    // 키 모양은 회고(`retroBannerShownWeekKeyForCurrentUser`)와 같다 — 앞자리 + 계정 id.
    #expect(store.feedbackReplySeenKeyForCurrentUser == "check.feedback.replySeenAt.\(frbUserID)",
            "키 모양이 계약과 다르다: \(store.feedbackReplySeenKeyForCurrentUser)")

    store.markFeedbackReplyBannerSeen()
    let written = defaults.string(forKey: "check.feedback.replySeenAt.\(frbUserID)")
    #expect(written != nil, "봤음을 적지 않았다 — 다음 팝오버에서 같은 답장이 또 뜬다")

    // ★ 적힌 값은 **서버가 준 시각**이다. Date() 를 적었다면 실행 시각(2026-09-12 03:04 과 한참 떨어진)이
    //   들어가 이 비교가 깨진다. 그게 이 픽스처를 먼 시각으로 고른 이유다.
    let parsed = ISO8601DateFormatter()
    parsed.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(parsed.date(from: written ?? "") == latest, "서버 시각이 아니라 다른 값을 적었다: \(written ?? "nil")")
    #expect(abs((parsed.date(from: written ?? "") ?? .distantPast).timeIntervalSinceNow) > 60,
            "이 맥의 '지금'을 적었다 — 서버가 앞서 있으면 그 사이 답장이 영영 안 뜬다")
}

@MainActor
@Test
func oneMacWithTwoLoginsDoesNotSwallowTheOtherAccountsReply() {
    // 회고가 실제로 겪고 고친 결함의 판박이: 전역 키 하나면 A 가 답장을 확인한 순간 같은 맥의 B 도
    // '봤음'이 돼 B 의 알림이 통째로 사라진다(로그아웃은 이 기록을 지우지 않는다).
    let defaults = frbDefaults()
    let latest = frbDate(frbServerAt)

    let accountA = frbStore(host: "v0314-banner-two-a", defaults: defaults, userID: frbUserID)
    accountA.feedbackReplyLatestAt = latest
    accountA.markFeedbackReplyBannerSeen()

    let accountB = frbStore(host: "v0314-banner-two-b", defaults: defaults, userID: frbOtherUserID)
    accountB.feedbackReplyLatestAt = latest
    accountB.evaluateFeedbackReplyBanner()
    #expect(accountB.showsFeedbackReplyBanner, "A 가 본 것으로 B 의 답장 알림까지 묻혔다")

    // 반대로 A 로 돌아오면 같은 답장이 다시 뜨지 않는다(기록을 지우지 않는 쪽의 이득).
    let accountAAgain = frbStore(host: "v0314-banner-two-a2", defaults: defaults, userID: frbUserID)
    accountAAgain.feedbackReplyLatestAt = latest
    accountAAgain.evaluateFeedbackReplyBanner()
    #expect(!accountAAgain.showsFeedbackReplyBanner, "본 답장이 재로그인으로 되살아났다")
}

@MainActor
@Test
func loggingOutTakesTheBannerDownButKeepsThePerAccountRecord() {
    let defaults = frbDefaults()
    let store = frbStore(host: "v0314-banner-logout", defaults: defaults)
    store.feedbackReplyLatestAt = frbDate(frbServerAt)
    store.evaluateFeedbackReplyBanner()
    #expect(store.showsFeedbackReplyBanner)
    store.markFeedbackReplyBannerSeen()

    store.signOut()
    #expect(!store.showsFeedbackReplyBanner, "로그아웃했는데 앞 사람의 '답장이 왔어요'가 남았다")
    #expect(store.feedbackReplyLatestAt == nil, "앞 계정의 답장 시각이 다음 계정으로 넘어간다")
    #expect(defaults.string(forKey: "check.feedback.replySeenAt.\(frbUserID)") != nil,
            "계정별 기록까지 지웠다 — 되돌아오면 본 답장이 또 뜬다")
}

// MARK: - 제보 패널을 열면 본 것으로 친다

@MainActor
@Test
func lookingAtTheFeedbackPanelCountsAsHavingSeenTheReply() {
    let defaults = frbDefaults()
    let store = frbStore(host: "v0314-banner-panel", defaults: defaults)
    store.feedbackReplyLatestAt = frbDate(frbServerAt)
    store.evaluateFeedbackReplyBanner()
    #expect(store.showsFeedbackReplyBanner)

    // 답장 판은 이 화면 안에 이미 그려져 있다(갈래 B) — 배너가 겹치면 중복이고 창 높이만 밀어 올린다.
    store.isFeedbackPanelVisible = true
    store.evaluateFeedbackReplyBanner()
    #expect(!store.showsFeedbackReplyBanner, "답장을 보고 있는데 그 위에 '답장이 왔어요'가 겹쳤다")
    #expect(defaults.string(forKey: "check.feedback.replySeenAt.\(frbUserID)") != nil,
            "패널을 보고 나왔는데 다음 팝오버에서 같은 답장이 또 뜬다")
}

@MainActor
@Test
func theViewMarksTheReplySeenWhenTheFeedbackPanelAppears() {
    // 위 갈래는 '조회가 패널이 떠 있는 동안 돌아온' 경우를 받고, 이 갈래는 사람이 직접 연 경우를 받는다.
    // 들어오는 문은 둘(레일 [제보] · 배너 [보기])인데 그려지는 자리는 하나라, 훅도 그 자리에 하나만 건다.
    //
    // ⚠️ 소스 계약으로 재는 이유: `onAppear` 는 호스팅이 있어야 불린다(ImageRenderer 는 안 부른다).
    //    주석은 걷어내고 본다 — 안 그러면 설명을 지워야만 초록이 되는 테스트가 된다.
    let source = try! String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check/CheckMenuView.swift"),
        encoding: .utf8
    )
    let code = source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let slash = line.range(of: "//") else { return String(line) }
            return String(line[line.startIndex..<slash.lowerBound])
        }
        .joined(separator: "\n")

    #expect(code.contains("CheckFeedbackView("), "전제가 깨졌다 — 제보 패널을 그리는 자리를 못 찾았다")
    guard let panel = code.range(of: "CheckFeedbackView(") else { return }
    let tail = code[panel.lowerBound...].prefix(700)
    #expect(tail.contains("markFeedbackReplyBannerSeen"),
            "제보 패널을 열어도 '봤음'이 안 찍힌다 — 답장을 읽고 나와도 배너가 계속 뜬다")
}

// MARK: - ③ 여는 순간 1회, 폴링 금지

@MainActor
@Test
func theReplyBadgeIsAskedOncePerPopoverOpeningAndNeverPolled() async {
    let host = "v0314-banner-once"
    let store = frbStore(host: host)
    store.isMenuPresented = false
    FeedbackURLProtocol.set(.init(status: 200, body: "\"\(frbServerAt)\""), host: host, path: frbLatestPath)

    store.setMenuPresented(true)
    await frbWait { store.showsFeedbackReplyBanner }
    #expect(FeedbackURLProtocol.count(host: host, path: frbLatestPath) == 1,
            "여는 순간 1회가 아니다: \(FeedbackURLProtocol.count(host: host, path: frbLatestPath))회")
    #expect(store.showsFeedbackReplyBanner, "서버가 새 답장을 줬는데 배너가 안 섰다")

    // 인자 없는 RPC 규약: PostgREST 는 **본문의 키 집합**으로 함수를 고르므로 `{}` 여야 한다.
    #expect(FeedbackURLProtocol.sentBodies(host: host, path: frbLatestPath).first == "{}")

    // 티커가 도는 동안(매초 displayNow 갱신) 추가 조회가 없어야 한다 — 폴링 금지.
    for i in 1...5 {
        store.displayNow = store.displayNow.addingTimeInterval(Double(i))
    }
    try? await Task.sleep(for: .milliseconds(60))
    #expect(FeedbackURLProtocol.count(host: host, path: frbLatestPath) == 1,
            "초침이 돌자 조회가 따라 늘었다 — 폴링에 걸렸다")

    // 창을 닫았다 여는 것은 '사람이 화면을 보는 시점'이라 한 번 더 묻는다.
    store.setMenuPresented(false)
    store.setMenuPresented(true)
    await frbWait { FeedbackURLProtocol.count(host: host, path: frbLatestPath) == 2 }
    #expect(FeedbackURLProtocol.count(host: host, path: frbLatestPath) == 2,
            "다시 열었는데 안 물었다 — 닫아 둔 사이에 온 답장을 영영 모른다")
}

@MainActor
@Test
func aServerWithoutTheReplyRpcYetIsSilentNotBroken() async {
    // 브루 배포가 db push 보다 앞선 창에서는 이 함수가 **없는 것이 정상**이다(PGRST202).
    // 그 며칠 동안 배너가 그냥 안 뜨면 된다 — 여기서 실패로 칠하면 모두가 빨간 화면을 보고
    // '앱이 고장 났다'고 제보한다. 제보 화면에서.
    let host = "v0314-banner-no-rpc"
    let store = frbStore(host: host)
    store.isMenuPresented = false
    FeedbackURLProtocol.set(
        .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.feedback_reply_latest without parameters in the schema cache"}"#),
        host: host,
        path: frbLatestPath
    )

    store.setMenuPresented(true)
    await frbWait { FeedbackURLProtocol.count(host: host, path: frbLatestPath) >= 1 }
    try? await Task.sleep(for: .milliseconds(80))

    #expect(!store.showsFeedbackReplyBanner, "서버에 함수도 없는데 배너를 세웠다")
    #expect(store.feedbackReplyLatestAt == nil, "못 받은 값을 지어냈다")
    #expect(store.feedbackNotice == nil, "배너 하나 때문에 화면에 실패 문구를 띄웠다")
    #expect(!store.feedbackFailed, "배너 조회 실패가 제보 목록을 실패로 칠했다")
    #expect(store.syncMessage != "다시 로그인 필요", "스키마 부재를 세션 만료로 오해했다")
}

@MainActor
@Test
func aFailedLookupNeverTakesDownABannerThatIsAlreadyStanding() async {
    // 못 물어봤다는 사실은 "답장이 없다"는 답이 아니다. 여기서 내리면 Wi-Fi 가 끊긴 팝오버 한 번으로
    // 읽지 않은 답장 알림이 사라진다.
    let host = "v0314-banner-keep"
    let store = frbStore(host: host)
    store.feedbackReplyLatestAt = frbDate(frbServerAt)
    store.evaluateFeedbackReplyBanner()
    #expect(store.showsFeedbackReplyBanner)

    FeedbackURLProtocol.set(.init(status: 500, body: #"{"message":"boom"}"#), host: host, path: frbLatestPath)
    store.refreshFeedbackReplyBadge()
    await frbWait { FeedbackURLProtocol.count(host: host, path: frbLatestPath) >= 1 }
    try? await Task.sleep(for: .milliseconds(80))
    #expect(store.showsFeedbackReplyBanner, "조회 한 번 실패했다고 읽지 않은 답장 알림을 걷어냈다")
}

// MARK: - ④ 배너는 동시에 하나 · 우선순위 · 창 높이 상한

@MainActor
@Test
func theReplyBannerLosesToTheRetroBannerAndBeatsTheUpdateBanner() throws {
    // 배너는 **동시에 하나만** 그린다(창 위 모서리가 고정이라 겹쳐 쌓이면 푸터가 화면 밖으로 나간다).
    // 그래서 우선순위는 높이로 실측한다 — 같은 높이면 같은 배너 하나가 그려진 것이다.
    let now = Date()
    func store(host: String) -> WorkTimerStore { frbStore(host: host, now: now) }

    let plain = try #require(frbRenderedHeight(CheckMenuView(store: store(host: "v0314-h-plain"))))

    let replyOnly = store(host: "v0314-h-reply")
    replyOnly.showsFeedbackReplyBanner = true
    let withReply = try #require(frbRenderedHeight(CheckMenuView(store: replyOnly)))
    #expect(withReply > plain, "답장 배너를 세웠는데 창이 그대로다 — 아무것도 안 그렸다")

    // (가) 회고가 이긴다. ⚠️ 두 배너는 **같은 InlineActionBanner 라 높이가 같다** — 높이만 보면
    //      '답장 하나만 그렸다'도 통과한다(기준선이 같은 입력이면 그 테스트는 영원히 초록이다).
    //      그래서 픽셀로 본다: 문구와 아이콘이 달라 회고 화면과 답장 화면은 서로 다른 그림이다.
    let retroOnly = store(host: "v0314-h-retro")
    retroOnly.showsRetroBanner = true
    let retroInk = try frbRenderedFingerprint(CheckMenuView(store: retroOnly))
    let replyInk = try frbRenderedFingerprint(CheckMenuView(store: replyOnly))
    #expect(retroInk != replyInk, "전제가 깨졌다 — 회고 배너와 답장 배너가 같은 그림이라 아무것도 못 가른다")

    let both = store(host: "v0314-h-both")
    both.showsRetroBanner = true
    both.showsFeedbackReplyBanner = true
    let bothInk = try frbRenderedFingerprint(CheckMenuView(store: both))
    #expect(bothInk == retroInk,
            "둘 다 자격이 있을 때 그려진 그림이 회고가 아니다 — 우선순위가 뒤집혔거나 둘이 겹쳤다 (둘 다: \(bothInk) / 회고만: \(retroInk) / 답장만: \(replyInk))")
    let withRetro = try #require(frbRenderedHeight(CheckMenuView(store: retroOnly)))
    #expect(try #require(frbRenderedHeight(CheckMenuView(store: both))) == withRetro,
            "회고와 답장이 함께 그려졌다 — 창이 상한을 넘는 길이 열렸다")

    // (나) 답장이 새 버전 안내를 이긴다. 업데이트 배너(81pt)가 답장 배너(54pt)보다 높으므로,
    //      둘을 함께 세웠을 때 높이가 '답장만'과 같다는 것은 답장이 그 자리를 가져갔다는 뜻이다.
    let updateOnly = store(host: "v0314-h-update")
    let withUpdate = try #require(frbRenderedHeight(CheckMenuView(store: updateOnly, previewUpdateBanner: true)))
    #expect(withUpdate > withReply, "전제가 깨졌다 — 업데이트 배너가 답장 배너보다 높지 않다")

    let replyAndUpdate = store(host: "v0314-h-reply-update")
    replyAndUpdate.showsFeedbackReplyBanner = true
    let withReplyAndUpdate = try #require(
        frbRenderedHeight(CheckMenuView(store: replyAndUpdate, previewUpdateBanner: true))
    )
    #expect(withReplyAndUpdate == withReply, "새 버전 안내가 답장을 밀어냈다 — 사람이 기다리는 쪽이 뒤로 갔다")

    // (다) 12시간 확인이 전부를 이긴다(무응답 30분이면 자동 마감이라 가장 급하다).
    let longSession = store(host: "v0314-h-long")
    longSession.showsFeedbackReplyBanner = true
    longSession.startedAt = now.addingTimeInterval(-10)
    longSession.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
    longSession.isLongSessionPromptActive = true
    let longOnly = store(host: "v0314-h-long-only")
    longOnly.startedAt = now.addingTimeInterval(-10)
    longOnly.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
    longOnly.isLongSessionPromptActive = true
    #expect(frbRenderedHeight(CheckMenuView(store: longSession)) == frbRenderedHeight(CheckMenuView(store: longOnly)),
            "12시간 확인 위에 답장 배너가 겹쳤다")
}

@MainActor
@Test
func thePopoverStaysWithinTheHeightCapWithTheReplyBanner() throws {
    // 창 높이 상한 700pt — 넘으면 13" 맥북에서 푸터(로그아웃/앱 종료)가 화면 밖으로 나간다.
    let now = Date()
    let store = frbStore(host: "v0314-cap", now: now)
    store.teamMembers = (0..<8).map { i in
        TeamMemberStatus(
            id: "bbbbbbbb-0000-0000-0000-\(String(format: "%012d", i))",
            name: "멤버\(i)",
            status: .offWork,
            updatedAt: nil,
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 3_600
        )
    }
    store.showsFeedbackReplyBanner = true
    let pixels = try #require(frbRenderedHeight(CheckMenuView(store: store)))
    #expect(Double(pixels) / 2.0 <= 700.0, "답장 배너가 얹힌 팝오버가 700pt 상한을 넘었다: \(Double(pixels) / 2.0)pt")
}

// MARK: - ★ 배너 하나 때문에 팝오버가 매초 다시 그려지면 안 된다

@MainActor
@Test
func theReplyBannerDoesNotMakeTheWholePopoverRedrawEverySecond() {
    // 이 화면의 대표 회귀: `topBanner` 가 시각 의존 판정을 직접 부르면(넘길 수 있는 시각은 매초 갱신되는
    // displayNow 뿐이다) body 최상단이 그것을 관찰 등록해 팝오버 **전체** 서브트리가 매초 무효화된다.
    // 그래서 답장 판정은 스토어가 끝내고 뷰는 결과 깃발만 읽는다 — 그 구조를 여기서 실측한다.
    let now = Date()
    let store = frbStore(host: "v0314-observe", now: now)
    store.feedbackReplyLatestAt = frbDate(frbServerAt)
    let view = CheckMenuView(store: store)

    let invalidated = FRBObservationFlag()
    withObservationTracking {
        _ = view.body
    } onChange: {
        invalidated.value = true
    }

    store.displayNow = now.addingTimeInterval(1)
    #expect(!invalidated.value, "초침 한 틱에 팝오버 전체가 무효화됐다 — 판정을 뷰에서 직접 불렀다")

    // 반대로 **배너 상태가 실제로 바뀌면** 반드시 다시 그려져야 한다(추적이 살아 있다는 증거이기도 하다).
    store.showsFeedbackReplyBanner = true
    #expect(invalidated.value, "배너가 섰는데 화면이 안 바뀐다 — 깃발이 관찰 밖에 있다")
}
