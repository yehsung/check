import CheckCore
import CoreGraphics
import Foundation

// MARK: - 1:1 메시지 사진(폰 1.0.19 — 맥 0.3.86 `WorkTimerStoreMessagePhotos` 의 폰 짝 · 대표 #d_xygj8oZRFlfH 4번 메시지 묶음)
//
// 전선 이름 · 키 · 행 모양은 코어 `MessagePhotoWire.swift` 한 곳이다. 맥과 같은 여섯 가지:
// ① 24시간 머리(`history`)는 그대로 — 사진은 따로 든 표(`photoMeta`)로 배우고 **그릴 때만** 얹는다(`photoDisplayed`).
//    안 읽음 점 · 읽음 경계는 사진을 모른다.
// ② 사진 칸을 묻는 자리는 둘뿐: 대화를 열 때 한 번(`armPhotoMeta`), 열린 대화의 머리에 사진 칸을 모르는 말이 생겼을 때(합쳐서 ·
//    0.4초 · 상대마다 하나 — `noteHeadChangedForPhotos`). 이 폰이 보낸 말은 보낸 자리에서 물어본 것으로 친다.
//    함수가 없는 서버면 다음 대화 열기까지 안 묻는다(사진 줄은 글 '📷 사진'으로 그린다).
// ③ 보내기는 올리기 → `send_photo_message`, 같은 소문자 uuid 가 파일 이름 · `p_client_message_id` 를 겸한다. 답을 못 받은 실패는
//    같은 이름 · 같은 키로 한 번 더. 올리기 409 는 우리 앞 시도가 올린 우리 파일이다(성공). 올리기가 거절되면 RPC 로 사유를 가른다.
// ④ 그림은 메모리에만(`MessagesPhotoImageCache` — 경로가 열쇠). 보이는 말풍선이 그때 한 장씩 받는다. 로그아웃이 통째로 비운다.
// ⑤ 화면을 찍지 않는다 — 사진은 사람이 시스템 사진 고르기로 고른 것뿐이다(사진 권한을 묻지 않는다).
// ⑥ 사진 · 경로 · 글은 사람이 보낸 것 — 로그 금지.

/// 사진 칸 한 줄 — 그 메시지의 사진과 설명(사진만 보냈으면 nil).
package struct MessagesPhotoMeta: Equatable, Sendable {
    package let attachment: MessagePhotoAttachment
    package let caption: String?
}

/// 고른 사진(미리 보기 · 보내기 전). `id` 가 파일 이름이자 전송 멱등 키다(③).
package struct MessagesPhotoDraft: Identifiable, Equatable, @unchecked Sendable {
    package let id: String
    package let peer: String
    package let encoded: MessagePhotoEncoded
    /// 미리 보기 그림.
    package let preview: MessagePhotoImageBox
    /// 이 이름으로 이미 올렸는가(다시 [보내기]를 누르면 올리기를 건너뛴다).
    package var uploaded = false

    package static func == (lhs: MessagesPhotoDraft, rhs: MessagesPhotoDraft) -> Bool {
        lhs.id == rhs.id && lhs.peer == rhs.peer && lhs.uploaded == rhs.uploaded && lhs.encoded == rhs.encoded
    }
}

/// 사진 칸 조회의 비관찰 장부(로그아웃이 통째로 새것으로 바꾼다).
struct MessagesPhotoRuntime {
    var armedPeer: String?
    var coveredIDs: [String: Set<String>] = [:]
    var coveredFloor: [String: Date] = [:]
    var inFlight: Set<String> = []
    var trailing: Set<String> = []
    var scheduled: Task<Void, Never>?
    var token = 0
    var prepareToken = 0
}

/// 말풍선이 사진을 그리는 묶음(캐시 + 받기 · 다시 받기 문). 뷰는 스토어를 몰라도 된다.
@MainActor
package struct MessagesPhotoBubbleContext {
    package let images: MessagesPhotoImageCache
    package let owner: String?
    package let request: @MainActor (String) -> Void
    package let retry: @MainActor (String) -> Void

    package func image(for path: String) -> CGImage? { images.image(for: path, owner: owner) }
    package func state(for path: String) -> MessagesPhotoLoadState? { images.state(for: path, owner: owner) }
}

