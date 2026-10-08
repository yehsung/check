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
// ## ★ 기기 이름(`device_label`)은 **아홉 칸 옆의 열째 칸**이다 (v0.3.47)
// `(user_id, device_id, provider)` 가 PK 이므로 서버는 이미 기기별로 저장한다. 모자랐던 것은 **그 맥을 부를
// 이름**뿐이었다 — 폰이 "맥 A 와 맥 B" 를 "제공자당 최신 하나"로 접은 까닭도 가를 이름이 없었기 때문이다.
// 이름은 PK 가 아니고(이름을 바꿔도 같은 맥이다) 자격증명도 아니다(시스템 설정에 사람이 적은 그 값이다).
// ★ 키 집합은 **모든 행에서 같아야 한다**: 값 행도 비우는 행도 이 칸을 적는다(nil 이면 명시적 null).
//   한 행만 빼면 PostgREST 가 400 PGRST102 로 본문 전체를 거절하고 그 거절은 조용하다.
// ★ 처리방침(`docs/privacy.md`)의 "올라가는 것" 열거에 **기기 이름이 들어가야 한다** — 그 문장은
//   "…뿐입니다"로 끝나는 배타적 단정이라 항목이 늘면 거짓이 된다(그 문서는 다른 담당이 고친다).
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
    /// 이 맥의 컴퓨터 이름(v0.3.47). nil = 이름을 모른다(= 서버에 null 로 남는다).
    ///
    /// ★ **PK 가 아니다.** 이름을 바꿔도 같은 맥이고, 두 맥이 같은 이름이어도 다른 맥이다 —
    ///   가르는 것은 `device_id` 뿐이다. 이름은 사람이 두 줄을 알아보게 하는 라벨이다.
    package let deviceLabel: String?
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
        case deviceLabel = "device_label"
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
        deviceLabel: String? = nil,
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
        self.deviceLabel = deviceLabel
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
        try container.encode(deviceLabel, forKey: .deviceLabel)
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
        deviceLabel: String? = nil,
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
            deviceLabel: AILimitDeviceLabelContract.normalized(deviceLabel),
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

    /// 그 제공자의 행을 **비우는** 한 행(v0.3.47). 창 값·리셋 시각·플랜 라벨이 전부 null 이고 PK + `observed_at` 만 값이다.
    ///
    /// ## 왜 지우지 않고 덮는가
    /// `authenticated` 에 DELETE 를 **일부러 주지 않았다**. 그래서 클라가 자기 행을 없애는 길은 "비워서 올리기"
    /// 하나뿐이다. 폰·위젯은 **보이는 창이 하나도 없는 행을 숨기므로**(`AILimitSnapshotBundle.visibleProviders` 가
    /// `isLinked` 로 거른다 — 심사 중인 폰 빌드도 이미 그렇다) 이 한 번의 업로드로 그 제공자가 세 화면에서 같이 사라진다.
    /// ★ 3일 유령 게이트(`AILimitGhostRow`)에 기대지 않는다 — 설정을 끈 사람에게 사흘을 기다리게 할 수는 없다.
    ///
    /// ## 키 집합은 값 행과 **똑같다**
    /// `AILimitUpsertRow.encode(to:)` 가 아홉 칸을 전부 적으므로(머리말 PGRST102) 비우는 행과 값 행을 한 본문에
    /// 섞어도 400 이 나지 않는다. 그래서 요청을 둘로 나누지 않는다 — 나누면 비우기만 실패하는 조합이 생긴다.
    ///
    /// `observed_at` 은 NOT NULL 이라(안 보내면 23502 로 그 행이 조용히 거절된다) 비우는 행도 시각을 싣는다.
    /// **옛 관측 시각이 아니라 지금**이다: 이 행이 말하는 사실은 "이 제공자는 더 올리지 않는다"이고 그 시각이 지금이다.
    package func aiLimitClearingRow(
        userID: String,
        deviceID: String,
        deviceLabel: String? = nil,
        provider: AILimitProvider,
        observedAt: Date
    ) -> AILimitUpsertRow {
        AILimitUpsertRow(
            userId: userID,
            deviceId: deviceID,
            // ★ 비우는 행도 이름을 **싣는다**. 키 집합이 값 행과 글자 하나까지 같아야 하기 때문이고
            //   (머리말 PGRST102), 뜻으로도 맞다 — 그 맥은 여전히 그 맥이고 이름만 남는다.
            deviceLabel: AILimitDeviceLabelContract.normalized(deviceLabel),
            provider: provider.rawValue,
            fiveHourPercent: nil,
            fiveHourResetsAt: nil,
            weeklyPercent: nil,
            weeklyResetsAt: nil,
            planLabel: nil,
            observedAt: dateFormatter.string(from: observedAt)
        )
    }

    /// 내 리밋 행들을 올린다(제공자당 한 행). 빈 배열이면 **요청을 아예 보내지 않는다**.
    ///
    /// `clearedProviders` 는 사용자가 설정에서 **끈** 제공자다(v0.3.47) — 그 행은 값 대신 null 로 덮인다.
    ///
    /// 실패는 호출측이 삼키고 장부를 갱신하지 않아 다음 주기에 재시도한다(upsert 는 멱등이다).
    package func upsertAILimits(
        accessToken: String,
        userID: String,
        deviceID: String,
        deviceLabel: String? = nil,
        bundle: AILimitSnapshotBundle,
        clearedProviders: [AILimitProvider] = [],
        clearedAt: Date = Date()
    ) async throws {
        let valueRows = bundle.visibleProviders.compactMap {
            aiLimitRow(userID: userID, deviceID: deviceID, deviceLabel: deviceLabel, snapshot: $0)
        }
        // ★ **같은 PK 를 한 본문에 두 번 담지 않는다.** upsert 가 한 요청에서 같은 행을 두 번 건드리면
        //   Postgres 가 21000("ON CONFLICT DO UPDATE command cannot affect row a second time")으로
        //   **본문 전체**를 거절한다 — 값도 비우기도 못 올라가고, 그 거절은 조용하다. 중복 제공자도 접는다.
        let taken = Set(valueRows.map(\.provider))
        var seen = Set<AILimitProvider>()
        let clearingRows = clearedProviders
            .filter { !taken.contains($0.rawValue) && seen.insert($0).inserted }
            .map {
                aiLimitClearingRow(
                    userID: userID, deviceID: deviceID, deviceLabel: deviceLabel,
                    provider: $0, observedAt: clearedAt
                )
            }
        let rows = valueRows + clearingRows
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
        // 눈금은 **유니코드 스칼라**다 — 서버 `char_length` 가 세는 것이 그것이고, Swift `count`(자소 묶음)로
        // 재면 둘이 갈려 통과시킨 값이 23514 로 거절되는 조합이 생긴다(`AILimitDeviceLabelContract` 와 같은 근거).
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= maxLength else { return nil }
        return trimmed
    }
}

