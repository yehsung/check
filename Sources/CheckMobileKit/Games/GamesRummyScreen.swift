import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 큐브 **화면 하나** — 로비 · 방 · 판 · 결과를 코어 `phase` 로 갈아 끼운다(체스·테트리스와 같은 구조). 각 단계의 그림은 파일 단위로 나뉜다:
//   `GamesRummyLobby.swift`(로비·순위) · `GamesRummyRoom.swift`(방) · `GamesRummyMatch.swift`(판 — 가로) · `GamesRummyResult.swift`(결과) · `GamesRummyRules.swift`(규칙 시트).
// 판만 가로다. 방향은 이 화면이 정하지 않는다 — `GamesStore.rummyInterfaceOrientation` 이 상태에서 계산한다(`GamesRummyOrientation.swift`).
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesRummyCard` · `GamesRummyExit` · `GamesRummyUnavailable` · `GamesRummySeating`)은 `#if os(iOS)` 밖이다 — 폰 뷰는 맥 스위트가 한 줄도 못 본다.
//
// ── 수명은 직접 코어를 부르지 않는다 ──
// `onAppear` → `GamesStore.rummyScreenDidAppear()`, `onDisappear` → `…DidDisappear()` 뿐이다. 하트비트는 코어가 창과 무관하게 돌린다.

/// 로비 안 탭 둘(순위는 자식 화면이 아니라 탭이다 — 자식을 push 하면 `onDisappear` 로 폴링이 죽는다).
package enum GamesRummyLobbyTab: String, Hashable, CaseIterable, Sendable {
    case people, ranking

    package var title: String {
        switch self {
        case .people: return GamesRummyText.usersTab
        case .ranking: return GamesRummyText.rankTab
        }
    }
}

#if DEBUG
extension GamesRummyLobbyTab {
    /// 데모 라우트 꼬리가 고른 탭 → 이 화면의 탭(데모 값은 Release 에서 이름이 사라져야 해서 열거가 따로다 — 테트리스와 같다).
    package init(demo tab: MobileDemoRummyRoute.LobbyTab) {
        switch tab {
        case .people: self = .people
        case .ranking: self = .ranking
        }
    }
}
#endif

/// 게임 탭 **아잉 큐브 카드**의 한 줄 판정(칩 + 보조 줄). 서열을 한 열거로 못 박는다: 차단 > 판 진행 > 방 > 받은 초대 > 전적 > 기본 한 줄.
@MainActor
package enum GamesRummyCard {
    package enum Line: String, Equatable, Sendable, CaseIterable {
        case blocked, activeMatch, room, incoming, record, idle
    }

    package static func line(_ store: GamesStore) -> Line {
        if store.rummyEntryBlock != nil { return .blocked }
        if store.hasActiveRummyMatch { return .activeMatch }
        if store.isInRummyRoom { return .room }
        if !store.rummy.incomingInvites.isEmpty { return .incoming }
        return store.rummy.lobby?.me?.games != nil ? .record : .idle
    }

    package static func chip(_ store: GamesStore) -> String? {
        switch line(store) {
        case .blocked: return ChessPhoneText.entryBlock(playing: store.rummyEntryBlock?.text)
        case .activeMatch: return GamesRummyText.activeChip
        case .room: return GamesRummyText.roomChip
        case .incoming: return GamesRummyText.incomingChip(store.rummy.incomingInvites.count)
        case .record, .idle: return nil
        }
    }

    /// 보조 줄. 막혔을 때 칩은 왜 막혔는지, 이 줄은 언제 풀리는지를 말한다(폰엔 호버 툴팁이 없다).
    package static func detail(_ store: GamesStore) -> String? {
        let me = store.rummy.lobby?.me
        let recordLine = me?.games.map { GamesRummyText.recordTitle + " " + GamesRummyText.record(games: $0, wins: me?.wins) }
        switch line(store) {
        case .blocked:
            return ChessPhoneText.entryBlockHint(playing: store.rummyEntryBlock?.text, blocked: .rummy)
        case .activeMatch, .room, .incoming, .record:
            return recordLine
        case .idle:
            return GamesRummyText.idleLine
        }
    }
}

