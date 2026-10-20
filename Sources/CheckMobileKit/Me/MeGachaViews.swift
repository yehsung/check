#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 캐릭터 뽑기 카드 (v0.3.54 · 폰 1.0.8)

/// 상점 맨 위 뽑기 카드: 제목 + 1회 값 · 마지막 결과 한 줄 · [뽑기 · 50] · 막힌 이유 · [확률 보기] [조각 N개 · 교환].
///
/// 판정·문구는 코어(`GachaRules` · `GachaText`)가 맥과 한 벌로 들고 있다 — 이 뷰는 그리기만 한다. 시트(확률표 · 교환)와
/// 기계 덮개는 화면 루트(`MeShopView`)가 띄운다(시트는 루트만 띄운다는 관례).
///
/// v0.3.54 공개판: [뽑기] 는 **캡슐 뽑기 기계**(전체 화면 덮개 · `MeGachaMachineScreen`)를 연다 — 뽑기는 기계의 손잡이가 한다.
/// 예전의 짧은 결과 연출은 걷었고, 카드에는 마지막 결과 한 줄만 남는다(덮개를 공개 전에 닫았어도 무엇을 뽑았는지 보인다).
///
/// [뽑기] 는 **틴트**다: 이 화면의 채운 버튼은 아래 구매 막대 하나다(화면당 채운 버튼 하나 — `MeDesignContractTests`).
/// 뽑을 수 없으면(루비 모자람 · 잔량 모름 · 앞 뽑기가 떠 있음) 잠기고 이유가 아래 줄에 선다.
struct MeGachaCard: View {
    let store: MeStore
    let onPull: () -> Void
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
                    MeGachaLastResultRow(result: result, name: store.gachaName(result.characterID))
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
            onPull()
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

/// 마지막 뽑기 결과 한 줄(움직임 없음 — 연출은 기계 몫이다). 희귀 둘은 그 빛깔 받침 + 테두리 + 머리말:
/// 황금은 금빛 + "황금 아잉이!" · 무지개(v0.3.59)는 일곱 빛 + "무지개 아잉이!" · 새 캐릭터 "새 캐릭터: 여우" ·
/// 중복 "이미 있는 여우 → 조각 +1"(문구·마감은 `MeText.gachaResultLines` → 코어 `GachaText` — 맥과 같은 글자).
///
/// 머리말 **글자**는 희귀여도 `label` 이다: 금빛·무지개를 받침으로 깔고 그 위 글자까지 같은 빛으로 칠하면 라이트에서
/// 4.2:1 로 내려간다(받침 14% 가 바탕을 띄운다). 희귀 표시는 받침 · 1pt 테두리 · 머리말 글귀가 셋이서 한다.
struct MeGachaLastResultRow: View {
    let result: GachaPullResult
    let name: String

