import CheckCore
import Foundation

// 우리 팀 전체 명단(지금 탭 [전체 보기] → push). 값·순수 계산·문구만 둔다 — 플랫폼 무관이라 맥 `swift test` 가 그대로 돈다
// (화면은 `NowTeamRosterScreen.swift`).
//
// 맥 `TeamPanel`(CheckMenuView.swift `sortedMembers` · `TeamMemberLiveRow`)이 견본이다: 쉬는 사람까지 전원 · 근무 중 먼저 · 그 안은
// 이름순 · 사람마다 주간 누적과 목표 막대. 다만 시간은 맥 공식이 아니라 `NowTimeMath` 로 센다 — 이 화면의 내 줄이 지금 탭 내 카드와
// 다른 숫자를 말하면 안 된다(폰은 60초마다 받으므로 끊김 판정 시각도 `presenceJudgedAt` 을 따른다).
//
// 서버 요청을 더하지 않는다: 재료는 지금 탭이 이미 받아 둔 `teamMembers` · `directory` 다.
//
// ★ 차단: **명단에서 빼지 않는다.** 차단 확인 시트가 "순위판·팀 현황의 이름은 그대로 남아요"라고 약속했고(`BlockReportText.blockConfirmScopeNote`)
//   맥 팀 카드도 빼지 않는다. 대신 ① 그 사람이 쓴 문장(상태메시지)은 보이지 않는다 — 서버가 서로 차단한 사람을 사람 목록에서 빼므로
//   보통은 재료부터 없고, 방금 차단해 옛 목록을 쥔 창만 `hiddenPeerIDs` 가 막는다. ② 이 화면에는 말 거는 입구가 없다.

/// 지금 탭 내비게이션 경로 원소.
package enum NowDestination: Hashable, Sendable {
    /// 우리 팀 전체 명단.
    case teamRoster
}

extension NowText {
    package static let teamRosterSeeAll = "전체 보기"
    /// 우리 팀 묶음이 없는 자리(우리 팀에 근무 중인 사람이 없다)의 절 머리 링크 — "우리 팀" 줄이 없어 무엇의 전체인지 글자로 말한다.
    package static let teamRosterSeeAllInHeader = "우리 팀 전체 보기"
    package static let teamRosterWorking = "근무 중"
    package static let teamRosterResting = "쉬는 중"
    /// 서버가 이름을 안 줬을 때(코어 `assembleTeamStatuses` 의 폴백과 같은 글자).
    package static let teamMemberFallbackName = "팀원"
    package static let teamRosterEmpty = "아직 명단에 보일 팀원이 없어요"
    package static let teamRosterUnavailable = "팀 명단을 불러오지 못했어요"
    package static let teamRosterNoTeamBody = "지금 탭에서 팀 코드로 합류하거나 새 팀을 만들 수 있어요"
    /// "아잉 데모팀 · 1인당 주 40시간".
    package static func teamRosterSummary(teamName: String?, goalHours: Int) -> String {
        let goal = "1인당 주 \(goalHours)시간"
        guard let teamName, !teamName.isEmpty else { return goal }
        return "\(teamName) · \(goal)"
    }
    /// 줄 오른쪽 "주 24시간 48분"(맥 `primaryDetail` 의 "주 N시간"과 같은 말).
    package static func teamRosterWeek(_ seconds: Int) -> String { "주 \(NowFormat.hoursMinutesText(seconds))" }
    package static let teamRosterJustStarted = "방금 시작했어요"
    /// 근무 중인 줄 부제 "지금 3시간 20분째". 1분이 안 됐으면 "0분째"라 하지 않는다.
    package static func teamRosterElapsed(_ seconds: Int) -> String {
        seconds < 60 ? teamRosterJustStarted : "지금 \(NowFormat.hoursMinutesText(seconds))째"
    }
}

/// 명단 한 줄의 값(시각 `now` 기준).
package struct NowTeamRosterRow: Identifiable, Equatable, Sendable {
    package var id: String
    package var name: String
    package var avatarURL: URL?
    /// 센터 서버값(표시는 `CenterLabel` 한 곳).
    package var center: String?
    package var isMe: Bool
    /// 근무 중인가(`status == .working` — 끊긴 사람도 여기다. 맥 정렬과 같은 기준).
    package var isWorking: Bool
    package var isStale: Bool
    /// 근무 중이고 **시작 시각을 알 때만**: 이번 세션 경과(끊겼으면 마지막 신호에서 멈춘 값). 근무 중인데 열린 세션 행이 안 왔으면
    /// (다른 팀에 열린 세션 · 부분 응답) nil 이다 — 0 으로 두면 몇 시간째 일하는 사람이 "방금 시작했어요"가 된다.
    package var elapsedSeconds: Int?
    /// 끊긴 줄 부제 "마지막 확인 N분 전".
    package var lastSeenAt: Date?
    /// 이미 `StatusMessage.display` 를 지난 값(nil = 줄을 그리지 않는다).
    package var statusMessage: String?
    package var weekSeconds: Int
    /// 1인당 목표 진행(0~1).
    package var goalProgress: Double
    package var isGoalMet: Bool

    /// 보이스오버 한 줄: "민트, 근무 중, 3시간 20분째, 이번 주 9시간". 화면 글자와 같은 사실을 말한다(줄이 자식을 합치므로 이 문장이 전부다).
    package func spokenSummary(now: Date) -> String {
        var parts = [name]
        if isMe { parts.append("나") }
        if isStale {
            parts.append(NowText.staleLastSeen(lastSeenAt.map { MobileRelativeTime.text(for: $0, now: now) }))
        } else if isWorking {
            parts.append(NowText.teamRosterWorking)
            if let elapsedSeconds {
                parts.append(elapsedSeconds < 60 ? NowText.teamRosterJustStarted : "\(NowFormat.spokenDuration(elapsedSeconds))째")
            }
        } else {
            parts.append(NowText.teamRosterResting)
        }
        parts.append("\(NowText.weekPrefix) \(NowFormat.spokenDuration(weekSeconds))")
        if let statusMessage { parts.append("상태메시지 \(statusMessage)") }
        return parts.joined(separator: ", ")
    }
}

