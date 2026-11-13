import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 콕 찌르기 이름 찾기(2026-11-10). 제보(맥 0.3.81) "콕 찌르기에서 검색기능있으면 좋겠어요 / 사람 쉽게 찾고싶어요"
// → 대표 "둘 다 지금 시작". 총괄 지시: 이름 일부를 치면 목록이 바로 걸러지고 · 기존 목록 순서와 화면 모양을 해치지 않는다.

private func psEntry(_ id: String, _ name: String, working: Bool = false) -> PokeDirectoryEntry {
    PokeDirectoryEntry(userID: id, name: name, avatarURL: nil, isWorking: working)
}

private let psPeople: [PokeDirectoryEntry] = [
    psEntry("a", "영식", working: true),
    psEntry("b", "부잉아잉", working: true),
    psEntry("c", "타팀 김서연"),
    psEntry("d", "아잉부잉"),
    psEntry("e", "dupoy"),
    psEntry("f", "닭강정"),
    psEntry("g", "봐요"),
]

@Suite struct PokeDirectorySearchRuleTests {
    @Test("빈 검색어(공백뿐 포함)는 받은 목록 그대로 — 순서도 그대로")
    func emptyQueryKeepsEverything() {
        for q in ["", "   ", "\t", " \n "] {
            #expect(PokeDirectorySearch.filter(psPeople, query: q).map(\.userID) == psPeople.map(\.userID), "검색어 \(q.debugDescription)")
        }
    }

    @Test("이름 일부로 거르고, 남은 사람은 원래 순서 그대로(빼기만 한다)")
    func partialNameKeepsOrder() {
        #expect(PokeDirectorySearch.filter(psPeople, query: "부잉").map(\.userID) == ["b", "d"])
        #expect(PokeDirectorySearch.filter(psPeople, query: "아잉").map(\.userID) == ["b", "d"])
        // 역순 목록을 넣으면 역순으로 나온다 — 거르기가 자기 순서를 만들지 않는다.
        #expect(PokeDirectorySearch.filter(psPeople.reversed(), query: "부잉").map(\.userID) == ["d", "b"])
        // 기준선: 안 맞는 이름은 빠진다.
        #expect(!PokeDirectorySearch.matches(name: "영식", query: "부잉"))
        #expect(PokeDirectorySearch.filter(psPeople, query: "없는이름").isEmpty)
    }

    @Test("한글을 치는 동안 지나가는 모든 꼴(ㅂ → 부 → 붕 → 부이 → 부잉 …)에서 목록이 비지 않는다")
    func everyCompositionStepStillMatches() {
        // 2벌식으로 "부잉아잉"을 칠 때 입력기가 칸에 띄우는 글자 차례(마지막 음절은 표시 글자).
        let steps = ["ㅂ", "부", "붕", "부이", "부잉", "부잉ㅇ", "부잉아", "부잉앙", "부잉아이", "부잉아잉"]
        for step in steps {
            #expect(PokeDirectorySearch.matches(name: "부잉아잉", query: step), "'\(step)' 에서 부잉아잉이 빠졌다(목록이 깜빡인다)")
        }
        // 겹모음 · 겹받침도 치는 중간 꼴이 걸린다: "보" → "봐", "달" → "닭".
        #expect(PokeDirectorySearch.matches(name: "봐요", query: "보"))
        #expect(PokeDirectorySearch.matches(name: "닭강정", query: "달"))
        #expect(PokeDirectorySearch.matches(name: "닭강정", query: "ㄺ"))
        // 기준선: 음절로만 비교하면 "붕"·"부이"는 "부잉아잉"에 없다 — 자모로 풀어야 맞는다.
        #expect(!"부잉아잉".contains("붕") && !"부잉아잉".contains("부이"))
    }

    @Test("자음만 치면 첫소리로도 찾는다(ㅂㅇ → 부잉아잉) · 영문은 대소문자 · 띄어쓰기 무시")
    func initialsCaseAndSpaces() {
        // 봐요(ㅂㅇ)도 첫소리가 같아 걸린다 — 자음만 친 사람은 그 첫소리 이름을 다 보고 싶은 것이다.
        #expect(PokeDirectorySearch.filter(psPeople, query: "ㅂㅇ").map(\.userID) == ["b", "d", "g"])
        #expect(PokeDirectorySearch.matches(name: "타팀 김서연", query: "ㄱㅅㅇ"))
        #expect(!PokeDirectorySearch.matches(name: "영식", query: "ㅂㅇ"))
        #expect(PokeDirectorySearch.matches(name: "dupoy", query: "DUP"))
        #expect(PokeDirectorySearch.matches(name: "dupoy", query: " du poy "))
        #expect(PokeDirectorySearch.matches(name: "타팀 김서연", query: "팀김"))
        #expect(PokeDirectorySearch.matches(name: "타팀 김서연", query: "김 서"))
        // NFD 로 온 이름(분해형 한글)도 같은 이름이다.
        let nfd = "부잉아잉".decomposedStringWithCanonicalMapping
        #expect(nfd.unicodeScalars.count > 4, "전제: 분해형이 아니다")
        #expect(PokeDirectorySearch.matches(name: nfd, query: "부잉"))
    }

