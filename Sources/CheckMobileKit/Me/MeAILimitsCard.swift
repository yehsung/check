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
// ## 기기 묶음 — 맥 두 대 이상이면 이름으로 묶어 **전부** 그린다 (v0.3.47)
// 서버는 이미 기기별로 저장한다(`ai_limits` PK = user·device·provider). 0.3.46 의 폰은 그걸 "제공자당 최신
// 하나"로 접었고, 그 접기가 **맥 A 에서 끈 제공자를 맥 B 의 값으로 되살렸다**. 숨기는 대신 드러낸다 —
// "껐는데 되살아났다"가 "저건 다른 맥 것"이 된다.
//  · **맥 한 대면 지금 그대로**(이름 줄이 아예 서지 않는다 — 혼자 쓰는 사람에게 군더더기를 보이지 않는다).
//  · 두 대 이상이면 묶음마다 머리글 한 줄(12pt semibold `label2`) + 그 맥의 제공자 줄들.
//
// ### ★ 열 머리는 **카드당 한 번**이다(묶음마다 되풀이하지 않는다) — 고른 근거 넷
// ① **세로 길이.** 이 카드는 나 탭의 접힌 아래쪽에 있다. 머리 줄은 11pt 글자 + 아래 여백 4 ≈ 15pt 고,
//    맥 셋이면 그 되풀이만 30pt 다 — 그만큼 아래 토큰 줄이 더 멀어진다. 되풀이로 얻는 것이 없다면 그 값은 손해다.
// ② **격자가 구조적으로 고정이다.** 왼쪽 이름 칸 108pt → 5시간 칸 → 주간 칸 순서는 `MeAILimitCardBudget` 의
//    고정 예산이라 **모든 묶음에서 같은 자리**다. 두 번째 머리글은 새 사실을 하나도 말하지 않는다.
// ③ **짝 단서가 이미 셋이고 그 가운데 둘이 모든 줄에 있다**(색 · 좌우 자리). 머리 글자는 그 색과 글자를
//    묶어 주는 세 번째 단서이고, 한 번 묶이면 **색이 아래로 그 묶음을 운반한다**.
// ④ **세 화면이 같은 문법을 쓴다**(승인된 문법 ② — 맥 팝오버·위젯도 머리를 한 번만 적는다). 폰만 되풀이하면
//    같은 데이터가 화면마다 다른 문법으로 선다 — 이 기능이 몇 번이고 밟은 함정이다.
// ★ 바꿔 말하면 **맥 한 대인 사람의 카드는 글자 하나 안 바뀐다**: 제목 → 열 머리 → 제공자 줄들. 두 대가 되면
//   그 사이에 머리글 줄만 끼어든다. 머리를 묶음마다 두면 1대 배치와 2대 배치가 서로 다른 모양이 된다.
//
// ### 이름이 겹치는 맥 두 대
// 맥 미니 두 대는 시스템 설정 이름이 **글자 그대로 같다**. 맥들은 서로를 모르므로 가르는 일은 **읽는 쪽**이
// 한다 — 같은 이름이 둘 이상이면 뒤에 식별자 꼬리가 붙는다(`Mac mini (A1B2)`). 겹치지 않으면 아무것도 붙지
// 않고, 이름을 한 번도 올린 적 없는 맥은 `이름 모를 맥 A1B2` 로 선다. 규칙은 코어 한 벌이다
// (`AILimitDeviceRoster.displayNameParts` · `AILimitDevice.baseName`) — 이 뷰는 스토어가 정한 글자를 적기만 한다.
// ★ 그 꼬리는 **이름과 따로** 그린다(v0.3.47 P2): 상한 길이(64 스칼라) 이름 두 대는 두 줄에도 안 들어가고,
//   합쳐 적으면 말줄임이 **꼬리부터** 먹어 두 머리글이 똑같아진다 — 근거는 `deviceNameRow` 주석.
//
// ## 고른 맥이 조용하면 그 사실을 적는다 (v0.3.47 P1)
// 고른 메인 맥이 유령(3일 무보고)이거나 그 맥에서 제공자를 전부 껐으면 폰은 **다른 맥**을 그린다. 그때
//  · 묶음이 하나뿐이어도 **기기 이름을 적고**(`AILimitsStore.showsDeviceNames`),
//  · 표 앞에 **한 줄**로 대체 사실을 말한다(`substituteDeviceLine`).
// 이름만으로는 "고르기가 저장되지 않았다"로 읽히기 때문이다 — 근거는 `AILimitSurfaceText.substitutedMainDevice`.
//
// 숨기기 규칙(2026-10-07 사용자 결정): 미연동 제공자는 줄을 만들지 않고, 하나도 없으면 안내 한 줄만 둔다.
// 폰에는 이 축의 스위치가 없다 — 사용자가 맥에서 그 도구에 로그인하면 저절로 나타난다.
//
// ## 설정에서 끈 제공자도 같은 길로 사라진다 (v0.3.47)
// 맥 설정에 **보기 스위치**가 생겼다(제공자별 + 마스터). 끄면 맥이 그 제공자의 서버 행을 창 값·리셋·플랜
// **전부 null 로 덮어** 한 번 올리고(서버에 DELETE 권한이 없다), 폰은 보이는 창이 0개인 행을 숨긴다 —
// 그래서 이 뷰에는 설정을 아는 코드가 **한 줄도 없다**(스토어의 줄이 그냥 사라진다 · 3일 유령 게이트를
// 기다리지 않는다). ★ 판정은 '보이는 창이 0개인가'다 — '5시간 창이 있나'로 재면 주간만 오는 안티그래비티가
// 함께 사라진다.
// 그 대신 **빈 상태 문구**가 바뀌었다: "로그인하면 보여요" 는 끈 사람에게 거짓이다(이미 로그인해 있다).
// 지금 문구는 연동과 보기 설정 **두 문을 함께** 가리킨다(`AILimitSurfaceText.noVisibleProviders` — 근거도 거기).

