import Foundation
import Testing
@testable import check
@testable import CheckCore

/// 착용 캐릭터를 **서버에 저장하는 경로**의 계약.
///
/// **왜 필요한가**(2026-09-13 실측): 선택기는 `CharacterSelection`(UserDefaults)에만 저장하고 있었고,
/// `set_character` 를 부르는 곳이 클라 전체에 **한 곳도 없었다**. 그래서 캐릭터를 골라도 `profiles.character`
/// 가 전원 null 이었고 — 캐릭터가 남에게 보이는 유일한 순간인 **울트라 찌르기**(`take_pokes` 가
/// `from_character` 를 실어 준다)에서 전원이 아잉으로 보였다. 내 화면만 맞아서 **정상으로 보이는** 결함이다.
@Suite("v0.3.16 캐릭터 서버 저장")
struct V0316CharacterServerSyncTests {

    // MARK: - 본문 인코딩 (PGRST202 함정)

    /// `set_character(p_id text)` 에는 **인자 기본값이 없다.** 그래서 본문에서 키가 빠지면 PostgREST 가
    /// 함수를 못 고르고 `PGRST202` 가 된다. Swift 가 만들어 주는 인코더는 Optional 을 `encodeIfPresent`
    /// 로 내보내 **키를 생략**하므로, 커스텀 `encode(to:)` 가 없으면 "기본으로 되돌리기"가 통째로 실패한다.
    @Test("nil 은 키 생략이 아니라 null 로 실린다")
    func nilEncodesAsExplicitNull() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try String(data: encoder.encode(SetCharacterRequest(pId: nil)), encoding: .utf8)
        let body = try #require(json)
        #expect(body.contains("\"p_id\""),
                Comment(rawValue: "p_id 키가 생략됐다 — 서버 인자에 기본값이 없어 PGRST202 가 된다: \(body)"))
        #expect(body.contains("null"), Comment(rawValue: "p_id 가 null 로 안 실렸다: \(body)"))
    }

    @Test("id 는 p_id 로 스네이크 변환되어 실린다")
    func idEncodesAsSnakeCase() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try String(data: encoder.encode(SetCharacterRequest(pId: "fox")), encoding: .utf8)
        let body = try #require(json)
        #expect(body.contains("\"p_id\""), Comment(rawValue: body))
        #expect(body.contains("fox"), Comment(rawValue: body))
    }

    /// 서버 어휘 4종(`set_character` 주석)이 전부 디코드돼야 한다. 하나라도 throw 하면 저장이
    /// **성공했는데도** 실패로 보이거나 그 반대가 된다.
    @Test("서버 응답 어휘 네 가지가 전부 디코드된다")
    func decodesEveryServerStatus() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let cases: [(String, String, String?)] = [
            (#"{"status":"ok","character":"fox"}"#, "ok", "fox"),
            (#"{"status":"ok","character":null}"#, "ok", nil),
            (#"{"status":"unknown_character","id":"nope"}"#, "unknown_character", nil),
            (#"{"status":"unauthorized"}"#, "unauthorized", nil),
            (#"{"status":"no_profile"}"#, "no_profile", nil),
        ]
        for (json, status, character) in cases {
            let decoded = try decoder.decode(SetCharacterResponse.self,
                                             from: Data(json.utf8))
            #expect(decoded.status == status, Comment(rawValue: json))
            #expect(decoded.character == character, Comment(rawValue: json))
        }
    }

    // MARK: - 배선 계약 (여기가 끊기면 화면은 멀쩡한데 서버만 비어 있다)

    @Test("선택기 두 곳이 저장 성공 뒤 onChosen 을 부른다")
    func bothPickersCallOnChosen() throws {
        for name in ["CheckCharacterPanel.swift", "CheckSettingsView.swift"] {
            let code = csStripped(try csSource(name))
            #expect(code.contains("selectedID = id onChosen(id)"),
                    Comment(rawValue: "\(name): 저장이 이긴 가지에서 onChosen 을 안 부른다 — 로컬에만 남는다"))
        }
    }

    @Test("호출부 두 곳이 서버 밀어넣기를 연결한다")
    func callSitesWireTheServerPush() throws {
        for name in ["CheckMenuView.swift", "CheckSettingsView.swift"] {
            let code = csStripped(try csSource(name))
            #expect(code.contains("onChosen:") && code.contains("pushSelectedCharacter("),
                    Comment(rawValue: "\(name): onChosen 이 pushSelectedCharacter 로 안 간다 — 고른 캐릭터가 남에게는 아잉이다"))
        }
    }

    /// **세션이 생기는 두 경로**(저장 세션 활성화 · 로그인 마무리)는 v0.3.30 부터 **밀지 않고 읽는다.**
    /// 0.3.16~0.3.29 에는 여기서 로컬 선택을 밀었는데, 폰에서 캐릭터를 바꾸면 맥이 다음에 켜질 때 그걸 말없이
    /// 되돌렸다(R8). 동작은 `V0330CharacterSyncTests` 가 스텁으로 재고, 여기는 배선 개수만 못 박는다.
    @Test("세션이 생기는 두 경로는 밀지 않고 서버값을 읽는다")
    func bothSessionPathsReadInsteadOfPush() throws {
        let code = csStripped(try csSource("WorkTimerStoreAuth.swift"))
        let pushes = code.components(separatedBy: "pushSelectedCharacter(announcesFailure: false)").count - 1
        #expect(pushes == 0, Comment(rawValue:
                "세션 확립 경로에서 \(pushes)번 민다(기대 0) — 폰에서 바꾼 캐릭터를 맥이 켜질 때 되돌린다"))
        let reads = code.components(separatedBy: "syncEquippedCharacterFromServer(reason: .launch)").count - 1
            + code.components(separatedBy: "syncEquippedCharacterFromServer(reason: .signIn)").count - 1
        #expect(reads == 2, Comment(rawValue:
                "세션 확립 경로에서 \(reads)번 읽는다(기대 2 — 저장 세션 활성화 · 로그인 마무리)"))
    }

    /// ★ 기준선이 실제로 다른가: 위 계약들이 "원래부터 그랬다"로 초록이 되지 않게,
    ///   서버 호출이 **정말 새로 생긴 것**인지 서비스 쪽에서 확인한다.
    @Test("서비스가 set_character RPC 를 실제로 부른다")
    func serviceCallsTheRPC() throws {
        let code = csStripped(try CheckCoreSourceLayout.joinedSplitSource("SupabaseWorkService.swift"))
        #expect(code.contains("/rest/v1/rpc/set_character"),
                "set_character RPC 경로가 서비스에 없다 — 쓰기 경로가 통째로 없다")
    }
}

// MARK: - 소스 읽기

private func csSource(_ name: String) throws -> String {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/check", isDirectory: true)
    return try String(contentsOf: dir.appendingCheckSourcePath(name), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다
/// (이 저장소가 실제로 밟은 함정). 문자열 리터럴 안의 `//` 는 보존한다 — URL 이 주석으로 오인되면
/// 그 뒤 코드가 통째로 검사에서 사라진다.
private func csStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
