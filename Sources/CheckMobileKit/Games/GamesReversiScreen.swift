import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **화면 하나**(1.0.17) — 로비 · 판 · AI 연습 · 결과 · 관전 · 순위를 코어 `phase`·`spectating` 으로 갈아 끼운다(체스와 같은 구조).
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesReversiCard` · `GamesReversiUnavailable` · `GamesReversiChallengeGate` · `GamesReversiStakeSend`)은 `#if os(iOS)` **밖**이다 —
// 폰 뷰는 맥 스위트가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'). 그림(뷰)은 판정을 받아 그리기만 한다.
//
// ── 수명은 직접 코어를 부르지 않는다 ──
// `onAppear` → `GamesStore.reversiScreenDidAppear()`, `onDisappear` → `…DidDisappear()` 뿐이다. 그 둘이 `openWindow`·`windowDidShow`·
// `stopWatching`·`windowDidHide`·`windowDidClose` 의 순서와 끝난 판 접기를 쥔다(배선 갈래 1/4). 여기서 코어 창 문을 직접 부르면 그 순서가 두 벌이 된다.
// 순위·관전은 **자식 화면이 아니라 이 화면 안의 절·탭**이어야 한다 — push 하면 `onDisappear` → `windowDidHide()` 로 폴링이 죽는다(체스 머리말).

/// 게임 탭 **아잉 뒤집기 카드**가 그리는 한 줄의 판정(칩 + 보조 줄). 서열을 한 열거로 못 박는다(테트리스 카드와 같은 까닭 — 자리마다 삼항으로 고르면
/// 서열이 두 벌이 되어 한쪽만 고쳐진다): 차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 한 줄.
@MainActor
package enum GamesReversiCard {
    package enum Line: String, Equatable, Sendable, CaseIterable {
        /// 다른 게임 판이 흐른다 — 카드가 흐려지고 눌리지 않는다.
        case blocked
        /// 내 판이 흐른다(1:1 — 같은 계정 다른 기기의 판 포함 · AI 연습 판은 받은 신청이 없을 때만).
        case activeMatch
        case incoming
        case outgoing
        case record
        /// 칩도 보조 줄 재료도 없다 — **할 일**을 말한다.
        case idle
    }

    package static func line(_ store: GamesStore) -> Line {
        if store.reversiEntryBlock != nil { return .blocked }
        let reversi = store.reversi
        let incoming = reversi.visibleIncomingInvites.count
        // AI 연습 판은 사람의 신청을 가리지 않는다 — 오목·체스 카드와 같은 규칙(`GamesText.hubShowsActiveMatch`).
        if GamesText.hubShowsActiveMatch(active: store.hasActiveReversiMatch, isAIMatch: reversi.isAIMatch, incoming: incoming) {
            return .activeMatch
        }
        if incoming > 0 { return .incoming }
        if reversi.outgoing != nil { return .outgoing }
        return reversi.record != nil ? .record : .idle
    }

    /// 칩(없으면 nil). 막힌 칩은 **두는 판의 이름**을 말한다(`ChessPhoneText` 한 곳이 조립한다 — 뷰가 지어내지 않는다).
    package static func chip(_ store: GamesStore) -> String? {
        switch line(store) {
        case .blocked: return ChessPhoneText.entryBlock(playing: store.reversiEntryBlock?.text)
        case .activeMatch: return GamesText.activeMatchChip
        case .incoming: return ReversiPhoneText.incomingChip(store.reversi.visibleIncomingInvites.count)
        case .outgoing, .record, .idle: return nil
        }
    }

    /// 보조 줄(없으면 nil). 막혔을 때 칩은 왜 막혔는지, 이 줄은 **언제 풀리는지**를 말한다(폰엔 호버 툴팁이 없다).
    package static func detail(_ store: GamesStore) -> String? {
        let recordLine = store.reversi.record.map { ReversiPhoneText.recordTitle + " " + ReversiPhoneText.record($0) }
        switch line(store) {
        case .blocked:
            return ChessPhoneText.entryBlockHint(playing: store.reversiEntryBlock?.text, blocked: .reversi)
        case .activeMatch, .incoming, .record:
            return recordLine
        case .outgoing:
            return ReversiPhoneText.outgoingLine
        case .idle:
            return ReversiPhoneText.idleLine
        }
    }
}

/// 이 기기·서버 조합에서 아잉 뒤집기를 할 수 없다(코어 `availability`) — 로비 대신 세울 안내. 문구는 코어 것이다(맥과 같은 말).
package enum GamesReversiUnavailable {
    package static func title(_ availability: ReversiAvailability) -> String? {
        switch availability {
        case .available: return nil
        case .updateRequired: return ReversiNoticeText.updateRequired
        case .serverMissing: return ReversiNoticeText.unavailable
        }
    }

    package static func icon(_ availability: ReversiAvailability) -> String {
        availability == .updateRequired ? "arrow.up.circle" : "clock"
    }
}

