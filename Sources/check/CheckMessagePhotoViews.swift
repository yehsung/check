import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CheckCore

// MARK: - 1:1 메시지 사진의 화면 조각 (2026-11-11 — 맥 0.3.86)
//
// 로직은 `WorkTimerStoreMessagePhotos.swift`, 전선은 코어 `MessagePhotoWire.swift` 다. 이 파일은 그림만 그린다.
//
// ── 이 파일이 지키는 것 ──
//  ① **사진 말풍선은 따로 든 구조체다**(`MessagePhotoBubble`). `MessageBubbleRow` 안에 메뉴를 하나 더 두면 그 행의 단일 우클릭 메뉴
//     계약(V0334 — `.contextMenu {` 정확히 하나)이 깨진다. 행은 사진을 **먼저** 고르고(설명이 있으면 그 아래 글 말풍선), 여기는 사진 한 장만 그린다.
//  ② 크기는 코어 규칙 하나다(`MessagePhotoLayout.bubbleSize`) — 틀 높이 추정이 같은 함수를 부른다(빈 회색 판 · 갇힌 사진 방지).
//  ③ 덮개(미리 보기 · 크게 보기 · 준비 중)는 **대화 자리**를 덮는다 — 이모티콘 그리드와 같은 규약이다(패널 높이를 1pt 도 늘리지 않는다 ·
//     밑의 대화는 보이스오버에서 내려가고 덮개는 `.isModal`).
//  ④ 사진을 얻는 길은 사람이 고른 파일 · 붙여넣기(⌘V)뿐이다. **화면을 찍는 코드는 없다**(처리방침 — 화면 기록 권한을 안 묻는다).
//  ⑤ 그림은 `CGImage` 로 든다(ImageRenderer 스냅샷이 그린다). 사진 · 경로는 로그로 흘리지 않는다.

// MARK: - 열기 · 저장 창

/// 사진 고르기 · 저장 창. **사람이 고른 파일만** 다룬다(④).
@MainActor
enum MessagePhotoPanels {
    /// 고를 수 있는 형식(계약: png · jpeg · heic · tiff · gif · webp).
    static let allowedTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .webP]

    /// 열기 창(팝오버에서 띄워도 된다 — 아바타 고르기가 같은 길이다). 취소면 nil.
    static func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = MessagePhotoText.pickerPrompt
        panel.message = MessagePhotoText.pickerMessage
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// 저장 창. 취소는 실패가 아니다(true). 쓰기에 실패했을 때만 false.
    static func save(_ data: Data) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = MessagePhotoText.saveDefaultName
        guard panel.runModal() == .OK, let url = panel.url else { return true }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 작성기의 [사진] 버튼

/// 입력칸 옆 [사진] 버튼(이모티콘 버튼과 같은 26pt · 같은 줄 — 작성기 높이가 그대로다). 못 보낼 때는 같은 모양으로 흐려진다.
struct MessagePhotoButton: View {
    let enabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "photo")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(MessagePhotoText.buttonLabel)
        .checkTooltip(help)
    }
}

// MARK: - 사진 한 장(받기 상태별)

/// 사진 한 장을 그 크기로 그린다 — 그림이 있으면 그림, 받는 중이면 자리표, 못 받았으면 "사진을 볼 수 없어요" 자리표.
/// 보이면 그때 받는다(`context.request` — 경로마다 하나 · 실패 기억은 캐시가 한다).
struct MessagePhotoSurface: View {
    /// 저장소 경로(그림 캐시의 열쇠).
    let path: String
    let context: MessagePhotoBubbleContext?
    let size: CGSize
    /// 채워 자른다(말풍선 · 썸네일) / 비율대로 맞춘다(크게 보기).
    var fills: Bool = true
    var corner: CGFloat = MessagePhotoLayout.corner

    var body: some View {
        ZStack {
            if let image = context?.image(for: path) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                placeholder(failed: context?.state(for: path) == .failed)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: path) { context?.request(path) }
    }

