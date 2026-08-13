import AppKit
import Observation
import SwiftUI

// MARK: - 패널

/// 투두 보드가 사는 패널. **`canBecomeKey` 오버라이드가 이 타입의 존재 이유 전부다.**
///
/// 보드 패널은 캐릭터 패널과 같은 `[.borderless, .nonactivatingPanel]` 조합을 쓰는데, 이 조합은
/// 기본 구현에서 키 윈도우가 **되지 못한다**(NSWindow 의 기본 `canBecomeKey` 는 타이틀바가 있거나
/// 리사이즈 가능한 창에만 true 를 준다). 그 상태로 보드를 띄우면 화면에는 보이는데 텍스트필드에
/// 캐럿이 서지 않아 **글자를 한 자도 넣을 수 없다**(실측). 캐릭터 패널은 클릭 통과 전용이라 이 문제가
/// 아예 없었지만, 보드는 '적는 것'이 존재 이유라 여기서만 뒤집는다.
///
/// `.nonactivatingPanel` 은 그대로 둔다 — 키가 되어도 **앱을 활성화하지 않는다**. 즉 사용자가 쓰던
/// 앱의 창은 계속 앞에 있고, 우리 보드만 키를 가져가 입력을 받는다.
final class TodoBoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 배치(순수 함수)

/// 캐릭터(앵커) 옆에 보드를 놓는 규칙. 화면·창에 손대지 않는 **값 계산만** 하므로 헤드리스로 전부 검증된다.
enum TodoBoardAnchor {
    /// 보드 크기(pt). 고정 — 내용이 늘어도 창이 자라지 않고 내부에서 스크롤한다.
    static let boardSize = NSSize(width: 300, height: 400)
    /// 캐릭터와 보드 사이 간격(pt).
    static let gap: CGFloat = 10

    /// 캐릭터 프레임(`anchor`, 스크린 좌표)과 그 화면의 `visible`(visibleFrame)로 보드 프레임을 계산한다.
    ///
    /// 규칙:
    /// · 기본은 **캐릭터 왼쪽**(보드 maxX = anchor.minX - gap), **상단 정렬**(보드 maxY = anchor.maxY).
    ///   캐릭터는 기본이 화면 우상단이라 왼쪽이 거의 항상 넉넉하고, 상단 정렬이면 보드가 메뉴바 바로 아래에서
    ///   아래로 자라 시선 이동이 짧다.
    /// · 왼쪽이 화면 밖으로 나가면 **오른쪽으로 뒤집는다**(보드 minX = anchor.maxX + gap).
    /// · 뒤집어도 안 들어가면 **뒤집지 않고 화면 안으로 클램프한다**. 보드가 잘려 글자를 못 읽는 것보다
    ///   캐릭터를 잠깐 가리는 편이 낫다(캐릭터는 장식이고 보드는 내용이다).
    /// · 세로는 클램프만 한다. **아래→위 뒤집기는 하지 않는다** — 위로 뒤집으면 보드가 캐릭터 위로 튀어올라
    ///   메뉴바를 향해 자라는 꼴이 되어, 같은 클릭에 보드가 위/아래를 오가는 정신없는 배치가 된다.
    static func frame(anchor: NSRect, in visible: NSRect) -> NSRect {
        let size = boardSize
        var x = anchor.minX - gap - size.width
        if x < visible.minX {
            let flipped = anchor.maxX + gap
            // 뒤집은 자리가 **온전히** 들어갈 때만 뒤집는다. 어차피 잘릴 자리로 옮기면 왼쪽 클램프보다
            // 나을 게 없으면서 위치만 오락가락한다.
            if flipped + size.width <= visible.maxX {
                x = flipped
            }
        }
        let y = anchor.maxY - size.height
        return NSRect(origin: clamped(NSPoint(x: x, y: y), size: size, in: visible), size: size)
    }

    /// 프레임 전체가 `visible` 안에 들도록 origin 을 당긴다. 보드가 화면보다 큰 극단에서는 좌하단 정렬을
    /// 우선한다(`CheckOverlayController.clampedOrigin` 과 같은 계약 — 두 창이 다르게 잘리면 안 된다).
    private static func clamped(_ origin: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }
}

// MARK: - ⌥ + 스크롤(순수 누적기)

/// 스크롤 이벤트 한 개에서 **판단에 필요한 네 가지만** 떼어 낸 값.
///
/// 왜 구조체로 가르는가: `NSEvent` 는 합성해도 오프스크린에서 우리가 보는 필드(창·페이즈·정밀 여부)가
/// 비어 오거나 아예 만들어지지 않아 단언에 쓸 수 없다(실측 — `NSEvent.mouseEvent`/`otherEvent` 로는
/// `.scrollWheel` 타입 자체를 만들 수 없다). 그래서 이벤트에서 값만 뽑아 내고, **누적 규칙 전체는
/// 이 값 위에서** 헤드리스로 검증한다.
struct TodoBoardScrollSample: Equatable, Sendable {
    /// `NSEvent.scrollingDeltaY`. 부호는 손가락 방향이 아니라 **문서가 움직이는 방향**이다(`isInverted` 참고).
    var deltaY: Double
    /// `hasPreciseScrollingDeltas`. true = 트랙패드·매직마우스(연속 델타), false = 걸림쇠 있는 휠(이산).
    var isPrecise: Bool
    /// `isDirectionInvertedFromDevice`(="자연스러운 스크롤" 켜짐). true면 `deltaY` 가 **손가락 움직임의 반대**다.
    var isInverted: Bool
    /// 손을 뗀 뒤 관성으로 흘러오는 이벤트인가(`momentumPhase != []`).
    var isMomentum: Bool
}

extension TodoBoardScrollSample {
    /// 실제 이벤트에서 값만 뽑는다. **여기에는 판단이 없다** — 판단이 섞이는 순간 그 조각만 검증 밖으로 나간다.
    init(event: NSEvent) {
        self.init(
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            isInverted: event.isDirectionInvertedFromDevice,
            isMomentum: event.momentumPhase != []
        )
    }
}

/// ⌥+스크롤 델타를 모아 **투명도 스텝 수**로 바꾸는 누적기. 창도 이벤트도 모르는 순수 값 로직이다.
///
/// 왜 누적이 필요한가: 트랙패드의 `scrollingDeltaY` 는 한 번 쓸어도 잘게 수십 번 온다. 매 이벤트마다
/// `nudge(by: step)` 을 부르면 손가락을 조금만 움직여도 0.20↔0.95 를 순식간에 왕복한다(스텝 15개짜리 레일이다).
/// 거리를 모아 문턱을 넘을 때만 한 스텝을 내보내면 "한 틱 = 한 스텝"으로 읽힌다.
struct TodoBoardScrollOpacityGesture {
    /// 트랙패드에서 **편하게 한 번 쓸었을 때** 쌓이는 델타(pt). 정밀 델타는 대체로 '문서가 움직이는 거리'와
    /// 같은 단위라 한 번 쓸기는 200~300pt 다. 감도의 기준점은 이 숫자 하나뿐이고 나머지는 전부 여기서 나온다.
    static let sweepDistance: Double = 240

