#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 캐릭터 뽑기 카드 (v0.3.54 · 폰 1.0.8)

/// 상점 맨 위 뽑기 카드: 제목 + 1회 값 · 결과 연출(마지막 결과) · [뽑기 · 50] · 막힌 이유 · [확률 보기] [조각 N개 · 교환].
///
/// 판정·문구는 코어(`GachaRules` · `GachaText`)가 맥과 한 벌로 들고 있다 — 이 뷰는 그리기만 한다. 시트(확률표 · 교환)는 화면 루트
/// (`MeShopView`)가 띄운다(시트는 루트만 띄운다는 관례).
///
/// [뽑기] 는 **틴트**다: 이 화면의 채운 버튼은 아래 구매 막대 하나다(화면당 채운 버튼 하나 — `MeDesignContractTests`).
/// 뽑기에는 확인 대화상자를 두지 않는다(맥 뽑기 패널과 같다) — 버튼 글자가 값을 말하고, 요청이 떠 있는 동안 잠겨 연타가 요청 하나다.
struct MeGachaCard: View {
    let store: MeStore
    let onOdds: () -> Void
    let onExchange: () -> Void

    var body: some View {
        let price = store.gachaInfo?.price ?? 0
        AingCard {
            VStack(alignment: .leading, spacing: MobileTheme.space3) {
                HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
                    Text(GachaText.title)
                        .font(.headline)
                        .foregroundStyle(MobileTheme.label)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: MobileTheme.space2)
                    RubyPrice(price, balance: store.rubyBalance, gemSize: 17, style: .subheadline)
                }
                Text(MeText.gachaLede(price: price))
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                if let result = store.lastGachaResult {
                    MeGachaResultView(result: result, name: store.gachaName(result.characterID))
                        .id(store.gachaRevealSerial)
                }
                pullButton(price: price)
                if let detail = store.gachaDetail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(store.isGachaNoticeError ? MobileTheme.danger : MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MobileTheme.space2) { secondaryButtons }
                    VStack(spacing: MobileTheme.space2) { secondaryButtons }
                }
            }
        }
    }

    private func pullButton(price: Int) -> some View {
        Button {
            store.pullGacha()
        } label: {
            HStack(spacing: 6) {
                if store.isPulling {
                    ProgressView().controlSize(.small).tint(MobileTheme.accent)
                } else {
                    Image(systemName: "sparkles").imageScale(.medium).accessibilityHidden(true)
                }
                Text(GachaText.pullButton(price: price)).monospacedDigit()
            }
        }
        .buttonStyle(AingButtonStyle(.tinted, size: .lg, fillsWidth: true))
        .disabled(!store.canPullGacha)
        .accessibilityLabel(Text("\(GachaText.pullButton), 루비 \(price)개"))
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        AingButton(GachaText.oddsButton, systemImage: "percent", kind: .gray, size: .md, fillsWidth: true, action: onOdds)
        AingButton(MeText.gachaExchangeEntry(shards: store.gachaShards), systemImage: "puzzlepiece.extension",
                   kind: .gray, size: .md, fillsWidth: true, action: onExchange)
    }
}

