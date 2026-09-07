import SwiftUI

// MARK: - 미니게임 공용 계약 (v0.2.46)
//
// 팝오버 안에서 혼자 하는 미니게임 2종(타이밍 바 · 플래피 아잉)과 최고기록 순위표가 공유하는 타입.
// 허브(MiniGamePanel · 스토어 · 서비스)와 각 게임(MiniGameTimingBar.swift · MiniGameFlappy.swift)은
// 이 파일만 사이에 두고 만난다 — 게임은 허브를 모르고, 허브는 게임의 규칙을 모른다.

/// 미니게임 종류. rawValue 는 서버 표 `minigame_scores.game` 의 값과 같다(변경 금지 — 서버 check 제약과 짝).
enum MiniGameKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case timingBar = "timing_bar"
    case flappy = "flappy"

    var id: String { rawValue }

    /// 패널 선택 칩·순위표 제목에 쓰는 이름.
    var title: String {
        switch self {
        case .timingBar: "타이밍 바"
        case .flappy: "플래피 아잉"
        }
    }

    /// 한 판에서 나올 수 있는 최대 점수(클라·서버 동일 — 서버 check 제약 상한). 초과는 업로드하지 않는다.
    var maxScore: Int {
        switch self {
        case .timingBar: 1000
        case .flappy: 999
        }
    }

    /// 한 줄 규칙 설명(시작 오버레이).
    var howToPlay: String {
        switch self {
        case .timingBar: "움직이는 마커가 파란 구간에 들어올 때 클릭 · 10라운드"
        case .flappy: "클릭해서 점프 · 기둥 사이를 지나갈수록 +1"
        }
    }
}

/// 게임 논리 좌표계. 게임 규칙은 언제나 이 크기 안에서 계산하고, 뷰는 실제 캔버스 크기에 **비율 유지**로 맞춘다
/// (팝오버 높이 예산 때문에 캔버스 높이가 preferred 와 minimum 사이에서 바뀔 수 있다 — 규칙은 영향받지 않는다).
enum MiniGameCanvas {
    static let logicalWidth: CGFloat = 292
    static let logicalHeight: CGFloat = 200
    /// 패널이 여유 있을 때의 캔버스 높이(= logicalHeight, 배율 1).
    static let preferredHeight: CGFloat = 200
    /// 배너·목표 편집이 얹혀 예산이 줄 때 캔버스가 양보하는 하한.
    static let minimumHeight: CGFloat = 140

    /// 실제 캔버스 크기에서 논리 좌표를 그릴 배율과 원점(가운데 정렬). 순수 함수.
    static func transform(in size: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        transform(in: size, logicalSize: CGSize(width: logicalWidth, height: logicalHeight))
    }

    /// 게임이 자기 논리 크기를 가질 때(플래피는 창 캔버스와 같은 비율의 세로로 긴 판을 쓴다 — 위아래가
    /// 레터박스로 비면 기둥이 천장·바닥에 닿지 않는 것처럼 보인다). 배율은 짧은 축이 정하므로 비율은 유지된다.
    static func transform(in size: CGSize, logicalSize: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let scale = min(size.width / logicalSize.width, size.height / logicalSize.height)
        let origin = CGPoint(
            x: (size.width - logicalSize.width * scale) / 2,
            y: (size.height - logicalSize.height * scale) / 2
        )
        return (scale, origin)
    }
}

/// 허브(MiniGamePanel)가 게임 잎 뷰에 건네는 것 전부. 게임 뷰는 이것 말고 스토어를 읽지 않는다.
struct MiniGameHost {
    /// 이 게임의 로컬 최고기록(결과 화면 "최고 N" 과 신기록 판정에 쓴다).
    var bestScore: Int
    /// 시스템 '동작 줄이기'. 참이면 흔들림·스쿼시 같은 장식 애니메이션을 끈다(규칙·속도는 그대로).
    var reduceMotion: Bool
    /// 값이 바뀌면 진행 중인 판을 **즉시** 끝낸다(팝오버 닫힘 · 다른 패널로 전환 · 게임 종류 전환).
    /// 플래피는 그 순간 게임오버(점수 유효), 타이밍 바는 판 무효(10라운드를 못 채움).
    var interruptToken: Int
    /// 유효하게 끝난 판의 점수(0 이상, maxScore 이하). 허브가 최고기록 갱신·업로드·순위 새로고침을 맡는다.
    var onFinished: (Int) -> Void
    /// 진행 중 여부 변화(시작 → true, 종료/무효 → false). 허브가 스페이스 키 모니터·상태 표시에 쓴다.
    var onPlayingChanged: (Bool) -> Void

