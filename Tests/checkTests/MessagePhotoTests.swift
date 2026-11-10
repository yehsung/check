import AppKit
import CheckRenderTestSupport
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import check
@testable import CheckCore

// 2026-11-11 — **1:1 메시지 사진**(맥 0.3.86 · build 139). 계약: CONTRACT-photo · 서버 목록 §2 · 초안 20261114101000 §1~§6.
//
// 이 파일이 재는 것(전선은 진짜 `SupabaseWorkService` 디코더 · 요청 경로로 — 스텁은 호스트별 URLProtocol):
//  ① 전선: 요청 여섯 키(명시적 null) · 응답(ok + 사진 칸 · duplicate · unsupported_client+door_open · invalid_photo · photo_missing · 공용 status)
//     · `message_page` 행 → entry.photo · 신고된 사진 경로 행 · 경로 모양 · 크기 규칙.
//  ② 스토어: 올리기 경로(소문자 uid/uuid.jpg · image/jpeg · x-upsert 없음) → 같은 uuid 의 `p_client_message_id` · 답을 못 받으면 같은 uuid 로
//     한 번 더 · 다시 올리기 409 = 성공 · 올리기 거절 뒤 사유 가르기(문 닫힘) · 사진 칸은 대화 열기 · 새 받은 줄에서만(팝오버 열기 · 새로고침 X)
//     · 404 는 숨기고 다음 열기에서 되살림 · 로그아웃이 그림 캐시를 비움 · 안 읽음 점 · 읽음 처리는 그대로.
//  ③ 인코더: 긴 변 ≤ 1600 · 목표 크기 이하 · EXIF 회전 · 투명 → 흰 바탕 · GPS 등 메타데이터 없음.
//  ④ 화면: 틀 높이 추정 ≥ 그려진 사진 말풍선 · 덮개가 밑의 대화를 보이스오버에서 내림 · 스냅숏(FEATURE_SHOTS_DIR).
//
// 실행: 함수 이름 정규식으로 — `swift test --skip-build --filter 'checkTests\.사진_'`(파일 이름 필터는 자유 함수를 건너뛴다).
// 이름 · 본문 · 그림은 전부 지어낸 것이다(공개 저장소 — 그림은 코드로 그린다).

private typealias Fx = MessageReadFixture
private typealias Reply = MessageReadStubProtocol.Reply

// MARK: - 픽스처

private enum PhFx {
    /// 상대가 올린 사진(소문자 uuid 둘 — 서버 정규식 모양).
    static let peerPhotoID = "11111111-2222-4333-8444-555555555555"
    static let peerPhotoPath = "\(Fx.peerA)/\(peerPhotoID).jpg"
    static let otherPhotoID = "66666666-7777-4888-9999-aaaaaaaaaaaa"
    static let otherPhotoPath = "\(Fx.peerA)/\(otherPhotoID).jpg"
    static let minePhotoPath = "\(Fx.me)/\(otherPhotoID).jpg"

    static var nowEpoch: Int { Int(Fx.now.timeIntervalSince1970) }

    static func micros(_ secondsAgo: Int) -> Int64 {
        Int64(nowEpoch - secondsAgo) * 1_000_000 + 4_321
    }

    /// `message_page` 한 줄(서버 최종 목록 §1 의 열네 칸).
    static func pageRow(
        id: String, isMine: Bool, secondsAgo: Int, caption: String?, photoPath: String?,
        width: Int = 1_600, height: Int = 1_200, megaphone: Bool = false
    ) -> [String: Any] {
        let hasPhoto = photoPath != nil
        let stored = caption ?? (hasPhoto ? MessageNoticeText.photoFallbackBody : "그냥 말")
        let us = micros(secondsAgo)
        return [
            "id": id,
            "from_user": isMine ? Fx.me : Fx.peerA,
            "to_user": isMine ? Fx.peerA : Fx.me,
            "body": stored,
            "caption": caption.map { $0 as Any } ?? (hasPhoto ? NSNull() : stored as Any),
            "photo_path": photoPath.map { $0 as Any } ?? NSNull(),
            "photo_width": hasPhoto ? width as Any : NSNull(),
            "photo_height": hasPhoto ? height as Any : NSNull(),
            "is_megaphone": megaphone,
            "is_mine": isMine,
            "created_epoch_ms": us / 1_000,
            "created_epoch_us": us,
            "read_by_peer": isMine ? false as Any : NSNull(),
            "unread_for_me": isMine ? NSNull() : false as Any
        ]
    }

    /// 24시간 머리 한 줄(사진 칸이 **없다** — 서버 계약).
    static func head(_ id: String, isMine: Bool, secondsAgo: Int, body: String, unread: Bool? = nil) -> [String: Any] {
        Fx.readsRow(id: id, peer: Fx.peerA, isMine: isMine, body: body, epoch: nowEpoch - secondsAgo, unread: unread, name: "민수")
    }

    /// `send_photo_message` ok 응답(요청의 경로 · 크기를 그대로 돌려준다 — 서버 §4).
    static func okReply(for call: MessageReadStubProtocol.Call, messageID: String, duplicate: Bool = false) -> Reply {
        let json = call.json
        let caption = json["p_caption"] as? String
        return Reply(body: Fx.json([
            "status": "ok", "ring": duplicate ? "duplicate" : "sent", "message_id": messageID,
            "created_at": "2026-09-21T12:00:00+00:00", "duplicate": duplicate,
            "body": caption ?? MessageNoticeText.photoFallbackBody,
            "photo_path": json["p_path"] as Any, "photo_width": json["p_width"] as Any, "photo_height": json["p_height"] as Any
        ]))
    }

    static func entry(
        _ id: String, body: String, isMine: Bool, photo: MessagePhotoAttachment? = nil, at date: Date = Fx.now
    ) -> MessageHistoryEntry {
        MessageHistoryEntry(
            id: id, peerUserID: Fx.peerA, peerName: "민수", peerAvatarURL: nil, body: body,
            createdAt: date, isMine: isMine, readByPeer: isMine ? true : nil, isUnread: isMine ? nil : false, photo: photo
        )
    }
}

/// 잠금 있는 깃발 · 셈(스텁 처리기는 다른 스레드에서 돈다).
private final class PhBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flags: Set<String> = []
    private var counts: [String: Int] = [:]
    func set(_ name: String) { lock.lock(); flags.insert(name); lock.unlock() }
    func has(_ name: String) -> Bool { lock.lock(); defer { lock.unlock() }; return flags.contains(name) }
    func bump(_ name: String = "") { lock.lock(); counts[name, default: 0] += 1; lock.unlock() }
    func count(_ name: String = "") -> Int { lock.lock(); defer { lock.unlock() }; return counts[name] ?? 0 }
}

// MARK: - 그림(코드로 그린다)

/// 하늘 그라데이션 + 해 + 땅. `alpha` 면 가운데만 불투명하고 나머지는 투명하다. `noise` 면 결정적 잡음을 깐다(압축이 잘 안 되는 그림).
private func phImage(width: Int, height: Int, alpha: Bool = false, noise: Bool = false) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    if alpha {
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: width / 3, y: height / 3, width: width / 3, height: height / 3))
        return context.makeImage()!
    }
    let bands = 24
    for band in 0..<bands {
        let t = CGFloat(band) / CGFloat(bands - 1)
        context.setFillColor(CGColor(red: 0.35 + 0.4 * t, green: 0.55 + 0.25 * t, blue: 0.95, alpha: 1))
        let bandHeight = CGFloat(height) / CGFloat(bands)
        context.fill(CGRect(x: 0, y: CGFloat(band) * bandHeight, width: CGFloat(width), height: bandHeight + 1))
    }
    context.setFillColor(CGColor(red: 0.25, green: 0.6, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height) * 0.3))
    context.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
    let r = CGFloat(min(width, height)) * 0.12
    context.fillEllipse(in: CGRect(x: CGFloat(width) * 0.7 - r, y: CGFloat(height) * 0.7 - r, width: r * 2, height: r * 2))
    if noise, let data = context.data {
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var seed: UInt32 = 0x9E37_79B9
        for index in 0..<(width * height) {
            for channel in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                pixels[index * 4 + channel] = UInt8(truncatingIfNeeded: seed >> 24)
            }
            pixels[index * 4 + 3] = 255
        }
    }
    return context.makeImage()!
}

private func phEncode(_ image: CGImage, type: UTType, properties: [CFString: Any] = [:]) -> Data {
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func phPixelSize(_ data: Data) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return (image.width, image.height)
}

/// (x, y) 픽셀의 RGB(위가 y=0).
private func phPixel(_ data: Data, x: Int, y: Int) -> (Int, Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var pixel = [UInt8](repeating: 0, count: 4)
    guard let context = CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
}

@MainActor
private func phSeedImage(_ store: WorkTimerStore, path: String, width: Int = 400, height: Int = 300) {
    store.messagePhotoImages.insert(MessagePhotoImageBox(phImage(width: width, height: height)), data: nil, path: path, owner: Fx.me)
}

/// 미리 보기에 세울 고른 사진(인코더를 진짜로 지난다).
@MainActor
private func phDraft(peer: String = Fx.peerA, width: Int = 1_200, height: Int = 900) throws -> MessagePhotoDraft {
    let png = phEncode(phImage(width: width, height: height), type: .png)
    let (encoded, box) = try #require(MessagePhotoEncoder.encode(data: png))
    return MessagePhotoDraft(id: MessagePhotoPath.newID(), peer: peer, encoded: encoded, preview: box)
}

/// 대화가 열린 상태(패널 · 상대)를 직접 세운다 — 사진 칸 조회를 부르는 문(`openMessagePanel`)을 안 지난다.
@MainActor
private func phOpen(_ store: WorkTimerStore, peer: String = Fx.peerA) {
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = peer
    store.messageSendRetrySleep = { _ in }
    store.messagePhotoMetaDebounceSleep = { _ in }
}

private func phStorageCalls(_ host: String) -> [MessageReadStubProtocol.Call] {
    MessageReadStubProtocol.calls(host: host).filter { $0.path.hasPrefix("/storage/v1/") }
}

private func phMetaCalls(_ host: String) -> [MessageReadStubProtocol.Call] {
    MessageReadStubProtocol.calls(host: host, rpc: "message_page")
}

