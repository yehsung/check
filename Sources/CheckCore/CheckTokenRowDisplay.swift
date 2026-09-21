import Foundation

// MARK: - 팝오버 토큰 행의 표시 규칙 (순수)
//
// 왜 별도 파일인가(두 가지):
//  ⓐ `CheckTokenUsage.swift` 는 이 작업과 동시에 **다른 세션이 편집 중**이다. 같은 파일에 규칙을 들이면
//     두 작업이 같은 줄에서 만난다.
//  ⓑ 값·툴팁·렌더 게이트 셋이 **한 함수 안**에 있어야 "스토어만 고치고 뷰는 그대로" 가 구조적으로 불가능해진다.
//     이 저장소의 관행('클라 게이트는 짝으로 있다')을 주석이 아니라 타입으로 못 박는 자리다.

/// 순위판 보드 RPC 가 내려준 **내 행**의 표시값 묶음. 팝오버 행이 이 값을 그대로 그린다.
///
/// 왜 서버 행인가(2026-09-22 실측):
/// 공유 Codex 계정 사용자의 팝오버는 `TokenUsageDisplay.effectiveTotal` 로 계산해 **계정 원본**을 그대로 띄우고 있었다
/// (분배 계수 share_ratio 가 한 번도 안 곱해진 값). 순위판은 서버가 나눈 내 몫을 띄워서, 같은 사람의 두 숫자가 갈렸다.
///   · ㅂ보예성  개인 5,784,713,585 vs 순위 2,844,663,420 (+2,940,050,165)
///   · 맥주밤거리엠버서더 개인 11,154,164,635 vs 순위 4,614,662,772 (+6,539,501,863 — 약 2.4배)
///   · 수 빈    개인 6,455,604,017 vs 순위 6,952,033,183 (**−496,429,166** — 올라가는 사람도 있다)
/// (2026-09-22 KST 서비스롤 읽기 전용 SELECT. 공유 그룹 멤버는 자기 맥의 계정 스냅샷 시점이 달라 수치가 시간마다 흔들린다.)
///
/// 비율만 받아 클라가 다시 계산하는 길은 **닫혀 있다**. 서버 `codex_effective` 에는
///   (a) `offline_local` — 미로그인 기기 몫
///   (b) `tail_factor`   — 스냅샷 노후·과다계상 축소율
///   (c) `group_bucket`  — 그룹 멤버 버킷의 max 로 하는 일별 화해
/// 이 들어간다(20260917160000:640-800). 셋 다 **남의 기기·남의 스냅샷**을 봐야 나오는 값이라 이 맥은 원리적으로 못 맞춘다.
/// 그래서 서버가 준 숫자를 그대로 그린다.
package struct TokenRowServerValue: Codable, Equatable, Sendable {
    package let userID: String
    /// 'YYYY-MM'(KST). 이 값이 곧 유효 범위다 — 다른 달이면 팝오버가 쓰지 않는다.
    package let month: String
    /// 서버 total = `claude_total + codex_effective + antigravity_total`(20260917160000:817).
    package let total: Int
    package let claudeTotal: Int
    package let codexEffective: Int
    /// 잔차(`TokenBoardEntry.antigravityEffective`). 툴팁을 순위판 카드와 **글자 하나 다르지 않게** 만들기 위해 담는다.
    package let antigravityEffective: Int
    /// 보드 출력 14번째 칸 `codex_account_month` = `e.codex_account_share`(20260917160000:809) — **이미 나눈 내 몫**이다.
    /// 옛 표가 이긴 행(prefer_device = false)이면 서버가 null 을 준다 → nil.
    package let codexAccountShare: Int?
    package let fetchedAt: Date

    /// 보드 엔트리에서 만든다.
    ///
    /// ⚠️ **서버가 `codex_effective` 를 안 준 행(옛 RPC)은 만들지 않는다.** 그때 엔트리의 `codexEffective` 는
    /// `SupabaseWorkModels.swift` 의 `max(로컬, 계정)` 미러인데, 그 max 는 이 프로젝트가 명시적으로 폐기한
    /// 증폭기다(CodexEffectiveRule 머리 주석 — 포크 복사본으로 부푼 쪽을 정확히 고른다). 개인 표시가 거기로
    /// 떨어지면 안 된다. 이 guard 하나가 "서버를 롤백하면 팝오버가 분배 전 값으로 돌아간다"를 구조적으로 막는다.
    package init?(entry: TokenBoardEntry, month: String, fetchedAt: Date) {
        guard entry.hasServerCodexEffective else { return nil }
        userID = entry.userID
        self.month = month
        total = entry.total
        claudeTotal = entry.claudeTotal
        codexEffective = entry.codexEffective
        antigravityEffective = entry.antigravityEffective
        codexAccountShare = entry.codexAccountMonth
        self.fetchedAt = fetchedAt
    }

    /// 순위판 카드 툴팁(`TokenBoardEntry.detailTooltip`)과 **같은 조립**이다 — 같은 숫자를 두 어휘로 부르지 않는다.
    /// 0 인 종류는 줄을 만들지 않는다(그쪽 규약 그대로). 셋의 합 == `total` 이라 검산 가능한 불변식이 여기서도 성립한다.
    package var detailTooltip: String {
        var parts: [String] = []
        if claudeTotal > 0 { parts.append("Claude \(TokenNumberFormatter.grouped(claudeTotal))") }
        if codexEffective > 0 { parts.append("Codex \(TokenNumberFormatter.grouped(codexEffective))") }
        if antigravityEffective > 0 { parts.append("안티그래비티 \(TokenNumberFormatter.grouped(antigravityEffective))") }
        return parts.joined(separator: " · ")
    }

    /// 'YYYY-MM' 뒤 두 자리를 정수로(선행 0 제거). `TokenUsageMonthly.monthNumber` 와 같은 규약.
    package var monthNumber: Int { Int(month.split(separator: "-").last ?? "") ?? 0 }
}

