import Foundation
import Testing
@testable import check

// MARK: - v0.2.39: 3시간 미션이 "하루 1회"에서 "3시간마다 반복 지급(랩)"으로 바뀐다
//
// 서버 울트라 경제가 바뀌었다. 바뀐 것은 셋이고, 셋 다 **화면이 거짓말할 수 있는** 자리다:
//
//  ① 미션이 반복된다. 그날 누적 3시간마다 랩이 다시 열리고 그때마다 +1 이 들어온다. 그래서 서버는
//     3시간 줄의 `claimed` 를 **언제나 false** 로 보낸다(랩이 또 열려 있으니 "오늘 치는 받았다"로
//     닫을 수가 없다). `claimed` 만 읽던 화면은 오늘 세 개를 받고도 하루 종일 "아직 못 받았다"고 말한다.
//  ② `progress_seconds` 의 뜻이 바뀌었다. 예전엔 그날 총합이었고 지금은 **현재 랩의 진행**이다.
//     그날 총합은 새 키 `worked_seconds` 로 옮겨 갔다. 뜻만 바뀌고 키 이름은 그대로라, 이 둘을 안
//     가르면 7시간 일한 사람의 진행 바가 조용히 틀린 곳을 가리킨다.
//  ③ 잔량 상한이 5→3 으로 내려갔고, 가득 찬 상태에서 달성한 랩은 **영구 소멸**한다(예전엔 한 발 쓰면
//     그날 안에 되받았다). 그래서 상한 문구가 과거형에서 현재형 경고로 바뀌었다.
//
// 이 파일이 못 박는 것:
//  (가) **구서버 호환** — 새 키 3개가 통째로 없는 응답에서도 디코드가 살고, 값이 안전한 쪽으로 접힌다.
//       서버를 롤백하는 날 이게 없으면 화면이 "오늘 0개"라고 거짓말한다.
//  (나) **순수 변환 규칙** — 진행률은 현재 랩 기준, 랩 수는 오늘 행에서만, 문구는 남은 시간이 주어.
//  (다) **스로틀 키** — 랩 1은 기존 "hour3" 와 문자 그대로 같다(장부 연속성).
//  (라) **랩마다 발화** — 3·6·9시간 지점에서 각각 한 번씩 지갑 sync 를 킥한다. 하루 1회 키로는 첫 랩만
//       즉시 나가고 랩 2·3 은 5분 주기 sync 를 기다린다 — 받은 순간과 알려 주는 순간이 최대 5분 어긋난다.
//  (마) **문구 계약** — 제목·상한 경고·잔량 0 캡션·안내줄 2종이 글자 그대로.

// MARK: - 픽스처

/// 테스트 plist 는 **고정 이름**이다(UUID 접미어 없음 — 실행마다 ~/Library/Preferences 에 빈 plist 를 쌓지 않는다).
/// 스위트 이름을 테스트마다 **따로** 두는 이유: 스토어를 만들 때 `removePersistentDomain` 으로 도메인을
/// 비우므로, 같은 이름을 두 테스트가 나눠 쓰면 뒤에 시작한 쪽이 앞선 쪽의 마일스톤 장부를 지워 버린다
/// (그러면 이미 발화한 랩이 다시 발화해 요청 수 단언이 흔들린다).
private let v0239LapSuiteName = "check-v0239-ultra-lap-tests"
private let v0239EarlySuiteName = "check-v0239-ultra-lap-early-tests"
private let v0239NoticeSuiteName = "check-v0239-ultra-lap-notice-tests"
private let v0239FixtureSuiteName = "check-v0239-ultra-lap-fixture-tests"

