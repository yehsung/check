import AppKit
import SwiftUI

// MARK: - 캐릭터 선택 패널 (v0.3.15)
//
// 팝오버 **안의** 하위 패널이다. 별도 창도 설정 안도 아니다(2026-09-13 사용자 확정) — 고르는 대상이
// 이 팝오버 헤더에 떠 있는 바로 그 마스코트라, 고르는 화면이 다른 창에 있으면 결과를 보려고 창을 오가야 한다.
//
// ★ **범위는 선택뿐이다.** 상점(가격·잠금·구매)은 이번에 만들지 않는다 — 다음 단계에서 이 카드 위에
//   잠금·가격이 얹힌다(DECISIONS.md 의 "재화·상점" 항목: 사장님 테스트 → 바로 상점).
//   그래서 지금은 **전원이 모든 캐릭터를 고를 수 있다**(의도한 중간 상태, 사용자 확인).
//   설정 창의 칩 줄(`CheckCharacterSettingsRow`)은 `ultraUnlimited` 게이트를 단 채 **그대로 남아 있다** —
//   관리자용 빠른 경로이고, 그쪽 게이트를 건드리면 V0316CharacterPickerTests 가 빨개진다.

/// 캐릭터 선택 패널 본문. 팀 카드 자리를 대신 쓰고, [뒤로]로 홈(팀 목록)에 돌아간다.
///
/// ★ **카드는 `Button` + `Image` 로만 만든다.** 이 저장소의 렌더 검증은 `ImageRenderer` 로 잘림·겹침을
///   픽셀로 보는데 `Menu`·`Picker`·`TextField(axis:)` 는 그 렌더러에서 **노란 상자**로 그려진다(실측 —
///   그 자리는 픽셀 커버리지가 0이라 색 결함이 8일간 안 잡혔다). 격자를 `LazyVGrid` 로 짜지 않은 것도
///   같은 결의 조심이다: 지연 컨테이너는 렌더러가 보이는 자리를 못 정해 빈 칸으로 굳을 수 있어,
///   행을 직접 끊어 `HStack` 으로 쌓는다(캐릭터 수가 한 자릿수라 지연으로 아낄 것도 없다).
struct CheckCharacterPanel: View {
    /// 이 빌드가 세울 수 있는 캐릭터 전부. **순서의 주인은 카탈로그다**(`allIDs` 가 아잉 먼저, 나머지는 id 정렬).
    let catalog: CharacterCatalog
    /// 영속 선택. 저장·읽기의 규약은 전부 저쪽에 있다(모르는 id 는 아잉으로 접고, 저장은 거절될 수 있다).
    let selection: CharacterSelection
    /// 되그릴 쪽(메뉴바 아이콘·오버레이)에 알리는 통로. 테스트는 자기 인스턴스를 넣어 전역을 안 건드린다.
    var broadcast: CharacterSelectionBroadcast = .shared
    /// 목록 위쪽에서 배너/목표 편집 행이 먹은 높이(pt). 그만큼 격자 표시 높이를 깎아 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    /// 스냅샷 전용: 넘치는 격자를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    let onBack: () -> Void

    /// 눌린 카드를 즉시 옮기기 위한 로컬 거울. 진짜 값은 `selection` 에 있다 —
    /// 저장이 **거절되면 여기도 안 움직인다**(화면만 바뀌었다가 조용히 되돌아가는 거짓말을 만들지 않는다).
    @State private var selectedID: String

