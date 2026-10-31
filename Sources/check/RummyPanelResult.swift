import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 결과 (2판 설계서 §3 ⑩)
//
// 등수 줄(서버 등수 순 · 루비 순수익 · 남은 랙)에 둘을 더했다.
//   · [한 판 더] — 같은 판돈 · 같은 공개 여부로 새 탁자를 열고, **끝까지 남은 사람**(기권하지 않은 나 말고 모두)을 부른다
//     (`RummyInviteQueue.createAndInvite`). 기권한 사람은 나간 사람이라 다시 부르지 않는다.
//   · [최종 판] — 등수 줄 자리에 끝난 판의 묶음을 그 배치(`table_layout`) 그대로 보여 준다. 다시 누르면 등수로 돌아간다.

enum RummyResultText {
    static let title = "결과"
    static let playAgain = "한 판 더"
    static let finalBoard = "최종 판"
    static let ranks = "등수"
    static let emptyBoard = "판에 놓인 묶음이 없어요"
}

struct RummyResultView: View {
    let store: RummyStore
    let scene: RummyScene
    let match: RummyMatchState
    var onPlayAgain: ([UUID]) -> Void = { _ in }
    var startsWithBoard = false

    @State private var showsBoard = false

    /// 판에 앉았던 자리(끝까지 한 자리 · 기권) — 서버 등수 순.
    private var rows: [RummyMatchSeat] {
        (match.seats ?? []).filter { $0.state == .done || $0.state == .forfeit || $0.finalRank != nil }
            .sorted { ($0.finalRank ?? 99, $0.seatNo ?? 9) < ($1.finalRank ?? 99, $1.seatNo ?? 9) }
    }

    private var winnerName: String? {
        rows.first { $0.isWinner == true }?.displayName
    }

    private var boardShown: Bool { showsBoard || startsWithBoard }

