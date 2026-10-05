import Foundation

// v0.3.44 — 체스 말이 **움직이는 동안**을 담는 값.
//
// 0.3.43 의 판은 멈춘 국면 하나를 Canvas 한 장에 그렸다. `position` 이 바뀌면 다음 프레임에 새 배치가 그대로 찍혀
// 말이 순간이동하고 잡힌 말은 그 프레임에 사라진다 — 따라갈 수가 없다. 그래서 애니메이션을
// **`(시작 시각, 길이, 움직이는 말들)` 을 담은 순수 값**으로 두고, 어떤 프레임이든 `now` 하나로 결정한다.
//
// 왜 `withAnimation`·`matchedGeometryEffect` 가 아닌가:
//   · 판은 Canvas 한 장이라 말마다 뷰가 없다 — `matchedGeometryEffect` 를 쓰려면 64칸 뷰로 갈라야 한다.
//   · `withAnimation` 으로 `@State` 를 0→1 차는 길은 같은 틱의 상태 쓰기가 합쳐져 0 프레임이 안 그려지는
//     고전 함정이 있고, **중간 프레임을 밖에서 재현할 수 없어** 이 파일 같은 테스트를 짤 수가 없다.
//   · 이 저장소는 이미 `TimelineView(.animation(minimumInterval:paused:))` 로 시계·미니게임을 굴린다 —
//     주사율 저더 함정(`MiniGameFrameRate`)을 아는 길이다.
//
// 그래서 이 파일에는 시각·이징·칸 셈만 있다. 화면 좌표도, 뒤집기도, 색도 없다(그건 `ChessBoardGeometry` 와 뷰).

