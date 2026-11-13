import AppKit
import SceneKit
import SwiftUI
import CheckCore

// MARK: - 1:1 길건너 대결 화면 (SPEC v1.3 §9.2 · §9.3)
//
// 위: 경주 트랙 띠 44pt(대표 답 C — `.claude/crossy-duel-mocks-20261106-190319/Q2-C-경주트랙.png` 가 기준 그림).
// 아래 두 열: [캔버스 344×356 | 오른쪽 열 256(상대 카드 · 죽은 횟수/목표 · 조작 · [기권] / 결과 카드 · [로비로])].
//
// ★ 판 값은 **잎의 `TimelineView` 안에서** `store.raceSnapshot()` 하나로 읽는다(스토어 `duel` 은 관찰 대상이 아니다).
//   잎은 셋이다 — 경주 띠(`CrossyDuelRaceBandLeaf`) · 캔버스(`CrossyDuelCanvasLeaf`, 여기서만 `store.tick()`) · 판 숫자
//   (`CrossyDuelLiveStats`). 잎이 그리는 몸통은 **값을 인자로 받는 순수 뷰**(`CrossyDuelRaceBand` · `CrossyDuelCanvasOverlayView`)라
//   렌더 시험이 스냅숏 값을 그대로 넣어 찍을 수 있다.

// MARK: - 경주 트랙 기하(순수)

/// 경주 트랙 띠의 자리 계산(순수 — 시험이 값으로 잰다). 좌표는 **띠 안**(왼쪽 위 0,0).
///
/// 얼굴 점 중심 x = 트랙 시작 + 트랙 길이 × 점수/목표(0…1 로 자름). 점수 0 의 점이 띠 밖으로 나가지 않게 트랙 시작을
/// 점 반지름만큼 안으로 들였다. 오른쪽 끝에서 왼쪽으로: 남은 시간 · 점수 두 줄 · 깃발.
enum CrossyDuelRaceTrackLayout {
    /// 얼굴(아바타) 지름 · 테두리(SPEC §9.2 — 26pt + 2pt).
    static let faceDiameter: CGFloat = 26
    static let ringWidth: CGFloat = 2
    static var dotDiameter: CGFloat { faceDiameter + ringWidth * 2 }
    /// 트랙 선 두께(4pt 둥근 선).
    static let lineThickness: CGFloat = 4
    static let leadingPadding: CGFloat = 12
    static let trailingPadding: CGFloat = 16
    static let clockWidth: CGFloat = 64
    static let scoreColumnWidth: CGFloat = 96
    static let columnGap: CGFloat = 12
    static let flagWidth: CGFloat = 18
    /// 눈금(25 · 50 · 75).
    static let ticks: [Int] = [25, 50, 75]

    /// 점수 0 의 점 중심.
    static var trackStartX: CGFloat { leadingPadding + dotDiameter / 2 }

    /// 점수 = 목표(100)의 점 중심(= 깃발 기둥).
    static func trackEndX(bandWidth: CGFloat) -> CGFloat {
        bandWidth - trailingPadding - clockWidth - columnGap - scoreColumnWidth - columnGap - flagWidth
    }

    static func trackLength(bandWidth: CGFloat) -> CGFloat { trackEndX(bandWidth: bandWidth) - trackStartX }

    /// 점수의 자리(트랙 위 x). 목표가 0 이하면 시작에 둔다.
    static func centerX(score: Int, goal: Int, bandWidth: CGFloat) -> CGFloat {
        guard goal > 0 else { return trackStartX }
        let fraction = min(1, max(0, CGFloat(score) / CGFloat(goal)))
        return trackStartX + trackLength(bandWidth: bandWidth) * fraction
    }

    /// 겹치면 **점수가 높은 쪽이 위**, 같으면 내가 위(SPEC §9.2 — 대표 카드 설명 그대로).
    static func opponentOnTop(myScore: Int, opponentScore: Int) -> Bool { opponentScore > myScore }
}

// MARK: - 캔버스 겹(순수)

