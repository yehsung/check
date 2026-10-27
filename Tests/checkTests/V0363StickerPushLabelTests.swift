import Foundation
import Testing
@testable import CheckCore

// v0.3.63 보강 — **푸시 알림 본문**의 아잉이 이모티콘(서버 쪽 한 자리).
//
// 이모티콘은 서버를 안 고치려고 평범한 텍스트(`[아잉:기쁨]`)로 나른다. 앱 안에서는 맥·폰이 그림으로 그리거나
// `AingStickerText.preview` 로 "아잉이 기쁨"으로 읽어 주는데, **푸시 알림 본문만 날것**이었다 —
// `push_on_message_insert` 가 `new.body` 를 그대로 `aps.alert.body` 에 넣기 때문이다.
// 2026-10-22 운영 실측: 최근 message 푸시 40건 중 18건이 `[아잉:기쁨]` 꼴로 나갔다.
// 폰이 가로챌 수도 없다(페이로드에 `mutable-content` 가 없어 알림 서비스 확장이 아예 안 불린다).
// 그래서 서버 함수 `public.sticker_push_label(text)` 를 뒀다.
//
// ⚠️ **같은 표가 두 곳에 산다**(스위프트 열거 · SQL case). 한쪽만 고치면 **푸시에서만** 토큰이 새는데,
//    그건 보내는 사람 화면에도 받는 사람 앱에도 안 보인다 — 알림 창에만 뜬다. 그래서 여기서 맞대 본다.
//    이모티콘을 늘릴 때는 **마이그레이션에도 줄을 더해야** 이 시험이 초록이다.

private struct SpushError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라간다(다른 마이그레이션 계약과 같은 방식).
private func spushMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SpushError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    throw SpushError("supabase/migrations 를 못 찾았다(워크트리라면 CHECK_MIGRATIONS_DIR 로 알려 줘라)")
}

/// `--` 줄 주석을 걷어낸다 — 안 그러면 **주석에 적은 예시 토큰**이 표로 잡힌다.
private func spushStripped(_ sql: String) -> String {
    sql.components(separatedBy: "\n")
        .map { line -> String in
            guard let c = line.range(of: "--") else { return line }
            return String(line[..<c.lowerBound])
        }
        .joined(separator: "\n")
}

@Test("서버 푸시 라벨 표가 AingSticker 여섯 종과 글자까지 같다")
func v0363StickerPushLabelMatchesEnum() throws {
    let dir = try spushMigrationsDirectory()
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasSuffix("_sticker_push_label.sql") }
    let name = try #require(names.sorted().last, "푸시 라벨 마이그레이션이 없다 — 서버는 아직 날것 토큰을 보낸다")
    let sql = spushStripped(try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8))

    // `when '<토큰>' then '<문구>'` 를 전부 긁는다.
    let pattern = #"when\s+'([^']+)'\s+then\s+'([^']+)'"#
    let regex = try NSRegularExpression(pattern: pattern)
    var table: [String: String] = [:]
    for m in regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)) {
        guard let k = Range(m.range(at: 1), in: sql), let v = Range(m.range(at: 2), in: sql) else { continue }
        table[String(sql[k])] = String(sql[v])
    }

    let expected = Dictionary(uniqueKeysWithValues: AingSticker.allCases.map {
        ($0.token, AingStickerText.preview(for: $0.token))
    })
    let serverSide = table.sorted { $0.key < $1.key }
    let clientSide = expected.sorted { $0.key < $1.key }
    #expect(table == expected,
            "서버 표와 클라 열거가 갈렸다 — 푸시에서만 토큰이 샌다(알림 창에만 보여서 아무도 못 본다). 서버: \(serverSide) · 클라: \(clientSide)")

    // 치환은 **통째로 같을 때만**이다. `case <컬럼> when ... end` 꼴이어야 접두·접미가 붙은 본문이 안 걸린다
    // (확성기 `📢 ` 가 붙은 본문은 그대로 가야 한다 — 0.3.62 의 의도).
    #expect(sql.contains("case p_body"), "토큰을 통째 일치가 아닌 방식으로 찾으면 확성기·평범한 글까지 바뀐다")
    #expect(sql.contains("else p_body"), "표에 없는 본문을 그대로 돌려주지 않으면 평범한 메시지가 비어 나간다")

    // 트리거가 실제로 그 함수를 지나야 한다 — 함수만 만들고 안 부르면 아무것도 안 바뀐다.
    #expect(sql.contains("public.sticker_push_label(new.body)"),
            "트리거가 아직 new.body 를 그대로 담는다 — 함수를 만들어 두고 안 부르는 꼴이다")
}
