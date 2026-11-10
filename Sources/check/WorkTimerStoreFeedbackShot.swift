import AppKit
import Foundation
import CheckCore

// MARK: - 제보 화면 캡처 — 붙이기 · 빼기 · 보낸 뒤 올리고 붙이기 · 목록 옆 캡처 · 필요할 때 보기 (11-11)
//
// 대표 결정(#d_x5kYyOPOeLlH): "제보에 화면 캡처 첨부하는것도 괜찮고". 서버 어휘는 전부 `FeedbackShotWire`(CheckCore)에 있다
// (계약 v2 §3 — 서버 목록 11-11).
//
// ── 이 파일이 지키는 것 ──
// ① **글이 먼저 간다.** `submit_feedback`(예전 네 키 그대로)이 제보 id 를 돌려주면, 그 id 폴더에 캡처를 하나씩 올리고
//    (`feedback-shots/<내 uid>/<제보 id>/<새 uuid>.jpg`) 붙인다(`feedback_attach_shot`). 캡처가 하나라도 실패해도 **제보는 보낸
//    것이다** — 글을 다시 보내지 않는다. 글 · 캡처를 모두 비우고 한 줄로 말한다("제보는 보냈어요 · 캡처는 못 붙였어요" 등).
// ② **새 자동 호출은 하나뿐이다**: `feedback_list` 가 성공했고 목록이 비어 있지 않을 때 `feedback_shots` 한 번(모든 제보 id 를 한꺼번에).
//    팝오버 열기 · 폴링 · 앱 시작에는 아무것도 더하지 않는다. 그림은 사람이 누른 자리(받은 제보 펼침 · 칩 · 크게 보기)에서만 받는다.
// ③ **404 · PGRST202(서버 배포 전)는 입구를 숨긴다**(붙이기 줄 · 칩). 영구히 기억하지 않는다 — 패널을 열 때 다시 묻는다.
// ④ 캡처를 얻는 길은 고르기 · 붙여넣기 · 끌어다 놓기뿐이다(이 앱은 화면을 찍지 않는다 — 화면 기록 권한을 묻지 않는다).
// ⑤ 캡처에는 남의 이름·대화가 찍혀 있을 수 있다 — `print`/`Logger` 금지. 안내 문구에 경로를 담지 않는다. 디스크에 쓰지 않는다.

extension WorkTimerStore {
    // MARK: 파생값

    /// 캡처 입구(붙이기 줄 · 칩)를 보이는가. **붙이기 줄 · 전송 · 안내 한 줄이 같은 값을 읽는다**(한쪽만 보면 보이지 않는 캡처가
    /// 나가거나, 보이는데 안 나간다).
    var feedbackShotsShown: Bool { !feedbackShotServerMissing }

    /// 지금 캡처를 붙이거나 뺄 수 있는가(전송 중 · 준비 중에는 잠근다).
    var canEditFeedbackShots: Bool { feedbackShotsShown && !isSendingFeedback && !feedbackShotPreparing }

    /// 한 장 더 붙일 수 있는가(상한 `FeedbackShotRules.maxDraft`).
    var canAddFeedbackShot: Bool { canEditFeedbackShots && feedbackShots.count < FeedbackShotRules.maxDraft }

    /// 이번 전송에 실을 캡처. 입구가 숨었으면 없다(붙여 둔 것이 있어도 — ① 와 같은 판정).
    var feedbackShotsForSend: [FeedbackShotDraft] { feedbackShotsShown ? feedbackShots : [] }

    /// 제보 하나에 붙은 캡처들(목록 뒤 받은 행). 입구가 숨었으면 없다.
    func feedbackShots(forReport id: String) -> [FeedbackShot] {
        guard feedbackShotsShown else { return [] }
        return feedbackShotsByReport[id.lowercased()] ?? []
    }

