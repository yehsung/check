@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 행이 실은 착용값(`characterHint`) — 0.3.41 수리 R2.
//
// 결함: 폰 순위표가 서버가 준 `GomokuRankEntry.user.characterID` 를 버리고 환경값 표(`\.appUserCharacters`)만 봤다. 그 표는
// 로그인 직후 한 번 + 스로틀 조회라(`App/AppUserCharacterStore.swift`) **조회가 실패했거나 아직 안 온 세션에서는 비어 있다** —
// 행마다 자기 캐릭터를 들고 있는데도 순위표 전원이 이니셜이 됐다(맥은 같은 상태에서 캐릭터를 그렸다).
//
// 수리: 맥에만 있던 판정을 코어로 올려(`CheckCore/AppUserCharacters.swift` — `avatar(for:photoURL:characterHint:)`)
// 맥·폰이 **한 규칙**을 쓰게 하고, 폰 `PersonAvatar` 에 `characterHint`(기본값 nil)를 더해 순위 행이 넘긴다.
//
// 여기서 재는 것 둘:
//   ① 규칙 자체 — **폰의 `knownIDs`**(`AingCharacterArt.knownIDs`)로 만든 표에서 네 갈래가 맞는가.
//   ② 배선(소스 계약) — 폰 뷰는 맥 `swift test` 가 못 보므로(`#if os(iOS)`) 소스 글자가 유일한 그물이다.
//
// ★ 사용자 id 는 전부 합성이다(퍼블릭 저장소).

private let hintFox = "00000000-0000-4000-8000-0000000041a1"      // 표에 있다 — 여우
private let hintPlain = "00000000-0000-4000-8000-0000000041a2"    // 표에 있다 — character null(= 아잉으로 접혀 들어온다)
private let hintFuture = "00000000-0000-4000-8000-0000000041a3"   // 표에 있다 — 이 빌드가 모르는 캐릭터
private let hintStranger = "00000000-0000-4000-8000-0000000041a4" // 표에 없다(첫 조회 전 · 조회 실패 · 숨김 격리 밖)

private func hintRow(_ userID: String, _ character: String?) -> AppUserCharacterRow {
    AppUserCharacterRow(userId: userID, character: character)
}

/// 폰이 실제로 만드는 표와 같은 재료(`AppUserCharacterStore` 의 기본 `knownIDs`).
private func hintDirectory(rows: [AppUserCharacterRow]) -> AppUserCharacterDirectory {
    AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs, rows: rows)
}

private let hintFilledDirectory = hintDirectory(rows: [
    hintRow(hintFox, "fox"), hintRow(hintPlain, nil), hintRow(hintFuture, "dragon")
])

