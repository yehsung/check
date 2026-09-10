import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// 제보(버그·요청) — 순수 경계 · 서버 어휘 · 스토어 왕복 · 패널 계약 · 렌더 스냅샷.
//
// **v0.2.50 에 표면이 바뀌었다**(파일 이름은 이력이라 그대로 둔다). 사용자 지시 2026-09-10:
//   "제보 창도 쓸데없이 너무 넓어. 제보창도 팝오버 창 안에서만 뜨게 하면서. 배치도 좀 효율적으로 해줘."
//   "제보창에서 새로고침 버튼 없어도 될 듯."
// 별도 창(520×560)이 사라지고 팝오버 하위 패널(폭 292pt)이 됐다. 그래서 창 스타일마스크·지연 생성·
// 로그아웃 시 창 닫기를 재던 세 테스트는 **패널 계약**으로 갈아 끼웠고, 렌더 스냅샷은 패널 하나가 아니라
// **팝오버 통째로** 그린다 — 이 작업의 최악 결함이 창 높이 회귀(700pt 상한, 푸터 잘림)이기 때문이다.
//
// ★ 이 파일의 픽스처 본문은 전부 **합성 문자열**이다("샘플 본문 1" 같은). 실제 제보를 픽스처로 옮겨 오지 마라 —
//   테스트 파일은 퍼블릭 저장소에 남고, 사용자가 쓴 글은 남에게 보여 주려고 쓴 것이 아니다.
//
// 네트워크는 아래 `FeedbackURLProtocol`(테스트별 고유 호스트)로 격리한다. 공용 `URLProtocolStub` 을 쓰지 않는 이유는
// 그 파일이 이 작업의 소유가 아니어서다 — 404/400 같은 **실패 상태코드**를 경로별로 심을 손잡이가 필요하다.

private let fbUserID = "00000000-0000-0000-0000-000000000002"
private let fbOtherID = "00000000-0000-0000-0000-000000000003"

// MARK: - 격리된 네트워크

/// 호스트 × 경로별로 (상태코드, 본문)을 심어 주는 URLProtocol. 병렬 테스트가 서로 간섭하지 않게
/// 각 테스트가 고유 호스트를 쓴다(TokenBoardURLProtocol 과 같은 규약 + 상태코드).
final class FeedbackURLProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        init(status: Int = 200, body: String = "[]") {
            self.status = status
            self.body = body
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var replies: [String: [String: Reply]] = [:]
    private nonisolated(unsafe) static var bodies: [String: [String: [String]]] = [:]
    private nonisolated(unsafe) static var counts: [String: [String: Int]] = [:]

    static func set(_ reply: Reply, host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host, default: [:]][path] = reply
    }

    static func reset(host: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host] = nil
        bodies[host] = nil
        counts[host] = nil
    }

    static func count(host: String, path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[host]?[path] ?? 0
    }

    /// 이 호스트·경로로 나간 요청 본문들(순서대로).
    static func sentBodies(host: String, path: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return bodies[host]?[path] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let text = Self.bodyText(from: request)
        Self.lock.lock()
        Self.counts[host, default: [:]][path, default: 0] += 1
        Self.bodies[host, default: [:]][path, default: []].append(text)
        let reply = Self.replies[host]?[path] ?? Reply()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private func fbDefaults() -> UserDefaults {
    let suite = "v0248-feedback-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 스텁 네트워크에 물린 스토어. `signedIn: false` 면 세션 없는 스토어(no-op 검증용).
@MainActor
private func fbStore(host: String, signedIn: Bool = true, admin: Bool = false) -> WorkTimerStore {
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: fbDefaults()
    )
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: fbUserID)
    }
    store.ultraUnlimited = admin
    // 버전은 고정 주입 — 스냅샷과 요청 본문 단언이 이 맥의 번들에 흔들리지 않게.
    store.appVersionProvider = { AppVersionReport(build: 58, version: "0.2.48") }
    store.osVersionProvider = { "15.6" }
    return store
}

/// 200×5ms 폴링(≈1초 상한) — 비동기 스토어 반영 대기(UltraPokeTests 관용구).
@MainActor
private func fbWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 합성 제보 한 건. **실제 제보 본문을 여기 옮기지 마라.**
private func fbReport(
    id: String,
    kind: FeedbackKind = .bug,
    status: FeedbackStatus = .open,
    owner: String? = fbUserID,
    body: String = "샘플 본문",
    createdAt: Date = Date(timeIntervalSince1970: 1_789_000_000)
) -> FeedbackReport {
    FeedbackReport(
        id: id,
        userID: owner,
        kind: kind,
        body: body,
        status: status,
        adminNote: nil,
        appVersion: "0.2.48 (58)",
        osVersion: "15.6",
        createdAt: createdAt,
        updatedAt: createdAt,
        authorName: owner == fbUserID ? "나야" : "동료",
        authorAvatarURL: nil
    )
}

// MARK: - 순수: 본문 길이 경계

@Test
func bodyLengthBoundariesMatchTheServerConstraint() {
    // 서버 submit_feedback 은 1~1000자를 받는다. 클라 게이트가 그보다 관대하면 사용자는 다 쓰고 나서야 거절당하고,
    // 더 엄격하면 서버가 받아 주는 글을 우리가 막는다 — 경계 넷을 못 박는다.
    #expect(!FeedbackComposer.isSendable(""), "0자를 보낼 수 있다")
    #expect(!FeedbackComposer.isSendable("   \n\t "), "공백만 친 글을 보낼 수 있다")
    #expect(FeedbackComposer.isSendable("가"), "1자를 못 보낸다")
    #expect(FeedbackComposer.isSendable(String(repeating: "가", count: 1000)), "1000자를 못 보낸다")
    #expect(!FeedbackComposer.isSendable(String(repeating: "가", count: 1001)), "1001자를 보낼 수 있다")
    // 앞뒤 공백은 경계 판정에 들어가지 않는다(정규화 뒤에 센다) — 1000자 글에 개행 하나가 붙었다고 막히면 안 된다.
    #expect(FeedbackComposer.isSendable("\n" + String(repeating: "가", count: 1000) + "  "))
}

@Test
func theCounterCountsWhatTheUserTypedAndWarnsNearTheLimit() {
    // 카운터는 **원문**을 센다(사람이 친 그대로 보여야 한다). 전송 판정만 공백을 걷어낸 값을 쓴다.
    #expect(FeedbackComposer.counterText("") == "0/1000")
    #expect(FeedbackComposer.counterText("  ") == "2/1000")
    #expect(FeedbackComposer.counterText(String(repeating: "가", count: 901)) == "901/1000")
    #expect(!FeedbackComposer.isCounterWarning(String(repeating: "가", count: 900)), "900자에서 벌써 경고색이다")
    #expect(FeedbackComposer.isCounterWarning(String(repeating: "가", count: 901)), "901자인데 경고색이 아니다")
}

@Test
func adminNoteIsTrimmedClampedAndNilWhenEmpty() {
    // 빈 메모는 nil 로 보낸다 — 빈 문자열을 보내면 서버가 기존 메모를 지운다.
    #expect(FeedbackComposer.normalizedNote("") == nil)
    #expect(FeedbackComposer.normalizedNote("   ") == nil)
    #expect(FeedbackComposer.normalizedNote(" 확인함 ") == "확인함")
    #expect(FeedbackComposer.normalizedNote(String(repeating: "가", count: 600))?.count == 500, "메모 상한 500자를 넘겨 보낸다")
}

// MARK: - 순수: 서버 어휘

@Test
func kindRawValuesAreExactlyTheServerCheckVocabulary() {
    // 서버 `feedback.kind` check 제약과 **글자까지 같아야** 한다. 다르면 submit 이 23514 로 죽는데,
    // 사용자에게는 "보내지 못했어요"로만 보여서 원인을 추적할 수 없다.
    #expect(FeedbackKind.bug.rawValue == "bug")
    #expect(FeedbackKind.request.rawValue == "request")
    #expect(Set(FeedbackKind.allCases.map(\.rawValue)) == ["bug", "request"], "종류가 둘이 아니다 — 서버 제약과 갈렸다")
    #expect(FeedbackKind.bug.label == "버그" && FeedbackKind.request.label == "요청")
    #expect(FeedbackKind.bug.isDanger && !FeedbackKind.request.isDanger, "버그 배지가 경고색이 아니다")
}

@Test
func statusRawValuesRoundTripAndUnknownValuesAreNotFoldedIntoOpen() {
    // ★ 이 저장소가 이미 한 번 물린 함정(열거값 확장엔 능력 협상): 서버가 상태를 하나 더했을 때
    //   모르는 값을 .open 으로 접으면 '처리된 제보'가 '미해결'로 오배달되고 아무도 그 사실을 모른다.
    for status in FeedbackStatus.known {
        #expect(FeedbackStatus(rawValue: status.rawValue) == status, "\(status.rawValue) 왕복이 깨졌다")
    }
    // ★ 서버 어휘 그대로다(feedback_reports.status check 제약 — 20260910120000_feedback_reports.sql:88).
    //   케이스 이름(inProgress · held)은 화면 라벨(진행 · 보류)을 따르고, 이 문자열은 **서버**를 따른다.
    //   여기를 이름 쪽으로 맞추면 set_feedback_status 가 FEEDBACK_BAD_STATUS 로 거절한다.
    #expect(FeedbackStatus.known.map(\.rawValue) == ["open", "doing", "done", "wontfix"])
    let unknown = FeedbackStatus(rawValue: "escalated")
    #expect(unknown == .other("escalated"), "모르는 상태를 아는 값으로 접었다")
    #expect(!unknown.isOpen, "모르는 상태가 '미해결'로 셰어졌다 — 관리자가 처리된 건을 다시 처리한다")
    #expect(unknown.label == "escalated", "모르는 상태를 사람 말로 지어냈다")
    #expect(unknown.rawValue == "escalated", "원문을 잃었다 — 되돌려 보낼 수 없다")
}

@Test
func statusLabelsAndTransitionsAreTheOnesTheScreenPromises() {
    #expect(FeedbackStatus.open.label == "미해결")
    #expect(FeedbackStatus.inProgress.label == "진행")
    #expect(FeedbackStatus.done.label == "완료")
    #expect(FeedbackStatus.held.label == "보류")
    // ★ 되돌리기가 **있어야 한다**(v0.2.48 수정). [완료]를 잘못 누르면 앱 안에서 되돌릴 길이 없었고,
    //   제보는 지워지지도 않으므로(서버에 delete 경로가 없다) 그 오조작이 영구였다 — 레일 배지의
    //   미해결 건수도 그만큼 영영 줄었다.
    #expect(FeedbackStatus.transitions == [.open, .inProgress, .done, .held])
    #expect(FeedbackStatus.transitions.contains(.open), "[완료]를 잘못 눌러도 되돌릴 길이 없다")
    // 전이 목록은 **서버가 받는 값**을 넘어설 수 없다: set_feedback_status 는
    // p_status in ('open','doing','done','wontfix') 넷만 통과시키고 나머지는 FEEDBACK_BAD_STATUS 다
    // (20260910120000_feedback_reports.sql:329). 여기가 넓어지면 버튼을 누를 때마다 실패 한 줄만 뜬다.
    #expect(Set(FeedbackStatus.transitions.map(\.rawValue)) == ["open", "doing", "done", "wontfix"])
    #expect(FeedbackStatus.transitions.allSatisfy { FeedbackStatus.known.contains($0) }, "서버가 모르는 값을 버튼으로 만들었다")
    // 필터 칩과 **같은 어휘·같은 순서**다 — 한 화면에서 같은 상태가 두 순서로 서면 관리자가 매번 다시 읽는다.
    #expect(FeedbackStatus.transitions == FeedbackStatus.known)
    // 미해결 판정은 한 곳이다 — 이게 갈리면 필터·배지·정렬이 서로 다른 말을 한다.
    #expect(FeedbackStatus.open.isOpen)
    #expect(![FeedbackStatus.inProgress, .done, .held].contains { $0.isOpen })
}

// MARK: - 순수: 색 대비(칩 글자가 읽히는가)

