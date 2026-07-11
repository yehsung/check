import SwiftUI

struct CheckMascotView: View {
    let snapshot: WorkStatusSnapshot

    var body: some View {
        ZStack {
            // 상태 틴트 글로우 — 이미지 뒤에서 상태감을 은은하게 살린다.
            Circle()
                .fill(tint.opacity(snapshot.isWorking ? 0.30 : 0.18))
                .blur(radius: 8)
                .padding(2)
            mascot
        }
    }

    @ViewBuilder
    private var mascot: some View {
        if let image = CheckMascotAssets.image(for: snapshot) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(1)
        } else {
            // 로드 실패 폴백 — crash 대신 SF Symbol로 상태를 표시한다.
            Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }

    private var tint: Color {
        if snapshot.pendingSync {
            return CheckTheme.pending
        }
        return snapshot.isWorking ? CheckTheme.working : CheckTheme.offWork
    }
}
