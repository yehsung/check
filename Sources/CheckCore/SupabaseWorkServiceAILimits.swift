import Foundation

// MARK: - AI 리밋 업로드 (ai_limits 표 · v0.3.45)
//
// 기존 토큰 업로드(`upsertTokenUsage` · `upsertTokenUsageDaily`)와 **같은 모양**이다: PostgREST upsert ·
// `on_conflict` 는 PK · `Prefer: resolution=merge-duplicates,return=minimal`.
// 다른 점은 표가 다르다는 것 하나다 — 토큰 축 표(token_usage_*)는 이 파일이 **한 줄도 건드리지 않는다.**
//
// ## ★ PGRST102 — 이 파일이 존재하는 가장 큰 이유
// PostgREST 는 배열 본문의 **키 집합이 행마다 다르면** 스키마를 보기도 전에 400 PGRST102
// ("All object keys must match")로 **본문 전체**를 거절한다(프로덕션 14.5 실측, v0.2.41 사고).
// 그리고 400 은 호출측이 조용히 삼키므로, 그 사람의 행은 **영원히 한 줄도 올라가지 않고** 장부도 갱신되지
// 않아 다음 주기가 같은 혼합 본문을 다시 보낸다 — 영구 고착이다.
//
// 이 축에서 그 혼합은 **반드시** 생긴다: Claude 는 두 창이 다 오지만 Codex 는 창이 null 일 수 있고
// (크레딧 사용자) 플랜 라벨도 제공자마다 있고 없다. Swift 가 합성한 `Encodable` 은 nil 옵셔널의
// 키를 **생략하므로**(`encodeIfPresent`), 그냥 두면 제공자마다 다른 키 집합이 한 요청에 섞인다.
//
// 그래서 이 파일은 `AILimitUpsertRow` 의 `encode(to:)` 를 **손으로 쓴다**: 아홉 칸 전부를 `encode(_:forKey:)`
// 로 넣어 nil 을 **명시적 null 로** 내보낸다. 키 집합이 모든 행에서 같아지므로 묶음 나누기가 필요 없다
// (일별 토큰 표는 "빠진 키는 갱신하지 않는다"가 요건이라 묶음을 나눠야 했지만, 이 표는 반대다 — 창이
// 사라졌으면 서버도 null 이 되어야 한다. 그래서 명시적 null 이 **정답**이고 PGRST102 도 같이 사라진다).
//
// ## ★ 계정 지문(`account_fingerprint`)은 **본문에 싣지 않는다** (v0.3.45 P1)
// 공개 처리방침(`docs/privacy.md` "AI 사용량 리밋을 읽는 방법")은 "**계정 식별자는 올리지 않는다**"를
// 단정한다 — 그 문서는 공개 URL 로 가입 화면·App Store 에 걸린다. 초안은 그 약속과 어긋나게
// 계정 식별자의 SHA-256 앞 16자를 실어 보냈다.
//
// 그 칸을 **지운** 근거는 "해시라서 괜찮다"가 아니라 **쓰임이 없다**는 것이다(전수 grep):
// 만들고(`AILimitFingerprint.make`) 운반할 뿐, 서버에서 **소비·표시·비교하는 호출부가 0건**이다.
// 폰은 일부러 안 받아 오고(`MeAILimitsService`), 서버 정책·RPC 도 그 칸을 읽지 않는다.
// 선언된 목적("맥 두 대가 같은 계정을 보는지 판정")을 구현한 코드가 없으므로, 쓰임 없는 파생 식별자를
// 계속 올릴 이유가 없다.
//
// ★ 지문 **생성 자체는 남는다**: 업로드 게이트(`AILimitUploadLedger.fingerprint`)가 "무엇이 바뀌었나"를
//   재는 로컬 비교에 쓴다 — 그 문자열은 **이 맥을 벗어나지 않는다**. 여기서 끊는 것은 네트워크로 가는 쪽뿐이다.
// ★ 서버 컬럼·마이그레이션은 **건드리지 않는다**(검증된 nullable 칸이다). 안 보내면 null 로 남는다.
//
// ## 하트비트에 새 칸을 싣지 않는다
// `sendTokenScanHeartbeat` 의 본문은 다섯 칸뿐이고 이 파일은 그 함수를 만지지 않는다. 리밋 값을 거기 얹으면
// 하트비트가 토큰 누적치를 미는 그 사고(그 함수 주석)의 쌍둥이가 생긴다.
//
// ## `updated_at` 을 보내지 않는다
// 서버 터치 트리거가 insert·update 양쪽에서 덮는다(마이그레이션 §5⑦). 클라가 보내면 버려지고,
// `observed_at` 은 반대로 **클라 값이 그대로 남아야 한다**(신선도 축이 그 값이다) — 그래서 그 칸은 반드시 싣는다.