private func phRefused() -> Reply {
    // 저장소는 정책 거절을 HTTP 400 + 본문 statusCode "403" 으로 말하는 판이 있다.
    Reply(status: 400, body: #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#)
}

// MARK: - ① 전선

@Test
func 사진_경로와_크기는_서버_모양만_받는다() {
    #expect(MessagePhotoPath.isServerShaped(PhFx.peerPhotoPath))
    #expect(MessagePhotoPath.isServerShaped("\(Fx.me)/\(PhFx.otherPhotoID).png"))
    #expect(!MessagePhotoPath.isServerShaped(PhFx.peerPhotoPath.uppercased()), "대문자 경로는 서버 정책이 거절한다")
    #expect(!MessagePhotoPath.isServerShaped("\(Fx.me)/\(PhFx.otherPhotoID).gif"), "서버가 안 받는 확장자")
    #expect(!MessagePhotoPath.isServerShaped("\(Fx.me)/photo.jpg"), "이름이 uuid 가 아니다")
    #expect(!MessagePhotoPath.isServerShaped("\(Fx.me)/../\(PhFx.otherPhotoID).jpg"))
    #expect(!MessagePhotoPath.isServerShaped("a/\(Fx.me)/\(PhFx.otherPhotoID).jpg"), "폴더가 둘이다")
    // 올리기 경로는 소문자다(Swift uuid 는 대문자 — 그대로 쓰면 자기 폴더에 못 올린다).
    let id = MessagePhotoPath.newID()
    #expect(id == id.lowercased() && UUID(uuidString: id) != nil)
    let upload = MessagePhotoPath.uploadPath(owner: Fx.me.uppercased(), id: id.uppercased())
    #expect(upload == "\(Fx.me)/\(id).jpg")
    #expect(MessagePhotoPath.isServerShaped(upload))

    #expect(MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 1_600, height: 1_200) != nil)
    #expect(MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 0, height: 1_200) == nil)
    #expect(MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 20_001, height: 10) == nil)
    #expect(MessagePhotoAttachment(path: nil, width: 10, height: 10) == nil)
    #expect(MessagePhotoAttachment(path: "x/y.jpg", width: 10, height: 10) == nil)
}

@Test
func 사진_말풍선_크기_규칙은_200_상자_안이고_비율을_지키며_하한은_60이다() {
    // 가로 사진 — 내 말은 200 폭, 받은 말은 170 폭(패널 밖으로 안 밀리게).
    #expect(MessagePhotoLayout.bubbleSize(width: 1_600, height: 1_200) == CGSize(width: 200, height: 150))
    let received = MessagePhotoLayout.bubbleSize(
        for: MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 1_600, height: 1_200)!, isMine: false
    )
    #expect(received == CGSize(width: 170, height: 128))
    // 세로 사진 — 높이 200.
    #expect(MessagePhotoLayout.bubbleSize(width: 900, height: 1_600) == CGSize(width: 113, height: 200))
    // 아주 긴 사진 — 짧은 변이 하한 60(넘치는 쪽은 잘라 그린다).
    #expect(MessagePhotoLayout.bubbleSize(width: 4_000, height: 100) == CGSize(width: 200, height: 60))
    // 작은 사진은 키우지 않는다(1pt = 1px 까지) — 하한만 지킨다.
    #expect(MessagePhotoLayout.bubbleSize(width: 120, height: 90) == CGSize(width: 120, height: 90))
    #expect(MessagePhotoLayout.bubbleSize(width: 20, height: 20) == CGSize(width: 60, height: 60))
    for (w, h) in [(1, 1), (20_000, 1), (1, 20_000), (3_000, 2_000), (64, 4_096)] {
        let size = MessagePhotoLayout.bubbleSize(width: w, height: h)
        #expect(size.width <= 200 && size.height <= 200 && size.width >= 60 && size.height >= 60, "\(w)×\(h) → \(size)")
    }
}

@MainActor
@Test
func 사진_덮개는_가장_좁은_대화_자리에도_넘치지_않는다() {
    let heights: [CGFloat] = [MessagePanelLayout.minConversationHeight, 120, MessagePanelLayout.conversationHeight]
    let pad: CGFloat = MessagePhotoOverlayLayout.padding * 2
    let gap: CGFloat = MessagePhotoOverlayLayout.spacing
    let buttons: CGFloat = MessagePhotoOverlayLayout.buttonHeight
    for available in heights {
        for hasNote in [false, true] {
            let box: CGSize = MessagePhotoOverlayLayout.imageBox(availableHeight: available, hasNote: hasNote)
            let title: CGFloat = MessagePhotoOverlayLayout.showsTitle(availableHeight: available)
                ? MessagePhotoOverlayLayout.titleHeight + gap : 0
            let note: CGFloat = MessagePhotoOverlayLayout.showsNote(availableHeight: available, hasNote: hasNote)
                ? MessagePhotoOverlayLayout.noteHeight + gap : 0
            let used: CGFloat = pad + title + box.height + note + gap + buttons
            #expect(used <= available, "미리 보기가 \(available)pt 자리를 넘친다(\(used)pt · 안내 \(hasNote))")
        }
        let viewer: CGSize = MessagePhotoOverlayLayout.viewerBox(availableHeight: available)
        let viewerUsed: CGFloat = pad + viewer.height + gap + buttons
        #expect(viewerUsed <= available, "크게 보기가 \(available)pt 자리를 넘친다")
        #expect(viewer.width <= MessagePanelLayout.contentWidth)
    }
}

@Test
func 사진_보내기_요청은_여섯_키를_null까지_싣고_응답은_서비스_디코더로_읽는다() async throws {
    let host = "photo-wire-\(UUID().uuidString.prefix(8))".lowercased()
    let replies: [String] = [
        #"{"status":"ok","ring":"sent","message_id":"m1","created_at":"2026-09-21T12:00:00+00:00","duplicate":false,"body":"📷 사진","photo_path":"\#(PhFx.minePhotoPath)","photo_width":1600,"photo_height":1200}"#,
        #"{"status":"ok","ring":"duplicate","message_id":"m1","created_at":"2026-09-21T12:00:00+00:00","duplicate":true,"body":"📷 사진","photo_path":"\#(PhFx.minePhotoPath)","photo_width":1600,"photo_height":1200}"#,
        #"{"status":"unsupported_client","door_open":false}"#,
        #"{"status":"unsupported_client","door_open":true}"#,
        #"{"status":"invalid_photo"}"#,
        #"{"status":"photo_missing"}"#,
        #"{"status":"target_focused"}"#,
        #"{"status":"flood"}"#,
        #"{"status":"blocked"}"#,
        #"{"status":"too_long","max_length":200}"#
    ]
    MessageReadStubProtocol.register(host: host) { call, index in
        call.rpc == "send_photo_message" ? Reply(body: replies[min(index, replies.count - 1)]) : nil
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: MessageReadStubProtocol.session()
    )
    let noCaption = SendPhotoMessageRequest(
        to: Fx.peerA, path: PhFx.minePhotoPath, width: 1_600, height: 1_200, caption: nil, clientMessageID: PhFx.otherPhotoID
    )
    var outcomes: [MessagePhotoSendOutcome] = []
    var first: SendPhotoMessageResponse?
    for index in 0..<replies.count {
        let request = index == 1
            ? SendPhotoMessageRequest(to: Fx.peerA, path: PhFx.minePhotoPath, width: 1_600, height: 1_200,
                                      caption: "주말 사진", clientMessageID: PhFx.otherPhotoID)
            : noCaption
        let response = try await service.sendPhotoMessage(accessToken: "access-token", request: request)
        if index == 0 { first = response }
        outcomes.append(MessagePhotoSendOutcome(response: response))
    }
    #expect(outcomes == [
        .message(.ok), .message(.ok), .unsupportedClient(doorOpen: false), .unsupportedClient(doorOpen: true),
        .invalidPhoto, .photoMissing, .message(.targetFocused), .message(.flood), .message(.invalid), .message(.tooLong)
    ])
    // ok 응답의 공용 칸과 사진 칸(스네이크 → 카멜, 진짜 디코더).
    let ok = try #require(first)
    #expect(ok.send.messageId == "m1" && ok.send.createdAt != nil && ok.send.body == MessageNoticeText.photoFallbackBody)
    #expect(ok.attachment == MessagePhotoAttachment(path: PhFx.minePhotoPath, width: 1_600, height: 1_200))

    // 요청 본문: 여섯 키가 **언제나** 있고, 설명이 없으면 명시적 null 이다(PostgREST 는 키 집합으로 함수를 고른다).
    let sent = MessageReadStubProtocol.calls(host: host, rpc: "send_photo_message")
    let expectedKeys: Set<String> = ["p_to", "p_path", "p_width", "p_height", "p_caption", "p_client_message_id"]
    #expect(sent.allSatisfy { Set($0.json.keys) == expectedKeys }, "본문 키 집합: \(sent.first?.body ?? "")")
    #expect(Set(SendPhotoMessageRequest.CodingKeys.allCases.map(\.rawValue)) == expectedKeys)
    #expect(sent[0].body.contains("\"p_caption\":null"), "설명이 없을 때 키를 뺐다: \(sent[0].body)")
    #expect(sent[1].json["p_caption"] as? String == "주말 사진")
    #expect(sent[0].json["p_client_message_id"] as? String == PhFx.otherPhotoID)
    #expect((sent[0].json["p_width"] as? NSNumber)?.intValue == 1_600)
    #expect(sent[0].method == "POST")
}