/// sRGB 상대 휘도(WCAG 2.x). 눈으로 "읽히나?"를 다투지 않으려고 숫자로 붙들어 둔다.
private func fbLuminance(_ color: NSColor) -> Double {
    let c = color.usingColorSpace(.sRGB) ?? color
    func channel(_ value: CGFloat) -> Double {
        let v = Double(value)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
}

private func fbContrast(_ lhs: NSColor, _ rhs: NSColor) -> Double {
    let a = fbLuminance(lhs), b = fbLuminance(rhs)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// `color` 를 `alpha` 로 `over` 위에 합성한 결과(칩 채움은 언제나 반투명이라 실제로 눈에 닿는 색은 이 값이다).
private func fbComposite(_ color: NSColor, alpha: Double, over background: NSColor) -> NSColor {
    let top = color.usingColorSpace(.sRGB) ?? color
    let bottom = background.usingColorSpace(.sRGB) ?? background
    func mix(_ t: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat(alpha) * t + CGFloat(1 - alpha) * b }
    return NSColor(
        srgbRed: mix(top.redComponent, bottom.redComponent),
        green: mix(top.greenComponent, bottom.greenComponent),
        blue: mix(top.blueComponent, bottom.blueComponent),
        alpha: 1
    )
}

@MainActor
@Test
func theOpenStatusChipIsActuallyReadable() {
    // ★ 실측 지적(2026-09-10): 미해결 칩(#DDA04D)에 흰 글자 = **2.28:1**. 큰 글자 기준(3:1)에도 못 미치는데
    //   실제로는 10pt 굵은 글자다. 목록에서 **가장 중요한 칩 하나만** 안 읽히고 있었다.
    //
    // 이 칩만 글자를 뒤집는 이유(다른 칩 규약은 그대로 둔다): 나머지 채움색은 accent(파랑)·danger(빨강)이라
    // 흰 글자가 읽히는 쪽이다. 규약은 "칩 글자는 흰색"이 아니라 "채움색에서 읽히는 극을 고른다"이고,
    // 밝은 호박색은 그 규약이 검은 극을 가리키는 유일한 자리다.
    //
    // 배경은 두 극단으로 재서 값이 배경 추정에 흔들리지 않게 한다(카드는 그라디언트 위의 반투명 판이다).
    let backgrounds: [NSColor] = [
        .black,
        NSColor(CheckTheme.panelElevated)
    ]
    let ink = NSColor(FeedbackStatusChip.openInk)
    for background in backgrounds {
        let fill = fbComposite(NSColor(CheckTheme.pending), alpha: 0.85, over: background)
        let dark = fbContrast(ink, fill)
        let white = fbContrast(.white, fill)
        #expect(dark >= 6.0, "미해결 칩 글자가 안 읽힌다(\(String(format: "%.2f", dark)):1)")
        #expect(dark > white, "흰 글자가 더 읽히는데 어두운 글자를 쓰고 있다")
        // 되돌리기 방지: 흰 글자는 여기서 언제나 실패한다는 사실 자체를 못 박는다.
        #expect(white < 3.0, "흰 글자가 3:1 을 넘었다 — pending 색이 바뀌었으면 이 판단을 다시 하라")
    }
    // 채워지지 않은 칩(테두리만)은 secondaryText 로 카드 위에 선다 — 그쪽은 원래 규약대로 둔다.
    // **글자색도 반투명이라 합성해서 재야 한다**(흰색 68%). 안 하면 이 단언은 늘 통과하는 장식이 된다.
    let card = fbComposite(.black, alpha: 0.20, over: NSColor(CheckTheme.panel))
    let secondaryInk = fbComposite(.white, alpha: 0.68, over: card)
    #expect(fbContrast(secondaryInk, card) >= 4.5, "채우지 않은 상태 칩 글자가 안 읽힌다")
}

// MARK: - 순수: 문구가 내부 코드를 흘리지 않는다

@Test
func failureNoticesNeverLeakServerExceptionNames() {
    // 서버가 던지는 것은 `FEEDBACK_RATE_LIMIT` / `FEEDBACK_FORBIDDEN` 이고, 공용 매핑은 그것을
    // `.authMessage(원문)` 으로 올린다. 공용 매퍼(authMessage(for:fallback:))는 그 원문을 **그대로** 돌려주므로
    // 제보 경로는 자기 매퍼를 쓴다 — 그 사실이 깨지면 화면에 영문 대문자 상수가 뜬다.
    let rate = FeedbackFailure.notice(
        for: SupabaseWorkServiceError.authMessage("FEEDBACK_RATE_LIMIT"),
        fallback: FeedbackText.sendFailed
    )
    #expect(rate == FeedbackText.rateLimited)
    let forbidden = FeedbackFailure.notice(
        for: SupabaseWorkServiceError.authMessage("FEEDBACK_FORBIDDEN"),
        fallback: FeedbackText.statusFailed
    )
    #expect(forbidden == FeedbackText.forbidden)
    // 모르는 서버 예외는 **원문을 버린다**(fallback). 여기서 원문을 흘리면 다음에 서버가 예외를 하나 더할 때마다
    // 새 영문 상수가 사용자 화면에 뜬다.
    let unknown = FeedbackFailure.notice(
        for: SupabaseWorkServiceError.authMessage("SOME_NEW_SERVER_CODE"),
        fallback: FeedbackText.sendFailed
    )
    #expect(unknown == FeedbackText.sendFailed, "모르는 서버 예외 원문이 화면으로 샜다")
    // 429(게이트웨이 제한)도 같은 뜻이라 같은 문장.
    #expect(FeedbackFailure.notice(for: SupabaseWorkServiceError.rateLimited(retryAfterSeconds: 30), fallback: "x") == FeedbackText.rateLimited)

    // 사용자에게 보이는 문장 전체에 내부 어휘가 없다.
    for text in [
        FeedbackText.rateLimited, FeedbackText.forbidden, FeedbackText.sendFailed,
        FeedbackText.statusFailed, FeedbackText.failed, FeedbackText.sendSchemaMissing
    ] {
        let upper = text.uppercased()
        #expect(!upper.contains("FEEDBACK"), "화면 문구에 내부 코드가 들어 있다: \(text)")
        #expect(!upper.contains("RATE_LIMIT") && !upper.contains("FORBIDDEN"), "화면 문구에 서버 예외 이름이 들어 있다: \(text)")
        #expect(!text.contains("_"), "화면 문구에 코드 모양의 밑줄이 있다: \(text)")
    }
}

@Test
func theAutoAttachNoticeSaysExactlyWhatGetsSent() {
    // 몰래 보내지 않는다 — 실어 보내는 것과 밝히는 문장이 같은 값에서 나와야 한다.
    let notice = FeedbackText.autoAttachNotice(appVersion: "0.2.48", build: 58, osVersion: "15.6")
    #expect(notice.contains("0.2.48") && notice.contains("58") && notice.contains("15.6"))
    #expect(notice.contains("함께 전송"), "무엇을 하는지 말하지 않는다")
    // 버전을 못 읽는 개발 빌드에서도 문장이 깨지지 않는다(모르면 침묵한다).
    let unknown = FeedbackText.autoAttachNotice(appVersion: "", build: nil, osVersion: "15.6")
    #expect(unknown.hasPrefix("앱 ·"), "버전 미상일 때 문장이 어그러진다: \(unknown)")
    // 요청 본문에 실리는 값도 같은 규약이다.
    #expect(FeedbackText.appVersionField(AppVersionReport(build: 58, version: "0.2.48")) == "0.2.48 (58)")
    #expect(FeedbackText.appVersionField(nil) == "", "버전을 모르는데 지어낸 값을 보낸다")
}

@Test
func osVersionTextDropsTheTrailingZeroPatch() {
    #expect(OSVersionReport.text(OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0)) == "15.6")
    #expect(OSVersionReport.text(OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 1)) == "15.6.1")
}

@Test
func relativeAgeTextCoversDaysNotJustHours() {
    // 제보는 며칠 묵는 표면이다 — "72시간 전"은 사람이 읽는 단위가 아니다.
    let now = Date(timeIntervalSince1970: 1_789_000_000)
    #expect(FeedbackText.ageText(now.addingTimeInterval(-30), now: now) == "방금")
    #expect(FeedbackText.ageText(now.addingTimeInterval(-600), now: now) == "10분 전")
    #expect(FeedbackText.ageText(now.addingTimeInterval(-7200), now: now) == "2시간 전")
    #expect(FeedbackText.ageText(now.addingTimeInterval(-3 * 86_400), now: now) == "3일 전")
    #expect(FeedbackText.ageText(nil, now: now) == "", "시각을 모르는데 지어낸 문구를 쓴다")
}

// MARK: - 순수: 빈 목록 문구 3분기

@Test
func emptyMessagesSeparateLoadingFromFailureFromReallyEmpty() {
    // 이 저장소가 실제로 겪은 회귀: 실패했는데 "없어요"라고 단정하는 화면(그 옆에 [다시 시도]가 함께 떴다).
    #expect(FeedbackEmptyMessage.inbox(loaded: false, failed: false).text == FeedbackText.loading)
    #expect(FeedbackEmptyMessage.inbox(loaded: false, failed: true).text == FeedbackText.failed)
    #expect(FeedbackEmptyMessage.inbox(loaded: true, failed: false).text == FeedbackText.inboxEmpty)
    // 한 번 성공한 뒤의 실패는 '없어요'가 아니라 이미 받은 목록을 유지한 채의 실패다 —
    // 빈 자리 문구로는 단정하지 않는다.
    #expect(FeedbackEmptyMessage.inbox(loaded: true, failed: true).text == FeedbackText.inboxEmpty)
    #expect(FeedbackEmptyMessage.mine(loaded: false, failed: false).text == FeedbackText.loading)
    #expect(FeedbackEmptyMessage.mine(loaded: true, failed: false).text == FeedbackText.mineEmpty)
    // 로딩·실패에는 보조 줄을 붙이지 않는다 — 그 두 상태에서 할 말은 [다시 시도] 버튼이 이미 한다.
    #expect(FeedbackEmptyMessage.inbox(loaded: false, failed: false).hint == nil)
    #expect(FeedbackEmptyMessage.inbox(loaded: false, failed: true).hint == nil)
}

@Test
func aFilteredEmptyListNeverSpeaksLikeAnEmptyInbox() {
    // ★ v0.2.48 결함: 필터를 걸어 아무것도 안 남은 화면과 진짜 빈 화면이 **같은 문장**이었다.
    //   필터 칩 다섯이 그대로 떠 있는 채로 "받은 제보가 없어요"만 뜨니, 관리자는 "필터를 잘못 걸었나"와
    //   "아직 아무도 안 보냈다"를 화면에서 가를 수 없었다(리그 페이지가 이미 이 규약을 세워 뒀다).
    let filtered = FeedbackEmptyMessage.inbox(loaded: true, failed: false, filter: .done, unfilteredCount: 4)
    #expect(filtered.text == "완료 제보가 없어요", "필터가 걸린 빈 목록이 진짜 빈 목록처럼 말한다: \(filtered.text)")
    #expect(filtered.text != FeedbackText.inboxEmpty)
    // 빠져나갈 길을 말한다. 화면에 실제로 있는 칩 이름(전체)을 그대로 부른다 — 없는 버튼을 말하면 안 된다.
    #expect(
        filtered.hint?.contains(FeedbackText.filterAll) == true,
        "필터를 푸는 방법을 말하지 않는다: \(filtered.hint ?? "nil")"
    )

    // 원본이 비어 있으면 필터를 탓할 수 없다 — 필터를 걸었어도 진짜 빈 목록 문구다.
    let reallyEmpty = FeedbackEmptyMessage.inbox(loaded: true, failed: false, filter: .done, unfilteredCount: 0)
    #expect(reallyEmpty.text == FeedbackText.inboxEmpty)
    #expect(reallyEmpty.hint == FeedbackText.inboxEmptyHint, "진짜 빈 목록에도 '앞으로 여기 쌓인다'는 한 줄이 있어야 한다")
    // 필터가 없으면 언제나 진짜 빈 목록이다.
    #expect(FeedbackEmptyMessage.inbox(loaded: true, failed: false, filter: nil, unfilteredCount: 9).text == FeedbackText.inboxEmpty)
    // 실패는 필터보다 앞선다 — 못 불러온 화면에 "필터를 푸세요"라고 말하면 안 된다.
    #expect(FeedbackEmptyMessage.inbox(loaded: false, failed: true, filter: .open, unfilteredCount: 3).text == FeedbackText.failed)
    // 네 상태 어느 것으로 걸어도 문구가 그 상태를 이름으로 부른다.
    for status in FeedbackStatus.known {
        let state = FeedbackEmptyMessage.inbox(loaded: true, failed: false, filter: status, unfilteredCount: 1)
        #expect(state.text.hasPrefix(status.label), "\(status.rawValue) 필터의 빈 문구가 그 상태를 말하지 않는다: \(state.text)")
    }
}

// MARK: - 순수: 정렬

@Test
func listSortsOpenFirstThenNewest() {
    let base = Date(timeIntervalSince1970: 1_789_000_000)
    let rows = [
        fbReport(id: "done-new", status: .done, createdAt: base),
        fbReport(id: "open-old", status: .open, createdAt: base.addingTimeInterval(-3600)),
        fbReport(id: "open-new", status: .open, createdAt: base),
        fbReport(id: "held-old", status: .held, createdAt: base.addingTimeInterval(-7200))
    ]
    #expect(rows.sortedForFeedbackList().map(\.id) == ["open-new", "open-old", "done-new", "held-old"])
    // 시각을 모르는 행은 맨 뒤(같은 상태 안에서). 지어낸 순서로 위에 올리지 않는다.
    let withNil = [fbReport(id: "b", createdAt: base), fbReport(id: "a", createdAt: base)].map {
        FeedbackReport(
            id: $0.id, userID: $0.userID, kind: $0.kind, body: $0.body, status: $0.status,
            adminNote: nil, appVersion: nil, osVersion: nil,
            createdAt: $0.id == "a" ? nil : $0.createdAt, updatedAt: nil,
            authorName: $0.authorName, authorAvatarURL: nil
        )
    }
    #expect(withNil.sortedForFeedbackList().map(\.id) == ["b", "a"])
}

// MARK: - 스토어: 세션이 없으면 아무 일도 없다

@MainActor
@Test
func withoutASessionThePanelOpensButNothingIsSentAndNothingHangsOnLoading() async {
    let host = "fb-no-session"
    let store = fbStore(host: host, signedIn: false)
    store.feedbackDraft = "샘플 본문"

    store.openFeedbackPanel()
    #expect(store.isFeedbackPanelVisible, "패널 열림 의도는 세워야 한다(로그인 안내를 그 안에서 본다)")
    // ★ "불러오는 중…"에 영영 갇히지 않는다 — 세션이 없으면 조회를 시작조차 하지 않으므로 그 깃발을 세우면
    //   아무도 내려 주지 않는다(빈 자리 문구가 loading 으로 굳는다).
    #expect(!store.feedbackLoading, "세션이 없는데 로딩 깃발이 섰다 — 화면이 '불러오는 중…'에 갇힌다")

    store.sendFeedback()
    store.changeFeedbackStatus(id: "x", to: .done, note: nil)
    store.refreshFeedbackOpenCount()
    await fbWait { false }

    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/submit_feedback") == 0)
    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") == 0)
    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/set_feedback_status") == 0)
    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_open_count") == 0)
    #expect(store.feedbackDraft == "샘플 본문", "보내지도 않았는데 초안을 지웠다")
}

// MARK: - 스토어: 스키마 부재는 실패가 아니다

@MainActor
@Test
func aServerWithoutTheFeedbackSchemaFoldsQuietlyInsteadOfShowingAFailure() async {
    // 브루 배포가 db push 보다 앞선 창. 이때 빨간 실패 화면을 보여 주면 모두가 '앱이 고장 났다'고 제보한다 — 제보 화면에서.
    let host = "fb-schema-missing"
    let store = fbStore(host: host)
    FeedbackURLProtocol.set(
        .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.feedback_list(p_limit, p_status) in the schema cache"}"#),
        host: host,
        path: "/rest/v1/rpc/feedback_list"
    )

    store.openFeedbackPanel()
    await fbWait { store.feedbackLoaded }

    #expect(store.feedbackLoaded, "스키마 부재를 '로드 전'으로 남겨 두면 화면이 영영 '불러오는 중…'이다")
    #expect(!store.feedbackFailed, "스키마 부재를 실패로 칠했다 — [다시 시도]는 사용자가 고칠 수 있는 일에만 쓴다")
    #expect(store.feedbackList.isEmpty)
    #expect(!store.feedbackLoading)
}

@MainActor
@Test
func sendingBeforeTheSchemaShippedSaysItWillOpenSoonAndKeepsWhatWasWritten() async {
    // 목록 갈래(위)에는 이 테스트가 있었는데 **보내기 갈래에는 없었다.** 그런데 사용자가 실제로 부딪히는
    // 것은 이쪽이다: 목록은 조용히 비어 보일 뿐이지만, 보내기는 글을 다 쓰고 누른 뒤에 실패한다.
    //
    // ★ "잠시 뒤 다시 시도해 주세요"라고 말하면 안 되는 상태다. 브루 배포가 db push 보다 앞선 창은
    //   **며칠 간다** — 그 문장은 사용자를 며칠 동안 같은 실패로 되돌려 보낸다.
    let host = "fb-send-schema-missing"
    let store = fbStore(host: host)
    FeedbackURLProtocol.set(
        .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.submit_feedback(p_app_version, p_body, p_kind, p_os_version) in the schema cache"}"#),
        host: host,
        path: "/rest/v1/rpc/submit_feedback"
    )
    store.feedbackDraft = "샘플 본문 E"

    store.sendFeedback()
    await fbWait { store.feedbackNotice != nil }

    let notice = store.feedbackNotice ?? ""
    // (a) 안내에 내부 코드가 없다 — PostgREST 코드도, 함수 시그니처도, 우리 예외 이름도.
    #expect(!notice.uppercased().contains("PGRST"), "PostgREST 코드가 화면으로 샜다: \(notice)")
    #expect(!notice.lowercased().contains("schema"), "'schema cache' 원문이 화면으로 샜다: \(notice)")
    #expect(!notice.contains("submit_feedback") && !notice.contains("_"), "코드 모양의 문자열이 화면에 떴다: \(notice)")
    // (b) **작성 중이던 초안이 살아남는다.** 지우는 자리는 전송 성공 하나뿐이라는 계약이 여기서도 지켜진다.
    #expect(store.feedbackDraft == "샘플 본문 E", "보내지도 못했는데 쓰던 글을 지웠다")
    #expect(!store.isSendingFeedback, "전송 깃발이 안 내려갔다 — 버튼이 영영 잠긴다")
    // 스키마 부재는 **평범한 실패와 다른 문장**이다. 같으면 '며칠 가는 상태'에 "잠시 뒤 다시 시도"를 말하게 된다.
    #expect(notice == FeedbackText.sendSchemaMissing)
    #expect(notice != FeedbackText.sendFailed, "며칠 가는 상태에 '잠시 뒤 다시 시도해 주세요'라고 말한다")
    #expect(!notice.contains("잠시 뒤"), "곧 열리는 것이 아니라 잠시 뒤 되는 일처럼 말한다: \(notice)")
    // 쓴 글이 살아 있다는 사실을 **문장으로도** 말한다 — 실패 문구를 본 사람은 글이 날아갔다고 믿고 창을 닫는다.
    #expect(notice.contains("그대로"), "초안이 살아 있다는 것을 말하지 않는다: \(notice)")

    // 순수 매퍼 쪽도 같은 규약이다: 보내기 경로만 이 문장을 받고,
    // 상태 변경 경로(schemaMissing 인자를 안 넘긴다)는 평범한 실패 문구로 남는다 —
    // 스키마가 없으면 목록이 통째로 비어 누를 행 자체가 없으므로 "쓰신 글"이라고 말할 것이 없다.
    #expect(
        FeedbackFailure.notice(for: SupabaseWorkServiceError.databaseSchemaMissing, fallback: FeedbackText.sendFailed) == FeedbackText.sendFailed
    )
    #expect(
        FeedbackFailure.notice(
            for: SupabaseWorkServiceError.databaseSchemaMissing,
            fallback: FeedbackText.sendFailed,
            schemaMissing: FeedbackText.sendSchemaMissing
        ) == FeedbackText.sendSchemaMissing
    )
    // 보낸 것은 **한 번**이다(실패했다고 자동으로 다시 보내지 않는다 — 24시간 상한을 축낸다).
    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/submit_feedback") == 1)
}

