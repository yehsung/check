import AppKit
import Observation
import SwiftUI
import CheckCore

// MARK: - 왜 시스템 툴팁을 버렸는가 (v0.3.25)
//
// 사용자 신고: "마우스를 올려도 툴팁이 안 뜨는 경우가 많다." 이 앱의 툴팁은 전부 SwiftUI 의 시스템 툴팁
// 모디파이어(AppKit NSView.toolTip)였고 Sources/check 에 30곳이 있었다. 실측(2026-09-16):
//   · 실앱(0.3.24) 팝오버에서 새로고침·로그아웃·토큰 사용량 버튼을 번갈아 6번 호버(CGEvent 이동, 새 창 감지)하면
//     시스템 툴팁은 **2번만** 떴고, 뜰 때도 **1.7초** 걸렸다.
//   · 최소 MenuBarExtra(.window) 앱에서 앱을 활성으로 해도 **2/6** — 앱 활성 여부와 무관하다.
//   · 같은 창에서 SwiftUI onHover + 앵커 preference → 루트 overlayPreferenceValue 로 모은 자체 말풍선은 **7/7** 이었다
//     (ScrollView 안 행, 오른쪽 가장자리, 하단 푸터 포함). 떠나면 매번 비워졌다.
// 그래서 호버 추적·표시·배치를 우리가 쥔다. 선례는 v0.2.44 잔디 칸(ContributionGridView)이다 — 같은 이유로 시스템 툴팁을
// 걷고 자체 말풍선(ContributionCellBubble)을 쓰며, 배치 기법(alignmentGuide 가 주는 말풍선 자신의 크기로 원점 계산)도 거기서 왔다.
//
// 함께 잰 사실(같은 날):
//   · 한 뷰에 .onHover 를 두 번 달면 둘 다 불린다 — 호출부의 기존 호버 하이라이트를 그대로 둘 수 있다.
//   · .disabled(true) 뒤(바깥)에 단 .onHover 도 불린다 — 비활성 버튼도 왜 막혔는지 말할 수 있다.
//   · .accessibilityHint(Text(s)) 는 AXHelp 로 노출된다 — 시스템 툴팁이 맡던 접근성 몫을 이것이 대신한다.
//   · 바깥 뷰의 anchorPreference 는 **자식이 실은 값을 덮는다**(ImageRenderer 프로브: 자식 [1, 3] + 바깥 [2] → [2],
//     바깥이 빈 배열이면 []). transformAnchorPreference 는 [1, 3, 2] 로 보존했다. 툴팁 안에 툴팁이 있는 자리
//     (토큰 사용량 패널 안의 순위 버튼)가 실제로 있어서 모디파이어는 transform 쪽을 쓴다.
//
// 구성: 루트마다 `.checkTooltipLayer()` 하나(센터 소유 + 말풍선 그리기), 호출부는 `.checkTooltip(문구)`.
// 레이어가 없는 창에 붙으면 시스템 툴팁으로 폴백한다 — 툴팁이 조용히 사라지는 것보다 늦게라도 뜨는 편이 낫다.

// MARK: - 타이밍

/// 말풍선 타이밍(초). **여기 한 곳에만 둔다** — 상태 기계·센터·테스트가 전부 이 값을 읽는다.
nonisolated enum CheckTooltipTiming {
    /// 첫 표시 지연. 커서가 지나가는 버튼마다 말풍선이 번쩍이면 그게 더 시끄럽다.
    static let showDelay: TimeInterval = 0.4
    /// 워밍 창. 말풍선이 숨은 지 이 시간 안에 다른 항목에 들어가면 지연 없이 바로 띄운다(레일을 훑어 내려갈 때).
    static let warmWindow: TimeInterval = 0.6
}

// MARK: - 상태 기계