// MARK: - 내 맥 목록 + 메인 맥 (v0.3.47 · ai_limits_prefs 표)
//
// ## 왜 두 요청인가
// 기기 목록은 `ai_limits` 에, 고른 맥은 `ai_limits_prefs` 에 있다. 한 요청으로 접을 길(임베드)은
// **일부러 막혀 있다** — `main_device_id` 에 FK 를 걸지 않았고(마이그레이션 머리말: 걸면 임베드가 모호해져
// 기존 조회가 400 이 된다), 그래서 PostgREST 가 두 표를 이어 줄 근거가 없다. 두 GET 이 설계대로다.
//
// ## 읽기 RPC 를 만들지 않는다
// 두 표 다 `authenticated` 에 SELECT 가 있고 RLS 가 `user_id = auth.uid()` 다. 읽기 RPC 를 더하면
// 마이그레이션의 사후 단언("읽기 RPC 0개")이 깨지고, 무엇보다 definer 함수는 RLS 를 **우회**하므로
// 남의 기기 목록이 새는 길이 하나 더 생긴다.
//
// ## 쓰기는 upsert 하나다 (`on_conflict=user_id`)
// `authenticated` 에 DELETE 가 없고, 고른 맥을 되돌리는 길은 `main_device_id` 를 null 로 **쓰는** 것이다
// (행을 지울 필요가 없다 — 마이그레이션 §2 주석과 같은 규약).

extension SupabaseWorkService {
    package static let aiLimitsPrefsPath = "/rest/v1/ai_limits_prefs"
    /// PK 가 `user_id` 하나다 — 어느 맥에서 바꿔도 **같은 한 값**이 되는 것이 요구사항이다.
    package static let aiLimitsPrefsConflictKey = "user_id"

