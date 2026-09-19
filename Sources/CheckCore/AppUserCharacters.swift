import Foundation

// MARK: - 기본 아바타 = 착용 캐릭터 — 캐릭터 한 표 `app_user_characters()` (20260920200000)
//
// 사용자 요청(2026-09-20): 프로필 사진이 없는 사람의 아바타 자리에 별명 첫 글자 대신 **그 사람이 착용한 캐릭터**를 그린다.
// 사진을 올린 사람은 사진 그대로다. 우선순위(정본):
//   ① 올린 사진(avatar_url) → ② 착용 캐릭터 초상(neutral) → ③ 캐릭터를 **모를 때만** 이니셜.
//   사진 로딩이 실패해도 이니셜이 아니라 **캐릭터**로 떨어진다(`AppUserAvatar.photo(_:fallbackCharacterID:)`).
//
// ── 왜 목록 응답에 칸을 더하지 않고 표를 따로 받나 ──
// 목록 RPC(app_user_directory · message_history · token_usage_board · team_weekly_leaderboard · minigame_board ·
// gomoku_lobby · list_blocks · report_admin_list …) 대부분이 캐릭터를 싣지 않는다. 하나씩 고치면 47명이 쓰는 함수 여러 개를
// drop + create 해야 한다(`returns table` 칸 추가 — default·ACL 을 잃은 2026-09-12 사고의 그 자리). 그래서 서버는
// 캐릭터만 담은 표 하나를 주고, 클라는 그 표를 한 번 받아 **user_id 로 찾는다**(`AppUserCharacterDirectory`).
//
// ── 접기 규칙(★ 이 파일의 계약) ──
//   · 서버 null(안 골랐다) = **아잉**이다(`profiles.character` null = 아잉, 20260913093000:12). 그래서 표에 있는 사람은
//     전원 사진 아니면 캐릭터가 뜬다.
//   · 이 빌드가 **모르는** 캐릭터 id 는 아잉으로 접지 않고 **nil(이니셜)** 이다. 폰·맥 착용 경로(`MeCharacterCards.equippedID`
//     · `CharacterSyncDecision`)는 "내 화면에 세울 것"이라 아잉으로 접지만, 여기는 **남의 사실**을 그리는 자리다 —
//     구버전이 새 캐릭터를 아잉으로 단정하면 "그 사람이 아잉을 입었다"는 틀린 사실을 그린다(열거값 확장엔 능력 협상).
//   · 표에 없는 사람(첫 조회 전 · 조회 실패 · 숨김 격리 밖 · 방금 가입해 아직 안 받은 사람)도 nil — 지금처럼 이니셜.
//   · 서버에 함수가 아직 없으면(404 PGRST202 — 앱이 db push 보다 먼저 나갈 수 있다) 조회는 **조용히 빈 표**다.
//     아바타는 지금처럼 이니셜로 남고 아무 오류도 올라가지 않는다.
//   · "아는 캐릭터"의 정본은 그 플랫폼이 **초상을 그릴 수 있는** 캐릭터다 — 코어 `CharacterCatalog` 규칙(아잉은 늘 있다)을 따르고,
//     목록은 호출부가 준다: 맥은 번들 카탈로그(`init(catalog:)` ← `CheckMascotAssets.catalog`), 폰은 초상 번들
//     (`init(knownIDs:)` ← `AingCharacterArt.knownIDs`). 초상이 없는 id 를 '안다'고 하면 빈 그림이 선다.
//
// ── 맥(작업 M)의 결정 — 구현은 `Sources/check/CheckAvatarView.swift` · `WorkTimerStoreAvatars.swift` ──
//   · **초상은 맥 번들에 이미 있다.** `Sources/check/Characters/<id>/portrait-neutral.png`(스프라이트 다섯)와
//     `Sources/check/Resources/aing-neutral.png`(아잉)가 `check_check.bundle` 에 실려 나간다. 폰 `CheckMobileShared/Resources/
//     Portraits` 는 이 원본들을 **무손실 재압축한 사본**이다 — 그림(픽셀)은 같고 파일 바이트는 다르다(`BaseComponentTests` 는
//     바이트가 아니라 **픽셀**로 대조한다). 맥은 **CheckMobileShared 에 의존을 더하지 않고 자원도 옮기지 않는다** —
//     `CheckMascotAssets.portraitURL(for: .neutral, characterID:)` 가 이미 그 둘을 찾는다.
//   · 그래서 `scripts/build-local.sh` 는 **고칠 것이 없다**(지금처럼 `check_check.bundle` 하나만 복사한다). 새 자원 번들을
//     만드는 길(의존 추가·자원 이동)을 고르면 그때는 그 번들도 복사해야 한다 — 안 하면 설치본에서만 캐릭터가 안 보인다.
//   · 주의: `CheckMascotAssets.image(for:characterID:)` 는 모르는 id 를 **아잉으로 폴백**한다(내 캐릭터용 규칙). 남의 아바타는
//     `AppUserCharacterDirectory.characterID(for:)` 가 nil 이면 이니셜을 그려야 한다 — 맥은 그 함수를 쓰지 않고 초상 URL 을 직접
//     디코드한다(`AppUserAvatarArt.portrait(characterID:)` — 못 그리면 nil = 이니셜).
//   · 맥 디렉터리는 `AppUserCharacterDirectory(knownIDs: AppUserAvatarArt.knownIDs)` 로 만든다 — 번들 카탈로그(`CheckMascotAssets.
//     catalog`) 중 **neutral 초상 파일이 실제로 있는** id(아잉 포함). 지금 번들에서는 `init(catalog:)` 와 같은 여섯이지만, 초상 없는
//     캐릭터가 카탈로그에 들어오는 날 '안다'고 해서 빈 그림을 세우지 않게 파일로 거른다.

