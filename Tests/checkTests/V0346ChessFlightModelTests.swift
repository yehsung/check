import Foundation
import Testing
@testable import CheckCore

// v0.3.44 — 체스 말 이동 애니메이션의 **수학**만 잰다(렌더 없음 · 저장소 없음 · 뷰 없음).
//
// 0.3.43 의 판은 멈춘 국면 하나를 그렸다: `position` 이 바뀌면 다음 프레임에 말이 **순간이동**하고 잡힌 말은
// 그 프레임에 **사라진다**. `ChessMoveFlight` 는 그 사이를 메우는 순수 값이고, 여기서 재는 것은 그 값이
// 내는 숫자 전부다 — 경계·단조성·이징·길이·잡힘 칸·밀림 방향·흐려짐 순서·끝 판정.
//
// 왜 숫자를 직접 재나: 이 모델은 **뷰가 멍청해지는 대가로** 모든 판단을 떠안았다. 밀림 방향 부호가 뒤집히거나
// 흐려짐이 밀림보다 먼저 시작하면 화면은 "그 자리에서 사라진다"로 되돌아가는데, 렌더 테스트는 그걸
// 픽셀 몇 개 차이로만 본다(그리고 ImageRenderer 는 첫 두 장을 다르게 굽는다). 숫자가 그물이다.

/// 시각 기준점. `timeIntervalSinceReferenceDate` 가 **0** 인 순간을 쓴다 — `addingTimeInterval(d)` 뒤
/// `timeIntervalSince` 가 `d` 를 한 비트도 안 틀리고 되돌려주기 때문이다. 1_800_000_000 처럼 큰 값에서는
/// 그 자리의 ulp 가 약 1.2e-7 이라 0.175 가 반올림돼 경계 시각이 `duration` 을 넘을 수도, 못 넘을 수도 있다.
/// 그러면 ①의 "경계가 칸에 꽂힌다" 가 날마다 다르게 떨어진다(값 자체는 실제 앱에서 임의의 Date 다 — 거기서는
/// `TimelineView` 가 주는 시각이 경계에 정확히 꽂히는 일이 없으므로 이 기준점은 단언을 위한 것이다).
private let flT0 = Date(timeIntervalSinceReferenceDate: 0)
private let flMatch = "11111111-1111-1111-1111-111111111111"

private func flMove(_ uci: String) throws -> ChessMove {
    let characters = Array(uci)
    let from = try #require(ChessSquare(String(characters[0...1])), "칸 표기가 아니다: \(uci)")
    let to = try #require(ChessSquare(String(characters[2...3])), "칸 표기가 아니다: \(uci)")
    guard characters.count == 5 else { return ChessMove(from: from, to: to) }
    let promotion = try #require(ChessPieceKind(fenLetter: characters[4]), "승격 글자가 아니다: \(uci)")
    return ChessMove(from: from, to: to, promotion: promotion)
}

/// FEN 국면에서 UCI 수를 **실제로 적용해** 전/후 국면을 만들고 애니메이션을 뽑는다.
/// `after` 를 손으로 짜지 않는 까닭: 파생이 `after[move.to]` 로 "수와 국면이 맞는가"를 보는데,
/// 손으로 짠 `after` 는 그 단언을 공허하게 만든다(엔진이 준 국면이어야 실물이다).
private func flMade(_ fen: String, _ uci: String,
                    ply: Int = 7, generation: Int = 3, startedAt: Date = flT0) throws
    -> (before: ChessPosition, after: ChessPosition, move: ChessMove, flight: ChessMoveFlight) {
    let before = try #require(ChessPosition(fen: fen), "FEN 이 안 읽힌다: \(fen)")
    let move = try flMove(uci)
    let after = try #require(ChessRules.apply(move, to: before), "합법 수가 아니다: \(uci) · \(fen)")
    let flight = try #require(ChessMoveFlight.make(move: move, before: before, after: after,
                                                   matchID: flMatch, ply: ply, generation: generation,
                                                   startedAt: startedAt),
                              "애니메이션을 못 만들었다: \(uci) · \(fen)")
    return (before, after, move, flight)
}

/// 제네릭 제약으로만 통과하는 도우미 — `Sendable` 이 **쓸 수 있는지**를 컴파일 시간에 재는 자리다.
private func flRequireSendable<T: Sendable>(_ value: T) -> T { value }

// 재는 수들. 거리·잡힘·캐슬링·승격이 서로 다른 갈래로 들어가도록 골랐다.
private let flPawnPushFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"            // e2e4: 두 칸 · 잡기 없음
private let flPawnCaptureFEN = "rnbqkbnr/pppp1ppp/8/4p3/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2"     // d4e5: 한 칸 · 오른쪽 위로 잡기
private let flPawnCaptureDownFEN = "rnbqkbnr/pppp1ppp/8/4p3/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq - 1 2" // e5d4: 왼쪽 아래로 잡기
private let flKnightCaptureFEN = "rnbqkbnr/pppp1ppp/8/4p3/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 3"   // f3e5: 나이트 잡기
private let flRookCaptureFEN = "4k3/8/8/8/R6r/8/8/4K3 w - - 0 1"                                  // a4h4: 일곱 칸 잡기
private let flEnPassantFEN = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3"       // e5d6: 앙파상
private let flCastlingFEN = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"                                // e1g1 · e1c1
private let flPromotionFEN = "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"                                    // b7b8q: 승격(잡기 없음)
private let flPromotionCaptureFEN = "1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1"                            // a7b8q: 승격 + 잡기

// MARK: - ① 경계가 칸에 꽂힌다

