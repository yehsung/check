import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 0.3.70 받침대 정리 · 내 차례 표시 (감사 #2 #3 #10 #7 — 레인 R)
//
// 판 화면(`RummyPanelMatch.swift`)이 얹는 잎 뷰들. 규칙은 CheckCore(`RummyRackLayout.insert` · `RummyRackMelds.swift` ·
// 스토어 `rackSortMode`)에 있고 여기는 그리기만 한다.
//  · 랙 묶음 표시: 받침대에서 딱 붙인 덩어리가 그대로 맞는 묶음이면 그 아래에 초록 밑줄 띠 + 점수(`RummyRackMeldMarks`).
//    띠는 타일 아랫단(색 점 아래 6pt)과 선반 턱에 걸친다 — 뒷줄·앞줄 사이 틈이 1.6pt 뿐이라 타일 밖에 따로 줄을 둘 자리가 없다.
//  · 첫 등록 전: 받침대 위 난간 오른쪽에 '랙 묶음 합 N / 30'(판에 이번 차례 새로 놓은 맞는 묶음이 있으면 '랙 a + 판 b = N / 30').
//  · 뽑은 타일: 3초 동안 빛낸다(동작 줄이기면 테두리만) — `RummyRackView` 의 `freshTileIDs`.
//  · 내 차례: 받침대 테두리가 한 번 크게 빛난 뒤(0.8초) 은은하게 남는다 · 판 가운데 '내 차례' 배지 1.3초 · [완료] 안에 남은 초
//    (10초 이하 주황, 5초 이하 빨강 — 차례 링과 같은 색). 화면 안에서만(소리·Dock 없음). 동작 줄이기면 펄스·배지 움직임 없이 은은한 테두리.

/// 받침대 테두리 빛 단계.
enum RummyTurnGlowPhase: Equatable {
    /// 차례가 막 왔다(한 번 크게).
    case pulse
    /// 그 뒤 차례 내내 은은하게.
    case steady
}

/// 렌더 시험 주입구: 잠깐 떴다 사라지는 표시들을 그 순간으로 고정한다(앱은 nil).
struct RummyCuePreview: Equatable {
    var turnGlow: RummyTurnGlowPhase?
    var turnBadge = false
    var freshTileIDs: Set<Int> = []
    var sortMode: RummyRackSort?
}

private struct RummyCuePreviewKey: EnvironmentKey {
    static let defaultValue: RummyCuePreview? = nil
}

extension EnvironmentValues {
    var rummyCuePreview: RummyCuePreview? {
        get { self[RummyCuePreviewKey.self] }
        set { self[RummyCuePreviewKey.self] = newValue }
    }
}

/// 0.3.70 고정 글자.
enum RummyCueText {
    static let myTurnBadge = "내 차례"
    static func plan(table: Int, rack: Int) -> String {
        table > 0 ? "랙 묶음 \(rack) + 판 \(table) = \(table + rack) / 30" : "랙 묶음 합 \(rack) / 30"
    }
    static func meldPoints(_ points: Int) -> String { "\(points)" }
}

/// 랙 묶음 표시 색(초록 — [완료] 가능 색과 같은 계열).
enum RummyCueStyle {
    static var meld: Color { CheckTheme.working }
    static var fresh: Color { CheckTheme.pending }
    /// 밑줄 띠 높이와 타일 아랫단에 걸치는 깊이.
    static let meldBarHeight: CGFloat = 12
    static let meldBarOverlap: CGFloat = 6
}

/// 랙 묶음 밑줄 띠 + 점수. 받침대 칸 좌표.
struct RummyRackMeldMarks: View {
    let melds: [RummyRackMeld]
    let layout: RummyRackLayout
    let geometry: RummyRackGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(melds.enumerated()), id: \.offset) { _, meld in
                if let frame = Self.frame(of: meld, layout: layout, geometry: geometry) {
                    Text(RummyCueText.meldPoints(meld.points))
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: frame.width, height: frame.height)
                        .background(Capsule().fill(RummyCueStyle.meld))
                        .overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 띠 자리: 덩어리 가로(양끝 4pt 안쪽) · 타일 아랫단 6pt 위부터 12pt.
    static func frame(of meld: RummyRackMeld, layout: RummyRackLayout, geometry: RummyRackGeometry) -> CGRect? {
        let frames = meld.tileIDs.compactMap { layout.slot(of: $0).map(geometry.frame) }
        guard let first = frames.first, let last = frames.last else { return nil }
        let inset: CGFloat = 4
        return CGRect(x: first.minX + inset, y: first.maxY - RummyCueStyle.meldBarOverlap,
                      width: last.maxX - first.minX - inset * 2, height: RummyCueStyle.meldBarHeight)
    }
}

/// 첫 등록 전 '랙 묶음 합 N / 30' 꼬리표.
struct RummyRackPlanTag: View {
    let table: Int
    let rack: Int

    var body: some View {
        let reached = table + rack >= 30
        HStack(spacing: 4) {
            Image(systemName: reached ? "checkmark.circle.fill" : "square.stack.3d.up.fill")
                .font(.system(size: 9, weight: .bold))
            Text(RummyCueText.plan(table: table, rack: rack))
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(reached ? Color.white : CheckTheme.primaryText)
        .padding(.horizontal, 8)
        .frame(height: 17)
        .background(Capsule().fill(reached ? RummyCueStyle.meld : Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(reached ? Color.clear : RummyCueStyle.meld.opacity(0.7), lineWidth: 1))
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// 받침대 테두리 빛(내 차례).
struct RummyTurnGlow: View {
    let phase: RummyTurnGlowPhase

    var body: some View {
        let pulse = phase == .pulse
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(CheckTheme.accent.opacity(pulse ? 1 : 0.7), lineWidth: pulse ? 4 : 2)
            .shadow(color: CheckTheme.accent.opacity(pulse ? 0.95 : 0.55), radius: pulse ? 14 : 6)
            .padding(2)
            .allowsHitTesting(false)
    }
}

/// 판 가운데 '내 차례' 배지.
struct RummyTurnBadge: View {
    var body: some View {
        Label(RummyCueText.myTurnBadge, systemImage: "sparkles")
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Capsule().fill(CheckTheme.accent))
            .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: CheckTheme.accent.opacity(0.7), radius: 14)
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            .allowsHitTesting(false)
    }
}

/// [완료] 안의 남은 초 — **잎 뷰**만 시계를 읽는다(`RummyCountdownLeaf` 와 같은 갈래).
struct RummySubmitSeconds: View {
    let remaining: (Date) -> TimeInterval?
    let fixedNow: Date?

    var body: some View {
        if let fixedNow {
            chip(at: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in chip(at: context.date) }
        }
    }

    /// 차례 링과 같은 색 문턱: 10초 이하 주황, 5초 이하 빨강.
    static func tint(seconds: Int) -> Color? {
        seconds <= 5 ? CheckTheme.danger : (seconds <= 10 ? CheckTheme.pending : nil)
    }

    @ViewBuilder
    private func chip(at date: Date) -> some View {
        if let left = remaining(date) {
            let seconds = max(0, Int(left.rounded(.up)))
            let tint = Self.tint(seconds: seconds)
            Text(RummyText.seconds(seconds))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(tint ?? Color.black.opacity(0.28)))
                .allowsHitTesting(false)
        }
    }
}
