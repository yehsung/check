import AppKit
import Foundation
import SwiftUI
import Testing
import CheckRenderTestSupport
@testable import check
@testable import CheckCore

// 제보 화면 캡처(11-11 — 대표 #d_x5kYyOPOeLlH · 계약 v2 §3) — 보내기 순서 · 실패 갈래 · 목록 옆 한 번 · 필요할 때 보기 · 화면.
//
// 이 스위트가 지키는 것:
//  ① 순서: `submit_feedback`(예전 네 키 그대로) → 캡처마다 저장소 올리기(`feedback-shots/<uid>/<제보 id>/<uuid>.jpg`, 소문자 ·
//     image/jpeg · upsert 없음) → `feedback_attach_shot`(키 넷). 제보 id 는 submit 의 반환값을 소문자로 쓴다.
//  ② 캡처가 없으면 예전 그대로다(네 키 · 저장소 안 부름).
//  ③ 캡처가 실패해도 제보는 보낸 것이다 — 글은 다시 안 보내고, 글 · 캡처를 비우고 한 줄로 말한다(일부 · 전부 · 문 닫힘 · 상한).
//  ④ 목록 뒤 `feedback_shots` 는 **비어 있지 않을 때 한 번** · 404 는 입구를 숨기고 패널을 다시 열면 다시 묻는다.
//  ⑤ 그림은 사람이 연 자리에서만 서명 URL 로 받고, 받은 것은 스토어에 남는다. 로그아웃은 전부 비운다.
//  ⑥ 응답은 **서비스 디코더**(convertFromSnakeCase)로 읽힌다 — 대조군으로 평범한 디코더가 실제로 놓친다는 것을 함께 잰다.
//  ⑦ 화면: 붙이기 줄(캡처 둘 + 경고) · 내 제보 칩 · 받은 제보 썸네일 · 크게 보기 — PNG 는 `FEATURE_SHOTS_DIR` 이 있을 때만 쓴다.
//
// ★ 픽스처 그림은 전부 **코드로 그린 합성 그림**이다. 실제 화면 캡처를 픽스처로 옮겨 오지 마라 — 테스트 파일은 퍼블릭 저장소에 남는다.
// 네트워크는 아래 `FeedbackShotURLProtocol`(테스트별 고유 호스트)로 막는다.

private let fsUser = "00000000-0000-0000-0000-00000000000b"
private let fsOther = "00000000-0000-0000-0000-00000000000c"
private let fsNow = Date(timeIntervalSince1970: 1_789_000_000)
/// submit_feedback 이 돌려주는 제보 id — 일부러 **대문자**로 준다(경로 · 본문은 소문자여야 한다).
private let fsReturnedID = "ABCDEF01-2345-6789-ABCD-EF0123456789"
private let fsReportID = fsReturnedID.lowercased()

private let fsSubmitPath = "/rest/v1/rpc/submit_feedback"
private let fsListPath = "/rest/v1/rpc/feedback_list"
private let fsShotsPath = "/rest/v1/rpc/feedback_shots"
private let fsAttachPath = "/rest/v1/rpc/feedback_attach_shot"

// MARK: - 격리된 네트워크(순서 · 메서드까지 적는다)

/// 호스트 × (메서드) × 경로별 (상태, 본문)을 심고, 나간 요청을 **순서대로** 적는 스텁. 서명 POST 와 서명 URL GET 은 경로가 같아
/// 메서드 답이 경로 답보다 먼저다. 기본 답은 200 `[]`.
final class FeedbackShotURLProtocol: URLProtocol {
    struct Sent: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        func header(_ name: String) -> String? {
            headers.first { $0.key.lowercased() == name.lowercased() }?.value
        }

        var json: [String: Any]? {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var replies: [String: [String: (Int, Data)]] = [:]
    /// 차례 답: 같은 경로를 여러 번 부를 때 순서대로 하나씩 꺼낸다(다 쓰면 위 고정 답).
    private nonisolated(unsafe) static var queued: [String: [String: [(Int, Data)]]] = [:]
    private nonisolated(unsafe) static var sent: [String: [Sent]] = [:]

    static func reset(host: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host] = nil
        queued[host] = nil
        sent[host] = nil
    }

    static func enqueue(status: Int, body: String, host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        queued[host, default: [:]][path, default: []].append((status, Data(body.utf8)))
    }

    static func set(status: Int, body: String, host: String, path: String, method: String? = nil) {
        set(status: status, data: Data(body.utf8), host: host, path: path, method: method)
    }

    static func set(status: Int, data: Data, host: String, path: String, method: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        let key = method.map { "\($0) \(path)" } ?? path
        replies[host, default: [:]][key] = (status, data)
    }

    static func log(host: String) -> [Sent] {
        lock.lock(); defer { lock.unlock() }
        return sent[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackShotURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let entry = Sent(
            method: request.httpMethod ?? "",
            path: path,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.bodyData(request)
        )
        Self.lock.lock()
        Self.sent[host, default: []].append(entry)
        var reply = Self.replies[host]?["\(entry.method) \(path)"] ?? Self.replies[host]?[path] ?? (200, Data("[]".utf8))
        if var line = Self.queued[host]?[path], !line.isEmpty {
            reply = line.removeFirst()
            Self.queued[host]?[path] = line
        }
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.0, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - 도우미

/// 차례로 다른 파일 이름을 내주는 이음새(시도마다 새 uuid 인지 재려고).
@MainActor
private final class FSFileIDs {
    private var next = 1
    func make() -> String {
        defer { next += 1 }
        return String(format: "aaaaaaaa-0000-0000-0000-%012d", next)
    }
}

private func fsService(host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackShotURLProtocol.session()
    )
}

@MainActor
private func fsStore(host: String, admin: Bool = false, function: String = #function) -> WorkTimerStore {
    FeedbackShotURLProtocol.reset(host: host)
    let store = WorkTimerStore(
        service: fsService(host: host),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: CheckTestScratch.defaults(host, function: function)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: fsUser)
    store.ultraUnlimited = admin
    store.appVersionProvider = { AppVersionReport(build: 139, version: "0.3.86") }
    store.osVersionProvider = { "15.6" }
    let ids = FSFileIDs()
    store.feedbackShotFileID = { ids.make() }
    return store
}

/// 400×10ms(≈4초 상한) — 이미지 줄이기가 백그라운드라 제보 테스트보다 넉넉히 기다린다.
@MainActor
private func fsWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<400 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// 코드로 그린 합성 "화면" PNG. 창 하나 · 말풍선 몇 개 모양의 색 상자뿐이다(글자 없음).
@MainActor
private func fsSyntheticPNG(width: Int, height: Int, tint: NSColor = NSColor(calibratedRed: 0.33, green: 0.67, blue: 1, alpha: 1)) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let w = CGFloat(width), h = CGFloat(height)
    NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1).setFill()
    NSRect(x: 0, y: h * 0.9, width: w, height: h * 0.1).fill()
    for index in 0..<4 {
        let y = h * (0.12 + 0.19 * CGFloat(index))
        (index % 2 == 0 ? tint : NSColor(calibratedRed: 0.8, green: 0.82, blue: 0.86, alpha: 1)).setFill()
        let x = index % 2 == 0 ? w * 0.08 : w * 0.42
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w * 0.5, height: h * 0.12), xRadius: 12, yRadius: 12).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

private enum FSError: Error { case failed }

@MainActor
private func fsDraft(width: Int = 1200, height: Int = 800, tint: NSColor = .systemBlue) throws -> FeedbackShotDraft {
    guard case .jpeg(let jpeg) = FeedbackShotImage.encode(imageData: fsSyntheticPNG(width: width, height: height, tint: tint)) else {
        throw FSError.failed
    }
    return try #require(FeedbackShotImage.draft(fromJPEG: jpeg))
}