/// 판 위에서 **움직이는 중인 수 하나**. 순수 값 — `now` 하나면 어느 프레임이든 결정적이다.
package nonisolated struct ChessMoveFlight: Equatable, Sendable {
    /// 미끄러지는 말. 캐슬링은 둘(왕·룩)이고 그 밖에는 하나다.
    package struct Slider: Equatable, Sendable {
        /// 수를 **두기 전**의 말. 승격하는 폰은 **폰으로** 미끄러진다 — 도착해서 퀸이 된다(lichess·chess.com 관례).
        package let piece: ChessPiece
        package let from: ChessSquare
        package let to: ChessSquare

        package init(piece: ChessPiece, from: ChessSquare, to: ChessSquare) {
            self.piece = piece
            self.from = from
            self.to = to
        }
    }

    /// 판에서 빠지는 말.
    package struct Knockout: Equatable, Sendable {
        package let piece: ChessPiece
        /// 잡힌 말이 서 있던 칸. ★ **앙파상이면 도착 칸이 아니다** — 지나친 폰이 선 칸이다.
        package let square: ChessSquare
        /// 밀려나는 방향(칸 단위, 최대 성분이 ±1). 잡은 말이 온 방향을 **그대로 이어** 밀려난다.
        ///
        /// ★ 방향을 **판 좌표**(file/rank)로 담는 까닭: 화면 좌표로 담으면 흑으로 두는 사람(판이 뒤집힌 사람)에게
        ///   엉뚱한 쪽으로 밀려난다. 뒤집기는 `ChessBoardGeometry` 하나가 쥔다.
        package let pushFile: Double
        package let pushRank: Double

        package init(piece: ChessPiece, square: ChessSquare, pushFile: Double, pushRank: Double) {
            self.piece = piece
            self.square = square
            self.pushFile = pushFile
            self.pushRank = pushRank
        }
    }

    package let matchID: String
    package let ply: Int
    /// 세대 — 같은 수가 두 번 들어와도 다시 돌지 않게 하는 꼬리표(저장소가 올린다).
    package let generation: Int
    package let move: ChessMove
    package let sliders: [Slider]
    package let knockout: Knockout?
    package let startedAt: Date
    package let slideDuration: TimeInterval
    package let knockoutDelay: TimeInterval
    package let knockoutDuration: TimeInterval

    package init(matchID: String,
                 ply: Int,
                 generation: Int,
                 move: ChessMove,
                 sliders: [Slider],
                 knockout: Knockout?,
                 startedAt: Date,
                 slideDuration: TimeInterval,
                 knockoutDelay: TimeInterval,
                 knockoutDuration: TimeInterval) {
        self.matchID = matchID
        self.ply = ply
        self.generation = generation
        self.move = move
        self.sliders = sliders
        self.knockout = knockout
        self.startedAt = startedAt
        self.slideDuration = slideDuration
        self.knockoutDelay = knockoutDelay
        self.knockoutDuration = knockoutDuration
    }

    // MARK: - 시간 상수

    /// 거리에 무관한 바닥값. 한 칸 폰 전진도 0.15s 는 미끄러져야 "놓였다"로 보인다.
    package static let slideSecondsBase: TimeInterval = 0.15
    /// 칸당 더하는 값. 룩이 판을 가로지르는데 폰 한 칸과 같은 0.175s 면 **총알처럼** 보인다.
    package static let slideSecondsPerSquare: TimeInterval = 0.025
    /// 뚜껑. 0.3s 를 넘으면 **차례가 느리게 느껴진다** — 블리츠에서 수마다 쌓이는 체감이다.
    package static let slideSecondsCap: TimeInterval = 0.30

    /// 체비셰프 거리(`max(|Δfile|, |Δrank|)`)로 정한 미끄러짐 길이.
    /// 실측값: 한 칸 = 0.175s · 두 칸 = 0.20s · 여섯 칸 = 0.30s(여기서 뚜껑에 닿는다) · 일곱 칸 = 0.30s.
    package static func slideSeconds(distance: Int) -> TimeInterval {
        min(slideSecondsCap, slideSecondsBase + slideSecondsPerSquare * Double(max(0, distance)))
    }

    /// 잡는 말이 **절반쯤 왔을 때** 잡힌 말이 밀리기 시작한다 — 그래야 충격의 순서가 보인다.
    package static let knockoutDelayFraction: Double = 0.45
    /// 밀려나는 데 걸리는 시간. 미끄러짐과 달리 거리에 안 매인다(판에서 빠지는 동작은 어디서나 같다).
    package static let knockoutSeconds: TimeInterval = 0.22

    /// 전체 길이.
    /// ★ 잡는 수는 **잡는 말이 도착한 뒤에도** 잡힌 말이 계속 밀려난다 — 그래야 "먹혔다"가 보인다.
    ///   그래서 `max` 다(`slideDuration` 하나로 끊으면 밀림이 중간에 잘려 그 자리에서 사라진 것처럼 보인다).
    package var duration: TimeInterval { max(slideDuration, knockoutDelay + knockoutDuration) }

    // MARK: - 모양 상수(잡힌 말)

    /// 밀려나는 거리(칸 단위). 한 칸을 다 가면 옆 칸 말과 겹쳐 보여 0.55 칸에서 멈춘다.
    package static let knockoutPushCells: Double = 0.55
    /// 줄어드는 끝 비율. 0 까지 줄이면 '빨려 들어간다'로 보여 절반 남짓만 줄인다.
    package static let knockoutMinScale: Double = 0.55
    /// 흐려짐이 시작되는 지점(이징이 들어간 진행도 기준). 이 값이 클수록 **밀림을 먼저 보여 준다**.
    package static let knockoutFadeStart: Double = 0.35

    // MARK: - 이징

    /// 0 아래·1 위를 자른다. 음수 시각·지난 시각이 들어와도 판이 안 깨지는 근거가 여기 하나다.
    package static func clamp01(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        return min(1, max(0, value))
    }

    /// easeOutCubic. 미끄러짐과 밀려남 **둘 다** 이걸 쓴다 — 말은 놓이는 물건이라 끝에서 느려지는 것이 자연스럽다.
    /// `easeOut(0.5) == 0.875` 이므로 선형(0.5)과 **값이 갈린다**.
    package static func easeOut(_ t: Double) -> Double {
        let x = clamp01(t)
        let inverse = 1 - x
        return 1 - inverse * inverse * inverse
    }

    // MARK: - 진행도

    /// 미끄러짐 진행도(이징 **전**, 0…1).
    package func slideProgress(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(startedAt)
        guard slideDuration > 0 else { return elapsed >= 0 ? 1 : 0 }
        return Self.clamp01(elapsed / slideDuration)
    }

    /// 밀림 진행도(이징 **전**, 0…1). 지연(`knockoutDelay`)이 지나기 전에는 0 이다.
    package func knockoutProgress(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(startedAt) - knockoutDelay
        guard knockoutDuration > 0 else { return elapsed >= 0 ? 1 : 0 }
        return Self.clamp01(elapsed / knockoutDuration)
    }

    /// 다 끝났는가(저장소가 이걸로 값을 거둔다).
    ///
    /// ★ 경계는 **열려 있다**(`>`): 잡기 없는 수는 `duration == slideDuration` 이라 닫으면
    ///   t 가 1 인 마지막 프레임이 한 번도 안 그려지고 말이 도착 칸 직전에서 순간이동한다.
    package func isFinished(now: Date) -> Bool {
        now.timeIntervalSince(startedAt) > duration
    }

    /// 이 시각의 프레임. 다 끝났으면 **nil**(뷰는 멈춘 판을 그린다).
    ///
    /// ★ nil 조건을 `isFinished(now:)` 로 **그대로 부른다** — 두 판정을 따로 적으면 한쪽만 고쳐져
    ///   "끝났는데 안 거둬서 60fps 로 계속 도는" 또는 "거뒀는데 마지막 프레임이 안 그려진" 상태가 된다.
    package func frame(now: Date) -> ChessFlightFrame? {
        guard !isFinished(now: now) else { return nil }

        let slide = Self.easeOut(slideProgress(now: now))
        let moving = sliders.map {
            ChessFlightFrame.Moving(piece: $0.piece, from: $0.from, to: $0.to, t: slide)
        }

        var leaving: ChessFlightFrame.Leaving?
        if let knockout {
            // 잡힌 말은 멈춘 배치(`after`)에 **없다**. 그래서 지연이 지나기 전에도 값을 내야 한다 —
            // 안 내면 잡힌 말이 수가 시작하는 그 프레임에 사라져서 고치려는 증상으로 되돌아간다.
            let eased = Self.easeOut(knockoutProgress(now: now))
            leaving = ChessFlightFrame.Leaving(
                piece: knockout.piece,
                square: knockout.square,
                fileOffset: knockout.pushFile * Self.knockoutPushCells * eased,
                rankOffset: knockout.pushRank * Self.knockoutPushCells * eased,
                scale: 1 - (1 - Self.knockoutMinScale) * eased,
                // ★ **먼저 밀려나고 나중에 흐려진다.** 오프셋·비율은 `eased` 로 깎고 불투명도는 **날 진행도**로
                //   깎는다 — 분자가 `1 - raw` 다. 둘을 같은 `eased` 로 깎으면(처음에 그렇게 썼다) 밀림이 절반
                //   갔을 때 불투명도가 벌써 **0.19**, 80% 에서 **0.012** 가 된다. easeOut 이 움직임의 87.5% 를
                //   앞 절반에 몰아넣기 때문이다. 그러면 잡힌 말은 거의 그 자리에서 사라지고, 고치려는 증상으로
                //   되돌아간다.
                //   날 진행도로 깎으면 불투명도가 **정확히 1** 인 창이 `raw <= knockoutFadeStart` = 0.35,
                //   곧 0.22 × 0.35 = **77ms(60Hz 4.6프레임)**다. 그 끝에서 오프셋은 이미 0.399칸 —
                //   **전체 밀림의 72.5%** 가 불투명한 채로 끝난 뒤에 흐려지기 시작한다. 그게 "먹혔다"로 읽힌다.
                //   (같은 상수를 `eased` 로 쓰면 그 창은 29.4ms = 1.77프레임이다. 실측으로 가른 숫자다.)
                opacity: min(1, (1 - Self.clamp01(knockoutProgress(now: now))) / (1 - Self.knockoutFadeStart)))
        }

        return ChessFlightFrame(moving: moving, leaving: leaving, hidden: Set(sliders.map(\.to)))
    }

    // MARK: - 파생

    /// 수 하나를 보고 애니메이션을 만든다. 못 만들면 nil — 그러면 판은 지금처럼 바로 바뀐다(안전한 폴백).
    ///
    /// `after` 는 **단언용**이다: 수와 국면이 안 맞으면(도착 칸이 비어 있으면) 애니메이션을 안 만든다.
    /// 서버가 이상한 FEN 을 줬을 때 말을 엉뚱한 칸으로 미끄러뜨리는 것보다 안 미끄러뜨리는 게 낫다.
    package static func make(move: ChessMove,
                             before: ChessPosition,
                             after: ChessPosition,
                             matchID: String,
                             ply: Int,
                             generation: Int,
                             startedAt: Date) -> ChessMoveFlight? {
        // 움직인 적 없는 말은 못 미끄러뜨린다.
        guard let mover = before[move.from] else { return nil }
        // 제자리 수는 애니메이션이 아니다. 거리 0 이라 밀림 방향이 0/0(NaN)이 되고, 자기 칸의 말을
        // '잡힌 말'로 세서 스스로를 밀어낸다 — 합법 수 목록에는 없지만 서버 글자는 이 꼴이 될 수 있다.
        guard move.from != move.to else { return nil }
        // 수와 국면이 안 맞는다(도착 칸이 비었다).
        guard after[move.to] != nil else { return nil }

        let deltaFile = move.to.file - move.from.file
        let deltaRank = move.to.rank - move.from.rank
        let distance = max(abs(deltaFile), abs(deltaRank))

        // 잡힘 판정. **순서가 중요하다** — 도착 칸을 먼저 보지 않으면 폰의 보통 잡기를 앙파상으로 읽는다.
        var knockout: Knockout?
        var victim: (piece: ChessPiece, square: ChessSquare)?
        if let captured = before[move.to] {
            victim = (captured, move.to)
        } else if mover.kind == .pawn, move.from.file != move.to.file,
                  let passed = ChessSquare(file: move.to.file, rank: move.from.rank),
                  let captured = before[passed], captured.color != mover.color {
            // 앙파상 — 잡힌 말은 **도착 칸이 아니라** 지나친 칸에 서 있다.
            // 그 칸이 비어 있으면 잡힘 없음으로 떨어뜨린다(서버가 이상한 FEN 을 줬어도 판은 그려야 한다).
            // ★ **색을 본다.** 이 갈래의 칸은 `hidden` 에 안 들어간다(도착 칸이 아니다) — 그래서 거기 선 말이
            //   **내 편**인데 잡힌 말로 세면 그 말이 멈춘 배치에 서 있는 채로 **동시에 밀려나며 흐려진다**.
            //   같은 말이 둘로 보인다. 합법 체스에서는 앙파상 대상 칸에 언제나 적 폰이 있으니 이 조건은
            //   서버 FEN 과 앱 파서가 갈린 응답에서만 일을 한다 — 캐슬링 룩에 색·종류를 보는 것과 같은 이유다.
            victim = (captured, passed)
        }
        if let victim {
            // 최대 성분을 ±1 로 정규화한다 — 잡은 말이 온 방향을 그대로 **잇는다**.
            // 나이트는 (±0.5, ±1) 류가 되어 자기 궤적을 잇고, 룩·퀸·비숍은 정확히 한 축(또는 대각)이 ±1 이다.
            knockout = Knockout(piece: victim.piece,
                                square: victim.square,
                                pushFile: Double(deltaFile) / Double(distance),
                                pushRank: Double(deltaRank) / Double(distance))
        }

        // 캐슬링 — 왕이 두 칸 가면 룩도 같이 미끄러진다. 수는 왕의 두 칸 이동으로만 적히므로(e1g1) 여기서 푼다.
        var sliders: [Slider] = []
        if mover.kind == .king, abs(deltaFile) == 2 {
            let rank = move.from.rank
            let rookFromFile = deltaFile > 0 ? 7 : 0      // 킹사이드 h · 퀸사이드 a
            let rookToFile = deltaFile > 0 ? 5 : 3        // 킹사이드 f · 퀸사이드 d
            // ★ 그 칸에 **그 색 룩이 실제로 있는지** 본다. 없으면(서버가 망가진 국면) 룩 조각만 빼고 왕만 미끄러뜨린다 —
            //   여기서 nil 로 떨어지면 외통으로 끝난 판의 캐슬링이 통째로 순간이동한다.
            if let rookFrom = ChessSquare(file: rookFromFile, rank: rank),
               let rookTo = ChessSquare(file: rookToFile, rank: rank),
               before[rookFrom] == ChessPiece(mover.color, .rook) {
                sliders.append(Slider(piece: ChessPiece(mover.color, .rook), from: rookFrom, to: rookTo))
            }
        }
        // ★ 왕을 **마지막**에 둔다. 배열 뒤가 위에 그려지므로 캐슬링에서 둘이 스치는 구간에 왕이 룩 위에 온다.
        sliders.append(Slider(piece: mover, from: move.from, to: move.to))

        let slide = slideSeconds(distance: distance)
        return ChessMoveFlight(
            matchID: matchID,
            ply: ply,
            generation: generation,
            move: move,
            sliders: sliders,
            knockout: knockout,
            startedAt: startedAt,
            slideDuration: slide,
            // 잡기가 없으면 둘 다 0 이라 `duration == slideDuration` 이다 — 안 그러면 잡지도 않은 수가
            // 0.22s 더 돌아 `TimelineView` 가 쓸데없이 깨어 있다.
            knockoutDelay: knockout == nil ? 0 : knockoutDelayFraction * slide,
            knockoutDuration: knockout == nil ? 0 : knockoutSeconds)
    }
}

