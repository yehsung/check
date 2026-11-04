import AppKit
import CheckCore
import Foundation
import ImageIO
import os

// MARK: - 이슬 아잉이 그림 저장소 (v0.3.74 — 설계서 §6 '굽지 않기')
//
// 대표가 다시 다듬을 그림은 **라벨**(3D 셰이더 인자 ckLabelMap)과 **초상 두 장**이다(메모리 assets-users-iterate-must-not-be-baked-in).
// 아잉 큐브 판 그림(`RummyArt`)과 같은 길이다:
//   1) 디스크 캐시(`Caches/check.game-art/isul/{label,neutral,negative}.png`) — 운영 Storage 에서 받은 것.
//   2) 번들 폴백(`aing_isul-{label,neutral,negative}.png` — 그림 생성기 `scripts/make-isul-aing.swift` 산출).
// 조건부 요청(ETag · Last-Modified)으로 `game-art/isul/<이름>.png` 를 받아 캐시를 덮는다 — 200 = 바꿈 · 304 = 그대로 · 없는 개체(404, 또는
// 400 + 본문 not_found — Supabase Storage 버전에 따라 이렇게 온다, `deleteAvatarFile` 과 같은 판정) = 캐시 지우고 번들로 ·
// 그 밖(본문 없는 400 · 5xx · 끊김 · 못 쓰는 그림) = 그대로. 받은 그림은 검사한다(라벨은 가로로 긴 판 · 초상은 정사각 128px 이상).
//
// 언제 받나 — **이슬을 그릴 일이 처음 생길 때 한 번**(`url(_:)` 첫 조회가 연다 — 프로세스당 한 번). RummyArt 가 '판 화면이 처음 뜰 때 한 번'인
// 것과 같은 결이다: 그림을 쓰는 자리가 처음 생길 때 묻고, 이슬을 한 번도 안 그리는 실행에서는 네트워크를 안 탄다. 앱 시작 직후 고정 시각에
// 묻지 않는 이유는 둘이다 — ① RummyArt 처럼 화면(그림)이 실제로 필요한 때가 '받기'의 근거이고, ② 시작 경로(`AppDelegate`)는 다른 갈래와
// 나눠 쓰는 파일이라 줄을 더하지 않는다. 실제로는 사람 아바타 목록(`AppUserAvatarArt.knownIDs` — 카탈로그 전부의 초상 URL)이나 상점의 잠긴 칸이
// 시작 뒤 곧 첫 조회를 내므로 대부분의 실행에서 '시작 뒤 한 번'과 같다.
// 받은 그림은 **다음에 그리는 자리부터** 쓴다: 라벨은 다음에 세우는 3D 씬(착용 · 울트라 교체)부터, 초상은 그 그림을 쥔 캐시 셋(메뉴바 · 헤더 —
// `CheckMascotAssets`, 남의 아바타 — `AppUserAvatarArt`, 고르기 · 상점 카드 — `CharacterCardArt`)의 이슬 몫을 비우고 관찰 값
// (`IsulArtRevision`)을 올려 그 초상을 그린 SwiftUI 화면이 곧바로 다시 그린다(세 캐시가 이슬을 줄 때 그 값을 읽어 둔다).
// 이미 서 있는 3D 씬의 라벨은 바꾸지 않는다(재질 인자를 렌더 중에 갈지 않는다 — 다음 씬에서 선다).
// 시험 중엔 디스크 캐시도 네트워크도 타지 않는다(`CheckPanelVisibility.isRunningTests` — 렌더 시험이 운영에 닿지 않고, 사용자 캐시에 흔들리지 않게).
// 운영 Storage 에 그림을 올리는 일은 이번 범위 밖이다(대표 승인 후) — 올리기 전까지 요청은 404 이고 번들 그대로 선다.
final class IsulArt: @unchecked Sendable {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// 그림 종류. 이름이 곧 캐시 파일 이름 · Storage 경로 · 번들 이름의 꼬리다.
    enum Kind: String, CaseIterable, Sendable {
        case label, neutral, negative

        /// 번들 폴백 리소스 이름(확장자 png — 금 · 무지개 · 케이크 규약 `<id>-<꼬리>`).
        var bundleName: String { "\(CharacterCatalog.isulAingID)-\(rawValue)" }
        /// 캐시 파일 이름.
        var fileName: String { "\(rawValue).png" }
        /// Storage 버킷 `game-art` 안 경로.
        var remotePath: String { "isul/\(fileName)" }

        init(mood: CheckMascotAssets.Mood) {
            self = mood == .neutral ? .neutral : .negative
        }
    }

    /// 조건부 요청 결과 → 할 일(RummyArt 와 같은 어휘).
    enum Outcome: Equatable, Sendable {
        /// 새 그림으로 바꾼다(캐시에 쓰고 다음 그리기부터).
        case replace
        /// 그대로(304 · 일시 실패 · 못 쓰는 그림).
        case keep
        /// 서버에서 지워졌다(404) — 캐시를 지우고 번들 사본으로.
        case revert
    }

