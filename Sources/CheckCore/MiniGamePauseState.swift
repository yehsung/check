import Foundation

// MARK: - 미니게임 일시정지 (맥 v0.2.48 → 폰 1.0.16 에 코어로 옮겼다)
//
// 여기 있는 것은 **두 플랫폼이 같아야 하는 규칙뿐**이다: 세 상태 · 3-2-1 · 5분 상한의 값 · 전이.
// 게임은 `isFrozen` 한 값만 읽는다. 상태를 들고 시계를 재는 일은 각자의 자리가 맡는다(맥 `CheckMiniGameWindowView` ·
// 폰 `GamesMiniGameHub`). **상한을 어느 게임에 거는가는 여기 없다** — 접었을 때 기록이 남는가가 플랫폼마다 달라서다
// (맥 `MiniGamePauseState.quittingKeepsTheScore` · 폰 `GamesMiniGamePausePolicy`).

package enum MiniGamePauseState: Equatable, Sendable {
    case none
    case paused
    /// 재개 카운트다운(3 → 2 → 1). 이 동안에도 판은 **얼어 있다** — 안 그러면 정지로 얻은 리듬 이점이 남는다.
    case resuming(Int)

    /// 카운트다운 시작값. 3-2-1 이 있어야 정지 직전 화면을 보고 손을 맞춰 두는 이득이 사라진다.
    package static let countdownStart = 3

    /// **정지 상한(초).** 넘으면 판을 그 점수로 확정하고 끝낸다(무효가 아니다).
    ///
    /// 왜 필요한가: 서버는 정지를 **모른다** — 라운드 토큰의 만료를 `clock_timestamp() - started_at` 실시간으로만
    /// 재고(20260914010000:296-297), 유효기간은 30분이다. 클라가 판 시작 때 토큰을 최대 12분 묵은 것까지
    /// 재사용하고(WorkTimerStoreMiniGame) 테트리스 한 판이 최장 9분쯤이므로, 남는 여유가 **9분 안팎**이다.
    /// 그 이상 멈춰 두면 돌아와 끝내도 제출이 `token_expired` 로 거절된다 — **멈춰 뒀다는 이유로 기록을 잃는다.**
    /// 5분에서 잘라 그 시점 점수를 확정하면, 잃는 것은 "이어서 더 할 기회"뿐이고 번 점수는 남는다.
    /// 이것은 설정 스위치가 아니라 게임 상수다(2026-09-15 '자동 종료는 사용자 스위치로 주지 않는다').
    /// 거는 범위는 **접었을 때 기록이 남는 게임**이다(v0.3.62 · `quittingKeepsTheScore`) — 0.3.61 까지는
    /// "두 기존 게임은 한 판이 짧아 이 여유를 쓸 일이 없다"로 테트리스에만 걸었는데, 자동 정지(키 상실)가
    /// 그 전제를 무너뜨려 플래피가 들어왔다. 타이밍 바는 접어도 남는 것이 없어 빠진다.
    ///
    /// **맥에서 이 상한은 앱이 켜져 있는 동안만 산다** — 집행하는 쪽이 1초씩 자는 Task 라 프로세스가 죽으면 같이
    /// 죽는다(`armPauseWatchdog`). 5분이 차기 전에 앱을 끄면 그 판 점수는 어디에도 안 남는다.
    /// 폰은 그 Task 가 background 에서 멈추므로 **벽시계**로 잰다(`GamesMiniGameHub.pausedSecondsUsed`).
    package static let pauseLimitSeconds = 5 * 60

    /// 판이 얼어 있는가(= `MiniGameHost.isPaused`). 카운트다운 중에도 참이다.
    package var isFrozen: Bool { self != .none }
    /// 정지 카드(이어하기·그만두기)가 떠 있는가. **화면이 실제로 이 프로퍼티로 분기한다** —
    /// 테스트만 부르고 화면은 `countdown == nil` 로 따로 판정하면, 상태가 하나 더 생기는 날
    /// 테스트는 초록인 채 화면만 갈린다.
    package var showsCard: Bool { self == .paused }
    /// 카운트다운 숫자(아니면 nil).
    package var countdown: Int? {
        if case let .resuming(remaining) = self { return remaining }
        return nil
    }

    /// [일시정지] 버튼과 ESC 가 공유하는 전이. **진행 중일 때만** 정지할 수 있다 —
    /// 시작 전·결과 화면에서 얼리면 클릭이 안 먹는 화면이 된다.
    package func toggled(isPlaying: Bool) -> MiniGamePauseState {
        switch self {
        case .none: return isPlaying ? .paused : .none
        case .paused: return .resuming(Self.countdownStart)
        case .resuming: return .paused          // 카운트다운 중 ESC 는 다시 정지(취소)
        }
    }

    /// **창이 키를 잃었을 때**의 전이(0.3.62 — 실사용 제보 "테트리스 일시정지하고 다른 창을 클릭하면
    /// 아예 끝나버려요"의 수리). `toggled(isPlaying:)` 를 재사용하지 않는 이유는 **방향이 하나**라는 것이다 —
    /// 키 상실은 언제나 '얼린다'이고 절대 풀지 않는다. `toggled` 를 그대로 쓰면 이미 정지해 둔 판이 키를
    /// 잃는 순간 `.resuming` 으로 **풀려** 안 보이는 창에서 3-2-1 이 흐른다(제보의 반대 방향 사고다).
    ///
    /// `nil` 은 "아무 일도 하지 않는다"다(지금 상태를 그대로 둔다). 두 자리에서 돌려준다:
    ///   · **판이 도는 중이 아니다** — 시작 전·결과 화면에서 얼리면 클릭이 안 먹는 창이 된다(위 `toggled` 와 같은 근거).
    ///   · **이미 `.paused` 다** — 여기서 또 얼리면 수신처가 정지 감시(`armPauseWatchdog`)를 새로 걸고,
    ///     그 시계는 1초 수면부터 다시 시작한다. 1초 안에 키를 잃었다 되찾기를 반복하면 누적(`pausedSecondsUsed`)이
    ///     영영 안 올라 5분 상한이 통째로 무력해진다 — 그 상한은 순위 공정성의 보루다.
    package func resigningKey(isPlaying: Bool) -> MiniGamePauseState? {
        guard isPlaying else { return nil }
        switch self {
        case .paused: return nil
        // 카운트다운 중이면 **취소하고 다시 언다.** 안 그러면 안 보이는 창에서 3-2-1 이 흘러 판이 저절로 풀린다.
        case .none, .resuming: return .paused
        }
    }

    /// 카운트다운 한 걸음(1초). 3 → 2 → 1 → none.
    package func steppedDown() -> MiniGamePauseState {
        guard case let .resuming(remaining) = self else { return self }
        return remaining <= 1 ? .none : .resuming(remaining - 1)
    }
}
