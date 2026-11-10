import Foundation

// MARK: - 제보 화면 캡처(11-11 대표 결정 #d_x5kYyOPOeLlH "제보에 화면 캡처 첨부하는것도 괜찮고")
//
// ★ **이 기능의 서버 어휘는 전부 이 파일에 있다**(계약 v2 §3 — 서버 팀 목록 11-11 · 초안 20261114101000).
//   버킷 이름 · 개체 경로 모양 · RPC 이름 · 본문 키 · 응답 칸 · status 어휘. 다른 파일은 여기 이름을 부르기만 한다.
//
// ── 순서(서버가 강제한다) ──
//   ① `submit_feedback` — **예전 네 키 그대로**. 새 제보 id(uuid 문자열)를 돌려준다.
//   ② 캡처마다 저장소에 올린다: `feedback-shots/<내 uid>/<제보 id>/<새 uuid>.jpg`(전부 소문자, upsert 없음).
//      내 제보 · 제보 한 시간 안 · 그 폴더에 3장 미만 · 문이 열렸을 때만 저장소가 받는다(아니면 403/400 RLS).
//   ③ 캡처마다 `feedback_attach_shot(p_report, p_path, p_width, p_height)`.
//   목록: `feedback_list` 를 받은 뒤 **한 번에** `feedback_shots(p_report_ids)` → 행(report_id · attachment_id · path ·
//   width · height · created_epoch_ms). 보기는 서명 URL(`downloadPrivateObjectViaSignedURL`).
//
// ── 지키는 것 ──
// ① **디코더 함정**: 서비스 디코더는 `convertFromSnakeCase` 다. 응답 모델은 낙타 표기 이름이고 스네이크 원문 CodingKeys 가
//    없다 — 원문 키를 적으면 그 디코더 아래에서 조용히 nil 이 된다. 시험은 진짜 서비스 경로(스텁 URLProtocol)로 디코드한다.
// ② **요청 본문은 키를 전부 싣는다**(PostgREST 는 키 집합으로 함수를 고른다). 이름은 서버 인자 이름 그대로다.
// ③ 캡처는 남의 이름·대화가 찍혀 있을 수 있다 — 바이트 · 경로 · 본문을 로그로 흘리지 마라.

/// 제보 캡처의 서버 어휘 한 벌.
package enum FeedbackShotWire {
    /// 비공개 버킷. 읽기는 본인 · 운영자만(서버 정책 `feedback_shot_readable`).
    package static let bucket = "feedback-shots"
    /// 붙이기 RPC.
    package static let attachPath = "/rest/v1/rpc/feedback_attach_shot"
    /// 목록 옆 캡처 RPC(한 번에 여러 제보).
    package static let listPath = "/rest/v1/rpc/feedback_shots"
    /// 제보 하나에 붙는 캡처 상한(서버 `feedback_shots_per_report()` = 3). 보내기 탭이 고를 수 있는 수도 이 값이다.
    package static let maxPerReport = 3
    /// 서명 URL 수명(초) — 계약 v2 의 `{"expiresIn":3600}`.
    package static let signedURLSeconds = 3600

    /// `<내 uid>/<제보 id>/<새 uuid>.jpg` — **조각마다 소문자**(서버 정책이 글자 그대로 견준다). 시도마다 새 uuid 다.
    package static func objectPath(userID: String, reportID: String, fileID: String) -> String {
        PrivateStorage.objectPath(folders: [userID, reportID], name: fileID, ext: "jpg")
    }

    /// `submit_feedback` 이 돌려준 값 → 제보 id(소문자 uuid). uuid 모양이 아니면 nil — 그때 제보는 보낸 것으로 치고
    /// 캡처만 못 붙인다(디코드 실패가 성공한 전송을 실패로 보이게 하면 사람은 같은 글을 두 번 보낸다).
    package static func reportID(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return trimmed.lowercased()
    }

    /// 목록 행이 준 경로를 믿어도 되는가(빈 값 · 이상한 글자 · `..` 는 버린다 — URL 을 엉뚱한 곳으로 돌리지 못하게).
    package static func acceptedPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrivateStorage.isSafeObjectPath(trimmed) ? trimmed : nil
    }

    /// `feedback_shots` 행들 → 제보 id(소문자)별 캡처. 쓸 수 없는 행(칸 빠짐 · 이상한 경로 · 크기 0)은 버리고,
    /// 제보마다 붙인 순서(시각 → id)로 세운 뒤 **상한까지만** 둔다(화면 높이 추정이 그 수를 믿는다).
    package static func grouped(_ rows: [FeedbackShotRow]) -> [String: [FeedbackShot]] {
        var result: [String: [FeedbackShot]] = [:]
        for row in rows {
            guard let report = row.reportId?.lowercased(), !report.isEmpty,
                  let path = acceptedPath(row.path),
                  let width = row.width, let height = row.height, width > 0, height > 0
            else { continue }
            let shot = FeedbackShot(
                id: (row.attachmentId ?? path).lowercased(),
                reportID: report,
                path: path,
                width: width,
                height: height,
                createdAt: row.createdEpochMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            )
            if result[report]?.contains(where: { $0.path == path }) == true { continue }
            result[report, default: []].append(shot)
        }
        for (report, shots) in result {
            let sorted = shots.sorted {
                let left = $0.createdAt ?? .distantPast, right = $1.createdAt ?? .distantPast
                return left != right ? left < right : $0.id < $1.id
            }
            result[report] = Array(sorted.prefix(maxPerReport))
        }
        return result
    }
}