@Test
func 사진_message_page_행은_entry_photo_로_가고_사진만_보낸_줄은_빈_글이다() async throws {
    let service = SupabaseWorkService(projectURL: URL(string: "http://photo-page-decode")!, anonKey: "anon-test-key")
    let rows: [Any] = [
        PhFx.pageRow(id: "p3", isMine: true, secondsAgo: 100, caption: "주말에 찍었어요", photoPath: PhFx.minePhotoPath, width: 1_200, height: 1_600),
        PhFx.pageRow(id: "p2", isMine: false, secondsAgo: 200, caption: nil, photoPath: PhFx.peerPhotoPath),
        // 경로가 서버 모양이 아니다(대문자) — 사진 없이 글로 그린다.
        PhFx.pageRow(id: "p1", isMine: false, secondsAgo: 300, caption: nil, photoPath: PhFx.peerPhotoPath.uppercased()),
        PhFx.pageRow(id: "p0", isMine: false, secondsAgo: 400, caption: "그냥 말", photoPath: nil),
        PhFx.pageRow(id: "mega", isMine: false, secondsAgo: 500, caption: "공지", photoPath: nil, megaphone: true)
    ]
    let page = try await service.messagePage(from: Data(Fx.json(rows).utf8), peer: Fx.peerA, me: Fx.me, limit: 30)
    #expect(page.entries.map(\.id) == ["p0", "p1", "p2", "p3"])
    let photoOnly = try #require(page.entries.first { $0.id == "p2" })
    #expect(photoOnly.photo == MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 1_600, height: 1_200))
    #expect(photoOnly.body.isEmpty, "사진만 보낸 줄의 글이 비어 있지 않다 — 사진 아래 '📷 사진'이 또 그려진다")
    #expect(photoOnly.photoCaption == nil)
    let captioned = try #require(page.entries.first { $0.id == "p3" })
    #expect(captioned.photo?.width == 1_200 && captioned.photo?.height == 1_600)
    #expect(captioned.body == "주말에 찍었어요" && captioned.photoCaption == "주말에 찍었어요")
    #expect(page.entries.first { $0.id == "p1" }?.photo == nil)
    #expect(page.entries.first { $0.id == "p1" }?.body == MessageNoticeText.photoFallbackBody, "깨진 사진 줄이 글로 접히지 않았다")
    #expect(page.entries.first { $0.id == "p0" }?.photo == nil)
    // 버린 확성기 줄도 "물어본 줄"이다(사진 칸 조회의 덮은 id).
    #expect(page.rowIDs == ["p3", "p2", "p1", "p0", "mega"])
    // 지난 쪽 모양으로 옮겨도 사진은 남는다(안 읽음 칸만 비운다).
    let paged = MessageOlderHistoryRules.pageEntry(captioned)
    #expect(paged.photo == captioned.photo && paged.body == captioned.body)
    // 머리 줄에 배운 사진을 얹으면 글은 설명(사진만이면 빈 글)이고 나머지 칸은 그대로다.
    let head = PhFx.entry("h1", body: MessageNoticeText.photoFallbackBody, isMine: false)
    let shown = head.withPhoto(photoOnly.photo!, caption: nil)
    #expect(shown.body.isEmpty && shown.photo == photoOnly.photo && shown.isUnread == head.isUnread && shown.createdAt == head.createdAt)
}

@Test
func 사진_신고된_사진_경로는_한_번에_묻고_서버_모양만_받는다() async throws {
    let host = "photo-admin-wire-\(UUID().uuidString.prefix(8))".lowercased()
    MessageReadStubProtocol.register(host: host) { call, _ in
        guard call.rpc == "report_admin_photo_paths" else { return nil }
        return Reply(body: Fx.json([
            ["report_id": "r1", "photo_path": PhFx.peerPhotoPath],
            ["report_id": "r2", "photo_path": "../x.jpg"],
            "깨진 원소",
            ["report_id": NSNull(), "photo_path": PhFx.otherPhotoPath]
        ]))
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: MessageReadStubProtocol.session()
    )
    let paths = try await service.fetchReportAdminPhotoPaths(accessToken: "access-token", ids: ["r1", "r2", "r3"])
    #expect(paths == ["r1": PhFx.peerPhotoPath])
    let sent = try #require(MessageReadStubProtocol.calls(host: host, rpc: "report_admin_photo_paths").first)
    #expect(Set(sent.json.keys) == ["p_ids"])
    #expect(sent.json["p_ids"] as? [String] == ["r1", "r2", "r3"])
    // 빈 목록은 묻지 않는다.
    #expect(try await service.fetchReportAdminPhotoPaths(accessToken: "access-token", ids: []).isEmpty)
    #expect(MessageReadStubProtocol.count(host: host, rpc: "report_admin_photo_paths") == 1)
    // 서버 모양이 아닌 경로는 올리지도 받지도 않는다(요청 없음).
    await #expect(throws: PrivateStorageError.invalidPath) {
        try await service.uploadMessagePhoto(accessToken: "access-token", path: "\(Fx.me)/photo.jpg", data: Data([1]))
    }
    await #expect(throws: PrivateStorageError.invalidPath) {
        try await service.fetchMessagePhotoData(accessToken: "access-token", path: "../../etc.jpg")
    }
    #expect(phStorageCalls(host).isEmpty)
}

