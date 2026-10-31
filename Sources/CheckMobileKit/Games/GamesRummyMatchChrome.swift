#if os(iOS)
import CheckCore
import SwiftUI

// 폰 아잉 큐브 판 화면의 판·받침대 바깥 줄들 — 머리 줄 · 상대 줄 · 상태 줄 · 동작 줄 · 안내(맥 `RummyPanelMatch.swift` 의 위 띠·자리 카드·버튼을 세로로 옮겼다).
// 초 단위 값은 **잎 뷰**(`GamesRummyTurnRing`·`GamesRummySeconds`)만 읽는다 — 화면이 매초 다시 그려지지 않게. 데모 시계가 고정이라 날짜는 `rummy.clock()` 으로 묻는다.

/// 자리 카드 위치(자리 번호 → 카드 사각형). 다음 갈래(반응 말풍선)가 `.overlayPreferenceValue` 로 읽어 보낸 사람 자리에 띄운다. 내 자리는 받침대 칸이다.
struct GamesRummySeatAnchorKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - 머리 줄

struct GamesRummyMatchHeader: View {
    let match: RummyMatchState
    let onExit: () -> Void
    let onReaction: (() -> Void)?
    let onRules: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(GamesRummyText.leave)
            .accessibilityHint(GamesRummyText.leaveHint)
            HStack(spacing: 5) {
                RubyIcon(size: 17, scalesWithText: false)
                Text(GamesRummyText.potLine(stake: match.stake, seats: match.seatCount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                GamesRummyTileBack(size: CGSize(width: 11, height: 15))
                Text(GamesRummyText.pool(match.poolCount))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            if let onReaction {
                Button(action: onReaction) {
                    Image(systemName: "face.smiling")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(GamesRummyText.react)
            }
            Button(action: onRules) {
                Image(systemName: "questionmark.circle")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(GamesRummyText.rulesButton)
        }
        .foregroundStyle(MobileTheme.label)
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

// MARK: - 상대 줄

/// 상대를 내 다음 차례부터 가로로. **남의 패는 장수만** 보인다.
struct GamesRummyOpponentRow: View {
    let rummy: RummyStore
    let match: RummyMatchState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GamesRummySeats.opponents(match)) { seat in
                GamesRummySeatCard(rummy: rummy, match: match, seat: seat)
                    .anchorPreference(key: GamesRummySeatAnchorKey.self, value: .bounds) { anchor in
                        seat.seatNo.map { [$0: anchor] } ?? [:]
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .allowsHitTesting(false)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

private struct GamesRummySeatCard: View {
    let rummy: RummyStore
    let match: RummyMatchState
    let seat: RummyMatchSeat

    private var isTurn: Bool { GamesRummySeats.isTurn(seat, in: match) }
    private var tags: [GamesRummySeatTag] { GamesRummySeats.tags(seat) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 6) {
            ZStack {
                if isTurn {
                    GamesRummyTurnRing(rummy: rummy, total: GamesRummySeats.turnTotal(match), diameter: 38)
                }
                PersonAvatar(name: seat.displayName ?? "?", colorSeed: seat.userId.uuidString.lowercased(),
                             url: seat.avatarUrl.flatMap(URL.init(string:)), userID: seat.userId.uuidString.lowercased(),
                             size: 30, scalesWithText: false, characterHint: seat.character)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(seat.displayName ?? "?")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 3) {
                    GamesRummyTileBack(size: CGSize(width: 8, height: 11))
                    Text(GamesRummyText.rackCount(seat.rackCount))
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // 셋째 줄: 차례면 남은 초, 아니면 표시(폭 320 에서 카드 글자 칸이 43pt 뿐이라 한 줄에 다 못 싣는다).
                if isTurn {
                    GamesRummySeconds(rummy: rummy)
                        .font(.system(size: 10, weight: .heavy))
                } else if let tag = tags.first {
                    Text(tag.text)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tagColor(tag))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(MobileTheme.label)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(isTurn ? MobileTheme.accentTint : MobileTheme.surface))
        .overlay(shape.stroke(isTurn ? MobileTheme.accent : MobileTheme.separator, lineWidth: isTurn ? 1.5 : 0.8))
        .opacity(GamesRummySeats.isGone(seat) ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesRummyText.seatSummary(name: seat.displayName ?? "?", count: seat.rackCount, isTurn: isTurn,
                                                       tags: tags.map(\.text)))
    }

    private func tagColor(_ tag: GamesRummySeatTag) -> Color {
        switch tag {
        case .forfeit, .disconnected, .timeouts: return MobileTheme.danger
        case .beforeInitial: return MobileTheme.pending
        }
    }
}

/// 차례 시간 링 — **잎 뷰**만 시계를 읽는다.
private struct GamesRummyTurnRing: View {
    let rummy: RummyStore
    let total: TimeInterval
    let diameter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = rummy.turnRemaining(at: rummy.clock()) ?? total
            let fraction = min(1, max(0, left / max(total, 1)))
            ZStack {
                Circle().stroke(MobileTheme.fill, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(GamesRummySeconds.tint(left) ?? MobileTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: diameter - 3, height: diameter - 3)
        }
        .accessibilityHidden(true)
    }
}

/// 남은 초 글자(자리 카드). 10초 이하 앰버 · 5초 이하 빨강.
private struct GamesRummySeconds: View {
    let rummy: RummyStore

    static func tint(_ left: TimeInterval) -> Color? {
        left <= 5 ? MobileTheme.danger : (left <= 10 ? MobileTheme.pending : nil)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let left = rummy.turnRemaining(at: rummy.clock()) {
                Text(GamesRummyText.seconds(max(0, Int(left.rounded(.up)))))
                    .monospacedDigit()
                    .foregroundStyle(Self.tint(left) ?? MobileTheme.label2)
                    .lineLimit(1)
            }
        }
    }
}

/// [완료] 안 남은 초.
private struct GamesRummySubmitSeconds: View {
    let rummy: RummyStore
    /// [완료]가 꺼져 있어도 남은 초는 또렷해야 한다(흐린 회색 위에서는 바탕을 진하게).
    let enabled: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let left = rummy.turnRemaining(at: rummy.clock()) {
                Text(GamesRummyText.seconds(max(0, Int(left.rounded(.up)))))
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 20)
                    .background(Capsule().fill(GamesRummySeconds.tint(left) ?? Color.black.opacity(enabled ? 0.28 : 0.5)))
            }
        }
    }
}

// MARK: - 상태 줄

struct GamesRummyStatusRow: View {
    let line: GamesRummyStatusLine
    /// 첫 등록 전 받침대 합(판 · 받침대). nil 이면 안 보인다.
    let plan: (table: Int, rack: Int)?

    private var tint: Color {
        switch line.tone {
        case .notice: return MobileTheme.pending
        case .ready: return MobileTheme.working
        case .plain: return MobileTheme.label
        case .quiet: return MobileTheme.label2
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(line.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let plan {
                let reached = plan.table + plan.rack >= 30
                Text(GamesRummyText.plan(table: plan.table, rack: plan.rack))
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(reached ? MobileTheme.working : MobileTheme.label2)
            }
        }
        .padding(.horizontal, 10)
        .allowsHitTesting(false)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

// MARK: - 동작 줄

/// [완료(남은 초)] 가장 크게 · [뽑기|넘기기] · [되돌리기] · [777|789]. 큰 글자면 두 줄로 나눈다(`GamesRummyMatchLayout.actionRowCount`).
struct GamesRummyActionRow: View {
    let rummy: RummyStore
    let match: RummyMatchState
    let editor: RummyTurnEditor?
    let isMyTurn: Bool
    let width: CGFloat
    let textScale: CGFloat
    let onSort: (RummyRackSort) -> Void

    var body: some View {
        let rows = GamesRummyMatchLayout.actionRowCount(textScale: textScale)
        let height = GamesRummyMatchLayout.actionButtonHeight(textScale: textScale)
        let gap = GamesRummyMatchLayout.actionGap
        Group {
            if rows == 1 {
                let widths = GamesRummyMatchLayout.actionWidths(total: width)
                HStack(spacing: gap) {
                    submit.frame(width: widths.submit)
                    draw.frame(width: widths.draw)
                    undo.frame(width: widths.undo)
                    sort.frame(width: widths.sort)
                }
                .frame(height: height)
            } else {
                VStack(spacing: gap) {
                    submit.frame(height: height)
                    HStack(spacing: gap) {
                        draw
                        undo
                        sort
                    }
                    .frame(height: height)
                }
            }
        }
        .padding(.horizontal, gap)
        // 칸 높이는 64 에서 멈춘다. 글자가 그 위로 더 커지면 버튼을 넘치고 [777]이 말줄임이 된다(가장 큰 글자 · 폭 320 실화면) — 여기까지만 키운다.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var canEdit: Bool { isMyTurn && !rummy.isWorking }
    private var poolEmpty: Bool { (match.poolCount ?? 0) == 0 }

    private var submit: some View {
        let enabled = canEdit && editor?.canSubmit == true
        // `.disabled` 를 안 쓴다 — 버튼 전체를 흐리게 해서 남은 초까지 안 읽힌다(꺼진 동안에도 시간은 간다). 꺼진 모습은 아래 색이 맡고, 누르기는 두 겹으로 막는다.
        return Button {
            if enabled { rummy.submitTurn() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.footnote.weight(.black))
                Text(GamesRummyText.submit)
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isMyTurn { GamesRummySubmitSeconds(rummy: rummy, enabled: enabled) }
            }
            .foregroundStyle(enabled ? MobileTheme.onAccentFill : MobileTheme.label3Text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(enabled ? MobileTheme.accentFill : MobileTheme.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
    }

    private var draw: some View {
        secondary(title: poolEmpty ? GamesRummyText.pass : GamesRummyText.draw,
                  icon: poolEmpty ? "forward.fill" : "plus.rectangle.on.rectangle",
                  enabled: canEdit) { rummy.drawTile() }
    }

    private var undo: some View {
        secondary(title: GamesRummyText.undo, icon: "arrow.uturn.backward",
                  enabled: canEdit && (editor?.isChanged == true || editor?.isLayoutChanged == true)) { rummy.resetTurn() }
    }

    private func secondary(title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.footnote.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(enabled ? MobileTheme.label : MobileTheme.label3Text)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MobileTheme.separator, lineWidth: 0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var sort: some View {
        let selected = rummy.rackSortMode
        let enabled = editor != nil
        return HStack(spacing: 2) {
            segment(.number, title: GamesRummyText.sortNumber, name: GamesRummyText.sortNumberName, on: selected == .number, enabled: enabled)
            Rectangle().fill(MobileTheme.separator).frame(width: 0.8).padding(.vertical, 8)
            segment(.color, title: GamesRummyText.sortColor, name: GamesRummyText.sortColorName, on: selected == .color, enabled: enabled)
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MobileTheme.separator, lineWidth: 0.8))
        .opacity(enabled ? 1 : 0.45)
    }

    private func segment(_ mode: RummyRackSort, title: String, name: String, on: Bool, enabled: Bool) -> some View {
        Button {
            onSort(mode)
        } label: {
            Text(title)
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(on ? MobileTheme.onAccentFill : MobileTheme.label)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? MobileTheme.accentFill : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(name)
    }
}

// MARK: - 판 위 안내

/// 판 가운데 '내 차례' 배지.
struct GamesRummyTurnBadge: View {
    var body: some View {
        Label(GamesRummyText.myTurnBadge, systemImage: "sparkles")
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(MobileTheme.onAccentFill)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Capsule().fill(MobileTheme.accentFill))
            .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            .allowsHitTesting(false)
    }
}

/// 판 아래쪽 한 줄 — 직전 사건 · 남의 차례(작업 중이면 '놓는 중').
struct GamesRummyTableStrip: View {
    let match: RummyMatchState
    let isMyTurn: Bool
    let hasOtherDraft: Bool

    var body: some View {
        let turn = GamesRummySeats.turnSeat(match)
        let last = match.lastEvent.flatMap { event in
            GamesRummyText.lastEvent(event, name: match.seats?.first { $0.seatNo == event.seatNo }?.displayName)
        }
        HStack(alignment: .bottom, spacing: 6) {
            if let last {
                Text(last)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
            }
            Spacer(minLength: 4)
            if !isMyTurn, let name = turn?.displayName {
                Label(hasOtherDraft ? GamesRummyText.placing(name) : GamesRummyText.turnOf(name),
                      systemImage: hasOtherDraft ? "hand.draw.fill" : "hourglass")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(MobileTheme.accentFill))
            }
        }
        .padding(8)
        .allowsHitTesting(false)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

/// 다른 기기 판 안내 — 읽기만 하는 동안. **입력은 막지 않는다**(맥과 같다 — 여기서 타일을 옮기면 이 폰에서 이어 한다).
struct GamesRummyElsewhereCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(GamesRummyText.elsewhereTitle, systemImage: "iphone.and.arrow.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MobileTheme.label)
            Text(GamesRummyText.elsewhereDetail)
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MobileTheme.separator, lineWidth: 0.8))
        .padding(.horizontal, 10)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
#endif
