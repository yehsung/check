#if os(iOS)
import CheckCore
import SwiftUI
import UIKit

// 1:1 알까기 폰 판 그림 · 판 뷰(1.0.18). 그림은 맥 `AlkkagiDrawing`(Sources/check/AlkkagiGameView.swift)과 같은 식이다 —
// 나무 판 15줄 · 화점 다섯 · 돌(오목과 같은 돌) · 끌기 띠 · 날아갈 방향 점선 화살(길이 = 힘, 흰 → 주황 → 빨강) · 부딪힘 고리 · 떨어지는 돌.
// 좌표는 판 600 칸(코어 `AlkkagiGame.boardSize`)이고 흑이 아래다(맥과 같다 — 화면을 뒤집지 않는다).

@MainActor
enum GamesAlkkagiDrawing {
    static let woodLight = Color(red: 0.88, green: 0.73, blue: 0.49)
    static let woodDark = Color(red: 0.79, green: 0.62, blue: 0.38)
    static let lineColor = Color(red: 0.30, green: 0.21, blue: 0.12)

    static func board(context: GraphicsContext, size: CGSize) {
        let side = size.width
        let inset = side * 0.06
        let lines = 15
        let cell = (side - inset * 2) / CGFloat(lines - 1)
        context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.025, style: .continuous),
                     with: .linearGradient(Gradient(colors: [woodLight, woodDark]), startPoint: .zero, endPoint: CGPoint(x: side, y: side)))
        var grid = Path()
        let far = inset + CGFloat(lines - 1) * cell
        for i in 0..<lines {
            let offset = inset + CGFloat(i) * cell
            grid.move(to: CGPoint(x: offset, y: inset)); grid.addLine(to: CGPoint(x: offset, y: far))
            grid.move(to: CGPoint(x: inset, y: offset)); grid.addLine(to: CGPoint(x: far, y: offset))
        }
        context.stroke(grid, with: .color(lineColor.opacity(0.85)), lineWidth: max(0.6, side / 640))
        context.stroke(Path(CGRect(x: inset, y: inset, width: far - inset, height: far - inset)),
                       with: .color(lineColor), lineWidth: max(1, side / 380))
        for (x, y) in [(3, 3), (11, 3), (7, 7), (3, 11), (11, 11)] {
            let c = CGPoint(x: inset + CGFloat(x) * cell, y: inset + CGFloat(y) * cell)
            let r = max(1.5, cell * 0.1)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(lineColor))
        }
    }

    static func disc(center p: CGPoint, radius r: Double, player: AlkkagiGame.Player, context: GraphicsContext) {
        var layer = context
        GamesGomokuBoardCanvas.drawStone(&layer, at: p, radius: r, color: player == .black ? .black : .white, opacity: context.opacity)
    }

    static func stone(_ stone: AlkkagiGame.Stone, context: GraphicsContext, scale: Double, selected: Bool, pull: AlkkagiVector,
                      launch: AlkkagiPhoneLaunch?, hits: [AlkkagiPhoneHit], trails: Bool) {
        let point = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let radius = AlkkagiGame.stoneRadius * scale
        if trails, stone.velocity.length > 130 {
            for i in (1...3).reversed() {
                let lag = Double(i) * 0.009
                let p = CGPoint(x: point.x - stone.velocity.x * scale * lag, y: point.y - stone.velocity.y * scale * lag)
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color((stone.owner == .black ? Color(white: 0.15) : Color(white: 0.95)).opacity(0.035 * Double(4 - i))))
            }
        }
        var squash = selected ? min(1, pull.length / AlkkagiGame.maxPull) * 0.09 : 0
        var angle = atan2(pull.y, pull.x)
        if let launch, launch.stoneID == stone.id {
            squash += sin(launch.age * 65) * exp(-launch.age * 22) * launch.power * 0.12
            angle = atan2(launch.direction.y, launch.direction.x)
        }
        if let hit = hits.last(where: { !$0.ringOut && $0.age < 0.1 && (stone.position - $0.position).length < 70 }) {
            squash += hit.strength * exp(-hit.age * 28) * 0.16
            angle = atan2(stone.position.y - hit.position.y, stone.position.x - hit.position.x)
        }
        var shaped = context
        if trails {
            squash = min(0.22, max(-0.12, squash))
            shaped.translateBy(x: point.x, y: point.y)
            shaped.rotate(by: .radians(angle))
            shaped.scaleBy(x: 1 - squash, y: 1 / (1 - squash))
            shaped.translateBy(x: -point.x, y: -point.y)
        }
        disc(center: point, radius: radius, player: stone.owner, context: shaped)
        if selected {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - radius - 5, y: point.y - radius - 5, width: radius * 2 + 10, height: radius * 2 + 10)),
                           with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }
    }

    static func aim(stone: AlkkagiGame.Stone, pull: AlkkagiVector, context: GraphicsContext, scale: Double) {
        guard pull.length > 2 else { return }
        let center = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let grip = CGPoint(x: center.x + pull.x * scale, y: center.y + pull.y * scale)
        let direction = pull * (-1 / pull.length)
        let power = min(1, pull.length / AlkkagiGame.maxPull)
        let spread = AlkkagiGame.stoneRadius * scale * 0.8
        var band = Path()
        band.move(to: CGPoint(x: center.x - direction.y * spread, y: center.y + direction.x * spread))
        band.addLine(to: grip)
        band.addLine(to: CGPoint(x: center.x + direction.y * spread, y: center.y - direction.x * spread))
        let dark = Color(red: 0.19, green: 0.17, blue: 0.14)
        context.stroke(band, with: .color(dark.opacity(0.15)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        context.stroke(band, with: .color(.white.opacity(0.65 + power * 0.35)), style: StrokeStyle(lineWidth: 1.5 + power, lineCap: .round, lineJoin: .round))
        let gripRadius = 5 + power * 2
        context.stroke(Path(ellipseIn: CGRect(x: grip.x - gripRadius, y: grip.y - gripRadius, width: gripRadius * 2, height: gripRadius * 2)),
                       with: .color(.white), lineWidth: 1.5)
        // 날아갈 방향 — 돌 앞으로 점선 화살. 길이 = 힘(어디서 멈출지는 보여 주지 않는다), 색 = 흰 → 주황 → 빨강.
        let radius = AlkkagiGame.stoneRadius * scale
        let length = (36 + 150 * power) * scale
        let from = CGPoint(x: center.x + direction.x * (radius + 4), y: center.y + direction.y * (radius + 4))
        let to = CGPoint(x: from.x + direction.x * length, y: from.y + direction.y * length)
        let tint: Color = power < 0.6 ? .white : (power < 0.9 ? Color(red: 1, green: 0.72, blue: 0.3) : Color(red: 1, green: 0.38, blue: 0.3))
        var guide = Path(); guide.move(to: from); guide.addLine(to: to)
        context.stroke(guide, with: .color(tint.opacity(0.85)), style: StrokeStyle(lineWidth: 2 + power * 1.5, lineCap: .round, dash: [6, 6]))
        let head = 7 + power * 4
        var arrow = Path()
        arrow.move(to: CGPoint(x: to.x - direction.x * head - direction.y * head * 0.6, y: to.y - direction.y * head + direction.x * head * 0.6))
        arrow.addLine(to: to)
        arrow.addLine(to: CGPoint(x: to.x - direction.x * head + direction.y * head * 0.6, y: to.y - direction.y * head - direction.x * head * 0.6))
        context.stroke(arrow, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 2 + power, lineCap: .round, lineJoin: .round))
    }

    static func effects(_ hits: [AlkkagiPhoneHit], context: GraphicsContext, scale: Double, reduced: Bool) {
        for hit in hits {
            let t = hit.age / 0.32
            let radius = (8 + t * (18 + hit.strength * 24)) * scale
            let p = CGPoint(x: hit.position.x * scale, y: hit.position.y * scale)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(.white.opacity((1 - t) * 0.8)), lineWidth: (1 - t) * 2 + 0.5)
            if !reduced, !hit.ringOut, t < 0.35 {
                let flash = (6 + hit.strength * 14) * scale * (1 + t)
                context.fill(Path(ellipseIn: CGRect(x: p.x - flash, y: p.y - flash, width: flash * 2, height: flash * 2)),
                             with: .color(.white.opacity((1 - t / 0.35) * (0.25 + 0.5 * hit.strength))))
            }
            if !reduced {
                let sparks = 5 + Int(hit.strength * 6)
                for i in 0..<sparks {
                    let a = Double(i) / Double(sparks) * .pi * 2
                    let d = radius * 1.3
                    context.fill(Path(ellipseIn: CGRect(x: p.x + cos(a) * d - 1.5, y: p.y + sin(a) * d - 1.5, width: 3, height: 3)),
                                 with: .color(.white.opacity((1 - t) * 0.7)))
                }
            }
        }
    }

    /// 판 밖으로 나간 돌이 떨어진다(판 여백 안 — 판 칸 밖까지 그린다).
    static func falling(_ falls: [AlkkagiPhoneFall], context: GraphicsContext, scale: Double, origin: CGPoint, reduced: Bool) {
        for fall in falls {
            let t = min(1, fall.age / 0.9)
            let outward = fall.outward.length > 0 ? fall.outward * (1 / fall.outward.length) : AlkkagiVector(x: 0, y: 1)
            let distance = (reduced ? 24 * t : 10 + 40 * t) * scale / 0.6
            let p = CGPoint(x: origin.x + fall.position.x * scale + outward.x * distance,
                            y: origin.y + fall.position.y * scale + outward.y * distance + t * t * 60)
            let radius = AlkkagiGame.stoneRadius * scale * (1 - t * 0.25)
            var layer = context
            layer.opacity = reduced ? 1 - t : 1 - t * 0.6
            if !reduced {
                layer.translateBy(x: p.x, y: p.y)
                layer.rotate(by: .radians(t * 0.7 * (outward.x < 0 ? -1 : 1)))
                layer.scaleBy(x: 1, y: 1 - t * 0.25)
                layer.translateBy(x: -p.x, y: -p.y)
            }
            disc(center: p, radius: radius, player: fall.owner, context: layer)
        }
    }

    /// 관전 판에서 그릴 돌(순수 — 맥 `AlkkagiSpectateBoard.stones` 와 같다). 굴림 중이면 shot 을 처음부터 지금까지 되살린 돌.
    static func watchStones(_ watch: AlkkagiWatchState, serverNowMs: Double) -> [AlkkagiGame.Stone] {
        guard watch.phase == .rolling, let shot = watch.shot, shot.startedAtMs.isFinite,
              let shooter = shot.initialStones.first(where: { $0.id == shot.stoneID })?.owner,
              var game = AlkkagiGame.restore(stones: shot.initialStones, currentPlayer: shooter, phase: .aiming,
                                            shotCount: max(0, watch.shotCount - 1)),
              game.shoot(stoneID: shot.stoneID, pull: shot.pull) else { return watch.stones }
        var left = min(shot.duration, max(0, (serverNowMs - shot.startedAtMs) / 1_000))
        while left > 1e-9 && game.phase == .rolling {
            let slice = min(0.25, left)
            _ = game.advance(dt: slice)
            left -= slice
        }
        return game.stones
    }
}

