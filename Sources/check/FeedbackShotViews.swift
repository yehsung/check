import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CheckCore

// MARK: - 제보 화면 캡처 — 조각들 (11-11)
//
// 네 자리에 선다: 보내기 탭의 붙이기 줄 · 내가 보낸 제보 행의 칩 · 받은 제보(관리자) 펼친 행의 썸네일 · 패널 위 크게 보기.
//
// ── 이 파일이 지키는 것 ──
// ① **네트워크를 부르지 않는다.** 그림은 스토어가 받아 둔 것만 그린다(`store.feedbackShotCell(for:)`). 받기는 사람이 누른
//    자리(행 펼침 · 칩 · 썸네일)에서 스토어가 한다 — 렌더 시험은 네트워크가 막혀 있고, 뷰가 받으면 그림이 비어 보인다.
// ② **높이 추정은 올림이다**(`FeedbackShotLayout`). 이 값이 `FeedbackPanelLayout` 의 스크롤 판정에 들어간다 — 낮게 잡으면
//    스냅샷 갈래에서 아래가 잘리고, 높게 잡으면 스크롤이 조금 일찍 붙을 뿐이다.
// ③ 붙이기 줄은 **입구가 보일 때만** 부른다(부르는 자리 `CheckFeedbackView.swift` 가 `store.feedbackShotAttachShown` 을 본다).
// ④ 화면을 스스로 찍는 버튼은 없다 — 고르기 · 붙여넣기 · 끌어다 놓기뿐이다.

/// 캡처 조각의 치수와 높이 추정(pt).
enum FeedbackShotLayout {
    /// 붙인 캡처 미리보기 칸(3:2). 누르면 크게 본다.
    static let draftThumbWidth: CGFloat = 45
    static let draftThumbHeight: CGFloat = 30
    /// 받은 제보 펼친 행의 썸네일 칸.
    static let inboxThumbWidth: CGFloat = 84
    static let inboxThumbHeight: CGFloat = 56

    /// 보내기 탭 붙이기 줄의 추정 높이(위 블록과의 간격 6 포함). 입구가 숨었으면 0 — 그 줄은 아예 없다.
    /// 안 붙임: 버튼 줄 22 → 28. 붙임: 미리보기 줄 30 + 2 + 경고 한 줄(9pt) 13 → 45 + 6 = 51.
    ///
    /// ★ **붙인 줄을 이 높이로 묶은 이유**: 크롬이 가장 클 때(241pt) 보내기 본문은 `minSendBodyHeight`(180)까지 깎이고,
    ///   그 접힘선 위에 종류 · 에디터 · [보내기] 줄이 남아야 한다는 것이 그 값의 약속이다 —
    ///   22 + 6 + 68 + 6 + 45 + 6 + 26 = 179 ≤ 180. 경고를 두 줄로 쌓거나 미리보기를 키우면 [보내기]가 접힘선 아래로 밀린다.
    static func sendRowHeight(shown: Bool, count: Int) -> CGFloat {
        guard shown else { return 0 }
        return (count > 0 ? 45 : 22) + FeedbackPanelLayout.sectionSpacing
    }

    /// 내가 보낸 제보 행에 칩이 더하는 높이. 칩(16)이 시각 줄(13)에 같이 서서 그 줄이 3pt 높아진다 → 4. 캡처가 없으면 0.
    static func mineRowExtra(shotCount: Int) -> CGFloat {
        shotCount > 0 ? 4 : 0
    }

    /// 받은 제보 **펼친** 행에 썸네일 판이 더하는 높이(이름표 13 + 3 + 썸네일 56 + 간격 6 = 78 → 80). 캡처가 없으면 0.
    static func inboxExpandedExtra(shotCount: Int) -> CGFloat {
        shotCount > 0 ? 80 : 0
    }
}

