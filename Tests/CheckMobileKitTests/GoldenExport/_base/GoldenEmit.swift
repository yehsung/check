import CheckGoldenSupport
import Testing

// 골든 바탕(W0-b): 폰 타깃 GoldenExport 스위트(W1-d 와이어 녹음 · W2-a 세션 …)가 부르는 한 줄.
// 맥 타깃(Tests/checkTests/GoldenExport/_base/GoldenEmit.swift)과 같은 도우미다 — 시험 타깃끼리는 파일을 나눌 수 없어 두 벌이다.
// 규칙: 스위트 이름은 `GoldenExport…` 로 시작하는 @Suite struct, 자유 함수 @Test 금지 — 자유 함수도 --filter 에 걸려 돌지만
// scripts/golden-export.sh 의 목록 정규식(`.GoldenExport…/메서드`)이 못 세서 "돈 수 ≠ 목록 수"로 빨갛다(맥 타깃 GoldenEmit.swift 주석).

func goldenEmit(_ file: GoldenFile, filePath: String = #filePath, sourceLocation: SourceLocation = #_sourceLocation) {
    let outcome = GoldenExport.emit(file, generatorFilePath: filePath)
    #expect(outcome.passed, Comment(rawValue: outcome.message), sourceLocation: sourceLocation)
}