/// `ai_limits` 한 행. **모든 옵셔널이 명시적 null 로 나간다**(머리말 PGRST102).
package struct AILimitUpsertRow: Encodable, Equatable, Sendable {
    package let userId: String
    package let deviceId: String
    package let provider: String
    package let fiveHourPercent: Double?
    package let fiveHourResetsAt: String?
    package let weeklyPercent: Double?
    package let weeklyResetsAt: String?
    package let planLabel: String?
    package let observedAt: String

    /// 본문 키. **이 집합이 모든 행에서 같다는 것이 계약이다**(테스트가 되묻는다).
    package enum CodingKeys: String, CodingKey, CaseIterable {
        case userId = "user_id"
        case deviceId = "device_id"
        case provider
        case fiveHourPercent = "five_hour_percent"
        case fiveHourResetsAt = "five_hour_resets_at"
        case weeklyPercent = "weekly_percent"
        case weeklyResetsAt = "weekly_resets_at"
        case planLabel = "plan_label"
        case observedAt = "observed_at"
    }

    package init(
        userId: String,
        deviceId: String,
        provider: String,
        fiveHourPercent: Double?,
        fiveHourResetsAt: String?,
        weeklyPercent: Double?,
        weeklyResetsAt: String?,
        planLabel: String?,
        observedAt: String
    ) {
        self.userId = userId
        self.deviceId = deviceId
        self.provider = provider
        self.fiveHourPercent = fiveHourPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.planLabel = planLabel
        self.observedAt = observedAt
    }

    /// ★ **합성 인코더를 쓰지 않는다.** 합성 코드는 nil 옵셔널 키를 생략하므로(`encodeIfPresent`) 제공자마다
    /// 키 집합이 달라지고, 그 본문은 PostgREST 가 400 PGRST102 로 **통째로** 거절한다(머리말).
    /// `encode(_:forKey:)` 는 nil 을 `null` 로 적는다 — 그게 이 손글씨의 전부이고 이유다.
    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(provider, forKey: .provider)
        try container.encode(fiveHourPercent, forKey: .fiveHourPercent)
        try container.encode(fiveHourResetsAt, forKey: .fiveHourResetsAt)
        try container.encode(weeklyPercent, forKey: .weeklyPercent)
        try container.encode(weeklyResetsAt, forKey: .weeklyResetsAt)
        try container.encode(planLabel, forKey: .planLabel)
        try container.encode(observedAt, forKey: .observedAt)
    }
}

extension SupabaseWorkService {
    package static let aiLimitsPath = "/rest/v1/ai_limits"
    /// PK 그대로. 맥 두 대가 같은 계정을 읽어도 서로를 덮지 않는다(기기별 행).
    package static let aiLimitsConflictKey = "user_id,device_id,provider"

