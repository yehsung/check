import Foundation
import Testing
@testable import check

// MARK: - v0.2.41: 가득 찬 상태의 3시간 달성은 **소멸이 아니라 대기**다
//
// 사장님 지시: "다 차 있는 상태인데 달성하면 달성한 상태 그대로 유지하다가, 소모하면 퀘스트를 달성한
// 걸로 하고 지급하고 다시 3시간을 돌게끔." 정정: **대기는 최대 1개**이고 대기 중에는 카운터가 멈춘다
// ("꽉 찬 상태를 계속 대기해주면서 시간을 계속 카운트하면 최대 보유 3회로 제한한 이유가 없잖아").
//
// 서버(20260903190000)가 `missions[].pending` 을 새로 보낸다. 이 파일이 못 박는 것은 넷이다:
//  (가) **디코드** — 키가 있을 때와 **없을 때**(구서버). 없으면 false 로 접는다: 대기를 지어내면
//       화면이 "하나 쓰면 받아요"라고 약속하는데 그 서버는 줄 것이 없다(그쪽에선 소멸했다).
//  (나) **순수 변환** — 대기는 **오늘 행**에서만 온다. 어제 행에서 새면 이미 끝난 약속을 다시 말한다.
//  (다) **문구와 우선순위** — 대기 중이면 `capped` 도 반드시 참이라, 대기를 **먼저** 말하지 않으면
//       채워 둔 하나가 있다는 사실이 화면에서 통째로 사라진다.
//  (라) **발사 직후 지갑 sync** — 서버는 "잔량이 상한 밑으로 내려간 다음 sync"에 대기분을 준다.
//       발사 성공 지점에서 걷어차지 않으면 그 사람은 최대 5분(.periodic 스로틀)을 기다린다.
//       랩 스로틀 키는 **로컬 누적 근무초**로 오르는 별개의 발화라(울트라를 써도 그 값은 안 움직인다)
//       잔량이 줄어드는 순간을 잡아 주지 못한다 — 그래서 여기가 유일한 즉시 경로다.
//  (마) **서버 계약** — 마이그레이션 소스가 상태 기계와 권한 미부여를 실제로 담고 있는가.

// MARK: - 픽스처

private let v0241Today = "2026-09-04"
private let v0241Yesterday = "2026-09-03"
private let v0241LapSeconds = 10_800

private func v0241Decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

/// 미션 한 줄짜리 지갑 응답 JSON. `pending` 키를 **넣은 판과 뺀 판**을 같은 뼈대에서 만든다 —
/// 두 판을 손으로 따로 적으면 "구서버와 신서버가 무엇이 다른가"가 흐려진다.
private func v0241WalletJSON(
    progressSeconds: Int = 10_800,
    capped: Bool = true,
    pending: Bool?,
    grantedNow: Bool = false,
    balance: Int = 3
) -> Data {
    let pendingKey = pending.map { ",\"pending\":\($0)" } ?? ""
    return Data(
        """
        {"status":"ok","balance":\(balance),"balance_cap":3,"daily_floor":1,"day":"\(v0241Today)",
         "floor_applied":false,
         "missions":[{"key":"work3h","kst_day":"\(v0241Today)","target_seconds":\(v0241LapSeconds),
                      "progress_seconds":\(progressSeconds),"claimed":false,
                      "granted_now":\(grantedNow),"capped":\(capped),
                      "laps_settled":0,"laps_granted":0,"worked_seconds":21600\(pendingKey)}],
         "worked_seconds_closed":21600,"worked_seconds_open":0,
         "streak_days":3,"streak_includes_today":true,"measured_at":1787098516}
        """.utf8
    )
}

private func v0241Response(
    balance: Int = 3,
    missions: [UltraWalletResponse.MissionRow]
) -> UltraWalletResponse {
    UltraWalletResponse(
        status: "ok",
        balance: balance,
        balanceCap: 3,
        dailyFloor: 1,
        day: v0241Today,
        floorApplied: false,
        missions: missions,
        workedSecondsClosed: 21_600,
        workedSecondsOpen: 0,
        streakDays: 3,
        streakIncludesToday: true,
        measuredAt: 1
    )
}

// MARK: - (가) 디코딩 — pending 이 있을 때와 **없을 때**

