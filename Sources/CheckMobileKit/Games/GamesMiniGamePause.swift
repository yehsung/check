import CheckCore
#if os(iOS)
import SwiftUI
#endif

/// 폰 미니게임 일시정지의 **게임별 표**(폰 1.0.16 · 전이는 코어 `MiniGamePauseState`, 시계·임시 항목은 `GamesMiniGameHub`).
///
/// | 게임 | 앱 내림 | [그만두기]·뒤로 | 5분 상한 | 임시 항목 |
/// | 테트리스·길건너 | 자동 정지 | 여기까지 확정 | 있음, 넘으면 확정 | 있음 |
/// | 플래피·타이밍 바 | 자동 정지 | 버림 | 없음 | 없음 |
///
/// 맥 표(`MiniGamePauseState.quittingKeepsTheScore`)와 **플래피만 다르다**: 맥은 접어도 그 점수가 남고, 폰은 사용자 답으로
/// 버린다(2026-11-01 "지금처럼 버림"). 그래서 코어에 두지 않았다.
package enum GamesMiniGamePausePolicy {
    /// 판을 접었을 때 그 점수가 남는가. `GamesPlayController.endRound()` 의 갈래와 같아야 한다(시험이 엔진을 돌려 맞춰 본다).
    /// **게임이 늘면 여기서 멈춰 서서 그 게임의 `endRound()` 갈래를 정해라.** 기본 가지를 두지 않는 이유다.
    package static func quittingKeepsTheScore(_ kind: MiniGameKind) -> Bool {
        switch kind {
        case .tetris, .crossy: return true
        case .timingBar, .flappy: return false
        }
    }

    /// 5분 상한을 거는가. 맥과 같은 원칙이다 — 상한이 하는 일은 판을 접는 것이므로, **접어도 기록이 남는 게임에만** 건다.
    /// 안 남는 게임에 걸면 점수를 건지는 장치가 아니라 판을 없애는 장치가 된다. 상한이 없는 판은 토큰이 30분에 늙으면
    /// 끝낼 때 `GamesMiniGameText.submitTokenDead` 로 끝난다(`GamesMiniGameHub.recordScore`).
    package static func capApplies(_ kind: MiniGameKind) -> Bool {
        quittingKeepsTheScore(kind)
    }
}

#if os(iOS)
/// 정지 화면: 캔버스를 **완전히 가리는** 스크림 + 카드(또는 3-2-1). 맥 `pauseOverlay` 의 폰판이다.
///
/// 스크림이 불투명인 이유는 미관이 아니다 — 순위표가 걸린 게임이라 멈춰 놓고 다음 칸을 외우는 것이 이득이 되면 안 된다.
/// 앱 전환기 스냅숏에도 판이 안 찍히게 `.inactive` 에서 이미 이 화면이 선다.
struct GamesMiniGamePauseOverlay: View {
    let kind: MiniGameKind
    let state: MiniGamePauseState
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            CheckTheme.panel
            if state.showsCard {
                card
            } else if let remaining = state.countdown {
                countdown(remaining)
            }
        }
        .contentShape(Rectangle())
        // ★ 판은 라이트 모드에서도 어둡다. 버튼 토큰이 라이트 값을 고르면 어두운 스크림 위에 어두운 빨강이 되어 [그만두기] 가 안 읽힌다(라이트 캡처 실측).
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
    }

    private var card: some View {
        VStack(spacing: MobileTheme.space2) {
            Image(systemName: "pause.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CheckTheme.pending)
                .frame(width: 34, height: 34)
                .background(Circle().fill(CheckTheme.pending.opacity(0.16)))
                .accessibilityHidden(true)
            Text(GamesMiniGameText.pauseTitle)
                .font(.headline)
                .foregroundStyle(CheckTheme.primaryText)
            Text(GamesMiniGameText.pauseSubtitle(kind))
                .font(.footnote)
                .foregroundStyle(CheckTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // 큰 글자에서는 위아래로 접는다 — 좁은 판에서 버튼 글자가 잘리면 무엇을 누르는지 모른다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MobileTheme.space2) { buttons }
                VStack(spacing: MobileTheme.space2) { buttons }
            }
            .padding(.top, MobileTheme.space1)
        }
        .padding(MobileTheme.space4)
        // 판 위 글자라 캔버스처럼 상한을 둔다. 판 폭(최소 288pt)을 넘지 않는 크기까지다.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var buttons: some View {
        AingButton(GamesMiniGameText.resumeAction, systemImage: "play.fill", kind: .filled, size: .md, action: onResume)
        AingButton(GamesMiniGameText.quitAction, systemImage: "xmark", kind: .destructive, size: .md, action: onQuit)
    }

    private func countdown(_ remaining: Int) -> some View {
        VStack(spacing: 4) {
            Text(String(remaining))
                .font(.system(size: 68, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.accent)
            Text(GamesMiniGameText.resumeCountdownCaption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
