import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 콕 찌르기 목록 거르기 칸 '전체 · 근무중 · 자리비움'(2026-11-18). 제보(부산, 11-10) "콕 찌르기에서 '전체', '활동중', '활동안함'
// 이렇게 카테고리 되어있어서 사람들 구분할수 있는? 거 있으면 좋겠어요." → 대표 "고치기 — 다음 맥 판에 넣기".
// 지시: 빼기만(순서 그대로 · 안 읽음 맨 위 유지) · 이름 찾기와 AND · 집중은 근무 중 · 칸마다 빈 문구 · 스토어에 남고 로그아웃에 전체 ·
// 패널 높이 그대로(이름 찾기 칸과 같은 줄).

private func pfEntry(_ id: String, _ name: String, working: Bool, focused: Bool = false) -> PokeDirectoryEntry {
    PokeDirectoryEntry(userID: id, name: name, avatarURL: nil, isWorking: working, isFocused: focused)
}

/// 정렬 전 목록(일부러 뒤섞었다). f · e 는 안 읽음이 있다.
private let pfPeople: [PokeDirectoryEntry] = [
    pfEntry("g", "사랑", working: false),
    pfEntry("c", "다솜", working: true, focused: true),      // 근무 중 집중 — 칩은 '집중'
    pfEntry("e", "마루", working: false),                    // 안 읽은 메시지
    pfEntry("a", "가람", working: true),
    pfEntry("d", "라온", working: false, focused: true),     // 집중을 켜 둔 채 퇴근 — 칩은 '집중'
    pfEntry("f", "바다", working: true),                     // 안 본 찌르기
    pfEntry("b", "나래", working: false),
]

/// 화면과 같은 정렬(안 읽음 → 근무중 → 이름 — `PokePanelOrder`)을 지난 목록.
private let pfSorted = PokePanelOrder.sorted(pfPeople, unreadMessagePeerIDs: ["e"], unreadPokePeerIDs: ["f"])

@Suite struct PokePresenceFilterRuleTests {
    @Test("전제: 정렬은 안 읽음 → 근무중 → 이름이다(이 파일의 기준 목록)")
    func fixtureOrder() {
        #expect(pfSorted.map(\.userID) == ["f", "e", "a", "c", "b", "d", "g"])
    }

    @Test("전체 칸 · 빈 검색어는 받은 목록 그대로 — 거르는 중이 아니다(높이를 붙들지 않는다)")
    func allKeepsEverything() {
        for query in ["", "  ", "\n"] {
            let shown = PokeDirectoryNarrowing.apply(pfSorted, query: query, presence: .all)
            #expect(shown.rows.map(\.userID) == pfSorted.map(\.userID), "검색어 \(query.debugDescription)")
            #expect(!shown.isNarrowed)
            #expect(shown.emptyText == nil)
        }
    }

    @Test("근무중 · 자리비움 칸은 빼기만 한다 — 순서 그대로, 안 읽은 사람은 칸 안에서도 맨 위")
    func presenceKeepsOrderAndUnreadFirst() {
        let working = PokeDirectoryNarrowing.apply(pfSorted, query: "", presence: .working)
        let away = PokeDirectoryNarrowing.apply(pfSorted, query: "", presence: .away)
        #expect(working.rows.map(\.userID) == ["f", "a", "c"])
        #expect(away.rows.map(\.userID) == ["e", "b", "d", "g"])
        // 안 읽은 사람(f · e)이 각 칸의 맨 위다(v0.3.65 네 무리 정렬이 칸 안에서도 산다).
        #expect(working.rows.first?.userID == "f")
        #expect(away.rows.first?.userID == "e")
        // 두 칸은 겹치지 않고 합치면 전체다.
        #expect(Set(working.rows.map(\.userID)).isDisjoint(with: away.rows.map(\.userID)))
        #expect(working.rows.count + away.rows.count == pfSorted.count)
        // 칸을 골랐으면 아무도 안 빠져도 거르는 중이다 — 칸을 바꿀 때 목록 자리가 흔들리지 않게 높이를 붙든다.
        #expect(working.isNarrowed && away.isNarrowed)
        // 거르기가 자기 순서를 만들지 않는다: 뒤집어 넣으면 뒤집혀 나온다.
        let reversed = PokeDirectoryNarrowing.apply(Array(pfSorted.reversed()), query: "", presence: .working)
        #expect(reversed.rows.map(\.userID) == ["c", "a", "f"])
    }

    @Test("집중은 칸을 바꾸지 않는다 — 근무 중 집중은 근무중 칸, 퇴근 뒤 켜 둔 집중은 자리비움 칸(칩과 같은 isWorking)")
    func focusCountsAsWorkingWhileWorking() {
        let working = PokeDirectoryNarrowing.apply(pfSorted, query: "", presence: .working).rows.map(\.userID)
        let away = PokeDirectoryNarrowing.apply(pfSorted, query: "", presence: .away).rows.map(\.userID)
        #expect(working.contains("c"), "근무 중에 집중한 사람(칩 '집중')이 근무중 칸에서 빠졌다")
        #expect(!away.contains("c"))
        #expect(away.contains("d"), "집중을 켠 채 퇴근한 사람은 근무 중이 아니다 — 자리비움 칸이어야 한다")
        #expect(!working.contains("d"))
        // 한 사람씩: 판정은 근무 여부 하나다.
        for entry in pfPeople {
            #expect(PokePresenceFilter.working.admits(entry) == entry.isWorking, "\(entry.name)")
            #expect(PokePresenceFilter.away.admits(entry) == !entry.isWorking, "\(entry.name)")
            #expect(PokePresenceFilter.all.admits(entry))
        }
    }