/// 어느 말풍선을 언제 보일지 정하는 **순수** 상태 기계. 시각은 인자로 받는다 — 시계를 안에 두면
/// "0.4초 뒤에 뜬다"를 재는 테스트가 실제로 기다려야 하고, 기다리는 테스트는 결국 아무도 안 돌린다.
///
/// 항목은 호출부 모디파이어가 만든 UUID 로 구분한다. 한 루트(센터) 안에서만 의미가 있다.
nonisolated struct CheckTooltipIntent: Sendable, Equatable {
    /// 첫 표시 지연(프로덕션은 `CheckTooltipTiming.showDelay`).
    let showDelay: TimeInterval
    /// 워밍 창(프로덕션은 `CheckTooltipTiming.warmWindow`).
    let warmWindow: TimeInterval

    /// 지금 보이는 항목.
    private(set) var visibleID: UUID?
    /// 표시를 기다리는 항목과 그 예약 시각.
    private(set) var pendingID: UUID?
    private(set) var pendingAt: TimeInterval?
    /// 커서가 올라가 있는 항목들, **들어온 순서대로**. 툴팁 안에 툴팁이 있으면 둘 이상이다 — 안쪽을 떠날 때
    /// 바깥(아직 커서 아래)을 다시 올리려면 누가 남았는지뿐 아니라 누가 가장 최근인지도 알아야 한다.
    private(set) var hovered: [UUID] = []
    /// 클릭으로 거둔 항목들 — 호버가 끝날 때까지 다시 안 뜬다.
    private(set) var suppressed: Set<UUID> = []
    /// 말풍선이 마지막으로 **호버를 떠나서** 숨은 시각(워밍 판정의 재료).
    private(set) var lastHiddenAt: TimeInterval?

    init(
        showDelay: TimeInterval = CheckTooltipTiming.showDelay,
        warmWindow: TimeInterval = CheckTooltipTiming.warmWindow
    ) {
        self.showDelay = showDelay
        self.warmWindow = warmWindow
    }

    /// 보이거나 대기 중인 항목이 있는가(센터가 클릭 모니터를 거는 조건).
    var isActive: Bool { visibleID != nil || pendingID != nil }

    /// 커서가 항목에 들어왔다.
    mutating func hoverBegan(_ id: UUID, now: TimeInterval) {
        // 클릭으로 거둔 항목은 호버가 끝날 때까지 아무것도 안 한다.
        guard !suppressed.contains(id) else { return }
        if !hovered.contains(id) { hovered.append(id) }
        // 같은 항목의 중복 통지(onHover true 두 번)는 예약 시각을 뒤로 밀지 않는다.
        guard visibleID != id, pendingID != id else { return }
        let warm = lastHiddenAt.map { now - $0 < warmWindow } ?? false
        if visibleID != nil || warm {
            // 다른 말풍선이 보이는 중이거나 방금 숨었다 — 사용자는 이미 말풍선을 읽는 중이다. 기다리게 하지 않는다.
            visibleID = id
            pendingID = nil
            pendingAt = nil
        } else {
            pendingID = id
            pendingAt = now + showDelay
        }
    }

    /// 예약 시각이 됐다. 대기 중인 항목이 그 id 이고 여전히 호버 중일 때만 보인다.
    ///
    /// 시각은 받지만 예약 시각과 비교하지 않는다 — 기다리는 일은 센터의 Task 가 이미 했다. 여기서 한 번 더 비교하면
    /// 깨어난 시각과 시계의 단위 차이(수 ns)만으로 말풍선을 통째로 잃을 수 있다.
    mutating func fire(_ id: UUID, now: TimeInterval) {
        guard pendingID == id, hovered.contains(id) else { return }
        visibleID = id
        pendingID = nil
        pendingAt = nil
    }

    /// 커서가 항목을 떠났다.
    mutating func hoverEnded(_ id: UUID, now: TimeInterval) {
        hovered.removeAll { $0 == id }
        suppressed.remove(id)
        if visibleID == id {
            visibleID = nil
            lastHiddenAt = now
        }
        if pendingID == id {
            pendingID = nil
            pendingAt = nil
        }
        // 툴팁 안에 툴팁(토큰 사용량 행 ⊃ 순위 버튼): 바깥 행에 들어오며 걸린 대기는 안쪽 버튼이 덮어 지웠다. 버튼을 떠나
        // 행 위에 멈추면 커서는 여전히 행 위인데 아무것도 기다리지 않는다 — 남은 호버 중 가장 최근 항목을 다시 올린다.
        // 안쪽 말풍선이 보이다 떠난 경우면 방금 숨었으니 워밍으로 바로, 대기 중에 떠난 경우면 처음처럼 기다린다.
        if visibleID == nil, pendingID == nil, let next = hovered.last(where: { !suppressed.contains($0) }) {
            if let lastHiddenAt, now - lastHiddenAt < warmWindow {
                visibleID = next
            } else {
                pendingID = next
                pendingAt = now + showDelay
            }
        }
    }

    /// 앱 어딘가에서 마우스를 눌렀다. 보이는/대기 중인 항목을 거두고, 그 항목은 호버가 끝날 때까지 다시 안 뜬다.
    ///
    /// ★ 워밍을 **끊는다**(lastHiddenAt = nil). 클릭으로 숨긴 것을 '방금 숨었다'로 치지 않는 것은 물론이고, 클릭 **전에**
    ///   남아 있던 워밍도 지운다 — A 에서 떠나 B 가 워밍으로 바로 뜬 직후 B 를 누르고 옆 C 로 옮기면, 옛 lastHiddenAt 이
    ///   아직 0.6초 안이라 C 가 즉시 떠 버린다. 클릭 뒤 옆 버튼으로 옮겨도 즉시 뜨지 않게 하는 것이 이 전이의 목적이다.
    ///   설계 문구는 "lastHiddenAt 은 갱신하지 않는다"였다. 문구대로 **그냥 두면** 20.0 에 A 를 떠나고 → 20.2 에 워밍으로 뜬
    ///   B 를 누르고 → 20.4 에 C 에 들어가는 경로에서 C 가 즉시 뜬다. 그래서 목적 쪽을 따라 지운다(테스트
    ///   `mouseDownDoesNotWarmTheNeighbor` 의 (나)가 이 차이를 못 박는다).
    mutating func mouseDown(now: TimeInterval) {
        if let shown = visibleID {
            suppressed.insert(shown)
            visibleID = nil
        }
        if let waiting = pendingID {
            suppressed.insert(waiting)
            pendingID = nil
            pendingAt = nil
        }
        lastHiddenAt = nil
    }

    /// 전부 비운다(루트가 사라질 때).
    mutating func reset() {
        visibleID = nil
        pendingID = nil
        pendingAt = nil
        hovered = []
        suppressed = []
        lastHiddenAt = nil
    }
}

