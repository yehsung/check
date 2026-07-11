import SwiftUI

struct CheckMascotView: View {
    let snapshot: WorkStatusSnapshot

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(snapshot.isWorking ? 0.22 : 0.12))
                .blur(radius: 1)
                .offset(y: 2)
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.96), CheckTheme.panelElevated],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.26), radius: 8, y: 3)
            face
            Image(systemName: snapshot.isWorking ? "checkmark" : "sparkle")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.white.opacity(0.9))
                .offset(x: 13, y: 14)
        }
    }

    private var face: some View {
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                Circle()
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                    .frame(width: snapshot.isWorking ? 5 : 6, height: snapshot.isWorking ? 7 : 6)
                Circle()
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                    .frame(width: snapshot.isWorking ? 5 : 6, height: snapshot.isWorking ? 7 : 6)
            }
            Capsule()
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.86))
                .frame(width: snapshot.isWorking ? 15 : 10, height: 3)
        }
        .offset(y: -1)
    }

    private var tint: Color {
        if snapshot.pendingSync {
            return CheckTheme.pending
        }
        return snapshot.isWorking ? CheckTheme.working : CheckTheme.offWork
    }
}
