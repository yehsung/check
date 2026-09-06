import Foundation

// MARK: - Codex 유효 사용량 규칙 (계정 우선 · 미반영 꼬리만 로컬)

/// Codex 토큰의 **표시값**을 정하는 단 하나의 규칙. 순위판 RPC(`token_usage_board`, 20260906120000)·내 박스 총합
/// (`TokenUsageDisplay.effectiveTotal`)·토큰 잔디(`TokenDailyMerge`)·툴팁이 전부 이 타입을 부른다 — 서버 SQL 과 이 Swift 가
/// 같은 픽스처에서 같은 답을 내는지 테스트(V0243AccountFirstTests)가 고정한다.
///
/// 왜 `max(로컬, 계정)` 을 버렸나(2026-09-06 실측): Codex CLI 는 스레드를 포크할 때(서브에이전트·thread/fork·review) 부모
/// rollout 의 `token_count` 이벤트를 새 파일에 **통째로 복사**한다. 파일별 차분 스캐너는 그 복사본을 새 소비로 세어
/// 제보자 계정에서 로컬이 계정의 4.64배(225억 vs 48.5억), 다른 한 명은 3.43배로 부풀었고, `greatest(로컬, 계정)` 은
/// 정확히 그 부풀린 쪽을 골라 순위판 1·2위에 올렸다. max 는 어느 쪽이 부풀든 그것을 고르는 증폭기다.
///
/// 규칙(사용자·월 단위):
/// ```
/// 계정 월합이 없다(nil)            → 로컬 월합                       (계정 없음 — 미로그인·구버전·프로브 실패)
/// 계정 월합은 있는데 이 달 버킷이 없다 → 로컬 월합                       (전부 미반영 꼬리)
/// 그 외                            → 계정 월합
///                                   + Σ_{day > lastDay} 로컬[day]                          (아직 버킷이 없는 날은 로컬)
///                                   + max(0, 로컬[lastDay] − 버킷[lastDay])                 (마지막 버킷은 배치 반영 중인 부분값)
/// ```
/// 계정이 반영된 날짜(lastDay 앞)에는 로컬을 **쓰지 않는다** — 로컬이 더 커도 갈아타지 않는다.
///
/// 날짜 키: 로컬은 KST 일자, 계정 버킷은 UTC 일자인데 같은 문자열 키로 맞춘다(경계 9시간 차 — 월간 순위와 같은 문서화된 미결,
/// `TokenDailyMerge.localTotals` 주석). 고정폭 'YYYY-MM-DD' 라 사전식 비교가 곧 날짜 비교다.
enum CodexEffectiveRule {
    /// 로컬이 계정보다 이 배수 넘게 크면 "포크 복사본 의심" 으로 본다(서버 진단 `token_scan_health` 의 1.2 와 같은 문턱 —
    /// 계정 버킷은 몇 시간 늦게 배치로 반영되므로 당일·최근분만큼 로컬이 앞서는 것은 정상이고, 그 정상 창을 결함으로 읽지 않는 여유).
    static let overcountRatio = 1.2

    // 진단 문구("로컬 집계가 계정보다 큼(포크 복사본 의심)")는 v0.2.45 에 UI 에서 걷어냈다 — 운영자 진단은 서버 token_scan_health 가 낸다.

    /// 로컬 월합이 계정 월합보다 `overcountRatio` 배 넘게 큰가. 계정이 없거나 0 이면 비교 대상이 아니라 false.
    static func localExceedsAccount(local: Int, account: Int?) -> Bool {
        guard let account, account > 0 else { return false }
        return Double(local) > Double(account) * overcountRatio
    }

    /// 월 단위 유효 Codex 토큰.
    /// - localMonth: 로컬 월합(입력+출력, 기기 합).
    /// - localDaily: 로컬 일별 맵(KST 'YYYY-MM-DD' → 입력+출력 델타, 기기 합). 꼬리 계산에만 쓴다.
    /// - accountMonth: 계정 월합(기기 간 max). nil = 계정 없음.
    /// - accountLastDay: **이 달 안의** 마지막 계정 버킷 날짜(`CodexAccountUsage.latestBucketDate(in:)` / 월 표 `codex_account_last_day`).
    ///   nil = 이 달 버킷이 하나도 없다.
    /// - accountBucketOnLastDay: 그 날짜의 계정 버킷. nil 은 0 으로 본다.
    static func month(
        localMonth: Int,
        localDaily: [String: Int],
        accountMonth: Int?,
        accountLastDay: String?,
        accountBucketOnLastDay: Int?
    ) -> Int {
        let local = max(0, localMonth)
        guard let accountMonth, let lastDay = accountLastDay else { return local }
        var effective = max(0, accountMonth)
        for (day, tokens) in localDaily where day > lastDay {
            effective += max(0, tokens)
        }
        effective += max(0, max(0, localDaily[lastDay] ?? 0) - max(0, accountBucketOnLastDay ?? 0))
        return effective
    }

    /// 하루 단위 유효 Codex 토큰(잔디 칸). 같은 규칙을 하루에 적용한 것이다.
    /// - accountLastDay: 마지막 계정 버킷 날짜(잔디는 달을 가르지 않으므로 **전 기간** 최신 버킷 — `latestBucketDate`).
    ///   nil = 계정 없음 → 로컬.
    /// - day < lastDay: 계정 버킷(없으면 0 — 그 날 계정에 사용이 없다는 뜻이고, 로컬이 있어도 쓰지 않는다).
    /// - day == lastDay: max(버킷, 로컬) — 마지막 버킷은 부분값.
    /// - day > lastDay: 로컬.
    static func day(_ day: String, local: Int, accountBucket: Int?, accountLastDay: String?) -> Int {
        let local = max(0, local)
        guard let lastDay = accountLastDay else { return local }
        let bucket = max(0, accountBucket ?? 0)
        if day < lastDay { return bucket }
        if day == lastDay { return max(bucket, local) }
        return local
    }
}
