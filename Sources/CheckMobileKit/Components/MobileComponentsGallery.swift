#if DEBUG && os(iOS)
import CheckMobileShared
import SwiftUI

/// 기반 부품 견본(DEBUG 전용 — Release 에 컴파일되지 않는다). 데모 라우트로 연다:
///
///     simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute components/1 -AingCheckDemoAppearance dark
///
/// 페이지: `components/1` 토큰·루비 · `/2` 버튼·유리·칩 · `/3` 초상 · `/4` 사람 행·순위 · `/5` 그룹·막대·시트 머리 · `/6` 잔디 ·
/// `/7` 큰 글자 확인용 한 장.
/// `components/tabbar/<단계>`: 탭 막대 숨김 실측 — 0 목록(보임) · 1 대화 push(숨김) · 2 push 뒤 시트 띄웠다 닫기(숨김 유지) · 3 push 뒤 뒤로(다시 보임).
struct MobileComponentsGallery: View {
    let route: String

    var body: some View {
        let parts = route.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[1] == "tabbar" {
            GalleryTabBarProbe(step: parts.count >= 3 ? Int(parts[2]) ?? 0 : 0)
        } else {
            let page = parts.count >= 2 ? Int(parts[1]) ?? 1 : 1
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    Text("부품 견본 \(page)")
                        .font(MobileTheme.title(.largeTitle))
                        .foregroundStyle(MobileTheme.label)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    switch page {
                    case 2: GalleryPageButtons()
                    case 3: GalleryPagePeople()
                    case 4: GalleryPageRows()
                    case 5: GalleryPageGroups()
                    case 6: GalleryPageGrass()
                    case 7: GalleryPageLargeText()
                    default: GalleryPageTokens()
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.bottom, 40)
            }
            .background(MobileTheme.background.ignoresSafeArea())
        }
    }
}

private struct GalleryCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2).foregroundStyle(MobileTheme.label2)
    }
}

// MARK: 1 — 토큰 · 루비 · 버튼

private struct GalleryPageTokens: View {
    private let swatches: [(String, Color)] = [
        ("label", MobileTheme.label), ("label2", MobileTheme.label2), ("label3Text", MobileTheme.label3Text), ("label3", MobileTheme.label3),
        ("accent", MobileTheme.accent), ("accentFill", MobileTheme.accentFill), ("working", MobileTheme.working), ("workingDot", MobileTheme.workingDot),
        ("pending", MobileTheme.pending), ("danger", MobileTheme.danger), ("aiToken", MobileTheme.aiToken), ("offWork", MobileTheme.offWork),
        ("fill", MobileTheme.fill), ("surface2", MobileTheme.surface2), ("separator", MobileTheme.separator), ("badge", MobileTheme.badge),
    ]

    var body: some View {
        SectionHeader("색 토큰", trailing: .text("뜻으로만"), padded: true)
        AingCard {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(swatches, id: \.0) { name, color in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color).frame(height: 26)
                        Text(name).font(.system(size: 9)).foregroundStyle(MobileTheme.label2).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            }
            HStack(spacing: 10) {
                Text("본문").foregroundStyle(MobileTheme.label)
                Text("보조").foregroundStyle(MobileTheme.label2)
                Text("자리표시").foregroundStyle(MobileTheme.label3Text)
                Text("근무 중").foregroundStyle(MobileTheme.working)
                Text("연결 끊김").foregroundStyle(MobileTheme.pending)
                Text("AI").foregroundStyle(MobileTheme.aiToken)
            }
            .font(.footnote)
            ProgressBar(0.62, style: .gauge)
        }

        SectionHeader("루비", trailing: .text("ruby.png · 문법 셋"), padded: true)
        AingCard {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(RubyGlyph.sizes, id: \.self) { size in
                    VStack(spacing: 4) {
                        RubyIcon(size: size, scalesWithText: false)
                        GalleryCaption(text: "\(Int(size))")
                    }
                }
                Spacer()
                RubyBalanceChip(37, style: .glass)
            }
            HStack(spacing: 12) {
                RubyBalanceChip(47, style: .large)
                RubyBalanceChip(37)
                RubyBalanceChip(nil)
            }
            HStack(spacing: 14) {
                RubyPrice(30, balance: 47)
                RubyPrice(80, balance: 47)
                RubyGain(10)
                RubyGain(20, suffix: "받음", style: .chip)
            }
        }

    }
}