/// 캔버스 위 겹 하나. **우선순위(v1.1 CC-20)**: 결과 > 판정 기다림 > 부활 카운트 > 시작 카운트다운 — 위가 보이면 아래는 숨긴다
/// (3분 얼림·100 기다림이 엔진 `.over` 남은 값과 겹쳐도 부활 "2" 가 같이 뜨지 않는다).
enum CrossyDuelCanvasOverlay: Equatable {
    case result(CrossyDuelOutcome?)
    /// `goal` = 100 에 닿아 기다린다(아니면 3분 끝).
    case waiting(goal: Bool)
    case respawn(String)
    case countdown(String)

    static func resolve(phase: CrossyDuelPhase, isFinished: Bool, outcome: CrossyDuelOutcome?,
                        snapshot: CrossyDuelRaceSnapshot?) -> CrossyDuelCanvasOverlay? {
        if isFinished || phase == .finished { return .result(outcome) }
        guard let snapshot, phase == .countdown || phase == .playing else { return nil }
        let reachedGoal = snapshot.myScore >= snapshot.goal
        let timeUp = phase == .playing && (snapshot.remaining.map { $0 <= 0 } ?? false)
        if snapshot.waitingForResult || snapshot.frozen || reachedGoal || timeUp {
            return .waiting(goal: reachedGoal)
        }
        if let respawn = snapshot.respawnIn, respawn > 0 { return .respawn(CrossyDuelText.countdownDigit(respawn)) }
        if let countdown = snapshot.countdown, countdown > 0 { return .countdown(CrossyDuelText.countdownDigit(countdown)) }
        return nil
    }
}

// MARK: - 대결 화면 (띠 + 두 열)

struct CrossyDuelMatchView: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState
    let me: ChessPlayerFace
    let myUserID: String?
    @Binding var confirmResign: Bool
    let showsConfirmPreview: Bool
    let previewCanvas: CGImage?
    let frameRateMonitor: MiniGameFrameRateMonitor?
    let onCanvasFrame: (@MainActor (CGRect) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CrossyDuelWindowLayout.raceBandSpacing) {
            CrossyDuelRaceBandLeaf(store: store, match: match, me: me, myUserID: myUserID)
                .frame(width: CrossyDuelWindowLayout.innerWidth, height: CrossyDuelWindowLayout.raceBandHeight)
            HStack(alignment: .top, spacing: CrossyDuelWindowLayout.columnSpacing) {
                CrossyDuelCanvasLeaf(store: store, match: match, previewCanvas: previewCanvas,
                                     frameRateMonitor: frameRateMonitor, onCanvasFrame: onCanvasFrame)
                    .frame(width: CrossyDuelWindowLayout.canvasSize.width,
                           height: CrossyDuelWindowLayout.canvasSize.height)
                CrossyDuelMatchSide(store: store, match: match, confirmResign: $confirmResign,
                                    showsConfirmPreview: showsConfirmPreview)
                    .frame(width: CrossyDuelWindowLayout.sideColumnWidth,
                           height: CrossyDuelWindowLayout.matchColumnHeight, alignment: .top)
                    .clipped()
            }
        }
    }
}

// MARK: - 경주 트랙 띠

/// 경주 띠 — **잎 뷰**(판 값은 여기 TimelineView 안에서만 읽는다). 창이 안 보이거나 판이 아니면 멈춘다.
struct CrossyDuelRaceBandLeaf: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState
    let me: ChessPlayerFace
    let myUserID: String?

    /// 띠를 다시 그리는 간격 — 점수는 정수라 0.1초면 착지 순간을 놓치지 않는다(판 루프 0.05초의 두 배).
    static let refreshSeconds: TimeInterval = 0.1

    var body: some View {
        let live = store.isWindowVisible && (store.phase == .countdown || store.phase == .playing)
        TimelineView(.animation(minimumInterval: Self.refreshSeconds, paused: !live)) { _ in
            CrossyDuelRaceBand(snapshot: store.raceSnapshot() ?? Self.fallback(match),
                               me: me, myUserID: myUserID, opponent: match.opponent,
                               isFinished: match.isFinished || store.phase == .finished)
        }
    }

    /// 판 구동기가 아직 없을 때(준비 단계)의 값 — 둘 다 0 · 남은 시간 3:00.
    static func fallback(_ match: CrossyDuelMatchState) -> CrossyDuelRaceSnapshot {
        CrossyDuelRaceSnapshot(myScore: match.finalMyScore ?? 0, opponentScore: match.finalOpponentScore ?? match.opponentScore,
                               goal: CrossyDuelSession.expectedGoal, myDeaths: 0, opponentDeaths: match.opponentDeaths,
                               remaining: match.isFinished ? 0 : TimeInterval(CrossyDuelSession.expectedMaxDurationSeconds))
    }
}