    @Test("찾는 동안 목록 높이는 찾기 전 높이(상한 이하)로 붙든다 · 안 찾을 때는 손대지 않는다")
    func listHeightHoldsWhileSearching() {
        #expect(PokeSearchListHeight.held(isSearching: false, shown: 48, unfiltered: 432, cap: 384) == nil)
        #expect(PokeSearchListHeight.held(isSearching: true, shown: 48, unfiltered: 432, cap: 384) == 384)
        #expect(PokeSearchListHeight.held(isSearching: true, shown: 48, unfiltered: 104, cap: 384) == 104)
        #expect(PokeSearchListHeight.held(isSearching: true, shown: 104, unfiltered: 104, cap: 384) == 104)
    }
}

// MARK: - 칸: 치는 중인 음절이 바깥으로 나오는가(진짜 텍스트 뷰)

@MainActor
private final class PSDelegateDraft: NSObject, NSTextViewDelegate {
    var draft = ""
    func textDidChange(_ notification: Notification) {
        draft = (notification.object as? NSTextView)?.string ?? draft
    }
}

@MainActor
@Suite struct PokeSearchEditorTests {
    @Test("표시 글자(조합 중 음절)가 그려진 글자 통로로 곧바로 나온다 · 같은 글자는 다시 안 알린다 · 바인딩은 여전히 한 음절 늦다(기준선)")
    func renderedTextIncludesMarkedText() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 26), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let view = CheckEditorTextView(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        window.contentView = view
        window.makeFirstResponder(view)
        let delegate = PSDelegateDraft()
        view.delegate = delegate
        var reports: [String] = []
        view.onRenderedTextChange = { reports.append($0) }

        let none = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("ㅂ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        #expect(view.hasMarkedText(), "표시 글자를 못 심었다 — 이 시험이 재는 것이 없다")
        view.setMarkedText("부", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 1))
        #expect(reports == ["ㅂ", "부"], "치는 중 음절이 안 나왔다: \(reports)")
        // 기준선: 표시 글자 구간에는 바인딩(textDidChange)이 안 온다 — 그래서 이 통로가 필요하다.
        #expect(delegate.draft == "", "바인딩이 조합 중 글자를 받았다 — 전제가 바뀌었다: \(delegate.draft)")

        #expect(view.commitComposition())
        #expect(delegate.draft == "부")
        // 확정은 같은 글자라 다시 알리지 않는다(SwiftUI 상태를 흔들지 않는다).
        #expect(reports == ["ㅂ", "부"], "같은 글자를 또 알렸다: \(reports)")

        // 통로를 안 붙인 칸(대화 · 제보 · 오목)은 아무 일도 없다.
        view.onRenderedTextChange = nil
        view.insertText("잉", replacementRange: none)
        #expect(reports == ["ㅂ", "부"])
    }

    @Test("검색 칸 배선: 패널이 칸을 목록 위에 세우고, 그려진 글자로 거른다 · 높이 예산에 칸을 넣는다")
    func panelWiring() throws {
        let menu = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/CheckMenuView.swift"),
                              encoding: .utf8)
        #expect(menu.contains("PokeSearchBox(draft: $searchDraft, rendered: $searchRendered, rendersPlainText: plainTextEditors)"))
        #expect(menu.contains("extraChromeHeight: extraChromeHeight + receiptStripHeight + searchRowHeight"),
                "검색 칸 높이가 목록 예산에 안 들어갔다 — 창이 700pt 를 넘는다")
        #expect(menu.contains("private var searchQuery: String { searchRendered ?? searchDraft }"))
        let box = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/PokeDirectorySearch.swift"),
                             encoding: .utf8)
        #expect(box.contains("if (rendered ?? draft) != newValue { rendered = newValue }"), "칸이 치는 중 글자를 넘기지 않는다")
    }
}

// MARK: - 화면: 찌르기 패널에 검색 칸 · 걸러진 목록 · 높이

