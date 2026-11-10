import CheckCore
import Foundation

// MARK: - 지난 확성기(📢) — 맥 배선 (2026-11-11 · 최근 30일 모아 보기)
//
// 판정(문 세 갈래 · 커서 · 중복 · 세대 가드 · 내리기)은 전부 코어 `MegaphoneFeedStore` 에 있다(폰과 한 벌 — Sources/CheckCore/MegaphoneFeed.swift 머리말).
// 맥이 더하는 것은 **문 하나와 자리 하나**뿐이다:
//   · 문: 확성기 작성기의 설명 줄 끝 '지난 확성기 ›'(`MegaphoneComposer`). 레일 칸 · 배너 단추는 더하지 않는다
//     (레일 8칸 높이 계약 · 배너는 [닫기]·[더 보기] 둘뿐이라는 대표 결정).
//   · 자리: 상점 패널 자리(`CheckMenuView` 의 상점 갈래가 이 페이지를 대신 그린다). 하위 패널 깃발이 아니다 — 상점 안의 보기라
//     토큰 행 게이트(`isSubPanelOpen`)는 상점 깃발이 이미 센다. [뒤로]는 작성기가 열린 상점으로 돌아간다.
//
// 부르는 자리(코어 머리말 ③): 페이지 열기 · [이전 확성기 더 보기] · [다시 시도] · 페이지가 떠 있는 동안의 실시간 신호 · 운영자 [내리기].
// 팝오버 열기 · 폴링 틱 · 작성기 열기에서는 부르지 않는다(작성기 열기는 닫힌 문을 **요청 없이** 다시 모름으로 돌릴 뿐이다).

@MainActor
extension WorkTimerStore {
    /// 지난 확성기 페이지가 지금 상점 자리에 서 있는가 — 디스패치(`CheckMenuView`)와 실시간 새로고침이 **이 술어 하나**를 읽는다.
    /// 작성기가 접히면(상품 고르기 · 뽑기 · 오목알 스킨 — 셋 다 작성기를 접는다) 페이지도 저절로 내려간다.
    var isMegaphoneFeedShowing: Bool {
        isShopPanelVisible && megaphone.isComposerOpen && megaphoneFeed.isOpen
    }

    /// 작성기 설명 줄 끝에 '지난 확성기 ›' 문을 세우는가. 서버에 함수가 없다고 들었을 때(닫힘)만 숨는다(문 짝의 화면 쪽).
    /// 모름이면 선다 — 누르면 그때 묻는다(작성기를 열 때마다 미리 묻지 않는다).
    var showsMegaphoneFeedEntry: Bool {
        megaphoneFeed.isAvailable != false
    }

    /// 운영자 [내리기]를 세우는가. 표시 전용 깃발이다 — 판정은 서버 `is_app_admin()`(신고 관리 칸과 같은 문).
    var canHideMegaphonePosts: Bool { ultraUnlimited }

    /// 페이지가 그리는 목록 — 차단으로 걷어낸 사람의 글은 **곧바로** 뺀다(서버 응답을 기다리지 않는다 · 콕 찌르기 목록과 같은 규약).
    /// 목록 원본(`megaphoneFeed.items`)은 서버가 답한 그대로 둔다 — 차단이 실패하면 숨김만 풀려 그대로 돌아온다.
    var visibleMegaphoneFeed: [MegaphoneFeedItem] {
        let items = megaphoneFeed.items
        guard !blockHiddenPeerIDs.isEmpty else { return items }
        return items.filter { item in
            guard let sender = item.senderID else { return true }
            return !blockHiddenPeerIDs.contains(sender)
        }
    }

    /// 페이지의 결과 한 줄 — 신고·차단 결과가 먼저, 없으면 운영자 [내리기] 결과.
    var megaphoneFeedNotice: MegaphoneFeedNotice? {
        if let notice = blockReportNotice(on: .megaphoneFeed) {
            return MegaphoneFeedNotice(text: notice.text, isError: notice.isError)
        }
        return megaphoneFeed.notice
    }

    /// '지난 확성기 ›'. 작성기가 열린 상점에서만 연다(문이 그 자리에만 있다).
    func openMegaphoneFeed() {
        guard isShopPanelVisible, megaphone.isComposerOpen, showsMegaphoneFeedEntry else { return }
        clearBlockReportNotice(on: .megaphoneFeed)
        megaphoneFeed.open()
    }

