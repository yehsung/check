#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// 게임 탭 안에서만 쓰는 조각(w15 G — 시안 B 07·08·09). 공용 부품(Components)은 고치지 않는다 — 두 탭 이상이 같은 것을 만들면
// 통합 때 승격한다(후보: `GamesNavTitle` · `GamesToolbarRubyPill` · `GamesStakeLine`).

/// 게임 탭 누름 영역의 최소 한 변(pt) — HIG 44×44. 수락·거절처럼 붙은 버튼이 작으면 잘못 눌러 판돈이 걸린다
/// (games-verify: 기본 글자에서 수락 35pt · 빠른 문구 31pt 실측).
enum GamesTouchTarget {
    static let minimum: CGFloat = 44
}

// MARK: - 나

/// 게임 화면이 그리는 '나' — 착용 캐릭터 · 표정(근무 상태) · 이름. **새 서버 호출 없이** 다른 탭 스토어가 이미 아는 값만 읽는다.
///
/// - 착용: 나 탭이 알아 왔으면 그 값, 아니면 위젯 스냅샷에 남은 지난 값(모르면 아잉 — `CharacterPortrait` 가 접는다).
/// - 표정: 지금 탭 내 카드(근무 중 · 연결 끊김 · 안 함) → 스냅샷 상태 → 모르면 링 없는 기본 얼굴.
/// - 이름: 나 탭 프로필 → 지금 탭 팀 목록의 내 행 → 없으면 nil(부르는 쪽이 "나"로).
@MainActor
struct GamesMeIdentity {
    let name: String?
    let characterID: String?
    let mood: CharacterMood

    static func current(_ context: MobileContext) -> GamesMeIdentity {
        let me = context.links.me
        let now = context.links.now
        let snapshot = context.widgetSnapshots.current
        let characterID = (me?.equippedLoaded == true) ? me?.equippedCharacterID : snapshot?.resolvedCharacterID
        let mood: CharacterMood
        if let card = now?.myCard(now: context.clock.now()) {
            mood = card.isWorking ? (card.isStale ? .lost : .working) : .off
        } else if let state = snapshot?.me?.resolvedStatus {
            mood = CharacterMood(state)
        } else {
            mood = .plain
        }
        let rawName = me?.displayName ?? now?.myStatus?.name
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GamesMeIdentity(name: (name?.isEmpty ?? true) ? nil : name, characterID: characterID, mood: mood)
    }

    /// 공용 순위 행 얼굴(`RankRowFace`)에 넘길 짝.
    var rankFace: (id: String?, mood: CharacterMood) { (characterID, mood) }
}

extension GomokuUser {
    /// 로비·신청 행의 아바타 점(근무 중만 — 근무 안 함은 점 없음, 시안 B).
    var presence: PresenceStatus? { isWorking ? .working : nil }
    /// 오목 판 위 상대 초상의 표정.
    var mood: CharacterMood { isWorking ? .working : .off }
    var avatarLink: URL? { avatarURL.flatMap(URL.init(string:)) }
}

// MARK: - 내비게이션 머리

/// 가운데 제목 + 부제 한 줄(시안 `.b-nav-title`). 부제에 보석 같은 그림이 들어가 `navigationSubtitle`(iOS 26 전용 · 글자만) 대신 쓴다.
struct GamesNavTitle<Subtitle: View>: View {
    let title: String
    @ViewBuilder var subtitle: Subtitle

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
            HStack(spacing: 3) { subtitle }
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
                .lineLimit(1)
                .monospacedDigit()
        }
        // 내비 막대 높이는 늘지 않는다 — 접근성 크기에서 두 줄이 막대를 넘치지 않게 상한을 둔다.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 판돈 한 줄 "판돈 [보석]5 · 이기면 +5"(내비 부제 · 신청 행 부제 · 대결 중 행).