@Test
func 사진_받기는_서명_URL_로_두_번_왕복하고_로그인_토큰을_서명_주소에_안_싣는다() async throws {
    let host = "photo-sign-\(UUID().uuidString.prefix(8))".lowercased()
    MessageReadStubProtocol.register(host: host) { call, _ in
        // 서명(POST)과 받기(GET)는 같은 경로다 — 받기는 쿼리에 서명 토큰을 싣는다.
        guard call.path == "/storage/v1/object/sign/message-photos/\(PhFx.peerPhotoPath)" else { return nil }
        return call.method == "POST"
            ? Reply(body: #"{"signedURL":"/object/sign/message-photos/\#(PhFx.peerPhotoPath)?token=signed-token"}"#)
            : Reply(body: "jpeg-bytes")
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: MessageReadStubProtocol.session()
    )
    let data = try await service.fetchMessagePhotoData(accessToken: "access-token", path: PhFx.peerPhotoPath)
    #expect(data == Data("jpeg-bytes".utf8))
    let calls = phStorageCalls(host)
    #expect(calls.count == 2, "서명 → 받기 두 왕복이 아니다: \(calls.map(\.path))")
    #expect(calls.first?.method == "POST" && calls.first?.json["expiresIn"] as? Int == MessagePhotoText.signedURLSeconds)
    #expect(calls.last?.method == "GET")
    #expect(calls.last?.url.query?.contains("token=signed-token") == true)
    #expect(calls.last?.headers["Authorization"] == nil, "서명 주소에 로그인 토큰을 실었다")
}

// MARK: - ② 스토어 — 보내기

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_보내기는_소문자_경로로_올리고_같은_uuid_로_RPC_를_부르고_그_자리에_그린다() async throws {
    let (store, host) = makeMessageReadStore("photo-send") { call, _ in
        call.rpc == "send_photo_message" ? PhFx.okReply(for: call, messageID: "m-photo-1") : nil
    }
    phOpen(store)
    // 고르기: 진짜 인코더를 지나 미리 보기 덮개가 선다(떼어 낸 작업).
    let png = phEncode(phImage(width: 2_400, height: 1_800), type: .png)
    store.pickMessagePhoto(imageData: png)
    #expect(store.messagePhotoPreparing && store.messagePhotoOverlayShown)
    await messageReadWait { store.messagePhotoDraft != nil }
    let draft = try #require(store.selectedMessagePhotoDraft)
    #expect(!store.messagePhotoPreparing)
    #expect(max(draft.encoded.pixelWidth, draft.encoded.pixelHeight) == MessagePhotoEncoder.maxPixelSide)
    #expect(draft.id == draft.id.lowercased())

    store.messageDraft = "주말에 찍은 사진이에요"
    store.sendMessagePhotoDraft()
    #expect(store.isSendingMessage, "왕복 잠금이 안 섰다(글 · 이모티콘이 끼어든다)")
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 1 }

    // 올리기: POST · 경로 정확히 · image/jpeg · x-upsert 없음 · 로그인 토큰.
    let path = "\(Fx.me)/\(draft.id).jpg"
    let uploads = phStorageCalls(host)
    #expect(uploads.count == 1)
    let upload = try #require(uploads.first)
    #expect(upload.method == "POST")
    #expect(upload.path == "/storage/v1/object/message-photos/\(path)", "올리기 경로: \(upload.path)")
    #expect(upload.headers["Content-Type"] == "image/jpeg")
    #expect(!upload.headers.keys.contains { $0.lowercased() == "x-upsert" }, "덮어쓰기 머리를 실었다(서버에 고치기 정책이 없다)")
    #expect(upload.headers["Authorization"] == "Bearer access-token")
    #expect(upload.byteCount == draft.encoded.data.count)

    // RPC: 같은 uuid 가 파일 이름이자 멱등 키다 · 설명은 입력칸의 글.
    let rpc = try #require(MessageReadStubProtocol.calls(host: host, rpc: "send_photo_message").first)
    #expect(rpc.json["p_path"] as? String == path)
    #expect(rpc.json["p_client_message_id"] as? String == draft.id)
    #expect(rpc.json["p_to"] as? String == Fx.peerA)
    #expect(rpc.json["p_caption"] as? String == "주말에 찍은 사진이에요")
    #expect((rpc.json["p_width"] as? NSNumber)?.intValue == draft.encoded.pixelWidth)
    #expect((rpc.json["p_height"] as? NSNumber)?.intValue == draft.encoded.pixelHeight)
    let order = MessageReadStubProtocol.calls(host: host).map(\.path)
    let uploadIndex = try #require(order.firstIndex { $0.hasPrefix("/storage/") })
    let rpcIndex = try #require(order.firstIndex { $0.hasSuffix("send_photo_message") })
    #expect(uploadIndex < rpcIndex, "올리기 전에 RPC 를 불렀다(받는 사람이 깨진 사진을 본다)")

    // 결과: 글을 보낸 것과 같은 처리(문구 · 초안 비우기 · 확정 줄) + 사진 칸 + 그림 캐시(내 사진은 받지 않는다).
    #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
    #expect(store.messageDraft.isEmpty, "설명으로 간 글이 입력칸에 남았다 — 다음 Enter 에 또 나간다")
    #expect(store.messagePhotoDraft == nil)
    let row = try #require(store.messageHistory.first { $0.id == "m-photo-1" }, "확정 줄이 안 섰다")
    #expect(row.photo == nil && row.body == "주말에 찍은 사진이에요", "24시간 머리 줄 모양이 바뀌었다")
    let shown = try #require(store.messagePhotoDisplayed(store.selectedConversationMessages).first { $0.id == "m-photo-1" })
    #expect(shown.photo?.path == path && shown.body == "주말에 찍은 사진이에요")
    #expect(store.messagePhotoImage(for: path) != nil, "보낸 사진을 캐시에 안 넣었다(받으러 간다)")
    #expect(store.messagePhotoSaveData(path: path) == draft.encoded.data)
    #expect(!MessageReadStubProtocol.calls(host: host).contains { $0.path.contains("/object/sign/") }, "내 사진을 다시 받으러 갔다")
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_답을_못_받으면_같은_uuid_로_한_번_더_보내고_다시_올리기_409_는_성공이다() async throws {
    let (store, host) = makeMessageReadStore("photo-retry") { call, index in
        if call.path.hasPrefix("/storage/v1/object/message-photos/") {
            return index == 0
                ? Reply(status: 503, body: #"{"message":"upstream"}"#)
                : Reply(status: 400, body: #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#)
        }
        if call.rpc == "send_photo_message" {
            return index == 0 ? Reply(status: 504, body: #"{"message":"timeout"}"#) : PhFx.okReply(for: call, messageID: "m-retry", duplicate: true)
        }
        return nil
    }
    phOpen(store)
    let draft = try phDraft()
    store.messagePhotoDraft = draft
    store.sendMessagePhotoDraft()
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 2 }

    let uploads = phStorageCalls(host)
    #expect(uploads.count == 2, "올리기 재시도가 한 번이 아니다: \(uploads.count)")
    #expect(Set(uploads.map(\.path)).count == 1, "재시도가 다른 이름으로 올렸다 — 고아 파일이 생긴다")
    let rpcs = MessageReadStubProtocol.calls(host: host, rpc: "send_photo_message")
    #expect(rpcs.count == 2)
    #expect(Set(rpcs.compactMap { $0.json["p_client_message_id"] as? String }) == [draft.id], "재시도가 다른 멱등 키를 썼다")
    #expect(Set(rpcs.compactMap { $0.json["p_path"] as? String }) == ["\(Fx.me)/\(draft.id).jpg"])
    // 409(우리 앞 시도의 파일)는 "이미 가입된 이메일"이 아니다 — 성공으로 이어졌다.
    #expect(store.messageNotice == WorkTimerStore.messageSentNotice, "문구: \(store.messageNotice ?? "nil")")
    #expect(store.messageHistory.contains { $0.id == "m-retry" })
    #expect(store.messagePhotoDraft == nil)
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_올리기가_거절되면_RPC_로_사유를_가르고_문이_닫혔으면_버튼을_다음_열기까지_숨긴다() async throws {
    let state = PhBox()
    let (store, host) = makeMessageReadStore("photo-door") { call, _ in
        if call.path.hasPrefix("/storage/v1/object/message-photos/") { return phRefused() }
        if call.rpc == "send_photo_message" {
            return state.has("missing")
                ? Reply(body: #"{"status":"photo_missing"}"#)
                : Reply(body: #"{"status":"unsupported_client","door_open":false}"#)
        }
        return nil
    }
    phOpen(store)
    #expect(store.showsMessagePhotoButton && store.canSendPhotoNow)
    store.messageDraft = "쓰던 글"
    store.messagePhotoDraft = try phDraft()
    store.sendMessagePhotoDraft()
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 1 }
    #expect(phStorageCalls(host).count == 1, "거절된 올리기를 다시 보냈다")
    let classify = try #require(MessageReadStubProtocol.calls(host: host, rpc: "send_photo_message").first)
    #expect((classify.json["p_path"] as? String)?.hasPrefix("\(Fx.me)/") == true, "사유를 가르는 호출이 그 경로를 안 실었다")
    #expect(store.messageNotice == MessagePhotoText.doorClosedNotice)
    #expect(store.messagePhotoSendClosed && !store.showsMessagePhotoButton, "문이 닫혔는데 [사진] 버튼이 남았다")
    #expect(!store.canSendPhotoNow)
    #expect(store.messagePhotoDraft == nil)
    #expect(store.messageDraft == "쓰던 글", "문이 닫혔다고 쓰던 글을 지웠다")
    #expect(!store.messageHistory.contains { $0.isMine })

    // 다음 패널 열기에서 되살린다(숨김을 영구히 들지 않는다 — 문은 출시 때 열린다).
    store.closeMessagePanel()
    store.openMessagePanel(peer: Fx.peerA)
    #expect(store.showsMessagePhotoButton && !store.messagePhotoSendClosed)

    // 파일 없음(한 시간 상한 등으로 거절됐다) — "사진을 올리지 못했어요", 고른 사진은 남는다(다시 [보내기]).
    state.set("missing")
    phOpen(store)
    store.messagePhotoDraft = try phDraft()
    store.sendMessagePhotoDraft()
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 2 }
    #expect(store.messageNotice == MessagePhotoText.uploadFailedNotice)
    #expect(store.messagePhotoDraft != nil, "실패했는데 고른 사진이 사라졌다")
    #expect(store.messagePhotoDraft?.uploaded == false)
    #expect(store.showsMessagePhotoButton)
    await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_잘못된_사진은_새_이름으로_다시_올리고_공용_거절은_글과_같은_문구다() async throws {
    let state = PhBox()
    let (store, host) = makeMessageReadStore("photo-invalid") { call, _ in
        guard call.rpc == "send_photo_message" else { return nil }
        state.bump()
        return state.count() == 1 ? Reply(body: #"{"status":"invalid_photo"}"#) : Reply(body: #"{"status":"target_focused"}"#)
    }
    phOpen(store)
    let first = try phDraft()
    store.messagePhotoDraft = first
    store.sendMessagePhotoDraft()
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 1 }
    #expect(store.messageNotice == MessagePhotoText.invalidPhotoNotice)
    let renewed = try #require(store.messagePhotoDraft, "잘못된 사진 하나에 고른 사진을 버렸다")
    #expect(renewed.id != first.id && !renewed.uploaded && renewed.encoded == first.encoded)

    store.sendMessagePhotoDraft()
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 2 }
    #expect(phStorageCalls(host).count == 2)
    #expect(phStorageCalls(host).last?.path.contains(renewed.id) == true, "새 이름으로 다시 안 올렸다")
    // 공용 거절은 글 보내기와 **같은 문구**(같은 함수 `applyMessageSendOutcome`).
    #expect(store.messageNotice == WorkTimerStore.messageTargetFocusedNotice)
    #expect(store.messagePhotoDraft != nil)
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_미리_보기가_떠_있으면_입력칸의_보내기가_사진과_설명을_함께_보낸다() async throws {
    let (store, host) = makeMessageReadStore("photo-enter") { call, _ in
        call.rpc == "send_photo_message" ? PhFx.okReply(for: call, messageID: "m-enter") : nil
    }
    phOpen(store)
    store.messagePhotoDraft = try phDraft()
    store.messageDraft = "설명으로 갈 글"
    // ↩ · ⌘↩ · [보내기]가 지나는 문 하나(조합 확정 → `sendDraftMessage`).
    MessageComposerView(store: store).send()
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 1 }
    #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 0, "글이 사진과 따로 나갔다")
    #expect(MessageReadStubProtocol.calls(host: host, rpc: "send_photo_message").first?.json["p_caption"] as? String == "설명으로 갈 글")
    #expect(store.messageDraft.isEmpty && store.messagePhotoDraft == nil)
    // 미리 보기가 없으면 예전 그대로 글이다.
    store.messageDraft = "그냥 글"
    MessageComposerView(store: store).send()
    await messageReadWait { !store.isSendingMessage && MessageReadStubProtocol.count(host: host, rpc: "send_message") == 1 }
    #expect(MessageReadStubProtocol.count(host: host, rpc: "send_photo_message") == 1)
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_왕복_중이나_집중이면_고르지_않고_사유를_말한다() async throws {
    let (store, _) = makeMessageReadStore("photo-gate")
    phOpen(store)
    store.isSendingMessage = true
    #expect(!store.canSendPhotoNow)
    store.pickMessagePhoto(imageData: phEncode(phImage(width: 40, height: 30), type: .png))
    #expect(!store.messagePhotoPreparing && store.messagePhotoDraft == nil)
    #expect(store.messageNotice == AingStickerText.sendingNowNotice)
    store.isSendingMessage = false
    // 상대 없음 — 버튼도 없다.
    store.selectedMessagePeerID = nil
    #expect(!store.showsMessagePhotoButton && !store.canSendPhotoNow)
}

// MARK: - ② 스토어 — 사진 칸

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_칸은_대화를_열_때와_새로_받은_줄에서만_묻고_팝오버_열기나_새로고침은_안_묻는다() async throws {
    let state = PhBox()
    let (store, host) = makeMessageReadStore("photo-meta") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            var rows = [
                PhFx.head("a1", isMine: false, secondsAgo: 600, body: MessageNoticeText.photoFallbackBody),
                PhFx.head("a2", isMine: true, secondsAgo: 300, body: "잘 봤어요")
            ]
            if state.has("arrival") {
                rows.append(PhFx.head("a3", isMine: false, secondsAgo: 30, body: "이것도 보세요"))
            }
            if state.has("mine") {
                rows.append(PhFx.head("a4", isMine: true, secondsAgo: 10, body: "고마워요"))
            }
            return Fx.historyReply(rows)
        case "message_page":
            var rows: [Any] = [
                PhFx.pageRow(id: "a2", isMine: true, secondsAgo: 300, caption: "잘 봤어요", photoPath: nil),
                PhFx.pageRow(id: "a1", isMine: false, secondsAgo: 600, caption: nil, photoPath: PhFx.peerPhotoPath)
            ]
            if state.has("arrival") {
                rows.insert(PhFx.pageRow(id: "a3", isMine: false, secondsAgo: 30, caption: "이것도 보세요", photoPath: PhFx.otherPhotoPath), at: 0)
            }
            return Reply(body: Fx.json(rows))
        case "message_unread_summary": return Fx.summaryReply([])
        default: return nil
        }
    }
    store.messagePhotoMetaDebounceSleep = { _ in }
    store.isMenuPresented = true
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messageHistoryLoaded && messageReadIdle(store) && store.messagePhotoMetaIdle }
    #expect(phMetaCalls(host).count == 1, "대화를 열 때 사진 칸을 한 번 묻지 않았다(또는 더 물었다)")
    let first = try #require(phMetaCalls(host).first)
    #expect(Set(first.json.keys) == ["p_peer", "p_before_us", "p_before_id", "p_limit"])
    #expect((first.json["p_limit"] as? NSNumber)?.intValue == MessagePhotoText.metaPageLimit)
    #expect(first.body.contains("\"p_before_us\":null") && first.body.contains("\"p_before_id\":null"))
    #expect(first.json["p_peer"] as? String == Fx.peerA)

    // 머리 줄은 그대로(사진 칸 없음 · 본문 '📷 사진'), 그릴 때만 사진이 얹힌다.
    let a1 = try #require(store.messageHistory.first { $0.id == "a1" })
    #expect(a1.photo == nil && a1.body == MessageNoticeText.photoFallbackBody)
    let shown = store.messagePhotoDisplayed(store.selectedConversationMessages)
    #expect(shown.first { $0.id == "a1" }?.photo?.path == PhFx.peerPhotoPath)
    #expect(shown.first { $0.id == "a1" }?.body.isEmpty == true)
    #expect(shown.first { $0.id == "a2" }?.photo == nil)
    #expect(shown.map(\.id) == store.selectedConversationMessages.map(\.id), "사진을 얹다가 줄 순서 · 수가 바뀌었다")

    // 팝오버 열기 · 새로고침(같은 줄) — 묻지 않는다.
    store.refreshMessageActivityOnMenuOpen()
    await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
    _ = store.requestMessageActivityRefresh(includeHistory: true)
    await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
    await store.performLoadMessageHistory()
    await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
    #expect(phMetaCalls(host).count == 1, "팝오버 열기 · 새로고침이 사진 칸을 물었다(기존 요청 수가 바뀐다)")

    // 내 말이 새로 와도(이 맥이 보낸 것이면 이미 안다) 묻지 않는다.
    state.set("mine")
    await store.performLoadMessageHistory()
    await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
    #expect(phMetaCalls(host).count == 1, "내 말 때문에 사진 칸을 물었다")

    // 받은 말이 새로 오면 한 번 묻는다(합쳐서).
    state.set("arrival")
    await store.performLoadMessageHistory()
    await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
    #expect(phMetaCalls(host).count == 2, "새로 받은 줄의 사진 칸을 안 물었다")
    #expect(store.messagePhotoDisplayed(store.selectedConversationMessages).first { $0.id == "a3" }?.photo?.path == PhFx.otherPhotoPath)
    // 다시 받아도 같은 줄이면 더 묻지 않는다.
    await store.performLoadMessageHistory()
    await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
    #expect(phMetaCalls(host).count == 2)

    // 닫으면 사진 칸을 걷는다(가장 사적인 표면). 다시 열면 다시 묻는다.
    store.closeMessagePanel()
    #expect(store.messagePhotoMeta.isEmpty)
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messagePhotoMetaIdle && messageReadIdle(store) }
    #expect(phMetaCalls(host).count == 3)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_칸_함수가_없는_서버면_숨기고_다음_패널_열기에서_다시_묻는다() async throws {
    let state = PhBox()
    // `message_page` 는 스텁 기본값이 404 PGRST202 다.
    let (store, host) = makeMessageReadStore("photo-meta-404") { call, _ in
        guard call.rpc == "message_history_with_reads" else { return nil }
        var rows = [PhFx.head("a1", isMine: false, secondsAgo: 600, body: MessageNoticeText.photoFallbackBody)]
        if state.has("arrival") { rows.append(PhFx.head("a2", isMine: false, secondsAgo: 30, body: "새 말")) }
        return Fx.historyReply(rows)
    }
    store.messagePhotoMetaDebounceSleep = { _ in }
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messageHistoryLoaded && store.messagePhotoMetaIdle && messageReadIdle(store) }
    #expect(phMetaCalls(host).count == 1)
    #expect(store.messagePhotoMetaAvailable == false)
    // 사진 줄은 글('📷 사진')로 그린다 — 사진 칸이 없다.
    #expect(store.messagePhotoDisplayed(store.selectedConversationMessages).allSatisfy { $0.photo == nil })
    #expect(store.messageOlderAvailable == nil, "사진 칸 조회가 [이전 대화 더 보기]의 판정을 바꿨다")

    state.set("arrival")
    await store.performLoadMessageHistory()
    await messageReadWait { store.messagePhotoMetaIdle && messageReadIdle(store) }
    #expect(phMetaCalls(host).count == 1, "함수가 없는 서버에 다시 물었다")

    store.closeMessagePanel()
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messagePhotoMetaIdle && messageReadIdle(store) }
    #expect(phMetaCalls(host).count == 2, "다음 패널 열기에서 다시 묻지 않았다(숨김을 영구히 들었다)")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_칸을_배워도_안_읽음_점과_읽음_처리는_그대로다() async throws {
    func run(withPhotos: Bool) async -> (marks: [String], unread: Set<String>, head: [MessageHistoryEntry], shown: [MessageHistoryEntry]) {
        let marked = PhBox()
        let (store, host) = makeMessageReadStore("photo-read-\(withPhotos)") { call, _ in
            switch call.rpc {
            case "message_history_with_reads":
                return Fx.historyReply([
                    PhFx.head("a0", isMine: true, secondsAgo: 900, body: "먼저 보낸 말"),
                    PhFx.head("a1", isMine: false, secondsAgo: 600, body: MessageNoticeText.photoFallbackBody, unread: !marked.has("read"))
                ])
            case "mark_messages_read":
                marked.set("read")
                return Fx.markReply()
            case "message_unread_summary":
                return Fx.summaryReply(marked.has("read") ? [] : [(Fx.peerA, 1)])
            case "message_page" where withPhotos:
                return Reply(body: Fx.json([
                    PhFx.pageRow(id: "a1", isMine: false, secondsAgo: 600, caption: nil, photoPath: PhFx.peerPhotoPath),
                    PhFx.pageRow(id: "a0", isMine: true, secondsAgo: 900, caption: "먼저 보낸 말", photoPath: nil)
                ]))
            default: return nil
            }
        }
        store.messagePhotoMetaDebounceSleep = { _ in }
        store.isMenuPresented = true
        store.openMessagePanel(peer: Fx.peerA)
        await messageReadWait {
            MessageReadStubProtocol.count(host: host, rpc: "mark_messages_read") >= 1 && messageReadIdle(store) && store.messagePhotoMetaIdle
        }
        try? await Task.sleep(for: .milliseconds(80))
        await messageReadWait { messageReadIdle(store) && store.messagePhotoMetaIdle }
        // 본문 키 순서는 인코더마다 다를 수 있다 — 키=값을 정렬해 견준다.
        let marks = MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").map { call in
            call.json.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&")
        }
        return (marks, store.unreadMessagePeerIDs, store.messageHistory, store.messagePhotoDisplayed(store.selectedConversationMessages))
    }
    let baseline = await run(withPhotos: false)
    let photos = await run(withPhotos: true)
    #expect(baseline.marks.count == 1)
    #expect(photos.marks == baseline.marks, "사진 칸 때문에 읽음 처리가 달라졌다: \(photos.marks) vs \(baseline.marks)")
    #expect(photos.unread == baseline.unread)
    #expect(photos.head == baseline.head, "사진 칸 때문에 24시간 머리가 바뀌었다")
    #expect(photos.shown.first { $0.id == "a1" }?.photo != nil, "전제: 사진 칸을 배웠다")
    #expect(baseline.shown.first { $0.id == "a1" }?.photo == nil)
}

