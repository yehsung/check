@testable import CheckCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CheckMobileKit

// 폰 1.0.19 — 제보 화면 캡처(맥 0.3.86 과 같은 계약 v2 §3 · 대표 #d_xygj8oZRFlfH 4번 메시지 묶음).
@MainActor
@Suite("폰 1.0.19 — 제보 화면 캡처", .serialized)
struct V1019FeedbackShotTests {
    nonisolated static let reportID = "0f8fad5b-d9cb-469f-a165-70867728950e"

    /// 시험용 JPEG 한 장(가로 40 · 세로 30).
    nonisolated static func jpeg() -> Data {
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test("안내 한 줄: 다 붙음 = 예전 성공 · 하나도 못 = '캡처는 못 붙였어요' · 일부 · 문 닫힘 · 옛 판 · 상한 — 맥과 같은 글")
    func tally() {
        var all = MeFeedbackShotTally(total: 2)
        all.record(.attached); all.record(.attached)
        #expect(all.notice == FeedbackText.sendSuccess)
        var none = MeFeedbackShotTally(total: 2)
        none.record(.failed); none.record(.failed)
        #expect(none.notice == FeedbackShotText.sentShotsFailed)
        var some = MeFeedbackShotTally(total: 3)
        some.record(.attached); some.record(.failed); some.record(.attached)
        #expect(some.notice == FeedbackShotText.sentSomeShotsFailed(1))
        var door = MeFeedbackShotTally(total: 2)
        door.record(.doorClosed)
        #expect(door.notice == FeedbackShotText.sentShotsDoorClosed && MeFeedbackShotStep.doorClosed.stops)
        var old = MeFeedbackShotTally(total: 1)
        old.record(.outdated)
        #expect(old.notice == FeedbackShotText.sentShotsAppOutdated && MeFeedbackShotStep.outdated.closesTheDoor)
        var many = MeFeedbackShotTally(total: 1)
        many.record(.tooMany(3))
        #expect(many.notice == FeedbackShotText.sentShotsTooMany(3))
        #expect(!MeFeedbackShotStep.failed.stops && MeFeedbackShotStep.refused.stops)
    }

    @Test("붙이기 → 보내기: 글이 먼저(submit_feedback) · 그 제보 폴더에 올리고(feedback-shots/<나>/<제보>/<uuid>.jpg) 붙인다 · 목록 뒤 칩 한 번")
    func attachThenSend() async throws {
        let harness = await RankMeHarness(label: "v1019-feedback-shot") { request in
            if request.rpcName == "submit_feedback" { return .json("\"\(Self.reportID)\"") }
            if request.rpcName == "feedback_attach_shot" { return .json(#"{"status":"ok","attachment_id":"a1","duplicate":false}"#) }
            if request.rpcName == "feedback_list" {
                return .json(#"[{"id":"\#(Self.reportID)","user_id":"\#(RankMeFixture.userID)","kind":"bug","body":"글","status":"open","created_at":"2026-09-17T01:00:00Z"}]"#)
            }
            if request.rpcName == "feedback_shots" {
                return .json(#"[{"report_id":"\#(Self.reportID)","attachment_id":"a1","path":"\#(RankMeFixture.userID)/\#(Self.reportID)/x.jpg","width":40,"height":30,"created_epoch_ms":1}]"#)
            }
            if request.path.hasPrefix("/storage/v1/object/feedback-shots/") { return .json(#"{"Key":"ok"}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.feedbackDidAppear()
        await harness.quiesceMe()
        #expect(store.feedbackShotAttachShown && store.feedbackShotRoom == 3)
        store.attachFeedbackShots(datas: [Self.jpeg(), Self.jpeg()])
        await harness.quiesceMe()
        #expect(store.feedbackShots.count == 2 && !store.feedbackShotPreparing)
        #expect(store.feedbackShots.first.map { $0.pixelWidth == 40 && $0.pixelHeight == 30 } == true)

        store.feedbackDraft = "사진이 안 보여요"
        await store.sendFeedback()
        await harness.quiesceMe()
        #expect(store.feedbackNotice == FeedbackText.sendSuccess, "\(String(describing: store.feedbackNotice))")
        #expect(store.feedbackShots.isEmpty, "보낸 캡처가 다음 제보를 위해 남았다")
        let uploads = harness.requests.filter { $0.path.hasPrefix("/storage/v1/object/feedback-shots/") }
        #expect(uploads.count == 2 && uploads.allSatisfy { $0.path.contains("/\(RankMeFixture.userID)/\(Self.reportID)/") && $0.path.hasSuffix(".jpg") })
        let attaches = harness.requests(rpc: "feedback_attach_shot")
        #expect(attaches.count == 2 && attaches.first?.jsonBody["p_report"] as? String == Self.reportID)
        #expect(attaches.first?.jsonBody["p_width"] as? Int == 40 && attaches.first?.jsonBody["p_height"] as? Int == 30)
        // 순서: 글 → (올리기 → 붙이기)×2.
        let order = harness.requests.compactMap { request -> String? in
            if request.rpcName == "submit_feedback" { return "submit" }
            if request.rpcName == "feedback_attach_shot" { return "attach" }
            if request.path.hasPrefix("/storage/v1/object/feedback-shots/") { return "upload" }
            return nil
        }
        #expect(order == ["submit", "upload", "attach", "upload", "attach"], "\(order)")
        #expect(store.feedbackShotCount(forReport: Self.reportID) == 1, "목록 뒤 칩이 안 섰다")
        #expect(harness.requests(rpc: "feedback_shots").count >= 1)
    }

    @Test("함수 없는 서버: 붙이기가 404 면 입구를 숨기고 '아직 준비 중' · 제보 화면을 다시 열면 다시 선다(요청 없이)")
    func missingFunctionHides() async throws {
        let harness = await RankMeHarness(label: "v1019-feedback-shot-missing") { request in
            if request.rpcName == "submit_feedback" { return .json("\"\(Self.reportID)\"") }
            if request.rpcName == "feedback_attach_shot" { return .missingFunction("feedback_attach_shot") }
            if request.rpcName == "feedback_list" { return .json("[]") }
            if request.path.hasPrefix("/storage/v1/object/feedback-shots/") { return .json(#"{"Key":"ok"}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.attachFeedbackShots(datas: [Self.jpeg()])
        await harness.quiesceMe()
        store.feedbackDraft = "글"
        await store.sendFeedback()
        await harness.quiesceMe()
        #expect(store.feedbackNotice == FeedbackShotText.sentShotsDoorClosed)
        #expect(!store.feedbackShotsShown && !store.feedbackShotAttachShown && store.feedbackShotsForSend.isEmpty)
        store.feedbackDidDisappear()
        store.feedbackDidAppear()
        #expect(store.feedbackShotAttachShown, "다시 열었는데 입구가 숨은 채다")
    }

    @Test("배선: 제보 쓰기 카드가 캡처 줄(사진 고르기 · 남은 자리만큼 · ✕ · 경고)을 붙이기 값으로만 세우고 · 목록 줄에 칩 — 주석을 걷고 본다")
    func wiring() throws {
        let view = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeFeedbackView.swift").filter { !$0.isWhitespace }
        #expect(view.contains("ifstore.feedbackShotAttachShown{shotsRow(store:store)}"))
        #expect(view.contains("PhotosPicker(selection:$pickedShots,maxSelectionCount:max(1,store.feedbackShotRoom),matching:.images)"))
        #expect(view.contains("store.attachFeedbackShots(datas:datas)") && view.contains("store.removeFeedbackShot(id:shot.id)"))
        #expect(view.contains("Text(FeedbackShotText.privacyWarning)"))
        #expect(view.contains("shotCount:store.feedbackShotCount(forReport:report.id)"))
    }
}
