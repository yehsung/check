#if os(iOS)
import SwiftUI

// 순위판 행 문법 — **순위 탭**(팀 리그 · AI 토큰 · 미니게임)과 **게임 탭**(미니게임 '오늘 순위' · 결과 화면)이 한 벌을 쓴다.
//
// 통합 때 승격했다: 두 탭이 어제 1등 행과 순위 한 행을 각자 만들어, 같은 데이터가 화면마다 다른 부품으로 보였다
// (비평 4a "어제 1등: 순위 탭은 왕관·무테 카드·초록 칩, 게임 화면은 크림색 테두리 상자와 주황 칩" · 4b "센터 배지 자리").
// 치수는 시안 B 05·06 을 따른다: 순위 원 24 · 사이 10 · 얼굴 36(리그·토큰)/30(미니게임) · 행 48 · 내 행 파랑 6%.

/// 순위판 행 치수(시안 `.b-lg-row` · `.b-mg-row`). 얼굴은 글자를 따라 커지고(`MobileAvatarScale`), 구분선 시작점도 같은 배율로 옮긴다.
package enum RankRowMetrics {
    /// 순위 원 ↔ 얼굴 ↔ 이름 사이.
    package static let gap: CGFloat = 10

    /// 구분선 시작점 = 이름 글자가 시작하는 x. 접근성 글자 크기에서는 행이 두 줄로 쌓여 얼굴 폭이 뜻을 잃으므로 카드 안쪽 여백까지만.
    package static func dividerInset(rankSide: CGFloat, faceBase: CGFloat, textScale: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        if isAccessibilitySize { return MobileTheme.cardPadding }
        return MobileTheme.cardPadding + rankSide + gap + MobileAvatarScale.side(base: faceBase, textScale: textScale) + gap
    }
}

