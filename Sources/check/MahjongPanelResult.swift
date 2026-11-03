import SwiftUI
import CheckCore

// MARK: - 아잉 마작 국 결과 · 판 결과 (SPEC §5.5)
//
//  · 국 결과 카드(펠트 위 600×400): 화료자 손(40×54) · 화료패 · 역과 판 · 도라·적도라·뒷도라(+ 뒷도라 표시패, 리치 화료만) ·
//    점수 이동(자리마다 ±) · 더블론이면 화료자마다 한 장씩 넘김(쉬는 시간 7초 + 4초 × (화료자 − 1) 안에서
//    `(쉬는 시간 − 1.5초) / 화료자 수` 간격 — D48) · 유국이면 텐파이 손·유국 이유 · "다음 국까지 N초"(`next_hand_ms`, 잎 뷰).
//    **판·부·점수는 늘 서버 값**이다. 확인 단추 없음(서버 시각으로 넘어간다, D30).
//  · 판 결과(큐브 `RummyPanelResult` 틀): 등수(`final_rank`) · 최종 점수 · 루비 순수익(`payout − stake`) · 탈퇴 칩 ·
//    [한 판 더] · [로비로]. 오카·우마는 보이지 않는다. 연습판은 루비 줄 없이 [다시 하기].

/// 더블론 넘김(순수 — D48).
enum MahjongResultPaging {
    /// 서버 쉬는 시간(초) = 7 + 4 × (화료자 − 1).
    static func restSeconds(winners: Int) -> Double { 7 + 4 * Double(max(1, winners) - 1) }

    /// 지금 보일 화료자 번호.
    static func index(winners: Int, nextHand: Date?, now: Date) -> Int {
        guard winners > 1, let nextHand else { return 0 }
        let rest = restSeconds(winners: winners)
        let interval = (rest - 1.5) / Double(winners)
        let elapsed = now.timeIntervalSince(nextHand.addingTimeInterval(-rest))
        return max(0, min(winners - 1, Int(elapsed / interval)))
    }
}