@MainActor
extension MessagesStore {
    /// 머리 변화 뒤 사진 칸 조회를 모으는 시간(초).
    package nonisolated static let photoMetaDebounceSeconds: TimeInterval = 0.4
    /// 머리 시각은 초 단위 반올림이다 — 덮은 창의 아래 끝을 이만큼 너그럽게 본다.
    nonisolated static let photoCoverSlack: TimeInterval = 1

    // MARK: 파생값

    /// [사진] 버튼이 서는가 — 로그인 · 상대 있음 · 이 세션에 문이 닫혀 있지 않음.
    package func showsPhotoButton(for peerID: String) -> Bool {
        isSignedIn && !peerID.isEmpty && !photoSendClosed
    }

    /// 지금 사진을 고르거나 보낼 수 있는가 — 글과 같은 조건(왕복 중 아님 · 집중이 막지 않음) + 문 + 준비 중 아님.
    package func canSendPhoto(to peerID: String) -> Bool {
        showsPhotoButton(for: peerID) && !isSending && focusBlock(for: peerID) == nil && !photoPreparing
    }

    /// 그 대화의 고른 사진(다른 사람에게 고른 사진은 이 대화에 안 선다).
    package func photoDraft(for peerID: String) -> MessagesPhotoDraft? {
        guard let draft = photoDraft, draft.peer == peerID else { return nil }
        return draft
    }

    /// 그릴 줄에 사진을 얹는다(①). 머리 줄은 사진 칸 표에서, 지난 쪽 줄은 이미 실려 있다. id · 순서 · 읽음은 그대로다.
    package func photoDisplayed(_ entries: [MessageHistoryEntry], peer: String) -> [MessageHistoryEntry] {
        guard let meta = photoMeta[peer], !meta.isEmpty else { return entries }
        return entries.map { entry in
            guard entry.photo == nil, let known = meta[entry.id] else { return entry }
            return entry.withPhoto(known.attachment, caption: known.caption)
        }
    }

    /// 뷰가 사진을 그리는 묶음.
    package var photoContext: MessagesPhotoBubbleContext {
        MessagesPhotoBubbleContext(
            images: photoImages,
            owner: context.gomokuHost.session?.userID,
            request: { [weak self] path in self?.requestPhotoImage(path) },
            retry: { [weak self] path in self?.retryPhotoImage(path) }
        )
    }

    /// 사진 칸 조회가 쉬고 있는가(시험).
    package var photoMetaIdle: Bool { photoRuntime.inFlight.isEmpty && photoRuntime.scheduled == nil }

    // MARK: 사진 칸 — 묻기(②)

    /// 사람이 대화를 열었다. 닫힌 문 · 함수 없음 숨김을 되돌리고, 다른 사람의 사진 상태를 걷고, 한 번 묻는다.
    package func armPhotoMeta(for peer: String) {
        if photoSendClosed { photoSendClosed = false }
        if photoMetaAvailable == false { photoMetaAvailable = nil }
        if photoRuntime.armedPeer != peer { clearPhotoConversation() }
        photoRuntime.armedPeer = peer
        guard isSignedIn else { return }
        startPhotoMetaFetch(peer: peer)
    }

    /// 대화 화면을 떠난다 — 사진 칸 · 고른 사진을 걷고 날던 조회를 버린다. 그림 캐시는 남는다.
    package func clearPhotoConversation() {
        photoRuntime.token += 1
        photoRuntime.scheduled?.cancel()
        photoRuntime.scheduled = nil
        photoRuntime.inFlight = []
        photoRuntime.trailing = []
        photoRuntime.coveredIDs = [:]
        photoRuntime.coveredFloor = [:]
        photoRuntime.armedPeer = nil
        if !photoMeta.isEmpty { photoMeta = [:] }
        cancelPhotoDraft()
    }

    /// 로그아웃. 사진 상태 전부 + 그림 캐시를 비운다.
    func resetPhotoState() {
        clearPhotoConversation()
        photoRuntime = MessagesPhotoRuntime()
        photoMetaAvailable = nil
        photoSendClosed = false
        photoImages.wipe()
    }

    /// 열린 대화의 머리가 바뀌었다(이력 응답). 사진 칸을 모르는 줄이 있으면 합쳐서 한 번 묻는다.
    func noteHeadChangedForPhotos() {
        guard isSignedIn, let peer = photoRuntime.armedPeer, openConversationPeerID == peer, photoMetaAvailable != false else { return }
        guard !uncoveredPhotoCandidates(peer: peer).isEmpty else { return }
        if photoRuntime.inFlight.contains(peer) {
            photoRuntime.trailing.insert(peer)
            return
        }
        schedulePhotoMetaFetch(peer: peer)
    }

