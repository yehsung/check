#if os(macOS)
import Foundation
import Observation

// MARK: - 리밋 스토어 (맥 전용 · @MainActor · 10분 간격 · 영속)
//
// 선례는 둘이다.
//  · 간격·영속·상태 관리는 `CodexAccountUsageStore` 를 본떴다(스탬프를 러너 **전에** 찍어 실패도 간격을
//    지키게 하는 관용구, `inert()` 기본값으로 주입을 잊은 테스트가 프로세스를 띄우지 못하게 하는 fail-closed).
//  · 외부 HTTP 의 조용한 실패는 `UpdateCheckStore` 를 본떴다(주입형 fetcher · 실패는 사용자를 방해하지 않는다).
//
// ## 왜 주기가 10분이고 강제 갱신에도 5분 하한이 있는가
// Claude 의 사용량 엔드포인트는 **5분에 5회**가 상한이고 6번째부터 429 `retry-after: 300` 이다(실측 2026-10-07).
// 팝오버는 여닫기가 잦아서, 열 때마다 치면 평범한 사용자가 몇 분 만에 자기 계정을 5분간 잠근다.
// 그래서 `refreshInterval` 10분 · `forcedRefreshFloor` 5분이다. 429 를 받으면 `retryAfter` 가 끝날 때까지
// **완전히 침묵한다** — 30초마다 다시 노크하는 구현은 300초 금지창에서 틀린 동작이다.
//
// ★ **간격은 프로세스 수명보다 오래 살아야 한다.** 초안은 숫자와 실패 분류만 영속해서, 앱을 다시 켜면
//   `lastAttemptAt == nil` → `isDue` 가 즉시 참이고 `silentUntil == nil` → **429 금지창 안에서도** 바로
//   노크했다. 맥 앱은 업데이트·로그아웃·수동 재시작으로 몇 분 안에 여러 번 켜진다 — 5분에 5회를 그렇게 넘기면
//   스토어가 막겠다고 선언한 바로 그 사고(사용자 본인 계정이 5분 잠김)를 스토어가 만든다.
//   그래서 **시도 시각과 금지창도 함께 영속하고 복원한다.** 시도 스탬프는 러너를 부르기 **직전에** 디스크로
//   내려간다 — 바퀴 도중에 앱이 죽어도 그 시도가 장부에 남아야 한다(실패도 간격을 지켜야 난사가 안 된다).
//   복원값은 **지금보다 미래면 지금으로 접는다**: 시계가 뒤로 간 맥에서 미래 스탬프가 남으면 그 뒤로 영원히
//   갱신하지 않는 '세션 영구고착' 꼴이 된다.
//
// ## 실패해도 직전 값을 버리지 않는다
// 사용률은 한 창 안에서 올라가기만 하므로 마지막 값은 **안전한 하한**이다(`AILimitFreshnessRule` 머리말).
// 그래서 네트워크·429·만료에서는 영속된 값을 그대로 들고 있고, 나이 캡션만 낡는다. 숨기는 것은
// "그 도구를 안 쓴다 / 우리가 볼 수 없다"(`AILimitReadFailure.hidesProvider`) 뿐이다.
//
// ## 자동 감지 — 그리고 그 위에 얹은 사용자 설정(v0.3.47)
// 자격증명이 하나도 없으면 `isAvailable == false` 이고 화면은 섹션을 **통째로 숨긴다**(2026-10-07 사용자 결정).
// 그래서 **연동 안 된 제공자는 설정에도 줄이 서지 않는다** — 쓰는 사람에게만 저절로 생긴다.
// v0.3.47 이 그 위에 얹은 것은 "**보이는 것 중에서** 원하는 것만, 아예 안 볼 수도 있게" 하나다
// (사용자 요청 2026-10-07). 자동 감지 규약은 그대로고, 설정은 그 앞단 게이트다 — 값·캡션·표시여부는
// 여전히 `AILimitFreshnessRule` 한 곳에서 나온다.

// MARK: - 표시 설정 (v0.3.47)
//
// ## 로컬 설정이다 — 서버 컬럼이 아니다
// 자격증명은 맥에만 있어 **맥이 이 축의 유일한 주인**이고, 앱이 꺼진 동안 이 설정이 서버에 없어서
// 잃는 사람이 없다(관례: '서버보다 클라 먼저'). 기존 `autoWorkStartEnabled` 와 같은 결이다.
// ★ `profiles` 에 컬럼을 더하지 않았다 — 그 표는 표 단위 UPDATE 가 회수돼 있어 컬럼 grant 를 빼먹으면
//   "토글은 켜지는데 서버 값이 안 바뀐다"가 된다. 살 이유가 없는 함정이다.
//
// ## 끄면 **읽지도 올리지도** 않는다 — 화면에서 감추는 게 아니다
//  · 꺼진 제공자: 리더를 **부르지 않는다**(키체인·`auth.json`·`agy` 접근 0), 제공자 API 를 치지 않는다,
//    서버에 올리지 않는다.
//  · 전체 끄기: 리밋 축이 통째로 잠든다 — `isDue` 가 거짓이라 **갱신 타이머가 돌지 않는다**.
// 왜 이렇게까지 하나: "표시 안 함"이라 해 놓고 뒤에서 계속 토큰을 읽고 네트워크를 쓰면 그건 거짓말이다.
// 그리고 이 기능은 공개 처리방침이 "로그인 정보를 읽는다"고 적은 **유일한** 자리라, 끄면 정말 안 읽어야
// 그 문장이 참이 된다.
// ★ 그래서 걸러는 자리는 **러너 앞**이다. 리더 안쪽에서 걸러도 늦다 — 그때는 이미 키체인에 손을 댄 뒤다.
//
// ## 기본값은 전부 켬 — 그리고 **꺼진 쪽**을 저장한다
// 저장하는 것이 '켠 목록'이면 열거값이 늘어난 날 구버전이 적어 둔 목록에 새 제공자가 없어서 그 제공자가
// 조용히 꺼진다(기본값 역전 — 기존 사용자에게 변화가 없어야 한다는 요건이 깨진다). 꺼진 쪽을 적으면
// 모르는 제공자는 **켜짐**이 기본이고, 그게 지금 동작과 같다.
// 그리고 모르는 rawValue 도 **버리지 않고 들고 있는다**: 신버전에서 끈 제공자를 구버전이 저장하며 지워 버리면
// 다시 올라갈 때 그 제공자가 아무 말 없이 켜진다(열거값 확장 함정의 쌍둥이).

