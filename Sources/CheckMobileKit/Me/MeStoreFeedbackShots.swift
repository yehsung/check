import CheckCore
import Foundation

// MARK: - 제보 화면 캡처(폰 1.0.19 — 맥 0.3.86 `WorkTimerStoreFeedbackShot` 의 폰 짝 · 대표 #d_xygj8oZRFlfH 4번 메시지 묶음)
//
// 서버 어휘는 전부 코어 `FeedbackShotWire`(계약 v2 §3). 맥과 같은 다섯 가지:
//  ① **글이 먼저 간다.** `submit_feedback` 이 돌려준 제보 id 폴더에 캡처를 하나씩 올리고(`feedback-shots/<내 uid>/<제보 id>/<새 uuid>.jpg`)
//     붙인다(`feedback_attach_shot`). 캡처가 실패해도 제보는 보낸 것이다 — 글을 다시 보내지 않고 한 줄로 말한다.
//  ② 새 자동 호출은 하나뿐: `feedback_list` 가 비어 있지 않을 때 `feedback_shots` 한 번(칩 "캡처 N장").
//  ③ 404 · PGRST202 는 입구를 숨기되 영구히 기억하지 않는다(제보 화면을 다시 열면 다시 묻는다). 문 닫힘은 붙이기 줄만 숨긴다.
//  ④ 캡처를 얻는 길은 사진 고르기뿐이다(시스템 사진 고르기 — 사진 권한을 묻지 않는다 · 이 앱은 화면을 찍지 않는다).
//  ⑤ 캡처에는 남의 이름 · 대화가 찍혀 있을 수 있다 — 로그 금지 · 디스크에 쓰지 않는다.
// 줄이기는 메시지 사진과 같은 코어 `MessagePhotoEncoder`(긴 변 1600px · JPEG · 약 0.35MB) — 계약 "긴 변 1600px 안팎 · JPEG · 약 0.3MB".

/// 붙여 둔 캡처 한 장(보내기 전).
package struct MeFeedbackShotDraft: Identifiable, Equatable, @unchecked Sendable {
    package let id: UUID
    /// 올릴 JPEG(긴 변 ≤ 1600px).
    package let jpeg: Data
    package let pixelWidth: Int
    package let pixelHeight: Int
    /// 화면에 그릴 미리 보기.
    package let preview: MessagePhotoImageBox

    package init(id: UUID = UUID(), jpeg: Data, pixelWidth: Int, pixelHeight: Int, preview: MessagePhotoImageBox) {
        self.id = id
        self.jpeg = jpeg
        self.pixelWidth = max(1, pixelWidth)
        self.pixelHeight = max(1, pixelHeight)
        self.preview = preview
    }

    package static func == (lhs: MeFeedbackShotDraft, rhs: MeFeedbackShotDraft) -> Bool { lhs.id == rhs.id }
}

/// 보낸 뒤 캡처 한 장의 결과(올리기 + 붙이기) — 맥 `FeedbackShotStep` 과 같은 갈래.
package enum MeFeedbackShotStep: Equatable, Sendable {
    case attached
    /// 일시 실패 — 다음 캡처는 계속한다.
    case failed
    /// 저장소가 정책으로 거절했고 서버도 문 닫힘을 말하지 않았다 — 멈춘다.
    case refused
    /// 서버 문이 닫혔다(`door_open` 거짓).
    case doorClosed
    /// 문은 열렸는데 이 앱 판을 받지 않았다(`door_open` 참).
    case outdated
    case tooMany(Int)
    /// 서버에 함수 · 버킷이 없다.
    case missing

    package var stops: Bool {
        switch self {
        case .attached, .failed: return false
        case .refused, .doorClosed, .outdated, .tooMany, .missing: return true
        }
    }

    package var closesTheDoor: Bool { self == .doorClosed || self == .outdated }
}

/// 보낸 뒤 캡처들의 결과를 세어 안내 한 줄을 고른다(순수 — 맥 `FeedbackShotTally` 와 같은 글).
package struct MeFeedbackShotTally: Equatable, Sendable {
    package let total: Int
    package private(set) var attached = 0
    package private(set) var stop: MeFeedbackShotStep?

    package init(total: Int) { self.total = total }

    package mutating func record(_ step: MeFeedbackShotStep) {
        if step == .attached { attached += 1 }
        if step.stops, stop == nil { stop = step }
    }

    package var failed: Int { max(0, total - attached) }

    package var notice: String {
        switch stop {
        case .doorClosed?, .missing?: return FeedbackShotText.sentShotsDoorClosed
        case .outdated?: return FeedbackShotText.sentShotsAppOutdated
        case .tooMany(let max)?: return FeedbackShotText.sentShotsTooMany(max)
        default: break
        }
        if failed == 0 { return FeedbackText.sendSuccess }
        if attached == 0 { return FeedbackShotText.sentShotsFailed }
        return FeedbackShotText.sentSomeShotsFailed(failed)
    }
}

