import CheckCore
import Foundation
import Observation
import OSLog

/// 한 게임의 순위 칸 — **오늘과 역대 두 판**이 함께 산다(머리의 [오늘 | 역대] 전환이 고르는 것은 보기이고,
/// 표는 게임마다 이 한 칸에 모인다). 이름이 `board` 인 자리는 그대로 두었다 — 오늘 순위 쪽 호출부가 많다.
package struct GamesMiniGameBoard: Equatable {
    package var entries: [MiniGameBoardEntry] = []
    package var yesterdayWinner: MiniGameWinner?
    /// 이번 로그인에서 한 번이라도 받았다(빈 목록을 "아직 모른다"와 가른다).
    package var loaded = false
    package var loading = false
    package var failed = false

    // MARK: 역대 순위 (맥 0.3.67 → 폰 1.0.15)
    //
    // 그 게임의 **역대** 최고(사람마다 한 줄 — `minigame_alltime_board`). [역대] 를 **고를 때 처음** 받는다:
    // 오늘 순위처럼 미리 받지 않는다(안 보는 사람에게 호출이 가면 안 된다 — 설계서 ②).
    // 3플래그 규약은 위 오늘 순위와 같고, 넷째 깃발 `allTimeUnavailable` 이 하나 더 있다 —
    // 서버에 함수가 아직 없는 창은 **실패가 아니다**(맥 `miniGameAllTimeUnavailable` 과 같은 판정).
    package var allTime: [MiniGameAllTimeEntry] = []
    package var allTimeLoaded = false
    package var allTimeLoading = false
    package var allTimeFailed = false
    package var allTimeUnavailable = false

    package init() {}

    /// 오늘 한 사람 수를 **안다**(정족수 줄 "오늘은 아직 아무도 안 했어요 · 5명부터 지급"을 그려도 된다).
    /// 줄이 하나라도 있으면 적어도 그만큼은 했다. 비어 있으면 받은 적이 있고 마지막 조회가 실패하지 않았을 때만 0명이다 —
    /// 불러오지 못한 순위를 "아무도 안 했다"로 말하지 않는다(games-verify: 실패 카드에 두 말이 함께 떴다).
    package var knowsPlayerCount: Bool {
        MobileLoadKnowledge.knowsCount(hasRows: !entries.isEmpty, hasLoaded: loaded, lastFailed: failed)
    }

    /// 빈 순위 자리를 무엇으로 채우는가(공용 규칙 — 순위 탭 미니게임 판과 같다).
    package var placeholder: MobileLoadKnowledge.Placeholder {
        MobileLoadKnowledge.placeholder(hasRows: !entries.isEmpty, hasLoaded: loaded, lastFailed: failed)
    }

    /// [역대] 빈 자리에 **[다시 시도] 를 다는가** — 한 번도 못 받았고 마지막 조회가 실패했을 때만
    /// (맥 `MiniGamePanel` 의 `store.miniGameAllTimeFailed, !store.miniGameAllTimeLoaded` 와 같은 조건).
    ///
    /// 공용 `MobileLoadKnowledge.placeholder` 를 쓰지 않는 이유: 이 판에는 **넷째 상태**가 있다(준비 중 — 서버에 함수가
    /// 아직 없는 창). 그 상태는 `allTimeLoaded = true` · 줄 0 으로 들어와 공용 규칙에서는 `.empty` 지만 문구는
    /// "아직 기록이 없어요"가 아니라 "준비 중"이어야 한다. 문구와 버튼을 **한 조건에서** 내지 않으면 "준비 중" 옆에
    /// [다시 시도] 가 붙어 같은 404 를 영원히 두드리게 된다(맥이 그 고리를 일부러 막았다).
    package var allTimeShowsRetry: Bool { allTimeFailed && !allTimeLoaded }

    /// [역대] 빈 자리 문구(맥 `allTimeEmptyText` 와 같은 순서 — 실패 → 준비 중 → 불러오는 중 → 아직 없음).
    package var allTimeEmptyText: String {
        GamesMiniGameText.allTimeEmpty(failed: allTimeFailed, loaded: allTimeLoaded, unavailable: allTimeUnavailable)
    }
}

