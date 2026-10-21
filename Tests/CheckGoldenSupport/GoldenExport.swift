import Foundation

// 골든 바탕(W0-b · K1 · C§5.3·§5.4 · A§4-2): 내보내기 한 건 = 머리말 + cases 를 정규 바이트로 만들어
//   · 비교 모드(기본) — 커밋된 파일과 바이트까지 같아야 통과. 다르면 첫 불일치 경로와 case id 를 말한다.
//   · 쓰기 모드(`CHECK_GOLDEN_WRITE=1`) — 파일을 다시 쓰고 **언제나 실패**로 돌려준다(실수로 초록이 되지 않게).
// 그리고 `CHECK_GOLDEN_RUN_DIR` 가 있으면(= scripts/golden-export.sh 실행) 영수증을 남긴다. 스크립트가 영수증으로
// `_manifest.json` 을 조립하고, 영수증 없는 파일(고아)·두 번 쓴 골든을 빨갛게 한다.
//
// 이 타깃은 Testing 을 import 하지 않는다(제품 빌드가 이 타깃을 컴파일해도 시험 프레임워크를 찾지 않게).
// 시험 쪽 얇은 도우미(`GoldenExport/_base/GoldenEmit.swift`)가 결과를 `#expect` 로 옮긴다.

/// 동일성 등급(C§5.1).
package enum GoldenEquivalence: String, Sendable {
    /// 같은 입력이면 모든 출력 비트가 같다.
    case bit
    /// 정수·열거 출력만 같다(실수는 허용 오차를 골든 spec 에 적는다).
    case discrete
    /// 정답 집합 안에 든다.
    case set
}

/// 골든을 두는 뿌리.
package enum GoldenRoot: String, Sendable {
    /// 계약: `contract/golden/<이름>.json`. `_manifest.json` 에 들고, Kotlin 이 소비 시험을 가져야 한다(GoldenCoverageTest).
    case contract
    /// 실험 표: `multiplatform/testkit/src/desktopTest/resources/golden/<이름>.json`. 기기·런타임 차이를 재는 탐침
    /// (C-X1 pow · C-X4 글자 · C-X12 KST 등)이 읽는다. 계약이 아니라 `_manifest.json` 에 들지 않는다(영수증은 남긴다).
    case probe

    package var directory: String {
        switch self {
        case .contract: return "contract/golden"
        case .probe: return "multiplatform/testkit/src/desktopTest/resources/golden"
        }
    }
}

/// 내보낼 골든 한 벌. `generator` 는 받지 않는다 — 부른 시험 파일(#filePath)에서 저장소 상대 경로로 정한다.
package struct GoldenFile: Sendable {
    package var golden: String
    package var equivalence: GoldenEquivalence
    package var swiftSources: [String]
    package var platformSensitive: Bool
    package var spec: [String: GoldenJSON]
    package var cases: [GoldenJSON]
    package var root: GoldenRoot

    package init(golden: String, equivalence: GoldenEquivalence, swiftSources: [String], platformSensitive: Bool = false,
                 spec: [String: GoldenJSON], cases: [GoldenJSON], root: GoldenRoot = .contract) {
        self.golden = golden
        self.equivalence = equivalence
        self.swiftSources = swiftSources
        self.platformSensitive = platformSensitive
        self.spec = spec
        self.cases = cases
        self.root = root
    }

    /// 형식 판(머리말 `schema`). 바꾸면 Kotlin 로더·golden-digest 를 같은 커밋에서 바꾼다.
    package static let schema = 1
    /// 파일 하나의 크기 상한(C§5.3 예산).
    package static let maxBytes = 2 * 1024 * 1024

    package func json(generator: String) -> GoldenJSON {
        .object([
            "golden": .string(golden),
            "schema": .int(Self.schema),
            "equivalence": .string(equivalence.rawValue),
            "generator": .string(generator),
            "swiftSources": .array(swiftSources.map(GoldenJSON.string)),
            "platformSensitive": .bool(platformSensitive),
            "spec": .object(spec),
            "cases": .array(cases),
        ])
    }

    package var relativePath: String { "\(root.directory)/\(golden).json" }
}

/// 내보내기 한 건의 결과. 시험 쪽 도우미가 `passed == false` 면 `message` 로 실패를 기록한다.
package struct GoldenOutcome: Sendable, Equatable {
    package enum Status: String, Sendable { case same, differs, missing, written, invalid }

    package var status: Status
    package var path: String
    package var message: String

    package var passed: Bool { status == .same }
}