    @Test("이름 찾기와 근무 칸은 함께 건다(AND) — 둘 다 맞는 사람만, 순서 그대로")
    func searchAndPresenceCombine() {
        // "라" 는 가람(근무) · 라온(자리비움, 집중) · 사랑(자리비움) 셋에 걸린다(자모로 풀어 비교 — 가람 = ㄱㅏㄹㅏㅁ, 사랑 = ㅅㅏㄹㅏㅇ).
        #expect(PokeDirectoryNarrowing.apply(pfSorted, query: "라", presence: .all).rows.map(\.userID) == ["a", "d", "g"])
        #expect(PokeDirectoryNarrowing.apply(pfSorted, query: "라", presence: .working).rows.map(\.userID) == ["a"])
        #expect(PokeDirectoryNarrowing.apply(pfSorted, query: "라", presence: .away).rows.map(\.userID) == ["d", "g"])
        // 모든 칸 × 여러 검색어에서: 결과 = 정렬된 목록에서 (칸에 들고 && 이름이 맞는) 사람을 순서대로 남긴 것.
        for presence in PokePresenceFilter.allCases {
            for query in ["", "ㄹ", "바", "ㅁㄹ", "없는이름", " 다 솜 "] {
                let expected = pfSorted.filter { presence.admits($0) && PokeDirectorySearch.matches(name: $0.name, query: query) }
                let shown = PokeDirectoryNarrowing.apply(pfSorted, query: query, presence: presence)
                #expect(shown.rows.map(\.userID) == expected.map(\.userID), "\(presence) · \(query.debugDescription)")
            }
        }
    }

    @Test("칸마다 빈 문구 — 걸러서 비면 그 칸의 한 줄, 사람이 아예 없으면 거르는 중이 아니다(원래 빈 목록 문구)")
    func emptyStatePerFilter() {
        let allAway = pfSorted.filter { !$0.isWorking }
        let noneWorking = PokeDirectoryNarrowing.apply(allAway, query: "", presence: .working)
        #expect(noneWorking.rows.isEmpty && noneWorking.isNarrowed)
        #expect(noneWorking.emptyText == PokePresenceFilterText.noneWorking)

        let allWorking = pfSorted.filter(\.isWorking)
        #expect(PokeDirectoryNarrowing.apply(allWorking, query: "", presence: .away).emptyText == PokePresenceFilterText.noneAway)

        #expect(PokeDirectoryNarrowing.apply(pfSorted, query: "없는이름", presence: .all).emptyText == PokeDirectorySearch.noMatch)
        #expect(PokeDirectoryNarrowing.apply(pfSorted, query: "없는이름", presence: .working).emptyText == PokePresenceFilterText.noMatchWorking)
        #expect(PokeDirectoryNarrowing.apply(pfSorted, query: "없는이름", presence: .away).emptyText == PokePresenceFilterText.noMatchAway)

        // 사람이 없으면 칸도 검색 칸도 안 선다 — 어느 칸을 골라 뒀든 원래 빈 목록 문구('아직 다른 사용자가 없어요')가 말한다.
        for presence in PokePresenceFilter.allCases {
            let empty = PokeDirectoryNarrowing.apply([], query: "영", presence: presence)
            #expect(empty.rows.isEmpty && !empty.isNarrowed && empty.emptyText == nil, "\(presence)")
        }
        // 여섯 갈래가 모두 다른 말이다(전체 · 안 찾는 중만 nil).
        let texts = PokePresenceFilter.allCases.flatMap { p in [false, true].map { PokePresenceFilterText.empty(presence: p, isSearching: $0) } }
        #expect(texts.compactMap { $0 }.count == 5)
        #expect(Set(texts.compactMap { $0 }).count == 5)
    }

