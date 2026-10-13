import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 체스 말 그림(`ChessPieceArt`)을 **맥·폰이 한 벌로** 쓴다 — 그 한 벌이 맥에서 그대로 그려지는지 잰다.
//
// 이 그림은 0.3.44~0.3.48 동안 맥 전용 자리(`Sources/check/ChessPanel.swift`)에 있었고, 폰 체스 판을 만들면서
// `Sources/CheckCore/ChessPieceArt.swift` 로 **올렸다**(접근 수준 `package`). 복사하지 않은 까닭: 두 벌이면
// 한쪽만 고쳐지고 갈라진 것을 아무도 모른다.
//
// 그래서 이 파일은 둘을 잰다:
//  ① **두 벌이 아니다** — `Sources/` 전체에 `ChessPieceArt` 선언이 **하나**뿐이고 그 자리는 코어다.
//  ② **맥이 그대로 그린다** — 여섯 말 × 두 색이 전부 **칸 가운데를 덮는다**(맥 렌더 검증과 같은 감지기:
//     칸 중앙 50% 상자의 극단 픽셀). 가운데가 비면 "말이 안 그려졌다" 와 구분이 되지 않는다.

@Suite("체스 말 그림 — 맥·폰 공용(CheckCore)")
struct ChessPieceArtSharedTests {

    // MARK: - ① 두 벌이 아니다