extension SupabaseWorkService {
    /// 캐릭터 한 표. `POST /rest/v1/rpc/app_user_characters` · 본문 `{}`(인자 없는 RPC — PostgREST 는 본문의 키 집합으로 함수를 고른다).
    ///
    /// 서버는 보는 사람과 같은 쪽(숨김/일반) 사용자 **전원 · 나 포함 · 차단 무관**을 `(user_id, character)` 로 준다.
    /// character 는 서버 원문이다(null = 아잉, 모르는 id 도 그대로) — 접기는 `AppUserCharacterDirectory` 가 한다.
    ///
    /// - 함수가 아직 없는 서버(404 PGRST202 → 공용 매핑 `.databaseSchemaMissing`, 본문 없는 404 → `.invalidResponse(404)`)는
    ///   **빈 배열**이다(파일 머리 "접기 규칙"). 폰 기기 등록(`MobileDeviceService`)과 같은 두 모양을 받는다.
    /// - 그 밖의 실패(네트워크 · 5xx · 세션 만료 · 배열이 아닌 응답)는 **던진다** — 호출부는 지금 가진 표를 그대로 둔다.
    ///   빈 표로 접으면 일시 장애 한 번에 모든 아바타가 이니셜로 깜빡인다.
    /// - 행 하나가 이상해도(칸 없음·타입 어긋남) 배열 전체가 죽지 않는다 — 그 행만 버린다(`AppUserCharacterRow`).
    package func fetchAppUserCharacters(accessToken: String) async throws -> [AppUserCharacterRow] {
        let data: Data
        do {
            data = try await send(
                path: Self.appUserCharactersPath,
                method: "POST",
                body: EmptyBody(),
                accessToken: accessToken,
                prefer: nil
            )
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            return []
        } catch SupabaseWorkServiceError.invalidResponse(404) {
            return []
        }
        let rows = try decoder.decode([AppUserCharacterRow].self, from: data)
        // 클로저 인자 이름이 `row` 가 아닌 이유는 제보·신고 목록과 같다(소스 계약 테스트가 `return rows.map { row in` 을 센다).
        return rows.filter { characterRow in characterRow.userId != nil }
    }

    package nonisolated static let appUserCharactersPath = "/rest/v1/rpc/app_user_characters"
}

// MARK: - 전선 모양

