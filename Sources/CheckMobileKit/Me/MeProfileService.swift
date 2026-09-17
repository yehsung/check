import CheckCore
import Foundation

/// 나 탭 머리(이름·사진) 한 행. 두 칸 다 옛 칸(가입 때부터 있음)이라 컬럼 부재 400 걱정이 없다 —
/// 새 칸(센터·착용 캐릭터·별명 쿨타임·공개 설정)은 코어의 **별도 GET** 을 그대로 쓴다(맥과 같은 규약: 새 칸 하나 때문에 머리 전체가 죽지 않게).
package struct MeProfileCardRow: Decodable, Equatable, Sendable {
    package var displayName: String?
    package var avatarUrl: String?
}

extension SupabaseWorkService {
    /// 내 프로필 이름·사진(`profiles?select=display_name,avatar_url&id=eq.<me>`, 읽기). 행이 없으면 nil.
    /// 맥은 이 값을 팀 상태(work_statuses 임베드)에서 얻지만, 폰 머리는 팀이 없어도 서야 하고 그 조회는 GET 넷이라 한 줄짜리를 따로 둔다.
    package func fetchMyProfileCard(accessToken: String, userID: String) async throws -> MeProfileCardRow? {
        let data = try await send(
            path: "/rest/v1/profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "display_name,avatar_url"),
                URLQueryItem(name: "id", value: "eq.\(userID)"),
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([MeProfileCardRow].self, from: data).first
    }
}
