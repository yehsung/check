import Foundation
import Observation
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 차례 시계가 3~4초씩 끊겨 줄던 일(대표 11-10 "초 줄어드는게 막 3~4초 단위로 끊기면서 줄어들던데").
// 원인: 온라인 판의 남은 초는 `서버 마감 − 서버 보정 시각`(시계로 흐르는 값)인데, 링을 판 화면 본문에서 읽었다. SwiftUI 는 본문을
// **관찰 값이 바뀔 때만** 다시 그리므로, 링은 판 조회(3초 박자 + 왕복)가 판 상태를 새로 쓸 때만 바뀌었다 — 30 → 27 → 23 … .
// 고침: 오목 `GomokuTurnClock` 처럼 시계를 **잎 뷰**(`AlkkagiTurnClock`) 안 TimelineView(0.2초)에서만 읽는다. 앱만 — 서버는 그대로.

private final class AlkClockFlag: @unchecked Sendable { var fired = false }

/// `//` · `/* */` 주석을 걷는다(설명 글에 든 낱말로 초록 · 빨강이 갈리지 않게).
private func alkClockStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; i += 1 }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; i += 1
        } else if c == "/", next == "*" {
            inBlock = true; i += 1
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        i += 1
    }
    return out
}

private func alkClockSource(_ name: String) throws -> String {
    let url = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/\(name)")
    return alkClockStripped(try String(contentsOf: url, encoding: .utf8))
}

/// `from` 부터 그 뒤 첫 `to` 직전까지(없으면 nil).
private func alkClockRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

@MainActor
@Suite("1:1 알까기 차례 시계 — 1초씩 줄어든다")
struct V03xxAlkkagiTurnClockTests {
    /// 재현: 조회 응답 없이 3초가 흐르면 남은 초 **값**은 30 → 27 로 줄지만, 관찰 값은 하나도 안 바뀐다 —
    /// 본문에서 읽는 링은 그동안 다시 그려지지 않는다(화면 걸음 `tick` 도 온라인 조준 중엔 관찰 값을 건드리지 않는다).
    /// 다음 판 조회 응답(판 상태를 새로 씀)이 와야 깬다 = 3초 박자 + 왕복마다 한 번.
    @Test func 온라인_판_남은_초는_시계로만_흐르고_관찰_값이_아니다() {
        let clock = AKClock()
        let store = AlkkagiOnlineStore(clock: { clock.date })
        store.me = AK.black
        store.state = AK.match(phase: .aiming, current: .black)
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.attachOnline(store)
        var now = 10.0
        model.tick(now: now)
        model.tick(now: now + 1.0 / 60)
        now += 1.0 / 60
        #expect(abs(model.remainingSeconds - 30) < 0.05)

        let flag = AlkClockFlag()
        withObservationTracking({ _ = model.remainingSeconds }, onChange: { flag.fired = true })
        for _ in 0..<(60 * 3) {
            now += 1.0 / 60
            clock.advance(1.0 / 60)
            model.tick(now: now)
        }
        #expect(abs(model.remainingSeconds - 27) < 0.05, "값은 흐른다 \(model.remainingSeconds)")
        #expect(!flag.fired, "시계만 흘렀는데 관찰 값이 바뀌었다 — 이 시험의 전제(본문 링은 멈춘다)가 바뀌었다")

        // 판 조회 응답 = 판 상태를 새로 쓴다 → 그제야 깬다.
        store.state = AK.match(phase: .aiming, current: .black, revision: 8)
        #expect(flag.fired)
    }

    /// 숨겨 놓기(배치 30초)도 같은 길이다 — 같은 값을 같은 링이 그린다.
    @Test func 숨겨_놓기_30초도_같은_시계() {
        let clock = AKClock()
        let store = AlkkagiOnlineStore(clock: { clock.date })
        store.me = AK.black
        store.state = AK.match(phase: .placing)
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.attachOnline(store)
        model.tick(now: 10)
        let flag = AlkClockFlag()
        withObservationTracking({ _ = model.remainingSeconds }, onChange: { flag.fired = true })
        clock.advance(2)
        model.tick(now: 12)
        #expect(abs(model.remainingSeconds - 28) < 0.05 && !flag.fired)
    }

