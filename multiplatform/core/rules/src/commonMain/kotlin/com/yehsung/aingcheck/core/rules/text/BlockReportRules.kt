// 원본: Sources/CheckCore/BlockReportRules.swift @ 1b8260d · ContentReportDetail(Sources/CheckCore/SupabaseWorkServiceBlocks.swift:236-254)
package com.yehsung.aingcheck.core.rules.text

/*
 * 차단·신고의 순수 규칙과 문구 — 폰·맥·Android·Windows 가 읽는 한 벌. 사실(사유 넷 · 24시간 · 200자 · 무엇이 막히는가)은 이 한 곳에만 둔다.
 * 플랫폼마다 길 안내만 다르다([BlockReportPlatform]). Android·Windows 는 폰 문구를 쓴다(맥에만 있는 콕·울트라 찌르기 표면이 없다).
 *
 * INV-BlockReportRules-6d651a0c 이식: 신고 자유 입력은 사람이 쓴 문장이다 — 이 파일에 `println`/로거를 붙이지 마라(메시지 파일 공통 규약).
 * 오류 문자열에도 본문을 싣지 않는다(이 파일의 함수는 본문을 받아도 길이만 잰다).
 */

enum class BlockReportPlatform { phone, mac }

object BlockReportText {
    const val menuAccessibilityLabel = "더 보기"
    const val blockAction = "차단하기"
    const val reportAction = "신고하기"
    const val reportMessageAction = "이 메시지 신고하기"

    fun blockConfirmTitle(name: String): String = "$name 님을 차단할까요?"
    const val blockedMessagesFact = "서로 메시지를 주고받을 수 없어요"
    fun blockConfirmItems(platform: BlockReportPlatform): List<String> = when (platform) {
        BlockReportPlatform.phone -> listOf(blockedMessagesFact, "이 대화가 목록에서 사라져요", "사람 찾기와 오목 신청에서 서로 보이지 않아요")
        BlockReportPlatform.mac -> listOf(blockedMessagesFact, "콕 찌르기·울트라를 서로 보낼 수 없어요", "콕 찌르기 목록과 오목 신청에서 서로 보이지 않아요")
    }
    const val blockConfirmScopeNote = "순위판·팀 현황의 이름은 그대로 남아요."
    fun blockedListPath(platform: BlockReportPlatform): String = when (platform) {
        BlockReportPlatform.phone -> "나 → 설정 → 차단한 사람"
        BlockReportPlatform.mac -> "설정 → 차단한 사람"
    }
    fun blockConfirmUndoNote(platform: BlockReportPlatform): String = "${blockedListPath(platform)}에서 언제든 풀 수 있어요."
    const val blockConfirm = "차단하기"
    const val blockCancel = "취소"

    const val reportTitle = "신고하기"
    fun reportLede(name: String): String = "$name 님을 신고해요. 운영자만 봅니다."
    const val reportMessageLede = "이 메시지를 신고해요. 운영자만 봅니다."
    const val reportReasonHeader = "사유"
    const val reportDetailHeader = "자세히 (선택)"
    const val reportDetailPlaceholder = "무슨 일이 있었는지 적어 주세요"
    const val reportAlsoBlock = "신고하면서 차단하기"
    const val reportAlsoBlockDetail = "차단하면 서로 메시지를 주고받을 수 없어요"
    const val reviewPromise = "접수한 신고는 24시간 안에 확인합니다."
    const val reportSubmit = "신고 보내기"
    const val reportSending = "보내는 중…"
    const val reportReasonRequired = "사유를 골라 주세요"
    fun reportDetailOverflow(limit: Int): String = "자세한 내용은 ${limit}자까지예요"

    const val blockedListTitle = "차단한 사람"
    const val blockedListMenuDetail = "메시지 · 오목 차단"
    fun blockedListLede(platform: BlockReportPlatform): String = when (platform) {
        BlockReportPlatform.phone -> "차단한 사람과는 메시지를 주고받을 수 없고, 사람 찾기와 오목 신청에서도 서로 보이지 않아요."
        BlockReportPlatform.mac -> "차단한 사람과는 메시지·콕 찌르기를 주고받을 수 없고, 콕 찌르기 목록과 오목 신청에서도 서로 보이지 않아요."
    }
    fun blockedAtLine(relative: String): String = "$relative 차단"
    const val blockedEmptyTitle = "차단한 사람이 없어요"
    fun blockedEmptyMessage(platform: BlockReportPlatform): String = when (platform) {
        BlockReportPlatform.phone -> "대화 화면의 ··· 에서 차단할 수 있어요"
        BlockReportPlatform.mac -> "대화 화면이나 오목 채팅의 ··· 에서 차단할 수 있어요"
    }
    const val blockedListFailed = "차단 목록을 불러오지 못했어요"
    const val unblockAction = "차단 해제"
    fun unblockConfirmTitle(name: String): String = "$name 님의 차단을 풀까요?"
    const val unblockConfirmMessage = "다시 메시지를 주고받을 수 있게 돼요."
    const val unblockConfirm = "차단 해제"

    fun blockedNotice(name: String): String = "$name 님을 차단했어요"
    const val reportSentNotice = "신고를 접수했어요 · 24시간 안에 확인할게요"
    const val serverNotReady = "이 기능이 아직 서버에 준비되지 않았어요 — 잠시 뒤 다시 시도하거나 제보로 알려 주세요"
    /** Swift `GomokuNoticeText.checkConnection`(오목 문구 묶음 — 같은 글자를 여기서 고정한다, 골든이 원문과 대조). */
    const val checkConnection = "연결을 확인하고 다시 시도해 주세요"
}