// MARK: - 센터

/// 루트 하나(팝오버·설정·할 일 보드·미니게임 창)의 말풍선 상태. 상태 기계를 감싸 **시간과 클릭**을 붙인다.
///
/// 관찰 대상은 `visibleID` 하나뿐이다. 호버가 바뀔 때마다 다시 그려지는 것은 말풍선 오버레이 하나여야 한다 —
/// 이 앱은 팝오버 전체 무효화를 매우 경계한다(호출부 모디파이어도 이 값을 읽지 않는다).
@MainActor
@Observable
final class CheckTooltipCenter {
    /// 지금 보이는 말풍선의 주인. 값이 실제로 바뀔 때만 쓴다(같은 값을 다시 써도 관찰자가 깨지 않게).
    private(set) var visibleID: UUID?

    @ObservationIgnored private var intent: CheckTooltipIntent
    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    /// 지금 걸려 있는 fire 예약(어느 항목의 어느 시각). 같은 예약을 두 번 걸지 않는 판정에 쓴다.
    @ObservationIgnored private var scheduledFire: (id: UUID, at: TimeInterval)?
    @ObservationIgnored private var mouseDownMonitor: CheckTooltipMonitorToken?

    /// - Parameters:
    ///   - showDelay·warmWindow: 프로덕션은 언제나 기본값. **테스트만** 짧게 주입한다.
    ///   - now: 단조 시계(초). 테스트가 시각을 쥘 수 있게 주입 지점을 남긴다.
    init(
        showDelay: TimeInterval = CheckTooltipTiming.showDelay,
        warmWindow: TimeInterval = CheckTooltipTiming.warmWindow,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        intent = CheckTooltipIntent(showDelay: showDelay, warmWindow: warmWindow)
        self.now = now
    }

