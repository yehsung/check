import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 펠트 그림·팔레트 JSON 받기(SPEC §5.9 — 큐브 RummyArt 길, 번들 사본 없이 코드 폴백). 네트워크 없이 받기 함수를 주입한다.
// 캐시는 시험 스크래치(`CheckTestScratch.root`) 아래 — 다음 실행이 통째로 치운다.

@MainActor
@Suite("아잉 마작 그림 받기")
struct V03xxMahjongArtFetchTests {
    @Test
    func remoteDecisionsFollowTheCubeRulesWithoutABundleCopy() throws {
        // 없으면: 64px 조각·그림 아닌 바이트·키 빠진 팔레트를 받아 판을 망가뜨리거나, 404 에도 옛 캐시를 계속 쓰거나(지운 그림이 안 사라짐),
        // 일시 실패(500)에 캐시를 버려도 초록이다.
        #expect(MahjongArtRemote.Kind.table.remotePath == "mahjong/table.png")
        #expect(MahjongArtRemote.Kind.tiles.remotePath == "mahjong/tiles.json")
        #expect(MahjongArt.remoteURL(.table).path.hasSuffix("/storage/v1/object/public/game-art/mahjong/table.png"))
        let png = try mjArtPNG(side: 256), tiny = try mjArtPNG(side: 64)
        func felt(_ status: Int, _ data: Data) -> MahjongArtRemote.Outcome {
            MahjongArtRemote.outcome(.table, status: status, data: data, feltPixels: MahjongArt.pixels(.table, data: data))
        }
        #expect(felt(200, png) == .replace)
        #expect(felt(200, tiny) == .keep)
        #expect(felt(200, Data("not an image".utf8)) == .keep)
        #expect(felt(304, Data()) == .keep && felt(500, png) == .keep)
        #expect(felt(404, Data()) == .revert)
        let good = mjArtPaletteJSON()
        func tiles(_ status: Int, _ data: Data) -> MahjongArtRemote.Outcome {
            MahjongArtRemote.outcome(.tiles, status: status, data: data, feltPixels: nil)
        }
        #expect(tiles(200, good) == .replace)
        #expect(tiles(200, mjArtPaletteJSON(ink: "#12345")) == .keep, "색 글자 틀린 팔레트를 받았다")
        #expect(tiles(200, Data(##"{"bodyTop":"#FFFFFF"}"##.utf8)) == .keep, "키 빠진 팔레트를 받았다")
        #expect(tiles(200, good + Data(repeating: 0x20, count: 17 * 1024)) == .keep, "16KB 넘는 팔레트를 받았다")
        #expect(tiles(404, Data()) == .revert)
    }

