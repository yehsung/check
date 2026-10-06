import AppKit
import CheckCore
import SwiftUI

// MARK: - AI 리밋 창 (v0.3.45)
//
// `CheckSettingsWindowController.swift` 의 **형제**다. 그 파일의 규약을 그대로 베꼈고(지연 생성 · 멱등 열기 ·
// 닫아도 파괴 안 함 · 자리 저장 이름 등록 · 고착 감시자 + 재생성 상한 · 테스트 알파 0), 달라지는 것은 숫자와
// 담는 뷰뿐이다. 그 규약 하나하나의 근거는 그 파일 머리말에 있다 — 특히:
//   · `makeKeyAndOrderFront` 는 **조용히 실패할 수 있다**(v0.2.27 할 일 보드 실측: `isVisible` 이 true 라고
//     거짓말했고 창은 어느 Space 에도 없었다). 통한 복구는 **창을 버리고 새로 만드는 것** 하나뿐이었다.
//   · `setFrameAutosaveName` 은 같은 이름이 이미 등록돼 있으면 **false 를 돌려주고 아무 일도 하지 않는다** —
//     재생성 경로에서 옛 창의 등록을 안 풀면 자리가 영영 저장되지 않는다.
//
// ## 왜 팝오버 안이 아니라 별도 창인가 (2026-10-07 사용자 결정)
// 팝오버 본문 열은 **316pt** 로 고정이고(카드 안쪽 292), 거기에 제공자 셋 × 창 둘 = 바 여섯 개와 리셋 시각
// 캡션을 넣으면 세로가 한 화면을 넘긴다. 팝오버는 근무 상태를 보는 자리이고 리밋은 **들여다보는** 자리라
// 체류 시간도 다르다. 그래서 요약은 한 줄로 팝오버에 남기고(`CheckAILimitsRow`) 상세는 이 창이 받는다.
//
// ## ★ 툴팁 레이어
// 이 창의 루트에는 `.checkTooltipLayer()` 가 **반드시** 있어야 한다. 없으면 `.checkTooltip` 이 시스템 툴팁으로
// 폴백하는데, 시스템 툴팁은 이 저장소가 실측한 대로 2/6 확률 · 1.7초 지연이라 사실상 안 뜬다
// (`CheckTooltip.swift` 머리말 — v0.3.25 가 자체 말풍선을 만든 이유).
//
// ## ★ 스페이스 키
// 이 창의 식별자는 `MiniGameSpaceKey.standaloneWindowIDs` 에 들어 있어야 한다. 그 목록이 모르는 창에서 누른
// 스페이스는 미니게임 창이 띄워져 있을 때 **통째로 삼켜진다**(2026-09-17 실사용 제보 · 체스 창이 같은 이유로
// 등록돼 있다). 이 창에 입력칸은 없지만 스페이스로 스크롤하는 사람이 있고, 무엇보다 이 등록은 창을 만들 때마다
// 치러야 하는 비용이다.

// MARK: - 레이아웃 (순수 상수)

/// 리밋 창의 **고정** 레이아웃. 창 크기를 두 곳에 적지 않는다.
///
/// ── 숫자의 근거 ──
///  · `cardInnerWidth` 가 먼저 정해졌다: 카드 한 줄에 [타일 28][이름+리셋 캡션][큰 %] 가 서야 한다.
///    실측(10pt, 2026-10-07) "안티그래비티" 51.9 · "오후 6:59 리셋" 62.97 · "초기화됨 · 확인 못 함" 84.0 이고
///    큰 숫자는 22pt bold monospacedDigit 로 "100% 이상" 이 **106.3** 이다.
///    글 열 최악 84 + 간격 10 + 숫자 106.3 + 타일 28 + 간격 10 = 238.3 → 여유를 둔 **280**.
///  · `contentWidth` = 280 + 카드 패딩 14×2 + 창 패딩 20×2 = **348**. 창은 리사이즈된다(넓히면 글 열이 는다).
///  · `cardHeight 100` = 패딩 14×2 + 머리 줄 28 + 8 + 5시간 바 6 + 10 + 주간 라벨 12 + 4 + 주간 바 3 = 99 → 100.
///  · 안내 한 줄(만료·429·구독 리밋 없음)이 붙으면 +18 이다 — 카드 높이를 **고정하지 않고** 자연 높이로 두고,
///    목록을 `ScrollView` 에 담아 어떤 조합에서도 잘리지 않게 한다(창 높이 계약이 제공자 수 × 상태에 끌려다니면
///    `CheckSettingsWindow` 가 겪은 "행이 붙을 때마다 상수를 올리는" 쳇바퀴가 그대로 재현된다).
enum AILimitWindowLayout {
    static let contentPadding: CGFloat = 20
    static let cardPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 10
    static let cardCornerRadius: CGFloat = 14