    /// 레일(0.20~0.95)을 몇 스텝에 훑는가. **설정 모델이 정한다** — 여기서 다시 세지 않는다.
    static var railSteps: Double {
        (TodoBoardAppearance.maxOpacity - TodoBoardAppearance.minOpacity) / TodoBoardAppearance.step
    }

    /// 한 스텝을 밀어내는 누적 거리(pt). **한 번 쓸기 = 레일의 절반**이 되도록 역산한다.
    ///
    /// 왜 상수로 박지 않는가: 스텝 크기(`TodoBoardAppearance.step`)는 설정 모델의 소유고 실제로 바뀐다.
    /// 거리를 박아 두면 스텝이 잘아지는 순간 같은 손동작이 몇 배로 굼떠진다("한참 굴려도 안 움직인다").
    /// 감도의 계약은 거리가 아니라 **"한 번 쓸어서 어느 만큼 가는가"** 라야 스텝 크기와 무관하게 유지된다.
    /// 절반인 이유는 양끝 어느 쪽에서 시작해도 두 번이면 반대 끝에 닿으면서, 목록을 훑던 손버릇 그대로
    /// 한 번 미끄러졌을 때 값이 끝까지 튀지는 않는 지점이기 때문이다.
    /// 바닥값 8pt 는 한 틱이 손끝에 느껴지는 하한이다(그 아래면 조절이 아니라 미끄럼이 된다).
    static var stepDistance: Double { max(8, sweepDistance / (railSteps / 2)) }

    /// 한 이벤트가 낼 수 있는 최대 스텝 수(= 레일의 절반). 방어의 진짜 목적은 감도가 아니라
    /// **`Int` 변환 붕괴**다 — 드라이버가 튀는 큰 델타를 흘리는 일이 실제로 있고(설정 모델이 `nudge` 에서
    /// 무한대를 버리는 것과 같은 이유), 나눗셈 결과를 그대로 `Int(_:)` 에 넣으면 표현 범위를 넘는 순간 크래시다.
    static var maxStepsPerEvent: Double { max(4, (railSteps / 2).rounded()) }

    /// 아직 한 스텝에 못 미친 잔여 거리(pt). 부호는 '위로'가 양수다.
    private var accumulated: Double = 0

    /// 보드를 열고 닫을 때 잔여를 턴다. 어제 굴리다 만 20pt 가 남아 있으면 다음에 여는 순간
    /// 손가락을 4pt 만 움직여도 값이 한 칸 튄다.
    mutating func reset() {
        accumulated = 0
    }

    /// 이벤트 하나를 먹고 **이번에 적용할 스텝 수**를 돌려준다(0이면 아직 문턱 미만).
    ///
    /// 방향: 반환값이 양수 = 더 불투명(값 증가)이고, 그 기준은 **손가락·휠의 물리적 위쪽**이다
    /// (`isInverted` 면 `deltaY` 를 뒤집어 물리 방향으로 되돌린다). 문서 방향(deltaY 부호)을 그대로 쓰지 않는
    /// 이유는 하나다 — 자연스러운 스크롤은 장치별로 따로 켜진다(트랙패드는 켜고 외장 마우스는 끄는 조합이
    /// 흔하다). 문서 방향을 쓰면 **같은 맥에서 같은 손동작이 트랙패드와 마우스에서 반대로 동작한다.**
    /// 물리 방향으로 고정하면 "위로 밀면 진해진다"가 장치와 설정에 상관없이 성립한다(슬라이더를 위로
    /// 올리면 값이 커지는 것과 같은 은유).
    ///
    /// 관성(`isMomentum`)은 **버린다**. 손을 뗀 뒤에도 값이 혼자 흘러가면 멈출 방법이 없고, 사용자는
    /// 자기가 놓은 자리가 아닌 곳에서 끝난 값을 보게 된다. 목록 스크롤과 달리 이건 되돌리기가 번거로운 설정값이다.
    ///
    /// 걸림쇠 휠(`isPrecise == false`)은 누적하지 않고 **이벤트 한 개 = 한 스텝**으로 센다. 장치가 이미
    /// 이산적으로 끊어 주고 있고, 한 칸이 몇 '줄'로 오는지는 드라이버마다 다르다(1 또는 3) — 그 숫자를
    /// 거리로 환산해 문턱과 견주는 순간 기기에 따라 한 칸이 한 스텝이 되기도 세 스텝이 되기도 한다.
    mutating func steps(for sample: TodoBoardScrollSample) -> Int {
        guard !sample.isMomentum else {
            // 관성이 시작됐다는 건 제스처가 끝났다는 뜻이다 — 잔여도 같이 턴다.
            accumulated = 0
            return 0
        }
        guard sample.deltaY.isFinite, sample.deltaY != 0 else { return 0 }
        let up = sample.isInverted ? -sample.deltaY : sample.deltaY

        guard sample.isPrecise else {
            accumulated = 0
            return up > 0 ? 1 : -1
        }

        // 방향이 바뀌면 반대편 잔여를 버린다. 남겨 두면 "+20pt 쌓다가 반대로 꺾었더니 44pt 를 밀어야
        // 한 칸 내려간다"가 되어, 되돌리는 조작만 유독 둔해진다.
        if accumulated != 0, (up > 0) != (accumulated > 0) { accumulated = 0 }
        accumulated += up

        let raw = (accumulated / Self.stepDistance).rounded(.towardZero)
        let bounded = min(max(raw, -Self.maxStepsPerEvent), Self.maxStepsPerEvent)
        if bounded == raw {
            accumulated -= bounded * Self.stepDistance
        } else {
            // 한도에 걸린 이벤트는 정상적인 손동작이 아니다 — 잔여를 남겨 다음 이벤트까지 끌고 가지 않는다.
            accumulated = 0
        }
        return Int(bounded)
    }
}

