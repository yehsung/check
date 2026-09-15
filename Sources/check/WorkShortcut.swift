import AppKit
import Carbon.HIToolbox

// MARK: - 근무 시작·종료 전역 단축키 (v0.3.23)
//
// 메뉴바를 열지 않고 키 한 번으로 근무를 시작하거나 끝낸다. 기본은 ⌃⌥⌘Space, 설정에서 끄거나 키를 바꾼다.
//
// ★ 왜 Carbon `RegisterEventHotKey` 인가 — **권한이 필요 없는 유일한 길**이라서다.
//   · `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` 는 '입력 모니터링' 권한 창을 띄우고,
//     우리 앱이 frontmost 면 아예 침묵한다(설정 창을 띄워 둔 채 누르면 안 먹는다).
//   · `CGEvent.tapCreate`·`AXIsProcessTrusted` 는 접근성/입력 모니터링 권한을 요구한다. 팀원 전원에게
//     시스템 설정 깊숙한 권한을 켜 달라고 하는 순간 이 기능은 아무도 안 쓰는 기능이 된다.
//   · 핫키 등록은 창 서버가 조합을 우리 앱에 **배달**하는 방식이라 권한이 없고, 어느 앱이 앞에 있든(우리 앱 포함) 온다.
//   V0323WorkShortcutTests 가 이 셋이 Sources 에 들어오지 않았는지 소스로 되묻는다.
//
// ★ 겹침: 등록 결과(OSStatus)는 겹침을 알려 주지 않는다. 옵션 0 등록은 다른 앱이 같은 조합을 잡아도, 켜진 macOS 시스템
//   단축키와 같아도 noErr 이고, 한 번 누르면 **양쪽이 다** 받는다. 그래서 macOS 시스템 단축키는 목록을 읽어 대조하고
//   (`WorkShortcutSystemHotKeys`) 겹치면 걸지 않는다. 다른 앱과의 겹침은 원리적으로 알 수 없어 약속하지 않는다.

/// 전역 단축키 한 조합. 키는 **물리 키 코드**(kVK_*)로, 수식키는 Carbon 비트(controlKey 등)로 든다 —
/// `RegisterEventHotKey` 가 받는 모양 그대로라 등록 때 변환이 없고, 입력 소스(한글/영문)가 바뀌어도 같은 키다.
struct WorkShortcut: Equatable, Codable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    /// ⌃⌥⌘Space. 셋을 다 요구하는 조합이라 다른 앱의 기본 단축키와 겹칠 일이 드물다
    /// (⌘Space 는 Spotlight, ⌃⌘Space 는 이모지 창이 이미 쓴다).
    static let `default` = WorkShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
    )
}

extension WorkShortcut {
    /// 수식키 **자체**의 키 코드(오른쪽 ⌘ 54 · ⌘ 55 · ⇧ 56 · capsLock 57 · ⌥ 58 · ⌃ 59 · 오른쪽 ⇧⌥⌃ 60~62 · fn 63).
    /// 이 키들은 조합의 '키' 자리에 세우지 않는다. 수식키는 keyDown 이 아니라 flagsChanged 로 와서 기록기에는 원래 안 닿지만,
    /// 다른 경로(합성 입력 등)로 들어와도 "⌃⌥ + ⌘키" 같은, 사용자가 뜻한 적 없는 조합이 저장되지 않게 여기서 막는다.
    static let modifierOnlyKeyCodes: ClosedRange<UInt16> = 54...63

    /// Esc. 기록기에서 **취소 전용**이라 조합의 키로 받지 않는다(받으면 기록을 끝낼 방법이 사라진다).
    static let escapeKeyCode: UInt16 = 53

    /// 키 이벤트 하나를 조합으로. 수식키만 누른 이벤트면 nil.
    init?(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard !Self.modifierOnlyKeyCodes.contains(keyCode) else { return nil }
        self.init(keyCode: UInt32(keyCode), carbonModifiers: Self.carbonModifiers(from: flags))
    }