/// 팝오버 행이 실제로 그릴 것. `nil` 은 "그릴 것이 없다"는 뜻이고, 그 판정도 `TokenRowDisplayRule.resolve` 가 한다.
package struct TokenRowDisplay: Equatable, Sendable {
    package let total: Int
    package let tooltip: String
    package let monthNumber: Int
    /// 테스트·디버그용. **화면에는 이 사실을 표시하지 않는다**(2026-09-22 사용자 결정: 숫자가 내려가는 11명에게
    /// 앱 내 안내를 넣지 않는다 — "따로 표시할 필요없을듯").
    package let isFromServer: Bool

    package init(total: Int, tooltip: String, monthNumber: Int, isFromServer: Bool) {
        self.total = total
        self.tooltip = tooltip
        self.monthNumber = monthNumber
        self.isFromServer = isFromServer
    }
}

/// 팝오버 토큰 행이 **무엇을 그릴지** 정하는 단 하나의 규칙.
package enum TokenRowDisplayRule {
    /// 값·툴팁·렌더 게이트가 전부 여기 하나에서 나온다. nil = 그릴 것이 없다(뷰는 순위판 진입 행 또는 EmptyView).
    ///
    /// 규칙(이 순서):
    ///  1. 서버 행이 **내 것**이고 **이번 달**이고 **total > 0** 이면 → 서버 행을 그대로 그린다.
    ///     · `total > 0` 의 뜻: 0 은 '서버의 답'이 아니라 '아직 업로드가 안 닿은 행'이다(보드 merged 가 coalesce 0 을 쓴다).
    ///       0 을 표시로 읽으면 첫 설치 사용자의 행이 0 으로 굳는다. 이건 max 폴백이 아니라 '부재를 부재로 읽는' 것뿐이다.
    ///     · **낡음을 이유로 로컬로 되돌아가지 않는다.** fetchedAt 이 몇 시간 전이어도 서버값을 유지한다 —
    ///       낡았다고 큰 쪽/신선한 쪽으로 갈아타면 그게 곧 폐기된 max 증폭기의 재발명이고, 두 화면이 다시 갈린다.
    ///  2. 그 외에는 오늘 경로 그대로(로컬 산식). 오늘의 렌더 게이트를 그대로 승계한다.
    ///  3. 로컬도 서버도 없으면 nil.
    package static func resolve(
        local: TokenUsageMonthly?,
        account: CodexAccountUsage?,
        server: TokenRowServerValue?,
        userID: String?,
        currentMonth: String
    ) -> TokenRowDisplay? {
        if let server, let userID, server.userID == userID, server.month == currentMonth, server.total > 0 {
            return TokenRowDisplay(
                total: server.total,
                tooltip: server.detailTooltip,
                monthNumber: server.monthNumber,
                isFromServer: true
            )
        }
        guard let local else { return nil }
        // 오늘의 게이트를 글자 그대로 승계한다(CheckTokenUsageRow 의 옛 조건): 로컬 총합·계정 월합·안티그래비티 중
        // 하나라도 있으면 그린다. 게이트는 짝으로 있어야 한다 — 표시 산식이 계정값을 쓰는데 이 가드가 로컬 0 을 막으면
        // `.zst` 만 남은 채 설치한 사람에게 아무것도 안 보인다.
        guard local.total > 0 || (account?.monthTotal(local.month) ?? 0) > 0 || local.antigravityTotal > 0 else {
            return nil
        }
        return TokenRowDisplay(
            total: local.displayTotal(account: account),
            tooltip: local.detailTooltip(account: account),
            monthNumber: local.monthNumber,
            isFromServer: false
        )
    }

    /// 잔디용 **계정 버킷 축소 비율**. 기본 1.0(= 오늘과 산술적으로 완전히 동일).
    ///
    /// 분모가 **이 맥의 계정 월합**인 것이 핵심이다. 서버의 진짜 share_ratio(= 내 fork_safe 로컬 ÷ 그룹 로컬 합)는
    /// 분모가 그룹 max 스냅샷이라 이 맥의 버킷에 곱하면 맞지 않는다. '내 몫 ÷ 이 맥이 본 계정 월합' 을 이 맥의 버킷에
    /// 곱해야 잔디의 이번 달 Codex 합이 정확히 내 몫이 된다.
    ///
    /// · 비공유 사용자는 서버 몫 = 계정값이라 비율이 **정확히 1.0** → 잔디 산술 무변화(우연이 아니라 구조).
    ///   2026-09-22 실측으로 확인: 계정이 있는 비공유 사용자 전원(기기 15대)에서 개인 산식 − 보드 total = 0.
    /// · **상한 1.0 클램프**: 그룹 월합은 멤버 중 **가장 최신 스냅샷**이라 내 몫이 이 맥이 본 계정 월합을 넘을 수 있다
    ///   (2026-09-22 실측: '수 빈' 은 이 맥의 계정 월합 667,859,401 인데 서버 몫이 1,164,288,567 — 비율 1.74).
    ///   클램프가 없으면 그 사람 잔디가 통째로 밝아진다. **이 맥이 관측하지 않은 사용량을 잔디에 그리지 않는다.**
    /// · 하한 0.0 과 `whole > 0` 가드가 0 나눗셈·음수를 막는다.
    /// · 옛 표가 이긴 행은 `codexAccountShare == nil` → 1.0(잔디 무변화).
    package static func accountShareRatio(
        server: TokenRowServerValue?,
        account: CodexAccountUsage?,
        currentMonth: String
    ) -> Double {
        guard let server, server.month == currentMonth, let share = server.codexAccountShare,
              let whole = account?.monthTotal(currentMonth), whole > 0
        else { return 1.0 }
        return min(1.0, max(0.0, Double(share) / Double(whole)))
    }

    /// 계정 버킷 하나를 비율로 줄인다. 서버의 `round(... * share_ratio)`(20260917160000:723) 과 같은 반올림.
    /// 비율 1.0 이면 항등이다(`Double(x).rounded()` 는 Int 범위에서 x 를 그대로 돌려준다) — 비공유 사용자의 잔디가
    /// 이 변경 전과 **한 칸도 다르지 않다**는 것이 이 항등에서 온다.
    package static func scaledAccountBucket(_ value: Int, ratio: Double) -> Int {
        guard ratio < 1.0 else { return value }
        return Int((Double(value) * ratio).rounded())
    }
}
