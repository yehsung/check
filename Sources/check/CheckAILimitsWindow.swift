import AppKit
import CheckCore
import SwiftUI

// MARK: - AI 리밋 창 (v0.3.45)
//
// `CheckSettingsWindowController.swift` 의 **형제**다. 그 파일의 규약을 그대로 베꼈고(지연 생성 · 멱등 열기 ·
// 닫아도 파괴 안 함 · 자리 저장 이름 등록 · 고착 감시자 + 재생성 상한 · 테스트 알파 0), 달라지는 것은 숫자와
// 담는 뷰뿐이다. 그 규약 하나하나의 근거는 그 파일 머리말에 있다 — 특히:
//   · `makeKeyAndOrderFront` 는 **조용히 실패할 수 있다**(v0.2.27 할 일 보드 실측: `isVisible` 이 true 라고
//     거짓말했고 창은 어느 Space 에도 없었다). 통한 복구는 **창을 버리고 새로 만드는 것** 하나뿐이었다.
//   · `setFrameAutosaveName` 은 같은 이름이 이미 등록돼 있으면 **false 를 돌려주고 아무 일도 하지 않는다** —
//     재생성 경로에서 옛 창의 등록을 안 풀면 자리가 영영 저장되지 않는다.
//
// ## 왜 팝오버 안이 아니라 별도 창인가 (2026-10-07 사용자 결정)
// 팝오버 본문 열은 **316pt** 로 고정이고(카드 안쪽 292), 거기에 제공자 셋 × 창 둘 = 바 여섯 개와 리셋 시각
// 캡션을 넣으면 세로가 한 화면을 넘긴다. 팝오버는 근무 상태를 보는 자리이고 리밋은 **들여다보는** 자리라
// 체류 시간도 다르다. 그래서 요약은 한 줄로 팝오버에 남기고(`CheckAILimitsRow`) 상세는 이 창이 받는다.
//
// ## ★ 툴팁 레이어
// 이 창의 루트에는 `.checkTooltipLayer()` 가 **반드시** 있어야 한다. 없으면 `.checkTooltip` 이 시스템 툴팁으로
// 폴백하는데, 시스템 툴팁은 이 저장소가 실측한 대로 2/6 확률 · 1.7초 지연이라 사실상 안 뜬다
// (`CheckTooltip.swift` 머리말 — v0.3.25 가 자체 말풍선을 만든 이유).
//
// ## ★ 스페이스 키
// 이 창의 식별자는 `MiniGameSpaceKey.standaloneWindowIDs` 에 들어 있어야 한다. 그 목록이 모르는 창에서 누른
// 스페이스는 미니게임 창이 띄워져 있을 때 **통째로 삼켜진다**(2026-09-17 실사용 제보 · 체스 창이 같은 이유로
// 등록돼 있다). 이 창에 입력칸은 없지만 스페이스로 스크롤하는 사람이 있고, 무엇보다 이 등록은 창을 만들 때마다
// 치러야 하는 비용이다.

// MARK: - 레이아웃 (순수 상수)

/// 리밋 창의 **고정** 레이아웃. 창 크기를 두 곳에 적지 않는다.
///
/// ── 숫자의 근거 ──
///  · `cardInnerWidth` 가 먼저 정해졌다: 카드 한 줄에 [타일 28][이름+리셋 캡션][큰 %] 가 서야 한다.
///    실측(10pt, 2026-10-07) "안티그래비티" 51.9 · "오후 6:59 리셋" 62.97 · "초기화됨 · 확인 못 함" 84.0 이고
///    큰 숫자는 22pt bold monospacedDigit 로 "100% 이상" 이 **106.3** 이다.
///    글 열 최악 84 + 간격 10 + 숫자 106.3 + 타일 28 + 간격 10 = 238.3 → 여유를 둔 **280**.
///  · `contentWidth` = 280 + 카드 패딩 14×2 + 창 패딩 20×2 = **348**. 창은 리사이즈된다(넓히면 글 열이 는다).
///  · `cardHeight 100` = 패딩 14×2 + 머리 줄 28 + 8 + 5시간 바 6 + 10 + 주간 라벨 12 + 4 + 주간 바 3 = 99 → 100.
///  · 안내 한 줄(만료·429·구독 리밋 없음)이 붙으면 +18 이다 — 카드 높이를 **고정하지 않고** 자연 높이로 두고,
///    목록을 `ScrollView` 에 담아 어떤 조합에서도 잘리지 않게 한다(창 높이 계약이 제공자 수 × 상태에 끌려다니면
///    `CheckSettingsWindow` 가 겪은 "행이 붙을 때마다 상수를 올리는" 쳇바퀴가 그대로 재현된다).
enum AILimitWindowLayout {
    static let contentPadding: CGFloat = 20
    static let cardPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 10
    static let cardCornerRadius: CGFloat = 14