/// `app_user_characters()` 응답 한 행. **전부 옵셔널이고 칸마다 따로 읽는다** — 한 행 때문에 배열 디코드가 통째로 throw 되면
/// 모든 아바타가 이니셜로 돌아간다(신고 목록 `ContentReportAdminRow` 와 같은 관용).
///
/// 키는 `.convertFromSnakeCase` 뒤의 카멜 이름으로 매칭한다(`user_id` → `userId`). 서버 반환 칸 이름은 마이그레이션 §2 가
/// 카탈로그로 못 박고(`TABLE(user_id uuid, "character" text)`), 이 목록과 같은지는 `AppUserCharactersMigrationTests` 가 대조한다.
package struct AppUserCharacterRow: Decodable, Equatable, Sendable {
    /// 사용자 id(uuid 문자열). 비었거나 못 읽으면 nil — 그 행은 버린다(찾을 열쇠가 없다).
    package let userId: String?
    /// `profiles.character` 원문. **nil = 아직 안 골랐다 = 아잉**(키가 없거나 JSON null 이거나 타입이 어긋나도 nil).
    package let character: String?

    package enum CodingKeys: String, CodingKey, CaseIterable {
        case userId, character
    }

    package init(userId: String?, character: String?) {
        self.userId = userId
        self.character = character
    }

    package init(from decoder: any Decoder) throws {
        // 배열 안에 객체가 아닌 원소(null 등)가 섞여도 그 원소만 빈 행이 된다.
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            userId = nil
            character = nil
            return
        }
        func text(_ key: CodingKeys) -> String? { (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil }
        userId = AppUserCharacterDirectory.normalizedUserID(text(.userId))
        character = text(.character)
    }
}

// MARK: - 순수 모델

