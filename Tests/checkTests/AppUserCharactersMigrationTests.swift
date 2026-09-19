import Foundation
import Testing
@testable import check
@testable import CheckCore

// 기본 아바타 = 착용 캐릭터(SPEC 작업 F · 2026-09-20) — **캐릭터 한 표 마이그레이션의 소스 계약**(20260920200000_app_user_characters.sql).
//
// 행동은 로컬 Postgres 하네스(replay-harness-v2 전용 사본 · 체인 102개 재생 → 새 파일 3회 연속 적용 → 파일 안 프로브 11건,
// 합성 계정 갈래와 빌린 프로필 갈래 둘 다 · 뮤턴트 8개 전부 빨강)가 증명했다. 여기서 보는 것은 **그 행동을 만드는 문장이
// 사라지거나 넓어지는 것**이고, 특히 위험한 여섯 가지다:
//   ① 가시성이 app_user_directory(숨김 격리)와 갈라지는 것 — 심사용 숨김 계정이 일반 사용자에게 샌다.
//   ② 차단을 거르는 것 — 차단당한 사람의 순위판에서 차단한 사람만 이니셜이 되어 "차단당했다"가 샌다.
//   ③ 서버가 값을 접는 것(null → 'aing' 등) — 클라의 "모르는 id → 이니셜" 규칙이 무너진다.
//   ④ 실행권이 anon 에게 새는 것.
//   ⑤ 서버 반환 칸 이름과 클라 디코더(`AppUserCharacterRow`)가 갈리는 것 — 표가 조용히 비고 전원 이니셜로 남는다.
//   ⑥ 이 파일이 기존 함수·표·권한에 손대는 것 — 47명이 쓰는 목록 함수를 다시 정의하지 않는 것이 이 설계의 이유다.
//
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

private struct AppUserCharactersContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private let aucMigrationName = "20260920200000_app_user_characters.sql"

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫 디렉토리를 잡는다.
/// `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다(V0333·V0334 계약 테스트들과 같은 방식).
private func aucMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppUserCharactersContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var visited: [String] = []
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        visited.append(directory.path)
        directory = directory.deletingLastPathComponent()
    }
    throw AppUserCharactersContractError(
        "supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", ")). "
            + "워크트리라면 'cp -R /Users/yesung/check/supabase ./supabase' 로 들여오거나 CHECK_MIGRATIONS_DIR 로 알려 줘라."
    )
}