private struct GalleryPageButtons: View {
    var body: some View {
        SectionHeader("버튼 3단", trailing: .text("50 · 40 · 30"), padded: true)
        AingCard {
            AingButton("30 사기", kind: .filled, size: .lg, fillsWidth: true) {}
            HStack(spacing: 8) {
                AingButton("캐릭터 바꾸기", systemImage: "person", kind: .tinted, size: .md) {}
                AingButton("상점", kind: .gray, size: .md) {}
            }
            HStack(spacing: 8) {
                AingButton("도전", kind: .tinted, size: .sm) {}
                AingButton("대국 중", kind: .tinted, size: .sm) {}.disabled(true)
                AingButton("전체 보기", kind: .plain, size: .sm) {}
                AingButton("기권", kind: .destructive, size: .sm) {}
            }
            HStack(spacing: 8) {
                AingButton("보내는 중", kind: .filled, size: .md, isBusy: true) {}
                AingButton("저장", kind: .filled, size: .md) {}.disabled(true)
                RetryButton {}
            }
        }
        SectionHeader("유리 · 칩", padded: true)
        AingCard {
            HStack(spacing: 10) {
                GlassCircleButton(systemImage: "square.and.pencil", accessibilityLabel: "새 대화") {}
                GlassCircleButton(systemImage: "ellipsis", accessibilityLabel: "더보기") {}
                GlassPill {
                    StatusDot(.working)
                    Text("근무 중 6명").font(.subheadline.weight(.semibold)).foregroundStyle(MobileTheme.label)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                AingChip(text: "목표 달성", tint: MobileTheme.working)
                AingChip(text: "어제", tint: MobileTheme.label2, background: MobileTheme.fill)
                AingChip(text: "우리 팀", outlined: true)
                MeChip()
                MeChip(outlined: true)
                CenterBadge("busan")
            }
            // 이름 줄 키(18pt) — 센터 배지·'나' 칩과 높이가 맞는다(통합 때 승격한 `AingChip.Size.small`).
            HStack(spacing: 8) {
                AingChip(text: "우리 팀", size: .small)
                AingChip(text: "비공개", tint: MobileTheme.label2, background: MobileTheme.fill, size: .small)
                CenterBadge("seoul")
                MeChip()
                Spacer()
            }
            PersonName("아주아주긴이름의사람", center: "seoul", isMe: true,
                       chips: [.accent("우리 팀"), .muted("비공개")], onTint: true)
            HStack(spacing: 8) {
                StatusDot(.working); StatusDot(.pending); StatusDot(.off)
                ProgressBar(0.3, style: .ai, thin: true)
            }
            LoadFailureRow("순위를 불러오지 못했어요", retry: {})
        }
    }
}

// MARK: 2 — 초상 · 사람 · 순위

private struct GalleryPagePeople: View {
    var body: some View {
        SectionHeader("캐릭터 초상", trailing: .text("표정 = 상태"), padded: true)
        AingCard {
            HStack(alignment: .top, spacing: 16) {
                portrait("fox", .working, "근무 중")
                portrait("fox", .lost, "연결 끊김")
                portrait("fox", .off, "근무 안 함")
                portrait("ghost", .plain, "상태 없음")
            }
            HStack(alignment: .center, spacing: 18) {
                CharacterPortrait(id: "aing", mood: .working, size: 68, badge: .symbol("paintbrush.pointed.fill"))
                CharacterPortrait(id: "shiba", mood: .working, size: 40, badge: .stone(isBlack: true))
                CharacterPortrait(id: "squirrel", mood: .off, size: 40, badge: .stone(isBlack: false))
                CharacterPortrait(id: "jellyfish", mood: .working, size: 25)
                CharacterPortrait(id: "unknown-id", mood: .plain, size: 32)
            }
            HStack(alignment: .bottom, spacing: 12) {
                CharacterPortrait(id: "fox", mood: .working, size: 132, framed: false)
                CharacterPortrait(id: "fox", mood: .off, size: 96, framed: false)
                VStack(alignment: .leading, spacing: 4) {
                    GalleryCaption(text: "무대(틀 없음)")
                    GalleryCaption(text: "132pt = 고해상 420px")
                    GalleryCaption(text: "시무룩은 192px 원본")
                }
            }
        }

    }