/// 미니게임 허브(SPEC-ios §3.5) — 오늘 순위 · 로컬 최고 · 라운드 토큰 · 점수 제출 · 공개 여부. 맥 `WorkTimerStoreMiniGame` 의
/// 흐름을 폰 세션 위에 다시 썼다(맥 스토어는 폰에서 못 쓴다 — ios-inventory §4.3).
///
/// 라운드 토큰 흐름(맥과 같다)
/// 1. **화면을 열 때 미리 받는다**(`openScreen`). 판 시작에 받으면 플래피 즉사처럼 1초 안에 끝나는 판은 왕복이 못 끝나
///    점수를 통째로 버린다. 일찍 받을수록 서버가 재는 경과가 길어져 **더 관대하다**(정직한 플레이를 못 막는다).
/// 2. 판이 시작될 때 쓸 수 있는 토큰이 없으면(선발급 실패·20분 지남) 그때 받는다. 게임을 막지 않는다(Task 로 띄운다).
/// 3. 판이 끝나면 토큰을 **로컬에서 먼저 비우고** 제출한다(한 토큰에 한 점수). 성공이든 거절이든 다음 토큰을 미리 받는다.
/// 4. 들고 있는 토큰이 쓸 만하면 다시 받지 않는다 — 다시 받으면 서버가 started_at 을 now() 로 되돌려 벌어 둔 여유가 사라진다.
/// 5. 늦게 온 토큰 응답은 버린다(`roundGeneration`). 서버는 (사용자, 게임)당 미사용 토큰을 한 행만 두고 갈아 끼운다.
/// 6. `minigame_public == false` 면 토큰도 제출도 없다(설정 문구가 약속한 "올라가지도 않아요").
///
/// 폰 규칙(1.0.16): **앱이 내려가면 판을 얼린다**(`appWillResignActive` · `appDidEnterBackground`), 화면을 떠나면 끝낸다(`endRound()`).
/// 끝내는 결과는 게임마다 다르다 — 타이밍 바·플래피는 기록 없이 버리고, **테트리스·길건너는 여기까지의 점수로 확정해 제출한다**
/// (`GamesMiniGamePausePolicy`). 로그아웃(`reset`)은 **`abandon()` 그대로**다 — 남의 계정에 올리면 안 된다.
///
/// 일시정지(맥 v0.2.48 → 폰 1.0.16 — 전이는 코어 `MiniGamePauseState` 한 벌, 아래 일시정지 절):
///  · 맥과 **같은 것**: 스크림 · 카드 · 3-2-1 · 자동 정지는 절대 풀지 않음 · 상한 5분 · 상한은 접어도 기록이 남는 게임에만.
///  · 맥과 **다른 것 셋**: ① 시계가 벽시계다(1초씩 자는 Task 는 background 에서 멈춘다) ② 3-2-1 도 상한에 든다(맥은 안 세어서
///    카드↔3-2-1 왕복으로 영영 안 찬다) ③ 플래피를 접으면 버리므로 플래피에 상한이 없다.
///  · **임시 항목**: 얼린 판은 끝난 판이 아니라서 iOS 가 앱을 죽이면 점수가 사라진다. 그래서 테트리스·길건너는 내려갈 때 지금 점수·토큰을
///    따로 적어 둔다(`pauseDraftKey`). 인편과 **키가 다르다** — 인편에 넣으면 도는 판의 토큰이 나가 버린다. 다음 실행에 남아 있으면 인편으로 올린다.
///
/// 제출 인편(`pendingSubmits` · 맥 v0.3.39 → 폰 1.0.16 — 타입과 판정은 코어 `MiniGamePendingSubmit` 한 벌): 끝난 판의 점수는
/// 제출 **전에** 대기열에 적고 계정별로 영속한다. 지우는 것은 `ok`·`token_used`·terminal 거절·TTL(30분)뿐이고, 네트워크 실패·
/// `too_fast` 는 2 → 8 → 30초 간격으로 **같은 토큰으로** 되보낸다. 판이 끝난 순간 토큰이 없으면 토큰을 기다리고,
/// `no_token` 은 한 번 되살린다(다른 기기가 토큰을 갈아 끼운 판).
///
/// ★ 불변식: **그 게임의 인편이 살아 있는 동안 그 게임의 `start_round` 는 나가지 않는다.**
///   서버가 (사용자, 게임)당 미사용 토큰을 한 행만 두고 갈아 끼우므로, 순서가 뒤집히면 인편의 점수가 `no_token` 으로 죽는다.
///
/// 맥과 다른 점 둘 — 전부 폰이어서다.
///  · **방아쇠(앱 복귀·화면 열기·판 시작·판 끝)는 백오프도 푼다.** 맥의 깨어남은 깨어난 뒤 연결을 기다리는 게이트가 따로 있지만,
///    폰은 복귀가 곧 사람이 돌아왔다는 신호다. 사람의 행동 한 번에 한 번이라 두드리기가 되지 않는다(꼬리·타이머는 `fromTrigger: false`).
///  · **다른 게임 판이 도는 중에는 토큰을 기다리는 인편에 토큰을 받아 주지 않는다**(토큰 칸이 하나라 그 판의 토큰을 치운다). 판이 끝나면 밀린다.
/// 진단: 거절 status 이름까지만 로그에 남긴다 — need_seconds·elapsed_seconds 는 화면에도 로그에도 쓰지 않는다(위조 보조 도구).
@MainActor
@Observable
package final class GamesMiniGameHub {
    /// 토큰을 새로 받는 기준(초). 서버 TTL 30분보다 넉넉히 짧다(맥 `miniGameTokenRefreshSeconds`).
    ///
    /// ⚠️ v0.3.38 부터 **게임별**이다 — 판정은 `MiniGameKind.roundTokenReuseSeconds` 한 곳에서 나온다(테트리스는 12분).
    /// 이 상수는 기존 두 게임의 값(20분)을 가리키는 별명으로 남긴다: 여기를 고쳐도 테트리스는 안 움직인다.
    package nonisolated static let tokenRefreshSeconds: TimeInterval = MiniGameKind.flappy.roundTokenReuseSeconds
    /// 정지 감시 간격(초 · 맥 `armPauseWatchdog` 과 같은 1초).
    package nonisolated static let pauseWatchInterval: TimeInterval = 1
    /// 첫 화면 카드(오늘 최고·순위)를 다시 읽는 간격(초).
    package nonisolated static let summaryThrottleSeconds: TimeInterval = 60

    /// 한 판의 **벽시계 상한**(초 · 폰 테트리스만). `beginRound` 가 구동기에 건넨다.
    ///
    /// 검산: 토큰 재사용 12분 + 판 15분 + 제출 여유 1분 = 28분 < 서버 TTL 30분. 그리고 15분은 시뮬 최장 판
    /// 8.7분의 1.72배라 정직한 판은 안 걸린다. 왜 필요한가: 엔진의 **고의 늘어뜨리기 상계가 24.7분**이라
    /// 12 + 24.7 = 36.7 > 30 이다 — 상한이 없으면 24분을 쌓아 올린 판이 통째로 거절된다(클램프가 아니라 거절).
    /// 사용자 스위치로 주지 않는다(2026-09-15 '자동 종료는 사용자 스위치로 주지 않는다').
    package nonisolated static let tetrisRoundLimitSeconds: TimeInterval = 15 * 60

    /// 서버 status 분류 — 코어 한 벌(`MiniGameSubmitRules`). 까닭은 그쪽 주석.
    ///
    /// `too_fast` 가 정직한 판에 닿는 길이 둘이다: 타이밍바는 하한과 실제 최소의 여유가 **0.1906초**뿐이라 플레이 중에 생긴 토큰이면
    /// 하한 밑으로 나오고, 길건너는 판 도중 갈아 끼운 직후 끝나면 새 토큰 기준으로 다시 재서 **길면 450초**를 기다려야 한다
    /// (상한 5000 × 0.09초 — `MiniGameKind.roundTokenMidRunRefreshSeconds`). 그래서 횟수가 아니라 TTL 이 끝을 낸다.
    /// ⚠️ 서버가 같이 주는 `need_seconds`·`elapsed_seconds` 로 지연을 **계산하지 않는다** — 간격은 눈먼 고정값뿐이다(위조 보조 도구).
    nonisolated static let terminalSubmitStatuses = MiniGameSubmitRules.terminalStatuses
    nonisolated static let retryableSubmitStatuses = MiniGameSubmitRules.retryableStatuses
    nonisolated static let deadTokenStatuses = MiniGameSubmitRules.deadTokenStatuses

    nonisolated static let logger = Logger(subsystem: "aingcheck", category: "minigame")

    /// 기다리기(테스트는 즉시 돌아오는 것으로 바꾼다 — `MessagesStore.sleep` 과 같은 장치).
    @ObservationIgnored package var sleep: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }

    @ObservationIgnored package let context: MobileContext

    /// 지금 열려 있는 게임 화면(없으면 nil).
    package private(set) var activeKind: MiniGameKind?
    /// 열린 화면의 엔진 구동기. 화면마다 새로 만든다.
    package private(set) var controller: GamesPlayController?
    package private(set) var boards: [MiniGameKind: GamesMiniGameBoard] = [:]
    /// 순위 머리가 보여 주는 판 [오늘 | 역대](맥 0.3.67 → 폰 1.0.15). **허브 하나의 상태다** — 게임마다 기억하지 않는다
    /// (맥 `WorkTimerStore.miniGameBoardScope` 와 같다). 앱이 떠 있는 동안만 기억하고 영속하지 않으며,
    /// **로그아웃도 되돌리지 않는다**: 계정이 아니라 이 실행의 보기 선택이다(`reset()` 의 그 자리 주석).
    ///
    /// 이 값은 **[게임] 탭 미니게임 화면**의 것이다. [순위] 탭 미니게임 판은 자기 값을 따로 든다(`RankingsStore.miniGameScope`).
    package private(set) var boardScope: MiniGameBoardScope = .today
    /// 내 순위 공개 여부(profiles.minigame_public). 이번 로그인에서 아직 모르면 공개로 본다(맥과 같다 — 컬럼 없는 서버).
    /// 한 번 안 값은 조회 실패로 바뀌지 않는다(`refreshPublic`).
    package private(set) var isPublic = true
    /// 제출 실패·판 끝남 안내 한 줄.
    package private(set) var submitNotice: String?
    /// 로컬 최고(계정별 — 관찰용 미러). 읽기는 `best(for:)`.
    package private(set) var localBest: [MiniGameKind: Int] = [:]

    // MARK: 토큰(관찰 대상 아님)
    @ObservationIgnored package private(set) var roundToken: String?
    @ObservationIgnored package private(set) var roundTokenKind: MiniGameKind?
    @ObservationIgnored package private(set) var roundTokenAt: Date?
    @ObservationIgnored package private(set) var roundGeneration = 0
    /// 지금 왕복 중인 토큰 요청의 게임(없으면 nil). 선발급이 도는 중에 판이 시작되면 **또 요청하지 않는다** —
    /// 또 보내면 서버가 started_at 을 새로 찍어 앞 요청이 벌어 둔 여유를 버린다(폰에서 화면을 열자마자 탭하는 경로).
    @ObservationIgnored package private(set) var roundTokenInFlightKind: MiniGameKind?
    /// **제출 인편** — 아직 서버가 받았다고 확인해 주지 않은 끝난 판들. 읽고 쓰는 문은 아래 인편 절 하나다(영속과 어긋나지 않게).
    @ObservationIgnored package private(set) var pendingSubmits: [MiniGamePendingSubmit] = []
    /// 메모리의 인편이 **어느 계정 것인가**(nil = 아직 안 읽었거나 로그아웃). 계정이 바뀌면 그 계정의 키에서 다시 읽는다.
    @ObservationIgnored private var pendingOwner: String?
    /// 지금 제출 왕복이 떠 있는 게임들(같은 토큰을 두 번 동시에 보내지 않게).
    @ObservationIgnored private var submittingKinds: Set<MiniGameKind> = []
    /// 실패 뒤 백오프 타이머(한 개 — 가장 먼저 돌아오는 인편에 맞춘다).
    @ObservationIgnored private var pendingRetryTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRetryTarget: Date?
    /// 이번 로그인에서 공개 여부를 서버에게 **들었다.** 디스크에서 되살린 인편은 이걸 안 뒤에만 나간다 — `isPublic` 의 기본값은 "모름 = 공개"라
    /// 재시작 직후에 그대로 믿으면 그 사이 공개를 끈 사람의 점수가 나간다(`refreshPublic` 주석의 games-verify PROBE-1 과 같은 구멍).
    @ObservationIgnored private var publicIsKnown = false
    @ObservationIgnored private var pendingAwaitsPublicCheck = false
    @ObservationIgnored private var isCheckingPublicForPending = false
    /// 상한에서 세운 안내("5분 넘게 멈춰서 …")를 **비동기 제출 성공이 지우지 않게** 붙든다.
    /// 성공 갈래는 `submitNotice = nil` 인데, 그게 이 문장을 지우면 사용자에게는 판이 조용히 사라진 것처럼 보인다.
    @ObservationIgnored private var exitNoticeIsSticky = false
    @ObservationIgnored private var resetGeneration = 0
    @ObservationIgnored private var lastSummaryAt: Date = .distantPast

    // MARK: 일시정지(관찰 대상 아님 — 화면은 `controller.pauseState` 를 본다)

    /// 3-2-1 · 정지 감시의 기다리기. **`sleep` 과 일부러 나눴다** — 테스트가 `sleep` 을 즉시 돌아오는 것으로 바꾸므로, 같은 값을 쓰면
    /// 시계가 안 흐르는 빌드에서 감시 고리가 메인 액터를 잡고 돈다. 시험은 `advanceResumeCountdown` · `pauseWatchTick` 을 직접 부른다.
    @ObservationIgnored package var pauseSleep: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }
    /// 이번 판에서 이미 **닫힌** 정지 구간의 합(초). 새 판에서만 0 이 된다 — 회당이면 정지를 풀었다 걸기만 해도 상한이 되돌아간다.
    @ObservationIgnored private var frozenSecondsBanked: TimeInterval = 0
    /// 지금 열려 있는 정지 구간의 시작 시각(`.none` 이면 nil).
    @ObservationIgnored private var frozenSince: Date?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var pauseWatchTask: Task<Void, Never>?
    /// 정지 중 토큰 감시를 마지막으로 돈 시각(길건너만).
    @ObservationIgnored private var lastFrozenKeepAliveAt: Date?
    /// 앱이 background 에 있다 — 잠깐 도는 감시가 그 사이 판을 끝내지 않게(복귀가 판정한다).
    @ObservationIgnored private var isInBackground = false
    /// 이 실행에서 임시 항목을 적은 계정. 살아 있는 판의 것이라 **인편으로 올리지 않는다**(다음 실행에 남은 것만 올린다).
    @ObservationIgnored private var liveDraftOwner: String?
    /// 엔진 시드 — 화면을 열 때마다 달라야 같은 판이 반복되지 않는다(데모 고정 시계에서도).
    @ObservationIgnored private var seedCounter: UInt64 = 0

    // MARK: 역대 순위 신선도(관찰 대상 아님 — 화면은 이 값을 그리지 않는다)

    /// 지금 들고 있는 역대 표가 **어느 게임의 최신 응답인가.** nil 이거나 다른 게임이면 다음에 [역대] 를 고를 때 다시 받는다 —
    /// 게임을 바꿨거나, [오늘] 을 보는 사이 그 게임 판이 기록돼 표가 낡았다(새 개인 최고가 들어갔을 수 있다).
    /// 게임마다 한 칸이 아닌 이유는 맥과 같다: 전환을 들고 있는 미니게임 화면은 **한 번에 한 장**이다.
    @ObservationIgnored package private(set) var allTimeFreshKind: MiniGameKind?
    /// 역대 표가 **낡았다고 표시된 횟수**(판이 서버에 남을 때 오른다). 받기를 시작할 때 이 값을 쥐고, 응답이 왔을 때 그 사이
    /// 올랐으면 그 응답을 '최신'으로 **표시하지 않는다** — 제출 **전에** 떠난 받기가 제출 **뒤에** 닿아 최신 표시를 다시
    /// 세우면, [역대] 로 넘어가도 새 개인 최고가 빠진 표를 안 받는다(맥 검토 지적 2026-10-27 · `bc9a64c` 6번).
    @ObservationIgnored package private(set) var allTimeInvalidation = 0
    /// 역대 받기의 일련번호와, 마지막으로 **반영한** 받기의 번호. 늦게 닿은 옛 받기가 새 표를 덮지 않게 한다 —
    /// 사람이 전환을 누른 받기와 판이 끝나 다시 받는 받기가 겹칠 때 **늦게 온 쪽이 이기던** 결함(같은 커밋).
    @ObservationIgnored package private(set) var allTimeFetchSerial = 0
    @ObservationIgnored package private(set) var allTimeAppliedSerial = 0

    package init(context: MobileContext) {
        self.context = context
    }

    // MARK: 화면

    /// 게임 화면이 열렸다. 오늘 순위·어제 1등·공개 여부를 읽고 **토큰을 미리 받는다**.
    package func openScreen(_ kind: MiniGameKind) {
        if activeKind == kind, controller != nil {
            enforcePauseCap()
            return
        }
        // 화면 경합 정리는 **버리는 것**이다(`abandon()`) — 사람이 쌓아 올린 판을 끝내는 자리가 아니다.
        // ★ 단 **얼려 둔 판은 다르다**: 정지 카드를 띄운 채 알림을 눌러 다른 게임 화면이 열리면(새 화면의 등장이 옛 화면의 퇴장보다 먼저 올 수 있다)
        //   그 판은 사람이 쌓아 올린 판이다 — 맥이 정지 중 다른 게임으로 넘어갈 때처럼 [그만두기]와 같은 결과로 접는다.
        if let controller, controller.isFrozen {
            endFrozenRound(controller, notice: nil)
        } else {
            controller?.abandon()
        }
        activeKind = kind
        submitNotice = nil
        exitNoticeIsSticky = false
        seedCounter &+= 1
        let seed = UInt64(truncatingIfNeeded: Int64(context.clock.now().timeIntervalSince1970 * 1000)) &+ seedCounter &* 0x9E37_79B9_7F4A_7C15
        let controller = GamesPlayController(kind: kind, seed: seed)
        controller.onStarted = { [weak self] in self?.beginRound(kind: kind) }
        controller.onFinished = { [weak self] score in self?.recordScore(kind: kind, score: score) }
        // 끝이 정해지지 않은 판(길건너)만 판 도중에 토큰을 갈아 끼운다. 나머지는 프레임마다 시간을 재지도 않는다.
        if kind.roundTokenMidRunRefreshSeconds != nil {
            controller.onRoundKeepAlive = { [weak self] in self?.keepRoundTokenFresh(kind: kind) }
        }
        self.controller = controller
        loadLocalBest(kind)
        guard context.session.isSignedIn else { return }
        // 화면을 닫아 둔 사이에 죽은 점수가 있으면 **여기서 한 번 말하고 표식을 지운다**(아래 밀기가 문구를 덮기 전에).
        showLostNoticeIfAny()
        let generation = resetGeneration
        Task { [weak self] in
            // 공개 여부를 **먼저** 안다 — 끈 사람에게 토큰을 받아 두지 않는다. 그 왕복 동안 판이 시작되면 `beginRound` 가
            // (아직 공개로 보고) 토큰을 받는다: 제출은 끝날 때 다시 공개 여부를 보므로 끈 사람의 점수는 여전히 안 나간다.
            await self?.refreshPublic()
            guard let self, generation == self.resetGeneration, self.activeKind == kind else { return }
            // 인편이 남아 있으면 **먼저 밀어낸다.** 선발급은 살아 있는 인편을 보면 스스로 비켜서므로
            // (`prefetchRoundToken` 의 가드), 여기서 인편을 풀어 두지 않으면 사람이 탭할 때까지 토큰이 없다.
            // 비워지는 순간 `performSubmit` 의 꼬리가 새 토큰을 받아 주므로 대개 첫 탭 전에 준비가 끝난다.
            self.retryPendingSubmitIfAny()
            self.prefetchRoundToken(kind: kind)
            await self.loadBoard(kind, withWinner: true)
            // [역대] 를 보던 채로 화면을 다시 열었다(또는 다른 게임으로 넘어왔다) — 그 게임의 역대도 받는다.
            // [오늘] 이면 **아무것도 안 나간다**(역대는 처음 넘어갈 때 받는다). 오늘 순위 **뒤에** 두는 이유는
            // 머리 줄·정족수가 오늘 표를 먼저 쓰기 때문이다(맥도 선발급·오늘 순위가 먼저다).
            //
            // ★ **이미 그 게임의 받기가 떠 있으면 얹지 않는다**(`allTimeLoading`). 이 꼬리는 `loaded` 가 선 **뒤에**
            //   돌아서(순위를 넣고 어제 1등을 await 한 다음이다), 화면을 여는 동안 사람이 [역대] 를 누르면
            //   전환과 이 꼬리가 **같은 표를 받으러 둘이 나간다**(실측: 일련번호가 1 이 아니라 3 까지 갔다).
            //   여기만 비켜선다 — 이 자리의 뜻은 "표가 있게 하자"이고, 판이 끝났을 때의 재조회는 "내 표가 낡았다"라
            //   떠 있는 받기가 있어도 **반드시** 나가야 한다(그 둘이 겹칠 때 새 쪽이 이기는 것이 일련번호 가드의 몫이다).
            if self.boardScope == .allTime, self.boards[kind]?.allTimeLoading != true {
                await self.performLoadAllTimeBoard(kind)
            }
        }
    }

    /// 게임 화면을 떠났다. 진행 중인 판은 **끝낸다**(`endRound()` — 테트리스·길건너는 여기까지의 점수로 확정 제출).
    /// 얼려 둔 판도 같다 — 정지 중 뒤로 가기는 [그만두기]와 같은 결과다.
    /// 토큰은 들고 있는다(재사용 나이 안에 다시 열면 그대로 쓴다).
    ///
    /// 안내 한 줄은 세우지 않는다 — 이 화면은 지금 사라지는 중이고, 다시 열면 `openScreen` 이 어차피 비운다.
    package func closeScreen(_ kind: MiniGameKind) {
        guard activeKind == kind else { return }
        if let controller {
            endFrozenRound(controller, notice: nil)
        }
        controller = nil
        activeKind = nil
    }

    /// 장면이 앞에서 물러난다(`.inactive` — 전화 수신 · 제어 센터 · 앱 전환기). 도는 판을 얼린다.
    ///
    /// background 까지 기다리지 않는다: 앱 전환기 스냅숏은 그 전에 찍히고, 앱 전환기에서 쓸어 올려 죽이면 background 가 안 올 수도 있다.
    package func appWillResignActive() {
        freezeForSceneChange()
    }

    /// 앱이 background 로 간다. **판은 끝나지 않고 얼어 있는다**(폰 1.0.16 — 전화에 판이 산다).
    /// 대신 iOS 가 앱을 죽여도 테트리스·길건너 점수가 남도록 임시 항목을 적는다(`writePauseDraft`).
    package func appDidEnterBackground() {
        isInBackground = true
        freezeForSceneChange()
    }

    /// 장면이 앞으로 왔다. 상한을 재고, 넘지 않았으면 토큰을 챙긴다. **자동으로 풀지 않는다** — 사람이 [이어하기] 를 눌러야 한다.
    package func sceneDidComeForward() {
        isInBackground = false
        guard let controller, controller.isFrozen else { return }
        if enforcePauseCap() { return }
        keepFrozenRoundTokenFresh(controller)
    }

    /// 로그아웃·치명 만료. 계정에 묶인 값을 전부 비운다.
    ///
    /// 여기는 **`abandon()` 그대로**다 — 남의 계정으로 넘어가는 자리에서 앞 사람의 판을 제출하면 안 된다.
    package func reset() {
        resetGeneration &+= 1
        roundGeneration &+= 1
        stopPauseTasks()
        resetPauseClock()
        // 얼려 둔 판의 임시 항목도 함께 지운다 — 로그아웃은 그 판을 버리는 자리다(`abandon()` 과 같은 뜻).
        clearPauseDraft()
        controller?.abandon()
        controller = nil
        activeKind = nil
        boards = [:]
        // 역대 표도 남의 행이라 계정에 묶인다(`boards` 가 통째로 비었다). 신선도 표식만 따로 되돌린다.
        // **보기 선택(`boardScope`)은 그대로 둔다** — 계정이 아니라 이 앱 실행의 것이다(맥과 같은 선택).
        allTimeFreshKind = nil
        allTimeInvalidation &+= 1
        isPublic = true
        submitNotice = nil
        exitNoticeIsSticky = false
        localBest = [:]
        roundToken = nil
        roundTokenKind = nil
        roundTokenAt = nil
        roundTokenInFlightKind = nil
        // 인편은 **메모리만** 비운다 — 디스크의 것은 계정별 키에 남아 같은 계정의 다음 로그인에서 살아난다(TTL 안이면).
        pendingSubmits = []
        pendingOwner = nil
        submittingKinds = []
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        pendingRetryTarget = nil
        publicIsKnown = false
        pendingAwaitsPublicCheck = false
        // 떠 있는 앞 로그인의 조회는 세대 가드가 버린다 — 이 깃발이 남으면 다음 로그인의 인편이 묻지도 못하고 멈춘다.
        isCheckingPublicForPending = false
        lastSummaryAt = .distantPast
    }

    // MARK: 첫 화면 카드

    /// 첫 화면이 보였다: **폰에 보이는 게임**(`MiniGameKind.phoneCases`)의 오늘 순위(카드의 "오늘 최고·순위")를 읽는다.
    /// 60초 스로틀. 안 보이는 게임까지 돌면 폰이 쓰지 않는 순위표를 60초마다 한 번씩 더 받아 온다.
    package func refreshSummariesIfStale() {
        guard context.session.isSignedIn else { return }
        let now = context.clock.now()
        guard now.timeIntervalSince(lastSummaryAt) >= Self.summaryThrottleSeconds else { return }
        lastSummaryAt = now
        for kind in MiniGameKind.phoneCases {
            loadLocalBest(kind)
            Task { [weak self] in await self?.loadBoard(kind, withWinner: false) }
        }
    }

    /// 오늘 내 순위(1부터). 순위표에 없으면 nil.
    package func myRank(_ kind: MiniGameKind) -> Int? {
        guard let me = myUserID, let index = boards[kind]?.entries.firstIndex(where: { $0.userID == me }) else { return nil }
        return index + 1
    }

    /// 오늘 내 순위표 점수(없으면 nil).
    package func myTodayBest(_ kind: MiniGameKind) -> Int? {
        guard let me = myUserID else { return nil }
        return boards[kind]?.entries.first { $0.userID == me }?.bestScore
    }

    /// 결과 카드의 "최고 N" — 로컬 최고와 오늘 내 행 중 큰 쪽(맥 허브와 같다).
    package func best(for kind: MiniGameKind) -> Int {
        max(localBest[kind] ?? 0, myTodayBest(kind) ?? 0)
    }

    // MARK: 토큰 · 제출

    /// 들고 있는 토큰이 이 게임에 **지금** 쓸 만한가.
    package func hasUsableRoundToken(for kind: MiniGameKind) -> Bool {
        guard roundToken != nil, roundTokenKind == kind, let issued = roundTokenAt else { return false }
        // 나이 기준은 **게임별**이다(테트리스 판은 길어서 12분 — MiniGameKind.roundTokenReuseSeconds 의 검산).
        return context.clock.now().timeIntervalSince(issued) < kind.roundTokenReuseSeconds
    }

    /// 토큰을 미리 받는다(화면 열기 · 제출 뒤). 쓸 만한 토큰이 있으면 다시 받지 않는다.
    package func prefetchRoundToken(kind: MiniGameKind) {
        guard isPublic, context.session.isSignedIn else { return }
        // ★ 그 게임의 **인편이 살아 있으면 받지 않고 인편부터 민다.** 서버는 (사용자, 게임)당 미사용 토큰을 한 행만 두고
        //   새 요청이 오면 갈아 끼운다(`minigame_rounds_one_open`) — 그래서 `requestRoundToken` 주석의
        //   "새 요청이 나가는 순간 들고 있던 것은 죽는다"가 **인편이 들고 있는 토큰에도 그대로** 걸린다.
        //   막힌 채로 굳지 않는다: 인편이 비워지는 순간 `performSubmit` 의 꼬리가 여기를 다시 불러 새 토큰을 받는다.
        if hasPendingSubmit(for: kind) {
            retryPendingSubmitIfAny()
            return
        }
        guard !hasUsableRoundToken(for: kind) else { return }
        guard roundTokenInFlightKind != kind else { return }
        // 다른 게임의 인편이 토큰을 기다리며 왕복 중이면 비킨다 — 토큰 칸이 하나라 새 요청은 그 응답을 세대 가드로 버리고,
        // 그 인편에는 왕복도 타이머도 안 남아 다음 방아쇠까지 굳는다. 선발급은 급하지 않다: 그 인편의 제출 꼬리가 여기를 다시 부르고, 판 시작도 받는다.
        if let inFlight = roundTokenInFlightKind, pendingSubmits.contains(where: { $0.kind == inFlight && $0.token == nil }) { return }
        requestRoundToken(kind: kind)
    }

    /// 판이 시작됐다(엔진 onStarted). 쓸 만한 토큰이 없을 때만 받는다 — 게임은 기다리지 않는다.
    package func beginRound(kind: MiniGameKind) {
        resetPauseClock()
        // 판 벽시계 상한은 **가드보다 먼저** 건다: 순위 공정성 장치라 공개 여부·로그인과 무관하다.
        // 기존 두 게임은 nil(판이 스스로 끝나거나 자동잠금이 판을 얼린다 — `GamesStore.wantsIdleTimerDisabled`).
        // **길건너도 nil 이다**(폰 1.0.15 D4): `CrossyGame.idleLimit` 9초가 가만히 있는 판을 이미 죽이므로
        // 벽시계 상한이 할 일이 없다(테트리스는 조각을 세워 두고 생각하는 무입력 구간이 있어 필요했다).
        //
        // ⚠️ **길이를 건넨다(절대 시각이 아니다).** 마감을 재는 축은 구동기의 `tick(at:)` 하나뿐인데 그 `now` 는
        //    `TimelineView` 가 주는 실제 벽시계다 — 여기서 `context.clock.now()` 로 찍으면 두 축이 섞여
        //    시계를 주입한 빌드(데모·테스트)에서 판이 첫 프레임에 죽는다(까닭은 `GamesPlayController.roundLimitSeconds`).
        controller?.roundLimitSeconds = kind == .tetris ? Self.tetrisRoundLimitSeconds : nil
        exitNoticeIsSticky = false
        guard isPublic, context.session.isSignedIn else { return }
        submitNotice = nil
        guard !hasUsableRoundToken(for: kind) else { return }
        // ★ 이 게임의 인편이 살아 있으면 토큰을 받는 대신 **인편부터 밀어낸다**(까닭은 `prefetchRoundToken` 의 가드).
        //   이번 판이 토큰 없이 시작될 수는 있다 — 그러면 이 판의 점수는 토큰을 기다리는 인편이 되어 앞 인편이 비워진 뒤
        //   토큰을 받는다. 앞 판을 확실히 버리는 것보다 싸다.
        if hasPendingSubmit(for: kind) {
            retryPendingSubmitIfAny()
            return
        }
        guard roundTokenInFlightKind != kind else { return }
        requestRoundToken(kind: kind)
    }

    /// 판 도중 토큰 갈아 끼우기(맥 v0.3.67 → 폰 1.0.16 — 길건너처럼 끝이 정해지지 않은 판). 구동기가 판이 도는 동안 30초마다 부른다.
    ///
    /// 들고 있는 그 게임의 토큰이 `roundTokenMidRunRefreshSeconds` 보다 늙었으면 새로 받는다(서버가 안 쓴 토큰을 갈아 끼우며
    /// TTL 을 새로 센다). 이게 없으면 약 28분을 넘긴 판이 다 끝난 뒤 `token_expired` 로 **통째로** 거절된다.
    /// 대가: 서버 시간 하한도 새 토큰부터 다시 잰다 — 갈아 끼운 직후에 끝난 판은 `too_fast` 를 받고 인편이 통과할 때까지 되보낸다.
    /// 아무것도 안 하는 자리: 갈아 끼우지 않는 게임 · 아직 젊다 · 이미 왕복 중이다 ·
    /// **그 게임의 인편이 살아 있다**(불변식 — 새 토큰을 받는 순간 인편이 든 옛 토큰이 죽는다. 인편을 먼저 민다).
    /// 들고 있는 토큰이 아예 없으면(판 시작 왕복이 실패했다) 받는다 — 그 판이 끝나기 전에 쥐어야 한다.
    package func keepRoundTokenFresh(kind: MiniGameKind) {
        guard let limit = kind.roundTokenMidRunRefreshSeconds else { return }
        guard isPublic, context.session.isSignedIn else { return }
        if hasPendingSubmit(for: kind) {
            // 사람의 행동이 아니라 시계가 부른 자리다 — 백오프를 풀지 않는다.
            retryPendingSubmitIfAny(fromTrigger: false)
            return
        }
        guard roundTokenInFlightKind != kind else { return }
        if roundToken != nil, roundTokenKind == kind, let issued = roundTokenAt,
           context.clock.now().timeIntervalSince(issued) < limit {
            return
        }
        Self.logger.notice("round token refreshed mid-run game=\(kind.rawValue, privacy: .public)")
        requestRoundToken(kind: kind)
    }

    private func requestRoundToken(kind: MiniGameKind) {
        // 들고 있던 것은 버린다 — 서버가 행을 갈아 끼우므로 새 요청이 나가는 순간 죽는다.
        roundToken = nil
        roundTokenKind = nil
        roundTokenAt = nil
        roundGeneration &+= 1
        roundTokenInFlightKind = kind
        let generation = roundGeneration
        Task { [weak self] in await self?.performStartRound(kind: kind, roundGeneration: generation) }
    }

    package func performStartRound(kind: MiniGameKind, roundGeneration requested: Int) async {
        defer { if requested == roundGeneration { roundTokenInFlightKind = nil } }
        guard context.session.isSignedIn else { return }
        let sessionGeneration = context.generation
        let service = context.service
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await service.startMiniGameRound(accessToken: session.accessToken, kind: kind)
            }
            guard sessionGeneration == context.generation else { return }
            // ★ 늦게 온 응답은 버린다 — 내 뒤에 나간 요청이 있었다면 내 토큰은 이미 죽었다.
            guard requested == roundGeneration else { return }
            guard response.status == "ok", let token = response.token else {
                Self.logger.notice("round token refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                deferPendingTokenWait(kind: kind)
                return
            }
            // ★ 토큰을 기다리는 인편이 있으면 **그 인편이 먼저 받는다**(살아 있는 판보다 앞). 판이 끝난 뒤에 나간 요청이었다면
            //   서버가 too_fast 를 줄 수 있는데, 경과는 자라기만 하니 백오프 재시도가 통과시킨다.
            if adoptTokenIntoWaitingPending(kind: kind, token: token) {
                retryPendingSubmitIfAny(fromTrigger: false)
                return
            }
            roundToken = token
            roundTokenKind = kind
            roundTokenAt = context.clock.now()
        } catch {
            guard requested == roundGeneration else { return }
            Self.logger.notice("round token request failed game=\(kind.rawValue, privacy: .public)")
            deferPendingTokenWait(kind: kind)
        }
    }

    /// 유효하게 끝난 판(엔진 onFinished). 범위 밖은 버리고, 로컬 최고를 올리고, 공개면 토큰과 함께 올린다.
    ///
    /// 여기서부터 점수는 **인편**이다 — 제출을 시도하기 **전에** 적는다(맥 `recordMiniGameScore` 와 같은 자리).
    package func recordScore(kind: MiniGameKind, score: Int) {
        // 얼렸던 판이 정말 끝났다 — 임시 항목의 일은 끝났다. 남겨 두면 다음 실행에 **같은 판이 또 올라간다.**
        clearPauseDraft()
        guard score >= 0, score <= kind.maxScore else { return }
        raiseLocalBest(kind, to: score)
        guard isPublic, context.session.isSignedIn else { return }
        loadPendingIfNeeded()
        var token: String?
        var issuedAt: Date?
        if let held = roundToken, roundTokenKind == kind {
            // 정지·복귀로 토큰이 이미 서버 TTL 을 넘겼다(상한 없는 플래피·타이밍 바를 오래 얼려 둔 판 · 오래 내려 뒀다 돌아온 판). 보내 봐야 `token_expired` 다.
            // "연결을 확인하고 다시 해 주세요"(인편 TTL 문구)가 아니라 **그 판은 못 올라간다**를 말한다. 새 토큰으로 되살리지 않는다 —
            // 그 점수가 다른 날 순위표에 올라갈 수 있다(`MiniGamePendingSubmit.deadline` 과 같은 근거).
            if let issued = roundTokenAt,
               context.clock.now().timeIntervalSince(issued) >= MiniGameSubmitRules.pendingTTL {
                roundToken = nil
                roundTokenKind = nil
                roundTokenAt = nil
                submitNotice = GamesMiniGameText.submitTokenDead
                exitNoticeIsSticky = false
                pushPendingAndPrefetch(after: kind)
                return
            }
            // 한 토큰에 한 점수다. 여기서 비워 두면 같은 토큰이 두 번 나가지 않는다 — 인편이 그 토큰의 유일한 주인이 된다.
            token = held
            issuedAt = roundTokenAt ?? context.clock.now()
            roundToken = nil
            roundTokenKind = nil
            roundTokenAt = nil
        } else {
            // 토큰이 없다. **버리지 않는다** — 토큰을 기다리는 인편으로 적는다. 왕복 중인 요청이 있으면 그 응답이 이 인편에 온다.
            Self.logger.notice("submit waiting for token game=\(kind.rawValue, privacy: .public)")
            submitNotice = GamesMiniGameText.submitRetrying
        }
        pendingSubmits.append(MiniGamePendingSubmit(
            id: UUID(), kind: kind, score: score, token: token, tokenIssuedAt: issuedAt, recordedAt: context.clock.now(), attempts: 0))
        persistPendingSubmits()
        retryPendingSubmitIfAny()
    }

    // MARK: 제출 인편

    /// 맨 앞 인편(없으면 nil).
    package var pendingSubmit: MiniGamePendingSubmit? {
        loadPendingIfNeeded()
        return pendingSubmits.first
    }

    /// 이 게임의 인편이 하나라도 있는가(토큰 유무 무관). TTL 을 넘긴 것은 없는 것이다.
    package func hasPendingSubmit(for kind: MiniGameKind) -> Bool {
        loadPendingIfNeeded()
        dropExpiredPendingSubmits()
        return pendingSubmits.contains { $0.kind == kind }
    }

    /// 인편을 민다. 방아쇠(앱 복귀 · 로그인 · 화면 열기 · 판 시작 · 판 끝)와 백오프 타이머가 전부 여기로 온다. 인편이 없으면 비용이 없다.
    ///
    /// 게임마다: 토큰을 실은 인편이 있으면 그것을 **같은 토큰으로** 보낸다(서버가 `token_used` 로 돌려주므로 두 번 올라가지 않는다).
    /// 전부 토큰을 기다리는 인편이면 맨 앞 것에 토큰을 받아 준다 — 왕복이 없을 때만 띄운다(있으면 그 응답이 온다).
    ///
    /// - Parameter fromTrigger: 바깥 방아쇠(기본)면 모르는 status 로 붙든 인편과 백오프를 푼다. 제출·토큰 응답의 **꼬리**와 타이머는
    ///   false — 그 꼬리가 방아쇠로 치면 거절 응답이 곧 다음 제출을 부르는 고리가 된다(두드리기).
    package func retryPendingSubmitIfAny(fromTrigger: Bool = true) {
        loadPendingIfNeeded()
        dropExpiredPendingSubmits()
        if fromTrigger {
            for index in pendingSubmits.indices {
                pendingSubmits[index].heldUntilTrigger = false
                pendingSubmits[index].nextRetryAt = nil
            }
        }
        guard isPublic, context.session.isSignedIn, !pendingSubmits.isEmpty else {
            schedulePendingRetry()
            return
        }
        guard !holdsPendingForPublicCheck() else { return }
        let now = context.clock.now()
        let generation = resetGeneration
        for kind in MiniGameKind.phoneCases {
            guard !submittingKinds.contains(kind) else { continue }
            let entries = pendingSubmits.filter { $0.kind == kind }
            guard !entries.isEmpty else { continue }
            // 보험: 들고 있던 토큰이 이 게임 것인데 인편이 토큰을 기다린다면 넘겨준다(정상 흐름에선 recordScore 가 이미 실었다).
            if !entries.contains(where: { $0.token != nil }), hasUsableRoundToken(for: kind), let held = roundToken {
                roundToken = nil
                roundTokenKind = nil
                roundTokenAt = nil
                _ = adoptTokenIntoWaitingPending(kind: kind, token: held)
            }
            switch pendingSubmits.nextStep(for: kind, at: now) {
            case .submit(let ready):
                Task { [weak self] in
                    guard let self, generation == self.resetGeneration else { return }
                    await self.performSubmit(entry: ready)
                }
            case .requestToken:
                guard roundTokenInFlightKind != kind else { continue }
                // 토큰 칸은 하나다 — 다른 게임 판이 도는 중에 받으면 **그 판의 토큰을 치운다.** 그 판이 끝나면(`recordScore`) 다시 민다.
                if let controller, controller.isPlaying, controller.kind != kind { continue }
                requestRoundToken(kind: kind)
            case .wait:
                continue
            }
        }
        schedulePendingRetry()
    }

    /// 디스크에서 되살린 인편이 있는데 이번 로그인의 공개 여부를 아직 못 들었으면 먼저 묻고 **이번 밀기를 멈춘다**. 못 들으면 다음 방아쇠가 다시 묻는다.
    private func holdsPendingForPublicCheck() -> Bool {
        guard pendingAwaitsPublicCheck else { return false }
        guard !publicIsKnown else {
            pendingAwaitsPublicCheck = false
            return false
        }
        guard !isCheckingPublicForPending else { return true }
        isCheckingPublicForPending = true
        let generation = resetGeneration
        Task { [weak self] in
            await self?.refreshPublic()
            guard let self, generation == self.resetGeneration else { return }
            self.isCheckingPublicForPending = false
            guard self.publicIsKnown else { return }
            self.retryPendingSubmitIfAny(fromTrigger: false)
        }
        return true
    }

    /// 제출 왕복 한 번. 인편은 **성공과 terminal 거절에서만** 지운다. 네트워크 실패·재시도 대상 거절·모르는 status 는 남긴다.
    /// 진단: 거절 status 이름까지만 남긴다(`need_seconds`·`elapsed_seconds` 는 화면에도 로그에도 쓰지 않는다).
    package func performSubmit(entry: MiniGamePendingSubmit) async {
        guard context.session.isSignedIn, let token = entry.token else { return }
        let kind = entry.kind
        guard !submittingKinds.contains(kind) else { return }
        submittingKinds.insert(kind)
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        let outcome: Result<MiniGameSubmitScoreResponse, Error>
        do {
            outcome = .success(try await context.withMobileSessionRetry { session in
                try await service.submitMiniGameScore(accessToken: session.accessToken, kind: kind, score: entry.score, token: token)
            })
        } catch {
            outcome = .failure(error)
        }
        // 비워진 허브(로그아웃)에는 한 글자도 쓰지 않는다. 인편은 디스크에 남아 같은 계정의 다음 로그인에서 살아난다.
        guard generation == resetGeneration else { return }
        // 꼬리에서 다음 인편을 밀어야 하므로 깃발은 **여기서** 내린다.
        submittingKinds.remove(kind)
        guard sessionGeneration == context.generation else {
            retryPendingSubmitIfAny(fromTrigger: false)
            return
        }
        switch outcome {
        case .failure(let error):
            if case .cancelled = AuthErrorRules.classify(error) { return }
            Self.logger.notice("submit failed (network) game=\(kind.rawValue, privacy: .public)")
            // 네트워크 실패는 인편을 **남긴다** — 백오프 뒤, 그리고 다음 방아쇠에 같은 토큰으로 한 번 더 보낸다.
            deferPendingRetry(id: entry.id)
            submitNotice = GamesMiniGameText.submitRetrying
            exitNoticeIsSticky = false
        case .success(let response):
            await handleSubmitResponse(response, entry: entry)
        }
    }

    private func handleSubmitResponse(_ response: MiniGameSubmitScoreResponse, entry: MiniGamePendingSubmit) async {
        let kind = entry.kind
        // ★ `token_used` 는 **성공이다.** 서버는 제출이 성공한 순간 그 토큰에 used_at 을 찍고, 이미 쓴 토큰에는
        //   `token_used` 를 돌려준다. 즉 이 응답을 받는 경우는 **응답만 유실된 첫 제출의 재시도**뿐이고,
        //   그때 점수는 이미 올라가 있다. 이걸 거절로 그리면 올라간 점수를 "못 올렸어요"라고 말하는 거짓말이 된다.
        if response.status == "ok" || response.status == "token_used" {
            if let best = response.bestScore { raiseLocalBest(kind, to: best) }
            removePendingSubmit(id: entry.id)
            // 이 게임의 역대 표는 이제 낡았다(새 개인 최고가 들어갔을 수 있다) — 아래에서 바로 다시 받거나,
            // [오늘] 을 보는 중이면 다음에 [역대] 로 넘어갈 때 받는다(보지도 않는 표를 판마다 받지 않는다).
            noteAllTimeStale(kind)
            // 상한에서 세운 안내("5분 넘게 멈춰서 …")는 제출과 무관한 사실이라 지우지 않는다.
            if !exitNoticeIsSticky, !hasPendingSubmit(for: kind) { submitNotice = nil }
            pushPendingAndPrefetch(after: kind)
            // 일일 미션(v0.3.64) — 판이 서버에 남은 직후 **한 번** 묻는다(새 타이머 없이 이벤트로).
            // 오늘 이 게임 줄을 이미 채웠으면 요청 0건이고, 미션 조회가 떠 있으면 그 옛 답에 합류하지 않고 끝난 뒤 한 번 더다
            // (`MeStore.refreshAchievementsAfterGameResult` 주석). 순위 재조회보다 **앞**에 둔다 — 순위 왕복을 기다리는
            // 동안 사용자는 이미 미션 화면으로 갈 수 있다.
            context.links.me?.refreshAchievementsAfterGameResult(game: kind.rawValue)
            // 순위 재조회는 **화면을 떠난 뒤에도** 한다(activeKind 로 막으면 뒤로가기로 끝낸 판이 반영되지 않는다).
            await loadBoard(kind, withWinner: false)
            // 역대는 **[역대] 를 보는 중일 때만**, 오늘 순위 뒤에 받는다(맥 `reloadsBoard, miniGameBoardScope == .allTime` 와 같은 자리).
            if boardScope == .allTime { await performLoadAllTimeBoard(kind) }
            return
        }
        exitNoticeIsSticky = false
        if Self.terminalSubmitStatuses.contains(response.status) {
            Self.logger.notice("submit refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
            // ★ `no_token` 은 **한 번은 되살린다.** 그 판은 진짜로 있었고 점수도 진짜다 — 죽은 것은 토큰뿐이다(다른 기기가 같은
            //   계정으로 토큰을 청하면 이쪽 토큰이 죽는다). 새 토큰 기준으로 하한만큼 기다려야 통과하므로 서버 방어는 그대로다.
            if response.status == "no_token", !entry.recoveredFromDeadTokenOnce,
               let index = pendingSubmits.firstIndex(where: { $0.id == entry.id }) {
                pendingSubmits[index].demoteToTokenWait()
                persistPendingSubmits()
                Self.logger.notice("pending submit recovered from dead token game=\(kind.rawValue, privacy: .public)")
                submitNotice = GamesMiniGameText.submitRetrying
                retryPendingSubmitIfAny(fromTrigger: false)
                return
            }
            removePendingSubmit(id: entry.id)
            // 토큰이 죽은 거절은 **그 판이 영영 못 올라간다** — "다시 해 주세요"(복구된다는 뜻)와 문장을 가른다.
            submitNotice = Self.deadTokenStatuses.contains(response.status)
                ? GamesMiniGameText.submitTokenDead
                : GamesMiniGameText.submitRefused
        } else if Self.retryableSubmitStatuses.contains(response.status) {
            // 아직 하한을 못 넘겼다 — 토큰이 살아 있으니 **인편을 남기고** 눈먼 지연 뒤 같은 토큰으로 다시 보낸다.
            // 기다리는 동안 "못 올렸어요"를 띄우면 곧 올라갈 점수를 못 올렸다고 말하는 거짓말이 된다.
            Self.logger.notice("submit too early — will retry status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
            deferPendingRetry(id: entry.id)
            submitNotice = GamesMiniGameText.submitRetrying
        } else {
            // 모르는 status(신버전 서버). 이해 못 한 거절을 두드리지는 않되 점수를 버리지도 않는다 — 타이머 없이 남기고,
            // 방아쇠에서만 다시 보낸다. TTL 이 끝을 낸다.
            Self.logger.notice("submit refused (unknown status) status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
            if let index = pendingSubmits.firstIndex(where: { $0.id == entry.id }) {
                pendingSubmits[index].heldUntilTrigger = true
            }
            submitNotice = GamesMiniGameText.submitRetrying
        }
        pushPendingAndPrefetch(after: kind)
    }

    /// 제출 꼬리: 다음 인편을 밀고, 그 게임의 인편이 다 비었으면 **다음 판의 토큰**을 미리 받는다(방금 쓴 토큰은 죽었다).
    /// 인편이 남아 있으면 선발급하지 않는다 — 그게 불변식이다.
    private func pushPendingAndPrefetch(after kind: MiniGameKind) {
        retryPendingSubmitIfAny(fromTrigger: false)
        // 다른 게임 인편의 토큰이 왕복 중이면 비킨다 — 새 요청은 그 응답을 세대 가드로 버린다. 그 인편의 꼬리가 여기로 다시 온다.
        guard roundTokenInFlightKind == nil else { return }
        // 받는 토큰은 **지금 화면의 게임** 것이다(다른 게임의 토큰을 받으면 토큰 칸 하나를 그 게임이 차지한다).
        let next = activeKind ?? kind
        if !hasPendingSubmit(for: next) { prefetchRoundToken(kind: next) }
    }

    /// 화면을 닫아 둔 사이에 인편이 TTL 로 죽었다면 한 줄로 말하고 표식을 지운다(한 번만 말한다).
    private func showLostNoticeIfAny() {
        loadPendingIfNeeded()
        dropExpiredPendingSubmits()
        guard let owner = pendingOwner, context.storage.defaults.bool(forKey: Self.lostNoticeKey(userID: owner)) else { return }
        context.storage.defaults.removeObject(forKey: Self.lostNoticeKey(userID: owner))
        submitNotice = GamesMiniGameText.submitFailedConnection
    }

    /// 토큰을 기다리는 이 게임의 맨 앞 인편에 토큰을 넘긴다. 넘겼으면 true(호출자가 인편을 민다).
    private func adoptTokenIntoWaitingPending(kind: MiniGameKind, token: String) -> Bool {
        guard let index = pendingSubmits.firstIndex(where: { $0.kind == kind && $0.token == nil }) else { return false }
        pendingSubmits[index].adopt(token: token, at: context.clock.now())
        persistPendingSubmits()
        return true
    }

    /// 실패한 인편의 백오프를 한 단계 올리고 타이머를 다시 잡는다.
    private func deferPendingRetry(id: UUID) {
        guard let index = pendingSubmits.firstIndex(where: { $0.id == id }) else { return }
        pendingSubmits[index].noteFailure(delays: MiniGameSubmitRules.retryDelays, at: context.clock.now())
        persistPendingSubmits()
        schedulePendingRetry()
    }

    /// 토큰 요청이 실패했는데 그 게임에 토큰을 기다리는 인편이 있으면 그 인편의 백오프를 올린다(다음 요청은 타이머가 띄운다).
    private func deferPendingTokenWait(kind: MiniGameKind) {
        guard let head = pendingSubmits.first(where: { $0.kind == kind && $0.token == nil }) else { return }
        deferPendingRetry(id: head.id)
    }

    /// 백오프 타이머 한 개 — 가장 먼저 돌아오는 인편의 시각에 맞춘다. 기다릴 것이 없으면 거둔다.
    private func schedulePendingRetry() {
        let now = context.clock.now()
        let next = pendingSubmits.nextRetryDate(after: now, ttl: MiniGameSubmitRules.pendingTTL)
        // 같은 시각을 이미 기다리고 있으면 그대로 둔다(꼬리마다 다시 잡지 않는다).
        if next == pendingRetryTarget, pendingRetryTask != nil { return }
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        pendingRetryTarget = next
        guard let next else { return }
        let delay = next.timeIntervalSince(now)
        let generation = resetGeneration
        let wait = sleep
        pendingRetryTask = Task { [weak self] in
            await wait(delay)
            guard !Task.isCancelled, let self, generation == self.resetGeneration else { return }
            self.pendingRetryTask = nil
            self.pendingRetryTarget = nil
            // 이 타이머가 돌아온 것이 곧 '그 시각이 됐다'다 — 시계를 주입한 빌드(데모·테스트)는 시계가 안 흘러서 시각을 다시 재면 영영 못 나간다.
            for index in self.pendingSubmits.indices {
                if let at = self.pendingSubmits[index].nextRetryAt, at <= next { self.pendingSubmits[index].nextRetryAt = nil }
            }
            self.retryPendingSubmitIfAny(fromTrigger: false)
        }
    }

    private func removePendingSubmit(id: UUID) {
        guard pendingSubmits.contains(where: { $0.id == id }) else { return }
        pendingSubmits.removeAll { $0.id == id }
        persistPendingSubmits()
    }

    /// TTL 을 넘긴 인편을 버린다(토큰이 죽었다). 화면이 열려 있으면 그 사실을 말하고, 닫혀 있으면 표식을 남겨 다음에 화면을 열 때 말한다 —
    /// 안 그러면 로그에만 남아 사용자는 그 판이 사라진 것을 영영 모른다.
    private func dropExpiredPendingSubmits() {
        let now = context.clock.now()
        let expired = pendingSubmits.filter { $0.isExpired(at: now, ttl: MiniGameSubmitRules.pendingTTL) }
        guard !expired.isEmpty else { return }
        for entry in expired {
            Self.logger.notice("pending submit expired game=\(entry.kind.rawValue, privacy: .public)")
        }
        let gone = Set(expired.map(\.id))
        pendingSubmits.removeAll { gone.contains($0.id) }
        persistPendingSubmits()
        if activeKind != nil {
            submitNotice = GamesMiniGameText.submitFailedConnection
            exitNoticeIsSticky = false
        } else if let owner = pendingOwner {
            context.storage.defaults.set(true, forKey: Self.lostNoticeKey(userID: owner))
        }
    }

    /// 메모리의 인편이 지금 계정 것이 아니면(처음 · 계정 전환 · 재로그인) 그 계정의 키에서 읽는다. TTL 을 넘긴 것은 여기서 버린다.
    private func loadPendingIfNeeded() {
        let owner = context.session.isSignedIn ? myUserID : nil
        guard pendingOwner != owner else { return }
        pendingOwner = owner
        guard let owner else {
            pendingSubmits = []
            return
        }
        var restored: [MiniGamePendingSubmit] = []
        if let data = context.storage.defaults.data(forKey: Self.pendingKey(userID: owner)),
           let decoded = try? JSONDecoder().decode([MiniGamePendingSubmit].self, from: data) {
            restored = decoded
        }
        pendingSubmits = restored
        adoptOrphanedPauseDraft(owner: owner)
        dropExpiredPendingSubmits()
        if !pendingSubmits.isEmpty {
            pendingAwaitsPublicCheck = true
            Self.logger.notice("pending submits restored count=\(self.pendingSubmits.count, privacy: .public)")
        }
    }

    /// 영속본을 메모리와 맞춘다. 비었으면 키를 지운다. 주인이 없으면(로그아웃 상태) 쓰지 않는다.
    private func persistPendingSubmits() {
        guard let owner = pendingOwner else { return }
        let key = Self.pendingKey(userID: owner)
        if pendingSubmits.isEmpty {
            context.storage.defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(pendingSubmits) {
            context.storage.defaults.set(data, forKey: key)
        }
    }

    // MARK: 일시정지

    /// 이 판에서 지금까지 얼어 있던 초(판 단위 누적 · 3-2-1 포함).
    ///
    /// **벽시계로 잰다**: 맥의 1초 Task 는 폰 background 에서 멈춘다. 시작 시각을 들고 빼면 돌아온 그 순간 바로 판정할 수 있다.
    /// 3-2-1 도 넣는다(맥은 안 넣는다) — 안 넣으면 카드 → 3-2-1 → 카드 왕복으로 영영 안 차서 토큰이 그대로 늙는다.
    package var pausedSecondsUsed: TimeInterval {
        let open = frozenSince.map { max(0, context.clock.now().timeIntervalSince($0)) } ?? 0
        return frozenSecondsBanked + open
    }

    /// [일시정지] 버튼 · 카드의 [이어하기]. 도는 판 → 정지, 정지 → 3-2-1, 3-2-1 → 다시 정지(취소). 규칙은 코어 `toggled` 한 벌이다.
    package func togglePause() {
        guard let controller else { return }
        let next = controller.pauseState.toggled(isPlaying: controller.isPlaying)
        guard next != controller.pauseState else { return }
        applyPause(next, to: controller)
    }

    /// 카드의 [그만두기]. 결과는 게임마다 다르다(`endRound()` — 테트리스·길건너는 확정, 플래피·타이밍 바는 버림).
    package func quitPausedRound() {
        guard let controller, controller.isFrozen else { return }
        endFrozenRound(controller, notice: nil)
    }

    /// 3-2-1 한 걸음. 돌 일이 남았으면 true(바깥 고리가 다음 1초를 잔다). 다 내려가면 판이 풀린다.
    @discardableResult
    package func advanceResumeCountdown() -> Bool {
        guard let controller, case .resuming = controller.pauseState else { return false }
        let next = controller.pauseState.steppedDown()
        guard next == .none else {
            controller.setPauseState(next)
            return true
        }
        closeFrozenSpan()
        stopPauseTasks()
        controller.setPauseState(.none)
        return false
    }

    /// 상한을 넘었으면 그 판을 끝낸다. 끝냈으면 true.
    ///
    /// 거는 범위는 `GamesMiniGamePausePolicy.capApplies` 뿐이다 — 플래피·타이밍 바는 접으면 버리는 게임이라 여기 걸면 판을 없앤다.
    @discardableResult
    package func enforcePauseCap() -> Bool {
        guard let controller, controller.isFrozen,
              GamesMiniGamePausePolicy.capApplies(controller.kind),
              pausedSecondsUsed >= TimeInterval(MiniGamePauseState.pauseLimitSeconds) else { return false }
        Self.logger.notice("pause limit reached game=\(controller.kind.rawValue, privacy: .public)")
        endFrozenRound(controller, notice: GamesMiniGameText.pauseCapEnded)
        return true
    }

    /// 감시 한 걸음. 카드가 떠 있는 동안 1초마다: 상한을 재고, 정지 중에도 토큰을 챙긴다(맥과 같다 — 멈춰 둔 동안에도 TTL 은 흐른다).
    /// 3-2-1 동안은 상한으로 끊지 않는다 — 넘기 전에 [이어하기] 를 누른 사람의 판이다(그 3초는 다음 정지에 세어 넣는다).
    /// background 면 아무것도 안 한다: 복귀(`sceneDidComeForward`)가 판정하고 토큰을 챙긴다.
    package func pauseWatchTick() {
        guard let controller, controller.isFrozen, !isInBackground else { return }
        if case .paused = controller.pauseState, enforcePauseCap() { return }
        if let last = lastFrozenKeepAliveAt,
           context.clock.now().timeIntervalSince(last) < GamesPlayController.keepAliveInterval { return }
        keepFrozenRoundTokenFresh(controller)
    }

    private func freezeForSceneChange() {
        guard let controller else { return }
        if let next = controller.pauseState.resigningKey(isPlaying: controller.isPlaying) {
            applyPause(next, to: controller)
        }
        writePauseDraft(controller)
    }

    /// 정해진 다음 상태를 판과 시계에 **옮긴다** — 버튼과 자동 정지가 같은 순서를 밟는 한 자리다(맥 `applyPause`).
    private func applyPause(_ next: MiniGamePauseState, to controller: GamesPlayController) {
        resumeTask?.cancel()
        resumeTask = nil
        if next.isFrozen, frozenSince == nil { frozenSince = context.clock.now() }
        controller.setPauseState(next)
        // [이어하기] 를 눌렀어도 이미 넘었으면 풀어 주지 않는다. 재정지로 시계를 되돌릴 길이 없는 까닭이다.
        if enforcePauseCap() { return }
        if case .resuming = next {
            // 사람이 돌아와 이어 한다 — 임시 항목은 지운다. 다시 내려가면 그때의 점수·토큰으로 다시 적는다.
            clearPauseDraft()
            startResumeCountdown()
        }
        armPauseWatch(controller)
    }

    private func startResumeCountdown() {
        let wait = pauseSleep
        resumeTask = Task { [weak self] in
            while !Task.isCancelled {
                await wait(1)
                guard !Task.isCancelled, let self else { return }
                guard self.advanceResumeCountdown() else { return }
            }
        }
    }

    /// 정지 감시를 건다. 할 일이 없는 게임(플래피·타이밍 바 — 상한도 토큰 갈아 끼우기도 없다)에는 안 건다.
    private func armPauseWatch(_ controller: GamesPlayController) {
        guard pauseWatchTask == nil,
              GamesMiniGamePausePolicy.capApplies(controller.kind) || controller.kind.roundTokenMidRunRefreshSeconds != nil else { return }
        let wait = pauseSleep
        pauseWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                await wait(Self.pauseWatchInterval)
                guard !Task.isCancelled, let self else { return }
                self.pauseWatchTick()
            }
        }
    }

    /// 정지 중 토큰 갈아 끼우기. 규칙은 판 도중과 같은 `keepRoundTokenFresh` 한 벌이다(인편이 살아 있으면 인편부터 민다 — 불변식).
    private func keepFrozenRoundTokenFresh(_ controller: GamesPlayController) {
        lastFrozenKeepAliveAt = context.clock.now()
        keepRoundTokenFresh(kind: controller.kind)
    }

    /// 얼려 둔(또는 떠나는 화면의) 판을 끝낸다. [그만두기] · 뒤로 · 판 전환 · 상한이 전부 여기로 온다.
    ///
    /// 안내는 **그 판이 토큰을 들고 인편에 올랐을 때만** 세운다. 토큰을 기다리면 `recordScore` 가 "올리는 중"을 말했고,
    /// 토큰이 죽었으면 "못 올렸어요"를 말했다 — 그 말을 "기록했어요"로 덮는 것이 이 화면에서 제일 나쁜 거짓말이다.
    private func endFrozenRound(_ controller: GamesPlayController, notice: String?) {
        stopPauseTasks()
        resetPauseClock()
        let known = Set(pendingSubmits.map(\.id))
        let outcome = controller.endRound()
        clearPauseDraft()
        guard let notice, case .confirmed = outcome else { return }
        let carriesToken = pendingSubmits.last { !known.contains($0.id) }?.token != nil
        guard carriesToken || !isPublic || !context.session.isSignedIn else { return }
        submitNotice = notice
        // 비동기 제출 성공이 이 문장을 지우면 판이 조용히 사라진 것처럼 보인다.
        exitNoticeIsSticky = carriesToken
    }

    private func closeFrozenSpan() {
        frozenSecondsBanked = pausedSecondsUsed
        frozenSince = nil
    }

    private func resetPauseClock() {
        frozenSecondsBanked = 0
        frozenSince = nil
        lastFrozenKeepAliveAt = nil
    }

    private func stopPauseTasks() {
        resumeTask?.cancel()
        resumeTask = nil
        pauseWatchTask?.cancel()
        pauseWatchTask = nil
    }

    // MARK: 임시 항목(iOS 가 앱을 죽여도 점수를 건진다)
    //
    // 지금까지 테트리스·길건너는 앱을 내리는 순간 점수를 확정해서 iOS 가 앱을 죽여도 남았다. 얼리는 것으로 바꾸면 그 판은 메모리에만 있다.
    // 그래서 내려갈 때 지금 점수·토큰을 **인편과 다른 키**에 적는다. 인편에 넣으면 밀기가 도는 판의 토큰을 그 자리에서 보내 버린다.
    //
    //  · 사람이 돌아와 [이어하기] → 지운다(다시 내려가면 다시 적는다).
    //  · 판이 끝났다([그만두기]·상한·뒤로) → `recordScore` 가 지운다(진짜 인편이 대신한다 — 이중 제출 없음).
    //  · 로그아웃 → 지운다(`reset`) · 계정 삭제 → 지운다(`forgetPendingSubmits`).
    //  · 프로세스가 죽었다 → 다음 실행의 `loadPendingIfNeeded` 가 그 계정의 인편으로 올린다. 토큰이 죽었으면 인편 규칙대로 끝난다.
    //
    // 플래피·타이밍 바는 적지 않는다 — 접으면 버리는 게임이다(`GamesMiniGamePausePolicy`).

    private func writePauseDraft(_ controller: GamesPlayController) {
        let kind = controller.kind
        guard controller.isPlaying, controller.isFrozen, GamesMiniGamePausePolicy.quittingKeepsTheScore(kind) else { return }
        let score = controller.score
        guard score >= 0, score <= kind.maxScore, context.session.isSignedIn else { return }
        // 공개를 끈 사람은 제출이 없다 — 죽어도 남아야 하는 것은 로컬 최고뿐이다.
        guard isPublic else {
            raiseLocalBest(kind, to: score)
            return
        }
        loadPendingIfNeeded()
        guard let owner = pendingOwner else { return }
        let carries = roundTokenKind == kind
        let draft = MiniGamePendingSubmit(
            id: UUID(), kind: kind, score: score,
            token: carries ? roundToken : nil, tokenIssuedAt: carries ? roundTokenAt : nil,
            recordedAt: context.clock.now(), attempts: 0)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        context.storage.defaults.set(data, forKey: Self.pauseDraftKey(userID: owner))
        liveDraftOwner = owner
    }

    private func clearPauseDraft() {
        guard let owner = liveDraftOwner else { return }
        context.storage.defaults.removeObject(forKey: Self.pauseDraftKey(userID: owner))
        liveDraftOwner = nil
    }

    /// 앞 실행이 남긴 임시 항목을 그 계정의 인편으로 올린다. 이 실행에서 적은 것은 살아 있는 판의 것이라 건드리지 않는다.
    private func adoptOrphanedPauseDraft(owner: String) {
        guard liveDraftOwner != owner else { return }
        let key = Self.pauseDraftKey(userID: owner)
        guard let data = context.storage.defaults.data(forKey: key) else { return }
        if let draft = try? JSONDecoder().decode(MiniGamePendingSubmit.self, from: data),
           !pendingSubmits.contains(where: { $0.id == draft.id }) {
            raiseLocalBest(draft.kind, to: draft.score)
            pendingSubmits.append(draft)
            persistPendingSubmits()
        }
        context.storage.defaults.removeObject(forKey: key)
    }

    #if DEBUG
    /// 데모 스크린샷 전용: 정지 카드 · 3-2-1 장면을 그 상태에서 시작한다(시계도 Task 도 없다 — 합성 탭을 넣지 않는다).
    func demoFreeze(_ state: MiniGamePauseState) {
        controller?.setPauseState(state)
    }
    #endif

    // MARK: 조회

    /// 공개 여부를 읽는다(설정은 나 탭이 바꾼다 — 화면을 열 때마다 다시 읽는다).
    ///
    /// - 서버가 답했다: 그 값. 행·컬럼이 없어 값이 없으면(nil) 공개(맥과 같다 — 컬럼 없는 서버).
    /// - 표·함수가 아직 없는 서버(`databaseSchemaMissing`): 공개.
    /// - **그 밖의 실패(오프라인·5xx·만료)는 아는 값을 그대로 둔다** — 예전에는 `try?` 가 실패를 nil 로 바꿔 "모름 = 공개"로
    ///   덮었고, 순위 공개를 끈 사람의 점수가 조회 한 번 실패 뒤 서버로 나갔다(games-verify PROBE-1). 맥
    ///   `miniGamePublicLoaded` 도 실패는 값을 바꾸지 않는다.
    package func refreshPublic() async {
        guard context.session.isSignedIn, let userID = context.session.session?.userID else { return }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        let resolved: Bool
        do {
            let value = try await context.withMobileSessionRetry { session in
                try await service.fetchMiniGamePublic(accessToken: session.accessToken, userID: userID)
            }
            resolved = value ?? true
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            resolved = true
        } catch {
            if case .cancelled = AuthErrorRules.classify(error) { return }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            let kept = isPublic
            Self.logger.notice("minigame public lookup failed — keeping isPublic=\(kept, privacy: .public)")
            return
        }
        guard sessionGeneration == context.generation, generation == resetGeneration else { return }
        publicIsKnown = true
        if isPublic != resolved { isPublic = resolved }
        if !resolved {
            // 꺼져 있으면 들고 있는 토큰은 쓸 일이 없다.
            roundToken = nil
            roundTokenKind = nil
            roundTokenAt = nil
        }
    }

    // MARK: 역대 순위 (맥 0.3.67 → 폰 1.0.15)
    //
    // 받는 때는 **넷뿐**이다 — ① [역대] 로 넘어갈 때(그 게임 표가 최신이 아닐 때만) ② [역대] 를 보는 중에 화면을 열 때
    // (게임을 바꿨거나 다시 들어왔다) ③ [역대] 를 보는 중에 판이 서버에 남았을 때 ④ [다시 시도].
    // 60초 요약 루프(`refreshSummariesIfStale`)에는 **얹지 않는다** — 안 보는 사람에게 호출이 가면 안 된다(설계서 ②).

    /// 순위 머리의 [오늘 | 역대] 전환. 같은 쪽을 다시 누르면 아무 일도 없다.
    ///
    /// [역대] 로 넘어갈 때 그 게임의 **최신 표를 들고 있으면 다시 받지 않는다**(오가며 누를 때마다 요청이 나가지 않게).
    /// 실패한 채였으면 한 번 더 받는다 — 사용자가 다시 보러 온 것이 곧 재시도 의사다(맥 `selectMiniGameBoardScope` 그대로).
    /// 화면이 열려 있지 않으면 받지 않는다(`activeKind` 가 nil) — 이 전환은 그 화면 머리에만 있다.
    package func selectBoardScope(_ scope: MiniGameBoardScope) {
        guard scope != boardScope else { return }
        boardScope = scope
        guard scope == .allTime, let kind = activeKind else { return }
        guard allTimeFreshKind != kind || boards[kind]?.allTimeFailed == true else { return }
        loadAllTimeBoard(kind)
    }

    /// 역대 순위를 받는다(Task 발사). 위 네 방아쇠가 부른다.
    package func loadAllTimeBoard(_ kind: MiniGameKind) {
        Task { [weak self] in await self?.performLoadAllTimeBoard(kind) }
    }

    /// 그 게임의 역대 표가 **낡았다**고 표시한다(판이 서버에 남은 직후). 부르는 자리는 하나 — 제출 성공.
    private func noteAllTimeStale(_ kind: MiniGameKind) {
        if allTimeFreshKind == kind { allTimeFreshKind = nil }
        // 떠 있는 받기가 이 제출 **전**에 떠났을 수 있다 — 그 응답이 늦게 닿아 '최신'을 다시 세우지 못하게 한다.
        allTimeInvalidation &+= 1
    }

    /// `minigame_alltime_board` 를 받아 그 게임 칸에 반영한다.
    ///
    /// **버리는 자리가 넷**이다 — 하나라도 빠지면 옛 표가 새 표를 덮거나 낡은 표가 '최신'으로 굳는다.
    ///  ① 계정이 바뀌었다(`context.generation`) ② 로그아웃·치명 만료로 허브가 비워졌다(`resetGeneration`)
    ///  ③ 내 뒤에 떠난 받기가 **이미 반영됐다**(`allTimeAppliedSerial`) — 사람이 전환을 누른 받기와 판이 끝나 다시 받는
    ///     받기가 겹칠 때 늦게 온 쪽이 이기던 결함(맥 검토 2026-10-27 · `bc9a64c` 6번).
    ///  ④ 떠난 뒤 표가 낡았다고 표시됐다(`allTimeInvalidation`) — 그 응답은 **반영하되 '최신'으로는 표시하지 않는다.**
    ///
    /// 맥의 `kind == miniGameKind` 가드가 여기 없는 이유: 폰은 표를 **게임마다** 들고 있어 이 함수가 `boards[kind]` 한 칸에만
    /// 쓴다 — 맥에서 그 가드가 막던 "남의 게임 순위가 뜬다"는 여기서 구조적으로 못 일어난다(③ 이 그 몫을 받는다).
    ///
    /// 실패는 셋으로 가른다(맥과 같다).
    ///  · 함수가 아직 없는 서버(PGRST202 · 본문 없는 404) → **준비 중**(빈 표 + `allTimeUnavailable` · [다시 시도] 없음).
    ///  · 그 밖(네트워크 · 5xx · 배열이 아닌 본문) → 실패. 이미 그린 줄이 있으면 그대로 두고, 없을 때만 실패 행이 선다.
    ///  · 취소 → 아무것도 안 바꾼다.
    package func performLoadAllTimeBoard(_ kind: MiniGameKind) async {
        guard context.session.isSignedIn else { return }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        // 떠날 때의 낡음 표시 횟수와 일련번호(위 ③ ④).
        let invalidation = allTimeInvalidation
        allTimeFetchSerial &+= 1
        let serial = allTimeFetchSerial
        var state = boards[kind] ?? GamesMiniGameBoard()
        if !state.allTimeLoading {
            state.allTimeLoading = true
            state.allTimeFailed = false
            boards[kind] = state
        }
        defer {
            // 내 뒤에 떠난 받기가 있으면 '불러오는 중'의 주인은 그쪽이다 — 그 깃발을 내려 주지 않는다.
            // 비워진 허브(로그아웃)에는 한 글자도 쓰지 않는다 — 여기서 쓰면 비운 `boards` 에 칸이 되살아난다.
            if generation == resetGeneration, serial == allTimeFetchSerial, boards[kind]?.allTimeLoading == true {
                boards[kind]?.allTimeLoading = false
            }
        }
        do {
            let entries = try await context.withMobileSessionRetry { session in
                try await service.fetchMiniGameAllTimeBoard(accessToken: session.accessToken, kind: kind)
            }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            guard serial > allTimeAppliedSerial else { return }
            allTimeAppliedSerial = serial
            // 서버 정렬을 믿지 않고 다시 세운다(점수 ↓ → 먼저 닿은 사람 → user_id — 코어 한 벌).
            let sorted = entries.sortedForMiniGameAllTimeBoard()
            var next = boards[kind] ?? GamesMiniGameBoard()
            next.allTime = sorted
            next.allTimeLoaded = true
            next.allTimeLoading = false
            next.allTimeFailed = false
            next.allTimeUnavailable = false
            if boards[kind] != next { boards[kind] = next }
            if invalidation == allTimeInvalidation { allTimeFreshKind = kind }
            // 내 역대 행은 이 계정의 **진짜** 전체 기간 최고다 — 로컬 캐시가 그보다 작으면(다른 기기 · 재설치) 올린다.
            if let me = myUserID, let mine = sorted.first(where: { $0.userID == me }) {
                raiseLocalBest(kind, to: mine.bestScore)
            }
        } catch {
            if case .cancelled = AuthErrorRules.classify(error) { return }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            var next = boards[kind] ?? GamesMiniGameBoard()
            next.allTimeLoading = false
            if let serviceError = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(serviceError) {
                // 앱이 db push 보다 먼저 나간 창: 실패가 아니라 '아직 표가 없다'. 빈 표 + "준비 중" 한 줄.
                next.allTime = []
                next.allTimeUnavailable = true
                next.allTimeLoaded = true
                boards[kind] = next
                // 같은 게임으로 오가며 누를 때마다 404 를 다시 두드리지 않는다(판 기록 · 화면 열기가 다시 묻는다).
                allTimeFreshKind = kind
            } else {
                Self.logger.notice("alltime board fetch failed game=\(kind.rawValue, privacy: .public)")
                next.allTimeFailed = true
                boards[kind] = next
            }
        }
    }

    /// 오늘 순위(+어제 1등). 두 조회는 독립 실패다(맥과 같다).
    package func loadBoard(_ kind: MiniGameKind, withWinner: Bool) async {
        guard context.session.isSignedIn else { return }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        var state = boards[kind] ?? GamesMiniGameBoard()
        if !state.loading {
            state.loading = true
            state.failed = false
            boards[kind] = state
        }
        do {
            let entries = try await context.withMobileSessionRetry { session in
                try await service.fetchMiniGameBoard(accessToken: session.accessToken, kind: kind, day: nil)
            }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            var next = boards[kind] ?? GamesMiniGameBoard()
            next.entries = entries.sortedForMiniGameBoard()
            next.loaded = true
            next.loading = false
            next.failed = false
            if boards[kind] != next { boards[kind] = next }
            if let me = myUserID, let mine = next.entries.first(where: { $0.userID == me }) {
                raiseLocalBest(kind, to: mine.bestScore)
            }
        } catch {
            if case .cancelled = AuthErrorRules.classify(error) { return }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            var next = boards[kind] ?? GamesMiniGameBoard()
            next.loading = false
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 표·함수가 아직 없는 서버: 실패가 아니라 "아직 기록이 없다"로 조용히 접는다(맥과 같다).
                next.loaded = true
            } else {
                next.failed = true
            }
            boards[kind] = next
            return
        }
        guard withWinner else { return }
        let winner = try? await context.withMobileSessionRetry { session in
            try await service.fetchMiniGameYesterdayWinner(accessToken: session.accessToken, kind: kind)
        }
        guard sessionGeneration == context.generation, generation == resetGeneration else { return }
        let resolved = winner
        if boards[kind]?.yesterdayWinner != resolved { boards[kind]?.yesterdayWinner = resolved }
    }

    // MARK: 로컬 최고

    /// 로컬 최고 키 — **계정별**(같은 폰을 다른 계정이 쓰면 남의 최고를 물려받지 않는다). 공용 suite 에 둔다.
    package nonisolated static func bestKey(userID: String?, kind: MiniGameKind) -> String {
        "aing.minigame.best.\(userID ?? "local").\(kind.rawValue)"
    }

    /// 제출 인편의 영속 키. **계정별**이다(남의 점수를 내 이름으로 올리지 않는다).
    package nonisolated static func pendingKey(userID: String) -> String {
        "aing.minigame.pending.\(userID)"
    }

    /// 얼려 둔 판의 임시 항목 영속 키(계정별 · 한 칸 — 한 번에 판은 하나다). 인편(`pendingKey`)과 일부러 나눴다(`writePauseDraft`).
    package nonisolated static func pauseDraftKey(userID: String) -> String {
        "aing.minigame.pausedraft.\(userID)"
    }

    /// 화면이 닫힌 채 인편이 TTL 로 버려졌다는 표식의 영속 키(계정별). 다음에 화면을 열 때 한 번 말하고 지운다.
    package nonisolated static func lostNoticeKey(userID: String) -> String {
        "aing.minigame.lostnotice.\(userID)"
    }

    /// 계정이 지워졌다 — 그 계정의 인편·표식을 기기에서 지운다. 로그아웃에는 남기는 값이지만(같은 계정이 돌아오면 올린다) 지운 계정은 돌아오지 않는다.
    package nonisolated static func forgetPendingSubmits(userID: String, in defaults: UserDefaults) {
        let owner = userID.lowercased()
        defaults.removeObject(forKey: pendingKey(userID: owner))
        defaults.removeObject(forKey: pauseDraftKey(userID: owner))
        defaults.removeObject(forKey: lostNoticeKey(userID: owner))
    }

    private var myUserID: String? { context.session.session?.userID.lowercased() }

    private func loadLocalBest(_ kind: MiniGameKind) {
        let stored = max(0, context.storage.defaults.integer(forKey: Self.bestKey(userID: myUserID, kind: kind)))
        if localBest[kind] != stored { localBest[kind] = stored }
    }

    private func raiseLocalBest(_ kind: MiniGameKind, to score: Int) {
        let key = Self.bestKey(userID: myUserID, kind: kind)
        let current = max(0, context.storage.defaults.integer(forKey: key))
        if score > current { context.storage.defaults.set(score, forKey: key) }
        let resolved = max(current, score)
        if localBest[kind] != resolved { localBest[kind] = resolved }
    }
}