/// `NSEvent` 모니터 토큰을 담는 상자.
///
/// 왜 `Any?` 를 그냥 들고 있지 않은가 — 해제 경로가 두 곳이기 때문이다. 닫기는 메인 액터에서 오지만
/// `deinit` 은 Swift 6 에서 **비격리**라 격리된 저장 프로퍼티를 읽지 못한다(`Any` 는 Sendable 이 아니다).
/// 토큰을 Sendable 상자에 넣으면 deinit 도 토큰을 꺼낼 수 있고, `removeMonitor` 는 **등록한 스레드에서**
/// 불러야 하므로(문서) 거기서 메인으로 한 번 건너뛴다.
private final class TodoBoardScrollMonitorToken: @unchecked Sendable {
    let raw: Any
    init(_ raw: Any) { self.raw = raw }
}

// MARK: - 보드 UI 상태(컨트롤러 소유)

/// 보드의 **입력 상태**. 뷰의 `@State` 가 아니라 컨트롤러가 소유해야 하는 값들만 모았다.
///
/// 왜 뷰에 두지 않는가: 울트라 격발처럼 보드를 잠깐 내렸다 다시 올리는 경로가 이미 있고, 그때 SwiftUI 는
/// 뷰 트리를 다시 만들 수 있다 — `@State` 였다면 **적다 만 글이 통째로 사라진다**. 창을 살려 두는 것만으로는
/// 부족하다(상태의 주인이 뷰이면 뷰가 다시 만들어질 때 같이 날아간다).
///
/// 쓰기는 전부 `CheckTodoBoardController` 의 setter 를 거친다(그쪽에 `!=` 가드와 100자 차단이 있다).
/// 여기서는 저장만 한다.
@Observable
@MainActor
final class TodoBoardUIState {
    /// 입력칸 초안.
    var draft: String
    /// 인라인 수정 중인 항목. nil 이면 수정 중 아님.
    var editingID: UUID?
    /// '삭제됨 [되돌리기]' 로 자리를 지키고 있는 항목(아직 store 에서 지우지 않았다).
    var pendingDeleteID: UUID?
    /// 하단 '오래된 항목 (N)' 펼침 여부.
    var isOldSectionExpanded: Bool
    /// 보드가 기준으로 삼는 KST 하루 키. 컨트롤러가 열 때·손댈 때 갱신한다(자정 넘김 반영).
    var todayKey: String

    init(todayKey: String) {
        self.draft = ""
        self.editingID = nil
        self.pendingDeleteID = nil
        self.isOldSectionExpanded = false
        self.todayKey = todayKey
    }
}

// MARK: - 패널 콘텐츠 루트

/// 패널에 얹는 배선용 루트 뷰. 스토어와 UI 상태를 **관찰**해서 순수 뷰 `CheckTodoBoardView` 에는
/// 값과 클로저만 내려 준다 — 그래야 보드 본체가 store 를 모른 채 픽스처만으로 렌더 검증된다.
/// (캐릭터 오버레이의 `CheckOverlayRootView` 와 같은 역할이다.)
///
/// `@MainActor` 를 명시한 이유: 아래 `Binding(get:set:)` 이 받는 클로저는 `@Sendable` 이라, 붙들고 있는
/// 값들이 메인 액터에 묶여 있다는 것이 **타입 수준에서** 드러나야 캡처가 허용된다(뷰 body 는 어차피
/// 메인 액터에서만 돈다 — 사실을 적어 두는 것뿐이다).
@MainActor
private struct TodoBoardRootView: View {
    let store: TodoListStore
    let ui: TodoBoardUIState
    /// 투명도 설정의 주인. **값이 아니라 스토어를 들고 있는 것이 핵심이다** — `@Observable` 이라
    /// body 에서 `appearance.appearance` 를 읽는 순간 관찰이 걸려, 슬라이더든 ⌥+스크롤이든 값이 바뀌면
    /// 이 뷰가 스스로 다시 그려진다(컨트롤러가 뷰를 밀어 넣을 필요가 없다).
    let appearance: TodoBoardAppearanceStore
    let onOpacityChange: (Double) -> Void
    let onDraftChange: (String) -> Void
    let onSubmitDraft: () -> Void
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    let onToggleOldSection: () -> Void
    let onClose: () -> Void

    var body: some View {
        let key = ui.todayKey
        // 표시 규칙(자정 지난 완료 감추기·삭제 제외)과 **정렬은 TodoRules 가 단독으로 소유한다**.
        // 여기서 한 번 더 정렬하면 순서 정책이 두 곳으로 갈라져 조용히 어긋난다. 우리는 '오래된 항목'
        // 구간만 갈라내고 원래 순서를 그대로 보존한다.
        let all = TodoRules.visible(store.items, todayKey: key)
        var active: [TodoItem] = []
        var old: [TodoItem] = []
        for item in all {
            if TodoRules.isOld(item, todayKey: key) {
                old.append(item)
            } else {
                active.append(item)
            }
        }
        // 바인딩 클로저에는 뷰 자신(self)이 아니라 필요한 둘만 넘긴다 — 붙잡는 것이 적을수록 수명이 명확하다.
        let state = ui
        let write = onDraftChange
        return CheckTodoBoardView(
            items: active,
            oldItems: old,
            todayKey: key,
            isOldSectionExpanded: ui.isOldSectionExpanded,
            editingID: ui.editingID,
            pendingDeleteID: ui.pendingDeleteID,
            // 읽기는 관찰 대상(ui.draft)에서 곧바로, 쓰기는 컨트롤러를 거친다 — 100자 차단과 `!=` 가드가
            // 거기 한 곳에만 있어야 입력칸이 어느 경로로 바뀌든 규칙이 똑같이 걸린다.
            draft: Binding(get: { state.draft }, set: { write($0) }),
            onSubmitDraft: onSubmitDraft,
            onToggleDone: onToggleDone,
            onBeginEdit: onBeginEdit,
            onCommitEdit: onCommitEdit,
            onCancelEdit: onCancelEdit,
            onDelete: onDelete,
            onUndoDelete: onUndoDelete,
            onToggleOldSection: onToggleOldSection,
            onClose: onClose,
            appearance: appearance.appearance,
            onOpacityChange: onOpacityChange
        )
    }
}

// MARK: - 컨트롤러

/// 투두 보드 패널의 수명·배치·입력 상태를 쥐는 컨트롤러.
///
/// 캐릭터 오버레이 컨트롤러와의 차이만 적는다: 이 창은 **클릭을 받고 키가 되며**(입력이 목적),
/// 화면공유·녹화에서 제외되고(`sharingType = .none`), 근무 상태가 아니라 **사용자의 클릭**으로만 뜬다.
@MainActor
final class CheckTodoBoardController {
    /// 표시 의도(헤드리스 검증 지점). 실제 표시 여부는 `panel.isVisible` 이지만 그건 헤드리스에서 흔들린다.
    private(set) var isBoardOpen = false