// MARK: - ② 스토어 — 그림 캐시

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_그림은_경로마다_한_번만_받고_실패는_기억하며_사람이_누를_때만_다시_받는다() async throws {
    let (store, _) = makeMessageReadStore("photo-cache")
    let counter = PhBox()
    let jpeg = phEncode(phImage(width: 900, height: 600), type: .jpeg)
    store.messagePhotoDataLoader = { path in
        counter.bump(path)
        if path == PhFx.otherPhotoPath { throw URLError(.badServerResponse) }
        return jpeg
    }
    store.requestMessagePhotoImage(PhFx.peerPhotoPath)
    store.requestMessagePhotoImage(PhFx.peerPhotoPath)
    #expect(store.messagePhotoImages.state(for: PhFx.peerPhotoPath, owner: Fx.me) == .loading)
    await messageReadWait { store.messagePhotoImage(for: PhFx.peerPhotoPath) != nil }
    #expect(counter.count(PhFx.peerPhotoPath) == 1, "같은 경로를 두 번 받았다")
    let image = try #require(store.messagePhotoImage(for: PhFx.peerPhotoPath))
    #expect(max(image.width, image.height) <= MessagePhotoImageCache.displayPixels)
    store.requestMessagePhotoImage(PhFx.peerPhotoPath)
    #expect(store.messagePhotoImages.inFlightCount == 0)
    #expect(store.messagePhotoSaveData(path: PhFx.peerPhotoPath) == jpeg, "[저장…] 이 원본 바이트가 아니다")

    // 실패는 기억한다 — 보일 때마다 다시 받지 않는다. 사람이 실패 칸을 누르면 한 번 다시.
    store.requestMessagePhotoImage(PhFx.otherPhotoPath)
    await messageReadWait { store.messagePhotoImages.state(for: PhFx.otherPhotoPath, owner: Fx.me) == .failed }
    store.requestMessagePhotoImage(PhFx.otherPhotoPath)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(counter.count(PhFx.otherPhotoPath) == 1, "실패한 사진을 다시 받으러 갔다(고리)")
    store.retryMessagePhotoImage(PhFx.otherPhotoPath)
    await messageReadWait { counter.count(PhFx.otherPhotoPath) == 2 && store.messagePhotoImages.inFlightCount == 0 }
    #expect(counter.count(PhFx.otherPhotoPath) == 2)

    // 다른 계정의 눈에는 안 보인다.
    #expect(store.messagePhotoImages.image(for: PhFx.peerPhotoPath, owner: Fx.peerB) == nil)
    // 서버 모양이 아닌 경로는 받지 않는다.
    store.requestMessagePhotoImage("../x.jpg")
    #expect(counter.count("../x.jpg") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_로그아웃과_계정_바뀜이_그림_캐시와_사진_상태를_비운다() async throws {
    let (store, _) = makeMessageReadStore("photo-wipe")
    phOpen(store)
    phSeedImage(store, path: PhFx.peerPhotoPath)
    store.messagePhotoMeta[Fx.peerA] = ["a1": MessagePhotoMeta(attachment: MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 4, height: 3)!, caption: nil)]
    store.messagePhotoDraft = try phDraft()
    store.messagePhotoViewer = MessagePhotoViewerItem(
        photo: MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 4, height: 3)!, messageID: "a1", peerID: Fx.peerA, isMine: false
    )
    store.messagePhotoSendClosed = true
    store.reportAdminPhotoPaths = ["r1": PhFx.peerPhotoPath]
    #expect(store.messagePhotoImage(for: PhFx.peerPhotoPath) != nil)

    store.clearPersistedSession()
    #expect(store.messagePhotoImages.states.isEmpty && store.messagePhotoImages.owner == nil, "남의 비공개 사진이 다음 계정에 남았다")
    #expect(store.messagePhotoMeta.isEmpty && store.messagePhotoDraft == nil && store.messagePhotoViewer == nil)
    #expect(!store.messagePhotoSendClosed && store.messagePhotoMetaAvailable == nil)
    #expect(store.reportAdminPhotoPaths.isEmpty)

    // 계정이 바뀌면(로그아웃 없이 다른 계정의 그림이 들어와도) 앞 계정의 그림은 통째로 비운다.
    let cache = MessagePhotoImageCache()
    cache.insert(MessagePhotoImageBox(phImage(width: 8, height: 8)), data: nil, path: PhFx.peerPhotoPath, owner: Fx.me)
    #expect(cache.image(for: PhFx.peerPhotoPath, owner: Fx.me) != nil)
    #expect(cache.image(for: PhFx.peerPhotoPath, owner: Fx.peerB) == nil)
    cache.insert(MessagePhotoImageBox(phImage(width: 8, height: 8)), data: nil, path: PhFx.otherPhotoPath, owner: Fx.peerB)
    #expect(cache.image(for: PhFx.peerPhotoPath, owner: Fx.peerB) == nil && cache.states[PhFx.peerPhotoPath] == nil)
    #expect(cache.image(for: PhFx.otherPhotoPath, owner: Fx.peerB) != nil)
}

