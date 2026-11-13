import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 원격 기계 연결(aing-scan) — 맥 설정 쪽: 설치 명령 · 서버 호출 세 개 · 목록 상태 · 문구.
// 서버는 이 파일 전용 가짜(URLProtocol)다 — 운영 서버에 닿지 않는다(호스트도 .invalid).

private final class ScannerStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var bodies: [String: String] = [:]
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "aing-scan-settings.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let reply: (Int, String) = Self.lock.withLock {
            Self.bodies[path] = String(data: body, encoding: .utf8) ?? ""
            return Self.responses[path] ?? (404, "{}")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func scannerService() -> SupabaseWorkService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScannerStubProtocol.self]
    return SupabaseWorkService(
        projectURL: URL(string: "https://aing-scan-settings.invalid")!,
        anonKey: "anon-test",
        session: URLSession(configuration: configuration)
    )
}

@Suite(.serialized)
struct AingScanSettingsServiceTests {
    @Test
    func linkCodeDecodesAndMakesTheInstallCommand() async throws {
        ScannerStubProtocol.responses["/rest/v1/rpc/scanner_link_code_create"] = (200,
            #"{"ok":true,"code":"ABCD2345EFGH","expires_at":"2026-11-07T10:00:00.123Z","install_url":"https://example.invalid/install.sh"}"#)
        let code = try await scannerService().createScannerLinkCode(accessToken: "t")
        #expect(code.code == "ABCD2345EFGH")
        #expect(code.expiresAt != nil)
        #expect(code.command == "curl -fsSL 'https://example.invalid/install.sh' | sh -s -- ABCD2345EFGH")
        #expect(ScannerStubProtocol.bodies["/rest/v1/rpc/scanner_link_code_create"] == "{}")
    }

    @Test
    func linkCodeRateLimitIsItsOwnError() async {
        ScannerStubProtocol.responses["/rest/v1/rpc/scanner_link_code_create"] = (200, #"{"ok":false,"reason":"rate"}"#)
        await #expect(throws: ScannerLinkCodeError.rateLimited) {
            _ = try await scannerService().createScannerLinkCode(accessToken: "t")
        }
    }

    @Test
    func devicesDecodeAndDropRowsWithoutAnID() async throws {
        ScannerStubProtocol.responses["/rest/v1/rpc/scanner_devices"] = (200, #"""
        [{"device_id":"d1","name":"home-mac","os":"macos-arm64","version":"0.1.0","linked_at":"2026-11-07T01:00:00Z",
          "last_upload_at":"2026-11-07T02:00:00Z","last_scan_at":"2026-11-07T02:00:00Z","month_total":1234567},
         {"name":"broken"},
         {"device_id":"d2","os":"linux-x86_64","month_total":null}]
        """#)
        let rows = try await scannerService().fetchScannerDevices(accessToken: "t")
        #expect(rows.map(\.id) == ["d1", "d2"])
        #expect(rows[0].kindLabel == "맥" && rows[1].kindLabel == "리눅스")
        #expect(rows[0].monthTotal == 1_234_567 && rows[1].monthTotal == 0)
        #expect(rows[1].name == "다른 기기")
    }

    @Test
    func revokeSendsTheDeviceID() async throws {
        ScannerStubProtocol.responses["/rest/v1/rpc/scanner_device_revoke"] = (200, #"{"ok":true}"#)
        let ok = try await scannerService().revokeScannerDevice(accessToken: "t", deviceID: "d1")
        #expect(ok)
        #expect(ScannerStubProtocol.bodies["/rest/v1/rpc/scanner_device_revoke"] == #"{"p_device_id":"d1"}"#)
    }
}

// MARK: - 순수

@Test
func scannerInstallCommandQuotesTheURLAndKeepsOnlyCodeLetters() {
    let cmd = ScannerInstallCommand.make(code: "abcd-2345 efgh;rm", installURL: URL(string: "https://x.invalid/i.sh?a='b'"))
    #expect(cmd == "curl -fsSL 'https://x.invalid/i.sh?a=b' | sh -s -- ABCD2345EFGHRM")
    #expect(ScannerInstallCommand.make(code: "AB", installURL: nil).contains(ScannerInstallCommand.fallbackInstallURL.absoluteString))
}

@Test
func remoteScannerPageStateSeparatesEmptyFromNotLoaded() {
    #expect(RemoteScannerPageState.of(loaded: false, loading: false, failed: false, count: 0) == .loading)
    #expect(RemoteScannerPageState.of(loaded: true, loading: false, failed: false, count: 0) == .empty)
    #expect(RemoteScannerPageState.of(loaded: true, loading: false, failed: true, count: 0) == .failed)
    #expect(RemoteScannerPageState.of(loaded: true, loading: true, failed: true, count: 2) == .list)
}

@Test
func remoteScannerTextSaysHowFreshTheMachineIs() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func device(_ ago: TimeInterval?) -> ScannerDevice {
        ScannerDevice(id: "d", name: "n", os: "linux", version: "", linkedAt: nil,
                      lastUploadAt: nil, lastScanAt: ago.map { now.addingTimeInterval(-$0) }, monthTotal: 0)
    }
    #expect(RemoteScannerText.lastSeen(device(nil), now: now) == "아직 집계 전")
    #expect(RemoteScannerText.lastSeen(device(20), now: now) == "방금 집계")
    #expect(RemoteScannerText.lastSeen(device(600), now: now) == "10분 전 집계")
    #expect(RemoteScannerText.lastSeen(device(7200), now: now) == "2시간 전 집계")
    #expect(RemoteScannerText.expiry(now.addingTimeInterval(299), now: now) == "5분 안에 한 번만 쓸 수 있어요.")
    #expect(RemoteScannerText.expiry(now.addingTimeInterval(-1), now: now) == "만료됐어요. 다시 만들어 주세요.")
    #expect(RemoteScannerText.makeCodeFailure(ScannerLinkCodeError.rateLimited).contains("한 시간"))
}

// MARK: - 그림(설정 본문 행 · 원격 기계 쪽) — 창 높이 안 · 노란 상자 0

@MainActor
@Suite(.serialized)
struct AingScanSettingsRenderTests {
    private func render(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
        else { throw AingScanRenderError.failed }
        return bitmap
    }

    private func yellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
        guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
        let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
        var hits = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let o = y * bpr + x * spp
                if data[o] >= 240 && data[o + 1] >= 195 && data[o + 2] <= 40 { hits += 1 }
            }
        }
        return hits
    }

    @Test(.gomokuDefaultsCleanup)
    func 원격_기계_쪽은_명령과_목록을_창_안에_그린다() throws {
        let (store, _) = makeMessageReadStore("aing-scan-render")
        // 쪽 열기 전: 설정 본문에 행이 있다.
        let settings = try render(CheckSettingsView(store: store, launchAtLoginSeed: false).frame(width: CheckSettingsView.preferredWidth))
        MessagePanelSnapshots.save(settings, name: "aing-scan-settings-body.png")

        store.showsRemoteScannerInSettings = true
        store.remoteScannerLoaded = true
        let empty = try render(CheckSettingsView(store: store, launchAtLoginSeed: false).frame(width: CheckSettingsView.preferredWidth))
        MessagePanelSnapshots.save(empty, name: "aing-scan-settings-empty.png")

        store.remoteScannerLinkCode = ScannerLinkCode(
            code: "K7QW2M9XRT4P", expiresAt: MessageReadFixture.now.addingTimeInterval(540),
            installURL: URL(string: "https://example.invalid/aing-scan/install.sh")
        )
        store.remoteScannerDevices = [
            ScannerDevice(id: "d1", name: "home-mac", os: "macos-arm64", version: "0.1.0",
                          linkedAt: nil, lastUploadAt: nil, lastScanAt: MessageReadFixture.now.addingTimeInterval(-420),
                          monthTotal: 182_400_000),
            ScannerDevice(id: "d2", name: "gpu-server", os: "linux-x86_64", version: "0.1.0",
                          linkedAt: nil, lastUploadAt: nil, lastScanAt: MessageReadFixture.now.addingTimeInterval(-7_300),
                          monthTotal: 5_920_000),
        ]
        let list = try render(CheckRemoteScannerSettingsPage(store: store, now: { MessageReadFixture.now })
            .padding(14).frame(width: CheckSettingsView.preferredWidth).background(CheckTheme.background))
        MessagePanelSnapshots.save(list, name: "aing-scan-settings-list.png")

        #expect(Double(settings.pixelsHigh) / 2 <= CheckSettingsWindowController.defaultContentSize.height, "설정 본문이 창 높이를 넘었다")
        // 노란 상자 검사는 새 쪽에만 건다 — 설정 본문의 별명·상태메시지 입력칸(NSTextField)은 원래 렌더러에서 노란 상자다.
        for (name, image) in [("빈 목록", empty), ("명령+목록", list)] {
            #expect(Double(image.pixelsHigh) / 2 <= CheckSettingsWindowController.defaultContentSize.height, "\(name) 화면이 설정 창 높이를 넘었다")
            #expect(yellowPixels(image) == 0, "\(name) 화면에 노란 상자가 있다(시스템 컨트롤)")
        }
        // 닫으면 연결 코드까지 지운다.
        store.closeRemoteScannerSettings()
        #expect(!store.showsRemoteScannerInSettings && store.remoteScannerLinkCode == nil)
    }
}

private enum AingScanRenderError: Error { case failed }