/// 파일 고르기 창. 화면 기록 권한 없이 사람이 직접 찍은 캡처 파일을 고른다(남은 자리만큼 여러 장).
/// 렌더 시험에서는 부르지 않는다(창을 띄운다).
@MainActor
enum FeedbackShotPicker {
    /// 고른 파일을 **전부** 돌려준다 — 남은 자리보다 많으면 스토어가 앞에서부터 자리만큼 붙이고 "N장까지" 를 말한다
    /// (여기서 조용히 자르면 사람은 다 붙은 줄 안다).
    static func chooseImageFiles(limit: Int) -> [URL] {
        guard limit > 0 else { return [] }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FeedbackShotImage.pickableTypes
        panel.allowsMultipleSelection = limit > 1
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "붙이기"
        panel.message = FeedbackShotText.pickerMessage(remaining: limit)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}

// MARK: - 보내기 탭: 붙이기 줄

/// 에디터 아래 한 줄. 안 붙였으면 [이미지 고르기] [붙여넣기], 붙였으면 미리보기들(각자 [빼기]) + 버튼 + 경고 한 줄.
/// 줄 전체가 끌어다 놓기 판이다(파일 · 그림).
struct FeedbackShotAttachRow: View {
    @Bindable var store: WorkTimerStore
    /// 끌어다 놓기 판을 다는가. **스냅샷만 false** 다 — `ImageRenderer` 는 놓기 판(AppKit 끌기 대상)을 노란 상자로 그려
    /// 그 줄을 통째로 가린다(실측). 앱은 언제나 true 다(호출부가 `rendersPlainTextEditor` 와 같은 스위치를 넘긴다).
    var acceptsDrops: Bool = true
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if store.feedbackShots.isEmpty {
                idle
            } else {
                attached
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(CheckTheme.accent.opacity(dropTargeted ? 0.8 : 0), lineWidth: 1.5)
                .padding(-2)
        )
        .modifier(FeedbackShotDropTarget(enabled: acceptsDrops, targeted: $dropTargeted) { providers in
            store.attachFeedbackShots(fromDropped: providers)
        })
    }

    private var attached: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ForEach(Array(store.feedbackShots.enumerated()), id: \.element.id) { index, shot in
                    FeedbackShotDraftThumb(
                        image: shot.preview,
                        removeEnabled: !store.isSendingFeedback,
                        onOpen: { store.openFeedbackShotDraftViewer(index: index) },
                        onRemove: { store.removeFeedbackShot(id: shot.id) }
                    )
                }
                Spacer(minLength: 4)
                if store.feedbackShotPreparing {
                    Text(FeedbackShotText.preparing)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                } else if store.feedbackShots.count < FeedbackShotRules.maxDraft {
                    buttons
                } else {
                    Text(FeedbackShotText.attachedCount(store.feedbackShots.count))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize()
                }
            }
            .frame(height: FeedbackShotLayout.draftThumbHeight)
            // 붙인 동안 **늘** 보인다 — 찍힌 화면에 남의 이름·대화가 있을 수 있고, 누가 보는지를 함께 말한다.
            // 9pt 한 줄 — 두 줄이 되면 [보내기] 줄이 접힘선 아래로 밀린다(`FeedbackShotLayout.sendRowHeight`).
            Text(FeedbackShotText.privacyWarning)
                .font(.system(size: 9))
                .foregroundStyle(CheckTheme.pending)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var idle: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 10))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(store.feedbackShotPreparing ? FeedbackShotText.preparing : FeedbackShotText.rowTitle)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 4) {
            FeedbackShotSmallButton(
                label: FeedbackShotText.pickAction,
                enabled: store.canAddFeedbackShot,
                action: pickTapped
            )
            FeedbackShotSmallButton(
                label: FeedbackShotText.pasteAction,
                enabled: store.canAddFeedbackShot,
                action: { store.attachFeedbackShotFromPasteboard() }
            )
        }
    }

    /// [이미지 고르기]. 고르기 창이 팝오버를 닫아도 캡처는 스토어에 붙는다(초안과 같은 자리).
    @MainActor
    func pickTapped() {
        let urls = FeedbackShotPicker.chooseImageFiles(limit: FeedbackShotRules.maxDraft - store.feedbackShots.count)
        store.attachFeedbackShots(fromFiles: urls)
    }
}

/// 끌어다 놓기 판(켜졌을 때만). 파일 URL · 그림 바이트를 받는다.
struct FeedbackShotDropTarget: ViewModifier {
    let enabled: Bool
    @Binding var targeted: Bool
    let perform: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: FeedbackShotImage.dropTypes, isTargeted: $targeted, perform: perform)
        } else {
            content
        }
    }
}