    /// 카드 안쪽 글·바가 설 폭.
    static let cardInnerWidth: CGFloat = 280
    /// 창 콘텐츠 폭.
    static var contentWidth: CGFloat { cardInnerWidth + cardPadding * 2 + contentPadding * 2 }

    /// 제공자 로고 타일 한 변.
    static let tileSide: CGFloat = 28
    /// 카드 머리 줄 높이(타일·이름·큰 숫자가 같은 줄에 선다).
    static let headerRowHeight: CGFloat = 28
    /// 5시간 바 높이(크게).
    static let fiveHourBarHeight: CGFloat = 6
    /// 주간 바 높이(얇게).
    static let weeklyBarHeight: CGFloat = 3
    /// 카드 안쪽 세로 간격(머리 줄 ↔ 5시간 바 ↔ 주간 묶음).
    static let cardRowSpacing: CGFloat = 8
    static let weeklyBlockSpacing: CGFloat = 10
    static let weeklyLabelSpacing: CGFloat = 4

    /// 안내 한 줄이 없는 카드의 자연 높이.
    static let cardHeight: CGFloat = 100
    /// 안내 한 줄이 붙으면 더해지는 높이.
    static let noticeExtraHeight: CGFloat = 18

    /// 창 머리글 높이.
    static let headerHeight: CGFloat = 24
    static let headerSpacing: CGFloat = 12

    /// 카드 `n` 장이 필요한 콘텐츠 높이(안내 줄은 세지 않는다 — 넘치면 스크롤이 받는다).
    static func contentHeight(cards: Int) -> CGFloat {
        let list = CGFloat(max(1, cards)) * cardHeight + CGFloat(max(0, cards - 1)) * cardSpacing
        return contentPadding * 2 + headerHeight + headerSpacing + list
    }

    /// 제공자 셋이 다 있는 기본 창 크기.
    static var defaultContentSize: NSSize {
        NSSize(width: contentWidth, height: contentHeight(cards: AILimitProvider.allCases.count))
    }

    /// 최소 크기(카드 한 장).
    static var minContentSize: NSSize {
        NSSize(width: contentWidth, height: contentHeight(cards: 1))
    }
}

// MARK: - 카드가 그릴 것 (순수)