/// 없으면: 시작 프레임에 말이 출발 칸에서 **이미 떨어져** 있거나(점프) 끝 프레임에 도착 칸에 **못 닿은 채**
/// 값이 거둬져 마지막 몇 픽셀이 순간이동한다 — 고치려던 증상 그대로다.
@Test
func theSlideIsPinnedToTheFromSquareAtZeroAndToTheToSquareAtTheEnd() throws {
    let cases: [(String, String)] = [
        (flPawnPushFEN, "e2e4"), (flPawnCaptureFEN, "d4e5"), (flKnightCaptureFEN, "f3e5"),
        (flRookCaptureFEN, "a4h4"), (flCastlingFEN, "e1g1"), (flPromotionFEN, "b7b8q"),
    ]
    for (fen, uci) in cases {
        let made = try flMade(fen, uci)
        let start = try #require(made.flight.frame(now: flT0), "시작 프레임이 nil 이다: \(uci)")
        #expect(start.moving[0].t == 0, "\(uci) 시작 t")
        // 캐슬링은 둘이 함께 움직인다 — 왕과 룩이 다른 t 로 가면 둘이 어긋나 보인다.
        #expect(start.moving.allSatisfy { $0.t == 0 }, "\(uci) 시작 t 전부")

        let end = try #require(made.flight.frame(now: flT0.addingTimeInterval(made.flight.slideDuration)),
                               "끝 프레임이 nil 이다 — 경계가 닫혀 있다: \(uci)")
        for moving in end.moving {
            #expect(abs(moving.t - 1) <= 1e-9, "\(uci) 끝 t = \(moving.t)")
        }
    }
}

// MARK: - ② 단조 증가

/// 없으면: 이징 식에 부호가 섞여 말이 가다가 **뒤로 밀렸다** 다시 가거나, 1 을 넘겨 도착 칸을 지나친다.
@Test
func theSlideProgressNeverGoesBackwardsAndNeverPassesOne() throws {
    for (fen, uci) in [(flPawnCaptureFEN, "d4e5"), (flRookCaptureFEN, "a4h4"), (flPawnPushFEN, "e2e4")] {
        let flight = try flMade(fen, uci).flight
        var previous = -1.0
        var samples: [Double] = []
        for step in 0...50 {   // 0…duration 을 50등분
            let now = flT0.addingTimeInterval(flight.duration * Double(step) / 50)
            let frame = try #require(flight.frame(now: now), "\(uci) step \(step) 프레임이 nil")
            let t = frame.moving[0].t
            #expect(t >= previous, "\(uci) step \(step): \(t) < \(previous) — 뒤로 갔다")
            #expect(t <= 1, "\(uci) step \(step): \(t) > 1")
            previous = t
            samples.append(t)
        }
        // ★ 기준선이 갈려야 한다: 전부 같은 값이면 위 두 단언은 상수 함수에도 초록이다.
        #expect(samples.first == 0 && samples.last == 1, "\(uci) 양 끝")
        #expect(Set(samples).count > 20, "\(uci) 서로 다른 t 가 \(Set(samples).count) 개뿐 — 값이 안 움직인다")
    }
}

// MARK: - ③ 이징이 실제로 이징이다

/// 없으면: `easeOut` 이 선형으로 바뀌어도 ①②가 전부 초록이다(경계와 단조성은 선형도 만족한다).
/// 선형 미끄러짐은 말이 **등속으로 밀려 멈추는** 느낌이라 놓인 것처럼 안 보인다.
@Test
func theEasingIsActuallyEasingAndNotLinear() throws {
    // 기준선을 명시적으로 가른다 — easeOutCubic 은 절반에서 0.875 다(1 - 0.5³).
    #expect(ChessMoveFlight.easeOut(0.5) == 0.875)
    #expect(ChessMoveFlight.easeOut(0.5) != 0.5, "선형이면 이 줄이 빨개진다")
    #expect(ChessMoveFlight.easeOut(0) == 0)
    #expect(ChessMoveFlight.easeOut(1) == 1)
    // clamp01 이 붙어 있다는 증거: 범위 밖 입력이 끝값으로 잘린다(음수 시각·지난 시각의 근거).
    #expect(ChessMoveFlight.easeOut(-3) == 0)
    #expect(ChessMoveFlight.easeOut(4) == 1)
    #expect(ChessMoveFlight.clamp01(-0.5) == 0)
    #expect(ChessMoveFlight.clamp01(1.5) == 1)
    #expect(ChessMoveFlight.clamp01(0.25) == 0.25)

    for (fen, uci) in [(flPawnCaptureFEN, "d4e5"), (flRookCaptureFEN, "a4h4")] {
        let flight = try flMade(fen, uci).flight
        let half = try #require(flight.frame(now: flT0.addingTimeInterval(flight.slideDuration / 2)))
        #expect(half.moving[0].t > 0.5, "\(uci) 절반 t = \(half.moving[0].t) — 0.5 면 선형이다")
        #expect(abs(half.moving[0].t - 0.875) <= 1e-9, "\(uci) 절반 t")
    }
}

// MARK: - ④ 거리에 따라 길이가 다르다

