import CheckCore
import Foundation

// MARK: - 확성기 배너 — 맥 배선 (2026-10-30 · 계약 docs/plan/megaphone-banner-contract.md C2 · C3)
//
// 판정(필터 술어 · 판정 보류 · 요약 함수 고르기 · 큐 · 8초)은 전부 코어 `MegaphoneBannerStore` 에 있다(폰과 한 벌).
// 이 파일이 맥에서 더하는 것:
//
// ① **한 술어, 모든 자리.** 대화 목록·열린 대화·안 읽음 사람(목록 점·레일 점·메뉴바 점)은 `visibleMessageHistory` 하나를 읽고,
//    말풍선 큐·팝오버 도착 줄·도착 새로고침은 `receiveConsumedMessages` 앞의 `partitionMegaphoneRows` 하나를 지난다.
//    둘 다 `megaphoneBanner.hides(messageID:)` 를 부른다 — 차단 숨김(`blockHiddenPeerIDs`)을 빼는 자리와 같은 자리다.
//    이력 판(`messageHistory`) 자체는 서버가 답한 그대로 둔다: 배너 목록이 늦게 와도 읽는 자리가 다시 거른다(관찰 값이라 화면이 따라온다).
// ② **판정 보류.** 📢 로 시작하는데 배너 목록이 아직 모르는 줄은 붙든 채 배너 목록을 한 번 받는다(`refresh(verifying:)`).
//    받은 뒤에도 모르면(위조 DM · 연결 실패) 메시지로 돌아온다 — 접두는 "확인해 볼 이유"일 뿐 표식이 아니다.
// ③ **신호와 예비 경로.** 실시간 'megaphone' 신호는 스로틀 없이(`requestMegaphoneBannerRefresh`), 팝오버 열기·폴링 틱은 60초 스로틀로
//    (`refreshMegaphoneBannerIfStale`). 필터가 막 켜지면 들고 있는 요약(옛 함수 — 확성기 줄도 셌다)을 v2 로 한 번 다시 받는다.
// ④ 서버가 배너 함수를 모르면(`.unavailable`) 이 파일의 모든 자리가 그대로 통과시킨다 — 지금처럼 메시지로 보인다.

@MainActor
extension WorkTimerStore {
    /// 예비 새로고침(팝오버 열기 · 폴링 틱) 스로틀. 실시간 신호가 정본이고 이쪽은 소켓이 끊긴 맥의 그물이다.
    nonisolated static let megaphoneBannerRefreshThrottleSeconds: TimeInterval = 60

    // MARK: 필터(① · ②)

    /// 이 줄을 메시지함에서 뺄(또는 판정까지 붙들) 것인가. 내가 보낸 줄은 확성기가 아니다(서버 fan-out 에 본인이 없다).
    func isMegaphoneRowWithheld(_ entry: MessageHistoryEntry) -> Bool {
        guard !entry.isMine else { return false }
        let banner = megaphoneBanner
        return banner.hides(messageID: entry.id) || banner.needsVerification(messageID: entry.id, body: entry.body)
    }

    /// 화면이 읽는 이력 — 확성기 줄을 뺀 판. 대화 목록(`messageThreads`) · 열린 대화 · 안 읽음(`unreadMessagePeerIDs`)이 이것 하나를 읽는다.
    var visibleMessageHistory: [MessageHistoryEntry] {
        guard megaphoneBanner.capability != .unavailable else { return messageHistory }
        return messageHistory.filter { !isMegaphoneRowWithheld($0) }
    }

    /// 지금 이력에서 판정 보류 중인 줄의 id(배너 목록을 받을 때 같이 확인한다).
    var megaphoneVerificationCandidates: Set<String> {
        let banner = megaphoneBanner
        guard banner.capability != .unavailable else { return [] }
        var ids: Set<String> = []
        for entry in messageHistory where !entry.isMine && banner.needsVerification(messageID: entry.id, body: entry.body) {
            ids.insert(entry.id)
        }
        return ids
    }

