import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 받침대·테이블 그림 (2판 §3 "그림" · §5 사용자가 고른 그림)
//
// 고른 그림(10-30): 받침대 = 짙은 남색 유광 + 분홍 테두리, 테이블 = 남보라 펠트(이음매 없는 반복 질감).
// 사용자가 **다시 고를 수 있게** 그림을 앱에 굽지 않는다(메모리 assets-users-iterate-must-not-be-baked-in):
//   1) 디스크 캐시(`Caches/check.game-art/rummy/{rack,table}.png`) — 운영 Storage 에서 받은 것.
//   2) 번들의 **줄인 폴백 사본**(`rummy-rack.png` 가로 1600px · `rummy-table.png` 512px).
//   3) 둘 다 없으면 SwiftUI 로 그린 앱 톤 폴백(`RummyRackFallback` · `RummyFeltFallback`).
// 판 화면이 처음 뜰 때 한 번 `game-art/rummy/{rack,table}.png` 를 조건부 요청(ETag · Last-Modified)으로 받아 캐시를 덮는다
// (200 = 바꿈 · 304 = 그대로 · 404 = 캐시 지우고 번들로 · 그 밖 = 그대로). 시험 중엔 네트워크를 타지 않는다.

/// 그림 두 장.
enum RummyArtKind: String, CaseIterable, Sendable {
    case rack
    case table

    /// 공개 버킷 `game-art` 안의 경로.
    var remotePath: String { "rummy/\(rawValue).png" }
    /// 번들 폴백 사본 이름(`.process("Resources")` 는 폴더를 평탄화하므로 앞머리로 가른다).
    var bundleName: String { "rummy-\(rawValue)" }
}

/// 받침대 그림의 기준선 — 원본(2400×478, 그림자 없는 판) 높이 H 대비. 설계서 §5 값 그대로.
enum RummyRackArtMetrics {
    /// 뒷줄 타일 바닥 · 앞줄 타일 바닥(H 대비).
    static let backRowBottom: CGFloat = 0.44
    static let frontRowBottom: CGFloat = 0.76
    /// 타일 높이(H 대비).
    static let tileHeight: CGFloat = 0.31
    /// 원본 가로/세로.
    static let naturalAspect: CGFloat = 2400.0 / 478.0
    /// 타일이 놓이는 가로 구간(원본 폭 대비 7%~93%) → 높이 H 일 때 좌우 안쪽 여백(pt).
    static let tileSpanStart: CGFloat = 0.07
    /// 3-슬라이스 끝캡(원본 2400 기준 좌우 약 150px).
    static let capFraction: CGFloat = 150.0 / 2400.0

    /// 타일 높이 `tile` 에 맞는 받침대 높이.
    static func height(forTileHeight tile: CGFloat) -> CGFloat { (tile / tileHeight).rounded() }
    /// 높이 H 받침대의 타일 구간 좌우 여백.
    static func sideInset(height: CGFloat) -> CGFloat { tileSpanStart * naturalAspect * height }
    /// 높이 H 받침대의 끝캡 폭.
    static func capWidth(height: CGFloat) -> CGFloat { capFraction * naturalAspect * height }
}

/// 그림을 무엇으로 그릴까 — 렌더 시험이 그린 폴백을 따로 굽는 주입구. 앱은 늘 `.automatic`.
enum RummyArtStyle: Equatable, Sendable {
    case automatic
    case drawn
}

private struct RummyArtStyleKey: EnvironmentKey {
    static let defaultValue: RummyArtStyle = .automatic
}

extension EnvironmentValues {
    var rummyArtStyle: RummyArtStyle {
        get { self[RummyArtStyleKey.self] }
        set { self[RummyArtStyleKey.self] = newValue }
    }
}

/// 받침대 3-슬라이스(왼 끝캡 · 늘이는 가운데 · 오른 끝캡). 가운데만 가로로 늘인다 — 세로로는 절대 늘이지 않는다.
struct RummyRackSlices {
    let left: NSImage
    let middle: NSImage
    let right: NSImage
    /// 끝캡 폭 / 그림 높이.
    let capAspect: CGFloat

    init?(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let cap = (RummyRackArtMetrics.capFraction * w).rounded()
        guard w > cap * 2 + 2, h > 0,
              let l = cg.cropping(to: CGRect(x: 0, y: 0, width: cap, height: h)),
              let m = cg.cropping(to: CGRect(x: cap, y: 0, width: w - cap * 2, height: h)),
              let r = cg.cropping(to: CGRect(x: w - cap, y: 0, width: cap, height: h)) else { return nil }
        left = NSImage(cgImage: l, size: NSSize(width: cap, height: h))
        middle = NSImage(cgImage: m, size: NSSize(width: w - cap * 2, height: h))
        right = NSImage(cgImage: r, size: NSSize(width: cap, height: h))
        capAspect = cap / h
    }
}

/// 그림 저장소(앱 하나 · 메인 스레드). 판 화면이 읽고, 처음 뜰 때 `refreshIfNeeded()` 를 부른다.
@MainActor
@Observable
final class RummyArt {
    static let shared = RummyArt()