// MARK: - ② 붙여넣기 · 신고 · 운영자

@MainActor
@Test
func 사진_붙여넣기는_그림과_그림_파일만_받고_글이_함께_있으면_글이다() throws {
    // 사용자의 `NSPasteboard.general` 을 건드리지 않는다 — 이름 있는 판을 따로 만든다.
    let board = NSPasteboard(name: NSPasteboard.Name("check-photo-paste-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let png = phEncode(phImage(width: 30, height: 20), type: .png)

    board.clearContents()
    board.setData(png, forType: .png)
    #expect(MessagePhotoPasteboard.source(from: board) == .data(png))

    board.clearContents()
    board.setString("표에서 복사한 글", forType: .string)
    board.setData(png, forType: .png)
    #expect(MessagePhotoPasteboard.source(from: board) == nil, "글과 그림이 함께 실린 판을 사진으로 읽었다")

    board.clearContents()
    board.setString("그냥 글", forType: .string)
    #expect(MessagePhotoPasteboard.source(from: board) == nil)

    let file = CheckTestScratch.directory("photo-paste").appendingPathComponent("사진.png")
    try png.write(to: file)
    board.clearContents()
    board.writeObjects([file as NSURL])
    #expect(MessagePhotoPasteboard.source(from: board) == .file(file), "그림 파일을 붙이면 사진이다")

    let text = CheckTestScratch.directory("photo-paste").appendingPathComponent("메모.txt")
    try Data("글".utf8).write(to: text)
    board.clearContents()
    board.writeObjects([text as NSURL])
    #expect(MessagePhotoPasteboard.source(from: board) == nil, "그림이 아닌 파일을 사진으로 읽었다")
}

@MainActor
@Test
func 사진_신고는_기존_신고_문을_지나고_시트는_썸네일을_센다() throws {
    let photo = try #require(MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 1_600, height: 1_200))
    let photoOnly = PhFx.entry("r1", body: "", isMine: false, photo: photo)
    let target = try #require(MessageBubbleReportRule.target(for: photoOnly))
    #expect(target.messageID == "r1" && target.photo == photo)
    #expect(target.messageBody == nil, "사진만 보낸 줄에 빈 인용 판을 세운다")
    let captioned = try #require(MessageBubbleReportRule.target(for: PhFx.entry("r2", body: "이 사진 보세요", isMine: false, photo: photo)))
    #expect(captioned.messageBody == "이 사진 보세요" && captioned.photo == photo)
    #expect(MessageBubbleReportRule.target(for: PhFx.entry("r3", body: "", isMine: true, photo: photo)) == nil, "내 사진에 신고가 선다")
    // 시트 높이 추정이 썸네일을 센다(그리는 쪽과 같은 크기 규칙).
    let plain = BlockReportTarget(peerID: Fx.peerA, peerName: "민수", messageID: "r1")
    let thumb = MessagePhotoThumbnailLayout.reportSize(photo)
    #expect(thumb.width <= MessagePhotoThumbnailLayout.reportBox.width && thumb.height <= MessagePhotoThumbnailLayout.reportBox.height)
    #expect(BlockReportSheetLayout.reportBodyHeight(target: target, detail: "")
            == BlockReportSheetLayout.reportBodyHeight(target: plain, detail: "") + thumb.height + BlockReportSheetLayout.spacing)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_운영자_신고함은_목록을_받은_뒤_한_번에_묻고_처음_보는_id_만_다시_묻는다() async throws {
    let host = "photo-admin-\(UUID().uuidString.prefix(8))".lowercased()
    ReportAdminURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: ReportAdminURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: CheckTestScratch.defaults(host)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: Fx.me)
    store.ultraUnlimited = true
    let listPath = "/rest/v1/rpc/report_admin_list"
    let photosPath = "/rest/v1/rpc/report_admin_photo_paths"
    func row(_ id: String) -> String {
        #"{"id":"\#(id)","reporter_id":"u1","reporter_name":"신고자","reporter_avatar_url":null,"target_id":"u2","target_name":"대상","target_avatar_url":null,"reason":"inappropriate","detail":null,"message_body":"📷 사진","status":"open","admin_note":null,"created_at":"2026-09-19T16:07:03+00:00","handled_at":null}"#
    }

    // 함수가 없는 서버(스텁 기본값 404) — 사진 없이 그린다.
    ReportAdminURLProtocol.set(.init(body: "[" + row("r1") + "]"), host: host, path: listPath)
    await store.performLoadReportAdmin()
    await messageReadWait { ReportAdminURLProtocol.count(host: host, path: photosPath) == 1 }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(store.reportAdminPhotoPaths.isEmpty)

    // 사진이 있는 서버 — 새 id 만 묻는다(r1 은 이미 물었다).
    ReportAdminURLProtocol.set(.init(body: Fx.json([["report_id": "r2", "photo_path": PhFx.peerPhotoPath]])), host: host, path: photosPath)
    ReportAdminURLProtocol.set(.init(body: "[" + row("r1") + "," + row("r2") + "]"), host: host, path: listPath)
    await store.performLoadReportAdmin()
    await messageReadWait { !store.reportAdminPhotoPaths.isEmpty }
    #expect(ReportAdminURLProtocol.count(host: host, path: photosPath) == 2)
    let sent = try #require(ReportAdminURLProtocol.sentBodies(host: host, path: photosPath).last)
    let json = try #require(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any])
    #expect(json["p_ids"] as? [String] == ["r2"], "이미 물어본 id 를 다시 물었다: \(sent)")
    #expect(store.reportAdminPhotoPaths == ["r2": PhFx.peerPhotoPath])

    // 같은 목록을 다시 받으면 묻지 않는다.
    await store.performLoadReportAdmin()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(ReportAdminURLProtocol.count(host: host, path: photosPath) == 2, "목록을 다시 받을 때마다 사진 경로를 물었다")

    // 행 높이 추정이 사진 조각을 센다(작게 < 크게).
    let item = try #require(store.reportAdminList.first { $0.id == "r2" })
    let none = ReportAdminLayout.rowHeight(item, expanded: false)
    let small = ReportAdminLayout.rowHeight(item, expanded: false, photo: false)
    let large = ReportAdminLayout.rowHeight(item, expanded: false, photo: true)
    #expect(small == none + 6 + ReportAdminPhotoBlock.height(enlarged: false) && large > small)
    store.toggleReportAdminPhoto("r2")
    #expect(store.reportAdminPhotoEnlargedID == "r2")
    store.toggleReportAdminPhoto("r2")
    #expect(store.reportAdminPhotoEnlargedID == nil)

    // 운영자가 아니면 묻지 않는다.
    store.ultraUnlimited = false
    store.reportAdminPhotoChecked = []
    store.loadReportAdminPhotoPaths(for: store.reportAdminList, generation: store.sessionGeneration)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(ReportAdminURLProtocol.count(host: host, path: photosPath) == 2)
}

// MARK: - ③ 인코더

@Test
func 사진_인코더는_긴_변을_1600으로_줄이고_목표_크기_안에_든다() throws {
    let wide = phEncode(phImage(width: 3_000, height: 2_000), type: .png)
    let (encoded, box) = try #require(MessagePhotoEncoder.encode(data: wide))
    #expect(encoded.pixelWidth == 1_600 && encoded.pixelHeight == 1_067, "\(encoded.pixelWidth)×\(encoded.pixelHeight)")
    #expect(encoded.data.count <= MessagePhotoEncoder.targetBytes)
    #expect(box.image.width == encoded.pixelWidth && box.image.height == encoded.pixelHeight)
    #expect(phPixelSize(encoded.data).map { $0 == (1_600, 1_067) } == true)
    // 작은 그림은 키우지 않는다.
    let small = try #require(MessagePhotoEncoder.encode(data: phEncode(phImage(width: 300, height: 200), type: .png)))
    #expect(small.0.pixelWidth == 300 && small.0.pixelHeight == 200)
    // 잡음뿐인 큰 그림 — 품질 계단 · 크기 계단을 내려 목표 안에 든다.
    let noisy = try #require(MessagePhotoEncoder.encode(data: phEncode(phImage(width: 2_400, height: 2_400, noise: true), type: .png)))
    #expect(noisy.0.data.count <= MessagePhotoEncoder.targetBytes, "\(noisy.0.data.count) 바이트")
    #expect(max(noisy.0.pixelWidth, noisy.0.pixelHeight) <= MessagePhotoEncoder.maxPixelSide)
    // 그림이 아닌 바이트.
    #expect(MessagePhotoEncoder.encode(data: Data("사진이 아니다".utf8)) == nil)
}

@Test
func 사진_인코더는_EXIF_방향을_적용하고_투명을_흰_바탕에_깔고_메타데이터를_안_싣는다() throws {
    // 400×200 을 "90도 돌려 보라"(6)로 저장한 사진 — 결과는 세로 200×400 이어야 한다.
    let gps: [CFString: Any] = [
        kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 127.0, kCGImagePropertyGPSLongitudeRef: "E"
    ]
    let source = phEncode(phImage(width: 400, height: 200), type: .jpeg, properties: [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: gps,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "테스트카메라", kCGImagePropertyTIFFModel: "모델"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"]
    ])
    // 전제: 원본에는 GPS 가 실려 있다.
    let inProps = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(source as CFData, nil)!, 0, nil) as? [CFString: Any]
    #expect(inProps?[kCGImagePropertyGPSDictionary] != nil, "전제: 원본에 GPS 가 없다 — 아래 단언이 공허하다")

    let (rotated, _) = try #require(MessagePhotoEncoder.encode(data: source))
    #expect(rotated.pixelWidth == 200 && rotated.pixelHeight == 400, "EXIF 방향이 안 먹었다: \(rotated.pixelWidth)×\(rotated.pixelHeight)")
    let outSource = try #require(CGImageSourceCreateWithData(rotated.data as CFData, nil))
    let outProps = CGImageSourceCopyPropertiesAtIndex(outSource, 0, nil) as? [CFString: Any] ?? [:]
    #expect(outProps[kCGImagePropertyGPSDictionary] == nil, "위치(GPS)가 그대로 올라간다")
    let tiff = outProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    #expect(tiff?[kCGImagePropertyTIFFMake] == nil && tiff?[kCGImagePropertyTIFFModel] == nil, "카메라 정보가 그대로 올라간다")
    let exif = outProps[kCGImagePropertyExifDictionary] as? [CFString: Any]
    #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil, "찍은 시각이 그대로 올라간다")
    let orientation = (outProps[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    #expect(orientation == 1, "방향을 적용하고도 방향 꼬리표를 남겼다(두 번 돈다)")

    // 투명 PNG — 투명 자리는 흰색, 가운데는 그린 색.
    let transparent = phEncode(phImage(width: 90, height: 90, alpha: true), type: .png)
    let (flat, _) = try #require(MessagePhotoEncoder.encode(data: transparent))
    let corner = try #require(phPixel(flat.data, x: 2, y: 2))
    #expect(corner.0 > 245 && corner.1 > 245 && corner.2 > 245, "투명 자리가 흰색이 아니다: \(corner)")
    let center = try #require(phPixel(flat.data, x: 45, y: 45))
    #expect(center.0 > 180 && center.1 < 100, "가운데 그림이 사라졌다: \(center)")
}

@Test
func 사진_아바타_축소는_같은_몸통을_쓴다() throws {
    // 아바타(256px)는 코어 몸통 `ImageDownscale` 을 그대로 쓴다 — 결과가 몸통을 직접 부른 것과 바이트까지 같다.
    let png = phEncode(phImage(width: 1_000, height: 600), type: .png)
    let avatar = try #require(CheckAvatarView.downscaledJPEGData(from: png))
    let core = try #require(ImageDownscale.downscaledJPEG(
        from: CGImageSourceCreateWithData(png as CFData, nil)!, maxPixelSize: 256, quality: 0.85
    ))
    #expect(avatar == core)
    #expect(phPixelSize(avatar).map { $0 == (256, 154) } == true)
}