/// 어떤 제공자의 리밋을 **읽고 보여 줄지**. 마스터 하나 + 제공자별 하나.
///
/// 작은 값 타입인 까닭: 저장·복원·판정이 전부 순수 함수라 테스트가 화면 없이 되묻을 수 있다.
/// 스토어는 이 값을 들고 있을 뿐이고, "누구를 읽는가"는 `enabledProviders` 한 곳에서 나온다.
package struct AILimitVisibility: Equatable, Sendable {
    /// 지금까지의 동작 = 전부 켬. **기본값이다**(기존 사용자에게 변화가 없어야 한다).
    package static let allEnabled = AILimitVisibility()

    /// 마스터. 끄면 제공자 스위치와 무관하게 아무것도 읽지 않는다.
    package var masterEnabled: Bool
    /// **꺼진** 제공자의 rawValue. 모르는 값도 그대로 보존한다(머리말).
    package var disabledRaws: Set<String>

    package init(masterEnabled: Bool = true, disabledRaws: Set<String> = []) {
        self.masterEnabled = masterEnabled
        self.disabledRaws = disabledRaws
    }

    /// 지금 이 제공자를 **읽어야 하는가**. 마스터와 제공자 스위치를 둘 다 본다.
    package func isEnabled(_ provider: AILimitProvider) -> Bool {
        masterEnabled && isProviderOn(provider)
    }

    /// 제공자 스위치 **하나만**. 마스터가 꺼진 동안에도 설정 화면은 "마스터를 켜면 무엇이 켜지는가"를
    /// 보여 줘야 하므로, 하위 줄이 그리는 값은 이것이다(`isEnabled` 가 아니다 — 그걸 그리면 마스터를 끄는
    /// 순간 하위 스위치 셋이 전부 꺼진 것처럼 보이고, 다시 켰을 때 내 선택이 사라진 것처럼 보인다).
    package func isProviderOn(_ provider: AILimitProvider) -> Bool {
        !disabledRaws.contains(provider.rawValue)
    }

    /// 이번 바퀴에 리더를 부를 제공자. **비어 있으면 바퀴 자체를 돌지 않는다.**
    package var enabledProviders: Set<AILimitProvider> {
        guard masterEnabled else { return [] }
        return Set(AILimitProvider.allCases.filter { isProviderOn($0) })
    }

    package mutating func setProvider(_ provider: AILimitProvider, on: Bool) {
        if on {
            disabledRaws.remove(provider.rawValue)
        } else {
            disabledRaws.insert(provider.rawValue)
        }
    }
}

/// 비우기 대기열을 **한 번 집은 것**(v0.3.47 P1).
///
/// 업로드는 `await` 를 건너므로, 돌아왔을 때 "내가 보낸 것"을 알 길이 이것뿐이다. 세대까지 함께 들고 오는
/// 까닭은 `AILimitStore.pendingClearGenerations` 머리말에 있다 — 떠난 사이에 **다시 끈** 제공자를
/// 비웠다고 표시하면 그 끄기는 영원히 서버에 닿지 않는다.
package struct AILimitClearClaim: Equatable, Sendable {
    /// 이번 본문에 실을 제공자(제공자 순서로 정렬).
    package let providers: [AILimitProvider]
    /// 제공자별 세대. 돌아왔을 때 대기열의 세대가 **이것과 같을 때만** 비운 것으로 친다.
    package let generations: [AILimitProvider: Int]

    package init(providers: [AILimitProvider], generations: [AILimitProvider: Int]) {
        self.providers = providers
        self.generations = generations
    }

    package var isEmpty: Bool { providers.isEmpty }
}

/// 리더 셋을 한 번 돌린 결과. 제공자마다 성공이거나 분류된 실패다.
package struct AILimitReadOutcome: Sendable {
    package var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>]

    package init(results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [:]) {
        self.results = results
    }

    /// 성공한 제공자 스냅샷(정렬).
    package var snapshots: [AILimitProviderSnapshot] {
        results.values
            .compactMap { try? $0.get() }
            .sorted { $0.provider.sortOrder < $1.provider.sortOrder }
    }

    /// 실패 분류만.
    package var failures: [AILimitProvider: AILimitReadFailure] {
        results.compactMapValues { result in
            switch result {
            case .success: return nil
            case .failure(let error): return error.failure
            }
        }
    }

    /// 이번 바퀴에서 받은 가장 긴 `retry-after`(초). 없으면 nil.
    package var retryAfter: TimeInterval? {
        results.values.compactMap { result -> TimeInterval? in
            switch result {
            case .success: return nil
            case .failure(let error): return error.retryAfter
            }
        }.max()
    }
}

