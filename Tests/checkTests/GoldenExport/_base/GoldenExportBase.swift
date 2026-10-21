import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 골든 바탕(W0-b): 견본 골든 `rng/splitmix64`(C§5.2 G2) + 골든 목록의 정적 잠금(고아 금지 — A§4-2 Swift 쪽).
//
// rng 는 모든 게임의 뿌리다(C§5.1 E1). Kotlin `core/foundation/…/rng/SplitMix64` 가 이 파일과 비트로 대조한다
// (`SplitMix64GoldenTest`). Swift 에는 같은 알고리즘이 두 벌 있다 — MiniGameRandom(게임)과 GomokuAISplitMix64(오목 AI).
// Kotlin 은 하나로 합친다(C§3.2 F-1). 그래서 이 내보내기가 두 벌이 같은 열을 낸다는 것을 먼저 단언한다.

@Suite("GoldenExport _base — 견본 골든 rng/splitmix64 · 골든 목록 정적 잠금")
struct GoldenExportBase {
    /// (id, 시드). C§5.2: 0 · 1 · 42 · 2^63−1 · 2^64−1 + 게임이 실제로 쓰는 시드와 소금.
    static let seeds: [(String, UInt64)] = [
        ("zero", 0),
        ("one", 1),
        ("forty-two", 42),
        ("int63-max", 0x7FFF_FFFF_FFFF_FFFF),
        ("int63-min", 0x8000_0000_0000_0000),
        ("uint64-max", 0xFFFF_FFFF_FFFF_FFFF),
        ("tetris-a", 20_261_020),
        ("tetris-b", 7_777),
        ("garbage-salt", 0x6A09_E667_F3BC_C909),
        ("tetris-a-garbage", 20_261_020 ^ 0x6A09_E667_F3BC_C909),
        ("pattern", 0x0123_4567_89AB_CDEF),
        ("golden-gamma", 0x9E37_79B9_7F4A_7C15),
    ]
    static let nextCount = 64
    static let unitCount = 16
    static let uniformRanges: [(Double, Double)] = [(0.45, 1.0), (-3.5, 2.25)]
    static let uniformCount = 4

    @Test("rng/splitmix64 — 시드 12개 × next 64 · unit 16 · uniform 2×4 (MiniGameRandom = GomokuAISplitMix64)")
    func rngSplitMix64() {
        var cases: [GoldenJSON] = []
        var split: [String] = []
        for (id, seed) in Self.seeds {
            var game = MiniGameRandom(seed: seed)
            var gomoku = GomokuAISplitMix64(seed: seed)
            var next: [GoldenJSON] = []
            for index in 0..<Self.nextCount {
                let value = game.next()
                let other = gomoku.next()
                if value != other {
                    split.append("시드 \(id) 의 \(index) 번째: MiniGameRandom \(GoldenBits.hex64(value)) ≠ GomokuAISplitMix64 \(GoldenBits.hex64(other))")
                }
                next.append(.hex64(value))
            }
            var unitRng = MiniGameRandom(seed: seed)
            let units = (0..<Self.unitCount).map { _ in GoldenJSON.bits(unitRng.unit()) }
            var uniforms: [GoldenJSON] = []
            for (lo, hi) in Self.uniformRanges {
                var rng = MiniGameRandom(seed: seed)
                uniforms.append([
                    "loBits": .bits(lo),
                    "hiBits": .bits(hi),
                    "valuesBits": .array((0..<Self.uniformCount).map { _ in .bits(rng.uniform(lo, hi)) }),
                ])
            }
            cases.append([
                "id": .string(id),
                "seed": .hex64(seed),
                "next": .array(next),
                "unitBits": .array(units),
                "uniform": .array(uniforms),
            ])
        }
        #expect(split.isEmpty, "Swift 의 SplitMix64 두 벌이 갈렸다(\(split.count)곳) — Kotlin 은 한 벌이다. 첫 자리: \(split.first ?? "")")
        goldenEmit(GoldenFile(
            golden: "rng/splitmix64",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/MiniGameEngine.swift", "Sources/CheckCore/GomokuAIEngine.swift"],
            spec: [
                "algorithm": "SplitMix64: state = state + 0x9e3779b97f4a7c15; z = state; z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9; z = (z ^ (z >> 27)) * 0x94d049bb133111eb; next = z ^ (z >> 31). 64비트 감김 산술, 부호 없는 오른쪽 밀기(Kotlin ULong 또는 Long + ushr)",
                "unit": "Double(next() >> 11) / 2^53 — [0, 1), 나눗셈 한 번(곱셈 1/2^53 으로 바꾸지 않는다 — 비트는 같지만 원본 식 그대로)",
                "uniform": "lo + (hi - lo) * unit()",
                "streams": "next · unitBits · uniform 의 각 범위는 같은 시드로 새로 만든 생성기에서 처음부터 뽑는다",
                "swift": "MiniGameRandom(MiniGameEngine.swift) 과 GomokuAISplitMix64(GomokuAIEngine.swift) 는 같은 열을 낸다 — 이 내보내기가 시드마다 64개를 단언한다",
            ],
            cases: cases
        ))
    }

    // MARK: - 골든 목록 정적 잠금(고아 금지). 스크립트 없이 도는 전체 스위트에서도 돈다.