@Suite struct AvatarCharacterHintTests {
    /// 갈래 ①: **표가 모르는 사람**은 행이 실은 착용값을 쓴다(앞뒤 공백은 걷는다 — 코어 `CharacterSyncDecision.normalized`).
    @Test("표가 모르는 사람 + 이 빌드가 아는 힌트 → 그 캐릭터")
    func unknownPersonUsesKnownHint() {
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: nil, characterHint: "jellyfish") == .character("jellyfish"))
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: nil, characterHint: " shiba ") == .character("shiba"))
        // 이 빌드가 모르는 캐릭터를 입은 사람도 표 기준으로는 '모름'이다 — 그 사람의 힌트가 아는 id 면 그것을 그린다.
        #expect(hintFilledDirectory.avatar(for: hintFuture, photoURL: nil, characterHint: "ghost") == .character("ghost"))
    }

    /// 갈래 ②: **표가 아는 사람은 표가 이긴다.** 표는 통째로 갈아 끼우는 정본이고 행의 힌트는 그 응답이 떠난 시점의 값이다 —
    /// 힌트가 이기면 같은 사람이 화면마다 다른 캐릭터로 그려진다.
    @Test("표가 아는 사람 → 표가 이긴다(힌트가 달라도)")
    func knownPersonWinsOverHint() {
        #expect(hintFilledDirectory.avatar(for: hintFox, photoURL: nil, characterHint: "ghost") == .character("fox"))
        // 표의 null 은 이미 아잉으로 접혀 있다 — 그건 서버가 말해 준 사실이므로 힌트로 덮지 않는다.
        #expect(hintFilledDirectory.avatar(for: hintPlain, photoURL: nil, characterHint: "ghost") == .character("aing"))
    }

    /// 갈래 ③: 이 빌드가 **초상을 그릴 수 없는** 힌트는 안 쓴다 — 그리면 빈 그림이 선다(코어 접기 규칙).
    @Test("모르는 힌트 → 이니셜")
    func unknownHintFallsBackToInitials() {
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: nil, characterHint: "dragon") == .initials)
    }

    /// 갈래 ④: **nil 을 아잉으로 접지 않는다.** 행의 nil 은 '안 골랐다(아잉)'와 '그 응답이 칸을 안 실었다(신청 행 · 옛 서버)'를
    /// 가르지 못한다 — 아잉으로 단정하면 틀린 사실을 그린다.
    @Test("nil·빈 힌트 → 아잉으로 접지 않고 이니셜")
    func nilHintIsNotFoldedToAing() {
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: nil, characterHint: nil) == .initials)
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: nil, characterHint: "") == .initials)
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: nil, characterHint: "   ") == .initials)
    }

    /// 사진은 여전히 이긴다. 힌트는 **사진이 실패했을 때 떨어질 얼굴**로 들어간다(이니셜이 아니라 캐릭터로).
    @Test("사진 + 힌트 → 사진, 실패 폴백은 힌트 캐릭터")
    func photoKeepsHintAsFallback() throws {
        let photo = try #require(URL(string: "https://x.invalid/p.jpg"))
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: photo, characterHint: "jellyfish")
                == .photo(photo, fallbackCharacterID: "jellyfish"))
        #expect(hintFilledDirectory.avatar(for: hintStranger, photoURL: photo, characterHint: "dragon")
                == .photo(photo, fallbackCharacterID: nil))
    }

    /// 이 수리가 겨눈 바로 그 상태: **표가 비었다**(로그인 직후 조회가 실패했거나 아직 안 왔다). 옛 폰은 여기서 순위표 전원이
    /// 이니셜이었다. 힌트를 넘기면 행이 들고 온 캐릭터가 그대로 선다.
    @Test("표가 비어 있어도 행이 실은 착용값으로 얼굴이 선다(수리 전에는 전원 이니셜)")
    func emptyDirectoryStillDrawsRowCharacters() {
        let empty = hintDirectory(rows: [])
        #expect(empty.avatar(for: hintFox, photoURL: nil) == .initials, "비교 기준선 — 힌트 없이는 이니셜이다")
        #expect(empty.avatar(for: hintFox, photoURL: nil, characterHint: "fox") == .character("fox"))
        #expect(empty.avatar(for: hintPlain, photoURL: nil, characterHint: "aing") == .character("aing"))
        #expect(empty.avatar(for: hintStranger, photoURL: nil, characterHint: "squirrel") == .character("squirrel"))
    }

    // MARK: - 배선(소스 계약 — 주석을 걷어내고 본다)

    /// 규칙은 **코어 한 곳**에만 선언돼 있어야 한다. 맥(`Sources/check/CheckAvatarView.swift`)에 같은 서명을 되살리면
    /// 두 모듈에 겹쳐 맥 빌드가 모호해지고, 지우면 힌트가 조용히 죽는다.
    @MainActor
    @Test("판정은 CheckCore 한 곳에만 선언된다")
    func ruleIsDeclaredOnlyInCore() throws {
        let needle = "func avatar(for userID: String?, photoURL: URL?, characterHint: String?)"
        let declaring = try IntegrationContractTests.files(containing: [needle], under: "Sources")
        #expect(declaring == ["Sources/CheckCore/AppUserCharacters.swift"], "\(declaring)")
    }

    /// 폰 배선: 부품이 힌트를 받아 코어 판정에 넘기고(기본값 nil — 기존 호출부 무영향), 순위 행이 자기 행의 착용값을 넘긴다.
    /// **폰 뷰는 맥 스위트가 그려 보지 못하므로**(`#if os(iOS)`) 이 소스 계약이 유일한 그물이다.
    @MainActor
    @Test("배선: PersonAvatar 가 힌트를 나르고 순위 행이 행의 착용값을 넘긴다")
    func phoneWiringPassesTheHint() throws {
        let person = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/PersonComponents.swift")
        #expect(person.contains("characterHint: String? = nil"), "기본값 nil 이어야 기존 호출부가 무영향이다")
        #expect(person.contains("characters.avatar(for: userID, photoURL: url, characterHint: characterHint)"),
                "부품이 힌트를 받아만 두고 판정에 넘기지 않는다")
        let ranking = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuRanking.swift")
        #expect(ranking.contains("characterHint: entry.user.characterID"), "순위 행이 서버가 준 캐릭터를 버린다")
    }
}