    /// 카드 안쪽 글·바가 설 폭.
    static let cardInnerWidth: CGFloat = 280
    /// 창 콘텐츠 폭.
    static var contentWidth: CGFloat { cardInnerWidth + cardPadding * 2 + contentPadding * 2 }

    /// 제공자 로고 타일 한 변.
    static let tileSide: CGFloat = 28
    /// 카드 머리 줄 높이(타일·이름·큰 숫자가 같은 줄에 선다).
    static let headerRowHeight: CGFloat = 28
    /// 5시간 바 높이(크게).
    static let fiveHourBarHeight: CGFloat = 6
    /// 주간 바 높이(얇게).
    static let weeklyBarHeight: CGFloat = 3
    /// 카드 안쪽 세로 간격(머리 줄 ↔ 5시간 바 ↔ 주간 묶음).
    static let cardRowSpacing: CGFloat = 8
    static let weeklyBlockSpacing: CGFloat = 10
    static let weeklyLabelSpacing: CGFloat = 4

    /// 안내 한 줄이 없는 카드의 자연 높이.
    static let cardHeight: CGFloat = 100
    /// 안내 한 줄이 붙으면 더해지는 높이.
    static let noticeExtraHeight: CGFloat = 18

    /// 창 머리글 높이.
    static let headerHeight: CGFloat = 24
    static let headerSpacing: CGFloat = 12

    /// 카드 `n` 장이 필요한 콘텐츠 높이(안내 줄은 세지 않는다 — 넘치면 스크롤이 받는다).
    static func contentHeight(cards: Int) -> CGFloat {
        let list = CGFloat(max(1, cards)) * cardHeight + CGFloat(max(0, cards - 1)) * cardSpacing
        return contentPadding * 2 + headerHeight + headerSpacing + list
    }

    /// 제공자 셋이 다 있는 기본 창 크기.
    static var defaultContentSize: NSSize {
        NSSize(width: contentWidth, height: contentHeight(cards: AILimitProvider.allCases.count))
    }

    /// 최소 크기(카드 한 장).
    static var minContentSize: NSSize {
        NSSize(width: contentWidth, height: contentHeight(cards: 1))
    }
}

// MARK: - 카드

