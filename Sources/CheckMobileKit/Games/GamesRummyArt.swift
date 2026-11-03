import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
import UIKit
#endif

// 폰 아잉 큐브 받침대·펠트 그림(맥 `RummyArt` 견본 — AppKit 의존은 옮기지 않았다).
// 사용자가 **다시 고를 수 있게** 그림을 앱에 굽지 않는다(메모리 assets-users-iterate-must-not-be-baked-in):
//   1) 디스크 캐시(`Caches/check.game-art/rummy/{rack,table}.png`) — 운영 Storage 에서 받은 것.
//   2) 번들의 폴백 사본(`Resources/Art/rummy-{rack,table}.png` — 맥과 같은 blob).
//   3) 둘 다 없으면 SwiftUI 로 그린 폴백(남색 유광 + 분홍 테두리 · 남보라 펠트).
// 화면이 처음 뜰 때 한 번 조건부 요청(ETag · Last-Modified)으로 받아 캐시를 덮는다. **데모에서는 받지 않는다**(렌더·데모가 운영을 부르면 안 된다).

/// 받은 그림을 쓸지의 판정(순수 — 맥 스위트가 잰다). 맥 `RummyArt.isAcceptable`·`outcome` 과 같은 문턱이다.
package enum GamesRummyArtRules {
    package enum Outcome: Equatable, Sendable {
        /// 새 그림으로 바꾼다(캐시에 쓰고 화면도).
        case replace
        /// 그대로(304 · 일시 실패 · 못 쓰는 그림).
        case keep
        /// 서버에서 지워졌다(404) — 캐시를 지우고 번들 사본으로.
        case revert
    }

    /// 받침대는 가로로 긴 판(3.5~7.5:1, 600px 이상), 펠트는 정사각에 가까운 128px 이상.
    package static func isAcceptable(kind: RummyArtKind, pixelWidth: Int, pixelHeight: Int) -> Bool {
        guard pixelWidth > 0, pixelHeight > 0 else { return false }
        let w = CGFloat(pixelWidth), h = CGFloat(pixelHeight)
        switch kind {
        case .rack: return w >= 600 && (3.5...7.5).contains(w / h)
        case .table: return w >= 128 && (0.5...2.0).contains(w / h)
        }
    }

    /// 조건부 요청 결과 → 할 일. `pixels` = 200 본문을 그림으로 읽은 크기(못 읽었으면 nil).
    package static func outcome(status: Int, byteCount: Int, pixels: (width: Int, height: Int)?, kind: RummyArtKind) -> Outcome {
        switch status {
        case 200:
            guard byteCount <= 8 * 1024 * 1024, let pixels,
                  isAcceptable(kind: kind, pixelWidth: pixels.width, pixelHeight: pixels.height) else { return .keep }
            return .replace
        case 404: return .revert
        default: return .keep
        }
    }

    package static func remoteURL(_ kind: RummyArtKind, projectURL: URL) -> URL {
        projectURL.appendingPathComponent("storage/v1/object/public/game-art/\(kind.remotePath)")
    }
}

#if os(iOS)

/// 받침대 3-슬라이스(왼 끝캡 · 늘이는 가운데 · 오른 끝캡). 가운데만 가로로 늘인다 — 세로로는 늘이지 않는다.
struct GamesRummyRackSlices {
    let left: UIImage
    let middle: UIImage
    let right: UIImage
    /// 끝캡 폭 / 그림 높이.
    let capAspect: CGFloat

    init?(_ image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let cap = (RummyRackArtMetrics.capFraction * w).rounded()
        guard w > cap * 2 + 2, h > 0,
              let l = cg.cropping(to: CGRect(x: 0, y: 0, width: cap, height: h)),
              let m = cg.cropping(to: CGRect(x: cap, y: 0, width: w - cap * 2, height: h)),
              let r = cg.cropping(to: CGRect(x: w - cap, y: 0, width: cap, height: h)) else { return nil }
        left = UIImage(cgImage: l)
        middle = UIImage(cgImage: m)
        right = UIImage(cgImage: r)
        capAspect = cap / h
    }
}

/// 그림 저장소(앱 하나 · 메인 스레드). 화면이 읽고, 처음 뜰 때 `refreshIfNeeded` 를 부른다.
@MainActor
@Observable
final class GamesRummyArt {
    static let shared = GamesRummyArt()

    private(set) var rack: UIImage?
    private(set) var table: UIImage?
    private(set) var rackSlices: GamesRummyRackSlices?
    @ObservationIgnored private var refreshStarted = false

    init() {
        for kind in RummyArtKind.allCases {
            install(Self.cachedImage(kind) ?? Self.bundledImage(kind), kind: kind)
        }
    }

    private func install(_ image: UIImage?, kind: RummyArtKind) {
        switch kind {
        case .rack:
            rack = image
            rackSlices = image.flatMap(GamesRummyRackSlices.init)
        case .table:
            table = image
        }
    }

