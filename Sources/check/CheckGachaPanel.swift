import AppKit
import SwiftUI
import CheckCore

// MARK: - 캐릭터 뽑기 패널 (v0.3.54 — 상점 패널 안)
//
// 문은 상점 '소모품' 구획의 **[캐릭터 뽑기]** 카드다(`CheckShopPanel.gachaCard`). 누르면 이 패널이 **캐릭터 구획과 하단 구매 바
// 자리를 빌려** 선다 — 확성기 작성기와 같은 자리이고 둘은 서로 배타다. 높이를 상수로 못 박아(`height`) 그 자리의 최소보다 커지지
// 않으므로 팝오버 700pt 예산(`ShopPanelGridBudget`)에 새 항목이 생기지 않는다(`V0354GachaMacTests` 가 렌더로 잰다).
//
// 보기 셋(높이 고정이라 한 번에 하나): [뽑기] 확률 한눈에 + 큰 [뽑기 · 50] · [확률 보기] 여덟 줄 · [조각 교환] 내 조각 + 교환 목록.
// 희귀 둘(황금 아잉이 · v0.3.59 무지개 아잉이)은 같은 급으로 강조한다 — 금은 금빛, 무지개는 일곱 빛(`GachaPalette.rare`).
// **[뽑기 · 50] 은 뽑지 않는다 — 뽑기 창(캡슐 기계 · `CheckGachaWindow.swift`)을 연다.** 뽑기·연출은 그 창의 몫이고(0.3.54 — 예전의
// 0.8초 결과 카드는 걷어냈다), 이 패널은 마지막 결과를 **한 줄**로만 말한다.
// 판정·문구·확률표·교환 목록은 전부 코어(`GachaRules` · `GachaText`)가 만든다 — 이 파일은 그리기만 한다. **숫자를 적지 않는다**
// (값 50 · 확률 · 교환값은 서버 `shop_state.gacha` 에서 온다).
//
// ⚠️ `Menu`·`Picker`·`popover` 를 쓰지 않는다 — `ImageRenderer` 가 그 자리를 노란 상자로 그려 렌더 검증이 눈이 먼다.

/// 확률표 한 줄(맥 화면용). 코어 `GachaOddsRow` 에서 만든다 — 스냅샷이 줄을 직접 넣을 수 있게 맥 쪽에 한 벌 둔다.
struct GachaOddsLine: Equatable, Identifiable {
    let id: String
    let name: String
    /// 상점가 칸: "60" · "뽑기 전용"(또는 코어가 정한 금 문구) · "—".
    let priceText: String
    let percentText: String
    /// 희귀 강조(.gold · .rainbow · .standard — v0.3.59). 코어 `GachaOddsRow.finish`(= 3D 마감과 같은 판정)에서 온다.
    let finish: CharacterManifest.Finish
    var isGold: Bool { finish == .gold }
    var isRainbow: Bool { finish == .rainbow }

    init(id: String, name: String, priceText: String, percentText: String, finish: CharacterManifest.Finish) {
        self.id = id
        self.name = name
        self.priceText = priceText
        self.percentText = percentText
        self.finish = finish
    }

    /// 스냅샷 호환(v0.3.54 모양): 금이 아니면 id 로 무지개를 가린다.
    init(id: String, name: String, priceText: String, percentText: String, isGold: Bool) {
        self.init(id: id, name: name, priceText: priceText, percentText: percentText,
                  finish: isGold ? .gold : (CharacterCatalog.isRainbowAing(id) ? .rainbow : .standard))
    }

    init(_ row: GachaOddsRow) {
        self.init(id: row.characterID, name: row.name, priceText: row.priceText, percentText: row.percentText,
                  finish: row.finish)
    }
}

/// 교환 목록 한 칸(맥 화면용). 코어 `GachaExchangeRow` 에서 만든다.
struct GachaExchangeLine: Equatable, Identifiable {
    let id: String
    let name: String
    let availability: GachaExchangeAvailability

    init(id: String, name: String, availability: GachaExchangeAvailability) {
        self.id = id
        self.name = name
        self.availability = availability
    }

    init(_ row: GachaExchangeRow) {
        self.init(id: row.characterID, name: row.name, availability: row.availability)
    }
}

/// 뽑기 패널 문구(맥 전용 조각). 공용 문구는 `GachaText` 가 주인이다.
enum GachaPanelText {
    static func tabTitle(_ mode: GachaPanelMode) -> String {
        switch mode {
        case .pull: return GachaText.pullButton
        case .odds: return GachaText.oddsButton
        case .exchange: return GachaText.exchangeTitle
        }
    }

