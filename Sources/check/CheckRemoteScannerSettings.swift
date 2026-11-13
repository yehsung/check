import CheckCore
import SwiftUI

// MARK: - 설정 [원격 기계 연결] — 행(설정 본문) + 쪽(설정 창 본문 자리)
//
// 차단 목록과 같은 쪽 전환이다(`showsRemoteScannerInSettings`) — 설정 본문에는 행 하나만 더해지고, 목록·명령은
// 그 행을 눌렀을 때 창 본문 자리에 선다. 연결 코드는 이 쪽을 떠나면 지운다(closeRemoteScannerSettings).

struct RemoteScannerSettingsEntryRow: View {
    let store: WorkTimerStore

    var body: some View {
        Button {
            store.openRemoteScannerSettings()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(RemoteScannerText.entryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                    Text(RemoteScannerText.entryDetail)
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
        .accessibilityLabel(RemoteScannerText.entryTitle)
        .accessibilityHint(RemoteScannerText.entryDetail)
    }
}

/// 목록 상태(순수). 빈 목록과 로드 전·실패를 가른다(차단 목록과 같은 규약).
enum RemoteScannerPageState: Equatable {
    case loading, failed, empty, list

    static func of(loaded: Bool, loading: Bool, failed: Bool, count: Int) -> RemoteScannerPageState {
        if count > 0 { return .list }
        if failed { return .failed }
        if !loaded || loading { return .loading }
        return .empty
    }
}

struct CheckRemoteScannerSettingsPage: View {
    let store: WorkTimerStore
    var now: () -> Date = { Date() }

    @State private var confirmingDeviceID: String?

    private var state: RemoteScannerPageState {
        RemoteScannerPageState.of(
            loaded: store.remoteScannerLoaded, loading: store.remoteScannerLoading,
            failed: store.remoteScannerFailed, count: store.remoteScannerDevices.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "설정으로") { store.closeRemoteScannerSettings() }
                Text(RemoteScannerText.entryTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                Spacer(minLength: 6)
            }
            Text(RemoteScannerText.lede)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            commandCard
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelStyle()

            if let notice = store.remoteScannerNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.remoteScannerServerNotReady {
                Text(RemoteScannerText.serverNotReady)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.pending)
            }

            Text(RemoteScannerText.listTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
                .padding(.leading, 2)
            listContent
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelStyle()

            Text(RemoteScannerText.thisMacNote + " " + RemoteScannerText.windowsLater)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var commandCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let code = store.remoteScannerLinkCode {
                Text(code.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CheckTheme.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckTheme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 8) {
                    Text(RemoteScannerText.commandHelp + " " + RemoteScannerText.expiry(code.expiresAt, now: now()))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    RemoteScannerPillButton(title: RemoteScannerText.copy, prominent: false) { store.copyRemoteScannerCommand() }
                }
            } else {
                HStack(spacing: 8) {
                    Text(RemoteScannerText.commandHelp)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    RemoteScannerPillButton(
                        title: store.remoteScannerMakingCode ? RemoteScannerText.makingCommand : RemoteScannerText.makeCommand,
                        prominent: true,
                        enabled: !store.remoteScannerMakingCode && !store.remoteScannerServerNotReady
                    ) {
                        store.makeRemoteScannerLinkCode()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch state {
        case .loading:
            Text("불러오는 중…")
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 36)
        case .failed:
            VStack(spacing: 6) {
                Text(RemoteScannerText.failed)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                PanelRetryButton { store.loadRemoteScannerDevices(force: true) }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        case .empty:
            Text(RemoteScannerText.empty)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 36)
        case .list:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(store.remoteScannerDevices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { PanelDivider() }
                    deviceRow(device)
                }
            }
        }
    }

    private func deviceRow(_ device: ScannerDevice) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Text("\(device.kindLabel) · \(RemoteScannerText.lastSeen(device, now: now())) · 이번 달 \(TokenNumberFormatter.compactKorean(device.monthTotal))")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if store.revokingScannerDeviceIDs.contains(device.id) {
                Text("끊는 중…")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
            } else if confirmingDeviceID == device.id {
                RemoteScannerPillButton(title: RemoteScannerText.revokeConfirm, prominent: true, danger: true) {
                    confirmingDeviceID = nil
                    store.revokeRemoteScanner(device.id)
                }
            } else {
                RemoteScannerPillButton(title: RemoteScannerText.revoke, prominent: false) { confirmingDeviceID = device.id }
            }
        }
    }
}

/// 이 쪽의 알약 단추(설정 [저장]과 같은 모양 — 시스템 단추는 렌더 검증에서 그려지지 않는다).
private struct RemoteScannerPillButton: View {
    let title: String
    var prominent: Bool
    var enabled: Bool = true
    var danger: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : CheckTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    if prominent && enabled {
                        if danger {
                            Capsule().fill(CheckTheme.danger)
                        } else {
                            Capsule().fill(CheckTheme.gaugeGradient)
                        }
                    } else {
                        Capsule().fill(CheckTheme.trackFill)
                            .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
                    }
                }
                .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!enabled)
        .fixedSize()
    }
}
