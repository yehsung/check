import AppKit
import CoreGraphics
import QuartzCore

// 캐릭터 패널이 "모든 Space" 소속을 잃는 고장(2026-11-22 대표 맥 실측)의 감지 도구.
//
// 실측: 0.3.87 프로세스(3.5일째)의 캐릭터 창은 Space 12개 중 2개([데스크톱 4, IAMCEO 817])에만 소속돼 있었고,
// 설정이 같은 할 일 보드 창은 12개 전부에 있었다. 나머지 전체 화면 Space(크롬·Aside·Ghostty…)에는 캐릭터 창이
// **통째로 없어서** [캐릭터 표시]·찌르기·울트라가 전부 같은 창을 올리기만 하고 아무것도 안 보였다. 내렸다 올리기로는
// 안 낫고(실측), 앱을 다시 켜야(=창을 새로 만들어야) 나았다. 이 파일은 그 상태를 **읽기만** 한다.
//
// 근거 프로브(알파 0 · 클릭 통과 · 캡처 제외 패널, 같은 맥에서 2026-11-22 17:45~18:05 KST):
//  · 한 번도 올린 적 없는 새 패널은 SkyLight 가 `[]` 를 돌려준다(첫 커밋 뒤 25~55ms 에 12/12). 그래서 "빈 목록"만으로는
//    절대 판정하지 않는다 — 공개 신호(`isOnActiveSpace`)가 그때 true 라 아래 교차 확인이 막는다.
//  · `isOnActiveSpace` 는 측정한 모든 상태에서 정직했다(망가진 창은 올려 둔 채로도, 내려 둔 채로도 false).
//  · `NSWindow.windowNumbers(options: [])` 는 올려 둔 창에 대해서만 뜻이 있다(내려 둔 창은 언제나 빠진다).
//  · `occlusionState` 는 알파 0 에서 한 번도 `.visible` 이 아니었고, SCNView 프레임 수는 Space 밖에서도 그대로였다 —
//    둘 다 이 고장의 신호가 못 된다.

/// 캐릭터 패널의 Space 소속 판정.
///
/// 재생성(수리)의 근거는 **`.missingCurrentSpace` 하나뿐이다**(반론 D2). "그 화면의 Space 전부보다 적다"는
/// `.onCurrentSpace(memberCount:displaySpaceCount:)` 의 두 숫자로 진단 로그에만 남는다 — 지금 Space 에 있는 창은 지금 보인다.
enum OverlaySpacePresence: Equatable, Sendable {
    /// 지금 그 화면의 Space 에 있다. 숫자가 nil 이면 SkyLight 가 없어 공개 신호만으로 판정한 것이다.
    case onCurrentSpace(memberCount: Int?, displaySpaceCount: Int?)
    /// 지금 그 화면의 Space 에 없다. 값이 nil 이면 SkyLight 가 없어 공개 신호만으로 판정한 것이다.
    case missingCurrentSpace(spaces: [UInt64]?, current: UInt64?)

    var isMissing: Bool {
        if case .missingCurrentSpace = self { return true }
        return false
    }

    var memberCount: Int? {
        switch self {
        case .onCurrentSpace(let count, _): return count
        case .missingCurrentSpace(let spaces, _): return spaces?.count
        }
    }

    /// 진단 로그용 "소속 수/그 화면 Space 수"(모르면 ?).
    func membershipText(displaySpaceCount: Int?) -> String {
        "\(memberCount.map(String.init) ?? "?")/\(displaySpaceCount.map(String.init) ?? "?")"
    }
}

