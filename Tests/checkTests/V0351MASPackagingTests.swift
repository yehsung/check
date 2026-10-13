import Foundation
import Testing

// MARK: - 맥 앱스토어 판 패키징 계약 (v0.3.51 F7 — scripts/package-mas.sh · packaging/mas.entitlements)
//
// 이 스위트가 지키는 것은 넷이다.
//  ① **엔타이틀먼트는 정해진 집합 그대로다.** 키 하나를 더하면 심사 설명·프로파일 허락이 같이 바뀌어야 하고, 하나를 빼면
//     샌드박스 안에서 그 기능이 소리 없이 0 이 된다(2026-10-14 프로브 실측: 예외 밖 경로는 EPERM). 그래서 집합을 통째로 잰다.
//  ② **예외 경로가 스캐너가 읽는 경로를 덮는다.** 맥 소스 코드에서 홈 아래 경로처럼 생긴 리터럴(`.x…` · `Library/…` 로 시작하는
//     `appendingPathComponent("…")` · `appending(path:/component:)` 인자와 `let … = "…"` 상수)을 **전부 뽑아** 예외가 덮는지 잰다.
//     그래서 스캐너가 그 꼴로 새 홈 경로(예: `.config/…`)를 읽기 시작하면 빨개진다. 다른 꼴(문자열 이어 붙이기 · `"~/…"` 펼치기)로
//     만든 경로는 못 잡는다 — 그 꼴은 샌드박스에서 컨테이너 홈을 가리키므로 예외가 필요 없기도 하다.
//  ③ **금지 문자열 게이트가 헛돌지 않는다.** 스크립트는 '자가 업데이트·타사 자격증명 코드가 바이너리에 0건'으로 CHECK_MAS 갈래가
//     컴파일됐음을 증명한다. 그 문자열이 Developer ID 소스에 **있어야** 게이트가 뜻을 가진다(기준선이 같으면 영원히 초록이다).
//     그리고 16바이트 이상이어야 한다 — Swift 는 15바이트 이하 문자열을 코드에 인라인해 바이트 검색으로 원리상 못 찾는다.
//     게이트 블록 자체도 bash 로 **실제로 돌려** 제출본(엄격)에서는 문자열 하나만 있어도 멈추고(경고로 낮아지지 않는다),
//     리허설에서만 경고로 지나가는지 잰다.
//  ④ **스크립트는 올리지 않고, --deep 으로 서명하지 않고, 암호를 argv 에 싣지 않으며, Developer ID 판을 건드리지 않는다.**
//     글자 단언에 더해 bash 3.2(맥 기본 /bin/bash)가 실제로 파싱·실행하는지까지 본다 — 문자열 단언은 깨진 스크립트도 통과시킨다.
//     엄격/리허설을 가르는 `#if … CHECK_MAS` 탐지 블록도 실제로 돌려, `#if !CHECK_MAS` 줄은 잡고 주석 속 언급은 안 잡는지 잰다.
//
// ⚠️ 소스 계약은 전부 **주석을 걷어낸 뒤** 잰다(안 그러면 설명을 지워야만 초록이 된다).

private let masRoot = CheckCoreSourceLayout.repoRoot

private func masText(_ relative: String) throws -> String {
    try String(contentsOf: masRoot.appendingPathComponent(relative), encoding: .utf8)
}

