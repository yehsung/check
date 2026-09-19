import Foundation
import CheckCore

// MARK: - 신고 관리(운영자) (v0.3.34) — "받은 제보" 탭 안의 [신고] 칸
//
// 왜: 폰 앱에 신고가 생겼고(content_reports) 심사 노트·지원 페이지에 "접수한 신고는 24시간 안에 확인합니다"라고
// 약속했는데, 신고는 서버 표에만 쌓이고 운영자가 볼 화면이 없었다(SPEC w20 갈래 A). 운영자 전용 표면은 이미 하나 있다 —
// 맥 [제보] 패널의 "받은 제보" 탭. 신고는 **거기에** 붙인다. 새 창·새 탭 체계를 만들지 않는다.
//
// ── 이 파일이 지키는 네 가지 ──
//
// ① **판정은 전부 서버다**(제보 파일 ① 과 같은 선). 운영자 판정은 서버 `is_app_admin()` 하나다 — 비운영자에게
//    `report_admin_list` 는 0행, `report_admin_update` 는 REPORT_FORBIDDEN, `report_open_count` 는 0 을 준다.
//    `ultraUnlimited`(표시 전용 깃발)로 하는 일은 "[신고] 칸을 그릴까"와 "물어볼까"(비운영자 40명이 매번 묻지 않게) 둘뿐이다.
// ② **제보 칸의 동작은 한 걸음도 안 바뀐다.** 신고 칸은 목록·펼침·메모 초안·안내 한 줄을 **자기 것으로** 따로 든다
//    (`WorkTimerStore` 의 report* 값들). 칸을 오갈 때 양쪽의 펼침·초안·안내를 접는 것은 탭을 오갈 때 제보가 이미 하던 일이다.
// ③ **폴링을 새로 만들지 않는다.** 목록은 [신고] 칸을 고를 때 · 그 칸이 열린 채 패널을 열 때 · 처리 성공 뒤에만 받는다.
//    미해결 건수는 거기에 더해 **팝오버를 여는 순간** 한 번(답장 배지와 같은 자리 — `setMenuPresented`) 묻는다.
// ④ **처리는 낙관 반영이 없다.** 제보 답장(`performSendFeedbackReply`)과 같은 판단이다 — 운영자가 알아야 하는 것은
//    "처리가 **저장됐는가**"이고(24시간 약속의 증거다), 왕복 전에 칩이 바뀌면 실패한 처리도 된 것처럼 보인다. 대신 떠 있는
//    동안 버튼을 잠그고(`reportUpdatingID`) "저장하는 중…"을 보인다. 잠금이 하나뿐이라 두 처리가 겹칠 수 없다.
//
// 비동기 관용구는 제보와 같다: 세션 가드 → 세대 캡처 → `withSessionRetry` → 세대 가드. 목록은 거기에 **조회 순번**을
// 하나 더 건다(`reportAdminLoadSerial`) — 늦게 도착한 옛 목록이 새 목록을 덮지 않게.
//
// ★ 신고의 상세·신고된 메시지 원문은 **사람이 쓴 글**이다. 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라.

extension WorkTimerStore {
    /// 한 번에 받을 신고 수 — 서버 기본값·상한과 같은 200(SPEC w20 A-1 `p_limit int default 200`).
    /// 페이지네이션은 없다: 47명 규모에서 200건이 밀리기 전에 24시간 약속이 먼저 깨진다.
    static let reportAdminListLimit = 200

    // MARK: 파생값(뷰가 읽는 것)

    /// [신고] 칸을 지금 그리는가. **세 값의 곱이다** — 받은 제보 탭을 그리는가(= 관리자 깃발 × 탭 선택) × 칸 선택.
    /// 관리자 깃발이 내려간 순간 낡은 칸 선택이 남아 있어도 신고 목록은 그려지지 않는다(받은 제보 탭과 같은 구조).
    var showsReportAdmin: Bool { showsFeedbackInbox && feedbackInboxShowsReports }

    /// 지금 그릴 신고들. 필터를 적용하고 **정렬을 다시 세운다**(서버 정렬을 신뢰하지 않는 규약 — 제보와 같다).
    var visibleReports: [ContentReportAdminItem] {
        let filtered = reportFilter.map { status in reportAdminList.filter { $0.status == status } } ?? reportAdminList
        return filtered.sortedForReportList()
    }

