import CheckCore
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
    /// 연동한 도구가 하나도 없다 — **설정 토글이 없는 기능**이라 "맥에서 로그인하면 보인다"가 유일한 다음 행동이다.
    package static let aiLimitsNoProviders = "맥 앱에서 AI 도구에 로그인하면 보여요"

    /// 창 라벨 + 값 한 줄(보이스오버). 예: "Claude 5시간 27%, 12분 전".
    package static func aiLimitAccessibility(provider: AILimitProvider, display: AILimitDisplay) -> String {
        let window = display.window?.displayName ?? ""
        return "\(provider.displayName) \(window) \(display.valueText), \(display.captionText)"
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
