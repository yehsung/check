import SwiftUI
import CheckCore

// MARK: - 아잉 마작 창 루트 (설계서 mj/SPEC.md §5)
//
// 화면: 로비(방 포함) · 판(루비 판·연습판 한 길 — `store.table`) · 국 결과·판 결과(판 위 카드) · 규칙(덮개) · 시트(방 만들기·연습 시작).
//
// ── 이 화면이 지키는 것 ──
//  · **단추·버릴 수 있는 패는 `store.myDecision` 에 있는 것만** — 클라 판정으로 켜지 않는다(SPEC §4 머리). 판·부·점수는 늘 서버 값.
//  · 숨은 정보는 서버가 이미 걷었다 — 남의 손은 `hand_count` 뒷면뿐, 울기 창(`wait`)에는 누구에게도 표시가 없다(UX:148).
//  · 초 단위 값(내 시계 · 남은 초 · "기다리는 중…")은 잎 뷰(`MahjongTick`)만 읽는다 — 창 루트가 매초 다시 그려지지 않게(⑦).
//  · 시각은 `store.clock()` 하나 — 렌더 시험이 시계를 고정한다. 서버 ms → 기기 시각은 `store.serverClockOffset` 로 옮긴다(②).
//  · 문구: 서버 응답 문구는 스토어 `notice`(코어 `MahjongNoticeText`), 화면 고정 글자는 `MahjongText` 한 곳. 진단 어휘 금지.
//  · 상태는 스토어 칸만 읽는다(렌더 시험은 `applyState`·`applyLobby`·`package internal(set)` 칸으로 심는다 — 주입구 없음).
//    렌더 전용 인자는 덮개(`previewOverlay`)·호버(`previewHoverIndex`)·로비 탭뿐이다.

/// 화면 고정 글자 — 서버 응답 문구는 여기 두지 않는다(스토어 `notice`).
enum MahjongText {
    static var title: String { MahjongInviteText.gameName }
    static let subtitle = "리치 마작 4인 대국 — 가장 널리 쓰이는 온라인 리치 마작 규칙과 같아요"
    static let rules = "규칙"
    static let yaku = "역"
    static let scoreTable = "점수표"
    static let close = "닫기"
    static let practice = "혼자 연습"
    static let usersTab = "사람"
    static let rankTab = "순위"
    static let invite = "초대"
    static let invited = "초대함"
    static let join = "참가"
    static let decline = "거절"
    static let emptyUsers = "함께할 사람이 아직 없어요"
    static let loadingUsers = "사람 목록을 불러오는 중…"
    static let inMatchChip = "대국 중"
    static let outdatedChip = "업데이트 필요"
    static let focusChip = "집중 모드"
    static let workingChip = "근무 중"
    static let invitesTitle = "받은 초대"
    static let publicRoomsTitle = "공개 방"
    static let noJoinables = "받은 초대나 열린 공개 방이 없어요"
    static let createTitle = "방 만들기"
    static let createButton = "만들기"
    static let createHint = "판돈은 시작할 때 모두에게서 걷고, 등수대로 나눠 가져요."
    static let stakeLabel = "판돈"
    static let formatLabel = "판 길이"
    static let publicLabel = "공개"
    static let publicOn = "누구나 참가"
    static let publicOff = "초대한 사람만"
    static let myRoomTitle = "내 방"
    static let start = "시작"
    static let leave = "나가기"
    static let emptySeat = "빈자리"
    static let hostTag = "방장"
    static let invitedTag = "초대 중"
    static let joinedTag = "참가"
    static let needFour = "4명이 모여야 시작해요"
    static let unseenDrop = "앱을 끈 사람은 시작할 때 빠져요"
    static let waitingHost = "방장이 시작하기를 기다리고 있어요"
    static let noRoomHint = "[초대]를 누르면 방이 열리고 바로 불러요 · 방에서 넷째를 기다리며 혼자 연습할 수 있어요"
    static let roomViewButton = "방 보기"
    static let practiceViewButton = "연습판 보기"
    static let practiceTitle = "혼자 연습"
    static let practiceTimedOff = "넉넉히"
    static let practiceTimedOn = "실전처럼 5+20"
    static let practiceTimeLabel = "생각 시간"
    static let practiceSeatNote = "내 자리는 무작위예요"
    static let practiceNoRuby = "연습판은 루비·기록이 없어요"
    static let practiceStart = "연습 시작"
    static let practiceAgain = "다시 하기"
    static let practiceEnd = "연습 끝내기"
    static let comeBack = "돌아왔어요"
    static let awayHint = "자리 비움 — 차례가 오면 저절로 버려요"
    static let autoChip = "자동"
    static let deletedChip = "탈퇴"
    static let dealerChip = "친"
    static let riichiChip = "리치"
    static let waitingOthers = "기다리는 중…"
    static let wallRemaining = "남은 패"
    static let tsumo = "쯔모"
    static let ron = "론"
    static let riichi = "리치"
    static let kan = "깡"
    static let kanMore = "깡 ▸"
    static let kyuushu = "구종구패"
    static let pon = "퐁"
    static let chi = "치"
    static let pass = "넘기기"
    static let cancel = "취소"
    static let riichiArmedHint = "리치 — 버릴 패를 고르세요(밝은 패만)"
    static let kuikaeHint = "방금 운 패와 같은 패는 이번에 못 버려요"
    static let noYakuHint = "역 없음 — 쯔모나 리치로만 화료"
    static let furitenChip = "후리텐 — 론 불가, 쯔모만"
    static let waitsTitle = "기다리는 패"
    static let reserve = "예비"
    static let toLobby = "로비로"
    static let rematch = "한 판 더"
    static let crampedNotice = "화면이 좁아 마작 판이 잘려요"
    static let updateRequired = "앱을 업데이트해 주세요"
    static let unavailable = MahjongNoticeText.unavailable
    static let aidAutoWin = "자동 화료"
    static let aidNoCalls = "울지 않기"
    static let aidTsumogiri = "쯔모기리"
    static let recordUnranked = "10판부터 순위"
    static let rankHeader = "평균 등수 순 · 10판 이상"
    static let emptyRanking = "아직 10판을 채운 사람이 없어요"
    static let gamesUntilRanked = "판 더 하면 순위에 올라요"
    static let firstTimeTitle = "처음이에요"

