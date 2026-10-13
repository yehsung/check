import AppKit
import SwiftUI
import CheckCore

// MARK: - 확성기 작성기 (v0.3.51 — 상점 패널 안)
//
// 문은 상점 '소모품' 구획의 **📢 확성기** 카드 하나다(`CheckShopPanel.megaphoneCard`). 누르면 이 작성기가 **캐릭터 구획과 하단 구매
// 바 자리를 빌려** 선다 — 높이를 상수로 못 박아(`height`) 그 자리보다 커지지 않는다. 그래서 팝오버 700pt 예산
// (`ShopPanelGridBudget`)에 새 항목이 생기지 않는다(`V0351MegaphoneMacTests` 가 렌더로 잰다).
//
// 흐름(2단 확인 — 상점 구매와 같은 규약): 글 → [보내기] → "루비 50개로 N명에게 보낼까요?" → [보내기] → 결과 한 줄.
// 판정·문구·요청 id 는 전부 코어 `MegaphoneStore`(폰과 한 벌)에 있고, 이 파일은 그리기와 **조합 확정**만 한다:
// 두 버튼 모두 `FeedbackReplySend.commitThenSend(slot: .megaphone)` 를 지난다 — 한글 마지막 음절이 조합 중인 채로 나가면
// 루비 50개짜리 문장이 잘린 채 모두에게 간다(답장 칸 v0.3.14 · 별명 칸 v0.3.15 와 같은 결함 종).
//
// ⚠️ 입력칸은 `TextField` 다 — `ImageRenderer` 는 그 자리에 노란 상자를 그린다(렌더 테스트는 그 상자를 **입력칸 자리**로 센다).

struct MegaphoneComposer: View {
    @Bindable var store: WorkTimerStore

    /// 작성기 전체 높이(pt). **캐릭터 구획 최소 자리**(소제목 + 간격 4 + 카드 한 줄 112) + 간격 7 + 구매 바 38 보다 작아야 한다 —
    /// 그래야 어떤 예산 조합에서도 작성기를 연 패널이 격자를 연 패널보다 높아지지 않는다.
    static let height: CGFloat = 166
    /// 입력칸 높이(세 줄 자리 — 비어도 같은 자리).
    static let fieldHeight: CGFloat = 58

    var body: some View {
        let mega = store.megaphone
        VStack(alignment: .leading, spacing: 6) {
            // 제목(📢 확성기)은 바로 위 카드가 이미 말한다 — 여기서는 무엇이 일어나는지만 한 줄로.
            Text(MegaphoneText.explainer)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            field(mega)
            HStack(spacing: 6) {
                Text(mega.infoLine(now: mega.clock()))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // 서버와 같은 눈금(코드포인트) — 그래핌으로 세면 클라가 통과시킨 글을 서버가 too_long 으로 거절한다.
                Text(mega.counterText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(mega.isOverLength ? CheckTheme.danger : CheckTheme.secondaryText)
                    .fixedSize()
            }
            bar(mega)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.height, alignment: .top)
    }

    @ViewBuilder
    private func field(_ mega: MegaphoneStore) -> some View {
        TextField(MegaphoneText.placeholder,
                  text: Binding(get: { mega.draft }, set: { mega.setDraft($0) }),
                  axis: .vertical)
            .textFieldStyle(.plain)
            .font(.caption)
            .foregroundStyle(CheckTheme.primaryText)
            .tint(CheckTheme.accent)
            .lineLimit(3, reservesSpace: true)
            .disabled(mega.isSending)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.fieldHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(mega.isOverLength ? CheckTheme.danger : CheckTheme.border, lineWidth: 1))
            // 이 칸이 선 창을 조합 확정 문에 알려 준다(두 버튼의 첫 줄이 이 창의 조합을 확정한다).
            .background(FeedbackReplyWindowAnchor(slot: .megaphone).frame(width: 0, height: 0))
            // Return = 첫 단계(확인으로 가기). 바로 보내지 않는다 — 루비 50개는 되돌릴 수 없다.
            .onSubmit { FeedbackReplySend.commitThenSend(slot: .megaphone) { mega.requestSend() } }
            .accessibilityLabel("확성기 할 말")
    }

    /// 하단 바 — 상점 구매 바와 **같은 높이·모양**(`CheckShopPanel.purchaseBarHeight`). 높이를 상태에 안 맡긴다.
    @ViewBuilder
    private func bar(_ mega: MegaphoneStore) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.barTitle(mega))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                // 둘째 줄은 언제나 그린다(빈 칸이어도) — 결과·거절 한 줄이 여기 선다.
                Text(Self.barDetail(mega))
                    .font(.caption2)
                    .foregroundStyle(mega.noticeIsError ? CheckTheme.danger : CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            if mega.isConfirming {
                Button {
                    mega.cancelConfirm()
                } label: {
                    Text(MegaphoneText.cancelButton)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(mega.isSending)
                BuyButton(title: mega.isSending ? "…" : MegaphoneText.sendButton, enabled: !mega.isSending) {
                    // ★ 실제 요청은 이 한 줄뿐이다(confirmSend). 확정이 글을 바꾸면 확인 단계가 풀려 아무것도 안 나간다 —
                    //   확인한 글과 보낼 글이 다르면 다시 확인받는 것이 맞다.
                    FeedbackReplySend.commitThenSend(slot: .megaphone) { mega.confirmSend() }
                }
            } else {
                if let price = mega.price {
                    RubyBalanceChip(balance: price)
                }
                BuyButton(title: mega.isSending ? "…" : MegaphoneText.sendButton, enabled: mega.canRequestSend) {
                    FeedbackReplySend.commitThenSend(slot: .megaphone) { mega.requestSend() }
                }
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
                        .strokeBorder(mega.isConfirming ? CheckTheme.accent : CheckTheme.border,
                                      lineWidth: mega.isConfirming ? 2 : 1)
                }
        }
    }

    /// 바 첫 줄(순수). 확인 단계면 질문, 아니면 무엇을 하는 버튼인지.
    @MainActor
    static func barTitle(_ mega: MegaphoneStore) -> String {
        if mega.isConfirming, let question = mega.confirmQuestion { return question }
        return "모두에게 보내기"
    }

    /// 바 둘째 줄(순수). 결과 한 줄 > 확인 단계 경고 > 침묵(" ").
    @MainActor
    static func barDetail(_ mega: MegaphoneStore) -> String {
        if let notice = mega.notice { return notice }
        if mega.isConfirming { return "보내면 되돌릴 수 없어요" }
        return " "
    }
}
