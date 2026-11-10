import Foundation
import CoreGraphics

// MARK: - 1:1 메시지 사진 (2026-11-11 — 맥 0.3.86 · build 139)
//
// 대표 결정(#d_x5kYyOPOeLlH): "사진 보내기". 서버(서버 안정화 11-11 최종 목록 §2 · 초안 20261114101000 §1~§6):
//  · 버킷 `message-photos`(비공개 · 5MB). 경로는 **정확히** `<내 uid 소문자>/<새 uuid 소문자>.jpg` — 덮어쓰기 정책이 없다(upsert 끔).
//  · `send_photo_message(p_to, p_path, p_width, p_height, p_caption, p_client_message_id)` — 응답은 send_message 와 같은 jsonb
//    (+ ok 면 photo_path · photo_width · photo_height). 새 status 셋: unsupported_client(+door_open) · invalid_photo · photo_missing.
//  · 사진만 보낸 줄의 본문은 '📷 사진'(`MessageNoticeText.photoFallbackBody`) — 옛 앱 · 푸시 · 메뉴 줄 · 신고 본문은 그 글을 본다.
//  · 24시간 머리(`message_history_with_pokes` 등)에는 사진 칸이 **없다**. 사진은 `message_page` 행(caption · photo_*)에만 있다.
//  · 보기: 서명 URL(비공개 버킷 도우미 `downloadPrivateObjectViaSignedURL`). 보낸 사람 · 받은 사람 · 신고된 사진의 운영자만 열 수 있다.
//  · 신고: `report_content` 는 그대로(서버가 사진 경로를 스스로 남긴다). 운영자는 `report_admin_photo_paths(p_ids)` 로 경로를 받는다.
//    **운영자 사진 지우기 RPC 는 서버 목록에 없다** — 만들지 않는다(운영자는 보고 상태만 바꾼다).
//
// **전선 이름·키·행 모양은 전부 이 파일 한 곳**에 있다(버킷 · 두 RPC · 요청 여섯 키 · 응답 · 행).
//
// ── 이 파일이 지키는 것 ──
//  ① 요청은 **여섯 키를 언제나** 싣는다(nil → JSON null) — PostgREST 는 본문의 키 집합으로 함수를 고른다(V0313 의 교훈).
//  ② 디코더 함정: 서비스 디코더는 `.convertFromSnakeCase` 다. 응답 모델의 칸 이름은 **카멜**이고 스네이크 원값을 주지 않는다.
//  ③ 새 status 셋은 **따로 든 열거형**(`MessagePhotoSendOutcome`)이 맡는다 — 공용 `MessageSendOutcome` 에 케이스를 더하면
//     폰 화면의 망라 switch 가 깨진다. 공용 어휘(ok · blackout · flood …)는 공용 매핑 그대로 지난다.
//  ④ 경로는 서버 정규식과 **같은 모양**만 받는다(소문자 uuid 둘 · 확장자 넷). 이상한 값이 서명 URL 을 엉뚱한 곳으로 돌리지 못하게.
//  ⑤ 사진 · 경로 · 글은 로그로 흘리지 않는다(`print`/`Logger` 금지).

// MARK: - 상수 · 문구

