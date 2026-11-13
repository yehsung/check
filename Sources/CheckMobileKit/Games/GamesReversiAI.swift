import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **로봇 연습**(판 갈래 2/4 — 맥 [AI와 두기] 와 같은 단계·흐름).
//
// 흐름(맥 `ReversiAIPrompt` 그대로): 입구 → 돌 색 고르기(흑 · 백 · 무작위) → **고르면 곧바로 판**(걸 것이 없어 확인 단계가 없다) →
// 대국 화면(`GamesReversiMatchView` — 1:1 과 같은 화면, 판 종류별 차이는 `GamesReversiMatchChrome`) → 결과에서 [같은 색으로 다시 두기].
// 규칙·시계·AI·애니메이션은 **전부 코어**다(`ReversiStoreAI` · `ReversiAIGame`). 이 파일은 코어를 고치지 않는다.
//
// 시계 멈춤 규칙(코어 `ReversiStoreAI` 머리말): 사람 시계는 **화면이 보이고 안 가려졌을 때만** 돈다. 폰에서 그 두 깃발을 켜고 끄는 것은
// `GamesStore` 의 화면 수명(나타남 → `windowDidShow` · 사라짐 → `windowDidHide` · 앱 background → 가림)이다 — 그래서 이 화면은
// 시계를 손대지 않는다. 사람 차례 30초가 지나면 코어가 사람 합법 수 가운데 하나를 대신 두고, 연속 3번이면 사람이 진다(1:1 과 같다).
// 로봇 판은 루비·전적·순위·미션에 남지 않는다(코어 `onMatchFinished` 가 로봇 판에 안 운다).
//
// ★ 입구를 여는 판정은 코어 `canStartAIMatch` **하나**다(여기서 다시 세면 클라 게이트가 짝으로 갈린다). 이 파일은 닫혔을 때
//   **무엇을 말할지**만 고른다(`GamesReversiAIEntry.block`).
// ★ 받은 1:1 신청을 로봇 판 중에 수락하는 길은 먼저 물어야 한다(`GamesStore.hasLiveReversiAIGame` 머리말 — 코어 `respond` 에
//   로봇 판 가드가 없어 1:1 이 서는 순간 두던 판이 말없이 사라진다). 그 확인은 신청 카드를 그리는 로비 갈래의 몫이다.

// MARK: - 판정 표 (순수)

/// 돌 색 고르기 세 칸(맥 `ReversiAIPrompt` 와 같은 셋 — 순서도 같다).
package enum GamesReversiAIColorChoice: CaseIterable, Equatable, Sendable {
    case black, white, random

    /// 코어 `startAIMatch(humanColor:)` 에 넘길 값. 무작위는 nil(코어가 고른다 — 화면이 주사위를 굴리지 않는다).
    package var humanColor: ReversiColor? {
        switch self {
        case .black: return .black
        case .white: return .white
        case .random: return nil
        }
    }

    package var title: String {
        switch self {
        case .black: return ReversiPhoneText.aiPlayBlack
        case .white: return ReversiPhoneText.aiPlayWhite
        case .random: return ReversiPhoneText.aiPlayRandom
        }
    }
}

/// 로봇 연습 입구가 그리는 것(열렸는가 · 닫혔으면 까닭 한 줄).
package struct GamesReversiAIEntry: Equatable, Sendable {
    package let canStart: Bool
    package let block: ReversiPhoneText.AIBlock?

    @MainActor
    package init(store: ReversiStore) {
        canStart = store.canStartAIMatch
        block = Self.block(store: store)
    }

    /// 입구 둘째 줄 — 열렸으면 무엇을 하는 곳인지, 닫혔으면 **언제 풀리는지**.
    package var caption: String { block.map(ReversiPhoneText.aiBlock) ?? ReversiPhoneText.aiButtonHelp }

    /// 닫힌 까닭 하나(열려 있으면 nil). 서열: 판 > 보낸 신청 > 오가는 요청 — 보낸 신청은 **취소로 당장 풀 수 있는** 막힘이라
    /// 판과 다른 말을 들어야 한다(체스 실측 D3 — 신청만 보낸 사람이 "두는 중이에요" 를 들었다).
    @MainActor
    package static func block(store: ReversiStore) -> ReversiPhoneText.AIBlock? {
        guard !store.canStartAIMatch else { return nil }
        if store.match != nil || store.activeMatchID != nil || store.phase != .lobby { return .playing }
        if store.outgoing != nil { return .outgoingInvite }
        return .busy
    }
}