    deinit {
        // deinit 은 비격리라 격리 프로퍼티의 비-Sendable 토큰을 못 만진다 — 상자에 넣어 둔 이유다(보드 스크롤 모니터와 같은 길).
        // 정상 경로는 레이어의 onDisappear → reset() 이 먼저 뗀다. 여기는 그 통지가 안 온 경로의 안전망이다.
        if let token = mouseDownMonitor {
            Task { @MainActor in NSEvent.removeMonitor(token.raw) }
        }
    }

    /// 클릭 모니터가 걸려 있는가(헤드리스 검증 지점).
    var isMouseDownMonitorInstalled: Bool { mouseDownMonitor != nil }

    /// 표시를 기다리는 항목(헤드리스 검증 지점).
    var pendingID: UUID? { intent.pendingID }

    func hoverBegan(_ id: UUID) {
        intent.hoverBegan(id, now: now())
        apply()
    }

    func hoverEnded(_ id: UUID) {
        intent.hoverEnded(id, now: now())
        apply()
    }

    /// 마우스 다운(모니터가 부른다 — 테스트도 직접 부른다).
    func mouseDown() {
        intent.mouseDown(now: now())
        apply()
    }

    /// 전부 비우고 예약·모니터까지 걷는다(루트가 사라질 때).
    func reset() {
        intent.reset()
        cancelFire()
        removeMouseDownMonitor()
        if visibleID != nil { visibleID = nil }
    }

    /// 상태 기계의 결과를 화면·예약·모니터에 반영한다. 모든 전이 뒤에 한 번씩.
    private func apply() {
        if visibleID != intent.visibleID { visibleID = intent.visibleID }
        scheduleFireIfNeeded()
        if intent.isActive {
            if mouseDownMonitor == nil { installMouseDownMonitor() }
        } else {
            removeMouseDownMonitor()
        }
    }

    private func scheduleFireIfNeeded() {
        guard let id = intent.pendingID, let at = intent.pendingAt else {
            cancelFire()
            return
        }
        if let scheduledFire, scheduledFire.id == id, scheduledFire.at == at { return }
        fireTask?.cancel()
        scheduledFire = (id, at)
        let delay = max(0, at - now())
        fireTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // 취소 검사가 없으면 cancel() 이 곧 즉시 표시다 — 이미 떠난 항목의 말풍선이 뜬다.
            guard !Task.isCancelled else { return }
            self?.fire(id)
        }
    }

    private func fire(_ id: UUID) {
        fireTask = nil
        intent.fire(id, now: now())
        // 무시된 fire(예약이 그대로 남은 경우)는 다시 걸지 않는다 — 0초 예약이 되풀이되는 고리를 만들지 않게.
        if intent.pendingID != id { scheduledFire = nil }
        apply()
    }

    private func cancelFire() {
        fireTask?.cancel()
        fireTask = nil
        scheduledFire = nil
    }

    /// 클릭 모니터가 보는 이벤트: 왼쪽·오른쪽·그 밖의 버튼 누름.
    static let mouseDownMonitorMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// 클릭 모니터 핸들러. 알리고 **받은 이벤트를 그대로 돌려준다** — 말풍선을 거둘 뿐 클릭을 먹지 않는다.
    /// nil 을 돌려주면 말풍선이 보이거나 대기 중인 동안(툴팁 달린 버튼을 누르는 거의 모든 순간) 앱의 클릭이 사라진다.
    ///
    /// 설치 클로저 안에 두지 않고 따로 뺀 이유: 이 반환값을 테스트가 실제 `NSEvent` 로 재게 하려고. 헤드리스 테스트에서
    /// 모니터를 이벤트 큐로 부를 수는 없다 — 스크래치 프로브(독립 실행 파일)에서 postEvent 로 넣은 마우스다운은 모니터가
    /// 없어도 nextEvent 로 돌아오지 않았고, 테스트가 `NSApplication.shared` 로 앱 객체를 만드는 것은 CheckWindowAnchorTests 가 금한다.
    nonisolated static func mouseDownMonitorHandler(
        notify: @escaping @MainActor () -> Void
    ) -> (NSEvent) -> NSEvent? {
        return { event in
            // 로컬 모니터 콜백은 메인 런루프(메인 스레드)에서 온다.
            MainActor.assumeIsolated { notify() }
            return event
        }
    }

    /// 클릭 모니터를 건다. **걸기 전에 기존 것을 반드시 뗀다** — 두 벌이 걸리면 한 벌은 영영 못 뗀다.
    /// 로컬 모니터는 우리 앱으로 오는 이벤트만 본다 — 남의 앱을 누르는 것은 호버 종료가 이미 처리한다.
    private func installMouseDownMonitor() {
        removeMouseDownMonitor()
        let raw = NSEvent.addLocalMonitorForEvents(matching: Self.mouseDownMonitorMask, handler: Self.mouseDownMonitorHandler { [weak self] in self?.mouseDown() })
        mouseDownMonitor = raw.map(CheckTooltipMonitorToken.init)
    }

    private func removeMouseDownMonitor() {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor.raw) }
        mouseDownMonitor = nil
    }
}

