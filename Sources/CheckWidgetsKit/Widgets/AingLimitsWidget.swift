#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI
import WidgetKit

// MARK: - 「AI 리밋」 위젯 (v0.3.45 — 전용 1종 · small/medium/large)
//
// 그리는 값은 전부 `AingWidgetModel.swift`(플랫폼 무관 — 테스트 대상)에서 오고, 이 파일은 배치만 한다.
// 네트워크 없음 · 토큰 읽기 없음: 앱이 쓴 App Group 스냅샷(`WidgetSnapshot.aiLimits`)만 그린다.
//
// ## 이 파일이 지키는 규칙 넷
// 1. **막대만 쓴다.** 링·도넛 게이지(`trim(from:)`)는 틴트·투명 모드에서 트랙과 채움이 한 색이 되어 62%가 꽉 찬
//    원으로 보인다(w11 실측 — 그래서 저장소가 소스 계약으로 금지한다). 채움은 `AingWidgetBar`.
// 2. **색으로만 제공자를 가르지 않는다.** `widgetRenderingMode == .accented` 는 색을 통째로 버리므로 브랜드색
//    타일은 세 줄이 똑같은 덩어리가 된다. 그 모드에서는 **로고 실루엣**만 남기고, 어느 모드에서나 **이름 글자**가
//    타일 옆에 함께 선다.
// 3. **절대 시각을 투영한다.** 스냅샷에는 `resetsAt`(절대)만 있고 "남은 시간"은 칸 시각으로 여기서 만든다 —
//    남은 초를 스냅샷에 실으면 쓰기 창구의 중복 제거가 무력화돼 60초마다 파일을 다시 쓴다.
// 4. **경고 기호를 쓰지 않는다**(`exclamationmark`). 리밋이 90%인 것은 고장이 아니다.
//
// ## 두 빈 상태를 섞지 않는다
// `noData`("앱을 열면 채워져요")와 `noProviders`("맥 앱에서 AI 도구에 로그인하면 보여요")는 사용자가 할 일이
// 다르다. 하나로 합치면 맥을 안 쓰는 사람이 앱만 몇 번이고 열게 된다.

/// 리밋 위젯이 눌렸을 때 열 화면 — 카드가 있는 **나 탭**이다(다른 세 위젯은 지금 탭을 연다).
enum AingLimitsLinks {
    static let me = URL(string: "aingcheck://me")!
}

/// 리밋 위젯**만의** 타임라인 공급자. 읽는 것은 다른 세 위젯의 공급자(`AingWidgetProvider`)와 똑같고
/// (App Group 스냅샷 하나 · 네트워크 없음) **칸만 다르다** — 지평 밖 칸을 함께 깐다.
///
/// 왜 공급자를 따로 두는가: 다른 세 위젯의 타임라인 정책을 건드리지 않기 위해서다. 그들이 그리는 것은
/// '우리 서버가 센 사실'이라 늦게 반영돼도 그 시각의 참이고, 칸을 늘리면 얻는 것 없이 엔트리만 늘어난다.
/// 리밋은 **원격 자원의 현재값**을 등호로 단정하는 자리라 재적재가 끊긴 날에도 스스로 열화해야 한다
/// (근거 전부는 `AingWidgetLimitsTimelinePlan` 머리말).
struct AingLimitsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AingWidgetEntry {
        let now = Date()
        return AingWidgetEntry(date: now, snapshot: AingWidgetSamples.snapshot(now: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (AingWidgetEntry) -> Void) {
        let now = Date()
        // 갤러리 미리보기는 지어낸 예시(실사용자 데이터가 갤러리에 뜨지 않게, 로그아웃이어도 모양을 보이게).
        let snapshot = context.isPreview ? AingWidgetSamples.snapshot(now: now) : WidgetSharedData.live().snapshot()
        completion(AingWidgetEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AingWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSharedData.live().snapshot()
        let entries = AingWidgetLimitsTimelinePlan.entryDates(now: now).map {
            AingWidgetEntry(date: $0, snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(AingWidgetLimitsTimelinePlan.nextReload(now: now))))
    }
}

public struct AingAILimitsWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: AingWidgetKind.aiLimits, provider: AingLimitsTimelineProvider()) { entry in
            AingLimitsContainer(entry: entry) { family in
                AingAILimitsContent(entry: entry, family: family)
            }
        }
        .configurationDisplayName(AingWidgetText.limitsGalleryName)
        .description(AingWidgetText.limitsGalleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// 공통 껍데기(다른 위젯의 `AingWidgetContainer` 와 같은 일 — 링크 목적지만 나 탭이다).
private struct AingLimitsContainer<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let entry: AingWidgetEntry
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View {
        content(family)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .widgetURL(AingLimitsLinks.me)
            .containerBackground(for: .widget) { AingWidgetColors.background }
    }
}

// MARK: - 본문

struct AingAILimitsContent: View {
    let entry: AingWidgetEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLarge: Bool { family == .systemLarge }
    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        if let snapshot = entry.snapshot {
            switch AingWidgetLimitsState(snapshot: snapshot, at: entry.date) {
            case .limits(let limits):
                content(limits, snapshot: snapshot)
            case .noProviders:
                message(AingWidgetText.limitsNoProviders, characterID: snapshot.resolvedCharacterID)
            case .noData:
                message(AingWidgetText.limitsNoData, characterID: snapshot.resolvedCharacterID)
            }
        } else {
            AingWidgetSignedOut(family: family, hint: isSmall ? nil : AingWidgetText.limitsSignedOutHint)
        }
    }