/// 사진 기능의 이름 · 수 · 문구. 숫자가 들어가는 문구는 상수에서 만든다.
package enum MessagePhotoText {
    /// 비공개 버킷 이름(서버 §2).
    package static let bucket = "message-photos"
    /// 서명 URL 유효 시간(초, 계약 v2).
    package static let signedURLSeconds = 3_600
    /// 열린 대화의 사진 칸을 받을 때 `message_page` 한 번이 받는 줄 수(머리 24시간에는 사진 칸이 없다 — 계약).
    package static let metaPageLimit = 30
    /// 서버 크기 범위(`photo_width` · `photo_height` 1~20000).
    package static let sideRange = 1...20_000
    /// 서버가 받는 확장자(경로 정규식 `\.(jpg|png|heic|webp)$`). 맥은 언제나 jpg 로 올린다.
    package static let serverExtensions: Set<String> = ["jpg", "png", "heic", "webp"]
    package static let uploadExtension = "jpg"

    // 화면 문구(짧고 쉬운 말).
    package static let buttonHelp = "사진 보내기"
    /// 보이스오버 라벨 — "보내기" 를 넣지 않는다(작성기 [보내기] 와 같은 낱말이면 훑기가 둘을 헷갈린다).
    package static let buttonLabel = "사진 고르기"
    package static let pickerMessage = "보낼 사진을 고르세요"
    package static let pickerPrompt = "고르기"
    package static let previewTitle = "이 사진을 보낼까요?"
    package static let previewSend = "보내기"
    package static let previewCancel = "취소"
    /// 입력칸에 글이 있으면 그 글이 사진 아래 설명으로 같이 간다.
    package static let captionNote = "입력칸의 글도 함께 보내요"
    package static let preparing = "사진을 준비하는 중…"
    package static let sending = "보내는 중…"
    package static let loadingLabel = "사진을 불러오는 중"
    package static let unavailable = "사진을 볼 수 없어요"
    package static let viewerClose = "닫기"
    package static let viewerSave = "저장…"
    package static let viewerSaveFailed = "사진을 저장하지 못했어요"
    package static let openLabel = "사진 크게 보기"
    package static let photoAccessibility = "사진"
    package static let saveDefaultName = "사진.jpg"
    package static let reportPhotoTitle = "신고할 사진"
    package static let adminPhotoTitle = "신고된 사진"
    package static let adminPhotoHint = "눌러서 크게 보기"
    package static let dropHint = "여기에 놓으면 사진을 보내요"

    /// 문이 닫혀 있다(서버 `unsupported_client` · door_open 거짓) — 새 판이 퍼지면 서버가 연다.
    package static let doorClosedNotice = "사진 보내기는 새 버전이 퍼진 뒤 열려요"
    /// 문은 열렸는데 이 기기를 아직 새 판으로 모른다(door_open 참) — 잠시 뒤 다시.
    package static let doorOpenNotice = "사진 보내기를 준비하는 중이에요 · 잠시 후 다시 시도해 주세요"
    /// 올리기 실패(서버 `photo_missing` · 올리기 거절).
    package static let uploadFailedNotice = "사진을 올리지 못했어요"
    /// 서버가 그 사진을 받지 않는다(`invalid_photo`). 새 이름으로 다시 올리면 된다.
    package static let invalidPhotoNotice = "사진을 보내지 못했어요 · 다시 보내 주세요"
    /// 고른 파일을 그림으로 못 읽었다.
    package static let unreadableNotice = "사진을 읽지 못했어요"
    /// 줄여도 버킷 상한보다 크다(413).
    package static let tooLargeNotice = "사진이 너무 커요"
}

// MARK: - 사진 한 장(전선 위 모양)

/// 메시지에 붙은 사진 한 장 — 경로 · 픽셀 크기. 서버가 준 값이 모양 규칙(④)을 지날 때만 만들어진다.
package struct MessagePhotoAttachment: Equatable, Hashable, Sendable {
    package let path: String
    package let width: Int
    package let height: Int

    /// 서버 값 → 사진. 경로가 서버 모양이 아니거나 크기가 범위 밖이면 nil(그 줄은 글로 그린다).
    package init?(path: String?, width: Int?, height: Int?) {
        guard let path, MessagePhotoPath.isServerShaped(path),
              let width, let height,
              MessagePhotoText.sideRange.contains(width), MessagePhotoText.sideRange.contains(height)
        else { return nil }
        self.path = path
        self.width = width
        self.height = height
    }
}

/// 경로 규칙(순수). 버킷 도우미(`PrivateStorage`)가 모양 일반(소문자 · 안전 글자)을, 이 파일이 **이 버킷의** 모양을 안다.
package enum MessagePhotoPath {
    /// 새 사진 이름 — 소문자 uuid. 같은 값이 파일 이름과 `p_client_message_id` 를 **겸한다**(재시도가 같은 줄로 접힌다).
    package static func newID() -> String { UUID().uuidString.lowercased() }

    /// `<내 uid 소문자>/<id 소문자>.jpg`. 서버 정책은 첫 폴더를 `auth.uid()::text` 와 글자 그대로 견준다.
    package static func uploadPath(owner: String, id: String) -> String {
        PrivateStorage.objectPath(owner: owner, name: id, ext: MessagePhotoText.uploadExtension)
    }

    /// 서버 정규식 `^<uuid>/<uuid>\.(jpg|png|heic|webp)$` 와 같은 판정(정규식 없이 — 소문자 16진 8-4-4-4-12).
    package static func isServerShaped(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, isLowercaseUUID(parts[0]) else { return false }
        let file = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard file.count == 2, isLowercaseUUID(file[0]), MessagePhotoText.serverExtensions.contains(String(file[1])) else {
            return false
        }
        return PrivateStorage.isSafeObjectPath(path)
    }

    /// 소문자 uuid 표기(8-4-4-4-12)인가.
    package static func isLowercaseUUID(_ text: Substring) -> Bool {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        let hex = Set("0123456789abcdef")
        return groups.allSatisfy { $0.allSatisfy { hex.contains($0) } }
    }
}