struct MahjongHandResultCard: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let result: MahjongHandResult

    private func name(_ seatNo: Int?) -> String {
        guard let seatNo, let seat = payload.seats?.first(where: { $0.seatNo == seatNo }) else { return "?" }
        if seat.deleted == true { return MahjongText.deletedChip }
        return seatNo == payload.mySeat ? "나" : (seat.user?.displayName ?? "?")
    }

    var body: some View {
        let nextHand = MahjongClockMath.local(payload.match?.nextHandMs, store: store)
        MahjongTick(store: store, interval: 0.5) { now in
            VStack(alignment: .leading, spacing: 10) {
                if let wins = result.wins, !wins.isEmpty {
                    let index = MahjongResultPaging.index(winners: wins.count, nextHand: nextHand, now: now)
                    winContent(wins[index], index: index, count: wins.count)
                } else {
                    drawContent
                }
                Spacer(minLength: 0)
                deltas
                if let nextHand {
                    Text(MahjongText.nextHand(max(0, Int(nextHand.timeIntervalSince(now).rounded(.up)))))
                        .font(.caption.monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(CheckTheme.panelElevated.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(CheckTheme.pending.opacity(0.6), lineWidth: 2))
        }
    }

    @ViewBuilder
    private func winContent(_ win: MahjongWinResult, index: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(win.fromSeat == nil ? "\(name(win.seat)) 쯔모" : "\(name(win.seat)) 론 ← \(name(win.fromSeat))")
                .font(.title3.weight(.heavy))
            if count > 1 { MahjongChip(text: "\(index + 1)/\(count)", tint: CheckTheme.accent) }
            Spacer()
            Text(scoreLine(win)).font(.headline.monospacedDigit()).foregroundStyle(CheckTheme.pending)
        }
        handRow(win)
        let yaku = win.yaku ?? []
        // 두 열(LazyVGrid 는 ImageRenderer 가 못 그릴 수 있어 HStack 두 줄로).
        let rows = stride(from: 0, to: yaku.count, by: 2).map { Array(yaku[$0..<min($0 + 2, yaku.count)]) }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 0) {
                    ForEach(Array(pair.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Text(MahjongNoticeText.yakuName(item.id)).font(.callout.weight(.semibold))
                            Text((win.yakuman ?? 0) > 0 ? "역만" : "\(item.han)판").font(.callout.monospacedDigit())
                                .foregroundStyle(CheckTheme.secondaryText)
                        }
                        .frame(width: 270, alignment: .leading)
                    }
                }
            }
        }
        HStack(spacing: 10) {
            if (win.dora ?? 0) > 0 { Text("도라 \(win.dora ?? 0)") }
            if (win.aka ?? 0) > 0 { Text("적도라 \(win.aka ?? 0)") }
            if let ura = win.uraIndicators {
                Text("뒷도라 \(win.ura ?? 0)")
                MahjongTileStrip(tiles: ura.enumerated().map { MahjongStripTile(face: MahjongTileFace($1), size: .smallMeld,
                                                                                    origin: CGPoint(x: CGFloat($0) * 26, y: 0)) },
                                 size: CGSize(width: CGFloat(max(1, ura.count)) * 26, height: 32), cornerLabels: false,
                                 accessibilityText: "뒷도라 표시패 \(ura.count)장")
            }
            if let pao = win.pao, let seat = pao.seat {
                Text("책임 지불 \(name(seat))")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(CheckTheme.secondaryText)
    }

    private func scoreLine(_ win: MahjongWinResult) -> String {
        var parts: [String] = []
        if let yakuman = win.yakuman, yakuman > 0 {
            parts.append(yakuman > 1 ? "\(yakuman)배 역만" : "역만")
        } else {
            parts.append("\(win.han ?? 0)판 \(win.fu ?? 0)부")
            if let limit = MahjongText.limitName(win.limit) { parts.append(limit) }
        }
        parts.append("\((win.total ?? 0).formatted())점")
        return parts.joined(separator: " · ")
    }

    /// 화료자 손(40×54) + 화료패(띄움) + 부로.
    private func handRow(_ win: MahjongWinResult) -> some View {
        let size = MahjongTileSize.result
        var tiles: [MahjongStripTile] = []
        var x: CGFloat = 0
        var hand = (win.hand ?? []).sorted()
        if let winTile = win.winTile, let at = hand.firstIndex(of: winTile) { hand.remove(at: at) }
        for tile in hand {
            tiles.append(MahjongStripTile(face: MahjongTileFace(tile), size: size, origin: CGPoint(x: x, y: 0)))
            x += size.width
        }
        if let winTile = win.winTile {
            x += 10
            tiles.append(MahjongStripTile(face: MahjongTileFace(winTile), size: size, state: .highlighted, origin: CGPoint(x: x, y: 0)))
            x += size.width
        }
        for meld in win.melds ?? [] {
            x += 10
            for tile in meld.tiles {
                tiles.append(MahjongStripTile(face: MahjongTileFace(tile), size: .meld,
                                              origin: CGPoint(x: x, y: size.height - MahjongTileSize.meld.height)))
                x += MahjongTileSize.meld.width
            }
        }
        return MahjongTileStrip(tiles: tiles, size: CGSize(width: 564, height: size.height),
                                accessibilityText: "화료 손 \(win.hand?.count ?? 0)장")
    }

    @ViewBuilder
    private var drawContent: some View {
        Text(MahjongText.handEnd(result.kind == "abortive" ? result.reason : (result.nagashi?.isEmpty == false ? "nagashi"
                                                                                                    : (result.reason ?? "exhaustive"))))
            .font(.title3.weight(.heavy))
        let tenpai = result.tenpai ?? []
        if tenpai.isEmpty {
            Text("모두 노텐").font(.callout).foregroundStyle(CheckTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(tenpai.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Text("\(name(row.seat)) 텐파이").font(.caption.weight(.semibold)).frame(width: 110, alignment: .leading)
                        let hand = (row.hand ?? []).sorted()
                        MahjongTileStrip(tiles: hand.enumerated().map { MahjongStripTile(face: MahjongTileFace($1), size: .smallMeld,
                                                                                         origin: CGPoint(x: CGFloat($0) * 24, y: 0)) },
                                         size: CGSize(width: 24 * 14, height: 32), cornerLabels: false,
                                         accessibilityText: "\(name(row.seat)) 텐파이 손")
                    }
                }
            }
        }
    }

    /// 점수 이동(자리마다 ±).
    private var deltas: some View {
        let deltas = result.deltas ?? []
        let after = result.scoresAfter ?? []
        return HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { seatNo in
                let delta = seatNo < deltas.count ? deltas[seatNo] : 0
                VStack(spacing: 2) {
                    Text(name(seatNo)).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(MahjongText.delta(delta))
                        .font(.callout.weight(.heavy).monospacedDigit())
                        .foregroundStyle(delta > 0 ? CheckTheme.working : (delta < 0 ? CheckTheme.danger : CheckTheme.secondaryText))
                    Text(MahjongText.score(seatNo < after.count ? after[seatNo] : nil))
                        .font(.caption2.monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.fieldFill))
            }
        }
    }
}