/// 이 기기가 지금 큐브를 할 수 없다(코어 `availability`) — 로비 대신 세울 안내. 문구는 코어 것이다(맥과 같은 말).
package enum GamesRummyUnavailable {
    package static func title(_ availability: RummyStore.Availability) -> String? {
        switch availability {
        case .available: return nil
        case .updateRequired: return RummyNoticeText.updateRequired
        case .serverMissing: return RummyNoticeText.unavailable
        }
    }

    package static func icon(_ availability: RummyStore.Availability) -> String {
        availability == .updateRequired ? "arrow.up.circle" : "clock"
    }
}

/// 의도적 이탈(맥 `RummyExitFlow` 의 폰 짝). 판단은 코어 `RummyExitPolicy` 한 곳이고, **이 기기가 손대지 않은 판이면 아무것도 안 보낸다**(SPEC-v2 §6).
@MainActor
package enum GamesRummyExit {
    /// 로그아웃 앞(세션을 지우기 전 — 뒤면 이탈 요청이 토큰 없이 떠난다). 최대 2초(코어 상한).
    /// 계정 삭제 앞에는 **부르지 않는다**: 서버 `delete_my_account` 가 같은 트랜잭션에서 판을 기권 처리한다. 먼저 나가면 삭제가 실패해도 기권은 안 되돌아간다.
    package static func leaveBeforeSessionEnds(_ rummy: RummyStore) async {
        guard RummyExitPolicy.needsExitLeave(rummy) else { return }
        _ = await rummy.leaveForExit(reason: .signOut)
    }

    /// 화면의 [나가기]를 눌렀다 — 무엇을 할지.
    package static func decision(_ rummy: RummyStore) -> RummyCloseDecision {
        RummyExitPolicy.closeDecision(for: rummy)
    }

    /// 확인 시트의 [나가기]. **낡은 판단으로 이탈하지 않는다** — 고르는 순간 다시 판단한다(확인이 떠 있는 동안 판이 끝났거나 시작됐으면 기권시키지 않는다). 나갔으면 true.
    @discardableResult
    package static func confirm(asked: RummyCloseDecision, rummy: RummyStore) async -> Bool {
        guard decision(rummy) == asked else { return false }
        _ = await rummy.leaveForExit(reason: .windowClosed)
        await settleAfterLeaving(rummy)
        return true
    }

    /// 묻지 않는 나가기(손님이 방에서). 그새 시작된 판이면 코어가 나가지 않고 그 판을 든다(`leaveRoomForExit`).
    package static func leaveRoom(_ rummy: RummyStore) async {
        _ = await rummy.leaveRoomForExit(reason: .windowClosed)
        await settleAfterLeaving(rummy)
    }

    /// 나간 뒤 같은 화면이 로비로 남는다(맥은 창이 닫혀 안 드러난다). 코어 `leave()`·`dismissResult()` 처럼 안내줄을 지우고 로비를 다시 읽는다 —
    /// 안 읽으면 낡은 `activeMatchId` 로 게임 탭 카드가 최대 30초 '판 진행 중'이고, 닫힌 방이 공개 목록에 남는다. 시작된 판을 들고 남았으면(`leaveRoomForExit`) 아무것도 안 한다.
    private static func settleAfterLeaving(_ rummy: RummyStore) async {
        guard rummy.match == nil else { return }
        rummy.setNotice(nil)
        await rummy.refreshLobby()
    }

    /// 확인 시트 글자(제목 · 설명 · 버튼).
    package static func prompt(_ decision: RummyCloseDecision) -> (title: String, detail: String, confirm: String)? {
        switch decision {
        case .confirmForfeit: return (GamesRummyText.forfeitTitle, GamesRummyText.forfeitDetail, GamesRummyText.forfeitConfirm)
        case .confirmCloseRoom: return (GamesRummyText.closeRoomTitle, GamesRummyText.closeRoomDetail, GamesRummyText.closeRoomConfirm)
        case .close, .leaveRoom: return nil
        }
    }
}

