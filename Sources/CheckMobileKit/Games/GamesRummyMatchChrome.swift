#if os(iOS)
import CheckCore
import SwiftUI

// 폰 아잉 큐브 판 화면의 판·받침대 바깥 — 왼쪽 열(뒤로 · 규칙 · 자리 카드) · 오른쪽 열(판돈 · 더미 · 반응 · 동작 버튼) · 상태 줄 · 안내(맥 `RummyPanelMatch.swift` 의 위 띠·자리 카드·버튼을 가로 화면 양옆 열로 옮겼다).
// 칸 자리는 전부 `GamesRummyMatchLayout` 한 값이다. 높이가 약 372pt 뿐이라 큰 글자에서 스크롤 없이 들어가야 한다 — 열 안 글자는 상한을 두고 칸에 맞춰 줄인다.
// 초 단위 값은 **잎 뷰**(`GamesRummyTurnRing`·`GamesRummySeconds`)만 읽는다 — 화면이 매초 다시 그려지지 않게. 데모 시계가 고정이라 날짜는 `rummy.clock()` 으로 묻는다.

extension View {
    /// 칸 사각형 그대로 놓는다(판 화면 좌표).
    func rummyCell(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}

/// 자리 카드 위치(자리 번호 → 카드 사각형). 반응 말풍선이 `.overlayPreferenceValue` 로 읽어 보낸 사람 자리에 띄운다. 내 자리도 왼쪽 열 카드다.
struct GamesRummySeatAnchorKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - 열 위쪽

/// 열 안의 원형 버튼(`GlassCircleButton` 과 같은 유리 원 · 지름만 열 폭에 맞춘다). 터치 자리는 칸 전체다.
private struct GamesRummyColumnButton: View {
    let systemImage: String
    let label: String
    let hint: String?
    let action: () -> Void

    init(systemImage: String, label: String, hint: String? = nil, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.hint = hint
        self.action = action
    }

    var body: some View {
        let diameter = GamesRummyMatchLayout.navButtonDiameter
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MobileTheme.label)
                .frame(width: diameter, height: diameter)
                .background(GlassBackground(shape: Circle()))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
    }
}

/// 왼쪽 열 위 — [나가기] · [규칙]. 판 안 칸이라 시스템 뒤로를 못 쓴다.
struct GamesRummyNavButtons: View {
    let onExit: () -> Void
    let onRules: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            GamesRummyColumnButton(systemImage: "chevron.left", label: GamesRummyText.leave, hint: GamesRummyText.leaveHint, action: onExit)
            GamesRummyColumnButton(systemImage: "book", label: GamesRummyText.rulesButton, action: onRules)
        }
    }
}

/// 오른쪽 열 위 — 판돈 · 더미.
struct GamesRummyMatchInfo: View {
    let match: RummyMatchState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                RubyIcon(size: 14, scalesWithText: false)
                Text(GamesRummyText.potLine(stake: match.stake, seats: match.seatCount))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 5) {
                GamesRummyTileBack(size: CGSize(width: 10, height: 14))
                Text(GamesRummyText.pool(match.poolCount))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(MobileTheme.label)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .allowsHitTesting(false)
    }
}

