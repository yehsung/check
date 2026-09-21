import AppKit
import SwiftUI
import CheckCore

// MARK: - 왜 직접 만든 NSWindow 인가 (버린 쪽: SwiftUI `Settings` scene)
//
// 후보는 둘이었다.
//
// (a) SwiftUI `Settings` scene — macOS 표준이고 ⌘, 가 공짜로 붙는다. **버렸다.** 대가가 이 앱의
//     구조와 정확히 어긋난다:
//     · `LSUIElement` 에이전트 앱에는 앱 메뉴가 없다. 그래서 "Settings…" 메뉴 항목도, 거기 붙는 ⌘,
//       도 사용자에게 도달하지 않는다 — 공짜라던 것이 실제로는 안 붙는다. 여는 경로는 어차피
//       우리가 만들어야 하고, 그 경로는 macOS 13/14 에서 이름이 갈린 비공개 셀렉터
//       (`showSettingsWindow:` / `showPreferencesWindow:`)를 `NSApp.sendAction` 으로 때리는 것뿐이다.
//       **버전에 따라 조용히 아무 일도 안 일어나는 호출**을 이 저장소의 창 계층에 들일 수는 없다.
//     · 창 객체를 우리가 쥐지 못한다. 그런데 이 저장소에서 창은 v0.2.27 에 **실제로 안 떴다**
//       (`orderFrontRegardless()` 가 조용히 실패했고 `NSWindow.isVisible` 은 true 라고 거짓말했다).
//       그때 유일하게 통한 복구는 **창을 버리고 다시 만드는 것**이었다(같은 창을 orderOut→orderFront
//       로 다시 태워도 살아나지 않았다). `Settings` scene 은 창을 버릴 손잡이를 주지 않는다 —
//       즉 그 사고가 재발하면 복구 수단이 0이다.
//     · 테스트 격리도 못 건다. `CheckPanelVisibility.isRunningTests` 는 우리가 만든 창에 알파를
//       거는 스위치인데, scene 이 만든 창에는 걸 자리가 없다. 사고 이력("테스트가 사장님 데스크톱을
//       도배했다")이 그대로 돌아온다.
//
// (b) 직접 만든 `NSWindow` — **골랐다.** 창을 우리가 쥐므로 위 셋이 전부 해결된다.
//     대가도 정직하게 적는다: ⌘, 를 우리가 붙여야 하고(아래 `CheckSettingsShortcut`),
//     창 기하·복원·다크 외관을 손으로 정해야 한다. 그 대가는 이미 이 저장소가 치러 본 값이다 —
//     `CheckTodoBoardWindow.swift` 의 패턴(지연 생성 · 멱등 열기 · 고착 감시자 · 재생성 상한)을
//     그대로 재사용한다.
//
// `NSPanel` 이 아니라 `NSWindow` 인 이유: 보드 패널은 '남의 앱 위에 떠 있는 보조 표면'이라
// borderless + nonactivating 이 맞지만, 설정은 **사용자가 잠깐 우리 앱 안에 들어와 있는 창**이다.
// 타이틀바(제목·닫기)와 리사이즈가 있어야 하고, 키보드로 조작되며, 다른 앱을 클릭해도 남아 있어야 한다.

// MARK: - 설정 창 컨트롤러

/// 설정 창의 수명·표시·복구를 쥐는 단 하나의 지점.
///
/// **공개 진입점은 `CheckSettingsWindowController.shared.show()` 하나다.** 팝오버(`CheckMenuView`)의
/// 기어 버튼이든 ⌘, 든 여기로 모인다. 그 파일들은 컨트롤러 인스턴스를 알 필요가 없다 — 스토어를
/// 물리는 일은 앱 시작 때 `configure(store:content:)` 가 한 번 한다.
@MainActor
final class CheckSettingsWindowController: NSObject, NSWindowDelegate {
    /// 앱이 쓰는 단 하나의 인스턴스. `init` 을 막지 않은 이유는 **헤드리스 검증**이다 —
    /// 전역만 두면 창 하나 재는 데도 앱 전역 상태를 오염시켜야 한다.
    static let shared = CheckSettingsWindowController()

    /// 창 제목. CGWindowList 로 밖에서 셀 때의 표식이기도 하다(중복 창 검사).
    static let windowTitle = "설정"