    /// 캡처 한 장의 칸 상태. **네트워크를 부르지 않는다**(읽기만).
    func feedbackShotCell(for path: String) -> FeedbackShotCell {
        if let image = feedbackShotImages[path] { return .image(image) }
        if feedbackShotLoading.contains(path) { return .loading }
        if let failure = feedbackShotFailures[path] { return .failed(failure) }
        return .idle
    }

    /// 제보 하나의 칸들(붙인 순서).
    func feedbackShotCells(forReport id: String) -> [FeedbackShotCell] {
        feedbackShots(forReport: id).map { feedbackShotCell(for: $0.path) }
    }

    // MARK: 입구(다시 묻기 · 숨기기)

    /// 패널을 열 때 — 앞서 "서버에 없다"고 숨긴 입구를 다시 연다(③). 목록 뒤 `feedback_shots` 가 다시 판정한다.
    func rearmFeedbackShots() {
        if feedbackShotServerMissing { feedbackShotServerMissing = false }
    }

    /// 서버에 캡처 함수·버킷이 없다 — 입구를 숨기고 받은 캡처 행을 내린다. 붙여 둔 캡처는 남는다(보이지 않으니 실리지도 않는다 —
    /// `feedbackShotsForSend`). 다음에 패널을 열면 다시 묻는다.
    func markFeedbackShotsMissing() {
        feedbackShotServerMissing = true
        if !feedbackShotsByReport.isEmpty { feedbackShotsByReport = [:] }
        if feedbackShotViewer != nil { feedbackShotViewer = nil }
    }

    // MARK: 붙이기 · 빼기

    /// [이미지 고르기]로 받은 파일들을 붙인다(남은 자리만큼, 줄이기는 백그라운드).
    func attachFeedbackShots(fromFiles urls: [URL]) {
        guard canAddFeedbackShot, !urls.isEmpty else { return }
        prepareFeedbackShots(urls.map { .file($0) })
    }

    /// [붙여넣기] — 클립보드의 이미지(⌘⌃⇧4 로 찍은 것)나 이미지 파일을 붙인다. 없으면 한 줄로 말한다.
    /// 판은 주입할 수 있다(시험은 자기 판을 쓴다 — 사용자의 클립보드를 건드리지 않는다).
    func attachFeedbackShotFromPasteboard(_ pasteboard: NSPasteboard = .general) {
        guard canEditFeedbackShots else { return }
        guard feedbackShots.count < FeedbackShotRules.maxDraft else {
            feedbackNotice = FeedbackShotText.full
            return
        }
        guard let source = FeedbackShotImage.source(in: pasteboard) else {
            feedbackNotice = FeedbackShotText.pasteEmpty
            return
        }
        prepareFeedbackShots([source])
    }

    /// 끌어다 놓기. 받을 수 있으면 true(놓기 판이 받아들였다는 뜻) — 실제 붙이기는 비동기로 이어진다.
    @discardableResult
    func attachFeedbackShots(fromDropped providers: [NSItemProvider]) -> Bool {
        guard canEditFeedbackShots, !providers.isEmpty else { return false }
        guard feedbackShots.count < FeedbackShotRules.maxDraft else {
            feedbackNotice = FeedbackShotText.full
            return false
        }
        let room = FeedbackShotRules.maxDraft - feedbackShots.count
        let taken = Array(providers.prefix(room))
        feedbackShotPrepareSerial += 1
        let serial = feedbackShotPrepareSerial
        let generation = sessionGeneration
        feedbackShotPreparing = true
        Task { @MainActor in
            var sources: [FeedbackShotImage.Source] = []
            for provider in taken {
                if let source = await FeedbackShotImage.source(from: provider) { sources.append(source) }
            }
            guard generation == sessionGeneration, serial == feedbackShotPrepareSerial else { return }
            guard !sources.isEmpty else {
                feedbackShotPreparing = false
                feedbackNotice = FeedbackShotText.unreadable
                return
            }
            await finishPreparingFeedbackShots(sources, serial: serial, generation: generation)
        }
        return true
    }

