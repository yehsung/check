import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Avatar view

/// 원형 아바타. `avatarURL`이 있으면 비동기 원격 이미지를 원형으로 그리고,
/// 없거나 로딩 중/실패 시엔 이름 이니셜 + 해시색 폴백을 보여 준다.
/// 행 아바타 기준 크기는 26pt. 레티나 선명도를 위해 원본 비트맵을 그대로 고해상 보간한다.
struct CheckAvatarView: View {
    let name: String
    var avatarURL: URL? = nil
    var size: CGFloat = 26

    var body: some View {
        if let avatarURL {
            RemoteAvatarView(name: name, url: avatarURL, size: size)
        } else {
            InitialAvatar(name: name, size: size)
        }
    }
}

// MARK: - Initial (fallback) avatar

/// 이름 이니셜 + 해시색 원형 아바타. 원격 이미지가 없거나 로드 실패했을 때의 폴백이며,
/// `CheckAvatarView`가 폴백으로 재사용한다.
struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 30

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    var body: some View {
        let color = CheckTheme.avatarColor(for: name)
        Text(initial)
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Remote avatar

/// URL 기반 원형 이미지 아바타.
/// - file URL 또는 캐시 hit은 동기 로드해 스냅샷/첫 프레임에서도 즉시 표시된다.
/// - http(s) URL은 `URLSession`으로 비동기 로드하고 성공 시 `NSCache`에 저장한다.
/// - 로딩 중/실패 시에는 이니셜 폴백을 유지한다.
private struct RemoteAvatarView: View {
    let name: String
    let url: URL
    let size: CGFloat

    @State private var loaded: NSImage?

    var body: some View {
        Group {
            if let image = loaded ?? AvatarImageCache.shared.synchronousImage(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            } else {
                InitialAvatar(name: name, size: size)
            }
        }
        .task(id: url) {
            loaded = await AvatarImageCache.shared.image(for: url)
        }
    }
}

/// URL별 아바타 이미지 캐시. 동기 경로(file URL·캐시 hit)와 비동기 네트워크 로드를 함께 제공한다.
/// 내부 저장소는 `NSCache`로 스레드 세이프하다.
final class AvatarImageCache: @unchecked Sendable {
    static let shared = AvatarImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {}

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// 캐시 hit 또는 file URL은 즉시 이미지를 돌려준다(스냅샷/첫 프레임 대응). 그 외엔 nil.
    func synchronousImage(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard url.isFileURL, let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// 캐시 → file URL 동기 로드 → http(s) 비동기 로드 순으로 이미지를 얻는다. 실패 시 nil.
    func image(for url: URL) async -> NSImage? {
        if let image = synchronousImage(for: url) {
            return image
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - Editable avatar (own row)

/// 내 행 전용 아바타. hover 시 카메라 배지를 덧씌우고, 클릭하면 이미지 파일 선택 패널을 연다.
/// 선택된 이미지는 최장변 256px JPEG로 다운스케일해 `onPick(Data)`로 전달한다.
struct EditableAvatarView: View {
    let name: String
    var avatarURL: URL? = nil
    var size: CGFloat = 26
    let onPick: (Data) -> Void

    @State private var hovering = false

    var body: some View {
        CheckAvatarView(name: name, avatarURL: avatarURL, size: size)
            .overlay {
                if hovering {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.48))
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)
                }
            }
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .onTapGesture { presentPicker() }
            .help("아바타 변경")
    }

    // 공개 이미지 타입(png/jpeg/heic)만 허용하는 열기 패널. 취소·비이미지·로드 실패는 조용히 무시.
    private func presentPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "선택"
        panel.message = "아바타로 사용할 이미지를 선택하세요"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url),
              let data = CheckAvatarView.downscaledJPEGData(from: image) else {
            return
        }
        onPick(data)
    }
}

// MARK: - Downscale (pure)

extension CheckAvatarView {
    /// 원본 픽셀 크기를 최장변이 `maxDimension`을 넘지 않도록 종횡비를 유지해 축소한다.
    /// 최장변이 이미 `maxDimension` 이하면 원본 크기를 그대로 돌려준다(확대하지 않음).
    /// 순수 함수 — 그래픽 컨텍스트 없이 크기 계산만 하므로 단위 테스트 대상이다.
    static func downscaledPixelSize(for source: CGSize, maxDimension: CGFloat = 256) -> CGSize {
        let longest = max(source.width, source.height)
        guard longest > maxDimension, longest > 0 else {
            return source
        }
        let scale = maxDimension / longest
        return CGSize(
            width: max(1, (source.width * scale).rounded()),
            height: max(1, (source.height * scale).rounded())
        )
    }

    /// 이미지를 최장변 256px로 다운스케일한 JPEG(압축 0.85) Data로 변환한다. 실패 시 nil.
    static func downscaledJPEGData(from image: NSImage, maxDimension: CGFloat = 256, compression: CGFloat = 0.85) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        let sourcePixels = CGSize(width: source.pixelsWide, height: source.pixelsHigh)
        let target = downscaledPixelSize(for: sourcePixels, maxDimension: maxDimension)

        // 원본 크기와 같으면 재드로 없이 그대로 JPEG 인코딩한다.
        if target == sourcePixels {
            return source.representation(using: .jpeg, properties: [.compressionFactor: compression])
        }

        guard let scaled = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        scaled.size = target

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
        source.draw(in: NSRect(origin: .zero, size: target))

        return scaled.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }
}
