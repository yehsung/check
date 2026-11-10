import AppKit
import CheckCore
import UniformTypeIdentifiers

// MARK: - 1:1 메시지 사진 (2026-11-11 — 맥 0.3.86 · build 139)
//
// 대표 결정(#d_x5kYyOPOeLlH): "사진 보내기". 전선 이름 · 키 · 행 모양은 코어 `MessagePhotoWire.swift` 한 곳이다.
//
// ── 이 파일이 지키는 여섯 가지 ──
//
// ① **24시간 머리(`messageHistory`)는 한 글자도 안 바뀐다.** 머리 줄에는 사진 칸이 없어서 사진은 따로 든 표(`messagePhotoMeta`)로
//    배우고, **그릴 때만** 얹는다(`messagePhotoDisplayed`). 그래서 안 읽음 점 · 읽음 경계 · 확성기 판정은 사진을 모른다.
// ② **사진 칸을 묻는 자리는 둘뿐이다**: 사람이 대화를 열 때(`openMessagePanel` → `armMessagePhotoMeta`) 한 번, 그리고 열린 대화의
//    머리에 사진 칸을 모르는 **받은** 말이 생겼을 때(합쳐서 · 상대마다 하나씩만 — `noteMessageHeadChangedForPhotos`). 팝오버 열기 ·
//    폴링 tick · 앱 시작 · 내 글 보내기는 묻지 않는다(내 말은 이 맥이 보낸 것이면 이미 안다).
//    함수가 없는 서버(404 · PGRST202)면 다음 패널 열기까지 안 묻는다(사진 줄은 글 '📷 사진'으로 그린다).
// ③ **보내기는 올리기 → `send_photo_message`** 이고, 같은 소문자 uuid 가 파일 이름과 `p_client_message_id` 를 겸한다. 답을 못 받은 실패는
//    **같은 이름 · 같은 키로** 한 번 더 보낸다(서버가 `duplicate` 로 한 줄에 접는다). 올리기 409 는 우리 앞 시도가 올린 우리 파일이다(성공).
//    올리기가 거절되면(403/400 — 문 닫힘 · 폴더 · 한 시간 60장) 그 경로로 RPC 를 한 번 불러 **사유를 가른다**.
//    결과 처리(문구 · 초안 비우기 · 확정 줄 · 이력 재조회)는 글과 **같은 함수**(`applyMessageSendOutcome`)다 — 여기 다시 적지 않는다.
// ④ **그림은 메모리에만** 든다(경로가 열쇠 — 서명 URL 은 바뀐다). 보이는 말풍선이 그때 한 장씩 받고, 경로마다 하나만 날고, 실패는
//    이 세션 동안 기억한다(무한 재시도 없음 — 사람이 실패 칸을 누를 때만 다시). 로그아웃 · 계정이 바뀌면 통째로 비운다.
// ⑤ **화면을 찍지 않는다.** 사진은 사람이 고른 파일(열기 창) · 붙여넣기(⌘V)뿐이다(처리방침 — 화면 기록 권한을 안 묻는다).
//    끌어 놓기는 없다 — 팝오버가 Finder 로 활성이 넘어가는 순간 닫힌다(CheckMessageView `conversation` 주석).
// ⑥ 사진 · 경로 · 글은 사람이 보낸 것이다 — 이 파일에 `print`/`Logger` 를 붙이지 마라.

// MARK: - 모양

/// 사진 칸 한 줄 — 그 메시지의 사진과 설명(사진만 보냈으면 nil).
struct MessagePhotoMeta: Equatable, Sendable {
    let attachment: MessagePhotoAttachment
    let caption: String?
}

/// 고른 사진(미리 보기 덮개 · 보내기 전). `id` 가 파일 이름이자 전송 멱등 키다(③).
struct MessagePhotoDraft: Equatable {
    let id: String
    let peer: String
    let encoded: MessagePhotoEncoded
    /// 미리 보기 그림(올릴 JPEG 를 화면 크기로 다시 읽은 것).
    let preview: MessagePhotoImageBox
    /// 이 이름으로 이미 올렸는가(다시 [보내기]를 누르면 올리기를 건너뛴다).
    var uploaded = false

    static func == (lhs: MessagePhotoDraft, rhs: MessagePhotoDraft) -> Bool {
        lhs.id == rhs.id && lhs.peer == rhs.peer && lhs.uploaded == rhs.uploaded && lhs.encoded == rhs.encoded
    }
}

/// 크게 보기 한 장(대화 자리 덮개).
struct MessagePhotoViewerItem: Equatable, Sendable {
    let photo: MessagePhotoAttachment
    let messageID: String
    let peerID: String
    let isMine: Bool
}

