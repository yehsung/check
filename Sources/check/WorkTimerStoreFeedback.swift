import AppKit
import Foundation

// MARK: - 제보(버그·요청) (v0.2.48, 답장 v0.3.14) — 창 열고 닫기 · 보내기 · 목록 · 상태 변경 · 답장
//
// 사용자 요청(2026-09-10): "사람들이 버그 제보 가능하게 해주고, 제보 받은 내용은 관리자인 내가 앱 내에서
// 볼 수 있게끔 하자. 버그 또는 요청사항 보낼 수 있게 하자."
//
// ── 이 파일이 지키는 세 가지 ──
//
// ① **판정은 전부 서버다.** `store.ultraUnlimited` 는 서버(`profiles.role = 'admin'`)가 말해 준 사실의
//    미러이고 **표시 전용 깃발**이다. 여기서 그 값으로 하는 일은 "받은 제보 탭을 그릴까 말까" 하나뿐이고,
//    실제 접근 차단은 `feedback_list` / `set_feedback_status` 안의 RLS·권한 검사가 한다. 깃발을 조작해도
//    남의 제보는 한 줄도 오지 않는다 — 그 성질이 이 화면을 안전하게 만든다.
//    (20260820040000_ultra_unlimited_flag.sql 은 이 깃발이 **판정**에 쓰이면 배포를 막는 단언을 걸어 뒀다.
//     '무엇을 보여 줄까'는 판정이 아니다. 그 선을 넘지 마라.)
//
// ② **폴링을 새로 만들지 않는다.** 목록은 창을 열 때 · [새로고침] · 상태 변경 성공에만 받는다.
//    무료 플랜에 상시 요청을 하나 더 얹지 않는다(미니게임 순위와 같은 규약).
//
// ③ **제보 본문은 사용자가 쓴 글이다.** 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라. 실패 문구도
//    본문이나 서버 예외 원문을 담지 않는다(FeedbackFailure 참고).
//
// 비동기 관용구는 `performLoadMiniGameBoard` 를 그대로 따른다: 세션 가드 → 세대 캡처 → `withSessionRetry`
// → 세대 가드. 세대 가드가 없으면 로그아웃 뒤 도착한 응답이 다음 계정 화면에 남의 제보를 그린다.

extension WorkTimerStore {
    /// 한 번에 받아 올 제보 수. 관리자 화면이 스크롤 하나로 끝나는 크기이면서, 무료 플랜에서 한 왕복에
    /// 실려도 무거워지지 않는 수. 페이지네이션은 **일부러 없다** — 26명 규모에서 두 번째 페이지가 생기려면
    /// 100건이 쌓여야 하고, 그전에 상태 필터가 목록을 갈라 준다.
    static let feedbackListLimit = 100

    // MARK: 파생값(뷰가 읽는 것)

    /// 받은 제보 탭을 지금 그리는가. **두 값의 곱이다** — 관리자 깃발이 내려간 순간(로그아웃·계정 전환)
    /// 낡은 탭 선택이 남아 탭이 잠깐 드러나는 일을 구조적으로 막는다.
    /// 다시 말하지만 이건 **발견성**이고, 차단은 서버가 한다.
    var showsFeedbackInbox: Bool { ultraUnlimited && feedbackShowsInbox }

    /// 지금 화면에 그릴 제보들. 필터를 적용하고 **정렬을 다시 세운다**(서버 정렬을 신뢰하지 않는 규약).
    var visibleFeedback: [FeedbackReport] {
        let filtered = feedbackFilter.map { status in feedbackList.filter { $0.status == status } } ?? feedbackList
        return filtered.sortedForFeedbackList()
    }

    /// 보내기 탭에서 내가 보낸 것만(비관리자에게는 목록 전체가 이미 내 것이지만, 관리자에게는 아니다).
    /// 로그인 전이면 빈 목록이다 — userID 가 nil 일 때 `$0.userID == nil` 인 행을 내 것으로 보면
    /// 서버가 익명화한 남의 제보가 '내가 보낸 제보'로 둔갑한다.
    var myFeedback: [FeedbackReport] {
        guard let me = session?.userID else { return [] }
        return feedbackList.filter { $0.userID == me }.sortedForFeedbackList()
    }

    /// 지금 [보내기]를 누를 수 있는가. 서버 경계(1~1000자)와 **같은 판정**이고, 전송 중에는 잠긴다.
    var canSendFeedback: Bool {
        !isSendingFeedback && FeedbackComposer.isSendable(feedbackDraft)
    }

    /// 지금 [답장 보내기]를 누를 수 있는가(v0.3.14).
    ///
    /// **펼친 행이 기준이다.** 메모 초안은 한 칸뿐이고 그 칸은 언제나 펼친 행의 것이므로
    /// (`toggleFeedbackExpansion` 이 그 행의 답장을 실어 준다), 펼친 행이 없으면 이 초안은 아무에게도
    /// 속하지 않는다 — 그때 보내기를 열어 두면 방금 접은 행에 엉뚱한 답장이 붙는다.
    ///
    /// 나머지 두 갈래는 `FeedbackComposer.isSendableReply` 가 판정한다(비었나 · 저장된 답장과 같나).
    var canSendFeedbackReply: Bool {
        guard !feedbackReplySending, let id = expandedFeedbackID else { return false }
        let saved = feedbackList.first { $0.id == id }?.adminNote
        return FeedbackComposer.isSendableReply(draft: feedbackNoteDraft, savedNote: saved)
    }

