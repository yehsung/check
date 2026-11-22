import CheckCore
import Foundation

// MARK: - 사람 찾기 거르기 칸 '전체 · 근무중 · 자리비움' (폰 1.0.19 — 맥 0.3.87 `PokePresenceFilter` 의 폰 짝)
//
// 제보(부산, 11-10): "콕 찌르기에서 '전체', '활동중', '활동안함' 이렇게 카테고리 되어있어서 사람들 구분할수 있는? 거 있으면 좋겠어요."
// → 맥 0.3.87(찌르기 목록 이름 찾기 칸 옆) → 대표 #d_xygj8oZRFlfH "추천안대로 한 판(1.0.19)에 전부"(9번 거르기 칸).
//
// 폰 자리는 메시지 탭 '새 대화'의 사람 찾기다(폰의 찌르기 · 메시지 상대 고르기가 이 시트 하나다 — 이름 · 초성 찾기는 11-03 부터 있다).
// 맥과 같은 규칙 넷:
//  · **빼기만 한다.** 순서(안 읽음 → 근무 중 → 이름 — `MessagesDirectoryRules.filter`)는 그대로, 칸은 그 결과에서 사람을 덜어 낼 뿐이다.
//  · **이름 찾기와 함께 건다(AND).**
//  · **근무 여부만 본다**(서버 명부의 is_working — 줄의 초록 점 · '근무 중' 묶음과 같은 값). 센터 칸은 만들지 않는다.
//  · **집중은 칸을 바꾸지 않는다** — 근무 중 집중은 근무중 칸, 집중 켠 채 퇴근은 자리비움 칸(맥 머리 주석 그대로).
// 맥과 다른 것 하나: 가려진 안 읽음 점은 없다 — 폰 시트는 대화를 **새로 여는** 자리이고, 안 읽은 대화는 메시지 목록이 늘 보여 준다.
// 고른 칸은 앱이 켜져 있는 동안 스토어가 들고 있고(`MessagesStore.directoryPresenceFilter`), 로그아웃(`reset`)하면 전체로 돌아간다.

/// 근무 칸 셋(맥 `PokePresenceFilter` 와 같은 값 · 같은 글자).
package enum MessagesPresenceFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case working
    case away

    /// 칸 글자 — 맥과 같다.
    package var label: String {
        switch self {
        case .all: return MessagesPresenceFilterText.allLabel
        case .working: return MessagesPresenceFilterText.workingLabel
        case .away: return MessagesPresenceFilterText.awayLabel
        }
    }

    /// 이 칸에 드는 사람인가. 근무 여부 하나만 본다.
    package func admits(_ entry: PokeDirectoryEntry) -> Bool {
        switch self {
        case .all: return true
        case .working: return entry.isWorking
        case .away: return !entry.isWorking
        }
    }
}

/// 칸 글자 · 빈 문구(맥 `PokePresenceFilterText` 와 한 글자도 다르지 않다).
package enum MessagesPresenceFilterText {
    package static let allLabel = "전체"
    package static let workingLabel = "근무중"
    package static let awayLabel = "자리비움"
    /// 칸 묶음의 보이스오버 이름.
    package static let groupLabel = "목록 거르기"

    package static let noneWorking = "지금 근무 중인 사람이 없어요"
    package static let noneAway = "자리를 비운 사람이 없어요"
    package static let noMatchWorking = "근무 중인 사람 중엔 맞는 이름이 없어요"
    package static let noMatchAway = "자리를 비운 사람 중엔 맞는 이름이 없어요"

    /// 걸러서 아무도 안 남았을 때의 제목. 전체 칸이면 nil — 원래 빈 문구(이름 찾기 · 빈 명부)가 말한다.
    package static func empty(presence: MessagesPresenceFilter, isSearching: Bool) -> String? {
        switch (presence, isSearching) {
        case (.all, _): return nil
        case (.working, false): return noneWorking
        case (.working, true): return noMatchWorking
        case (.away, false): return noneAway
        case (.away, true): return noMatchAway
        }
    }
}