    @Test("가려진 안 읽음: 고른 칸 밖의 안 읽은 사람이 든 칸에만 점 — 전체를 골랐거나 안 읽은 사람이 다 보이면 점이 없다")
    func hiddenUnreadMarksItsOwnSegment() {
        func marks(_ selected: PokePresenceFilter, messages: Set<String> = [], pokes: Set<String> = []) -> Set<PokePresenceFilter> {
            PokePresenceFilter.segmentsHidingUnread(pfSorted, selected: selected, unreadMessagePeerIDs: messages, unreadPokePeerIDs: pokes)
        }
        // 근무중을 골랐는데 자리비움인 마루(e)가 메시지를 보냈다 → 자리비움 칸에 점. 근무 중인 바다(f)의 찌르기는 보이므로 점이 아니다.
        #expect(marks(.working, messages: ["e"], pokes: ["f"]) == [.away])
        // 거꾸로: 자리비움을 골랐는데 근무 중인 바다(f)가 찔렀다 → 근무중 칸에 점(찌르기도 안 읽음이다 — v0.3.65).
        #expect(marks(.away, pokes: ["f"]) == [.working])
        #expect(marks(.away, messages: ["e"]) == [], "보이는 사람의 안 읽음에 점을 찍었다")
        // 전체를 골랐으면 아무도 안 가려진다 — 안 읽음이 있어도 점이 없다.
        #expect(marks(.all, messages: ["e"], pokes: ["f"]) == [])
        #expect(marks(.working) == [] && marks(.away) == [])
        // 전체 칸에는 점을 안 찍는다(점은 그 사람이 든 칸 하나).
        for selected in PokePresenceFilter.allCases {
            #expect(!marks(selected, messages: Set(pfSorted.map(\.userID))).contains(.all))
            #expect(!marks(selected, messages: Set(pfSorted.map(\.userID))).contains(selected), "고른 칸에 점이 찍혔다(\(selected))")
        }
        // 집중을 켠 채 퇴근한 라온(d)은 자리비움 칸 사람이다 — 판정은 `admits` 하나라 칸 나누기와 점이 같은 규칙이다.
        #expect(marks(.working, messages: ["d"]) == [.away])
        // 툴팁: 점이 있으면 그 까닭을 덧붙인다.
        #expect(PokePresenceFilterText.tooltip(.away, hidingUnread: false) == PokePresenceFilter.away.help)
        #expect(PokePresenceFilterText.tooltip(.away, hidingUnread: true).hasSuffix(PokePresenceFilterText.hidingUnread))
    }

    @Test("칸 글자는 행 칩의 낱말과 같다(근무중 · 자리비움) · 빈 문구는 목록 폭 한 줄에 든다")
    func copyMatchesChipsAndFitsOneLine() throws {
        #expect(PokePresenceFilter.allCases.map(\.label) == ["전체", "근무중", "자리비움"])
        let menu = pfStripComments(try pfSource("Sources/check/CheckMenuView.swift"))
        let row = try #require(pfRegion(menu, from: "struct PokeDirectoryRowView: View {", to: "static func pokeBlockedReason("))
        #expect(row.contains("Text(\"\(PokePresenceFilter.working.label)\")"), "칩 낱말과 칸 글자가 갈렸다(근무중)")
        #expect(row.contains("Text(\"\(PokePresenceFilter.away.label)\")"), "칩 낱말과 칸 글자가 갈렸다(자리비움)")
        // 빈 문구는 caption 한 줄(목록 폭 292pt)에 든다 — 두 줄이 되면 빈 행(48pt) 안에서 글자가 눌린다.
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        for text in [PokePresenceFilterText.noneWorking, PokePresenceFilterText.noneAway,
                     PokePresenceFilterText.noMatchWorking, PokePresenceFilterText.noMatchAway] {
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            #expect(width < PokeTitleRowWidthBudget.contentWidth, "'\(text)' 가 한 줄(\(PokeTitleRowWidthBudget.contentWidth)pt)을 넘는다: \(width)")
        }
    }
}

// MARK: - 스토어: 기본 전체 · 고르기 · 로그아웃에 전체

@MainActor
private func pfStore(people: [PokeDirectoryEntry], presence: PokePresenceFilter = .all,
                     function: String = #function, line: Int = #line) -> WorkTimerStore {
    let tag = "pf-\(line)"
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
    store.pokeDirectory = people
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    store.pokePresenceFilter = presence
    return store
}

@MainActor
@Suite struct PokePresenceFilterStoreTests {
    @Test("처음은 전체 · 고르면 남는다 · 같은 칸을 다시 고르면 아무것도 안 건드린다(관찰 무효화 0)")
    func defaultSelectAndSameValueIsQuiet() {
        let store = pfStore(people: [])
        #expect(store.pokePresenceFilter == .all)

        let fired = PFObservationFlag()
        withObservationTracking { _ = store.pokePresenceFilter } onChange: { fired.value = true }
        store.selectPokePresenceFilter(.all)
        #expect(!fired.value, "같은 값을 다시 써서 찌르기 패널이 헛돌았다")

        // 기준선: 다른 칸이면 알린다(위 '안 알림'이 추적을 못 건 탓이 아니라는 뜻).
        store.selectPokePresenceFilter(.away)
        #expect(store.pokePresenceFilter == .away)
        #expect(fired.value)

        // 패널을 닫아도(화면 깃발만 내려도) 고른 칸은 남는다 — 앱이 켜져 있는 동안의 값이다.
        store.isPokePanelVisible = false
        store.isPokePanelVisible = true
        #expect(store.pokePresenceFilter == .away)
    }

    @Test("로그아웃(사용자가 누른 것 · 토큰 만료 강제 둘 다)하면 전체로 돌아간다")
    func signOutResetsToAll() {
        let forced = pfStore(people: [], presence: .working)
        forced.clearPersistedSession()
        #expect(forced.pokePresenceFilter == .all, "강제 로그아웃 뒤 앞 사람이 고른 칸이 남았다")

        let user = pfStore(people: [], presence: .away)
        user.signOut(notifyServer: false)
        #expect(user.pokePresenceFilter == .all, "로그아웃 뒤 앞 사람이 고른 칸이 남았다")
    }