    /// "앱 0.2.48 (58) · macOS 15.6 · 연결 상태 정보가 함께 전송돼요" — 자동으로 실리는 것을 밝히는 한 줄.
    ///
    /// **연결 상태가 이 문장에 들어 있는 이유**(2026-09-10): 그날부터 제보 본문 뒤에 진단 두 줄이 자동으로
    /// 붙는다(아래 `feedbackDiagnosticsLines`). 몰래 보내지 않는다는 약속이 이 문장이므로, 실어 보내는 것이
    /// 늘면 **문장도 같이 늘어야 한다.** 붙일 진단이 하나도 없으면 말하지도 않는다 — 둘이 같은 값에서 나온다.
    ///
    /// 다만 "자리가 모자라 진단이 빠지는" 경우(사용자 글이 940자 근처)까지 문장이 따라가지는 않는다.
    /// 이 줄은 *무엇이 갈 수 있는가*를 밝히는 약속이고, 글자 수에 따라 타이핑 중에 문구가 바뀌면
    /// 사람은 그 변화를 자기 글에 대한 경고로 읽는다(그리고 그 조합은 극단이다).
    var feedbackAutoAttachNotice: String {
        let report = appVersionProvider()
        return FeedbackText.autoAttachNotice(
            appVersion: report?.version ?? "",
            build: report?.build,
            osVersion: osVersionProvider(),
            includesDiagnostics: !feedbackDiagnosticsLines.isEmpty
        )
    }

    /// 제보에 자동으로 실을 진단 줄들(초인종 · 근무 틱). **설정 창에 있던 그 두 줄이다** —
    /// 2026-09-10 사용자 지적("이건 뭐야? 왜 넣은 거야?")으로 화면에서 걷어내고 이 경로로 옮겼다.
    ///
    /// 값이 없는 줄은 **아예 빠진다**(`FeedbackDiagnostics.line` 이 nil 을 돌려준다). 지금의 두 제공자는
    /// 빈 문자열을 낼 일이 없지만, 언젠가 하나가 조용히 비면 본문 뒤에 "초인종" 만 덩그러니 붙은
    /// 의미 없는 줄이 남는다 — 그건 운영자에게도 사용자에게도 소음이다.
    ///
    /// ★ `.idle(.disabled)`(전송자 없음)는 '값이 없는 것'이 **아니다.** 그게 바로 "찌르기가 안 와요"의
    ///   답이라서, 이 경로가 생긴 이유의 절반이 그 상태를 실어 나르는 것이다. 침묵으로 접지 마라.
    ///
    /// 두 줄이 각각 무엇을 가르는지(설정 창에서 옮겨 온 근거 그대로):
    ///  · **초인종**(리얼타임) — "찌르기가 안 와요" 신고에서 소켓/따라잡기/토큰 중 어디인지. 이 값이
    ///    없으면 `.idle(.disabled)`(킬스위치 off 또는 조립 실패)가 **완전한 침묵**이 된다: REST 는 멀쩡하고
    ///    `syncMessage` 는 "동기화됨"을 유지하므로 앱 어디에도 신호가 남지 않는다.
    ///  · **근무 틱**(work_tick RPC) — "팀 화면이 늦어요/안 바뀌어요" 신고에서 통합 RPC 를 쓰는지, 개별
    ///    REST 로 폴백해 있는지(사유·언제까지), 시계차가 얼마인지. `syncMessage` 에는 폴백 사유를 싣지
    ///    않으므로 이 줄이 **유일한 표면**이다.
    var feedbackDiagnosticsLines: [String] {
        [
            FeedbackDiagnostics.line(label: FeedbackText.realtimeDiagnosticsLabel, value: realtimeDiagnosticsLine),
            FeedbackDiagnostics.line(label: FeedbackText.workTickDiagnosticsLabel, value: workTickDiagnosticsLine)
        ].compactMap { $0 }
    }

    // MARK: 패널 열고 닫기

    /// **이 기능의 공개 진입점.** 팝오버 레일의 제보 버튼이 부르는 단 하나의 문이다. 패널을 열고 목록을 받는다.
    ///
    /// ★ **팝오버를 닫지 않는다**(v0.2.50 에서 바뀐 지점). 창이던 시절에는 여기 `dismissMenuPopover()` 가
    ///   있었다 — 팝오버 위에 창을 띄우는 동작이었으니까. 지금은 팝오버 **안에서 화면이 바뀌는 것**이라,
    ///   닫으면 방금 연 화면이 그 자리에서 사라진다. 미니게임·설정은 여전히 별도 창이므로 그쪽 호출은 그대로다.
    ///
    /// 다른 하위 패널과 **상호 배타**다. 순서가 뜻이다: `closeUltraPanel()`/`closeMessagePanel()` 은 origin 이
    /// .poke 면 콕찌르기 목록을 되살리므로, 그 목록을 내리는 `closePokePanel()` 이 뒤에 온다.
    ///
    /// **목록을 받는 자리가 곧 이 문이다.** [새로고침] 버튼은 v0.2.50 에 없앴다(사용자 지시:
    /// "제보창에서 새로고침 버튼 없어도 될 듯"). 최신을 보는 길은 그래서 셋이다 —
    ///   ① [뒤로]로 나갔다가 레일의 [제보]를 다시 누르면 이 문을 다시 지나 목록을 새로 받는다.
    ///   ② 제보를 보내면 성공 직후 `loadFeedback()` 이 목록을 다시 받는다.
    ///   ③ (관리자) 상태를 바꾸면 성공 직후 같은 자리에서 다시 받는다.
    /// 즉 버튼이 하던 일은 **화면을 여는 동작 자체**가 물려받았다. 폴링은 여전히 없다(머리 주석).
    func openFeedbackPanel() {
        isFeedbackPanelVisible = true
        isLeaderboardVisible = false
        closeTokenBoard()
        closeUltraPanel()
        closeMessagePanel()
        closePokePanel()
        isInsightsPanelVisible = false
        // 관리자 깃발이 아직 안 왔으면(로그인 직후 지갑 sync 전) 보내기 탭에서 시작한다.
        // 깃발이 도착하면 탭이 나타나고, 사용자가 고르면 그때 넘어간다 — 화면이 저절로 튀지 않는다.
        if !ultraUnlimited, feedbackShowsInbox { feedbackShowsInbox = false }
        // 첫 프레임부터 빈 목록 자리에 "불러오는 중…"이 뜨게 한다(미니게임 보드와 같은 규약 —
        // 본문 자리에 동기화 문구를 쓰지 않는다).
        //
        // **세션이 있을 때만** 세운다. 로그인 전이면 아래 `loadFeedback()` 이 세션 가드에서 조용히 되돌아가는데,
        // 그 경우 이 깃발을 세워 두면 아무도 내려 주지 않아 화면이 영영 "불러오는 중…"에 갇힌다.
        if session != nil, !feedbackLoaded { feedbackLoading = true }
        loadFeedback()
    }