    private let store: TodoListStore
    /// 보드 투명도 설정의 주인(창 밖에서 산다 — 설정 UI 도 같은 인스턴스를 본다).
    private let appearanceStore: TodoBoardAppearanceStore
    /// 보드 입력 상태의 주인. 패널을 내려도, 뷰가 다시 만들어져도 여기 남는다.
    private let ui: TodoBoardUIState
    /// 지연 생성된 패널. **닫을 때 파괴하지 않는다** — NSHostingView 를 다시 만드는 비용도 비용이지만,
    /// 재생성 과정에서 3D 캐릭터 옆에 한 프레임 빈 창이 스치고 포커스가 튀는 게 더 나쁘다.
    private var panelStorage: TodoBoardPanel?
    /// 블러 뷰(패널을 만들 때 같이 선다). 투명도 통지가 왔을 때 **여기에만** 알파를 건다 —
    /// 컨테이너나 패널에 걸면 글자까지 같이 흐려진다.
    private var blurStorage: NSVisualEffectView?
    /// '삭제됨 [되돌리기]' 창을 닫는 타이머. 이 태스크가 끝나면 삭제가 확정된다.
    private var undoTask: Task<Void, Never>?

    /// 이 인스턴스의 되돌리기 유예(초). 프로덕션은 언제나 `TodoRules.undoSeconds`(5).
    /// **테스트만** 짧게 주입해 "타이머가 스스로 깨어나 삭제를 확정하는가"를 실시간으로 검증한다.
    /// (오버레이의 `ultraDurationSeconds` 와 같은 이유 — 주입 지점이 없으면 그 검증에 매번 5초가 들어
    ///  아무도 안 쓰게 되고, 결국 타이머 생성을 통째로 지워도 스위트가 초록인 구멍이 생긴다.)
    let undoSeconds: Double

    /// `appearance` 에 기본값이 있는 이유는 **테스트 편의가 아니라 계약의 방향** 때문이다. 이 컨트롤러는
    /// 설정 스토어의 소유자가 아니라 소비자다(설정 UI 도 같은 인스턴스를 본다) — 그래서 주입을 받되,
    /// 안 주면 앱이 실제로 쓰는 표준 저장소를 그대로 쓴다.
    init(
        store: TodoListStore,
        appearance: TodoBoardAppearanceStore = TodoBoardAppearanceStore(),
        undoSeconds: Double = TodoRules.undoSeconds
    ) {
        self.store = store
        self.appearanceStore = appearance
        self.undoSeconds = undoSeconds
        self.ui = TodoBoardUIState(todayKey: store.todayKey)
        // 콜백의 소비자는 **AppKit 쪽(블러 알파) 하나뿐**이다(SwiftUI 쪽은 @Observable 관찰로 따로 따라온다).
        // 붙잡는 것은 weak self 뿐이라 컨트롤러가 죽으면 통지도 조용히 멎는다.
        appearance.onChange = { [weak self] value in self?.applyBlurAlpha(value) }
    }

    deinit {
        // 모니터 토큰의 주인은 NSEvent 다 — 컨트롤러가 죽어도 등록은 앱에 그대로 남아, 그 뒤로도
        // 앱의 모든 스크롤이 죽은 클로저를 거쳐 간다. 닫기 경로가 한 번이라도 새면 여기가 마지막 문이다.
        guard let scrollMonitor else { return }
        Task { @MainActor in NSEvent.removeMonitor(scrollMonitor.raw) }
    }

    // MARK: - 패널

    /// 패널(첫 접근에 생성). 근무 내내 안 열 수도 있는 창이라 앱 시작 시 만들지 않는다.
    var panel: TodoBoardPanel {
        if let panelStorage { return panelStorage }
        let created = Self.makePanel()
        let bounds = NSRect(origin: .zero, size: TodoBoardAnchor.boardSize)

        // ★ 계층은 **형제 배치**다: 투명 컨테이너 아래에 블러와 호스팅 뷰가 나란히 선다.
        //
        //   왜 자식이 아니라 형제인가 — 사용자 투명도가 `effect.alphaValue` 로 들어오는데, 호스팅 뷰가
        //   블러의 자식이면 그 알파를 **글자·체크박스·버튼까지 그대로 먹는다**. "투명하게 했더니 글자가
        //   안 보인다"가 정확히 그 그림이고, 설정 모델이 명시적으로 금지한 배치다.
        //
        //   형제로 옮겨도 behind-window 블렌딩은 **그대로 산다**(이게 유일한 걱정거리였다). 실측 —
        //   같은 패널을 두 배치로 세워 레이어 트리를 덤프했을 때 둘 다 `CABackdropLayer` 가 섰고,
        //   형제 배치에서 `effect.alphaValue = 0.3` 을 건 뒤에는 블러 뷰의 백킹 레이어만 opacity 0.3,
        //   호스팅 뷰의 백킹 레이어는 1.0 그대로였다. 호스팅 뷰 백킹스토어 픽셀도 알파 0.549(=틴트 0.55)로
        //   불투명(1.000)이 아니었다.
        //
        //   컨테이너는 **배경을 깔지 않는다**. 한 겹이라도 불투명한 판이 블러 위/아래에 끼면 창이
        //   반투명이어도 사용자 눈에는 회색 판이다.
        let container = NSView(frame: bounds)
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]