    @Test("소스: 고르기는 값만 바꾼다(조회 · 작업 없음) · 앱 화면이 스토어 값과 고르기를 패널에 넘긴다")
    func wiringAndNoNetwork() throws {
        let filter = pfStripComments(try pfSource("Sources/check/PokePresenceFilter.swift"))
        let select = try #require(pfRegion(filter, from: "func selectPokePresenceFilter(", to: "enum PokePresenceFilterText"))
        #expect(!select.contains("Task"), "칸 고르기가 작업을 띄운다 — 새 조회가 생긴다")
        #expect(!select.contains("service"), "칸 고르기가 서버를 부른다")
        #expect(!select.contains("refresh"), "칸 고르기가 목록을 다시 받는다")
        #expect(select.contains("guard pokePresenceFilter != filter else { return }"))

        let menu = pfStripComments(try pfSource("Sources/check/CheckMenuView.swift"))
        #expect(menu.contains("presenceFilter: store.pokePresenceFilter,"), "스토어의 칸이 패널로 안 간다")
        #expect(menu.contains("onSelectPresenceFilter: { store.selectPokePresenceFilter($0) },"), "칸을 눌러도 스토어가 모른다")
    }
}

// MARK: - 화면 계약: 같은 줄 · 높이 예산 그대로 · 보이스오버 · 툴팁

@Suite struct PokePresenceFilterLayoutContractTests {
    @Test("소스: 근무 칸은 이름 찾기 칸과 한 줄(PokeSearchFilterRow) · 목록 예산에 새 높이를 더하지 않는다 · 정렬 한 번 뒤 거르기")
    func sameRowAndBudgetUnchanged() throws {
        let menu = pfStripComments(try pfSource("Sources/check/CheckMenuView.swift"))
        let panel = try #require(pfRegion(menu, from: "private struct PokePanel: View {", to: "static func listContentHeight(rowCount:"))
        let rowStart = try #require(panel.range(of: "PokeSearchFilterRow("), "근무 칸이 검색 칸 줄에 없다")
        let afterRow = panel[rowStart.upperBound...]
        let narrowing = try #require(afterRow.range(of: "PokeDirectoryNarrowing.apply("))
        let rowCall = afterRow[..<narrowing.lowerBound]
        #expect(rowCall.contains("PokeSearchBox(draft: $searchDraft, rendered: $searchRendered, rendersPlainText: plainTextEditors)"),
                "검색 칸이 근무 칸과 같은 줄 안에 있지 않다")
        #expect(rowCall.contains("presence: presenceFilter,") && rowCall.contains("onSelect: onSelectPresenceFilter"))
        // 가려진 안 읽음 점: 정렬된 목록과 안 읽음 두 집합(메시지 · 찌르기)을 그대로 넘긴다.
        #expect(rowCall.contains("hidingUnread: PokePresenceFilter.segmentsHidingUnread("), "가려진 안 읽은 사람을 칸이 모른다")
        #expect(rowCall.contains("sorted, selected: presenceFilter,"))
        #expect(rowCall.contains("unreadMessagePeerIDs: unreadMessagePeerIDs, unreadPokePeerIDs: unreadPokePeerIDs"))
        #expect(panel.components(separatedBy: "PokeSearchBox(").count - 1 == 1, "검색 칸이 줄 밖에 하나 더 섰다")
        #expect(panel.contains("entryList(PokeDirectoryNarrowing.apply(sorted, query: searchQuery, presence: presenceFilter), all: sorted)"),
                "거르기가 정렬된 목록(sorted)을 거치지 않는다 — 순서가 깨진다")
        // 목록 예산: 검색 줄 몫은 예전 그대로 '칸 높이 + 간격 12' 하나다(근무 칸 몫 0).
        #expect(panel.contains("entries.isEmpty ? 0 : PokeSearchBox.height + 12"), "검색 줄 높이 예산이 바뀌었다")
        #expect(panel.contains("extraChromeHeight: extraChromeHeight + receiptStripHeight + searchRowHeight"))
        #expect(!panel.contains("PokePresenceFilterBar("), "근무 칸이 줄 밖(새 줄)에 따로 섰다")
        // 높이 붙들기는 거르는 중(이름 · 칸) 전체에 건다.
        #expect(panel.contains("isSearching: narrowing.isNarrowed"), "칸을 바꿀 때 목록 자리가 줄었다 늘었다 한다")
    }

    @Test("소스: 걸러서 비면 그 칸의 한 줄이 행 자리에 선다 — 목록의 세 갈래(맞춤 · 클립 · 스크롤)가 모두 그 줄을 넘긴다")
    func emptyLineReachesThePanel() throws {
        let menu = pfStripComments(try pfSource("Sources/check/CheckMenuView.swift"))
        let list = try #require(pfRegion(menu, from: "private func entryList(_ narrowing: PokeDirectoryNarrowing, all: [PokeDirectoryEntry])",
                                         to: "private func rows(_ sorted: [PokeDirectoryEntry], emptyText: String?)"))
        #expect(list.components(separatedBy: "rows(sorted, emptyText: narrowing.emptyText)").count - 1 == 3,
                "목록 한 갈래가 칸의 빈 문구를 안 넘긴다")
        let rows = try #require(pfRegion(menu, from: "private func rows(_ sorted: [PokeDirectoryEntry], emptyText: String?)",
                                         to: "PokeDirectoryRowView("))
        // '?? 원래 문구'가 빠지면 근무중 칸이 비었을 때 '아직 다른 사용자가 없어요'(거짓)가 뜬다.
        #expect(rows.contains("Text(emptyText ?? PokeDirectoryEmptyMessage.text(hasLoaded: hasLoaded, fallbackStatus: fallbackStatus))"),
                "빈 행이 칸의 한 줄(emptyText)을 먼저 보지 않는다")
    }

    @Test("소스: 칸마다 툴팁 · 보이스오버 말 · 고른 칸 표시 — AppKit 고르개(Picker)는 쓰지 않는다")
    func accessibilityAndTooltips() throws {
        let filter = pfStripComments(try pfSource("Sources/check/PokePresenceFilter.swift"))
        let bar = try #require(pfRegion(filter, from: "struct PokePresenceFilterBar: View {", to: nil))
        #expect(bar.contains(".checkTooltip(PokePresenceFilterText.tooltip(filter, hidingUnread: hidesUnread))"))
        // 이름은 보이는 글자 그대로 — 음성 제어 "근무중 클릭"이 그 칸을 찾는다. 긴 문장은 툴팁이 힌트로 붙인다.
        #expect(bar.contains(".accessibilityLabel(filter.label)"))
        #expect(!bar.contains(".accessibilityLabel(filter.help)"), "보이스오버가 보이는 글자와 다른 이름을 읽는다")
        #expect(bar.contains(".accessibilityValue(hidesUnread ? PokePresenceFilterText.hidingUnread : \"\")"))
        #expect(bar.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        #expect(bar.contains(".accessibilityLabel(PokePresenceFilterText.groupLabel)"))
        #expect(!bar.contains("Picker("), "AppKit 고르개는 렌더 시험에서 노란 상자가 된다")
        // 툴팁 말은 칸마다 다르고 비어 있지 않다.
        let helps = PokePresenceFilter.allCases.map(\.help)
        #expect(Set(helps).count == 3 && helps.allSatisfy { !$0.isEmpty })
        // 칸은 근무 여부 하나로 나눈다 — 집중을 켠 채 퇴근한 사람('집중' 칩)은 자리비움 칸이다. 근무중 툴팁이 '(집중 포함)'이라
        // 말하면 자리비움 칸의 '집중' 칩이 고장으로 읽힌다.
        for filter in PokePresenceFilter.allCases {
            #expect(!filter.help.contains("집중"), "\(filter.label) 툴팁이 집중을 말한다 — 칸은 근무 여부만 본다")
        }
    }
}