/// `NSEvent` 모니터 토큰 상자 — deinit(비격리)에서도 꺼낼 수 있게 Sendable 로 감싼다(TodoBoardScrollMonitorToken 과 같은 이유).
private final class CheckTooltipMonitorToken: @unchecked Sendable {
    let raw: Any
    init(_ raw: Any) { self.raw = raw }
}

// MARK: - 배치

/// 말풍선 원점(컨테이너 좌표, 좌상단). **순수 함수** — 크기를 재지 않고 alignmentGuide 가 준 말풍선 크기로 부른다.
nonisolated enum CheckTooltipPlacement {
    /// 대상과 말풍선 사이 간격(pt).
    static let gap: CGFloat = 6
    /// 컨테이너 가장자리 여백(pt).
    static let margin: CGFloat = 6

    /// - 세로: 아래 우선. 아래가 안 되면 위. 둘 다 안 되면 공간이 큰 쪽(같으면 아래)에 붙인 뒤 컨테이너 안으로 클램프.
    /// - 가로: 대상 가운데 정렬을 컨테이너 안으로 클램프. 말풍선이 컨테이너보다 크면 여백 자리(margin).
    static func origin(
        target: CGRect,
        bubble: CGSize,
        container: CGSize,
        gap: CGFloat = 6,
        margin: CGFloat = 6
    ) -> CGPoint {
        let below = target.maxY + gap
        let above = target.minY - gap - bubble.height
        let y: CGFloat
        if below + bubble.height <= container.height - margin {
            y = below
        } else if above >= margin {
            y = above
        } else {
            let roomBelow = container.height - target.maxY
            let roomAbove = target.minY
            y = clamp(roomBelow >= roomAbove ? below : above, lower: margin, upper: container.height - margin - bubble.height)
        }
        let x = clamp(target.midX - bubble.width / 2, lower: margin, upper: container.width - margin - bubble.width)
        return CGPoint(x: x, y: y)
    }

    /// [lower, upper] 로 클램프. 상한이 하한보다 작으면(말풍선이 자리보다 크면) 하한.
    static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }
}

// MARK: - 말풍선

/// 툴팁 말풍선. 카드는 잔디 말풍선(ContributionCellBubble)과 같다 — 같은 앱 안에서 말풍선이 두 모양이면 안 된다.
struct CheckTooltipBubble: View {
    let text: String