        // ★ 블러는 **창의 콘텐츠 계층에 직접** 서야 한다. SwiftUI `.background(NSViewRepresentable)` 로 넣으면
        //   호스팅 뷰가 자기 레이어에 합성해 버려 behind-window 블렌딩이 죽고, 보드가 뒤를 완전히 가리는
        //   불투명 판이 된다(실사용 신고).
        let effect = NSVisualEffectView(frame: bounds)
        // 재질 선택 근거는 **실측한 틴트 두께**다. 같은 어두운 외관에서 각 재질이 백드롭 위에 얹는 틴트 알파는
        // hudWindow 0.40 < popover 0.60 < menu 0.70 < sidebar·underWindowBackground 0.80 이었다
        // (레이어 트리 덤프로 확인). 우리는 그 위에 대비용 틴트 0.55 를 한 겹 더 얹으므로, 뒤가 실제로
        // 보이는 양은 hudWindow 가 (1-0.40)×(1-0.55)≈27%, underWindowBackground 는 ≈9% 다.
        // "반투명하지 않다"는 신고를 받은 창에서 가장 얇은 재질을 고르는 건 자명하고, 의미상으로도
        // hudWindow 는 '남의 앱 위에 떠 있는 보조 패널'용 재질이다(popover/menu 는 곧 사라지는 임시 표면,
        // underWindowBackground/sidebar 는 자기 창 안의 영역용).
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        // .followsWindowActiveState 면 다른 앱을 클릭하는 순간 블러가 꺼져 회색 판으로 죽는다.
        // 이 보드는 남의 앱 위에 계속 떠 있는 게 목적이라 항상 활성으로 고정한다.
        //
        // 이 한 줄이 실제로 뒤를 뚫는다는 증거: state 를 .inactive 로 두면 AppKit 이 레이어 트리에서
        // CABackdropLayer(뒤 화면을 표본 삼는 레이어) 자체를 빼 버리고 **알파 1.0 짜리 단색 레이어**로
        // 갈아치운다(실측). 즉 신고된 "뒤를 완전 가려버린다"와 정확히 같은 그림이 된다.
        effect.state = .active
        effect.wantsLayer = true
        // ★ 모서리 클립은 **컨테이너가 아니라 블러 뷰에** 건다. 형제 배치가 되면서 후보가 둘로 늘었지만,
        //   자를 것이 있는 쪽은 블러뿐이다 — 재질은 자기 bounds 를 꽉 채운 사각형으로 그려지므로 레이어가
        //   깎지 않으면 네 귀퉁이가 각진 채 삐져나온다. 반대로 호스팅 뷰 쪽 그림(틴트·테두리·행)은 SwiftUI 가
        //   이미 같은 반지름·같은 곡선으로 자르고 있고(`CheckTodoBoardView.body` 의 clipShape), 컨테이너에
        //   masksToBounds 를 걸면 **두 자식을 전부** 담는 오프스크린 합성이 매 프레임 한 번 더 생긴다 —
        //   이미 잘려 있는 그림을 다시 자르려고. 실측으로도 블러 쪽 클립만으로 호스팅 뷰의 모서리 픽셀이
        //   비어 있었다(같은 지점 중앙은 틴트 알파 0.549, 모서리는 0.000).
        effect.layer?.cornerRadius = CheckTodoBoardView.cornerRadius
        // ★ SwiftUI 쪽은 `RoundedRectangle(style: .continuous)` 로 자른다. 레이어의 기본 곡률은 원호(.circular)라
        //   같은 반지름이어도 **모서리 곡선이 다르다** — 재질(레이어가 자름)과 틴트·테두리(SwiftUI 가 자름)의
        //   경계가 몇 px 어긋나 모서리에 지저분한 실선이 남는다. 두 클립을 같은 스퀘어클 곡선으로 맞춘다.
        effect.layer?.cornerCurve = .continuous
        // 이 한 줄은 **지금은 지워도 그림이 같다** — `cornerRadius` 를 넣는 순간 AppKit 이 백킹 레이어의
        // masksToBounds 를 스스로 켠다(실측: 대입 전 false → cornerRadius 대입 직후 true. 그래서 이 줄만
        // 지우는 뮤테이션은 어떤 테스트로도 못 죽인다). 그래도 남기는 이유는 그 켜짐이 문서화된 계약이
        // 아니라 관찰된 동작이고, 위 두 줄이 언젠가 maskImage 같은 다른 방식으로 바뀌면 클립이 조용히
        // 사라지기 때문이다(모서리는 각지는데 테스트는 초록인 상태).
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        // 앱을 껐다 켠 뒤 **처음 여는 창**에도 저장값이 서 있어야 한다. 통지(onChange)는 값이 바뀔 때만
        // 오므로, 여기서 한 번 읽지 않으면 사용자가 슬라이더를 만지기 전까지 창만 기본값으로 남는다.
        effect.alphaValue = CGFloat(appearanceStore.appearance.blurAlpha)