/// 탁자 의자 넷(순서는 코어 `RummyTableSeating` · 글자는 이 표). 나 = 세션 id, 남 = 자리 user_id — 엉뚱한 칸을 넘기면 남의 캐릭터가 선다.
package enum GamesRummySeating {
    package static func chairs(room: RummyRoom?, myUserID: UUID?, myName: String, myAvatarURL: String?,
                               myCharacter: String?) -> [RummyTableChair] {
        let solo = RummyTableChair(kind: .person, userID: myUserID, name: myName, avatarURL: myAvatarURL,
                                   character: myCharacter, tag: GamesRummyText.me, isMe: true)
        return RummyTableSeating.chairs(room: room, myUserID: myUserID, solo: solo) { seat, facts in
            let tag: String
            if facts.isInvited {
                tag = GamesRummyText.waitingAnswer
            } else if facts.isMe {
                tag = facts.isHost ? "\(GamesRummyText.me) · \(GamesRummyText.hostTag)" : GamesRummyText.me
            } else {
                tag = facts.isHost ? GamesRummyText.hostTag : GamesRummyText.seated
            }
            return RummyTableChair(kind: .person, userID: seat.userId, name: seat.displayName ?? "?",
                                   avatarURL: seat.avatarUrl, character: seat.character,
                                   seatNo: seat.state == .joined ? seat.seatNo : nil, tag: tag, isHost: facts.isHost,
                                   isMe: facts.isMe, dimmed: facts.isInvited)
        }
    }
}

#if os(iOS)

/// 아잉 큐브 화면 — 코어 `RummyStore.phase` 로 단계를 갈아 끼운다. 각 단계 뷰의 입력은 여기서 정한다:
///  · `store` 하나가 전부다(`store.rummy` · `store.context`). 뷰가 스토어를 따로 쥐지 않는다.
///  · `inviteQueue` = 방 없이 [초대] · 결과 [한 판 더]의 '부를 사람' 줄(화면이 쥐고 `isWorking`·판 id 변화에 민다).
///  · `onExit` = 화면의 [나가기](이탈 판단·확인 시트는 여기 한 곳이다 — 단계 뷰가 `leave`·`leaveForExit` 를 직접 부르지 않는다).
///  · 규칙 시트는 `store.rummy.rulesShown` 하나로 연다(`rulesShown = true`).
///  · 반응: 고르는 자리는 여기가 쥐고(`onReaction` — 판 화면은 작은 판 · 결과는 시트), 말풍선은 단계 뷰가 낸 자리 앵커(`GamesRummySeatAnchorKey`) 위에 여기서 그린다.
///  · ⚠️ 데모의 시계는 고정이다(`MobileClock.fixed`). 남은 초는 `TimelineView` 의 날짜가 아니라 `store.rummy.clock()` 으로 물어라 — 날짜를 쓰면 데모 판이 늘 0초로 그려진다.
struct GamesRummyScreen: View {
    let store: GamesStore

    @State private var inviteQueue = RummyInviteQueue()
    @State private var tab: GamesRummyLobbyTab = .people
    /// 떠 있는 나가기 확인(판 중 기권 · 방장 방 닫기).
    @State private var exitPrompt: RummyCloseDecision?
    /// 판 화면의 반응 작은 판 · 결과의 고르기 시트. 값을 나눈 까닭: 하나로 쓰면 작은 판을 연 채 판이 끝나는 순간 시트가 떴다 내려간다(값을 끄는 `onChange` 는 본문 뒤에 돈다).
    @State private var reactionPanelOpen = false
    @State private var reactionSheetOpen = false
    #if DEBUG
    @State private var demoLeaving = false
    #endif

    private var rummy: RummyStore { store.rummy }

