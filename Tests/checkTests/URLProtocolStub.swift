import Foundation
@testable import check

extension URLSessionConfiguration {
    static var stubbed: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return configuration
    }
}

final class URLProtocolStub: URLProtocol {
    // 기록 버퍼(요청/본문)는 여러 URLSession 워커 스레드가 동시에 append 하고 테스트 스레드가 읽으므로
    // 단일 NSLock 으로 모든 접근을 직렬화한다. 외부는 아래 정적 헬퍼로만 접근한다(직접 노출 금지).
    private nonisolated(unsafe) static var requests: [URLRequest] = []
    private nonisolated(unsafe) static var bodiesByHost: [String: [String]] = [:]
    private static let stateLock = NSLock()
    nonisolated(unsafe) static var patchWorkSessionsShouldFail = false
    nonisolated(unsafe) static var delayedHosts: Set<String> = []
    nonisolated(unsafe) static var responseDelay: TimeInterval = 0.15
    /// 이 접두어로 시작하는 호스트는 **항상** 지연 응답한다. delayedHosts 는 테스트마다 통째로 대입/초기화하는
    /// 프로세스 전역 값이라, 병렬로 도는 다른 스위트의 defer 가 내 지연을 지워 레이스 재현이 무음으로 깨진다
    /// (실제로 그렇게 사라져 in-flight 창이 0이 된 적이 있다). 접두어 규약은 아무도 대입하지 않아 안전하다.
    static let alwaysDelayedHostPrefix = "delayed-"

    private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.record(request: request, bodyText: Self.bodyText(from: request))

        let responseData = Self.responseData(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode(for: request),
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        let delivery = StubDelivery(proto: self, response: response, data: responseData)
        if let host = request.url?.host,
           Self.delayedHosts.contains(host) || host.hasPrefix(Self.alwaysDelayedHostPrefix) {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.responseDelay) {
                delivery.run()
            }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {
        isStopped = true
    }

    private final class StubDelivery: @unchecked Sendable {
        let proto: URLProtocolStub
        let response: HTTPURLResponse
        let data: Data

        init(proto: URLProtocolStub, response: HTTPURLResponse, data: Data) {
            self.proto = proto
            self.response = response
            self.data = data
        }

        func run() {
            guard !proto.isStopped else { return }
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }

    // 기록 헬퍼. 요청과 그 본문을 잠금 아래에서 원자적으로 함께 적재한다(zip 정합성 유지).
    private static func record(request: URLRequest, bodyText: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        requests.append(request)
        bodiesByHost[request.url?.host ?? "", default: []].append(bodyText)
    }

    static func requests(forHost host: String) -> [URLRequest] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requests.filter { $0.url?.host == host }
    }

    static func bodyText(forHost host: String) -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return bodiesByHost[host, default: []].joined(separator: "\n")
    }