// MARK: - 크기 규칙(말풍선 · 틀 높이 추정이 같은 하나를 쓴다)

/// 사진 말풍선의 크기 규칙(순수). **말풍선과 틀 높이 추정(`MessagePanelLayout.conversationContentHeight`)이 같은 함수를 부른다** —
/// 둘이 갈리면 빈 회색 판이 생기거나 사진이 스크롤 안에 갇힌다.
package enum MessagePhotoLayout {
    /// 한 변 상한(pt) — 계약 "200×200 안".
    package static let maxSide: CGFloat = 200
    /// 받은 말풍선의 폭 상한(pt). 292pt 패널에서 받은 줄은 아바타 20 · 시각 ≈27 · 간격 4×3 · 반대쪽 여백 40 · 안쪽 여백 16 을 쓰고
    /// 남는 폭이 177pt 다 — 200 을 주면 줄이 패널 밖으로 밀린다.
    package static let receivedMaxWidth: CGFloat = 170
    /// 한 변 하한(pt). 아주 가늘고 긴 사진도 누를 수 있는 과녁으로 남게(넘치는 쪽은 잘라 그린다).
    package static let minSide: CGFloat = 60
    /// 사진과 설명 글 사이 간격(pt).
    package static let captionSpacing: CGFloat = 4
    /// 말풍선 모서리(pt).
    package static let corner: CGFloat = 10

    /// 픽셀 크기 → 말풍선 크기(pt). 비율을 지키며 상자(`maxWidth`×`maxHeight`)에 맞추고(1pt = 1px 보다 키우지 않는다),
    /// 각 변을 하한까지 올린다(그때는 비율이 바뀌어 그림을 채워 자른다). 정수 pt 로 반올림한다.
    package static func bubbleSize(
        width: Int, height: Int, maxWidth: CGFloat = maxSide, maxHeight: CGFloat = maxSide
    ) -> CGSize {
        let w = CGFloat(max(1, width))
        let h = CGFloat(max(1, height))
        let scale = min(1, maxWidth / w, maxHeight / h)
        let fittedWidth = min(maxWidth, max(minSide, (w * scale).rounded()))
        let fittedHeight = min(maxHeight, max(minSide, (h * scale).rounded()))
        return CGSize(width: fittedWidth, height: fittedHeight)
    }

    /// 대화 줄의 말풍선 크기 — 내 말은 200 폭, 받은 말은 `receivedMaxWidth` 폭까지.
    package static func bubbleSize(for photo: MessagePhotoAttachment, isMine: Bool) -> CGSize {
        bubbleSize(width: photo.width, height: photo.height, maxWidth: isMine ? maxSide : receivedMaxWidth)
    }

    /// 비율만 지켜 상자에 맞춘다(크게 보기 · 미리 보기 · 신고 썸네일). 하한 없음 · 키우기 허용.
    package static func fitted(width: Int, height: Int, in box: CGSize) -> CGSize {
        let w = CGFloat(max(1, width))
        let h = CGFloat(max(1, height))
        let scale = min(box.width / w, box.height / h)
        return CGSize(width: max(1, (w * scale).rounded()), height: max(1, (h * scale).rounded()))
    }
}

// MARK: - 표시용 한 건에 사진 붙이기

extension MessageHistoryEntry {
    /// 사진 칸을 붙인 사본. 글은 **설명(caption)** 이다 — 사진만 보낸 줄은 빈 글(사진만 그린다). 나머지 칸은 그대로다.
    /// 24시간 머리 줄(사진 칸이 없다)에 `message_page` 에서 배운 사진을 얹을 때 쓴다(맥 스토어 `messagePhotoDisplayed`).
    package func withPhoto(_ photo: MessagePhotoAttachment, caption: String?) -> MessageHistoryEntry {
        replacingBody(
            caption.flatMap { MessageBody.hasVisibleContent($0) ? MessageBody.sanitized($0) : nil } ?? "",
            photo: photo
        )
    }

    /// 사진 줄의 설명(보이는 글이 있을 때만). 사진이 없는 줄은 nil.
    package var photoCaption: String? {
        guard photo != nil, MessageBody.hasVisibleContent(body) else { return nil }
        return body
    }
}

// MARK: - 보내기 요청 · 응답