/// 카드 한 장이 그릴 것. **값·캡션·"이상" 깃발은 전부 `AILimitFreshnessRule` 이 만들고**, 이 타입이 하는 일은
/// 그 중 **어느 창을 머리 숫자로 세우나** 하나다.
///
/// ## 왜 '대표 창 고르기'가 한 자리에 있어야 하는가 (2026-10-07 실증한 결함)
/// 초안 카드는 `store.display(provider:window:.fiveHour)` 를 **무조건** 머리 숫자로 그렸다. 그런데 5시간 창이
/// **아예 없는** 계정이 있다(주간만 오는 요금제 · 안티그래비티는 그룹 구성이 달라 5시간 칸이 비는 날이 있다 —
/// 실측 §3). 그 계정에서 큰 글자는 `—`, 캡션은 `알 수 없음` 이 되고 **주간 60% 는 얇은 줄로만 남았다.**
/// 규칙은 이미 `isVisible` 로 "이 자리를 만들지 마라"를 말하고 있었는데 뷰가 그 깃발을 무시한 것이다.
/// 같은 데이터로 폰은 머리 줄을 안 그리고(`AILimitDisplayRow.visibleWindows`) 위젯은 주간을 대표로 올린다
/// (`AingWidgetLimitRow.primaryWindow`) — 세 화면이 같은 숫자를 **다르게** 말했다.
///
/// 그래서 선택 규칙을 폰·위젯과 같게 둔다: **보이는 창을 5시간 → 주간 순서로 담고 첫 줄이 머리**다.
/// 그리고 머리 줄에는 **창 라벨을 값과 함께** 적는다(`headWindowLabel`) — 대표 창이 카드마다 다를 수 있으므로,
/// 라벨이 없으면 이 카드의 주간 8% 가 옆 카드의 5시간 27% 와 같은 창으로 읽힌다(위젯이 라벨을 값과 한 묶음으로
/// 내보내는 것과 같은 근거).
struct AILimitCardModel: Equatable, Identifiable {
    let provider: AILimitProvider
    /// **보이는** 창들, 5시간 → 주간 순서. 없는 창은 줄을 만들지 않는다(0% 로 지어내지 않는다).
    let windows: [AILimitDisplay]
    /// 만료·429·플랜 없음의 한 줄(없으면 nil). 네트워크 실패에는 **문구가 없다** — 숫자를 그대로 두고
    /// 나이 캡션만 낡게 하는 것이 그때의 정직한 표시다(`AILimitReadFailure.noticeText` 주석).
    let notice: String?
    /// 플랜 라벨("plus"/"max"). 없으면 안 그린다.
    let planLabel: String?
    /// 머리 캡션에 **덧붙일** 리셋 시각(`오후 6:59 리셋`). 없으면 nil.
    ///
    /// `make` 가 `now` 를 알 때 만든다. 저장하는 까닭 둘:
    ///  · **이미 지난 리셋은 안 적는다.** 유예(120초) 안쪽에서 리셋이 막 지난 동안 값은 아직 90% 가 맞는데
    ///    (`AILimitFreshnessRule` 함정 ②) 캡션이 `오후 2:04 리셋` 이라고 **지난 시각**을 미래처럼 말했다
    ///    (2026-10-07 실측: 지금이 2:05). 그 판정에는 `now` 가 필요하다.
    ///  · 리셋을 **이미 주장한** 창(0% · 초기화됨)에서는 규칙의 문구가 그 사실을 말하므로 덧붙이지 않는다.
    let headResetText: String?

    var id: AILimitProvider { provider }

    /// 머리 줄이 말하는 것 = 대표 창. 보이는 창이 하나도 없으면 nil(그 카드는 안내 한 줄만 말한다).
    var head: AILimitDisplay? { windows.first }
    /// 머리 아래에 **따로** 그릴 줄들. 대표로 선 창은 빠진다 — 같은 값을 한 카드에 두 번 그리지 않는다.
    var rest: [AILimitDisplay] { Array(windows.dropFirst()) }
    /// 큰 숫자. 대표 창이 없으면 규칙의 '판정 불가' 글자(`—`)다 — `0%` 로 지어내지 않는다.
    var headValueText: String { head?.valueText ?? AILimitFreshnessRule.unknownValueText }
    /// 큰 숫자가 **어느 창인가**("5시간" · "주간"). 모르면 nil.
    var headWindowLabel: String? { head?.window?.displayName }

