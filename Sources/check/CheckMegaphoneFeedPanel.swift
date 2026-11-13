import AppKit
import SwiftUI
import CheckCore

// MARK: - 지난 확성기 페이지 (2026-11-11 · 최근 30일 모아 보기)
//
// 문은 확성기 작성기의 설명 줄 끝 '지난 확성기 ›' 하나다(`MegaphoneComposer`). 이 페이지는 **상점 패널 자리**에 선다 —
// `CheckMenuView` 의 상점 갈래가 `store.isMegaphoneFeedShowing` 이면 상점 대신 이것을 그린다. [뒤로]는 작성기가 열린 상점으로 간다.
// 판정·문구는 전부 코어(`MegaphoneFeedStore` · `MegaphoneFeedText`)에 있고, 이 파일은 그리기만 한다.
//
// ── 높이 ──
// 팝오버 700pt 상한을 지킨다: 목록 상자의 상한(`MegaphoneFeedLayout.listCap`)은 700 − 패널 밖 크롬(상점과 같은 216 실측) − 이 페이지의
// 고정 크롬 − 배너·목표 편집 행(`extraChromeHeight`)이다. 앱은 내용 높이를 따르다 상한에서 스크롤하고, 스냅샷은 상한에서 자른다
// (`ImageRenderer` 는 ScrollView 안쪽을 못 그린다). 신고 시트도 같은 자리 같은 상한으로 선다(`reportSheetBodyCap`).
//
// ── 줄 ──
// 얼굴(`CheckAvatarView` — 사진 → 팝오버 루트 표의 착용 캐릭터 → 이니셜) · 이름 · '내가 보낸' · 시각 · 받은 사람 수 · 본문(마크다운
// 기호를 벗긴 글 3줄, 넘치면 그 줄의 [더 보기]/[접기]) · ··· (남의 글: 신고 · 차단 — 시트를 **열기만** 한다. 보내는 문은 시트 하나다.
// 운영자: [내리기]). 줄에는 메시지 id 가 없어서 신고는 보낸 사람 신고다(`MegaphoneFeedSafetyRule`).
// SwiftUI `Menu` 를 쓰지 않는다 — ··· 는 AppKit 팝업(`MegaphoneFeedRowPopup`)이라 스냅샷이 눈멀지 않는다.

/// 페이지 치수와 세로 예산. **한 곳에서만 온다.**
enum MegaphoneFeedLayout {
    /// 칸 사이 간격(pt).
    static let spacing: CGFloat = 8
    /// 머리 줄 높이(pt, `IconButton` 27).
    static let headerHeight: CGFloat = 27
    /// 결과 한 줄(신고 접수 · 차단 실패 — caption 한 줄) 높이(pt).
    static let noticeHeight: CGFloat = 16
    /// 패널 안쪽 폭(pt) — 본문 열 316 − 카드 padding 12×2.
    static let contentWidth: CGFloat = 292
    /// 얼굴 크기 · 얼굴과 글 사이.
    static let avatarSize: CGFloat = 26
    static let avatarGap: CGFloat = 8
    /// 본문 폭(pt) = 안쪽 폭 − 얼굴 − 간격.
    static let bodyWidth: CGFloat = contentWidth - avatarSize - avatarGap
    /// 본문 글자 크기(pt). 넘침 판정(`needsMore`)이 같은 글꼴로 잰다.
    static let bodyFontSize: CGFloat = 12
    /// 넘침 판정의 여유 폭 — 배너와 같은 규약(실제보다 좁게 재서 넘치는데 [더 보기]가 안 서는 쪽을 막는다).
    static let overflowSlack: CGFloat = 4
    /// 목록 상자가 아무리 깎여도 남기는 높이(pt) — 줄 둘 남짓.
    static let minListHeight: CGFloat = 120

    /// 이 페이지의 고정 크롬(pt) = 카드 padding 24 + 머리 27 + 간격 8 + 구분선 1 + 간격 8 (+ 결과 한 줄 16 + 간격 8).
    static func fixedChrome(hasNotice: Bool) -> CGFloat {
        24 + headerHeight + spacing + 1 + spacing + (hasNotice ? noticeHeight + spacing : 0)
    }