// MARK: - 스토어: 전송

@MainActor
@Test
func aSuccessfulSendClearsTheDraftAndCarriesTheVersionsTheScreenPromised() async {
    let host = "fb-send-ok"
    let store = fbStore(host: host)
    FeedbackURLProtocol.set(
        .init(status: 200, body: #""11111111-1111-1111-1111-111111111111""#),
        host: host,
        path: "/rest/v1/rpc/submit_feedback"
    )
    store.feedbackKind = .request
    store.feedbackDraft = "  샘플 본문 A  "

    store.sendFeedback()
    // 전송 깃발이 내려간 시점까지 기다린다 — 초안이 비는 순간에 멈추면 그 뒤의 목록 재조회가 아직 떠 있다.
    await fbWait { !store.isSendingFeedback && store.feedbackNotice != nil }

    #expect(store.feedbackDraft.isEmpty, "성공했는데 초안이 남았다 — 사용자는 같은 글을 두 번 보내고 하루 상한만 축낸다")
    #expect(store.feedbackNotice == FeedbackText.sendSuccess)
    #expect(!store.isSendingFeedback, "전송 깃발이 안 내려갔다 — 버튼이 영영 잠긴다")

    let body = try? JSONSerialization.jsonObject(
        with: Data((FeedbackURLProtocol.sentBodies(host: host, path: "/rest/v1/rpc/submit_feedback").first ?? "").utf8)
    ) as? [String: Any]
    let payload = body ?? [:]
    #expect(Set(payload.keys) == ["p_kind", "p_body", "p_app_version", "p_os_version"], "본문 키가 서버 시그니처와 다르다 — \(payload.keys.sorted())")
    #expect(payload["p_kind"] as? String == "request")
    // 본문은 **사용자 글 + 진단**이다(2026-09-10, 설정 창의 두 줄이 여기로 이사했다). 사용자가 쓴 부분은
    // 앞뒤 공백을 걷어낸 원문 그대로이고, 그 판정은 화면이 쓰는 것과 **같은 함수**로 되돌려 확인한다 —
    // 여기서 문자열을 손으로 자르면 화면과 테스트가 서로 다른 규칙으로 가르게 된다.
    let sentBody = payload["p_body"] as? String ?? ""
    let sentParts = FeedbackDiagnostics.split(sentBody)
    #expect(sentParts.body == "샘플 본문 A", "앞뒤 공백을 걷어내지 않고 보냈다: \(sentBody)")
    #expect(sentParts.diagnostics?.contains(FeedbackText.realtimeDiagnosticsLabel) == true,
            "연결 상태가 함께 안 갔다 — 그럼 운영자는 설정 창을 찍어 달라고 다시 부탁해야 한다")
    // 화면이 "함께 전송돼요"라고 약속한 것과 **같은 값**이 실제로 실린다.
    #expect(payload["p_app_version"] as? String == "0.2.48 (58)")
    #expect(payload["p_os_version"] as? String == "15.6")
    #expect(store.feedbackAutoAttachNotice.contains("0.2.48") && store.feedbackAutoAttachNotice.contains("15.6"))
    // 성공하면 목록을 다시 받는다(방금 보낸 것이 바로 보이게).
    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") >= 1)
}

