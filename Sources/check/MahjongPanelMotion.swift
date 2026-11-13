import SwiftUI
import CheckCore

// MARK: - 아잉 마작 패 움직임 그리기 (SPEC §5.9 '움직임' · §4.5 — 스토어 `motion` 을 화면 프레임으로)
//
//  · 스토어가 응답이 온 **뒤** 새 사건 꼬리의 마지막 움직임 하나를 `store.motion` 에 둔다(낙관적 그림 없음 — 코어 `MahjongMotion`).
//    화면은 그것을 **위치·크기(회전)** 로만 그린다: 버림 0.15초 · 울기·깡 0.25초 · 리치 선언패는 세운 꼴에서 가로로 눕는다.
//  · **불투명도는 건드리지 않는다**(메모리 easing-must-not-drive-opacity — 이징으로 깎으면 밀려나기 전에 사라진다).
//  · 동작 줄이기면 끈다(움직임 없이 끝 그림). 시스템 값은 읽기 전용이라 렌더 시험은 `\.mahjongReduceMotion` 으로 강제한다.
//  · 프레임은 `TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(…), paused:))` — 움직일 것이 없으면 멈춘다.
//    **입력(손패 누름·호버)은 TimelineView 바깥**이다: 펠트에는 입력이 없고, 손 칸은 부로 띠만 감싼다.
//  · 시각은 스토어 시계(`store.clock()` — 렌더 시험이 고정, 앱은 지금)로 잰다.

/// 화면 움직임 한 프레임(순수 — 시험이 되묻는다).
enum MahjongMotionPlan {
    /// 손 → 강.
    static let discardSeconds: TimeInterval = 0.15
    /// 강 → 부로(치·퐁·대명깡) · 손 → 부로(암깡).
    static let callSeconds: TimeInterval = 0.25
    /// 시작 자리까지의 거리(pt).
    static let travel: CGFloat = 36

    /// 화면 길이 — 사건 꼬리가 여럿이라 스토어가 한 장 길이를 줄였으면(1.5초 안에 따라잡기) 그 값과 작은 쪽.
    static func duration(_ motion: MahjongMotion) -> TimeInterval {
        let base = motion.kind == .discard ? discardSeconds : callSeconds
        return motion.duration < MahjongMotion.defaultDuration ? min(base, motion.duration) : base
    }

    /// 이징 전 진행도 0…1.
    static func progress(_ motion: MahjongMotion, now: Date) -> Double {
        let elapsed = now.timeIntervalSince(motion.startedAt)
        guard elapsed > 0 else { return 0 }
        let length = duration(motion)
        guard length > 0 else { return 1 }
        return min(1, elapsed / length)
    }

    /// 자리용 진행도(3차 ease-out). **불투명도에 쓰지 않는다.**
    static func eased(_ motion: MahjongMotion, now: Date) -> Double {
        let inverse = 1 - progress(motion, now: now)
        return 1 - inverse * inverse * inverse
    }

    /// 지금 그릴 움직임 — 동작 줄이기 · 다른 판·국 · 끝난 것은 nil.
    static func active(_ motion: MahjongMotion?, matchID: String?, handIndex: Int?, now: Date, reduceMotion: Bool) -> MahjongMotion? {
        guard !reduceMotion, let motion, motion.applies(matchID: matchID, handIndex: handIndex),
              progress(motion, now: now) < 1 else { return nil }
        return motion
    }

    /// 방위의 바깥쪽 단위 벡터(그 자리 손이 있는 쪽).
    static func outward(_ compass: MahjongCompass) -> CGSize {
        switch compass {
        case .bottom: CGSize(width: 0, height: 1)
        case .top: CGSize(width: 0, height: -1)
        case .left: CGSize(width: -1, height: 0)
        case .right: CGSize(width: 1, height: 0)
        }
    }

    /// 시작 자리의 어긋남 — 버림은 주인 손 쪽에서, 울기는 준 사람 쪽에서, 깡은 주인 손 쪽에서 절반만.
    static func startOffset(_ motion: MahjongMotion) -> CGSize {
        let travel = Self.travel
        switch motion.kind {
        case .discard:
            let v = outward(motion.to.compass)
            return CGSize(width: v.width * travel, height: v.height * travel)
        case .call:
            let from = outward(motion.from.compass), to = outward(motion.to.compass)
            let dx = from.width - to.width, dy = from.height - to.height
            let length = max(0.001, (dx * dx + dy * dy).squareRoot())
            return CGSize(width: dx / length * travel, height: dy / length * travel)
        case .kan:
            let v = outward(motion.to.compass)
            return CGSize(width: v.width * travel / 2, height: v.height * travel / 2)
        }
    }