/// 실제 디코더를 태운다. 직접 생성자로는 커스텀 `init(from:)` 의 누락을 원리적으로 못 잡는다 —
/// CodingKey 만 더하고 `decodeIfPresent` 를 빠뜨리면 값이 영원히 기본값이고, 그러면 대기가
/// 서버에서 화면까지 오는 길이 통째로 끊긴 채 모든 순수 테스트가 초록이다.
///
/// ★ 키를 **카멜로** 적어야 하는 함정도 여기서 지킨다(디코더가 `.convertFromSnakeCase` 다).
@Test
func pendingRidesThroughTheRealDecoder() throws {
    let response = try v0241Decoder().decode(UltraWalletResponse.self, from: v0241WalletJSON(pending: true))
    let row = try #require(response.missions.first)
    #expect(row.pending)
    // 대기와 가득 참은 **다른 축**이다. 같은 값을 두 키에 담은 픽스처를 쓰면 둘을 뒤바꾼 뮤턴트가 산다.
    #expect(row.capped)
    #expect(row.claimed == false, "대기 중에도 claimed 는 false 다 — 랩이 또 열려 있다.")
    // 대기 중 진행도는 서버가 target 에 고정해 보낸다(카운터 정지). 화면의 바가 100%로 차는 근거다.
    #expect(row.progressSeconds == row.targetSeconds)
}

/// **구서버 호환.** `pending` 을 통째로 모르는 서버(대기 규칙 이전)가 실재한다. 비옵셔널이면
/// 디코드가 throw 되어 잔량·미션·스트릭이 함께 사라지고 화면은 "못 읽었어요"를 띄운다.
///
/// 그리고 **접히는 값이 중요하다**: 없으면 false 다. 대기를 지어내면 "하나 쓰면 받아요"라고
/// 약속하게 되는데, 그 서버에서 그 랩은 이미 소멸해 아무리 써도 들어오지 않는다.
@Test
func missingPendingFoldsToFalseSoWeNeverPromiseWhatAnOlderServerCannotGive() throws {
    let response = try v0241Decoder().decode(UltraWalletResponse.self, from: v0241WalletJSON(pending: nil))
    #expect(response.isOK)
    #expect(response.balance == 3)
    let row = try #require(response.missions.first)
    #expect(row.pending == false, "모를 때 대기라고 말하면, 아무리 써도 안 들어오는 약속을 하는 것이다.")
    #expect(row.capped, "곁가지 하나가 없다고 본체(가득 참 경고)가 죽으면 안 된다.")

    // 멤버와이즈 init 도 **같은 규칙**으로 접힌다(두 생성 경로가 갈리면 픽스처 화면과 실서버 화면이 갈린다).
    let handMade = UltraWalletResponse.MissionRow(
        key: "work3h", kstDay: v0241Today, targetSeconds: v0241LapSeconds,
        progressSeconds: 10_800, claimed: false, grantedNow: false, capped: true
    )
    #expect(handMade.pending == false)
}

// MARK: - (나) 순수 변환 — 대기는 오늘 행에서만 온다

/// 서버의 `pending` 이 표시 타입까지 그대로 실려야 한다. 여기서 끊기면 화면은 대기 중인 사람에게
/// 그냥 "가득 찼어요"만 말하고, 그 사람은 자기가 이미 채워 둔 하나가 있다는 것을 모른다.
@Test
func pendingReachesTheDisplayRowAndOnlyFromTodaysRow() {
    let today = MissionProgress.rows(
        from: v0241Response(missions: [
            .init(key: "work3h", kstDay: v0241Today, targetSeconds: v0241LapSeconds,
                  progressSeconds: 10_800, claimed: false, grantedNow: false, capped: true,
                  lapsSettled: 0, lapsGranted: 0, workedSeconds: 21_600, pending: true)
        ])
    )
    #expect(today[0].isPending)
    #expect(today[0].cappedToday, "대기 중이면 잔량은 반드시 가득이다 — 서버는 이 조합만 보낸다.")
    // 진행 바는 100%로 찬다(서버가 progress 를 target 에 고정해 보내기 때문이다).
    #expect(today[0].progress == 1.0)

    // ★ 어제 행의 대기는 오늘 줄로 새면 안 된다. 어제 대기했다가 오늘 이미 받은 사람의 줄이
    //   "하나 쓰면 받아요"라고 말하면, 그 사람은 안 오는 것을 기다리며 울트라를 한 발 태운다.
    let yesterdayOnly = MissionProgress.rows(
        from: v0241Response(missions: [
            .init(key: "work3h", kstDay: v0241Yesterday, targetSeconds: v0241LapSeconds,
                  progressSeconds: 0, claimed: false, grantedNow: false, capped: true,
                  lapsSettled: 1, lapsGranted: 1, workedSeconds: 32_400, pending: true)
        ])
    )
    #expect(yesterdayOnly[0].isPending == false)

    // 오늘 행이 아예 없는 아침도 false 다(없는 약속을 지어내지 않는다).
    #expect(MissionProgress.rows(from: v0241Response(missions: []))[0].isPending == false)
    // 대기가 아닌 오늘 행은 그대로 false — 대조군이 없으면 `true` 상수 뮤턴트가 살아남는다.
    let plain = MissionProgress.rows(
        from: v0241Response(missions: [
            .init(key: "work3h", kstDay: v0241Today, targetSeconds: v0241LapSeconds,
                  progressSeconds: 3_600, claimed: false, grantedNow: false, capped: false,
                  lapsSettled: 0, lapsGranted: 0, workedSeconds: 3_600, pending: false)
        ])
    )
    #expect(plain[0].isPending == false)
}