    /// [한 판 더] 가 부를 사람 — 나 말고, 기권하지 않은 사람(자리 순).
    static func rematchInvitees(_ match: RummyMatchState) -> [UUID] {
        (match.seats ?? []).filter { $0.seatNo != match.mySeatNo && $0.state != .forfeit }
            .sorted { ($0.seatNo ?? 9) < ($1.seatNo ?? 9) }
            .map(\.userId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RummyWindowLayout.resultRowSpacing) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(CheckTheme.pending)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RummyResultText.title).font(.title3.weight(.bold))
                    Text(RummyText.endReason(match.endReason, winner: winnerName))
                        .font(.callout)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
                Spacer()
                TetrisDuelActionButton(title: boardShown ? RummyResultText.ranks : RummyResultText.finalBoard,
                                       icon: boardShown ? "list.number" : "square.grid.3x2", style: .outline,
                                       height: 38, action: { showsBoard = !boardShown })
                TetrisDuelActionButton(title: RummyText.toLobby, icon: "arrow.left", style: .outline, height: 38,
                                       action: { store.dismissResult() })
                TetrisDuelActionButton(title: RummyResultText.playAgain, icon: "arrow.clockwise", height: 38,
                                       isEnabled: !scene.isWorking, action: playAgain)
            }
            .frame(height: 48)
            if boardShown {
                RummyFinalBoard(sets: match.table ?? [], layout: match.tableLayout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(rows) { seat in
                    RummyResultRow(seat: seat, stake: match.stake ?? 0, isMe: seat.seatNo == match.mySeatNo)
                        .frame(height: RummyWindowLayout.resultRowHeight)
                        .rummyReactionAnchor(seatNo: seat.seatNo)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard(padding: 18)
    }

    /// 같은 판돈·공개 여부로 새 탁자 + 지난 판 사람들 부르기.
    private func playAgain() {
        if let stake = match.stake { store.selectedStake = stake }
        store.createPublic = match.isPublic ?? false
        let invitees = Self.rematchInvitees(match)
        store.dismissResult()
        onPlayAgain(invitees)
    }
}

private struct RummyResultRow: View {
    let seat: RummyMatchSeat
    let stake: Int
    let isMe: Bool

    static let maxTiles = 16

    var body: some View {
        let net = (seat.payout ?? 0) - stake
        let rack = seat.finalRack ?? []
        HStack(spacing: 16) {
            Text(RummyText.rank(seat.finalRank))
                .font(.title2.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(seat.finalRank == 1 ? CheckTheme.pending : CheckTheme.primaryText)
                .frame(width: 64, alignment: .leading)
            CheckAvatarView(name: seat.displayName ?? "?", userID: seat.userId.uuidString.lowercased(),
                            avatarURL: seat.avatarUrl.flatMap(URL.init(string:)), size: 44,
                            characterHint: seat.character)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(seat.displayName ?? "?").font(.callout.weight(.bold)).lineLimit(1)
                    if seat.isWinner == true { Image(systemName: "crown.fill").foregroundStyle(CheckTheme.pending) }
                    if isMe { RummyChip(text: "나", tint: CheckTheme.accent) }
                    if seat.state == .forfeit { RummyChip(text: RummyText.forfeit, tint: CheckTheme.danger) }
                }
                Text(RummyText.score(seat.finalScore))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            .frame(width: 190, alignment: .leading)
            HStack(spacing: 5) {
                RubyIcon(size: 16)
                Text(RummyText.net(net))
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(net > 0 ? CheckTheme.working : (net < 0 ? CheckTheme.danger : CheckTheme.primaryText))
            }
            .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(RummyText.remainingTiles).font(.caption2).foregroundStyle(CheckTheme.secondaryText)
                HStack(spacing: 2) {
                    ForEach(Array(rack.prefix(Self.maxTiles).enumerated()), id: \.offset) { _, face in
                        RummyTileView(face: face, size: .table)
                    }
                    if rack.count > Self.maxTiles {
                        Text("+\(rack.count - Self.maxTiles)").font(.caption.weight(.bold))
                    }
                    if rack.isEmpty {
                        Text("—").font(.callout).foregroundStyle(CheckTheme.secondaryText)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(seat.isWinner == true ? CheckTheme.pending.opacity(0.10) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isMe ? CheckTheme.accent.opacity(0.6) : CheckTheme.border, lineWidth: isMe ? 2 : 1))
    }
}

/// 끝난 판 — 확정 묶음을 서버 배치 그대로(1000×640 논리 캔버스를 비율 유지로 맞춘다). 읽기 전용.
struct RummyFinalBoard: View {
    let sets: [[RummyFace]]
    let layout: RummyLayout?

    var body: some View {
        GeometryReader { proxy in
            let table = RummyTableLayout(sets: sets, layout: layout)
            let inset: CGFloat = 16
            let scale = min((proxy.size.width - inset * 2) / CGFloat(RummyTableLayout.canvasWidth),
                            (proxy.size.height - inset * 2) / CGFloat(RummyTableLayout.canvasHeight))
            let canvas = CGSize(width: CGFloat(RummyTableLayout.canvasWidth) * scale,
                                height: CGFloat(RummyTableLayout.canvasHeight) * scale)
            let tileScale = CGFloat(RummyTableLayout.tileWidth) * scale / RummyTileSize.table.size.width
            ZStack(alignment: .topLeading) {
                // 판 화면과 같은 바닥(펠트 그림 · 분홍-보라 테두리).
                RummyTableSurface(cornerRadius: 18)
                if sets.isEmpty {
                    Text(RummyResultText.emptyBoard)
                        .font(.callout)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(width: canvas.width, height: canvas.height)
                }
                ForEach(Array(sets.enumerated()), id: \.offset) { setIndex, faces in
                    ForEach(Array(faces.enumerated()), id: \.offset) { tileIndex, face in
                        if let frame = table.tileFrame(set: setIndex, tile: tileIndex) {
                            RummyTileView(face: face, size: .table)
                                .scaleEffect(tileScale, anchor: .topLeading)
                                .frame(width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale,
                                       alignment: .topLeading)
                                .offset(x: CGFloat(frame.x) * scale, y: CGFloat(frame.y) * scale)
                        }
                    }
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