/// 상대 줄 [도전] 버튼이 **눌리는가** — 맥 `ReversiPanel` 의 상대 줄 게이트(`isCapable && !inMatch && !focusMode && !isBusy`)에 폰에서 셋을 더한 것이다:
/// 보낸 신청 · 내 판(**AI 연습 포함**) · **다른 게임의 판**(한 사람 한 판, 다섯 방향).
///
/// ★ `store.match == nil` 이 **AI 연습 판까지** 막는 자리다(`GamesStore.hasLiveReversiAIGame` 머리말) — 코어 `challenge` 에는 AI 가드가 없어 여기를 열면
///   요청이 그대로 나가고, 1:1 판이 서는 순간 두던 AI 판이 말없이 사라진다.
/// ★ `user.isCapable` 은 서버 `capable` 이 **nil 이면 false** 다(코어 `user(from:)`) — 모르는 상대에게 신청해 `target_outdated` 를 받는 것보다 낫다.
///   리버시 화면이 없는 폰(1.0.16 이하)은 서버 상수(`reversi_ios_min_build`)가 capable=false 로 내린다.
package enum GamesReversiChallengeGate {
    @MainActor
    package static func isEnabled(user: ReversiUser, store: ReversiStore, blockedBy other: GamesBusyGame?) -> Bool {
        other == nil
            && user.isCapable
            && !user.inMatch
            && !user.focusMode
            && store.outgoing == nil
            && store.match == nil
            // 서버가 진행 중이라 말한 내 판(같은 계정 다른 기기 · 판을 아직 못 읽음) — 신청은 `busy` 로 돌아온다.
            && store.activeMatchID == nil
            && !store.isBusy
    }
}

/// 판돈 시트의 [도전하기] 가 **실제로 요청을 낼 수 있는가**(낼 수 있으면 그 판돈, 못 내면 nil). 신청이 나가는 **마지막 문**이라 "버튼이 비활성"이 아니라
/// **요청 0건**을 재야 한다(뷰는 맥 스위트가 못 본다). 게이트가 열린 뒤 상태가 바뀐 틈(시트가 떠 있는 동안 AI 연습을 시작했다 · 다른 기기에서 판이 섰다)을 막는다.
/// 판돈 표(3·5·10)는 서버 CHECK 가 쥔다(`ReversiStake`). 잔액을 **모르면 막지 않는다**(맥 0.3.29 규칙 — 서버가 거절하면 그때 안내한다).
package enum GamesReversiStakeSend {
    @MainActor
    package static func sendable(
        _ selected: ReversiStake?, store: ReversiStore, balance: Int?, blockedBy other: GamesBusyGame?
    ) -> ReversiStake? {
        guard let selected,
              affordable(selected, balance: balance),
              !store.isBusy,
              other == nil,
              store.match == nil,
              store.outgoing == nil,
              store.activeMatchID == nil
        else { return nil }
        return selected
    }

    package static func affordable(_ stake: ReversiStake, balance: Int?) -> Bool {
        guard let balance else { return true }
        return balance >= stake.rawValue
    }
}

#if os(iOS)

/// 아잉 뒤집기 화면 — 게임 탭 목적지(`GamesDestination.reversi`)의 **진입 뷰**.
///
/// 배선 갈래(1/4)는 수명 훅 둘과 '할 수 없음' 안내만 세운다. 로비·판·AI 연습·결과·관전·순위·규칙 그림은 화면 갈래가 이 `content` 를 바꿔 채운다
/// (넘김 메모 phone-1017/lane-notes/reversi.md '다음 갈래가 바꿀 자리'). 수명 훅 두 줄(`onAppear`·`onDisappear`)은 그대로 둔다 — 순서를 쥔 곳이 `GamesStore` 다.
struct GamesReversiScreen: View {
    let store: GamesStore

    private var reversi: ReversiStore { store.reversi }

    var body: some View {
        content
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(ReversiPhoneText.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { store.reversiScreenDidAppear() }
            .onDisappear { store.reversiScreenDidDisappear() }
    }

    @ViewBuilder
    private var content: some View {
        if let unavailable = GamesReversiUnavailable.title(reversi.availability) {
            // 할 수 없는 기기·서버 상태다 — 로비를 그리면 [도전]이 서고 그 요청은 전부 거절된다.
            EmptyStateView(systemImage: GamesReversiUnavailable.icon(reversi.availability), title: unavailable)
                .padding(.horizontal, MobileTheme.sideMargin)
        } else {
            EmptyStateView(systemImage: "circle.lefthalf.filled", title: ReversiPhoneText.title,
                           message: reversi.record.map { ReversiPhoneText.recordTitle + " " + ReversiPhoneText.record($0) }
                               ?? ReversiPhoneText.subtitle)
                .padding(.horizontal, MobileTheme.sideMargin)
        }
    }
}

#endif
