import Foundation
import Observation
import Testing
@testable import CheckCore
@testable import check

// v0.3.69 미니게임 창 사이드바 — 대결 문의 '받은 신청' 점이 **창이 실제로 부르는 자리**(`MiniGameDuelInvites(store:)`)에서
// 스토어의 네 사실을 따라가는가. 렌더 시험은 `previewInvites` 로 점을 **강제로** 그리므로 이 길(스토어 → 점)을 안 지난다 —
// 모양만 재면 초록이다. 여기서는 창 뷰 body 가 읽는 바로 그 생성자를 관찰 추적 안에서 불러, 신청이 들어오고 빠질 때
// ① 값이 뒤집히고 ② 관찰이 깨어나는지(= 창이 다시 그려지는지)를 잰다. 대조군: 아무 사실도 안 바꾸면 깨어나지 않는다.

private final class SidebarInviteFlag: @unchecked Sendable {
    var fired = false
}

@MainActor
private func sidebarInviteStore() -> WorkTimerStore {
    let suiteName = CheckTestScratch.suitePath(named: "check-v0369-minigame-sidebar-invite-tests")
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
}

/// `body` 를 돌리는 동안 창이 읽는 `MiniGameDuelInvites(store:)` 의 관찰이 깨어났는가.
@MainActor
private func sidebarInviteWakes(_ store: WorkTimerStore, _ body: () throws -> Void) rethrows -> Bool {
    let flag = SidebarInviteFlag()
    withObservationTracking {
        _ = MiniGameDuelInvites(store: store)
    } onChange: {
        flag.fired = true
    }
    try body()
    return flag.fired
}

@MainActor
@Test("사이드바 신청 점: 창이 부르는 MiniGameDuelInvites(store:) 가 네 사실을 따라가고, 바뀌면 창을 깨운다")
func sidebarInviteDotsFollowTheLiveStoreFacts() throws {
    let store = sidebarInviteStore()
    #expect(MiniGameDuelInvites(store: store) == MiniGameDuelInvites(), "아무 신청도 없는데 점이 섰다")

    // 대조군 — 관계없는 값만 바꾸면 깨어나지 않는다(관찰이 아무 데나 묶여 있으면 아래 '깨어났다' 가 공짜 초록이다).
    #expect(!sidebarInviteWakes(store) { store.gomoku.outgoing = nil }, "신청과 무관한 값에 점이 깨어난다")

    // ① 오목 — 메뉴바와 같은 사실(pendingIncomingInvites).
    let gomokuPeer = GomokuUser(id: "00000000-0000-0000-0000-00000000000a", displayName: "민수", avatarURL: nil,
                                characterID: "fox", isWorking: true, isCapable: true, inMatch: false)
    #expect(sidebarInviteWakes(store) {
        store.gomoku.incoming = [GomokuInvite(id: "g-1", peer: gomokuPeer, stake: 5, expiresAt: Date().addingTimeInterval(50))]
    }, "오목 신청이 들어왔는데 창이 안 깨어난다 — 점이 다음 무관한 갱신까지 안 선다")
    #expect(MiniGameDuelInvites(store: store) == MiniGameDuelInvites(gomoku: true))
    // 차단으로 걷어낸 사람의 신청은 점을 내린다(메뉴바와 같은 파생값을 읽는다는 증거).
    #expect(sidebarInviteWakes(store) { store.gomoku.hiddenPeerIDs = [gomokuPeer.id] })
    #expect(MiniGameDuelInvites(store: store).gomoku == false, "차단한 사람의 오목 신청에 점이 남았다")
    store.gomoku.hiddenPeerIDs = []
    #expect(sidebarInviteWakes(store) { store.gomoku.incoming = [] })
    #expect(MiniGameDuelInvites(store: store) == MiniGameDuelInvites())

    // ② 체스.
    let chessPeer = ChessUser(id: "00000000-0000-0000-0000-000000000011", displayName: "민수", avatarURL: nil,
                              characterID: "fox", isWorking: true, isCapable: true, inMatch: false, center: nil)
    #expect(sidebarInviteWakes(store) {
        store.chess.incoming = ChessInvite(id: "c-1", peer: chessPeer, stake: 5, expiresAt: Date().addingTimeInterval(48))
    }, "체스 신청이 들어왔는데 창이 안 깨어난다")
    #expect(MiniGameDuelInvites(store: store) == MiniGameDuelInvites(chess: true))
    store.chess.incoming = nil

    // ③ 테트리스.
    let tetrisPeer = TetrisDuelUser(id: "00000000-0000-0000-0000-000000000012", displayName: "준호", avatarURL: nil,
                                    characterID: "squirrel", isWorking: true, isCapable: true, inMatch: false, isFocused: false)
    #expect(sidebarInviteWakes(store) {
        store.tetris.incoming = [TetrisDuelInvite(id: "t-1", peer: tetrisPeer, stake: 3, expiresAt: Date().addingTimeInterval(40))]
    }, "테트리스 신청이 들어왔는데 창이 안 깨어난다")
    #expect(MiniGameDuelInvites(store: store) == MiniGameDuelInvites(tetris: true))
    store.tetris.incoming = []

    // ④ 아잉 큐브 — 로비의 invites(서버 답 그대로)를 읽는다.
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let lobbyJSON = #"{"status":"ok","invites":[{"id":"d0000000-0000-4000-8000-0000000000aa"}],"public_rooms":[],"users":[]}"#
    let lobby = try decoder.decode(RummyLobby.self, from: Data(lobbyJSON.utf8))
    #expect(sidebarInviteWakes(store) { store.rummy.lobby = lobby }, "큐브 초대가 들어왔는데 창이 안 깨어난다")
    #expect(MiniGameDuelInvites(store: store) == MiniGameDuelInvites(rummy: true))
    #expect(sidebarInviteWakes(store) { store.rummy.lobby = nil })
    #expect(MiniGameDuelInvites(store: store) == MiniGameDuelInvites())

    // 창 뷰가 실제로 이 생성자를 부른다(스냅샷 전용 previewInvites 가 없을 때) — 위 측정이 창의 길이라는 연결.
    let panel = try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/MiniGamePanel.swift"), encoding: .utf8)
    #expect(panel.contains("invites: previewInvites ?? MiniGameDuelInvites(store: store),"),
            "창 사이드바가 스토어의 신청 사실을 안 읽는다")
}
