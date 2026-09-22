import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.23 근무 시작·종료 전역 단축키
//
// 사용자 확정(2026-09-15): 기본 ⌃⌥⌘Space, 설정에서 켜고 끄기 + 키 직접 바꾸기. 누르면 팝오버 근무 알약과
// **같은 조건·같은 동작(toggle)** 이다. 조건은 알약에 실제로 손이 닿는 것 — 키(canSync) · 로그인 · 팀 있음 — 이다.
//
// 이 파일이 지키는 것(전부 초록인 채로 틀릴 수 있는 자리다):
//  ① 조합 값: 기본값·표시·수식키 변환·허용 규칙·키 이름 표. 한 수식키 조합이 새면 이 맥의 모든 앱에서 ⌘C 가 죽는다.
//  ② 영속: 기본 켜짐·기본 조합, 바꾼 값의 재실행 생존, 깨진/허용 안 되는 저장값은 기본값으로.
//  ③ 조정자 apply: 켜짐·꺼짐·기록 중·조합 변경·macOS 단축키 겹침·실패가 등록과 상태에 그대로 비친다 + 시스템 단축키 목록 읽기 +
//     재판정 요청(설정 창 show · 행 onAppear).
//  ④ 누름: 알약과 같은 조건·같은 동작, 연타 가드 1.5초, 거부된 누름은 가드를 안 건다.
//  ⑤ 기록기: esc 취소 · 모양 거절 · macOS 단축키 겹침 거절 · 수락의 순수 판정과 기록 세션의 흐름(꺼진 스위치 거부 포함).
//  ⑥ 기록 종료: 설정 창 close() · 창 닫힘 델리게이트 · 앱 비활성 · 시간 초과(거절마다 재무장). 하나라도 빠지면 전역 단축키가 멈춘다.
//  ⑦ 소스 계약: 진짜 Carbon 등록기는 AppDelegate 한 곳(오버레이 뒤) · 권한이 필요한 키 감시 금지 · 설정 행 ·
//     단축키 게이트와 알약 게이트의 짝 · 등록기의 방어선(걸기 전 해제 · 서명/id 비교) · 꺼진 키캡.
//  ⑧ 렌더: 기록 행이 노란 상자(255,204,0) 없이 상태마다 제 색으로 그려진다.
//
// ⚠️ 진짜 Carbon 등록은 **한 번도** 하지 않는다 — 가짜 등록기만 쓴다. 테스트 프로세스가 실제 전역 키를 잡으면
//    스위트를 도는 동안 개발자 맥의 ⌃⌥⌘Space 를 훔친다. 시스템 단축키 목록은 **읽기만** 한다(systemHotKeyListParsing 한 곳).
// ⚠️ 조정자·기록 세션에는 시스템 단축키 목록과 알림 센터를 **언제나 주입한다**. 기본값(실제 목록 · `.default` 센터)을 쓰면
//    이 맥의 시스템 설정과 테스트 프로세스의 활성 전환이 판정을 흔든다.

/// ⌃⌥Space — macOS 가 기본으로 켜 두는 '이전 입력 소스 선택'(한/영 전환). 모양은 `isAllowed` 를 통과하는 시스템 단축키다.
private let v0323InputSourceSwitch = WorkShortcut(keyCode: 49, carbonModifiers: 4096 | 2048)

/// 테스트별 고정 이름의 격리 defaults(V0322Scratch 와 같은 규약 — UUID 스위트는 실행마다 빈 plist 를 쌓는다).
private final class V0323Scratch {
    let suiteName: String
    let defaults: UserDefaults

    init(_ test: String) {
        // 이름은 고정(테스트 신원)이라 개수가 유계지만, 그 이름 그대로면 ~/Library/Preferences 에
        // 항목이 생긴다 — 같은 이름을 $TMPDIR 절대 경로로 옮긴다(CheckTestScratch 주석의 2026-09-22 사고).
        suiteName = CheckTestScratch.suitePath(
            named: "check-v0323-shortcut.\(test.replacingOccurrences(of: "()", with: ""))")
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
    }
}

/// 가짜 등록기. `live` 는 "지금 전역에 걸려 있는 조합"이다 — 등록 성공이면 그 조합, 실패·해제면 nil.
@MainActor
private final class V0323FakeRegistrar: WorkShortcutRegistrar {
    var onPressed: (@MainActor () -> Void)?
    /// 다음 register 가 돌려줄 OSStatus.
    var nextStatus: OSStatus = 0
    private(set) var registerCalls: [WorkShortcut] = []
    private(set) var unregisterCalls = 0
    private(set) var live: WorkShortcut?

    func register(_ shortcut: WorkShortcut) -> OSStatus {
        registerCalls.append(shortcut)
        live = nextStatus == 0 ? shortcut : nil
        return nextStatus
    }

    func unregister() {
        unregisterCalls += 1
        live = nil
    }

    /// 창 서버가 핫키를 배달한 것과 같은 길(등록기의 onPressed)로 누른다.
    func press() { onPressed?() }
}

/// 네트워크를 전부 URLProtocolStub 으로 막은 스토어. 프로덕션 호출 없음.
/// `hasKey: false` 면 canSync 가 거짓이다(환경에 키가 없고, 테스트 프로세스의 메인 번들엔 CheckConfig.plist 가 없다 —
/// 호출부가 `#require(!canSync)` 로 한 번 더 확인한다).
@MainActor
private func v0323Store(defaults: UserDefaults, hasKey: Bool = true) -> WorkTimerStore {
    WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://v0323-shortcut-tests")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: hasKey ? ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"] : [:],
        defaults: defaults,
        workspaceNotifications: nil
    )
}

/// 가짜 등록기를 문 조정자. 시스템 단축키 목록은 주입한 것만 본다(기본 빈 목록).
@MainActor
private func v0323Coordinator(
    _ store: WorkTimerStore,
    _ registrar: V0323FakeRegistrar,
    system: @escaping () -> [WorkShortcut] = { [] }
) -> WorkShortcutCoordinator {
    WorkShortcutCoordinator(store: store, registrar: registrar, systemHotKeys: system, onRejected: {})
}

/// 기록 세션. 시스템 단축키 목록과 알림 센터를 주입한다(파일 머리 ⚠️).
@MainActor
private func v0323Session(
    timeout: TimeInterval = 60,
    system: [WorkShortcut] = [],
    center: NotificationCenter = NotificationCenter()
) -> WorkShortcutRecordingSession {
    WorkShortcutRecordingSession(timeoutSeconds: timeout, systemHotKeys: { system }, notificationCenter: center)
}

/// 실제 스토어 + 실제 조정자 + 가짜 등록기. 시계만 주입해 연타 가드를 결정적으로 돌린다(V0322 하네스와 같은 모양).
@MainActor
private final class V0323PressHarness {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    let scratch: V0323Scratch
    let store: WorkTimerStore
    let registrar = V0323FakeRegistrar()
    var rejectedCount = 0
    var coordinator: WorkShortcutCoordinator?

    /// 기본은 알약에 실제로 손이 닿는 상태(키 · 로그인 · 팀)다. 거부 테스트는 조건을 한 번에 하나씩만 뺀다 —
    /// 그래야 어느 게이트가 막았는지 읽힌다.
    init(_ test: String = #function, hasKey: Bool = true, signedIn: Bool = true, hasTeam: Bool = true) {
        scratch = V0323Scratch(test)
        store = v0323Store(defaults: scratch.defaults, hasKey: hasKey)
        if signedIn { signIn() }
        if hasTeam { joinTeam() }
        coordinator = WorkShortcutCoordinator(
            store: store,
            registrar: registrar,
            clock: { [weak self] in self?.now ?? .distantPast },
            systemHotKeys: { [] },
            onRejected: { [weak self] in self?.rejectedCount += 1 }
        )
        coordinator?.apply()
    }

    func signIn() {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    }

    func joinTeam() {
        store.currentTeamID = "10000000-0000-0000-0000-000000003230"
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    /// 스토어가 띄운 태스크를 회수한다(잔여 태스크 금지).
    func cleanup() {
        store.session = nil
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
        store.pokePollTask?.cancel()
        store.drainInFlight?.cancel()
    }
}

@MainActor
@Suite(.serialized)
struct V0323WorkShortcutTests {
    // MARK: ① 조합 값

    @Test("기본값은 ⌃⌥⌘Space 이고, 수식키 변환은 ⌃⌥⇧⌘ 만 옮기며, 한 수식키 조합은 전역으로 못 간다")
    func shortcutValueRules() throws {
        // Carbon 비트를 **숫자로** 못 박는다(controlKey 4096 · optionKey 2048 · shiftKey 512 · cmdKey 256).
        // 상수 이름으로만 비교하면 구현과 테스트가 같은 오타를 공유해도 초록이다.
        #expect(WorkShortcut.default.keyCode == 49)
        #expect(WorkShortcut.default.carbonModifiers == 4096 | 2048 | 256)
        #expect(WorkShortcut.default.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
        #expect(WorkShortcut.default.displayString == "⌃⌥⌘Space")
        #expect(WorkShortcut.default.spokenDescription == "Control Option Command Space")

        #expect(WorkShortcut.carbonModifiers(from: [.shift]) == 512, "⇧ 가 Carbon 비트로 안 옮겨졌다 — ⇧ 조합이 영영 발화하지 않는다")
        #expect(WorkShortcut.carbonModifiers(from: [.control]) == 4096)
        #expect(WorkShortcut.carbonModifiers(from: [.option]) == 2048)
        #expect(WorkShortcut.carbonModifiers(from: [.command]) == 256)
        #expect(WorkShortcut.carbonModifiers(from: [.control, .option, .shift, .command]) == 4096 | 2048 | 512 | 256)
        #expect(WorkShortcut.carbonModifiers(from: [.command, .capsLock, .function, .numericPad, .help]) == 256,
                "capsLock·fn·numericPad 가 섞였다 — capsLock 을 켠 채 기록한 조합이 끄는 순간 안 먹는다")