// MARK: - (다) 문구와 우선순위 — 대기가 가득 참을 **덮는다**

/// 화면의 말이 경제와 어긋나면 사용자가 잃는 것은 울트라 하나가 아니라 이 화면 전체에 대한 신뢰다.
/// 그래서 리터럴로 못 박는다(같은 문장을 뷰가 다시 적지 않는다는 계약은 CheckMenuRenderTests 가 지킨다).
@Test
func pendingCopyIsCharacterForCharacterAndOutranksTheFullWarning() {
    #expect(MissionCopy.pendingChip == "대기 중")
    #expect(MissionCopy.pendingNotice == "3시간 채웠어요 — 하나 쓰면 받아요")
    // 소멸이 대기로 바뀌었으므로 "놓쳐요"는 이제 거짓말이다 — 안 써도 하나는 남아 기다린다.
    #expect(MissionCopy.cappedNotice == "가득 찼어요 — 3시간을 채워도 대기해요")
    #expect(MissionCopy.cappedNotice.contains("놓") == false, "소멸 어휘가 되살아나면 없는 손실을 말하게 된다.")

    // ★ 실제 서버 상태: 대기 중이면 capped 도 참이다. 그 조합에서 **대기가 이긴다.**
    let waiting = MissionProgress(kind: .todayThreeHours, progress: 1, claimedToday: false,
                                  cappedToday: true, detail: "다음 하나까지 0분",
                                  lapsGrantedToday: 0, isPending: true)
    #expect(MissionCopy.chip(waiting) == .pending)
    #expect(MissionCopy.detail(waiting) == MissionCopy.pendingNotice)
    #expect(MissionCopy.detail(waiting) != MissionCopy.cappedNotice)

    // 대조군 ①: 가득 찼지만 아직 못 채운 아침 → 예전 그대로 경고다.
    let full = MissionProgress(kind: .todayThreeHours, progress: 0.2, claimedToday: false,
                               cappedToday: true, detail: "다음 하나까지 2시간 24분")
    #expect(MissionCopy.chip(full) == .capped)
    #expect(MissionCopy.detail(full) == MissionCopy.cappedNotice)

    // 대조군 ②: 평상시 줄은 보상 칩과 진행 문장을 그대로 유지한다(회귀 방지).
    let plain = MissionProgress(kind: .todayThreeHours, progress: 0.4, claimedToday: false,
                                cappedToday: false, detail: "다음 하나까지 1시간 48분")
    #expect(MissionCopy.chip(plain) == .reward("⚡︎ +1"))
    #expect(MissionCopy.detail(plain) == plain.detail)

    // 대조군 ③: `.claimed` 가지는 밑바닥 보정 줄에서 여전히 살아 있다(대기를 앞에 얹었을 뿐
    //   기존 세 상태의 순서는 건드리지 않았다는 증거).
    let floorClaimed = MissionProgress(kind: .dailyFloor, progress: nil, claimedToday: true,
                                       cappedToday: false, detail: "잔량 0이면 1개로")
    #expect(MissionCopy.chip(floorClaimed) == .claimed)
    // 보상이 없는 줄(연속 출근)은 대기여도 칩을 안 그린다 — 사장님 확정 3(스트릭 보상 없음)이 먼저다.
    let streak = MissionProgress(kind: .arrivalStreak, progress: nil, claimedToday: false,
                                 cappedToday: false, detail: "5일 연속", lapsGrantedToday: 0, isPending: true)
    #expect(MissionCopy.chip(streak) == .none)
}