/// 제공자 하나의 카드. 로고 타일 + 이름 + `오후 6:59 리셋` 캡션 + 우측 큰 % + 굵은 바,
/// 그 아래 `주간 60%` + 얇은 바.
///
/// **숫자·캡션·표시여부를 계산하지 않는다** — 전부 `AILimitFreshnessRule` 에서 받은 `AILimitDisplay` 를 그린다.
struct AILimitProviderCard: View {
    let provider: AILimitProvider
    let fiveHour: AILimitDisplay
    let weekly: AILimitDisplay
    /// 만료·429·플랜 없음의 한 줄(없으면 nil). 네트워크 실패에는 **문구가 없다** — 숫자를 그대로 두고
    /// 나이 캡션만 낡게 하는 것이 그때의 정직한 표시다(`AILimitReadFailure.noticeText` 주석).
    let notice: String?
    /// 플랜 라벨("plus"/"max"). 없으면 안 그린다.
    let planLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AILimitWindowLayout.cardRowSpacing) {
            header
            AILimitBar(
                percent: fiveHour.percent,
                floorOnly: fiveHour.floorOnly,
                height: AILimitWindowLayout.fiveHourBarHeight,
                tint: AILimitBar.tint(for: fiveHour.percent)
            )
            weeklyBlock
            if let notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.pending)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(AILimitWindowLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AILimitWindowLayout.cardCornerRadius, style: .continuous)
                .fill(CheckTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: AILimitWindowLayout.cardCornerRadius, style: .continuous)
                        .stroke(CheckTheme.border, lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            AIProviderTile(provider: provider, size: AILimitWindowLayout.tileSide)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // ★ 제공자를 **색으로만** 구분하지 않는다(위젯 틴트 모드가 색을 버린다 ·
                    //   `AIProviderLogo.swift` 머리말). 타일 옆에 항상 이름 글자가 있다.
                    Text(provider.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    if let planLabel {
                        Text(planLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CheckTheme.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(CheckTheme.fieldFill))
                            .lineLimit(1)
                    }
                }
                Text(captionText)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Text(fiveHour.valueText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(height: AILimitWindowLayout.headerRowHeight)
    }

    private var weeklyBlock: some View {
        VStack(alignment: .leading, spacing: AILimitWindowLayout.weeklyLabelSpacing) {
            Text("\(AILimitWindow.weekly.displayName) \(weekly.valueText)")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            AILimitBar(
                percent: weekly.percent,
                floorOnly: weekly.floorOnly,
                height: AILimitWindowLayout.weeklyBarHeight,
                tint: AILimitBar.tint(for: weekly.percent)
            )
        }
        .padding(.top, AILimitWindowLayout.weeklyBlockSpacing - AILimitWindowLayout.cardRowSpacing)
    }

    /// 머리 줄의 캡션. 리셋 시각을 알면 `오후 6:59 리셋`, 모르면 규칙이 준 나이 문구다.
    ///
    /// 왜 둘을 겹치지 않는가: 이 한 줄에 "3시간 전 · 오후 6:59 리셋"을 다 적으면 글 열이 숫자를 밀고
    /// (실측 84 + 63 = 147pt > 글 열 예산) 무엇보다 사용자가 두 시각을 헷갈린다. 리셋 시각이 있으면
    /// 그게 더 쓸모 있는 사실이고, 신선도는 숫자의 "이상" 과 바의 투명도가 이미 말한다.
    private var captionText: String {
        if let resetsAt = fiveHour.resetsAt, !fiveHour.freshness.isResetClaim {
            return "\(AILimitResetTimeText.text(resetsAt)) 리셋"
        }
        return fiveHour.captionText
    }
}