/// SkyLight 읽기 질의(비공개, `dlopen`/`dlsym` 1회). 심볼이 하나라도 없으면 아무것도 묻지 않는다.
///
/// **읽기 전용이다.** 이 파일에는 윈도우 서버에 쓰는 호출이 없다(수리는 AppKit 공개 API 로만 한다 —
/// `OverlayPanelRepair` · `CheckOverlayController.rebuildPanel`). 맥 앱스토어판은 이미 은퇴했고 Developer ID 배포라
/// 시스템 프레임워크 `dlopen` 은 라이브러리 검증 대상이 아니다. 미래 macOS 에서 심볼이 사라지면 공개 신호만으로 돈다.
enum OverlaySpaceProbe {
    typealias MainConnection = @convention(c) () -> Int32
    typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias CopyManagedDisplayForWindow = @convention(c) (Int32, UInt32) -> Unmanaged<CFString>?
    typealias ManagedDisplayGetCurrentSpace = @convention(c) (Int32, CFString) -> UInt64
    typealias GetActiveSpace = @convention(c) (Int32) -> UInt64
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias WindowQueryWindows = @convention(c) (Int32, CFArray, UInt32) -> Unmanaged<CFTypeRef>?
    typealias WindowQueryResultCopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    typealias WindowIteratorAdvance = @convention(c) (CFTypeRef) -> Bool
    typealias WindowIteratorGetTags = @convention(c) (CFTypeRef) -> UInt64

    /// 윈도우 서버 창 태그의 "모든 Space"(sticky) 비트. 실측: 정상 패널·대표 맥의 망가진 창 둘 다 서 있었다 —
    /// 대표 맥의 고장은 "sticky 를 잃음"이 아니라 "소속 목록만 잃음"이었다(진단 로그가 둘을 가른다).
    static let stickyTagBit: UInt64 = 1 << 11

    struct Symbols: @unchecked Sendable {
        let mainConnection: MainConnection
        let copySpacesForWindows: CopySpacesForWindows
        let copyManagedDisplayForWindow: CopyManagedDisplayForWindow
        let managedDisplayGetCurrentSpace: ManagedDisplayGetCurrentSpace
        let getActiveSpace: GetActiveSpace
        let copyManagedDisplaySpaces: CopyManagedDisplaySpaces
        // 진단 전용(없어도 판정은 돈다). `SLSGetWindowTags` 가 아니라 반복자 경로다 — 실측: 그쪽은 다른 연결의 창을
        // 0 으로 읽는다. 자기 창은 둘 다 맞지만 같은 도구를 밖에서 읽는 프로브와 맞춰 둔다.
        let queryWindows: WindowQueryWindows?
        let queryResultCopyWindows: WindowQueryResultCopyWindows?
        let iteratorAdvance: WindowIteratorAdvance?
        let iteratorGetTags: WindowIteratorGetTags?
    }

