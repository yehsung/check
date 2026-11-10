// 1:1 대기방 — 맥 여섯 1:1 게임 로비의 왼쪽 열 맨 위 탭 [방 | 상대 고르기](대표 #d_xydpun7g29KO 추천안: 방은 로비 맨 위,
// 도전은 '사람' 탭으로). 방 탭: [방 만들기](판돈 3·5·10) · 내 방(닫기) · 기다리는 방(참가). 문이 닫혀 있으면 탭 없이 원래 열 그대로.
//
// 스토어는 앱에 하나(`DuelRoomsHub.store` — WorkTimerStore 가 넣는다). 창 여섯이 같은 스토어를 본다: 내 방은 어느 게임이든 하나다.
import CheckCore
import SwiftUI

@MainActor
enum DuelRoomsHub {
    /// 앱의 방 스토어(WorkTimerStore 가 만든다 · 렌더 시험이 바꿔 끼운다). nil 이면 방 탭을 그리지 않는다.
    static var store: DuelRoomStore?
}

enum DuelLobbyTab: Hashable { case rooms, people }

/// 로비 왼쪽 열을 감싼다 — 방 문이 열려 있으면 [방 · N | 상대 고르기] 탭을 세우고, 아니면 `people` 그대로.
/// (테트리스 · 길건너는 원래 왼쪽 열에 [상대 고르기 | 순위] 탭이 있어 그 줄에 '방' 탭을 더한다 — `DuelRoomsTab` 을 쓴다.)
struct DuelRoomsLobbyColumn<People: View>: View {
    let game: DuelRoomGame
    var store: DuelRoomStore? = DuelRoomsHub.store
    /// 렌더 시험 전용 — 처음 탭.
    var initialTab: DuelLobbyTab = .rooms
    /// 렌더 시험은 부르지 않는다(시험 스토어에 값을 심는다).
    var loadsRooms = true
    @ViewBuilder let people: () -> People
    @State private var tab: DuelLobbyTab?

    var body: some View {
        if let store, store.doorOpen == true {
            VStack(alignment: .leading, spacing: 10) {
                DuelLobbyTabHeader(selection: Binding(get: { tab ?? initialTab }, set: { tab = $0 }),
                                   roomCount: store.rooms(for: game).count)
                switch tab ?? initialTab {
                case .rooms:
                    DuelRoomsTab(store: store, game: game, loadsRooms: loadsRooms)
                case .people:
                    people()
                }
            }
        } else {
            people()
                .task(id: loadsRooms) {
                    // 문을 아직 모르면 한 번 물어본다(열려 있으면 탭이 선다).
                    guard loadsRooms, let store, store.doorOpen == nil else { return }
                    await store.refresh(game)
                }
        }
    }
}

/// 방 탭 하나(본문 + 로비가 보이는 동안 15초마다 목록).
struct DuelRoomsTab: View {
    let store: DuelRoomStore
    let game: DuelRoomGame
    var loadsRooms = true
    var initiallyCreating = false