// MARK: - (라) 발사 성공이 지갑 sync 를 걷어찬다

/// 울트라 발사 성공 · 지갑 sync 두 경로를 함께 답하고 **요청을 기록**하는 스텁.
/// 공용 URLProtocolStub 은 ultra_poke_user 를 모르고, UltraSequenceURLProtocol 은 다른 경로를
/// 기록하지 않는다 — 이 테스트는 "발사 뒤에 지갑 요청이 나갔는가"를 세야 하므로 둘 다 필요하다.
final class V0241PendingURLProtocol: URLProtocol {
    static let ultraPath = "/rest/v1/rpc/ultra_poke_user"
    static let walletPath = "/rest/v1/rpc/ultra_wallet_sync"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var pathsByHost: [String: [String]] = [:]

    static func reset(host: String) {
        lock.lock(); defer { lock.unlock() }
        pathsByHost[host] = []
    }

    static func paths(forHost host: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return pathsByHost[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [V0241PendingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.pathsByHost[host, default: []].append(path)
        Self.lock.unlock()

        let data: Data
        switch path {
        case Self.ultraPath:
            // 발사 성공. 잔량이 3 → 2 로 내려가는 그 순간이 서버가 대기분을 지급하는 조건이다.
            data = Data(#"{"status":"ok","ultra_balance":2,"ultra_remaining":2,"ring":"sent"}"#.utf8)
        case Self.walletPath:
            // 그 다음 sync 는 대기분을 지급한 뒤의 모습(granted_now=true, pending 은 이미 false).
            data = v0241WalletJSON(progressSeconds: 0, capped: false, pending: false,
                                   grantedNow: true, balance: 3)
        default:
            data = Data("[]".utf8)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private func v0241Store(host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: V0241PendingURLProtocol.session()
    )
    let suiteName = "check-v0241-ultra-pending-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.startedAt = Date()
    return store
}

/// **발사 성공 직후 지갑 sync 를 한 번 부른다.**
///
/// 서버는 대기 중인 랩을 "잔량이 상한 밑으로 내려간 **다음** sync"에 지급한다. 잔량이 줄어드는 순간은
/// 이 발사 하나뿐이다. 랩 스로틀 키(`ultraLapKey`)는 대신해 주지 못한다 — 그 키는 로컬 누적 근무초
/// (`todayDuration`)를 3시간으로 나눈 값이라 대기 중에도 6·9시간에서 오르지만, **울트라를 써도 그 값은
/// 1초도 안 움직인다.** 그래서 이 호출이 없으면 방금 하나를 쓴 사람이 최대 5분을 기다린다.
@MainActor
@Test
func firingAnUltraKicksAWalletSyncSoThePendingLapArrivesNow() async {
    let host = "v0241-pending-fire"
    V0241PendingURLProtocol.reset(host: host)
    let store = v0241Store(host: host)
    store.applyUltraBalance(3)

    store.sendUltraPoke(to: "teammate")

    // 발사 → 지갑 두 요청이 다 도착할 때까지 짧게 기다린다(발사형 Task 경로다).
    for _ in 0..<400 {
        if V0241PendingURLProtocol.paths(forHost: host).contains(V0241PendingURLProtocol.walletPath) { break }
        try? await Task.sleep(for: .milliseconds(5))
    }

    let paths = V0241PendingURLProtocol.paths(forHost: host)
    #expect(paths.filter { $0 == V0241PendingURLProtocol.ultraPath }.count == 1)
    #expect(
        paths.filter { $0 == V0241PendingURLProtocol.walletPath }.count == 1,
        "발사 성공이 지갑 sync 를 안 걷어찼다 — 대기분이 최대 5분 늦게 들어온다(요청: \(paths))."
    )
    // 순서도 계약이다: 잔량이 줄어든 **뒤에** 물어야 서버가 대기분을 지급할 수 있다.
    let ultraIndex = paths.firstIndex(of: V0241PendingURLProtocol.ultraPath)
    let walletIndex = paths.firstIndex(of: V0241PendingURLProtocol.walletPath)
    #expect(ultraIndex != nil && walletIndex != nil && ultraIndex! < walletIndex!)

    // 그리고 그 응답이 실제로 반영된다(요청만 나가고 버려지면 화면은 여전히 옛 숫자를 말한다).
    for _ in 0..<400 {
        if store.ultraBalance == 3 { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(store.ultraBalance == 3, "대기분 지급이 화면 잔량에 반영되지 않았다.")
    #expect(store.missionNotice == "3시간 채웠어요 — 울트라 +1")
}

// MARK: - (마) 서버 계약 — 마이그레이션 소스

private func v0241RepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// SQL 의 `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 되고,
/// 더 나쁘게는 주석에 적어 둔 문장만으로 계약이 통과한다). 문자열 안의 `--` 는 보존한다.
private func v0241StrippingSQLComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inString {
            result.append(c)
            if c == "'" { inString = false }
        } else if c == "-", next == "-" {
            inLineComment = true
            i += 1
        } else {
            if c == "'" { inString = true }
            result.append(c)
        }
        i += 1
    }
    return result
}

/// 서버 마이그레이션 계약(20260903190000). 파일이 없으면(supabase/ 없는 체크아웃) 다른 SQL 계약
/// 테스트와 같이 **빨강**이다 — 조용히 통과하면 계약이 검사되지 않은 채 초록으로 보인다.
@Test
func migrationContractUltraPendingLap() throws {
    let sql = v0241StrippingSQLComments(
        try String(contentsOf: v0241RepoURL("supabase/migrations/20260903190000_ultra_pending_lap.sql"),
                   encoding: .utf8)
    )

    // ① 상태 컬럼 3개.
    for column in ["ultra_quest_day date",
                   "ultra_quest_base_sec bigint not null default 0",
                   "ultra_quest_pending boolean not null default false"] {
        #expect(sql.contains("add column if not exists \(column)"), "상태 컬럼 정의 누락: \(column)")
    }
    // ② ★ 그 컬럼에 grant 를 주지 않는다(위조 방어). grant 로 시작하는 줄 어디에도 없어야 한다.
    let grantLines = sql.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("grant") }
    #expect(
        grantLines.allSatisfy { !$0.contains("ultra_quest") },
        "퀘스트 상태 컬럼에 grant 가 걸렸다 — 진행도가 클라에서 위조 가능해진다: \(grantLines)"
    )
    #expect(sql.contains("has_column_privilege('authenticated'"), "권한 미부여 단언이 없다.")
    // 랩 번호 헬퍼도 definer 전용이다 — 클라에 열면 남의 장부 지급 수를 헤아릴 수 있다.
    #expect(
        grantLines.allSatisfy { !$0.contains("ultra_work3h_laps") },
        "랩 번호 헬퍼에 grant 가 걸렸다 — definer 전용 계약 위반: \(grantLines)"
    )
    #expect(sql.contains("revoke all on function public.ultra_work3h_laps(uuid, date) from anon, authenticated;"),
            "랩 번호 헬퍼의 실행권 회수가 없다.")