// MARK: - ④ 화면

/// 대화 한 판(클립 갈래 · SwiftUI 글자) — 그림은 미리 캐시에 넣는다.
@MainActor
private func phConversation(_ entries: [MessageHistoryEntry], context: MessagePhotoBubbleContext?, height: CGFloat) -> some View {
    MessageConversationView(
        items: MessageThreadBuilder.timeline(entries, now: Fx.now),
        peerUserID: Fx.peerA,
        lastMessageID: entries.last?.id,
        clipsInsteadOfScrolling: true,
        rendersPlainText: true,
        photoContext: context
    )
    .frame(width: MessagePanelLayout.contentWidth, height: height)
    .background(Color.black)
}

/// 그려진 잉크의 세로 범위(pt) — 같은 크기의 빈 판과 다른 픽셀의 위아래 끝(2배 화면).
private func phInkHeight(_ bitmap: NSBitmapImageRep, blank: NSBitmapImageRep) -> CGFloat? {
    guard bitmap.pixelsWide == blank.pixelsWide, bitmap.pixelsHigh == blank.pixelsHigh,
          bitmap.bytesPerRow == blank.bytesPerRow, bitmap.samplesPerPixel == blank.samplesPerPixel,
          let a = bitmap.bitmapData, let b = blank.bitmapData else { return nil }
    let rowBytes = bitmap.bytesPerRow
    let step = bitmap.bitsPerPixel / 8
    var minY = Int.max, maxY = Int.min
    for y in 0..<bitmap.pixelsHigh {
        var x = 0
        while x < bitmap.pixelsWide {
            let offset = y * rowBytes + x * step
            let delta = abs(Int(a[offset]) - Int(b[offset])) + abs(Int(a[offset + 1]) - Int(b[offset + 1]))
                + abs(Int(a[offset + 2]) - Int(b[offset + 2]))
            if delta > 20 {
                minY = min(minY, y)
                maxY = max(maxY, y)
                break
            }
            x += 1
        }
    }
    guard minY <= maxY else { return nil }
    return CGFloat(maxY - minY + 1) / 2
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_틀_높이_추정은_그려진_사진_말풍선보다_작지_않다() throws {
    let (store, _) = makeMessageReadStore("photo-estimate")
    let cases: [(Int, Int, Bool, String)] = [
        (1_600, 1_200, true, ""), (1_600, 1_200, false, ""), (900, 1_600, false, "주말에 찍은 사진이에요 바다가 예뻤어요"),
        (4_000, 100, true, "긴 사진"), (120, 90, false, "")
    ]
    for (w, h, mine, caption) in cases {
        let photo = try #require(MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: w, height: h))
        phSeedImage(store, path: photo.path, width: w, height: h)
        let entry = PhFx.entry("e1", body: caption, isMine: mine, photo: photo, at: Fx.now.addingTimeInterval(-60))
        let estimate = MessagePanelLayout.conversationContentHeight(MessageThreadBuilder.timeline([entry], now: Fx.now))
        let drawn = try #require(CheckRenderSettle.bitmap(phConversation([entry], context: store.messagePhotoContext, height: 460), scale: 2))
        let blank = try #require(CheckRenderSettle.bitmap(phConversation([], context: nil, height: 460), scale: 2))
        let ink = try #require(phInkHeight(drawn, blank: blank), "\(w)×\(h) 사진이 안 그려졌다")
        #expect(estimate >= ink, "추정 \(estimate)pt < 그려진 \(ink)pt — \(w)×\(h) mine=\(mine) caption=\(caption.count)")
        // 사진 높이는 틀림없이 그 안에 있다(공허하지 않게 — 날짜 줄 + 사진).
        #expect(ink >= MessagePhotoLayout.bubbleSize(for: photo, isMine: mine).height, "사진이 그 크기로 안 그려졌다")
    }
}

@Test
func 사진_말풍선은_따로_든_구조체이고_행과_추정이_사진을_먼저_고른다_소스계약() throws {
    let view = phSource("CheckMessageView.swift")
    // 행: 사진 → 이모티콘 → 글 순서.
    let bubble = try #require(phRegion(view, from: "private var bubble: some View {", to: "private func photoBubble("))
    let photoBranch = try #require(bubble.range(of: "if let photo = entry.photo"))
    let stickerBranch = try #require(bubble.range(of: "AingStickerArt.drawable(for: entry.body)"))
    #expect(photoBranch.lowerBound < stickerBranch.lowerBound, "말풍선이 사진보다 이모티콘을 먼저 고른다")
    // 추정: 같은 순서 · 같은 크기 규칙.
    let estimate = try #require(phRegion(view, from: "static func conversationContentHeight(", to: "\n    }"))
    let photoEstimate = try #require(estimate.range(of: "MessagePhotoLayout.bubbleSize(for: photo, isMine: entry.isMine)"))
    let stickerEstimate = try #require(estimate.range(of: "AingStickerArt.drawable(for: entry.body)"))
    #expect(photoEstimate.lowerBound < stickerEstimate.lowerBound)
    // 사진 메뉴는 말풍선 행 밖의 구조체가 든다(행의 메뉴 하나 계약).
    let photoViews = phSource("CheckMessagePhotoViews.swift")
    #expect(photoViews.contains("struct MessagePhotoBubble: View"))
    #expect(photoViews.contains("BlockReportText.reportMessageAction"), "받은 사진에 [신고]가 없다")
    // 화면을 찍는 코드는 없다(처리방침 — 화면 기록 권한을 안 묻는다).
    let store = phSource("WorkTimerStoreMessagePhotos.swift")
    for source in [view, photoViews, store] {
        #expect(!source.contains("CGWindowListCreateImage") && !source.contains("SCScreenshotManager") && !source.contains("screencapture"))
        #expect(!source.contains("print(") && !source.contains("Logger("), "사진 · 경로를 로그로 흘린다")
    }
    // 사진 칸 조회는 열기 문과 머리 변화에서만 — 팝오버 열기 · 폴링 자리에 없다.
    let messages = v0331StripComments(try CheckCoreSourceLayout.joinedSplitSource("WorkTimerStoreMessages.swift"))
    let open = try #require(phRegion(messages, from: "func openMessagePanel(peer:", to: "\n    }\n"))
    #expect(open.contains("armMessagePhotoMeta(for: peer)"))
    let menuOpen = try #require(phRegion(messages, from: "func refreshMessageActivityOnMenuOpen() {", to: "\n    }\n"))
    #expect(!menuOpen.contains("MessagePhoto"), "팝오버 열기가 사진 칸을 묻는다")
    // 운영자 신고 행 모양(V0334 계약 열과 같은 칸)은 그대로다 — 사진 경로는 따로 든 표다.
    #expect(!phSource("SupabaseWorkServiceReportAdmin.swift").contains("photo"))
}

/// 주석을 걷은 소스(V0331 공용 도우미 — 코어로 간 파일도 찾는다).
private func phSource(_ name: String) -> String {
    (try? v0331Source(name)) ?? ""
}

private func phRegion(_ text: String, from: String, to: String) -> String? {
    guard let start = text.range(of: from),
          let end = text.range(of: to, range: start.upperBound..<text.endIndex) else { return nil }
    return String(text[start.lowerBound..<end.lowerBound])
}

/// 보조기술이 읽는 라벨(V0362 의 프로브와 같은 수법 — 창을 띄우지 않는다).
@MainActor
private func phAccessibilityLabels(_ view: some View, width: CGFloat, height: CGFloat) -> [String] {
    let key = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    let app = NSApplication.shared
    app.accessibilitySetValue(true, forAttribute: key)
    defer { app.accessibilitySetValue(false, forAttribute: key) }
    let host = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    var labels: [String] = []
    func walk(_ node: Any, depth: Int) {
        guard depth < 12, let object = node as? NSObject else { return }
        let labelSelector = NSSelectorFromString("accessibilityLabel")
        if object.responds(to: labelSelector), let text = object.perform(labelSelector)?.takeUnretainedValue() as? String, !text.isEmpty {
            labels.append(text)
        }
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        if object.responds(to: childrenSelector), let children = object.perform(childrenSelector)?.takeUnretainedValue() as? [Any] {
            for child in children { walk(child, depth: depth + 1) }
        }
    }
    walk(host, depth: 0)
    withExtendedLifetime(host) {}
    return labels
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_미리_보기_덮개는_밑의_대화를_보이스오버에서_내린다() throws {
    func labels(withDraft: Bool) throws -> [String] {
        let (store, _) = makeMessageReadStore("photo-ax-\(withDraft)")
        store.openMessagePanel(peer: Fx.peerA)
        store.messageHistoryFailed = true   // 대화 자리에 [다시 시도] 가 선다(= 덮이는 쪽의 표식)
        if withDraft { store.messagePhotoDraft = try phDraft() }
        return phAccessibilityLabels(
            CheckMessageView(store: store, rendersPlainTextEditor: true, clipsOverflowInsteadOfScroll: true, now: Fx.now, onBack: {}),
            width: 316, height: 700
        )
    }
    let closed = try labels(withDraft: false)
    #expect(closed.contains("다시 시도"), "대조군: 접힌 화면에서 대화 자리가 안 읽힌다 — 프로브가 공허하다: \(closed)")
    #expect(closed.contains(MessagePhotoText.buttonLabel), "작성기에 [사진] 버튼이 안 읽힌다: \(closed)")
    let open = try labels(withDraft: true)
    #expect(!open.contains("다시 시도"), "가려진 대화가 보이스오버에 남았다: \(open)")
    #expect(open.contains(MessagePhotoText.previewCancel), "미리 보기 덮개의 [취소]가 안 읽힌다: \(open)")
}

// MARK: - ④ 스냅숏 (FEATURE_SHOTS_DIR)

private func phSaveShot(_ bitmap: NSBitmapImageRep, name: String) {
    if let dir = ProcessInfo.processInfo.environment["FEATURE_SHOTS_DIR"], !dir.isEmpty {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: url.appendingPathComponent(name))
        }
    }
    MessagePanelSnapshots.save(bitmap, name: name)
}

