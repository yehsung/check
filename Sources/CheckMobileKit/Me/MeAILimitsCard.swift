#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 나 탭 「AI 리밋」 카드 (v0.3.46 — 승인된 문법: 한 제공자 = 한 줄, 두 열이 나란히)
//
// 카드 경계 = **시간 범위 하나**라는 이 탭의 규칙(MeRecordsViews 머리말)에 리밋은 들어맞지 않는다 — 5시간 창과
// 주간 창이 한 제공자 안에 같이 있다. 그래서 범위가 아니라 **축**으로 카드를 가른다: 이 카드는 "지금 내 AI 한도"
// 하나를 말하고, 아래 토큰 줄은 같은 도구의 **다른 축**(우리가 센 누적)이라 구분선 밑에 둔다. 두 축을 한 바에
// 섞지 않는 것이 이 카드의 가장 중요한 규칙이다(`AILimits.swift` 머리말).
//
// ## 승인된 문법 (2026-10-07 — 맥 팝오버·위젯 미디움과 **같은 문법**)
// ① 한 제공자 = 한 줄. 5시간과 주간이 그 줄 안에 **나란히** 선다(세로로 쌓지 않는다).
//    쌓으면 제공자 셋에 줄이 여섯이 되고, 무엇보다 "지금 막히나(5시간) · 이번 주가 위험한가(주간)"는
//    **나란히 놓고 견주는** 질문이다.
// ② 열 머리(`5시간` / `주간`)는 카드 맨 위에 **한 번만**. 줄마다 반복하지 않는다.
// ③ 짝을 알려 주는 단서를 **셋** 둔다 — 열 머리 글자 · 색 · 좌우 자리. 하나로는 부족한 이유가 각각 있다:
//    색만으로 가르면 색을 버리는 표면(위젯 틴트 모드)·색각 이상·흑백 스크린샷에서 두 숫자가 구별되지 않고,
//    자리만으로 가르면 열 머리를 한 번만 적는 이 배치에서 스크롤 중에 기준을 잃고, 글자만으로 가르면
//    (`5시간 88%`) 폭이 모자라 말줄임이 나는데 이 자리에서 말줄임은 **숫자 자릿수 오독**이다.
// ④ 제공자 사이 1px 구분선. 카드 안쪽 여백 **바깥까지** 긋는다 — 안쪽에서 끊으면 줄이 '카드 안의 또 다른
//    카드'처럼 보이고 세 줄이 한 표라는 사실이 흐려진다.
// ⑤ 5시간 창이 **없는** 제공자는 그 칸을 `없음` 으로 비운다. ★ `—` 를 쓰지 않는다 — 그 글자는 코어 규칙이
//    '판정 불가(= 못 읽었다)'로 못 박았다(`AILimitFreshnessRule.unknownValueText`). 그 둘은 다른 사실이다.
// ⑥ 퍼센트는 tabular-nums · 오른쪽 정렬 · **고정폭 칸**(`MeAILimitCardBudget.valueWidth`).
//
// ## 폰은 이름과 요금제를 **둘 다** 쓴다 (맥과 다른 예산)
// 맥 팝오버는 안쪽이 292pt 뿐이라 이름을 넣으면 바가 각 60pt 로 줄어, 이름을 버리고 호버 툴팁으로 갚았다.
// 폰 카드는 ~361pt 라 자리가 남는다: 왼쪽 **108pt 고정 칸**에 [마크 26pt][이름 / 요금제 2줄] 을 넣고,
// 그 고정 폭이 **세 줄의 바 시작점을 가지런히** 맞춘다. 폰에는 호버가 없으므로(툴팁을 걸 자리가 없다)
// 이름·요금제는 화면에 있어야 한다.
//
// ## 숫자·캡션·표시여부를 뷰가 계산하지 않는다
// 전부 `AILimitsStore.displayRows`(코어 규칙 `AILimitFreshnessRule` 이 만든 `AILimitDisplay`)에서 온다.
// 이 파일은 퍼센트를 다시 반올림하지도, 나이를 다시 세지도, "이상"을 붙이지도 않는다 — 그 순간 규칙이 둘이 되고,
// 뷰만 고친 화면은 스토어 테스트가 초록인 채 거짓을 그린다(관례: '클라 게이트는 짝으로 있다').
//
// ## 가로 예산은 뷰 밖에 있다
// 폭 숫자는 전부 `MeAILimitCardBudget`(`MeAILimitsLayout.swift`)이다. 이 뷰는 `#if os(iOS)` 라 맥 스위트가
// 한 줄도 컴파일하지 않으므로, 숫자를 뷰 안에 적으면 **그물이 하나도 없다**(관례: '폰 뷰는 맥 스위트가 못 본다').
//
// 숨기기 규칙(2026-10-07 사용자 결정): 미연동 제공자는 줄을 만들지 않고, 하나도 없으면 안내 한 줄만 둔다.
// 설정 토글도 알림도 없다 — 사용자가 맥에서 그 도구에 로그인하면 저절로 나타난다.

