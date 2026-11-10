import SwiftUI
#if ALKKAGI_PLAYGROUND
import AlkkagiCore
#else
import CheckCore
#endif

// MARK: - 콕 찌르기 이름 찾기 (2026-11-10)
//
// 제보(맥 0.3.81): "콕 찌르기에서 검색기능있으면 좋겠어요 / 사람 쉽게 찾고싶어요" → 대표 "둘 다 지금 시작".
// 찌르기 창 목록 위에 검색 칸 하나. 이름 일부를 치면 목록이 **그 자리에서** 걸러진다. 순서는 원래 목록 순서
// (안 읽음 → 근무중 → 이름 — `PokePanelOrder`) 그대로이고, 거르기는 그 결과에서 빼기만 한다.
//
// ★ 한글은 **치는 중인 글자까지** 본다. 맥 입력기는 마지막 음절을 표시 글자(marked text)로 띄워 두고, 그 구간에는
//   바인딩이 안 올라온다(`CheckTextEditor.swift` 머리 주석의 실측). 바인딩만 보면 "부"를 쳐도 아무것도 안 걸러지고
//   한 음절씩 늦게 따라온다 — 그래서 칸은 **뷰에 그려진 글자**(`onRenderedTextChange`)를 넘기고, 비교는 자모로 풀어서 한다.
//   치는 중 글자는 "ㅂ" → "부" → "붕" → "부이" → "부잉"처럼 지나가는데, 자모로 풀면 모두 "부잉…"의 앞부분이라
//   목록이 중간에 비었다가 다시 차는 깜빡임이 없다.

/// 이름 찾기 규칙(순수 · 결정적 — 시험이 값으로 되묻는 자리).
enum PokeDirectorySearch {
    /// 검색 칸 안내 글자.
    static let placeholder = "이름으로 찾기"
    /// 지우기 단추 말.
    static let clearHelp = "검색어 지우기"
    /// 걸러서 아무도 안 남았을 때.
    static let noMatch = "맞는 이름이 없어요"

    /// 원래 순서를 지킨 채 이름이 맞는 사람만 남긴다. 검색어가 비면(공백뿐이어도) **받은 그대로** 돌려준다.
    static func filter(_ entries: [PokeDirectoryEntry], query: String) -> [PokeDirectoryEntry] {
        let key = SearchKey(query)
        guard !key.isEmpty else { return entries }
        return entries.filter { key.matches(name: $0.name) }
    }

    /// 한 사람만 볼 때(시험 · 다른 화면).
    static func matches(name: String, query: String) -> Bool {
        let key = SearchKey(query)
        return key.isEmpty || key.matches(name: name)
    }

    /// 검색어를 한 번만 풀어 둔다 — 목록 77명을 돌 때마다 검색어를 다시 풀지 않게.
    struct SearchKey {
        let jamo: String
        /// 검색어가 **자음만**인가("ㅂㅇ") — 그러면 이름의 첫소리 줄에서도 찾는다(초성 검색).
        let isConsonantsOnly: Bool

        init(_ query: String) {
            let folded = HangulSearchFold.fold(query)
            jamo = HangulSearchFold.jamo(folded)
            isConsonantsOnly = !folded.isEmpty && folded.unicodeScalars.allSatisfy(HangulSearchFold.isCompatibilityConsonant)
        }

        var isEmpty: Bool { jamo.isEmpty }

        func matches(name: String) -> Bool {
            let folded = HangulSearchFold.fold(name)
            if HangulSearchFold.jamo(folded).contains(jamo) { return true }
            return isConsonantsOnly && HangulSearchFold.initials(folded).contains(jamo)
        }
    }
}

/// 한글 · 영문 비교용 접기. 공백을 빼고, 영문은 소문자로, 한글 음절은 자모(호환 자모 낱자)로 푼다.
enum HangulSearchFold {
    private static let syllableBase: UInt32 = 0xAC00
    private static let syllableLast: UInt32 = 0xD7A3
    private static let medialCount: UInt32 = 21
    private static let finalCount: UInt32 = 28

