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

/// 상점에서 고른 것. **고른 것이지 산 것이 아니다** — 실제 구매는 `WorkTimerStore.confirmShopPurchase()`
/// 하나뿐이고, 이 값은 하단 구매 바가 무엇을 말할지 정한다.
enum ShopSelection: Equatable, Hashable {
    case character(String)
    case ultra
}

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
    /// **nil = 아직 모름.** 숫자를 만들지 않고 "—" 를 그린다 — 0 은 "모른다"가 아니라 "없다"로 읽힌다.
    let balance: Int?
    var highlighted: Bool = false
    /// 큰 칩(상점 제목 줄의 잔량). 사용자 지적 2026-09-13: "루비 아이콘이랑 숫자가 지금은 너무 작아."
    /// 작은 칩은 **가격표**에 그대로 쓴다 — 잔량과 가격이 같은 크기면 무엇이 내 것인지 안 읽힌다.
    var large: Bool = false

    var body: some View {
        HStack(spacing: large ? 5 : 3) {
            RubyIcon(size: large ? 20 : 13)
            Text(ShopText.balance(balance))
                .font(large ? .system(size: 17, weight: .bold) : .caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
        }
        .padding(.horizontal, large ? 11 : 6)
        .padding(.vertical, large ? 5 : 2)
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

    /// 잔량 글자. **nil 은 "—"** 다(0 이 아니다 — 실제로 3 을 가진 사용자에게 "0" 이라고 말한 신고가 있었다).
    static func balance(_ value: Int?) -> String {
        guard let value else { return "—" }
        let v = max(0, value)
        return v > balanceMaxNumber ? balanceOverflow : "\(v)"
    }

    static func entryHelp(_ value: Int?) -> String {
        value.map { "루비 \(max(0, $0))개" } ?? "루비 잔량을 아직 못 읽었어요"
    }

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

    // ── 하단 구매 바 문구(순수 — 값으로 검증한다) ────────────────────────────────────────────

    /// 바의 첫 줄. 아무것도 안 골랐으면 **무엇을 해야 하는지** 말한다(빈칸으로 두면 고장으로 보인다).
    @MainActor
    static func barTitle(selection: ShopSelection?, catalog: CharacterCatalog) -> String {
        switch selection {
        case .character(let id): return catalog.manifest(id: id)?.displayName ?? id
        case .ultra: return "울트라 찌르기 1개"
        case nil: return WorkTimerStore.pickSomethingNotice
        }
    }

    /// 바의 둘째 줄. **언제나 문자열을 돌려준다**(빈 문자열이어도) — 높이를 상태에 안 맡긴다.
    ///
    /// 우선순위: 방금 일어난 일(`notice`) > 모자란 양 > 침묵.
    /// 안내가 모자람보다 앞서는 이유: "샀어요!" 직후에도 잔량이 다음 상품에 모자랄 수 있는데,
    /// 그때 "루비 N개 더 필요해요"만 보이면 **방금 산 것이 실패한 것처럼 읽힌다.**
    static func barDetail(notice: String?, selection: ShopSelection?,
                          price: Int?, balance: Int?) -> String {
        if let notice { return notice }
        guard selection != nil, let price, let balance, balance < price else { return " " }
        return WorkTimerStore.shortfallNotice(need: price, have: balance)
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
    /// 패널 높이 − 격자 자연 높이 = **둘 다 199.0pt**. 행 수와 무관하게 같다는 것이 이 상수가 참이라는
    /// 근거다(캐릭터 패널의 101pt 를 같은 방법으로 잰 것과 같은 절차).
    /// 손으로 추정하지 마라 — 틀리면 창이 700pt 상한을 넘어 푸터(로그아웃/앱 종료)가 잘린다.
    /// `V0317ShopTests.shopChromeHeightMatchesMeasurement` 가 이 숫자를 실측과 맞대 못 박는다.
    ///
    /// 캐릭터 패널(101pt)보다 98pt 높은 것이 곧 **큰 잔량 칩 + 소모품 구획(소제목 + 카드)
    /// + 캐릭터 소제목 + 하단 구매 바(38pt)** 의 값이다.
    /// 이력: 바깥 간격 12pt·안내 줄 별도일 때 210pt → 간격 7pt 로 174pt → 2단 구매의 하단 바를 더해 199pt.
    /// (안내 줄을 따로 두지 않고 **구매 바 둘째 줄로 합쳐** 25pt 만 늘었다 — 따로 뒀으면 39pt 였다.)
    static let chromeOutsideGrid: CGFloat = 199
    /// 팝오버에서 패널이 아닌 부분(헤더 카드 + 푸터 + 바깥 여백).
    ///
    /// ★ **캐릭터 패널의 194pt 를 그대로 쓰면 안 된다**(처음에 그렇게 했다가 최악 조합이 717pt 로
    ///   상한을 넘었다). 같은 방법으로 상점 기준으로 다시 재면 **216pt** 다 — 팝오버 717pt 에서
    ///   패널(199 + 격자 210)과 목표 편집 행(92)을 뺀 값이다. 두 패널이 갈리는 이유까지는 못 밝혔고,
    ///   그래서 **추정하지 않고 잰 값을 쓴다**(`V0317ShopTests.popoverStaysUnderTheCapInTheWorstCase`
    ///   가 최악 조합을 렌더로 확인한다).
    static let popoverChromeOutsidePanel: CGFloat = 216
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
        // 간격 7pt — 캐릭터 패널(12)보다 좁다. 이 패널은 줄이 둘 더 붙는데(소모품 카드 · 구획 소제목 둘),
        // 12 로 두면 크롬만 210pt 가 되어 최악 조합(배너 + 목표 편집)에서 창이 700pt 를 넘는다(실측 728pt).
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("상점")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // 진입점이 아니게 됐으므로(레일의 [상점] 칸이 문이다) 잔량은 **여기서** 확인한다.
                // 그래서 크게 그린다 — 이 화면에서 제일 먼저 읽어야 할 숫자다.
                RubyBalanceChip(balance: store.rubyBalance, highlighted: true, large: true)
            }
            PanelDivider()
            // ── 구획 ①: 소모품 ────────────────────────────────────────────────────────────
            // 사용자 지적 2026-09-13: "상점에서 울트라 찌르기도 너무 구분이 안되어 있어서 알아보기가
            // 힘들어." 예전에는 캐릭터 카드들과 **같은 평면에 한 줄**로 얹혀 있어 다른 종류의 상품이라는
            // 것이 안 읽혔다. 소제목 + 자기 배경을 가진 카드로 감싸 갈라 놓는다.
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("소모품")
                ultraCard
            }
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("캐릭터")
                grid
            }
            purchaseBar
        }
        .padding(12)
        .panelStyle()
    }

    // MARK: 하단 구매 바 — **실제 구매로 가는 유일한 문**

    /// ★ **높이가 상태와 무관하게 고정이다.** 고른 것이 있든 없든, 안내가 있든 없든 같은 자리를
    ///   차지한다 — 상태마다 높이가 달라지면 `chromeOutsideGrid` 예산이 거짓이 되고, 그 순간 창이
    ///   700pt 상한을 넘는 조합이 생긴다(안내 줄을 "비어도 자리 유지"로 둔 것과 같은 이유).
    ///
    /// 예전의 별도 안내 줄을 **여기로 합쳤다**. 둘 다 "지금 무슨 일이 일어나는가"를 말하는 자리라
    /// 합치면 높이가 한 번만 든다.
    @ViewBuilder
    private var purchaseBar: some View {
        let selection = store.shopSelection
        let price = store.shopSelectionPrice
        let busy = store.purchasingID != nil
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ShopText.barTitle(selection: selection, catalog: catalog))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selection == nil ? CheckTheme.secondaryText : CheckTheme.primaryText)
                    .lineLimit(1)
                // 둘째 줄은 **언제나 그려진다**(빈 문자열이어도) — 높이를 상태에 안 맡긴다.
                Text(ShopText.barDetail(notice: store.shopNotice, selection: selection,
                                        price: price, balance: store.rubyBalance))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let price {
                RubyBalanceChip(balance: price)
            }
            BuyButton(title: busy ? "…" : "구매하기",
                      enabled: store.canConfirmShopPurchase) {
                store.confirmShopPurchase()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.purchaseBarHeight)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.trackFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selection == nil ? CheckTheme.border : CheckTheme.accent,
                                      lineWidth: selection == nil ? 1 : 2)
                }
        }
    }

    /// 구매 바의 고정 높이(pt). 상수로 못 박는다 — 내용에 따라 흔들리면 예산 계산이 거짓이 된다.
    static let purchaseBarHeight: CGFloat = 38

    /// 구획 소제목. 높이가 상태와 무관하게 고정이어야 예산이 참이다(둘 다 언제나 그려진다).
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CheckTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 소모품 — 울트라 구매 카드

    /// 캐릭터 격자와 **다른 물건**임을 배경으로 말한다. 격자 카드는 `trackFill` 평면인데 이쪽은
    /// accent 틴트 + accent 테두리라, 색을 못 보는 화면에서도 소제목("소모품")이 한 번 더 말한다.
    @ViewBuilder
    private var ultraCard: some View {
        // ★ [사기] 버튼이 여기 있었는데 **없앴다.** 상품 종류마다 구매 방법이 다르면 그게 곧 실수의
        //   자리다 — 울트라도 캐릭터와 똑같이 "누르면 고르기 → 하단 바에서 구매하기"를 지난다.
        let picked = store.shopSelection == .ultra
        Button {
            store.selectShopItem(.ultra)
        } label: {
            ultraRow
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CheckTheme.accent.opacity(picked ? 0.22 : 0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(CheckTheme.accent.opacity(picked ? 1.0 : 0.35),
                                              lineWidth: picked ? 2 : 1)
                        }
                }
                .overlay(alignment: .topTrailing) {
                    if picked { pickedBadge.padding(4) }
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(store.purchasingID != nil)
        .accessibilityLabel("울트라 찌르기 고르기")
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    /// 고른 것에 얹는 배지. 캐릭터 선택 패널의 체크 배지와 **같은 문법**이다(오버레이라 크기에 영향 0).
    private var pickedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(CheckTheme.accent))
    }

    @ViewBuilder
    private var ultraRow: some View {
        let price = store.ultraPrice
        let busy = store.purchasingID == WorkTimerStore.ultraPurchaseID
        // 가격을 모르면 **살 수 없다**(값을 지어내지 않는다). 잔량 부족도 같은 이유로 서버가 최종 판정이고,
        // 여기 비활성화는 헛왕복을 줄이는 장치다.
        let affordable = (store.rubyBalance).flatMap { have in price.map { have >= $0 } } ?? false
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
        let affordable = (store.rubyBalance).flatMap { have in entry.price.map { have >= $0 } } ?? false
        let name = catalog.manifest(id: entry.id)?.displayName ?? entry.id
        let picked = store.shopSelection == .character(entry.id)
        Button {
            store.selectShopItem(.character(entry.id))
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
                            .strokeBorder(picked ? CheckTheme.accent
                                                 : (owned ? CheckTheme.accent.opacity(0.5) : CheckTheme.border),
                                          lineWidth: picked ? 2 : 1)
                    }
            }
            // 살 수 없는 카드는 흐리게. 그래도 **누를 수는 있다** — 골라 보면 하단 바가 얼마가
            // 모자란지 말해 준다(서버로는 안 나간다).
            .opacity(owned || affordable ? 1 : 0.5)
            .overlay(alignment: .topTrailing) {
                if picked { pickedBadge.padding(4) }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        // 구매 중에만 막는다. 보유한 것도 누를 수 있다 — 누르면 "이미 갖고 있어요"라고 말한다
        // (침묵하면 눌러도 아무 일이 없어 고장으로 보인다).
        .disabled(store.purchasingID != nil)
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

// MARK: - 진입점
//
// **진입점은 오른쪽 레일의 [상점] 칸이다**(`CheckMenuSideRail`). v0.3.17 초안에서는 헤더 카드의 루비
// 잔량 칩이 문이었는데, 사용자가 실제 화면을 보고 뒤집었다: "루비표시랑 위치가 별로야. (…) 그냥 루비가
// 아니라 상점 버튼으로 따로 만들고, 상점에서 루비 개수 확인 할 수 있게하자. (…) 상점 버튼 위치는
// 오른쪽 버튼 목록으로 바꾸자." 그래서 헤더에는 아무것도 없고, 잔량은 상점 제목 줄에서 크게 보인다.
//
// 칸을 일곱으로 늘리면서 `CheckMenuSideRail.buttonHeight` 를 54 → 45pt 로 내렸다 — 그 이유와 실측은
// 그쪽 '높이 계약' 주석에 있다.