/// 「AI 리밋」 카드. 제목 · 열 머리 둘 · 제공자마다 한 줄 · 그 아래 기존 토큰 사용량(다른 축).
struct MeAILimitsCard: View {
    let store: MeStore

    private var limits: AILimitsStore { store.aiLimits }

    var body: some View {
        let rows = limits.displayRows
        VStack(alignment: .leading, spacing: MobileTheme.space3) {
            titleRow(summary: limits.fiveHourSummary)
            if rows.isEmpty {
                emptyLine
            } else {
                table(rows)
                Text(MeText.aiLimitsCaption)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            tokenBlock
        }
        .padding(MobileTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
    }

    /// 제목 한 줄. 보이스오버는 여기서 **5시간 요약**을 한 번 말한다 — 화면에는 칩이 없다(줄마다의 숫자가
    /// 이미 다 보이는 것이 이 문법의 요점이고, 칩을 또 두면 같은 수가 두 번 선다).
    private func titleRow(summary: AILimitDisplay?) -> some View {
        HStack(spacing: MobileTheme.space2) {
            Text(MeText.aiLimitsTitle)
                .font(.headline)
                .foregroundStyle(MobileTheme.label)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Text(summary.map { "\(MeText.aiLimitsTitle), \(MeText.aiLimitsFiveHourPeak) \($0.valueText)" }
            ?? MeText.aiLimitsTitle))
    }

    private func table(_ rows: [AILimitDisplayRow]) -> some View {
        MeAILimitsTable(rows: rows)
    }

    /// 아직 그릴 줄이 없다: 불러오는 중 · 실패 · 연동한 도구 없음. **셋을 섞지 않는다** —
    /// "연동 없음"을 실패로 말하면 맥을 안 쓰는 사용자에게 고장으로 읽힌다.
    @ViewBuilder
    private var emptyLine: some View {
        if limits.state.hasLoaded {
            Text(MeText.aiLimitsNoProviders)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        } else if limits.state.hasFailed {
            LoadFailureRow(MeText.aiLimitsFailed, isRetrying: limits.state.isLoading) {
                Task { await limits.load() }
            }
        } else {
            Text(MeText.aiLimitsLoading)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
        }
    }

    /// 기존 토큰 사용량(다른 축). 모르면(수집 꺼짐 · 아직 못 받음) **줄을 만들지 않는다** — 0 은 "안 썼다"는 거짓이다.
    @ViewBuilder
    private var tokenBlock: some View {
        let totals = limits.phoneTokenTotals()
        if let today = totals.today {
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MeText.aiTokenTodayTitle)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                    Text(MeText.aiTokenValue(today))
                        .font(MobileTheme.number(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                }
                Spacer(minLength: MobileTheme.space2)
                if let recent = totals.recent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(MeText.aiTokenRecentTitle)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                        Text(MeText.aiTokenCompact(recent))
                            .font(MobileTheme.number(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.label)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - 표(열 머리 + 제공자 줄들)

/// 열 머리 한 줄 + 제공자 줄들. 간격 0 인 VStack 이다 — 줄 사이는 구분선이 쥐고, 줄 안쪽 여백은 각 줄이 쥔다
/// (간격을 VStack 에 주면 구분선이 줄 가운데가 아니라 한쪽에 붙는다).
///
/// 카드에서 **따로 뗀 까닭**: 검증 하네스가 `ImageRenderer` 로 이 격자를 그대로 구워 사람이 본다
/// (`MeAILimitsPreviewCatalog` — 카드는 `MeStore` 를 쥐고 있어 하네스가 만들 수 없다). 숫자 칸은
/// `lineLimit(1)` 이라 넘쳐도 높이가 변하지 않으므로 **눈으로 보는 것 말고는 잡을 길이 없는 결함**이 있다.
struct MeAILimitsTable: View {
    let rows: [AILimitDisplayRow]

    var body: some View {
        VStack(spacing: 0) {
            columnHeaderRow
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { rowSeparator }
                MeAILimitRow(row: row)
                    .padding(.vertical, MobileTheme.space1)
            }
        }
    }

    /// 열 머리 줄. **데이터 줄과 같은 격자**를 쓴다 — 왼쪽 칸을 비우고, 두 머리 칸이 `maxWidth: .infinity` 로
    /// 남는 폭을 **똑같이** 나눠 가진다. 데이터 줄의 두 칸(바 + 간격 + 숫자)도 같은 몫을 받으므로,
    /// 머리 글자의 오른쪽 끝이 자기 열 숫자 칸의 오른쪽 끝과 **구조적으로** 맞는다(측정 상수가 아니라 항등식이다 —
    /// 맥은 폭이 316pt 고정이라 간격을 상수로 적을 수 있었지만 폰은 기기마다 폭이 다르다).
    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
                .frame(width: MeAILimitCardBudget.nameColumnWidth + MeAILimitCardBudget.nameGap)
            columnHeader(.fiveHour)
            Spacer(minLength: 0).frame(width: MeAILimitCardBudget.columnGap)
            columnHeader(.weekly)
        }
        .padding(.bottom, MobileTheme.space1)
        .accessibilityHidden(true)
    }

    private func columnHeader(_ window: AILimitWindow) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(window.displayName)
                .font(.caption2.weight(.semibold))
                // ★ 열 머리 글자를 **그 열의 색으로 물들인다**. 색만으로 가르지 않는 것과 모순이 아니다 —
                //   글자 · 색 · 자리 셋이 같은 짝을 말하게 하는 것이 요점이다.
                .foregroundStyle(MeAILimitColumnColor.header(window))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 제공자 사이 구분선. 카드 안쪽 여백 **바깥까지** 긋는다(승인된 문법 ④) — 그래서 음수 여백이다.
    private var rowSeparator: some View {
        Rectangle()
            .fill(MeAILimitColumnColor.separator)
            .frame(height: MeAILimitCardBudget.separatorHeight)
            .padding(.horizontal, -MobileTheme.cardPadding)
            .accessibilityHidden(true)
    }
}

// MARK: - 제공자 한 줄

/// `[마크 이름/요금제][5시간 바 %][주간 바 %]` 한 줄.
///
/// ★ 큰 글자(AX 크기)에서는 **격자를 접고 세로로 쌓는다**. 고정폭 격자는 기본 글자 크기에서 재어 만든 것이고,
/// AX 크기에서는 이름(`안티그래비티`)만으로도 108pt 칸을 넘기므로 격자를 유지하면 바가 사라지거나 숫자가
/// 줄어들다 못해 읽히지 않는다. 쌓은 모양에서도 **정보는 하나도 빠지지 않는다** — 창마다 라벨 + 값 + 바를
/// 전부 그린다(없는 창은 `없음`). 말줄임 대신 배치를 바꾸는 것이 이 저장소 관례다.
private struct MeAILimitRow: View {
    let row: AILimitDisplayRow
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                grid
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }

    // MARK: 격자(기본 글자 크기)

    private var grid: some View {
        HStack(alignment: .center, spacing: 0) {
            nameColumn
                .frame(width: MeAILimitCardBudget.nameColumnWidth, alignment: .leading)
            Spacer(minLength: 0).frame(width: MeAILimitCardBudget.nameGap)
            cell(.fiveHour)
            Spacer(minLength: 0).frame(width: MeAILimitCardBudget.columnGap)
            cell(.weekly)
        }
    }

    /// 왼쪽 고정 칸: [마크][이름 / 요금제]. 요금제를 모르면 이름만(빈 줄을 만들지 않는다).
    private var nameColumn: some View {
        HStack(spacing: MeAILimitCardBudget.markGap) {
            AIProviderTile(provider: row.provider, size: MeAILimitCardBudget.markSide)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.provider.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let plan = row.planLabel {
                    Text(plan)
                        .font(.caption2)
                        .foregroundStyle(MobileTheme.label2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 한 칸 = 바 + 숫자. 세 모양이 있다:
    ///  ① 값이 있다 → 트랙 + 채움(열 색, 하한이면 흐리게) + `27%` / `27% 이상` / `0%`
    ///  ② 창은 있는데 판정 불가(기기 시계 어긋남) → 트랙만 + `—`(코어 규칙의 글자)
    ///  ③ **그 창이 없다** → 더 어두운 트랙만 + `없음`
    /// ②와 ③을 같은 글자로 그리지 않는 이유는 파일 머리말 ⑤에 있다.
    private func cell(_ window: AILimitWindow) -> some View {
        let display = row.display(window)
        return HStack(spacing: MeAILimitCardBudget.barValueGap) {
            MeAILimitBar(
                percent: display?.percent,
                floorOnly: display?.floorOnly ?? false,
                tint: MeAILimitColumnColor.bar(window),
                track: display == nil ? MeAILimitColumnColor.absentTrack : MeAILimitColumnColor.emptyTrack
            )
            .frame(maxWidth: .infinity)
            valueText(display)
                .frame(width: MeAILimitCardBudget.valueWidth, alignment: .trailing)
        }
    }

    /// 숫자 글자. **사용량 단계는 이 글자가 말한다**(바는 열 색을 쥐었다 — `AILimitUsageStage` 머리말).
    private func valueText(_ display: AILimitDisplay?) -> some View {
        Text(display?.valueText ?? AILimitColumnText.absentValueText)
            .font(MobileTheme.number(.caption, weight: .bold))
            // tabular-nums. 숫자 폭이 글리프마다 다르면 세 줄의 `%` 가 들쭉날쭉해 자릿수를 오독한다.
            .monospacedDigit()
            .foregroundStyle(display == nil
                             ? MeAILimitColumnColor.absentText
                             : MeAILimitColumnColor.usage(display?.percent))
            .lineLimit(1)
            // 글자 크기를 올린 사람도 **자릿수가 잘리지 않게** — 말줄임 대신 줄여서 넣는다.
            .minimumScaleFactor(0.7)
    }

    // MARK: 쌓은 모양(AX 크기)

    private var stacked: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            HStack(spacing: MeAILimitCardBudget.markGap) {
                AIProviderTile(provider: row.provider, size: MeAILimitCardBudget.markSide)
                Text(row.planLabel.map { "\(row.provider.displayName) · \($0)" } ?? row.provider.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            ForEach(AILimitWindow.allCases.sorted { $0.sortOrder < $1.sortOrder }, id: \.rawValue) { window in
                let display = row.display(window)
                VStack(alignment: .leading, spacing: MobileTheme.space1) {
                    HStack(spacing: MobileTheme.space1) {
                        Text(window.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MeAILimitColumnColor.header(window))
                        Spacer(minLength: MobileTheme.space1)
                        valueText(display)
                    }
                    MeAILimitBar(
                        percent: display?.percent,
                        floorOnly: display?.floorOnly ?? false,
                        tint: MeAILimitColumnColor.bar(window),
                        track: display == nil ? MeAILimitColumnColor.absentTrack : MeAILimitColumnColor.emptyTrack
                    )
                }
            }
        }
    }

    /// 보이스오버: 창마다 한 문장(값 + 나이), 없는 창도 말한다. 바는 숨기고 이 라벨 하나가 줄 전체를 말한다.
    private var label: String {
        let windows = AILimitWindow.allCases.sorted { $0.sortOrder < $1.sortOrder }.map { window -> String in
            guard let display = row.display(window) else {
                return MeText.aiLimitAbsentAccessibility(window: window)
            }
            return MeText.aiLimitAccessibility(provider: row.provider, display: display)
        }
        return ([row.provider.displayName] + windows).joined(separator: ", ")
    }
}

// MARK: - 바

/// 리밋 진행바. 트랙 + 채움 두 장. 폭은 호출부가 정하고(격자에서는 남는 폭), 높이는 두 열이 **같다**.
///
/// `percent` 가 nil 이면(판정 불가 · 창 없음) **트랙만** 그린다 — 0% 로 그리면 "하나도 안 썼다"는 거짓이다.
///
/// ★ 하한("27% 이상")은 채움을 **흐리게** 그린다. 수단은 색이 아니라 **불투명도**다(`AILimitFloorFill` —
///   위젯 틴트·투명 모드는 색을 통째로 버리고 알파만 남긴다. 세 화면이 같은 수를 쓴다).
///
/// 왜 공용 `ProgressBar` 를 안 쓰나: 그 부품은 채움 색을 `Style` 열거값에서 고르고 트랙이 한 가지다.
/// 이 카드는 칸마다 **열 색**과 **두 종류의 트랙**(빈 칸 / 창이 없는 칸)이 필요하다. 공용 부품에 그 입력을
/// 더하면 리밋과 무관한 다섯 자리의 렌더가 같이 흔들린다.
struct MeAILimitBar: View {
    /// 0…100. nil = 모른다 / 그 창이 없다(채움 없음).
    let percent: Double?
    let floorOnly: Bool
    let tint: Color
    let track: Color
    var height: CGFloat = MeAILimitCardBudget.barHeight

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if percent != nil {
                    Capsule()
                        .fill(tint)
                        .opacity(AILimitFloorFill.opacity(floorOnly: floorOnly))
                        // 채움 폭 산식은 **폰·위젯·맥이 한 벌**이다(좁은 바에서 1% 와 18% 가 같은 길이가 되지 않게).
                        .frame(width: AILimitBarFill.width(barWidth: proxy.size.width, percent: percent))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - 열 색 (숫자는 공유 팔레트 하나 — 위젯과 같은 값)

/// 두 열의 색. **숫자는 `AILimitColumnPalette`(CheckMobileShared) 한 곳에 있다** — 위젯 확장은 이 모듈을
/// 링크하지 않으므로(Package.swift) 색을 두 벌로 적으면 같은 데이터가 폰과 위젯에서 다른 색으로 보인다.
/// 이 타입이 하는 일은 그 숫자를 **라이트/다크를 아는 `Color`** 로 바꾸는 것뿐이다.
enum MeAILimitColumnColor {
    static func bar(_ window: AILimitWindow) -> Color { color(AILimitColumnPalette.bar(column(window))) }
    static func header(_ window: AILimitWindow) -> Color { color(AILimitColumnPalette.header(column(window))) }
    static let emptyTrack = color(AILimitColumnPalette.emptyTrack)
    static let absentTrack = color(AILimitColumnPalette.absentTrack)
    static let absentText = color(AILimitColumnPalette.absentText)

    /// 제공자 사이 구분선. ★ **여기만 공유 팔레트를 쓰지 않는다** — 그 값(`#2C3037`)은 맥 팝오버·위젯 바탕
    /// (어두운 `#232633`)에서 고른 것이라, 한 단 밝은 폰 카드 바탕(`surface` 다크 `#2B2E3D`) 위에서는
    /// 대비가 1.01:1 로 **보이지 않는다**(실측 렌더로 잡았다). 선이 안 보이면 승인된 문법 ④(제공자 사이
    /// 1px 구분선)가 화면에 없는 것과 같다. 그래서 이 앱이 모든 카드에서 쓰는 구분선 토큰을 쓴다 —
    /// 뜻과 모양(1px · 안쪽 여백 바깥까지)은 같고 **바탕에 맞춘 값**만 다르다.
    static let separator = MobileTheme.separator

    /// 사용량 단계 색. 경계는 공유 규칙이 쥐고(`AILimitUsageStage`), **반올림은 코어 규칙**을 거친다 —
    /// 89.5% 는 글자가 `90%` 라고 적으므로 색도 거기서 갈려야 한다(날것 double 로 가르면 글자와 색이 어긋난다).
    static func usage(_ percent: Double?) -> Color {
        switch AILimitUsageStage.stage(wholePercent: percent.map(AILimitFreshnessRule.wholePercent)) {
        case .calm: return MobileTheme.label
        case .warn: return MobileTheme.pending
        case .danger: return MobileTheme.danger
        }
    }

    /// 코어 열거값 → 공유 팔레트의 열. 옮기는 자리는 공유 모듈 한 곳이다(두 모듈이 각자 `switch` 를 적으면
    /// 한쪽에서 파랑과 보라가 뒤집힌 채 컴파일이 통과한다).
    private static func column(_ window: AILimitWindow) -> AILimitColumnWindow {
        AILimitColumnPalette.column(windowRawValue: window.rawValue)
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

// MARK: - 검증 하네스가 굽는 자리 (DEBUG 전용)

#if DEBUG
/// 「AI 리밋」 격자를 **위젯 밖·앱 밖에서** 그려 보는 목록(Release 에서 컴파일되지 않는다).
/// 검증 하네스가 `ImageRenderer` 로 PNG 를 뽑아 사람이 직접 본다 — 위젯의 `AingWidgetPreviewCatalog` 와 같은 갈래다.
///
/// ## 왜 필요한가
/// 숫자 칸은 `lineLimit(1)` 이라 넘쳐도 **높이가 변하지 않는다** = 렌더 높이로는 안 잡히고, 증상은 말줄임뿐이다.
/// 그리고 이 카드는 나 탭의 **접힌 아래쪽**에 있어 시뮬레이터 스크린샷으로는 보이지 않는다(스크롤이 필요하다).
/// 예산 테스트(`MeAILimitCardBudget`)가 숫자를 재지만, 겹침·정렬은 사람 눈이 마지막 그물이다.
public enum MeAILimitsPreviewCatalog {
    /// 기본 기기(393pt)의 카드 바깥 폭.
    public static let cardWidth: CGFloat = MeAILimitCardBudget.cardOuterWidth(screenWidth: 393)

    @MainActor
    public static func items(now: Date) -> [(id: String, width: CGFloat, view: AnyView)] {
        [
            ("card-three", cardWidth, card(rows(now: now, observedAgo: 120))),
            // 한 시간 전 관측 — 숫자가 하한("27% 이상")이 되어 **가장 넓은 문구**가 칸에 들어가는지 본다.
            ("card-stale", cardWidth, card(rows(now: now, observedAgo: 3_600))),
            // 제공자 하나 · 5시간 창이 아예 없는 계정(그 칸이 `없음` 으로 비는 모양).
            ("card-one", cardWidth, card(Array(rows(now: now, observedAgo: 120).suffix(1)))),
            // 좁은 기기(375pt)에서도 바가 남는지.
            ("card-narrow", MeAILimitCardBudget.cardOuterWidth(screenWidth: 375), card(rows(now: now, observedAgo: 120))),
        ]
    }

    /// 실제 서버 모양의 행 → **코어 규칙**을 그대로 지난 줄들(값을 지어내지 않는다).
    @MainActor
    private static func rows(now: Date, observedAgo: TimeInterval) -> [AILimitDisplayRow] {
        let observed = now.addingTimeInterval(-observedAgo)
        let fetched = [
            AILimitFetchedRow(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: now.addingTimeInterval(9_000),
                              weeklyPercent: 60, weeklyResetsAt: now.addingTimeInterval(450_000),
                              planLabel: "max", observedAt: observed),
            AILimitFetchedRow(provider: "codex", fiveHourPercent: 0, fiveHourResetsAt: nil,
                              weeklyPercent: 94, weeklyResetsAt: now.addingTimeInterval(200_000),
                              planLabel: "plus", observedAt: observed),
            AILimitFetchedRow(provider: "antigravity", fiveHourPercent: nil, fiveHourResetsAt: nil,
                              weeklyPercent: 8, weeklyResetsAt: now.addingTimeInterval(500_000),
                              planLabel: nil, observedAt: observed),
        ]
        let bundle = AILimitsStore.bundle(from: fetched, now: now)
        return bundle.visibleProviders.map { snapshot in
            func display(_ window: AILimitWindow) -> AILimitDisplay? {
                guard snapshot.window(window) != nil else { return nil }
                let value = AILimitFreshnessRule.display(provider: snapshot, window: window, now: now)
                return value.isVisible ? value : nil
            }
            return AILimitDisplayRow(provider: snapshot.provider, planLabel: snapshot.planLabel,
                                     fiveHour: display(.fiveHour), weekly: display(.weekly))
        }
    }

    @MainActor
    private static func card(_ rows: [AILimitDisplayRow]) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: MobileTheme.space3) {
                Text(MeText.aiLimitsTitle).font(.headline).foregroundStyle(MobileTheme.label)
                MeAILimitsTable(rows: rows)
                Text(MeText.aiLimitsCaption).font(.footnote).foregroundStyle(MobileTheme.label2)
            }
            .padding(MobileTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
        )
    }
}
#endif
#endif