/// 판 뷰 — 판 걸음(TimelineView) · 끌기 손짓 · 흔들림. 판 한 변은 주어진 폭을 꽉 채운다(정사각형).
struct GamesAlkkagiBoardView: View {
    let model: GamesAlkkagiBoardModel
    /// 배치 중 영역 표시(내 쪽 반). 연습 판은 지금 놓는 사람, 서버 판은 내 색.
    var placingPlayer: AlkkagiGame.Player?
    @GestureState private var dragIsActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var haptics = GamesAlkkagiHaptics()
    static let fallMargin: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            surface(side: side)
                .frame(width: side, height: side)
                // 떨어지는 돌은 판 칸 밖(여백)까지 그린다 — 판보다 사방 `fallMargin` 큰 캔버스를 그만큼 당겨 둔다.
                // ★ 겹쳐 그리기(overlay)여야 한다: ZStack 형제로 두면 큰 캔버스가 묶음 크기를 키워 판 전체가 왼쪽 · 위로
                //   `fallMargin` 만큼 밀린다(11-10 캡처 — 판 왼쪽이 화면 끝에 붙었다). 맥 `AlkkagiGameView.board` 도 겹쳐 그린다(background).
                .overlay(alignment: .topLeading) {
                    Canvas { context, _ in
                        GamesAlkkagiDrawing.falling(model.falls, context: context, scale: side / AlkkagiGame.boardSize,
                                                    origin: CGPoint(x: Self.fallMargin, y: Self.fallMargin), reduced: reduceMotion)
                    }
                    .frame(width: side + Self.fallMargin * 2, height: side + Self.fallMargin * 2)
                    .offset(x: -Self.fallMargin, y: -Self.fallMargin)
                    .allowsHitTesting(false)
                }
                .overlay { guideOverlay(side: side) }
                .offset(shakeOffset)
        }
        .aspectRatio(1, contentMode: .fit)
        .background {
            TimelineView(.animation(minimumInterval: 1.0 / Double(MiniGameFrameRate.baselineFPS))) { context in
                Color.clear.onChange(of: context.date) { _, _ in model.tick() }
            }
        }
        .onAppear {
            model.haptic = { [haptics] event in haptics.play(event) }
            // 손 안내 횟수는 이 기기에 기억한다(앱 표준 스위트 — 시험은 모델에 시험 스위트를 직접 넣는다).
            if model.guideDefaults == nil { model.guideDefaults = .standard }
        }
        .onChange(of: dragIsActive) { _, active in
            if !active { model.finishGesture() }
        }
    }

    // MARK: 판 위 안내(폰 1.0.19 — 맥 0.3.86 C안 · 대표 "뭘 하라는건지 모르겠어")

    /// 숨겨 놓기: 판 **가운데 빈 띠**(두 진영 사이 — 돌이 못 오는 곳)에 큰 안내 한 줄.
    /// 쏘기 차례: 손이 내 돌을 뒤로 당기고 날아갈 쪽을 화살로 보여 준다(돌을 잡으면 사라지고, 세 번 쏘고 나면 더 안 나온다).
    @ViewBuilder
    private func guideOverlay(side: CGFloat) -> some View {
        if let hint = model.pullHintStone {
            GamesAlkkagiPullHint(stone: hint, mine: model.guideSide, reduced: reduceMotion)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
        }
        if let text = model.guideBandText {
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(MobileTheme.accent.opacity(0.92)))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
        }
    }

    private var shakeOffset: CGSize {
        guard !reduceMotion else { return .zero }
        let recoil = model.launchRecoil
        return CGSize(width: sin(model.time * 155) * model.jolt * 2.5 + recoil.x * 0.6,
                      height: cos(model.time * 183) * model.jolt * 1.8 + recoil.y * 0.6)
    }

    private func surface(side: CGFloat) -> some View {
        Canvas { context, size in
            GamesAlkkagiDrawing.board(context: context, size: size)
            let scale = size.width / AlkkagiGame.boardSize
            if model.game.phase == .placing, let player = placingPlayer {
                // 둘 수 있는 **실제** 칸만 파랗게 + 점선 + '내 진영', 그 밖은 어둡게(옛 그림은 판 절반을 12% 로만 칠해 거의 안 보였고
                // 300~320 은 칠했는데 못 뒀다 — 맥 0.3.86 과 같은 고침).
                GamesAlkkagiGuideDrawing.zones(context: context, size: size, mine: player)
            }
            for stone in model.game.stones where stone.isPlaced && !stone.isOut {
                GamesAlkkagiDrawing.stone(stone, context: context, scale: scale, selected: stone.id == model.selectedID,
                                          pull: model.pull, launch: model.launch, hits: model.hits, trails: !reduceMotion)
            }
            if let selected = model.selectedStone, model.game.phase == .aiming {
                GamesAlkkagiDrawing.aim(stone: selected, pull: model.pull, context: context, scale: scale)
            }
            if model.guideIsMyAim {
                GamesAlkkagiGuideDrawing.myStones(context: context, scale: scale, stones: model.game.stones, mine: model.guideSide)
            }
            if let preview = model.placementPoint, let id = model.dragPlacementID,
               let stone = model.game.stones.first(where: { $0.id == id }) {
                var layer = context
                layer.opacity = 0.65
                GamesAlkkagiDrawing.disc(center: CGPoint(x: preview.x * scale, y: preview.y * scale),
                                         radius: AlkkagiGame.stoneRadius * scale, player: stone.owner, context: layer)
                let tint = model.game.canPlace(stoneID: id, at: preview) ? MobileTheme.accent : MobileTheme.danger
                let radius = AlkkagiGame.stoneRadius * scale + 3
                context.stroke(Path(ellipseIn: CGRect(x: preview.x * scale - radius, y: preview.y * scale - radius,
                                                     width: radius * 2, height: radius * 2)), with: .color(tint), lineWidth: 2)
            }
            GamesAlkkagiDrawing.effects(model.hits, context: context, scale: scale, reduced: reduceMotion)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($dragIsActive) { _, active, _ in active = true }
            .onChanged { value in
                let scale = AlkkagiGame.boardSize / side
                model.aim(start: AlkkagiVector(x: value.startLocation.x * scale, y: value.startLocation.y * scale),
                          translation: AlkkagiVector(x: value.translation.width * scale, y: value.translation.height * scale))
            }
            .onEnded { _ in model.release() })
        .accessibilityLabel(Text("알까기 바둑판"))
        .accessibilityValue(Text(model.status))
    }
}