    /// AppKit 수식키 → Carbon 비트. ⌃⌥⇧⌘ 넷만 옮긴다 — capsLock·fn·numericPad 는 **버린다**.
    /// 그것들은 조합의 뜻이 아니라 누른 순간의 상태다(capsLock 이 켜져 있었다 · 화살표·F키는 fn 비트가 붙어 온다).
    /// 섞여 저장되면 같은 조합이 그 순간의 상태에 따라 다른 값이 되어, 표시·비교·허용 판정이 갈린다.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// 전역으로 가져가도 되는 조합인가: ⌃·⌥·⌘ 중 **두 개 이상**(⇧ 는 세지 않는다) 그리고 Esc 가 아님.
    ///
    /// ★ 한 수식키 조합을 막는 이유: 전역 핫키는 **모든 앱에서** 그 키를 가로챈다. ⌘C 를 가져가면 이 맥의 모든 앱에서
    ///   복사가 죽고, ⌘⇧K 같은 것도 어느 앱의 메뉴 단축키와 겹친다. ⇧ 는 대문자·기호 입력에 늘 붙는 키라 수로 치지 않는다.
    /// ★ 이 판정은 **모양**만 본다. 모양이 맞아도 켜진 macOS 단축키와 같으면 기록기가 따로 거절하고(`.rejectedSystem`)
    ///   조정자가 걸지 않는다(`.conflict`) — 그 목록은 사용자가 시스템 설정에서 바꾸는 값이라 여기 고정할 수 없다.
    var isAllowed: Bool {
        let strong = [controlKey, optionKey, cmdKey].filter { carbonModifiers & UInt32($0) != 0 }.count
        return strong >= 2 && keyCode != UInt32(Self.escapeKeyCode)
    }

    /// 화면 표시: ⌃⌥⇧⌘ 순서의 기호 + 키 이름(예: "⌃⌥⌘Space"). macOS 메뉴가 쓰는 순서와 같다.
    var displayString: String {
        modifierSymbols.map(\.symbol).joined() + Self.keyName(for: keyCode).symbol
    }

    /// 접근성 낭독용: "Control Option Command Space". 기호(⌃⌥⌘)는 VoiceOver 가 읽지 못하거나 엉뚱하게 읽는다.
    var spokenDescription: String {
        (modifierSymbols.map(\.spoken) + [Self.keyName(for: keyCode).spoken]).joined(separator: " ")
    }

    private var modifierSymbols: [KeyName] {
        [
            (controlKey, KeyName("⌃", "Control")),
            (optionKey, KeyName("⌥", "Option")),
            (shiftKey, KeyName("⇧", "Shift")),
            (cmdKey, KeyName("⌘", "Command")),
        ]
        .filter { carbonModifiers & UInt32($0.0) != 0 }
        .map(\.1)
    }

    struct KeyName: Equatable, Sendable {
        let symbol: String
        let spoken: String
        init(_ symbol: String, _ spoken: String) {
            self.symbol = symbol
            self.spoken = spoken
        }
    }

    /// 키 코드 → 이름. **ANSI 물리 배열 표**로 만든다 — `NSEvent.charactersIgnoringModifiers` 나 입력 소스(TIS)에서
    /// 뽑으면 한글 입력 상태에서 'ㅏ' 가 나오거나, ⌥ 가 섞여 'å' 같은 글자가 나온다. 등록되는 것은 물리 키이므로
    /// 이름도 물리 키에서 나와야 사용자가 본 것과 눌러야 할 것이 같다. 표에 없는 키는 "키 <코드>".
    static func keyName(for keyCode: UInt32) -> KeyName {
        keyNames[keyCode] ?? KeyName("키 \(keyCode)", "키 \(keyCode)")
    }

