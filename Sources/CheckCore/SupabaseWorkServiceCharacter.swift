import Foundation

extension SupabaseWorkService {
    /// 내 착용 캐릭터(`profiles.character`) 서버값. nil = 기본(아잉).
    ///
    /// **왜 읽기가 필요한가**(v0.3.30): 폰에서도 캐릭터를 바꾼다. 맥이 서버값을 모르면 자기 로컬 선택을
    /// 진실로 믿고 되밀어 폰의 변경을 지운다(R8). 이 GET 이 맥이 서버를 따라가는 유일한 입구다.
    ///
    /// **별도 GET 인 이유**: 기존 설정 GET(`fetchTokenUsageSettings`)의 select 에 끼우면 컬럼이 없는 서버에서
    /// 42703 → 그 요청이 통째로 400 이 되어 토큰 공개·수집·집중 모드까지 같이 못 읽는다(센터·미니게임 공개와 같은
    /// 규약). 컬럼 select 권한은 `20260913093000_profile_character.sql` 이 authenticated 에 준다.
    ///
    /// **행이 0개면 throw 한다**(`CharacterSyncFetchError.noProfileRow`). 자기 행은 RLS(`id = auth.uid()`)로 늘
    /// 보이므로 0행은 "프로필 행이 없다"는 이상 상태다 — 그걸 "기본(아잉)"으로 단정하면 로컬 선택을 근거 없이
    /// 지운다. 호출부는 다른 조회 실패와 똑같이 "로컬 그대로, 밀지도 않음"으로 접는다.
    package func fetchEquippedCharacter(accessToken: String, userID: String) async throws -> String? {
        let data = try await send(
            path: "/rest/v1/profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "character"),
                URLQueryItem(name: "id", value: "eq.\(userID)")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([CharacterSyncProfileRow].self, from: data)
        guard let row = rows.first else { throw CharacterSyncFetchError.noProfileRow }
        return row.character
    }
}

/// `profiles?select=character` 한 행. **Optional** — null(안 골랐다)과 키 없음을 둘 다 "기본"으로 읽는다.
package struct CharacterSyncProfileRow: Decodable, Equatable {
    package var character: String?
}

package enum CharacterSyncFetchError: Error, Equatable {
    /// 자기 프로필 행이 안 보인다(가입 트리거 실패의 잔재 등).
    case noProfileRow
}