/// `--` 줄 주석을 걷어낸다.
private func aucStripLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func aucSquash(_ sql: String) -> String {
    sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func aucMigrationFiles() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: try aucMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// (주석 걷은 원문, 공백 접고 소문자로 만든 한 줄).
private func aucSQL(_ name: String = aucMigrationName) throws -> (code: String, flat: String) {
    let file = try aucMigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw AppUserCharactersContractError("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    let code = aucStripLineComments(try String(contentsOf: file, encoding: .utf8))
    return (code, aucSquash(code).lowercased())
}

/// 공백 접은 소문자 SQL 에서 `create or replace function public.<name>(` **마지막** 정의의 머리부터 본문 닫힘까지. 없으면 nil.
private func aucFunctionDefinition(_ name: String, in flat: String) -> String? {
    guard let start = flat.range(of: "create or replace function public.\(name)(", options: .backwards) else { return nil }
    let rest = flat[start.lowerBound...]
    guard let asRange = rest.range(of: " as $") else { return nil }
    let afterAs = rest[asRange.upperBound...]
    guard let tagEnd = afterAs.firstIndex(of: "$") else { return nil }
    let tag = "$" + afterAs[afterAs.startIndex..<tagEnd] + "$"
    let bodyStart = afterAs.index(after: tagEnd)
    guard let close = afterAs[bodyStart...].range(of: tag) else { return nil }
    return String(rest[rest.startIndex..<close.upperBound])
}

// MARK: - ① 가시성 = app_user_directory 최신 정의

@Test
func 캐릭터표_가시성은_app_user_directory_최신_정의와_같은_줄이다() throws {
    let (_, flat) = try aucSQL()
    let definition = try #require(aucFunctionDefinition("app_user_characters", in: flat), "app_user_characters 정의가 없다")

    // 기준: 이 파일보다 **앞** 번호에서 app_user_directory 를 마지막으로 정의한 파일(지금은 20260918180000 — 차단 줄을 얹은 판).
    var canonical: (file: String, body: String)?
    for file in try aucMigrationFiles() where file.lastPathComponent < aucMigrationName {
        let body = aucSquash(aucStripLineComments(try String(contentsOf: file, encoding: .utf8))).lowercased()
        if let found = aucFunctionDefinition("app_user_directory", in: body) { canonical = (file.lastPathComponent, found) }
    }
    let directory = try #require(canonical, "app_user_directory 의 정본을 못 찾았다")
    #expect(directory.file == "20260918180000_blocks_and_reports.sql",
            "app_user_directory 의 최신 정의가 \(directory.file) 로 옮겨 갔다 — 캐릭터 표의 가시성을 그 판과 다시 대조하라")

    for line in ["where auth.uid() is not null", "and public.same_visibility(auth.uid(), p.id)"] {
        #expect(directory.body.contains(line), "기준(app_user_directory)에 가시성 줄 '\(line)' 이 없다 — 기준이 바뀌었다")
        #expect(definition.contains(line), "app_user_characters 에 가시성 줄 '\(line)' 이 없다 — 숨김 계정이 샌다")
    }
    // 적용 시점에도 두 본문을 카탈로그로 대조한다(누가 app_user_directory 를 바꿨으면 배포가 멈춘다).
    #expect(flat.contains("pg_get_functiondef('public.app_user_directory()'::regprocedure)"),
            "사후 단언이 app_user_directory 본문과 대조하지 않는다")
}

// MARK: - ② 차단을 거르지 않는다 · 나를 포함한다 · ③ 값을 접지 않는다

@Test
func 캐릭터표는_차단을_거르지_않고_나를_포함하며_원문을_싣는다() throws {
    let (_, flat) = try aucSQL()
    let definition = try #require(aucFunctionDefinition("app_user_characters", in: flat))
    #expect(!definition.contains("blocked_between"), "차단을 거른다 — 차단당한 사람의 화면에서 차단한 사람만 이니셜이 되어 차단이 샌다")
    #expect(!definition.contains("user_blocks"), "차단 표를 직접 본다 — 차단은 이 표의 범위가 아니다(20260918180000 머리말)")
    #expect(!definition.contains("p.id <> auth.uid()") && !definition.contains("p.id != auth.uid()"),
            "나를 뺀다 — 순위판·팀 현황의 내 행 아바타를 그릴 수 없다")
    #expect(definition.contains("select p.id, p.character from public.profiles p"),
            "profiles.character 원문을 그대로 싣지 않는다")
    #expect(!definition.contains("coalesce(p.character"), "서버가 null 을 접는다 — null(= 아잉)과 모르는 id 의 구별은 클라 몫이다")
    #expect(!definition.contains("'aing'"), "서버 본문이 캐릭터 id 를 적는다 — 명단은 CHECK 한 곳에만 있다")
    // 적용 시점에도 같은 계약을 카탈로그로 되묻는다.
    #expect(flat.contains("if position('blocked_between' in v_src) > 0 then"))
    #expect(flat.contains("if position('p.id <> auth.uid()' in v_src) > 0 then"))
}

// MARK: - ④ 실행권 · definer