/// 관전 판 — 판 화면과 같은 그림 · 입력 없음. 굴림 중이면 서버 시각으로 되살린다.
struct GamesAlkkagiWatchBoard: View {
    let store: AlkkagiOnlineStore
    let watch: AlkkagiWatchState

    var body: some View {
        let rolling = watch.phase == .rolling && watch.shot != nil
        TimelineView(.animation(minimumInterval: 1.0 / Double(MiniGameFrameRate.baselineFPS), paused: !(rolling && store.isWindowVisible))) { _ in
            let stones = GamesAlkkagiDrawing.watchStones(watch, serverNowMs: store.estimatedServerNowMs)
            Canvas { context, size in
                GamesAlkkagiDrawing.board(context: context, size: size)
                let scale = size.width / AlkkagiGame.boardSize
                for stone in stones where stone.isPlaced && !stone.isOut {
                    GamesAlkkagiDrawing.stone(stone, context: context, scale: scale, selected: false,
                                              pull: AlkkagiVector(x: 0, y: 0), launch: nil, hits: [], trails: false)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
        .allowsHitTesting(false)
        .accessibilityLabel(Text("알까기 바둑판(관전)"))
    }
}

/// 판 진동(맥 `NSHapticFeedbackManager` 자리). 돌 잡기 = 선택 틱 · 힘 한 칸 = 가볍게 · 놓기 = 단단 · 쏘기 = 세기만큼 · 세게 부딪힘 = 묵직.
@MainActor
final class GamesAlkkagiHaptics {
    private let select = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    func play(_ event: AlkkagiPhoneHaptic) {
        switch event {
        case .select: select.selectionChanged()
        case .power: light.impactOccurred(intensity: 0.6)
        case .place: rigid.impactOccurred(intensity: 0.6)
        case .launch(let strength): rigid.impactOccurred(intensity: CGFloat(min(1, max(0.3, strength))))
        case .impact(let strength): heavy.impactOccurred(intensity: CGFloat(min(1, max(0.3, strength))))
        }
    }
}
/// 안내 그림(폰 1.0.19 — 맥 `AlkkagiGuideDrawing` 과 같은 그림 · 폰 판 폭(약 350pt)에 맞춰 글자만 한 단계 작게).
enum GamesAlkkagiGuideDrawing {
    /// 숨겨 놓기: 내 칸만 파랗게 + 점선 테두리 + '내 진영' 이름표, 그 밖(상대 칸 + 가운데 빈 띠)은 어둡게.
    static func zones(context: GraphicsContext, size: CGSize, mine: AlkkagiGame.Player) {
        let s = size.width / AlkkagiGame.boardSize
        let blackTop = AlkkagiPhoneGuideGeometry.blackZoneTop * s, whiteBottom = AlkkagiPhoneGuideGeometry.whiteZoneBottom * s
        let lower = CGRect(x: 0, y: blackTop, width: size.width, height: size.height - blackTop)
        let upper = CGRect(x: 0, y: 0, width: size.width, height: whiteBottom)
        let mineRect = mine == .black ? lower : upper
        let theirRect = mine == .black ? upper : lower
        let outside = mine == .black ? CGRect(x: 0, y: 0, width: size.width, height: blackTop)
                                     : CGRect(x: 0, y: whiteBottom, width: size.width, height: size.height - whiteBottom)
        context.fill(Path(outside), with: .color(.black.opacity(0.48)))
        context.fill(Path(mineRect), with: .color(MobileTheme.accent.opacity(0.55)))
        context.stroke(Path(roundedRect: mineRect.insetBy(dx: 3, dy: 3), cornerRadius: 8),
                       with: .color(MobileTheme.accent), style: StrokeStyle(lineWidth: 2.5, dash: [10, 5]))
        let mineLabel = context.resolve(Text(AlkkagiPhoneGuideText.mineZone).font(.footnote.weight(.heavy)).foregroundStyle(.white))
        let labelSize = mineLabel.measure(in: CGSize(width: 200, height: 40))
        let labelY = mine == .black ? mineRect.maxY - 18 : mineRect.minY + 18
        let pill = CGRect(x: mineRect.midX - labelSize.width / 2 - 10, y: labelY - labelSize.height / 2 - 4,
                          width: labelSize.width + 20, height: labelSize.height + 8)
        context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(MobileTheme.accent))
        context.draw(mineLabel, at: CGPoint(x: mineRect.midX, y: labelY))
        let theirLabel = context.resolve(Text(AlkkagiPhoneGuideText.theirZone).font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6)))
        context.draw(theirLabel, at: CGPoint(x: theirRect.midX, y: theirRect.midY))
    }