struct GamesStakeLine: View {
    let stake: Int
    var prefix: String? = GomokuPhoneText.stakeTitle
    var suffix: String?
    var gemSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            if let prefix { Text(prefix + " ") }
            RubyIcon(size: gemSize)
            Text(suffix.map { "\(stake)" + $0 } ?? "\(stake)")
                .monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(prefix ?? "") 루비 \(stake)\(suffix ?? "")"))
    }
}

/// 오른쪽 위 루비 잔량 유리 알약(시안 `.b-gpill`) — 누르면 상점.
///
/// 도구 막대 유리 이중 겹침(iOS 26 은 막대가 스스로 유리를 두른다)은 공용 `RubyBalanceChip(.toolbar)` 가 안다 —
/// 게임 탭과 나 탭 상점이 각자 같은 분기를 쓰던 것을 통합 때 한 벌로 승격했다.
struct GamesToolbarRubyPill: View {
    let balance: Int?
    let action: () -> Void

    var body: some View {
        RubyBalanceChip(balance, style: .toolbar, hint: GamesText.rubyPillHint, action: action)
    }
}

// MARK: - 오목 조각

/// 나무판 썸네일(시안 `.b-woodthumb` 60pt) — 판 그림과 같은 나무·돌.
struct GamesWoodThumbnail: View {
    var side: CGFloat = 60

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: rect, cornerRadius: side * 0.2, style: .continuous),
                         with: .linearGradient(Gradient(colors: [GamesGomokuBoardCanvas.woodLight, GamesGomokuBoardCanvas.woodDark]),
                                               startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            let lines = 11
            let inset = side * 0.12
            let cell = (side - inset * 2) / CGFloat(lines - 1)
            var grid = Path()
            for i in 0..<lines {
                let offset = inset + CGFloat(i) * cell
                grid.move(to: CGPoint(x: offset, y: inset))
                grid.addLine(to: CGPoint(x: offset, y: side - inset))
                grid.move(to: CGPoint(x: inset, y: offset))
                grid.addLine(to: CGPoint(x: side - inset, y: offset))
            }
            context.stroke(grid, with: .color(GamesGomokuBoardCanvas.lineColor.opacity(0.55)), lineWidth: 0.5)
            let stones: [(Int, Int, GomokuColor)] = [(5, 5, .black), (6, 4, .white), (4, 6, .black), (6, 6, .white), (5, 3, .black)]
            for (x, y, color) in stones {
                let center = CGPoint(x: inset + CGFloat(x) * cell, y: inset + CGFloat(y) * cell)
                GamesGomokuBoardCanvas.drawStone(&context, at: center, radius: cell * 0.48, color: color, opacity: 1)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// 관전 입구 문구(0.3.41) — **[관전] 칩이 쓰는 것만** 여기 둔다. 관전 화면 안의 문구는 관전 화면이 자기 텍스트 파일에서 더한다
/// (공용 `GamesText.swift` 를 여럿이 같이 고치면 충돌한다). 낱말은 맥과 같다(`GomokuText.watch` · `watchHelp` · `myMatch`).
extension GomokuPhoneText {
    /// 로비 "지금 대결 중" 행의 [관전] 알약.
    package static let watchChip = "관전"
    package static let watchChipHint = "이 판을 지켜봐요"
    /// 내 판이면 칩 대신 서는 캡션(누를 수 없다 — 내 판은 관전에 못 들어간다).
    package static let myMatchCaption = "내 판"
    /// 서버에 관전이 아직 없으면 칩 대신 서는 캡션. **짧게** 둔 것이 핵심이다 — 칩 자리는 얼굴 둘·이름·판돈 다음의 좁은 끝이라
    /// 긴 문장을 넣으면 이름 줄이 낱글자로 꺾인다. 보이스오버는 대신 온전한 문장(`GomokuNoticeText.watchUnavailable`)을 읽는다. 폰
    package static let watchSoonCaption = "곧 열려요"
}

/// "지금 대결 중" 한 줄(게임 탭 · 오목 로비 같은 모양): 두 얼굴 vs · 이름 둘 · 판돈 [보석]10 · 1분 35초째.
///
/// 오른쪽 [관전] 칩(0.3.41)은 `showsWatch` 를 켠 호출부에만 붙는다 — 관전 화면은 **오목 로비 자리에만** 서므로, 게임 허브에서 누르면
/// 아무 일도 안 일어난 것처럼 보인다(관전 상태만 조용히 서고 화면은 그대로). 그래서 입구는 오목 로비 하나다
/// (맥도 같은 관례다 — `GomokuLiveMatchCard.onWatch` "nil 이면 칩이 없다").
struct GamesLiveMatchRow: View {
    let store: GamesStore
    let live: GomokuLiveMatch
    var isLast = true
    /// 관전 입구를 붙이는가. 기본 false — 오목 로비만 켠다(위 머리말).
    var showsWatch = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding)) {
            if typeSize.isAccessibilitySize {
                // 큰 글자: 폭을 재보지 않고 곧장 세로 — 상대 고르기 행([도전])이 겪은 그것(한 줄에 두면 이름이 낱글자로 꺾인다).
                //
                // ★ 아래 '좁은 폭' 갈래와 조건이 겹칠 때는 **이 갈래가 이긴다**(먼저 본다). 그래도 둘이 싸우지 않는 이유는
                //   조건을 갈라 둔 게 아니라 **결론을 하나로 둔** 것이다 — 두 갈래의 접힌 꼴이 같은 `stacked` 뷰다.
                stacked
            } else if hasWatchEntry {
                // 칩이 붙는 행만 폭을 재본다. **왜 틀렸었나**: [관전] 칩(52.0pt)이 붙으면서 판돈·경과 줄에 남는 폭이
                // 142.5 → 78.5pt 로 줄었는데 그 줄이 필요한 폭은 128.4pt 다(320pt Display Zoom · 기본 글자 CoreText 실측 —
                // 판돈 58.1 + " · 1분 35초째" 70.2). 판돈도 경과도 줄임표로 잘려 **관전 입구 옆에서 판돈을 못 읽었다.**
                // 375pt 에서도 남는 폭이 133.5pt 뿐이라, 판이 1시간을 넘겨 " · 1시간 22분째"(81.0 → 필요 139.1)가 되는 순간
                // 같은 잘림이 시작된다. 칩이 붙기 전 이 줄은 142.5pt 를 쓰고 있었다 — **잘림은 칩 때문에 처음 생겼다.**
                //
                // 아래 첫 후보(`inline`)의 이상 폭은 실제 한 줄 배치와 **같은 식**(얼굴 89.5 + 칩 + 간격 36 + 글)이라,
                // 이 재보기는 곧 "글 묶음이 자기 이상 폭을 받는가" 다 — 잘릴 때만 접히고, 들어가면 전과 똑같이 한 줄로 선다
                // (320pt 접힘 · 375pt 한 줄 · 1시간 넘긴 375pt 접힘 · 393pt 한 줄).
                ViewThatFits(in: .horizontal) {
                    inline
                    stacked
                }
            } else {
                // 허브(게임 탭 '지금 대결 중')는 칩 없이 같은 행을 쓴다 — 글에 남는 폭이 142.5pt 라 잘리지 않으므로
                // 재보지 않고 전과 똑같은 한 줄이다(칩이 없는 호출부의 모양을 이 수리가 바꾸지 않는다).
                inline
            }
        }
    }

    /// 한 줄 꼴: 두 얼굴 · 글 · 오른쪽 끝 칩 슬롯.
    ///
    /// 전에는 이 넷이 `GroupRow` 의 HStack(`spacing: space3`)에 바로 앉아 있었다. 같은 간격으로 묶기만 한 것이라 폭·정렬은
    /// 그대로고(간격 셋 = 36pt), `ViewThatFits` 후보가 되려면 하나의 뷰여야 해서 묶었다.
    /// `Spacer(minLength: 0)` 를 남겨 둔 것도 계산 때문이다 — 이상 폭에 0 으로 들어가서 위 재보기가 실제 배치와 같은 식이 된다.
    private var inline: some View {
        HStack(spacing: MobileTheme.space3) {
            faces
            texts
            Spacer(minLength: 0)
            watchEntry
        }
    }

    /// 세로로 접은 꼴: 칩이 글 아래 줄로 내려가고, 글 묶음이 행 내부 폭을 통째로 받는다(320pt 에서 256pt · 375pt 에서 311pt).
    /// 부제를 두 줄로 쪼개는 길도 있었지만 이쪽을 골랐다 — "판돈 10 · 1분 35초째"는 한 낱말처럼 읽히는 한 줄이고,
    /// 큰 글자 갈래가 이미 같은 꼴로 접고 있어서 **접는 방법을 한 벌로** 둘 수 있다(쪼개면 접는 꼴이 두 벌이 된다).
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            faces
            texts
            watchEntry
        }
    }

    /// 칩 슬롯이 실제로 뷰를 그리는가. 위 폭 재보기와 아래 `watchEntry` 가 **이 하나**를 본다 — 조건을 두 곳에 적으면
    /// 한쪽만 고쳐져 "빈 슬롯 때문에 줄을 접는" 꼴이 된다.
    ///
    /// 주 스위치가 꺼진 배선에서는 칩 자체를 두지 않는다 — `startWatching` 이 `spectatorFeaturesEnabled` 를 먼저 보고 조용히
    /// 돌아서므로(`GomokuStoreWatch.swift:68`) 눌러도 아무 일도 없는 버튼이 된다.
    private var hasWatchEntry: Bool { showsWatch && gomoku.spectatorFeaturesEnabled }

    private var faces: some View {
        HStack(spacing: 8) {
            PersonAvatar(name: live.a.displayName, colorSeed: live.a.id, url: live.a.avatarLink, userID: live.a.id, size: 30)
            Text("vs")
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            PersonAvatar(name: live.b.displayName, colorSeed: live.b.id, url: live.b.avatarLink, userID: live.b.id, size: 30)
        }
        .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(GomokuPhoneText.livePair(live))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 0) {
                    GamesStakeLine(stake: live.stake.rawValue)
                    Text(" · " + GomokuPhoneText.elapsedPhrase(store.context.clock.now().timeIntervalSince(live.startedAt)))
                        .monospacedDigit()
                }
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            }
        }
        // 합치기는 **이 글 묶음에만** 둔다(전에는 행 전체였다). 칩이 붙는 행에서 행 전체를 합치면 [관전]이 한 덩이에 삼켜져
        // 보이스오버가 누를 수 없다 — 상대 고르기 행(`GamesGomokuOpponentRow.info` + 제 몫의 `challengeButton`)과 같은 관례다.
        // 얼굴은 이미 `accessibilityHidden` 이라 **읽히는 말은 전과 같다**(이름 줄 + 판돈·경과 줄).
        .accessibilityElement(children: .combine)
    }

    /// 관전 입구: [관전] 틴트 알약(상대 고르기 행의 [도전]과 같은 모양·크기) — 누를 수 없는 두 경우(내 판 · 서버에 관전이
    /// 아직 없다)에는 칩 대신 **그 이유를 말하는 회색 캡션**이 같은 자리에 선다.
    @ViewBuilder
    private var watchEntry: some View {
        // 게이트는 `hasWatchEntry` 하나다(까닭은 그쪽 주석).
        if hasWatchEntry {
            if gomoku.isMine(live) {
                // 내 판은 관전에 들어갈 수 없다(스토어가 막는다 — `GomokuStoreWatch.swift:69`). 수락 직후·30초 로비 주기 사이에
                // 로비 목록에 내 판이 잠깐 보이는 틈이 있어, 이 자리를 비워 두면 "왜 내 판만 칩이 없나"로 읽힌다.
                Text(GomokuPhoneText.myMatchCaption)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
            } else if gomoku.watchUnavailable {
                // 서버에 **관전이** 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창). 맥과 같은 게이트다
                // (`GomokuPanel` 의 `canWatch: !store.watchUnavailable`).
                //
                // ★ 전에는 이 자리가 `rankingUnavailable` 이었고, 그것이 **우연히만** 맞았다. 그 깃발은 "순위표가 없다"와
                //   "관전이 없다"를 **겸업**하고 있었다 — 관전 404 가 그 깃발을 세웠기 때문이다(옛 `noteWatchFailure`).
                //   맥이 그 겸업을 풀어 "순위를 한 번이라도 받았으면 순위 깃발은 세우지 않는다"로 좁히자,
                //   **행을 들고 있는 사용자에게는 이 게이트가 영영 열려** [관전] 칩이 활성인 채 눌러도 조용히 접히고
                //   같은 카드를 계속 눌러 404 를 무한히 낼 수 있었다(맥에서 5번 눌러 5요청 실측). 그래서 관전 전용
                //   깃발(`watchUnavailable` — 관전 404 에 **조건 없이** 선다)로 옮겼다. [[client-gates-come-in-pairs]]
                //   문 앞 가드(`startWatching` 의 `guard !watchUnavailable`)가 화면을 안 지나는 길까지 막고,
                //   잠금은 60초 순위 폴이 한 번 풀어 준다(안 풀면 잠금이 자기를 못 연다 — `pollSpectatorFeatures` 주석).
                //
                // ★ 전에는 또렷한 [관전] 칩을 `.disabled` 로만 흐려 두었고, **보이는** 이유는 로비 **맨 아래** 순위 절 한 줄뿐이었다
                // (여기 있던 이유 문장은 `accessibilityHint` 라 보이스오버 전용이었고, 폰엔 호버 툴팁이 없다 — 저장소 메모
                // '자체 말풍선 툴팁'). 눈으로 보는 사용자는 화면 반대쪽 끝까지 내려가야 회색 칩의 이유를 알 수 있었다.
                // 그래서 칩을 빼고 그 자리에 이유를 글자로 둔다 — 바로 위 '내 판' 갈래와 같은 관용구다.
                //
                // 자리를 칩 슬롯으로 잡은 이유: 절 머리·바닥은 `GamesGomokuScreen.swift` 몫이라 이 부품에는 절당 한 번만
                // 말할 자리가 없다. 대신 캡션을 **짧게**(`watchSoonCaption`) 둬서, 판이 여러 줄이어도 같은 낱말이 한 열로 서는
                // **상태 열**로 읽히게 했다(긴 문장이 줄마다 반복되는 꼴을 피한다 — '내 판' 캡션과 같은 폭·같은 색).
                Text(GomokuPhoneText.watchSoonCaption)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
                    // 보이스오버에는 온전한 문장으로 — 짧게 자른 것은 눈으로 보는 폭 때문이지 뜻을 줄인 게 아니다.
                    .accessibilityLabel(Text(GomokuNoticeText.watchUnavailable))
            } else {
                AingButton(GomokuPhoneText.watchChip, kind: .tinted, size: .sm) {
                    gomoku.startWatching(matchID: live.id)
                }
                .fixedSize()
                .accessibilityHint(GomokuPhoneText.watchChipHint)
            }
        }
    }
}

extension View {
    /// 데모 스크린샷(`-AingCheckGamesDemo bottom`)에서만 스크롤을 맨 아래에서 시작한다. Release 에서는 아무것도 안 한다.
    @ViewBuilder
    func gamesDemoScrollAnchor(isDemo: Bool) -> some View {
        #if DEBUG
        if GamesDemoSeed.current(isDemo: isDemo) == .bottom {
            defaultScrollAnchor(.bottom)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
#endif