/// 경주 트랙 띠 한 장(순수 — 값만 그린다). 왼쪽부터 트랙(남은 폭) · 점수 두 줄 · 남은 시간.
struct CrossyDuelRaceBand: View {
    let snapshot: CrossyDuelRaceSnapshot
    let me: ChessPlayerFace
    let myUserID: String?
    let opponent: CrossyDuelUser
    let isFinished: Bool

    private typealias L = CrossyDuelRaceTrackLayout
    private var bandWidth: CGFloat { CrossyDuelWindowLayout.innerWidth }
    private var midY: CGFloat { CrossyDuelWindowLayout.raceBandHeight / 2 }

    var body: some View {
        let goal = snapshot.goal
        let myX = L.centerX(score: snapshot.myScore, goal: goal, bandWidth: bandWidth)
        let opponentX = L.centerX(score: snapshot.opponentScore, goal: goal, bandWidth: bandWidth)
        let endX = L.trackEndX(bandWidth: bandWidth)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel.opacity(0.85))
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1)
            // 트랙 바탕 · 눈금.
            segment(from: L.trackStartX, to: endX, color: CheckTheme.trackFill)
            ForEach(L.ticks, id: \.self) { tick in
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 1, height: 10)
                    .position(x: L.centerX(score: tick, goal: 100, bandWidth: bandWidth), y: midY)
            }
            // 0→상대 점수(옅은 주황) 위에 0→내 점수(파랑).
            segment(from: L.trackStartX, to: opponentX, color: CheckTheme.pending.opacity(0.5))
            segment(from: L.trackStartX, to: myX, color: CheckTheme.accent)
            // 끝(100)의 체크 무늬 깃발 — 입구 아이콘과 같은 그림.
            Image(systemName: CrossyDuelEntryIcon.resolved)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CheckTheme.primaryText)
                .frame(width: L.flagWidth, height: L.flagWidth, alignment: .leading)
                .position(x: endX + L.flagWidth / 2, y: midY)
            // 얼굴 점 둘 — 겹치면 점수가 높은 쪽이 위(같으면 나 위).
            let opponentTop = L.opponentOnTop(myScore: snapshot.myScore, opponentScore: snapshot.opponentScore)
            opponentDot
                .position(x: opponentX, y: midY)
                .animation(.easeOut(duration: 0.25), value: snapshot.opponentScore)
                .zIndex(opponentTop ? 2 : 1)
            myDot
                .position(x: myX, y: midY)
                .zIndex(opponentTop ? 1 : 2)
            scores
                .frame(width: L.scoreColumnWidth, alignment: .trailing)
                .position(x: endX + L.flagWidth + L.columnGap + L.scoreColumnWidth / 2, y: midY)
            Text(CrossyDuelText.clock(isFinished ? 0 : (snapshot.remaining ?? 0)))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .frame(width: L.clockWidth, alignment: .trailing)
                .position(x: bandWidth - L.trailingPadding - L.clockWidth / 2, y: midY)
        }
        .frame(width: bandWidth, height: CrossyDuelWindowLayout.raceBandHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(CrossyDuelText.me) \(snapshot.myScore)점, \(opponent.displayName) \(snapshot.opponentScore)점")
    }

    private func segment(from x0: CGFloat, to x1: CGFloat, color: Color) -> some View {
        let width = max(0, x1 - x0)
        return Capsule()
            .fill(color)
            .frame(width: width + L.lineThickness, height: L.lineThickness)
            .position(x: x0 + width / 2, y: midY)
    }

    private var myDot: some View {
        CrossyDuelFaceDot(ring: CheckTheme.accent) {
            CheckAvatarView(name: me.name, userID: myUserID, avatarURL: me.avatarURL,
                            size: L.faceDiameter, characterHint: me.characterID)
        }
    }

    private var opponentDot: some View {
        CrossyDuelFaceDot(ring: CheckTheme.pending) {
            CheckAvatarView(name: opponent.displayName, userID: opponent.id,
                            avatarURL: opponent.avatarURL.flatMap(URL.init(string:)),
                            size: L.faceDiameter, characterHint: opponent.characterID)
        }
    }

    private var scores: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 4) {
                Text(CrossyDuelText.me)
                Text("\(snapshot.myScore)").monospacedDigit()
            }
            .foregroundStyle(CheckTheme.accent)
            HStack(spacing: 4) {
                Text(opponent.displayName).lineLimit(1).truncationMode(.tail)
                Text("\(snapshot.opponentScore)").monospacedDigit().fixedSize()
            }
            .foregroundStyle(CheckTheme.pending)
        }
        .font(.callout.weight(.bold))
    }
}

