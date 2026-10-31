import Foundation
import Testing
@testable import CheckCore

// MARK: - 0.3.70 핫픽스 — 반응 말풍선 덮개가 CPU 를 120% 쓰던 고리(10-31 실측, PID sample)
//
// 0.3.69 의 덮개는 `.task(id:)` 안에서 `try? await Task.sleep` 뒤 `expiryTick &+= 1` 을 하고 `.id(expiryTick)` 로 덮개를
// 통째로 새로 만들었다. 새로 만들면 도는 task 가 취소되고, 취소된 task 는 `try?` 로 CancellationError 를 삼킨 채 곧바로
// expiryTick 을 또 올려 다시 새로 만든다 — 말풍선이 하나도 없어도, 창이 안 보여도 쉬지 않는 고리였다.
// 렌더 시험으로는 CPU 를 못 재므로 고리를 이루는 세 조각이 다시 생기지 않는지 소스로 묶는다(주석을 걷고 잰다).
@Test("반응 덮개: 정체성을 바꾸지 않고(.id 없음) · 취소되면 아무것도 안 하고 · 보일 말풍선이 없으면 자지 않는다")
func v0370ReactionOverlayHasNoRebuildLoop() throws {
    let url = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/RummyReactionOverlay.swift")
    let raw = try String(contentsOf: url, encoding: .utf8)
    let code = raw.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let r = line.range(of: "//") else { return String(line) }
            return String(line[..<r.lowerBound])
        }
        .joined(separator: "\n")
    #expect(!code.contains(".id(expiryTick)"), "덮개 정체성을 expiryTick 으로 바꾸면 task 취소 → 증가 → 재생성 고리가 돈다")
    #expect(!code.contains("try? await Task.sleep"), "취소를 삼키면 곧바로 증가로 넘어간다 — catch 에서 돌아가야 한다")
    #expect(code.contains("catch { return }"))
    #expect(code.contains("guard live else { return }"), "보일 말풍선이 없을 때도 자고 증가하면 빈 덮개가 영원히 깨어난다")
}
