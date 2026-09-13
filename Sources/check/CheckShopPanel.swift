import AppKit
import SwiftUI

// MARK: - 상점 패널 (v0.3.17)
//
// 재화는 **루비**다(2026-09-13 사용자 확정). 파는 것은 캐릭터와 울트라 찌르기 둘뿐이고, 가격·보유·잔량은
// 전부 **서버가 말한다** — 이 파일에 가격표가 없는 것이 설계다(클라가 한 벌 더 가지면 가격을 바꾸는 날
// 화면만 옛 숫자를 말한다, `ultraBalanceCap` 주석이 이미 같은 이유를 적어 뒀다).
//
// **진입점은 헤더 카드의 루비 잔량 칩**이다(사용자 확정: "상점 진입 걍 재화 버튼 눌러서 진입으로 하자").
// 오른쪽 레일에 일곱 번째 칸을 더하지 않는 이유는 캐릭터 패널과 같다 — 레일 6칸이 378pt 인데 제일 짧은
// 메인 화면이 381pt 라 여유가 3pt 뿐이고, 한 칸(+60pt)이면 곧바로 **레일이 창 높이를 결정한다**
// (`CheckMenuSideRail` 주석 · `CheckMenuRenderTests.sideRailNeverDecidesTheWindowHeight`).

/// 루비 아이콘 비트맵. 번들에서 한 번만 읽어 캐시한다.
///
/// ★★ **`Image(nsImage:)` 는 `.interpolation(...)` 을 통째로 무시한다**(2026-09-13 실측 — 같은 그림을
///    `.none`/`.high` 로 구운 PNG 가 바이트까지 같았다). 원본이 327²라 14pt 로 그리면 **23배 축소**다.
///    그래서 반드시 `Image(decorative: CGImage, scale:)` 로 내려 그린다 — `CharacterPortrait` 위의
///    긴 주석이 같은 함정의 실측 근거를 갖고 있다.
@MainActor
enum RubyAsset {
    private static var cached: CGImage??

    /// 루비 CGImage(없으면 nil — 호출부가 SF Symbol 로 접는다).
    static var image: CGImage? {
        if let cached { return cached }
        let url = CheckResources.bundle.url(forResource: "ruby", withExtension: "png")
        let made = url.flatMap { NSImage(contentsOf: $0) }?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        cached = .some(made)
        return made
    }

    static func resetCacheForTesting() { cached = nil }
}

/// 루비 아이콘 한 장. 에셋이 없으면 SF Symbol 로 접는다 — 그림이 통째로 사라지면 "루비 3" 이 "3" 이 된다.
struct RubyIcon: View {
    var size: CGFloat = 13

    var body: some View {
        if let image = RubyAsset.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "diamond.fill")
                .font(.system(size: size * 0.8, weight: .bold))
                .foregroundStyle(CheckTheme.accent)
                .frame(width: size, height: size)
        }
    }
}

/// 루비 잔량 캡슐(아이콘 + 숫자). 헤더 진입 버튼과 상점 제목 행이 **같은 모양**을 쓴다 —
/// 누르고 들어온 곳과 도착한 곳이 같은 표식을 달고 있어야 "여기가 그 화면"임이 읽힌다.
struct RubyBalanceChip: View {
    let balance: Int
    var highlighted: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            RubyIcon(size: 13)
            Text(ShopText.balance(balance))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        // 테두리를 남기는 이유는 미학이 아니라 **검증**이다(UltraBalanceBadge 와 같은 이유):
        // 배경과의 픽셀 델타가 거의 0 이면 칩 소실 회귀를 렌더가 못 잡는다.
        .background(Capsule().fill(CheckTheme.accent.opacity(highlighted ? 0.28 : 0.16)))
        .overlay(Capsule().stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
    }
}

/// 상점 문구(순수 — 값으로 검증한다).
enum ShopText {
    /// 잔량이 아무리 커져도 헤더 칩이 창을 밀지 않게 접는 지점. 정확한 수는 툴팁이 말한다.
    static let balanceMaxNumber = 9_999
    static let balanceOverflow = "9999+"

