import CheckCore
import CoreGraphics
import Foundation
import Observation

// MARK: - 메시지 사진 그림 캐시(폰 1.0.19 — 맥 0.3.86 `MessagePhotoImageCache` 의 폰 짝)
//
// **경로가 열쇠**이고 디스크에 남기지 않는다(메모리만). 계정(`owner`)이 바뀌면 통째로 비운다 — 남의 비공개 사진이 다음 계정 화면에
// 남지 않게. 경로마다 받기는 하나만 날고, 실패는 이 세션 동안 기억한다(사람이 실패 칸을 누를 때만 다시). 관찰 칸은 `states` 하나다.

/// 사진 한 장의 받기 상태.
package enum MessagesPhotoLoadState: Equatable, Sendable {
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
package final class MessagesPhotoImageCache {
    /// 화면용으로 줄여 드는 긴 변(px) — 말풍선 · 크게 보기를 3배 화면에서 그리기에 넉넉하다.
    package nonisolated static let displayPixels = 1_200
    @ObservationIgnored private let images = NSCache<NSString, MessagePhotoImageBox>()
    package private(set) var states: [String: MessagesPhotoLoadState] = [:]
    @ObservationIgnored package private(set) var owner: String?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var epoch = 0

    package init() {
        images.totalCostLimit = 120 * 1_024 * 1_024
    }

    /// 그 경로의 그림(이 계정 것만). 관찰 칸을 먼저 읽는다 — 받기가 끝나면 부른 뷰가 다시 그려진다.
    package func image(for path: String, owner: String?) -> CGImage? {
        let state = states[path]
        guard let owner, owner == self.owner, state == .loaded else { return nil }
        return images.object(forKey: path as NSString)?.image
    }

    package func state(for path: String, owner: String?) -> MessagesPhotoLoadState? {
        let state = states[path]
        guard let owner, owner == self.owner else { return nil }
        return state
    }

    package var inFlightCount: Int { tasks.count }

    /// 그림을 넣는다(보낸 내 사진 — 받지 않는다).
    package func insert(_ box: MessagePhotoImageBox, path: String, owner: String) {
        adopt(owner)
        tasks[path]?.cancel()
        tasks[path] = nil
        images.setObject(box, forKey: path as NSString, cost: box.image.width * box.image.height * 4)
        if states[path] != .loaded { states[path] = .loaded }
    }

    /// 그 경로를 받는다(경로마다 하나만 · 실패는 기억 · 이미 있으면 아무것도 안 한다).
    package func load(path: String, owner: String, fetch: @escaping @Sendable @MainActor () async throws -> Data) {
        adopt(owner)
        switch states[path] {
        case .some(.loaded) where images.object(forKey: path as NSString) != nil: return
        case .some(.failed): return
        default: break
        }
        guard tasks[path] == nil else { return }
        states[path] = .loading
        let epoch = self.epoch
        tasks[path] = Task { @MainActor [weak self] in
            var box: MessagePhotoImageBox?
            do {
                let fetched = try await fetch()
                box = await Task.detached(priority: .userInitiated) {
                    MessagePhotoEncoder.decodeForDisplay(fetched, maxPixelSize: MessagesPhotoImageCache.displayPixels)
                }.value
            } catch {
                box = nil
            }
            guard let self, epoch == self.epoch else { return }
            self.tasks[path] = nil
            if let box {
                self.images.setObject(box, forKey: path as NSString, cost: box.image.width * box.image.height * 4)
                self.states[path] = .loaded
            } else {
                self.states[path] = .failed
            }
        }
    }

    /// 실패 기억을 지운다(사람이 실패 칸을 눌렀을 때만).
    package func forgetFailure(path: String) {
        if states[path] == .failed { states[path] = nil }
    }

    /// 통째로 비운다(로그아웃 · 계정 바뀜). 날던 받기의 결과는 순번으로 버린다.
    package func wipe() {
        epoch += 1
        for task in tasks.values { task.cancel() }
        tasks = [:]
        images.removeAllObjects()
        if !states.isEmpty { states = [:] }
        owner = nil
    }

    private func adopt(_ owner: String) {
        guard self.owner != owner else { return }
        wipe()
        self.owner = owner
    }
}