    /// [빼기] 한 장.
    func removeFeedbackShot(id: UUID) {
        guard !isSendingFeedback else { return }
        feedbackShots.removeAll { $0.id == id }
        if case .draft? = feedbackShotViewer?.source { feedbackShotViewer = nil }
        clearFeedbackShotAttachNotice()
    }

    private func prepareFeedbackShots(_ sources: [FeedbackShotImage.Source]) {
        feedbackShotPrepareSerial += 1
        let serial = feedbackShotPrepareSerial
        let generation = sessionGeneration
        feedbackShotPreparing = true
        Task { @MainActor in
            await finishPreparingFeedbackShots(sources, serial: serial, generation: generation)
        }
    }

    /// 재료를 하나씩 줄여 붙인다(자리가 남는 만큼). 늦게 온 결과는 버린다(로그아웃 · 그사이 새 준비).
    private func finishPreparingFeedbackShots(_ sources: [FeedbackShotImage.Source], serial: Int, generation: Int) async {
        var problem: String?
        var added = 0
        for source in sources {
            let encoded = await FeedbackShotImage.encode(source)
            guard generation == sessionGeneration, serial == feedbackShotPrepareSerial else { return }
            switch encoded {
            case .jpeg(let data):
                guard feedbackShots.count < FeedbackShotRules.maxDraft else {
                    problem = FeedbackShotText.full
                    continue
                }
                guard let draft = FeedbackShotImage.draft(fromJPEG: data) else {
                    problem = FeedbackShotText.unreadable
                    continue
                }
                feedbackShots.append(draft)
                added += 1
            case .unreadable:
                problem = FeedbackShotText.unreadable
            case .tooLarge:
                problem = FeedbackShotText.tooLarge
            }
        }
        feedbackShotPreparing = false
        if let problem {
            feedbackNotice = problem
        } else if added > 0 {
            clearFeedbackShotAttachNotice()
        }
    }

    /// 붙이기에 관한 안내(클립보드 비었음 · 못 읽음 · 너무 큼 · 가득 참)만 지운다. 다른 안내(보냈어요 등)는 건드리지 않는다.
    private func clearFeedbackShotAttachNotice() {
        guard let notice = feedbackNotice else { return }
        let attachNotices = [FeedbackShotText.pasteEmpty, FeedbackShotText.unreadable, FeedbackShotText.tooLarge, FeedbackShotText.full]
        if attachNotices.contains(notice) { feedbackNotice = nil }
    }

    // MARK: 보낸 뒤(`performSendFeedback` 이 부른다 — 글은 이미 갔다)

    /// 제보 글이 나간 직후: 캡처를 화면에서 내리고(다시 보내지 않는다 — 손에 쥔 사본으로 올린다), 하나씩 올리고 붙인 뒤
    /// 안내 한 줄을 정한다. 제보 id 를 못 읽었으면(응답 모양이 다르다) 캡처만 못 붙인 것으로 말한다.
    func finishFeedbackShotsAfterSubmit(_ shots: [FeedbackShotDraft], returnedID: String?, generation: Int) async {
        let sentIDs = Set(shots.map(\.id))
        feedbackShots.removeAll { sentIDs.contains($0.id) }
        if case .draft? = feedbackShotViewer?.source { feedbackShotViewer = nil }
        guard let reportID = FeedbackShotWire.reportID(from: returnedID), let userID = session?.userID else {
            feedbackNotice = FeedbackShotText.sentShotsFailed
            return
        }
        feedbackNotice = FeedbackShotText.uploading
        var tally = FeedbackShotTally(total: shots.count)
        for shot in shots {
            let step = await uploadAndAttachFeedbackShot(shot, userID: userID, reportID: reportID)
            guard generation == sessionGeneration else { return }
            tally.record(step)
            if step == .missing { markFeedbackShotsMissing() }
            if step.stops { break }
        }
        feedbackNotice = tally.notice
    }