#if os(iOS)

// MARK: - 입구 (로비 안)

/// 로비의 [로봇과 연습하기] 카드. 맥은 로비 머리글에만 버튼을 세운다(판 중에 새 판을 열 길을 두지 않는다) — 폰도 로비에만 있다.
/// 누르면 돌 색 시트가 뜬다(시트의 주인은 화면 루트 — `onPlay`).
struct GamesReversiAIEntryCard: View {
    let store: ReversiStore
    let onPlay: () -> Void

    var body: some View {
        let entry = GamesReversiAIEntry(store: store)
        InsetGroup {
            Button(action: onPlay) {
                GroupRow(divider: .none, minHeight: MobileTheme.rowHeightTwoLine) {
                    CharacterPortrait(id: ReversiUser.reversiAI.characterID, mood: .plain, size: 36)
                        .opacity(entry.canStart ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ReversiPhoneText.aiButton)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(entry.canStart ? MobileTheme.label : MobileTheme.label2)
                        Text(entry.caption)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if entry.canStart {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MobileTheme.label3)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .disabled(!entry.canStart)
            .accessibilityHint(ReversiPhoneText.aiNoRecord)
        }
    }
}

// MARK: - 돌 색 시트

/// 돌 색 시트(맥 `ReversiAIPrompt`): 흑 · 백 · 무작위 — 누르면 **곧바로 시작**한다. 닫기는 왼쪽 위 ✕ 하나(공용 `SheetHeader`).
/// 시트가 떠 있는 동안 1:1 판이 서거나 신청을 보내면 세 칸이 비활성으로 바뀐다(판정은 코어 `canStartAIMatch` 하나).
struct GamesReversiAIColorSheet: View {
    let store: ReversiStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let entry = GamesReversiAIEntry(store: store)
        VStack(spacing: 0) {
            SheetHeader(ReversiPhoneText.aiPromptTitle, subtitle: ReversiPhoneText.aiPromptCaption, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    // 큰 글자에서는 세로로 — 세 칸을 한 줄에 두면 "나중에 둬요"가 낱글자로 꺾인다.
                    Group {
                        if typeSize >= .xxLarge {
                            VStack(spacing: 10) { options(enabled: entry.canStart) }
                        } else {
                            HStack(spacing: 10) { options(enabled: entry.canStart) }
                        }
                    }
                    if let block = entry.block {
                        InlineNotice(text: ReversiPhoneText.aiBlock(block), kind: .warning)
                    }
                    Label {
                        Text(ReversiPhoneText.aiNoRecord)
                    } icon: {
                        Image(systemName: "cpu")
                            .foregroundStyle(MobileTheme.accent)
                    }
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space4)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        // 큰 글자(접근성 크기)에서는 처음부터 크게 — 반 높이에서는 세 칸 아래 '기록 없음' 한 줄이 잘린다(오목 AX3 실측).
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func options(enabled: Bool) -> some View {
        ForEach(GamesReversiAIColorChoice.allCases, id: \.self) { choice in
            option(choice, enabled: enabled)
        }
    }

    private func option(_ choice: GamesReversiAIColorChoice, enabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            dismiss()
            store.startAIMatch(humanColor: choice.humanColor)
        } label: {
            VStack(spacing: 8) {
                GamesReversiStoneDot(color: choice.humanColor, size: 30)
                Text(choice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(enabled ? MobileTheme.label : MobileTheme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(shape.fill(MobileTheme.surface))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(ReversiPhoneText.aiNoRecord)
    }
}

#endif
