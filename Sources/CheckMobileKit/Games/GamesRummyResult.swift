import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 큐브 결과(설계서 §6, 맥 `RummyResultView` 견본 — 배치는 세로용으로 다시 짰다. [최종 판]만 가로다 — §10.1).
// 아래 `GamesRummyResultPlan` 은 `#if os(iOS)` 밖이다 — 폰 뷰는 맥 스위트가 못 보므로 등수 순서 · 순수익 · [한 판 더] 재료를 값으로 잰다.
// 끝난 판의 분배는 **서버 값(`payout`)만** 쓴다. 안내 글자(`GamesRummyText.splitLines`)로 계산하지 않는다.

package enum GamesRummyResultPlan {
    /// [한 판 더] 재료 — 같은 판돈 · 같은 공개 여부 · 끝까지 남은 사람.
    package struct Rematch: Equatable, Sendable {
        package let stake: Int?
        package let isPublic: Bool
        package let invitees: [UUID]
    }

    /// 판에 앉았던 자리(끝까지 한 자리 · 기권) — 서버 등수 순.
    package static func rows(_ match: RummyMatchState) -> [RummyMatchSeat] {
        (match.seats ?? []).filter { $0.state == .done || $0.state == .forfeit || $0.finalRank != nil }
            .sorted { ($0.finalRank ?? 99, $0.seatNo ?? 9) < ($1.finalRank ?? 99, $1.seatNo ?? 9) }
    }

    package static func winnerName(_ match: RummyMatchState) -> String? {
        rows(match).first { $0.isWinner == true }?.displayName
    }

    package static func winnerIsMe(_ match: RummyMatchState) -> Bool {
        rows(match).first { $0.isWinner == true }.map { $0.seatNo != nil && $0.seatNo == match.mySeatNo } ?? false
    }

    /// 루비 순수익 = 받은 몫 − 판돈.
    package static func net(_ seat: RummyMatchSeat, stake: Int?) -> Int {
        (seat.payout ?? 0) - (stake ?? 0)
    }

    package static func mine(_ match: RummyMatchState) -> RummyMatchSeat? {
        guard let number = match.mySeatNo else { return nil }
        return match.seats?.first { $0.seatNo == number }
    }

    package static func rematch(_ match: RummyMatchState) -> Rematch {
        Rematch(stake: match.stake, isPublic: match.isPublic ?? false, invitees: match.rematchInvitees)
    }

    /// [한 판 더]를 누를 수 있는가. 잔액은 안 본다 — 로비 값은 정산 전 값이라 이긴 사람을 막을 수 있다(모자라면 서버가 말한다).
    package static func canPlayAgain(isWorking: Bool, blockedBy other: GamesBusyGame?) -> Bool {
        !isWorking && other == nil
    }
}

#if os(iOS)