    static func record(avg: Double?, games: Int) -> String {
        guard games >= MahjongRules.rankingMinGames, let avg else { return "\(games)판 · \(recordUnranked)" }
        return String(format: "평균 %.2f등 · %d판", avg, games)
    }

    static func stake(_ stake: Int?) -> String { "판돈 \(stake ?? 0)" }
    static func seats(_ joined: Int) -> String { "\(joined)/4명" }
    static func roomOf(_ name: String) -> String { "\(name)님의 방" }
    static func inviteFrom(_ name: String) -> String { "\(name)님이 초대했어요" }
    static func format(_ format: MahjongFormat?) -> String {
        switch format {
        case .hanchan: "반장전"
        default: "동풍전"
        }
    }

    static func formatDetail(_ format: MahjongFormat) -> String {
        switch format {
        case .tonpuu: "동장 4국(기본)"
        case .hanchan: "동장·남장 8국"
        }
    }

    static let windNames = ["동", "남", "서", "북"]
    static let windGlyphs = ["東", "南", "西", "北"]

    static func wind(_ wire: String?) -> String {
        switch wire {
        case "E": "동"
        case "S": "남"
        case "W": "서"
        case "N": "북"
        default: "—"
        }
    }

    /// "동 1국".
    static func roundName(round: Int?, handNo: Int?) -> String {
        let r = windNames[max(0, min(3, round ?? 0))]
        return "\(r) \((handNo ?? 0) + 1)국"
    }

    static func honba(_ honba: Int?, kyotaku: Int?) -> String { "\(honba ?? 0)본장 · 공탁 \(kyotaku ?? 0)" }
    static func wall(_ count: Int?) -> String { "\(wallRemaining) \(count ?? 0)" }

