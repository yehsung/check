import Foundation
import Testing

// MARK: - 맥 앱스토어 판 패키징 계약 (v0.3.51 F7 — scripts/package-mas.sh · packaging/mas.entitlements)
//
// 이 스위트가 지키는 것은 넷이다.
//  ① **엔타이틀먼트는 정해진 집합 그대로다.** 키 하나를 더하면 심사 설명·프로파일 허락이 같이 바뀌어야 하고, 하나를 빼면
//     샌드박스 안에서 그 기능이 소리 없이 0 이 된다(2026-10-14 프로브 실측: 예외 밖 경로는 EPERM). 그래서 집합을 통째로 잰다.
//  ② **예외 경로가 스캐너가 읽는 경로를 덮는다.** 스캐너가 새 홈 경로를 읽기 시작하면 이 테스트가 빨개져 엔타이틀먼트를 다시 보게 한다.
//  ③ **금지 문자열 게이트가 헛돌지 않는다.** 스크립트는 '자가 업데이트·타사 자격증명 코드가 바이너리에 0건'으로 CHECK_MAS 갈래가
//     컴파일됐음을 증명한다. 그 문자열이 Developer ID 소스에 **있어야** 게이트가 뜻을 가진다(기준선이 같으면 영원히 초록이다).
//     그리고 16바이트 이상이어야 한다 — Swift 는 15바이트 이하 문자열을 코드에 인라인해 바이트 검색으로 원리상 못 찾는다.
//  ④ **스크립트는 올리지 않고, --deep 으로 서명하지 않고, 암호를 argv 에 싣지 않으며, Developer ID 판을 건드리지 않는다.**
//     글자 단언에 더해 bash 3.2(맥 기본 /bin/bash)가 실제로 파싱·실행하는지까지 본다 — 문자열 단언은 깨진 스크립트도 통과시킨다.
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
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = [masRoot.appendingPathComponent("scripts/package-mas.sh").path] + arguments
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
        let corpus = try masMacCodeCorpus()
        // 스캐너가 홈 아래에서 읽는 경로(코드 리터럴 그대로). 리터럴이 바뀌면 이 표와 엔타이틀먼트를 같이 고친다.
        let scannerPaths = [
            ".claude/projects",                        // Claude Code 로그
            ".claude/transcripts",
            ".codex",                                  // Codex rollout · auth.json(리밋)
            ".gemini/antigravity-cli/conversations",   // 안티그래비티 sqlite
            "Library/Application Support/orca",        // Orca 런타임 미러·계정별 Codex 홈
        ]
        for path in scannerPaths {
            #expect(corpus.contains("\"\(path)\""), "스캐너 코드에서 \"\(path)\" 리터럴이 사라졌다 — 이 표와 엔타이틀먼트를 다시 맞춘다")
            let covered = exceptions.contains { ex in
                let prefix = String(ex.dropFirst())     // "/.claude/" → ".claude/"
                return (path + "/").hasPrefix(prefix)
            }
            #expect(covered, "~/\(path) 를 덮는 읽기 전용 예외가 없다 — 샌드박스에서 소리 없이 0 이 된다")
        }
    }

    // ③ 금지 문자열 게이트가 뜻을 가진다
    @Test func masForbiddenStringsAreLongAndPresentInDeveloperIDSources() throws {
        let forbidden = try masForbiddenStrings()
        #expect(forbidden.count >= 7, "금지 문자열 목록을 읽지 못했다(\(forbidden.count)개)")
        let corpus = try masMacCodeCorpus()
        for s in forbidden {
            #expect(s.utf8.count >= 16, "[\(s)] 는 \(s.utf8.count)바이트 — 15바이트 이하는 코드에 인라인돼 바이트 검색으로 못 찾는다")
            #expect(corpus.contains(s), "[\(s)] 가 맥 소스 코드에 없다 — 게이트가 헛돈다(기준선이 같으면 영원히 초록). 목록을 지금 코드에 맞춘다")
        }
        // 다섯 갈래(brew · DMG · GitHub 감시 · 타사 자격증명 · 외부 실행)가 다 덮여야 한다.
        for needle in ["brew upgrade", "releases/latest/download", "api.github.com", "Claude Code-credentials", "account/usage/read", "agy"] {
            #expect(forbidden.contains { $0.contains(needle) }, "금지 목록에서 [\(needle)] 갈래가 빠졌다")
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
