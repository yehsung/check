import CheckCore
import Foundation

// 이번 주 누적 근무 보상(v0.3.55 · 폰 1.0.8(19) — 서버 20261016120000_weekly_work_reward.sql).
//
// 사장님 결정(2026-10-16): 한 주(월요일 0시 → 다음 월요일 0시, KST)에 누적 20시간을 넘으면 💎20, 40시간 💎50, 60시간 💎200 —
// 칸마다 **따로** 준다(60시간이면 그 주 270). 3시간 랩(+3)은 그대로 있고 이건 더해진 것이다.
//
// 폰이 하는 일은 **읽기 하나**다: `weekly_work_status()` 가 이 사용자의 지급을 먼저 정산하고(서버 한 트랜잭션 · 칸마다 한 번은
// DB 유니크 인덱스가 막는다) 이번 주 상태를 돌려준다. 근무 시간 계산 · 칸 판정 · 지급은 전부 서버 몫이고 폰은 숫자를 옮겨 적는다
// (서버 cron 도 1분마다 같은 정산을 돈다 — 앱이 꺼져 있어도 받는다).

// 응답 모델 · 디코더 · 서비스 호출은 맥과 **한 벌**이다 — CheckCore `WeeklyWorkReward.swift`(`WeeklyWorkStatus` ·
// `SupabaseWorkService.weeklyWorkStatus(accessToken:)` · 게이지 `WeeklyWorkGauge`). 폰 갈래가 동시에 짓느라 두었던 임시 사본
// (DTO)은 병합 때 이 코어 모델로 접었다 — 디코드 규약도 하나다(키가 없거나 모양이 틀려도 통째로 죽지 않는다 · 깨진 칸은 그 칸만 ·
// 누적초를 모르면 nil 이고 카드는 0 으로 지어내지 않는다). 여기 남은 것은 폰에만 있는 규칙(이 기기가 본 칸 · 알림 합치기 ·
// 주 넘김 · 루비 미러)이다.

// MARK: - 순수 규칙(화면이 읽는 값 — 맥 `swift test` 가 값으로 잰다)

/// 한 번의 '받았어요' 알림(+N). 여러 칸이 한꺼번에 들어오면 합쳐서 한 번.
package struct WeeklyWorkGrantNotice: Equatable, Sendable {
    package var ruby: Int
    /// 들어온 칸들(시간 · 오름차순). 지난주 따라잡기 지급도 섞일 수 있다.
    package var hours: [Int]

    package init(ruby: Int, hours: [Int]) {
        self.ruby = ruby
        self.hours = hours
    }
}

/// 이 기기가 마지막으로 **본** 이번 주 받은 칸(계정별 저장 — `WeeklyWorkRules.newGrants`).
package struct WeeklyWorkSeen: Equatable, Sendable {
    package var weekStart: String
    package var claimedHours: Set<Int>

    package init(weekStart: String, claimedHours: Set<Int>) {
        self.weekStart = weekStart
        self.claimedHours = claimedHours
    }

    /// 저장 글자 "2026-10-12|20,40"(빈 칸이면 "2026-10-12|").
    package var encoded: String {
        "\(weekStart)|" + claimedHours.sorted().map(String.init).joined(separator: ",")
    }

    package init?(encoded: String?) {
        guard let encoded else { return nil }
        let parts = encoded.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        weekStart = String(parts[0])
        claimedHours = Set(parts[1].split(separator: ",").compactMap { Int($0) })
    }
}