    /// 1회만 연다(지연 `static let` — 스레드 안전 초기화). nil = 심볼 없음.
    static let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
            return nil
        }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let main = symbol("SLSMainConnectionID", MainConnection.self),
              let copySpaces = symbol("SLSCopySpacesForWindows", CopySpacesForWindows.self),
              let displayForWindow = symbol("SLSCopyManagedDisplayForWindow", CopyManagedDisplayForWindow.self),
              let currentSpace = symbol("SLSManagedDisplayGetCurrentSpace", ManagedDisplayGetCurrentSpace.self),
              let activeSpace = symbol("SLSGetActiveSpace", GetActiveSpace.self),
              let managedSpaces = symbol("SLSCopyManagedDisplaySpaces", CopyManagedDisplaySpaces.self)
        else { return nil }
        return Symbols(
            mainConnection: main,
            copySpacesForWindows: copySpaces,
            copyManagedDisplayForWindow: displayForWindow,
            managedDisplayGetCurrentSpace: currentSpace,
            getActiveSpace: activeSpace,
            copyManagedDisplaySpaces: managedSpaces,
            queryWindows: symbol("SLSWindowQueryWindows", WindowQueryWindows.self),
            queryResultCopyWindows: symbol("SLSWindowQueryResultCopyWindows", WindowQueryResultCopyWindows.self),
            iteratorAdvance: symbol("SLSWindowIteratorAdvance", WindowIteratorAdvance.self),
            iteratorGetTags: symbol("SLSWindowIteratorGetTags", WindowIteratorGetTags.self)
        )
    }()

    static var skyLightAvailable: Bool { symbols != nil }

    /// SkyLight 가 본 한 창의 소속.
    struct SkyLightReading: Equatable, Sendable {
        /// 창이 속한 Space 들(`SLSCopySpacesForWindows`, 마스크 7).
        let spaces: [UInt64]
        /// **그 창이 놓인 화면**에 지금 보이는 Space(다중 모니터에서도 창의 화면 기준). 화면을 못 찾으면 활성 Space.
        let current: UInt64
        /// 그 화면의 Space 수(진단 전용).
        let displaySpaceCount: Int?
    }

    /// 한 창의 소속을 SkyLight 에 묻는다. 질의가 실패하거나 현재 Space 를 모르면 nil(= 모름).
    ///
    /// ⚠️ 존재하지 않는 창 번호에도 화면은 메인으로, 소속은 `[]` 로 답한다(설계 §1.1 의 함정). 그래서 이 값 하나로
    /// 판정하지 않는다 — 호출자가 `windowNumber > 0` 을 보고, 공개 신호와 교차 확인한다.
    static func skyLightReading(windowNumber wid: Int) -> SkyLightReading? {
        guard let sy = symbols, wid > 0 else { return nil }
        let cid = sy.mainConnection()
        guard let raw = sy.copySpacesForWindows(cid, 7, [NSNumber(value: wid)] as CFArray)?.takeRetainedValue(),
              let numbers = raw as? [NSNumber]
        else { return nil }
        let display = sy.copyManagedDisplayForWindow(cid, UInt32(wid))?.takeRetainedValue() as String?
        let current = display.map { sy.managedDisplayGetCurrentSpace(cid, $0 as CFString) } ?? sy.getActiveSpace(cid)
        guard current != 0 else { return nil }
        var count: Int?
        if let managed = sy.copyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] {
            let entry = managed.first { ($0["Display Identifier"] as? String) == display } ?? managed.first
            count = (entry?["Spaces"] as? [Any])?.count
        }
        return SkyLightReading(spaces: numbers.map(\.uint64Value), current: current, displaySpaceCount: count)
    }

    /// 자기 창의 sticky 비트(진단 전용). 심볼이 없거나 질의가 실패하면 nil.
    static func stickyTag(windowNumber wid: Int) -> Bool? {
        guard let sy = symbols, wid > 0,
              let query = sy.queryWindows, let copy = sy.queryResultCopyWindows,
              let advance = sy.iteratorAdvance, let tags = sy.iteratorGetTags,
              let result = query(sy.mainConnection(), [NSNumber(value: wid)] as CFArray, 0)?.takeRetainedValue(),
              let iterator = copy(result)?.takeRetainedValue(),
              advance(iterator)
        else { return nil }
        return tags(iterator) & stickyTagBit != 0
    }

    /// 순수 판정 — 재생성 근거는 "현재 Space 가 빠졌다" 하나다(`[]` = v0.2.27 보드 모양도 여기 든다).
    static func evaluate(spaces: [UInt64], current: UInt64, displaySpaceCount: Int?) -> OverlaySpacePresence {
        spaces.contains(current)
            ? .onCurrentSpace(memberCount: spaces.count, displaySpaceCount: displaySpaceCount)
            : .missingCurrentSpace(spaces: spaces, current: current)
    }

    /// 공개 신호가 "지금 Space 에 없다"고 말하는가(순수 함수, 반론 D3).
    ///
    /// · `isOnActiveSpace` 가 true 면 언제나 아니다 — 한 번도 안 올린 새 패널도 true 라(문서: "올리면 활성 Space 에 놓일
    ///   창") 새 패널의 `[]` 를 고장으로 읽는 일(반론 D2)이 여기서 막힌다.
    /// · 올려 둔 창이면 `windowNumbers(options: [])`(활성 Space 의 내 창 목록)에서도 빠져야 한다(둘 다 정직했다).
    /// · 내려 둔 창은 그 목록에 언제나 없으므로 `isOnActiveSpace` 하나로 본다(실측: 망가진 채 내려 둔 창도 false).
    static func publicSaysMissing(isVisible: Bool, isOnActiveSpace: Bool, inActiveSpaceList: Bool) -> Bool {
        if isOnActiveSpace { return false }
        return isVisible ? !inActiveSpaceList : true
    }

    @MainActor
    static func publicSaysMissing(_ window: NSWindow) -> Bool {
        let inActiveList = (NSWindow.windowNumbers(options: []) ?? []).contains(NSNumber(value: window.windowNumber))
        return publicSaysMissing(
            isVisible: window.isVisible,
            isOnActiveSpace: window.isOnActiveSpace,
            inActiveSpaceList: inActiveList
        )
    }

    /// 비공개 판정과 공개 신호를 합친다(순수 함수).
    ///
    /// · SkyLight 가 없다 → 공개 신호만으로 판정한다(심볼이 사라진 미래 macOS 에서도 계속 돈다).
    /// · SkyLight 는 있는데 질의가 실패했다 → nil(모름 = 아무것도 안 한다).
    /// · 비공개가 "없음"인데 공개가 "있음"이면 nil — 둘이 엇갈리면 고치지 않는다(SkyLight 의미가 바뀐 미래의 오탐을 막는다).
    static func combine(skyLightAvailable: Bool, reading: SkyLightReading?, publicMissing: Bool) -> OverlaySpacePresence? {
        guard skyLightAvailable else {
            return publicMissing
                ? .missingCurrentSpace(spaces: nil, current: nil)
                : .onCurrentSpace(memberCount: nil, displaySpaceCount: nil)
        }
        guard let reading else { return nil }
        let verdict = evaluate(spaces: reading.spaces, current: reading.current, displaySpaceCount: reading.displaySpaceCount)
        if verdict.isMissing && !publicMissing { return nil }
        return verdict
    }

    /// 프로덕션 판정(`CheckOverlayController.spacePresence` 의 기본값). `windowNumber <= 0` 이면 nil.
    @MainActor
    static func presence(of window: NSWindow) -> OverlaySpacePresence? {
        let wid = window.windowNumber
        guard wid > 0 else { return nil }
        return combine(
            skyLightAvailable: skyLightAvailable,
            reading: skyLightReading(windowNumber: wid),
            publicMissing: publicSaysMissing(window)
        )
    }

    /// 진단용: 그 창이 놓인 화면의 Space 수(모르면 nil).
    static func displaySpaceCount(windowNumber wid: Int) -> Int? {
        skyLightReading(windowNumber: wid)?.displaySpaceCount
    }
}

