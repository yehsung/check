import CheckCore
import Testing
@testable import CheckMobileKit

/// v0.3.65(맥 먼저): 코어 `sortedForPokeDisplay(unreadPeerIDs:workKnown:)` 가 기본값 없는 필수 인자로 바뀌었다(명세 §3.0).
/// 폰 1.0.13: `MessagesDirectoryRules.filter` 도 `unreadPeerIDs` 를 **기본값 없이** 받는다(한 겹 위에서 `= []` 로
/// 되살리면 같은 사고가 난다). 안 읽음이 빈 집합이면 순서는 예전 그대로 — 이 시험이 그 "그대로"를 잰다
/// (안 읽음이 있을 때의 순서는 `MessagesPokeLogStoreTests.directoryUsesTheSameUnreadSet`).
///
/// 기존 사람 찾기 시험(`MessagesRulesTests.directoryFilter`)은 근무 중이 이름도 앞서는 픽스처라(한국어 로캘은 한글을 라틴 앞에 둔다)
/// 근무 축을 빼도 같은 순서가 나와 이 회귀를 못 잡는다. 여기는 **이름이 앞서는 자리비움**을 둔다.
@Suite struct V0365PhoneDirectoryOrderTests {
    static func person(_ id: String, _ name: String, working: Bool) -> PokeDirectoryEntry {
        [PokeDirectoryRow(userId: id, displayName: name, avatarUrl: nil, isWorking: working)].toPokeDirectoryEntries()[0]
    }

    @Test("폰 사람 찾기: 빈 검색어 · 초성 검색 모두 근무 중 먼저 → 이름순(이름이 앞서는 자리비움이 근무 중 앞으로 오지 않는다)")
    func phoneSearchKeepsWorkFirst() {
        let entries = [Self.person("1", "가람", working: false), Self.person("2", "하린", working: true),
                       Self.person("3", "나래", working: false), Self.person("4", "다온", working: true)]
        #expect(MessagesDirectoryRules.filter(entries, query: "", unreadPeerIDs: []).map(\.name) == ["다온", "하린", "가람", "나래"])
        // 초성 "ㄹ": 가람(ㄱㄹ) · 하린(ㅎㄹ) · 나래(ㄴㄹ) — 거른 뒤에도 같은 순서.
        #expect(MessagesDirectoryRules.filter(entries, query: "ㄹ", unreadPeerIDs: []).map(\.name) == ["하린", "가람", "나래"])
    }
}