@Test
func 캐릭터표_RPC_는_definer_이고_authenticated_만_실행한다() throws {
    let (_, flat) = try aucSQL()
    let definition = try #require(aucFunctionDefinition("app_user_characters", in: flat))
    #expect(definition.contains("security definer"), "security definer 가 아니다 — profiles RLS 가 팀 범위라 팀 밖 캐릭터를 못 읽는다")
    #expect(definition.contains("set search_path = public"), "search_path 가 고정되지 않았다(definer 함수의 필수 자물쇠)")
    #expect(definition.contains(" stable "), "stable 이 아니다")
    let signature = "public.app_user_characters()"
    #expect(flat.contains("revoke all on function \(signature) from public;"), "public 회수 줄이 없다")
    #expect(flat.contains("revoke execute on function \(signature) from public, anon;"),
            "anon 회수 줄이 없다 — Supabase 는 새 함수에 anon 실행권을 딸려 보낸다")
    #expect(flat.contains("grant execute on function \(signature) to authenticated;"),
            "authenticated 에게 주는 줄이 없다 — 표가 403 이라 아바타가 전원 이니셜로 남는다")
    #expect(!flat.contains("grant execute on function \(signature) to anon"), "anon 에게 준다")
    #expect(!flat.contains("grant execute on function \(signature) to public"), "public 에게 준다")
    // 적용 시점 카탈로그 단언.
    #expect(flat.contains("has_function_privilege('anon', v_fn, 'execute')"))
    #expect(flat.contains("has_function_privilege('authenticated', v_fn, 'execute')"))
}

// MARK: - ⑤ 서버 반환 칸 ↔ 클라 디코더

@Test
func 캐릭터표_반환_칸은_클라_디코더가_읽는_이름과_같다() throws {
    let (_, flat) = try aucSQL()
    let definition = try #require(aucFunctionDefinition("app_user_characters", in: flat))
    // 인자가 없다 — 클라는 빈 본문 `{}` 를 보낸다.
    #expect(definition.hasPrefix("create or replace function public.app_user_characters() returns table("),
            "app_user_characters 에 인자가 생겼다(클라는 빈 본문을 보낸다 — PGRST202)")
    let tableStart = try #require(definition.range(of: "returns table("))
    let tableEnd = try #require(definition.range(of: ") language sql", range: tableStart.upperBound..<definition.endIndex))
    let serverColumns = definition[tableStart.upperBound..<tableEnd.lowerBound]
        .split(separator: ",")
        .compactMap { $0.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) }
        .map { $0.replacingOccurrences(of: "\"", with: "") }
    // 디코더는 `.convertFromSnakeCase` 뒤의 카멜 이름으로 매칭한다 — 스네이크로 되돌려 대조한다.
    let clientColumns = AppUserCharacterRow.CodingKeys.allCases.map { key in
        key.rawValue.reduce(into: "") { result, character in
            if character.isUppercase { result += "_" + character.lowercased() } else { result.append(character) }
        }
    }
    #expect(serverColumns == clientColumns, "서버 반환 칸과 클라 디코더가 갈렸다 — 서버 \(serverColumns) · 클라 \(clientColumns)")
    // CHARACTER 는 타입 키워드라 칸 이름 자리에 인용이 필요하다 — 적용 시점 단언이 그 모양 그대로를 되묻는다.
    #expect(flat.contains("returns table(user_id uuid, \"character\" text)"))
    #expect(flat.contains("'table(user_id uuid, \"character\" text)'"), "사후 단언이 반환 칸을 되묻지 않는다")
    #expect(SupabaseWorkService.appUserCharactersPath == "/rest/v1/rpc/app_user_characters")
}

// MARK: - ⑥ 기존 것에 손대지 않는다