    /// 그림이 바뀌었다(바꿈 · 되돌림) — 메인에서 보낸다. 받는 쪽은 이슬 그림을 다시 읽으면 된다.
    static let didChange = Notification.Name("check.isulArt.didChange")

    static let shared = IsulArt()

    /// 시험 전용 갈아 끼우기(작업 지역값 — 그 시험 작업 안에서만 보인다, 나란히 도는 다른 시험은 `shared` 그대로).
    @TaskLocal static var testOverride: IsulArt?

    /// 초상 조회가 타는 저장소 — 앱은 언제나 `shared`, 시험은 `testOverride` 로 따로 저장소(임시 캐시 폴더)를 끼운다.
    static var current: IsulArt { testOverride ?? shared }

    let cacheDirectory: URL
    let readsCache: Bool
    let usesNetwork: Bool
    private let bundleURL: @Sendable (Kind) -> URL?

    private let lock = NSLock()
    private var resolved: [Kind: URL] = [:]
    private var label: CGImage?
    private var labelDecoded = false
    private var refreshStarted = false

    /// - Parameters:
    ///   - readsCache: 디스크 캐시를 읽는가(앱 = 참 · 시험 = 거짓 — RummyArt `loadCached` 와 같은 기본값).
    ///   - usesNetwork: 첫 조회 때 조건부 요청을 여는가(앱 = 참 · 시험 = 거짓).
    init(cacheDirectory: URL = IsulArt.defaultCacheDirectory,
         readsCache: Bool = !CheckPanelVisibility.isRunningTests,
         usesNetwork: Bool = !CheckPanelVisibility.isRunningTests,
         bundleURL: @escaping @Sendable (Kind) -> URL? = IsulArt.bundledURL) {
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
        return base.appendingPathComponent("check.game-art/isul", isDirectory: true)
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

    /// 받은 그림을 써도 되나 — 라벨은 **가로로 긴 판**(가로 ≥ 256px · 가로/세로 1.5~4 — 번들 폴백 1200×551 은 2.18),
    /// 초상은 **정사각 128px 이상**(번들 192²). 셰이더는 라벨을 (θ, t) 범위 상수로 읽어 비가 조금 달라도 깨지지 않지만(늘어날 뿐),
    /// 세로로 긴 판 · 아주 작은 판은 잘못 올린 그림으로 보고 버린다.
    static func isAcceptable(pixelWidth w: Int, pixelHeight h: Int, kind: Kind) -> Bool {
        guard w > 0, h > 0 else { return false }
        switch kind {
        case .label:
            let ratio = Double(w) / Double(h)
            return w >= 256 && (1.5...4.0).contains(ratio)
        case .neutral, .negative:
            return w >= 128 && w == h
        }
    }

    /// PNG 바이트를 써도 되나(크기 상한 8MB — RummyArt 와 같다).
    static func isAcceptable(data: Data, kind: Kind) -> Bool {
        guard data.count <= 8 * 1024 * 1024, let size = pixelSize(of: data) else { return false }
        return isAcceptable(pixelWidth: size.width, pixelHeight: size.height, kind: kind)
    }

    static func outcome(status: Int, data: Data, kind: Kind) -> Outcome {
        switch status {
        case 200: return isAcceptable(data: data, kind: kind) ? .replace : .keep
        case 404: return .revert
        // Supabase Storage 는 버전 · 게이트웨이에 따라 없는 개체에 400 을 주며 본문에만 not_found 를 싣는다(`deleteAvatarFile` 판정).
        // 그 표식이 없는 400 은 정말 잘못된 요청이다 — 캐시를 건드리지 않는다.
        case 400: return isStorageNotFound(data) ? .revert : .keep
        default: return .keep
        }
    }

    /// 본문이 Storage 의 '없는 개체' 표식인가 — `{"statusCode":"404","error":"not_found","message":"Object not found"}`.
    static func isStorageNotFound(_ data: Data) -> Bool {
        let body = String(decoding: data, as: UTF8.self)
        return body.contains("\"error\":\"not_found\"") || body.contains("\"statusCode\":\"404\"")
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
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

    /// 초상 파일(메뉴바 · 헤더 · 카드 · 남의 아바타 · 상점 칸이 `CharacterCatalog.portraitURL` 로 탄다).
    func portraitURL(_ mood: CheckMascotAssets.Mood) -> URL? {
        url(Kind(mood: mood))
    }

    /// 라벨 그림(3D 셰이더 인자 ckLabelMap). 한 번 풀어 두고 바뀔 때까지 같은 객체를 준다. 캐시 파일을 못 풀면(크기 머리는 읽히는데 몸이
    /// 깨진 PNG) 번들 폴백으로 한 번 더 푼다. 둘 다 못 풀면 nil(셰이더는 라벨 없는 유리 병).
    func labelImage() -> CGImage? {
        let url = url(.label)
        lock.lock()
        defer { lock.unlock() }
        if labelDecoded { return label }
        labelDecoded = true
        var candidates = [URL]()
        if let url { candidates.append(url) }
        if let bundled = bundleURL(.label), bundled != url { candidates.append(bundled) }
        for candidate in candidates {
            guard let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                Self.logger.error("isul art: 라벨 그림을 못 풀었다 \(candidate.lastPathComponent, privacy: .public)")
                continue
            }
            label = image
            return image
        }
        Self.logger.error("isul art: 라벨 그림이 하나도 안 풀린다 — 라벨 없이 선다")
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

    /// 조건부 요청(**쓸 만한** 캐시가 있을 때만 If-None-Match · If-Modified-Since — 캐시가 없거나 못 쓰는 그림인데(`resolveLocked` 가 번들로
    /// 접는다) 304 를 받으면 번들에 갇힌다).
    func conditionalRequest(_ kind: Kind) -> URLRequest {
        var request = URLRequest(url: Self.remoteURL(kind), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let meta = readMeta(kind)
        let hasCache = (try? Data(contentsOf: cacheFile(kind))).map { Self.isAcceptable(data: $0, kind: kind) } ?? false
        if hasCache, let etag = meta["etag"] { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if hasCache, let modified = meta["last_modified"] { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        return request
    }

    /// 응답 하나를 받아들인다 — 판정(`outcome`)대로 캐시를 쓰거나 지우고, 바뀌었으면 기억한 파일 · 라벨을 버린다. 네트워크와 떨어져 있어
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
                Self.logger.error("isul art: 캐시를 못 썼다 \(kind.rawValue, privacy: .public) — 그대로 둔다")
                return .keep
            }
            var meta: [String: String] = [:]
            meta["etag"] = etag
            meta["last_modified"] = lastModified
            if let encoded = try? JSONEncoder().encode(meta) { try? encoded.write(to: metaFile(kind), options: .atomic) }
        }
        lock.lock()
        resolved[kind] = nil
        if kind == .label { label = nil; labelDecoded = false }
        lock.unlock()
        Self.logger.notice("isul art: \(kind.rawValue, privacy: .public) \(outcome == .replace ? "replaced" : "reverted", privacy: .public)")
        let isShared = self === IsulArt.current
        Task { @MainActor in
            // 초상을 쥔 캐시(메뉴바 · 헤더 · 남의 아바타 · 카드)를 비우고 화면을 다시 그리게 한다. 초상 조회가 타지 않는 따로 저장소는 건드리지 않는다.
            if isShared { IsulArt.forgetDrawnPortraits() }
            NotificationCenter.default.post(name: Self.didChange, object: nil, userInfo: ["kind": kind.rawValue])
        }
        return outcome
    }

    /// 초상을 쥔 앱 캐시에서 이슬 몫을 버리고(`CheckMascotAssets` 초상 · 메뉴바 · `AppUserAvatarArt` 아바타 · `CharacterCardArt` 카드)
    /// 관찰 값(`IsulArtRevision`)을 올린다 — 그 초상을 그린 화면이 다시 그리며 새 파일을 읽는다.
    @MainActor
    static func forgetDrawnPortraits() {
        CheckMascotAssets.forgetCachedImages(characterID: CharacterCatalog.isulAingID)
        AppUserAvatarArt.forget(characterID: CharacterCatalog.isulAingID)
        CharacterCardArt.forget(characterID: CharacterCatalog.isulAingID)
        // 받는 창 · 뽑기 창의 초상 캐시도(v0.3.77 검토 수리 — 안 비우면 그 두 창은 옛 이슬 그림을 프로세스 내내 쥔다).
        CheckCakeGiftWindowView.forgetPortrait(characterID: CharacterCatalog.isulAingID)
        CheckGachaWindowView.forgetPortrait(characterID: CharacterCatalog.isulAingID)
        IsulArtRevision.shared.bump()
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

/// 이슬 그림이 바뀐 횟수 — **관찰 값**(v0.3.74 검토 수리). 초상을 쥔 캐시 셋(`CheckMascotAssets` · `CharacterCardArt` · `AppUserAvatarArt`)이
/// 이슬을 줄 때 이 값을 읽어 두므로, 그 초상을 그린 SwiftUI 화면은 이 값을 관찰한다 — 그림 저장소가 새 초상을 받아 값을 올리면 곧바로 다시
/// 그린다(앱 재시작 없이). 어느 스레드에서 읽어도 된다(자물쇠 · 관찰 등록기는 스레드 안전).
@Observable
final class IsulArtRevision: @unchecked Sendable {
    static let shared = IsulArtRevision()

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var storedCount = 0

    var count: Int {
        access(keyPath: \.count)
        return lock.withLock { storedCount }
    }

    /// 이슬 초상을 그리는 자리가 부른다 — 이슬이 아니면 아무것도 안 읽는다(다른 캐릭터 화면은 이 값에 묶이지 않는다).
    static func observe(characterID: String) {
        if CharacterCatalog.isIsulAing(characterID) { _ = shared.count }
    }

    func bump() {
        withMutation(keyPath: \.count) { lock.withLock { storedCount += 1 } }
    }
}