/// `send_photo_message` 요청. **여섯 키를 언제나 싣는다**(① — 설명이 없으면 `p_caption` 을 JSON null 로).
package struct SendPhotoMessageRequest: Encodable, Equatable, Sendable {
    package let pTo: String
    package let pPath: String
    package let pWidth: Int
    package let pHeight: Int
    package let pCaption: String?
    package let pClientMessageId: String

    package init(to: String, path: String, width: Int, height: Int, caption: String?, clientMessageID: String) {
        pTo = to
        pPath = path
        pWidth = width
        pHeight = height
        pCaption = caption
        pClientMessageId = clientMessageID
    }

    /// 키를 이미 스네이크로 적는다(인코더의 스네이크 변환은 대문자 없는 글자를 그대로 지난다 — `MessagePageRequest` 와 같다).
    package enum CodingKeys: String, CodingKey, CaseIterable {
        case pTo = "p_to"
        case pPath = "p_path"
        case pWidth = "p_width"
        case pHeight = "p_height"
        case pCaption = "p_caption"
        case pClientMessageId = "p_client_message_id"
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTo, forKey: .pTo)
        try container.encode(pPath, forKey: .pPath)
        try container.encode(pWidth, forKey: .pWidth)
        try container.encode(pHeight, forKey: .pHeight)
        // `encode` 다(encodeIfPresent 가 아니다) — nil 이면 키를 빼지 않고 null 을 싣는다.
        try container.encode(pCaption, forKey: .pCaption)
        try container.encode(pClientMessageId, forKey: .pClientMessageId)
    }
}