/// 없으면: 길이가 상수로 굳어 룩이 판을 가로지르는데 폰 한 칸과 같은 시간(총알처럼 보인다)이거나
/// 폰 한 칸이 룩과 같은 시간(늘어진다)이 된다.
@Test
func theSlideLengthGrowsWithDistanceAndStopsAtTheCap() throws {
    // 상수 셋을 각각 고정한다: 바닥 0.15 · 칸당 0.025 · 뚜껑 0.30.
    #expect(ChessMoveFlight.slideSeconds(distance: 0) == 0.15)
    #expect(ChessMoveFlight.slideSeconds(distance: 1) == 0.175)
    #expect(ChessMoveFlight.slideSeconds(distance: 2) == 0.20)
    #expect(ChessMoveFlight.slideSeconds(distance: 6) == 0.30, "여기서 뚜껑에 처음 닿는다")
    #expect(ChessMoveFlight.slideSeconds(distance: 7) == 0.30)
    #expect(ChessMoveFlight.slideSeconds(distance: 99) == ChessMoveFlight.slideSecondsCap)

    // ★ 기준선 확인: 두 값이 **실제로 다른** 수 두 개다(한 칸 d4e5 · 일곱 칸 a4h4).
    let short = try flMade(flPawnCaptureFEN, "d4e5").flight
    let long = try flMade(flRookCaptureFEN, "a4h4").flight
    #expect(short.slideDuration == 0.175)
    #expect(long.slideDuration == 0.30)
    #expect(short.slideDuration != long.slideDuration)
    #expect(short.slideDuration < long.slideDuration)
    #expect(long.slideDuration <= ChessMoveFlight.slideSecondsCap, "뚜껑을 넘었다")

    // 체비셰프다(유클리드가 아니다): 대각 한 칸은 직교 한 칸과 같은 길이다.
    let diagonal = try flMade(flPawnCaptureFEN, "d4e5").flight          // Δfile 1 · Δrank 1
    #expect(diagonal.slideDuration == ChessMoveFlight.slideSeconds(distance: 1))
    // 나이트는 (1,2) 라 두 칸으로 센다.
    let knight = try flMade(flKnightCaptureFEN, "f3e5").flight
    #expect(knight.slideDuration == ChessMoveFlight.slideSeconds(distance: 2))
}

// MARK: - ⑤ 보통의 잡기

/// 없으면: 잡힌 말이 아무 데도 안 담겨 멈춘 배치에서 **그 프레임에 사라진다**.
@Test
func anOrdinaryCaptureKnocksOutThePieceStandingOnTheDestination() throws {
    let made = try flMade(flPawnCaptureFEN, "d4e5")
    let knockout = try #require(made.flight.knockout)
    #expect(knockout.square == ChessSquare("e5"))
    #expect(knockout.square == made.move.to, "보통의 잡기는 잡힌 칸 = 도착 칸이다")
    #expect(knockout.piece == ChessPiece(.black, .pawn))
    // 미끄러지는 말은 잡는 쪽이다(잡힌 쪽이 아니다).
    #expect(made.flight.sliders.count == 1)
    #expect(made.flight.sliders[0].piece == ChessPiece(.white, .pawn))
    #expect(made.flight.sliders[0].from == ChessSquare("d4"))
    #expect(made.flight.sliders[0].to == ChessSquare("e5"))
    // 꼬리표가 그대로 실려 와야 저장소가 "어느 판의 몇 수째"를 가린다.
    #expect(made.flight.matchID == flMatch)
    #expect(made.flight.ply == 7)
    #expect(made.flight.generation == 3)
    #expect(made.flight.move == made.move)
}

// MARK: - ⑥ 앙파상 — 잡힌 칸이 도착 칸이 아니다

/// 없으면: 앙파상에서 지나친 폰이 **제자리에서 사라지고** 도착 칸의 빈 칸이 밀려난다(아무것도 안 보인다).
/// 도착 칸을 먼저 보지 않는 파생은 폰의 보통 잡기까지 앙파상으로 읽는다.
@Test
func enPassantKnocksOutThePawnThatIsNotOnTheDestinationSquare() throws {
    let made = try flMade(flEnPassantFEN, "e5d6")
    let knockout = try #require(made.flight.knockout)
    #expect(knockout.square == ChessSquare("d5"), "지나친 폰이 선 칸")
    #expect(knockout.square != made.move.to, "★ 앙파상은 잡힌 칸 ≠ 도착 칸이다")
    #expect(made.move.to == ChessSquare("d6"))
    #expect(knockout.piece == ChessPiece(.black, .pawn))
    // 온 방향을 잇는다: e5 → d6 은 왼쪽 위다.
    #expect(knockout.pushFile == -1)
    #expect(knockout.pushRank == 1)

    let frame = try #require(made.flight.frame(now: flT0))
    #expect(frame.hidden == [ChessSquare("d6")!], "도착 칸만 가린다")
    #expect(frame.hidden.contains(ChessSquare("d6")!))
    // ★ 잡힌 칸은 멈춘 배치에 이미 없다 — 넣어도 아무 일이 안 일어나지만, 들어 있다는 것은
    //   파생이 '도착 칸'과 '잡힌 칸'을 헷갈렸다는 뜻이다(보통의 잡기에서는 둘이 같아서 안 드러난다).
    #expect(!frame.hidden.contains(ChessSquare("d5")!))

    // 기준선이 갈린다: 같은 폰의 **보통** 잡기는 둘이 같은 칸이다(⑤) — 위 단언이 공허하지 않다.
    let ordinary = try flMade(flPawnCaptureFEN, "d4e5")
    let ordinaryKnockout = try #require(ordinary.flight.knockout)
    #expect(ordinaryKnockout.square == ordinary.move.to)
}

// MARK: - ⑦ 캐슬링 양쪽

