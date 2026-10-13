import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 0.3.51 — 오목 **내 차례 마지막 3초**의 판 테두리 빛(폰). 판정·세기·그림은 코어 `GomokuTurnWarning`(맥 `GomokuBoardTimeWarning` 과
// 한 벌 — 맥 스위트 `V0351GomokuLowTimeGlowTests` 가 판정 경계와 그림을 픽셀로 잰다)이고, 폰은 잎 뷰 `GamesGomokuBoardTimeWarning` 이
// 시계를 읽어 넘기기만 한다.
//
// ── 잴 수 있는 길이 둘뿐이다 ──
// 대국 화면은 `#if os(iOS)` 안이라 **맥 스위트가 컴파일조차 못 한다**(저장소 메모 '폰 뷰는 맥 스위트가 못 본다' — 컴파일 그물은
// `ios/scripts/build-sim.sh` 하나다). 그래서 둘로 나눠 잰다:
//   1. **문구 계약**(값) — `GomokuPhoneText` 는 `#if` 밖이다. 링 글자가 "3초"가 되는 순간과 빛이 켜지는 순간이 같은지.
//   2. **소스 계약**(글자) — 잎이 판 위에 얹히는 자리 · 시계의 출처(데모 고정 시계 · 테스트 조작 시계) · 입력과 보이스오버를 안 가리는지.
// 주석은 반드시 걷어낸다(`stripComments` — 하우스 규칙). 안 걷으면 설명문에 적은 이름만으로 초록이 된다.
@Suite struct GamesGomokuLowTimeGlowContractTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let matchPath = "Sources/CheckMobileKit/Games/GamesGomokuMatch.swift"

    // MARK: - 1. 문구 계약

    /// 없으면: 폰 링이 "4초"인데 판이 켜지거나 "3초"가 됐는데 안 켜져도(문턱을 폰에서 따로 적어 어긋남), 0초에 꺼져도 초록이다.
    @Test("링 글자가 3초가 되는 순간 빛이 켜지고 0초에도 켜져 있다")
    func ringTextAndGlowAgreeOnThreeSeconds() {
        for (remaining, ring, on) in [(3.01, "4초", false), (3.0, "3초", true), (2.01, "3초", true), (0.4, "1초", true), (0.0, "0초", true)] {
            #expect(GomokuPhoneText.remaining(remaining) == ring)
            #expect(GomokuTurnWarning.isActive(remaining: remaining) == on, "\(remaining)초(링 \(ring))의 빛이 \(on ? "꺼졌다" : "켜졌다")")
        }
        // 마감이 없는 순간(AI 차례·멈춘 AI 시계)은 링이 `?? 0` 으로 0초를 그려도 빛은 꺼짐이다 — 입력이 nil 그대로 와야 한다.
        #expect(!GomokuTurnWarning.isActive(remaining: nil))
    }

    // MARK: - 2. 소스 계약

    /// 없으면: 빛이 판 뷰(`GamesGomokuPlayBoard` — 시계가 없다) 안에 들어가 `Date()` 를 읽어 데모 고정 시계·테스트 조작 시계를 무시하거나,
    /// 그림자 **앞**에 얹혀 5Hz 틱마다 그림자를 다시 굽거나, 탭(미리보기·착수)·보이스오버 칸 요소를 가리거나, 멈춘 TimelineView 의
    /// 마지막 그림(빛)을 차례가 넘어간 뒤에도 들고 있거나, 링처럼 `?? 0` 을 써서 AI 차례에 켜져도 폰 스위트는 초록이다.
    @Test("빛 잎은 그림자 뒤 판 위에 얹히고 폰 시계로 읽고 입력·보이스오버를 가리지 않는다")
    func glowLeafSitsOverTheBoardReadsThePhoneClockAndStaysOutOfInput() throws {
        let code = try Self.code(Self.matchPath)

        // 판 한 장(board(side:)) — 그림자 뒤 · 가운데 정렬 앞에 잎이 얹힌다.
        let board = try #require(Self.block(after: "private func board(side: CGFloat", in: code), "board(side:) 를 못 찾았다")
        let shadow = try #require(board.range(of: ".shadow("), "판 그림자가 없다")
        let overlay = try #require(board.range(of: ".overlay { GamesGomokuBoardTimeWarning(store: store) }"), "판에 빛 잎이 안 얹혔다")
        let centre = try #require(board.range(of: ".frame(maxWidth: .infinity)"))
        #expect(shadow.upperBound <= overlay.lowerBound, "빛 잎이 그림자 앞에 얹혔다 — 5Hz 틱마다 그림자를 다시 굽는다")
        #expect(overlay.upperBound <= centre.lowerBound, "빛 잎이 화면 폭 전체(가운데 정렬 틀)에 얹혔다 — 판 밖까지 칠한다")

        // 잎 본체.
        let leaf = try #require(Self.block(after: "struct GamesGomokuBoardTimeWarning: View", in: code), "빛 잎이 없다")
        for required in ["TimelineView(.animation(minimumInterval: 0.2, paused: !gomoku.isWindowVisible || !watches))",
                         "gomoku.remainingSeconds(now: store.context.clock.now())",
                         "GomokuTurnWarning.isActive(remaining: remaining)", "GomokuTurnWarning.intensity(remaining: remaining)",
                         "GomokuTurnWarning.drawEdgeGlow(", ".allowsHitTesting(false)", ".accessibilityHidden(true)"] {
            #expect(leaf.contains(required), "빛 잎에 `\(required)` 가 없다")
        }
        // 켜짐 판정은 두 번 — TimelineView 를 멈추는 데 한 번, 그 **본문에서** 한 번 더(멈춘 TimelineView 는 마지막 그림을 들고 있다).
        #expect(leaf.components(separatedBy: "GomokuTurnWarning.watchesMyClock(gomoku.match)").count - 1 == 2, "본문에서 차례를 다시 안 본다")
        let timeline = try #require(leaf.range(of: "TimelineView("))
        let read = try #require(leaf.range(of: "gomoku.remainingSeconds("))
        let recheck = try #require(leaf.range(of: "GomokuTurnWarning.watchesMyClock(gomoku.match)", options: .backwards))
        #expect(timeline.lowerBound < read.lowerBound && timeline.lowerBound < recheck.lowerBound, "시계·차례를 TimelineView 밖에서 읽는다")
        for forbidden in ["?? 0", "Date()", "context.date", ".shadow(", ".blur(", "repeatForever", "withAnimation", ".animation(.",
                          "drawLayer", "addFilter"] {
            #expect(!leaf.contains(forbidden), "빛 잎에 `\(forbidden)` 이 있다")
        }

        // 잎은 대국 판 **한 곳**에만 선다 — 결과 판·관전 판·판 뷰 자체에는 없다(관전자에게는 빛이 없다).
        #expect(code.components(separatedBy: "GamesGomokuBoardTimeWarning(").count - 1 == 1, "빛 잎이 대국 판 말고 다른 자리에도 섰다")
        for other in ["Sources/CheckMobileKit/Games/GamesGomokuWatch.swift", "Sources/CheckMobileKit/Games/GamesGomokuBoardCanvas.swift"] {
            let text = try Self.code(other)
            #expect(!text.contains("GomokuTurnWarning") && !text.contains("GamesGomokuBoardTimeWarning"), "\(other) 에 빛이 들어왔다")
        }
    }

    // MARK: - 도우미

    /// 주석을 걷어낸 소스(하우스 규칙 — `IntegrationContractTests.code(_:)` 와 같은 길).
    static func code(_ relative: String) throws -> String {
        stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    /// `needle` 뒤 첫 `{` 부터 짝이 맞는 `}` 앞까지. 문자열 리터럴 안의 중괄호는 세지 않는다 — 읽는 소스에 그런 리터럴이 없다.
    static func block(after needle: String, in code: String) -> String? {
        guard let hit = code.range(of: needle), let open = code[hit.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = open
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[code.index(after: open)..<i]) }
            }
            i = code.index(after: i)
        }
        return nil
    }
}