    static func balance(_ value: Int) -> String {
        let v = max(0, value)
        return v > balanceMaxNumber ? balanceOverflow : "\(v)"
    }

    static func entryHelp(_ value: Int) -> String { "루비 \(max(0, value))개 — 눌러서 상점" }

    /// 캐릭터 카드 아래 줄. 보유한 것은 가격 대신 사실을 말한다.
    static func cardPrice(owned: Bool, price: Int?) -> String {
        if owned { return "보유" }
        guard let price else { return "—" }
        return "\(max(0, price))"
    }

    /// 울트라 줄 제목. 가격을 모르면 "1개"를 말하지 않는다 — 몇 개를 얼마에 파는지 모르는 채로
    /// 수량만 단정하면 그 줄이 거짓말을 한다.
    static func ultraRowTitle(price: Int?) -> String {
        price == nil ? "울트라 찌르기" : "울트라 찌르기 1개"
    }

    /// 울트라 줄 오른쪽 보조 문구. 잔량을 **모르면 숫자를 만들지 않는다**.
    static func ultraHeld(_ balance: Int?) -> String {
        balance.map { "보유 \(max(0, $0))개" } ?? "보유 —"
    }
}

// MARK: - 상점 격자 높이 예산 (순수 계산 — 결정적 검증 지점)

/// 상점 격자의 표시 높이 예산.
///
/// `CharacterPanelGridBudget` 과 **같은 조립**이고 `chromeOutsideGrid` 하나만 다르다 — 상점은 제목 행
/// 아래에 울트라 구매 줄과 안내 줄이 더 붙기 때문이다. 그 값은 **실측으로 정한다**(아래 주석).
enum ShopPanelGridBudget {
    static let columns = CharacterPanelGridBudget.columns
    static let cardSpacing = CharacterPanelGridBudget.cardSpacing
    /// 카드 고정 높이. 캐릭터 패널(96)보다 **가격 줄 하나만큼** 높다.
    /// 상수로 못 박는 이유는 저쪽과 같다 — 내용에 따라 흔들리면 아래 예산이 거짓이 된다.
    static let cardHeight: CGFloat = 112

    /// 패널 안에서 격자가 **아닌** 부분의 높이(pt) = 패널 여백 12×2 + 제목 행 + 구분선 + 울트라 구매 줄
    /// + 안내 줄 + 간격들.
    ///
    /// **실측값이다**(ImageRenderer · 콘텐츠 폭 292pt): 카드 3장(1행)과 6장(2행)으로 각각 재어
    /// 패널 높이 − 격자 자연 높이 = **둘 다 141.0pt**. 행 수와 무관하게 같다는 것이 이 상수가 참이라는
    /// 근거다(캐릭터 패널의 101pt 를 같은 방법으로 잰 것과 같은 절차).
    /// 손으로 추정하지 마라 — 틀리면 창이 700pt 상한을 넘어 푸터(로그아웃/앱 종료)가 잘린다.
    /// `V0317ShopTests.shopChromeHeightMatchesMeasurement` 가 이 숫자를 실측과 맞대 못 박는다.
    ///
    /// 캐릭터 패널(101pt)보다 40pt 높은 것이 곧 **울트라 구매 줄 + 안내 줄**의 값이다.
    static let chromeOutsideGrid: CGFloat = 141
    /// 팝오버에서 패널이 아닌 부분(헤더 카드 + 푸터 + 바깥 여백). 캐릭터 패널과 **같은 값**이다 —
    /// 패널 바깥은 어느 패널이 떠 있든 같은 구성이기 때문이다.
    static let popoverChromeOutsidePanel = CharacterPanelGridBudget.popoverChromeOutsidePanel
    static let safetySlack = CharacterPanelGridBudget.safetySlack

    static let maxGridHeight: CGFloat = 700 - popoverChromeOutsidePanel - chromeOutsideGrid - safetySlack
    static let minGridHeight: CGFloat = cardHeight