    private func placeholder(failed: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.08))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
            VStack(spacing: 3) {
                Image(systemName: failed ? "exclamationmark.triangle" : "photo")
                    .font(.system(size: min(18, max(10, size.height / 5)), weight: .light))
                if failed, size.height >= 44 {
                    Text(MessagePhotoText.unavailable)
                        .font(.system(size: 9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(CheckTheme.secondaryText.opacity(0.8))
            .padding(4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(failed ? MessagePhotoText.unavailable : MessagePhotoText.loadingLabel)
    }
}

// MARK: - 사진 말풍선(①)

/// 대화의 사진 말풍선. 누르면 크게 보기(못 받은 사진은 한 번 다시 받기), 우클릭은 [크게 보기] + (받은 사진이면) [이 메시지 신고하기].
/// 신고는 **기존 신고 문**(`onReport` — 메시지 id 를 실은 `report_content`)을 그대로 지난다. 배경 · 테두리가 없다(그림이 곧 말풍선).
struct MessagePhotoBubble: View {
    let entry: MessageHistoryEntry
    let photo: MessagePhotoAttachment
    var context: MessagePhotoBubbleContext?
    /// 받은 말풍선에만 들어온다(`MessageBubbleReportRule` — 대화 뷰가 거른다).
    var onReport: (() -> Void)? = nil

    private var size: CGSize { MessagePhotoLayout.bubbleSize(for: photo, isMine: entry.isMine) }
    private var failed: Bool { context?.state(for: photo.path) == .failed }

    var body: some View {
        Button(action: tapped) {
            MessagePhotoSurface(path: photo.path, context: context, size: size)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { context?.open(entry, photo) } label: {
                Label(MessagePhotoText.openLabel, systemImage: "arrow.up.left.and.arrow.down.right")
            }
            if let onReport {
                Button(role: .destructive, action: onReport) {
                    Label(BlockReportText.reportMessageAction, systemImage: ChatBubbleMenuText.reportSymbol)
                }
            }
        }
        .accessibilityLabel(failed ? MessagePhotoText.unavailable : MessagePhotoText.photoAccessibility)
        .accessibilityHint(MessagePhotoText.openLabel)
    }

    private func tapped() {
        if failed {
            context?.retry(photo.path)
        } else {
            context?.open(entry, photo)
        }
    }
}

// MARK: - 덮개(③)

/// 덮개의 공통 바탕 — 대화를 **가린다**(반투명이면 말풍선이 그림 뒤에 겹쳐 읽힌다). 이모티콘 그리드와 같은 바탕이다.
struct MessagePhotoOverlayBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
            .fill(CheckTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
    }
}

/// 덮개 치수(순수 — 뷰와 시험이 같은 산식을 본다).
enum MessagePhotoOverlayLayout {
    static let padding: CGFloat = 8
    static let spacing: CGFloat = 6
    static let titleHeight: CGFloat = 16
    static let buttonHeight: CGFloat = 24
    static let noteHeight: CGFloat = 13

    /// 제목 줄을 세우는가 — 좁으면 접는다(사진과 버튼이 먼저다).
    static func showsTitle(availableHeight: CGFloat) -> Bool { availableHeight >= 150 }

    /// 설명 안내 한 줄을 세우는가 — 가장 좁은 대화 자리(76pt — 배너 · 패치노트 · 목표 편집이 다 뜬 때)에서는 접는다(버튼이 먼저다).
    static func showsNote(availableHeight: CGFloat, hasNote: Bool) -> Bool { hasNote && availableHeight >= 110 }

    /// 미리 보기 그림이 쓸 수 있는 상자(제목 · 설명 한 줄 · 버튼 줄을 뺀다).
    static func imageBox(availableHeight: CGFloat, hasNote: Bool) -> CGSize {
        let title = showsTitle(availableHeight: availableHeight) ? titleHeight + spacing : 0
        let note = showsNote(availableHeight: availableHeight, hasNote: hasNote) ? noteHeight + spacing : 0
        let height = availableHeight - padding * 2 - title - note - buttonHeight - spacing
        return CGSize(width: MessagePanelLayout.contentWidth - padding * 2, height: max(24, height))
    }

    /// 크게 보기 그림이 쓸 수 있는 상자(버튼 줄만 뺀다 — 제목이 없다).
    static func viewerBox(availableHeight: CGFloat) -> CGSize {
        let height = availableHeight - padding * 2 - buttonHeight - spacing
        return CGSize(width: MessagePanelLayout.contentWidth - padding * 2, height: max(24, height))
    }
}

/// 고른 사진 미리 보기 — [취소] · [보내기]. 입력칸에 글이 있으면 그 글이 설명으로 같이 간다는 한 줄.
struct MessagePhotoPreviewOverlay: View {
    let image: CGImage
    let pixelWidth: Int
    let pixelHeight: Int
    let availableHeight: CGFloat
    let hasCaption: Bool
    let canSend: Bool
    let isSending: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    private typealias Layout = MessagePhotoOverlayLayout

    var body: some View {
        let box = Layout.imageBox(availableHeight: availableHeight, hasNote: hasCaption)
        let fitted = MessagePhotoLayout.fitted(width: pixelWidth, height: pixelHeight, in: box)
        VStack(spacing: Layout.spacing) {
            if Layout.showsTitle(availableHeight: availableHeight) {
                Text(MessagePhotoText.previewTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Layout.titleHeight)
            }
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: MessagePhotoLayout.corner, style: .continuous))
                .frame(width: box.width, height: box.height)
                .accessibilityLabel(MessagePhotoText.photoAccessibility)
            if Layout.showsNote(availableHeight: availableHeight, hasNote: hasCaption) {
                Text(MessagePhotoText.captionNote)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Layout.noteHeight)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                MessagePhotoOverlayButton(title: MessagePhotoText.previewCancel, prominent: false, enabled: true, action: onCancel)
                MessagePhotoOverlayButton(
                    title: isSending ? MessagePhotoText.sending : MessagePhotoText.previewSend,
                    prominent: true,
                    enabled: canSend,
                    action: onSend
                )
            }
            .frame(height: Layout.buttonHeight)
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityAddTraits(.isModal)
    }
}