private func v0239Defaults(_ suiteName: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 랩 하나의 길이. 서버 `mission_work_seconds()` 이자 `MissionProgress.defaultTargetSeconds` 다.
private let lapSeconds = 10_800

/// 시나리오의 고정 근무 시작(2026-08-19 05:00 KST). 벽시계를 읽지 않는 이유는 KST 자정 클리핑이다 —
/// `todayDuration` 은 진행 세션을 자정으로 자르므로, 새벽에 돌리면 9시간이 채워지지 않아 랩 3이
/// 발화하지 않는다(같은 함정을 PokePollGateTests 가 실측으로 잡았다). 05:00 시작 + 9시간 = 14:00 이라
/// 세 랩이 모두 같은 KST 날짜 안에 들어온다.
private let v0239WorkStart = Date(timeIntervalSince1970: 1_787_083_200)

/// 서버가 판정한 '오늘'(위 시각의 KST 날짜).
private let v0239Today = "2026-08-19"

@MainActor
private func v0239Store(host: String, suiteName: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: v0239Defaults(suiteName)
    )
    // 세션을 직접 주입해 로그인 흐름을 건너뛴다(지갑 sync 는 세션이 없으면 아예 발사하지 않는다).
    store.session = SupabaseSession(
        accessToken: "access-token",
        refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

/// 요청 기록은 프로세스 전역 버퍼라 테스트마다 고유 호스트로 격리하고, 여기서 경로로 한 번 더 좁힌다.
private func v0239WalletSyncCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host).filter { $0.url?.path == "/rest/v1/rpc/ultra_wallet_sync" }.count
}