/// 얼굴 점 하나 — 지름 26 아바타 + 2pt 테두리(SPEC §9.2).
struct CrossyDuelFaceDot<Face: View>: View {
    let ring: Color
    @ViewBuilder let face: Face

    var body: some View {
        ZStack {
            Circle().fill(ring)
            Circle().fill(CheckTheme.panel)
                .frame(width: CrossyDuelRaceTrackLayout.faceDiameter, height: CrossyDuelRaceTrackLayout.faceDiameter)
            face
                .frame(width: CrossyDuelRaceTrackLayout.faceDiameter, height: CrossyDuelRaceTrackLayout.faceDiameter)
                .clipShape(Circle())
        }
        .frame(width: CrossyDuelRaceTrackLayout.dotDiameter, height: CrossyDuelRaceTrackLayout.dotDiameter)
    }
}

// MARK: - 캔버스

/// 캔버스 — **잎 뷰**. 판 루프 틱(`store.tick()`)을 부르는 곳은 여기 하나다. 프레임 상한은 창 자기 주사율
/// (`MiniGameFrameRate` — 리터럴 1/60 금지, v1.1 CC-5)이고 `TimelineView` 간격과 `CrossySceneView(framesPerSecond:)` 둘 다에 넘긴다.
struct CrossyDuelCanvasLeaf: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState
    let previewCanvas: CGImage?
    let frameRateMonitor: MiniGameFrameRateMonitor?
    let onCanvasFrame: (@MainActor (CGRect) -> Void)?

    @State private var pressing = false

    /// 이 주사율에서 쓸 (TimelineView 간격, SCNView fps). nil 이면 공용 모니터(미니게임 창 값).
    static func timing(_ monitor: MiniGameFrameRateMonitor?) -> (interval: TimeInterval, fps: Int) {
        let hz = (monitor ?? MiniGameFrameRateMonitor.shared).refreshHz
        return (MiniGameFrameRate.minimumInterval(forRefreshRate: hz), MiniGameFrameRate.targetFPS(forRefreshRate: hz))
    }

    /// SCNView 를 마운트하는 흐름(v1.1 CC-26 — 로비·준비에서는 안 올린다).
    static func mountsScene(_ phase: CrossyDuelPhase) -> Bool {
        phase == .countdown || phase == .playing || phase == .finished
    }

    var body: some View {
        let phase = store.phase
        let live = store.isWindowVisible && (phase == .countdown || phase == .playing)
        let timing = Self.timing(frameRateMonitor)
        TimelineView(.animation(minimumInterval: timing.interval, paused: !live)) { context in
            let snapshot = store.raceSnapshot()
            ZStack {
                board(phase: phase, fps: timing.fps)
                CrossyDuelCanvasOverlayView(
                    overlay: CrossyDuelCanvasOverlay.resolve(phase: phase, isFinished: match.isFinished,
                                                             outcome: match.outcome, snapshot: snapshot),
                    score: phase == .playing ? snapshot?.myScore : nil)
                if phase == .playing {
                    clickLayer
                }
            }
            .onChange(of: context.date) { _, _ in
                store.tick()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(CrossyDuelPanel.coordinateSpace))
        } action: { frame in
            onCanvasFrame?(frame)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CrossyDuelText.keysAccessibility)
    }

    @ViewBuilder
    private func board(phase: CrossyDuelPhase, fps: Int) -> some View {
        if let previewCanvas {
            Image(decorative: previewCanvas, scale: 2)
                .resizable()
                .interpolation(.high)
                .frame(width: CrossyDuelWindowLayout.canvasSize.width, height: CrossyDuelWindowLayout.canvasSize.height)
        } else if Self.mountsScene(phase) {
            CrossyDuelSceneLeaf(game: store.duel?.game ?? Self.placeholder(match), framesPerSecond: fps,
                                ghost: store.opponentGhost)
        } else {
            CrossyDuelWaitingBoard()
        }
    }

    /// 판 구동기가 아직 없을 때(판 씨앗을 받기 전) 그릴 판 — 같은 씨앗이면 같은 길이다.
    static func placeholder(_ match: CrossyDuelMatchState) -> CrossyGame {
        CrossyGame(seed: UInt64(clamping: max(0, match.seed ?? 0)), rules: .duel)
    }

    /// 클릭 = 앞으로 한 칸 — 캔버스 위 투명 제스처 층(SCNView 는 마우스를 안 받는다). 누르는 순간 한 번(뗌이 아니라).
    private var clickLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        store.forward()
                    }
                    .onEnded { _ in pressing = false }
            )
    }
}

