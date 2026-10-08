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
// `account_fingerprint` 는 받지 않는다: 해시라도 폰 화면에 쓰임이 없는 값이다(맥 두 대가 같은 계정인지
// 판정하는 데만 쓰고 그 판정은 맥이 한다).
//
// ## ★ `device_id`·`device_label` 은 **받는다** (v0.3.47 — 기기 축)
// 0.3.46 까지는 둘 다 받지 않았고, 주석은 "기기 식별자는 화면에 쓸 일이 없다"고 적었다. **그 문장이 결함의
// 뿌리였다.** 서버 PK 는 `(user_id, device_id, provider)` 라 행이 이미 기기별인데, 폰은 기기 칸을 안 받아
// "제공자당 가장 최신 행 하나"로 접을 수밖에 없었다. 그 접기가 두 가지 거짓을 만들었다:
//  ① 맥 A 에서 끈 제공자가 맥 B 의 더 새로운 행에 밀려 **폰에 되살아난다**(한 대에서 끌 방법이 없었다).
//  ② 두 맥이 다른 값을 보고해도 화면이 **누구 값인지 말하지 않는다**.
// 숨기는 대신 드러내면 둘 다 사라진다 — "껐는데 되살아났다"가 "저건 다른 맥 것"이 된다.
//
// ★ **이 `select` 는 `device_label` 칸이 있는 서버를 요구한다**(`20261008120000_ai_limits_devices.sql`).
//   없는 칸을 적으면 PostgREST 가 400 으로 응답 전체를 거절한다 → 리밋 카드가 통째로 빈다. 그래서 이 코드는
//   그 마이그레이션이 올라간 **뒤에** 나가는 빌드에만 들어간다(iOS 1.0.4/build 14 는 심사 중이고 이 코드가
//   없다). 맥의 `fetchAILimitDevices` 도 같은 칸을 같은 조건으로 읽는다.
//
// ## 날짜는 두 모양이 섞여 온다
// Supabase timestamptz 는 소수초가 있는 것과 없는 것이 **한 응답에 섞인다**(저장소 관례 —
// `SupabaseWorkService.parseDate` 가 그래서 두 포매터를 순서대로 쓴다). 포매터 한 벌로 읽으면 반드시 한쪽을
// nil 로 떨구고, 그러면 리셋 시각이 조용히 사라진 카드가 된다. 그래서 문자열로 받아 `parseDate` 로 푼다.

/// `ai_limits` 한 행(폰이 읽는 칸만). 액터 안에서 `Date` 로 푼 뒤 밖으로 나간다.
struct AILimitServerRow: Decodable, Equatable, Sendable {
    /// 이 행을 올린 맥(PK 의 한 칸이라 서버에서는 NOT NULL 이다). **옵셔널로 받는다** — 어느 날 이 칸이
    /// 응답에서 빠져도 디코드가 통째로 죽지 않게(그러면 카드가 비고, '맥이 없다'와 구별되지 않는다).
    let deviceId: String?
    /// 그 맥의 컴퓨터 이름. nil = 아직 이름을 올린 적 없는 맥(v0.3.46 이하 빌드가 남긴 행).
    let deviceLabel: String?
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
    /// 이 행을 올린 맥. **기본값이 없다** — 모든 행은 어느 맥의 것이고, 이 축이 비면 기기별 묶기가
    /// 조용히 한 묶음으로 접힌다(= 되살리려던 그 결함이 돌아온다). 기기 신원을 지어내지 않는다.
    package let deviceID: String
    /// 그 맥의 컴퓨터 이름(없으면 nil → 묶음 머리는 `이름 모를 맥 ABCD`).
    package let deviceLabel: String?
    package let provider: String
    package let fiveHourPercent: Double?
    package let fiveHourResetsAt: Date?
    package let weeklyPercent: Double?
    package let weeklyResetsAt: Date?
    package let planLabel: String?
    package let observedAt: Date

    package init(
        deviceID: String,
        deviceLabel: String? = nil,
        provider: String,
        fiveHourPercent: Double?,
        fiveHourResetsAt: Date?,
        weeklyPercent: Double?,
        weeklyResetsAt: Date?,
        planLabel: String?,
        observedAt: Date
    ) {
        self.deviceID = deviceID
        self.deviceLabel = deviceLabel
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
    /// 내 리밋 행 전부(제공자 × 기기). 묶는 일(기기별 · 기기 안에서 제공자별)은 스토어가 한다 —
    /// 서버 정렬을 믿지 않는다.
    ///
    /// 버리는 행 둘:
    ///  · `observed_at` 을 못 읽은 행 — 신선도 축이 그 값 하나로 서 있어서, 없으면 그 행으로는 아무 말도 할 수
    ///    없다(0% 로 지어내면 "하나도 안 썼다"는 단정이 된다).
    ///  · `device_id` 가 빈 행 — **어느 맥의 것인지 모르는 값**이다. 이제 화면의 묶음 단위가 기기이므로
    ///    귀속 없는 행은 둘 곳이 없고, 억지로 한 묶음에 몰면 그게 바로 v0.3.46 의 결함(맥들을 섞기)이다.
    ///    서버에서는 PK 칸이라 NOT NULL 이므로 이 갈래는 응답이 망가진 경우뿐이다.
    package func fetchMyAILimits(accessToken: String, userID: String) async throws -> [AILimitFetchedRow] {
        let data = try await send(
            path: Self.aiLimitsPath,
            method: "GET",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "device_id,device_label,provider,five_hour_percent,five_hour_resets_at,weekly_percent,weekly_resets_at,plan_label,observed_at"
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
            let deviceID = (row.deviceId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !deviceID.isEmpty else { return nil }
            return AILimitFetchedRow(
                deviceID: deviceID,
                // 이름은 **올리는 쪽과 같은 규약**으로 접는다(`AILimitDeviceLabelContract`) — 공백뿐이면 없는
                // 것으로, 상한을 넘으면 잘라서. 읽는 쪽이 그 규약을 안 지나면 서버가 거절할 글자를 화면에 적는다.
                deviceLabel: AILimitDeviceLabelContract.normalized(row.deviceLabel),
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