    static func naturalHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let rows = CGFloat(rowCount)
        return rows * cardHeight + (rows - 1) * cardSpacing
    }

    static func rowCount(cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        return (cardCount + columns - 1) / columns
    }

    static func capHeight(extraChromeHeight: CGFloat) -> CGFloat {
        max(minGridHeight, maxGridHeight - extraChromeHeight)
    }
}

// MARK: - 상점 패널

struct CheckShopPanel: View {
    @Bindable var store: WorkTimerStore
    /// 이 빌드가 세울 수 있는 캐릭터 전부. 순서의 주인은 **서버 목록**이고, 서버가 모르는 것은 안 판다.
    var catalog: CharacterCatalog = CheckCharacter3DScene.catalog
    var extraChromeHeight: CGFloat = 0
    /// 스냅샷 전용: 넘치는 격자를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("상점")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                RubyBalanceChip(balance: store.rubyBalance, highlighted: true)
            }
            PanelDivider()
            ultraRow
            // ★ **안내 줄은 비어 있어도 자리를 지킨다.** 상태에 따라 행이 생겼다 사라지면
            //   `chromeOutsideGrid` 가 상태마다 달라져 위 예산이 거짓이 된다(그 순간 창이 상한을 넘는
            //   조합이 생긴다). 배지가 "자리는 유지하고 숫자만 비운다"로 푼 것과 같은 처방이다.
            Text(store.shopNotice ?? " ")
                .font(.caption2)
                .foregroundStyle(store.shopNotice == nil ? Color.clear : CheckTheme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            grid
        }
        .padding(12)
        .panelStyle()
    }

    // MARK: 울트라 구매 줄

    @ViewBuilder
    private var ultraRow: some View {
        let price = store.ultraPrice
        let busy = store.purchasingID == WorkTimerStore.ultraPurchaseID
        // 가격을 모르면 **살 수 없다**(값을 지어내지 않는다). 잔량 부족도 같은 이유로 서버가 최종 판정이고,
        // 여기 비활성화는 헛왕복을 줄이는 장치다.
        let affordable = price.map { store.rubyBalance >= $0 } ?? false
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CheckTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(ShopText.ultraRowTitle(price: price))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Text(ShopText.ultraHeld(store.ultraBalance))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let price {
                RubyBalanceChip(balance: price)
            }
            // 모자라도 **누를 수 있다** — 그래야 "얼마가 모자란지"를 말할 자리가 생긴다
            // (tapBuyUltra 가 서버로 안 나가고 안내만 남긴다). 가격을 모르면 그때만 막는다.
            BuyButton(title: busy ? "…" : "사기",
                      enabled: !busy && store.purchasingID == nil && price != nil) {
                store.tapBuyUltra()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 격자

    private var rows: [[ShopCharacterRow?]] {
        // 서버 목록이 유일한 출처다. 아직 못 읽었으면 **번들 목록으로 자리만** 그린다(가격 없음) —
        // 빈 화면보다 낫고, 가격을 지어내지도 않는다.
        let source: [ShopCharacterRow] = store.shopCharacters.isEmpty
            ? catalog.allIDs.filter { $0 != CharacterCatalog.builtInAingID }
                .map { ShopCharacterRow(id: $0, price: nil, owned: false) }
            : store.shopCharacters
        var out: [[ShopCharacterRow?]] = []
        var index = 0
        while index < source.count {
            let slice = source[index..<min(index + ShopPanelGridBudget.columns, source.count)].map { Optional($0) }
            out.append(slice + Array(repeating: nil, count: ShopPanelGridBudget.columns - slice.count))
            index += ShopPanelGridBudget.columns
        }
        return out
    }

    @ViewBuilder
    private var grid: some View {
        let natural = ShopPanelGridBudget.naturalHeight(rowCount: rows.count)
        let cap = ShopPanelGridBudget.capHeight(extraChromeHeight: extraChromeHeight)
        FeedbackListBox(contentHeight: natural, capHeight: cap,
                        clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll) {
            VStack(spacing: ShopPanelGridBudget.cardSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: ShopPanelGridBudget.cardSpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, entry in
                            if let entry {
                                card(entry)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: ShopPanelGridBudget.cardHeight)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ entry: ShopCharacterRow) -> some View {
        let owned = entry.owned == true || store.ownedCharacterIDs.contains(entry.id)
        let busy = store.purchasingID == entry.id
        let affordable = entry.price.map { store.rubyBalance >= $0 } ?? false
        let name = catalog.manifest(id: entry.id)?.displayName ?? entry.id
        Button {
            store.tapShopCharacter(entry.id)
        } label: {
            VStack(spacing: 4) {
                // 카드 그림은 캐릭터 선택 패널과 **같은 것**을 쓴다(아틀라스 frontIdle 셀을 알파로 조인 전신).
                // 두 화면이 같은 캐릭터를 다르게 그리면 "이게 그거 맞나"를 묻게 된다.
                CharacterPortrait(characterID: entry.id,
                                  isPixelArt: catalog.manifest(id: entry.id)?.pixelArt == true)
                    .frame(width: 80, height: 56)
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    if !owned { RubyIcon(size: 10) }
                    Text(busy ? "…" : ShopText.cardPrice(owned: owned, price: entry.price))
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(owned ? CheckTheme.secondaryText : CheckTheme.primaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: ShopPanelGridBudget.cardHeight)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CheckTheme.trackFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(owned ? CheckTheme.accent.opacity(0.5) : CheckTheme.border,
                                          lineWidth: 1)
                    }
            }
            // 살 수 없는 카드는 흐리게. **누르는 것 자체는 막는다**(아래 disabled) — 비활성 카드를
            // 누를 수 있게 두면 서버 왕복이 늘 뿐 결과가 같다.
            .opacity(owned || affordable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        // 보유·구매중만 막는다. **잔량 부족은 막지 않는다** — 누르면 얼마가 모자란지 말해 준다.
        .disabled(owned || busy || store.purchasingID != nil)
        .help(owned ? "\(name) — 보유 중" : "\(name) 사기")
        .accessibilityLabel(owned ? "\(name) 보유 중" : "\(name) 사기")
    }
}

/// 상점의 작은 [사기] 버튼. `Menu`·`TextField` 를 쓰지 않는 이유는 렌더 검증 때문이다 —
/// `ImageRenderer` 가 그 둘을 **노란 상자**로 그려서 그 자리의 결함이 스냅샷에서 통째로 사라진다
/// (이 저장소가 실제로 8일간 못 잡은 색 결함이 그 자리에 있었다).
struct BuyButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    if enabled {
                        Capsule().fill(CheckTheme.gaugeGradient)
                    } else {
                        Capsule().fill(CheckTheme.trackFill)
                            .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}

// MARK: - 진입점 — 헤더 카드의 루비 잔량 칩

/// 헤더 카드 첫 줄 오른쪽, 근무 토글 알약 **왼쪽**에 서는 진입 버튼.
///
/// ★ **헤더가 1pt 도 높아지면 안 된다**(팝오버 700pt 계약 — 렌더 테스트 여럿이 지킨다).
///   그래서 이 버튼이 더하는 것은 전부 **높이에 영향이 없는 것들**이다: 칩의 자연 높이(≈19pt)가
///   같은 줄의 마스코트(46pt)보다 낮아 `HStack` 의 높이를 바꾸지 않고, 표식·hover 는 배경/테두리로만 그린다.
///
/// ★ 무효화는 캐릭터 마스코트 버튼과 **같은 장치**다 — `store.rubyBalance` 를 직접 읽으므로
///   `@Observable` 이 이 잎 뷰만 다시 그린다(헤더 카드 본체는 안 흔든다).
struct RubyEntryButton: View {
    @Bindable var store: WorkTimerStore

    @State private var hovering = false

    var body: some View {
        Button {
            store.toggleShopPanel()
        } label: {
            RubyBalanceChip(balance: store.rubyBalance, highlighted: hovering)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(ShopText.entryHelp(store.rubyBalance))
        .accessibilityLabel("상점 열기")
        .accessibilityValue("루비 \(max(0, store.rubyBalance))개")
        .accessibilityAddTraits(.isButton)
    }
}