/// 아잉 큐브 결과. [나가기] = `dismissResult` · [한 판 더] = 같은 판돈·공개 여부로 새 탁자 + 지난 판 사람들 부르기.
/// [최종 판]은 이 화면 안에서 갈아 끼운다 — 자식 화면을 push 하면 `onDisappear` 가 돌아 결과가 접힌다(`rummyScreenDidDisappear`). 펼친 동안만 가로라 값은 스토어가 쥔다(`isRummyFinalBoardShown`).
struct GamesRummyResultView: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue
    var onReaction: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    private var rummy: RummyStore { store.rummy }
    private var showsBoard: Bool { store.isRummyFinalBoardShown }

    var body: some View {
        Group {
            if let match = rummy.match {
                if showsBoard {
                    GamesRummyFinalBoard(match: match, onRanks: { store.setRummyFinalBoardShown(false) },
                                         onLobby: { rummy.dismissResult() })
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: MobileTheme.space2) {
                                headline(match)
                                ForEach(GamesRummyResultPlan.rows(match)) { seat in
                                    GamesRummyResultRow(seat: seat, stake: match.stake, isMe: seat.seatNo == match.mySeatNo)
                                        .anchorPreference(key: GamesRummySeatAnchorKey.self, value: .bounds) { anchor in
                                            seat.seatNo.map { [$0: anchor] } ?? [:]
                                        }
                                }
                            }
                            .padding(.horizontal, MobileTheme.sideMargin)
                            .padding(.vertical, MobileTheme.space2)
                        }
                        actions(match)
                    }
                }
            }
        }
        .onAppear(perform: applyDemo)
        // [최종 판]은 가로 전체를 쓴다. 등수 화면은 그대로다.
        .toolbar(showsBoard && TabBarPolicy.hidesTabBar(on: .rummyMatch) ? .hidden : .automatic, for: .tabBar)
        .toolbar(showsBoard ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(showsBoard)
    }

    // MARK: 머리 카드 — 내 등수 · 내 루비

    private func headline(_ match: RummyMatchState) -> some View {
        let mine = GamesRummyResultPlan.mine(match)
        let net = mine.map { GamesRummyResultPlan.net($0, stake: match.stake) }
        let title = Text(mine.map { GamesRummyText.myResult(rank: $0.finalRank, forfeited: $0.state == .forfeit) } ?? GamesRummyText.resultTitle)
            .font(MobileTheme.title(.title3))
            .foregroundStyle(MobileTheme.label)
        let reason = Text(GamesRummyText.endReason(match.endReason, winner: GamesRummyResultPlan.winnerName(match),
                                                   winnerIsMe: GamesRummyResultPlan.winnerIsMe(match)))
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
        return InsetGroup {
            Group {
                // 큰 글자에서는 한 줄에 다 못 싣는다(사유가 글자 하나 폭으로 접힌다) — 사유와 루비를 아래로 내린다.
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MobileTheme.space1) {
                        HStack(spacing: MobileTheme.space2) {
                            title
                            Spacer(minLength: 4)
                            reactionButton
                        }
                        reason
                        if let net { GamesRummyNetLabel(net: net, iconSize: 20, font: MobileTheme.number(.title3, weight: .bold)) }
                    }
                } else {
                    HStack(spacing: MobileTheme.space2) {
                        Image(systemName: mine?.isWinner == true ? "trophy.fill" : "flag.checkered")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(mine?.isWinner == true ? MobileTheme.gold : MobileTheme.label2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            title
                            reason
                        }
                        Spacer(minLength: 4)
                        if let net { GamesRummyNetLabel(net: net, iconSize: 20, font: MobileTheme.number(.title3, weight: .bold)) }
                        reactionButton
                    }
                }
            }
            .padding(.leading, MobileTheme.cardPadding)
            .padding(.trailing, onReaction == nil ? MobileTheme.cardPadding : 6)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var reactionButton: some View {
        if let onReaction {
            Button(action: onReaction) {
                Image(systemName: GamesRummyText.reactionSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(GamesRummyText.react)
        }
    }

    // MARK: 동작

    private func actions(_ match: RummyMatchState) -> some View {
        let block = store.rummyEntryBlock
        return VStack(spacing: MobileTheme.space1) {
            if let hint = block.flatMap({ ChessPhoneText.entryBlockHint(playing: $0.text, blocked: .rummy) }) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.pending)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AingButton(GamesRummyText.playAgain, systemImage: "arrow.clockwise", size: .lg, fillsWidth: true) {
                playAgain(match)
            }
            .disabled(!GamesRummyResultPlan.canPlayAgain(isWorking: rummy.isWorking, blockedBy: block))
            HStack(spacing: MobileTheme.space1) {
                AingButton(GamesRummyText.finalBoard,
                           systemImage: typeSize.isAccessibilitySize ? nil : "square.grid.3x2",
                           kind: .gray, size: .md, fillsWidth: true) {
                    store.setRummyFinalBoardShown(true)
                }
                AingButton(GamesRummyText.toLobby, kind: .gray, size: .md, fillsWidth: true) {
                    rummy.dismissResult()
                }
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.vertical, MobileTheme.space2)
        // 버튼 줄이 글자를 끝까지 따라가면 등수 줄 칸을 다 먹고 [최종 판]이 말줄임이 된다(가장 큰 글자 실화면) — 여기까지만 키운다.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// 판돈 · 공개 여부를 맞춘 뒤 결과를 접고 새 탁자를 연다(순서가 맥과 같다 — 접으면 스토어가 방을 만들 수 있는 상태가 된다).
    private func playAgain(_ match: RummyMatchState) {
        let plan = GamesRummyResultPlan.rematch(match)
        if let stake = plan.stake { rummy.selectedStake = stake }
        rummy.createPublic = plan.isPublic
        rummy.dismissResult()
        inviteQueue.createAndInvite(plan.invitees, store: rummy)
    }

    /// 데모 스크린샷 전용: `games/rummy/result/board` 면 최종 판을 펴고 연다. Release 에서는 한 줄도 돌지 않는다.
    private func applyDemo() {
        #if DEBUG
        if store.demoRummyRoute?.scene == .resultBoard { store.setRummyFinalBoardShown(true) }
        #endif
    }
}

// MARK: - 순수익 글자

private struct GamesRummyNetLabel: View {
    let net: Int
    let iconSize: CGFloat
    let font: Font

    var body: some View {
        HStack(spacing: 4) {
            RubyIcon(size: iconSize)
            Text(GamesRummyText.net(net))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(net > 0 ? MobileTheme.working : (net < 0 ? MobileTheme.danger : MobileTheme.label))
        }
        .fixedSize()
    }
}

// MARK: - 등수 줄

private struct GamesRummyResultRow: View {
    let seat: RummyMatchSeat
    let stake: Int?
    let isMe: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    private static let tile = CGSize(width: 26, height: 36)

    private var net: Int { GamesRummyResultPlan.net(seat, stake: stake) }
    private var forfeited: Bool { seat.state == .forfeit }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        let rack = seat.finalRack ?? []
        VStack(alignment: .leading, spacing: MobileTheme.space1) {
            if typeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    rank
                    avatar
                    Spacer(minLength: 4)
                    netLabel
                }
                identity
            } else {
                HStack(spacing: 10) {
                    rank.frame(minWidth: 38, alignment: .leading)
                    avatar
                    identity
                    Spacer(minLength: 4)
                    netLabel
                }
            }
            if !rack.isEmpty {
                Text(GamesRummyText.remainingCount(rack.count))
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tile.width, maximum: Self.tile.width), spacing: 3)],
                          alignment: .leading, spacing: 3) {
                    ForEach(Array(rack.enumerated()), id: \.offset) { _, face in
                        GamesRummyTile(face: face, size: Self.tile)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(seat.isWinner == true ? MobileTheme.gold.opacity(0.12) : MobileTheme.surface))
        .overlay(shape.stroke(isMe ? MobileTheme.accent : Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesRummyText.resultRowAccessibility(rank: seat.finalRank, name: seat.displayName ?? "?", isMe: isMe,
                                                                  forfeited: forfeited, score: seat.finalScore, net: net, rackCount: rack.count))
    }

    private var rank: some View {
        Text(GamesRummyText.rank(seat.finalRank))
            .font(.title3.weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(seat.finalRank == 1 ? MobileTheme.gold : MobileTheme.label)
            .lineLimit(1)
            .fixedSize()
    }

    private var avatar: some View {
        PersonAvatar(name: seat.displayName ?? "?", colorSeed: seat.userId.uuidString.lowercased(),
                     url: seat.avatarUrl.flatMap(URL.init(string:)), userID: seat.userId.uuidString.lowercased(),
                     size: 36, characterHint: seat.character)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(seat.displayName ?? "?")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if seat.isWinner == true {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(MobileTheme.gold)
                }
                if isMe { chip(GamesRummyText.me, tint: MobileTheme.accent) }
                if forfeited { chip(GamesRummyText.forfeitTag, tint: MobileTheme.danger) }
            }
            Text(GamesRummyText.score(seat.finalScore))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
                .lineLimit(1)
        }
    }

    private var netLabel: some View {
        GamesRummyNetLabel(net: net, iconSize: 16, font: MobileTheme.number(.headline, weight: .heavy))
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: - 최종 판

/// 끝난 판(가로) — 판 화면과 같은 칸을 읽기 전용으로 쓴다(보기 값 · 밀기 · 핀치 · [전체 보기] · 화면 밖 배지가 같다). 손은 판을 밀고 키울 뿐 타일을 집지 않는다.
/// 왼쪽은 판 전부, 오른쪽 열은 판 화면과 같은 폭이다.
private struct GamesRummyFinalBoard: View {
    let match: RummyMatchState
    let onRanks: () -> Void
    let onLobby: () -> Void

    @State private var model = GamesRummyMatchModel()
    /// 앞 사건의 끈 거리. `@GestureState` 라 제스처가 **취소돼도** 비워진다 — `@State` 는 `onEnded` 가 안 오면(시트 · 앱 내림) 낡은 값이 남아 다음 밀기 첫 사건에 판이 반대로 튀었다.
    @GestureState private var lastPan: CGSize = .zero
    /// 핀치 수명 표시. 취소된 `MagnifyGesture` 는 `onEnded` 를 안 부른다 — 꺼지면 모델의 핀치를 닫는다(안 닫으면 다음 핀치가 끝날 때까지 밀기가 죽는다).
    @GestureState private var pinching = false

    var body: some View {
        HStack(spacing: 0) {
            board
            VStack(spacing: GamesRummyMatchLayout.actionGap) {
                GamesRummyZoomButton(model: model)
                Spacer(minLength: 0)
                AingButton(GamesRummyText.ranks, kind: .gray, size: .md, fillsWidth: true, action: onRanks)
                AingButton(GamesRummyText.toLobby, kind: .gray, size: .md, fillsWidth: true, action: onLobby)
            }
            .padding(GamesRummyMatchLayout.columnPadding)
            .frame(width: GamesRummyMatchLayout.rightColumnWidth)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }

    private var board: some View {
        let scene = GamesRummyBoardScene.make(match: match, editor: nil, isMyTurn: false, otherDraft: nil)
        return GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                GamesRummyTablePane(model: model, scene: scene, size: size, editable: false)
                if scene.melds.isEmpty {
                    Text(GamesRummyText.emptyBoard)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(pan)
                    .simultaneousGesture(
                        MagnifyGesture()
                            .updating($pinching) { _, state, _ in state = true }
                            .onChanged { value in
                                model.pinch(magnification: value.magnification,
                                            tableAnchor: CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height))
                            }
                            .onEnded { _ in model.pinchEnded(touching: false) }
                    )
                    .accessibilityHidden(true)
                GamesRummyTableControls(model: model, scene: scene, size: size)
            }
            .frame(width: size.width, height: size.height)
            .onAppear { model.tableSizeChanged(size) }
            .onChange(of: size) { _, new in model.tableSizeChanged(new) }
            .onChange(of: pinching) { _, now in if !now { model.pinchEnded(touching: false) } }
        }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($lastPan) { value, last, _ in
                model.readOnlyPan(by: CGSize(width: value.translation.width - last.width,
                                             height: value.translation.height - last.height))
                last = value.translation
            }
    }
}
#endif