@Test
func 캐릭터표_마이그레이션은_기존_함수_표_권한에_손대지_않는다() throws {
    let (code, flat) = try aucSQL()
    let creates = code.lowercased().components(separatedBy: "create or replace function").count - 1
    #expect(creates == 1, "함수를 \(creates)개 정의한다 — 이 파일은 app_user_characters 하나만 더한다(목록 함수를 다시 정의하지 않는 것이 설계다)")
    for forbidden in ["create table", "alter table", "drop table", "create policy", "alter policy", "drop policy",
                      "create trigger", "drop function", " references ", "grant select", "grant update", "grant insert",
                      "revoke select", "revoke update"] {
        #expect(!flat.contains(forbidden), "이 파일이 '\(forbidden)' 을 한다 — 새 함수 하나 말고는 아무것도 바꾸지 않는다")
    }
    // 뒤 파일이 이 함수를 다시 정의하면(가시성·차단 규칙이 바뀔 수 있다) 이 계약을 그 파일에도 걸어야 한다.
    var defining: [String] = []
    for file in try aucMigrationFiles() {
        let sql = aucStripLineComments(try String(contentsOf: file, encoding: .utf8)).lowercased()
        if sql.contains("create or replace function public.app_user_characters(")
            || sql.contains("create function public.app_user_characters(") {
            defining.append(file.lastPathComponent)
        }
    }
    #expect(defining == [aucMigrationName], "app_user_characters 를 정의하는 파일이 바뀌었다: \(defining)")
}

// MARK: - 프로브 규약

@Test
func 캐릭터표_흐름_프로브는_기대_건수와_실제_단언_수가_같고_센티널로_롤백한다() throws {
    let (code, flat) = try aucSQL()
    let expected = try #require(flat.range(of: "v_expected constant int := "))
    let digits = flat[expected.upperBound...].prefix { $0.isNumber }
    let declared = try #require(Int(digits))
    let increments = code.components(separatedBy: "probes := probes + 1;").count - 1
    #expect(declared == increments, "v_expected(\(declared))와 실제 단언 수(\(increments))가 다르다 — 카운터 단언이 거짓이 된다")
    #expect(declared >= 10, "프로브가 너무 적다(\(declared))")
    #expect(flat.contains("raise exception 'app_user_characters_probe_rollback'"), "센티널 롤백이 없다 — 같은 파일 3회 적용이 행을 남긴다")
    #expect(flat.contains("execute format('set local role %i', v_exec_role)"), "실행 역할 복귀가 set local role 이 아니다(RESET ROLE 함정)")
    #expect(!flat.contains("reset role"), "RESET ROLE 을 쓴다 — 운영 CLI 에서 세션 사용자(권한 0)로 떨어진다")
    #expect(flat.contains("notify pgrst"), "스키마 캐시 리로드 신호가 없다 — PostgREST 가 새 RPC 를 404 로 낸다")
    // 차단 프로브에는 대조군이 있다(사람 찾기에서는 빠진다) — 없으면 '거르지 않음'과 '픽스처가 안 걸림'이 구별되지 않는다.
    #expect(flat.contains("from public.app_user_directory() d"), "차단 대조군(app_user_directory)이 없다")
    // 최상위 트랜잭션 제어가 없다(운영 CLI 가 파일을 한 트랜잭션으로 감싼다).
    for line in code.split(separator: "\n") where ["begin;", "commit;", "rollback;"].contains(line.trimmingCharacters(in: .whitespaces).lowercased()) {
        Issue.record("최상위 트랜잭션 제어가 있다: \(line)")
    }
}

// MARK: - 맥(작업 M)이 기댈 사실 — 서버 명단의 초상이 맥 번들에 이미 있다

/// 서버가 허용하는 캐릭터 명단(`profiles_character_valid` CHECK 의 **마지막** 정의).
private func serverCharacterRoster() throws -> [String] {
    var roster: [String]?
    for file in try aucMigrationFiles() {
        let flat = aucSquash(aucStripLineComments(try String(contentsOf: file, encoding: .utf8))).lowercased()
        var searchStart = flat.startIndex
        while let header = flat.range(of: "add constraint profiles_character_valid check (character is null or character in (",
                                      range: searchStart..<flat.endIndex) {
            guard let close = flat.range(of: ")", range: header.upperBound..<flat.endIndex) else { break }
            roster = flat[header.upperBound..<close.lowerBound]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "' ")) }
            searchStart = close.upperBound
        }
    }
    return try #require(roster, "profiles_character_valid 명단을 못 찾았다")
}