    /// 운영자가 처리해야 할 것의 합(미해결 제보 + 미해결 신고). **레일 [제보] 배지와 "받은 제보" 탭 배지가 읽는 값**이다 —
    /// 두 표면 모두 "받은 제보 탭 안에 손 안 댄 것이 몇 개"를 말한다. 비운영자에게는 둘 다 서버가 0 을 준다.
    var adminInboxOpenCount: Int { max(0, feedbackOpenCount) + max(0, reportOpenCount) }

    /// 지금 처리 버튼을 누를 수 있는가(떠 있는 처리가 없다).
    var canUpdateReport: Bool { reportUpdatingID == nil }

    // MARK: 칸 전환 · 필터 · 펼침

    /// 받은 제보 탭 안의 [제보] / [신고] 칩. 관리자가 아니면 [신고]로 갈 수 없다(뷰가 칩을 안 그리지만 문도 잠근다 —
    /// `selectFeedbackTab` 과 같은 두 겹).
    ///
    /// [신고]를 고를 때마다 목록을 **다시 받는다**. 24시간 약속이 걸린 표면이라, 칸을 여는 순간이 곧 최신을 보고 싶은 순간이다.
    func selectInboxSegment(reports: Bool) {
        let target = reports && ultraUnlimited
        guard feedbackInboxShowsReports != target else { return }
        feedbackInboxShowsReports = target
        // 양쪽의 펼침·초안·안내를 접는다 — 한 칸의 메모가 다른 칸 행에 붙거나, 한 칸의 안내가 다른 칸 아래 남으면
        // 무엇에 대한 말인지 알 수 없다(탭 전환이 이미 하는 일과 같다).
        expandedFeedbackID = nil
        feedbackNoteDraft = ""
        feedbackNotice = nil
        expandedReportID = nil
        reportNoteDraft = ""
        reportAdminNotice = nil
        if target {
            // 첫 프레임부터 "불러오는 중…"이 뜨게 — 세션이 있을 때만(없으면 아무도 이 깃발을 내려 주지 않는다).
            if session != nil, !reportAdminLoaded { reportAdminLoading = true }
            loadReportAdmin()
        }
    }

    /// 상태 필터 칩. nil = 전체. **다시 조회하지 않는다** — 목록은 이미 전부 받아 왔고 거르기는 순수 계산이다.
    func selectReportFilter(_ status: ContentReportStatus?) {
        guard reportFilter != status else { return }
        reportFilter = status
        expandedReportID = nil
        reportNoteDraft = ""
    }

    /// 행을 펼치거나 접는다(한 번에 하나). 펼칠 때 그 신고의 **저장된 메모**를 초안으로 싣는다 — 빈 칸으로 열면
    /// 상태 버튼 한 번에 기존 메모가 지워진다(상태 버튼이 칸의 글을 함께 저장한다).
    func toggleReportExpansion(_ id: String) {
        if expandedReportID == id {
            expandedReportID = nil
            reportNoteDraft = ""
            return
        }
        expandedReportID = id
        reportNoteDraft = reportAdminList.first { $0.id == id }?.adminNote ?? ""
    }

    /// 제보 패널이 열릴 때 [신고] 칸이 이미 골라져 있으면 목록을 새로 받는다(제보 목록이 패널 열기마다 새로 받는 것과 같은 규약).
    /// `openFeedbackPanel` 이 부른다 — 칸이 [제보]면 아무 일도 안 한다(제보 칸의 왕복 수가 그대로다).
    func reloadReportAdminIfShowing() {
        guard showsReportAdmin else { return }
        if session != nil, !reportAdminLoaded { reportAdminLoading = true }
        loadReportAdmin()
    }

    // MARK: 목록

    func loadReportAdmin() {
        Task { @MainActor in await performLoadReportAdmin() }
    }