@MainActor
private func phMenuBitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    // ★ ImageRenderer 는 ScrollView 안쪽 · TextEditor 를 못 그린다 — 렌더 시험 전용 두 스위치(앱은 언제나 false).
    let view = CheckMenuView(store: store, previewClipsOverflowList: true, previewPlainTextEditors: true)
    return try #require(CheckRenderSettle.bitmap(view, scale: 2), "렌더 실패")
}

private func phLooksDifferent(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Bool {
    guard let a = lhs.cgImage, let b = rhs.cgImage, let diff = CheckRenderDiff(a, b) else { return false }
    return diff.looksDifferent
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 사진_화면_스냅숏() async throws {
    // ★ 기다림(await)은 **맨 앞에만** 둔다 — 화면 상태를 세운 뒤에 쉬면 그 사이 스토어의 배경 작업(명부 · 팀)이 돌아 팀 화면이 바뀐다.
    let item = try #require(try await phAdminItem())
    let (store, _) = makeMessageReadStore("photo-shots")
    store.isMenuPresented = true
    store.displayNow = Date()
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    let now = Date()
    let receivedPhoto = try #require(MessagePhotoAttachment(path: PhFx.peerPhotoPath, width: 1_600, height: 1_200))
    let sentPhoto = try #require(MessagePhotoAttachment(path: PhFx.minePhotoPath, width: 1_200, height: 1_600))
    func head(_ id: String, _ body: String, secondsAgo: TimeInterval, mine: Bool) -> MessageHistoryEntry {
        MessageHistoryEntry(
            id: id, peerUserID: Fx.peerA, peerName: "민수", peerAvatarURL: nil, body: body,
            createdAt: now.addingTimeInterval(-secondsAgo), isMine: mine, readByPeer: mine ? true : nil, isUnread: mine ? nil : false
        )
    }
    store.messageHistory = [
        head("h1", "주말 잘 보냈어요?", secondsAgo: 2_400, mine: false),
        head("h2", "네 바다 다녀왔어요", secondsAgo: 2_000, mine: true)
    ]
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["h1": 0, "h2": 1])
    store.messageReadReceiptsAvailable = true
    store.messageHistoryLoaded = true
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = Fx.peerA

    // ① 작성기 [사진] 버튼(이모티콘 옆 · 같은 줄).
    let composer = try phMenuBitmap(store)
    phSaveShot(composer, name: "photo-1-composer-button.png")
    #expect(Double(composer.pixelsHigh) / 2 <= 700, "팝오버 높이 상한을 넘었다")
    store.messagePhotoSendClosed = true
    let noButton = try phMenuBitmap(store)
    #expect(phLooksDifferent(composer, noButton), "[사진] 버튼이 그려지지 않았다")
    #expect(composer.pixelsHigh == noButton.pixelsHigh, "[사진] 버튼이 작성기 높이를 바꿨다")
    store.messagePhotoSendClosed = false

    // ② 미리 보기 덮개(입력칸 글이 설명으로 간다는 한 줄).
    store.messageDraft = "바다 사진이에요"
    store.messagePhotoDraft = try phDraft(width: 1_600, height: 1_000)
    let preview = try phMenuBitmap(store)
    phSaveShot(preview, name: "photo-2-preview.png")
    #expect(phLooksDifferent(preview, composer))
    #expect(Double(preview.pixelsHigh) / 2 <= 700)
    store.messagePhotoDraft = nil
    store.messageDraft = ""

    // ③ 보낸 사진(사진만 — 글 '📷 사진'은 그리지 않는다).
    store.messageHistory.append(head("h3", MessageNoticeText.photoFallbackBody, secondsAgo: 1_800, mine: true))
    store.messagePhotoMeta[Fx.peerA] = ["h3": MessagePhotoMeta(attachment: sentPhoto, caption: nil)]
    phSeedImage(store, path: sentPhoto.path, width: 600, height: 800)
    let sent = try phMenuBitmap(store)
    phSaveShot(sent, name: "photo-3-sent-photo-only.png")
    #expect(phLooksDifferent(sent, composer))

    // ④ 받은 사진 + 설명.
    store.messageHistory.append(head("h4", "이건 제 사진이에요", secondsAgo: 600, mine: false))
    store.messagePhotoMeta[Fx.peerA]?["h4"] = MessagePhotoMeta(attachment: receivedPhoto, caption: "이건 제 사진이에요")
    phSeedImage(store, path: receivedPhoto.path, width: 800, height: 600)
    let received = try phMenuBitmap(store)
    phSaveShot(received, name: "photo-4-received-caption.png")
    #expect(phLooksDifferent(received, sent))
    #expect(Double(received.pixelsHigh) / 2 <= 700)

    // ⑤ 크게 보기([저장…] · [닫기]).
    store.messagePhotoViewer = MessagePhotoViewerItem(photo: receivedPhoto, messageID: "h4", peerID: Fx.peerA, isMine: false)
    let viewer = try phMenuBitmap(store)
    phSaveShot(viewer, name: "photo-5-viewer.png")
    #expect(phLooksDifferent(viewer, received))
    #expect(Double(viewer.pixelsHigh) / 2 <= 700)
    store.closeMessagePhotoViewer()

    // ⑥ 신고 시트(글 인용 대신 작은 사진).
    let target = try #require(MessageBubbleReportRule.target(for: PhFx.entry("h4", body: "", isMine: false, photo: receivedPhoto)))
    store.openReport(target, surface: .message)
    let sheet = try phMenuBitmap(store)
    phSaveShot(sheet, name: "photo-6-report-sheet.png")
    #expect(phLooksDifferent(sheet, received))
    #expect(Double(sheet.pixelsHigh) / 2 <= 700)
    store.dismissBlockReportSheet(on: .message)

    // ⑦ 운영자 신고함 한 줄(신고된 사진 썸네일).
    let row = ReportAdminRow(
        report: item, now: now, isExpanded: false, note: .constant(""), onToggle: {}, onStatus: { _ in },
        photoPath: receivedPhoto.path, photoEnlarged: false, photoContext: store.messagePhotoContext
    )
    .frame(width: MessagePanelLayout.contentWidth)
    .padding(12)
    .background(CheckTheme.background)
    let adminRow = try #require(CheckRenderSettle.bitmap(row, scale: 2))
    phSaveShot(adminRow, name: "photo-7-admin-row.png")
    let estimate = ReportAdminLayout.rowHeight(item, expanded: false, photo: false)
    #expect(estimate + 24 + 1 >= CGFloat(adminRow.pixelsHigh) / 2, "행 높이 추정(\(estimate))이 그려진 행보다 작다")

    // ⑧ 문이 닫혔다 — 안내 한 줄 · [사진] 버튼 없음.
    store.messagePhotoSendClosed = true
    store.messageNotice = MessagePhotoText.doorClosedNotice
    let closed = try phMenuBitmap(store)
    phSaveShot(closed, name: "photo-8-door-closed.png")
    #expect(phLooksDifferent(closed, received))
    #expect(Double(closed.pixelsHigh) / 2 <= 700)
    #expect(store.isMessagePanelVisible && store.currentTeamID != nil, "전제: 대화 화면 그대로다(배경 작업이 화면을 바꾸지 않았다)")
}

/// 운영자 신고 한 줄(서비스의 행 → 항목 변환을 지난다 — 값은 합성).
private func phAdminItem() async throws -> ContentReportAdminItem? {
    let json = #"[{"id":"r1","reporter_id":"u1","reporter_name":"신고자","reporter_avatar_url":null,"target_id":"u2","target_name":"민수","target_avatar_url":null,"reason":"inappropriate","detail":"보기 불편한 사진이에요","message_body":"📷 사진","status":"open","admin_note":null,"created_at":"2026-09-19T16:07:03+00:00","handled_at":null}]"#
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([ContentReportAdminRow].self, from: Data(json.utf8))
    let service = SupabaseWorkService(projectURL: URL(string: "http://photo-admin-item")!, anonKey: "anon-test-key")
    guard let row = rows.first else { return nil }
    return await service.item(from: row)
}

