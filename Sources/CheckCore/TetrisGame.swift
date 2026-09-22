import Foundation

// v0.3.38 테트리스 — 순수 규칙 엔진. 화면(AppKit·뷰)은 한 줄도 없다(플래피·타이밍 바와 같은 자리).
//
// ── 이 파일이 지키는 단 하나의 축 ──────────────────────────────────────────────────
// 난이도 시계는 **advance = 고정한 조각 수 + 지운 줄 수** 다. 시간도 프레임도 아니다.
// 줄을 한 줄도 안 지우는 사람에게도 램프가 닿게 하는 유일한 장치이고(줄 축이면 레벨 1에 갇혀 40분짜리 판이 난다),
// 시계가 아니라 플레이 행위라서 사용자가 배제한 '시간 상한'이 아니다. 판은 여전히 **탑아웃으로만** 끝난다.
//
// ── 시간 상수는 전부 초 단위다 ─────────────────────────────────────────────────────
// 프레임 수로 두면 안 된다: 이 저장소의 프레임 루프는 화면 주사율을 따라 24~119fps 로 달라진다
// (MiniGameEngine.swift 의 `MiniGameFrameRate`). DAS·ARR·중력·소프트드롭·락딜레이가 전부 여기서 흐르고,
// **뷰는 dt 만 흘려 준다** — 허브·뷰에서 `Date()`·`Timer` 로 재면 소스 계약이 막는다.
//
// ── 입력 선행(스폰 전 키 버퍼링 · IRS/IHS)을 **넣지 않았다** ────────────────────────
// 2026-09-23 사용자 확정. 넣으면 ARE 0.100초 동안 DAS 를 미리 채워 스폰 직후 ARR 로 조각당 2~3칸이 공짜로 생기고,
// 그러면 아래 `lockResetLimit` 바닥 2 가 만드는 종료 보장(§접지 리셋)이 통째로 무너진다 — 바닥을 1 로 내려야 하는데
// 그건 "완벽해도 벽에 못 닿는다"가 아니라 "조작이 고장 났다"로 느껴진다. DAS 충전 자체는 표준대로 텀 동안에도 도는데
// (`advanceRepeatClock`), 그건 타이머만 도는 것이고 **조각이 없는 동안의 키 입력은 어디에도 쌓이지 않는다.**