/// 없으면: 룩이 순간이동한다(캐슬링은 수 글자가 왕의 두 칸 이동뿐이라 룩을 여기서 풀지 않으면 아무도 안 푼다).
@Test
func castlingSlidesBothPiecesWithTheKingDrawnOnTop() throws {
    // 킹사이드: 룩 h1 → f1
    let kingside = try flMade(flCastlingFEN, "e1g1")
    #expect(kingside.flight.sliders.count == 2)
    #expect(kingside.flight.sliders[0].piece == ChessPiece(.white, .rook))
    #expect(kingside.flight.sliders[0].from == ChessSquare("h1"))
    #expect(kingside.flight.sliders[0].to == ChessSquare("f1"))
    // ★ 왕이 배열 **마지막**이다 — 배열 뒤가 위에 그려지므로 스치는 구간에 왕이 룩 위에 온다.
    #expect(kingside.flight.sliders.last?.piece == ChessPiece(.white, .king))
    #expect(kingside.flight.sliders.last?.from == ChessSquare("e1"))
    #expect(kingside.flight.sliders.last?.to == ChessSquare("g1"))
    #expect(kingside.flight.knockout == nil, "캐슬링은 잡기가 아니다")
    let kingsideFrame = try #require(kingside.flight.frame(now: flT0))
    #expect(kingsideFrame.hidden == [ChessSquare("f1")!, ChessSquare("g1")!], "두 도착 칸 다 가린다")

    // 퀸사이드: 룩 a1 → d1
    let queenside = try flMade(flCastlingFEN, "e1c1")
    #expect(queenside.flight.sliders.count == 2)
    #expect(queenside.flight.sliders[0].from == ChessSquare("a1"))
    #expect(queenside.flight.sliders[0].to == ChessSquare("d1"))
    #expect(queenside.flight.sliders.last?.piece == ChessPiece(.white, .king))
    #expect(queenside.flight.sliders.last?.to == ChessSquare("c1"))
    let queensideFrame = try #require(queenside.flight.frame(now: flT0))
    #expect(queensideFrame.hidden == [ChessSquare("c1")!, ChessSquare("d1")!])

    // 흑도 같은 모양이다(랭크만 다르다) — 랭크를 상수로 박으면 여기서 빨개진다.
    let blackFEN = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1"
    let blackKingside = try flMade(blackFEN, "e8g8")
    #expect(blackKingside.flight.sliders[0].piece == ChessPiece(.black, .rook))
    #expect(blackKingside.flight.sliders[0].from == ChessSquare("h8"))
    #expect(blackKingside.flight.sliders[0].to == ChessSquare("f8"))
    #expect(blackKingside.flight.sliders.last?.piece == ChessPiece(.black, .king))

    // 기준선: 캐슬링이 아닌 왕의 한 칸 이동은 미끄러지는 말이 하나다.
    let step = try flMade("4k3/8/8/8/8/8/8/4K3 w - - 0 1", "e1f1")
    #expect(step.flight.sliders.count == 1)
}

// MARK: - ⑧ 룩이 없는 캐슬링 꼴

/// 없으면: 서버가 망가진 국면(룩 없는 왕의 두 칸 이동)을 주면 파생이 nil 로 떨어져 **외통으로 끝난 판의
/// 그 수가 통째로 순간이동한다** — 왜 끝났는지 알 수 없다. 왕만 미끄러져도 보여 주는 게 낫다.
@Test
func aCastlingShapeWithNoRookStillSlidesTheKing() throws {
    // 손으로 짠 국면이다(엔진은 이 꼴을 만들지 않는다 — 그게 이 테스트의 전부다).
    var before = ChessPosition.empty
    before[ChessSquare("e1")!] = ChessPiece(.white, .king)
    var after = ChessPosition.empty
    after[ChessSquare("g1")!] = ChessPiece(.white, .king)

    let flight = try #require(ChessMoveFlight.make(move: try flMove("e1g1"), before: before, after: after,
                                                   matchID: flMatch, ply: 1, generation: 1, startedAt: flT0),
                              "★ nil 로 떨어졌다")
    #expect(flight.sliders.count == 1)
    #expect(flight.sliders[0].piece == ChessPiece(.white, .king))
    #expect(flight.sliders[0].from == ChessSquare("e1"))
    #expect(flight.sliders[0].to == ChessSquare("g1"))
    #expect(flight.knockout == nil)

    // 엉뚱한 말이 모퉁이에 있어도 (색이 다른 룩도) 같다 — 룩이라고 확인하는 자리가 있다는 증거.
    var wrongCorner = before
    wrongCorner[ChessSquare("h1")!] = ChessPiece(.black, .rook)
    let wrong = try #require(ChessMoveFlight.make(move: try flMove("e1g1"), before: wrongCorner, after: after,
                                                  matchID: flMatch, ply: 1, generation: 1, startedAt: flT0))
    #expect(wrong.sliders.count == 1, "흑 룩을 백의 캐슬링 룩으로 셌다")

    // 기준선: 그 색 룩이 있으면 둘이다(위 단언이 "언제나 1" 로 굳은 게 아니다).
    var withRook = before
    withRook[ChessSquare("h1")!] = ChessPiece(.white, .rook)
    let paired = try #require(ChessMoveFlight.make(move: try flMove("e1g1"), before: withRook, after: after,
                                                   matchID: flMatch, ply: 1, generation: 1, startedAt: flT0))
    #expect(paired.sliders.count == 2)
}

// MARK: - ⑧b 앙파상 꼴인데 지나친 칸에 **내 편** 폰이 섰다