/// 발사형(Task) 경로라 요청이 비동기로 도착한다. 폴링 없이 짧게 기다린다.
private func v0239WaitForWalletSync(host: String, expected: Int, timeout: TimeInterval = 60) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if v0239WalletSyncCount(host: host) >= expected { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// snake_case 응답을 실제 앱과 같은 설정으로 읽는 디코더(서비스 계층과 같은 전략이라야 키 매칭 함정을 잡는다).
private func v0239Decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

/// 미션 한 줄짜리 지갑 응답 JSON. 랩 3형제를 **넣은 판과 뺀 판**을 같은 뼈대에서 만든다 —
/// 두 판을 손으로 따로 적으면 "구서버와 신서버가 무엇이 다른가"가 흐려진다.
private func v0239WalletJSON(
    day: String = v0239Today,
    kstDay: String = v0239Today,
    targetSeconds: Int = lapSeconds,
    progressSeconds: Int,
    claimed: Bool = false,
    grantedNow: Bool = false,
    capped: Bool = false,
    lapKeys: (settled: Int, granted: Int, worked: Int)?
) -> Data {
    let laps = lapKeys.map {
        ",\"laps_settled\":\($0.settled),\"laps_granted\":\($0.granted),\"worked_seconds\":\($0.worked)"
    } ?? ""
    return Data(
        """
        {"status":"ok","balance":1,"balance_cap":3,"daily_floor":1,"day":"\(day)",
         "floor_applied":false,
         "missions":[{"key":"work3h","kst_day":"\(kstDay)","target_seconds":\(targetSeconds),
                      "progress_seconds":\(progressSeconds),"claimed":\(claimed),
                      "granted_now":\(grantedNow),"capped":\(capped)\(laps)}],
         "worked_seconds_closed":\(lapKeys?.worked ?? progressSeconds),"worked_seconds_open":0,
         "streak_days":3,"streak_includes_today":true,"measured_at":1787098516}
        """.utf8
    )
}

/// 응답 값 조립(HTTP 를 안 타는 순수 규칙 테스트 전용).
private func v0239Response(
    day: String = v0239Today,
    balance: Int = 1,
    missions: [UltraWalletResponse.MissionRow],
    workedSecondsClosed: Int = 0
) -> UltraWalletResponse {
    UltraWalletResponse(
        status: "ok",
        balance: balance,
        balanceCap: 3,
        dailyFloor: 1,
        day: day,
        floorApplied: false,
        missions: missions,
        workedSecondsClosed: workedSecondsClosed,
        workedSecondsOpen: 0,
        streakDays: 3,
        streakIncludesToday: true,
        measuredAt: 1
    )
}

// MARK: - (가) 디코딩 — 새 키가 있을 때와 **없을 때**

/// 랩 3형제가 실제 JSON 을 타고 들어온다. 직접 생성자로는 커스텀 `init(from:)` 의 누락을 원리적으로
/// 못 잡는다 — CodingKey 만 더하고 `decodeIfPresent` 를 빠뜨리면 값이 영원히 기본값이다.
///
/// ★ 키를 **카멜로** 적어야 하는 함정도 여기서 지킨다: 디코더가 `.convertFromSnakeCase` 라
///   `laps_granted` 는 매칭 전에 이미 `lapsGranted` 가 되어 있다. CodingKeys 에 스네이크로 적으면
///   어떤 키도 안 잡혀 셋 다 조용히 기본값이 되고, 화면은 "오늘 0개"라고 말한다.
@Test
func lapKeysRideThroughTheRealDecoder() throws {
    let response = try v0239Decoder().decode(
        UltraWalletResponse.self,
        // 7시간 일했고 랩 2개를 정산했다 → 현재 랩 진행은 25200 - 21600 = 3600.
        from: v0239WalletJSON(progressSeconds: 3_600, lapKeys: (settled: 2, granted: 2, worked: 25_200))
    )

    let row = try #require(response.missions.first)
    #expect(row.lapsSettled == 2)
    #expect(row.lapsGranted == 2)
    #expect(row.workedSeconds == 25_200)
    // 그날 총합과 현재 랩 진행은 **다른 수**다. 같은 값을 두 키에 담은 픽스처를 쓰면 둘을 뒤바꾼
    // 뮤턴트가 그대로 살아남는다.
    #expect(row.progressSeconds == 3_600)
    #expect(row.workedSeconds != row.progressSeconds)
    // 랩 서버는 그날 치를 닫지 못하므로 claimed 는 false 다(랩이 또 열려 있다).
    #expect(row.claimed == false)
}

/// **구서버 호환.** 랩 3형제를 통째로 모르는 서버(랩 전환 이전)가 실재한다. 그 응답에서 셋이
/// 비옵셔널이면 디코드가 통째로 throw 되어 잔량·미션·스트릭이 함께 사라지고, 화면은
/// "못 읽었어요"를 띄운다 — 실제 원인은 "곁가지 키 셋이 없다"인데.
///
/// 그리고 **접히는 값이 중요하다**:
///  - 랩 수는 0 이 안전한 쪽이다. 없는 랩을 지어내면 화면이 "오늘 N개"라고 거짓말한다.
///  - `worked_seconds` 만은 0 이 아니라 **`progressSeconds`** 로 접는다. 랩 이전 서버는
///    `progress_seconds` 에 그날 총합을 담았으므로 거기서 이 둘은 같은 수이고, 0 으로 접으면
///    총 근무초가 화면에서 사라진다(진단 줄이 "0분 일했다"고 말한다).
@Test
func missingLapKeysFoldToSafeDefaultsSoARollbackDoesNotLie() throws {
    let response = try v0239Decoder().decode(
        UltraWalletResponse.self,
        from: v0239WalletJSON(progressSeconds: 14_400, claimed: true, lapKeys: nil)
    )

    // 곁가지가 없다고 본체가 죽지 않았다.
    #expect(response.isOK)
    #expect(response.balance == 1)
    #expect(response.streakDays == 3)

    let row = try #require(response.missions.first)
    #expect(row.lapsSettled == 0)
    #expect(row.lapsGranted == 0)
    #expect(row.workedSeconds == 14_400, "0 으로 접으면 그날 총 근무초가 화면에서 통째로 사라진다.")
    #expect(row.workedSeconds == row.progressSeconds, "구서버에서는 이 둘이 같은 수다 — 그게 폴백의 근거다.")
    // 그 서버는 여전히 진짜 완료를 claimed 에 담는다. 그걸 계속 읽는 것이 롤백 호환의 나머지 절반이다.
    #expect(row.claimed)

    // 메모리와이즈 init 도 **같은 규칙**으로 접힌다. 두 생성 경로가 다른 값을 만들면 픽스처로 재현한
    // 화면과 실서버 화면이 갈린다.
    let handMade = UltraWalletResponse.MissionRow(
        key: "work3h", kstDay: v0239Today, targetSeconds: lapSeconds,
        progressSeconds: 14_400, claimed: true, grantedNow: false
    )
    #expect(handMade.lapsSettled == 0)
    #expect(handMade.lapsGranted == 0)
    #expect(handMade.workedSeconds == 14_400)
}

// MARK: - (나) 순수 변환 — 진행률·랩 수·문구

/// 문구의 주어가 '완료'가 아니라 **다음 하나까지 남은 시간**이다. 랩은 반복되므로 "다 했어요"라고
/// 말할 수 있는 순간이 하루 중 존재하지 않는다 — 그렇게 적으면 두 번째 랩부터는 화면이 침묵한다.
@Test
func missionDetailSpeaksInLapsNotInCompletion() {
    func detail(progressSeconds: Int, lapsGranted: Int) -> String {
        MissionProgress.rows(
            from: v0239Response(missions: [
                .init(key: "work3h", kstDay: v0239Today, targetSeconds: lapSeconds,
                      progressSeconds: progressSeconds, claimed: false, grantedNow: false,
                      capped: false, lapsSettled: lapsGranted, lapsGranted: lapsGranted,
                      workedSeconds: lapsGranted * lapSeconds + progressSeconds)
            ])
        )[0].detail
    }

    // ① 아직 하나도 못 받았다 → 개수를 말하지 않는다("오늘 0개"는 아무것도 알려 주지 않는 소음이다).
    #expect(detail(progressSeconds: 3_600, lapsGranted: 0) == "다음 하나까지 2시간")
    // ② 오늘 두 개 받았다 → 받은 수와 다음까지를 함께 말한다.
    #expect(detail(progressSeconds: 3_600, lapsGranted: 2) == "오늘 2개 · 다음까지 2시간")
    // ③ ★ remaining 이 0 인 순간. `max(0, target - done)` 이 없으면 여기서 음수가 나오고,
    //    hoursText 가 그걸 그대로 받아 "-1시간" 같은 말을 화면에 그린다.
    #expect(detail(progressSeconds: lapSeconds, lapsGranted: 1) == "오늘 1개 · 다음까지 0분")
    // ④ 구서버가 그날 총합(14400 > target)을 보내도 음수로 새지 않는다.
    #expect(detail(progressSeconds: 14_400, lapsGranted: 0) == "다음 하나까지 0분")
}

/// **진행 바는 현재 랩 기준이다.** 7시간 일하고 랩 2개를 정산한 사람의 진행률은 1.0 이 아니라
/// 3600/10800 이다. `worked_seconds` 를 진행 바에 물리면(옛 코드가 하던 대로 총합을 쓰면)
/// 그 사람의 바는 아침 9시부터 밤까지 100% 로 붙박여, 다음 하나까지 얼마나 남았는지 영영 알 수 없다.
@Test
func progressMeasuresTheCurrentLapNotTheWholeDay() {
    let rows = MissionProgress.rows(
        from: v0239Response(
            missions: [
                .init(key: "work3h", kstDay: v0239Today, targetSeconds: lapSeconds,
                      progressSeconds: 3_600, claimed: false, grantedNow: false,
                      capped: false, lapsSettled: 2, lapsGranted: 2, workedSeconds: 25_200)
            ],
            workedSecondsClosed: 25_200
        )
    )

    #expect(rows.map(\.kind) == [.todayThreeHours, .dailyFloor, .arrivalStreak])
    #expect(rows[0].progress == 3_600.0 / 10_800.0)
    #expect(rows[0].progress != 1.0, "총합을 진행 바에 물리면 하루 종일 100% 로 붙박인다.")
    #expect(rows[0].lapsGrantedToday == 2)
}

/// 오늘 받은 랩 수가 그대로 실려야 한다. 서버의 `claimed` 가 언제나 false 라, 이 수가 "오늘 뭔가
/// 받았다"를 화면에 나타내는 **유일한** 입력이다(아이콘 착색과 문구가 이걸 읽는다).
@Test
func lapsGrantedTodayRidesThroughAndDefaultsToZeroWithoutATodayRow() {
    let withRow = MissionProgress.rows(
        from: v0239Response(missions: [
            .init(key: "work3h", kstDay: v0239Today, targetSeconds: lapSeconds,
                  progressSeconds: 1_800, claimed: false, grantedNow: false,
                  capped: false, lapsSettled: 3, lapsGranted: 3, workedSeconds: 34_200)
        ])
    )
    #expect(withRow[0].lapsGrantedToday == 3)

    // 오늘 행이 아예 없는 아침(서버가 아직 그날을 평가하지 않았거나 근무가 0초다) → 0 이다.
    // 여기서 다른 수를 지어내면 아무것도 안 한 사람에게 "오늘 N개"라고 말하게 된다.
    let withoutRow = MissionProgress.rows(from: v0239Response(missions: []))
    #expect(withoutRow[0].lapsGrantedToday == 0)
    #expect(withoutRow[0].detail == "다음 하나까지 3시간")
}

/// **어제 행을 오늘 줄로 빨아들이지 않는다**(기존 규칙 — 회귀 방지).
/// `p_days_back=1` 이 함께 주는 어제 행은 **적립을 위해** 존재하는 것이지 화면의 '오늘 미션'이 아니다.
/// `kstDay == day` 대조를 지우면 어제 세 개를 받은 사람의 오늘 줄이 "오늘 3개"라고 말한다 —
/// 그리고 그 사람은 오늘 몫을 이미 받은 줄 알고 근무를 접는다.
@Test
func yesterdaysLapsNeverLeakIntoTodaysRow() {
    let rows = MissionProgress.rows(
        from: v0239Response(
            missions: [
                .init(key: "work3h", kstDay: "2026-08-18", targetSeconds: lapSeconds,
                      progressSeconds: 5_400, claimed: true, grantedNow: false,
                      capped: false, lapsSettled: 3, lapsGranted: 3, workedSeconds: 37_800)
            ],
            workedSecondsClosed: 1_800
        )
    )

    #expect(rows[0].lapsGrantedToday == 0, "어제 받은 랩이 오늘 줄로 새면 사용자는 오늘 몫을 포기한다.")
    #expect(rows[0].claimedToday == false)
    #expect(rows[0].detail == "다음 하나까지 2시간 30분", "개수 분기가 어제 값으로 켜지면 안 된다.")
    // 목표는 다른 날 행에서라도 읽어 온다(0/0 이 되어 바가 100% 로 튀는 것을 막는 기존 규칙).
    #expect(rows[0].progress == 1_800.0 / 10_800.0)
}

/// **`capped` 의 뜻이 바뀌었다.** 예전엔 "이번 호출에서 랩이 소멸했다"라 순간적이었다 — 가득 찬 사람은
/// 3시간마다 딱 한 번, 그 순간 팝오버를 열고 있어야만 문구를 볼 수 있었고 나머지 시간엔 사라졌다.
/// 이제는 **"지금 잔량이 상한 이상이다"** 를 뜻해서 가득 찬 동안 계속 떠 있는다.
///
/// 그래서 **랩이 하나도 소멸하지 않은 아침에도** capped 가 참일 수 있다(어제 받아 둔 잔량이 가득한 채
/// 출근한 사람). 그 조합에서 화면이 깨지면 안 된다: 진행 바는 그대로 그려지고 보조 문장만 경고로 덮인다.
@Test
func cappedMeansBalanceIsFullNotThatALapJustDied() {
    let rows = MissionProgress.rows(
        from: v0239Response(
            balance: 3,
            missions: [
                .init(key: "work3h", kstDay: v0239Today, targetSeconds: lapSeconds,
                      progressSeconds: 2_160, claimed: false, grantedNow: false,
                      capped: true, lapsSettled: 0, lapsGranted: 0, workedSeconds: 2_160)
            ]
        )
    )

    #expect(rows[0].cappedToday)
    // claimed 와 동시에 참일 수 없다 — 서버가 상한에서는 장부를 안 쓰기 때문이다.
    #expect(rows[0].claimedToday == false)
    // 진행률이 남아 있어야 사용자가 자기 근무가 어디쯤인지 본다(상한은 진행을 멈추지 않는다).
    #expect(rows[0].progress == 2_160.0 / 10_800.0)
    // 소멸을 여기서 말하지 않는다 — 뷰가 MissionCopy.cappedNotice 로 이 줄을 덮는다.
    #expect(rows[0].detail == "다음 하나까지 2시간 24분")
    #expect(MissionCopy.detail(rows[0]) == MissionCopy.cappedNotice)
}

// MARK: - (다) 스로틀 키 — 랩 1은 기존 키와 **문자 그대로** 같다

/// 랩 1에 새 이름을 붙이면 오늘 이미 3시간 지점에서 발화한 사용자가 같은 랩을 한 번 더 발화한다.
/// 멱등한 RPC 라 결과는 무해하지만 무료 플랜에서 불필요한 왕복이고, 무엇보다 마일스톤 장부의
/// 연속성이 끊긴다 — 어제까지 "hour3" 로 남은 기록과 오늘부터의 기록이 다른 이름이 되어
/// 같은 사건을 두 이름으로 세게 된다.
@Test
func lapOneKeepsTheOldMilestoneKeyVerbatim() {
    #expect(MilestoneTracker.ultraLapKey(1) == MilestoneTracker.hourThreeKey)
    #expect(MilestoneTracker.ultraLapKey(1) == "hour3", "상수를 바꿔치기해도 이 줄이 잡는다.")
    // 0·음수도 같은 자리로 접는다. 스토어는 `missionWorkSeconds <= 0` 일 때 랩을 0 으로 접는데
    // (서버가 준 target 이 0/음수여도 0 나눗셈으로 앱이 죽지 않게), 그 값이 여기로 들어와도
    // 새 이름을 만들어 내면 안 된다 — 장부에 아무도 모르는 키가 하나 생긴다.
    #expect(MilestoneTracker.ultraLapKey(0) == "hour3")
    #expect(MilestoneTracker.ultraLapKey(-1) == "hour3")

    // 그리고 랩마다 **다른** 키여야 한다. 전부 같은 문자열이면 스로틀이 하루 1회로 되돌아가고,
    // 랩 2·3 은 5분 주기 sync 를 기다리게 된다(받은 순간과 알려 주는 순간이 최대 5분 어긋난다).
    let keys = (1...4).map { MilestoneTracker.ultraLapKey($0) }
    #expect(Set(keys).count == 4, "랩 키가 겹친다 — 두 번째 랩부터 즉시 발화가 사라진다.")
    #expect(MilestoneTracker.ultraLapKey(2) == "hour3.lap2")
    #expect(MilestoneTracker.ultraLapKey(3) == "hour3.lap3")
    // 기존 마일스톤 키와도 안 겹친다(1시간·4시간 축하를 랩이 조용히 삼키면 안 된다).
    #expect(!keys.contains(MilestoneTracker.hourOneKey))
    #expect(!keys.contains(MilestoneTracker.hourFourKey))
}

// MARK: - (라) 랩마다 발화 — 3·6·9시간

/// **랩마다 한 번씩 지갑 sync 를 킥한다.** 이 호출 지점이 없으면 근무만 하고 패널을 안 연 사용자는
/// 그날 sync 가 5분 주기밖에 없어 랩을 받은 사실을 최대 5분 늦게 안다(그리고 하루 1회 키 시절에는
/// 랩 2·3 의 즉시 발화가 통째로 없었다).
///
/// 같은 랩에서 두 번 발화하지 않는 것도 함께 못 박는다 — 스로틀이 풀리면 근무 중 매초 호출되는
/// 이 함수가 무료 플랜에 초당 왕복을 낸다.
@MainActor
@Test
func everyLapKicksItsOwnWalletSyncExactlyOnce() async {
    let host = "v0239-lap-fire"
    let store = v0239Store(host: host, suiteName: v0239LapSuiteName)
    store.startedAt = v0239WorkStart
    store.accumulatedSeconds = 0
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: v0239WorkStart)

    // 랩 n 을 막 넘긴 시각(+60초 여유 — 경계에서 반올림 논쟁이 붙지 않게).
    func justPast(lap: Int) -> Date { v0239WorkStart.addingTimeInterval(Double(lap * lapSeconds + 60)) }

    // ① 3시간 → 1건.
    store.evaluateTimeMilestones(now: justPast(lap: 1))
    await v0239WaitForWalletSync(host: host, expected: 1)
    #expect(v0239WalletSyncCount(host: host) == 1)

    // ② 같은 랩에서 다시 평가해도 늘지 않는다.
    store.evaluateTimeMilestones(now: justPast(lap: 1).addingTimeInterval(60))
    try? await Task.sleep(for: .milliseconds(60))
    #expect(v0239WalletSyncCount(host: host) == 1, "같은 랩이 두 번 발화한다 — 근무 중 매초 왕복이 나간다.")

    // ③ 6시간 → 2건. 하루 1회 키였다면 여기서 멈춰 있다(이 줄이 이번 릴리스의 핵심 회귀 그물이다).
    store.evaluateTimeMilestones(now: justPast(lap: 2))
    await v0239WaitForWalletSync(host: host, expected: 2)
    #expect(v0239WalletSyncCount(host: host) == 2, "랩 2가 즉시 발화하지 않는다 — 스로틀 키가 하루 1회로 굳었다.")

    // ④ 9시간 → 3건.
    store.evaluateTimeMilestones(now: justPast(lap: 3))
    await v0239WaitForWalletSync(host: host, expected: 3)
    #expect(v0239WalletSyncCount(host: host) == 3)

    // ⑤ 랩 3 안에서 더 굴러도(9시간 30분) 늘지 않는다.
    store.evaluateTimeMilestones(now: justPast(lap: 3).addingTimeInterval(1_800))
    try? await Task.sleep(for: .milliseconds(60))
    #expect(v0239WalletSyncCount(host: host) == 3)
}