    /// 창 위치를 기억하는 키(UserDefaults `NSWindow Frame …`). 설정 창은 사용자가 자기 자리로 옮겨
    /// 두면 다음에도 거기서 열려야 한다 — 매번 화면 중앙으로 튀면 듀얼 모니터에서 특히 성가시다.
    static let frameAutosaveName = "check.settingsWindow"

    /// 기본 콘텐츠 크기. 폭은 뷰가 스스로 밝힌 `CheckSettingsView.preferredWidth`(설명 한 줄이 두 줄로
    /// 접히지 않는 최소치)에 창 여백을 더한 값이다 — **크기를 여기서 따로 정하면 뷰가 문구를 고칠 때마다
    /// 두 숫자가 조용히 어긋난다.** 높이는 지금 담긴 두 묶음이 잘리지 않는 값이고, 창은 리사이즈된다
    /// (v0.2.46: '미니게임 순위 공개' 행이 붙어 콘텐츠가 452pt 로 늘어 400 → 470 — RealtimeLinkTests 의 높이 계약이 이 값을 읽는다).
    ///
    /// v0.3.13: '소속 센터' 행(읽기 전용)이 붙어 콘텐츠가 **465pt** 가 됐다. 470 은 그대로 둔다 —
    /// 대신 **폭 하한을 올려서** 그 5pt 를 우연이 아니게 만들었다.
    ///
    /// 근거(실측 2026-09-12, 세 상태 loading/미지정/서울 × 별명 안내 세 종류 — 전부 같은 값이었다):
    /// `320 → 517pt · 360 → 504 · 370 → 491 · 375 → 478 · **380 이상 → 465 고정**`.
    /// 예전 폭 하한 320 에서는 설명 줄들이 두 줄로 접혀 콘텐츠가 517 까지 자랐고, 470 창에서 잘리는 것은
    /// **맨 아래 설정 항목 하나가 통째로** 였다(각주 한 줄이 아니다 — 그 각주는 2026-09-10 에 제보로 옮겼다).
    /// 한때 그 대응으로 470 → 520 을 넣었지만, 그러면 기본 폭에서 아래가 55pt 비고 계약 숫자만 흐려진다.
    /// 폭 하한을 preferredWidth 로 올리면 **어떤 폭에서도 465** 라 470 이 다시 진짜 계약이 된다.
    ///
    /// v0.3.22: '자동 근무 시작' 행(설명 두 줄)이 붙어 콘텐츠가 **533pt** 가 됐다(실측 2026-09-15, 폭 380 — 행 하나 +68).
    /// 창을 538 로 올렸다 — v0.3.13 과 같은 5pt 여유다. 폭이 넓어지면 줄바꿈이 줄어 콘텐츠는 같거나 작아지므로
    /// 폭 하한(preferredWidth)에서 잰 값이 곧 계약이다. 높이 테스트 셋(RealtimeLinkTests · V0313 · V0316)이 이 값을 읽는다.
    ///
    /// v0.3.23: '근무 시작·종료 단축키' 스위치 + 키캡 기록 행이 붙어 **624pt**(+91) 가 됐다. 이 묶음은 상태에 따라 아래에
    /// 안내 한 줄(macOS 단축키 겹침 · 등록 실패 · 기록 중 · 기록 거절 — 전부 한 줄)이 더 붙어 **643pt**(+19) 까지 자란다(실측 2026-09-15, 폭 380 — 안내가 있는 상태 전부 같은 값,
    /// 폭 400 이상에서는 630). 창 계약은 **그 가장 높은 상태**로 잡는다: 643 + 5 = **648**. 등록이 정상이면 아래가 24pt 비지만,
    /// 정상 상태(624)로 잡으면 겹침·실패 안내가 뜨는 바로 그 순간 맨 아래 '소속 센터' 행의 설명 줄이 잘린다 — 사용자가 설정을
    /// 고치러 들어온 순간에 화면이 깨지는 셈이다. V0316 이 가장 높은 상태를 이 값과 비교한다.
    ///
    /// v0.3.34: '내 정보'에 [차단한 사람] 행(맥 차단·신고)이 붙어 가장 높은 상태가 **698pt**(+55 — 구분선 + 간격 + 두 줄 행,
    /// 실측 2026-09-20 폭 380)가 됐다. 같은 5pt 여유로 **703**. 목록 자체는 이 본문에 펼치지 않는다 — 행을 누르면 본문 자리에
    /// 목록이 서서(`CheckBlockedPeopleSettingsPage`) 사람 수가 이 계약을 흔들지 않는다. 저장된 옛 자리(648)로 열리는 사람을 위해
    /// 열 때 모자라면 채운다(`growForContentIfNeeded`).
    ///
    /// v0.3.36: '내 정보'에 [프로필 사진] 행(기본 캐릭터로 되돌리기)이 붙어 전체 렌더가 **753pt**(+55 — 구분선 + 간격 +
    /// 행, 실측 2026-09-21 폭 380)가 됐다. 그런데 그 행은 **누르면 자란다**: 확인 안내와 "파일이 남았어요" 문구가
    /// 카드 안쪽 폭(328)에서 두 줄로 접혀 46 → 59pt, 즉 **+13pt**(`AvatarRemovalSettingsRow.maxExtraHeight`).
    /// 확인 단계는 전체 렌더에 절대 안 나타나므로(누른 뒤에만 존재한다) 가장 높은 상태는 753 + 13 = **766pt** 다.
    /// 같은 5pt 여유로 **771**. V0336AvatarRemovalTests 가 네 상태를 실제 폭으로 그려 이 값을 되묻는다.
    static let defaultContentSize = NSSize(width: CheckSettingsView.preferredWidth + 40, height: 771)
    /// 최소 크기. 폭은 뷰가 선언한 하한(`minWidth: Self.preferredWidth`)을 그대로 따른다 — 여기에 뷰가
    /// 모르는 숫자를 새로 적으면 그 순간 두 하한이 갈리고, 갈리는 쪽이 위 높이 계약을 깬다(바로 위 실측표).
    static let minContentSize = NSSize(width: CheckSettingsView.preferredWidth, height: 260)

