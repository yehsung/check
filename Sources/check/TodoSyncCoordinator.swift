import AppKit
import CheckCore
import Foundation
import Observation

// B3: `TodoSync.swift` 가 코어로 가면서 화면·맥 배선 부분만 맥 타깃에 남긴 파일.

/// 동기화 시점과 계정 전환을 잇는 **유일한** 배선. AppDelegate 안 private 메서드로 두면 앱을 띄우지 않고는 한 줄도 검증할 수
/// 없다(`TodoBoardWiring` 을 밖으로 꺼낸 것과 같은 이유) — 테스트는 이 타입을 그대로 쓴다.
///
/// 맞추는 때(명세 A4-5): 실행·로그인 직후 · 보드를 열 때 · 고친 뒤 1.5초 · 로그인 중 5분마다 · 잠에서 깰 때.
@MainActor
final class TodoSyncCoordinator {
    let sync: TodoSync
    private weak var board: CheckTodoBoardController?
    private let userID: @MainActor () -> String?
    private let fileURL: (String?) -> URL
    private let wakeNotifications: NotificationCenter?
    private var lastUserID: String?
    /// 깨어남 구독 토큰. 조정자는 앱 수명 동안 살고 구독 블록은 self 를 weak 로만 잡으므로 따로 떼지 않는다.
    private var wakeToken: NSObjectProtocol?
    private var started = false

    /// - Parameters:
    ///   - userID: 지금 세션의 사용자 id(관찰 가능한 값을 읽어야 계정 전환을 스스로 알아챈다).
    ///   - fileURL: 계정 → 할 일 파일(프로덕션은 `TodoFileStore.defaultURL(userID:)`).
    ///   - wakeNotifications: 깨어남 통지가 오는 곳(프로덕션은 NSWorkspace 의 센터, 테스트는 자기 센터).
    init(
        sync: TodoSync,
        board: CheckTodoBoardController?,
        userID: @escaping @MainActor () -> String?,
        fileURL: @escaping (String?) -> URL,
        wakeNotifications: NotificationCenter?
    ) {
        self.sync = sync
        self.board = board
        self.userID = userID
        self.fileURL = fileURL
        self.wakeNotifications = wakeNotifications
    }

    /// 배선을 건다(멱등).
    func start() {
        guard !started else { return }
        started = true
        let list = sync.list
        list.onLocalChange = { [weak self] in self?.sync.noteLocalChange() }
        list.syncProtectedIDs = { [weak self] in self?.board?.syncProtectedIDs ?? [] }
        board?.onOpened = { [weak self] in self?.sync.requestSync(.boardOpened) }
        if let wakeNotifications {
            wakeToken = wakeNotifications.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in self?.sync.requestSync(.wake) }
            }
        }

        let current = userID()
        lastUserID = current
        let expected = fileURL(current)
        if list.fileURL != expected {
            // 목록을 만든 뒤 세션이 바뀌었다(실행 직후 복구·로그아웃). 그 계정 파일로 바꿔 연다.
            board?.resetForAccountSwitch()
            sync.switchAccount(userID: current, fileURL: expected)
        } else {
            sync.activate(userID: current, reason: .launch)
        }
        arm()
    }

    /// 세션 사용자가 바뀌었는지 보고, 바뀌었으면 보드 입력 상태를 정리하고 파일·동기화 대상을 바꾼다.
    /// (관찰 콜백이 부르는 문. 테스트도 이 문으로 직접 부를 수 있다.)
    func accountMayHaveChanged() {
        let current = userID()
        guard current != lastUserID else { return }
        lastUserID = current
        // 되돌리기 창의 삭제는 **앞 계정 파일에** 확정하고, 편집·초안은 버린다(다음 사람이 앞 사람의 적다 만 글을 보면 안 된다).
        board?.resetForAccountSwitch()
        sync.switchAccount(userID: current, fileURL: fileURL(current))
    }

    private func arm() {
        withObservationTracking {
            _ = userID()
        } onChange: { [weak self] in
            // onChange 는 값이 바뀌기 **직전**(willSet)에 온다 — 한 틱 뒤 메인 액터에서 새 값을 읽는다.
            Task { @MainActor in
                guard let self else { return }
                self.accountMayHaveChanged()
                self.arm()
            }
        }
    }
}
