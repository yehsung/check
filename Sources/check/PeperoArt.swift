import AppKit
import CheckCore
import Foundation
import ImageIO
import os

// MARK: - 빼빼로 아잉이 그림 저장소 (v0.3.77 — 굽지 않기, 이슬 `IsulArt` 와 같은 길)
//
// 대표가 다시 다듬을(그리고 상표 문제가 생기면 이름 없는 '11.11' 판으로 갈아 끼울) 그림은 **상자 인쇄 판**(3D 상자 바깥 벽 — `PeperoDecor` 가 굽는다)과
// **초상 두 장**이다(메모리 assets-users-iterate-must-not-be-baked-in). 순서는 이슬과 같다:
//   1) 디스크 캐시(`Caches/check.game-art/pepero/{box,neutral,negative}.png`) — 운영 Storage 에서 받은 것.
//   2) 번들 폴백(`aing_pepero-{box,neutral,negative}.png` — 그림 생성기 `scripts/make-pepero-aing.swift` 산출).
// 조건부 요청(ETag · Last-Modified)으로 `game-art/pepero/<이름>.png` 를 받아 캐시를 덮는다 — 200 = 바꿈 · 304 = 그대로 · 없는 개체(404, 또는
// 400 + 본문 not_found — `IsulArt.isStorageNotFound` 같은 판정) = 캐시 지우고 번들로 · 그 밖(본문 없는 400 · 5xx · 끊김 · 못 쓰는 그림) = 그대로.
// 받은 그림은 검사한다: 판은 **정사각 1024 불투명**(`PeperoDecor.sheetWidth` × `sheetHeight` — 띠 자리가 화소 행 번호라 크기가 다르면 어긋난다 ·
// 투명 화소가 있으면 상자 벽에 구멍처럼 검게 굽힌다), 초상은 **정사각 128px 이상**(번들 192²).
//
// 언제 받나 — 빼빼로를 그릴 일이 처음 생길 때 한 번(`url(_:)` 첫 조회가 연다 — 프로세스당 한 번, 이슬과 같은 결).
// 받은 그림은 **다음에 그리는 자리부터** 쓴다: 판은 다음에 세우는 3D 씬(착용 · 울트라 교체)부터 — 판 객체가 바뀌어 `PeperoAingFinish.decorNode`
// 가 다시 굽는다(받은 쪽이 메인 밖에서 미리 굽는다). 초상은 그 그림을 쥔 캐시(메뉴바 · 헤더 — `CheckMascotAssets`, 남의 아바타 — `AppUserAvatarArt`,
// 고르기 · 상점 카드 — `CharacterCardArt`, 받는 창 — `CheckCakeGiftWindowView`, 뽑기 창 — `CheckGachaWindowView`)의 빼빼로 몫을 비우고
// 관찰 값(`PeperoArtRevision`)을 올려 그 초상을 그린 SwiftUI 화면이 곧바로 다시 그린다. 이미 서 있는 3D 씬의 상자는 바꾸지 않는다.
// 시험 중엔 디스크 캐시도 네트워크도 타지 않는다(`CheckPanelVisibility.isRunningTests`).
// 운영 Storage 에 그림을 올리는 일은 이번 범위 밖이다(대표 승인 후) — 올리기 전까지 요청은 404 이고 번들 그대로 선다.
final class PeperoArt: @unchecked Sendable {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// 그림 종류. 이름이 곧 캐시 파일 이름 · Storage 경로 · 번들 이름의 꼬리다.
    enum Kind: String, CaseIterable, Sendable {
        case box, neutral, negative

        /// 번들 폴백 리소스 이름(확장자 png — `<id>-<꼬리>` 규약).
        var bundleName: String { "\(CharacterCatalog.peperoAingID)-\(rawValue)" }
        /// 캐시 파일 이름.
        var fileName: String { "\(rawValue).png" }
        /// Storage 버킷 `game-art` 안 경로.
        var remotePath: String { "pepero/\(fileName)" }
        /// 초상인가(바뀌면 초상 캐시를 비운다 — 판은 3D 만 쓴다).
        var isPortrait: Bool { self != .box }