    private static let keyNames: [UInt32: KeyName] = {
        var table: [Int: KeyName] = [
            kVK_Space: KeyName("Space", "Space"),
            kVK_Return: KeyName("↩", "Return"),
            kVK_Tab: KeyName("⇥", "Tab"),
            kVK_Delete: KeyName("⌫", "Delete"),
            kVK_ForwardDelete: KeyName("⌦", "Forward Delete"),
            kVK_LeftArrow: KeyName("←", "Left Arrow"),
            kVK_RightArrow: KeyName("→", "Right Arrow"),
            kVK_UpArrow: KeyName("↑", "Up Arrow"),
            kVK_DownArrow: KeyName("↓", "Down Arrow"),
            kVK_ANSI_Minus: KeyName("-", "Minus"),
            kVK_ANSI_Equal: KeyName("=", "Equal"),
            kVK_ANSI_LeftBracket: KeyName("[", "Left Bracket"),
            kVK_ANSI_RightBracket: KeyName("]", "Right Bracket"),
            kVK_ANSI_Backslash: KeyName("\\", "Backslash"),
            kVK_ANSI_Semicolon: KeyName(";", "Semicolon"),
            kVK_ANSI_Quote: KeyName("'", "Quote"),
            kVK_ANSI_Comma: KeyName(",", "Comma"),
            kVK_ANSI_Period: KeyName(".", "Period"),
            kVK_ANSI_Slash: KeyName("/", "Slash"),
            kVK_ANSI_Grave: KeyName("`", "Grave Accent"),
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"),
            (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"),
            (kVK_F11, "F11"), (kVK_F12, "F12"), (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"),
            (kVK_F16, "F16"), (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20"),
        ]
        for (code, name) in letters { table[code] = KeyName(name, name) }
        return Dictionary(uniqueKeysWithValues: table.map { (UInt32($0.key), $0.value) })
    }()
}

// MARK: - macOS 시스템 단축키 (읽기 전용)

/// 지금 **켜져 있는** macOS 시스템 단축키(시스템 설정 › 키보드 › 키보드 단축키)를 조합 모양으로 읽는다.
///
/// ★ 왜 목록을 읽는가: 옵션 0 `RegisterEventHotKey` 는 ⌘Space·⌃Space·⌃⌥Space·⌘⇧3 같은 시스템 단축키와 겹쳐도 noErr 를
///   돌려주고, 한 번 누르면 시스템 동작과 우리 토글이 **둘 다** 일어난다(실측, Darwin 25.6). 등록 결과로는 영영 모르니
///   등록 **전에** 이 목록과 대조한다. `CopySymbolicHotKeys` 는 권한 없이 읽힌다 — 등록도, 이벤트 주입도 없다.
/// ★ 다른 **앱**의 단축키는 이 목록에 없다. 그 겹침은 원리적으로 감지할 수 없어서 약속하지 않는다.
enum WorkShortcutSystemHotKeys {
    /// 비교에 쓰는 수식키 네 비트(⌃⌥⇧⌘). 기록기가 이 넷만 남기므로(`WorkShortcut.carbonModifiers(from:)`) 목록도 이 넷으로 접는다.
    static let comparableModifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    /// 항목에 키가 없다는 표시.
    static let noKeyCode = 0xFFFF

    /// 켜진 시스템 단축키. 읽기에 실패하면 빈 목록이다 — 막는 쪽으로 틀리면 단축키 기능이 통째로 죽고,
    /// 빈 목록이면 그 순간 겹침만 못 보는 예전 동작으로 돌아간다.
    static func enabled() -> [WorkShortcut] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == OSStatus(noErr),
              let items = array?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return shortcuts(fromSymbolicHotKeys: items)
    }

    /// `CopySymbolicHotKeys` 항목 → 조합. 순수 함수라 테스트가 합성 항목으로 직접 묻는다.
    /// - 꺼진 항목은 버린다(사용자가 끈 시스템 단축키는 우리가 가져가도 된다).
    /// - 키 코드 0xFFFF(키 없음)는 버린다.
    /// - 수식키는 ⌃⌥⇧⌘ 네 비트만 남긴다 — fn(0x20000) 같은 나머지 비트는 버리되 **항목은 버리지 않는다**.
    ///   화살표·F키 항목은 fn 비트를 달고 오는데, 기록기는 fn 을 버린 값을 저장하므로 fn 째로 비교하면 영영 겹치지 않는다.
    static func shortcuts(fromSymbolicHotKeys items: [[String: Any]]) -> [WorkShortcut] {
        items.compactMap { item in
            guard (item["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                  let code = item["kHISymbolicHotKeyCode"] as? Int,
                  (0..<noKeyCode).contains(code),
                  let modifiers = item["kHISymbolicHotKeyModifiers"] as? Int
            else { return nil }
            return WorkShortcut(
                keyCode: UInt32(code),
                carbonModifiers: UInt32(truncatingIfNeeded: modifiers) & comparableModifierMask
            )
        }
    }
}

// MARK: - 등록 상태

/// 전역 등록의 결과. 설정 화면이 이 값으로 상태 한 줄을 고른다.
enum WorkShortcutStatus: Equatable, Sendable {
    /// 등록돼 있다(누르면 근무가 토글된다).
    case active
    /// 사용자가 스위치를 껐다.
    case off
    /// 설정 창에서 새 조합을 기록하는 중이라 잠시 내렸다 — 지금 조합을 다시 눌러 지정할 때 근무가 토글되면 안 된다.
    case paused
    /// 켜진 **macOS 시스템 단축키**와 같은 조합이라 걸지 않았다(`WorkShortcutSystemHotKeys`). 다른 앱과의 겹침은
    /// 여기 오지 않는다 — 등록이 noErr 로 성공해 버려서 알 방법이 없다.
    case conflict
    /// 등록 실패(OSStatus 그대로). `eventHotKeyExistsErr`(-9878)도 여기다: 같은 프로세스 안의 중복이거나 독점 등록끼리일
    /// 때만 오는 값이라, 새로 걸기 전에 먼저 푸는 등록기(`CarbonWorkShortcutRegistrar.register`)에선 생기지 않는다.
    case failed(Int32)
}

// MARK: - 등록기

/// 전역 핫키를 실제로 거는 쪽. **테스트는 가짜만 쓴다** — 테스트 프로세스가 진짜 전역 키를 잡으면
/// 스위트를 도는 동안 개발자 맥의 ⌃⌥⌘Space 를 훔친다.
@MainActor
protocol WorkShortcutRegistrar: AnyObject {
    var onPressed: (@MainActor () -> Void)? { get set }
    /// 조합을 건다(이미 걸린 것이 있으면 갈아 끼운다). 결과 OSStatus 를 그대로 돌려준다.
    func register(_ shortcut: WorkShortcut) -> OSStatus
    /// 건 것을 푼다(멱등).
    func unregister()
}

/// Carbon 핫키 등록기. 프로덕션에서 **AppDelegate 한 곳**만 만든다(소스 계약 테스트가 센다).
@MainActor
final class CarbonWorkShortcutRegistrar: WorkShortcutRegistrar {
    /// 우리 핫키의 서명 'CHKW'. 같은 앱 대상(application target)에 다른 핫키가 생겨도 이 서명·id 가 맞을 때만 반응한다.
    nonisolated static let signature: OSType = {
        "CHKW".utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()
    nonisolated static let hotKeyIdentifier: UInt32 = 1

    var onPressed: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {}

    func register(_ shortcut: WorkShortcut) -> OSStatus {
        // 처리기가 없으면 등록은 성공해도 눌러서 아무 일도 안 일어난다 — 그건 '등록 실패'로 보고해야 정직하다.
        let handlerStatus = installEventHandlerOnce()
        guard handlerStatus == OSStatus(noErr) else { return handlerStatus }
        // 걸기 **전에** 푼다. 안 풀면 같은 조합은 같은 프로세스 중복이라 eventHotKeyExistsErr(-9878)로 실패하고,
        // 다른 조합은 옛 조합이 풀리지 않은 채 남아(참조만 덮여 영영 못 푼다) 두 키가 다 근무를 토글한다.
        unregister()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyIdentifier),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == OSStatus(noErr) { hotKeyRef = ref }
        return status
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// 처리기는 이 등록기에 **한 번만** 건다. 같은 처리기·userData 로 다시 걸면 `eventHandlerAlreadyInstalledErr`(-9866)로
    /// 거부돼, 그 실패가 그대로 조합 변경(register)의 실패가 된다.
    /// 또 등록기 인스턴스가 둘이면 나중에 건 처리기가 먼저 불려 noErr 로 이벤트를 먹어, 앞의 것은 영영 못 받는다 —
    /// 프로덕션 인스턴스가 **하나**여야 하는 이유다(AppDelegate 한 곳, 소스 계약 테스트가 센다).
    ///
    /// userData 로 self 를 **소유권 없이**(passUnretained) 넘긴다. 이 등록기는 조정자가 붙들고, 조정자는 AppDelegate 가
    /// 앱 수명 동안 붙든다 — 처리기를 떼는 경로가 없는 대신 등록기도 앱보다 먼저 죽지 않는다는 가정이다.
    /// 이 등록기를 앱 수명보다 짧게 쓰려면 `RemoveEventHandler` 부터 만들어라(안 그러면 해제된 주소를 부른다).
    private func installEventHandlerOnce() -> OSStatus {
        guard eventHandlerRef == nil else { return OSStatus(noErr) }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(
            GetApplicationEventTarget(),
            carbonWorkShortcutEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}

/// Carbon 이벤트 처리기(C 함수 포인터라 캡처 없는 전역 함수여야 한다).
/// 핫키 이벤트는 앱 이벤트 대상에 붙어 **메인 스레드의 이벤트 루프**에서 온다 — 그래서 MainActor 로 가정한다.
private func carbonWorkShortcutEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    // 서명·id 가 우리 것일 때만 반응한다 — 아니면 다음 처리기에게 넘긴다.
    guard status == OSStatus(noErr),
          hotKeyID.signature == CarbonWorkShortcutRegistrar.signature,
          hotKeyID.id == CarbonWorkShortcutRegistrar.hotKeyIdentifier
    else { return OSStatus(eventNotHandledErr) }
    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<CarbonWorkShortcutRegistrar>.fromOpaque(pointer).takeUnretainedValue().onPressed?()
    }
    return OSStatus(noErr)
}

// MARK: - 조정자

/// 스토어의 설정 ↔ 전역 등록 ↔ 누름을 잇는 단 하나의 지점.
///
/// ★ 누름의 뜻은 팝오버 근무 알약(`WorkTogglePill(enabled: store.canSync, action: { store.toggle() })`)과 **같다** —
///   알약에 실제로 손이 닿는 조건(`store.canToggleWorkByShortcut`: 로그인·팀 있음이라 HeaderCard 가 그려지고, 그 위에서
///   canSync)에서 같은 동작(toggle)만 한다. 단축키만의 판정을 따로 만들면 알약은 막히는데(또는 아예 안 보이는데) 키는
///   되는 화면이 생긴다 — canSync 하나만 보던 때 로그아웃 상태의 누름이 서버에 안 가는 로컬 근무를, 무소속의 누름이 영속
///   큐의 start 항목을 남겼다.
@MainActor
final class WorkShortcutCoordinator {
    /// 연타 가드. 누르고 나서 화면에 바로 보이는 것이 없으니(메뉴바를 안 연다) 사람은 "안 먹었나?" 싶어 한 번 더 누른다 —
    /// 그러면 시작하자마자 종료된다(근무 0초 세션). 1.5초는 두 번째 누름이 '확인차'인 창이다.
    static let repeatGuardSeconds: TimeInterval = 1.5

    private let store: WorkTimerStore
    private let registrar: WorkShortcutRegistrar
    private let clock: () -> Date
    /// 지금 켜진 macOS 시스템 단축키. 프로덕션은 `WorkShortcutSystemHotKeys.enabled` 를 **apply 마다 새로** 읽는다 —
    /// 사용자가 시스템 설정에서 겹치는 단축키를 끄면 다음 apply(설정 창을 열 때의 재판정 등)에 풀린다. 테스트는 목록을 주입한다.
    private let systemHotKeys: () -> [WorkShortcut]
    private let onRejected: @MainActor () -> Void
    /// 마지막으로 **실제로 토글한** 누름의 시각. 거부된 누름은 여기를 안 바꾼다 — 바꾸면 거부 직후
    /// 조건이 풀려도 1.5초 동안 키가 먹통이 된다.
    private var lastToggledAt: Date?

    init(
        store: WorkTimerStore,
        registrar: WorkShortcutRegistrar,
        clock: @escaping () -> Date = { Date() },
        systemHotKeys: @escaping () -> [WorkShortcut] = WorkShortcutSystemHotKeys.enabled,
        onRejected: @escaping @MainActor () -> Void = { NSSound.beep() }
    ) {
        self.store = store
        self.registrar = registrar
        self.clock = clock
        self.systemHotKeys = systemHotKeys
        self.onRejected = onRejected
        // 등록기·스토어가 이 조정자를 강하게 잡으면 조정자 → 등록기 → 클로저 → 조정자 순환이 된다.
        registrar.onPressed = { [weak self] in self?.handlePress() }
        store.onWorkShortcutSettingsChanged = { [weak self] in self?.apply() }
    }

    /// 스토어의 설정을 전역 등록에 반영한다. 설정이 바뀔 때마다(스토어 세터가), 설정 창의 재판정 요청 때, 앱 시작 때 부른다.
    func apply() {
        let next: WorkShortcutStatus
        if !store.workShortcutEnabled {
            registrar.unregister()
            next = .off
        } else if store.isRecordingWorkShortcut {
            // 기록 중에는 내린다 — 지금 조합을 다시 눌러 지정하는 순간 근무가 토글되면 안 되고,
            // 내려야 그 keyDown 이 기록기(로컬 모니터)에 닿는다.
            registrar.unregister()
            next = .paused
        } else if systemHotKeys().contains(store.workShortcut) {
            // 켜진 macOS 단축키와 같은 조합은 **걸지 않는다**. 걸면 등록은 noErr 인데 한 번 누를 때 시스템 동작과 근무 토글이
            // 둘 다 일어난다(⌃⌥Space 라면 한/영을 바꿀 때마다 근무가 토글된다). 이미 걸려 있던 것도 푼다 — 설정 화면이
            // '겹쳐요'라고 말하는 동안 그 키가 여전히 근무를 토글하면 안 된다.
            registrar.unregister()
            next = .conflict
        } else {
            let status = registrar.register(store.workShortcut)
            next = status == OSStatus(noErr) ? .active : .failed(status)
        }
        // 같은 값을 다시 대입하면 설정 화면이 헛되이 다시 그려진다.
        if store.workShortcutStatus != next { store.workShortcutStatus = next }
    }

    /// 전역 핫키가 눌렸다.
    func handlePress() {
        let now = clock()
        // 시계가 뒤로 간 경우(수동 시각 변경)는 가드로 치지 않는다 — 음수 간격을 '1.5초 안'으로 읽으면
        // 되돌린 만큼 키가 먹통이 된다.
        if let lastToggledAt {
            let elapsed = now.timeIntervalSince(lastToggledAt)
            if elapsed >= 0, elapsed < Self.repeatGuardSeconds { return }
        }
        guard store.canToggleWorkByShortcut else {
            // 알약이 흐리게 막히거나(canSync) 아예 그려지지 않는(로그아웃 · 무소속) 조건이다.
            // 키는 흐리게 보일 자리가 없으니 소리로 알린다.
            onRejected()
            return
        }
        store.toggle()
        lastToggledAt = now
    }
}

// MARK: - 기록기 (설정 창에서 새 조합 받기)

/// 기록 중 keyDown 하나의 판정. **순수 함수**라 테스트가 합성 이벤트 없이 직접 묻는다.
enum WorkShortcutRecorder {
    enum Outcome: Equatable {
        case cancel
        /// 모양이 전역으로 못 가는 조합(수식키 모자람 · 수식키 자체 · 수식키 붙은 Esc).
        case rejected
        /// 모양은 허용되지만(`isAllowed`) 켜진 macOS 시스템 단축키와 같다.
        case rejectedSystem
        case accepted(WorkShortcut)
    }

    /// 기록 중 거절의 까닭. 안내 문구가 갈린다(`WorkShortcutRecorderNotice`).
    enum Rejection: Equatable, Sendable {
        /// ⌃⌥⌘ 중 두 개 이상이 아니다.
        case shape
        /// macOS 단축키와 겹친다.
        case system
    }

    /// 기록을 시작한 뒤 이만큼 아무 조합도 수락되지 않으면 기록을 끝낸다(거절된 입력마다 다시 잰다). 기록 중에는 전역
    /// 등록이 내려가 있어서, 끝나는 문이 하나라도 막히면 **앱을 다시 켤 때까지 전역 단축키가 멈춘다** — 이 시간 초과가
    /// 마지막 안전망이다.
    static let recordingTimeoutSeconds: TimeInterval = 15

    /// - Parameter systemHotKeys: 켜진 macOS 시스템 단축키(기록 세션이 시작할 때 한 번 읽은 것). **기본값을 두지 않는다** —
    ///   빠뜨린 호출부가 시스템 단축키를 조용히 수락하는 길이 되지 않게.
    static func evaluate(keyCode: UInt16, flags: NSEvent.ModifierFlags, systemHotKeys: [WorkShortcut]) -> Outcome {
        // ⌃⌥⌘ 없이 누른 Esc 만 취소다(⇧ 는 세지 않는다). ⌃⌥+Esc 같은 것은 조합 시도로 보고 거절한다 —
        // 그걸 취소로 읽으면 조합을 고르던 사람의 기록이 안내 없이 끝나 "눌렀는데 아무것도 안 바뀌었다"가 된다.
        if keyCode == WorkShortcut.escapeKeyCode, flags.intersection([.control, .option, .command]).isEmpty {
            return .cancel
        }
        guard let shortcut = WorkShortcut(keyCode: keyCode, flags: flags), shortcut.isAllowed else {
            return .rejected
        }
        // 수락하면 저장은 되지만 조정자가 걸지 않아(.conflict) '방금 고른 키가 안 먹는' 채로 기록이 끝난다.
        // 기록 중에 거절해야 사람이 그 자리에서 다른 조합을 누른다.
        guard !systemHotKeys.contains(shortcut) else { return .rejectedSystem }
        return .accepted(shortcut)
    }
}

/// 기록 한 번의 수명(로컬 키 모니터 · 앱 비활성 관찰 · 시간 초과 · 거절 안내). 뷰가 아니라 **바깥 객체**로 둔 이유:
/// 기록을 끝내는 문이 뷰 밖에도 있다 — 설정 창 컨트롤러의 `close()`·창 닫힘 델리게이트는 `onDisappear` 가
/// 안 오는 AppKit 경로(orderOut 뒤에도 뷰가 산다)를 대신 닫아야 하는데, 뷰의 @State 에는 손이 안 닿는다.
@MainActor
@Observable
final class WorkShortcutRecordingSession {
    /// 앱이 쓰는 하나(설정 화면 기본값 · 설정 창 컨트롤러 기본값). 테스트는 자기 인스턴스를 만든다.
    static let shared = WorkShortcutRecordingSession()

    /// 이번 기록에서 마지막 입력이 거절된 까닭(안내 문구를 바꾼다). 거절이 없었거나 기록이 끝나면 nil.
    private(set) var lastRejection: WorkShortcutRecorder.Rejection?

    /// 마지막 입력이 (어떤 까닭으로든) 거절됐는가.
    var lastAttemptRejected: Bool { lastRejection != nil }

    /// 시간 초과(초). 프로덕션은 언제나 `WorkShortcutRecorder.recordingTimeoutSeconds`, 테스트만 짧게 주입한다 —
    /// 주입 지점이 없으면 시간 초과를 통째로 지워도 스위트가 초록이다.
    @ObservationIgnored let timeoutSeconds: TimeInterval
    /// 켜진 macOS 시스템 단축키를 읽는 문. 프로덕션은 `WorkShortcutSystemHotKeys.enabled`, 테스트는 목록을 주입한다
    /// (주입하지 않으면 이 맥의 시스템 설정이 판정을 흔든다).
    @ObservationIgnored private let systemHotKeys: () -> [WorkShortcut]
    /// 앱 비활성 알림을 받을 센터. 프로덕션은 AppKit 이 `didResignActiveNotification` 을 보내는 `.default`, 테스트는
    /// 자기 센터를 넣는다 — 테스트 프로세스의 활성 전환이 다른 테스트의 기록을 끝내지 않게.
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private weak var store: WorkTimerStore?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignActiveObserver: NSObjectProtocol?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    /// 이번 기록 동안 대조할 시스템 단축키(begin 에서 한 번 읽는다 — 키마다 시스템에 다시 물을 까닭이 없다).
    @ObservationIgnored private var systemHotKeysWhileRecording: [WorkShortcut] = []

    init(
        timeoutSeconds: TimeInterval = WorkShortcutRecorder.recordingTimeoutSeconds,
        systemHotKeys: @escaping () -> [WorkShortcut] = WorkShortcutSystemHotKeys.enabled,
        notificationCenter: NotificationCenter = .default
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.systemHotKeys = systemHotKeys
        self.notificationCenter = notificationCenter
    }

    /// 로컬 키 모니터가 걸려 있는가(헤드리스 검증 지점).
    var isMonitorInstalled: Bool { monitor != nil }

    /// 앱 비활성 관찰이 걸려 있는가(헤드리스 검증 지점).
    var isObservingResignActive: Bool { resignActiveObserver != nil }

    /// 기록을 시작한다.
    ///
    /// ★ 스위치가 꺼져 있으면 **아무것도 안 한다**(깃발·모니터·관찰 없음). 꺼진 키캡은 흐리게 막혀 있지만(`.disabled`),
    ///   그 한 줄에만 기대면 꺼진 스위치 아래에 '새 조합을 누르세요'가 뜨고 어떤 키도 받지 않는(첫 키에 조용히 끝나는)
    ///   기록이 생긴다.
    /// ★ 모니터·관찰은 **언제나 떼고 다시 건다**(멱등 가드 금지). AppKit 창은 orderOut 뒤에도 뷰가 살아 `onDisappear` 가
    ///   안 오는 경로가 있어, '이미 걸려 있으면 그대로'로 두면 죽은 기록을 쥔 모니터가 남는다(MiniGameSpaceKey 의 실사고).
    /// ★ `isKeyWindow` 로 거르지 않는다. 로컬 모니터는 우리 앱이 활성일 때만 오고, 창을 막 연 순간에는 키 창이
    ///   아직 안 넘어와 있어 그 게이트가 첫 입력을 죽인다.
    /// ★ 앱이 비활성이 되면 끝낸다. 로컬 모니터는 우리 앱이 활성일 때만 듣고 전역 등록은 기록 중이라 내려가 있어서,
    ///   기록 중에 다른 앱으로 넘어가면 시간 초과까지(최대 15초) 단축키가 어디서도 안 먹는다.
    func begin(store: WorkTimerStore) {
        guard store.workShortcutEnabled else { return }
        removeMonitor()
        removeResignActiveObserver()
        timeoutTask?.cancel()
        self.store = store
        lastRejection = nil
        systemHotKeysWhileRecording = systemHotKeys()
        store.setRecordingWorkShortcut(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated { () -> Bool in
                self?.handleKeyDown(keyCode: keyCode, flags: flags) ?? false
            }
            return consumed ? nil : event
        }
        resignActiveObserver = notificationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // AppKit 은 이 알림을 메인 스레드에서 보낸다 — 그 자리에서 끝내야 넘어간 앱에서 누르는 첫 키부터 전역 등록이 받는다.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.end() }
            } else {
                Task { @MainActor in self?.end() }
            }
        }
        armTimeout()
    }

    /// keyDown 하나를 처리한다. 반환값 = 삼켰는가. 기록 중에는 **전부 삼킨다** — 흘리면 설정 창의 스위치·버튼이
    /// 스페이스/리턴에 눌리고, 조합 시도가 그대로 다른 동작이 된다.
    @discardableResult
    func handleKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard let store, store.isRecordingWorkShortcut, store.workShortcutEnabled else {
            // 기록이 다른 문(스위치 끄기·창 닫기)으로 이미 끝났는데 모니터만 남았다. 흘려보내고 치운다.
            end()
            return false
        }
        switch WorkShortcutRecorder.evaluate(keyCode: keyCode, flags: flags, systemHotKeys: systemHotKeysWhileRecording) {
        case .cancel:
            end()
        case .rejected:
            reject(.shape)
        case .rejectedSystem:
            reject(.system)
        case .accepted(let shortcut):
            store.setWorkShortcut(shortcut)
            end()
        }
        return true
    }

    /// 기록을 끝낸다(멱등). 모니터·관찰·시간 초과를 걷고, 스토어의 기록 깃발을 내려 전역 등록을 되살린다.
    func end() {
        timeoutTask?.cancel()
        timeoutTask = nil
        removeMonitor()
        removeResignActiveObserver()
        if lastRejection != nil { lastRejection = nil }
        store?.setRecordingWorkShortcut(false)
    }

    /// 거절을 안내하고 시간 초과를 **다시 건다** — 여러 번 시도하는 사람의 기록이 첫 시작으로부터 15초에 안내 없이
    /// 끊기지 않게(끊기면 방금 본 '다시 눌러 주세요'를 따라 누른 키가 아무 일도 안 한다).
    private func reject(_ reason: WorkShortcutRecorder.Rejection) {
        if lastRejection != reason { lastRejection = reason }
        armTimeout()
    }

    /// 시간 초과를 (다시) 건다. 앞의 타이머는 취소한다.
    private func armTimeout() {
        timeoutTask?.cancel()
        let delay = timeoutSeconds
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // 취소 검사가 없으면 cancel() 이 곧 즉시 종료다 — 다시 시작한(또는 다시 건) 기록을 옛 타이머가 끝내 버린다.
            guard !Task.isCancelled else { return }
            self?.end()
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func removeResignActiveObserver() {
        if let resignActiveObserver { notificationCenter.removeObserver(resignActiveObserver) }
        resignActiveObserver = nil
    }
}