        let hosting = NSHostingView(rootView: makeRootView())
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]

        container.addSubview(effect)
        // 순서가 곧 계층이다 — 호스팅 뷰가 블러 **위**여야 글자가 재질에 묻히지 않는다.
        container.addSubview(hosting, positioned: .above, relativeTo: effect)
        created.contentView = container
        panelStorage = created
        blurStorage = effect
        return created
    }

    /// 사용자 투명도를 창에 반영한다. **블러 뷰의 알파만 만진다** — 컨테이너나 패널에 걸면 그 아래
    /// 호스팅 뷰까지 같이 흐려져 글자가 유령이 된다(형제 배치의 존재 이유가 여기다).
    ///
    /// **패널을 아직 안 만들었으면 아무 일도 하지 않는다.** 여기서 `panel` 을 읽으면 설정 슬라이더를
    /// 움직이는 것만으로 열지도 않은 보드가 생겨 버린다(지연 생성 파괴). 반영할 창이 없으면 반영할 것도
    /// 없고, 처음 만들 때 저장값을 그대로 읽어 세운다.
    private func applyBlurAlpha(_ value: TodoBoardAppearance) {
        guard let blurStorage else { return }
        blurStorage.alphaValue = CGFloat(value.blurAlpha)
    }

    /// 헤드리스 검증 지점 — '패널을 이미 만들었는가'. 지연 생성(열기 전엔 없음)과 닫아도 살아 있음
    /// (입력 상태 보존)을 밖에서 값으로 확인하려면 이 문이 필요하다. `panel` 을 읽으면 그 순간 만들어져
    /// 버리므로 이 프로퍼티로만 물어야 한다.
    var hasPanel: Bool { panelStorage != nil }

    /// 보드 패널을 만든다. 캐릭터 패널(`CheckOverlayController.makePanel`)과 **다른 점**:
    /// · `ignoresMouseEvents = false` — 체크·수정·삭제를 클릭으로 받는 창이다.
    /// · `hasShadow = true` — 반투명 보드가 뒤 창과 뒤섞이지 않게 경계를 세운다.
    /// · `TodoBoardPanel` — 키를 받을 수 있어야 글자가 들어간다(위 타입 주석 참고).
    /// 나머지(레벨·투명 배경·전 Space 유지·비활성화 시 숨지 않음)는 캐릭터 패널과 같은 값을 쓴다.
    static func makePanel() -> TodoBoardPanel {
        let panel = TodoBoardPanel(
            contentRect: NSRect(origin: .zero, size: TodoBoardAnchor.boardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        // NSPanel 의 기본값은 **true** 다. 그대로 두면 사용자가 원래 쓰던 앱이 활성인 동안(=거의 항상)
        // 보드가 저절로 숨는다 — 우리는 앱을 활성화하지 않는 창이므로 이 값을 반드시 뒤집어야 한다.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // 위치는 컨트롤러가 앵커로 계산한다. 사용자가 끌어 옮기면 캐릭터와 어긋난 채 남아 다음 열기에 튄다.
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // ★ 프라이버시 방어선. 투두 본문은 업무 정보(고객명·계약·급여 같은 게 그대로 적힌다)라
        //   화면공유·녹화에 **절대** 실리면 안 된다. 발표 중 캐릭터를 눌러 보드를 여는 일은 반드시 일어나고,
        //   그때 사용자가 막을 수단은 없다 — 창 자체를 캡처 대상에서 뺀다.
        panel.sharingType = .none
        // 우리가 패널을 계속 붙들고 재사용하므로(닫기=orderOut) 닫힘에 딸린 해제가 끼어들면 안 된다.
        panel.isReleasedWhenClosed = false
        // ★ 보드는 **어두운 테마 전용**으로 그려진다(CheckTheme.panel 틴트 + 흰 글자). 그런데 재질은
        //   시스템 외관을 따라가므로, 밝은 테마에서는 같은 hudWindow 가 흰 틴트(0.965@0.48 + 0.96)로 바뀐다(실측).
        //   그 위에 어두운 틴트 0.55 를 얹으면 중간 회색 판이 되어 흰 글자 대비가 무너지고, 스크롤바 같은
        //   시스템 그림도 밝은 배경 기준으로 그려진다. 사용자 외관과 무관하게 창을 어둡게 고정한다.
        panel.appearance = NSAppearance(named: .darkAqua)
        // 테스트 실행일 때만 알파 0(프로덕션은 1 그대로 — 보드의 반투명은 블러 뷰 알파가 정한다).
        // 캐릭터 패널과 **같은 한 지점**을 지난다. 근거는 CheckPanelVisibility 주석에 있다.
        CheckPanelVisibility.apply(to: panel)
        return panel
    }

    private func makeRootView() -> TodoBoardRootView {
        // 패널 → 호스팅 뷰 → 루트 뷰 → 클로저가 컨트롤러를 도로 잡으므로 전부 weak 로 끊는다.
        TodoBoardRootView(
            store: store,
            ui: ui,
            appearance: appearanceStore,
            // 뷰가 부르는 조절은 전부 스토어를 거친다(clamp·저장·중복 차단이 거기 한 곳에만 있다).
            onOpacityChange: { [weak self] value in self?.appearanceStore.setOpacity(value) },
            onDraftChange: { [weak self] text in self?.setDraft(text) },
            onSubmitDraft: { [weak self] in self?.submitDraft() },
            onToggleDone: { [weak self] id in self?.toggleDone(id) },
            onBeginEdit: { [weak self] id in self?.beginEdit(id) },
            onCommitEdit: { [weak self] id, text in self?.commitEdit(id, to: text) },
            onCancelEdit: { [weak self] in self?.cancelEdit() },
            onDelete: { [weak self] id in self?.requestDelete(id) },
            onUndoDelete: { [weak self] id in self?.undoDelete(id) },
            onToggleOldSection: { [weak self] in self?.toggleOldSection() },
            onClose: { [weak self] in self?.close() }
        )
    }

    // MARK: - 열기 / 닫기 / 배치

    /// 캐릭터 클릭 진입점. 열려 있으면 닫고, 닫혀 있으면 그 자리에 연다.
    func toggle(anchor: NSRect, screenVisibleFrame: NSRect) {
        if isBoardOpen {
            close()
        } else {
            open(anchor: anchor, screenVisibleFrame: screenVisibleFrame)
        }
    }

    /// 보드를 앵커 옆에 띄운다(멱등 — 이미 열려 있으면 위치만 다시 잡는다).
    ///
    /// **`makeKey` 를 부르지 않는다.** 프로그램으로 키를 가져오면 실측상 앱이 활성화되어(nonactivating 패널도
    /// `makeKeyAndOrderFront` 경로에서는 활성화를 유발한다) 사용자가 쓰던 편집기·브라우저가 비활성이 된다 —
    /// 할 일 하나 적자고 남의 창 포커스를 뺏는 셈이다. 그래서 **2단 포커스**로 간다: 여기서는 띄우기만 하고,
    /// 사용자가 입력칸을 클릭하는 순간 nonactivating 패널이 스스로 키를 가져간다(그때는 앱이 활성화되지 않는다).
    ///
    /// `display: false` 인 이유는 캐릭터 패널과 같다 — 여기서 표시 패스를 강제하면 AppKit 이 그 자리에서
    /// SwiftUI 를 평가해 우리 콜백을 재진입시킨다. 프레임 값은 이 줄에서 이미 확정되고 그리기만 다음
    /// 런루프로 밀린다.
    func open(anchor: NSRect, screenVisibleFrame: NSRect) {
        syncTodayKey()
        let board = panel
        board.setFrame(TodoBoardAnchor.frame(anchor: anchor, in: screenVisibleFrame), display: false)
        board.orderFrontRegardless()
        isBoardOpen = true
        installScrollMonitor()
    }

    /// 보드를 내린다(멱등). 패널과 입력 상태(초안·수정 중)는 **그대로 남는다** — 다시 열면 적다 만 글이
    /// 그 자리에 있어야 한다.
    ///
    /// 단 하나, 삭제 되돌리기만은 여기서 **확정**한다. 5초 유예는 '눈에 보이는 되돌리기 버튼'이 있을 때만
    /// 성립하는 약속이라, 보드를 내린 채 재는 카운트다운은 사용자가 볼 수도 누를 수도 없는 유령이다.
    /// 남겨 두면 다시 열었을 때 유령 '삭제됨' 행이 서 있거나, 보이지 않는 곳에서 항목이 사라진다.
    func close() {
        commitPendingDelete()
        removeScrollMonitor()
        panelStorage?.orderOut(nil)
        isBoardOpen = false
    }

    // MARK: - ⌥ + 스크롤로 투명도 조절

    /// 등록된 로컬 모니터 토큰. nil 이면 안 걸려 있다(헤드리스 검증 지점 `hasScrollMonitor` 가 이걸 본다).
    private var scrollMonitor: TodoBoardScrollMonitorToken?
    /// 델타 누적 상태. 창을 열고 닫을 때 턴다.
    private var scrollGesture = TodoBoardScrollOpacityGesture()

    /// 모니터가 걸려 있는가(헤드리스 검증 지점). 전역 훅을 앱 수명 내내 켜 두지 않는다는 계약을
    /// 밖에서 값으로 확인하려면 이 문이 필요하다.
    var hasScrollMonitor: Bool { scrollMonitor != nil }

    /// ⌥+스크롤을 가로챌 로컬 모니터를 건다(**보드가 떠 있는 동안만**).
    ///
    /// 왜 뷰 계층 오버라이드(`scrollWheel(with:)`)가 아니라 모니터인가: 보드 안에는 SwiftUI `ScrollView` 가
    /// 있고, 스크롤 이벤트는 그 안쪽 스크롤 뷰가 먼저 먹는다 — 우리 뷰의 오버라이드까지 올라오지 않는다.
    /// 모니터는 이벤트가 창에 배달되기 **전에** 보므로 순서 싸움이 아예 없다.
    ///
    /// 대신 로컬 모니터는 **앱 전체**의 스크롤을 본다. 그래서 열려 있는 동안에만 걸고, 닫을 때 반드시 뗀다.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollGesture.reset()
        // `[weak self]` 는 **바깥** 클로저에 있어야 한다. 안쪽(assumeIsolated)에만 걸면 바깥이 self 를
        // 강하게 잡아 컨트롤러가 영영 안 죽고, 그러면 바로 위 `deinit` 의 removeMonitor 는 정의상
        // 도달할 수 없는 죽은 코드가 된다(Swift 6 로 컴파일해 실증 — 유일한 강한 참조를 놓아도 deinit 이
        // 돌지 않았고, 여기 weak 를 붙이자 즉시 돌았다). 실행당 컨트롤러가 1개라 새는 건 아니지만,
        // "닫기가 새면 deinit 이 마지막 문"이라는 계약이 거짓이 된다.
        let token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // 주인이 사라졌으면 **반드시 그대로 흘려보낸다**. 여기서 삼키면(nil) 등록만 남은 죽은
            // 클로저가 앱의 모든 스크롤을 죽인다 — 로컬 모니터는 앱 전체를 본다.
            guard let self else { return event }
            // 모니터 콜백은 메인 런루프에서 온다(오버레이의 mouseMoved 모니터와 같은 계약).
            // 경계 밖으로 내보내는 값이 Bool 인 이유: NSEvent 는 Sendable 이 아니라 액터 경계를 못 넘는다.
            // 삼킬지 말지만 안에서 정하고, 이벤트 자체는 이 클로저 안에 그대로 둔 채 돌려준다.
            let consumed = MainActor.assumeIsolated { self.handleScroll(event) }
            return consumed ? nil : event
        }
        scrollMonitor = token.map(TodoBoardScrollMonitorToken.init)
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor.raw) }
        scrollMonitor = nil
        scrollGesture.reset()
    }

    /// 스크롤 한 개를 보고 **삼킬지 흘려보낼지** 정한다. 반환값 true = 소비(이벤트를 죽인다).
    ///
    /// 우리 창 위의 ⌥+스크롤만 가져간다. 그 밖은 전부 그대로 흘려보내야 한다 — 여기서 잘못 삼키면
    /// 보드 목록은 물론 **앱의 다른 창 스크롤까지** 죽는다(로컬 모니터는 앱 전체를 본다).
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let panelStorage, event.window === panelStorage,
              Self.adjustsOpacity(modifiers: event.modifierFlags)
        else { return false }

        let steps = scrollGesture.steps(for: TodoBoardScrollSample(event: event))
        if steps != 0 {
            appearanceStore.nudge(by: Double(steps) * TodoBoardAppearance.step)
        }
        // 문턱을 못 넘은 이벤트도 삼킨다. 흘려보내면 ⌥ 를 쥔 채 굴리는 내내 목록이 같이 움직여,
        // 투명도를 맞추고 나면 화면이 엉뚱한 곳에 가 있다.
        return true
    }

    /// 이 조합이 투명도 조절인가. 조합 판정만 순수 함수로 떼어 낸 이유는 `.scrollWheel` NSEvent 를
    /// 합성할 수 없어서다(오프스크린에서 만들 방법이 없다) — 규칙만이라도 값으로 검증한다.
    ///
    /// ⌘·⌃ 가 섞이면 물러난다: ⌃+스크롤은 **시스템 화면 확대**, ⌘+스크롤은 앱마다 확대·축소로 이미 쓰인다.
    /// ⇧ 는 스크롤을 가로 방향으로 바꾸는 조합이라(그때 `scrollingDeltaY` 는 0으로 온다) 역시 뺀다.
    /// CapsLock·Fn 같은 나머지 플래그는 **무시한다** — `flags == .option` 로 못 박으면 CapsLock 이 켜진
    /// 사용자에게만 기능이 통째로 죽는다.
    nonisolated static func adjustsOpacity(modifiers: NSEvent.ModifierFlags) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.option) && flags.isDisjoint(with: [.command, .control, .shift])
    }

    /// 실제로 창을 옮긴 횟수(헤드리스 검증 지점). 아래 조기 반환이 살아 있는지를 밖에서 값으로 확인하려면
    /// 이 계수기가 필요하다 — 같은 자리로 다시 옮기는 호출은 AppKit 이 조용히 흡수해 버려서
    /// 창 상태만 봐서는 "안 옮겼다"와 "옮겼는데 결과가 같다"를 구분할 수 없다.
    private(set) var repositionAppliedCount = 0

    /// 캐릭터가 움직였을 때 보드를 따라 옮긴다. **드래그 중 60Hz 로 불리는 경로다** — 여기서 하는 일은
    /// 전부 그 빈도를 견뎌야 한다.
    ///
    /// · 닫혀 있으면 아무것도 하지 않는다. 특히 `panel` 을 건드리지 않는다(읽는 순간 만들어지므로,
    ///   열지도 않은 창을 드래그만으로 생성해 버린다).
    /// · **띄우거나 키를 가져오는 호출을 절대 넣지 않는다.** 매 프레임 `orderFront`/`makeKey` 가 돌면
    ///   사용자가 쓰던 앱에서 포커스가 튀고, 마우스를 움직이는 내내 우리 창이 앞으로 튀어나온다.
    ///   위치만 바꾸면 이미 떠 있는 창은 그대로 따라온다.
    /// · 자리가 그대로면 조기 반환한다. 캐릭터는 픽셀 단위로 흔들려도 보드는 화면 클램프에 걸려
    ///   같은 좌표에 머무는 구간이 길다 — 그 구간에서 매 프레임 창을 건드리면 값을 다시 쓰는 비용만 든다.
    /// · 크기는 언제나 `boardSize` 로 고정이라 보통은 `setFrameOrigin` 으로 끝난다(`setFrame` 은 크기 변경과
    ///   표시 패스까지 다루는 무거운 경로다). 크기가 다를 때만 `setFrame` 으로 떨어지되 `display: false` 다 —
    ///   여기서 표시 패스를 강제하면 드래그 프레임마다 SwiftUI 평가가 끼어든다.
    func reposition(anchor: NSRect, screenVisibleFrame: NSRect) {
        guard isBoardOpen, let panelStorage else { return }
        let target = TodoBoardAnchor.frame(anchor: anchor, in: screenVisibleFrame)
        let current = panelStorage.frame
        guard current != target else { return }
        repositionAppliedCount += 1
        if current.size == target.size {
            panelStorage.setFrameOrigin(target.origin)
        } else {
            panelStorage.setFrame(target, display: false)
        }
    }

    // MARK: - 입력 상태(컨트롤러가 소유)

    var draft: String { ui.draft }
    var editingID: UUID? { ui.editingID }
    var pendingDeleteID: UUID? { ui.pendingDeleteID }
    var isOldSectionExpanded: Bool { ui.isOldSectionExpanded }
    /// 보드가 기준으로 삼는 KST 하루 키(헤드리스 검증 지점).
    var todayKey: String { ui.todayKey }

    /// 초안을 바꾼다. **100자를 넘기는 입력은 통째로 거부한다** — 자르지 않는다.
    /// 잘라 버리면 사용자가 방금 친 글자가 소리 없이 사라져 어디까지 들어갔는지 알 수 없다. 거부하면
    /// 화면이 그대로 멈춰 "더는 안 들어간다"가 보인다(90자부터 뜨는 카운터가 그 이유를 설명한다).
    /// 길이는 정규화 전 **사용자가 보는 글자 수**로 잰다(정규화는 저장 시점의 일이다).
    /// 짧아지는 방향은 언제나 허용되므로, 어떤 경로로 100자를 넘겨 들어왔더라도 지워서 빠져나올 수 있다.
    func setDraft(_ text: String) {
        guard text.count <= TodoRules.maxTitleLength || text.count < ui.draft.count else { return }
        if ui.draft != text { ui.draft = text }
    }

    /// 입력칸 Enter. 성공했을 때만 초안을 비운다 — 공백만 친 입력을 store 가 거절했는데 여기서 지워 버리면
    /// 사용자가 친 것이 이유 없이 증발한다.
    func submitDraft() {
        syncTodayKey()
        guard store.add(ui.draft) != nil else { return }
        setDraft("")
    }

    func toggleDone(_ id: UUID) {
        syncTodayKey()
        store.toggleDone(id)
    }

    func beginEdit(_ id: UUID) {
        if ui.editingID != id { ui.editingID = id }
    }

    /// 인라인 수정 Enter. 저장 여부(빈 제목 거절 등)는 store 의 규칙에 맡기고, 수정 모드는 어느 쪽이든 닫는다 —
    /// 커밋을 눌렀는데 행이 계속 편집 상태로 남아 있으면 사용자는 저장이 안 된 줄 안다.
    func commitEdit(_ id: UUID, to rawTitle: String) {
        syncTodayKey()
        store.rename(id, to: rawTitle)
        cancelEdit()
    }

    /// 수정 모드 종료(Esc·커밋 후 공용). 원래 제목은 store 가 계속 들고 있으므로 여기서 되돌릴 것이 없다.
    func cancelEdit() {
        if ui.editingID != nil { ui.editingID = nil }
    }

    func toggleOldSection() {
        ui.isOldSectionExpanded.toggle()
    }

    // MARK: - 삭제 · 되돌리기(5초)

    /// 삭제 요청. **store 를 아직 건드리지 않는다.**
    ///
    /// 뷰가 보는 목록은 `TodoRules.visible` 이 걸러 낸 것뿐이라, 여기서 곧바로 지우면 그 항목이 목록에서
    /// 사라져 '삭제됨 [되돌리기]' 행이 설 자리 자체가 없어진다. 그래서 5초 동안은 항목을 그대로 두고
    /// `pendingDeleteID` 로만 표시해 그 자리에서 되돌릴 수 있게 하고, 유예가 끝나면 그때 지운다.
    ///
    /// 이미 다른 항목이 대기 중이면 그것을 먼저 확정한다 — 동시에 두 줄이 '삭제됨'으로 서 있으면
    /// 어느 되돌리기가 어느 줄의 것인지 알 수 없고, 타이머도 한 개뿐이다.
    func requestDelete(_ id: UUID) {
        if let pending = ui.pendingDeleteID, pending != id {
            commitPendingDelete()
        }
        syncTodayKey()
        if ui.pendingDeleteID != id { ui.pendingDeleteID = id }
        undoTask?.cancel()
        // 유예 값은 잠들기 **전에** 꺼내 둔다(자는 동안 컨트롤러를 붙들지 않게 — weak 로 끊는 이유가 사라진다).
        let seconds = undoSeconds
        undoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.commitPendingDelete()
        }
    }

    /// 되돌리기.
    ///
    /// 유예 중이면 아직 store 에 반영되지 않았으니 타이머를 끄는 것만으로 원상복구다.
    /// 대기 중이 아니면 **방금 확정된 직후의 늦은 클릭**이다(타이머가 먼저 깨어난 한 런루프 차이).
    /// 사용자는 분명히 되돌리기를 눌렀으므로 그 경우엔 store 에 되살리기를 부탁한다 — 여기서 조용히
    /// 물러나면 "눌렀는데 안 돌아왔다"가 된다.
    func undoDelete(_ id: UUID) {
        if ui.pendingDeleteID == id {
            undoTask?.cancel()
            undoTask = nil
            ui.pendingDeleteID = nil
            return
        }
        store.undoDelete(id)
    }

    /// 대기 중인 삭제를 지금 확정한다(멱등). 타이머 만료·보드 닫기·다른 항목 삭제가 모두 여기로 모인다.
    func commitPendingDelete() {
        undoTask?.cancel()
        undoTask = nil
        guard let id = ui.pendingDeleteID else { return }
        ui.pendingDeleteID = nil
        store.delete(id)
    }

    // MARK: - 하루 경계

    /// 보드가 쓰는 하루 키를 store 의 현재 값으로 맞춘다(값이 같으면 대입하지 않는다 — 같은 값 재대입도
    /// 관찰자를 깨워 보드 전체가 다시 그려진다).
    ///
    /// 열 때와 손댈 때마다 부른다. `store.todayKey` 는 시계를 읽는 계산 프로퍼티라 관찰 대상이 아니어서,
    /// 이 갱신이 없으면 자정을 넘겨 보드를 다시 열어도 **어제 기준 화면**이 그대로 서 있다
    /// (완료 항목이 안 사라지고 이월 배지도 안 는다).
    private func syncTodayKey() {
        let key = store.todayKey
        if ui.todayKey != key { ui.todayKey = key }
    }
}
