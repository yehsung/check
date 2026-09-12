import Foundation

/// 한 상태(frontIdle / sideIdle / sideWalk)의 프레임 재생 시계 — **순수 함수**다.
///
/// 왜 시계를 안 들고 있나: 호출부가 elapsed 를 준다. 그래야 테스트가 시간을 지배하고(경계·2바퀴·끝을 정확히 찍는다),
/// 렌더 프레임률(유휴 6fps ↔ 활성 60fps)이 바뀌어도 재생 결과가 달라지지 않는다. SceneKit 의
/// `SCNAction.sequence` 로 프레임을 굽지 않는 이유도 같다 — 렌더 정지(β2 `renderSuspended`) 중에 액션이
/// 밀려 쌓였다가 재개 순간 한꺼번에 튀는 그 증상을 이 갈래에 다시 들이지 않는다.
struct SpriteFramePlayer: Equatable, Sendable {
    /// 프레임 i 의 **끝 시각**(초, 상태 시작 기준). 누적은 정수 ms 로 하고 마지막에 나눈다 —
    /// 0.1 을 실수로 더해 가면 경계가 0.30000000000000004 가 돼 "정확히 경계" 테스트가 흔들린다.
    private let frameEnds: [TimeInterval]
    private let frameCount: Int
    private let loops: Bool

    /// 한 바퀴 길이(초). durationsMs 합.
    let totalDuration: TimeInterval

    init(state: CharacterManifest.State) {
        var ends: [TimeInterval] = []
        ends.reserveCapacity(state.frames.count)
        var accumulatedMs = 0
        for (index, _) in state.frames.enumerated() {
            let ms = index < state.durationsMs.count ? max(0, state.durationsMs[index]) : 0
            accumulatedMs += ms
            ends.append(TimeInterval(accumulatedMs) / 1000)
        }
        self.frameEnds = ends
        self.frameCount = state.frames.count
        self.loops = state.loop
        self.totalDuration = TimeInterval(accumulatedMs) / 1000
    }

    /// 상태 시작부터 `elapsed` 초가 지났을 때의 프레임 인덱스.
    ///
    /// 경계 규약은 **반열린 구간 [시작, 끝)** — elapsed 가 정확히 프레임 경계면 **다음** 프레임이다.
    /// 루프면 한 바퀴로 접고(2바퀴째 0초 = 0번), 아니면 마지막 프레임에서 멈춘다. 음수는 0.
    func frameIndex(elapsed: TimeInterval) -> Int {
        guard frameCount > 0 else { return 0 }
        let last = frameCount - 1
        // 총 길이 0(전부 0ms 인 1프레임 정지 상태)에서 나눗셈을 하면 NaN 이 나와 인덱스가 통째로 망가진다.
        guard totalDuration > 0 else { return 0 }
        guard elapsed.isFinite else { return 0 }
        guard elapsed > 0 else { return 0 }

        var t = elapsed
        if loops {
            t = t.truncatingRemainder(dividingBy: totalDuration)
            if t < 0 { t += totalDuration }   // 방어(elapsed > 0 이라 도달하지 않는다)
        } else if t >= totalDuration {
            return last
        }
        for index in 0...last where t < frameEnds[index] {
            return index
        }
        // 0ms 짜리 꼬리 프레임(예: [100ms, 0ms])이면 여기로 떨어진다 — 마지막이 정답.
        return last
    }
}
