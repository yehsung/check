#if os(iOS)
import CheckCore
import SwiftUI

/// 판돈 시트(맥 `GomokuStakePrompt` 흐름): **아무것도 안 골라진 채** 열리고, 판돈은 고르기만(다시 누르면 해제),
/// 맨 아래 버튼이 미선택이면 [취소], 고르면 [N 걸고 도전하기]. 잔액이 모자란 판돈은 비활성 + 이유 한 줄,
/// **잔액을 모르면 막지 않는다**(맥 0.3.29). 신청할 때 고른 값을 `selectedStake` 에 적는다(결과의 [다시 신청]이 쓴다).
struct GamesGomokuStakeSheet: View {
    let store: GomokuStore
    let target: GomokuUser

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: GomokuStake?

    private var balance: Int? { store.rubyBalance ?? store.host?.rubyBalance }

    private var sendable: GomokuStake? {
        guard let selected, GomokuPhoneStakeSelection.affordable(selected, balance: balance), !store.isBusy else { return nil }
        return selected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        AvatarView(name: target.displayName, url: target.avatarURL.flatMap(URL.init(string:)), size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GomokuPhoneText.stakePromptTitle(name: target.displayName))
                                .font(.headline)
                                .foregroundStyle(MobileTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(selected.map { GomokuPhoneText.stakePromptChosen($0.rawValue) } ?? GomokuPhoneText.stakePromptCaption)
                                .font(.subheadline)
                                .foregroundStyle(selected == nil ? MobileTheme.secondaryText : MobileTheme.primaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    // 큰 글자에서는 세로로 — 가로 셋에 "10" 이 줄바꿈되어 "1/0" 으로 읽혔다(AX 스크린샷 실측).
                    if typeSize.isAccessibilitySize {
                        VStack(spacing: 10) {
                            ForEach(GomokuStake.allCases, id: \.rawValue) { stake in stakeButton(stake) }
                        }
                    } else {
                        HStack(spacing: 10) {
                            ForEach(GomokuStake.allCases, id: \.rawValue) { stake in stakeButton(stake) }
                        }
                    }
                    if GomokuStake.allCases.contains(where: { !GomokuPhoneStakeSelection.affordable($0, balance: balance) }) {
                        Text(GomokuPhoneText.stakeShortfall)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MobileTheme.pending)
                    }
                    HStack(spacing: 6) {
                        Text("내 루비")
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.secondaryText)
                        RubyLabel(balance, style: .footnote)
                    }
                    Text(GomokuPhoneText.stakeCaption)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    bottomButton
                }
                .padding(20)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(GomokuPhoneText.stakeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(GomokuPhoneText.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stakeButton(_ stake: GomokuStake) -> some View {
        let isSelected = selected == stake
        let enabled = GomokuPhoneStakeSelection.affordable(stake, balance: balance) && !store.isBusy
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selected = GomokuPhoneStakeSelection.toggled(current: selected, tapped: stake)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .foregroundStyle(isSelected ? MobileTheme.onAccent : MobileTheme.ruby)
                Text("\(stake.rawValue)")
                    .font(MobileTheme.number(.title3, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isSelected ? MobileTheme.onAccent : MobileTheme.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? MobileTheme.accent : MobileTheme.cardElevated))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? MobileTheme.accent : MobileTheme.separator, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("판돈 루비 \(stake.rawValue)")
        .accessibilityValue(isSelected ? "선택됨" : (enabled ? "" : GomokuPhoneText.stakeShortfall))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var bottomButton: some View {
        if let selected {
            Button {
                guard let stake = sendable else { return }
                store.selectedStake = stake
                dismiss()
                Task { await store.challenge(userID: target.id) }
            } label: {
                Label(GomokuPhoneText.challengeWithStake(selected.rawValue), systemImage: "bolt.fill")
            }
            .buttonStyle(AingPrimaryButtonStyle())
            .disabled(sendable == nil)
        } else {
            Button(GomokuPhoneText.cancel) { dismiss() }
                .buttonStyle(GamesCompactButtonStyle(kind: .outline, fillsWidth: true))
        }
    }
}

/// 규칙 시트: 설명 일곱 줄 + 예시 판 여섯(맥 `GomokuRulesOverlay` 와 같은 내용).
struct GamesGomokuRulesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(GomokuPhoneRuleExample.ruleLines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(MobileTheme.accent)
                                    .frame(minWidth: 22, minHeight: 22)
                                    .background(Circle().fill(MobileTheme.accent.opacity(0.16)))
                                    .accessibilityHidden(true)
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(MobileTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], alignment: .leading, spacing: 16) {
                        ForEach(GomokuPhoneRuleExample.all) { example in
                            exampleTile(example)
                        }
                    }
                }
                .padding(20)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(GomokuPhoneText.rulesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(GomokuPhoneText.close) { dismiss() }
                }
            }
        }
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
            Text(example.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(good ? MobileTheme.working : MobileTheme.danger)
            Text(example.detail)
                .font(.caption)
                .foregroundStyle(MobileTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