// MARK: - 렌더: 줄 높이 · 폭 · 칸마다 패널 · 빈 문구(캡처는 FEATURE_SHOTS_DIR)

@MainActor
private func pfBitmap(_ view: some View) throws -> NSBitmapImageRep {
    try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2), "렌더 실패")
}

@MainActor
private func pfPanel(_ store: WorkTimerStore, query: String? = nil) throws -> NSBitmapImageRep {
    try pfBitmap(CheckMenuView(store: store, previewClipsOverflowList: true, previewPlainTextEditors: true, previewPokeSearchQuery: query))
}

/// 채널 차이가 8 을 넘는 픽셀 수(같은 크기만 — 크기가 다르면 Int.max).
@MainActor
private func pfDiffering(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
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

/// 픽셀 줄마다 다른 바이트가 있는 줄 번호(위에서부터). 크기가 다르면 nil.
@MainActor
private func pfDifferingRows(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> [Int]? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, a.bytesPerRow == b.bytesPerRow,
          let pa = a.bitmapData, let pb = b.bitmapData else { return nil }
    var rows: [Int] = []
    for y in 0..<a.pixelsHigh {
        let start = y * a.bytesPerRow
        for i in start..<(start + a.bytesPerRow) where abs(Int(pa[i]) - Int(pb[i])) > 8 {
            rows.append(y)
            break
        }
    }
    return rows
}

/// 픽셀 줄 `row` 아래(그 줄 제외)에서 채널 차이가 8 을 넘는 바이트 수. 크기가 다르면 nil.
@MainActor
private func pfDifferingBelow(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, row: Int) -> Int? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, a.bytesPerRow == b.bytesPerRow,
          let pa = a.bitmapData, let pb = b.bitmapData else { return nil }
    var n = 0
    var i = (row + 1) * a.bytesPerRow
    let count = a.bytesPerRow * a.pixelsHigh
    while i < count {
        if abs(Int(pa[i]) - Int(pb[i])) > 8 { n += 1 }
        i += 1
    }
    return n
}

/// 캡처 저장(보고 자료용). FEATURE_SHOTS_DIR 이 있을 때만 쓴다.
@MainActor
private func pfSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["FEATURE_SHOTS_DIR"], !dir.isEmpty,
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
}