        init(mood: CheckMascotAssets.Mood) {
            self = mood == .neutral ? .neutral : .negative
        }
    }

    /// 응답 → 할 일(이슬과 같은 어휘).
    typealias Outcome = IsulArt.Outcome

    /// 그림이 바뀌었다(바꿈 · 되돌림) — 메인에서 보낸다.
    static let didChange = Notification.Name("check.peperoArt.didChange")

    static let shared = PeperoArt()

    /// 시험 전용 갈아 끼우기(작업 지역값 — 그 시험 작업 안에서만 보인다).
    @TaskLocal static var testOverride: PeperoArt?

    /// 초상 조회 · 3D 판이 타는 저장소 — 앱은 언제나 `shared`, 시험은 `testOverride` 로 따로 저장소(임시 캐시 폴더)를 끼운다.
    static var current: PeperoArt { testOverride ?? shared }

    let cacheDirectory: URL
    let readsCache: Bool
    let usesNetwork: Bool
    private let bundleURL: @Sendable (Kind) -> URL?

    private let lock = NSLock()
    private var resolved: [Kind: URL] = [:]
    private var box: CGImage?
    private var boxDecoded = false
    private var refreshStarted = false

    init(cacheDirectory: URL = PeperoArt.defaultCacheDirectory,
         readsCache: Bool = !CheckPanelVisibility.isRunningTests,
         usesNetwork: Bool = !CheckPanelVisibility.isRunningTests,
         bundleURL: @escaping @Sendable (Kind) -> URL? = PeperoArt.bundledURL) {
        self.cacheDirectory = cacheDirectory
        self.readsCache = readsCache
        self.usesNetwork = usesNetwork
        self.bundleURL = bundleURL
    }

    // MARK: 위치(순수)