/// 사진 칸 조회의 비관찰 장부. 로그아웃이 통째로 새것으로 바꾼다.
struct MessagePhotoRuntime {
    /// 사람이 연 대화의 상대(사진 칸을 묻는 대상). nil = 연 대화가 없다.
    var armedPeer: String?
    /// 상대별 "이미 물어본" 메시지 id(서버가 준 줄 + 물을 때 모르던 받은 줄).
    var coveredIDs: [String: Set<String>] = [:]
    /// 상대별 덮은 창의 아래 끝(꽉 찬 쪽을 받았을 때 그 쪽의 가장 오래된 줄 시각). nil = 끝까지 받았다(그보다 옛 줄도 덮었다).
    var coveredFloor: [String: Date] = [:]
    /// 날고 있는 조회(상대마다 하나).
    var inFlight: Set<String> = []
    /// 날고 있는 동안 새 받은 줄이 생겼다 — 끝나면 한 번 더 본다.
    var trailing: Set<String> = []
    /// 합치기 잠을 자는 조회(하나).
    var scheduled: Task<Void, Never>?
    /// 비울 때마다 올려 날아가던 응답을 버린다(닫기 · 상대 바꾸기 · 로그아웃).
    var token = 0
    /// 사진 줄이기 작업의 순번(취소 · 다른 사진 고르기가 앞 작업의 결과를 버린다).
    var prepareToken = 0
}

/// 사진 한 장의 받기 상태(그림 캐시의 관찰 칸).
enum MessagePhotoLoadState: Equatable, Sendable {
    case loading
    case loaded
    case failed
}

/// 붙여넣기에서 읽은 사진 재료.
enum MessagePhotoPasteSource: Equatable {
    case file(URL)
    case data(Data)
}

/// 붙여넣기판 판정(순수에 가깝다 — 시험은 이름 있는 판을 따로 만들어 묻는다. 사용자의 `NSPasteboard.general` 을 안 건드린다).
enum MessagePhotoPasteboard {
    /// 그림 자료로 받는 형식(위에서부터).
    static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier)
    ]

    /// 그림 파일 URL → 파일, 글이 **없는** 그림 자료 → 바이트, 나머지 → nil(글 붙여넣기). 글이 함께 실린 판(표 · 웹 글 복사)은 글이다 —
    /// 그런 복사에도 그림 자료가 덤으로 실려서, 그림을 먼저 보면 사람이 붙이려던 글이 사진이 된다.
    static func source(from pasteboard: NSPasteboard) -> MessagePhotoPasteSource? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], let first = urls.first {
            return .file(first)
        }
        if pasteboard.string(forType: .string) != nil { return nil }
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty { return .data(data) }
        }
        return nil
    }
}

// MARK: - 그림 캐시(메모리 · 경로 열쇠)

/// 사진 그림의 메모리 캐시(④). **경로가 열쇠**이고 디스크에 남기지 않는다. 계정(`owner`)이 바뀌면 통째로 비운다 —
/// 남의 비공개 사진이 다음 계정 화면에 남지 않게. 관찰 칸은 `states` 하나다(그림은 NSCache 라 관찰되지 않는다).
@MainActor
@Observable
final class MessagePhotoImageCache {
    /// 화면용으로 줄여 드는 긴 변(px) — 말풍선 200pt · 크게 보기 292pt 를 2배 화면에서 그리기에 넉넉하다.
    nonisolated static let displayPixels = 800

    @ObservationIgnored private let images = NSCache<NSString, MessagePhotoImageBox>()
    /// 받은 JPEG 바이트([저장…] 이 원본을 그대로 쓴다). 한 장이 0.35MB 안팎이다.
    @ObservationIgnored private let originals = NSCache<NSString, NSData>()
    /// 경로 → 받기 상태(관찰 칸).
    private(set) var states: [String: MessagePhotoLoadState] = [:]
    /// 이 캐시가 담은 그림의 계정.
    @ObservationIgnored private(set) var owner: String?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var epoch = 0

    init() {
        images.totalCostLimit = 160 * 1_024 * 1_024
        originals.totalCostLimit = 40 * 1_024 * 1_024
    }

    /// 그 경로의 그림(이 계정 것만). 관찰 칸을 먼저 읽는다 — 받기가 끝나면 부른 뷰가 다시 그려진다.
    func image(for path: String, owner: String?) -> CGImage? {
        let state = states[path]
        guard let owner, owner == self.owner, state == .loaded else { return nil }
        return images.object(forKey: path as NSString)?.image
    }

    func state(for path: String, owner: String?) -> MessagePhotoLoadState? {
        let state = states[path]
        guard let owner, owner == self.owner else { return nil }
        return state
    }

    /// 받은 원본 바이트(이 계정 것만).
    func originalData(for path: String, owner: String?) -> Data? {
        guard let owner, owner == self.owner else { return nil }
        return originals.object(forKey: path as NSString) as Data?
    }

    /// 지금 날고 있는 받기 수(시험 · 부정형 단언용).
    var inFlightCount: Int { tasks.count }

    /// 그림을 넣는다(보낸 내 사진 — 받지 않는다).
    func insert(_ box: MessagePhotoImageBox, data: Data?, path: String, owner: String) {
        adopt(owner)
        tasks[path]?.cancel()
        tasks[path] = nil
        images.setObject(box, forKey: path as NSString, cost: box.image.width * box.image.height * 4)
        if let data { originals.setObject(data as NSData, forKey: path as NSString, cost: data.count) }
        if states[path] != .loaded { states[path] = .loaded }
    }