@Test
func 서버_캐릭터_명단의_neutral_초상이_맥_번들에_전부_있다() throws {
    // 작업 M 의 결정(AppUserCharacters.swift 머리말): 맥은 새 의존·새 자원 번들 없이 자기 번들의 초상을 쓴다 —
    // 그래서 build-local.sh 는 지금처럼 check_check.bundle 하나만 복사하면 된다. 그 전제가 이 테스트다.
    let roster = try serverCharacterRoster()
    #expect(roster.contains("aing") && roster.count >= 6, "서버 명단이 이상하다: \(roster)")
    let directory = AppUserCharacterDirectory(catalog: CheckMascotAssets.catalog)
    for id in roster {
        #expect(directory.knownIDs.contains(id), "서버가 허용하는 '\(id)' 를 맥 카탈로그가 모른다 — 그 사람은 맥에서 이니셜로 남는다")
        let url = try #require(CheckMascotAssets.portraitURL(for: .neutral, characterID: id), "'\(id)' 의 neutral 초상 경로가 없다")
        #expect(FileManager.default.fileExists(atPath: url.path), "'\(id)' 의 neutral 초상 파일이 번들에 없다: \(url.path)")
    }
}

// MARK: - 처리방침

@Test
func 처리방침은_착용_캐릭터가_아바타_자리에_보인다고_적는다() throws {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var privacyURL: URL?
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("docs/privacy.md")
        if FileManager.default.fileExists(atPath: candidate.path) { privacyURL = candidate; break }
        directory = directory.deletingLastPathComponent()
    }
    let privacy = try String(contentsOf: try #require(privacyURL, "docs/privacy.md 를 못 찾았다"), encoding: .utf8)
    let lines = privacy.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let bullet = try #require(lines.first { $0.hasPrefix("- 착용 캐릭터(") }, "처리방침에 착용 캐릭터 항목이 없다")
    // 이 마이그레이션 뒤로 "그 외의 목록·순위표에는 오르지 않습니다"는 거짓이다(애플 심사에 들어가는 URL 이다).
    #expect(!bullet.contains("오르지 않습니다"), "처리방침이 여전히 착용 캐릭터가 목록·순위표에 안 오른다고 말한다: \(bullet)")
    #expect(bullet.contains("사진을 올리지 않았으면") && bullet.contains("아바타 자리"),
            "처리방침이 '사진이 없으면 아바타 자리에 착용 캐릭터가 보인다'를 적지 않는다: \(bullet)")
    #expect(bullet.contains("같은 앱을 쓰는 모든 사용자"), "누가 보는지(앱 사용자 전체)를 적지 않는다")
    // '나만 보는 것' 절의 예외 문장도 울트라만 적으면 거짓이 된다.
    let mineOnly = try #require(lines.first { $0.hasPrefix("**나만 보는 것**") })
    #expect(mineOnly.contains("아바타 자리"), "'나만 보는 것' 절이 착용 캐릭터의 예외를 울트라로만 적는다: \(mineOnly)")
}