    /// 목록 상자의 상한(pt). 상점 패널과 같은 팝오버 크롬(216 실측)과 여유(5)를 쓴다 — 같은 디스패치 자리다.
    static func listCap(extraChromeHeight: CGFloat, hasNotice: Bool) -> CGFloat {
        let budget = 700 - ShopPanelGridBudget.popoverChromeOutsidePanel - ShopPanelGridBudget.safetySlack
        return max(minListHeight, budget - fixedChrome(hasNotice: hasNotice) - extraChromeHeight)
    }

    /// 이 자리에 선 신고·차단 시트의 본문 상한(pt). 시트의 고정 크롬은 `BlockReportSheetLayout` 의 값 그대로다
    /// (카드 padding 24 + 머리 27 + 간격 8 + 구분선 1 + 간격 8 + 간격 8 + 버튼 줄 24 [+ 안내 45]).
    static func reportSheetBodyCap(extraChromeHeight: CGFloat, hasFooterNotice: Bool) -> CGFloat {
        let budget = 700 - ShopPanelGridBudget.popoverChromeOutsidePanel - ShopPanelGridBudget.safetySlack - extraChromeHeight
        let sheet = BlockReportSheetLayout.self
        let fixed = 24 + sheet.headerHeight + sheet.spacing + 1 + sheet.spacing + sheet.spacing + sheet.footerRowHeight
            + (hasFooterNotice ? sheet.footerNoticeHeight : 0)
        return max(60, budget - fixed)
    }

    static func bodyFont() -> NSFont { NSFont.systemFont(ofSize: bodyFontSize) }

    /// 이 글이 접힌 줄(`MegaphoneFeedRules.collapsedLineLimit` 줄)에 다 안 들어가는가 — 그 줄에 [더 보기]를 세울지.
    /// 화면에 실제로 그리는 글(마크다운 기호를 벗긴 것)로 잰다(배너의 `MegaphoneBannerLayout.needsMore` 와 같은 방법 · 글꼴과 폭만 다르다).
    static func needsMore(_ body: String, width: CGFloat = bodyWidth,
                          lineLimit: Int = MegaphoneFeedRules.collapsedLineLimit) -> Bool {
        let text = ChatMarkdown.plainPreview(body)
        let font = bodyFont()
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let measured = max(40, width - overflowSlack)
        let rect = (text as NSString).boundingRect(with: NSSize(width: measured, height: 100_000),
                                                   options: [.usesLineFragmentOrigin], attributes: [.font: font])
        return (rect.height / lineHeight).rounded() > CGFloat(lineLimit)
    }
}

struct CheckMegaphoneFeedPanel: View {
    @Bindable var store: WorkTimerStore
    /// 스냅샷 전용: 신고 시트의 자세히 칸을 글자로 그린다. 앱은 언제나 false.
    var rendersPlainTextEditor: Bool = false
    /// 스냅샷 전용: 넘치는 목록을 스크롤 대신 클립으로 그린다. 앱은 언제나 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    var extraChromeHeight: CGFloat = 0
    /// 스냅샷 전용: 펼친 채로 그릴 줄(앱은 빈 집합 — 펼침은 `@State` 다).
    var previewExpandedIDs: Set<String> = []
    /// 시각 표시의 '지금'(스냅샷이 고정한다). 앱은 그리는 순간의 시각이다.
    var now: () -> Date = { Date() }
    let onBack: () -> Void

    @State private var expandedIDs: Set<String> = []
    /// 본문이 실제로 받은 폭(pt). 목록 상자의 스크롤 막대(마우스를 꽂은 맥의 늘 보이는 막대 ≈15pt)가 폭을 먹으면 계산값
    /// `Layout.bodyWidth` 보다 좁다 — 넘침 판정이 이 값으로 재야 잘린 글에 [더 보기]가 선다. 재기 전(스냅샷 포함)은 계산값.
    @State private var measuredBodyWidth: CGFloat?

    private typealias Layout = MegaphoneFeedLayout

