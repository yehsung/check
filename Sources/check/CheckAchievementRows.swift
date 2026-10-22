import CheckCore
import SwiftUI

// MARK: - 도전 미션 절 · 받기 버튼 · 받기 연출(v0.3.58 — 미션 화면)
//
// 사장님 확정(2026-10-19): 폰 로그인 · 할 일 3개 · 오목 · 체스 · 미니게임 3종 · 팀 2/3명 · 콕 10/50/100 · 울트라 5회 · 연속 근무 14/30일.
// 그리고 같은 날 **받기 버튼으로 받는다**(원문): "달성하면 받는 버튼이 생기고 그거 누르면 받아지게끔 해줘. 그래야 루비를 받는 재미가
// 더 올라갈거 같아. 기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고."
//
// 미션 화면(`MissionPanel`)의 기존 줄(근무 3시간마다 · 이번 주 근무 · 안내줄) **아래**에 "도전 미션" 소제목과 계열마다 한 줄씩 선다.
// 줄의 글자 · 숫자 · 순서는 전부 서버 응답이다(코어 `AchievementStatus.seriesRows`) — 이 파일에 50 · 20 · 10 … 이 없는 것이 설계다.
// 모르는 키도 그린다(아이콘만 기본 별) — 서버가 미션을 더하는 날 앱을 다시 낼 필요가 없다.
//
// ── 받는 순간("받는 재미") ── 길이 0.9초 · 꽃가루 없음 · 동작 줄이기를 따른다:
//  · 채운 줄은 오른쪽에 **[받기 💎+50]** 버튼(상점 [구매하기]와 같은 그라데이션 캡슐 · 더 크게)이 서고 줄 테두리가 강조색이 된다.
//  · 누르면 버튼이 흐려지고(떠 있음 — 두 번 눌러도 요청 하나), 서버가 넣었다고 답하면 그 자리에서 **"+50" 알약이 톡 커졌다가
//    위로 떠오르고**(`MissionClaimBurstCurve` — 위치는 easeOut, 크기는 짧은 튕김) **떠오름이 다 끝난 뒤 작아지며 빨려 들어간다**
//    (줄어들기 60%부터 · 흐려지기는 80%부터의 직선 — 메모리 '이징으로 불투명도를 깎지 마라': 같은 easeOut 으로 깎으면 밀려나기 전에
//    사라진다). 반투명한 큰 알약이 오래 남지 않게 한 이유: 알약이 멈추는 자리가 받은 줄의 보상 칩("💎 +50") 바로 위라, 절반쯤
//    흐린 채 머무르면 두 "+50"이 겹쳐 비친다(0.75 장면 실측). 그 사이 줄은 "✓ 받음"(단계가 남은 계열은 다음 단계)으로 스프링처럼
//    자리를 잡고, 제목 행의 루비 숫자가 올라간다(`MissionRubyBalance` — 숫자 넘김 전환). 캐릭터 말풍선 "루비 +N!"은 스토어가 기존
//    자리로 낸다.
//  · 동작 줄이기: 위치 · 크기 변화 없이 제자리에 섰다가 흐려지기만 하고, 줄 · 숫자는 애니메이션 없이 바로 바뀐다.
//  · 실패: 그 줄의 보조 문장 자리가 "받지 못했어요 · 다시 눌러 주세요"(주황)로 바뀌고 [받기]는 그대로 선다. 안내줄로 띄우지 않는다
//    (검토 지적 2026-10-19 — 안내줄은 절 위에 끼어 줄을 26pt 밀고, 아래 줄을 누른 사람에겐 스크롤 밖이라 안 보였다).
//
// ── v0.3.64 — 세 묶음 · 일일 미션 · 루비 아이콘 ──
// 사용자 결정(2026-10-22): 미션 화면을 **일일 미션 → 주간 미션 → 누적 미션** 세 묶음으로("도전 미션"은 "누적 미션"으로 이름을 바꿨다).
// 일일 미션 6줄(미니게임 3종 · 1:1 3종 하루 한 판 = 루비 5)은 이 파일의 줄(`AchievementRowView`)을 **그대로** 쓴다 — 묶음만
// `MissionRowGroup.daily` 로 갈려 받기 함수 · 떠 있음 · 실패 · 연출 자리 · 아이콘이 일일 쪽을 본다. 묶음 머리는 셋 다 같은 모양
// (`MissionGroupHeader` — 예전 "도전 미션" 소제목 그대로)이다.
// 루비 그림(사용자: "실제 루비는 핑크색인데 지금 미션에 있는 루비 아이콘은 달라")은 전부 `RubyIcon` 이다 — 보상 칩도 "💎 +20" 글자가
// 아니라 `RubyIcon` + "+20" 이다(`RubyRewardLabel`).