/// 패널 픽스처 10명 — 근무 4(그중 민수는 집중) · 자리비움 6(그중 서준은 집중을 켜 둔 채 퇴근).
private let pfPanelPool: [PokeDirectoryEntry] = [
    pfEntry("u1", "영식", working: true), pfEntry("u2", "민수", working: true, focused: true), pfEntry("u3", "지현", working: false),
    pfEntry("u4", "타팀 김서연", working: false), pfEntry("u5", "서준", working: false, focused: true), pfEntry("u6", "하윤", working: true),
    pfEntry("u7", "타팀 박도윤", working: false), pfEntry("u8", "도현", working: false), pfEntry("u9", "예린", working: true),
    pfEntry("u10", "타팀 최시우", working: false),
]

@MainActor
@Suite struct PokePresenceFilterRenderTests {
    @Test("한 줄: 검색 칸 + 근무 칸 줄은 검색 칸 높이(26pt) 그대로 · 근무 칸 폭은 상한 안 · 검색 칸에 안내 글자 + 지우기 폭이 남는다")
    func rowKeepsSearchHeightAndWidth() throws {
        let width = PokeTitleRowWidthBudget.contentWidth
        let boxOnly = try pfBitmap(
            PokeSearchBox(draft: .constant(""), rendered: .constant(nil), rendersPlainText: true).frame(width: width)
        )
        let row = try pfBitmap(
            PokeSearchFilterRow(presence: .working, onSelect: { _ in }) {
                PokeSearchBox(draft: .constant(""), rendered: .constant(nil), rendersPlainText: true)
            }
            .frame(width: width)
        )
        pfSave(row, "poke-filter-row")
        #expect(boxOnly.pixelsHigh == Int(PokeSearchBox.height * 2), "기준선: 검색 칸 높이가 \(boxOnly.pixelsHigh / 2)pt 다")
        #expect(row.pixelsHigh == boxOnly.pixelsHigh, "근무 칸이 줄을 키웠다(\(boxOnly.pixelsHigh / 2) → \(row.pixelsHigh / 2)pt)")

        let bar = try pfBitmap(PokePresenceFilterBar(selection: .all, onSelect: { _ in }))
        let barWidth = CGFloat(bar.pixelsWide) / 2
        print("[poke-filter] 근무 칸 폭 \(barWidth)pt · 높이 \(CGFloat(bar.pixelsHigh) / 2)pt")
        #expect(barWidth <= PokePresenceFilterBar.maxWidth, "근무 칸이 \(barWidth)pt — 상한 \(PokePresenceFilterBar.maxWidth)pt 를 넘는다")
        #expect(CGFloat(bar.pixelsHigh) / 2 == PokeSearchBox.height)
        // 고른 칸이 굵어져도 폭 상한 안이다(가장 긴 '자리비움'을 고른 때).
        let barAway = try pfBitmap(PokePresenceFilterBar(selection: .away, onSelect: { _ in }))
        #expect(CGFloat(barAway.pixelsWide) / 2 <= PokePresenceFilterBar.maxWidth)

        // 검색 칸에 남는 폭: 돋보기(9 + 11) − 당김 4 + 안쪽 여백 10×2 + '이름으로 찾기' + 지우기 단추 22.
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        let placeholder = ceil((PokeDirectorySearch.placeholder as NSString).size(withAttributes: [.font: font]).width)
        let needed = 9 + 11 - 4 + CheckEditorMetrics.inset.width * 2 + placeholder + 22
        let left = width - PokePresenceFilterBar.maxWidth - PokeSearchFilterRow<EmptyView>.spacing
        #expect(left >= needed, "검색 칸이 \(left)pt 로 좁아져 안내 글자(\(needed)pt)가 잘린다")
    }

    @Test("10명 패널: 칸마다 다르게 그려지고 창 높이는 그대로(700pt 안) · 같은 입력 두 번은 같다(기준선)")
    func panelPerFilterHoldsHeight() throws {
        let all = try pfPanel(pfStore(people: pfPanelPool, presence: .all))
        let allTwin = try pfPanel(pfStore(people: pfPanelPool, presence: .all))
        let working = try pfPanel(pfStore(people: pfPanelPool, presence: .working))
        let away = try pfPanel(pfStore(people: pfPanelPool, presence: .away))
        let awaySearch = try pfPanel(pfStore(people: pfPanelPool, presence: .away), query: "타팀")
        let workingNoMatch = try pfPanel(pfStore(people: pfPanelPool, presence: .working), query: "타팀")
        pfSave(all, "poke-filter-all")
        pfSave(working, "poke-filter-working")
        pfSave(away, "poke-filter-away")
        pfSave(awaySearch, "poke-filter-away-search")
        pfSave(workingNoMatch, "poke-filter-working-nomatch")
        print("[poke-filter] 높이 px: 전체 \(all.pixelsHigh) · 근무중 \(working.pixelsHigh) · 자리비움 \(away.pixelsHigh) · 자리비움+'타팀' \(awaySearch.pixelsHigh) · 근무중+'타팀' \(workingNoMatch.pixelsHigh)")

        #expect(Double(all.pixelsHigh) / 2 <= 700, "창이 700pt 를 넘었다")
        for (name, shot) in [("근무중", working), ("자리비움", away), ("자리비움+검색", awaySearch), ("근무중+검색 없음", workingNoMatch)] {
            #expect(shot.pixelsHigh == all.pixelsHigh, "\(name) 칸에서 창 높이가 바뀌었다(\(all.pixelsHigh) → \(shot.pixelsHigh))")
        }
        // 기준선: 같은 입력이면 사실상 같다 — 아래 '다르다'가 잡음이 아니라 거르기 때문이라는 뜻이다.
        #expect(pfDiffering(all, allTwin) < 40, "같은 입력 두 장이 다르다 — 비교가 뜻을 잃는다")
        #expect(pfDiffering(all, working) > 400, "근무중 칸을 골라도 화면이 그대로다")
        #expect(pfDiffering(working, away) > 400)
        #expect(pfDiffering(all, away) > 400)
        #expect(pfDiffering(away, awaySearch) > 400, "자리비움 칸에서 이름 찾기가 안 걸렸다")
        #expect(pfDiffering(awaySearch, workingNoMatch) > 400)
    }