/// 수리(리뷰 medium): 처리방침이 착용 캐릭터의 노출 범위를 **사진 없는 사람으로 좁혀** 적었다 — "사진을 올렸으면 사진이 보이고
/// 캐릭터는 아바타로 쓰이지 않습니다". 두 사실과 어긋난다:
///   · 서버 `app_user_characters()` 는 avatar_url 과 **무관하게** 같은 쪽 사용자 전원의 착용값을 로그인한 모두에게 준다
///     (마이그레이션 §1 — 사진 조건이 없다). 사진을 올린 사람의 착용값도 앱 사용자 전체의 앱에 간다.
///   · 코어는 사진 로딩이 실패하면 **캐릭터**로 떨어진다(`AppUserAvatar.afterPhotoFailure`). 사진을 올렸어도 캐릭터가 뜬다.
/// 애플 심사에 들어가는 URL 이라 노출 범위는 실제보다 좁게 적으면 안 된다. 전제(서버에 사진 조건 없음 · 사진 실패 → 캐릭터)를
/// 먼저 확인하고, 그 전제가 바뀌면 이 계약도 함께 고쳐야 한다.
@Test
func 처리방침은_사진을_올린_사람의_착용값도_전달되고_사진_실패시_캐릭터가_뜬다고_적는다() throws {
    // 전제 ① — 서버 본문에 사진 조건이 없다.
    let (_, flat) = try aucSQL()
    let body = try #require(aucFunctionDefinition("app_user_characters", in: flat), "app_user_characters 정의가 없다")
    #expect(!body.contains("avatar_url"), "app_user_characters 가 사진 유무로 행을 거른다 — 이 계약의 전제가 사라졌다: \(body)")
    // 전제 ② — 사진이 실패하면 캐릭터로 떨어진다.
    let photo = AppUserAvatar.photo(URL(string: "https://example.invalid/a.png")!, fallbackCharacterID: "fox")
    #expect(photo.afterPhotoFailure == .character("fox"), "사진 실패가 캐릭터로 떨어지지 않는다 — 이 계약의 전제가 사라졌다")

    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var privacyURL: URL?
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("docs/privacy.md")
        if FileManager.default.fileExists(atPath: candidate.path) { privacyURL = candidate; break }
        directory = directory.deletingLastPathComponent()
    }
    let privacy = try String(contentsOf: try #require(privacyURL, "docs/privacy.md 를 못 찾았다"), encoding: .utf8)
    let lines = privacy.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let bullet = try #require(lines.first { $0.hasPrefix("- 착용 캐릭터(") }, "처리방침에 착용 캐릭터 항목이 없다")

    #expect(!bullet.contains("아바타로 쓰이지 않"),
            "처리방침이 '사진을 올렸으면 캐릭터는 아바타로 쓰이지 않는다'고 말한다 — 사진 실패 시 캐릭터가 뜨고 착용값은 사진과 무관하게 전달된다: \(bullet)")
    #expect(bullet.contains("불러오지 못"), "처리방침이 '올린 사진을 불러오지 못하면 착용 캐릭터가 대신 보인다'를 적지 않는다: \(bullet)")
    #expect(bullet.contains("상관없이") && bullet.contains("전달"),
            "처리방침이 '착용값은 사진을 올렸는지와 상관없이 앱 사용자에게 전달된다'를 적지 않는다: \(bullet)")

    // '나만 보는 것' 절의 예외 문장이 '사진을 올리지 않았으면'만 조건으로 달면 사진을 올린 사람의 캐릭터는 울트라 상대만 본다고 읽힌다.
    let mineOnly = try #require(lines.first { $0.hasPrefix("**나만 보는 것**") })
    #expect(mineOnly.contains("상관없이") && mineOnly.contains("전달"),
            "'나만 보는 것' 절이 착용값 전달을 '사진을 올리지 않았으면'으로 좁혀 적는다: \(mineOnly)")
    #expect(mineOnly.contains("불러오지 못"), "'나만 보는 것' 절이 사진을 못 불러올 때 캐릭터가 뜬다는 것을 적지 않는다: \(mineOnly)")

    // '같은 앱을 쓰는 모든 사용자에게 보이는 것' 절이 착용 캐릭터를 목록에 두지 않으면 그 절만 읽은 사람은 범위를 좁게 안다.
    let everyoneStart = try #require(lines.firstIndex { $0.hasPrefix("**같은 앱을 쓰는 모든 사용자에게 보이는 것**") })
    let everyoneEnd = try #require(lines[everyoneStart...].firstIndex { $0.hasPrefix("**나만 보는 것**") })
    let everyone = lines[everyoneStart..<everyoneEnd]
    #expect(everyone.contains { $0.hasPrefix("- ") && $0.contains("착용 캐릭터") },
            "'같은 앱을 쓰는 모든 사용자에게 보이는 것' 절에 착용 캐릭터가 없다")
}