        func combo(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) throws -> WorkShortcut {
            try #require(WorkShortcut(keyCode: keyCode, flags: flags))
        }
        #expect(try !combo(8, [.command]).isAllowed, "⌘C 가 허용됐다 — 이 맥의 모든 앱에서 복사가 죽는다")
        #expect(try !combo(40, [.command, .shift]).isAllowed, "⌘⇧K 가 허용됐다 — ⇧ 는 수로 치지 않는다")
        #expect(try combo(40, [.control, .command]).isAllowed)
        #expect(try combo(49, [.control, .option, .command]).isAllowed)
        #expect(try !combo(53, [.control, .option, .command]).isAllowed, "Esc 조합이 허용됐다 — 기록을 끝낼 키가 사라진다")
        #expect(try !combo(40, []).isAllowed)

        for code in UInt16(54)...63 {
            #expect(WorkShortcut(keyCode: code, flags: [.control, .option]) == nil, "수식키 자체(\(code))가 조합의 키로 섰다")
        }
        #expect(WorkShortcut(keyCode: 64, flags: [.control, .option]) != nil, "수식키 범위 밖(F17)까지 거절한다")

        // 키 이름 표 — 입력 소스(한글/영문)와 무관한 ANSI 물리 키 코드에서 나온다.
        let names: [(UInt32, String)] = [
            (0, "A"), (11, "B"), (40, "K"), (6, "Z"),
            (29, "0"), (18, "1"), (25, "9"),
            (49, "Space"), (36, "↩"), (48, "⇥"), (51, "⌫"), (117, "⌦"),
            (123, "←"), (124, "→"), (126, "↑"), (125, "↓"),
            (122, "F1"), (120, "F2"), (111, "F12"), (105, "F13"), (90, "F20"),
            (27, "-"), (24, "="), (33, "["), (30, "]"), (42, "\\"), (41, ";"),
            (39, "'"), (43, ","), (47, "."), (44, "/"), (50, "`"),
            (53, "키 53"), (115, "키 115"),
        ]
        for (code, name) in names {
            #expect(WorkShortcut.keyName(for: code).symbol == name, "키 코드 \(code) 의 이름이 \(WorkShortcut.keyName(for: code).symbol) 다(기대 \(name))")
        }
        #expect(try combo(40, [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘K", "기호 순서가 macOS 메뉴(⌃⌥⇧⌘)와 다르다")
        #expect(try combo(123, [.control, .command]).spokenDescription == "Control Command Left Arrow")
    }

    // MARK: ② 영속

    @Test("기본은 켜짐·⌃⌥⌘Space 이고, 바꾼 조합과 끈 값은 다음 실행에도 남는다 — 기록 중 여부는 안 남는다")
    func settingsSurviveRelaunch() throws {
        let scratch = V0323Scratch(#function)
        let first = v0323Store(defaults: scratch.defaults)
        #expect(first.workShortcutEnabled, "기본값이 꺼짐이다 — 업데이트하는 순간 아무도 단축키를 못 쓴다")
        #expect(first.workShortcut == .default)
        #expect(first.workShortcutStatus == .off, "조정자가 붙기 전에는 등록된 적이 없다")
        #expect(!first.isRecordingWorkShortcut)

        let custom = try #require(WorkShortcut(keyCode: 40, flags: [.control, .command]))
        #expect(first.setWorkShortcut(custom))
        first.setWorkShortcutEnabled(false)
        first.setRecordingWorkShortcut(true)

        let relaunched = v0323Store(defaults: scratch.defaults)
        #expect(relaunched.workShortcut == custom, "바꾼 조합이 재실행에 사라졌다")
        #expect(!relaunched.workShortcutEnabled, "끈 값이 재실행에 되살아났다")
        #expect(!relaunched.isRecordingWorkShortcut, "기록 중이 저장됐다 — 다음 실행이 전역 단축키가 멈춘 채로 시작한다")

        // 허용 안 되는 조합은 세터가 **아무것도 안 바꾸고** 거절한다(기록기 밖의 경로도 막는 최종 관문).
        #expect(relaunched.setWorkShortcut(WorkShortcut(keyCode: 8, carbonModifiers: 256)) == false)
        #expect(relaunched.workShortcut == custom)
        #expect(v0323Store(defaults: scratch.defaults).workShortcut == custom, "거절된 조합이 저장소에 들어갔다")

        relaunched.resetWorkShortcut()
        relaunched.setWorkShortcutEnabled(true)
        let again = v0323Store(defaults: scratch.defaults)
        #expect(again.workShortcut == .default)
        #expect(again.workShortcutEnabled)

        // 키 이름을 못 박는다. 바꾸면 이미 바꾼 사람의 조합이 아무 말 없이 기본값으로 돌아간다.
        #expect(WorkTimerStore.workShortcutEnabledKey == "check.workShortcut.enabled")
        #expect(WorkTimerStore.workShortcutKey == "check.workShortcut.combo")
    }

    @Test("깨진 저장값과 허용 안 되는 저장값은 기본값으로 접힌다 — 허용되는 저장값은 그대로 산다(대조군)")
    func brokenOrForbiddenStoredValuesFallBackToDefault() throws {
        let scratch = V0323Scratch(#function)

        scratch.defaults.set(Data("not json".utf8), forKey: WorkTimerStore.workShortcutKey)
        #expect(v0323Store(defaults: scratch.defaults).workShortcut == .default, "깨진 Data 로 조합을 만들었다")

        let forbidden = try JSONEncoder().encode(WorkShortcut(keyCode: 8, carbonModifiers: 256))
        scratch.defaults.set(forbidden, forKey: WorkTimerStore.workShortcutKey)
        #expect(v0323Store(defaults: scratch.defaults).workShortcut == .default,
                "저장된 ⌘C 를 그대로 되살렸다 — 이 맥의 모든 앱에서 복사가 죽는다")

        // 대조군: 저장 형식(JSON 키 이름)까지 못 박는다 — 형식이 바뀌면 기존 사용자의 조합이 조용히 기본값으로 접힌다.
        scratch.defaults.set(Data(#"{"keyCode":40,"carbonModifiers":4352}"#.utf8), forKey: WorkTimerStore.workShortcutKey)
        #expect(v0323Store(defaults: scratch.defaults).workShortcut == WorkShortcut(keyCode: 40, carbonModifiers: 4096 | 256),
                "허용되는 저장값까지 기본값으로 접는다 — 위 두 단언이 '무조건 기본값'인 세계에서도 초록이 된다")
    }

    // MARK: ③ 조정자 apply

    @Test("조정자는 켜짐·꺼짐·기록 중·조합 변경·실패를 등록과 상태에 그대로 비추고, 스토어 세터가 그것을 부른다")
    func coordinatorApplyMirrorsSettings() throws {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        let coordinator = v0323Coordinator(store, fake)
        defer { withExtendedLifetime(coordinator) {} }

        #expect(fake.registerCalls.isEmpty, "init 만으로 등록했다 — 첫 등록은 AppDelegate 의 apply() 몫이다")
        coordinator.apply()
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == .default)

        // 꺼짐 — 여기서부터 apply 를 손으로 부르지 않는다(세터가 불러야 한다).
        store.setWorkShortcutEnabled(false)
        #expect(store.workShortcutStatus == .off)
        #expect(fake.live == nil, "끈 뒤에도 전역 키가 걸려 있다")
        let custom = try #require(WorkShortcut(keyCode: 40, flags: [.control, .command]))
        let callsWhileOff = fake.registerCalls.count
        store.setWorkShortcut(custom)
        #expect(fake.registerCalls.count == callsWhileOff, "꺼진 동안 조합을 바꿨더니 전역에 걸었다")
        #expect(fake.live == nil)

        store.setWorkShortcutEnabled(true)
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == custom, "켜면서 새 조합이 아니라 옛 조합을 걸었다")

        // 기록 중 — 내려야 지금 조합을 다시 눌러 지정할 때 근무가 토글되지 않는다.
        store.setRecordingWorkShortcut(true)
        #expect(store.workShortcutStatus == .paused)
        #expect(fake.live == nil, "기록 중인데 전역 키가 살아 있다 — 지금 조합을 다시 누르면 근무가 토글된다")
        store.setRecordingWorkShortcut(false)
        #expect(store.workShortcutStatus == .active, "기록이 끝났는데 전역 키가 안 돌아왔다")
        #expect(fake.live == custom)

        let other = try #require(WorkShortcut(keyCode: 96, flags: [.control, .option]))
        store.setWorkShortcut(other)
        #expect(fake.live == other, "조합을 바꿨는데 새 조합으로 다시 걸지 않았다")
        #expect(fake.registerCalls.last == other)

        // -9878(eventHotKeyExistsErr)은 '겹침'이 아니라 실패다. 다른 앱·시스템 단축키와 겹쳐도 이 값은 오지 않고(noErr),
        // 같은 프로세스 안의 중복일 때만 온다 — 겹침으로 안내하면 사실이 아닌 말을 한다.
        #expect(OSStatus(eventHotKeyExistsErr) == -9878)
        fake.nextStatus = -9878
        coordinator.apply()
        #expect(store.workShortcutStatus == .failed(-9878), "등록 실패(-9878)를 macOS 단축키 겹침으로 안내한다")
        fake.nextStatus = -50
        coordinator.apply()
        #expect(store.workShortcutStatus == .failed(-50))

        fake.nextStatus = 0
        store.resetWorkShortcut()
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == .default)