/// 오른쪽 열 — [반응] · [전체 보기].
struct GamesRummyToolRow: View {
    let model: GamesRummyMatchModel
    let onReaction: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if let onReaction {
                GlassCircleButton(systemImage: GamesRummyText.reactionSymbol, accessibilityLabel: GamesRummyText.react, action: onReaction)
            }
            GamesRummyZoomButton(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 자리 카드

/// 왼쪽 열 — 상대를 내 다음 차례부터 위에서 아래로 · 내 자리는 맨 아래. **남의 패는 장수만** 보인다. 칸 자리는 값이고 인원과 무관하다(말풍선 닻도 카드다).
struct GamesRummySeatColumn: View {
    let rummy: RummyStore
    let match: RummyMatchState
    let layout: GamesRummyMatchLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(GamesRummySeats.opponents(match).prefix(GamesRummyMatchLayout.maxOpponentCards).enumerated()), id: \.element.id) { index, seat in
                card(seat, rect: layout.opponentCard(index))
            }
            if let mine = GamesRummySeats.mine(match) {
                card(mine, rect: layout.mySeatCard)
            }
        }
        .allowsHitTesting(false)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func card(_ seat: RummyMatchSeat, rect: CGRect) -> some View {
        GamesRummySeatCard(rummy: rummy, match: match, seat: seat)
            .anchorPreference(key: GamesRummySeatAnchorKey.self, value: .bounds) { anchor in
                seat.seatNo.map { [$0: anchor] } ?? [:]
            }
            .rummyCell(rect)
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
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                ZStack {
                    if isTurn {
                        GamesRummyTurnRing(rummy: rummy, total: GamesRummySeats.turnTotal(match), diameter: 34)
                    }
                    PersonAvatar(name: seat.displayName ?? "?", colorSeed: seat.userId.uuidString.lowercased(),
                                 url: seat.avatarUrl.flatMap(URL.init(string:)), userID: seat.userId.uuidString.lowercased(),
                                 size: 27, scalesWithText: false, characterHint: seat.character)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        GamesRummyTileBack(size: CGSize(width: 8, height: 11))
                        Text(GamesRummyText.rackCount(seat.rackCount))
                            .font(.caption2.weight(.heavy))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if isTurn {
                        GamesRummySeconds(rummy: rummy)
                            .font(.system(size: 10, weight: .heavy))
                    }
                }
            }
            Text(seat.displayName ?? "?")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let tag = tags.first {
                Text(tag.text)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tagColor(tag))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 3)
        .foregroundStyle(MobileTheme.label)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
    let tail: GamesRummyStatusTail

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
                .layoutPriority(1)
            Spacer(minLength: 0)
            // 자리가 모자라면 직전 사건부터 줄어든다(지금 할 일이 먼저다).
            if let last = tail.lastEvent {
                Text(last)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MobileTheme.label2)
                    .lineLimit(1)
            }
            if let turn = tail.turn {
                Label(turn, systemImage: tail.isPlacing ? "hand.draw.fill" : "hourglass")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MobileTheme.accent)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let warning = line.warning {
                Text(warning)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(MobileTheme.danger)
            }
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

// MARK: - 동작 버튼

/// 오른쪽 열 아래 — [완료(남은 초)] 가장 크게 · [뽑기|넘기기] · [되돌리기] · [777|789]. 칸은 값으로 정해져 있고 글자가 칸에 맞춰 줄어든다(스크롤 없이 들어간다).
struct GamesRummyActionColumn: View {
    let rummy: RummyStore
    let match: RummyMatchState
    let editor: RummyTurnEditor?
    let isMyTurn: Bool
    let layout: GamesRummyMatchLayout
    let onSort: (RummyRackSort) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            submit.rummyCell(layout.submit)
            draw.rummyCell(layout.draw)
            undo.rummyCell(layout.undo)
            sort.rummyCell(layout.sort)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var canEdit: Bool { isMyTurn && !rummy.isWorking }
    private var poolEmpty: Bool { (match.poolCount ?? 0) == 0 }

    private var submit: some View {
        let enabled = canEdit && editor?.canSubmit == true
        // `.disabled` 를 안 쓴다 — 버튼 전체를 흐리게 해서 남은 초까지 안 읽힌다(꺼진 동안에도 시간은 간다). 꺼진 모습은 아래 색이 맡고, 누르기는 두 겹으로 막는다.
        return Button {
            if enabled { rummy.submitTurn() }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.footnote.weight(.black))
                    Text(GamesRummyText.submit)
                        .font(.subheadline.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
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
        // 같은 층의 다른 줄과 같은 상한 — 없으면 큰 글자에서 카드가 판을 다 가린다.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .combine)
    }
}
#endif
