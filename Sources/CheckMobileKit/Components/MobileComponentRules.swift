import Foundation

/// 조회 결과를 화면에 **사실로 말해도 되는가**의 규칙 — 탭마다 따로 적으면 갈라진다(통합 검증: 게임 탭은 고쳤는데 순위 탭은
/// 실패 카드 밑에 "오늘은 아직 아무도 안 했어요"를 그렸고, 게임 허브·오목 로비는 실패를 "없음"으로 그렸다).
///
/// 규칙(모든 탭 공통)
/// - 줄이 하나라도 있으면 적어도 그만큼은 있다(지난 조회 값이어도 거짓이 아니다).
/// - 비어 있으면 **한 번 받았고 마지막 조회가 실패하지 않았을 때만** "없다"고 말한다.
/// - 모르면: 마지막 조회가 실패했으면 실패 문구(+ 다시 시도), 아니면 불러오는 중.
package enum MobileLoadKnowledge {
    /// 빈 자리를 무엇으로 채우는가.
    package enum Placeholder: Equatable, Sendable {
        /// 줄이 있다 — 줄을 그린다.
        case rows
        /// 받았고 비어 있다 — "없어요" 문구.
        case empty
        /// 모르고, 마지막 조회가 실패했다 — "불러오지 못했어요" + 다시 시도.
        case failed
        /// 아직 모른다(첫 조회가 돌거나 아직 안 나갔다).
        case loading
    }

    /// 개수(0 포함)를 안다.
    package static func knowsCount(hasRows: Bool, hasLoaded: Bool, lastFailed: Bool) -> Bool {
        hasRows || (hasLoaded && !lastFailed)
    }

    package static func placeholder(hasRows: Bool, hasLoaded: Bool, lastFailed: Bool) -> Placeholder {
        if hasRows { return .rows }
        if knowsCount(hasRows: hasRows, hasLoaded: hasLoaded, lastFailed: lastFailed) { return .empty }
        return lastFailed ? .failed : .loading
    }
}

/// 조회 실패 화면의 공용 문구. 탭마다 "연결을 확인하고…"·"네트워크를 확인하고…"·"당겨서…"로 갈리던 것을 모은다.
///
/// 모양 규칙(부품은 `Components/MobileComponents.swift`)
/// - **탭 첫 화면 전체**가 비었다(메시지 목록·대화) → `EmptyStateView`(아이콘 · 제목 · `checkConnection` · 주 버튼 `retry`).
/// - **카드 안 한 절**이 비었다(순위 판·기록·제보·설정·상점·게임 순위·오목 절) → `LoadFailureRow`(경고 한 줄 + `RetryButton`).
/// - 절이 이미 줄을 들고 있으면 실패를 조용히 둔다(지난 값을 지우지 않는다) — 한 번도 못 받았을 때만 실패 행을 그린다.
package enum MobileLoadText {
    package static let retry = "다시 시도"
    /// 코어 오목 문구와 같은 문장(`GomokuNoticeText.checkConnection`).
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    package static let retrying = "불러오는 중…"
}

/// 아바타 크기 규칙(탭 공통 — `AvatarView` · `AvatarSpacer`). 순수 함수라 macOS 테스트가 값으로 잰다.
package enum MobileAvatarScale {
    /// 본문 글자 배율을 따라가는 상한. AX3(본문 약 2.8배)에서 48pt 목록 아바타가 72pt 까지 — 이름·미리보기 줄에 폭을 남긴다.
    package static let maximum: CGFloat = 1.5

    /// 기본 글자 크기에서의 지름 × 글자 배율(1 밑으로는 줄이지 않는다 · 상한 `maximum`).
    package static func side(base: CGFloat, textScale: CGFloat) -> CGFloat {
        let factor = min(max(textScale, 1), maximum)
        return (base * factor).rounded()
    }
}

/// 목록(`List`) 행 카드 조각의 자리(`CardSegmentBackground` · `cardSegmentRow`) — 한 절의 행들이 `AingCard` 한 장처럼 이어진다.
package enum CardSegmentPosition: Equatable, Sendable {
    case single, first, middle, last

    /// `index` 번째(0부터) 행의 자리(`count` 행 중).
    package static func of(index: Int, count: Int) -> CardSegmentPosition {
        if count <= 1 { return .single }
        if index <= 0 { return .first }
        return index >= count - 1 ? .last : .middle
    }

    package var roundsTop: Bool { self == .single || self == .first }
    package var roundsBottom: Bool { self == .single || self == .last }
}