/// 크게 보기 — [저장…] · [닫기]. 그림은 대화 자리 안에 비율대로 맞춘다.
struct MessagePhotoViewerOverlay: View {
    let item: MessagePhotoViewerItem
    let context: MessagePhotoBubbleContext?
    let availableHeight: CGFloat
    let canSave: Bool
    let onSave: () -> Void
    let onClose: () -> Void

    private typealias Layout = MessagePhotoOverlayLayout

    var body: some View {
        let box = Layout.viewerBox(availableHeight: availableHeight)
        let fitted = MessagePhotoLayout.fitted(width: item.photo.width, height: item.photo.height, in: box)
        VStack(spacing: Layout.spacing) {
            MessagePhotoSurface(path: item.photo.path, context: context, size: fitted, fills: false)
                .frame(width: box.width, height: box.height)
                .accessibilityLabel(MessagePhotoText.photoAccessibility)
            HStack(spacing: 8) {
                MessagePhotoOverlayButton(title: MessagePhotoText.viewerSave, prominent: false, enabled: canSave, action: onSave)
                Spacer(minLength: 0)
                MessagePhotoOverlayButton(title: MessagePhotoText.viewerClose, prominent: true, enabled: true, action: onClose)
            }
            .frame(height: Layout.buttonHeight)
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityAddTraits(.isModal)
    }
}

/// 고른 사진을 줄이는 동안의 덮개(한 줄).
struct MessagePhotoPreparingOverlay: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(CheckTheme.secondaryText.opacity(0.7))
            Text(MessagePhotoText.preparing)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
            MessagePhotoOverlayButton(title: MessagePhotoText.previewCancel, prominent: false, enabled: true, action: onCancel)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
    }
}

/// 덮개의 알약 버튼([보내기] · [취소] · [닫기] · [저장…]).
struct MessagePhotoOverlayButton: View {
    let title: String
    let prominent: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(prominent ? Color.white : CheckTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(
                    Capsule().fill(prominent ? CheckTheme.accent.opacity(enabled ? 1 : 0.35) : Color.white.opacity(0.10))
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || prominent ? 1 : 0.5)
    }
}

// MARK: - 신고 시트 · 신고함의 작은 사진

/// 신고 시트의 사진 한 장(무엇을 신고하는지 눈으로 확인 — 글 인용 대신, 설명이 있으면 그 위에).
enum MessagePhotoThumbnailLayout {
    /// 신고 시트 썸네일 상자(pt).
    static let reportBox = CGSize(width: 120, height: 90)
    /// 신고함 행의 접힌 썸네일 상자.
    static let adminBox = CGSize(width: 120, height: 64)
    /// 신고함 행의 펼친 사진 상자(행 안쪽 폭 ≈ 276).
    static let adminEnlargedBox = CGSize(width: 260, height: 200)

    static func reportSize(_ photo: MessagePhotoAttachment) -> CGSize {
        MessagePhotoLayout.fitted(width: photo.width, height: photo.height, in: reportBox)
    }
}

/// 신고함 행의 신고된 사진(누르면 행 안에서 크게 · 다시 누르면 작게). 사진 경로만 알고 크기는 모른다 — 상자에 채워 자른다.
struct ReportAdminPhotoBlock: View {
    let path: String
    let context: MessagePhotoBubbleContext?
    let enlarged: Bool
    let onToggle: () -> Void

    var body: some View {
        // 경로만 알고 크기는 모른다 — 접히면 상자에 채워 자르고, 펼치면 상자 안에 비율대로 맞춘다.
        let box = enlarged ? MessagePhotoThumbnailLayout.adminEnlargedBox : MessagePhotoThumbnailLayout.adminBox
        VStack(alignment: .leading, spacing: 3) {
            Text(MessagePhotoText.adminPhotoTitle)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.secondaryText)
            Button(action: onToggle) {
                MessagePhotoSurface(path: path, context: context, size: box, fills: !enlarged, corner: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MessagePhotoText.adminPhotoTitle)
            .checkTooltip(MessagePhotoText.adminPhotoHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 이 조각의 높이(이름표 13 + 간격 3 + 상자).
    nonisolated static func height(enlarged: Bool) -> CGFloat {
        13 + 3 + (enlarged ? MessagePhotoThumbnailLayout.adminEnlargedBox.height : MessagePhotoThumbnailLayout.adminBox.height)
    }
}
