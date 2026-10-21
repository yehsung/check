import CheckGoldenSupport
import Foundation
import Testing

// 골든 바탕(W0-b): GoldenExport 스위트가 부르는 한 줄. 지원 타깃(CheckGoldenSupport)은 Testing 을 import 하지 않으므로
// 결과를 여기서 `#expect` 로 옮긴다. 생성 시험 경로(generator)는 **부른 파일**이다(#filePath 를 그대로 넘긴다).
//
// 갈래 규칙(contract/README.md):
//   · 스위트는 `@Suite struct GoldenExport<갈래>` — 이름이 `GoldenExport` 로 시작해야 scripts/golden-export.sh 의
//     `--filter GoldenExport` 가 잡고, `swift test list` 의 `.GoldenExport…/메서드` 줄로 개수가 세진다.
//   · 자유 함수 @Test 는 쓰지 않는다. GoldenExport*.swift 파일 안의 자유 함수는 시험 ID 에 파일 이름이 들어 --filter 에
//     걸려 **돌기는 한다**(W0-b 검증 실측). 그러나 목록 정규식이 스위트 메서드만 세므로 "돈 수 ≠ 목록 수"로 빨갛다 —
//     스크립트가 xunit 결과로 스위트 밖 시험 이름을 짚어 준다.
//   · UserDefaults·키체인·네트워크·창을 쓰지 않는다.

func goldenEmit(_ file: GoldenFile, filePath: String = #filePath, sourceLocation: SourceLocation = #_sourceLocation) {
    let outcome = GoldenExport.emit(file, generatorFilePath: filePath)
    #expect(outcome.passed, Comment(rawValue: outcome.message), sourceLocation: sourceLocation)
}

/// 저장소 뿌리(이 파일 기준). 정적 계약 시험이 파일을 읽을 때 쓴다.
enum GoldenRepo {
    static let root: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir.deleteLastPathComponent()
        }
        fatalError("Package.swift 를 못 찾았다")
    }()

    static func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
}