    /// 쏘기 차례: 쏠 수 있는 내 돌마다 초록 고리(뒤집기의 '둘 수 있는 곳' 점처럼).
    static func myStones(context: GraphicsContext, scale: Double, stones: [AlkkagiGame.Stone], mine: AlkkagiGame.Player) {
        let r = AlkkagiGame.stoneRadius * scale + 4
        for stone in stones where stone.owner == mine && stone.isPlaced && !stone.isOut {
            let p = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(MobileTheme.working.opacity(0.9)), lineWidth: 2.5)
        }
    }

    /// 손 안내 한 장면. `pullFraction` 0…1 = 손이 당긴 정도(1 = 끝까지), `release` 0…1 = 놓은 뒤 화살이 밝아지는 정도.
    static func pullHint(context: GraphicsContext, scale: Double, stone: AlkkagiGame.Stone, mine: AlkkagiGame.Player,
                         pullFraction: Double, release: Double) {
        // 흑(아래)은 아래로 당겨 위로, 백(위)은 위로 당겨 아래로 쏜다. 판 밖으로 손이 나가지 않게 당김 길이를 줄인다.
        let back: Double = mine == .black ? 1 : -1
        let p = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let r = AlkkagiGame.stoneRadius * scale
        let room = mine == .black ? (AlkkagiGame.boardSize - stone.position.y) : stone.position.y
        let fullReach = max(24, min(62, room - 18))
        let pullEnd = CGPoint(x: p.x + 18 * scale * pullFraction, y: p.y + back * fullReach * pullFraction * scale)
        let fullEnd = CGPoint(x: p.x + 18 * scale, y: p.y + back * fullReach * scale)
        if pullFraction > 0.02 {
            var pullPath = Path()
            pullPath.move(to: p)
            pullPath.addLine(to: pullEnd)
            context.stroke(pullPath, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4]))
        }
        // 날아갈 쪽(반대) 화살 — 당긴 반대 방향. 당기기 전에는 기본 방향(상대 쪽 · 조금 비스듬히).
        let dx = pullFraction > 0.02 ? p.x - pullEnd.x : -18 * scale
        let dy = pullFraction > 0.02 ? p.y - pullEnd.y : -back * 62 * scale
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        let ux = dx / len, uy = dy / len
        let start = CGPoint(x: p.x + ux * (r + 5), y: p.y + uy * (r + 5))
        let tip = CGPoint(x: p.x + ux * (r + 78 * scale), y: p.y + uy * (r + 78 * scale))
        let arrow = MobileTheme.working.opacity(0.55 + 0.4 * max(pullFraction, release))
        var flyPath = Path()
        flyPath.move(to: start)
        flyPath.addLine(to: tip)
        context.stroke(flyPath, with: .color(arrow), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - ux * 11 - uy * 7, y: tip.y - uy * 11 + ux * 7))
        head.addLine(to: CGPoint(x: tip.x - ux * 11 + uy * 7, y: tip.y - uy * 11 - ux * 7))
        head.closeSubpath()
        context.fill(head, with: .color(arrow))
        // 손 · 말풍선(손 옆, 판 안쪽으로)
        let hand = context.resolve(Text(Image(systemName: "hand.point.up.left.fill")).font(.system(size: 24)).foregroundStyle(.white))
        context.draw(hand, at: CGPoint(x: pullEnd.x + 8, y: pullEnd.y + back * 6))
        let label = context.resolve(Text(AlkkagiPhoneGuideText.handHint).font(.caption.weight(.bold)).foregroundStyle(.black))
        let size = label.measure(in: CGSize(width: 240, height: 30))
        let bubbleAt = CGPoint(x: fullEnd.x + 8, y: fullEnd.y + back * 6)
        let toLeft = bubbleAt.x + 26 + size.width + 16 > AlkkagiGame.boardSize * scale
        let anchor = CGPoint(x: toLeft ? bubbleAt.x - 26 - size.width / 2 - 8 : bubbleAt.x + 26 + size.width / 2 + 8, y: bubbleAt.y)
        let bubble = CGRect(x: anchor.x - size.width / 2 - 8, y: anchor.y - size.height / 2 - 5,
                            width: size.width + 16, height: size.height + 10)
        context.fill(Path(roundedRect: bubble, cornerRadius: bubble.height / 2), with: .color(.white.opacity(0.95)))
        context.draw(label, at: anchor)
    }
}

/// 손 안내 — 판 위 덮개(입력을 막지 않는다). 동작 줄이기를 켜면 끝까지 당긴 한 장면으로 멈춘다.
struct GamesAlkkagiPullHint: View {
    let stone: AlkkagiGame.Stone
    let mine: AlkkagiGame.Player
    let reduced: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduced)) { context in
            let phase = reduced ? (pull: 1.0, release: 0.0)
                : AlkkagiPhoneGuideGeometry.pullHintPhase(context.date.timeIntervalSinceReferenceDate)
            Canvas { canvas, size in
                GamesAlkkagiGuideDrawing.pullHint(context: canvas, scale: size.width / AlkkagiGame.boardSize, stone: stone, mine: mine,
                                                  pullFraction: phase.pull, release: phase.release)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