    /// 레일 버튼을 다시 눌렀을 때(열려 있으면 닫고, 아니면 연다). 레일 칸은 토글로 읽히기 때문에 남긴다.
    func toggleFeedbackPanel() {
        if isFeedbackPanelVisible {
            closeFeedbackPanel()
            return
        }
        openFeedbackPanel()
    }

    /// 제보 패널을 닫는 **유일한** 경로(멱등). [뒤로]와 다른 패널을 여는 다섯 자리가 전부 여기를 지난다.
    ///
    /// **초안은 지우지 않는다** — 길게 쓴 글이 화면을 잘못 바꿨다고 사라지면 그 사용자는 두 번 다시
    /// 제보하지 않는다. 초안이 사라지는 자리는 전송 성공 하나뿐이다.
    ///
    /// 돌아갈 곳은 언제나 **홈(팀 목록)** 이다 — 들어오는 문이 레일 한 곳뿐이라 origin 을 물을 이유가 없다.
    func closeFeedbackPanel() {
        guard isFeedbackPanelVisible else { return }
        isFeedbackPanelVisible = false
        // 펼쳐 둔 행과 메모 초안은 접는다 — 다시 열었을 때 앞서 보던 제보가 펼쳐진 채로 서 있으면
        // 그 메모가 어느 제보의 것인지 화면만으로는 알 수 없다(탭 전환이 같은 이유로 같은 일을 한다).
        expandedFeedbackID = nil
        feedbackNoteDraft = ""
    }

    // MARK: 화면 상태

    /// 보내기 탭의 종류 선택([버그] / [요청]).
    func selectFeedbackKind(_ kind: FeedbackKind) {
        guard feedbackKind != kind else { return }
        feedbackKind = kind
    }

    /// 탭 전환. 관리자가 아니면 받은 제보로 갈 수 없다(뷰가 탭을 안 그리지만, 문도 잠가 둔다 —
    /// 게이트가 한 겹뿐이면 언젠가 다른 경로가 그 겹을 우회한다).
    func selectFeedbackTab(inbox: Bool) {
        let target = inbox && ultraUnlimited
        guard feedbackShowsInbox != target else { return }
        feedbackShowsInbox = target
        // 탭을 옮기면 펼쳐 둔 행과 메모 초안은 접는다 — 다른 목록의 메모가 남아 있으면 엉뚱한 제보에 붙는다.
        expandedFeedbackID = nil
        feedbackNoteDraft = ""
        // 안내 한 줄도 함께 지운다. 두 탭이 같은 칸을 나눠 쓰므로, 안 지우면 받은 제보 탭 아래에
        // "보냈어요. 고마워요!" 가 남아 무엇에 대한 말인지 알 수 없는 문장이 된다.
        feedbackNotice = nil
    }

    /// 상태 필터 칩. nil = 전체. **다시 조회하지 않는다** — 목록은 이미 전부 받아 왔고(전체 조회),
    /// 거르는 일은 순수 계산이다. 칩마다 왕복을 내면 무료 플랜에 필터 수만큼 요청이 곱해진다.
    func selectFeedbackFilter(_ status: FeedbackStatus?) {
        guard feedbackFilter != status else { return }
        feedbackFilter = status
        expandedFeedbackID = nil
        feedbackNoteDraft = ""
    }

    /// 행을 펼치거나 접는다(한 번에 하나). 펼칠 때 그 제보의 기존 메모를 초안으로 실어 준다 —
    /// 빈 칸으로 열면 관리자가 메모를 덮어쓰려다 기존 메모를 지운다.
    func toggleFeedbackExpansion(_ id: String) {
        if expandedFeedbackID == id {
            expandedFeedbackID = nil
            feedbackNoteDraft = ""
            return
        }
        expandedFeedbackID = id
        feedbackNoteDraft = feedbackList.first { $0.id == id }?.adminNote ?? ""
    }

    // MARK: 목록

