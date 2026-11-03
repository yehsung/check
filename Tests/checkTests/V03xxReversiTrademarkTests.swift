import Foundation
import Testing

// 아잉 뒤집기(reversi) — **상표 글자 0** (SPEC §1 · §6.3 T `V03xxReversiTrademarkTests`, v1.1 CCT I9 · D24).
// 출시 버전이 정해지면 `git mv` + `@Suite` 이름을 함께 바꾼다(SPEC §1).
//
// 없으면 어떤 결함이 초록으로 통과하는가: 게임 이름으로 쓰면 안 되는 상표 글자(한글 두 표기 + 로마자, 대소문자 무관)가 화면 문구 ·
// 말풍선 · 도움말 · 주석 · 시험 · 마이그레이션 · 체인지로그 어디에 새어 들어가도 아무 시험도 안 본다. 리버시 파일만 훑으면 배선 갈래가
// 고치는 공용 파일(메뉴 · 배너 · 사이드바 · 미션)과 남의 시험 주석이 빠지고, 소문자만 보면 대문자 표기를 놓친다 — 그래서 저장소 전역을
// 대소문자 무시로 훑는다(검토 시점 0건이라 비용이 없다). 파일 · 폴더 **이름**도 본다.
//
// 범위: `Sources/**` · `Tests/**` · `supabase/migrations/**`(워크트리면 심링크 너머 메인 체인) · `CHANGELOG.md`, 그리고
// `REVERSI_MIGRATION_SQL` 이 가리키는 리버시 초안(승인 전엔 supabase/migrations 밖에 있다 — 들어가는 순간 같은 그물에 걸려야 한다).
// 허용은 `Tests/checkTests/Fixtures/reversi/cases.json` 안 **정확히 1건**(규칙 근거의 출처 주소 — research/cases.json 바이트 복사)뿐이다.
// 패턴은 글자 조각을 이어 만든다 — 이 파일 자신도 0건이다(허용 목록에 이 파일을 두지 않는다).

/// 금지 글자(소문자로 접어 비교한다). 조각을 잇는 까닭: 이 파일도 훑는 범위 안에 있다.
private let rtmNeedles: [String] = ["오" + "델로", "오" + "셀로", "oth" + "ello"]
private let rtmAllowedFile = "Tests/checkTests/Fixtures/reversi/cases.json"
private let rtmAllowedCount = 1

private struct RTMError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 저장소 꼭대기(Package.swift 가 있는 조상).
private func rtmRepoRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) { return directory }
        directory.deleteLastPathComponent()
    }
    throw RTMError("저장소 꼭대기(Package.swift)를 못 찾았다")
}

/// 한 줄에서 금지 글자가 몇 번 나오는가(대소문자 무시).
private func rtmHits(in text: String) -> Int {
    let folded = text.lowercased()
    return rtmNeedles.reduce(0) { $0 + folded.components(separatedBy: $1).count - 1 }
}

/// 폴더 아래 모든 일반 파일(심링크 폴더는 실제 경로로 풀어서 훑는다). 상대 경로 표기는 `label` 머리 + 폴더 안 경로.
private func rtmFiles(under directory: URL, label: String) -> [(label: String, url: URL)] {
    let resolved = directory.resolvingSymlinksInPath()
    guard let enumerator = FileManager.default.enumerator(
        at: resolved, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return [] }
    var out: [(String, URL)] = []
    let base = resolved.path.hasSuffix("/") ? resolved.path : resolved.path + "/"
    for case let url as URL in enumerator {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        let path = url.resolvingSymlinksInPath().path
        let relative = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
        out.append(("\(label)/\(relative)", url))
    }
    return out
}

@Suite("아잉 뒤집기 상표 글자 — 저장소 전역 0(허용 1)")
struct V03xxReversiTrademarkTests {

    // 없으면: 상표 글자가 저장소 어디에 새어도(대문자 표기 포함) 초록이다. 허용 1건이 늘거나(출처 주소 말고 다른 글) 사라져도
    // (복사본이 바뀌었다) 모른다.
    @Test
    func 상표_글자는_허용_한_건_말고_없다() throws {
        let root = try rtmRepoRoot()
        var targets: [(label: String, url: URL)] = []
        for folder in ["Sources", "Tests"] {
            targets += rtmFiles(under: root.appendingPathComponent(folder, isDirectory: true), label: folder)
        }
        let migrations = root.appendingPathComponent("supabase/migrations", isDirectory: true)
        let hasMigrations = FileManager.default.fileExists(atPath: migrations.path)
        if hasMigrations {
            targets += rtmFiles(under: migrations, label: "supabase/migrations")
        }
        targets.append(("CHANGELOG.md", root.appendingPathComponent("CHANGELOG.md")))
        if let draft = ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"], !draft.isEmpty,
           FileManager.default.fileExists(atPath: draft) {
            targets.append(("REVERSI_MIGRATION_SQL(\(URL(fileURLWithPath: draft).lastPathComponent))", URL(fileURLWithPath: draft)))
        }

        var hits: [String] = []
        var allowedHits = 0
        var textFiles = 0
        var scannedNames = 0
        for target in targets {
            // 이름(파일 · 폴더 경로)도 본다.
            scannedNames += 1
            if rtmHits(in: target.label) > 0 { hits.append("\(target.label) (경로 이름)") }
            guard let data = try? Data(contentsOf: target.url),
                  let text = String(data: data, encoding: .utf8) else { continue }   // 그림 · 바이너리
            textFiles += 1
            guard rtmHits(in: text) > 0 else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let count = rtmHits(in: String(line))
                guard count > 0 else { continue }
                if target.label == rtmAllowedFile {
                    allowedHits += count
                } else {
                    hits.append("\(target.label):\(number + 1)")
                }
            }
        }

        print("[상표] 훑은 파일 \(scannedNames)개(글자 파일 \(textFiles)) · supabase/migrations \(hasMigrations ? "포함" : "없음") · 허용 \(allowedHits)건")
        #expect(textFiles > 1_000, "글자 파일을 \(textFiles)개만 읽었다 — 훑는 범위가 비었다(경로가 틀렸다)")
        #expect(targets.contains { $0.label == rtmAllowedFile }, "허용 파일 \(rtmAllowedFile) 이 없다 — 규칙 코퍼스 복사본이 사라졌다")
        #expect(hits.isEmpty, "상표 글자가 있다(대소문자 무시) — 이름 · 문구 · 주석 · 시험 어디에도 쓰지 않는다: \(hits)")
        #expect(allowedHits == rtmAllowedCount,
                "\(rtmAllowedFile) 안 상표 글자가 \(allowedHits)건이다(허용은 출처 주소 정확히 \(rtmAllowedCount)건)")
    }
}