/// 받아 둔 그림(JPEG 바이트와 그 그림).
@MainActor
private func fsPicture(tint: NSColor = .systemTeal) throws -> (jpeg: Data, image: NSImage) {
    guard case .jpeg(let jpeg) = FeedbackShotImage.encode(imageData: fsSyntheticPNG(width: 900, height: 600, tint: tint)) else {
        throw FSError.failed
    }
    return (jpeg, try #require(NSImage(data: jpeg)))
}

private func fsFile(_ number: Int) -> String { String(format: "aaaaaaaa-0000-0000-0000-%012d", number) }

/// n 번째로 올린 캡처의 버킷 안 경로.
private func fsShotPath(_ number: Int, report: String = fsReportID) -> String {
    "\(fsUser)/\(report)/\(fsFile(number)).jpg"
}

private func fsUploadURLPath(_ number: Int) -> String {
    "/storage/v1/object/feedback-shots/\(fsShotPath(number))"
}

private let fsRLSRefusal = #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#

/// 합성 제보 한 건. **실제 제보 본문을 여기 옮기지 마라.**
private func fsReport(id: String, owner: String = fsUser, status: FeedbackStatus = .open, body: String = "샘플 본문") -> FeedbackReport {
    FeedbackReport(
        id: id, userID: owner, kind: .bug, body: body, status: status, adminNote: nil,
        appVersion: "0.3.86 (139)", osVersion: "15.6", createdAt: fsNow.addingTimeInterval(-600), updatedAt: fsNow,
        authorName: owner == fsUser ? "나야" : "동료", authorAvatarURL: nil
    )
}

private func fsShot(report: String, number: Int, owner: String = fsUser) -> FeedbackShot {
    FeedbackShot(
        id: String(format: "dddddddd-0000-0000-0000-%012d", number),
        reportID: report,
        path: "\(owner)/\(report)/\(String(format: "eeeeeeee-0000-0000-0000-%012d", number)).jpg",
        width: 1600, height: 1000, createdAt: fsNow
    )
}

/// 보내기 한 번을 끝까지 기다린다(성공 · 실패 모두 — 잠금이 풀리고 안내가 섰다).
@MainActor
private func fsSendAndWait(_ store: WorkTimerStore) async {
    store.sendFeedback()
    await fsWait { !store.isSendingFeedback && store.feedbackNotice != nil && store.feedbackNotice != FeedbackShotText.uploading }
    // 성공 뒤 목록 다시 받기까지 끝나게 한 번 더 양보한다.
    await fsWait { !store.feedbackLoading }
}

// MARK: - ① ② 보내기 순서

@MainActor
@Test
func fbShotSendGoesSubmitThenUploadThenAttachWithExactPathsAndKeys() async throws {
    let host = "fs-send-order"
    let store = fsStore(host: host)
    let first = try fsDraft(width: 1200, height: 800)
    let second = try fsDraft(width: 2400, height: 1500, tint: .systemPink)
    store.feedbackShots = [first, second]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: host, path: fsSubmitPath)
    for number in 1...2 {
        FeedbackShotURLProtocol.set(status: 200, body: #"{"Key":"feedback-shots/x"}"#, host: host, path: fsUploadURLPath(number))
    }
    FeedbackShotURLProtocol.set(status: 200, body: #"{"status":"ok","attachment_id":"99999999-0000-0000-0000-000000000001"}"#,
                                host: host, path: fsAttachPath)
    store.feedbackDraft = "샘플 본문 캡처 둘"
    #expect(store.feedbackAutoAttachNotice.contains(FeedbackShotText.noticeTerm), "캡처가 붙었는데 안내가 그 사실을 말하지 않는다")

    await fsSendAndWait(store)

    let log = FeedbackShotURLProtocol.log(host: host)
    let interesting = log.map(\.path).filter { $0 != fsListPath && $0 != fsShotsPath }
    #expect(interesting == [fsSubmitPath, fsUploadURLPath(1), fsAttachPath, fsUploadURLPath(2), fsAttachPath],
            "순서가 submit → 올리기 → 붙이기가 아니다: \(interesting)")

    // 제출 본문은 캡처가 있어도 예전 네 키 그대로다.
    let submit = try #require(log.first { $0.path == fsSubmitPath })
    #expect(Set(try #require(submit.json).keys) == ["p_kind", "p_body", "p_app_version", "p_os_version"])
    #expect(FeedbackDiagnostics.split(submit.json?["p_body"] as? String ?? "").body == "샘플 본문 캡처 둘", "경로가 본문에 섞였다")

    // 올리기: POST · 로그인 토큰 · apikey · image/jpeg · upsert 없음 · 바이트 그대로 · 경로는 소문자 제보 id 폴더.
    let uploads = log.filter { $0.path.hasPrefix("/storage/v1/object/feedback-shots/") }
    #expect(uploads.count == 2)
    for (upload, shot) in zip(uploads, [first, second]) {
        #expect(upload.method == "POST")
        #expect(upload.header("Authorization") == "Bearer access-token")
        #expect(upload.header("apikey") == "anon-test-key")
        #expect(upload.header("Content-Type") == "image/jpeg")
        #expect(upload.header("x-upsert") == nil, "비공개 버킷 올리기가 덮어쓰기를 연다")
        #expect(upload.body == shot.jpeg, "올린 바이트가 붙인 캡처와 다르다")
        #expect(upload.path == upload.path.lowercased(), "경로에 대문자가 섞였다(서버 정책은 글자 그대로 견준다)")
    }

    // 붙이기: 키 넷 · 제보 id 소문자 · 경로는 버킷 이름 없이 · 크기는 줄인 뒤 픽셀.
    let attaches = log.filter { $0.path == fsAttachPath }.compactMap(\.json)
    #expect(attaches.count == 2)
    for (index, payload) in attaches.enumerated() {
        #expect(Set(payload.keys) == ["p_report", "p_path", "p_width", "p_height"], "\(payload.keys.sorted())")
        #expect(payload["p_report"] as? String == fsReportID)
        #expect(payload["p_path"] as? String == fsShotPath(index + 1))
    }
    #expect(attaches[0]["p_width"] as? Int == 1200 && attaches[0]["p_height"] as? Int == 800)
    #expect(attaches[1]["p_width"] as? Int == 1600 && attaches[1]["p_height"] as? Int == 1000, "긴 변 1600 으로 줄인 크기가 아니다")

    #expect(store.feedbackDraft.isEmpty)
    #expect(store.feedbackShots.isEmpty, "보냈는데 캡처가 남았다 — 다음 제보에 같은 캡처가 또 실린다")
    #expect(store.feedbackNotice == FeedbackText.sendSuccess)
    #expect(log.filter { $0.path == fsSubmitPath }.count == 1)
}

@MainActor
@Test
func fbShotTextOnlySendKeepsTheOldFourKeysAndNeverTouchesStorage() async throws {
    // (가) 캡처 없음. (나) 캡처는 있는데 서버에 기능이 없다고 숨겨진 채 — 보이지 않는 캡처는 실리지 않는다.
    for (label, hidden) in [("none", false), ("hidden", true)] {
        let host = "fs-send-plain-\(label)"
        let store = fsStore(host: host)
        if hidden {
            store.feedbackShots = [try fsDraft()]
            store.markFeedbackShotsMissing()
        }
        FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: host, path: fsSubmitPath)
        store.feedbackDraft = "샘플 본문 \(label)"
        #expect(!store.feedbackAutoAttachNotice.contains(FeedbackShotText.noticeTerm), "\(label): 안 보내는 캡처를 보낸다고 말한다")
        #expect(store.feedbackAutoAttachNotice == FeedbackText.autoAttachNotice(
            appVersion: "0.3.86", build: 139, osVersion: "15.6", includesDiagnostics: !store.feedbackDiagnosticsLines.isEmpty
        ), "\(label): 캡처 없는 안내가 예전 문장과 다르다")

        await fsSendAndWait(store)

        let log = FeedbackShotURLProtocol.log(host: host)
        #expect(log.map(\.path) == [fsSubmitPath, fsListPath], "\(label): 캡처 없는 전송이 다른 곳을 불렀다 — \(log.map(\.path))")
        let payload = try #require(log.first?.json)
        #expect(Set(payload.keys) == ["p_kind", "p_body", "p_app_version", "p_os_version"], "\(label): \(payload.keys.sorted())")
        #expect(store.feedbackNotice == FeedbackText.sendSuccess)
        // 숨어서 안 실린 캡처도 이 제보의 것이었다 — 글과 함께 내린다. 남으면 패널을 다시 열어 줄이 돌아올 때 다음 제보에 실린다.
        #expect(store.feedbackShots.isEmpty, "\(label): 글만 나갔는데 숨은 캡처가 남았다 — 다음(다른) 제보에 따라 나간다")
        store.closeFeedbackPanel()
        store.openFeedbackPanel()
        #expect(store.feedbackShotsForSend.isEmpty, "\(label): 패널을 다시 열자 앞 제보의 캡처가 다시 붙었다")
    }
}

// MARK: - ③ 실패 갈래(제보는 보낸 것이다)

@MainActor
@Test
func fbShotPartialFailuresStillCountTheReportAsSentAndNeverResendTheText() async throws {
    // 셋: ① 올리기 500(다음 것은 계속) ② 올렸지만 붙이기 photo_missing ③ 성공.
    let host = "fs-partial"
    let store = fsStore(host: host)
    store.feedbackShots = [try fsDraft(), try fsDraft(tint: .systemOrange), try fsDraft(tint: .systemGreen)]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: host, path: fsSubmitPath)
    FeedbackShotURLProtocol.set(status: 500, body: "", host: host, path: fsUploadURLPath(1))
    FeedbackShotURLProtocol.set(status: 200, body: "{}", host: host, path: fsUploadURLPath(2))
    FeedbackShotURLProtocol.set(status: 200, body: "{}", host: host, path: fsUploadURLPath(3))
    // 붙이기는 경로가 같다 — 차례 답으로 둘째는 photo_missing, 셋째는 ok.
    FeedbackShotURLProtocol.enqueue(status: 200, body: #"{"status":"photo_missing"}"#, host: host, path: fsAttachPath)
    FeedbackShotURLProtocol.enqueue(status: 200, body: #"{"status":"ok","attachment_id":"x"}"#, host: host, path: fsAttachPath)
    store.feedbackDraft = "샘플 본문 일부 실패"

    await fsSendAndWait(store)

    let log = FeedbackShotURLProtocol.log(host: host)
    #expect(log.filter { $0.path == fsSubmitPath }.count == 1, "캡처가 실패했다고 글을 다시 보냈다")
    #expect(log.filter { $0.path.hasPrefix("/storage/") }.count == 3, "일시 실패 뒤 다음 캡처를 멈췄다")
    let attached = log.filter { $0.path == fsAttachPath }.compactMap { $0.json?["p_path"] as? String }
    #expect(attached == [fsShotPath(2), fsShotPath(3)], "못 올린 캡처를 붙이려 했다: \(attached)")
    #expect(store.feedbackNotice == FeedbackShotText.sentSomeShotsFailed(2))
    #expect(store.feedbackDraft.isEmpty, "제보는 갔는데 글이 남았다 — 다시 누르면 같은 글이 두 번 간다")
    #expect(store.feedbackShots.isEmpty, "제보는 갔는데 캡처가 남았다")
    #expect(!store.isSendingFeedback)

    // 전부 실패면 "캡처는 못 붙였어요".
    let all = "fs-all-fail"
    let allStore = fsStore(host: all)
    allStore.feedbackShots = [try fsDraft(), try fsDraft(tint: .systemOrange)]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: all, path: fsSubmitPath)
    for number in 1...2 { FeedbackShotURLProtocol.set(status: 502, body: "<html>bad gateway</html>", host: all, path: fsUploadURLPath(number)) }
    allStore.feedbackDraft = "샘플 본문 전부 실패"
    await fsSendAndWait(allStore)
    #expect(allStore.feedbackNotice == FeedbackShotText.sentShotsFailed)
    #expect(allStore.feedbackDraft.isEmpty && allStore.feedbackShots.isEmpty)
    #expect(FeedbackShotURLProtocol.log(host: all).filter { $0.path == fsSubmitPath }.count == 1)
}