    /// 첫소리 19.
    private static let initialJamo: [String] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]
    /// 가운뎃소리 21 — 겹모음은 치는 순서대로 풀어 둔다(ㅘ = ㅗ + ㅏ). "보" 를 치는 중에도 "봐"가 걸리게.
    private static let medialJamo: [String] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅗㅏ", "ㅗㅐ", "ㅗㅣ", "ㅛ", "ㅜ", "ㅜㅓ", "ㅜㅔ", "ㅜㅣ",
        "ㅠ", "ㅡ", "ㅡㅣ", "ㅣ"
    ]
    /// 끝소리 28(0 = 없음) — 겹받침도 치는 순서대로 푼다(ㄺ = ㄹ + ㄱ). "달" 을 치는 중에도 "닭"이 걸리게.
    private static let finalJamo: [String] = [
        "", "ㄱ", "ㄲ", "ㄱㅅ", "ㄴ", "ㄴㅈ", "ㄴㅎ", "ㄷ", "ㄹ", "ㄹㄱ", "ㄹㅁ", "ㄹㅂ", "ㄹㅅ", "ㄹㅌ", "ㄹㅍ", "ㄹㅎ", "ㅁ",
        "ㅂ", "ㅂㅅ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]
    /// 입력기가 낱자로 띄우는 겹자모(호환 자모)도 같은 꼴로 푼다.
    private static let compoundCompatibility: [Unicode.Scalar: String] = [
        "ㄳ": "ㄱㅅ", "ㄵ": "ㄴㅈ", "ㄶ": "ㄴㅎ", "ㄺ": "ㄹㄱ", "ㄻ": "ㄹㅁ", "ㄼ": "ㄹㅂ", "ㄽ": "ㄹㅅ", "ㄾ": "ㄹㅌ",
        "ㄿ": "ㄹㅍ", "ㅀ": "ㄹㅎ", "ㅄ": "ㅂㅅ", "ㅘ": "ㅗㅏ", "ㅙ": "ㅗㅐ", "ㅚ": "ㅗㅣ", "ㅝ": "ㅜㅓ", "ㅞ": "ㅜㅔ",
        "ㅟ": "ㅜㅣ", "ㅢ": "ㅡㅣ"
    ]

    /// 공백 빼기 · 소문자 · NFC(서버 이름과 입력기 글자가 같은 꼴이 되게).
    static func fold(_ text: String) -> String {
        let composed = text.precomposedStringWithCanonicalMapping.lowercased()
        return String(String.UnicodeScalarView(composed.unicodeScalars.filter { !$0.properties.isWhitespace }))
    }

    /// 한글 음절을 자모 낱자로 푼 글. 한글이 아닌 글자는 그대로 둔다.
    static func jamo(_ folded: String) -> String {
        var out = ""
        out.reserveCapacity(folded.unicodeScalars.count * 3)
        for scalar in folded.unicodeScalars {
            if let parts = syllableParts(scalar) {
                out += initialJamo[parts.initial] + medialJamo[parts.medial] + finalJamo[parts.final]
            } else if let split = compoundCompatibility[scalar] {
                out += split
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// 이름의 첫소리 줄("부잉아잉" → "ㅂㅇㅇㅇ"). 한글이 아닌 글자는 그대로 둔다.
    static func initials(_ folded: String) -> String {
        var out = ""
        for scalar in folded.unicodeScalars {
            if let parts = syllableParts(scalar) {
                out += initialJamo[parts.initial]
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// 호환 자모 자음(ㄱ U+3131 ~ ㅎ U+314E)인가.
    static func isCompatibilityConsonant(_ scalar: Unicode.Scalar) -> Bool {
        (0x3131...0x314E).contains(scalar.value)
    }

    private static func syllableParts(_ scalar: Unicode.Scalar) -> (initial: Int, medial: Int, final: Int)? {
        guard (syllableBase...syllableLast).contains(scalar.value) else { return nil }
        let index = scalar.value - syllableBase
        let initial = index / (medialCount * finalCount)
        let medial = (index % (medialCount * finalCount)) / finalCount
        let final = index % finalCount
        return (Int(initial), Int(medial), Int(final))
    }
}

/// 찌르기 목록 위의 검색 칸. 테두리 · 돋보기 · 안내 글자 · 지우기 단추는 이 뷰가 그리고, 글자는 `CheckTextEditor`
/// (한글 조합을 지키는 공용 칸)가 받는다 — SwiftUI `TextField` 는 치는 중인 음절을 바깥에 안 알려 줘서 한 음절씩 늦는다.
struct PokeSearchBox: View {
    /// 칸 높이. 글자 자리(`CheckEditorMetrics.inset` 세로 7 + caption 한 줄 13)가 위아래 고르게 들어가는 최소치.
    static let height: CGFloat = 26

    /// 확정된 글자(편집기 바인딩).
    @Binding var draft: String
    /// 뷰에 그려진 글자(치는 중 음절 포함). 거르기는 이 값을 쓴다.
    @Binding var rendered: String?
    /// 스냅샷 전용: AppKit 칸 대신 같은 자리에 글자만 그린다(ImageRenderer 는 AppKit 칸을 노란 상자로 그린다).
    var rendersPlainText: Bool = false

    private var shownText: String { rendered ?? draft }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
                .padding(.leading, 9)
                .accessibilityHidden(true)
            ZStack(alignment: .topLeading) {
                if shownText.isEmpty {
                    Text(PokeDirectorySearch.placeholder)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, CheckEditorMetrics.inset.width)
                        .padding(.vertical, CheckEditorMetrics.inset.height)
                        .allowsHitTesting(false)
                }
                if rendersPlainText {
                    Text(draft)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, CheckEditorMetrics.inset.width)
                        .padding(.vertical, CheckEditorMetrics.inset.height)
                } else {
                    // Enter 는 아무것도 안 보낸다(못 보내는 칸) — 조합 중이면 확정만 한다(`CheckEditorReturnKey`).
                    CheckTextEditor(
                        text: $draft,
                        sendsOnReturn: true,
                        canSendNow: { false },
                        // 거르는 글자가 실제로 바뀔 때만 상태를 건드린다. 칸이 처음 서면 "" 를 한 번 알리는데(`apply()` 의
                        // 다음 턴 보고), 그때 nil → "" 로 바꾸면 찌르기 패널 body 가 초침 사이에 한 번 더 돈다(V0238 계측).
                        onRenderedTextChange: { newValue in
                            if (rendered ?? draft) != newValue { rendered = newValue }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(PokeDirectorySearch.placeholder)
                }
            }
            // 돋보기와 글자 사이가 칸 안쪽 여백(10)만큼 벌어지지 않게 조금 당긴다.
            .padding(.leading, -4)
            if !shownText.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(width: 22, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .checkTooltip(PokeDirectorySearch.clearHelp)
                .accessibilityLabel(PokeDirectorySearch.clearHelp)
            }
        }
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
    }

    /// 조합 중인 음절을 먼저 확정한다 — 확정 없이 비우면 칸이 조합 중이라 되쓰기를 건너뛰어(`apply()` 의 조합 가드)
    /// 글자는 남고 목록만 풀리는 어긋남이 생긴다.
    private func clear() {
        _ = CheckEditorTextView.commitActiveComposition()
        draft = ""
        rendered = ""
    }
}

/// 찾는 동안의 목록 높이(순수 — 시험이 값으로 되묻는 자리).
///
/// 목록 자리는 원래 사람 수만큼 자라고 상한(`listCapHeight`)에서 멈춘다. 찾을 때 그 규칙을 그대로 두면 한 글자 칠 때마다
/// 걸러진 수만큼 팝오버가 줄었다 늘었다 한다(창은 위가 고정이라 아래 버튼들이 손 밑에서 오르내린다). 그래서 찾는 동안은
/// **찾기 전 목록 높이**(상한 이하)를 붙들고, 걸러진 줄은 그 안 위쪽에 앉힌다. 안 찾을 때는 nil — 지금 그대로다.
enum PokeSearchListHeight {
    static func held(isSearching: Bool, shown: CGFloat, unfiltered: CGFloat, cap: CGFloat) -> CGFloat? {
        guard isSearching else { return nil }
        return max(shown, min(unfiltered, cap))
    }
}
