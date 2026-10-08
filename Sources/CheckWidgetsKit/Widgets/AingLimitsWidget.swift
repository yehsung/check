#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI
import WidgetKit

// MARK: - 「AI 리밋」 위젯 (v0.3.46 — **미디움 한 칸뿐** · 두 열이 나란히)
//
// 그리는 값은 전부 `AingWidgetModel.swift`(플랫폼 무관 — 테스트 대상)에서 오고, 이 파일은 배치만 한다.
// 네트워크 없음 · 토큰 읽기 없음: 앱이 쓴 App Group 스냅샷(`WidgetSnapshot.aiLimits`)만 그린다.
//
// ## 왜 스몰·라지가 없나 (2026-10-06 사용자 지시)
// *"스몰과 라지 버전 다 없애고. 미디움 버전만 똑바로 만들어."*
//  · 스몰은 한 제공자만 세웠다 — 그래서 "어느 제공자의 어느 창인지"를 숫자보다 먼저 말해야 했고,
//    그 문법은 승인된 **두 열 나란히**와 어긋난다(한 칸에 열이 하나면 열 머리를 둘 적을 수 없다).
//  · 라지는 미디움과 **같은 세 줄**을 띄워 놓아 아래가 비었다.
// `supportedFamilies` 는 `[.systemMedium]` 하나이고, 이 파일에는 **크기 분기가 한 줄도 없다** —
// 죽은 분기는 다음 사람을 속인다. 위젯은 아직 출시 전이라(iOS 1.0.3/build 13 에 없다) 이미 추가한 사용자가
// 없고 마이그레이션 걱정도 없다.
//
// ## 승인된 문법 (맥 팝오버·폰 카드와 **같은 문법 · 다른 예산**)
// ① 한 제공자 = 한 줄, 5시간과 주간이 그 줄 안에 **나란히**(세로로 쌓지 않는다).
// ② 열 머리(`5시간` / `주간`)는 맨 위에 **한 번만**.
// ③ 짝 단서 셋 — 열 머리 글자 · 색 · 좌우 자리.
// ④ 제공자 사이 1px 구분선(칸 안쪽 여백 **바깥까지**).
// ⑤ 그 창이 **없는** 제공자는 그 칸을 `없음` 으로 비운다(`—` 는 '못 읽었다'라 다른 말이다).
// ⑥ 퍼센트는 tabular-nums · 오른쪽 정렬 · 고정폭 칸.
// ⑦ 맨 아래 **토큰 한 줄**(구분선 위) — 리밋과 다른 축이라 막대를 쓰지 않는다. 토큰에는 분모가 없다.
// 위젯은 이름을 쓰고 요금제는 생략한다(왼쪽 92pt 칸에 [마크 20][이름]). 폭 숫자는 전부
// `AingWidgetLimitsMediumBudget` 에 있다 — 이 파일은 `#if os(iOS)` 라 맥 스위트가 한 줄도 컴파일하지 않는다.
//
// ## 이 파일이 지키는 규칙 넷
// 1. **막대만 쓴다.** 링·도넛 게이지(`trim(from:)`)는 틴트·투명 모드에서 트랙과 채움이 한 색이 되어 62%가 꽉 찬
//    원으로 보인다(w11 실측 — 그래서 저장소가 소스 계약으로 금지한다).
// 2. **색으로만 가르지 않는다.** `widgetRenderingMode == .accented` 는 색을 통째로 버린다. 그 모드에서
//    제공자는 **로고 실루엣**이, 두 열은 **열 머리 글자 + 좌우 자리**가 가른다(`AingWidgetLimitInk` 머리말).
// 3. **절대 시각을 투영한다.** 스냅샷에는 `resetsAt`(절대)만 있고 "남은 시간"은 칸 시각으로 여기서 만든다 —
//    남은 초를 스냅샷에 실으면 쓰기 창구의 중복 제거가 무력화돼 60초마다 파일을 다시 쓴다.
// 4. **경고 기호를 쓰지 않는다**(`exclamationmark`). 리밋이 90%인 것은 고장이 아니다 — 숫자 색이 말한다.
//
// ## 맥 두 대 이상이면 **메인 맥 하나**만 그린다 (v0.3.47)
// 서버는 기기별로 저장하고 폰 카드는 맥마다 묶어 전부 그린다. 미디움 칸은 그럴 자리가 없다 —
// 170pt 에 줄 셋이면 이미 꽉 차는데 맥 두 대 × 제공자 셋이면 여섯 줄이다. 그래서 **앱이 한 대를 골라**
// (`AILimitMainDeviceRule` — 고른 맥이 없으면 가장 최근에 일한 맥) 그 맥의 줄만 패널에 싣고, 머리에 그 맥
// 이름을 적는다. 위젯은 고르지 않는다: 고르는 규칙과 `ai_limits_prefs` 를 아는 쪽은 앱이고, 위젯이 같은
// 판단을 따로 하면 두 벌이 갈린 채 한동안 산다(확장은 앱과 따로 갱신된다).
// ★ **맥이 한 대면 이름을 적지 않는다**(`deviceName` nil) — 혼자 쓰는 사람의 위젯은 0.3.46 과 똑같다.
// ★ 토큰 줄은 **계정 전체의 합** 그대로다(합산 유지 — 리밋만 메인 맥을 따른다). 그래서 그 줄에는 맥 이름이 없다.
//
// ## 두 빈 상태를 섞지 않는다
// `noData`("앱을 열면 채워져요")와 `noProviders`(`AILimitSurfaceText.noVisibleProviders` — 맥에서 연동·보기
// 설정을 가리킨다)는 사용자가 할 일이 다르다. 하나로 합치면 맥을 안 쓰는 사람이 앱만 몇 번이고 열게 된다.
// ★ `noProviders` 의 문장에 "로그인하면" 만 적지 마라(v0.3.47): 맥 설정에서 **끈** 사람은 이미 로그인해 있고,
//   위젯은 둘을 가릴 수 없다(패널에 비워진 행이 실리지 않는다 — 근거는 `AILimitSurfaceText` 머리말).

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
            AingLimitsContainer {
                AingAILimitsContent(entry: entry)
            }
        }
        .configurationDisplayName(AingWidgetText.limitsGalleryName)
        .description(AingWidgetText.limitsGalleryDescription)
        // ★ 미디움 **하나**. 늘리기 전에 이 파일 머리말을 읽어라 — 크기마다 다른 문법이 필요하다.
        .supportedFamilies([.systemMedium])
    }
}