/// 셸 스크립트의 코드 줄(줄 전체가 주석인 줄을 뺀다). 맨 앞 shebang 도 주석으로 빠진다.
private func masShellCode(_ relative: String) throws -> [String] {
    try masText(relative)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다. 문자열 리터럴 안의 `//` 는 남긴다(RealtimeLinkTests 와 같은 규칙).
private func masStrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let chars = Array(source)
    var index = 0
    while index < chars.count {
        let c = chars[index]
        let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

/// 맥 앱이 컴파일하는 모든 Swift 소스(맥 실행 타깃 + 코어)를 주석을 걷어 이어 붙인 것.
private func masMacCodeCorpus() throws -> String {
    var out = ""
    for dir in ["Sources/check", "Sources/CheckCore"] {
        let root = masRoot.appendingPathComponent(dir, isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
        for case let url as URL in walker where url.pathExtension == "swift" {
            out += masStrippingComments(try String(contentsOf: url, encoding: .utf8)) + "\n"
        }
    }
    return out
}

/// 스크립트의 `FORBIDDEN_STRINGS=( … )` 배열 원소(따옴표 안 글자).
private func masForbiddenStrings() throws -> [String] {
    let lines = try masShellCode("scripts/package-mas.sh")
    guard let start = lines.firstIndex(where: { $0.hasPrefix("FORBIDDEN_STRINGS=(") }) else { return [] }
    var out: [String] = []
    for line in lines[(start + 1)...] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(")") { break }
        guard trimmed.hasPrefix("\""), let close = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
        out.append(String(trimmed[trimmed.index(after: trimmed.startIndex)..<close]))
    }
    return out
}

private struct MASScriptRun {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// 스크립트를 맥 기본 bash(3.2)로 돌린다. 인자 검사에서 멈추는 경로만 부른다 — 빌드·서명·네트워크에 닿기 전이다.
private func masRunScript(_ arguments: [String]) throws -> MASScriptRun {
    try masRunBash(masRoot.appendingPathComponent("scripts/package-mas.sh"), arguments)
}

/// 아무 bash 파일을 맥 기본 bash(3.2)로 돌린다. `environment` 의 nil 값은 그 이름을 환경에서 **지운다**.
private func masRunBash(_ script: URL, _ arguments: [String], environment: [String: String?] = [:]) throws -> MASScriptRun {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = [script.path] + arguments
    var env = ProcessInfo.processInfo.environment
    for (key, value) in environment { env[key] = value }
    proc.environment = env
    proc.standardInput = FileHandle.nullDevice
    let out = Pipe()
    let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    try proc.run()
    let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    proc.waitUntilExit()
    return MASScriptRun(status: proc.terminationStatus, stdout: stdout, stderr: stderr)
}

/// 스크립트 원문의 줄(주석 포함 — 블록을 잘라 그대로 bash 에 먹인다).
private func masScriptRawLines() throws -> [String] {
    try masText("scripts/package-mas.sh").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

/// 맨 앞이 `prefix` 인 첫 줄부터 그 뒤 **맨 앞에 홀로 선** `terminator` 줄까지(들여쓴 안쪽 `fi` 는 블록 끝이 아니다).
private func masScriptBlock(from prefix: String, through terminator: String) throws -> String {
    let lines = try masScriptRawLines()
    let start = try #require(lines.firstIndex { $0.hasPrefix(prefix) }, "스크립트에서 [\(prefix)] 로 시작하는 줄을 찾지 못했다")
    let end = try #require(lines[start...].firstIndex { $0 == terminator }, "[\(prefix)] 블록의 끝 [\(terminator)] 을 찾지 못했다")
    return lines[start...end].joined(separator: "\n")
}

/// 게이트 블록을 따로 돌리는 데 필요한 스크립트의 앞부분: `set -euo pipefail` · log/warn/die · 금지 문자열 배열 — 전부 원문 그대로.
private func masGatePrelude() throws -> String {
    let lines = try masScriptRawLines()
    var out = [try #require(lines.first { $0.hasPrefix("set -euo pipefail") }, "set -euo pipefail 줄이 없다")]
    for name in ["log", "warn", "die"] {
        out.append(try #require(lines.first { $0.hasPrefix("\(name)() {") }, "\(name)() 정의가 없다"))
    }
    out.append(try masScriptBlock(from: "FORBIDDEN_STRINGS=(", through: ")"))
    return out.joined(separator: "\n")
}

/// 테스트마다 따로 쓰는 임시 폴더(끝나면 지운다 — 저장소·공유 폴더에 흘리지 않는다).
private func masTempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("v0351-mas-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// 코드(주석을 걷은 것)에서 홈 아래 경로처럼 생긴 리터럴 — 점 디렉터리(`.x…`) 또는 `Library/…` 로 시작하는 것 — 을 뽑는다.
/// 잡는 꼴: `appendingPathComponent("…")` · `appending(path: "…")` · `appending(component: "…")` 인자, `let 이름 = "…"` 상수.
/// 확장자 리터럴(`".zst"`)처럼 경로가 아닌 점 문자열은 이 꼴에 안 걸린다(`path + ".zst"` 로 쓰인다).
private func masHomeRelativeLiterals(in code: String) throws -> Set<String> {
    let literal = #""((?:\.[A-Za-z]|Library/)[^"\\]*)""#
    let patterns = [
        #"appendingPathComponent\(\s*"# + literal,
        #"appending\(\s*(?:path|component):\s*"# + literal,
        #"\blet\s+\w+\s*(?::\s*String\s*)?=\s*"# + literal,
    ]
    var found: Set<String> = []
    let range = NSRange(code.startIndex..., in: code)
    for pattern in patterns {
        let regex = try NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: code, range: range) {
            guard let r = Range(match.range(at: 1), in: code) else { continue }
            found.insert(String(code[r]))
        }
    }
    return found
}

@Suite("맥 앱스토어 판 패키징 — 엔타이틀먼트 · 금지 문자열 게이트 · 스크립트 계약")
struct V0351MASPackagingTests {

    // ① 엔타이틀먼트 집합
    @Test func masEntitlementsAreExactlyTheSandboxSet() throws {
        let data = try Data(contentsOf: masRoot.appendingPathComponent("packaging/mas.entitlements"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let expectedKeys: Set<String> = [
            "com.apple.security.app-sandbox",
            "com.apple.security.network.client",
            "com.apple.security.files.user-selected.read-only",
            "com.apple.security.temporary-exception.files.home-relative-path.read-only",
            "com.apple.application-identifier",
            "com.apple.developer.team-identifier",
        ]
        #expect(Set(plist.keys) == expectedKeys,
                "엔타이틀먼트 키가 바뀌었다 — 더한 키: \(Set(plist.keys).subtracting(expectedKeys).sorted()) · 빠진 키: \(expectedKeys.subtracting(plist.keys).sorted())")
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(plist["com.apple.security.network.client"] as? Bool == true)
        #expect(plist["com.apple.security.files.user-selected.read-only"] as? Bool == true, "아바타 사진 고르기(NSOpenPanel)가 막힌다")
        #expect(plist["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String]
                == ["/.claude/", "/.codex/", "/.gemini/", "/Library/Application Support/orca/"])
        #expect(plist["com.apple.application-identifier"] as? String == "MQ2KQK37WD.com.yehsung.aingcheck")
        #expect(plist["com.apple.developer.team-identifier"] as? String == "MQ2KQK37WD")
        // 배포 서명에 디버거 붙이기 권한이 섞이면 업로드가 거절된다. 위 집합 비교가 잡지만 이유를 따로 적어 둔다.
        #expect(plist["com.apple.security.get-task-allow"] == nil)
        // 쓰기 예외는 없다 — 남의 앱 폴더에 쓰는 앱이 된다.
        #expect(!plist.keys.contains { $0.contains("read-write") })
    }

    // ② 예외 경로 ↔ 스캐너 경로
    @Test func masExceptionsCoverEveryHomePathTheScannersRead() throws {
        let data = try Data(contentsOf: masRoot.appendingPathComponent("packaging/mas.entitlements"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let exceptions = try #require(plist["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String])
        func covered(_ path: String) -> Bool {
            exceptions.contains { ex in
                let prefix = String(ex.dropFirst())     // "/.claude/" → ".claude/"
                return (path + "/").hasPrefix(prefix)
            }
        }
        // 목록은 손으로 적지 않고 **코드에서 뽑는다** — 스캐너가 `.config/…` 같은 새 홈 경로를 읽기 시작하면 여기서 빨개진다.
        let derived = try masHomeRelativeLiterals(in: try masMacCodeCorpus())
        // 실행 파일 탐색 경로(`…/bin/…` · nvm 노드 설치 폴더 — codex app-server · agy 를 찾는 곳)는 읽기 대상이 아니다.
        // 샌드박스 앱은 남의 바이너리를 실행하지 못하고, 그 코드는 맥 앱스토어 판에서 컴파일되지 않는다
        // (게이트 ② 의 "account/usage/read" · "/opt/homebrew/bin/agy" 가 바이너리에 0건이어야 pkg 가 나온다).
        func isExecutableLookup(_ path: String) -> Bool {
            path.split(separator: "/").contains("bin") || path.hasPrefix(".nvm/")
        }
        let read = derived.filter { !isExecutableLookup($0) }
        for path in read.sorted() {
            #expect(covered(path), "코드가 ~/\(path) 를 읽는데 덮는 읽기 전용 예외가 없다 — 샌드박스에서 소리 없이 0 이 된다. packaging/mas.entitlements 와 심사 설명을 같이 고친다")
        }
        // 뽑기가 헛돌지 않는다: 지금 스캐너가 읽는 다섯 경로가 뽑힌 집합에 있어야 한다(코드 모양이 바뀌어 뽑기가 0 이 되면 위 루프는
        // 아무것도 안 재고 초록이 된다). 이 표가 틀리면 뽑기 정규식을 새 코드 모양에 맞춘다.
        for path in [
            ".claude/projects",                        // Claude Code 로그
            ".claude/transcripts",
            ".codex",                                  // Codex rollout · auth.json(리밋)
            ".gemini/antigravity-cli/conversations",   // 안티그래비티 sqlite
            "Library/Application Support/orca",        // Orca 런타임 미러·계정별 Codex 홈
        ] {
            #expect(read.contains(path), "\"\(path)\" 를 코드에서 뽑지 못했다(뽑은 것: \(read.sorted())) — 뽑기 정규식이 지금 코드 모양을 못 따라간다")
        }
        // 뽑기 자체가 새 루트를 잡는지(이 테스트가 홀로 지키는 약속) — 합성 코드로 잰다.
        let synthetic = """
            let a = homeDirectory.appendingPathComponent(".config/newtool", isDirectory: true)
            let b = home.appending(path: "Library/Application Support/NewTool")
            static let logsSubpath = ".newtool/logs"
            let ext = path + ".zst"
            let c = home.appendingPathComponent(".local/bin/newtool")
            """
        let syntheticFound = try masHomeRelativeLiterals(in: synthetic)
        #expect(syntheticFound == [".config/newtool", "Library/Application Support/NewTool", ".newtool/logs", ".local/bin/newtool"])
        #expect(Set(syntheticFound.filter { !isExecutableLookup($0) && !covered($0) }) == [".config/newtool", "Library/Application Support/NewTool", ".newtool/logs"],
                "덮이지 않은 새 루트를 '덮였다'로 본다")
    }

    // ③ 금지 문자열 게이트가 뜻을 가진다
    @Test func masForbiddenStringsAreLongAndPresentInDeveloperIDSources() throws {
        let forbidden = try masForbiddenStrings()
        #expect(forbidden.count >= 6, "금지 문자열 목록을 읽지 못했다(\(forbidden.count)개)")
        let corpus = try masMacCodeCorpus()
        for s in forbidden {
            #expect(s.utf8.count >= 16, "[\(s)] 는 \(s.utf8.count)바이트 — 15바이트 이하는 코드에 인라인돼 바이트 검색으로 못 찾는다")
            #expect(corpus.contains(s), "[\(s)] 가 맥 소스 코드에 없다 — 게이트가 헛돈다(기준선이 같으면 영원히 초록). 목록을 지금 코드에 맞춘다")
        }
        // 네 갈래(brew · DMG · GitHub 감시 · 사용자 설치 실행 파일)가 다 덮여야 한다. Claude 리밋(시스템 `security` 로 키체인
        // 항목 읽기)은 2026-10-14 결정으로 앱스토어 판에 남으므로 이 목록에 없다 — `MacEdition.readsClaudeLimits` 참고.
        for needle in ["brew upgrade", "releases/latest/download", "api.github.com", "account/usage/read", "agy"] {
            #expect(forbidden.contains { $0.contains(needle) }, "금지 목록에서 [\(needle)] 갈래가 빠졌다")
        }
    }

    // ③ 게이트 ② 블록을 실제로 돌린다: 제출본(엄격)에서는 금지 문자열 **하나**만 있어도 멈추고, 리허설에서만 경고로 지나간다.
    //   글자 단언("die 가 있다")은 die → warn 변형을 못 잡는다 — 블록을 원문 그대로 잘라 가짜 바이너리에 건다.
    @Test func masForbiddenStringGateDiesInStrictModeAndOnlyWarnsInRehearsal() throws {
        let forbidden = try masForbiddenStrings()
        #expect(forbidden.count >= 6, "금지 문자열 목록을 읽지 못했다(\(forbidden.count)개)")
        let dir = try masTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let harness = dir.appendingPathComponent("gate2.sh")
        let gate = try masScriptBlock(from: "FOUND=()", through: "fi")
        #expect(gate.contains("\"${FORBIDDEN_STRINGS[@]}\"") && gate.contains("\"$BIN\""), "게이트 ② 블록을 엉뚱한 곳에서 잘랐다:\n\(gate)")
        try ([try masGatePrelude(), "BIN=\"$1\"", "REHEARSAL=\"$2\"", gate, "echo GATE2_PASSED"].joined(separator: "\n"))
            .write(to: harness, atomically: true, encoding: .utf8)

        // 바이너리 흉내: Mach-O 머리 바이트·NUL·0xFF 사이에 문자열 — grep 이 텍스트가 아니라 바이너리로 보는 파일이다.
        func fakeBinary(_ name: String, containing middle: String) throws -> URL {
            var bytes = Data([0xCF, 0xFA, 0xED, 0xFE, 0x00, 0x00, 0x01, 0x07, 0x00])
            bytes.append(Data(middle.utf8))
            bytes.append(Data([0x00, 0xFF, 0x00, 0x42]))
            let url = dir.appendingPathComponent(name)
            try bytes.write(to: url)
            return url
        }

        // 깨끗한 바이너리(비슷하지만 다른 글자만): 엄격에서도 통과 — 빈 FOUND 배열이 bash 3.2 + set -u 에서 죽지 않는지도 여기서 잰다.
        let clean = try fakeBinary("clean", containing: "brew upgrade --cas\u{0}releases/latest\u{0}Claude Code-credential")
        let cleanRun = try masRunBash(harness, [clean.path, "0"])
        #expect(cleanRun.status == 0 && cleanRun.stdout.contains("GATE2_PASSED"), "깨끗한 바이너리를 막았다: \(cleanRun.stderr)")
        #expect(cleanRun.stderr.contains("0건"), "깨끗한 바이너리에서 '0건' 로그가 없다: \(cleanRun.stderr)")

        for (index, s) in forbidden.enumerated() {
            let bin = try fakeBinary("dirty-\(index)", containing: s)
            let strict = try masRunBash(harness, [bin.path, "0"])
            #expect(strict.status == 1, "엄격 모드가 [\(s)] 를 품은 바이너리를 통과시켰다(status \(strict.status)) — 제출본에서 게이트 ② 가 경고로 낮아졌다")
            #expect(!strict.stdout.contains("GATE2_PASSED"), "엄격 모드가 [\(s)] 뒤에도 다음 단계로 넘어갔다")
            #expect(strict.stderr.contains("오류:") && strict.stderr.contains(s), "엄격 모드 멈춤 문구에 [\(s)] 가 없다: \(strict.stderr)")

            let rehearsal = try masRunBash(harness, [bin.path, "1"])
            #expect(rehearsal.status == 0 && rehearsal.stdout.contains("GATE2_PASSED"), "리허설이 [\(s)] 에서 멈췄다: \(rehearsal.stderr)")
            #expect(rehearsal.stderr.contains("경고:") && rehearsal.stderr.contains(s), "리허설 경고에 [\(s)] 가 없다: \(rehearsal.stderr)")
        }
    }

    // ④ 스크립트 계약
    @Test func masScriptBuildsSeparatelyWithTheFlag() throws {
        let code = try masShellCode("scripts/package-mas.sh").joined(separator: "\n")
        #expect(code.contains("-Xswiftc -DCHECK_MAS"), "MAS 플래그 없이 빌드한다")
        #expect(code.contains("SCRATCH=\"$ROOT/.build-mas\""), "Developer ID 빌드 캐시(.build/)와 섞인다")
        #expect(code.contains("--scratch-path \"$SCRATCH\""))
        #expect(code.contains("--show-bin-path"), "산출물 경로를 SwiftPM 에 묻지 않는다(Xcode 27 경로 함정)")
        #expect(code.contains("rm -f \"$BUILD_PRODUCTS/check\""), "빌드 전에 옛 산출물을 지우지 않는다 — 증분 빌드의 exit 0 은 '다시 만들었다'가 아니다")
        #expect(code.contains("-newer \"$BUILD_MARK\""), "산출물이 이번 빌드보다 새것인지 재지 않는다")
        #expect(try masText(".gitignore").contains("\n.build-mas/\n"), ".build-mas/ 가 gitignore 에 없다")
    }

    @Test func masScriptNeverUploadsNeverDeepSignsNeverLeaksThePassword() throws {
        let lines = try masShellCode("scripts/package-mas.sh")
        let code = lines.joined(separator: "\n")
        #expect(!code.contains("--upload-package") && !code.contains("--upload-app"), "스크립트가 업로드한다 — 업로드는 사람이 따로 한다")
        let signing = lines.filter { $0.contains("codesign") && $0.contains("--sign") }
        #expect(signing.count >= 2, "서명 줄을 찾지 못했다")
        for line in signing {
            #expect(!line.contains("--deep"), "배포 서명에 --deep 을 쓴다(애플 문서가 금한다): \(line)")
        }
        #expect(code.contains("--entitlements \"$ENTITLEMENTS\""))
        #expect(code.contains("cp \"$PROFILE\" \"$APP/Contents/embedded.provisionprofile\""))
        #expect(code.contains("productbuild --component \"$APP\" /Applications --sign \"$INSTALLER_IDENTITY\" --keychain \"$INSTALLER_KEYCHAIN\""))
        // 키체인 암호는 stdin 으로만 — argv 는 ps 에 보인다.
        #expect(code.contains("security unlock-keychain \"$INSTALLER_KEYCHAIN\" < \"$KEYCHAIN_PASSWORD_FILE\""))
        #expect(!code.contains("unlock-keychain -p"), "키체인 암호를 argv 로 넘긴다")
        // anon 키가 없으면 멈춘다(심사관이 로그인 못 하는 앱이 올라가는 길).
        #expect(code.contains("[[ -n \"${CHECK_SUPABASE_ANON_KEY:-}\" ]] || die"))
        #expect(code.contains("[[ \"$KEY_ROLE\" == \"anon\" ]] || die"), "service_role 키를 막지 않는다")
        // 리허설 손잡이는 MAS 갈래가 있는 소스에서 거부돼야 한다.
        #expect(code.contains("[[ -z \"${MAS_REHEARSAL:-}\" ]] || die"))
    }

    // 엄격/리허설 가르기를 실제로 돌린다. 탐지 정규식이 `#if !CHECK_MAS` 를 놓치면 MAS 갈래가 병합된 소스에서도 '갈래 없음'으로 보여
    // 제출본이 리허설 손잡이로만 나오고(게이트 ② 경고), 주석 속 언급까지 잡으면 갈래가 없는 소스를 엄격으로 오판한다.
    @Test func masBranchDetectionSplitsStrictFromRehearsal() throws {
        let dir = try masTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let harness = dir.appendingPathComponent("detect.sh")
        let detect = try masScriptBlock(from: "if grep -rqE ", through: "fi")
        #expect(detect.contains("\"$ROOT/Sources\""), "탐지 블록이 Sources 를 보지 않는다:\n\(detect)")
        try ([try masGatePrelude(), "ROOT=\"$1\"", "OUT_DIR=\"$ROOT/dist/mas\"", "APP_NAME=AingCheck", detect,
              "echo \"REHEARSAL=$REHEARSAL\"", "echo \"PKG=$PKG\""].joined(separator: "\n"))
            .write(to: harness, atomically: true, encoding: .utf8)

        func run(sourceLine: String, rehearsal: Bool) throws -> MASScriptRun {
            let root = dir.appendingPathComponent("root-\(UUID().uuidString)", isDirectory: true)
            let nested = root.appendingPathComponent("Sources/check/Nested", isDirectory: true)   // grep -r 이 하위 폴더까지 보는지
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try "import Foundation\n\(sourceLine)\nlet x = 1\n#endif\n"
                .write(to: nested.appendingPathComponent("File.swift"), atomically: true, encoding: .utf8)
            return try masRunBash(harness, [root.path], environment: ["MAS_REHEARSAL": rehearsal ? "1" : nil])
        }

        let branches = [
            "    #if !CHECK_MAS",
            "#if CHECK_MAS",
            "\t#if !CHECK_MAS",
            "#elseif CHECK_MAS",
            "#if os(macOS) && !CHECK_MAS",
        ]
        for line in branches {
            let strict = try run(sourceLine: line, rehearsal: false)
            #expect(strict.status == 0 && strict.stdout.contains("REHEARSAL=0") && strict.stdout.contains("/AingCheck.pkg"),
                    "[\(line)] 를 MAS 갈래로 못 알아봤다(status \(strict.status)): \(strict.stdout) \(strict.stderr)")
            let refused = try run(sourceLine: line, rehearsal: true)
            #expect(refused.status == 1 && refused.stderr.contains("MAS_REHEARSAL"),
                    "[\(line)] 갈래가 있는데 MAS_REHEARSAL=1 을 받아들였다 — 제출본에서 게이트 ② 를 끄는 손잡이가 생긴다")
            #expect(!refused.stdout.contains("PKG="))
        }

        let mentionsOnly = [
            "// #if CHECK_MAS",
            "/// `#if !CHECK_MAS` 로 가른다",
            "    /* #if !CHECK_MAS */",
            "let marker = \"#if CHECK_MAS\"",
            "#if DEBUG // CHECK_MAS 갈래는 나중에",
            "#if DEBUG",
        ]
        for line in mentionsOnly {
            let strict = try run(sourceLine: line, rehearsal: false)
            #expect(strict.status == 1 && strict.stderr.contains("CHECK_MAS"),
                    "[\(line)] 만 있는 소스를 MAS 갈래가 있다고 봤다(status \(strict.status)): \(strict.stdout)")
            let rehearsal = try run(sourceLine: line, rehearsal: true)
            #expect(rehearsal.status == 0 && rehearsal.stdout.contains("REHEARSAL=1") && rehearsal.stdout.contains("/AingCheck-rehearsal.pkg"),
                    "[\(line)] 소스의 리허설이 리허설 이름으로 나오지 않는다(status \(rehearsal.status)): \(rehearsal.stdout) \(rehearsal.stderr)")
        }
    }

    @Test func masDeveloperIDScriptsStayUnaware() throws {
        for script in ["scripts/build-local.sh", "scripts/package-notarized.sh", "scripts/package-dmg.sh", "scripts/release-brew.sh"] {
            let code = try masShellCode(script).joined(separator: "\n")
            #expect(!code.contains("CHECK_MAS"), "\(script) 가 MAS 플래그를 안다 — Developer ID 판은 기본 빌드여야 한다")
            #expect(!code.contains(".build-mas") && !code.contains("dist/mas"), "\(script) 가 MAS 산출물·캐시에 닿는다")
        }
    }

    @Test func masScriptParsesAndRejectsBadArgumentsUnderSystemBash() throws {
        let parse = Process()
        parse.executableURL = URL(fileURLWithPath: "/bin/bash")
        parse.arguments = ["-n", masRoot.appendingPathComponent("scripts/package-mas.sh").path]   // 파싱만 한다
        let err = Pipe()
        parse.standardError = err
        try parse.run()
        let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        parse.waitUntilExit()
        #expect(parse.terminationStatus == 0, "/bin/bash 가 스크립트를 파싱하지 못했다: \(message)")

        // 아래는 전부 인자 검사에서 멈춘다(.env.local 읽기 · 빌드 · 서명 · 네트워크 전).
        let help = try masRunScript(["--help"])
        #expect(help.status == 0 && help.stdout.contains("사용법"))
        for bad in [[], ["0.3.52"], ["0.3", "105"], ["0.3.52", "0"], ["0.3.52", "10x"], ["0.3.52", "105", "--upload"]] {
            let run = try masRunScript(bad)
            #expect(run.status == 1, "\(bad) 를 받아들였다(status \(run.status))")
            #expect(run.stderr.contains("오류:"), "\(bad): 오류 문구 없이 끝났다 — \(run.stderr)")
            #expect(run.stdout.isEmpty, "\(bad): stdout 에 무언가를 찍었다(마지막 줄 = pkg 경로 계약)")
        }
    }
}