/// 없으면: 그 폰이 **멈춘 배치에 서 있는 채로 동시에 밀려나며 흐려진다** — 같은 말이 둘로 보인다.
/// 왜 앙파상만 이 병을 앓나: 이 갈래의 잡힌 칸은 **도착 칸이 아니라서 `hidden` 에 안 들어간다**.
/// 보통의 잡기는 잡힌 칸 = 도착 칸이고 그 칸이 `hidden` 이므로 멈춘 배치가 그리지 않는다.
///
/// 도달 조건은 서버 FEN 과 앱 파서가 갈린 응답뿐이다(합법 체스에서 앙파상 대상 칸에는 언제나 적 폰이 있다).
/// 그래도 캐슬링 룩에 색·종류를 보는 것과 **같은 이유**로 본다 — 망가진 국면에서 더 미끄러뜨리는 쪽보다
/// 덜 미끄러뜨리는 쪽이 낫다.
@Test
func anEnPassantShapeWithAFriendlyPawnOnThePassedSquareIsNotACapture() throws {
    // 손으로 짠 국면: e5 와 d5 에 **둘 다 백 폰**. d6 은 비었고 d5 는 그대로 남는다.
    var before = ChessPosition.empty
    before[ChessSquare("e5")!] = ChessPiece(.white, .pawn)
    before[ChessSquare("d5")!] = ChessPiece(.white, .pawn)
    var after = ChessPosition.empty
    after[ChessSquare("d6")!] = ChessPiece(.white, .pawn)
    after[ChessSquare("d5")!] = ChessPiece(.white, .pawn)

    let flight = try #require(ChessMoveFlight.make(move: try flMove("e5d6"), before: before, after: after,
                                                   matchID: flMatch, ply: 9, generation: 1, startedAt: flT0),
                              "★ nil 로 떨어졌다 — 수는 그려야 한다(잡힘만 빠져야 한다)")
    #expect(flight.knockout == nil, "내 편 폰을 잡힌 말로 셌다 — 그 말이 둘로 보인다")
    #expect(flight.sliders.count == 1, "폰 하나만 미끄러진다")
    // 프레임까지 간다 — 모델만 맞고 프레임이 따로 세면 무용지물이다.
    let frame = try #require(flight.frame(now: flT0.addingTimeInterval(flight.knockoutDelay + 0.05)))
    #expect(frame.leaving == nil, "빠지는 말이 생겼다")
    #expect(frame.hidden == [ChessSquare("d6")!], "도착 칸만 가린다 — d5 가 끼면 내 편 폰이 사라진다")

    // ★ 기준선이 갈린다: 같은 칸에 **흑** 폰이면 잡힌 말이 생긴다(위 단언이 "언제나 nil" 로 굳은 게 아니다).
    var enemy = before
    enemy[ChessSquare("d5")!] = ChessPiece(.black, .pawn)
    var enemyAfter = ChessPosition.empty
    enemyAfter[ChessSquare("d6")!] = ChessPiece(.white, .pawn)
    let captured = try #require(ChessMoveFlight.make(move: try flMove("e5d6"), before: enemy, after: enemyAfter,
                                                     matchID: flMatch, ply: 9, generation: 1, startedAt: flT0))
    let knockout = try #require(captured.knockout, "적 폰인데 잡힘이 안 생겼다")
    #expect(knockout.square == ChessSquare("d5"))
    #expect(knockout.piece == ChessPiece(.black, .pawn))
}

// MARK: - ⑨ 승격

/// 없으면: 폰이 **퀸으로 변한 채** 미끄러진다. lichess·chess.com 은 폰으로 미끄러뜨리고 도착해서 바꾼다 —
/// 변신이 중간에 일어나면 어느 폰이 올라갔는지 눈으로 못 쫓는다.
@Test
func aPromotingPawnSlidesAsAPawnNotAsAQueen() throws {
    let plain = try flMade(flPromotionFEN, "b7b8q")
    #expect(plain.flight.sliders[0].piece.kind == .pawn, "퀸으로 미끄러졌다")
    #expect(plain.flight.sliders[0].piece == ChessPiece(.white, .pawn))
    #expect(plain.flight.knockout == nil)
    #expect(plain.move.promotion == .queen, "수에는 승격이 담겨 있다 — 미끄러지는 말만 폰이다")
    // 멈춘 배치(after)에서는 이미 퀸이다 — 뷰가 도착 칸을 가리는 근거.
    #expect(plain.after[ChessSquare("b8")!] == ChessPiece(.white, .queen))

    // 승격 잡기: 미끄러지는 말은 폰이고 knockout 은 잡힌 룩이다.
    let capture = try flMade(flPromotionCaptureFEN, "a7b8q")
    #expect(capture.flight.sliders[0].piece.kind == .pawn)
    let knockout = try #require(capture.flight.knockout)
    #expect(knockout.square == ChessSquare("b8"))
    #expect(knockout.piece == ChessPiece(.black, .rook))
    #expect(knockout.pushFile == 1)
    #expect(knockout.pushRank == 1)
    // ★ 폰이 옆 줄로 갔지만 이건 **앙파상이 아니다** — 도착 칸을 먼저 보는 순서가 지켜졌다는 증거.
    #expect(knockout.square != ChessSquare("b7"), "앙파상 갈래로 떨어졌다")
}

// MARK: - ⑩ 밀리는 방향

