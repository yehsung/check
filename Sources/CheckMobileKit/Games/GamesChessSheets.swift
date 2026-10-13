#if os(iOS)
import CheckCore
import SwiftUI

// 1:1 체스 **폰 시트 셋**(인수인계 §7) — 승격 고르기 · 규칙 보기 · 무승부 제안·응답.
// 오목 짝은 `GamesGomokuSheets.swift` 이고 머리·바탕·버튼 규약을 그대로 따른다:
// 머리는 공용 `SheetHeader`(왼쪽 위 유리 ✕ 하나 — 아래에 [취소]를 또 두지 않는다), 바탕은 `MobileTheme.background`,
// 채운 버튼은 화면당 하나.
//
// **문구는 한 줄도 여기서 만들지 않는다** — 전부 `ChessPhoneText`(= `GamesChessText`)에서 온다. 그래야 맥 스위트가
// 값으로 잴 수 있다(폰 뷰는 맥 스위트가 못 본다 · `ios/scripts/build-sim.sh` 가 이 파일의 유일한 그물이다).

// MARK: - 승격 고르기 (★ 입력 2단의 셋째 단)

/// 승격 시트. **도착 칸이 같은 합법수가 넷일 때만** 열린다(`ChessStore.commit` 이 `candidates.count > 1` 로 판정한다 —
/// 체스에 다른 경우는 없다). 고르기 전에는 수가 **나가지 않는다**: 네 말 중 하나를 눌러야 `chess_move` 가 떠난다.
///
/// ★ 내려가는 길을 둘로 묶어 뒀다. 쓸어내려 닫기(`interactiveDismissDisabled`)를 막은 까닭은 그 길이
///   `store.cancelPromotion()` 을 지나지 않기 때문이다 — 안 막으면 스토어에는 `promotion` 이 남고 끌어 놓은 폰은
///   도착 칸에 뜬 채 굳는다(판은 아직 안 바뀌었는데 화면만 바뀐 꼴). 그래서 ✕ 와 [다른 수 두기] 둘 다 같은
///   함수를 지난다.
struct GamesChessPromotionSheet: View {
    let store: ChessStore
    let prompt: ChessPromotionPrompt
    /// 승격하는 쪽의 색(= 내 색). 그림이 판과 같은 색으로 서야 고른 말이 어떻게 설지 눈으로 맞춰진다.
    let myColor: ChessColor

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        // 큰 글자에서는 한 줄에 하나 — 말 이름("나이트")이 두 칸 가로에서 줄바꿈되어 글자가 먼저 잘렸다(오목 판돈 시트와 같은 이유).
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(ChessPhoneText.promotionTitle, subtitle: ChessPhoneText.promotionCaption,
                        onClose: { cancel() })
            ScrollView {
                LazyVGrid(columns: columns, spacing: MobileTheme.space3) {
                    ForEach(prompt.choices, id: \.rawValue) { kind in
                        choice(kind)
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space4)
            }
            AingButton(ChessPhoneText.promotionCancel, kind: .gray, size: .lg, fillsWidth: true) { cancel() }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.bottom, MobileTheme.space3)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }

    /// 말 한 칸 — 그림 + 이름. 누르면 **그 말로 승격한 수가 나간다**(한 번에 끝난다 — 고르고 확인하는 2단이 아니다).
    private func choice(_ kind: ChessPieceKind) -> some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            dismiss()
            Task { await store.choosePromotion(kind) }
        } label: {
            VStack(spacing: 4) {
                GamesChessPieceTile(kind: kind, color: myColor, side: 56)
                Text(ChessPhoneText.pieceName(kind))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(shape.fill(MobileTheme.surface))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
        .accessibilityLabel(ChessPhoneText.pieceName(kind))
        .accessibilityHint(ChessPhoneText.promotionTitle)
    }

    private func cancel() {
        dismiss()
        store.cancelPromotion()
    }
}

/// 승격 시트의 말 한 칸 그림 — **판과 같은 한 벌**(`ChessPieceArt`)로 그린다.
///
/// ★ 자리표시(유니코드 ♔♕♖♗♘♙)를 걷어낸 자리다. 판은 벡터 실루엣인데 시트만 글리프면 **같은 말이 두 모양**이고,
///   고른 말이 판에 어떻게 설지 눈으로 맞춰지지 않는다(그것이 이 칸의 유일한 일이다). 색·테두리 굵기도 판 부품의
///   상수를 그대로 쓴다 — 여기서 색을 새로 고르면 시트와 판의 흑백 대비가 갈린다.
struct GamesChessPieceTile: View {
    let kind: ChessPieceKind
    let color: ChessColor
    let side: CGFloat

    var body: some View {
        Canvas { context, size in
            // `path(for:in:)` 가 안에서 `box(in:)` 로 여백을 잡는다 — 칸 사각형을 그대로 넘긴다.
            let path = ChessPieceArt.path(for: kind, in: CGRect(origin: .zero, size: size))
            context.fill(path, with: .color(color == .white ? GamesChessBoardCanvas.whitePiece
                                                            : GamesChessBoardCanvas.blackPiece))
            context.stroke(path,
                           with: .color(color == .white ? GamesChessBoardCanvas.whitePieceEdge
                                                        : GamesChessBoardCanvas.blackPieceEdge),
                           lineWidth: max(0.8, min(size.width, size.height) * 0.035))
        }
        .frame(width: side, height: side)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MobileTheme.fill))
        .accessibilityHidden(true)
    }
}

// MARK: - 규칙 보기

/// 규칙 시트: FIDE 요약 여덟 줄(맥 `ChessRulesOverlay` 와 같은 내용 + 폰이 더한 시계·판돈·한 사람 한 판).
/// 예시 판을 두지 않는다 — 체스는 한 국면이 규칙 하나를 말해 주지 않고(오목의 금수 예시와 다르다), 대신
/// 글 여덟 줄이 돈이 갈리는 셋(시간·판돈·한 사람 한 판)을 다 말한다.
///
/// 시간 수치는 **스토어가 서버에서 받은 값**을 넘겨받는다(기본값은 로비를 읽기 전의 자리표시다).
struct GamesChessRulesSheet: View {
    var initialMs: Int = ChessClock.initialMs
    var incrementMs: Int = Int(ChessClock.incrementSeconds * 1000)
    var inviteTtlSeconds: Int = ChessPhoneText.inviteTtlSecondsFallback

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let lines = ChessPhoneRuleLine.all(initialMs: initialMs, incrementMs: incrementMs,
                                           inviteTtlSeconds: inviteTtlSeconds)
        return VStack(spacing: 0) {
            SheetHeader(ChessPhoneText.rulesTitle,
                        subtitle: ChessPhoneText.subtitle(initialMs: initialMs, incrementMs: incrementMs),
                        onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    InsetGroup {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            GroupRow(divider: index == lines.count - 1
                                     ? .none
                                     : .inset(MobileTheme.cardPadding + 22 + MobileTheme.space3),
                                     minHeight: 56) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(MobileTheme.accent)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(MobileTheme.accentTint))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(MobileTheme.label)
                                    Text(line.detail)
                                        .font(.footnote)
                                        .foregroundStyle(MobileTheme.label2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                                Spacer(minLength: 0)
                            }
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
}
#endif