    // 호스트별 본문 배열. requests(forHost:)와 순서가 대응하므로 zip 으로 요청-본문을 짝지을 수 있다.
    static func bodies(forHost host: String) -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return bodiesByHost[host, default: []]
    }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }

        guard let stream = request.httpBodyStream else {
            return ""
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func statusCode(for request: URLRequest) -> Int {
        if request.url?.host == "invalid-key" {
            return 401
        }
        if request.url?.host == "invalid-login" && request.url?.path == "/auth/v1/token" {
            return 400
        }
        if request.url?.host == "email-not-confirmed" && request.url?.path == "/auth/v1/token" {
            return 400
        }
        if request.url?.host == "schema-missing" && request.url?.path.hasPrefix("/rest/v1/") == true {
            return 404
        }
        // 만료 access token 재현. 정확 일치가 아니라 **접미어** 매칭인 이유는 지연 응답 규약(alwaysDelayedHostPrefix)
        // 과 조합해야 하기 때문이다 — "delayed-expired-token" 처럼 접두어+접미어를 동시에 만족하는 호스트로만
        // "grant 가 in-flight 인 사이에 낡은 토큰으로 요청이 나가면 두 번째 grant 가 터진다"를 재현할 수 있다.
        if request.url?.host?.hasSuffix("expired-token") == true,
           request.url?.path.hasPrefix("/rest/v1/") == true,
           request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access-token" {
            return 401
        }
        if request.url?.host == "stop-fails",
           request.url?.path == "/rest/v1/work_sessions",
           request.httpMethod == "PATCH" {
            return 500
        }
        // 참여코드 RPC 만 일시 실패(500)시키는 호스트 — loadMyInviteCode do/catch 가 기존 코드를 지우지 않는지 검증용.
        if request.url?.host == "invite-code-fails",
           request.url?.path == "/rest/v1/rpc/my_team_invite_code" {
            return 500
        }
        // 개인 기록 조회만 실패(500)시키는 호스트 — 실패가 "불러오는 중…"에 갇히지 않는지(insightsFailed) 검증용.
        if request.url?.host == "insights-fetch-fails",
           request.url?.path == "/rest/v1/work_sessions",
           request.httpMethod == "GET" {
            return 500
        }
        // 토큰 순위 RPC 만 일시 실패(500)시키는 호스트 — 월 이동 중 실패가 본문에 동기화 문구를 남기지 않는지
        // (tokenBoardFailed) 검증용. 다른 조회(멤버십 등)는 정상 응답해야 스토어 준비가 된다.
        if request.url?.host == "token-board-fails",
           request.url?.path == "/rest/v1/rpc/token_usage_board" {
            return 500
        }
        // 새 기기별 표만 없는 서버(= v0.2.11 마이그레이션 미적용) 재현 호스트: 옛 표 업로드는 성공하고
        // 새 표만 404(PGRST205)로 거부된다 — 스키마 부재가 화면 문구로 드러나는지 검증용.
        if request.url?.host == "device-table-missing",
           request.url?.path == "/rest/v1/token_usage_device_monthly" {
            return 404
        }
        // v0.2.40 스캐너 하트비트만 5xx 로 떨어뜨리는 호스트. 도장(lastTokenScanHeartbeatAt)이 **성공에만**
        // 찍혀 실패한 스캔이 다음 주기에 그대로 재시도되는지 검증용 — 실패에도 도장을 찍으면 그 스캔의 사실은
        // 영영 서버에 안 남고, "안 씀"과 "스캐너 죽음"을 가를 신호가 그 창에서 사라진다.
        if request.url?.host?.hasPrefix("v0240-hb-fails") == true,
           request.url?.path == "/rest/v1/token_usage_device_monthly" {
            return 500
        }
        // 기기별 소유 주장 표만 없는 서버(= 이 릴리스의 마이그레이션 미적용) 재현 호스트.
        // 팀 상태 폴링이 이 404 하나로 통째로 죽지 않는지(= 앱이 서버 배포 순서에 인질로 잡히지 않는지) 검증용.
        if request.url?.host == "status-device-table-missing",
           request.url?.path == "/rest/v1/work_status_devices" {
            return 404
        }
        // ultra_wallet_sync RPC 가 **아직 없는 서버**(브루 배포가 db push 보다 앞선 창) 재현 호스트.
        // 404 + "schema cache" 문구가 PGRST202 의 실제 모양이고, 서비스가 그걸 .ultraWalletUnavailable 로
        // 접는지 검증한다(재던지면 "네트워크 실패"와 구별이 사라진다).
        if request.url?.host?.contains("wallet-missing") == true,
           request.url?.path == "/rest/v1/rpc/ultra_wallet_sync" {
            return 404
        }
        if request.url?.host == "retry-toggle",
           request.url?.path == "/rest/v1/work_sessions",
           request.httpMethod == "PATCH" {
            return patchWorkSessionsShouldFail ? 500 : 200
        }

        return request.url?.path == "/rest/v1/work_sessions" ? 201 : 200
    }

    private static func responseData(for request: URLRequest) -> Data {
        if request.url?.host == "invalid-key" {
            return Data(
                """
                {"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}
                """.utf8
            )
        }
        if request.url?.host == "invalid-login" && request.url?.path == "/auth/v1/token" {
            return Data(#"{"msg":"Invalid login credentials","code":400}"#.utf8)
        }
        if request.url?.host == "email-not-confirmed" && request.url?.path == "/auth/v1/token" {
            return Data(#"{"msg":"Email not confirmed","code":400}"#.utf8)
        }
        if request.url?.host == "schema-missing" && request.url?.path.hasPrefix("/rest/v1/") == true {
            return Data(#"{"code":"PGRST205","message":"Could not find the table 'public.work_statuses' in the schema cache"}"#.utf8)
        }
        if request.url?.host?.hasSuffix("expired-token") == true,
           request.url?.path.hasPrefix("/rest/v1/") == true,
           request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access-token" {
            return Data(#"{"code":"PGRST301","message":"JWT expired"}"#.utf8)
        }
        if request.url?.host == "device-table-missing",
           request.url?.path == "/rest/v1/token_usage_device_monthly" {
            return Data(
                #"{"code":"PGRST205","message":"Could not find the table 'public.token_usage_device_monthly' in the schema cache"}"#.utf8
            )
        }
        if request.url?.host == "status-device-table-missing",
           request.url?.path == "/rest/v1/work_status_devices" {
            return Data(
                #"{"code":"PGRST205","message":"Could not find the table 'public.work_status_devices' in the schema cache"}"#.utf8
            )
        }
        // take_pokes 는 인자 없는 RPC 라 '받을 게 없음'의 정상 응답이 빈 배열이다. 미등록으로 두면 Data() 가
        // 돌아가 [TakenPokeRow] 디코드가 조용히 throw 되는데, 스토어의 catch 가 그걸 삼켜 "요청은 나갔는데
        // 전달 경로만 죽은" 상태가 테스트에 전혀 드러나지 않는다(건수만 세는 테스트는 통과해 버린다).
        if request.url?.path == "/rest/v1/rpc/take_pokes" {
            return Data("[]".utf8)
        }
        // 내 공개 설정 조회(profiles GET)도 정상 1행을 돌려준다. 미등록이면 loadTokenUsagePrivacyIfNeeded 의
        // loaded 래치가 영영 안 서서 폴링 tick 마다 같은 GET 이 재발사되고, 요청 건수를 세는 테스트가 흔들린다.
        if request.url?.path == "/rest/v1/profiles", request.httpMethod == "GET" {
            return Data(#"[{"token_usage_public":true}]"#.utf8)
        }
        if request.url?.path == "/rest/v1/rpc/ultra_wallet_sync" {
            return ultraWalletSyncData(for: request)
        }
        if request.url?.path == "/rest/v1/rpc/lookup_team_by_code" {
            return lookupTeamByCodeData(for: request)
        }
        if request.url?.path == "/rest/v1/rpc/join_team" {
            return joinTeamData(for: request)
        }
        if request.url?.path == "/rest/v1/rpc/create_team" {
            return createTeamData()
        }
        if request.url?.path == "/rest/v1/rpc/my_team_invite_code" {
            return myInviteCodeData(for: request)
        }
        if request.url?.path == "/rest/v1/rpc/team_weekly_leaderboard" {
            return teamLeaderboardData()
        }
        if request.url?.path == "/rest/v1/memberships", request.httpMethod == "GET" {
            return membershipsData(for: request)
        }
        if request.url?.path == "/rest/v1/work_statuses" {
            return workStatusesData(for: request)
        }
        if request.url?.path == "/rest/v1/work_status_devices", request.httpMethod == "GET" {
            return workStatusDevicesData(for: request)
        }
        if request.url?.path == "/rest/v1/work_sessions", request.httpMethod == "GET" {
            return workSessionsData(for: request)
        }
        if request.url?.path == "/rest/v1/token_usage_monthly", request.httpMethod == "GET" {
            return legacyTokenUsageData(for: request)
        }
        if request.url?.path == "/auth/v1/token",
           request.url?.query?.contains("grant_type=refresh_token") == true
        {
            return Data(
                """
                {
                  "access_token": "refreshed-token",
                  "refresh_token": "next-refresh-token",
                  "user": { "id": "00000000-0000-0000-0000-000000000002" }
                }
                """.utf8
            )
        }
        if request.url?.path == "/auth/v1/token" {
            return Data(
                """
                {
                  "access_token": "signed-in-token",
                  "refresh_token": "signed-in-refresh-token",
                  "user": { "id": "00000000-0000-0000-0000-000000000002" }
                }
                """.utf8
            )
        }

        guard request.url?.path == "/auth/v1/signup" else {
            return Data()
        }

        return Data(
            """
            {
              "access_token": "signed-up-token",
              "refresh_token": "signed-up-refresh-token",
              "user": { "id": "00000000-0000-0000-0000-000000000002" }
            }
            """.utf8
        )
    }

    /// 랩 하나의 길이(3시간). 서버 `mission_work_seconds()` 와 같은 값이다.
    static let walletFixtureLapSeconds = 10_800
    /// **현재 랩**의 진행(15분). 0 으로 두면 "진행이 그날 총합이 아니라 현재 랩 기준인가"를 묻는 단언이
    /// 0 == 0 으로 우연히 통과해 버린다 — 그래서 총합과 절대 같아질 수 없는 값을 심는다.
    static let walletFixtureLapProgressSeconds = 900

    /// ultra_wallet_sync 픽스처. 기본은 "오늘 3시간짜리 랩을 하나 정산해 +1 을 방금 받았다" 이고,
    /// host 에 "wallet-missing" 이 들어가면 RPC 부재(PGRST202)를, "wallet-claimed" 가 들어가면
    /// **이번 호출에서는 안 받았다**(granted_now=false)를 돌려준다 — 연출 트리거가 claimed 가 아니라
    /// granted_now 인지 가르는 유일한 픽스처 쌍이다.
    /// host 에 "wallet-lapsN" 이 들어가면 오늘 랩을 N 개 정산한 상태가 된다(안 적으면 1개).
    ///
    /// ★ 2026-09-01 랩 전환 뒤 **새 서버가 실제로 보내는 모양**이다. 세 가지가 예전과 다르다:
    ///   ① `claimed` 는 언제나 false — 랩이 또 열려 있으니 "오늘 치는 받았다"로 닫을 수가 없다.
    ///   ② `progress_seconds` 는 그날 총합이 아니라 **현재 랩의 진행**이다.
    ///   ③ 그날 총합은 새 키 `worked_seconds` 로 옮겨 갔고, 받은 랩 수는 `laps_granted` 가 말한다.
    ///   옛 모양(claimed=true + progress_seconds=총합)을 픽스처에 남겨 두면, 스텁만 보는 테스트들이
    ///   실서버에서 이미 사라진 화면을 계속 초록으로 지킨다.
    private static func ultraWalletSyncData(for request: URLRequest) -> Data {
        let host = request.url?.host ?? ""
        if host.contains("wallet-missing") {
            return Data(#"{"code":"PGRST202","message":"Could not find the function public.ultra_wallet_sync(p_days_back) in the schema cache"}"#.utf8)
        }
        let grantedNow = host.contains("wallet-claimed") ? "false" : "true"
        let laps = walletFixtureLapCount(in: host)
        // 그날 총합 = 정산한 랩들 + 지금 돌고 있는 랩의 진행. 이 항등식이 깨진 픽스처는
        // 서버가 절대 못 보내는 상태라, 그걸로 초록이 된 코드는 실서버에서 무슨 짓을 할지 모른다.
        let workedSeconds = laps * walletFixtureLapSeconds + walletFixtureLapProgressSeconds
        return Data(
            """
            {"status":"ok","balance":1,"balance_cap":3,"daily_floor":1,"day":"2026-08-19",
             "floor_applied":true,
             "missions":[{"key":"work3h","kst_day":"2026-08-19","target_seconds":\(walletFixtureLapSeconds),
                          "progress_seconds":\(walletFixtureLapProgressSeconds),"claimed":false,
                          "granted_now":\(grantedNow),"capped":false,
                          "laps_settled":\(laps),"laps_granted":\(laps),"worked_seconds":\(workedSeconds)}],
             "worked_seconds_closed":\(workedSeconds),"worked_seconds_open":0,
             "streak_days":3,"streak_includes_today":true,"measured_at":1787098516}
            """.utf8
        )
    }

    /// host 의 "wallet-lapsN" 에서 N 을 읽는다(없으면 1). 호스트 이름으로 고르는 이유는 이 스텁의
    /// 다른 분기(wallet-missing / wallet-claimed)와 같다 — 테스트마다 고유 호스트를 쓰므로
    /// 병렬 실행에서 서로의 픽스처를 덮어쓸 수 없다.
    private static func walletFixtureLapCount(in host: String) -> Int {
        guard let marker = host.range(of: "wallet-laps") else { return 1 }
        let digits = host[marker.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? 1
    }

    // 스텁 팀 픽스처가 반환하는 기본 팀 id. 스토어 테스트가 currentTeamID 를 직접 세팅할 때도 사용한다.
    static let stubTeamID = "10000000-0000-0000-0000-000000000001"
    /// 주간 누적 픽스처의 고정 기준시각(2026-07-14 12:33 KST — 화요일 낮). 주 경계(월요일 00시)에 걸려
    /// 클리핑이 0이 되는 시각 의존을 없애려고, 이 값을 쓰는 테스트는 같은 값을 서비스에 now 로 주입한다.
    static let weeklyFixtureNow = Date(timeIntervalSince1970: 1_784_000_000)

    // 옛 표(token_usage_monthly) 현재 값 조회 픽스처(덮어쓰기 전 게이트가 읽는 그 요청).
    // host 에 "legacy-bigger" 가 들어가면 **아직 v0.2.10 인 다른 맥**이 올려 둔 큰 누적치 한 줄을,
    // 그 외에는 빈 목록(그 달 행 없음 → 덮어쓰기 허용)을 돌려준다.
    private static func legacyTokenUsageData(for request: URLRequest) -> Data {
        guard request.url?.host?.contains("legacy-bigger") == true else {
            return Data("[]".utf8)
        }
        return Data(#"[{"total": 200000000}]"#.utf8)
    }

    // 코드 미리보기 픽스처. host 에 "miss" 가 들어가면 불일치(0행)로, 그 외에는 stubTeamID 팀을 돌려준다.
    private static func lookupTeamByCodeData(for request: URLRequest) -> Data {
        if request.url?.host?.contains("miss") == true {
            return Data("[]".utf8)
        }
        return Data(
            """
            [
              {"team_id": "10000000-0000-0000-0000-000000000001", "name": "아잉팀", "weekly_goal_hours": 40, "member_count": 3}
            ]
            """.utf8
        )
    }

    // 코드 합류 픽스처. host 에 "miss" 가 들어가면 불일치(0행)로, 그 외에는 합류 성공 팀 정보를 돌려준다.
    private static func joinTeamData(for request: URLRequest) -> Data {
        if request.url?.host?.contains("miss") == true {
            return Data("[]".utf8)
        }
        return Data(
            """
            [
              {"team_id": "10000000-0000-0000-0000-000000000001", "name": "아잉팀", "weekly_goal_hours": 40}
            ]
            """.utf8
        )
    }

    // 팀 만들기 픽스처. 새로 만든 팀의 참여코드(8자)를 함께 돌려준다.
    private static func createTeamData() -> Data {
        Data(
            """
            [
              {"team_id": "10000000-0000-0000-0000-000000000001", "name": "새로운 팀", "invite_code": "X7K2M9Q4", "weekly_goal_hours": 50}
            ]
            """.utf8
        )
    }

    // owner 참여코드 픽스처. host 에 "member" 가 들어가면 owner 아님(0행)으로 둔다.
    private static func myInviteCodeData(for request: URLRequest) -> Data {
        if request.url?.host?.contains("member") == true {
            return Data("[]".utf8)
        }
        return Data(#"[{"invite_code": "AINGTEAM"}]"#.utf8)
    }

    // 팀 리그 픽스처: 3팀. member_count 로 "평균 역전"을 심는다 — 총합 1위(오목교 90000)가 1인당 평균으로는
    // 2위가 되도록(오목교 90000/3=30000 < 코드 크래프터 36000/1=36000) 인원을 준다. 정렬은 총합이 아니라
    // 평균 내림차순이라, 정렬 후 평균 [36000(코드), 30000(오목교), 24000(내 팀 72000/3)] 순이어야 한다.
    // 서버 정렬(총합 desc)을 신뢰하지 않고 클라가 평균으로 다시 정렬하는지 보이려 원본은 평균순이 아니다.
    private static func teamLeaderboardData() -> Data {
        Data(
            """
            [
              {"team_id": "30000000-0000-0000-0000-000000000003", "team_name": "코드 크래프터", "weekly_goal_hours": 50, "total_seconds": 36000, "working_count": 0, "member_count": 1},
              {"team_id": "20000000-0000-0000-0000-000000000002", "team_name": "오목교 브라더스", "weekly_goal_hours": 60, "total_seconds": 90000, "working_count": 1, "member_count": 3},
              {"team_id": "10000000-0000-0000-0000-000000000001", "team_name": "아잉팀", "weekly_goal_hours": 40, "total_seconds": 72000, "working_count": 3, "member_count": 3}
            ]
            """.utf8
        )
    }

    private static func membershipsData(for request: URLRequest) -> Data {
        // 무소속 로그인 검증 전용 호스트는 빈 배열(소속 없음)을 돌려준다.
        if request.url?.host == "no-team-test" {
            return Data("[]".utf8)
        }
        // 목표시간 폴백 검증 전용 호스트: weekly_goal_hours 필드를 아예 내려주지 않는다(누락 → 60h 폴백).
        if request.url?.host == "membership-no-goal-test" {
            return Data(
                """
                [
                  {"team_id": "10000000-0000-0000-0000-000000000001", "teams": {"name": "아잉팀"}}
                ]
                """.utf8
            )
        }
        // owner 검증 전용 호스트: role=owner 를 함께 내려준다(confirmMembership 이 참여코드를 로드하도록).
        if request.url?.host?.contains("owner") == true {
            return Data(
                """
                [
                  {"team_id": "10000000-0000-0000-0000-000000000001", "role": "owner", "teams": {"name": "아잉팀", "weekly_goal_hours": 40}}
                ]
                """.utf8
            )
        }
        // 기본 픽스처는 팀 목표시간 40시간과 member 역할을 함께 내려준다(멤버십 조회 한 번으로 목표까지 확정).
        return Data(
            """
            [
              {"team_id": "10000000-0000-0000-0000-000000000001", "role": "member", "teams": {"name": "아잉팀", "weekly_goal_hours": 40}}
            ]
            """.utf8
        )
    }

    private static func workStatusesData(for request: URLRequest) -> Data {
        let host = request.url?.host

        if host == "today-hours-test" {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "status": "off_work",
                    "updated_at": "2026-07-10T04:00:00Z",
                    "last_seen_at": null,
                    "active_session_id": null,
                    "profiles": { "display_name": "영식", "email": "member@example.com" }
                  }
                ]
                """.utf8
            )
        }

        // 경계 클리핑 검증 전용 호스트: 누적 계산은 완료 세션(work_sessions)에서 나오므로 상태는 off_work.
        if host == "week-boundary-clip" || host == "day-boundary-clip" {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "status": "off_work",
                    "updated_at": "2026-07-08T12:00:00Z",
                    "last_seen_at": null,
                    "active_session_id": null,
                    "profiles": { "display_name": "영식", "email": "member@example.com" }
                  }
                ]
                """.utf8
            )
        }

        // last_seen_at 파싱 검증 전용 호스트.
        if host == "presence-fetch-test" {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "status": "working",
                    "updated_at": "2026-07-01T04:00:00Z",
                    "last_seen_at": "2026-07-01T05:00:00Z",
                    "active_session_id": "60000000-0000-0000-0000-000000000001",
                    "profiles": { "display_name": "영식", "email": "member@example.com" }
                  }
                ]
                """.utf8
            )
        }

        // 자리 비움 자동 마감 중 '오늘 시작한' 세션 전용 호스트군(자정 클리핑 계약).
        // 시각은 **고정된 절대 시각**(staleTodayFixture)에서 파생한다 — 벽시계에서 파생하면 이 픽스처가
        // 만들어지는 시각(URLProtocol 워커 스레드)과 스토어가 판정하는 시각이 달라 그 차이가 그대로 오차가
        // 되고, KST 00시대에는 2시간 전 시작이 자정으로 잘려 기대값이 통째로 붕괴한다(매일 밤 빨간 테스트).
        if let fixture = staleTodayFixture(forHost: host) {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "status": "working",
                    "updated_at": "\(iso(fixture.sessionStart))",
                    "last_seen_at": "\(iso(fixture.lastSeenAt))",
                    "active_session_id": "50000000-0000-0000-0000-000000000002",
                    "profiles": { "display_name": "영식", "email": "member@example.com" }
                  }
                ]
                """.utf8
            )
        }

        // R1 전용 호스트군: '맥 A 가 살아 있는데 맥 B 를 켠' 상황을 신호 공백 길이만 바꿔 재현한다.
        // 전부 2시간 전 시작한 열린 세션 하나를 들고 있고, 다른 것은 마지막 신호 시각뿐이다.
        if let fixture = ownerSignalFixture(forHost: host) {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "status": "working",
                    "updated_at": "\(iso(fixture.sessionStart))",
                    "last_seen_at": "\(iso(fixture.lastSeenAt))",
                    "active_session_id": "51000000-0000-0000-0000-000000000001",
                    "profiles": { "display_name": "영식", "email": "member@example.com" }
                  }
                ]
                """.utf8
            )
        }

        // 자리 비움 자동 마감 검증 전용 호스트군: 마지막 신호가 아주 오래되어(>90초) stale 로 판정된다.
        // 이름 포함으로 매칭해, 레이스 테스트가 지연 접두어를 붙인 자기만의 호스트(delayed-abandoned-session-…)를
        // 쓸 수 있게 한다 — 호스트를 공유하면 요청 기록 버퍼가 섞여 in-flight 시점을 잡을 수 없다.
        if host?.contains("abandoned-session") == true {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "status": "working",
                    "updated_at": "2026-01-01T00:00:00Z",
                    "last_seen_at": "2026-01-01T00:01:00Z",
                    "active_session_id": "50000000-0000-0000-0000-000000000001",
                    "profiles": { "display_name": "영식", "email": "member@example.com" }
                  }
                ]
                """.utf8
            )
        }

        if Self.hasTeamFixture(for: request) == false {
            return Data("[]".utf8)
        }

        // 팀 픽스처의 근무중 멤버는 생존신호(last_seen_at)를 현재 시각으로 둬 stale/자동 마감으로 오판되지 않게 한다.
        return Data(
            """
            [
              {
                "user_id": "00000000-0000-0000-0000-000000000002",
                "status": "working",
                "updated_at": "2026-07-01T01:00:00Z",
                "last_seen_at": "\(isoNow())",
                "active_session_id": "30000000-0000-0000-0000-000000000001",
                "profiles": { "display_name": "영식", "email": "member@example.com" }
              }
            ]
            """.utf8
        )
    }

    // R1 픽스처의 신호 공백(초). 자리 비움 자동 마감의 계약 임계(WorkTimerStore.adoptedReclaimStaleSeconds
    // = sleepGraceSeconds + 4주기 = 7분)를 **사이에 두고** 양쪽에 하나씩 둔다.
    // 상수를 여기서 직접 참조하지 않는 이유는 그 값이 @MainActor 격리라 URLProtocol 워커 스레드에서
    // 읽을 수 없기 때문이다 — 대신 이 세 값이 실제로 임계를 감싸는지는
    // autoCloseFixturesStraddleTheContractThreshold 가 @MainActor 에서 단언한다(파생 관계는 거기서 고정된다).
    /// 맥 A 의 3분 낮잠. 이 앱의 잠자기 유예(5분) **안**이라 A 는 그대로 근무 중이다 — 마감 대상이 아니다.
    static let ownerNapSignalGap: TimeInterval = 180
    /// 임계 -60초. 계약 안이라 마감 금지.
    static let signalGapInsideContract: TimeInterval = 360
    /// 임계 +60초. 계약 밖이라 마감 + 되돌리기 제공.
    static let signalGapOutsideContract: TimeInterval = 480
    /// stale-today-session 호스트군의 신호 공백(초). 계약 임계 **밖**이어야 자동 마감이 성립한다.
    static let staleTodaySessionSignalGap: TimeInterval = 480

    // MARK: - 자정 클리핑 계약 호스트군(고정 시각)

    /// 자동 마감의 '오늘 몫'(= seen − max(sessionStart, KST 자정))을 검증하는 호스트의 픽스처.
    ///
    /// **왜 벽시계가 아니라 고정 절대 시각인가**(이 구조체의 전부다): 이 계약은 KST 자정 클리핑을 지나므로
    /// 결과가 "지금이 자정에서 얼마나 떨어졌는가"에 좌우된다. 벽시계로 픽스처를 만들면
    ///   (1) KST 00:00~02:00 에는 '2시간 전 시작'이 자정으로 잘려 기대값이 붕괴하고,
    ///   (2) 픽스처 생성(워커 스레드)과 스토어 판정(메인 액터, 전체 스위트에서 수십 초 밀릴 수 있다) 사이의
    ///       지연이 클리핑이 걸린 순간 그대로 오차가 되며,
    ///   (3) 자정 직전에 시작한 실행은 픽스처와 단언이 **서로 다른 날**의 자정을 쓰게 된다.
    /// 절대 시각으로 못 박고 스토어의 주입 시계(store.clock)를 같은 값으로 맞추면 이 축이 통째로 사라진다.
    struct StaleTodayFixture {
        /// 이 시나리오의 '지금'. 테스트는 반드시 `store.clock = { fixture.now }` 로 같은 값을 주입한다.
        let now: Date
        /// 서버가 들고 있는 열린 세션의 시작 시각.
        let sessionStart: Date
        /// 마지막 생존신호. now 와의 공백이 계약 임계(7분) 밖이라 자동 마감이 성립한다.
        let lastSeenAt: Date
        /// 이 시나리오가 서 있는 KST 하루의 시작(자정). 클리핑 기대값 계산의 기준이다.
        var koreanDayStart: Date { TeamWeeklyGoal.koreanDayStart(for: now) }
    }

    /// 정오 고정: 자정에서 12시간 떨어져 있어 클리핑이 개입하지 않는다(원래 계약의 기준 배치).
    static let staleTodayNoonHost = "stale-today-session-test"
    /// KST 00:05 고정: 마감된 세션의 구간이 **전부 어제**라 '오늘 몫'이 0 이어야 한다(클리핑 그 자체).
    static let staleTodayMidnightHost = "stale-today-session-midnight-test"
    /// KST 00:45 고정: 클리핑이 실제로 자르면서도 '오늘 몫'이 유의미한 크기다 —
    /// 정오 배치와 **같은 형태의 단언**이 자정 창 안에서도 그대로 성립함을 보이는 배치.
    static let staleTodayAfterMidnightHost = "stale-today-session-after-midnight-test"

    /// 하루 스윕용 호스트 접두어. 뒤에 'KST 자정으로부터 몇 분'을 붙인다(예: stale-today-at-13 → 00:13).
    /// 이 스윕이 있어야 "특정 시각에만 무너지는" 회귀가 **매 실행마다** 잡힌다 — 벽시계로 돌던 시절엔
    /// 그 시각에 우연히 돌려야만 드러났고, 실제로 매일 밤 00시대에만 빨갛게 떴다.
    static let staleTodaySweepHostPrefix = "stale-today-at-"
    static func staleTodaySweepHost(minutesAfterMidnight: Int) -> String {
        "\(staleTodaySweepHostPrefix)\(minutesAfterMidnight)"
    }

    static func staleTodayFixture(forHost host: String?) -> StaleTodayFixture? {
        func make(minutesAfterMidnight: Int, sessionStartOffset: TimeInterval) -> StaleTodayFixture {
            let now = kst(hour: 0, minute: 0).addingTimeInterval(Double(minutesAfterMidnight) * 60)
            return StaleTodayFixture(
                now: now,
                sessionStart: now.addingTimeInterval(-sessionStartOffset),
                lastSeenAt: now.addingTimeInterval(-staleTodaySessionSignalGap)
            )
        }
        switch host {
        case staleTodayNoonHost:
            return make(minutesAfterMidnight: 12 * 60, sessionStartOffset: 7_200)
        case staleTodayMidnightHost:
            // 8분 전 신호가 어제 23:57 이라 '오늘 몫'은 0 이다(자정 직후엔 그것이 정답이다).
            return make(minutesAfterMidnight: 5, sessionStartOffset: 7_200)
        case staleTodayAfterMidnightHost:
            // 00:05 시작 → 00:37 신호 두절 → 00:45 관측. 세션 시작이 자정 **뒤**라 클리핑이 자르지 않지만
            // 2시간 전 시작이었다면 잘렸을 창이다(= 옛 픽스처가 매일 밤 무너지던 바로 그 시간대).
            return make(minutesAfterMidnight: 45, sessionStartOffset: 2_400)
        default:
            guard let host, host.hasPrefix(staleTodaySweepHostPrefix),
                  let minutes = Int(host.dropFirst(staleTodaySweepHostPrefix.count))
            else {
                return nil
            }
            return make(minutesAfterMidnight: minutes, sessionStartOffset: 7_200)
        }
    }

    /// 고정 기준일(2026-01-15) KST 의 시각. 벽시계를 전혀 읽지 않으므로 실행 시각·날짜 경계와 무관하다.
    private static func kst(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TeamWeeklyGoal.koreanTimeZone
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private static func ownerSignalGap(for host: String?) -> TimeInterval? {
        switch host {
        case ownerNapHost: return ownerNapSignalGap
        case autoCloseUnderThresholdHost: return signalGapInsideContract
        case autoCloseOverThresholdHost: return signalGapOutsideContract
        default: return nil
        }
    }

    static let ownerNapHost = "owner-nap-test"
    static let autoCloseUnderThresholdHost = "autoclose-under-threshold-test"
    static let autoCloseOverThresholdHost = "autoclose-over-threshold-test"

    /// R1 호스트군('맥 A 가 살아 있는데 맥 B 를 켠' 상황)의 고정 시각 픽스처.
    ///
    /// **왜 여기도 벽시계를 못 쓰는가**: 이 호스트군은 신호 공백을 계약 임계(7분) **바로 옆 ±60초**에 둔다.
    /// 그런데 픽스처는 URLProtocol 워커 스레드가 만들고 판정은 메인 액터가 하는데, 전체 스위트에서는 메인
    /// 액터가 60초 넘게 점유되는 일이 실제로 일어난다(같은 실행에서 여러 테스트가 "62.8초 후 통과"로 찍힌다).
    /// 그 지연이 그대로 공백에 더해지므로 '계약 안(-60초)'이 '계약 밖'으로 넘어가, 살아 있는 맥의 낮잠을
    /// 마감하지 말라는 R1 단언이 **무작위로** 빨개졌다(실측: `lastAutoClosedSessionID == nil` 실패).
    /// 시각을 고정하고 스토어의 주입 시계를 같은 값으로 맞추면 지연이 판정에 들어오지 않는다.
    static func ownerSignalFixture(forHost host: String?) -> StaleTodayFixture? {
        guard let gap = ownerSignalGap(for: host) else { return nil }
        let now = kst(hour: 12, minute: 0)
        return StaleTodayFixture(
            now: now,
            sessionStart: now.addingTimeInterval(-7_200),
            lastSeenAt: now.addingTimeInterval(-gap)
        )
    }

    // 기기별 소유 주장 표(work_status_devices) 픽스처. 기본은 **빈 목록**이다 — 이 표를 모르는 서버/구버전
    // 맥만 있는 상태와 같고, 앱은 그것을 '다른 맥 없음'이 아니라 '판정 불가'로 읽어야 한다.
    // host 에 "device-claim" 이 들어가면 다른 맥이 남긴 주장 한 줄을 돌려준다(파싱·결합 검증용).
    // host 에 "legacy-device-claim" 이 들어가면 **opened_session 키가 없는** 행을 돌려준다 —
    // 그 컬럼이 아직 없는 서버에서 행 전체가 디코드 실패로 사라지지 않는지(= 반납 규칙이 조용히 죽지 않는지) 검증용.
    private static func workStatusDevicesData(for request: URLRequest) -> Data {
        let host = request.url?.host
        if host?.contains("legacy-device-claim") == true {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "device_id": "AAAA-OTHER-MAC",
                    "session_id": "30000000-0000-0000-0000-000000000001",
                    "last_seen_at": "\(isoNow())"
                  }
                ]
                """.utf8
            )
        }
        guard host?.contains("device-claim") == true else {
            return Data("[]".utf8)
        }
        return Data(
            """
            [
              {
                "user_id": "00000000-0000-0000-0000-000000000002",
                "device_id": "AAAA-OTHER-MAC",
                "session_id": "30000000-0000-0000-0000-000000000001",
                "last_seen_at": "\(isoNow())",
                "opened_session": true
              }
            ]
            """.utf8
        )
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// 절대 시각 픽스처용 ISO8601 문자열(벽시계를 읽지 않는다).
    ///
    /// 여기 있던 `iso(offset:)`(= Date() + offset)은 전부 제거했다. 임계 근처의 상대 시각 픽스처는
    /// **픽스처를 만든 시각(워커 스레드)과 스토어가 판정한 시각(메인 액터)의 지연**을 그대로 오차로 흘려보내,
    /// 전체 스위트에서 메인 액터가 60초 넘게 점유될 때 계약 안/밖이 뒤집혔다. 새 픽스처가 필요하면
    /// staleTodayFixture / ownerSignalFixture 처럼 **고정 시각**을 쓰고 스토어에도 같은 값을 주입해라.
    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func workSessionsData(for request: URLRequest) -> Data {
        let host = request.url?.host
        let openQuery = request.url?.query?.contains("ended_at=is.null") == true

        if host == "today-hours-test" {
            if openQuery {
                return Data("[]".utf8)
            }
            return Data(
                """
                [
                  {
                    "id": "40000000-0000-0000-0000-000000000001",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-10T04:00:00Z",
                    "ended_at": "2026-07-10T05:00:00Z",
                    "duration_seconds": 3600
                  },
                  {
                    "id": "40000000-0000-0000-0000-000000000002",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-08T04:00:00Z",
                    "ended_at": "2026-07-08T04:30:00Z",
                    "duration_seconds": 1800
                  }
                ]
                """.utf8
            )
        }

        // 주 경계 걸침: 일요일 23시(KST)~월요일 1시(KST) 세션. 저장 duration 은 2시간이나 주 기여는 1시간이어야 한다.
        if host == "week-boundary-clip" {
            if openQuery { return Data("[]".utf8) }
            return Data(
                """
                [
                  {
                    "id": "70000000-0000-0000-0000-000000000001",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-05T14:00:00Z",
                    "ended_at": "2026-07-05T16:00:00Z",
                    "duration_seconds": 7200
                  }
                ]
                """.utf8
            )
        }

        // 하루 경계 걸침: 어제 23시(KST)~오늘 1시(KST) 세션. 저장 duration 은 2시간이나 오늘 기여는 1시간이어야 한다.
        if host == "day-boundary-clip" {
            if openQuery { return Data("[]".utf8) }
            return Data(
                """
                [
                  {
                    "id": "70000000-0000-0000-0000-000000000002",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-07T14:00:00Z",
                    "ended_at": "2026-07-07T16:00:00Z",
                    "duration_seconds": 7200
                  }
                ]
                """.utf8
            )
        }

        // 로그인 직후 회고 배너 경로 검증용: '지난주'(KST) 월요일 10~12시 완료 세션 하나.
        // 이 한 건이면 WeeklyRetro.build 가 non-nil 회고를 만들어 배너 판정이 성립한다.
        if host == "signin-retro-banner-test" {
            if openQuery { return Data("[]".utf8) }
            let lastWeekStart = TeamWeeklyGoal.koreanWeekStart(for: Date()).addingTimeInterval(-7 * 86_400)
            let formatter = ISO8601DateFormatter()
            let started = formatter.string(from: lastWeekStart.addingTimeInterval(10 * 3_600))
            let ended = formatter.string(from: lastWeekStart.addingTimeInterval(12 * 3_600))
            return Data(
                """
                [
                  {
                    "id": "80000000-0000-0000-0000-000000000001",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "\(started)",
                    "ended_at": "\(ended)",
                    "duration_seconds": 7200
                  }
                ]
                """.utf8
            )
        }

        // 자정 클리핑 계약 호스트군: 열린 세션 하나만 존재(완료 세션 없음 → 서버 today 합계 0).
        // 완료 세션이 0건이어야 '오늘 누적'이 오직 이 마감분에서만 나와, 계약이 다른 값에 묻히지 않는다.
        if let fixture = staleTodayFixture(forHost: host) {
            if openQuery {
                return Data(
                    """
                    [
                      {
                        "id": "50000000-0000-0000-0000-000000000002",
                        "user_id": "00000000-0000-0000-0000-000000000002",
                        "started_at": "\(iso(fixture.sessionStart))",
                        "ended_at": null,
                        "duration_seconds": null
                      }
                    ]
                    """.utf8
                )
            }
            return Data("[]".utf8)
        }

        // R1 호스트군: 2시간 전 시작한 열린 세션 하나(완료 세션 없음 → 서버 today 합계 0).
        if let fixture = ownerSignalFixture(forHost: host) {
            if openQuery {
                return Data(
                    """
                    [
                      {
                        "id": "51000000-0000-0000-0000-000000000001",
                        "user_id": "00000000-0000-0000-0000-000000000002",
                        "started_at": "\(iso(fixture.sessionStart))",
                        "ended_at": null,
                        "duration_seconds": null
                      }
                    ]
                    """.utf8
                )
            }
            return Data("[]".utf8)
        }

        // 자리 비움 자동 마감 검증: 아주 오래 전 시작한 열린 세션만 존재(완료 세션은 없음).
        if host?.contains("abandoned-session") == true {
            if openQuery {
                return Data(
                    """
                    [
                      {
                        "id": "50000000-0000-0000-0000-000000000001",
                        "user_id": "00000000-0000-0000-0000-000000000002",
                        "started_at": "2026-01-01T00:00:00Z",
                        "ended_at": null,
                        "duration_seconds": null
                      }
                    ]
                    """.utf8
                )
            }
            return Data("[]".utf8)
        }

        guard Self.hasTeamFixture(for: request) else {
            return Data("[]".utf8)
        }

        if openQuery {
            return Data(
                """
                [
                  {
                    "id": "30000000-0000-0000-0000-000000000001",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-01T01:00:00Z",
                    "ended_at": null,
                    "duration_seconds": null
                  }
                ]
                """.utf8
            )
        }

        // 완료(주간) 세션은 기준 시각의 주 안에 들도록 상대 시각으로 둔다(클리핑 후 2시간=7200 기여).
        // 주간 누적을 실제로 단언하는 team-hours-test 는 고정 기준시각(weeklyFixtureNow — KST 화요일 낮)을 쓴다.
        // 벽시계 now 를 쓰면 KST 월요일 00~02시에 'now-3h'가 지난주로 넘어가 클리핑 0이 되어 테스트가 시각 의존이 된다.
        let formatter = ISO8601DateFormatter()
        let now = (host == "team-hours-test") ? weeklyFixtureNow : Date()
        let started = formatter.string(from: now.addingTimeInterval(-3 * 3600))
        let ended = formatter.string(from: now.addingTimeInterval(-1 * 3600))
        return Data(
            """
            [
              {
                "id": "30000000-0000-0000-0000-000000000000",
                "user_id": "00000000-0000-0000-0000-000000000002",
                "started_at": "\(started)",
                "ended_at": "\(ended)",
                "duration_seconds": 7200
              }
            ]
            """.utf8
        )
    }

    private static func hasTeamFixture(for request: URLRequest) -> Bool {
        let host = request.url?.host
        return host == "team-hours-test"
            || host == "expired-token"
            || host == "stop-fails"
            || host == "signout-refresh-race"
            // 기기별 소유 주장 결합/스키마 부재 검증 호스트도 팀 픽스처가 필요하다(상태 행이 있어야
            // 그 행에 주장을 붙일 수 있고, 404 를 삼킨 뒤 폴링이 살아남았는지도 확인할 수 있다).
            || host?.contains("device-claim") == true
            || host == "status-device-table-missing"
            || host?.hasPrefix("korean-week-") == true
    }
}
