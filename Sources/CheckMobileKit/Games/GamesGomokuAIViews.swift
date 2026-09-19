#if os(iOS)
import CheckCore
import SwiftUI

// 폰 AI 오목 화면 조각(1.0.1) — 입구(로비 카드) · 돌 색 시트 · AI 초상 · "생각 중" 표시. 대국·결과 화면 본체는 사람 대국 화면
// (`GamesGomokuMatch` · `GamesGomokuResult`)을 그대로 쓰고, 판 종류별 차이는 `GomokuPhoneMatchChrome` 표 하나로 가른다.
// 맥 대응: `GomokuHeader` 의 [AI와 두기] · `GomokuAIPrompt` · `GomokuAIPortrait` · `GomokuAIThinkingMark`(Sources/check/GomokuPanel.swift).

/// 로비의 [AI와 두기] 카드. 맥은 로비 머리글에만 버튼을 세운다(대국·결과 중에 새 판을 열 길을 두지 않는다) — 폰도 로비에만 있다.
/// 1:1 판이 열려 있거나 보낸 신청이 떠 있으면 누를 수 없다(코어 `canStartAIMatch` — 신청이 수락되는 순간 1:1 이 AI 판을 이긴다).
struct GamesGomokuAIEntryCard: View {
    let store: GomokuStore
    let onPlay: () -> Void

    var body: some View {
        let enabled = store.canStartAIMatch
        InsetGroup {
            Button(action: onPlay) {
                GroupRow(divider: .none, minHeight: 56) {
                    GamesGomokuAIPortrait(size: 36)
                        .opacity(enabled ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GomokuPhoneText.aiButton)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(enabled ? MobileTheme.label : MobileTheme.label2)
                        Text(GomokuPhoneText.aiButtonHelp)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if enabled {
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
            .disabled(!enabled)
            .accessibilityHint(GomokuPhoneText.aiPromptCaption)
        }
    }
}

/// 돌 색 시트(맥 `GomokuAIPrompt`): 흑 · 백 두 칸 — 누르면 **곧바로 시작**한다(걸 것이 없어 확인 단계를 두지 않는다 — 맥과 같다).
/// 닫기는 왼쪽 위 ✕ 하나(공용 `SheetHeader`). 시트가 떠 있는 동안 1:1 판이 열리거나 신청을 보내면 두 칸이 비활성으로 바뀐다.
struct GamesGomokuAIColorSheet: View {
    let store: GomokuStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(GomokuPhoneText.aiPromptTitle, subtitle: GomokuPhoneText.aiPromptCaption, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    // 큰 글자에서는 세로로 — 반 폭 두 칸에서는 "나중에 둬요"가 낱글자로 꺾인다(판돈 시트와 같은 규칙).
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(spacing: 10) { option(.black); option(.white) }
                        } else {
                            HStack(spacing: 10) { option(.black); option(.white) }
                        }
                    }
                    Label {
                        Text(GomokuPhoneText.aiNoRecord)
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
        // 큰 글자(접근성 크기)에서는 처음부터 크게 — 반 높이에서는 두 칸 아래 '기록 없음' 한 줄이 잘려 보였다(AX3 스크린샷 실측).
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func option(_ color: GomokuColor) -> some View {
        let enabled = store.canStartAIMatch
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            dismiss()
            store.startAIMatch(humanColor: color)
        } label: {
            VStack(spacing: 8) {
                GamesStoneDot(color: color, size: 30)
                Text(color == .black ? GomokuPhoneText.aiPlayBlack : GomokuPhoneText.aiPlayWhite)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(enabled ? MobileTheme.label : MobileTheme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(shape.fill(MobileTheme.surface))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(GomokuPhoneText.aiNoRecord)
    }
}

/// AI 상대의 얼굴(캐릭터 자리): 파랑 틴트 원 + `cpu` 기호 — 맥 `GomokuAIPortrait` 와 같은 기호. 돌 배지는 캐릭터 초상과 같은 자리·크기.
struct GamesGomokuAIPortrait: View {
    let size: CGFloat
    var stone: GomokuColor?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(MobileTheme.accentTint)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(MobileTheme.accent)
                )
                .frame(width: size, height: size)
            if let stone {
                let side = max(12, min(20, size * 0.3))
                GamesStoneDot(color: stone, size: side)
                    .overlay(Circle().strokeBorder(MobileTheme.surface, lineWidth: 2).padding(-2))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GomokuUser.gomokuAI.displayName)
    }
}

/// AI 차례에 초 링 자리(44pt)에 서는 "생각 중" 표시 — 맥 `GomokuAIThinkingMark`(원 + 말줄임표 + "생각 중")와 같은 모양이고,
/// 말줄임표가 차례로 밝아져 판이 멈춘 것처럼 보이지 않는다(동작 줄이기를 켜면 멈춘 말줄임표 — 맥과 같은 정지 모양). 시계를 읽지 않는다 —
/// AI 차례에는 마감이 없다(링을 두면 0초로 빨갛게 선다).
struct GamesGomokuAIThinkingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(MobileTheme.accent.opacity(0.35), lineWidth: 4)
            VStack(spacing: 0) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                Text(GomokuPhoneText.aiThinkingShort)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(MobileTheme.accent)
        }
        .padding(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GomokuPhoneText.aiThinking)
    }
}

/// 돌 하나(판 그림과 같은 칠 — `GamesGomokuBoardCanvas.drawStone`).
struct GamesStoneDot: View {
    let color: GomokuColor
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            // 그림자(아래로 r·0.14)까지 칸 안에 들게 반지름을 줄인다.
            let radius = min(canvasSize.width, canvasSize.height) / 2 * 0.86
            GamesGomokuBoardCanvas.drawStone(&context, at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                                             radius: radius, color: color, opacity: 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
#endif
