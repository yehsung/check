import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 마작 펠트 그림 · 패 팔레트 받기 (SPEC §5.9 — 큐브 `RummyArt` 길, 번들 사본 없이 코드 폴백)
//
//  · 펠트 `game-art/mahjong/table.png`(반복 무늬) · 팔레트 `game-art/mahjong/tiles.json`(색 7개) — 판 화면이 처음 뜰 때 한 번
//    조건부 요청(ETag · Last-Modified)으로 받아 디스크 캐시(`Caches/check.game-art/mahjong/`)를 덮는다.
//    200 = 바꿈 · 304 = 그대로 · 404 = 캐시를 비우고 코드 기본으로 · 그 밖 = 그대로(판정은 코어 `MahjongArtRemote`).
//  · **번들 사본이 없다**: 기본은 코드 — 펠트 = `MahjongFeltStyle` 색, 팔레트 = `MahjongTilePalette.code`(고른 뒷면 짝).
//    다듬을 그림을 앱에 굽지 않는다(메모리 assets-users-iterate-must-not-be-baked-in).
//  · 받기 함수는 주입한다 — 시험은 네트워크 없이 가짜 응답을 넣는다. 시험 중 `shared` 는 캐시를 읽지 않고 받지도 않는다
//    (렌더 시험이 운영에 닿지 않게 — 메모리 render-tests-hit-production).
//  · 404 의 '캐시 지우기'는 파일을 비우는 것(빈 파일 = 캐시 없음)이다 — 지우기 경쟁 없이 같은 자리를 다시 쓴다.

@MainActor
@Observable
final class MahjongArt {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = MahjongArt()

    /// 받은 펠트(512pt 한 칸으로 반복). nil 이면 코드 펠트. CGImage 로 쥔다 — NSImage 는 ImageRenderer 가 비워 그린다.
    private(set) var table: CGImage?
    /// 받은 팔레트(바른 JSON 만). nil 이면 코드 팔레트.
    private(set) var palette: MahjongTilePalette?
    /// 팔레트가 바뀐 횟수 — 판 화면이 읽어 패 띠를 다시 그린다.
    private(set) var paletteRevision = 0

    @ObservationIgnored let cacheDirectory: URL
    @ObservationIgnored private let fetch: Fetch
    /// 받은 팔레트를 패 그림(`MahjongTileArt` — 프로세스 하나)에 놓는가. 시험 인스턴스는 거짓(남의 시험 그림을 안 바꾼다).
    @ObservationIgnored private let installsPalette: Bool
    @ObservationIgnored private var refreshStarted = false