/// 뽑기 결과 한 칸 — 짧게(0.8초 안) 튀어나온다. 황금 아잉이는 금빛 후광 + "황금 아잉이!" · 새 캐릭터 "새 캐릭터: 여우" ·
/// 중복 "이미 있는 여우 → 조각 +1"(문구는 코어 `GachaText` — 맥과 같은 글자).
///
/// 움직임과 나타남을 **다른 곡선·다른 상태**로 준다: 크기는 스프링(0.45초 · 살짝 튕김), 불투명은 0.12초 직선 — 같은 easeOut 으로
/// 둘 다 깎으면 커지기 전에 흐려 보인다(메모리 '이징으로 불투명도를 깎지 마라'). 동작 줄이기를 켜면 크기 변화 없이 나타나기만 한다.
/// 새 결과마다 카드가 `.id(gachaRevealSerial)` 로 새로 서므로 같은 캐릭터가 연달아 나와도 다시 튀어나온다.
struct MeGachaResultView: View {
    let result: GachaPullResult
    let name: String
    @State private var visible = false
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isGold = result.kind == .gold
        let shape = RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            ZStack {
                if isGold {
                    Circle()
                        .fill(RadialGradient(colors: [MobileTheme.gold.opacity(0.55), MobileTheme.gold.opacity(0)],
                                             center: .center, startRadius: 4, endRadius: 46))
                        .frame(width: 92, height: 92)
                        .scaleEffect(grown ? 1 : 0.4)
                }
                MeCharacterArt(id: result.characterID, size: 64)
                    .scaleEffect(grown ? 1 : 0.55)
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if isGold {
                        Image(systemName: "sparkles")
                            .foregroundStyle(MobileTheme.gold)
                            .accessibilityHidden(true)
                    }
                    Text(GachaText.headline(for: result, name: name))
                        .font(.headline)
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = GachaText.detail(for: result, name: name) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(MobileTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(isGold ? MobileTheme.gold.opacity(0.14) : MobileTheme.surface2))
        .opacity(visible ? 1 : 0)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.linear(duration: 0.12)) { visible = true }
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) { grown = true }
            }
        }
    }
}

// MARK: - 확률표 시트