/// 위 테스트의 **음성 대조군**. 첫 랩을 못 채웠으면 한 건도 안 나간다 — 임계를 0으로 만드는 뮤턴트
/// (`lap >= 0` 이나 나눗셈 제거)는 이 줄이 없으면 초록으로 살아남는다.
@MainActor
@Test
func nothingFiresBeforeTheFirstLapCloses() async {
    let host = "v0239-lap-early"
    let store = v0239Store(host: host, suiteName: v0239EarlySuiteName)
    store.startedAt = v0239WorkStart
    store.accumulatedSeconds = 0
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: v0239WorkStart)

    // 2시간 59분 59초 — 1초만 모자라도 랩은 열리지 않는다.
    store.evaluateTimeMilestones(now: v0239WorkStart.addingTimeInterval(Double(lapSeconds - 1)))
    try? await Task.sleep(for: .milliseconds(60))

    #expect(v0239WalletSyncCount(host: host) == 0)
}

// MARK: - (마) 안내줄 — 하루에 여러 번 오는 문장이다

/// 연출(`.ultraCharged`)은 2초면 사라진다. 자리를 비운 사용자에게 그것만으로는 아무 증거도 남지
/// 않으므로 **지속 증거**를 같은 지점에서 남긴다(패널을 열면 이 줄이 그를 기다린다).
///
/// 랩 반복 지급이라 오늘 몫이 항상 1개는 아니다. 개수를 안 말하면 세 개를 받은 사람은 안내줄만 보고
/// 하나만 받은 줄 안다. 반대로 1개일 때 "(오늘 1개)"를 붙이면 아무것도 더 알려 주지 않는 소음이다.
@MainActor
@Test
func missionNoticeCountsTodaysLapsOnlyWhenThereIsMoreThanOne() {
    let store = v0239Store(host: "v0239-notice", suiteName: v0239NoticeSuiteName)

    func grant(lapsGranted: Int) -> UltraWalletResponse {
        v0239Response(missions: [
            .init(key: "work3h", kstDay: v0239Today, targetSeconds: lapSeconds,
                  progressSeconds: 600, claimed: false, grantedNow: true,
                  capped: false, lapsSettled: lapsGranted, lapsGranted: lapsGranted,
                  workedSeconds: lapsGranted * lapSeconds + 600)
        ])
    }

    store.applyUltraWallet(grant(lapsGranted: 1))
    #expect(store.missionNotice == "3시간 채웠어요 — 울트라 +1")

    // ★ 경계는 **2다.** 1과 3만 재면 `>= 2` 를 `>= 3` 으로 바꾼 뮤턴트가 살아남는다 —
    //   1은 어느 쪽이든 개수 없는 문구, 3은 어느 쪽이든 개수 있는 문구라 두 판본의 출력이 같다.
    //   실제로 뮤테이션에서 그 자리가 비어 있는 것이 드러나 이 줄을 더했다.
    store.applyUltraWallet(grant(lapsGranted: 2))
    #expect(store.missionNotice == "3시간 채웠어요 — 울트라 +1 (오늘 2개)")

    store.applyUltraWallet(grant(lapsGranted: 3))
    #expect(store.missionNotice == "3시간 채웠어요 — 울트라 +1 (오늘 3개)")

    // 랩 이전 서버는 laps_granted 를 안 보낸다(= 0). "오늘 0개"는 방금 받은 사람에게 거짓말이므로
    // 개수 없는 쪽으로 접는다.
    store.applyUltraWallet(grant(lapsGranted: 0))
    #expect(store.missionNotice == "3시간 채웠어요 — 울트라 +1")
}

