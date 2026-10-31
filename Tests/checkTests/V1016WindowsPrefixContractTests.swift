import CheckCore
import Foundation
import Testing

// MARK: - 1.0.16 기기 종류 판정이 서버와 같은 글자인가
//
// 폰·맥·위젯은 `AILimitDevicePlatform.windowsPrefix` 로, 서버는 `desktop_device_platform(text)` 로 같은 판정을 한다.
// 두 벌이라 어긋나면 양쪽 다 그럴듯한 이름을 그린 채 조용히 갈린다. 그래서 SQL 본문에서 접두를 읽어 견준다.
// (`AILimitDeviceLabelContract.maxScalars` 와 서버 CHECK 를 견주는 `V0347AILimitsDevicesMigrationTests` 와 같은 방식.)
private let v1016AxisMigration = "20261101120000_desktop_windows_axis.sql"

private struct V1016Error: Error, CustomStringConvertible {
    let description: String
}

/// `supabase/` 는 .gitignore 라 워크트리에 없다 — 조상을 훑어 `supabase/migrations` 를 찾는다(V0347 과 같은 방식).
private func v1016MigrationText() throws -> String {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations/\(v1016AxisMigration)")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        directory = directory.deletingLastPathComponent()
    }
    throw V1016Error(description: "\(v1016AxisMigration) 를 못 찾았다")
}

@Suite struct V1016WindowsPrefixContractTests {
    @Test("서버 `desktop_device_platform` 의 접두와 앱 상수가 같은 글자다")
    func prefixMatchesServerFunction() throws {
        let sql = try v1016MigrationText()
        let head = "create or replace function public.desktop_device_platform"
        let start = try #require(sql.range(of: head), "함수 정의를 못 찾았다")
        let body = sql[start.upperBound...]
        let marker = "p_device_id like '"
        let open = try #require(body.range(of: marker), "like 절을 못 찾았다 — 판정 규칙이 바뀌었으면 앱도 같이 바꿔라")
        let rest = body[open.upperBound...]
        let close = try #require(rest.firstIndex(of: "'"))
        #expect(String(rest[..<close]) == "\(AILimitDevicePlatform.windowsPrefix)%")
    }

    @Test("서버 프로브가 재는 입력을 앱도 같은 쪽으로 읽는다 — 대소문자를 가린다")
    func probeInputsReadTheSame() throws {
        let sql = try v1016MigrationText()
        // 프로브 줄이 사라지면 "서버가 대문자를 mac 으로 읽는다"는 근거도 같이 사라진다.
        #expect(sql.contains("desktop_device_platform('WIN:abc') <> 'mac'"))
        #expect(sql.contains("desktop_device_platform('A0A0A0A0-0000') <> 'mac'"))
        #expect(AILimitDevicePlatform.of(deviceID: "WIN:abc") == .mac)
        #expect(AILimitDevicePlatform.of(deviceID: "A0A0A0A0-0000") == .mac)
        #expect(AILimitDevicePlatform.of(deviceID: "win:0b7e") == .windows)
    }
}