/// 그릴 **한 장**. 뷰는 이것만 보고 그린다 — 시각·이징·칸 셈이 하나도 뷰에 없다.
package nonisolated struct ChessFlightFrame: Equatable, Sendable {
    package struct Moving: Equatable, Sendable {
        package let piece: ChessPiece
        package let from: ChessSquare
        package let to: ChessSquare
        /// **이징이 이미 들어간** 0…1. 뷰는 이 값으로 두 칸을 선형 보간한다.
        package let t: Double

        package init(piece: ChessPiece, from: ChessSquare, to: ChessSquare, t: Double) {
            self.piece = piece
            self.from = from
            self.to = to
            self.t = t
        }
    }

    package struct Leaving: Equatable, Sendable {
        package let piece: ChessPiece
        package let square: ChessSquare
        /// 칸 단위 오프셋(화면 오프셋이 아니다 — 뒤집기는 `ChessBoardGeometry` 가 입힌다).
        package let fileOffset: Double
        package let rankOffset: Double
        package let scale: Double
        package let opacity: Double

        package init(piece: ChessPiece,
                     square: ChessSquare,
                     fileOffset: Double,
                     rankOffset: Double,
                     scale: Double,
                     opacity: Double) {
            self.piece = piece
            self.square = square
            self.fileOffset = fileOffset
            self.rankOffset = rankOffset
            self.scale = scale
            self.opacity = opacity
        }
    }

    package let moving: [Moving]
    package let leaving: Leaving?
    /// 멈춘 배치에서 **그리지 않을** 칸 = 날고 있는 말의 **도착** 칸. 안 빼면 말이 두 개로 보인다.
    ///
    /// 잡힌 칸은 여기 **안 들어간다**: 잡힌 말은 멈춘 배치에 이미 없어서 넣어도 아무 일이 안 일어나고,
    /// 들어 있다는 것은 파생이 '도착 칸'과 '잡힌 칸'을 헷갈렸다는 뜻이다(앙파상에서 둘은 다른 칸이다).
    package let hidden: Set<ChessSquare>

    package init(moving: [Moving], leaving: Leaving?, hidden: Set<ChessSquare>) {
        self.moving = moving
        self.leaving = leaving
        self.hidden = hidden
    }
}
