import CheckTokenScan
import Foundation

/// 한 번의 업로드에 실을 것. 서버 함수 scanner_upload 의 p_payload 가 이 모양이다.
struct ScanUploadPayload: Encodable {
    /// 월 행(token_usage_device_monthly). 맥 앱과 같은 함수(TokenUsageUpsertRequest.monthly)가 만든다. 총합 0 이면 nil.
    var monthly: TokenUsageUpsertRequest?
    /// 일별 행(token_usage_device_daily) — 바뀐 날만.
    var daily: [TokenUsageDailyUpsertRow]
    /// 스캔 하트비트(토큰 값 없이 "돌았고 파일 N개를 봤다").
    var heartbeat: TokenScanHeartbeatRequest
    var scannerVersion: String
    var build: Int
}

/// 업로드 계획 = 보낼 본문 + 성공하면 남길 상태.
struct ScanPlan {
    var payload: ScanUploadPayload
    /// false 면 보내지 않는다(바뀐 것이 없고 하트비트도 아직 신선하다).
    var shouldSend: Bool
    var stateOnSuccess: ScanState
}

/// 순수 계산: 스캔 결과 + 지난 상태 → 이번에 보낼 것. 맥 앱 WorkTimerStoreSync.uploadTokenUsageIfNeeded 의 게이트를 따른다
/// (총합 0 이면 월 행 생략 · 바뀐 것만 · 날이 바뀌면 일별 장부 초기화). 시각·네트워크·파일은 바깥에서 넣는다.
enum ScanPlanner {
    /// 바뀐 것이 없어도 이 간격마다 하트비트를 보낸다(맥 앱 설정 화면의 '마지막 올림'이 신선하게).
    static let heartbeatInterval: TimeInterval = 3600
    /// 서버도 같은 하한을 둔다(2분). 그보다 잦은 실행은 보내지 않는다.
    static let minimumSendInterval: TimeInterval = 110

    static func plan(
        usage: TokenUsageMonthly,
        filesStatted: Int,
        diagnostics: CodexUsageDiagnostics?,
        config: ScanConfig,
        state: ScanState,
        now: Date
    ) -> ScanPlan {
        let iso = ISO8601DateFormatter()
        let today = TokenUsageIncrementalScanner.dayBounds(now: now).date

        // 1) 월 행 — 맥 앱과 같은 게이트: Claude+Codex 총합 또는 안티그래비티가 있을 때만(계정 프로브는 원격 기계에서 돌리지 않는다).
        let monthlyNeeded = usage.total > 0 || usage.antigravityTotal > 0
        let monthly: TokenUsageUpsertRequest? = monthlyNeeded ? TokenUsageUpsertRequest.monthly(
            userID: "",                       // 서버가 기기 키로 정한다(본문 값은 쓰지 않는다)
            usage: usage,
            deviceID: config.deviceId,
            account: nil,
            accountStatus: nil,
            diagnostics: diagnostics,
            formatDate: { iso.string(from: $0) }
        ) : nil
        let snapshot = Self.snapshot(usage)
        let monthlyChanged = monthlyNeeded && snapshot != state.lastUploadedUsage

        // 2) 일별 행 — 날이 바뀌면 장부를 비워 그 날 전부 다시 보낸다(맥 앱 lastUploadedDailyBaselineDay 와 같은 규칙).
        var ledger = state.dailyBaselineDay == today ? state.uploadedDaily : [:]
        let values = TokenUsageDailyUpload.values(usage: usage, account: nil)
        let changedDays = values.keys.sorted().filter { ledger[$0] != Self.canonical(values[$0]!) }
        let daily = TokenUsageDailyUpload.rows(userID: "", deviceID: config.deviceId, days: changedDays, values: values)
        for day in changedDays { ledger[day] = Self.canonical(values[day]!) }

        // 3) 하트비트 — 늘 싣는다.
        let heartbeat = TokenScanHeartbeatRequest(
            userId: "", month: usage.month, deviceId: config.deviceId,
            lastScanAt: iso.string(from: now), scanFiles: filesStatted
        )

        let sinceLast = state.lastUploadAt.map { now.timeIntervalSince($0) } ?? .infinity
        let heartbeatDue = sinceLast >= heartbeatInterval
        let somethingNew = monthlyChanged || !daily.isEmpty || diagnostics != nil
        let shouldSend = sinceLast >= minimumSendInterval && (somethingNew || heartbeatDue)

        var next = state
        next.lastUploadAt = now
        next.lastResult = "ok"
        if monthlyNeeded { next.lastUploadedUsage = snapshot }
        next.dailyBaselineDay = today
        next.uploadedDaily = ledger
        if let diagnostics {
            next.diagnosticsStamp = diagnosticsStamp(build: diagnostics.appBuild, now: now)
        }
        next.lastMonth = usage.month
        next.lastClaudeTotal = usage.claudeTotal
        next.lastCodexTotal = usage.codexTotal
        next.lastAntigravityTotal = usage.antigravityTotal
        next.lastFiles = filesStatted

        return ScanPlan(
            payload: ScanUploadPayload(
                monthly: monthly, daily: daily, heartbeat: heartbeat,
                scannerVersion: AingScanBuild.version, build: AingScanBuild.sharedCodeAppBuild
            ),
            shouldSend: shouldSend,
            stateOnSuccess: next
        )
    }

    /// 맥 앱 WorkTimerStoreSync.codexDiagnosticsStamp 와 같은 모양("<빌드>:<KST 날짜>").
    static func diagnosticsStamp(build: Int, now: Date) -> String {
        "\(build):\(TokenUsageIncrementalScanner.dayBounds(now: now).date)"
    }

    static func diagnosticsDue(state: ScanState, now: Date) -> Bool {
        state.diagnosticsStamp != diagnosticsStamp(build: AingScanBuild.sharedCodeAppBuild, now: now)
    }

    static func snapshot(_ usage: TokenUsageMonthly) -> TokenUsageMonthlySnapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(usage)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return TokenUsageMonthlySnapshot(json: json)
    }

    /// 하루 값의 정규 문자열(모르는 값 nil 은 "-" — 0 과 구별된다).
    static func canonical(_ value: TokenUsageDailyValue) -> String {
        func s(_ v: Int?) -> String { v.map(String.init) ?? "-" }
        return [s(value.claude), s(value.codex), s(value.codexUTC), s(value.codexAccount), s(value.antigravity)]
            .joined(separator: ",")
    }
}