    /// 머리 줄의 캡션 = **관측 나이**(`3시간 전` · `초기화됨 · 확인 못 함` · `알 수 없음`).
    ///
    /// ## ★ 나이를 리셋 시각으로 **갈아 치우지 않는다** (v0.3.45 P2)
    /// 초안은 리셋 주장이 아니면 **항상** `오후 3:05 리셋` 만 적었다. 그래서 맥 카드는 이 숫자가 얼마나
    /// 묵었는지를 **아예 말하지 않았다** — 폰은 같은 자리에 `3시간 전` 을 적는다. 숫자의 "이상"과 바의
    /// 투명도가 하한임을 알리지만 그것은 "30분을 넘었다"까지이고, 3시간인지 3일인지는 말하지 못한다
    /// (`AILimitFreshnessRule` 머리말 ⓑ — 묵은 값을 지금 값으로 읽는 것이 **비싼 쪽**의 거짓이다).
    ///
    /// 리셋 시각은 버리지 않고 **덧붙인다**(`headCaptionDetailed`). 다만 글 열 예산이 좁아
    /// (실측 "3시간 전 · 오후 6:59 리셋" 107.19pt > 나이만 35.27pt) 뷰가 `ViewThatFits` 로 좁은 창에서는
    /// 리셋 쪽을 **뺀다** — 말줄임보다 조각 빼기가 이 저장소 규칙이고, 창은 리사이즈되므로 넓히면 둘 다 선다.
    var headCaption: String {
        head?.captionText ?? Self.unknownCaption
    }

    /// 나이 + 리셋 시각(`3시간 전 · 오후 6:59 리셋`). 리셋을 모르거나 이미 지났으면 나이만.
    var headCaptionDetailed: String {
        guard let headResetText else { return headCaption }
        return "\(headCaption) · \(headResetText)"
    }

    /// '판정 불가' 캡션은 **규칙에서 가져온다**. 여기에 "알 수 없음"을 다시 적으면 문구가 두 벌이 되고,
    /// 한쪽만 고쳐지는 날 화면과 규칙이 다른 말을 한다.
    static let unknownCaption = AILimitFreshnessRule.captionText(
        freshness: .unknown, reference: .distantPast, now: .distantPast
    )

    /// 목록에 세울 카드 전부(순수 — 테스트가 직접 부른다). 순서·숨김은 스토어가 이미 정했다.
    @MainActor
    static func all(store: AILimitStore, now: Date) -> [AILimitCardModel] {
        store.listedProviders.map { make(store: store, provider: $0, now: now) }
    }

    /// 카드 한 장. 창은 **규칙에 물어** 만들고 `isVisible` 이 거짓인 창은 담지 않는다.
    @MainActor
    static func make(store: AILimitStore, provider: AILimitProvider, now: Date) -> AILimitCardModel {
        let windows = AILimitWindow.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { store.display(provider: provider, window: $0, now: now) }
            .filter(\.isVisible)
        return AILimitCardModel(
            provider: provider,
            windows: windows,
            notice: store.noticeText(provider: provider),
            planLabel: store.bundle?.provider(provider)?.planLabel,
            headResetText: resetText(head: windows.first, now: now)
        )
    }

    /// 머리 캡션에 덧붙일 리셋 시각. **지난 시각은 nil** 이고, 리셋을 이미 주장한 창도 nil 이다.
    static func resetText(head: AILimitDisplay?, now: Date) -> String? {
        guard let head, !head.freshness.isResetClaim, let resetsAt = head.resetsAt else { return nil }
        // 유예 안쪽에서 리셋이 막 지난 동안(값은 아직 하한이 맞다) **지난 시각을 미래처럼 적지 않는다.**
        guard resetsAt > now else { return nil }
        return "\(AILimitResetTimeText.text(resetsAt)) 리셋"
    }
}

// MARK: - 카드

/// 제공자 하나의 카드. 로고 타일 + 이름 + `오후 6:59 리셋` 캡션 + 우측 [창 라벨 + 큰 %] + 굵은 바,
/// 그 아래 남은 창(`주간 60%`) + 얇은 바.
///
/// **숫자·캡션·표시여부를 계산하지 않는다** — 전부 `AILimitCardModel`(= 규칙이 만든 `AILimitDisplay`)을 그린다.
struct AILimitProviderCard: View {
    let model: AILimitCardModel

    private var provider: AILimitProvider { model.provider }
    private var planLabel: String? { model.planLabel }

