import Foundation
import SwiftUI

// B3: `MiniGameTimingBar.swift` 에서 화면(AppKit·뷰)과 무관한 규칙·값 타입만 코어로 옮겼다.
// 설명 주석의 큰 줄기(왜 이 값인가)는 원래 파일 머리에 남아 있다.

package struct TimingBarGame: Equatable, Sendable {
    package enum Phase: Equatable, Sendable {
        /// 시작 전. 루프는 멈춰 있다.
        case ready
        /// 라운드 진행 중. `t` 는 라운드 시작부터 흐른 초.
        case running(round: Int, t: TimeInterval)
        /// 정지 직후 결과 표시. `hold` 가 0 이 되면 다음 라운드(또는 finished)로 스스로 넘어간다.
        case roundResult(round: Int, score: Int, hold: TimeInterval)
        /// 10라운드 끝. 클릭하면 바로 새 판.
        case finished(total: Int)
    }

    /// 정지 순간의 판정 등급. **점수에서만 나오는 순수 함수**다 — 그림이 자기 기준으로 등급을 다시 세면
    /// 배점이 바뀔 때 표시와 점수가 조용히 갈린다. 색과 함께 라벨을 들고 다니는 이유는 접근성이다:
    /// 색만으로 결과를 알리지 않는다(색각 이상에서도 "완벽!"이 글자로 온다).
    package enum Verdict: Equatable, Sendable {
        case perfect, great, good, close, miss

        package var label: String {
            switch self {
            case .perfect: "완벽!"
            case .great: "훌륭!"
            case .good: "좋아"
            case .close: "아슬"
            case .miss: "빗나감"
            }
        }

        /// 등급 색. **무대를 타지 않는다** — 무대는 2라운드마다 바뀌는데 판정 색까지 따라 바뀌면
        /// "이 색이 몇 점인지"를 라운드마다 새로 배워야 한다. 100점만 테마에 없는 금색을 쓴다
        /// (working 초록을 90점대와 나눠 쓰면 완벽과 훌륭이 한눈에 구별되지 않는다).
        package var tint: Color {
            switch self {
            case .perfect: Self.perfectGold
            case .great: CheckTheme.working
            case .good: CheckTheme.accent
            case .close: CheckTheme.pending
            case .miss: CheckTheme.danger
            }
        }

        /// 등급 글리프(라운드 스트립 칸 안). **색만으로는 말하지 않는다** — 칸이 22pt 라 숫자는 못 넣지만
        /// 채운 정도(꽉 참 → 테두리만 → ×)는 색을 못 보는 눈에도 순서로 읽힌다(2026-09-10 지적).
        package var glyph: TimingBarSegmentGlyph {
            switch self {
            case .perfect: .star
            case .great: .disc
            case .good: .diamond
            case .close: .ring
            case .miss: .cross
            }
        }

        /// 무대 glow 5종의 공통분모에 가까운 금색(새벽·노을 glow 계열).
        private static let perfectGold = Color(red: 1.00, green: 0.84, blue: 0.52)
    }

    package static let roundCount = 10
    /// 라운드 결과("+N")를 보여 주는 시간.
    package static let resultHold: TimeInterval = 0.6
    /// 한 걸음의 상한. 앱 정지·팝오버 재표시 뒤 첫 프레임이 몇 초를 한꺼번에 흘리지 않게.
    package static let maxStep: TimeInterval = 1.0 / 30.0

    package private(set) var phase: Phase = .ready
    package private(set) var roundScores: [Int] = []
    private var targetCenter: Double = 0.5
    private var targetWidthValue: Double = 0.30
    /// 정지한 자리(결과 표시 동안 마커를 얼려 둔다).
    private var stoppedPosition: Double?
    /// 마지막 정지가 목표 안이었는지(마커 색). 시작 전·무효 뒤엔 nil.
    package private(set) var lastHit: Bool?
    private var rng: MiniGameRandom

    package init(seed: UInt64) {
        rng = MiniGameRandom(seed: seed)
    }

    // 난수 상태는 비교하지 않는다 — "같은 화면"인지가 관심사이고, MiniGameRandom 은 Equatable 이 아니다.
    package static func == (lhs: TimingBarGame, rhs: TimingBarGame) -> Bool {
        lhs.phase == rhs.phase && lhs.roundScores == rhs.roundScores
            && lhs.targetCenter == rhs.targetCenter && lhs.targetWidthValue == rhs.targetWidthValue
            && lhs.stoppedPosition == rhs.stoppedPosition && lhs.lastHit == rhs.lastHit
    }

    // MARK: 읽기

    /// 현재(또는 마지막) 라운드 번호. 시작 전 0.
    package var round: Int {
        switch phase {
        case .ready: 0
        case .running(let round, _), .roundResult(let round, _, _): round
        case .finished: Self.roundCount
        }
    }

    package var total: Int { roundScores.reduce(0, +) }

    /// 연속으로 목표 구간에 넣은 횟수. 배점상 구간 안이면 70~100, 밖이면 0 뿐이라 "70점 이상"이 곧 "명중"이다.
    /// **표시 전용이다.** 총점(`total`)에 절대 더하지 마라 — 서버 상한 1000점(= 100 × 10라운드)을 넘겨
    /// 업로드가 거부되고, 콤보 보너스가 붙은 기록과 안 붙은 기록이 한 순위표에 섞여 의미가 깨진다.
    package var combo: Int {
        var streak = 0
        for score in roundScores.reversed() {
            guard score >= 70 else { break }
            streak += 1
        }
        return streak
    }

    /// 루프가 돌아야 하는 상태(진행 중 또는 결과 표시 중).
    package var isPlaying: Bool {
        switch phase {
        case .running, .roundResult: true
        case .ready, .finished: false
        }
    }

    /// 트랙 위 마커 위치 0…1. 결과 표시 중엔 정지한 자리에 얼어 있다.
    package var markerPosition: Double {
        switch phase {
        case .running(let round, let t): Self.markerPosition(t: t, period: Self.period(round: round))
        case .roundResult: stoppedPosition ?? 0
        case .ready, .finished: 0
        }
    }

    package var target: (center: Double, width: Double) { (targetCenter, targetWidthValue) }

    // MARK: 순수 함수(스펙 상수)

    /// 라운드 주기(초). 갈수록 빨라지되 0.42 밑으로는 안 내려간다.
    /// r1 1.10 · r5 0.80 · r10 0.425. 2026-09-08 실기에서 "너무 쉽다"는 지적을 받아 1.40/0.09 에서 올렸다.
    package static func period(round: Int) -> Double {
        max(0.42, 1.10 - 0.075 * Double(round - 1))
    }

    /// 목표 구간 폭(트랙 길이 = 1). 갈수록 좁아지되 0.07 밑으로는 안 내려간다.
    /// r1 0.24 · r5 0.164 · r10 0.07(하한). 종전 0.30/0.022 보다 처음부터 좁고 끝은 더 좁다.
    package static func targetWidth(round: Int) -> Double {
        max(0.07, 0.24 - 0.019 * Double(round - 1))
    }

    /// 삼각파 0→1→0. t=0 에서 0, t=T/2 에서 1, t=T 에서 다시 0.
    /// 해석식이라 **과거·미래 시각도 그냥 계산된다** — 마커 잔상(t − k/60)이 이 성질에 기대고 있다.
    package static func markerPosition(t: Double, period: Double) -> Double {
        let x = t / period
        return 2 * abs(x - (x + 0.5).rounded(.down))
    }

    /// 목표 중심에서의 거리 d(= |p − c| / (w/2)) 를 점수로.
    /// 라운드 점수(사용자 결정 2026-09-08): 목표 구간 **안**이면 정중앙 100 → 가장자리 70 (정확도 비례), **밖이면 0**.
    /// 구간 밖 부분 점수는 없다 — "들어왔느냐"가 먼저고, 그 다음이 정확도다.
    package static func roundScore(distance d: Double) -> Int {
        guard d <= 1 else { return 0 }
        return 100 - Int((30 * d).rounded())
    }

    /// 점수 → 판정 등급. 경계는 100 / 90 / 80 / 70 이고 그 밑은 전부 빗나감(배점상 0 뿐이다).
    package static func verdict(score: Int) -> Verdict {
        if score >= 100 { return .perfect }
        if score >= 90 { return .great }
        if score >= 80 { return .good }
        if score >= 70 { return .close }
        return .miss
    }

    // MARK: 전이

    package mutating func step(dt: TimeInterval) {
        let dt = min(max(dt, 0), Self.maxStep)
        switch phase {
        case .running(let round, let t):
            phase = .running(round: round, t: t + dt)
        case .roundResult(let round, let score, let hold):
            let remaining = hold - dt
            if remaining > 0 {
                phase = .roundResult(round: round, score: score, hold: remaining)
            } else if round >= Self.roundCount {
                phase = .finished(total: total)
            } else {
                startRound(round + 1)
            }
        case .ready, .finished:
            break
        }
    }

    /// 클릭. 시작 전/끝난 뒤엔 새 판, 진행 중엔 정지. 결과 표시 중엔 무시(두 번 눌러 다음 라운드를 잃지 않게).
    package mutating func tap() {
        switch phase {
        case .ready, .finished:
            roundScores = []
            lastHit = nil
            stoppedPosition = nil
            startRound(1)
        case .running(let round, let t):
            let p = Self.markerPosition(t: t, period: Self.period(round: round))
            let d = abs(p - targetCenter) / (targetWidthValue / 2)
            let score = Self.roundScore(distance: d)
            roundScores.append(score)
            lastHit = d <= 1
            stoppedPosition = p
            phase = .roundResult(round: round, score: score, hold: Self.resultHold)
        case .roundResult:
            break
        }
    }

    /// 판 무효(팝오버 닫힘·패널 전환). 점수는 버리고 시작 전으로.
    package mutating func invalidate() {
        phase = .ready
        roundScores = []
        lastHit = nil
        stoppedPosition = nil
    }

    private mutating func startRound(_ round: Int) {
        let width = Self.targetWidth(round: round)
        targetWidthValue = width
        targetCenter = rng.uniform(width / 2 + 0.05, 1 - width / 2 - 0.05)
        stoppedPosition = nil
        phase = .running(round: round, t: 0)
    }
}

/// 라운드 스트립 칸 안에 그리는 등급 형태. 색을 못 보는 눈에도 등급이 남게 하는 두 번째 채널이다.
package enum TimingBarSegmentGlyph {
    case star, disc, diamond, ring, cross
}
