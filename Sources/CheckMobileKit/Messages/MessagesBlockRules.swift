import CheckCore
import Foundation

// 차단·신고의 규칙과 문구는 **코어 한 벌**이다(`Sources/CheckCore/BlockReportRules.swift` — 2026-09-20, 맥 차단·신고).
// 맥도 같은 표를 읽는다: 사실(사유 넷 · 24시간 · 200자 · 무엇이 막히는가)이 두 벌이 되면 한쪽이 언젠가 갈린다.
// 폰이 받는 글자는 옮기기 전과 한 글자도 다르지 않다 — 폰 쪽 길 안내는 `.phone` 으로 고른다.
//
// 여기 남은 것은 폰만의 표현 하나다: 차단한 시각을 **폰의 상대 시각 눈금**(`MobileRelativeTime` — "방금"·"어제"·"9월 3일")으로 말하는 줄.
// 맥은 같은 줄을 자기 눈금(`FeedbackText.ageText`)으로 센다 — 문장의 틀("… 차단")은 코어 한 곳이다.
//
// ★ 신고 자유 입력은 사람이 쓴 문장이다 — 이 파일에도 `print`/`Logger` 를 붙이지 마라(메시지 파일 공통 규약).
extension BlockReportText {
    /// "3일 전 차단"(시각을 모르면 화면이 이 줄을 아예 그리지 않는다).
    package static func blockedAtLine(_ date: Date, now: Date) -> String {
        blockedAtLine(relative: MobileRelativeTime.text(for: date, now: now))
    }
}