    /// 머리 줄 중 아직 안 물어본 것(덮은 창 안의 것만). 내 말도 센다 — 같은 계정의 맥이 보낸 사진은 이 폰이 모른다.
    package func uncoveredPhotoCandidates(peer: String) -> [String] {
        let covered = photoRuntime.coveredIDs[peer] ?? []
        let floor = photoRuntime.coveredFloor[peer]?.addingTimeInterval(-Self.photoCoverSlack)
        return history.compactMap { entry in
            guard entry.peerUserID == peer, !covered.contains(entry.id) else { return nil }
            if let floor, entry.createdAt < floor { return nil }
            return entry.id
        }
    }

    /// 이 폰이 보낸 말의 서버 id — 열린 대화의 것이면 물어본 것으로 친다.
    func noteMessageSentForPhotos(messageID: String?, peer: String) {
        guard let messageID, !messageID.isEmpty, photoRuntime.armedPeer == peer else { return }
        photoRuntime.coveredIDs[peer, default: []].insert(messageID)
    }

    private func schedulePhotoMetaFetch(peer: String) {
        guard photoRuntime.scheduled == nil else { return }
        let token = photoRuntime.token
        let sleep = self.sleep
        photoRuntime.scheduled = Task { @MainActor [weak self] in
            await sleep(Self.photoMetaDebounceSeconds)
            guard let self, token == self.photoRuntime.token else { return }
            self.photoRuntime.scheduled = nil
            guard !self.uncoveredPhotoCandidates(peer: peer).isEmpty else { return }
            self.startPhotoMetaFetch(peer: peer)
        }
    }

    private func startPhotoMetaFetch(peer: String) {
        guard isSignedIn, photoMetaAvailable != false else { return }
        guard !photoRuntime.inFlight.contains(peer) else {
            photoRuntime.trailing.insert(peer)
            return
        }
        photoRuntime.inFlight.insert(peer)
        let asked = uncoveredPhotoCandidates(peer: peer)
        let token = photoRuntime.token
        let generation = context.generation
        Task { @MainActor [weak self] in
            await self?.performLoadPhotoMeta(peer: peer, asked: asked, token: token, generation: generation)
        }
    }

    private func isCurrentPhotoRequest(peer: String, token: Int, generation: Int) -> Bool {
        generation == context.generation && token == photoRuntime.token && photoRuntime.armedPeer == peer
    }

    /// `message_page(peer, null, null, 30)` 한 번 → 사진 칸을 배운다.
    private func performLoadPhotoMeta(peer: String, asked: [String], token: Int, generation: Int) async {
        guard let me = context.gomokuHost.session?.userID else {
            if token == photoRuntime.token { photoRuntime.inFlight.remove(peer) }
            return
        }
        let service = context.service
        do {
            let page = try await context.withMobileSessionRetry { session in
                try await service.fetchMessagePage(accessToken: session.accessToken, peer: peer, me: me, before: nil,
                                                   limit: MessagePhotoText.metaPageLimit)
            }
            guard isCurrentPhotoRequest(peer: peer, token: token, generation: generation) else { return }
            photoRuntime.inFlight.remove(peer)
            if photoMetaAvailable != true { photoMetaAvailable = true }
            absorbPhotoMeta(page.entries, peer: peer)
            var covered = photoRuntime.coveredIDs[peer] ?? []
            covered.formUnion(page.rowIDs)
            covered.formUnion(asked)
            photoRuntime.coveredIDs[peer] = covered
            if page.rowCount >= page.limit, let oldest = page.oldestCursor {
                photoRuntime.coveredFloor[peer] = Date(timeIntervalSince1970: TimeInterval(oldest.epochMicros) / 1_000_000)
            } else {
                photoRuntime.coveredFloor[peer] = nil
            }
            if photoRuntime.trailing.remove(peer) != nil, !uncoveredPhotoCandidates(peer: peer).isEmpty {
                schedulePhotoMetaFetch(peer: peer)
            }
        } catch {
            if AuthErrorRules.classify(error) == .cancelled {
                if token == photoRuntime.token { photoRuntime.inFlight.remove(peer) }
                return
            }
            guard isCurrentPhotoRequest(peer: peer, token: token, generation: generation) else { return }
            photoRuntime.inFlight.remove(peer)
            photoRuntime.trailing.remove(peer)
            if let serviceError = error as? SupabaseWorkServiceError, Self.isMissingFunction(serviceError) {
                photoMetaAvailable = false
            } else {
                // 일시 실패 — 지금 아는 줄은 물어본 것으로 친다(같은 줄로 다시 묻는 고리가 없게). 다음 대화 열기가 다시 묻는다.
                var covered = photoRuntime.coveredIDs[peer] ?? []
                covered.formUnion(asked)
                covered.formUnion(uncoveredPhotoCandidates(peer: peer))
                photoRuntime.coveredIDs[peer] = covered
            }
        }
    }