    private func message(_ text: String, characterID: String) -> some View {
        AingWidgetEmptyState(
            characterID: characterID, mood: .plain, expression: nil, title: text, hint: nil,
            layout: isSmall ? .stacked : .row, portraitSize: isSmall ? 52 : (isLarge ? 96 : 72)
        )
    }

    @ViewBuilder
    private func content(_ limits: AingWidgetLimits, snapshot: WidgetSnapshot) -> some View {
        if isSmall {
            small(limits, snapshot: snapshot)
        } else {
            wide(limits, snapshot: snapshot)
        }
    }

    // MARK: S — 가장 임박한 하나

    /// S: [로고] 이름 → **창 라벨** → 큰 % → 막대 → 캡션("주간 60% · 2시간 뒤 초기화").
    /// 한 칸에 한 제공자만 세우므로 **어느 제공자의 어느 창인지**가 숫자보다 먼저 와야 한다.
    @ViewBuilder
    private func small(_ limits: AingWidgetLimits, snapshot: WidgetSnapshot) -> some View {
        let ink = AingWidgetInk(renderingMode)
        if let row = limits.mostUrgent, let primary = row.primaryWindow {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    AingWidgetProviderBadge(provider: row.provider, size: AingWidgetLayout.limitTileSize)
                    Text(row.name)
                        .aingFont(13, .semibold, relativeTo: .footnote)
                        .foregroundStyle(ink.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityHidden(true)
                Text(primary.label)
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .padding(.top, 8)
                AingWidgetBigNumber(text: primary.display.valueText)
                Spacer(minLength: 0)
                AingWidgetBar(progress: barProgress(primary.display), isComplete: false, height: 6)
                    .padding(.bottom, 5)
                AingWidgetCaption(text: smallCaption(row, primary: primary))
                    .padding(.bottom, -4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(AingWidgetText.limitsTitle))
            .accessibilityValue(Text("\(row.name) \(spokenAll(row))"))
        } else {
            // 창이 하나도 없는 줄만 남았다 — 그릴 숫자가 없으니 '연동 없음'과 같은 안내로 선다.
            message(AingWidgetText.limitsNoProviders, characterID: snapshot.resolvedCharacterID)
        }
    }

    // MARK: M · L — 세 줄(L 은 토큰 줄까지)

    private func wide(_ limits: AingWidgetLimits, snapshot: WidgetSnapshot) -> some View {
        let rows = limits.shown(limit: isLarge ? AingWidgetLayout.limitRowsLarge : AingWidgetLayout.limitRowsMedium)
        return VStack(alignment: .leading, spacing: 0) {
            header(snapshot: snapshot)
            VStack(alignment: .leading, spacing: isLarge ? 14 : 8) {
                ForEach(rows) { row in
                    providerRow(row)
                }
            }
            .padding(.top, isLarge ? 8 : 6)
            Spacer(minLength: 0)
            if isLarge, limits.hasTokens {
                tokenBlock(limits)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(snapshot: WidgetSnapshot) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(AingWidgetText.limitsTitle)
                .aingFont(isLarge ? 17 : 15, .bold, relativeTo: isLarge ? .headline : .subheadline)
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            Text(AingWidgetFormat.ago(from: snapshot.generatedAt, now: entry.date))
                .monospacedDigit()
                .aingFont(11, relativeTo: .caption2)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// 줄: [로고] 이름 (리셋 캡션) … [창 라벨] % / 대표 창 굵은 막대 / (L · 두 창 다 있을 때만) 주간 얇은 막대.
    private func providerRow(_ row: AingWidgetLimitRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // 큰 글자에서 한 줄에 안 들어가면 **리셋 캡션을 뺀다**(이름·창 라벨·숫자가 먼저다 — 말줄임 대신 조각 빼기).
            ViewThatFits(in: .horizontal) {
                titleLine(row, showsCaption: true)
                titleLine(row, showsCaption: false)
            }
            if let primary = row.primaryWindow {
                AingWidgetBar(progress: barProgress(primary.display), isComplete: false, height: isLarge ? 6 : 5)
            }
            // 주간이 이미 대표로 섰으면(5시간 창이 없는 요금제) 같은 값을 두 번 그리지 않는다.
            if isLarge, let weekly = row.secondaryWeekly {
                weeklyLine(weekly)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.name))
        .accessibilityValue(Text(spokenAll(row)))
    }

    private func titleLine(_ row: AingWidgetLimitRow, showsCaption: Bool) -> some View {
        let ink = AingWidgetInk(renderingMode)
        let primary = row.primaryWindow
        return HStack(alignment: .center, spacing: 7) {
            AingWidgetProviderBadge(provider: row.provider, size: AingWidgetLayout.limitTileSize)
            Text(row.name)
                .aingFont(isLarge ? 15 : 14, .semibold, relativeTo: .subheadline)
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                .fixedSize(horizontal: showsCaption, vertical: false)
            if showsCaption, let primary, let text = rowCaption(primary.display) {
                Text(text)
                    .monospacedDigit()
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if let primary {
                // ★ 창 라벨은 **빼지 않는다**. 라벨 없이 숫자만 세우면 주간 8% 가 5시간 27% 옆에 나란히 서서
                //   같은 창으로 읽힌다(실제 렌더에서 잡은 결함 — 세 제공자의 창 구성이 서로 다르다).
                Text(primary.label)
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Text(primary.display.valueText)
                    .monospacedDigit()
                    .aingFont(isLarge ? 16 : 15, .bold, relativeTo: .subheadline)
                    .foregroundStyle(ink.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// 주간은 얇은 막대 + 작은 라벨·값(L 만 — M 칸에는 세 줄이 들어갈 자리가 없다).
    private func weeklyLine(_ weekly: AILimitDisplay) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(AingWidgetText.limitsWeekly)
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(ink.secondary)
                Spacer(minLength: 4)
                Text(weekly.valueText)
                    .monospacedDigit()
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(ink.secondary)
                    .fixedSize()
            }
            AingWidgetBar(progress: barProgress(weekly), isComplete: false, height: 3)
        }
        .padding(.leading, AingWidgetLayout.limitTileSize + 7)
    }

    /// L 아래 줄: 기존 **토큰 축**(우리가 센 누적 개수). 리밋과 다른 축이라 구분선 아래에 두고 막대를 쓰지 않는다 —
    /// 토큰에는 분모가 없다(잔디의 하루 5천만은 농도 눈금이고 한도가 아니다).
    @ViewBuilder
    private func tokenBlock(_ limits: AingWidgetLimits) -> some View {
        let ink = AingWidgetInk(renderingMode)
        if let today = limits.todayTokens {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(ink.separator)
                    .frame(height: 0.5)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AingWidgetText.limitsTokenTitle)
                        .aingFont(12, .semibold, relativeTo: .caption)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    tokenValue(AingWidgetText.limitsTokenToday, value: today)
                    if let recent = limits.recentTokens {
                        tokenValue(AingWidgetText.limitsTokenRecent, value: recent)
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, -2)
            .accessibilityElement(children: .combine)
        }
    }

    private func tokenValue(_ label: String, value: Int) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return HStack(spacing: 4) {
            Text(label)
                .aingFont(11, relativeTo: .caption2)
                .foregroundStyle(ink.secondary)
            Text(AingWidgetLimitFormat.tokens(value))
                .monospacedDigit()
                .aingFont(13, .bold, relativeTo: .footnote)
                .foregroundStyle(ink.primary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: 값 다듬기(계산은 코어 규칙 · 여기는 고르기만)


    /// 막대 채우기. 판정 불가(`percent == nil`)면 **0** — 빈 트랙만 남는다(0% 로 "안 썼다"고 말하지 않는다.
    /// 숫자 자리에는 규칙이 이미 `—` 를 세워 두었다).
    private func barProgress(_ display: AILimitDisplay) -> Double {
        guard let percent = display.percent else { return 0 }
        return percent / 100
    }

    /// S 의 아래 줄: "주간 60% · 2시간 뒤 초기화". 큰 숫자가 5시간이면 주간을 여기서 한 번 말해 둘 다 보이게 하고
    /// (2026-10-07 사용자 결정 "둘 다"), 리셋이 남아 있으면 투영한 글자를, 아니면 규칙이 만든 나이 캡션을 잇는다.
    private func smallCaption(_ row: AingWidgetLimitRow, primary: (display: AILimitDisplay, label: String)) -> String {
        let weekly = row.secondaryWeekly.map { "\(AingWidgetText.limitsWeekly) \($0.valueText)" }
        let tail = AingWidgetLimitFormat.resetIn(primary.display.resetsAt, now: entry.date) ?? primary.display.captionText
        return AingWidgetText.joined([weekly, tail])
    }

    /// M·L 줄의 작은 글자. 같은 규칙인데 자리가 좁아 둘 중 하나만 — 리셋이 더 쓸모 있다(나이는 머리의 "2분 전"이 말한다).
    private func rowCaption(_ display: AILimitDisplay) -> String? {
        AingWidgetLimitFormat.resetIn(display.resetsAt, now: entry.date)
            ?? (display.freshness.isResetClaim ? display.captionText : nil)
    }

    /// 보이스오버: 창마다 한 문장(라벨 + 값) + 나이. 막대는 숨기고 이 한 줄이 줄 전체를 말한다.
    private func spokenAll(_ row: AingWidgetLimitRow) -> String {
        var parts: [String] = []
        if let five = row.fiveHour { parts.append("\(AingWidgetText.limitsFiveHour) \(five.valueText)") }
        if let weekly = row.weekly { parts.append("\(AingWidgetText.limitsWeekly) \(weekly.valueText)") }
        if let age = row.primaryWindow?.display.captionText { parts.append(age) }
        return parts.joined(separator: ", ")
    }
}

/// 제공자 표식. **모드마다 다른 것을 그린다**:
///  · 원색: 브랜드색 라운드 사각 + 흰 마크(`AIProviderTile` — 맥 카드·폰 카드와 같은 뷰).
///  · 틴트·투명: 시스템이 색을 버리므로 타일은 단색 덩어리가 되고 그 안의 흰 마크가 **사라진다**.
///    그래서 타일을 걷고 **로고 실루엣만** 남긴다(세 제공자가 모양으로 갈린다). 이름 글자는 호출부가 옆에 세운다.
struct AingWidgetProviderBadge: View {
    let provider: AILimitProvider
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .accented {
            AIProviderMark(provider)
                .fill(Color.white)
                .frame(width: size * 0.92, height: size * 0.92)
                .frame(width: size, height: size)
                .widgetAccentable()
                .accessibilityHidden(true)
        } else {
            AIProviderTile(provider: provider, size: size)
        }
    }
}
#endif