    /// 창을 물릴 재료. **스토어와 콘텐츠를 함께 묶는다** — 따로 두면 스토어만 물리고 콘텐츠는
    /// 플레이스홀더인 채로 배포되는 조합이 만들어진다(그러면 사용자는 빈 창을 본다).
    struct Wiring {
        let store: WorkTimerStore
        /// 창에 담을 뷰. 기본값이 `CheckSettingsView` 이고, 주입 지점을 남겨 둔 이유는 **창을 뷰 없이
        /// 재기 위해서**다 — 창 계층 검증(뜨는가·하나인가·다시 뜨는가)이 설정 화면의 내용 변화에
        /// 끌려다니면 안 된다.
        let content: @MainActor (WorkTimerStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 지연 생성된 창. **닫아도 파괴하지 않는다** — 다시 여는 데 드는 비용(호스팅 뷰 재구성)도 비용이지만,
    /// 사용자가 스크롤해 둔 자리와 창 크기가 매번 초기화되는 게 더 나쁘다.
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). 실제 표시 여부는 창 서버가 아는 사실이고 `isVisible` 은
    /// 이 저장소에서 이미 한 번 거짓말했다 — 그래서 '의도'와 '사실'을 다른 이름으로 분리해 둔다.
    private(set) var isOpen = false

    /// 창을 이미 만들었는가(헤드리스 검증 지점). `window` 를 읽으면 그 순간 만들어지므로 이 문으로만 묻는다.
    var hasWindow: Bool { windowStorage != nil }

    /// 지금 창이 실제로 자리를 저장하고 있는가(헤드리스 검증 지점). false 면 다음에 열 때 창이 중앙으로
    /// 되돌아간다 — 눈에 잘 안 띄는 퇴행이라 값으로 붙들어 둔다.
    private(set) var frameAutosaveActive = false

    /// 이 인스턴스의 고착 확인 지연(초). 프로덕션은 언제나 `Self.stuckWindowCheckSeconds`.
    /// **테스트만** 짧게 주입한다(`CheckTodoBoardController.stuckPanelCheckSeconds` 와 같은 이유 —
    /// 주입 지점이 없으면 감시자를 통째로 지워도 스위트가 초록이다).
    let stuckWindowCheckSeconds: Double

    /// 설정 화면의 단축키 기록(v0.3.23). 창이 닫히면 **여기서** 기록을 끝낸다 — 기본값은 설정 화면이 쓰는 것과 같은
    /// `.shared` 이고, 테스트는 자기 인스턴스를 넣어 전역 모니터 상태를 흔들지 않는다.
    let workShortcutRecording: WorkShortcutRecordingSession