/// 붙인 캡처 한 장 — 누르면 크게 보고, 귀퉁이 ⓧ 가 [빼기]다.
struct FeedbackShotDraftThumb: View {
    let image: NSImage
    let removeEnabled: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: FeedbackShotLayout.draftThumbWidth, height: FeedbackShotLayout.draftThumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(!removeEnabled)
            .checkTooltip(FeedbackShotText.removeAction)
            .accessibilityLabel(FeedbackShotText.removeAction)
            .offset(x: 3, y: -3)
        }
    }
}

/// 작은 테두리 버튼(붙이기 줄 · 크게 보기가 쓴다).
struct FeedbackShotSmallButton: View {
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - 내가 보낸 제보: 칩

/// "캡처 N장" 칩. 첫 장을 받아 두었으면 작은 썸네일을 함께 그린다. 누르면 크게 본다(받기는 스토어가).
struct FeedbackShotChip: View {
    let count: Int
    let firstCell: FeedbackShotCell?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if case .image(let image)? = firstCell {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(FeedbackShotText.chip(count))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(CheckTheme.accent)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 받은 제보(관리자): 접힌 행의 표 · 펼친 행의 썸네일

/// 접힌 행 메타 줄의 작은 "캡처 N장" 표 — 어느 제보에 캡처가 있는지 펼치기 전에 보인다.
struct FeedbackShotBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "photo")
                .font(.system(size: 8, weight: .semibold))
            Text(FeedbackShotText.chip(count))
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(CheckTheme.secondaryText)
        .fixedSize()
    }
}

/// 펼친 행의 캡처 판(썸네일 최대 3). 그림은 받아 둔 것만 그리고, 누르면 그 장을 크게 본다.
struct FeedbackShotStrip: View {
    let cells: [FeedbackShotCell]
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(FeedbackShotText.stripTitle(cells.count))
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.secondaryText)
            HStack(spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    Button(action: { onOpen(index) }) {
                        FeedbackShotCellView(cell: cell, compact: true)
                            .frame(width: FeedbackShotLayout.inboxThumbWidth, height: FeedbackShotLayout.inboxThumbHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 칸 하나(썸네일 · 크게 보기 공용). 받아 둔 그림 · 받는 중 · 실패 · 아직 안 받음.
struct FeedbackShotCellView: View {
    let cell: FeedbackShotCell
    /// 썸네일이면 채워 자르고, 크게 보기면 통째로 맞춘다.
    var compact: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(CheckTheme.trackFill)
            switch cell {
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: compact ? .fill : .fit)
            case .loading:
                Text(FeedbackShotText.loading)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
            case .failed(let failure):
                Text(failure.text)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.pending)
                    .multilineTextAlignment(.center)
                    .padding(4)
            case .idle:
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        }
    }
}

// MARK: - 크게 보기(패널 위 덮개)

/// 패널 전체를 덮는 크게 보기. 받아 둔 그림만 그린다(받기는 열 때 스토어가 했다). 앞뒤 넘기기 · [닫기].
struct FeedbackShotViewerOverlay: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        if let viewer = store.feedbackShotViewer, let cell = store.feedbackShotViewerCell {
            let count = store.feedbackShotViewerCount
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(FeedbackShotText.viewerTitle(viewer.index, count))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if count > 1 {
                        FeedbackShotSmallButton(label: FeedbackShotText.viewerPrevious, enabled: true, action: { store.stepFeedbackShotViewer(by: -1) })
                        FeedbackShotSmallButton(label: FeedbackShotText.viewerNext, enabled: true, action: { store.stepFeedbackShotViewer(by: 1) })
                    }
                    FeedbackShotSmallButton(label: FeedbackShotText.viewerClose, enabled: true, action: { store.closeFeedbackShotViewer() })
                }
                FeedbackShotCellView(cell: cell)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(FeedbackShotText.privacyWarning)
                    .font(.system(size: 9))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                    .fill(CheckTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                    .stroke(CheckTheme.border, lineWidth: 1)
            )
        }
    }
}