    var body: some View {
        VStack(alignment: .leading, spacing: AILimitWindowLayout.cardRowSpacing) {
            header
            if let head = model.head {
                AILimitBar(
                    percent: head.percent,
                    floorOnly: head.floorOnly,
                    height: AILimitWindowLayout.fiveHourBarHeight,
                    tint: AILimitBar.tint(for: head.percent)
                )
            }
            // 남은 창(보통 주간 하나). 대표 창은 위에서 이미 말했으므로 여기 다시 나오지 않는다.
            ForEach(model.rest, id: \.window) { display in
                secondaryBlock(display)
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.pending)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(AILimitWindowLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AILimitWindowLayout.cardCornerRadius, style: .continuous)
                .fill(CheckTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: AILimitWindowLayout.cardCornerRadius, style: .continuous)
                        .stroke(CheckTheme.border, lineWidth: 1)
                )
        )
    }

    /// 머리 줄. 캡션은 **나이 + 리셋 시각**이 먼저고, 글 열이 좁으면 리셋 쪽을 뺀다(말줄임 대신 조각 빼기 —
    /// 나이는 어느 쪽에서도 **남는다**: 이 숫자가 얼마나 묵었는지는 지울 수 없는 사실이다).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(caption: model.headCaptionDetailed, canShrink: false)
            headerRow(caption: model.headCaption, canShrink: true)
        }
    }

    private func headerRow(caption: String, canShrink: Bool) -> some View {
        HStack(spacing: 10) {
            AIProviderTile(provider: provider, size: AILimitWindowLayout.tileSide)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // ★ 제공자를 **색으로만** 구분하지 않는다(위젯 틴트 모드가 색을 버린다 ·
                    //   `AIProviderLogo.swift` 머리말). 타일 옆에 항상 이름 글자가 있다.
                    Text(provider.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    if let planLabel {
                        Text(planLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CheckTheme.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(CheckTheme.fieldFill))
                            .lineLimit(1)
                    }
                }
                // ★ 첫 갈래는 줄이지 않는다(`fixedSize`) — 줄일 수 있으면 `ViewThatFits` 가 언제나 첫 갈래를
                //   고르고 리셋을 뺄 일이 없어져, 글 열이 숫자를 밀어낸다.
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(canShrink ? 0.8 : 1)
                    .fixedSize(horizontal: !canShrink, vertical: false)
            }
            Spacer(minLength: 8)
            // ★ 큰 숫자 **옆에 창 라벨**이 붙는다. 대표 창은 카드마다 다를 수 있어서(5시간 창이 없는 요금제가
            //   있다) 라벨이 없으면 주간 8% 가 옆 카드의 5시간 27% 와 같은 창으로 읽힌다.
            if let label = model.headWindowLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Text(model.headValueText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(height: AILimitWindowLayout.headerRowHeight)
    }

    /// 대표 창 아래의 얇은 줄(라벨 + 값 + 얇은 바). 라벨은 그 창의 이름이다 — `주간` 을 글자로 박지 않는다
    /// (대표가 주간인 카드에서는 이 자리에 5시간이 설 수도 있다).
    private func secondaryBlock(_ display: AILimitDisplay) -> some View {
        VStack(alignment: .leading, spacing: AILimitWindowLayout.weeklyLabelSpacing) {
            Text("\(display.window?.displayName ?? "") \(display.valueText)")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            AILimitBar(
                percent: display.percent,
                floorOnly: display.floorOnly,
                height: AILimitWindowLayout.weeklyBarHeight,
                tint: AILimitBar.tint(for: display.percent)
            )
        }
        .padding(.top, AILimitWindowLayout.weeklyBlockSpacing - AILimitWindowLayout.cardRowSpacing)
    }
}