/// 3D 판 — 씬은 잎 `@StateObject` 로 **한 번** 만든다(`CrossyScene` 머리 주석 — `@State` 면 다시 지을 때마다 모델을 다시 읽는다).
private struct CrossyDuelSceneLeaf: View {
    let game: CrossyGame
    let framesPerSecond: Int
    /// 상대 반투명 그림자(11-10 — 상대 프레임에 위치가 실려 올 때만).
    var ghost: CrossyDuelGhost? = nil

    @StateObject private var scene = CrossyScene.mac()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CrossySceneView(scene: scene, game: game, reduceMotion: reduceMotion, framesPerSecond: framesPerSecond, ghost: ghost)
    }
}

/// 준비 단계 캔버스(SCNView 를 올리지 않는다 — CC-26).
private struct CrossyDuelWaitingBoard: View {
    var body: some View {
        ZStack {
            CrossyHUDBackdrop()
            VStack(spacing: 10) {
                Image(systemName: CrossyDuelEntryIcon.resolved)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                Text(CrossyDuelText.waitingTitle)
                    .font(.headline)
                Text(CrossyDuelText.waitingAction)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        }
    }
}

/// 3D 가 서기 전의 바탕 — 풀밭 초록을 어둡게 눌렀다(로비 카드와 이어지게).
private struct CrossyHUDBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.20), Color(red: 0.10, green: 0.13, blue: 0.16)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// 캔버스 글자 겹 한 장(순수 — 값만 그린다). 위 가운데 내 점수(솔로 HUD 와 같은 자리·모양) + 겹 하나.
struct CrossyDuelCanvasOverlayView: View {
    let overlay: CrossyDuelCanvasOverlay?
    /// 위 가운데 점수(판 중에만 — 결과·카운트다운엔 nil).
    let score: Int?