    private func portrait(_ id: String, _ mood: CharacterMood, _ caption: String) -> some View {
        VStack(spacing: 8) {
            CharacterPortrait(id: id, mood: mood, size: 52)
            GalleryCaption(text: caption)
        }
    }
}

private struct GalleryPageRows: View {
    var body: some View {
        SectionHeader("사람 행", trailing: .text("점 · 이름 뒤 센터"), padded: true)
        InsetGroup {
            GroupRow(divider: .inset(60)) {
                PersonAvatar(name: "민트", status: .working, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    PersonName("민트", center: "seoul")
                    Text("4시간 10분").font(MobileTheme.rowSubtitle).monospacedDigit().foregroundStyle(MobileTheme.label2)
                }
            }
            GroupRow(divider: .inset(60)) {
                PersonAvatar(name: "보리", status: .pending, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    PersonName("보리", center: "busan")
                    Text("연결 끊김 · 마지막 확인 13분 전").font(MobileTheme.rowSubtitle).foregroundStyle(MobileTheme.pending)
                }
            }
            GroupRow(divider: .none, isHighlighted: true) {
                RankBadge(rank: 3)
                CharacterPortrait(id: "fox", mood: .working, size: 32, ringGap: MobileTheme.surface)
                PersonName("새벽", center: "seoul", isMe: true)
                Spacer()
                Text("941점").font(MobileTheme.roundedNumber(.callout)).monospacedDigit().foregroundStyle(MobileTheme.label)
            }
        }
        // 순위판 머리 + 어제 1등 + 그룹 안 행 — 순위 탭과 게임 탭이 함께 쓰는 승격 부품(`SectionHeaderBar`·`ChampionRow`·`RankRow`).
        SectionHeaderBar("순위", topPadding: 18) {
            AingChip(text: "타이밍 바", tint: MobileTheme.label2, background: MobileTheme.fill)
        }
        ChampionRow(caption: "어제 1등", name: "라떼", center: "seoul", score: "972점", awarded: 20)
        RankRow(isMine: false, isLast: false, dividerInset: 84, minHeight: 48, verticalPadding: (7, 7)) {
            RankRowBody(rank: 2) {
                RankRowFace(name: "구름", colorSeed: "구름", url: nil, base: 30, me: nil)
            } content: {
                HStack(spacing: 8) {
                    PersonName("구름", center: "busan")
                    Spacer(minLength: 4)
                    Text("968점").font(MobileTheme.number(.callout, weight: .semibold)).monospacedDigit()
                }
            }
        }
        RankRow(isMine: true, isLast: true, dividerInset: 84, minHeight: 48, verticalPadding: (7, 7)) {
            RankRowBody(rank: 3) {
                RankRowFace(name: "나", colorSeed: "나", url: nil, base: 30, me: ("fox", .working))
            } content: {
                HStack(spacing: 8) {
                    PersonName("새벽", center: "seoul", isMe: true, onTint: true)
                    Spacer(minLength: 4)
                    Text("941점").font(MobileTheme.number(.callout, weight: .semibold)).monospacedDigit()
                }
            }
        }
        SectionHeader("순위 조각", padded: true)
        InsetGroup {
            GroupRow(divider: .inset(16)) {
                RubyBalanceChip(37, style: .toolbar)
                Spacer()
                GalleryCaption(text: "도구 막대 알약")
            }
            GroupRow(divider: .none) {
                ForEach(1...4, id: \.self) { RankBadge(rank: $0) }
                Spacer(minLength: 4)
                ForEach(["코랄", "하늘", "모래", "도윤"], id: \.self) { PersonAvatar(name: $0, size: 28) }
            }
        }
    }
}

// MARK: 3 — 그룹 · 막대 · 유리 · 시트 머리

private struct GalleryPageGroups: View {
    var body: some View {
        SheetHeader("새 대화", subtitle: "지금 근무 중 6명", onClose: {})
            .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
        SectionHeader("팀별 이번 주", trailing: .action("1인당 평균", {}), padded: true)
        InsetGroup {
            leagueRow(rank: 1, name: "새벽 커피단", value: "25시간 07분", fraction: 0.63, style: .accent, mine: false)
            leagueRow(rank: 2, name: "아잉 데모팀", value: "22시간 07분", fraction: 0.55, style: .gauge, mine: true)
            leagueRow(rank: 3, name: "구름 공방", value: "40시간 30분", fraction: 1.0, style: .done, mine: false, last: true)
        }
    }

    private func leagueRow(rank: Int, name: String, value: String, fraction: Double, style: ProgressBar.Style, mine: Bool, last: Bool = false) -> some View {
        GroupRow(divider: last ? .none : .inset(52), minHeight: 64, isHighlighted: mine) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    RankBadge(rank: rank)
                    PersonName(name, center: "seoul", isMe: false)
                    if mine { AingChip(text: "우리 팀", outlined: true) }
                    Spacer(minLength: 4)
                    Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(MobileTheme.label)
                }
                HStack(spacing: 10) {
                    ProgressBar(fraction, style: style)
                    Text("\(Int(fraction * 100))%").font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(MobileTheme.label2)
                }
                .padding(.leading, 34)
            }
        }
    }
}

// MARK: 4 — 잔디