/// 리셋 시각을 `오후 6:59` 로 적는다(KST 기준 기기 시간대).
///
/// 초 이하를 쓰지 않는 이유: Claude 의 `resets_at` 에는 요청 시각의 잔여 분수(`…00.434051`)가 섞여 온다 —
/// 초를 적으면 같은 경계가 호출마다 다르게 보인다.
enum AILimitResetTimeText {
    static func text(_ date: Date, locale: Locale = Locale(identifier: "ko_KR"), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 창 본문

/// 창에 담기는 뷰. 카드 목록 하나뿐이라 스토어를 통째로 읽는다.
///
/// ## ★ 시각은 **값이 아니라 클로저**다 (2026-10-07 실증한 P0)
/// 초안은 `var now: Date = Date()` 였다. 기본 인자는 **딱 한 번** 평가되고, 그 한 번은 `configure` 의 기본
/// content 클로저가 이 뷰를 만드는 순간이다. 창은 `windowStorage` 에 캐시돼 닫아도 파괴되지 않으므로
/// (아래 컨트롤러) 그 `now` 는 **앱 수명 내내 창을 처음 만든 시각**으로 얼어붙었다.
/// 재현: 09:00Z 에 창을 연다 → 13:50Z 에 스토어가 5시간 창 88% · 리셋 14:00Z 를 받는다 → 15:00Z 에 같은 창이
/// `88% · 방금` 을 그린다(맞는 값은 `0% · 초기화됨 · 확인 못 함`). 리셋이 한 시간 전에 지났는데 사용자는
/// "88% 썼다"를 보고 작업을 멈춘다 — `AILimitFreshnessRule` 머리말 ⓐ 가 적어 둔 바로 그 거짓이다.
/// 그 사이 팝오버 한 줄은 `clock:` 으로 **클로저**를 받아 정상이었다 = 두 화면이 다른 말을 했다.
///
/// 그래서 ① 저장된 `Date` 를 없애고(규약: 이 자리에 `Date()` 기본 인자를 다시 두지 마라 —
/// `AILimitFreshnessRule` 머리말이 "`Date()` 를 부르지 않는다"로 적은 그 규약이다) ② 창이 떠 있는 동안
/// **분마다 다시 그린다**(`TimelineView`). 둘 다 필요하다: 클로저만 있으면 스토어가 갱신될 때까지 캡션이
/// 안 늙고, 틱만 있으면 얼어붙은 값이 분마다 똑같이 다시 그려진다.
struct CheckAILimitsView: View {
    let store: AILimitStore
    /// 표시 기준 시각을 **읽는 클로저**(값이 아니다 — 팝오버 한 줄 `CheckAILimitsRow.clock` 과 같은 모양).
    let clock: () -> Date

    /// 창이 떠 있는 동안 다시 그리는 주기(초). 나이 캡션의 가장 작은 단위가 '분'이라 분이면 충분하고
    /// (`FeedbackText.ageText`), 리셋 유예(120초)보다 짧아 리셋도 한 틱 안에 드러난다.
    static let tickSeconds: TimeInterval = 60

    /// 지금 그릴 카드들. **시계를 읽는 자리가 여기다** — 테스트가 이 문으로 "시각이 흐르면 다른 값을 그린다"를 잰다.
    var cards: [AILimitCardModel] { AILimitCardModel.all(store: store, now: clock()) }
    /// 머리글 오른쪽의 나이 캡션(한 줄 요약의 캡션 — 숫자는 카드가 말한다).
    var summaryCaption: String { store.summary(now: clock()).captionText }

    var body: some View {
        // ★ 분 틱. `TimelineView` 는 창이 **보이는 동안** 이 서브트리를 주기적으로 다시 평가한다 —
        //   값은 그 칸의 날짜가 아니라 **`clock()`** 에서 읽는다(틱은 "다시 그려라"만 말하고, "지금이 언제인가"는
        //   주입된 시계 하나가 말한다. 둘을 섞으면 축이 둘이 되고 테스트가 잴 자리가 사라진다).
        TimelineView(.periodic(from: clock(), by: Self.tickSeconds)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AILimitWindowLayout.headerSpacing) {
            header
            if store.listedProviders.isEmpty {
                emptyState
            } else {
                // 안내 줄이 붙어 카드가 자라도 잘리지 않게 목록은 스크롤에 담는다(레이아웃 주석 참고).
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AILimitWindowLayout.cardSpacing) {
                        ForEach(cards) { card in
                            AILimitProviderCard(model: card)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AILimitWindowLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CheckTheme.background)
        // ★ 창 루트의 툴팁 레이어. 없으면 `.checkTooltip` 이 시스템 툴팁으로 폴백한다(머리말).
        .checkTooltipLayer()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CheckTheme.accent)
            Text("AI 리밋")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
            Spacer(minLength: 6)
            Text(summaryCaption)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(height: AILimitWindowLayout.headerHeight)
    }

    /// 보여 줄 제공자가 없을 때. **빈 카드를 0% 로 지어내지 않는다.**
    private var emptyState: some View {
        Text("읽을 수 있는 AI 구독이 없습니다")
            .font(.caption)
            .foregroundStyle(CheckTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 창 컨트롤러

/// AI 리밋 창의 수명·표시·복구를 쥐는 단 하나의 지점.
///
/// 공개 진입점은 `show()` 하나다(팝오버 한 줄이 부른다). 배선은 앱 시작 때 `configure(store:)` 가 한 번 한다.
@MainActor
final class CheckAILimitsWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckAILimitsWindowController()

    /// 창 제목. CGWindowList 로 밖에서 셀 때의 표식이기도 하다(중복 창 검사).
    static let windowTitle = "AI 리밋"
    /// 자리 저장 키 = 창 식별자. **`MiniGameSpaceKey.standaloneWindowIDs` 가 읽는 값이다**(머리말 ★).
    static let frameAutosaveName = "check.aiLimitsWindow"

    /// 창을 물릴 재료. 스토어와 담을 뷰를 함께 묶는다 — 따로 두면 스토어만 물리고 콘텐츠는 플레이스홀더인
    /// 조합이 만들어진다(`CheckSettingsWindowController.Wiring` 과 같은 이유).
    struct Wiring {
        let store: AILimitStore
        let content: @MainActor (AILimitStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 지연 생성된 창. **닫아도 파괴하지 않는다**(스크롤 자리·크기가 매번 초기화되지 않게).
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). 실제 표시 여부는 창 서버가 아는 사실이고 `isVisible` 은 이 저장소에서
    /// 이미 한 번 거짓말했다 — 그래서 '의도'와 '사실'을 다른 이름으로 분리해 둔다.
    private(set) var isOpen = false
    var hasWindow: Bool { windowStorage != nil }
    private(set) var frameAutosaveActive = false
    /// 창을 열 때 불린다(스토어 갱신을 당기는 자리 — 컨트롤러가 스토어의 주기를 모르게 둔다).
    var onOpen: (() -> Void)?

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckAILimitsWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    /// 창을 물린다(앱 시작 때 1회).
    ///
    /// ★ 기본 content 는 뷰에 **시계 클로저**를 넣는다. 값(`Date()`)을 넣으면 그 한 번의 평가가 창의 수명 내내
    ///   얼어붙는다(`CheckAILimitsView` 머리말의 P0). 그리고 그 클로저는 `WorkTimerStore.displayNow` 가
    ///   **아니라** 진짜 벽시계다 — `displayNow` 는 팝오버가 닫히면 미는 쪽이 멈춰서, 팝오버를 닫고 창만 보는
    ///   사람에게 같은 얼어붙음이 다시 생긴다(그게 `leagueClockNow` 를 팝오버 행에 쓰는 것과 갈리는 지점이다).
    func configure(
        store: AILimitStore,
        content: @escaping @MainActor (AILimitStore) -> AnyView = { store in
            AnyView(CheckAILimitsView(store: store, clock: { Date() }))
        }
    ) {
        wiring = Wiring(store: store, content: content)
    }

    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        // `setFrameAutosaveName` 만으로는 **복원이 일어나지 않는다**(저장만 한다). 복원은 `setFrameUsingName` 이다.
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        // 반환값을 버리지 않는다 — 같은 이름이 이미 등록돼 있으면 false 를 돌려주고 자리가 조용히 저장되지 않는다.
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AILimitWindowLayout.defaultContentSize),
            // `.miniaturizable` 은 일부러 뺐다 — `LSUIElement` 앱은 Dock 타일이 없어 최소화한 창을 되돌리는
            // 길이 없다(`CheckSettingsWindowController.makeWindow` 와 같은 근거).
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = AILimitWindowLayout.minContentSize
        // 우리가 창을 붙들고 재사용하므로 닫힘에 딸린 해제가 끼면 다음 `show()` 가 해제된 창을 만진다.
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // ★ 앱 전체가 다크다(`CheckTheme`). 시스템 외관을 따라가면 밝은 테마에서 흰 배경 위 흰 글자가 나온다.
        window.appearance = NSAppearance(named: .darkAqua)
        // 지금 보고 있는 화면으로 온다. `.canJoinAllSpaces` 는 떠 있는 보조 패널의 계약이고 이 창의 것이 아니다.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0. 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    /// 창을 연다(멱등 — 여러 번 불러도 창은 하나다).
    ///
    /// **이 문은 팝오버를 닫지 않는다** — 활성화만으로 팝오버가 닫힌다는 통념은 v0.2.49 실측에서 거짓으로
    /// 판명됐다(`WindowTopAnchor.dismissMenuPopover` 주석). 팝오버에서 열 때는 **호출부**가 닫는다.
    func show() {
        guard let window else { return }
        onOpen?()
        // 테스트에서는 활성화하지 않는다 — 알파 0 은 창을 안 보이게 할 뿐 포커스는 못 막는다.
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        armStuckWindowWatchdog()
    }

    /// 창을 내린다(멱등). 창과 그 안의 상태는 남는다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
    }

    // MARK: 창이 화면에 못 올라갔을 때의 복구

    /// 주문 뒤 창이 실제로 떴는지 확인하기까지 두는 여유(초). 값의 근거는 `CheckTodoBoardController` 와 같다.
    static let stuckWindowCheckSeconds: Double = 0.5
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    private(set) var stuckWindowRebuilds = 0

    private func armStuckWindowWatchdog() {
        stuckWindowWatchdog?.cancel()
        let delay = stuckWindowCheckSeconds
        stuckWindowWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // 취소 검사가 없으면 cancel() 이 곧 즉시 실행이다(이 저장소의 다른 감시 태스크와 같은 계약).
            guard let self, !Task.isCancelled, self.isOpen,
                  let stuck = self.windowStorage, Self.isOnScreen(stuck) == false
            else { return }
            self.rebuildStuckWindow()
        }
    }

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 테스트 진입점이라 internal 이다 —
    /// 창 서버를 헤드리스에서 오염시킬 방법이 없으므로 복구 자체는 이 문으로만 검증할 수 있다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        // 델리게이트를 먼저 뗀다 — 아래 close() 의 windowWillClose 가 우리에게 오면 새 창을 세우는 도중
        // isOpen 이 false 로 뒤집힌다.
        old.delegate = nil
        old.contentView = nil
        // ★ 자동저장 이름을 반드시 놓아준다(머리말 — 안 풀면 재생성된 창이 자리를 영영 저장하지 못한다).
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        // ★ `orderOut(nil)` 이 아니라 `close()` 다 — AppKit 은 창을 close 할 때까지 자기 목록에서 붙들고 있어
        //   우리가 참조를 놓아도 창 서버 자원이 남는다(`CheckSettingsWindowController.rebuildStuckWindow` 실측).
        old.close()
        windowStorage = nil
        show()
    }

    /// 이 창이 지금 **실제로** 화면에 올라가 있는가를 창 서버에 직접 묻는다.
    /// 구현을 새로 쓰지 않고 `CheckTodoBoardController.isOnScreen` 을 그대로 부른다 — 이 판정이 두 벌이 되는
    /// 순간 둘 중 하나만 고쳐지는 날이 온다(그날 이 창은 v0.2.27 의 보드가 된다).
    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    /// 지금 창의 상태를 한 줄로(진단·사후 분석이 같은 문장을 본다).
    var diagnosticState: String {
        guard let windowStorage else { return "window=none isOpen=\(isOpen) rebuilds=\(stuckWindowRebuilds)" }
        let onScreen = Self.isOnScreen(windowStorage).map(String.init(describing:)) ?? "unknown"
        return "window=\(windowStorage.windowNumber) isOpen=\(isOpen) isVisible=\(windowStorage.isVisible)"
            + " onScreen=\(onScreen) rebuilds=\(stuckWindowRebuilds)"
    }
}