/// 공통 껍데기(다른 위젯의 `AingWidgetContainer` 와 같은 일 — 링크 목적지만 나 탭이다).
/// 크기 분기가 없으므로 `family` 를 들고 다니지 않는다.
private struct AingLimitsContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .widgetURL(AingLimitsLinks.me)
            .containerBackground(for: .widget) { AingWidgetColors.background }
    }
}

// MARK: - 본문

struct AingAILimitsContent: View {
    let entry: AingWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

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
            AingWidgetSignedOut(family: .systemMedium, hint: AingWidgetText.limitsSignedOutHint)
        }
    }

    private func message(_ text: String, characterID: String) -> some View {
        AingWidgetEmptyState(
            characterID: characterID, mood: .plain, expression: nil, title: text, hint: nil,
            layout: .row, portraitSize: 72
        )
    }

    @ViewBuilder
    private func content(_ limits: AingWidgetLimits, snapshot: WidgetSnapshot) -> some View {
        let rows = limits.shown(limit: AingWidgetLayout.limitRowsMedium).filter(\.hasAnyWindow)
        if rows.isEmpty {
            // 그릴 숫자가 하나도 없다 — '연동 없음'과 같은 안내로 선다(0% 로 지어내지 않는다).
            message(AingWidgetText.limitsNoProviders, characterID: snapshot.resolvedCharacterID)
        } else {
            // ★ 예산은 **이 기기의 칸 크기**로 만든다. 기준 칸(364×170)만 믿으면 375pt 기기(329×155 —
            //   안쪽 123pt)에서 세 줄 + 토큰 줄이 칸을 넘겨 마크가 조용히 압축된다.
            GeometryReader { proxy in
                let budget = AingWidgetLimitsMediumBudget(
                    innerWidth: proxy.size.width, innerHeight: proxy.size.height,
                    providerCount: rows.count, hasTokens: limits.hasTokens
                )
                VStack(alignment: .leading, spacing: 0) {
                    header(limits)
                    columnHeaderRow
                    // ★ 줄들이 **남는 높이를 나눠 갖는다**: 제공자가 하나·둘뿐인 사람도 아래가 통째로 비지 않는다
                    //   (라지가 그래서 못생겼다 — `AingWidgetLimitsMediumBudget` 머리말).
                    //   높이를 못 박지 않고 `maxHeight: .infinity` 로 나누는 까닭: 예산의 `rowHeight` 는
                    //   마크·바 크기를 고르는 데 쓰고, 1pt 미만의 나머지는 SwiftUI 가 정확히 나눠 준다.
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { rowSeparator }
                            providerRow(row, budget: budget)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    if limits.hasTokens {
                        tokenBlock(limits)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    /// 머리: 제목 + **메인 맥 이름**(맥 두 대 이상) + **리밋 관측 나이**.
    ///
    /// ★ 나이는 `snapshot.generatedAt` 이 아니다(v0.3.45 P2). 그 값은 **폰이 파일을 쓴 시각**이고
    /// `NowStore.touchWidgetSnapshot` 이 리밋이 안 바뀌어도 60초마다 '지금'으로 옮긴다 — 맥이 몇 시간
    /// 자고 있어도 머리는 '방금'이라고 적었다. 리밋 위젯이 지평 밖 칸을 깐 근거가 "헤더의 N분 전도 얼어
    /// 낡음을 알릴 수단이 멈춘다" 였는데, **그 수단은 애초에 리밋의 나이를 말한 적이 없었다.**
    /// 그래서 이 머리만 **가장 낡은 보이는 줄의 관측 시각**으로 센다(다른 세 위젯의 머리는 그대로다 —
    /// 그들이 그리는 것은 '우리 서버가 센 사실'이라 스냅샷을 만든 시각이 맞는 기준이다).
    private func header(_ limits: AingWidgetLimits) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return HStack(alignment: .firstTextBaseline, spacing: AingWidgetLimitsMediumBudget.headerItemGap) {
            Text(AingWidgetText.limitsTitle)
                .aingFont(15, .bold, relativeTo: .subheadline)
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            // ★ 메인 맥 이름(맥이 **두 대 이상일 때만** 들어온다 — 한 대면 nil 이라 지금과 똑같이 보인다).
            //   자리는 머리 줄 안이고 세로를 하나도 더 쓰지 않는다. 그 선택의 실측 근거는
            //   `AingWidgetLimitsMediumBudget` §머리 줄의 기기 이름(좁은 기기에서 이름 자리 194.4pt).
            //   ★ **적을지 말지는 뷰가 정하지 않는다** — `AingWidgetLimits.headerDevice` 가 값으로 답한다
            //     (뷰는 맥 스위트가 한 줄도 컴파일하지 않아서 그 분기를 재는 그물이 grep 하나뿐이 된다).
            //   ★ **말줄임이 나는 쪽이 이 글자다**: 나이 글자는 `fixedSize()` 로, 제목은 짧아서 버틴다 —
            //     이름은 사람이 적은 값이라 앞부분도 그 맥을 가리킨다(숫자를 줄이는 것과 다르다).
            if let header = limits.headerDevice {
                Text(header.text)
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // 가운뎃점은 **보이는 글자**일 뿐이다 — 소리로 읽으면 이름의 일부처럼 들린다.
                    .accessibilityLabel(Text(header.spoken))
            }
            Spacer(minLength: AingWidgetLimitsMediumBudget.headerMinGap)
            if let age = limits.observationAgeText(now: entry.date) {
                Text(age)
                    .monospacedDigit()
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        // ★ **최소** 높이다. 기본 글자 크기에서는 예산(18pt)과 정확히 같고, 글자를 키운 사람에게는 머리가
        //   조금 자라고 줄들이 그만큼 줄어든다 — 고정 높이로 못 박으면 그 사람의 머리 글자가 아래 줄을 덮는다.
        .frame(minHeight: AingWidgetLimitsMediumBudget.headerHeight, alignment: .leading)
    }

    /// 열 머리 줄. **데이터 줄과 같은 격자**를 쓴다 — 왼쪽 칸을 비우고, 두 머리 칸이 `maxWidth: .infinity` 로
    /// 남는 폭을 **똑같이** 나눠 가진다. 데이터 줄의 두 칸(바 + 간격 + 숫자)도 같은 몫을 받으므로 머리 글자의
    /// 오른쪽 끝이 자기 열 숫자 칸의 오른쪽 끝과 **구조적으로** 맞는다(기기마다 칸 폭이 달라 간격을 상수로
    /// 적을 수 없다).
    ///
    /// ★ 이 줄은 **어느 렌더링 모드에서나 그린다**. 틴트·투명에서는 색이 사라지므로 두 열을 가르는 단서가
    ///   머리 글자와 좌우 자리뿐이다 — 여기서 머리를 빼면 단서가 자리 하나로 줄어든다.
    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0).frame(
                width: AingWidgetLimitsMediumBudget.nameColumnWidth + AingWidgetLimitsMediumBudget.nameGap
            )
            columnHeader(.fiveHour, label: AingWidgetText.limitsFiveHour)
            Spacer(minLength: 0).frame(width: AingWidgetLimitsMediumBudget.columnGap)
            columnHeader(.weekly, label: AingWidgetText.limitsWeekly)
        }
        .padding(.top, AingWidgetLimitsMediumBudget.headerGap)
        .accessibilityHidden(true)
    }

    private func columnHeader(_ window: AILimitWindow, label: String) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(label)
                .aingFont(11, .semibold, relativeTo: .caption2)
                // ★ 열 머리 글자를 **그 열의 색으로 물들인다**(틴트에서는 시스템이 걷어내 흰 글자가 된다).
                .foregroundStyle(AingWidgetLimitColors.header(window, mode: renderingMode))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 제공자 사이 구분선. 칸 안쪽 여백 **바깥까지** 긋는다(승인된 문법 ④) — 그래서 음수 여백이다.
    private var rowSeparator: some View {
        Rectangle()
            .fill(AingWidgetLimitColors.separator(mode: renderingMode))
            .frame(height: AingWidgetLimitsMediumBudget.separatorHeight)
            .padding(.horizontal, -AingWidgetLimitsMediumBudget.contentMargin)
            .accessibilityHidden(true)
    }

    /// 줄: `[마크 이름][5시간 바 %][주간 바 %]`.
    private func providerRow(_ row: AingWidgetLimitRow, budget: AingWidgetLimitsMediumBudget) -> some View {
        HStack(alignment: .center, spacing: 0) {
            nameColumn(row, markSide: budget.markSide)
                .frame(width: AingWidgetLimitsMediumBudget.nameColumnWidth, alignment: .leading)
            Spacer(minLength: 0).frame(width: AingWidgetLimitsMediumBudget.nameGap)
            cell(row, .fiveHour, barHeight: budget.barHeight)
            Spacer(minLength: 0).frame(width: AingWidgetLimitsMediumBudget.columnGap)
            cell(row, .weekly, barHeight: budget.barHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.name))
        .accessibilityValue(Text(spokenAll(row)))
    }

    /// 왼쪽 고정 칸: [마크][이름]. 요금제는 쓰지 않는다(승인된 문법 — 위젯은 이름까지).
    private func nameColumn(_ row: AingWidgetLimitRow, markSide: Double) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return HStack(spacing: AingWidgetLimitsMediumBudget.markGap) {
            AingWidgetProviderBadge(provider: row.provider, size: markSide)
            Text(row.name)
                .aingFont(12, .semibold, relativeTo: .footnote)
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                // 글자 크기를 올린 사람도 이름이 **잘리지 않게** — 말줄임 대신 줄여서 넣는다.
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    /// 한 칸 = 바 + 숫자. 세 모양이 있다:
    ///  ① 값이 있다 → 트랙 + 채움(열 색, 하한이면 흐리게) + `27%` / `27% 이상` / `0%`
    ///  ② 창은 있는데 판정 불가(기기 시계 어긋남) → 트랙만 + `—`(코어 규칙의 글자)
    ///  ③ **그 창이 없다** → 더 조용한 트랙만 + `없음`
    /// ②와 ③을 같은 글자로 그리지 않는 이유는 파일 머리말 ⑤에 있다.
    private func cell(_ row: AingWidgetLimitRow, _ window: AILimitWindow, barHeight: Double) -> some View {
        let display = row.display(window)
        return HStack(spacing: AingWidgetLimitsMediumBudget.barValueGap) {
            AingWidgetLimitBar(
                percent: display?.percent,
                floorOnly: display?.floorOnly ?? false,
                window: window,
                isAbsent: display == nil,
                height: barHeight
            )
            .frame(maxWidth: .infinity)
            Text(display?.valueText ?? AILimitColumnText.absentValueText)
                // tabular-nums. 숫자 폭이 글리프마다 다르면 세 줄의 `%` 가 들쭉날쭉해 자릿수를 오독한다.
                .monospacedDigit()
                .aingFont(12, .bold, relativeTo: .footnote)
                .foregroundStyle(AingWidgetLimitColors.value(display?.percent, isAbsent: display == nil,
                                                             mode: renderingMode))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // 오른쪽 정렬 · 고정 칸(승인된 문법 ⑥).
                .frame(width: AingWidgetLimitsMediumBudget.valueWidth, alignment: .trailing)
        }
    }

    /// 맨 아래 줄: 기존 **토큰 축**(우리가 센 누적 개수). 리밋과 다른 축이라 구분선 아래에 두고 막대를 쓰지 않는다 —
    /// 토큰에는 분모가 없다(잔디의 하루 5천만은 농도 눈금이고 한도가 아니다).
    @ViewBuilder
    private func tokenBlock(_ limits: AingWidgetLimits) -> some View {
        let ink = AingWidgetInk(renderingMode)
        if let today = limits.todayTokens {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(ink.separator)
                    .frame(height: 0.5)
                    .padding(.horizontal, -AingWidgetLimitsMediumBudget.contentMargin)
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
            .padding(.top, 7)
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

    /// 보이스오버: 창마다 한 문장(라벨 + 값), 없는 창도 말한다 + 나이. 막대는 숨기고 이 한 줄이 줄 전체를 말한다.
    private func spokenAll(_ row: AingWidgetLimitRow) -> String {
        var parts: [String] = []
        for (window, label) in [(AILimitWindow.fiveHour, AingWidgetText.limitsFiveHour),
                                (AILimitWindow.weekly, AingWidgetText.limitsWeekly)] {
            let value = row.display(window)?.valueText ?? AILimitColumnText.absentValueText
            parts.append("\(label) \(value)")
        }
        if let age = row.display(.fiveHour)?.captionText ?? row.display(.weekly)?.captionText { parts.append(age) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - 바

/// 리밋 진행바. 트랙 + 채움 두 장(링 금지 — 파일 머리말 1).
///
/// `percent` 가 nil 이면(판정 불가 · 창 없음) **트랙만** 그린다 — 0% 로 그리면 "하나도 안 썼다"는 거짓이다.
/// 하한("27% 이상")은 채움을 **흐리게** 그린다(수단은 색이 아니라 불투명도 — 틴트·투명은 색을 통째로 버린다).
///
/// 왜 공용 `AingWidgetBar` 를 안 쓰나: 그 부품은 채움이 두 색(달성 초록 / 강조 파랑) 가운데 하나고 트랙이
/// 한 가지다. 이 칸은 **열 색**과 **두 종류의 트랙**(빈 칸 / 창이 없는 칸)이 필요하고, 좁은 바(26~44pt)라
/// 최소 채움 산식도 다르다. 공용 부품에 그 입력을 더하면 리밋과 무관한 다른 세 위젯의 막대가 같이 흔들린다.
struct AingWidgetLimitBar: View {
    /// 0…100. nil = 모른다 / 그 창이 없다(채움 없음).
    let percent: Double?
    let floorOnly: Bool
    let window: AILimitWindow
    /// 그 창이 **아예 없다**(= 트랙을 더 조용하게). 판정 불가(`percent == nil`)와 **다른 사실**이다.
    let isAbsent: Bool
    let height: Double
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AingWidgetLimitColors.track(isAbsent: isAbsent, mode: renderingMode))
                if percent != nil {
                    Capsule()
                        .fill(AingWidgetLimitColors.bar(window, mode: renderingMode))
                        .opacity(AILimitFloorFill.opacity(floorOnly: floorOnly))
                        // 채움 폭 산식은 **폰·위젯·맥이 한 벌**이다(좁은 바에서 1% 와 18% 가 같은 길이가 되지 않게).
                        .frame(width: AILimitBarFill.width(barWidth: proxy.size.width, percent: percent))
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - 열 색 (숫자는 공유 팔레트 하나 — 폰 카드와 같은 값)

/// 두 열의 색. **숫자는 `AILimitColumnPalette`(CheckMobileShared) 한 곳에 있다** — 위젯 확장은 폰 앱 모듈을
/// 링크하지 않으므로(Package.swift) 색을 두 벌로 적으면 같은 데이터가 폰과 위젯에서 다른 색으로 보인다.
///
/// ★ 틴트·투명(`.accented`)에서는 **열 색을 쓰지 않는다**. 시스템이 색을 통째로 버리므로 쓰려 해도 못 쓰고,
///   그 모드에서 두 열을 가르는 것은 열 머리 글자와 좌우 자리다(`AingWidgetLimitInk` 머리말).
enum AingWidgetLimitColors {
    static func bar(_ window: AILimitWindow, mode: WidgetRenderingMode) -> Color {
        switch AingWidgetLimitInk.bar(window: window, accented: mode == .accented) {
        case .accentedWhite: return .white
        case .column(let column): return color(AILimitColumnPalette.bar(column))
        }
    }

    static func header(_ window: AILimitWindow, mode: WidgetRenderingMode) -> Color {
        switch AingWidgetLimitInk.bar(window: window, accented: mode == .accented) {
        // 틴트에서는 머리 글자도 흰색이다 — 글자 자체(`5시간` / `주간`)가 짝을 말한다.
        case .accentedWhite: return AingWidgetInk(mode).secondary
        case .column(let column): return color(AILimitColumnPalette.header(column))
        }
    }

    /// 트랙. 창이 **없는** 칸은 더 조용하다(빈 트랙과 같은 밝기면 "0% 라 비었다"로 읽힌다).
    static func track(isAbsent: Bool, mode: WidgetRenderingMode) -> Color {
        if mode == .accented {
            let opacity = AingWidgetPalette.Accented.track
            return .white.opacity(isAbsent ? opacity * 0.5 : opacity)
        }
        return color(isAbsent ? AILimitColumnPalette.absentTrack : AILimitColumnPalette.emptyTrack)
    }

    static func separator(mode: WidgetRenderingMode) -> Color {
        mode == .accented ? AingWidgetInk(mode).separator : color(AILimitColumnPalette.separator)
    }

    /// 숫자 글자. **사용량 단계는 이 글자가 말한다**(바는 열 색을 쥐었다 — `AILimitUsageStage` 머리말).
    /// 틴트·투명에서는 색이 없으므로 단계가 사라진다 — 그 모드의 신호는 숫자 자체다(시스템 제약이다).
    static func value(_ percent: Double?, isAbsent: Bool, mode: WidgetRenderingMode) -> Color {
        let ink = AingWidgetInk(mode)
        if mode == .accented { return isAbsent ? ink.tertiaryText : ink.primary }
        if isAbsent { return color(AILimitColumnPalette.absentText) }
        switch AILimitUsageStage.stage(wholePercent: percent.map(AILimitFreshnessRule.wholePercent)) {
        case .calm: return AingWidgetColors.primary
        case .warn: return AingWidgetColors.pending
        case .danger: return AingWidgetColors.danger
        }
    }

    private static func color(_ pair: AILimitColumnPalette.Pair) -> Color {
        let light = ui(pair.light), dark = ui(pair.dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func ui(_ hex: UInt32) -> UIColor {
        let c = AILimitColumnPalette.components(hex)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
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