    /// 지금 어긋남 — 시작 어긋남이 이징 진행도만큼 0 으로 줄어든다.
    static func offset(_ motion: MahjongMotion, now: Date) -> CGSize {
        let start = startOffset(motion)
        let left = 1 - eased(motion, now: now)
        return CGSize(width: start.width * left, height: start.height * left)
    }

    /// 이 움직임이 그 자리의 **마지막 부로**를 옮기나 — 울기(치·퐁·대명깡)는 늘 새 부로가 끝에 붙고, 깡은 암깡일 때만
    /// (가깡은 옛 퐁 자리가 커지는 것이라 어느 묶음인지 화면이 모른다 — 움직이지 않는다).
    static func movesNewestMeld(_ motion: MahjongMotion, compass: MahjongCompass, melds: [MahjongWireMeld]) -> Bool {
        guard motion.to.compass == compass, motion.to.area == .melds, let last = melds.last else { return false }
        switch motion.kind {
        case .call: return true
        case .kan: return last.type == "ankan"
        case .discard: return false
        }
    }

    /// 리치 눕기 — 끝 그림(가로 패)에 더할 회전(도): −90(세운 꼴) → 0(가로).
    static func riichiTilt(_ motion: MahjongMotion, now: Date) -> Double {
        -90 * (1 - eased(motion, now: now))
    }

    /// 움직이는 버림패의 회전 — 리치 선언패만 눕는다(보통 패는 0).
    static func tilt(_ motion: MahjongMotion, discard: MahjongDiscard?, now: Date) -> Double {
        discard?.riichi == true ? riichiTilt(motion, now: now) : 0
    }
}

/// 동작 줄이기 강제값 — nil 이면 시스템 설정(`accessibilityReduceMotion` 은 읽기 전용이라 렌더 시험이 여기로 강제한다).
private struct MahjongReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var mahjongReduceMotion: Bool? {
        get { self[MahjongReduceMotionKey.self] }
        set { self[MahjongReduceMotionKey.self] = newValue }
    }
}

/// 움직임 프레임 그릇 — 움직일 것이 있을 때만 TimelineView 가 돈다. 끝나면 한 번 다시 그려 멈춘다
/// (`.id` 로 새로 만들지 않는다 — 0.3.69 `.task`·`.id` 고리, 메모리 swiftui-task-id-identity-loop).
struct MahjongMotionFrames<Content: View>: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    var fixedNow: Date? = nil
    @ViewBuilder let content: (MahjongMotion?, Date) -> Content

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.mahjongReduceMotion) private var forcedReduceMotion
    @State private var settleTick = 0

    private var reduceMotion: Bool { forcedReduceMotion ?? systemReduceMotion }

    private func active(at now: Date) -> MahjongMotion? {
        MahjongMotionPlan.active(store.motion, matchID: payload.match?.id, handIndex: payload.match?.handIndex, now: now,
                                 reduceMotion: reduceMotion)
    }

    var body: some View {
        if let fixedNow {
            content(active(at: fixedNow), fixedNow)
        } else {
            let _ = settleTick
            let running = active(at: store.clock())
            TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(
                forRefreshRate: MiniGameFrameRateMonitor.shared.refreshHz), paused: running == nil)) { _ in
                let now = store.clock()
                content(active(at: now), now)
            }
            .task(id: running?.seq) {
                guard let running else { return }
                let left = MahjongMotionPlan.duration(running) - store.clock().timeIntervalSince(running.startedAt)
                do { try await Task.sleep(for: .seconds(max(0, left) + 0.05)) } catch { return }
                settleTick &+= 1
            }
        }
    }
}

/// 움직이는 패 한 장(띠 밖에 따로) — 끝 자리 + 어긋남, 리치 선언패면 눕기 회전. 불투명도는 늘 1.
struct MahjongMovingTile: View {
    let tile: MahjongStripTile
    let offset: CGSize
    var tilt: Double = 0
    var cornerLabels: Bool = true

    var body: some View {
        let size = MahjongTileArt.imageSize(tile.size, rotation: tile.rotation)
        MahjongTileView(face: tile.face, size: tile.size, state: tile.state, rotation: tile.rotation, cornerLabels: cornerLabels)
            .rotationEffect(.degrees(tilt))
            .position(x: tile.origin.x + size.width / 2 + offset.width, y: tile.origin.y + size.height / 2 + offset.height)
            .accessibilityHidden(true)
    }
}
