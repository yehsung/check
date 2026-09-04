import Foundation
import Testing
@testable import check

/// 실제 `codex app-server` 를 띄우는 **opt-in 라이브 프로브**. `CHECK_LIVE_CODEX_PROBE=1` 일 때만 돈다(기본은 즉시 통과).
///
/// 왜 있나: 단위 테스트는 규약상 실제 codex 를 절대 띄우지 않으므로(CodexAccountUsageProbe 주석), 실행 파일 탐색 →
/// PATH 조립 → 프로세스 기동 → JSON-RPC 왕복 → 파싱의 **실물 경로**는 이 테스트로만 확인된다. GUI 앱의 환경을 흉내내려면
/// `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin CHECK_LIVE_CODEX_PROBE=1 swift test --filter LiveCodexProbe` 로
/// 돌려라(로그인 셸 조회가 codex 를 찾아야 통과한다). 결과는 상태값과 이번 달 합만 찍는다(버킷 원본은 출력하지 않는다).
@Suite struct LiveCodexProbeTests {
    @Test func liveAccountProbeFindsCodexWithoutPATHAndReadsUsage() async throws {
        guard ProcessInfo.processInfo.environment["CHECK_LIVE_CODEX_PROBE"] == "1" else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let started = Date()
        let result = await CodexAccountUsageProbe.fetch(
            homeDirectory: home, appVersion: "live-test", cache: CodexAccountUsageProbe.LocateCache()
        )
        let elapsed = Date().timeIntervalSince(started)
        switch result {
        case .success(let usage):
            let month = TokenUsageMonthKey.current()
            print("LIVE_PROBE ok elapsed=\(String(format: "%.2f", elapsed))s buckets=\(usage.buckets.count) lifetime=\(usage.lifetimeTokens ?? -1) month[\(month)]=\(usage.monthTotal(month)) latest=\(usage.latestBucketDate ?? "-")")
            #expect(usage.buckets.count > 0)
            #expect((usage.lifetimeTokens ?? 0) > 0)
            #expect(elapsed < 15)
        case .failure(let failure):
            print("LIVE_PROBE FAILED status=\(failure.status) reason=\(failure.reason) elapsed=\(String(format: "%.2f", elapsed))s")
            Issue.record("라이브 프로브 실패: \(failure.status) — \(failure.reason)")
        }
    }
}