    /// 그 경로를 받는다(경로마다 하나만 · 실패는 기억 · 이미 있으면 아무것도 안 한다).
    func load(path: String, owner: String, fetch: @escaping @Sendable @MainActor () async throws -> Data) {
        adopt(owner)
        switch states[path] {
        case .some(.loaded) where images.object(forKey: path as NSString) != nil: return
        case .some(.failed): return
        default: break
        }
        guard tasks[path] == nil else { return }
        states[path] = .loading
        let epoch = self.epoch
        tasks[path] = Task { @MainActor [weak self] in
            var box: MessagePhotoImageBox?
            var data: Data?
            do {
                let fetched = try await fetch()
                data = fetched
                box = await Task.detached(priority: .userInitiated) {
                    MessagePhotoEncoder.decodeForDisplay(fetched, maxPixelSize: MessagePhotoImageCache.displayPixels)
                }.value
            } catch {
                box = nil
            }
            guard let self, epoch == self.epoch else { return }
            self.tasks[path] = nil
            if let box {
                self.images.setObject(box, forKey: path as NSString, cost: box.image.width * box.image.height * 4)
                if let data { self.originals.setObject(data as NSData, forKey: path as NSString, cost: data.count) }
                self.states[path] = .loaded
            } else {
                self.states[path] = .failed
            }
        }
    }

    /// 실패 기억을 지운다(사람이 실패 칸을 눌렀을 때만 — 다시 받는 자리는 그것뿐이다).
    func forgetFailure(path: String) {
        if states[path] == .failed { states[path] = nil }
    }

    /// 통째로 비운다(로그아웃 · 계정 바뀜). 날던 받기의 결과는 순번으로 버린다.
    func wipe() {
        epoch += 1
        for task in tasks.values { task.cancel() }
        tasks = [:]
        images.removeAllObjects()
        originals.removeAllObjects()
        if !states.isEmpty { states = [:] }
        owner = nil
    }

    private func adopt(_ owner: String) {
        guard self.owner != owner else { return }
        wipe()
        self.owner = owner
    }
}

/// 말풍선 · 신고 시트 · 신고함이 사진을 그리는 데 쓰는 묶음(캐시 + 받기 문 + 크게 보기 문). 뷰는 스토어를 몰라도 된다.
@MainActor
struct MessagePhotoBubbleContext {
    let images: MessagePhotoImageCache
    let owner: String?
    let request: @MainActor (String) -> Void
    let retry: @MainActor (String) -> Void
    let open: @MainActor (MessageHistoryEntry, MessagePhotoAttachment) -> Void

    func image(for path: String) -> CGImage? { images.image(for: path, owner: owner) }
    func state(for path: String) -> MessagePhotoLoadState? { images.state(for: path, owner: owner) }
}

// MARK: - 스토어

@MainActor
extension WorkTimerStore {
    /// 머리 변화 뒤 사진 칸 조회를 모으는 시간(초). 도착이 몰려도 한 번이다.
    nonisolated static let messagePhotoMetaDebounceSeconds: TimeInterval = 0.4
    /// 머리 시각은 초 단위 반올림이다 — 덮은 창의 아래 끝을 이만큼 너그럽게 본다.
    nonisolated static let messagePhotoCoverSlack: TimeInterval = 1
    /// 연결 실패 문구(글 보내기와 같은 문장).
    nonisolated static let messagePhotoUnstableNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"

    // MARK: 파생값(화면이 읽는 것)

    /// [사진] 버튼이 서는가 — 로그인 · 상대 있음 · 이 세션에 문이 닫혀 있지 않음.
    var showsMessagePhotoButton: Bool {
        session != nil && selectedMessagePeerID != nil && !messagePhotoSendClosed
    }

    /// 지금 사진을 고르거나 보낼 수 있는가 — 이모티콘과 **같은 세 조건**(`canSendStickerNow`) + 문 + 준비 중 아님(두 겹 게이트의 스토어 쪽).
    var canSendPhotoNow: Bool {
        showsMessagePhotoButton && canSendStickerNow && !messagePhotoPreparing
    }

    /// 열린 대화의 고른 사진(다른 사람에게 고른 사진은 이 대화에 안 선다).
    var selectedMessagePhotoDraft: MessagePhotoDraft? {
        guard let draft = messagePhotoDraft, draft.peer == selectedMessagePeerID else { return nil }
        return draft
    }

    /// 열린 대화의 크게 보기.
    var selectedMessagePhotoViewer: MessagePhotoViewerItem? {
        guard let viewer = messagePhotoViewer, viewer.peerID == selectedMessagePeerID else { return nil }
        return viewer
    }

    /// 대화 자리를 덮개가 쓰는가(미리 보기 · 크게 보기 · 준비 중) — 대화는 보이스오버에서 내려간다.
    var messagePhotoOverlayShown: Bool {
        selectedMessagePhotoDraft != nil || selectedMessagePhotoViewer != nil || messagePhotoPreparing
    }

    /// 그릴 줄에 사진을 얹는다(①). 머리 줄은 사진 칸 표에서, 지난 쪽 줄은 이미 실려 있다. id · 순서 · 읽음은 그대로다.
    func messagePhotoDisplayed(_ entries: [MessageHistoryEntry]) -> [MessageHistoryEntry] {
        guard let peer = selectedMessagePeerID, let meta = messagePhotoMeta[peer], !meta.isEmpty else { return entries }
        return entries.map { entry in
            guard entry.photo == nil, let known = meta[entry.id] else { return entry }
            return entry.withPhoto(known.attachment, caption: known.caption)
        }
    }

