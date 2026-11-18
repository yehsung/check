import SwiftUI
#if ALKKAGI_PLAYGROUND
import AlkkagiCore
#else
import CheckCore
#endif

// MARK: - 콕 찌르기 목록 거르기 칸 '전체 · 근무중 · 자리비움' (2026-11-18)
//
// 제보(부산, 11-10): "콕 찌르기에서 '전체', '활동중', '활동안함' 이렇게 카테고리 되어있어서 사람들 구분할수 있는? 거 있으면 좋겠어요."
// → 대표 "고치기 — 다음 맥 판에 넣기".
//
// 규칙 넷:
//  · **빼기만 한다.** 목록 순서(안 읽음 → 근무중 → 이름 — `PokePanelOrder`)는 그대로이고, 칸은 그 결과에서 사람을 덜어 낼 뿐이다.
//    안 읽은 사람이 맨 위인 것(v0.3.65 네 무리 정렬)도 칸 안에서 그대로다.
//  · **이름 찾기와 함께 건다(AND).** 근무중 칸에서 "영"을 치면 근무 중이면서 이름이 맞는 사람만 남는다.
//  · **근무 여부만 본다.** 센터로 나누는 칸은 만들지 않는다(README "센터로 나누는 필터나 탭은 없습니다").
//  · **새 높이를 만들지 않는다.** 칸은 이름 찾기 칸과 **같은 줄** 오른쪽에 붙는다 — 목록 예산(`searchRowHeight`)이 그대로라
//    보이는 줄 수도, 팝오버 700pt 상한도 그대로다.
//
// ★ 근무중/자리비움은 행의 칩과 **같은 값**(`PokeDirectoryEntry.isWorking` — 서버 명부의 is_working)을 본다. 정렬의 근무 축
//   (`sortedForPokeDisplay`)도 같은 값이라, 근무중 칸은 정렬된 목록의 '근무중' 무리를 그대로 잘라 낸 것이다.
//   **집중은 칸을 바꾸지 않는다**: 집중은 근무 중에 켜는 일이라 칩이 '집중'인 사람도 근무 중이면 근무중 칸에 든다
//   (칩은 집중을 근무중보다 앞에 그려 근무 여부를 가린다 — 그 사람이 지금 일하는 중인지는 칸이 말해 준다).
//   집중을 켜 둔 채 퇴근한 사람(2단은 끌 때까지 남는다)은 근무 중이 아니므로 자리비움 칸이다 — 칩은 그때도 '집중'이다.

/// 근무 칸 셋. 앱이 켜져 있는 동안 스토어가 들고 있고(`WorkTimerStore.pokePresenceFilter`), 로그아웃하면 전체로 돌아간다.
enum PokePresenceFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case working
    case away

    /// 칸 글자. 근무중 · 자리비움은 행 칩의 낱말과 **같다** — 같은 사정을 두 자리가 다른 말로 부르면 다른 일로 읽힌다.
    var label: String {
        switch self {
        case .all: return PokePresenceFilterText.allLabel
        case .working: return PokePresenceFilterText.workingLabel
        case .away: return PokePresenceFilterText.awayLabel
        }
    }

    /// 툴팁 · 보이스오버 말(같은 문장).
    var help: String {
        switch self {
        case .all: return PokePresenceFilterText.allHelp
        case .working: return PokePresenceFilterText.workingHelp
        case .away: return PokePresenceFilterText.awayHelp
        }
    }

    /// 이 칸에 드는 사람인가. 근무 여부 하나만 본다(위 머리 주석 — 집중은 칸을 바꾸지 않는다).
    func admits(_ entry: PokeDirectoryEntry) -> Bool {
        switch self {
        case .all: return true
        case .working: return entry.isWorking
        case .away: return !entry.isWorking
        }
    }
}

extension WorkTimerStore {
    /// 거르기 칸 고르기. 같은 값은 쓰지 않는다 — @Observable 무효화로 찌르기 패널 body 가 헛돌지 않게.
    /// 네트워크도 폴링도 건드리지 않는다(화면에서 빼기만 하는 값이다).
    func selectPokePresenceFilter(_ filter: PokePresenceFilter) {
        guard pokePresenceFilter != filter else { return }
        pokePresenceFilter = filter
    }
}

/// 칸 글자 · 안내 문장(재사용 문구는 한 곳에).
enum PokePresenceFilterText {
    static let allLabel = "전체"
    static let workingLabel = "근무중"
    static let awayLabel = "자리비움"

    static let allHelp = "모두 보기"
    static let workingHelp = "근무 중인 사람만 보기(집중 포함)"
    static let awayHelp = "자리를 비운 사람만 보기"
    /// 칸 묶음 전체의 보이스오버 이름.
    static let groupLabel = "목록 거르기"

    /// 근무중 칸에 아무도 없을 때.
    static let noneWorking = "지금 근무 중인 사람이 없어요"
    /// 자리비움 칸에 아무도 없을 때.
    static let noneAway = "자리를 비운 사람이 없어요"
    /// 근무중 칸에서 찾았는데 아무도 안 맞을 때.
    static let noMatchWorking = "근무 중인 사람 중엔 맞는 이름이 없어요"
    /// 자리비움 칸에서 찾았는데 아무도 안 맞을 때.
    static let noMatchAway = "자리를 비운 사람 중엔 맞는 이름이 없어요"

