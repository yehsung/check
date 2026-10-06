import CheckCore
import Foundation

// MARK: - 폰의 AI 리밋 읽기 (ai_limits 표 · v0.3.45)
//
// 폰은 이 축에서 **읽기만** 한다. 자격증명을 읽는 쪽은 맥 하나뿐이고(2026-10-07 사용자 결정 — Anthropic 이
// 2026-02 약관으로 소비자 OAuth 토큰의 타사 사용을 금지했고 실제 차단을 집행했다), 폰이 제공자 API 를 직접
// 부르는 길은 아예 만들지 않는다. 그래서 여기 있는 것은 GET 하나다.
//
// ## RPC 가 아니라 표를 직접 읽는 까닭
// 서버 마이그레이션(20261007120000_ai_limits.sql)은 `ai_limits` 를 **본문에서 읽는 함수·뷰를 0개로 못 박았다**
// (§5⑦) — 순위판 RPC 에 이 표가 섞이는 길을 서버가 구조적으로 막는다. 읽기는 RLS(`user_id = auth.uid()`)로
// 본인 행만 열려 있으므로 PostgREST 직접 조회가 맞는 모양이다.
//
// ## `select` 에 쓸 칸만 적는다
// `device_id` 는 받지 않는다 — 기기를 **고르는** 데는 `observed_at` 만 쓰고(가장 최신 행), 기기 식별자는
// 화면에 쓸 일이 없다. `account_fingerprint` 도 받지 않는다: 해시라도 폰 화면에 쓰임이 없는 값이다
// (맥 두 대가 같은 계정인지 판정하는 데만 쓰고 그 판정은 맥이 한다).
//
// ## 날짜는 두 모양이 섞여 온다
// Supabase timestamptz 는 소수초가 있는 것과 없는 것이 **한 응답에 섞인다**(저장소 관례 —
// `SupabaseWorkService.parseDate` 가 그래서 두 포매터를 순서대로 쓴다). 포매터 한 벌로 읽으면 반드시 한쪽을
// nil 로 떨구고, 그러면 리셋 시각이 조용히 사라진 카드가 된다. 그래서 문자열로 받아 `parseDate` 로 푼다.

/// `ai_limits` 한 행(폰이 읽는 칸만). 액터 안에서 `Date` 로 푼 뒤 밖으로 나간다.
struct AILimitServerRow: Decodable, Equatable, Sendable {
    let provider: String
    let fiveHourPercent: Double?
    let fiveHourResetsAt: String?
    let weeklyPercent: Double?
    let weeklyResetsAt: String?
    let planLabel: String?
    let observedAt: String
}

/// 파싱까지 끝난 행. 스토어는 이 값만 본다.
package struct AILimitFetchedRow: Equatable, Sendable {
    package let provider: String
    package let fiveHourPercent: Double?
    package let fiveHourResetsAt: Date?
    package let weeklyPercent: Double?
    package let weeklyResetsAt: Date?
    package let planLabel: String?
    package let observedAt: Date

    package init(
        provider: String,
        fiveHourPercent: Double?,
        fiveHourResetsAt: Date?,
        weeklyPercent: Double?,
        weeklyResetsAt: Date?,
        planLabel: String?,
        observedAt: Date
    ) {
        self.provider = provider
        self.fiveHourPercent = fiveHourPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.planLabel = planLabel
        self.observedAt = observedAt
    }
}

extension SupabaseWorkService {
    /// 내 리밋 행 전부(제공자 × 기기). 고르는 일(제공자당 가장 최신 행)은 스토어가 한다 — 서버 정렬을 믿지 않는다.
    ///
    /// `observed_at` 을 못 읽은 행은 **버린다**: 신선도 축이 그 값 하나로 서 있어서, 없으면 그 행으로는 아무 말도
    /// 할 수 없다(0% 로 지어내면 "하나도 안 썼다"는 단정이 된다).
    package func fetchMyAILimits(accessToken: String, userID: String) async throws -> [AILimitFetchedRow] {
        let data = try await send(
            path: Self.aiLimitsPath,
            method: "GET",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "provider,five_hour_percent,five_hour_resets_at,weekly_percent,weekly_resets_at,plan_label,observed_at"
                ),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "order", value: "observed_at.desc"),
                // 제공자 3 × 맥 몇 대. 넉넉히 두되 상한은 둔다(무료 플랜 — 응답이 커질 길을 열지 않는다).
                URLQueryItem(name: "limit", value: "60")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([AILimitServerRow].self, from: data)
        return rows.compactMap { row in
            guard let observed = parseDate(row.observedAt) else { return nil }
            return AILimitFetchedRow(
                provider: row.provider,
                fiveHourPercent: row.fiveHourPercent,
                fiveHourResetsAt: row.fiveHourResetsAt.flatMap(parseDate),
                weeklyPercent: row.weeklyPercent,
                weeklyResetsAt: row.weeklyResetsAt.flatMap(parseDate),
                planLabel: AILimitPlanLabelContract.normalized(row.planLabel),
                observedAt: observed
            )
        }
    }
}
