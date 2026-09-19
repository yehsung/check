import Foundation

// 차단·신고의 **순수 규칙과 문구 — 폰과 맥이 읽는 한 벌**(2026-09-20 맥 차단·신고).
//
// 처음에는 폰 모듈(`CheckMobileKit/Messages/MessagesBlockRules.swift`)에 있었다. 맥에도 1:1 메시지와 오목 채팅이 있고
// 서버는 차단을 양쪽에 똑같이 강제하므로(폰에서 차단하면 맥에서도 막힌다), 맥만 쓰는 사람도 같은 약속을 같은 말로 들어야 한다.
// 두 벌을 두면 한쪽이 언젠가 갈린다 — 특히 **사실**(사유 넷 · 24시간 · 200자 · 무엇이 막히는가)이 갈리면
// 심사원이 읽는 폰 화면과 맥 화면 중 어느 쪽이 참인지 묻게 된다. 그래서 사실은 여기 한 곳에만 있다.
//
// 플랫폼마다 **길 안내만** 다르다: 푸는 자리(폰 "나 → 설정 → 차단한 사람" · 맥 "설정 → 차단한 사람")와
// 그 플랫폼에만 있는 표면의 이름(폰 "사람 찾기" · 맥 "콕 찌르기 목록", 맥에만 있는 콕·울트라 찌르기). 그 줄들만
// `BlockReportPlatform` 으로 가른다 — 폰이 받는 글자는 옮기기 전과 **한 글자도** 다르지 않다(폰 테스트가 원문과 대조한다).
//
// Foundation 만 쓴다(SwiftUI 없음 — macOS `swift test` 로 검증).
// ★ 신고 자유 입력은 사람이 쓴 문장이다 — 이 파일에도 `print`/`Logger` 를 붙이지 마라(메시지 파일 공통 규약).
//
// 애플 심사 지침 1.2 가 요구하는 것은 ② 신고 창구와 시의적절한 대응, ③ 학대하는 사용자를 차단하는 기능이다.
// '시의적절한 대응'의 증거로 신고 시트와 지원 페이지에 **24시간 안에 확인한다**고 적는다(`reviewPromise`).

/// 문구가 갈리는 플랫폼. 사실이 아니라 **길 안내와 표면 이름**만 가른다(파일 머리 주석).
package enum BlockReportPlatform: Sendable, CaseIterable {
    case phone
    case mac
}

// MARK: - 문구