// MARK: - 픽스처 왕복 — 스텁이 실서버 모양을 그대로 흘린다

/// 순수 함수 테스트는 규칙이 옳은지만 알고, 그 규칙에 들어가는 값이 실제 서버 모양인지는 모른다.
/// 이 테스트는 공용 스텁(URLProtocolStub 의 ultra_wallet_sync 픽스처)을 **HTTP → 디코더 → 스토어**
/// 로 통째로 태워, 픽스처가 옛 모양(claimed=true + progress=총합)으로 되돌아가면 빨개진다.
@MainActor
@Test
func theSharedFixtureFeedsTheStoreTheNewServerShape() async throws {
    // 호스트 이름의 "wallet-laps3" 가 "오늘 랩 3개를 정산했다"를 고른다.
    let host = "v0239-wallet-laps3-roundtrip"
    let store = v0239Store(host: host, suiteName: v0239FixtureSuiteName)

    await store.performSyncUltraWallet(reason: .panelOpen)

    #expect(store.ultraBalanceFailed == false)
    #expect(store.missionsLoaded)
    // 상한은 서버가 말한 값을 그대로 쓴다(클라가 리터럴을 박으면 서버가 바꿔도 화면만 옛 숫자를 말한다).
    #expect(store.ultraBalanceCap == 3)

    let row = try #require(store.missions.first { $0.kind == .todayThreeHours })
    #expect(row.lapsGrantedToday == 3)
    // 진행 바는 **현재 랩** 기준이다(그날 총합 33300 이 아니라 900/10800).
    #expect(row.progress == 900.0 / 10_800.0)
    #expect(row.claimedToday == false, "랩 서버의 claimed 는 언제나 false 다.")
    #expect(row.detail == "오늘 3개 · 다음까지 2시간 45분")
    // 방금 받았으므로(granted_now=true) 지속 증거가 개수와 함께 남는다.
    #expect(store.missionNotice == "3시간 채웠어요 — 울트라 +1 (오늘 3개)")
}