    init(
        catalog: CharacterCatalog,
        selection: CharacterSelection,
        broadcast: CharacterSelectionBroadcast = .shared,
        extraChromeHeight: CGFloat = 0,
        clipsOverflowInsteadOfScroll: Bool = false,
        onBack: @escaping () -> Void
    ) {
        self.catalog = catalog
        self.selection = selection
        self.broadcast = broadcast
        self.extraChromeHeight = extraChromeHeight
        self.clipsOverflowInsteadOfScroll = clipsOverflowInsteadOfScroll
        self.onBack = onBack
        _selectedID = State(initialValue: selection.selectedID)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("캐릭터")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            PanelDivider()
            Text("오버레이와 메뉴바에 나오는 내 캐릭터예요.")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                // 좁혀도 말줄임 대신 줄바꿈(이 앱의 설명 줄 규약).
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            grid
        }
        .padding(12)
        .panelStyle()
    }

    // MARK: - 격자

    /// 카드 치수는 전부 `CharacterPanelGridBudget` 이 갖는다 — 높이 예산을 재는 쪽과 카드를 그리는 쪽이
    /// 같은 숫자를 봐야 하는데, 예산 계산은 뷰 밖(nonisolated 순수 함수)에 있어야 테스트가 화면 없이 잰다.
    private static let columns = CharacterPanelGridBudget.columns
    private static let cardSpacing = CharacterPanelGridBudget.cardSpacing
    private static let cardHeight = CharacterPanelGridBudget.cardHeight

    /// 카드를 행 단위로 끊는다. 마지막 행이 모자라면 **빈 칸을 채워** 카드 폭을 모든 행에서 같게 한다
    /// (안 채우면 두 장짜리 마지막 행에서 카드가 혼자 넓어져 격자가 아니라 목록처럼 보인다).
    private var rows: [[String?]] {
        let ids = catalog.allIDs
        var out: [[String?]] = []
        var index = 0
        while index < ids.count {
            let slice = ids[index..<min(index + Self.columns, ids.count)].map { Optional($0) }
            out.append(slice + Array(repeating: nil, count: Self.columns - slice.count))
            index += Self.columns
        }
        return out
    }

    private var gridNaturalHeight: CGFloat {
        CharacterPanelGridBudget.naturalHeight(rowCount: rows.count)
    }

    @ViewBuilder
    private var grid: some View {
        let capHeight = CharacterPanelGridBudget.capHeight(extraChromeHeight: extraChromeHeight)
        // 짧으면 자연 높이 그대로, 넘치면 상한에서 스크롤(제보 목록과 같은 관용구).
        FeedbackListBox(
            contentHeight: gridNaturalHeight,
            capHeight: capHeight,
            clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll
        ) {
            VStack(spacing: Self.cardSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.cardSpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, id in
                            if let id {
                                card(id)
                            } else {
                                // 자리만 먹는 빈 칸. 그려지는 것이 없으므로 스냅샷에도 아무 흔적이 없다.
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Self.cardHeight)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 카드 한 장

    @ViewBuilder
    private func card(_ id: String) -> some View {
        let manifest = catalog.manifest(id: id)
        let isOn = id == selectedID
        Button {
            // 저장이 이긴 경우에만 카드를 옮긴다.
            if CheckCharacterPicker.choose(id, selection: selection, broadcast: broadcast) {
                selectedID = id
            }
        } label: {
            VStack(spacing: 5) {
                CharacterPortrait(
                    characterID: id,
                    // 픽셀아트는 **이웃 보간**으로 그려야 격자가 산다. `.high` 면 확대·축소에서 계단이
                    // 뭉개져 픽셀아트가 '흐린 그림'이 된다 — 앱 재질 필터가 `.nearest` 로 간 것과 같은 짝이다
                    // (SpriteCharacterNode 의 `manifest.pixelArt == true ? .nearest : .linear`).
                    isPixelArt: manifest?.pixelArt == true
                )
                .frame(width: 52, height: 52)
                Text(manifest?.displayName ?? id)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOn ? CheckTheme.primaryText : CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.cardHeight)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(CheckTheme.gaugeGradient.opacity(0.22))
                               : AnyShapeStyle(CheckTheme.trackFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isOn ? CheckTheme.accent : CheckTheme.border,
                                          lineWidth: isOn ? 2 : 1)
                    }
            }
            // 선택됨 표시. 테두리·바탕만으로는 어두운 팔레트에서 한눈에 안 읽혀 **배지를 함께** 단다
            // (오버레이라 카드 크기에 1pt 도 영향을 주지 않는다).
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(CheckTheme.accent))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        // 팝오버가 열릴 때 첫 포커스 링이 카드 위에 사각으로 겹치는 것을 막는다(이 앱의 기존 규약).
        .focusEffectDisabled()
        .accessibilityLabel(manifest?.displayName ?? id)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 초상화 한 장

/// 카드에 놓는 캐릭터 초상. **neutral 표정 고정**이다 — 고르는 화면에서 근무 상태에 따라 얼굴이 바뀌면
/// "이 캐릭터가 원래 이렇게 생겼나"를 묻게 된다(헤더 마스코트는 반대로 상태를 비추는 것이 일이다).
///
/// ★★ **`Image(nsImage:)` 는 `.interpolation(...)` 을 통째로 무시한다**(2026-09-13 실측).
///    같은 초상을 `.none` 과 `.high` 로 구운 PNG 가 **바이트까지 같았다** — 52·200·400pt 어느 크기에서도.
///    같은 그림을 `Image(decorative: CGImage, scale:)` 로 바꿔 그리면 그때서야 갈린다(400pt 에서
///    60,279바이트 대 294,702바이트 — 이웃 보간이 평평한 블록을 만들어 PNG 가 훨씬 작다).
///    그래서 여기서는 **반드시 CGImage 로 내려서** 그린다. `Image(nsImage:)` 로 되돌리면 `pixelArt`
///    분기는 남아 있는 채 아무 일도 안 하고, 픽셀아트는 조용히 뭉개진 채로 배포된다.
///    (`V0316CharacterPanelTests.픽셀아트_초상은_이웃_보간으로_그려진다` 가 그 되돌림을 픽셀로 잡는다.)
struct CharacterPortrait: View {
    let characterID: String
    /// 픽셀아트면 이웃 보간. 매니페스트의 `pixelArt` 가 유일한 출처다.
    var isPixelArt: Bool = false

    /// 초상의 CGImage. NSImage 가 비트맵 rep 하나짜리라(초상 PNG 한 장) 이 변환은 그 rep 의 CGImage 를
    /// 돌려주는 값싼 조회다 — NSImage 자체는 `CheckMascotAssets` 가 이미 캐시하고 있다.
    private var cgImage: CGImage? {
        CheckMascotAssets.image(for: .neutral, characterID: characterID)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var body: some View {
        if let cgImage {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .interpolation(isPixelArt ? .none : .high)
                .scaledToFit()
        } else {
            // 에셋이 통째로 없는 빌드(또는 깨진 PNG). 빈 자리 대신 기호를 그려 카드가 사라지지 않게 한다 —
            // 카탈로그가 이름을 알고 있는 캐릭터는 고를 수 있어야 한다(그림이 없는 것과 없는 캐릭터는 다르다).
            Image(systemName: "person.crop.circle")
                .resizable()
                .scaledToFit()
                .foregroundStyle(CheckTheme.secondaryText)
        }
    }
}

// MARK: - 격자 높이 예산 (순수 계산 — 결정적 검증 지점)

/// 캐릭터 격자의 표시 높이 예산.
///
/// 팝오버는 위 모서리가 메뉴바 아래에 고정돼 **아래로만** 자라므로(CheckWindowAnchor), 상한(700pt)을 넘긴
/// 만큼은 푸터(로그아웃/앱 종료)가 화면 밖으로 나가 손이 닿지 않는다. 캐릭터가 늘어나 행이 쌓이면
/// 그 일이 실제로 일어나므로, 넘치는 만큼은 **스크롤로 넘긴다**(개인 기록 패널과 같은 처방).
enum CharacterPanelGridBudget {
    /// 한 줄에 놓는 카드 수. 콘텐츠 폭 292pt 에서 칸 하나가 92pt 남짓이라 초상 52pt + 이름 한 줄이 든다.
    /// 넷으로 늘리면 칸이 67pt 로 좁아져 세 글자 이름이 줄어든다(폭 예산 292 는 고정이다 — 넓어지는 것은 창이지 본문이 아니다).
    static let columns = 3
    static let cardSpacing: CGFloat = 8
    /// 카드 고정 높이(pt). **상수로 못 박는다** — 이름 길이에 따라 흔들리면 격자 총 높이가 내용에 따라
    /// 달라지고, 그러면 아래 예산 계산이 거짓이 되어 창이 상한을 넘는 조합이 생긴다.
    static let cardHeight: CGFloat = 96

    /// 패널 안에서 격자가 **아닌** 부분의 높이(pt) = 패널 여백 12×2 + 제목 행 + 구분선 + 설명 줄 + 간격들.
    /// ImageRenderer 실측(콘텐츠 폭 292pt): 격자 자연 96/200/304pt 인 패널이 각각 197/301/405pt →
    /// 차가 어느 행 수에서도 **정확히 101pt** 다. 패널 머리에 줄을 하나 더하면 이 값이 커지고 아래 예산이
    /// 거짓이 되므로, `V0316CharacterPanelTests` 가 이 숫자를 실측과 맞대 못 박는다.
    static let chromeOutsideGrid: CGFloat = 101
    /// 캐릭터 패널이 떠 있을 때 팝오버에서 **패널이 아닌** 부분의 높이(pt) = 헤더 카드 + 푸터 + 바깥 여백
    /// (배너·목표 편집 행은 뺀 값 — 그것들은 `extraChromeHeight` 로 따로 들어온다).
    /// 실측: 한 행짜리 패널(197pt)이 든 팝오버가 391pt → 391 − 197 = 194pt.
    /// (검산: 회고 배너 + 목표 편집 행을 얹은 같은 화면이 537pt = 197 + 194 + 54 + 92 — 예산 상수 그대로다.)
    static let popoverChromeOutsidePanel: CGFloat = 194
    /// 상한을 넘지 않으려고 남기는 안전 여유(pt).
    static let safetySlack: CGFloat = 5

    /// 크롬이 하나도 없을 때 격자에 줄 수 있는 최대 높이(pt).
    /// = 700(창 상한) − 194(팝오버 크롬) − 101(패널 크롬) − 5(안전 여유) = 400.
    /// **손으로 고치지 마라** — 위 세 상수를 실측으로 고치면 이 값은 따라온다.
    static let maxGridHeight: CGFloat = 700 - popoverChromeOutsidePanel - chromeOutsideGrid - safetySlack
    /// 아무리 깎여도 격자에 남기는 최소 높이(카드 한 줄은 통째로 보이도록).
    static let minGridHeight: CGFloat = cardHeight

    /// 행 수에 대한 격자의 자연 높이(pt).
    static func naturalHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let rows = CGFloat(rowCount)
        return rows * cardHeight + (rows - 1) * cardSpacing
    }

    /// 카드 n 장이 만드는 행 수(마지막 행이 모자라도 한 행이다).
    static func rowCount(cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        return (cardCount + columns - 1) / columns
    }

    /// 실제 표시 높이(pt). 위에 얹힌 크롬이 있으면 그만큼 더 깎는다.
    static func capHeight(extraChromeHeight: CGFloat) -> CGFloat {
        max(minGridHeight, maxGridHeight - extraChromeHeight)
    }
}

// MARK: - 진입점 — 헤더 카드의 마스코트

/// 헤더 카드의 46×46 마스코트를 **누를 수 있게** 만든 버튼. 누르면 캐릭터 선택 패널이 열린다.
///
/// ★ **왜 레일이 아니라 여기인가.** 오른쪽 세로 레일은 여섯 칸으로 꽉 찼고(여유 3pt), 일곱 번째를 더하면
///   레일이 창 높이를 결정해 버려 렌더 테스트가 막는다. 그리고 "내 캐릭터를 고른다"는 화면으로 가는 문은
///   지금 화면에 떠 있는 **바로 그 캐릭터**를 누르는 것이 가장 자연스럽다.
///
/// ★ **헤더가 1pt 도 높아지면 안 된다**(창 높이 상한 700pt 계약 — 렌더 테스트 여럿이 지킨다).
///   그래서 이 버튼이 더하는 것은 전부 **레이아웃에 영향이 없는 것들**뿐이다:
///   `Button` + `.buttonStyle(.plain)` 은 라벨 크기를 그대로 쓰고, 46×46 `.frame` 은 예전 그 자리에
///   그대로 있으며, 누를 수 있다는 표식은 `.overlay`(크기에 영향 없음)로만 그린다. `.onHover` 도 마찬가지다.
struct CharacterEntryButton: View {
    @Bindable var store: WorkTimerStore

    @State private var hovering = false

    var body: some View {
        Button {
            store.toggleCharacterPanel()
        } label: {
            CheckMascotView(snapshot: store.snapshot)
                .frame(width: 46, height: 46)
                // hover 하면 은은하게 밝아진다 — "여긴 누를 수 있다"의 절반.
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(hovering ? 0.10 : 0))
                }
                // 나머지 절반은 **아주 작은 표식** 하나다(사용자 지시: 과하게 만들지 마라).
                // 평소엔 흐릿하게 있다가 hover 하면 또렷해진다.
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(CheckTheme.accent.opacity(hovering ? 1.0 : 0.72))
                                .overlay(Circle().strokeBorder(CheckTheme.panel, lineWidth: 1))
                        )
                }
        }
        .buttonStyle(.plain)
        // 팝오버가 열릴 때 첫 포커스가 이 버튼에 떨어져 마스코트 둘레에 파란 사각 링이 그려지는 것을 막는다
        // (바로 옆 근무 알약이 같은 이유로 같은 수식어를 달고 있다 — 이 한 줄은 이 버튼 하나만 덮는다).
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help("캐릭터 고르기")
        .accessibilityLabel("캐릭터 고르기")
        .accessibilityAddTraits(.isButton)
    }
}