    init(
        stuckWindowCheckSeconds: Double = CheckSettingsWindowController.stuckWindowCheckSeconds,
        workShortcutRecording: WorkShortcutRecordingSession = .shared
    ) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        self.workShortcutRecording = workShortcutRecording
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 스토어와 담을 뷰를 물린다.
    ///
    /// 두 번 불러도 안전하다(마지막 배선이 이긴다). 다만 **이미 만들어진 창은 새 배선을 따라가지 않는다** —
    /// 콘텐츠를 갈아 끼우려면 창을 버려야 하는데, 배선이 실행당 1회인 이상 그 경로는 죽은 코드다.
    func configure(
        store: WorkTimerStore,
        content: @escaping @MainActor (WorkTimerStore) -> AnyView = { store in
            // 뷰는 자기 폭만 정하고 높이는 내용만큼만 차지한다(그게 뷰의 올바른 계약이다). 창은 그보다
            // 큰 사각형이므로 **채우는 일은 창 쪽이 한다** — 안 하면 리사이즈했을 때 아래쪽에 시스템
            // 기본 회색 판이 드러나 창 절반이 다른 앱처럼 보인다.
            AnyView(
                CheckSettingsView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(CheckTheme.background)
            )
        }
    ) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    /// 창(첫 `show()` 에 생성). 설정을 한 번도 안 여는 실행이 대부분이라 앱 시작 시 만들지 않는다.
    /// **배선 전이면 nil 이다** — 스토어 없이 만든 창은 담을 게 없다.
    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        // 저장된 자리가 있으면 거기서, 없으면 화면 중앙에서 연다. `setFrameAutosaveName` 만으로는
        // **복원이 일어나지 않는다**(저장만 한다) — 복원은 `setFrameUsingName` 이 한다.
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        // 반환값을 버리지 않는다. `setFrameAutosaveName` 은 **같은 이름이 이미 등록돼 있으면 false 를
        // 돌려주고 아무 일도 하지 않는다** — 그 경우 창 자리가 조용히 저장되지 않는다(재생성 경로에서
        // 옛 창의 등록을 안 풀면 정확히 그 일이 난다. 아래 `rebuildStuckWindow` 참고).
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 설정 창을 만든다. 값 하나하나가 이 앱의 형태(메뉴바 전용 · 다크 고정)에서 나온다.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultContentSize),
            // `.miniaturizable` 은 **일부러 뺐다.** `LSUIElement` 앱은 Dock 타일이 없어서, 최소화한
            // 설정 창을 되돌리는 길이 Dock 최소화 영역을 뒤지는 것뿐이다("설정 창이 사라졌다").
            // 닫기(창은 살아 있다)와 다시 열기가 이 앱에서 최소화의 자리를 이미 대신한다.
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = minContentSize
        // 우리가 창을 붙들고 재사용하므로(닫기 = orderOut/close 후에도 보존) 닫힘에 딸린 해제가 끼면
        // 다음 `show()` 가 해제된 창을 만진다.
        window.isReleasedWhenClosed = false
        // 다른 앱을 클릭해도 설정 창은 남아야 한다(NSWindow 기본값이 false 지만 계약이므로 명시한다).
        window.hidesOnDeactivate = false
        // ★ 앱 전체가 다크다(`CheckTheme`). 시스템 외관을 따라가면 밝은 테마에서 흰 배경 위에 흰 글자가
        //   나오는 조합이 생긴다 — 보드 패널이 `.darkAqua` 로 못 박은 것과 같은 이유.
        window.appearance = NSAppearance(named: .darkAqua)
        // 설정은 '지금 보고 있는 화면'으로 와야 한다. `.canJoinAllSpaces`(보드 패널의 값)를 쓰면 설정 창이
        // 모든 Space 를 따라다니는 유령이 된다 — 그건 떠 있는 보조 패널의 계약이지 설정 창의 계약이 아니다.
        // `.fullScreenAuxiliary` 는 남의 앱이 전체화면일 때도 설정이 뜨게 한다(그때 못 뜨면 탈출로가 없다).
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 레벨은 기본(.normal)이다. 설정 창이 남의 창 위에 항상 떠 있을 이유가 없다.
        //
        // 테스트 실행일 때만 알파 0(프로덕션은 1). 판정은 `CheckPanelVisibility` 한 곳뿐이다 —
        // `apply(to:)` 를 부르지 않는 이유는 그 함수 시그니처가 `NSPanel` 전용이고 그 파일은 우리 소유가
        // 아니어서다. **같은 스위치(`isRunningTests`)를 지나는 것이 계약이고, 그 계약은 지킨다.**
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 설정 창을 연다(멱등 — **여러 번 불러도 창은 하나다**. 이미 떠 있으면 앞으로 가져오기만 한다).
    ///
    /// `NSApp.activate()` 가 필요한 이유: 이 앱은 `LSUIElement` 라 활성 앱이 되는 일이 거의 없다.
    /// 활성화 없이 `makeKeyAndOrderFront` 만 하면 창이 **다른 앱 뒤에 뜬 채로** 키만 가져가, 사용자
    /// 눈에는 "눌렀는데 아무 일도 안 일어난다"가 된다.
    ///
    /// **단, 테스트에서는 활성화하지 않는다.** 알파 0 은 창을 안 보이게 할 뿐 포커스는 못 막는다 —
    /// 스위트를 돌릴 때마다 사장님이 쓰던 앱에서 포커스가 튀는 건 창이 보이는 것만큼 나쁘다.
    ///
    /// ★ **이 문은 팝오버를 닫지 않는다.** 활성화만으로 팝오버가 닫힌다는 오랜 통념은 v0.2.49 실측에서
    ///   거짓으로 판명됐다(표는 `WindowTopAnchor.dismissMenuPopover` 주석). 팝오버에서 열 때는
    ///   **호출부**(`CheckMenuSideRail` 의 [설정] 칸)가 닫는다 — ⌘, 로 열 때는 닫을 팝오버가 없거나
    ///   사용자가 일부러 열어 둔 것이라, 그 판단을 여기 넣으면 두 경로의 뜻이 갈린다.
    func show() {
        guard let window else { return }
        growForContentIfNeeded(window)
        // 열 때마다 전역 단축키를 다시 판정한다(v0.3.23). macOS 단축키와 겹쳐 .conflict 인 사람이 시스템 설정에서 그 단축키를
        // 끄고 돌아와 설정을 다시 열면 여기서 풀린다. 단축키 행의 onAppear 만으로는 안 된다 — 이 창은 닫아도(orderOut) 뷰가
        // 창에 붙은 채라 다시 열 때 onAppear 가 오지 않는다(실측 2026-09-15, 알파 0 테스트 창: show → close → show →
        // performClose → show 에서 onAppear 1회 · onDisappear 0회).
        wiring?.store.requestWorkShortcutReapply()
        // 사진 되돌리기의 2단 확인·결과 한 줄도 **열 때 접는다**(v0.3.36). 닫을 때만 접으면 닫기를 거치지 않은
        // 경로(창 재생성 · 앱이 창을 잃었다 되찾는 복구)에서 빨간 [되돌리기]가 무장된 채로 사용자를 맞는다.
        wiring?.store.resetAvatarRemovalRow()
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        armStuckWindowWatchdog()
    }