@MainActor
private func psStore(memberCount: Int, function: String = #function, line: Int = #line) -> WorkTimerStore {
    let tag = "ps-\(line)"
    let home = CheckTestScratch.directory("token-\(tag)", function: function)
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: CheckTestScratch.defaults(tag, function: function),
        tokenUsage: TokenUsageStore(
            defaults: CheckTestScratch.defaults("token-\(tag)", function: function),
            homeDirectory: home.appendingPathComponent("home", isDirectory: true),
            cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
        )
    )
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
    store.displayNow = now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    let pool: [PokeDirectoryEntry] = [
        psEntry("u1", "영식", working: true), psEntry("u2", "민수", working: true), psEntry("u3", "지현"),
        psEntry("u4", "타팀 김서연"), psEntry("u5", "서준"), psEntry("u6", "하윤", working: true),
        psEntry("u7", "타팀 박도윤"), psEntry("u8", "도현"), psEntry("u9", "예린", working: true), psEntry("u10", "타팀 최시우"),
    ]
    store.pokeDirectory = Array(pool.prefix(memberCount))
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    return store
}

@MainActor
private func psRender(_ store: WorkTimerStore, query: String?) throws -> NSBitmapImageRep {
    let view = CheckMenuView(store: store, previewClipsOverflowList: true, previewPlainTextEditors: true, previewPokeSearchQuery: query)
    return try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2), "렌더 실패")
}

/// 채널 차이가 8 을 넘는 픽셀 수(같은 크기만).
@MainActor
private func psDifferingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, let pa = a.bitmapData, let pb = b.bitmapData else { return Int.max }
    let count = a.bytesPerRow * a.pixelsHigh
    var n = 0
    var i = 0
    while i < count {
        if abs(Int(pa[i]) - Int(pb[i])) > 8 { n += 1 }
        i += 1
    }
    return n
}

/// 캡처 저장(보고 자료용). 환경 변수가 있을 때만 쓴다.
@MainActor
private func psSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["POKE_SEARCH_SHOTS"],
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
}

@MainActor
@Suite struct PokeSearchPanelRenderTests {
    @Test("10명 패널: 검색 칸이 서도 창은 700pt 안 · 찾는 동안 창 높이가 그대로 · 걸러진 화면은 다르게 그려진다")
    func panelStaysWithinCapAndHoldsHeight() throws {
        let plain = try psRender(psStore(memberCount: 10), query: nil)
        let searching = try psRender(psStore(memberCount: 10), query: "타팀")
        let none = try psRender(psStore(memberCount: 10), query: "없는이름")
        psSave(plain, "poke-search-empty")
        psSave(searching, "poke-search-tatim")
        psSave(none, "poke-search-nomatch")
        print("[poke-search] 높이 px: 빈 칸 \(plain.pixelsHigh) · '타팀' \(searching.pixelsHigh) · 없음 \(none.pixelsHigh)")
        #expect(Double(plain.pixelsHigh) / 2 <= 700, "검색 칸 때문에 창이 700pt 를 넘었다")
        #expect(searching.pixelsHigh == plain.pixelsHigh, "찾는 동안 창 높이가 바뀌었다(\(plain.pixelsHigh) → \(searching.pixelsHigh))")
        #expect(none.pixelsHigh == plain.pixelsHigh, "아무도 안 맞을 때 창 높이가 바뀌었다")
        #expect(psDifferingPixels(plain, searching) > 400, "검색어를 넣어도 화면이 그대로다 — 안 걸러졌다")
        #expect(psDifferingPixels(searching, none) > 400)
    }

    @Test("3명 패널(스크롤 없음): 찾는 동안 목록 자리가 그대로 · 빈 목록이면 검색 칸을 세우지 않는다")
    func smallPanelAndEmptyDirectory() throws {
        let plain = try psRender(psStore(memberCount: 3), query: nil)
        let searching = try psRender(psStore(memberCount: 3), query: "영")
        #expect(searching.pixelsHigh == plain.pixelsHigh, "3명 목록에서 찾는 동안 창이 줄었다")
        psSave(searching, "poke-search-small")

        // 사람이 없으면 칸도 없다 — 검색어를 넣어도 화면이 같다(칸이 섰다면 글자가 보여 달라진다).
        let emptyPlain = try psRender(psStore(memberCount: 0), query: nil)
        let emptyQuery = try psRender(psStore(memberCount: 0), query: "영")
        #expect(emptyQuery.pixelsHigh == emptyPlain.pixelsHigh)
        #expect(psDifferingPixels(emptyPlain, emptyQuery) < 40, "빈 목록인데 검색 칸이 섰다")
    }
}