package enum BlockReportText {
    // 대화 화면 오른쪽 위 메뉴(···)
    package static let menuAccessibilityLabel = "더 보기"
    package static let blockAction = "차단하기"
    package static let reportAction = "신고하기"
    package static let reportMessageAction = "이 메시지 신고하기"

    // 차단 확인 시트 — **무엇이 막히는지 세 줄**(SPEC). 되돌릴 수 있는 일이라는 것도 같이 말한다.
    package static func blockConfirmTitle(_ name: String) -> String { "\(name) 님을 차단할까요?" }

    /// 막히는 것 ① — 두 플랫폼이 같은 사실을 같은 말로 한다.
    package static let blockedMessagesFact = "서로 메시지를 주고받을 수 없어요"

    /// 막히는 것 세 줄. 첫 줄(메시지)은 공통 사실이고, 나머지 둘은 그 플랫폼에 있는 표면의 이름으로 말한다:
    ///  · 폰 — 대화 목록 · 사람 찾기 · 오목 신청(폰에는 찌르기가 없다).
    ///  · 맥 — 콕·울트라 찌르기(맥에만 있다 — 서버 `poke_user`·`ultra_poke_user` 도 차단을 본다) · 콕 찌르기 목록(맥에서
    ///    사람을 고르는 자리다 — 폰의 '사람 찾기'와 같은 서버 목록 `app_user_directory`) · 오목 신청.
    package static func blockConfirmItems(_ platform: BlockReportPlatform) -> [String] {
        switch platform {
        case .phone:
            return [
                blockedMessagesFact,
                "이 대화가 목록에서 사라져요",
                "사람 찾기와 오목 신청에서 서로 보이지 않아요",
            ]
        case .mac:
            return [
                blockedMessagesFact,
                "콕 찌르기·울트라를 서로 보낼 수 없어요",
                "콕 찌르기 목록과 오목 신청에서 서로 보이지 않아요",
            ]
        }
    }

    /// 순위판·팀 현황은 그대로다 — 숨기지 않고 밝힌다(팀 통계라 빈칸이 생기면 다른 사실이 틀어진다).
    package static let blockConfirmScopeNote = "순위판·팀 현황의 이름은 그대로 남아요."

    /// 차단을 푸는 자리(길 안내). 폰은 [나] 탭 안의 설정, 맥은 메뉴바의 설정 창이다.
    package static func blockedListPath(_ platform: BlockReportPlatform) -> String {
        switch platform {
        case .phone: return "나 → 설정 → 차단한 사람"
        case .mac: return "설정 → 차단한 사람"
        }
    }

    package static func blockConfirmUndoNote(_ platform: BlockReportPlatform) -> String {
        "\(blockedListPath(platform))에서 언제든 풀 수 있어요."
    }

    package static let blockConfirm = "차단하기"
    package static let blockCancel = "취소"

    // 신고 시트
    package static let reportTitle = "신고하기"
    package static func reportLede(_ name: String) -> String { "\(name) 님을 신고해요. 운영자만 봅니다." }
    package static let reportMessageLede = "이 메시지를 신고해요. 운영자만 봅니다."
    package static let reportReasonHeader = "사유"
    package static let reportDetailHeader = "자세히 (선택)"
    package static let reportDetailPlaceholder = "무슨 일이 있었는지 적어 주세요"
    package static let reportAlsoBlock = "신고하면서 차단하기"
    package static let reportAlsoBlockDetail = "차단하면 서로 메시지를 주고받을 수 없어요"
    /// 애플이 요구하는 '시의적절한 대응'의 약속 — 지원 페이지(docs/index.md)와 같은 문장이다.
    package static let reviewPromise = "접수한 신고는 24시간 안에 확인합니다."
    package static let reportSubmit = "신고 보내기"
    package static let reportSending = "보내는 중…"
    package static let reportReasonRequired = "사유를 골라 주세요"
    package static func reportDetailOverflow(_ limit: Int) -> String { "자세한 내용은 \(limit)자까지예요" }

    // 차단 목록(폰: 나 → 설정 → 차단한 사람 · 맥: 설정 → 차단한 사람)
    package static let blockedListTitle = "차단한 사람"
    package static let blockedListMenuDetail = "메시지 · 오목 차단"

    /// 목록 맨 위 한 줄 — 무엇이 막혀 있는지 다시 말한다(차단을 건 지 한참 지나 여기 오는 사람을 위해).
    /// 확인 시트의 세 줄과 **같은 사실**을 같은 표면 이름으로 말한다(`blockConfirmItems`).
    package static func blockedListLede(_ platform: BlockReportPlatform) -> String {
        switch platform {
        case .phone:
            return "차단한 사람과는 메시지를 주고받을 수 없고, 사람 찾기와 오목 신청에서도 서로 보이지 않아요."
        case .mac:
            return "차단한 사람과는 메시지·콕 찌르기를 주고받을 수 없고, 콕 찌르기 목록과 오목 신청에서도 서로 보이지 않아요."
        }
    }

    /// "3일 전 차단". 상대 시각을 **어떻게 세는지**는 플랫폼 몫이라(폰 `MobileRelativeTime` · 맥 `FeedbackText.ageText`)
    /// 이미 센 글자를 받는다. 시각을 모르면 화면이 이 줄을 아예 그리지 않는다(지어내지 않는다).
    package static func blockedAtLine(relative: String) -> String { "\(relative) 차단" }

    package static let blockedEmptyTitle = "차단한 사람이 없어요"

    /// 빈 목록 안내 — 차단을 **거는** 자리를 가리킨다. 맥은 오목 창 채팅에도 같은 ··· 가 있어 함께 말한다.
    package static func blockedEmptyMessage(_ platform: BlockReportPlatform) -> String {
        switch platform {
        case .phone: return "대화 화면의 ··· 에서 차단할 수 있어요"
        case .mac: return "대화 화면이나 오목 채팅의 ··· 에서 차단할 수 있어요"
        }
    }

    package static let blockedListFailed = "차단 목록을 불러오지 못했어요"
    package static let unblockAction = "차단 해제"
    package static func unblockConfirmTitle(_ name: String) -> String { "\(name) 님의 차단을 풀까요?" }
    package static let unblockConfirmMessage = "다시 메시지를 주고받을 수 있게 돼요."
    package static let unblockConfirm = "차단 해제"

    // 결과 문구
    package static func blockedNotice(_ name: String) -> String { "\(name) 님을 차단했어요" }
    package static let reportSentNotice = "신고를 접수했어요 · 24시간 안에 확인할게요"

    /// 서버가 아직 이 기능을 모른다(앱이 db push 보다 먼저 나간 창). "고장"이 아니라 "아직"이라고 말하고,
    /// 기다리는 것 말고 할 수 있는 일(제보)도 준다 — 계정 삭제의 `serverNotReady` 와 같은 규약이다.
    package static let serverNotReady = "이 기능이 아직 서버에 준비되지 않았어요 — 잠시 뒤 다시 시도하거나 제보로 알려 주세요"

    /// 연결 실패 뒤에 붙는 한마디. 오목·폰 목록 문구와 **같은 문장**이다(`GomokuNoticeText.checkConnection` —
    /// 폰의 `MobileLoadText.checkConnection` 도 이 문장을 그대로 들고 있다).
    package static var checkConnection: String { GomokuNoticeText.checkConnection }
}