@MainActor
@Test
func theDailyLimitSpeaksHumanAndKeepsTheDraft() async {
    let host = "fb-rate-limit"
    let store = fbStore(host: host)
    FeedbackURLProtocol.set(
        .init(status: 400, body: #"{"code":"P0001","message":"FEEDBACK_RATE_LIMIT","details":null,"hint":null}"#),
        host: host,
        path: "/rest/v1/rpc/submit_feedback"
    )
    store.feedbackDraft = "샘플 본문 B"

    store.sendFeedback()
    await fbWait { store.feedbackNotice != nil }

    #expect(store.feedbackNotice == FeedbackText.rateLimited)
    let notice = store.feedbackNotice ?? ""
    #expect(!notice.uppercased().contains("FEEDBACK"), "화면에 서버 예외 이름이 그대로 떴다: \(notice)")
    #expect(!notice.contains("_"), "화면에 코드 모양의 문자열이 떴다: \(notice)")
    // ★ 실패했으면 글은 **그대로 남는다**. 여기서 지우면 사용자는 다 쓴 글을 잃고 다시 쓰지 않는다.
    #expect(store.feedbackDraft == "샘플 본문 B", "실패했는데 초안을 지웠다")
    #expect(!store.isSendingFeedback)
}

@MainActor
@Test
func sendIsLockedWhileInFlightAndWhenTheDraftIsOutOfRange() {
    let store = fbStore(host: "fb-send-gate")
    #expect(!store.canSendFeedback, "빈 초안인데 보내기가 열려 있다")
    store.feedbackDraft = "샘플"
    #expect(store.canSendFeedback)
    store.feedbackDraft = String(repeating: "가", count: 1001)
    #expect(!store.canSendFeedback, "1001자인데 보내기가 열려 있다 — 서버가 거절할 글을 보내게 한다")
    store.feedbackDraft = "샘플"
    store.isSendingFeedback = true
    #expect(!store.canSendFeedback, "전송 중인데 버튼이 살아 있다 — 연타가 하루 상한을 두 배로 축낸다")
}

// MARK: - 스토어: 상태 변경(낙관 반영 · 실패 원복)

@MainActor
@Test
func statusChangeShowsImmediatelyAndRollsBackTheWholeRowWhenTheServerRefuses() async {
    let host = "fb-status-forbidden"
    let store = fbStore(host: host, admin: true)
    FeedbackURLProtocol.set(
        .init(status: 403, body: #"{"code":"P0001","message":"FEEDBACK_FORBIDDEN","details":null,"hint":null}"#),
        host: host,
        path: "/rest/v1/rpc/set_feedback_status"
    )
    store.feedbackList = [fbReport(id: "r1", status: .open, owner: fbOtherID)]
    store.feedbackLoaded = true

    store.changeFeedbackStatus(id: "r1", to: .done, note: "확인함")
    // 낙관 반영은 **동기적으로** 보여야 한다 — 왕복을 기다리면 관리자가 버튼을 다시 누른다.
    #expect(store.feedbackList[0].status == .done, "낙관 반영이 없다")
    #expect(store.feedbackList[0].adminNote == "확인함")

    await fbWait { store.feedbackNotice != nil }

    #expect(store.feedbackList[0].status == .open, "실패했는데 상태가 되돌아오지 않았다")
    // 상태만 되돌리면 메모가 남아 '저장된 것처럼' 보인다 — 행을 통째로 되돌린다.
    #expect(store.feedbackList[0].adminNote == nil, "실패했는데 메모가 저장된 것처럼 남았다")
    #expect(store.feedbackNotice == FeedbackText.forbidden)
    #expect(!(store.feedbackNotice ?? "").uppercased().contains("FORBIDDEN"), "서버 예외 이름이 화면으로 샜다")
}

@MainActor
@Test
func aSuccessfulStatusChangeSendsTheServerVocabularyAndRefetchesOnce() async {
    let host = "fb-status-ok"
    let store = fbStore(host: host, admin: true)
    FeedbackURLProtocol.set(.init(status: 204, body: ""), host: host, path: "/rest/v1/rpc/set_feedback_status")
    store.feedbackList = [fbReport(id: "r1", status: .open, owner: fbOtherID)]
    store.feedbackLoaded = true
    store.expandedFeedbackID = "r1"
    store.feedbackNoteDraft = " 처리했음 "

    store.applyFeedbackStatusFromEditor(id: "r1", status: .inProgress)
    await fbWait { FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") >= 1 }

    let sent = FeedbackURLProtocol.sentBodies(host: host, path: "/rest/v1/rpc/set_feedback_status").first ?? ""
    let payload = ((try? JSONSerialization.jsonObject(with: Data(sent.utf8))) as? [String: Any]) ?? [:]
    #expect(Set(payload.keys) == ["p_id", "p_status", "p_note"], "본문 키가 서버 시그니처와 다르다 — \(payload.keys.sorted())")
    #expect(payload["p_id"] as? String == "r1")
    #expect(payload["p_status"] as? String == "doing", "서버 어휘가 아니라 화면 라벨/케이스 이름을 보냈다")
    #expect(payload["p_note"] as? String == "처리했음", "메모 앞뒤 공백을 안 걷었다")
    // 성공했을 때만 재조회한다(정렬·미해결 건수를 서버 사실에 맞춘다).
    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") == 1)
}

// MARK: - 스토어: 필터·펼침은 왕복을 내지 않는다

@MainActor
@Test
func filterChipsAndExpansionNeverCostARoundTrip() async {
    // 무료 플랜이다. 칩마다 조회를 내면 필터 수만큼 요청이 곱해진다 — 거르기는 순수 계산으로 끝낸다.
    let host = "fb-filter"
    let store = fbStore(host: host, admin: true)
    store.feedbackList = [
        fbReport(id: "a", status: .open, owner: fbOtherID),
        fbReport(id: "b", status: .done, owner: fbOtherID),
        fbReport(id: "c", status: .held, owner: fbOtherID)
    ]
    store.feedbackLoaded = true

    store.selectFeedbackFilter(.done)
    #expect(store.visibleFeedback.map(\.id) == ["b"])
    store.selectFeedbackFilter(nil)
    #expect(store.visibleFeedback.map(\.id) == ["a", "b", "c"])
    store.toggleFeedbackExpansion("b")
    #expect(store.expandedFeedbackID == "b")
    // 펼치면 기존 메모가 초안으로 실린다 — 빈 칸으로 열면 관리자가 기존 메모를 지운다.
    store.feedbackList[0].adminNote = "앞선 메모"
    store.toggleFeedbackExpansion("a")
    #expect(store.feedbackNoteDraft == "앞선 메모")
    // 필터를 옮기면 펼침과 메모 초안은 접힌다(다른 제보에 남의 메모가 붙지 않게).
    store.selectFeedbackFilter(.held)
    #expect(store.expandedFeedbackID == nil && store.feedbackNoteDraft.isEmpty)

    await fbWait { false }
    #expect(FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") == 0, "필터를 눌렀다고 서버에 물었다")
}

// MARK: - 스토어: 관리자 게이트는 표시일 뿐이고, 두 겹이다

@MainActor
@Test
func theInboxTabCannotBeReachedWithoutTheServerSaidAdminFlag() {
    let store = fbStore(host: "fb-tab-gate", admin: false)
    store.selectFeedbackTab(inbox: true)
    #expect(!store.feedbackShowsInbox, "관리자가 아닌데 받은 제보 탭으로 넘어갔다")
    #expect(!store.showsFeedbackInbox)

    // 깃발이 도착하면 열린다(로그인 직후 지갑 sync 전에는 닫혀 있다가 나타난다).
    store.ultraUnlimited = true
    store.selectFeedbackTab(inbox: true)
    #expect(store.showsFeedbackInbox)

    // ★ 깃발이 내려가면(로그아웃·계정 전환) 낡은 탭 선택이 남아도 화면은 즉시 닫힌다 —
    //   두 값의 곱이라 한쪽만 낡아 있는 조합이 존재할 수 없다.
    store.ultraUnlimited = false
    #expect(store.feedbackShowsInbox, "저장된 선택 자체는 남아 있는 상황을 재현한다")
    #expect(!store.showsFeedbackInbox, "관리자 깃발이 내려갔는데 받은 제보 탭이 그려진다")
}

@MainActor
@Test
func theRailBadgeFallsWithTheAdminFlagInsteadOfWaitingForTheNextLoad() {
    // ★ v0.2.48 결함: 관리자에서 내려온 뒤(권한 회수·계정 전환) 레일의 제보 배지가 **다음 목록 로드까지**
    //   앞서 받은 미해결 건수를 계속 보여 줬다. 탭은 곱(showsFeedbackInbox)으로 즉시 닫히는데 배지만
    //   안 닫혀서, 이제 열 수도 없는 화면의 건수가 남았다.
    //   고치는 자리를 대입 지점이 아니라 **관찰자**로 잡았기 때문에, 어떤 경로로 내려가든 함께 내려간다.
    let store = fbStore(host: "fb-badge-follows-flag", admin: true)
    store.feedbackOpenCount = 5
    #expect(store.feedbackOpenCount == 5)

    store.ultraUnlimited = false
    #expect(store.feedbackOpenCount == 0, "관리자가 아닌데 미해결 건수가 남았다 — 배지가 계속 떠 있다")

    // 배지를 그리는 뷰는 건수 하나만 본다(관리자 판정을 클라가 하지 않는다는 규약). 그 뷰가 안전한 이유가
    // 위 성질이므로, 여기서 두 값이 갈리는 조합이 다시 생기면 배지가 다시 남는다.
    store.ultraUnlimited = true
    #expect(store.feedbackOpenCount == 0, "깃발이 올라갔다고 없던 건수를 지어냈다 — 건수는 서버가 준다")
    store.feedbackOpenCount = 3
    store.signOut()
    #expect(store.feedbackOpenCount == 0)
}

/// `withObservationTracking(onChange:)` 이 @Sendable 클로저라 지역 변수를 못 쓴다. 발화는 대입 스레드에서
/// 동기적으로 일어나므로 잠금 없이 안전하다(그 사실 때문에 `@unchecked` 다).
private final class FBObservationFlag: @unchecked Sendable {
    var fired = false
}

@MainActor
@Test
func puttingAnObserverOnTheAdminFlagDidNotStopSwiftUIFromSeeingIt() {
    // ★ 위 수정은 `@Observable` 프로퍼티에 `didSet` 을 붙인다. 매크로가 저장 프로퍼티를 접근자로 바꿔
    //   놓는 자리라, 관찰 등록이 조용히 끊기면 **컴파일은 되는데 화면만 안 갱신된다**(레일 배지·잔량 표시가
    //   서버 응답을 받고도 옛 값을 그린 채로 남는다 — 눈으로 보기 전에는 아무도 모르는 종류의 회귀다).
    //   그래서 값이 아니라 **관찰이 실제로 발화하는지**를 되묻는다.
    let store = fbStore(host: "fb-observation-still-works", admin: false)
    // `onChange` 는 @Sendable 이라 지역 변수를 못 건드린다. 발화는 **대입한 그 스레드에서 동기적으로**
    // 일어나므로(관찰 등록의 계약) 상자 하나면 충분하다.
    let flagSeen = FBObservationFlag()
    withObservationTracking { _ = store.ultraUnlimited } onChange: { flagSeen.fired = true }
    store.ultraUnlimited = true
    #expect(flagSeen.fired, "ultraUnlimited 에 didSet 을 붙였더니 관찰이 끊겼다 — 화면이 서버 응답을 받고도 안 바뀐다")

    let countSeen = FBObservationFlag()
    withObservationTracking { _ = store.feedbackOpenCount } onChange: { countSeen.fired = true }
    store.feedbackOpenCount = 2
    #expect(countSeen.fired, "feedbackOpenCount 관찰이 끊겼다 — 배지가 안 갱신된다")

    // 관찰자가 **다른 프로퍼티를 쓰는** 경로도 발화해야 한다(깃발이 내려가며 건수를 0으로 내리는 그 경로다).
    let cascadeSeen = FBObservationFlag()
    withObservationTracking { _ = store.feedbackOpenCount } onChange: { cascadeSeen.fired = true }
    store.ultraUnlimited = false
    #expect(cascadeSeen.fired, "깃발을 내려 건수가 0이 됐는데 배지 관찰이 안 깨어났다")
    #expect(store.feedbackOpenCount == 0)
}

@MainActor
@Test
func openCountIsAskedOnlyForAdminsAndNeverOnATimer() async {
    // 호스트를 나눈다 — `fbStore` 가 호스트별 카운터를 초기화하므로 한 호스트에 두 스토어를 두면
    // 두 번째 생성이 첫 번째의 요청 기록을 지운다(첫 판에서 실제로 그렇게 셌다).
    let userHost = "fb-open-count-user"
    let store = fbStore(host: userHost, admin: false)
    FeedbackURLProtocol.set(.init(status: 200, body: "7"), host: userHost, path: "/rest/v1/rpc/feedback_open_count")

    store.openFeedbackPanel()
    await fbWait { store.feedbackLoaded }
    #expect(FeedbackURLProtocol.count(host: userHost, path: "/rest/v1/rpc/feedback_open_count") == 0, "관리자가 아닌데 미해결 건수를 물었다")
    #expect(store.feedbackOpenCount == 0)
    // 패널을 여는 동안 목록 조회는 **정확히 한 번**이다 — 폴링이 붙으면 여기가 먼저 빨개진다.
    #expect(FeedbackURLProtocol.count(host: userHost, path: "/rest/v1/rpc/feedback_list") == 1, "패널 열기 한 번에 목록 조회가 여러 번 나갔다")

    let adminHost = "fb-open-count-admin"
    let admin = fbStore(host: adminHost, admin: true)
    FeedbackURLProtocol.set(.init(status: 200, body: "7"), host: adminHost, path: "/rest/v1/rpc/feedback_open_count")
    admin.openFeedbackPanel()
    await fbWait { admin.feedbackOpenCount == 7 }
    #expect(admin.feedbackOpenCount == 7)
    #expect(FeedbackURLProtocol.count(host: adminHost, path: "/rest/v1/rpc/feedback_list") == 1, "패널 열기 한 번에 목록 조회가 여러 번 나갔다")
    #expect(FeedbackURLProtocol.count(host: adminHost, path: "/rest/v1/rpc/feedback_open_count") == 1, "건수 조회가 여러 번 나갔다")
}

// MARK: - 스토어: 계정에 묶인다

@MainActor
@Test
func signingOutLeavesNoOneElsesWordsBehind() {
    let store = fbStore(host: "fb-logout", admin: true)
    store.feedbackList = [fbReport(id: "a", owner: fbOtherID)]
    store.feedbackLoaded = true
    store.feedbackOpenCount = 3
    store.feedbackDraft = "샘플 본문 C"
    store.feedbackNotice = FeedbackText.sendSuccess
    store.feedbackShowsInbox = true
    store.expandedFeedbackID = "a"
    store.feedbackNoteDraft = "메모"
    store.isFeedbackPanelVisible = true

    store.signOut()

    // ★ 이 화면이 나르는 것은 순위 숫자가 아니라 **사람이 쓴 문장**이다 — 다음 사람에게 한 줄도 남기지 않는다.
    #expect(store.feedbackList.isEmpty, "로그아웃 뒤에도 앞 사람이 쓴 글이 남아 있다")
    #expect(store.feedbackDraft.isEmpty, "로그아웃 뒤에도 앞 사람이 쓰던 초안이 남아 있다")
    #expect(store.feedbackNoteDraft.isEmpty && store.expandedFeedbackID == nil)
    #expect(store.feedbackOpenCount == 0 && !store.feedbackShowsInbox && !store.showsFeedbackInbox)
    #expect(store.feedbackNotice == nil && !store.feedbackLoaded && !store.isFeedbackPanelVisible)
}

@MainActor
@Test
func myFeedbackIsEmptyWithoutASessionInsteadOfClaimingAnonymousRows() {
    // 서버가 익명화한(user_id null) 남의 제보를 '내가 보낸 제보'로 둔갑시키지 않는다.
    let store = fbStore(host: "fb-mine", signedIn: false)
    store.feedbackList = [fbReport(id: "anon", owner: nil), fbReport(id: "mine", owner: fbUserID)]
    #expect(store.myFeedback.isEmpty)

    let signedIn = fbStore(host: "fb-mine-2")
    signedIn.feedbackList = [fbReport(id: "anon", owner: nil), fbReport(id: "mine", owner: fbUserID), fbReport(id: "other", owner: fbOtherID)]
    #expect(signedIn.myFeedback.map(\.id) == ["mine"])
}

// MARK: - 패널 계약 (v0.2.50 — 창이 사라졌다)

// 사용자 지시(2026-09-10): "제보창도 팝오버 창 안에서만 뜨게 하면서."
// 그래서 여기 있던 세 테스트(창 스타일마스크·지연 생성·로그아웃 시 창 닫기)는 **잴 대상이 사라졌다.**
// 지우기만 하면 그 자리에 아무 계약도 안 남으므로, 창이 지키던 성질 중 **패널에도 유효한 것들**을
// 여기서 다시 못 박는다: 상호 배타 · 진입점이 목록을 받는다 · 팝오버를 닫지 않는다 · 초안이 산다.

@MainActor
@Test
func openingTheFeedbackPanelClosesEveryOtherPanelAndNeverTouchesThePopover() throws {
    let store = fbStore(host: "fb-panel-exclusive", admin: true)
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.isPokePanelVisible = true
    store.isInsightsPanelVisible = true
    store.isMessagePanelVisible = true

    store.openFeedbackPanel()

    #expect(store.isFeedbackPanelVisible)
    #expect(!store.isLeaderboardVisible && !store.isTokenBoardVisible)
    #expect(!store.isPokePanelVisible && !store.isInsightsPanelVisible)
    #expect(!store.isUltraPanelVisible && !store.isMessagePanelVisible, "다른 패널이 제보 뒤에 살아 남았다")

    // ★ **팝오버를 닫지 않는다.** 창이던 시절에는 진입점이 `dismissMenuPopover()` 를 불렀는데(팝오버 위에
    //   창을 띄우는 동작이었으니까), 지금 그러면 방금 연 화면이 그 자리에서 사라진다.
    //   주석은 걷어내고 본다 — 위 문단과 소스 주석에 그 이름이 들어 있어서, 안 걷으면 설명을 지워야만 초록이 된다.
    let code = fbStrippingComments(try String(contentsOf: fbSourceURL("WorkTimerStoreFeedback.swift"), encoding: .utf8))
    #expect(!code.contains("dismissMenuPopover"), "제보 진입점이 아직 팝오버를 닫는다 — 패널은 팝오버 안에 산다")
    // 대조군: 미니게임은 **여전히 별도 창**이라 그쪽은 닫아야 한다(함께 지웠다면 그건 요구를 넘어선 파괴다).
    let game = fbStrippingComments(try String(contentsOf: fbSourceURL("WorkTimerStoreMiniGame.swift"), encoding: .utf8))
    #expect(game.contains("WindowTopAnchor.dismissMenuPopover()"), "미니게임 창이 팝오버를 안 닫는다")
}

@MainActor
@Test
func theRefreshButtonIsGoneAndOpeningThePanelIsWhatFetchesTheList() async throws {
    // 사용자 지시 3: "제보창에서 새로고침 버튼 없어도 될 듯."
    // 버튼이 사라져도 **최신을 볼 길은 남아야 한다** — 그 길이 곧 진입점이다.
    let view = fbStrippingComments(try String(contentsOf: fbSourceURL("CheckFeedbackView.swift"), encoding: .utf8))
    #expect(!view.contains("arrow.clockwise\", help: \"새로고침\""), "[새로고침] 버튼이 남아 있다")
    #expect(!view.contains("IconButton(icon: \"arrow.clockwise\""), "[새로고침] 아이콘 버튼이 남아 있다")
    // [다시 시도]는 **다르다**(실패했을 때만 뜨는 복구 버튼이고, 이 저장소의 모든 패널이 갖는 규약이다).
    #expect(view.contains("FeedbackRetryButton"), "실패 복구 버튼까지 함께 지웠다")

    // 그리고 패널을 열 때마다 목록을 받는다 — 두 번 열면 두 번 받는다(그것이 새로고침을 대신하는 경로다).
    let host = "fb-open-refetches"
    let store = fbStore(host: host)
    store.openFeedbackPanel()
    await fbWait { store.feedbackLoaded }
    store.closeFeedbackPanel()
    store.openFeedbackPanel()
    await fbWait { FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") == 2 }
    #expect(
        FeedbackURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") == 2,
        "다시 열었는데 목록을 안 받았다 — [새로고침]을 없앤 대가를 아무도 안 물려받았다"
    )
}

@MainActor
@Test
func signingOutClearsThePanelFlagAndOnlyTheMiniGameWindowStillNeedsClosing() {
    // ★ v0.2.48 의 결함은 "깃발만 내리고 창은 화면에 남았다"였다. v0.2.50 에 제보 창이 사라지면서
    //   그 결함의 절반이 **구조적으로** 없어졌다 — 패널은 깃발이 곧 화면이기 때문이다.
    //   남은 절반(미니게임 창)은 그대로라, 그쪽만 계속 잰다.
    let store = fbStore(host: "fb-signout-closes-windows", admin: true)
    let game = CheckMiniGameWindowController.shared
    game.configure(store: store, content: { _ in AnyView(Color.clear) })
    game.show()
    store.isFeedbackPanelVisible = true
    store.isMiniGamePanelVisible = true
    #expect(game.isOpen, "창을 못 열었다 — 이 테스트가 아무것도 재현하지 못한다")

    store.signOut()

    #expect(!store.isFeedbackPanelVisible, "제보 패널 깃발이 안 내려갔다 — 다음 계정 화면에 앞 사람 제보가 뜬다")
    #expect(!store.isMiniGamePanelVisible, "레일 하이라이트가 안 내려갔다")
    #expect(!game.isOpen, "로그아웃했는데 미니게임 창이 화면에 남았다")
    // **창 자체는 파괴하지 않는다**(닫아도 살아 있다는 계약 — 다시 로그인해 열면 같은 자리에 선다).
    #expect(game.hasWindow, "닫으면서 창을 버렸다 — 다음에 열면 자리가 초기화된다")

    game.currentWindow?.close()
}

@MainActor
@Test
func closingThePanelKeepsTheDraftAliveButFoldsTheExpandedRow() {
    // 화면을 잘못 바꿨다고 쓰던 글이 사라지면 그 사용자는 두 번 다시 제보하지 않는다.
    let store = fbStore(host: "fb-draft-survives", admin: true)
    store.feedbackDraft = "샘플 본문 D"
    store.isFeedbackPanelVisible = true
    store.expandedFeedbackID = "row-0"
    store.feedbackNoteDraft = "메모"

    store.closeFeedbackPanel()

    #expect(!store.isFeedbackPanelVisible)
    #expect(store.feedbackDraft == "샘플 본문 D", "화면을 닫았다고 쓰던 글을 지웠다")
    // 반면 펼친 행과 메모는 접는다 — 다시 열었을 때 어느 제보의 메모인지 화면만으로는 알 수 없다.
    #expect(store.expandedFeedbackID == nil && store.feedbackNoteDraft.isEmpty)
}

// MARK: - 렌더 스냅샷 (panels-)
//
// v0.2.50 부터 제보는 **팝오버 하위 패널**이다. 그래서 스냅샷도 패널 하나가 아니라 **팝오버 통째로** 그린다 —
// 이 작업에서 가장 값비싼 결함이 "창 높이 회귀"이기 때문이다: 패널만 따로 그리면 배너·헤더 카드·푸터가
// 함께 서는 실제 높이를 영영 못 잰다(그리고 푸터가 잘리는 순간 사용자는 로그아웃할 방법을 잃는다).

/// 스냅샷 저장 위치. 기본은 이 실행의 임시 디렉터리이고 `CHECK_SNAPSHOT_DIR` 로 덮어쓴다.
/// 세션 전용 절대 경로를 소스에 박아 두면 퍼블릭 저장소에 개인 머신 경로가 남고, 다른 기계에서는
/// `try?` 가 조용히 no-op 이 되어 "스냅샷을 남긴다"는 약속이 거짓말이 된다(V0246 렌더 스위트와 같은 규약).
enum FeedbackSnapshots {
    static func save(_ bitmap: NSBitmapImageRep, name: String) {
        let base = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-snapshots", isDirectory: true)
        let dir = base.appendingPathComponent("panels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }
}

private enum FBRenderError: Error { case failed }

/// 얼린 기준 시각. 값 자체에 뜻은 없고 **변하지 않는다는 사실**만 쓴다(스냅샷이 실행 시각에 흔들리면
/// 사람이 눈으로 비교할 수 없다).
private let fbRenderNow = Date(timeIntervalSince1970: 1_789_000_000)

/// 제보 패널이 열린 **메인 화면** 스토어. 팀이 확정된 로그인 상태여야 팝오버가 헤더 카드·레일·푸터를 그린다 —
/// 안 그러면 "합류할 팀을 찾아요" 화면이 나와 이 스냅샷이 아무것도 증명하지 못한다.
@MainActor
private func fbMenuStore(_ store: WorkTimerStore) -> WorkTimerStore {
    store.isMenuPresented = true
    store.displayNow = fbRenderNow
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.startedAt = fbRenderNow.addingTimeInterval(-3_600)
    store.isFeedbackPanelVisible = true
    return store
}

/// 팝오버가 얹을 수 있는 **가장 큰 크롬**의 재료. 새 버전 배너는 패치노트 줄 수만큼 자라고 그 수는
/// `UpdateCheckStore.maxNotes`(4)로 묶여 있으므로, 노트 4줄짜리 배너(81 + 8 + 4×15 = 149pt)가 배너의 상한이다.
/// 거기에 주간 목표 편집 인라인 행(92pt)을 겹치면 **241pt** — 이것이 하위 패널이 감당해야 할 최악의 크롬이다.
/// (토큰 소모량 행은 하위 패널이 열리면 감춰지므로 여기 없다. 12시간 확인 배너는 92pt 라 새 버전 배너보다 낮다.)
private let fbWorstNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

/// ★ `previewClipsOverflowList: true` · `previewPlainTextEditors: true` — `ImageRenderer` 는 ScrollView
///   안쪽과 `TextEditor`/`TextField` 를 못 그린다. 이 인자들이 없으면 아래 스냅샷은 목록 자리가 비고
///   입력칸 자리가 **노란 상자**인 그림이고, 사람이 확인할 수 있는 것이 사라진다.
///   **앱은 언제나 진짜 위젯을 쓴다**(두 기본값이 false 다).
@MainActor
private func fbPanelBitmap(_ store: WorkTimerStore, worstChrome: Bool = false) throws -> NSBitmapImageRep {
    let view = CheckMenuView(
        store: store,
        previewClipsOverflowList: true,
        previewGoalEditing: worstChrome,
        previewUpdateBanner: worstChrome,
        previewUpdateNotes: worstChrome ? fbWorstNotes : [],
        previewPlainTextEditors: true
    )
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw FBRenderError.failed }
    return bitmap
}

/// 내용 없이 배경만 그린 같은 크기의 비트맵. 배경이 **그라디언트**라 "한 픽셀을 배경색으로 삼는" 잉크 탐지는
/// 통째로 거짓말한다(첫 판에서 실제로 minX=0 이 나왔다) — 그래서 기준을 그림 하나로 둔다.
@MainActor
private func fbBlankBitmap(matching bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
    let view = Color.clear
        .frame(width: CGFloat(bitmap.pixelsWide) / 2, height: CGFloat(bitmap.pixelsHigh) / 2)
        .background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let blank = NSBitmapImageRep(data: tiff)
    else { throw FBRenderError.failed }
    return blank
}

/// 두 비트맵이 눈에 띄게 다른 영역의 경계(픽셀). 없으면 nil.
private func fbDiffBounds(
    _ lhs: NSBitmapImageRep,
    _ rhs: NSBitmapImageRep,
    tolerance: Double = 0.06,
    skippingTopPixels: Int = 0
) -> CGRect? {
    let width = min(lhs.pixelsWide, rhs.pixelsWide)
    let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in stride(from: skippingTopPixels, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 2) {
            guard let a = lhs.colorAt(x: x, y: y), let b = rhs.colorAt(x: x, y: y) else { continue }
            let delta = abs(a.redComponent - b.redComponent)
                + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
            if delta > tolerance {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

@MainActor
private func fbInboxStore(host: String, rows: Int) -> WorkTimerStore {
    let store = fbStore(host: host, admin: true)
    let base = fbRenderNow
    let statuses: [FeedbackStatus] = [.open, .open, .inProgress, .done, .held]
    var built: [FeedbackReport] = []
    for index in 0..<rows {
        let owner: String = index == 0 ? fbUserID : "u-\(index)"
        let kind: FeedbackKind = index % 2 == 0 ? .bug : .request
        // 합성 본문. **두 줄을 훌쩍 넘겨야** 접힘(2줄 말줄임)과 펼침(전문)의 차이가 그림에 남는다 —
        // 첫 판에서는 본문이 딱 두 줄에 맞아 펼쳐도 그림이 그대로였다.
        let body: String = "샘플 본문 \(index) — " + String(repeating: "가나다라마바사아자차 ", count: 22)
        let note: String? = index == 1 ? "샘플 메모" : nil
        let version: String = "0.2.5\(index % 9) (5\(index % 9))"
        let created: Date = base.addingTimeInterval(-Double(index) * 4000)
        let author: String = index == 0 ? "나야" : "동료\(index)"
        built.append(
            FeedbackReport(
                id: "row-\(index)",
                userID: owner,
                kind: kind,
                body: body,
                status: statuses[index % statuses.count],
                adminNote: note,
                appVersion: version,
                osVersion: "15.6",
                createdAt: created,
                updatedAt: base,
                authorName: author,
                authorAvatarURL: nil
            )
        )
    }
    store.feedbackList = built
    store.feedbackLoaded = true
    store.feedbackOpenCount = store.feedbackList.filter { $0.status.isOpen }.count
    store.feedbackShowsInbox = true
    return store
}

/// 팝오버 높이 상한(pt). 창은 위 모서리가 메뉴바 아래에 고정되고 아래로만 자라므로, 이걸 넘으면
/// 푸터(로그아웃/앱 종료)가 화면 밖으로 잘린다 — 그 순간 사용자는 로그아웃할 방법을 잃는다.
private let fbPopoverHeightCap: Double = 700

@MainActor
@Test
func bothTabsDrawInsideThePopoverWithoutClippingOrOverlap() throws {
    // ① 보내기 탭(일반 사용자) — 글을 쓰고 있는 중, 내가 보낸 제보 두 줄.
    let send = fbMenuStore(fbStore(host: "fb-render-send"))
    send.feedbackDraft = "샘플 본문 — " + String(repeating: "가나다라마바사아자차 ", count: 4)
    send.feedbackList = [
        fbReport(id: "m1", kind: .bug, status: .open, createdAt: fbRenderNow.addingTimeInterval(-3600)),
        fbReport(id: "m2", kind: .request, status: .done, createdAt: fbRenderNow.addingTimeInterval(-200_000))
    ]
    send.feedbackLoaded = true
    let sendBitmap = try fbPanelBitmap(send)
    FeedbackSnapshots.save(sendBitmap, name: "panels-feedback-send.png")
    // 팝오버 폭은 본문 316 + 간격 10 + 레일 64 + 바깥 padding 24 = 414pt 고정이다.
    #expect(sendBitmap.pixelsWide == 414 * 2, "팝오버 폭이 414pt 가 아니다 — 제보 패널이 본문 열을 밀어냈다")
    #expect(Double(sendBitmap.pixelsHigh) / 2.0 <= fbPopoverHeightCap,
            "보내기 탭이 700pt 상한을 넘었다: \(Double(sendBitmap.pixelsHigh) / 2.0)pt")
    let sendBlank = try fbBlankBitmap(matching: sendBitmap)
    let sendInk = try #require(fbDiffBounds(sendBitmap, sendBlank), "보내기 탭이 통째로 비었다")
    #expect(sendInk.maxX <= CGFloat(sendBitmap.pixelsWide) - 2, "보내기 탭 내용이 오른쪽으로 넘쳤다")
    #expect(sendInk.minX >= 4, "보내기 탭 내용이 왼쪽 밖에서 시작한다")
    // **푸터가 살아 있다**: 잉크가 그림 맨 아래까지 닿는다(로그아웃/앱 종료 버튼 줄).
    #expect(sendInk.maxY > CGFloat(sendBitmap.pixelsHigh) - 60, "팝오버 아래쪽이 비었다 — 푸터가 안 그려졌다")

    // ② 받은 제보 탭(관리자) — 상태가 섞인 목록.
    let inbox = fbMenuStore(fbInboxStore(host: "fb-render-inbox", rows: 5))
    let inboxBitmap = try fbPanelBitmap(inbox)
    FeedbackSnapshots.save(inboxBitmap, name: "panels-feedback-inbox.png")
    #expect(inboxBitmap.pixelsWide == 414 * 2)
    #expect(Double(inboxBitmap.pixelsHigh) / 2.0 <= fbPopoverHeightCap,
            "받은 제보 탭이 700pt 상한을 넘었다: \(Double(inboxBitmap.pixelsHigh) / 2.0)pt")
    let inboxBlank = try fbBlankBitmap(matching: inboxBitmap)
    let inboxInk = try #require(fbDiffBounds(inboxBitmap, inboxBlank), "받은 제보 탭이 통째로 비었다")
    #expect(inboxInk.maxX <= CGFloat(inboxBitmap.pixelsWide) - 2, "받은 제보 행이 오른쪽으로 넘쳤다")
    #expect(inboxInk.minX >= 4, "받은 제보 행이 왼쪽 밖에서 시작한다")
    #expect(inboxInk.maxY > CGFloat(inboxBitmap.pixelsHigh) - 60, "받은 제보 탭에서 푸터가 안 그려졌다")

    // ③ 펼친 행 — 전체 본문 + 진단 판 + 메모 + 상태 버튼 넷.
    let expanded = fbMenuStore(fbInboxStore(host: "fb-render-expanded", rows: 4))
    expanded.expandedFeedbackID = "row-0"
    expanded.feedbackNoteDraft = "샘플 메모"
    let expandedBitmap = try fbPanelBitmap(expanded)
    FeedbackSnapshots.save(expandedBitmap, name: "panels-feedback-expanded.png")
    #expect(Double(expandedBitmap.pixelsHigh) / 2.0 <= fbPopoverHeightCap,
            "펼친 행이 700pt 상한을 넘었다: \(Double(expandedBitmap.pixelsHigh) / 2.0)pt")
    // 펼치면 그림이 **달라진다**(접힘과 같으면 펼침이 아무 일도 안 한 것이다).
    let collapsed = fbMenuStore(fbInboxStore(host: "fb-render-collapsed", rows: 4))
    let collapsedBitmap = try fbPanelBitmap(collapsed)
    #expect(
        fbDiffBounds(expandedBitmap, collapsedBitmap) != nil,
        "행을 펼쳤는데 그림이 그대로다 — 펼침이 아무 일도 안 했다"
    )

    // ④ 빈 목록(관리자) — 첫 실행에서 보게 될 그림.
    let empty = fbMenuStore(fbStore(host: "fb-render-empty", admin: true))
    empty.feedbackShowsInbox = true
    empty.feedbackLoaded = true
    let emptyBitmap = try fbPanelBitmap(empty)
    FeedbackSnapshots.save(emptyBitmap, name: "panels-feedback-empty.png")
    #expect(Double(emptyBitmap.pixelsHigh) / 2.0 <= fbPopoverHeightCap)
    let emptyBlank = try fbBlankBitmap(matching: emptyBitmap)
    let emptyInk = try #require(fbDiffBounds(emptyBitmap, emptyBlank), "빈 목록 화면이 통째로 비었다 — 안내 한 줄도 없다")
    #expect(emptyInk.maxX <= CGFloat(emptyBitmap.pixelsWide) - 2 && emptyInk.minX >= 4, "빈 안내 카드가 화면 밖으로 넘쳤다")
    // ★ 창 시절의 "빈 카드가 영역을 채운다"는 **패널에서 뒤집힌다**(v0.2.50): 팝오버는 콘텐츠 높이가 곧
    //   창 높이라, 빈 카드를 늘리면 아무것도 없는 화면이 상한을 갉아먹는다. 그래서 빈 화면은 목록이 있는
    //   화면보다 **짧아야** 한다 — 그것이 "자연 높이로 그린다"의 눈에 보이는 증거다.
    #expect(
        emptyBitmap.pixelsHigh < inboxBitmap.pixelsHigh,
        "빈 목록 화면이 목록 있는 화면만큼 길다 — 빈 카드가 아직 자리를 늘리고 있다"
    )

    // ⑤ 필터가 걸린 빈 목록 — ④와 **그림이 달라야** 한다(문구가 갈리지 않으면 관리자는 필터를 의심하지 못한다).
    let filteredEmpty = fbMenuStore(fbInboxStore(host: "fb-render-empty-filtered", rows: 3))
    filteredEmpty.selectFeedbackFilter(.held)   // rows=3 이면 보류가 하나도 없다
    #expect(filteredEmpty.visibleFeedback.isEmpty, "필터가 걸린 빈 목록을 재현하지 못했다")
    let filteredBitmap = try fbPanelBitmap(filteredEmpty)
    FeedbackSnapshots.save(filteredBitmap, name: "panels-feedback-empty-filtered.png")
    #expect(
        fbDiffBounds(filteredBitmap, emptyBitmap) != nil,
        "필터가 걸린 빈 목록이 진짜 빈 목록과 똑같이 그려졌다 — 화면에서 둘을 가를 수 없다"
    )

    // ⑥ 못 불러온 목록 — 같은 자리에 실패 문구와 [다시 시도]가 선다(빈 목록이라고 단정하지 않는다).
    let failed = fbMenuStore(fbStore(host: "fb-render-empty-failed", admin: true))
    failed.feedbackShowsInbox = true
    failed.feedbackFailed = true
    let failedBitmap = try fbPanelBitmap(failed)
    FeedbackSnapshots.save(failedBitmap, name: "panels-feedback-empty-failed.png")
    #expect(
        fbDiffBounds(failedBitmap, emptyBitmap) != nil,
        "못 불러온 화면이 '받은 제보가 없어요'와 똑같이 그려졌다"
    )
}

