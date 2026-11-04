import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 패 움직임 그리기(SPEC §5.9 '움직임') — 버림 0.15초 · 울기 0.25초 · 리치 눕기 · 동작 줄이기면 끔 ·
// TimelineView(MiniGameFrameRate, paused:) · 입력은 TimelineView 바깥 · 불투명도는 이징으로 깎지 않는다.

@MainActor
@Suite("아잉 마작 움직임 그리기")
struct V03xxMahjongMotionPlanTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func motion(_ kind: MahjongMotion.Kind, from: MahjongCompass, to: MahjongCompass, duration: TimeInterval = 0.24,
                        startedAt: Date? = nil) -> MahjongMotion {
        let toArea: MahjongMotion.Place.Area = kind == .discard ? .river : .melds
        let fromArea: MahjongMotion.Place.Area = kind == .call ? .river : .hand
        return MahjongMotion(matchID: "m", handIndex: 2, seq: 40, kind: kind, from: .init(compass: from, area: fromArea),
                             to: .init(compass: to, area: toArea), startedAt: startedAt ?? t0, duration: duration)
    }

    @Test
    func durationsAreDiscardPointOneFiveAndCallPointTwoFive() {
        // 없으면: 화면이 코어 기본 길이(0.24초) 하나로 버림·울기를 같이 그리거나, 꼬리 따라잡기(1.5초 안)로 줄인 길이를 무시해도 초록이다.
        #expect(MahjongMotionPlan.duration(motion(.discard, from: .left, to: .left)) == 0.15)
        #expect(MahjongMotionPlan.duration(motion(.call, from: .left, to: .bottom)) == 0.25)
        #expect(MahjongMotionPlan.duration(motion(.kan, from: .top, to: .top)) == 0.25)
        let tail = MahjongMotion.duration(forTailCount: 15)   // 0.1
        #expect(MahjongMotionPlan.duration(motion(.call, from: .left, to: .bottom, duration: tail)) == tail)
        #expect(MahjongMotionPlan.duration(motion(.discard, from: .left, to: .left, duration: tail)) == tail)
    }

    @Test
    func discardSlidesInFromTheOwnersHandSideAndSettlesExactly() {
        // 없으면: 버린 패가 엉뚱한 쪽(손 반대편)에서 오거나, 끝에 제자리로 안 돌아오거나(어긋난 채 멈춤), 이징이 거꾸로여도 초록이다.
        let left = motion(.discard, from: .left, to: .left)
        #expect(MahjongMotionPlan.offset(left, now: t0) == CGSize(width: -MahjongMotionPlan.travel, height: 0))
        #expect(MahjongMotionPlan.offset(motion(.discard, from: .bottom, to: .bottom), now: t0).height == MahjongMotionPlan.travel)
        #expect(MahjongMotionPlan.offset(motion(.discard, from: .top, to: .top), now: t0).height == -MahjongMotionPlan.travel)
        #expect(MahjongMotionPlan.offset(motion(.discard, from: .right, to: .right), now: t0).width == MahjongMotionPlan.travel)
        #expect(MahjongMotionPlan.offset(left, now: t0.addingTimeInterval(0.15)) == .zero)
        #expect(MahjongMotionPlan.offset(left, now: t0.addingTimeInterval(1)) == .zero)
        var last = CGFloat.infinity
        for step in 0...15 {
            let now = t0.addingTimeInterval(Double(step) * 0.01)
            let gap = abs(MahjongMotionPlan.offset(left, now: now).width)
            #expect(gap <= last)
            last = gap
            // ease-out: 자리는 이징 전 진행도보다 앞선다(끝에서 느려진다).
            #expect(MahjongMotionPlan.eased(left, now: now) >= MahjongMotionPlan.progress(left, now: now))
        }
    }

    @Test
    func callComesFromTheGiverAndKanOnlyMovesAClosedKan() {
        // 없으면: 상가(왼쪽)에게서 운 패가 오른쪽에서 날아오거나, 가깡(옛 퐁이 커짐)에 엉뚱한 마지막 묶음이 움직여도 초록이다.
        let call = MahjongMotionPlan.startOffset(motion(.call, from: .left, to: .bottom))
        #expect(call.width < 0 && call.height < 0, "상가 쪽(왼쪽 위)에서 와야 한다")
        #expect(abs((call.width * call.width + call.height * call.height).squareRoot() - MahjongMotionPlan.travel) < 0.001)
        let pon = MahjongWireMeld(type: "pon", tiles: MahjongTiles.parse("555p") ?? [])
        let ankan = MahjongWireMeld(type: "ankan", tiles: MahjongTiles.parse("1111z") ?? [])
        #expect(MahjongMotionPlan.movesNewestMeld(motion(.call, from: .left, to: .bottom), compass: .bottom, melds: [pon]))
        #expect(!MahjongMotionPlan.movesNewestMeld(motion(.call, from: .left, to: .bottom), compass: .top, melds: [pon]))
        #expect(MahjongMotionPlan.movesNewestMeld(motion(.kan, from: .top, to: .top), compass: .top, melds: [pon, ankan]))
        #expect(!MahjongMotionPlan.movesNewestMeld(motion(.kan, from: .top, to: .top), compass: .top, melds: [ankan, pon]))
        #expect(!MahjongMotionPlan.movesNewestMeld(motion(.discard, from: .top, to: .top), compass: .top, melds: [pon]))
        #expect(!MahjongMotionPlan.movesNewestMeld(motion(.call, from: .left, to: .bottom), compass: .bottom, melds: []))
    }

    @Test
    func onlyTheRiichiTileLiesDown() throws {
        // 없으면: 리치 선언패가 눕지 않고 그냥 가로로 나타나거나, 보통 버림패까지 기울어도 초록이다.
        let m = motion(.discard, from: .right, to: .right)
        let tile = try #require(MahjongTile(id: 40))
        let riichi = MahjongDiscard(tile: tile, tsumogiri: false, riichi: true, taken: false)
        let plain = MahjongDiscard(tile: tile, tsumogiri: false, riichi: false, taken: false)
        #expect(MahjongMotionPlan.tilt(m, discard: riichi, now: t0) == -90)
        #expect(MahjongMotionPlan.tilt(m, discard: riichi, now: t0.addingTimeInterval(0.15)) == 0)
        let mid = MahjongMotionPlan.tilt(m, discard: riichi, now: t0.addingTimeInterval(0.05))
        #expect(mid > -90 && mid < 0)
        #expect(MahjongMotionPlan.tilt(m, discard: plain, now: t0) == 0)
        #expect(MahjongMotionPlan.tilt(m, discard: nil, now: t0) == 0)
    }

    @Test
    func nothingMovesUnderReduceMotionOtherHandsOrAfterTheEnd() {
        // 없으면: 동작 줄이기에도 패가 미끄러지거나, 다른 판·다른 국의 움직임을 지금 판에 그리거나, 끝난 움직임에 프레임이 계속 돌아도 초록이다.
        let m = motion(.discard, from: .left, to: .left)
        let mid = t0.addingTimeInterval(0.05)
        #expect(MahjongMotionPlan.active(m, matchID: "m", handIndex: 2, now: mid, reduceMotion: false) == m)
        #expect(MahjongMotionPlan.active(m, matchID: "m", handIndex: 2, now: mid, reduceMotion: true) == nil)
        #expect(MahjongMotionPlan.active(m, matchID: "other", handIndex: 2, now: mid, reduceMotion: false) == nil)
        #expect(MahjongMotionPlan.active(m, matchID: "m", handIndex: 3, now: mid, reduceMotion: false) == nil)
        #expect(MahjongMotionPlan.active(m, matchID: "m", handIndex: 2, now: t0.addingTimeInterval(0.16), reduceMotion: false) == nil)
        #expect(MahjongMotionPlan.active(nil, matchID: "m", handIndex: 2, now: mid, reduceMotion: false) == nil)
    }

    @Test
    func framesUseTheMiniGameRateAndInputStaysOutsideAndOpacityIsUntouched() throws {
        // 없으면: 1/60 을 박아 120Hz·비배수 주사율에서 저더가 나거나, 멈춤 없이 늘 돌거나, 손패 누름·호버가 TimelineView 안으로 들어가
        // (프레임마다 제스처가 새로 생겨) 누름을 잃거나, 이징 진행도로 불투명도를 깎아도 초록이다.
        let motion = try mjMotionSource("MahjongPanelMotion.swift")
        #expect(motion.contains("TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval( "
                                + "forRefreshRate: MiniGameFrameRateMonitor.shared.refreshHz), paused: running == nil))"))
        #expect(!motion.contains("1.0 / 60") && !motion.contains("1/60"))
        #expect(!motion.contains(".opacity("), "움직임이 불투명도를 건드린다")
        let hand = try mjMotionSource("MahjongPanelHand.swift")
        let melds = try #require(mjBlock(hand, after: "private func melds(after x: CGFloat) -> some View {"))
        #expect(melds.contains("MahjongMotionFrames("))
        for input in ["gesture(", "onTapGesture", "onContinuousHover", "Button"] { #expect(!melds.contains(input), "\(input)") }
        let body = try #require(mjBlock(hand, after: "struct MahjongHandView: View {"))
        let frames = try #require(body.range(of: "melds(after:"))
        let tap = try #require(body.range(of: ".gesture(SpatialTapGesture()"))
        #expect(frames.upperBound < tap.lowerBound, "손패 누름이 움직임 그릇 바깥(뒤)에 붙어 있어야 한다")
        let table = try mjMotionSource("MahjongPanelTable.swift")
        let felt = try #require(mjBlock(table, after: "struct MahjongFeltView: View {"))
        #expect(felt.contains("MahjongMotionFrames("))
        for input in ["gesture(", "onTapGesture", "onContinuousHover", "Button", ".opacity("] { #expect(!felt.contains(input), "\(input)") }
    }
}

private let mjMotionSourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Sources/check")

/// 소스(주석 걷고 공백 접음).
private func mjMotionSource(_ name: String) throws -> String {
    let raw = try String(contentsOf: mjMotionSourceDir.appendingPathComponent(name), encoding: .utf8)
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "//") { return line[..<range.lowerBound] }
        return line
    }
    return lines.joined(separator: " ").split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
}

/// `marker`(여는 중괄호로 끝난다) 뒤 짝 맞는 중괄호까지의 본문.
private func mjBlock(_ source: String, after marker: String) -> String? {
    guard let start = source.range(of: marker) else { return nil }
    var depth = 1
    var index = start.upperBound
    while index < source.endIndex {
        let ch = source[index]
        if ch == "{" { depth += 1 }
        if ch == "}" { depth -= 1; if depth == 0 { return String(source[start.upperBound..<index]) } }
        index = source.index(after: index)
    }
    return nil
}