/// 도전 미션 절의 문구 · 아이콘 규약(순수 — 값으로 검증한다).
enum AchievementCopy {
    /// 누적 미션 묶음 머리(v0.3.64 에 "도전 미션"에서 이름을 바꿨다 — 사용자 결정 2026-10-22).
    static let sectionTitle = "누적 미션"
    /// 받은 줄의 표시(진행 숫자 자리). 3시간 줄의 "받음" 칩과 같은 낱말이다(`MissionCopy.claimedChip`).
    static let claimedMark = MissionCopy.claimedChip
    /// 받기 버튼의 낱말 — 주간 줄도 같은 버튼이다.
    static let claimButton = "받기"
    /// 한 번도 못 받았는데 실패 — 미션 화면의 실패 문장 그대로.
    static let failedCaption = MissionPanelCopy.failedCaption
    static let loadingCaption = MissionPanelCopy.loadingCaption
    /// 받기가 실패한 줄의 보조 문장(그 줄 안 — [받기]는 그대로 서 있다). 주간 줄도 같은 문장이다.
    static let claimFailedCaption = AchievementNoticeText.claimFailedRow

    /// 보상 칩의 글자 — "+20". 앞의 루비는 **그림**(`RubyIcon`)이다(v0.3.64 — 파란 💎 글자를 버렸다). 0 이면 칩이 없다(nil).
    static func reward(_ mission: AchievementStatus.Mission) -> String? {
        mission.reward > 0 ? "+\(mission.reward)" : nil
    }

    /// 진행 숫자("23/50"). 받은 줄은 이 자리에 `claimedMark` 를 그린다(연속 근무는 받은 뒤 지금 연속이 다시 낮을 수 있다 — 숫자는 거짓이 된다).
    static func count(_ mission: AchievementStatus.Mission) -> String {
        "\(mission.progress)/\(mission.target)"
    }

    /// 절 머리 오른쪽 — 받을 것이 있으면 "받을 보상 2개"(줄이 스크롤 아래에 있어도 여기서 보인다). 없으면 nil.
    static func pendingHint(_ count: Int) -> String? {
        count > 0 ? "받을 보상 \(count)개" : nil
    }

    /// 받기 버튼의 보이스오버 문구("받기, 루비 50개").
    static func claimAccessibility(_ amount: Int) -> String { "\(claimButton), 루비 \(max(0, amount))개" }

    /// 줄 아이콘. **키 앞부분으로 고른다**(계열 이름은 서버가 정하고 키는 계약 표에 있다) — 모르는 키는 별.
    /// 다른 화면에서 이미 그 기능을 뜻하는 기호를 그대로 쓴다(콕 = 레일 손가락 · 미니게임 = 레일 게임기 · 오목 = 미니게임 머리글 입구 ·
    /// 체스 = 체스 입구 · 연속 근무 = 헤더 칩 불꽃 · 울트라 = 울트라 화면 번개). 전부 macOS 11+ (배포 타깃 14 ✓).
    static func icon(_ key: String) -> String {
        let table: [(prefix: String, symbol: String)] = [
            ("phone", "iphone"),
            ("todo", "checklist"),
            ("gomoku", "circle.grid.3x3.fill"),
            ("chess", ChessEntryIcon.symbol),
            ("minigame", "gamecontroller.fill"),
            ("team", "person.3.fill"),
            ("poke", "hand.point.right.fill"),
            ("ultra", "bolt.fill"),
            ("streak", HeaderStreakCopy.icon),
        ]
        return table.first { key.hasPrefix($0.prefix) }?.symbol ?? fallbackIcon
    }

    static let fallbackIcon = "star.fill"
}

/// 일일 미션 묶음의 문구 · 아이콘 규약(v0.3.64 — 순수). 줄의 제목 · 보상은 **서버 글자**다(이 파일에 "한 판 하기" · 5 를 적지 않는다).
enum DailyMissionCopy {
    static let sectionTitle = "일일 미션"
    /// 머리 옆 짧은 안내 — 하루가 자정에 끝나고 **받지 않은 보상은 사라진다**(사용자 결정 2026-10-22). 한 줄을 넘지 않는다
    /// (머리 줄 292pt 안에 제목 · 안내 · "받을 보상 N개"가 같이 선다 — 폭은 V0364 시험이 잰다).
    static let resetNote = "자정에 초기화 · 안 받으면 사라져요"

