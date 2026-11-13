import SwiftUI
import CheckCore

// MARK: - 아잉 마작 이모티콘 반응 (SPEC §5.3 — 큐브 `RummyReactionOverlay` 를 `compass:` 클로저로 그대로)
//
//  · 보내기: 판 머리 CL 줄의 [반응](얼굴 아이콘) → 아잉이 이모티콘 여섯(큐브 `RummyReactionPicker`) → `store.sendReaction(key)`.
//    루비 판만(연습판은 스토어가 보내지 않는다 — 단추도 없다). 서버 쿨다운 2초(too_fast)와 같은 값으로 화면도 막는다.
//  · 받기: 서버 state 의 `reactions`(최근 10초) 가운데 **처음 보는 것만** 말풍선으로 낸다 — 보이는 2.5초는 받은 때부터
//    (폴링 간격이 몇 초여도 말풍선이 안 사라지게). 처음 볼 때 6초보다 오래된 것(창을 늦게 연 경우)은 그리지 않는다.
//  · 내 것: 누르는 즉시 내 자리 말풍선을 내고, 서버 메아리(같은 자리·같은 키, 10초 안)는 한 번 삼킨다.
//    `mahjong_react` ok 응답엔 state 가 없어(실응답 — 픽스처 `mahjong_react__ok`) 메아리는 다음 state 에서 온다.
//  · 큐브 코어(`RummyStore.reactionFeed`)와 같은 규칙이지만 마작 스토어에는 그 칸이 없어 **화면 쪽 공급기**로 둔다
//    (창 루트 `MahjongPanel` 이 창 수명 동안 하나를 쥔다). 그리기는 큐브 덮개 그대로 — 자리 카드에 앵커를 단다.

@MainActor
@Observable
final class MahjongReactionFeed {
    /// 서버 쿨다운(`mahjong_react` too_fast)과 같은 값.
    static let cooldownSeconds: TimeInterval = 2
    /// 서버 state 가 싣는 반응의 창(최근 10초) — 내 메아리를 기다리는 한도.
    static let echoSeconds: TimeInterval = 10
    /// 처음 볼 때 이보다 오래된 반응은 그리지 않는다(창을 늦게 열었을 때 지난 말풍선이 한꺼번에 뜨지 않게).
    static let staleSeconds: TimeInterval = 6
    /// 들고 있을 말풍선 수 상한.
    static let limit = 12

    private(set) var bubbles: [RummyReactionBubble] = []
    @ObservationIgnored private var matchID: String?
    @ObservationIgnored private var seenKeys = Set<String>()
    @ObservationIgnored private var pendingOwn: [(key: String, at: Date)] = []
    @ObservationIgnored private var lastSentAt = Date.distantPast
    @ObservationIgnored private var serial = 0

    init() {}

    func canSend(now: Date) -> Bool { now.timeIntervalSince(lastSentAt) >= Self.cooldownSeconds }

    /// 내 반응 — 쿨다운 안이면 false(아무것도 안 한다). 참이면 내 말풍선을 바로 내고 메아리를 기다린다.
    @discardableResult
    func noteSent(_ sticker: AingSticker, seat: Int, matchID: String, now: Date) -> Bool {
        guard canSend(now: now) else { return false }
        adopt(matchID)
        lastSentAt = now
        pendingOwn.append((sticker.rawValue, now))
        emit(seat: seat, sticker: sticker, isMine: true, at: now)
        return true
    }

    /// state 의 `reactions` 를 먹인다(오래된 것부터). 모르는 키·자리 없는 줄은 버린다. 판이 바뀌면 처음부터.
    func ingest(_ payload: MahjongStatePayload, now: Date, serverOffset: TimeInterval) {
        guard let id = payload.match?.id else { return }
        adopt(id)
        pendingOwn.removeAll { now.timeIntervalSince($0.at) > Self.echoSeconds }
        let mine = payload.mySeat
        let rows = (payload.reactions ?? []).sorted { ($0.atMs ?? 0) < ($1.atMs ?? 0) }
        for row in rows {
            guard let seat = row.seatNo, let sticker = row.sticker else { continue }
            let key = "\(seat)#\(sticker.rawValue)#\(Int64(row.atMs ?? 0))"
            guard seenKeys.insert(key).inserted else { continue }
            if let at = row.atMs, now.timeIntervalSince(Date(timeIntervalSince1970: at / 1_000 + serverOffset)) > Self.staleSeconds {
                continue
            }
            if seat == mine, let index = pendingOwn.firstIndex(where: { $0.key == sticker.rawValue }) {
                pendingOwn.remove(at: index)
                continue
            }
            emit(seat: seat, sticker: sticker, isMine: seat == mine, at: now)
        }
    }

    private func adopt(_ id: String) {
        guard id != matchID else { return }
        matchID = id
        seenKeys = []
        pendingOwn = []
        bubbles = []
    }

    private func emit(seat: Int, sticker: AingSticker, isMine: Bool, at: Date) {
        serial &+= 1
        var next = bubbles
        next.append(RummyReactionBubble(id: serial, seatNo: seat, sticker: sticker, isMine: isMine, receivedAt: at))
        if next.count > Self.limit { next.removeFirst(next.count - Self.limit) }
        bubbles = next
    }
}

/// 마작 방위 → 큐브 덮개의 방위(앵커가 없을 때의 기본 자리 — 자리 카드에 앵커를 달아 보통은 안 쓴다).
enum MahjongReactionCompass {
    static func of(seat: Int, mySeat: Int) -> RummySeatCompass {
        switch MahjongSeatCompass.of(seat: seat, mySeat: mySeat) {
        case .bottom: .bottom
        case .left: .left
        case .top: .top
        case .right: .right
        }
    }

    /// 자리 카드에서 말풍선이 설 쪽 — 위 카드는 아래로(판 안쪽), 옆 카드는 판 쪽, 내 카드는 위.
    static func edge(_ compass: MahjongCompass) -> Edge {
        switch compass {
        case .bottom: .top
        case .left: .trailing
        case .top: .bottom
        case .right: .leading
        }
    }
}

extension MahjongText {
    static let reactionButton = "반응"
}

/// [반응] — 얼굴 아이콘 하나. 누르면 이모티콘 여섯, 고르면 보내고 닫는다(쿨다운 안이면 아무것도 안 한다).
struct MahjongReactionButton: View {
    let store: MahjongStore
    let feed: MahjongReactionFeed
    let payload: MahjongStatePayload

    @State private var picking = false

    var body: some View {
        Button { picking.toggle() } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(CheckTheme.secondaryText.opacity(0.14)))
                .overlay(Capsule().stroke(CheckTheme.secondaryText.opacity(0.5), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MahjongText.reactionButton)
        .checkTooltip(MahjongText.reactionButton)
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            RummyReactionPicker { sticker in
                picking = false
                guard let seat = payload.mySeat, let id = payload.match?.id,
                      feed.noteSent(sticker, seat: seat, matchID: id, now: store.clock()) else { return }
                Task { await store.sendReaction(sticker.rawValue) }
            }
        }
    }
}
