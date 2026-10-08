import CheckCore
import CheckMobileShared
import Foundation

/// AI 리밋 카드 문구(v0.3.45 — 플랫폼 무관, macOS `swift test` 가 값으로 검증한다).
///
/// 규약(코어 `AILimitFreshnessRule` 머리말과 같은 것):
///  · **출처를 말하지 않는다**. "맥에서 읽어 서버를 거쳐 왔다"는 진단 어휘이고 사용자가 답할 수 있는 질문이
///    아니다(2026-09-22 결정 — 토큰 행이 같은 규약이다). 캡션은 **나이만** 말한다.
///  · 숫자·캡션·"이상" 접미사는 여기서 만들지 않는다 — 코어 규칙이 만든 `AILimitDisplay` 를 그대로 쓴다.
///    여기 있는 것은 제목·빈 상태·토큰 줄처럼 리밋 값이 아닌 문장뿐이다.
extension MeText {
    // MARK: AI 리밋

    package static let aiLimitsTitle = "AI 리밋"
    /// 카드 아래 한 줄(값이 무엇을 뜻하는지). "쓴 비율"을 말해 둬야 72%가 "많이 남았다"로 읽히지 않는다.
    package static let aiLimitsCaption = "5시간 창과 주간 창에서 쓴 비율이에요."
    /// 한 번도 못 받았을 때(불러오는 중). 실패해도 들고 있던 값이 있으면 이 문구를 쓰지 않는다.
    package static let aiLimitsLoading = MeText.loading
    package static let aiLimitsFailed = "AI 리밋을 불러오지 못했어요"
    /// 그릴 줄이 하나도 없다 — 까닭이 **둘**이다(연동이 없다 · 맥 설정에서 껐다). 글자는 위젯과 **같은 상수**
    /// 하나에서 온다(`AILimitSurfaceText` — 두 문을 함께 가리키는 한 문장을 고른 근거도 거기 있다).
    /// ★ 여기에 "로그인하면 보여요" 를 다시 적지 마라: 설정에서 끈 사람은 이미 로그인해 있다.
    package static let aiLimitsNoProviders = AILimitSurfaceText.noVisibleProviders

    /// 카드 제목의 보이스오버가 덧붙이는 말(화면에는 칩이 없다 — 줄마다의 숫자가 이미 다 보인다).
    /// "가장 높은"이지 "평균"이 아니다 — 요약은 5시간 창의 **최악**을 모은다(`AILimitsStore.fiveHourSummary`).
    package static let aiLimitsFiveHourPeak = "5시간 가장 높은 값"

    /// 창 라벨 + 값 한 줄(보이스오버). 예: "Claude 5시간 27%, 12분 전".
    package static func aiLimitAccessibility(provider: AILimitProvider, display: AILimitDisplay) -> String {
        let window = display.window?.displayName ?? ""
        return "\(provider.displayName) \(window) \(display.valueText), \(display.captionText)"
    }

    /// 줄 하나를 **한 문장**으로(보이스오버). 예: "사무실 iMac, Claude, Claude 5시간 91%, 10분 전, 주간 44%, 10분 전".
    ///
    /// ## 왜 뷰가 아니라 여기서 만드나
    /// 카드 뷰는 `#if os(iOS)` 라 맥 스위트가 **한 줄도 컴파일하지 않는다**. 라벨을 뷰 안에서 이어 붙이면
    /// "기기 이름이 맨 앞에 온다"를 재는 그물이 소스 grep 하나뿐이 되고, grep 은 항목 순서를 바꾸거나 한
    /// 조각을 빼는 변형을 **못 잡는다**(실증: 기기 이름을 라벨에서 뺀 변형이 안 물렸다).
    ///
    /// ## 왜 기기 이름이 **맨 앞**인가
    /// 보이스오버는 한 줄씩 읽는다. 묶음 머리글을 지나쳐 세 번째 줄에 바로 닿은 사람에게 "Claude 5시간 91%" 는
    /// **어느 맥인지 말하지 않는다** — 이 기능이 고치려던 바로 그 거짓이 소리에만 남는다. 뒤에 붙이면 숫자를
    /// 다 들은 뒤에야 주인이 나온다.
    ///
    /// `deviceName` nil = 맥이 한 대다(= 말할 것이 없다). 글자는 스토어가 정한 것 그대로(겹침 꼬리까지 붙은 값)다.
    package static func aiLimitRowAccessibility(deviceName: String?, row: AILimitDisplayRow) -> String {
        let windows = AILimitWindow.allCases.sorted { $0.sortOrder < $1.sortOrder }.map { window -> String in
            guard let display = row.display(window) else {
                return aiLimitAbsentAccessibility(window: window)
            }
            return aiLimitAccessibility(provider: row.provider, display: display)
        }
        return ([deviceName, row.provider.displayName].compactMap { $0 } + windows).joined(separator: ", ")
    }

    /// 그 창이 **아예 없는** 칸(보이스오버). 예: "5시간 없음".
    ///
    /// ★ 판정 불가(`—`)와 **다른 말이어야 한다**. 화면의 글자를 그대로 읽어 주는 것이고, 글자는 공유 규칙
    /// (`AILimitColumnText.absentValueText`) 하나에서 온다 — 여기에 "모름"을 따로 적으면 보는 사람과
    /// 듣는 사람이 다른 사실을 받는다.
    package static func aiLimitAbsentAccessibility(window: AILimitWindow) -> String {
        "\(window.displayName) \(AILimitColumnText.absentValueText)"
    }

    // MARK: 토큰 축(리밋과 나란히 — 섞지 않는다)

    package static let aiTokenTodayTitle = "오늘 AI 토큰"
    package static let aiTokenRecentTitle = "최근 12주"

    /// "12,345,678 토큰" · 0 이면 "사용 없음"(잔디 말풍선과 **같은 함수**를 거친다 — 같은 값을 두 화면이 다르게 읽지 않게).
    package static func aiTokenValue(_ tokens: Int) -> String {
        TokenDailyGrid.tooltipValueText(tokens)
    }

    /// 좁은 자리(위젯·카드 우측)용 축약 — "196.6억 토큰".
    package static func aiTokenCompact(_ tokens: Int) -> String {
        tokens > 0 ? "\(TokenNumberFormatter.compactKorean(tokens)) 토큰" : TokenDailyGrid.tooltipValueText(0)
    }
}