/// 명단 전체(근무 중 · 쉬는 중 두 묶음).
package struct NowTeamRoster: Equatable, Sendable {
    package var working: [NowTeamRosterRow]
    package var resting: [NowTeamRosterRow]

    package var isEmpty: Bool { working.isEmpty && resting.isEmpty }
    package var count: Int { working.count + resting.count }
}

package enum NowTeamRosterRules {
    /// 표시 이름. 서버 이름이 비었거나 공백뿐이면 폴백 — 이니셜도 이름도 없는 빈 줄을 그리지 않는다.
    package static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NowText.teamMemberFallbackName : trimmed
    }

    /// 맥 `TeamPanel.sortedMembers` 와 같은 순서: 근무 중 먼저, 그 안은 이름순(`localizedStandardCompare`).
    /// 같은 이름은 id 로 고정한다 — 새로고침마다 두 줄이 자리를 바꾸지 않게.
    package static func precedes(_ lhs: NowTeamRosterRow, _ rhs: NowTeamRosterRow) -> Bool {
        if lhs.isWorking != rhs.isWorking { return lhs.isWorking }
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }

    package static func build(
        members: [TeamMemberStatus],
        directory: [PokeDirectoryRow],
        hiddenPeerIDs: Set<String>,
        me: String?,
        goalHours: Int,
        fetchedAt: Date,
        now: Date,
        presenceAt: Date
    ) -> NowTeamRoster {
        var directoryByID: [String: PokeDirectoryRow] = [:]
        for row in directory where directoryByID[row.userId] == nil { directoryByID[row.userId] = row }
        let goalSeconds = max(1, goalHours) * 3600
        let rows = members.map { member -> NowTeamRosterRow in
            let entry = directoryByID[member.id]
            let isWorking = member.status == .working
            let isStale = isWorking && NowTimeMath.isStale(member, now: presenceAt)
            let week = NowTimeMath.weekSeconds(member, fetchedAt: fetchedAt, now: now, presenceAt: presenceAt)
            return NowTeamRosterRow(
                id: member.id,
                name: displayName(member.name),
                avatarURL: member.avatarURL ?? entry?.avatarUrl.flatMap { URL(string: $0) },
                center: entry?.center,
                isMe: member.id == me,
                isWorking: isWorking,
                isStale: isStale,
                elapsedSeconds: isWorking && member.currentSessionStartedAt != nil
                    ? NowTimeMath.elapsedSeconds(member, now: now, presenceAt: presenceAt)
                    : nil,
                lastSeenAt: isStale ? (member.lastSeenAt ?? member.updatedAt) : nil,
                statusMessage: hiddenPeerIDs.contains(member.id) ? nil : StatusMessage.display(entry?.statusMessage),
                weekSeconds: week,
                goalProgress: TeamWeeklyGoal(workedSeconds: week, goalSeconds: goalSeconds).progress,
                isGoalMet: week >= goalSeconds
            )
        }
        .sorted(by: precedes)
        return NowTeamRoster(working: rows.filter(\.isWorking), resting: rows.filter { !$0.isWorking })
    }
}

extension NowStore {
    /// 지금 탭의 [전체 보기]를 세울까. 명단을 받았을 때만 — 모르는 채로 들어가면 빈 화면이 먼저 보인다.
    package var showsTeamRosterEntry: Bool { membership != nil && hasLoadedTeam }

    /// [전체 보기]. 이미 쌓여 있으면 또 쌓지 않는다 — 빠르게 두 번 누르면 같은 화면이 두 장 쌓여 뒤로를 두 번 눌러야 한다.
    /// (지금 탭이 쌓는 화면은 이것뿐이라 경로가 비었는지만 보면 된다.)
    package func openTeamRoster() {
        guard context.router.path(for: .now).isEmpty else { return }
        context.router.push(NowDestination.teamRoster, on: .now)
    }

    /// 전체 명단(팀 상태를 한 번이라도 받았을 때만). 서버를 부르지 않는다.
    package func teamRoster(now: Date) -> NowTeamRoster? {
        guard let fetchedAt = teamFetchedAt, membership != nil else { return nil }
        return NowTeamRosterRules.build(
            members: teamMembers,
            directory: directory,
            hiddenPeerIDs: context.links.messages?.hiddenBlockedPeerIDs ?? [],
            me: context.session.userID,
            goalHours: goalHours,
            fetchedAt: fetchedAt,
            now: now,
            presenceAt: presenceJudgedAt(now: now)
        )
    }
}
