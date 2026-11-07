import Foundation

// MARK: - 원격 기계 스캐너(aing-scan) 연결 — 맥 설정 [원격 기계 연결]
//
// 서버 계약(20261110120000_token_scanner.sql): `scanner_link_code_create()` · `scanner_devices()` ·
// `scanner_device_revoke(p_device_id)` — 셋 다 security definer · authenticated 전용. 스캐너 자신이 부르는
// `scanner_link` · `scanner_upload` · `scanner_unlink`(anon)는 aing-scan 패키지가 부른다 — 이 앱은 부르지 않는다.
//
// 이 파일이 지키는 것:
// ① 연결 코드는 **화면에만** 있다. 저장하지 않고 로그로 남기지 않는다(10분 · 한 번만 쓰이지만 그 10분 동안은 열쇠다).
// ② 행의 칸은 전부 옵셔널로 받는다(차단 목록과 같은 규약) — 서버가 칸 하나를 달리 불러도 목록이 통째로 사라지지 않게.
// ③ 함수가 없는 서버(앱이 db push 보다 먼저 나간 경우)에서 접는 판단은 스토어 몫이다 — 여기서 삼키지 않는다.

/// 설치 명령 한 줄. 사용자는 이것을 원격 기계 터미널에 붙여넣는다.
package enum ScannerInstallCommand {
    /// 서버가 주소를 안 주면 쓰는 자리(공개 배포 때 확정한다 — 그 전에는 서버 값이 늘 온다).
    package static let fallbackInstallURL = URL(string: "https://github.com/yehsung/check/releases/download/aing-scan/install.sh")!

    /// `curl -fsSL '<주소>' | sh -s -- <코드>`. 주소는 작은따옴표로 감싸고, 코드는 서버가 준 글자(대문자·숫자)만 남긴다.
    package static func make(code: String, installURL: URL?) -> String {
        let safeCode = String(code.uppercased().filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) })
        let url = (installURL ?? fallbackInstallURL).absoluteString.replacingOccurrences(of: "'", with: "")
        return "curl -fsSL '\(url)' | sh -s -- \(safeCode)"
    }
}

/// 서버가 내준 일회용 연결 코드.
package struct ScannerLinkCode: Equatable, Sendable {
    package let code: String
    package let expiresAt: Date?
    package let installURL: URL?

    package init(code: String, expiresAt: Date?, installURL: URL?) {
        self.code = code
        self.expiresAt = expiresAt
        self.installURL = installURL
    }

    package var command: String { ScannerInstallCommand.make(code: code, installURL: installURL) }
}

package enum ScannerLinkCodeError: Error, Equatable {
    /// 한 시간에 열 번을 넘겼다.
    case rateLimited
    /// 그 밖의 거절(서버가 말한 이유).
    case rejected(String)
}

/// 연결된 원격 기계 한 대(맥 설정 목록의 한 줄).
package struct ScannerDevice: Equatable, Sendable, Identifiable {
    package let id: String
    package let name: String
    package let os: String
    package let version: String
    package let linkedAt: Date?
    package let lastUploadAt: Date?
    package let lastScanAt: Date?
    /// 이번 달(KST) 그 기계가 올린 토큰(Claude+Codex+안티그래비티).
    package let monthTotal: Int

    package init(
        id: String, name: String, os: String, version: String,
        linkedAt: Date?, lastUploadAt: Date?, lastScanAt: Date?, monthTotal: Int
    ) {
        self.id = id
        self.name = name
        self.os = os
        self.version = version
        self.linkedAt = linkedAt
        self.lastUploadAt = lastUploadAt
        self.lastScanAt = lastScanAt
        self.monthTotal = monthTotal
    }

    /// 목록에 보일 기계 종류("맥" · "리눅스").
    package var kindLabel: String {
        if os.hasPrefix("macos") { return "맥" }
        if os.hasPrefix("linux") { return "리눅스" }
        return os.isEmpty ? "기기" : os
    }
}

#if os(macOS)
extension SupabaseWorkService {
    static let scannerLinkCodeCreatePath = "/rest/v1/rpc/scanner_link_code_create"
    static let scannerDevicesPath = "/rest/v1/rpc/scanner_devices"
    static let scannerDeviceRevokePath = "/rest/v1/rpc/scanner_device_revoke"

    /// 일회용 연결 코드(10분 · 한 번). 거절은 `ScannerLinkCodeError` 로 던진다.
    package func createScannerLinkCode(accessToken: String) async throws -> ScannerLinkCode {
        let data = try await send(
            path: Self.scannerLinkCodeCreatePath, method: "POST", body: EmptyBody(),
            accessToken: accessToken, prefer: nil
        )
        struct Row: Decodable {
            let ok: Bool?
            let reason: String?
            let code: String?
            let expiresAt: String?
            let installUrl: String?
        }
        let row = try decoder.decode(Row.self, from: data)
        guard row.ok == true, let code = row.code, !code.isEmpty else {
            if row.reason == "rate" { throw ScannerLinkCodeError.rateLimited }
            throw ScannerLinkCodeError.rejected(row.reason ?? "unknown")
        }
        return ScannerLinkCode(
            code: code,
            expiresAt: row.expiresAt.flatMap { parseDate($0) },
            installURL: row.installUrl.flatMap { URL(string: $0) }
        )
    }

    /// 내 원격 기계 목록(끊은 기계는 빠진다).
    package func fetchScannerDevices(accessToken: String) async throws -> [ScannerDevice] {
        let data = try await send(
            path: Self.scannerDevicesPath, method: "POST", body: EmptyBody(),
            accessToken: accessToken, prefer: nil
        )
        struct Row: Decodable {
            let deviceId: String?
            let name: String?
            let os: String?
            let version: String?
            let linkedAt: String?
            let lastUploadAt: String?
            let lastScanAt: String?
            let monthTotal: Int?
        }
        let rows = try decoder.decode([Row].self, from: data)
        return rows.compactMap { scannerRow -> ScannerDevice? in
            guard let id = scannerRow.deviceId, !id.isEmpty else { return nil }
            return ScannerDevice(
                id: id,
                name: scannerRow.name.flatMap { $0.isEmpty ? nil : $0 } ?? "다른 기기",
                os: scannerRow.os ?? "",
                version: scannerRow.version ?? "",
                linkedAt: scannerRow.linkedAt.flatMap { parseDate($0) },
                lastUploadAt: scannerRow.lastUploadAt.flatMap { parseDate($0) },
                lastScanAt: scannerRow.lastScanAt.flatMap { parseDate($0) },
                monthTotal: max(0, scannerRow.monthTotal ?? 0)
            )
        }
    }

    /// 한 기계의 연결을 끊는다. 그 기계의 스캐너는 다음 올림에서 'revoked' 를 받고 스스로 예약을 끈다.
    /// 반환: 서버가 실제로 끊었는가(이미 끊긴 · 남의 기계면 false).
    package func revokeScannerDevice(accessToken: String, deviceID: String) async throws -> Bool {
        struct Body: Encodable { let pDeviceId: String }
        let data = try await send(
            path: Self.scannerDeviceRevokePath, method: "POST", body: Body(pDeviceId: deviceID),
            accessToken: accessToken, prefer: nil
        )
        struct Row: Decodable { let ok: Bool? }
        return (try? decoder.decode(Row.self, from: data))?.ok == true
    }
}
#endif