/// 리셋 시각을 `오후 6:59` 로 적는다(KST 기준 기기 시간대).
///
/// 초 이하를 쓰지 않는 이유: Claude 의 `resets_at` 에는 요청 시각의 잔여 분수(`…00.434051`)가 섞여 온다 —
/// 초를 적으면 같은 경계가 호출마다 다르게 보인다.
enum AILimitResetTimeText {
    static func text(_ date: Date, locale: Locale = Locale(identifier: "ko_KR"), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 창 본문

/// 창에 담기는 뷰. 카드 목록 하나뿐이라 스토어를 통째로 읽는다.
struct CheckAILimitsView: View {
    let store: AILimitStore
    /// 표시 기준 시각(주입 — 창의 분 틱이 넘긴다).
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: AILimitWindowLayout.headerSpacing) {
            header
            if store.listedProviders.isEmpty {
                emptyState
            } else {
                // 안내 줄이 붙어 카드가 자라도 잘리지 않게 목록은 스크롤에 담는다(레이아웃 주석 참고).
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AILimitWindowLayout.cardSpacing) {
                        ForEach(store.listedProviders, id: \.self) { provider in
                            AILimitProviderCard(
                                provider: provider,
                                fiveHour: store.display(provider: provider, window: .fiveHour, now: now),
                                weekly: store.display(provider: provider, window: .weekly, now: now),
                                notice: store.noticeText(provider: provider),
                                planLabel: store.bundle?.provider(provider)?.planLabel
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AILimitWindowLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CheckTheme.background)
        // ★ 창 루트의 툴팁 레이어. 없으면 `.checkTooltip` 이 시스템 툴팁으로 폴백한다(머리말).
        .checkTooltipLayer()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CheckTheme.accent)
            Text("AI 리밋")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
            Spacer(minLength: 6)
            Text(store.summary(now: now).captionText)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(height: AILimitWindowLayout.headerHeight)
    }

    /// 보여 줄 제공자가 없을 때. **빈 카드를 0% 로 지어내지 않는다.**
    private var emptyState: some View {
        Text("읽을 수 있는 AI 구독이 없습니다")
            .font(.caption)
            .foregroundStyle(CheckTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 창 컨트롤러

/// AI 리밋 창의 수명·표시·복구를 쥐는 단 하나의 지점.
///
/// 공개 진입점은 `show()` 하나다(팝오버 한 줄이 부른다). 배선은 앱 시작 때 `configure(store:)` 가 한 번 한다.
@MainActor
final class CheckAILimitsWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckAILimitsWindowController()

    /// 창 제목. CGWindowList 로 밖에서 셀 때의 표식이기도 하다(중복 창 검사).
    static let windowTitle = "AI 리밋"
    /// 자리 저장 키 = 창 식별자. **`MiniGameSpaceKey.standaloneWindowIDs` 가 읽는 값이다**(머리말 ★).
    static let frameAutosaveName = "check.aiLimitsWindow"

    /// 창을 물릴 재료. 스토어와 담을 뷰를 함께 묶는다 — 따로 두면 스토어만 물리고 콘텐츠는 플레이스홀더인
    /// 조합이 만들어진다(`CheckSettingsWindowController.Wiring` 과 같은 이유).
    struct Wiring {
        let store: AILimitStore
        let content: @MainActor (AILimitStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 지연 생성된 창. **닫아도 파괴하지 않는다**(스크롤 자리·크기가 매번 초기화되지 않게).
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). 실제 표시 여부는 창 서버가 아는 사실이고 `isVisible` 은 이 저장소에서
    /// 이미 한 번 거짓말했다 — 그래서 '의도'와 '사실'을 다른 이름으로 분리해 둔다.
    private(set) var isOpen = false
    var hasWindow: Bool { windowStorage != nil }
    private(set) var frameAutosaveActive = false
    /// 창을 열 때 불린다(스토어 갱신을 당기는 자리 — 컨트롤러가 스토어의 주기를 모르게 둔다).
    var onOpen: (() -> Void)?

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckAILimitsWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    func configure(
        store: AILimitStore,
        content: @escaping @MainActor (AILimitStore) -> AnyView = { store in
            AnyView(CheckAILimitsView(store: store))
        }
    ) {
        wiring = Wiring(store: store, content: content)
    }

    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        // `setFrameAutosaveName` 만으로는 **복원이 일어나지 않는다**(저장만 한다). 복원은 `setFrameUsingName` 이다.
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        // 반환값을 버리지 않는다 — 같은 이름이 이미 등록돼 있으면 false 를 돌려주고 자리가 조용히 저장되지 않는다.
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AILimitWindowLayout.defaultContentSize),
            // `.miniaturizable` 은 일부러 뺐다 — `LSUIElement` 앱은 Dock 타일이 없어 최소화한 창을 되돌리는
            // 길이 없다(`CheckSettingsWindowController.makeWindow` 와 같은 근거).
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = AILimitWindowLayout.minContentSize
        // 우리가 창을 붙들고 재사용하므로 닫힘에 딸린 해제가 끼면 다음 `show()` 가 해제된 창을 만진다.
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // ★ 앱 전체가 다크다(`CheckTheme`). 시스템 외관을 따라가면 밝은 테마에서 흰 배경 위 흰 글자가 나온다.
        window.appearance = NSAppearance(named: .darkAqua)
        // 지금 보고 있는 화면으로 온다. `.canJoinAllSpaces` 는 떠 있는 보조 패널의 계약이고 이 창의 것이 아니다.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0. 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    /// 창을 연다(멱등 — 여러 번 불러도 창은 하나다).
    ///
    /// **이 문은 팝오버를 닫지 않는다** — 활성화만으로 팝오버가 닫힌다는 통념은 v0.2.49 실측에서 거짓으로
    /// 판명됐다(`WindowTopAnchor.dismissMenuPopover` 주석). 팝오버에서 열 때는 **호출부**가 닫는다.
    func show() {
        guard let window else { return }
        onOpen?()
        // 테스트에서는 활성화하지 않는다 — 알파 0 은 창을 안 보이게 할 뿐 포커스는 못 막는다.
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        armStuckWindowWatchdog()
    }

    /// 창을 내린다(멱등). 창과 그 안의 상태는 남는다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
    }

    // MARK: 창이 화면에 못 올라갔을 때의 복구

    /// 주문 뒤 창이 실제로 떴는지 확인하기까지 두는 여유(초). 값의 근거는 `CheckTodoBoardController` 와 같다.
    static let stuckWindowCheckSeconds: Double = 0.5
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    private(set) var stuckWindowRebuilds = 0

    private func armStuckWindowWatchdog() {
        stuckWindowWatchdog?.cancel()
        let delay = stuckWindowCheckSeconds
        stuckWindowWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // 취소 검사가 없으면 cancel() 이 곧 즉시 실행이다(이 저장소의 다른 감시 태스크와 같은 계약).
            guard let self, !Task.isCancelled, self.isOpen,
                  let stuck = self.windowStorage, Self.isOnScreen(stuck) == false
            else { return }
            self.rebuildStuckWindow()
        }
    }

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 테스트 진입점이라 internal 이다 —
    /// 창 서버를 헤드리스에서 오염시킬 방법이 없으므로 복구 자체는 이 문으로만 검증할 수 있다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        // 델리게이트를 먼저 뗀다 — 아래 close() 의 windowWillClose 가 우리에게 오면 새 창을 세우는 도중
        // isOpen 이 false 로 뒤집힌다.
        old.delegate = nil
        old.contentView = nil
        // ★ 자동저장 이름을 반드시 놓아준다(머리말 — 안 풀면 재생성된 창이 자리를 영영 저장하지 못한다).
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        // ★ `orderOut(nil)` 이 아니라 `close()` 다 — AppKit 은 창을 close 할 때까지 자기 목록에서 붙들고 있어
        //   우리가 참조를 놓아도 창 서버 자원이 남는다(`CheckSettingsWindowController.rebuildStuckWindow` 실측).
        old.close()
        windowStorage = nil
        show()
    }

    /// 이 창이 지금 **실제로** 화면에 올라가 있는가를 창 서버에 직접 묻는다.
    /// 구현을 새로 쓰지 않고 `CheckTodoBoardController.isOnScreen` 을 그대로 부른다 — 이 판정이 두 벌이 되는
    /// 순간 둘 중 하나만 고쳐지는 날이 온다(그날 이 창은 v0.2.27 의 보드가 된다).
    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    /// 지금 창의 상태를 한 줄로(진단·사후 분석이 같은 문장을 본다).
    var diagnosticState: String {
        guard let windowStorage else { return "window=none isOpen=\(isOpen) rebuilds=\(stuckWindowRebuilds)" }
        let onScreen = Self.isOnScreen(windowStorage).map(String.init(describing:)) ?? "unknown"
        return "window=\(windowStorage.windowNumber) isOpen=\(isOpen) isVisible=\(windowStorage.isVisible)"
            + " onScreen=\(onScreen) rebuilds=\(stuckWindowRebuilds)"
    }
}