    /// `report_admin_list` 를 받아 반영하고, 이어서 미해결 건수를 받는다(독립 실패 — 건수를 못 받아도 목록은 그린다).
    ///
    /// ★ **조회 순번 가드**: 조회가 겹치면(패널 열기 조회 + 처리 성공 뒤 재조회) 늦게 도착한 **옛** 응답이 새 목록을 덮을 수 있다.
    ///   세대 가드는 계정이 바뀐 경우만 막으므로, 마지막으로 **보낸** 조회의 응답만 반영한다.
    func performLoadReportAdmin() async {
        guard session != nil, ultraUnlimited else { return }
        let generation = sessionGeneration
        reportAdminLoadSerial += 1
        let serial = reportAdminLoadSerial
        if !reportAdminLoading { reportAdminLoading = true }
        if reportAdminFailed { reportAdminFailed = false }
        defer {
            if generation == sessionGeneration, serial == reportAdminLoadSerial, reportAdminLoading { reportAdminLoading = false }
        }
        do {
            let items = try await withSessionRetry { activeSession in
                try await service.fetchReportAdminList(
                    accessToken: activeSession.accessToken,
                    status: nil,
                    limit: Self.reportAdminListLimit
                )
            }
            guard generation == sessionGeneration, serial == reportAdminLoadSerial else { return }
            let sorted = items.sortedForReportList()
            if reportAdminList != sorted { reportAdminList = sorted }
            if !reportAdminLoaded { reportAdminLoaded = true }
            if reportAdminFailed { reportAdminFailed = false }
            // 펼쳐 둔 행이 목록에서 사라졌으면 접는다(없는 행에 메모 초안이 매달려 있으면 안 된다).
            if let expanded = expandedReportID, !sorted.contains(where: { $0.id == expanded }) {
                expandedReportID = nil
                reportNoteDraft = ""
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration, serial == reportAdminLoadSerial else { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 서버 배포 전(브루가 db push 보다 앞선 창): 실패가 아니라 '아직 표가 없다'. 빈 목록으로 조용히 접는다 —
                // 제보 목록이 세운 관례 그대로(빨간 화면은 사용자가 고칠 수 있는 일에만 쓴다).
                if !reportAdminLoaded { reportAdminLoaded = true }
            } else if !reportAdminFailed {
                reportAdminFailed = true
            }
            return
        }
        if reportAdminLoading { reportAdminLoading = false }
        await performRefreshReportOpenCount(generation: generation)
    }

    /// 미해결 신고 건수만 다시 받는다(Task 발사). **폴링에 걸지 마라** — 팝오버를 여는 순간처럼 사람이 화면을 보는 시점에만.
    /// 비운영자는 묻지 않는다(40명이 팝오버를 열 때마다 0 을 받으러 가지 않게 — `refreshFeedbackOpenCount` 와 같은 가드).
    func refreshReportOpenCount() {
        guard session != nil, ultraUnlimited else { return }
        let generation = sessionGeneration
        Task { @MainActor in await performRefreshReportOpenCount(generation: generation) }
    }

    /// 건수 조회 본체. 실패는 **조용히** — 배지·점 하나 때문에 화면에 실패 문구를 띄우지 않는다(스키마 부재 포함).
    ///
    /// 반영 직전에 **관리자 깃발을 다시 본다**: 묻는 사이에 깃발이 내려갔으면(권한 회수·계정 전환 직후) 늦게 온 건수가
    /// 메뉴바 점을 도로 켜면 안 된다. 깃발 관찰자가 이미 0 으로 내렸고, 그 뒤를 옛 응답이 덮는 순서를 막는다.
    func performRefreshReportOpenCount(generation: Int) async {
        guard session != nil else { return }
        do {
            let count = try await withSessionRetry { activeSession in
                try await service.fetchReportOpenCount(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration, ultraUnlimited else { return }
            let clamped = max(0, count)
            if reportOpenCount != clamped { reportOpenCount = clamped }
        } catch {
            // 취소·스키마 부재·5xx 전부 조용히. 다음에 팝오버를 열면 다시 묻는다.
        }
    }

    // MARK: 처리(운영자)

    /// 펼친 행의 [미해결]/[처리 중]/[조치함]/[무시]. **메모 칸의 글을 함께 저장한다** — 신고 메모는 신고자에게 가는 답장이
    /// 아니라 운영자 자신의 기록이라(서버가 칸 단위로 신고자에게 막는다), 제보처럼 "상태와 답장을 따로" 둘 이유가 없다.
    /// 행을 펼칠 때 저장된 메모가 칸에 실리므로 칸에 보이는 글이 곧 저장될 글이다(비우면 지운다).
    ///
    /// 펼친 행에서만 통한다 — 메모 초안은 한 칸뿐이고 그 칸은 언제나 펼친 행의 것이다.
    func applyReportStatus(id: String, status: ContentReportStatus) {
        guard session != nil, canUpdateReport, expandedReportID == id,
              reportAdminList.contains(where: { $0.id == id }) else { return }
        let note = ReportAdminNote.outgoing(reportNoteDraft)
        Task { @MainActor in await performUpdateReport(id: id, status: status, note: note) }
    }

    /// `report_admin_update` 왕복. 파일 머리 ④ — **낙관 반영이 없다**: 목록을 건드리는 자리는 성공 갈래 하나뿐이다.
    func performUpdateReport(id: String, status: ContentReportStatus, note: String) async {
        guard session != nil, reportUpdatingID == nil else { return }
        let generation = sessionGeneration
        reportUpdatingID = id
        do {
            let handledAt = try await withSessionRetry { activeSession in
                try await service.updateReportAdmin(
                    accessToken: activeSession.accessToken,
                    id: id,
                    status: status,
                    note: note
                )
            }
            guard generation == sessionGeneration else { return }
            if reportUpdatingID == id { reportUpdatingID = nil }
            // 그 사이에 행이 사라졌으면(목록을 새로 받았으면) 아무것도 되살리지 않는다.
            if let index = reportAdminList.firstIndex(where: { $0.id == id }) {
                reportAdminList[index].status = status
                reportAdminList[index].adminNote = note.isEmpty ? nil : note
                // 서버 시각을 못 읽었으면 이 맥의 시계로 근사한다 — 바로 아래 재조회가 서버 값으로 덮는다.
                reportAdminList[index].handledAt = handledAt ?? clock()
            }
            if expandedReportID == id { reportNoteDraft = note }
            reportAdminNotice = ReportAdminText.saved(status)
            // 성공 때만 재조회한다(정렬·미해결 건수·메뉴바 점을 서버 사실에 맞춘다 — 제보 상태 변경과 같은 규약).
            await performLoadReportAdmin()
        } catch {
            if case .cancelled = classifyAuthError(error) {
                if generation == sessionGeneration, reportUpdatingID == id { reportUpdatingID = nil }
                return
            }
            guard generation == sessionGeneration else { return }
            if reportUpdatingID == id { reportUpdatingID = nil }
            // 목록은 **한 글자도** 안 바뀐다. 메모 초안도 그대로 둔다(다시 누르면 같은 글이 간다).
            reportAdminNotice = ReportAdminFailure.notice(for: error)
        }
    }

    // MARK: 계정 경계

    /// 로그아웃·강제 로그아웃(`clearPersistedSession`)이 부른다. 신고 목록은 남이 쓴 글이고, 미해결 건수는 메뉴바 점을 켠다 —
    /// 다음 계정에 한 줄도 물려주지 않는다. 떠 있던 조회는 세대 가드가 막고, 순번도 올려 옛 목록 응답을 확실히 버린다.
    func resetReportAdminState() {
        feedbackInboxShowsReports = false
        reportAdminList = []
        reportAdminLoaded = false
        reportAdminLoading = false
        reportAdminFailed = false
        reportAdminNotice = nil
        reportFilter = nil
        expandedReportID = nil
        reportNoteDraft = ""
        reportUpdatingID = nil
        reportOpenCount = 0
        reportAdminLoadSerial += 1
    }
}

// MARK: - 정렬

extension Array where Element == ContentReportAdminItem {
    /// 서버 정렬을 신뢰하지 않고 다시 세운다: **미해결 먼저** → 최신순(created_at 내림차순, 모르면 뒤) → id.
    /// 처리 직후(재조회 전)에는 클라 목록이 서버 정렬과 이미 달라져 있다 — 방금 [조치함]으로 닫은 신고가 미해결 사이에 남지 않게.
    func sortedForReportList() -> [ContentReportAdminItem] {
        sorted { lhs, rhs in
            if lhs.status.isOpen != rhs.status.isOpen { return lhs.status.isOpen }
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?) where l != r: return l > r
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - 문구

/// 신고 칸의 고정 문구. 한 곳에 모으는 이유는 제보(`FeedbackText`)와 같다 — 테스트가 **문구 자체**를 되묻고,
/// 서버 예외 이름(REPORT_*)이 화면으로 새지 않는지를 이 표 하나로 본다.
enum ReportAdminText {
    /// [제보] / [신고] 칩의 글자.
    static let feedbackSegment = "제보"
    static let reportSegment = "신고"
    static let filterAll = "전체"
    static let loading = "불러오는 중…"
    static let failed = "신고를 불러오지 못했어요"
    static let empty = "받은 신고가 없어요"
    /// 진짜 빈 목록의 보조 한 줄. 24시간 약속을 운영자 자신에게 상기시키는 자리다.
    static let emptyHint = "폰에서 신고가 들어오면 여기에 쌓여요 — 24시간 안에 확인해 주세요"
    static func filterEmpty(_ status: ContentReportStatus) -> String { "\(status.reportLabel) 신고가 없어요" }
    /// 칩 이름(`filterAll`)을 **그대로** 부른다 — 화면에 없는 버튼을 말하면 안 된다.
    static let filterEmptyHint = "위 [\(filterAll)]를 누르면 나머지가 보여요"
    /// 신고된 메시지 원문 판의 이름표.
    static let quoteTitle = "신고된 메시지"
    /// 처리 메모 판의 이름표.
    static let noteTitle = "처리 메모"
    static let notePlaceholder = "처리 메모(500자까지)"
    /// 펼친 행 맨 아래 안내. 두 가지를 말한다: 버튼이 메모를 **함께** 저장한다 · 메모는 신고자에게 **안 보인다**.
    static let noteHint = "상태 버튼이 메모를 함께 저장해요 — 메모는 신고한 사람에게 안 보여요"
    static let updating = "저장하는 중…"
    /// 사람 신고(메시지 없음)를 말하는 작은 글자.
    static let personReport = "사람 신고"
    static func handledAge(_ text: String) -> String { "처리 \(text)" }
    /// 처리 성공 한 줄. 어느 상태로 갔는지를 말한다 — 버튼을 눌렀다는 사실이 아니라 **저장된 결과**가 증거다.
    static func saved(_ status: ContentReportStatus) -> String { "'\(status.reportLabel)'(으)로 저장했어요" }
    static let failedUpdate = "처리를 저장하지 못했어요 — 잠시 뒤 다시 눌러 주세요"
    static let forbidden = "권한이 없어요"
    static let badStatus = "이 앱이 모르는 상태예요 — 앱을 업데이트해 주세요"
    static let noteTooLong = "메모가 너무 길어요 — 500자까지 저장할 수 있어요"
    static let notFound = "그 신고를 찾지 못했어요 — 목록을 다시 열어 주세요"
    static let schemaMissing = "신고 처리는 곧 열려요 — 쓰신 메모는 그대로 둘게요"

    /// 이 안내가 좋은 소식인가(색이 여기서 갈린다 — 제보 `FeedbackText.isSuccessNotice` 와 같은 규약).
    static func isSuccessNotice(_ notice: String) -> Bool {
        ContentReportStatus.reportTransitions.contains { saved($0) == notice }
    }
}

/// 처리 경로의 실패를 **사용자 말투**로 옮긴다(`FeedbackFailure` 와 같은 이유 — 공용 매퍼는 서버 원문을 그대로 돌려준다).
/// 아는 코드만 사람 말로 바꾸고, 모르는 코드는 원문을 버린다.
enum ReportAdminFailure {
    static func notice(for error: Error) -> String {
        guard let serviceError = error as? SupabaseWorkServiceError else { return ReportAdminText.failedUpdate }
        switch serviceError {
        case .authMessage(let message):
            let upper = message.uppercased()
            if upper.contains("REPORT_FORBIDDEN") { return ReportAdminText.forbidden }
            if upper.contains("REPORT_BAD_STATUS") { return ReportAdminText.badStatus }
            if upper.contains("REPORT_NOTE_TOO_LONG") { return ReportAdminText.noteTooLong }
            if upper.contains("REPORT_NOT_FOUND") { return ReportAdminText.notFound }
            return ReportAdminText.failedUpdate
        case .databaseSchemaMissing:
            return ReportAdminText.schemaMissing
        default:
            return ReportAdminText.failedUpdate
        }
    }
}