    @Test
    func feltIsFetchedCachedRevalidatedAndRevertedWithoutTheNetwork() async throws {
        // 없으면: 받은 펠트를 캐시에 안 써 다음 실행에 또 받거나, ETag 를 안 보내(늘 200 전체 받기), 304 에 그림을 버리거나,
        // 404 뒤에도 캐시 그림이 다음 실행에 되살아나도(번들 사본이 없으니 코드 펠트여야 한다) 초록이다.
        let dir = CheckTestScratch.root.appendingPathComponent("v03xx-mahjong-art-felt", isDirectory: true)
        let png = try mjArtPNG(side: 256)
        let server = MJArtStubServer()
        server.reply = (200, png, ["ETag": "\"v1\""])
        let art = MahjongArt(loadCached: false, cacheDirectory: dir, installsPalette: false, fetch: server.fetch)
        #expect(art.table == nil, "번들 사본 없이 코드 펠트에서 시작한다")
        #expect(await art.refresh(.table) == .replace)
        #expect(art.table != nil)
        #expect(try Data(contentsOf: art.cacheFile(.table)) == png)
        #expect(server.requests.last?.url == MahjongArt.remoteURL(.table))
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil, "캐시가 없을 땐 조건 없이 받는다")
        // 다음 실행: 캐시에서 바로 그린다(받기 전).
        let next = MahjongArt(loadCached: true, cacheDirectory: dir, installsPalette: false, fetch: server.fetch)
        #expect(next.table != nil)
        server.reply = (304, Data(), [:])
        #expect(await next.refresh(.table) == .keep)
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"", "ETag 를 안 보냈다")
        #expect(next.table != nil, "304 에 그림을 버렸다")
        // 받기 실패(오프라인)는 아무것도 안 바꾼다.
        server.reply = nil
        #expect(await next.refresh(.table) == nil)
        #expect(next.table != nil)
        // 404 — 캐시를 비우고 코드 펠트로, 다음 실행에도 되살아나지 않는다.
        server.reply = (404, Data(), [:])
        #expect(await next.refresh(.table) == .revert)
        #expect(next.table == nil)
        #expect(MahjongArt(loadCached: true, cacheDirectory: dir, installsPalette: false, fetch: server.fetch).table == nil)
    }

    @Test
    func paletteJSONIsDeliveredWithoutTouchingTheSharedTileArtInTests() async throws {
        // 없으면: 바른 팔레트 JSON 을 받아도 색이 안 바뀌거나(revision 그대로라 판이 다시 안 그려짐), 틀린 JSON 으로 받은 팔레트를
        // 지우거나, 시험 인스턴스가 프로세스 공용 패 그림을 바꿔 남의 시험 그림이 흔들려도 초록이다.
        let dir = CheckTestScratch.root.appendingPathComponent("v03xx-mahjong-art-tiles", isDirectory: true)
        let server = MJArtStubServer()
        let before = MahjongTileArt.deliveredPalette
        let art = MahjongArt(loadCached: false, cacheDirectory: dir, installsPalette: false, fetch: server.fetch)
        server.reply = (200, mjArtPaletteJSON(), [:])
        #expect(await art.refresh(.tiles) == .replace)
        #expect(art.palette == MahjongTilePalette.delivered(from: mjArtPaletteJSON()) && art.paletteRevision == 1)
        server.reply = (200, mjArtPaletteJSON(ink: "#XYZXYZ"), [:])
        #expect(await art.refresh(.tiles) == .keep)
        #expect(art.palette != nil && art.paletteRevision == 1, "틀린 JSON 이 받은 팔레트를 지웠다")
        #expect(MahjongArt(loadCached: true, cacheDirectory: dir, installsPalette: false, fetch: server.fetch).palette == art.palette)
        server.reply = (404, Data(), [:])
        #expect(await art.refresh(.tiles) == .revert)
        #expect(art.palette == nil && art.paletteRevision == 2)
        #expect(MahjongTileArt.deliveredPalette == before, "시험 인스턴스가 공용 패 그림을 바꿨다")
        // 시험 중 공용 인스턴스는 캐시를 안 읽는다(렌더 시험이 기기 캐시·운영에 닿지 않게).
        #expect(MahjongArt.shared.table == nil && MahjongArt.shared.palette == nil)
    }

    @Test
    func feltSurfaceDrawsTheDeliveredPictureOrTheCodeFelt() async throws {
        // 없으면: 받은 펠트 그림이 있어도 판이 코드 색만 그리거나(받기 길이 화면에 안 닿음), 그림이 없을 때 빈 판이어도 초록이다.
        let dir = CheckTestScratch.root.appendingPathComponent("v03xx-mahjong-art-surface", isDirectory: true)
        let server = MJArtStubServer()
        server.reply = (200, try mjArtPNG(side: 256), [:])
        let art = MahjongArt(loadCached: false, cacheDirectory: dir, installsPalette: false, fetch: server.fetch)
        let plain = try #require(CheckRenderSettle.bitmap(MahjongFeltSurface(art: art).frame(width: 200, height: 120).fixedSize(),
                                                          scale: 2))
        #expect(await art.refresh(.table) == .replace)
        let drawn = try #require(CheckRenderSettle.bitmap(MahjongFeltSurface(art: art).frame(width: 200, height: 120).fixedSize(),
                                                          scale: 2))
        let code = mjArtPixel(plain, x: 200, y: 120), picture = mjArtPixel(drawn, x: 200, y: 120)
        let felt = MahjongFeltScheme.teal.felt.channels
        #expect(zip(code, felt).allSatisfy { abs($0 - $1) <= 6 }, "코드 펠트 색이 아니다: \(code)")
        #expect(picture[0] >= 150 && picture[1] <= 90, "받은 펠트 그림(붉은 무늬)이 안 그려졌다: \(picture)")
    }
}

/// 가짜 Storage — 응답 하나를 돌려주고 요청을 적는다(네트워크 없음).
private final class MJArtStubServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _reply: (Int, Data, [String: String])?
    private var _requests: [URLRequest] = []

    var reply: (Int, Data, [String: String])? {
        get { lock.withLock { _reply } }
        set { lock.withLock { _reply = newValue } }
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    var fetch: MahjongArt.Fetch {
        { [self] request in
            let reply = lock.withLock { () -> (Int, Data, [String: String])? in
                _requests.append(request)
                return _reply
            }
            guard let reply, let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: reply.2)
            else { throw URLError(.notConnectedToInternet) }
            return (reply.1, response)
        }
    }
}

/// 붉은 정사각 PNG(펠트 그림 대역).
private func mjArtPNG(side: Int) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(srgbRed: 0.85, green: 0.20, blue: 0.25, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let image = try #require(context.makeImage())
    return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
}

private func mjArtPaletteJSON(ink: String = "#1F2A5A") -> Data {
    Data(("{\"bodyTop\":\"#FBF9FF\",\"bodyBottom\":\"#ECE7F7\",\"bevel\":\"#C9C0E3\",\"backTop\":\"#5B3FB2\","
          + "\"backBottom\":\"#3A2680\",\"backRim\":\"#FF8DC7\",\"ink\":\"\(ink)\"}").utf8)
}

private func mjArtPixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> [Int] {
    guard let data = bitmap.bitmapData else { return [] }
    let o = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
    return [Int(data[o]), Int(data[o + 1]), Int(data[o + 2])]
}