@MainActor
@Test
func atTwoNinetyTwoALongNameNeverRunsUnderTheStatusChip() throws {
    // 창(460pt 최소 폭) 시절의 걱정이 **292pt 에서 훨씬 급해졌다**. 이름 칸은 `lineLimit(1)` +
    // `Spacer(minLength: 4)` 라 압축 순서가 SwiftUI 기본값에 맡겨져 있는데, 이름이 말줄임되지 않고
    // 옆 요소를 밀어내면 그것이 화면 밖으로 나간다.
    //
    // v0.2.50 의 배치 변경(상태 칩을 이름 줄에서 **메타 줄로** 내렸다)이 지키는 것이 정확히 이 성질이다.
    let store = fbMenuStore(fbInboxStore(host: "fb-render-long-name", rows: 3))
    // 20자 이상(한글 24자). 실제로 이렇게 긴 별명이 가능하다 — 화면은 그걸 감당해야 한다.
    let longName = "아주아주긴이름을가진동료사람입니다요"
    #expect(longName.count >= 17)
    store.feedbackList = store.feedbackList.enumerated().map { index, report in
        FeedbackReport(
            id: report.id, userID: report.userID, kind: report.kind, body: report.body,
            status: report.status, adminNote: report.adminNote,
            appVersion: report.appVersion, osVersion: report.osVersion,
            createdAt: report.createdAt, updatedAt: report.updatedAt,
            // 첫 행은 **말줄임이 반드시 일어나는** 길이로 준다(51자).
            authorName: index == 0 ? String(repeating: longName, count: 3) : longName,
            authorAvatarURL: nil
        )
    }
    // 첫 행은 펼쳐 둔다 — 상태 버튼이 **넷**이라 292pt 에서 그 줄도 함께 확인해야 한다.
    store.expandedFeedbackID = store.feedbackList[0].id
    store.feedbackNoteDraft = "샘플 메모"

    let bitmap = try fbPanelBitmap(store)
    FeedbackSnapshots.save(bitmap, name: "panels-feedback-long-name.png")
    #expect(bitmap.pixelsWide == 414 * 2, "긴 이름이 팝오버 폭을 밀어냈다")
    #expect(Double(bitmap.pixelsHigh) / 2.0 <= fbPopoverHeightCap)

    let blank = try fbBlankBitmap(matching: bitmap)
    let ink = try #require(fbDiffBounds(bitmap, blank), "화면이 통째로 비었다")
    #expect(ink.maxX <= CGFloat(bitmap.pixelsWide) - 2, "292pt 에서 내용이 오른쪽으로 넘쳤다(상태 칩이 잘린다)")
    #expect(ink.minX >= 4, "292pt 에서 내용이 왼쪽 밖에서 시작한다")

    // 이름이 길다고 그림이 짧은 이름 판과 **같아지면** 안 된다(같으면 이름이 아예 안 그려진 것이다).
    let shortName = fbMenuStore(fbInboxStore(host: "fb-render-short-name", rows: 3))
    shortName.expandedFeedbackID = "row-0"
    shortName.feedbackNoteDraft = "샘플 메모"
    let shortBitmap = try fbPanelBitmap(shortName)
    #expect(fbDiffBounds(bitmap, shortBitmap) != nil, "긴 이름이 화면에 아무 흔적도 남기지 않았다")
}