    /// 관리자에게만 보이는 캐릭터 선택 행이 붙으면 콘텐츠가 **855pt** 까지 자란다(`CheckSettingsView.adminContentHeight`,
    /// v0.3.36 — 단축키 안내 한 줄 + 사진 되돌리기 확인이 함께 열린 가장 높은 상태). 기본 창은 771pt 라 그대로 열면 맨 아래 행이 잘린다.
    ///
    /// **왜 창을 만들 때가 아니라 열 때인가**: `ultraUnlimited` 는 서버가 정하고 세션 동기화로 **늦게 도착한다**.
    /// 창 생성 시점에 읽으면 첫 실행에서는 아직 false 라 기본 높이로 굳는다.
    ///
    /// **v0.3.34 부터 관리자가 아니어도 채운다**: 이 창은 자리를 기억한다(`setFrameUsingName`). 옛 버전에서 648pt 로 저장된 창이
    /// 그대로 열리면 새로 붙은 맨 아래 [차단한 사람] 행이 잘린다 — 행이 붙을 때마다 사용자가 창을 손으로 늘려야 보이는 셈이다.
    /// 그래서 일반 사용자는 기본 높이(`defaultContentSize`)까지, 관리자는 관리자 높이까지 **모자랄 때만** 채운다.
    ///
    /// **왜 키우기만 하는가**: 사용자가 직접 줄여 둔 창을 우리가 매번 되돌리면 그 조작이 무의미해진다.
    /// 저장된 자리(`setFrameAutosaveName`)보다 우리가 세게 굴면 안 된다 — 모자랄 때만 채운다.
    private func growForContentIfNeeded(_ window: NSWindow) {
        let needed = wiring?.store.ultraUnlimited == true
            ? CheckSettingsView.adminContentHeight
            : Self.defaultContentSize.height
        guard window.contentLayoutRect.height < needed else { return }
        var size = window.frame.size
        size.height += needed - window.contentLayoutRect.height
        var frame = window.frame
        // 타이틀바가 위에 있으므로 **위쪽을 고정하고 아래로** 늘린다 — 그래야 창이 화면 위로 튀지 않는다.
        frame.origin.y -= size.height - frame.size.height
        frame.size = size
        window.setFrame(frame, display: false)
    }

