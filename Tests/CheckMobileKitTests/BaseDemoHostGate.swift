import Foundation
@testable import CheckMobileKit

/// 데모 조립(`MobileDemo.environment`)을 **한 번에 하나만** 돌게 하는 문.
///
/// 왜: 그 조립은 전역 호스트 하나(`MobileDemo.host`)와 공용 저장소 하나(`AingSharedStorage.temporary(name: "demo")`)를 쓴다 —
/// 새 조립이 그 호스트의 응답기를 **장면째 갈아 끼우고**(`index.response(for:scenario:)`) 저장소 폴더와 defaults 도메인을 지운다.
/// 두 스위트가 병렬로 조립하면 한쪽의 로그인이 **다른 장면의 픽스처**를 받아 영영 끝나지 않는다.
///
/// 실측(w16): `PushCoordinatorTests.noPrimerInBackgroundOrDemo` 가 `baseWaitUntil { demo.session.isSignedIn }` 에서 83초를
/// 기다리다 실패했다 — 같은 시각 `BaseAppModelTests.demoEnvironments` 가 `login`·`signup` 장면을 순회하며 같은 호스트의
/// 응답기를 바꾸고 있었다(순회가 길어질수록 자주 터진다). 기다림을 늘리는 것은 고치는 게 아니다 — 겹치지 않게 해야 한다.
///
/// 쓰는 법: 데모 조립을 만드는 자리를 통째로 감싼다(`tearDown` 까지 안에 둔다 — 그게 호스트를 내리는 지점이다).
@MainActor
func baseWithDemoHost<T>(_ body: () async throws -> T) async rethrows -> T {
    await BaseDemoHostGate.shared.acquire()
    defer { BaseDemoHostGate.shared.release() }
    return try await body()
}

/// 재진입 없는 비동기 뮤텍스(대기는 잠들고, 스레드를 잡아 두지 않는다).
final class BaseDemoHostGate: @unchecked Sendable {
    static let shared = BaseDemoHostGate()

    private let lock = NSLock()
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isBusy {
                waiters.append(continuation)
                lock.unlock()
            } else {
                isBusy = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()
        if waiters.isEmpty {
            isBusy = false
            lock.unlock()
            return
        }
        let next = waiters.removeFirst()
        lock.unlock()
        next.resume()
    }
}
