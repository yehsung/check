import AppKit
import SwiftUI
import CheckCore

// MARK: - 미니게임 공용 계약 (v0.2.48)
//
// 별도 창에서 혼자 하는 미니게임 2종(타이밍 바 · 플래피 아잉)과 최고기록 순위표가 공유하는 타입.
// 허브(MiniGamePanel · 스토어 · 서비스)와 각 게임(MiniGameTimingBar.swift · MiniGameFlappy.swift)은
// 이 파일만 사이에 두고 만난다 — 게임은 허브를 모르고, 허브는 게임의 규칙을 모른다.
//
// v0.2.48 에 **공용 시각 키트**가 여기로 들어왔다(사용자 지적 2026-09-10: "디자인이나 효과 임팩트가 너무 없다").
// 배경·무대·이펙트를 각 게임이 따로 만들면 두 게임이 다른 제품처럼 보인다 — 오버레이 카드를 공용으로 뺀 것과
// 같은 이유다. 게임이 쓰는 것은 `MiniGameStage`(무대 팔레트) · `MiniGameBackdrop`(하늘·지형) ·
// `MiniGameEffects`(링·파편) · `MiniGameScorePop` · `MiniGameOverlayCard` 다섯이고, 나머지는 각자의 그림이다.


// MARK: - 프레임 상한 (v0.2.50)


/// 미니게임 창이 지금 선 화면의 주사율을 들고 있는 **단 하나의 지점**.
///
/// 왜 전역인가: 이 값을 만드는 곳(창 컨트롤러 — 창이 어느 화면에 섰는지는 AppKit 만 안다)과 쓰는 곳
/// (게임 잎 뷰 — SwiftUI 안쪽)이 스토어를 거치지 않고 만난다. 스토어에 넣으면 근무 타이머 상태를 보는
/// 모든 표면이 화면을 옮길 때마다 무효화된다. `@Observable` 이라 잎 뷰는 값을 읽기만 하면 다시 그려진다.
@Observable
@MainActor
final class MiniGameFrameRateMonitor {
    /// 앱이 쓰는 단 하나의 인스턴스. 테스트는 `init` 으로 따로 만든다(전역을 오염시키지 않는다).
    static let shared = MiniGameFrameRateMonitor()

    /// 지금 화면의 주사율(Hz). 시작값은 폴백 — 창이 서기 전에는 아무도 모른다.
    private(set) var refreshHz: Int = MiniGameFrameRate.baselineFPS

    init(refreshHz: Int = MiniGameFrameRate.baselineFPS) {
        self.refreshHz = refreshHz
    }

    /// 창이 선 화면에서 주사율을 다시 읽는다(창 생성 · 표시 · **화면 이동** · 화면 구성 변경).
    /// 값이 같으면 대입하지 않는다 — `@Observable` 은 같은 값 대입도 관찰자를 깨워 게임 뷰를 통째로 다시 만든다.
    @discardableResult
    func update(for window: NSWindow?) -> Int {
        let hz = MiniGameFrameRate.refreshRate(of: window)
        if hz != refreshHz { refreshHz = hz }
        return hz
    }

    #if DEBUG
    /// **테스트 전용.** 값을 아무거나 밀어 넣는다 — "갱신이 실제로 일어났는가"를 값으로 구별하려면
    /// 먼저 틀린 값을 세워 둬야 한다(이 기계에 화면이 하나뿐이라 실제로 옮겨 볼 수가 없다).
    func setForTesting(_ hz: Int) { refreshHz = hz }
    #endif
}


// MARK: - 무대(스테이지)


// MARK: - 배경(하늘 · 별 · 능선)


// MARK: - 이펙트(링 · 파편)


// MARK: - 공용 오버레이 카드

/// 캔버스 위에 뜨는 시작 안내·결과 카드. **두 게임이 같은 모양을 쓴다** — 색과 글씨가 게임마다 달라
/// "통일성이 없다"는 지적을 받았다(2026-09-08). 새 게임을 붙일 때도 이 뷰만 쓴다.
///
/// v0.2.48 에서 아이콘 원판·강조 색·조작 안내 알약이 붙었다(디자인 보강). 인자는 전부 기본값이 있어
/// 예전 호출부(제목·부제·행동 세 줄)는 그대로 컴파일된다.
struct MiniGameOverlayCard: View {
    /// 큰 제목. 시작 화면은 게임 이름, 결과 화면은 점수("총점 720" · "12점").
    let title: String
    /// 제목을 점수처럼 크게(30pt heavy rounded, 고정폭 숫자) 그릴지. 시작 화면은 false.
    var titleIsScore: Bool = false
    /// 가운데 줄. 시작 화면은 규칙 한 줄, 결과 화면은 "최고 N".
    let subtitle: String
    /// 가운데 줄을 강조색(초록)으로 — 신기록일 때만.
    var subtitleIsHighlighted: Bool = false
    /// 맨 아래 행동 안내. "클릭해서 시작" · "클릭해서 다시".
    let action: String
    /// 제목 위 아이콘(SF Symbol). nil 이면 아이콘 줄이 통째로 빠진다.
    var icon: String? = nil
    /// 아이콘 원판·행동 알약의 색. 무대 색을 넘기면 카드가 배경과 한 몸으로 읽힌다.
    var tint: Color = CheckTheme.accent