    /// 줄 아이콘 — 그 게임이 **다른 화면에서 이미 쓰는 기호**(미니게임 창의 종류 칩 `MiniGameKind.icon` · 1:1 입구 셋). 모르는 게임은 별.
    @MainActor
    static func icon(game: String) -> String {
        if let kind = MiniGameKind(rawValue: game) { return kind.icon }
        switch game {
        case "gomoku": return MiniGameGomokuEntryButton.icon
        case "chess": return ChessEntryIcon.resolved
        case "tetris_duel": return TetrisDuelEntryIcon.resolved
        default: return AchievementCopy.fallbackIcon
        }
    }
}

/// 주간 미션 묶음의 머리(v0.3.64). 줄은 예전 "이번 주 근무" 그대로다(`WeeklyWorkRowView`).
enum WeeklyMissionCopy {
    static let sectionTitle = "주간 미션"
}

/// 줄이 어느 묶음의 것인가(v0.3.64). 누적 미션 줄과 일일 미션 줄은 **같은 그림**이고, 받기 함수 · 떠 있음 · 실패 · 연출 자리 · 아이콘만
/// 이 값으로 갈린다.
enum MissionRowGroup: Equatable {
    case achievement
    /// 일일 미션 — 세는 게임(아이콘을 고른다).
    case daily(game: String)
}

/// 레일 [미션] 칸의 숫자 배지 · 툴팁(순수). 받을 것이 없으면 배지가 없다(nil). 두 자리부터는 "9+"(칸 모서리를 넘지 않게).
enum MissionRailBadge {
    static func text(count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 9 ? "9+" : "\(count)"
    }

    static let plainHelp = "미션 — 일일 · 주간 · 누적"

    /// 숫자는 색 · 모양으로만 말하지 않는다 — 툴팁(= 보이스오버)도 같은 수를 말한다.
    static func tooltipText(count: Int) -> String {
        count > 0 ? "미션 — 받을 보상 \(count)개" : plainHelp
    }
}

/// 미션 화면이 도전 미션 절을 어떻게 그리는가. 스토어 값 셋에서 **한 곳**(`make`)이 고른다.
enum AchievementSectionState: Equatable {
    /// 절이 없다 — 이 서버엔 도전 미션이 없다(404 · PGRST202) 또는 줄이 하나도 없다. 실패 문구도 소제목도 안 그린다.
    case hidden
    /// 아직 한 번도 못 받았다(조회가 떠 있다).
    case loading
    /// 한 번도 못 받았는데 마지막 조회가 실패했다 — 실패 문장 + 제목 행의 [다시 시도].
    case failed
    /// 계열마다 한 줄(코어 `seriesRows`) + 받을 것의 수(계열로 접기 **전** — 절 머리 "받을 보상 N개" · 레일 배지와 같은 수).
    case loaded(rows: [AchievementStatus.Mission], claimableCount: Int)

    static func make(status: AchievementStatus?, unavailable: Bool, failed: Bool) -> AchievementSectionState {
        if unavailable { return .hidden }
        // 받아 둔 값이 있으면 실패해도 그 값을 그린다(알던 줄을 지우지 않는다 — 주간 줄과 같은 규약).
        if let status {
            let rows = status.seriesRows
            return rows.isEmpty ? .hidden : .loaded(rows: rows, claimableCount: status.claimableCount)
        }
        return failed ? .failed : .loading
    }

    /// 줄을 아직 모르는 동안(불러오는 중 · 한 번도 못 받은 실패) 미션 화면이 **스크롤 창 높이를 미리 잡아 두는가**.
    /// 검토 지적(2026-10-19): 문구 한 줄로 세면 첫 열기마다 팝오버가 482pt 로 섰다가 답이 오면 582pt 로 100pt 자랐다(9줄은 언제나
    /// 스크롤 상한을 넘는다). 그래서 이 두 상태는 받은 뒤와 같은 높이를 차지한다 — 실패 ↔ 다시 묻는 중도 같은 높이라 [다시 시도]가
    /// 팝오버를 흔들지 않는다. 서버에 기능이 없다고 **안 뒤**(`.hidden`)에만 접힌다(db push 전 창의 한 번뿐이다).
    var reservesViewport: Bool {
        switch self {
        case .loading, .failed: return true
        case .hidden, .loaded: return false
        }
    }

    /// 절이 그리는 줄 수(소제목 제외). 문구 한 줄도 한 줄 높이다(미션 화면의 빈 목록 문구와 같은 규약).
    var rowCount: Int {
        switch self {
        case .hidden: return 0
        case .loading, .failed: return 1
        case .loaded(let rows, _): return rows.count
        }
    }
}