    static func score(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.grouping(.automatic))
    }

    static func delta(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : (value < 0 ? "−\((-value).formatted())" : "0")
    }

    static func net(_ value: Int) -> String {
        value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0")
    }

    static func rank(_ rank: Int?) -> String { rank.map { "\($0)위" } ?? "—" }
    static func avgRank(_ avg: Double?) -> String { avg.map { String(format: "평균 %.2f등", $0) } ?? "—" }
    static func remaining(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
    static func nextHand(_ seconds: Int) -> String { "다음 국까지 \(seconds)초" }
    static func backIn(_ seconds: Int) -> String { "\(comeBack) · \(seconds)초" }

    /// "방 3/4 · 남은 7:12".
    static func roomBand(joined: Int, seconds: Int) -> String { "방 \(joined)/4 · 남은 \(remaining(seconds))" }
    static let roomBandReady = "4명이 모였어요"

    /// 분배 안내(카드 ② — `[3N, N, 0, 0]` 지급, 순수익 +2N · 0 · −N · −N). 실제 분배는 서버, 결과 화면은 서버 값만.
    static func split(stake: Int) -> String {
        "1위 +\(stake * 2) · 2위 본전 · 3·4위 −\(stake)"
    }

    static func handEnd(_ reason: String?) -> String {
        switch reason {
        case "exhaustive": "황패 유국"
        case "kyuushu": "구종구패 유국"
        case "suufon": "사풍연타 유국"
        case "suukaikan": "사개깡 유국"
        case "suucha_riichi": "사가 리치 유국"
        case "nagashi": "유국만관"
        default: "유국"
        }
    }

    static func matchEnd(_ reason: String?) -> String {
        switch reason {
        case "tobi": "점수가 0 아래로 내려간 사람이 나와 끝났어요"
        case "agari_yame", "tenpai_yame": "마지막 국의 친이 1위로 끝냈어요"
        case "target_reached": "연장에서 30000점을 넘은 사람이 나와 끝났어요"
        case "max_round": "마지막 국까지 마쳤어요"
        case "void": "판이 무효가 되어 판돈을 돌려줬어요"
        default: "판이 끝났어요"
        }
    }

    static func limitName(_ limit: String?) -> String? {
        switch limit {
        case "mangan": "만관"
        case "haneman": "하네만"
        case "baiman": "배만"
        case "sanbaiman": "삼배만"
        case "yakuman": "역만"
        default: nil
        }
    }
}

/// 로비 왼쪽 열 탭.
enum MahjongLobbyTab: Equatable { case users, ranking }

/// 덮개(한 번에 하나).
enum MahjongOverlay: Equatable {
    case rules(MahjongRulesTab)
    case createRoom
    case practiceStart
    /// '처음이에요' 4장(§5.7) — `launch` 가 있으면 다 본 뒤 그 연습판을 연다(연습 시작에서 왔다), nil 이면 [규칙]에서 다시 보기.
    case firstTime(page: Int, launch: MahjongPracticeLaunch?)
}

/// 규칙 창 탭.
enum MahjongRulesTab: Equatable { case rules, yaku, scores }

/// 화면 고르기(순수 — 시험이 되묻는다).
enum MahjongScreen: Equatable {
    case unavailable
    case lobby
    case table

    /// `dismissedMatchID` = 판 결과에서 [로비로]를 누른 판(그 판이 finished 로 남아 있어도 로비를 보인다).
    @MainActor
    static func of(_ store: MahjongStore, dismissedMatchID: String? = nil) -> MahjongScreen {
        if store.availability != .available, !store.isPractice { return .unavailable }
        if store.isPractice { return .table }
        if let match = store.match?.match, store.match?.mySeat != nil,
           match.matchStatus == .active || (match.matchStatus == .finished && match.id != dismissedMatchID) {
            return .table
        }
        return .lobby
    }
}

/// 시각 도우미 — 서버 ms → 기기 시각(②).
@MainActor
enum MahjongClockMath {
    static func local(_ ms: Double?, store: MahjongStore) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1_000 + store.serverClockOffset)
    }
}

// MARK: - 창 루트