/// 사용자 id → 아바타에 그릴 캐릭터 id. **값 타입이고 네트워크를 모른다** — 앱 모델이 들고 있다가 뷰에 흘린다.
///
/// 표는 서버 응답으로 **통째로 갈아 끼운다**(`replace(with:)`). 더하기만 하면 숨김 격리 밖으로 옮겨진 사람·계정을 지운 사람의
/// 옛 캐릭터가 끝까지 남는다. 로그아웃하면 `removeAll()` — 앞 계정의 표가 다음 계정 화면에 남으면 안 된다.
package struct AppUserCharacterDirectory: Equatable, Sendable {
    /// 이 빌드가 초상을 그릴 수 있는 캐릭터 id. **아잉은 늘 들어 있다**(`CharacterCatalog` 와 같은 안전망 — null 이 아잉으로
    /// 접히는데 아잉을 모르면 표 전체가 이니셜이 된다).
    package let knownIDs: Set<String>
    /// 소문자 user id → 접은 착용값(null·공백 → "aing"). **모르는 id 도 원문 그대로 보관한다** — 모름 판정은 읽을 때 한다
    /// (다음 빌드가 그 캐릭터를 알게 되어도 표를 다시 받을 필요가 없게, 그리고 진단이 원문을 볼 수 있게).
    private var equipped: [String: String]

    /// 폰: `AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs)` — 초상 번들에 있는 id.
    package init<IDs: Sequence>(knownIDs: IDs, rows: [AppUserCharacterRow] = []) where IDs.Element == String {
        var known = Set(knownIDs.compactMap { CharacterSyncDecision.normalized($0) })
        known.insert(CharacterCatalog.builtInAingID)
        self.knownIDs = known
        self.equipped = [:]
        replace(with: rows)
    }

    /// 맥: `AppUserCharacterDirectory(catalog: CheckMascotAssets.catalog)` — 번들 카탈로그에 있는 id(아잉 포함).
    package init(catalog: CharacterCatalog, rows: [AppUserCharacterRow] = []) {
        self.init(knownIDs: catalog.allIDs, rows: rows)
    }

    /// 아는 사람 수(모르는 캐릭터를 입은 사람 포함 — 표에 있는 사람 수).
    package var count: Int { equipped.count }

    package var isEmpty: Bool { equipped.isEmpty }

    /// 아바타에 그릴 캐릭터 id. **nil = 모른다 → 이니셜**(표에 없는 사람 · 이 빌드가 모르는 캐릭터 · id 가 비었다).
    /// null(안 골랐다)은 여기 오기 전에 이미 아잉으로 접혀 있다.
    package func characterID(for userID: String?) -> String? {
        guard let id = equippedID(for: userID), knownIDs.contains(id) else { return nil }
        return id
    }

    /// 서버 착용값을 접은 것(null → 아잉, **모르는 id 는 원문**). nil = 이 사람을 표에서 모른다. 진단·테스트용 —
    /// 화면은 `characterID(for:)` 나 `avatar(for:photoURL:)` 를 쓴다.
    package func equippedID(for userID: String?) -> String? {
        guard let key = Self.normalizedUserID(userID) else { return nil }
        return equipped[key]
    }

    /// 아바타 우선순위를 한 곳에서 판정한다: 사진 → 캐릭터 → 이니셜. 사진이 있으면 **실패했을 때 떨어질 캐릭터**를 함께 준다.
    package func avatar(for userID: String?, photoURL: URL?) -> AppUserAvatar {
        let character = characterID(for: userID)
        if let photoURL {
            return .photo(photoURL, fallbackCharacterID: character)
        }
        if let character {
            return .character(character)
        }
        return .initials
    }

    /// 서버 표로 **통째로** 갈아 끼운다. user id 가 빈 행은 버리고, 같은 id 가 두 번 오면 뒤의 것이 이긴다.
    ///
    /// ⚠️ 경합: 내가 캐릭터를 바꾼 직후(`setEquipped`) 그 전에 떠난 조회가 늦게 돌아오면 옛 값으로 덮인다. 호출부는 표를
    /// 갈아 끼운 뒤 **자기가 아는 내 착용값을 다시 얹어라**(내 착용의 정본은 방금 set_character 가 ok 를 준 그 값이다).
    package mutating func replace(with rows: [AppUserCharacterRow]) {
        var next: [String: String] = [:]
        for characterRow in rows {
            guard let key = Self.normalizedUserID(characterRow.userId) else { continue }
            next[key] = Self.foldedEquippedID(characterRow.character)
        }
        equipped = next
    }

    /// 한 사람의 착용값을 바로 고친다 — 내가 착용을 바꿨을 때 내 칸을 다음 조회 전에 반영한다.
    /// `serverValue` 는 서버와 같은 어휘다: nil·빈 문자열 = 기본(아잉).
    package mutating func setEquipped(_ serverValue: String?, for userID: String) {
        guard let key = Self.normalizedUserID(userID) else { return }
        equipped[key] = Self.foldedEquippedID(serverValue)
    }

    /// 표를 비운다(로그아웃 · 계정 전환). `knownIDs` 는 빌드의 사실이라 그대로다.
    package mutating func removeAll() {
        equipped = [:]
    }

    /// 서버 착용값 → 표에 적을 값. null·빈 문자열·공백 = **아잉**(서버 규약). 나머지는 앞뒤 공백만 걷은 원문.
    package static func foldedEquippedID(_ serverValue: String?) -> String {
        CharacterSyncDecision.normalized(serverValue) ?? CharacterCatalog.builtInAingID
    }

    /// 사용자 id 의 표 열쇠. uuid 는 대소문자를 가리지 않는다 — 서버는 소문자로 주지만 `UUID().uuidString` 은 대문자라
    /// 호출부 한 곳만 대문자로 넘겨도 영영 못 찾는다. 비었으면 nil.
    package static func normalizedUserID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

/// 아바타 자리에 무엇을 그릴지(판정 결과). 그리는 방법(원형 자르기 · 센터 배지 · 상태 점)은 각 플랫폼 뷰의 몫이다.
package enum AppUserAvatar: Equatable, Sendable {
    /// 올린 사진. 로딩이 실패하면 `fallbackCharacterID` 의 캐릭터로, 그것도 nil 이면 이니셜로 떨어진다.
    case photo(URL, fallbackCharacterID: String?)
    /// 착용 캐릭터의 neutral 초상.
    case character(String)
    /// 캐릭터를 모른다 — 지금의 이니셜 원.
    case initials

    /// 사진 로딩이 실패했을 때 대신 그릴 것. 사진이 아닌 경우는 자기 자신이다.
    package var afterPhotoFailure: AppUserAvatar {
        guard case .photo(_, let fallback) = self else { return self }
        return fallback.map { .character($0) } ?? .initials
    }
}
