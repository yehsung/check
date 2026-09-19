import Foundation

// MARK: - 신고 관리(운영자) — 20260920100000_report_admin.sql 의 RPC 셋
//
// 폰 앱에 신고(`report_content` → `content_reports`)가 생겼고 심사 노트·지원 페이지에 "접수한 신고는 24시간 안에
// 확인합니다"라고 약속했다. 그 약속을 지키는 운영자 화면(맥 "받은 제보" 탭 안의 [신고])이 부르는 세 RPC 다:
//   · `report_admin_list(p_status, p_limit)`   — 운영자면 전부, 아니면 **0행**(예외가 아니다 — 제보함 목록 규약).
//   · `report_admin_update(p_id, p_status, p_note)` — 운영자만(아니면 `REPORT_FORBIDDEN`). 새 처리 시각을 돌려준다.
//   · `report_open_count()`                     — 운영자면 미해결 건수, 아니면 0.
//
// ── 이 파일이 지키는 것 ──
// ① **판정은 서버다.** 여기 어느 타입도 "운영자인가"를 묻지 않는다. 맥 게이트(`#if os(macOS)`)도 두지 않는다 —
//    폰 바이너리에 경로 문자열이 실려도 서버가 비운영자에게 0행·0·거절을 준다(SPEC w20 A-2). 관리자 화면을 여닫는
//    깃발(`ultraUnlimited`)은 표시 전용이고 맥 스토어가 "물어볼까"에만 쓴다.
// ② **목록 디코드는 관대하다.** 제보 목록(`FeedbackReportRow`)과 같은 관용 — 칸 하나가 없거나 모양이 달라도 목록
//    **전체**가 죽지 않는다. 여기서는 한 걸음 더 간다: 칸마다 `try?` 로 읽어 **타입이 어긋난 칸도 nil** 로 접고,
//    id 를 못 읽은 행만 버린다(처리 버튼을 걸 곳이 없는 행이다). 신고 목록이 통째로 죽으면 운영자는 신고가 0건이라고
//    믿는다 — 24시간 약속이 그 순간 조용히 깨진다.
// ③ **신고 본문은 사람이 쓴 글이다.** 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라(제보·메시지 파일 공통 규약).
// ④ 모르는 값은 **접지 않는다.** 상태는 `FeedbackStatus.other(원문)`, 사유는 원문 그대로 — 서버가 어휘를 늘린 날
//    조용한 오배달보다 낯선 글자가 낫다(열거값 확장엔 능력 협상).