    /// [뒤로] · 상점 닫기 · 작성기 접기. 그 자리의 신고 시트·결과 한 줄도 걷는다(다음에 연 페이지를 덮지 않게).
    func closeMegaphoneFeed() {
        dismissBlockReportSheet(on: .megaphoneFeed)
        clearBlockReportNotice(on: .megaphoneFeed)
        megaphoneFeed.close()
    }

    /// 작성기를 여는 순간(다음 자연스러운 진입) — 닫혔던 문을 모름으로 되돌린다. **요청은 없다**(코어 `rearm`).
    func rearmMegaphoneFeedEntry() {
        megaphoneFeed.rearm()
    }

    /// 실시간 'megaphone' 신호. 페이지가 떠 있을 때만 첫 쪽을 다시 읽는다(배너 새로고침과 따로 — 배너 스토어에는 넣지 않는다).
    func refreshMegaphoneFeedIfShowing() {
        guard isMegaphoneFeedShowing else { return }
        megaphoneFeed.refresh()
    }

    /// 운영자 [내리기]. 운영자 깃발이 없으면 0건(서버도 `forbidden` 으로 막는다 — 두 겹).
    @discardableResult
    func hideMegaphonePost(_ item: MegaphoneFeedItem) -> Task<Void, Never>? {
        guard canHideMegaphonePosts, isMegaphoneFeedShowing else { return nil }
        clearBlockReportNotice(on: .megaphoneFeed)
        return megaphoneFeed.adminHide(megaphoneID: item.megaphoneID)
    }
}

/// 지난 확성기 줄의 ··· 항목.
enum MegaphoneFeedRowAction: CaseIterable, Equatable, Sendable {
    /// 보낸 사람 신고(시트를 연다).
    case report
    /// 보낸 사람 차단(확인 시트를 연다).
    case block
    /// 운영자 [내리기](모두의 지난 확성기에서 뺀다).
    case adminHide

    var title: String {
        switch self {
        case .report: return BlockReportText.reportAction
        case .block: return BlockReportText.blockAction
        case .adminHide: return MegaphoneFeedText.adminHideAction
        }
    }

    var systemImage: String {
        switch self {
        case .report: return "exclamationmark.bubble"
        case .block: return "nosign"
        case .adminHide: return "eye.slash"
        }
    }
}

/// 지난 확성기 줄의 ··· 규칙(순수 — 결정적 검증 지점).
/// [신고하기]·[차단하기]는 **남의 글에만** 선다. 줄에는 메시지 id 가 없어서(계약 §2) 신고는 **보낸 사람 신고**다 —
/// `report_content(p_message_id: null)`. 본문을 따로 실을 칸이 서버에 없으니 시트에도 본문을 싣지 않는다(운영자가 못 보는 것을
/// 보낸 것처럼 보이지 않게). 운영자는 [내리기]로 글 자체를 내린다.
enum MegaphoneFeedSafetyRule {
    static func actions(for item: MegaphoneFeedItem, me: String?, isAdmin: Bool) -> [MegaphoneFeedRowAction] {
        var actions: [MegaphoneFeedRowAction] = []
        if !isOwnPost(item, me: me), let sender = item.senderID, !sender.isEmpty {
            actions += [.report, .block]
        }
        if isAdmin { actions.append(.adminHide) }
        return actions
    }

    /// 그 글을 보낸 사람을 신고할 대상(내 글이거나 보낸 사람을 모르면 nil). 메시지 id 는 없다(사람 신고).
    static func reportTarget(for item: MegaphoneFeedItem, me: String?) -> BlockReportTarget? {
        guard !isOwnPost(item, me: me), let sender = item.senderID, !sender.isEmpty else { return nil }
        return BlockReportTarget(peerID: sender, peerName: item.senderName)
    }

    /// 그 사람을 차단할 대상(내 글이면 nil).
    static func blockTarget(for item: MegaphoneFeedItem, me: String?) -> BlockReportTarget? {
        guard !isOwnPost(item, me: me), let sender = item.senderID, !sender.isEmpty else { return nil }
        return BlockReportTarget(peerID: sender, peerName: item.senderName)
    }

    /// 서버가 `is_mine` 을 잘못 말해도 내 id 면 내 글이다(나를 신고·차단하는 문은 없다).
    private static func isOwnPost(_ item: MegaphoneFeedItem, me: String?) -> Bool {
        if item.isOwn { return true }
        guard let me, let sender = item.senderID else { return false }
        return sender.lowercased() == me.lowercased()
    }
}