    var body: some View {
        ZStack {
            if let score, !hidesScore {
                GeometryReader { geo in
                    Text("\(score)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                        .shadow(color: .black.opacity(0.40), radius: 7)
                        .position(x: geo.size.width / 2, y: CrossyHUD.scoreCenterY)
                }
            }
            switch overlay {
            case .result(let outcome)?:
                Color.black.opacity(0.35)
                card(icon: CrossyDuelResultCard.icon(outcome), tint: CrossyDuelResultCard.tint(outcome),
                     title: CrossyDuelText.outcomeTitle(outcome), caption: nil)
            case .waiting(let goal)?:
                Color.black.opacity(0.30)
                card(icon: goal ? "flag.checkered" : "timer", tint: goal ? CheckTheme.accent : CheckTheme.pending,
                     title: goal ? CrossyDuelText.goalWaiting : CrossyDuelText.timeWaiting, caption: nil)
            case .respawn(let digit)?:
                bigDigit(digit, caption: CrossyDuelText.respawnCaption, tint: CheckTheme.pending)
            case .countdown(let digit)?:
                Color.black.opacity(0.25)
                bigDigit(digit, caption: CrossyDuelText.countdownCaption, tint: CheckTheme.accent)
            case nil:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
    }

    /// 판정 기다림·결과 겹이 서면 점수 글자는 카드에 양보한다(겹이 겹치지 않게).
    private var hidesScore: Bool {
        switch overlay {
        case .result?, .waiting?: return true
        default: return false
        }
    }

    private func card(icon: String, tint: Color, title: String, caption: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .foregroundStyle(CheckTheme.primaryText)
                .multilineTextAlignment(.center)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(CheckTheme.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.55), lineWidth: 1))
    }

    private func bigDigit(_ digit: String, caption: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(digit)
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                .shadow(color: .black.opacity(0.40), radius: 10)
            Text(caption)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        }
    }
}

// MARK: - 오른쪽 열

private struct CrossyDuelMatchSide: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState
    @Binding var confirmResign: Bool
    let showsConfirmPreview: Bool

    /// 이 화면(이 판)이 나타난 시각 — [기권] 누름 판정의 기준(`GomokuResignGuard`).
    @State private var shownAt: Date?

    private var showsConfirm: Bool { confirmResign || showsConfirmPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: CrossyDuelWindowLayout.sideSpacing) {
            if match.isFinished {
                CrossyDuelResultCard(store: store, match: match)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let status = statusLine {
                    statusCard(status)
                }
                CrossyDuelOpponentCard(store: store, match: match)
            }
            CrossyDuelLiveStats(store: store, match: match)
            if !match.isFinished {
                keysCard
            }
            Spacer(minLength: 0)
            actionRow
                .frame(height: CrossyDuelWindowLayout.actionRowHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { shownAt = GomokuResignGuard.clock() }
        .onChange(of: match.id) { _, _ in
            shownAt = GomokuResignGuard.clock()
            confirmResign = false
        }
        .onChange(of: store.isWindowVisible) { _, visible in
            if visible { shownAt = GomokuResignGuard.clock() }
        }
        // 확인이 아무 선택 없이 오래 서 있으면 스스로 접는다(다음 누름 하나가 곧 기권이 되지 않게).
        .task(id: confirmResign) {
            guard confirmResign else { return }
            try? await Task.sleep(for: .seconds(GomokuResignGuard.confirmTimeout))
            guard !Task.isCancelled else { return }
            confirmResign = false
        }
    }

    /// 판 위 안내 한 줄(있을 때만): 다른 기기 > 안내 > 준비 대기 > 카운트다운.
    private var statusLine: (title: String, detail: String?)? {
        if store.playingElsewhere { return (CrossyDuelNoticeText.otherDevice, CrossyDuelText.otherDeviceSubtitle) }
        if let notice = store.notice { return (notice, nil) }
        switch store.phase {
        case .ready:
            let seconds = match.readyDeadline.map { Int(max(0, $0.timeIntervalSince(store.clock())).rounded(.up)) }
            return (CrossyDuelText.waitingTitle, seconds.map(CrossyDuelText.waitingSubtitle(seconds:)) ?? CrossyDuelText.waitingAction)
        case .countdown:
            return (CrossyDuelText.startingSoon, CrossyDuelText.gameHint)
        case .playing, .finished, .lobby:
            return nil
        }
    }

    private func statusCard(_ status: (title: String, detail: String?)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(status.title)
                .font(.callout.weight(.bold))
                .foregroundStyle(CheckTheme.pending)
                .lineLimit(1)
            if let detail = status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .crossyDuelCard(padding: 12)
    }

    private var keysCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CrossyDuelText.keysLine)
            Text(CrossyDuelText.clickLine)
        }
        .font(.caption)
        .foregroundStyle(CheckTheme.secondaryText)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crossyDuelCard(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CrossyDuelText.keysAccessibility)
    }

    /// 판정 기다림(100 도달 · 3분 얼림) — [기권] 을 끈다(스토어 `resign()` 도 같은 조건에서 보내지 않는다).
    private var waitingForResult: Bool { store.raceSnapshot()?.waitingForResult ?? false }

    @ViewBuilder
    private var actionRow: some View {
        if match.isFinished {
            TetrisDuelActionButton(title: CrossyDuelText.backToLobby, icon: "chevron.left", style: .outline,
                                   height: CrossyDuelWindowLayout.actionRowHeight, fullWidth: true) {
                store.backToLobby()
            }
            .focusable(false)
        } else if showsConfirm {
            HStack(spacing: 8) {
                TetrisDuelActionButton(title: CrossyDuelText.confirmResign, icon: "flag.fill", tint: CheckTheme.danger,
                                       height: CrossyDuelWindowLayout.actionRowHeight, fullWidth: true,
                                       isEnabled: !store.isBusy && !waitingForResult) {
                    confirmResign = false
                    Task { await store.resign() }
                }
                // 스페이스·↩ 로 눌리지 않는다 — 판 중 스페이스는 '앞으로'다(키 모니터가 삼키지만 한 번 더 막는다).
                .focusable(false)
                .checkTooltip(CrossyDuelText.resignWarning)
                TetrisDuelActionButton(title: CrossyDuelText.keepPlaying, tint: CheckTheme.offWork, style: .outline,
                                       height: CrossyDuelWindowLayout.actionRowHeight, fullWidth: true) {
                    confirmResign = false
                }
                .focusable(false)
            }
        } else {
            TetrisDuelActionButton(title: CrossyDuelText.resign, tint: CheckTheme.danger, style: .outline,
                                   height: CrossyDuelWindowLayout.actionRowHeight, fullWidth: true,
                                   isEnabled: !store.isBusy && !store.playingElsewhere && !waitingForResult) {
                // 화면이 막 나타난 직후의 누름(로비 [수락] 더블클릭의 두 번째 누름)은 이 화면을 보고 누른 것이 아니다.
                guard GomokuResignGuard.acceptsTap(shownAt: shownAt, now: GomokuResignGuard.clock()) else { return }
                confirmResign = true
            }
            .focusable(false)
            .checkTooltip(CrossyDuelText.resignHelp)
        }
    }
}