extension SupabaseWorkService {
    /// 신고 목록(운영자 전용). 미해결 먼저 → 최신순으로 오지만, 정렬을 신뢰하지 않고 호출부가 다시 세운다(제보 목록과 같은 규약).
    /// `status` 가 nil 이면 키가 빠져(합성 인코딩) 서버 기본값(전체)을 쓴다.
    package func fetchReportAdminList(
        accessToken: String,
        status: ContentReportStatus?,
        limit: Int
    ) async throws -> [ContentReportAdminItem] {
        let data = try await send(
            path: Self.reportAdminListPath,
            method: "POST",
            body: ReportAdminListRequest(pStatus: status?.rawValue, pLimit: limit),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([ContentReportAdminRow].self, from: data)
        // 클로저 인자 이름이 `row` 가 **아닌** 이유는 제보 목록·차단 목록과 같다(소스 계약 테스트가 그 문장을 센다).
        return rows.compactMap { reportRow in item(from: reportRow) }
    }

    /// 신고 한 건의 상태·처리 메모를 바꾼다(운영자 전용). 성공하면 서버가 찍은 처리 시각을 돌려준다.
    ///
    /// `note` 의 뜻은 서버와 같다: **nil = 메모를 그대로 둔다**(키가 빠진다), 빈 문자열 = 메모를 지운다.
    /// 거절은 서버가 예외로 말한다 — `REPORT_FORBIDDEN` · `REPORT_BAD_STATUS` · `REPORT_NOTE_TOO_LONG` · `REPORT_NOT_FOUND`
    /// (공용 매핑을 지나 `.authMessage(원문)` 으로 올라가고, 사람 말로 옮기는 일은 맥 스토어의 `ReportAdminFailure` 가 한다).
    ///
    /// **시각을 못 읽어도 throw 하지 않는다**(제보 `replyFeedback` 과 같은 근거): 여기까지 왔다는 것은 서버가 **이미
    /// 저장했다**는 뜻이다. 스칼라 모양이 조금 다르다고 성공을 실패로 뒤집으면 운영자는 같은 처리를 다시 누른다.
    /// nil 을 돌려주면 호출부가 자기 시계로 근사하고, 다음 목록 조회가 서버 값으로 덮는다.
    package func updateReportAdmin(
        accessToken: String,
        id: String,
        status: ContentReportStatus,
        note: String?
    ) async throws -> Date? {
        let data = try await send(
            path: Self.reportAdminUpdatePath,
            method: "POST",
            body: ReportAdminUpdateRequest(pId: id, pStatus: status.rawValue, pNote: note),
            accessToken: accessToken,
            prefer: nil
        )
        return (try? decoder.decode(String.self, from: data)).flatMap { parseDate($0) }
    }

    /// 미해결 신고 건수. 인자 없는 RPC 라 본문은 `{}` 다(`feedback_open_count` 와 같은 규약 — PostgREST 는 본문의 키 집합으로
    /// 함수를 고른다). 운영자가 아니면 서버가 0 을 준다 — 클라가 판정하지 않는다. 모양이 어긋나면 0(배지 하나 때문에 실패를 올리지 않는다).
    package func fetchReportOpenCount(accessToken: String) async throws -> Int {
        let data = try await send(
            path: Self.reportOpenCountPath,
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return (try? decoder.decode(Int.self, from: data)) ?? 0
    }

    /// 행 → 화면 모델. id 가 없으면 nil(버린다). 나머지 빈칸은 **지어내지 않고** 폴백 글자나 nil 로 둔다.
    package func item(from reportRow: ContentReportAdminRow) -> ContentReportAdminItem? {
        guard let id = reportRow.id, !id.isEmpty else { return nil }
        let reporterID = reportRow.reporterId.flatMap { $0.isEmpty ? nil : $0 }
        return ContentReportAdminItem(
            id: id,
            reporterID: reporterID,
            // 신고자가 계정을 지웠으면 서버가 reporter 를 null 로 익명화한다(on delete set null) — 그 사실을 이름 자리에서 말한다.
            // 계정은 있는데 별명이 비었으면 이력·제보 목록과 같은 폴백('사용자')이다.
            reporterName: reporterID == nil
                ? ReportAdminNames.departedReporter
                : ContentReportAdminItem.displayName(reportRow.reporterName),
            reporterAvatarURL: reporterID == nil ? nil : reportRow.reporterAvatarUrl.flatMap { URL(string: $0) },
            targetID: reportRow.targetId.flatMap { $0.isEmpty ? nil : $0 },
            targetName: ContentReportAdminItem.displayName(reportRow.targetName),
            targetAvatarURL: reportRow.targetAvatarUrl.flatMap { URL(string: $0) },
            reason: reportRow.reason ?? "",
            detail: ContentReportAdminItem.visibleText(reportRow.detail),
            messageBody: ContentReportAdminItem.visibleText(reportRow.messageBody),
            // 상태가 비어 오면 '미해결'로 읽는다(새 신고는 언제나 open 에서 시작한다 — 서버 기본값). 모르는 값은 원문 그대로.
            status: ContentReportStatus(rawValue: reportRow.status ?? ContentReportStatus.open.rawValue),
            adminNote: ContentReportAdminItem.visibleText(reportRow.adminNote),
            createdAt: reportRow.createdAt.flatMap { parseDate($0) },
            handledAt: reportRow.handledAt.flatMap { parseDate($0) }
        )
    }

    package nonisolated static let reportAdminListPath = "/rest/v1/rpc/report_admin_list"
    package nonisolated static let reportAdminUpdatePath = "/rest/v1/rpc/report_admin_update"
    package nonisolated static let reportOpenCountPath = "/rest/v1/rpc/report_open_count"
}

// MARK: - 상태 어휘

/// 신고 처리 상태. **제보 상태와 같은 타입이다** — 서버 어휘가 같은 넷(`content_reports.status` CHECK = open · doing · done ·
/// wontfix, 20260918180000)이고, 새 어휘를 만들지 않는 것이 이 기능의 규칙이다(SPEC w20 A-1). 같은 타입이라 모르는 값을
/// `.other(원문)` 으로 받는 보호(열거값 확장엔 능력 협상)도 그대로 따라온다. 다른 것은 **화면 라벨뿐**이다(`reportLabel`).
package typealias ContentReportStatus = FeedbackStatus

extension FeedbackStatus {
    /// 신고 화면의 라벨. 제보(미해결·진행·완료·보류)와 **말이 다르다** — 신고는 버그가 아니라 사람에 대한 판단이라
    /// "완료"보다 "조치함", "보류"보다 "무시"가 운영자가 실제로 한 일을 말한다(SPEC w20 A-3 의 [처리 중]/[조치함]/[무시]).
    /// 서버로 나가는 값(`rawValue`)은 제보와 같다 — 라벨만 갈린다.
    package var reportLabel: String {
        switch self {
        case .open: return "미해결"
        case .inProgress: return "처리 중"
        case .done: return "조치함"
        case .held: return "무시"
        case .other(let raw): return raw
        }
    }

    /// 신고 행에서 누를 수 있는 전이. **[미해결]이 들어 있다** — 제보 화면이 v0.2.48 에 물린 결함(잘못 누른 [완료]를
    /// 앱 안에서 되돌릴 길이 없었다 — `FeedbackStatus.transitions` 주석)을 여기서 되풀이하지 않는다. 신고도 지워지지
    /// 않으므로 한 번의 오조작이 영구가 되고, 미해결 건수(메뉴바 점)가 그만큼 거짓이 된다.
    package static let reportTransitions: [FeedbackStatus] = [.open, .inProgress, .done, .held]
}

// MARK: - 전선 모양

/// `report_admin_list(p_status, p_limit)` 본문. `pStatus` 가 nil 이면 키가 빠져 서버 기본값(전체)을 쓴다.
package struct ReportAdminListRequest: Encodable, Equatable, Sendable {
    package var pStatus: String?
    package let pLimit: Int

    package init(pStatus: String?, pLimit: Int) {
        self.pStatus = pStatus
        self.pLimit = pLimit
    }
}

/// `report_admin_update(p_id, p_status, p_note)` 본문. `pNote` 가 nil 이면 키가 빠진다 = 서버가 메모를 그대로 둔다
/// (빈 문자열과 뜻이 다르다 — 빈 문자열은 "지운다"). 인코더의 스네이크 변환이 `pId` → `p_id` 로 옮긴다.
package struct ReportAdminUpdateRequest: Encodable, Equatable, Sendable {
    package let pId: String
    package let pStatus: String
    package var pNote: String?

    package init(pId: String, pStatus: String, pNote: String?) {
        self.pId = pId
        self.pStatus = pStatus
        self.pNote = pNote
    }
}

/// `report_admin_list` 응답 행. **전부 옵셔널이고 칸마다 따로 읽는다**(파일 머리 ②).
///
/// 키는 `.convertFromSnakeCase` 가 이미 카멜로 바꾼 뒤에 매칭되므로 카멜로 적는다(`BlockedUserRow` 와 같은 함정 —
/// `reporter_avatar_url` → `reporterAvatarUrl`). 서버 반환 칸 이름은 마이그레이션 §4 가 카탈로그로 못 박고,
/// 이 목록과 그 칸 이름이 같은지는 `V0334ReportAdminMigrationTests` 가 대조한다.
package struct ContentReportAdminRow: Decodable, Equatable, Sendable {
    package let id: String?
    package let reporterId: String?
    package let reporterName: String?
    package let reporterAvatarUrl: String?
    package let targetId: String?
    package let targetName: String?
    package let targetAvatarUrl: String?
    package let reason: String?
    package let detail: String?
    package let messageBody: String?
    package let status: String?
    package let adminNote: String?
    package let createdAt: String?
    package let handledAt: String?

    package enum CodingKeys: String, CodingKey, CaseIterable {
        case id, reporterId, reporterName, reporterAvatarUrl, targetId, targetName, targetAvatarUrl
        case reason, detail, messageBody, status, adminNote, createdAt, handledAt
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` + `decodeIfPresent` — 없으면 nil, **타입이 어긋나도 nil**. 한 칸 때문에 배열 디코드가 통째로 throw 되면
        // 목록 전체가 사라진다(파일 머리 ②).
        func text(_ key: CodingKeys) -> String? { (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil }
        id = text(.id)
        reporterId = text(.reporterId)
        reporterName = text(.reporterName)
        reporterAvatarUrl = text(.reporterAvatarUrl)
        targetId = text(.targetId)
        targetName = text(.targetName)
        targetAvatarUrl = text(.targetAvatarUrl)
        reason = text(.reason)
        detail = text(.detail)
        messageBody = text(.messageBody)
        status = text(.status)
        adminNote = text(.adminNote)
        createdAt = text(.createdAt)
        handledAt = text(.handledAt)
    }
}

// MARK: - 화면 모델

/// 운영자 목록의 신고 한 건. 행 자체가 완결이다(이름·아바타 포함) — 제보 목록과 같은 설계.
package struct ContentReportAdminItem: Identifiable, Equatable, Sendable {
    package let id: String
    /// 신고자. **nil = 계정을 지웠다**(서버가 익명화했다).
    package let reporterID: String?
    package let reporterName: String
    package let reporterAvatarURL: URL?
    package let targetID: String?
    package let targetName: String
    package let targetAvatarURL: URL?
    /// 서버 사유 원문(`spam` · `harassment` · `inappropriate` · `other`). 화면 글자는 `reasonLabel`.
    package let reason: String
    /// 신고자가 적은 자유 입력(200자). **사람이 쓴 글이다.** 비었으면 nil.
    package let detail: String?
    /// 신고 순간의 메시지 본문 스냅숏(400자). 사람 신고면 nil. **신고당한 사람이 쓴 글이다** — 로그로 흘리지 마라.
    package let messageBody: String?
    package var status: ContentReportStatus
    /// 운영자의 처리 메모(500자). 신고자에게는 안 보인다(서버가 칸 단위로 막는다). 비었으면 nil.
    package var adminNote: String?
    package let createdAt: Date?
    /// 운영자가 마지막으로 상태·메모를 바꾼 순간. nil = 아직 아무도 손대지 않았다(또는 서버가 아직 이 칸을 모른다).
    package var handledAt: Date?

    package init(
        id: String,
        reporterID: String?,
        reporterName: String,
        reporterAvatarURL: URL?,
        targetID: String?,
        targetName: String,
        targetAvatarURL: URL?,
        reason: String,
        detail: String?,
        messageBody: String?,
        status: ContentReportStatus,
        adminNote: String?,
        createdAt: Date?,
        handledAt: Date?
    ) {
        self.id = id
        self.reporterID = reporterID
        self.reporterName = reporterName
        self.reporterAvatarURL = reporterAvatarURL
        self.targetID = targetID
        self.targetName = targetName
        self.targetAvatarURL = targetAvatarURL
        self.reason = reason
        self.detail = detail
        self.messageBody = messageBody
        self.status = status
        self.adminNote = adminNote
        self.createdAt = createdAt
        self.handledAt = handledAt
    }

    /// 사유의 한국어 라벨. 폰 신고 시트의 네 칸(`ContentReportReason.label`)과 **같은 글자**다 — 운영자가 보는 말과 신고자가
    /// 고른 말이 갈리면 "무엇으로 신고했는지"가 흐려진다. 모르는 사유는 원문 그대로(파일 머리 ④), 비었으면 '기타'.
    package var reasonLabel: String {
        if let known = ContentReportReason(rawValue: reason) { return known.label }
        return reason.isEmpty ? ContentReportReason.other.label : reason
    }

    /// 신고자가 계정을 지웠는가.
    package var reporterDeparted: Bool { reporterID == nil }

    /// 메시지 신고인가(원문 스냅숏이 있다).
    package var isMessageReport: Bool { messageBody != nil }

    /// 별명 폴백(이력·제보·차단 목록과 같은 글자).
    package static func displayName(_ raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ReportAdminNames.unnamed }
        return raw
    }

    /// 공백만 남은 글은 없는 것이다(빈 판이 행에 서면 운영자는 뭔가 적혀 있는 줄 안다). 글 자체는 **다듬지 않는다** —
    /// 신고자·신고당한 사람이 쓴 그대로 보여야 판단할 수 있다.
    package static func visibleText(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }
}

/// 이름 자리의 폴백 글자.
package enum ReportAdminNames {
    /// 별명이 비었을 때(이력·제보 목록과 같은 글자).
    package static let unnamed = "사용자"
    /// 신고자가 계정을 지웠을 때. '사용자'로 두면 운영자는 누가 신고했는지 모르는 이유를 모른다.
    package static let departedReporter = "탈퇴한 사용자"
}

/// 처리 메모의 정규화·상한. **서버와 같은 판정**이다(`report_admin_update` 가 btrim 뒤 500자를 본다).
package enum ReportAdminNote {
    /// 상한 — 제보함 답장 메모(`FeedbackComposer.maxNoteLength`)와 같은 값이다(SPEC w20 A-1).
    package static let maxLength = FeedbackComposer.maxNoteLength

    /// 서버로 나갈 메모. 앞뒤 공백을 걷어내고 상한에서 자른다. **빈 문자열이 나갈 수 있다** — 그게 "메모를 지운다"이다.
    /// 행을 펼칠 때 칸에 저장된 메모를 실어 주므로(맥 스토어 `toggleReportExpansion`), 칸에 보이는 것이 곧 저장될 것이다.
    ///
    /// **자르는 눈금은 코드포인트다.** 서버 `char_length` 가 코드포인트를 세므로, 자소 묶음(`Character`)으로 500을 자르면
    /// 이모지 섞인 메모가 서버에서 `REPORT_NOTE_TOO_LONG` 으로 거절된다. 자소 묶음을 반으로 가르지 않도록 묶음 단위로 담되,
    /// 담을지는 코드포인트 합으로 판정한다(제보 진단 첨부 `FeedbackDiagnostics.measured` 와 같은 보수적 눈금).
    package static func outgoing(_ draft: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var kept = ""
        var scalars = 0
        for character in trimmed {
            let width = character.unicodeScalars.count
            if scalars + width > maxLength { break }
            kept.append(character)
            scalars += width
        }
        return kept
    }
}