    private(set) var rack: NSImage?
    private(set) var table: NSImage?
    private(set) var rackSlices: RummyRackSlices?
    @ObservationIgnored private var refreshStarted = false

    init(loadCached: Bool = !CheckPanelVisibility.isRunningTests) {
        for kind in RummyArtKind.allCases {
            let cached = loadCached ? Self.cachedImage(kind) : nil
            install(cached ?? Self.bundledImage(kind), kind: kind)
        }
    }

    private func install(_ image: NSImage?, kind: RummyArtKind) {
        switch kind {
        case .rack:
            rack = image
            rackSlices = image.flatMap(RummyRackSlices.init)
        case .table:
            // 펠트는 512pt 한 칸으로 반복한다(받은 그림이 1024px 이어도 같은 결로).
            image?.size = NSSize(width: 512, height: 512)
            table = image
        }
    }

    // MARK: 위치

    nonisolated static func remoteURL(_ kind: RummyArtKind) -> URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/game-art/\(kind.remotePath)")
    }

    nonisolated static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("check.game-art/rummy", isDirectory: true)
    }

    nonisolated static func cacheFile(_ kind: RummyArtKind) -> URL {
        cacheDirectory.appendingPathComponent("\(kind.rawValue).png")
    }

    nonisolated static func metaFile(_ kind: RummyArtKind) -> URL {
        cacheDirectory.appendingPathComponent("\(kind.rawValue).json")
    }

    static func bundledImage(_ kind: RummyArtKind) -> NSImage? {
        guard let url = CheckResources.bundle.url(forResource: kind.bundleName, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func cachedImage(_ kind: RummyArtKind) -> NSImage? {
        guard let data = try? Data(contentsOf: cacheFile(kind)), let image = NSImage(data: data),
              isAcceptable(image, kind: kind) else { return nil }
        return image
    }

    // MARK: 판정(순수)

    /// 받은 그림을 써도 되나 — 받침대는 가로로 긴 판(3.5~7.5:1, 600px 이상), 펠트는 정사각에 가까운 128px 이상.
    nonisolated static func isAcceptable(_ image: NSImage, kind: RummyArtKind) -> Bool {
        guard let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return false }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        switch kind {
        case .rack: return w >= 600 && (3.5...7.5).contains(w / h)
        case .table: return w >= 128 && (0.5...2.0).contains(w / h)
        }
    }

    /// 조건부 요청 결과 → 할 일.
    enum Outcome: Equatable {
        /// 새 그림으로 바꾼다(캐시에 쓰고 화면도).
        case replace
        /// 그대로(304 · 일시 실패 · 못 쓰는 그림).
        case keep
        /// 서버에서 지워졌다(404) — 캐시를 지우고 번들 사본으로.
        case revert
    }

    nonisolated static func outcome(status: Int, data: Data, kind: RummyArtKind) -> Outcome {
        switch status {
        case 200:
            guard data.count <= 8 * 1024 * 1024, let image = NSImage(data: data),
                  isAcceptable(image, kind: kind) else { return .keep }
            return .replace
        case 404: return .revert
        default: return .keep
        }
    }

    // MARK: 받기

    /// 판 화면이 처음 뜰 때 한 번. 시험 중엔 아무것도 안 한다(렌더 시험이 운영에 닿지 않게).
    func refreshIfNeeded() {
        guard !refreshStarted, !CheckPanelVisibility.isRunningTests else { return }
        refreshStarted = true
        Task { @MainActor [weak self] in
            for kind in RummyArtKind.allCases { await self?.refresh(kind) }
        }
    }

    private func refresh(_ kind: RummyArtKind) async {
        var request = URLRequest(url: Self.remoteURL(kind), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        let meta = Self.readMeta(kind)
        let hasCache = FileManager.default.fileExists(atPath: Self.cacheFile(kind).path)
        if hasCache, let etag = meta["etag"] { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if hasCache, let modified = meta["last_modified"] {
            request.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }
        switch Self.outcome(status: http.statusCode, data: data, kind: kind) {
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
            install(NSImage(data: data), kind: kind)
        }
    }

    private static func readMeta(_ kind: RummyArtKind) -> [String: String] {
        guard let data = try? Data(contentsOf: metaFile(kind)),
              let meta = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return meta
    }
}

// MARK: - 테이블 바닥

/// 판 바닥 — 펠트 그림(반복) 또는 그린 폴백 + 가장자리 어둡게 + 옅은 아잉이 + 분홍-보라 테두리.
struct RummyTableSurface: View {
    var art: RummyArt = .shared
    var cornerRadius: CGFloat = 18
    @Environment(\.rummyArtStyle) private var style

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if style == .automatic, let felt = art.table {
                Image(nsImage: felt).resizable(resizingMode: .tile)
            } else {
                RummyFeltFallback()
            }
            // 가장자리를 눌러 가운데에 눈이 가게.
            RadialGradient(colors: [Color.clear, Color.black.opacity(0.38)], center: .center,
                           startRadius: 120, endRadius: 620)
            if let face = RummyJokerFace.faceImage {
                Image(nsImage: face)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .opacity(0.05)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.82).opacity(0.55),
                                                      Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.35)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        .overlay(shape.inset(by: 1.5).stroke(Color.black.opacity(0.35), lineWidth: 2).blur(radius: 2).clipShape(shape))
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }
}

