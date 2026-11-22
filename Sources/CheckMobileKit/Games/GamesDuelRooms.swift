import CheckCore
import Foundation

// MARK: - 1:1 대기방(폰 1.0.19 — 맥 0.3.83 `DuelRoomsLobby` 의 폰 짝 · 대표 #d_xygj8oZRFlfH 1번 · 맥 결정 #d_xydpun7g29KO "추천안대로")
//
// 방 = 상대를 정하지 않은 신청. 방장이 판돈을 골라 열면 그 게임 로비 '기다리는 방'에 뜨고, 누구든 [참가]하면 서버가 한 트랜잭션에서
// 그 게임의 신청 + 수락으로 판을 세운다 — 판돈 · 정산 · 전적 · 대국 중 판정은 각 게임 것 그대로다. 상태 · 판정은 전부 코어
// `DuelRoomStore`(맥과 한 벌)다. 이 파일은 로비에 끼우는 절 하나(그리기 · 누름)와 순수 판정 둘이다.
//
// 맥과 다른 배치 하나: 맥은 로비 왼쪽 열 맨 위 탭 [방 | 상대 고르기]다. 폰 로비는 세로 한 줄이라 탭 대신 **절**로 둔다 —
// 받은 신청 · 보낸 신청(시간이 흐르는 것) 바로 아래, 상대 고르기 위. 문이 닫혀 있으면(서버 문 · 함수 없음) 절이 아예 없다.
// 부르는 자리: 로비가 보이는 동안 처음 한 번 + 문이 열려 있으면 15초마다 목록(맥과 같은 주기) · [방 만들기] · [닫기] · [참가].
// 방장 숨(20초)은 코어가 방이 열려 있는 동안 화면과 상관없이 쉰다 — 판이 서면 그 게임 스토어가 판을 받아 화면을 연다(`MobileAppModel`).

/// 대기방 절의 순수 판정(시험이 값으로 잰다).
package enum GamesDuelRoomsRules {
    /// 목록을 다시 읽는 주기(초) — 맥 `DuelRoomsTab` 과 같은 15초.
    package static let refreshSeconds: TimeInterval = 15

    /// 이 방에 들어갈 루비가 있는가(잔액을 모르면 막지 않는다 — 서버가 다시 잰다).
    package static func affordable(stake: Int, balance: Int?) -> Bool { (balance ?? Int.max) >= stake }

    /// [참가]를 누를 수 있는가: 루비 · 걸린 일 없음 · 이 게임에 내 방이 열려 있지 않음.
    @MainActor package static func canJoin(_ room: DuelRoom, store: DuelRoomStore, game: DuelRoomGame) -> Bool {
        affordable(stake: room.stake, balance: store.rubyBalance) && !store.isBusy && store.myOpenRoom(for: game) == nil
    }
}

#if os(iOS)
import SwiftUI