struct MahjongPanel: View {
    let store: MahjongStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다 — 체스·큐브와 같은 얼굴 값).
    var me: @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback }
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳. nil 이면 이니셜로 떨어진다.
    var safety: WorkTimerStore? = nil
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용 덮개 · 호버 · 로비 탭(앱은 nil).
    var previewOverlay: MahjongOverlay? = nil
    var previewHoverIndex: Int? = nil
    var previewLobbyTab: MahjongLobbyTab? = nil
    /// '처음이에요'를 봤는지 적는 곳(앱 = 표준 · 시험 = 시험 전용 스위트).
    var guideDefaults: UserDefaults = .standard
    /// 반응 말풍선 공급기 — nil 이면 창 루트가 자기 것을 쥔다(렌더 시험은 미리 먹인 것을 넘긴다).
    var reactionFeed: MahjongReactionFeed? = nil
    /// 스냅샷 전용: 말풍선·움직임을 이 시각 한 장으로 그린다(앱은 nil — 살아 있는 시계).
    var previewNow: Date? = nil

    @State private var overlay: MahjongOverlay?
    @State private var lobbyTab: MahjongLobbyTab = .users
    /// 판 결과에서 [로비로]·[한 판 더]를 누른 판 id(스토어는 그 판을 들고 있어도 화면은 로비로).
    @State private var dismissedMatchID: String?
    @State private var ownReactionFeed = MahjongReactionFeed()
    @Environment(\.mahjongCramped) private var cramped

    private var shownOverlay: MahjongOverlay? { previewOverlay ?? overlay }

    var body: some View {
        let screen = MahjongScreen.of(store, dismissedMatchID: dismissedMatchID)
        ZStack(alignment: .topLeading) {
            switch screen {
            case .table:
                if let payload = store.table {
                    MahjongTableView(store: store, payload: payload, me: me(), hoverIndex: previewHoverIndex,
                                     feed: reactionFeed ?? ownReactionFeed, fixedNow: previewNow,
                                     onRules: { overlay = .rules($0) },
                                     onToLobby: { dismissedMatchID = payload.match?.id },
                                     onRematch: { dismissedMatchID = payload.match?.id; overlay = .createRoom })
                        // 받은 팔레트가 바뀌면(세션에 많아야 한 번) 패 띠를 새 색으로 다시 그린다.
                        .id(MahjongArt.shared.paletteRevision)
                        .frame(width: MahjongMatchLayout.bodySize.width, height: MahjongMatchLayout.bodySize.height,
                               alignment: .topLeading)
                        .offset(x: MahjongMatchLayout.bodyOrigin.x, y: MahjongMatchLayout.bodyOrigin.y)
                }
            case .lobby, .unavailable:
                VStack(alignment: .leading, spacing: MahjongWindowLayout.headerSpacing) {
                    MahjongLobbyHeader(store: store, cramped: cramped,
                                       onPractice: { overlay = .practiceStart },
                                       onRules: { overlay = .rules(.rules) })
                        .frame(height: MahjongWindowLayout.headerHeight)
                    if screen == .unavailable {
                        MahjongUnavailableView(availability: store.availability)
                            .frame(width: MahjongWindowLayout.innerWidth, height: MahjongWindowLayout.bodyHeight)
                    } else {
                        MahjongLobbyView(store: store, me: me(), tab: previewLobbyTab ?? lobbyTab,
                                         onSelectTab: { lobbyTab = $0 },
                                         onCreate: { overlay = .createRoom },
                                         onPractice: { overlay = .practiceStart },
                                         clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                            .frame(width: MahjongWindowLayout.innerWidth, height: MahjongWindowLayout.bodyHeight,
                                   alignment: .topLeading)
                    }
                }
                .padding(MahjongWindowLayout.contentPadding)
            }
            if let shown = shownOverlay {
                MahjongOverlayHost(store: store, overlay: shown, onClose: { closeOverlay(shown) },
                                   onSwitchRules: { overlay = .rules($0) },
                                   onStartPractice: startPractice,
                                   onGuidePage: { page in
                                       if case .firstTime(_, let launch) = shown { overlay = .firstTime(page: page, launch: launch) }
                                   },
                                   onReopenGuide: { overlay = .firstTime(page: 0, launch: nil) })
            }
        }
        .frame(width: MahjongWindowLayout.contentSize.width, height: MahjongWindowLayout.contentSize.height,
               alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        // 툴팁 말풍선 레이어 — 창 루트 하나(새 창 루트에는 이 한 줄이 반드시 있어야 말풍선이 뜬다).
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표(짝 — 남의 시험이 센다, §4.6 #23).
        .appUserAvatarCharacters(from: safety)
        .onChange(of: lobbyTab) { _, tab in
            if tab == .ranking { Task { await store.refreshRanking() } }
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .playing, overlay == .createRoom || overlay == .practiceStart { overlay = nil }
        }
    }

    /// [연습 시작] — 처음이면 '처음이에요' 4장 뒤에 연다(§5.7).
    private func startPractice(_ launch: MahjongPracticeLaunch) {
        if let guide = MahjongFirstTimeGuide.overlayBeforePractice(launch, defaults: guideDefaults) {
            overlay = guide
            return
        }
        overlay = nil
        store.startPractice(format: launch.format, timed: launch.timed)
    }

    /// 덮개 닫기 — 안내면 '봤음'을 적고(연습 시작에서 왔으면 연다), 아니면 그냥 닫는다.
    private func closeOverlay(_ shown: MahjongOverlay) {
        overlay = nil
        if case .firstTime(_, let launch) = shown {
            MahjongFirstTimeGuide.finish(launch: launch, defaults: guideDefaults) { launch in
                store.startPractice(format: launch.format, timed: launch.timed)
            }
        }
    }
}

/// 서버가 아직 없거나 앱이 낡았다.
private struct MahjongUnavailableView: View {
    let availability: MahjongAvailability

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: MahjongEntryIcon.resolved)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(availability == .updateRequired ? MahjongText.updateRequired : MahjongText.unavailable)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(CheckTheme.panel.opacity(0.7)))
    }
}