    /// 목록을 로드한다(Task 발사). **패널 열기 · 전송 성공 · 상태 변경 성공에서만 부른다.**
    /// [새로고침] 버튼은 없다(위 `openFeedbackPanel` 주석의 세 경로가 그 자리를 물려받았다).
    func loadFeedback() {
        Task { @MainActor in await performLoadFeedback() }
    }

    /// `feedback_list` 를 받아 반영한다. 관리자면 **미해결 건수**도 같은 자리에서 함께 받는다
    /// (독립 실패 — 건수를 못 받아도 목록은 그린다. 미니게임의 '어제 1등'과 같은 규약).
    ///
    /// 필터는 **서버로 보내지 않는다**(p_status = nil, 전체). 이유는 `selectFeedbackFilter` 주석과 같다 —
    /// 거르기는 순수 계산이고, 전체를 한 번 받아 두면 칩을 눌러도 왕복이 없다.
    func performLoadFeedback() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        if !feedbackLoading { feedbackLoading = true }
        if feedbackFailed { feedbackFailed = false }
        defer { if generation == sessionGeneration, feedbackLoading { feedbackLoading = false } }
        do {
            let reports = try await withSessionRetry { activeSession in
                try await service.fetchFeedbackList(
                    accessToken: activeSession.accessToken,
                    status: nil,
                    limit: Self.feedbackListLimit
                )
            }
            guard generation == sessionGeneration else { return }
            let sorted = reports.sortedForFeedbackList()
            if feedbackList != sorted { feedbackList = sorted }
            if !feedbackLoaded { feedbackLoaded = true }
            if feedbackFailed { feedbackFailed = false }
            // 펼쳐 둔 행이 목록에서 사라졌으면(다른 관리자가 지웠거나 필터 밖으로 나갔으면) 접는다.
            if let expanded = expandedFeedbackID, !sorted.contains(where: { $0.id == expanded }) {
                expandedFeedbackID = nil
                feedbackNoteDraft = ""
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 마이그레이션 전 창(브루 배포가 db push 보다 앞선 경우): 실패가 아니라 '아직 표가 없다'.
                // 빈 목록으로 조용히 접는다 — 실패 문구와 [다시 시도] 는 **사용자가 고칠 수 있는 일**에만 쓴다.
                // (미니게임 보드가 세운 관례. 여기서 실패로 칠하면 서버 배포를 기다리는 며칠 동안
                //  모두가 빨간 화면을 보고 '앱이 고장 났다'고 제보한다 — 제보 화면에서.)
                if !feedbackLoaded { feedbackLoaded = true }
            } else if !feedbackFailed {
                feedbackFailed = true
            }
            return
        }
        // 목록이 반영된 시점에 로딩 깃발을 내린다 — 아래 건수 조회가 끝날 때까지 붙들면
        // 화면은 이미 목록을 그리고 있는데 "불러오는 중…" 상태가 남는다(아래 `defer` 는 이른 반환의 안전망이다).
        if feedbackLoading { feedbackLoading = false }
        // 미해결 건수(관리자 배지). 목록이 이미 반영된 뒤라 여기서 실패해도 화면은 멀쩡하다.
        guard ultraUnlimited else {
            if feedbackOpenCount != 0 { feedbackOpenCount = 0 }
            return
        }
        await performRefreshFeedbackOpenCount(generation: generation)
    }

    /// 미해결 건수만 다시 받는다(레일 배지용). **폴링에 걸지 마라** — 팝오버를 여는 순간처럼
    /// 사람이 화면을 보는 시점에 많아야 한 번이다.
    func refreshFeedbackOpenCount() {
        guard session != nil, ultraUnlimited else { return }
        let generation = sessionGeneration
        Task { @MainActor in await performRefreshFeedbackOpenCount(generation: generation) }
    }

    /// 건수 조회 본체. 실패는 **조용히** 넘긴다 — 배지 하나 때문에 화면에 실패 문구를 띄우지 않는다.
    /// 스키마 부재(서버 배포 전)도 같은 취급이다.
    func performRefreshFeedbackOpenCount(generation: Int) async {
        guard session != nil else { return }
        do {
            let count = try await withSessionRetry { activeSession in
                try await service.fetchFeedbackOpenCount(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            if feedbackOpenCount != count { feedbackOpenCount = max(0, count) }
        } catch {
            // 취소·스키마 부재·5xx 전부 조용히. 다음에 창을 열면 다시 묻는다.
        }
    }

    // MARK: 보내기

    /// [보내기] 버튼의 액션. 판정은 `canSendFeedback` 하나이고 여기서 다시 세지 않는다.
    func sendFeedback() {
        guard canSendFeedback, session != nil else { return }
        Task { @MainActor in await performSendFeedback() }
    }

    /// `submit_feedback` 왕복. 성공하면 **초안을 비우고** 목록을 다시 받는다(방금 보낸 것이 바로 보이게).
    ///
    /// 초안을 비우는 자리가 여기 하나뿐인 것이 계약이다 — 창을 닫아도, 탭을 옮겨도 글은 남는다.
    func performSendFeedback() async {
        guard session != nil, !isSendingFeedback else { return }
        let body = FeedbackComposer.normalized(feedbackDraft)
        guard FeedbackComposer.isSendable(body) else { return }
        // 진단은 **판정이 끝난 뒤에** 붙인다. 보낼 수 있는가는 사용자가 쓴 글로만 판정해야 한다
        // (canSendFeedback 과 같은 값이어야 버튼이 살아 있는데 서버가 거절하는 조합이 안 생긴다).
        // compose 는 사용자 글을 절대 자르지 않는다 — 자리가 모자라면 진단 쪽이 줄거나 빠진다.
        let sentBody = FeedbackDiagnostics.compose(body: body, lines: feedbackDiagnosticsLines)
        let kind = feedbackKind
        let appVersion = FeedbackText.appVersionField(appVersionProvider())
        let osVersion = osVersionProvider()
        let generation = sessionGeneration
        isSendingFeedback = true
        defer { if generation == sessionGeneration { isSendingFeedback = false } }
        do {
            _ = try await withSessionRetry { activeSession in
                try await service.submitFeedback(
                    accessToken: activeSession.accessToken,
                    kind: kind,
                    body: sentBody,
                    appVersion: appVersion,
                    osVersion: osVersion
                )
            }
            guard generation == sessionGeneration else { return }
            feedbackDraft = ""
            feedbackNotice = FeedbackText.sendSuccess
            await performLoadFeedback()
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            // 초안은 **여기서도 살아남는다**(비우는 자리는 위 성공 갈래 하나뿐이다). 스키마 부재 문구가
            // "쓰신 글은 그대로 둘게요"라고 약속하는 근거가 그 성질이고, 테스트가 그 둘을 함께 못 박는다.
            feedbackNotice = FeedbackFailure.notice(
                for: error,
                fallback: FeedbackText.sendFailed,
                schemaMissing: FeedbackText.sendSchemaMissing
            )
        }
    }

    // MARK: 상태 변경(관리자)

    /// 제보 상태를 바꾼다. **낙관 반영 → 실패 시 원복**(미니게임 공개 토글·토큰 공개 토글과 같은 규약).
    ///
    /// 낙관 반영이 필요한 이유: 왕복이 끝날 때까지 칩이 안 바뀌면 관리자는 버튼을 다시 누르고,
    /// 그 두 번째 요청이 첫 번째와 겹친다. 실패하면 **원래 행을 통째로 되돌린다**(상태만 되돌리면
    /// 함께 저장하려던 메모가 화면에 남아 저장된 것처럼 보인다).
    func changeFeedbackStatus(id: String, to status: FeedbackStatus, note: String?) {
        guard session != nil, let index = feedbackList.firstIndex(where: { $0.id == id }) else { return }
        let previous = feedbackList[index]
        feedbackList[index].status = status
        if let note { feedbackList[index].adminNote = note }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.setFeedbackStatus(
                        accessToken: activeSession.accessToken,
                        id: id,
                        status: status,
                        note: note
                    )
                }
                guard generation == sessionGeneration else { return }
                if feedbackNotice != nil { feedbackNotice = nil }
                // 성공 때만 재조회한다(정렬과 미해결 건수가 서버 사실과 맞게).
                await performLoadFeedback()
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                if let current = feedbackList.firstIndex(where: { $0.id == id }) {
                    feedbackList[current] = previous
                }
                feedbackNotice = FeedbackFailure.notice(for: error, fallback: FeedbackText.statusFailed)
            }
        }
    }

    /// 펼친 행에서 [미해결]/[진행]/[완료]/[보류] 를 눌렀을 때.
    ///
    /// ★ **메모를 같이 보내지 않는다(v0.3.14 계약 변경).** 예전에는 상태 칩이 메모 초안을 함께 실어 날랐고,
    ///   그게 메모가 저장되는 **유일한** 길이었다. 이제 답장은 [답장 보내기]로만 나간다 — 그 둘을 한 번에
    ///   묶으면 (가) 상태만 바꾸려던 클릭이 아직 다 쓰지도 않은 답장을 제보자에게 보내고
    ///   (나) 서버 트리거가 `admin_note_at` 을 찍어 "답장 왔어요" 배너가 오발화한다.
    ///   `nil` 을 보내야 서버가 기존 답장을 건드리지 않는다(빈 문자열은 '메모 삭제'다).
    func applyFeedbackStatusFromEditor(id: String, status: FeedbackStatus) {
        changeFeedbackStatus(id: id, to: status, note: nil)
    }

    // MARK: 답장 보내기(관리자) — v0.3.14

    /// [답장 보내기] 버튼의 액션. 판정은 `canSendFeedbackReply` 하나이고 여기서 다시 세지 않는다
    /// (`sendFeedback` 과 같은 규약).
    func sendFeedbackReply(id: String) {
        guard session != nil, canSendFeedbackReply, expandedFeedbackID == id else { return }
        guard let note = FeedbackComposer.normalizedNote(feedbackNoteDraft) else { return }
        Task { @MainActor in await performSendFeedbackReply(id: id, note: note) }
    }

    /// `reply_feedback` 왕복.
    ///
    /// ★★ **낙관 반영이 없다. 이 화면에서만 그렇고, 그것이 이 기능의 존재 이유다.**
    ///    상태 칩은 낙관 반영을 한다(`changeFeedbackStatus`) — 거기서는 "빨리 보이는 것"이 이득이다.
    ///    여기서는 정반대다: 사용자가 요구한 것이 *"이제 뭐 제대로 입력이 된건지 확인하기가 어려워"* 였고,
    ///    답장이 **가기 전에** 목록에 그려지면 그 화면은 왕복이 실패한 뒤에도 "갔다"고 말한다.
    ///    그러면 이 버튼은 예전의 조용한 메모 칸과 똑같아진다. 그래서 목록을 건드리는 자리는
    ///    **성공 갈래 하나뿐**이고, 실패하면 목록은 **한 글자도 안 바뀐다**.
    ///
    /// 진행은 `feedbackReplySending` 으로 보인다(잠금 + "보내는 중…") — 낙관 반영의 이득이던
    /// "눌렀다는 사실이 즉시 보인다"는 그쪽이 대신 한다.
    ///
    /// **초안은 그대로 둔다.** 보낸 글이 칸에 남아 있어야 방금 보낸 것과 행에 그려진 답장이 같은지
    /// 눈으로 맞춰 볼 수 있다(그리고 같으면 버튼이 저절로 잠긴다 — `isSendableReply`).
    ///
    /// **목록을 다시 받지 않는다.** 답장은 상태도 정렬도 안 건드리고, 서버가 준 시각을 그 자리에서 받았다 —
    /// 무료 플랜에 왕복을 하나 더 얹을 이유가 없다(이 파일 머리 주석 ②).
    func performSendFeedbackReply(id: String, note: String) async {
        guard session != nil, !feedbackReplySending else { return }
        let generation = sessionGeneration
        feedbackReplySending = true
        defer { if generation == sessionGeneration { feedbackReplySending = false } }
        do {
            let repliedAt = try await withSessionRetry { activeSession in
                try await service.replyFeedback(accessToken: activeSession.accessToken, id: id, note: note)
            }
            guard generation == sessionGeneration else { return }
            // 왕복이 끝난 **뒤에** 목록을 건드린다. 그 사이에 행이 사라졌으면(다른 관리자가 지웠거나
            // 목록을 새로 받았으면) 아무것도 안 한다 — 없는 행을 되살리지 않는다.
            guard let index = feedbackList.firstIndex(where: { $0.id == id }) else { return }
            feedbackList[index].adminNote = note
            feedbackList[index].adminNoteAt = repliedAt
            feedbackNotice = FeedbackText.replySent
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            // 스키마 부재를 **따로 말하는 이유**: 이 경로는 상태 변경과 달리 목록이 멀쩡한 채로 실패한다
            // (`feedback_list` 는 이미 배포돼 있고 `reply_feedback` 만 아직 없는 창). 누를 행도 쓴 글도
            // 눈앞에 있으므로 "쓰신 글은 그대로 둘게요"가 가리키는 대상이 분명하다.
            feedbackNotice = FeedbackFailure.notice(
                for: error,
                fallback: FeedbackText.replyFailed,
                schemaMissing: FeedbackText.replySchemaMissing
            )
        }
    }
}

