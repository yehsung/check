#if os(iOS)
import CheckCore
import SwiftUI

/// 상점 '오목알' 절(폰 1.0.18 — 맥 0.3.81 상점 '오목알' 탭과 같은 규약). '일반 돌' + 서버가 말한 스킨 칸.
/// 가진 칸 · '일반 돌'을 누르면 바로 낀다. 안 가진 칸을 누르면 확인 뒤 산다(사면 서버가 바로 끼운다 — 칸 탭만으로는 사지 않는다).
struct MeOmokSkinSection: View {
    let store: MeStore
    @State private var buying: OmokStoneSkin?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(OmokSkinPhoneText.title, trailing: .text(OmokSkinPhoneText.note))
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space1)
            LazyVGrid(columns: MeCharacterTile.columns(dynamicTypeSize), spacing: 10) {
                tile(nil)
                ForEach(store.omokSkins?.rows ?? []) { row in tile(row.skin) }
            }
            if let notice = store.omokSkinNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            }
        }
        .confirmationDialog(buying.map(OmokSkinPhoneText.confirmTitle) ?? "", isPresented: Binding(
            get: { buying != nil }, set: { if !$0 { buying = nil } }
        ), titleVisibility: .visible) {
            Button(MeText.buyAction) { if let skin = buying { store.buyOmokSkin(skin) } }
            Button("취소", role: .cancel) {}
        } message: {
            if let skin = buying, let price = store.omokSkinPrice(skin), let balance = store.rubyBalance {
                Text(MeText.purchaseConfirmMessage(price: price, balance: balance))
            }
        }
    }

    private func tile(_ skin: OmokStoneSkin?) -> some View {
        let owned = skin.map(store.isOmokSkinOwned) ?? true
        let equipped = store.equippedOmokSkin == skin
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            if owned { store.equipOmokSkin(skin) } else if let skin { buying = skin }
        } label: {
            VStack(spacing: 8) {
                MeOmokSkinPreview(skin: skin)
                    .frame(height: 44)
                Text(OmokSkinPhoneText.name(skin))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                status(skin: skin, owned: owned, equipped: equipped)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(shape.fill(equipped ? MobileTheme.accentTint : MobileTheme.surface))
            .overlay(shape.strokeBorder(equipped ? MobileTheme.accent : .clear, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(store.omokSkinBusy != nil)
        .accessibilityLabel(Text(accessibility(skin: skin, owned: owned, equipped: equipped)))
    }

    @ViewBuilder
    private func status(skin: OmokStoneSkin?, owned: Bool, equipped: Bool) -> some View {
        if equipped {
            Text(OmokSkinPhoneText.equippedBadge).font(.caption.weight(.semibold)).foregroundStyle(MobileTheme.accent)
        } else if owned {
            Text(OmokSkinPhoneText.owned).font(.caption).foregroundStyle(MobileTheme.label2)
        } else if let skin, let price = store.omokSkinPrice(skin) {
            RubyPrice(price, balance: store.rubyBalance, gemSize: 14, style: .caption)
        } else {
            Text("—").font(.caption).foregroundStyle(MobileTheme.label2)
        }
    }

    private func accessibility(skin: OmokStoneSkin?, owned: Bool, equipped: Bool) -> String {
        let name = OmokSkinPhoneText.name(skin)
        if equipped { return "\(name) 오목알, \(OmokSkinPhoneText.equippedBadge)" }
        if owned { return "\(name) 오목알, \(OmokSkinPhoneText.owned)" }
        if let skin, let price = store.omokSkinPrice(skin) { return "\(name) 오목알, 루비 \(price)개" }
        return "\(name) 오목알"
    }
}

/// 흑 · 백 돌 한 쌍 미리 보기(오목판 나뭇결 위) — 판과 같은 그림 식(`GamesGomokuBoardCanvas.drawStone`).
struct MeOmokSkinPreview: View {
    let skin: OmokStoneSkin?

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            context.fill(Path(roundedRect: rect, cornerRadius: 8, style: .continuous), with: .color(GamesGomokuBoardCanvas.woodLight))
            let r = min(size.height * 0.36, size.width * 0.2)
            let y = size.height / 2
            GamesGomokuBoardCanvas.drawStone(&context, at: CGPoint(x: size.width / 2 - r * 1.15, y: y), radius: r, color: .black,
                                             opacity: 1, skin: skin, seed: 1)
            GamesGomokuBoardCanvas.drawStone(&context, at: CGPoint(x: size.width / 2 + r * 1.15, y: y), radius: r, color: .white,
                                             opacity: 1, skin: skin, seed: 2)
        }
        .accessibilityHidden(true)
    }
}
#endif
