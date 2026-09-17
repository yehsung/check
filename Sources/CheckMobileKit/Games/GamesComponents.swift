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

/// 오른쪽 위 루비 잔량 유리 알약(시안 `.b-gpill`) — 누르면 상점. iOS 26 은 도구 막대가 유리를 입히므로 알맹이만,
/// 그 전 버전은 공용 유리 바탕을 직접 두른다.
struct GamesToolbarRubyPill: View {
    let balance: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if #available(iOS 26, *) {
                label.padding(.horizontal, 4)
            } else {
                label
                    .padding(.leading, 10)
                    .padding(.trailing, 14)
                    .frame(minHeight: GamesTouchTarget.minimum)
                    .background(GlassBackground(shape: Capsule()))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(balance.map { "루비 \($0)개" } ?? "루비 잔액 모름"))
        .accessibilityHint(Text(GamesText.rubyPillHint))
    }

    private var label: some View {
        HStack(spacing: 6) {
            RubyIcon(size: 22, scalesWithText: false)
            Text(balance.map { "\($0)" } ?? "–")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label)
        }
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

/// "지금 대결 중" 한 줄(게임 탭 · 오목 로비 같은 모양): 두 얼굴 vs · 이름 둘 · 판돈 [보석]10 · 1분 35초째.
struct GamesLiveMatchRow: View {
    let store: GamesStore
    let live: GomokuLiveMatch
    var isLast = true

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding)) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    faces
                    texts
                }
            } else {
                faces
                texts
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var faces: some View {
        HStack(spacing: 8) {
            PersonAvatar(name: live.a.displayName, colorSeed: live.a.id, url: live.a.avatarLink, size: 30)
            Text("vs")
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            PersonAvatar(name: live.b.displayName, colorSeed: live.b.id, url: live.b.avatarLink, size: 30)
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