// MARK: - 받기 맥락(환경값)

/// 미션 화면이 줄들에게 내려 주는 받기 맥락 — 동작 · 떠 있음 · 연출 · 동작 줄이기 강제값.
///
/// **왜 인자가 아니라 환경값인가**: 주간 줄의 호출부 `WeeklyWorkRowView(status: weeklyRow)` 는 v0.3.56 소스 계약 테스트가 글자 그대로
/// 읽는다(줄 순서 단언). 서명을 바꾸면 그 계약이 깨지고, 렌더 테스트들이 그 줄 하나만 그릴 때도 받기와 무관한 인자를 채워야 한다.
/// 기본값은 "아무것도 안 함"이라 맥락 없이 그린 줄은 v0.3.57 과 같다(버튼은 서지만 눌러도 조용하다 — 옛 서버엔 버튼 자체가 없다).
struct MissionClaimContext {
    var claimAchievement: (String) -> Void = { _ in }
    var claimWeekly: () -> Void = {}
    /// 떠 있는 받기(키 · 전부 받기는 `WorkTimerStore.achievementClaimAllSlot`).
    var inFlightKeys: Set<String> = []
    var weeklyInFlight = false
    /// 줄 자리 → 받기 연출(`MissionClaimBurst.achievementTarget(series:)` · `weeklyTarget`).
    var bursts: [String: MissionClaimBurst] = [:]
    /// 마지막 받기가 실패한 키 · 주간 받기 실패(검토 지적 2026-10-19 — 실패는 **그 줄 안**에서 말한다, 안내줄로 절을 밀지 않는다).
    var failedKeys: Set<String> = []
    var weeklyFailed = false
    /// 동작 줄이기 강제값. nil 이면 시스템 설정을 따른다(`accessibilityReduceMotion` 은 읽기 전용이라 렌더 테스트가 여기로 강제한다 —
    /// `CheckFocusModeButton.reduceMotion` 과 같은 규약).
    var reduceMotion: Bool? = nil
    /// 받기 연출을 이 장면(0…1)에 멈춰 그린다 — **렌더 테스트 · 스틸 전용**, 앱은 언제나 nil(0 → 1 로 한 번 재생한다).
    /// 왜 필요한가(2026-10-19 실측): `ImageRenderer` 는 `onAppear` 의 `withAnimation` 을 끝값으로 건너뛰어 굽는다 — 연출이 언제나
    /// 불투명도 0 으로 찍혀, 줄이 동작 줄이기 값을 연출에 넘기는지 그림으로 잴 수 없었다(검토 지적: 넘기지 않게 바꿔도 초록).
    var frozenBurstProgress: Double? = nil
    /// 일일 미션 받기(v0.3.64 — `daily_mission_claim`). 누적 받기와 함수가 달라 따로 받는다. 칸 순서가 뒤인 이유: 멤버별 초기화의
    /// 인자 순서가 칸 순서라, 앞에 끼우면 기존 호출부(`MissionClaimContext(failedKeys:)` 따위)는 괜찮아도 읽는 순서가 갈린다.
    var claimDaily: (String) -> Void = { _ in }
    /// 떠 있는 일일 받기 · 마지막 일일 받기가 실패한 키(v0.3.64 — 누적 쪽과 따로 센다).
    var dailyInFlightKeys: Set<String> = []
    var dailyFailedKeys: Set<String> = []

    func isInFlight(_ key: String) -> Bool {
        inFlightKeys.contains(key) || inFlightKeys.contains(WorkTimerStore.achievementClaimAllSlot)
    }

    func hasFailed(_ key: String) -> Bool { failedKeys.contains(key) }

    /// 묶음을 아는 판정(v0.3.64) — 줄이 부른다.
    func isInFlight(_ key: String, group: MissionRowGroup) -> Bool {
        switch group {
        case .achievement: return isInFlight(key)
        case .daily: return dailyInFlightKeys.contains(key) || dailyInFlightKeys.contains(WorkTimerStore.achievementClaimAllSlot)
        }
    }

    func hasFailed(_ key: String, group: MissionRowGroup) -> Bool {
        switch group {
        case .achievement: return hasFailed(key)
        case .daily: return dailyFailedKeys.contains(key)
        }
    }

    func claim(_ key: String, group: MissionRowGroup) {
        switch group {
        case .achievement: claimAchievement(key)
        case .daily: claimDaily(key)
        }
    }
}

private struct MissionClaimContextKey: EnvironmentKey {
    /// 계산 속성인 이유: 맥락이 클로저를 쥐어 `Sendable` 이 아니다 — 저장 전역으로 두면 동시성 검사가 막는다(매번 새 기본값이라 상태도 없다).
    static var defaultValue: MissionClaimContext { MissionClaimContext() }
}

