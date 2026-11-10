import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CheckCore

// MARK: - 제보 화면 캡처 — 값 · 이미지 준비(순수에 가까운 조각) (11-11)
//
// 캡처를 **어디서 얻는가**(계약 v2 §3): 사람이 고른 파일(NSOpenPanel) · 클립보드 붙여넣기 · 끌어다 놓기, 셋뿐이다.
// 사람이 시스템 도구(⌘⇧4 · ⌘⌃⇧4)로 직접 찍는다 — 그 도구가 자기 권한을 갖고 있어 **이 앱은 화면 기록 권한을 묻지 않는다**
// (docs/privacy.md 가 그 권한을 금한다). 이 앱이 스스로 화면을 찍는 길(ScreenCaptureKit 등)을 이 파일에 들이지 마라.
//
// ★ 캡처는 남의 이름·대화가 찍혀 있을 수 있다. 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라. 디스크에 쓰지도 않는다
//   (받아 둔 그림은 스토어 메모리에만 있고 로그아웃 때 비운다).

/// 보내기 탭에 붙여 둔 캡처 한 장. 같음은 **id** 로 잰다(그림 바이트를 비교하지 않는다).
struct FeedbackShotDraft: Identifiable, Equatable {
    let id: UUID
    /// 올릴 JPEG(긴 변 ≤ 1600px).
    let jpeg: Data
    /// 화면에 그릴 미리보기.
    let preview: NSImage
    /// 줄인 뒤의 픽셀 크기(`feedback_attach_shot` 의 p_width · p_height).
    let pixelSize: CGSize

    var pixelWidth: Int { max(1, Int(pixelSize.width.rounded())) }
    var pixelHeight: Int { max(1, Int(pixelSize.height.rounded())) }

    static func == (lhs: FeedbackShotDraft, rhs: FeedbackShotDraft) -> Bool { lhs.id == rhs.id }
}

/// 캡처를 못 받은 까닭. 문구가 다르다(지워진 것은 다시 눌러도 소용없다).
enum FeedbackShotLoadFailure: Equatable {
    case missing
    case failed

    var text: String {
        switch self {
        case .missing: return FeedbackShotText.missing
        case .failed: return FeedbackShotText.loadFailed
        }
    }
}

/// 행이 그릴 캡처 칸 하나의 상태. **뷰는 이 값만 읽는다** — 받기(네트워크)는 스토어가 사람이 누른 자리에서만 한다.
enum FeedbackShotCell: Equatable {
    /// 아직 안 받았다(누르면 받는다).
    case idle
    case loading
    case image(NSImage)
    case failed(FeedbackShotLoadFailure)
}

/// 크게 보기(패널 위 덮개)가 무엇을 보고 있나.
struct FeedbackShotViewerState: Equatable {
    enum Source: Equatable {
        /// 보내기 탭에 붙여 둔(아직 안 보낸) 캡처 — 보내기 전에 남의 이름이 찍혔는지 확인하는 길.
        case draft
        /// 보낸 제보(내 것 · 운영자는 남의 것)의 캡처. 제보 id(소문자).
        case report(String)
    }

    var source: Source
    var index: Int
}

/// 보낸 뒤 캡처 한 장의 결과(올리기 + 붙이기). 갈래마다 다음 캡처를 계속할지가 다르다.
enum FeedbackShotStep: Equatable {
    case attached
    /// 일시 실패(5xx · 네트워크 · 모르는 status) — 다음 캡처는 계속한다.
    case failed
    /// 저장소가 정책으로 거절했고(한 시간 지남 · 폴더 가득 등) 서버도 문 닫힘/상한을 말하지 않았다 — 다음 것도 같은 벽이라 멈춘다.
    case refused
    /// 서버 문이 닫혔다(`unsupported_client`). 멈춘다.
    case doorClosed
    /// 제보 하나의 상한을 넘었다. 멈춘다.
    case tooMany(Int)
    /// 서버에 그 함수 · 버킷이 없다(배포 전). 멈추고 입구를 숨긴다.
    case missing

    var stops: Bool {
        switch self {
        case .attached, .failed: return false
        case .refused, .doorClosed, .tooMany, .missing: return true
        }
    }
}

/// 보낸 뒤 캡처들의 결과를 세어 안내 한 줄을 고른다(순수).
struct FeedbackShotTally: Equatable {
    let total: Int
    private(set) var attached = 0
    private(set) var stop: FeedbackShotStep?

    init(total: Int) {
        self.total = total
    }

    mutating func record(_ step: FeedbackShotStep) {
        if step == .attached { attached += 1 }
        if step.stops, stop == nil { stop = step }
    }

    /// 못 붙인 수(멈춰서 시도도 못 한 것까지).
    var failed: Int { max(0, total - attached) }

    /// 안내 한 줄. 다 붙었으면 예전 성공 문구 그대로다(초록).
    var notice: String {
        switch stop {
        case .doorClosed?, .missing?:
            return FeedbackShotText.sentShotsDoorClosed
        case .tooMany(let max)?:
            return FeedbackShotText.sentShotsTooMany(max)
        default:
            break
        }
        if failed == 0 { return FeedbackText.sendSuccess }
        if attached == 0 { return FeedbackShotText.sentShotsFailed }
        return FeedbackShotText.sentSomeShotsFailed(failed)
    }
}