/// 상대 카드(시안 — "상대" · 얼굴 · 이름 · 상태 점). 상태는 판 값(`opponentQuiet`)을 읽어 잎 TimelineView 안에서 고른다.
private struct CrossyDuelOpponentCard: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CrossyDuelText.opponentTitle)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
            HStack(spacing: 12) {
                CheckAvatarView(name: match.opponent.displayName, userID: match.opponent.id,
                                avatarURL: match.opponent.avatarURL.flatMap(URL.init(string:)), size: 40,
                                characterHint: match.opponent.characterID)
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.opponent.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    CrossyDuelOpponentPresence(store: store, match: match)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .crossyDuelCard(padding: 12)
    }
}

/// 상대 상태 한 줄 — **잎**(초를 읽는 것은 여기 TimelineView 뿐이다).
struct CrossyDuelOpponentPresence: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState

    var body: some View {
        let live = store.isWindowVisible && !match.isFinished
        TimelineView(.animation(minimumInterval: 0.5, paused: !live)) { _ in
            let quiet = store.raceSnapshot()?.opponentQuiet ?? false
            let label = Self.label(phase: store.phase, match: match, quiet: quiet)
            HStack(spacing: 5) {
                Circle()
                    .fill(label.tint)
                    .frame(width: 7, height: 7)
                Text(label.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(quiet ? CheckTheme.pending : CheckTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    /// 상태 글자(순수): 끝남 > 연결 확인 중(판 중 `opponentQuiet`) > 판 중 "달리는 중" > 준비 완료 / 들어오는 중.
    static func label(phase: CrossyDuelPhase, match: CrossyDuelMatchState, quiet: Bool) -> (text: String, tint: Color) {
        if match.isFinished || phase == .finished { return (CrossyDuelText.finishedPresence, CheckTheme.offWork) }
        switch phase {
        case .playing:
            return quiet ? (CrossyDuelText.opponentQuiet, CheckTheme.pending) : (CrossyDuelText.running, CheckTheme.working)
        case .countdown:
            return (CrossyDuelText.ready, CheckTheme.working)
        case .ready, .lobby, .finished:
            return match.opponentReady ? (CrossyDuelText.ready, CheckTheme.working)
                                       : (CrossyDuelText.notReady, CheckTheme.pending)
        }
    }
}

/// 죽은 횟수 · 목표 — **잎**(내 죽음은 로컬 엔진 값이라 관찰 대상이 아니다).
private struct CrossyDuelLiveStats: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState

    var body: some View {
        let live = store.isWindowVisible && store.phase == .playing
        TimelineView(.animation(minimumInterval: 0.25, paused: !live)) { _ in
            let snapshot = store.raceSnapshot()
            VStack(spacing: 8) {
                row(CrossyDuelText.deathsTitle,
                    CrossyDuelText.deathsLine(me: snapshot?.myDeaths ?? 0,
                                              opponent: snapshot?.opponentDeaths ?? match.opponentDeaths))
                row(CrossyDuelText.goalTitle, CrossyDuelText.goalLine(snapshot?.goal ?? CrossyDuelSession.expectedGoal))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .crossyDuelCard(padding: 12)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(CheckTheme.secondaryText)
            Spacer(minLength: 6)
            Text(value).monospacedDigit().lineLimit(1)
        }
        .font(.callout)
    }
}

// MARK: - 결과 카드

/// 결과 카드(오른쪽 열, 테트리스 틀) — 승·패·무 아이콘 + 사유 + 굳은 점수 "나 100 : 상대 87" + 루비 순수익. [로비로] 는 아래 줄.
struct CrossyDuelResultCard: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState

    static func tint(_ outcome: CrossyDuelOutcome?) -> Color {
        switch outcome {
        case .win?: return CheckTheme.working
        case .loss?: return CheckTheme.danger
        default: return CheckTheme.offWork
        }
    }

    static func icon(_ outcome: CrossyDuelOutcome?) -> String {
        switch outcome {
        case .win?: return "trophy.fill"
        case .loss?: return "xmark.circle.fill"
        default: return "equal.circle.fill"
        }
    }

    /// 루비 증감 — 스토어가 낸 값(승 `DuelFee.winnerNet` · 패 −판돈 · 무 0). 없으면 같은 식으로 다시 낸다.
    static func delta(_ match: CrossyDuelMatchState) -> Int {
        if let rubyDelta = match.rubyDelta { return rubyDelta }
        switch match.outcome {
        case .win?: return DuelFee.winnerNet(stake: match.stake)
        case .loss?: return -match.stake
        default: return 0
        }
    }

    /// 굳은 점수 줄을 그리는가 — 판이 열리지 않은 끝(no_show)은 0:0 이라 말할 것이 없다.
    static func showsScores(_ match: CrossyDuelMatchState) -> Bool { match.endReason != .noShow }

    var body: some View {
        let tint = Self.tint(match.outcome)
        let delta = Self.delta(match)
        // Q3 답 (가): goal 로 진 판만 max(final.me, 로컬). 로컬 = 이 기기 엔진의 점수(끝난 판이라 더 안 움직인다).
        let mine = CrossyDuelText.resultMyScore(finalMe: match.finalMyScore, local: store.duel?.game.score,
                                                reason: match.endReason, outcome: match.outcome)
        let reason = CrossyDuelNoticeText.endReason(match.endReason, outcome: match.outcome,
                                                    meReady: match.meReady, opponentReady: match.opponentReady)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: Self.icon(match.outcome))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                Text(CrossyDuelText.outcomeTitle(match.outcome))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 4)
            }
            if !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if Self.showsScores(match) {
                Text(CrossyDuelText.finalScoreLine(me: mine, opponent: match.finalOpponentScore ?? match.opponentScore))
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                RubyIcon(size: 16)
                Text(CrossyDuelText.rubyLine(delta))
                    .font(delta == 0 ? .callout.weight(.semibold) : .title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? CheckTheme.working
                                     : (delta < 0 ? CheckTheme.danger : CheckTheme.secondaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .crossyDuelCard(padding: 12)
    }
}
