@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 순위 탭 재디자인(w15 · 시안 B 05·06) — 새 문구 함수와 모양 계약.
@MainActor
@Suite("순위 탭 재디자인(w15 R)")
struct RankingsRedesignTests {
    static func team(total: Int, members: Int, working: Int = 0, goalHours: Int = 40) -> TeamLeaderboardEntry {
        TeamLeaderboardEntry(id: "t", name: "팀", weeklyGoalHours: goalHours, totalSeconds: total, workingCount: working, memberCount: members)
    }

    static func tokens(total: Int, today: Int = 0, todayDate: String = "2026-09-17") -> TokenBoardEntry {
        TokenBoardEntry(
            userID: "u", name: "사람", avatarURL: nil, total: total,
            claudeInput: total, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
            codexInput: 0, codexOutput: 0, todayTotal: today, todayDate: todayDate
        )
    }

    @Test("제목 부제: 판마다 기간과 마감")
    func boardSubtitles() {
        #expect(RankingsText.boardSubtitle(.league) == "이번 주 · 월요일 0시에 새로 시작해요")
        #expect(RankingsText.boardSubtitle(.tokens) == "이번 달 · 1일에 새로 시작해요")
        #expect(RankingsText.boardSubtitle(.minigame) == "오늘 · 자정에 마감해요")
    }

    @Test("팀 리그 행: 큰 숫자(평균) · 퍼센트 · 부제 조각 — 기록 없는 팀은 '—'(0% 로 지어내지 않는다) · 구분점은 조각 사이에만")
    func leagueRowTexts() {
        let busy = Self.team(total: 5 * (25 * 3600 + 7 * 60), members: 5, working: 3)
        #expect(RankingsText.leagueValue(busy) == "25시간 07분")
        #expect(RankingsText.leaguePercentText(busy) == "63%")
        #expect(RankingsText.leagueSubtitle(busy) == "5명 · 3명 근무 중 · 목표 40시간")
        #expect(RankingsText.leagueAverageHint == "1인당 평균")

        let idle = Self.team(total: 3 * 3600, members: 3, goalHours: 45)
        #expect(RankingsText.leagueSubtitle(idle) == "3명 · 근무 중 없음 · 목표 45시간")

        let empty = Self.team(total: 0, members: 3)
        #expect(RankingsText.leagueValue(empty) == "—")
        #expect(RankingsText.leaguePercentText(empty) == "—")
        #expect(RankingsText.leagueSubtitle(empty) == "3명 · 이번 주 기록 없음 · 목표 40시간")
        for subtitle in [busy, idle, empty].map({ RankingsText.leagueSubtitle($0) }) {
            #expect(!subtitle.hasSuffix("·") && !subtitle.hasSuffix("· ") && !subtitle.hasPrefix("·"))
            #expect(!subtitle.contains("근무중"), "붙여 쓴 '근무중'이 남았다")
        }
    }

    @Test("팀 리그 막대 색 뜻: 달성 = 초록 · 게이지 그라디언트는 '우리 팀'만 · 나머지는 진행 파랑")
    func leagueBarKinds() {
        let halfway = Self.team(total: 2 * 20 * 3600, members: 2)
        #expect(RankingsText.leagueBarKind(halfway, isMyTeam: true) == .gauge)
        #expect(RankingsText.leagueBarKind(halfway, isMyTeam: false) == .accent)
        let done = Self.team(total: 2 * 41 * 3600, members: 2)
        #expect(RankingsText.leagueBarKind(done, isMyTeam: false) == .done)
        #expect(RankingsText.leagueBarKind(done, isMyTeam: true) == .done)
    }