@MainActor
@Test
func fbShotDoorClosedSaysSoAndStopsUploading() async throws {
    // (가) 저장소가 정책으로 거절(문이 닫히면 저장소가 먼저 막는다) → 붙이기에 까닭을 물으면 unsupported_client.
    let refused = "fs-door-upload"
    let store = fsStore(host: refused)
    store.feedbackShots = [try fsDraft(), try fsDraft(tint: .systemOrange)]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: refused, path: fsSubmitPath)
    FeedbackShotURLProtocol.set(status: 400, body: fsRLSRefusal, host: refused, path: fsUploadURLPath(1))
    FeedbackShotURLProtocol.set(status: 200, body: #"{"status":"unsupported_client","door_open":false}"#, host: refused, path: fsAttachPath)
    store.feedbackDraft = "샘플 본문 문 닫힘"

    await fsSendAndWait(store)

    let log = FeedbackShotURLProtocol.log(host: refused)
    #expect(store.feedbackNotice == FeedbackShotText.sentShotsDoorClosed)
    #expect(!log.contains { $0.path == fsUploadURLPath(2) }, "문이 닫혔는데 다음 캡처를 또 올렸다")
    let probe = try #require(log.first { $0.path == fsAttachPath }?.json, "거절 까닭을 묻지 않았다")
    #expect(probe["p_path"] as? String == fsShotPath(1))
    #expect(log.filter { $0.path == fsSubmitPath }.count == 1)
    #expect(store.feedbackDraft.isEmpty && store.feedbackShots.isEmpty)
    #expect(store.feedbackShotsShown, "문 닫힘은 서버에 기능이 없다는 뜻이 아니다 — 칩 · 받은 캡처까지 숨기지 마라")
    // 붙이기 줄은 이 패널에서 내린다 — 다음 제보에 또 붙이면 같은 답을 듣고 캡처를 줄이고 올렸다 버린다.
    #expect(!store.feedbackShotAttachShown, "문이 닫혔다는 답을 듣고도 붙이기 줄을 그대로 둔다")
    #expect(!store.canAddFeedbackShot)
    store.closeFeedbackPanel()
    store.openFeedbackPanel()
    #expect(store.feedbackShotAttachShown, "패널을 다시 열었는데 문을 다시 묻지 않는다 — 한 번의 답을 영구히 기억했다")

    // (나) 올리기는 됐는데 붙이기가 unsupported_client · door_open 참 — 문은 열렸고 이 앱 판을 안 받았다(서버가 아는 판이 옛것).
    //      "아직 준비 중"이 아니라 최신 앱을 다시 켜라고 말한다.
    let attach = "fs-door-attach"
    let other = fsStore(host: attach)
    other.feedbackShots = [try fsDraft()]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: attach, path: fsSubmitPath)
    FeedbackShotURLProtocol.set(status: 200, body: "{}", host: attach, path: fsUploadURLPath(1))
    FeedbackShotURLProtocol.set(status: 200, body: #"{"status":"unsupported_client","door_open":true}"#, host: attach, path: fsAttachPath)
    other.feedbackDraft = "샘플 본문 문 닫힘 둘"
    await fsSendAndWait(other)
    #expect(other.feedbackNotice == FeedbackShotText.sentShotsAppOutdated, "문이 열렸는데 '아직 준비 중'이라고 말한다")
    #expect(!other.feedbackShotAttachShown && other.feedbackShotsShown)

    // (다) 저장소 거절인데 까닭이 문도 상한도 아니다(한 시간 지남 등) → 멈추고 "못 붙였어요".
    let late = "fs-refused-late"
    let lateStore = fsStore(host: late)
    lateStore.feedbackShots = [try fsDraft(), try fsDraft(tint: .systemOrange)]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: late, path: fsSubmitPath)
    FeedbackShotURLProtocol.set(status: 403, body: fsRLSRefusal, host: late, path: fsUploadURLPath(1))
    FeedbackShotURLProtocol.set(status: 200, body: #"{"status":"photo_missing"}"#, host: late, path: fsAttachPath)
    lateStore.feedbackDraft = "샘플 본문 늦음"
    await fsSendAndWait(lateStore)
    #expect(lateStore.feedbackNotice == FeedbackShotText.sentShotsFailed)
    #expect(!FeedbackShotURLProtocol.log(host: late).contains { $0.path == fsUploadURLPath(2) }, "같은 벽에 또 부딪혔다")
}

@MainActor
@Test
func fbShotTooManyStopsAndNamesTheServerLimit() async throws {
    let host = "fs-too-many"
    let store = fsStore(host: host)
    store.feedbackShots = [try fsDraft(), try fsDraft(tint: .systemOrange)]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: host, path: fsSubmitPath)
    FeedbackShotURLProtocol.set(status: 200, body: "{}", host: host, path: fsUploadURLPath(1))
    FeedbackShotURLProtocol.set(status: 200, body: #"{"status":"too_many","max":3}"#, host: host, path: fsAttachPath)
    store.feedbackDraft = "샘플 본문 상한"

    await fsSendAndWait(store)

    #expect(store.feedbackNotice == FeedbackShotText.sentShotsTooMany(3))
    #expect(store.feedbackNotice?.contains("\(FeedbackShotWire.maxPerReport)장") == true)
    #expect(!FeedbackShotURLProtocol.log(host: host).contains { $0.path == fsUploadURLPath(2) }, "상한인데 다음 캡처를 올렸다")
}

@MainActor
@Test
func fbShotARefusedReportKeepsTextAndCapturesAndUploadsNothing() async throws {
    let host = "fs-submit-fail"
    let store = fsStore(host: host)
    let shot = try fsDraft()
    store.feedbackShots = [shot]
    FeedbackShotURLProtocol.set(status: 500, body: "", host: host, path: fsSubmitPath)
    store.feedbackDraft = "샘플 본문 거절"

    await fsSendAndWait(store)

    #expect(!FeedbackShotURLProtocol.log(host: host).contains { $0.path.hasPrefix("/storage/") || $0.path == fsAttachPath },
            "제보가 안 갔는데 캡처를 올렸다")
    #expect(store.feedbackDraft == "샘플 본문 거절", "실패했는데 글을 지웠다")
    #expect(store.feedbackShots.map(\.id) == [shot.id], "실패했는데 캡처를 내렸다")
    #expect(store.feedbackNotice == FeedbackText.sendFailed)
}