@Observable
@MainActor
package final class AILimitStore {
    /// 리더 셋을 한 번 돌리는 일. 프로덕션은 `live()` 가 만들고, 테스트는 고정 결과를 돌려주는 클로저를 넣는다.
    ///
    /// ★ `providers` 가 **계약의 절반**이다(v0.3.47): 러너는 이 집합 안의 리더만 부른다. 설정에서 꺼진
    ///   제공자를 러너에게 알리고 **결과를 버리는** 구현은 틀렸다 — 그때는 이미 키체인·`auth.json`·`agy` 를
    ///   건드린 뒤이고, "끄면 안 읽는다"는 약속이 거짓이 된다. 그래서 가르는 자리가 인자다.
    package typealias Runner = @Sendable (_ now: Date, _ providers: Set<AILimitProvider>) async -> AILimitReadOutcome

    // MARK: 상수

    package nonisolated static let snapshotKey = "check.aiLimits.snapshot"
    package nonisolated static let failuresKey = "check.aiLimits.failures"
    /// 마지막 **시도** 시각(epoch 초). 이게 없으면 재시작마다 간격이 0 으로 리셋돼 429 를 자초한다(머리말).
    package nonisolated static let lastAttemptKey = "check.aiLimits.lastAttemptAt"
    /// 429 금지창의 끝(epoch 초). 이게 없으면 재시작이 금지창을 뚫는다(머리말).
    package nonisolated static let silentUntilKey = "check.aiLimits.silentUntil"
    /// 평상시 갱신 주기(초). 10분 — Claude 의 5분/5회 상한에 여유를 두고도 5시간 창의 변화를 놓치지 않는 값이다.
    package nonisolated static let refreshInterval: TimeInterval = 600
    /// 팝오버·창을 열었을 때의 하한(초). 5분 — 이 아래로 내려가면 여닫기만으로 429 를 맞는다.
    package nonisolated static let forcedRefreshFloor: TimeInterval = 300
    /// 429 의 `retry-after` 를 못 읽었을 때의 침묵 길이(초). 실측 헤더 값과 같은 300.
    package nonisolated static let defaultBackoff: TimeInterval = 300

    /// 마스터 스위치(Bool). **키가 없으면 켜짐**이다 — 기존 사용자에게 변화가 없어야 한다.
    /// ★ 이름을 바꾸면 이미 끈 사람의 설정이 아무 말 없이 켜짐으로 돌아간다.
    package nonisolated static let visibilityKey = "check.aiLimits.show"
    /// **꺼진** 제공자의 rawValue 목록([String]). 없으면 빈 목록(= 전부 켬).
    package nonisolated static let disabledProvidersKey = "check.aiLimits.disabledProviders"
    /// 서버 행을 **비워야** 하는 제공자 목록([String]). 끈 순간 들어가고, 비우기 업로드가 성공하면 빠진다.
    /// ★ 영속해야 한다 — 끄고 바로 앱이 죽으면 그 행이 서버에 영원히 남아 폰·위젯이 계속 보여 준다.
    package nonisolated static let pendingClearKey = "check.aiLimits.pendingClear"

    // MARK: 상태

    /// 마지막으로 받은 묶음(실패해도 유지 — 머리말). nil = 한 번도 못 읽었다.
    package private(set) var bundle: AILimitSnapshotBundle?
    /// 제공자별 마지막 실패 분류. 성공한 제공자는 여기서 사라진다.
    package private(set) var failures: [AILimitProvider: AILimitReadFailure] = [:]
    /// 마지막 **시도** 시각(주입 시계). 간격 판정의 기준.
    package private(set) var lastAttemptAt: Date?
    /// 이 시각 전에는 아무것도 하지 않는다(429 백오프). nil = 제한 없음.
    package private(set) var silentUntil: Date?
    /// 표시 설정(v0.3.47). 기본은 전부 켬. 설정 화면이 이 값을 그리고, 갱신 경로가 이 값으로 가른다.
    package private(set) var visibility: AILimitVisibility = .allEnabled
    /// 서버 행을 비워야 하는 제공자 → **그 끄기의 세대**. 업로드 성공에만 빠진다 — `markCleared(_:)`.
    ///
    /// ## 왜 집합이 아니라 세대 표인가 (v0.3.47 P1)
    /// 업로드는 `await` 를 건너므로, 돌아왔을 때의 대기열은 떠날 때의 대기열이 아니다. 같은 제공자가 그 사이
    /// **다시 켜지고 또 꺼졌으면** 그건 아직 아무도 보낸 적 없는 **새 사건**이다. 집합만 들고 있으면 둘을
    /// 구별할 수 없어서, 돌아온 업로드가 "내가 보낸 것"이라며 그 새 사건을 지운다 — 그러면 그 제공자는
    /// 서버에서 영원히 안 비워진다(대기열이 비어 다음 주기도 재시도할 근거가 없다).
    private var pendingClearGenerations: [AILimitProvider: Int] = [:]
    /// 대기열에 들어온 끄기의 순번. 같은 제공자가 다시 꺼지면 **더 큰** 값을 받는다.
    private var clearSequence = 0
    /// 러너가 불린 횟수(테스트 계측 — 간격·백오프·재진입 가드가 실제로 막는지).
    @ObservationIgnored package private(set) var runnerCallCount = 0
    @ObservationIgnored private var inFlight = false

    /// 서버 행을 비워야 하는 제공자(끈 순간 들어온다). 세대는 감춘다 — 밖에서 재는 것은 "누가 남았나"뿐이다.
    package var pendingClear: Set<AILimitProvider> { Set(pendingClearGenerations.keys) }

    // MARK: 업로드 직렬화 (v0.3.47 P1)
    //
    // 업로드의 HTTP 는 `WorkTimerStore` 가 하지만 **순서는 이 스토어가 쥔다.** 간격(10분)·429 금지창과 같은
    // 종류의 상태이고, 업로드를 띄우는 설정 세터가 바로 이 스토어의 세터 뒤에 붙어 있다.
    // 관용구는 `WorkTimerStore.requestDrain`(찔림 회수)과 같다 — 비행 중이면 새로 쏘지 않고 **트레일링
    // 한 번**으로 접는다. 몇 번 울려도 한 번이고, 그래서 같은 PK 가 두 본문에 동시에 뜨는 일이 없다.

    /// 비행 중인 업로드. non-nil 인 동안 들어온 요청은 트레일링으로 합쳐진다. 테스트는 이 Task 를 기다린다.
    @ObservationIgnored package var uploadInFlight: Task<Void, Never>?
    /// 비행 중에 들어온 요청이 있다 → 끝난 뒤 **한 번** 더 돈다.
    @ObservationIgnored package var uploadPendingTrailing = false
    /// 동시에 떠 있던 업로드 왕복의 **최대 수**(테스트 계측 — `runnerCallCount` 와 같은 규약).
    /// ★ 1 이 아니면 두 본문의 도착 순서를 아무도 보장하지 않는다: 값 본문이 비우는 본문보다 늦게 닿으면
    ///   끈 제공자가 되살아나고, 그 사이 `markCleared` 가 대기열을 비워 **다시는 안 비운다.**
    @ObservationIgnored package private(set) var uploadPeakConcurrency = 0
    /// **시작된** 업로드 왕복의 수(테스트 계측). 비행 창을 기다리는 테스트가 "이번 왕복이 떠났다"를 이걸로 안다 —
    /// 최대치(`uploadPeakConcurrency`)는 한 번 1 이 되면 그대로라 "방금 떠났다"를 말해 주지 못한다.
    @ObservationIgnored package private(set) var uploadRoundTripCount = 0
    @ObservationIgnored private var uploadsInFlightNow = 0

    // MARK: 비우기 재시도 백오프 (v0.3.47 P2)
    //
    // ## 고치는 자리: 비우기가 **항구적으로** 실패하면 30초마다 영원히 POST 했다
    // 비우기는 성공할 때까지 대기열에 남아야 한다(그래야 끈 제공자가 폰·위젯에서 사라진다). 그런데 그 실패가
    // 항구적이면 — 스키마가 없는 서버, 즉 앱이 `db push` 보다 먼저 나간 경우(머리말이 스스로 예상한 경우다) —
    // 30초 틱마다 같은 404 를 영원히 받는다. 그 상태의 사용자는 **마스터를 끈 사람**이고, 그에게 약속한 것은
    // "리밋 축이 통째로 잠든다 … 네트워크 0"이었다.
    //
    // ## 포기는 하지 않는다 — **느려지되 멈추지 않는다**
    // 대기열을 버리면 그 행은 영영 안 지워진다. 그래서 간격만 벌린다: 60초에서 시작해 실패마다 두 배,
    // 상한 1시간. 성공하면 즉시 풀린다(다음 실패는 다시 60초부터다).
    // 영속하지 않는 까닭: 다시 켠 앱이 한 번 더 노크하는 것은 요청 하나이고, 429 처럼 **남의 상한**을
    // 건드리는 일도 아니다(여기는 우리 서버다). 영속해야 하는 쪽은 대기열 자체이고 그건 이미 디스크에 있다.

    /// 비우기 재시도의 첫 간격(초).
    package nonisolated static let clearRetryBaseBackoff: TimeInterval = 60
    /// 비우기 재시도 간격의 상한(초). 1시간 — 이 위로 벌려도 네트워크는 더 안 줄고 복구만 늦는다.
    package nonisolated static let clearRetryMaxBackoff: TimeInterval = 3_600

    @ObservationIgnored private var clearFailureCount = 0
    @ObservationIgnored private var clearRetryNotBefore: Date?

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let runner: Runner

    package init(defaults: UserDefaults, clock: @escaping () -> Date = { Date() }, runner: @escaping Runner) {
        self.defaults = defaults
        self.clock = clock
        self.runner = runner
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(AILimitSnapshotBundle.self, from: data),
           restored.schemaVersion <= AILimitSnapshotBundle.currentSchemaVersion {
            bundle = restored
        }
        if let data = defaults.data(forKey: Self.failuresKey),
           let restored = try? JSONDecoder().decode([String: AILimitReadFailure].self, from: data) {
            // 모르는 제공자 키는 버린다(열거값 확장 함정 — 접어서 남의 실패를 내 카드에 붙이지 않는다).
            failures = restored.reduce(into: [:]) { out, pair in
                guard let provider = AILimitProvider(rawValue: pair.key) else { return }
                out[provider] = pair.value
            }
        }
        // 간격·금지창은 프로세스 수명보다 오래 산다(머리말). 미래 스탬프는 지금으로 접어 영구고착을 막고,
        // 금지창은 한 번의 기본 백오프보다 길게 믿지 않는다(디스크 값 하나가 리밋 축을 영원히 끌 수 있다).
        let now = self.clock()
        if let stamp = Self.restoredDate(defaults, key: Self.lastAttemptKey) {
            lastAttemptAt = min(stamp, now)
        }
        if let until = Self.restoredDate(defaults, key: Self.silentUntilKey) {
            silentUntil = min(until, now.addingTimeInterval(Self.defaultBackoff))
        }
        // 표시 설정(v0.3.47). **키가 없으면 전부 켬** — 기존 사용자에게 변화가 없어야 한다.
        // 모르는 rawValue 는 `AILimitProvider(rawValue:)` 로 접지 않고 **문자열 그대로** 보존한다(머리말).
        visibility = AILimitVisibility(
            masterEnabled: defaults.object(forKey: Self.visibilityKey) as? Bool ?? true,
            disabledRaws: Set(defaults.stringArray(forKey: Self.disabledProvidersKey) ?? [])
        )
        // 비우기 대기열은 **아는 제공자만** 복원한다 — 모르는 이름으로는 올릴 행을 만들 수 없고(서버 CHECK),
        // 올릴 수 없는 항목을 대기열에 남기면 매 주기 재시도하는 영구 고착이 된다.
        // 세대는 디스크에 없다(적는 것은 '무엇을' 뿐이고 순번은 한 프로세스 안에서만 뜻이 있다) — 복원 순서대로
        // 다시 매긴다. 이 프로세스의 첫 업로드가 보낸 뒤 그대로 비울 수 있고, 그 사이 다시 끈 제공자는 더 큰
        // 세대를 받아 살아남는다.
        for provider in (defaults.stringArray(forKey: Self.pendingClearKey) ?? [])
            .compactMap(AILimitProvider.init(rawValue:)) {
            enqueueClear(provider)
        }
    }

    /// epoch 초로 적힌 시각을 읽는다. 값이 없거나 숫자가 아니면 nil(= 제한 없음).
    private nonisolated static func restoredDate(_ defaults: UserDefaults, key: String) -> Date? {
        guard let raw = defaults.object(forKey: key) as? Double, raw.isFinite else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    /// 무해 인스턴스: 격리 defaults + 아무것도 안 읽는 러너. `WorkTimerStore` 의 기본값이라, 주입을 잊은
    /// 테스트가 실제 키체인·`agy`·네트워크를 건드리는 일이 **구조적으로** 없다(fail-closed).
    ///
    /// ★★ 스위트 이름이 **절대 경로**이고 **UUID 가 없다.** 둘 다 실측으로 못 박힌 값이다.
    ///   · 평범한 도메인 이름(`"check.aiLimits.inert.…"`)을 주면 `cfprefsd` 가 `~/Library/Preferences` 에
    ///     plist 를 만든다. 선례인 `CodexAccountUsageStore.inert()` 는 같은 꼴인데도 파일이 안 생기는데,
    ///     그 스토어는 무해 경로에서 defaults 에 **아무것도 쓰지 않기** 때문이다. 이 스토어는 `refresh` 끝에
    ///     `persist()` 가 실패 표를 **빈 사전이라도** 쓴다 → 바퀴를 한 번 돈 inert 마다 파일 하나가 생긴다.
    ///   · UUID 를 붙이면 그 파일이 **인스턴스마다 다른 이름**이 된다. 2026-10-07 실측: 전체 스위트 한 바퀴가
    ///     `~/Library/Preferences` 에 1,454개를 남겼다. 62만 개가 `cfprefsd` 를 통째로 죽여 로그아웃·유령
    ///     기기·토큰 2배를 한 뿌리에서 만든 그 사고와 같은 가족이다.
    ///   그래서 이름은 `$TMPDIR` 아래 **고정** 경로다. inert 가 쓰는 내용은 어떤 인스턴스에서나 같으므로
    ///   (묶음 없음 + 빈 실패 표) 도메인을 나눠 써도 서로의 관측을 바꾸지 못한다 — 나눠 쓰는 대가가 없다.
    package static func inert() -> AILimitStore {
        let name = FileManager.default.temporaryDirectory
            .appendingPathComponent("check-ai-limits-inert").path
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return AILimitStore(defaults: defaults, runner: { _, _ in AILimitReadOutcome() })
    }

    // MARK: 표시 재료

    /// 화면에 그릴 제공자 카드(정렬 · 미연동 제거 · **설정이 끈 제공자 제거**).
    ///
    /// 설정을 여기서 거는 까닭: 표시·조합값·업로드가 전부 이 한 목록을 거친다. 뷰마다 다시 걸러면
    /// 한 군데를 잊은 날 "설정에서는 껐는데 메뉴바 한 줄에는 아직 섞여 있다"가 된다
    /// (관례: '클라 게이트는 짝으로 있다' — 그래서 짝을 안 만들고 목이 하나다).
    package var visibleProviders: [AILimitProviderSnapshot] {
        guard visibility.masterEnabled else { return [] }
        return (bundle?.visibleProviders ?? []).filter { visibility.isProviderOn($0.provider) }
    }

    /// 이 맥에 리밋 축을 보여 줄 근거가 있는가. **없으면 화면이 섹션을 통째로 숨긴다**(높이 0).
    ///
    /// 근거는 둘이다: ① 읽은 창이 하나라도 있다, ② 숨기지 않는 실패가 하나라도 있다(만료·429·네트워크 —
    /// 그 사람은 그 도구를 쓰고 있고 우리가 지금만 못 읽는 것이다).
    /// v0.3.47: 마스터를 끄면 **근거를 따지기 전에** 거짓이다(화면에서 섹션이 사라진다).
    package var isAvailable: Bool {
        guard visibility.masterEnabled else { return false }
        if !visibleProviders.isEmpty { return true }
        // 꺼진 제공자의 실패는 세지 않는다 — 안 읽는 제공자의 만료 문구로 섹션을 살려 두면
        // "다 껐는데 카드가 남아 있다"가 된다.
        return failures.contains { visibility.isProviderOn($0.key) && !$0.value.hidesProvider }
    }

    /// **설정 화면이** 줄을 세울 제공자(읽은 것 + 숨기지 않는 실패). 표시 설정을 **보지 않는다.**
    ///
    /// ★ 설정을 보면 안 되는 이유: 꺼서 안 보이는 제공자도 다시 켤 줄이 있어야 한다. 마스터를 끄면 아무것도
    ///   읽지 않으므로, 이 목록이 설정에 기대어 좁아지는 구현은 **들어가면 못 나오는 방**을 만든다
    ///   (끈 뒤로는 되켜는 스위치가 화면에 없다).
    /// ★ 그래서 근거는 **영속된 묶음과 실패 표**다 — 둘 다 끈 동안에도 디스크에 남아 있어, 마스터를 끈 사람의
    ///   설정 화면에도 같은 줄들이 그대로 선다.
    package var configurableProviders: [AILimitProvider] {
        var seen = Set<AILimitProvider>()
        var out: [AILimitProvider] = []
        for snapshot in bundle?.visibleProviders ?? [] where seen.insert(snapshot.provider).inserted {
            out.append(snapshot.provider)
        }
        for (provider, failure) in failures where !failure.hidesProvider && seen.insert(provider).inserted {
            out.append(provider)
        }
        return out.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 목록에 세울 제공자 순서(읽은 것 + 숨기지 않는 실패 − 설정이 끈 것). 실패만 있는 제공자도 카드를 세워 문구를 말한다.
    package var listedProviders: [AILimitProvider] {
        guard visibility.masterEnabled else { return [] }
        return configurableProviders.filter { visibility.isProviderOn($0) }
    }

    /// 서버에 **값으로** 올라갈 묶음(설정이 켠 제공자만). 끈 제공자는 여기서 사라지고, 그 자리는
    /// 비우는 행이 대신 올라간다(`pendingClear`).
    package var enabledBundle: AILimitSnapshotBundle {
        AILimitSnapshotBundle(providers: visibleProviders)
    }

    /// 한 줄 요약(메뉴바·팝오버)이 그릴 값. 모든 제공자의 모든 창을 합친다 — 가장 많이 쓴 쪽이 하한이고,
    /// 캡션은 가장 낡은 기여자가 정한다(규칙은 `AILimitFreshnessRule.combine` 한 곳).
    package func summary(now: Date) -> AILimitDisplay {
        AILimitFreshnessRule.combine(visibleProviders.flatMap {
            AILimitFreshnessRule.displays(provider: $0, now: now)
        })
    }

    /// 창 하나의 표시(카드가 쓴다). 뷰가 직접 계산하지 않는다.
    package func display(provider: AILimitProvider, window: AILimitWindow, now: Date) -> AILimitDisplay {
        AILimitFreshnessRule.display(provider: bundle?.provider(provider), window: window, now: now)
    }

    /// 제공자 카드에 덧붙일 한 줄(없으면 nil).
    package func noticeText(provider: AILimitProvider) -> String? {
        failures[provider]?.noticeText(for: provider)
    }

    // MARK: 갱신

    /// 간격이 찼는가. 진행 중이거나 백오프 중이면 거짓.
    ///
    /// ★ **꺼진 축은 타이머가 돌지 않는다**(v0.3.47 설계 ②). 여기서 거짓이면 `refreshIfDue` 가 즉시 반환하고,
    ///   시도 스탬프도 찍히지 않고 디스크도 안 건드린다 — 끈 사람의 맥에서는 이 축이 **아무 일도 안 한다.**
    ///   가르는 값이 '마스터' 하나가 아니라 `enabledProviders.isEmpty` 인 까닭: 셋을 각각 끈 사람도
    ///   읽을 리더가 없고, 그때 바퀴를 돌리면 빈 결과를 받아 와 `apply` 가 디스크를 쓴다.
    ///
    /// ★★ 게이트는 **사용자가 끌 수 있는 집합**으로 잰다(v0.3.47 P2 — 2026-10-08 실증).
    ///   `enabledProviders` 는 '꺼진 쪽을 저장한다' 규약 때문에 **연동 안 된 제공자까지 켜진 것으로 센다.**
    ///   그 제공자는 설정 화면에 줄이 **없어서**(섹션은 연동된 것만 세운다 — `configurableProviders`)
    ///   사용자가 끌 수도 없다. 그걸로 바퀴를 살려 두면 Claude 하나만 연동한 사람이 그 하나를 끈 뒤에도
    ///   10분마다 `~/.codex/auth.json` 을 읽고 `agy`(5초짜리)를 띄운다 — 화면에 남은 스위치가 마스터뿐이라
    ///   "끄면 읽지도 않는다"가 그 사람에게는 거짓이 된다.
    ///   그래서 줄이 선 제공자 중 켜진 것이 하나도 없으면 **바퀴를 돌리지 않는다.**
    ///
    /// ★ 줄이 **하나도 없는** 동안은(아직 한 번도 못 읽었다 · 연동 0) 거꾸로 **돈다**: 그때 닫으면
    ///   내일 Claude Code 를 깐 사람에게 이 축이 영영 켜지지 않는다(실패 표도 디스크에 남아 재실행이
    ///   구해 주지 못한다). 그 사람에게는 끌 줄도 없으니 지킬 약속도 아직 없다.
    ///
    /// ★ 그래서 **남는 것 하나**(알고 남긴다): 줄이 선 **다른** 제공자 때문에 바퀴가 도는 동안에는,
    ///   줄이 없는 제공자도 그 바퀴에서 같이 물어본다(`refreshIfDue` 가 넘기는 집합은 여전히
    ///   `enabledProviders` 다). 그게 연동을 발견하는 유일한 길이다 — 숨기는 실패는 디스크에 남으므로
    ///   요청 집합에서 빼 버리면 나중에 로그인한 사람에게 그 줄이 영영 안 생긴다. 끌 줄이 **있는**
    ///   제공자에 대한 약속("끄면 안 읽는다")은 그대로다.
    package func isDue(now: Date, force: Bool = false) -> Bool {
        if visibility.enabledProviders.isEmpty { return false }
        let stoppable = Set(configurableProviders)
        if !stoppable.isEmpty, visibility.enabledProviders.isDisjoint(with: stoppable) { return false }
        if inFlight { return false }
        if let silentUntil, now < silentUntil { return false }
        guard let last = lastAttemptAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return force ? elapsed >= Self.forcedRefreshFloor : elapsed >= Self.refreshInterval
    }

    // 캐시 TTL(`isFresh`)은 **없다.** 초안에 있었는데 호출부가 저장소에 0 건이었다 — 걸려 있지도 않은 장치가
    // 머리말에 "이 안이면 네트워크를 안 쓴다"로 적혀 있으면, 다음 사람이 그걸 믿고 5분 하한을 낮춘다.
    // 창을 열 때 네트워크를 쓸지 가르는 것은 `isDue(now:force:)` 의 **5분 하한 하나**다(겹치는 장치를 두지 않는다).

    /// 간격이 찼을 때만 리더를 돈다. `force` 는 "사용자가 방금 팝오버·창을 열었다"일 때 쓴다(5분 하한 유지).
    package func refreshIfDue(now: Date, force: Bool = false) async {
        guard isDue(now: now, force: force) else { return }
        // 켜진 제공자만 러너에게 넘긴다. 집합을 **여기서** 굳히는 까닭: 바퀴 도중에 사용자가 스위치를
        // 만져도 이번 바퀴의 요청 집합은 변하지 않아야 한다(요청한 적 없는 제공자의 결과가 섞이지 않는다).
        let providers = visibility.enabledProviders
        // 스탬프를 러너 **전에** 찍는다 — 실패도 간격을 지켜야 난사가 안 된다(CodexAccountUsageStore 와 같은 관용구).
        // 디스크에도 **지금** 내려간다: 바퀴 도중에 앱이 죽어도 이 시도가 장부에 남아야 다음 실행이 간격을 지킨다.
        lastAttemptAt = now
        persistSchedule()
        inFlight = true
        defer { inFlight = false }
        runnerCallCount += 1
        let outcome = await runner(now, providers)
        apply(outcome, now: now)
    }

    // MARK: 표시 설정 (v0.3.47)

    /// 마스터 스위치. 끄면 **읽기·업로드·타이머가 통째로 멈추고**, 이미 올라간 행들은 비우기 대기열에 들어간다.
    package func setMasterEnabled(_ enabled: Bool) {
        guard visibility.masterEnabled != enabled else { return }
        var next = visibility
        next.masterEnabled = enabled
        apply(visibility: next)
    }

    /// 제공자 하나의 스위치. **마스터와 독립**이다(마스터가 꺼진 동안 바꿔 둘 수 있다).
    package func setProviderEnabled(_ provider: AILimitProvider, _ enabled: Bool) {
        guard visibility.isProviderOn(provider) != enabled else { return }
        var next = visibility
        next.setProvider(provider, on: enabled)
        apply(visibility: next)
    }

    /// 설정을 갈아 끼우고 **비우기 대기열을 갱신한다.**
    ///
    /// 대기열에 넣는 것은 "바뀌기 **전에** 올라가던 제공자 − 바뀐 **뒤에** 올라갈 제공자" 뿐이다.
    /// 그 차집합으로 재는 까닭이 셋 있다:
    ///  ① 이미 꺼 둔(그래서 이미 비운) 제공자를 마스터 끄기가 다시 대기열에 넣지 않는다 — 넣으면 같은 빈 행을
    ///     매번 다시 올린다("한 번이면 된다").
    ///  ② 연동되지 않은 제공자는 애초에 올라간 적이 없으니 비울 것도 없다.
    ///  ③ 마스터를 끄면 **연동된 모든 제공자**가 한꺼번에 차집합에 들어온다(설계 ③).
    ///
    /// 그리고 다시 **켠** 제공자는 대기열에서 **뺀다**: 값이 곧 다시 올라가므로 비우기는 뜻이 없고, 무엇보다
    /// 같은 PK 의 값 행과 비우는 행이 한 본문에 섞이면 upsert 가 21000 으로 **본문 전체**를 거절한다.
    private func apply(visibility next: AILimitVisibility) {
        let before = uploadableProviders(visibility)
        visibility = next
        let after = uploadableProviders(next)
        // 새로 끈 제공자는 **새 세대**로 들어온다(정렬 — 세대 번호가 결정적이어야 테스트가 되묻을 수 있다).
        for provider in before.subtracting(after).sorted(by: { $0.sortOrder < $1.sortOrder }) {
            enqueueClear(provider)
        }
        for provider in after { pendingClearGenerations.removeValue(forKey: provider) }
        persistVisibility()
    }

    /// 대기열에 넣는다. 같은 제공자가 다시 꺼지면 **새 세대**다 — 그게 "아직 아무도 안 보낸 끄기"라는 표시다.
    private func enqueueClear(_ provider: AILimitProvider) {
        clearSequence += 1
        pendingClearGenerations[provider] = clearSequence
    }

    /// 지금 설정에서 서버에 **값이 올라가는** 제공자(= 끄면 비워야 하는 대상).
    /// 연동 사실은 `configurableProviders` 가 아니라 **묶음**에서 본다 — 실패만 있는 제공자는 올린 적이 없다.
    private func uploadableProviders(_ visibility: AILimitVisibility) -> Set<AILimitProvider> {
        guard visibility.masterEnabled else { return [] }
        let linked = (bundle?.visibleProviders ?? []).map(\.provider)
        return Set(linked.filter { visibility.isProviderOn($0) })
    }

    /// 지금 보낼 비우기 묶음을 **집는다**. 업로드가 `await` **전에** 부르고, 돌아와서 그 집음으로 비운다.
    package func claimPendingClear() -> AILimitClearClaim {
        AILimitClearClaim(
            // 정렬해서 집는다(제공자 순서) — 본문이 결정적이어야 테스트가 글자로 되묻을 수 있다.
            providers: pendingClearGenerations.keys.sorted { $0.sortOrder < $1.sortOrder },
            generations: pendingClearGenerations
        )
    }

    /// 비우기 업로드가 **성공한** 제공자를 대기열에서 뺀다. 실패하면 부르지 않는다 — 그래야 다음 기회에 재시도된다.
    ///
    /// ★ 인자가 '지금 대기열'이 아니라 **집음**인 까닭(v0.3.47 P1): 비우는 것은 **자기가 실제로 보낸 것**뿐이어야
    ///   한다. 보낸 뒤에 사용자가 다시 켜고 또 끈 제공자는 세대가 커져 여기서 **살아남고**, 다음 업로드
    ///   (트레일링·30초 틱)가 그 끄기를 새로 보낸다. 무조건 비우면 그 끄기는 아무 흔적도 없이 사라진다.
    package func markCleared(_ claim: AILimitClearClaim) {
        var next = pendingClearGenerations
        for (provider, sent) in claim.generations where next[provider] == sent {
            next.removeValue(forKey: provider)
        }
        guard next != pendingClearGenerations else { return }
        pendingClearGenerations = next
        persistVisibility()
    }

    /// 업로드 왕복이 시작됐다(겹침 계측). 부르는 자리는 `WorkTimerStore.uploadAILimitsIfNeeded` 하나다.
    package func noteUploadStarted() {
        uploadsInFlightNow += 1
        uploadRoundTripCount += 1
        uploadPeakConcurrency = max(uploadPeakConcurrency, uploadsInFlightNow)
    }

    /// 업로드 왕복이 끝났다(성공이든 실패든).
    package func noteUploadFinished() {
        uploadsInFlightNow = max(0, uploadsInFlightNow - 1)
    }

    /// 지금 **비우기만** 다시 보내도 되는가. 값이 바뀐 업로드는 이 게이트를 지나지 않는다 — 새 소식은 늘
    /// 나가고 비우기가 거기 얹혀 간다. 막는 것은 "같은 실패를 30초마다 영원히" 하나다.
    package func clearRetryAllowed(now: Date) -> Bool {
        guard let clearRetryNotBefore else { return true }
        return now >= clearRetryNotBefore
    }

    /// 비우기 업로드가 실패했다 → 다음 시도를 뒤로 미룬다(두 배씩, 상한까지). **대기열은 그대로 둔다.**
    package func noteClearFailed(now: Date) {
        clearFailureCount += 1
        let doubled = Self.clearRetryBaseBackoff * pow(2, Double(clearFailureCount - 1))
        clearRetryNotBefore = now.addingTimeInterval(min(Self.clearRetryMaxBackoff, doubled))
    }

    /// 비우기 업로드가 성공했다 → 백오프를 통째로 푼다.
    package func noteClearSucceeded() {
        clearFailureCount = 0
        clearRetryNotBefore = nil
    }

    /// 연속 실패 수(테스트 계측 — 성공이 백오프를 실제로 푸는지).
    package var clearFailureStreak: Int { clearFailureCount }

    private func persistVisibility() {
        defaults.set(visibility.masterEnabled, forKey: Self.visibilityKey)
        defaults.set(visibility.disabledRaws.sorted(), forKey: Self.disabledProvidersKey)
        defaults.set(pendingClear.map(\.rawValue).sorted(), forKey: Self.pendingClearKey)
    }

    /// 결과를 상태에 반영한다(순수에 가까운 지점 — 테스트가 직접 부른다).
    ///
    /// **새로 읽은 제공자는 통째로 교체한다**(옛 값과 max 를 취하지 않는다). 리셋을 지난 창은 값이 **내려가는 것이
    /// 정답**이고, '높은 쪽을 믿는다'는 규칙은 *같은 순간의 두 출처*(로컬 vs 서버)를 견줄 때의 것이다
    /// (`AILimitFreshnessRule` 머리말 — 폐기된 `max(로컬, 계정)` 증폭기와 같은 사고를 여기서 만들지 않는다).
    /// 읽지 **못한** 제공자는 들고 있던 값을 그대로 남긴다 — 그게 하한이다.
    package func apply(_ outcome: AILimitReadOutcome, now: Date) {
        var merged: [AILimitProvider: AILimitProviderSnapshot] = [:]
        for snapshot in bundle?.providers ?? [] { merged[snapshot.provider] = snapshot }
        for snapshot in outcome.snapshots { merged[snapshot.provider] = snapshot }
        // 숨기는 실패(미설치·미로그인·차단)는 들고 있던 값까지 **지운다** — 로그아웃한 사람의 옛 숫자를
        // 계속 보여 주면 그건 남의 계정 값일 수도 있다(기기를 넘겨준 경우).
        for (provider, failure) in outcome.failures where failure.hidesProvider {
            merged.removeValue(forKey: provider)
        }
        let next = AILimitSnapshotBundle(providers: merged.values.sorted { $0.provider.sortOrder < $1.provider.sortOrder })
        bundle = next
        var nextFailures = failures
        for provider in outcome.results.keys { nextFailures.removeValue(forKey: provider) }
        for (provider, failure) in outcome.failures { nextFailures[provider] = failure }
        failures = nextFailures
        silentUntil = outcome.failures.values.contains(.rateLimited)
            ? now.addingTimeInterval(outcome.retryAfter ?? Self.defaultBackoff)
            : nil
        persist()
    }

    private func persist() {
        if let bundle, let data = try? JSONEncoder().encode(bundle) {
            defaults.set(data, forKey: Self.snapshotKey)
        } else if bundle == nil {
            defaults.removeObject(forKey: Self.snapshotKey)
        }
        let raw = failures.reduce(into: [String: AILimitReadFailure]()) { out, pair in
            out[pair.key.rawValue] = pair.value
        }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.failuresKey)
        }
        persistSchedule()
    }

    /// 간격·금지창만 내려쓴다(숫자보다 자주, 러너 전에도 불린다).
    private func persistSchedule() {
        if let lastAttemptAt {
            defaults.set(lastAttemptAt.timeIntervalSince1970, forKey: Self.lastAttemptKey)
        } else {
            defaults.removeObject(forKey: Self.lastAttemptKey)
        }
        if let silentUntil {
            defaults.set(silentUntil.timeIntervalSince1970, forKey: Self.silentUntilKey)
        } else {
            defaults.removeObject(forKey: Self.silentUntilKey)
        }
    }
}

