import CheckMobileShared
import Foundation

/// 위젯 스냅샷 쓰기 창구(SPEC-ios §4). 지금 탭이 데이터를 받을 때마다 `update { … }` 로 고친다.
///
/// - 파일은 App Group `widget-snapshot.json` 하나(`WidgetSnapshotCodec` — 원자적 쓰기).
/// - 위젯 새로고침(`reloadTimelines` — iOS 조립이 `WidgetCenter.shared.reloadAllTimelines()` 를 넣는다)은 **30초 스로틀**:
///   값이 1초마다 바뀌어도(근무 누적) 시스템 위젯 예산을 태우지 않는다. 스로틀에 걸린 변경은 창이 끝날 때 한 번 더 민다.
/// - 로그아웃은 세션 스토어가 파일을 지운다(`clear()` 도 같은 일을 한다).
@MainActor
package final class WidgetSnapshotWriter {
    package nonisolated static let reloadThrottleSeconds: TimeInterval = 30

    private let url: URL
    private let clock: MobileClock
    private let reloadTimelines: @MainActor () -> Void
    private var lastReloadAt: Date?
    private var trailingReload: Task<Void, Never>?
    /// 마지막으로 쓴 값(같은 값이면 파일도 위젯도 건드리지 않는다).
    package private(set) var current: WidgetSnapshot?
    /// 실제 위젯 새로고침 횟수(테스트).
    package private(set) var reloadCount = 0

    package init(url: URL, clock: MobileClock, reloadTimelines: @escaping @MainActor () -> Void) {
        self.url = url
        self.clock = clock
        self.reloadTimelines = reloadTimelines
        self.current = WidgetSnapshotCodec.read(from: url)
    }

    /// 현재 스냅샷(없으면 빈 스냅샷)을 고쳐 쓴다. generatedAt 은 이 호출의 시각으로 바뀐다.
    package func update(_ mutate: (inout WidgetSnapshot) -> Void) {
        let now = clock.now()
        var next = current ?? WidgetSnapshot(generatedAt: now)
        mutate(&next)
        next.version = WidgetSnapshot.currentVersion
        var comparable = next
        comparable.generatedAt = current?.generatedAt ?? now
        guard comparable != current else { return }
        next.generatedAt = now
        do {
            try WidgetSnapshotCodec.write(next, to: url)
            current = next
            requestReload(now: now)
        } catch {
            // 쓰기 실패는 조용히 — 위젯은 직전 파일을 계속 그린다.
        }
    }

    /// 스냅샷 삭제 + 위젯 새로고침(스로틀 없이).
    package func clear() {
        WidgetSnapshotCodec.remove(at: url)
        current = nil
        trailingReload?.cancel()
        trailingReload = nil
        lastReloadAt = clock.now()
        reloadCount += 1
        reloadTimelines()
    }

    /// 다른 주체(세션 스토어)가 파일을 지웠다 — 기억만 비운다.
    package func forgetCurrent() {
        current = nil
    }

    private func requestReload(now: Date) {
        if let last = lastReloadAt, now.timeIntervalSince(last) < Self.reloadThrottleSeconds, now >= last {
            guard trailingReload == nil else { return }
            let wait = Self.reloadThrottleSeconds - now.timeIntervalSince(last)
            trailingReload = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                self.trailingReload = nil
                self.lastReloadAt = self.clock.now()
                self.reloadCount += 1
                self.reloadTimelines()
            }
            return
        }
        lastReloadAt = now
        reloadCount += 1
        reloadTimelines()
    }
}
