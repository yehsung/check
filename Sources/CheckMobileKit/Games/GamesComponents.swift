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

/// 관전 입구 두 문구(0.3.41) — **[관전] 칩이 쓰는 것만** 여기 둔다. 관전 화면 안의 문구는 관전 화면이 자기 텍스트 파일에서 더한다
/// (공용 `GamesText.swift` 를 여럿이 같이 고치면 충돌한다). 낱말은 맥과 같다(`GomokuText.watch` · `watchHelp` · `myMatch`).
extension GomokuPhoneText {
    /// 로비 "지금 대결 중" 행의 [관전] 알약.
    package static let watchChip = "관전"
    package static let watchChipHint = "이 판을 지켜봐요"
    /// 내 판이면 칩 대신 서는 캡션(누를 수 없다 — 내 판은 관전에 못 들어간다).
    package static let myMatchCaption = "내 판"
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
                // 큰 글자: 칩을 아래 줄로 — 상대 고르기 행([도전])이 겪은 그것(한 줄에 두면 이름이 낱글자로 꺾인다).
                VStack(alignment: .leading, spacing: 6) {
                    faces
                    texts
                    watchEntry
                }
            } else {
                faces
                texts
                Spacer(minLength: 0)
                watchEntry
            }
        }
    }

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

    /// 관전 입구: [관전] 틴트 알약(상대 고르기 행의 [도전]과 같은 모양·크기) — 내 판이면 누를 수 없는 회색 캡션이다.
    @ViewBuilder
    private var watchEntry: some View {
        // 주 스위치가 꺼진 배선에서는 칩 자체를 두지 않는다 — `startWatching` 이 `spectatorFeaturesEnabled` 를 먼저 보고 조용히
        // 돌아서므로(`GomokuStoreWatch.swift:68`) 눌러도 아무 일도 없는 버튼이 된다.
        if showsWatch, gomoku.spectatorFeaturesEnabled {
            if gomoku.isMine(live) {
                // 내 판은 관전에 들어갈 수 없다(스토어가 막는다 — `GomokuStoreWatch.swift:69`). 수락 직후·30초 로비 주기 사이에
                // 로비 목록에 내 판이 잠깐 보이는 틈이 있어, 이 자리를 비워 두면 "왜 내 판만 칩이 없나"로 읽힌다.
                Text(GomokuPhoneText.myMatchCaption)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
            } else {
                AingButton(GomokuPhoneText.watchChip, kind: .tinted, size: .sm) {
                    gomoku.startWatching(matchID: live.id)
                }
                // 서버에 순위·관전이 아직 없으면(PGRST202 — 앱이 먼저 나간 창) 잠근다. 맥과 같은 게이트다
                // (`GomokuStore.swift:654` "화면은 '순위는 곧 열려요'로 접고 [관전] 칩을 잠근다").
                .disabled(gomoku.rankingUnavailable)
                .fixedSize()
                .accessibilityHint(gomoku.rankingUnavailable ? GomokuNoticeText.watchUnavailable : GomokuPhoneText.watchChipHint)
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