    /// 없으면: 폰 작업이 `ChessPieceArt` 를 복사해 두 벌로 둬도 초록이다. 두 벌이면 한쪽만 고쳐지고,
    /// 갈라진 걸 아무도 모른다(맥과 폰의 비숍이 다른 모양이 되는 길).
    @Test("Sources 전체에 ChessPieceArt 선언이 하나뿐이고 그 자리는 CheckCore 다")
    func thePieceArtIsDeclaredExactlyOnceAndLivesInTheSharedCore() throws {
        var declarations: [String] = []
        let sources = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources", isDirectory: true)
        let walker = try #require(FileManager.default.enumerator(atPath: sources.path), "Sources 를 못 훑었다")
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(relative), encoding: .utf8)
            // 주석을 걷어낸 뒤에 본다 — 안 그러면 설명에 적힌 타입 이름이 '선언' 으로 세어진다.
            for line in Self.stripComments(text).split(separator: "\n", omittingEmptySubsequences: false)
            where line.contains("enum ChessPieceArt") || line.contains("struct ChessPieceArt") {
                declarations.append(relative)
            }
        }
        print("[공용] ChessPieceArt 선언 자리: \(declarations)")
        #expect(declarations == ["CheckCore/ChessPieceArt.swift"],
                "선언이 \(declarations) 에 있다 — 한 벌이어야 하고 그 자리는 Sources/CheckCore/ChessPieceArt.swift 다")
    }

    /// 코어로 올릴 수 있었던 **근거**를 못으로 박는다: AppKit·UIKit 의존이 0건이다. 하나라도 들어오면
    /// 폰 빌드가 깨지는데, 폰 뷰는 맥 스위트가 못 보므로 이 줄이 그 변화를 먼저 잡는다.
    @Test("공용 그림 파일에 AppKit·UIKit 의존이 없다")
    func theSharedPieceArtHasNoPlatformDependency() throws {
        let text = try String(contentsOf: CheckCoreSourceLayout.coreDirectory
            .appendingPathComponent("ChessPieceArt.swift"), encoding: .utf8)
        let code = Self.stripComments(text)
        for forbidden in ["import AppKit", "import UIKit", "NSColor", "UIColor", "#if os("] {
            #expect(!code.contains(forbidden), "공용 그림 파일에 `\(forbidden)` 이 들어왔다 — 더 이상 한 벌이 아니다")
        }
    }

    static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - ② 맥이 그대로 그린다

    /// 여섯 말 × 두 색. 백은 2열, 흑은 7열에 종류 순서대로 놓는다(b~g 파일).
    static let kinds: [ChessPieceKind] = [.pawn, .knight, .bishop, .rook, .queen, .king]

    static func sampleBoard() throws -> (ChessPosition, [(ChessPiece, ChessSquare)]) {
        var position = ChessPosition.empty
        var placed: [(ChessPiece, ChessSquare)] = []
        for (offset, kind) in kinds.enumerated() {
            for (color, rank) in [(ChessColor.white, 1), (ChessColor.black, 6)] {
                let square = try #require(ChessSquare(file: offset + 1, rank: rank))
                let piece = ChessPiece(color, kind)
                position[square] = piece
                placed.append((piece, square))
            }
        }
        return (position, placed)
    }

    /// 맥 판 하나만 구운 비트맵(scale 2) — V0344·V0346 과 같은 방식이다.
    @MainActor
    static func bitmap(_ position: ChessPosition) throws -> NSBitmapImageRep {
        let view = ChessBoardView(position: position,
                                  geometry: ChessBoardGeometry(side: ChessWindowLayout.boardSide),
                                  showsCoordinates: false)
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = 2
        let image = try #require(renderer.nsImage, "판을 못 구웠다")
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff))
    }

    /// **말 잉크** — 아주 밝거나(최대 ≥ 235) 아주 어두운(최소 ≤ 55) 픽셀. 칸·덮개는 전부 중간 톤이라
    /// 이 셈이 곧 "그 자리에 말이 있는가" 다(`ChessBoardView` 머리말의 규칙).
    static func pieceInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
        guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
        let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
        let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
        let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
        guard x0 <= x1, y0 <= y1 else { return 0 }
        var hits = 0
        for y in y0...y1 {
            for x in x0...x1 {
                let o = y * bpr + x * spp
                let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
                if max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55 { hits += 1 }
            }
        }
        return hits
    }

    /// 없으면: 코어로 옮기면서 경로가 깨져도(빈 Path · 상자 밖으로 나간 좌표) 맥이 컴파일만 되면 초록이다.
    @MainActor
    @Test("여섯 말 × 두 색이 전부 칸 가운데를 덮는다 — 빈 칸은 0px 다")
    func allSixPiecesStillCoverTheCenterOfTheirSquareOnTheMac() throws {
        let g = ChessBoardGeometry(side: ChessWindowLayout.boardSide)
        let (position, placed) = try Self.sampleBoard()
        let bitmap = try Self.bitmap(position)

        var report: [String] = []
        for (piece, square) in placed {
            let box = g.rect(of: square)
            let probe = box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
            let ink = Self.pieceInk(bitmap, rect: probe)
            report.append("\(piece.color) \(piece.kind) @\(square.notation): \(ink)px")
            #expect(ink > 0,
                    "\(piece.color) \(piece.kind) 가 \(square.notation) 칸 가운데를 안 덮는다(\(ink)px) — 작은 화면에서 '말이 안 그려졌다' 와 구분되지 않는다")
        }
        for line in report { print("[말 잉크] \(line)") }

        // ★ 기준선이 갈린다: **빈 칸**은 가운데가 0px 다. 안 갈리면 위 열두 줄은 "판 전체가 극단 색" 으로도 초록이다.
        for notation in ["a1", "h8", "d4", "e5"] {
            let square = try #require(ChessSquare(notation))
            let box = g.rect(of: square)
            let ink = Self.pieceInk(bitmap, rect: box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25))
            #expect(ink == 0, "빈 칸 \(notation) 가운데에 \(ink)px 가 있다 — 감지기가 칸 색을 말로 센다")
        }
    }

    /// 그림 좌표가 **상자 안**에 있다(그려지는 상자는 칸의 86% · 가운데 정렬). 상자를 넘으면 옆 칸을 침범하고,
    /// 상자가 가운데에서 벗어나면 끌어 놓은 말·밀려나는 말의 비율 계산이 전부 어긋난다.
    @Test("path 는 box(in:) 안에 들어가고 box 는 칸 가운데에 있다", arguments: ChessPieceKind.allCases)
    func everyPiecePathStaysInsideItsCenteredBox(kind: ChessPieceKind) throws {
        let cell = CGRect(x: 100, y: 200, width: 76, height: 76)
        let box = ChessPieceArt.box(in: cell)
        #expect(abs(box.midX - cell.midX) < 1e-9 && abs(box.midY - cell.midY) < 1e-9,
                "말 상자 \(box) 가 칸 \(cell) 가운데에 없다")
        #expect(abs(box.width - 76 * ChessPieceArt.fillFraction) < 1e-9)

        let path = ChessPieceArt.path(for: kind, in: cell)
        let bounds = path.boundingRect
        #expect(!bounds.isEmpty, "\(kind) 의 경로가 비었다 — 아무것도 안 그려진다")
        #expect(bounds.minX >= box.minX - 1e-6 && bounds.maxX <= box.maxX + 1e-6
                && bounds.minY >= box.minY - 1e-6 && bounds.maxY <= box.maxY + 1e-6,
                "\(kind) 의 경로 \(bounds) 가 상자 \(box) 밖으로 나갔다")
        // 그림이 **칸 가운데에 모여 있다**(위 렌더 단언의 기하 쪽 짝 — 한쪽 구석에만 그려진 말을 잡는다).
        //
        // ★ `path.contains(칸 가운데)` 로는 재지 않는다: 폰은 머리 원과 몸통 다각형이 정확히 그 높이(0.50)에서
        //   맞닿고 두 조각의 감는 방향이 반대라 **그 한 점이 nonZero 에서 상쇄된다**(실측 — 0.3.44 부터 있던
        //   맥 그림 그대로다. 상쇄되는 조각은 상자의 13% × 2.5% 라 45pt 칸에서 1픽셀 남짓이고 렌더 잉크로는
        //   안 보인다). 점 하나의 경계 판정은 모양을 재는 자리가 아니다 — 가운데를 덮는가는 위의 렌더 시험이
        //   칸 중앙 50% 상자의 잉크로 잰다.
        #expect(abs(bounds.midX - cell.midX) < cell.width * 0.12
                && abs(bounds.midY - cell.midY) < cell.height * 0.12,
                "\(kind) 의 그림 가운데 \(CGPoint(x: bounds.midX, y: bounds.midY)) 가 칸 가운데 \(CGPoint(x: cell.midX, y: cell.midY)) 에서 너무 멀다")
        #expect(bounds.width > cell.width * 0.4 && bounds.height > cell.height * 0.5,
                "\(kind) 의 그림 \(bounds.size) 이 칸 \(cell.size) 에 비해 너무 작다")
    }
}