    /// 사진이 실린 줄(지난 쪽 · 사진 칸 조회)을 사진 칸 표에 넣는다.
    func absorbPhotoMeta(_ entries: [MessageHistoryEntry], peer: String) {
        var map = photoMeta[peer] ?? [:]
        var changed = false
        for entry in entries {
            guard let photo = entry.photo else { continue }
            let meta = MessagesPhotoMeta(attachment: photo, caption: entry.photoCaption)
            if map[entry.id] != meta {
                map[entry.id] = meta
                changed = true
            }
        }
        if changed { photoMeta[peer] = map }
    }

    // MARK: 고르기(⑤)

    /// 고른 사진 원본을 메인 밖에서 줄인 뒤 미리 보기에 세운다. 못 보내는 상태면 사유를 한 줄 남기고 아무것도 안 한다.
    package func preparePhoto(data: Data, for peerID: String) {
        // 집중이 막으면 입력줄이 사유를 늘 띄운다(`MessagesComposerRules.noticeLine`) — 여기 적지 않는다(글 보내기와 같은 약속).
        guard canSendPhoto(to: peerID) else {
            if focusBlock(for: peerID) == nil, isSending { sendNotices[peerID] = AingStickerText.sendingNowNotice }
            return
        }
        photoRuntime.prepareToken += 1
        let token = photoRuntime.prepareToken
        let generation = context.generation
        photoPreparing = true
        Task { @MainActor [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) { () -> (MessagePhotoEncoded, MessagePhotoImageBox)? in
                guard let (encoded, full) = MessagePhotoEncoder.encode(data: data) else { return nil }
                let preview = MessagePhotoEncoder.decodeForDisplay(encoded.data, maxPixelSize: MessagesPhotoImageCache.displayPixels)
                return (encoded, preview ?? full)
            }.value
            guard let self, generation == self.context.generation, token == self.photoRuntime.prepareToken else { return }
            self.photoPreparing = false
            guard let prepared else {
                self.sendNotices[peerID] = MessagePhotoText.unreadableNotice
                return
            }
            self.photoDraft = MessagesPhotoDraft(id: MessagePhotoPath.newID(), peer: peerID, encoded: prepared.0, preview: prepared.1)
        }
    }

    /// 미리 보기의 [취소]. 보내는 중이면 아무것도 안 한다(날고 있는 올리기 · RPC 는 멈출 수 없다).
    package func cancelPhotoDraftFromPreview() {
        guard !isSending else { return }
        cancelPhotoDraft()
    }

    /// 고른 사진을 버린다(줄이던 작업의 결과도 버린다).
    package func cancelPhotoDraft() {
        photoRuntime.prepareToken += 1
        if photoPreparing { photoPreparing = false }
        if photoDraft != nil { photoDraft = nil }
    }

    // MARK: 보내기(③)