extension EnvironmentValues {
    var missionClaim: MissionClaimContext {
        get { self[MissionClaimContextKey.self] }
        set { self[MissionClaimContextKey.self] = newValue }
    }
}

// MARK: - 움직임 규약(순수 — 값으로 검증한다)

/// 받기 연출의 곡선. `t` 는 0…1 의 **선형 시간**이고(`MissionClaimBurstView` 가 `.linear(duration:)` 으로 민다) 이징은 여기서 건다 —
/// 위치 · 크기 · 불투명도가 각자 다른 곡선을 가져야 해서다.
enum MissionClaimBurstCurve {
    /// 전체 길이(초) — 1초 미만(설계서 "Keep it brief (< 1 s)").
    static let duration: Double = 0.9
    /// 떠오르는 높이(pt). 버튼 중심(줄 가운데)에서 22pt — 56pt 줄 안에서 끝난다(스크롤 창에 잘리지 않는다).
    static let rise: CGFloat = 22
    /// 톡 커지는 크기: 0.7 → 1.18(시간의 22%) → 1.0(40%).
    static let popFrom: CGFloat = 0.7
    static let popPeak: CGFloat = 1.18
    static let popPeakAt: Double = 0.22
    static let popSettleAt: Double = 0.40
    /// 작아지기 시작하는 시점 · 끝 크기 — 떠오름(easeOutCubic)이 94% 온 뒤 1.0 → 0.2 로 빨려 들어간다(easeIn).
    static let shrinkStart: Double = 0.6
    static let shrinkTo: CGFloat = 0.2
    /// 흐려지기 시작하는 시점 — 그때 위치는 이미 99% 왔고 크기는 0.8 남짓이다. 그 뒤 끝까지 **직선**으로 0.
    static let fadeStart: Double = 0.8

    struct Frame: Equatable {
        let offsetY: CGFloat
        let scale: CGFloat
        let opacity: Double
    }

    /// 위치가 온 비율(0…1) — easeOutCubic. 동작 줄이기면 0(움직이지 않는다).
    static func riseFraction(_ t: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        let x = min(1, max(0, t))
        return 1 - pow(1 - x, 3)
    }

    static func frame(at t: Double, reduceMotion: Bool) -> Frame {
        let x = min(1, max(0, t))
        // 불투명도는 **이징이 아니다** — 절반까지 1, 그 뒤 직선. 동작 줄이기에서도 같다(제자리에서 흐려지기만 한다).
        let opacity = x <= fadeStart ? 1 : max(0, 1 - (x - fadeStart) / (1 - fadeStart))
        guard !reduceMotion else { return Frame(offsetY: 0, scale: 1, opacity: opacity) }
        let scale: CGFloat
        if x < popPeakAt {
            let u = x / popPeakAt
            scale = popFrom + (popPeak - popFrom) * CGFloat(1 - (1 - u) * (1 - u))
        } else if x < popSettleAt {
            let u = (x - popPeakAt) / (popSettleAt - popPeakAt)
            scale = popPeak + (1 - popPeak) * CGFloat(u * u * (3 - 2 * u))
        } else if x < shrinkStart {
            scale = 1
        } else {
            let u = (x - shrinkStart) / (1 - shrinkStart)
            scale = 1 - (1 - shrinkTo) * CGFloat(u * u)
        }
        return Frame(offsetY: -rise * CGFloat(riseFraction(x, reduceMotion: false)), scale: scale, opacity: opacity)
    }
}

/// 받기 둘레의 애니메이션(순수). 동작 줄이기면 nil — 바로 바뀐다.
enum MissionClaimMotion {
    /// 줄이 [받기] → "✓ 받음"(또는 다음 단계)으로 자리 잡는 스프링.
    static func rowSettle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)
    }

    /// 제목 행 루비 숫자가 넘어가는 시간.
    static func balanceTick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.5)
    }
}

// MARK: - 받기 버튼 · 연출

/// [받기 💎+50]. 상점 [구매하기](`BuyButton`)와 같은 그라데이션 캡슐이되 더 크다(26pt — 이 화면에서 누를 것은 이것이다).
/// 떠 있으면 흐려지고 눌리지 않는다(두 번 눌러도 요청 하나 — 스토어도 따로 막는다).
struct MissionClaimButton: View {
    let amount: Int
    var inFlight: Bool = false
    let action: () -> Void

    @State private var hovering = false