// MARK: - 실패 갈래

/// 차단·신고 왕복의 실패 갈래. `cancelled` 는 화면에 아무 말도 하지 않는다(세대가 바뀐 것뿐이다).
package enum BlockReportFailure: Equatable, Sendable {
    /// 서버에 함수가 없다(PGRST202 · 404).
    case serverNotReady
    case network
    /// 서버가 거절했다(자기 자신 차단 · 24시간 상한 · 권한).
    case rejected
    case cancelled
}

package enum BlockReportAction: Equatable, Sendable {
    case block
    case unblock
    case report
}

package enum BlockReportRules {
    /// "이 서버에는 그 함수가 없다"의 판정. PostgREST 는 404 + PGRST202 를 내고 공용 매핑이 `.databaseSchemaMissing` 으로 접는다.
    /// 본문이 그 문장이 아닌 404 도 같은 뜻으로 본다(프록시가 본문을 바꾸는 날). 메시지 이력의 판정(폰 `MessagesStore.isMissingFunction` ·
    /// 맥 `WorkTimerStore.isMissingMessageReadFunction`)과 **같은 표**다 — 401/403·5xx·네트워크는 여기 넣지 않는다.
    package static func isMissingFunction(_ error: SupabaseWorkServiceError) -> Bool {
        switch error {
        case .databaseSchemaMissing: return true
        case .invalidResponse(let status): return status == 404
        default: return false
        }
    }

    /// 오류 → 갈래. 판정 재료는 **오직 서비스 오류의 모양**이다.
    package static func classify(_ error: Error) -> BlockReportFailure {
        if case .cancelled = AuthErrorRules.classify(error) { return .cancelled }
        guard let serviceError = error as? SupabaseWorkServiceError else { return .network }
        if isMissingFunction(serviceError) { return .serverNotReady }
        switch serviceError {
        // 5xx · 레이트리밋은 "지금은 안 된다"다 — 사용자가 다시 눌러 볼 일이다.
        case .invalidResponse(let status): return status >= 500 ? .network : .rejected
        case .rateLimited: return .network
        default: return .rejected
        }
    }

    /// 갈래 → 화면 한 줄. `cancelled` 는 nil(아무 말도 하지 않는다).
    package static func notice(for failure: BlockReportFailure, action: BlockReportAction) -> String? {
        switch failure {
        case .cancelled:
            return nil
        case .serverNotReady:
            return BlockReportText.serverNotReady
        case .network:
            return "\(verb(action))지 못했어요 — " + BlockReportText.checkConnection
        case .rejected:
            return "\(verb(action))지 못했어요 — 잠시 뒤 다시 시도해 주세요"
        }
    }

    private static func verb(_ action: BlockReportAction) -> String {
        switch action {
        case .block: return "차단하"
        case .unblock: return "차단을 풀"
        case .report: return "신고를 보내"
        }
    }

    /// [신고 보내기] 를 누를 수 있는가 — 사유를 골랐고 · 자유 입력이 상한 안이고 · 도는 중이 아니다.
    /// 화면은 이 값으로 버튼을 잠그고, 스토어가 같은 조건을 **다시** 본다(비활성만 두면 왜 막혔는지 말할 기회가 없다).
    package static func canSubmitReport(reason: ContentReportReason?, detail: String, isSending: Bool) -> Bool {
        guard reason != nil, !isSending else { return false }
        return ContentReportDetail.isWithinLimit(detail)
    }

    /// 자유 입력 카운터("183/200"). 상한 가까이에서만 보인다 — 입력칸 카운터와 같은 규칙(폰 `MessagesComposerRules`).
    package static func detailCounterText(_ detail: String) -> String? {
        let length = ContentReportDetail.length(detail)
        guard length >= counterThreshold else { return nil }
        return "\(length)/\(ContentReportDetail.maxLength)"
    }

    /// 카운터가 서기 시작하는 길이(상한의 90%).
    package static let counterThreshold = 180

    package static func isDetailOverflowing(_ detail: String) -> Bool {
        !ContentReportDetail.isWithinLimit(detail)
    }
}