    var body: some View {
        if let sheet = store.blockReportSheet(on: .megaphoneFeed) {
            // 신고·차단 시트는 페이지 **자리에** 선다(대화 패널과 같은 규약 — 팝오버는 겹쳐 띄울 자리가 없다).
            BlockReportSheetView(
                store: store,
                sheet: sheet,
                rendersPlainTextEditor: rendersPlainTextEditor,
                clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll,
                bodyCap: Layout.reportSheetBodyCap(
                    extraChromeHeight: extraChromeHeight,
                    hasFooterNotice: sheet.kind == .report && store.reportNotice != nil
                )
            )
            .padding(12)
            .pagePanelStyle()
        } else {
            let notice = store.megaphoneFeedNotice
            VStack(alignment: .leading, spacing: Layout.spacing) {
                header
                PanelDivider()
                if let notice {
                    Text(notice.text)
                        .font(.caption)
                        .foregroundStyle(notice.isError ? CheckTheme.danger : CheckTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(height: Layout.noticeHeight, alignment: .leading)
                }
                content(cap: Layout.listCap(extraChromeHeight: extraChromeHeight, hasNotice: notice != nil))
            }
            .padding(12)
            .pagePanelStyle()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
            Text(MegaphoneFeedText.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            Text(MegaphoneFeedText.windowNote)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: Layout.headerHeight)
    }

    @ViewBuilder
    private func content(cap: CGFloat) -> some View {
        let feed = store.megaphoneFeed
        let items = store.visibleMegaphoneFeed
        if feed.isAvailable == false {
            stateLine(MegaphoneFeedText.unavailable, retry: false)
        } else if items.isEmpty {
            if feed.loadFailed && !feed.isLoading {
                stateLine(MegaphoneFeedText.failed, retry: true)
            } else if !feed.hasLoaded || feed.isLoading {
                stateLine(MegaphoneFeedText.loading, retry: false)
            } else {
                stateLine(MegaphoneFeedText.empty, retry: false)
            }
        } else {
            listBox(cap: cap) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle().fill(CheckTheme.border.opacity(0.6)).frame(height: 1)
                        }
                        row(item)
                    }
                    footer(feed)
                }
            }
        }
    }

    /// 빈 · 실패 · 불러오는 중 · 닫힘 한 줄(실패면 [다시 시도]).
    private func stateLine(_ text: String, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if retry {
                PanelRetryButton { store.megaphoneFeed.refresh() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    /// 목록 상자. 앱: 내용 높이를 따르다 상한에서 스크롤(갈래 하나 — 줄이 늘어도 뷰가 바뀌지 않는다).
    /// 스냅샷: 같은 상한에서 자른다(`ImageRenderer` 는 ScrollView 안쪽을 못 그린다).
    @ViewBuilder
    private func listBox<Content: View>(cap: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        if clipsOverflowInsteadOfScroll {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(maxHeight: cap, alignment: .top)
                .clipped()
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // ★ 수식어 순서가 뜻이다(`FeedbackListBox.keepsOneBranch` 주석): `frame(maxHeight:)` 가 안, `fixedSize` 가 밖이어야
            //   상자가 내용 높이를 따르다 상한에서 멈춘다.
            ScrollView(.vertical, showsIndicators: true) {
                content().frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: cap)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ item: MegaphoneFeedItem) -> some View {
        let expanded = expandedIDs.contains(item.id) || previewExpandedIDs.contains(item.id)
        let canExpand = Layout.needsMore(item.body, width: measuredBodyWidth ?? Layout.bodyWidth)
        let actions = MegaphoneFeedSafetyRule.actions(for: item, me: store.session?.userID, isAdmin: store.canHideMegaphonePosts)
        let hiding = store.megaphoneFeed.hidingID == item.id
        return HStack(alignment: .top, spacing: Layout.avatarGap) {
            // 사진 → 착용 캐릭터(팝오버 루트의 표) → 이니셜. 서버 줄에는 착용값이 없다.
            CheckAvatarView(name: item.senderName, userID: item.senderID, avatarURL: item.senderAvatarURL,
                            size: Layout.avatarSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    if item.isOwn {
                        Text(MegaphoneFeedText.ownBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CheckTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(CheckTheme.accent.opacity(0.14)))
                            .fixedSize()
                    }
                    Spacer(minLength: 4)
                    Text(Self.metaText(item, now: now()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                    if !actions.isEmpty {
                        moreButton(item, actions: actions)
                            .disabled(hiding)
                    }
                }
                .frame(minHeight: 16)
                Text(ChatMarkdown.plainPreview(item.body))
                    .font(.system(size: Layout.bodyFontSize))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(expanded ? nil : MegaphoneFeedRules.collapsedLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 글이 실제로 받은 폭을 잰다(줄마다 같은 값 — 바뀐 때만 적는다). [더 보기]는 글 아래라 이 폭을 바꾸지 않는다(고리 없음).
                    .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in
                        if width > 0, measuredBodyWidth != width { measuredBodyWidth = width }
                    }
                if canExpand {
                    Button {
                        if expandedIDs.contains(item.id) { expandedIDs.remove(item.id) } else { expandedIDs.insert(item.id) }
                    } label: {
                        Text(expanded ? MegaphoneFeedText.collapse : MegaphoneFeedText.expand)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CheckTheme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(hiding ? 0.45 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 머리 줄 오른쪽의 작은 글씨: 시각 · 받은 사람 수(모르면 시각만).
    static func metaText(_ item: MegaphoneFeedItem, now: Date) -> String {
        let time = MegaphoneFeedText.timeLabel(item.createdAt, now: now)
        guard let recipients = item.recipients, recipients > 0 else { return time }
        return "\(time) · \(MegaphoneFeedText.recipients(recipients))"
    }

    /// 줄의 ··· — [신고하기]·[차단하기](남의 글 · 시트를 **열기만** 한다) · [내리기](운영자).
    private func moreButton(_ item: MegaphoneFeedItem, actions: [MegaphoneFeedRowAction]) -> some View {
        let me = store.session?.userID
        let label = actions.map(\.title).joined(separator: " · ")
        return Button {
            MegaphoneFeedRowPopup.present(actions) { choice in
                switch choice {
                case .report:
                    if let target = MegaphoneFeedSafetyRule.reportTarget(for: item, me: me) {
                        store.openReport(target, surface: .megaphoneFeed)
                    }
                case .block:
                    if let target = MegaphoneFeedSafetyRule.blockTarget(for: item, me: me) {
                        store.openBlockConfirm(target, surface: .megaphoneFeed)
                    }
                case .adminHide:
                    store.hideMegaphonePost(item)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: 20, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .checkTooltip(label)
        .accessibilityLabel(label)
    }

    /// 꼬리: 더 있으면 [이전 확성기 더 보기](읽는 중이면 그 말) · 실패 한 줄.
    @ViewBuilder
    private func footer(_ feed: MegaphoneFeedStore) -> some View {
        if feed.hasMore || feed.loadMoreFailed {
            VStack(spacing: 4) {
                if feed.loadMoreFailed {
                    Text(MegaphoneFeedText.loadMoreFailed)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.danger)
                        .lineLimit(1)
                }
                if feed.hasMore {
                    Button {
                        feed.loadMore()
                    } label: {
                        Text(feed.isLoadingMore ? MegaphoneFeedText.loading : MegaphoneFeedText.loadMore)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(CheckTheme.accent.opacity(0.12)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .disabled(feed.isLoadingMore)
                }
            }
            .padding(.top, 6)
        }
    }
}

/// ··· 의 AppKit 팝업 메뉴(`BlockReportPopup` 과 같은 방법 — 항목 표만 이 페이지의 것이다). 마우스가 있는 자리에 뜬다.
@MainActor
enum MegaphoneFeedRowPopup {
    /// 메뉴 항목의 과녁. 메뉴가 떠 있는 동안 살아 있어야 하므로 다음 팝업까지 붙잡아 둔다.
    private final class Target: NSObject {
        let items: [MegaphoneFeedRowAction]
        let onSelect: (MegaphoneFeedRowAction) -> Void

        init(items: [MegaphoneFeedRowAction], onSelect: @escaping (MegaphoneFeedRowAction) -> Void) {
            self.items = items
            self.onSelect = onSelect
        }

        @objc func choose(_ sender: NSMenuItem) {
            guard items.indices.contains(sender.tag) else { return }
            onSelect(items[sender.tag])
        }
    }

    private static var retained: Target?

    static func present(_ items: [MegaphoneFeedRowAction], onSelect: @escaping (MegaphoneFeedRowAction) -> Void) {
        // 테스트 실행에서는 띄우지 않는다 — 팝업은 사용자가 고를 때까지 돌아오지 않는다(스위트가 멈춘다).
        guard !CheckPanelVisibility.isRunningTests, !items.isEmpty else { return }
        let target = Target(items: items, onSelect: onSelect)
        let popup = NSMenu()
        popup.autoenablesItems = false
        for (index, item) in items.enumerated() {
            if item == .adminHide, index > 0 { popup.addItem(.separator()) }
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

/// 작성기 설명 줄 끝의 '지난 확성기 ›'. 설명 줄과 같은 글자 크기라 작성기 높이(`MegaphoneComposer.height`)를 바꾸지 않는다.
struct MegaphoneFeedEntryLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(MegaphoneFeedText.entryLink)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.accent)
                .lineLimit(1)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(MegaphoneFeedText.title)
    }
}