// MARK: - 판 결과

struct MahjongMatchResultCard: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let onToLobby: () -> Void
    let onRematch: () -> Void

    var body: some View {
        let seats = (payload.seats ?? []).sorted { ($0.finalRank ?? 9, $0.seatNo) < ($1.finalRank ?? 9, $1.seatNo) }
        let stake = payload.match?.stake ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("판 결과").font(.title2.weight(.heavy))
                Spacer()
                Text(MahjongText.matchEnd(payload.match?.endReason)).font(.caption).foregroundStyle(CheckTheme.secondaryText)
            }
            ForEach(seats, id: \.seatNo) { seat in
                HStack(spacing: 12) {
                    Text(MahjongText.rank(seat.finalRank)).font(.title3.weight(.heavy).monospacedDigit()).frame(width: 46)
                    CheckAvatarView(name: seat.user?.displayName ?? "?", userID: seat.user?.userId,
                                    avatarURL: seat.user?.avatarUrl.flatMap(URL.init(string:)), size: 36,
                                    characterHint: seat.user?.character)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(seat.seatNo == payload.mySeat ? "나" : (seat.user?.displayName ?? "?"))
                                .font(.callout.weight(.semibold))
                            if seat.deleted == true { MahjongChip(text: MahjongText.deletedChip, tint: CheckTheme.danger) }
                        }
                        Text("\((seat.finalScore ?? seat.score ?? 0).formatted())점").font(.caption.monospacedDigit())
                            .foregroundStyle(CheckTheme.secondaryText)
                    }
                    Spacer()
                    if !store.isPractice, payload.match?.isVoid != true {
                        let net = (seat.payout ?? 0) - stake
                        HStack(spacing: 3) {
                            RubyIcon(size: 13)
                            Text(MahjongText.net(net)).font(.headline.monospacedDigit())
                                .foregroundStyle(net > 0 ? CheckTheme.working : (net < 0 ? CheckTheme.danger : CheckTheme.secondaryText))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(seat.seatNo == payload.mySeat ? CheckTheme.accent.opacity(0.16) : CheckTheme.fieldFill))
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if store.isPractice {
                    MahjongCapsuleButton(title: MahjongText.practiceAgain, tint: CheckTheme.working) { store.restartPractice() }
                    MahjongCapsuleButton(title: MahjongText.practiceEnd, tint: CheckTheme.secondaryText, filled: false) {
                        store.endPractice()
                    }
                } else {
                    MahjongCapsuleButton(title: MahjongText.rematch, tint: CheckTheme.accent, action: onRematch)
                    MahjongCapsuleButton(title: MahjongText.toLobby, tint: CheckTheme.secondaryText, filled: false, action: onToLobby)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18).fill(CheckTheme.panelElevated.opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CheckTheme.accent.opacity(0.6), lineWidth: 2))
    }
}