    /// 걸러서 아무도 안 남았을 때의 한 줄. 전체 칸에서 찾다가 비면 이름 찾기의 문장 그대로다(`PokeDirectorySearch.noMatch`).
    /// 전체 칸 · 안 찾는 중이면 nil — 거르는 것이 없으니 원래 빈 목록 문구(`PokeDirectoryEmptyMessage`)가 말한다.
    static func empty(presence: PokePresenceFilter, isSearching: Bool) -> String? {
        switch (presence, isSearching) {
        case (.all, false): return nil
        case (.all, true): return PokeDirectorySearch.noMatch
        case (.working, false): return noneWorking
        case (.working, true): return noMatchWorking
        case (.away, false): return noneAway
        case (.away, true): return noMatchAway
        }
    }
}

/// 찌르기 목록에 **보일 사람**(순수 · 결정적 — 시험이 값으로 되묻는 자리). 이름 찾기와 근무 칸을 함께 건다.
struct PokeDirectoryNarrowing: Equatable {
    /// 보일 사람. 받은 순서 그대로다(빼기만 한다).
    let rows: [PokeDirectoryEntry]
    /// 거르는 중인가(이름 찾기든 근무 칸이든). 그동안 목록 자리는 **거르기 전 높이**를 붙든다(`PokeSearchListHeight`) —
    /// 칸을 바꾸거나 한 글자 칠 때마다 팝오버가 줄었다 늘었다 하지 않게.
    let isNarrowed: Bool
    /// 걸러서 비었을 때의 한 줄. nil 이면 거르는 것이 없다 — 원래 빈 목록 문구를 쓴다.
    let emptyText: String?

    /// `sorted` 는 이미 정렬된 목록이다(`PokePanelOrder`). 사람이 없으면 칸도 검색 칸도 안 서므로 거르는 중이 아니다 —
    /// 빈 목록 문구('아직 다른 사용자가 없어요' · 불러오는 중)를 그대로 둔다.
    static func apply(_ sorted: [PokeDirectoryEntry], query: String, presence: PokePresenceFilter) -> PokeDirectoryNarrowing {
        guard !sorted.isEmpty else { return PokeDirectoryNarrowing(rows: [], isNarrowed: false, emptyText: nil) }
        let isSearching = !PokeDirectorySearch.SearchKey(query).isEmpty
        let inPresence = presence == .all ? sorted : sorted.filter(presence.admits)
        let rows = isSearching ? PokeDirectorySearch.filter(inPresence, query: query) : inPresence
        return PokeDirectoryNarrowing(
            rows: rows,
            isNarrowed: isSearching || presence != .all,
            emptyText: PokePresenceFilterText.empty(presence: presence, isSearching: isSearching)
        )
    }
}

/// 이름 찾기 칸과 근무 칸을 **한 줄**에 세운다. 줄 높이는 검색 칸 높이 그대로다(`PokeSearchBox.height`) —
/// 칸을 아래 새 줄로 내리면 목록이 한 줄 더 줄어든다(이름 찾기 칸이 이미 7 → 6 줄로 한 줄을 썼다).
struct PokeSearchFilterRow<Search: View>: View {
    /// 검색 칸과 근무 칸 사이.
    static var spacing: CGFloat { 6 }

    let presence: PokePresenceFilter
    let onSelect: (PokePresenceFilter) -> Void
    @ViewBuilder let search: () -> Search

    var body: some View {
        HStack(spacing: Self.spacing) {
            search()
            PokePresenceFilterBar(selection: presence, onSelect: onSelect)
        }
        .frame(height: PokeSearchBox.height)
    }
}

/// 근무 칸 셋을 붙인 작은 고르개. 검색 칸과 같은 테두리 · 같은 높이라 한 줄로 읽힌다.
/// AppKit `Picker(.segmented)` 를 안 쓰는 이유: 팝오버의 다른 칩들과 결이 달라지고, 렌더 시험(ImageRenderer)이 AppKit 칸을
/// 노란 상자로 그려 '입력칸 수' 시험(`pokePanelHasNoInlineComposerAnymore`)이 칸을 하나 더 센다.
struct PokePresenceFilterBar: View {
    /// 고르개 전체 폭의 상한(pt). 검색 칸이 '이름으로 찾기' + 지우기 단추를 담을 폭을 남기는지 시험이 이 값으로 잰다.
    static let maxWidth: CGFloat = 132
    /// 바깥 테두리와 칸 사이.
    static let inset: CGFloat = 2
    /// 칸 하나의 좌우 여백.
    static let segmentPadding: CGFloat = 6

    let selection: PokePresenceFilter
    let onSelect: (PokePresenceFilter) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PokePresenceFilter.allCases, id: \.self) { filter in
                segment(filter)
            }
        }
        .padding(Self.inset)
        .frame(height: PokeSearchBox.height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PokePresenceFilterText.groupLabel)
    }

    private func segment(_ filter: PokePresenceFilter) -> some View {
        let isSelected = filter == selection
        return Button {
            // 같은 칸을 다시 눌러도 아무 일도 없다(스토어도 같은 값은 안 쓴다 — 패널 body 를 헛돌리지 않게).
            if !isSelected { onSelect(filter) }
        } label: {
            Text(filter.label)
                .font(.caption2.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? CheckTheme.accent : CheckTheme.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, Self.segmentPadding)
                .frame(maxHeight: .infinity)
                // 고른 칸은 [모두 읽음]과 같은 옅은 파랑 바탕 · 파랑 글자다(흰 글자 + 파랑 채움은 10pt 글자에 대비가 모자라다).
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? CheckTheme.accent.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .checkTooltip(filter.help)
        .accessibilityLabel(filter.help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