    /// 미리 보기의 [보내기]. 설명은 **지금 입력칸의 글**이다(성공하면 글을 보낸 것처럼 비운다 · 실패하면 글과 사진이 남는다).
    package func sendPhotoDraft(to peerID: String) {
        guard let photo = photoDraft(for: peerID), let me = context.gomokuHost.session?.userID else { return }
        guard canSendPhoto(to: peerID) else { return }
        let caption: String?
        switch MessageBody.validate(draft(for: peerID)) {
        case .ok(let normalized): caption = normalized
        case .empty: caption = nil
        case .tooLong(let maxLength):
            // 설명이 너무 길다 — 글 보내기의 서버 거절과 같은 문장(입력칸 글은 그대로 남는다).
            sendNotices[peerID] = MessagesSendRules.notice(for: .tooLong, maxLength: maxLength)
            return
        }
        let draft = photo
        sendNotices[peerID] = nil
        isSending = true
        let generation = context.generation
        let path = MessagePhotoPath.uploadPath(owner: me, id: draft.id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.isSending = false } }
            guard let response = await self.deliverPhoto(draft: draft, path: path, caption: caption, generation: generation) else { return }
            guard generation == self.context.generation else { return }
            switch MessagePhotoSendOutcome(response: response) {
            case .message(let outcome):
                if outcome == .ok {
                    self.recordSentPhoto(draft: draft, path: path, caption: caption, response: response, owner: me)
                    // 설명을 입력칸에서 가져갔을 때만 비운다(빈 칸이었으면 왕복 중에 친 글을 지우지 않는다).
                    if caption != nil { self.setDraft("", for: peerID) }
                    self.noteMessageSentForPhotos(messageID: response.send.messageId, peer: peerID)
                    self.requestActivityRefresh(includeHistory: true)
                } else if outcome == .senderFocused {
                    // 내 집중으로 거절 — 켜짐으로 들인다(사유는 입력줄이 띄운다 · 글 보내기와 같다).
                    self.adoptServerSenderFocused()
                } else if let notice = MessagesSendRules.notice(for: outcome, maxLength: response.send.maxLength) {
                    self.sendNotices[peerID] = notice
                }
            case .unsupportedClient(let doorOpen):
                if doorOpen == true {
                    // 문은 열렸는데 이 기기의 판 번호가 아직 서버에 안 닿았다(잠깐이다) — 고른 사진을 남긴다.
                    self.sendNotices[peerID] = MessagePhotoText.doorOpenNotice
                } else {
                    self.closePhotoDoor(notice: MessagePhotoText.doorClosedNotice, peer: peerID)
                }
            case .invalidPhoto:
                self.renewPhotoDraft(draft)
                self.sendNotices[peerID] = MessagePhotoText.invalidPhotoNotice
            case .photoMissing:
                self.markPhotoDraft(draft, uploaded: false)
                self.sendNotices[peerID] = MessagePhotoText.uploadFailedNotice
            }
        }
    }

    /// 올리기(필요하면) → RPC. nil 이면 문구까지 여기서 끝냈다(또는 취소 · 세대 변경).
    private func deliverPhoto(draft: MessagesPhotoDraft, path: String, caption: String?, generation: Int) async -> SendPhotoMessageResponse? {
        if !draft.uploaded {
            switch await uploadPhotoForSend(draft: draft, path: path, generation: generation) {
            case .uploaded: markPhotoDraft(draft, uploaded: true)
            case .refused: break
            case .handled: return nil
            }
        }
        let request = SendPhotoMessageRequest(to: draft.peer, path: path, width: draft.encoded.pixelWidth,
                                              height: draft.encoded.pixelHeight, caption: caption, clientMessageID: draft.id)
        let service = context.service
        var retried = false
        while true {
            do {
                return try await context.withMobileSessionRetry { session in
                    try await service.sendPhotoMessage(accessToken: session.accessToken, request: request)
                }
            } catch {
                if AuthErrorRules.classify(error) == .cancelled { return nil }
                guard generation == context.generation else { return nil }
                if MessagesSendRules.isAmbiguousFailure(error), !retried {
                    retried = true
                    await sleep(sendRetryDelaySeconds)
                    guard generation == context.generation else { return nil }
                    continue
                }
                if let serviceError = error as? SupabaseWorkServiceError, Self.isMissingFunction(serviceError) {
                    closePhotoDoor(notice: MessagePhotoText.doorClosedNotice, peer: draft.peer)
                } else {
                    sendNotices[draft.peer] = MessagesSendRules.connectionNotice
                }
                return nil
            }
        }
    }

    private enum PhotoUploadResult { case uploaded, refused, handled }

    /// 올리기 한 번(+ 답을 못 받으면 같은 이름으로 한 번 더). 409 는 우리 앞 시도가 올린 우리 파일이다(성공).
    private func uploadPhotoForSend(draft: MessagesPhotoDraft, path: String, generation: Int) async -> PhotoUploadResult {
        let service = context.service
        var retried = false
        while true {
            do {
                try await context.withMobileSessionRetry { session in
                    try await service.uploadMessagePhoto(accessToken: session.accessToken, path: path, data: draft.encoded.data)
                }
                return .uploaded
            } catch PrivateStorageError.alreadyExists {
                return .uploaded
            } catch {
                if AuthErrorRules.classify(error) == .cancelled { return .handled }
                guard generation == context.generation else { return .handled }
                if MessagesSendRules.isAmbiguousFailure(error), !retried {
                    retried = true
                    await sleep(sendRetryDelaySeconds)
                    guard generation == context.generation else { return .handled }
                    continue
                }
                switch error {
                case PrivateStorageError.forbidden:
                    return .refused
                case PrivateStorageError.tooLarge:
                    sendNotices[draft.peer] = MessagePhotoText.tooLargeNotice
                case SupabaseWorkServiceError.databaseSchemaMissing:
                    closePhotoDoor(notice: MessagePhotoText.doorClosedNotice, peer: draft.peer)
                default:
                    sendNotices[draft.peer] = MessagesSendRules.connectionNotice
                }
                return .handled
            }
        }
    }

    /// 보낸 내 사진을 그 자리에서 그린다: 사진 칸 표에 넣고 올린 그림을 캐시에 넣는다(내 사진은 받지 않는다). 고른 사진은 내린다.
    private func recordSentPhoto(draft: MessagesPhotoDraft, path: String, caption: String?, response: SendPhotoMessageResponse, owner: String) {
        let attachment = response.attachment
            ?? MessagePhotoAttachment(path: path, width: draft.encoded.pixelWidth, height: draft.encoded.pixelHeight)
        if let attachment {
            photoImages.insert(draft.preview, path: attachment.path, owner: owner)
            if let id = response.send.messageId, !id.isEmpty {
                var map = photoMeta[draft.peer] ?? [:]
                map[id] = MessagesPhotoMeta(attachment: attachment,
                                            caption: Self.sentPhotoCaption(serverBody: response.send.body, sent: caption))
                photoMeta[draft.peer] = map
                photoRuntime.coveredIDs[draft.peer, default: []].insert(id)
            }
        }
        if photoDraft?.id == draft.id { photoDraft = nil }
    }

    /// 보낸 사진의 설명 — **서버가 저장한 본문**이 진실이다. 본문이 '📷 사진'이면 사진만 보낸 줄이다(맥과 같은 규칙).
    package nonisolated static func sentPhotoCaption(serverBody: String?, sent: String?) -> String? {
        guard let serverBody else { return sent }
        let body = MessageBody.sanitized(serverBody)
        guard MessageBody.hasVisibleContent(body), body != MessageNoticeText.photoFallbackBody else { return nil }
        return body
    }

    /// 문이 닫혀 있다(또는 함수 · 버킷이 없다) — 문구 한 줄, 고른 사진을 내리고 [사진] 버튼을 다음 대화 열기까지 숨긴다. 글 초안은 남는다.
    private func closePhotoDoor(notice: String, peer: String) {
        photoSendClosed = true
        cancelPhotoDraft()
        sendNotices[peer] = notice
    }

    private func markPhotoDraft(_ draft: MessagesPhotoDraft, uploaded: Bool) {
        guard var current = photoDraft, current.id == draft.id, current.uploaded != uploaded else { return }
        current.uploaded = uploaded
        photoDraft = current
    }

    /// 같은 사진 · 새 이름(서버가 그 이름을 안 받는다 — invalid_photo).
    private func renewPhotoDraft(_ draft: MessagesPhotoDraft) {
        guard let current = photoDraft, current.id == draft.id else { return }
        photoDraft = MessagesPhotoDraft(id: MessagePhotoPath.newID(), peer: current.peer, encoded: current.encoded, preview: current.preview)
    }

    // MARK: 그림 받기(④)

    /// 말풍선이 보일 때 그 사진을 받는다(경로마다 하나 · 실패 기억).
    package func requestPhotoImage(_ path: String) {
        guard let owner = context.gomokuHost.session?.userID, MessagePhotoPath.isServerShaped(path) else { return }
        if let loader = photoDataLoader {
            photoImages.load(path: path, owner: owner) { try await loader(path) }
            return
        }
        let generation = context.generation
        let service = context.service
        let ctx = context
        photoImages.load(path: path, owner: owner) {
            guard generation == ctx.generation else { throw CancellationError() }
            return try await ctx.withMobileSessionRetry { session in
                try await service.fetchMessagePhotoData(accessToken: session.accessToken, path: path)
            }
        }
    }

    /// 실패 칸을 사람이 눌렀다 — 한 번 다시 받는다.
    package func retryPhotoImage(_ path: String) {
        photoImages.forgetFailure(path: path)
        requestPhotoImage(path)
    }
}