    /// 글 폭 상한(pt). 짧은 글은 글에 맞추고, 넘으면 이 폭에서 줄바꿈한다.
    static let maxTextWidth: CGFloat = 240

    var body: some View {
        // `.frame(maxWidth:)` 를 쓰지 않는다 — 오버레이가 컨테이너 폭을 제안하면 짧은 글도 240 으로 늘어난다.
        CheckTooltipTextWidthLayout(maxWidth: Self.maxTextWidth) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CheckTheme.primaryText)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.panelElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("checkTooltipBubble")
    }
}

/// 글 하나를 받아 **제안 폭을 무시하고** 크기를 정하는 레이아웃: 이상 폭이 상한 이하면 이상 크기, 넘으면 상한 폭을 제안해 잰 크기.
struct CheckTooltipTextWidthLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        return text.sizeThatFits(textProposal(for: text))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let text = subviews.first else { return }
        text.place(at: bounds.origin, anchor: .topLeading, proposal: textProposal(for: text))
    }

    private func textProposal(for text: LayoutSubview) -> ProposedViewSize {
        let ideal = text.sizeThatFits(.unspecified)
        return ideal.width <= maxWidth ? ProposedViewSize(ideal) : ProposedViewSize(width: maxWidth, height: nil)
    }
}

// MARK: - 환경 · preference

private struct CheckTooltipCenterKey: EnvironmentKey {
    static var defaultValue: CheckTooltipCenter? { nil }
}

extension EnvironmentValues {
    /// 가장 가까운 `.checkTooltipLayer()` 의 센터. 레이어 밖이면 nil(→ 모디파이어가 시스템 툴팁으로 폴백).
    var checkTooltipCenter: CheckTooltipCenter? {
        get { self[CheckTooltipCenterKey.self] }
        set { self[CheckTooltipCenterKey.self] = newValue }
    }
}

/// 호버 중인 항목 하나(위치는 앵커로 싣고, 루트가 자기 좌표로 푼다).
struct CheckTooltipEntry: Equatable, Sendable {
    let id: UUID
    let text: String
    let anchor: Anchor<CGRect>
}

struct CheckTooltipPreferenceKey: PreferenceKey {
    static var defaultValue: [CheckTooltipEntry] { [] }

    static func reduce(value: inout [CheckTooltipEntry], nextValue: () -> [CheckTooltipEntry]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - 모디파이어

extension View {
    /// 자체 말풍선 툴팁. 문구가 공백뿐이면 아무것도 붙이지 않는다.
    func checkTooltip(_ text: String) -> some View {
        modifier(CheckTooltipModifier(text: text))
    }

    /// 말풍선을 그리는 루트 레이어. 창 루트에 **한 번만**, 모든 클리핑(ScrollView·clipShape·clipped) 밖에 단다.
    func checkTooltipLayer() -> some View {
        modifier(CheckTooltipLayerModifier())
    }
}

/// 호출부 모디파이어. **센터의 visibleID 를 읽지 않는다** — 읽으면 호버 한 번에 이 모디파이어를 단 뷰 전부가 다시 평가된다.
struct CheckTooltipModifier: ViewModifier {
    let text: String

    @Environment(\.checkTooltipCenter) private var center
    @State private var hovering = false
    @State private var id = UUID()

    @ViewBuilder
    func body(content: Content) -> some View {
        // body 에서 읽어 둔다 — preference 클로저 안에서만 읽으면 hovering 이 바뀌어도 이 body 가 다시 안 돌아 값이 안 갈린다.
        let showing = hovering
        let entryID = id
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 빈 문구(총합 0 인 순위 행 등)에는 말풍선·힌트·호버 추적 무엇도 달지 않는다 — 빈 카드가 뜨면 고장으로 보인다.
            content
        } else if let center {
            content
                // 호출부의 기존 onHover(하이라이트)와 함께 불린다(실측). 비활성 버튼 바깥에 달려도 불린다.
                .onHover { inside in
                    if hovering != inside { hovering = inside }
                    if inside {
                        center.hoverBegan(entryID)
                    } else {
                        center.hoverEnded(entryID)
                    }
                }
                // 호버 중에 뷰가 사라지면(분기 전환·패널 닫힘) 끝났다는 통지가 안 온다 — 여기서 대신 알린다.
                .onDisappear {
                    guard hovering else { return }
                    hovering = false
                    center.hoverEnded(entryID)
                }
                // 로컬 호버 중일 때만 싣는다. transform 이라 **안쪽 툴팁이 실은 값을 보존한다**(머리 주석의 실측).
                .transformAnchorPreference(key: CheckTooltipPreferenceKey.self, value: .bounds) { entries, anchor in
                    if showing {
                        entries.append(CheckTooltipEntry(id: entryID, text: text, anchor: anchor))
                    }
                }
                .accessibilityHint(Text(text))
        } else {
            // 레이어가 없는 창에 붙었다 — 툴팁이 사라지는 것보다 늦게라도 뜨는 편이 낫다. 저장소에서 시스템 툴팁은 이 한 곳뿐이다.
            content.help(text)
        }
    }
}

/// 루트 레이어: 센터를 소유해 환경으로 내려주고, 모인 항목 중 보이는 것 하나를 그린다.
@MainActor
struct CheckTooltipLayerModifier: ViewModifier {
    @State private var center = CheckTooltipCenter()