/// 없으면: 잡힌 말이 잡은 말과 **반대쪽**으로 튀거나 늘 같은 쪽으로 밀려 궤적이 안 이어진다.
/// 부호와 크기를 숫자로 박는 까닭: 축을 바꿔 적어도(file↔rank) 크기만 보는 단언은 초록이다.
@Test
func theKnockoutPushContinuesTheDirectionTheCapturerCameFrom() throws {
    // ① 오른쪽 위로 잡는 폰: d4 → e5
    let upRight = try #require(try flMade(flPawnCaptureFEN, "d4e5").flight.knockout)
    #expect(upRight.pushFile == 1)
    #expect(upRight.pushRank == 1)

    // ② 왼쪽 아래로 잡는 폰: e5 → d4 (흑)
    let downLeft = try #require(try flMade(flPawnCaptureDownFEN, "e5d4").flight.knockout)
    #expect(downLeft.pushFile == -1)
    #expect(downLeft.pushRank == -1)
    #expect(downLeft.piece == ChessPiece(.white, .pawn))

    // ③ 나이트: f3 → e5 는 (Δfile -1, Δrank +2) → 최대 성분이 ±1 로 정규화된다.
    let knight = try #require(try flMade(flKnightCaptureFEN, "f3e5").flight.knockout)
    #expect(knight.pushFile == -0.5)
    #expect(knight.pushRank == 1.0)
    #expect(max(abs(knight.pushFile), abs(knight.pushRank)) == 1, "최대 성분이 ±1 이 아니다")

    // ④ 판을 가로질러 잡는 룩: a4 → h4 는 (Δfile +7, Δrank 0).
    let rook = try #require(try flMade(flRookCaptureFEN, "a4h4").flight.knockout)
    #expect(rook.pushFile == 1.0)
    #expect(rook.pushRank == 0.0)
    #expect(rook.piece == ChessPiece(.black, .rook))

    // ★ 기준선이 갈린다: 네 경우의 (pushFile, pushRank) 가 서로 다 다르다 — 상수로 굳으면 빨개진다.
    let all = [(upRight.pushFile, upRight.pushRank), (downLeft.pushFile, downLeft.pushRank),
               (knight.pushFile, knight.pushRank), (rook.pushFile, rook.pushRank)]
    #expect(Set(all.map { "\($0.0)/\($0.1)" }).count == 4)
}

// MARK: - ⑪ 먼저 밀려나고 나중에 흐려진다

/// 없으면: 잡힌 말의 비율·오프셋과 불투명도가 같이 깎여 **그 자리에서 그냥 사라진 것과 구분되지 않는다** —
/// 사용자가 고쳐 달라고 한 바로 그 증상이다.
///
/// ★ 오프셋·비율은 `easeOut(k)` 로 깎고 **불투명도만 날 진행도 k** 로 깎는다. 둘을 같은 `easeOut` 으로
///   깎았던 첫 판은 불투명도가 1 인 창이 `k ≤ 1 − ∛0.65 = 0.13376`(0.22초 중 **29.4ms = 60Hz 1.77프레임**)
///   뿐이었고, 밀림이 절반 갔을 때 벌써 **0.192** · 80% 에서 **0.012** 였다 — 거의 그 자리에서 사라진다.
///   날 진행도로 깎으면 그 창이 `k ≤ 0.35`(**77ms = 4.62프레임**)이고, 그 끝에서 오프셋은 이미
///   **전체 밀림의 72.5%**(0.399칸)다. 아래 숫자는 전부 그 식의 실측값이다.
@Test
func theCapturedPieceIsPushedBeforeItStartsFading() throws {
    let flight = try flMade(flPawnCaptureFEN, "d4e5").flight
    #expect(flight.knockoutDelay == 0.45 * 0.175)
    #expect(flight.knockoutDuration == 0.22)

    /// 밀림 진행도 `k` 의 프레임.
    func leaving(at k: Double) throws -> ChessFlightFrame.Leaving {
        let now = flT0.addingTimeInterval(flight.knockoutDelay + k * flight.knockoutDuration)
        let frame = try #require(flight.frame(now: now), "k=\(k) 프레임이 nil")
        #expect(abs(flight.knockoutProgress(now: now) - k) <= 1e-9, "k 계산이 어긋났다")
        return try #require(frame.leaving, "k=\(k) leaving 이 nil")
    }

    // 밀림이 시작된 직후: 불투명도는 **정확히 1**, 오프셋은 **0 이 아니다**.
    let early = try leaving(at: 0.10)
    #expect(early.opacity == 1.0, "밀림 직후에 벌써 흐려졌다 — 이게 뒤집히면 '그 자리에서 사라진다'로 되돌아간다")
    #expect(early.fileOffset != 0)
    #expect(early.rankOffset != 0)
    #expect(abs(early.fileOffset - 0.55 * 0.271) <= 1e-9, "0.55칸 × easeOut(0.1)=0.271")
    #expect(early.scale < 1, "이미 줄어드는 중이다(불투명도만 멈춰 있다)")
    // ★ 기준선이 갈린다: 흐려짐을 밀림과 **같이** 깎았다면(opacity = 1 - easeOut(k)) 여기서 0.729 다.
    #expect(early.opacity != 1 - ChessMoveFlight.easeOut(0.10))

    // 사양이 "진행도 0.2 에서 1.0" 이라고 적은 지점 — 날 진행도 식에서는 **정확히 1** 이다.
    let twenty = try leaving(at: 0.2)
    #expect(twenty.opacity == 1.0, "실제 = \(twenty.opacity)")
    #expect(abs(twenty.fileOffset - 0.55 * ChessMoveFlight.easeOut(0.2)) <= 1e-9,
            "불투명한 채로 이미 0.55 × 0.488 = 0.268칸 나가 있다")

    // 실측 경계: **0.35 까지 1 · 그 뒤부터 1 아래**(= knockoutFadeStart 그대로. 이징이 끼면 0.13376 이 된다).
    #expect(try leaving(at: 0.35).opacity == 1.0)
    #expect(try leaving(at: 0.3501).opacity < 1.0)
    // ★ 그 경계에서 밀림은 벌써 72.5% 다 — "먼저 밀려나고" 가 숫자로 증명되는 자리.
    #expect(abs(try leaving(at: 0.35).fileOffset - 0.55 * 0.725375) <= 1e-9)

    // 그 뒤로는 서서히 깎인다(기울기가 1/0.65 로 일정하다 — 이징이 끼면 0.192·0.012 로 곤두박질친다).
    #expect(abs(try leaving(at: 0.5).opacity - 0.769230769230769) <= 1e-9)
    #expect(abs(try leaving(at: 0.8).opacity - 0.307692307692308) <= 1e-9)
    // ★ 기준선이 갈린다: 이징이 낀 식이면 이 둘이 0.192 · 0.012 다. 그 값과 **다르다**는 것을 못 박는다.
    #expect(try leaving(at: 0.5).opacity > 1 - ChessMoveFlight.easeOut(0.5))
    #expect(try leaving(at: 0.8).opacity > 1 - ChessMoveFlight.easeOut(0.8))

    // 지연이 지나기 전에는 **아무것도 안 움직인다**(잡는 말이 절반쯤 와야 충격이 보인다).
    let beforeDelay = try #require(flight.frame(now: flT0.addingTimeInterval(flight.knockoutDelay / 2)))
    let beforePush = try #require(beforeDelay.leaving)
    #expect(beforePush.fileOffset == 0)
    #expect(beforePush.rankOffset == 0)
    #expect(beforePush.scale == 1)
    #expect(beforePush.opacity == 1)
    #expect(beforePush.square == ChessSquare("e5"), "잡힌 말은 제 칸에 서 있다")

    // 끝: 0.55칸 밀리고 0.55 로 줄고 투명해진다.
    let done = try leaving(at: 1)
    #expect(abs(done.fileOffset - 0.55) <= 1e-9)
    #expect(abs(done.scale - 0.55) <= 1e-9)
    #expect(done.opacity == 0)
    #expect(ChessMoveFlight.knockoutPushCells == 0.55)
    #expect(ChessMoveFlight.knockoutMinScale == 0.55)
    #expect(ChessMoveFlight.knockoutFadeStart == 0.35)
}