/// `send_photo_message` 응답. send_message 와 같은 jsonb(`PokeSendResponse` — 그 디코더를 그대로 탄다) + 사진 칸 + 문 칸.
package struct SendPhotoMessageResponse: Decodable, Equatable {
    /// 공용 칸(status · message_id · created_at · body · duplicate · ring · max_length …).
    package let send: PokeSendResponse
    /// `unsupported_client` 에 실려 온다: 문이 열렸는가(서버가 이 기기를 아직 새 판으로 모를 뿐인가).
    package var doorOpen: Bool?
    package var photoPath: String?
    package var photoWidth: Int?
    package var photoHeight: Int?

    package init(send: PokeSendResponse, doorOpen: Bool? = nil, photoPath: String? = nil, photoWidth: Int? = nil, photoHeight: Int? = nil) {
        self.send = send
        self.doorOpen = doorOpen
        self.photoPath = photoPath
        self.photoWidth = photoWidth
        self.photoHeight = photoHeight
    }

    /// 카멜 이름만(원값 없음 — ②).
    private enum CodingKeys: String, CodingKey {
        case doorOpen, photoPath, photoWidth, photoHeight
    }

    package init(from decoder: Decoder) throws {
        send = try PokeSendResponse(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 칸 하나가 깨져도 응답 전체를 버리지 않는다(사진 칸은 ok 에만 붙는 덤이다).
        doorOpen = (try? c.decodeIfPresent(Bool.self, forKey: .doorOpen)) ?? nil
        photoPath = (try? c.decodeIfPresent(String.self, forKey: .photoPath)) ?? nil
        photoWidth = (try? c.decodeIfPresent(Int.self, forKey: .photoWidth)) ?? nil
        photoHeight = (try? c.decodeIfPresent(Int.self, forKey: .photoHeight)) ?? nil
    }

    package var status: String { send.status }

    /// ok 에 실려 온 사진(모양 규칙을 지날 때만).
    package var attachment: MessagePhotoAttachment? {
        MessagePhotoAttachment(path: photoPath, width: photoWidth, height: photoHeight)
    }
}

/// 사진 보내기 결과(③). 공용 어휘는 `.message(MessageSendOutcome)` 로 **그대로** 지나고, 사진만의 셋이 따로 선다.
package enum MessagePhotoSendOutcome: Equatable {
    /// send_message 와 같은 어휘(ok · blackout · flood · target_focused … · 모르는 말은 `.invalid`).
    case message(MessageSendOutcome)
    /// 문이 닫혀 있다(또는 이 기기를 새 판으로 모른다). `doorOpen` 은 서버가 실어 준 값(nil = 안 실었다).
    case unsupportedClient(doorOpen: Bool?)
    /// 경로 · 크기 · 이미 다른 메시지에 붙은 사진.
    case invalidPhoto
    /// 그 경로에 올린 파일이 없다.
    case photoMissing

    package init(response: SendPhotoMessageResponse) {
        switch response.status {
        case "unsupported_client": self = .unsupportedClient(doorOpen: response.doorOpen)
        case "invalid_photo": self = .invalidPhoto
        case "photo_missing": self = .photoMissing
        default: self = .message(MessageSendOutcome(response: response.send))
        }
    }
}

// MARK: - 운영자: 신고된 사진 경로

/// `report_admin_photo_paths` 요청 — 키 하나(`p_ids`, uuid 배열).
package struct ReportAdminPhotoPathsRequest: Encodable, Equatable, Sendable {
    package let pIds: [String]

    package init(ids: [String]) { pIds = ids }

    package enum CodingKeys: String, CodingKey {
        case pIds = "p_ids"
    }
}

/// 응답 한 행 `{report_id, photo_path}`. 칸마다 따로 읽고(깨진 원소는 그 원소만 버린다), 카멜 이름만 둔다(②).
package struct ReportAdminPhotoPathRow: Decodable, Equatable, Sendable {
    package var reportId: String?
    package var photoPath: String?

    package init(reportId: String?, photoPath: String?) {
        self.reportId = reportId
        self.photoPath = photoPath
    }

    private enum CodingKeys: String, CodingKey {
        case reportId, photoPath
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reportId = (try? c.decodeIfPresent(String.self, forKey: .reportId)) ?? nil
        photoPath = (try? c.decodeIfPresent(String.self, forKey: .photoPath)) ?? nil
    }
}

/// 배열의 원소 하나가 깨져도 그 원소만 nil 로 접는 상자.
private struct ReportAdminPhotoPathLossyRow: Decodable {
    let row: ReportAdminPhotoPathRow?
    init(from decoder: Decoder) throws {
        row = try? ReportAdminPhotoPathRow(from: decoder)
    }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let sendPhotoMessagePath = "/rest/v1/rpc/send_photo_message"
    package nonisolated static let reportAdminPhotoPathsPath = "/rest/v1/rpc/report_admin_photo_paths"

    /// 사진 JPEG 를 올린다(`POST /storage/v1/object/message-photos/<path>` · image/jpeg · **x-upsert 없음**).
    /// 실패 갈래는 버킷 도우미 그대로다: 정책 거절 → `PrivateStorageError.forbidden` · 같은 경로(우리의 재시도) → `.alreadyExists` ·
    /// 버킷 없음 → `.databaseSchemaMissing` · 만료 → `.sessionExpired`.
    package func uploadMessagePhoto(accessToken: String, path: String, data: Data) async throws {
        guard MessagePhotoPath.isServerShaped(path) else { throw PrivateStorageError.invalidPath }
        try await uploadPrivateObject(
            bucket: MessagePhotoText.bucket,
            path: path,
            data: data,
            contentType: PrivateStorage.jpegContentType,
            accessToken: accessToken
        )
    }

    /// `send_photo_message` 한 번. 응답은 **서비스 디코더**로 읽는다(시험이 같은 바이트를 같은 디코더로 흘린다).
    /// 함수가 없는 서버(404/PGRST202)는 그대로 던진다 — 숨길지는 스토어가 정한다.
    package func sendPhotoMessage(accessToken: String, request: SendPhotoMessageRequest) async throws -> SendPhotoMessageResponse {
        let data = try await send(
            path: Self.sendPhotoMessagePath,
            method: "POST",
            body: request,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(SendPhotoMessageResponse.self, from: data)
    }

    /// 사진 바이트를 받는다(서명 URL — 계약 v2 "보기는 서명 URL"). 경로가 서버 모양이 아니면 요청을 내지 않는다(④).
    package func fetchMessagePhotoData(accessToken: String, path: String) async throws -> Data {
        guard MessagePhotoPath.isServerShaped(path) else { throw PrivateStorageError.invalidPath }
        return try await downloadPrivateObjectViaSignedURL(
            bucket: MessagePhotoText.bucket,
            path: path,
            expiresIn: MessagePhotoText.signedURLSeconds,
            accessToken: accessToken
        )
    }

    /// 운영자: 신고 id → 사진 경로(사진이 붙은 신고만 온다). 운영자가 아니면 빈 배열이다. 경로가 서버 모양이 아닌 행은 버린다.
    package func fetchReportAdminPhotoPaths(accessToken: String, ids: [String]) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let data = try await send(
            path: Self.reportAdminPhotoPathsPath,
            method: "POST",
            body: ReportAdminPhotoPathsRequest(ids: ids),
            accessToken: accessToken,
            prefer: nil
        )
        return try reportAdminPhotoPaths(from: data)
    }

    /// 응답 바이트 → (신고 id → 경로). 디코더는 서비스의 것이다.
    package func reportAdminPhotoPaths(from data: Data) throws -> [String: String] {
        let rows = try decoder.decode([ReportAdminPhotoPathLossyRow].self, from: data).compactMap(\.row)
        var paths: [String: String] = [:]
        for row in rows {
            guard let id = row.reportId, !id.isEmpty, let path = row.photoPath, MessagePhotoPath.isServerShaped(path) else { continue }
            paths[id] = path
        }
        return paths
    }
}