    static let height: CGFloat = 26

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(AchievementCopy.claimButton)
                    .font(.caption.weight(.bold))
                RubyIcon(size: 13)
                Text("+\(max(0, amount))")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: Self.height)
            .background(Capsule().fill(CheckTheme.gaugeGradient))
            // hover 는 흰색을 얇게 덧칠한다(레일 버튼과 같은 관용구).
            .overlay(Capsule().fill(Color.white.opacity(hovering && !inFlight ? 0.12 : 0)))
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(inFlight)
        .opacity(inFlight ? 0.55 : 1)
        .onHover { hovering = $0 }
        .accessibilityLabel(AchievementCopy.claimAccessibility(amount))
    }
}

/// 받기 연출의 한 장면(`progress` 0…1 에서의 모양). **순수 그림**이라 렌더 테스트 · 미리보기가 중간 장면을 그대로 굽는다.
/// `Animatable` 이라 `MissionClaimBurstView` 가 `progress` 를 밀면 SwiftUI 가 매 프레임 이 값을 보간해 다시 그린다.
struct MissionClaimBurstFace: View, Animatable {
    let amount: Int
    var progress: Double
    var reduceMotion: Bool = false

    /// `Animatable` 은 격리 없는 프로토콜이라 이 속성도 격리 없이 둔다(값 타입의 Sendable 저장 속성이라 안전하다).
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let frame = MissionClaimBurstCurve.frame(at: progress, reduceMotion: reduceMotion)
        HStack(spacing: 3) {
            RubyIcon(size: 14)
            Text("+\(max(0, amount))")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(CheckTheme.working)
        .fixedSize()
        .padding(.horizontal, 9)
        .frame(height: 24)
        // 불투명 바탕 — 떠오르는 동안 아래 줄 글자("✓ 받음")와 겹쳐 읽히지 않게.
        .background(Capsule().fill(CheckTheme.panelElevated))
        .overlay(Capsule().stroke(CheckTheme.working.opacity(0.55), lineWidth: 1))
        .scaleEffect(frame.scale)
        .offset(y: frame.offsetY)
        .opacity(frame.opacity)
    }
}

/// 받기 연출(한 번 재생하고 끝 — 끝난 뒤엔 불투명도 0 으로 남아 아무것도 가리지 않는다). 다시 재생하려면 `.id(serial)` 로 새로 만든다.
/// 동작 줄이기 값은 **줄이 넘긴다**(줄마다 같은 값으로 자리잡기 애니메이션도 고르므로 — 두 곳이 갈리지 않게). 멈춘 장면
/// (`MissionClaimContext.frozenBurstProgress`)만 환경값에서 직접 읽는다 — 렌더 테스트가 줄의 배선을 그대로 거쳐 재게.
struct MissionClaimBurstView: View {
    let amount: Int
    let reduceMotion: Bool

    @Environment(\.missionClaim) private var claim
    @State private var progress: Double = 0

    var body: some View {
        MissionClaimBurstFace(amount: amount, progress: claim.frozenBurstProgress ?? progress, reduceMotion: reduceMotion)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard claim.frozenBurstProgress == nil else { return }
                withAnimation(.linear(duration: MissionClaimBurstCurve.duration)) { progress = 1 }
            }
    }
}

// MARK: - 제목 행 루비 잔량

/// 미션 화면 제목 행 오른쪽의 루비 잔량 — **받으면 숫자가 올라가는 자리**다(`.numericText` 전환). 상점 칩(`RubyBalanceChip`)과 같은
/// 아이콘 · 같은 "—"(모름) 규약이고, 높이는 제목 행의 뒤로 버튼(27pt)보다 낮아 행을 키우지 않는다(팝오버 높이 예산).
struct MissionRubyBalance: View {
    let balance: Int?
    var reduceMotion: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    static let height: CGFloat = 23