/// 펠트 천만(테두리·아잉이 없이) — 로비 탁자 · 결과 최종 판이 판 화면과 **같은 천**을 쓰게 한다(그림 → 그린 폴백 순서도 같다).
struct RummyFeltPaint: View {
    var art: RummyArt = .shared
    @Environment(\.rummyArtStyle) private var style

    var body: some View {
        if style == .automatic, let felt = art.table {
            Image(nsImage: felt).resizable(resizingMode: .tile)
        } else {
            RummyFeltFallback()
        }
    }
}

/// 그림이 없을 때의 펠트 — 남보라 그라데이션 + 가운데 빛.
struct RummyFeltFallback: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.38), Color(red: 0.13, green: 0.11, blue: 0.27)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.33, green: 0.27, blue: 0.56).opacity(0.55), Color.clear],
                           center: .center, startRadius: 10, endRadius: 420)
        }
    }
}

// MARK: - 받침대

/// 받침대 — 그림(3-슬라이스, 세로로 안 늘림) 또는 그린 폴백. 크기는 부르는 쪽이 정한다(높이 = 타일 높이 / 0.31).
struct RummyRackStand: View {
    var art: RummyArt = .shared
    @Environment(\.rummyArtStyle) private var style

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if style == .automatic, let slices = art.rackSlices {
                let cap = min(size.width / 2, slices.capAspect * size.height)
                // 가운데를 끝캡 밑으로 2pt 씩 더 깔아 이음매(가장자리 보간의 반투명 줄)가 안 보이게.
                ZStack(alignment: .topLeading) {
                    Image(nsImage: slices.middle).resizable().interpolation(.high)
                        .frame(width: max(0, size.width - cap * 2 + 4), height: size.height)
                        .offset(x: cap - 2)
                    Image(nsImage: slices.left).resizable().interpolation(.high)
                        .frame(width: cap, height: size.height)
                    Image(nsImage: slices.right).resizable().interpolation(.high)
                        .frame(width: cap, height: size.height)
                        .offset(x: size.width - cap)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            } else {
                RummyRackFallback()
            }
        }
        // 조각마다 따로 그림자가 지면 이음매에 어두운 세로줄이 생긴다 — 한 장으로 묶은 뒤 그림자.
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 9, y: 5)
    }
}

/// 그림이 없을 때의 받침대 — 짙은 남색 몸체 · 두 단 선반 · 분홍 테두리 · 둥근 끝캡(그림과 같은 기준선).
struct RummyRackFallback: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let rim = LinearGradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.80), Color(red: 0.62, green: 0.42, blue: 1.0)],
                                     startPoint: .leading, endPoint: .trailing)
            let body = RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
            ZStack(alignment: .topLeading) {
                body.fill(LinearGradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.52), Color(red: 0.10, green: 0.11, blue: 0.32)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.94)
                    .offset(y: h * 0.03)
                // 뒷벽(위 단은 더 어둡게) — 그림의 두 단 계단을 흉내 낸다.
                Rectangle()
                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.13, blue: 0.36), Color(red: 0.18, green: 0.20, blue: 0.48)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.94, height: h * (RummyRackArtMetrics.frontRowBottom - RummyRackArtMetrics.backRowBottom))
                    .offset(x: w * 0.03, y: h * RummyRackArtMetrics.backRowBottom)
                ForEach([RummyRackArtMetrics.backRowBottom, RummyRackArtMetrics.frontRowBottom, 0.92], id: \.self) { y in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.46, green: 0.48, blue: 0.92), Color(red: 0.20, green: 0.21, blue: 0.52)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().stroke(rim.opacity(0.8), lineWidth: 1))
                        .overlay(Capsule().fill(Color.white.opacity(0.35)).frame(height: 1.2).padding(.horizontal, 6)
                            .frame(maxHeight: .infinity, alignment: .top).padding(.top, 1.5))
                        .frame(width: w * 0.95, height: h * 0.07)
                        .offset(x: w * 0.025, y: h * y - h * 0.012)
                }
                ForEach([0.0, 1.0], id: \.self) { side in
                    RoundedRectangle(cornerRadius: h * 0.1, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.32, blue: 0.82), Color(red: 0.20, green: 0.17, blue: 0.50)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: h * 0.1, style: .continuous).stroke(rim, lineWidth: 1.5))
                        .frame(width: h * 0.2, height: h)
                        .offset(x: side == 0 ? 0 : w - h * 0.2, y: 0)
                }
            }
            .overlay(body.stroke(rim, lineWidth: 2).frame(width: w, height: h * 0.94).offset(y: h * 0.03))
        }
    }
}