// MARK: - 본문

/// `feedback_attach_shot(p_report uuid, p_path text, p_width int, p_height int)` 본문. 키 넷을 **언제나** 싣는다(②).
/// 서비스 인코더가 낙타 → 스네이크로 바꾼다(`pReport` → `p_report`).
package struct FeedbackAttachShotRequest: Encodable, Equatable, Sendable {
    package let pReport: String
    package let pPath: String
    package let pWidth: Int
    package let pHeight: Int

    package init(pReport: String, pPath: String, pWidth: Int, pHeight: Int) {
        self.pReport = pReport
        self.pPath = pPath
        self.pWidth = pWidth
        self.pHeight = pHeight
    }

    private enum CodingKeys: String, CodingKey {
        case pReport, pPath, pWidth, pHeight
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pReport, forKey: .pReport)
        try container.encode(pPath, forKey: .pPath)
        try container.encode(pWidth, forKey: .pWidth)
        try container.encode(pHeight, forKey: .pHeight)
    }
}

/// `feedback_shots(p_report_ids uuid[])` 본문(`pReportIds` → `p_report_ids`).
package struct FeedbackShotsRequest: Encodable, Equatable, Sendable {
    package let pReportIds: [String]

    package init(pReportIds: [String]) {
        self.pReportIds = pReportIds
    }

    private enum CodingKeys: String, CodingKey {
        case pReportIds
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pReportIds, forKey: .pReportIds)
    }
}

// MARK: - 응답

/// `feedback_attach_shot` 응답 봉투. 낙타 표기 — 서비스 디코더가 `attachment_id` · `door_open` 을 이 이름에 맞춘다(①).
package struct FeedbackAttachShotResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let attachmentId: String?
    package let duplicate: Bool?
    package let doorOpen: Bool?
    package let max: Int?
}

/// 붙이기 한 번의 결과(서버 status 어휘 → 값).
package enum FeedbackAttachOutcome: Equatable, Sendable {
    /// 붙었다(같은 경로를 다시 붙였으면 `duplicate`).
    case attached(duplicate: Bool)
    /// 문이 닫혔다(`unsupported_client`). `doorOpen` = 서버 문 자체가 열렸는가(열렸는데 거절이면 이 앱 판이 아직 안 알려졌다).
    case doorClosed(doorOpen: Bool?)
    /// 내 제보가 아니다.
    case invalid
    /// 경로 · 크기가 맞지 않다.
    case invalidPhoto
    /// 그 경로에 올린 파일이 없다.
    case photoMissing
    /// 제보 하나의 상한을 넘었다.
    case tooMany(max: Int)
    case unauthorized
    /// 모르는 status(서버가 앞서 나갔다) — 실패로 친다.
    case unknown

    package static func from(_ response: FeedbackAttachShotResponse) -> FeedbackAttachOutcome {
        switch response.status ?? "" {
        case "ok": return .attached(duplicate: response.duplicate ?? false)
        case "unsupported_client": return .doorClosed(doorOpen: response.doorOpen)
        case "invalid": return .invalid
        case "invalid_photo": return .invalidPhoto
        case "photo_missing": return .photoMissing
        case "too_many": return .tooMany(max: response.max ?? FeedbackShotWire.maxPerReport)
        case "unauthorized": return .unauthorized
        default: return .unknown
        }
    }
}

