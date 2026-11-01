// 원본: Sources/check/CheckSettingsView.swift:731(AvatarRemovalText) · :765(AvatarRemovalNoticeTone) · :1147(CenterSettingsRowState)
//
// 프로필 사진 되돌리기 · 소속 센터 행의 문구와 상태(순수 값 — 시험이 글자 그대로 되묻는다). iOS 에는 둘 다 짝이 없어 맥 글자를 옮겼다.
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.wire.CenterLabel

/** 사진 되돌리기 문구 한 벌. */
object AvatarRemovalText {
    const val title = "프로필 사진"
    const val detail = "지우면 내 자리에 착용한 캐릭터가 대신 보여요."
    const val confirmDetail = "지운 사진은 되돌릴 수 없어요. 다시 쓰려면 새로 올려야 해요."
    const val action = "기본 캐릭터로 되돌리기"
    const val confirm = "되돌리기"
    const val cancel = "취소"
    const val inFlight = "지우는 중…"
    const val successMessage = "기본 캐릭터로 되돌렸어요"

    /** 표는 비웠는데 **파일이 남은** 경우. "되돌렸어요"라고 말하면 거짓말이다. */
    const val fileLeftMessage = "사진 파일이 아직 남아 있어요. 잠시 후 다시 시도해 주세요"
    const val failureMessage = "사진을 지우지 못했어요"
    const val signedOutMessage = "로그인하면 사진을 지울 수 있어요"

    /** 한 줄 우선순위: 스토어가 세운 결과 > 로그인 전 안내 > 확인 안내 > 기본 설명(맥 `AvatarRemovalSettingsRow.notice`). */
    fun notice(result: String?, signedIn: Boolean, confirming: Boolean): String = when {
        result != null -> result
        !signedIn -> signedOutMessage
        confirming -> confirmDetail
        else -> detail
    }
}

/** 결과 한 줄의 색 갈래. Bool 이 아닌 이유: 파일이 남은 경우는 실패가 아니지만 성공이라고 말하면 안 된다. */
enum class AvatarRemovalNoticeTone { success, warning, failure }

/**
 * 소속 센터 행(읽기 전용 — 바꾸는 길이 없다, 서버 권한이 막는다). 셋이 **다른 문장**이어야 이 행이 말을 한다.
 * 맥과 다른 글자 하나: 맥은 배지가 아바타 모서리에 서서 "아바타 모서리에 배지로 보여요" 인데, 폰은 이름 뒤에 선다(PersonName · CenterBadge) — 사실대로 "이름 옆에"로 적는다.
 */
sealed interface CenterSettingsRowState {
    data object Loading : CenterSettingsRowState
    data object Unset : CenterSettingsRowState
    data class Chosen(val name: String) : CenterSettingsRowState

    val value: String
        get() = when (this) {
            Loading -> "…"
            Unset -> "미지정"
            is Chosen -> name
        }

    val caption: String
        get() = when (this) {
            Loading -> "불러오는 중…"
            Unset -> "가입할 때 안 골랐어요. 운영자에게 말해 주세요."
            is Chosen -> "이름 옆에 배지로 보여요. 바꾸려면 운영자에게."
        }

    companion object {
        const val title = "소속 센터"

        /** 모르는 서버값은 [CenterLabel] 이 걸러 미지정으로 접는다. */
        fun of(loaded: Boolean, center: String?): CenterSettingsRowState {
            if (!loaded) return Loading
            return CenterLabel.display(center)?.let { Chosen(it) } ?: Unset
        }
    }
}
