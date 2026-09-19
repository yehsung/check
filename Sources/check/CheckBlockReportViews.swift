import AppKit
import SwiftUI
import CheckCore

// MARK: - 차단 · 신고 화면 (v0.3.34 — 맥, 2026-09-20)
//
// 폰의 두 시트(차단 확인 · 신고)와 [차단한 사람] 목록을 맥의 부품으로 옮긴 것이다. **문구·사유·확인 절차는 폰과 한 벌**이다 —
// 전부 코어 `BlockReportText`·`BlockReportRules` 를 읽는다(맥 길 안내는 `.mac`). 동작은 `WorkTimerStoreBlocks.swift`.
//
// ── 새 스타일을 만들지 않는다 ──
// 시트는 이 앱이 이미 쓰는 부품으로만 짓는다: 패널 틀(`panelStyle`) · 머리 버튼(`IconButton`) · 구분선(`PanelDivider`) ·
// 칩(`FeedbackSegmentChip`) · 주 버튼(`FeedbackPrimaryButton`) · 본문 칸(`FeedbackBodyEditor` — 진짜 `CheckTextEditor`) ·
// 스위치(`CheckSettingsToggleStyle`) · 스크롤 상자(`FeedbackListBox`). 색은 `CheckTheme` 토큰뿐이다.
// 시스템 알림창(`.alert`)·`.sheet`·SwiftUI `Menu`·`TextEditor` 를 쓰지 않는다: 알림창 재질은 뒤 화면 색을 빨아들이고,
// 팝오버 위 `.sheet` 는 팝오버를 가리고, `Menu`·`TextEditor` 는 `ImageRenderer` 가 노란 상자로 그려 스냅샷이 눈이 먼다.
//
// ── 시트가 서는 자리 ──
//  · 팝오버: 대화 패널 **자리에** 선다(`CheckMessageView`). 팝오버는 콘텐츠 높이가 곧 창 높이라 겹쳐 띄울 자리가 없고,
//    높이 상한(700pt)은 대화 패널의 예산(`MessagePanelLayout`)을 그대로 빌린다 — 본문이 넘치면 스크롤로 밀린다.
//  · 오목 창: 판돈 창과 같은 **가운데 덮개**다(`GomokuPanel` — 바깥을 누르거나 Esc 면 닫힌다).
//
// ★ 신고 본문은 사람이 쓴 문장이다 — 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라.

// MARK: - ··· 버튼

/// 대화 머리 · 오목 채팅 머리의 ··· . 누르면 [신고하기] · [차단하기] 메뉴가 뜬다 — **시트를 열 뿐**이고 왕복은 없다.
///
/// 메뉴는 AppKit 팝업(`BlockReportPopup`)이다. SwiftUI `Menu` 가 아닌 이유: `ImageRenderer` 가 그 자리를 노란 상자로 그려
/// 스냅샷이 눈이 먼다(이 저장소가 겪은 눈가리개). 팝업은 누를 때만 뜨므로 그리는 것은 버튼 하나다.
/// 항목 표는 `BlockReportMenuItem` 한 곳이다(두 입구가 같은 표를 읽는다).
struct BlockReportMoreButton: View {
    let onSelect: (BlockReportMenuItem) -> Void

    var body: some View {
        IconButton(icon: "ellipsis", help: BlockReportText.menuAccessibilityLabel) {
            BlockReportPopup.present(BlockReportMenuItem.allCases, onSelect: onSelect)
        }
        .accessibilityLabel(BlockReportText.menuAccessibilityLabel)
    }
}

/// ··· 의 AppKit 팝업 메뉴. 마우스가 있는 자리에 뜬다(화면 좌표 — 뷰를 몰라도 된다).
@MainActor
enum BlockReportPopup {
    /// 메뉴 항목의 과녁. 메뉴가 떠 있는 동안 살아 있어야 하므로 다음 팝업까지 붙잡아 둔다.
    private final class Target: NSObject {
        let items: [BlockReportMenuItem]
        let onSelect: (BlockReportMenuItem) -> Void

        init(items: [BlockReportMenuItem], onSelect: @escaping (BlockReportMenuItem) -> Void) {
            self.items = items
            self.onSelect = onSelect
        }