/// `feedback_shots` 한 행. 낙타 표기(①) · 전부 옵셔널(칸 하나가 비어도 목록 전체가 죽지 않는다 — 그 행만 버린다).
package struct FeedbackShotRow: Decodable, Equatable, Sendable {
    package let reportId: String?
    package let attachmentId: String?
    package let path: String?
    package let width: Int?
    package let height: Int?
    package let createdEpochMs: Int64?
}

/// 제보에 붙은 캡처 한 장(표시용).
package struct FeedbackShot: Identifiable, Equatable, Sendable {
    /// attachment id(소문자).
    package let id: String
    /// 제보 id(소문자).
    package let reportID: String
    /// 버킷 안 경로.
    package let path: String
    package let width: Int
    package let height: Int
    package let createdAt: Date?

    package init(id: String, reportID: String, path: String, width: Int, height: Int, createdAt: Date?) {
        self.id = id
        self.reportID = reportID
        self.path = path
        self.width = width
        self.height = height
        self.createdAt = createdAt
    }
}

// MARK: - 규칙(순수)

package enum FeedbackShotRules {
    /// 보내기 탭이 붙일 수 있는 캡처 수 = 서버 상한.
    package static let maxDraft = FeedbackShotWire.maxPerReport
    /// 화면 캡처를 줄이는 긴 변(px)과 JPEG 품질 — 계약 "긴 변 1600px 안팎 · JPEG · 약 0.3MB".
    package static let maxDimension: Double = 1600
    package static let jpegQuality: Double = 0.8
    /// 그래도 이보다 크면 한 번 더 세게 줄인다(바이트). 버킷 상한(5MB)보다 넉넉히 작다.
    package static let maxUploadBytes = 1_500_000
    package static let fallbackJPEGQuality: Double = 0.6
    /// 받아 둔 캡처 그림 수 상한(관리자가 여러 행을 펼쳐 볼 때 메모리가 끝없이 자라지 않게).
    package static let cacheLimit = 24

    /// "이 서버에는 그 함수(또는 버킷)가 없다" — 404 · PGRST202 · 버킷 없음. 기능 입구를 숨기되 **영구히 기억하지 않는다**.
    package static func isMissing(_ error: Error) -> Bool {
        guard let serviceError = error as? SupabaseWorkServiceError else { return false }
        return BlockReportRules.isMissingFunction(serviceError)
    }
}

// MARK: - 문구

/// 제보 캡처 문구. 숫자는 상수에서 나온다.
package enum FeedbackShotText {
    /// 자동 첨부 안내 한 줄에 끼는 말 — 캡처를 붙였을 때만 들어간다.
    package static let noticeTerm = "화면 캡처"
    package static let rowTitle = "화면 캡처"
    package static var limitHint: String { "최대 \(FeedbackShotWire.maxPerReport)장" }
    /// 파일 고르기 창의 안내 — **남은 자리**를 말한다(이미 붙인 것이 있으면 상한보다 적다). 넘게 고르면 앞에서부터 그만큼만 붙고
    /// `full` 이 선다.
    package static func pickerMessage(remaining: Int) -> String {
        "제보에 붙일 화면 캡처를 골라 주세요(\(max(0, remaining))장 더 붙일 수 있어요)"
    }
    package static let pickAction = "이미지 고르기"
    package static let pasteAction = "붙여넣기"
    package static let removeAction = "빼기"
    /// 붙인 수 / 상한.
    package static func attachedCount(_ count: Int) -> String { "\(count)/\(FeedbackShotWire.maxPerReport)" }
    /// 붙인 동안 **늘** 보이는 경고 한 줄 — 찍힌 화면에 남의 이름·대화가 있을 수 있고, 누가 보는지를 함께 말한다.
    package static let privacyWarning = "남의 이름·대화가 찍혔는지 확인해 주세요 · 나와 운영자만 봐요"
    package static let preparing = "캡처를 준비하는 중…"
    package static let pasteEmpty = "클립보드에 이미지가 없어요"
    package static let unreadable = "이미지를 읽지 못했어요 — 다른 파일을 골라 주세요"
    package static let tooLarge = "이미지가 너무 커요 — 다른 이미지를 골라 주세요"
    package static var full: String { "캡처는 \(FeedbackShotWire.maxPerReport)장까지 붙일 수 있어요" }

    // 보낸 뒤(제보 글은 이미 갔다 — 다시 보내지 않는다)
    /// 글은 갔고 캡처를 올리는 중.
    package static let uploading = "제보는 보냈어요 · 캡처 올리는 중…"
    /// 캡처를 하나도 못 붙였다.
    package static let sentShotsFailed = "제보는 보냈어요 · 캡처는 못 붙였어요"
    /// 일부만 못 붙였다.
    package static func sentSomeShotsFailed(_ failed: Int) -> String { "제보는 보냈어요 · 캡처 \(failed)장은 못 붙였어요" }
    /// 서버 문이 닫혔다(`unsupported_client` · `door_open` 거짓) — 내 앱 탓이 아니다.
    package static let sentShotsDoorClosed = "제보는 보냈어요 · 캡처 붙이기는 아직 준비 중이에요"
    /// 서버 문은 열렸는데 이 앱 판을 받지 않았다(`unsupported_client` · `door_open` 참) — 서버가 아는 이 기기의 판이 아직 옛것이거나
    /// (판 알리기 전) 문턱이 이 판보다 높다. 둘 다 최신 앱을 다시 켜면 풀린다.
    package static let sentShotsAppOutdated = "제보는 보냈어요 · 캡처는 앱을 최신으로 다시 켜면 붙어요"
    /// 상한을 넘었다(`too_many`).
    package static func sentShotsTooMany(_ max: Int) -> String { "제보는 보냈어요 · 캡처는 \(max)장까지만 붙어요" }

    // 목록
    /// 내가 보낸 제보 행 · 받은 제보 메타 줄의 칩.
    package static func chip(_ count: Int) -> String { "캡처 \(count)장" }
    package static let loading = "불러오는 중…"
    package static let loadFailed = "못 불러왔어요"
    package static let missing = "지워진 캡처예요"
    /// 받은 제보 펼친 행 썸네일 판의 이름표.
    package static func stripTitle(_ count: Int) -> String { "\(rowTitle) \(count)장" }
    package static let viewerClose = "닫기"
    package static let viewerPrevious = "이전"
    package static let viewerNext = "다음"
    package static func viewerPosition(_ index: Int, _ count: Int) -> String { "\(index + 1)/\(count)" }
    /// 크게 보기 머리 — "화면 캡처 1/3".
    package static func viewerTitle(_ index: Int, _ count: Int) -> String { "\(rowTitle) \(viewerPosition(index, count))" }
}