    @Test("3명 패널(스크롤 없음): 칸을 바꿔도 목록 자리 그대로 · 근무 중인 사람이 없으면 빈 문구")
    func smallPanelAndEmptyState() throws {
        let threeAway = [pfPanelPool[2], pfPanelPool[3], pfPanelPool[4]]   // 지현 · 타팀 김서연 · 서준(집중, 퇴근)
        let all = try pfPanel(pfStore(people: threeAway, presence: .all))
        let emptyWorking = try pfPanel(pfStore(people: threeAway, presence: .working))
        let away = try pfPanel(pfStore(people: threeAway, presence: .away))
        pfSave(emptyWorking, "poke-filter-empty-working")
        #expect(emptyWorking.pixelsHigh == all.pixelsHigh, "아무도 안 남았을 때 창이 줄었다")
        #expect(away.pixelsHigh == all.pixelsHigh)
        #expect(pfDiffering(all, emptyWorking) > 400, "근무중 칸이 비었는데 화면이 그대로다")
        // 셋 다 자리비움이라 자리비움 칸은 전체와 목록이 같다 — 다른 것은 고른 칸 표시뿐이다(작은 차이).
        let selectorOnly = pfDiffering(all, away)
        #expect(selectorOnly > 0 && selectorOnly < pfDiffering(all, emptyWorking), "고른 칸 표시만 달라야 한다: \(selectorOnly)")

        // 사람이 없으면 칸도 안 선다 — 어떤 칸을 골라 뒀든 같은 화면('아직 다른 사용자가 없어요').
        let emptyAll = try pfPanel(pfStore(people: [], presence: .all))
        let emptyAway = try pfPanel(pfStore(people: [], presence: .away))
        #expect(emptyAway.pixelsHigh == emptyAll.pixelsHigh)
        #expect(pfDiffering(emptyAll, emptyAway) < 40, "빈 목록인데 근무 칸이 섰다")
    }