    var body: some View {
        DuelRoomsPane(store: store, game: game, rubyBalance: store.rubyBalance, initiallyCreating: initiallyCreating)
            .task(id: loadsRooms) {
                guard loadsRooms else { return }
                while !Task.isCancelled {
                    await store.refresh(game)
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
    }
}

/// 방 탭이 설 수 있나(테트리스 · 길건너 탭 줄이 묻는다).
@MainActor
func duelRoomsTabAvailable(_ store: DuelRoomStore? = DuelRoomsHub.store) -> Bool { store?.doorOpen == true }

struct DuelLobbyTabHeader: View {
    @Binding var selection: DuelLobbyTab
    let roomCount: Int

    var body: some View {
        HStack(spacing: 6) {
            DuelLobbyTabChip(title: roomCount > 0 ? "\(DuelRoomText.tabRooms) \(roomCount)" : DuelRoomText.tabRooms,
                             icon: "door.left.hand.open", isOn: selection == .rooms) { selection = .rooms }
            DuelLobbyTabChip(title: DuelRoomText.tabPeople, icon: "person.2.fill", isOn: selection == .people) {
                selection = .people
            }
            Spacer(minLength: 4)
        }
        .frame(height: 30)
    }
}

/// 로비 탭 칩 — 테트리스 · 길건너 로비 탭과 같은 모양(캡션 굵게 · 켜지면 강조색 글자와 옅은 강조 바탕).
struct DuelLobbyTabChip: View {
    let title: String
    let icon: String
    let isOn: Bool
    var height: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isOn ? CheckTheme.accent : CheckTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: height)
                .background(Capsule().fill(isOn ? CheckTheme.accent.opacity(0.20) : Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(isOn ? CheckTheme.accent.opacity(0.55) : CheckTheme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 방 탭 본문.
struct DuelRoomsPane: View {
    let store: DuelRoomStore
    let game: DuelRoomGame
    let rubyBalance: Int?
    /// 렌더 시험 전용 — 방 만들기 줄을 펼친 채로.
    var initiallyCreating = false
    @State private var creating: Bool?

    private var isCreating: Bool { creating ?? initiallyCreating }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let mine = store.myOpenRoom(for: game) {
                DuelMyRoomCard(store: store, room: mine)
            } else if let other = store.myOpenRoom(otherThan: game), let otherGame = other.game {
                HStack(spacing: 8) {
                    Image(systemName: "door.left.hand.open").foregroundStyle(CheckTheme.accent)
                    Text(DuelRoomText.otherGameRoom(otherGame)).font(.caption).foregroundStyle(CheckTheme.secondaryText)
                    Spacer(minLength: 6)
                    ChessActionButton(title: DuelRoomText.closeRoom, height: 26, isEnabled: !store.isBusy) {
                        Task { await store.closeMyRoom() }
                    }
                }
                .padding(.horizontal, 12).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
            } else if isCreating {
                DuelCreateRoomCard(store: store, game: game, rubyBalance: rubyBalance) { creating = false }
            } else {
                Button { creating = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        Text(DuelRoomText.create).font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
            }
            if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(CheckTheme.pending).lineLimit(2)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(DuelRoomText.roomsTitle).font(.headline)
                Spacer()
            }
            let rooms = store.rooms(for: game)
            if rooms.isEmpty {
                Text(store.loadedGames.contains(game) ? DuelRoomText.emptyRooms : DuelRoomText.loading)
                    .font(.caption).foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(rooms) { room in
                        DuelRoomRow(room: room, waited: store.waitedSeconds(room),
                                    affordable: (rubyBalance ?? Int.max) >= room.stake,
                                    isEnabled: !store.isBusy && store.myOpenRoom(for: game) == nil) {
                            Task { await store.join(room) }
                        }
                        .frame(height: 56)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DuelRoomRow: View {
    let room: DuelRoom
    let waited: Int
    let affordable: Bool
    let isEnabled: Bool
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: room.host?.displayName ?? "사용자", userID: room.host?.userID ?? room.id,
                            avatarURL: room.host?.avatarURL.flatMap(URL.init(string:)), size: 34,
                            characterHint: room.host?.character)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.host?.displayName ?? "사용자").font(.callout.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    RubyIcon(size: 11)
                    Text("\(room.stake) · \(DuelRoomText.waiting(seconds: waited))")
                        .font(.caption2).foregroundStyle(CheckTheme.secondaryText).monospacedDigit().lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ChessActionButton(title: affordable ? DuelRoomText.join : DuelRoomText.notEnough, height: 28,
                              isEnabled: affordable && isEnabled, action: onJoin)
                .accessibilityLabel("\(room.host?.displayName ?? "사용자")님 방에 \(DuelRoomText.join)")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

struct DuelMyRoomCard: View {
    let store: DuelRoomStore
    let room: DuelRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(DuelRoomText.myRoomTitle).font(.headline)
                HStack(spacing: 4) {
                    RubyIcon(size: 12)
                    Text(DuelRoomText.stakeLine(room.stake)).font(.caption.weight(.semibold)).monospacedDigit()
                }
                Spacer(minLength: 6)
                ChessActionButton(title: DuelRoomText.closeRoom, height: 26, isEnabled: !store.isBusy) {
                    Task { await store.closeMyRoom() }
                }
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("\(DuelRoomText.waiting(seconds: store.waitedSeconds(room))) · \(DuelRoomText.myRoomHint)")
                    .font(.caption2).foregroundStyle(CheckTheme.secondaryText).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CheckTheme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.accent.opacity(0.55), lineWidth: 1))
    }
}

struct DuelCreateRoomCard: View {
    let store: DuelRoomStore
    let game: DuelRoomGame
    let rubyBalance: Int?
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DuelRoomText.createTitle).font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(CheckTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("방 만들기 닫기")
            }
            Text(DuelRoomText.createHint).font(.caption2).foregroundStyle(CheckTheme.secondaryText).lineLimit(2)
            HStack(spacing: 6) {
                Text(DuelRoomText.stakeLabel).font(.caption).foregroundStyle(CheckTheme.secondaryText)
                ForEach(store.stakes, id: \.self) { stake in
                    let affordable = (rubyBalance ?? Int.max) >= stake
                    Button { store.selectedStake = stake } label: {
                        HStack(spacing: 3) {
                            RubyIcon(size: 10)
                            Text("\(stake)").font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        .padding(.horizontal, 10).frame(height: 28)
                        .foregroundStyle(affordable ? CheckTheme.primaryText : CheckTheme.secondaryText)
                        .background(RoundedRectangle(cornerRadius: 8).fill(store.selectedStake == stake
                                                                            ? CheckTheme.accent.opacity(0.25) : Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(store.selectedStake == stake ? CheckTheme.accent : CheckTheme.border,
                                                                          lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!affordable)
                }
                Spacer(minLength: 6)
                ChessActionButton(title: DuelRoomText.createButton, height: 28,
                                  isEnabled: !store.isBusy && (rubyBalance ?? Int.max) >= store.selectedStake) {
                    Task { await store.open(game, stake: store.selectedStake) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}
