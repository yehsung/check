#if os(iOS)
import CheckCore
import SwiftUI

/// 판돈 시트(맥 `GomokuStakePrompt` 흐름): **아무것도 안 골라진 채** 열리고, 판돈은 고르기만(다시 누르면 해제),
/// 신청은 맨 아래 채운 버튼 하나 — 고르기 전에는 "판돈을 고르세요"로 비활성이다(비평: 판돈 버튼이 곧바로 신청하는지 모양으로 알 수 없었다).
/// 닫기는 왼쪽 위 유리 ✕ 하나(공용 `SheetHeader` — 아래 [취소]를 또 두지 않는다). 잔액이 모자란 판돈은 흐린 가격 + 비활성,
/// **잔액을 모르면 막지 않는다**(맥 0.3.29). 신청할 때 고른 값을 `selectedStake` 에 적는다(결과의 [다시 신청]이 쓴다).
struct GamesGomokuStakeSheet: View {
    let store: GomokuStore
    let target: GomokuUser

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: GomokuStake?

    /// 공유 미러(나 탭 상점 구매도 적는다) 먼저 — `GamesStore.rubyBalance` 와 같은 순서.
    private var balance: Int? { store.host?.rubyBalance ?? store.rubyBalance }

    private var sendable: GomokuStake? {
        guard let selected, GomokuPhoneStakeSelection.affordable(selected, balance: balance), !store.isBusy else { return nil }
        return selected
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(GomokuPhoneText.stakeTitle, subtitle: GomokuPhoneText.stakePromptTitle(name: target.displayName), onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    InsetGroup {
                        GroupRow(divider: .none, minHeight: 64) {
                            PersonAvatar(name: target.displayName, colorSeed: target.id, status: target.presence, url: target.avatarLink, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                PersonName(target.displayName, center: CenterLabel.serverValue(forDisplay: target.center))
                                Text(selected.map { GomokuPhoneText.stakePromptChosen($0.rawValue) } ?? GomokuPhoneText.stakePromptCaption)
                                    .font(MobileTheme.rowSubtitle)
                                    .monospacedDigit()
                                    .foregroundStyle(selected == nil ? MobileTheme.label2 : MobileTheme.accent)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    // 큰 글자에서는 세로로 — 가로 셋에 "10" 이 줄바꿈되어 "1/0" 으로 읽혔다(AX 스크린샷 실측).
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(spacing: 10) {
                                ForEach(GomokuStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        } else {
                            HStack(spacing: 10) {
                                ForEach(GomokuStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(GomokuPhoneText.myRubyTitle)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                            if let balance {
                                RubyPrice(balance, isShort: false, gemSize: 14, style: .footnote)
                            } else {
                                Text("–").font(.footnote).foregroundStyle(MobileTheme.label2)
                            }
                            if GomokuStake.allCases.contains(where: { !GomokuPhoneStakeSelection.affordable($0, balance: balance) }) {
                                Text("· " + GomokuPhoneText.stakeShortfall)
                                    .font(.footnote)
                                    .foregroundStyle(MobileTheme.label2)
                            }
                        }
                        Text(GomokuPhoneText.stakeCaption)
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space4)
            }
            AingButton(selected.map { GomokuPhoneText.challengeWithStake($0.rawValue) } ?? GomokuPhoneText.stakePromptCaption,
                       kind: .filled, size: .lg, fillsWidth: true) {
                guard let stake = sendable else { return }
                store.selectedStake = stake
                dismiss()
                Task { await store.challenge(userID: target.id) }
            }
            .disabled(sendable == nil)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space3)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    /// 판돈 칸 하나 — **고르기만** 한다(선택 = 파랑 틴트 + 파랑 테두리 + 체크). 모자라면 흐린 가격 + 비활성.
    private func stakeOption(_ stake: GomokuStake) -> some View {
        let isSelected = selected == stake
        let affordable = GomokuPhoneStakeSelection.affordable(stake, balance: balance)
        let enabled = affordable && !store.isBusy
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selected = GomokuPhoneStakeSelection.toggled(current: selected, tapped: stake)
            }
        } label: {
            VStack(spacing: 2) {
                RubyPrice(stake.rawValue, isShort: !affordable, gemSize: 20, style: .title3)
                Text("이기면 +\(stake.rawValue)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(affordable ? MobileTheme.label2 : MobileTheme.label3Text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(shape.fill(isSelected ? MobileTheme.accentTint : MobileTheme.surface))
            .overlay(shape.strokeBorder(isSelected ? MobileTheme.accent : Color.clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MobileTheme.accent)
                        .padding(7)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("판돈 루비 \(stake.rawValue)")
        .accessibilityValue(isSelected ? "선택됨" : (affordable ? "" : GomokuPhoneText.stakeShortfall))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 규칙 시트: 설명 일곱 줄 + 예시 판 여섯(맥 `GomokuRulesOverlay` 와 같은 내용). 머리는 공용 `SheetHeader`(왼쪽 위 ✕).
struct GamesGomokuRulesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(GomokuPhoneText.rulesTitle, subtitle: GomokuPhoneText.subtitle, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    InsetGroup {
                        let lines = GomokuPhoneRuleExample.ruleLines
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            GroupRow(divider: index == lines.count - 1 ? .none : .inset(MobileTheme.cardPadding + 22 + MobileTheme.space3)) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(MobileTheme.accent)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(MobileTheme.accentTint))
                                    .accessibilityHidden(true)
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(MobileTheme.label)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(GomokuPhoneRuleExample.all) { example in
                            exampleTile(example)
                        }
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space6)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
    }

    private func exampleTile(_ example: GomokuPhoneRuleExample) -> some View {
        let good = example.expected == .win || example.expected == .legal
        return VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        GamesGomokuBoardCanvas(
                            board: example.board,
                            geometry: GomokuPhoneBoardGeometry(side: geo.size.width, lines: GomokuPhoneRuleExample.cropLines,
                                                               originX: GomokuPhoneRuleExample.cropOriginX,
                                                               originY: GomokuPhoneRuleExample.cropOriginY, insetRatio: 0.07),
                            marks: example.marks,
                            showsCoordinates: false
                        )
                    }
                }
                .accessibilityHidden(true)
            // 되는 수는 초록이 아니다(초록 = 근무 중·달성) — 기본 글자 + 체크, 금수만 빨강 + ✕.
            Label {
                Text(example.title)
            } icon: {
                Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(good ? MobileTheme.label2 : MobileTheme.danger)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(good ? MobileTheme.label : MobileTheme.danger)
            Text(example.detail)
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous).fill(MobileTheme.surface))
        .accessibilityElement(children: .combine)
    }
}
#endif