    nonisolated static var defaultCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("check.game-art/mahjong", isDirectory: true)
    }

    nonisolated static func remoteURL(_ kind: MahjongArtRemote.Kind) -> URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/game-art/\(kind.remotePath)")
    }

    init(loadCached: Bool = !CheckPanelVisibility.isRunningTests, cacheDirectory: URL = MahjongArt.defaultCacheDirectory,
         installsPalette: Bool = !CheckPanelVisibility.isRunningTests,
         fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.cacheDirectory = cacheDirectory
        self.fetch = fetch
        self.installsPalette = installsPalette
        guard loadCached else { return }
        for kind in MahjongArtRemote.Kind.allCases {
            if let data = try? Data(contentsOf: cacheFile(kind)), Self.decodedAcceptable(kind, data: data) { install(kind, data: data) }
        }
    }

    func cacheFile(_ kind: MahjongArtRemote.Kind) -> URL { cacheDirectory.appendingPathComponent(kind.cacheName) }
    func metaFile(_ kind: MahjongArtRemote.Kind) -> URL { cacheDirectory.appendingPathComponent("\(kind.rawValue).meta.json") }

    // MARK: 받기

    /// 판 화면이 처음 뜰 때 한 번. 시험 중엔 아무것도 안 한다.
    func refreshIfNeeded() {
        guard !refreshStarted, !CheckPanelVisibility.isRunningTests else { return }
        refreshStarted = true
        Task { @MainActor [weak self] in await self?.refreshAll() }
    }

    func refreshAll() async {
        for kind in MahjongArtRemote.Kind.allCases { _ = await refresh(kind) }
    }

    /// 하나를 조건부로 받는다. 받기에 실패하면(오프라인) nil — 아무것도 안 바꾼다.
    @discardableResult
    func refresh(_ kind: MahjongArtRemote.Kind) async -> MahjongArtRemote.Outcome? {
        var request = URLRequest(url: Self.remoteURL(kind), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let hasCache = ((try? Data(contentsOf: cacheFile(kind)))?.isEmpty == false)
        let meta = readMeta(kind)
        if hasCache, let etag = meta["etag"] { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if hasCache, let modified = meta["last_modified"] { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        guard let (data, response) = try? await fetch(request), let http = response as? HTTPURLResponse else { return nil }
        let outcome = MahjongArtRemote.outcome(kind, status: http.statusCode, data: data, feltPixels: Self.pixels(kind, data: data))
        switch outcome {
        case .keep:
            break
        case .revert:
            write(Data(), to: cacheFile(kind))
            write(Data(), to: metaFile(kind))
            uninstall(kind)
        case .replace:
            write(data, to: cacheFile(kind))
            var next: [String: String] = [:]
            next["etag"] = http.value(forHTTPHeaderField: "ETag")
            next["last_modified"] = http.value(forHTTPHeaderField: "Last-Modified")
            if let encoded = try? JSONEncoder().encode(next) { write(encoded, to: metaFile(kind)) }
            install(kind, data: data)
        }
        return outcome
    }

    // MARK: 놓기

    private func install(_ kind: MahjongArtRemote.Kind, data: Data) {
        switch kind {
        case .table:
            table = NSBitmapImageRep(data: data)?.cgImage
        case .tiles:
            setPalette(MahjongTilePalette.delivered(from: data))
        }
    }

    private func uninstall(_ kind: MahjongArtRemote.Kind) {
        switch kind {
        case .table: table = nil
        case .tiles: setPalette(nil)
        }
    }

    private func setPalette(_ next: MahjongTilePalette?) {
        guard next != palette else { return }
        palette = next
        if installsPalette { MahjongTileArt.apply(palette: next) }
        paletteRevision &+= 1
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func readMeta(_ kind: MahjongArtRemote.Kind) -> [String: String] {
        guard let data = try? Data(contentsOf: metaFile(kind)),
              let meta = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return meta
    }

    /// 펠트 그림의 픽셀 크기(못 읽으면 nil). 팔레트는 nil.
    nonisolated static func pixels(_ kind: MahjongArtRemote.Kind, data: Data) -> (width: Int, height: Int)? {
        guard kind == .table, let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    nonisolated static func decodedAcceptable(_ kind: MahjongArtRemote.Kind, data: Data) -> Bool {
        MahjongArtRemote.acceptable(kind, data: data, feltPixels: pixels(kind, data: data))
    }
}

/// 판 바닥 — 받은 펠트 그림(반복) 또는 코드 펠트 색. 테두리는 늘 코드 색(중간 톤).
struct MahjongFeltSurface: View {
    /// 펠트 한 칸(pt) — 받은 그림이 1024px 이어도 같은 결로 반복한다(큐브 펠트와 같다).
    static let tilePoints: CGFloat = 512

    var art: MahjongArt = .shared
    var cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let felt = art.table {
                // 반복은 Canvas 로 놓는다(`resizingMode: .tile` 은 ImageRenderer 가 비워 그려 렌더 시험이 못 본다).
                Canvas { context, size in
                    let tile = context.resolve(Image(decorative: felt, scale: CGFloat(felt.width) / MahjongFeltSurface.tilePoints))
                    let step = CGSize(width: MahjongFeltSurface.tilePoints, height: MahjongFeltSurface.tilePoints)
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = 0
                        while x < size.width {
                            context.draw(tile, in: CGRect(origin: CGPoint(x: x, y: y), size: step))
                            x += step.width
                        }
                        y += step.height
                    }
                }
            } else {
                MahjongFeltStyle.felt
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(MahjongFeltStyle.rim, lineWidth: 3))
    }
}