/// 캡처 이미지를 올릴 모양으로 만든다.
enum FeedbackShotImage {
    /// 붙일 재료.
    enum Source {
        /// 이미지 바이트(⌘⌃⇧4 가 클립보드에 넣는 PNG · TIFF, 끌어다 놓은 그림).
        case data(Data)
        /// 이미지 파일(고르기 · Finder 에서 복사하거나 끌어온 파일).
        case file(URL)
    }

    /// 줄인 결과. 바이트만 담는다(백그라운드에서 만들어 메인으로 넘긴다).
    enum Encoded: Equatable, Sendable {
        case jpeg(Data)
        case unreadable
        case tooLarge
    }

    static var maxDimension: CGFloat { CGFloat(FeedbackShotRules.maxDimension) }

    /// 이미지 바이트 → 긴 변 1600px JPEG. 너무 크면 한 번 더 세게 줄이고, 그래도 크면 `.tooLarge`.
    nonisolated static func encode(imageData: Data) -> Encoded {
        guard let first = CheckAvatarView.downscaledJPEGData(
            from: imageData, maxDimension: maxDimension, compression: CGFloat(FeedbackShotRules.jpegQuality)
        ) else { return .unreadable }
        if first.count <= FeedbackShotRules.maxUploadBytes { return .jpeg(first) }
        guard let second = CheckAvatarView.downscaledJPEGData(
            from: imageData, maxDimension: maxDimension, compression: CGFloat(FeedbackShotRules.fallbackJPEGQuality)
        ), second.count <= FeedbackShotRules.maxUploadBytes else { return .tooLarge }
        return .jpeg(second)
    }

    /// 파일 → 같은 규칙. 파일을 통째로 읽지 않는다(ImageIO 가 필요한 만큼만 읽는다 — 아바타 경로와 같다).
    nonisolated static func encode(fileURL: URL) async -> Encoded {
        guard let first = await CheckAvatarView.decodeDownscaledJPEGData(
            from: fileURL, maxDimension: maxDimension, compression: CGFloat(FeedbackShotRules.jpegQuality)
        ) else { return .unreadable }
        if first.count <= FeedbackShotRules.maxUploadBytes { return .jpeg(first) }
        guard let second = await CheckAvatarView.decodeDownscaledJPEGData(
            from: fileURL, maxDimension: maxDimension, compression: CGFloat(FeedbackShotRules.fallbackJPEGQuality)
        ), second.count <= FeedbackShotRules.maxUploadBytes else { return .tooLarge }
        return .jpeg(second)
    }

    /// 어느 갈래든 백그라운드에서 줄인다(메인 액터를 멈추지 않는다).
    nonisolated static func encode(_ source: Source) async -> Encoded {
        switch source {
        case .file(let url):
            return await encode(fileURL: url)
        case .data(let data):
            return await Task.detached(priority: .userInitiated) { encode(imageData: data) }.value
        }
    }

    /// 줄인 JPEG → 붙일 캡처(미리보기 포함). 그림으로 못 읽으면 nil.
    @MainActor
    static func draft(fromJPEG jpeg: Data) -> FeedbackShotDraft? {
        guard let image = NSImage(data: jpeg) else { return nil }
        return FeedbackShotDraft(id: UUID(), jpeg: jpeg, preview: image, pixelSize: pixelSize(of: jpeg) ?? image.size)
    }

    /// JPEG 의 실제 픽셀 크기(NSImage.size 는 포인트라 72dpi 가 아니면 다르다).
    nonisolated static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// 클립보드에서 이미지를 찾는다. 바이트(PNG → TIFF → JPEG)를 먼저, 없으면 이미지 파일을 본다. 없으면 nil.
    @MainActor
    static func source(in pasteboard: NSPasteboard) -> Source? {
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)]
        for type in types {
            if let data = pasteboard.data(forType: type), !data.isEmpty { return .data(data) }
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], let url = urls.first {
            return .file(url)
        }
        return nil
    }

    /// 끌어다 놓기가 받는 종류(파일 URL · 그림 바이트).
    static let dropTypes: [UTType] = [.fileURL, .image]

    /// 끌어다 놓은 것 하나 → 재료. 파일이면 이미지 파일만, 아니면 그림 바이트. 못 읽으면 nil.
    /// 메인 액터에 둔다 — 제공자(`NSItemProvider`)를 액터 밖으로 넘기지 않고, 완료 처리기는 값(URL · Data)만 돌려준다.
    @MainActor
    static func source(from provider: NSItemProvider) async -> Source? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    continuation.resume(returning: (object as? NSURL) as URL?)
                }
            }
            guard let url, url.isFileURL else { return nil }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            guard type?.conforms(to: .image) ?? true else { return nil }
            return .file(url)
        }
        for type in [UTType.png, .tiff, .jpeg, .heic, .image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data, !data.isEmpty { return .data(data) }
        }
        return nil
    }

    /// 파일 고르기 창에서 받는 이미지 종류(계약 v2: png · jpeg · heic · tiff).
    static let pickableTypes: [UTType] = [.png, .jpeg, .heic, .tiff]
}