/// 「AI 리밋」 카드. 제목 · 열 머리 둘 · 제공자마다 한 줄 · 그 아래 기존 토큰 사용량(다른 축).
struct MeAILimitsCard: View {
    let store: MeStore

    private var limits: AILimitsStore { store.aiLimits }

    var body: some View {
        let groups = limits.displayGroups
        VStack(alignment: .leading, spacing: MobileTheme.space3) {
            titleRow(summary: limits.fiveHourSummary)
            if groups.isEmpty {
                emptyLine
            } else {
                // ★ 표 **앞**이다. 이 줄은 아래 숫자들을 어떻게 읽어야 하는지를 말하므로, 숫자를 다 본 뒤에
                //   나오면 늦다(보이스오버는 위에서 아래로 한 번 읽는다).
                if limits.isShowingSubstituteDevice { substituteDeviceLine }
                table(groups, showsDeviceNames: limits.showsDeviceNames)
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

    private func table(_ groups: [AILimitDeviceDisplayGroup], showsDeviceNames: Bool) -> some View {
        MeAILimitsTable(groups: groups, showsDeviceNames: showsDeviceNames)
    }

    /// 고른 맥 대신 다른 맥을 그리고 있다는 한 줄(v0.3.47 P1).
    ///
    /// ## 왜 머리글의 이름만으로는 부족한가
    /// 이름을 적으면 "이 숫자는 이 맥 것"은 참이 된다. 그러나 맥 설정에서 **다른 맥**을 고른 사람에게 그 이름은
    /// "고르기가 저장되지 않았다"로 읽힌다(고쳐질 것이 없는데 다시 고르러 간다). 그래서 대체가 일어났다는
    /// 사실을 글자로 말한다 — 문장·근거는 공유 상수에 있다(`AILimitSurfaceText.substitutedMainDevice`).
    ///
    /// 색은 `pending`(경고가 아니라 **주의**)이다: 고장이 아니고 숫자도 참이지만, 사용자가 고른 것과 다르다는
    /// 사실은 `label2` 로 적으면 캡션처럼 읽혀 지나친다.
    private var substituteDeviceLine: some View {
        Text(MeText.aiLimitsSubstitutedDevice)
            .font(.footnote)
            .foregroundStyle(MobileTheme.pending)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 아직 그릴 줄이 없다: 불러오는 중 · 실패 · **그릴 줄 0건**(연동이 없다 · 맥 설정에서 껐다 · 전부 유령이다).
    /// **셋을 섞지 않는다** — "줄 0건"을 실패로 말하면 맥을 안 쓰는 사용자에게 고장으로 읽힌다.
    /// 마지막 갈래의 세 까닭은 **한 문장으로** 말한다(가르지 않는 근거는 `AILimitSurfaceText` 머리말).
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

/// 열 머리 한 줄 + **기기 묶음들**. 간격 0 인 VStack 이다 — 줄 사이는 구분선이 쥐고, 줄 안쪽 여백은 각 줄이 쥔다
/// (간격을 VStack 에 주면 구분선이 줄 가운데가 아니라 한쪽에 붙는다).
///
/// 카드에서 **따로 뗀 까닭**: 검증 하네스가 `ImageRenderer` 로 이 격자를 그대로 구워 사람이 본다
/// (`MeAILimitsPreviewCatalog` — 카드는 `MeStore` 를 쥐고 있어 하네스가 만들 수 없다). 숫자 칸은
/// `lineLimit(1)` 이라 넘쳐도 높이가 변하지 않으므로 **눈으로 보는 것 말고는 잡을 길이 없는 결함**이 있다.
///
/// ## 평평한 한 격자다 — 묶음이 '카드 안의 카드'가 되지 않게
/// 묶음마다 `VStack` 을 중첩하지 않고 **머리글 줄과 제공자 줄을 한 줄기로** 세운다. 중첩하면 구분선을 묶음
/// 안쪽에서 끊을 수밖에 없고(음수 여백이 중첩 컨테이너의 폭을 기준으로 잡힌다), 그러면 승인된 문법 ④
/// ("구분선은 카드 안쪽 여백 **바깥까지**")가 깨져 묶음이 카드 속 또 다른 카드처럼 보인다.
///
/// ★ `ForEach` 의 id: 묶음은 **기기**로 돌고, 줄은 그 묶음 **안에서만** 제공자로 돈다.
///   맥 두 대가 같은 Claude 를 올리면 제공자 id 가 카드 안에서 두 번 나오므로, 한 `ForEach` 에 펼치면
///   SwiftUI 가 같은 id 두 개를 보고 줄을 뒤섞는다(`AILimitsStore.displayRows` 주석과 같은 경고).
struct MeAILimitsTable: View {
    let groups: [AILimitDeviceDisplayGroup]
    /// 기기 이름 줄을 그릴 것인가. **맥이 한 대면 false** — 그때 이 뷰는 0.3.46 과 글자 하나 다르지 않다.
    var showsDeviceNames: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            columnHeaderRow
            ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                // 묶음 경계에는 **이름을 그리든 안 그리든** 선이 있다(죽은 분기를 만들지 않는다 —
                // 지금은 이름 없이 묶음이 둘일 수 없지만, 그 전제가 느슨해지는 날 두 줄이 맞붙지 않게).
                if groupIndex > 0 { rowSeparator }
                if showsDeviceNames { deviceNameRow(group.nameParts, isFirst: groupIndex == 0) }
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { rowSeparator }
                    MeAILimitRow(row: row, deviceName: showsDeviceNames ? group.name : nil)
                        .padding(.vertical, MobileTheme.space1)
                }
            }
        }
    }

    /// 기기 묶음 머리글 한 줄. **구획 표시**라 제공자 이름보다 조용하다(12pt semibold `label2` — 같은 굵기·같은
    /// 색이면 네 번째 제공자 줄처럼 읽힌다).
    ///
    /// ## ★ 이름과 꼬리를 **따로** 그린다 (v0.3.47 P2 — 실증으로 잡은 결함)
    /// 0.3.47 초안은 합친 글자 하나를 `lineLimit(2)` + tail 말줄임으로 그렸고, 주석은 "긴 이름은 두 줄로 접힌다
    /// (말줄임이 아니다)"라고 단정했다. **두 줄에도 안 드는 이름이 있다**: `device_label` 상한이 64 스칼라고
    /// 한글은 12pt 에서 한 자가 ~12pt 라, 상한 길이 이름은 두 줄(가장 좁은 기기에서 311×2 = 622pt)을 넘는다.
    /// 그러면 말줄임이 **뒤**를 먹는데 거기가 바로 꼬리 `(A1B2)` 자리다 — 같은 이름의 맥 두 대가 **글자 그대로
    /// 똑같은 머리글**로 서서, 가르려고 만든 장치가 아무 일도 못 한다.
    ///
    /// 그래서 꼬리를 **말줄임이 닿지 않는 자리**로 옮긴다: 이름은 지금처럼 두 줄까지 접히고 넘치면 잘리되,
    /// 꼬리는 `fixedSize()` + `layoutPriority` 로 **언제나 제 폭을 먼저 가져간다**. 잘리는 쪽은 **겹쳐도 같은**
    /// 글자(이름)이고, 남는 쪽은 **가르는** 글자(꼬리)다.
    ///
    /// ★ 보이스오버는 이 줄을 **머리글 하나로** 읽는다(`children: .combine` + `.isHeader`) — 두 Text 로 나뉜 것은
    ///   그리기 사정이지 들을 사람의 사정이 아니다. 그리고 줄마다의 라벨에도 기기 이름이 들어간다
    ///   (`MeAILimitRow`): 머리글은 건너뛰며 읽는 사람을 위한 것이고, 줄 라벨은 한 줄만 들었을 때
    ///   "어느 맥이냐"에 답하기 위한 것이다.
    private func deviceNameRow(_ parts: AILimitDeviceNameParts, isFirst: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MeAILimitCardBudget.deviceTailGap) {
            Text(parts.base)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if let tail = parts.tail {
                Text(AILimitDeviceNameParts.tailText(tail))
                    .lineLimit(1)
                    // ★ 이 둘이 꼬리를 지킨다: `fixedSize` 는 "줄이지 마라", `layoutPriority` 는 "먼저 가져가라".
                    //   하나만 두면 이름이 긴 날 꼬리가 0pt 로 눌리거나 `…` 로 바뀐다.
                    .fixedSize()
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(MobileTheme.label2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, isFirst ? 0 : MeAILimitCardBudget.deviceNameTopGap)
        .padding(.bottom, MeAILimitCardBudget.deviceNameBottomGap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 열 머리 줄. **데이터 줄과 같은 격자**를 쓴다 — 왼쪽 칸을 비우고, 두 머리 칸이 `maxWidth: .infinity` 로
    /// 남는 폭을 **똑같이** 나눠 가진다. 데이터 줄의 두 칸(바 + 간격 + 숫자)도 같은 몫을 받으므로,
    /// 머리 글자의 오른쪽 끝이 자기 열 숫자 칸의 오른쪽 끝과 **구조적으로** 맞는다(측정 상수가 아니라 항등식이다 —
    /// 맥은 폭이 316pt 고정이라 간격을 상수로 적을 수 있었지만 폰은 기기마다 폭이 다르다).
    ///
    /// ★ **카드당 한 번**이다 — 기기 묶음마다 되풀이하지 않는다(근거 넷은 파일 머리말 §기기 묶음).
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
    /// 이 줄이 어느 맥의 것인가 — **보이스오버 라벨에만** 쓴다(화면에는 묶음 머리글이 이미 그 이름을 적었다).
    /// nil = 맥이 한 대다(= 말할 것이 없다).
    ///
    /// ★ 왜 라벨에 넣는가: 보이스오버는 한 줄씩 읽는다. 머리글을 지나쳐 세 번째 줄에 바로 닿은 사람에게
    ///   "Claude 5시간 91%" 는 **어느 맥인지 말하지 않는다** — 이 기능이 고치려던 바로 그 거짓이 소리에만 남는다.
    var deviceName: String?
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
        // ★ 한 문장을 만드는 일은 **뷰 밖**이다(`MeText.aiLimitRowAccessibility`) — 이 뷰는 맥 스위트가 한 줄도
        //   컴파일하지 않아서, 여기서 이어 붙이면 순서·누락을 재는 그물이 소스 grep 하나뿐이 된다.
        .accessibilityLabel(Text(MeText.aiLimitRowAccessibility(deviceName: deviceName, row: row)))
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

    /// 미리보기용 맥 둘(**지어낸 이름** — 실사용자 값이 아니다).
    private static let macA = "mac-a-1111"
    private static let macB = "mac-b-2222"
    /// 이름이 **글자 그대로 겹치는** 맥 둘(맥 미니 두 대) — 꼬리가 붙는 모양을 눈으로 본다.
    private static let twinA = "twin-aaaa-a1b2"
    private static let twinB = "twin-bbbb-c3d4"

    @MainActor
    public static func items(now: Date) -> [(id: String, width: CGFloat, view: AnyView)] {
        [
            ("card-three", cardWidth, card(groups(now: now, observedAgo: 120))),
            // 한 시간 전 관측 — 숫자가 하한("27% 이상")이 되어 **가장 넓은 문구**가 칸에 들어가는지 본다.
            ("card-stale", cardWidth, card(groups(now: now, observedAgo: 3_600))),
            // 제공자 하나 · 5시간 창이 아예 없는 계정(그 칸이 `없음` 으로 비는 모양).
            ("card-one", cardWidth, card(groups(now: now, observedAgo: 120, suffix: 1))),
            // 좁은 기기(375pt)에서도 바가 남는지.
            ("card-narrow", MeAILimitCardBudget.cardOuterWidth(screenWidth: 375),
             card(groups(now: now, observedAgo: 120))),
            // ★ 맥 **두 대**(v0.3.47) — 묶음 머리글이 제공자 줄과 갈려 보이는지 · 열 머리가 위에 한 번만 있는지 ·
            //   두 번째 묶음이 '카드 안의 카드' 처럼 보이지 않는지. 둘째 맥은 Claude 하나뿐이다(불균형 모양).
            ("card-two-devices", cardWidth, card(twoDevices(now: now), showsDeviceNames: true)),
            // ★ **이름이 겹치는** 맥 두 대 — 꼬리 `(A1B2)` 가 붙은 가장 넓은 머리글이 한 줄에 드는지.
            ("card-twin-names", cardWidth, card(twinDevices(now: now), showsDeviceNames: true)),
            // ★ 좁은 기기 + 두 대(머리글이 좁은 폭에서 접히지 않는지).
            ("card-two-devices-narrow", MeAILimitCardBudget.cardOuterWidth(screenWidth: 375),
             card(twoDevices(now: now), showsDeviceNames: true)),
            // ★★ **상한 길이(64 스칼라) 이름이 겹친 맥 두 대** — v0.3.47 P2 가 고친 그 모양이다.
            //   보는 것: 이름은 두 줄에서 잘려도 꼬리 `(A1B2)`/`(C3D4)` 가 **둘 다 남아** 두 머리글이 다르게
            //   보이는지. 합쳐 적던 초안에서는 두 줄이 글자까지 똑같았다(그래서 사람 눈이 마지막 그물이다 —
            //   폰 뷰는 맥 스위트가 한 줄도 컴파일하지 않는다).
            ("card-twin-long-names", cardWidth, card(twinLongNameDevices(now: now), showsDeviceNames: true)),
            ("card-twin-long-names-narrow", MeAILimitCardBudget.cardOuterWidth(screenWidth: 375),
             card(twinLongNameDevices(now: now), showsDeviceNames: true)),
        ]
    }

    /// 상한 길이(64 스칼라)로 **글자 그대로 같은** 이름을 쓰는 맥 두 대. 서버 CHECK 가 받아 주는 가장 긴 이름이고,
    /// 사람이 실제로 적을 수 있는 값이다(`AILimitDeviceLabelContract.maxScalars`).
    @MainActor
    private static func twinLongNameDevices(now: Date) -> [AILimitDeviceDisplayGroup] {
        // 한글 한 자 = 스칼라 하나다. 앞을 알아볼 수 있는 말로 두고 상한까지 채운다(잘리는 자리가 어디인지 보이게).
        let head = "거실에 둔 맥 미니 "
        let maxName = head + String(repeating: "길", count: AILimitDeviceLabelContract.maxScalars - head.unicodeScalars.count)
        let first = Array(rows(deviceID: twinA, label: maxName, now: now, observedAgo: 120).prefix(2))
        let second = Array(rows(deviceID: twinB, label: maxName, now: now, observedAgo: 600,
                                fiveHour: 91, weekly: 44).prefix(1))
        return fold(first + second, now: now)
    }

    /// 실제 서버 모양의 행 → **스토어의 기기 묶기 + 코어 규칙**을 그대로 지난 묶음들(값을 지어내지 않는다).
    @MainActor
    private static func groups(now: Date, observedAgo: TimeInterval, suffix: Int? = nil) -> [AILimitDeviceDisplayGroup] {
        var fetched = rows(deviceID: macA, label: "예성의 MacBook Pro", now: now, observedAgo: observedAgo)
        if let suffix { fetched = Array(fetched.suffix(suffix)) }
        return fold(fetched, now: now)
    }

    @MainActor
    private static func twoDevices(now: Date) -> [AILimitDeviceDisplayGroup] {
        let first = rows(deviceID: macA, label: "예성의 MacBook Pro", now: now, observedAgo: 120)
        // 둘째 맥은 **더 오래전** 관측이고 Claude 하나뿐이다 — 묶음 순서(최근 먼저)와 불균형을 같이 본다.
        let second = Array(rows(deviceID: macB, label: "사무실 iMac", now: now, observedAgo: 1_800,
                                fiveHour: 91, weekly: 44).prefix(1))
        return fold(first + second, now: now)
    }

    @MainActor
    private static func twinDevices(now: Date) -> [AILimitDeviceDisplayGroup] {
        // 같은 이름 둘 — 이름을 **한 번도 올린 적 없는 맥**은 `이름 모를 맥 ABCD` 로 선다(그 모양도 같이 본다).
        let first = Array(rows(deviceID: twinA, label: "Mac mini", now: now, observedAgo: 120).prefix(2))
        let second = Array(rows(deviceID: twinB, label: "Mac mini", now: now, observedAgo: 600,
                                fiveHour: 91, weekly: 44).prefix(1))
        let third = Array(rows(deviceID: "nameless-9f8e", label: nil, now: now, observedAgo: 900,
                               fiveHour: 12, weekly: 5).prefix(1))
        return fold(first + second + third, now: now)
    }

    /// ★ 스토어와 **같은 두 함수**를 지난다(기기 묶기 → 그릴 묶음). 하네스가 이름 가르기·코어 규칙을 자기 손으로
    /// 다시 적으면 사람이 보는 그림이 화면과 다른 규칙으로 서고, 그 그림으로 승인을 받으면 틀린 것이 굳는다.
    @MainActor
    private static func fold(_ fetched: [AILimitFetchedRow], now: Date) -> [AILimitDeviceDisplayGroup] {
        AILimitsStore.displayGroups(from: AILimitsStore.groups(from: fetched, now: now), now: now)
    }

    private static func rows(
        deviceID: String, label: String?, now: Date, observedAgo: TimeInterval,
        fiveHour: Double = 27, weekly: Double = 60
    ) -> [AILimitFetchedRow] {
        let observed = now.addingTimeInterval(-observedAgo)
        return [
            AILimitFetchedRow(deviceID: deviceID, deviceLabel: label, provider: "claude",
                              fiveHourPercent: fiveHour, fiveHourResetsAt: now.addingTimeInterval(9_000),
                              weeklyPercent: weekly, weeklyResetsAt: now.addingTimeInterval(450_000),
                              planLabel: "max", observedAt: observed),
            AILimitFetchedRow(deviceID: deviceID, deviceLabel: label, provider: "codex",
                              fiveHourPercent: 0, fiveHourResetsAt: nil,
                              weeklyPercent: 94, weeklyResetsAt: now.addingTimeInterval(200_000),
                              planLabel: "plus", observedAt: observed),
            AILimitFetchedRow(deviceID: deviceID, deviceLabel: label, provider: "antigravity",
                              fiveHourPercent: nil, fiveHourResetsAt: nil,
                              weeklyPercent: 8, weeklyResetsAt: now.addingTimeInterval(500_000),
                              planLabel: nil, observedAt: observed),
        ]
    }

    @MainActor
    private static func card(_ groups: [AILimitDeviceDisplayGroup], showsDeviceNames: Bool = false) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: MobileTheme.space3) {
                Text(MeText.aiLimitsTitle).font(.headline).foregroundStyle(MobileTheme.label)
                MeAILimitsTable(groups: groups, showsDeviceNames: showsDeviceNames)
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