    var body: some View {
        let lines = MeText.gachaResultLines(result, name: name)
        let shape = RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            MeCharacterArt(id: result.characterID, size: 40)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(lines.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = lines.detail {
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
        .background(shape.fill(MobileTheme.tint(lines.finish, otherwise: MobileTheme.surface2)))
        .overlay {
            if let rare = MobileTheme.rare(lines.finish) {
                shape.strokeBorder(rare, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([MeText.gachaLastResult, lines.headline, lines.detail].compactMap { $0 }.joined(separator: ", ")))
    }
}

// MARK: - 캡슐 뽑기 기계(전체 화면 덮개)

extension View {
    /// 캡슐 뽑기 기계 덮개(상점 [뽑기] · 뽑기 전용 타일이 연다). 덮개는 아래로 끌어 닫히지 않는다 — 왼쪽 위 ✕ 와 기계의 [닫기] 가 닫는다.
    func gachaMachineCover(store: MeStore, isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            MeGachaMachineScreen(store: store, onClose: { isPresented.wrappedValue = false })
        }
    }
}

/// 캡슐 뽑기 기계를 폰 전체 화면에 띄운다(코어 `GachaMachineView` — 맥 뽑기 창과 같은 뷰 · 같은 그림 `.bundled`).
///
/// - 뽑기: 손잡이 한 바퀴 = `store.pullGachaForMachine()` 한 번(요청 id · 세대 가드 · 루비 미러 · 다시 읽기는 카드와 같은 몸통).
///   기계는 잔액 · 조각을 스스로 안 바꾼다 — 넘기는 값은 전부 스토어의 서버 값이다.
/// - `isActive`: 앱이 앞(`scenePhase == .active`)이고 · 덮개가 떠 있고 · 확률 시트가 기계를 가리지 않을 때만. 아니면 매 프레임 그리기를 멈춘다.
/// - 손잡이 잠금: 로그인 · 뽑기 닫힘 · 잔량 모름 · **이 기계가 모르는 앞 뽑기**(닫았다 다시 연 덮개)만 막는다(`gachaMachineBlockedReason`).
/// - 덮개를 공개 전에 닫아도 요청은 끊기지 않는다(스토어의 일) — 결과는 상점 카드의 마지막 결과 줄에 선다.
struct MeGachaMachineScreen: View {
    let store: MeStore
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var haptics = MeGachaHaptics()
    /// 덮개가 떠 있는가(onAppear ~ onDisappear).
    @State private var isShown = false
    /// 이 기계가 띄운 뽑기가 떠 있는가(그 판은 막지 않는다 — `gachaMachineBlockedReason(machineOwnsPull:)`).
    @State private var ownsPull = false
    @State private var showsOdds = false

    var body: some View {
        GachaMachineView(
            balance: store.rubyBalance ?? 0,
            cost: store.gachaInfo?.price ?? 0,
            shards: store.gachaShards ?? 0,
            rubyIcon: rubyIcon,
            portrait: portrait,
            art: .bundled,
            haptics: haptics,
            isActive: isShown && scenePhase == .active && !showsOdds,
            blockedReason: store.gachaMachineBlockedReason(machineOwnsPull: ownsPull),
            againEnabled: !store.isPulling,
            pull: { try await pull() },
            onClose: onClose
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) { chrome }
        .onAppear {
            isShown = true
            store.gachaMachineDidAppear()
        }
        .onDisappear { isShown = false }
        .sheet(isPresented: $showsOdds) { MeGachaOddsSheet(store: store) }
    }

    /// 왼쪽 위 ✕(시트 머리 관례) · 오른쪽 위 [확률 보기](사기 전에 확률을 볼 수 있는 자리 — 카드와 같은 시트).
    private var chrome: some View {
        HStack {
            GlassCircleButton(systemImage: "xmark", accessibilityLabel: SheetChromeText.close, action: onClose)
            Spacer(minLength: MobileTheme.space2)
            Button { showsOdds = true } label: {
                GlassPill {
                    Image(systemName: "percent")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(GachaText.oddsButton)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(MobileTheme.label)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space2)
    }

    private func pull() async throws -> GachaRevealOutcome {
        ownsPull = true
        defer { ownsPull = false }
        return try await store.pullGachaForMachine()
    }

    private var rubyIcon: Image {
        // 기계 칩은 15~18pt × 무대 배율(≈1.03) — 24pt 로 고르면 3배 화면에서 ruby-96 이 온다(뭉개지지 않는다).
        // 그림이 없으면 빈 자리(루비를 SF 기호로 대신하지 않는다 — `RubyIcon` 과 같은 규칙).
        Image(uiImage: MobileArt.ruby(pointSize: 24, displayScale: displayScale) ?? UIImage())
    }

    private func portrait(_ id: String) -> Image {
        // 기계는 초상을 150~172pt × 무대 배율로 그린다 — 그 크기면 여섯 캐릭터는 무대용 420px, 아잉 · 황금 · 무지개 아잉이는 192px 초상이 온다.
        guard let image = MobileArt.character(id: id, expression: .neutral, pointSize: 180, displayScale: displayScale) else {
            return Image(systemName: "questionmark.circle")
        }
        return Image(uiImage: image)
    }
}

// MARK: - 확률표 시트

/// "확률 보기" 시트: 서버가 준 표 그대로(순서까지) — 캐릭터 · 상점가(뽑기 전용이면 그 말) · 확률 + 규칙 한 줄.
/// 앱스토어 지침(확률형 아이템은 **사기 전에** 확률 공개)이 요구하는 자리다 — 표가 불완전하면 카드가 아예 안 서므로
/// 여기 오는 표는 늘 합 100% 다(`GachaInfo.isUsable`). **합계 줄은 두지 않는다** — 화면 표시는 한 자리 반올림이라 더하면 100.1% 가 된다.
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
                            // 희귀 둘(황금 · 무지개)은 같은 급으로 강조한다 — 이름을 굵게, 이름·확률을 그 빛깔로. 가름은
                            // `MeText.gachaOddsEmphasized`(= `finish.isRare`)뿐이다(`isGold` 로 가르면 무지개가 평범해진다).
                            let emphasized = MeText.gachaOddsEmphasized(row)
                            let ink = MobileTheme.ink(row.finish, otherwise: MobileTheme.label)
                            GroupRow(divider: index == rows.count - 1 ? .none : .inset(MobileTheme.cardPadding + 40 + MobileTheme.space3)) {
                                MeCharacterArt(id: row.characterID, size: 40)
                                    .frame(width: 40, height: 40)
                                    .accessibilityHidden(true)
                                Text(row.name)
                                    .font(.subheadline.weight(emphasized ? .bold : .semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: MobileTheme.space2)
                                priceCell(row)
                                    .frame(minWidth: 72, maxWidth: 104, alignment: .trailing)
                                Text(row.percentText)
                                    .font(.subheadline.weight(emphasized ? .bold : .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(ink)
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
        // 표 전체(여덟 줄 + 규칙 한 줄 — v0.3.59 무지개)가 한 번에 보이게 — 중간 높이면 마지막 줄이 잘려 공개한 확률이 반만 보인다.
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func priceCell(_ row: GachaOddsRow) -> some View {
        if let price = row.shopPrice {
            RubyPrice(price, isShort: false, gemSize: 14, style: .footnote)
        } else {
            // 희귀 줄(금 · 무지개)은 "뽑기 또는 조각 20개"(코어 문구)처럼 길 수 있다 — 두 줄까지 접고 오른쪽에 붙인다(글자를 줄여 숨기지 않는다).
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

/// 조각 교환: 서버 교환표 그대로(**코어가 준 순서** — 황금 아잉이 → 무지개 아잉이 → 서버 순서. 화면이 다시 정렬하지 않는다) · 줄마다 그림 · 이름 · 값 · [교환](모자라면 잠김 · 가졌으면 "보유").
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
        // 희귀 둘은 이름을 그 빛깔로(금빛 · 일곱 빛) — 확률 시트와 같은 급. 값 줄은 코어 문구 그대로("조각 20개").
        let finish = CharacterManifest.Finish(characterID: row.characterID)
        MeCharacterArt(id: row.characterID, size: 44)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.subheadline.weight(finish.isRare ? .bold : .semibold))
                .foregroundStyle(MobileTheme.ink(finish, otherwise: MobileTheme.label))
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
