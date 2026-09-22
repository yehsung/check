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

/// 보드 응답 한 번이 스토어의 `myTokenRow` 에 시키는 일. 세 갈래뿐이고, 그 판정은
/// `TokenRowDisplayRule.outcomeForMyRow` 만이 한다.
///
/// **`.keep` 이 있는 이유**: 네트워크·서버 실패로 응답을 못 받은 것과, 응답은 받았는데 내 행이 없는 것은
/// 정반대의 사실이다. 전자를 비움으로 읽으면 비행기 모드에서 팝오버 숫자가 로컬값으로 튀고, 후자를 유지로 읽으면
/// 서버가 지운 숫자가 화면에 남는다. 스토어의 `catch` 는 이 열거값을 **아예 만들지 않는다**(= 유지).
package enum MyTokenRowOutcome: Equatable, Sendable {
    /// 서버가 내 행을 줬다 — 이 값으로 갈아끼우고 디스크에도 남긴다.
    case adopt(TokenRowServerValue)
    /// 서버는 응답했는데 **내 행이 없다** — 값·영속본을 비우고 로컬 산식으로 되돌아간다.
    case clear
    /// 지금은 판단하지 않는다 — 들고 있던 값을 그대로 둔다.
    case keep
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
        guard let server, server.month == currentMonth else { return 1.0 }
        return accountShareRatio(share: server.codexAccountShare, bucketSum: account?.monthTotal(currentMonth) ?? 0)
    }

    /// 같은 나눗셈의 **관측 분모 판**(v0.3.36 — 폰). 위 맥 판이 이 함수로 위임하므로 클램프·가드가 한 곳에만 있다.
    /// 라벨이 달라(`share:bucketSum:` vs `server:account:currentMonth:`) 호출 모호성은 없다.
    ///
    /// 폰이 이 판을 쓰는 이유: 폰에는 로컬 스캐너가 없어 맥의 분모(이 맥의 계정 월합)를 만들 수 없고, 관측 가능한 분모가
    /// 서버 일별 계정 버킷의 그 달 합(`TokenDailyMerge.accountBucketSum`)뿐이다. 분자는 맥과 같은 값
    /// (보드 14번 칸 `codex_account_month` = 이미 나눈 내 몫).
    ///
    /// · `share == nil` → 1.0(옛 표가 이긴 행·미로그인 기기). **`share == 0` 은 nil 과 다르다** — fork_safe 로컬이 0 인
    ///   그룹원의 진짜 몫 0 이므로 비율 0 으로 간다(순위판 숫자와 같은 결론). nil 로 접어 1.0 으로 올리면 그 사람 잔디에
    ///   계정 전체가 그려진다.
    /// · `bucketSum <= 0` → 1.0(0 나눗셈 가드. 분모가 0 이면 곱할 버킷도 없어 산술적으로 무변화다).
    /// · **상한 1.0 클램프**: 분자는 그룹에서 가장 최신인 남의 스냅샷에서 나오고 분모는 내가 관측한 버킷이라, 늦게 읽은
    ///   쪽이 크면 몫이 분모를 넘는다(2026-09-22 실측 '수 빈' 1.74). 클램프가 "관측한 적 없는 사용량을 잔디에 그리지
    ///   않는다"를 지키고, 덤으로 분모가 모자란 모든 실패가 비율 ≥ 1 → 클램프 → 오늘 동작으로 **안전 착지**한다
    ///   (잘못 줄이는 쪽으로는 넘어지지 않는다).
    package static func accountShareRatio(share: Int?, bucketSum: Int) -> Double {
        guard let share, bucketSum > 0 else { return 1.0 }
        return min(1.0, max(0.0, Double(share) / Double(bucketSum)))
    }

    /// 폰이 새 달의 비율을 **아직 재지 않는** 유예 일수(KST 월초). `shareRatioMonthIsYoung` 만 읽는다.
    ///
    /// 3일인 이유: 서버의 그룹 지문도 **끝난 날**만 보고(`bnd.hi = today − 2`) 2일 이상 일치를 요구한다 —
    /// 그 창이 열리기 전에는 그룹 판정 자체가 지난 달 지문에 기대고 있다. 더 늘리면 이 달에 처음 공유를 시작한
    /// 사람이 부푼 잔디를 보는 기간이 그만큼 길어져, 두 손해가 만나는 자리로 골랐다.
    package static let shareRatioGraceDays = 3

    /// 지금이 **새 달의 지분비가 아직 표본이 아닌** 구간인가(KST 월초 `shareRatioGraceDays` 일). `now` 는 스토어 시계.
    ///
    /// 왜 필요한가 — **지분비는 월중에 0 부터 다시 쌓인다**(서버 SQL): 분자 `codex_account_month` 는
    /// `round(그룹 계정 월합 × share_ratio)` 이고, 그 `share_ratio` 는 `codex_account_group()` 이 **그 달치 로컬만**
    /// (`where d.month = p_month`, `local_safe = Σ(codex_input+codex_output) filter build ≥ 52`) 모아 나눈 값이다
    /// (20260911230000:114-123·166-167). 반면 분모(일별 계정 버킷)는 그룹 **전체**의 사용이라 월초에도 곧바로 찬다.
    /// 그래서 달의 첫 며칠에는 두 극단이 확실히 난다:
    ///  · 그 달 Codex 를 아직 안 쓴 멤버 → share_ratio 0 → 비율 0 → 13주 잔디 **전체**(지난 달의 정확하던 칸까지)가
    ///    로컬 꼬리만 남고 0 으로 내려앉는다(그 0 이 defaults 에 영속된다).
    ///  · 그 달 맨 먼저 쓴 멤버 → share_ratio ≈ 1 → 몫 > 분모 → 클램프 1.0 → 잔디가 '계정 전체'(최대 19.15배)로 되부푼다.
    /// 비율 하나를 13주 창에 거는 근사(`TokenDailyMerge.serverTotals` 머리 주석)는 그 하나가 **달을 대표**할 때만
    /// 성립하는데, 월초 며칠의 지분비는 표본이 아니라 잡음이다. 이 구간에는 재지 않고(왕복도 안 쏜다) **직전에 잰 값**을
    /// 그대로 쓴다 — 공유 *관계*는 상시적이라 직전 달 비율이 새 달 첫 며칠의 잡음보다 언제나 참에 가깝다.
    /// 한 번도 못 쟀으면 1.0 = 이 수리 전 동작이다.
    ///
    /// 달을 못 읽으면 `false`(= 잰다) — 유예는 정확도를 위한 보정이지 안전 장치가 아니라, 모를 때는 종전 경로로 둔다.
    ///
    /// ⚠️ 이 유예는 **폰 전용**이다. 맥(`accountShareRatio(server:account:currentMonth:)`)도 같은 분자를 쓰니 같은
    /// 월초 잡음을 타지만, 맥 호출부는 이 릴리스에서 한 글자도 건드리지 않는다(다른 세션이 그 파일을 쓴다).
    package static func shareRatioMonthIsYoung(_ now: Date) -> Bool {
        guard let day = TeamWeeklyGoal.kstCalendar.dateComponents([.day], from: now).day else { return false }
        return day <= shareRatioGraceDays
    }

    /// 보드 응답 **한 번**이 들고 있던 내 행에 무슨 일을 해야 하는가. 스토어는 이 판정을 그대로 집행만 한다
    /// (`WorkTimerStoreSync.applyMyTokenRowOutcome`) — '행 없음'과 '조회 실패'를 가르는 규칙이 스토어의 do/catch
    /// 사이에 흩어져 있으면 테스트가 네트워크를 세우지 않고는 한 글자도 확인할 수 없다.
    ///
    /// **왜 `.clear` 가 필요한가**(2026-09-22): 토큰 수집을 끈 사람의 행은 서버가 purge 한다. 그때 보드 응답은
    /// 정상인데 내 행만 없고, 지금 코드는 조용한 no-op 이라 팝오버가 **서버에 더 이상 없는 숫자**를 계속 그렸다
    /// (같은 화면의 잔디는 비어 있어 한 화면이 두 사실을 말한다). 해당자는 2026-09 기준 1명이다.
    ///
    /// 낡음 시한(오프라인 N시간 경과 같은 것)은 **넣지 않는다**(2026-09-22 사용자 결정) — 여기 분기는 셋뿐이다.
    package static func outcomeForMyRow(
        entries: [TokenBoardEntry],
        userID: String,
        month: String,
        fetchedAt: Date
    ) -> MyTokenRowOutcome {
        // 서버가 응답했는데 내 행이 없다 = 그 숫자는 서버에 더 이상 없다. 비우고 로컬 산식으로 되돌아간다.
        guard let mine = entries.first(where: { $0.userID == userID }) else { return .clear }
        // 내 행은 왔는데 값을 만들 수 없다 = 구버전 RPC(`codex_effective` 없음)로 떨어진 서버다.
        // 이건 '행이 사라졌다'가 아니라 '이 서버가 답을 못 한다'이므로 **들고 있던 값을 지키는 쪽**이다 —
        // 비우면 공유 Codex 계정 사용자의 팝오버가 곧바로 분배 전 로컬값으로 돌아간다(이 릴리스가 고친 그 화면).
        guard let value = TokenRowServerValue(entry: mine, month: month, fetchedAt: fetchedAt) else { return .keep }
        return .adopt(value)
    }

    /// 계정 버킷 하나를 비율로 줄인다. 서버의 `round(... * share_ratio)`(20260917160000:723) 과 같은 반올림.
    /// 비율 1.0 이면 항등이다(`Double(x).rounded()` 는 Int 범위에서 x 를 그대로 돌려준다) — 비공유 사용자의 잔디가
    /// 이 변경 전과 **한 칸도 다르지 않다**는 것이 이 항등에서 온다.
    package static func scaledAccountBucket(_ value: Int, ratio: Double) -> Int {
        guard ratio < 1.0 else { return value }
        return Int((Double(value) * ratio).rounded())
    }
}