    /// 설정 창을 내린다(멱등). 창과 그 안의 상태는 남는다 — 다시 열면 같은 자리에 같은 크기로 선다.
    /// **앱은 계속 돈다**(메뉴바 전용 앱이다 — 이 창은 앱의 마지막 창일 뿐 앱의 수명이 아니다).
    func close() {
        endWorkShortcutRecording()
        // [차단한 사람] 쪽을 보던 채 닫아도 다시 열면 설정 본문부터 보인다(v0.3.34).
        wiring?.store.closeBlockedPeopleSettings()
        // 사진 되돌리기 확인을 연 채 닫아도 다음에 열면 평소 상태다(v0.3.36) — 이 창은 닫아도 뷰가 살아 있다.
        wiring?.store.resetAvatarRemovalRow()
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
    }

    /// 사용자가 타이틀바의 빨간 점을 눌렀을 때. `close()` 를 우리가 부른 게 아니므로 여기서 의도를 맞춘다 —
    /// 안 맞추면 `isOpen` 이 true 로 남아 다음 `show()` 가 "이미 열려 있다"고 착각한다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        endWorkShortcutRecording()
        wiring?.store.closeBlockedPeopleSettings()
        wiring?.store.resetAvatarRemovalRow()
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
    }

    /// 창이 내려가면 단축키 기록을 끝낸다(v0.3.23). **이 문이 없으면 전역 단축키가 앱을 다시 켤 때까지 멈출 수 있다** —
    /// 기록 중에는 전역 등록이 내려가 있는데, 이 창은 닫아도 뷰가 살아 있어(orderOut) `onDisappear` 가 안 오는 경로가 있다.
    /// 모니터 제거(세션)와 깃발 내리기(스토어)를 둘 다 한다: 세션이 다른 스토어로 시작됐거나 한 번도 안 시작됐어도
    /// 이 창의 스토어는 반드시 기록 중이 아니게 된다.
    private func endWorkShortcutRecording() {
        workShortcutRecording.end()
        wiring?.store.setRecordingWorkShortcut(false)
    }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구

    /// 주문 뒤 창이 실제로 떴는지 확인하기까지 두는 여유(초).
    /// 값의 근거는 `CheckTodoBoardController.stuckPanelCheckSeconds` 와 같다(실측 ~50ms 의 10배).
    static let stuckWindowCheckSeconds: Double = 0.5
    /// 한 실행에서 허용하는 재생성 횟수. 상한이 없으면 창 서버가 계속 거부하는 극단에서 무한 루프가 된다.
    static let maxStuckWindowRebuilds = 3

    /// 이번 열기에 대한 확인 감시(열 때마다 갈아 끼운다).
    private var stuckWindowWatchdog: Task<Void, Never>?
    /// 이 실행에서 실제로 다시 만든 횟수(헤드리스 검증 지점).
    private(set) var stuckWindowRebuilds = 0

    /// **`makeKeyAndOrderFront` 도 조용히 실패할 수 있다.** v0.2.27 의 할 일 보드가 정확히 그랬고
    /// (`orderFrontRegardless()` 뒤에도 창이 어느 Space 에도 없었다. `isVisible` 은 true 였다),
    /// 그때 통한 복구는 **창을 버리고 새로 만드는 것** 하나뿐이었다. 설정 창도 같은 창 서버 위에 산다.
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

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다.
    ///
    /// 잃는 것: 창 안의 SwiftUI `@State`(설정 창은 값의 주인이 아니라 스토어를 비추는 표면이라
    /// 잃을 것이 사실상 없다)와 이번 세션의 리사이즈(자리·크기는 `frameAutosaveName` 이 되살린다).
    ///
    /// 테스트 진입점이라 internal 이다 — 창 서버를 헤드리스에서 오염시킬 방법이 없으므로 복구 자체는
    /// 이 문으로만 검증할 수 있다.
    func rebuildStuckWindow() {
        // 상한은 **여기** 하나뿐이다(감시자 쪽에도 두면 언젠가 두 판정이 갈린다).
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        // 델리게이트를 먼저 뗀다 — 아래 `close()` 가 `windowWillClose` 를 부르는데, 그게 우리에게 오면
        // 새 창을 세우는 도중에 `isOpen` 이 false 로 뒤집힌다.
        old.delegate = nil
        // 호스팅 뷰가 스토어/클로저를 도로 잡는 사슬을 끊는다(옛 창이 실제로 사라지도록).
        old.contentView = nil
        // ★ 자동저장 이름을 **반드시 놓아준다.** AppKit 은 이름별로 창을 전역 표에 등록해 두고, 같은
        //   이름으로 두 번째 창이 등록하려 하면 `setFrameAutosaveName` 이 false 를 돌려주고 무시한다.
        //   안 풀면 재생성된 창은 자리를 영영 저장하지 못한다(사용자 눈에는 "설정 창을 옮겨 놨는데
        //   가끔 중앙으로 돌아간다" — 원인을 추적할 수 없는 종류의 신고다).
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        // ★ `orderOut(nil)` 이 아니라 `close()` 다. **실측**: 재생성 뒤 `orderOut` 만 한 옛 창이
        //   1.5초 뒤에도 CGWindowList 에 그대로 남아 있었다(#4245 offscreen, 새 창 #4247 과 나란히).
        //   AppKit 은 창을 `close()` 할 때까지 자기 창 목록에서 붙들고 있어서, 우리가 참조를 놓아도
        //   NSWindow 가 해제되지 않고 창 서버 자원이 남는다 — 상한이 3이라 새는 양은 작지만,
        //   "못 뜨는 창을 버린다"는 이 함수의 존재 이유가 절반만 이뤄진 상태다.
        //   `isReleasedWhenClosed = false` 이므로 `close()` 가 해제까지 하지는 않는다(우리 참조가
        //   마지막이고, 바로 아래에서 그 참조를 놓는다).
        old.close()
        windowStorage = nil
        show()
    }

    /// 이 창이 지금 **실제로** 화면에 올라가 있는가를 창 서버에 직접 묻는다.
    ///
    /// 구현을 새로 쓰지 않고 `CheckTodoBoardController.isOnScreen` 을 그대로 부른다. 그 함수는 이름만
    /// 보드에 붙어 있을 뿐 내용은 순수한 창 서버 질의이고, **이 판정이 두 벌이 되는 순간 둘 중 하나만
    /// 고쳐지는 날이 온다**(그날 설정 창은 v0.2.27 의 보드가 된다). 옮겨 오지 않은 이유는 그 파일이
    /// 이 작업의 소유가 아니어서다.
    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    /// 지금 창의 상태를 한 줄로. 진단(`CheckSettingsWindowProbe`)과 사후 분석에서 **같은 문장**을 본다.
    var diagnosticState: String {
        guard let windowStorage else { return "window=none isOpen=\(isOpen) rebuilds=\(stuckWindowRebuilds)" }
        let onScreen = Self.isOnScreen(windowStorage).map(String.init(describing:)) ?? "unknown"
        let f = windowStorage.frame
        return "window=\(windowStorage.windowNumber) isOpen=\(isOpen) isVisible=\(windowStorage.isVisible)"
            + " onScreen=\(onScreen) alpha=\(windowStorage.alphaValue) autosave=\(frameAutosaveActive)"
            + " frame=\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))"
            + " rebuilds=\(stuckWindowRebuilds)"
    }
}