        // 같은 값 세터는 조정자를 흔들지 않는다(흔들면 핫키를 풀었다 다시 거는 사이 누른 키가 샌다).
        let settled = (fake.registerCalls.count, fake.unregisterCalls)
        store.setWorkShortcutEnabled(true)
        store.setRecordingWorkShortcut(false)
        store.setWorkShortcut(.default)
        #expect(fake.registerCalls.count == settled.0 && fake.unregisterCalls == settled.1)
    }

    @Test("켜진 macOS 단축키와 같은 조합은 걸지 않고 .conflict — 시스템 설정에서 끄면 재판정 요청에 다시 .active")
    func systemHotKeyOverlapIsNotRegistered() throws {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        var system: [WorkShortcut] = [.default]
        let coordinator = v0323Coordinator(store, fake, system: { system })
        defer { withExtendedLifetime(coordinator) {} }

        coordinator.apply()
        #expect(store.workShortcutStatus == .conflict, "macOS 단축키와 같은 조합인데 .conflict 가 아니다")
        #expect(fake.registerCalls.isEmpty, "macOS 단축키와 같은 조합을 걸었다 — 한 번 누르면 시스템 동작과 근무 토글이 둘 다 일어난다")
        #expect(fake.live == nil)

        // 사용자가 시스템 설정에서 그 단축키를 껐다 → 설정 창을 열 때(show · 행의 onAppear) 재판정을 요청한다.
        system = []
        store.requestWorkShortcutReapply()
        #expect(store.workShortcutStatus == .active, "시스템 단축키를 껐는데 재판정 요청이 단축키를 되살리지 않았다")
        #expect(fake.live == .default)

        // 걸려 있던 조합이 시스템 목록에 새로 들어오면(사용자가 켰다) 다음 재판정에서 **내린다**.
        system = [v0323InputSourceSwitch, .default]
        store.requestWorkShortcutReapply()
        #expect(store.workShortcutStatus == .conflict)
        #expect(fake.live == nil, "'겹쳐요'라고 안내하면서 옛 등록을 살려 뒀다 — 그 키가 여전히 근무를 토글한다")

        // 비교는 네 수식키 비트 그대로다: ⌃⌥Space 가 시스템 것이어도 ⌃⌥⌘Space 는 막히지 않는다(대조군).
        system = [v0323InputSourceSwitch]
        store.requestWorkShortcutReapply()
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == .default)

        // 저장된 조합 쪽이 시스템 단축키가 되는 길(옛 저장값 · 세터 직접 호출)도 같은 판정을 지난다.
        #expect(store.setWorkShortcut(v0323InputSourceSwitch), "모양은 허용되는 조합이다 — 세터는 모양만 본다")
        #expect(store.workShortcutStatus == .conflict)
        #expect(fake.live == nil)
    }

    @Test("시스템 단축키 목록: 켜진 항목만 · 키 없는 항목(0xFFFF) 제외 · 수식키는 네 비트만(fn 항목은 버리지 않는다) — 실제 목록도 읽힌다")
    func systemHotKeyListParsing() {
        let fn = 0x20000
        let items: [[String: Any]] = [
            // ⌃⌥Space — 켜짐.
            ["kHISymbolicHotKeyCode": 49, "kHISymbolicHotKeyModifiers": 4096 | 2048, "kHISymbolicHotKeyEnabled": true],
            // ⌃⌥⌘Space — 꺼짐. 사용자가 끈 시스템 단축키는 우리가 가져가도 된다.
            ["kHISymbolicHotKeyCode": 49, "kHISymbolicHotKeyModifiers": 4096 | 2048 | 256, "kHISymbolicHotKeyEnabled": false],
            // 키 없는 항목.
            ["kHISymbolicHotKeyCode": 0xFFFF, "kHISymbolicHotKeyModifiers": 4096 | 256, "kHISymbolicHotKeyEnabled": true],
            // ⌃⌘← — 화살표 항목은 fn 비트를 달고 온다.
            ["kHISymbolicHotKeyCode": 123, "kHISymbolicHotKeyModifiers": 4096 | 256 | fn, "kHISymbolicHotKeyEnabled": true],
            // 수식키 필드가 빠진 항목.
            ["kHISymbolicHotKeyCode": 40, "kHISymbolicHotKeyEnabled": true],
            // ⌃⇧⌘4 — 스크린샷을 클립보드로(켜짐). ⇧ 가 **든** 항목이 하나도 없으면 비교 마스크에서 ⇧ 를 잃어도 이 테스트가
            // 초록이다(재검증 뮤테이션 X01 생존): 그 뮤턴트는 ⌃⇧⌘4 를 받아 걸고(누를 때 스크린샷과 근무 토글이 둘 다),
            // 시스템 단축키도 아닌 ⌃⌘4 를 막는다.
            ["kHISymbolicHotKeyCode": 21, "kHISymbolicHotKeyModifiers": 4096 | 512 | 256, "kHISymbolicHotKeyEnabled": true],
        ]
        let parsed = WorkShortcutSystemHotKeys.shortcuts(fromSymbolicHotKeys: items)
        let controlCommandLeft = WorkShortcut(keyCode: 123, carbonModifiers: 4096 | 256)
        let controlShiftCommand4 = WorkShortcut(keyCode: 21, carbonModifiers: 4096 | 512 | 256)
        #expect(parsed == [v0323InputSourceSwitch, controlCommandLeft, controlShiftCommand4],
                "목록 해석이 다르다: \(parsed.map(\.displayString)) — 꺼진 항목·키 없는 항목이 섞였거나 fn 항목을 버렸거나 ⇧ 를 잃었다")
        // 기록기가 만드는 값과 같은 모양이라 겹침으로 잡힌다(기록기는 fn·numericPad 를 버린다).
        #expect(WorkShortcutRecorder.evaluate(keyCode: 123, flags: [.control, .command, .function, .numericPad], systemHotKeys: parsed) == .rejectedSystem,
                "fn 을 달고 온 시스템 항목이 기록기의 조합과 안 겹친다")
        // ⇧ 는 비교의 일부다: ⌃⇧⌘4 는 겹침이고, ⇧ 만 뺀 ⌃⌘4 는 시스템 단축키가 아니라 받는다(대조군 — 기준선이 달라야 한다).
        #expect(WorkShortcutRecorder.evaluate(keyCode: 21, flags: [.control, .shift, .command], systemHotKeys: parsed) == .rejectedSystem,
                "⌃⇧⌘4(스크린샷) 를 받아 준다 — 시스템 비교에서 ⇧ 를 잃었다")
        #expect(WorkShortcutRecorder.evaluate(keyCode: 21, flags: [.control, .command], systemHotKeys: parsed)
                    == .accepted(WorkShortcut(keyCode: 21, carbonModifiers: 4096 | 256)),
                "시스템 단축키가 아닌 ⌃⌘4 를 막았다 — ⇧ 를 비교에서 빼면 이렇게 된다")
        #expect(WorkShortcutSystemHotKeys.comparableModifierMask == UInt32(4096 | 2048 | 512 | 256),
                "비교 마스크는 ⌃⌥⇧⌘ 네 비트다")

        // 실제 목록(권한 없음 · 등록 없음 · 읽기만). 키 이름 문자열이 틀리면 위 합성 항목도 **같이** 틀려 초록이 되므로,
        // 진짜 목록이 비지 않는지를 따로 본다 — 켜진 시스템 단축키가 하나도 없는 맥은 없다(⌘Space 등).
        let live = WorkShortcutSystemHotKeys.enabled()
        #expect(!live.isEmpty, "CopySymbolicHotKeys 에서 켜진 항목을 하나도 못 읽었다 — 항목 키 이름이 틀렸는지 보라")
        for shortcut in live {
            #expect(shortcut.carbonModifiers & ~UInt32(4096 | 2048 | 512 | 256) == 0, "\(shortcut) 에 네 비트 밖의 수식키가 남았다")
            #expect(shortcut.keyCode != 0xFFFF)
        }
    }

    // MARK: ④ 누름

    @Test("누르면 근무가 시작되고, 1.5초 안의 두 번째 누름은 무시되고, 그 뒤 누름은 근무를 끝낸다")
    func pressTogglesWorkWithRepeatGuard() {
        let h = V0323PressHarness()
        defer { h.cleanup() }
        #expect(h.store.canToggleWorkByShortcut, "하네스가 알약에 손이 닿는 스토어를 못 만들었다 — 아래 단언이 전부 헛돈다")
        #expect(h.store.workShortcutStatus == .active)
        #expect(!h.store.snapshot.isWorking)

        h.registrar.press()
        #expect(h.store.snapshot.isWorking, "단축키를 눌렀는데 근무가 시작되지 않았다")
        #expect(h.store.startedAt != nil)

        h.advance(1.0)
        h.registrar.press()
        #expect(h.store.snapshot.isWorking, "1초 만의 두 번째 누름이 방금 시작한 근무를 끝냈다 — 연타 가드가 없다")

        // 첫 토글로부터 1.6초. 무시된 누름이 기준 시각을 옮겼다면 여기서도 무시된다.
        h.advance(0.6)
        h.registrar.press()
        #expect(!h.store.snapshot.isWorking, "1.5초가 지난 누름이 근무를 끝내지 못했다")
        #expect(h.store.startedAt == nil)
        #expect(h.rejectedCount == 0)
        #expect(WorkShortcutCoordinator.repeatGuardSeconds == 1.5)
    }

    @Test("canSync 가 거짓이면 토글 없이 거부음을 내고, 거부된 누름은 연타 기준을 옮기지 않는다")
    func pressWithoutSyncKeyIsRejected() throws {
        let h = V0323PressHarness(hasKey: false)
        defer { h.cleanup() }
        try #require(!h.store.canSync, "키 없는 스토어를 못 만들었다(번들 키가 새어 들어왔다) — 이 테스트가 아무것도 안 잰다")
        try #require(h.store.isSignedIn && !h.store.isTeamless, "키만 빼야 한다 — 로그인·팀 게이트가 대신 막으면 이 테스트가 canSync 를 안 잰다")

        h.registrar.press()
        #expect(h.rejectedCount == 1)
        #expect(h.store.startedAt == nil, "알약이 막히는 조건인데 단축키로는 근무가 시작됐다")
        #expect(!h.store.snapshot.isWorking)

        // 0.2초 뒤 다시. 거부가 기준 시각을 옮겼다면 이 누름은 가드에 걸려 **소리 없이** 사라진다.
        // (canSync 는 스토어 수명 동안 고정값이다 — '거부 직후 조건이 풀리면 곧바로 토글'은 로그인·팀 게이트로 그대로 연출한다:
        //  pressRightAfterRejectionTogglesOnceConditionsHold.)
        h.advance(0.2)
        h.registrar.press()
        #expect(h.rejectedCount == 2, "거부된 누름이 연타 기준을 옮겼다 — 조건이 풀려도 1.5초 동안 키가 먹통이 된다")
        #expect(h.store.startedAt == nil)
    }

    @Test("로그아웃 상태의 누름은 거부된다 — 알약이 안 그려지는 화면이고, 시작하면 서버에 안 가는 로컬 근무가 된다")
    func pressWhileSignedOutIsRejected() throws {
        let h = V0323PressHarness(signedIn: false, hasTeam: false)
        defer { h.cleanup() }
        try #require(h.store.canSync, "키 있는 스토어여야 한다 — canSync 게이트가 대신 막으면 이 테스트가 로그인 게이트를 안 잰다")
        try #require(!h.store.isSignedIn)
        try #require(h.store.pendingItems.isEmpty)
        #expect(!h.store.canToggleWorkByShortcut)

        h.registrar.press()
        #expect(h.rejectedCount == 1, "로그아웃 상태의 누름에 거부음이 없다")
        #expect(h.store.startedAt == nil, "로그아웃 상태에서 단축키로 근무가 시작됐다 — 서버에 안 가고 재로그인 때 버려진다")
        #expect(!h.store.snapshot.isWorking)
        #expect(h.store.pendingItems.isEmpty, "로그아웃 상태의 누름이 영속 큐에 항목을 남겼다")
    }

    @Test("무소속(로그인 · 팀 없음)의 누름은 거부된다 — 알약 대신 팀 코드 패널이 뜨는 화면이고, 시작하면 영속 큐에 start 가 남는다")
    func pressWhileTeamlessIsRejected() throws {
        let h = V0323PressHarness(signedIn: true, hasTeam: false)
        defer { h.cleanup() }
        try #require(h.store.canSync)
        try #require(h.store.isTeamless, "무소속 스토어를 못 만들었다 — 이 테스트가 무소속 게이트를 안 잰다")
        try #require(h.store.pendingItems.isEmpty)
        #expect(!h.store.canToggleWorkByShortcut)

        h.registrar.press()
        #expect(h.rejectedCount == 1, "무소속의 누름에 거부음이 없다")
        #expect(h.store.startedAt == nil, "무소속인데 단축키로 근무가 시작됐다 — 팝오버에는 누를 알약이 없는 상태다")
        #expect(!h.store.snapshot.isWorking)
        #expect(h.store.pendingItems.isEmpty, "무소속의 누름이 영속 큐에 항목을 남겼다")
    }

    @Test("거부 직후 로그인·팀이 서면 시계를 안 움직여도 곧바로 누름이 토글된다 — 거부된 누름은 연타 기준을 옮기지 않는다")
    func pressRightAfterRejectionTogglesOnceConditionsHold() throws {
        let h = V0323PressHarness(signedIn: false, hasTeam: false)
        defer { h.cleanup() }
        h.registrar.press()
        try #require(h.rejectedCount == 1)
        try #require(h.store.startedAt == nil)

        h.signIn()
        h.joinTeam()
        try #require(h.store.canToggleWorkByShortcut, "로그인·팀을 세웠는데 게이트가 안 열렸다")
        // 시계는 그대로(0초 뒤)다. 거부가 기준 시각을 옮겼다면 이 누름은 1.5초 가드에 걸려 소리 없이 사라진다.
        h.registrar.press()
        #expect(h.store.startedAt != nil, "조건이 풀린 직후의 누름이 무시됐다 — 거부된 누름이 연타 기준을 옮겼다")
        #expect(h.store.snapshot.isWorking)
        #expect(h.rejectedCount == 1)
    }

    // MARK: ⑤ 기록기

    @Test("기록기 판정: esc 는 취소, 수식키 하나·없음·수식키 자체는 거절, macOS 단축키는 시스템 거절, ⌃⌥⌘K 는 수락")
    func recorderEvaluate() {
        func evaluate(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, system: [WorkShortcut] = []) -> WorkShortcutRecorder.Outcome {
            WorkShortcutRecorder.evaluate(keyCode: keyCode, flags: flags, systemHotKeys: system)
        }
        #expect(evaluate(53, []) == .cancel)
        #expect(evaluate(53, [.shift]) == .cancel, "⇧+esc 가 취소가 아니다")
        #expect(evaluate(53, [.control, .option]) == .rejected)
        #expect(evaluate(40, [.command]) == .rejected)
        #expect(evaluate(40, [.command, .shift]) == .rejected)
        #expect(evaluate(40, []) == .rejected)
        #expect(evaluate(55, [.control, .option, .command]) == .rejected)
        let expected = WorkShortcut(keyCode: 40, carbonModifiers: 4096 | 2048 | 256)
        #expect(evaluate(40, [.control, .option, .command]) == .accepted(expected))
        #expect(evaluate(40, [.control, .option, .command, .capsLock]) == .accepted(expected))

        // macOS 단축키: 모양은 되지만 켜진 시스템 단축키와 같으면 거절(기록 유지). 목록에 없으면 같은 키가 수락된다(대조군).
        let system = [v0323InputSourceSwitch]
        #expect(evaluate(49, [.control, .option], system: system) == .rejectedSystem,
                "⌃⌥Space(한/영 전환)를 수락했다 — 저장되면 한/영을 바꿀 때마다 근무가 토글되거나(등록 시) 고른 키가 안 먹는다(.conflict)")
        #expect(evaluate(49, [.control, .option]) == .accepted(v0323InputSourceSwitch))
        #expect(evaluate(49, [.control, .option, .command], system: system) == .accepted(.default),
                "⌃⌥⌘Space 가 목록에 없는데 거절됐다 — 비교가 네 수식키 비트 그대로가 아니다")
        // 모양 거절이 먼저다: ⌘Space 가 시스템 단축키여도 안내는 '두 개 이상'이어야 사람이 뭘 고칠지 안다.
        #expect(evaluate(49, [.command], system: [WorkShortcut(keyCode: 49, carbonModifiers: 256)]) == .rejected)
        #expect(evaluate(53, [], system: [WorkShortcut(keyCode: 53, carbonModifiers: 0)]) == .cancel, "esc 취소가 시스템 목록에 막혔다")
    }

    @Test("기록 세션: 거절은 기록을 이어 가고(까닭별 안내), 수락은 저장 후 끝내고, esc 는 저장 없이 끝내고, 남은 모니터는 스스로 치운다")
    func recordingSessionFlow() throws {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        let coordinator = v0323Coordinator(store, fake)
        defer { withExtendedLifetime(coordinator) {} }
        coordinator.apply()
        var reads = 0
        let session = WorkShortcutRecordingSession(
            timeoutSeconds: 60,
            systemHotKeys: { reads += 1; return [v0323InputSourceSwitch] },
            notificationCenter: NotificationCenter()
        )
        defer { session.end() }

        func notice() -> WorkShortcutRecorderNotice? {
            WorkShortcutRecorderNotice.of(
                isRecording: store.isRecordingWorkShortcut,
                lastRejection: session.lastRejection,
                isEnabled: store.workShortcutEnabled,
                status: store.workShortcutStatus
            )
        }

        session.begin(store: store)
        #expect(store.isRecordingWorkShortcut)
        #expect(session.isMonitorInstalled)
        #expect(session.isObservingResignActive)
        #expect(store.workShortcutStatus == .paused)
        #expect(fake.live == nil)
        #expect(reads == 1, "기록을 시작하며 시스템 단축키 목록을 읽지 않았다")
        #expect(notice() == .recording)

        #expect(session.handleKeyDown(keyCode: 40, flags: [.command]), "기록 중 keyDown 을 흘렸다 — 조합 시도가 다른 동작이 된다")
        #expect(session.lastRejection == .shape)
        #expect(session.lastAttemptRejected)
        #expect(store.isRecordingWorkShortcut, "거절이 기록을 끝냈다")
        #expect(store.workShortcut == .default)
        #expect(notice() == .rejected)

        // macOS 단축키: 삼키고, 저장하지 않고, 기록을 이어 가며, 안내가 바뀐다.
        #expect(session.handleKeyDown(keyCode: 49, flags: [.control, .option]), "macOS 단축키 시도를 흘렸다")
        #expect(session.lastRejection == .system)
        #expect(store.isRecordingWorkShortcut, "macOS 단축키 거절이 기록을 끝냈다 — 사람이 그 자리에서 다른 조합을 못 누른다")
        #expect(store.workShortcut == .default, "macOS 단축키를 저장했다")
        #expect(notice() == .rejectedSystem)
        #expect(reads == 1, "키마다 시스템 목록을 다시 읽는다 — 기록 동안은 시작할 때 읽은 목록을 쓴다")

        #expect(session.handleKeyDown(keyCode: 40, flags: [.control, .option, .command]))
        let accepted = WorkShortcut(keyCode: 40, carbonModifiers: 4096 | 2048 | 256)
        #expect(store.workShortcut == accepted)
        #expect(!store.isRecordingWorkShortcut)
        #expect(!session.isMonitorInstalled)
        #expect(!session.isObservingResignActive)
        #expect(session.lastRejection == nil)
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == accepted, "수락한 조합이 전역에 안 걸렸다")

        session.begin(store: store)
        #expect(reads == 2, "새 기록이 시스템 목록을 새로 읽지 않았다 — 시스템 설정을 바꾸고 온 사람에게 옛 목록을 들이댄다")
        #expect(session.handleKeyDown(keyCode: 53, flags: []))
        #expect(!store.isRecordingWorkShortcut, "esc 가 기록을 안 끝냈다")
        #expect(!session.isMonitorInstalled)
        #expect(store.workShortcut == accepted, "esc 가 조합을 바꿨다")

        // 다른 문(창 닫기·스위치 끄기)으로 기록이 끝났는데 모니터만 남은 경우: 흘려보내고 치운다.
        session.begin(store: store)
        store.setRecordingWorkShortcut(false)
        #expect(session.handleKeyDown(keyCode: 49, flags: [.control, .option, .command]) == false, "기록이 끝났는데 키를 삼켰다")
        #expect(!session.isMonitorInstalled)
        #expect(store.workShortcut == accepted)
    }

    @Test("스위치가 꺼져 있으면 기록이 시작되지 않는다 — 깃발 · 모니터 · 비활성 관찰 전부 없음")
    func beginDoesNothingWhileSwitchIsOff() {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        let coordinator = v0323Coordinator(store, fake)
        defer { withExtendedLifetime(coordinator) {} }
        coordinator.apply()
        let session = v0323Session()
        defer { session.end() }

        store.setWorkShortcutEnabled(false)
        session.begin(store: store)
        #expect(!store.isRecordingWorkShortcut, "꺼진 스위치 아래에서 기록이 시작됐다 — '새 조합을 누르세요'가 뜨는데 어떤 키도 안 받는다")
        #expect(!session.isMonitorInstalled, "꺼진 스위치인데 기록 모니터를 걸었다")
        #expect(!session.isObservingResignActive)
        #expect(store.workShortcutStatus == .off)

        // 대조군: 켜면 같은 호출이 기록을 시작한다(위 단언이 'begin 이 원래 아무것도 안 한다'로 초록이 되지 않게).
        store.setWorkShortcutEnabled(true)
        session.begin(store: store)
        #expect(store.isRecordingWorkShortcut)
        #expect(session.isMonitorInstalled)
    }

    // MARK: ⑥ 기록 종료

    @Test("설정 창 컨트롤러의 close() 가 단축키 기록을 끝낸다 — 세션을 거친 기록도, 한 번도 시작 안 한 세션의 컨트롤러도")
    func settingsWindowCloseEndsRecording() {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        let coordinator = v0323Coordinator(store, fake)
        defer { withExtendedLifetime(coordinator) {} }
        coordinator.apply()
        let session = v0323Session()
        defer { session.end() }
        let controller = CheckSettingsWindowController(stuckWindowCheckSeconds: 60, workShortcutRecording: session)
        controller.configure(store: store, content: { _ in AnyView(EmptyView()) })

        session.begin(store: store)
        #expect(store.workShortcutStatus == .paused)
        controller.close()
        #expect(!store.isRecordingWorkShortcut, "설정 창을 닫았는데 기록 중이 남았다 — 전역 단축키가 앱 재시작까지 멈춘다")
        #expect(!session.isMonitorInstalled, "설정 창을 닫았는데 기록 모니터가 남았다")
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == .default)
        #expect(!controller.hasWindow, "close() 가 창을 만들었다")

        // 한 번도 begin 하지 않은 **새** 세션 + 새 컨트롤러. 이 세션의 end() 는 붙든 스토어가 없어 깃발에 손이 안 닿으므로,
        // 여기서 깃발을 내리는 것은 컨트롤러의 `wiring?.store.setRecordingWorkShortcut(false)` 뿐이다.
        // (위 절반과 같은 세션을 쓰면 그 세션이 begin 때 붙든 스토어로 깃발을 내려, 컨트롤러의 그 한 줄을 지워도 초록이었다.)
        let freshSession = v0323Session()
        let freshController = CheckSettingsWindowController(stuckWindowCheckSeconds: 60, workShortcutRecording: freshSession)
        freshController.configure(store: store, content: { _ in AnyView(EmptyView()) })
        store.setRecordingWorkShortcut(true)
        #expect(store.workShortcutStatus == .paused)
        freshController.close()
        #expect(!store.isRecordingWorkShortcut, "세션을 안 거친 기록 깃발은 close() 가 못 내린다 — 컨트롤러가 스토어 깃발을 직접 안 내린다")
        #expect(store.workShortcutStatus == .active)
        #expect(!freshController.hasWindow)
    }

    @Test("타이틀바 빨간 점(창 닫힘 델리게이트)도 단축키 기록을 끝낸다")
    func windowCloseButtonEndsRecording() throws {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let session = v0323Session()
        defer { session.end() }
        let controller = CheckSettingsWindowController(stuckWindowCheckSeconds: 60, workShortcutRecording: session)
        controller.configure(store: store, content: { _ in AnyView(EmptyView()) })
        controller.show()
        defer { controller.close() }
        let window = try #require(
            NSApplication.shared.windows.first { ($0.delegate as AnyObject?) === controller },
            "show() 가 창을 안 세웠다"
        )
        // 이 프로세스의 창 자리 자동저장 이름을 놓아준다(다른 스위트가 같은 이름으로 창을 세워도 저장이 살게).
        defer { window.setFrameAutosaveName("") }
        #expect(window.alphaValue == 0, "테스트 창이 사용자 화면에 보인다")

        session.begin(store: store)
        #expect(store.isRecordingWorkShortcut)
        window.performClose(nil)
        #expect(!controller.isOpen, "빨간 점 경로가 델리게이트에 닿지 않았다 — 이 테스트가 아무것도 안 잰다")
        #expect(!store.isRecordingWorkShortcut, "빨간 점으로 닫았는데 기록 중이 남았다")
        #expect(!session.isMonitorInstalled)
    }

    @Test("설정 창을 열 때마다(show) 전역 단축키를 다시 판정한다 — 닫았다 다시 열면 행의 onAppear 는 다시 오지 않는다")
    func settingsWindowShowReappliesShortcut() throws {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        var system: [WorkShortcut] = [.default]
        let coordinator = v0323Coordinator(store, fake, system: { system })
        defer { withExtendedLifetime(coordinator) {} }
        coordinator.apply()
        try #require(store.workShortcutStatus == .conflict)

        let session = v0323Session()
        defer { session.end() }
        let controller = CheckSettingsWindowController(stuckWindowCheckSeconds: 60, workShortcutRecording: session)
        // 행이 없는 콘텐츠다 — 행의 onAppear 가 아니라 컨트롤러의 show() 가 재판정하는지를 떼어 잰다.
        controller.configure(store: store, content: { _ in AnyView(EmptyView()) })
        defer { controller.close() }

        // 사용자가 시스템 설정에서 겹치던 단축키를 끄고 돌아와 설정을 열었다.
        system = []
        controller.show()
        let window = try #require(
            NSApplication.shared.windows.first { ($0.delegate as AnyObject?) === controller },
            "show() 가 창을 안 세웠다"
        )
        defer { window.setFrameAutosaveName("") }
        #expect(window.alphaValue == 0, "테스트 창이 사용자 화면에 보인다")
        #expect(store.workShortcutStatus == .active, "설정 창을 열었는데 재판정하지 않았다 — 시스템 단축키를 끄고 와도 겹침 안내가 안 풀린다")
        #expect(fake.live == .default)

        // 닫고, 그 단축키를 다시 켜고, 다시 연다 — 첫 열기에만 묻는 구현이면 여기서 걸린다.
        controller.close()
        system = [.default]
        controller.show()
        #expect(store.workShortcutStatus == .conflict, "다시 연 설정 창이 재판정하지 않았다")
        #expect(fake.live == nil)
    }

    @Test("기록 중 앱이 비활성이 되면(didResignActive) 기록이 끝나고 전역 등록이 돌아온다 — 관찰은 begin 마다 새로 걸고 end 에서 뗀다")
    func resignActiveEndsRecording() {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        let coordinator = v0323Coordinator(store, fake)
        defer { withExtendedLifetime(coordinator) {} }
        coordinator.apply()
        let center = NotificationCenter()
        let session = v0323Session(center: center)
        defer { session.end() }

        session.begin(store: store)
        #expect(session.isObservingResignActive)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!store.isRecordingWorkShortcut,
                "다른 앱으로 넘어갔는데 기록이 안 끝났다 — 로컬 모니터는 못 듣고 전역 등록은 내려가 있어 시간 초과까지 키가 죽는다")
        #expect(!session.isMonitorInstalled)
        #expect(!session.isObservingResignActive, "기록이 끝났는데 비활성 관찰이 남았다")
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == .default)

        // 다음 기록도 듣는다(관찰을 begin 마다 새로 건다).
        session.begin(store: store)
        #expect(store.isRecordingWorkShortcut)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!store.isRecordingWorkShortcut, "두 번째 기록이 비활성 알림을 못 들었다")

        // 끝난 기록의 관찰은 남지 않는다: 깃발만 따로 세우고 알림을 보내도 내려가지 않는다(남아 있으면 end() 가 불려 내려간다).
        store.setRecordingWorkShortcut(true)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(store.isRecordingWorkShortcut, "끝난 기록의 비활성 관찰이 살아서 남의 깃발을 내렸다")
        store.setRecordingWorkShortcut(false)

        // 대조군: 다른 알림(활성이 됨)에는 끝나지 않는다.
        session.begin(store: store)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(store.isRecordingWorkShortcut, "비활성이 아닌 알림에도 기록이 끝났다")
    }

    @Test("15초 시간 초과가 기록을 끝내고 전역 등록을 되살린다 — 끝낸 기록의 옛 타이머는 새 기록을 안 건드린다")
    func recordingTimesOut() async throws {
        #expect(WorkShortcutRecorder.recordingTimeoutSeconds == 15)
        #expect(WorkShortcutRecordingSession().timeoutSeconds == 15, "기본 세션의 시간 초과가 15초가 아니다")
        #expect(WorkShortcutRecordingSession.shared.timeoutSeconds == 15)

        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        let coordinator = v0323Coordinator(store, fake)
        defer { withExtendedLifetime(coordinator) {} }
        coordinator.apply()

        let quick = v0323Session(timeout: 0.05)
        defer { quick.end() }
        quick.begin(store: store)
        #expect(store.workShortcutStatus == .paused)
        let deadline = Date().addingTimeInterval(5)
        while store.isRecordingWorkShortcut, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!store.isRecordingWorkShortcut, "시간 초과가 기록을 끝내지 않았다 — 전역 단축키가 앱 재시작까지 멈춘다")
        #expect(!quick.isMonitorInstalled)
        #expect(store.workShortcutStatus == .active)
        #expect(fake.live == .default)

        // 시작 → 끝 → 다시 시작. 첫 타이머는 취소됐다 — 취소 검사가 없으면 그 타이머가 곧바로 깨어나 새 기록을 끝낸다.
        let slow = v0323Session(timeout: 60)
        defer { slow.end() }
        slow.begin(store: store)
        slow.end()
        slow.begin(store: store)
        try await Task.sleep(for: .milliseconds(150))
        #expect(store.isRecordingWorkShortcut, "끝낸 기록의 타이머가 새 기록을 끝냈다")
        #expect(slow.isMonitorInstalled)
    }

    @Test("거절된 입력마다 시간 초과를 다시 건다 — 모양 거절도 macOS 단축키 겹침 거절도, 그리고 결국은 끝난다")
    func rejectionRearmsTimeout() async throws {
        let scratch = V0323Scratch(#function)
        let store = v0323Store(defaults: scratch.defaults)
        let fake = V0323FakeRegistrar()
        let coordinator = v0323Coordinator(store, fake)
        defer { withExtendedLifetime(coordinator) {} }
        coordinator.apply()

        // 시각이 아니라 **순서**로 잰다: 아래 확인(sleep 의 마감)은 언제나 살아 있어야 할 타이머의 마감보다 0.6초 앞이고
        // 죽었어야 할 타이머의 마감보다 0.6초 뒤다. 둘 다 메인 액터에 마감 순서대로 줄을 서므로, 부하로 메인 스레드가
        // 막혀도 실행이 늦어질 뿐 순서는 뒤집히지 않는다.
        let timeout: TimeInterval = 2
        let session = v0323Session(timeout: timeout, system: [v0323InputSourceSwitch])
        defer { session.end() }
        session.begin(store: store)

        try await Task.sleep(for: .seconds(timeout * 0.6))
        try #require(store.isRecordingWorkShortcut, "첫 시간 초과 전에 기록이 끝났다 — 아래 단언이 아무것도 안 잰다")
        #expect(session.handleKeyDown(keyCode: 40, flags: [.command]))
        try await Task.sleep(for: .seconds(timeout * 0.7))
        // 시작으로부터 1.3×. 첫 타이머가 살아 있었다면 이미 끝났다.
        #expect(store.isRecordingWorkShortcut, "모양 거절이 시간 초과를 다시 걸지 않았다 — 여러 번 시도하는 사람의 기록이 안내 없이 끊긴다")
        #expect(session.lastRejection == .shape)

        #expect(session.handleKeyDown(keyCode: 49, flags: [.control, .option]))
        try await Task.sleep(for: .seconds(timeout * 0.7))
        #expect(store.isRecordingWorkShortcut, "macOS 단축키 겹침 거절이 시간 초과를 다시 걸지 않았다")
        #expect(session.lastRejection == .system)

        // 다시 건 타이머도 결국 끝낸다 — 재무장이 '끝나지 않는 기록'이 되지 않는다.
        let deadline = Date().addingTimeInterval(10)
        while store.isRecordingWorkShortcut, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!store.isRecordingWorkShortcut)
        #expect(!session.isMonitorInstalled)
        #expect(store.workShortcutStatus == .active)
    }

    // MARK: ⑦ 소스 계약

    @Test("진짜 Carbon 등록기는 AppDelegate 한 곳에서, 오버레이를 만든 뒤에 만들고 apply 한다")
    func productionRegistrarIsBuiltOnceAfterOverlay() throws {
        var hits: [String: Int] = [:]
        for name in try v0323SourceNames() {
            let count = v0323Stripped(try v0323Source(name)).components(separatedBy: "CarbonWorkShortcutRegistrar(").count - 1
            if count > 0 { hits[name] = count }
        }
        #expect(hits == ["CheckApp.swift": 1], "진짜 등록기를 만드는 곳이 \(hits) 다 — 테스트 경로가 실제 전역 키를 잡을 수 있다")

        let app = v0323Collapsed(v0323Stripped(try v0323Source("CheckApp.swift")))
        let launch = try #require(app.range(of: "func applicationDidFinishLaunching(_ notification: Notification) {"))
        let launchEnd = try #require(app.range(of: "private func wireTodoBoard()", range: launch.upperBound..<app.endIndex))
        let body = app[launch.upperBound..<launchEnd.lowerBound]
        let overlay = try #require(body.range(of: "overlayController = CheckOverlayController("))
        let make = try #require(
            body.range(of: "workShortcut = WorkShortcutCoordinator(store: store, registrar: CarbonWorkShortcutRegistrar())"),
            "AppDelegate 가 단축키 조정자를 안 만든다"
        )
        let apply = try #require(body.range(of: "workShortcut?.apply()"),
                                 "AppDelegate 가 첫 apply() 를 안 부른다 — 설정 스위치를 한 번 건드리기 전까지 단축키가 죽어 있다")
        #expect(overlay.lowerBound < make.lowerBound, "오버레이보다 먼저 단축키를 잇는다 — 단축키로 시작한 근무에 캐릭터가 안 나올 수 있다")
        #expect(make.lowerBound < apply.lowerBound)
        #expect(app.contains("private var workShortcut: WorkShortcutCoordinator?"), "조정자를 붙드는 참조가 없다 — 등록기가 해제된 주소를 Carbon 에 남긴다")
    }

    @Test("전역 키 감시는 권한이 필요 없는 핫키뿐이다 — keyDown 전역 모니터·이벤트 탭·접근성 신뢰 조회 금지")
    func noPermissionHungryKeyWatching() throws {
        for name in try v0323SourceNames() {
            let code = v0323Stripped(try v0323Source(name))
            #expect(!code.contains("tapCreate"), "\(name) 에 CGEvent 탭이 있다 — 입력 모니터링 권한이 필요하다")
            #expect(!code.contains("AXIsProcessTrusted"), "\(name) 가 접근성 신뢰를 묻는다 — 권한 창이 뜬다")
            var rest = Substring(code)
            while let hit = rest.range(of: "addGlobalMonitorForEvents(") {
                let mask = rest[hit.upperBound...].prefix { $0 != ")" && $0 != "{" }
                for banned in ["keyDown", "keyUp", "flagsChanged"] {
                    #expect(!mask.contains(banned), "\(name) 가 키 입력(\(banned))을 전역으로 감시한다 — 입력 모니터링 권한 창이 뜨고 우리 앱이 앞이면 침묵한다")
                }
                rest = rest[hit.upperBound...]
            }
        }
        // 금지 목록이 '아무것도 안 한다'로 초록이 되지 않게, 권한 없는 길이 실제로 있는지도 본다.
        let shortcut = v0323Stripped(try v0323Source("WorkShortcut.swift"))
        #expect(shortcut.components(separatedBy: "RegisterEventHotKey(").count - 1 == 1)
        #expect(shortcut.components(separatedBy: "InstallEventHandler(").count - 1 == 1)
        #expect(shortcut.contains("guard eventHandlerRef == nil else"),
                "처리기를 등록마다 새로 건다 — 두 번째 InstallEventHandler 가 -9866 으로 거부돼 조합 변경이 실패한다")
    }

    @Test("단축키 게이트와 알약 게이트는 짝이다 — canSync·로그인·무소속 아님 ↔ 로그인 분기 → 무소속 분기의 else → HeaderCard 안 알약")
    func shortcutGateMirrorsThePillGate() throws {
        let storeCode = v0323Collapsed(v0323Stripped(try v0323Source("WorkTimerStore.swift")))
        let gate = try #require(storeCode.range(of: "var canToggleWorkByShortcut: Bool {"), "단축키 게이트(canToggleWorkByShortcut)가 없다")
        let gateEnd = try #require(storeCode.range(of: "}", range: gate.upperBound..<storeCode.endIndex))
        let gateBody = storeCode[gate.upperBound..<gateEnd.lowerBound]
        #expect(gateBody.contains("canSync"), "단축키 게이트가 canSync 를 안 본다 — 키 없는 빌드에서 알약은 막혀도 키는 된다")
        #expect(gateBody.contains("isSignedIn"), "단축키 게이트가 로그인을 안 본다 — 로그아웃 상태의 누름이 서버에 안 가는 근무를 시작한다")
        #expect(gateBody.contains("!isTeamless"), "단축키 게이트가 무소속을 안 본다 — 무소속의 누름이 영속 큐에 start 를 남긴다")

        let shortcut = v0323Collapsed(v0323Stripped(try v0323Source("WorkShortcut.swift")))
        let press = try #require(shortcut.range(of: "func handlePress() {"))
        let pressEnd = try #require(shortcut.range(of: "enum WorkShortcutRecorder {", range: press.upperBound..<shortcut.endIndex))
        #expect(shortcut[press.upperBound..<pressEnd.lowerBound].contains("guard store.canToggleWorkByShortcut else {"),
                "누름이 단축키 게이트를 안 지난다")

        // 알약 쪽: 로그인 분기 → 무소속 분기(팀 코드 패널) → else → HeaderCard. 이 순서가 바뀌면 위 게이트도 바꿔야 한다.
        let menu = v0323Collapsed(v0323Stripped(try v0323Source("CheckMenuView.swift")))
        let content = try #require(menu.range(of: "private var content: some View {"))
        let signedIn = try #require(menu.range(of: "if store.isSignedIn {", range: content.upperBound..<menu.endIndex))
        let teamless = try #require(menu.range(of: "if store.isTeamless {", range: signedIn.upperBound..<menu.endIndex))
        let header = try #require(menu.range(of: "HeaderCard(", range: teamless.upperBound..<menu.endIndex))
        let between = menu[teamless.upperBound..<header.lowerBound]
        #expect(between.contains("TeamlessPanel(store: store)"), "무소속 분기에 팀 코드 패널이 없다 — 알약 게이트의 모양이 바뀌었다")
        #expect(between.contains("} else {"), "HeaderCard 가 무소속 분기의 else 안에 있지 않다 — 단축키 게이트의 !isTeamless 근거가 사라졌다")
        #expect(menu.components(separatedBy: "HeaderCard(").count - 1 == 1, "HeaderCard 를 그리는 곳이 둘 이상이다 — 알약에 닿는 조건을 다시 세라")
        #expect(menu.contains("WorkTogglePill( isWorking: store.snapshot.isWorking, enabled: store.canSync, action: { store.toggle() } )"),
                "알약의 enabled·action 이 바뀌었다 — 단축키 게이트·동작도 같이 바꿔라")
        #expect(menu.components(separatedBy: "WorkTogglePill(").count - 1 == 1, "근무 알약이 HeaderCard 밖에도 생겼다 — 알약에 닿는 조건을 다시 세라")
    }

    @Test("등록기·키캡의 방어선은 소스로 못 박는다 — 걸기 전 해제 · 서명/id 비교 · 꺼진 키캡")
    func registrarAndKeycapDefensesHoldInSource() throws {
        // 서명 'CHKW' 와 id 를 숫자로 못 박는다(진짜 등록은 없다 — 상수만 읽는다).
        #expect(CarbonWorkShortcutRegistrar.signature == 0x43484B57, "서명이 'CHKW' 가 아니다")
        #expect(CarbonWorkShortcutRegistrar.hotKeyIdentifier == 1)

        let shortcut = v0323Collapsed(v0323Stripped(try v0323Source("WorkShortcut.swift")))

        // 걸기 전 해제: 빠지면 같은 조합 재등록은 -9878 로 실패하고, 다른 조합은 옛 조합이 남아 두 키가 다 토글한다.
        let register = try #require(shortcut.range(of: "func register(_ shortcut: WorkShortcut) -> OSStatus {"))
        let registerEnd = try #require(shortcut.range(of: "func unregister() {", range: register.upperBound..<shortcut.endIndex))
        let registerBody = shortcut[register.upperBound..<registerEnd.lowerBound]
        let release = try #require(registerBody.range(of: "unregister()"), "등록기가 새로 걸기 전에 옛 등록을 풀지 않는다")
        let carbonRegister = try #require(registerBody.range(of: "RegisterEventHotKey("))
        #expect(release.lowerBound < carbonRegister.lowerBound, "옛 등록을 푸는 것이 새로 거는 것보다 뒤다")

        // 서명·id 비교: 빠지면 같은 앱 대상에 붙은 **다른** 핫키에도 근무가 토글된다.
        let handler = try #require(shortcut.range(of: "private func carbonWorkShortcutEventHandler("))
        let handlerEnd = try #require(shortcut.range(of: "final class WorkShortcutCoordinator", range: handler.upperBound..<shortcut.endIndex))
        let handlerBody = shortcut[handler.upperBound..<handlerEnd.lowerBound]
        let guardClause = try #require(
            handlerBody.range(of: "guard status == OSStatus(noErr), hotKeyID.signature == CarbonWorkShortcutRegistrar.signature, hotKeyID.id == CarbonWorkShortcutRegistrar.hotKeyIdentifier else { return OSStatus(eventNotHandledErr) }"),
            "Carbon 처리기가 서명·id 를 비교하지 않는다 — 우리 것이 아닌 핫키에도 근무가 토글된다"
        )
        let fire = try #require(handlerBody.range(of: "onPressed?()"))
        #expect(guardClause.lowerBound < fire.lowerBound, "서명·id 비교가 누름 전달보다 뒤다")

        // 꺼진 키캡: 스위치가 꺼지면 키캡 버튼 자체가 막혀야 한다(세션의 begin 거부와 짝 — beginDoesNothingWhileSwitchIsOff).
        let settings = v0323Collapsed(v0323Stripped(try v0323Source("CheckSettingsView.swift")))
        let keycap = try #require(settings.range(of: "private var keycap: some View {"))
        let keycapEnd = try #require(settings.range(of: "private var resetButton: some View {", range: keycap.upperBound..<settings.endIndex))
        let keycapCode = settings[keycap.upperBound..<keycapEnd.lowerBound]
        let style = try #require(keycapCode.range(of: ".buttonStyle(WorkShortcutKeycapButtonStyle(isRecording: isRecording))"))
        let disabled = try #require(keycapCode.range(of: ".disabled(!isEnabled)"), "키캡 버튼이 꺼진 스위치에서 막히지 않는다")
        #expect(style.lowerBound < disabled.lowerBound, "키캡의 .disabled 가 버튼 체인 밖에 있다")
    }

    @Test("설정 화면에 '근무 시작·종료 단축키' 행이 있고, 기록 행은 버튼만으로 만들며 나타날 때 재판정을 요청하고, 기록 세션은 모니터·관찰을 떼고 다시 건다")
    func settingsRowAndRecorderKeepHouseRules() throws {
        let settings = v0323Collapsed(v0323Stripped(try v0323Source("CheckSettingsView.swift")))
        let autoStart = try #require(settings.range(of: "title: \"자동 근무 시작\""))
        let row = try #require(
            settings.range(of: "CheckSettingsToggleRow( title: \"근무 시작·종료 단축키\", detail: \"메뉴바를 열지 않아도 이 키로 근무를 시작하거나 끝내요.\", isOn: workShortcutEnabledBinding ) WorkShortcutRecorderRow(store: store)"),
            "설정 화면에 '근무 시작·종료 단축키' 스위치와 기록 행이 없다"
        )
        let todo = try #require(settings.range(of: "title: \"캐릭터를 눌러 할 일 열기\""))
        #expect(autoStart.lowerBound < row.lowerBound && row.lowerBound < todo.lowerBound, "단축키 행이 '자동 근무 시작' 다음 자리가 아니다")
        #expect(settings.contains("get: { store.workShortcutEnabled }, set: { store.setWorkShortcutEnabled($0) }"))

        let rowStart = try #require(settings.range(of: "enum WorkShortcutRecorderNotice: Equatable {"))
        let rowEnd = try #require(settings.range(of: "enum CenterSettingsRowState: Equatable {"))
        let rowCode = settings[rowStart.lowerBound..<rowEnd.lowerBound]
        for banned in ["TextField", "SecureField", "Picker", "Menu"] {
            #expect(!rowCode.contains(banned), "기록 행에 \(banned) 가 있다 — ImageRenderer 가 노란 상자로 그려 스냅샷이 눈이 먼다")
        }
        // 뷰 쪽 기록 종료 문: 키캡 다시 누름 · 스위치 끄기 · 사라짐.
        #expect(rowCode.contains("if isRecording { session.end() } else { session.begin(store: store) }"))
        #expect(rowCode.contains(".onChange(of: store.workShortcutEnabled) { _, enabled in if !enabled { session.end() } }"))
        #expect(rowCode.contains(".onDisappear { session.end() }"))
        #expect(rowCode.contains(".accessibilityLabel(isRecording ? \"새 조합을 누르세요\" : store.workShortcut.spokenDescription)"))
        // 설정 창을 열 때의 재판정: 빠지면 시스템 설정에서 겹치는 단축키를 끄고 온 사람이 앱을 다시 켤 때까지 .conflict 에 갇힌다.
        #expect(rowCode.contains(".onAppear { store.requestWorkShortcutReapply() }"),
                "단축키 행이 나타날 때 재판정을 요청하지 않는다 — macOS 단축키를 끄고 돌아와도 겹침 안내가 안 풀린다")
        let storeCode = v0323Collapsed(v0323Stripped(try v0323Source("WorkTimerStore.swift")))
        #expect(storeCode.contains("func requestWorkShortcutReapply() { onWorkShortcutSettingsChanged?() }"),
                "재판정 요청이 조정자에게 닿지 않는다")

        let shortcut = v0323Collapsed(v0323Stripped(try v0323Source("WorkShortcut.swift")))
        let begin = try #require(shortcut.range(of: "func begin(store: WorkTimerStore) {"))
        let beginEnd = try #require(shortcut.range(of: "func handleKeyDown(", range: begin.upperBound..<shortcut.endIndex))
        let beginBody = shortcut[begin.upperBound..<beginEnd.lowerBound]
        let remove = try #require(beginBody.range(of: "removeMonitor()"), "기록 시작이 옛 모니터를 떼지 않는다 — 죽은 기록을 쥔 모니터가 남는다")
        let add = try #require(beginBody.range(of: "NSEvent.addLocalMonitorForEvents(matching: .keyDown)"))
        #expect(remove.lowerBound < add.lowerBound)
        let removeObserver = try #require(beginBody.range(of: "removeResignActiveObserver()"), "기록 시작이 옛 비활성 관찰을 떼지 않는다")
        let addObserver = try #require(beginBody.range(of: "notificationCenter.addObserver( forName: NSApplication.didResignActiveNotification,"))
        #expect(removeObserver.lowerBound < addObserver.lowerBound)
        #expect(!shortcut.contains("isKeyWindow"), "기록 모니터가 키 창으로 거른다 — 창을 막 연 순간 첫 입력이 죽는다")
        #expect(!shortcut.contains("monitor == nil"), "기록 모니터 설치가 멱등 가드로 바뀌었다 — 교체가 아니면 죽은 화면에 묶인다")
    }

    // MARK: ⑧ 렌더 · 문구

    @Test("상태 한 줄의 문구는 글자 그대로다")
    func noticeWording() {
        typealias N = WorkShortcutRecorderNotice
        #expect(N.of(isRecording: true, lastRejection: nil, isEnabled: true, status: .paused) == .recording)
        #expect(N.of(isRecording: true, lastRejection: .shape, isEnabled: true, status: .paused) == .rejected)
        #expect(N.of(isRecording: true, lastRejection: .system, isEnabled: true, status: .paused) == .rejectedSystem)
        #expect(N.of(isRecording: false, lastRejection: nil, isEnabled: true, status: .conflict) == .conflict)
        #expect(N.of(isRecording: false, lastRejection: nil, isEnabled: true, status: .failed(-50)) == .failed)
        #expect(N.of(isRecording: false, lastRejection: nil, isEnabled: true, status: .failed(-9878)) == .failed)
        #expect(N.of(isRecording: false, lastRejection: nil, isEnabled: true, status: .active) == nil)
        #expect(N.of(isRecording: false, lastRejection: nil, isEnabled: false, status: .conflict) == nil,
                "스위치를 끈 사람에게 옛 겹침을 계속 빨갛게 보인다")

        #expect(N.recording.text == "⌃ ⌥ ⌘ 중 두 개 이상과 함께 눌러요 · esc 취소")
        #expect(N.rejected.text == "⌃ ⌥ ⌘ 중 두 개 이상을 함께 눌러 주세요")
        #expect(N.rejectedSystem.text == "macOS 단축키와 겹쳐요. 다른 조합을 눌러 주세요")
        #expect(N.conflict.text == "macOS 단축키와 겹쳐요. 다른 키로 바꿔 주세요.")
        #expect(N.failed.text == "단축키를 등록하지 못했어요.")
        #expect(N.recording.tone == .hint)
        #expect(N.rejected.tone == .retry && N.rejectedSystem.tone == .retry, "기록 중 거절은 둘 다 주황(다시 해 보라)이다")
        #expect(N.conflict.tone == .danger && N.failed.tone == .danger)
    }

    @Test("기록 행은 노란 상자 없이 그려지고, 상태마다 제 색·제 줄을 갖는다")
    func recorderRowRendersEveryState() throws {
        let scratch = V0323Scratch(#function)
        let custom = try #require(WorkShortcut(keyCode: 40, flags: [.control, .command]))

        func render(
            system: [WorkShortcut] = [],
            _ configure: (WorkTimerStore, WorkShortcutRecordingSession) -> Void,
            name: String
        ) throws -> NSBitmapImageRep {
            scratch.defaults.removePersistentDomain(forName: scratch.suiteName)
            let store = v0323Store(defaults: scratch.defaults)
            let session = v0323Session(system: system)
            defer { session.end() }
            configure(store, session)
            let bitmap = try v0323RowBitmap(WorkShortcutRecorderRow(store: store, session: session))
            #expect(v0323Count(bitmap, v0323IsYellowPlaceholder) == 0, "\(name): 기록 행에 '못 그림' 노란 상자가 있다")
            v0323Save(bitmap, name: "v0323-recorder-\(name).png")
            return bitmap
        }

        let idle = try render({ store, _ in store.workShortcutStatus = .active }, name: "idle")
        let recording = try render({ store, _ in store.setRecordingWorkShortcut(true) }, name: "recording")
        let rejected = try render({ store, session in
            session.begin(store: store)
            session.handleKeyDown(keyCode: 40, flags: [.command])
        }, name: "rejected")
        let rejectedSystem = try render(system: [v0323InputSourceSwitch], { store, session in
            session.begin(store: store)
            session.handleKeyDown(keyCode: 49, flags: [.control, .option])
        }, name: "rejected-system")
        let conflict = try render({ store, _ in store.workShortcutStatus = .conflict }, name: "conflict")
        let failed = try render({ store, _ in store.workShortcutStatus = .failed(-50) }, name: "failed")
        let changed = try render({ store, _ in store.setWorkShortcut(custom) }, name: "custom")
        let off = try render({ store, _ in store.setWorkShortcutEnabled(false) }, name: "off")

        // 키캡 글자(밝은 흰색)가 실제로 찍혔다 — 빈 그림이면 위의 '노란 상자 0' 이 아무것도 증명하지 않는다.
        #expect(v0323Count(idle, v0323IsBright) > 50, "기록 행이 비어 있다")
        // 스위치를 끄면 흐리게: 밝은 흰 글자가 한 톨도 안 남는다.
        #expect(v0323Count(off, v0323IsBright) == 0, "스위치를 껐는데 키캡이 흐려지지 않았다")

        // 줄: 할 말이 있는 상태에만 한 줄이 붙고, 그 줄은 언제나 **한 줄**이다(창 높이 계약이 이 높이로 잡혀 있다).
        let idleHeight = idle.pixelsHigh
        #expect(off.pixelsHigh == idleHeight && changed.pixelsHigh == idleHeight)
        for (name, bitmap) in [("recording", recording), ("rejected", rejected), ("rejected-system", rejectedSystem), ("conflict", conflict), ("failed", failed)] {
            #expect(bitmap.pixelsHigh > idleHeight + 20, "\(name) 상태에 안내 한 줄이 없다(\(bitmap.pixelsHigh)px, 정상 \(idleHeight)px)")
            #expect(bitmap.pixelsHigh == recording.pixelsHigh, "\(name) 상태의 안내가 한 줄이 아니다 — 창 계약(가장 높은 상태)이 흔들린다")
        }

        // 색: macOS 단축키 겹침·실패는 빨강, 기록 중 거절(모양·시스템)은 주황, 기록 중은 파랑 테두리. 정상 상태엔 셋 다 없다(대조군).
        #expect(v0323Count(conflict, v0323IsDanger) > 20, "겹침 안내가 빨갛지 않다")
        #expect(v0323Count(failed, v0323IsDanger) > 20, "등록 실패 안내가 빨갛지 않다")
        #expect(v0323Count(rejected, v0323IsRetryAmber) > 20, "거절 안내가 주황이 아니다")
        #expect(v0323Count(rejectedSystem, v0323IsRetryAmber) > 20, "macOS 단축키 거절 안내가 주황이 아니다")
        #expect(v0323Count(recording, v0323IsAccent) > 50, "기록 중 키캡이 파랗게 '듣고 있다'를 말하지 않는다")
        #expect(v0323Count(idle, v0323IsDanger) == 0 && v0323Count(idle, v0323IsRetryAmber) == 0 && v0323Count(idle, v0323IsAccent) == 0)

        // [기본값으로] 는 기본값이 아닐 때만: 키캡 오른쪽(110pt 이후)에 글자가 찍힌다.
        #expect(v0323Count(changed, v0323IsBright, fromX: 220) > 30, "기본값이 아닌데 [기본값으로] 버튼이 없다")
        #expect(v0323Count(idle, v0323IsBright, fromX: 220) == 0, "기본값인데 [기본값으로] 버튼이 있다")
    }
}