    /// 이력에 판정 보류 줄이 있으면 배너 목록을 한 번 받는다(없으면 아무 요청도 안 낸다).
    func verifyMegaphoneCandidatesIfNeeded() {
        let ids = megaphoneVerificationCandidates
        guard !ids.isEmpty else { return }
        requestMegaphoneBannerRefresh(verifying: ids)
    }

    /// take_pokes 가 소비한 행을 가른다 — `ready` 는 곧바로 들이고, 배너 목록이 아는 확성기 줄은 버리고, `held` 는 판정까지 붙든다.
    /// 메시지가 아닌 행(찌르기)은 언제나 `ready` 다.
    func partitionMegaphoneRows(_ rows: [TakenPokeRow]) -> (ready: [TakenPokeRow], held: [TakenPokeRow]) {
        let banner = megaphoneBanner
        guard banner.capability != .unavailable else { return (rows, []) }
        var ready: [TakenPokeRow] = []
        var held: [TakenPokeRow] = []
        for row in rows {
            guard PokeKind(rawServerValue: row.kind) == .message else {
                ready.append(row)
                continue
            }
            if banner.hides(messageID: row.id) { continue }
            if banner.needsVerification(messageID: row.id, body: MessageBody.sanitized(row.body ?? "")) {
                held.append(row)
                continue
            }
            ready.append(row)
        }
        return (ready, held)
    }

    // MARK: 새로고침(③)

    /// 배너 목록을 받는다(스로틀 없음 — 실시간 신호 · 판정 보류). 겹친 호출은 배너 스토어가 하나로 모은다.
    /// 이력의 판정 보류 줄은 언제나 같이 확인한다. 반환 Task 는 기다려야 하는 호출부(도착 판정)와 시험용이다.
    @discardableResult
    func requestMegaphoneBannerRefresh(verifying extra: Set<String> = []) -> Task<Void, Never>? {
        guard session != nil else { return nil }
        megaphoneBannerLastRefreshAt = clock()
        let ids = extra.union(megaphoneVerificationCandidates)
        let generation = sessionGeneration
        let before = megaphoneBanner.capability
        return Task { @MainActor [weak self] in
            guard let self else { return }
            await self.megaphoneBanner.refresh(verifying: ids)
            guard generation == self.sessionGeneration else { return }
            // 필터가 막 켜졌다 — 들고 있는 요약은 옛 함수로 받은 것이라 확성기 줄도 셌다. v2 로 한 번 다시 받는다(점이 그 줄로 켜져 있지 않게).
            if before != .available, self.megaphoneBanner.capability == .available {
                self.megaphoneFilterDidTurnOn()
            }
        }
    }

    /// 예비 경로(팝오버 열기 · 폴링 틱) — 마지막 새로고침에서 60초가 지났을 때만.
    func refreshMegaphoneBannerIfStale() {
        guard session != nil else { return }
        guard clock().timeIntervalSince(megaphoneBannerLastRefreshAt) >= Self.megaphoneBannerRefreshThrottleSeconds else { return }
        requestMegaphoneBannerRefresh()
    }

    // MARK: 본인 배너 · 로그아웃

    /// 보낸 직후 자기 배너를 한 번(전송 응답의 본문으로 — "이렇게 떴어요"). 이름은 지금 화면의 내 이름이다.
    func presentOwnMegaphoneBanner(body: String, megaphoneID: String?) {
        megaphoneBanner.presentOwn(body: body, senderName: displayName, megaphoneID: megaphoneID)
    }

    /// 로그아웃 · 계정 전환. 큐 · 필터 id · 판정 기록 · 스로틀을 비운다(본 것 기록은 계정 키에 남는다 — 코어 머리말 ⑤).
    /// [답장] 이 남긴 상대 이름 힌트도 계정에 묶인다(앞 사람의 대화 제목이 새 계정에 남지 않게).
    func resetMegaphoneBanner() {
        megaphoneBanner.reset()
        megaphoneBannerLastRefreshAt = .distantPast
        messagePeerHint = nil
    }