    /// 상점 카드 둘째 말: "확률 공개 · 조각 3개"(조각 수를 모르면 앞말만).
    static func cardSubtitle(shards: Int?) -> String {
        guard let shards else { return "확률 공개" }
        return "확률 공개 · \(GachaText.shards(max(0, shards)))"
    }

    /// 결과가 아직 없을 때 첫 줄: "루비 50개로 하나를 뽑아요"(값은 서버 값).
    static func idleLine(price: Int?) -> String {
        guard let price else { return "캐릭터 하나를 뽑아요" }
        return "루비 \(max(0, price))개로 하나를 뽑아요"
    }

    static let pulling = "뽑는 중…"
    /// 마지막 결과 한 줄(패널은 연출하지 않는다 — 연출은 뽑기 창): "방금 · 새 캐릭터: 여우" · "방금 · 이미 있는 다람쥐 → 조각 +1" ·
    /// "방금 · 황금 아잉이!" · "방금 · 무지개 아잉이!"(이미 있던 희귀면 조각 줄).
    static func lastResult(_ result: GachaPullResult, name: String) -> String {
        let line = GachaText.rareHeadline(result.kind) != nil && result.isDuplicate
            ? GachaText.duplicate(name: name, shardsGained: result.shardsGained)
            : GachaText.headline(for: result, name: name)
        return "방금 · \(line)"
    }
    /// 하단 바 첫 줄.
    static let barTitle = "캐릭터 뽑기 1회"
    static let oddsHeaderName = "캐릭터"
    static let oddsHeaderPrice = "상점가"
    static let oddsHeaderPercent = "확률"
    static let exchangeEmpty = "교환할 수 있는 캐릭터가 없어요"
}

/// 희귀 강조색(결과 한 줄 · 확률표 줄 · 교환 칸 테두리 · 상점 카드 문구). 금은 금 초상과 같은 계열의 진한 금,
/// 무지개(v0.3.59)는 무지개 초상과 같은 차례(빨 → 보)의 일곱 빛 — 어두운 판(`CheckTheme`) 위 글자라 밝은 파스텔이다.
enum GachaPalette {
    static let gold = Color(red: 0.96, green: 0.76, blue: 0.27)
    static let rainbowColors: [Color] = [
        Color(red: 1.00, green: 0.56, blue: 0.64), Color(red: 1.00, green: 0.72, blue: 0.44),
        Color(red: 1.00, green: 0.90, blue: 0.43), Color(red: 0.56, green: 0.90, blue: 0.61),
        Color(red: 0.49, green: 0.76, blue: 1.00), Color(red: 0.65, green: 0.61, blue: 1.00),
        Color(red: 0.91, green: 0.61, blue: 1.00),
    ]
    /// 글자 · 테두리에 거는 무지개(왼쪽 → 오른쪽).
    static var rainbow: LinearGradient {
        LinearGradient(colors: rainbowColors, startPoint: .leading, endPoint: .trailing)
    }

    /// 희귀 강조 칠. 평범한 캐릭터는 nil — 호출부가 제 기본색을 쓴다.
    static func rare(_ finish: CharacterManifest.Finish) -> AnyShapeStyle? {
        switch finish {
        case .gold: return AnyShapeStyle(gold)
        case .rainbow: return AnyShapeStyle(rainbow)
        case .standard: return nil
        }
    }

    /// 희귀면 그 칠, 아니면 `otherwise`.
    static func ink(_ finish: CharacterManifest.Finish, otherwise: Color) -> AnyShapeStyle {
        rare(finish) ?? AnyShapeStyle(otherwise)
    }
}

struct CheckGachaPanel: View {
    @Bindable var store: WorkTimerStore
    var catalog: CharacterCatalog = CheckCharacter3DScene.catalog
    /// 스냅샷 전용: 확률표·교환 목록을 직접 넣는다(코어 결과 대신). 앱은 nil.
    var previewOddsLines: [GachaOddsLine]?
    var previewExchangeLines: [GachaExchangeLine]?
    /// 테스트 전용: 고정 높이를 풀고 **내용의 자연 높이**로 그린다 — 내용이 `height` 를 넘는지(넘치면 아래가 잘린다) 재는 문. 앱은 false.
    var measuresNaturalHeight = false