    func body(content: Content) -> some View {
        content
            .environment(\.checkTooltipCenter, center)
            .overlayPreferenceValue(CheckTooltipPreferenceKey.self) { entries in
                CheckTooltipOverlay(entries: entries, center: center)
            }
            // 창이 닫히면(팝오버 닫힘 포함) 예약·클릭 모니터까지 걷는다.
            .onDisappear { center.reset() }
            // 설정·미니게임·할 일 보드 창은 닫을 때 orderOut 만 한다 — 뷰가 살아 있어 onDisappear 가 **안 온다**. 그 사이
            // 호버 중이던 항목의 끝 통지도 안 와서, 대기가 숨은 창에서 뜨고 클릭 모니터·거둔 항목이 남는다. 창이 숨는 순간을 따로 본다.
            // 크기 0 — ImageRenderer 는 AppKit 뷰 자리를 노란 상자로 그리므로 자리를 차지하면 렌더 테스트가 전부 흔들린다.
            .background(CheckTooltipWindowWatcher { center.reset() }.frame(width: 0, height: 0))
    }
}

/// 레이어가 붙은 창이 **숨는 순간**(orderOut·close)을 알린다.
///
/// 실측(2026-09-16 스크래치 프로브, borderless NSWindow): `orderOut(nil)` 에 `didChangeOcclusionStateNotification` 은 오지 않았고
/// (알파 0.01·보조 앱에서는 close 의 willClose 만 왔다), `isVisible` 키-값 관찰은 orderFront 마다 true, orderOut 마다 false 로
/// 두 번씩 정확히 왔다. 그래서 알림이 아니라 `isVisible` 을 본다.
struct CheckTooltipWindowWatcher: NSViewRepresentable {
    let onHidden: @MainActor () -> Void

    func makeNSView(context: Context) -> CheckTooltipWindowWatcherView {
        let view = CheckTooltipWindowWatcherView(frame: .zero)
        view.onHidden = onHidden
        return view
    }

    func updateNSView(_ nsView: CheckTooltipWindowWatcherView, context: Context) {
        nsView.onHidden = onHidden
    }
}

final class CheckTooltipWindowWatcherView: NSView {
    var onHidden: (@MainActor () -> Void)?
    private var observation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation?.invalidate()
        observation = nil
        guard let window else { return }
        let box = CheckTooltipWatcherBox(self)
        observation = window.observe(\.isVisible, options: [.new]) { _, change in
            guard change.newValue == false else { return }
            // 창을 숨기는 호출(orderOut)은 메인 스레드에서 오고, 키-값 관찰은 그 호출 안에서 동기로 불린다.
            MainActor.assumeIsolated { box.view?.windowDidHide() }
        }
    }