    /// `//` 줄 주석을 걷어낸다(글자 리터럴 안의 `//` 는 남긴다). 설명 주석에 골든 이름이 남아 있어도 생성기로 치지 않게.
    static func strippingLineComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var inString = false
            var previous: Character = " "
            var index = line.startIndex
            while index < line.endIndex {
                let ch = line[index]
                if ch == "\"" && previous != "\\" { inString.toggle() }
                if !inString, ch == "/", previous == "/" {
                    return line[..<line.index(before: index)]
                }
                previous = ch
                index = line.index(after: index)
            }
            return line
        }.joined(separator: "\n")
    }

    static func jsonFiles(under relative: String) -> Set<String> {
        let base = GoldenRepo.url(relative)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var found = Set<String>()
        for case let url as URL in walker where url.pathExtension == "json" {
            let rel = String(url.standardizedFileURL.path.dropFirst(GoldenRepo.root.standardizedFileURL.path.count + 1))
            found.insert(rel)
        }
        return found
    }

    /// 목록 문제(빈 배열이면 통과). 시험과 대조 시험이 같은 판정을 쓴다.
    static func manifestProblems(manifest: GoldenJSON, contractFiles: Set<String>, probeFiles: Set<String>,
                                 readSource: (String) -> String?) -> [String] {
        var problems: [String] = []
        func entries(_ key: String) -> [GoldenJSON] {
            if case .array(let items)? = manifest[key] { return items }
            problems.append("_manifest.json 에 \(key) 배열이 없다")
            return []
        }
        func check(_ items: [GoldenJSON], files: Set<String>, label: String) {
            var listed = Set<String>()
            for item in items {
                guard case .string(let golden)? = item["golden"], case .string(let path)? = item["path"],
                      case .string(let generator)? = item["generator"] else {
                    problems.append("\(label): 칸이 빠진 항목 \(item)")
                    continue
                }
                listed.insert(path)
                guard let source = readSource(generator) else {
                    problems.append("\(label) \(golden): 생성 시험 \(generator) 가 없다")
                    continue
                }
                if !strippingLineComments(source).contains("\"\(golden)\"") {
                    problems.append("\(label) \(golden): 생성 시험 \(generator) 의 코드(주석 밖)에 이름 \"\(golden)\" 이 없다")
                }
            }
            for orphan in files.subtracting(listed).sorted() { problems.append("\(label): 목록에 없는 파일(고아) \(orphan)") }
            for missing in listed.subtracting(files).sorted() { problems.append("\(label): 목록에만 있는 파일 \(missing)") }
        }
        check(entries("goldens"), files: contractFiles, label: "계약")
        check(entries("probes"), files: probeFiles, label: "실험 표")
        return problems
    }

    static func loadManifest() throws -> (GoldenJSON, Data) {
        let data = try Data(contentsOf: GoldenRepo.url("contract/golden/_manifest.json"))
        return (try GoldenJSON.parse(data), data)
    }

    static func currentFiles() -> (contract: Set<String>, probes: Set<String>) {
        let contract = jsonFiles(under: GoldenRoot.contract.directory)
            .filter { !$0.hasSuffix("/_manifest.json") && !$0.hasSuffix("/_digests.json") }
        return (contract, jsonFiles(under: GoldenRoot.probe.directory))
    }

    static func readRepoText(_ relative: String) -> String? {
        try? String(contentsOf: GoldenRepo.url(relative), encoding: .utf8)
    }

    @Test("_manifest.json = 디스크의 골든 파일(계약 · 실험 표) — 고아 0 · 목록만 0 · 생성 시험 코드에 이름이 있다 · 정규 바이트")
    func manifestMatchesFiles() throws {
        let (manifest, bytes) = try Self.loadManifest()
        let files = Self.currentFiles()
        #expect(files.contract.contains("contract/golden/rng/splitmix64.json"), "견본 골든이 디스크에 없다")
        let problems = Self.manifestProblems(manifest: manifest, contractFiles: files.contract, probeFiles: files.probes,
                                             readSource: Self.readRepoText)
        #expect(problems == [], "\(problems.joined(separator: "\n"))")
        // 파이썬(golden-digest.py)이 쓴 목록이 Swift 정규 작성기와 바이트까지 같다 — 두 작성기가 한 형식이다.
        #expect(try manifest.canonicalData() == bytes, "_manifest.json 이 정규 형식(contract/README.md)과 바이트가 다르다")
    }

    /// 대조(기준선이 다른 입력): 고아 파일 하나 · 주석에만 남은 이름 · 목록만 있는 항목은 각각 빨갛다.
    @Test("대조: 고아 파일 · 주석에만 남은 생성기 이름 · 목록에만 있는 파일을 심으면 각각 문제로 잡힌다")
    func manifestProblemsCatchPlantedDefects() throws {
        let (manifest, _) = try Self.loadManifest()
        let files = Self.currentFiles()
        let orphan = Self.manifestProblems(manifest: manifest,
                                           contractFiles: files.contract.union(["contract/golden/rng/orphan.json"]),
                                           probeFiles: files.probes, readSource: Self.readRepoText)
        #expect(orphan.contains { $0.contains("고아") && $0.contains("orphan.json") })
        // 이름은 조각으로 만든다 — 이 파일(생성 시험) 코드에 이름 글자가 통째로 한 번 더 있으면 대조가 무력해진다.
        let name = ["rng", "splitmix64"].joined(separator: "/")
        let commentOnly = Self.manifestProblems(manifest: manifest, contractFiles: files.contract, probeFiles: files.probes) { path in
            guard let text = Self.readRepoText(path) else { return nil }
            return text.replacingOccurrences(of: "golden: \"\(name)\"", with: "// golden: \"\(name)\"")
        }
        #expect(commentOnly.contains { $0.contains(name) && $0.contains("주석 밖") })
        let missing = Self.manifestProblems(manifest: manifest,
                                            contractFiles: files.contract.subtracting(["contract/golden/rng/splitmix64.json"]),
                                            probeFiles: files.probes, readSource: Self.readRepoText)
        #expect(missing.contains { $0.contains("목록에만") })
    }
}