enum class BlockReportFailure { serverNotReady, network, rejected, cancelled }

enum class BlockReportAction { block, unblock, report }

/**
 * 서비스 오류를 규칙이 읽는 모양. 전선 오류 타입(W1-d `SupabaseWorkServiceError`)과 인증 분류(`AuthErrorRules.classify`)는 core/net 에 있고
 * rules 는 net 을 부를 수 없으므로(의존 rules → wire), 호출부(스토어)가 그 오류를 이 사실로 바꿔 넘긴다.
 */
sealed interface ServiceErrorFacts {
    /** 인증 분류가 "취소"다(창 닫기 · 세대 교체 · 작업 취소). */
    data object cancelled : ServiceErrorFacts
    /** 전선 오류가 아니다(URLError · 디코드 실패 밖의 것 등) — 연결 문제로 본다. */
    data object notServiceError : ServiceErrorFacts
    /** PostgREST PGRST202 · 42883(함수 없음) · 스키마 없음. */
    data object databaseSchemaMissing : ServiceErrorFacts
    data class invalidResponse(val status: Int) : ServiceErrorFacts
    data object rateLimited : ServiceErrorFacts
    /** 그 밖의 전선 오류(거절 · 디코드 실패 · 인증 만료 등). */
    data object otherServiceError : ServiceErrorFacts
}

object BlockReportRules {
    /** 함수가 서버에 없다(배포 전 서버) — 스키마 없음 또는 HTTP 404. 뽑기 · 선물 · 확성기도 이 판정을 쓴다. */
    fun isMissingFunction(error: ServiceErrorFacts): Boolean = when (error) {
        ServiceErrorFacts.databaseSchemaMissing -> true
        is ServiceErrorFacts.invalidResponse -> error.status == 404
        else -> false
    }

    fun classify(error: ServiceErrorFacts): BlockReportFailure = when {
        error == ServiceErrorFacts.cancelled -> BlockReportFailure.cancelled
        error == ServiceErrorFacts.notServiceError -> BlockReportFailure.network
        isMissingFunction(error) -> BlockReportFailure.serverNotReady
        // 5xx · 레이트리밋은 "지금은 안 된다"다 — 사용자가 다시 눌러 볼 일이다.
        error is ServiceErrorFacts.invalidResponse -> if (error.status >= 500) BlockReportFailure.network else BlockReportFailure.rejected
        error == ServiceErrorFacts.rateLimited -> BlockReportFailure.network
        else -> BlockReportFailure.rejected
    }

    fun notice(failure: BlockReportFailure, action: BlockReportAction): String? = when (failure) {
        BlockReportFailure.cancelled -> null
        BlockReportFailure.serverNotReady -> BlockReportText.serverNotReady
        BlockReportFailure.network -> "${verb(action)}지 못했어요 — " + BlockReportText.checkConnection
        BlockReportFailure.rejected -> "${verb(action)}지 못했어요 — 잠시 뒤 다시 시도해 주세요"
    }

    private fun verb(action: BlockReportAction): String = when (action) {
        BlockReportAction.block -> "차단하"
        BlockReportAction.unblock -> "차단을 풀"
        BlockReportAction.report -> "신고를 보내"
    }

    /** 사유를 골랐고 · 보내는 중이 아니고 · 자유 입력이 상한 안. (사유 열거 `ContentReportReason` 은 전선 값이라 W1-d — 여기는 골랐는가만.) */
    fun canSubmitReport(hasReason: Boolean, detail: String, isSending: Boolean): Boolean {
        if (!hasReason || isSending) return false
        return ContentReportDetail.isWithinLimit(detail)
    }

    fun detailCounterText(detail: String): String? {
        val length = ContentReportDetail.length(detail)
        if (length < counterThreshold) return null
        return "$length/${ContentReportDetail.maxLength}"
    }

    const val counterThreshold = 180

    fun isDetailOverflowing(detail: String): Boolean = !ContentReportDetail.isWithinLimit(detail)
}

/**
 * 신고 자유 입력(200자)의 정규화 · 길이 판정 — **[MessageBody] 의 정규화 · 눈금을 그대로 빌린다**(상한만 따로). 서버 CHECK 도 char_length 다.
 * Swift 는 서비스 파일(SupabaseWorkServiceBlocks)에 두었지만 글자 규칙이라 여기 둔다(전선 갈래가 쓰려면 조정자 이전 — 완료 보고).
 */
object ContentReportDetail {
    const val maxLength = 200
    fun sanitized(raw: String): String = MessageBody.sanitized(raw)
    fun length(raw: String): Int = MessageBody.length(raw)
    /** 자유 입력은 **선택**이다 — 비어 있어도 신고는 나간다. 넘치면 보내지 않는다. */
    fun isWithinLimit(raw: String): Boolean = length(raw) <= maxLength
    /** 실제로 보낼 값(보이는 글자가 없으면 null — 전선에는 null 이 실린다). */
    fun payload(raw: String): String? {
        val normalized = sanitized(raw)
        return if (MessageBody.hasVisibleContent(normalized)) normalized else null
    }
}