// MARK: - ⌘, 단축키

/// ⌘, 로 설정 창을 여는 로컬 키 모니터.
///
/// **왜 메인 메뉴가 아닌가**: `LSUIElement` 앱은 메뉴바를 소유하지 않는다. `NSApp.mainMenu` 에 항목을
/// 꽂아도 사용자에게 보이지 않고, 이 앱은 SwiftUI `MenuBarExtra` 만 있어 메뉴를 세우는 자리 자체가 없다.
///
/// **로컬 모니터의 범위는 우리 앱뿐이다** — 다른 앱의 ⌘, 는 애초에 여기 오지 않는다(그래서 남의 앱
/// 설정 단축키를 훔치는 사고가 구조적으로 불가능하다). 실제로 닿는 순간은 팝오버가 열려 있을 때와
/// 설정 창이 떠 있을 때다. 삼키는 것은 **정확히 ⌘,(다른 수식키 없음)** 하나뿐이고 나머지는 전부
/// 그대로 흘려보낸다 — 여기서 잘못 삼키면 팝오버의 텍스트 입력이 통째로 죽는다.
@MainActor
enum CheckSettingsShortcut {
    private static var token: Any?

    /// 걸려 있는가(헤드리스 검증 지점).
    static var isInstalled: Bool { token != nil }