// MARK: - 문구 계약 — 글자 그대로

/// 화면의 말이 경제와 어긋나면 사용자가 잃는 것은 울트라 하나가 아니라 이 화면 전체에 대한 신뢰다.
/// 그래서 리터럴로 못 박는다(같은 문장을 뷰가 다시 적지 않는다는 계약은 CheckMenuRenderTests 가 지킨다).
@Test
func lapEconomyCopyIsCharacterForCharacter() {
    // 제목: 하루 한 번 끝나는 퀘스트가 아니라 3시간마다 다시 열리는 랩이다. "오늘 3시간"으로 적으면
    // 한 번 채운 사람은 그날 남은 근무에서 더 받을 게 없다고 읽는다.
    #expect(MissionCopy.title(.todayThreeHours) == "근무 3시간마다")

    // 상한 경고: `capped` 가 "지금 잔량이 가득이다"로 바뀌어 가득한 동안 계속 떠 있으므로,
    // 아직 아무것도 안 놓친 사람에게도 뜬다 — 과거형("놓쳤어요")은 그 사람에게 거짓말이다.
    // v0.2.41 에서 뒷말이 한 번 더 바뀌었다: 소멸이 **대기**가 되어(20260903190000) 안 써도 하나는 남는다.
    #expect(MissionCopy.cappedNotice == "가득 찼어요 — 3시간을 채워도 대기해요")

    // 잔량 0 캡션: 0개인 사람이 알아야 할 것은 미션 화면이 어디 있는지가 아니라 **언제 다시 생기는지**다.
    #expect(UltraPanelCopy.heroCaption(balance: 0, hasFailed: false) == "근무 3시간마다 하나씩 생겨요")
    // 잔량이 있는 사람에게는 여전히 쓰는 법을 말한다(0 분기만 바뀌었다는 대조군).
    #expect(UltraPanelCopy.heroCaption(balance: 1, hasFailed: false).contains(UltraChargeStyle.holdSecondsText))
    #expect(UltraPanelCopy.heroCaption(balance: 1, hasFailed: false) != UltraPanelCopy.heroCaption(balance: 0, hasFailed: false))

    // 칩 선택 구조는 그대로다: 상한 → 받음 → 보상. 순서를 바꾸면 상한에 걸린 줄이 보상 칩을 그려
    // **줄 수 없는 것을 약속**한다.
    let capped = MissionProgress(kind: .todayThreeHours, progress: 1, claimedToday: false,
                                 cappedToday: true, detail: "다음 하나까지 0분", lapsGrantedToday: 2)
    #expect(MissionCopy.chip(capped) == .capped)
}