    /// 렌더 테스트·프리뷰용 무해한 호스트.
    static func inert(bestScore: Int = 0, reduceMotion: Bool = false, interruptToken: Int = 0) -> MiniGameHost {
        MiniGameHost(bestScore: bestScore, reduceMotion: reduceMotion, interruptToken: interruptToken,
                     onFinished: { _ in }, onPlayingChanged: { _ in })
    }
}

/// 게임 잎 뷰가 허브에서 받는 입력. 허브는 캔버스 클릭(DragGesture minimumDistance 0 의 첫 onChanged = 마우스 다운)과
/// 스페이스 키(로컬 keyDown 모니터)를 이 한 값으로 접어 `MiniGameInput` 카운터로 전달한다 — 게임은 "카운터가 늘었다"만 본다.
struct MiniGameInput: Equatable, Sendable {
    /// 클릭·스페이스가 올 때마다 1 증가. 게임은 onChange 로 감지해 점프/정지/시작을 처리한다.
    var actionCount: Int = 0
}

/// 결정론적 난수(SplitMix64). 게임 규칙은 이것만 쓰고, 테스트는 시드를 고정한다.
struct MiniGameRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1) 균등.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// [lo, hi] 균등.
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }
}

/// 프레임 루프가 실제로 도는지 헤드리스에서 세는 카운터(DEBUG). 게임 뷰는 TimelineView 본문마다 `note()` 를 부른다.
/// "paused 뒤 0회" · "팝오버 닫힘 뒤 0회" 를 테스트가 못 박는 지점.
enum MiniGameFrameProbe {
    #if DEBUG
    nonisolated(unsafe) private static var count = 0
    private static let lock = NSLock()

    static func note() { lock.lock(); count += 1; lock.unlock() }
    static func reset() { lock.lock(); count = 0; lock.unlock() }
    static var frames: Int { lock.lock(); defer { lock.unlock() }; return count }
    #else
    @inline(__always) static func note() {}
    static func reset() {}
    static var frames: Int { 0 }
    #endif
}

// MARK: - 공용 오버레이 카드

/// 캔버스 위에 뜨는 시작 안내·결과 카드. **두 게임이 같은 모양을 쓴다** — 색과 글씨가 게임마다 달라
/// "통일성이 없다"는 지적을 받았다(2026-09-08). 새 게임을 붙일 때도 이 뷰만 쓴다.
///
/// 구성은 위에서부터 제목(subheadline bold) · 설명 또는 점수 · 행동 안내(caption, accent) 세 줄이다.
/// 바탕은 잔디 말풍선과 같은 `panelElevated` + `border`, 모서리 10.
struct MiniGameOverlayCard: View {
    /// 큰 제목. 시작 화면은 게임 이름, 결과 화면은 점수("총점 720" · "12점").
    let title: String
    /// 제목을 점수처럼 크게(26pt heavy rounded, 고정폭 숫자) 그릴지. 시작 화면은 false.
    var titleIsScore: Bool = false
    /// 가운데 줄. 시작 화면은 규칙 한 줄, 결과 화면은 "최고 N".
    let subtitle: String
    /// 가운데 줄을 강조색(초록)으로 — 신기록일 때만.
    var subtitleIsHighlighted: Bool = false
    /// 맨 아래 행동 안내. "클릭해서 시작" · "클릭해서 다시".
    let action: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(titleIsScore ? .system(size: 26, weight: .heavy, design: .rounded) : .subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
            Text(subtitle)
                .font(subtitleIsHighlighted ? .caption.bold() : .caption2)
                .monospacedDigit()
                .foregroundStyle(subtitleIsHighlighted ? CheckTheme.working : CheckTheme.secondaryText)
                .multilineTextAlignment(.center)
            Text(action)
                .font(.caption)
                .foregroundStyle(CheckTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 236)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.panelElevated)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        )
    }
}