/// "확률 보기" 시트: 서버가 준 표 그대로(순서까지) — 캐릭터 · 상점가(뽑기 전용이면 그 말) · 확률 + 규칙 한 줄.
/// 앱스토어 지침(확률형 아이템은 **사기 전에** 확률 공개)이 요구하는 자리다 — 표가 불완전하면 카드가 아예 안 서므로
/// 여기 오는 표는 늘 합 100% 다(`GachaInfo.isUsable`).
struct MeGachaOddsSheet: View {
    let store: MeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let rows = store.gachaOddsRows
        VStack(spacing: 0) {
            SheetHeader(GachaText.oddsTitle,
                        subtitle: store.gachaInfo?.price.map { GachaText.pullButton(price: $0) },
                        onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    InsetGroup {
                        GroupRow(minHeight: 32, padding: EdgeInsets(top: 8, leading: MobileTheme.cardPadding, bottom: 8, trailing: MobileTheme.cardPadding)) {
                            Text(MeText.gachaOddsColumnName)
                            Spacer(minLength: 0)
                            Text(MeText.gachaOddsColumnPrice).frame(minWidth: 72, alignment: .trailing)
                            Text(MeText.gachaOddsColumnPercent).frame(minWidth: 48, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MobileTheme.label2)
                        .accessibilityHidden(true)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            GroupRow(divider: index == rows.count - 1 ? .none : .inset(MobileTheme.cardPadding + 40 + MobileTheme.space3)) {
                                MeCharacterArt(id: row.characterID, size: 40)
                                    .frame(width: 40, height: 40)
                                    .accessibilityHidden(true)
                                Text(row.name)
                                    .font(.subheadline.weight(row.isGold ? .bold : .semibold))
                                    .foregroundStyle(MobileTheme.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: MobileTheme.space2)
                                priceCell(row)
                                    .frame(minWidth: 72, maxWidth: 104, alignment: .trailing)
                                Text(row.percentText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(MobileTheme.label)
                                    .frame(minWidth: 48, alignment: .trailing)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("\(row.name), \(MeText.gachaOddsColumnPrice) \(row.priceText), \(MeText.gachaOddsColumnPercent) \(row.percentText)"))
                        }
                    }
                    Text(GachaText.oddsFootnote)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.space1)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space6)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        // 표 전체(7줄 + 규칙 한 줄)가 한 번에 보이게 — 중간 높이면 마지막 줄이 잘려 공개한 확률이 반만 보인다.
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func priceCell(_ row: GachaOddsRow) -> some View {
        if let price = row.shopPrice {
            RubyPrice(price, isShort: false, gemSize: 14, style: .footnote)
        } else {
            // 금 줄은 "뽑기 또는 조각 20개"(코어 문구)처럼 길 수 있다 — 두 줄까지 접고 오른쪽에 붙인다(글자를 줄여 숨기지 않는다).
            Text(row.priceText)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 조각 교환 시트

/// 조각 교환: 서버 교환표 그대로(확률표 순서 — 황금 아잉이가 맨 앞) · 줄마다 그림 · 이름 · 값 · [교환](모자라면 잠김 · 가졌으면 "보유").
/// 교환은 확인 대화상자의 [교환하기] 로만 나간다(상점 구매와 같은 관례 — 카드를 눌러 바로 쓰이지 않는다).
struct MeGachaExchangeSheet: View {
    let store: MeStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirming: GachaExchangeRow?

    var body: some View {
        let rows = store.gachaExchangeRows
        VStack(spacing: 0) {
            SheetHeader(GachaText.exchangeTitle,
                        subtitle: store.gachaShards.map { GachaText.shards($0) },
                        onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    if let notice = store.exchangeNotice {
                        InlineNotice(text: notice, kind: store.isExchangeNoticeError ? .warning : .info)
                    }
                    InsetGroup {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            GroupRow(divider: index == rows.count - 1 ? .none : .inset(MobileTheme.cardPadding + 44 + MobileTheme.space3)) {
                                exchangeRow(row)
                            }
                        }
                    }
                    Text(GachaText.oddsFootnote)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.space1)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space6)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents([.large])
        .onDisappear { store.exchangeSheetDidDisappear() }
        .confirmationDialog(confirmTitle, isPresented: confirmingBinding, titleVisibility: .visible, presenting: confirming) { row in
            Button(MeText.exchangeAction) { store.exchangeShards(for: row.characterID) }
            Button("취소", role: .cancel) {}
        } message: { row in
            if let cost = row.availability.cost, let shards = store.gachaShards {
                Text(MeText.exchangeConfirmMessage(cost: cost, shards: shards))
            }
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var confirmTitle: String {
        guard let row = confirming, let cost = row.availability.cost else { return "" }
        return MeText.exchangeConfirmTitle(name: row.name, cost: cost)
    }

    @ViewBuilder
    private func exchangeRow(_ row: GachaExchangeRow) -> some View {
        MeCharacterArt(id: row.characterID, size: 44)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let cost = row.availability.cost {
                Text(costLine(row.availability, cost: cost))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(row.availability.canExchange ? MobileTheme.label2 : MobileTheme.label3Text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MeText.exchangeRowAccessibility(name: row.name, availability: row.availability)))
        Spacer(minLength: MobileTheme.space2)
        trailing(row)
    }

    /// "조각 5개" · 모자라면 "조각 5개 · 조각 2개 더 필요해요".
    private func costLine(_ availability: GachaExchangeAvailability, cost: Int) -> String {
        if case .short(_, let missing) = availability {
            return "\(GachaText.shardCost(cost)) · \(GachaText.shardShortfall(missing: missing))"
        }
        return GachaText.shardCost(cost)
    }

    @ViewBuilder
    private func trailing(_ row: GachaExchangeRow) -> some View {
        if store.exchangingID == row.characterID {
            ProgressView().controlSize(.small)
                .frame(minWidth: AingButtonMetrics.minimumTarget, minHeight: AingButtonMetrics.minimumTarget)
        } else if row.availability == .owned {
            Text(GachaText.owned)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
        } else {
            Button(GachaText.exchangeButton) { confirming = row }
                .buttonStyle(AingButtonStyle(.tinted, size: .sm))
                .disabled(!row.availability.canExchange || store.exchangingID != nil)
                .accessibilityLabel(Text(MeText.exchangeRowAccessibility(name: row.name, availability: row.availability)))
        }
    }
}
#endif