/// 로비에 끼우는 '기다리는 방' 절. 문이 열려 있을 때만 그린다(닫혔거나 모르면 빈 자리 — 처음 한 번 묻는다).
struct GamesDuelRoomsSection: View {
    let store: DuelRoomStore
    let game: DuelRoomGame
    /// 부모 VStack 이 간격을 이미 준다(길건너 · 알까기 로비) — 위 여백을 덧대지 않는다.
    var parentSpaced = false
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            if store.doorOpen == true {
                content
            }
        }
        .padding(.top, store.doorOpen == true && !parentSpaced ? MobileTheme.rowSpacing : 0)
        .task(id: game) { await poll() }
    }

    /// 처음 한 번 묻고, 문이 열려 있는 동안 15초마다 목록을 다시 읽는다(화면이 사라지면 작업이 끝난다).
    private func poll() async {
        await store.refresh(game)
        while !Task.isCancelled, store.doorOpen == true {
            do { try await Task.sleep(for: .seconds(GamesDuelRoomsRules.refreshSeconds)) } catch { return }
            await store.refresh(game)
        }
    }

    @ViewBuilder
    private var content: some View {
        let rooms = store.rooms(for: game)
        SectionHeader(DuelRoomText.roomsTitle, trailing: rooms.isEmpty ? .none : .text("\(rooms.count)"), padded: !parentSpaced)
        InsetGroup {
            if let mine = store.myOpenRoom(for: game) {
                myRoomRow(mine)
            } else if let other = store.myOpenRoom(otherThan: game), let otherGame = other.game {
                GroupRow(divider: .inset(MobileTheme.cardPadding)) {
                    Image(systemName: "door.left.hand.open").foregroundStyle(MobileTheme.accent)
                    Text(DuelRoomText.otherGameRoom(otherGame))
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                    Spacer(minLength: 6)
                    AingButton(DuelRoomText.closeRoom, kind: .gray, size: .sm) { Task { await store.closeMyRoom() } }
                        .disabled(store.isBusy)
                        .fixedSize()
                }
            } else if creating {
                createRow
            } else {
                GroupRow(divider: .inset(MobileTheme.cardPadding)) {
                    AingButton(DuelRoomText.create, systemImage: "plus", kind: .filled, size: .md, fillsWidth: true) { creating = true }
                        .disabled(store.isBusy)
                }
            }
            if let notice = store.notice {
                GroupRow(divider: .inset(MobileTheme.cardPadding), minHeight: 36) {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.pending)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if rooms.isEmpty {
                GroupRow(divider: .none, minHeight: 44) {
                    Text(store.loadedGames.contains(game) ? DuelRoomText.emptyRooms : DuelRoomText.loading)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    roomRow(room, isLast: index == rooms.count - 1)
                }
            }
        }
    }

    private func myRoomRow(_ room: DuelRoom) -> some View {
        GroupRow(divider: .inset(MobileTheme.cardPadding), isHighlighted: true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(DuelRoomText.myRoomTitle).font(.subheadline.weight(.semibold))
                    RubyIcon(size: 13)
                    Text(DuelRoomText.stakeLine(room.stake))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(DuelRoomText.waiting(seconds: store.waitedSeconds(room))) · \(DuelRoomText.myRoomHint)")
                        .font(.caption)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            AingButton(DuelRoomText.closeRoom, kind: .gray, size: .sm) { Task { await store.closeMyRoom() } }
                .disabled(store.isBusy)
                .fixedSize()
        }
    }

    private var createRow: some View {
        GroupRow(divider: .inset(MobileTheme.cardPadding)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(DuelRoomText.createTitle).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { creating = false } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(MobileTheme.label2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("방 만들기 닫기"))
                }
                Text(DuelRoomText.createHint)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(DuelRoomText.stakeLabel).font(.footnote).foregroundStyle(MobileTheme.label2)
                    ForEach(store.stakes, id: \.self) { stake in
                        let affordable = GamesDuelRoomsRules.affordable(stake: stake, balance: store.rubyBalance)
                        Button { store.selectedStake = stake } label: {
                            HStack(spacing: 3) {
                                RubyIcon(size: 12)
                                Text("\(stake)").font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(affordable ? MobileTheme.label : MobileTheme.label3)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(store.selectedStake == stake ? MobileTheme.accentTint : MobileTheme.fill))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(store.selectedStake == stake ? MobileTheme.accent : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(!affordable)
                        .accessibilityAddTraits(store.selectedStake == stake ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                AingButton(DuelRoomText.createButton, kind: .filled, size: .md, fillsWidth: true, isBusy: store.isBusy) {
                    Task {
                        await store.open(game, stake: store.selectedStake)
                        if store.myOpenRoom(for: game) != nil { creating = false }
                    }
                }
                .disabled(store.isBusy || !GamesDuelRoomsRules.affordable(stake: store.selectedStake, balance: store.rubyBalance))
            }
        }
    }

    private func roomRow(_ room: DuelRoom, isLast: Bool) -> some View {
        let name = room.host?.displayName ?? "사용자"
        let affordable = GamesDuelRoomsRules.affordable(stake: room.stake, balance: store.rubyBalance)
        return GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 40 + 12), minHeight: 60) {
            PersonAvatar(name: name, url: room.host?.avatarURL.flatMap(URL.init(string:)), userID: room.host?.userID, size: 40,
                         characterHint: room.host?.character)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    RubyIcon(size: 12)
                    Text("\(room.stake) · \(DuelRoomText.waiting(seconds: store.waitedSeconds(room)))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AingButton(affordable ? DuelRoomText.join : DuelRoomText.notEnough, kind: .tinted, size: .sm) {
                Task { await store.join(room) }
            }
            .disabled(!GamesDuelRoomsRules.canJoin(room, store: store, game: game))
            .fixedSize()
            .accessibilityLabel(Text("\(name)님 방에 \(DuelRoomText.join)"))
        }
    }
}
#endif