    @Test("빈 문구는 그 칸의 말이다 — 검색 줄 아래(목록 자리)만 비교해 근무중 빈 칸과 자리비움 '맞는 이름 없음'이 다르게 그려진다")
    func emptyLineWordingIsTheFiltersOwn() throws {
        let threeAway = [pfPanelPool[2], pfPanelPool[3], pfPanelPool[4]]
        // 검색 줄의 아래 끝 찾기: 목록이 같고 고른 칸만 다른 두 장(전체 · 자리비움 — 셋 다 자리비움)이 갈리는 마지막 픽셀 줄.
        let all = try pfPanel(pfStore(people: threeAway, presence: .all))
        let away = try pfPanel(pfStore(people: threeAway, presence: .away))
        let selectorRows = try #require(pfDifferingRows(all, away), "두 장 크기가 다르다")
        let cutoff = try #require(selectorRows.max(), "고른 칸 표시가 안 그려졌다")
        #expect(cutoff < all.pixelsHigh / 2, "고른 칸 표시가 패널 아래쪽까지 번졌다(\(cutoff)px)")

        // 둘 다 빈 목록이지만 칸의 말이 다르다: '지금 근무 중인 사람이 없어요' · '자리를 비운 사람 중엔 맞는 이름이 없어요'.
        let emptyWorking = try pfPanel(pfStore(people: threeAway, presence: .working))
        let emptyWorkingTwin = try pfPanel(pfStore(people: threeAway, presence: .working))
        let awayNoMatch = try pfPanel(pfStore(people: threeAway, presence: .away), query: "없는이름")
        pfSave(awayNoMatch, "poke-filter-away-nomatch")
        let noise = try #require(pfDifferingBelow(emptyWorking, emptyWorkingTwin, row: cutoff))
        let wording = try #require(pfDifferingBelow(emptyWorking, awayNoMatch, row: cutoff), "빈 칸 두 장의 창 높이가 다르다")
        // 기준선: 같은 입력 두 장은 목록 자리에서 같다 — 아래 차이가 잡음이 아니라 글자 때문이라는 뜻이다.
        #expect(noise < 40, "같은 입력 두 장이 목록 자리에서 다르다: \(noise)")
        // 칸의 말(emptyText)이 빠져 원래 문구('아직 다른 사용자가 없어요')로 돌아가면 두 장의 목록 자리가 같아진다.
        #expect(wording > 400, "근무중 빈 칸과 자리비움 '맞는 이름 없음'의 목록 자리가 같다 — 칸의 빈 문구가 안 그려진다: \(wording)")
        #expect(PokePresenceFilterText.empty(presence: .working, isSearching: false)
                != PokePresenceFilterText.empty(presence: .away, isSearching: true))
    }

    @Test("가려진 안 읽음 점: 칸 폭 · 줄 높이 그대로, 점은 그 칸 위에만 — 패널 높이도 그대로")
    func hiddenUnreadDotKeepsSize() throws {
        let plain = try pfBitmap(PokePresenceFilterBar(selection: .working, onSelect: { _ in }))
        let dotted = try pfBitmap(PokePresenceFilterBar(selection: .working, hidingUnread: [.away], onSelect: { _ in }))
        let plainTwin = try pfBitmap(PokePresenceFilterBar(selection: .working, onSelect: { _ in }))
        #expect(dotted.pixelsWide == plain.pixelsWide && dotted.pixelsHigh == plain.pixelsHigh, "점이 칸 크기를 바꿨다")
        #expect(pfDiffering(plain, plainTwin) < 8, "기준선: 같은 입력 두 장이 다르다")
        #expect(pfDiffering(plain, dotted) > 20, "점이 안 그려졌다")
        // 점은 자리비움 칸(오른쪽 끝 칸) 위에만 — 다른 바이트가 모두 고르개 오른쪽 1/3 안에 있다.
        if let pa = plain.bitmapData, let pb = dotted.bitmapData {
            let bytesPerPixel = plain.bitsPerPixel / 8
            var leftmost = Int.max
            for y in 0..<plain.pixelsHigh {
                for x in 0..<plain.pixelsWide {
                    let i = y * plain.bytesPerRow + x * bytesPerPixel
                    if (0..<bytesPerPixel).contains(where: { abs(Int(pa[i + $0]) - Int(pb[i + $0])) > 8 }) { leftmost = min(leftmost, x) }
                }
            }
            #expect(leftmost > plain.pixelsWide * 2 / 3, "점이 자리비움 칸 밖(\(leftmost)px / \(plain.pixelsWide)px)에 그려졌다")
        }
        let row = try pfBitmap(
            PokeSearchFilterRow(presence: .working, hidingUnread: [.away], onSelect: { _ in }) {
                PokeSearchBox(draft: .constant(""), rendered: .constant(nil), rendersPlainText: true)
            }
            .frame(width: PokeTitleRowWidthBudget.contentWidth)
        )
        pfSave(row, "poke-filter-row-hidden-unread")
        #expect(row.pixelsHigh == Int(PokeSearchBox.height * 2), "점이 검색 줄 높이를 바꿨다")

        // 패널: 근무중을 골라 둔 채 자리비움인 지현(u3)이 메시지를 보냈다 → 자리비움 칸에 점, 창 높이는 그대로.
        let store = pfStore(people: pfPanelPool, presence: .working)
        store.messageHistory = [
            MessageHistoryEntry(id: "pf-m1", peerUserID: "u3", peerName: "지현", peerAvatarURL: nil, body: "퇴근했어요",
                                createdAt: Date(timeIntervalSince1970: 1_789_999_940), isMine: false),
        ]
        #expect(store.unreadMessagePeerIDs == ["u3"], "전제: 지현의 메시지가 안 읽음이다")
        let sorted = PokePanelOrder.sorted(store.pokeDirectory, unreadMessagePeerIDs: store.unreadMessagePeerIDs,
                                           unreadPokePeerIDs: store.unreadPokePeerIDs)
        #expect(PokePresenceFilter.segmentsHidingUnread(sorted, selected: .working, unreadMessagePeerIDs: store.unreadMessagePeerIDs,
                                                        unreadPokePeerIDs: store.unreadPokePeerIDs) == [.away])
        let panel = try pfPanel(store)
        let baseline = try pfPanel(pfStore(people: pfPanelPool, presence: .all))
        pfSave(panel, "poke-filter-working-hidden-unread")
        #expect(panel.pixelsHigh == baseline.pixelsHigh, "가려진 안 읽음이 있을 때 창 높이가 바뀌었다")
    }
}

/// withObservationTracking 의 @Sendable onChange 에서 발화 여부를 받아 두는 상자. 알림은 MainActor 의 willSet 에서 동기로 온다.
private final class PFObservationFlag: @unchecked Sendable {
    var value = false
}

// MARK: - 소스 도우미(이 파일 전용 — 주석을 걷어 설명문이 단언에 걸리지 않게)

private func pfSource(_ relative: String) throws -> String {
    try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent(relative), encoding: .utf8)
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어 낸다(이 저장소의 다른 소스 계약 시험과 같은 규약).
private func pfStripComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}

/// `from` 부터 `to` 앞까지(없으면 끝까지).
private func pfRegion(_ source: String, from: String, to: String?) -> String? {
    guard let start = source.range(of: from) else { return nil }
    let tail = source[start.lowerBound...]
    guard let to else { return String(tail) }
    guard let end = tail.range(of: to, range: start.upperBound..<tail.endIndex) else { return nil }
    return String(tail[..<end.lowerBound])
}
