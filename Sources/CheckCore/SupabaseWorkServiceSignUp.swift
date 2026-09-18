import Foundation

// w16(앱스토어 정식 출시 준비): **가입의 팀 합류/생성**을 맥 전용 조각(SupabaseWorkServiceMacOnly.swift)에서 떼어 낸 자리.
// OS 게이트가 없다 — 폰 앱 바이너리에도 컴파일된다.
//
// 왜 이제는 폰이 불러도 되는가: D-base 가 이 둘을 맥 전용으로 묶은 이유는 "폰 범위 밖"이었지 사고 위험이 아니었다.
// 맥 전용 조각의 나머지(take_pokes·work_tick·세션/상태 쓰기·토큰 업로드·찌르기)는 **남의 세션·찌르기·근무 시간**을 건드리므로
// 폰이 한 번이라도 부르면 사고가 나지만, `join_team`·`create_team` 은 **본인 계정에만** 작용한다 — 서버 함수가 `auth.uid()` 의
// 멤버십 행을 넣거나 그 사람을 owner 로 하는 팀을 만들 뿐이고, 다른 사람의 행·세션·찌르기에는 닿지 않는다(센터 게이트도 서버가
// 건다 — 20260912185423_join_team_center_gate.sql). 앱스토어 심사(4.2 최소 기능 · 5.1.1 로그인 벽)는 폰에서 가입이 끝나기를
// 요구하므로, 가입 화면(`MobileSignUpStore`)이 이 둘을 부른다.
//
// 본문은 맥 전용 조각에서 **글자 그대로** 옮겼다 — 맥은 바뀌는 것이 없다(같은 actor 의 확장이라 격리·접근이 같다).
// 소스 계약 테스트는 `CheckCoreSourceLayout.joinedSplitSource("SupabaseWorkService.swift")` 로 세 조각을 이어 읽는다.

extension SupabaseWorkService {
    /// 코드로 팀 합류. join_team(code) RPC 를 로그인 토큰으로 호출한다. 불일치/비로그인은 0행 → nil.
    package func joinTeam(accessToken: String, code: String) async throws -> (teamID: String, name: String, goalHours: Int)? {
        let data = try await send(
            path: "/rest/v1/rpc/join_team",
            method: "POST",
            body: InviteCodeRequest(code: Self.normalizeInviteCode(code)),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([JoinTeamRow].self, from: data)
        guard let row = rows.first else {
            return nil
        }
        return (teamID: row.teamId, name: row.name, goalHours: row.weeklyGoalHours)
    }

    /// 새 팀 만들기. create_team(team_name, goal_hours) RPC 를 로그인 토큰으로 호출하고 참여코드를 함께 받는다.
    package func createTeam(accessToken: String, name: String, goalHours: Int) async throws -> (teamID: String, name: String, inviteCode: String, goalHours: Int) {
        let data = try await send(
            path: "/rest/v1/rpc/create_team",
            method: "POST",
            body: CreateTeamRequest(teamName: name, goalHours: goalHours),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([CreateTeamRow].self, from: data)
        guard let row = rows.first else {
            throw SupabaseWorkServiceError.invalidResponse(200)
        }
        return (teamID: row.teamId, name: row.name, inviteCode: row.inviteCode, goalHours: row.weeklyGoalHours)
    }
}
