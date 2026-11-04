import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 '처음이에요' 4장(SPEC §5.7 · UX:441) — 첫 연습판을 시작할 때 한 번, 다 보면 다시 안 뜬다, [규칙]에서 다시 본다.
// 값은 시험 전용 스위트에만 쓴다(표준 스위트에 '봤음'이 새면 사람의 첫 안내가 사라진다).

@MainActor
@Suite("아잉 마작 처음이에요 안내")
struct V03xxMahjongFirstTimeGuideTests {
    private let launch = MahjongPracticeLaunch(format: .hanchan, timed: true)

    @Test(.gomokuDefaultsCleanup)
    func firstPracticeShowsTheGuideOnceThenStartsThatPractice() {
        // 없으면: 첫 [연습 시작]이 안내 없이 판을 열거나, 다 본 뒤에도 매번 안내가 뜨거나, 안내 끝에 고른 판(반장전·실전처럼)이
        // 아닌 판이 열려도 초록이다.
        let defaults = GomokuTestDefaults.make("v03xx-mahjong-guide")
        #expect(MahjongFirstTimeGuide.overlayBeforePractice(launch, defaults: defaults) == .firstTime(page: 0, launch: launch))
        var started: [MahjongPracticeLaunch] = []
        MahjongFirstTimeGuide.finish(launch: launch, defaults: defaults) { started.append($0) }
        #expect(started == [launch], "안내 끝에 고른 판이 열리지 않았다")
        #expect(MahjongFirstTimeGuide.hasSeen(defaults))
        #expect(MahjongFirstTimeGuide.overlayBeforePractice(launch, defaults: defaults) == nil, "다 본 뒤에도 안내가 또 뜬다")
        // 기준선(결과가 다른): 새 스위트는 다시 안내를 띄운다 — '늘 nil' 인 구현은 위 첫 줄에서 빨갛다.
        let fresh = GomokuTestDefaults.make("v03xx-mahjong-guide-fresh")
        #expect(MahjongFirstTimeGuide.overlayBeforePractice(launch, defaults: fresh) != nil)
        // 표준 스위트에는 아무것도 안 쓴다.
        #expect(UserDefaults.standard.object(forKey: MahjongFirstTimeGuide.seenKey) == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    func reopeningFromRulesDoesNotStartAPractice() {
        // 없으면: [규칙]에서 다시 본 안내를 닫을 때 연습판이 저절로 열려(루비 판 로비에서도) 초록이다.
        let defaults = GomokuTestDefaults.make("v03xx-mahjong-guide-reopen")
        var started = 0
        MahjongFirstTimeGuide.finish(launch: nil, defaults: defaults) { _ in started += 1 }
        #expect(started == 0)
        #expect(MahjongFirstTimeGuide.hasSeen(defaults), "건너뛰기·다시 보기 닫기도 '봤음'이다")
    }

    @Test
    func fourPagesFollowTheRulesTextAndEachHasAnExampleHand() {
        // 없으면: 안내가 네 장이 아니거나(UX:441 — 목표 · 역 · 버리기·울기 · 리치) 규칙 창과 다른 글(두 벌)이거나, 그림 없는 장이 있어도 초록이다.
        let pages = MahjongFirstTimeGuide.pages
        #expect(pages.count == 4)
        #expect(pages.map(\.title) == MahjongRulesText.rules.prefix(4).map(\.title))
        #expect(pages.map(\.detail) == MahjongRulesText.rules.prefix(4).map(\.detail))
        for page in pages {
            #expect((MahjongTiles.parse(page.example)?.count ?? 0) >= 6, "\(page.title) 예시 손이 없다")
        }
        #expect(MahjongFirstTimeGuide.next(after: 0) == 1 && MahjongFirstTimeGuide.next(after: 2) == 3)
        #expect(MahjongFirstTimeGuide.next(after: 3) == nil)
    }

    @Test
    func practiceStartGoesThroughTheGuideGate() throws {
        // 없으면: 연습 시작 시트가 스토어를 바로 불러(안내 문을 건너뛰어) 첫 연습판에 안내가 안 떠도 초록이다.
        // 이 문(연습 시작)은 한 곳뿐이다 — 다른 `startPractice` 호출이 생기면 이 시험이 그것도 문을 지나는지 묻게 한다.
        let room = try mjGuideSource("MahjongPanelRoom.swift")
        #expect(!room.contains("store.startPractice("), "연습 시작 시트가 안내 문을 건너뛴다")
        #expect(room.contains("onStart(MahjongPracticeLaunch(format: format, timed: store.practiceTimed))"))
        let panel = try mjGuideSource("MahjongPanel.swift")
        #expect(panel.contains("if let guide = MahjongFirstTimeGuide.overlayBeforePractice(launch, defaults: guideDefaults) {"))
        #expect(panel.contains("onStartPractice: startPractice"))
        var callers = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: mjGuideSourceDir.path) where name.hasPrefix("Mahjong") {
            let text = try mjGuideSource(name)
            callers += text.components(separatedBy: "store.startPractice(").count - 1
        }
        // 창 루트의 두 곳(바로 열기 · 안내 끝)뿐.
        #expect(callers == 2)
    }
}

private let mjGuideSourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Sources/check")

/// 소스(주석 걷고 공백 접음).
private func mjGuideSource(_ name: String) throws -> String {
    let raw = try String(contentsOf: mjGuideSourceDir.appendingPathComponent(name), encoding: .utf8)
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "//") { return line[..<range.lowerBound] }
        return line
    }
    return lines.joined(separator: " ").split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
}