    var body: some View {
        content
            .overlayPreferenceValue(GamesRummySeatAnchorKey.self) { anchors in
                GamesRummyReactionLayer(rummy: rummy, anchors: anchors, settled: demoSettlesBubbles)
            }
            // 단계 뷰의 폭이 어떻든 화면을 다 채운다 — 이 줄이 없으면 내용이 좁은 단계(방·결과)의 양옆이 까맣게 빈다(실화면에서 봤다).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(GamesRummyText.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: rulesBinding) {
                GamesRummyRulesView()
            }
            .sheet(isPresented: $reactionSheetOpen) {
                GamesRummyReactionPicker(rummy: rummy)
            }
            .overlay {
                if reactionPanelOpen, rummy.phase == .playing {
                    GamesRummyReactionPanel(rummy: rummy, onClose: { reactionPanelOpen = false })
                }
            }
            .alert(exitPromptCopy?.title ?? "", isPresented: exitPromptBinding, presenting: exitPromptCopy) { copy in
                Button(copy.confirm, role: .destructive) { confirmExit() }
                Button(GamesRummyText.keepPlaying, role: .cancel) { exitPrompt = nil }
            } message: { copy in
                Text(copy.detail)
            }
            .onAppear {
                store.rummyScreenDidAppear()
                GamesRummyArt.shared.refreshIfNeeded(projectURL: store.context.service.projectURL,
                                                     isDemo: store.context.isDemo)
                applyDemo()
            }
            .onDisappear { store.rummyScreenDidDisappear() }
            // 스토어 동작이 끝날 때 · 판이 바뀔 때 초대 줄을 민다(맥 `.rummyInviteQueue` 와 같다).
            .onChange(of: rummy.isWorking) { _, _ in inviteQueue.pump(rummy) }
            .onChange(of: rummy.match?.id) { _, _ in
                inviteQueue.pump(rummy)
                exitPrompt = nil
                applyDemo()
            }
            // 방이 판으로 · 판이 결과로 넘어가면(판 id 는 그대로다) 낡은 확인을 거둔다 — 눌러도 `confirm` 이 막지만 틀린 글자가 떠 있게 두지 않는다.
            .onChange(of: rummy.phase) { _, _ in
                exitPrompt = nil
                reactionPanelOpen = false
                reactionSheetOpen = false
                applyDemo()
            }
            .onChange(of: rummy.editor != nil) { _, _ in applyDemo() }
    }

    @ViewBuilder
    private var content: some View {
        if let unavailable = GamesRummyUnavailable.title(rummy.availability) {
            EmptyStateView(systemImage: GamesRummyUnavailable.icon(rummy.availability), title: unavailable)
                .padding(.horizontal, MobileTheme.sideMargin)
        } else {
            switch rummy.phase {
            case .lobby:
                GamesRummyLobbyView(store: store, inviteQueue: inviteQueue, tab: $tab)
            case .room:
                GamesRummyRoomView(store: store, inviteQueue: inviteQueue, onExit: requestExit)
            case .playing:
                GamesRummyMatchView(store: store, onExit: requestExit, onReaction: { reactionPanelOpen = true })
            case .finished:
                GamesRummyResultView(store: store, inviteQueue: inviteQueue, onReaction: { reactionSheetOpen = true })
            }
        }
    }

    private var demoSettlesBubbles: Bool {
        #if DEBUG
        store.demoRummyRoute?.scene == .matchReaction
        #else
        false
        #endif
    }

    private var rulesBinding: Binding<Bool> {
        Binding(get: { rummy.rulesShown }, set: { rummy.rulesShown = $0 })
    }

    private var exitPromptBinding: Binding<Bool> {
        Binding(get: { exitPrompt != nil }, set: { if !$0 { exitPrompt = nil } })
    }

    private var exitPromptCopy: (title: String, detail: String, confirm: String)? {
        exitPrompt.flatMap(GamesRummyExit.prompt)
    }

    /// 화면의 [나가기]. 놀던 기기는 그냥 닫는다(아무것도 안 보낸다 — SPEC-v2 §6).
    private func requestExit() {
        switch GamesRummyExit.decision(rummy) {
        case .close:
            store.context.router.popToRoot(.games)
        case .leaveRoom:
            Task { await GamesRummyExit.leaveRoom(rummy) }
        case let asked:
            exitPrompt = asked
        }
    }

    private func confirmExit() {
        guard let asked = exitPrompt else { return }
        exitPrompt = nil
        Task { await GamesRummyExit.confirm(asked: asked, rummy: rummy) }
    }

    /// 데모 스크린샷 전용: 라우트 꼬리의 로비 탭 · 작업 판. Release 에서는 한 줄도 돌지 않는다(`demoRummyRoute` 가 DEBUG 전용).
    private func applyDemo() {
        #if DEBUG
        guard let demo = store.demoRummyRoute else { return }
        tab = GamesRummyLobbyTab(demo: demo.lobbyTab)
        demo.applyEdit(to: rummy)
        guard rummy.phase == .playing else { return }
        if demo.scene == .matchReactionPicker { reactionPanelOpen = true }
        if demo.scene == .matchExit { exitPrompt = GamesRummyExit.decision(rummy) }
        // 방향이 실제로 세로로 돌아오는지 보는 장면(합성 입력 없이 빠져나가는 길을 그대로 밟는다).
        if demo.scene == .matchLeave || demo.scene == .matchSignOut, !demoLeaving {
            demoLeaving = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if demo.scene == .matchLeave {
                    store.context.router.popToRoot(.games)
                } else {
                    await store.context.session.signOut()
                }
            }
        }
        #endif
    }
}

#endif