    // MARK: 미룸(배너 창 — CheckMegaphoneBannerWindow.swift)

    /// 미니게임 판이 돌고 있는가 — 창이 열려 있고 진행 중인 판의 장부가 아직 안 닫혔다(멈춰 둔 판도 진행 중이다).
    var isMiniGameRoundLive: Bool {
        guard isMiniGamePanelVisible, let round = miniGameLiveRound else { return false }
        return !round.settled
    }

    /// 지금 배너를 미뤄야 하는가(실시간 대결 · 미니게임 판). 배너 스토어의 `isBannerDeferred` 가 이것을 읽는다.
    var isMegaphoneBannerDeferred: Bool {
        MegaphoneBannerDeferral.isDeferred(gomoku: gomoku.phase, chess: chess.phase, tetris: tetris.phase,
                                           miniGameRoundLive: isMiniGameRoundLive, rummyLive: rummy.defersMegaphoneBanner)
    }

    /// 미룸이 바뀌었으면 배너 스토어에 알린다(바뀐 때만 — 미루기 시작이면 떠 있던 배너를 줄로 되돌리고, 풀렸으면 신선한 것만 띄운다).
    /// 부르는 곳: 배너 창 컨트롤러의 관찰(대결 단계 · 미니게임 창) · 진행 중인 판의 장부(`miniGameLiveRound` didSet — 관찰 밖이다).
    func megaphoneBannerDeferralMayHaveChanged() {
        let deferred = isMegaphoneBannerDeferred
        guard deferred != megaphoneBannerLastDeferred else { return }
        megaphoneBannerLastDeferred = deferred
        megaphoneBanner.deferralChanged()
    }

    // MARK: [답장]

    /// 배너의 [답장] — 보낸 사람과의 1:1 대화를 연다(진입 맥락 `.overlay` — [뒤로]는 홈). 확성기 줄은 메시지함에서 빠지므로
    /// 그 사람과 주고받은 것이 없으면 대화 제목이 빈다 — 배너의 이름·아바타를 힌트로 함께 넘긴다(`selectedMessagePeerName` 의 마지막 출처).
    /// 답장할 수 없는 배너(내 확성기 · 보낸 사람 모름)면 아무것도 안 하고 거짓.
    @discardableResult
    func openMegaphoneReply(_ banner: MegaphoneBanner) -> Bool {
        guard banner.canReply, let peer = banner.senderID else { return false }
        messagePeerHint = MessagePeerHint(userID: peer, name: banner.senderName, avatarURL: banner.senderAvatarURL)
        openMessagePanel(peer: peer, from: .overlay)
        return true
    }
}

/// [답장] 으로 연 대화의 상대 이름·아바타(이력 · 콕찌르기 목록 · 받은 줄 어디에도 그 사람이 없을 때만 쓴다).
struct MessagePeerHint: Equatable {
    let userID: String
    let name: String
    let avatarURL: URL?
}

/// 배너 미룸 판정(순수 함수). 오목 · 체스는 `playing`, 테트리스는 `countdown` · `playing`, 미니게임은 판 진행 중, 아잉 큐브는 손댄 판에서 내 자리 playing.
enum MegaphoneBannerDeferral {
    static func isDeferred(gomoku: GomokuPhase, chess: ChessPhase, tetris: TetrisDuelPhase, miniGameRoundLive: Bool,
                           rummyLive: Bool = false) -> Bool {
        if gomoku == .playing { return true }
        if chess == .playing { return true }
        if tetris == .countdown || tetris == .playing { return true }
        if miniGameRoundLive { return true }
        // 아잉 큐브(v0.3.69): 이 기기가 손댄 판이 진행 중이고 내 자리가 playing(`RummyStore.defersMegaphoneBanner`).
        // 관찰 추적이 `rummy.phase`·`match` 를 읽으므로 판이 시작·끝·기권될 때 배너 창 컨트롤러가 다시 판단한다.
        if rummyLive { return true }
        return false
    }
}