    /// 캡처 한 장: 올리기 → 붙이기. 저장소가 정책으로 거절했으면(403 · 400 RLS) **붙이기에 까닭을 묻는다** — 문이 닫혔는지
    /// (`unsupported_client`) · 상한인지(`too_many`)는 붙이기만 말해 준다(저장소 거절 본문은 다 같다). 그 물음은 실패 때만 나간다.
    private func uploadAndAttachFeedbackShot(_ shot: FeedbackShotDraft, userID: String, reportID: String) async -> FeedbackShotStep {
        // 시도마다 새 이름. 세션 갱신 뒤 다시 도는 한 번은 같은 경로다 — 첫 시도는 만료로 거절돼 아무것도 남기지 않았다.
        let path = FeedbackShotWire.objectPath(userID: userID, reportID: reportID, fileID: feedbackShotFileID())
        var uploadRefused = false
        do {
            try await withSessionRetry { activeSession in
                try await service.uploadFeedbackShot(accessToken: activeSession.accessToken, path: path, jpeg: shot.jpeg)
            }
        } catch PrivateStorageError.alreadyExists {
            // 같은 경로가 이미 있다 = 앞선 시도가 실제로는 올라갔다. 붙이기로 넘어간다.
        } catch PrivateStorageError.forbidden {
            uploadRefused = true
        } catch {
            return FeedbackShotRules.isMissing(error) ? .missing : .failed
        }
        do {
            let outcome = try await withSessionRetry { activeSession in
                try await service.attachFeedbackShot(
                    accessToken: activeSession.accessToken,
                    reportID: reportID,
                    path: path,
                    width: shot.pixelWidth,
                    height: shot.pixelHeight
                )
            }
            switch outcome {
            case .attached: return .attached
            case .doorClosed: return .doorClosed
            case .tooMany(let max): return .tooMany(max)
            case .invalid, .invalidPhoto, .photoMissing, .unauthorized, .unknown:
                return uploadRefused ? .refused : .failed
            }
        } catch {
            if FeedbackShotRules.isMissing(error) { return .missing }
            return uploadRefused ? .refused : .failed
        }
    }

    // MARK: 목록 옆 캡처(`performLoadFeedback` 이 목록을 반영한 뒤 부른다)

    /// 목록이 비어 있지 않으면 **한 번에** 캡처 행을 받는다(②). 404 는 입구를 숨긴다(③). 다른 실패는 조용히 — 칩만 안 보인다.
    func performLoadFeedbackShots(for reports: [FeedbackReport], generation: Int) async {
        guard session != nil, !reports.isEmpty, feedbackShotsShown else { return }
        let ids = reports.map { $0.id.lowercased() }
        do {
            let grouped = try await withSessionRetry { activeSession in
                try await service.fetchFeedbackShots(accessToken: activeSession.accessToken, reportIDs: ids)
            }
            guard generation == sessionGeneration else { return }
            if feedbackShotsByReport != grouped { feedbackShotsByReport = grouped }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            if FeedbackShotRules.isMissing(error) { markFeedbackShotsMissing() }
        }
    }

    // MARK: 보기(필요할 때만)

    /// 받은 제보 행을 펼쳤을 때 — 그 제보의 캡처를 받는다.
    func loadFeedbackShotImages(forReport id: String) {
        for shot in feedbackShots(forReport: id) { loadFeedbackShotImage(path: shot.path) }
    }