    private nonisolated static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("check.game-art/rummy", isDirectory: true)
    }

    private nonisolated static func cacheFile(_ kind: RummyArtKind) -> URL {
        cacheDirectory.appendingPathComponent("\(kind.rawValue).png")
    }

    private nonisolated static func metaFile(_ kind: RummyArtKind) -> URL {
        cacheDirectory.appendingPathComponent("\(kind.rawValue).json")
    }

    private static func bundledImage(_ kind: RummyArtKind) -> UIImage? {
        MobileArtNames.url(kind.bundleName).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    private static func cachedImage(_ kind: RummyArtKind) -> UIImage? {
        guard let data = try? Data(contentsOf: cacheFile(kind)), let image = UIImage(data: data),
              let cg = image.cgImage,
              GamesRummyArtRules.isAcceptable(kind: kind, pixelWidth: cg.width, pixelHeight: cg.height) else { return nil }
        return image
    }

    /// 화면이 처음 뜰 때 한 번. 데모에서는 아무것도 안 한다.
    func refreshIfNeeded(projectURL: URL, isDemo: Bool) {
        guard !refreshStarted, !isDemo else { return }
        refreshStarted = true
        Task { @MainActor [weak self] in
            for kind in RummyArtKind.allCases { await self?.refresh(kind, projectURL: projectURL) }
        }
    }

    private func refresh(_ kind: RummyArtKind, projectURL: URL) async {
        var request = URLRequest(url: GamesRummyArtRules.remoteURL(kind, projectURL: projectURL),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let meta = Self.readMeta(kind)
        let hasCache = FileManager.default.fileExists(atPath: Self.cacheFile(kind).path)
        if hasCache, let etag = meta["etag"] { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if hasCache, let modified = meta["last_modified"] {
            request.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }
        let image = http.statusCode == 200 ? UIImage(data: data) : nil
        let pixels = image?.cgImage.map { (width: $0.width, height: $0.height) }
        switch GamesRummyArtRules.outcome(status: http.statusCode, byteCount: data.count, pixels: pixels, kind: kind) {
        case .keep:
            return
        case .revert:
            try? FileManager.default.removeItem(at: Self.cacheFile(kind))
            try? FileManager.default.removeItem(at: Self.metaFile(kind))
            if hasCache { install(Self.bundledImage(kind), kind: kind) }
        case .replace:
            try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: Self.cacheFile(kind), options: .atomic)
            var next: [String: String] = [:]
            next["etag"] = http.value(forHTTPHeaderField: "ETag")
            next["last_modified"] = http.value(forHTTPHeaderField: "Last-Modified")
            if let encoded = try? JSONEncoder().encode(next) { try? encoded.write(to: Self.metaFile(kind), options: .atomic) }
            install(image, kind: kind)
        }
    }

    private static func readMeta(_ kind: RummyArtKind) -> [String: String] {
        guard let data = try? Data(contentsOf: metaFile(kind)),
              let meta = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return meta
    }
}

// MARK: - 테이블 바닥

/// 펠트 천만(테두리 없이) — 그림(반복) → 그린 폴백 순서.
struct GamesRummyFeltPaint: View {
    var art: GamesRummyArt = .shared

    var body: some View {
        if let felt = art.table {
            // 펠트는 그림 크기 그대로 반복한다.
            Image(uiImage: felt).resizable(resizingMode: .tile)
        } else {
            GamesRummyFeltFallback()
        }
    }
}

/// 판 바닥 — 펠트 + 가장자리 어둡게 + 분홍-보라 테두리.
struct GamesRummyTableSurface: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            GamesRummyFeltPaint()
            RadialGradient(colors: [Color.clear, Color.black.opacity(0.38)], center: .center,
                           startRadius: 80, endRadius: 420)
        }
        .clipShape(shape)
        .overlay(shape.stroke(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.82).opacity(0.55),
                                                      Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.35)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }
}

/// 그림이 없을 때의 펠트 — 남보라 그라데이션 + 가운데 빛.
struct GamesRummyFeltFallback: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.38), Color(red: 0.13, green: 0.11, blue: 0.27)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.33, green: 0.27, blue: 0.56).opacity(0.55), Color.clear],
                           center: .center, startRadius: 10, endRadius: 320)
        }
    }
}

// MARK: - 받침대

/// 받침대 — 그림(3-슬라이스, 세로로 안 늘림) 또는 그린 폴백(남색 유광 + 분홍 테두리). 크기는 부르는 쪽이 정한다.
struct GamesRummyRackStand: View {
    var art: GamesRummyArt = .shared

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if let slices = art.rackSlices {
                let cap = min(size.width / 2, slices.capAspect * size.height)
                // 가운데를 끝캡 밑으로 2pt 씩 더 깔아 이음매가 안 보이게.
                ZStack(alignment: .topLeading) {
                    Image(uiImage: slices.middle).resizable().interpolation(.high)
                        .frame(width: max(0, size.width - cap * 2 + 4), height: size.height)
                        .offset(x: cap - 2)
                    Image(uiImage: slices.left).resizable().interpolation(.high)
                        .frame(width: cap, height: size.height)
                    Image(uiImage: slices.right).resizable().interpolation(.high)
                        .frame(width: cap, height: size.height)
                        .offset(x: size.width - cap)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            } else {
                GamesRummyRackFallback()
            }
        }
        // 조각마다 따로 그림자가 지면 이음매에 어두운 세로줄이 생긴다 — 한 장으로 묶은 뒤 그림자.
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 9, y: 5)
    }
}

/// 그림이 없을 때의 받침대 — 짙은 남색 몸체 · 분홍 테두리.
struct GamesRummyRackFallback: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.52), Color(red: 0.10, green: 0.11, blue: 0.32)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.stroke(LinearGradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.80), Color(red: 0.62, green: 0.42, blue: 1.0)],
                                                 startPoint: .leading, endPoint: .trailing), lineWidth: 2))
    }
}

#endif