    var body: some View {
        VStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: MiniGameCardChrome.iconDiameter, height: MiniGameCardChrome.iconDiameter)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .overlay(Circle().stroke(tint.opacity(0.40), lineWidth: 1))
            }
            Text(title)
                .font(titleIsScore ? .system(size: 30, weight: .heavy, design: .rounded) : .headline)
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
            Text(subtitle)
                .font(subtitleIsHighlighted ? .caption.bold() : .caption2)
                .monospacedDigit()
                .foregroundStyle(subtitleIsHighlighted ? CheckTheme.working : CheckTheme.secondaryText)
                .multilineTextAlignment(.center)
            Text(action)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.16)))
                .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, MiniGameCardChrome.verticalPadding)
        .frame(maxWidth: MiniGameCardChrome.width)
        .modifier(MiniGameCardChrome(tint: tint))
    }
}

/// 캔버스 위에 뜨는 카드의 **크롬 한 벌**(배경 · 테두리 · 그림자). 시작·결과 카드(`MiniGameOverlayCard`)와
/// 정지 카드(`MiniGamePauseCard`)가 같은 창에서 번갈아 뜨는데 각자 만들면 모서리·그림자·폭이 갈린다 —
/// 실제로 갈렸다(모서리 16 vs 14 · 그림자 14/5 vs 12/4 · 폭 250 vs 240, 2026-09-10 지적).
struct MiniGameCardChrome: ViewModifier {
    /// 테두리 그라디언트의 강조색. 무대 색을 넘기면 카드가 배경과 한 몸으로 읽힌다.
    var tint: Color = CheckTheme.accent
    /// 바닥 불투명도. 정지 카드는 **1.0(불투명)** 이어야 한다 — 스크림과 같은 색 반투명이면 카드가 녹는다.
    var fillOpacity: Double = 0.94
    /// 위에서 아래로 옅어지는 흰 광택(정지 카드처럼 스크림 위에 뜨는 카드만).
    var sheen: Bool = false

    /// 두 카드가 공유하는 수치. 여기 말고 다른 곳에 적지 마라.
    static let cornerRadius: CGFloat = 14
    static let width: CGFloat = 240
    static let verticalPadding: CGFloat = 14
    /// 아이콘 원판 지름(카드 맨 위 동그라미).
    static let iconDiameter: CGFloat = 34

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return content.background(
            shape
                .fill(CheckTheme.panelElevated.opacity(fillOpacity))
                .overlay(
                    sheen
                        ? AnyView(shape.fill(LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom)))
                        : AnyView(Color.clear)
                )
                .overlay(
                    shape.stroke(
                        LinearGradient(colors: [tint.opacity(0.45), CheckTheme.border],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
    }
}

/// 무대 이름 칩. **두 게임이 같은 픽셀을 쓴다** — 같은 정보를 각자 만들면 캡슐 채움(0.16 vs black 0.38)과
/// 테두리(0.40 vs 0.55)가 갈려 같은 창에서 두 물건으로 보인다(2026-09-10 지적).
struct MiniGameStageChip: View {
    let stage: MiniGameStage

    var body: some View {
        Text(stage.name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(stage.glow)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(stage.glow.opacity(0.16)))
            .overlay(Capsule().stroke(stage.glow.opacity(0.40), lineWidth: 1))
            .fixedSize()
    }
}

/// 캔버스 위에 잠깐 떠오르는 점수/판정 글씨("+100 · 완벽!" · "+1"). 두 게임이 같은 모양을 쓴다.
/// 위치는 부르는 쪽이 `.position(x:y:)` 로 잡는다 — 이 뷰는 모양과 등장 애니메이션만 안다.
struct MiniGameScorePop: View {
    let text: String
    var caption: String? = nil
    var tint: Color = CheckTheme.working
    var reduceMotion: Bool = false

    @State private var scale: CGFloat = 0.55
    @State private var lift: CGFloat = 0

    var body: some View {
        VStack(spacing: 1) {
            Text(text)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(tint)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .scaleEffect(reduceMotion ? 1 : scale)
        .offset(y: reduceMotion ? 0 : lift)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 0.30, bounce: 0.42)) { scale = 1 }
            withAnimation(.easeOut(duration: 0.55)) { lift = -14 }
        }
    }
}