// MARK: - ⑫ 잡는 수는 미끄러짐보다 오래 간다

/// 없으면: 잡는 말이 도착하는 순간 값이 거둬져 밀림이 **중간에 잘린다** — 잡힌 말이 반쯤 밀린 채 사라진다.
/// 반대로 잡기 없는 수까지 0.22s 를 더 돌면 `TimelineView` 가 쓸데없이 깨어 있다(배터리 계약).
@Test
func aCapturingMoveOutlivesItsSlideAndAQuietMoveDoesNot() throws {
    let capture = try flMade(flPawnCaptureFEN, "d4e5").flight
    #expect(capture.duration > capture.slideDuration)
    #expect(capture.duration == 0.45 * 0.175 + 0.22, "0.07875 + 0.22 = 0.29875")

    let longCapture = try flMade(flRookCaptureFEN, "a4h4").flight
    #expect(longCapture.duration > longCapture.slideDuration, "뚜껑(0.30)에 닿은 수도 밀림이 더 길다")
    #expect(longCapture.duration == 0.45 * 0.30 + 0.22, "0.135 + 0.22 = 0.355")

    for (fen, uci) in [(flPawnPushFEN, "e2e4"), (flCastlingFEN, "e1g1"), (flPromotionFEN, "b7b8q")] {
        let flight = try flMade(fen, uci).flight
        #expect(flight.knockout == nil)
        #expect(flight.knockoutDelay == 0)
        #expect(flight.knockoutDuration == 0)
        #expect(flight.duration == flight.slideDuration, "\(uci) 잡지도 않은 수가 더 돈다")
        let quietFrame = try #require(flight.frame(now: flT0))
        #expect(quietFrame.leaving == nil)
    }
}

// MARK: - ⑬ frame(now:) == nil 과 isFinished(now:)

/// 없으면: 둘이 어긋나 "끝났는데 안 거둬서 60fps 로 계속 도는"(배터리) 또는 "거뒀는데 마지막 프레임이
/// 안 그려진"(마지막 몇 픽셀 순간이동) 상태가 된다. 한쪽만 고쳐지는 사고를 막는 자리다.
@Test
func theNilFrameAndTheFinishedFlagAgreeEverywhere() throws {
    for (fen, uci) in [(flPawnCaptureFEN, "d4e5"), (flPawnPushFEN, "e2e4"), (flRookCaptureFEN, "a4h4")] {
        let flight = try flMade(fen, uci).flight
        let span = flight.duration + 0.5
        var sawFrame = false, sawNil = false
        for step in 0...2000 {   // 촘촘히: 약 0.4ms 간격
            let now = flT0.addingTimeInterval(span * Double(step) / 2000)
            let isNil = flight.frame(now: now) == nil
            #expect(isNil == flight.isFinished(now: now), "\(uci) step \(step) 에서 갈렸다")
            if isNil { sawNil = true } else { sawFrame = true }
        }
        // ★ 기준선: 두 갈래를 다 봤다(언제나 nil 또는 언제나 non-nil 이면 위 단언은 공허하다).
        #expect(sawFrame && sawNil, "\(uci) 한쪽 갈래만 봤다")
        // 경계가 열려 있다는 것(elapsed == duration 은 아직 안 끝났다)을 따로 못 박는다.
        #expect(!flight.isFinished(now: flT0.addingTimeInterval(flight.duration)))
        #expect(flight.isFinished(now: flT0.addingTimeInterval(flight.duration.nextUp)))
    }
}