extension MeStore {
    // MARK: 파생값

    /// 캡처 입구(붙이기 줄 · 칩)를 보이는가 — 서버에 기능이 있는가(③).
    package var feedbackShotsShown: Bool { !feedbackShotServerMissing }
    /// 붙이기 줄을 보이는가(붙이기 줄 · 전송 · 경고 한 줄이 같은 값을 읽는다).
    package var feedbackShotAttachShown: Bool { feedbackShotsShown && !feedbackShotDoorClosed }
    /// 지금 캡처를 붙이거나 뺄 수 있는가.
    package var canEditFeedbackShots: Bool { feedbackShotAttachShown && !isSendingFeedback && !feedbackShotPreparing }
    /// 더 붙일 수 있는 장수.
    package var feedbackShotRoom: Int { max(0, FeedbackShotRules.maxDraft - feedbackShots.count) }
    /// 이번 전송에 실을 캡처(붙이기 줄이 숨었으면 없다).
    package var feedbackShotsForSend: [MeFeedbackShotDraft] { feedbackShotAttachShown ? feedbackShots : [] }

    /// 내 제보 하나에 붙은 캡처 수(칩). 입구가 숨었으면 0.
    package func feedbackShotCount(forReport id: String) -> Int {
        guard feedbackShotsShown else { return 0 }
        return feedbackShotsByReport[id.lowercased()]?.count ?? 0
    }

    // MARK: 입구

    /// 제보 화면을 열 때 — 앞서 숨긴 입구를 다시 연다(③).
    package func rearmFeedbackShots() {
        if feedbackShotServerMissing { feedbackShotServerMissing = false }
        if feedbackShotDoorClosed { feedbackShotDoorClosed = false }
    }

    private func markFeedbackShotsMissing() {
        feedbackShotServerMissing = true
        if !feedbackShotsByReport.isEmpty { feedbackShotsByReport = [:] }
    }

    // MARK: 붙이기 · 빼기

    /// 사진 고르기로 받은 원본들을 붙인다(남은 자리만큼 · 줄이기는 메인 밖). 자리보다 많으면 앞에서부터 자리만큼 붙이고 "3장까지"를 말한다.
    package func attachFeedbackShots(datas: [Data]) {
        guard canEditFeedbackShots else { return }
        // 골랐는데 하나도 못 읽었다(아이클라우드에서 못 받음 등) — 조용히 끝내지 않고 말한다.
        guard !datas.isEmpty else {
            feedbackNotice = FeedbackShotText.unreadable
            return
        }
        guard feedbackShotRoom > 0 else {
            feedbackNotice = FeedbackShotText.full
            return
        }
        let room = feedbackShotRoom
        let taken = Array(datas.prefix(room))
        let overflowed = datas.count > room
        feedbackShotPrepareSerial += 1
        let serial = feedbackShotPrepareSerial
        let generation = context.generation
        feedbackShotPreparing = true
        launch { [weak self] in
            var drafts: [MeFeedbackShotDraft] = []
            var unreadable = false
            for data in taken {
                let encoded = await Task.detached(priority: .userInitiated) { MessagePhotoEncoder.encode(data: data) }.value
                if let (photo, box) = encoded {
                    drafts.append(MeFeedbackShotDraft(jpeg: photo.data, pixelWidth: photo.pixelWidth, pixelHeight: photo.pixelHeight, preview: box))
                } else {
                    unreadable = true
                }
            }
            guard let self, generation == self.context.generation, serial == self.feedbackShotPrepareSerial else { return }
            self.feedbackShotPreparing = false
            let space = max(0, FeedbackShotRules.maxDraft - self.feedbackShots.count)
            self.feedbackShots.append(contentsOf: drafts.prefix(space))
            if overflowed || drafts.count > space {
                self.feedbackNotice = FeedbackShotText.full
            } else if unreadable {
                self.feedbackNotice = FeedbackShotText.unreadable
            } else if let notice = self.feedbackNotice,
                      [FeedbackShotText.unreadable, FeedbackShotText.tooLarge, FeedbackShotText.full].contains(notice) {
                self.feedbackNotice = nil
            }
        }
    }