    /// 패널 전체 높이(pt). **캐릭터 구획 최소 자리**(소제목 + 간격 4 + 카드 한 줄 112) + 간격 7 + 구매 바 38 보다 작아야 한다 —
    /// 그래야 어떤 예산 조합에서도 이 패널을 연 상점이 격자를 연 상점보다 높아지지 않는다(확성기 작성기 166 과 같은 규약).
    /// 실측: 격자 구획 최소 자리는 174pt(소제목 13 + 4 + 112 + 7 + 38) — 1pt 여유를 둔다(`V0354GachaMacRenderTests.gachaPanelFitsTheBudget`).
    static let height: CGFloat = 173
    /// 보기 전환 줄 높이.
    static let tabsHeight: CGFloat = 22
    static let spacing: CGFloat = 6
    /// 결과 무대 높이([뽑기] 보기) = 패널 − 전환 줄 − 간격 둘 − 하단 바.
    static let stageHeight: CGFloat = height - tabsHeight - spacing * 2 - CheckShopPanel.purchaseBarHeight
    /// 교환 칸 높이 · 열 수.
    static let exchangeCellHeight: CGFloat = 27
    static let exchangeColumns = 2
    /// 확률표 한 줄 높이(caption2 한 줄). **여덟 줄**(v0.3.59 무지개) + 머리 + 각주 두 줄이 패널 안에 들어가는 값이다 —
    /// 일곱 줄일 땐 13pt + 줄 간격 1pt 였고 그 합(14 × 9)이 자리(145pt)를 꽉 채웠다. 간격을 0 으로, 줄을 12.5pt 로 줄여 한 줄을 들였다.
    static let oddsRowHeight: CGFloat = 12.5
    /// 확률표 줄 간격.
    static let oddsRowSpacing: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            tabs
            switch store.gachaPanelMode {
            case .pull: pullView
            case .odds: oddsView
            case .exchange: exchangeView
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: measuresNaturalHeight ? nil : Self.height, alignment: .top)
    }

    // MARK: 보기 전환

    private var tabs: some View {
        HStack(spacing: 5) {
            ForEach(GachaPanelMode.allCases, id: \.self) { mode in
                let on = store.gachaPanelMode == mode
                Button {
                    store.setGachaPanelMode(mode)
                } label: {
                    Text(GachaPanelText.tabTitle(mode))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(on ? Color.white : CheckTheme.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .frame(height: Self.tabsHeight)
                        .background {
                            if on {
                                Capsule().fill(CheckTheme.accent)
                            } else {
                                Capsule().strokeBorder(CheckTheme.border, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 4)
            // 내 조각 — 세 보기 모두에서 보인다(뽑기 결과가 조각을 바꾸고, 교환이 조각을 쓴다).
            HStack(spacing: 3) {
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                Text(store.gachaShards.map { GachaText.shards(max(0, $0)) } ?? "조각 —")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(height: Self.tabsHeight)
            .background(Capsule().fill(CheckTheme.accent.opacity(0.14)))
            .overlay(Capsule().stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
        .frame(height: Self.tabsHeight)
    }

    // MARK: [뽑기]

    private var pullView: some View {
        VStack(spacing: Self.spacing) {
            stage
                .frame(maxWidth: .infinity)
                .frame(height: Self.stageHeight)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CheckTheme.trackFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(CheckTheme.border, lineWidth: 1)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            pullBar
        }
    }

    /// 무대: 첫 줄(마지막 결과 한 줄 · 없으면 "루비 50개로 하나를 뽑아요") + 일곱 캐릭터와 확률(서버 순서 그대로) + 조각 규칙.
    /// 무엇이 얼마의 확률로 나오는지 첫 화면에서 보인다. 결과 연출은 없다 — 뽑기 창의 기계가 한다.
    private var stage: some View {
        let lines = oddsLines
        return VStack(spacing: 6) {
            topLine
            HStack(spacing: 2) {
                ForEach(lines) { line in
                    VStack(spacing: 2) {
                        CharacterPortrait(characterID: line.id,
                                          isPixelArt: catalog.manifest(id: line.id)?.pixelArt == true)
                            .frame(width: 32, height: 30)
                        Text(line.percentText)
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(GachaPalette.ink(line.finish, otherwise: CheckTheme.secondaryText))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("이미 있는 캐릭터가 나오면 조각 +1")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
    }

    /// 무대 첫 줄. 결과가 있으면 그 한 줄(황금이면 금빛 · 무지개면 무지개빛), 없으면 값 안내.
    @ViewBuilder
    private var topLine: some View {
        if let result = store.gachaLastResult {
            let line = GachaPanelText.lastResult(result, name: store.gachaDisplayName(result.characterID))
            Text(line)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GachaPalette.ink(CharacterManifest.Finish(characterID: result.characterID),
                                                  otherwise: CheckTheme.primaryText))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(line)
        } else {
            Text(GachaPanelText.idleLine(price: store.gachaInfo?.price))
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
        }
    }

    /// 하단 바 — 상점 구매 바와 **같은 높이·모양**(`CheckShopPanel.purchaseBarHeight`).
    private var pullBar: some View {
        let availability = store.gachaPullAvailability
        let button = Self.pullButtonState(store)
        let reason: String? = store.gachaNotice ?? Self.reason(for: availability, balance: store.rubyBalance)
            ?? (store.gachaPulling ? GachaPanelText.pulling : nil)
        let isError = store.gachaNotice != nil ? store.gachaNoticeIsError : !availability.canPull
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(GachaPanelText.barTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                // 둘째 줄은 언제나 그린다(빈 칸이어도) — 높이를 상태에 안 맡긴다.
                Text(reason ?? " ")
                    .font(.caption2)
                    .foregroundStyle(isError ? CheckTheme.danger : CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            // 뽑지 않는다 — 뽑기 창을 연다(창 기계의 손잡이가 실제 뽑기다). 팝오버는 창이 뜬 뒤 닫힌다.
            GachaPullButton(price: store.gachaInfo?.price, busy: store.gachaPulling, enabled: button.enabled) {
                store.openGachaWindow()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CheckShopPanel.purchaseBarHeight)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.trackFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(availability.canPull ? CheckTheme.accent : CheckTheme.border,
                                      lineWidth: availability.canPull ? 2 : 1)
                }
        }
    }

    /// [뽑기 · 50] 의 상태: 뽑을 수 있을 때만 눌린다(모자람 · 잔량 모름 · 뽑기 없음 · 왕복 중 · 구매 중이면 잠긴다), 잠겼으면 이유 한 줄.
    /// 잠긴 버튼은 창도 안 연다 — 창의 기계도 같은 이유로 손잡이가 안 도는데, 그걸 보러 창을 여는 것은 한 번 더 누르게 할 뿐이다.
    static func pullButtonState(_ store: WorkTimerStore) -> (enabled: Bool, reason: String?) {
        let availability = store.gachaPullAvailability
        let enabled = availability.canPull && !store.isGachaBusy && store.purchasingID == nil
        return (enabled, reason(for: availability, balance: store.rubyBalance))
    }

    /// 버튼을 잠근 이유(뽑을 수 있으면 nil). 잔량을 모르면 "루비 잔량을 아직 못 읽었어요"(코어는 nil 을 준다 — 침묵하면 고장으로 보인다).
    static func reason(for availability: GachaPullAvailability, balance: Int?) -> String? {
        if case .unknownBalance = availability { return ShopText.entryHelp(balance) }
        return GachaText.blockedReason(availability)
    }

    // MARK: [확률 보기]

    /// 확률표 줄(서버 순서 그대로). 이름은 맥 카탈로그(강아지 등), 상점가는 `shop_state.characters`.
    var oddsLines: [GachaOddsLine] {
        if let previewOddsLines { return previewOddsLines }
        return store.gachaOddsLines(catalog: catalog)
    }

    private var oddsView: some View {
        VStack(alignment: .leading, spacing: Self.oddsRowSpacing) {
            oddsRow(name: GachaPanelText.oddsHeaderName, price: GachaPanelText.oddsHeaderPrice,
                    percent: GachaPanelText.oddsHeaderPercent, header: true, finish: .standard)
            Rectangle().fill(CheckTheme.border).frame(height: 1)
            ForEach(oddsLines) { line in
                oddsRow(name: line.name, price: line.priceText, percent: line.percentText, header: false, finish: line.finish)
            }
            Spacer(minLength: 0)
            // 규칙 한 줄(공용 문구 — 폰과 같은 말). 두 줄까지, 잘리지 않게 세로 고정.
            Text(GachaText.oddsFootnote)
                .font(.system(size: 9.5))
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.trackFill)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CheckTheme.border, lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GachaText.oddsTitle)
    }

    /// 확률표 한 줄. 희귀(황금 · 무지개)는 이름과 확률을 그 빛깔로 칠한다(머리 줄은 언제나 흐린 글자).
    private func oddsRow(name: String, price: String, percent: String, header: Bool, finish: CharacterManifest.Finish) -> some View {
        let ink = header ? AnyShapeStyle(CheckTheme.secondaryText) : GachaPalette.ink(finish, otherwise: CheckTheme.primaryText)
        return HStack(spacing: 6) {
            Text(name)
                .font(header ? .caption2.weight(.semibold) : .caption2.weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            Text(price)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(percent)
                .font(header ? .caption2.weight(.semibold) : .caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: Self.oddsRowHeight)
    }

    // MARK: [조각 교환]

    /// 교환 목록(코어 순서 그대로 — 금이 교환표에 있으면 맨 위, 무지개가 그 다음).
    var exchangeLines: [GachaExchangeLine] {
        if let previewExchangeLines { return previewExchangeLines }
        guard let info = store.gachaInfo else { return [] }
        return GachaRules.exchangeRows(info: info, ownedIDs: store.ownedCharacterIDs) { catalog.manifest(id: $0)?.displayName }
            .map(GachaExchangeLine.init)
    }

    private var exchangeView: some View {
        let lines = exchangeLines
        let rows = stride(from: 0, to: lines.count, by: Self.exchangeColumns).map { start in
            Array(lines[start..<min(start + Self.exchangeColumns, lines.count)])
        }
        return VStack(alignment: .leading, spacing: 4) {
            if lines.isEmpty {
                Text(GachaPanelText.exchangeEmpty)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: Self.exchangeCellHeight)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { line in exchangeCell(line) }
                    if row.count < Self.exchangeColumns {
                        ForEach(0..<(Self.exchangeColumns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity).frame(height: Self.exchangeCellHeight)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            // 결과·거절 한 줄(언제나 그린다 — 높이를 상태에 안 맡긴다).
            Text(store.gachaNotice ?? " ")
                .font(.caption2)
                .foregroundStyle(store.gachaNoticeIsError ? CheckTheme.danger : CheckTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func exchangeCell(_ line: GachaExchangeLine) -> some View {
        let finish = CharacterManifest.Finish(characterID: line.id)
        let busy = store.gachaExchangingID == line.id
        let enabled = line.availability.canExchange && !store.isGachaBusy && store.purchasingID == nil
        return HStack(spacing: 5) {
            CharacterPortrait(characterID: line.id, isPixelArt: catalog.manifest(id: line.id)?.pixelArt == true)
                .frame(width: 24, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(line.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GachaPalette.ink(finish, otherwise: CheckTheme.primaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // 보유면 아랫줄을 비운다 — 오른쪽 "보유" 와 같은 말을 두 번 하지 않는다(높이는 그대로).
                Text(line.availability == .owned ? " " : Self.costText(line.availability))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Self.isShort(line.availability) ? CheckTheme.danger : CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 2)
            if case .owned = line.availability {
                Text(GachaText.owned)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
            } else {
                BuyButton(title: busy ? "…" : GachaText.exchangeButton, enabled: enabled) {
                    store.exchangeGacha(line.id)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: Self.exchangeCellHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.trackFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(GachaPalette.rare(finish) ?? AnyShapeStyle(CheckTheme.border), lineWidth: 1)
                        .opacity(finish.isRare ? 0.7 : 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.name) \(Self.costText(line.availability))")
    }

    /// 교환 칸 아랫줄: "조각 2개"(교환값) · 보유면 "보유" · 모자라면 가진 조각/교환값 "조각 3/20".
    /// (모자람을 "조각 20개 · 17개 더" 로 적으면 칸 폭 142pt 에서 잘렸다 — 실측 미리보기. 진행 꼴이 짧고 같은 사실을 말한다.)
    static func costText(_ availability: GachaExchangeAvailability) -> String {
        switch availability {
        case .owned: return GachaText.owned
        case .available(let cost), .unknownShards(let cost): return GachaText.shardCost(cost)
        case .short(let cost, let missing): return "조각 \(max(0, cost - missing))/\(cost)"
        case .notExchangeable: return GachaText.notExchangeable
        }
    }

    static func isShort(_ availability: GachaExchangeAvailability) -> Bool {
        if case .short = availability { return true }
        return false
    }
}

/// 큰 [뽑기 · 50] 버튼. 상점 [구매하기](`BuyButton`)보다 크다 — 이 패널에서 누를 것은 이것 하나다. 누르면 뽑기 창이 열린다.
/// 값을 모르면 숫자를 지어내지 않는다("뽑기" 만).
struct GachaPullButton: View {
    let price: Int?
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if busy {
                    Text("…")
                        .font(.caption.weight(.heavy))
                } else {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(price.map { GachaText.pullButton(price: $0) } ?? GachaText.pullButton)
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
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
        .accessibilityLabel(price.map { "뽑기, 루비 \($0)개" } ?? "뽑기")
        .accessibilityHint("뽑기 창을 열어요")
    }
}