    /// 서버에 행이 있는 **내 맥 전부**(최근에 일한 순). 설정의 고르개가 세우는 목록이다.
    ///
    /// 제공자별로 흩어진 행을 기기 단위로 접는 일은 `AILimitDeviceRoster.fold` 가 한다(순수 — 폰이 같은 규칙을 쓴다).
    /// `select` 에 **값 칸을 넣지 않는다**: 고르개가 필요한 것은 "어떤 맥이 있고 언제 일했나" 뿐이고,
    /// 사용률까지 받아 오면 설정 창을 여는 것만으로 쓰지도 않는 숫자가 네트워크로 흐른다.
    package func fetchAILimitDevices(accessToken: String, userID: String) async throws -> [AILimitDevice] {
        let data = try await send(
            path: Self.aiLimitsPath,
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "device_id,device_label,observed_at"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([AILimitDeviceServerRow].self, from: data)
        return AILimitDeviceRoster.fold(rows.map {
            AILimitDeviceObservation(
                deviceID: $0.deviceId ?? "",
                label: $0.deviceLabel,
                // ★ 날짜는 **문자열로 받아 여기서 파싱한다**. 이 서비스의 디코더에는 날짜 전략이 없어서
                //   `Date` 로 선언하면 timestamptz 가 통째로 디코드 실패가 된다(그러면 목록이 빈다).
                observedAt: $0.observedAt.flatMap { parseDate($0) }
            )
        })
    }

    /// 계정이 고른 메인 맥. nil = 아직 안 골랐다(행이 없거나 칸이 null).
    ///
    /// 행이 0개인 것은 **정상**이다(한 번도 안 골랐다) — `profiles` 와 달리 가입 트리거가 이 행을 만들지 않는다.
    /// 그래서 0행을 throw 로 올리지 않는다(올리면 아무도 못 고른 상태에서 고르개가 영영 안 뜬다).
    package func fetchAILimitMainDeviceID(accessToken: String, userID: String) async throws -> String? {
        let data = try await send(
            path: Self.aiLimitsPrefsPath,
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "main_device_id"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([AILimitPrefsServerRow].self, from: data)
        guard let raw = rows.first?.mainDeviceId else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 메인 맥을 고른다(또는 nil 로 되돌린다). 계정당 한 행이므로 **upsert 하나**다.
    ///
    /// 상한을 클라에서도 막는 까닭: 서버 CHECK(1…128)를 넘기면 23514 로 그 행이 통째로 거절되고 그 거절은
    /// 조용하다 — 고른 맥이 저장된 줄 알고 설정을 닫은 사람이 폰에서 다른 맥을 계속 본다.
    /// 넘치는 값은 **보내지 않고 nil 로 접는다**(자르면 아무 맥도 안 가리키는 식별자가 된다).
    package func upsertAILimitMainDeviceID(
        accessToken: String,
        userID: String,
        mainDeviceID: String?
    ) async throws {
        let row = AILimitPrefsUpsertRow(
            userId: userID,
            mainDeviceId: AILimitMainDeviceIDContract.normalized(mainDeviceID)
        )
        try await sendNoBody(
            path: Self.aiLimitsPrefsPath,
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: Self.aiLimitsPrefsConflictKey)],
            body: [row],
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }
}

/// `ai_limits?select=device_id,device_label,observed_at` 한 행. 전부 **옵셔널**이다 —
/// 칸이 없는 서버(마이그레이션 전)에서도 디코드가 통째로 죽지 않아야 고르개만 조용히 비고 나머지는 산다.
package struct AILimitDeviceServerRow: Decodable, Equatable, Sendable {
    package var deviceId: String?
    package var deviceLabel: String?
    package var observedAt: String?
}

/// `ai_limits_prefs?select=main_device_id` 한 행.
package struct AILimitPrefsServerRow: Decodable, Equatable, Sendable {
    package var mainDeviceId: String?
}

/// `ai_limits_prefs` 한 행(upsert 본문). `updated_at` 은 **보내지 않는다** — 서버 터치 트리거가 덮는다.
///
/// 손글씨 인코더가 아닌 까닭: 이 본문은 **행이 하나뿐**이라 키 집합이 행마다 다를 수 없다(PGRST102 는
/// 배열에 섞인 행들 사이의 문제다). 그래도 nil 을 **명시적 null 로** 내보내야 "고른 맥 없음"으로 되돌릴 수
/// 있으므로(키를 생략하면 merge-duplicates 가 옛 값을 그대로 둔다) 그 한 칸만 손으로 적는다.
package struct AILimitPrefsUpsertRow: Encodable, Equatable, Sendable {
    package let userId: String
    package let mainDeviceId: String?

    package enum CodingKeys: String, CodingKey, CaseIterable {
        case userId = "user_id"
        case mainDeviceId = "main_device_id"
    }

    package init(userId: String, mainDeviceId: String?) {
        self.userId = userId
        self.mainDeviceId = mainDeviceId
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        // ★ `encodeIfPresent` 가 아니다. nil 을 생략하면 "안 고른 상태로 되돌리기"가 서버에 닿지 못한다
        //   (merge-duplicates 는 빠진 키를 건드리지 않는다).
        try container.encode(mainDeviceId, forKey: .mainDeviceId)
    }
}

/// `ai_limits_prefs.main_device_id` 의 단 하나의 규칙.
///
/// ★ 상한이 **`ai_limits.device_id` 와 같은 128** 이다(마이그레이션 §2 CHECK). 어긋나면 고를 수 있는 맥을
///   고르는 순간 23514 다 — 그 거절은 조용하고, 사용자는 저장된 줄 안다.
package enum AILimitMainDeviceIDContract {
    package static let maxLength = 128

    /// 보내도 되는 값, 또는 nil(= 안 고른 상태). 공백뿐이거나 상한을 넘으면 nil 이다.
    package static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}