// MARK: - 정렬

extension Array where Element == FeedbackReport {
    /// 서버 정렬을 신뢰하지 않고 다시 세운다: **미해결 먼저** → 최신순(created_at 내림차순, 모르면 뒤) → id.
    ///
    /// 서버도 같은 순서로 주지만, 낙관 반영으로 상태를 바꾼 직후에는 클라 목록이 서버 정렬과 이미 달라진다 —
    /// 그때 재정렬이 없으면 방금 '완료'로 바꾼 제보가 미해결 사이에 남아 있다.
    func sortedForFeedbackList() -> [FeedbackReport] {
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

// MARK: - 실패 문구

/// 제보 경로의 실패를 **사용자 말투**로 옮긴다.
///
/// **`authMessage(for:fallback:)` 를 쓰지 않는 이유가 이 타입의 존재 이유다**: 그 공용 매퍼는
/// `.authMessage(원문)` 을 만나면 서버가 준 문자열을 **그대로** 돌려준다. 제보 경로에서 그건
/// 화면에 `FEEDBACK_RATE_LIMIT` 이 뜬다는 뜻이고, 사용자는 자기가 뭘 잘못했는지 알 수 없다.
/// 여기서는 아는 코드만 사람 말로 바꾸고, **모르는 코드는 원문을 버리고 fallback 을 쓴다** —
/// 우리 내부 어휘가 화면으로 새는 경로를 구조적으로 막는다.
enum FeedbackFailure {
    /// - Parameters:
    ///   - fallback: 우리가 모르는 실패에 쓸 문장(내부 어휘가 새지 않게 원문은 언제나 버린다).
    ///   - schemaMissing: 서버에 아직 표·함수가 없을 때만 쓰는 문장. **nil 이면 fallback 을 쓴다** —
    ///     그 상태를 다르게 말할 이유가 있는 경로(보내기)만 넘긴다. 상태 변경 경로에는 넘기지 않는다:
    ///     스키마가 없으면 목록이 통째로 비어 누를 행 자체가 없다(그 자리에 "쓰신 글은 그대로 둘게요"는
    ///     무슨 글을 말하는지 알 수 없는 문장이 된다).
    static func notice(for error: Error, fallback: String, schemaMissing: String? = nil) -> String {
        guard let serviceError = error as? SupabaseWorkServiceError else { return fallback }
        switch serviceError {
        case .authMessage(let message):
            let upper = message.uppercased()
            if upper.contains("FEEDBACK_RATE_LIMIT") { return FeedbackText.rateLimited }
            if upper.contains("FEEDBACK_FORBIDDEN") { return FeedbackText.forbidden }
            // 답장 경로의 셋(v0.3.14). 셋 다 클라 게이트가 먼저 막으므로 평소에는 닿지 않는다 —
            // 그래도 적어 두는 이유는 **게이트가 새는 날**이다. 여기가 비어 있으면 그날 화면에
            // `FEEDBACK_EMPTY_REPLY` 라는 영문 상수가 뜬다(이 타입이 존재하는 이유가 정확히 그것이다).
            if upper.contains("FEEDBACK_EMPTY_REPLY") { return FeedbackText.replyEmpty }
            if upper.contains("FEEDBACK_NOTE_TOO_LONG") { return FeedbackText.replyTooLong }
            if upper.contains("FEEDBACK_NOT_FOUND") { return FeedbackText.replyNotFound }
            // ★ 원문을 돌려주지 마라. 여기로 오는 것은 우리가 아직 모르는 서버 예외이고,
            //   그 이름은 사용자에게 아무 의미가 없다(그리고 대개 영어다).
            return fallback
        case .rateLimited:
            // HTTP 429(게이트웨이 단위 제한). 뜻이 같으므로 같은 문장을 쓴다.
            return FeedbackText.rateLimited
        case .databaseSchemaMissing:
            // 서버가 아직 배포 전. 사용자에게 '스키마'를 말할 이유가 없고, **"잠시 뒤 다시 시도"도 말하면
            // 안 된다** — 이 상태는 우리가 마이그레이션을 올릴 때까지 며칠 간다(브루 배포가 db push 보다
            // 앞선 창). 그 며칠 동안 사용자는 같은 글을 계속 다시 보내고 매번 같은 문장을 본다.
            return schemaMissing ?? fallback
        default:
            return fallback
        }
    }
}

extension FeedbackText {
    /// 진단 줄의 이름표. **본문에 그대로 나가는 글자**라 사용자도 읽는다 — `realtime` 같은 내부 어휘가
    /// 아니라 이 앱이 화면에서 쓰는 말(초인종)을 쓴다.
    static let realtimeDiagnosticsLabel = "초인종"
    static let workTickDiagnosticsLabel = "근무 틱"
    /// 자동 첨부 안내에서 진단을 부르는 말. 팀원에게 `work_tick` 을 말할 이유가 없다.
    static let diagnosticsTerm = "연결 상태"
    /// 받은 제보(관리자)에서 진단 판 위에 붙는 작은 이름표. 사람이 쓴 문장이 아니라는 사실을 말한다.
    static let diagnosticsBlockTitle = "자동 첨부 · 연결 상태"

    /// 자동 첨부 안내 한 줄. **`autoAttachNotice(appVersion:build:osVersion:)` 의 확장이다** —
    /// `includesDiagnostics: false` 면 그 함수와 **한 글자도 다르지 않은** 문장을 만든다
    /// (V0248FeedbackTests 가 둘을 나란히 세워 못 박는다. 원본은 SupabaseWorkModels.swift 에 있고
    ///  이번 작업의 소유가 아니라 고칠 수 없어서, 사실을 테스트로 묶어 둔다).
    ///
    /// 값이 늘어난 자리는 문장 가운데다: "앱 … · macOS … · 연결 상태 정보가 함께 전송돼요".
    /// 꼬리("정보가 함께 전송돼요")를 건드리지 않는 것이 요점이다 — 그 꼬리가 이 문장의 약속이다.
    static func autoAttachNotice(
        appVersion: String,
        build: Int?,
        osVersion: String,
        includesDiagnostics: Bool
    ) -> String {
        var app = appVersion.isEmpty ? "앱" : "앱 \(appVersion)"
        if let build, build > 0 { app += " (\(build))" }
        var parts = [app, "macOS \(osVersion)"]
        if includesDiagnostics { parts.append(diagnosticsTerm) }
        return parts.joined(separator: " · ") + " 정보가 함께 전송돼요"
    }

    /// 제보에 실어 보낼 앱 버전 문자열("0.2.48 (58)"). 관리자 화면에서 이 한 줄이 재현 조건의 절반이다.
    /// 버전을 못 읽는 개발 빌드에서는 빈 문자열 — **모르면 침묵한다**(AppVersionReport 와 같은 규약).
    static func appVersionField(_ report: AppVersionReport?) -> String {
        guard let report else { return "" }
        return report.build > 0 ? "\(report.version) (\(report.build))" : report.version
    }
}


// MARK: - 진단 자동 첨부 (2026-09-10)

/// 제보 본문 뒤에 붙는 **연결 상태 두 줄**을 만들고, 받은 쪽에서 다시 가르는 순수 함수들.
///
/// **배경**: 이 두 줄은 원래 설정 창 하단의 각주였다. 사용자 지적(2026-09-10, 스크린샷과 함께):
/// "이건 뭐야? 왜 넣은 거야? 빼는 게 맞지 않아?" — 맞다, 자리가 틀렸다. 설정은 팀원 전원이 여는
/// 화면이고 그들에게 `idle(disabled) · 재연결 0회` 는 암호문이다. 정작 볼 사람은 운영자인데,
/// 신고가 오면 "설정 열어서 하단 두 줄 찍어 보내주세요"를 부탁해야 했다. 그래서 지운 게 아니라 옮겼다.
///
/// **왜 본문에 붙이는가**(칼럼을 새로 만들지 않고): 서버 `submit_feedback` 은 `p_app_version` ·
/// `p_os_version` 두 자리만 받는다. 진단 한 벌 때문에 스키마를 넓히는 것은 과하고, 본문 뒤에 구분선과
/// 함께 붙이면 운영자 받은함에서 **그대로 읽힌다**(받은 제보 화면이 이 표식으로 판을 갈라 그린다).
///
/// ★ **철칙: 사용자 글은 한 글자도 자르지 않는다.** 본문 상한 1000자는 서버 제약이라, 진단을 붙였다고
///   글이 잘리거나 전송이 거절되면 그건 진단이 사용자를 방해한 것이다(그 사용자는 두 번 다시 제보하지
///   않는다). 자리가 모자라면 **진단이** 줄고, 그래도 모자라면 진단이 통째로 빠진다.
enum FeedbackDiagnostics {
    /// 본문과 기계가 붙인 줄을 가르는 표식. 받은 제보 화면은 이 줄 **자체를 그리지 않고** 판을 가른다 —
    /// 사람이 쓴 문장과 기계가 붙인 줄이 한 덩어리로 섞이면 둘 다 읽기 나쁘다.
    ///
    /// 사람이 우연히 칠 만한 문자열이 아니어야 한다(그러면 자기 글이 진단 판으로 넘어간다). 그래도
    /// 완전히 막을 수는 없으므로 `split` 은 **마지막** 표식을 기준으로 자른다 — 우리가 붙인 것은 언제나 맨 뒤다.
    static let marker = "— 자동 첨부(연결 상태) —"

    /// 서버 제약과 견줄 때 쓰는 길이. **자소 묶음과 코드포인트 중 큰 쪽**이다.
    ///
    /// 서버 `submit_feedback` 은 `char_length`(코드포인트)로 세고 화면 카운터는 `Character`(자소 묶음)로
    /// 센다 — 이모지가 섞이면 후자가 훨씬 작다. 작은 쪽으로 자리를 재면 진단을 붙인 순간 **사용자 글까지
    /// 함께** 서버에 거절당한다. 여기서만 보수적으로 세는 이유가 그것이다(화면 카운터는 그대로 둔다 —
    /// 거기서 코드포인트를 세면 모든 사람의 숫자가 이상해진다).
    static func measured(_ text: String) -> Int {
        max(text.count, text.unicodeScalars.count)
    }

    /// 진단 한 줄("초인종 idle(disabled) · …"). 값이 비면 **nil** — 빈 줄을 붙이지 않는다.
    /// 이름표만 남은 줄은 운영자에게 아무것도 말해 주지 않으면서 본문 자리만 먹는다.
    static func line(label: String, value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\(label) \(trimmed)"
    }

    /// 본문 뒤에 붙일 덩어리(빈 줄 + 표식 + 줄들). 실을 줄이 하나도 없으면 nil 이다.
    static func attachment(_ lines: [String]) -> String? {
        let kept = keep(lines)
        guard !kept.isEmpty else { return nil }
        return "\n\n" + marker + "\n" + kept.joined(separator: "\n")
    }

    /// 보낼 본문을 만든다. **사용자 글이 우선이고 진단은 남는 자리에만 들어간다.**
    ///
    /// 자리가 모자라면 뒤에서부터 한 줄씩 버리고(초인종을 남긴다 — "찌르기가 안 와요"가 이 경로가 생긴
    /// 이유다), 한 줄도 못 들어가면 진단 없이 사용자 글만 보낸다. 어느 갈래에서도 본문은 그대로다.
    static func compose(body: String, lines: [String], limit: Int = FeedbackComposer.maxBodyLength) -> String {
        let text = FeedbackComposer.normalized(body)
        var kept = keep(lines)
        let room = limit - measured(text)
        while !kept.isEmpty {
            if let attachment = attachment(kept), measured(attachment) <= room {
                return text + attachment
            }
            kept.removeLast()
        }
        return text
    }

    /// 받은 본문을 사람이 쓴 글과 기계가 붙인 줄로 가른다. 표식이 없으면(그날 이전의 제보, 또는 진단이
    /// 자리 부족으로 빠진 제보) 전부가 사용자 글이다 — **없는 것을 지어내지 않는다.**
    static func split(_ body: String) -> FeedbackBodyParts {
        let needle = "\n\n" + marker + "\n"
        guard let range = body.range(of: needle, options: .backwards) else {
            return FeedbackBodyParts(body: body, diagnostics: nil)
        }
        let tail = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // 표식만 있고 뒤가 빈 본문은 우리가 만들지 않는다. 그런 글이 왔다면 사용자가 직접 친 것이므로
        // 손대지 않고 통째로 사용자 글로 둔다(남의 글을 우리 규칙으로 잘라내지 않는다).
        guard !tail.isEmpty else { return FeedbackBodyParts(body: body, diagnostics: nil) }
        return FeedbackBodyParts(body: String(body[..<range.lowerBound]), diagnostics: tail)
    }

    /// 빈 줄을 걷어낸 목록. `line(label:value:)` 을 이미 지나온 값이라도 한 번 더 거른다 —
    /// `compose` 는 스토어를 거치지 않은 배열도 받을 수 있고(테스트·미래의 호출부), 그 한 자리만
    /// 게이트가 없으면 빈 줄이 사용자 글 뒤에 남는다.
    private static func keep(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// 받은 제보 한 건을 화면에 그릴 때의 두 조각. 본문은 **사람이 쓴 글만**이고, 진단은 있을 수도 없을 수도 있다.
struct FeedbackBodyParts: Equatable {
    /// 사용자가 쓴 글. 목록의 2줄 미리보기는 **이것만** 쓴다 — 기계가 붙인 줄이 미리보기를 먹으면
    /// 관리자는 목록에서 제보 내용을 읽을 수 없다.
    let body: String
    /// 기계가 붙인 줄들(표식 제외). 없으면 nil.
    let diagnostics: String?
}