/// 테트리스 규칙. 시드만 주면 결정론적으로 같은 판이 나온다(테스트가 시드를 고정한다).
package struct TetrisGame: Equatable, Sendable {

    // MARK: - 판 · 조각

    /// 표준 10×40. 아래 20행만 보이고 위 20행은 버퍼다(스폰이 보이는 판 위에서 일어난다).
    package static let columns = 10
    package static let totalRows = 40
    package static let visibleRows = 20
    /// 보이는 판이 시작하는 행(0 = 맨 위). `totalRows - visibleRows`.
    package static let firstVisibleRow = totalRows - visibleRows
    /// 스폰 바운딩 상자의 왼쪽 위 칸. 표준 "21·22행"(바닥에서 셈)을 위에서 세는 좌표로 옮긴 값이다 —
    /// 3×3 조각은 18·19행을 쓰고 I 는 19행을 쓴다. 둘 다 **보이는 판 바로 위 두 줄**이다.
    package static let spawnRow = 18
    /// 스폰 열. 3×3 은 4~6열(1-indexed) · I 는 4~7열 · O 는 5~6열을 점유한다 — 전부 표준 그대로다.
    /// 이 세 값이 아래 '접지 리셋 바닥 2' 종료 보장의 전제다(양 끝 열까지 3칸·4칸이 필요하다).
    package static let spawnColumn = 3
    /// 넥스트 표시 개수(사용자 확정. 표준은 "최대 6").
    package static let nextCount = 5

    /// 조각 7종. `allCases` 순서는 7-bag 섞기의 입력이라 **바꾸면 같은 시드가 다른 판을 낸다.**
    package enum Piece: Int, CaseIterable, Sendable, Hashable {
        case i, j, l, o, s, t, z
    }

    /// 회전 상태. 0 = 스폰 · R = 시계 · 2 = 180° · L = 반시계(SRS 표기 그대로).
    package enum Rotation: Int, Sendable, Hashable, CaseIterable {
        case spawn = 0, right = 1, flip = 2, left = 3

        /// 시계 방향 다음 상태.
        package var clockwise: Rotation {
            switch self {
            case .spawn: return .right
            case .right: return .flip
            case .flip: return .left
            case .left: return .spawn
            }
        }
        /// 반시계 방향 다음 상태.
        package var counterClockwise: Rotation {
            switch self {
            case .spawn: return .left
            case .right: return .spawn
            case .flip: return .right
            case .left: return .flip
            }
        }
    }

    /// 떨어지는 조각. 좌표는 **바운딩 상자의 왼쪽 위 칸**이다(행은 0 = 맨 위, 아래로 증가).
    /// 칸 하나하나가 아니라 상자를 들고 다니는 이유는 SRS 킥이 상자를 옮기는 규칙이기 때문이다 —
    /// 칸 목록을 직접 옮기면 회전마다 기준점이 달라져 킥표를 옮겨 적을 수 없다.
    package struct ActivePiece: Equatable, Sendable {
        package var piece: Piece
        package var rotation: Rotation
        package var column: Int
        package var row: Int

        package init(piece: Piece, rotation: Rotation = .spawn, column: Int, row: Int) {
            self.piece = piece
            self.rotation = rotation
            self.column = column
            self.row = row
        }

        /// 판 좌표로 푼 네 칸.
        package var cells: [(row: Int, column: Int)] {
            TetrisGame.shape(piece, rotation).map { (row: row + $0.dy, column: column + $0.dx) }
        }
    }

    /// T-스핀 판정. 점수표가 세 갈래(없음·미니·완전)로 갈린다.
    package enum Spin: Equatable, Sendable {
        case none, mini, full
    }

    /// 방금 끝난 배치의 결과. **그림 전용**이다 — 규칙은 이 값을 한 번도 읽지 않는다.
    package struct ClearEvent: Equatable, Sendable {
        package var lines: Int
        package var spin: Spin
        /// B2B 배수(×1.5)가 실제로 붙었는가.
        package var backToBack: Bool
        package var perfectClear: Bool
        /// 이 배치로 더해진 점수(행동 + 콤보 + 퍼펙트클리어. 드롭 점수는 뺀다 — 그건 떨어뜨리는 동안 이미 올랐다).
        package var points: Int
        /// 판 시각(초). 벽시계가 아니라 `step(dt:)` 이 흘린 시간이다.
        package var at: TimeInterval
    }

    package enum Phase: Equatable, Sendable {
        /// 시작 전(루프 정지). 액션 = 새 판.
        case ready
        case running
        /// 줄소거 정지. `remaining` 이 0 이 되면 ARE 로.
        case lineClear(remaining: TimeInterval)
        /// ARE(조각 사이 텀). `remaining` 이 0 이 되면 다음 조각이 나온다.
        case are(remaining: TimeInterval)
        /// 탑아웃 직후 유예. 다 지나면 `.result`(그 사이 클릭은 무시 — 죽자마자 새 판이 열리지 않게).
        case over(hold: TimeInterval)
        /// 결과 카드(루프 정지). 액션 = 새 판.
        case result
    }

    // MARK: - 확정 상수 (난이도)

    /// dt 상한. 앱 정지·창 재표시 뒤 첫 프레임이 몇 초를 한 번에 밀지 않게.
    ///
    /// **기존 두 게임(1/30)과 일부러 다르다 — 1/20 이다.** "통일"이 이유가 될 수 없는 자리다:
    /// 클램프는 **화면이 주는 프레임 간격보다 커야** 뜻이 있다. 24Hz 화면의 간격은 0.0417초라 1/30(0.0333)을
    /// 쓰면 **매 프레임 0.0083초를 버려 판이 실시간의 80% 로 돈다.** 중력·락딜레이·DAS 가 통째로 25% 느려지고,
    /// 이 게임에서 느린 시계는 곧 **이득**이다(순위표가 걸려 있으므로 하드웨어가 순위를 가르게 된다).
    /// 30Hz 도 간격 0.0333 이라 1/30 과 **정확히 같아** 지터 한 번이면 같은 일이 벌어진다.
    /// 1/20(0.05)은 24Hz·30Hz 를 여유 있게 덮으면서, 히칭 한 번이 미는 양은 0.033 → 0.05 로만 는다.
    ///
    /// (플래피·타이밍 바도 같은 구조적 문제를 갖지만 이번 범위가 아니다 — 거긴 1/30 그대로 둔다.)
    package static let maxStep: TimeInterval = 1.0 / 20.0

    /// DAS(Delayed Auto Shift) — 방향키를 누르고 자동 반복이 시작되기까지. 가이드라인 표기값.
    package static let dasSeconds: TimeInterval = 0.167
    /// ARR(Auto Repeat Rate) — 자동 반복 한 칸 사이.
    package static let arrSeconds: TimeInterval = 0.033
    /// 조각 사이 텀. **레벨과 무관하게 고정**이다.
    /// ⚠️ 이 값과 아래 `lineClearSeconds` 가 서버 시간 하한 `minigame_min_seconds('tetris', …)` 의 **유일한 뿌리다**
    ///    (하드드롭이 낙하 시간을 0 으로 만들어 남는 강제 정지가 이 둘뿐이다). 바꾸면 그 SQL 도 같이 바꿔라.
    package static let areSeconds: TimeInterval = 0.100
    /// 줄소거 정지. **지운 줄 수와 무관하게 고정**이다(위 ⚠️ 와 한 벌).
    package static let lineClearSeconds: TimeInterval = 0.500
    /// 탑아웃 뒤 결과 카드가 뜨기까지의 유예(그 사이 액션은 무시 — 죽자마자 실수로 새 판을 열지 않게).
    package static let overHold: TimeInterval = 0.4

    /// 조각당 접지(바닥에 닿아 있는) 총 체류 시간의 상한.
    ///
    /// ★ **선택적 보험이 아니라 필수 상수다.** 이 값을 빼면 고의 늘어뜨리기 상계가 **24.7분 → 71.0분**이 된다
    ///   (리셋 15회를 매번 락딜레이 끝까지 쓰는 경로. 715조각 × 0.5초 × 16 ≈ 95분 중 접지분만 해도 71분).
    ///   정직한 마무리는 9칸 슬라이드+회전 4회 = 0.631초(DAS 0.167 + ARR 0.033×8 + 회전)라 1.00초는 58% 여유다 —
    ///   즉 **체감 비용이 0 이면서 최악을 3분의 1로 자른다.**
    ///
    /// 예산은 조각이 아니라 **한 번의 배치**에 붙는다(홀드로 갈아타도 이어진다) — `holdCurrentPiece()` 주석 참고.
    package static let maxGroundedSeconds: TimeInterval = 1.00

    /// 레벨 축이 갈리는 지점의 advance. 이 앞은 20 마다, 뒤는 50 마다 한 레벨이다.
    package static let advanceAtGravityCap = 280
    /// 점수 배수·화면 표시 전용 레벨 상한. **난이도는 이미 L28~30 에서 바닥이라 여기서 더 조이지 않는다.**
    package static let scoreLevelCap = 30

    /// 엔진 자체 점수 상한. 다음 단계가 `MiniGameKind.tetris.maxScore` 를 이 값과 맞춘다.
    ///
    /// 왜 자르는가(거절이 아니라): 클라 업로드 게이트가 `guard score <= kind.maxScore else { return }` 라
    /// **초과분을 조용히 버린다** — 자르지 않으면 어떤 계산 착오에서든 최고 기록이 화면에도 순위표에도 안 남고 사라진다.
    /// 플래피가 같은 이유로 엔진에서 자른다(FlappyGame.swift:336-337). 구조적 최대가 실측 1,412만이라
    /// 이 문은 실제로는 한 번도 안 열린다 — 이중 안전망이다.
    package static let maxScore = 100_000_000

    // MARK: - 순수 규칙 — 레벨·중력·락다운

    /// advance(고정한 조각 + 지운 줄) → 레벨. **정수 나눗셈이다.**
    /// A < 280 은 20 마다(20G 를 advance 280 에 놓는다), 그 뒤는 50 마다(램프를 13레벨에 걸친다).
    package static func level(forAdvance advance: Int) -> Int {
        let a = max(0, advance)
        if a < advanceAtGravityCap { return 1 + a / 20 }
        return 15 + (a - advanceAtGravityCap) / 50
    }

    /// 점수 배수·화면 표시에 쓰는 레벨. 난이도 함수는 **이 값을 쓰지 않는다**(잘라 놓은 레벨로 중력을 읽으면 곡선이 헛돈다).
    package static func scoreLevel(forLevel level: Int) -> Int {
        min(max(1, level), scoreLevelCap)
    }

    /// 레벨 → 표준 중력 공식의 지수 단계. 사상만 우리 값이고(4 를 더한다 = 시작을 E5 에 둔다), 공식은 표준 그대로다.
    /// 19 에서 멈추는 이유: 표준 공식이 처음 20G(1/(20×60) = 8.333e-4 초/칸) 아래로 내려가는 단계가 E19 다.
    package static func gravityStage(forLevel level: Int) -> Int {
        min(4 + max(1, level), 19)
    }

    /// 중력(초/칸). 표준 공식 `(0.8 − 0.007·(E−1))^(E−1)`.
    ///
    /// ★ `min(stage, 20)` 클램프는 장식이 아니다: 밑 `0.8 − 0.007(E−1)` 은 E = 115.29 에서 0 을 지나
    /// **E = 116 부터 음수**가 된다(조각이 위로 솟는다). 바로 앞 E = 115 는 2.08e-308 로 Double 정규 최소(2.2e-308)
    /// 아래라 0 으로 언더플로하면 나눗셈이 ∞ 다. `gravityStage` 가 이미 19 에서 멈추지만, 이 함수를 직접 부르는
    /// 자리(테스트·검산)가 생기는 순간 그 보호가 사라지므로 **식이 있는 곳에 클램프를 둔다.**
    package static func gravitySeconds(forStage stage: Int) -> TimeInterval {
        let e = Double(min(max(stage, 1), 20))
        return pow(0.8 - 0.007 * (e - 1), e - 1)
    }

    package static func gravitySeconds(forLevel level: Int) -> TimeInterval {
        gravitySeconds(forStage: gravityStage(forLevel: level))
    }

    /// 소프트드롭(초/칸) — 표준대로 중력의 20배다.
    package static func softDropSeconds(forLevel level: Int) -> TimeInterval {
        gravitySeconds(forLevel: level) / 20
    }

    /// 락딜레이(초). 0.50(L≤15) → 0.16(L≥30) 선형.
    /// 0.16 에서 멈추는 이유: 24fps 화면에서 0.16초 = 3.84프레임이다. 이 밑으로 내리면 **입력 샘플링이 난이도를 대신한다**
    /// (같은 실력이 119Hz 에서는 살고 24Hz 에서는 죽는다).
    package static func lockDelaySeconds(forLevel level: Int) -> TimeInterval {
        if level <= 15 { return 0.50 }
        if level >= 30 { return 0.16 }
        return 0.50 + (0.16 - 0.50) * Double(level - 15) / 15.0
    }

    /// 접지 리셋 한도. 15(L≤15) → 2(L≥28) 선형(정수 반올림. 실제로는 15 ≤ L < 28 에서 정확히 `15 − (L−15)` 다).
    ///
    /// ★ **이 축이 판을 끝낸다.** 20G(L15~)에서 조각은 스폰과 거의 같은 틱에 더미 위에 얹히므로 가로 이동 한 번이 곧 리셋
    ///   한 번이다. 스폰 점유열은 4~6열(I 는 4~7 · O 는 5~6, 1-indexed)이라 왼벽까지 3칸·오른벽까지 4칸이 필요하다 —
    ///   **한도 2 에서는 어느 벽에도 못 닿는다.** 1·10열이 영구히 비므로 줄을 더 못 지우고, 남은 빈칸 ÷ 4 조각 안에
    ///   탑아웃이다(최대 50조각 ≈ 36초). 실력과 무관한 종료 보장이 여기서 나온다.
    ///   이 축은 **횟수**라서 24~119fps 어디서도 정확히 같게 동작한다 — 시간으로 막는 장치였다면 저주사율이 순위를 갈랐다.
    package static func lockResetLimit(forLevel level: Int) -> Int {
        if level <= 15 { return 15 }
        if level >= 28 { return 2 }
        return Int((15.0 + (2.0 - 15.0) * Double(level - 15) / 13.0).rounded())
    }

    /// 표준 규칙: 지금까지 닿은 가장 낮은 줄을 갱신하면 리셋 카운터가 재충전된다.
    /// **L > 15 에서는 끈다** — 거친 판(우물·계단)에서 접지 예산이 2~3배로 부푸는 것이 실측됐고, 그러면 위 종료 보장이
    /// "벽에 못 닿는다"에서 "한 칸 내려갈 때마다 다시 2칸"으로 새 버린다.
    package static func lockResetRefreshes(forLevel level: Int) -> Bool {
        level <= 15
    }

    // MARK: - 순수 규칙 — 점수 (전부 표준 그대로)

    /// 행동 점수(레벨 배수 전). 줄소거·T-스핀 표.
    package static func actionPoints(lines: Int, spin: Spin = .none) -> Int {
        switch spin {
        case .none:
            switch lines {
            case 1: return 100
            case 2: return 300
            case 3: return 500
            case 4: return 800
            default: return 0
            }
        case .full:
            switch lines {
            case 0: return 400
            case 1: return 800
            case 2: return 1200
            case 3: return 1600
            default: return 0
            }
        case .mini:
            switch lines {
            case 0: return 100
            case 1: return 200
            case 2: return 400
            default: return 0
            }
        }
    }

    /// '어려운 소거' — 테트리스와 **모든 T-스핀 줄소거**. B2B 사슬을 잇는 것도, 끊지 않는 것도 이 판정이다.
    /// 줄을 안 지우는 배치로는 사슬이 안 끊긴다(평범한 1~3줄 소거만 끊는다).
    package static func isDifficult(lines: Int, spin: Spin) -> Bool {
        if lines == 4 { return true }
        return lines > 0 && spin != .none
    }

    /// 퍼펙트 클리어 보너스(레벨 배수 전). 행동 점수에 **더한다**(B2B ×1.5 는 여기 안 곱한다).
    package static func perfectClearPoints(lines: Int, backToBackTetris: Bool) -> Int {
        if lines == 4, backToBackTetris { return 3200 }
        switch lines {
        case 1: return 800
        case 2: return 1200
        case 3: return 1800
        case 4: return 2000
        default: return 0
        }
    }

    /// 콤보 점수 = 50 × 콤보수 × 레벨. 콤보수는 '연속 소거 − 1' 이라 첫 소거는 0 점이다.
    package static func comboPoints(combo: Int, scoreLevel: Int) -> Int {
        max(0, combo) * 50 * scoreLevel
    }

    /// 한 배치가 만드는 점수 전부(드롭 점수 제외). B2B 배수는 **행동 점수에만** 곱한다.
    ///
    /// `× 3 / 2` 로 적은 이유: 행동 점수 × 레벨은 언제나 100의 배수라 ×1.5 가 정확히 정수로 떨어진다.
    /// Double 로 곱하면 1,199.9999… 가 내림돼 조용히 1점이 사라진다.
    package static func placementPoints(lines: Int, spin: Spin, scoreLevel: Int,
                                        backToBack: Bool, combo: Int, perfectClear: Bool) -> Int {
        var points = actionPoints(lines: lines, spin: spin) * scoreLevel
        if backToBack { points = points * 3 / 2 }
        if perfectClear {
            points += perfectClearPoints(lines: lines, backToBackTetris: backToBack && lines == 4) * scoreLevel
        }
        points += comboPoints(combo: combo, scoreLevel: scoreLevel)
        return points
    }

    // MARK: - 순수 규칙 — 모양 · SRS 킥표

    /// 바운딩 상자 안의 네 칸(dx = 열, dy = 행, 둘 다 0 = 상자의 왼쪽 위).
    /// 3×3 상자(I 만 4×4)를 쓰는 것은 SRS 의 전제다 — 상자를 옮기는 것이 곧 킥이다.
    package static func shape(_ piece: Piece, _ rotation: Rotation) -> [(dx: Int, dy: Int)] {
        switch piece {
        case .i:
            switch rotation {
            case .spawn: return [(0, 1), (1, 1), (2, 1), (3, 1)]
            case .right: return [(2, 0), (2, 1), (2, 2), (2, 3)]
            case .flip:  return [(0, 2), (1, 2), (2, 2), (3, 2)]
            case .left:  return [(1, 0), (1, 1), (1, 2), (1, 3)]
            }
        case .j:
            switch rotation {
            case .spawn: return [(0, 0), (0, 1), (1, 1), (2, 1)]
            case .right: return [(1, 0), (2, 0), (1, 1), (1, 2)]
            case .flip:  return [(0, 1), (1, 1), (2, 1), (2, 2)]
            case .left:  return [(1, 0), (1, 1), (0, 2), (1, 2)]
            }
        case .l:
            switch rotation {
            case .spawn: return [(2, 0), (0, 1), (1, 1), (2, 1)]
            case .right: return [(1, 0), (1, 1), (1, 2), (2, 2)]
            case .flip:  return [(0, 1), (1, 1), (2, 1), (0, 2)]
            case .left:  return [(0, 0), (1, 0), (1, 1), (1, 2)]
            }
        case .o:
            // O 는 회전해도 모양이 같다 — 네 상태 전부 같은 칸이라 킥을 볼 일이 없다(표준).
            return [(1, 0), (2, 0), (1, 1), (2, 1)]
        case .s:
            switch rotation {
            case .spawn: return [(1, 0), (2, 0), (0, 1), (1, 1)]
            case .right: return [(1, 0), (1, 1), (2, 1), (2, 2)]
            case .flip:  return [(1, 1), (2, 1), (0, 2), (1, 2)]
            case .left:  return [(0, 0), (0, 1), (1, 1), (1, 2)]
            }
        case .t:
            switch rotation {
            case .spawn: return [(1, 0), (0, 1), (1, 1), (2, 1)]
            case .right: return [(1, 0), (1, 1), (2, 1), (1, 2)]
            case .flip:  return [(0, 1), (1, 1), (2, 1), (1, 2)]
            case .left:  return [(1, 0), (0, 1), (1, 1), (1, 2)]
            }
        case .z:
            switch rotation {
            case .spawn: return [(0, 0), (1, 0), (1, 1), (2, 1)]
            case .right: return [(2, 0), (1, 1), (2, 1), (1, 2)]
            case .flip:  return [(0, 1), (1, 1), (1, 2), (2, 2)]
            case .left:  return [(1, 0), (0, 1), (1, 1), (0, 2)]
            }
        }
    }

    /// SRS 월킥표. **y 양수 = 위**(표준 표기 그대로 옮겼다). 판 좌표는 아래로 증가하므로 적용할 때 행은 `- dy` 다.
    /// 1번 오프셋 (0,0) 은 '제자리 회전'이고, 5번(마지막)으로 성공한 T 회전은 T-스핀 미니가 아니라 **완전 T-스핀**이다.
    ///
    /// 180° 회전은 v1 에서 제공하지 않는다(가이드라인 필수가 아니고 표준 킥표가 없다).
    package static func kicks(piece: Piece, from: Rotation, to: Rotation) -> [(dx: Int, dy: Int)] {
        // O 는 어느 상태에서도 모양이 같아 킥을 보지 않는다.
        if piece == .o { return [(0, 0)] }
        let key = (from.rawValue, to.rawValue)
        if piece == .i {
            switch key {
            case (0, 1): return [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)]
            case (1, 0): return [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)]
            case (1, 2): return [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)]
            case (2, 1): return [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)]
            case (2, 3): return [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)]
            case (3, 2): return [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)]
            case (3, 0): return [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)]
            case (0, 3): return [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)]
            default: return [(0, 0)]
            }
        }
        switch key {
        case (0, 1): return [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)]
        case (1, 0): return [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)]
        case (1, 2): return [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)]
        case (2, 1): return [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)]
        case (2, 3): return [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)]
        case (3, 2): return [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)]
        case (3, 0): return [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)]
        case (0, 3): return [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)]
        default: return [(0, 0)]
        }
    }

    // MARK: - 상태

    /// 굳은 칸. `board[행][열]` 이고 행 0 이 맨 위다. nil = 빈 칸, 값 = 그 칸을 만든 조각(색은 뷰가 정한다).
    package private(set) var board: [[Piece?]]
    /// 떨어지는 조각. 텀(ARE·줄소거) 동안에는 nil 이다.
    package private(set) var active: ActivePiece?
    /// 넥스트 큐. 언제나 `nextCount` 개를 채워 둔다.
    package private(set) var next: [Piece]
    package private(set) var heldPiece: Piece?
    /// 이 배치에서 홀드를 이미 썼는가(조각당 1회 — 굳기 전 재홀드 금지).
    package private(set) var holdUsed: Bool
    package private(set) var score: Int
    /// 난이도 시계. **고정한 조각 수 + 지운 줄 수**다.
    package private(set) var advance: Int
    /// 이번 판에 지운 줄 누계(무대 경계·화면 표시가 읽는다. 난이도는 읽지 않는다).
    package private(set) var lines: Int
    /// 콤보수. −1 = 사슬 없음(소거 없는 배치에서 −1 로 돌아간다).
    package private(set) var combo: Int
    /// B2B 사슬 길이. −1 = 없음, 0 = 첫 어려운 소거(배수 없음), 1 이상부터 ×1.5 가 붙는다.
    package private(set) var backToBack: Int
    package private(set) var phase: Phase
    /// 이번 판이 시작된 뒤 흐른 시간(초). 벽시계가 아니라 `step(dt:)` 이 흘린 dt 의 합이다 — 판이 결정적으로 재현된다.
    package private(set) var elapsed: TimeInterval
    /// 마지막 배치 결과(그림 전용).
    package private(set) var lastClear: ClearEvent?

    // ── 내부 시계·상태 ───────────────────────────────────────────────────────────────
    // 전부 초 단위 '남은 시간' 카운트다운이다. 프레임 수가 아니라 dt 를 깎으므로 주사율과 무관하다.
    private var rng: MiniGameRandom
    private var bag: [Piece]
    /// 다음 자동 반복 이동까지 남은 시간. nil = 방향키가 안 눌려 있음.
    private var repeatCountdown: TimeInterval?
    /// 자동 반복 방향(−1 왼쪽 · +1 오른쪽 · 0 없음).
    private var repeatDirection: Int
    private var leftHeld: Bool
    private var rightHeld: Bool
    private var softDropHeld: Bool
    /// 다음 낙하 한 칸까지 남은 시간.
    private var fallCountdown: TimeInterval
    /// 지금 접지 상태로 머문 시간(이동·회전이 성공하면 0 으로 되돌아간다).
    private var groundedSeconds: TimeInterval
    /// 이 배치가 접지 상태로 머문 **총** 시간(`maxGroundedSeconds` 가 자른다. 홀드로 갈아타도 이어진다).
    private var groundedTotalSeconds: TimeInterval
    /// 쓴 접지 리셋 횟수.
    private var lockResets: Int
    /// 지금까지 조각이 닿은 가장 낮은 행(재충전 판정).
    private var lowestRow: Int
    /// 마지막으로 성공한 행동이 회전이었는가(T-스핀의 첫째 조건).
    private var lastActionWasRotation: Bool
    /// 그 회전이 킥표의 5번째(마지막) 오프셋으로 성공했는가(미니를 완전으로 올리는 조건).
    private var lastKickWasFinal: Bool

    // MARK: - 읽기

    /// 지금 레벨(난이도가 읽는 값).
    package var level: Int { Self.level(forAdvance: advance) }
    /// 점수 배수·화면 표시용 레벨(`min(level, 30)`).
    package var scoreLevel: Int { Self.scoreLevel(forLevel: level) }
    /// 다음 레벨까지 남은 advance. 진행 표시는 **줄 수가 아니라 이 값**을 봐야 한다 —
    /// 레벨 축이 advance 라 '줄 수'만 봐서는 다음 상승을 못 읽는다.
    package var advanceToNextLevel: Int {
        let step = advance < Self.advanceAtGravityCap ? 20 : 50
        let base = advance < Self.advanceAtGravityCap ? 0 : Self.advanceAtGravityCap
        return step - (advance - base) % step
    }

    /// 프레임 루프가 돌아야 하는 상태. ready/result 는 정지.
    package var isPlaying: Bool {
        switch phase {
        case .running, .lineClear, .are, .over: return true
        case .ready, .result: return false
        }
    }

    /// 탑아웃 이후(over·result).
    package var isGameOver: Bool {
        switch phase {
        case .over, .result: return true
        case .ready, .running, .lineClear, .are: return false
        }
    }

    /// 고스트(지금 하드드롭하면 앉을 자리). 규칙은 이 값을 읽지 않는다 — 그리기·조준 전용이다.
    package var ghost: ActivePiece? {
        guard let active else { return nil }
        var candidate = active
        while true {
            var next = candidate
            next.row += 1
            guard fits(next) else { return candidate }
            candidate = next
        }
    }

    /// 지금 접지(한 칸도 못 내려감) 상태인가.
    package var isGrounded: Bool {
        guard let active else { return false }
        var below = active
        below.row += 1
        return !fits(below)
    }

    // MARK: - 만들기

    package init(seed: UInt64) {
        rng = MiniGameRandom(seed: seed)
        board = Self.emptyBoard()
        active = nil
        next = []
        heldPiece = nil
        holdUsed = false
        score = 0
        advance = 0
        lines = 0
        combo = -1
        backToBack = -1
        phase = .ready
        elapsed = 0
        lastClear = nil
        bag = []
        repeatCountdown = nil
        repeatDirection = 0
        leftHeld = false
        rightHeld = false
        softDropHeld = false
        fallCountdown = Self.gravitySeconds(forLevel: 1)
        groundedSeconds = 0
        groundedTotalSeconds = 0
        lockResets = 0
        lowestRow = -1
        lastActionWasRotation = false
        lastKickWasFinal = false
    }

    /// 테스트 픽스처 — 임의 상태에서 시작한다(난수는 seed).
    /// **새 인자는 전부 기본값이 있다**: 예전 픽스처가 그대로 컴파일돼야 규칙 테스트가 흔들리지 않는다.
    package init(seed: UInt64,
                 board: [[Piece?]],
                 active: ActivePiece?,
                 phase: Phase = .running,
                 next: [Piece] = [],
                 heldPiece: Piece? = nil,
                 holdUsed: Bool = false,
                 score: Int = 0,
                 advance: Int = 0,
                 lines: Int = 0,
                 combo: Int = -1,
                 backToBack: Int = -1,
                 elapsed: TimeInterval = 0,
                 softDropHeld: Bool = false) {
        self.init(seed: seed)
        self.board = Self.normalized(board)
        self.active = active
        self.phase = phase
        self.next = next
        self.heldPiece = heldPiece
        self.holdUsed = holdUsed
        self.score = score
        self.advance = advance
        self.lines = lines
        self.combo = combo
        self.backToBack = backToBack
        self.elapsed = elapsed
        self.softDropHeld = softDropHeld
        refillNext()
        fallCountdown = fallInterval
        lowestRow = active.map { Self.bottomRow(of: $0) } ?? -1
    }

    /// 빈 판.
    package static func emptyBoard() -> [[Piece?]] {
        Array(repeating: Array(repeating: Piece?.none, count: columns), count: totalRows)
    }

    /// 판 리터럴 픽스처. 문자열 한 줄이 판의 한 행이고 `.` 은 빈 칸, 그 밖의 글자는 찬 칸이다
    /// (`i j l o s t z` 는 그 조각으로, 다른 글자는 `.i` 로 채운다 — 색은 규칙이 안 본다).
    /// 주어진 행들은 **판 바닥에 붙는다**: 위쪽 빈 행은 자동으로 채운다.
    package static func boardFixture(bottomRows rows: [String]) -> [[Piece?]] {
        var board = emptyBoard()
        let start = totalRows - rows.count
        for (offset, line) in rows.enumerated() {
            let row = start + offset
            guard row >= 0, row < totalRows else { continue }
            for (column, character) in line.enumerated() where column < columns {
                guard character != "." else { continue }
                board[row][column] = piece(forFixtureCharacter: character)
            }
        }
        return board
    }

    private static func piece(forFixtureCharacter character: Character) -> Piece {
        switch character {
        case "i", "I": return .i
        case "j", "J": return .j
        case "l", "L": return .l
        case "o", "O": return .o
        case "s", "S": return .s
        case "t", "T": return .t
        case "z", "Z": return .z
        default: return .i
        }
    }

    /// 픽스처가 넘긴 판을 40×10 으로 맞춘다(모자라면 위를 비우고, 넘치면 위를 버린다).
    private static func normalized(_ board: [[Piece?]]) -> [[Piece?]] {
        var rows = board.map { row -> [Piece?] in
            var row = row
            if row.count < columns { row.append(contentsOf: Array(repeating: Piece?.none, count: columns - row.count)) }
            if row.count > columns { row = Array(row.prefix(columns)) }
            return row
        }
        if rows.count > totalRows { rows = Array(rows.suffix(totalRows)) }
        if rows.count < totalRows {
            let pad = Array(repeating: Array(repeating: Piece?.none, count: columns), count: totalRows - rows.count)
            rows = pad + rows
        }
        return rows
    }

    /// 난수 상태는 비교하지 않는다 — "같은 판"인지가 관심사이고, `MiniGameRandom` 은 Equatable 이 아니다.
    /// 나머지는 **내부 시계까지 전부** 본다: 접지 시계 하나가 갈라져도 다음 프레임의 결과가 갈리므로,
    /// 비교에서 빼 두면 "같다고 했는데 다음 프레임에 다른 판"이 된다.
    package static func == (lhs: TetrisGame, rhs: TetrisGame) -> Bool {
        lhs.board == rhs.board && lhs.active == rhs.active && lhs.next == rhs.next
            && lhs.heldPiece == rhs.heldPiece && lhs.holdUsed == rhs.holdUsed
            && lhs.score == rhs.score && lhs.advance == rhs.advance && lhs.lines == rhs.lines
            && lhs.combo == rhs.combo && lhs.backToBack == rhs.backToBack
            && lhs.phase == rhs.phase && lhs.elapsed == rhs.elapsed && lhs.lastClear == rhs.lastClear
            && lhs.bag == rhs.bag
            && lhs.repeatCountdown == rhs.repeatCountdown && lhs.repeatDirection == rhs.repeatDirection
            && lhs.leftHeld == rhs.leftHeld && lhs.rightHeld == rhs.rightHeld
            && lhs.softDropHeld == rhs.softDropHeld && lhs.fallCountdown == rhs.fallCountdown
            && lhs.groundedSeconds == rhs.groundedSeconds && lhs.groundedTotalSeconds == rhs.groundedTotalSeconds
            && lhs.lockResets == rhs.lockResets && lhs.lowestRow == rhs.lowestRow
            && lhs.lastActionWasRotation == rhs.lastActionWasRotation
            && lhs.lastKickWasFinal == rhs.lastKickWasFinal
    }

    // MARK: - 입력

    /// 액션(클릭·스페이스). ready/result 면 새 판, running 이면 **하드드롭**, 그 밖(텀·유예)에서는 아무 일도 없다.
    /// 시작과 하드드롭이 같은 키인 것은 기존 두 게임의 관용구를 잇는 것이고(허브가 `actionCount` 하나만 넘긴다),
    /// 그래야 스페이스가 이미 검증된 관대한 키 게이트를 그대로 쓴다.
    package mutating func action() {
        switch phase {
        case .ready, .result:
            startRound()
        case .running:
            hardDrop()
        case .lineClear, .are, .over:
            return
        }
    }

    /// 왼쪽 방향키 눌림/뗌. **뗌은 멱등이다** — 게이트 밖에서 온 뗌도 안전하게 부를 수 있어야 키가 굳지 않는다.
    package mutating func setLeftHeld(_ held: Bool) {
        guard held != leftHeld else { return }
        leftHeld = held
        updateRepeat(pressed: held ? -1 : nil, released: held ? nil : -1)
    }

    package mutating func setRightHeld(_ held: Bool) {
        guard held != rightHeld else { return }
        rightHeld = held
        updateRepeat(pressed: held ? 1 : nil, released: held ? nil : 1)
    }

    /// 소프트드롭 눌림/뗌. 누르는 순간 떨어지는 속도가 바뀐다(다음 칸까지 남은 시간을 새 간격으로 줄인다) —
    /// 누른 뒤 한 칸을 기다리게 하면 "눌렀는데 안 내려간다"가 된다.
    package mutating func setSoftDropHeld(_ held: Bool) {
        guard held != softDropHeld else { return }
        softDropHeld = held
        fallCountdown = min(fallCountdown, fallInterval)
    }

    /// 회전. 성공하면 접지 리셋을 한 번 쓴다(예산이 바닥나면 그 자리에서 굳는다 — `registerPlacementAction`).
    package mutating func rotate(clockwise: Bool) {
        guard case .running = phase, let current = active else { return }
        let target = clockwise ? current.rotation.clockwise : current.rotation.counterClockwise
        let offsets = Self.kicks(piece: current.piece, from: current.rotation, to: target)
        for (index, offset) in offsets.enumerated() {
            var candidate = current
            candidate.rotation = target
            candidate.column += offset.dx
            candidate.row -= offset.dy          // 킥표의 y 는 위가 양수다. 판 행은 아래로 증가한다.
            guard fits(candidate) else { continue }
            active = candidate
            lastActionWasRotation = true
            lastKickWasFinal = index == offsets.count - 1
            registerPlacementAction()
            return
        }
    }

    /// 홀드(조각당 1회). 홀드가 비어 있으면 넥스트에서 한 장을 꺼내 온다.
    ///
    /// 접지 예산(`groundedTotalSeconds`)은 **이어진다**: 예산을 조각이 아니라 한 번의 배치에 붙이지 않으면
    /// 홀드 한 번에 예산이 두 배가 되어 늘어뜨리기 상계가 24.7분에서 다시 벌어진다.
    /// 리셋 횟수는 새로 준다 — 갈아탄 조각은 아직 한 번도 안 움직였고, 바닥 2 의 종료 보장은 **스폰 자리가
    /// 원위치로 돌아가기 때문에** 그대로 선다(홀드로 갈아타도 조각은 다시 4~6열에서 시작한다).
    package mutating func holdCurrentPiece() {
        guard case .running = phase, let current = active, !holdUsed else { return }
        let incoming: Piece
        if let held = heldPiece {
            incoming = held
        } else {
            incoming = takeFromQueue()
        }
        heldPiece = current.piece
        holdUsed = true
        spawn(incoming, fromHold: true)
    }

    /// 허브가 판을 끊을 때(창 닫힘·포커스 상실·게임 전환). 진행 중이면 그 점수로 결과 확정 — 점수는 유효하다.
    package mutating func interrupt() {
        switch phase {
        case .running, .lineClear, .are, .over:
            phase = .result
            releaseAllKeys()
        case .ready, .result:
            break
        }
    }

    /// 눌린 채 판이 끝날 때. 키가 굳지 않게 허브가 출구마다 부른다.
    package mutating func releaseAllKeys() {
        leftHeld = false
        rightHeld = false
        softDropHeld = false
        repeatDirection = 0
        repeatCountdown = nil
    }

    // MARK: - 한 걸음

    /// 한 프레임. **첫 줄이 dt 클램프**다 — 앱 정지·창 재표시 뒤 첫 프레임이 몇 초를 한 번에 밀지 않게.
    ///
    /// 안에서는 dt 를 **사건 사이로 잘라** 흘린다(자동 반복 · 낙하 · 접지 만료). 그래야 24fps 와 119fps 가
    /// 같은 판을 낸다 — "한 프레임에 한 칸"으로 짜면 레벨 15(프레임당 20칸)가 재현되지 않고 저주사율 화면이
    /// 순위를 가른다. 자른 조각의 남은 시간은 **버리지 않고 다음 단계로 넘긴다**(텀이 끝난 뒤 남은 dt 를 버리면
    /// 조각이 뜨는 시각이 주사율마다 달라진다).
    package mutating func step(dt rawDt: TimeInterval) {
        let dt = min(max(0, rawDt), Self.maxStep)
        guard dt > 0 else { return }
        var remaining = dt

        while remaining > 1e-12 {
            switch phase {
            case .ready, .result:
                return
            case .over(let hold):
                let used = min(remaining, hold)
                remaining -= used
                phase = hold - used <= 0 ? .result : .over(hold: hold - used)
                if case .result = phase { return }
            case .lineClear(let left):
                let used = min(remaining, left)
                elapsed += used
                remaining -= used
                advanceRepeatClock(used)
                phase = left - used <= 0 ? .are(remaining: Self.areSeconds) : .lineClear(remaining: left - used)
            case .are(let left):
                let used = min(remaining, left)
                elapsed += used
                remaining -= used
                advanceRepeatClock(used)
                if left - used <= 0 {
                    spawn(takeFromQueue(), fromHold: false)
                } else {
                    phase = .are(remaining: left - used)
                }
            case .running:
                remaining = advanceRunning(remaining)
            }
        }
    }

    // MARK: - 진행 중 한 조각

    /// `.running` 동안 dt 를 사건 사이로 잘라 흘린다. 조각이 굳으면 **쓰지 않은 시간을 돌려준다.**
    private mutating func advanceRunning(_ dt: TimeInterval) -> TimeInterval {
        var remaining = dt
        while remaining > 1e-12 {
            guard active != nil else { return remaining }

            // 간격은 매번 새로 읽는다 — 소프트드롭을 누르거나 레벨이 오르면 곧바로 반영돼야 한다.
            fallCountdown = min(fallCountdown, fallInterval)

            let grounded = isGrounded
            if grounded {
                // 접지 만료 셋 중 하나라도 걸리면 굳는다: ① 락딜레이 ② 배치당 접지 총량 ③ 리셋 예산 소진.
                // ③ 은 표준 Extended Placement 의 "예산을 다 쓰면 바닥에 닿는 순간 곧바로 고정"이다.
                if lockResets >= Self.lockResetLimit(forLevel: level) {
                    lockPiece()
                    return remaining
                }
                let untilLock = min(Self.lockDelaySeconds(forLevel: level) - groundedSeconds,
                                    Self.maxGroundedSeconds - groundedTotalSeconds)
                if untilLock <= 0 {
                    lockPiece()
                    return remaining
                }
                let slice = max(0, min(remaining, min(untilLock, repeatCountdown ?? .infinity)))
                remaining -= slice
                elapsed += slice
                groundedSeconds += slice
                groundedTotalSeconds += slice
                advanceRepeatClock(slice)
                fireDueRepeat()
            } else {
                groundedSeconds = 0
                let slice = max(0, min(remaining, min(fallCountdown, repeatCountdown ?? .infinity)))
                remaining -= slice
                elapsed += slice
                fallCountdown -= slice
                advanceRepeatClock(slice)
                fireDueRepeat()
                if fallCountdown <= 0 {
                    fallOneCell()
                    fallCountdown = fallInterval
                }
            }
            guard case .running = phase else { return remaining }
        }
        return 0
    }

    /// 지금 조각이 한 칸 떨어지는 데 걸리는 시간. 소프트드롭이 눌려 있으면 중력의 1/20.
    private var fallInterval: TimeInterval {
        softDropHeld ? Self.softDropSeconds(forLevel: level) : Self.gravitySeconds(forLevel: level)
    }

    /// DAS/ARR 시계만 흘린다. **조각이 없는 동안(ARE·줄소거)에도 돈다** — 표준이 그렇고, 그래야 텀이 끝나자마자
    /// 이어서 움직인다. 그래도 **입력이 쌓이지는 않는다**: 쌓이는 것은 시계뿐이고, 조각이 없는 동안의 키 누름은
    /// 아무 데도 기록되지 않는다(입력 선행을 안 넣는다는 사용자 확정).
    private mutating func advanceRepeatClock(_ dt: TimeInterval) {
        guard let countdown = repeatCountdown else { return }
        repeatCountdown = max(0, countdown - dt)
    }

    /// 자동 반복이 만기면 한 칸 옮긴다(막혀 있어도 시계는 다시 감긴다 — 벽에 붙은 채 DAS 가 풀리지 않게).
    private mutating func fireDueRepeat() {
        guard let countdown = repeatCountdown, countdown <= 0, repeatDirection != 0 else { return }
        repeatCountdown = Self.arrSeconds
        guard case .running = phase, active != nil else { return }
        shift(by: repeatDirection)
    }

    /// 방향키 상태가 바뀔 때 자동 반복을 다시 잡는다.
    /// 새로 누른 쪽이 언제나 이긴다(마지막 누름 우선). **뗌에서는 즉시 이동을 주지 않는다** —
    /// 뗌이 곧 한 칸이 되면 키를 떼는 것만으로 접지 리셋 예산이 줄어든다.
    private mutating func updateRepeat(pressed: Int?, released: Int?) {
        if let direction = pressed {
            repeatDirection = direction
            repeatCountdown = Self.dasSeconds
            if case .running = phase, active != nil { shift(by: direction) }
            return
        }
        guard let direction = released, direction == repeatDirection else { return }
        if leftHeld {
            repeatDirection = -1
            repeatCountdown = Self.dasSeconds
        } else if rightHeld {
            repeatDirection = 1
            repeatCountdown = Self.dasSeconds
        } else {
            repeatDirection = 0
            repeatCountdown = nil
        }
    }

    /// 가로 한 칸. 성공하면 접지 리셋을 한 번 쓴다.
    @discardableResult
    private mutating func shift(by dx: Int) -> Bool {
        guard let current = active else { return false }
        var candidate = current
        candidate.column += dx
        guard fits(candidate) else { return false }
        active = candidate
        lastActionWasRotation = false
        registerPlacementAction()
        return true
    }

    /// 중력·소프트드롭 한 칸.
    private mutating func fallOneCell() {
        guard let current = active else { return }
        var candidate = current
        candidate.row += 1
        guard fits(candidate) else { return }
        active = candidate
        // 떨어지는 동안에는 회전 표시를 지운다 — 회전으로 끼워 넣은 뒤 **더 내려간** 조각은 T-스핀이 아니다.
        // (20G 에서도 문제가 없다: 킥으로 슬롯에 끼워진 조각은 그 자리에서 더 못 내려가므로 표시가 살아 있다.)
        lastActionWasRotation = false
        if softDropHeld { addScore(1) }
        noteNewLowestRow()
    }

    /// 하드드롭 — 끝까지 떨어뜨리고 락딜레이 없이 굳힌다. 칸당 2점.
    private mutating func hardDrop() {
        guard let current = active else { return }
        var candidate = current
        var dropped = 0
        while true {
            var next = candidate
            next.row += 1
            guard fits(next) else { break }
            candidate = next
            dropped += 1
        }
        active = candidate
        if dropped > 0 {
            // 0칸 하드드롭은 회전 표시를 지우지 않는다 — 회전해서 끼운 자리에서 바로 떨어뜨리는 T-스핀이 표준이다.
            lastActionWasRotation = false
            addScore(2 * dropped)
        }
        lockPiece()
    }

    /// 이동·회전이 성공했을 때의 접지 리셋 회계.
    ///
    /// 표준 Extended Placement: 이동·회전마다 락딜레이가 되감기고, 그 횟수가 한도에 묶인다.
    /// 예산을 다 쓰면 **바닥에 닿는 순간 곧바로 고정**된다 — 여기서는 조각이 이미 닿아 있으면 다음 걸음에서 굳고
    /// (`advanceRunning` 의 ③), 공중이면 착지하는 순간 굳는다. 이 회계가 곧 '리셋 바닥 2' 의 종료 보장이다.
    private mutating func registerPlacementAction() {
        let limit = Self.lockResetLimit(forLevel: level)
        if lockResets < limit {
            lockResets += 1
            groundedSeconds = 0
        }
        noteNewLowestRow()
    }

    /// 가장 낮은 줄을 갱신했으면 리셋 예산을 재충전한다(L ≤ 15 에서만).
    private mutating func noteNewLowestRow() {
        guard let active else { return }
        let bottom = Self.bottomRow(of: active)
        guard bottom > lowestRow else { return }
        lowestRow = bottom
        if Self.lockResetRefreshes(forLevel: level) {
            lockResets = 0
            groundedSeconds = 0
        }
    }

    // MARK: - 굳히기

    private mutating func lockPiece() {
        guard let current = active else { return }
        let spin = detectSpin(for: current)
        // 행 범위만 막는다: 열은 `fits` 가 언제나 먼저 거르므로 여기서 또 막으면 **불변식이 깨진 것을 조용히 삼킨다**
        // (실측: `shift` 의 충돌 판정을 지우는 뮤테이션이 열 가드가 있으면 초록으로 통과했다. 지금은 크래시로 드러난다).
        // 행 가드는 픽스처 때문이다 — 테스트용 init 은 조각 자리를 검사하지 않아 판 위로 벗어난 조각을 만들 수 있다.
        for cell in current.cells where cell.row >= 0 && cell.row < Self.totalRows {
            board[cell.row][cell.column] = current.piece
        }
        active = nil

        let cleared = clearFullRows()
        let difficult = Self.isDifficult(lines: cleared, spin: spin)

        // B2B: 어려운 소거는 사슬을 잇고, 평범한 소거(1~3줄)만 끊는다. 소거 없는 배치는 사슬을 건드리지 않는다.
        var b2bApplies = false
        if cleared > 0 {
            if difficult {
                b2bApplies = backToBack >= 0
                backToBack += 1
            } else {
                backToBack = -1
            }
            combo += 1
        } else {
            combo = -1
        }

        let perfect = cleared > 0 && isBoardEmpty
        let points = Self.placementPoints(lines: cleared, spin: spin, scoreLevel: scoreLevel,
                                          backToBack: b2bApplies, combo: combo, perfectClear: perfect)
        addScore(points)
        lastClear = ClearEvent(lines: cleared, spin: spin, backToBack: b2bApplies,
                               perfectClear: perfect, points: points, at: elapsed)

        // 난이도 시계는 **여기서만** 움직인다: 고정 1 + 지운 줄. 시간도 프레임도 아니다.
        advance += 1 + cleared
        lines += cleared

        holdUsed = false
        phase = cleared > 0 ? .lineClear(remaining: Self.lineClearSeconds) : .are(remaining: Self.areSeconds)
    }

    /// 3코너 규칙. 마지막 행동이 회전인 T 만 본다.
    private func detectSpin(for piece: ActivePiece) -> Spin {
        guard piece.piece == .t, lastActionWasRotation else { return .none }
        // T 의 중심은 어느 회전에서도 상자의 (1,1) 이다.
        let centerRow = piece.row + 1
        let centerColumn = piece.column + 1
        let topLeft = isBlocked(row: centerRow - 1, column: centerColumn - 1)
        let topRight = isBlocked(row: centerRow - 1, column: centerColumn + 1)
        let bottomLeft = isBlocked(row: centerRow + 1, column: centerColumn - 1)
        let bottomRight = isBlocked(row: centerRow + 1, column: centerColumn + 1)
        let blocked = [topLeft, topRight, bottomLeft, bottomRight].filter { $0 }.count
        guard blocked >= 3 else { return .none }
        // T 가 가리키는 쪽 두 모서리.
        let front: (Bool, Bool)
        switch piece.rotation {
        case .spawn: front = (topLeft, topRight)
        case .right: front = (topRight, bottomRight)
        case .flip:  front = (bottomLeft, bottomRight)
        case .left:  front = (topLeft, bottomLeft)
        }
        if front.0 && front.1 { return .full }
        // 킥표의 5번째(마지막) 오프셋으로 성공한 회전은 미니가 아니라 완전 T-스핀이다(표준 예외).
        return lastKickWasFinal ? .full : .mini
    }

    /// 꽉 찬 줄을 지우고 위를 내린다. 지운 줄 수를 돌려준다.
    private mutating func clearFullRows() -> Int {
        var kept: [[Piece?]] = []
        kept.reserveCapacity(Self.totalRows)
        var cleared = 0
        for row in board {
            if row.allSatisfy({ $0 != nil }) {
                cleared += 1
            } else {
                kept.append(row)
            }
        }
        guard cleared > 0 else { return 0 }
        let pad = Array(repeating: Array(repeating: Piece?.none, count: Self.columns), count: cleared)
        board = pad + kept
        return cleared
    }

    private var isBoardEmpty: Bool {
        board.allSatisfy { $0.allSatisfy { $0 == nil } }
    }

    // MARK: - 조각 내보내기

    /// 새 판. 난수만 이어 받고 나머지는 전부 처음 값으로 돌린다(같은 판을 두 번 시작하면 두 번째는 다른 조각 순서다 —
    /// 이건 플래피와 같은 규약이고, 한 판 안에서의 재현성과는 무관하다).
    private mutating func startRound() {
        board = Self.emptyBoard()
        active = nil
        next = []
        bag = []
        heldPiece = nil
        holdUsed = false
        score = 0
        advance = 0
        lines = 0
        combo = -1
        backToBack = -1
        elapsed = 0
        lastClear = nil
        releaseAllKeys()
        groundedSeconds = 0
        groundedTotalSeconds = 0
        lockResets = 0
        lowestRow = -1
        lastActionWasRotation = false
        lastKickWasFinal = false
        phase = .running
        spawn(takeFromQueue(), fromHold: false)
    }

    /// 새 조각을 스폰 자리에 놓는다. 스폰 4칸 중 하나라도 막혀 있으면 **블록아웃**으로 그 자리에서 끝난다
    /// (락아웃·파셜락아웃은 v1 에서 쓰지 않는다 — 판정이 하나면 테스트가 하나다).
    ///
    /// `fromHold` 는 접지 예산의 주인을 가른다: 홀드로 갈아탄 조각은 **같은 배치**라 예산을 이어받고,
    /// 굳은 뒤에 나오는 조각은 새 배치라 예산을 새로 받는다.
    private mutating func spawn(_ piece: Piece, fromHold: Bool) {
        let candidate = ActivePiece(piece: piece, rotation: .spawn,
                                    column: Self.spawnColumn, row: Self.spawnRow)
        active = candidate
        groundedSeconds = 0
        if !fromHold { groundedTotalSeconds = 0 }
        lockResets = 0
        lowestRow = Self.bottomRow(of: candidate)
        lastActionWasRotation = false
        lastKickWasFinal = false
        fallCountdown = fallInterval
        guard fits(candidate) else {
            // 겹친 조각을 그대로 남긴다 — 화면이 "여기서 막혔다"를 보여 줄 수 있어야 한다.
            phase = .over(hold: Self.overHold)
            releaseAllKeys()
            return
        }
        phase = .running
    }

    private mutating func takeFromQueue() -> Piece {
        refillNext()
        let piece = next.removeFirst()
        refillNext()
        return piece
    }

    /// 7-bag: 봉지가 비면 7종을 새로 섞는다. 같은 시드면 같은 순서다.
    private mutating func refillNext() {
        while next.count < Self.nextCount {
            if bag.isEmpty { bag = Self.shuffledBag(&rng) }
            next.append(bag.removeFirst())
        }
    }

    /// Fisher-Yates. `rng.next()` 를 7 이하로 나눈 나머지의 편향은 2^64 대비 1e-19 라 판에 보이지 않는다.
    package static func shuffledBag(_ rng: inout MiniGameRandom) -> [Piece] {
        var bag = Piece.allCases
        var index = bag.count - 1
        while index > 0 {
            let pick = Int(rng.next() % UInt64(index + 1))
            bag.swapAt(index, pick)
            index -= 1
        }
        return bag
    }

    // MARK: - 판 질의

    /// 조각이 판 안에 들어가고 굳은 칸과 겹치지 않는가.
    package func fits(_ piece: ActivePiece) -> Bool {
        for cell in piece.cells {
            guard cell.column >= 0, cell.column < Self.columns, cell.row < Self.totalRows else { return false }
            guard cell.row >= 0 else { return false }
            if board[cell.row][cell.column] != nil { return false }
        }
        return true
    }

    /// T-스핀 모서리 판정용. **판 밖은 막힌 것으로 센다**(표준).
    private func isBlocked(row: Int, column: Int) -> Bool {
        guard row >= 0, row < Self.totalRows, column >= 0, column < Self.columns else { return true }
        return board[row][column] != nil
    }

    private static func bottomRow(of piece: ActivePiece) -> Int {
        piece.cells.map(\.row).max() ?? piece.row
    }

    /// 점수는 언제나 `maxScore` 에서 잘린다.
    private mutating func addScore(_ points: Int) {
        score = min(Self.maxScore, score + max(0, points))
    }
}