@MainActor
@Test
func theFeedbackPanelStaysUnderTheCapWithTheTallestChromeOnTop() throws {
    // ★ **이 작업 최악의 결함이 창 높이 회귀다.** 배너 + 목표 편집 행이 겹친 가장 키 큰 조합까지 그려
    //   700pt 를 안 넘고 푸터가 살아 있는지 본다(넘으면 로그아웃 버튼이 화면 밖으로 나간다).
    //
    // **첫 판은 여기서 728pt 로 빨개졌다**(에디터 5줄 + 목록만 깎는 예산). 그 실측이 `FeedbackPanelLayout`
    // 의 두 부등식과 "보내기 탭은 본문 전체가 예산을 진다"는 구조를 만들었다.
    for (label, store) in [
        ("send", fbMenuStore(fbStore(host: "fb-tallest-send"))),
        ("inbox", fbMenuStore(fbInboxStore(host: "fb-tallest-inbox", rows: 12)))
    ] {
        store.feedbackDraft = String(repeating: "가나다라마바사아자차 ", count: 8)
        store.feedbackNotice = FeedbackText.rateLimited
        if label == "inbox" {
            store.expandedFeedbackID = "row-0"
            store.feedbackNoteDraft = "샘플 메모"
        } else {
            store.feedbackList = (0..<6).map { fbReport(id: "m\($0)", createdAt: fbRenderNow) }
            store.feedbackLoaded = true
        }
        // 새 버전 배너 + 패치노트 4줄(149pt) + 주간 목표 편집 인라인 행(92pt) = **241pt**(위 상수 주석).
        let bitmap = try fbPanelBitmap(store, worstChrome: true)
        FeedbackSnapshots.save(bitmap, name: "panels-feedback-tallest-\(label).png")
        let height = Double(bitmap.pixelsHigh) / 2.0
        #expect(height <= fbPopoverHeightCap, "\(label) 최악 조합이 700pt 를 넘었다: \(height)pt")
        let blank = try fbBlankBitmap(matching: bitmap)
        let ink = try #require(fbDiffBounds(bitmap, blank))
        #expect(ink.maxY > CGFloat(bitmap.pixelsHigh) - 60, "\(label) 최악 조합에서 푸터가 안 그려졌다")
    }
}