// MARK: - ⑭ 못 만드는 경우 nil

/// 없으면: 말이 없는 칸에서 유령이 미끄러지거나, 수와 안 맞는 국면에서 엉뚱한 칸으로 미끄러진다.
/// nil 은 안전한 폴백이다 — 판은 지금(0.3.43)처럼 바로 바뀐다.
@Test
func theFlightIsNilWhenTheMoveAndThePositionDoNotLineUp() throws {
    let standard = try #require(ChessPosition(fen: flPawnPushFEN))

    // 출발 칸이 빈 수.
    let fromEmpty = try flMove("a3a4")
    #expect(ChessMoveFlight.make(move: fromEmpty, before: standard, after: standard,
                                 matchID: flMatch, ply: 1, generation: 1, startedAt: flT0) == nil)

    // `after` 의 도착 칸이 빈 국면(수를 안 적용한 국면을 after 로 줬다).
    let push = try flMove("e2e4")
    #expect(standard[ChessSquare("e4")!] == nil, "전제: e4 는 비어 있다")
    #expect(ChessMoveFlight.make(move: push, before: standard, after: standard,
                                 matchID: flMatch, ply: 1, generation: 1, startedAt: flT0) == nil)

    // 제자리 수. 거리 0 이라 밀림 방향이 0/0(NaN)이 되고 자기 칸의 말을 '잡힌 말'로 센다.
    let still = try flMove("e2e2")
    #expect(ChessMoveFlight.make(move: still, before: standard, after: standard,
                                 matchID: flMatch, ply: 1, generation: 1, startedAt: flT0) == nil)

    // ★ 기준선: 같은 국면·같은 수에 **맞는** after 를 주면 만들어진다(위 nil 들이 "언제나 nil" 이 아니다).
    let after = try #require(ChessRules.apply(push, to: standard))
    #expect(ChessMoveFlight.make(move: push, before: standard, after: after,
                                 matchID: flMatch, ply: 1, generation: 1, startedAt: flT0) != nil)
}

// MARK: - ⑮ 음수·먼 미래 시각

/// 없으면: 창을 깨우거나 시계가 뒤로 간 순간 `t` 가 음수·100 이 되어 말이 판 밖으로 날아간다.
@Test
func timesBeforeTheStartAndFarAfterTheEndStayInsideZeroToOne() throws {
    let flight = try flMade(flPawnCaptureFEN, "d4e5").flight

    let past = flT0.addingTimeInterval(-10)
    #expect(flight.slideProgress(now: past) == 0)
    #expect(flight.knockoutProgress(now: past) == 0)
    #expect(!flight.isFinished(now: past), "시작 전은 '끝났다'가 아니다")
    let before = try #require(flight.frame(now: past), "시작 전 프레임이 nil")
    #expect(before.moving[0].t == 0)
    let beforeLeaving = try #require(before.leaving)
    #expect(beforeLeaving.fileOffset == 0 && beforeLeaving.rankOffset == 0)
    #expect(beforeLeaving.scale == 1 && beforeLeaving.opacity == 1)

    let future = flT0.addingTimeInterval(100)
    #expect(flight.slideProgress(now: future) == 1)
    #expect(flight.knockoutProgress(now: future) == 1)
    #expect(flight.isFinished(now: future))
    #expect(flight.frame(now: future) == nil)

    // 진행도는 어느 시각에서도 0…1 이다(위 둘 말고 중간도 훑는다).
    for seconds in stride(from: -5.0, through: 5.0, by: 0.05) {
        let now = flT0.addingTimeInterval(seconds)
        let slide = flight.slideProgress(now: now), knock = flight.knockoutProgress(now: now)
        #expect((0...1).contains(slide), "slide \(slide) @ \(seconds)")
        #expect((0...1).contains(knock), "knock \(knock) @ \(seconds)")
    }
}

// MARK: - ⑯ Equatable · Sendable

/// 없으면: 뷰가 `ChessFlightFrame` 을 비교할 수 없어 같은 프레임에도 다시 그리거나(저더),
/// 값이 `@Observable` 저장소와 `TimelineView`(다른 격리) 사이를 못 건넌다.
@Test
func theFlightAndItsFrameAreUsableValues() throws {
    let one = try flMade(flPawnCaptureFEN, "d4e5").flight
    let two = try flMade(flPawnCaptureFEN, "d4e5").flight
    #expect(one == two, "같은 입력인데 값이 다르다")
    #expect(flRequireSendable(one) == one)

    let frameOne = try #require(one.frame(now: flT0.addingTimeInterval(0.05)))
    let frameTwo = try #require(two.frame(now: flT0.addingTimeInterval(0.05)))
    #expect(frameOne == frameTwo)
    #expect(flRequireSendable(frameOne) == frameOne)

    // ★ 기준선이 갈려야 한다: 다른 입력은 다른 값이다(== 가 늘 true 인 게 아니다).
    let otherGeneration = try flMade(flPawnCaptureFEN, "d4e5", generation: 4).flight
    #expect(one != otherGeneration)
    #expect(try flMade(flPawnCaptureFEN, "d4e5", ply: 8).flight != one)
    #expect(try flMade(flPawnCaptureFEN, "d4e5", startedAt: flT0.addingTimeInterval(1)).flight != one)
    let frameLater = try #require(one.frame(now: flT0.addingTimeInterval(0.06)))
    #expect(frameLater != frameOne)
}