package enum GoldenMode: Equatable, Sendable {
    case compare
    case write

    /// `CHECK_GOLDEN_WRITE` 는 "1" 만 쓰기다. 빈 값·없음은 비교. 그 밖의 값은 오타로 보고 빨갛게 한다
    /// ("true" 를 줬는데 조용히 비교로 돌면 '다시 썼다'고 믿게 된다).
    package static func from(environment: [String: String]) -> Result<GoldenMode, GoldenJSONError> {
        switch environment["CHECK_GOLDEN_WRITE"] ?? "" {
        case "": return .success(.compare)
        case "1": return .success(.write)
        case let other: return .failure(GoldenJSONError("CHECK_GOLDEN_WRITE 는 1 만 받는다(받은 값 \(other.debugDescription))"))
        }
    }
}

package enum GoldenExport {
    /// 골든 이름: 영역/이름(소문자·숫자·`-`, 이름 마디는 `.`·`_` 도). 예: `rng/splitmix64`, `w0b-probe/pow3`.
    private static let namePattern = #"^[a-z0-9][a-z0-9-]*(/[a-z0-9][a-z0-9._-]*)+$"#

    /// 저장소 뿌리: `CHECK_GOLDEN_REPO_ROOT` 가 있으면 그것, 없으면 시험 파일에서 위로 올라가 `Package.swift` 를 찾는다.
    package static func repoRoot(from filePath: String, environment: [String: String]) -> URL? {
        if let given = environment["CHECK_GOLDEN_REPO_ROOT"], !given.isEmpty {
            return URL(fileURLWithPath: given, isDirectory: true).resolvingSymlinksInPath()
        }
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// 내보내기 한 건. `generatorFilePath` 는 기본값 그대로 두면 **부른 쪽 파일**이 된다(도우미가 받아 넘긴다).
    package static func emit(_ file: GoldenFile,
                             generatorFilePath: String = #filePath,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> GoldenOutcome {
        func invalid(_ message: String) -> GoldenOutcome {
            GoldenOutcome(status: .invalid, path: file.relativePath, message: "골든 \(file.golden): \(message)")
        }
        let mode: GoldenMode
        switch GoldenMode.from(environment: environment) {
        case .success(let value): mode = value
        case .failure(let error): return invalid(error.description)
        }
        guard let root = repoRoot(from: generatorFilePath, environment: environment) else {
            return invalid("저장소 뿌리(Package.swift)를 못 찾았다: \(generatorFilePath)")
        }
        guard file.golden.range(of: namePattern, options: .regularExpression) != nil else {
            return invalid("이름 규칙(영역/이름, 소문자) 밖이다")
        }
        // 두 경로 모두 심볼릭 링크를 푼다(/tmp → /private/tmp). 한쪽만 표준화하면 같은 파일이 '저장소 밖'으로 보인다.
        let resolvedRoot = root.resolvingSymlinksInPath().path
        let rootPath = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        let generatorPath = URL(fileURLWithPath: generatorFilePath).resolvingSymlinksInPath().path
        guard generatorPath.hasPrefix(rootPath) else {
            return invalid("생성 시험 파일이 저장소 밖이다: \(generatorPath)")
        }
        let generator = String(generatorPath.dropFirst(rootPath.count))
        guard generator.hasPrefix("Tests/"), generator.contains("/GoldenExport/") else {
            return invalid("생성 시험은 Tests/<타깃>/GoldenExport/<갈래>/ 아래에 둔다: \(generator)")
        }
        guard !file.swiftSources.isEmpty else { return invalid("swiftSources 가 비었다(지문을 셀 원본이 없다)") }
        for source in file.swiftSources {
            guard source.hasPrefix("Sources/") || source.hasPrefix("Tests/checkTests/Fixtures/"),
                  !source.contains(".."),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(source).path) else {
                return invalid("swiftSources 의 \(source) 가 없거나 Sources/ 밖이다")
            }
        }
        guard !file.cases.isEmpty else { return invalid("cases 가 비었다") }
        var ids = Set<String>()
        for (index, item) in file.cases.enumerated() {
            guard case .string(let id)? = item["id"], !id.isEmpty else {
                return invalid("cases[\(index)] 에 글자 id 가 없다(실패 문구가 case 를 가리켜야 한다)")
            }
            guard ids.insert(id).inserted else { return invalid("case id \(id) 가 겹친다") }
        }

        let data: Data
        do {
            data = try file.json(generator: generator).canonicalData()
        } catch {
            return invalid("정규 글자를 못 만들었다 — \(error)")
        }
        guard data.count <= GoldenFile.maxBytes else {
            return invalid("\(data.count) 바이트 — 파일 하나 상한 \(GoldenFile.maxBytes) 를 넘는다")
        }
        if let verbose = environment["CHECK_GOLDEN_VERBOSE"], !verbose.isEmpty,
           let match = file.cases.first(where: { $0["id"] == .string(verbose) }),
           let text = try? match.canonicalText() {
            print("[golden] \(file.golden) case \(verbose):\n\(text)", terminator: "")
        }

        let target = root.appendingPathComponent(file.relativePath)
        let existing = try? Data(contentsOf: target)
        let outcome: GoldenOutcome
        switch mode {
        case .write:
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            } catch {
                return invalid("쓰기 실패 — \(error)")
            }
            let change = existing == data ? "내용은 그대로" : (existing == nil ? "새로 만듦" : "내용이 바뀜")
            outcome = GoldenOutcome(status: .written, path: file.relativePath,
                                    message: "CHECK_GOLDEN_WRITE=1: \(file.relativePath) 를 다시 썼다(\(change)) — 쓰기 모드는 실패로 끝난다. "
                                        + "git diff 로 바뀐 이유를 확인하고 비교 모드로 다시 돌린다")
        case .compare:
            if existing == data {
                outcome = GoldenOutcome(status: .same, path: file.relativePath, message: "")
            } else if let existing {
                outcome = GoldenOutcome(status: .differs, path: file.relativePath,
                                        message: "골든 \(file.relativePath) 가 지금 Swift 가 낸 값과 다르다 — "
                                            + describeDifference(new: data, old: existing, cases: file.cases)
                                            + ". 의도한 엔진 변경이면 CHECK_GOLDEN_WRITE=1 scripts/golden-export.sh 로 다시 쓰고 "
                                            + "같은(또는 바로 다음) 커밋에서 Kotlin 을 따라 고친다(C§5.4)")
            } else {
                outcome = GoldenOutcome(status: .missing, path: file.relativePath,
                                        message: "골든 \(file.relativePath) 가 없다 — CHECK_GOLDEN_WRITE=1 scripts/golden-export.sh 로 만든다")
            }
        }
        if let receiptError = writeReceipt(file: file, generator: generator, status: outcome.status, environment: environment) {
            return invalid(receiptError)
        }
        return outcome
    }

    /// 첫 불일치(경로 + case id). 파일이 정규 JSON 이 아니면 그 사실을 말한다.
    private static func describeDifference(new: Data, old: Data, cases: [GoldenJSON]) -> String {
        guard let newValue = try? GoldenJSON.parse(new), let oldValue = try? GoldenJSON.parse(old) else {
            return "커밋된 파일을 정규 JSON 으로 못 읽었다(손으로 고쳤나?)"
        }
        guard let path = GoldenJSON.firstDifference(newValue, oldValue) else {
            return "값은 같고 바이트만 다르다(정규 형식이 아닌 파일 — 손으로 고쳤나?)"
        }
        var label = "첫 불일치 \(path)"
        if let open = path.range(of: "$.cases["), let close = path[open.upperBound...].firstIndex(of: "]"),
           let index = Int(path[open.upperBound..<close]), index < cases.count, case .string(let id)? = cases[index]["id"] {
            label += " (case id=\(id), 자세히: CHECK_GOLDEN_VERBOSE=\(id))"
        }
        return label
    }

    /// 영수증: `<run>/receipts/<뿌리>__<이름>.json`. 같은 골든을 두 시험이 쓰면 두 번째가 실패한다.
    private static func writeReceipt(file: GoldenFile, generator: String, status: GoldenOutcome.Status,
                                     environment: [String: String]) -> String? {
        guard let run = environment["CHECK_GOLDEN_RUN_DIR"], !run.isEmpty else { return nil }
        let dir = URL(fileURLWithPath: run, isDirectory: true).appendingPathComponent("receipts", isDirectory: true)
        let name = "\(file.root.rawValue)__" + file.golden.replacingOccurrences(of: "/", with: "__") + ".json"
        let receipt: GoldenJSON = .object([
            "golden": .string(file.golden),
            "root": .string(file.root.rawValue),
            "path": .string(file.relativePath),
            "generator": .string(generator),
            "swiftSources": .array(file.swiftSources.map(GoldenJSON.string)),
            "platformSensitive": .bool(file.platformSensitive),
            "equivalence": .string(file.equivalence.rawValue),
            "status": .string(status.rawValue),
            "cases": .int(file.cases.count),
        ])
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try receipt.canonicalData().write(to: dir.appendingPathComponent(name), options: .withoutOverwriting)
            return nil
        } catch {
            return "영수증을 못 남겼다(같은 골든을 두 시험이 쓰나?) — \(name): \(error.localizedDescription)"
        }
    }
}
