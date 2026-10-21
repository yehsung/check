// 원본: 없음 — Swift 원본 없음(iOS·맥은 시스템 SF). 글꼴 파일은 Pretendard 1.3.9 공식 배포본(아래 출처).
//
// 번들 글꼴 Pretendard 1.3.9(SIL OFL 1.1, Reserved Font Name "Pretendard") — D§13-2·A§4-5: OS 마다 기본 한글 글꼴이 달라
// (맥 Apple SD 산돌고딕 Neo · Windows 맑은 고딕 · Android Noto/삼성) 두 플랫폼 화면과 스냅숏을 한 글꼴로 고정한다.
//
// 출처: 공식 배포본 github.com/orioncactus/pretendard releases v1.3.9 `Pretendard-1.3.9.zip`
//   (zip sha256 04be351a74d6bf7d60c480a3087e51d185485d35a52023142af1df19eb8c428a), public/static/Pretendard-<굵기>.otf 를
//   **바꾸지 않고** 이름만 소문자로 옮겼다. npm `pretendard@1.3.9`(integrity sha512-PaQAADyL…IaywSw==) 의 같은 파일과 바이트가 같다.
//   부분 집합을 만들면 OFL 의 예약 이름 때문에 "Pretendard" 이름을 쓸 수 없다 — 지금은 원본 그대로(크기 줄이기는 E18 뒤 판단).
// 라이선스 원문은 composeResources/files/licenses/Pretendard-OFL-1.1.txt 로 앱과 함께 나간다.
//
// 굵기 다섯: iOS·맥 화면이 쓰는 regular·medium·semibold·bold·heavy(=ExtraBold 800). light·black 은 쓰임이 6곳뿐이라 싣지 않고
// 가까운 굵기로 맞춘다(Compose 글꼴 고르기 규칙).
package com.yehsung.aingcheck.ui.fonts

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.yehsung.aingcheck.ui.resources.Res
import com.yehsung.aingcheck.ui.resources.pretendard_bold
import com.yehsung.aingcheck.ui.resources.pretendard_extrabold
import com.yehsung.aingcheck.ui.resources.pretendard_medium
import com.yehsung.aingcheck.ui.resources.pretendard_regular
import com.yehsung.aingcheck.ui.resources.pretendard_semibold
import org.jetbrains.compose.resources.Font
import org.jetbrains.compose.resources.FontResource

object Pretendard {
    const val FAMILY_NAME = "Pretendard"
    const val VERSION = "1.3.9"
    const val LICENSE_PATH = "files/licenses/Pretendard-OFL-1.1.txt"

    /** 실은 굵기 → (리소스, composeResources 안 경로, 원본 sha256). 시험이 바이트·이름·한글 범위를 잰다. */
    class Face(val weight: FontWeight, val resource: FontResource, val path: String, val sha256: String)

    val faces: List<Face> = listOf(
        Face(FontWeight.Normal, Res.font.pretendard_regular, "font/pretendard_regular.otf",
            "3ffbacde6ab8411f1d2db54bb9b1f0b3ee2a738932033722cf0388c06aed1c93"),
        Face(FontWeight.Medium, Res.font.pretendard_medium, "font/pretendard_medium.otf",
            "d39e50e4bb52b4993b6a4eeb821a171254745bd824446af01e1f616b89fface0"),
        Face(FontWeight.SemiBold, Res.font.pretendard_semibold, "font/pretendard_semibold.otf",
            "c89bc43027dc7cde5726e96223376f8eec09302b2fc1f8147fd5b57cfc376118"),
        Face(FontWeight.Bold, Res.font.pretendard_bold, "font/pretendard_bold.otf",
            "2e91915fab54df71cc9598ebf608b2bdb54c6fe3c066ac61dff0bc44fca71cc7"),
        Face(FontWeight.ExtraBold, Res.font.pretendard_extrabold, "font/pretendard_extrabold.otf",
            "c35fe941b7568d52a96010561540e47f9d3948dfde66ba25bc1908233e0a40cd"),
    )
}

/** Pretendard 글꼴 묶음(다섯 굵기). Compose 리소스 글꼴은 컴포지션 안에서 연다. */
@Composable
fun pretendardFontFamily(): FontFamily = FontFamily(Pretendard.faces.map { Font(it.resource, it.weight) })