    /// 캡처 한 장을 받아 둔다(서명 URL). 이미 있거나 받는 중이면 아무것도 안 한다. 일시 실패는 다시 부르면 다시 묻고,
    /// **지워진 것은 다시 묻지 않는다**(30일 정리 · 계정 삭제 — 다시 물어도 없다).
    func loadFeedbackShotImage(path: String) {
        guard session != nil, PrivateStorage.isSafeObjectPath(path) else { return }
        guard feedbackShotImages[path] == nil, !feedbackShotLoading.contains(path) else { return }
        guard feedbackShotFailures[path] != .missing else { return }
        feedbackShotLoading.insert(path)
        feedbackShotFailures[path] = nil
        let generation = sessionGeneration
        Task { @MainActor in
            defer { if generation == sessionGeneration { feedbackShotLoading.remove(path) } }
            do {
                let data = try await withSessionRetry { activeSession in
                    try await service.downloadFeedbackShot(accessToken: activeSession.accessToken, path: path)
                }
                guard generation == sessionGeneration else { return }
                guard let image = NSImage(data: data) else {
                    feedbackShotFailures[path] = .failed
                    return
                }
                if feedbackShotImages.count >= FeedbackShotRules.cacheLimit { feedbackShotImages.removeAll() }
                feedbackShotImages[path] = image
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                if case PrivateStorageError.objectMissing = error {
                    feedbackShotFailures[path] = .missing
                } else {
                    feedbackShotFailures[path] = .failed
                }
            }
        }
    }

    /// 보낸 제보의 캡처를 크게 본다(칩 · 썸네일을 눌렀을 때). 받아 두지 않았으면 받는다.
    func openFeedbackShotViewer(reportID: String, index: Int = 0) {
        let shots = feedbackShots(forReport: reportID)
        guard !shots.isEmpty else { return }
        let clamped = min(max(0, index), shots.count - 1)
        feedbackShotViewer = FeedbackShotViewerState(source: .report(reportID.lowercased()), index: clamped)
        loadFeedbackShotImages(forReport: reportID)
    }

    /// 붙여 둔(아직 안 보낸) 캡처를 크게 본다 — 보내기 전에 남의 이름·대화가 찍혔는지 확인하는 길.
    func openFeedbackShotDraftViewer(index: Int) {
        guard feedbackShots.indices.contains(index) else { return }
        feedbackShotViewer = FeedbackShotViewerState(source: .draft, index: index)
    }

    /// 크게 보기에서 앞뒤로.
    func stepFeedbackShotViewer(by delta: Int) {
        guard var viewer = feedbackShotViewer else { return }
        let count = feedbackShotViewerCount
        guard count > 0 else {
            feedbackShotViewer = nil
            return
        }
        viewer.index = (viewer.index + delta % count + count) % count
        feedbackShotViewer = viewer
        if case .report(let id) = viewer.source { loadFeedbackShotImages(forReport: id) }
    }

    func closeFeedbackShotViewer() {
        if feedbackShotViewer != nil { feedbackShotViewer = nil }
    }

    /// 크게 보기가 넘길 수 있는 장 수.
    var feedbackShotViewerCount: Int {
        switch feedbackShotViewer?.source {
        case .draft?: return feedbackShots.count
        case .report(let id)?: return feedbackShots(forReport: id).count
        case nil: return 0
        }
    }

    /// 크게 보기가 지금 그릴 칸(뷰는 이 값만 읽는다).
    var feedbackShotViewerCell: FeedbackShotCell? {
        guard let viewer = feedbackShotViewer else { return nil }
        switch viewer.source {
        case .draft:
            guard feedbackShots.indices.contains(viewer.index) else { return nil }
            return .image(feedbackShots[viewer.index].preview)
        case .report(let id):
            let shots = feedbackShots(forReport: id)
            guard shots.indices.contains(viewer.index) else { return nil }
            return feedbackShotCell(for: shots[viewer.index].path)
        }
    }

    // MARK: 로그아웃

    /// 캡처 상태를 전부 비운다(로그아웃 블록이 부른다).
    func resetFeedbackShotState() {
        feedbackShotPrepareSerial += 1
        feedbackShots = []
        feedbackShotPreparing = false
        feedbackShotServerMissing = false
        feedbackShotsByReport = [:]
        feedbackShotImages = [:]
        feedbackShotLoading = []
        feedbackShotFailures = [:]
        feedbackShotViewer = nil
    }
}