    var body: some View {
        let reduces = reduceMotion ?? systemReduceMotion
        HStack(spacing: 4) {
            RubyIcon(size: 15)
            Text(ShopText.balance(balance))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
                .contentTransition(.numericText(value: Double(balance ?? 0)))
        }
        .padding(.horizontal, 9)
        .frame(height: Self.height)
        .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
        .overlay(Capsule().stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
        .animation(MissionClaimMotion.balanceTick(reduceMotion: reduces), value: balance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShopText.entryHelp(balance))
    }
}

// MARK: - 도전 미션 줄

/// 도전 미션 한 줄(계열 하나). 3시간 줄(`MissionRowView`) · 주간 줄(`WeeklyWorkRowView`)과 **같은 뼈대 · 같은 높이**다:
/// 아이콘 · 제목 + 오른쪽 보상 칩("💎 +20") · 진행 바(progress/target) · 보조 문장 + 오른쪽 진행 숫자("23/50").
///  · 채웠고 안 받음 → 칩 · 숫자 대신 오른쪽에 [받기 💎+N](세로 가운데) · 바 가득(강조색) · 테두리 강조색.
///  · 받음 → 아이콘 · 바 · 칩이 근무색이고 진행 숫자 자리에 "✓ 받음".
/// private 가 아닌 이유: 렌더 테스트가 이 줄 하나만 그려 ✓ · [받기]를 픽셀로 잰다(주간 줄과 같은 이유).
struct AchievementRowView: View {
    let mission: AchievementStatus.Mission
    /// 어느 묶음의 줄인가(v0.3.64). 기본값은 누적 미션 — 예전 호출부(`AchievementRowView(mission:)`)는 그대로다.
    var group: MissionRowGroup = .achievement

    @Environment(\.missionClaim) private var claim
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// 줄 아이콘 — 누적은 키 앞부분으로, 일일은 세는 게임으로 고른다.
    private var icon: String {
        switch group {
        case .achievement: return AchievementCopy.icon(mission.key)
        case .daily(let game): return DailyMissionCopy.icon(game: game)
        }
    }

    /// 받기 연출이 서는 자리 — 누적은 계열(단계가 올라도 같은 줄), 일일은 키.
    private var burstTarget: String {
        switch group {
        case .achievement: return MissionClaimBurst.achievementTarget(series: mission.series)
        case .daily: return MissionClaimBurst.dailyTarget(key: mission.key)
        }
    }

    var body: some View {
        let reduces = claim.reduceMotion ?? systemReduceMotion
        let state = mission.state
        let tint = state == .claimed ? CheckTheme.working : CheckTheme.accent
        // 버튼이 서면 왼쪽 글자 열이 그만큼 좁아진다 — 가장 긴 제목("미니게임 3종 한 판씩 해보기")이 말줄임 대신 살짝 줄어들게.
        let squeeze: CGFloat = state == .claimable ? 0.8 : 1
        // 받기가 실패했으면 보조 문장 자리에 실패 문장(검토 지적 2026-10-19) — 줄 높이 · 위치는 그대로라 아무것도 밀리지 않고,
        // 누른 그 줄에서 보인다. [받기]가 서 있을 때만이다(그 사이 다른 기기에서 받았으면 실패는 더 뜻이 없다).
        let failed = state == .claimable && claim.hasFailed(mission.key, group: group)
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mission.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(squeeze)
                    Spacer(minLength: 4)
                    if state != .claimable, let reward = AchievementCopy.reward(mission) {
                        RubyRewardLabel(text: reward)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.16)))
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CheckTheme.trackFill)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(0, proxy.size.width * mission.fraction))
                    }
                }
                .frame(height: 4)      // MissionRowView 와 같은 관용구
                HStack(spacing: 6) {
                    Text(failed ? AchievementCopy.claimFailedCaption : mission.detail)
                        .font(failed ? .caption2.weight(.semibold) : .caption2)
                        .foregroundStyle(failed ? CheckTheme.pending : CheckTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(squeeze)
                    Spacer(minLength: 4)
                    switch state {
                    case .claimed:
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            Text(AchievementCopy.claimedMark).font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(CheckTheme.working)
                    case .inProgress:
                        Text(AchievementCopy.count(mission))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(CheckTheme.secondaryText)
                    case .claimable:
                        EmptyView()
                    }
                }
            }
            if state == .claimable {
                MissionClaimButton(amount: mission.reward, inFlight: claim.isInFlight(mission.key, group: group)) {
                    claim.claim(mission.key, group: group)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: AchievementSectionLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(state == .claimable ? CheckTheme.accent.opacity(0.55) : CheckTheme.border, lineWidth: 1))
        // 받기 연출은 줄(계열) 자리에 선다 — 콕 10 을 받아 이 줄이 콕 50 으로 바뀌어도 "+5"는 같은 자리에서 떠오른다.
        .overlay(alignment: .trailing) {
            if let burst = claim.bursts[burstTarget] {
                MissionClaimBurstView(amount: burst.amount, reduceMotion: reduces)
                    .id(burst.serial)
                    .padding(.trailing, 12)
            }
        }
        .animation(MissionClaimMotion.rowSettle(reduceMotion: reduces), value: AchievementRowAnimationKey(mission))
        // 버튼이 있으면 그 버튼이 따로 눌려야 한다(합치면 줄 전체가 한 요소가 돼 버튼 동작이 묻힌다).
        .accessibilityElement(children: state == .claimable ? .contain : .combine)
    }
}