// MARK: - 프로덕션 조립

extension AILimitStore {
    /// 라이브 스토어. **저장소에서 이 함수를 부르는 프로덕션 지점은 `CheckApp.swift` 한 줄뿐이다**
    /// (`CodexAccountUsageStore.live()` 와 같은 규약 — 기본값은 무해 인스턴스라 테스트가 실제 자격증명을
    /// 건드리지 않는다).
    package static func live(
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appVersion: String,
        session: URLSession = .shared
    ) -> AILimitStore {
        let runner = liveRunner(home: home, appVersion: appVersion, session: session)
        return AILimitStore(defaults: defaults, runner: runner)
    }

    /// 리더 셋을 **동시에** 돌리는 러너. 셋이 서로를 기다리지 않아야 한다 — `agy` 는 5초짜리라
    /// 직렬로 묶으면 팝오버를 연 사람이 그만큼 더 기다린다.
    /// `nonisolated` 인 이유: 클로저 셋을 **조립만** 하므로 메인 액터일 필요가 없고, 그래야 실증 하네스나
    /// 배경 작업이 메인을 잡지 않고 한 바퀴를 돌려 볼 수 있다(`live()` 는 스토어를 만들어야 해서 메인이다).
    package nonisolated static func liveRunner(
        home: URL,
        appVersion: String,
        session: URLSession,
        processRunner: AILimitCommandRunner? = nil,
        fetcher: AILimitHTTPFetcher? = nil,
        locateAntigravity: (@Sendable () -> URL?)? = nil,
        codexHome: URL? = nil
    ) -> Runner {
        let process = processRunner ?? AILimitProcess.live()
        let fetch = fetcher ?? AILimitHTTP.fetcher(session: session)
        let claude = AILimitClaudeReader(runner: process, fetch: fetch, appVersion: appVersion)
        let codex = AILimitCodexReader(
            fetch: fetch,
            // 주입 지점이 있는 까닭은 `locateAntigravity` 와 같다: 기본 해결은 **이 맥의 셸 캐시**
            // (`CODEX_HOME` — Orca 가 바꿔 놓는 그 값)를 읽으므로, 주입이 없으면 "켠 Codex 는 실제로
            // chatgpt.com 을 친다"는 대조군이 기계마다 초록·회색으로 갈린다. 그러면 '꺼진 Codex 를 읽는'
            // 퇴행이 들어와도 스위트가 조용히 통과한다(기준선이 같은 입력이면 영원히 초록).
            codexHome: codexHome
                ?? CodexAccountUsageProbe.cachedCodexHome()
                ?? home.appendingPathComponent(".codex", isDirectory: true),
            appVersion: appVersion
        )
        let antigravity = AILimitAntigravityReader(
            runner: process,
            // 주입 지점이 있는 까닭: 기본 탐색은 **이 맥의 PATH** 를 읽어 `agy` 가 깔려 있는지에 따라 결과가
            // 갈린다. 그러면 "켠 제공자는 실제로 불린다"는 대조군이 기계마다 초록·회색으로 바뀌어,
            // 게이트를 통째로 지워도 스위트가 조용히 통과하는 날이 온다(기준선이 같은 입력이면 영원히 초록).
            locate: locateAntigravity ?? { AILimitAntigravityReader.liveLocate(home: home) }
        )
        return { now, providers in
            // ★ **꺼진 제공자의 리더를 부르지 않는다.** 결과를 받아서 버리는 구현과 눈에 보이는 차이가
            //   여기다: 부르지 않으면 `security`(키체인)·`auth.json`·`agy` 에 손이 닿지 않고 제공자 API 도
            //   치지 않는다. 설정을 끈 사람에게 그게 전부다(머리말 '끄면 읽지도 올리지도 않는다').
            //   빈 집합이면 자식 작업이 하나도 안 떠서 묻는 데 드는 비용도 0 이다.
            typealias Reading = (AILimitProvider, Result<AILimitProviderSnapshot, AILimitReadError>)
            return await withTaskGroup(of: Reading.self) { group in
                // 셋이 서로를 기다리지 않아야 한다 — `agy` 는 5초짜리라 직렬로 묶으면 팝오버를 연 사람이
                // 그만큼 더 기다린다(그래서 `async let` 셋을 작업 그룹으로 바꿔도 동시성은 그대로다).
                if providers.contains(.claude) { group.addTask { (.claude, await claude.read(now: now)) } }
                if providers.contains(.codex) { group.addTask { (.codex, await codex.read(now: now)) } }
                if providers.contains(.antigravity) { group.addTask { (.antigravity, await antigravity.read(now: now)) } }
                var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [:]
                for await (provider, result) in group { results[provider] = result }
                return AILimitReadOutcome(results: results)
            }
        }
    }
}
#endif