private struct GalleryPageGrass: View {
    private static func sample(seed: Int, activity: Double) -> ContributionGridData {
        var state = UInt64(seed)
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1000) / 1000
        }
        let levels: [[Int?]] = (0..<12).map { week in
            (0..<7).map { day in
                if week == 11 && day > 3 { return nil }
                let roll = next()
                if day >= 5 { return roll > 0.8 ? 1 : 0 }
                return roll < 1 - activity ? 0 : min(4, 1 + Int(roll * 4.2))
            }
        }
        return ContributionGridData(weeks: 12, levels: levels)
    }

    var body: some View {
        SectionHeader("기록", trailing: .text("잔디 둘 한눈에"), padded: true)
        AingCard {
            ContributionGridPair {
                ContributionGrid(title: "최근 12주 근무", axis: .work, data: Self.sample(seed: 7, activity: 0.8))
            } second: {
                ContributionGrid(title: "최근 12주 AI 토큰", axis: .token, data: Self.sample(seed: 11, activity: 0.7))
            }
        }
        SectionHeader("빈 기록 · 불러오는 중 · 실패", padded: true)
        AingCard {
            ContributionGridPair {
                ContributionGrid(title: "최근 12주 근무", axis: .work, data: .blank())
            } second: {
                ContributionGrid(title: "최근 12주 AI 토큰", axis: .token, data: .blank(), phase: .loading)
            }
            ContributionGridPair {
                ContributionGrid(title: "최근 12주 근무", axis: .work, data: .blank(), phase: .failed, retry: {})
            }
            ContributionLegend(axis: .work)
        }
    }
}

// MARK: 5 — 큰 글자

private struct GalleryPageLargeText: View {
    var body: some View {
        AingCard {
            HStack(spacing: 12) {
                CharacterPortrait(id: "fox", mood: .working, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("맥에서 근무 중").font(.headline).foregroundStyle(MobileTheme.working)
                    Text("이번 세션 10:20부터").font(.footnote).foregroundStyle(MobileTheme.label2)
                }
            }
            Text("5:10:00").scaledFont(size: 48, weight: .semibold).monospacedDigit().foregroundStyle(MobileTheme.label)
            ViewThatFits(in: .horizontal) {
                HStack { RubyBalanceChip(47, style: .large); RubyPrice(80, balance: 47); RubyGain(20, suffix: "받음", style: .chip) }
                VStack(alignment: .leading) { RubyBalanceChip(47, style: .large); RubyPrice(80, balance: 47); RubyGain(20, suffix: "받음", style: .chip) }
            }
            AingButton("캐릭터 바꾸기", systemImage: "person", kind: .tinted, size: .md, fillsWidth: true) {}
        }
        InsetGroup {
            GroupRow(divider: .inset(60)) {
                PersonAvatar(name: "민트", status: .working, size: 32)
                PersonName("민트", center: "seoul", isMe: true)
            }
            GroupRow(divider: .none) {
                RankBadge(rank: 1)
                PersonName("아주 긴 이름을 가진 팀원", center: "busan")
            }
        }
        AingCard {
            ContributionGridPair {
                ContributionGrid(title: "최근 12주 근무", axis: .work, data: .blank())
            } second: {
                ContributionGrid(title: "최근 12주 AI 토큰", axis: .token, data: .blank())
            }
        }
    }
}

// MARK: 탭 막대 숨김 실측

private struct GalleryTabBarProbe: View {
    let step: Int
    @State private var path: [Int] = []
    @State private var sheet = false

    var body: some View {
        TabView {
            NavigationStack(path: $path) {
                List {
                    Text("목록 화면 — 탭 막대 보임")
                    NavigationLink("대화 열기", value: 1)
                }
                .navigationTitle("메시지")
                .navigationDestination(for: Int.self) { _ in
                    VStack(spacing: 16) {
                        Text("대화 화면 — 탭 막대 숨김").font(.headline).foregroundStyle(MobileTheme.label)
                        Text("단계 \(step)").foregroundStyle(MobileTheme.label2)
                        Spacer()
                        Text("아래 끝").foregroundStyle(MobileTheme.label2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(MobileTheme.background)
                    .hidesTabBar(for: .conversation)
                    .sheet(isPresented: $sheet) {
                        SheetHeader("시트", onClose: { sheet = false })
                        Spacer()
                    }
                }
            }
            .tabItem { Label("메시지", systemImage: "bubble.left") }
            Text("다른 탭").tabItem { Label("나", systemImage: "person") }
        }
        .task {
            guard step > 0 else { return }
            try? await Task.sleep(for: .milliseconds(600))
            path = [1]
            if step == 2 {
                try? await Task.sleep(for: .milliseconds(900))
                sheet = true
                try? await Task.sleep(for: .milliseconds(1200))
                sheet = false
            } else if step == 3 {
                try? await Task.sleep(for: .milliseconds(1200))
                path = []
            }
        }
    }
}
#endif