@MainActor
@Test
func aNonAdminNeverGetsAnInboxTabNotEvenAHiddenOne() throws {
    // ★ 감춤이 아니라 **미생성**이다. `opacity 0`/`hidden` 으로 두면 접근성 트리와 키보드 순회에는 남아 있어
    //   탭 키만으로 그 표면에 닿는다.
    #expect(CheckFeedbackView.visibleTabs(isAdmin: false) == [.send])
    #expect(CheckFeedbackView.visibleTabs(isAdmin: true) == [.send, .inbox])

    // 낡은 탭 선택이 남아 있어도 관리자가 아니면 받은 제보 화면이 그려지지 않는다.
    let user = fbMenuStore(fbStore(host: "fb-render-nonadmin", admin: false))
    user.feedbackShowsInbox = true
    user.feedbackList = [fbReport(id: "x", owner: fbOtherID, body: "남의 샘플 본문")]
    user.feedbackLoaded = true
    #expect(!user.showsFeedbackInbox)
    let userBitmap = try fbPanelBitmap(user)
    FeedbackSnapshots.save(userBitmap, name: "panels-feedback-send-nonadmin.png")

    // 관리자 화면과 **그림이 달라야** 한다(같으면 비관리자에게 받은 제보가 그려지고 있다는 뜻이다).
    let admin = fbMenuStore(fbInboxStore(host: "fb-render-admin-cmp", rows: 3))
    let adminBitmap = try fbPanelBitmap(admin)
    var differs = adminBitmap.pixelsHigh != userBitmap.pixelsHigh
    if !differs {
        for y in stride(from: 0, to: min(userBitmap.pixelsHigh, adminBitmap.pixelsHigh), by: 8) {
            for x in stride(from: 0, to: min(userBitmap.pixelsWide, adminBitmap.pixelsWide), by: 8) {
                if userBitmap.colorAt(x: x, y: y) != adminBitmap.colorAt(x: x, y: y) { differs = true; break }
            }
            if differs { break }
        }
    }
    #expect(differs, "비관리자 화면이 관리자 화면과 똑같이 그려졌다")
}

// MARK: - 진단 자동 첨부(설정 창 → 제보) — 2026-09-10

// 사용자 지적(스크린샷과 함께): 설정 창 하단의 진단 두 줄을 가리키며 "이건 뭐야? 왜 넣은 거야?
// **빼는 게 맞지 않아?**" — 맞다. 다만 지우는 게 아니라 **옮긴다.** 설정은 팀원 전원이 여는 화면이고
// 그들에게 `idle(disabled) · 재연결 0회` 는 암호문이다. 정작 볼 사람은 운영자인데, 신고가 오면
// "설정 열어서 하단 두 줄 찍어 보내주세요"를 매번 부탁해야 했다.
//
// 아래가 지키는 계약은 넷이다:
//  ① 제보를 보내면 그 두 줄이 본문 뒤에 **자동으로** 붙는다.
//  ② 붙이느라 **사용자 글이 잘리는 일은 절대 없다**(자리가 모자라면 진단이 줄거나 빠진다).
//  ③ 값이 없으면 빈 줄을 붙이지 않는다.
//  ④ 설정 창에는 그 두 줄이 더 이상 없다.

@Test
func aReportCarriesTheConnectionStateBehindASeparator() throws {
    let lines = [
        "초인종 idle(disabled) · 전송자 없음 · 재연결 0회 · 따라잡기 없음",
        "근무 틱 work_tick 사용 · 성공 3회 · 폴백 0회"
    ]
    let composed = FeedbackDiagnostics.compose(body: "찌르기가 안 와요", lines: lines)

    // 사용자 글이 **맨 앞에 그대로** 있다 — 운영자 받은함에서 첫 줄은 사람의 말이어야 한다.
    #expect(composed.hasPrefix("찌르기가 안 와요"))
    for line in lines { #expect(composed.contains(line), "진단이 본문에 안 실렸다: \(line)") }
    #expect(composed.contains(FeedbackDiagnostics.marker), "구분선이 없다 — 받은 쪽이 판을 가를 근거가 없다")

    // 그리고 **되돌릴 수 있다**(받은 제보 화면이 이 판정으로 사람 글과 기계 줄을 가른다).
    let parts = FeedbackDiagnostics.split(composed)
    #expect(parts.body == "찌르기가 안 와요", "가르고 났더니 사용자 글이 달라졌다: \(parts.body)")
    let diagnostics = try #require(parts.diagnostics, "진단을 붙였는데 가른 결과가 비었다")
    #expect(diagnostics.contains("초인종") && diagnostics.contains("근무 틱"))
    // 표식 자체는 어느 쪽에도 남지 않는다 — 화면은 판으로 가르지 구분선을 그려 보이지 않는다.
    #expect(!parts.body.contains(FeedbackDiagnostics.marker))
    #expect(!diagnostics.contains(FeedbackDiagnostics.marker))

    // 표식이 없는 본문(이 변경 이전의 제보 · 진단이 자리 부족으로 빠진 제보)은 **전부가 사용자 글**이다.
    let plain = FeedbackDiagnostics.split("그냥 쓴 글")
    #expect(plain.body == "그냥 쓴 글" && plain.diagnostics == nil, "없는 진단을 지어냈다")

    // 사용자가 표식을 직접 쳐 넣었어도 **우리가 붙인 마지막 것**이 기준이다(우리 것은 언제나 맨 뒤다).
    let sneaky = FeedbackDiagnostics.compose(
        body: "앞글\n\n\(FeedbackDiagnostics.marker)\n내가 친 줄", lines: ["초인종 subscribed"]
    )
    let sneakyParts = FeedbackDiagnostics.split(sneaky)
    #expect(sneakyParts.diagnostics == "초인종 subscribed", "사용자가 친 표식이 진짜 진단을 밀어냈다")
    #expect(sneakyParts.body.contains("내가 친 줄"), "사용자가 쓴 글이 진단 판으로 끌려갔다")
}

@Test
func theUsersWordsAreNeverTruncatedToMakeRoomForDiagnostics() {
    // ★ 이 묶음에서 가장 중요한 단언이다. 본문 상한 1000자는 **서버 제약**이라, 진단을 붙였다고 글이
    //   잘리거나 전송이 거절되면 그건 진단이 사용자를 방해한 것이다 — 그 사용자는 두 번 다시 제보하지 않는다.
    let lines = [
        "초인종 idle(disabled) · 전송자 없음 · 재연결 0회 · 따라잡기 없음",
        "근무 틱 work_tick 사용 · 성공 3회 · 폴백 0회"
    ]

    // ① 딱 상한까지 쓴 글: 진단이 통째로 빠지고 글은 **한 글자도** 안 줄어든다.
    let full = String(repeating: "가", count: FeedbackComposer.maxBodyLength)
    let composedFull = FeedbackDiagnostics.compose(body: full, lines: lines)
    #expect(composedFull == full, "상한까지 쓴 글에 진단을 욱여넣었다(길이 \(composedFull.count))")
    #expect(FeedbackComposer.isSendable(composedFull), "진단을 붙여 서버가 거절할 본문을 만들었다")

    // ② 한 줄만 들어갈 자리: **초인종이 남는다.** "찌르기가 안 와요"가 이 경로가 생긴 이유다.
    //    경계 길이를 손으로 박지 않는다 — 구분선이나 진단 문구가 한 글자만 바뀌어도 그 숫자는 거짓이 되고,
    //    그러면 이 테스트는 "한 줄만 들어가는 자리"가 아닌 다른 상황을 재고 있게 된다(초록인 채로).
    let bothLength = FeedbackDiagnostics.measured(FeedbackDiagnostics.attachment(lines) ?? "")
    let almost = String(repeating: "가", count: FeedbackComposer.maxBodyLength - bothLength + 1)
    let composedAlmost = FeedbackDiagnostics.compose(body: almost, lines: lines)
    #expect(composedAlmost.hasPrefix(almost), "사용자 글이 앞에서부터 바뀌었다")
    #expect(composedAlmost.contains(lines[0]), "자리가 있는데 초인종 줄까지 버렸다")
    #expect(!composedAlmost.contains(lines[1]), "자리가 없는데 근무 틱 줄을 욱여넣었다")
    #expect(FeedbackDiagnostics.measured(composedAlmost) <= FeedbackComposer.maxBodyLength)

    // ③ 넉넉한 글: 둘 다 붙고, 그래도 상한 안이다.
    let short = String(repeating: "가", count: 100)
    let composedShort = FeedbackDiagnostics.compose(body: short, lines: lines)
    #expect(composedShort.contains(lines[0]) && composedShort.contains(lines[1]))
    #expect(FeedbackDiagnostics.measured(composedShort) <= FeedbackComposer.maxBodyLength)

    // ④ 어느 갈래에서도 사용자 글은 **원문 그대로** 복원된다.
    for (body, composed) in [(full, composedFull), (almost, composedAlmost), (short, composedShort)] {
        #expect(FeedbackDiagnostics.split(composed).body == body, "가르고 났더니 사용자 글이 달라졌다")
    }

    // ⑤ 이모지 글: 서버는 코드포인트로 세고 화면 카운터는 자소 묶음으로 센다. **작은 쪽으로 자리를 재면**
    //    진단을 붙인 순간 사용자 글까지 함께 거절당한다 — 그래서 여기서만 큰 쪽으로 센다.
    let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 200)   // 자소 200 · 코드포인트 1400
    #expect(emoji.count < emoji.unicodeScalars.count, "이 표본이 두 세는 법을 가르지 못한다")
    #expect(FeedbackDiagnostics.compose(body: emoji, lines: lines) == emoji,
            "코드포인트로는 이미 상한을 넘긴 글에 진단을 더 얹었다")
}