    /// 뷰가 사진을 그리는 묶음.
    var messagePhotoContext: MessagePhotoBubbleContext {
        MessagePhotoBubbleContext(
            images: messagePhotoImages,
            owner: session?.userID,
            request: { [weak self] path in self?.requestMessagePhotoImage(path) },
            retry: { [weak self] path in self?.retryMessagePhotoImage(path) },
            open: { [weak self] entry, photo in self?.openMessagePhotoViewer(entry, photo: photo) }
        )
    }

    /// 그 경로의 그림(이 계정 것만 · 없으면 nil).
    func messagePhotoImage(for path: String) -> CGImage? {
        messagePhotoImages.image(for: path, owner: session?.userID)
    }

    /// 사진 칸 조회가 쉬고 있는가(시험 · 부정형 단언 앞).
    var messagePhotoMetaIdle: Bool {
        messagePhotoRuntime.inFlight.isEmpty && messagePhotoRuntime.scheduled == nil
    }

    // MARK: 사진 칸 — 묻기(②)

    /// 사람이 대화를 열었다(`openMessagePanel` 이 부른다). 닫힌 문 · 함수 없음 숨김을 되돌리고, 다른 사람의 사진 상태를 걷고, 한 번 묻는다.
    func armMessagePhotoMeta(for peer: String) {
        if messagePhotoSendClosed { messagePhotoSendClosed = false }
        if messagePhotoMetaAvailable == false { messagePhotoMetaAvailable = nil }
        if messagePhotoRuntime.armedPeer != peer {
            clearMessagePhotoConversation()
        }
        messagePhotoRuntime.armedPeer = peer
        startMessagePhotoMetaFetch(peer: peer)
    }

    /// 대화 화면을 떠난다(`closeMessagePanel` 이 부른다). 사진 칸 · 고른 사진 · 크게 보기를 걷고 날던 조회를 버린다. 그림 캐시는 남는다.
    func clearMessagePhotoConversation() {
        messagePhotoRuntime.token += 1
        messagePhotoRuntime.scheduled?.cancel()
        messagePhotoRuntime.scheduled = nil
        messagePhotoRuntime.inFlight = []
        messagePhotoRuntime.trailing = []
        messagePhotoRuntime.coveredIDs = [:]
        messagePhotoRuntime.coveredFloor = [:]
        messagePhotoRuntime.armedPeer = nil
        if !messagePhotoMeta.isEmpty { messagePhotoMeta = [:] }
        if messagePhotoViewer != nil { messagePhotoViewer = nil }
        cancelMessagePhotoDraft()
    }

    /// 로그아웃(`clearPersistedSession`). 사진 상태 전부 + **그림 캐시**를 비운다.
    func resetMessagePhotoState() {
        clearMessagePhotoConversation()
        messagePhotoRuntime = MessagePhotoRuntime()
        messagePhotoMetaAvailable = nil
        messagePhotoSendClosed = false
        messagePhotoImages.wipe()
    }

    /// 열린 대화의 머리가 바뀌었다(이력 응답 · 즉시 도착). 사진 칸을 모르는 **받은** 줄이 있으면 합쳐서 한 번 묻는다.
    func noteMessageHeadChangedForPhotos() {
        guard session != nil, isMessagePanelVisible, let peer = messagePhotoRuntime.armedPeer,
              peer == selectedMessagePeerID, messagePhotoMetaAvailable != false
        else { return }
        guard !uncoveredMessagePhotoCandidates(peer: peer).isEmpty else { return }
        if messagePhotoRuntime.inFlight.contains(peer) {
            messagePhotoRuntime.trailing.insert(peer)
            return
        }
        scheduleMessagePhotoMetaFetch(peer: peer)
    }

    /// 머리의 받은 줄 중 아직 안 물어본 것(덮은 창 안의 것만 — 창보다 옛 줄은 [이전 대화 더 보기]가 사진을 싣는다).
    func uncoveredMessagePhotoCandidates(peer: String) -> [String] {
        let covered = messagePhotoRuntime.coveredIDs[peer] ?? []
        let floor = messagePhotoRuntime.coveredFloor[peer]?.addingTimeInterval(-Self.messagePhotoCoverSlack)
        return messageHistory.compactMap { entry in
            guard entry.peerUserID == peer, !entry.isMine, !covered.contains(entry.id) else { return nil }
            if let floor, entry.createdAt < floor { return nil }
            return entry.id
        }
    }