        @objc func choose(_ sender: NSMenuItem) {
            guard items.indices.contains(sender.tag) else { return }
            onSelect(items[sender.tag])
        }
    }

    private static var retained: Target?

    static func present(_ items: [BlockReportMenuItem], onSelect: @escaping (BlockReportMenuItem) -> Void) {
        // 테스트 실행에서는 띄우지 않는다 — 팝업은 사용자가 고를 때까지 돌아오지 않는다(스위트가 멈춘다).
        guard !CheckPanelVisibility.isRunningTests else { return }
        let target = Target(items: items, onSelect: onSelect)
        let popup = NSMenu()
        popup.autoenablesItems = false
        for (index, item) in items.enumerated() {
            let entry = NSMenuItem(title: item.title, action: #selector(Target.choose(_:)), keyEquivalent: "")
            entry.target = target
            entry.tag = index
            entry.image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil)
            popup.addItem(entry)
        }
        retained = target
        popup.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - 치수

/// 시트의 치수와 세로 예산. **한 곳에서만 온다**(대화 패널 `MessagePanelLayout` 과 같은 규약).
enum BlockReportSheetLayout {
    /// 칸 사이 간격(pt).
    static let spacing: CGFloat = 8
    /// 자유 입력 칸 높이(pt) — 메시지 입력칸과 같은 3줄(`MessagePanelLayout.editorHeight`).
    static let editorHeight: CGFloat = MessagePanelLayout.editorHeight
    /// 아래 버튼 줄 높이(pt, `FeedbackPrimaryButton` 과 같은 값).
    static let footerRowHeight: CGFloat = 24
    /// 아래 안내 한 줄(최대 세 줄 · caption2)이 먹는 높이(pt, 간격 포함).
    static let footerNoticeHeight: CGFloat = 45
    /// 시트 머리 줄 높이(pt, `IconButton` 27).
    static let headerHeight: CGFloat = 27

    /// 팝오버 시트의 **본문 상한**(pt). 시트 패널 전체가 대화 패널이 쓸 수 있는 가장 큰 높이
    /// (고정 크롬 178 + 대화 높이 — `MessagePanelLayout` 의 두 부등식이 이미 700pt 안을 보증한다)를 넘지 않게,
    /// 거기서 시트의 고정 크롬(카드 padding 24 + 머리 27 + 간격 8 + 구분선 1 + 간격 8 + 간격 8 + 버튼 줄 24 [+ 안내 45])을 뺀다.
    /// 배너가 가장 클 때(241pt)에도 성립한다 — 본문이 이보다 크면 스크롤로 **밀릴 뿐** 아무것도 사라지지 않는다.
    static func popoverBodyCap(extraChromeHeight: CGFloat, hasFooterNotice: Bool) -> CGFloat {
        let panel = messagePanelFixedChrome + MessagePanelLayout.conversationHeight(extraChromeHeight: extraChromeHeight)
        let fixed = 24 + headerHeight + spacing + 1 + spacing + spacing + footerRowHeight
            + (hasFooterNotice ? footerNoticeHeight : 0)
        return max(60, panel - fixed)
    }

    /// 대화 패널의 고정 크롬(pt) — `MessagePanelLayout.conversationHeight` 주석의 실측 178.
    static let messagePanelFixedChrome: CGFloat = 178

    /// caption 글자 한 줄에 드는 글자 수(추정, 292pt 기준). **조금 작게 잡는다** — 과소평가하면 본문이 잘리고 과대평가하면 스크롤이
    /// 조금 일찍 붙을 뿐이다(잘림은 결함이고 이른 스크롤은 아니다 — 제보 패널 `FeedbackPanelLayout` 과 같은 규약).
    /// 2026-09-20 스냅샷 실측: 292pt 에서 caption 한글 29자가 한 줄에 들었다. 20 으로 잡았을 때는 한 줄짜리 머리글을 두 줄로 세어
    /// 본문이 상한에 걸려 아래가 27pt 비었다 — 24 는 전각 글자만 이어진 최악의 줄(≈ 11pt × 24 = 264pt)도 넘기지 않는 값이다.
    static let charactersPerLine = 24

    static func lines(_ text: String) -> Int {
        max(1, Int((Double(text.count) / Double(charactersPerLine)).rounded(.up)))
    }

    /// 차단 확인 본문의 **추정** 자연 높이(pt).
    static func confirmBodyHeight(peerName: String, items: [String]) -> CGFloat {
        let title = CGFloat(lines(BlockReportText.blockConfirmTitle(peerName))) * 15
        let box = items.reduce(CGFloat(16)) { $0 + CGFloat(lines($1)) * 15 } + CGFloat(max(0, items.count - 1)) * 5
        let notes = CGFloat(lines(BlockReportText.blockConfirmScopeNote) + lines(BlockReportText.blockConfirmUndoNote(.mac))) * 13
        return title + box + notes + spacing * 3
    }

    /// 신고 본문의 **추정** 자연 높이(pt).
    static func reportBodyHeight(target: BlockReportTarget, detail: String) -> CGFloat {
        var total: CGFloat = CGFloat(lines(BlockReportText.reportLede(target.peerName))) * 15
        if let body = target.messageBody {
            total += CGFloat(min(3, lines(body))) * 15 + 16 + spacing
        }
        // 사유 머리 13 + 칩 줄 22 + 자세히 머리 13 + 칸 + 스위치 줄 30 + 약속 13, 그 사이 간격 다섯 번.
        total += 13 + 22 + 13 + editorHeight + 30 + 13 + spacing * 6
        if BlockReportRules.detailCounterText(detail) != nil { total += 13 + spacing }
        return total
    }
}

// MARK: - 시트

/// 차단 확인 · 신고 시트(두 자리가 같은 뷰를 쓴다 — 팝오버 대화 자리 · 오목 창 덮개).
///
/// **차단을 부르는 곳은 이 시트의 [차단하기] 하나다**(`store.confirmBlockFromSheet()` — 소스 계약 테스트가 센다).
/// 신고를 보내는 곳도 이 시트의 [신고 보내기] 하나이고, 그 문은 **조합 확정을 먼저** 지난다(`submitTapped`).
struct BlockReportSheetView: View {
    @Bindable var store: WorkTimerStore
    let sheet: BlockReportSheet
    /// 스냅샷 전용: 자유 입력 칸을 AppKit 뷰 대신 글자로 그린다. **앱은 언제나 false**.
    var rendersPlainTextEditor: Bool = false
    /// 스냅샷 전용: 넘치는 본문을 스크롤 대신 클립으로 그린다. **앱은 언제나 false**.
    var clipsInsteadOfScrolling: Bool = false
    /// 본문 상한(pt). nil 이면 자연 높이(오목 창 — 세로가 넉넉하다).
    var bodyCap: CGFloat? = nil
    /// 자세히 칸의 입력칸 재사용 자리를 만드는 **이 시트를 부른 소스 위치**(v0.3.34 수리). 팝오버 대화 자리와 오목 창 덮개가
    /// 각자 제 자리를 갖는다 — 오목 창은 닫아도 `orderOut` 뿐이라 그 덮개의 칸이 살아 남고, 자리를 나눠 쓰면 나중에 선 칸이
    /// 새로 만들어져 한글 조합이 죽는다(`FeedbackBodyEditor.editorFile` 주석 · `V0334BlockReportLeaveTests`).
    /// ★ 기본값은 **맨 매직 리터럴**이어야 부른 자리에서 펼쳐진다(`CheckEditorSlot` 주석).
    private let editorFile: String
    private let editorLine: Int

    init(
        store: WorkTimerStore,
        sheet: BlockReportSheet,
        rendersPlainTextEditor: Bool = false,
        clipsInsteadOfScrolling: Bool = false,
        bodyCap: CGFloat? = nil,
        file: String = #fileID,
        line: Int = #line
    ) {
        self.store = store
        self.sheet = sheet
        self.rendersPlainTextEditor = rendersPlainTextEditor
        self.clipsInsteadOfScrolling = clipsInsteadOfScrolling
        self.bodyCap = bodyCap
        self.editorFile = file
        self.editorLine = line
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Layout = BlockReportSheetLayout

    private var footerNotice: String? {
        sheet.kind == .report ? store.reportNotice : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            header
            PanelDivider()
            FeedbackListBox(
                contentHeight: estimatedBodyHeight,
                capHeight: bodyCap ?? .greatestFiniteMagnitude,
                clipsInsteadOfScrolling: clipsInsteadOfScrolling,
                // 팝오버 신고 시트는 **갈래 하나**(v0.3.34 수리): 쓰는 도중 카운터(180자)·안내 줄(보내기 실패)이 서고 지며 상자가
                // 그대로 ↔ 스크롤로 갈리면 자세히 칸이 새 NSTextView 가 되어 포커스와 한글 조합을 잃는다(`keepsOneBranch` 주석).
                // 오목 덮개는 상한이 없어(자연 높이) 갈래가 바뀌지 않고, 차단 확인은 입력칸이 없어 잃을 것이 없다 — 둘은 예전 그대로다.
                keepsOneBranch: bodyCap != nil && sheet.kind == .report
            ) {
                switch sheet.kind {
                case .blockConfirm: confirmBody
                case .report: reportBody
                }
            }
            footer
        }
    }

    private var estimatedBodyHeight: CGFloat {
        switch sheet.kind {
        case .blockConfirm:
            return Layout.confirmBodyHeight(peerName: sheet.target.peerName, items: confirmItems)
        case .report:
            return Layout.reportBodyHeight(target: sheet.target, detail: store.reportDetailDraft)
        }
    }

    private var confirmItems: [String] { BlockReportText.blockConfirmItems(WorkTimerStore.blockReportPlatform) }

    // MARK: 머리

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(icon: "xmark", help: BlockReportText.blockCancel, enabled: !store.isSendingReport) {
                store.closeBlockReportSheet()
            }
            Image(systemName: sheet.kind == .blockConfirm ? "nosign" : "exclamationmark.bubble")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CheckTheme.danger)
            Text(sheet.kind == .blockConfirm ? BlockReportText.blockAction : BlockReportText.reportTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
        }
        .frame(height: Layout.headerHeight)
    }