/// 순위판 행에서 쓰는 치수 읽기(글자 배율 · 순위 원 크기 — 공용 부품과 같은 기준 글자).
package struct RankRowScaledMetrics: DynamicProperty {
    @ScaledMetric(relativeTo: .body) package var textScale: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) package var rankSide: CGFloat = 24
    @Environment(\.dynamicTypeSize) package var dynamicTypeSize

    package init() {}

    package func dividerInset(faceBase: CGFloat) -> CGFloat {
        RankRowMetrics.dividerInset(rankSide: rankSide, faceBase: faceBase, textScale: textScale,
                                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    /// 윗줄 맞춤 행에서 순위 원을 얼굴 가운데 높이로 내리는 양(시안 `.b-lg-row .b-rank{margin-top:6px}` = (36 − 24) / 2).
    package func badgeTopOffset(faceBase: CGFloat) -> CGFloat {
        max(0, (MobileAvatarScale.side(base: faceBase, textScale: textScale) - rankSide) / 2)
    }
}

/// 인셋 그룹 **안의 한 행**. 행마다 카드가 아니라 한 그룹 안의 행이다(비평 3 "목록 밀도" — 맥의 절반 이하였다).
/// 내 행(내 팀)은 공용 강조 파랑 6%. 구분선은 이름 글자 시작점부터, 마지막 행은 긋지 않는다.
package struct RankRow<Content: View>: View {
    private let isMine: Bool
    private let isLast: Bool
    private let dividerInset: CGFloat
    private let minHeight: CGFloat
    private let verticalPadding: (top: CGFloat, bottom: CGFloat)
    private let content: Content

    package init(
        isMine: Bool,
        isLast: Bool,
        dividerInset: CGFloat,
        minHeight: CGFloat = MobileTheme.rowHeight,
        verticalPadding: (top: CGFloat, bottom: CGFloat) = (10, 10),
        @ViewBuilder content: () -> Content
    ) {
        self.isMine = isMine
        self.isLast = isLast
        self.dividerInset = dividerInset
        self.minHeight = minHeight
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    package var body: some View {
        GroupRow(
            divider: isLast ? .none : .inset(dividerInset),
            minHeight: minHeight,
            padding: EdgeInsets(top: verticalPadding.top, leading: MobileTheme.cardPadding,
                                bottom: verticalPadding.bottom, trailing: MobileTheme.cardPadding)
        ) {
            content
        }
        .rankRowSurface(isMine: isMine, standsAlone: false, padding: 0, cornerRadius: 0)
    }
}

/// 행 머리(순위 원 · 얼굴) + 본문. 보통 크기는 가로 한 줄, **접근성 글자 크기**에서는 머리를 위 한 줄로 올려 본문에 폭을 다 준다
/// (큰 글자 실측: 가로 그대로면 이름이 한 글자씩 꺾이고 숫자가 잘렸다).
package struct RankRowBody<Face: View, Content: View>: View {
    private let rank: Int
    private let alignment: VerticalAlignment
    private let badgeTopOffset: CGFloat
    private let face: Face
    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter badgeTopOffset: 윗줄 맞춤 행(팀 리그)에서 순위 원을 얼굴 가운데 높이로 내리는 양.
    package init(
        rank: Int,
        alignment: VerticalAlignment = .center,
        badgeTopOffset: CGFloat = 0,
        @ViewBuilder face: () -> Face,
        @ViewBuilder content: () -> Content
    ) {
        self.rank = rank
        self.alignment = alignment
        self.badgeTopOffset = badgeTopOffset
        self.face = face()
        self.content = content()
    }

    package var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: RankRowMetrics.gap) {
                    RankBadge(rank: rank)
                    face
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: RankRowMetrics.gap) {
                RankBadge(rank: rank)
                    .padding(.top, alignment == .top ? badgeTopOffset : 0)
                face
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 순위판 행의 얼굴: **내 행**은 착용 캐릭터 초상(표정 = 근무 상태), 남은 이니셜 틴트 원(사진이 있으면 사진).
/// 점은 그리지 않는다 — 순위판은 근무 상태판이 아니다.
package struct RankRowFace: View {
    private let name: String
    private let colorSeed: String
    private let url: URL?
    private let base: CGFloat
    private let me: (id: String?, mood: CharacterMood)?
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    /// - Parameter me: 내 행이면 착용 캐릭터(id 가 nil 이면 아잉), 남의 행이면 nil.
    package init(name: String, colorSeed: String, url: URL?, base: CGFloat, me: (id: String?, mood: CharacterMood)?) {
        self.name = name
        self.colorSeed = colorSeed
        self.url = url
        self.base = base
        self.me = me
    }

    package var body: some View {
        if let me {
            CharacterPortrait(id: me.id, mood: me.mood, size: MobileAvatarScale.side(base: base, textScale: textScale))
        } else {
            PersonAvatar(name: name, colorSeed: colorSeed, url: url, size: base)
        }
    }
}

/// 어제 1등 한 줄(시안 B 06 `.b-champ`): 왕관 원 32 · "어제 1등" / 이름 + 센터 배지 + 점수 · 오른쪽 초록 획득 칩 [보석]+20 받음.
///
/// **'오늘 순위' 그룹과 다른 그룹**으로 떼어 첫 행처럼 읽히지 않게 한다(시안은 `b-group` 두 장) — 그래서 이 부품이 자기 인셋 그룹을
/// 두른다. 게임 탭 미니게임 화면과 순위 탭 미니게임 판이 **같은 이 부품**을 쓴다(비평 4a).
package struct ChampionRow: View {
    private let caption: String
    private let name: String
    private let center: String?
    private let score: String
    private let awarded: Int?
    private let awardedSuffix: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - caption: 위 줄("어제 1등").
    ///   - center: 센터 **서버 값**(`CenterLabel` 규약).
    ///   - score: 이미 꾸민 점수 글자("972점").
    ///   - awarded: 받은 루비(nil = 못 받았거나 모른다 → 칩 없음).
    package init(caption: String, name: String, center: String?, score: String, awarded: Int?, awardedSuffix: String = "받음") {
        self.caption = caption
        self.name = name
        self.center = center
        self.score = score
        self.awarded = awarded
        self.awardedSuffix = awardedSuffix
    }

    package var body: some View {
        InsetGroup {
            GroupRow(divider: .none,
                     padding: EdgeInsets(top: 12, leading: MobileTheme.cardPadding, bottom: 12, trailing: MobileTheme.cardPadding)) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        CrownBadge()
                        texts
                        gain
                    }
                } else {
                    CrownBadge()
                    texts
                    Spacer(minLength: 8)
                    gain
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [caption, name]
        if let display = CenterLabel.display(center) { parts.append(display) }
        parts.append(score)
        if awarded != nil { parts.append("루비 \(awarded ?? 0)개 \(awardedSuffix)") }
        return parts.joined(separator: ", ")
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            if dynamicTypeSize.isAccessibilitySize {
                // 접근성 글자에서는 이름 줄이 늘 두 줄(이름 / 배지)이라 점수를 옆에 두면 가운데에 떠 보였다(실측) — 아래 줄로.
                VStack(alignment: .leading, spacing: 2) {
                    nameLine
                    scoreText
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 6) {
                        nameLine
                        scoreText
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        nameLine
                        scoreText
                    }
                }
            }
        }
    }

    private var nameLine: some View {
        PersonName(name, center: center)
    }

    private var scoreText: some View {
        Text(score)
            .font(MobileTheme.number(.callout, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
            .fixedSize()
    }

    @ViewBuilder
    private var gain: some View {
        if let awarded {
            RubyGain(awarded, suffix: awardedSuffix, style: .chip)
        }
    }
}
#endif