// MARK: - 렌더 헬퍼

private enum V0323Error: Error { case renderFailed }

/// 기록 행 하나를 카드 안쪽 폭(창 380 − 바깥 여백 14×2 − 카드 여백 12×2 = 328)에서 2배율로 그린다(V0316 행 렌더와 같은 규약).
@MainActor
private func v0323RowBitmap(_ row: WorkShortcutRecorderRow) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: row.padding(8).background(CheckTheme.panel).frame(width: 328))
    // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V0323Error.renderFailed }
    return bitmap
}

/// ImageRenderer 의 "못 그림" 표식(샛노란 상자, 실측 255/204/0). 파랑 성분이 0 인 게 결정적이다(V0316 과 같은 판정).
private func v0323IsYellowPlaceholder(_ r: Int, _ g: Int, _ b: Int) -> Bool { r >= 240 && g >= 195 && b <= 40 }
/// 흰 글자(primaryText 94%).
private func v0323IsBright(_ r: Int, _ g: Int, _ b: Int) -> Bool { r >= 200 && g >= 200 && b >= 200 }
/// CheckTheme.danger(255,115,117).
private func v0323IsDanger(_ r: Int, _ g: Int, _ b: Int) -> Bool { r >= 200 && g <= 150 && b <= 150 && r - g >= 70 }
/// CheckTheme.pending(255,184,84).
private func v0323IsRetryAmber(_ r: Int, _ g: Int, _ b: Int) -> Bool { r >= 210 && g >= 140 && g <= 210 && b <= 120 }
/// CheckTheme.accent(84,171,255).
private func v0323IsAccent(_ r: Int, _ g: Int, _ b: Int) -> Bool { b >= 200 && r <= 140 && b - r >= 80 }