    // MARK: 차단 확인

    /// 무엇이 막히는지 **세 줄** → 무엇이 안 막히는지 한 줄 → 되돌릴 수 있다는 한 줄(폰 시트와 같은 차례).
    private var confirmBody: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(BlockReportText.blockConfirmTitle(sheet.target.peerName))
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(confirmItems, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "nosign")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CheckTheme.danger)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(CheckTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("차단하면: \(confirmItems.joined(separator: ", "))")
            Text(BlockReportText.blockConfirmScopeNote)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BlockReportText.blockConfirmUndoNote(WorkTimerStore.blockReportPlatform))
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 신고

    /// 사유 넷(필수) · 자세히 200자(선택) · [신고하면서 차단](기본 켬) · "24시간 안에 확인합니다".
    private var reportBody: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(sheet.target.messageID == nil
                 ? BlockReportText.reportLede(sheet.target.peerName)
                 : BlockReportText.reportMessageLede)
                .font(.caption)
                .foregroundStyle(CheckTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let quoted = sheet.target.messageBody {
                // 신고하는 메시지 한 장(읽기 전용 · 세 줄까지) — 무엇을 신고하는지 눈으로 확인하는 자리다.
                Text(quoted)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            sectionLabel(BlockReportText.reportReasonHeader)
            HStack(spacing: 6) {
                ForEach(ContentReportReason.allCases) { reason in
                    FeedbackSegmentChip(
                        label: reason.label,
                        tint: CheckTheme.accent,
                        isSelected: store.reportReason == reason
                    ) {
                        store.selectReportReason(reason)
                    }
                    .accessibilityAddTraits(store.reportReason == reason ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
            .disabled(store.isSendingReport)
            sectionLabel(BlockReportText.reportDetailHeader)
            FeedbackBodyEditor(
                text: $store.reportDetailDraft,
                height: Layout.editorHeight,
                rendersPlainText: rendersPlainTextEditor,
                placeholder: BlockReportText.reportDetailPlaceholder,
                // 제보 패널과 같은 부품이지만 **같은 자리가 아니다** — 이 시트를 부른 화면의 자리를 넘긴다(위 `editorFile`).
                file: editorFile, line: editorLine
            )
            .overlay(
                // 넘치면 테두리까지 빨갛게 — 카운터 숫자만으로는 못 보고 지나친다(메시지 입력칸과 같은 규약).
                RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                    .stroke(CheckTheme.danger, lineWidth: 1)
                    .opacity(BlockReportRules.isDetailOverflowing(store.reportDetailDraft) ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .disabled(store.isSendingReport)
            if let counter = BlockReportRules.detailCounterText(store.reportDetailDraft) {
                Text(counter)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(
                        BlockReportRules.isDetailOverflowing(store.reportDetailDraft) ? CheckTheme.danger : CheckTheme.secondaryText
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Toggle(isOn: $store.reportAlsoBlock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BlockReportText.reportAlsoBlock)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                    Text(BlockReportText.reportAlsoBlockDetail)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(CheckSettingsToggleStyle(reduceMotion: reduceMotion))
            .disabled(store.isSendingReport)
            Text(BlockReportText.reviewPromise)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CheckTheme.secondaryText)
    }

    // MARK: 아래 — 안내 · [취소] · 주 버튼

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let footerNotice {
                Text(footerNotice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.pending)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                FeedbackSegmentChip(label: BlockReportText.blockCancel, tint: CheckTheme.accent, isSelected: false) {
                    store.closeBlockReportSheet()
                }
                .disabled(store.isSendingReport)
                switch sheet.kind {
                case .blockConfirm:
                    FeedbackPrimaryButton(label: BlockReportText.blockConfirm, enabled: true, tint: CheckTheme.danger) {
                        store.confirmBlockFromSheet()
                    }
                    .checkTooltip(BlockReportText.blockConfirmUndoNote(WorkTimerStore.blockReportPlatform))
                case .report:
                    FeedbackPrimaryButton(
                        label: store.isSendingReport ? BlockReportText.reportSending : BlockReportText.reportSubmit,
                        enabled: store.canSubmitReportNow,
                        action: submitTapped
                    )
                    .checkTooltip(store.reportReason == nil ? BlockReportText.reportReasonRequired : BlockReportText.reviewPromise)
                }
            }
            .frame(height: Layout.footerRowHeight)
        }
    }

    /// [신고 보내기]의 동작. **조합 확정이 먼저다**(`CheckEditorSend.commitThenSend` — 메시지·제보 칸과 같은 문):
    /// 한글 마지막 음절이 조합 중인 채로 누르면 그 음절이 초안에 아직 없다. 확정은 동기라 스토어가 곧바로 화면의 글 전체를 읽는다.
    ///
    /// `private` 이 아닌 이유(제보 `sendTapped` 와 같다): SwiftUI `Button` 은 헤드리스 테스트에서 누를 수 없어서,
    /// 테스트가 **올린 화면의 이 값**을 태워 서버로 나가는 본문을 잰다.
    @MainActor
    func submitTapped() {
        CheckEditorSend.commitThenSend { store.sendReportFromSheet() }
    }
}

// MARK: - 설정 → 차단한 사람

/// 설정 '내 정보'의 [차단한 사람] 행. 누르면 설정 본문 자리에 목록이 선다(`CheckBlockedPeopleSettingsPage`).
/// 목록을 이 창 안에 펼치지 않는 이유: 설정 창은 높이 계약(`CheckSettingsWindowController.defaultContentSize`)을 가진 창이라
/// 사람 수만큼 자라는 목록을 품으면 맨 아래 항목이 잘린다.
struct BlockedPeopleSettingsEntryRow: View {
    let store: WorkTimerStore

    var body: some View {
        Button {
            store.openBlockedPeopleSettings()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(BlockReportText.blockedListTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                    Text(BlockReportText.blockedListMenuDetail)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(BlockReportText.blockedListTitle)
        .accessibilityHint(BlockReportText.blockedListMenuDetail)
    }
}

/// 차단 목록 화면이 그릴 네 상태(순수 — 결정적 검증 지점). **빈 목록과 로드 전·실패를 가른다**(제보 목록의 3플래그 규약) —
/// 못 받은 목록을 "차단한 사람이 없어요"라고 말하면 그건 거짓말이다.
enum BlockedPeoplePageState: Equatable {
    case loading
    case failed
    case empty
    case list

    static func of(loaded: Bool, loading: Bool, failed: Bool, count: Int) -> BlockedPeoplePageState {
        if count > 0 { return .list }
        if failed, !loaded { return .failed }
        if !loaded { return .loading }
        return .empty
    }
}

/// 설정 → [차단한 사람]. 목록 + [차단 해제](행 안에서 한 번 더 확인). 0명이면 빈 상태 문구.
/// 서버가 아직 차단 RPC 를 모르면(앱이 db push 보다 먼저 나간 창) "고장"이 아니라 **"아직"**이라고 말한다.
struct CheckBlockedPeopleSettingsPage: View {
    let store: WorkTimerStore
    /// 이 수를 넘으면 목록이 스크롤한다(행 44pt — 설정 창 높이 안에 머문다).
    static let maxUnscrolledRows = 8
    static let rowHeight: CGFloat = 44

    private var state: BlockedPeoplePageState {
        BlockedPeoplePageState.of(
            loaded: store.blocksLoaded, loading: store.blocksLoading,
            failed: store.blocksFailed, count: store.blockedPeople.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "설정으로") { store.closeBlockedPeopleSettings() }
                Text(BlockReportText.blockedListTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                Spacer(minLength: 6)
            }
            Text(BlockReportText.blockedListLede(WorkTimerStore.blockReportPlatform))
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let notice = store.blockedListNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.blocksServerNotReady {
                Text(BlockReportText.serverNotReady)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.pending)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelStyle()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            Text("불러오는 중…")
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
        case .failed:
            VStack(spacing: 6) {
                Text(BlockReportText.blockedListFailed)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                PanelRetryButton { store.loadBlocks(force: true) }
            }
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
        case .empty:
            VStack(spacing: 5) {
                Image(systemName: "nosign")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(CheckTheme.secondaryText.opacity(0.55))
                Text(BlockReportText.blockedEmptyTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(BlockReportText.blockedEmptyMessage(WorkTimerStore.blockReportPlatform))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        case .list:
            let people = store.blockedPeople
            if people.count > Self.maxUnscrolledRows {
                ScrollView(.vertical, showsIndicators: true) { rows(people) }
                    .frame(height: CGFloat(Self.maxUnscrolledRows) * Self.rowHeight)
            } else {
                rows(people)
            }
        }
    }

    private func rows(_ people: [BlockedUser]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 { PanelDivider() }
                BlockedPersonRow(store: store, person: person)
            }
        }
    }
}

/// 차단 목록 한 줄: 아바타 · 이름 · 차단한 시각 · [차단 해제]. 해제도 **확인을 지난다** — 목록에서 손이 스쳐 풀리면
/// 사용자는 그 사실을 영영 모른다(폰 목록과 같은 규칙). 확인은 같은 줄 안에서 뜬다(오목 기권 확인과 같은 맥 관례).
struct BlockedPersonRow: View {
    let store: WorkTimerStore
    let person: BlockedUser
    @State private var confirming = false

    var body: some View {
        let isUnblocking = store.unblockingUserIDs.contains(person.userID)
        HStack(spacing: 10) {
            CheckAvatarView(name: person.name, avatarURL: person.avatarURL, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                if confirming {
                    Text(BlockReportText.unblockConfirmMessage)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.pending)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let at = person.blockedAt {
                    // 시각을 모르면 이 줄을 그리지 않는다(지어내지 않는다).
                    Text(BlockReportText.blockedAtLine(relative: FeedbackText.ageText(at, now: store.clock())))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
            Spacer(minLength: 6)
            if confirming {
                FeedbackSegmentChip(label: BlockReportText.blockCancel, tint: CheckTheme.accent, isSelected: false) {
                    confirming = false
                }
                FeedbackPrimaryButton(label: BlockReportText.unblockConfirm, enabled: !isUnblocking) {
                    confirming = false
                    store.unblock(person.userID)
                }
            } else {
                FeedbackPrimaryButton(
                    label: isUnblocking ? "푸는 중…" : BlockReportText.unblockAction,
                    enabled: !isUnblocking
                ) {
                    confirming = true
                }
                .checkTooltip(BlockReportText.unblockConfirmTitle(person.name))
            }
        }
        .frame(minHeight: CheckBlockedPeopleSettingsPage.rowHeight)
    }
}