    static func remoteURL(_ kind: Kind) -> URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/game-art/\(kind.remotePath)")
    }

    static var defaultCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("check.game-art/pepero", isDirectory: true)
    }

    @Sendable static func bundledURL(_ kind: Kind) -> URL? {
        CheckResources.bundle.url(forResource: kind.bundleName, withExtension: GoldAingArt.resourceExtension)
    }

    func cacheFile(_ kind: Kind) -> URL {
        cacheDirectory.appendingPathComponent(kind.fileName)
    }

    func metaFile(_ kind: Kind) -> URL {
        cacheDirectory.appendingPathComponent("\(kind.rawValue).json")
    }

    // MARK: 판정(순수)

    /// 크기만으로 써도 되나 — 판은 정사각 `PeperoDecor.sheetWidth` × `sheetHeight`(1024²) 그대로, 초상은 정사각 128px 이상.
    static func isAcceptable(pixelWidth w: Int, pixelHeight h: Int, kind: Kind) -> Bool {
        guard w > 0, h > 0 else { return false }
        switch kind {
        case .box: return w == PeperoDecor.sheetWidth && h == PeperoDecor.sheetHeight
        case .neutral, .negative: return w >= 128 && w == h
        }
    }

    /// PNG 바이트를 써도 되나(크기 상한 8MB). 판은 크기에 더해 **불투명**까지 본다(화소를 한 번 푼다 — 받을 때 · 캐시를 처음 고를 때 한 번).
    static func isAcceptable(data: Data, kind: Kind) -> Bool {
        guard data.count <= 8 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              isAcceptable(pixelWidth: w, pixelHeight: h, kind: kind) else { return false }
        guard kind == .box else { return true }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        return isOpaque(image)
    }

    /// 모든 화소의 알파가 255 인가(알파 없는 그림은 바로 참).
    static func isOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: break
        }
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var i = 3
        while i < px.count {
            if px[i] != 255 { return false }
            i += 4
        }
        return true
    }

    static func outcome(status: Int, data: Data, kind: Kind) -> Outcome {
        switch status {
        case 200: return isAcceptable(data: data, kind: kind) ? .replace : .keep
        case 404: return .revert
        // 없는 개체에 400 + 본문 not_found 로 오는 Storage 가 있다(이슬과 같은 판정 — 표식 없는 400 은 잘못된 요청이라 그대로).
        case 400: return IsulArt.isStorageNotFound(data) ? .revert : .keep
        default: return .keep
        }
    }

    // MARK: 읽기(어느 스레드든)

    /// 이 그림의 파일 — 디스크 캐시가 있고 쓸 만하면 그것, 아니면 번들 폴백. 처음 부르면 받기를 연다(`refreshIfNeeded`).
    func url(_ kind: Kind) -> URL? {
        defer { refreshIfNeeded() }
        lock.lock()
        defer { lock.unlock() }
        if let hit = resolved[kind] { return hit }
        let found = resolveLocked(kind)
        if let found { resolved[kind] = found }
        return found
    }

    /// 초상 파일(메뉴바 · 헤더 · 카드 · 남의 아바타 · 상점 칸 · 받는 창 · 뽑기 창이 `CharacterCatalog.portraitURL` 로 탄다).
    func portraitURL(_ mood: CheckMascotAssets.Mood) -> URL? {
        url(Kind(mood: mood))
    }

    /// 상자 인쇄 판(3D 장식이 굽는다). 한 번 풀어 두고 바뀔 때까지 **같은 객체**를 준다(장식 원본이 이 객체에 묶인다 — 바뀌면 다시 굽는다).
    /// 캐시 파일을 못 풀거나 규약 크기가 아니면 번들 폴백으로 한 번 더 푼다. 둘 다 못 풀면 nil(장식 없이 선다).
    func boxImage() -> CGImage? {
        let url = url(.box)
        lock.lock()
        defer { lock.unlock() }
        if boxDecoded { return box }
        boxDecoded = true
        var candidates = [URL]()
        if let url { candidates.append(url) }
        if let bundled = bundleURL(.box), bundled != url { candidates.append(bundled) }
        for candidate in candidates {
            guard let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  Self.isAcceptable(pixelWidth: image.width, pixelHeight: image.height, kind: .box) else {
                Self.logger.error("pepero art: 인쇄 판을 못 풀었다 \(candidate.lastPathComponent, privacy: .public)")
                continue
            }
            box = image
            return image
        }
        Self.logger.error("pepero art: 인쇄 판이 하나도 안 풀린다 — 장식 없이 선다")
        return nil
    }

    private func resolveLocked(_ kind: Kind) -> URL? {
        if readsCache {
            let file = cacheFile(kind)
            if let data = try? Data(contentsOf: file), Self.isAcceptable(data: data, kind: kind) { return file }
        }
        return bundleURL(kind)
    }

    // MARK: 받기

    /// 조건부 요청(**쓸 만한** 캐시가 있을 때만 If-None-Match · If-Modified-Since — 없거나 못 쓰는 캐시에 달면 304 를 받아 번들에 갇힌다).
    func conditionalRequest(_ kind: Kind) -> URLRequest {
        var request = URLRequest(url: Self.remoteURL(kind), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let meta = readMeta(kind)
        let hasCache = (try? Data(contentsOf: cacheFile(kind))).map { Self.isAcceptable(data: $0, kind: kind) } ?? false
        if hasCache, let etag = meta["etag"] { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if hasCache, let modified = meta["last_modified"] { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        return request
    }

    /// 응답 하나를 받아들인다 — 판정(`outcome`)대로 캐시를 쓰거나 지우고, 바뀌었으면 기억한 파일 · 판을 버린다. 네트워크와 떨어져 있어
    /// 시험이 바로 부른다. 반환 = 판정.
    @discardableResult
    func absorb(kind: Kind, status: Int, data: Data, etag: String? = nil, lastModified: String? = nil) -> Outcome {
        let outcome = Self.outcome(status: status, data: data, kind: kind)
        let fm = FileManager.default
        switch outcome {
        case .keep:
            return outcome
        case .revert:
            let hadCache = fm.fileExists(atPath: cacheFile(kind).path)
            try? fm.removeItem(at: cacheFile(kind))
            try? fm.removeItem(at: metaFile(kind))
            guard hadCache else { return outcome }
        case .replace:
            try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            do {
                try data.write(to: cacheFile(kind), options: .atomic)
            } catch {
                Self.logger.error("pepero art: 캐시를 못 썼다 \(kind.rawValue, privacy: .public) — 그대로 둔다")
                return .keep
            }
            var meta: [String: String] = [:]
            meta["etag"] = etag
            meta["last_modified"] = lastModified
            if let encoded = try? JSONEncoder().encode(meta) { try? encoded.write(to: metaFile(kind), options: .atomic) }
        }
        lock.lock()
        resolved[kind] = nil
        if kind == .box { box = nil; boxDecoded = false }
        lock.unlock()
        Self.logger.notice("pepero art: \(kind.rawValue, privacy: .public) \(outcome == .replace ? "replaced" : "reverted", privacy: .public)")
        let isShared = self === PeperoArt.current
        if kind == .box, isShared {
            // 새 판으로 장식 원본을 메인 밖에서 미리 굽는다 — 다음 빼빼로 씬이 메인에서 구우며 멎지 않게(판 객체가 바뀌어 원본이 낡았다).
            DispatchQueue.global(qos: .utility).async { _ = PeperoAingFinish.decorNode(sheet: self.boxImage()) }
        }
        Task { @MainActor in
            if isShared, kind.isPortrait { PeperoArt.forgetDrawnPortraits() }
            NotificationCenter.default.post(name: Self.didChange, object: nil, userInfo: ["kind": kind.rawValue])
        }
        return outcome
    }

    /// 초상을 쥔 앱 캐시에서 빼빼로 몫을 버리고(메뉴바 · 헤더 · 아바타 · 카드 · 받는 창 · 뽑기 창) 관찰 값(`PeperoArtRevision`)을 올린다.
    @MainActor
    static func forgetDrawnPortraits() {
        let id = CharacterCatalog.peperoAingID
        CheckMascotAssets.forgetCachedImages(characterID: id)
        AppUserAvatarArt.forget(characterID: id)
        CharacterCardArt.forget(characterID: id)
        CheckCakeGiftWindowView.forgetPortrait(characterID: id)
        CheckGachaWindowView.forgetPortrait(characterID: id)
        PeperoArtRevision.shared.bump()
    }

    /// 프로세스당 한 번 — 세 그림을 차례로 조건부 요청한다. 시험 중엔(`usesNetwork` 거짓) 아무것도 안 한다.
    func refreshIfNeeded() {
        guard usesNetwork else { return }
        lock.lock()
        let first = !refreshStarted
        refreshStarted = true
        lock.unlock()
        guard first else { return }
        Task.detached(priority: .utility) { [self] in
            for kind in Kind.allCases { await self.refresh(kind) }
        }
    }

    private func refresh(_ kind: Kind) async {
        guard let (data, response) = try? await URLSession.shared.data(for: conditionalRequest(kind)),
              let http = response as? HTTPURLResponse else { return }
        absorb(kind: kind, status: http.statusCode, data: data,
               etag: http.value(forHTTPHeaderField: "ETag"), lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
    }

    private func readMeta(_ kind: Kind) -> [String: String] {
        guard let data = try? Data(contentsOf: metaFile(kind)),
              let meta = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return meta
    }
}

/// 빼빼로 그림이 바뀐 횟수 — **관찰 값**(이슬 `IsulArtRevision` 과 같은 틀). 초상을 쥔 캐시가 빼빼로를 줄 때 이 값을 읽어 두므로, 그 초상을
/// 그린 SwiftUI 화면은 그림 저장소가 새 초상을 받아 값을 올리면 곧바로 다시 그린다. 어느 스레드에서 읽어도 된다.
@Observable
final class PeperoArtRevision: @unchecked Sendable {
    static let shared = PeperoArtRevision()

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var storedCount = 0

    var count: Int {
        access(keyPath: \.count)
        return lock.withLock { storedCount }
    }

    /// 빼빼로 초상을 그리는 자리가 부른다 — 빼빼로가 아니면 아무것도 안 읽는다(다른 캐릭터 화면은 이 값에 묶이지 않는다).
    static func observe(characterID: String) {
        if CharacterCatalog.isPeperoAing(characterID) { _ = shared.count }
    }

    func bump() {
        withMutation(keyPath: \.count) { lock.withLock { storedCount += 1 } }
    }
}