    @Test("AI 토큰 행: 큰 숫자와 오늘 증가가 도구 줄과 같은 억/만 한 체계 · 비교 막대는 1등 대비 0~1")
    func tokenRowTexts() {
        let top = Self.tokens(total: 5_014_407_391, today: 184_523_456)
        #expect(RankingsText.tokenTotalCompact(top) == "50.1억")
        #expect(RankingsText.tokenTodayCompact(top, todayKey: "2026-09-17") == "오늘 +1.8억")
        #expect(top.toolUsageLabel == "Claude 50.1억", "도구 줄과 큰 숫자가 같은 말로 읽힌다")
        #expect(RankingsText.tokenTotalCompact(Self.tokens(total: 6_382_702)) == "638만")
        #expect(RankingsText.tokenTotalCompact(Self.tokens(total: 8_432)) == "8,432")
        #expect(RankingsText.tokenTodayCompact(Self.tokens(total: 900, today: 99, todayDate: "2026-09-10"), todayKey: "2026-09-17") == "오늘 +0",
                "지난 날짜의 증가량은 오늘이 아니다")
        // 정확한 값은 보이스오버가 읽는다(단위 축약은 화면만).
        #expect(RankingsText.tokenRowAccessibility(rank: 1, entry: top, isMe: false, isPrivate: false, todayKey: nil).contains("5,014,407,391"))

        #expect(RankingsText.tokenBarFraction(total: 5_014_407_391, top: 5_014_407_391) == 1)
        #expect(abs(RankingsText.tokenBarFraction(total: 6_382_702, top: 5_014_407_391) - 0.00127) < 0.0001)
        #expect(RankingsText.tokenBarFraction(total: 10, top: 0) == 0)
        #expect(RankingsText.tokenBarFraction(total: 20, top: 10) == 1)
    }

    @Test("모양 계약: 행마다 카드 없이 한 그룹 · 세그먼트는 판 고르기 하나(게임은 메뉴 알약) · 내 행 = 초상 + '나' · 보석은 실제 루비")
    func layoutContracts() throws {
        let sections = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift")
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsTab.swift")
        let folder = sections + tab
        // 행 조립·어제 1등·이름 줄은 통합 때 Components 로 승격했다(게임 탭과 한 벌) — 순위 탭은 그 부품을 쓰고,
        // 초상·'나' 칩·루비 획득 칩은 승격한 부품 안에서 확인한다.
        let rankParts = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/RankBoardParts.swift")
        let personParts = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/PersonComponents.swift")
        #expect(!folder.contains("AingCard {"), "순위 행이 다시 행마다 카드가 됐다(비평: 목록 밀도)")
        #expect(sections.components(separatedBy: "InsetGroup {").count - 1 >= 3, "리그·토큰·미니게임 목록이 인셋 그룹 안의 행이 아니다")
        #expect(folder.components(separatedBy: ".pickerStyle(.segmented)").count - 1 == 1, "세그먼트가 두 줄로 쌓였다(게임 고르기는 메뉴 알약)")
        #expect(sections.contains("Menu {"), "미니게임 게임 고르기가 메뉴 알약이 아니다")
        #expect(sections.contains("RankingsFace(") && tab.contains("typealias RankingsFace = RankRowFace"),
                "순위 행 얼굴이 공용 부품이 아니다")
        #expect(rankParts.contains("CharacterPortrait("), "내 행에 착용 캐릭터 초상이 없다")
        #expect(tab.contains("case .me: return .me") && personParts.contains("MeChip("), "내 행에 '나' 칩이 없다")
        #expect(sections.contains("awarded: winner.awarded") && rankParts.contains("RubyGain("),
                "어제 1등 획득이 실제 루비 획득 칩이 아니다")
        #expect(sections.contains("RubyIcon("), "상품 문구에 실제 보석이 없다")
        #expect(!folder.contains("diamond.fill"))
        #expect(!sections.contains("style: .gauge") || sections.contains("case .gauge: return .gauge"), "게이지 그라디언트가 '우리 팀' 판정을 거치지 않는다")
        #expect(!sections.contains("usesMedals: false"), "AI 토큰 판만 메달 규칙이 다르다")
        #expect(!tab.contains("RankingsAvatar"), "센터 배지가 다시 아바타 아래로 갔다(이름 뒤가 규칙)")
    }
}