    /// 고침의 모양: 판 화면은 남은 초를 읽지 않고, 잎 `AlkkagiTurnClock` 이 TimelineView(0.2초) 틱 안에서만 읽는다.
    @Test func 남은_초는_잎_뷰의_TimelineView_안에서만_읽는다() throws {
        let file = try alkClockSource("AlkkagiGameView.swift")
        let views = try #require(alkClockRegion(file, from: "struct AlkkagiGameView: View {", to: "final class AlkkagiLocalModel"))
        let leaf = try #require(alkClockRegion(file, from: "struct AlkkagiTurnClock: View {", to: "struct AlkkagiStoneCountCard: View {"),
                                "차례 시계 잎 뷰가 없다")
        let timeline = try #require(leaf.range(of: "TimelineView(.animation(minimumInterval: 0.2, paused: !model.clockTicks))"),
                                    "잎에 0.2초 TimelineView 가 없다")
        let read = try #require(leaf.range(of: "model.remainingSeconds"), "잎이 남은 초를 안 읽는다")
        #expect(timeline.lowerBound < read.lowerBound, "잎이 TimelineView 밖에서 남은 초를 읽는다")
        #expect(leaf.contains("BoardGameClockRing(remaining: remaining, duration: 30, tint: AlkkagiLocalModel.clockTint(remaining))"))
        // 잎을 뺀 나머지 뷰(판 화면 · 오른쪽 열 · 카드들)는 남은 초도, 그 초로 고르는 시계 색도 읽지 않는다.
        let outside = views.replacingOccurrences(of: leaf, with: "")
        #expect(outside.count < views.count)
        #expect(!outside.contains("remainingSeconds"), "잎 밖 뷰가 남은 초를 읽는다 — 관찰 값이 바뀔 때만 다시 그려진다")
        #expect(!outside.contains("clockTint"), "잎 밖 뷰가 시계 색(남은 초)을 읽는다")
        #expect(outside.contains("AlkkagiTurnClock(model: model)"), "선수 카드가 잎 시계를 안 쓴다")
    }

    @Test func 시계_틱은_온라인_판이고_창이_보일_때만() {
        let local = AlkkagiLocalModel()
        #expect(!local.clockTicks, "연습 판은 모델 틱(5Hz)이 다시 그린다")
        let store = AlkkagiOnlineStore(clock: { Date(timeIntervalSince1970: AK.nowMs / 1_000) })
        let model = AlkkagiLocalModel()
        model.attachOnline(store)
        #expect(!model.clockTicks)
        store.windowDidShow()
        #expect(model.clockTicks)
        store.windowDidHide()
        #expect(!model.clockTicks)
        store.reset()
    }

    @Test func 시계_색_문턱은_그대로() {
        #expect(AlkkagiLocalModel.clockTint(0) == CheckTheme.danger)
        #expect(AlkkagiLocalModel.clockTint(5) == CheckTheme.danger)
        #expect(AlkkagiLocalModel.clockTint(5.01) == CheckTheme.pending)
        #expect(AlkkagiLocalModel.clockTint(10) == CheckTheme.pending)
        #expect(AlkkagiLocalModel.clockTint(10.01) == CheckTheme.working)
    }

    /// 관전 시계: 1초 틱은 화면 프레임에 맞춰 1.0x초마다라 올림 숫자가 가끔 2씩 건너뛴다 — 0.2초로.
    @Test func 관전_시계도_0_2초_틱() throws {
        let file = try alkClockSource("AlkkagiPanelWatch.swift")
        let leaf = try #require(alkClockRegion(file, from: "private struct AlkkagiWatchClock: View {", to: "private struct AlkkagiSpectateBoard"))
        #expect(leaf.contains("TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible))"))
        #expect(!leaf.contains("minimumInterval: 1,"))
    }
}