    // ③ 랩 reason 규약은 그대로다(랩 1을 바꾸면 어제 몫이 전원에게 이중 지급된다).
    #expect(sql.contains("'mission:work3h'"))
    #expect(sql.contains("'mission:work3h#'"))
    // ④ ★ 소멸 경로가 사라졌다. 이 insert 가 돌아오면 대기해야 할 랩이 '정산됨'으로 굳는다.
    #expect(!sql.contains("'capped', true"), "delta 0 소멸 행 insert 가 돌아왔다 — 대기가 영영 안 온다.")
    // ⑤ 대기 상태 기계의 판정들.
    //    대기 플래그를 세우는 자리는 **둘**이다: 오늘 루프의 상한 분기와, 어제 따라잡기의 상한 분기.
    //    뒤쪽이 빠지면 "앱을 켜 두었으면 대기, 꺼 두었으면 소멸"로 같은 근무가 갈린다.
    #expect(
        sql.components(separatedBy: "v_q_pending := true;").count - 1 == 2,
        "대기 플래그를 세우는 자리가 2곳이 아니다 — 어느 한쪽에서 가득 찬 달성이 그냥 사라진다."
    )
    #expect(sql.contains("v_q_base := v_today_sec;"), "대기 지급이 base 를 지금으로 안 옮긴다 — 시간이 이월된다.")
    #expect(sql.contains("v_q_base := v_q_base + v_target_sec;"), "정상 지급이 target 만큼만 전진하지 않는다.")
    #expect(sql.contains("case when v_q_pending then v_target_sec"), "대기 중 진행도 고정이 없다.")
    #expect(sql.contains("not v_was_pending"), "따라잡기가 대기 여부를 안 본다 — 같은 랩을 두 번 준다.")
    #expect(sql.contains("'pending_paid', true"), "대기 지급이 감사에서 구분되지 않는다.")

    // ⑤-b ★ 장부 reason 슬롯은 **이미 쓰인 최대 랩 번호 + 1** 이다(그날 지급 개수 + 1 이 아니다).
    //     ⑦의 일회성 삭제가 장부 가운데에 구멍을 남기므로(프로덕션 실장부: `[work3h(삭제), #2(지급)]`),
    //     개수 + 1 은 이미 쓰인 자리를 가리켜 유니크 인덱스에 삼켜지고 대기가 그날 자정까지 안 풀린다.
    #expect(
        sql.components(separatedBy: "greatest(v_lap_hi, v_paid_cnt) + 1").count - 1 == 3,
        "슬롯 계산이 세 지급 지점(대기·어제 따라잡기·오늘 루프)에 모두 있지 않다."
    )
    #expect(!sql.contains("v_paid_cnt + 1"), "reason 슬롯이 다시 '개수 + 1' 로 만들어진다 — 구멍에서 지급이 삼켜진다.")
    #expect(sql.contains("create function public.ultra_work3h_laps(p_uid uuid, p_day date,"),
            "랩 번호 헬퍼가 없다 — 같은 계산이 다시 복사됐다.")
    // ⑤-c ★ 배포 첫 sync(상태 null)의 기준선은 **장부에서** 온다. 0 으로 잡으면 오늘 이미 받고
    //     소비까지 끝낸 랩을 같은 근무로 다시 준다(상한에 닿을 때까지 — 슬롯이 단조라 인덱스는 못 막는다).
    #expect(sql.contains("v_q_base := v_paid_cnt::bigint * v_target_sec;"),
            "롤오버 기준선이 장부에서 오지 않는다 — 배포 첫 sync 가 이미 받은 랩을 다시 지급한다.")
    #expect(!sql.contains("v_q_base := 0;"), "롤오버가 기준선을 0 으로 되돌린다 — 배포 첫 sync 이중 지급.")
    // ⑤-d ★ 어제 따라잡기는 상태가 '정확히 어제'일 때만 도는 것이 아니다. 좁히면 배포 당일 전원
    //     (상태 null)의 어제 몫이 통째로 사라지고, ⑦의 어제 삭제가 아무 일도 못 한다.
    #expect(sql.contains("if v_q_day is null or v_q_day <= v_yday then"),
            "어제 따라잡기가 '상태 = 어제' 로 좁혀졌다 — 배포 당일 어제 몫이 사라진다.")
    #expect(sql.contains("else v_paid_cnt::bigint * v_target_sec end"),
            "어제 기준선이 장부에서 오지 않는다 — 어제 이미 받은 사람에게 또 지급된다.")
    // ⑥ 응답 계약: pending 키를 오늘 행에서만 참으로 보낸다.
    #expect(sql.contains("'pending', (v_i = 0 and v_q_pending)"))
    // ⑦ 일회성 정정은 오늘·어제로 **한정**된다(과거는 역사로 보존).
    #expect(sql.contains("and (detail->>'capped') = 'true'"))
    #expect(sql.contains("and kst_day in (today, today - 1)"))
    // ⑧ 실행권과 프로브 롤백.
    #expect(sql.contains("grant  execute on function public.ultra_wallet_sync(int) to authenticated;"))
    #expect(sql.contains("raise exception 'ULTRA_PENDING_LAP_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'ULTRA_PENDING_LAP_PROBE_ROLLBACK' then"))
    // ⑨ 표를 새로 만들지 않는다(PostgREST 임베드 모호성 PGRST201 회피 — 20260802120000 사고).
    #expect(!sql.contains("create table"))
}