    /// [빼기] 한 장.
    package func removeFeedbackShot(id: UUID) {
        guard !isSendingFeedback else { return }
        feedbackShots.removeAll { $0.id == id }
    }

    /// 글만 나간 제보 뒤 — 실리지 않은 캡처를 내린다(다음 제보에 따라 나가지 않게 — 남의 대화가 찍혔을 수 있는 그림이다).
    func discardUnsentFeedbackShots() {
        if !feedbackShots.isEmpty { feedbackShots = [] }
    }

    // MARK: 보낸 뒤(글은 이미 갔다)

    /// 캡처를 화면에서 내리고 하나씩 올리고 붙인 뒤 안내 한 줄을 정한다. 제보 id 를 못 읽었으면 캡처만 못 붙인 것으로 말한다.
    func finishFeedbackShotsAfterSubmit(_ shots: [MeFeedbackShotDraft], returnedID: String?, generation: Int) async {
        let sentIDs = Set(shots.map(\.id))
        feedbackShots.removeAll { sentIDs.contains($0.id) }
        guard let reportID = FeedbackShotWire.reportID(from: returnedID), let userID = context.session.userID else {
            feedbackNotice = FeedbackShotText.sentShotsFailed
            return
        }
        feedbackNotice = FeedbackShotText.uploading
        var tally = MeFeedbackShotTally(total: shots.count)
        for shot in shots {
            let step = await uploadAndAttachFeedbackShot(shot, userID: userID, reportID: reportID)
            guard generation == context.generation else { return }
            tally.record(step)
            if step == .missing { markFeedbackShotsMissing() }
            if step.closesTheDoor { feedbackShotDoorClosed = true }
            if step.stops { break }
        }
        feedbackNotice = tally.notice
    }

    /// 캡처 한 장: 올리기 → 붙이기(맥과 같은 갈래 — 저장소 거절이면 붙이기에 까닭을 묻는다).
    private func uploadAndAttachFeedbackShot(_ shot: MeFeedbackShotDraft, userID: String, reportID: String) async -> MeFeedbackShotStep {
        let path = FeedbackShotWire.objectPath(userID: userID, reportID: reportID, fileID: UUID().uuidString.lowercased())
        let service = context.service
        var uploadRefused = false
        do {
            try await context.withMobileSessionRetry { session in
                try await service.uploadFeedbackShot(accessToken: session.accessToken, path: path, jpeg: shot.jpeg)
            }
        } catch PrivateStorageError.alreadyExists {
            // 앞선 시도가 실제로는 올라갔다 — 붙이기로 넘어간다.
        } catch PrivateStorageError.forbidden {
            uploadRefused = true
        } catch {
            return FeedbackShotRules.isMissing(error) ? .missing : .failed
        }
        do {
            let outcome = try await context.withMobileSessionRetry { session in
                try await service.attachFeedbackShot(accessToken: session.accessToken, reportID: reportID, path: path,
                                                     width: shot.pixelWidth, height: shot.pixelHeight)
            }
            switch outcome {
            case .attached: return .attached
            case .doorClosed(let doorOpen): return doorOpen == true ? .outdated : .doorClosed
            case .tooMany(let max): return .tooMany(max)
            case .invalid, .invalidPhoto, .photoMissing, .unauthorized, .unknown:
                return uploadRefused ? .refused : .failed
            }
        } catch {
            if FeedbackShotRules.isMissing(error) { return .missing }
            return uploadRefused ? .refused : .failed
        }
    }

    // MARK: 목록 옆 칩

    /// 목록이 비어 있지 않으면 **한 번에** 캡처 행을 받는다(②). 404 는 입구를 숨긴다(③). 다른 실패는 조용히 — 칩만 안 보인다.
    func loadFeedbackShots(for reports: [FeedbackReport], generation: Int) async {
        guard context.session.isSignedIn, !reports.isEmpty, feedbackShotsShown else { return }
        let ids = reports.map { $0.id.lowercased() }
        let service = context.service
        do {
            let grouped = try await context.withMobileSessionRetry { session in
                try await service.fetchFeedbackShots(accessToken: session.accessToken, reportIDs: ids)
            }
            guard generation == context.generation else { return }
            if feedbackShotsByReport != grouped { feedbackShotsByReport = grouped }
        } catch {
            guard generation == context.generation else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            if FeedbackShotRules.isMissing(error) { markFeedbackShotsMissing() }
        }
    }
}