/// 디스플레이가 깨어 있는가(설계 §3.3 H2). `.screensAsleep` 렌더 정지 사유를 깨움 노티 없이 걷어낼 근거다.
enum OverlayDisplayProbe {
    /// 활성 디스플레이가 하나 이상이고 그중 잠든 것이 없으면 true, 활성 디스플레이가 없거나 하나라도 자면 false,
    /// 질의가 실패하면 nil(= 모름 → 사유를 그대로 둔다).
    static func allActiveDisplaysAwake() -> Bool? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var filled: UInt32 = 0
        guard CGGetActiveDisplayList(count, &ids, &filled) == .success else { return nil }
        let active = ids.prefix(Int(filled))
        guard !active.isEmpty else { return false }
        return active.allSatisfy { CGDisplayIsAsleep($0) == 0 }
    }
}

/// 수리 사다리 1단(뷰 이동 없음 — AppKit 만). 실측: 망가진 네 모양(현재 Space 빠짐 · 현재 Space 포함 일부 · 빈 목록 ·
/// sticky 비트 지움) 모두에서 4/4 나았고, 내려 둔 창에서도 나아 표시 직전 수리로 쓸 수 있다.
@MainActor
enum OverlayPanelRepair {
    /// `collectionBehavior` 를 `[]` 로 내렸다가 원래 값으로 되돌린다.
    ///
    /// ★ **두 대입은 따로 커밋돼야 한다.** 같은 턴에 연달아 쓰면 AppKit 이 하나로 합쳐 아무 일도 없다(실측 4/4 실패).
    ///   `DispatchQueue.main.async` 로 미뤄도 커밋 전에 돌아 실패했고, 같은 값 재대입은 AppKit 이 건너뛴다.
    ///   `CATransaction.flush()` 로 첫 대입을 윈도우 서버에 내보낸 뒤 되돌리면 4/4 나았다.
    static func reapplyCollectionBehavior(_ panel: NSWindow) {
        let original = panel.collectionBehavior
        panel.collectionBehavior = []
        CATransaction.flush()
        panel.collectionBehavior = original
    }
}