/// 줄이 자리를 잡는 애니메이션의 열쇠 — 보이는 단계 · 상태가 바뀔 때만 움직인다(떠 있음 · 연출 시작은 열쇠가 아니다).
private struct AchievementRowAnimationKey: Equatable {
    let key: String
    let state: AchievementStatus.RowState

    init(_ mission: AchievementStatus.Mission) {
        key = mission.key
        state = mission.state
    }
}

/// 루비 보상 글자 — **분홍 루비 그림**(`RubyIcon`) + "+20"(v0.3.64 — 상단 잔량 칩과 같은 그림). 색 · 바탕은 부르는 쪽이 칠한다
/// (줄 칩 · 3시간 칩 · 주간 칩이 같은 부품이다). 글자는 caption2 굵게 — 예전 "💎 +20" 칩과 같은 크기라 줄 높이가 그대로다.
struct RubyRewardLabel: View {
    let text: String
    var iconSize: CGFloat = 11
    /// 앞에 붙는 그림(주간 완료 칩의 체크 같은). nil 이면 루비만.
    var leadingSymbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol).font(.system(size: 9, weight: .bold))
            }
            RubyIcon(size: iconSize)
            Text(text)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("루비 \(text)")
    }
}

/// 미션 화면 묶음 머리(v0.3.64 — 일일 · 주간 · 누적 셋 다 같은 모양, 예전 "도전 미션" 소제목 그대로). 높이는 `MissionGroupLayout.headerHeight`.
struct MissionGroupHeader: View {
    let title: String
    /// 제목 옆 짧은 안내(일일 묶음의 "자정에 초기화 …"). 한 줄을 넘지 않는다.
    var note: String? = nil
    /// 오른쪽 "받을 보상 N개"(0 이면 없음).
    var pendingCount: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .fixedSize()
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            if let hint = AchievementCopy.pendingHint(pendingCount) {
                Text(hint)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: MissionGroupLayout.headerHeight - 6, alignment: .bottom)
        .padding(.top, 6)
    }
}

/// 묶음 머리의 높이 규약(순수 — 미션 화면의 스크롤 판정이 이 값으로 내용 높이를 센다).
enum MissionGroupLayout {
    /// 머리 줄 높이(글자 14 + 위 여백 6 — 위 줄들과 묶음을 가르는 틈). 예전 "도전 미션" 소제목과 같다.
    static let headerHeight: CGFloat = 20
}

/// 누적 미션 절의 높이 규약(순수 — 미션 화면의 스크롤 판정이 이 값으로 내용 높이를 센다).
enum AchievementSectionLayout {
    /// 줄 높이 · 간격은 미션 화면 줄과 같다(56 · 8 — `MissionPanel.rowHeight/rowSpacing` 와 짝).
    static let rowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 8
    /// 소제목 줄 높이(글자 14 + 위 여백 6 — 위 줄들과 절을 가르는 틈). 세 묶음 머리가 같은 값이다(`MissionGroupLayout`).
    static let headerHeight: CGFloat = MissionGroupLayout.headerHeight

    /// 절 전체 높이(앞 줄과의 간격 포함). 절이 없으면 0.
    static func height(_ state: AchievementSectionState) -> CGFloat {
        let rows = state.rowCount
        guard rows > 0 else { return 0 }
        return rowSpacing + headerHeight + rowSpacing + CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }
}

/// 누적 미션 절(묶음 머리 + 줄들 — v0.3.64 에 "도전 미션"에서 이름을 바꿨다). 미션 화면의 스크롤 내용 맨 아래에 선다. 상태는 값으로만
/// 받는다(렌더 테스트 친화) — 받기 동작은 환경값(`missionClaim`)으로 줄들에 내려간다.
struct AchievementSectionView: View {
    let state: AchievementSectionState

    private var pendingCount: Int {
        if case .loaded(_, let claimable) = state { return claimable }
        return 0
    }

    var body: some View {
        if state != .hidden {
            VStack(spacing: AchievementSectionLayout.rowSpacing) {
                MissionGroupHeader(title: AchievementCopy.sectionTitle, pendingCount: pendingCount)
                switch state {
                case .hidden:
                    EmptyView()
                case .loading, .failed:
                    Text(state == .failed ? AchievementCopy.failedCaption : AchievementCopy.loadingCaption)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: AchievementSectionLayout.rowHeight,
                               maxHeight: AchievementSectionLayout.rowHeight, alignment: .leading)
                case .loaded(let rows, _):
                    ForEach(rows) { AchievementRowView(mission: $0) }
                }
            }
        }
    }
}