private func v0323Count(_ bitmap: NSBitmapImageRep, _ match: (Int, Int, Int) -> Bool, fromX: Int = 0) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in min(fromX, bitmap.pixelsWide)..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if match(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { count += 1 }
        }
    }
    return count
}

/// 사람이 볼 그림을 남긴다. 세션 전용 절대 경로를 소스에 박지 않는다 — 퍼블릭 저장소에 개인 머신 경로가 남는다.
private func v0323Save(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0323", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}

// MARK: - 소스 읽기

private func v0323SourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/V0323WorkShortcutTests.swift
        .deletingLastPathComponent()          // Tests/checkTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // repo root
        .appendingPathComponent("Sources/check", isDirectory: true)
}

private func v0323SourceNames() throws -> [String] {
    try FileManager.default.checkSourcesContentsOfDirectory(atPath: v0323SourcesDirectory().path).filter { $0.hasSuffix(".swift") }
}

private func v0323Source(_ name: String) throws -> String {
    try String(contentsOf: v0323SourcesDirectory().appendingCheckSourcePath(name), encoding: .utf8)
}

/// 주석을 걷어낸 코드(줄바꿈은 남긴다). 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다 — 이 파일의 설명문에도
/// 금지 목록의 낱말(tapCreate 등)이 나온다. 문자열 리터럴 안의 `//`·`/*` 는 보존해야 하므로 따옴표 상태를 추적한다
/// (V0316CharacterPickerTests 의 v0316Stripped 와 같은 기계 — 이 저장소의 소스 계약 도구는 파일마다 private 사본을 둔다).
private func v0323Stripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let next = source.index(after: index) < source.endIndex ? source[source.index(after: index)] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = source.index(after: index) }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = source.index(after: index)
        } else if c == "/", next == "*" {
            inBlock = true; index = source.index(after: index)
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}

/// 공백을 한 칸으로 접는다 — 여러 줄 인자 목록의 들여쓰기·빈 줄(주석 자리)이 비교를 흔들지 않게.
private func v0323Collapsed(_ code: String) -> String {
    code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
