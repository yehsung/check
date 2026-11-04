import Foundation
import Testing

// 아잉 마작(mahjong) — **상표 글자 0** (MJ/SPEC.md §1 상표 시험 · §6.3 T `V03xxMahjongTrademarkTests`).
// 출시 버전이 정해지면 `git mv` + `@Suite` 이름을 함께 바꾼다(SPEC §1).
//
// 없으면 어떤 결함이 초록으로 통과하는가: 다른 마작 서비스 이름(한글·한자·가나·로마자 표기, 대소문자 무관)이 화면 문구 · 말풍선 ·
// 도움말 · 주석 · 시험 · 마이그레이션 · 체인지로그 · 두 서버 초안 어디에 새어 들어가도 아무 시험도 안 본다. 저장소 전역을 대소문자
// 무시로 훑고 파일 · 폴더 **이름**도 본다.
//
// 범위: `Sources/**` · `Tests/**` · `supabase/migrations/**`(워크트리면 심링크 너머 메인 체인) · `CHANGELOG.md`, 그리고
// `MAHJONG_RULES_SQL` · `MAHJONG_TABLE_SQL` 이 가리키는 두 초안(승인 전엔 supabase/migrations 밖에 있다).
// 허용은 둘뿐이다: `Fixtures/mahjong/cases.json`(규칙 코퍼스 바이트 복사 — 역 id·사례 id·근거 칸 **11건**) ·
// `Fixtures/mahjong/corpus_alias.json`(별칭 표 — 그 글자를 저장소 글자로 바꾸는 표 자체라 **1건**, R2 보고 2번).
// 패턴은 글자 조각을 이어 만든다 — 이 파일 자신도 0건이다.

private let mtmPattern: NSRegularExpression = {
    let pieces = ["작" + "혼", "雀" + "魂", "mah" + "jong[ _-]?soul", "maj" + "soul", "jan" + "tama", "じゃん" + "たま",
                  "천" + "봉", "天" + "鳳", "天" + "凤", "텐" + "호", "마작 ?소" + "울", "ten" + "hou"]
    return try! NSRegularExpression(pattern: pieces.joined(separator: "|"), options: [.caseInsensitive])
}()

private let mtmAllowed: [String: Int] = [
    "Tests/checkTests/Fixtures/mahjong/cases.json": 11,
    "Tests/checkTests/Fixtures/mahjong/corpus_alias.json": 1,
]

private struct MTMError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func mtmRepoRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) { return directory }
        directory.deleteLastPathComponent()
    }
    throw MTMError("저장소 꼭대기(Package.swift)를 못 찾았다")
}

private func mtmHits(in text: String) -> Int {
    mtmPattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
}

private func mtmFiles(under directory: URL, label: String) -> [(label: String, url: URL)] {
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

@Suite("아잉 마작 상표 글자 — 저장소 전역 · 두 초안 0(허용 둘)")
struct V03xxMahjongTrademarkTests {
    // 없으면: 서비스 이름이 저장소·초안 어디에 새어도 초록이다. 허용 건수가 늘거나(코퍼스 밖 글) 사라져도(복사본이 바뀌었다) 모른다.
    @Test
    func 서비스_이름_글자는_허용_둘_말고_없다() throws {
        let root = try mtmRepoRoot()
        var targets: [(label: String, url: URL)] = []
        for folder in ["Sources", "Tests"] {
            targets += mtmFiles(under: root.appendingPathComponent(folder, isDirectory: true), label: folder)
        }
        let migrations = root.appendingPathComponent("supabase/migrations", isDirectory: true)
        if FileManager.default.fileExists(atPath: migrations.path) {
            targets += mtmFiles(under: migrations, label: "supabase/migrations")
        }
        targets.append(("CHANGELOG.md", root.appendingPathComponent("CHANGELOG.md")))
        var drafts = 0
        for key in ["MAHJONG_RULES_SQL", "MAHJONG_TABLE_SQL"] {
            if let path = ProcessInfo.processInfo.environment[key], !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                targets.append(("\(key)(\(URL(fileURLWithPath: path).lastPathComponent))", URL(fileURLWithPath: path)))
                drafts += 1
            }
        }
        var hits: [String] = []
        var allowedHits: [String: Int] = [:]
        var textFiles = 0
        for target in targets {
            if mtmHits(in: target.label) > 0 { hits.append("\(target.label) (경로 이름)") }
            guard let data = try? Data(contentsOf: target.url), let text = String(data: data, encoding: .utf8) else { continue }
            textFiles += 1
            guard mtmHits(in: text) > 0 else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let count = mtmHits(in: String(line))
                guard count > 0 else { continue }
                if mtmAllowed[target.label] != nil {
                    allowedHits[target.label, default: 0] += count
                } else {
                    hits.append("\(target.label):\(number + 1)")
                }
            }
        }
        print("[상표] 글자 파일 \(textFiles) · 초안 \(drafts) · 허용 \(allowedHits)")
        #expect(textFiles > 1_000, "글자 파일을 \(textFiles)개만 읽었다 — 훑는 범위가 비었다")
        #expect(hits.isEmpty, "서비스 이름 글자가 있다(대소문자 무시): \(hits.prefix(10))")
        for (file, count) in mtmAllowed {
            #expect(allowedHits[file, default: 0] == count, "\(file) 안 글자가 \(allowedHits[file, default: 0])건이다(허용 \(count))")
        }
        if ProcessInfo.processInfo.environment["MAHJONG_REQUIRE_MIGRATION"] == "1" {
            #expect(drafts == 2, "MAHJONG_REQUIRE_MIGRATION=1 인데 두 초안을 다 못 읽었다(\(drafts))")
        }
        // ★ 기준선: 같은 패턴이 대문자 표기와 띄어 쓴 한글 표기를 잡는다(감지기가 살아 있다).
        #expect(mtmHits(in: "MAH" + "JONG SOUL") == 1 && mtmHits(in: "마작 소" + "울") == 1 && mtmHits(in: "아잉 마작") == 0)
    }
}