@MainActor
@Test
func fbShotAnUnreadableReportIDStillCountsAsSent() async throws {
    // submit 응답 모양이 달라 id 를 못 읽었다 — 예전처럼 제보는 보낸 것이고, 캡처만 못 붙였다.
    let host = "fs-odd-id"
    let store = fsStore(host: host)
    store.feedbackShots = [try fsDraft()]
    FeedbackShotURLProtocol.set(status: 200, body: #"{"id":"not-a-uuid"}"#, host: host, path: fsSubmitPath)
    store.feedbackDraft = "샘플 본문 이상한 응답"

    await fsSendAndWait(store)

    #expect(store.feedbackNotice == FeedbackShotText.sentShotsFailed)
    #expect(store.feedbackDraft.isEmpty && store.feedbackShots.isEmpty)
    #expect(!FeedbackShotURLProtocol.log(host: host).contains { $0.path.hasPrefix("/storage/") }, "모르는 폴더에 올렸다")
    #expect(FeedbackShotWire.reportID(from: "  \(fsReturnedID)\n") == fsReportID)
    #expect(FeedbackShotWire.reportID(from: "../x") == nil)
}

@MainActor
@Test
func fbShotAMissingAttachFunctionHidesTheEntryUntilThePanelOpensAgain() async throws {
    let host = "fs-attach-404"
    let store = fsStore(host: host)
    store.feedbackShots = [try fsDraft(), try fsDraft(tint: .systemOrange)]
    FeedbackShotURLProtocol.set(status: 200, body: "\"\(fsReturnedID)\"", host: host, path: fsSubmitPath)
    FeedbackShotURLProtocol.set(status: 200, body: "{}", host: host, path: fsUploadURLPath(1))
    FeedbackShotURLProtocol.set(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.feedback_attach_shot in the schema cache"}"#,
                                host: host, path: fsAttachPath)
    store.feedbackDraft = "샘플 본문 함수 없음"

    await fsSendAndWait(store)

    #expect(store.feedbackNotice == FeedbackShotText.sentShotsDoorClosed)
    #expect(!store.feedbackShotsShown, "함수가 없는데 붙이기 줄을 그대로 둔다")
    #expect(!FeedbackShotURLProtocol.log(host: host).contains { $0.path == fsUploadURLPath(2) })
    store.closeFeedbackPanel()
    store.openFeedbackPanel()
    #expect(store.feedbackShotsShown, "패널을 다시 열었는데 다시 묻지 않는다 — 한 번의 404 를 영구히 기억했다")
}

// MARK: - ④ 목록 옆 한 번

@MainActor
@Test
func fbShotListBatchesOneCallOnlyWhenNonEmptyAndDecodesThroughTheService() async throws {
    let host = "fs-list-batch"
    let store = fsStore(host: host)
    let r1 = "11111111-0000-0000-0000-000000000001", r2 = "11111111-0000-0000-0000-000000000002"
    FeedbackShotURLProtocol.set(status: 200, body: """
    [{"id":"\(r1)","user_id":"\(fsUser)","kind":"bug","body":"샘플 1","status":"open"},
     {"id":"\(r2)","user_id":"\(fsUser)","kind":"request","body":"샘플 2","status":"open"}]
    """, host: host, path: fsListPath)
    let late = "\(fsUser)/\(r1)/eeeeeeee-0000-0000-0000-000000000002.jpg"
    let early = "\(fsUser)/\(r1)/eeeeeeee-0000-0000-0000-000000000001.jpg"
    // 서버 응답 그대로(스네이크 키) — 순서는 일부러 섞고, 못 쓸 행(이상한 경로 · 크기 없음)을 하나씩 넣는다.
    FeedbackShotURLProtocol.set(status: 200, body: """
    [{"report_id":"\(r1)","attachment_id":"a2","path":"\(late)","width":1600,"height":900,"created_epoch_ms":1789000002000},
     {"report_id":"\(r1)","attachment_id":"a1","path":"\(early)","width":1200,"height":800,"created_epoch_ms":1789000001000},
     {"report_id":"\(r2)","attachment_id":"a3","path":"../avatars/x.jpg","width":10,"height":10,"created_epoch_ms":1789000003000},
     {"report_id":"\(r2)","attachment_id":"a4","path":"\(fsUser)/\(r2)/eeeeeeee-0000-0000-0000-000000000004.jpg","width":null,"height":10,"created_epoch_ms":1}]
    """, host: host, path: fsShotsPath)

    store.openFeedbackPanel()
    await fsWait { FeedbackShotURLProtocol.log(host: host).contains { $0.path == fsShotsPath } && !store.feedbackShotsByReport.isEmpty }

    let log = FeedbackShotURLProtocol.log(host: host)
    #expect(log.map(\.path) == [fsListPath, fsShotsPath], "목록 뒤 한 번이 아니다: \(log.map(\.path))")
    let payload = try #require(log.last?.json)
    #expect(Set(payload.keys) == ["p_report_ids"])
    #expect(Set(payload["p_report_ids"] as? [String] ?? []) == [r1, r2])
    let shots = store.feedbackShots(forReport: r1)
    #expect(shots.map(\.path) == [early, late], "붙인 순서가 아니다(또는 디코더가 칸을 못 읽었다)")
    #expect(shots.first?.width == 1200 && shots.first?.height == 800 && shots.first?.id == "a1")
    #expect(store.feedbackShots(forReport: r2).isEmpty, "못 쓸 행을 받아들였다")
    #expect(store.feedbackShots(forReport: r1.uppercased()).count == 2, "제보 id 대소문자로 칩이 사라진다")
    #expect(!log.contains { $0.path.hasPrefix("/storage/") }, "목록이 그림까지 받았다 — 그림은 사람이 연 자리에서만")

    // 대조군: 서비스 디코더가 아닌 평범한 디코더는 같은 응답에서 칸을 놓친다(그래서 진짜 경로로 읽어야 한다).
    let raw = Data(#"[{"report_id":"r","attachment_id":"a","path":"u/r/f.jpg","width":1,"height":1,"created_epoch_ms":1}]"#.utf8)
    let naive = try JSONDecoder().decode([FeedbackShotRow].self, from: raw)
    #expect(naive.first?.reportId == nil, "대조군이 무너졌다 — 평범한 디코더가 스네이크 키를 읽는다면 이 시험의 근거를 다시 적어라")

    // 빈 목록이면 부르지 않는다.
    let empty = "fs-list-empty"
    let emptyStore = fsStore(host: empty)
    emptyStore.openFeedbackPanel()
    await fsWait { emptyStore.feedbackLoaded }
    await fsWait { !emptyStore.feedbackLoading }
    #expect(FeedbackShotURLProtocol.log(host: empty).map(\.path) == [fsListPath], "빈 목록인데 캡처를 물었다")
}

@MainActor
@Test
func fbShotTheAdminInboxAsksOnceForEveryRow() async throws {
    let host = "fs-list-admin"
    let store = fsStore(host: host, admin: true)
    let rows = (1...4).map { String(format: "22222222-0000-0000-0000-%012d", $0) }
    let body = rows.map { #"{"id":"\#($0)","user_id":"\#(fsOther)","kind":"bug","body":"샘플","status":"open"}"# }.joined(separator: ",")
    FeedbackShotURLProtocol.set(status: 200, body: "[\(body)]", host: host, path: fsListPath)
    FeedbackShotURLProtocol.set(status: 200, body: #"[{"report_id":"\#(rows[2])","attachment_id":"a","path":"\#(fsOther)/\#(rows[2])/eeeeeeee-0000-0000-0000-000000000001.jpg","width":800,"height":600,"created_epoch_ms":1}]"#,
                                host: host, path: fsShotsPath)
    store.openFeedbackPanel()
    await fsWait { !store.feedbackShotsByReport.isEmpty }
    await fsWait { !store.feedbackLoading }
    let calls = FeedbackShotURLProtocol.log(host: host).filter { $0.path == fsShotsPath }
    #expect(calls.count == 1, "운영자 목록에서 행마다 따로 물었다: \(calls.count)")
    #expect(Set(calls.first?.json?["p_report_ids"] as? [String] ?? []) == Set(rows))
    #expect(store.feedbackShots(forReport: rows[2]).count == 1)
    #expect(store.feedbackShotCells(forReport: rows[2]) == [.idle], "목록이 그림까지 받았다")
}

@MainActor
@Test
func fbShotAMissingListFunctionHidesChipsAndThePanelAsksAgain() async throws {
    let host = "fs-list-404"
    let store = fsStore(host: host)
    let r1 = "33333333-0000-0000-0000-000000000001"
    FeedbackShotURLProtocol.set(status: 200, body: #"[{"id":"\#(r1)","user_id":"\#(fsUser)","kind":"bug","body":"샘플","status":"open"}]"#,
                                host: host, path: fsListPath)
    FeedbackShotURLProtocol.set(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.feedback_shots(p_report_ids) in the schema cache"}"#,
                                host: host, path: fsShotsPath)
    store.feedbackShotsByReport = [r1: [fsShot(report: r1, number: 1)]]
    store.feedbackShots = [try fsDraft()]

    store.openFeedbackPanel()
    await fsWait { !store.feedbackShotsShown }

    #expect(!store.feedbackShotsShown, "함수가 없는데 입구를 그대로 둔다")
    #expect(store.feedbackShots(forReport: r1).isEmpty, "함수가 없는데 칩이 남았다")
    #expect(store.feedbackShotsForSend.isEmpty, "숨긴 캡처가 다음 전송에 실린다")
    #expect(!store.feedbackAutoAttachNotice.contains(FeedbackShotText.noticeTerm))

    // 다시 열면 다시 묻는다(영구히 기억하지 않는다).
    FeedbackShotURLProtocol.set(status: 200, body: "[]", host: host, path: fsShotsPath)
    store.closeFeedbackPanel()
    store.openFeedbackPanel()
    #expect(store.feedbackShotsShown)
    await fsWait { FeedbackShotURLProtocol.log(host: host).filter { $0.path == fsShotsPath }.count == 2 }
    await fsWait { !store.feedbackLoading }
    #expect(FeedbackShotURLProtocol.log(host: host).filter { $0.path == fsShotsPath }.count == 2)
    #expect(store.feedbackShotsShown, "서버가 생긴 뒤에도 입구가 숨어 있다")
}

// MARK: - ⑤ 필요할 때 보기 · 로그아웃

@MainActor
@Test
func fbShotImagesLoadOnlyWhenAskedThroughASignedURLAndStayCached() async throws {
    let host = "fs-view"
    let store = fsStore(host: host, admin: true)
    store.isFeedbackPanelVisible = true
    let r1 = "44444444-0000-0000-0000-000000000001"
    store.feedbackList = [fsReport(id: r1, owner: fsOther)]
    store.feedbackLoaded = true
    let held = fsShot(report: r1, number: 1, owner: fsOther)
    let gone = fsShot(report: r1, number: 2, owner: fsOther)
    store.feedbackShotsByReport = [r1: [held, gone]]
    let picture = try fsPicture()
    for shot in [held, gone] {
        let signPath = "/storage/v1/object/sign/feedback-shots/\(shot.path)"
        FeedbackShotURLProtocol.set(status: 200, body: #"{"signedURL":"/object/sign/feedback-shots/\#(shot.path)?token=synthetic"}"#,
                                    host: host, path: signPath, method: "POST")
    }
    FeedbackShotURLProtocol.set(status: 200, data: picture.jpeg, host: host,
                                path: "/storage/v1/object/sign/feedback-shots/\(held.path)", method: "GET")
    FeedbackShotURLProtocol.set(status: 400, body: #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#,
                                host: host, path: "/storage/v1/object/sign/feedback-shots/\(gone.path)", method: "GET")
    #expect(store.feedbackShotCells(forReport: r1) == [.idle, .idle])
    #expect(FeedbackShotURLProtocol.log(host: host).isEmpty, "읽기만 했는데 받았다")

    // 운영자가 행을 펼친 순간 그 제보의 캡처를 받는다(서명 → GET).
    store.toggleFeedbackExpansion(r1)
    await fsWait { store.feedbackShotLoading.isEmpty && store.feedbackShotImages[held.path] != nil && store.feedbackShotFailures[gone.path] != nil }

    let log = FeedbackShotURLProtocol.log(host: host)
    #expect(log.filter { $0.method == "POST" }.count == 2 && log.filter { $0.method == "GET" }.count == 2)
    let sign = try #require(log.first { $0.method == "POST" && $0.path.hasSuffix(held.path) })
    #expect(sign.json?["expiresIn"] as? Int == FeedbackShotWire.signedURLSeconds)
    #expect(sign.header("Authorization") == "Bearer access-token")
    #expect(log.first { $0.method == "GET" }?.header("Authorization") == nil, "서명 URL 받기에 로그인 토큰을 실었다")
    if case .image = store.feedbackShotCell(for: held.path) {} else { Issue.record("받은 그림이 칸에 안 들어갔다") }
    #expect(store.feedbackShotCell(for: gone.path) == .failed(.missing), "지워진 캡처를 '못 불러왔어요'로 말한다")

    // 크게 보기는 받아 둔 것을 쓴다(다시 받지 않는다).
    store.openFeedbackShotViewer(reportID: r1, index: 0)
    #expect(store.feedbackShotViewer == FeedbackShotViewerState(source: .report(r1), index: 0))
    if case .image = store.feedbackShotViewerCell {} else { Issue.record("크게 보기가 받아 둔 그림을 안 그린다") }
    await fsWait { store.feedbackShotLoading.isEmpty }
    #expect(FeedbackShotURLProtocol.log(host: host).filter { $0.path.hasSuffix(held.path) }.count == 2, "받아 둔 캡처를 또 받았다")
    #expect(FeedbackShotURLProtocol.log(host: host).filter { $0.path.hasSuffix(gone.path) }.count == 2, "지워진 캡처를 또 물었다")
    store.stepFeedbackShotViewer(by: 1)
    #expect(store.feedbackShotViewer?.index == 1)
    store.stepFeedbackShotViewer(by: 1)
    #expect(store.feedbackShotViewer?.index == 0, "끝에서 처음으로 돌지 않는다")
    store.closeFeedbackPanel()
    #expect(store.feedbackShotViewer == nil, "패널을 닫았는데 크게 보기가 남았다")
}

@MainActor
@Test
func fbShotAFullCacheKeepsTheCapturesOnScreen() async throws {
    // 상한에 닿은 캐시를 통째로 비우면 방금 받은 같은 행의 첫 장까지 지워져 칸이 빈 채로 남는다(다시 받는 길은 사람이 누를 때뿐).
    let host = "fs-cache-full"
    let store = fsStore(host: host, admin: true)
    store.isFeedbackPanelVisible = true
    let r1 = "45454545-0000-0000-0000-000000000001"
    store.feedbackList = [fsReport(id: r1, owner: fsOther)]
    store.feedbackLoaded = true
    let shots = (1...FeedbackShotRules.maxDraft).map { fsShot(report: r1, number: $0, owner: fsOther) }
    store.feedbackShotsByReport = [r1: shots]
    let picture = try fsPicture()
    // 앞서 펼쳐 본 다른 제보들의 그림으로 상한 한 장 앞까지 채운다.
    for index in 0..<(FeedbackShotRules.cacheLimit - 1) {
        store.feedbackShotImages["\(fsOther)/old-\(index)/x.jpg"] = picture.image
    }
    for shot in shots {
        let signPath = "/storage/v1/object/sign/feedback-shots/\(shot.path)"
        FeedbackShotURLProtocol.set(status: 200, body: #"{"signedURL":"/object/sign/feedback-shots/\#(shot.path)?token=synthetic"}"#,
                                    host: host, path: signPath, method: "POST")
        FeedbackShotURLProtocol.set(status: 200, data: picture.jpeg, host: host, path: signPath, method: "GET")
    }

    store.toggleFeedbackExpansion(r1)
    await fsWait {
        store.feedbackShotLoading.isEmpty
            && FeedbackShotURLProtocol.log(host: host).filter { $0.method == "GET" }.count == shots.count
    }

    for (index, shot) in shots.enumerated() {
        if case .image = store.feedbackShotCell(for: shot.path) {} else {
            Issue.record("상한에서 캐시를 비우며 펼친 행의 \(index + 1)번째 캡처를 지웠다 — 칸이 빈 채로 남는다")
        }
    }
    #expect(!store.feedbackShotImages.keys.contains { $0.contains("/old-") }, "화면 밖 옛 그림을 하나도 안 비웠다 — 상한이 뜻이 없다")
    #expect(store.feedbackShotImages.count <= FeedbackShotRules.cacheLimit)
}

@MainActor
@Test
func fbShotSigningOutForgetsCapturesImagesAndTheMissingFlag() throws {
    let store = fsStore(host: "fs-signout")
    store.feedbackShots = [try fsDraft()]
    store.feedbackShotPreparing = true
    store.feedbackShotServerMissing = true
    store.feedbackShotDoorClosed = true
    store.feedbackShotsByReport = ["r": [fsShot(report: "r", number: 1, owner: fsOther)]]
    store.feedbackShotImages = ["\(fsOther)/r/x.jpg": try fsPicture().image]
    store.feedbackShotLoading = ["\(fsOther)/r/y.jpg"]
    store.feedbackShotFailures = ["\(fsOther)/r/z.jpg": .failed]
    store.feedbackShotViewer = FeedbackShotViewerState(source: .draft, index: 0)

    store.signOut()

    #expect(store.feedbackShots.isEmpty, "로그아웃했는데 앞 사람의 캡처가 남았다")
    #expect(!store.feedbackShotPreparing && !store.feedbackShotServerMissing && !store.feedbackShotDoorClosed)
    #expect(store.feedbackShotsByReport.isEmpty)
    #expect(store.feedbackShotImages.isEmpty, "받아 둔 남의 캡처가 다음 계정에 남았다")
    #expect(store.feedbackShotLoading.isEmpty && store.feedbackShotFailures.isEmpty)
    #expect(store.feedbackShotViewer == nil)
}

// MARK: - ⑥ 디코더 · 순수 판정

@Test
func fbShotAttachAnswersDecodeThroughTheServiceDecoder() async throws {
    let host = "fs-attach-decode"
    FeedbackShotURLProtocol.reset(host: host)
    let service = fsService(host: host)
    let cases: [(String, FeedbackAttachOutcome)] = [
        (#"{"status":"ok","attachment_id":"a","duplicate":true}"#, .attached(duplicate: true)),
        (#"{"status":"ok","attachment_id":"a"}"#, .attached(duplicate: false)),
        (#"{"status":"unsupported_client","door_open":true}"#, .doorClosed(doorOpen: true)),
        (#"{"status":"unsupported_client","door_open":false}"#, .doorClosed(doorOpen: false)),
        (#"{"status":"too_many","max":3}"#, .tooMany(max: 3)),
        (#"{"status":"invalid"}"#, .invalid),
        (#"{"status":"invalid_photo"}"#, .invalidPhoto),
        (#"{"status":"photo_missing"}"#, .photoMissing),
        (#"{"status":"unauthorized"}"#, .unauthorized),
        (#"{"status":"brand_new"}"#, .unknown),
        ("[]", .unknown),
    ]
    for (body, expected) in cases {
        FeedbackShotURLProtocol.set(status: 200, body: body, host: host, path: fsAttachPath)
        let outcome = try await service.attachFeedbackShot(accessToken: "t", reportID: fsReportID, path: fsShotPath(1), width: 10, height: 20)
        #expect(outcome == expected, "\(body) → \(outcome)")
    }
    // 대조군: 평범한 디코더는 door_open 을 놓친다.
    let naive = try JSONDecoder().decode(FeedbackAttachShotResponse.self, from: Data(#"{"status":"unsupported_client","door_open":true}"#.utf8))
    #expect(naive.doorOpen == nil)

    // 경로 모양: <uid>/<제보 id>/<uuid>.jpg — 조각마다 소문자.
    #expect(FeedbackShotWire.objectPath(userID: fsUser.uppercased(), reportID: fsReturnedID, fileID: "BBBBBBBB-0000-0000-0000-000000000001")
            == "\(fsUser)/\(fsReportID)/bbbbbbbb-0000-0000-0000-000000000001.jpg")
}

@Test
func fbShotTallyPicksTheRightLine() {
    func notice(_ steps: [FeedbackShotStep], total: Int) -> String {
        var tally = FeedbackShotTally(total: total)
        for step in steps {
            tally.record(step)
            if step.stops { break }
        }
        return tally.notice
    }
    #expect(notice([.attached, .attached], total: 2) == FeedbackText.sendSuccess)
    #expect(notice([.failed, .failed], total: 2) == FeedbackShotText.sentShotsFailed)
    #expect(notice([.attached, .failed, .attached], total: 3) == FeedbackShotText.sentSomeShotsFailed(1))
    #expect(notice([.refused], total: 3) == FeedbackShotText.sentShotsFailed, "멈춘 뒤 남은 것도 못 붙인 것이다")
    #expect(notice([.attached, .refused], total: 3) == FeedbackShotText.sentSomeShotsFailed(2))
    #expect(notice([.doorClosed], total: 2) == FeedbackShotText.sentShotsDoorClosed)
    #expect(notice([.attached, .outdated], total: 2) == FeedbackShotText.sentShotsAppOutdated)
    #expect(FeedbackShotStep.outdated.stops && FeedbackShotStep.outdated.closesTheDoor && FeedbackShotStep.doorClosed.closesTheDoor)
    #expect(!FeedbackShotStep.missing.closesTheDoor && !FeedbackShotStep.refused.closesTheDoor, "문 닫힘이 아닌데 붙이기 줄을 내린다")
    #expect(notice([.missing], total: 1) == FeedbackShotText.sentShotsDoorClosed)
    #expect(notice([.attached, .tooMany(3)], total: 2) == FeedbackShotText.sentShotsTooMany(3))
    #expect(FeedbackShotText.sentShotsTooMany(FeedbackShotWire.maxPerReport).contains("\(FeedbackShotWire.maxPerReport)장"))
}

@Test
func fbShotGroupingCapsAtTheServerLimitAndLowercasesIDs() {
    let report = "55555555-AAAA-0000-0000-000000000001"
    let rows = (1...5).map { number in
        FeedbackShotRow(
            reportId: report, attachmentId: "A\(number)",
            path: "\(fsUser)/\(report.lowercased())/eeeeeeee-0000-0000-0000-00000000000\(number).jpg",
            width: 10, height: 10, createdEpochMs: Int64(number)
        )
    }
    let grouped = FeedbackShotWire.grouped(rows)
    #expect(grouped.keys.sorted() == [report.lowercased()])
    #expect(grouped[report.lowercased()]?.count == FeedbackShotWire.maxPerReport, "상한보다 많이 받아 화면 높이 추정이 틀린다")
    #expect(grouped[report.lowercased()]?.map(\.id) == ["a1", "a2", "a3"])
}

// MARK: - 붙이기(이미지 준비)

@MainActor
@Test
func fbShotLargeCapturesShrinkToTheLongEdgeAndBrokenBytesAreRefused() throws {
    guard case .jpeg(let jpeg) = FeedbackShotImage.encode(imageData: fsSyntheticPNG(width: 3200, height: 1200)) else {
        Issue.record("큰 합성 그림을 못 줄였다")
        return
    }
    let size = try #require(FeedbackShotImage.pixelSize(of: jpeg))
    #expect(size == CGSize(width: 1600, height: 600), "긴 변이 \(size) 다")
    #expect(jpeg.count <= FeedbackShotRules.maxUploadBytes)
    guard case .jpeg(let small) = FeedbackShotImage.encode(imageData: fsSyntheticPNG(width: 400, height: 300)) else {
        Issue.record("작은 합성 그림을 못 읽었다")
        return
    }
    #expect(FeedbackShotImage.pixelSize(of: small) == CGSize(width: 400, height: 300), "작은 그림을 키웠다")
    #expect(FeedbackShotImage.encode(imageData: Data("not an image".utf8)) == .unreadable)
}

@MainActor
@Test
func fbShotPasteAddsUpToTheLimitAndSaysWhenEmpty() async throws {
    let store = fsStore(host: "fs-paste")
    let board = NSPasteboard(name: NSPasteboard.Name("check.test.feedbackshot.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()

    store.attachFeedbackShotFromPasteboard(board)
    #expect(store.feedbackNotice == FeedbackShotText.pasteEmpty, "빈 클립보드인데 말이 없다")
    #expect(store.feedbackShots.isEmpty)

    board.clearContents()
    board.setData(fsSyntheticPNG(width: 2400, height: 1500), forType: .png)
    store.feedbackDraft = "샘플 본문"
    for expected in 1...FeedbackShotRules.maxDraft {
        store.attachFeedbackShotFromPasteboard(board)
        #expect(store.feedbackShotPreparing)
        #expect(!store.canSendFeedback, "줄이는 중에 보내기가 열렸다")
        #expect(!store.canAddFeedbackShot, "줄이는 중에 또 붙일 수 있다")
        await fsWait { store.feedbackShots.count == expected && !store.feedbackShotPreparing }
        #expect(store.feedbackShots.count == expected)
    }
    #expect(store.feedbackShots.last?.pixelSize == CGSize(width: 1600, height: 1000))
    #expect(store.feedbackNotice == nil, "붙였는데 '클립보드에 이미지가 없어요'가 남았다")
    #expect(!store.canAddFeedbackShot, "상한인데 더 붙일 수 있다")
    store.attachFeedbackShotFromPasteboard(board)
    #expect(store.feedbackNotice == FeedbackShotText.full)
    #expect(store.feedbackShots.count == FeedbackShotRules.maxDraft)

    // [빼기] 한 장 → 자리가 생기고 안내가 걷힌다.
    let removed = try #require(store.feedbackShots.first)
    store.removeFeedbackShot(id: removed.id)
    #expect(store.feedbackShots.count == FeedbackShotRules.maxDraft - 1 && !store.feedbackShots.contains(removed))
    #expect(store.feedbackNotice == nil)
    #expect(store.canAddFeedbackShot)
}

/// 시험이 쓰는 합성 PNG 파일 자리. 이름이 고정이라 돌릴 때마다 덮어쓴다(쌓이지 않는다).
private func fsSyntheticFile(_ name: String, png: Data) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("check-fbshot-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent(name)
    try png.write(to: file, options: .atomic)
    return file
}

@MainActor
@Test
func fbShotPastingACopiedFileAttachesTheFileNotItsIcon() async throws {
    // Finder 에서 파일을 ⌘C 하면 클립보드에 파일 URL 과 함께 **그 파일의 아이콘 그림**(TIFF)이 실린다. 붙는 것은 파일이어야 한다.
    let store = fsStore(host: "fs-paste-file")
    let file = try fsSyntheticFile("synthetic-capture.png", png: fsSyntheticPNG(width: 2400, height: 1500))
    let icon = try #require(NSImage(data: fsSyntheticPNG(width: 64, height: 64, tint: .systemGray))?.tiffRepresentation)
    let board = NSPasteboard(name: NSPasteboard.Name("check.test.feedbackshot.file.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    let item = NSPasteboardItem()
    item.setString(file.absoluteString, forType: .fileURL)
    item.setData(icon, forType: .tiff)
    board.writeObjects([item])
    try #require(board.data(forType: .tiff) != nil, "전제: 판에 아이콘 바이트도 있다(없으면 이 시험은 늘 초록이다)")

    guard case .file(let url)? = FeedbackShotImage.source(in: board) else {
        Issue.record("파일 URL 이 있는데 아이콘 바이트를 골랐다")
        return
    }
    #expect(url.standardizedFileURL == file.standardizedFileURL)

    store.attachFeedbackShotFromPasteboard(board)
    await fsWait { store.feedbackShots.count == 1 && !store.feedbackShotPreparing }
    #expect(store.feedbackShots.first?.pixelSize == CGSize(width: 1600, height: 1000), "캡처 파일 대신 아이콘(64×64)이 붙었다")

    // 파일 URL 이 없으면(⌘⌃⇧4 · 브라우저 이미지 복사) 예전처럼 바이트다.
    board.clearContents()
    board.setData(icon, forType: .tiff)
    guard case .data? = FeedbackShotImage.source(in: board) else {
        Issue.record("파일이 없는 클립보드 그림을 못 읽었다")
        return
    }
}

@MainActor
@Test
func fbShotPickingMoreThanTheRoomAttachesWhatFitsAndSaysSo() async throws {
    let files = try (1...FeedbackShotRules.maxDraft).map {
        try fsSyntheticFile("synthetic-pick-\($0).png", png: fsSyntheticPNG(width: 800, height: 500))
    }
    // 한 장 붙인 뒤 상한만큼 골랐다 — 자리는 하나 모자란다.
    let store = fsStore(host: "fs-pick-overflow")
    store.feedbackShots = [try fsDraft()]
    store.attachFeedbackShots(fromFiles: files)
    await fsWait { !store.feedbackShotPreparing }
    #expect(store.feedbackShots.count == FeedbackShotRules.maxDraft)
    #expect(store.feedbackNotice == FeedbackShotText.full, "자리보다 많이 고른 것을 조용히 버렸다 — 사람은 다 붙은 줄 안다")

    // 자리 안이면 말하지 않는다.
    let fits = fsStore(host: "fs-pick-fits")
    fits.attachFeedbackShots(fromFiles: Array(files.prefix(2)))
    await fsWait { !fits.feedbackShotPreparing }
    #expect(fits.feedbackShots.count == 2)
    #expect(fits.feedbackNotice == nil)

    // 고르기 창의 안내는 상한이 아니라 **남은 자리**를 말한다(상수에서 나온 수).
    let remaining = FeedbackShotRules.maxDraft - 1
    #expect(FeedbackShotText.pickerMessage(remaining: remaining).contains("\(remaining)장"))
}

// MARK: - 높이 추정 · 소스 계약

@MainActor
@Test
func fbShotLayoutEstimatesCountTheRowAndRoundUp() {
    let base = FeedbackPanelLayout.sendBodyContentHeight(rows: [], hasNotice: false)
    #expect(FeedbackShotLayout.sendRowHeight(shown: false, count: 2) == 0, "숨긴 입구가 자리를 먹는다")
    let idle = FeedbackShotLayout.sendRowHeight(shown: true, count: 0)
    let attached = FeedbackShotLayout.sendRowHeight(shown: true, count: 2)
    #expect(idle >= 22 + FeedbackPanelLayout.sectionSpacing)
    #expect(attached >= FeedbackShotLayout.draftThumbHeight + 2 + 11 + FeedbackPanelLayout.sectionSpacing)
    #expect(FeedbackPanelLayout.sendBodyContentHeight(rows: [], hasNotice: false, shotRowHeight: attached) == base + attached)
    // 크롬이 가장 클 때 보내기 본문은 `minSendBodyHeight` 까지 깎인다 — 캡처를 붙여도 [보내기] 줄이 그 접힘선 위에 남는다.
    // 종류 22 · 간격 · 에디터 · 간격 · 붙인 줄(뒤 간격 포함) · 안내/카운터 26.
    let aboveFold = 22 + FeedbackPanelLayout.sectionSpacing + FeedbackPanelLayout.editorHeight
        + FeedbackPanelLayout.sectionSpacing + attached + 26
    #expect(aboveFold <= FeedbackPanelLayout.minSendBodyHeight, "캡처를 붙이면 [보내기]가 접힘선 아래로 밀린다: \(aboveFold)")

    let rows = [fsReport(id: "a"), fsReport(id: "b")]
    let counts = ["a": 2]
    #expect(FeedbackPanelLayout.sendBodyContentHeight(rows: rows, hasNotice: false, shotCount: { counts[$0.id] ?? 0 })
            == FeedbackPanelLayout.sendBodyContentHeight(rows: rows, hasNotice: false) + FeedbackShotLayout.mineRowExtra(shotCount: 2))
    #expect(FeedbackShotLayout.mineRowExtra(shotCount: 0) == 0)

    let collapsed = FeedbackInboxView.estimatedHeight(rows, expandedID: nil, shotCount: { counts[$0.id] ?? 0 })
    #expect(collapsed == FeedbackInboxView.estimatedHeight(rows, expandedID: nil), "접힌 행에 썸네일 몫을 셌다")
    #expect(FeedbackInboxView.estimatedHeight(rows, expandedID: "a", shotCount: { counts[$0.id] ?? 0 })
            == FeedbackInboxView.estimatedHeight(rows, expandedID: "a") + FeedbackShotLayout.inboxExpandedExtra(shotCount: 2))
    #expect(FeedbackShotLayout.inboxExpandedExtra(shotCount: 1) >= FeedbackShotLayout.inboxThumbHeight + 13 + 3 + 6)
}

@MainActor
private func fsSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func fsEditors(in root: NSView) -> [CheckEditorTextView] {
    var found: [CheckEditorTextView] = []
    if let match = root as? CheckEditorTextView { found.append(match) }
    for child in root.subviews { found += fsEditors(in: child) }
    return found
}

@MainActor
@Test
func fbShotAttachingWhileTypingKeepsTheSameEditorAndFocus() throws {
    // 붙이기 줄이 미리보기로 바뀌면(+23pt) 본문 추정이 상한을 넘나든다. 상자가 그대로 ↔ 스크롤로 갈리면 본문 칸이 새 NSTextView 가
    // 되어 포커스와 조합 중인 음절을 잃는다(신고 시트 v0.3.34 와 같은 결함 — `FeedbackListBox.keepsOneBranch`).
    CheckTextEditor.resetPoolForTesting()
    defer { CheckTextEditor.resetPoolForTesting() }
    let extra: CGFloat = 160
    let cap = FeedbackPanelLayout.budget(
        base: FeedbackPanelLayout.sendBodyHeight, floor: FeedbackPanelLayout.minSendBodyHeight, extraChromeHeight: extra
    )
    func estimate(_ count: Int) -> CGFloat {
        FeedbackPanelLayout.sendBodyContentHeight(
            rows: [], hasNotice: false, shotRowHeight: FeedbackShotLayout.sendRowHeight(shown: true, count: count)
        )
    }
    try #require(estimate(0) <= cap && estimate(1) > cap,
                 "전제가 깨졌다(추정 \(estimate(0)) → \(estimate(1)) · 상한 \(cap)) — 붙일 때 상한을 넘는 경계를 다시 골라라")

    let store = fsStore(host: "fs-editor-stable")
    store.isFeedbackPanelVisible = true
    store.feedbackLoaded = true
    store.feedbackDraft = "샘플 본문"
    let size = NSRect(x: 0, y: 0, width: FeedbackPanelLayout.contentWidth, height: 420)
    let host = NSHostingView(rootView: FeedbackSendView(store: store, extraChromeHeight: extra)
        .frame(width: size.width, height: size.height))
    host.frame = size
    let window = NSWindow(contentRect: size, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    fsSpin()
    let first = try #require(fsEditors(in: host).first, "본문 칸이 안 섰다")
    try #require(window.makeFirstResponder(first))

    store.feedbackShots = [try fsDraft()]
    fsSpin()
    #expect(fsEditors(in: host).first === first, "캡처를 붙이는 순간 본문 칸이 새 NSTextView 로 바뀌었다 — 조합 중인 음절을 잃는다")
    #expect(window.firstResponder === first, "캡처를 붙이는 순간 치던 칸이 포커스를 잃었다")

    store.feedbackShots = []
    fsSpin()
    #expect(fsEditors(in: host).first === first, "캡처를 빼는 순간 본문 칸이 새로 만들어졌다")
    #expect(window.firstResponder === first, "캡처를 빼는 순간 포커스를 잃었다")
    withExtendedLifetime(window) {}
}

@MainActor
@Test
func fbShotTheSendTabFollowsItsContentUpToTheBudget() throws {
    // 갈래를 하나로 묶어도 높이 규칙은 그대로다: 짧으면 자연 높이(빈 자리 없음), 길면 예산에서 스크롤(팝오버 700pt 를 지킨다).
    // 렌더 시험은 스냅샷 갈래(잘라 그리기)라 앱의 스크롤 상자를 못 본다 — 그 높이를 여기서 잰다.
    for (label, extra, rows) in [("short", CGFloat(0), 0), ("long", CGFloat(0), 8), ("long-tallest-chrome", CGFloat(241), 8)] {
        let store = fsStore(host: "fs-send-height-\(label)")
        store.feedbackLoaded = true
        store.feedbackList = (0..<rows).map { fsReport(id: String(format: "99999999-0000-0000-0000-%012d", $0)) }
        let cap = FeedbackPanelLayout.budget(
            base: FeedbackPanelLayout.sendBodyHeight, floor: FeedbackPanelLayout.minSendBodyHeight, extraChromeHeight: extra
        )
        let host = NSHostingView(rootView: FeedbackSendView(store: store, extraChromeHeight: extra)
            .frame(width: FeedbackPanelLayout.contentWidth))
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        #expect(height <= cap + 1, "\(label): 본문이 예산 \(cap)pt 를 넘었다: \(height)pt")
        if rows == 0 {
            #expect(height < cap - 40, "\(label): 짧은 본문인데 상한까지 늘어 빈 자리가 생겼다: \(height)pt · 상한 \(cap)pt")
        } else {
            #expect(abs(height - cap) <= 1, "\(label): 긴 본문이 예산을 다 쓰지 않는다: \(height)pt · 상한 \(cap)pt")
        }
    }
}

/// 주석을 걷어낸 소스(하우스 규칙 — 설명을 지워야 초록이 되는 계약을 만들지 않는다). 문자열 안의 `//` 는 남긴다.
private func fsCode(_ name: String) throws -> String {
    let url = CheckCoreSourceLayout.repoRoot.appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
    let source = try String(contentsOf: url, encoding: .utf8)
    var out = ""
    var index = source.startIndex
    var inString = false
    while index < source.endIndex {
        let char = source[index]
        let next = source.index(after: index)
        if inString {
            out.append(char)
            if char == "\\", next < source.endIndex { out.append(source[next]); index = source.index(after: next); continue }
            if char == "\"" { inString = false }
            index = next
            continue
        }
        if char == "\"" { inString = true; out.append(char); index = next; continue }
        if char == "/", next < source.endIndex, source[next] == "/" {
            while index < source.endIndex, source[index] != "\n" { index = source.index(after: index) }
            continue
        }
        if char == "/", next < source.endIndex, source[next] == "*" {
            if let end = source.range(of: "*/", range: next..<source.endIndex) { index = end.upperBound } else { index = source.endIndex }
            continue
        }
        out.append(char)
        index = next
    }
    return out
}

@Test
func fbShotSourceContractsGateTheRowAndKeepViewsOffTheNetwork() throws {
    let panel = try fsCode("CheckFeedbackView.swift")
    // 게이트 짝의 뷰 반쪽: 붙이기 줄은 입구가 **보일 때만** 만든다.
    let gate = try #require(panel.range(of: "if store.feedbackShotAttachShown {"), "붙이기 줄 앞의 입구 검사가 없다")
    let row = try #require(panel.range(of: "FeedbackShotAttachRow(store: store, acceptsDrops: !rendersPlainTextEditor)"),
                           "붙이기 줄을 안 부른다(또는 앱에서 놓기 판을 끈다)")
    #expect(gate.upperBound <= row.lowerBound)
    #expect(panel.contains("shown: store.feedbackShotAttachShown"), "높이 추정이 붙이기 줄과 다른 값을 본다 — 숨은 줄의 몫을 센다")
    #expect(panel.components(separatedBy: "FeedbackShotAttachRow(").count - 1 == 1, "붙이기 줄이 두 자리에 있다")
    // 기존 계약은 그대로다(전송 문 하나 · 답장 판 둘).
    #expect(panel.components(separatedBy: "store.sendFeedback()").count - 1 == 1)
    #expect(panel.components(separatedBy: "FeedbackReplyBlock(note:").count - 1 == 2)

    // 뷰는 받지 않는다 — 네트워크 · 세션 재시도 · 서비스를 부르는 줄이 캡처 조각 파일에 없다.
    let views = try fsCode("FeedbackShotViews.swift")
    for banned in ["withSessionRetry", "service.", "URLSession", "AsyncImage", "downloadFeedbackShot", ".task", "loadFeedbackShotImage", ".help("] {
        #expect(!views.contains(banned), "캡처 조각이 \(banned) 를 부른다 — 렌더가 네트워크를 탄다")
    }
    // 이 앱은 화면을 스스로 찍지 않는다(docs/privacy.md — 화면 기록 권한 금지).
    for name in ["FeedbackShot.swift", "FeedbackShotViews.swift", "WorkTimerStoreFeedbackShot.swift", "FeedbackShotWire.swift"] {
        let code = try fsCode(name)
        for banned in ["ScreenCaptureKit", "SCScreenshotManager", "SCShareableContent", "CGWindowListCreateImage", "screencapture", "CGDisplayCreateImage"] {
            #expect(!code.contains(banned), "\(name) 이 \(banned) 를 쓴다 — 화면 기록 권한이 필요해진다")
        }
        for banned in ["print(", "Logger(", "NSLog("] {
            #expect(!code.contains(banned), "\(name) 이 \(banned) 로 남의 캡처·경로를 흘릴 수 있다")
        }
    }
    // 저장소 판정은 한 곳: 목록 뒤 한 번은 `performLoadFeedback` 안에서만 부른다(팝오버 열기 · 폴링에 걸지 않는다).
    let feedback = try fsCode("WorkTimerStoreFeedback.swift")
    #expect(feedback.components(separatedBy: "performLoadFeedbackShots(").count - 1 == 1)
    let all = try fsCode("WorkTimerStoreFeedbackShot.swift")
    #expect(!all.contains("x-upsert"), "올리기가 덮어쓰기를 연다")
}

// MARK: - ⑦ 화면(렌더) — FEATURE_SHOTS_DIR 에 PNG

private enum FeedbackShotPNGs {
    static func save(_ bitmap: NSBitmapImageRep, name: String) {
        guard let dir = ProcessInfo.processInfo.environment["FEATURE_SHOTS_DIR"], !dir.isEmpty else { return }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: base.appendingPathComponent(name))
    }
}

/// 팝오버 높이 상한(pt) — 넘으면 푸터(로그아웃)가 화면 밖으로 잘린다.
private let fsPopoverCap: Double = 700

private let fsWorstNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구",
]

@MainActor
private func fsMenuStore(_ store: WorkTimerStore) -> WorkTimerStore {
    store.isMenuPresented = true
    store.displayNow = fsNow
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.startedAt = fsNow.addingTimeInterval(-3_600)
    store.isFeedbackPanelVisible = true
    return store
}

@MainActor
private func fsPanelBitmap(_ store: WorkTimerStore, worstChrome: Bool = false) throws -> NSBitmapImageRep {
    let view = CheckMenuView(
        store: store,
        previewClipsOverflowList: true,
        previewGoalEditing: worstChrome,
        previewUpdateBanner: worstChrome,
        previewUpdateNotes: worstChrome ? fsWorstNotes : [],
        previewPlainTextEditors: true
    )
    return try #require(CheckRenderSettle.bitmap(view, scale: 2), "팝오버를 못 그렸다")
}

@MainActor
private func fsBlank(matching bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
    let view = Color.clear
        .frame(width: CGFloat(bitmap.pixelsWide) / 2, height: CGFloat(bitmap.pixelsHigh) / 2)
        .background(CheckTheme.background)
    return try #require(CheckRenderSettle.bitmap(view, scale: 2))
}

/// 배경과 눈에 띄게 다른 영역의 경계(픽셀). 없으면 nil.
private func fsInk(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> CGRect? {
    let width = min(lhs.pixelsWide, rhs.pixelsWide)
    let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in stride(from: 0, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 2) {
            guard let a = lhs.colorAt(x: x, y: y), let b = rhs.colorAt(x: x, y: y) else { continue }
            let delta = abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
            if delta > 0.06 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

@MainActor
private func fsCheckFits(_ bitmap: NSBitmapImageRep, _ label: String) throws {
    #expect(bitmap.pixelsWide == 414 * 2, "\(label): 팝오버 폭이 414pt 가 아니다 — 캡처 조각이 본문 열을 밀어냈다")
    let height = Double(bitmap.pixelsHigh) / 2.0
    #expect(height <= fsPopoverCap, "\(label): 700pt 상한을 넘었다: \(height)pt")
    let ink = try #require(fsInk(bitmap, try fsBlank(matching: bitmap)), "\(label): 통째로 비었다")
    #expect(ink.maxX <= CGFloat(bitmap.pixelsWide) - 2 && ink.minX >= 4, "\(label): 내용이 옆으로 넘쳤다")
    #expect(ink.maxY > CGFloat(bitmap.pixelsHigh) - 60, "\(label): 푸터가 안 그려졌다")
}

@MainActor
private func fsDiffers(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Bool {
    guard let left = a.cgImage, let right = b.cgImage, let diff = CheckRenderDiff(left, right) else { return true }
    return diff.looksDifferent
}

@MainActor
@Test
func fbShotScreensDrawInsideThePopoverAndSavePNGs() throws {
    // ① 보내기 탭 — 캡처 둘(미리보기 · ⓧ 빼기 · 경고 한 줄), 내가 보낸 제보 둘(하나는 캡처 칩).
    let mineID = "66666666-0000-0000-0000-000000000001"
    func sendStore(_ host: String, captures: Int, hidden: Bool = false) throws -> WorkTimerStore {
        let store = fsMenuStore(fsStore(host: host))
        store.feedbackShots = try (0..<captures).map { try fsDraft(width: 1600, height: 1000, tint: [NSColor.systemBlue, .systemOrange, .systemGreen][$0]) }
        if hidden { store.markFeedbackShotsMissing() }
        store.feedbackDraft = "샘플 본문 — 메시지 창에서 보낸 글이 두 번 보여요. " + String(repeating: "가나다라마바사 ", count: 3)
        store.feedbackList = [
            fsReport(id: mineID, body: "샘플 본문 — 캡처 붙인 제보"),
            fsReport(id: "66666666-0000-0000-0000-000000000002", status: .done, body: "샘플 본문 — 캡처 없는 제보"),
        ]
        if !hidden { store.feedbackShotsByReport = [mineID: [fsShot(report: mineID, number: 1), fsShot(report: mineID, number: 2)]] }
        store.feedbackLoaded = true
        return store
    }
    let attached = try sendStore("fs-render-send", captures: 2)
    let attachedBitmap = try fsPanelBitmap(attached)
    FeedbackShotPNGs.save(attachedBitmap, name: "fbshot-send-two-captures.png")
    try fsCheckFits(attachedBitmap, "보내기(캡처 둘)")

    // 입구가 숨으면 붙이기 줄도 칩도 **없다** — 그림이 달라야 한다(게이트 짝의 뷰 반쪽이 실제로 그린다).
    let hidden = try sendStore("fs-render-send-hidden", captures: 2, hidden: true)
    let hiddenBitmap = try fsPanelBitmap(hidden)
    FeedbackShotPNGs.save(hiddenBitmap, name: "fbshot-send-hidden.png")
    try fsCheckFits(hiddenBitmap, "보내기(입구 숨김)")
    #expect(fsDiffers(attachedBitmap, hiddenBitmap), "입구가 숨었는데 붙이기 줄이 보인다(또는 보여야 하는데 안 보인다)")
    let idle = try sendStore("fs-render-send-idle", captures: 0)
    let idleBitmap = try fsPanelBitmap(idle)
    FeedbackShotPNGs.save(idleBitmap, name: "fbshot-send-idle.png")
    #expect(fsDiffers(idleBitmap, hiddenBitmap), "[이미지 고르기] 줄이 안 그려졌다")
    #expect(fsDiffers(idleBitmap, attachedBitmap), "붙인 캡처가 화면에 흔적이 없다")

    // 가장 키 큰 크롬(새 버전 배너 + 노트 4줄 + 목표 편집) 아래에서도 상한을 지키고 푸터가 산다.
    let tallest = try sendStore("fs-render-send-tallest", captures: 3)
    tallest.feedbackNotice = FeedbackShotText.sentShotsDoorClosed
    let tallestBitmap = try fsPanelBitmap(tallest, worstChrome: true)
    FeedbackShotPNGs.save(tallestBitmap, name: "fbshot-send-three-tallest-chrome.png")
    try fsCheckFits(tallestBitmap, "보내기(캡처 셋 · 최악 크롬)")

    // ② 내가 보낸 제보 — 캡처 칩(받아 둔 첫 장 썸네일 · 아직 안 받음).
    let mine = fsMenuStore(fsStore(host: "fs-render-mine"))
    let heldReport = "77777777-0000-0000-0000-000000000001"
    let idleReport = "77777777-0000-0000-0000-000000000002"
    mine.feedbackList = [
        fsReport(id: heldReport, body: "샘플 본문 — 받아 둔 캡처"),
        fsReport(id: idleReport, status: .inProgress, body: "샘플 본문 — 아직 안 받은 캡처"),
        fsReport(id: "77777777-0000-0000-0000-000000000003", status: .done, body: "샘플 본문 — 캡처 없음"),
    ]
    let heldShot = fsShot(report: heldReport, number: 1)
    mine.feedbackShotsByReport = [
        heldReport: [heldShot, fsShot(report: heldReport, number: 2)],
        idleReport: [fsShot(report: idleReport, number: 3)],
    ]
    mine.feedbackLoaded = true
    mine.feedbackShotImages[heldShot.path] = try fsPicture(tint: .systemOrange).image
    let mineBitmap = try fsPanelBitmap(mine)
    FeedbackShotPNGs.save(mineBitmap, name: "fbshot-mine-chips.png")
    try fsCheckFits(mineBitmap, "내가 보낸 제보(칩)")
    let mineNoShot = fsMenuStore(fsStore(host: "fs-render-mine-plain"))
    mineNoShot.feedbackList = mine.feedbackList
    mineNoShot.feedbackLoaded = true
    #expect(fsDiffers(mineBitmap, try fsPanelBitmap(mineNoShot)), "캡처 칩이 화면에 아무 흔적도 남기지 않았다")

    // ③ 받은 제보(관리자) — 펼친 행에 썸네일 둘(하나는 받아 둔 합성 그림, 하나는 지워짐). 렌더는 네트워크를 안 탄다.
    func inboxStore(_ host: String, cached: Bool) throws -> WorkTimerStore {
        let store = fsMenuStore(fsStore(host: host, admin: true))
        store.feedbackShowsInbox = true
        let rows = (0..<3).map { String(format: "88888888-0000-0000-0000-%012d", $0) }
        store.feedbackList = [
            fsReport(id: rows[0], owner: fsOther,
                     body: "샘플 본문 0 — 오목 창에서 돌이 두 칸 겹쳐 보여요. " + String(repeating: "가나다라마바사 ", count: 4)),
            fsReport(id: rows[1], owner: fsOther, body: "샘플 본문 1"),
            fsReport(id: rows[2], owner: fsOther, status: .inProgress, body: "샘플 본문 2"),
        ]
        let first = fsShot(report: rows[0], number: 1, owner: fsOther)
        let second = fsShot(report: rows[0], number: 2, owner: fsOther)
        store.feedbackShotsByReport = [rows[0]: [first, second], rows[1]: [fsShot(report: rows[1], number: 3, owner: fsOther)]]
        store.feedbackLoaded = true
        store.feedbackOpenCount = 2
        store.expandedFeedbackID = rows[0]
        store.feedbackNoteDraft = "샘플 답장"
        if cached {
            store.feedbackShotImages[first.path] = try fsPicture().image
            store.feedbackShotFailures[second.path] = .missing
        }
        return store
    }
    let inbox = try inboxStore("fs-render-inbox", cached: true)
    let inboxBitmap = try fsPanelBitmap(inbox)
    FeedbackShotPNGs.save(inboxBitmap, name: "fbshot-inbox-expanded-thumbnails.png")
    try fsCheckFits(inboxBitmap, "받은 제보(펼친 행 썸네일)")
    let inboxIdle = try inboxStore("fs-render-inbox-idle", cached: false)
    #expect(fsDiffers(inboxBitmap, try fsPanelBitmap(inboxIdle)), "받아 둔 캡처 그림이 그려지지 않았다")

    // ④ 크게 보기(붙여 둔 캡처) — 패널을 덮는다.
    let viewer = try sendStore("fs-render-viewer", captures: 2)
    viewer.openFeedbackShotDraftViewer(index: 1)
    let viewerBitmap = try fsPanelBitmap(viewer)
    FeedbackShotPNGs.save(viewerBitmap, name: "fbshot-viewer-draft.png")
    try fsCheckFits(viewerBitmap, "크게 보기")
    #expect(fsDiffers(viewerBitmap, attachedBitmap), "크게 보기가 패널을 덮지 않았다")

    // 렌더는 캡처를 하나도 받지 않았다(저장소 · 캡처 RPC).
    for host in ["fs-render-inbox", "fs-render-inbox-idle", "fs-render-mine", "fs-render-send", "fs-render-viewer"] {
        let touched = FeedbackShotURLProtocol.log(host: host).filter {
            $0.path.hasPrefix("/storage/") || $0.path == fsShotsPath || $0.path == fsAttachPath
        }
        #expect(touched.isEmpty, "\(host): 그리는 동안 캡처를 받았다 — \(touched.map(\.path))")
    }
}