// MARK: - 서비스

extension SupabaseWorkService {
    /// 캡처 한 장을 올린다(②). 경로는 `FeedbackShotWire.objectPath` 가 만든다.
    package func uploadFeedbackShot(accessToken: String, path: String, jpeg: Data) async throws {
        try await uploadPrivateObject(
            bucket: FeedbackShotWire.bucket,
            path: path,
            data: jpeg,
            contentType: PrivateStorage.jpegContentType,
            accessToken: accessToken
        )
    }

    /// 올린 캡처를 제보에 붙인다(③). 응답이 봉투 모양이 아니면 `.unknown`(실패로 친다).
    package func attachFeedbackShot(
        accessToken: String,
        reportID: String,
        path: String,
        width: Int,
        height: Int
    ) async throws -> FeedbackAttachOutcome {
        let data = try await send(
            path: FeedbackShotWire.attachPath,
            method: "POST",
            body: FeedbackAttachShotRequest(pReport: reportID, pPath: path, pWidth: width, pHeight: height),
            accessToken: accessToken,
            prefer: nil
        )
        guard let response = try? decoder.decode(FeedbackAttachShotResponse.self, from: data) else { return .unknown }
        return FeedbackAttachOutcome.from(response)
    }

    /// 여러 제보의 캡처를 한 번에(목록 뒤 한 왕복). 내 제보만 오고 운영자는 전부 받는다(판정은 서버).
    package func fetchFeedbackShots(accessToken: String, reportIDs: [String]) async throws -> [String: [FeedbackShot]] {
        let data = try await send(
            path: FeedbackShotWire.listPath,
            method: "POST",
            body: FeedbackShotsRequest(pReportIds: reportIDs.map { $0.lowercased() }),
            accessToken: accessToken,
            prefer: nil
        )
        return FeedbackShotWire.grouped(try decoder.decode([FeedbackShotRow].self, from: data))
    }

    /// 캡처 한 장을 본다 — 서명 URL(3600초)을 받아 GET(계약 v2).
    package func downloadFeedbackShot(accessToken: String, path: String) async throws -> Data {
        try await downloadPrivateObjectViaSignedURL(
            bucket: FeedbackShotWire.bucket,
            path: path,
            expiresIn: FeedbackShotWire.signedURLSeconds,
            accessToken: accessToken
        )
    }
}