    /// 서버 CHECK(0…100)에 맞게 퍼센트를 다듬는다. **NaN·무한은 버린다**(nil).
    ///
    /// 왜 클라에서 막는가: NaN 이 들어가면 PostgREST 가 JSON 이 아닌 `NaN` 을 내려보내고, 그러면 폰의 응답
    /// 파싱이 **세 제공자 모두 통째로** 깨진다(마이그레이션 머리말). 100.0000001 도 23514 로 그 행이 통째로
    /// 거절된다 — 거절은 조용하다.
    package static func aiLimitPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(100, max(0, value))
    }

    /// 제공자 스냅샷 하나를 행 하나로. 창이 하나도 없으면 nil(= 올릴 말이 없다).
    package func aiLimitRow(
        userID: String,
        deviceID: String,
        snapshot: AILimitProviderSnapshot
    ) -> AILimitUpsertRow? {
        guard snapshot.isLinked else { return nil }
        let fiveHour = snapshot.window(.fiveHour)
        let weekly = snapshot.window(.weekly)
        // `observed_at` 은 **리더가 응답을 받은 시각**이다(서버 기본값이 없다 — 안 보내면 23502 로 크게 실패한다).
        // 창이 둘이면 더 최근 쪽을 쓴다: 두 창은 한 응답에서 왔으므로 실제로는 같은 값이다.
        guard let observed = snapshot.latestObservedAt else { return nil }
        return AILimitUpsertRow(
            userId: userID,
            deviceId: deviceID,
            provider: snapshot.provider.rawValue,
            fiveHourPercent: Self.aiLimitPercent(fiveHour?.usedPercent),
            fiveHourResetsAt: fiveHour?.resetsAt.map { dateFormatter.string(from: $0) },
            weeklyPercent: Self.aiLimitPercent(weekly?.usedPercent),
            weeklyResetsAt: weekly?.resetsAt.map { dateFormatter.string(from: $0) },
            planLabel: AILimitPlanLabelContract.normalized(snapshot.planLabel),
            // ★ `snapshot.accountFingerprint` 는 **의도적으로 싣지 않는다**(머리말) — 그 값은 업로드 게이트의
            //   로컬 비교에만 쓰이고 네트워크로 가지 않는다. 서버 컬럼은 nullable 이라 null 로 남는다.
            observedAt: dateFormatter.string(from: observed)
        )
    }

    /// 내 리밋 행들을 올린다(제공자당 한 행). 빈 배열이면 **요청을 아예 보내지 않는다**.
    ///
    /// 실패는 호출측이 삼키고 장부를 갱신하지 않아 다음 주기에 재시도한다(upsert 는 멱등이다).
    package func upsertAILimits(
        accessToken: String,
        userID: String,
        deviceID: String,
        bundle: AILimitSnapshotBundle
    ) async throws {
        let rows = bundle.visibleProviders.compactMap {
            aiLimitRow(userID: userID, deviceID: deviceID, snapshot: $0)
        }
        guard !rows.isEmpty else { return }
        try await sendNoBody(
            path: Self.aiLimitsPath,
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: Self.aiLimitsConflictKey)],
            body: rows,
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }
}

/// 플랜 라벨의 단 하나의 규칙(1…32자). 리더와 업로드가 **같은 함수**를 부른다 — 두 벌이 되면
/// 리더가 통과시킨 라벨이 업로드에서 거절되는 조합이 생기고, 그 거절은 조용하다
/// (서버 CHECK 가 23514 로 그 행을 통째로 버린다).
///
/// 길이 상한이 서버에 있는 이유는 **그 칸이 화면에 그대로 적히는 값**이기 때문이다 — 제공자가 어느 날
/// 문장을 돌려주면 카드가 터진다. 넘치면 **버린다**(잘라서 뜻이 반쯤 남은 라벨보다 없는 쪽이 정직하다).
/// 이 파일(플랫폼 무관)에 두는 이유는 폰·위젯 쪽도 같은 값을 읽기 때문이다.
package enum AILimitPlanLabelContract {
    package static let maxLength = 32

    package static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}