    /// ⌘, 를 건다(멱등). 수명은 앱과 같다 — 뗄 이유가 생기는 경로가 없어서 `remove()` 는 정리용이다.
    static func install(action: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard matches(event) else { return event }
            MainActor.assumeIsolated { action() }
            return nil
        }
    }

    static func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    /// ⌘, 인가. `charactersIgnoringModifiers` 로 보는 이유는 자판 배열 때문이다 — 한글 입력 상태의
    /// `characters` 는 조합 중인 글자를 돌려줄 수 있다.
    static func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return false }
        return event.charactersIgnoringModifiers == ","
    }
}

// MARK: - 창이 실제로 떴는지 밖에서 재기 위한 진단 문

/// 실행 중인 앱에 `show`/`close` 를 넣어 보고 창 상태를 stdout 으로 돌려주는 진단 모드.
///
/// **왜 프로덕션에 두는가**: 이 저장소에서 창은 "코드가 맞아 보이는 것"으로는 검증되지 않는다 —
/// v0.2.27 은 헤드리스 973개가 전부 초록인 채 실사용자가 깨졌고, 진실은 `CGWindowListCopyWindowInfo`
/// 로만 나왔다. 그 실측을 하려면 **실행 중인 앱을 밖에서 여닫을 수 있어야** 한다. 이 문이 없으면
/// 다음 사람은 같은 실측을 할 수 없고, 결국 "빌드가 통과했으니 됐다"로 되돌아간다.
///
/// 인자(`--check-settings-probe`)가 없으면 **아무 일도 하지 않는다**. 스레드도 만들지 않는다.
enum CheckSettingsWindowProbe {
    static let argument = "--check-settings-probe"

    /// 인자가 있으면 stdin 명령 루프를 띄우고 true.
    /// 명령: `show` / `close` / `redbutton`(타이틀바 빨간 점과 같은 길) / `rebuild`(고착 복구) / `state` / `quit`.
    @discardableResult
    static func startIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard arguments.contains(argument) else { return false }
        let thread = Thread {
            while let line = readLine(strippingNewline: true) {
                let command = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else { continue }
                DispatchQueue.main.async { MainActor.assumeIsolated { run(command) } }
            }
        }
        thread.stackSize = 1 << 19
        thread.start()
        return true
    }

    @MainActor
    private static func run(_ command: String) {
        let controller = CheckSettingsWindowController.shared
        switch command {
        case "show": controller.show()
        case "close": controller.close()
        case "redbutton":
            // 사용자가 실제로 쓰는 닫기 경로(타이틀바 빨간 점)는 `close()` 가 아니라 `performClose(_:)` 다.
            // 컨트롤러에 진단용 메서드를 새로 뚫지 않고 창을 밖에서 찾아 그대로 누른다 —
            // 그래야 `windowWillClose` 델리게이트까지 진짜 순서대로 지난다.
            NSApp.windows
                .first { $0.identifier?.rawValue == CheckSettingsWindowController.frameAutosaveName }?
                .performClose(nil)
        case "rebuild": controller.rebuildStuckWindow()
        case "state": break
        case "quit":
            print("PROBE quit pid=\(ProcessInfo.processInfo.processIdentifier)")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        default:
            print("PROBE unknown=\(command)")
            fflush(stdout)
            return
        }
        print("PROBE \(command) pid=\(ProcessInfo.processInfo.processIdentifier) \(controller.diagnosticState)")
        fflush(stdout)
    }
}
