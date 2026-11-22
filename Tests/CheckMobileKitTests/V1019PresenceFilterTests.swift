@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.19 — 사람 찾기 거르기 칸 '전체 · 근무중 · 자리비움'(맥 0.3.87 `PokePresenceFilter` 의 폰 짝 · 대표 #d_xygj8oZRFlfH 9번).
@MainActor
@Suite("폰 1.0.19 — 거르기 칸", .serialized)
struct V1019PresenceFilterTests {
    private static func entry(_ id: String, working: Bool) -> PokeDirectoryEntry {
        PokeDirectoryEntry(userID: id, name: id, avatarURL: nil, isWorking: working)
    }

    @Test("규칙: 근무 여부 하나만 본다 — 전체는 모두 · 근무중은 근무 중 · 자리비움은 그 나머지(둘이 겹치지도 빠뜨리지도 않는다)")
    func admits() {
        let on = Self.entry("on", working: true)
        let off = Self.entry("off", working: false)
        #expect(MessagesPresenceFilter.all.admits(on) && MessagesPresenceFilter.all.admits(off))
        #expect(MessagesPresenceFilter.working.admits(on) && !MessagesPresenceFilter.working.admits(off))
        #expect(!MessagesPresenceFilter.away.admits(on) && MessagesPresenceFilter.away.admits(off))
    }

    @Test("글자: 맥 0.3.87 과 한 글자도 다르지 않다 — 칸 · 빈 문구 넷 · 전체는 원래 말에 맡긴다")
    func copy() {
        #expect(MessagesPresenceFilter.allCases.map(\.label) == ["전체", "근무중", "자리비움"])
        #expect(MessagesPresenceFilterText.empty(presence: .working, isSearching: false) == "지금 근무 중인 사람이 없어요")
        #expect(MessagesPresenceFilterText.empty(presence: .away, isSearching: false) == "자리를 비운 사람이 없어요")
        #expect(MessagesPresenceFilterText.empty(presence: .working, isSearching: true) == "근무 중인 사람 중엔 맞는 이름이 없어요")
        #expect(MessagesPresenceFilterText.empty(presence: .away, isSearching: true) == "자리를 비운 사람 중엔 맞는 이름이 없어요")
        #expect(MessagesPresenceFilterText.empty(presence: .all, isSearching: true) == nil)
        #expect(MessagesPresenceFilterText.empty(presence: .all, isSearching: false) == nil)
    }

    @Test("스토어: 빼기만 · 순서 그대로 · 이름 찾기와 AND · 로그아웃하면 전체 — 네트워크는 안 부른다")
    func store() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(MessagesPokeLogStoreTests.directoryJSON([
                ("peer-ga", "가나", false), ("peer-na", "나나", true), ("peer-da", "다나", true), ("peer-ra", "라마", false),
            ]))
        }
        defer { h.tearDown() }
        h.store.loadDirectory(force: true)
        await h.settle()
        let all = h.store.filteredDirectory(query: "").map(\.name)
        #expect(all == ["나나", "다나", "가나", "라마"], "전제: 근무 중 먼저 → 이름순")
        #expect(h.store.directoryPresenceFilter == .all)
        #expect(h.store.visibleDirectory(query: "").map(\.name) == all)

        h.store.selectDirectoryPresenceFilter(.working)
        #expect(h.store.visibleDirectory(query: "").map(\.name) == ["나나", "다나"])
        #expect(h.store.visibleDirectory(query: "나나").map(\.name) == ["나나"], "이름 찾기와 AND 가 아니다")
        #expect(h.store.visibleDirectory(query: "ㄱ").isEmpty, "자리비움인 가나가 근무중 칸에 섰다")
        h.store.selectDirectoryPresenceFilter(.away)
        #expect(h.store.visibleDirectory(query: "").map(\.name) == ["가나", "라마"])
        #expect(h.store.visibleDirectory(query: "다").isEmpty)

        h.store.reset()
        #expect(h.store.directoryPresenceFilter == .all, "로그아웃 뒤에도 칸이 남았다")
        h.expectNoForbiddenCalls()
    }

    @Test("배선: 시트가 보일 사람(이름 찾기 + 칸)을 그리고 · 칸 줄은 스토어 고르기로 · 빈 문구는 칸의 말 먼저 — 주석을 걷고 본다")
    func wiring() throws {
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesNewConversationSheet.swift").filter { !$0.isWhitespace }
        #expect(sheet.contains("letpeople=store.visibleDirectory(query:query)"))
        #expect(!sheet.contains("store.filteredDirectory(query:query)"), "시트가 칸을 안 거친 목록을 그린다")
        #expect(sheet.contains("set:{store.selectDirectoryPresenceFilter($0)}"))
        #expect(sheet.contains(".pickerStyle(.segmented)"))
        #expect(sheet.contains("MessagesPresenceFilterText.empty(presence:presence,isSearching:isSearching)"))
    }
}