// MARK: - 덮개 그릇

/// 가운데 덮개 — 어둡게 깐 판 위에 카드 하나.
struct MahjongOverlayHost: View {
    let store: MahjongStore
    let overlay: MahjongOverlay
    let onClose: () -> Void
    let onSwitchRules: (MahjongRulesTab) -> Void
    var onStartPractice: (MahjongPracticeLaunch) -> Void = { _ in }
    var onGuidePage: (Int) -> Void = { _ in }
    var onReopenGuide: () -> Void = {}

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            switch overlay {
            case .rules(let tab):
                MahjongRulesSheet(store: store, tab: tab, onSelect: onSwitchRules, onClose: onClose, onReopenGuide: onReopenGuide)
            case .createRoom:
                MahjongCreateRoomSheet(store: store, onClose: onClose)
            case .practiceStart:
                MahjongPracticeStartSheet(store: store, onClose: onClose, onStart: onStartPractice)
            case .firstTime(let page, let launch):
                MahjongFirstTimeGuideSheet(page: page, launch: launch, onPage: onGuidePage, onFinish: onClose)
            }
        }
        .frame(width: MahjongWindowLayout.contentSize.width, height: MahjongWindowLayout.contentSize.height)
    }
}

// MARK: - 작은 공용 부품

/// 칩(작은 캡슐 글자).
struct MahjongChip: View {
    let text: String
    var tint: Color = CheckTheme.secondaryText
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(filled ? Color.white : tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.16)))
            .overlay(Capsule().stroke(tint.opacity(filled ? 0 : 0.45), lineWidth: 1))
    }
}

/// 캡슐 단추(앱의 둥근 단추 — 다른 마작 앱의 버튼 그림을 쓰지 않는다).
struct MahjongCapsuleButton: View {
    let title: String
    var tint: Color = CheckTheme.accent
    var filled = true
    var height: CGFloat = 32
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(filled ? Color.white : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(filled ? tint : tint.opacity(0.14)))
                .overlay(Capsule().stroke(tint.opacity(filled ? 0 : 0.5), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 둘 가운데 하나 고르기(Picker 를 쓰지 않는다 — ImageRenderer 가 못 그린다, MCL:99).
struct MahjongChoiceRow<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    let selected: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selected
                Button { onSelect(option.value) } label: {
                    Text(option.title)
                        .font(.callout.weight(on ? .bold : .regular))
                        .foregroundStyle(on ? Color.white : CheckTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? CheckTheme.accent : CheckTheme.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : CheckTheme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 카드 바탕.
struct MahjongCardBackground: View {
    var tint: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CheckTheme.panel.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint ?? CheckTheme.border, lineWidth: tint == nil ? 1 : 2))
    }
}

/// 초 단위 잎 — 이 안만 매 틱 다시 그린다. 시각은 스토어 시계(렌더 시험이 고정).
struct MahjongTick<Content: View>: View {
    let store: MahjongStore
    var interval: TimeInterval = 0.5
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { _ in
            content(store.clock())
        }
    }
}
