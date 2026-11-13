#if os(iOS)
import CheckCore
import SwiftUI

// 아잉 마작 폰 국 결과 · 판 결과(1.0.18 — 맥 `MahjongPanelResult` 와 같은 내용). **판 · 부 · 점수는 늘 서버 값**이다.
// 국 결과는 확인 단추 없이 서버 시각으로 넘어간다(다음 국까지 N초). 더블론이면 화료자마다 넘긴다(맥 D48 — `GamesMahjongResultPaging`).
// 판 결과: 등수 · 최종 점수 · 루비 순수익(payout − stake) · [한 판 더] · [로비로]. 연습판은 루비 줄 없이 [다시 하기].

struct GamesMahjongHandResultCard: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let result: MahjongHandResult

    private func name(_ seatNo: Int?) -> String {
        guard let seatNo, let seat = payload.seats?.first(where: { $0.seatNo == seatNo }) else { return "?" }
        if seat.deleted == true { return GamesMahjongText.deletedChip }
        return seatNo == payload.mySeat ? "나" : (seat.user?.displayName ?? "?")
    }

    var body: some View {
        let nextHand = GamesMahjongMyClock.local(payload.match?.nextHandMs, store: store)
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let now = store.clock()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let wins = result.wins, !wins.isEmpty {
                        let index = GamesMahjongResultPaging.index(winners: wins.count, nextHand: nextHand, now: now)
                        winContent(wins[index], index: index, count: wins.count)
                    } else {
                        drawContent
                    }
                    deltas
                    if let nextHand {
                        Text(GamesMahjongText.nextHand(max(0, Int(nextHand.timeIntervalSince(now).rounded(.up)))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(GamesMahjongPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GamesMahjongPalette.panel))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MobileTheme.pending.opacity(0.6), lineWidth: 2))
        }
    }

    @ViewBuilder
    private func winContent(_ win: MahjongWinResult, index: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(win.fromSeat == nil ? "\(name(win.seat)) 쯔모" : "\(name(win.seat)) 론 ← \(name(win.fromSeat))")
                .font(.headline.weight(.heavy))
            if count > 1 { GamesMahjongChip(text: "\(index + 1)/\(count)", tint: GamesMahjongPalette.accent) }
            Spacer(minLength: 4)
            Text(scoreLine(win)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(MobileTheme.pending)
        }
        handRow(win)
        let yaku = win.yaku ?? []
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 3) {
            ForEach(Array(yaku.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Text(MahjongNoticeText.yakuName(item.id)).font(.footnote.weight(.semibold))
                    Text((win.yakuman ?? 0) > 0 ? "역만" : "\(item.han)판")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(GamesMahjongPalette.secondary)
                }
            }
        }
        HStack(spacing: 8) {
            if (win.dora ?? 0) > 0 { Text("도라 \(win.dora ?? 0)") }
            if (win.aka ?? 0) > 0 { Text("적도라 \(win.aka ?? 0)") }
            if let ura = win.uraIndicators {
                Text("뒷도라 \(win.ura ?? 0)")
                HStack(spacing: 1) {
                    ForEach(Array(ura.enumerated()), id: \.offset) { _, tile in
                        GamesMahjongTileView(face: MahjongTileFace(tile), size: .smallMeld, cornerLabels: false,
                                             display: CGSize(width: 15, height: 20))
                    }
                }
            }
            if let pao = win.pao, let seat = pao.seat { Text("책임 지불 \(name(seat))") }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(GamesMahjongPalette.secondary)
    }

    private func scoreLine(_ win: MahjongWinResult) -> String {
        var parts: [String] = []
        if let yakuman = win.yakuman, yakuman > 0 {
            parts.append(yakuman > 1 ? "\(yakuman)배 역만" : "역만")
        } else {
            parts.append("\(win.han ?? 0)판 \(win.fu ?? 0)부")
            if let limit = GamesMahjongText.limitName(win.limit) { parts.append(limit) }
        }
        parts.append("\((win.total ?? 0).formatted())점")
        return parts.joined(separator: " · ")
    }

    /// 화료자 손 + 화료패(띄움) + 부로.
    private func handRow(_ win: MahjongWinResult) -> some View {
        var hand = (win.hand ?? []).sorted()
        if let winTile = win.winTile, let at = hand.firstIndex(of: winTile) { hand.remove(at: at) }
        let w: CGFloat = 22, h: CGFloat = 30
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(hand.enumerated()), id: \.offset) { _, tile in
                GamesMahjongTileView(face: MahjongTileFace(tile), size: .result, cornerLabels: false, display: CGSize(width: w, height: h))
            }
            if let winTile = win.winTile {
                Spacer().frame(width: 6)
                GamesMahjongTileView(face: MahjongTileFace(winTile), size: .result, state: .highlighted, cornerLabels: false,
                                     display: CGSize(width: w, height: h))
            }
            ForEach(Array((win.melds ?? []).enumerated()), id: \.offset) { _, meld in
                Spacer().frame(width: 6)
                ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, tile in
                    GamesMahjongTileView(face: MahjongTileFace(tile), size: .meld, cornerLabels: false,
                                         display: CGSize(width: w * 0.8, height: h * 0.8))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("화료 손 \(win.hand?.count ?? 0)장"))
    }

    @ViewBuilder
    private var drawContent: some View {
        Text(GamesMahjongText.handEnd(result.kind == "abortive" ? result.reason
                                      : (result.nagashi?.isEmpty == false ? "nagashi" : (result.reason ?? "exhaustive"))))
            .font(.headline.weight(.heavy))
        let tenpai = result.tenpai ?? []
        if tenpai.isEmpty {
            Text("모두 노텐").font(.footnote).foregroundStyle(GamesMahjongPalette.secondary)
        } else {
            ForEach(Array(tenpai.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Text("\(name(row.seat)) 텐파이").font(.caption.weight(.semibold)).frame(width: 90, alignment: .leading)
                    HStack(spacing: 0) {
                        ForEach(Array((row.hand ?? []).sorted().enumerated()), id: \.offset) { _, tile in
                            GamesMahjongTileView(face: MahjongTileFace(tile), size: .smallMeld, cornerLabels: false,
                                                 display: CGSize(width: 15, height: 20))
                        }
                    }
                }
            }
        }
    }

    /// 점수 이동(자리마다 ±).
    private var deltas: some View {
        let deltas = result.deltas ?? []
        let after = result.scoresAfter ?? []
        return HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { seatNo in
                let delta = seatNo < deltas.count ? deltas[seatNo] : 0
                VStack(spacing: 1) {
                    Text(name(seatNo)).font(.caption2.weight(.semibold)).lineLimit(1)
                    Text(GamesMahjongText.delta(delta))
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(delta > 0 ? MobileTheme.working : (delta < 0 ? MobileTheme.danger : GamesMahjongPalette.secondary))
                    Text(GamesMahjongText.score(seatNo < after.count ? after[seatNo] : nil))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(GamesMahjongPalette.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
        }
    }
}

struct GamesMahjongMatchResultCard: View {
    let store: GamesStore
    let payload: MahjongStatePayload

    var body: some View {
        let mahjong = store.mahjong
        let seats = (payload.seats ?? []).sorted { ($0.finalRank ?? 9, $0.seatNo) < ($1.finalRank ?? 9, $1.seatNo) }
        let stake = payload.match?.stake ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("판 결과").font(.title3.weight(.heavy))
                Spacer()
                Text(GamesMahjongText.matchEnd(payload.match?.endReason))
                    .font(.caption)
                    .foregroundStyle(GamesMahjongPalette.secondary)
                    .lineLimit(2)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(seats, id: \.seatNo) { seat in
                        HStack(spacing: 10) {
                            Text(GamesMahjongText.rank(seat.finalRank))
                                .font(.headline.weight(.heavy).monospacedDigit())
                                .frame(width: 40)
                            PersonAvatar(name: seat.user?.displayName ?? "?", colorSeed: seat.user?.userId ?? "seat-\(seat.seatNo)",
                                         url: seat.user?.avatarUrl.flatMap(URL.init(string:)), userID: seat.user?.userId ?? "seat-\(seat.seatNo)",
                                         size: 30, characterHint: seat.user?.character)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(seat.seatNo == payload.mySeat ? "나" : (seat.user?.displayName ?? "?"))
                                        .font(.subheadline.weight(.semibold))
                                    if seat.deleted == true { GamesMahjongChip(text: GamesMahjongText.deletedChip, tint: MobileTheme.danger) }
                                }
                                Text("\((seat.finalScore ?? seat.score ?? 0).formatted())점")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(GamesMahjongPalette.secondary)
                            }
                            Spacer()
                            if !mahjong.isPractice, payload.match?.isVoid != true {
                                let net = (seat.payout ?? 0) - stake
                                HStack(spacing: 3) {
                                    RubyIcon(size: 13)
                                    Text(GamesMahjongText.net(net))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(net > 0 ? MobileTheme.working : (net < 0 ? MobileTheme.danger : GamesMahjongPalette.secondary))
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(seat.seatNo == payload.mySeat ? GamesMahjongPalette.accent.opacity(0.18) : Color.white.opacity(0.06)))
                    }
                }
            }
            HStack(spacing: 10) {
                if mahjong.isPractice {
                    AingButton(GamesMahjongText.practiceEnd, kind: .gray, size: .md, fillsWidth: true) { mahjong.endPractice() }
                    AingButton(GamesMahjongText.practiceAgain, kind: .filled, size: .md, fillsWidth: true) { mahjong.restartPractice() }
                } else {
                    AingButton(GamesMahjongText.toLobby, kind: .gray, size: .md, fillsWidth: true) {
                        store.mahjongDismissedMatchID = payload.match?.id
                    }
                    AingButton(GamesMahjongText.rematch, kind: .filled, size: .md, fillsWidth: true) {
                        store.mahjongDismissedMatchID = payload.match?.id
                        Task { await mahjong.createRoom() }
                    }
                    .disabled(mahjong.isWorking || store.mahjongEntryBlock != nil)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GamesMahjongPalette.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }
}
#endif
