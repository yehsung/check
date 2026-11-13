// 오목과 로컬 보드 게임이 같은 빠른 문구를 쓴다. 서버 코드 값은 유지한다.
/// 빠른 문구 여덟. **코드는 서버와 나누고 한국어 문구는 앱만 갖는다** — 서버 `gomoku_chat_quick_codes()` 는
/// 같은 여덟 코드만 검사하고 표에 저장되는 것도 코드다. 그래서 문구를 다듬는 날 서버를 배포할 필요가 없다.
/// 반대로 서버가 코드를 넓히는 날 옛 앱은 그 코드를 모르는데, 그때 말이 사라지지 않게 받는 쪽에서
/// `GomokuNoticeText.chatUnknownQuick` 한 줄로 접는다(소실은 오배달보다 나쁘다).
package nonisolated enum GomokuQuickPhrase: String, CaseIterable, Sendable {
    case hi, gg, nice, hurry, sorry, think, oops, rematch

    package var text: String {
        switch self {
        case .hi: return "안녕하세요"
        case .gg: return "잘 뒀어요"
        case .nice: return "좋은 수네요"
        case .hurry: return "한 수 부탁해요"
        case .sorry: return "미안해요"
        case .think: return "생각 중이에요"
        case .oops: return "실수했어요"
        case .rematch: return "한 판 더 할까요?"
        }
    }
}
