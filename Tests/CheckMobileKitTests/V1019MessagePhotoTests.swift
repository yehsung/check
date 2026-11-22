@testable import CheckCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CheckMobileKit

// 폰 1.0.19 — 1:1 메시지 사진(맥 0.3.86 과 같은 코어 전선 `MessagePhotoWire` · 대표 #d_xygj8oZRFlfH 4번 메시지 묶음).
@MainActor
@Suite("폰 1.0.19 — 메시지 사진", .serialized)
struct V1019MessagePhotoTests {
    nonisolated static let peer = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    /// 사진 경로의 첫 폴더는 uuid 계정이다(서버 정책 `auth.uid()` · 코어 `MessagePhotoPath.isServerShaped`).
    nonisolated static let me = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"

    nonisolated static func jpeg() -> Data {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// `message_page` 사진 줄(받은 사진 — 경로는 서버 모양: <보낸 uid>/<소문자 uuid>.jpg).
    nonisolated static func photoRow(_ id: String, epochSeconds: Int, caption: String?) -> String {
        let path = "\(peer)/0f8fad5b-d9cb-469f-a165-70867728950e.jpg"
        let captionJSON = caption.map { "\"\($0)\"" } ?? "null"
        return #"{"id":"\#(id)","from_user":"\#(peer)","to_user":"\#(Self.me)","body":"📷 사진","caption":\#(captionJSON),"photo_path":"\#(path)","photo_width":800,"photo_height":600,"is_megaphone":false,"is_mine":false,"created_epoch_ms":\#(epochSeconds * 1000),"created_epoch_us":\#(Int64(epochSeconds) * 1_000_000),"read_by_peer":null,"unread_for_me":false}"#
    }

    @Test("사진 칸: 대화를 열면 한 번(message_page 30) 묻고 머리 줄에 사진을 얹는다 · 안 읽음 · 읽음은 그대로 · 대화를 닫으면 걷는다")
    func metaOnOpen() async throws {
        let base = MessagesHarness.base
        let h = await MessagesHarness.make(userID: Self.me) { server in
            server.setRows([.received("ph-1", from: Self.peer, body: "📷 사진", at: 10)])
            server.override("message_page") { _ in .json("[" + Self.photoRow("ph-1", epochSeconds: base + 10, caption: "바다") + "]") }
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        #expect(h.count("message_page") == 0, "대화를 열기 전에 사진 칸을 물었다")
        let token = UUID()
        h.store.conversationDidAppear(peerID: Self.peer, token: token)
        await h.settle()
        _ = await baseWaitUntil { h.store.photoMetaIdle && h.store.photoMetaAvailable == true }
        let body = try #require(h.bodies("message_page").first)
        #expect(body.contains("\"p_limit\":30") && body.contains("\"p_before_us\":null"), "\(body)")
        let shown = try #require(h.store.conversationMessages(for: Self.peer).first { $0.id == "ph-1" })
        #expect(shown.photo?.width == 800 && shown.photoCaption == "바다")
        #expect(h.store.history.first { $0.id == "ph-1" }?.photo == nil, "24시간 머리를 바꿨다")
        h.store.conversationDidDisappear(token: token)
        #expect(h.store.photoMeta.isEmpty)
        h.expectNoForbiddenCalls()
    }

    @Test("보내기: 고른 사진 → 올리기(message-photos/<나>/<uuid>.jpg) → send_photo_message(같은 uuid · 입력칸 글이 설명) · 그 자리에서 그린다")
    func sendPhoto() async throws {
        let h = await MessagesHarness.make(userID: Self.me) { server in
            server.setRows([.received("m-1", from: Self.peer, at: 10)])
            server.override("message_page") { _ in .json("[]") }
            server.override("send_photo_message") { _ in
                .json(#"{"status":"ok","body":"설명","ring":"sent","message_id":"sent-1","photo_path":null,"photo_width":null,"photo_height":null}"#)
            }
            server.overridePath(prefix: "/storage/v1/object/message-photos/") { _ in .json(#"{"Key":"ok"}"#) }
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peer, token: UUID())
        await h.settle()
        #expect(h.store.showsPhotoButton(for: Self.peer) && h.store.canSendPhoto(to: Self.peer))
        h.store.preparePhoto(data: Self.jpeg(), for: Self.peer)
        _ = await baseWaitUntil { h.store.photoDraft(for: Self.peer) != nil }
        let draft = try #require(h.store.photoDraft(for: Self.peer))
        #expect(draft.id == draft.id.lowercased() && draft.encoded.pixelWidth == 64 && draft.encoded.pixelHeight == 48)
        h.store.setDraft("설명", for: Self.peer)
        h.store.sendPhotoDraft(to: Self.peer)
        _ = await baseWaitUntil { !h.store.isSending }
        await h.settle()
        let uploads = h.requests.filter { $0.path.hasPrefix("/storage/v1/object/message-photos/") }
        #expect(uploads.count == 1 && uploads.first?.path == "/storage/v1/object/message-photos/\(Self.me)/\(draft.id).jpg")
        let sent = try #require(h.requests.first { $0.rpcName == "send_photo_message" })
        #expect(sent.jsonBody["p_client_message_id"] as? String == draft.id && sent.jsonBody["p_caption"] as? String == "설명")
        #expect(sent.jsonBody["p_path"] as? String == "\(Self.me)/\(draft.id).jpg")
        #expect(sent.jsonBody["p_width"] as? Int == 64 && sent.jsonBody["p_height"] as? Int == 48)
        #expect(h.store.photoDraft(for: Self.peer) == nil && h.store.draft(for: Self.peer).isEmpty, "보낸 뒤 사진 · 설명이 남았다")
        let meta = try #require(h.store.photoMeta[Self.peer]?["sent-1"])
        #expect(meta.attachment.path == "\(Self.me)/\(draft.id).jpg" && meta.caption == "설명")
        #expect(h.store.photoImages.image(for: meta.attachment.path, owner: Self.me) != nil, "내 사진을 다시 받으려 한다")
    }

    @Test("문 닫힘: unsupported_client(door_open false) 면 사진을 내리고 [사진]을 숨긴다 · 글은 남는다 · 대화를 다시 열면 다시 선다")
    func doorClosed() async throws {
        let h = await MessagesHarness.make(userID: Self.me) { server in
            server.override("message_page") { _ in .json("[]") }
            server.override("send_photo_message") { _ in .json(#"{"status":"unsupported_client","door_open":false}"#) }
            server.overridePath(prefix: "/storage/v1/object/message-photos/") { _ in .json(#"{"Key":"ok"}"#) }
        }
        defer { h.tearDown() }
        let token = UUID()
        h.store.conversationDidAppear(peerID: Self.peer, token: token)
        await h.settle()
        h.store.preparePhoto(data: Self.jpeg(), for: Self.peer)
        _ = await baseWaitUntil { h.store.photoDraft(for: Self.peer) != nil }
        h.store.setDraft("남을 글", for: Self.peer)
        h.store.sendPhotoDraft(to: Self.peer)
        _ = await baseWaitUntil { !h.store.isSending }
        #expect(h.store.photoSendClosed && !h.store.showsPhotoButton(for: Self.peer) && h.store.photoDraft(for: Self.peer) == nil)
        #expect(h.store.sendNotices[Self.peer] == MessagePhotoText.doorClosedNotice)
        #expect(h.store.draft(for: Self.peer) == "남을 글")
        h.store.conversationDidDisappear(token: token)
        h.store.conversationDidAppear(peerID: Self.peer, token: UUID())
        #expect(h.store.showsPhotoButton(for: Self.peer))
    }

    @Test("못 읽는 사진: 고른 자료를 못 읽으면 '사진을 읽지 못했어요' · 미리 보기가 안 선다")
    func unreadable() async {
        let h = await MessagesHarness.make(userID: Self.me) { server in server.override("message_page") { _ in .json("[]") } }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peer, token: UUID())
        h.store.preparePhoto(data: Data("not an image".utf8), for: Self.peer)
        _ = await baseWaitUntil { !h.store.photoPreparing }
        #expect(h.store.photoDraft(for: Self.peer) == nil && h.store.sendNotices[Self.peer] == MessagePhotoText.unreadableNotice)
    }

    @Test("배선: 입력줄 [사진]은 문 값으로만 · 대화 화면이 미리 보기 시트 · 크게 보기 · 사진 말풍선 — 주석을 걷고 본다")
    func wiring() throws {
        let composer = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesComposerView.swift").filter { !$0.isWhitespace }
        #expect(composer.contains("ifstore.showsPhotoButton(for:peerID){photoButton(sendMetrics)}"))
        #expect(composer.contains("PhotosPicker(selection:$pickedPhoto,matching:.images)"))
        #expect(composer.contains("store.preparePhoto(data:data??Data(),for:peerID)"))
        let view = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift").filter { !$0.isWhitespace }
        #expect(view.contains("photoContext:store.photoContext,onOpenPhoto:{photoViewer=$0}"))
        #expect(view.contains("MessagesPhotoPreviewSheet(store:store,peerID:peerID,draft:draft)"))
        #expect(view.contains(".interactiveDismissDisabled(store.isSending)"))
        #expect(view.contains("iflet photo=line.entry.photo{".filter { !$0.isWhitespace }))
        #expect(!view.contains("ShareLink"), "사진 저장 길을 열면 사진 보관함 권한 문구가 필요하다")
    }
}