@Test
func blankDiagnosticsAreNeverPastedIntoSomeonesReport() {
    // 값 없이 이름표만 붙은 줄("초인종 ")은 운영자에게 아무것도 말해 주지 않으면서 본문 자리만 먹는다.
    #expect(FeedbackDiagnostics.line(label: "초인종", value: "") == nil)
    #expect(FeedbackDiagnostics.line(label: "초인종", value: "   \n ") == nil)
    #expect(FeedbackDiagnostics.line(label: "초인종", value: "idle(disabled)") == "초인종 idle(disabled)")

    // 전부 비면 본문은 **손도 안 댄다**(구분선만 덩그러니 붙은 본문이 가장 나쁘다).
    #expect(FeedbackDiagnostics.compose(body: "찌르기가 안 와요", lines: []) == "찌르기가 안 와요")
    let allBlank = FeedbackDiagnostics.compose(body: "찌르기가 안 와요", lines: ["", "  "])
    #expect(allBlank == "찌르기가 안 와요")
    #expect(!allBlank.contains(FeedbackDiagnostics.marker), "붙일 진단이 없는데 구분선을 그었다")
    #expect(FeedbackDiagnostics.attachment(["", " "]) == nil)
    // 한쪽만 비면 나머지 한 줄은 그대로 간다(둘 다 잃지 않는다).
    let half = FeedbackDiagnostics.compose(body: "찌르기가 안 와요", lines: ["", "근무 틱 work_tick 사용"])
    #expect(half.contains("근무 틱 work_tick 사용") && half.contains(FeedbackDiagnostics.marker))
}

@MainActor
@Test
func theConnectionStateIsAttachedWhenTheReportActuallyGoesOut() async throws {
    // 스토어 왕복. 팀원은 "찌르기가 안 와요" 한 줄만 쓰면 되고, 운영자 받은함에는 그 사람의 연결 상태가
    // **이미 붙어서** 도착한다 — 그게 설정 창에서 두 줄을 걷어낼 수 있었던 이유다.
    let host = "fb-diagnostics-ride-along"
    let store = fbStore(host: host)
    FeedbackURLProtocol.set(
        .init(status: 200, body: #""11111111-1111-1111-1111-111111111111""#),
        host: host,
        path: "/rest/v1/rpc/submit_feedback"
    )
    store.feedbackDraft = "찌르기가 안 와요"
    #expect(!store.feedbackDiagnosticsLines.isEmpty, "보낼 진단이 한 줄도 없다 — 이 테스트가 아무것도 재현하지 못한다")

    store.sendFeedback()
    await fbWait { !store.isSendingFeedback && store.feedbackNotice != nil }
    #expect(store.feedbackNotice == FeedbackText.sendSuccess)

    let sent = FeedbackURLProtocol.sentBodies(host: host, path: "/rest/v1/rpc/submit_feedback")
    #expect(sent.count == 1)
    let raw = try #require(sent.first)
    let payload = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
    let body = try #require(payload["p_body"] as? String)
    let parts = FeedbackDiagnostics.split(body)
    #expect(parts.body == "찌르기가 안 와요")
    // `.idle(.disabled)`(전송자 없음)는 **값이 없는 것이 아니라** 바로 그 신고의 답이다 —
    // 침묵으로 접으면 이 경로가 생긴 이유의 절반이 사라진다.
    #expect(parts.diagnostics?.contains("idle(disabled)") == true, "연결 상태가 안 실렸다: \(body)")
    #expect(parts.diagnostics?.contains("work_tick") == true, "근무 틱 상태가 안 실렸다: \(body)")
    // 초안에는 손대지 않았다 — 진단은 **전송 본문에서만** 붙는다(사용자가 쓰던 글을 앱이 고치지 않는다).
    #expect(store.feedbackDraft.isEmpty, "성공했는데 초안이 남았다")
}

@Test
func theAutoAttachNoticeGrowsWithWhatIsActuallySent() {
    // 몰래 보내지 않는다 — 실어 보내는 것이 늘었으면 **밝히는 문장도** 늘어야 한다.
    let withDiagnostics = FeedbackText.autoAttachNotice(
        appVersion: "0.2.48", build: 58, osVersion: "15.6", includesDiagnostics: true
    )
    #expect(withDiagnostics.contains(FeedbackText.diagnosticsTerm),
            "연결 상태가 함께 간다는 사실을 안 밝힌다: \(withDiagnostics)")
    #expect(withDiagnostics.contains("0.2.48") && withDiagnostics.contains("58") && withDiagnostics.contains("15.6"))
    #expect(withDiagnostics.hasSuffix("정보가 함께 전송돼요"), "약속하는 꼬리가 바뀌었다: \(withDiagnostics)")
    // 팀원이 읽는 문장이다 — 내부 어휘(work_tick · realtime)를 여기로 흘리지 마라.
    let lowered = withDiagnostics.lowercased()
    #expect(!lowered.contains("work_tick") && !lowered.contains("realtime") && !withDiagnostics.contains("_"))

    // ★ 붙일 진단이 없으면 **말하지도 않는다.** 그때의 문장은 원본
    //   `autoAttachNotice(appVersion:build:osVersion:)`(SupabaseWorkModels.swift — 이번 작업의 소유가
    //   아니라 못 고친다)과 **한 글자도 다르지 않아야** 한다. 둘이 갈리면 같은 화면 문구가 두 벌이 된다.
    let cases: [(String, Int?, String)] = [("0.2.48", 58, "15.6"), ("", nil, "15.6"), ("0.2.48", 0, "26.0")]
    for (version, build, os) in cases {
        let quiet = FeedbackText.autoAttachNotice(appVersion: version, build: build, osVersion: os, includesDiagnostics: false)
        #expect(quiet == FeedbackText.autoAttachNotice(appVersion: version, build: build, osVersion: os),
                "진단 없는 문장이 원본과 갈렸다: \(quiet)")
        #expect(!quiet.contains(FeedbackText.diagnosticsTerm), "안 보내는 것을 보낸다고 말한다: \(quiet)")
    }
}

@MainActor
@Test
func theStoreOnlyPromisesTheConnectionStateWhenItHasOne() {
    let store = fbStore(host: "fb-diagnostics-notice")
    #expect(store.feedbackDiagnosticsLines.count == 2, "초인종·근무 틱 두 줄이 나와야 한다")
    #expect(store.feedbackDiagnosticsLines[0].hasPrefix(FeedbackText.realtimeDiagnosticsLabel))
    #expect(store.feedbackDiagnosticsLines[1].hasPrefix(FeedbackText.workTickDiagnosticsLabel))
    // 화면 안내가 그 사실과 **같은 값**에서 나온다(둘이 따로 놀면 몰래 보내거나 헛말을 하게 된다).
    #expect(store.feedbackAutoAttachNotice.contains(FeedbackText.diagnosticsTerm))
    #expect(store.feedbackAutoAttachNotice.contains("0.2.48") && store.feedbackAutoAttachNotice.contains("15.6"))
}

@Test
func theSettingsWindowNoLongerCarriesTheDiagnosticsFootnotes() throws {
    // ★ 소스 계약. **주석을 걷어내고** 센다 — 안 그러면 "왜 사라졌는지"를 적어 둔 그 주석 때문에
    //   테스트가 빨개지고, 다음 사람은 설명을 지워야만 초록을 되찾는다(이 저장소가 겪은 함정이다).
    let settings = try String(contentsOf: fbSourceURL("CheckSettingsView.swift"), encoding: .utf8)
    let code = fbStrippingComments(settings)
    for gone in ["DiagnosticsFootnote", "RealtimeDiagnosticsRow", "WorkTickDiagnosticsRow",
                 "realtimeDiagnosticsLine", "workTickDiagnosticsLine"] {
        #expect(!code.contains(gone), "설정 창에 진단 두 줄이 남아 있다(\(gone)) — 팀원 전원이 여는 화면이다")
    }
    // 그리고 **없어진 게 아니라 옮겨 간 것**이라는 자국이 남아 있다(주석까지 포함해 읽는다).
    // 이게 없으면 다음 사람이 "진단이 없어졌네" 하고 같은 각주를 다시 만든다.
    #expect(settings.contains("FeedbackDiagnostics"), "옮겨 간 곳을 가리키는 자국이 없다")

    // 반대편: 진단 줄 자체는 살아 있고, 이제 제보가 그것을 부른다.
    let feedback = fbStrippingComments(try String(contentsOf: fbSourceURL("WorkTimerStoreFeedback.swift"), encoding: .utf8))
    #expect(feedback.contains("realtimeDiagnosticsLine") && feedback.contains("workTickDiagnosticsLine"),
            "설정에서 걷어내면서 진단 자체를 죽였다 — 그럼 신고를 가를 표면이 하나도 없다")
}

// MARK: - 렌더 스냅샷: 진단이 옮겨 간 뒤의 화면들

@MainActor
@Test
func theMachineLinesReadAsMachineLinesAndNeverEatThePreview() throws {
    let now = Date(timeIntervalSince1970: 1_789_000_000)
    let lines = [
        "초인종 idle(disabled) · 전송자 없음 · 재연결 0회 · 따라잡기 없음",
        "근무 틱 work_tick 사용 · 성공 12회 · 폴백 0회 · 시계차 +0.4s"
    ]

    /// 첫 행만 진단이 붙은 제보로 바꾼 관리자 목록(운영자가 실제로 받게 될 모양).
    func inbox(host: String, attached: Bool, expanded: Bool) -> WorkTimerStore {
        let store = fbInboxStore(host: host, rows: 3)
        // **앞뒤 공백이 없는 글**로 만든다. compose 는 본문을 정규화(trim)하므로, 꼬리에 공백이 남은
        // 원문을 쓰면 진단 유무로 줄바꿈이 달라져 아래 ②(접힘은 그림이 같아야 한다)가 거짓으로 빨개진다.
        let userText = ("샘플 본문 0 — 찌르기가 안 와요. " + String(repeating: "가나다라마바사아자차 ", count: 6))
            .trimmingCharacters(in: .whitespaces)
        let body = attached ? FeedbackDiagnostics.compose(body: userText, lines: lines) : userText
        let first = store.feedbackList[0]
        store.feedbackList[0] = FeedbackReport(
            id: first.id, userID: first.userID, kind: first.kind, body: body, status: first.status,
            adminNote: first.adminNote, appVersion: first.appVersion, osVersion: first.osVersion,
            createdAt: first.createdAt, updatedAt: first.updatedAt,
            authorName: first.authorName, authorAvatarURL: first.authorAvatarURL
        )
        if expanded { store.expandedFeedbackID = first.id }
        return store
    }

    // ① 펼친 행 — 진단이 **본문과 다른 판**에 선다. 진단 없는 판과 그림이 달라야 한다(같으면 안 그린 것이다).
    let expanded = try fbPanelBitmap(fbMenuStore(inbox(host: "fb-diag-expanded", attached: true, expanded: true)))
    FeedbackSnapshots.save(expanded, name: "panels-feedback-diagnostics.png")
    let expandedPlain = try fbPanelBitmap(fbMenuStore(inbox(host: "fb-diag-expanded-plain", attached: false, expanded: true)))
    #expect(fbDiffBounds(expanded, expandedPlain) != nil,
            "진단이 붙었는데 펼친 행 그림이 그대로다 — 운영자에게 아무것도 안 보인다")

    // ② 접힌 행 — 기계가 붙인 줄이 2줄 미리보기를 **먹지 않는다.** 진단 유무로 그림이 같아야 한다.
    //    (여기서 픽셀이 달라졌다면 목록에서 제보 내용 대신 `idle(disabled)` 를 읽고 있다는 뜻이다.)
    let collapsed = try fbPanelBitmap(fbMenuStore(inbox(host: "fb-diag-collapsed", attached: true, expanded: false)))
    let collapsedPlain = try fbPanelBitmap(fbMenuStore(inbox(host: "fb-diag-collapsed-plain", attached: false, expanded: false)))
    #expect(fbDiffBounds(collapsed, collapsedPlain) == nil,
            "접힌 목록에 기계가 붙인 줄이 새어 나왔다 — 미리보기 두 줄은 사람이 쓴 글의 자리다")

    // ③ 보내기 탭 — 무엇이 함께 가는지 밝히는 한 줄에 연결 상태가 들어 있다.
    let send = fbMenuStore(fbStore(host: "fb-diag-send"))
    send.feedbackDraft = "찌르기가 안 와요"
    #expect(send.feedbackAutoAttachNotice.contains(FeedbackText.diagnosticsTerm))
    let sendBitmap = try fbPanelBitmap(send)
    let blank = try fbBlankBitmap(matching: sendBitmap)
    #expect(fbDiffBounds(sendBitmap, blank) != nil, "보내기 탭이 통째로 비었다")
    _ = now
}

// MARK: - 소스 계약 헬퍼

private func fbSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/check/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(문자열 리터럴 안의 `//` 는 남긴다).
/// **소스 계약 테스트는 반드시 이걸 통과시킨다** — 안 그러면 "왜 이렇게 했는지"를 적은 주석이 단언에 걸려,
/// 다음 사람이 설명을 지워야만 초록이 된다(이 저장소가 실제로 겪은 함정이다).
private func fbStrippingComments(_ source: String) -> String {
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