    /// 창이 숨었다(관찰이 부른다 — 테스트도 직접 부른다).
    func windowDidHide() {
        onHidden?()
    }

    deinit {
        observation?.invalidate()
    }
}

/// 관찰 클로저가 뷰를 약하게 쥐게 하는 상자(클로저가 Sendable 이어야 해서 뷰를 직접 담지 못한다).
private final class CheckTooltipWatcherBox: @unchecked Sendable {
    weak var view: CheckTooltipWindowWatcherView?
    init(_ view: CheckTooltipWindowWatcherView) { self.view = view }
}

/// 말풍선 오버레이. `center.visibleID` 를 읽는 곳은 **여기뿐**이라, 말풍선이 바뀔 때 다시 평가되는 것도 이 뷰뿐이다.
struct CheckTooltipOverlay: View {
    let entries: [CheckTooltipEntry]
    let center: CheckTooltipCenter

    var body: some View {
        if let visible = center.visibleID, let entry = entries.last(where: { $0.id == visible }) {
            GeometryReader { proxy in
                let rects = entries.map { proxy[$0.anchor] }
                let target = proxy[entry.anchor]
                let shown = Self.innermostIndex(of: target, among: rects).map { entries[$0] } ?? entry
                CheckTooltipPlacedBubble(text: shown.text, target: proxy[shown.anchor], container: proxy.size)
            }
            // 말풍선이 자기 밑의 호버·클릭을 가로채면 커서 아래 버튼이 호버를 잃고 말풍선이 깜빡인다.
            .allowsHitTesting(false)
        }
    }

    /// 보이는 항목의 사각형 **안에 든** 호버 항목 중 가장 작은 것의 자리. 없으면 nil.
    ///
    /// 툴팁 안에 툴팁이 있으면 두 모디파이어의 onHover 가 거의 동시에 오는데 **순서가 보장되지 않는다** — 안쪽이 먼저 오면
    /// 상태 기계는 바깥을 마지막으로 올리고, 순위 버튼 위에서 행 설명이 뜬다. preference 에 실린 항목은 전부 지금 커서 아래라
    /// (로컬 호버 중일 때만 싣는다) 바깥 사각형 안에 든 가장 작은 것이 곧 커서 바로 아래 항목이다.
    nonisolated static func innermostIndex(of visible: CGRect, among rects: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, rect) in rects.enumerated() where visible.contains(rect) {
            let area = rect.width * rect.height
            if best == nil || area < best!.area { best = (index, area) }
        }
        return best?.index
    }
}

/// 컨테이너 크기의 투명 판 위에 말풍선을 `CheckTooltipPlacement` 원점에 놓는다(렌더 테스트가 이 뷰를 직접 그린다).
struct CheckTooltipPlacedBubble: View {
    let text: String
    let target: CGRect
    let container: CGSize

    var body: some View {
        Color.clear
            .frame(width: max(0, container.width), height: max(0, container.height))
            .overlay(alignment: .topLeading) {
                // 크기를 재지 않고 배치한다: alignmentGuide 가 말풍선 자신의 폭·높이(d)를 주므로 그 크기로 원점을 계산하고,
                // 그 원점이 overlay 의 topLeading 에 오도록 가이드를 음수로 돌려준다 — 첫 프레임 점프가 없다(잔디 말풍선과 같은 기법).
                // 말풍선은 이 overlay 의 **무조건** 자식이다 — 조건부 자식에 건 가이드는 반영되지 않았다(ContributionGridView 주석의 실측).
                CheckTooltipBubble(text: text)
                    .alignmentGuide(.leading) { d in
                        -CheckTooltipPlacement.origin(
                            target: target, bubble: CGSize(width: d.width, height: d.height), container: container
                        ).x
                    }
                    .alignmentGuide(.top) { d in
                        -CheckTooltipPlacement.origin(
                            target: target, bubble: CGSize(width: d.width, height: d.height), container: container
                        ).y
                    }
            }
    }
}