package enum WeeklyWorkRules {
    /// '받았어요' 알림에 올릴 지급.
    ///
    /// 서버의 `granted_now` 만 보면 이 알림은 **거의 영영 안 뜬다**: cron 이 1분마다 같은 정산을 돌아 칸을 넘긴 지 1분 안에 먼저
    /// 지급하므로, 앱이 부르는 순간엔 이미 `claimed: true` 이고 `granted_now` 는 빈 배열이다. 그래서 '이 기기가 마지막으로 본 상태'와
    /// 비교해 새로 받은 칸도 알린다.
    /// - `granted_now`(이번 호출이 넣은 행 — 지난주 따라잡기 포함)는 늘 알린다.
    /// - 이번 주 받은 칸 중 `previous` 에 없던 것도 알린다. 단 `previous` 가 아예 없으면(설치 · 로그인 직후 첫 조회) 기준만 잡고
    ///   알리지 않는다 — 며칠 전에 받은 것을 방금 받은 것처럼 말하지 않는다. `previous` 가 지난주 것이면 이번 주 칸은 다 처음 본 것이다.
    /// - 같은 (주, 칸)은 한 번만 센다.
    ///
    /// ★ **v0.3.58 받기 서버에서는 '본 기록과 비교' 갈래를 보지 않는다**(`status.supportsClaim`). 그 서버에서 `claimed` 가 거짓 →
    ///   참이 되는 길은 **사람이 [받기]를 누른 것**뿐이고(이 폰이면 받기 연출이 그 자리에서 말했고, 맥에서 눌렀으면 거기서 봤다),
    ///   그걸 "N시간 채웠어요"로 또 말하면 같은 일을 두 번 알린다. `granted_now`(언제나 `[]` 다)는 그대로 둔다 — 서버가 다시
    ///   자동 지급으로 돌아가는 날 이 갈래가 저절로 산다. 맥 `WeeklyWorkStatus.newlyGranted(since:)` 와 같은 판단이다.
    package static func newGrants(previous: WeeklyWorkSeen?, status: WeeklyWorkStatus) -> [WeeklyWorkStatus.Grant] {
        var result: [WeeklyWorkStatus.Grant] = []
        var keys = Set<String>()
        func add(_ grant: WeeklyWorkStatus.Grant) {
            let week = grant.weekStart ?? status.weekStart ?? ""
            guard keys.insert("\(week)#\(grant.hours)").inserted else { return }
            result.append(grant)
        }
        status.grantedNow.forEach(add)
        if !status.supportsClaim, let previous, let week = status.weekStart {
            let already = previous.weekStart == week ? previous.claimedHours : []
            for tier in status.tiers where tier.claimed && !already.contains(tier.hours) {
                add(.init(hours: tier.hours, ruby: tier.ruby))
            }
        }
        return result
    }

    /// 이번 응답을 본 뒤 저장할 기준(이번 주 받은 칸). 주를 모르면 nil(저장하지 않는다).
    package static func seen(after status: WeeklyWorkStatus) -> WeeklyWorkSeen? {
        guard let week = status.weekStart, !week.isEmpty else { return nil }
        return WeeklyWorkSeen(weekStart: week, claimedHours: Set(status.tiers.filter(\.claimed).map(\.hours)))
    }

    /// 알림 하나로 합친다(빈 배열이면 nil).
    package static func notice(for grants: [WeeklyWorkStatus.Grant]) -> WeeklyWorkGrantNotice? {
        guard !grants.isEmpty else { return nil }
        let ruby = grants.reduce(0) { $0 + $1.ruby }
        guard ruby > 0 else { return nil }
        return WeeklyWorkGrantNotice(ruby: ruby, hours: grants.map(\.hours).sorted())
    }

    /// "2026-10-19" → 그 날 0시(KST). 못 읽으면 nil. 맥과 같은 달력(CheckCore `WeeklyWorkCalendar`).
    package static func kstMidnight(_ day: String?) -> Date? {
        WeeklyWorkCalendar.kstMidnight(day)
    }

    /// 이 응답의 주가 끝났는가(지금이 다음 주 월요일 0시 이후). 끝났으면 화면 값은 지난주 것이다 — 스로틀 없이 다시 읽는다.
    package static func weekHasRolled(_ status: WeeklyWorkStatus?, now: Date) -> Bool {
        status?.hasEnded(at: now) ?? false
    }

    /// 루비 미러에 서버 잔량을 쓸 것인가 — **더 새 값을 되돌리지 않는다**.
    ///
    /// 미러(`context.gomokuHost.rubyBalance`)는 상점 · 뽑기 · 오목 · 체스가 다 쓰는 한 칸이다. 이 조회가 떠 있는 사이 다른 응답이
    /// 미러에 썼으면(예: 뽑기 −50) 그 값이 이 응답보다 늦게 읽힌 값일 수 있다 — 그때 이 응답의 잔량을 쓰면 깎인 루비가
    /// 화면에서 되살아난다. 그래서 **떠난 뒤 미러에 쓴 횟수가 0 일 때만** 쓴다(`MobileGomokuHost.rubyWriteSerial`). 값으로 비교하면
    /// 사이의 쓰기가 마침 떠날 때와 같은 값이었을 때(ABA — 40시간 보상 50 = 뽑기 값 50 이라 흔하다) 옛 잔량이 이긴다.
    /// 쓰지 못했는데 이번에 받은 게 있으면 스토어가 상점을 다시 읽어 맞춘다.
    package static func shouldApplyRuby(server: Int?, writeSerialAtDeparture: Int, currentWriteSerial: Int) -> Bool {
        guard server != nil else { return false }
        return writeSerialAtDeparture == currentWriteSerial
    }
}