    /// 합치기 잠 뒤에 묻는다(하나만 잔다).
    private func scheduleMessagePhotoMetaFetch(peer: String) {
        guard messagePhotoRuntime.scheduled == nil else { return }
        let token = messagePhotoRuntime.token
        messagePhotoRuntime.scheduled = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.messagePhotoMetaDebounceSleep(Self.messagePhotoMetaDebounceSeconds)
            guard token == self.messagePhotoRuntime.token else { return }
            self.messagePhotoRuntime.scheduled = nil
            guard !self.uncoveredMessagePhotoCandidates(peer: peer).isEmpty else { return }
            self.startMessagePhotoMetaFetch(peer: peer)
        }
    }

    /// 조회를 띄운다(상대마다 하나 — 날고 있으면 "끝나면 한 번 더"로 접는다).
    private func startMessagePhotoMetaFetch(peer: String) {
        guard session != nil, messagePhotoMetaAvailable != false else { return }
        guard !messagePhotoRuntime.inFlight.contains(peer) else {
            messagePhotoRuntime.trailing.insert(peer)
            return
        }
        messagePhotoRuntime.inFlight.insert(peer)
        let asked = uncoveredMessagePhotoCandidates(peer: peer)
        let token = messagePhotoRuntime.token
        let generation = sessionGeneration
        Task { @MainActor in
            await performLoadMessagePhotoMeta(peer: peer, asked: asked, token: token, generation: generation)
        }
    }

    /// 지금 이 응답이 아직 이 화면의 것인가(세대 · 순번 · 상대). 상대는 **읽기만** 한다.
    private func isCurrentMessagePhotoRequest(peer: String, token: Int, generation: Int) -> Bool {
        generation == sessionGeneration && token == messagePhotoRuntime.token && messagePhotoRuntime.armedPeer == peer
    }

    /// `message_page(peer, null, null, 30)` 한 번 → 사진 칸을 배운다. 화면이 그대로일 때만 반영한다.
    private func performLoadMessagePhotoMeta(peer: String, asked: [String], token: Int, generation: Int) async {
        guard let me = session?.userID else {
            if token == messagePhotoRuntime.token { messagePhotoRuntime.inFlight.remove(peer) }
            return
        }
        do {
            let page = try await withSessionRetry { activeSession in
                try await service.fetchMessagePage(
                    accessToken: activeSession.accessToken,
                    peer: peer,
                    me: me,
                    before: nil,
                    limit: MessagePhotoText.metaPageLimit
                )
            }
            guard isCurrentMessagePhotoRequest(peer: peer, token: token, generation: generation) else { return }
            messagePhotoRuntime.inFlight.remove(peer)
            if messagePhotoMetaAvailable != true { messagePhotoMetaAvailable = true }
            absorbMessagePhotoMeta(page.entries, peer: peer)
            var covered = messagePhotoRuntime.coveredIDs[peer] ?? []
            covered.formUnion(page.rowIDs)
            covered.formUnion(asked)
            messagePhotoRuntime.coveredIDs[peer] = covered
            // 꽉 찬 쪽이면 그 쪽의 가장 오래된 줄이 덮은 창의 아래 끝이다(그보다 옛 머리 줄은 묻지 않는다). 덜 찼으면 끝까지 덮었다.
            if page.rowCount >= page.limit, let oldest = page.oldestCursor {
                messagePhotoRuntime.coveredFloor[peer] = Date(timeIntervalSince1970: TimeInterval(oldest.epochMicros) / 1_000_000)
            } else {
                messagePhotoRuntime.coveredFloor[peer] = nil
            }
            if messagePhotoRuntime.trailing.remove(peer) != nil, !uncoveredMessagePhotoCandidates(peer: peer).isEmpty {
                scheduleMessagePhotoMetaFetch(peer: peer)
            }
        } catch {
            if case .cancelled = classifyAuthError(error) {
                if token == messagePhotoRuntime.token { messagePhotoRuntime.inFlight.remove(peer) }
                return
            }
            guard isCurrentMessagePhotoRequest(peer: peer, token: token, generation: generation) else { return }
            messagePhotoRuntime.inFlight.remove(peer)
            messagePhotoRuntime.trailing.remove(peer)
            if let serviceError = error as? SupabaseWorkServiceError, Self.isMissingMessageReadFunction(serviceError) {
                // 함수가 없는 서버 — 다음 패널 열기까지 안 묻는다(사진 줄은 글로 그린다).
                messagePhotoMetaAvailable = false
            } else {
                // 일시 실패 — 지금 아는 받은 줄은 물어본 것으로 친다(같은 줄로 다시 묻는 고리가 없게). 다음 대화 열기가 다시 묻는다.
                var covered = messagePhotoRuntime.coveredIDs[peer] ?? []
                covered.formUnion(asked)
                covered.formUnion(uncoveredMessagePhotoCandidates(peer: peer))
                messagePhotoRuntime.coveredIDs[peer] = covered
            }
        }
    }

    /// 사진이 실린 줄(지난 쪽 · 사진 칸 조회)을 사진 칸 표에 넣는다. 사진 없는 줄은 건드리지 않는다.
    func absorbMessagePhotoMeta(_ entries: [MessageHistoryEntry], peer: String) {
        var map = messagePhotoMeta[peer] ?? [:]
        var changed = false
        for entry in entries {
            guard let photo = entry.photo else { continue }
            let meta = MessagePhotoMeta(attachment: photo, caption: entry.photoCaption)
            if map[entry.id] != meta {
                map[entry.id] = meta
                changed = true
            }
        }
        if changed { messagePhotoMeta[peer] = map }
    }

    // MARK: 고르기(⑤ — 열기 창 · 붙여넣기)

    /// 열기 창에서 고른 파일.
    func pickMessagePhoto(fileURL: URL) {
        prepareMessagePhoto { MessagePhotoEncoder.encode(fileURL: fileURL) }
    }

    /// 붙여넣기의 그림 자료.
    func pickMessagePhoto(imageData: Data) {
        prepareMessagePhoto { MessagePhotoEncoder.encode(data: imageData) }
    }

    /// ⌘V(입력칸 붙여넣기 갈고리). 그림이면 사진으로 받고 true(글 붙여넣기를 건너뛴다), 아니면 false(평소 붙여넣기).
    @discardableResult
    func pasteMessagePhoto(from pasteboard: NSPasteboard) -> Bool {
        guard showsMessagePhotoButton, let source = MessagePhotoPasteboard.source(from: pasteboard) else { return false }
        switch source {
        case .file(let url): pickMessagePhoto(fileURL: url)
        case .data(let data): pickMessagePhoto(imageData: data)
        }
        return true
    }

    /// 고른 사진을 떼어 낸 작업에서 줄인 뒤 미리 보기 덮개에 세운다. 못 보내는 상태면 사유를 한 줄 남기고 아무것도 안 한다.
    func prepareMessagePhoto(_ work: @escaping @Sendable () -> (MessagePhotoEncoded, MessagePhotoImageBox)?) {
        guard canSendPhotoNow, let peer = selectedMessagePeerID else {
            if let block = messageFocusBlock {
                messageNotice = block.messageText
            } else if isSendingMessage {
                messageNotice = AingStickerText.sendingNowNotice
            }
            return
        }
        messagePhotoRuntime.prepareToken += 1
        let token = messagePhotoRuntime.prepareToken
        let generation = sessionGeneration
        messagePhotoPreparing = true
        Task { @MainActor in
            let prepared = await Task.detached(priority: .userInitiated) { () -> (MessagePhotoEncoded, MessagePhotoImageBox)? in
                guard let made = work() else { return nil }
                let (encoded, full) = made
                let preview = MessagePhotoEncoder.decodeForDisplay(encoded.data, maxPixelSize: MessagePhotoImageCache.displayPixels)
                return (encoded, preview ?? full)
            }.value
            guard generation == sessionGeneration, token == messagePhotoRuntime.prepareToken else { return }
            messagePhotoPreparing = false
            guard let prepared else {
                messageNotice = MessagePhotoText.unreadableNotice
                return
            }
            guard selectedMessagePeerID == peer else { return }
            messagePhotoDraft = MessagePhotoDraft(id: MessagePhotoPath.newID(), peer: peer, encoded: prepared.0, preview: prepared.1)
        }
    }

    /// [취소] — 고른 사진을 버린다(줄이던 작업의 결과도 버린다).
    func cancelMessagePhotoDraft() {
        messagePhotoRuntime.prepareToken += 1
        if messagePhotoPreparing { messagePhotoPreparing = false }
        if messagePhotoDraft != nil { messagePhotoDraft = nil }
    }

    // MARK: 보내기(③)

    /// 미리 보기의 [보내기]. 설명은 **지금 입력칸의 글**이다(성공하면 글을 보낸 것처럼 비운다 · 실패하면 글과 사진이 남는다).
    func sendMessagePhotoDraft() {
        guard let draft = selectedMessagePhotoDraft, let me = session?.userID else { return }
        guard canSendPhotoNow else {
            if let block = messageFocusBlock { messageNotice = block.messageText }
            return
        }
        let caption: String?
        switch MessageBody.validate(messageDraft) {
        case .ok(let normalized): caption = normalized
        case .empty: caption = nil
        case .tooLong(let maxLength):
            messageNotice = Self.messageTooLongNotice(maxLength: maxLength)
            return
        }
        clearBlockReportNotice(on: .message)
        isSendingMessage = true
        let generation = sessionGeneration
        let focusIntentAtRequest = focusIntentSerial
        let path = MessagePhotoPath.uploadPath(owner: me, id: draft.id)
        Task { @MainActor in
            // 왕복 잠금은 글과 같은 칸이다(사진을 보내는 동안 글 · 이모티콘도 안 나간다 — 두 전송이 겹치지 않게).
            defer { if generation == sessionGeneration { isSendingMessage = false } }
            guard let response = await deliverMessagePhoto(draft: draft, path: path, caption: caption, generation: generation) else {
                return
            }
            let confirmedAt: Date? = if let raw = response.send.createdAt { await service.parseDate(raw) } else { nil }
            guard generation == sessionGeneration else { return }
            switch MessagePhotoSendOutcome(response: response) {
            case .message(let outcome):
                if outcome == .ok {
                    recordSentMessagePhoto(draft: draft, path: path, caption: caption, response: response, owner: me)
                }
                applyMessageSendOutcome(
                    outcome,
                    response: response.send,
                    to: draft.peer,
                    sentBody: caption ?? MessageNoticeText.photoFallbackBody,
                    confirmedAt: confirmedAt,
                    // 설명을 입력칸에서 가져갔을 때만 비운다(빈 칸이었으면 왕복 중에 친 글을 지우지 않는다).
                    clearsDraftOnSuccess: caption != nil,
                    focusIntentAtRequest: focusIntentAtRequest
                )
            case .unsupportedClient(let doorOpen):
                closeMessagePhotoDoor(notice: doorOpen == true ? MessagePhotoText.doorOpenNotice : MessagePhotoText.doorClosedNotice)
            case .invalidPhoto:
                // 그 이름은 서버가 안 받는다 — 같은 사진을 **새 이름**으로 다시 올리게 둔다(사진은 남는다).
                renewMessagePhotoDraft(draft)
                messageNotice = MessagePhotoText.invalidPhotoNotice
            case .photoMissing:
                markMessagePhotoDraft(draft, uploaded: false)
                messageNotice = MessagePhotoText.uploadFailedNotice
            }
        }
    }

    /// 올리기(필요하면) → RPC. nil 이면 문구까지 여기서 끝냈다(또는 취소 · 세대 변경).
    private func deliverMessagePhoto(
        draft: MessagePhotoDraft, path: String, caption: String?, generation: Int
    ) async -> SendPhotoMessageResponse? {
        if !draft.uploaded {
            switch await uploadMessagePhotoForSend(draft: draft, path: path, generation: generation) {
            case .uploaded: markMessagePhotoDraft(draft, uploaded: true)
            // 거절 — 그 경로로 RPC 를 한 번 불러 사유를 가른다(문 닫힘 · 파일 없음 · 그 밖은 글과 같은 문구).
            case .refused: break
            case .handled: return nil
            }
        }
        let request = SendPhotoMessageRequest(
            to: draft.peer,
            path: path,
            width: draft.encoded.pixelWidth,
            height: draft.encoded.pixelHeight,
            caption: caption,
            clientMessageID: draft.id
        )
        var retried = false
        while true {
            do {
                return try await withSessionRetry { activeSession in
                    try await service.sendPhotoMessage(accessToken: activeSession.accessToken, request: request)
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return nil }
                guard generation == sessionGeneration else { return nil }
                // 답을 못 받았다 — 같은 경로 · 같은 키로 한 번만 더(서버가 duplicate 로 한 줄에 접는다).
                if Self.isAmbiguousMessageSendFailure(error), !retried {
                    retried = true
                    await messageSendRetrySleep(Self.messageSendRetryDelaySeconds)
                    guard generation == sessionGeneration else { return nil }
                    continue
                }
                if let serviceError = error as? SupabaseWorkServiceError, Self.isMissingMessageReadFunction(serviceError) {
                    closeMessagePhotoDoor(notice: MessagePhotoText.doorClosedNotice)
                } else {
                    messageNotice = Self.messagePhotoUnstableNotice
                }
                return nil
            }
        }
    }

    private enum MessagePhotoUploadResult {
        case uploaded
        case refused
        case handled
    }

    /// 올리기 한 번(+ 답을 못 받으면 같은 이름으로 한 번 더). 409 는 우리 앞 시도가 올린 우리 파일이다(성공).
    private func uploadMessagePhotoForSend(
        draft: MessagePhotoDraft, path: String, generation: Int
    ) async -> MessagePhotoUploadResult {
        var retried = false
        while true {
            do {
                try await withSessionRetry { activeSession in
                    try await service.uploadMessagePhoto(accessToken: activeSession.accessToken, path: path, data: draft.encoded.data)
                }
                return .uploaded
            } catch PrivateStorageError.alreadyExists {
                return .uploaded
            } catch {
                if case .cancelled = classifyAuthError(error) { return .handled }
                guard generation == sessionGeneration else { return .handled }
                if Self.isAmbiguousMessageSendFailure(error), !retried {
                    retried = true
                    await messageSendRetrySleep(Self.messageSendRetryDelaySeconds)
                    guard generation == sessionGeneration else { return .handled }
                    continue
                }
                switch error {
                case PrivateStorageError.forbidden:
                    return .refused
                case PrivateStorageError.tooLarge:
                    messageNotice = MessagePhotoText.tooLargeNotice
                case SupabaseWorkServiceError.databaseSchemaMissing:
                    // 버킷이 없다 — 서버 2단계 전(아직 안 열린 기능).
                    closeMessagePhotoDoor(notice: MessagePhotoText.doorClosedNotice)
                default:
                    messageNotice = Self.messagePhotoUnstableNotice
                }
                return .handled
            }
        }
    }

    /// 보낸 내 사진을 그 자리에서 그린다: 사진 칸 표에 넣고(다음 이력이 같은 id 로 와도 사진이 남는다) 올린 JPEG 를 그림 캐시에 넣는다
    /// (내 사진은 받지 않는다). 고른 사진은 내린다.
    private func recordSentMessagePhoto(
        draft: MessagePhotoDraft, path: String, caption: String?, response: SendPhotoMessageResponse, owner: String
    ) {
        let attachment = response.attachment
            ?? MessagePhotoAttachment(path: path, width: draft.encoded.pixelWidth, height: draft.encoded.pixelHeight)
        if let attachment {
            messagePhotoImages.insert(draft.preview, data: draft.encoded.data, path: attachment.path, owner: owner)
            if let id = response.send.messageId, !id.isEmpty {
                var map = messagePhotoMeta[draft.peer] ?? [:]
                map[id] = MessagePhotoMeta(attachment: attachment, caption: caption)
                messagePhotoMeta[draft.peer] = map
                messagePhotoRuntime.coveredIDs[draft.peer, default: []].insert(id)
            }
        }
        if messagePhotoDraft?.id == draft.id { messagePhotoDraft = nil }
    }

    /// 문이 닫혀 있다(또는 함수 · 버킷이 없다) — 문구 한 줄, 고른 사진을 내리고 [사진] 버튼을 다음 패널 열기까지 숨긴다. 글 초안은 남는다.
    private func closeMessagePhotoDoor(notice: String) {
        messagePhotoSendClosed = true
        cancelMessagePhotoDraft()
        messageNotice = notice
    }

    private func markMessagePhotoDraft(_ draft: MessagePhotoDraft, uploaded: Bool) {
        guard var current = messagePhotoDraft, current.id == draft.id, current.uploaded != uploaded else { return }
        current.uploaded = uploaded
        messagePhotoDraft = current
    }

    /// 같은 사진 · 새 이름(서버가 그 이름을 안 받는다 — invalid_photo).
    private func renewMessagePhotoDraft(_ draft: MessagePhotoDraft) {
        guard let current = messagePhotoDraft, current.id == draft.id else { return }
        messagePhotoDraft = MessagePhotoDraft(
            id: MessagePhotoPath.newID(), peer: current.peer, encoded: current.encoded, preview: current.preview
        )
    }

    // MARK: 그림 받기(④)

    /// 말풍선이 보일 때 그 사진을 받는다(경로마다 하나 · 실패 기억 · 시험 프로세스는 주입 없이 네트워크로 안 나간다).
    func requestMessagePhotoImage(_ path: String) {
        guard let owner = session?.userID, MessagePhotoPath.isServerShaped(path) else { return }
        if let loader = messagePhotoDataLoader {
            messagePhotoImages.load(path: path, owner: owner) { try await loader(path) }
            return
        }
        guard !CheckPanelVisibility.isRunningTests else { return }
        let generation = sessionGeneration
        messagePhotoImages.load(path: path, owner: owner) { [weak self] in
            guard let self, generation == self.sessionGeneration else { throw CancellationError() }
            return try await self.withSessionRetry { activeSession in
                try await self.service.fetchMessagePhotoData(accessToken: activeSession.accessToken, path: path)
            }
        }
    }

    /// 실패 칸을 사람이 눌렀다 — 한 번 다시 받는다(다시 받는 자리는 이것뿐이다).
    func retryMessagePhotoImage(_ path: String) {
        messagePhotoImages.forgetFailure(path: path)
        requestMessagePhotoImage(path)
    }

    /// [저장…] 에 쓸 바이트 — 받은 원본(내 사진은 올린 JPEG). 없으면 화면 그림을 JPEG 로 다시 굽는다(메타데이터 없음).
    func messagePhotoSaveData(path: String) -> Data? {
        let owner = session?.userID
        if let original = messagePhotoImages.originalData(for: path, owner: owner) { return original }
        guard let image = messagePhotoImages.image(for: path, owner: owner) else { return nil }
        return ImageDownscale.jpegData(image, quality: 0.9)
    }

    // MARK: 크게 보기

    func openMessagePhotoViewer(_ entry: MessageHistoryEntry, photo: MessagePhotoAttachment) {
        guard entry.peerUserID == selectedMessagePeerID else { return }
        messagePhotoViewer = MessagePhotoViewerItem(
            photo: photo, messageID: entry.id, peerID: entry.peerUserID, isMine: entry.isMine
        )
        requestMessagePhotoImage(photo.path)
    }

    func closeMessagePhotoViewer() {
        if messagePhotoViewer != nil { messagePhotoViewer = nil }
    }

    // MARK: 운영자 신고함 — 신고된 사진 경로

    /// 신고 목록을 받은 **뒤** 한 번에 묻는다(처음 보는 id 만 · 운영자만 · 빈 목록이면 안 묻는다). 함수가 없는 서버면 사진 없이 그린다.
    func loadReportAdminPhotoPaths(for items: [ContentReportAdminItem], generation: Int) {
        guard session != nil, ultraUnlimited else { return }
        let ids = items.map(\.id).filter { !$0.isEmpty && !reportAdminPhotoChecked.contains($0) }
        guard !ids.isEmpty else { return }
        reportAdminPhotoChecked.formUnion(ids)
        Task { @MainActor in
            do {
                let paths = try await withSessionRetry { activeSession in
                    try await service.fetchReportAdminPhotoPaths(accessToken: activeSession.accessToken, ids: ids)
                }
                guard generation == sessionGeneration else { return }
                guard !paths.isEmpty else { return }
                var merged = reportAdminPhotoPaths
                for (id, path) in paths { merged[id] = path }
                if merged != reportAdminPhotoPaths { reportAdminPhotoPaths = merged }
            } catch {
                guard generation == sessionGeneration else { return }
                if let serviceError = error as? SupabaseWorkServiceError, Self.isMissingMessageReadFunction(serviceError) { return }
                // 일시 실패 — 다음 목록 조회가 다시 묻게 물어본 표에서 뺀다.
                reportAdminPhotoChecked.subtract(ids)
            }
        }
    }

    /// 신고함 사진 크게/작게(같은 행을 다시 누르면 접는다).
    func toggleReportAdminPhoto(_ reportID: String) {
        reportAdminPhotoEnlargedID = reportAdminPhotoEnlargedID == reportID ? nil : reportID
    }
}
